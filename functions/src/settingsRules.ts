// Validation of a company's operating settings before they are saved. No Firebase
// imports: unit-tested in settingsRules.test.ts. The admin app no longer writes
// settings/app itself; the updateSettings function runs every change through here, so
// a value that is out of range, or above the platform's ceiling, can never be stored,
// and each accepted change is written to the audit log.

import { DEFAULT_PLATFORM_DRAW_CEILING } from "./controls";
import { parseFeeSchedule, validateFeeSchedule } from "./feeSchedule";

type Obj = Record<string, unknown>;

const CLOCK_SOURCES = ["manual", "kioskPin", "kioskQr", "externalImport"];
const DISBURSEMENT = ["bankTransfer", "mobileMoney", "cash"];
const PAYDAY_TYPES = ["fixedDayOfMonth", "lastDayOfMonth", "lastWeekdayOfMonth"];

/** Keys the app may set. Anything else in the request is ignored. */
export const SETTING_KEYS = [
  "companyName", "maxDrawPercent", "feeMode", "feePercent", "feeTiers", "maxDrawsPerCycle",
  "clockSource", "allowManualHourEdits", "allowAttendanceImport", "maxShiftHours",
  "countOnlyReviewedHours", "disbursementPolicy", "paydayRule", "autoApprove", "autoApproveMaxMinor",
  "dualApprovalAboveMinor", "separatePayer", "newEmployeeWaitDays", "pauseDrawsDaysBeforeExit",
  "payoutCoolingHours", "separateSignOff", "claimCodeValidDays",
] as const;

export type SettingsResult = { ok: true; patch: Obj } | { ok: false; error: string };

const isInt = (v: unknown, min: number, max: number): v is number =>
  typeof v === "number" && Number.isInteger(v) && v >= min && v <= max;

function plainText(v: unknown, max: number): string | null {
  if (typeof v !== "string") return null;
  const s = v.replace(/\s+/g, " ").trim();
  if (s.length > max) return null;
  for (let i = 0; i < s.length; i++) {
    const c = s.charCodeAt(i);
    if (c === 60 || c === 62 || c < 32) return null;
  }
  return s;
}

/**
 * Checks the settings the app sent. `current` is what is stored now (used to validate the
 * fee schedule as a whole when only part of it is sent). Returns the cleaned values to store.
 */
export function validateSettings(input: unknown, current: Obj, platformCeiling: number): SettingsResult {
  if (typeof input !== "object" || input === null || Array.isArray(input)) {
    return { ok: false, error: "No settings were sent." };
  }
  const raw = input as Obj;
  const patch: Obj = {};
  const bad = (error: string): SettingsResult => ({ ok: false, error });
  const has = (k: string) => raw[k] !== undefined;
  const ceiling = Number.isFinite(platformCeiling) && platformCeiling > 0 && platformCeiling <= 1 ? platformCeiling : DEFAULT_PLATFORM_DRAW_CEILING;

  if (has("companyName")) {
    const name = plainText(raw.companyName, 100);
    if (name === null) return bad("The company name must be 100 characters or fewer, without < or >.");
    patch.companyName = name;
  }
  if (has("maxDrawPercent")) {
    const p = raw.maxDrawPercent;
    if (typeof p !== "number" || !Number.isFinite(p) || p < 0.05 || p > 1) return bad("The advance limit must be between 5% and 100% of earned wages.");
    if (p > ceiling + 1e-9) return bad(`The platform allows at most ${Math.round(ceiling * 100)}% of earned wages to be advanced.`);
    patch.maxDrawPercent = p;
  }
  if (has("maxDrawsPerCycle")) {
    if (!isInt(raw.maxDrawsPerCycle, 1, 10)) return bad("Advances per pay cycle must be a whole number from 1 to 10.");
    patch.maxDrawsPerCycle = raw.maxDrawsPerCycle;
  }
  if (has("clockSource")) {
    if (!CLOCK_SOURCES.includes(raw.clockSource as string)) return bad("That clock source is not recognised.");
    patch.clockSource = raw.clockSource;
  }
  if (has("disbursementPolicy")) {
    if (!DISBURSEMENT.includes(raw.disbursementPolicy as string)) return bad("That payment method is not recognised.");
    patch.disbursementPolicy = raw.disbursementPolicy;
  }
  for (const flag of ["allowManualHourEdits", "allowAttendanceImport", "countOnlyReviewedHours", "autoApprove", "separatePayer", "separateSignOff"]) {
    if (has(flag)) {
      if (typeof raw[flag] !== "boolean") return bad(`"${flag}" must be on or off.`);
      patch[flag] = raw[flag];
    }
  }
  if (has("maxShiftHours")) {
    if (!isInt(raw.maxShiftHours, 1, 24)) return bad("The longest time record must be 1 to 24 hours.");
    patch.maxShiftHours = raw.maxShiftHours;
  }
  const ranges: Array<[string, number, number, string]> = [
    ["newEmployeeWaitDays", 0, 90, "The wait for new employees must be 0 to 90 days."],
    ["pauseDrawsDaysBeforeExit", 0, 90, "The pause before someone leaves must be 0 to 90 days."],
    ["payoutCoolingHours", 0, 720, "The hold after a payout change must be 0 to 720 hours."],
    ["claimCodeValidDays", 0, 365, "Claim codes must stay valid for 0 to 365 days (0 = never expire)."],
  ];
  for (const [key, min, max, message] of ranges) {
    if (has(key)) {
      if (!isInt(raw[key], min, max)) return bad(message);
      patch[key] = raw[key];
    }
  }
  for (const key of ["autoApproveMaxMinor", "dualApprovalAboveMinor"]) {
    if (has(key)) {
      const v = raw[key];
      if (v !== null && !(typeof v === "number" && Number.isSafeInteger(v) && v > 0)) {
        return bad(key === "autoApproveMaxMinor" ? "The automatic approval ceiling must be an amount above zero, or none." : "The two-admin threshold must be an amount above zero, or none.");
      }
      patch[key] = v;
    }
  }
  if (has("paydayRule")) {
    const r = raw.paydayRule as Obj | null;
    if (typeof r !== "object" || r === null || !PAYDAY_TYPES.includes(r.type as string)) return bad("That payday rule is not recognised.");
    if (!isInt(r.dayOfMonth, 1, 31) || !isInt(r.weekday, 1, 7)) return bad("The payday day or weekday is out of range.");
    patch.paydayRule = { type: r.type, dayOfMonth: r.dayOfMonth, weekday: r.weekday };
  }

  if (has("feeMode") || has("feePercent") || has("feeTiers")) {
    const merged = { ...current, ...Object.fromEntries(["feeMode", "feePercent", "feeTiers"].filter(has).map((k) => [k, raw[k]])) };
    const schedule = parseFeeSchedule(merged);
    const problem = validateFeeSchedule(schedule);
    if (problem) return bad(problem);
    if (has("feeMode")) patch.feeMode = schedule.mode;
    if (has("feePercent")) patch.feePercent = Number(raw.feePercent);
    if (has("feeTiers")) {
      patch.feeTiers = schedule.mode === "tiered"
        ? schedule.tiers
        : (Array.isArray(raw.feeTiers) ? raw.feeTiers : []).map((t) => {
            const o = (t ?? {}) as Obj;
            return { upToMinor: (o.upToMinor ?? null) as number | null, flatMinor: Number(o.flatMinor ?? 0), percent: Number(o.percent ?? 0) };
          });
    }
  }

  const resulting = { ...current, ...patch };
  if (resulting.autoApprove === true && resulting.autoApproveMaxMinor !== null && resulting.autoApproveMaxMinor !== undefined
      && typeof resulting.dualApprovalAboveMinor === "number"
      && (resulting.autoApproveMaxMinor as number) > (resulting.dualApprovalAboveMinor as number)) {
    return bad("The automatic approval ceiling cannot be higher than the amount that needs two admins.");
  }
  return { ok: true, patch };
}

export interface SettingChange {
  field: string;
  from: unknown;
  to: unknown;
}

/** Which settings the patch actually changes, for the audit log. */
export function diffSettings(before: Obj, patch: Obj): SettingChange[] {
  const out: SettingChange[] = [];
  for (const [field, to] of Object.entries(patch)) {
    const from = before[field] === undefined ? null : before[field];
    if (JSON.stringify(from) !== JSON.stringify(to)) out.push({ field, from, to });
  }
  return out;
}
