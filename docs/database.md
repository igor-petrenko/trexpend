# Database and File Lifecycle

## Status and Architecture Change

Trexpend will use its own SQLite schema. A one-time offline conversion on the
computer will transfer selected data from the original MMEX export into that
schema. This supersedes operating on a copy of the MMEX schema.

The application will import and restore only supported Trexpend databases.
No MMEX importer, converter, or legacy SQL belongs in the iPhone target.
Canonical v1 SQL, the desktop converter, and a verified private trial dataset
exist. Application data access/import is not implemented yet.
See [Database design](specs/database-design.md) and the consolidated
[Conversion mapping](specs/mmex-conversion.md) for decisions and source disposition.

## Schema Rules

- All table and column names use lowercase ASCII `snake_case` without spaces.
- Choose names and structures for Trexpend, independently of MMEX identifiers.
- Define primary keys, required fields, unique/check constraints, and foreign keys.
- Enable and verify SQLite foreign-key enforcement on every applicable connection.
- Specify delete behavior explicitly. Account closure does not delete history.
- Store monetary amounts and opening balances as decimal TEXT with fractional
  precision from currencies.decimal_places; calculate with Decimal and round
  to the relevant currency precision before persistence using
  nearest rounding with halfway cases away from zero. Exchange rates use decimal
  TEXT without a fixed fractional scale; validate their calculable precision/range.
- Store primary local transaction date/time as TEXT without timezone conversion.
  Add an auxiliary offset-aware occurrence timestamp for future use; write it on
  creation or explicit date/time edits, not on unrelated edits. Current display
  and summaries use only the primary field date. For legacy transactions, assign
  the TRANSDATE calendar date plus LASTUPDATEDTIME clock time, with the combined
  date-specific America/Toronto offset. Map full LASTUPDATEDTIME to technical
  transaction updated_at separately. No time-precision flag is required.
  See the database design specification for conversion and sorting behavior.
- Account dates are open_date, optional exp_date, and optional close_date.
  They do not filter retained history; exp_date is card expiry metadata and does
  not trigger automatic closure.
- Account metadata includes optional color and notes, technical created_at and
  updated_at timestamps, and a reference to account_images. Built-in account images
  are protected; custom image management remains deferred.
- Reserve nullable accounts.current_balance but leave it NULL and unused initially.
  Derive balances from initial_balance and complete eligible history on demand.
- Use a Trexpend schema version and versioned future migrations.
- Define ordering and indexes from actual history and summary queries.

## Offline Conversion

Read the original file without modifying it. Keep original exports and converted
personal databases under ignored `local/`; never bundle them with the application.
The implemented converter is tools/convert_mmex.py, separate from the app.
See [usage](development.md) and [v1 schema](specs/database-schema.md).

Before conversion, agree a field-by-field map: source, destination, transformation,
meaning, and either retention or explicit omission. Unknown or populated optional
fields need a decision, not automatic disposal. Account identities, selected
transaction history, balances, categories, currencies, and both transfer amounts
must remain consistent. Tags, payees, transaction statuses, and transaction numbers are explicitly omitted.

The converter creates a new destination and remaps all related identifiers together
if Trexpend uses new IDs. Do not infer chronological order from legacy IDs.
Validate constraints, row mappings, opening balances, per-account balances, period
totals, currency coefficients, and both sides of transfers before accepting output.
Document source amount normalization and unknown-time handling. Keep any private
conversion report outside version control. Plan the converter before running it.

Omitted source information remains in the archived original. A later feature may
need a separate extraction or manual entry; omission does not guarantee effortless
future recovery into an evolved schema.

## File Identity, Versions, and Indexes

Canonical v1 SQL implements these choices:

- Use PRAGMA application_id 0x54525850 as a Trexpend file marker, together with required-table,
  integrity, and domain checks. An extension alone cannot identify a valid file;
  the marker is not authentication or proof that contents are trustworthy.
- Use PRAGMA user_version starting at 1 for the application schema version, not
  SQLite's internally managed schema_version. Store ordered migration SQL with
  the code. No separate migration-history table is needed initially.
- Apply each supported upgrade atomically and advance user_version only on success.
  Retain a consistent snapshot for recovery; reject unsupported newer versions.
- Add indexes for actual account/date and all-history queries, including both
  transfer sides. Choose exact columns and ordering with the final queries; avoid
  speculative indexes on every field. Indexes speed reads at storage/write cost.

## Working Database

Use the system SQLite library behind one database store. Proposed app location:
`Library/Application Support/Trexpend/`. The selected Trexpend file is a source
snapshot; operate on an app-owned working copy and leave the selected file intact.
Do not keep a live SQLite connection to an iCloud document.

SQLite records and app_settings are the source of truth for the dataset.
[User settings](specs/user-settings.md) defines portable dataset preferences in
SQLite and device-only preferences in UserDefaults.
Do not duplicate the ledger in Core Data or SwiftData. Manual export provides
access to a portable snapshot rather than requiring direct access to app storage.
External modification of an active working database is unsupported.

## Connection and Query Rules

One store owns connection lifetime and serialized access on a dedicated worker
queue. Finalize statements and close handles there. Use bound parameters, bounded
lock waits, explicit transactions, and error handling without private row contents.

Related writes commit as one operation. Read summaries from consistent snapshots.
Specify journal mode in the storage plan and account for its recovery files.

Read history in bounded pages using date/time and a stable final ID tie-breaker.
Sort within each day by stored time ascending, starting with midnight. Summary calculations
must use complete eligible history, not the currently loaded list pages.

## Trexpend Replacement Import

1. Acquire access to the selected Trexpend file through the system picker.
2. Stage a standalone local candidate; handle provider download/access failures.
   Use SQLite-aware copying when the selected source may have active journal state.
3. Validate integrity, Trexpend format identity, supported schema version, required
   schema elements, foreign-key integrity, and domain constraints.
4. Apply only supported, planned migrations to the staged copy when needed.
5. Serialize the switch with database operations and retain the previous file
   until the candidate has opened successfully.
6. Switch dataset generation, discard stale results/editors, revalidate preferences,
   and reload the UI.
7. Clean staging files and release external access.

Imports replace, never merge. Failure leaves the working database usable.
Reject MMEX, unrelated SQLite databases, and unsupported newer versions before
switching. Define an interruption-safe recovery procedure in the import plan.

## Export and Restoration

Create a consistent standalone destination with SQLite backup facilities, after
in-flight commits and before subsequent writes. Check completion and ensure it
opens independently of working WAL/journal files. Present the completed snapshot
through the system exporter; the user chooses iCloud Drive or another Files folder.
Only report export success after the system export succeeds.

Cancellation/failure does not modify the working database. Restore through the
same validation and replacement path. Choose the file extension and timestamped
suggested filename in the detailed export specification.

Snapshots include app_settings and its dataset preferences. UserDefaults contains
only device preferences excluded from the snapshot. Reload and validate settings
after restoring a dataset; no old dataset preferences may leak into the new one.
Manual export is not synchronization. Removing the app removes local data; an
independently saved snapshot is the restoration source.

## Schema Evolution

Define Trexpend format identity and version metadata before implementation.
Future migrations require exact SQL, ordering, verification, and recovery plans.
Take a recoverable snapshot before destructive changes; do not silently downgrade
unknown versions. Keep internal migrations independent of MMEX releases.

## References

- [SQLite: Datatypes and date/time storage](https://www.sqlite.org/datatype3.html).
- [SQLite: Foreign Key Support](https://www.sqlite.org/foreignkeys.html).
- [SQLite: Floating Point Numbers](https://www.sqlite.org/floatingpoint.html).
- [SQLite: Online Backup API](https://www.sqlite.org/backup.html).
