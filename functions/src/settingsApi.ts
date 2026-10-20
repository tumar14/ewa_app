import { Timestamp } from "firebase-admin/firestore";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { callableOptions, db, defaultAppSettings, requireCompanyAdmin } from "./common";
import { DEFAULT_PLATFORM_DRAW_CEILING } from "./controls";
import { diffSettings, validateSettings } from "./settingsRules";

/**
 * Saves a company's operating settings (fee, limits, approvals, attendance rules). The admin
 * app cannot write settings/app directly (see firestore.rules): every change comes through
 * here, is checked against sensible ranges and the platform's ceiling on advances, and is
 * written to the audit log with who changed what from which value to which. The values it
 * replaces are kept at settings/previous so a change, or a reset, can be undone.
 */
export const updateSettings = onCall(callableOptions, async (request) => {
  const companyId = await requireCompanyAdmin(request);
  const uid = request.auth!.uid;
  const companyRef = db.collection("companies").doc(companyId);
  const appRef = companyRef.collection("settings").doc("app");
  const previousRef = companyRef.collection("settings").doc("previous");

  const platform = await db.collection("platform_config").doc("limits").get();
  const ceiling = Number(platform.data()?.maxDrawPercentCeiling ?? DEFAULT_PLATFORM_DRAW_CEILING);

  const changed = await db.runTransaction(async (tx) => {
    const current = { ...defaultAppSettings(""), ...((await tx.get(appRef)).data() ?? {}) } as Record<string, unknown>;
    const checked = validateSettings(request.data, current, ceiling);
    if (!checked.ok) throw new HttpsError("invalid-argument", checked.error);

    const changes = diffSettings(current, checked.patch);
    if (changes.length === 0) return 0;

    tx.set(previousRef, { ...current, savedAt: Timestamp.now(), savedBy: uid });
    tx.set(appRef, checked.patch, { merge: true });
    tx.set(companyRef.collection("audit_log").doc(), {
      type: "settings_changed",
      changedBy: uid,
      changes: changes.slice(0, 40),
      timestamp: Timestamp.now(),
    });
    return changes.length;
  });

  return { ok: true, changed };
});
