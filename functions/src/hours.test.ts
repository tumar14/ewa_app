import { test } from "node:test";
import assert from "node:assert/strict";
import { accruedMinor } from "./drawRules";
import { DEFAULT_MAX_SHIFT_HOURS, countableSpans, parseHoursPolicy } from "./hours";

const H = 3_600_000;
const T0 = Date.parse("2026-10-15T06:00:00Z");
const day = { maxShiftMs: DEFAULT_MAX_SHIFT_HOURS * H };

test("overlapping records are counted once", () => {
  // Three records for the same 8 hours (a worker opening several sessions at once).
  const spans = [0, 1, 2].map(() => ({ clockInMs: T0, clockOutMs: T0 + 8 * H }));
  assert.equal(accruedMinor(50, spans, T0 + 9 * H, day.maxShiftMs), 40_000);
});

test("partly overlapping records add only the extra time", () => {
  const spans = [
    { clockInMs: T0, clockOutMs: T0 + 6 * H },
    { clockInMs: T0 + 4 * H, clockOutMs: T0 + 8 * H },
  ];
  assert.equal(accruedMinor(50, spans, T0 + 9 * H, day.maxShiftMs), 40_000); // 8h, not 10h
});

test("separate records still add up", () => {
  const spans = [
    { clockInMs: T0, clockOutMs: T0 + 4 * H },
    { clockInMs: T0 + 5 * H, clockOutMs: T0 + 9 * H },
  ];
  assert.equal(accruedMinor(50, spans, T0 + 10 * H, day.maxShiftMs), 40_000);
});

test("one record is capped at the longest shift, so a forgotten clock-out cannot run on", () => {
  const open = [{ clockInMs: T0, clockOutMs: null }];
  assert.equal(accruedMinor(50, open, T0 + 100 * H, day.maxShiftMs), 14 * 50 * 100);
  const closed = [{ clockInMs: T0, clockOutMs: T0 + 60 * H }];
  assert.equal(accruedMinor(50, closed, T0 + 100 * H, day.maxShiftMs), 14 * 50 * 100);
});

test("time that has not happened yet is not counted", () => {
  assert.equal(accruedMinor(50, [{ clockInMs: T0 + 5 * H, clockOutMs: T0 + 13 * H }], T0 + 2 * H, day.maxShiftMs), 0);
  assert.equal(accruedMinor(50, [{ clockInMs: T0, clockOutMs: T0 + 10 * H }], T0 + 4 * H, day.maxShiftMs), 20_000);
});

test("a record that ends before it starts counts for nothing", () => {
  assert.equal(accruedMinor(50, [{ clockInMs: T0 + 8 * H, clockOutMs: T0 }], T0 + 9 * H, day.maxShiftMs), 0);
});

test("without a cap the old behaviour is unchanged", () => {
  assert.equal(accruedMinor(50, [{ clockInMs: T0, clockOutMs: T0 + 20 * H }], T0 + 30 * H), 100_000);
});

test("the policy reads settings and falls back to safe values", () => {
  assert.equal(parseHoursPolicy({}).maxShiftMs, 14 * H);
  assert.equal(parseHoursPolicy({ maxShiftHours: 10 }).maxShiftMs, 10 * H);
  for (const bad of [0, -3, 25, NaN, "x", null]) {
    assert.equal(parseHoursPolicy({ maxShiftHours: bad }).maxShiftMs, 14 * H, String(bad));
  }
  assert.equal(parseHoursPolicy({}).countOnlyReviewed, false);
  assert.equal(parseHoursPolicy({ countOnlyReviewedHours: true }).countOnlyReviewed, true);
  assert.equal(parseHoursPolicy({ countOnlyReviewedHours: "yes" }).countOnlyReviewed, false);
});

test("voided records never count", () => {
  const docs = [
    { clockInMs: T0, clockOutMs: T0 + H, voided: true },
    { clockInMs: T0 + 2 * H, clockOutMs: T0 + 3 * H },
  ];
  assert.equal(countableSpans(docs, { ...day, countOnlyReviewed: false }).length, 1);
});

test("when sign-off is required, only signed-off records count, and open ones never do", () => {
  const docs = [
    { clockInMs: T0, clockOutMs: T0 + 8 * H, reviewedAtMs: T0 + 9 * H },
    { clockInMs: T0 + 24 * H, clockOutMs: T0 + 32 * H },
    { clockInMs: T0 + 48 * H, clockOutMs: null },
  ];
  assert.equal(countableSpans(docs, { ...day, countOnlyReviewed: true }).length, 1);
  assert.equal(countableSpans(docs, { ...day, countOnlyReviewed: false }).length, 3);
});
