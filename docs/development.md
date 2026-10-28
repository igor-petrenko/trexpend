# Development and Offline Conversion

## Current Status

The iPhone project is apps/ios/Trexpend/Trexpend.xcodeproj. It has Home/All/Settings navigation
and asynchronous SQLite startup. Shared financial/date foundations, initialization,
replacement import, snapshot export, reset, read-only Home, display-currency
selection, and focused tests are implemented. The
desktop MMEX converter and canonical Trexpend schema resources are implemented separately.

## Converter Requirements

- Python 3.11 or newer, standard library only, with SQLite and America/Toronto
  timezone data available. No pip packages are required on the tested macOS host.
- A standalone SQLite MMEX export with user_version 20 and the supported source
  columns described in the [mapping](specs/mmex-conversion.md).
- Existing output directories; choose unused destination names. A source with
  -wal, -shm, or -journal companions is refused. Export/close MMEX first.

## Run the Converter

From the repository root:

```sh
python3 -B tools/convert_mmex.py \
  --source local/init_export_db.mmb \
  --output local/new-ledger.sqlite \
  --report local/new-ledger.report.json
```

The report is optional. It contains private ID maps, balances, and account/month
totals: keep it in ignored local/ or outside version control. Console output is
limited to generic results and counts. All source and target text, including
non-English imported user data, is preserved rather than translated.

The command does not overwrite existing files. For another conversion choose new
output/report names. It produces an independent dataset and never merges existing
Trexpend edits. Rate downloads do not run. The destination is published only after
validation and independent reopening. Keep the original export for recovery.

Unsupported populated features/statuses or amounts requiring currency rounding
cause a clear failure, not silent data loss. Compatibility is deliberately bounded;
different future MMEX structures may require converter changes.

## Verification

```sh
python3 -B -m unittest discover -s tools/tests -v
```

Synthetic tests cover mapping, financial totals, text preservation, zero/unequal
transfer amounts, eight-digit currency precision, Toronto offsets/DST, FK checks,
invalid source data, no-overwrite behavior, and staging/publication failures.

The private trial output is local/trexpend.sqlite, with report
local/trexpend.report.json. Neither belongs in Git or the iPhone target. A successful
conversion and standalone reopen do not imply iPhone import/runtime verification.

## Schema Ownership

Use [001_initial.sql](../database/migrations/001_initial.sql) as the single schema
definition. See [schema contract](specs/database-schema.md) for constraints and limits.
The future iPhone storage implementation must add the canonical SQL as a resource
and validate/migrate supported Trexpend snapshots; it must not embed MMEX SQL.

## Build and Test the iPhone Foundations

Open apps/ios/Trexpend/Trexpend.xcodeproj and select the shared Trexpend scheme.
Use the installed iOS 27 SDK and an iOS 27 Simulator. Cmd+R runs the shell;
Cmd+U runs the TrexpendTests Swift Testing target. A clean launch creates the
public seeded ledger (USD, no accounts/history). Settings provides Import Database,
Save Database Copy, and confirmation-gated Reset Database. Full account/history
screens and financial editing remain later stages.

From the repository root, with the desired Simulator already booted:

```sh
xcodebuild -project apps/ios/Trexpend/Trexpend.xcodeproj \
  -scheme Trexpend -destination 'platform=iOS Simulator,name=iPhone 18 Pro' \
  -derivedDataPath local/DerivedData test
```

The 2026-10-17 final Simulator run passed all 22 financial/date tests. Tab switching,
stop/relaunch, fixed light appearance, and maximum accessibility text size were
verified. Preview declarations compile, but a separate interactive Canvas session
was not run. Pure foundations explicitly use nonisolated types because the app's
existing default isolation is MainActor. No app build setting was lowered.

Test fixtures are synthetic. This initial financial-foundation verification predates the storage work described
below. Actual ledger editing remains a subsequent stage.

## SQL Resources in Xcode

The application target explicitly references these repository files:

- database/migrations/001_initial.sql: canonical schema and built-in references.
- database/seeds/001_defaults.sql: public currency/category catalogs and USD settings.

Their PBXFileReference paths are relative to SOURCE_ROOT (the Xcode project's
apps/ios/Trexpend directory): ../../../database/migrations/001_initial.sql and
../../../database/seeds/001_defaults.sql. The files are not duplicated in the iOS
source directory. Copy Bundle Resources places both SQL files in Trexpend.app;
DatabaseResources reads them from Bundle.main on the database worker queue.
The built copies were compared byte-for-byte with the canonical sources.

To inspect this in Xcode, select the project, select target Trexpend, and open
Build Phases > Copy Bundle Resources. Both SQL files are already listed. For a
future SQL resource, use Add Files to Trexpend, retain the file in its original
repository location rather than copying it into the app folder, add it to the
Trexpend target, and verify its entry in Copy Bundle Resources. Rebuild after
changing a bundled script; an installed release cannot read the computer's repo.

Creation/reset execute schema then defaults only against a fresh staged file.
Imports and ordinary launches never rerun seeds. Working data is stored separately
at Library/Application Support/Trexpend/ledger.sqlite and is not bundled in Git.

## Storage Verification (2026-10-17)

The final iOS 27 Simulator run passed 44 test functions (zero failures/skips).
Coverage includes invalid imports, exact record/settings preservation, six import
and reset interruption boundaries, snapshot restore, lock failure/retry, source
access failure, stale generations, and export completion ordering. Fixtures are
synthetic. The native app was exercised for creation, local Files import/export,
confirmed/cancelled reset, and relaunch. This historical checkpoint predates Home;
see the Home verification below for current screen coverage.

Export uses a UIKit document picker for an already closed SQLite backup snapshot.
The experimental SwiftUI Transferable route was removed after a Simulator crash
in NSFileWrapper.setPreferredFilename. Signed-in iCloud, actual provider write
failures, provider-UI export cancellation, and physical-device testing remain
unverified; automated tests cover cancellation state and snapshot cleanup.

## Reliability Follow-up

Working-database startup now reads schema/settings/counts without a history audit.
Full validation remains at import and snapshot verification and reports timeout
separately. Settings and startup recovery actions work without an open ledger.
Recovery preserves unreadable source artifacts before replacement. Valuation
arithmetic permits finite intermediate precision loss, while stored/native money
arithmetic remains strict. See the reliability plan for current verification.

Automatic backups use Documents/Backups, visible in Files under On My iPhone /
Trexpend. The two standard file-sharing Info.plist keys are enabled in both target
configurations; the working ledger stays under Application Support. Backups run
on first successful opening of each local day. Retention is 30 days, applied only
after a usable current-day backup exists. Deleting the app also deletes local
backups; manual export to iCloud or another independent location remains useful.

The target merges apps/ios/Trexpend/Info.plist with Xcode-generated application
metadata. This source explicitly declares both Files-sharing Boolean keys; tests
assert their presence in Bundle.main, rather than relying only on build settings.

Reliability verification on 2026-10-18 passed all 58 app test functions and 21
converter tests. Startup recovery alert layout and a healthy restored launch were
captured on Simulator. Daily backups were reopened independently. Full UI routing
through the recovery picker and Files navigation was not automated in this run;
physical-device/iCloud verification remains pending. The completed reliability
plan contains the test scope and benchmark limits.

## Home Verification (2026-10-18)

The iOS 27 Simulator test suite passed 65 test functions with zero failures. Home
fixtures cover all account types, closed-account monthly activity, native opening
balances, transfer principal/fees, month boundaries, inactive/transfer-only rows,
missing rates, display-currency persistence, replacement generations, and exact
large-number formatting. UI state tests cover reload after currency change/reset.

Simulator screenshots were inspected for a populated synthetic ledger, missing
rates, an empty ledger, long account names, and maximum accessibility text size.
Bottom scroll clearance and the Settings currency picker were exercised, including
USD search, selection, and visible Home recalculation with unchanged native rows.
The Simulator required additional startup/rendering time before captures; early
blank transition frames were not accepted as UI verification. Synthetic fixture
work restored the original simulator ledger afterward. Physical-iPhone layout
and performance remain unverified. Home reads are local and do not download rates.

## Account History and Schema v2

A tap on a Home account opens read-only history with complete native balance/month
summaries and descending date/time pages. The approximate display-currency amount
is shown only for the balance. All history and the editor remain subsequent work.

Fresh/reset ledgers and the offline converter now produce v2. App startup upgrades
existing v1 working data through a staged SQLite backup; import upgrades only its
staged copy. No manual reconversion is needed. Retain the original v1 file for older
app builds. Exported v2 and existing v1 backups are both restorable by the new app.
The shared icon defaults JSON and v2 SQL are target resources alongside v1 SQL;
changing a bundled resource requires rebuilding/installing the application.

Verification on 2026-10-25 passed the full 73-function iOS Simulator suite, a
subsequent focused 8-function history suite, and 22 converter tests. Existing
ledger financial fields were compared before/after v2 migration. Home/account/Back
navigation and older-page scrolling passed. Final maximum-Dynamic-Type and manual
refresh/page-retry visual checks remain in the active account-history plan after
Simulator launch/rendering failures. A host query benchmark is recorded there; it
is not an iPhone performance measurement.

The compact summary/history-row refinement passed a fresh build and all 8 focused
history tests on 2026-10-25. Home/account cards, conditional difference columns,
toolbar favorite states, and primary/secondary transaction alignment were visually
inspected on the existing Simulator without rebooting it. See the
[completed refinement plan](plans/completed/compact-summary-and-history-rows.md)
for scope and remaining visual-test limits.
