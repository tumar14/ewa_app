import { Timestamp } from "firebase-admin/firestore";
import { onDocumentWritten } from "firebase-functions/v2/firestore";
import { db, notifyEmployee } from "./common";
import { changedEmployeeFields } from "./employeeChanges";

/**
 * Employee records are edited from the admin app, so every change is recorded here. The
 * rules make the app stamp who made each edit (lastEditedBy) with the server's time, so the
 * audit entry names a real person. A change to payout details also starts the holding period
 * before that employee can be paid (payoutChangedAt, which clients cannot set) and tells the
 * employee, so a quiet swap of someone's bank or mobile-money number does not go unnoticed.
 */
export const onEmployeeWritten = onDocumentWritten("companies/{companyId}/employees/{employeeId}", async (event) => {
  const after = event.data?.after.data();
  if (!after) return;
  const before = event.data?.before.data();
  const { companyId, employeeId } = event.params;
  const companyRef = db.collection("companies").doc(companyId);
  const by = (after.lastEditedBy as string | undefined) ?? null;

  if (!before) {
    if (by) {
      await companyRef.collection("audit_log").add({
        type: "employee_added",
        employeeId,
        name: after.name ?? "",
        role: after.role ?? "worker",
        hourlyRate: after.hourlyRate ?? null,
        addedBy: by,
        timestamp: Timestamp.now(),
      });
    }
    return;
  }

  const { changes, payoutChanged } = changedEmployeeFields(before, after);
  if (changes.length === 0 && !payoutChanged) return;

  if (payoutChanged) {
    await event.data!.after.ref.update({ payoutChangedAt: Timestamp.now() });
    await notifyEmployee(
      companyId,
      employeeId,
      "Your payout details changed",
      "Your payment details were changed by your employer. If you did not expect this, tell HR straight away. Payments to you are on hold for a short time while this is checked.",
    );
  }
  await companyRef.collection("audit_log").add({
    type: "employee_changed",
    employeeId,
    changes: [...changes, ...(payoutChanged ? [{ field: "payout details", from: "(hidden)", to: "(hidden)" }] : [])],
    changedBy: by,
    timestamp: Timestamp.now(),
  });
});
