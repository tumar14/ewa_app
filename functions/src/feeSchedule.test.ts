import { test } from "node:test";
import assert from "node:assert/strict";
import {
  FeeSchedule,
  feeFor,
  maxAmountMinor,
  parseAutoApprove,
  parseFeeSchedule,
  shouldAutoApprove,
  validateFeeSchedule,
} from "./feeSchedule";

// A mobile-money style tariff, in cents: up to E50 -> E1, up to E200 -> E3, up to E1000 -> E6 + 0.5%, above -> 1.5%.
const tariff: FeeSchedule = {
  mode: "tiered",
  tiers: [
    { upToMinor: 5_000, flatMinor: 100, percent: 0 },
    { upToMinor: 20_000, flatMinor: 300, percent: 0 },
    { upToMinor: 100_000, flatMinor: 600, percent: 0.005 },
    { upToMinor: null, flatMinor: 0, percent: 0.015 },
  ],
};
const capped: FeeSchedule = { mode: "tiered", tiers: [{ upToMinor: 50_000, flatMinor: 200, percent: 0 }] };

test("percent mode: fee is amount x percent, rounded to a cent", () => {
  assert.equal(feeFor({ mode: "percent", percent: 0.05 }, 20_000), 1_000);
  assert.equal(feeFor({ mode: "percent", percent: 0.05 }, 3_333), 167); // 166.65
  assert.equal(feeFor({ mode: "percent", percent: 0 }, 5_000), 0);
});

test("tiered mode: the band is chosen by amount and edges belong to the lower band", () => {
  assert.equal(feeFor(tariff, 1), 100);
  assert.equal(feeFor(tariff, 5_000), 100); // exactly E50
  assert.equal(feeFor(tariff, 5_001), 300); // one cent over
  assert.equal(feeFor(tariff, 20_000), 300);
  assert.equal(feeFor(tariff, 20_001), 600 + 100); // 600 + 0.5% of 20,001 = 100.005 -> 700
  assert.equal(feeFor(tariff, 100_000), 1_100); // 600 + 500
  assert.equal(feeFor(tariff, 100_001), 1_500); // open band: 1.5%
  assert.equal(feeFor(tariff, 1_000_000), 15_000);
});

test("a schedule with no open band refuses amounts above its last limit", () => {
  assert.equal(feeFor(capped, 50_000), 200);
  assert.equal(feeFor(capped, 50_001), null);
  assert.equal(maxAmountMinor(capped), 50_000);
  assert.equal(maxAmountMinor(tariff), null);
  assert.equal(maxAmountMinor({ mode: "percent", percent: 0.05 }), null);
});

test("valid schedules pass validation", () => {
  assert.equal(validateFeeSchedule(tariff), null);
  assert.equal(validateFeeSchedule(capped), null);
  assert.equal(validateFeeSchedule({ mode: "percent", percent: 0.05 }), null);
  assert.equal(validateFeeSchedule({ mode: "percent", percent: 0 }), null);
});

test("invalid schedules are explained", () => {
  const bad = (s: FeeSchedule) => validateFeeSchedule(s);
  assert.match(bad({ mode: "percent", percent: -0.01 })!, /between 0% and 50%/);
  assert.match(bad({ mode: "percent", percent: 0.6 })!, /between 0% and 50%/);
  assert.match(bad({ mode: "percent", percent: NaN })!, /between 0% and 50%/);
  assert.match(bad({ mode: "tiered", tiers: [] })!, /at least one/);
  assert.match(bad({ mode: "tiered", tiers: [{ upToMinor: 5_000, flatMinor: 100, percent: 0 }, { upToMinor: 5_000, flatMinor: 200, percent: 0 }] })!, /higher than the previous/);
  assert.match(bad({ mode: "tiered", tiers: [{ upToMinor: 9_000, flatMinor: 100, percent: 0 }, { upToMinor: 5_000, flatMinor: 200, percent: 0 }] })!, /higher than the previous/);
  assert.match(bad({ mode: "tiered", tiers: [{ upToMinor: null, flatMinor: 100, percent: 0 }, { upToMinor: 5_000, flatMinor: 200, percent: 0 }] })!, /only the last band/);
  assert.match(bad({ mode: "tiered", tiers: [{ upToMinor: 5_000, flatMinor: -1, percent: 0 }] })!, /flat fee/);
  assert.match(bad({ mode: "tiered", tiers: [{ upToMinor: 5_000, flatMinor: 1.5, percent: 0 }] })!, /flat fee/);
  assert.match(bad({ mode: "tiered", tiers: [{ upToMinor: 5_000, flatMinor: 100, percent: 0.9 }] })!, /between 0% and 50%/);
});

test("settings documents are parsed, including older ones without the new fields", () => {
  assert.deepEqual(parseFeeSchedule({ feePercent: 0.07 }), { mode: "percent", percent: 0.07 });
  assert.deepEqual(parseFeeSchedule({}), { mode: "percent", percent: 0.05 });
  assert.deepEqual(parseFeeSchedule({ feeMode: "percent", feePercent: 0.02, feeTiers: [{ upToMinor: 1, flatMinor: 1, percent: 0 }] }), { mode: "percent", percent: 0.02 });
  assert.deepEqual(parseFeeSchedule({ feeMode: "tiered", feeTiers: [{ upToMinor: 5_000, flatMinor: 100, percent: 0 }, { upToMinor: null, flatMinor: 0, percent: 0.02 }] }), {
    mode: "tiered",
    tiers: [{ upToMinor: 5_000, flatMinor: 100, percent: 0 }, { upToMinor: null, flatMinor: 0, percent: 0.02 }],
  });
  // Tiered with garbage tiers parses, then fails validation rather than computing nonsense.
  const garbage = parseFeeSchedule({ feeMode: "tiered", feeTiers: "nope" });
  assert.match(validateFeeSchedule(garbage)!, /at least one/);
});

test("auto-approval is off unless explicitly on", () => {
  assert.deepEqual(parseAutoApprove({}), { enabled: false, maxMinor: null });
  assert.deepEqual(parseAutoApprove({ autoApprove: "yes" }), { enabled: false, maxMinor: null });
  assert.deepEqual(parseAutoApprove({ autoApprove: false, autoApproveMaxMinor: 10_000 }), { enabled: false, maxMinor: null });
  assert.deepEqual(parseAutoApprove({ autoApprove: true }), { enabled: true, maxMinor: null });
  assert.deepEqual(parseAutoApprove({ autoApprove: true, autoApproveMaxMinor: null }), { enabled: true, maxMinor: null });
  assert.deepEqual(parseAutoApprove({ autoApprove: true, autoApproveMaxMinor: 20_000 }), { enabled: true, maxMinor: 20_000 });
});

test("an unclear ceiling fails closed: a person decides", () => {
  for (const bad of [0, -5, 1.5, "200", NaN, Infinity]) {
    assert.deepEqual(parseAutoApprove({ autoApprove: true, autoApproveMaxMinor: bad }), { enabled: false, maxMinor: null }, String(bad));
  }
});

test("the ceiling applies to the requested amount, and the edge is included", () => {
  const policy = { enabled: true, maxMinor: 20_000 };
  assert.equal(shouldAutoApprove(policy, 20_000), true);
  assert.equal(shouldAutoApprove(policy, 20_001), false);
  assert.equal(shouldAutoApprove({ enabled: true, maxMinor: null }, 99_999_999), true);
  assert.equal(shouldAutoApprove({ enabled: false, maxMinor: null }, 1), false);
});
