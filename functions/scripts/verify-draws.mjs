// Ad-hoc check of server-side draw enforcement (requestDraw, decideDrawRequest,
// firestore.rules) against the emulator suite on demo-ewa-test. Same environment
// as verify-multitenant.mjs (see the firebase-emulator-windows-gotchas memory).
// Run `npm run build` first; the script reads cycle math from lib/drawRules.js.
//
// Usage (from functions/, emulator already running):
//   node scripts/verify-draws.mjs

import { randomBytes } from "node:crypto";
import { initializeApp } from "firebase-admin/app";
import { getFirestore, Timestamp } from "firebase-admin/firestore";
import { getAuth } from "firebase-admin/auth";
import * as rules from "../lib/drawRules.js";

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
    headers: {
      "Content-Type": "application/json",
      ...(idToken ? { Authorization: `Bearer ${idToken}` } : {}),
    },
    body: JSON.stringify({ data }),
  });
  return { status: res.status, body: await res.json() };
}

const errStatus = (r) => r.body?.error?.status;

// Creates an auth user with the companyId claim and returns a token carrying it.
async function makeUser(email, companyId) {
  const password = randomBytes(12).toString("hex");
  const created = await fetch(`${AUTH_BASE}/accounts:signUp?key=fake-key`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ email, password, returnSecureToken: true }),
  }).then((r) => r.json());
  await auth.setCustomUserClaims(created.localId, { companyId, platformAdmin: false });
  const signedIn = await fetch(`${AUTH_BASE}/accounts:signInWithPassword?key=fake-key`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ email, password, returnSecureToken: true }),
  }).then((r) => r.json());
  return { uid: created.localId, idToken: signedIn.idToken };
}

const hasGlobalDefaults = { maxDrawPercent: 0.5, feePercent: 0.05, maxDrawsPerCycle: 2 };

async function seedCompany(label, { active = true } = {}) {
  const ref = db.collection("companies").doc();
  await ref.set({ name: label, shortCode: label.slice(0, 6).toUpperCase(), active });
  await ref.collection("settings").doc("app").set({
    companyName: label,
    ...hasGlobalDefaults,
    paydayRule: { type: "lastDayOfMonth", dayOfMonth: 25, weekday: 5 },
  });
  return ref;
}

async function seedEmployee(companyRef, user, extra = {}) {
  await companyRef.collection("employees").doc(user.uid).set({
    name: "Test Worker",
    role: "worker",
    hourlyRate: 50,
    active: true,
    ...extra,
  });
}

// Puts closed sessions inside the current cycle; returns the accrued wages the
// server should see for them.
async function seedSessions(companyRef, uid, rate = 50) {
  const now = Date.now();
  const cycleStart = rules.currentCycleStartMs(
    { type: "lastDayOfMonth", dayOfMonth: 25, weekday: 5 },
    now,
  );
  const durationMs = Math.min(8 * 3_600_000, now - cycleStart - 2 * 60_000);
  const clockIn = cycleStart + 60_000;
  const clockOut = clockIn + durationMs;
  const ref = companyRef.collection("time_sessions").doc();
  await ref.set({
    employeeId: uid,
    clockInTs: Timestamp.fromMillis(clockIn),
    clockOutTs: Timestamp.fromMillis(clockOut),
  });
  const accrued = rules.accruedMinor(rate, [{ clockInMs: clockIn, clockOutMs: clockOut }], now);
  return { sessionRef: ref, accrued, cap: Math.floor(accrued * hasGlobalDefaults.maxDrawPercent + 1e-9) };
}

async function main() {
  console.log(`Running against ${PROJECT_ID}\n`);

  // ── Setup ────────────────────────────────────────────────────────────────
  const co = await seedCompany("Draws Co");
  const worker = await makeUser(`worker.${randomBytes(3).toString("hex")}@example.test`, co.id);
  await seedEmployee(co, worker);
  const { sessionRef, accrued, cap } = await seedSessions(co, worker.uid);
  const admin = await makeUser(`admin.${randomBytes(3).toString("hex")}@example.test`, co.id);
  await seedEmployee(co, admin, { role: "admin", hourlyRate: 0 });
  console.log(`accrued=${accrued} cents, cap(50%)=${cap} cents\n`);

  // ── requestDraw: sign-in and input validation ────────────────────────────
  console.log("── requestDraw: input and caller checks ──");
  const anon = await call("requestDraw", { amountMinor: 1000 });
  check("unauthenticated caller is rejected", errStatus(anon) === "UNAUTHENTICATED", JSON.stringify(anon.body));

  const stringAmount = await call("requestDraw", { amountMinor: "1000" }, worker.idToken);
  check("non-numeric amount is rejected", errStatus(stringAmount) === "INVALID_ARGUMENT", JSON.stringify(stringAmount.body));

  const negative = await call("requestDraw", { amountMinor: -500 }, worker.idToken);
  check("negative amount is rejected", errStatus(negative) === "FAILED_PRECONDITION", JSON.stringify(negative.body));

  const noCompany = await fetch(`${AUTH_BASE}/accounts:signUp?key=fake-key`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ email: `nocompany.${randomBytes(3).toString("hex")}@example.test`, password: randomBytes(12).toString("hex"), returnSecureToken: true }),
  }).then((r) => r.json());
  const noClaim = await call("requestDraw", { amountMinor: 1000 }, noCompany.idToken);
  check("account without a company claim is rejected", errStatus(noClaim) === "PERMISSION_DENIED", JSON.stringify(noClaim.body));

  // ── requestDraw: cap, fee, count ─────────────────────────────────────────
  console.log("\n── requestDraw: cap, fee and count limit ──");
  const overCap = await call("requestDraw", { amountMinor: cap + 100 }, worker.idToken);
  check("amount above the 50% cap is rejected", errStatus(overCap) === "FAILED_PRECONDITION", JSON.stringify(overCap.body));

  const first = Math.floor(cap / 2);
  const r1 = await call("requestDraw", { amountMinor: first }, worker.idToken);
  const expectedFee = Math.round(first * 0.05);
  check("first draw within the cap succeeds", r1.status === 200, JSON.stringify(r1.body));
  check(
    "server computed the fee (5%) and total",
    r1.body?.result?.feeMinor === expectedFee && r1.body?.result?.totalMinor === first + expectedFee,
    JSON.stringify(r1.body),
  );
  const drawDoc = await co.collection("draw_requests").doc(r1.body.result.requestId).get();
  check(
    "draw stored as pending with null payrollRunId",
    drawDoc.exists && drawDoc.data().status === "pending" && drawDoc.data().payrollRunId === null,
  );
  const audit = await co.collection("audit_log").where("type", "==", "draw_request").get();
  check("audit log entry written", audit.size === 1);

  const remaining = cap - first;
  const overRemaining = await call("requestDraw", { amountMinor: remaining + 5 }, worker.idToken);
  check("second draw above the remaining cap is rejected", errStatus(overRemaining) === "FAILED_PRECONDITION", JSON.stringify(overRemaining.body));

  const r2 = await call("requestDraw", { amountMinor: remaining }, worker.idToken);
  check("second draw for exactly the remaining cap succeeds", r2.status === 200, JSON.stringify(r2.body));

  const r3 = await call("requestDraw", { amountMinor: 1 }, worker.idToken);
  check("third draw is rejected (2 per cycle)", errStatus(r3) === "FAILED_PRECONDITION", JSON.stringify(r3.body));

  // ── rules: clients cannot write draws ────────────────────────────────────
  console.log("\n── firestore.rules: no client writes to draw_requests ──");
  const forged = await fetch(`${FS_BASE}/companies/${co.id}/draw_requests`, {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${worker.idToken}` },
    body: JSON.stringify({
      fields: {
        employeeId: { stringValue: worker.uid },
        amount: { doubleValue: 1 },
        fee: { doubleValue: 0 },
        total: { doubleValue: 1 },
        status: { stringValue: "pending" },
      },
    }),
  });
  check("worker cannot create a draw directly", forged.status === 403, `status ${forged.status}`);

  const selfApprove = await fetch(
    `${FS_BASE}/companies/${co.id}/draw_requests/${r1.body.result.requestId}?updateMask.fieldPaths=status`,
    {
      method: "PATCH",
      headers: { "Content-Type": "application/json", Authorization: `Bearer ${worker.idToken}` },
      body: JSON.stringify({ fields: { status: { stringValue: "approved" } } }),
    },
  );
  check("worker cannot approve their own draw", selfApprove.status === 403, `status ${selfApprove.status}`);

  const adminDirect = await fetch(
    `${FS_BASE}/companies/${co.id}/draw_requests/${r1.body.result.requestId}?updateMask.fieldPaths=status`,
    {
      method: "PATCH",
      headers: { "Content-Type": "application/json", Authorization: `Bearer ${admin.idToken}` },
      body: JSON.stringify({ fields: { status: { stringValue: "approved" } } }),
    },
  );
  check("admin cannot bypass the function with a direct update", adminDirect.status === 403, `status ${adminDirect.status}`);

  const ownRead = await fetch(`${FS_BASE}/companies/${co.id}/draw_requests/${r1.body.result.requestId}`, {
    headers: { Authorization: `Bearer ${worker.idToken}` },
  });
  check("worker can still read their own draw", ownRead.status === 200, `status ${ownRead.status}`);

  // ── decideDrawRequest ────────────────────────────────────────────────────
  console.log("\n── decideDrawRequest ──");
  const approve1 = await call("decideDrawRequest", { requestId: r1.body.result.requestId, approve: true }, admin.idToken);
  check("approving a draw within the cap succeeds", approve1.status === 200, JSON.stringify(approve1.body));

  // Admin edits time records so the earned wages no longer cover the second draw.
  await sessionRef.delete();
  const approve2 = await call("decideDrawRequest", { requestId: r2.body.result.requestId, approve: true }, admin.idToken);
  check(
    "approval is blocked when earned wages no longer cover the draw",
    errStatus(approve2) === "FAILED_PRECONDITION",
    JSON.stringify(approve2.body),
  );
  const stillPending = await co.collection("draw_requests").doc(r2.body.result.requestId).get();
  check("blocked draw stays pending", stillPending.data().status === "pending");

  const reject2 = await call(
    "decideDrawRequest",
    { requestId: r2.body.result.requestId, approve: false, reason: "Time records under review" },
    admin.idToken,
  );
  const rejected = await co.collection("draw_requests").doc(r2.body.result.requestId).get();
  check(
    "rejection still works and stores the reason",
    reject2.status === 200 && rejected.data().status === "rejected" && rejected.data().reason === "Time records under review",
    JSON.stringify(reject2.body),
  );

  const workerDecide = await call("decideDrawRequest", { requestId: r2.body.result.requestId, approve: true }, worker.idToken);
  check("a worker cannot call decideDrawRequest", errStatus(workerDecide) === "PERMISSION_DENIED", JSON.stringify(workerDecide.body));

  // ── concurrency ──────────────────────────────────────────────────────────
  console.log("\n── concurrent requests ──");
  const co2 = await seedCompany("Race Co");
  const racer = await makeUser(`racer.${randomBytes(3).toString("hex")}@example.test`, co2.id);
  await seedEmployee(co2, racer);
  const { cap: cap2 } = await seedSessions(co2, racer.uid);
  const each = Math.floor(cap2 / 10);
  const results = await Promise.all(
    Array.from({ length: 6 }, () => call("requestDraw", { amountMinor: each }, racer.idToken)),
  );
  const ok = results.filter((r) => r.status === 200).length;
  const stored = (await co2.collection("draw_requests").get()).size;
  check("6 simultaneous requests: exactly 2 succeed (limit 2)", ok === 2 && stored === 2, `succeeded=${ok}, stored=${stored}`);

  // ── inactive employee / company ──────────────────────────────────────────
  console.log("\n── inactive accounts ──");
  await co2.collection("employees").doc(racer.uid).update({ active: false });
  const inactiveEmp = await call("requestDraw", { amountMinor: 100 }, racer.idToken);
  check("deactivated employee is rejected", errStatus(inactiveEmp) === "PERMISSION_DENIED", JSON.stringify(inactiveEmp.body));

  const co3 = await seedCompany("Suspended Co", { active: false });
  const suspended = await makeUser(`susp.${randomBytes(3).toString("hex")}@example.test`, co3.id);
  await seedEmployee(co3, suspended);
  await seedSessions(co3, suspended.uid);
  const suspendedCall = await call("requestDraw", { amountMinor: 100 }, suspended.idToken);
  check("employee of a suspended company is rejected", errStatus(suspendedCall) === "PERMISSION_DENIED", JSON.stringify(suspendedCall.body));

  console.log(`\n${pass} passed, ${fail} failed`);
  process.exit(fail === 0 ? 0 : 1);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
