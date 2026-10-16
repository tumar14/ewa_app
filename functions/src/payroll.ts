import { DocumentReference, Timestamp } from "firebase-admin/firestore";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { DrawRequestDoc, EmployeeDoc, db, requireCompanyAdmin } from "./common";
import { SessionSpan, accruedMinor } from "./drawRules";

const LOCK_TTL_MS = 15 * 60_000;
const BATCH_SIZE = 400;
const FIRST_RUN_LOOKBACK_MS = 14 * 86_400_000;

interface PayrollLine {
  employeeId: string;
  accruedMinor: number;
  drawsDeductedMinor: number;
  netPayoutMinor: number; // never negative
  shortfallMinor: number; // draws the cycle's wages could not cover
  drawIds: string[];
}

/**
 * Marks every draw in the run as settled by it, then flips the run to
 * "completed". Safe to repeat: it only sets fields to values they should end
 * up with, so a run interrupted halfway is finished by calling this again.
 */
async function applyRun(companyRef: DocumentReference, runId: string, uid: string): Promise<void> {
  const runRef = companyRef.collection("payroll_runs").doc(runId);
  const run = (await runRef.get()).data();
  if (!run) throw new HttpsError("not-found", "Payroll run not found.");

  const lines = (run.lines ?? []) as PayrollLine[];
  const drawIds = lines.flatMap((l) => l.drawIds);
  const drawsCollection = companyRef.collection("draw_requests");

  for (let i = 0; i < drawIds.length; i += BATCH_SIZE) {
    const batch = db.batch();
    for (const id of drawIds.slice(i, i + BATCH_SIZE)) {
      batch.update(drawsCollection.doc(id), { payrollRunId: runId });
    }
    await batch.commit();
  }

  const completedAt = Timestamp.now();
  const finish = db.batch();
  finish.update(runRef, { status: "completed", completedAt });
  finish.set(companyRef.collection("audit_log").doc(), {
    type: "payroll_run",
    payrollRunId: runId,
    drawCount: drawIds.length,
    totals: run.totals ?? null,
    performedBy: uid,
    timestamp: completedAt,
  });
  await finish.commit();
}

/**
 * Runs a full payroll cycle (spec section 4 step 4 / section 9) for the
 * caller's own company: for every active employee, sums accrued wages for
 * the cycle from time_sessions, nets off all outstanding (payrollRunId ==
 * null) approved draws, and settles those draws so they drop off the next
 * cycle's cap.
 *
 * Two runs cannot overlap (a lock document, expiring after 15 minutes if the
 * function dies). The run document is written first with status "applying"
 * and the ids of the draws it covers; draws are marked afterwards. If that
 * is interrupted, the next call finishes the same run instead of starting a
 * new one, so a draw is never deducted twice or left pointing at a run that
 * does not exist.
 */
export const runPayroll = onCall(async (request) => {
  const companyId = await requireCompanyAdmin(request);
  const uid = request.auth!.uid;
  const companyRef = db.collection("companies").doc(companyId);
  const lockRef = companyRef.collection("payroll_state").doc("lock");

  const startedAtMs = Date.now();
  await db.runTransaction(async (tx) => {
    const lock = (await tx.get(lockRef)).data();
    if (lock?.status === "running" && startedAtMs - (lock.startedAtMs as number) < LOCK_TTL_MS) {
      throw new HttpsError("aborted", "A payroll run is already in progress. Try again in a few minutes.");
    }
    tx.set(lockRef, { status: "running", startedAtMs, startedBy: uid });
  });

  try {
    const interrupted = await companyRef.collection("payroll_runs").where("status", "==", "applying").get();
    if (!interrupted.empty) {
      for (const doc of interrupted.docs) await applyRun(companyRef, doc.id, uid);
      return { ok: true, payrollRunId: interrupted.docs[interrupted.docs.length - 1].id, resumed: true };
    }

    const cycleEnd = Timestamp.now();
    const previousRunSnap = await companyRef
      .collection("payroll_runs")
      .orderBy("cycleEnd", "desc")
      .limit(1)
      .get();
    const cycleStart = previousRunSnap.empty
      ? Timestamp.fromMillis(cycleEnd.toMillis() - FIRST_RUN_LOOKBACK_MS)
      : (previousRunSnap.docs[0].data().cycleEnd as Timestamp);

    const employeesSnap = await companyRef.collection("employees").get();
    const lines: PayrollLine[] = [];

    for (const employeeDoc of employeesSnap.docs) {
      const employee = employeeDoc.data() as EmployeeDoc;
      if (employee.role === "admin") continue;
      if (employee.active === false) continue; // skip deactivated employees

      const sessionsSnap = await companyRef
        .collection("time_sessions")
        .where("employeeId", "==", employeeDoc.id)
        .where("clockInTs", ">=", cycleStart)
        .where("clockOutTs", "!=", null)
        .get();
      const sessions: SessionSpan[] = sessionsSnap.docs.map((doc) => ({
        clockInMs: (doc.data().clockInTs as Timestamp).toMillis(),
        clockOutMs: (doc.data().clockOutTs as Timestamp).toMillis(),
      }));
      const accrued = accruedMinor(employee.hourlyRate, sessions, cycleEnd.toMillis());

      const drawsSnap = await companyRef
        .collection("draw_requests")
        .where("employeeId", "==", employeeDoc.id)
        .where("status", "==", "approved")
        .where("payrollRunId", "==", null)
        .get();
      const drawsDeductedMinor = drawsSnap.docs.reduce(
        (sum, doc) => sum + (doc.data() as DrawRequestDoc).totalMinor,
        0,
      );

      lines.push({
        employeeId: employeeDoc.id,
        accruedMinor: accrued,
        drawsDeductedMinor,
        netPayoutMinor: Math.max(0, accrued - drawsDeductedMinor),
        shortfallMinor: Math.max(0, drawsDeductedMinor - accrued),
        drawIds: drawsSnap.docs.map((doc) => doc.id),
      });
    }

    const totals = lines.reduce(
      (t, l) => ({
        accruedMinor: t.accruedMinor + l.accruedMinor,
        drawsDeductedMinor: t.drawsDeductedMinor + l.drawsDeductedMinor,
        netPayoutMinor: t.netPayoutMinor + l.netPayoutMinor,
        shortfallMinor: t.shortfallMinor + l.shortfallMinor,
      }),
      { accruedMinor: 0, drawsDeductedMinor: 0, netPayoutMinor: 0, shortfallMinor: 0 },
    );

    const runRef = companyRef.collection("payroll_runs").doc();
    await runRef.set({
      cycleStart,
      cycleEnd,
      status: "applying",
      lines,
      totals,
      createdBy: uid,
      createdAt: Timestamp.now(),
    });
    await applyRun(companyRef, runRef.id, uid);

    return { ok: true, payrollRunId: runRef.id };
  } finally {
    // Only release our own lock: after a long stall another run may have taken over.
    await db.runTransaction(async (tx) => {
      const lock = (await tx.get(lockRef)).data();
      if (lock?.startedAtMs === startedAtMs) {
        tx.set(lockRef, { status: "idle", releasedAtMs: Date.now() });
      }
    });
  }
});
