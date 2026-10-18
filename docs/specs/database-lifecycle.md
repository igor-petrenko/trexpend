# Working Database Lifecycle

## Status

First-launch creation, replacement import, snapshot export, and confirmation-gated
reset are implemented and tested on iOS 27 Simulator. Financial record editing is
not yet implemented. Signed-in iCloud Drive and physical-device testing remain open.
This supersedes the earlier import-required first-launch proposal.

## Initial and Reset Dataset

On a clean first launch, automatically create a fresh Trexpend database in
Library/Application Support/Trexpend/. Import is optional. "Empty" means no user
history; the schema, built-in references, currency catalog, and app_settings must
still exist. Do not bundle a personal converted database as a template.

Use the existing canonical database/migrations/001_initial.sql for tables,
constraints, indexes, and built-in account images/types/statuses/transaction types.
A separate public SQL seed at database/seeds/001_defaults.sql supplies the full
currency and category catalogs and the initial settings row. It inserts no
accounts, transactions, or exchange rates. Initial creation and reset run the
same schema and seed; neither reads the user's current ledger to construct defaults.

The seed is the version-controlled definition of defaults for an app release.
Initially retain the current catalog of 64 categories, including parent/child
relationships, and all 168 currencies. Review the taxonomy later by editing the
seed deliberately; do not replace it with a minimal General/Transfer catalog.
A read-only inventory confirmed those counts in the converted dataset. This is
not permission to copy personal records, account data, or private metadata into
the public repository. Review reference labels before authoring public English/
ASCII seed text; imported snapshots retain their original text unchanged.

| Data | Confirmed initial value |
| --- | --- |
| Currencies | Full current currency catalog, including precision and reference metadata |
| Categories | Full current default category/subcategory hierarchy |
| Other references | Built-in images, account types/statuses, and transaction types from canonical SQL |
| Accounts | None |
| Transactions | None |
| Exchange rates | None; do not invent parity rates or download rates |
| app_settings | USD display currency; default_account_id NULL; user_name NULL |

Default USD is resolved from the seeded currency code, not assumed to have a
particular ID. Keep the complete seed atomic and check for the USD row before
publishing a fresh database. Initial catalog IDs only establish that new file's
relationships; do not use category IDs or currency IDs as global constants across
imported datasets.

Account/category management UI remains deferred. Until account creation exists,
a clean initial ledger cannot accept transactions; use imported data for daily
work. This is an accepted intermediate limitation, not a reason to create a
sample account. Offer no ordinary Create Transaction action without an eligible
account; later account management will make non-imported ledgers usable.

User edits to categories in a working ledger do not modify bundled defaults.
Future changes to shipped defaults affect new creation/reset only unless a
separate migration explicitly updates existing ledgers. Reset recreates the
release's default catalog, discarding dataset-specific category modifications.

Never append starter categories, currencies, or settings to an imported backup.
Its catalogs and preferences remain intact, including its chosen display currency.
Missing conversion rates are reported as unavailable; same-currency calculation
needs no saved rate. Existing converted CAD preferences are not rewritten to USD.

## Startup

1. Resolve the app-owned storage directory on the worker queue.
2. Recover an interrupted replacement, if any, before interpreting a missing file.
3. If the working file exists, check its format/schema/references and open it;
   read its own app_settings and counts without scanning transaction history.
4. If no file or pending recovery exists, create, seed, validate, and publish a
   fresh staged database. Subsequent launches reopen it without reseeding.
5. Publish a ready session and typed settings only after success.

Distinguish startup loading, ready-with-empty-history, and failed-open states.
An unreadable, incompatible, or corrupt existing file must not trigger automatic
creation over it. Preserve the file, show a recoverable error, and allow retry.
Creation failure leaves no partially initialized file at the working path.

An empty ledger is valid. Do not show "No database loaded" after successful
creation. Full Home/history content remains its own stage; the storage checkpoint
may show a concise database-ready state without inventing balances or records.

## SQLite Ownership and Initial Journal Choice

One DatabaseStore owns the working connection and synchronous SQLite calls on one
serial worker queue, with an async interface to feature state. MainActor owns UI
state. Bound parameters, statement finalization, checked errors, foreign_keys ON,
and bounded busy waits apply to all relevant handles.

Implemented working policy: journal_mode DELETE and synchronous FULL. This
fits the initial serialized workload and avoids introducing WAL sidecar switching.
Do not disable journaling or choose OFF/MEMORY for speed. Verify the effective
pragmas after opening. A hot rollback journal must be recovered through SQLite;
never delete it merely because it is beside a database file. Treat runtime policy
as a connection configuration, not a new schema version.

The app does not support externally editing its active working file. Export makes
an independent SQLite snapshot; it does not expose a live iCloud database.

## Replacement Engine

Import and reset prepare a candidate and share one replacement mechanism. Keep
staging, the working file, recovery copy, and replacement-state record on the same
local volume. Serialize connection close, moves, reopening, and session publication.
Use fixed app-controlled paths and a narrow state record, not paths supplied by an
imported database. Keep SQL/file errors free of private records and user filenames.

Implemented recoverable sequence for an existing working dataset:

1. Finish in-flight operations, prevent new writes, and validate a standalone
   candidate completely. Keep the current dataset intact until this succeeds.
2. Finalize statements and close handles. Persist a durable switching record.
3. Move the current file to a recovery path, then move the candidate to the working
   path. Do not remove unexplained journal companions to make moves succeed.
4. Open and validate the new working file and read its settings.
5. Persist the committed replacement state before reporting success. Then advance
   dataset generation, invalidate old requests/editors, reset navigation, and
   publish the new settings/session. Do not carry old dataset IDs into the new one.
6. Remove the obsolete recovery/staging files and state record after commit.

Before a durable commit, failure restores the previous file and settings. On next
launch, a switching record rolls back from the recovery file; if moving the old
file never occurred, reopen the untouched working file. A committed record keeps
and validates the new file and finishes cleanup. Contradictory/missing recovery
artifacts produce an error, not a guessed empty ledger. If rollback itself fails,
preserve the artifacts for retry/recovery and report the limitation.

The implementation uses fsync, same-volume rename, and a versioned JSON record
with switching/committed/rolledBack phases. Recovery preserves previous.sqlite
until rollback is durable. Synthetic tests exercise all six replacement boundaries. A SQL transaction alone does
not make a multi-file replacement atomic. Initial publication into an absent
working path is separate from replacing an existing file.

## Import

Settings offers Import Database. Select a supported standalone Trexpend .sqlite
snapshot through the system picker; coordinate provider access and downloads,
stage locally, and release access on success, cancellation, and failure. Preserve
the selected source file. Replacing the existing dataset requires confirmation.

Accept exported standalone snapshots, not live databases with uncheckpointed
journal state. Reject visible journal companions and unsupported active-source
conditions; copying a main file cannot recover unselected WAL contents. The
supported input contract is a standalone Trexpend snapshot, not any arbitrary
SQLite file a user can select.

Validate format marker, user_version, schema shape, required reference semantics,
integrity, foreign keys, and domain rules. Include currency precision, exact money,
valid calendar/offset/technical timestamps, category cycles, settings cardinality,
and transfer/fee combinations. Preserve valid data outside the current UI.
An extension or marker alone is not sufficient validation. Full import/export validation accepts exact canonical v1 schema definitions,
limits input files to 512 MiB and individual SQLite values to 16 MiB, and applies
a 30-second validation budget. A timeout has its own error, not invalid-data
classification. Normal opening and current-state reads do not run integrity/FK
or transaction-domain audits; use full checks at file ingress and snapshot
verification. Timestamp formatters are reused on the serial database worker. V1 is the only implemented version; reject newer/unimplemented versions without modifying them.

Do not download rates, rerun MMEX conversion, reseed, or merge. After success,
accounts, history, currencies, rates, categories, and settings all come exclusively
from the imported dataset.

## Export

Settings offers Save Database Copy. Finish preceding writes, create a consistent
standalone file using sqlite3_backup, close it, and verify it opens independently.
Present the completed file in the system exporter with a suggested name such as
Trexpend-2026-10-17-173000-12345678.sqlite. The user chooses iCloud Drive or another location.

Export uses UIDocumentPickerViewController with asCopy enabled. An experimental
SwiftUI Transferable exporter crashed inside NSFileWrapper.setPreferredFilename
on this Simulator and was removed. Keep the snapshot until both the native
delegate completion and sheet dismissal have arrived, in either order.

Only report success after the exporter reports completion. Cancellation/failure
leaves the working ledger unchanged. Clean temporary snapshots after the system
is finished with them. Portable app_settings travel with the snapshot; device-only
UserDefaults do not. Export is manual backup, not synchronization.

## Reset

Settings offers Reset Database beside import/export. Always require a destructive
confirmation that clearly says the current accounts, transactions, categories,
rates, and dataset settings will be replaced by the initial defaults. Cancellation
changes nothing. Offer ordinary export before the user chooses reset; do not force
an extra backup step or claim reset itself makes a permanent backup.

After confirmation, prepare and validate a fresh candidate and use the replacement
engine. Do not implement reset as a chain of DELETE statements against the active
file. On success, reset database-linked preferences, remove the old history and
custom data from the active dataset, invalidate drafts/requests, and reload views.
The new ledger has no user transactions. UserDefaults device preferences and
previously saved exports remain untouched.

The recovery copy is temporary implementation state, not an undo feature or a
retained backup. Clean it after success. If reset fails before commit, the prior
dataset remains or is restored. Reset is never an automatic response to corruption.

## Verification Boundaries

Use temporary directories and synthetic databases in tests. Cover clean creation,
reopen without reseeding, import cancellation/rejection, intact sources, settings
replacement, snapshot reopen/restore, confirmed/cancelled reset, and injected
failures/restarts at each replacement boundary. Later financial editing must not
be enabled before export/restore and reset recovery tests pass.

## Technical References

- [SQLite Online Backup API](https://www.sqlite.org/backup.html).
- [SQLite atomic commit and recovery](https://www.sqlite.org/atomiccommit.html).

## Recovery Without an Open Ledger

Tabs and Settings remain accessible regardless of database availability. Failed
startup presents Import Database, Reset Database, and Cancel. Cancelling leaves
the shell usable; Settings offers the same recovery actions. Export requires a
usable connection. Import and reset still require replacement confirmation.

A recovery replacement stages and fully validates a fresh file independently of
the failed connection. It writes a durable recovery-required sentinel and archives
old working/journal/replacement artifacts under Application Support/Trexpend/Recovery
before clearing conflicting artifacts. These archives preserve failed data and are
not daily backups. The shared replacement marker records unavailable/hadWorking
flags so rollback need not validate an unreadable old file. Pre-commit interruption
keeps the unavailable state; committed recovery opens the replacement. The sentinel
prevents automatic empty creation during an interrupted recovery attempt.

## Temporary Export Lifetime

Internal export snapshots use the app-owned TemporaryExports directory, excluded
from system backup. Startup removes abandoned snapshots there and in the legacy
Exports directory once per store lifetime. Reopening an already active store does
not delete a snapshot still used by a document picker. Manual exported files and
Documents/Backups are outside this cleanup.

## Daily Local Backups

On successful startup and foreground activation, attempt one complete SQLite
backup per local calendar day.
Store validated standalone snapshots in Documents/Backups; enable UIFileSharingEnabled
and LSSupportsOpeningDocumentsInPlace so Files exposes On My iPhone/Trexpend/Backups.
The working ledger remains private in Application Support. Custom test directories
use an isolated backup folder. Backup failure shows a warning in Settings and does
not make the database unavailable. A later launch retries.

Publish through a staged file and rename. A completed backup for today prevents
duplicates; an unreadable same-day file does not count as success. After obtaining
a usable current-day copy, remove recognized automatic-backup filenames older than
30 local calendar days. Preserve files with other names. Reset and replacement
imports do not delete saved backups. Clean abandoned owned partial backup files.

This is launch-triggered backup, not a guaranteed background daily schedule: no
launch means no new copy. Files are local, are not automatically synchronized to
iCloud Drive, and are removed if the app is deleted. Manual export to an external
folder remains available and provides an independent copy. A future external
folder option would require initial user selection, persisted permission/bookmark,
and handling unavailable or revoked provider access.
