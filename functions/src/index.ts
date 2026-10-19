import { randomInt } from "crypto";
import { getAuth } from "firebase-admin/auth";
import { Timestamp } from "firebase-admin/firestore";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import {
  EmployeeDoc,
  db,
  defaultAppSettings,
  notifyEmployee,
  requireCompanyAdmin,
  requirePlatformAdmin,
} from "./common";

export { requestDraw, decideDrawRequest, disburseDraw } from "./draws";
export { runPayroll } from "./payroll";
export { submitEnquiry } from "./enquiries";
export {
  createSettlement,
  confirmDeductions,
  recordSettlementPayment,
  resolveException,
  cancelSettlement,
} from "./settlements";

interface RosterDoc {
  name: string;
  employeeNumber: string;
  hourlyRate: number;
  department?: string;
  role?: string;
  disbursementMethod?: string;
  disbursementDetails?: Record<string, string>;
  claimCode: string;
  claimed?: boolean;
  claimedByUid?: string | null;
}

interface CompanyDoc {
  name: string;
  shortCode: string;
  active?: boolean;
}

// ── Defaults for a newly-created company's settings subdocs — mirror the
// Dart model defaults (OrgConfig.defaults(), AppPermissions.defaults(), the
// AppSettings()/RateMatrix.empty() constructors) so a fresh company behaves
// exactly like today's single-tenant defaults did. ──────────────────────────

const DEFAULT_DEPARTMENTS = [
  "Cutting", "Sewing", "Finishing", "Quality Control",
  "Packing", "Warehouse", "Maintenance", "Security",
  "Administration", "Management",
];
const DEFAULT_ROLES = ["worker", "supervisor"];

const DEFAULT_PERMISSIONS = {
  worker: {
    drawRequests: ["view", "create"],
    approvals: [], workforce: [], payroll: [], disbursements: [],
    supervisorSignoff: [], auditLog: [], reports: [], settings: [],
  },
  supervisor: {
    drawRequests: ["view", "create"],
    approvals: ["view", "approve"],
    workforce: ["view", "edit"],
    payroll: ["view"],
    disbursements: ["view"],
    supervisorSignoff: ["view", "approve"],
    auditLog: ["view"],
    reports: ["view"],
    settings: ["view"],
  },
};

// Avoids characters easily confused when read/typed aloud (0/O, 1/I/L) —
// same approach as the Dart-side RosterEntry.generateCode() claim codes.
const SHORT_CODE_ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789";

function generateShortCode(): string {
  let code = "";
  for (let i = 0; i < 6; i++) {
    code += SHORT_CODE_ALPHABET[randomInt(SHORT_CODE_ALPHABET.length)];
  }
  return code;
}

/**
 * Creates a Firebase Auth user and the matching Firestore employee doc,
 * scoped to the calling admin's own company (never client-supplied). Sets
 * the companyId custom claim so the new employee's client can resolve which
 * company subcollection to read on first sign-in.
 */
export const createEmployee = onCall(async (request) => {
  const companyId = await requireCompanyAdmin(request);

  const {
    name,
    email,
    temporaryPassword,
    hourlyRate,
    role,
    pin,
    disbursementMethod,
    disbursementDetails,
  } = request.data as {
    name: string;
    email: string;
    temporaryPassword: string;
    hourlyRate: number;
    role?: string;
    pin?: string | null;
    disbursementMethod?: string;
    disbursementDetails?: Record<string, string>;
  };

  const userRecord = await getAuth().createUser({ email, password: temporaryPassword });

  try {
    await getAuth().setCustomUserClaims(userRecord.uid, { companyId, platformAdmin: false });

    await db.collection("companies").doc(companyId).collection("employees").doc(userRecord.uid).set({
      name,
      hourlyRate,
      role: role ?? "worker",
      pin: pin ?? null,
      qrCode: userRecord.uid,
      disbursementMethod: disbursementMethod ?? "bankTransfer",
      disbursementDetails: disbursementDetails ?? {},
      active: true,
    });

    await db.collection("companies").doc(companyId).collection("audit_log").add({
      type: "employee_created",
      employeeId: userRecord.uid,
      name,
      email,
      role: role ?? "worker",
      createdBy: request.auth!.uid,
      createdAt: Timestamp.now(),
      timestamp: Timestamp.now(),
    });
  } catch (e) {
    await getAuth().deleteUser(userRecord.uid).catch(() => undefined);
    throw new HttpsError("internal", "Could not create employee. Please try again.");
  }

  return { uid: userRecord.uid };
});

/**
 * Employee-first onboarding (spec: roster claim). HR pre-loads employee
 * records into a company's private `roster` subcollection; a worker then
 * downloads the app, picks their company, and claims their seat by proving
 * who they are. The match runs entirely here so the roster — which holds
 * wages and bank/MoMo details — is never exposed to the client. On success
 * we create the Auth user, set companyId/platformAdmin custom claims, and
 * materialize the standard companies/{companyId}/employees/{uid} profile.
 *
 * Callable is intentionally UNauthenticated — the caller has no account yet.
 * Verifier: company + employee number + full name + a one-time claim code
 * that HR hands the worker out-of-band (payslip, SMS, printed handout) —
 * company/employee number/name alone are not secret (coworkers know all
 * three), so the code is what actually stops someone claiming a colleague's
 * seat. Errors are deliberately generic so an attacker cannot enumerate
 * valid employee numbers, valid companies, or tell which field was wrong.
 */
export const claimSeat = onCall(async (request) => {
  const { companyId, employeeNumber, fullName, claimCode, email, password } = request.data as {
    companyId?: string;
    employeeNumber?: string;
    fullName?: string;
    claimCode?: string;
    email?: string;
    password?: string;
  };

  if (
    !companyId?.trim() ||
    !employeeNumber?.trim() ||
    !fullName?.trim() ||
    !claimCode?.trim() ||
    !email?.trim() ||
    !password
  ) {
    throw new HttpsError("invalid-argument", "All fields are required.");
  }
  if (password.length < 6) {
    throw new HttpsError("invalid-argument", "Password must be at least 6 characters.");
  }

  const normEmpNum = employeeNumber.trim().toUpperCase();
  const normName = (s: string) => s.trim().toLowerCase().replace(/\s+/g, " ");
  const normCode = (s: string) => s.trim().toUpperCase().replace(/\s+/g, "");
  const cleanEmail = email.trim().toLowerCase();

  // Single generic mismatch error — same for "company not found/inactive",
  // "employee not found", "already claimed", "name doesn't match" and "code
  // doesn't match" so nothing leaks.
  const mismatch = new HttpsError(
    "permission-denied",
    "We couldn't match those details to an unclaimed employee record. Please check with HR.",
  );

  const companyRef = db.collection("companies").doc(companyId);
  const companySnap = await companyRef.get();
  if (!companySnap.exists || (companySnap.data() as CompanyDoc).active === false) {
    throw mismatch;
  }

  const rosterRef = companyRef.collection("roster").doc(normEmpNum);
  const rosterSnap = await rosterRef.get();
  if (!rosterSnap.exists) throw mismatch;
  const roster = rosterSnap.data() as RosterDoc;
  if (roster.claimed) throw mismatch;
  if (normName(roster.name) !== normName(fullName)) throw mismatch;
  if (normCode(roster.claimCode) !== normCode(claimCode)) throw mismatch;

  // Create the Auth user first so we fail fast on a duplicate email.
  let uid: string;
  try {
    const user = await getAuth().createUser({ email: cleanEmail, password });
    uid = user.uid;
  } catch (e: unknown) {
    const code = (e as { code?: string })?.code;
    if (code === "auth/email-already-exists") {
      throw new HttpsError(
        "already-exists",
        "An account with this email already exists. Try signing in instead.",
      );
    }
    if (code === "auth/invalid-email") {
      throw new HttpsError("invalid-argument", "That email address is not valid.");
    }
    throw new HttpsError("internal", "Could not create your account. Please try again.");
  }

  try {
    await getAuth().setCustomUserClaims(uid, { companyId, platformAdmin: false });

    // Claim the roster row and materialize the profile atomically. The
    // in-transaction re-check guards against two people racing on one record.
    await db.runTransaction(async (tx) => {
      const fresh = await tx.get(rosterRef);
      if (!fresh.exists || fresh.data()?.claimed) throw mismatch;
      const r = fresh.data() as RosterDoc;

      tx.set(companyRef.collection("employees").doc(uid), {
        name: r.name,
        email: cleanEmail,
        department: r.department ?? "",
        employeeNumber: normEmpNum,
        hourlyRate: r.hourlyRate,
        role: r.role ?? "worker",
        pin: null,
        pinSalt: null,
        qrCode: null,
        disbursementMethod: r.disbursementMethod ?? "bankTransfer",
        disbursementDetails: r.disbursementDetails ?? {},
        active: true,
        mustChangePassword: false,
        consentedAt: null,
      });

      tx.update(rosterRef, {
        claimed: true,
        claimedByUid: uid,
        claimedAt: Timestamp.now(),
      });
    });
  } catch (e) {
    // Roll the Auth user back so the worker can retry cleanly — no orphans.
    await getAuth().deleteUser(uid).catch(() => undefined);
    if (e instanceof HttpsError) throw e;
    throw new HttpsError("internal", "Could not complete your claim. Please try again.");
  }

  await companyRef.collection("audit_log").add({
    type: "seat_claimed",
    employeeId: uid,
    employeeNumber: normEmpNum,
    name: roster.name,
    email: cleanEmail,
    claimedAt: Timestamp.now(),
    timestamp: Timestamp.now(),
  });

  return { ok: true, uid, companyId };
});

/**
 * Creates a new company shell (platform-admin only): the public company
 * doc + a unique short code + default settings subdocs + the company's
 * first admin employee. This is deliberately the ONLY thing a platform
 * admin can do to a company via this API — no function here or elsewhere
 * gives a platform admin read access to any company's employees, draws,
 * time sessions, payroll, or audit log.
 */
export const createCompany = onCall(async (request) => {
  await requirePlatformAdmin(request);

  const { name, hrEmail, hrPhone, currency, adminName, adminEmail, adminTemporaryPassword } =
    request.data as {
      name?: string;
      hrEmail?: string;
      hrPhone?: string;
      currency?: string;
      adminName?: string;
      adminEmail?: string;
      adminTemporaryPassword?: string;
    };

  if (!name?.trim() || !adminName?.trim() || !adminEmail?.trim() || !adminTemporaryPassword) {
    throw new HttpsError(
      "invalid-argument",
      "Company name and the first admin's name/email/password are required.",
    );
  }
  if (adminTemporaryPassword.length < 6) {
    throw new HttpsError("invalid-argument", "Password must be at least 6 characters.");
  }

  // Reserve a unique short code before creating anything else.
  let shortCode = "";
  for (let attempt = 0; attempt < 5 && !shortCode; attempt++) {
    const candidate = generateShortCode();
    const existing = await db.collection("company_codes").doc(candidate).get();
    if (!existing.exists) shortCode = candidate;
  }
  if (!shortCode) {
    throw new HttpsError("internal", "Could not generate a unique company code. Please try again.");
  }

  const cleanAdminEmail = adminEmail.trim().toLowerCase();
  let adminUid: string;
  try {
    const adminUser = await getAuth().createUser({
      email: cleanAdminEmail,
      password: adminTemporaryPassword,
    });
    adminUid = adminUser.uid;
  } catch (e: unknown) {
    const code = (e as { code?: string })?.code;
    if (code === "auth/email-already-exists") {
      throw new HttpsError("already-exists", "An account with this email already exists.");
    }
    if (code === "auth/invalid-email") {
      throw new HttpsError("invalid-argument", "That admin email address is not valid.");
    }
    throw new HttpsError("internal", "Could not create the company admin account.");
  }

  const companyRef = db.collection("companies").doc();
  const companyId = companyRef.id;
  const companyName = name.trim();

  try {
    await getAuth().setCustomUserClaims(adminUid, { companyId, platformAdmin: false });

    const batch = db.batch();
    batch.set(companyRef, {
      name: companyName,
      shortCode,
      logoUrl: null,
      hrEmail: hrEmail?.trim() ?? "",
      hrPhone: hrPhone?.trim() ?? "",
      currency: currency?.trim() || "SZL",
      active: true,
      createdAt: Timestamp.now(),
      createdBy: request.auth!.uid,
    });
    batch.set(db.collection("company_codes").doc(shortCode), { companyId });
    batch.set(companyRef.collection("settings").doc("org"), {
      departments: DEFAULT_DEPARTMENTS,
      roles: DEFAULT_ROLES,
    });
    batch.set(companyRef.collection("settings").doc("rates"), {});
    batch.set(companyRef.collection("settings").doc("app"), defaultAppSettings(companyName));
    batch.set(companyRef.collection("settings").doc("permissions"), DEFAULT_PERMISSIONS);
    batch.set(companyRef.collection("employees").doc(adminUid), {
      name: adminName.trim(),
      email: cleanAdminEmail,
      department: "",
      employeeNumber: "",
      hourlyRate: 0,
      role: "admin",
      pin: null,
      pinSalt: null,
      qrCode: null,
      disbursementMethod: "bankTransfer",
      disbursementDetails: {},
      active: true,
      mustChangePassword: true,
      consentedAt: null,
    });
    await batch.commit();
  } catch (e) {
    await getAuth().deleteUser(adminUid).catch(() => undefined);
    throw new HttpsError("internal", "Could not create the company. Please try again.");
  }

  return { ok: true, companyId, shortCode };
});

/**
 * Disables the Firebase Auth account so the employee cannot sign in, and
 * sets active=false on their Firestore doc. History is preserved. Confirms
 * the target actually belongs to the caller's own company BEFORE touching
 * Firebase Auth — Auth accounts are a global resource, not scoped by
 * Firestore path, so this check is what stops a company-A admin disabling
 * a company-B worker's login by guessing/reusing a uid.
 */
export const deactivateEmployee = onCall(async (request) => {
  const companyId = await requireCompanyAdmin(request);
  const { employeeId } = request.data as { employeeId: string };

  const employeeRef = db.collection("companies").doc(companyId).collection("employees").doc(employeeId);
  const employeeSnap = await employeeRef.get();
  if (!employeeSnap.exists) {
    throw new HttpsError("not-found", "Employee not found in your company.");
  }

  await getAuth().updateUser(employeeId, { disabled: true });
  await employeeRef.update({ active: false });

  await db.collection("companies").doc(companyId).collection("audit_log").add({
    type: "employee_deactivated",
    employeeId,
    deactivatedBy: request.auth!.uid,
    deactivatedAt: Timestamp.now(),
    timestamp: Timestamp.now(),
  });

  return { ok: true };
});
