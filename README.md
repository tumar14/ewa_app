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
