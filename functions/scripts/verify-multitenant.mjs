// Ad-hoc multi-tenant isolation verification, run against the Firebase
// emulator suite (auth+firestore+functions on demo-ewa-test — see
// firebase-emulator-windows-gotchas memory for the environment setup this
// needs). NOT a CI test (no test framework wired up for functions/), just a
// repeatable script for re-checking the properties the multi-tenant plan
// promised whenever this code changes again.
//
// Usage (from functions/, with the emulator already running):
//   node scripts/verify-multitenant.mjs

import { initializeApp } from "firebase-admin/app";
import { getFirestore, Timestamp } from "firebase-admin/firestore";
import { getAuth } from "firebase-admin/auth";

process.env.FIRESTORE_EMULATOR_HOST ??= "127.0.0.1:8080";
process.env.FIREBASE_AUTH_EMULATOR_HOST ??= "127.0.0.1:9099";
process.env.GCLOUD_PROJECT ??= "demo-ewa-test";

const PROJECT_ID = process.env.GCLOUD_PROJECT;
const FUNCTIONS_BASE = `http://127.0.0.1:5001/${PROJECT_ID}/us-central1`;
const AUTH_BASE = `http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1`;

initializeApp({ projectId: PROJECT_ID });
const db = getFirestore();

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

async function callFunction(name, data, idToken) {
  const res = await fetch(`${FUNCTIONS_BASE}/${name}`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      ...(idToken ? { Authorization: `Bearer ${idToken}` } : {}),
    },
    body: JSON.stringify({ data }),
  });
  const json = await res.json();
  return { status: res.status, body: json };
}

async function createAuthUserAndSignIn(email, password) {
  await fetch(`${AUTH_BASE}/accounts:signUp?key=fake-key`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ email, password, returnSecureToken: true }),
  });
  return signIn(email, password);
}

async function signIn(email, password) {
  const res = await fetch(`${AUTH_BASE}/accounts:signInWithPassword?key=fake-key`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ email, password, returnSecureToken: true }),
  });
  const json = await res.json();
  return { idToken: json.idToken, uid: json.localId };
}

async function firestoreQuery(idToken, structuredQuery) {
  const res = await fetch(
    `http://127.0.0.1:8080/v1/projects/${PROJECT_ID}/databases/(default)/documents:runQuery`,
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${idToken}`,
      },
      body: JSON.stringify({ structuredQuery }),
    },
  );
  return res;
}

async function main() {
  console.log(`Running against ${PROJECT_ID} (${process.env.FIRESTORE_EMULATOR_HOST})\n`);

  // ── Seed two companies directly (Admin SDK bypasses rules) ──────────────
  const companyARef = db.collection("companies").doc();
  const companyBRef = db.collection("companies").doc();
  const companyA = companyARef.id;
  const companyB = companyBRef.id;

  await companyARef.set({ name: "Company A", shortCode: "AAA111", active: true });
  await companyBRef.set({ name: "Company B", shortCode: "BBB222", active: true });

  // Deliberately overlapping employee number AND claim code across the two
  // companies, with DIFFERENT names — this is the collision scenario the
  // plan's design claims can't happen because the roster lookup path
  // already includes companyId.
  await companyARef.collection("roster").doc("EMP-001").set({
    name: "Alice Alpha", employeeNumber: "EMP-001", hourlyRate: 40,
    claimCode: "SAME123", claimed: false,
  });
  await companyBRef.collection("roster").doc("EMP-001").set({
    name: "Bob Beta", employeeNumber: "EMP-001", hourlyRate: 55,
    claimCode: "SAME123", claimed: false,
  });

  console.log("── claimSeat cross-company isolation ──");

  const wrongCompanyClaim = await callFunction("claimSeat", {
    companyId: companyB,
    employeeNumber: "EMP-001",
    fullName: "Alice Alpha", // Company A's name, submitted against Company B
    claimCode: "SAME123",
    email: "alice.wrong@example.com",
    password: "secret123",
  });
  check(
    "Claiming Company B's EMP-001 as Company A's Alice Alpha is rejected",
    wrongCompanyClaim.status !== 200,
    JSON.stringify(wrongCompanyClaim.body),
  );

  const aliceClaim = await callFunction("claimSeat", {
    companyId: companyA,
    employeeNumber: "EMP-001",
    fullName: "Alice Alpha",
    claimCode: "SAME123",
    email: "alice@example.com",
    password: "secret123",
  });
  check("Alice claims her own Company A seat", aliceClaim.status === 200, JSON.stringify(aliceClaim.body));

  const bobClaim = await callFunction("claimSeat", {
    companyId: companyB,
    employeeNumber: "EMP-001",
    fullName: "Bob Beta",
    claimCode: "SAME123",
    email: "bob@example.com",
    password: "secret123",
  });
  check("Bob claims his own Company B seat (same number+code as Alice)", bobClaim.status === 200, JSON.stringify(bobClaim.body));

  if (aliceClaim.body.result) {
    const aliceEmp = await companyARef.collection("employees").doc(aliceClaim.body.result.uid).get();
    check("Alice's profile landed under Company A", aliceEmp.exists && aliceEmp.data().name === "Alice Alpha");
  }
  if (bobClaim.body.result) {
    const bobEmp = await companyBRef.collection("employees").doc(bobClaim.body.result.uid).get();
    check("Bob's profile landed under Company B", bobEmp.exists && bobEmp.data().name === "Bob Beta");
    const bobInA = await companyARef.collection("employees").doc(bobClaim.body.result.uid).get();
    check("Bob's uid does NOT also exist under Company A", !bobInA.exists);
  }

  // ── Cross-tenant Cloud Function protection ──────────────────────────────
  console.log("\n── Cloud Function companyId is derived from the caller's own claim ──");

  const adminAUid = (await createAuthUserAndSignIn("admin-a@example.com", "secret123")).uid;
  await getAuth().setCustomUserClaims(adminAUid, { companyId: companyA, platformAdmin: false });
  await companyARef.collection("employees").doc(adminAUid).set({
    name: "Admin A", role: "admin", hourlyRate: 0, active: true,
  });
  const adminASignIn = await signIn("admin-a@example.com", "secret123"); // refresh to pick up claims

  // A pending draw request that belongs to Company B only.
  const foreignDrawRef = companyBRef.collection("draw_requests").doc();
  await foreignDrawRef.set({
    employeeId: "someone", amountMinor: 10000, feeMinor: 500, totalMinor: 10500,
    status: "pending", payrollRunId: null,
  });

  const crossTenantDecision = await callFunction(
    "decideDrawRequest",
    { requestId: foreignDrawRef.id, approve: true },
    adminASignIn.idToken,
  );
  check(
    "Company A admin cannot decide a Company B draw request by id (not-found)",
    crossTenantDecision.status !== 200,
    JSON.stringify(crossTenantDecision.body),
  );

  // ── Collection-group query denial ───────────────────────────────────────
  console.log("\n── collectionGroup() query is denied (super-admin-snooping guard) ──");

  const cgRes = await firestoreQuery(adminASignIn.idToken, {
    from: [{ collectionId: "draw_requests", allDescendants: true }],
    limit: 5,
  });
  check(
    "A collectionGroup('draw_requests') query is rejected",
    cgRes.status === 403 || cgRes.status === 400,
    `status=${cgRes.status}`,
  );

  // ── Immediate role-revocation property ──────────────────────────────────
  console.log("\n── demoted admin loses access on the very next request ──");

  const beforeDemotion = await callFunction("runPayroll", {}, adminASignIn.idToken);
  check("Admin A can run payroll while still an admin", beforeDemotion.status === 200, JSON.stringify(beforeDemotion.body));

  await companyARef.collection("employees").doc(adminAUid).update({ role: "worker" });

  const afterDemotion = await callFunction("runPayroll", {}, adminASignIn.idToken);
  check(
    "The SAME (unrefreshed) token is rejected immediately after demotion",
    afterDemotion.status !== 200,
    JSON.stringify(afterDemotion.body),
  );

  console.log(`\n${pass} passed, ${fail} failed.`);
  if (fail > 0) process.exitCode = 1;
}

main().catch((e) => {
  console.error(e);
  process.exitCode = 1;
});
