# Trexpend Database Design

## Status

This is the consolidated database design discussion. Confirmed decisions and
remaining future proposals are distinguished below. Canonical v1 SQL and the
offline converter are implemented; application persistence is still pending.
See [v1 schema](database-schema.md) for final technical choices. See [Conversion mapping](mmex-conversion.md) for
the source-field audit and [Settings](user-settings.md) for confirmed settings ownership.

## Confirmed Decisions

- Use a standalone Trexpend SQLite database with lowercase `snake_case` names.
- Do not reproduce the MMEX schema or preserve compatibility inside the app.
- Perform the initial MMEX-to-Trexpend conversion on the computer.
- The app supports only Trexpend replacement import and snapshot export/restore.
- Select which source fields to migrate explicitly; keep the original privately.
- Preserve all selected transaction history and its financial meaning.
- Support date and time. Default a new transaction's date to today, allow any past
  date through a native picker, and reject future dates.
- Follow the agreed open/closed-account and period-summary rules in the other specs.

## Proposed Discussion Order

1. Transaction dates, times, unknown historical time, and timezone meaning.
2. Currency identifiers, precision, exact money storage, and exchange coefficients.
3. Account identity, opening balances, closure, and retained metadata.
4. Transaction type, statuses, categories, notes, payees, and transfer representation.
5. Category hierarchy and tag retention.
6. IDs, constraints, indexes, and schema-version identity.
7. Complete source mapping and conversion verification criteria.

## Candidate Entities

| Entity | Purpose | Decisions still open |
| --- | --- | --- |
| `currencies` | Complete catalog, precision, and retained affixes | Additional legacy formatting metadata treatment |
| `accounts` | Identity, currency, initial balance, status/type, and metadata | Final SQL constraints; future historical reports |
| `account_statuses` | Extensible status reference data | Future status behavior beyond open/closed |
| `account_types` | Account types used for UI labels/grouping | Source-to-target type mapping and default image references |
| `account_images` | Protected built-in images and future custom account images | Exact storage, constraints, and deletion behavior |
| `categories` | Identity, duplicate names, hierarchy, active flag, and favorites | Future inactive-category behavior and conversion constraints |
| `transactions` | One row per income, expense, or transfer, including fees | Final constraints and type reference IDs |
| `exchange_rates` | Current directed coefficients and technical updated_at | Final SQL; external provider selection after conversion |
| `tags` / `transaction_tags` | Excluded from initial schema and conversion | Explicitly omitted by the user; original remains private |
| `app_settings` | Singleton portable settings row, included in snapshots | Final constraints and initial source mapping |
| Schema metadata | Trexpend format/version recognition | Metadata table versus SQLite header pragmas |

Use one transactions row for each logical operation, with account_id/amount
and transfer-only to_account_id/to_amount. No entries ledger is needed initially.
A transaction_types lookup encodes expense 1, income 2, transfer 3 in the
implemented canonical schema. Account and category
relationships use explicit foreign keys.

Do not create tables for unused legacy features merely because MMEX has them.
Do not drop populated fields or relationships without a recorded mapping decision.

## Accounts

### Confirmed Field Decisions

| Field | Meaning and storage | Status |
| --- | --- | --- |
| `id` | INTEGER PRIMARY KEY | Confirmed; preserve ordinary source account IDs and remap the outlier |
| `name` | Account display name, TEXT | Duplicate names allowed; no name-specific validation |
| `currency_id` | Foreign key to `currencies` | Required; changing account currency is not supported |
| `initial_balance` | Signed decimal TEXT at the account currency precision | Required; replaces proposed opening_balance naming |
| `current_balance` | Nullable decimal TEXT, reserved for possible future use | Leave NULL; do not read or populate in the initial version |
| `open_date` | Nullable account opening date, TEXT | New accounts default to today; user may edit |
| `exp_date` | Optional card expiry date, TEXT | Confirmed; informational; does not automatically close the account |
| `close_date` | Optional actual account closure date, TEXT | Set when changing status to closed |
| `status` | Foreign key to `account_statuses.id` | Required; replaces is_closed proposal |
| `account_type` | Foreign key to `account_types.id` | Required |
| `account_number` | Optional arbitrary TEXT, including a partial card number | Confirmed |
| `bank` | Optional bank-name TEXT, entered manually after initial conversion | Confirmed |
| `credit_limit` | Optional monetary decimal TEXT in the account currency | Confirmed; validation range to specify |
| `favorite` | Boolean encoded as INTEGER constrained to 0/1 | Confirmed |
| `image_id` | Nullable foreign key to account_images.id | Confirmed override; NULL uses the account type default |
| `color` | Optional custom account color | Confirmed; NULL uses shared default; #RRGGBB TEXT |
| `notes` | Optional arbitrary account description, TEXT | Confirmed |
| `created_at` | Record-creation timestamp, TEXT | New records use creation time; imported accounts use INITIALDATE as an agreed historical proxy |
| `updated_at` | Technical record-edit timestamp, TEXT | Confirmed; encoding and conversion mapping to specify |

`status` and `account_type` store reference IDs, not free-form labels. The status
reference initially has stable codes `open` and `closed`; the type reference has
`checking`, `credit_card`, `cash`, and `deposit`. The deposit type is confirmed;
interest accrual, maturity rules, and withdrawal restrictions are not implied.
Proposed lookup fields are `id`, unique
`code`, and `name` for UI display. Define source type mapping before conversion.
Future statuses require explicit behavior; adding a lookup row alone does not
establish dashboard or editor eligibility. Hidden-account semantics remain open.

Account names may repeat. Do not add uniqueness, name-format, or non-empty UI
validation without a new requirement. Account currency is selected at creation
and cannot be changed in the current scope, even before transactions exist.

Preserve account numbers as text, including leading zeros. Do not require a full
bank/card number. The initial converter leaves `bank` empty for manual completion;
do not guess a bank from names or source metadata.

Favorite accounts should be marked and placed before other eligible accounts in
the account picker. This ordering does not make closed accounts eligible for new
transactions. A separate favorites group on Home remains a possible later layout.

Website and contact fields are intentionally omitted from the new account schema.
Other source account fields are classified in the conversion mapping.
`credit_limit` is information, not a transaction or an addition to account balance;
spending restrictions or available-credit calculations are not yet specified.

### Account Presentation and Deferred Metadata

Do not add sort_order, group_id, include_in_total, or minimum_balance now.
Ordering/grouping may use account type, bank, and favorites; exact UI ordering
remains to be designed. All open accounts still contribute to the Home total.
Color is optional and shares the default appearance when absent; its UI use is
not yet specified. Use nullable canonical #RRGGBB TEXT. NULL uses the shared UI default color;
the concrete default color is chosen with the interface, not stored per account.

Deposit terms, interest automation, and credit-card billing/statement metadata
are deferred. Do not create their detail tables now. There is no separate cards
table in the current model: a bank-card account represents that individual card.
When a card expires, the user may close its account and create a new one; do not
silently move history or duplicate a carried balance between the two accounts.

For newly created accounts, created_at and updated_at describe record lifecycle
and are separate from editable open_date. Technical UTC timestamp encoding remains a recommendation for final schema review.
For imported accounts, use source INITIALDATE for both open_date and created_at
as requested. This is a historical proxy for created_at, not proof of when the
source record was inserted. Preserve the calendar date; normalization of date-only
values and absent timezone information requires an explicit conversion rule.
Initialize imported updated_at to the same value as created_at. Later account
metadata edits update updated_at; adding or editing transactions does not update
the account metadata timestamp.

Propose UTC TEXT timestamps for new technical created_at and updated_at values,
formatted YYYY-MM-DDTHH:mm:ssZ and rendered in the current device timezone.
Account open_date, exp_date, and close_date remain calendar dates without timezone
conversion. Legacy INITIALDATE is not an instant: choose an explicit assumed
timezone for synthetic midnight before encoding it as UTC. This assumption cannot
recover the source creation time. Transaction occurrence timezone rules remain
a separate decision; do not apply technical timestamp rules to accounting dates.

### Account Images

The account_images table and an account foreign-key reference are confirmed.
Provide default images for checking, credit_card, cash, and deposit. Built-in
images cannot be deleted through the application. Custom image upload and
management are deferred; no image-loading UI is implemented by this specification.

Proposed minimal image fields:

| Field | Purpose |
| --- | --- |
| id | Primary key |
| name | Display name |
| source | Distinguish built_in from custom; final encoding to agree |
| asset_name | Bundled application asset identifier for built-in images |


Use account_types.default_image_id referencing account_images, with nullable
accounts.image_id overriding the type default. This keeps defaults centralized;
changing an account type uses its corresponding default unless an override exists.
A reference identifies an image, not an arbitrary external filesystem path.

Built-in images are bundled image sets in the application Assets.xcassets.
asset_name stores a stable asset identifier, not a filesystem path or image bytes.
The app loads the resource by that identifier. Reference artwork can remain in
design; the application uses its own bundled resources.

Custom-image storage is explicitly undecided: BLOB, managed files, and export
packaging will be compared when implementing that feature. Do not add image_data
or create a file-storage subsystem now. The source/name metadata and exact SQL
constraints remain to be finalized for the initial built-in catalog.

Before enabling custom-image deletion, specify reference handling. Recommend
resetting affected account overrides to the type default in the same transaction;
never delete an account or its history when deleting an image. Image selection
and fallback must handle a missing bundled resource without blocking account use.

### Account Dates and Initial Balance

Use `open_date`, `exp_date`, and `close_date`; do not add a separate
initial-balance date. Use canonical `YYYY-MM-DD` TEXT for these calendar dates.
open_date may be NULL at the schema level. New-account creation automatically
fills today and permits manual editing. For imported accounts, map INITIALDATE
to open_date and created_at. Read-only inspection confirms valid INITIALDATE values for every source account;
validate again against the exact file used when conversion executes.
Do not replace a malformed source date with today silently.

`open_date` describes account opening or creation in the app. The initial balance
is conceptually associated with that starting point. For the initial calculation
model, initial_balance is the baseline before retained transaction history;
open_date is informational and does not exclude earlier retained operations.
A balance through a chosen date adds eligible transactions through that boundary.
Rules for reports before the account's starting point remain a future report topic.

`exp_date` is the optional expiry date of the card represented by this account,
not a required bank-account closure date. Reaching it does not automatically close the
account or change transaction eligibility, balance calculations, or summary scope.
It may be displayed as informational metadata in a future UI. `close_date` records actual closure
when status is changed to closed; status controls current account eligibility.
Neither closure date nor status removes historical operations from period totals.
Reopening closed accounts, custom-image management, and additional statuses are
deferred features; agree their behavior when introducing them.

### Source Account Inspection and Mapping

Read-only inspection of local/init_export_db.mmb confirms valid INITIALDATE values
for every account, all with midnight times. Map their calendar dates to open_date;
use the agreed synthetic timestamp normalization for created_at and updated_at.
The initial balances need no change at two-digit precision when decoded from
the source's decimal representation. Source credit limits are considered incorrect
by the user: intentionally ignore them and initialize every credit_limit to the
canonical monetary TEXT value 0.00. This overrides the earlier preservation proposal. Source numeric
storage includes INTEGER and REAL, so conversion must explicitly normalize it
before exact Decimal calculations and reconcile the resulting balances.

Map source Checking, Credit Card, and Cash types to checking, credit_card, and
cash respectively. Seed deposit even though the inspected accounts do not use it.
Map Open to open and TRUE/FALSE favorites to INTEGER 1/0. Currency references
resolve, including EUR as well as CAD, USD, and UAH; retain every used currency.
All inspected source/destination account references on transactions resolve.

Preserve source account IDs 1 through 10 and map the remaining outlier to 11 after
checking destination uniqueness. Update every retained account reference through
this mapping, including both transfer sides. The exact private outlier ID belongs
in conversion inputs/reporting outside version control. Large source IDs fit
SQLite integers; remapping is a naming/identity choice, not a repair of corruption.

Some operations precede their account INITIALDATE. Preserve them: open_date is
informational and never a lower-bound filter for balance reconstruction.
Account numbers, notes, bank/location, website, and contact/access fields are
empty in the inspected source. Initialize all credit limits to 0.00 under the explicit user decision; do not
copy the populated source limits. Credit limits remain informational and do not
affect balance calculations. Statement/payment dates are populated
in some source accounts but excluded under the agreed deferred-feature scope;
retain the original privately so these can be recovered later.

This checks account-field representability and references, not final end-to-end
conversion parity. Final reconciliation still requires executing the converter and comparing
source and target. Transaction statuses are explicitly omitted, not an open feature.

### Current Balance: Calculated, Not Persisted

Include nullable `current_balance` in the account table, but leave it NULL during
initial conversion and ordinary writes. The initial application does not read it
for balances or summaries and does not maintain a persisted balance cache.

Calculate each native-currency balance from initial_balance and complete eligible
history when needed. Read only required accounting fields and perform Decimal
calculations off the UI path. Dashboard calculations may batch multiple accounts;
they must not depend on the history pages currently displayed.

After a successful transaction write, reload affected balances and summaries.
For changed accounts and transfers, include every affected old and new account.
Conversion verification compares calculated balances against the source; it does
not populate current_balance. Replacement import/restore also derives balances
from initial_balance and history rather than trusting the reserved column.

Measure performance with representative history before changing this approach.
Using current_balance later requires a separate agreed design and implementation
plan for atomic maintenance, reconstruction, and validation of derived values.

## Currencies and Money Discussion

### Currency Fields

Confirmed currency data is the complete catalog, unique code, name, retained
prefix_symbol/suffix_symbol, and decimal_places derived from SCALE. Rate values
are separate. The optional symbol is derived from the nonempty prefix or suffix,
with code available for disambiguation. Do not discard affixes or flatten precision.

The previous open-marked mapping table was stale. Prefix/suffix retention and
SCALE conversion are settled; source rate history is intentionally excluded.
Retain DECIMAL_POINT, GROUP_SEPARATOR, UNIT_NAME, CENT_NAME, and CURRENCY_TYPE
as reference metadata, as confirmed. See the conversion mapping for target names.

### Currency Catalog and Current Rates

Separating currencies from exchange_rates is confirmed. Store only current
valuation coefficients initially; historical exchange-rate reporting and automatic
updates are deferred. Updating a valuation rate must never rewrite transaction
amounts, transfer amounts, or native account balances. Current converted summaries
may change when the selected rate snapshot changes; they are not historical-rate
valuations of the original operations.

The user accepts retaining the legacy EUR coefficient for initial use and tolerates
approximation in converted results. This does not approve altering EUR transaction
amounts. Choosing an initial refreshed rate snapshot remains open.

Read-only inspection finds populated positive BASECONVRATE values for every source
currency, but only USD and UAH differ from 1. Values of 1 for non-base currencies
must not be treated as reliable parity rates. CAD is the base reference. The user confirms
creating rates initially only for the used currencies; do not fabricate rates for
unused catalog rows. CAD-to-CAD conversion is identity without requiring a rate row.

Retaining the complete currency catalog is confirmed. Retaining names/codes
does not require importing placeholder rates or implementing every currency's precision and behavior. Missing rates mean unavailable conversion, never parity.
The catalog includes fiat and crypto entries and display scales beyond two digits;
reference presence is not a promise of support in transaction entry. Remaining reference-formatting metadata is classified in the conversion mapping.

The user confirms first preserving existing used-currency coefficients for
migration reconciliation, then separately assigning a coherent recent valuation
snapshot after conversion, before daily use; choose its source after the initial
migration is complete. This is not an authorization to change the source or
implement network updates. Reference rates may differ from actual bank/card rates;
actual execution is already represented by both saved transfer amounts and fee.

Ukrainian rate sources are preferred, ideally PrivatBank if suitable coverage and
rate semantics are available. Use one reference coefficient per pair initially; separate buy/sell rates are
explicitly deferred. Provider and reference-coefficient selection remain open; bank branding alone does not establish card
execution rates. The documented PrivatBank public API distinguishes cash and
non-cash feeds, with buy/sale fields. Its current non-cash documentation lists
USD and EUR; its archive lists CAD but distinguishes NBU rates from bank rates.
Do not claim documented CAD archive coverage is a CAD card-rate guarantee.

A possible complete reference source is the National Bank of Ukraine, which publishes UAH
rates for CAD, USD, and EUR. Derive CAD coefficients from same-date source data:
CAD per currency = UAH per currency / UAH per CAD; UAH per UAH = 1.
Validate units and publication date before accepting a fetched snapshot. Rate
source/publication date metadata are deferred and not added now.

### Rate Metadata and Remaining Design Details

One reference coefficient is confirmed for initial valuation and transfer estimates;
do not add buy_rate/sell_rate columns or bank-specific rate tables now.
Add only technical updated_at (TEXT) to exchange_rates, recording when the stored
coefficient was written. Set it to conversion/write time on initial migration;
this does not claim the coefficient itself was published at that moment. Do not
add source or rate_date now. Provider metadata and publication-date storage may
be revisited with future rate-update functionality. No historical-rate table is
in scope. Select a provider and refresh rates only after initial conversion and
reconciliation; provider choice does not block creating the new schema.

Propose a unique from_currency_id/to_currency_id pair and require a positive
Decimal-representable rate. The explicit direction is destination units per one
source unit. Use CAD as the common valuation reference without requiring all
pair combinations; do not treat a bank buy/sell pair as reciprocal reference rates.
Exact SQL and provider initialization remain to be finalized.

Do not add favorite to currencies. Currency selection is currently needed for
display-currency settings and future account creation, not routine transaction input.
Cryptocurrency functionality is deferred, even if reference rows are retained.
SCALE mapping is settled. Remaining formatting/type metadata is retained under the confirmed
conversion mapping. Monetary display precision is distinct from rate precision;
exchange-rate TEXT has no two-digit fractional restriction. The user confirms currency-dependent monetary precision from the initial
implementation; this supersedes the earlier global two-digit amount rule.

Preserve prefix_symbol and suffix_symbol for future compact amount formatting.
Use symbols where currency is clear from context; recommend an explicit code when
needed to distinguish currencies sharing a symbol. UI formatting is not restricted
to codes only. Per-currency decimal/group separators and unit names remain separate
source-mapping decisions; approval to preserve affixes does not settle those fields.

Confirmed precision policy: retain every currency's decimal_places, mapping
SCALE = 10^n to n after validation. SCALE is a multiplier, not a literal count of
fractional digits: 100 maps to 2 and 100000000 maps to 8. Validate source SCALE
values before conversion; do not silently map unsupported values to 2.

Apply this precision to initial_balance, credit_limit, transaction amounts, fees,
and native balance displays. The source and destination sides of a transfer use
their own account currency precision; fees use the charged account's precision.
Converted displays use the chosen display currency precision. CAD, USD, UAH, and
EUR continue to use two digits. Exact Decimal calculations and supported-range
validation apply at all precisions, including the retained crypto catalog entry.
This provides amount-precision support now, without blockchain integration,
crypto price feeds, tax lots, or other specialized cryptocurrency functionality.

Do not change decimal_places for a used currency and silently round existing
records. Such a policy change requires an explicit migration/reconciliation plan.
Rates have independent precision and are never rounded to the currency scale.

### Confirmed Input and Balance Rules

- Support point and comma as decimal separators.
- Transaction amounts are nonnegative, including zero after rounding; direction
  is determined by type. Blank or invalid input is not automatically zero.
- Opening and current account balances may be negative.

### Money Storage Decision

Store monetary amounts as canonical decimal TEXT with exactly the number of
fractional digits defined by their currency. Examples: 12.35 or -12.35 for a
two-digit currency, 125 for a zero-digit currency, and 0.00001234 for an
eight-digit currency. Parse and calculate using Foundation.Decimal directly
from strings, not through Double. Use a point in storage regardless of the user's
input separator. Bind values as TEXT and validate format and supported range.

The user rejects REAL storage. SQLite NUMERIC affinity can convert fractional
values to REAL and is not an exact decimal alternative. INTEGER minor-unit
storage is not selected; do not use the proposed `amount_minor` naming.

Round monetary values to their currency precision using nearest rounding, with
exact halfway cases rounded away from zero. For a two-digit currency, `12.344` becomes `12.34`, `12.345`
becomes `12.35`, and `-12.345` becomes `-12.35`. Accepting extra input digits and rounding on save is allowed;
show the normalized value rather than silently hiding what will be persisted.

Propose retaining intermediate Decimal precision during conversion and rounding
only the resulting saved monetary amount or displayed aggregate. Per-step rounding
is not automatically implied by the storage scale. Do not rewrite historical
transaction amounts when display exchange rates change.

Exchange coefficients use decimal TEXT without a fixed fractional-digit limit
in the schema. Preserve their supplied decimal precision; do not apply the
currency-specific money scale. Application Decimal arithmetic still has finite precision
and range, so validate representability and report unsupported values rather
than silently truncating them. This is not an arbitrary-precision arithmetic promise.

Ordinary SQLite SUM, CAST-to-REAL, and arithmetic over decimal TEXT would use
approximate numeric conversion. Perform financial calculations through Decimal.
Lexical TEXT ordering is not numeric amount ordering. Define database constraints,
range limits, source REAL normalization, and reconciliation of rounded imported
amounts before implementation. Zero after rounding is explicitly allowed.

## Categories

Confirmed fields are id (INTEGER PRIMARY KEY), name (TEXT), nullable parent_id
(foreign key to categories.id), is_active (INTEGER boolean), and favorite
(INTEGER boolean). Names may repeat; do not add a unique-name constraint.
Support multiple hierarchy levels and permit transactions to select any node.

The future category-management application logic validates and prevents cycles;
do not add a recursive database trigger for cycle enforcement. Keep ordinary
foreign-key integrity. Offline conversion must separately check source hierarchy
and normalize its root sentinel to NULL so imported data does not bypass validation.

favorite marks frequently selected categories, including nested categories.
The picker places selectable favorite categories at the top with a disambiguating
parent path, so selection does not require expanding their ancestors. The full
category list uses expandable parent/child rows; favorite and tree selections
refer to the same category identity. Parent rows can be selected as well as expanded.
Propose default favorite 0 during conversion where no source flag exists.

Include is_active now, but its long-term role and category-management behavior
remain provisional. The inspected source categories are active; preserve source
ACTIVE as the initial boolean mapping. Do not implement archive/delete management
or invent parent/child inactivity propagation rules before those are agreed.

## Transaction Categories and Optional Source Metadata

Every transaction requires exactly one category_id referencing categories,
including transfers. A parent or child category may be selected directly;
transaction links do not depend on hierarchy depth. New categories are a future
management feature. Editor category defaults are undecided: previous selection
or a configured/default category. On switching to transfer, automatically selecting
the Transfer category is a proposed convenience; the user may override it.
Do not hardcode a category ID from its display name without a mapping decision.
All inspected source transactions have valid category references.

Payee/payer and tags are explicitly excluded from the initial schema and offline
conversion. Do not create payees, tags, or transaction_tags tables for this scope.
Keep the original privately for possible later recovery. TRANSACTIONNUMBER is
also explicitly omitted from the new schema and conversion, including populated
source values.

Source transaction statuses are uniformly R. The user confirms omitting
transaction status and its lookup table from the initial schema and conversion.
Do not introduce reconciliation, approval, or void-state workflows. Account
status remains a separate confirmed field and is not affected by this decision.

### Deferred Transaction Extensions

Do not add title, related_transaction_id, custom transaction color, or transaction
version history to the initial schema. Account color remains a separate confirmed
field; transaction styling initially derives from existing semantic data.

Attachments (photos/documents) and frequent-operation templates are desired future
features, implemented separately when requested. Do not create their placeholder
tables or storage columns now. Links between transactions and audit/version history
are also outside current scope. These decisions do not remove technical updated_at.

The implemented v1 schema specifies field nullability, foreign keys, fixed type
IDs, non-transfer defaults, and timestamp mapping. Future editor-only details
remain in the screen specification; they do not change converter behavior.

## Transfer Fees

Transfer fee amount and its charged account are confirmed. Use fee as nonnegative
monetary TEXT at the charged account currency precision, default zero, and
fee_account_id as a nullable foreign key
to accounts. A nonzero fee requires fee_account_id equal to account_id or
to_account_id. The currency is the charged account currency, not display currency.
Support one fee on one of the two accounts; no third-account or multiple-fee model.

Confirmed accounting convention: amount and to_amount exclude fee. Source impact
is -amount, destination impact is +to_amount, plus an additional -fee on the
selected fee account. Most transfers have zero fee. Do not automatically derive
commission from an exchange difference or create a second expense transaction.
Total-inclusive input is not required by the current request; label the editor
amount fields clearly so the user does not include commission twice.

Count fee as an expense on its charged account using the transfer's saved date,
including account and Home period summaries. Exclude transfer principal from
income/expense. No fee_category_id or fee-category reference is needed. The
transfer retains its single required category. Future reports may identify fees
from transfer rows without storing another category; report grouping is deferred.

Changing either transfer account preserves all entered monetary numbers, including
fee; never convert, clear, or recalculate amounts merely because currency changes.
The editor updates currency labels. Maintain the chosen fee side (source or
receiver), resolving fee_account_id to that side's currently selected account.
For example, replacing the source account while the source pays the fee changes
fee_account_id to the new source but leaves fee unchanged. The database must not
retain a reference to an account that is no longer either side of the transfer.

Save, update, and deletion apply both sides and fee atomically. New transfers
default fee_account_id to the source, including when fee is zero; the user may
select the receiver. Keep the selected side when accounts change. No same-currency
amount equality constraint is allowed. Treatment of a fee larger than the receiver amount remains an editor validation
detail; imported fees are zero.

Initial conversion assigns fee 0.00 to every legacy transfer (all source account
currencies in this dataset use two digits) and sets fee_account_id to the remapped
source account ID, including for zero fee. Never infer or deduct an old fee again: preserve the original
transfer amounts. Expense/income records use zero fee and NULL fee_account_id; transfer-only
receiver fields are NULL.

## Transaction Editing and Deletion

Confirmed: a transfer changed to expense/income keeps the source account selected.
Keep the source amount and shared fields, setting to_account_id
and to_amount to NULL, and resetting fee to zero and fee_account_id to NULL.
This confirmed cleanup applies only on saving the changed draft; opening the
editor or cancelling does not alter persisted data. If a fee was nonzero, the
form must clearly reflect its removal. Do not silently merge it into amount.
This cleanup is confirmed by the user.

Confirmed: for same-currency transfers, show only the source amount field; do not
validate equality between stored principal amounts. Derive the hidden
receiver value from source input for new equal-currency drafts, as confirmed. Existing values
must survive opening/saving without amount changes, including hypothetical unequal
legacy values; the current source has no unequal same-currency transfers. The
hidden-value policy after explicit amount edits to an existing unequal transfer
is an editor detail, not a blocker for this source dataset.

Confirmed: transaction deletion is physical after confirmation, without a deleted
flag. Foreign keys must prevent deleting referenced accounts/categories. Delete
one logical transfer row atomically so both account projections and its fee vanish.
Related child rows, if introduced later, need narrowly defined cleanup rules.

## Transaction Date and Time

### Confirmed Behavior

- Store the transaction date and time together as TEXT, including a time component.
- New drafts default to today's date and the current time; both are editable.
- When the user changes the transaction date, default the time to `00:00:00`.
  The user may then select another time; there is no separate time-precision flag.
- Backdated entries may be saved without knowing the actual time.
- For this initial MMEX conversion, combine TRANSDATE calendar date with
  LASTUPDATEDTIME wall-clock time under the confirmed mapping below. This
  supersedes the earlier midnight-only migration rule. New backdated drafts
  still default to midnight when their date changes; no time-precision flag.
- Within a day, sort by stored time ascending, so midnight entries come first.
  Keep ties stable; do not infer actual chronology from IDs.
- Created/updated timestamps describe record edits, not the operation time.
- Future dates are disallowed. Whether a time later today is allowed remains open.

Show the stored date and time in the editor. Opening an existing transaction or
editing another field must preserve both exactly unless the user explicitly changes
the date or time. Do not apply new-draft defaults merely because the editor appeared.

### Source Occurrence Date Versus Update Timestamp

Read-only source inspection distinguishes TRANSDATE from LASTUPDATEDTIME.
TRANSDATE contains dates or midnight date/time strings. LASTUPDATEDTIME contains
record-write times, with both offset-free seconds and fractional seconds plus
numeric offsets. The Android repository writes this field on insertion and
update; it does not prove occurrence time. The user explicitly accepts using
its clock time as a historical approximation, even for backdated/edited entries.

Confirmed initial conversion:

- Build date from TRANSDATE's calendar date and LASTUPDATEDTIME's local hour,
  minute, and second. When calendar dates match, this is LASTUPDATEDTIME's local
  date/time; when they differ, replace only its date. Normalize primary occurrence
  fields to the agreed whole-second precision, without rounding across boundaries.
- Build date_with_offset from that same combined date/time interpreted in
  America/Toronto. Use the offset applicable to the combined occurrence date,
  not necessarily the offset in LASTUPDATEDTIME for its later update date.
- Add technical updated_at to transactions. Import the complete LASTUPDATEDTIME
  as the update timestamp: explicit offsets define its UTC instant; interpret
  offset-free values in America/Toronto. Preserve supplied fractional seconds in
  this technical field. New writes update it after transaction edits, independently
  of whether the occurrence date changed; both occurrence fields stay unchanged
  on unrelated edits.

The user confirms using the original app only in Toronto, without travel abroad
throughout the recorded period. America/Toronto is therefore the confirmed import
zone for offset-free timestamps, not an unapproved guessed location. Source
creation time is not separately established; the user confirms setting imported
created_at equal to normalized updated_at as an explicit historical proxy.

A read-only conversion feasibility check parsed every row and produced valid
combined calendar values. Explicit update offsets agree with Toronto rules.
One combined time falls in a repeated daylight-saving hour; there are no gap
values. Propose selecting the earlier occurrence for that ambiguous auxiliary
instant and documenting that convention in the converter plan. Primary date and
clock time are unaffected. No conversion or personal-data output was written.

### Two Transaction Date/Time Fields

The two-field approach is confirmed. The local field is authoritative for all
current display, sorting, calendar groups, statistics, and accounting boundaries.
The auxiliary field is written on creation or explicit occurrence-date/time edits
and is otherwise unused by current product behavior. Both belong to one logical
transaction, including a transfer, and are saved atomically with its other fields.

Column names date and date_with_offset are confirmed. Encoding:

| Field | Encoding | Role |
| --- | --- | --- |
| date | TEXT YYYY-MM-DDTHH:mm:ss without offset | Authoritative local accounting date/time |
| date_with_offset | Nullable TEXT YYYY-MM-DDTHH:mm:ss+HH:MM or -HH:MM | Reserved occurrence date/time with an explicit UTC offset |

The offset representation is recommended instead of UTC-only storage because it
retains the original wall-clock components and identifies a convertible instant.
It does not identify an IANA timezone or preserve that timezone's complete rules.
Exact naming, constraints, and edge-case defaults remain to be finalized.

Store the entered Gregorian local date/time unchanged and display it unchanged
after device timezone changes. New drafts use the device local components when
opened; derive both persisted fields from the same final draft, not separate
calls to the current clock. Neither auxiliary field nor edit timestamps override
date. Preserve existing midnight behavior without a time-precision flag.

If the user edits only an amount, account, category, or notes, preserve both date
fields exactly, even after travel. Explicit date/time edits update both fields in
the same database transaction. The auxiliary value is the selected occurrence
time with an offset, not the time at which the Save button was pressed.

### Confirmed Auxiliary-Field Rules

For a new transaction with the unmodified current-time default, use the offset
for that same moment in the device timezone. For manually selected date/time,
use the phone's current timezone identity and calculate its applicable offset
for the selected date, including historical daylight-saving rules. Do not use
today's fixed numeric offset for every backdated date. No timezone selector is
required. This is the agreed assumption even for backdated entries after travel.

For legacy MMEX transactions, combine the TRANSDATE date and LASTUPDATEDTIME
clock time as specified above, then assign America/Toronto to date_with_offset.
This replaces the previously approved midnight-only mapping. Compute the offset
for each combined date/time; do not use a fixed -04:00 or -05:00 or copy an offset
from a different update date. This is accepted approximate occurrence metadata.
Later explicit occurrence edits use the phone timezone under the editor rule.

A manually selected wall time can be ambiguous or nonexistent during daylight-
saving changes. Detailed handling is deferred by the user; specify it when implementing date conversion. Never
silently change the primary local components to satisfy instant conversion. Any
case left unresolved must clear a stale auxiliary value rather than retain one
that describes the previous date/time. NULL is the proposed fallback if no
unambiguous conversion is available; final handling remains an open decision.

### Local Accounting and Future Use

Period membership follows date's saved calendar date; the current month
label follows the device current calendar month. Propose day groups descending,
then stored time ascending within each day, with a stable ID tie-breaker.
Cross-zone and repeated-hour ordering need not represent absolute chronology;
the auxiliary field does not change current sorting or calculation rules.

Picker and formatter adapters must preserve stored primary components rather
than reinterpret historical values in the current device timezone as real
instants. If native controls require Date, use an explicit component adapter that
avoids daylight-saving normalization and round-trip date/time shifts.

Future UTC conversion can use the auxiliary field where populated. Original local
components are also retained in an offset timestamp. Do not perform a mass rewrite
of date or report boundaries without a separately agreed migration.
Technical created_at/updated_at remain separate record-lifecycle timestamps.

## Remaining Initial-Schema Decisions

The source audit finds no data-integrity blocker. Fee defaults, transfer-to-single-
account cleanup, same-currency equality policy, zero amounts, physical deletion,
and core source date mapping are confirmed and must not be reopened as unanswered.

Imported transaction created_at equals normalized updated_at as a confirmed
historical proxy. Additional currency formatting/type fields are retained.
Dataset settings use the confirmed singleton app_settings row in SQLite; device
preferences stay outside snapshots in UserDefaults. These choices are settled.

Final technical choices are implemented and documented in [v1 schema](database-schema.md).
The converter chooses the earlier repeated-hour instant, validates supported
Decimal ranges, remaps IDs, and checks source/target records and financial totals.
The private trial passed; future application storage/import and UI are separate
implementation stages. See [usage](../development.md) and the [completed plan](../plans/completed/mmex-converter.md).

## References

- [SQLite: Datatypes](https://www.sqlite.org/datatype3.html).
- [NBU exchange-rate API documentation](https://bank.gov.ua/admin_uploads/article/Instr_API_KURS_VAL_Full_eng.pdf).
- [Android MMEX transaction write timestamps](https://github.com/moneymanagerex/android-money-manager-ex/blob/master/app/src/main/java/com/money/manager/ex/datalayer/AccountTransactionRepository.java).
- [Android MMEX date formatters](https://github.com/moneymanagerex/android-money-manager-ex/blob/master/app/src/main/java/com/money/manager/ex/utils/MmxDate.java).
- [RFC 3339: Timestamps with numeric UTC offsets](https://www.rfc-editor.org/rfc/rfc3339.html).
