# Hola Manje

**Your money. Your time.** Access your earned wages before payday.

Hola Manje is an earned wage access platform for employers and employees in Eswatini.
It is a Flutter app (Android, iOS, web) on Firebase: Authentication, Firestore, Cloud Functions.

Internal names (the Dart package `ewa_app`, the Firebase project `ewa-app-cb943`, Android/iOS
bundle IDs, Firestore collections) predate the brand and are deliberately unchanged.

## Layout

| Path | What it is |
|---|---|
| `lib/` | The app: worker, employer admin and platform admin experiences |
| `functions/` | Cloud Functions: draws, payroll, settlements, company creation, public enquiries |
| `site/` | The public website (static HTML/CSS/JS, no external dependencies) |
| `scripts/build-hosting.mjs` | Builds the website and the app into one Firebase Hosting folder |
| `firestore.rules`, `storage.rules` | Security rules |

## Common tasks

```bash
flutter analyze && flutter test                      # app checks
cd functions && npm run build && node --test lib/    # function checks
node scripts/build-hosting.mjs                       # assemble hosting/ (website at /, app at /app/)
```

Emulator testing: start the Firebase emulators, then run the app with
`--dart-define=USE_EMULATORS=true`. Never deploy a build made with that flag.

## Testing without the Blaze plan (demo data)

The Cloud Functions need Blaze, so on the live project you cannot request, approve or
pay advances, run payroll, or create companies. The local emulators run the same functions
for free, so test there with demo data.

1. Start the emulators and leave the window open:
   `.\scripts\demo-backend.ps1`
   (needs Java 21; on the first run it prints a `winget` command if it is missing).
2. First time only, if `emulator-data/` does not exist, seed in a second window:
   `cd functions; npm run build; node scripts\seed-demo.mjs --target emulator`
   Re-run the same command any time to reset the demo data (times in it are relative to now).
3. Run the app against the emulators. Never use these builds for real people:
   - BlueStacks / Android: `flutter build apk --debug --dart-define=USE_EMULATORS=true`, then install it.
   - Browser: `flutter run -d chrome --dart-define=USE_EMULATORS=true`
   Rebuild **without** the flag to go back to the live project.
4. Sign in with the accounts in `C:\Users\<you>\secrets\hola-manje-demo-emulator.txt`
   (random passwords, owner-only file, never printed). It also lists one-time codes for
   the "Claim your account" flow.

The seed creates two test companies ("Demo Garments (TEST)", "Sample Textiles (TEST)") with
an admin, a supervisor and workers, this cycle's time records (one person clocked in),
advances in every state, a previous payroll run with a settlement that has an open
exception, unclaimed seats, website enquiries, and a demo platform admin (emulator only).
`node scripts\verify-seed.mjs` checks it all against the real functions and rules.

The same script can fill the live project (`--target live --yes`, test data tagged and
removable with `--remove`), but without Blaze you could only look at the data there.

## Service fees and automatic approval

Management sets both in **Admin Settings** (stored in the company's `settings/app` document):

- **Service fee**: a percentage, or a *tariff table* of amount bands (like a mobile-money tariff). Each
  band has an upper limit, a flat fee and an optional percentage on top. A table without an open top
  band also caps the size of one advance. The server works out the fee when the advance is requested
  and stores it on the advance, so it never changes afterwards.
- **Automatic approval**: off by default. When on, a request that passes every limit (earned-wages cap,
  advances per cycle, fee table) is approved by the server without a person, optionally only up to a
  ceiling. Paying out is still done by finance, and every automatic approval is written to the audit log.
  Anything unclear (a bad ceiling, a flag that is not exactly `true`) means a person decides.
- The rules live in `functions/src/feeSchedule.ts`; the app's preview in `lib/models/fee_schedule.dart`
  mirrors it and both are tested with the same cases. Demo data: Demo Garments uses 5% with manual
  approval; Sample Textiles uses a tariff table with automatic approval up to E100.
- Settings are written by the admin app directly, so the server re-validates the fee schedule on
  every request and refuses to charge anything if it is invalid.


## Website industry list

The Industry dropdown on the website's "Register your company" page is set by the platform admin in the
app: **Platform Admin > Platform settings**. The list is stored in `platform_config/website`, which the
static site reads directly from Firestore (public read; only the platform admin can write it, see
`firestore.rules`). `submitEnquiry` accepts only an industry from the saved list, or "Other".

- Until a list is saved, the standard list in `functions/src/industries.ts` is used. The website build
  (`scripts/build-hosting.mjs`) embeds it as the fallback, so run `cd functions && npm run build` first.
  `lib/models/platform_config.dart` mirrors it and a test keeps the two identical.
- After changing the rules, deploy them (`firebase deploy --only firestore:rules`) or the site cannot read the list.

## Platform admin overview

**Platform Admin > Overview** (the chart icon) shows counts for every company: active employees and workers,
advances this pay cycle, requests waiting for approval or payout, and what the company still owes in open
settlements. It is built by the `platformOverview` Cloud Function (platform admin only) from Firestore count
queries, and returns numbers plus the company's public details, never an employee's name or an individual
amount. The platform admin still cannot read employees, advances or settlements directly (`firestore.rules`).
Check it with `GCLOUD_PROJECT=ewa-app-cb943 node scripts/verify-overview.mjs` while the emulators run.
It needs Cloud Functions deployed (Blaze).

## Attendance, manual hours and settings reset

- **Where hours come from:** workers clock in and out in the app (the server stamps the time), a kiosk run by an
  admin, an uploaded file (More > Upload attendance), or an admin adding or correcting a record
  (Workforce > a person > + / the menu on a record).
- **Management controls** (Admin Settings > Attendance & hours): allow or forbid manual changes, allow or forbid
  uploads, require supervisor sign-off before time counts towards advances, and the longest single record
  (default 14 hours). `firestore.rules` read these settings, so switching them off stops the writes themselves.
- **Every manual change** needs a reason, is marked on the record (`source: adminEdit | externalImport`), and
  adds an entry to the append-only `time_edits` collection (who, server time, why, times before and after).
  Records are never deleted: a wrong one is voided.
- **What the server counts** (`functions/src/hours.ts`, `drawRules.countableMs`): voided and (if required)
  unsigned records are ignored, time that has not happened yet is ignored, one record is capped, and overlapping
  records are merged so the same hour is never paid twice. The app mirrors this in `lib/utils/attendance_rules.dart`.
- **Reset / restore:** Admin Settings has "Reset to defaults" and "Restore previous". Saving keeps the
  replaced values at `settings/previous`, so a reset can be undone. Neither applies until Save is pressed.
- **Deploying:** these rules need `firebase deploy --only firestore:rules`, and the accrual change needs the
  functions deployed (Blaze). Until the new rules are live, the previous, looser rules still apply.
- **Checks:** `GCLOUD_PROJECT=ewa-app-cb943 node scripts/verify-attendance.mjs` with the emulators running.
