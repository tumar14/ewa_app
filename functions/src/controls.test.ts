import { test } from "node:test";
import assert from "node:assert/strict";
import {
  DEFAULT_CONTROLS, autoApprovalAllowed, canRecordPayment, clampDrawPercent, decide,
  drawBlockedReason, needsSecondApproval, parseControls, validatePaymentReference, withinRequestRate,
} from "./controls";

const day = 86_400_000;
const now = Date.parse("2026-10-20T10:00:00Z");
const dual = { ...DEFAULT_CONTROLS, dualApprovalAboveMinor: 50_000 };

test("defaults, and bad settings fall back to them", () => {
  assert.deepEqual(parseControls({}), DEFAULT_CONTROLS);
  assert.equal(parseControls({ dualApprovalAboveMinor: 0 }).dualApprovalAboveMinor, null);
  assert.equal(parseControls({ dualApprovalAboveMinor: "big" }).dualApprovalAboveMinor, null);
  assert.equal(parseControls({ dualApprovalAboveMinor: 50_000 }).dualApprovalAboveMinor, 50_000);
  assert.equal(parseControls({ newEmployeeWaitDays: 500 }).newEmployeeWaitDays, 0);
  assert.equal(parseControls({ newEmployeeWaitDays: 14 }).newEmployeeWaitDays, 14);
  assert.equal(parseControls({ payoutCoolingHours: -1 }).payoutCoolingHours, 48);
  assert.equal(parseControls({ separatePayer: false }).separatePayer, false);
  assert.equal(parseControls({ separatePayer: "no" }).separatePayer, true);
});

test("nobody can decide their own advance", () => {
  const r = decide({ uid: "a", employeeId: "a", amountMinor: 100, approve: true, firstApprovalBy: null, controls: DEFAULT_CONTROLS });
  assert.equal(r.ok, false);
  assert.equal(decide({ uid: "a", employeeId: "a", amountMinor: 100, approve: false, firstApprovalBy: null, controls: DEFAULT_CONTROLS }).ok, false);
});

test("a small advance needs one approval; declining is always one person", () => {
  assert.deepEqual(decide({ uid: "a", employeeId: "w", amountMinor: 50_000, approve: true, firstApprovalBy: null, controls: dual }), { ok: true, outcome: "final_approval" });
  assert.deepEqual(decide({ uid: "a", employeeId: "w", amountMinor: 90_000, approve: false, firstApprovalBy: null, controls: dual }), { ok: true, outcome: "reject" });
});

test("a large advance needs two different admins", () => {
  assert.equal(needsSecondApproval(dual, 50_001), true);
  assert.deepEqual(decide({ uid: "a", employeeId: "w", amountMinor: 90_000, approve: true, firstApprovalBy: null, controls: dual }), { ok: true, outcome: "first_approval" });
  assert.equal(decide({ uid: "a", employeeId: "w", amountMinor: 90_000, approve: true, firstApprovalBy: "a", controls: dual }).ok, false);
  assert.deepEqual(decide({ uid: "b", employeeId: "w", amountMinor: 90_000, approve: true, firstApprovalBy: "a", controls: dual }), { ok: true, outcome: "final_approval" });
});

test("a policy cannot approve a large advance by itself", () => {
  assert.equal(autoApprovalAllowed(dual, 90_000), false);
  assert.equal(autoApprovalAllowed(dual, 10_000), true);
  assert.equal(autoApprovalAllowed(DEFAULT_CONTROLS, 9_000_000), true);
});

test("payment references must be real-looking and not app-generated", () => {
  assert.equal(validatePaymentReference("MP241020.1530.A12345"), null);
  assert.equal(validatePaymentReference("FNB/2026/10/445"), null);
  for (const bad of ["", "abc", "x".repeat(61), "<b>", "DISP-ABCD1234", 5, null, undefined]) {
    assert.notEqual(validatePaymentReference(bad), null, String(bad));
  }
});

const pay = (over: Partial<Parameters<typeof canRecordPayment>[0]> = {}) =>
  canRecordPayment({ uid: "payer", employeeId: "w", decidedBy: "approver", firstApprovalBy: null, payoutChangedAtMs: null, nowMs: now, controls: DEFAULT_CONTROLS, ...over });

test("the payer must differ from the approver(s) and from the employee", () => {
  assert.equal(pay().ok, true);
  assert.equal(pay({ decidedBy: "payer" }).ok, false);
  assert.equal(pay({ decidedBy: "other", firstApprovalBy: "payer" }).ok, false);
  assert.equal(pay({ uid: "w" }).ok, false);
  assert.equal(pay({ decidedBy: "policy" }).ok, true); // an automatic approval has no person to conflict with
  assert.equal(pay({ decidedBy: "payer", controls: { ...DEFAULT_CONTROLS, separatePayer: false } }).ok, true);
});

test("payment is held after payout details change", () => {
  assert.equal(pay({ payoutChangedAtMs: now - 10 * 3_600_000 }).ok, false);
  assert.equal(pay({ payoutChangedAtMs: now - 49 * 3_600_000 }).ok, true);
  assert.equal(pay({ payoutChangedAtMs: now - 3_600_000, controls: { ...DEFAULT_CONTROLS, payoutCoolingHours: 0 } }).ok, true);
});

test("new employees wait; leavers pause", () => {
  const c = { ...DEFAULT_CONTROLS, newEmployeeWaitDays: 7 };
  assert.notEqual(drawBlockedReason({ nowMs: now, createdAtMs: now - 2 * day, lastWorkingDayMs: null, controls: c }), null);
  assert.equal(drawBlockedReason({ nowMs: now, createdAtMs: now - 8 * day, lastWorkingDayMs: null, controls: c }), null);
  assert.equal(drawBlockedReason({ nowMs: now, createdAtMs: null, lastWorkingDayMs: null, controls: c }), null); // older records have no start date
  assert.notEqual(drawBlockedReason({ nowMs: now, createdAtMs: null, lastWorkingDayMs: now + 3 * day, controls: DEFAULT_CONTROLS }), null);
  assert.equal(drawBlockedReason({ nowMs: now, createdAtMs: null, lastWorkingDayMs: now + 30 * day, controls: DEFAULT_CONTROLS }), null);
  assert.notEqual(drawBlockedReason({ nowMs: now, createdAtMs: null, lastWorkingDayMs: now - 2 * day, controls: DEFAULT_CONTROLS }), null);
  assert.equal(drawBlockedReason({ nowMs: now, createdAtMs: null, lastWorkingDayMs: now + 1 * day, controls: { ...DEFAULT_CONTROLS, pauseDrawsDaysBeforeExit: 0 } }), null);
});

test("the platform ceiling caps what a company can set", () => {
  assert.equal(clampDrawPercent(0.9, 0.5), 0.5);
  assert.equal(clampDrawPercent(0.3, 0.5), 0.3);
  assert.equal(clampDrawPercent(5, 0.4), 0.4);
  assert.equal(clampDrawPercent(0.3, NaN), 0.3);
  assert.equal(clampDrawPercent(0.9, NaN), 0.5);
  assert.equal(clampDrawPercent(-1, 0.5), 0);
  assert.equal(clampDrawPercent(NaN, 0.5), 0);
});

test("requests per hour are limited", () => {
  assert.equal(withinRequestRate(5), true);
  assert.equal(withinRequestRate(6), false);
});
