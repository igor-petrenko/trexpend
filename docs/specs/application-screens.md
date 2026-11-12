# Application Screens

## Status

Agreed first-version behavior with proposed choices explicitly identified below.
The shell, database lifecycle, read-only Home, and display-currency selection are
implemented. Read-only account and all-account history are implemented.
Transaction creation/editing is implemented, with remaining native verification
listed in the
[Transaction editor implementation plan](../plans/transaction-editor.md).

## Navigation

Use four tabs: Home, All, More, Settings. Each tab owns its NavigationStack.
Home opens account history; both history lists open the shared transaction editor.
Creation uses a bottom sheet with Save and Cancel; editing uses a full-screen page.
Account history is a navigation push. The editor uses a separate draft.

## More

More is the auxiliary navigation hub, with an ellipsis tab icon and a Management
section linking to Accounts, Categories and Currencies. Accounts opens the bank-grouped account manager. Categories and Currencies
remain placeholders for subsequent work.
Add future reports/statistics or other auxiliary destinations here when available.
Keep Settings as its own tab. More remains available without a working database;
startup Import/Reset shortcuts continue opening Settings. The existing Settings
currency picker changes the display currency, independently of future currency
and exchange-rate management.

## Home

- Show only open accounts, with names and current balances in their native currencies.
- Group by Credit Cards, Checking, Cash, and Deposits. Sort favorites first within
  each type, then by localized name with ID as a stable tie-breaker. Mark favorites
  with yellow stars. Show the optional bank below the account name.
- Use one compact statistics card: total balance first, a divider, then the
  current month/display currency and equal-width income/expense columns with
  centered headings and figures. Add a
  third difference column only when income is nonzero. Do not reserve its space
  when hidden. Use smaller scalable figures; stack metrics at accessibility sizes.
  Omit a large Home title.
- Under each native balance, show smaller green income and red expense with
  diagonal arrows. Prefer one horizontal line; stack only when the amounts do
  not fit. Vertically center the icon, name/bank, and balance column within each
  account row, including missing-bank and inactive-account cases. Hide them only when the account had no monthly activity. With
  activity on one side show zero on the other; transfer-only activity may show
  zero/zero because transfer principal is excluded. Fees count as expenses.
- Exclude closed accounts from the Home combined balance. Closing an account never
  removes its records or changes historical transfers.
- Tapping anywhere within the padded account row, including blank space, opens
  its history through native navigation.
- Show combined balance, current-calendar-month income, and expenses in the chosen
  display currency. New/reset ledgers default to USD; imports retain their saved choice.
- Monthly income and expenses include closed-account transactions. Only the
  combined balance and account rows exclude closed accounts.
- Show the create action when an eligible open account exists. Its
  size is 64 by 64 points at the lower right. Keep 96 points of bottom scroll
  padding so the final account can scroll clear of the future action and tabs.
- A clean launch automatically creates the initial
  database; import is optional. Show an empty-history state after successful creation,
  startup progress while opening, and a distinct error if opening fails.
- A fresh/reset ledger has no accounts. Until account management is implemented,
  use import to supply accounts; do not create a sample account or offer transaction
  creation without an eligible account.

View responsibility: layout, selection, and sheet/navigation presentation.
Home state responsibility: load account summaries and aggregate results, handle
loading/errors, and refresh after writes, conversion changes, and month changes.
The finance component, not the view, defines totals.

## History Navigation and Position

Switching between Home (including its open account destination), All, and Settings
keeps each existing history screen's loaded pages and native scroll position.
Reappearing with the same database generation/account/display currency/month
reuses loaded state instead of replacing it with page one. Explicit refresh and
Retry perform actual loads. Dataset replacement clears old navigation/content;
display-currency or month changes invalidate the relevant snapshot. Backing out
of an account and opening it again creates a fresh history at the top. Scroll
restoration across app termination is not part of this stage. Future transaction
writes must explicitly invalidate affected history rather than relying on appearance.

## Account History

The inline navigation header shows a custom account image before its name when
an uploaded image exists. It uses a 28-point transparent avatar and omits built-in
icons. Without a custom image, retain the standard text-only navigation title.


- Filter transactions by the selected account, including either side of transfers.
- Open with the entire history, loading additional pages on scroll. The summary
  above the list is separately labeled with the current calendar month.
- Group rows by calendar date, newest days first. Within each day, show later
  stored local times first. Use transaction ID as a stable final tie-breaker.
- Show date, amount/direction, category, and appropriate transfer counterparty.
- Use the same statistics card as Home for the selected account, including a
  conditional difference column and its native currency in the month heading.
  Show the favorite button in the trailing navigation toolbar: yellow filled
  star for favorites, secondary outline otherwise. Tapping it persists the choice
  and refreshes Home ordering. Disable it while saving; on failure keep the old
  value and show an error. Favorite changes preserve loaded transaction pages.
- Show a smaller, secondary-colored approximate display-currency equivalent
  directly below and right-aligned with the native balance when its currency
  differs. Prefix it with the approximation symbol rather than a word. Ordinary transaction rows stay in the
  account currency, without repeating its code. Transfer rows show only the
  selected account principal; preserve both amounts in storage. Do not add a converted
  equivalent to each transaction row.
- Create opens an expense draft with this account selected; for transfers, propose
  using it as the source account.
- Tapping a row opens edit mode. A right-to-left trailing swipe reveals Delete;
  full-swipe deletion is disabled. Delete requires explicit confirmation and leaves
  the row intact on cancellation or failure. A transfer is deleted as one operation,
  including its fee, and both account balances and complete summaries refresh.

History state requests records and complete summaries; pagination must not affect
totals. The view formats and groups records using shared date/amount presentation.

The general account-history mockup was accepted on 2026-10-24. The first delivery
was read-only. Summary scrolls with the list; creation and row editing are now
available, including confirmed deletion; an All time selector remains deferred. Transaction rows have three
columns: icon, identity/details, amount. Category/counterparty and time form the
primary two-line block; align icon and amount to its center. Notes, transfer
category, and explicit fee ownership extend only the middle column below it. Each
central text line truncates with an ellipsis. Reserve width for the complete
trailing amount; never move it below the identity. Home account names still wrap.
Ordinary rows use their category icon with expense/income direction styling.
Expense amounts use the primary text color in both account and All history,
while income amounts remain green. Category icon styling is unchanged.
Transfers always use neutral transfer arrows, the selected-side amount, and explicit
nonzero fee ownership. There are no per-category custom colors in this stage.

Category icons will be stored in a category_icons catalog with nullable
categories.icon_id. The future category editor will choose from this catalog;
SF Symbols provide artwork, and missing selections/symbols use a general fallback.
The v2 migration and initial assignments are implemented; management UI is deferred. See the
[Account history plan](../plans/account-history.md) for migration and delivery tasks.


## All History

Include historical records from closed accounts. Editing an existing transaction
must retain access to its original closed account, including either side of a
transfer. Do not require moving the record to an open account just to edit it.

Read-only All behavior was agreed and implemented on 2026-10-28. See the [All history plan](../plans/completed/all-history.md).

Reuse date groups and ordinary rows with a secondary account-name line above the
category and a currency-code line above the native amount. Preserve the amount's
width priority and truncate central text. Do not add per-row converted equivalents.

A transfer remains one card: source above destination, with a divider in the
middle/right columns and one neutral icon centered across the entire card. Always
show source negative/red and destination positive/green amounts in their respective
sections, even when both currency and amount match. Overlay a small static transfer
arrow symbol on the inner divider to distinguish it from separators between records. Notes and nonzero fee ownership appear once. Account-history
transfer presentation remains unchanged.

Use the Home-compatible complete statistics card above all dates, with an explicit
current-month label. Keep the Transactions heading's trailing region available for
future filter controls; do not show inactive filter actions.
Creation, row editing and confirmed swipe deletion are connected; filtering remains deferred.

## Transaction Editor

Use one view and state for creation and editing.

### Confirmed Editor Presentation (2026-10-29)

- Create uses a native adjustable bottom sheet across the available phone width.
  Focus the amount and show the standard decimal keyboard automatically on initial
  presentation. Use the expanded sheet position while entering text; dismissing
  the keyboard returns to the compact position unless the user chose an expanded
  resting position. Exact sizing/keyboard transitions require runtime verification.
- Save remains a separate persistent action above the keyboard or bottom safe area;
  Cancel remains in the persistent header. Only the form body scrolls. Do not add
  a keyboard-dismiss button beside Save or change its horizontal layout with focus.
  Dismiss input on a non-input background tap or an interactive form scroll; allow
  opening account/category selectors directly without prior keyboard dismissal.
  Moving to another text field transfers focus instead of closing input.
- The entire amount surface activates its field, including the trailing currency
  region. Use moderate amount typography rather than the initial oversized mockup.
- New expense/income forms show type, account, date/time, amount, category, and
  notes. Editing keeps type, date/time, account, amount, category, and notes.
  Transfer retains its existing field order. Right-align numeric input in Amount,
  Received amount and Fee, immediately before the currency code.
- Edit uses a separate full-screen presentation. Lay out all fields in normal
  top-to-bottom order without the mockup's large flexible gap; Save remains below
  the scrolling form. Do not autofocus an input on edit presentation; autofocus
  applies only to creation. Preserve stored field values.
- Keep sheet height stable during account/category/recipient picker navigation.
  Clear editor input focus before pushing. After a completed return, retain the
  current sheet height as the new resting height rather than contracting the form.
  The user can still resize the sheet manually. A cancelled back gesture must not
  trigger contraction. Device verification of transition rendering is
  tracked in [picker transition plan](../plans/editor-picker-transitions.md).
- The editor's selected Account, From, and To values show an uploaded custom
  image before the account name, at 32 points with no background. Built-in icons
  and fallback symbols are omitted from these form fields. Accounts without a
  custom image reserve no icon space; the full row still opens account selection.
- Account pickers show the shared account avatar, including custom images with
  transparent backgrounds and built-in type/image overrides with their icon tint.
  Image bytes load lazily for visible rows; the catalog carries only identifiers.
- Account/category selection round trips preserve amount, notes, date/time, and
  all other draft values. Account changes preserve entered numeric strings and
  never trigger currency conversion or silent rounding of manually entered amounts.
- Changing Expense to Income or back preserves account, amount, category, notes,
  and date/time. Switching into Transfer retains those values for the source,
  but selects the designated Transfer category even if another category was chosen.
  Leaving Transfer retains the currently selected category; do not restore an older
  ordinary category automatically. A later transition into Transfer selects the
  designated Transfer category again.
- Closing a changed form via Cancel or interactive dismissal asks to discard the
  changes or continue editing. Confirmed discard clears the draft and closes it.
  No saved draft or restoration on the next editor opening is required. Merely
  focusing the initial amount does not mark a new draft as changed.

### Confirmed Transfer Receiver Suggestions (2026-10-30)

- For each source, prefer the recipient remembered from its last successful new
  transfer creation. Editing an old transfer or cancelling does not update it.
- Without a remembered eligible recipient, use the most frequent eligible
  destination in existing outgoing transfer history, breaking ties by latest use.
- Without an eligible historical choice, select the sole other open account if
  there is exactly one; otherwise require explicit recipient selection.
- A suggested recipient must be open and different from the source. Reevaluate
  automatic suggestions on entry into Transfer or a source change, not each digit.
- Preserve a manually chosen recipient across source changes. If it equals the new
  source, require another recipient before saving rather than silently replacing it.
- Store one preferred recipient per source in SQLite, included in backups and
  dataset replacement. Bootstrap from history once on schema upgrade/conversion;
  update atomically with successful new transfer creation. Normal opening reads
  the saved pair, not the full history. Invalid/missing preferences may use a
  source-scoped fallback lookup. Schema and import tasks are in the editor plan.

### Fields and Persistence Rules

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
  Implemented editor behavior: automatic suggestions only while the destination is
  untouched; never overwrite a manual value or existing transaction amounts on
  opening, account changes, or background rate refresh. Exact recalculation
  controls are not added in this stage.
- Category: exactly one required selection, including transfers. The picker shows
  favorite categories first, including nested favorites with their parent path,
  followed by an expandable hierarchy. Selecting a parent category is allowed.
- Transfer fee: default the charged account to the source even for zero fee;
  allow choosing the destination. Labels must make clear that transfer amounts exclude fee. Changing an account
  preserves monetary numbers and updates the charged-account reference by side.
- Notes: optional editable text.
- Tags and payee/payer: omitted from the initial schema and editor.
- Save and Cancel; edits are not persisted until Save succeeds. Existing-record
  editing also shows Delete transaction below Save. It confirms deletion of the
  saved original record, including transfer fee, regardless of unsaved draft values.
  Success closes the editor; failure retains its draft. New creation has no Delete.

The view owns controls and focus. Editor state owns the draft, validation messages,
saving state, and the save request. Parsing and financial validation use shared
rules. The store maps and persists changes atomically.

Disable duplicate saves while a write is pending. Keep values on failure.
Cancellation never modifies the record. Protect a changed draft from accidental
sheet dismissal using the confirmed discard/continue-editing behavior above.

Changing a transfer to expense/income keeps the source account and amount, clears
receiver fields, and resets fee and fee_account_id. Categories remain required.
For new same-currency transfers, derive the hidden receiver amount from the source.
No equality validation is required; unrelated edits preserve saved amounts.

## Settings

Offer only open accounts as the default for ordinary new transactions. If the
saved default is closed or missing, require a valid open-account selection or use
the documented eligible fallback.

- Default account for new transactions: implemented Settings picker with open
  accounts, favorites first, name/currency and selection checkmark. None clears the
  nullable default. Persist with the dataset and validate eligibility on Save.
  Existing drafts retain their account; account-history creation keeps its override.
- Display currency for converted totals: implemented searchable catalog picker.
  Persist the selection in app_settings without changing rates or monetary values.
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
- Missing/ambiguous General or Transfer catalogs use the explicit-selection fallback
  documented in the editor plan; no category IDs are hardcoded.
- Date conversion edge cases; primary local date and auxiliary offset behavior are agreed.
- New-record versus edit defaults and type switching are defined above.
- Creation placement, transfer formatting and confirmed deletion are implemented.

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

## Home Implementation

Concept B was approved with the refinements recorded in the
[Home dashboard plan](../plans/completed/home-dashboard.md). The initial concept artwork
includes future controls; the working screen uses native system tabs and hides
editor/history actions until their destinations exist.

Home loads one coherent SQLite snapshot on the serial worker, scans history once,
and computes all native balances and monthly figures together. Missing rates
make only dependent converted totals unavailable, never a partial sum or a false
zero. Native rows remain visible. Difference is the displayed income minus the
displayed expense. Refresh on foreground, month rollover, currency/database
changes, retry, and pull-to-refresh. No balance is written to current_balance.


## Account Management

Accounts under More groups accounts by bank, with optional bundled bank logos and
an unassigned group last. Open is the initial filter; Closed and All are available.
Rows show the full name, account image, favorite marker, type, currency, and native
balance. The Add button and empty-state action open account creation. Tapping an
account opens its editor. Account history exposes the same editor after the star.

The full-page editor has Cancel and a fixed bottom Save action. It edits name,
type, bank, favorite, initial balance, optional credit limit, opening/card-expiry
dates, account/card number, notes, image, and icon color. Currency is selectable
only for new accounts. Require a nonempty name on save; duplicate names remain
valid. Initial balance may be changed without a warning, even with history.
The displayed current balance is persisted-state information calculated from history.

Closing/reopening is confirmed, staged in the draft, and applied on Save. Closing
clears a default-account reference. Reopening clears closure date. Accounts with
transactions can be closed but cannot be deleted; unused account deletion is
confirmed and rechecked at commit. View transactions also reaches closed history.
Cancel confirms discarding dirty drafts. Failed writes retain the draft.

Initial banks are PrivatBank, CIBC, and monobank. Existing bank names are preserved
as separate entries when needed. The current form selects a bank or No bank;
bank creation/editing will be provided on a separate future page.

Custom account images come from Photos or Files, are normalized to bounded PNG,
and are stored in SQLite so export/import and daily backups preserve them. Image
selection does not persist anything before the account save commits. Built-in
choices use native symbols and support a type-default fallback. Runtime layout,
photo/file pickers, and accessibility still require device acceptance; no Simulator
execution was performed. See [account-management plan](../plans/account-management.md).

Custom account images retain their aspect ratio and use a transparent avatar
background. The tinted rounded background applies only to built-in symbol icons
and their fallback while a custom image is unavailable.
