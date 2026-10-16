import { DocumentReference, Timestamp, Transaction } from "firebase-admin/firestore";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { db, requireCompanyAdmin, requirePlatformAdmin } from "./common";
import {
  ReconException,
  isValidTransactionId,
  outstandingMinor,
  reconcile,
  settlementReference,
  settlementStatus,
} from "./settlementRules";
import { formatMinor } from "./drawRules";

const BATCH_SIZE = 400;

const isWholeMinor = (n: unknown): n is number => typeof n === "number" && Number.isSafeInteger(n);

function settlementRef(companyId: string, settlementId: string): DocumentReference {
  return db.collection("companies").doc(companyId).collection("settlements").doc(settlementId);
}

async function readExceptions(tx: Transaction, settlement: DocumentReference): Promise<ReconException[]> {
  const snap = await tx.get(settlement.collection("exceptions"));
  return snap.docs.map((d) => ({ ...(d.data() as Omit<ReconException, "id">), id: d.id }));
}

/**
 * Applies new figures to a settlement inside a transaction: re-derives the
 * discrepancy exceptions, recomputes status and outstanding, and writes
 * everything plus an audit entry. The caller has already done all its reads.
 */
function writeReconciled(
  tx: Transaction,
  ref: DocumentReference,
  companyId: string,
  figures: { expectedMinor: number; confirmedMinor: number | null; receivedMinor: number },
  existing: ReconException[],
  cancelled: boolean,
  extraSettlementFields: Record<string, unknown>,
  audit: Record<string, unknown>,
): string {
  const { upserts, openCount } = reconcile(figures, existing);
  for (const e of upserts) {
    const { id, ...fields } = e;
    tx.set(ref.collection("exceptions").doc(id), { ...fields, updatedAt: Timestamp.now() }, { merge: true });
  }
  const status = settlementStatus(figures, openCount, cancelled);
  tx.update(ref, {
    ...extraSettlementFields,
    confirmedMinor: figures.confirmedMinor,
    receivedMinor: figures.receivedMinor,
    outstandingMinor: outstandingMinor(figures),
    openExceptionCount: openCount,
    status,
    updatedAt: Timestamp.now(),
  });
  tx.set(db.collection("companies").doc(companyId).collection("audit_log").doc(), {
    ...audit,
    settlementId: ref.id,
    resultingStatus: status,
    timestamp: Timestamp.now(),
  });
  return status;
}

/**
 * Creates the settlement for a completed payroll run: the amount the employer
 * is expected to remit, one item per employee with a deduction, and an
 * exception for every employee whose pay did not cover their draws. One
 * settlement per run (its id is the run id), so repeating the call is safe.
 */
export const createSettlement = onCall(async (request) => {
  const companyId = await requireCompanyAdmin(request);
  const { payrollRunId } = request.data as { payrollRunId?: string };
  if (!payrollRunId) throw new HttpsError("invalid-argument", "payrollRunId is required.");

  const companyRef = db.collection("companies").doc(companyId);
  const ref = settlementRef(companyId, payrollRunId);

  const [runSnap, existing, companySnap] = await Promise.all([
    companyRef.collection("payroll_runs").doc(payrollRunId).get(),
    ref.get(),
    companyRef.get(),
  ]);
  if (existing.exists) return { ok: true, settlementId: ref.id, created: false };

  const run = runSnap.data();
  if (!run) throw new HttpsError("not-found", "Payroll run not found.");
  if (run.status !== "completed") {
    throw new HttpsError("failed-precondition", "The payroll run has not finished.");
  }
  const lines = (run.lines ?? []) as Array<{
    employeeId: string;
    accruedMinor?: number;
    drawsDeductedMinor?: number;
    netPayoutMinor?: number;
    shortfallMinor?: number;
  }>;
  if (lines.some((l) => !isWholeMinor(l.drawsDeductedMinor))) {
    throw new HttpsError("failed-precondition", "This payroll run has no cent-based figures. Run payroll again.");
  }

  const withDraws = lines.filter((l) => (l.drawsDeductedMinor as number) > 0);
  const expectedMinor = withDraws.reduce((sum, l) => sum + (l.drawsDeductedMinor as number), 0);
  if (expectedMinor <= 0) {
    throw new HttpsError("failed-precondition", "This payroll run deducted no draws, so there is nothing to settle.");
  }

  const company = companySnap.data() ?? {};
  const cycleEnd = run.cycleEnd as Timestamp;
  const now = Timestamp.now();

  // Children first (deterministic ids, so a retry after a partial failure just
  // rewrites them); the settlement document is the commit point.
  const children: Array<{ ref: DocumentReference; data: Record<string, unknown> }> = [];
  for (const l of withDraws) {
    children.push({
      ref: ref.collection("items").doc(l.employeeId),
      data: {
        employeeId: l.employeeId,
        accruedMinor: l.accruedMinor ?? 0,
        drawsDeductedMinor: l.drawsDeductedMinor,
        netPayoutMinor: l.netPayoutMinor ?? 0,
        shortfallMinor: l.shortfallMinor ?? 0,
      },
    });
    if ((l.shortfallMinor ?? 0) > 0) {
      children.push({
        ref: ref.collection("exceptions").doc(`insufficient_pay_${l.employeeId}`),
        data: {
          type: "INSUFFICIENT_PAY",
          status: "open",
          employeeId: l.employeeId,
          expectedMinor: l.drawsDeductedMinor,
          actualMinor: l.accruedMinor ?? 0,
          differenceMinor: -(l.shortfallMinor as number),
          updatedAt: now,
        },
      });
    }
  }
  for (let i = 0; i < children.length; i += BATCH_SIZE) {
    const batch = db.batch();
    for (const c of children.slice(i, i + BATCH_SIZE)) batch.set(c.ref, c.data);
    await batch.commit();
  }

  const openCount = children.filter((c) => c.data.type === "INSUFFICIENT_PAY").length;
  const figures = { expectedMinor, confirmedMinor: null, receivedMinor: 0 };
  await db.runTransaction(async (tx) => {
    if ((await tx.get(ref)).exists) return;
    tx.create(ref, {
      payrollRunId,
      reference: settlementReference(String(company.shortCode ?? "CO"), cycleEnd.toMillis(), payrollRunId),
      currency: company.currency ?? "SZL",
      cycleStart: run.cycleStart,
      cycleEnd,
      expectedMinor,
      confirmedMinor: null,
      receivedMinor: 0,
      outstandingMinor: outstandingMinor(figures),
      itemCount: withDraws.length,
      openExceptionCount: openCount,
      status: settlementStatus(figures, openCount, false),
      createdAt: now,
      createdBy: request.auth!.uid,
    });
    tx.set(companyRef.collection("audit_log").doc(), {
      type: "settlement_created",
      settlementId: ref.id,
      payrollRunId,
      expectedMinor,
      performedBy: request.auth!.uid,
      timestamp: now,
    });
  });

  return { ok: true, settlementId: ref.id, created: true };
});

/**
 * Records the total payroll actually deducted for the cycle (blueprint step
 * "payroll sends a report confirming what was actually deducted"). A figure
 * that differs from the expected amount opens a discrepancy exception.
 */
export const confirmDeductions = onCall(async (request) => {
  const companyId = await requireCompanyAdmin(request);
  const { settlementId, confirmedMinor } = request.data as {
    settlementId?: string;
    confirmedMinor?: unknown;
  };
  if (!settlementId) throw new HttpsError("invalid-argument", "settlementId is required.");
  if (!isWholeMinor(confirmedMinor) || confirmedMinor < 0) {
    throw new HttpsError("invalid-argument", "confirmedMinor must be a whole number of cents, zero or more.");
  }

  const ref = settlementRef(companyId, settlementId);
  const status = await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const s = snap.data();
    if (!s) throw new HttpsError("not-found", "Settlement not found.");
    if (s.status === "CANCELLED") throw new HttpsError("failed-precondition", "Settlement is cancelled.");
    const existing = await readExceptions(tx, ref);

    return writeReconciled(
      tx,
      ref,
      companyId,
      { expectedMinor: s.expectedMinor, confirmedMinor, receivedMinor: s.receivedMinor },
      existing,
      false,
      { confirmedAt: Timestamp.now(), confirmedBy: request.auth!.uid },
      {
        type: "settlement_deductions_confirmed",
        expectedMinor: s.expectedMinor,
        confirmedMinor,
        performedBy: request.auth!.uid,
      },
    );
  });
  return { ok: true, status };
});

/**
 * Platform operator records a verified incoming payment against a settlement
 * reference (MVP: read off the bank statement). The platform admin never reads
 * company data; they supply the company code and reference and get back only
 * the resulting status. The provider transaction id is the idempotency key: the
 * same bank line submitted twice is counted once.
 */
export const recordSettlementPayment = onCall(async (request) => {
  await requirePlatformAdmin(request);
  const { shortCode, reference, amountMinor, currency, providerTransactionId } = request.data as {
    shortCode?: string;
    reference?: string;
    amountMinor?: unknown;
    currency?: string;
    providerTransactionId?: string;
  };
  if (!shortCode?.trim() || !reference?.trim() || !currency?.trim()) {
    throw new HttpsError("invalid-argument", "shortCode, reference and currency are required.");
  }
  if (!isWholeMinor(amountMinor) || amountMinor <= 0) {
    throw new HttpsError("invalid-argument", "amountMinor must be a positive whole number of cents.");
  }
  if (!providerTransactionId || !isValidTransactionId(providerTransactionId)) {
    throw new HttpsError(
      "invalid-argument",
      "providerTransactionId must be 4-100 letters, digits, dashes or underscores (the bank's own transaction id).",
    );
  }

  const codeSnap = await db.collection("company_codes").doc(shortCode.trim().toUpperCase()).get();
  const companyId = codeSnap.data()?.companyId as string | undefined;
  if (!companyId) throw new HttpsError("not-found", "No company with that code.");

  const companyRef = db.collection("companies").doc(companyId);
  const matches = await companyRef.collection("settlements").where("reference", "==", reference.trim()).limit(2).get();
  if (matches.size !== 1) {
    throw new HttpsError("not-found", "No single settlement matches that reference.");
  }
  const ref = matches.docs[0].ref;
  const paymentRef = companyRef.collection("payment_transactions").doc(providerTransactionId);

  const outcome = await db.runTransaction(async (tx) => {
    const [snap, paymentSnap] = await Promise.all([tx.get(ref), tx.get(paymentRef)]);
    const s = snap.data();
    if (!s) throw new HttpsError("not-found", "Settlement not found.");

    if (paymentSnap.exists) {
      const p = paymentSnap.data()!;
      if (p.settlementId !== ref.id || p.amountMinor !== amountMinor) {
        throw new HttpsError(
          "already-exists",
          "That transaction id was already recorded for a different payment.",
        );
      }
      return { duplicate: true, status: s.status, receivedMinor: s.receivedMinor, outstandingMinor: s.outstandingMinor };
    }

    if (s.status === "CANCELLED") throw new HttpsError("failed-precondition", "Settlement is cancelled.");
    if (s.confirmedMinor === null) {
      throw new HttpsError("failed-precondition", "The employer has not confirmed the payroll deductions yet.");
    }
    if (s.currency !== currency.trim().toUpperCase()) {
      throw new HttpsError("failed-precondition", `Currency mismatch: settlement is in ${s.currency}.`);
    }
    const existing = await readExceptions(tx, ref);

    const receivedMinor = s.receivedMinor + amountMinor;
    tx.create(paymentRef, {
      settlementId: ref.id,
      reference: s.reference,
      amountMinor,
      currency: s.currency,
      source: "bank_statement_manual",
      providerTransactionId,
      verificationStatus: "verified_manual",
      recordedBy: request.auth!.uid,
      recordedAt: Timestamp.now(),
    });
    const status = writeReconciled(
      tx,
      ref,
      companyId,
      { expectedMinor: s.expectedMinor, confirmedMinor: s.confirmedMinor, receivedMinor },
      existing,
      false,
      {},
      {
        type: "settlement_payment_recorded",
        amountMinor,
        providerTransactionId,
        performedBy: request.auth!.uid,
      },
    );
    return {
      duplicate: false,
      status,
      receivedMinor,
      outstandingMinor: outstandingMinor({ expectedMinor: s.expectedMinor, confirmedMinor: s.confirmedMinor, receivedMinor }),
    };
  });

  return { ok: true, ...outcome, receivedDisplay: formatMinor(outcome.receivedMinor) };
});

/** Closes an open exception with a written note; the note and person are kept for audit. */
export const resolveException = onCall(async (request) => {
  const companyId = await requireCompanyAdmin(request);
  const { settlementId, exceptionId, note } = request.data as {
    settlementId?: string;
    exceptionId?: string;
    note?: string;
  };
  if (!settlementId || !exceptionId) {
    throw new HttpsError("invalid-argument", "settlementId and exceptionId are required.");
  }
  const text = typeof note === "string" ? note.trim() : "";
  if (text.length < 5 || text.length > 500) {
    throw new HttpsError("invalid-argument", "Add a resolution note of 5 to 500 characters.");
  }

  const ref = settlementRef(companyId, settlementId);
  const status = await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const s = snap.data();
    if (!s) throw new HttpsError("not-found", "Settlement not found.");
    const existing = await readExceptions(tx, ref);
    const target = existing.find((e) => e.id === exceptionId);
    if (!target) throw new HttpsError("not-found", "Exception not found.");
    if (target.status !== "open") throw new HttpsError("failed-precondition", "Exception is already resolved.");

    const updated = existing.map((e) => (e.id === exceptionId ? { ...e, status: "resolved" as const } : e));
    tx.set(
      ref.collection("exceptions").doc(exceptionId),
      { status: "resolved", resolutionNote: text, resolvedBy: request.auth!.uid, resolvedAt: Timestamp.now() },
      { merge: true },
    );
    const figures = { expectedMinor: s.expectedMinor, confirmedMinor: s.confirmedMinor, receivedMinor: s.receivedMinor };
    const { upserts, openCount } = reconcile(figures, updated);
    // Resolving can only close things, never open new ones: reconcile sees the
    // resolved doc with unchanged numbers and leaves it alone.
    for (const e of upserts) {
      const { id, ...fields } = e;
      tx.set(ref.collection("exceptions").doc(id), { ...fields, updatedAt: Timestamp.now() }, { merge: true });
    }
    const newStatus = settlementStatus(figures, openCount, s.status === "CANCELLED");
    tx.update(ref, { status: newStatus, openExceptionCount: openCount, updatedAt: Timestamp.now() });
    tx.set(db.collection("companies").doc(companyId).collection("audit_log").doc(), {
      type: "settlement_exception_resolved",
      settlementId,
      exceptionId,
      note: text,
      resultingStatus: newStatus,
      performedBy: request.auth!.uid,
      timestamp: Timestamp.now(),
    });
    return newStatus;
  });
  return { ok: true, status };
});

/** Cancels a settlement that has received no money. The payroll run itself is unaffected. */
export const cancelSettlement = onCall(async (request) => {
  const companyId = await requireCompanyAdmin(request);
  const { settlementId, reason } = request.data as { settlementId?: string; reason?: string };
  if (!settlementId) throw new HttpsError("invalid-argument", "settlementId is required.");
  const text = typeof reason === "string" ? reason.trim() : "";
  if (text.length < 5 || text.length > 500) {
    throw new HttpsError("invalid-argument", "Add a reason of 5 to 500 characters.");
  }

  const ref = settlementRef(companyId, settlementId);
  await db.runTransaction(async (tx) => {
    const s = (await tx.get(ref)).data();
    if (!s) throw new HttpsError("not-found", "Settlement not found.");
    if (s.status === "CANCELLED") throw new HttpsError("failed-precondition", "Settlement is already cancelled.");
    if (s.receivedMinor > 0) {
      throw new HttpsError("failed-precondition", "Money has already been received against this settlement.");
    }
    tx.update(ref, {
      status: "CANCELLED",
      cancelledReason: text,
      cancelledBy: request.auth!.uid,
      cancelledAt: Timestamp.now(),
      updatedAt: Timestamp.now(),
    });
    tx.set(db.collection("companies").doc(companyId).collection("audit_log").doc(), {
      type: "settlement_cancelled",
      settlementId,
      reason: text,
      performedBy: request.auth!.uid,
      timestamp: Timestamp.now(),
    });
  });
  return { ok: true };
});
