import { initializeApp } from "firebase-admin/app";
import { Timestamp, getFirestore } from "firebase-admin/firestore";
import { getMessaging } from "firebase-admin/messaging";
import { HttpsError, CallableRequest } from "firebase-functions/v2/https";

initializeApp();
export const db = getFirestore();

/**
 * Options for the functions that touch money, settings or time records. Set
 * ENFORCE_APP_CHECK=true once the apps send App Check tokens (see README), so only
 * the real apps, not scripts, can call them.
 */
export const callableOptions = { enforceAppCheck: process.env.ENFORCE_APP_CHECK === "true" };

export interface EmployeeDoc {
  role?: string;
  hourlyRate: number;
  disbursementMethod?: string;
  disbursementDetails?: Record<string, string>;
  fcmToken?: string;
  active?: boolean;
  createdAt?: Timestamp;
  lastWorkingDay?: Timestamp;
  payoutChangedAt?: Timestamp;
}

// Money fields ending in "Minor" are integer minor units (cents of a lilangeni).
export interface DrawRequestDoc {
  employeeId: string;
  amountMinor: number;
  feeMinor: number;
  totalMinor: number;
  status: "pending" | "approved" | "rejected";
  createdAt?: Timestamp;
  payrollRunId?: string | null;
  disbursementStatus?: "pending" | "completed" | "failed" | null;
  decidedBy?: string | null;
  firstApprovalBy?: string | null;
}

export { defaultAppSettings } from "./defaults";

/**
 * Verifies the caller is an admin, scoped to their OWN company. companyId is
 * read exclusively from the caller's verified `companyId` custom claim
 * (never from client-supplied request.data) — every function below builds
 * its Firestore paths from the returned value, so a company-A admin cannot
 * act on company-B's data even by supplying a different id in the payload.
 *
 * role is deliberately NOT a custom claim (would delay a demotion/
 * deactivation taking effect until the next token refresh) — it's always a
 * live read of the caller's own employee doc, one Firestore get(), same
 * cost as before company-scoping existed.
 */
export async function requireCompanyAdmin(request: CallableRequest): Promise<string> {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Sign in required.");

  const companyId = request.auth?.token?.companyId as string | undefined;
  if (!companyId) {
    throw new HttpsError("permission-denied", "No company associated with this account.");
  }

  const employee = await db
    .collection("companies").doc(companyId)
    .collection("employees").doc(uid)
    .get();
  if (employee.data()?.role !== "admin") {
    throw new HttpsError("permission-denied", "Admin role required.");
  }
  return companyId;
}

/**
 * The caller's company, id and role, for functions open to more than admins.
 * Role is read live from their employee record and they must be active.
 */
export async function requireRole(
  request: CallableRequest,
  roles: string[],
): Promise<{ uid: string; companyId: string; role: string }> {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Sign in required.");
  const companyId = request.auth?.token?.companyId as string | undefined;
  if (!companyId) throw new HttpsError("permission-denied", "No company associated with this account.");
  const employee = await db.collection("companies").doc(companyId).collection("employees").doc(uid).get();
  const role = employee.data()?.role as string | undefined;
  if (!employee.exists || employee.data()?.active === false || !role || !roles.includes(role)) {
    throw new HttpsError("permission-denied", "You do not have permission to do this.");
  }
  return { uid, companyId, role };
}

export async function requirePlatformAdmin(request: CallableRequest): Promise<void> {
  if (!request.auth?.uid) throw new HttpsError("unauthenticated", "Sign in required.");
  if (request.auth?.token?.platformAdmin !== true) {
    throw new HttpsError("permission-denied", "Platform admin role required.");
  }
}

export async function notifyEmployee(
  companyId: string,
  employeeId: string,
  title: string,
  body: string,
): Promise<void> {
  const empDoc = await db
    .collection("companies").doc(companyId)
    .collection("employees").doc(employeeId)
    .get();
  const fcmToken = empDoc.data()?.fcmToken as string | undefined;
  if (!fcmToken) return;
  try {
    await getMessaging().send({
      token: fcmToken,
      notification: { title, body },
      android: { priority: "high" },
      apns: { payload: { aps: { badge: 1 } } },
    });
  } catch {
    // Stale token — don't fail the whole operation.
  }
}

/**
 * Like requireCompanyAdmin but for any signed-in member: companyId comes only
 * from the verified claim, and the caller must be an active employee of an
 * active company. Returns the caller's uid and company.
 */
export async function requireActiveMember(
  request: CallableRequest,
): Promise<{ uid: string; companyId: string }> {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Sign in required.");

  const companyId = request.auth?.token?.companyId as string | undefined;
  if (!companyId) {
    throw new HttpsError("permission-denied", "No company associated with this account.");
  }

  const companyRef = db.collection("companies").doc(companyId);
  const [company, employee] = await Promise.all([
    companyRef.get(),
    companyRef.collection("employees").doc(uid).get(),
  ]);
  if (!company.exists || company.data()?.active === false) {
    throw new HttpsError("permission-denied", "This company is not active.");
  }
  if (!employee.exists || employee.data()?.active === false) {
    throw new HttpsError("permission-denied", "Your account is not active.");
  }
  return { uid, companyId };
}
