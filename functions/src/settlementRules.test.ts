import { test } from "node:test";
import assert from "node:assert/strict";
import {
  DEDUCTION_MISMATCH_ID,
  OVERPAYMENT_ID,
  ReconException,
  isValidTransactionId,
  outstandingMinor,
  reconcile,
  settlementReference,
  settlementStatus,
} from "./settlementRules";

const fig = (expectedMinor: number, confirmedMinor: number | null, receivedMinor: number) => ({
  expectedMinor,
  confirmedMinor,
  receivedMinor,
});

test("status: draft until deductions are confirmed", () => {
  assert.equal(settlementStatus(fig(5_000_000, null, 0), 0, false), "DRAFT");
});

test("status: due, partially settled, settled", () => {
  assert.equal(settlementStatus(fig(5_000_000, 5_000_000, 0), 0, false), "DUE");
  assert.equal(settlementStatus(fig(5_000_000, 5_000_000, 1), 0, false), "PARTIALLY_SETTLED");
  assert.equal(settlementStatus(fig(5_000_000, 5_000_000, 4_999_999), 0, false), "PARTIALLY_SETTLED");
  assert.equal(settlementStatus(fig(5_000_000, 5_000_000, 5_000_000), 0, false), "SETTLED");
});

test("status: any open exception wins, cancelled wins over everything", () => {
  assert.equal(settlementStatus(fig(5_000_000, 5_000_000, 5_000_000), 1, false), "EXCEPTION");
  assert.equal(settlementStatus(fig(5_000_000, 5_000_000, 0), 1, true), "CANCELLED");
});

test("blueprint example: E50,000 expected, E49,500 confirmed and received", () => {
  const f = fig(5_000_000, 4_950_000, 4_950_000);
  assert.equal(outstandingMinor(f), 50_000); // the E500 difference
  const { upserts, openCount } = reconcile(f, []);
  assert.equal(openCount, 1);
  assert.equal(upserts[0].id, DEDUCTION_MISMATCH_ID);
  assert.equal(upserts[0].type, "DEDUCTION_SHORTFALL");
  assert.equal(upserts[0].differenceMinor, -50_000);
  // Not marked settled just because money arrived.
  assert.equal(settlementStatus(f, openCount, false), "EXCEPTION");
});

test("reconcile: matching figures raise nothing", () => {
  assert.deepEqual(reconcile(fig(1_000, 1_000, 1_000), []), { upserts: [], openCount: 0 });
  assert.deepEqual(reconcile(fig(1_000, null, 0), []), { upserts: [], openCount: 0 });
});

test("reconcile: excess deduction and overpayment", () => {
  const excess = reconcile(fig(1_000, 1_200, 0), []);
  assert.equal(excess.upserts[0].type, "DEDUCTION_EXCESS");
  const over = reconcile(fig(1_000, 1_000, 1_500), []);
  assert.equal(over.upserts[0].id, OVERPAYMENT_ID);
  assert.equal(over.upserts[0].differenceMinor, 500);
});

test("reconcile: a resolved discrepancy stays resolved while its numbers are unchanged", () => {
  const resolved: ReconException = {
    id: DEDUCTION_MISMATCH_ID,
    type: "DEDUCTION_SHORTFALL",
    status: "resolved",
    expectedMinor: 1_000,
    actualMinor: 900,
    differenceMinor: -100,
    resolutionNote: "Employee on unpaid leave",
  };
  assert.deepEqual(reconcile(fig(1_000, 900, 900), [resolved]), { upserts: [], openCount: 0 });
  // Numbers change -> it reopens.
  const changed = reconcile(fig(1_000, 800, 800), [resolved]);
  assert.equal(changed.openCount, 1);
  assert.equal(changed.upserts[0].status, "open");
});

test("reconcile: an open discrepancy closes itself when the figures agree again", () => {
  const open: ReconException = {
    id: DEDUCTION_MISMATCH_ID,
    type: "DEDUCTION_SHORTFALL",
    status: "open",
    expectedMinor: 1_000,
    actualMinor: 900,
    differenceMinor: -100,
  };
  const r = reconcile(fig(1_000, 1_000, 0), [open]);
  assert.equal(r.openCount, 0);
  assert.equal(r.upserts[0].status, "resolved");
});

test("reconcile: insufficient-pay exceptions pass through and still count as open", () => {
  const pay: ReconException = {
    id: "insufficient_pay_emp1",
    type: "INSUFFICIENT_PAY",
    status: "open",
    expectedMinor: 5_000,
    actualMinor: 3_000,
    differenceMinor: -2_000,
    employeeId: "emp1",
  };
  const r = reconcile(fig(5_000, 5_000, 5_000), [pay]);
  assert.deepEqual(r.upserts, []);
  assert.equal(r.openCount, 1);
});

test("reference is unique per run and stable", () => {
  const ref = settlementReference("ABC123", Date.parse("2026-10-31T10:00:00Z"), "k3f9Zx81");
  assert.equal(ref, "EWA-ABC123-20261031-K3F9");
  // 22:30Z on the 31st is already 1 Nov in Eswatini.
  assert.equal(settlementReference("ABC123", Date.parse("2026-10-31T22:30:00Z"), "k3f9Zx81"), "EWA-ABC123-20261101-K3F9");
});

test("transaction id validation", () => {
  assert.equal(isValidTransactionId("FNB-20261031-000123"), true);
  assert.equal(isValidTransactionId("ab"), false);
  assert.equal(isValidTransactionId("has space"), false);
  assert.equal(isValidTransactionId("a/b/c/d"), false);
});
