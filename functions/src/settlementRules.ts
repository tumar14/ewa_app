// Pure settlement / reconciliation rules (blueprint sections 6, 7, 10). No Firebase
// imports: unit-tested in settlementRules.test.ts. All money is integer minor units.

export type SettlementStatus =
  | "DRAFT" // created from a payroll run, employer has not confirmed deductions
  | "DUE" // deductions confirmed, no funds received
  | "PARTIALLY_SETTLED" // some, not all, funds received
  | "SETTLED" // confirmed amount received and nothing open
  | "EXCEPTION" // at least one unresolved discrepancy
  | "CANCELLED";

export type ExceptionType =
  | "DEDUCTION_SHORTFALL" // payroll deducted less than expected
  | "DEDUCTION_EXCESS" // payroll deducted more than expected
  | "OVERPAYMENT" // received more than the confirmed deductions
  | "INSUFFICIENT_PAY"; // an employee's final pay did not cover their draws

export interface ReconException {
  id: string;
  type: ExceptionType;
  status: "open" | "resolved";
  expectedMinor: number;
  actualMinor: number;
  differenceMinor: number;
  employeeId?: string;
  resolutionNote?: string;
}

export const DEDUCTION_MISMATCH_ID = "deduction_mismatch";
export const OVERPAYMENT_ID = "overpayment";

export interface Figures {
  expectedMinor: number;
  confirmedMinor: number | null;
  receivedMinor: number;
}

export function outstandingMinor(f: Figures): number {
  return f.expectedMinor - f.receivedMinor;
}

export function settlementStatus(
  f: Figures,
  openExceptions: number,
  cancelled: boolean,
): SettlementStatus {
  if (cancelled) return "CANCELLED";
  if (openExceptions > 0) return "EXCEPTION";
  if (f.confirmedMinor === null) return "DRAFT";
  if (f.receivedMinor === 0 && f.confirmedMinor > 0) return "DUE";
  if (f.receivedMinor < f.confirmedMinor) return "PARTIALLY_SETTLED";
  return "SETTLED";
}

export interface ReconResult {
  /** Exception documents to write (new, reopened or auto-resolved). */
  upserts: ReconException[];
  /** Open exceptions after applying `upserts` to `existing`. */
  openCount: number;
}

/**
 * Derives the deduction-mismatch and overpayment exceptions from the current
 * figures and the existing exception docs. A discrepancy a person has already
 * resolved stays resolved until its numbers change; one that no longer exists
 * is closed automatically. INSUFFICIENT_PAY exceptions are only ever created
 * with the settlement and closed by a person, so they pass through untouched.
 */
export function reconcile(f: Figures, existing: ReconException[]): ReconResult {
  const byId = new Map(existing.map((e) => [e.id, e]));
  const upserts: ReconException[] = [];

  const ensure = (
    id: string,
    needed: { type: ExceptionType; expectedMinor: number; actualMinor: number } | null,
  ) => {
    const current = byId.get(id);
    if (needed === null) {
      if (current && current.status === "open") {
        const closed: ReconException = {
          ...current,
          status: "resolved",
          resolutionNote: "Closed automatically: the figures now agree.",
        };
        byId.set(id, closed);
        upserts.push(closed);
      }
      return;
    }
    const differenceMinor = needed.actualMinor - needed.expectedMinor;
    const unchanged =
      current &&
      current.type === needed.type &&
      current.expectedMinor === needed.expectedMinor &&
      current.actualMinor === needed.actualMinor;
    if (unchanged) return; // keeps a person's resolution, or an already-open item
    const next: ReconException = {
      id,
      type: needed.type,
      status: "open",
      expectedMinor: needed.expectedMinor,
      actualMinor: needed.actualMinor,
      differenceMinor,
    };
    byId.set(id, next);
    upserts.push(next);
  };

  const { expectedMinor, confirmedMinor, receivedMinor } = f;

  ensure(
    DEDUCTION_MISMATCH_ID,
    confirmedMinor !== null && confirmedMinor !== expectedMinor
      ? {
          type: confirmedMinor < expectedMinor ? "DEDUCTION_SHORTFALL" : "DEDUCTION_EXCESS",
          expectedMinor,
          actualMinor: confirmedMinor,
        }
      : null,
  );
  ensure(
    OVERPAYMENT_ID,
    confirmedMinor !== null && receivedMinor > confirmedMinor
      ? { type: "OVERPAYMENT", expectedMinor: confirmedMinor, actualMinor: receivedMinor }
      : null,
  );

  const openCount = [...byId.values()].filter((e) => e.status === "open").length;
  return { upserts, openCount };
}

/** Same Eswatini local date as the pay cycle maths (UTC+2), as YYYYMMDD. */
export function localDateStamp(ms: number): string {
  const d = new Date(ms + 2 * 3_600_000);
  const p = (n: number) => String(n).padStart(2, "0");
  return `${d.getUTCFullYear()}${p(d.getUTCMonth() + 1)}${p(d.getUTCDate())}`;
}

/** Unique, human-typable payment reference, e.g. EWA-ABC123-20261031-K3F9. */
export function settlementReference(shortCode: string, cycleEndMs: number, runId: string): string {
  return `EWA-${shortCode}-${localDateStamp(cycleEndMs)}-${runId.slice(0, 4).toUpperCase()}`;
}

const TXN_ID_PATTERN = /^[A-Za-z0-9_-]{4,100}$/;

/** Provider transaction ids become Firestore document ids, so keep them strict. */
export function isValidTransactionId(id: string): boolean {
  return TXN_ID_PATTERN.test(id);
}
