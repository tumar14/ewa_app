import { test } from "node:test";
import assert from "node:assert/strict";
import { CompanyOverview, owedSummary, totalsOf } from "./overviewRules";

test("only settlements where money is still owed count", () => {
  const r = owedSummary([
    { status: "DUE", outstandingMinor: 10_000 },
    { status: "PARTIALLY_SETTLED", outstandingMinor: 2_500 },
    { status: "EXCEPTION", outstandingMinor: 700 },
    { status: "DRAFT", outstandingMinor: 99_999 },
    { status: "SETTLED", outstandingMinor: 0 },
    { status: "CANCELLED", outstandingMinor: 5_000 },
  ]);
  assert.deepEqual(r, { owedMinor: 13_200, openSettlements: 3 });
});

test("an overpayment never reduces what is owed elsewhere", () => {
  assert.deepEqual(
    owedSummary([{ status: "EXCEPTION", outstandingMinor: -500 }, { status: "DUE", outstandingMinor: 1_000 }]),
    { owedMinor: 1_000, openSettlements: 2 },
  );
});

test("malformed settlement data is ignored, not trusted", () => {
  assert.deepEqual(
    owedSummary([
      { status: "DUE", outstandingMinor: "1000" },
      { status: "DUE", outstandingMinor: NaN },
      { status: "DUE" },
      { status: 5, outstandingMinor: 100 },
      {},
    ]),
    { owedMinor: 0, openSettlements: 3 },
  );
  assert.deepEqual(owedSummary([]), { owedMinor: 0, openSettlements: 0 });
});

const company = (over: Partial<CompanyOverview>): CompanyOverview => ({
  companyId: "c", name: "C", shortCode: "C", currency: "SZL", active: true,
  employees: 0, activeEmployees: 0, activeWorkers: 0, advancesThisCycle: 0,
  pendingApproval: 0, awaitingPayout: 0, openSettlements: 0, owedMinor: 0,
  ...over,
});

test("totals add up counts across companies and leave money alone", () => {
  const t = totalsOf([
    company({ activeEmployees: 10, activeWorkers: 8, advancesThisCycle: 5, pendingApproval: 2, awaitingPayout: 1, openSettlements: 1, owedMinor: 500 }),
    company({ active: false, activeEmployees: 4, activeWorkers: 3, advancesThisCycle: 1, openSettlements: 2, owedMinor: 900, currency: "ZAR" }),
  ]);
  assert.deepEqual(t, {
    companies: 2, activeCompanies: 1, activeEmployees: 14, activeWorkers: 11,
    advancesThisCycle: 6, pendingApproval: 2, awaitingPayout: 1, openSettlements: 3,
  });
  assert.equal("owedMinor" in t, false);
  assert.equal(totalsOf([]).companies, 0);
});
