# Financial Behavior

## Status

Confirmed rules with implemented pure Swift financial/date foundations. SQLite
queries, editor wiring, and financial UI are not implemented yet.

## Balances

Account balance comes from its opening balance and eligible transaction history.
Income increases balance; expenses decrease it. A transfer decreases the source
by its actual source amount and increases the destination by its actual received
amount. The persisted baseline field is named `initial_balance`.

Calculate balances on demand from initial_balance and complete eligible history.
The nullable accounts.current_balance field is reserved, remains NULL, and is not
read or maintained by the initial version. Perform exact calculations outside
view rendering and off the UI path. Recalculate affected results after commits;
consider persisted derived values only if measured performance requires them.

Account open_date conceptually identifies the starting point for initial_balance
but is informational; it does not filter retained transactions. For a balance
through a selected date, add eligible history through that date. exp_date and
close_date do not change historical financial contributions or trigger automatic
closure. See the account design specification for date and future-report details.

Home combined balance includes only open accounts. Closed accounts retain their
complete history and historical balance semantics. Their existing transactions
remain editable; a future dedicated workflow will permit omitted backdated entries.
Account closure is not deletion and must not erase either side of a transfer.

Transaction status is omitted in the initial schema. The audited source has no
deleted markers or future accounting dates; validate this again on conversion input.
New and edited transactions may use today or any earlier date; future dates are
not allowed. Imported exceptions require an explicit conversion decision. The UI label "current balance" must have a precise date/status policy.

## Calendar-Month Summaries

Home monthly income and expenses include eligible transactions from all accounts,
including closed accounts. Account closure must not remove historical activity
from period totals. Apply the same rule to future annual and custom-date-range
reports; those report screens remain deferred. Current Home combined balance
uses a separate open-account filter, not the period-summary account scope.

Use saved primary local transaction calendar dates for the current month; do not
convert them to the current device timezone. The auxiliary offset-aware occurrence
timestamp is reserved and not used for current summaries or accounting boundaries.
Use an inclusive first day
and exclusive first day of the next month. Refresh when the month changes.
Income/expense totals exclude transfers between owned accounts, including transfers
to a personal credit-card account. Transfer fees count as expenses on their charged account; transfer principal
excludes the separately recorded fee. No separate fee category is stored.

A transfer can have different actual source/destination amounts. Its converted
contribution to total wealth may differ because saved valuation rates need not
match its execution rate; that difference is not a monthly income/expense entry.

## Transfers

A transfer is one logical editable operation. Account histories project its
relevant side; All history proposes one combined row. Updating or deleting it
must affect both account balances within the same commit.

Source and destination accounts must differ. Do not require equal principal
amounts for same-currency transfers. The editor hides the receiver amount for
same-currency transfers; exact draft synchronization is specified with the editor.
Principal amounts exclude fee, which defaults to the source account even at zero.

Never recalculate stored transfer amounts when display rates change.

## Currency Conversion

Use imported coefficients for first-version valuation. Display-currency selection
affects calculated presentation, not stored transaction amounts or account currency.
Use one reference coefficient per currency pair, without separate buy/sell rates
in the initial version. Apply the same coefficient snapshot to a dashboard calculation.
Use these coefficients to suggest a new cross-currency transfer destination amount;
allow manual correction and persist both actual chosen amounts. Fees are separate.
Rate updates never modify saved transaction/transfer amounts. Proposed draft
behavior preserves manual overrides and does not refresh old records automatically.

Use explicit exchange_rates.from_currency_id/to_currency_id direction. Direct
conversion multiplies by rate, inverse conversion divides, and common-base cross
conversion follows two directed/inverted edges. Identity conversion needs no rate.

First-version monthly conversion uses the same saved coefficients as
current balances, not historical rates on each transaction date. Clearly document
this valuation basis. Detect missing, invalid, or zero coefficients; present
unavailable conversion rather than treating it as zero or assuming parity.

Sum converted amounts at available Decimal precision before rounding the displayed
aggregate; the user confirmed final-only rounding. Individual displayed amounts may therefore differ slightly from their
summed rounded labels. Monetary totals use the display currency precision and nearest rounding
with halfway cases rounded away from zero.

## Amount Input and Storage

Accept one point or comma as the decimal separator and trim surrounding whitespace.
Reject grouping separators, mixed separators, exponent notation, and incomplete
input on validation. For example, 1234,56 is valid; 1 234,56 and 1,234.56 are not. Invalid and out-of-range input must produce an error. Monetary amounts
and opening balances are stored as canonical decimal TEXT at their currency
precision, defined by currencies.decimal_places. Extra input digits may be rounded before saving; present the
normalized result. Use nearest rounding to the relevant currency precision, with halfway
cases rounded away from zero. Zero amounts, including values rounded to zero, are allowed. Apply the v1 Decimal
range and exact representability checks; invalid or empty input must not become zero. Rate TEXT has no fixed fractional
scale; validate its representability for finite-precision Decimal arithmetic.

Each transfer amount follows its own account currency precision. Fee precision
follows the charged account; converted totals follow the display currency. Retain
intermediate Decimal precision and validate arithmetic errors, representability,
and overflow rather than assuming unlimited precision for crypto amounts.

Transaction amounts are nonnegative; transaction type determines their contribution
to balances. Opening and current account balances may be negative, including
credit-card debt. The audited source has no negative transaction amounts; unexpected negatives
in changed conversion input require review rather than silent reinterpretation.
Display currency alongside account amounts; changing that label never converts
what the user typed. Account changes update the currency and require revalidation.

Use Foundation.Decimal arithmetic and direct string decoding/encoding.
Retain intermediate precision and rounding final saved amounts or displayed
aggregates, rather than every arithmetic step. Offline conversion must define
source floating-point normalization, currency-specific rounding, and reconciliation.
Report any changed source amounts privately. Future representation changes require
a migration plan.

## Preservation

During offline conversion, migrate the agreed source fields and relationships.
Keep the original file privately; source features may be omitted only through
explicit field-mapping decisions. Preserve migrated fields outside the editor,
on normal updates. Tags and payees are explicitly omitted from the initial
conversion under the user decision.
For deletion, inspect dependent records and delete only related data that must be
removed; no dangling links or broad category/account deletions.
If a source record cannot be represented safely, stop or report the unresolved
conversion case before accepting the migrated dataset; do not silently drop it.

## Verification Requirements

Use synthetic fixtures for opening balances, income/expense, month boundaries,
transfers in both currencies, status eligibility, conversion errors, precision,
failed commits, and save/delete reload behavior. Compare imported balances privately
against the original application's semantics before declaring financial parity.

## Implemented Foundation Boundaries

MoneyCodec validates canonical stored text without silently rounding it. New input
is rounded to currency precision before encoding. Currency precision is 0 through
18, numeric values have at most 38 normalized significant digits and normalized
exponent -128 through 127, and Foundation.Decimal must represent storage exactly.
Checked add/subtract/multiply fail on precision loss or range errors. Division
allows a recurring quotient at Foundation precision, but not underflow, overflow,
or division by zero. There is no unlimited-precision or bank-execution guarantee.

LocalDateTime stores validated calendar components, not a timezone-dependent
instant. Fresh occurrence offsets use the actual instant; explicit historical
clock selections use the supplied device zone on that date. Ambiguous selections
use the first occurrence; nonexistent local times fail instead of shifting date.
Unedited occurrence fields, including a legacy NULL auxiliary value, are preserved.
TransactionDateRules also provides UTC technical timestamp encoding.

BalanceCalculator accepts complete accounting inputs, a supplied period/cutoff,
and distinct Home/period scopes. It does not read current_balance or a page of UI
rows. CurrencyConverter consumes an immutable rate snapshot. These components do
not open SQLite or save records; later storage/editor work must call these rules.

## Valuation Precision

Persisted amounts and native account arithmetic retain strict exact Decimal
validation. Currency valuation uses finite Foundation Decimal results and accepts
loss of the least significant intermediate digits after recurring division or
aggregate addition. Overflow, underflow, division by zero, and NaN remain errors.
Do not apply stored-number digit limits to a transient quotient. Round to the
display currency precision only after aggregation; saved amounts are unchanged.
