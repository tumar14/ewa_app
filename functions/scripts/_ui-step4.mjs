import { Browser, seed, sleep } from "./_ui-drive.mjs";

const FN = "http://127.0.0.1:5001/demo-ewa-test/us-central1";
const AUTH = "http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1";
const tokenFor = async (email, password) =>
  (await (await fetch(`${AUTH}/accounts:signInWithPassword?key=k`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ email, password, returnSecureToken: true }) })).json()).idToken;
const call = async (name, data, token) =>
  (await (await fetch(`${FN}/${name}`, { method: "POST", headers: { "Content-Type": "application/json", Authorization: `Bearer ${token}` }, body: JSON.stringify({ data }) })).json());

const data = await seed();
// Prepare a confirmed settlement through the API so the UI run can focus on the later steps.
const adminToken = await tokenFor(data.admin.email, data.admin.password);
const run = (await call("runPayroll", {}, adminToken)).result.payrollRunId;
await call("createSettlement", { payrollRunId: run }, adminToken);
await call("confirmDeductions", { settlementId: run, confirmedMinor: 37_500 }, adminToken);
const settlement = (await data.co.collection("settlements").doc(run).get()).data();
console.log("reference:", settlement.reference, "| company code:", data.shortCode);

const b = new Browser();
await b.start();
const all = async (tag) => { console.log(`--- ${tag}`); console.log([...new Set((await b.labels()).map((l) => l.replace(/\n/g, " | ")).filter((l) => !l.startsWith("-: EWA")))].join("\n")); };
try {
  // ── Admin: settlements list, resolve an exception, audit log ────────────
  await b.login("http://127.0.0.1:8099/", data.admin.email, data.admin.password);
  await b.click("More", { exact: true });
  await sleep(1000);
  await b.click("Track what employers remit");
  await sleep(1500);
  await b.shot("20-settlements-list");
  await all("settlements list");

  await b.click(settlement.reference);
  await sleep(1500);
  const resolve = (await b.nodes()).filter((n) => n.label === "Resolve").sort((x, y) => x.y - y.y)[0];
  await b.clickAt(resolve.x, resolve.y);
  await sleep(800);
  await b.shot("21-resolve-dialog");
  await b.fillBox(0, "ok");
  await b.click("Resolve", { exact: true });
  await sleep(800);
  await b.shot("22-resolve-too-short");
  await all("resolve validation");
  await b.fillBox(0, " and more text");
  await b.click("Resolve", { exact: true });
  await sleep(2500);
  await b.shot("23-after-resolve");
  await all("after resolving one exception");

  // Audit log (also checks the older pushed screens for the white-page problem).
  await b.click("Back", { exact: true });
  await sleep(800);
  await b.click("Back", { exact: true });
  await sleep(800);
  await b.click("Audit Log");
  await sleep(2000);
  await b.shot("24-audit-log");
  await all("audit log");
} catch (e) {
  console.log("ERROR", e.message);
  await b.shot("98-error-admin");
  await all("error state (admin)");
}

try {
  // ── Platform admin: record a payment ─────────────────────────────────────
  await b.open("http://127.0.0.1:8099/");
  const signOut = await b.find("Sign out");
  if (signOut) { await b.clickAt(signOut.x, signOut.y); await sleep(2500); }
  await b.login("http://127.0.0.1:8099/", data.platform.email, data.platform.password);
  await b.shot("30-platform-home");
  await all("platform home");
  await b.click("Record payment");
  await sleep(1200);
  await b.shot("31-record-form");
  await b.fillBox(0, data.shortCode);
  await b.fillBox(1, settlement.reference);
  await b.fillBox(2, "200.00");
  await b.fillBox(4, "FNB-20261016-0001");
  await b.shot("32-record-filled");
  await b.click("Record payment", { exact: true });
  await sleep(2500);
  await b.shot("33-record-result");
  await all("record payment result");
} catch (e) {
  console.log("ERROR", e.message);
  await b.shot("99-error-platform");
  await all("error state (platform)");
} finally {
  b.stop();
  process.exit(0);
}
