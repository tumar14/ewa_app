// Checks the public enquiry endpoint (submitEnquiry) and the rules around
// public_enquiries against the emulator suite on demo-ewa-test. Same
// environment as verify-multitenant.mjs. Run `npm run build` first.
//
// Usage (from functions/, emulator already running):
//   node scripts/verify-enquiries.mjs

import { randomBytes } from "node:crypto";
import { initializeApp } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";
import { getAuth } from "firebase-admin/auth";

process.env.FIRESTORE_EMULATOR_HOST ??= "127.0.0.1:8080";
process.env.FIREBASE_AUTH_EMULATOR_HOST ??= "127.0.0.1:9099";
process.env.GCLOUD_PROJECT ??= "demo-ewa-test";

const PROJECT_ID = process.env.GCLOUD_PROJECT;
const ENDPOINT = `http://127.0.0.1:5001/${PROJECT_ID}/us-central1/submitEnquiry`;
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

// Each call looks like a different visitor so the per-source limit only
// affects the test that is about the limit.
const post = async (body, { ip = `10.0.${Math.floor(Math.random() * 250)}.${Math.floor(Math.random() * 250)}`, method = "POST", raw } = {}) => {
  const res = await fetch(ENDPOINT, {
    method,
    headers: { "Content-Type": "application/json", "X-Forwarded-For": ip },
    body: method === "POST" ? (raw ?? JSON.stringify(body)) : undefined,
  });
  return { status: res.status, body: await res.json().catch(() => ({})), headers: res.headers };
};

async function signedIn(claims) {
  const email = `${randomBytes(4).toString("hex")}@example.test`;
  const password = randomBytes(10).toString("hex");
  const created = await fetch(`${AUTH_BASE}/accounts:signUp?key=k`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ email, password, returnSecureToken: true }) }).then((r) => r.json());
  await auth.setCustomUserClaims(created.localId, claims);
  const s = await fetch(`${AUTH_BASE}/accounts:signInWithPassword?key=k`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ email, password, returnSecureToken: true }) }).then((r) => r.json());
  return { uid: created.localId, token: s.idToken };
}

const employer = {
  type: "employer_registration",
  companyName: `Verify Co ${randomBytes(2).toString("hex")}`,
  contactName: "Thandi Dlamini",
  contactEmail: "thandi@example.co.sz",
  contactPhone: "+268 7600 0000",
  employeeCount: 120,
  consent: true,
};

async function main() {
  console.log(`Running against ${PROJECT_ID}\n`);

  console.log("-- endpoint --");
  const ok = await post(employer);
  check("a valid employer registration is accepted", ok.status === 200 && ok.body.ok === true && ok.body.reference, JSON.stringify(ok.body));
  const stored = (await db.collection("public_enquiries").where("companyName", "==", employer.companyName).get()).docs;
  check("it is stored once, status new", stored.length === 1 && stored[0].data().status === "new" && stored[0].data().type === "employer_registration");
  check("the raw IP address is not stored", !JSON.stringify(stored[0].data()).includes("10.0."), JSON.stringify(Object.keys(stored[0].data())));
  check("no company or user was created by the submission", (await db.collection("companies").where("name", "==", employer.companyName).get()).empty);

  const injected = await post({ ...employer, companyName: `Injected ${randomBytes(2).toString("hex")}`, role: "admin", platformAdmin: true, status: "handled", companyId: "x" });
  const injDoc = (await db.collection("public_enquiries").where("companyName", ">=", "Injected").where("companyName", "<", "Injectee").get()).docs[0]?.data();
  check("extra fields (role, status, companyId) cannot be smuggled in", injected.status === 200 && injDoc && !("role" in injDoc) && !("platformAdmin" in injDoc) && !("companyId" in injDoc) && injDoc.status === "new", JSON.stringify(injDoc));

  const contact = await post({ type: "contact", name: "Sipho", email: "s@example.com", message: "How are fees decided?", topic: "Pricing" });
  check("a contact message is accepted", contact.status === 200 && contact.body.ok === true);

  check("missing consent is rejected", (await post({ ...employer, consent: false })).status === 400);
  check("bad email is rejected", (await post({ ...employer, contactEmail: "not-an-email" })).status === 400);
  check("zero employees is rejected", (await post({ ...employer, employeeCount: 0 })).status === 400);
  check("markup in a field is rejected", (await post({ ...employer, companyName: "<script>x</script>" })).status === 400);
  check("an unknown form type is rejected", (await post({ type: "grant_admin", companyName: "x" })).status === 400);
  check("invalid JSON is rejected", (await post(null, { raw: "{not json" })).status >= 400);
  check("GET is refused", (await post(null, { method: "GET" })).status === 405);
  check("a body over the size limit is refused", (await post({ ...employer, message: "x".repeat(20000) })).status === 413);

  const before = (await db.collection("public_enquiries").get()).size;
  const spam = await post({ ...employer, website: "http://spam.example" });
  const after = (await db.collection("public_enquiries").get()).size;
  check("a honeypot submission looks successful but stores nothing", spam.status === 200 && after === before);

  const sameIp = "203.0.113.77";
  const results = [];
  for (let i = 0; i < 7; i++) results.push((await post({ ...employer, companyName: `Limit Co ${i}` }, { ip: sameIp })).status);
  check("the 6th submission from one source in an hour is limited", results.slice(0, 5).every((s) => s === 200) && results.slice(5).every((s) => s === 429), results.join(","));
  check("the limit applies per source, not globally", (await post(employer, { ip: "198.51.100.5" })).status === 200);

  console.log("\n-- industry dropdown --");
  const configRef = db.doc("platform_config/website");
  await configRef.delete();
  const withIndustry = (industry) => post({ ...employer, companyName: `Industry Co ${randomBytes(2).toString("hex")}`, industry });
  check("with no list saved, a standard industry is accepted", (await withIndustry("Construction")).status === 200);
  const refused = await withIndustry("Space tourism");
  check("an industry that is not on the list is refused", refused.status === 400 && /industry/i.test(refused.body.error ?? ""), JSON.stringify(refused.body));
  check("the wrong case is refused (it must be exactly what the dropdown offers)", (await withIndustry("construction")).status === 400);
  check("'Other' is always accepted", (await withIndustry("Other")).status === 200);
  check("no industry at all is still accepted", (await post({ ...employer, companyName: `No Industry Co ${randomBytes(2).toString("hex")}` })).status === 200);
  await configRef.set({ industries: ["Sugar farming", "Fishing"], updatedBy: "test" });
  check("once the platform admin saves a list, its entries are accepted", (await withIndustry("Sugar farming")).status === 200);
  check("and standard ones that were taken off are refused", (await withIndustry("Construction")).status === 400);
  check("'Other' still works when it is not in the saved list", (await withIndustry("Other")).status === 200);
  const accepted = (await db.collection("public_enquiries").where("industry", "==", "Sugar farming").get()).docs[0]?.data();
  check("the chosen industry is stored with the enquiry", accepted?.industry === "Sugar farming");
  await configRef.set({ industries: ["", 5, "<b>x</b>"], updatedBy: "test" });
  check("a saved list with nothing usable falls back to the standard list", (await withIndustry("Construction")).status === 200);

  console.log("\n-- firestore rules --");
  const platform = await signedIn({ platformAdmin: true });
  const companyAdmin = await signedIn({ companyId: "some-company", platformAdmin: false });
  const anon = { token: "" };
  const docId = stored[0].id;
  const get = (t, path) => fetch(`${FS_BASE}/${path}`, { headers: t ? { Authorization: `Bearer ${t}` } : {} });
  check("the platform admin can read an enquiry", (await get(platform.token, `public_enquiries/${docId}`)).status === 200);
  check("a company admin cannot read it", (await get(companyAdmin.token, `public_enquiries/${docId}`)).status === 403);
  check("an anonymous visitor cannot read it", (await get(anon.token, `public_enquiries/${docId}`)).status === 403);
  const list = await fetch(`${FS_BASE}/public_enquiries`, { headers: { Authorization: `Bearer ${companyAdmin.token}` } });
  check("a company admin cannot list enquiries", list.status === 403);

  const patch = (t, fields, mask) => fetch(`${FS_BASE}/public_enquiries/${docId}?${mask.map((m) => `updateMask.fieldPaths=${m}`).join("&")}`, { method: "PATCH", headers: { "Content-Type": "application/json", Authorization: `Bearer ${t}` }, body: JSON.stringify({ fields }) });
  const handled = { status: { stringValue: "handled" }, handledBy: { stringValue: platform.uid } };
  check("the platform admin can mark one handled", (await patch(platform.token, handled, ["status", "handledBy"])).status === 200);
  check("a company admin cannot update one", (await patch(companyAdmin.token, handled, ["status", "handledBy"])).status === 403);
  check("the platform admin cannot change the submitted details", (await patch(platform.token, { companyName: { stringValue: "Changed" } }, ["companyName"])).status === 403);
  check("handledBy must be the caller", (await patch(platform.token, { status: { stringValue: "handled" }, handledBy: { stringValue: "someone-else" } }, ["status", "handledBy"])).status === 403);
  const create = await fetch(`${FS_BASE}/public_enquiries`, { method: "POST", headers: { "Content-Type": "application/json", Authorization: `Bearer ${platform.token}` }, body: JSON.stringify({ fields: { type: { stringValue: "contact" } } }) });
  check("not even the platform admin can create one directly", create.status === 403);
  const del = await fetch(`${FS_BASE}/public_enquiries/${docId}`, { method: "DELETE", headers: { Authorization: `Bearer ${platform.token}` } });
  check("or delete one", del.status === 403);
  const limits = await fetch(`${FS_BASE}/enquiry_rate_limits`, { headers: { Authorization: `Bearer ${platform.token}` } });
  check("rate-limit counters are not readable by clients", limits.status === 403);

  console.log("\n-- platform_config rules (industries) --");
  await configRef.set({ industries: ["Sugar farming", "Fishing"], updatedBy: "test" });
  const read = (t, id = "website") => get(t, `platform_config/${id}`);
  check("anyone, signed in or not, can read the website config", (await read(anon.token)).status === 200 && (await read(companyAdmin.token)).status === 200);
  const body = (await (await read(anon.token)).json()).fields?.industries?.arrayValue?.values?.map((v) => v.stringValue);
  check("and the site's REST read returns the list", JSON.stringify(body) === JSON.stringify(["Sugar farming", "Fishing"]), JSON.stringify(body));
  check("no other platform_config document is readable", (await read(platform.token, "secrets")).status === 403);
  const put = (t, fields, id = "website") => fetch(`${FS_BASE}/platform_config/${id}`, { method: "PATCH", headers: { "Content-Type": "application/json", ...(t ? { Authorization: `Bearer ${t}` } : {}) }, body: JSON.stringify({ fields }) });
  const arr = (...names) => ({ arrayValue: { values: names.map((n) => ({ stringValue: n })) } });
  const valid = (uid) => ({ industries: arr("Retail", "Mining"), updatedBy: { stringValue: uid } });
  check("the platform admin can save a list", (await put(platform.token, valid(platform.uid))).status === 200);
  check("a company admin cannot", (await put(companyAdmin.token, valid(companyAdmin.uid))).status === 403);
  check("an anonymous visitor cannot", (await put(undefined, valid("x"))).status === 403);
  check("updatedBy must be the caller", (await put(platform.token, valid("someone-else"))).status === 403);
  check("an empty list is refused", (await put(platform.token, { industries: arr(), updatedBy: { stringValue: platform.uid } })).status === 403);
  check("a list of more than 50 is refused", (await put(platform.token, { industries: arr(...Array.from({ length: 51 }, (_, i) => `I${i}`)), updatedBy: { stringValue: platform.uid } })).status === 403);
  check("other fields cannot be added", (await put(platform.token, { ...valid(platform.uid), banner: { stringValue: "x" } })).status === 403);
  check("a list must be a list", (await put(platform.token, { industries: { stringValue: "Retail" }, updatedBy: { stringValue: platform.uid } })).status === 403);
  check("no other document can be created", (await put(platform.token, valid(platform.uid), "other")).status === 403);
  const delConfig = await fetch(`${FS_BASE}/platform_config/website`, { method: "DELETE", headers: { Authorization: `Bearer ${platform.token}` } });
  check("the config cannot be deleted by a client", delConfig.status === 403);
  await configRef.delete();

  console.log(`\n${pass} passed, ${fail} failed`);
  process.exit(fail === 0 ? 0 : 1);
}

main().catch((e) => { console.error(e); process.exit(1); });
