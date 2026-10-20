import { test } from "node:test";
import assert from "node:assert/strict";
import { canSignOff } from "./signoffRules";

const base = { uid: "sup", employeeId: "w", editedBy: null, voided: false, reviewed: false, separate: true };

test("a supervisor can sign off a worker's hours", () => {
  assert.equal(canSignOff(base).ok, true);
});

test("nobody signs off their own hours", () => {
  assert.equal(canSignOff({ ...base, uid: "w" }).ok, false);
});

test("the person who entered or uploaded a record cannot sign it off, unless the company allows it", () => {
  assert.equal(canSignOff({ ...base, editedBy: "sup" }).ok, false);
  assert.equal(canSignOff({ ...base, editedBy: "other" }).ok, true);
  assert.equal(canSignOff({ ...base, editedBy: "sup", separate: false }).ok, true);
});

test("void and already-signed records are refused with a reason", () => {
  assert.deepEqual(canSignOff({ ...base, voided: true }), { ok: false, reason: "This record is void." });
  assert.deepEqual(canSignOff({ ...base, reviewed: true }), { ok: false, reason: "Already signed off." });
});
