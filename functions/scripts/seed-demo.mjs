// Seeds demo companies, people and activity so the app can be tested without
// the Blaze plan. Run `npm run build` first (it reads the compiled rule modules
// in lib/ so the data matches what the Cloud Functions would write).
//
//   node scripts/seed-demo.mjs --target emulator            fill the local emulators (full testing)
//   node scripts/seed-demo.mjs --target emulator --remove   remove it again
//   node scripts/seed-demo.mjs --target live --yes          fill the LIVE project (ewa-app-cb943)
//   node scripts/seed-demo.mjs --target live --remove --yes remove only what this script created
//
// Everything it creates is tagged demoSeed = SEED_TAG; accounts use the reserved
// domain @demo.holamanje.test. --remove deletes only those. Passwords are random and written to a file outside the repo, never
// printed. For --target live set GOOGLE_APPLICATION_CREDENTIALS to a service
// account key file first.
//
// Note: on the live project the Cloud Functions are not deployed (Blaze), so the
// data can be browsed there but requesting, approving, paying and payroll only
// work against the emulators.

import { randomBytes, randomInt } from "node:crypto";
import { mkdirSync, writeFileSync } from "node:fs";
import { spawnSync } from "node:child_process";
import path from "node:path";
import { initializeApp } from "firebase-admin/app";
import { getFirestore, Timestamp } from "firebase-admin/firestore";
import { getAuth } from "firebase-admin/auth";
import { accruedMinor, currentCycleStartMs, formatMinor } from "../lib/drawRules.js";
import { outstandingMinor, reconcile, settlementReference, settlementStatus } from "../lib/settlementRules.js";
import { feeFor, parseFeeSchedule } from "../lib/feeSchedule.js";
import { DEFAULT_DEPARTMENTS, DEFAULT_PERMISSIONS, DEFAULT_ROLES, defaultAppSettings } from "../lib/defaults.js";

const SEED_TAG = "hola-manje-demo-v1";
const EMAIL_DOMAIN = "demo.holamanje.test";
const LIVE_PROJECT = "ewa-app-cb943";
// The emulators must run under the same project id the app uses (Android always
// uses google-services.json). Automated tests set EMULATOR_PROJECT=demo-ewa-test.
const EMULATOR_PROJECT = process.env.EMULATOR_PROJECT ?? LIVE_PROJECT;
const HOUR = 3_600_000;
const DAY = 24 * HOUR;
const SAST = 2 * HOUR;

// ── Arguments ────────────────────────────────────────────────────────────────
const args = process.argv.slice(2);
const flag = (name) => args.includes(`--${name}`);
const option = (name) => { const i = args.indexOf(`--${name}`); return i >= 0 ? args[i + 1] : undefined; };
const target = option("target");
const remove = flag("remove");
if (target !== "emulator" && target !== "live") {
  console.error("Usage: node scripts/seed-demo.mjs --target emulator|live [--remove] [--yes] [--out <file>]");
  process.exit(2);
}
if (target === "live") {
  if (!flag("yes")) {
    console.error(`Refusing to touch the LIVE project (${LIVE_PROJECT}) without --yes.`);
    process.exit(2);
  }
  if (!process.env.GOOGLE_APPLICATION_CREDENTIALS) {
    console.error("Set GOOGLE_APPLICATION_CREDENTIALS to a service account key file path first.");
    process.exit(2);
  }
  delete process.env.FIRESTORE_EMULATOR_HOST;
  delete process.env.FIREBASE_AUTH_EMULATOR_HOST;
} else {
  process.env.FIRESTORE_EMULATOR_HOST ??= "127.0.0.1:8080";
  process.env.FIREBASE_AUTH_EMULATOR_HOST ??= "127.0.0.1:9099";
}
const projectId = target === "live" ? LIVE_PROJECT : EMULATOR_PROJECT;
process.env.GCLOUD_PROJECT = projectId;
initializeApp({ projectId });
const db = getFirestore();
const auth = getAuth();
console.log(`Target: ${target === "live" ? "LIVE project " : "emulator, project "}${projectId}${remove ? " (removing demo data)" : ""}`);

// ── Demo content ─────────────────────────────────────────────────────────────
const RATE_TYPE = { type: "lastDayOfMonth", dayOfMonth: 25, weekday: 5 };

const COMPANIES = [
  {
    id: "demo_garments", name: "Demo Garments (TEST)", shortCode: "DEMOGA", hrEmail: `hr@${EMAIL_DOMAIN}`, hrPhone: "TEST-0000",
    people: [
      { slug: "nomsa.admin", name: "Nomsa Dlamini", role: "admin", dept: "Administration", empNo: "DG-001", rate: 0 },
      { slug: "sipho.supervisor", name: "Sipho Mamba", role: "supervisor", dept: "Sewing", empNo: "DG-002", rate: 55 },
      { slug: "thandi.worker", name: "Thandi Nkosi", role: "worker", dept: "Sewing", empNo: "DG-101", rate: 38.5, bank: "FNB", draws: ["paid", "pending"] },
      { slug: "bongani.worker", name: "Bongani Simelane", role: "worker", dept: "Cutting", empNo: "DG-102", rate: 42, mobile: "MTN MoMo", draws: ["pending"] },
      { slug: "lindiwe.worker", name: "Lindiwe Magagula", role: "worker", dept: "Finishing", empNo: "DG-103", rate: 36, bank: "Standard Bank", draws: ["approved"], clockedIn: true },
      { slug: "mandla.worker", name: "Mandla Dube", role: "worker", dept: "Packing", empNo: "DG-104", rate: 34, bank: "Nedbank", draws: ["rejected"] },
      { slug: "zodwa.worker", name: "Zodwa Khumalo", role: "worker", dept: "Quality Control", empNo: "DG-105", rate: 40, mobile: "MTN MoMo", draws: [] },
      { slug: "mbali.newhire", name: "Mbali Hlophe", role: "worker", dept: "Sewing", empNo: "DG-106", rate: 35, bank: "FNB", draws: [], noConsent: true },
    ],
    roster: [
      { name: "Nokuthula Mavuso", empNo: "DG-201", dept: "Sewing", rate: 37 },
      { name: "Sibusiso Gama", empNo: "DG-202", dept: "Cutting", rate: 41 },
      { name: "Phindile Zwane", empNo: "DG-203", dept: "Packing", rate: 33.5 },
    ],
    priorCycleSettlement: ["thandi.worker", "bongani.worker", "lindiwe.worker"],
    // 5% fee, a person approves every request (the defaults).
    settings: {},
  },
  {
    id: "demo_textiles", name: "Sample Textiles (TEST)", shortCode: "DEMOTX", hrEmail: `hr.textiles@${EMAIL_DOMAIN}`, hrPhone: "TEST-0001",
    people: [
      { slug: "themba.admin", name: "Themba Shongwe", role: "admin", dept: "Administration", empNo: "ST-001", rate: 0 },
      { slug: "nelisiwe.worker", name: "Nelisiwe Motsa", role: "worker", dept: "Sewing", empNo: "ST-101", rate: 39, bank: "FNB", draws: ["pending"], clockedIn: true },
      { slug: "vusi.worker", name: "Vusi Ginindza", role: "worker", dept: "Finishing", empNo: "ST-102", rate: 35.5, mobile: "MTN MoMo", draws: ["paid"] },
      { slug: "ayanda.worker", name: "Ayanda Masuku", role: "worker", dept: "Packing", empNo: "ST-103", rate: 33, bank: "Standard Bank", draws: ["auto"] },
    ],
    roster: [{ name: "Fikile Tsabedze", empNo: "ST-201", dept: "Sewing", rate: 36 }],
    priorCycleSettlement: [],
    // A mobile-money style tariff table instead of a percentage, and requests up
    // to E100 are approved automatically (anything larger waits for a person).
    settings: {
      feeMode: "tiered",
      feeTiers: [
        { upToMinor: 5_000, flatMinor: 100, percent: 0 },
        { upToMinor: 20_000, flatMinor: 300, percent: 0 },
        { upToMinor: 100_000, flatMinor: 600, percent: 0.005 },
        { upToMinor: null, flatMinor: 0, percent: 0.015 },
      ],
      autoApprove: true,
      autoApproveMaxMinor: 10_000,
    },
  },
];

const EMULATOR_ONLY_ACCOUNTS = [{ slug: "platform.admin", name: "Demo Platform Admin", claims: { platformAdmin: true } }];

const ENQUIRIES = [
  { type: "employer_registration", companyName: "Kingdom Cut & Sew (TEST)", contactName: "Lungile Sukati", jobTitle: "HR manager", contactEmail: `lungile@${EMAIL_DOMAIN}`, contactPhone: "TEST-0100", employeeCount: 140, payFrequency: "Monthly", industry: "Garment manufacturing", message: "We would like to offer wage access to our machinists.", consent: true, status: "new", hoursAgo: 5 },
  { type: "employer_registration", companyName: "Lubombo Packaging (TEST)", contactName: "Mduduzi Fakudze", jobTitle: "Finance manager", contactEmail: `mduduzi@${EMAIL_DOMAIN}`, contactPhone: "TEST-0101", employeeCount: 60, payFrequency: "Fortnightly", consent: true, status: "handled", note: "Called on Monday, sending terms.", hoursAgo: 72 },
  { type: "contact", name: "Sandile Hlatshwayo", email: `sandile@${EMAIL_DOMAIN}`, topic: "Security", message: "Where is our staff data stored and who can read it?", status: "new", hoursAgo: 26 },
];

// ── Helpers ──────────────────────────────────────────────────────────────────
const uidFor = (slug) => `demo-${slug.replace(/\./g, "-")}`;
const emailFor = (slug) => `${slug}@${EMAIL_DOMAIN}`;
const PASSWORD_ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZabcdefghjkmnpqrstuvwxyz23456789";
const newPassword = () => Array.from({ length: 14 }, () => PASSWORD_ALPHABET[randomInt(PASSWORD_ALPHABET.length)]).join("");
const CODE_ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789";
const newClaimCode = () => Array.from({ length: 6 }, () => CODE_ALPHABET[randomInt(CODE_ALPHABET.length)]).join("");
const ts = (ms) => Timestamp.fromMillis(ms);
const wholeE = (minor) => Math.floor(minor / 100) * 100;

async function findDemoCompanies() {
  const snap = await db.collection("companies").where("demoSeed", "==", SEED_TAG).get();
  return snap.docs;
}

async function listDemoUsers() {
  const out = [];
  let pageToken;
  do {
    const page = await auth.listUsers(1000, pageToken);
    // The reserved .test domain is the marker: it also catches accounts made by
    // claiming a demo seat, whose uids are generated.
    for (const u of page.users) if ((u.email ?? "").endsWith(`@${EMAIL_DOMAIN}`)) out.push(u);
    pageToken = page.pageToken;
  } while (pageToken);
  return out;
}

// ── Removal ──────────────────────────────────────────────────────────────────
async function removeAll() {
  const companies = await findDemoCompanies();
  for (const c of companies) {
    const code = c.data().shortCode;
    await db.recursiveDelete(c.ref);
    if (code) await db.collection("company_codes").doc(code).delete();
    console.log(`  removed company ${c.data().name}`);
  }
  const enquiries = await db.collection("public_enquiries").where("demoSeed", "==", SEED_TAG).get();
  for (const e of enquiries.docs) await e.ref.delete();
  console.log(`  removed ${enquiries.size} enquiries`);
  const users = await listDemoUsers();
  for (const u of users) await auth.deleteUser(u.uid);
  console.log(`  removed ${users.length} demo accounts`);
}

if (remove) {
  await removeAll();
  console.log("Done. Only items tagged as demo data were removed.");
  process.exit(0);
}

// ── Seeding ──────────────────────────────────────────────────────────────────
// Clear leftovers from earlier runs (for example accounts created by claiming a demo seat).
for (const u of await listDemoUsers()) if (!u.uid.startsWith("demo-")) await auth.deleteUser(u.uid);

const nowMs = Date.now();
const cycleStart = currentCycleStartMs(RATE_TYPE, nowMs);
const prevCycleEnd = cycleStart - 1;
const prevCycleStart = currentCycleStartMs(RATE_TYPE, prevCycleEnd);
const credentials = []; // { company, role, name, email, password }
const claimCodes = []; // { company, name, empNo, code }
const summary = { companies: 0, people: 0, sessions: 0, draws: 0, settlements: 0 };

async function ensureUser(slug, name, claims) {
  const uid = uidFor(slug);
  const password = newPassword();
  const base = { email: emailFor(slug), password, displayName: name, emailVerified: true, disabled: false };
  try {
    await auth.updateUser(uid, base);
  } catch (e) {
    if (e?.code !== "auth/user-not-found") throw e;
    await auth.createUser({ uid, ...base });
  }
  await auth.setCustomUserClaims(uid, claims);
  return { uid, password };
}

function shiftSessions(uid, personIndex) {
  const sessions = [];
  for (let day = cycleStart; day < nowMs; day += DAY) {
    const weekday = new Date(day + SAST).getUTCDay();
    if (weekday === 0 || weekday === 6) continue;
    const jitter = ((personIndex * 7 + Math.floor(day / DAY)) % 9) * 60_000; // 0-8 minutes, stable per person and day
    const clockIn = day + 7 * HOUR + jitter;
    const clockOut = day + 15.5 * HOUR + jitter;
    if (clockOut >= nowMs) continue; // today's shift is not finished yet
    sessions.push({ employeeId: uid, clockInTs: ts(clockIn), clockOutTs: ts(clockOut), source: "manual", flagged: false, photoUrl: null, reviewedBy: null, reviewedAt: null });
  }
  return sessions;
}

for (const company of COMPANIES) {
  console.log(`Seeding ${company.name} ...`);
  const companyRef = db.collection("companies").doc(company.id);
  await db.recursiveDelete(companyRef); // clean slate for a re-run
  const adminSlug = company.people.find((p) => p.role === "admin").slug;

  await companyRef.set({
    name: company.name, shortCode: company.shortCode, logoUrl: null, hrEmail: company.hrEmail, hrPhone: company.hrPhone,
    currency: "SZL", active: true, createdAt: ts(nowMs - 20 * DAY), createdBy: uidFor(adminSlug), demoSeed: SEED_TAG,
  });
  await db.collection("company_codes").doc(company.shortCode).set({ companyId: company.id });
  await companyRef.collection("settings").doc("org").set({ departments: DEFAULT_DEPARTMENTS, roles: DEFAULT_ROLES });
  await companyRef.collection("settings").doc("rates").set({});
  const settings = { ...defaultAppSettings(company.name), ...company.settings };
  await companyRef.collection("settings").doc("app").set(settings);
  const feeSchedule = parseFeeSchedule(settings);
  const feeOf = (amountMinor) => feeFor(feeSchedule, amountMinor);
  await companyRef.collection("settings").doc("permissions").set(DEFAULT_PERMISSIONS);
  summary.companies++;

  const writer = db.bulkWriter();
  const adminUid = uidFor(adminSlug);
  const people = [];

  for (const [i, p] of company.people.entries()) {
    const claims = { companyId: company.id, platformAdmin: false };
    const { uid, password } = await ensureUser(p.slug, p.name, claims);
    credentials.push({ company: company.name, role: p.role, name: p.name, email: emailFor(p.slug), password });
    const details = p.bank
      ? { accountNumber: `TEST-${p.empNo}`, bankName: p.bank }
      : p.mobile ? { phoneNumber: `TEST-${p.empNo}`, provider: p.mobile } : {};
    writer.set(companyRef.collection("employees").doc(uid), {
      name: p.name, email: emailFor(p.slug), department: p.dept, employeeNumber: p.empNo, hourlyRate: p.rate, role: p.role,
      pin: null, pinSalt: null, qrCode: null,
      disbursementMethod: p.bank ? "bankTransfer" : p.mobile ? "mobileMoney" : "bankTransfer", disbursementDetails: details,
      active: true, mustChangePassword: false, consentedAt: p.noConsent ? null : ts(nowMs - 10 * DAY),
    });
    people.push({ ...p, uid, index: i });
    summary.people++;
  }

  // Time sessions for everyone who is paid by the hour, plus one open shift.
  const sessionsByUid = new Map();
  for (const p of people.filter((x) => x.role !== "admin")) {
    const sessions = shiftSessions(p.uid, p.index);
    sessionsByUid.set(p.uid, sessions);
    for (const s of sessions) writer.create(companyRef.collection("time_sessions").doc(), s);
    summary.sessions += sessions.length;
    if (p.clockedIn) {
      writer.create(companyRef.collection("time_sessions").doc(), {
        employeeId: p.uid, clockInTs: ts(nowMs - 90 * 60_000), clockOutTs: null, source: "manual", flagged: false,
        photoUrl: null, reviewedBy: null, reviewedAt: null,
      });
    }
  }

  // Advances in the current cycle, sized from what each person has actually earned.
  const accruedOf = (p) => accruedMinor(p.rate, (sessionsByUid.get(p.uid) ?? []).map((s) => ({ clockInMs: s.clockInTs.toMillis(), clockOutMs: s.clockOutTs.toMillis() })), nowMs);
  let drawSeq = 0;
  for (const p of people) {
    if (!p.draws?.length) continue;
    const cap = Math.floor(accruedOf(p) * settings.maxDrawPercent);
    const shares = { paid: 0.25, pending: p.draws.length > 1 ? 0.25 : 0.4, approved: 0.4, rejected: 0.3, auto: 0.2 };
    for (const [k, state] of p.draws.entries()) {
      const amountMinor = wholeE(cap * shares[state]);
      if (amountMinor < 500) continue; // too little earned yet this cycle
      const feeMinor = feeOf(amountMinor);
      const createdAt = Math.max(cycleStart + 2 * HOUR, nowMs - (6 + 9 * (k + 1)) * HOUR);
      const doc = {
        employeeId: p.uid, amountMinor, feeMinor, totalMinor: amountMinor + feeMinor, status: "pending", createdAt: ts(createdAt),
        decidedBy: null, decidedAt: null, payrollRunId: null, disbursementStatus: null, disbursedAt: null, disbursementRef: null, reason: null,
      };
      const id = `${company.id}_draw_${++drawSeq}`;
      if (state !== "pending" && state !== "auto") { doc.decidedBy = adminUid; doc.decidedAt = ts(createdAt + 2 * HOUR); }
      if (state === "approved") { doc.status = "approved"; doc.disbursementStatus = "pending"; }
      if (state === "auto") {
        doc.status = "approved"; doc.disbursementStatus = "pending"; doc.autoApproved = true;
        doc.decidedBy = "policy"; doc.decidedAt = ts(createdAt);
      }
      if (state === "paid") { doc.status = "approved"; doc.disbursementStatus = "completed"; doc.disbursedAt = ts(createdAt + 5 * HOUR); doc.disbursementRef = `DISP-${id.slice(-8).toUpperCase()}`; }
      if (state === "rejected") { doc.status = "rejected"; doc.reason = "Please request a smaller amount until timesheets are signed off."; }
      writer.create(companyRef.collection("draw_requests").doc(id), doc);
      writer.create(companyRef.collection("audit_log").doc(), { type: "draw_request", requestId: id, employeeId: p.uid, amountMinor, feeMinor, timestamp: ts(createdAt) });
      if (state === "auto") writer.create(companyRef.collection("audit_log").doc(), { type: "draw_decision", requestId: id, employeeId: p.uid, amountMinor, approved: true, auto: true, decidedBy: "policy", decidedAt: ts(createdAt), autoApproveCeilingMinor: settings.autoApproveMaxMinor, timestamp: ts(createdAt) });
      else if (state !== "pending") writer.create(companyRef.collection("audit_log").doc(), { type: "draw_decision", requestId: id, employeeId: p.uid, amountMinor, approved: state !== "rejected", decidedBy: adminUid, decidedAt: ts(createdAt + 2 * HOUR), timestamp: ts(createdAt + 2 * HOUR) });
      if (state === "paid") writer.create(companyRef.collection("audit_log").doc(), { type: "disbursement", requestId: id, employeeId: p.uid, amountMinor, disbursementRef: doc.disbursementRef, disbursedBy: adminUid, disbursedAt: ts(createdAt + 5 * HOUR), timestamp: ts(createdAt + 5 * HOUR) });
      summary.draws++;
    }
  }

  // Unclaimed roster rows (for testing "Claim your account").
  for (const r of company.roster) {
    const code = newClaimCode();
    claimCodes.push({ company: company.name, shortCode: company.shortCode, name: r.name, empNo: r.empNo, code });
    writer.create(companyRef.collection("roster").doc(r.empNo), {
      name: r.name, employeeNumber: r.empNo, hourlyRate: r.rate, department: r.dept, role: "worker",
      disbursementMethod: "bankTransfer", disbursementDetails: { accountNumber: `TEST-${r.empNo}`, bankName: "FNB" },
      claimCode: code, claimed: false, claimedByUid: null,
    });
  }

  // A closed payroll run for the previous cycle and its settlement, with a
  // deliberate E50 shortfall so the exception workflow can be tried.
  if (company.priorCycleSettlement.length) {
    const runId = `${company.id}_run_prev`;
    const lines = [];
    const priorShares = [0.3, 0.4, 0.35];
    for (const [k, slug] of company.priorCycleSettlement.entries()) {
      const p = people.find((x) => x.slug === slug);
      const accrued = accruedMinor(p.rate, [{ clockInMs: 0, clockOutMs: 160 * HOUR }], 0);
      const amountMinor = wholeE(Math.floor(accrued * settings.maxDrawPercent) * priorShares[k]);
      const feeMinor = feeOf(amountMinor);
      const drawId = `${company.id}_draw_prev_${k + 1}`;
      writer.create(companyRef.collection("draw_requests").doc(drawId), {
        employeeId: p.uid, amountMinor, feeMinor, totalMinor: amountMinor + feeMinor, status: "approved", createdAt: ts(prevCycleStart + 10 * DAY),
        decidedBy: adminUid, decidedAt: ts(prevCycleStart + 10 * DAY + 2 * HOUR), payrollRunId: runId, disbursementStatus: "completed",
        disbursedAt: ts(prevCycleStart + 10 * DAY + 5 * HOUR), disbursementRef: `DISP-PREV${k + 1}`, reason: null,
      });
      lines.push({ employeeId: p.uid, accruedMinor: accrued, drawsDeductedMinor: amountMinor + feeMinor, netPayoutMinor: accrued - amountMinor - feeMinor, shortfallMinor: 0, drawIds: [drawId] });
    }
    const totals = lines.reduce((t, l) => ({ accruedMinor: t.accruedMinor + l.accruedMinor, drawsDeductedMinor: t.drawsDeductedMinor + l.drawsDeductedMinor, netPayoutMinor: t.netPayoutMinor + l.netPayoutMinor, shortfallMinor: 0 }), { accruedMinor: 0, drawsDeductedMinor: 0, netPayoutMinor: 0, shortfallMinor: 0 });
    writer.create(companyRef.collection("payroll_runs").doc(runId), {
      cycleStart: ts(prevCycleStart), cycleEnd: ts(prevCycleEnd), status: "completed", lines, totals,
      createdBy: adminUid, createdAt: ts(cycleStart + HOUR), completedAt: ts(cycleStart + HOUR),
    });
    writer.create(companyRef.collection("audit_log").doc(), { type: "payroll_run", payrollRunId: runId, drawCount: lines.length, totals, performedBy: adminUid, timestamp: ts(cycleStart + HOUR) });

    const expectedMinor = totals.drawsDeductedMinor;
    const confirmedMinor = expectedMinor - 5_000;
    const figures = { expectedMinor, confirmedMinor, receivedMinor: 0 };
    const { upserts, openCount } = reconcile(figures, []);
    const settlementRef = companyRef.collection("settlements").doc(runId);
    writer.create(settlementRef, {
      payrollRunId: runId, reference: settlementReference(company.shortCode, prevCycleEnd, runId), currency: "SZL",
      cycleStart: ts(prevCycleStart), cycleEnd: ts(prevCycleEnd), expectedMinor, confirmedMinor, receivedMinor: 0,
      outstandingMinor: outstandingMinor(figures), itemCount: lines.length, openExceptionCount: openCount,
      status: settlementStatus(figures, openCount, false), createdAt: ts(cycleStart + 2 * HOUR), createdBy: adminUid,
      confirmedAt: ts(cycleStart + 3 * HOUR), confirmedBy: adminUid,
    });
    for (const l of lines) {
      writer.create(settlementRef.collection("items").doc(l.employeeId), { employeeId: l.employeeId, accruedMinor: l.accruedMinor, drawsDeductedMinor: l.drawsDeductedMinor, netPayoutMinor: l.netPayoutMinor, shortfallMinor: 0 });
    }
    for (const e of upserts) { const { id, ...fields } = e; writer.create(settlementRef.collection("exceptions").doc(id), { ...fields, updatedAt: ts(cycleStart + 3 * HOUR) }); }
    writer.create(companyRef.collection("audit_log").doc(), { type: "settlement_created", settlementId: runId, payrollRunId: runId, expectedMinor, performedBy: adminUid, timestamp: ts(cycleStart + 2 * HOUR) });
    writer.create(companyRef.collection("audit_log").doc(), { type: "settlement_deductions_confirmed", settlementId: runId, expectedMinor, confirmedMinor, performedBy: adminUid, resultingStatus: "EXCEPTION", timestamp: ts(cycleStart + 3 * HOUR) });
    summary.settlements++;
  }
  await writer.close();
}

// Website enquiries (new and handled).
await Promise.all(ENQUIRIES.map(async (e, i) => {
  const { hoursAgo, ...fields } = e;
  await db.collection("public_enquiries").doc(`demo_enquiry_${i + 1}`).set({ ...fields, source: "demo-seed", demoSeed: SEED_TAG, createdAt: ts(nowMs - hoursAgo * HOUR) });
}));

if (target === "emulator") {
  for (const a of EMULATOR_ONLY_ACCOUNTS) {
    const { password } = await ensureUser(a.slug, a.name, a.claims);
    credentials.push({ company: "(platform)", role: "platform admin", name: a.name, email: emailFor(a.slug), password });
  }
}

// ── Credentials file (outside the repo, owner-only) ──────────────────────────
const outFile = option("out") ?? path.join("C:\\Users\\Boniswa\\secrets", `hola-manje-demo-${target}.txt`);
mkdirSync(path.dirname(outFile), { recursive: true });
const lines = [
  `Hola Manje demo accounts (${target === "live" ? `LIVE project ${LIVE_PROJECT}` : "local emulators"}), generated ${new Date(nowMs).toISOString()}`,
  "Test data only. Remove with: node scripts/seed-demo.mjs --target " + target + " --remove" + (target === "live" ? " --yes" : ""),
  "",
  "role | name | email | password",
  ...credentials.map((c) => `${c.role} | ${c.name} (${c.company}) | ${c.email} | ${c.password}`),
  "",
  "Unclaimed seats for the 'Claim your account' flow (company code, employee number, name as shown, one-time code):",
  ...claimCodes.map((c) => `${c.shortCode} | ${c.empNo} | ${c.name} | ${c.code}`),
  "",
];
writeFileSync(outFile, lines.join("\r\n"));
spawnSync("icacls", [outFile, "/inheritance:r", "/grant:r", `${process.env.USERNAME}:(R,W)`], { stdio: "ignore" });

console.log("\nCreated:", JSON.stringify(summary));
console.log(`Accounts (${credentials.length}), passwords are in the owner-only file:\n  ${outFile}`);
for (const c of credentials) console.log(`  ${c.role.padEnd(14)} ${c.email}`);
console.log("\nClaim seats:", claimCodes.map((c) => `${c.shortCode}/${c.empNo}`).join(", "));
process.exit(0);
