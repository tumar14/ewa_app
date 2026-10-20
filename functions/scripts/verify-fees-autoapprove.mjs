// Checks fee schedules (percentage and tariff table) and automatic approval
// against the emulator suite. Same environment as verify-draws.mjs.
// Run `npm run build` first.
//
//   node scripts/verify-fees-autoapprove.mjs

import { randomBytes } from "node:crypto";
import { initializeApp } from "firebase-admin/app";
import { getFirestore, Timestamp } from "firebase-admin/firestore";
import { getAuth } from "firebase-admin/auth";
import * as rules from "../lib/drawRules.js";

process.env.FIRESTORE_EMULATOR_HOST ??= "127.0.0.1:8080";
process.env.FIREBASE_AUTH_EMULATOR_HOST ??= "127.0.0.1:9099";
process.env.GCLOUD_PROJECT ??= process.env.EMULATOR_PROJECT ?? "demo-ewa-test";
const PROJECT_ID = process.env.GCLOUD_PROJECT;
const FN = `http://127.0.0.1:5001/${PROJECT_ID}/us-central1`;
const AUTH = "http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1";
initializeApp({ projectId: PROJECT_ID });
const db = getFirestore();
const auth = getAuth();

let pass = 0, fail = 0;
const check = (label, cond, detail) => { if (cond) { pass++; console.log(`  OK  ${label}`); } else { fail++; console.log(`FAIL  ${label}${detail ? " - " + detail : ""}`); } };
const hex = (n = 3) => randomBytes(n).toString("hex");
const call = async (name, data, token) => {
  const res = await fetch(`${FN}/${name}`, { method: "POST", headers: { "Content-Type": "application/json", ...(token ? { Authorization: `Bearer ${token}` } : {}) }, body: JSON.stringify({ data }) });
  const body = await res.json();
  return { status: res.status, err: body.error?.status, msg: body.error?.message, result: body.result };
};

async function makeUser(companyId) {
  const email = `${hex()}@example.test`, password = randomBytes(10).toString("hex");
  const created = await fetch(`${AUTH}/accounts:signUp?key=k`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ email, password, returnSecureToken: true }) }).then((r) => r.json());
  await auth.setCustomUserClaims(created.localId, { companyId, platformAdmin: false });
  const s = await fetch(`${AUTH}/accounts:signInWithPassword?key=k`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ email, password, returnSecureToken: true }) }).then((r) => r.json());
  return { uid: created.localId, token: s.idToken };
}

const rule = { type: "lastDayOfMonth", dayOfMonth: 25, weekday: 5 };
async function seedCompany(label, settings) {
  const ref = db.collection("companies").doc();
  await ref.set({ name: label, shortCode: hex(3).toUpperCase(), active: true });
  await ref.collection("settings").doc("app").set({ companyName: label, maxDrawPercent: 0.5, feePercent: 0.05, maxDrawsPerCycle: 2, paydayRule: rule, ...settings });
  const admin = await makeUser(ref.id);
  await ref.collection("employees").doc(admin.uid).set({ name: "Admin", role: "admin", hourlyRate: 0, active: true });
  return { ref, admin };
}
// A worker with a lot of earned wages so the cap never gets in the way, unless asked.
async function worker(co, rate = 500) {
  const w = await makeUser(co.ref.id);
  await co.ref.collection("employees").doc(w.uid).set({ name: "Worker", role: "worker", hourlyRate: rate, active: true });
  const now = Date.now();
  const start = rules.currentCycleStartMs(rule, now);
  const clockIn = start + 60_000;
  const clockOut = clockIn + Math.min(8 * 3_600_000, now - start - 2 * 60_000);
  await co.ref.collection("time_sessions").add({ employeeId: w.uid, clockInTs: Timestamp.fromMillis(clockIn), clockOutTs: Timestamp.fromMillis(clockOut) });
  return { ...w, accrued: rules.accruedMinor(rate, [{ clockInMs: clockIn, clockOutMs: clockOut }], now) };
}
const drawOf = async (co, id) => (await co.ref.collection("draw_requests").doc(id).get()).data();

const tariff = [
  { upToMinor: 5_000, flatMinor: 100, percent: 0 },
  { upToMinor: 20_000, flatMinor: 300, percent: 0 },
  { upToMinor: 50_000, flatMinor: 600, percent: 0.005 },
];

async function main() {
  console.log(`Running against ${PROJECT_ID}\n`);

  console.log("-- tariff table with a E500 top band, auto-approval up to E100 --");
  const A = await seedCompany("Tariff Co", { feeMode: "tiered", feeTiers: tariff, autoApprove: true, autoApproveMaxMinor: 10_000 });
  const w1 = await worker(A);
  const r30 = await call("requestDraw", { amountMinor: 3_000 }, w1.token);
  check("E30 is accepted", r30.status === 200, r30.msg);
  const d30 = await drawOf(A, r30.result?.requestId ?? "x");
  check("its fee comes from the first band (E1.00)", d30?.feeMinor === 100 && d30?.totalMinor === 3_100, JSON.stringify(d30));
  check("it was approved automatically, by policy", r30.result?.status === "approved" && d30?.status === "approved" && d30?.autoApproved === true && d30?.decidedBy === "policy");
  check("and is waiting to be paid, not marked paid", d30?.disbursementStatus === "pending" && d30?.disbursedAt === null);
  const audits = (await A.ref.collection("audit_log").where("requestId", "==", r30.result.requestId).get()).docs.map((d) => d.data());
  const decision = audits.find((a) => a.type === "draw_decision");
  check("the audit log records the automatic decision and the ceiling used", !!decision && decision.auto === true && decision.approved === true && decision.autoApproveCeilingMinor === 10_000, JSON.stringify(decision));
  check("a request entry is also logged", audits.some((a) => a.type === "draw_request"));
  const again = await call("decideDrawRequest", { requestId: r30.result.requestId, approve: false }, A.admin.token);
  check("an admin cannot re-decide an automatically approved advance", again.err === "FAILED_PRECONDITION", again.msg);
  const paid = await call("disburseDraw", { requestId: r30.result.requestId, paymentReference: "TEST/2026/FEES-1" }, A.admin.token);
  check("finance can still record the payment", paid.status === 200, paid.msg);

  const r150 = await call("requestDraw", { amountMinor: 15_000 }, w1.token);
  const d150 = await drawOf(A, r150.result?.requestId ?? "x");
  check("E150 is above the ceiling, so it waits for a person", r150.status === 200 && d150?.status === "pending" && d150?.autoApproved === false && d150?.decidedBy === null, JSON.stringify(d150));
  check("and takes its fee from the second band (E3.00)", d150?.feeMinor === 300);

  console.log("\n-- band edges and the ceiling edge --");
  const w2 = await worker(A), w3 = await worker(A), w4 = await worker(A);
  const e50 = await call("requestDraw", { amountMinor: 5_000 }, w2.token);
  check("exactly E50 is in the first band (fee E1.00)", (await drawOf(A, e50.result.requestId)).feeMinor === 100);
  const e5001 = await call("requestDraw", { amountMinor: 5_001 }, w2.token);
  check("E50.01 is in the second band (fee E3.00)", (await drawOf(A, e5001.result.requestId)).feeMinor === 300);
  const e100 = await call("requestDraw", { amountMinor: 10_000 }, w3.token);
  check("exactly the E100 ceiling is approved automatically", (await drawOf(A, e100.result.requestId)).autoApproved === true);
  const e10001 = await call("requestDraw", { amountMinor: 10_001 }, w4.token);
  const d10001 = await drawOf(A, e10001.result.requestId);
  check("one cent over the ceiling waits for a person", d10001.status === "pending" && d10001.autoApproved === false);
  check("its fee (second band) is E3.00", d10001.feeMinor === 300);

  console.log("\n-- the table's own limits --");
  const w5 = await worker(A);
  const tooBig = await call("requestDraw", { amountMinor: 60_000 }, w5.token);
  check("E600 is above the top band and is refused with the maximum", tooBig.err === "FAILED_PRECONDITION" && /maximum 500\.00/.test(tooBig.msg ?? ""), tooBig.msg);
  const top = await call("requestDraw", { amountMinor: 50_000 }, w5.token);
  const dTop = await drawOf(A, top.result?.requestId ?? "x");
  check("exactly E500 is allowed, fee E6.00 + 0.5% = E8.50, and waits for a person (over the ceiling)", top.status === 200 && dTop?.feeMinor === 850 && dTop?.status === "pending", JSON.stringify(dTop));
  const tiny = await call("requestDraw", { amountMinor: 50 }, (await worker(A)).token);
  check("50 cents is refused because the E1 fee would exceed it", tiny.err === "FAILED_PRECONDITION" && /more than the amount/.test(tiny.msg ?? ""), tiny.msg);

  console.log("\n-- percentage company, nobody approves automatically --");
  const B = await seedCompany("Percent Co", { feePercent: 0.07 });
  const wb = await worker(B);
  const rb = await call("requestDraw", { amountMinor: 10_000 }, wb.token);
  const db1 = await drawOf(B, rb.result.requestId);
  check("a 7% fee is applied (E7.00 on E100)", db1.feeMinor === 700 && db1.totalMinor === 10_700);
  check("with auto-approval off, it waits for a person", db1.status === "pending" && db1.autoApproved === false && rb.result.status === "pending");
  const legacy = await seedCompany("Legacy Co", {});
  await legacy.ref.collection("settings").doc("app").set({ companyName: "Legacy Co", maxDrawPercent: 0.5, feePercent: 0.03, maxDrawsPerCycle: 2, paydayRule: rule });
  const wl = await worker(legacy);
  const rl = await call("requestDraw", { amountMinor: 20_000 }, wl.token);
  check("a settings document from before these features still works (3%)", (await drawOf(legacy, rl.result.requestId)).feeMinor === 600);

  console.log("\n-- automatic approval without a ceiling, and the other limits still apply --");
  const C = await seedCompany("Auto Co", { autoApprove: true, autoApproveMaxMinor: null });
  const wc = await worker(C, 100);
  const cap = Math.floor(wc.accrued * 0.5);
  const big = await call("requestDraw", { amountMinor: Math.floor(cap / 100) * 100 }, wc.token);
  check("with no ceiling, any request within the cap is approved", big.result?.status === "approved", big.msg);
  const over = await call("requestDraw", { amountMinor: cap + 100 }, (await worker(C, 100)).token);
  check("automatic approval never lifts the cap: a request above it is refused", over.err === "FAILED_PRECONDITION" && /maximum/.test(over.msg ?? ""), over.msg);
  const wc2 = await worker(C);
  const burst = await Promise.all(Array.from({ length: 5 }, () => call("requestDraw", { amountMinor: 1_000 }, wc2.token)));
  const okCount = burst.filter((r) => r.status === 200).length;
  const stored = (await C.ref.collection("draw_requests").where("employeeId", "==", wc2.uid).get()).docs.map((d) => d.data());
  check("5 simultaneous requests: still only 2 get through (the per-cycle limit)", okCount === 2 && stored.length === 2 && stored.every((d) => d.autoApproved === true), `ok=${okCount}, stored=${stored.length}`);
  const inactiveCo = await seedCompany("Gone Co", { autoApprove: true });
  const wi = await worker(inactiveCo);
  await inactiveCo.ref.collection("employees").doc(wi.uid).update({ active: false });
  const gone = await call("requestDraw", { amountMinor: 1_000 }, wi.token);
  check("a deactivated employee is refused, not auto-approved", gone.err === "PERMISSION_DENIED", gone.msg);

  console.log("\n-- bad settings fail safe --");
  const zeroCeiling = await seedCompany("Zero Ceiling Co", { autoApprove: true, autoApproveMaxMinor: 0 });
  const rz = await call("requestDraw", { amountMinor: 1_000 }, (await worker(zeroCeiling)).token);
  check("an unusable ceiling (0) means a person decides", rz.status === 200 && rz.result.status === "pending", JSON.stringify(rz.result ?? rz.msg));
  const stringFlag = await seedCompany("String Flag Co", { autoApprove: "true" });
  const rs = await call("requestDraw", { amountMinor: 1_000 }, (await worker(stringFlag)).token);
  check("a flag that is not exactly true means a person decides", rs.status === 200 && rs.result.status === "pending");
  const broken = await seedCompany("Broken Fees Co", { feeMode: "tiered", feeTiers: [{ upToMinor: 9_000, flatMinor: 100, percent: 0 }, { upToMinor: 5_000, flatMinor: 200, percent: 0 }] });
  const rbk = await call("requestDraw", { amountMinor: 1_000 }, (await worker(broken)).token);
  check("a fee table that is out of order is refused rather than guessed", rbk.err === "FAILED_PRECONDITION" && /not set up correctly/.test(rbk.msg ?? ""), rbk.msg);
  const wildPercent = await seedCompany("Wild Fee Co", { feeMode: "percent", feePercent: 0.9 });
  const rw = await call("requestDraw", { amountMinor: 1_000 }, (await worker(wildPercent)).token);
  check("a 90% fee is refused", rw.err === "FAILED_PRECONDITION" && /not set up correctly/.test(rw.msg ?? ""), rw.msg);

  console.log(`\n${pass} passed, ${fail} failed`);
  process.exit(fail === 0 ? 0 : 1);
}

main().catch((e) => { console.error(e); process.exit(1); });
