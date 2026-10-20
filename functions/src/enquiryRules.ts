// Validation for the public website forms (employer registration and contact).
// Pure: no Firebase imports, unit-tested in enquiryRules.test.ts.

import { DEFAULT_INDUSTRIES } from "./industries";

export type EnquiryType = "employer_registration" | "contact";

export interface CleanEnquiry {
  type: EnquiryType;
  fields: Record<string, string | number | boolean>;
}

export type EnquiryResult =
  | { ok: true; enquiry: CleanEnquiry }
  | { ok: false; error: string }
  | { ok: "spam" };

const EMAIL = /^[^\s@<>()[\]\\,;:"]+@[^\s@<>()[\]\\,;:"]+\.[^\s@<>()[\]\\,;:"]{2,}$/;
const PHONE = /^[0-9+()\-.\s]{6,25}$/;
// Control characters (other than tab, newline, carriage return) and angle brackets
// have no place in these fields.
function hasBadChars(value: string): boolean {
  for (let i = 0; i < value.length; i++) {
    const code = value.charCodeAt(i);
    if (code === 60 || code === 62) return true; // < >
    if (code < 32 && code !== 9 && code !== 10 && code !== 13) return true;
  }
  return false;
}

function text(
  raw: unknown,
  label: string,
  opts: { required?: boolean; max: number; min?: number; multiline?: boolean },
): { value: string } | { error: string } {
  if (raw === undefined || raw === null || raw === "") {
    return opts.required ? { error: `${label} is required.` } : { value: "" };
  }
  if (typeof raw !== "string") return { error: `${label} is not valid.` };
  const value = opts.multiline ? raw.trim() : raw.replace(/\s+/g, " ").trim();
  if (opts.required && value.length === 0) return { error: `${label} is required.` };
  if (value.length > opts.max) return { error: `${label} must be ${opts.max} characters or fewer.` };
  if (opts.min && value.length < opts.min) return { error: `${label} must be at least ${opts.min} characters.` };
  if (hasBadChars(value)) return { error: `${label} contains characters that are not allowed.` };
  return { value };
}

/**
 * `industries` is what the registration form's Industry dropdown offers
 * (see industries.ts); a submitted industry must be one of them.
 */
export function validateEnquiry(body: unknown, industries: readonly string[] = DEFAULT_INDUSTRIES): EnquiryResult {
  if (typeof body !== "object" || body === null || Array.isArray(body)) {
    return { ok: false, error: "Invalid request." };
  }
  const b = body as Record<string, unknown>;

  // Honeypot: a hidden field real visitors never fill in.
  if (typeof b.website === "string" && b.website.trim() !== "") return { ok: "spam" };

  const type = b.type;
  if (type !== "employer_registration" && type !== "contact") {
    return { ok: false, error: "Unknown form type." };
  }

  const out: Record<string, string | number | boolean> = {};
  const take = (
    key: string,
    label: string,
    opts: Parameters<typeof text>[2],
    check?: (v: string) => string | null,
  ): string | null => {
    const r = text(b[key], label, opts);
    if ("error" in r) return r.error;
    if (r.value && check) {
      const problem = check(r.value);
      if (problem) return problem;
    }
    if (r.value) out[key] = r.value;
    return null;
  };
  const emailCheck = (v: string) => (EMAIL.test(v) ? null : "Enter a valid email address.");
  const phoneCheck = (v: string) => (PHONE.test(v) ? null : "Enter a valid phone number.");

  const problems: Array<string | null> = [];

  if (type === "employer_registration") {
    problems.push(
      take("companyName", "Company name", { required: true, max: 120, min: 2 }),
      take("contactName", "Your name", { required: true, max: 100, min: 2 }),
      take("jobTitle", "Job title", { max: 100 }),
      take("contactEmail", "Work email", { required: true, max: 160 }, emailCheck),
      take("contactPhone", "Phone number", { required: true, max: 25 }, phoneCheck),
      take("industry", "Industry", { max: 100 }, (v) =>
        industries.includes(v) ? null : "Choose an industry from the list. Please reload the page and try again.",
      ),
      take("payFrequency", "Pay frequency", { max: 40 }),
      take("message", "Message", { max: 1500, multiline: true }),
    );
    const count = Number(b.employeeCount);
    if (!Number.isInteger(count) || count < 1 || count > 1_000_000) {
      problems.push("Enter the number of employees (a whole number of 1 or more).");
    } else {
      out.employeeCount = count;
    }
    if (b.consent !== true) {
      problems.push("Please confirm that we may contact you about your registration.");
    } else {
      out.consent = true;
    }
  } else {
    problems.push(
      take("name", "Your name", { required: true, max: 100, min: 2 }),
      take("email", "Email", { required: true, max: 160 }, emailCheck),
      take("phone", "Phone number", { max: 25 }, phoneCheck),
      take("topic", "Topic", { max: 60 }),
      take("message", "Message", { required: true, max: 1500, min: 10, multiline: true }),
    );
  }

  const first = problems.find((p): p is string => typeof p === "string");
  if (first) return { ok: false, error: first };
  return { ok: true, enquiry: { type, fields: out } };
}

/** Allowed submissions per source per hour before further ones are refused. */
export const ENQUIRY_LIMIT_PER_HOUR = 5;

/** Hour bucket for the rate limit, e.g. "2026102016". */
export function hourBucket(ms: number): string {
  const d = new Date(ms);
  const p = (n: number) => String(n).padStart(2, "0");
  return `${d.getUTCFullYear()}${p(d.getUTCMonth() + 1)}${p(d.getUTCDate())}${p(d.getUTCHours())}`;
}
