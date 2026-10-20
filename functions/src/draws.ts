import { DocumentReference, FieldValue, Timestamp, Transaction } from "firebase-admin/firestore";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import {
  DrawRequestDoc,
  EmployeeDoc,
  callableOptions,
  db,
  defaultAppSettings,
  notifyEmployee,
  requireActiveMember,
  requireCompanyAdmin,
} from "./common";
import {
  DrawLimits,
  PaydayRule,
  SessionSpan,
  accruedMinor,
  checkNewDraw,
  currentCycleStartMs,
  formatMinor,
  withinCap,
} from "./drawRules";
import { countableSpans, parseHoursPolicy } from "./hours";
import {
  Controls, autoApprovalAllowed, canRecordPayment, clampDrawPercent, DEFAULT_PLATFORM_DRAW_CEILING, decide,
  drawBlockedReason, needsSecondApproval, parseControls, validatePaymentReference, withinRequestRate,
} from "./controls";
import { hourBucket } from "./enquiryRules";
import { AutoApprovePolicy, parseAutoApprove, parseFeeSchedule, shouldAutoApprove, validateFeeSchedule } from "./feeSchedule";

interface DrawContext {
  hourlyRate: number;
  limits: DrawLimits;
  rule: PaydayRule;
  sessions: SessionSpan[];
  maxShiftMs: number;
  controls: Controls;
  employeeMeta: { createdAtMs: number | null; lastWorkingDayMs: number | null };
  outstanding: Array<{ id: string; amountMinor: number; createdAtMs: number }>;
  autoApprove: AutoApprovePolicy;
}

/**
 * Everything the draw rules need, read inside the caller's transaction.
 * `outstanding` is the employee's non-rejected draws not yet settled by a
 * payroll run (the same set the app counts against the cycle cap).
 */
async function readDrawContext(
  tx: Transaction,
  companyId: string,
  employeeId: string,
  employeeRef: DocumentReference,
  cycleStartMs: (rule: PaydayRule) => number,
): Promise<DrawContext> {
  const companyRef = db.collection("companies").doc(companyId);
  const defaults = defaultAppSettings("");

  const [employeeSnap, settingsSnap, platformSnap] = await Promise.all([
    tx.get(employeeRef),
    tx.get(companyRef.collection("settings").doc("app")),
    tx.get(db.collection("platform_config").doc("limits")),
  ]);
  const employee = employeeSnap.data() as EmployeeDoc | undefined;
  if (!employee) throw new HttpsError("not-found", "Employee not found.");
  if (employee.active === false) {
    throw new HttpsError("failed-precondition", "Employee account is not active.");
  }

  const settings = { ...defaults, ...(settingsSnap.data() ?? {}) };
  const rule = { ...defaults.paydayRule, ...(settings.paydayRule ?? {}) } as PaydayRule;
  const fee = parseFeeSchedule(settings);
  if (validateFeeSchedule(fee) !== null) {
    // Settings are written straight from the admin app, so never trust them blindly.
    throw new HttpsError(
      "failed-precondition",
      "This company's fee schedule is not set up correctly. Please contact HR.",
    );
  }
  // Settings are validated when saved, but the platform's ceiling is applied here too, so
  // a value written any other way still cannot lift an employee's limit above it.
  const ceiling = Number(platformSnap.data()?.maxDrawPercentCeiling ?? DEFAULT_PLATFORM_DRAW_CEILING);
  const limits: DrawLimits = {
    maxDrawPercent: clampDrawPercent(Number(settings.maxDrawPercent), ceiling),
    maxDrawsPerCycle: Number(settings.maxDrawsPerCycle),
    fee,
  };
  const startMs = cycleStartMs(rule);

  const [sessionsSnap, drawsSnap] = await Promise.all([
    tx.get(
      companyRef.collection("time_sessions")
        .where("employeeId", "==", employeeId)
        .where("clockInTs", ">=", Timestamp.fromMillis(startMs)),
    ),
    tx.get(
      companyRef.collection("draw_requests")
        .where("employeeId", "==", employeeId)
        .where("payrollRunId", "==", null),
    ),
  ]);

  const hours = parseHoursPolicy(settings);
  const sessions = countableSpans(
    sessionsSnap.docs.map((doc) => ({
      clockInMs: (doc.data().clockInTs as Timestamp).toMillis(),
      clockOutMs: (doc.data().clockOutTs as Timestamp | null | undefined)?.toMillis() ?? null,
      voided: doc.data().voided,
      reviewedAtMs: (doc.data().reviewedAt as Timestamp | null | undefined)?.toMillis() ?? null,
    })),
    hours,
  );
  const outstanding = drawsSnap.docs
    .filter((doc) => doc.data().status !== "rejected")
    .map((doc) => ({
      id: doc.id,
      amountMinor: doc.data().amountMinor as number,
      createdAtMs: (doc.data().createdAt as Timestamp | undefined)?.toMillis() ?? 0,
    }));

  return { hourlyRate: employee.hourlyRate, limits, rule, sessions, maxShiftMs: hours.maxShiftMs,
    controls: parseControls(settings),
    employeeMeta: {
      createdAtMs: (employee as EmployeeDoc).createdAt?.toMillis() ?? null,
      lastWorkingDayMs: (employee as EmployeeDoc).lastWorkingDay?.toMillis() ?? null,
    },
    outstanding, autoApprove: parseAutoApprove(settings) };
}

/**
 * Creates a pending draw request for the caller. The limits and fee are
 * decided here from live data (time sessions, settings, outstanding draws);
 * the client only supplies the amount, in whole cents. Clients cannot write
 * draw_requests directly (see firestore.rules).
 */
export const requestDraw = onCall(callableOptions, async (request) => {
  const { uid, companyId } = await requireActiveMember(request);
  const { amountMinor } = request.data as { amountMinor?: unknown };
  if (typeof amountMinor !== "number") {
    throw new HttpsError("invalid-argument", "amountMinor must be a number of cents.");
  }

  const companyRef = db.collection("companies").doc(companyId);
  const employeeRef = companyRef.collection("employees").doc(uid);
  const drawRef = companyRef.collection("draw_requests").doc();

  const result = await db.runTransaction(async (tx) => {
    const nowMs = Date.now();
    const ctx = await readDrawContext(tx, companyId, uid, employeeRef, (rule) =>
      currentCycleStartMs(rule, nowMs),
    );

    const blocked = drawBlockedReason({ nowMs, ...ctx.employeeMeta, controls: ctx.controls });
    if (blocked) throw new HttpsError("failed-precondition", blocked);

    // At most a handful of requests an hour, so a script cannot hammer the function.
    const rateRef = companyRef.collection("rate_limits").doc(`draw_${uid}_${hourBucket(nowMs)}`);
    const rateCount = ((await tx.get(rateRef)).data()?.count as number | undefined) ?? 0;
    if (!withinRequestRate(rateCount)) {
      throw new HttpsError("resource-exhausted", "You have made several requests in the last hour. Please try again later.");
    }

    const check = checkNewDraw({
      amountMinor,
      accruedMinor: accruedMinor(ctx.hourlyRate, ctx.sessions, nowMs, ctx.maxShiftMs),
      limits: ctx.limits,
      outstanding: ctx.outstanding,
    });
    if (!check.ok) throw new HttpsError("failed-precondition", check.reason);

    const now = Timestamp.fromMillis(nowMs);
    // The request already passed every check above (limits, cap, fee). If the
    // company allows it, that is all a person would have verified, so approve it
    // by policy. Paying it out stays a person's job (disburseDraw).
    const auto = shouldAutoApprove(ctx.autoApprove, amountMinor) && autoApprovalAllowed(ctx.controls, amountMinor);
    tx.set(rateRef, { count: rateCount + 1, expiresAt: Timestamp.fromMillis(nowMs + 2 * 3_600_000) });
    tx.set(drawRef, {
      employeeId: uid,
      amountMinor,
      feeMinor: check.feeMinor,
      totalMinor: check.totalMinor,
      status: auto ? "approved" : "pending",
      autoApproved: auto,
      needsSecondApproval: needsSecondApproval(ctx.controls, amountMinor),
      createdAt: now,
      decidedBy: auto ? "policy" : null,
      decidedAt: auto ? now : null,
      payrollRunId: null,
      disbursementStatus: auto ? "pending" : null,
      disbursedAt: null,
      disbursementRef: null,
      reason: null,
    });
    // Writing the employee doc makes two simultaneous requests from the same
    // person conflict, so the cap and count checks cannot both pass on stale data.
    tx.update(employeeRef, { drawRequestSeq: FieldValue.increment(1) });
    const audit = companyRef.collection("audit_log");
    tx.set(audit.doc(), {
      type: "draw_request",
      requestId: drawRef.id,
      employeeId: uid,
      amountMinor,
      feeMinor: check.feeMinor,
      timestamp: now,
    });
    if (auto) {
      tx.set(audit.doc(), {
        type: "draw_decision",
        requestId: drawRef.id,
        employeeId: uid,
        amountMinor,
        approved: true,
        auto: true,
        decidedBy: "policy",
        decidedAt: now,
        autoApproveCeilingMinor: ctx.autoApprove.maxMinor,
        timestamp: now,
      });
    }
    return { feeMinor: check.feeMinor, totalMinor: check.totalMinor, status: auto ? "approved" : "pending", amountMinor };
  });

  if (result.status === "approved") {
    await notifyEmployee(
      companyId,
      uid,
      "Advance approved",
      `Your advance of E${formatMinor(result.amountMinor)} was approved automatically. Your employer's finance team will pay it out.`,
    );
  }

  return { ok: true, requestId: drawRef.id, ...result };
});

/**
 * Approve or reject a pending draw request (spec section 4). Runs as the
 * only path that can move a request out of "pending" — the cap re-check and
 * audit log entry happen atomically here, never trusted from the client.
 * Sends a push notification to the worker on completion.
 */
export const decideDrawRequest = onCall(callableOptions, async (request) => {
  const companyId = await requireCompanyAdmin(request);
  const uid = request.auth!.uid;
  const { requestId, approve, reason } = request.data as {
    requestId: string;
    approve: boolean;
    reason?: string;
  };
  const rejectionReason =
    !approve && typeof reason === "string" && reason.trim() ? reason.trim().slice(0, 500) : null;

  const companyRef = db.collection("companies").doc(companyId);
  const drawRef = companyRef.collection("draw_requests").doc(requestId);
  let employeeId = "";
  let amountMinor = 0;
  let firstApprovalOnly = false;

  await db.runTransaction(async (tx) => {
    const [drawSnap, settingsDoc] = await Promise.all([tx.get(drawRef), tx.get(companyRef.collection("settings").doc("app"))]);
    if (!drawSnap.exists) throw new HttpsError("not-found", "Draw request not found.");
    const draw = drawSnap.data() as DrawRequestDoc;
    if (draw.status !== "pending") {
      throw new HttpsError("failed-precondition", "Request already decided.");
    }

    employeeId = draw.employeeId;
    amountMinor = draw.amountMinor;

    // Nobody decides their own advance, and a large one needs two different admins.
    const verdict = decide({
      uid,
      employeeId,
      amountMinor,
      approve: !!approve,
      firstApprovalBy: draw.firstApprovalBy ?? null,
      controls: parseControls({ ...defaultAppSettings(""), ...(settingsDoc.data() ?? {}) }),
    });
    if (!verdict.ok) throw new HttpsError("permission-denied", verdict.reason);
    firstApprovalOnly = verdict.outcome === "first_approval";

    if (approve) {
      // Re-check against live data: sessions may have been edited, the
      // employee deactivated, or other draws approved since the request.
      // Measured over the cycle the request was made in, so a request approved
      // after payday is not judged against the new, empty cycle.
      const createdMs = draw.createdAt?.toMillis() ?? Date.now();
      const employeeRef = companyRef.collection("employees").doc(employeeId);
      const ctx = await readDrawContext(tx, companyId, employeeId, employeeRef, (rule) =>
        currentCycleStartMs(rule, createdMs),
      );
      const cycleStartMs = currentCycleStartMs(ctx.rule, createdMs);
      const drawnMinor = ctx.outstanding
        .filter((d) => d.id !== requestId && d.createdAtMs >= cycleStartMs)
        .reduce((sum, d) => sum + d.amountMinor, draw.amountMinor);
      const accrued = accruedMinor(ctx.hourlyRate, ctx.sessions, Date.now(), ctx.maxShiftMs);
      if (!withinCap(accrued, ctx.limits.maxDrawPercent, drawnMinor)) {
        throw new HttpsError(
          "failed-precondition",
          "Approving this would exceed the employee's draw limit for that pay cycle. Check their time records, or reject the request.",
        );
      }
    }

    if (firstApprovalOnly) {
      tx.update(drawRef, { firstApprovalBy: uid, firstApprovalAt: Timestamp.now() });
      tx.set(companyRef.collection("audit_log").doc(), {
        type: "draw_first_approval",
        requestId,
        employeeId,
        amountMinor,
        decidedBy: uid,
        decidedAt: Timestamp.now(),
        timestamp: Timestamp.now(),
      });
      return;
    }

    tx.update(drawRef, {
      status: approve ? "approved" : "rejected",
      decidedBy: request.auth!.uid,
      decidedAt: Timestamp.now(),
      ...(approve ? { disbursementStatus: "pending" } : {}),
      ...(rejectionReason ? { reason: rejectionReason } : {}),
    });

    tx.set(companyRef.collection("audit_log").doc(), {
      type: "draw_decision",
      requestId,
      employeeId,
      amountMinor,
      approved: approve,
      decidedBy: request.auth!.uid,
      decidedAt: Timestamp.now(),
      timestamp: Timestamp.now(),
    });
  });

  if (firstApprovalOnly) return { ok: true, status: "pending", awaitingSecondApproval: true };

  await notifyEmployee(
    companyId,
    employeeId,
    approve ? "Draw Request Approved" : "Draw Request Declined",
    approve
      ? `Your advance of E${formatMinor(amountMinor)} is approved. Your employer's finance team will pay it out.`
      : `Your draw request of E${formatMinor(amountMinor)} was not approved this time.`,
  );

  return { ok: true, status: approve ? "approved" : "rejected" };
});

/**
 * Marks an approved draw as disbursed (spec section E). Records a
 * disbursement reference for audit/reconciliation and notifies the worker.
 * Actual money movement is handled by the finance team outside the app
 * (bank transfer, MTN MoMo) — this records the confirmation.
 */
export const disburseDraw = onCall(callableOptions, async (request) => {
  const companyId = await requireCompanyAdmin(request);
  const uid = request.auth!.uid;
  const { requestId, paymentReference } = request.data as { requestId: string; paymentReference?: unknown };

  // The reference from the bank or mobile-money payment, so every "paid" entry can be
  // matched to a real transaction. The app no longer invents one.
  const refProblem = validatePaymentReference(paymentReference);
  if (refProblem) throw new HttpsError("invalid-argument", refProblem);
  const reference = (paymentReference as string).trim().replace(/\s+/g, " ");

  const companyRef = db.collection("companies").doc(companyId);
  const drawRef = companyRef.collection("draw_requests").doc(requestId);
  let employeeId = "";
  let amountMinor = 0;

  await db.runTransaction(async (tx) => {
    const snap = await tx.get(drawRef);
    if (!snap.exists) throw new HttpsError("not-found", "Draw request not found.");
    const draw = snap.data() as DrawRequestDoc;
    const [settingsDoc, employeeDoc, duplicate] = await Promise.all([
      tx.get(companyRef.collection("settings").doc("app")),
      tx.get(companyRef.collection("employees").doc(draw.employeeId)),
      tx.get(companyRef.collection("draw_requests").where("disbursementRef", "==", reference).limit(1)),
    ]);
    const allowed = canRecordPayment({
      uid,
      employeeId: draw.employeeId,
      decidedBy: draw.decidedBy ?? null,
      firstApprovalBy: draw.firstApprovalBy ?? null,
      payoutChangedAtMs: (employeeDoc.data() as EmployeeDoc | undefined)?.payoutChangedAt?.toMillis() ?? null,
      nowMs: Date.now(),
      controls: parseControls({ ...defaultAppSettings(""), ...(settingsDoc.data() ?? {}) }),
    });
    if (!allowed.ok) throw new HttpsError("permission-denied", allowed.reason);
    if (!duplicate.empty && duplicate.docs[0].id !== requestId) {
      throw new HttpsError("already-exists", "That payment reference is already recorded against another advance.");
    }

    if (draw.status !== "approved") {
      throw new HttpsError("failed-precondition", "Only approved draws can be disbursed.");
    }
    if (draw.disbursementStatus === "completed") {
      throw new HttpsError("failed-precondition", "Draw already disbursed.");
    }

    employeeId = draw.employeeId;
    amountMinor = draw.amountMinor;
    const disbursementRef = reference;

    tx.update(drawRef, {
      disbursementStatus: "completed",
      disbursedAt: Timestamp.now(),
      disbursementRef,
    });

    tx.set(companyRef.collection("audit_log").doc(), {
      type: "disbursement",
      requestId,
      employeeId,
      amountMinor,
      disbursementRef,
      disbursedBy: uid,
      disbursedAt: Timestamp.now(),
      timestamp: Timestamp.now(),
    });
  });

  await notifyEmployee(
    companyId,
    employeeId,
    "Payment recorded",
    `Your employer's finance team has marked your advance of E${formatMinor(amountMinor)} as paid. Please check your account.`,
  );

  return { ok: true };
});
