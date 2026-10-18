# Product Overview

## Status

The application contains a Home/All/Settings shell, app icon, Blue Slate accent,
and fixed light appearance. Pure financial/date components and their tests, the
offline converter, and canonical v1 schema are implemented. Automatic database
creation, replacement import, manual export, and confirmed reset are implemented.
Daily local backups visible in Files and recovery import/reset after startup
failure are implemented. Financial screen content and record editing remain planned.

## Purpose

Trexpend is a personal, local iPhone application for recording daily financial
transactions and retaining existing Money Manager Ex history.

## First Usable Version

- Target iPhone and iOS 27 with Swift and SwiftUI.
- Use a Trexpend-owned SQLite schema and import only supported Trexpend databases.
- Automatically create an initial empty-history database on a clean first launch.
  Import is optional. Existing MMEX data can be converted on the computer; the
  iPhone application does not contain an MMEX importer.
- Replace the current dataset on import; do not merge records.
- View accounts and balances in each account's currency.
- View total balances and calendar-month income and expenses in a selected
  display currency. New/reset ledgers default to USD; imports keep their saved
  display currency (CAD in the current converted dataset).
- Browse account-specific and all-account transaction history.
- Create, edit, and delete expenses, income, and transfers between owned accounts.
- Select one required category, record transaction date/time, and enter optional notes.
- Record a transfer fee and which of its two accounts was charged; principal
  excludes the fee, which contributes to expenses.
- Default the date to today and allow any past date; disallow future dates.
- Select a default account and display currency in Settings.
- Manually export a consistent database snapshot to Files, including iCloud Drive,
  and restore a supported snapshot through replacement import.
- Reset the database to its initial defaults only after explicit confirmation.

Agree which source information to migrate before conversion. Preserve original
exports privately so omitted information remains recoverable. Tags, payees, transaction status, and transaction numbers are explicitly omitted.
Other retained fields must survive even when their UI is omitted. Initial currency conversion uses the coefficients in the imported
file; these are saved coefficients, not a claim of current market rates.

## Deferred Scope

- Tag editing and account/category management screens.
- Scheduled transactions, split editing,
  charts, reports, and historical exchange-rate conversion.
- Transaction attachments and frequent-operation templates as separate future features.
- Transaction titles, links, custom colors, and version history are outside initial scope.
- Automatic exchange-rate downloads and unattended backup to external/cloud folders.
- Device synchronization, servers, authentication, macOS, and Android applications.

MMEX conversion is an offline migration aid, not an application feature. Future
schema evolution is independent of MMEX. Do not package private datasets in the
application or maintain export compatibility with the Android application.

## Documentation Map

- [Architecture](architecture.md): component boundaries, data flow, and delivery order.
- [Database](database.md): storage, preservation, and import/export rules.
- [Database design](specs/database-design.md): new-schema decisions and offline conversion.
- [Database lifecycle](specs/database-lifecycle.md): initialization, replacement, export, and reset.
- [Database schema](specs/database-schema.md): canonical implemented v1 structure.
- [Conversion mapping](specs/mmex-conversion.md): source-field mapping and audit findings.
- [User settings](specs/user-settings.md): current preference ownership and proposed SQLite storage.
- [Application screens](specs/application-screens.md): navigation and user-visible behavior.
- [Financial behavior](specs/financial-behavior.md): balances, transfers, and conversion.
- Implementation plans live in `plans/`; completed plans are retained in `plans/completed/`.
