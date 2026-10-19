# Starts the local Firebase emulators (under the app's own project id, so Android
# talks to them; nothing is sent to the real project) (Auth, Firestore, Functions) for testing
# without the Blaze plan. Data is saved to emulator-data/ on exit and reloaded on
# the next start, so the demo seed only has to be run once. BlueStacks reaches the
# emulators at 10.0.2.2 on its own: no tunnel is needed.
#
#   .\scripts\demo-backend.ps1                 start the emulators (leave this window open)
#
# Demo data: if emulator-data/ does not exist yet, seed once in a second window after
# the emulators say "All emulators ready":
#   cd functions; npm run build; node scripts\seed-demo.mjs --target emulator
# (re-run it any time to reset the demo data; times in it are relative to "now").
# Logins are written to C:\Users\<you>\secrets\hola-manje-demo-emulator.txt
#
# Then run the app against the emulators (not the live project):
#   flutter run -d chrome --dart-define=USE_EMULATORS=true
#   flutter build apk --debug --dart-define=USE_EMULATORS=true   # for BlueStacks

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

# The Firestore emulator needs Java 21 or newer.
$java = Get-ChildItem "C:\Program Files\Eclipse Adoptium" -Directory -ErrorAction SilentlyContinue |
  Where-Object { $_.Name -match "^(jre|jdk)-(2[1-9]|[3-9]\d)" } | Select-Object -First 1
if (-not $java) { throw "Java 21+ not found. Install it with: winget install --id EclipseAdoptium.Temurin.21.JRE -e" }
$env:PATH = "$($java.FullName)\bin;$env:PATH"
# Stops Google auth libraries waiting on a metadata server that does not answer on this network.
$env:METADATA_SERVER_DETECTION = "none"

$args = @("emulators:start", "--only", "auth,firestore,functions", "--project", "ewa-app-cb943", "--export-on-exit", "emulator-data")
if (Test-Path "emulator-data") { $args += @("--import", "emulator-data") }
firebase @args
