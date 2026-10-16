# Bootstrapping the first platform admin

There is deliberately no UI for this — it's a one-time action, and building a
"create the first super-admin" screen would just be an unauthenticated way to
grant platform-admin access to anyone who finds it. This mirrors the existing
precedent in `firestore.rules` for bootstrapping FTM's very first company
admin (done once via the Firebase console / Admin SDK, then every subsequent
admin is created through the normal flow).

## Steps

1. Sign in to the Firebase CLI as an account with Editor/Owner access to the
   `ewa-app-cb943` project (or set `GOOGLE_APPLICATION_CREDENTIALS` to a
   service account key with equivalent access).
2. Find the Firebase Auth UID of the account that should become the platform
   admin — Firebase Console → Authentication → Users, or:
   ```
   firebase auth:export /tmp/users.json --project ewa-app-cb943
   ```
3. Run this script once, with that UID substituted in. Do **not** commit a
   version of this file with a real UID filled in — copy it out, run it, and
   discard the copy.

   ```js
   // run-once.mjs — delete after running
   import { initializeApp } from "firebase-admin/app";
   import { getAuth } from "firebase-admin/auth";

   initializeApp();

   const uid = "PASTE_THE_UID_HERE";
   await getAuth().setCustomUserClaims(uid, { platformAdmin: true });
   console.log(`platformAdmin claim set for ${uid}`);
   ```

   ```
   node run-once.mjs
   ```

4. Sign that account out and back in (or wait for its next token refresh) so
   the new claim takes effect. It will now land on the `PlatformAdminShell`
   instead of the normal employee flow, and can use "Add company" to create
   FTM (or any other company) as a real company + its first admin.

## Revoking platform-admin access

```js
import { initializeApp } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";

initializeApp();
await getAuth().setCustomUserClaims("PASTE_THE_UID_HERE", { platformAdmin: false });
```
