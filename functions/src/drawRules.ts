// Pure draw-eligibility and pay-cycle math, ported from lib/utils/wage_calculator.dart
// and lib/utils/pay_cycle.dart so the server enforces the same rules the app displays.
// All money here is an integer number of minor units (cents of a lilangeni); the
// only floats are rates and percentages, rounded once when converted.
// No Firebase imports: unit-tested in drawRules.test.ts.
import { FeeSchedule, feeFor, maxAmountMinor } from "./feeSchedule";

export type PaydayType = "fixedDayOfMonth" | "lastDayOfMonth" | "lastWeekdayOfMonth";

export interface PaydayRule {
  type: PaydayType;
  dayOfMonth: number;
  weekday: number; // ISO: 1 = Monday ... 7 = Sunday
}

export interface DrawLimits {
  maxDrawPercent: number;
  maxDrawsPerCycle: number;
  /** How the service fee is worked out (percentage or a tariff table). Must be valid. */
  fee: FeeSchedule;
}

// Eswatini is UTC+2 year-round (no DST). Cycle boundaries are local midnight.
const LOCAL_OFFSET_MS = 2 * 3_600_000;
const DAY_MS = 86_400_000;

/** Whole minor units as a display string, e.g. 12345 -> "123.45". */
export function formatMinor(minor: number): string {
  return (minor / 100).toFixed(2);
}

// Smallest epsilon that keeps e.g. 400 * 0.5 from landing at 199.99999999999997.
function floorPercent(minor: number, fraction: number): number {
  return Math.floor(minor * fraction + 1e-9);
}

// A local calendar date as ms since epoch at 00:00 UTC of that date.
function localDateMs(y: number, m: number, d: number): number {
  return Date.UTC(y, m - 1, d);
}

function lastDayOfMonth(y: number, m: number): number {
  return new Date(Date.UTC(y, m, 0)).getUTCDate();
}

function paydayLocalMs(y: number, m: number, rule: PaydayRule): number {
  switch (rule.type) {
    case "fixedDayOfMonth": {
      const last = lastDayOfMonth(y, m);
      return localDateMs(y, m, Math.min(Math.max(rule.dayOfMonth, 1), last));
    }
    case "lastDayOfMonth":
      return localDateMs(y, m, lastDayOfMonth(y, m));
    case "lastWeekdayOfMonth": {
      let ms = localDateMs(y, m, lastDayOfMonth(y, m));
      const isoWeekday = (t: number) => {
        const d = new Date(t).getUTCDay();
        return d === 0 ? 7 : d;
      };
      while (isoWeekday(ms) !== rule.weekday) ms -= DAY_MS;
      return ms;
    }
  }
}

/** Start (local midnight, as a UTC instant in ms) of the pay cycle containing `nowMs`. */
export function currentCycleStartMs(rule: PaydayRule, nowMs: number): number {
  const local = new Date(nowMs + LOCAL_OFFSET_MS);
  const y = local.getUTCFullYear();
  const m = local.getUTCMonth() + 1;
  const today = localDateMs(y, m, local.getUTCDate());
  const thisPayday = paydayLocalMs(y, m, rule);

  const startLocal =
    today <= thisPayday
      ? paydayLocalMs(m === 1 ? y - 1 : y, m === 1 ? 12 : m - 1, rule) + DAY_MS
      : thisPayday + DAY_MS;
  return startLocal - LOCAL_OFFSET_MS;
}

export interface SessionSpan {
  clockInMs: number;
  clockOutMs: number | null; // null = still open, counted up to `nowMs`
}

/** hourlyRate * whole minutes worked / 60, in minor units (matches WageCalculator.accruedWages). */
export function accruedMinor(hourlyRate: number, sessions: SessionSpan[], nowMs: number): number {
  const totalMs = sessions.reduce(
    (sum, s) => sum + ((s.clockOutMs ?? nowMs) - s.clockInMs),
    0,
  );
  return Math.round((hourlyRate * 100 * Math.floor(totalMs / 60_000)) / 60);
}

export type DrawCheck =
  | { ok: true; feeMinor: number; totalMinor: number }
  | { ok: false; reason: string };

/**
 * `outstanding` must be this employee's non-rejected draws not yet settled by
 * a payroll run (the same set the app counts against the cycle cap).
 */
export function checkNewDraw(args: {
  amountMinor: number;
  accruedMinor: number;
  limits: DrawLimits;
  outstanding: { amountMinor: number }[];
}): DrawCheck {
  const { amountMinor, limits, outstanding } = args;

  if (!Number.isSafeInteger(amountMinor) || amountMinor <= 0) {
    return { ok: false, reason: "Amount must be a positive whole number of cents." };
  }
  if (outstanding.length >= limits.maxDrawsPerCycle) {
    return {
      ok: false,
      reason: `You have reached the limit of ${limits.maxDrawsPerCycle} draws this pay cycle.`,
    };
  }

  const used = outstanding.reduce((sum, d) => sum + d.amountMinor, 0);
  const remaining = Math.max(0, floorPercent(args.accruedMinor, limits.maxDrawPercent) - used);
  if (amountMinor > remaining) {
    return {
      ok: false,
      reason: `Amount exceeds what you can draw right now (maximum ${formatMinor(remaining)}).`,
    };
  }

  const feeMinor = feeFor(limits.fee, amountMinor);
  if (feeMinor === null) {
    return {
      ok: false,
      reason: `That amount is above the largest this company's fee table covers (maximum ${formatMinor(maxAmountMinor(limits.fee) ?? 0)}).`,
    };
  }
  if (feeMinor > amountMinor) {
    return { ok: false, reason: "The fee for such a small amount would be more than the amount itself. Choose a larger amount." };
  }
  return { ok: true, feeMinor, totalMinor: amountMinor + feeMinor };
}

/** True when `drawnMinor` (including the draw being approved) is within the cycle cap. */
export function withinCap(accruedMinorValue: number, maxDrawPercent: number, drawnMinor: number): boolean {
  return drawnMinor <= floorPercent(accruedMinorValue, maxDrawPercent);
}
