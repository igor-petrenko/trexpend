# All Transactions History

## Purpose

Replace the All tab placeholder with a read-only history across every account,
using the established history presentation and shared statistics card.

## Goal

- Show every persisted transaction once, including closed-account history.
- Order days and operations by stored local date/time descending, then ID descending.
- Load bounded pages while keeping complete monthly statistics independent of paging.
- Identify ordinary transaction accounts and currencies without crowding the amount.
- Show transfers as one taller card with distinct source and destination sections.
- Preserve account-history presentation, financial rules, and database recovery access.

## Scope

Implementation authorized by the user on 2026-10-28.

Include global reads/models/state, All screen, account/currency row context,
stacked transfer presentation, shared statistics, RootView wiring, focused tests,
and documentation. Reuse native tabs and existing financial/presentation helpers.

Exclude filter controls/logic, search, editing, creation/deletion, account management,
new schema fields, dependencies, and changes to account-history transfer presentation.
Keep space conceptually available to the right of Transactions for future controls;
do not display an inactive filter or plus button.

## Implementation Approach

### Screen and Statistics

- Match account history: a scrolling statistics card, Transactions heading, day
  groups, lazy rows, and existing bottom clearance above the native tab bar.
- Do not add an oversized All navigation title above the card. Use a heading row
  with a flexible trailing region so a future filter button fits naturally.
- Open with all dates. The card explicitly labels the current calendar month;
  that month does not filter the transaction list.
- Use HomeSummaryView/StatisticsSummaryView and the same coherent aggregate values
  as Home: combined balance of open accounts; monthly income/expenses including
  closed-account activity. Transfer principal is excluded; fees count as expenses.
- Use saved display currency for the card, equal centered metrics, and the
  conditional difference column. Missing conversion never becomes a false zero.
- Later filters must supply one consistent selection to the list and statistics.
  Period semantics and filter UI remain a separate feature, with no speculative
  filter framework or persisted preferences added now.

### Ordinary Transaction Rows

- Reuse the ordinary row's three-column presentation with an optional All context.
- In the middle column, put a small secondary account-name line above category.
  Category/time remain the main identity; notes follow below as secondary text.
- Put the account currency code above its native signed amount in the right column,
  using the same small secondary style as the summary currency code.
- Align the currency code with account name, and the amount with the primary
  category/time block. Keep the icon aligned to that primary block.
- Income is green and expense red. Amounts retain width priority and never move
  below the identity. Central lines truncate with an ellipsis; no name/note wraps.
- Do not add display-currency equivalents to individual transactions.
- Account history omits the new account/currency header as it does today.

### Transfers: One Card, Two Sections

The user approved stacked source and destination sections instead of an inline
source-to-destination account-name chain.

- Keep one stable transaction ID/card. Never create separate income/expense rows.
- Use one neutral transfer icon in the first column, centered vertically across
  the complete two-section card. This intentionally differs from ordinary rows.
- The middle and right columns contain a source section on top and a destination
  section below, separated by a subtle divider that does not cross the icon.
- Each section identifies direction (From/To) and account name, then shows the
  stored category and time using the ordinary row typography. Display that account's
  currency code at the top right. Use the same transaction time for both sections;
  there is no separate receipt timestamp in the database.
- If currency IDs and exact stored amounts match, show one unsigned, neutral
  amount beside the source section; the destination section has no second amount.
- If either currency or amount differs, show both actual native amounts, each
  aligned with its own section: negative/red for source and positive/green for
  destination. Do not infer the received amount from current exchange rates.
- Compare exact Decimal amounts and currency IDs, not formatted strings or rounded
  conversion results. Different currencies always show two amounts, even when
  their numeric values are equal. Same-currency unequal amounts also show both.
- Show notes once, below the destination details in the middle column. Show a
  nonzero fee once with its explicit currency and charged account. Do not repeat
  notes or fees for each section, or fold a fee into the displayed principal.
- Keep central lines truncated and monetary figures complete. Test long names,
  differing amount widths, zero values, both fee owners, and accessibility sizes.

### Data and State

- Add Models/AllHistoryPage.swift with global cursor/page/snapshot and row context
  containing source/destination IDs, names, currencies, and actual amounts.
  Keep account-scoped HistoryCursor semantics intact; do not use a fake account ID
  to represent the global query.
- Add Data/AllHistoryRead.swift behind DatabaseLifecycle/DatabaseStore. Reads run
  on the existing serial worker, without a view-owned connection.
- Initial load obtains complete Home-compatible statistics and the first global
  page inside one coherent read transaction. Reuse existing aggregate computation;
  do not scan the entire ledger again for a separate All statistics calculation.
  Reusing HomeRead's snapshot initially is acceptable; do not build a new finance
  engine or refactor unrelated Home code for hypothetical optimization.
- Query transactions once in global order, then join/project bounded account,
  currency, category, icon, and fee metadata. Do not concatenate account histories:
  that would duplicate transfers and complicate global ordering.
- Page size: 50 visible operations plus one look-ahead. Use the existing
  transactions_all_history_idx and a bound (date,id) cursor predicate. Inspect
  EXPLAIN QUERY PLAN on a large synthetic ledger; avoid an unbounded sort/scan.
- Add AllHistoryState.swift following HistoryState's request identity, generation,
  display-currency, month, cancellation, and concurrent-page protections. Merge day
  groups across page boundaries; deduplicate IDs and retain loaded rows on page error.
- Refresh restarts pagination coherently. Reload on foreground, month rollover,
  currency changes, and dataset replacement. Retain existing RootView generation
  invalidation. A later editor must invalidate summaries and rows after writes.
- Initial failure shows Retry without false empty/zero data. Page failure shows
  footer retry while retaining records. Empty history still shows the real summary
  (including any opening balances). An unavailable database never blocks Settings.

### Components and Wiring

- Replace AllHistoryView(session:) with AllHistoryView(dependencies:) in RootView.
- Reuse HistoryDay/date formatting and ordinary row/icon presentation where practical;
  extract a small shared helper only for actual shared code.
- Add an optional account/currency context to TransactionRowView, defaulting to
  current account-history behavior. Add AllTransferRowView.swift for the genuinely
  different two-section transfer layout instead of complicating that ordinary row.
- Reuse summary components without changing Home totals or native account rows.
- Do not add a generic query/repository/filter abstraction for this single screen.

## Database Changes

None. Existing schema v2, relationships, and global descending index are sufficient.
No migration, seed rewrite, or personal-database conversion is required.

## Tasks

- [x] Inspect existing history reads/state/rows, shared summary, and RootView wiring.
- [x] Record approved ordinary-row context and stacked transfer behavior.
- [x] Implement typed global pages/cursor and complete aggregate snapshot.
  - [x] Add account/currency metadata and exact transfer display selection.
  - [x] Add serialized lifecycle/store APIs and coherent initial reads.
  - [x] Verify indexed pagination without duplicate transfer records.
- [x] Implement All state and reload/error behavior.
  - [x] Protect against stale pages, concurrent requests, and replacement/currency changes.
  - [x] Merge dates across pages and retain data during page-error retry.
- [x] Implement All screen, ordinary context, stacked transfers, and RootView wiring.
  - [x] Reuse the complete monthly card with conditional difference.
  - [x] Preserve account-history row behavior and reserve future filter placement.
  - [x] Handle empty/unavailable states without blocking Settings recovery.
- [x] Verify focused tests, app build, and runtime layouts.
  - [x] Test ordering/ties, date/month boundaries, closed accounts, and page/day splits.
  - [x] Test transfers once only, same/different currencies, equal/unequal/zero amounts,
    both fee owners, and summary totals independent of page count.
  - [x] Test cancellation/replacement, currency changes, page failure, and successful retry.
  - [x] Exercise All navigation, scroll/load-more, refresh, and missing-rate/empty states.
  - [x] Inspect long account/category/notes, large figures, and Dynamic Type layouts.
  - [x] Recheck Home and account history after shared presentation changes.
- [x] Update implemented status, record evidence/limitations, and complete this plan.

## Verification Results

- Full iOS 27 Simulator suite: 78 test functions passed, zero failures/skips.
  After the final accessibility layout adjustment, all 13 focused account/All
  history test functions passed again. App builds reported no warnings/errors.
- The first full run exposed one invalid synthetic fixture: a zero-fee transfer
  omitted its required fee account. The fixture now uses the agreed source-account
  default. No database constraint or production behavior was weakened.
- Global tests cover 125 operations across pages, descending equal-time IDs,
  midnight/month boundaries, closed-account records, transfer uniqueness, complete
  Home-compatible totals, zero/equal/unequal amounts, both fee owners, missing rates,
  replacement, cancellation, currency changes, refresh, initial/page failure and retry.
- A 5,000-operation synthetic ledger confirmed bounded 50-row pages and a cursor
  query using transactions_all_history_idx without a full transactions scan.
- Existing Simulator UI was inspected on Home, All, and account history. Confirmed
  the complete shared summary, ordinary account/currency headers, single-amount
  stacked transfer, preserved account-history rows, and scrolling to older dates.
  Pull-to-refresh was exercised and returned to the loaded list. No Simulator
  reboot or private-ledger modification was needed.
- SwiftUI ImageRenderer ran inside the Simulator test host for synthetic normal and
  maximum-accessibility layouts, long account/category/notes, large native values,
  two-currency transfers with fee, empty state, and missing-rate state. Generated
  temporary images were visually inspected. This caught and fixed text starvation
  beside large amounts: reserve a minimal identity width, permit further amount
  scaling at accessibility sizes, and keep icons within their fixed containers.
- Error/retry, empty/missing-rate branches, and maximum text were checked through
  state tests and isolated component rendering; not every branch was manually
  triggered in the full app. Physical-device layout/performance remains unverified.
- No schema migration or converter changes. Existing private files remain outside
  version control. Documentation paths, English/ASCII content, and diff whitespace
  are checked before completion.

## Transfer Card Revision (2026-10-28)

The user superseded conditional amount visibility: always show both actual amounts,
source negative/red and destination positive/green, including equal and zero values.
Keep the left icon and central sections. Distinguish the inner divider with a small
static transfer-arrow symbol over a subtle accent line. This uses ordinary SwiftUI
shapes/SF Symbols and no timer, observer, animation, or additional database query.
The obsolete amount-visibility projection was removed; tests retain exact actual
amount/fee assertions. The iOS Simulator build and all 5 All-history test functions passed. The equal-
amount transfer was visually checked in the running app with both signed/color
amounts and the overlaid divider symbol. The Simulator was not rebooted.
