# Account History and Category Icons

## Purpose

Open a useful account transaction history from Home, preserving the established
financial rules and introducing the category icons approved on 2026-10-24.

## Goal

- Open account history by tapping a Home account row and return through native navigation.
- Show current native balance, an optional approximate display-currency equivalent,
  and separately labeled current-month income/expenses.
- Show the entire account history, newest date/time first, with bounded loading.
- Present ordinary category icons and neutral transfer arrows with both actual
  transfer amounts and explicit nonzero fees.
- Preserve existing v1 ledgers/backups through a validated, recoverable v2 migration.
- Keep accounts, operations, relationships, settings, monetary strings, and dates
  unchanged except for the new optional category icon association.

## Scope

Implementation authorized on 2026-10-25. The mockup is accepted as the general layout with the decisions
below. Account history is the only new screen in this checkpoint. All remains a
placeholder; its eventual history will reuse row models and presentation.

Include schema migration support, icon catalog, initial category assignments,
converter compatibility, bundled resources, history queries/state/views, Home
navigation, documentation, and verification. These dependencies are necessary to
use category icons without breaking existing ledgers.

Exclude transaction editing/creation/deletion, category/icon management UI, custom
image files, account management, date filters, search, running balances per row,
charts, new dependencies, and other platforms. Hide the plus action until the
editor exists. No inert edit/delete controls or row disclosures.

## Presentation Revision (2026-10-25)

The authorized [compact summary and rows plan](completed/compact-summary-and-history-rows.md)
supersedes the initial presentation below: account difference is now conditional,
favorite moves to the toolbar, transaction detail text is one-line/truncated in
the central column, and counterpart amount captions are omitted. Stored financial
values and migration behavior remain unchanged.

## Implementation Approach

### Confirmed Screen Behavior

- Inline navigation title: account name; native Back control to Home. Bank is
  optional. A favorite star is a read-only indicator, not a new editing action.
- Compact rounded summary card: native balance, smaller approximate equivalent
  only when display currency differs and a rate exists, then the current month
  and native income/expenses. No per-account difference.
- Summaries include complete history, not loaded list pages. Use the same exact
  accounting and final-conversion rounding rules as Home. Transfer principal is
  excluded from income/expenses; fees belong to the charged account's expenses.
- History opens with all dates. Remove the mockup's All time selector because
  there is no period selection in this checkpoint.
- Day headers descend; rows within a day descend by stored local date/time, with
  ID descending as a deterministic tie-breaker. Do not convert date through UTC.
- Ordinary rows: category name, optional notes up to two lines, occurrence time,
  signed native amount, and the category's icon. Retain inactive categories in
  history. Do not show a display-currency equivalent for individual operations.
- Transfers: To/From and counterparty account, native-side signed principal,
  counterpart actual amount/currency, and a separate nonzero fee caption naming
  its currency and charged account. Do not fabricate a rate-based counterpart.
  Keep the stored category accessible as secondary row text; optional notes and
  local time remain available. Hide the fee caption for zero fee.
- A source principal of 100 USD with 2 USD source fee displays principal -100 USD
  plus the separate fee, and reduces balance by 102 USD. A receiver principal of
  137 CAD with 3 CAD receiver fee displays +137 CAD plus that fee, and increases
  balance by 134 CAD. A fee paid by the other account must not be subtracted here.
- Ordinary direction is communicated through signs/symbols and green/red color.
  Transfers use neutral Blue Slate and transfer arrows regardless of category.
- Vertically center icon, identity, and figures in each row. Allow notes and long
  transfer/fee details to wrap; do not truncate monetary digits. Use a vertical
  alternative at accessibility text sizes, matching the Home refinements.
- Summary scrolls with history. Preserve native tabs, pull-to-refresh, and bottom
  clearance. No operations: show the real balance/summary plus a distinct empty
  history state. Missing rate: omit the approximate equivalent and indicate its
  unavailability without hiding native data or showing a false zero.

### Category Icons

Add category_icons(id, code, name, system_name) and nullable categories.icon_id.
The database catalog is the list offered by the future picker, and travels in
backups. SF Symbols supply the actual artwork; no image bytes are stored.

Use a curated initial catalog from the SQL below. code is a stable semantic key;
system_name is its current iOS renderer identifier. Validate the chosen SF Symbol
names against the installed SDK. If a symbol cannot render, use a known general
fallback. NULL icon_id also means general; do not require a selection for future
custom categories. Each subcategory owns its selection; no runtime parent-icon
inheritance or category-name-based rendering. Category icon changes will affect
all its displayed historical operations.

Assign initial icons once during v1 migration, fresh creation, and conversion.
Add database/seeds/002_category_icon_defaults.json with public default category
paths mapped to catalog codes. Derive paths from the existing public starter
catalog, never personal records or IDs. Use one mapping resource in both Swift
and Python. Use family icons for the public defaults, with more specific entries
such as Food/Groceries -> groceries, Food/Coffee -> coffee,
Education/Books -> books, and Public transport -> transport.

Match exact, unambiguous full paths, not bare names or numeric IDs. Duplicate,
renamed, or unrecognized paths remain NULL/general rather than guessing. Imported
text and IDs remain unchanged. A user-renamed category keeps its persisted icon;
this bootstrap mapping never runs on normal v2 opening. Future category creation
uses the picker or NULL and does not rerun bootstrap mapping.

### Schema Compatibility and File Lifecycle

The pre-feature validator accepted only version 1 and compared its canonical schema.
Do not edit 001_initial.sql to make existing files appear invalid. Add a versioned
DatabaseMigrator and build expected schemas by applying the exact ordered SQL to
an in-memory reference database. Preserve strict constraints/triggers checks for
both v1 and v2; do not replace them with table-existence checks. Unknown newer
versions remain unsupported.

Initial creation/reset: execute v1 schema, existing defaults, v2 migration, and
initial icon assignments against a fresh staged database, then validate as v2.

Existing working v1: first recover any interrupted replacement. Validate v1,
produce a consistent staged SQLite backup on the serial worker, close the source
handle, migrate the candidate, fully validate v2, then publish through the existing
replacement/recovery engine. Preserve the prior v1 file until success; interruption
or migration failure leaves the old data recoverable. Recover a prior v1 file
using its own validator, not the v2 validator. On failure show retry/recovery UI;
never reset automatically. Ordinary v2 opens retain the existing fast check.

Imported/restored v1: validate the staged original as v1 before migration, migrate
only that copy, validate v2, then use normal safe replacement. Apply this pipeline
also to unavailable-database recovery. The selected source stays untouched. Import
of v2 skips migration and bootstrap assignments, preserving chosen icons.

Export and automatic snapshots use current v2 and reopen independently. Retain
existing v1 automatic backup files and their retention behavior; detect and
validate supported versions when checking an existing daily backup. A usable v1
backup remains restorable through the staged migration path. Do not rewrite old
backups or weaken corruption checks. Older v1-only app builds cannot open v2;
retain a separate v1 source/backup, with no destructive downgrade SQL.

Update tools/convert_mmex.py to apply the same v2 SQL and public icon assignments
after mapping source data. Extend its expected target rows/report version and
validation to include icon_id/catalog values. Preserve its no-overwrite and source
preservation guarantees. Test new converted output in the app; do not overwrite
or reconvert the user's existing private files during implementation verification.

### Query, Financial, and State Ownership

Add Models/HistoryPage.swift for typed row projections, account summary, page,
and cursor values. Keep source/destination amounts, fee ownership, native
currencies, category identity, notes, and occurrence time explicit. Avoid an
independently persisted financial model or a second SQLite connection in views.

Add Data/HistoryRead.swift behind DatabaseLifecycle/DatabaseStore. Initial load
reads the summary and first page in one coherent read transaction on the existing
serial worker. Reuse BalanceCalculator, CurrencyConverter, MoneyPresentation, and
local-date rules. Add an account-scoped summary read so opening one account does
not map/render every account's complete Home presentation. Query its relevant
history once for complete balance/month totals; no query per visible row and no
financial SQL SUM/cast over decimal TEXT.

History uses keyset pagination with an initial implementation page size of 50
plus one look-ahead row. Query both account_id and to_account_id using the new
indexes. Source and destination branches are disjoint for a valid transfer;
UNION ALL, order by date DESC, id DESC, and limit the combined result. Apply the
cursor predicate to each branch: date < cursor_date OR
(date = cursor_date AND id < cursor_id). Bind all parameters. Check the actual
query plan; do not assume indexes alone prove a bounded scan. Join needed category,
icon, counterparty, and currency metadata in the bounded query.

Add Features/Transactions/History/HistoryState.swift with account ID, generation,
request identity, loaded rows, cursor, summary, and separate initial/page errors.
Deduplicate concurrent next-page requests, cancel or reject obsolete results, and
merge day groups across page boundaries without duplicate headers or records.
Refresh restarts cursor and replaces results coherently. Reload on foreground,
local month rollover, display currency change, and dataset replacement. Read-only
history has no financial writes yet; future writes must invalidate its pages and
summary together rather than patching local totals.

Initial read failure shows Retry without false empty/zero data. A later-page
failure retains loaded rows and offers a footer retry. Dataset replacement clears
old account destinations through the existing generation ownership. An unavailable
ledger must not block tabs/Settings or import/reset recovery.

Add AccountHistoryView.swift, AccountSummaryView.swift, and a reusable
TransactionRowView.swift under Features/Transactions/History. Add a small
CategoryIconView.swift there (move to a shared folder only when another real
consumer exists). HomeAccountView remains presentation; HomeView wraps account
rows in native navigation controls and passes the selected ID plus generation.
Do not change AllHistoryView behavior in this checkpoint.

### Implementation Sequence

Complete and verify migration compatibility before exposing the new screen.
Then implement/test history reads, state, UI, and Home navigation. Finish with
synthetic runtime checks and documentation. No product questions block this plan;
page size, file names, and icon mapping are implementation choices. Exact symbols
and runtime query plans still require SDK/SQLite verification.

## Database Changes

Implemented resource: database/migrations/002_category_icons_and_history.sql.
The migration runner validates application_id and source version 1, enables
foreign keys before the transaction, and executes the following body in one
checked SQLite transaction. The app and converter execute the resource through their migration runners.

```sql
CREATE TABLE category_icons (
    id INTEGER PRIMARY KEY,
    code TEXT NOT NULL UNIQUE CHECK (length(code) > 0),
    name TEXT NOT NULL CHECK (length(name) > 0),
    system_name TEXT NOT NULL CHECK (length(system_name) > 0)
);

INSERT INTO category_icons(id, code, name, system_name) VALUES
    (1, 'general', 'General', 'square.grid.2x2'),
    (2, 'bills', 'Bills', 'doc.text'),
    (3, 'food', 'Food', 'fork.knife'),
    (4, 'groceries', 'Groceries', 'cart'),
    (5, 'leisure', 'Leisure', 'film'),
    (6, 'automobile', 'Automobile', 'car'),
    (7, 'education', 'Education', 'graduationcap'),
    (8, 'home', 'Home', 'house'),
    (9, 'health', 'Healthcare', 'cross.case'),
    (10, 'insurance', 'Insurance', 'shield'),
    (11, 'travel', 'Travel', 'airplane'),
    (12, 'taxes', 'Taxes', 'doc.plaintext'),
    (13, 'gifts', 'Gifts', 'gift'),
    (14, 'income', 'Income', 'banknote'),
    (15, 'transport', 'Public transport', 'tram'),
    (16, 'coffee', 'Coffee', 'cup.and.saucer'),
    (17, 'books', 'Books', 'book');

ALTER TABLE categories ADD COLUMN icon_id INTEGER
    REFERENCES category_icons(id) ON DELETE RESTRICT;
CREATE INDEX categories_icon_idx ON categories(icon_id);

DROP INDEX transactions_all_history_idx;
DROP INDEX transactions_source_history_idx;
DROP INDEX transactions_destination_history_idx;
CREATE INDEX transactions_all_history_idx
    ON transactions(date DESC, id DESC);
CREATE INDEX transactions_source_history_idx
    ON transactions(account_id, date DESC, id DESC);
CREATE INDEX transactions_destination_history_idx
    ON transactions(to_account_id, date DESC, id DESC);
```

Next, inside the same transaction, resolve the shared default-path mapping to
actual category IDs and catalog IDs. Execute this bound statement only for
unambiguous matches; all other rows retain NULL:

```sql
UPDATE categories SET icon_id = ? WHERE id = ? AND icon_id IS NULL;
```

Finally, after assignments and before committing:

```sql
PRAGMA user_version = 2;
```

Do not change application_id. No existing financial row/field is modified. New
icons/default mapping are bundled through the existing external SQL resource
references in the Xcode target, including the JSON mapping. Fresh creation and
converter output execute the same schema sequence; there is no parallel edited
v2 schema definition. Persist/sync/reopen the migrated candidate and validate its
schema, FK integrity, data domains, and financial parity before replacement.

No downgrade script is planned. Before publication, rollback discards candidate
changes. After publication, recovery uses the preserved v1 file or an independent
backup through the safe replacement path, not ad hoc DROP COLUMN operations.

## Tasks

- [x] Inspect current v1 schema, validator, lifecycle, converter, and screen decisions.
- [x] Record approved layout, date order, currency display, and category icon rules.
- [x] Implement version-aware resources/validation and the v1-to-v2 migration.
  - [x] Add canonical v2 SQL and shared public default-path mapping; verify symbols.
  - [x] Include resources in the app target and make their bundle presence testable.
  - [x] Route fresh creation/reset and existing-v1 upgrade through the staged flow.
  - [x] Upgrade imported/restored copies, including unavailable-ledger recovery.
  - [x] Preserve v1 backup restoration and validate existing daily backup versions.
  - [x] Update converter output/version/mapping validation and synthetic tests.
  - [x] Verify migration parity, rejection paths, interruption recovery, and reopen.
- [x] Implement account-scoped summary and keyset history reads.
  - [x] Map ordinary, source-transfer, destination-transfer, and fee metadata.
  - [x] Reuse exact finance rules and independent optional balance conversion.
  - [x] Check query plans and page boundary behavior on a large synthetic ledger.
- [x] Implement HistoryState and stale request/page protection.
  - [x] Separate initial and page errors; retain rows after page failure.
  - [x] Handle refresh, currency changes, foreground/month changes, and replacement.
- [ ] Implement summary, date groups, reusable rows/icons, and Home navigation.
  - [x] Preserve all-time history and separately labeled current-month summary.
  - [x] Handle empty history, inactive categories, missing icons/rates, and errors.
  - [ ] Finish final visual checks for long amounts/names and maximum Dynamic Type.
  - [x] Keep editor/delete/plus controls hidden and All unchanged.
- [ ] Verify storage/finance/state tests, converter tests, build, and Simulator flows.
  - [x] Test same-time IDs, midnight/month boundaries, and equal-date page splits.
  - [x] Test both transfer directions, same/different currencies, zero/nonzero fees,
    source/receiver fee ownership, and zero-value operations.
  - [x] Test summary totals independent of paging and unchanged after icon migration.
  - [x] Test NULL/unknown symbols, duplicate names/paths, renamed/custom categories,
    and stable icon assignments across v2 reopen/export/import.
  - [x] Test import/reset during pending reads and unavailable-database navigation.
  - [x] Reopen v2 exports and restore v1/v2 backups without changing source files.
  - [ ] Finish manual refresh and page-error retry checks; navigation and scrolling passed.
- [x] Update current status/specifications and record actual verification/limitations.

## Verification Results

- The complete iOS 27 Simulator suite passed 73 test functions with zero failures
  after the final application changes. A later focused run passed all 8 history test functions, including assertions
  for v2 reimport, empty-account summaries, display-currency changes, and a reset
  concurrent with a read.
- All 22 synthetic converter tests passed. The app built successfully and bundled
  both new resources. All 17 catalog SF Symbols resolved in the installed SDK.
- Migration tests cover all six durable replacement interruption boundaries,
  failed migration preservation, ambiguous defaults, legacy imports/restoration,
  old daily backups, and persisted category icon choices.
- Finance/state tests cover complete summaries independent of pages, both transfer
  sides and fee ownership, missing conversion, descending ties, month boundaries,
  merged day groups, and a failed page followed by a successful retry.
- SQLite query-plan checks use both account history indexes without a transactions
  table scan. A separate host SQLite check returned 51 rows from 100,000 synthetic
  operations in 0.01901 seconds. This is a Mac query measurement, not iPhone timing.
- Simulator navigation Home -> account -> Back and scrolling into older pages
  passed on an existing imported ledger. Native balances/month summaries and
  transfer details were visually inspected. A read-only parity comparison found
  all pre-existing financial fields, IDs, dates, settings, and category text
  unchanged after upgrade; the original private source remains v1 and untouched.
- Repeated launches became blank/unresponsive, including a launch-helper
  timeout after a data-preserving Simulator reboot. A later normal launch and
  screenshot confirmed the final summary-column adjustment. Maximum text size
  applied on Home after relaunch, but remote automation then timed out and
  scrolling did not reach history reliably. History maximum-Dynamic-Type checks
  and manual refresh/page retry remain pending above. The
  plan stays active until they pass. No physical-device verification was done.
