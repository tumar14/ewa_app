import { Timestamp } from "firebase-admin/firestore";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { callableOptions, db, defaultAppSettings, requireRole } from "./common";
import { parseControls } from "./controls";
import { canSignOff } from "./signoffRules";

const MAX_WINDOW_MS = 36 * 3_600_000;
const MAX_ROWS = 500;
const MAX_SIGN = 200;

/**
 * Hours to sign off for a day, with the employees' names. Supervisors and admins can call it;
 * supervisors have no other access to employee records, so this is how they see who worked.
 * The caller sends the start and end of the day (their local midnight to midnight).
 */
export const getSignOffDay = onCall(callableOptions, async (request) => {
  const { uid, companyId } = await requireRole(request, ["admin", "supervisor"]);
  const { fromMs, toMs } = (request.data ?? {}) as { fromMs?: unknown; toMs?: unknown };
  if (typeof fromMs !== "number" || typeof toMs !== "number" || !(toMs > fromMs) || toMs - fromMs > MAX_WINDOW_MS) {
    throw new HttpsError("invalid-argument", "Choose a single day.");
  }

  const companyRef = db.collection("companies").doc(companyId);
  const [sessionsSnap, settingsSnap] = await Promise.all([
    companyRef.collection("time_sessions")
      .where("clockInTs", ">=", Timestamp.fromMillis(fromMs))
      .where("clockInTs", "<", Timestamp.fromMillis(toMs))
      .orderBy("clockInTs", "desc")
      .limit(MAX_ROWS)
      .get(),
    companyRef.collection("settings").doc("app").get(),
  ]);
  const controls = parseControls({ ...defaultAppSettings(""), ...(settingsSnap.data() ?? {}) });

  const ids = [...new Set(sessionsSnap.docs.map((d) => d.data().employeeId as string))];
  const people = new Map<string, { name: string; employeeNumber: string }>();
  if (ids.length > 0) {
    const docs = await db.getAll(...ids.map((id) => companyRef.collection("employees").doc(id)));
    for (const d of docs) {
      people.set(d.id, { name: String(d.data()?.name ?? ""), employeeNumber: String(d.data()?.employeeNumber ?? "") });
    }
  }

  const ms = (t: unknown) => (t instanceof Timestamp ? t.toMillis() : null);
  return {
    sessions: sessionsSnap.docs.map((d) => {
      const s = d.data();
      const who = people.get(s.employeeId as string);
      return {
        id: d.id,
        employeeId: s.employeeId,
        employeeName: who?.name ?? "",
        employeeNumber: who?.employeeNumber ?? "",
        clockInMs: ms(s.clockInTs),
        clockOutMs: ms(s.clockOutTs),
        source: s.source ?? "manual",
        flagged: s.flagged === true,
        voided: s.voided === true,
        reviewed: s.reviewedAt != null,
        editReason: s.editReason ?? null,
        canSign: canSignOff({
          uid,
          employeeId: s.employeeId as string,
          editedBy: (s.editedBy as string | undefined) ?? null,
          voided: s.voided === true,
          reviewed: s.reviewedAt != null,
          separate: controls.separateSignOff,
        }).ok,
      };
    }),
  };
});

/**
 * Signs off hours. Nobody signs off their own hours, and (when the company requires it, the
 * default) nobody signs off a record they typed in or uploaded themselves, so a second person
 * always looks at manual changes. Records that cannot be signed are reported, not skipped silently.
 */
export const signOffSessions = onCall(callableOptions, async (request) => {
  const { uid, companyId } = await requireRole(request, ["admin", "supervisor"]);
  const { sessionIds } = (request.data ?? {}) as { sessionIds?: unknown };
  if (!Array.isArray(sessionIds) || sessionIds.length === 0 || sessionIds.length > MAX_SIGN
      || sessionIds.some((i) => typeof i !== "string" || i.length === 0 || i.includes("/"))) {
    throw new HttpsError("invalid-argument", `Choose between 1 and ${MAX_SIGN} records to sign off.`);
  }

  const companyRef = db.collection("companies").doc(companyId);
  const settingsSnap = await companyRef.collection("settings").doc("app").get();
  const controls = parseControls({ ...defaultAppSettings(""), ...(settingsSnap.data() ?? {}) });
  const refs = (sessionIds as string[]).map((id) => companyRef.collection("time_sessions").doc(id));
  const docs = await db.getAll(...refs);

  const signed: string[] = [];
  const refused: Array<{ id: string; reason: string }> = [];
  const batch = db.batch();
  const now = Timestamp.now();
  for (const d of docs) {
    const s = d.data();
    if (!d.exists || !s) {
      refused.push({ id: d.id, reason: "Record not found." });
      continue;
    }
    const verdict = canSignOff({
      uid,
      employeeId: s.employeeId as string,
      editedBy: (s.editedBy as string | undefined) ?? null,
      voided: s.voided === true,
      reviewed: s.reviewedAt != null,
      separate: controls.separateSignOff,
    });
    if (!verdict.ok) {
      refused.push({ id: d.id, reason: verdict.reason });
      continue;
    }
    batch.update(d.ref, { reviewedBy: uid, reviewedAt: now });
    signed.push(d.id);
  }
  if (signed.length > 0) {
    batch.set(companyRef.collection("audit_log").doc(), {
      type: "time_signoff",
      signedBy: uid,
      count: signed.length,
      sessionIds: signed.slice(0, 50),
      timestamp: now,
    });
    await batch.commit();
  }
  return { signed: signed.length, refused };
});
