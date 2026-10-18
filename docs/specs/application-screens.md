# Application Screens

## Status

Agreed first-version behavior with proposed presentation choices. Layout details
and control styling remain open. The Home/All/Settings shell, database startup
states, and Settings import/export/reset controls are implemented. Home and All
currently show database status only; financial screens and editing remain planned.

## Navigation

Use three tabs: Home, All, Settings. Each tab can own its NavigationStack.
Home opens account history; both history lists open the shared transaction editor.
Proposed editor presentation: a sheet with Save and Cancel. Account history is a
navigation push. The editor starts in create or edit mode using a separate draft.

## Home

- Show only open accounts, with names and current balances in their native currencies.
- Use account types for labels or grouping; the exact Home arrangement is open.
  A favorites group or other favorite treatment is a possible later layout.
- Exclude closed accounts from the Home combined balance. Closing an account never
  removes its records or changes historical transfers.
- Tapping an account opens its history.
- Show combined balance, current-calendar-month income, and expenses in the chosen
  display currency. New/reset ledgers default to USD; imports retain their saved choice.
- Monthly income and expenses include closed-account transactions. Only the
  combined balance and account rows exclude closed accounts.
- Show an action for creating a transaction with the default account selected.
- Initially place the action at the lower right; use another placement if it
  overlaps rows or summaries. A central tab-bar action remains an alternative.
- After storage is implemented, a clean launch automatically creates the initial
  database; import is optional. Show an empty-history state after successful creation,
  startup progress while opening, and a distinct error if opening fails.
- A fresh/reset ledger has no accounts. Until account management is implemented,
  use import to supply accounts; do not create a sample account or offer transaction
  creation without an eligible account.

View responsibility: layout, selection, and sheet/navigation presentation.
Home state responsibility: load account summaries and aggregate results, handle
loading/errors, and refresh after writes, conversion changes, and month changes.
The finance component, not the view, defines totals.

## Account History

- Filter transactions by the selected account, including either side of transfers.
- Group rows by calendar date; propose newest days first. Within a day, show
  entries in ascending stored-time order, starting with midnight.
  Keep equal-time entries in a stable order.
- Show date, amount/direction, category, and appropriate transfer counterparty.
- Show current balance and monthly income/expenses in the account's currency.
- Also show smaller converted amounts when display currency differs.
- Create opens an expense draft with this account selected; for transfers, propose
  using it as the source account.
- Tapping a row opens edit mode. Swiping reveals Delete; disable full-swipe deletion.
  Propose a confirmation before the actual delete and retain the row on failure.

History state requests records and complete summaries; pagination must not affect
totals. The view formats and groups records using shared date/amount presentation.

## All History

Include historical records from closed accounts. Editing an existing transaction
must retain access to its original closed account, including either side of a
transfer. Do not require moving the record to an open account just to edit it.

Reuse history rows and date grouping, adding account identity to ordinary records.
Proposed transfer representation: one row naming source and destination accounts
and showing both actual amounts when necessary. Do not duplicate a transfer as
separate income and expense records. All history uses a global query and has no
account-specific balance footer requirement.

Proposed create action uses the default account, as on Home. The exact placement
can be shared with account history after layout review.

## Transaction Editor

Use one view and state for creation and editing.

- Type: Expense (create default), Income, or Transfer.
- Date: today by default, with a native date picker accepting any previous date.
  Future dates are not allowed; validate again on Save, not only in the picker.
- Time: current time for a new draft. Changing the date defaults the time to
  midnight; the user may supply another time or keep midnight. Show stored date
  and time in edit mode and preserve both when the user edits other fields. No
  time-precision flag is needed. Preserve local date/time and update the auxiliary
  offset timestamp only on explicit occurrence-date/time changes.
- Expense/income: one account and amount; show its currency next to the amount.
- Transfer: source account/amount and destination account/amount; show each currency.
  Hide the receiver amount field when account currencies match; no stored-amount
  equality validation is required. New-draft hidden-value synchronization is an
  editor detail; preserve existing amounts on unrelated edits. Use saved conversion
  coefficients to suggest a destination amount from the entered source amount.
  The user may replace the suggestion with the actual amount. This is an estimate
  excluding the separately entered fee, not a bank-execution guarantee.
  Proposed editor behavior: automatic suggestions only while the destination is
  untouched; never overwrite a manual value or existing transaction amounts on
  opening, account changes, or background rate refresh. Exact recalculation
  controls remain a UI design detail.
- Category: exactly one required selection, including transfers. The picker shows
  favorite categories first, including nested favorites with their parent path,
  followed by an expandable hierarchy. Selecting a parent category is allowed.
- Transfer fee: default the charged account to the source even for zero fee;
  allow choosing the destination. Labels must make clear that transfer amounts exclude fee. Changing an account
  preserves monetary numbers and updates the charged-account reference by side.
- Notes: optional editable text.
- Tags and payee/payer: omitted from the initial schema and editor.
- Save and Cancel; edits are not persisted until Save succeeds.

The view owns controls and focus. Editor state owns the draft, validation messages,
saving state, and the save request. Parsing and financial validation use shared
rules. The store maps and persists changes atomically.

Disable duplicate saves while a write is pending. Keep values on failure.
Cancellation never modifies the record. Protect a dirty draft from accidental
sheet dismissal; the exact discard-confirmation presentation is still proposed.

Changing a transfer to expense/income keeps the source account and amount, clears
receiver fields, and resets fee and fee_account_id. Categories remain required.
For new same-currency transfers, derive the hidden receiver amount from the source.
No equality validation is required; unrelated edits preserve saved amounts.

## Settings

Offer only open accounts as the default for ordinary new transactions. If the
saved default is closed or missing, require a valid open-account selection or use
the documented eligible fallback.

- Default account for new transactions. In account pickers, place eligible favorite
  accounts first and mark them; closed-account restrictions still apply.
- Display currency for converted totals.
- Import a supported Trexpend database, replacing existing data. No MMEX import UI.
- Save a database copy through the system exporter.
- Reset Database to the first-launch defaults, always with destructive confirmation.
  Cancel leaves data untouched. Reset includes dataset settings, not device preferences.

Require replacement confirmation when a working database exists. Let the user
cancel and export a copy before replacement; do not silently merge data.
Reload and validate default IDs from the new dataset. A NULL default account is
valid for an account-free ledger. Do not invent a default or copy a previous dataset
ID into an imported ledger. Handle closed defaults according to the settings rules.

Settings state delegates preferences to the settings store and file operations to
the import/export coordinator. Dataset settings live in SQLite app_settings and are included in snapshots;
UserDefaults is reserved for device-only preferences, as specified in
[User settings](user-settings.md). The view never manipulates database paths itself.

## Shared States and Accessibility

Distinguish startup/creation, an initialized empty ledger, empty query results,
recoverable read errors, and write errors. The current shell no-database state is
an intermediate state superseded by automatic initialization in the storage stage. Do not display misleading zero totals when a query or conversion failed.
Use native accessibility labels, Dynamic Type, and locale-aware amount formatting.
Communicate income/expense/transfer direction through text or symbols as well as color.

Use the current fixed light appearance and restrained Blue Slate accent. Pick the
remaining palette while implementing real screens. No theme switch is required.

## Closed Account Corrections

Ordinary creation from Home, All, or an open account's history offers only open
accounts. Existing transactions on closed accounts remain editable.

A future account-management screen must allow correcting closed-account history,
including adding an omitted transaction with a historical date. Do not implement
a blanket storage prohibition on writing records for closed accounts. The dedicated
creation workflow and its date restrictions are deferred; no account-management
screen is required in the first version.

## Questions Before Detailed Plans

- Hidden-account behavior is deferred, not an initial implementation requirement.
- Exact labels and category defaults; one category is required, payees are omitted.
- Date conversion edge cases; primary local date and auxiliary offset behavior are agreed.
- New-record versus edit defaults when changing transaction type.
- Final create-button placement, transfer-row formatting, and deletion confirmation.

## Database Lifecycle Specification

First-launch creation, import replacement, snapshot export, and reset behavior are
specified in [Database lifecycle](database-lifecycle.md). The initial dataset has complete default currency/category catalogs, no
accounts/history, and USD display currency; the app must never use the personal converted ledger as a seed.

## Unavailable Database Recovery

Keep all tabs and Settings reachable after startup failure. Show a startup alert
with Import Database, Reset Database, and Cancel. Import opens the system picker;
Reset opens the destructive confirmation. Cancelling does not force recovery.
Settings keeps Import and Reset available without a snapshot; Save Database Copy
requires an open ledger. Show automatic backup warnings in Settings without
blocking financial data or navigation.
