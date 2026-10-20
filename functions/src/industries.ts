// The industries offered on the website's employer-registration form. The
// platform admin edits the list (platform_config/website); these are used until
// they do. No Firebase imports: unit-tested in industries.test.ts, and mirrored
// by lib/models/platform_config.dart.

export const INDUSTRY_OTHER = "Other";
export const MAX_INDUSTRIES = 50;
export const MAX_INDUSTRY_LENGTH = 100;

export const DEFAULT_INDUSTRIES: readonly string[] = [
  "Garment and textile manufacturing",
  "Other manufacturing",
  "Agriculture and agro-processing",
  "Retail and wholesale",
  "Hospitality and tourism",
  "Construction",
  "Mining and quarrying",
  "Transport and logistics",
  "Security services",
  "Health care",
  "Education",
  "Financial services",
  "Public sector",
  INDUSTRY_OTHER,
];

function isUnsafe(value: string): boolean {
  for (let i = 0; i < value.length; i++) {
    const code = value.charCodeAt(i);
    if (code === 60 || code === 62 || code < 32) return true; // < > and control characters
  }
  return false;
}

/** Cleans a stored list: trimmed, single-spaced, no duplicates, nothing unsafe. Returns null if nothing usable. */
export function cleanIndustries(raw: unknown): string[] | null {
  if (!Array.isArray(raw)) return null;
  const seen = new Set<string>();
  const out: string[] = [];
  for (const item of raw) {
    if (typeof item !== "string") continue;
    const value = item.replace(/\s+/g, " ").trim();
    if (value.length === 0 || value.length > MAX_INDUSTRY_LENGTH) continue;
    if (isUnsafe(value)) continue;
    const key = value.toLowerCase();
    if (seen.has(key)) continue;
    seen.add(key);
    out.push(value);
    if (out.length === MAX_INDUSTRIES) break;
  }
  return out.length > 0 ? out : null;
}

/** What a submission may choose: the configured list (or the defaults) plus "Other". */
export function allowedIndustries(configured: unknown): string[] {
  const list = cleanIndustries(configured) ?? [...DEFAULT_INDUSTRIES];
  return list.some((i) => i.toLowerCase() === INDUSTRY_OTHER.toLowerCase()) ? list : [...list, INDUSTRY_OTHER];
}
