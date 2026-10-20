// Checks the platform admin's overview (platformOverview) against the emulator suite:
// exact counts, who may call it, and that nothing personal comes back. Seeds two
// throwaway companies and deletes them afterwards. Run `npm run build` first.
//
// Usage (from functions/, emulators running under the app's project id):
//   GCLOUD_PROJECT=ewa-app-cb943 node scripts/verify-overview.mjs

import { randomBytes } from "node:crypto";
import { initializeApp } from "firebase-admin/app";
import { getFirestore, Timestamp } from "firebase-admin/firestore";
import { getAuth } from "firebase-admin/auth";

process.env.FIRESTORE_EMULATOR_HOST ??= "127.0.0.1:8080";
process.env.FIREBASE_AUTH_EMULATOR_HOST ??= "127.0.0.1:9099";
process.env.GCLOUD_PROJECT ??= "demo-ewa-test";

const PROJECT_ID = process.env.GCLOUD_PROJECT;
const ENDPOINT = `http://127.0.0.1:5001/${PROJECT_ID}/us-central1/platformOverview`;
const AUTH_BASE = "http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1";
const FS_BASE = `http://127.0.0.1:8080/v1/projects/${PROJECT_ID}/databases/(default)/documents`;

initializeApp({ projectId: PROJECT_ID });
const db = getFirestore();
const auth = getAuth();

let pass = 0;
let fail = 0;
function check(label, condition, detail) {
  if (condition) { pass++; console.log(`  OK  ${label}`); }
  else { fail++; console.log(`FAIL  ${label}${detail ? ` - ${detail}` : ""}`); }
}

async function signedIn(claims) {
  const email = `${randomBytes(4).toString("hex")}@example.test`;
  const password = randomBytes(10).toString("hex");
  const post = (path, body) => fetch(`${AUTH_BASE}/${path}?key=k`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body) }).then((r) => r.json());
  const created = await post("accounts:signUp", { email, password, returnSecureToken: true });
  await auth.setCustomUserClaims(created.localId, claims);
  const s = await post("accounts:signInWithPassword", { email, password, returnSecureToken: true });
  return { uid: created.localId, token: s.idToken };
}

const call = async (token) => {
  const res = await fetch(ENDPOINT, { method: "POST", headers: { "Content-Type": "application/json", ...(token ? { Authorization: `Bearer ${token}` } : {}) }, body: JSON.stringify({ data: {} }) });
  const text = await res.text();
  let body = {};
  try { body = JSON.parse(text); } catch { /* keep text */ }
  return { status: res.status, body, text };
};

const NOW = Date.now();
const DAY = 86_400_000;
const tag = randomBytes(3).toString("hex");
const LEAK = `ZZLeakCheck${tag}`;
const created = [];

async function seed() {
  const a = db.collection("companies").doc();
  const b = db.collection("companies").doc();
  created.push(a, b);
  await a.set({ name: `Overview Test A ${tag}`, shortCode: `OA${tag}`.toUpperCase(), currency: "SZL", active: true });
  await b.set({ name: `Overview Test B ${tag}`, shortCode: `OB${tag}`.toUpperCase(), currency: "ZAR", active: false });
  await a.collection("settings").doc("app").set({}); // defaults apply

  const emp = (n, role, active) => a.collection("employees").doc(`${tag}-${n}`).set({ name: `${LEAK} Person ${n}`, role, active, hourlyRate: 40 });
  await Promise.all([
    emp(1, "worker", true), emp(2, "worker", true), emp(3, "worker", true),
    emp(4, "worker", false), emp(5, "supervisor", true), emp(6, "admin", true),
  ]);

  const draw = (n, fields) => a.collection("draw_requests").doc(`${tag}-d${n}`).set({ employeeId: `${tag}-1`, amountMinor: 11111, feeMinor: 555, ...fields });
  const recent = Timestamp.fromMillis(NOW - 60_000);
  await Promise.all([
    draw(1, { status: "pending", createdAt: recent }),
    draw(2, { status: "pending", createdAt: recent }),
    draw(3, { status: "approved", disbursementStatus: "pending", createdAt: recent }),
    draw(4, { status: "approved", disbursementStatus: "paid", createdAt: recent }),
    draw(5, { status: "rejected", createdAt: Timestamp.fromMillis(NOW - 400 * DAY) }), // an old cycle
  ]);

  const settlement = (n, status, outstandingMinor) => a.collection("settlements").doc(`${tag}-s${n}`).set({ status, outstandingMinor, expectedMinor: 77777, receivedMinor: 0 });
  await Promise.all([
    settlement(1, "DUE", 10_000), settlement(2, "PARTIALLY_SETTLED", 2_500), settlement(3, "SETTLED", 0),
    settlement(4, "DRAFT", 99_999), settlement(5, "CANCELLED", 5_000),
  ]);
  return { a, b };
}

async function main() {
  console.log(`Running against ${PROJECT_ID}\n`);
  const platform = await signedIn({ platformAdmin: true });
  const companyAdmin = await signedIn({ companyId: "some-company", platformAdmin: false });
  const { a, b } = await seed();

  console.log("-- who may call it --");
  check("an anonymous caller is refused", (await call(undefined)).status === 401);
  const asCompany = await call(companyAdmin.token);
  check("a company admin is refused", asCompany.status === 403, String(asCompany.status));

  console.log("\n-- the numbers --");
  const r = await call(platform.token);
  check("the platform admin gets an answer", r.status === 200 && r.body.result, r.text.slice(0, 200));
  const result = r.body.result ?? {};
  const rowA = (result.companies ?? []).find((c) => c.companyId === a.id);
  const rowB = (result.companies ?? []).find((c) => c.companyId === b.id);
  check("both test companies are listed", !!rowA && !!rowB);
  check("name, code and currency are the company's public details", rowA?.name === `Overview Test A ${tag}` && rowA?.currency === "SZL" && rowB?.currency === "ZAR");
  check("employees: 6 in all", rowA?.employees === 6, JSON.stringify(rowA));
  check("active employees: 5 (one worker is inactive)", rowA?.activeEmployees === 5);
  check("active workers: 3 (supervisor and admin are not workers)", rowA?.activeWorkers === 3);
  check("advances this cycle: 4 (the old one is not counted)", rowA?.advancesThisCycle === 4);
  check("waiting for approval: 2", rowA?.pendingApproval === 2);
  check("approved and waiting to be paid out: 1", rowA?.awaitingPayout === 1);
  check("open settlements: 2 (due and partially settled)", rowA?.openSettlements === 2);
  check("owed: 12500 (draft, settled and cancelled do not count)", rowA?.owedMinor === 12_500);
  check("an empty, suspended company shows zeros and active=false", rowB && rowB.active === false && rowB.employees === 0 && rowB.activeWorkers === 0 && rowB.advancesThisCycle === 0 && rowB.owedMinor === 0 && rowB.openSettlements === 0, JSON.stringify(rowB));
  const sum = (key) => (result.companies ?? []).reduce((t, c) => t + c[key], 0);
  check("totals equal the sum of the rows", result.totals?.activeWorkers === sum("activeWorkers") && result.totals?.advancesThisCycle === sum("advancesThisCycle") && result.totals?.companies === result.companies?.length);
  check("money is not added across companies", !("owedMinor" in (result.totals ?? {})));
  check("it was not cut short", result.truncated === false);

  console.log("\n-- nothing personal comes back --");
  check("no employee name appears anywhere in the answer", !r.text.includes(LEAK));
  check("no employee id or draw id appears", !r.text.includes(`${tag}-1`) && !r.text.includes(`${tag}-d`));
  check("no individual amount appears", !r.text.includes("11111") && !r.text.includes("555,") );
  const keys = new Set((result.companies ?? []).flatMap((c) => Object.keys(c)));
  check("each row holds only the expected fields", [...keys].sort().join() === ["active", "activeEmployees", "activeWorkers", "advancesThisCycle", "awaitingPayout", "companyId", "currency", "employees", "name", "openSettlements", "owedMinor", "pendingApproval", "shortCode"].join(), [...keys].join());

  console.log("\n-- the platform admin still cannot read the data itself --");
  const get = (path) => fetch(`${FS_BASE}/${path}`, { headers: { Authorization: `Bearer ${platform.token}` } });
  check("employees are still not readable", (await get(`companies/${a.id}/employees/${tag}-1`)).status === 403);
  check("advances are still not readable", (await get(`companies/${a.id}/draw_requests/${tag}-d1`)).status === 403);
  check("settlements are still not readable", (await get(`companies/${a.id}/settlements/${tag}-s1`)).status === 403);

  console.log("\n-- it follows the data --");
  await a.collection("employees").doc(`${tag}-4`).update({ active: true });
  await a.collection("draw_requests").doc(`${tag}-d1`).update({ status: "approved", disbursementStatus: "pending" });
  const r2 = (await call(platform.token)).body.result?.companies.find((c) => c.companyId === a.id);
  check("reactivating a worker and approving a request show up straight away", r2?.activeWorkers === 4 && r2?.pendingApproval === 1 && r2?.awaitingPayout === 2, JSON.stringify(r2));

  console.log(`\n${pass} passed, ${fail} failed`);
}

main()
  .catch((e) => { fail++; console.error(e); })
  .finally(async () => {
    for (const ref of created) await db.recursiveDelete(ref);
    process.exit(fail === 0 ? 0 : 1);
  });
