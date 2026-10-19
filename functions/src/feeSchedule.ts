// Service-fee schedules and the auto-approval policy. Pure: no Firebase imports,
// unit-tested in feeSchedule.test.ts, and mirrored in lib/models/fee_schedule.dart
// (the app uses the Dart copy only to preview the fee; the server is authoritative).
//
// All money is integer minor units (cents of a lilangeni).
//
// A schedule is one of:
//   percent: fee = amount x percent
//   tiered:  amount bands, like a mobile-money tariff table. Each band has an
//            upper limit, a flat fee and an optional percentage:
//            fee = flat + amount x percent. The last band may be open-ended
//            (upToMinor null); without one, amounts above the last limit are refused.

export interface FeeTier {
  upToMinor: number | null;
  flatMinor: number;
  percent: number;
}

export type FeeSchedule =
  | { mode: "percent"; percent: number }
  | { mode: "tiered"; tiers: FeeTier[] };

/** No single fee component may exceed half the amount; real tariffs sit far below this. */
export const MAX_FEE_PERCENT = 0.5;

const isCount = (v: unknown): v is number => typeof v === "number" && Number.isSafeInteger(v) && v >= 0;

/** Reads the schedule from a company's settings/app document, tolerating older documents. */
export function parseFeeSchedule(settings: Record<string, unknown>): FeeSchedule {
  if (settings.feeMode === "tiered") {
    const raw = Array.isArray(settings.feeTiers) ? settings.feeTiers : [];
    const tiers: FeeTier[] = raw.map((t) => {
      const o = (t ?? {}) as Record<string, unknown>;
      return {
        upToMinor: o.upToMinor === null || o.upToMinor === undefined ? null : (o.upToMinor as number),
        flatMinor: (o.flatMinor ?? 0) as number,
        percent: Number(o.percent ?? 0),
      };
    });
    return { mode: "tiered", tiers };
  }
  return { mode: "percent", percent: Number(settings.feePercent ?? 0.05) };
}

/** Null when the schedule is usable, otherwise a plain-language reason. */
export function validateFeeSchedule(s: FeeSchedule): string | null {
  const okPercent = (p: number) => Number.isFinite(p) && p >= 0 && p <= MAX_FEE_PERCENT;
  if (s.mode === "percent") {
    return okPercent(s.percent) ? null : "The fee percentage must be between 0% and 50%.";
  }
  if (s.tiers.length === 0) return "Add at least one fee band.";
  let previous = 0;
  for (const [i, t] of s.tiers.entries()) {
    const label = `Band ${i + 1}`;
    const last = i === s.tiers.length - 1;
    if (!isCount(t.flatMinor)) return `${label}: the flat fee must be zero or more.`;
    if (!okPercent(t.percent)) return `${label}: the percentage must be between 0% and 50%.`;
    if (t.upToMinor === null) {
      if (!last) return `${label}: only the last band can have no upper limit.`;
    } else {
      if (!isCount(t.upToMinor) || t.upToMinor <= previous) {
        return `${label}: the upper limit must be higher than the previous band's.`;
      }
    }
    if (t.upToMinor !== null) previous = t.upToMinor;
  }
  return null;
}

/** The largest amount the schedule allows, or null when there is no limit. */
export function maxAmountMinor(s: FeeSchedule): number | null {
  if (s.mode === "percent") return null;
  const last = s.tiers[s.tiers.length - 1];
  return last.upToMinor;
}

/** The fee for an amount, or null when the amount is outside every band. Assumes a valid schedule. */
export function feeFor(s: FeeSchedule, amountMinor: number): number | null {
  if (s.mode === "percent") return Math.round(amountMinor * s.percent);
  for (const t of s.tiers) {
    if (t.upToMinor === null || amountMinor <= t.upToMinor) {
      return Math.round(t.flatMinor + amountMinor * t.percent);
    }
  }
  return null;
}

// ── Auto-approval ────────────────────────────────────────────────────────────

export interface AutoApprovePolicy {
  enabled: boolean;
  /** Largest advance approved without a person, or null for no ceiling. */
  maxMinor: number | null;
}

/** Fails closed: anything unclear means a person decides. */
export function parseAutoApprove(settings: Record<string, unknown>): AutoApprovePolicy {
  if (settings.autoApprove !== true) return { enabled: false, maxMinor: null };
  const max = settings.autoApproveMaxMinor;
  if (max === null || max === undefined) return { enabled: true, maxMinor: null };
  if (typeof max === "number" && Number.isSafeInteger(max) && max > 0) return { enabled: true, maxMinor: max };
  return { enabled: false, maxMinor: null };
}

export function shouldAutoApprove(policy: AutoApprovePolicy, amountMinor: number): boolean {
  return policy.enabled && (policy.maxMinor === null || amountMinor <= policy.maxMinor);
}
