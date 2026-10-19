import { test } from "node:test";
import assert from "node:assert/strict";
import {
  DrawLimits,
  PaydayRule,
  accruedMinor,
  checkNewDraw,
  currentCycleStartMs,
  formatMinor,
  withinCap,
} from "./drawRules";

const lastDay: PaydayRule = { type: "lastDayOfMonth", dayOfMonth: 25, weekday: 5 };
const fixed25: PaydayRule = { type: "fixedDayOfMonth", dayOfMonth: 25, weekday: 5 };
const fixed31: PaydayRule = { type: "fixedDayOfMonth", dayOfMonth: 31, weekday: 5 };
const lastFriday: PaydayRule = { type: "lastWeekdayOfMonth", dayOfMonth: 25, weekday: 5 };

const iso = (ms: number) => new Date(ms).toISOString();
const at = (isoString: string) => Date.parse(isoString);

// Local (SAST, UTC+2) midnight of day D is D-1 at 22:00Z.

test("cycle start: last day of month rule, mid-cycle", () => {
  assert.equal(iso(currentCycleStartMs(lastDay, at("2026-10-15T10:00:00Z"))), "2026-09-30T22:00:00.000Z");
});

test("cycle start: payday itself still belongs to the closing cycle", () => {
  assert.equal(iso(currentCycleStartMs(lastDay, at("2026-10-31T08:00:00Z"))), "2026-09-30T22:00:00.000Z");
});

test("cycle start: 22:30Z on payday is already the next local day", () => {
  assert.equal(iso(currentCycleStartMs(lastDay, at("2026-10-31T22:30:00Z"))), "2026-10-31T22:00:00.000Z");
});

test("cycle start: January looks back to December of the previous year", () => {
  assert.equal(iso(currentCycleStartMs(lastDay, at("2026-01-10T10:00:00Z"))), "2025-12-31T22:00:00.000Z");
});

test("cycle start: fixed day of month", () => {
  assert.equal(iso(currentCycleStartMs(fixed25, at("2026-10-15T10:00:00Z"))), "2026-09-25T22:00:00.000Z");
  assert.equal(iso(currentCycleStartMs(fixed25, at("2026-10-26T10:00:00Z"))), "2026-10-25T22:00:00.000Z");
});

test("cycle start: fixed day 31 clamps to the end of a short month", () => {
  assert.equal(iso(currentCycleStartMs(fixed31, at("2026-03-05T10:00:00Z"))), "2026-02-28T22:00:00.000Z");
});

test("cycle start: last Friday of the month", () => {
  assert.equal(iso(currentCycleStartMs(lastFriday, at("2026-10-15T10:00:00Z"))), "2026-09-25T22:00:00.000Z");
});

test("accrued: closed and open sessions, whole minutes only, in cents", () => {
  const now = at("2026-10-15T12:00:30Z");
  const sessions = [
    { clockInMs: at("2026-10-15T00:00:00Z"), clockOutMs: at("2026-10-15T08:00:00Z") }, // 8h
    { clockInMs: at("2026-10-15T10:00:00Z"), clockOutMs: null }, // 2h 0m 30s open
  ];
  assert.equal(accruedMinor(50, sessions, now), 50_000); // 10h * E50, trailing 30s dropped
});

test("accrued: fractional hourly rate rounds once to the nearest cent", () => {
  const sessions = [{ clockInMs: 0, clockOutMs: 20 * 60_000 }]; // 20 minutes
  assert.equal(accruedMinor(33.33, sessions, 0), 1111); // 33.33 * 20/60 = 11.11
});

const limits = { maxDrawPercent: 0.5, maxDrawsPerCycle: 2, fee: { mode: "percent" as const, percent: 0.05 } };
const draw = (amountMinor: number, accrued: number, outstanding: number[] = [], l: DrawLimits = limits) =>
  checkNewDraw({ amountMinor, accruedMinor: accrued, limits: l, outstanding: outstanding.map((a) => ({ amountMinor: a })) });

test("draw: exactly the cap is allowed and fee is fixed", () => {
  assert.deepEqual(draw(20_000, 40_000), { ok: true, feeMinor: 1_000, totalMinor: 21_000 });
});

test("draw: one cent over the cap is rejected", () => {
  assert.equal(draw(20_001, 40_000).ok, false);
});

test("draw: prior outstanding draws reduce what remains", () => {
  assert.equal(draw(10_000, 40_000, [10_000]).ok, true);
  assert.equal(draw(10_001, 40_000, [10_000]).ok, false);
});

test("draw: per-cycle count limit", () => {
  assert.equal(draw(1_000, 400_000, [1_000, 1_000]).ok, false);
});

test("draw: zero, negative, NaN, Infinity and fractional-cent amounts are rejected", () => {
  for (const amount of [0, -5, NaN, Infinity, 10.5]) {
    assert.equal(draw(amount, 400_000).ok, false, String(amount));
  }
});

test("draw: no accrued wages means nothing can be drawn", () => {
  assert.equal(draw(1, 0).ok, false);
});

test("draw: fee is rounded to a whole cent", () => {
  assert.deepEqual(draw(3_333, 100_000), { ok: true, feeMinor: 167, totalMinor: 3_500 });
});

test("draw: cap uses the same rounding at an awkward fraction", () => {
  const thirds = { ...limits, maxDrawPercent: 0.3 };
  assert.equal(draw(3_000, 10_000, [], thirds).ok, true);
  assert.equal(draw(3_001, 10_000, [], thirds).ok, false);
});

test("withinCap and formatMinor", () => {
  assert.equal(withinCap(40_000, 0.5, 20_000), true);
  assert.equal(withinCap(40_000, 0.5, 20_001), false);
  assert.equal(formatMinor(12_345), "123.45");
});

const tiered = {
  ...limits,
  fee: { mode: "tiered" as const, tiers: [{ upToMinor: 5_000, flatMinor: 100, percent: 0 }, { upToMinor: 20_000, flatMinor: 300, percent: 0 }] },
};

test("draw: a tariff table sets the fee by band", () => {
  assert.deepEqual(draw(5_000, 100_000, [], tiered), { ok: true, feeMinor: 100, totalMinor: 5_100 });
  assert.deepEqual(draw(5_001, 100_000, [], tiered), { ok: true, feeMinor: 300, totalMinor: 5_301 });
});

test("draw: above the highest band of a capped tariff is refused with the maximum", () => {
  const r = draw(20_001, 1_000_000, [], tiered);
  assert.equal(r.ok, false);
  if (!r.ok) assert.match(r.reason, /maximum 200\.00/);
});

test("draw: a fee larger than the amount is refused", () => {
  const r = draw(50, 100_000, [], tiered); // E0.50 would cost E1 in fees
  assert.equal(r.ok, false);
  if (!r.ok) assert.match(r.reason, /more than the amount/);
});
