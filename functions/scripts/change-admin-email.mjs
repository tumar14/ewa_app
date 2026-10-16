/**
 * One-time maintenance script for the existing HR Manager account.
 *
 * Run only from a trusted computer after setting GOOGLE_APPLICATION_CREDENTIALS
 * and NEW_ADMIN_PASSWORD. Delete this file when the change is complete.
 */
import { initializeApp } from "firebase-admin/app";
import { FieldPath, getFirestore } from "firebase-admin/firestore";
import { getAuth } from "firebase-admin/auth";

const uid = "63xuQucCSWTnytlOoDrg2WADfyE2";
const newEmail = "10897boniswak@gmail.com";
const newPassword = process.env.NEW_ADMIN_PASSWORD;

if (!newPassword || newPassword.length < 6) {
  throw new Error("Set NEW_ADMIN_PASSWORD to a new password of at least 6 characters before running this script.");
}

initializeApp();

// The UID is retained, which preserves custom claims and the employee/admin role.
await getAuth().updateUser(uid, {
  email: newEmail,
  emailVerified: false,
  password: newPassword,
});

// Keep the mirrored email stored in the employee document in sync.
const db = getFirestore();
const employeeDocs = await db
  .collectionGroup("employees")
  .where(FieldPath.documentId(), "==", uid)
  .get();

if (employeeDocs.empty) {
  console.warn("Authentication was updated, but no employee document was found for this UID. Update its email in Firestore manually.");
} else {
  const batch = db.batch();
  for (const doc of employeeDocs.docs) {
    batch.update(doc.ref, { email: newEmail });
  }
  await batch.commit();
  console.log(`Updated ${employeeDocs.size} employee document(s).`);
}

console.log(`Admin login changed to ${newEmail}. Sign in with the new password.`);
