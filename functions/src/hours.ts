// Which recorded time counts towards earned wages. No Firebase imports: unit-tested in
// hours.test.ts. Time records come from phones, kiosks, uploads and manual edits, so
// the server never trusts them as written: overlaps are merged, one shift has a ceiling,
// voided records are ignored, and a company can insist on supervisor sign-off first.

import { SessionSpan } from "./drawRules";

export const DEFAULT_MAX_SHIFT_HOURS = 14;
export const MIN_SHIFT_HOURS = 1;
export const MAX_SHIFT_HOURS_LIMIT = 24;

export interface HoursPolicy {
  /** No single record counts for longer than this. Also catches a forgotten clock-out. */
  maxShiftMs: number;
  /** Only records a supervisor has signed off count. */
  countOnlyReviewed: boolean;
}

export function parseHoursPolicy(settings: Record<string, unknown>): HoursPolicy {
  const raw = Number(settings.maxShiftHours);
  const hours = Number.isFinite(raw) && raw >= MIN_SHIFT_HOURS && raw <= MAX_SHIFT_HOURS_LIMIT ? raw : DEFAULT_MAX_SHIFT_HOURS;
  return { maxShiftMs: hours * 3_600_000, countOnlyReviewed: settings.countOnlyReviewedHours === true };
}

export interface SessionDocLite {
  clockInMs: number;
  clockOutMs: number | null;
  voided?: unknown;
  reviewedAtMs?: number | null;
}

/** The records that may count, as spans. Unreviewed and voided ones are dropped here. */
export function countableSpans(docs: readonly SessionDocLite[], policy: HoursPolicy): SessionSpan[] {
  return docs
    .filter((d) => d.voided !== true)
    .filter((d) => !policy.countOnlyReviewed || (typeof d.reviewedAtMs === "number" && d.reviewedAtMs > 0))
    .map((d) => ({ clockInMs: d.clockInMs, clockOutMs: d.clockOutMs }));
}
