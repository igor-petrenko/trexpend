# Home Dashboard

## Purpose

Replace the database-status placeholder with a useful monthly overview and native
account balances, before transaction editing is introduced.

## Goal

Implement approved concept B with monthly income, expenses, and their difference
as the primary content. Keep combined balance secondary, group open accounts by
type, and display monthly native totals below each account balance. Preserve the
existing native tab bar and all database-unavailable recovery workflows.

## Scope

Implementation authorized on 2026-10-18. Include Home reads/calculations,
formatting, loading/error states, refresh, and display-currency selection in
Settings from the previously proposed checkpoint. Account history and editor are
later stages. The create button is hidden until the editor exists, as confirmed by the user.
Its eventual target is 64 by 64 points, with bottom scroll clearance.
No schema changes, charts, rate downloads, or account management.

## Implementation Approach

### Approved Presentation

- No large Home title. Put the current month/year in a compact heading inside the
  income/expense summary, alongside the display currency code.
- Show income and expenses prominently, followed by Difference = income - expense.
  Difference is monthly cash flow, not spendable balance or a credit limit.
- Show total balance as a smaller secondary row. Exclude closed accounts there.
- Group open accounts by Checking, Credit Cards, Cash, Deposits. No grouping menu.
  Favorite marks are yellow; do not duplicate favorite accounts in another group.
- Each account row has a type icon, account name, optional bank subtitle, native
  balance, and smaller income/expense below the balance. Use diagonal directional
  arrows with green income and red expense; do not repeat the month per row.
- Hide account period figures only if there was no activity affecting it that
  month. With one-sided activity, show zero on the other side. A transfer-only
  account has activity but principal is excluded, so figures may both be zero.
  Transfer fees count as expenses on their charged account.
- Keep native system tabs. Reserve sufficient bottom scroll padding for a future
  64-point create button without covering the last account.
- Rows become navigation controls when account history exists. Do not show inert
  disclosure controls that imply a working destination.

### Data Flow and Files

Add Models/HomeSnapshot.swift for typed account rows, type groups, and independent
optional converted figures. Add Data/HomeRead.swift for SQL mapping and coherent
aggregation on the existing serial worker. DatabaseLifecycle exposes a generation-
guarded Home read in a SQLite read transaction; DatabaseStore supplies async access.
Read history once for all balances, not once per account. Accumulate account and
global month totals together. Keep SQL SUM away from decimal TEXT. Native account
balance calculations remain exact; valuation uses the existing conversion policy.

Add Features/Home/HomeState.swift for loading/errors, request identity, and stale
result rejection. HomeView and focused subviews own layout only. Add a shared
Decimal-backed money formatter without Double conversion. Group/sort accounts
predictably using type, favorite within type, localized name, and ID tie-breaker;
never write a custom sort order to the database.

Reload on database generation/display currency changes, foreground activation,
month rollover, retry, and pull-to-refresh. Capture the relevant month once per
query. Errors in conversion must not hide native rows or fabricate zero/partial
aggregate totals. Income, expense, difference, and total balance may independently
be unavailable when required rates are missing. Zero cash flow requires no rate.

Add a display-currency picker in Settings using the currency catalog. Save through
DatabaseStore and reload typed settings/session after commit. Preserve other
settings and use generation checks. No rate changes or stored-money conversions.

### Verification

Use synthetic accounts across all types/currencies and closed status. Check
negative balances, initial balances, both transfer directions and fee accounts,
month boundaries, no activity, one-sided activity, missing rates, difference,
replacement/currency changes, stale results, long names and large text. Verify
native controls and scrolling in Simulator where tools permit.

## Database Changes

None. Reuse v1 schema and app_settings.display_currency_id. Keep current_balance
unused and NULL. Preference updates use a bound UPDATE in one transaction.

## Tasks

- [x] Record approved layout and calculation rules.
- [x] Settle create-button availability for this checkpoint.
- [x] Implement coherent Home reads, accounting, and typed mapping.
- [x] Implement HomeState refresh and stale-result protection.
- [x] Implement Decimal amount formatting and summary/account components.
- [x] Implement display-currency picker, persistence, and refresh.
- [x] Verify financial cases, storage, UI states, build, and Simulator layout.
- [x] Update specifications and record actual verification.

## Verification Results

Implemented and verified on 2026-10-18. Two final iOS 27 Simulator test runs
passed all 65 test functions with zero failures. Seven Home-focused functions
cover native balances, monthly fees and closed-account activity, period boundaries,
missing rates, independent converted totals, currency persistence, stale dataset
rejection, reload after reset/currency changes, and exact large Decimal formatting.

Inspected Simulator captures for a populated synthetic ledger, empty ledger,
missing rates, long names, and maximum accessibility text size. Exercised bottom
scroll clearance and Settings -> currency picker -> search USD -> select -> Home;
the summary changed to USD while native account balances remained unchanged.
All UI fixtures were synthetic and the original simulator ledger was restored.
Early blank launch frames reflected delayed Simulator rendering and were excluded
from visual acceptance. Physical-device layout/performance is not verified.

SQL schema and monetary data representation remain unchanged. No editor/history
navigation is exposed yet. The plus action is hidden as approved. The native tab
bar is retained. Git diff whitespace checks and authored-text ASCII checks passed.

## Layout Follow-up (2026-10-18)

The total balance now has a compact background card with an emphasized amount.
Account rows vertically center identity, icon, and figures. Period figures receive
layout priority and prefer a horizontal line; genuinely wide figures may still
stack, aligned to the trailing edge. Accessibility text retains the separate
vertical layout. Credit Cards precede Checking without changing stored type IDs.
The existing ordering assertion was updated; all 65 app tests passed again.
Simulator inspection on the imported ledger confirmed the compact total card,
credit-card-first order, centered inactive/no-bank rows, and horizontal monthly
figures for the previously wrapping credit-card example.
