// Ad-hoc check of runPayroll (lock, resume, shortfall) and the settlement flow
// against the emulator suite on demo-ewa-test. Same environment as
// verify-multitenant.mjs. Run `npm run build` first.
//
// Usage (from functions/, emulator already running):
//   node scripts/verify-settlements.mjs

import { randomBytes } from "node:crypto";
import { initializeApp } from "firebase-admin/app";
import { getFirestore, Timestamp } from "firebase-admin/firestore";
import { getAuth } from "firebase-admin/auth";

process.env.FIRESTORE_EMULATOR_HOST ??= "127.0.0.1:8080";
process.env.FIREBASE_AUTH_EMULATOR_HOST ??= "127.0.0.1:9099";
process.env.GCLOUD_PROJECT ??= "demo-ewa-test";

const PROJECT_ID = process.env.GCLOUD_PROJECT;
const FUNCTIONS_BASE = `http://127.0.0.1:5001/${PROJECT_ID}/us-central1`;
const AUTH_BASE = "http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1";
const FS_BASE = `http://127.0.0.1:8080/v1/projects/${PROJECT_ID}/databases/(default)/documents`;

initializeApp({ projectId: PROJECT_ID });
const db = getFirestore();
const auth = getAuth();

let pass = 0;
let fail = 0;
function check(label, condition, detail) {
  if (condition) {
    pass++;
    console.log(`  OK  ${label}`);
  } else {
    fail++;
    console.log(`FAIL  ${label}${detail ? ` — ${detail}` : ""}`);
  }
}

async function call(name, data, idToken) {
  const res = await fetch(`${FUNCTIONS_BASE}/${name}`, {
    method: "POST",
    headers: { "Content-Type": "application/json", ...(idToken ? { Authorization: `Bearer ${idToken}` } : {}) },
    body: JSON.stringify({ data }),
  });
  return { status: res.status, body: await res.json() };
}
const errStatus = (r) => r.body?.error?.status;
const result = (r) => r.body?.result;
const hex = (n = 3) => randomBytes(n).toString("hex");

async function makeUser(email, claims) {
  const password = randomBytes(12).toString("hex");
  const created = await fetch(`${AUTH_BASE}/accounts:signUp?key=fake-key`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ email, password, returnSecureToken: true }),
  }).then((r) => r.json());
  await auth.setCustomUserClaims(created.localId, claims);
  const signedIn = await fetch(`${AUTH_BASE}/accounts:signInWithPassword?key=fake-key`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ email, password, returnSecureToken: true }),
  }).then((r) => r.json());
  return { uid: created.localId, idToken: signedIn.idToken };
}

async function seedCompany(label) {
  const ref = db.collection("companies").doc();
  const shortCode = `T${hex(3).toUpperCase()}`;
  await ref.set({ name: label, shortCode, currency: "SZL", active: true });
  await db.collection("company_codes").doc(shortCode).set({ companyId: ref.id });
  return { ref, id: ref.id, shortCode };
}

// A worker with 3 closed hours at E50/h (= 15,000 cents accrued) and one approved
// draw of the given total (cents), all inside the payroll lookback window.
async function seedWorker(co, drawTotalMinor, { withDraw = true } = {}) {
  const user = await makeUser(`w.${hex()}@example.test`, { companyId: co.id, platformAdmin: false });
  await co.ref.collection("employees").doc(user.uid).set({ name: "Worker", role: "worker", hourlyRate: 50, active: true });
  const now = Date.now();
  await co.ref.collection("time_sessions").add({
    employeeId: user.uid,
    clockInTs: Timestamp.fromMillis(now - 4 * 3_600_000),
    clockOutTs: Timestamp.fromMillis(now - 1 * 3_600_000),
  });
  let drawId = null;
  if (withDraw) {
    const amount = Math.round(drawTotalMinor / 1.05);
    const ref = await co.ref.collection("draw_requests").add({
      employeeId: user.uid,
      amountMinor: amount,
      feeMinor: drawTotalMinor - amount,
      totalMinor: drawTotalMinor,
      status: "approved",
      createdAt: Timestamp.now(),
      payrollRunId: null,
      disbursementStatus: "completed",
    });
    drawId = ref.id;
  }
  return { ...user, drawId };
}

async function fsGet(path, token) {
  return fetch(`${FS_BASE}/${path}`, { headers: { Authorization: `Bearer ${token}` } });
}

async function main() {
  console.log(`Running against ${PROJECT_ID}\n`);

  const co = await seedCompany("Settle Co");
  const admin = await makeUser(`a.${hex()}@example.test`, { companyId: co.id, platformAdmin: false });
  await co.ref.collection("employees").doc(admin.uid).set({ name: "Admin", role: "admin", hourlyRate: 0, active: true });
  const platform = await makeUser(`p.${hex()}@example.test`, { platformAdmin: true });

  const wA = await seedWorker(co, 10_500);
  const wB = await seedWorker(co, 12_000);
  const wC = await seedWorker(co, 20_000); // accrued 15,000 -> 5,000 short
  const EXPECTED = 10_500 + 12_000 + 20_000;
  const CONFIRMED = EXPECTED - 5_000;

  // ── runPayroll ───────────────────────────────────────────────────────────
  console.log("── runPayroll ──");
  const noAuth = await call("runPayroll", {});
  check("unauthenticated run is rejected", errStatus(noAuth) === "UNAUTHENTICATED");
  const asWorker = await call("runPayroll", {}, wA.idToken);
  check("a worker cannot run payroll", errStatus(asWorker) === "PERMISSION_DENIED");

  const run1 = await call("runPayroll", {}, admin.idToken);
  check("admin runs payroll", run1.status === 200, JSON.stringify(run1.body));
  const runId = result(run1).payrollRunId;
  const runDoc = (await co.ref.collection("payroll_runs").doc(runId).get()).data();
  check("run is completed with cent totals", runDoc.status === "completed" && runDoc.totals.drawsDeductedMinor === EXPECTED, JSON.stringify(runDoc.totals));
  const lineC = runDoc.lines.find((l) => l.employeeId === wC.uid);
  check(
    "short employee: net payout is zero, shortfall recorded",
    lineC.netPayoutMinor === 0 && lineC.shortfallMinor === 5_000 && lineC.accruedMinor === 15_000,
    JSON.stringify(lineC),
  );
  const markedA = (await co.ref.collection("draw_requests").doc(wA.drawId).get()).data();
  check("draws are marked with the run id", markedA.payrollRunId === runId);
  const payrollAudit = await co.ref.collection("audit_log").where("type", "==", "payroll_run").get();
  check("payroll run is audited", payrollAudit.size === 1);

  const runAgain = await call("runPayroll", {}, admin.idToken);
  const emptyRun = (await co.ref.collection("payroll_runs").doc(result(runAgain).payrollRunId).get()).data();
  check("a second run does not deduct the same draws again", emptyRun.totals.drawsDeductedMinor === 0, JSON.stringify(emptyRun.totals));

  // ── runPayroll: concurrency and resume ──────────────────────────────────
  console.log("\n── runPayroll: concurrent calls and an interrupted run ──");
  const race = await seedCompany("Race Co");
  const raceAdmin = await makeUser(`ra.${hex()}@example.test`, { companyId: race.id, platformAdmin: false });
  await race.ref.collection("employees").doc(raceAdmin.uid).set({ name: "Admin", role: "admin", hourlyRate: 0, active: true });
  await seedWorker(race, 21_000);
  const burst = await Promise.all(Array.from({ length: 4 }, () => call("runPayroll", {}, raceAdmin.idToken)));
  const runs = await race.ref.collection("payroll_runs").get();
  const totalDeducted = runs.docs.reduce((s, d) => s + d.data().totals.drawsDeductedMinor, 0);
  check("4 simultaneous runs deduct the draw exactly once", totalDeducted === 21_000, `deducted=${totalDeducted}, runs=${runs.size}`);
  check("at least one overlapping call was turned away or found nothing to do", burst.filter((r) => r.status === 200).length >= 1);
  const unmarked = (await race.ref.collection("draw_requests").where("payrollRunId", "==", null).get()).size;
  check("no draw is left unmarked", unmarked === 0, `unmarked=${unmarked}`);

  const resume = await seedCompany("Resume Co");
  const resumeAdmin = await makeUser(`rs.${hex()}@example.test`, { companyId: resume.id, platformAdmin: false });
  await resume.ref.collection("employees").doc(resumeAdmin.uid).set({ name: "Admin", role: "admin", hourlyRate: 0, active: true });
  const wR = await seedWorker(resume, 10_500);
  // A run that wrote its document but died before marking the draws.
  const interrupted = await resume.ref.collection("payroll_runs").add({
    cycleStart: Timestamp.fromMillis(Date.now() - 86_400_000),
    cycleEnd: Timestamp.now(),
    status: "applying",
    lines: [{ employeeId: wR.uid, accruedMinor: 15_000, drawsDeductedMinor: 10_500, netPayoutMinor: 4_500, shortfallMinor: 0, drawIds: [wR.drawId] }],
    totals: { accruedMinor: 15_000, drawsDeductedMinor: 10_500, netPayoutMinor: 4_500, shortfallMinor: 0 },
  });
  const resumed = await call("runPayroll", {}, resumeAdmin.idToken);
  const resumeRuns = await resume.ref.collection("payroll_runs").get();
  const finished = (await interrupted.get()).data();
  const drawAfter = (await resume.ref.collection("draw_requests").doc(wR.drawId).get()).data();
  check(
    "an interrupted run is finished, not duplicated",
    result(resumed)?.resumed === true && resumeRuns.size === 1 && finished.status === "completed" && drawAfter.payrollRunId === interrupted.id,
    JSON.stringify({ r: result(resumed), runs: resumeRuns.size, status: finished.status }),
  );

  // ── createSettlement ─────────────────────────────────────────────────────
  console.log("\n── createSettlement ──");
  const noDraws = await call("createSettlement", { payrollRunId: result(runAgain).payrollRunId }, admin.idToken);
  check("a run with no deductions cannot be settled", errStatus(noDraws) === "FAILED_PRECONDITION", JSON.stringify(noDraws.body));
  const workerCreate = await call("createSettlement", { payrollRunId: runId }, wA.idToken);
  check("a worker cannot create a settlement", errStatus(workerCreate) === "PERMISSION_DENIED");

  const created = await call("createSettlement", { payrollRunId: runId }, admin.idToken);
  check("settlement is created from the run", created.status === 200 && result(created).created === true, JSON.stringify(created.body));
  const sid = result(created).settlementId;
  const sref = co.ref.collection("settlements").doc(sid);
  let s = (await sref.get()).data();
  check("expected amount is the sum of the deductions", s.expectedMinor === EXPECTED && s.outstandingMinor === EXPECTED && s.receivedMinor === 0 && s.confirmedMinor === null);
  check("reference has the agreed format", /^EWA-T[0-9A-F]{6}-\d{8}-[A-Z0-9]{4}$/.test(s.reference), s.reference);
  check("one item per deducted employee", (await sref.collection("items").get()).size === 3);
  const exc = await sref.collection("exceptions").get();
  check("the short employee raises an insufficient-pay exception", exc.size === 1 && exc.docs[0].data().type === "INSUFFICIENT_PAY" && exc.docs[0].data().differenceMinor === -5_000);
  check("status is EXCEPTION while that is open", s.status === "EXCEPTION");
  const again = await call("createSettlement", { payrollRunId: runId }, admin.idToken);
  check("creating it again is a no-op", result(again).created === false && (await co.ref.collection("settlements").get()).size === 1);

  // ── reading and writing settlements from a client ───────────────────────
  console.log("\n── rules: settlement visibility ──");
  const path = `companies/${co.id}/settlements/${sid}`;
  check("company admin can read it", (await fsGet(path, admin.idToken)).status === 200);
  check("a worker cannot read it", (await fsGet(path, wA.idToken)).status === 403);
  check("the platform admin cannot read it", (await fsGet(path, platform.idToken)).status === 403);
  const clientWrite = await fetch(`${FS_BASE}/${path}?updateMask.fieldPaths=status`, {
    method: "PATCH",
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${admin.idToken}` },
    body: JSON.stringify({ fields: { status: { stringValue: "SETTLED" } } }),
  });
  check("not even an admin can edit it directly", clientWrite.status === 403);

  // ── payments before confirmation, exceptions, confirmation ───────────────
  console.log("\n── confirm, record payments, resolve ──");
  const pay = (over = {}, token = platform.idToken) =>
    call("recordSettlementPayment", {
      shortCode: co.shortCode, reference: s.reference, amountMinor: 20_000, currency: "SZL", providerTransactionId: "TXN-0001", ...over,
    }, token);

  const early = await pay();
  check("a payment before the employer confirms is refused", errStatus(early) === "FAILED_PRECONDITION", JSON.stringify(early.body));

  const shortNote = await call("resolveException", { settlementId: sid, exceptionId: `insufficient_pay_${wC.uid}`, note: "ok" }, admin.idToken);
  check("an exception cannot be closed without a real note", errStatus(shortNote) === "INVALID_ARGUMENT");
  const resolvedPay = await call("resolveException", { settlementId: sid, exceptionId: `insufficient_pay_${wC.uid}`, note: "Balance carried to next cycle by HR" }, admin.idToken);
  check("insufficient-pay exception can be resolved with a note", resolvedPay.status === 200 && result(resolvedPay).status === "DRAFT", JSON.stringify(resolvedPay.body));

  const badConfirm = await call("confirmDeductions", { settlementId: sid, confirmedMinor: 1.5 }, admin.idToken);
  check("confirmed figure must be whole cents", errStatus(badConfirm) === "INVALID_ARGUMENT");
  const confirm = await call("confirmDeductions", { settlementId: sid, confirmedMinor: CONFIRMED }, admin.idToken);
  s = (await sref.get()).data();
  check("confirming a lower figure opens a shortfall exception", result(confirm).status === "EXCEPTION" && s.openExceptionCount === 1, JSON.stringify(confirm.body));
  const mismatch = (await sref.collection("exceptions").doc("deduction_mismatch").get()).data();
  check("the shortfall is recorded with its difference", mismatch.type === "DEDUCTION_SHORTFALL" && mismatch.differenceMinor === -5_000);

  // ── recordSettlementPayment ──────────────────────────────────────────────
  const byAdmin = await pay({}, admin.idToken);
  check("a company admin cannot record payments", errStatus(byAdmin) === "PERMISSION_DENIED");
  check("unknown company code", errStatus(await pay({ shortCode: "NOPE99" })) === "NOT_FOUND");
  check("unknown reference", errStatus(await pay({ reference: "EWA-NOPE" })) === "NOT_FOUND");
  check("wrong currency", errStatus(await pay({ currency: "ZAR" })) === "FAILED_PRECONDITION");
  check("bad transaction id", errStatus(await pay({ providerTransactionId: "a b" })) === "INVALID_ARGUMENT");
  check("zero amount", errStatus(await pay({ amountMinor: 0 })) === "INVALID_ARGUMENT");

  const p1 = await pay();
  check("first payment recorded", p1.status === 200 && result(p1).receivedMinor === 20_000 && result(p1).duplicate === false, JSON.stringify(p1.body));
  const p1again = await pay();
  s = (await sref.get()).data();
  check("the same bank line again is counted once", result(p1again).duplicate === true && s.receivedMinor === 20_000);
  const p1clash = await pay({ amountMinor: 999 });
  check("the same transaction id with a different amount is refused", errStatus(p1clash) === "ALREADY_EXISTS");

  const burstPay = await Promise.all(Array.from({ length: 4 }, () => pay({ amountMinor: 17_500, providerTransactionId: "TXN-0002" })));
  s = (await sref.get()).data();
  check("4 simultaneous submissions of one bank line count once", s.receivedMinor === 37_500, `received=${s.receivedMinor}, ok=${burstPay.filter((r) => r.status === 200).length}`);
  check("received now equals confirmed, yet status is not SETTLED while the shortfall is open", s.status === "EXCEPTION" && s.receivedMinor === CONFIRMED);
  check("outstanding shows the E50 difference to expected", s.outstandingMinor === 5_000, String(s.outstandingMinor));
  check("two payment records exist", (await co.ref.collection("payment_transactions").get()).size === 2);

  const cancelPaid = await call("cancelSettlement", { settlementId: sid, reason: "Entered in error" }, admin.idToken);
  check("a settlement that has received money cannot be cancelled", errStatus(cancelPaid) === "FAILED_PRECONDITION");

  const resolveShort = await call("resolveException", { settlementId: sid, exceptionId: "deduction_mismatch", note: "C's pay did not cover the draw; carried over" }, admin.idToken);
  s = (await sref.get()).data();
  check("resolving the shortfall settles it", result(resolveShort).status === "SETTLED" && s.status === "SETTLED", JSON.stringify(resolveShort.body));
  check("the E50 outstanding difference stays visible", s.outstandingMinor === 5_000);

  const over = await pay({ amountMinor: 100, providerTransactionId: "TXN-0003" });
  s = (await sref.get()).data();
  check("money beyond the confirmed amount raises an overpayment exception", result(over).status === "EXCEPTION" && s.receivedMinor === 37_600, JSON.stringify(over.body));
  const overExc = (await sref.collection("exceptions").doc("overpayment").get()).data();
  check("overpayment exception holds the difference", overExc.type === "OVERPAYMENT" && overExc.differenceMinor === 100);
  const audits = await co.ref.collection("audit_log").where("settlementId", "==", sid).get();
  const auditTypes = audits.docs.map((d) => d.data().type).sort().join(",");
  check(
    "every settlement step is in the audit log",
    auditTypes === "settlement_created,settlement_deductions_confirmed,settlement_exception_resolved,settlement_exception_resolved,settlement_payment_recorded,settlement_payment_recorded,settlement_payment_recorded",
    auditTypes,
  );

  // ── cross-company isolation and cancel ───────────────────────────────────
  console.log("\n── isolation and cancel ──");
  const other = await call("confirmDeductions", { settlementId: sid, confirmedMinor: 1 }, raceAdmin.idToken);
  check("another company's admin cannot touch this settlement", errStatus(other) === "NOT_FOUND", JSON.stringify(other.body));

  const raceRunId = runs.docs.find((d) => d.data().totals.drawsDeductedMinor > 0).id;
  const created2 = await call("createSettlement", { payrollRunId: raceRunId }, raceAdmin.idToken);
  const sid2 = result(created2).settlementId;
  const cancel = await call("cancelSettlement", { settlementId: sid2, reason: "Run was a test" }, raceAdmin.idToken);
  const s2 = (await race.ref.collection("settlements").doc(sid2).get()).data();
  check("an unpaid settlement can be cancelled with a reason", cancel.status === 200 && s2.status === "CANCELLED");
  const confirmCancelled = await call("confirmDeductions", { settlementId: sid2, confirmedMinor: 21_000 }, raceAdmin.idToken);
  check("a cancelled settlement cannot be confirmed", errStatus(confirmCancelled) === "FAILED_PRECONDITION");
  const payCancelled = await call("recordSettlementPayment", {
    shortCode: race.shortCode, reference: s2.reference, amountMinor: 1_000, currency: "SZL", providerTransactionId: "TXN-9001",
  }, platform.idToken);
  check("a cancelled settlement refuses payments", errStatus(payCancelled) === "FAILED_PRECONDITION");

  console.log(`\n${pass} passed, ${fail} failed`);
  process.exit(fail === 0 ? 0 : 1);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
