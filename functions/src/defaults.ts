// Default documents for a newly created company. No Firebase imports, so both
// the Cloud Functions and scripts/seed-demo.mjs build companies the same way.
// Mirrors the Dart defaults (OrgConfig.defaults(), AppPermissions.defaults(),
// AppSettings(), RateMatrix.empty()).

// ── Defaults for a newly-created company's settings subdocs — mirror the
// Dart model defaults (OrgConfig.defaults(), AppPermissions.defaults(), the
// AppSettings()/RateMatrix.empty() constructors) so a fresh company behaves
// exactly like today's single-tenant defaults did. ──────────────────────────

export const DEFAULT_DEPARTMENTS = [
  "Cutting", "Sewing", "Finishing", "Quality Control",
  "Packing", "Warehouse", "Maintenance", "Security",
  "Administration", "Management",
];
export const DEFAULT_ROLES = ["worker", "supervisor"];

export const DEFAULT_PERMISSIONS = {
  worker: {
    drawRequests: ["view", "create"],
    approvals: [], workforce: [], payroll: [], disbursements: [],
    supervisorSignoff: [], auditLog: [], reports: [], settings: [],
  },
  supervisor: {
    drawRequests: ["view", "create"],
    approvals: ["view", "approve"],
    workforce: ["view", "edit"],
    payroll: ["view"],
    disbursements: ["view"],
    supervisorSignoff: ["view", "approve"],
    auditLog: ["view"],
    reports: ["view"],
    settings: ["view"],
  },
};

export function defaultAppSettings(companyName: string) {
  return {
    companyName,
    maxDrawPercent: 0.5,
    feePercent: 0.05,
    feeMode: "percent",
    feeTiers: [] as Array<{ upToMinor: number | null; flatMinor: number; percent: number }>,
    autoApprove: false,
    autoApproveMaxMinor: null as number | null,
    maxDrawsPerCycle: 2,
    clockSource: "manual",
    allowManualHourEdits: true,
    allowAttendanceImport: true,
    maxShiftHours: 14,
    countOnlyReviewedHours: false,
    disbursementPolicy: "bankTransfer",
    paydayRule: { type: "lastDayOfMonth", dayOfMonth: 25, weekday: 5 },
  };
}
