# Initial MMEX Conversion Mapping

## Status

Implemented by tools/convert_mmex.py with the canonical Trexpend v1 schema.
Source reads use SQLite read-only mode; source hashes and standalone output are
verified. A private trial conversion passed native balance/month reconciliation.
iPhone application storage/import remains unimplemented.

This map consolidates decisions in database-design.md. Rows explicitly marked
proposed are not approvals. Canonical [SQL](../../database/migrations/001_initial.sql) and the
[completed converter plan](../plans/completed/mmex-converter.md) define execution; see [usage](../development.md). Personal values, balances, and source IDs stay out of Git.

## Source Audit

- Integrity check passed. Explicit account, currency, category, and transfer-side
  reference checks passed; a missing legacy FK is not evidence of a missing link.
- Categories have valid parents and no cycles; source root parent sentinel is -1.
- Occurrence/update dates parse. Toronto offset assumptions match user history.
  A repeated DST hour needs the documented deterministic auxiliary-time choice.
- No source negative/zero amounts, future occurrence dates, or monetary values
  changed by rounding to the currently used currencies' precision were found.
- No populated deletion markers. Status is uniformly R; follow-up and color
  fields contain their default sentinel, not additional used transaction features.
- Some non-transfer rows contain a nonzero TOTRANSAMOUNT equal to TRANSAMOUNT,
  without a recipient account. Normalize these irrelevant receiver fields to NULL;
  they do not represent another transfer or another amount to add to the balance.
- Split, scheduled, attachment, investment, custom-field, and transaction-link
  tables are empty. Tags/payee and rate-history data are excluded by agreed scope.

Revalidate the exact conversion input. Do not silently apply these observations
to a later export containing different populated features.

## Accounts

| Source | Target or disposition |
| --- | --- |
| ACCOUNTID | Preserve ordinary IDs and remap the outlier to the next agreed ID; update all retained references |
| ACCOUNTNAME | accounts.name, unchanged text |
| ACCOUNTTYPE | Map Checking/Credit Card/Cash to checking/credit_card/cash reference IDs; seed deposit separately |
| ACCOUNTNUM | account_number, unchanged text, including empty source values |
| STATUS | Map Open to the open account-status ID |
| NOTES | notes, unchanged text |
| HELDAT | Do not copy to bank; initialize bank empty for manual completion as agreed |
| INITIALBAL | initial_balance, exact normalized Decimal TEXT at account currency precision |
| INITIALDATE | open_date; interpret original midnight in Toronto for created_at, then initialize updated_at equally |
| FAVORITEACCT | TRUE/FALSE to favorite 1/0 |
| CURRENCYID | currency_id through the currency map |
| CREDITLIMIT | Intentionally replace with 0.00; source limits are incorrect per user |
| WEBSITE, CONTACTINFO, ACCESSINFO | Omit; source text is empty and fields excluded |
| STATEMENTLOCKED, STATEMENTDATE, MINIMUMBALANCE, INTERESTRATE, PAYMENTDUEDATE, MINIMUMPAYMENT | Omit under deferred account-feature scope; original is retained |

New account fields: current_balance NULL and unused; exp_date/close_date NULL;
image_id NULL to use the type default; color NULL for shared appearance.
Do not restrict history to operations on/after open_date.

## Transactions

Use one row per logical operation, including transfers. Final type encoding uses transaction_types: expense 1, income 2, transfer 3.
Reference IDs are defined by canonical SQL, not copied source labels.

| Source | Target or disposition |
| --- | --- |
| TRANSID | New sequential id in ascending legacy-ID order with private old/new map; never infer occurrence order from old ID magnitude |
| ACCOUNTID | account_id through the account map |
| TOACCOUNTID | to_account_id for Transfer; NULL otherwise, replacing source sentinels |
| TRANSCODE | Withdrawal -> expense; Deposit -> income; Transfer -> transfer |
| TRANSAMOUNT | amount at source-account currency precision |
| TOTRANSAMOUNT | to_amount at receiver currency precision for Transfer; NULL otherwise |
| CATEGID | Required category_id through the category map |
| NOTES | notes, unchanged text |
| TRANSDATE | Calendar date portion of date |
| LASTUPDATEDTIME | Wall-clock time portion of date; also full technical updated_at normalized to UTC |
| DELETEDTIME | No populated values; omit soft deletion under confirmed physical-delete model |
| PAYEEID, TRANSACTIONNUMBER, STATUS, FOLLOWUPID, COLOR | Omit under agreed scope; follow-up/color are default sentinels |

Build date_with_offset from the combined date/time in America/Toronto. Preserve
whole seconds for occurrence fields and source fractional seconds for updated_at.
Offset-free updates use Toronto; updates with explicit offsets preserve their
instant when normalized. Choose the earlier instance of repeated local
time where an offset must be synthesized. Never move the primary date for that rule.

All imported fee values are zero at the relevant currency precision. Transfers
set fee_account_id to the remapped source even at zero fee; expense/income records
use NULL. Existing principal amounts never incorporate an extra inferred fee.

### Confirmed Technical created_at Mapping

CHECKINGACCOUNT_V1 has TRANSDATE and LASTUPDATEDTIME, but neither a CREATEDTIME
column nor another verified insertion timestamp. This is not a missing accounting
date: date and updated_at mappings above are already settled.

Initialize created_at to the same normalized LASTUPDATEDTIME as
updated_at for historical rows, explicitly as a proxy. New app transactions use
their actual record creation time for created_at and never change it on edit.

## Categories

| Source | Target or disposition |
| --- | --- |
| CATEGID | categories.id, preserving the source IDs |
| CATEGNAME | name, unchanged; duplicates allowed |
| ACTIVE | is_active as 0/1 |
| PARENTID | parent_id through category map; -1 root becomes NULL |

Initialize favorite to 0 because the source has no category favorite flag.

## Currencies and Current Rates

Retain the complete currency catalog, with explicit ID mapping for account/rate
references. Used-currency rates only: preserve USD/UAH/EUR coefficients relative
to CAD for initial reconciliation. CAD identity needs no separate row. Do not
copy unused placeholder coefficients as exchange-rate facts.

| Source | Target or disposition |
| --- | --- |
| CURRENCYID | currencies.id and reference map |
| CURRENCYNAME | name, unchanged text |
| CURRENCY_SYMBOL | Unique code; audit confirms nonempty, case-insensitively unique source codes |
| PFX_SYMBOL | prefix_symbol, unchanged text |
| SFX_SYMBOL | suffix_symbol, unchanged text |
| SCALE | decimal_places by validated power-of-ten conversion |
| BASECONVRATE | exchange_rates.rate, only retained used-currency coefficients; direction is currency -> CAD |
| DECIMAL_POINT | Preserve as decimal_separator |
| GROUP_SEPARATOR | Preserve as group_separator |
| UNIT_NAME | Preserve as unit_name |
| CENT_NAME | Preserve as subunit_name |
| CURRENCY_TYPE | Preserve as currency_type, mapping Fiat/Crypto to fiat/crypto |

Derive optional symbol from a nonempty prefix, otherwise suffix,
otherwise NULL; preserve original affixes regardless. Retained reference metadata
does not control parsing/storage: canonical decimal TEXT always uses a point.
Do not create crypto network or trading features merely because a catalog row exists.

Rate updated_at is conversion/write time. Do not add source, rate_date, buy/sell
columns, or a historical-rate table. Omit CURRENCYHISTORY_V1 under current-rate
scope. Initial source EUR parity is retained for reconciliation, not verified as
a correct current market rate. Provider choice/update follows conversion.

## INFOTABLE_V1 and Other Tables

Do not copy INFOTABLE_V1 wholesale. BASECURRENCYID identifies the retained source
reference currency. Map the default account and user name into app_settings under the confirmed
[User settings](user-settings.md) specification. Old application versions,
platform UI options, synchronization configuration, and identifiers do not define
Trexpend's own metadata or enable deferred functions.

Omit PAYEE_V1, TAG_V1, and TAGLINK_V1 under explicit user decisions. Do not create
tables for empty deferred-feature data. Retain the original privately for recovery.

## Acceptance Checks After Conversion

Compare account/category/currency and transaction mappings, text preservation,
dates, transfer sides, fees, native balances, and calendar-period totals. Check
constraints and foreign keys on the target. Calculate money with Decimal, not
SQLite SUM over TEXT. Source REAL values need deliberate decimal normalization.

Compare native financial results before changing reference coefficients. An
intentional approximation in occurrence clock time must not change accounting
calendar dates. Test independent target opening and replacement/export workflows
in their implementation stages; a source audit is not a completed migration.

## Implemented Converter and Repeat Runs

Run tools/convert_mmex.py with Python 3.11 or newer. It uses standard-library
sqlite3, decimal, and zoneinfo and runs only on the computer. See the
[command and tests](../development.md). It is not bundled in the iPhone application.

Supported input is user_version 20 with the exact core table columns validated
by the script. Unknown columns/tables, populated deferred features, non-R statuses,
source deletion markers, missing references, or amounts requiring rounding fail
without publishing output. All retained source IDs must be positive integers.
Non-transfer receiver sentinels are normalized only for zero or redundant equal
amounts. Non-midnight source TRANSDATE values are refused, not silently discarded.

The command accepts explicit source and destination paths, plus an optional private
report destination under local/. It opens the source read-only, validates its
supported MMEX structure and values, creates a fresh staged Trexpend database,
inserts reference data and mapped records, and performs integrity, relationship,
date, count, and Decimal financial-reconciliation checks. Publish the completed
standalone destination only after validation. On failure, leave the source and
any existing destination intact; do not overwrite existing output by default.
Source files must be standalone consistent exports, not files being edited by MMEX.

Use the same canonical target-schema SQL/migration definitions as the application
for the later app implementation; do not maintain a divergent hand-copied schema in the converter.
Seed the agreed lookup/default-image/settings data and initialize file metadata.
Keep personal reports and source/target maps outside version control. The script
and schema definitions themselves can be committed without any personal data.

Repeat runs create new independent datasets from compatible original exports.
They do not merge into an existing Trexpend ledger, preserve edits made only in
that ledger, or reset a current phone database automatically. Importing the output
on the phone remains the ordinary explicit replacement workflow.

Record supported source assumptions and the produced Trexpend schema version.
Unknown source structures or unexpected populated features require a clear failure
or review, not silent omission. Future schema changes may require updating the
converter or applying supported Trexpend migrations to its output; keeping the
script does not promise indefinite MMEX compatibility. Snapshot restore of an
already-Trexpend file does not use this converter. Rate downloads are a later
separate step and must not silently run during source-history conversion.
