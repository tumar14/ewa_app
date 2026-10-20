import { test } from "node:test";
import assert from "node:assert/strict";
import { changedEmployeeFields } from "./employeeChanges";

const base = { name: "Thandi", role: "worker", hourlyRate: 40, active: true, disbursementMethod: "bankTransfer", disbursementDetails: { account: "123" } };

test("no change means nothing to log", () => {
  assert.deepEqual(changedEmployeeFields(base, { ...base }), { changes: [], payoutChanged: false });
});

test("rate, role and active changes are listed with old and new values", () => {
  const r = changedEmployeeFields(base, { ...base, hourlyRate: 400, role: "admin", active: false });
  assert.deepEqual(r.changes.map((c) => c.field).sort(), ["active", "hourlyRate", "role"]);
  assert.deepEqual(r.changes.find((c) => c.field === "hourlyRate"), { field: "hourlyRate", from: 40, to: 400 });
  assert.equal(r.payoutChanged, false);
});

test("a payout change is flagged but the account number is not copied", () => {
  const r = changedEmployeeFields(base, { ...base, disbursementDetails: { account: "999" } });
  assert.equal(r.payoutChanged, true);
  assert.equal(JSON.stringify(r).includes("999"), false);
  assert.equal(JSON.stringify(r).includes("123"), false);
  assert.equal(changedEmployeeFields(base, { ...base, disbursementMethod: "mobileMoney" }).payoutChanged, true);
});

test("the stamps the app adds are not changes in themselves", () => {
  const r = changedEmployeeFields(base, { ...base, lastEditedBy: "admin", lastEditedAt: 5, payoutChangedAt: 7 });
  assert.deepEqual(r, { changes: [], payoutChanged: false });
});

test("a last working day shows as a change, with times as milliseconds", () => {
  const ts = { toMillis: () => 1_800_000_000_000 };
  const r = changedEmployeeFields(base, { ...base, lastWorkingDay: ts });
  assert.deepEqual(r.changes, [{ field: "lastWorkingDay", from: null, to: 1_800_000_000_000 }]);
});
