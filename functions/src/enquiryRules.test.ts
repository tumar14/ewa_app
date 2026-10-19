import { test } from "node:test";
import assert from "node:assert/strict";
import { hourBucket, validateEnquiry } from "./enquiryRules";

const employer = {
  type: "employer_registration",
  companyName: "Example Garments (Pty) Ltd",
  contactName: "Thandi Dlamini",
  contactEmail: "thandi@example.co.sz",
  contactPhone: "+268 7600 0000",
  employeeCount: 250,
  consent: true,
};

test("a complete employer registration is accepted and cleaned", () => {
  const r = validateEnquiry({ ...employer, companyName: "  Example   Garments  ", message: "  Hello\nthere  " });
  assert.equal(r.ok, true);
  if (r.ok === true) {
    assert.equal(r.enquiry.type, "employer_registration");
    assert.equal(r.enquiry.fields.companyName, "Example Garments");
    assert.equal(r.enquiry.fields.message, "Hello\nthere");
    assert.equal(r.enquiry.fields.employeeCount, 250);
  }
});

test("required employer fields are enforced", () => {
  for (const key of ["companyName", "contactName", "contactEmail", "contactPhone"]) {
    const r = validateEnquiry({ ...employer, [key]: "" });
    assert.equal(r.ok, false, key);
  }
});

test("consent must be an explicit true", () => {
  assert.equal(validateEnquiry({ ...employer, consent: false }).ok, false);
  assert.equal(validateEnquiry({ ...employer, consent: "true" }).ok, false);
  const { consent: _omit, ...rest } = employer;
  assert.equal(validateEnquiry(rest).ok, false);
});

test("employee count must be a positive whole number", () => {
  for (const employeeCount of [0, -3, 2.5, "abc", NaN, 2_000_000, null]) {
    assert.equal(validateEnquiry({ ...employer, employeeCount }).ok, false, String(employeeCount));
  }
  assert.equal(validateEnquiry({ ...employer, employeeCount: "40" }).ok, true);
});

test("emails and phone numbers are checked", () => {
  for (const contactEmail of ["nope", "a@b", "a b@c.com", "<x>@y.com", "a@b.c"]) {
    assert.equal(validateEnquiry({ ...employer, contactEmail }).ok, false, contactEmail);
  }
  for (const contactPhone of ["abc", "12", "+268 <script>"]) {
    assert.equal(validateEnquiry({ ...employer, contactPhone }).ok, false, contactPhone);
  }
});

test("markup and control characters are rejected, over-long text is rejected", () => {
  assert.equal(validateEnquiry({ ...employer, companyName: "<b>Evil</b>" }).ok, false);
  assert.equal(validateEnquiry({ ...employer, message: "a" + String.fromCharCode(1) + "b" }).ok, false);
  assert.equal(validateEnquiry({ ...employer, message: "x".repeat(1501) }).ok, false);
  assert.equal(validateEnquiry({ ...employer, companyName: "x".repeat(121) }).ok, false);
});

test("non-string values for text fields are rejected", () => {
  assert.equal(validateEnquiry({ ...employer, companyName: { $gt: "" } }).ok, false);
  assert.equal(validateEnquiry({ ...employer, contactName: ["a", "b"] }).ok, false);
});

test("the honeypot silently marks a submission as spam", () => {
  assert.deepEqual(validateEnquiry({ ...employer, website: "http://spam.example" }), { ok: "spam" });
  assert.equal(validateEnquiry({ ...employer, website: "" }).ok, true);
});

test("unknown types and non-objects are rejected", () => {
  assert.equal(validateEnquiry({ type: "admin_signup" }).ok, false);
  assert.equal(validateEnquiry(null).ok, false);
  assert.equal(validateEnquiry("hi").ok, false);
  assert.equal(validateEnquiry([]).ok, false);
});

test("extra fields are dropped, so a form cannot smuggle in role or status data", () => {
  const r = validateEnquiry({ ...employer, role: "admin", platformAdmin: true, status: "approved" });
  assert.equal(r.ok, true);
  if (r.ok === true) assert.deepEqual(Object.keys(r.enquiry.fields).sort(), ["companyName", "consent", "contactEmail", "contactName", "contactPhone", "employeeCount"]);
});

test("contact form", () => {
  const ok = validateEnquiry({ type: "contact", name: "Sipho", email: "s@example.com", message: "How do fees work?" });
  assert.equal(ok.ok, true);
  assert.equal(validateEnquiry({ type: "contact", name: "Sipho", email: "s@example.com", message: "Hi" }).ok, false);
  assert.equal(validateEnquiry({ type: "contact", name: "S", email: "s@example.com", message: "A real question" }).ok, false);
});

test("hour bucket", () => {
  assert.equal(hourBucket(Date.parse("2026-10-20T16:59:59Z")), "2026102016");
  assert.equal(hourBucket(Date.parse("2026-10-20T17:00:00Z")), "2026102017");
});
