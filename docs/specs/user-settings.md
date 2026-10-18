# User Settings Storage

## Status

Confirmed: dataset-linked settings live in SQLite and device-only preferences
live in UserDefaults. This supersedes the earlier all-UserDefaults proposal.
The app_settings table and its offline conversion are implemented. The iPhone
SettingsStore loads a typed read-only cache on startup and replacement. Settings
shows the active display currency and database lifecycle actions. Preference
editors and device-specific controls remain subsequent work.

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

## First Launch and Reset

First launch automatically creates a seeded initial ledger and its app_settings
row. Confirmed defaults are USD display currency, default_account_id NULL, and
user_name NULL. There are no starter accounts. Resolve USD by its currency code
when building the seed. See [Database lifecycle](database-lifecycle.md).
Existing imported settings, including CAD display currency, remain unchanged.

Reset Database requires confirmation and replaces these settings with the same
initial defaults as a fresh installation. It must not preserve a default-account
ID or user name from the old ledger. Device-only UserDefaults and independent
exported backups remain unchanged. Import replaces settings from the snapshot;
it does not inject first-launch seed rows into the imported file.

## Availability and Local Backups

Settings remains accessible when the database cannot open. Import/reset recovery
actions do not depend on loaded dataset preferences; export requires usable data.
Startup failure offers the same actions and Cancel in an alert.

Automatic backups are local files in Documents/Backups, exposed in Files. The
calendar day is determined from the current device timezone. No backup-directory
preference or platform path is stored in the portable database. Device-specific
external-folder bookmarks remain outside the current scope.
