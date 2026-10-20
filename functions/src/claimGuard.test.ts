import { test } from "node:test";
import assert from "node:assert/strict";
import { CLAIM_LOCK_MS, MAX_FAILED_CLAIMS, afterFailure, isExpired, isLocked, validDaysFrom } from "./claimGuard";

const now = Date.parse("2026-10-20T10:00:00Z");
const day = 86_400_000;

test("the fifth wrong guess locks the seat, and the count starts again after", () => {
  let failures = 0;
  for (let i = 1; i < MAX_FAILED_CLAIMS; i++) {
    const r = afterFailure(failures, now);
    assert.equal(r.lockedUntilMs, null);
    failures = r.failures;
  }
  const last = afterFailure(failures, now);
  assert.equal(last.lockedUntilMs, now + CLAIM_LOCK_MS);
  assert.equal(last.failures, 0);
});

test("garbage failure counts are treated as zero", () => {
  assert.equal(afterFailure(NaN, now).failures, 1);
  assert.equal(afterFailure(-4, now).failures, 1);
});

test("a lock holds until its time", () => {
  assert.equal(isLocked(now + 1, now), true);
  assert.equal(isLocked(now, now), false);
  assert.equal(isLocked(null, now), false);
  assert.equal(isLocked(undefined, now), false);
});

test("codes expire after the company's number of days, unless it never expires", () => {
  assert.equal(isExpired(now - 31 * day, now, 30), true);
  assert.equal(isExpired(now - 29 * day, now, 30), false);
  assert.equal(isExpired(now - 999 * day, now, 0), false);
  assert.equal(isExpired(null, now, 30), false);
});

test("the validity setting falls back to 30 days", () => {
  assert.equal(validDaysFrom({}), 30);
  assert.equal(validDaysFrom({ claimCodeValidDays: 7 }), 7);
  assert.equal(validDaysFrom({ claimCodeValidDays: 0 }), 0);
  assert.equal(validDaysFrom({ claimCodeValidDays: -1 }), 30);
  assert.equal(validDaysFrom({ claimCodeValidDays: "7" }), 30);
});
