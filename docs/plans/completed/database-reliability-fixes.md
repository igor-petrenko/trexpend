# Database Reliability Fixes

## Purpose

Resolve the confirmed review failures before implementing financial screens.

## Goal

Ordinary cross-currency totals succeed with final-only currency rounding. Normal
opening and snapshot reads do not audit transaction history. Users can navigate,
restore a backup, or confirm reset after database startup failure. Abandoned
internal export snapshots are cleaned on next startup.

## Scope

Include arithmetic policy, fast versus full validation, recovery UI and durable
replacement of unreadable data, temporary export cleanup, regression tests, and
documentation. Keep canonical v1 SQL comparison unchanged as requested. Daily
backups use Documents/Backups, visible in Files, as selected by the user.
Check on startup and foreground activation each local day; retain 30 days. No scheduled
background execution or automatic iCloud destination is included.

## Implementation Approach

- Keep strict persisted-money arithmetic. Allow finite, precision-limited Decimal
  results for valuation, including intermediate division and aggregate addition;
  never round individual values to currency precision before totaling.
- Separate schema/settings snapshot reads from full import integrity/domain
  validation. Reuse timestamp formatters during full checks. Report validation
  timeout distinctly; do not classify a time limit as invalid data.
- Keep tabs and Settings available after startup failure. Show one startup alert
  offering Import, Reset, or Cancel. Import/reset have explicit confirmation.
- Permit an unavailable dataset to be replaced after staging/validation. Preserve
  all old working/recovery artifacts in an app-owned recovery directory before
  starting a clean replacement; keep that directory through success or failure.
  Never require corrupt old data to pass validation in order to restore a backup.
- Keep generation checks for ready-dataset operations. Recovery requests are
  allowed only while there is no usable working connection.
- Place temporary exports in an app-owned directory excluded from system backup, clean abandoned files
  at process startup and remove legacy internal Exports on startup. Do not touch
  saved user backups or an export currently in use by the system picker.

- Keep the working ledger private in Application Support. Share only Documents
  through the standard Info.plist file-sharing keys. Backups use SQLite snapshots,
  atomic publication, and owned filenames; clean expired copies only after a
  current-day backup succeeds. Backup failure must not block normal database use.

## Database Changes

None. No schema or amount representation migration. Recovery replacements retain
unreadable files separately; normal replacement continues using durable markers.
No rollback SQL applies to filesystem replacement.

## Tasks

- [x] Fix valuation arithmetic and add regression tests.
- [x] Split fast opening from full validation and distinguish timeouts.
- [x] Support restore/reset without an open database and preserve failed data.
- [x] Add database-independent Settings and startup recovery actions.
- [x] Clean abandoned internal exports without deleting active/saved copies.
- [x] Add visible daily backups, retention, and failure/retry tests.
- [x] Update specifications and verify focused tests, build, and runtime UI.

## Verification Results

- Final iOS 27 Simulator test run passed 58 test functions, with zero failures,
  skips, or runtime warnings. Converter tests passed all 21 cases.
- Regression cases cover recurring cross-currency totals, strict arithmetic
  failures, a 100,000-row working ledger, unavailable import/reset, all six
  unavailable replacement interruption boundaries, source preservation, fast
  snapshots, timeout classification, and abandoned versus active exports.
- Daily-backup tests cover same-day reuse, timezone boundaries, 30-day retention,
  unreadable same-day copies, interrupted partial cleanup, scoped filenames,
  retry after failure, and retaining old copies if a new snapshot fails.
- Native Mac review harness: 100,000-row opening completed in about 0.0012 seconds
  after the split; all 96 sampled valuation combinations succeeded (28 failed
  before). This is a synthetic native benchmark, not an iPhone timing guarantee.
- Simulator screenshots verified the startup alert with Import, Reset, and Cancel,
  and a healthy launch after restoring the original synthetic file. A daily backup
  from the real app container reopened with passing integrity/FK checks.
- Built Info.plist contains both Files-sharing Boolean keys; automated tests assert
  them in Bundle.main. The explicit source Info.plist is merged with generated
  metadata because the generated-only configuration omitted UIFileSharingEnabled.
- Popup-button routing into the system picker and navigation inside Files were
  not interactively automated in this run. Recovery/backup state transitions are
  tested directly. Physical-device and signed-in iCloud testing remain unverified.
- Canonical SQL is unchanged. Text/plist checks and local Markdown links passed;
  no personal files are tracked. No dependencies were added.
