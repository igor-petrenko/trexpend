# Account Favorites and Full-Row Navigation

## Purpose

Home account rows ignore taps in their empty central space, and the account
header favorite indicator has no action.

## Goal

The entire padded account row opens history. The header star adds/removes the
account from favorites, persists across reopening, and updates Home ordering.

## Scope

Home hit testing and account favorite editing only. Preserve existing ledger,
transaction editor and navigation work. No Simulator launch or Simulator tests.

## Implementation Approach

Give HomeAccountView a rectangular content shape after padding. Replace the
header image with an accessible button, disabled during its pending write.
Serialize a bound favorite/updated_at update through DatabaseStore/DatabaseLifecycle
with an expected dataset generation, existence check and atomic commit. Publish
an account metadata revision separately from transaction revisions: Home refreshes,
account history updates its favorite projection, pagination stays valid. Report
write errors without optimistically changing the star.

## Database Changes

None. Use existing accounts.favorite and accounts.updated_at; no schema migration.

## Tasks

- [x] Inspect hit testing, header controls and existing database/refresh ownership.
- [x] Fix Home full-row hit testing and implement persisted favorite toggling.
- [x] Verify persistence, removal, Home ordering, invalid IDs/generations and
  transaction/page preservation with synthetic data outside the Simulator.
- [x] Build application without launching a Simulator; update behavior documentation.

## Verification Results

- iOS 27 generic-device build passed with signing disabled; no app launch.
- Native macOS checks compiled the production database, session, Home and history
  state sources and passed against a disposable synthetic ledger: favorite
  add/remove, reopening, exported snapshot, Home ordering, 65 retained history
  rows, unchanged pagination revision, invalid IDs/generations and unchanged
  financial records. Temporary fixtures and binaries remain ignored in local/.
- Added two persistent HomeDashboardTests for favorite persistence/ordering,
  generation guards, loaded-history retention and failure behavior. Simulator-hosted
  suites were not run, as explicitly requested.
- Full-row content shape and favorite button state/error/accessibility were reviewed
  in source. Runtime UI tapping was not exercised because Simulator testing was
  excluded. No Simulator was launched or rebooted.
- Documentation, ASCII and git diff --check passed.
