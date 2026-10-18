# Database Export, Restore, and Reset

## Purpose

Provide a user-controlled portable backup and a confirmed return to initial
state before enabling financial record editing.

## Goal

Settings can save a consistent standalone database snapshot, restore it through
the existing replacement importer, and reset the ledger to the first-launch seed
only after explicit destructive confirmation. Cancellation and failure preserve
the working dataset, with tested replacement recovery.

## Scope

Depends on [storage and import](database-storage-and-import.md). Include SQLite
backup, system export, restoration verification, reset candidate creation, and
Settings actions/progress. Exclude automatic backups, live iCloud synchronization,
MMEX compatibility, permanent undo history, and financial editor features.

Implementation authorized by the user on 2026-10-17, following storage tests.

## Implementation Approach

Extend DatabaseStore/DatabaseLifecycle and DatabaseFileCoordinator from the
storage stage; do not create another SQLite owner. Extend SettingsState and
SettingsView with Save Database Copy and Reset Database near Import Database.
Keep UIKit/SwiftUI file presentation on MainActor and backup/validation on the
serialized worker. Follow the [lifecycle specification](../../specs/database-lifecycle.md).

### Snapshot and restore

Use sqlite3_backup to a fresh temporary destination after preceding writes.
Check init/step/finish statuses, bounded lock retries, cancellation, cleanup, and
independent reopen. Never copy only the live main file. The snapshot includes
app_settings and excludes device UserDefaults. Its contents reflect the selected
snapshot moment even if the working ledger changes after snapshot creation.

Present the closed standalone .sqlite file through the system exporter with a
safe timestamped Trexpend filename. Retain it until the exporter finishes. Report
success only after completion; cleanup must not remove a file still being used by
the provider. A cancelled exporter leaves the working ledger unchanged.

Restore uses the same importer and confirmation as another Trexpend snapshot.
Verify exported/imported data and preferences match without app-side reseeding.
Test Files locally and iCloud Drive when a signed-in device/provider is available;
record unavailable provider verification without claiming cloud success.

### Reset

Always ask for confirmation identifying that current accounts, history,
categories, rates, and dataset settings will be replaced by initial defaults.
Cancel must perform no destructive write. Do not force export or introduce a
second confirmation dialog. Disable duplicate/conflicting dataset operations.

After confirmation, create a new staged database using the same canonical SQL
and confirmed full-catalog starter seed as first launch (no accounts/history,
USD display currency, NULL default account/user name). Validate and pass it through the shared
replacement engine, retaining the old file until commit. Never reset through
piecemeal DELETE operations. Reload default settings, advance generation, clear
stale navigation/editors, and render the initial empty-history state on success.
Preserve device-only preferences and user-exported backups.

Keep reset failure distinct from success followed by cleanup failure. An internal
recovery copy is temporary safety state, not a promised retained backup. Exercise
restart recovery for reset as well as import. Do not silently reset unreadable
working data; any recovery-screen reset still requires the same explicit user
confirmation and safe replacement rules.

## Database Changes

None to the schema or imported data representation. Export uses the SQLite backup
API without DDL. Reset creates a new file with the canonical initial schema and
starter seed finalized by the storage plan; it replaces the working file only
after validation. Before commit, recovery restores the previous file. After a
successful reset, restore from an independently exported snapshot if needed;
there is no safe general rollback SQL or permanent reset undo.

## Tasks

- [x] Implement consistent snapshot creation, validation, retries, and cleanup.
- [x] Add system export presentation, filename suggestion, and correct completion handling.
- [x] Add Reset Database with explicit destructive confirmation and Cancel.
- [x] Create reset candidates using the same initialization path as first launch.
- [x] Reuse replacement recovery, generation invalidation, and settings reload.
- [x] Verify export, restoration, and reset.
  - [x] Export synthetic populated data and reopen the snapshot independently.
  - [x] Restore that snapshot and compare exact records and dataset settings.
  - [x] Test cancellation completion, unavailable-source errors, locked-backup failure/retry, and temporary-file cleanup; record provider limitations.
  - [x] Cancel reset and confirm data/settings remain unchanged.
  - [x] Confirm reset and compare results with a fresh installation's full seed.
  - [x] Verify reset removes dataset category edits and restores USD/NULL settings without creating accounts.
  - [x] Inject reset replacement failures/restarts and verify recovery.
  - [x] Verify old requests/drafts cannot repopulate the reset dataset.
  - [x] Verify device preferences and existing exported files survive reset.
  - [x] Build and test Settings/Files workflows on iOS 27 Simulator or device.
  - [x] Verify iCloud Drive on an available signed-in device, or document the limitation.
- [x] Update specifications/status and record verification before enabling financial editing.

## Verification Results

- The final iOS 27 Simulator run passed all 44 test functions without compiler
  warnings, failures, or skipped tests. The app builds and launches.
- Synthetic snapshots reopen independently and restore exact records/settings;
  reset returns the full default catalog and does not alter saved exports.
- Locked-backup failure leaves the ledger usable, cleans its partial snapshot,
  and permits a successful retry. An unavailable coordinated source preserves
  the current generation. Both export delegate/dismissal event orders are tested.
- Local Files export completed on Simulator and its saved SQLite snapshot was
  independently inspected. Import of synthetic data, cancelled/confirmed reset,
  and relaunch were exercised. Reset never accesses device UserDefaults.
- An experimental SwiftUI Transferable export crashed inside
  NSFileWrapper.setPreferredFilename. That path was removed. The final native
  UIDocumentPickerViewController exporter completed without terminating the app.
- Actual iCloud/provider write failures and export cancellation through the
  provider UI remain unverified; cancellation state/cleanup is tested directly.
  A signed-in physical device was unavailable, so iCloud success is not claimed.
- These platform limits do not enable financial editing; that remains separate
  work after the read-only Home/settings and history stages.
