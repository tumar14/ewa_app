// Checks how time records are protected, against the emulator suite: what the
// firestore.rules let a worker and an admin write, and what the server counts as
// earned hours when an advance is requested. Seeds throwaway companies and deletes
// them afterwards. Run `npm run build` first.
//
// Usage (from functions/, emulators running under the app's project id):
//   GCLOUD_PROJECT=ewa-app-cb943 node scripts/verify-attendance.mjs

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

const tag = randomBytes(3).toString("hex");
const H = 3_600_000;
const NOW = Date.now();
const created = [];

async function user(companyId, claims = {}) {
  const email = `${randomBytes(4).toString("hex")}@example.test`;
  const password = randomBytes(10).toString("hex");
  const post = (path, body) => fetch(`${AUTH}/${path}?key=k`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body) }).then((r) => r.json());
  const c = await post("accounts:signUp", { email, password, returnSecureToken: true });
  await auth.setCustomUserClaims(c.localId, { companyId, platformAdmin: false, ...claims });
  const s = await post("accounts:signInWithPassword", { email, password, returnSecureToken: true });
  return { uid: c.localId, token: s.idToken };
}

// ── Firestore REST helpers (so the rules, not the Admin SDK, judge each write) ──
const val = (x) => {
  if (x === null) return { nullValue: null };
  if (x instanceof Date) return { timestampValue: x.toISOString() };
  if (typeof x === "boolean") return { booleanValue: x };
  if (typeof x === "number") return Number.isInteger(x) ? { integerValue: String(x) } : { doubleValue: x };
  if (typeof x === "string") return { stringValue: x };
  if (typeof x === "object") return { mapValue: { fields: Object.fromEntries(Object.entries(x).map(([k, v]) => [k, val(v)])) } };
  throw new Error("unsupported");
};
const fields = (o) => Object.fromEntries(Object.entries(o).map(([k, v]) => [k, val(v)]));
const SERVER = Symbol("server time");

/** One write. Values that are SERVER become the request time. update=true patches, else creates. */
function write(path, data, { update = false } = {}) {
  const plain = Object.fromEntries(Object.entries(data).filter(([, v]) => v !== SERVER));
  const server = Object.keys(data).filter((k) => data[k] === SERVER);
  const w = { update: { name: `${DOCS}/${path}`, fields: fields(plain) } };
  if (server.length) w.updateTransforms = server.map((f) => ({ fieldPath: f, setToServerValue: "REQUEST_TIME" }));
  if (update) w.updateMask = { fieldPaths: Object.keys(plain) };
  else w.currentDocument = { exists: false };
  return w;
}
async function commit(token, writes) {
  const r = await fetch(`${FS}:commit`, { method: "POST", headers: { "Content-Type": "application/json", Authorization: `Bearer ${token}` }, body: JSON.stringify({ writes }) });
  return r.status;
}
async function remove(token, path) {
  return (await fetch(`${FS}/${path}`, { method: "DELETE", headers: { Authorization: `Bearer ${token}` } })).status;
}
const ok = (s) => s === 200;
const denied = (s) => s === 403;

async function company(name, settings = {}) {
  const ref = db.collection("companies").doc();
  created.push(ref);
  await ref.set({ name: `${name} ${tag}`, shortCode: `${name.slice(0, 2)}${tag}`.toUpperCase(), currency: "SZL", active: true });
  await ref.collection("settings").doc("app").set(settings);
  return ref;
}
async function employee(ref, u, role, extra = {}) {
  await ref.collection("employees").doc(u.uid).set({ name: `Test ${role}`, role, active: true, hourlyRate: 100, employeeNumber: `T-${u.uid.slice(0, 4)}`, ...extra });
}

async function main() {
  console.log(`Running against ${P}\n`);

  // ── Company A: the default settings (editing and uploads allowed) ─────────────
  const A = await company("Attendance A");
  const aAdmin = await user(A.id); await employee(A, aAdmin, "admin");
  const aWorker = await user(A.id); await employee(A, aWorker, "worker");
  const aOther = await user(A.id); await employee(A, aOther, "worker");
  const sess = (id) => `companies/${A.id}/time_sessions/${id}`;
  const punch = (over = {}) => ({ employeeId: aWorker.uid, clockInTs: SERVER, clockOutTs: null, source: "manual", flagged: false, photoUrl: null, reviewedBy: null, reviewedAt: null, ...over });

  console.log("-- a worker clocking in and out --");
  check("clocking in with the server's time works", ok(await commit(aWorker.token, [write(sess("w1"), punch())])));
  check("a start time the phone supplies is refused (no backdating)", denied(await commit(aWorker.token, [write(sess("w2"), punch({ clockInTs: new Date(NOW - 20 * H) }))])));
  check("a start time in the future is refused", denied(await commit(aWorker.token, [write(sess("w3"), punch({ clockInTs: new Date(NOW + 5 * H) }))])));
  check("a finished record cannot be invented", denied(await commit(aWorker.token, [write(sess("w4"), punch({ clockOutTs: new Date(NOW) }))])));
  check("a worker cannot mark their own record as an admin entry or upload", denied(await commit(aWorker.token, [write(sess("w5"), punch({ source: "adminEdit", editedBy: aWorker.uid }))])) && denied(await commit(aWorker.token, [write(sess("w6"), punch({ source: "externalImport", editedBy: aWorker.uid }))])));
  check("a worker cannot sign off or flag their own record", denied(await commit(aWorker.token, [write(sess("w7"), punch({ reviewedBy: aWorker.uid, reviewedAt: new Date(NOW) }))])) && denied(await commit(aWorker.token, [write(sess("w8"), punch({ flagged: true }))])));
  check("a worker cannot add extra fields such as voided", denied(await commit(aWorker.token, [write(sess("w9"), { ...punch(), voided: false })])));
  check("a worker cannot clock in for someone else", denied(await commit(aWorker.token, [write(sess("w10"), punch({ employeeId: aOther.uid }))])));
  check("clocking out with a time the phone supplies is refused", denied(await commit(aWorker.token, [write(sess("w1"), { clockOutTs: new Date(NOW + 9 * H) }, { update: true })])));
  check("a worker cannot change any other field of a record", denied(await commit(aWorker.token, [write(sess("w1"), { flagged: true }, { update: true })])) && denied(await commit(aWorker.token, [write(sess("w1"), { employeeId: aOther.uid }, { update: true })])));
  check("clocking out with the server's time works", ok(await commit(aWorker.token, [write(sess("w1"), { clockOutTs: SERVER }, { update: true })])));
  check("a second clock-out cannot rewrite the end time", denied(await commit(aWorker.token, [write(sess("w1"), { clockOutTs: SERVER }, { update: true })])));
  check("a worker cannot delete a record", denied(await remove(aWorker.token, sess("w1"))));

  console.log("\n-- an admin --");
  const adminAdd = (id, over = {}) => write(sess(id), { employeeId: aWorker.uid, clockInTs: new Date(NOW - 30 * H), clockOutTs: new Date(NOW - 22 * H), source: "adminEdit", flagged: false, photoUrl: null, reviewedBy: aAdmin.uid, reviewedAt: SERVER, editedBy: aAdmin.uid, editedAt: SERVER, editReason: "Forgot to clock in", ...over });
  check("an admin can add missing hours", ok(await commit(aAdmin.token, [adminAdd("a1")])));
  check("but only in their own name (editedBy must be them)", denied(await commit(aAdmin.token, [adminAdd("a2", { editedBy: aOther.uid })])));
  check("an admin can run a kiosk punch", ok(await commit(aAdmin.token, [write(sess("k1"), { employeeId: aWorker.uid, clockInTs: new Date(NOW - 3 * H), clockOutTs: null, source: "kioskPin", flagged: false, photoUrl: null, reviewedBy: null, reviewedAt: null })])));
  check("and clock that person out", ok(await commit(aAdmin.token, [write(sess("k1"), { clockOutTs: new Date(NOW - 1 * H) }, { update: true })])));
  check("an admin can correct times only as a marked, logged edit", ok(await commit(aAdmin.token, [write(sess("a1"), { clockOutTs: new Date(NOW - 21 * H), source: "adminEdit", editedBy: aAdmin.uid, editedAt: SERVER, editReason: "Left an hour earlier" }, { update: true })])));
  check("changing times without marking it as an edit is refused", denied(await commit(aAdmin.token, [write(sess("k1"), { clockInTs: new Date(NOW - 8 * H) }, { update: true })])));
  check("an admin can void a record", ok(await commit(aAdmin.token, [write(sess("a1"), { voided: true, source: "adminEdit", editedBy: aAdmin.uid, editedAt: SERVER, editReason: "Entered for the wrong person" }, { update: true })])));
  check("an admin can sign off and flag", ok(await commit(aAdmin.token, [write(sess("k1"), { reviewedBy: aAdmin.uid, reviewedAt: SERVER, flagged: true }, { update: true })])));
  check("nobody can delete a record, not even an admin", denied(await remove(aAdmin.token, sess("a1"))));
  const other = await user("some-other-company");
  check("an admin of another company can do none of this", denied(await commit(other.token, [adminAdd("x1")])));

  console.log("\n-- the edit log --");
  const log = (id, over = {}) => write(`companies/${A.id}/time_edits/${id}`, { sessionId: "a1", employeeId: aWorker.uid, action: "edit", before: { clockInTs: new Date(NOW - 30 * H) }, after: { clockInTs: new Date(NOW - 29 * H) }, reason: "Left an hour earlier", editedBy: aAdmin.uid, at: SERVER, ...over });
  check("an admin can add a log entry", ok(await commit(aAdmin.token, [log("e1")])));
  check("it must be in their name", denied(await commit(aAdmin.token, [log("e2", { editedBy: aOther.uid })])));
  check("it must carry the server's time, not one they choose", denied(await commit(aAdmin.token, [log("e3", { at: new Date(NOW - 99 * H) })])));
  check("it must give a real reason", denied(await commit(aAdmin.token, [log("e4", { reason: "ok" })])));
  check("it cannot carry other fields", denied(await commit(aAdmin.token, [log("e5", { secret: "x" })])));
  check("an entry cannot be changed", denied(await commit(aAdmin.token, [write(`companies/${A.id}/time_edits/e1`, { reason: "Nothing to see" }, { update: true })])));
  check("an entry cannot be deleted", denied(await remove(aAdmin.token, `companies/${A.id}/time_edits/e1`)));
  check("a worker can neither read nor add entries", denied(await commit(aWorker.token, [log("e6", { editedBy: aWorker.uid })])) && (await fetch(`${FS}/companies/${A.id}/time_edits/e1`, { headers: { Authorization: `Bearer ${aWorker.token}` } })).status === 403);

  console.log("\n-- uploading a file of attendance --");
  const rows = Array.from({ length: 150 }, (_, i) => write(sess(`imp${i}`), { employeeId: aWorker.uid, clockInTs: new Date(NOW - (400 + i) * H), clockOutTs: new Date(NOW - (392 + i) * H), source: "externalImport", flagged: false, photoUrl: null, reviewedBy: null, reviewedAt: null, editedBy: aAdmin.uid, importBatchId: "b1" }));
  check("an admin can upload 150 records in one batch", ok(await commit(aAdmin.token, rows.slice(0, 150))));
  check("an upload must be in the admin's own name", denied(await commit(aAdmin.token, [write(sess("imp-x"), { employeeId: aWorker.uid, clockInTs: new Date(NOW - 900 * H), clockOutTs: new Date(NOW - 892 * H), source: "externalImport", flagged: false, photoUrl: null, reviewedBy: null, reviewedAt: null, editedBy: aOther.uid })])));

  // ── Company B: management has switched manual edits and uploads off ───────────
  const B = await company("Attendance B", { allowManualHourEdits: false, allowAttendanceImport: false });
  const bAdmin = await user(B.id); await employee(B, bAdmin, "admin");
  const bWorker = await user(B.id); await employee(B, bWorker, "worker");
  const bs = (id) => `companies/${B.id}/time_sessions/${id}`;
  const bRec = (id, source, over = {}) => write(bs(id), { employeeId: bWorker.uid, clockInTs: new Date(NOW - 30 * H), clockOutTs: new Date(NOW - 22 * H), source, flagged: false, photoUrl: null, reviewedBy: null, reviewedAt: null, editedBy: bAdmin.uid, editedAt: SERVER, editReason: "Forgot to clock in", ...over });
  console.log("\n-- when management switches them off --");
  check("adding hours by hand is refused", denied(await commit(bAdmin.token, [bRec("b1", "adminEdit")])));
  check("uploading is refused", denied(await commit(bAdmin.token, [bRec("b2", "externalImport")])));
  check("kiosk punches still work", ok(await commit(bAdmin.token, [write(bs("b3"), { employeeId: bWorker.uid, clockInTs: new Date(NOW - 5 * H), clockOutTs: null, source: "kioskQr", flagged: false, photoUrl: null, reviewedBy: null, reviewedAt: null })])));
  check("so does a worker clocking in", ok(await commit(bWorker.token, [write(bs("b4"), punch({ employeeId: bWorker.uid }))])));
  check("correcting a record is refused", denied(await commit(bAdmin.token, [write(bs("b3"), { clockOutTs: new Date(NOW - 1 * H), source: "adminEdit", editedBy: bAdmin.uid, editedAt: SERVER, editReason: "Left early" }, { update: true })])));

  // ── What the server counts when an advance is requested ───────────────────────
  console.log("\n-- what counts towards an advance (server) --");
  const cycleStart = currentCycleStartMs({ type: "lastDayOfMonth", dayOfMonth: 25, weekday: 5 }, NOW);
  if (NOW - 12 * H < cycleStart) {
    console.log("  (skipped: too close to the start of the pay cycle for these records to fall inside it)");
  } else {
    const draw = async (u, amountMinor) => {
      const r = await fetch(FN("requestDraw"), { method: "POST", headers: { "Content-Type": "application/json", Authorization: `Bearer ${u.token}` }, body: JSON.stringify({ data: { amountMinor } }) });
      return { status: r.status, body: await r.json().catch(() => ({})) };
    };
    const seed = async (ref, uid, spans, extra = {}) => {
      for (const [from, to] of spans) {
        await ref.collection("time_sessions").add({ employeeId: uid, clockInTs: Timestamp.fromMillis(from), clockOutTs: to === null ? null : Timestamp.fromMillis(to), source: "manual", flagged: false, photoUrl: null, reviewedBy: null, reviewedAt: null, ...extra });
      }
    };
    const C = await company("Attendance C");
    const mk = async (ref) => { const u = await user(ref.id); await employee(ref, u, "worker"); return u; };

    const stacked = await mk(C); // five copies of the same 8 hours at E100/h
    await seed(C, stacked.uid, Array.from({ length: 5 }, () => [NOW - 10 * H, NOW - 2 * H]));
    check("five overlapping copies of one shift are paid once: E600 is refused", (await draw(stacked, 60_000)).status !== 200);
    check("while E400 (half of one 8-hour shift) is allowed", (await draw(stacked, 40_000)).status === 200);

    const forgot = await mk(C); // clocked in and never out, 3 days ago
    await seed(C, forgot.uid, [[NOW - 72 * H, null]]);
    check("a clock-out forgotten for days counts for 14 hours at most: E800 is refused", (await draw(forgot, 80_000)).status !== 200);
    check("while E600 (half of 14 hours, in this cycle) is allowed", (await draw(forgot, 60_000)).status === 200 || cycleStart > NOW - 72 * H);

    const voided = await mk(C);
    await seed(C, voided.uid, [[NOW - 10 * H, NOW - 2 * H]], { voided: true });
    check("a voided record earns nothing", (await draw(voided, 10_000)).status !== 200);

    const future = await mk(C);
    await seed(C, future.uid, [[NOW + 2 * H, NOW + 10 * H]]);
    check("hours that have not happened yet earn nothing", (await draw(future, 10_000)).status !== 200);

    const D = await company("Attendance D", { countOnlyReviewedHours: true, maxShiftHours: 10 });
    const unsigned = await mk(D);
    await seed(D, unsigned.uid, [[NOW - 10 * H, NOW - 2 * H]]);
    check("when sign-off is required, unsigned hours earn nothing", (await draw(unsigned, 10_000)).status !== 200);
    const signed = await mk(D);
    await seed(D, signed.uid, [[NOW - 11 * H, NOW - 1 * H]], { reviewedBy: "sup", reviewedAt: Timestamp.fromMillis(NOW - 30 * 60_000) });
    check("once signed off they count, up to the company's 10-hour limit (E500 ok)", (await draw(signed, 50_000)).status === 200);
    const signed2 = await mk(D);
    await seed(D, signed2.uid, [[NOW - 11 * H, NOW - 1 * H]], { reviewedBy: "sup", reviewedAt: Timestamp.fromMillis(NOW - 30 * 60_000) });
    check("and no more than that (E600 refused)", (await draw(signed2, 60_000)).status !== 200);
  }

  console.log(`\n${pass} passed, ${fail} failed`);
}

main()
  .catch((e) => { fail++; console.error(e); })
  .finally(async () => {
    for (const ref of created) await db.recursiveDelete(ref);
    process.exit(fail === 0 ? 0 : 1);
  });
