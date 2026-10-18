# Trexpend Database Schema v1

## Status and Canonical SQL

Implemented for the offline converter. The authoritative executable schema and
seed data are [001_initial.sql](../../database/migrations/001_initial.sql).
The iPhone application opens/imports this schema and bundles this same SQL.
[001_defaults.sql](../../database/seeds/001_defaults.sql) supplies public starter
catalogs and settings for creation/reset only. There is no duplicate schema.

This initial schema creates a new file. It is not an in-place MMEX migration.
application_id is 0x54525850 (TRXP) and user_version is 1. The marker distinguishes
the format, not its authenticity; import must also validate schema and contents.

## Tables

| Table | Contents |
| --- | --- |
| currencies | Full catalog; codes, names, affixes, optional symbol, currency type, separators, unit names, and decimal_places |
| account_images | Protected built-in image identifiers; no custom-image bytes/files |
| account_types | Checking, credit card, cash, deposit, each with a default image reference |
| account_statuses | Open and closed, with extensible reference structure |
| transaction_types | Fixed v1 IDs: expense 1, income 2, transfer 3 |
| categories | Names, nullable parent_id, is_active, favorite; duplicate names allowed |
| accounts | Identity, currency, initial balance, optional metadata, reference fields, and timestamps |
| transactions | One row per logical operation, including both sides and fee for transfers |
| exchange_rates | Current directed coefficients and technical updated_at |
| app_settings | One row, ID 1: display currency, nullable default account, optional user name |

The schema does not include users/authentication, payees, tags, transaction status,
transaction number, attachments, templates, transaction links, or rate history.

## Transactions Contract

| Column | Storage and rule |
| --- | --- |
| id | INTEGER PRIMARY KEY |
| transaction_type | Required FK to transaction_types |
| account_id | Required source/ordinary account FK |
| amount | Required nonnegative monetary TEXT in account_id currency |
| to_account_id | Required different account for transfers; NULL otherwise |
| to_amount | Required receiver-currency monetary TEXT for transfers; NULL otherwise |
| date | Required local Gregorian YYYY-MM-DDTHH:mm:ss; authoritative for accounting |
| date_with_offset | Nullable offset timestamp; populated by this converter |
| category_id | Required FK to any category node |
| notes | Optional unchanged TEXT |
| fee | Required nonnegative monetary TEXT; zero for ordinary income/expense |
| fee_account_id | Source or receiver FK for transfers even at zero fee; NULL otherwise |
| created_at | Required technical UTC timestamp; imported proxy equals updated_at |
| updated_at | Required technical UTC timestamp, retaining source fractional seconds |

No constraint equates same-currency amounts. Transfer principal excludes fee.
Deleting the logical row removes its financial effects; no soft-delete flag exists.

## Money and Validation Boundaries

Use canonical decimal TEXT, a point separator, and currency-specific fractional
digits. Stored rates have independent precision. Money calculations must not use
SQLite numeric casts or SQL SUM over these strings. The converter verifies text
mapping and independently reconciles native balances and per-account/month totals
using Python Decimal. The application must implement equivalent Decimal rules.

SQLite enforces type/shape for operation amounts and rates, nonnegative operation
syntax, positive-rate syntax, FK relationships, and operation-field combinations.
Currency-dependent scale and full calendar/UTC validation are code responsibilities;
they cannot be expressed as ordinary cross-table CHECK expressions. All converted
rows pass those validations before publication. Enabling foreign_keys is required
on each working/import connection.

Supported decimal_places is 0 through 18, including the source catalog's 0, 2, 4,
and 8. Source numbers use Decimal from their shortest SQLite/Python representation;
no binary floating-point arithmetic is used for financial calculations. Decimal
inputs must be finite, have at most 38 significant digits, and have normalized
exponents between -128 and 127. Unsupported values fail rather than truncate.
Reconciliation uses a wider temporary precision and reports no successful parity
when source amount rounding would be required. Such a changed source requires
explicit review. Normal future editor rounding remains nearest, halfway away from
zero, at the relevant currency precision.

current_balance is present but constrained to NULL in v1. Using persisted derived
balances later requires a deliberate schema/maintenance migration. Credit limits
are initialized to zero under the user's explicit decision. Account opening dates
are informational and do not filter operations used to reconstruct balances.

## Relationships and Indexes

Foreign keys restrict deleting referenced accounts, currencies, categories, and
reference data. Category parent FKs are deferred during the insertion transaction;
cycle detection is performed by the converter and future category-management code.
Built-in image deletion is additionally blocked by a trigger.

History indexes match day descending, clock time ascending, ID ascending queries,
using substr(date, 1, 10) as the day expression. Separate source and destination
account indexes cover both transfer projections. Category/fee-account indexes
support reference checks, and currency-pair uniqueness prevents duplicate rates.
No banking data or automatically calculated balance is stored in an index.

Default image asset names are seeded stable identifiers. Actual checking/card/
cash/deposit illustrations are not added to the iPhone resources by this converter
task; account UI work must supply them with a safe fallback. No private database
or report is bundled in the application.

## Evolution

This task implements only schema creation at v1. No upgrade path is claimed until
there is a later version and tested migration. Future upgrades need ordered SQL,
an atomic version change, a recoverable snapshot, and compatibility checks. Existing
v1 output is never overwritten by rerunning the MMEX converter.
