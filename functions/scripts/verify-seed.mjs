// Checks that the demo data written by seed-demo.mjs works with the real Cloud
// Functions and security rules, by signing in as the seeded people (emulator
// only). It CHANGES the demo data (approves an advance, claims a seat, etc.), so
// re-run `node scripts/seed-demo.mjs --target emulator` afterwards to reset it.
//
//   node scripts/verify-seed.mjs [path-to-credentials-file]

import { readFileSync } from "node:fs";
import { initializeApp } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";

process.env.FIRESTORE_EMULATOR_HOST ??= "127.0.0.1:8080";
process.env.FIREBASE_AUTH_EMULATOR_HOST ??= "127.0.0.1:9099";
process.env.GCLOUD_PROJECT ??= process.env.EMULATOR_PROJECT ?? "ewa-app-cb943";
const PROJECT = process.env.GCLOUD_PROJECT;
const FN = `http://127.0.0.1:5001/${PROJECT}/us-central1`;
const AUTH = "http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1";
const FS = `http://127.0.0.1:8080/v1/projects/${PROJECT}/databases/(default)/documents`;
initializeApp({ projectId: PROJECT });
const db = getFirestore();

const file = process.argv[2] ?? "C:\\Users\\Boniswa\\secrets\\hola-manje-demo-emulator.txt";
const text = readFileSync(file, "utf8").split(/\r?\n/);
const accounts = new Map(); // email -> password
const seats = [];
for (const line of text) {
  const parts = line.split(" | ");
  if (parts.length === 4 && parts[2].includes("@")) accounts.set(parts[2], parts[3]);
  if (parts.length === 4 && /^DEMO[A-Z]{2}$/.test(parts[0])) seats.push({ shortCode: parts[0], empNo: parts[1], name: parts[2], code: parts[3] });
}

let pass = 0, fail = 0;
const check = (label, cond, detail) => { if (cond) { pass++; console.log(`  OK  ${label}`); } else { fail++; console.log(`FAIL  ${label}${detail ? " - " + detail : ""}`); } };
const signIn = async (email) => {
  const r = await fetch(`${AUTH}/accounts:signInWithPassword?key=k`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ email, password: accounts.get(email), returnSecureToken: true }) }).then((x) => x.json());
  return r.idToken;
};
const call = async (name, data, token) => {
  const res = await fetch(`${FN}/${name}`, { method: "POST", headers: { "Content-Type": "application/json", ...(token ? { Authorization: `Bearer ${token}` } : {}) }, body: JSON.stringify({ data }) });
  const body = await res.json();
  return { status: res.status, err: body.error?.status, msg: body.error?.message, result: body.result };
};
const get = (token, p) => fetch(`${FS}/${p}`, { headers: { Authorization: `Bearer ${token}` } });
const E = (c) => `${c}@demo.holamanje.test`;

const tok = {};
for (const slug of ["nomsa.admin", "sipho.supervisor", "thandi.worker", "bongani.worker", "lindiwe.worker", "zodwa.worker", "mbali.newhire", "themba.admin", "nelisiwe.worker", "platform.admin"]) tok[slug] = await signIn(E(slug));

console.log("-- sign-in and roles --");
check("every seeded account can sign in", Object.values(tok).every(Boolean));
const claims = (t) => JSON.parse(Buffer.from(t.split(".")[1], "base64url").toString());
check("the admin's token carries the company and not platform rights", claims(tok["nomsa.admin"]).companyId === "demo_garments" && claims(tok["nomsa.admin"]).platformAdmin === false);
check("the demo platform admin has the platform claim", claims(tok["platform.admin"]).platformAdmin === true);

console.log("\n-- what each person can read (rules) --");
const own = await db.collection("companies").doc("demo_garments").collection("draw_requests").where("employeeId", "==", "demo-thandi-worker").get();
const outstanding = own.docs.filter((d) => d.data().payrollRunId === null);
check("Thandi has this cycle's advances (paid + pending) plus one settled last cycle", own.size === 3 && outstanding.length === 2, `found ${own.size} total, ${outstanding.length} outstanding`);
const readOwn = await get(tok["thandi.worker"], `companies/demo_garments/draw_requests/${own.docs[0].id}`);
check("a worker can read her own advance", readOwn.status === 200);
const bonganiDraw = (await db.collection("companies").doc("demo_garments").collection("draw_requests").where("employeeId", "==", "demo-bongani-worker").get()).docs[0];
check("a worker cannot read a colleague's advance", (await get(tok["thandi.worker"], `companies/demo_garments/draw_requests/${bonganiDraw.id}`)).status === 403);
check("an admin can read the company's advances", (await get(tok["nomsa.admin"], `companies/demo_garments/draw_requests/${bonganiDraw.id}`)).status === 200);
check("another company's admin cannot", (await get(tok["themba.admin"], `companies/demo_garments/draw_requests/${bonganiDraw.id}`)).status === 403);
check("the platform admin cannot read company advances", (await get(tok["platform.admin"], `companies/demo_garments/draw_requests/${bonganiDraw.id}`)).status === 403);
check("the platform admin can read website enquiries", (await get(tok["platform.admin"], "public_enquiries/demo_enquiry_1")).status === 200);
check("a company admin cannot read website enquiries", (await get(tok["nomsa.admin"], "public_enquiries/demo_enquiry_1")).status === 403);

console.log("\n-- advances (requestDraw) --");
const zodwa = await call("requestDraw", { amountMinor: 1000 }, tok["zodwa.worker"]);
check("Zodwa (no advances yet) can request E10", zodwa.status === 200, zodwa.msg);
const tooMuch = await call("requestDraw", { amountMinor: 99_999_900 }, tok["bongani.worker"]);
check("a request far above the limit is refused with the amount in the message", tooMuch.err === "FAILED_PRECONDITION" && /maximum/.test(tooMuch.msg ?? ""), tooMuch.msg);
const thandi = await call("requestDraw", { amountMinor: 500 }, tok["thandi.worker"]);
check("Thandi already used both advances this cycle, so a third is refused", thandi.err === "FAILED_PRECONDITION" && /limit of 2/.test(thandi.msg ?? ""), thandi.msg);

console.log("\n-- approvals and payment records --");
const approve = await call("decideDrawRequest", { requestId: bonganiDraw.id, approve: true }, tok["nomsa.admin"]);
check("the admin can approve Bongani's pending advance (it fits his cap)", approve.status === 200, approve.msg);
const crossCompany = await call("decideDrawRequest", { requestId: bonganiDraw.id, approve: true }, tok["themba.admin"]);
check("another company's admin cannot decide it", crossCompany.err === "NOT_FOUND", crossCompany.err);
const lindiwe = (await db.collection("companies").doc("demo_garments").collection("draw_requests").where("employeeId", "==", "demo-lindiwe-worker").get()).docs[0];
const paid = await call("disburseDraw", { requestId: lindiwe.id }, tok["nomsa.admin"]);
check("the admin can mark Lindiwe's approved advance as paid", paid.status === 200, paid.msg);
const workerApprove = await call("decideDrawRequest", { requestId: bonganiDraw.id, approve: true }, tok["thandi.worker"]);
check("a worker cannot approve advances", workerApprove.err === "PERMISSION_DENIED");

console.log("\n-- settlement from the seeded run --");
const settlement = (await db.collection("companies").doc("demo_garments").collection("settlements").get()).docs[0];
const sd = settlement.data();
check("the seeded settlement is waiting on an open exception", sd.status === "EXCEPTION" && sd.openExceptionCount === 1 && sd.confirmedMinor === sd.expectedMinor - 5000);
const resolved = await call("resolveException", { settlementId: settlement.id, exceptionId: "deduction_mismatch", note: "Payroll confirmed the E50 difference was unpaid leave." }, tok["nomsa.admin"]);
check("the admin can resolve the shortfall with a note", resolved.status === 200 && resolved.result?.status === "DUE", JSON.stringify(resolved.result ?? resolved.msg));
const pay = await call("recordSettlementPayment", { shortCode: "DEMOGA", reference: sd.reference, amountMinor: sd.confirmedMinor, currency: "SZL", providerTransactionId: "DEMO-BANK-0001" }, tok["platform.admin"]);
check("the platform admin can record the bank payment against its reference", pay.status === 200 && pay.result?.receivedMinor === sd.confirmedMinor, pay.msg);
const after = (await settlement.ref.get()).data();
check("the settlement is now part-settled with the E50 still outstanding to expected", after.receivedMinor === sd.confirmedMinor && after.outstandingMinor === 5000, JSON.stringify({ s: after.status, o: after.outstandingMinor }));

console.log("\n-- payroll over the seeded cycle --");
const payroll = await call("runPayroll", {}, tok["nomsa.admin"]);
check("the admin can run payroll for the current cycle", payroll.status === 200, payroll.msg);
const run = (await db.collection("companies").doc("demo_garments").collection("payroll_runs").doc(payroll.result?.payrollRunId ?? "x").get()).data();
check("it deducted the outstanding approved advances and covered every worker", run?.status === "completed" && run.totals.drawsDeductedMinor > 0 && run.lines.length >= 6, JSON.stringify(run?.totals));

console.log("\n-- claim your account --");
const seat = seats.find((s) => s.shortCode === "DEMOGA" && s.empNo === "DG-201");
const company = (await db.collection("company_codes").doc("DEMOGA").get()).data();
const wrong = await call("claimSeat", { companyId: company.companyId, employeeNumber: "DG-201", fullName: seat.name, claimCode: "WRONG1", email: "wrong@demo.holamanje.test", password: "Test-Password-1" });
check("a wrong one-time code is refused", wrong.status !== 200);
const claim = await call("claimSeat", { companyId: company.companyId, employeeNumber: "DG-201", fullName: seat.name, claimCode: seat.code, email: "nokuthula.claimed@demo.holamanje.test", password: "Test-Password-1" });
check("the right code claims the seat and creates the account", claim.status === 200, claim.msg);
const again = await call("claimSeat", { companyId: company.companyId, employeeNumber: "DG-201", fullName: seat.name, claimCode: seat.code, email: "someone.else@demo.holamanje.test", password: "Test-Password-1" });
check("the same seat cannot be claimed twice", again.status !== 200);

console.log(`\n${pass} passed, ${fail} failed. (This changed the demo data: re-run seed-demo.mjs --target emulator to reset it. A claimed demo account, if any, is removed by --remove.)`);
process.exit(fail ? 1 : 0);
