# User Settings Storage

## Status

Confirmed: dataset-linked settings live in SQLite and device-only preferences
live in UserDefaults. This supersedes the earlier all-UserDefaults proposal.
The app_settings table and its offline conversion are implemented. The iPhone
SettingsStore and settings UI are not implemented yet.

## Confirmed Dataset Settings

Use one app_settings row with typed columns instead of a generic key/value table:

| Field | Storage and purpose |
| --- | --- |
| id | INTEGER PRIMARY KEY constrained to 1; singleton, not a user identity |
| display_currency_id | Foreign key to currencies; currency for converted totals |
| default_account_id | Nullable foreign key to accounts; default for new transactions |
| user_name | Optional TEXT display name; not a login, unique name, or bank account |

A singleton is sufficient for one local ledger. Do not create users, passwords,
authentication, or multiple profiles. Column types and foreign keys make invalid
references visible; a string key/value value would not provide the same FK checks.
Future concrete preferences can be added through ordinary schema migrations.

The future SettingsStore exposes typed values and persists through DatabaseStore's
serialized operations, not open its own SQLite connection. Views do not write SQL.
Display-currency changes refresh converted results without rewriting ledger values.

## Confirmed Source Mapping

- INFOTABLE_V1.BASECURRENCYID maps to display_currency_id through the currency map.
- android:default_account_id maps to default_account_id through the account map.
- USERNAME maps to user_name, preserving source text.

Read-only inspection confirms the currency/default account references resolve,
the default account is open, and the source user name is populated. Do not print
personal setting values or include them in committed examples.

Do not copy INFOTABLE_V1 wholesale. MMEX versions/IDs, synchronization URLs, dialog
sizes, desktop paths, filters, investment settings, budget settings, and report
options are not Trexpend preferences. No copied legacy key may change schema version
or trigger network behavior. Source settings stay recoverable in the original.

## Export and Replacement

SQLite snapshot export includes the settings row. Import
replaces settings together with accounts, currencies, and transactions. Discard old
in-memory preferences after a successful dataset switch. An invalid candidate does
not replace either the existing ledger or its settings.

Foreign keys validate existence, not default-account openness. On closure or
replacement, revalidate the default account and clear or ask for a new choice when
it is no longer eligible. Never save an old dataset's account ID into the new one
just because the integer happens to exist there.

## Device Preferences

UserDefaults remains suitable for device-only presentation state such as a future
theme preference. It is not part of SQLite export. No such additional preferences
or screens are required now. Dataset snapshots must not depend on iOS-specific
preference storage; future other-platform apps can read the same portable dataset
settings while keeping their own device preferences outside the database. This
does not expand the current iPhone-only implementation scope.
