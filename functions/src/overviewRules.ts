// Pure rules for the platform admin's overview. No Firebase imports: unit-tested in
// overviewRules.test.ts. The overview carries counts and one company-level money
// figure only; never a name, an employee or an individual amount.

/** Settlement statuses where the company still owes money (DRAFT is not confirmed yet). */
export const OWED_STATUSES: readonly string[] = ["DUE", "PARTIALLY_SETTLED", "EXCEPTION"];

export interface SettlementLite {
  status?: unknown;
  outstandingMinor?: unknown;
}

/** What a company still owes across its settlements, and how many settlements that is. */
export function owedSummary(settlements: readonly SettlementLite[]): { owedMinor: number; openSettlements: number } {
  let owedMinor = 0;
  let openSettlements = 0;
  for (const s of settlements) {
    if (typeof s.status !== "string" || !OWED_STATUSES.includes(s.status)) continue;
    openSettlements++;
    // An overpayment is negative; it never reduces what another settlement is owed.
    if (typeof s.outstandingMinor === "number" && Number.isFinite(s.outstandingMinor) && s.outstandingMinor > 0) {
      owedMinor += Math.round(s.outstandingMinor);
    }
  }
  return { owedMinor, openSettlements };
}

export interface CompanyOverview {
  companyId: string;
  name: string;
  shortCode: string;
  currency: string;
  active: boolean;
  employees: number;
  activeEmployees: number;
  activeWorkers: number;
  advancesThisCycle: number;
  pendingApproval: number;
  awaitingPayout: number;
  openSettlements: number;
  owedMinor: number;
}

export interface OverviewTotals {
  companies: number;
  activeCompanies: number;
  activeEmployees: number;
  activeWorkers: number;
  advancesThisCycle: number;
  pendingApproval: number;
  awaitingPayout: number;
  openSettlements: number;
}

/** Counts across companies. Money is not added up: companies can use different currencies. */
export function totalsOf(companies: readonly CompanyOverview[]): OverviewTotals {
  const t: OverviewTotals = {
    companies: companies.length,
    activeCompanies: 0,
    activeEmployees: 0,
    activeWorkers: 0,
    advancesThisCycle: 0,
    pendingApproval: 0,
    awaitingPayout: 0,
    openSettlements: 0,
  };
  for (const c of companies) {
    if (c.active) t.activeCompanies++;
    t.activeEmployees += c.activeEmployees;
    t.activeWorkers += c.activeWorkers;
    t.advancesThisCycle += c.advancesThisCycle;
    t.pendingApproval += c.pendingApproval;
    t.awaitingPayout += c.awaitingPayout;
    t.openSettlements += c.openSettlements;
  }
  return t;
}
