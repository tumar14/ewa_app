// Checks the internal controls against the emulator suite: separation of duties on advances,
// proof of payment, audited and bounded settings, claim-code lockout, employee-record stamps,
// payout-change holds, supervisor sign-off, and the platform ceiling. Seeds throwaway
// companies and deletes them afterwards. Run `npm run build` first.
//
// Usage (from functions/, emulators running under the app's project id):
//   GCLOUD_PROJECT=ewa-app-cb943 node scripts/verify-controls.mjs

import { randomBytes } from "node:crypto";
import { initializeApp } from "firebase-admin/app";
import { getFirestore, Timestamp } from "firebase-admin/firestore";
import { getAuth } from "firebase-admin/auth";
import { currentCycleStartMs } from "../lib/drawRules.js";

process.env.FIRESTORE_EMULATOR_HOST ??= "127.0.0.1:8080";
process.env.FIREBASE_AUTH_EMULATOR_HOST ??= "127.0.0.1:9099";
process.env.GCLOUD_PROJECT ??= "demo-ewa-test";

const P = process.env.GCLOUD_PROJECT;
const AUTH = "http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1";
const DOCS = `projects/${P}/databases/(default)/documents`;
const FS = `http://127.0.0.1:8080/v1/${DOCS}`;
const FN = (name) => `http://127.0.0.1:5001/${P}/us-central1/${name}`;

initializeApp({ projectId: P });
const db = getFirestore();
const auth = getAuth();

let pass = 0;
let fail = 0;
const check = (label, ok, detail) => {
  if (ok) { pass++; console.log(`  OK  ${label}`); } else { fail++; console.log(`FAIL  ${label}${detail ? ` - ${detail}` : ""}`); }
};
const H = 3_600_000;
const DAY = 24 * H;
const NOW = Date.now();
const tag = randomBytes(3).toString("hex");
const created = [];
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function user(companyId, claims = {}) {
  const email = `${randomBytes(4).toString("hex")}@example.test`;
  const password = randomBytes(10).toString("hex");
  const post = (path, body) => fetch(`${AUTH}/${path}?key=k`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body) }).then((r) => r.json());
  const c = await post("accounts:signUp", { email, password, returnSecureToken: true });
  await auth.setCustomUserClaims(c.localId, { companyId, platformAdmin: false, ...claims });
  const s = await post("accounts:signInWithPassword", { email, password, returnSecureToken: true });
  return { uid: c.localId, token: s.idToken };
}
async function call(name, token, data) {
  const r = await fetch(FN(name), { method: "POST", headers: { "Content-Type": "application/json", ...(token ? { Authorization: `Bearer ${token}` } : {}) }, body: JSON.stringify({ data }) });
  const body = await r.json().catch(() => ({}));
  return { status: r.status, body, result: body.result, message: body.error?.message ?? "" };
}
const val = (x) => {
  if (x === null) return { nullValue: null };
  if (x instanceof Date) return { timestampValue: x.toISOString() };
  if (typeof x === "boolean") return { booleanValue: x };
  if (typeof x === "number") return Number.isInteger(x) ? { integerValue: String(x) } : { doubleValue: x };
  if (typeof x === "string") return { stringValue: x };
  if (typeof x === "object") return { mapValue: { fields: Object.fromEntries(Object.entries(x).map(([k, v]) => [k, val(v)])) } };
  throw new Error("unsupported");
};
const SERVER = Symbol("server");
function write(path, data, { update = false } = {}) {
  const plain = Object.fromEntries(Object.entries(data).filter(([, v]) => v !== SERVER));
  const server = Object.keys(data).filter((k) => data[k] === SERVER);
  const w = { update: { name: `${DOCS}/${path}`, fields: Object.fromEntries(Object.entries(plain).map(([k, v]) => [k, val(v)])) } };
  if (server.length) w.updateTransforms = server.map((f) => ({ fieldPath: f, setToServerValue: "REQUEST_TIME" }));
  if (update) w.updateMask = { fieldPaths: Object.keys(plain) };
  else w.currentDocument = { exists: false };
  return w;
}
const commit = async (token, writes) => (await fetch(`${FS}:commit`, { method: "POST", headers: { "Content-Type": "application/json", Authorization: `Bearer ${token}` }, body: JSON.stringify({ writes }) })).status;
const rest = async (token, method, path) => (await fetch(`${FS}/${path}`, { method, headers: token ? { Authorization: `Bearer ${token}` } : {} })).status;

async function company(name, settings = {}) {
  const ref = db.collection("companies").doc();
  created.push(ref);
  await ref.set({ name: `${name} ${tag}`, shortCode: `${name.slice(0, 2)}${tag}`.toUpperCase(), currency: "SZL", active: true });
  await ref.collection("settings").doc("app").set(settings);
  return ref;
}
async function person(ref, role, extra = {}) {
  const u = await user(ref.id);
  await ref.collection("employees").doc(u.uid).set({ name: `${role} ${u.uid.slice(0, 4)}`, role, active: true, hourlyRate: 100, employeeNumber: `E-${u.uid.slice(0, 4)}`, disbursementMethod: "bankTransfer", disbursementDetails: { accountNumber: "SECRET-ACCT-111" }, ...extra });
  return u;
}
const hours = (ref, uid, from = NOW - 10 * H, to = NOW - 2 * H, extra = {}) =>
  ref.collection("time_sessions").add({ employeeId: uid, clockInTs: Timestamp.fromMillis(from), clockOutTs: Timestamp.fromMillis(to), source: "manual", flagged: false, photoUrl: null, reviewedBy: null, reviewedAt: null, ...extra });

async function main() {
  console.log(`Running against ${P}\n`);
  const cycleStart = currentCycleStartMs({ type: "lastDayOfMonth", dayOfMonth: 25, weekday: 5 }, NOW);
  const canTestDraws = NOW - 12 * H >= cycleStart;
  if (!canTestDraws) console.log("(advance checks skipped: too close to the start of the pay cycle)\n");

  // ── Settings: audited, bounded, function-only ─────────────────────────────────
  console.log("-- settings --");
  const S = await company("Controls Settings", { maxDrawPercent: 0.5 });
  const sAdmin = await person(S, "admin");
  const sWorker = await person(S, "worker");
  check("an anonymous caller is refused", (await call("updateSettings", undefined, { maxDrawsPerCycle: 3 })).status === 401);
  check("a worker is refused", (await call("updateSettings", sWorker.token, { maxDrawsPerCycle: 3 })).status === 403);
  const okSave = await call("updateSettings", sAdmin.token, { maxDrawsPerCycle: 3, maxDrawPercent: 0.4, hacked: true });
  check("an admin can save valid settings", okSave.status === 200 && okSave.result?.changed === 2, JSON.stringify(okSave.body).slice(0, 160));
  const saved = (await S.collection("settings").doc("app").get()).data();
  check("they are stored, and unknown keys are not", saved.maxDrawsPerCycle === 3 && saved.maxDrawPercent === 0.4 && !("hacked" in saved));
  const prev = (await S.collection("settings").doc("previous").get()).data();
  check("the replaced values are kept for 'Restore previous'", prev?.maxDrawPercent === 0.5);
  const audit = (await S.collection("audit_log").where("type", "==", "settings_changed").get()).docs.map((d) => d.data());
  check("who changed what from what to what is in the audit log", audit.length === 1 && audit[0].changedBy === sAdmin.uid && audit[0].changes.some((c) => c.field === "maxDrawPercent" && c.from === 0.5 && c.to === 0.4));
  const tooHigh = await call("updateSettings", sAdmin.token, { maxDrawPercent: 0.9 });
  check("above the platform's ceiling is refused with a reason", tooHigh.status === 400 && /at most 50%/.test(tooHigh.message), tooHigh.message);
  check("nonsense values are refused", (await call("updateSettings", sAdmin.token, { maxDrawsPerCycle: 99 })).status === 400 && (await call("updateSettings", sAdmin.token, { feeMode: "percent", feePercent: 0.9 })).status === 400);
  check("a change that changes nothing writes no audit entry", (await call("updateSettings", sAdmin.token, { maxDrawsPerCycle: 3 })).result?.changed === 0 && (await S.collection("audit_log").where("type", "==", "settings_changed").get()).size === 1);
  check("an admin cannot write the settings document directly any more", (await commit(sAdmin.token, [write(`companies/${S.id}/settings/app`, { maxDrawPercent: 1 }, { update: true })])) === 403);
  check("nor the saved copy", (await commit(sAdmin.token, [write(`companies/${S.id}/settings/previous`, { maxDrawPercent: 1 }, { update: true })])) === 403);
  check("other settings pages (roles, rates) still save as before", (await commit(sAdmin.token, [write(`companies/${S.id}/settings/org`, { departments: ["A"], roles: ["worker"] })])) === 200);
  check("people in the company can read the settings", (await rest(sWorker.token, "GET", `companies/${S.id}/settings/app`)) === 200);
  const outsider = await user("some-other-company");
  check("the public and other companies cannot", (await rest(undefined, "GET", `companies/${S.id}/settings/app`)) === 403 && (await rest(outsider.token, "GET", `companies/${S.id}/settings/app`)) === 403);

  // ── Platform ceiling ──────────────────────────────────────────────────────────
  console.log("\n-- platform ceiling --");
  const platform = await user("", { platformAdmin: true });
  const lim = (uid, v) => write("platform_config/limits", { maxDrawPercentCeiling: v, updatedBy: uid });
  check("the platform admin can set it", (await commit(platform.token, [lim(platform.uid, 0.3)])) === 200);
  check("a company admin cannot, and nobody else can read it", (await commit(sAdmin.token, [lim(sAdmin.uid, 1)])) === 403 && (await rest(sAdmin.token, "GET", "platform_config/limits")) === 403);
  check("values outside 5% to 100% are refused", (await commit(platform.token, [write("platform_config/limits", { maxDrawPercentCeiling: 3, updatedBy: platform.uid }, { update: true })])) === 403);
  const lowered = await call("updateSettings", sAdmin.token, { maxDrawPercent: 0.35 });
  check("with the ceiling at 30%, a company asking for 35% is refused", lowered.status === 400 && /at most 30%/.test(lowered.message), lowered.message);

  if (canTestDraws) {
    console.log("\n-- the ceiling on a live request --");
    const C = await company("Controls Ceiling", { maxDrawPercent: 0.5, maxDrawsPerCycle: 10 }); // written directly, as a bypass would
    const w = await person(C, "worker");
    await hours(C, w.uid);
    const draw = (u, amountMinor) => call("requestDraw", u.token, { amountMinor });
    check("even if the company's own limit says 50%, 30% of E800 (E240) is the most: E300 refused", (await draw(w, 30_000)).status !== 200);
    check("and E200 is fine", (await draw(w, 20_000)).status === 200);
    await db.collection("platform_config").doc("limits").delete();
  } else {
    await db.collection("platform_config").doc("limits").delete();
  }

  if (canTestDraws) {
    // ── Separation of duties ────────────────────────────────────────────────────
    console.log("\n-- who approves and who pays --");
    const D = await company("Controls Duties", { maxDrawsPerCycle: 10, dualApprovalAboveMinor: 10_000 });
    const a1 = await person(D, "admin"); const a2 = await person(D, "admin"); const a3 = await person(D, "admin");
    const w1 = await person(D, "worker"); await hours(D, w1.uid);
    const ask = async (u, amountMinor) => (await call("requestDraw", u.token, { amountMinor })).status;
    const latest = async (uid) => (await D.collection("draw_requests").where("employeeId", "==", uid).get()).docs.sort((a, b) => b.data().createdAt.toMillis() - a.data().createdAt.toMillis())[0];

    // an admin who is also an employee
    await hours(D, a1.uid);
    check("an admin who draws an advance of their own", (await ask(a1, 5_000)) === 200);
    const own = await latest(a1.uid);
    const selfApprove = await call("decideDrawRequest", a1.token, { requestId: own.id, approve: true });
    check("cannot approve it themselves", selfApprove.status === 403 && /own advance/.test(selfApprove.message), selfApprove.message);
    check("nor decline it", (await call("decideDrawRequest", a1.token, { requestId: own.id, approve: false })).status === 403);
    check("another admin can approve it", (await call("decideDrawRequest", a2.token, { requestId: own.id, approve: true })).status === 200);
    const selfPay = await call("disburseDraw", a1.token, { requestId: own.id, paymentReference: "MP100000.A1" });
    check("and they cannot record the payment of their own advance either", selfPay.status === 403 && /own advance/.test(selfPay.message), selfPay.message);

    // a large advance
    check("a small advance needs one approval", (await ask(w1, 5_000)) === 200);
    const small = await latest(w1.uid);
    check("(a small one is approved by a single admin)", (await call("decideDrawRequest", a1.token, { requestId: small.id, approve: true })).status === 200);
    check("a large advance is requested", (await ask(w1, 20_000)) === 200);
    const big = await latest(w1.uid);
    check("it is marked as needing two admins", big.data().needsSecondApproval === true);
    const first = await call("decideDrawRequest", a1.token, { requestId: big.id, approve: true });
    check("the first admin's approval keeps it pending", first.status === 200 && first.result?.awaitingSecondApproval === true && (await big.ref.get()).data().status === "pending", JSON.stringify(first.body));
    const again = await call("decideDrawRequest", a1.token, { requestId: big.id, approve: true });
    check("the same admin cannot approve it twice", again.status === 403, String(again.status));
    const second = await call("decideDrawRequest", a2.token, { requestId: big.id, approve: true });
    check("a different admin completes it", second.status === 200 && (await big.ref.get()).data().status === "approved");
    const firstLog = await D.collection("audit_log").where("type", "==", "draw_first_approval").get();
    check("both approvals are in the audit log", firstLog.size === 1 && (await D.collection("audit_log").where("type", "==", "draw_decision").get()).size >= 2);

    // paying
    const noRef = await call("disburseDraw", a3.token, { requestId: big.id });
    check("recording a payment without a reference is refused", noRef.status === 400, noRef.message);
    check("an app-style reference is refused", (await call("disburseDraw", a3.token, { requestId: big.id, paymentReference: "DISP-ABCD1234" })).status === 400);
    const approverPay = await call("disburseDraw", a1.token, { requestId: big.id, paymentReference: "MP201020.1530.A1" });
    check("the admin who gave the first approval cannot pay it", approverPay.status === 403 && /different admin/.test(approverPay.message), approverPay.message);
    check("nor the one who gave the second", (await call("disburseDraw", a2.token, { requestId: big.id, paymentReference: "MP201020.1530.A1" })).status === 403);
    const paid = await call("disburseDraw", a3.token, { requestId: big.id, paymentReference: "MP201020.1530.A1" });
    check("a third admin can, with a real reference", paid.status === 200 && (await big.ref.get()).data().disbursementRef === "MP201020.1530.A1", JSON.stringify(paid.body));
    check("the reference on file is the one typed, and who paid is logged", (await D.collection("audit_log").where("type", "==", "disbursement").get()).docs.some((d) => d.data().disbursedBy === a3.uid && d.data().disbursementRef === "MP201020.1530.A1"));
    const dupe = await call("disburseDraw", a3.token, { requestId: small.id, paymentReference: "MP201020.1530.A1" });
    check("the same reference cannot be used for a second advance", dupe.status === 409 || dupe.status === 400, `${dupe.status} ${dupe.message}`);

    // a company that chooses to allow the same person
    const D2 = await company("Controls Duties2", { separatePayer: false });
    const b1 = await person(D2, "admin"); const bw = await person(D2, "worker"); await hours(D2, bw.uid);
    await call("requestDraw", bw.token, { amountMinor: 5_000 });
    const bd = (await D2.collection("draw_requests").get()).docs[0];
    await call("decideDrawRequest", b1.token, { requestId: bd.id, approve: true });
    check("a company that switches the rule off lets one admin do both", (await call("disburseDraw", b1.token, { requestId: bd.id, paymentReference: "FNB/2026/77" })).status === 200);

    // automatic approval stops at the two-admin threshold
    const E = await company("Controls Auto", { maxDrawsPerCycle: 10, autoApprove: true, autoApproveMaxMinor: 50_000, dualApprovalAboveMinor: 10_000 });
    const ew = await person(E, "worker"); await hours(E, ew.uid);
    await call("requestDraw", ew.token, { amountMinor: 5_000 });
    await call("requestDraw", ew.token, { amountMinor: 20_000 });
    const statuses = (await E.collection("draw_requests").get()).docs.map((d) => [d.data().amountMinor, d.data().status]).sort((a, b) => a[0] - b[0]);
    check("automatic approval applies below the threshold only", JSON.stringify(statuses) === JSON.stringify([[5000, "approved"], [20000, "pending"]]), JSON.stringify(statuses));

    // payout change hold
    console.log("\n-- payout details --");
    const F = await company("Controls Payout", { maxDrawsPerCycle: 10 });
    const fa = await person(F, "admin"); const fb = await person(F, "admin");
    const fw = await person(F, "worker"); await hours(F, fw.uid);
    await call("requestDraw", fw.token, { amountMinor: 5_000 });
    const fd = (await F.collection("draw_requests").get()).docs[0];
    await call("decideDrawRequest", fa.token, { requestId: fd.id, approve: true });
    await F.collection("employees").doc(fw.uid).update({ disbursementDetails: { accountNumber: "SECRET-ACCT-999" }, lastEditedBy: fa.uid });
    let marked = null;
    for (let i = 0; i < 20 && !marked; i++) { await sleep(500); marked = (await F.collection("employees").doc(fw.uid).get()).data().payoutChangedAt; }
    check("changing payout details starts a hold, set by the server", !!marked);
    const held = await call("disburseDraw", fb.token, { requestId: fd.id, paymentReference: "HOLD/2026/1" });
    check("payment is refused during the hold", held.status === 403 && /payout details were changed/.test(held.message), held.message);
    const empAudit = (await F.collection("audit_log").where("type", "==", "employee_changed").get()).docs.map((d) => d.data());
    check("the change is in the audit log without the account number", empAudit.length >= 1 && empAudit[0].changedBy === fa.uid && !JSON.stringify(empAudit).includes("SECRET-ACCT"));
    await F.collection("employees").doc(fw.uid).update({ payoutChangedAt: Timestamp.fromMillis(NOW - 3 * DAY) });
    await sleep(1500);
    check("once the hold has passed, the payment goes through", (await call("disburseDraw", fb.token, { requestId: fd.id, paymentReference: "HOLD/2026/1" })).status === 200);
    await F.collection("employees").doc(fw.uid).update({ hourlyRate: 4000 });
    let rateAudit = false;
    for (let i = 0; i < 20 && !rateAudit; i++) { await sleep(500); rateAudit = (await F.collection("audit_log").where("type", "==", "employee_changed").get()).docs.some((d) => d.data().changes.some((c) => c.field === "hourlyRate" && c.to === 4000)); }
    check("a change of pay rate is logged with the old and new value", rateAudit);

    // new employees and leavers
    console.log("\n-- new employees and leavers --");
    const G = await company("Controls Waits", { maxDrawsPerCycle: 10, newEmployeeWaitDays: 7, pauseDrawsDaysBeforeExit: 7 });
    const gNew = await person(G, "worker", { createdAt: Timestamp.fromMillis(NOW - 2 * DAY) }); await hours(G, gNew.uid);
    const gOld = await person(G, "worker", { createdAt: Timestamp.fromMillis(NOW - 20 * DAY) }); await hours(G, gOld.uid);
    const gLeaver = await person(G, "worker", { lastWorkingDay: Timestamp.fromMillis(NOW + 3 * DAY) }); await hours(G, gLeaver.uid);
    const gLater = await person(G, "worker", { lastWorkingDay: Timestamp.fromMillis(NOW + 40 * DAY) }); await hours(G, gLater.uid);
    const wait = await call("requestDraw", gNew.token, { amountMinor: 5_000 });
    check("a new employee must wait", wait.status === 400 && /after 7 days/.test(wait.message), wait.message);
    check("someone who has been there longer can draw", (await call("requestDraw", gOld.token, { amountMinor: 5_000 })).status === 200);
    const paused = await call("requestDraw", gLeaver.token, { amountMinor: 5_000 });
    check("someone leaving within a week is paused", paused.status === 400 && /paused/.test(paused.message), paused.message);
    check("someone leaving next month can draw", (await call("requestDraw", gLater.token, { amountMinor: 5_000 })).status === 200);

    // rate limit
    console.log("\n-- request rate --");
    const R = await company("Controls Rate", { maxDrawsPerCycle: 10, maxDrawPercent: 0.5 });
    const rw = await person(R, "worker"); await hours(R, rw.uid);
    const codes = [];
    for (let i = 0; i < 7; i++) codes.push((await call("requestDraw", rw.token, { amountMinor: 100 })).status);
    check("at most six requests an hour, the seventh is refused", codes.slice(0, 6).every((c) => c === 200) && codes[6] === 429, codes.join(","));
  }

  // ── Employee records ──────────────────────────────────────────────────────────
  console.log("\n-- employee records (rules) --");
  const T = await company("Controls Records");
  const ta = await person(T, "admin"); const tw = await person(T, "worker");
  const ep = (id) => `companies/${T.id}/employees/${id}`;
  const stamp = (u) => ({ lastEditedBy: u.uid, lastEditedAt: SERVER });
  check("an admin edit without the stamp is refused", (await commit(ta.token, [write(ep(tw.uid), { hourlyRate: 500 }, { update: true })])) === 403);
  check("a stamp in someone else's name is refused", (await commit(ta.token, [write(ep(tw.uid), { hourlyRate: 500, lastEditedBy: tw.uid, lastEditedAt: SERVER }, { update: true })])) === 403);
  check("a properly stamped edit works", (await commit(ta.token, [write(ep(tw.uid), { hourlyRate: 120, ...stamp(ta) }, { update: true })])) === 200);
  check("an admin cannot change when someone was added", (await commit(ta.token, [write(ep(tw.uid), { createdAt: new Date(NOW - 99 * DAY), ...stamp(ta) }, { update: true })])) === 403);
  check("nor clear the payout hold", (await commit(ta.token, [write(ep(tw.uid), { payoutChangedAt: new Date(NOW - 99 * DAY), ...stamp(ta) }, { update: true })])) === 403);
  check("nor delete a person", (await rest(ta.token, "DELETE", ep(tw.uid))) === 403);
  const fresh = { name: "New Person", role: "worker", active: true, hourlyRate: 40 };
  check("a new employee must be created with the server's time", (await commit(ta.token, [write(ep("ghost1"), { ...fresh, createdAt: new Date(NOW - 30 * DAY), ...stamp(ta) })])) === 403);
  check("and with the admin's stamp", (await commit(ta.token, [write(ep("ghost2"), { ...fresh, createdAt: SERVER })])) === 403);
  check("done properly it works", (await commit(ta.token, [write(ep("ghost3"), { ...fresh, createdAt: SERVER, ...stamp(ta) })])) === 200);
  check("a worker can still update their own consent and token", (await commit(tw.token, [write(ep(tw.uid), { fcmToken: "t" }, { update: true })])) === 200);
  check("but not their own pay rate", (await commit(tw.token, [write(ep(tw.uid), { hourlyRate: 9999 }, { update: true })])) === 403);

  // ── Claim codes ───────────────────────────────────────────────────────────────
  console.log("\n-- claim codes --");
  const K = await company("Controls Claims", { claimCodeValidDays: 30 });
  const seat = (n, over = {}) => K.collection("roster").doc(n).set({ employeeNumber: n, name: "Test Claimant", hourlyRate: 30, department: "Packing", role: "worker", claimCode: "ABC234", claimed: false, claimCodeIssuedAt: Timestamp.now(), ...over });
  const claim = (n, code, over = {}) => call("claimSeat", undefined, { companyId: K.id, employeeNumber: n, fullName: "Test Claimant", claimCode: code, email: `${randomBytes(4).toString("hex")}@example.test`, password: randomBytes(8).toString("hex"), ...over });
  await seat("K-1");
  const wrong = [];
  for (let i = 0; i < 5; i++) wrong.push((await claim("K-1", "WRONG1")).status);
  check("wrong codes are refused", wrong.every((s) => s === 403), wrong.join(","));
  const lockedTry = await claim("K-1", "ABC234");
  check("after five wrong tries even the right code is refused", lockedTry.status === 403);
  check("with the same message as any other refusal", lockedTry.message === (await claim("K-1", "WRONG1")).message);
  await K.collection("roster").doc("K-1").update({ claimLockedUntil: null, claimFailures: 0 });
  check("once HR unlocks the seat the right code works", (await claim("K-1", "ABC234")).status === 200);
  await seat("K-2", { claimCodeIssuedAt: Timestamp.fromMillis(NOW - 40 * DAY) });
  check("a code older than the company's limit is refused", (await claim("K-2", "ABC234")).status === 403);
  await K.collection("roster").doc("K-2").update({ claimCodeIssuedAt: Timestamp.now() });
  check("a freshly issued one works", (await claim("K-2", "ABC234")).status === 200);
  await seat("K-3", { claimCodeIssuedAt: Timestamp.fromMillis(NOW - 400 * DAY) });
  await K.collection("settings").doc("app").set({ claimCodeValidDays: 0 });
  check("a company can switch expiry off", (await claim("K-3", "ABC234")).status === 200);
  const claimed = (await K.collection("employees").where("employeeNumber", "==", "K-2").get()).docs[0]?.data();
  check("a claimed employee gets a start date, which the new-employee wait relies on", !!claimed?.createdAt);

  // ── Supervisor sign-off ───────────────────────────────────────────────────────
  console.log("\n-- supervisor sign-off --");
  const V = await company("Controls Signoff");
  const sup = await person(V, "supervisor"); const adm = await person(V, "admin"); const wk = await person(V, "worker");
  const day = { fromMs: NOW - 20 * H, toMs: NOW + 2 * H };
  const s1 = await hours(V, wk.uid, NOW - 9 * H, NOW - 1 * H);
  const s2 = await hours(V, wk.uid, NOW - 18 * H, NOW - 12 * H, { source: "adminEdit", editedBy: adm.uid, editReason: "Forgot to clock in" });
  const s3 = await hours(V, sup.uid, NOW - 9 * H, NOW - 1 * H);
  const view = await call("getSignOffDay", sup.token, day);
  const rows = view.result?.sessions ?? [];
  check("a supervisor sees the day's hours with names", view.status === 200 && rows.length === 3 && rows.some((r) => /worker/.test(r.employeeName)), JSON.stringify(view.body).slice(0, 200));
  check("their own hours cannot be signed by them", rows.find((r) => r.id === s3.id)?.canSign === false && rows.find((r) => r.id === s1.id)?.canSign === true);
  check("a worker cannot use it", (await call("getSignOffDay", wk.token, day)).status === 403 && (await call("getSignOffDay", undefined, day)).status === 401);
  check("a window longer than a day and a bad window are refused", (await call("getSignOffDay", sup.token, { fromMs: NOW - 10 * DAY, toMs: NOW })).status === 400 && (await call("getSignOffDay", sup.token, { fromMs: "x", toMs: 1 })).status === 400);
  check("a supervisor cannot read employee records or hours directly", (await rest(sup.token, "GET", `companies/${V.id}/employees/${wk.uid}`)) === 403 && (await rest(sup.token, "GET", `companies/${V.id}/time_sessions/${s1.id}`)) === 403);
  const signed = await call("signOffSessions", sup.token, { sessionIds: [s1.id, s2.id, s3.id] });
  check("a supervisor signs what they may, and is told what they may not", signed.result?.signed === 2 && signed.result?.refused.length === 1 && /own hours/.test(signed.result.refused[0].reason), JSON.stringify(signed.body));
  const d1 = (await s1.get()).data();
  check("the record names who signed it", d1.reviewedBy === sup.uid && !!d1.reviewedAt);
  const adminTry = await call("signOffSessions", adm.token, { sessionIds: [s3.id] });
  check("an admin can sign a supervisor's hours", adminTry.result?.signed === 1);
  const s4 = await hours(V, wk.uid, NOW - 30 * H, NOW - 25 * H, { source: "adminEdit", editedBy: adm.uid, editReason: "Phone had no signal" });
  const own = await call("signOffSessions", adm.token, { sessionIds: [s4.id] });
  check("an admin cannot sign off a record they typed in themselves", own.result?.signed === 0 && /entered or uploaded/.test(own.result?.refused?.[0]?.reason ?? ""), JSON.stringify(own.body));
  check("a worker cannot sign anything", (await call("signOffSessions", wk.token, { sessionIds: [s4.id] })).status === 403);
  check("an admin cannot sign off by writing the record directly", (await commit(adm.token, [write(`companies/${V.id}/time_sessions/${s4.id}`, { reviewedBy: adm.uid, reviewedAt: SERVER }, { update: true })])) === 403);
  check("a bad list of records is refused", (await call("signOffSessions", sup.token, { sessionIds: [] })).status === 400 && (await call("signOffSessions", sup.token, { sessionIds: ["a/b"] })).status === 400);

  console.log(`\n${pass} passed, ${fail} failed`);
}

main()
  .catch((e) => { fail++; console.error(e); })
  .finally(async () => {
    for (const ref of created) await db.recursiveDelete(ref);
    await db.collection("platform_config").doc("limits").delete().catch(() => undefined);
    process.exit(fail === 0 ? 0 : 1);
  });
