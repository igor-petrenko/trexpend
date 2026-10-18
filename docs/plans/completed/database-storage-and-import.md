# Database Storage, Initialization, and Replacement Import

## Purpose

Connect the existing shell and financial foundations to an app-owned SQLite file,
with optional import and safe replacement instead of an import-required first run.

## Goal

A clean launch creates a valid initial ledger automatically. Relaunch reopens the
same file. A supported Trexpend import replaces its entire dataset and preferences;
cancellation/failure preserves the prior dataset. All SQLite/file work stays off
the UI thread, with tested restart recovery.

## Scope

Include startup, canonical resources, starter seeds, serialized storage, record
mapping, typed settings, candidate validation, replacement recovery, and Settings
import UI. Exclude transaction editing, full Home/history UI, MMEX conversion in
the app, rate downloads, account management, export, and reset UI. The replacement
engine is reused by the next plan for reset.

Starter content is confirmed in the
[lifecycle specification](../../specs/database-lifecycle.md): all current default
categories/subcategories and currencies, no accounts/history/rates, USD display
currency, and NULL default account/user name. The public seed SQL is authored, reviewed, and bundled.
Implementation authorized by the user on 2026-10-17; implementation and verification are complete with the limitations below.

## Implementation Approach

### Components and physical files

Under apps/ios/Trexpend/Trexpend/, create only files with actual responsibilities:

| Component | Responsibility |
| --- | --- |
| App/AppDependencies.swift | Construct one DatabaseStore, SettingsStore, and file coordinator |
| App/AppSession.swift | Startup status, active generation, revisions, operation availability |
| Data/DatabaseStore.swift | Async facade over one worker queue and working connection |
| Data/SQLiteConnection.swift | Handles, bound statements, checked transactions, cleanup |
| Data/DatabaseValidator.swift | Read-only format/schema/integrity/domain validation |
| Data/DatabaseLifecycle.swift | Staged creation, replacement phases, recovery, cleanup |
| Data/SettingsStore.swift | Typed settings cache persisted through DatabaseStore |
| Files/DatabaseFileCoordinator.swift | System picker access, provider coordination, staging |
| Features/Settings/SettingsState.swift | Import progress, confirmation, errors, cancellation |
| Models/ | Required persisted/read models, using existing finance/date codecs |

Extend TrexpendApp and RootView for asynchronous startup and session injection.
Extend current tab views to distinguish loading, ready-empty, and failure. Do not
show accounts or complete dashboard/history layouts before their separate stage.
Add generation checks to requests and reject old results after replacement.

Keep canonical schema SQL under database/migrations/. Add the public starter seed
at database/seeds/001_defaults.sql, retaining the complete current category
hierarchy and currency catalog. Bundle canonical resources
through explicit Xcode references; verify app bundle contents. Do not maintain a
second hand-edited schema. Only reviewed public reference catalogs may be
extracted into the seed; never include personal accounts, history, rates, settings,
or reports.

Use journal_mode DELETE, synchronous FULL, and foreign_keys ON with an explicit
bounded busy timeout. Validate effective configuration. Upgrade journal policy
later only with measured need and a compatible replacement/recovery plan.

### Initialization and import

Follow [Database lifecycle](../../specs/database-lifecycle.md) for startup and the
replacement state machine. Startup checks recovery artifacts first; corruption
never becomes permission to create over existing data. Publish only a fully
seeded, validated database. Reopening must not reinsert defaults or overwrite
preferences.

Validate imports without executing their schema SQL or enabling extension loading.
Use read-only inspection, resource limits for validation, checked money/date
mapping, settings/reference checks, and SQLite integrity/FK checks. Accept only
supported v1 standalone Trexpend snapshots. Preserve valid imported rows/metadata,
including optional fields unused in UI; do not normalize by reseeding.

Test switching, commit, and cleanup interruption cases with injected filesystem
failures. Preserve evidence and expose recovery errors if rollback cannot finish.
Document concrete durable state-record encoding and filesystem flush/rename calls
before coding that path. SQL rollback cannot undo unrelated file moves.

Import confirmation names the replacement action without printing private source
paths or records. A failed candidate leaves navigation, drafts, settings, and the
old generation valid. Successful replacement clears stale navigation/drafts and
reloads the candidate's own settings. Prevent conflicting operations while switching.

### Concrete Replacement Protocol

Use ledger.sqlite, candidate.sqlite, previous.sqlite, and replacement.json within
one app-owned directory. The JSON record contains only format version 1 and phase
switching/committed/rolledBack. Recovery keeps previous intact until rolledBack
is durable, allowing another interruption during rollback itself. Write to replacement.tmp, fsync, rename, and fsync the directory.
Flush candidate data and directory renames before advancing the phase. Keep the
old file until committed is durable. Switching recovery always restores previous
when present; otherwise it keeps the old ledger only if candidate still exists
(the old-file move never happened). Committed recovery validates ledger and cleans
previous. Missing/contradictory artifacts fail closed. Initial creation uses its own
staged file and atomic publication without replacing an existing ledger.

The tests inject failures at marker write, old move, candidate move, new reopen,
commit marker, and cleanup boundaries. fsync/rename provide the filesystem protocol;
physical power-loss behavior is not claimed from Simulator interruption tests.

## Database Changes

No schema upgrade or change to existing converted v1 files is planned.

For a new staged file, execute the exact canonical SQL in
[001_initial.sql](../../../database/migrations/001_initial.sql), then the reviewed
[001_defaults.sql](../../../database/seeds/001_defaults.sql) in one initialization transaction, validate, close, and publish.
The seed must supply the full currency/category catalogs and exactly one
app_settings row (USD, NULL default account, NULL user name). It must insert no
accounts, transactions, or exchange rates. Resolve USD by code. Add exact seed SQL
to this plan or link its canonical file before implementation. Existing ledgers and
imports are never seeded. No rollback SQL is needed: discard a failed staged
initialization; replacement rollback restores the previous file.

## Tasks

- [x] Confirm starter content and the accepted lack of account-creation UI.
- [x] Author/review exact public seed SQL and verify catalog relationships and USD settings.
- [x] Specify durable replacement-state records and recovery behavior for each file-move boundary.
- [x] Bundle canonical schema/seeds and verify resource target membership.
- [x] Implement serialized SQLite handles, statements, transactions, and error mapping.
- [x] Implement staged initialization and reopen without reseeding.
- [x] Implement format/schema/domain validation with synthetic valid/invalid fixtures.
- [x] Implement replacement and interruption recovery shared by future reset.
- [x] Implement typed settings loading and dataset-generation checks.
- [x] Wire asynchronous startup and loading/empty/error states into the shell.
- [x] Add Settings import, provider access cleanup, replacement confirmation, and progress.
- [x] Verify storage behavior.
  - [x] Run synthetic creation, reopen, FK/domain, and invalid-import tests.
  - [x] Verify fresh/reset catalogs include the complete defaults, with zero accounts/history/rates and USD/NULL settings.
  - [x] Verify changed bundled defaults do not reseed existing or imported datasets.
  - [x] Inject failures/restarts before and after each replacement commit boundary.
  - [x] Verify original input preservation and exact imported record/settings round trips.
  - [x] Verify stale requests cannot save or publish into the replacement dataset.
  - [x] Build and run on iOS 27; test local Files import, cancellation, retry, and relaunch.
  - [x] Check no personal files/resources, private logs, new dependencies, or schema drift.
- [x] Update current-status documentation and record actual verification.

## Verification Results

- iOS 27 Simulator build succeeded with the original deployment target.
- The final full run passed 44 test functions with no failures or skipped tests.
  Synthetic fixtures cover creation, reopen, exact text/settings preservation,
  malformed imports, category cycles, precision, source preservation, stale
  generations, validation timeouts, and unavailable coordinated files.
- Import and reset interruption tests cover all six replacement boundaries;
  ordinary failures restore immediately and restart recovery is repeatable.
- Local Files import, replacement confirmation, relaunch, and default creation
  were exercised on Simulator. Retry after failure is covered by storage tests;
  third-party provider download failures were not reproduced interactively.
- Both bundled SQL files match their canonical repository files byte-for-byte.
  Fresh/reset data has 168 currencies, 64 categories, no accounts/history/rates,
  and USD/NULL settings. Existing/imported catalogs are not reseeded.
- The native validator opened the converted private dataset read-only. No
  personal database, record, report, or account metadata is bundled or tracked.
- Signed-in iCloud Drive, physical iPhone behavior, and physical power loss have
  not been verified. Fault injection verifies recovery logic, not hardware durability.
