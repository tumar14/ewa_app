import { test } from "node:test";
import assert from "node:assert/strict";
import { diffSettings, validateSettings } from "./settingsRules";

const current = { maxDrawPercent: 0.5, feeMode: "percent", feePercent: 0.05, feeTiers: [], autoApprove: false };
const ok = (input: unknown, ceiling = 0.5, cur: Record<string, unknown> = current) => {
  const r = validateSettings(input, cur, ceiling);
  assert.equal(r.ok, true, JSON.stringify(r));
  return r.ok ? r.patch : {};
};
const refused = (input: unknown, ceiling = 0.5, cur: Record<string, unknown> = current) => {
  const r = validateSettings(input, cur, ceiling);
  assert.equal(r.ok, false, `expected refusal for ${JSON.stringify(input)}`);
  return r.ok ? "" : r.error;
};

test("a normal change is accepted and unknown keys are dropped", () => {
  const p = ok({ maxDrawsPerCycle: 3, hacked: true, role: "admin", maxShiftHours: 12 });
  assert.deepEqual(p, { maxDrawsPerCycle: 3, maxShiftHours: 12 });
});

test("the advance limit cannot pass the platform ceiling or sit outside sensible bounds", () => {
  assert.match(refused({ maxDrawPercent: 0.9 }), /at most 50%/);
  assert.equal(ok({ maxDrawPercent: 0.9 }, 1).maxDrawPercent, 0.9);
  assert.match(refused({ maxDrawPercent: 5 }, 1), /between 5% and 100%/);
  refused({ maxDrawPercent: 0.01 });
  refused({ maxDrawPercent: "half" });
  refused({ maxDrawPercent: NaN });
  assert.equal(ok({ maxDrawPercent: 0.4 }).maxDrawPercent, 0.4);
});

test("counts, hours and days stay in range", () => {
  for (const bad of [0, 11, 2.5, "2", null]) refused({ maxDrawsPerCycle: bad });
  for (const bad of [0, 25, 1.5]) refused({ maxShiftHours: bad });
  refused({ newEmployeeWaitDays: 91 });
  refused({ payoutCoolingHours: -1 });
  refused({ claimCodeValidDays: 400 });
  assert.equal(ok({ claimCodeValidDays: 0 }).claimCodeValidDays, 0);
});

test("switches must be real on/off values", () => {
  refused({ autoApprove: "yes" });
  refused({ separatePayer: 1 });
  assert.equal(ok({ separatePayer: false }).separatePayer, false);
});

test("an invalid fee schedule is refused whatever is sent", () => {
  refused({ feeMode: "percent", feePercent: 0.9 });
  refused({ feeMode: "tiered", feeTiers: [] });
  refused({ feeMode: "tiered", feeTiers: [{ upToMinor: 100, flatMinor: 5, percent: 0 }, { upToMinor: 50, flatMinor: 5, percent: 0 }] });
  const p = ok({ feeMode: "tiered", feeTiers: [{ upToMinor: 5000, flatMinor: 100, percent: 0 }, { upToMinor: null, flatMinor: 0, percent: 0.015 }] });
  assert.equal(p.feeMode, "tiered");
  assert.equal((p.feeTiers as unknown[]).length, 2);
});

test("ceilings and thresholds are positive amounts or none", () => {
  refused({ autoApproveMaxMinor: 0 });
  refused({ autoApproveMaxMinor: -5 });
  refused({ dualApprovalAboveMinor: "big" });
  assert.equal(ok({ autoApproveMaxMinor: null }).autoApproveMaxMinor, null);
  assert.equal(ok({ dualApprovalAboveMinor: 50_000 }).dualApprovalAboveMinor, 50_000);
});

test("automatic approval cannot be set above the two-admin threshold", () => {
  assert.match(refused({ autoApprove: true, autoApproveMaxMinor: 90_000, dualApprovalAboveMinor: 50_000 }), /cannot be higher/);
  ok({ autoApprove: true, autoApproveMaxMinor: 40_000, dualApprovalAboveMinor: 50_000 });
  assert.match(refused({ dualApprovalAboveMinor: 10_000 }, 0.5, { ...current, autoApprove: true, autoApproveMaxMinor: 40_000 }), /cannot be higher/);
});

test("the payday rule must be a known one with sensible numbers", () => {
  ok({ paydayRule: { type: "lastDayOfMonth", dayOfMonth: 25, weekday: 5 } });
  refused({ paydayRule: { type: "whenever", dayOfMonth: 25, weekday: 5 } });
  refused({ paydayRule: { type: "fixedDayOfMonth", dayOfMonth: 40, weekday: 5 } });
  refused({ paydayRule: null });
});

test("company name is plain text", () => {
  assert.equal(ok({ companyName: "  Vuvuka   Investment " }).companyName, "Vuvuka Investment");
  refused({ companyName: "<script>" });
  refused({ companyName: "x".repeat(101) });
  refused({ companyName: 7 });
});

test("non-objects are refused", () => {
  for (const bad of [null, undefined, "x", 5, [1, 2]]) refused(bad);
});

test("the audit diff lists only real changes", () => {
  const d = diffSettings({ maxDrawPercent: 0.5, autoApprove: false }, { maxDrawPercent: 0.4, autoApprove: false, separatePayer: true });
  assert.deepEqual(d, [
    { field: "maxDrawPercent", from: 0.5, to: 0.4 },
    { field: "separatePayer", from: null, to: true },
  ]);
  assert.deepEqual(diffSettings({ a: 1 }, { a: 1 }), []);
});
