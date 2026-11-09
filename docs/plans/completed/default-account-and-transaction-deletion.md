# Default Account and Transaction Deletion

## Purpose

Complete daily-use Settings and transaction management: the stored default account
cannot currently be changed in Settings, and transactions cannot be deleted.

## Goal

Settings selects an open default account or None and persists it with the ledger.
Account and All histories reveal a red Delete action on a trailing swipe; full
swipe never deletes. Existing-transaction editing offers Delete below Save.
Deletion requires confirmation, commits atomically, and refreshes all balances and
history. A transfer and its embedded fee disappear as one operation.

## Scope

Default-account picker and deletion only. No schema changes, account management,
undo/soft-delete, new dependencies or Simulator launch/tests. Preserve current
layout, draft defaults, pagination and manual export/backup behavior.

## Implementation Approach

- Reuse the account catalog and SettingsState's serialized save/operation handling.
  Show only open accounts, favorites first, with name/currency and current checkmark.
  Allow clearing the nullable default. Failures keep the previous value and show an
  error; validate openness and dataset generation again at the write boundary.
- Persist app_settings.default_account_id only. Selecting a default affects future
  drafts, not an already-open draft or the account-history creation override.
- Read a deletion target (complete persisted SQL row plus dataset generation) before
  confirmation; editing uses its original loaded record. Recheck the row inside the
  write transaction so a missing/changed/reused ID cannot silently delete another
  operation. Do not validate unsaved editor fields to delete the persisted record.
- Use native SDK 27 swipeActionsContainer with trailing row swipeActions and
  allowsFullSwipe=false. A red non-destructive reveal button requests confirmation;
  the confirmation button performs the destructive action. Do not remove rows or
  change displayed balances optimistically.
- Share deletion confirmation/busy/error state between both histories and editor.
  Cancel writes nothing. Disable duplicate actions and Save during deletion; keep
  editor drafts on failure. Close the editor only after successful deletion.
- Delete one transactions row using bound parameters. The fee is stored in that
  row, so no second record exists. Keep accounts, categories, rates, remembered
  category/pair preferences and unrelated operations. Remembered pairs represent
  last successful creation, not a recalculated historical ranking.
- Publish through existing transaction revision invalidation, retaining history
  ranges and nearest surviving anchor. Old page cursors are invalid after deletion.
  Prepare the success snapshot before commit so a later read cannot report a false
  deletion failure. Default selection does not change transaction revisions.

## Database Changes

None. Use existing app_settings.default_account_id and physical transaction deletion.
No migration or downgrade SQL is needed.

## Tasks

- [x] Inspect current Settings, editor, histories, financial rules and SDK support.
- [x] Implement validated default-account catalog/save and Settings picker.
- [x] Implement atomic deletion with original-record/generation guards and shared state.
- [x] Connect native trailing swipe and edit-footer Delete with confirmation/errors.
- [x] Add focused synthetic tests for persistence, closed/stale choices, ordinary
  and transfer deletion, both fee sides, rollback, stale/missing records, unchanged
  preferences, refresh and invalidated cursors.
- [x] Build for iPhone without launching Simulator; run native synthetic checks.
- [x] Update specifications and record checks and limitations.

## Verification Results

- Generic iPhone build passed with iOS 27. The app and test target also passed
  build-for-testing with signing disabled; this compiled tests without executing
  them or launching a device/Simulator.
- A native macOS executable compiled production database, Settings/editor/deletion
  state, Home and history sources and ran on disposable synthetic SQLite data.
  Passed default selection/clear, closed/missing/stale rejection, future-draft
  defaults, retained existing drafts and account-history override.
- Native checks passed ordinary deletion and cross-currency transfer deletion
  with each fee side, cancellation, stale/missing record protection, invalid-database
  failure safety, preserved account/category/pair preferences and snapshot export.
  Both histories rebuilt their 61-row loaded ranges to 60 rows after deletion,
  retained the oldest row, restored balances and rejected the old pagination cursor.
- Added persistent unit tests for defaults, transfer fees, stale records/datasets,
  cancellation and failure. Simulator-hosted tests were not run.
- Native swipe APIs were confirmed in the installed SDK interface. Gesture reveal,
  alert presentation and edit footer layout were source-reviewed and compiled;
  their runtime UI verification remains for a physical device at the user's request.
- No personal ledger was changed. Native harness/resources and build logs remain
  in ignored local/. Diff and ASCII checks passed. No Simulator launch or reboot.

