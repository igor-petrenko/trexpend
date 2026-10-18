# Financial and Date Foundations

## Purpose

Provide shared, tested financial and date rules before DatabaseStore and screens
start interpreting stored amounts and calculating summaries independently.

## Goal

Pure Swift/Foundation components decode the v1 money/date contract, calculate
balances and monthly totals, and convert amounts with exact decimal arithmetic.
Focused synthetic tests cover agreed rules and failure paths. The shell remains
buildable and runnable; no new financial UI or persistence is introduced.

Implemented and verified on 2026-10-17 following the
[application shell](application-shell.md). SQLite integration remains a later stage.

## Scope

Include minimal value inputs/results, money parsing and canonical encoding, local
calendar handling, transfer/fee accounting, period summaries, currency conversion,
and a native unit-test target. Exclude SQLite, imports/exports, editor UI/drafts,
rate downloads, historical rates, and persistence or caching of current_balance.

Use the [v1 schema contract](../../specs/database-schema.md) and
[financial behavior](../../specs/financial-behavior.md). Do not reimplement the MMEX
converter in Swift or introduce another schema definition.

## Implementation Approach

### Files and dependencies

Proposed files under apps/ios/Trexpend/Trexpend/:

| File or folder | Planned responsibility |
| --- | --- |
| Finance/MoneyCodec.swift | User-input parsing, canonical storage encoding, currency-scale rounding |
| Models/LocalDateTime.swift | Validated Gregorian local calendar components, stable storage representation |
| Finance/TransactionDateRules.swift | Month boundaries, new-date defaults, auxiliary offset derivation |
| Finance/BalanceCalculator.swift | Account effects, native balances, native period income/expense totals |
| Finance/CurrencyConverter.swift | Directed rate lookup, inversion/base conversion, final precision rules |
| Models/ | Only the currency, account, transaction, and result value types needed by these calculations |

Add a sibling TrexpendTests directory and unit-test target in the existing Xcode
project when implementing tests. Use the installed native test framework; add no
third-party dependency or package. Keep synthetic fixtures inside the test target.
Do not add empty editor, database, or picker components.

Calculators take explicit values, month/date boundaries, and rate snapshots. They
do not read global settings, the current date, a database, or a view. Callers supply
clock/timezone context where needed, making the same inputs reproducible in tests.
Keep worker-facing models/rules independent of MainActor. Verify explicit
isolation declarations against the installed compiler; do not change the target's
default isolation to make a test pass.

### Money contract

- Use Foundation.Decimal and checked decimal operations. Do not parse through
  Double, use SQLite numeric aggregation, or treat failed parsing as zero.
- Separate user-input parsing from strict stored-text decoding. Accept
  a single point or comma decimal separator and surrounding whitespace in input;
  reject grouping separators, mixed separators, empty input, and exponent notation.
  Storage uses a point and canonical currency-specific fractional digits.
- Honor currencies.decimal_places, supported from 0 through 18; do not assume all
  currencies have two digits. Keep rate precision separate from money scale.
- Round saved amounts and final displayed aggregates to nearest, halfway away
  from zero. Canonicalize negative zero. Zero amounts after rounding are valid.
- Reject negative operation/fee amounts; allow signed initial/calculated balances.
- Apply the v1 limits of at most 38 significant digits and normalized exponent
  -128 through 127, and verify actual Foundation.Decimal representability. Fail
  on unsupported values, overflow, and underflow; never silently truncate storage
  values. If a v1-valid value cannot be decoded exactly, document the incompatibility
  before storage integration rather than weakening checks or changing the schema.
- For input beyond the currency scale, apply the agreed rounding deliberately.
  A stored value is already canonical and must not be silently rounded on decode.

### Dates

- Primary date is local Gregorian YYYY-MM-DDTHH:mm:ss. Keep calendar components
  independent of the phone timezone; do not use a UTC instant as its source of truth.
- Validate actual dates, including leap days; text shape alone is insufficient.
- Technical timestamps are UTC. date_with_offset carries the occurrence offset;
  neither changes the primary date or monthly accounting boundaries.
- For a new occurrence, derive the auxiliary field using the supplied device
  timezone and its offset on the chosen date. Reuse a deterministic documented
  policy for repeated/nonexistent local times; expose failures rather than shift
  the primary date silently. No timezone selector or extra UI is required.
- A new draft defaults to now; selecting another calendar date defaults its clock
  to midnight. Existing date fields change only after an explicit date/time edit.
  These are reusable rules tested here and wired to controls in the editor stage.
- Reject future calendar dates at save validation. Month selection uses inclusive
  first-day and exclusive next-month boundaries against primary local components.

The historical MMEX timestamp reconstruction remains converter behavior, already
implemented. These application rules must read its output without shifting dates.

### Accounting and conversion

- Account balance equals initial_balance plus the complete relevant history;
  open_date is informational and must not exclude older retained records.
- Income adds, expense subtracts, transfer subtracts the source amount and adds
  the destination amount. Subtract fee from its selected source or destination.
- Transfer principal never contributes to period income/expense; fee contributes
  to expenses of its charged account, including on a transfer involving closed accounts.
- Preserve unequal same-currency transfer amounts; impose no equality validation.
- Home combined balance filters to open accounts. Period totals include closed
  account activity. Keep those two account scopes distinct in the calculator API.
- Convert using stored directed rates, not an assumed hardcoded CAD formula.
  Support the imported common-base rates and inverse/cross conversion. Identity
  conversion needs no stored rate. Missing/invalid/zero rates are explicit errors,
  never parity or zero money. Use one rate snapshot for each calculation.
- Confirmed valuation policy: sum converted contributions before final rounding;
  round suggested transfer destination amounts to the receiving currency scale.
  Check arithmetic status and document deliberate division precision handling.
- Changing rates affects derived presentation only; calculators never rewrite
  stored transfer amounts. Return results instead of persisting current_balance.

### Focused test matrix

| Area | Required examples |
| --- | --- |
| Parsing/storage | Point/comma input; malformed and empty input; canonical round trip; signed initial balances |
| Precision | Scales 0/2/8/18; halfway rounding in both signs; zero after rounding; overflow/underflow and unsupported values |
| Dates | Leap day; invalid date; primary date unaffected by device zone; December/January and month boundaries |
| Date edits | Explicit context for now and backdated midnight; unchanged occurrence fields on unrelated edits |
| Balances | Negative initial balance; income/expense; both transfer sides; fee on either side; zero/unequal transfer amounts |
| Periods | Closed-account activity included; transfer principal excluded; fee included; complete history independent of visible pages |
| Conversion | Identity/direct/inverse/cross conversion; missing/invalid rates; final aggregate rounding; unchanged actual amounts |

Tests use deliberately invented values and explicit clocks/timezones. Prefer
independent expected financial results to expectations computed by the same helper
under test. Private reconciliation reports are not committed fixture data.

### Confirmed Details and Implementation Choices

The user confirmed single-separator input and final-aggregate rounding before
implementation. Foundation.Decimal division may return a recurring quotient at
its available precision; this is the only arithmetic operation allowed to report
loss of precision. Other arithmetic errors or silent representation loss fail.

Fresh occurrences retain the actual instant's offset, including the second
occurrence of a repeated clock time. Manually selected ambiguous times use the
first occurrence; nonexistent local times fail without shifting the primary date.
Pure models and calculators explicitly opt out of MainActor default isolation.

The compact AccountingValues.swift file contains only accounting inputs and
results. Full display/persistence models and editor validation remain later work.

## Database Changes

None. Consume the existing contract without opening or modifying a database. A
codec incompatibility requires review, not an unplanned schema migration.

## Tasks

- [x] Confirm the proposed input grammar and aggregate-rounding policy.
- [x] Define minimal typed calculator inputs/results and local calendar values.
- [x] Implement money decoding, input parsing, encoding, and checked arithmetic.
- [x] Implement local date, month-boundary, and auxiliary-offset rules.
- [x] Implement balance and period calculations including transfer fees and closed accounts.
- [x] Implement directed-rate conversion and final rounding with explicit failures.
- [x] Add a native test target and synthetic cases covering the test matrix.
- [x] Verify implementation.
  - [x] Run the financial/date unit tests with the installed iOS 27 SDK.
  - [x] Check exact stored-text round trips and amount-range failure behavior.
  - [x] Build the application and confirm the shell still launches in Simulator.
  - [x] Confirm no private fixtures, new dependencies, or database writes were added.
- [x] Update specifications for confirmed details and record verification results.

## Verification Results

Completed on 2026-10-17 with Xcode 27.0 (27A266a) and the iOS 27.0 Simulator SDK.

- The shared Trexpend scheme includes the native Swift Testing TrexpendTests target.
  Test sources belong only to that target, with an explicit application dependency.
- XcodeBuildMCP test_sim: 22 tests passed, zero failed/skipped; the final run had
  no reported compiler warnings. Parameterized cases cover additional inputs.
- Tests cover canonical round trips, scales 0/2/4/8/18, signed halfway rounding,
  zero after rounding, malformed/unsupported values, checked arithmetic failures,
  calendar validation, month boundaries, unchanged occurrence fields, Toronto
  offsets/DST, transfer fees on either side, unequal amounts, closed-account period
  activity, and direct/inverse/common-base conversion with final-only rounding.
- Pure Swift files also passed type checking with MainActor default isolation and
  an explicit local module cache. No unsafe Sendable escape hatch was introduced.
- The app rebuilt and relaunched; Home/All/Settings and larger text were verified
  in Simulator after the financial components were added.
- No dependencies, SQLite code, financial write UI, schema changes, or private
  fixtures were added. The personal conversion files remain outside the app target.
- English/ASCII, documentation links, project plist, and diff checks passed.
