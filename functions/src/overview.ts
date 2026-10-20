import { Query, Timestamp } from "firebase-admin/firestore";
import { onCall } from "firebase-functions/v2/https";
import { db, requirePlatformAdmin } from "./common";
import { defaultAppSettings } from "./defaults";
import { currentCycleStartMs, PaydayRule } from "./drawRules";
import { CompanyOverview, OWED_STATUSES, owedSummary, totalsOf } from "./overviewRules";

const MAX_COMPANIES = 300;

/**
 * Counts for the platform admin: per company, how many employees and active
 * workers, advances this pay cycle, requests waiting for approval or payout, and
 * what the company still owes in open settlements. The counts come from
 * Firestore aggregation queries run here with the Admin SDK; the response holds
 * numbers and the company's public details only. It never carries an employee's
 * name or an individual amount, so it does not widen the platform admin's access
 * to personal data (firestore.rules still deny them those collections).
 */
export const platformOverview = onCall(async (request) => {
  await requirePlatformAdmin(request);

  const nowMs = Date.now();
  const companies = await db.collection("companies").orderBy("name").limit(MAX_COMPANIES + 1).get();
  const truncated = companies.size > MAX_COMPANIES;
  const defaults = defaultAppSettings("");

  const rows: CompanyOverview[] = await Promise.all(
    companies.docs.slice(0, MAX_COMPANIES).map(async (doc) => {
      const company = doc.data();
      const ref = doc.ref;
      const employees = ref.collection("employees");
      const draws = ref.collection("draw_requests");
      const count = async (q: Query) => (await q.count().get()).data().count;

      const settingsSnap = await ref.collection("settings").doc("app").get();
      const settings = { ...defaults, ...(settingsSnap.data() ?? {}) };
      const rule = { ...defaults.paydayRule, ...(settings.paydayRule ?? {}) } as PaydayRule;
      const cycleStart = Timestamp.fromMillis(currentCycleStartMs(rule, nowMs));

      const [total, activeEmployees, activeWorkers, advancesThisCycle, pendingApproval, awaitingPayout, settlements] =
        await Promise.all([
          count(employees),
          count(employees.where("active", "==", true)),
          count(employees.where("active", "==", true).where("role", "==", "worker")),
          count(draws.where("createdAt", ">=", cycleStart)),
          count(draws.where("status", "==", "pending")),
          count(draws.where("status", "==", "approved").where("disbursementStatus", "==", "pending")),
          ref.collection("settlements").where("status", "in", [...OWED_STATUSES]).get(),
        ]);
      const owed = owedSummary(settlements.docs.map((s) => s.data()));

      return {
        companyId: doc.id,
        name: String(company.name ?? ""),
        shortCode: String(company.shortCode ?? ""),
        currency: String(company.currency ?? ""),
        active: company.active !== false,
        employees: total,
        activeEmployees,
        activeWorkers,
        advancesThisCycle,
        pendingApproval,
        awaitingPayout,
        openSettlements: owed.openSettlements,
        owedMinor: owed.owedMinor,
      };
    }),
  );

  return { generatedAtMs: nowMs, truncated, totals: totalsOf(rows), companies: rows };
});
