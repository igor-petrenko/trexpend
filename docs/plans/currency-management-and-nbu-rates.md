# Currency Management and NBU Rates

## Purpose

Replace the Currencies placeholder with current-rate management and reliable NBU
synchronization. Provide a consistent valuation of accounts in UAH, CAD, USD, EUR,
and other supported fiat currencies without changing actual ledger amounts.

Status: implemented with automated verification; physical-device acceptance is
pending. Implementation was authorized after plan review. Personal databases were
not changed during development, and Simulator was not launched.

## Goal

- More > Currencies provides Used/All lists, search, rate details, manual editing,
  Refresh, and a persistent automatic-update preference.
- NBU supplies one official reference coefficient per currency, expressed as UAH
  per one currency unit. There are no bank-specific buy/sell coefficients.
- Automatic updates run on foreground activation when due, at most once per
  successful device-local day unless a required rate is missing. Manual Refresh
  remains available independently of this daily limit and the automatic setting.
- A manual override affects one currency, survives synchronization and backups,
  and remains active until explicitly removed.
- Only current values are retained. Converted historical reports use current
  values; native balances, saved transaction amounts, both transfer amounts, and
  fees never change because of a rate update.
- Offline operation remains possible. Failed refreshes preserve saved data and
  never substitute a missing coefficient with 1.
- A rate update refreshes affected summaries without resetting history rows,
  pagination, scroll position, navigation, or an open transaction draft.

## Scope

Includes the currency list/detail/editor, one NBU client using URLSession,
foreground refresh coordination, Decimal conversion, a v6 migration, validation,
import/export/reset/converter integration, and focused verification.

Excludes currency creation/deletion, catalog metadata editing, precision editing,
currency favorites, historical-rate reporting, bank-specific rates, buy/sell
spreads, cryptocurrency feeds, currency calculators, transaction original-purchase
currency fields, and guaranteed background execution while the app is closed.
Existing currency names, codes, symbols, precision, and formatting are preserved.

## Implementation Approach

### Confirmed rules and implementation defaults

The source, current-only valuation, daily/manual updates, per-currency manual
override, and catalog-editing exclusions were agreed with the user. The scheduling,
retry, UI placement, and transitional-storage details below are implementation
defaults, rather than additional previously approved UI designs. Revise this plan
if implementation evidence requires a different mechanism with the same behavior.

### Page and detail layout

- Replace only the Currencies destination in Features/More/MoreView.swift. Follow
  the existing native navigation, list, draft-editor, and error-state patterns.
- Default to Used, with All and search by existing code/name. Used includes the
  display currency and currencies of every retained account, including closed
  accounts. Also retain manually managed currencies in Used so overrides are not
  hidden when an account closes or is removed.
- Each row shows code, name, a reference conversion into the display currency,
  and a compact source/status: NBU, Manual, Previous rate, or Rate unavailable.
  The display currency is identity and needs no external rate for that row.
- Show the effective rate date as secondary information. Put the last successful
  download time, requested date, refresh error, and automatic-update toggle in a
  synchronization section. Do not show two unexplained dates on every row.
- A toolbar Refresh updates the batch, with progress and protection against
  duplicate requests. Keep cached content usable while loading. Automatic errors
  are nonmodal; manual errors are visible and retryable.
- Details show both quote directions, the actual active source, NBU date and
  download time when available, and an explanation that this is a reference
  valuation rather than a bank execution quote.
- All displays unsupported/missing entries honestly. Opening a supported uncached
  detail may request its rate when automatic updates are enabled; otherwise offer
  explicit Refresh. Do not make opening every list row a network operation.
- Use clear labels such as Not downloaded or No NBU rate available. Do not call
  every unchanged quote stale: the source date and download time have different
  meanings, and a repeated rate can still be valid for the requested day.

### Manual rate editing

- Edit a draft with Cancel and Save, using the unambiguous quote
  `1 <CODE> = <value> UAH`. The reference anchor UAH is fixed at 1 and is not editable.
  Show the resulting display-currency equivalent as a preview when calculable.
- Require a positive representable Decimal. Accept the existing decimal-input
  conventions, preserve rate precision, reject zero/negative/overflow values, and
  do not round a rate to the currency's monetary precision.
- Save only on explicit confirmation. Failed saves retain the draft; cancellation
  does not change the active coefficient. Check the original override before
  overwriting it, following existing stale-editor protection.
- Store the override separately from the latest NBU value. Refresh may update the
  inactive NBU value but must not alter the override or its modification time.
- Use NBU Rate removes the override only if a usable NBU value exists. If none is
  cached, obtain it first; failure leaves the manual value active. Never clear the
  override and leave a formerly usable conversion missing as an incidental effect.
- Show the cached NBU date before switching back, including when offline. A user
  may explicitly use that cached quote; do not imply it was just refreshed.
- Overriding CAD changes valuations of all other currencies expressed in CAD,
  because CAD is the denominator. Overriding USD changes conversions involving
  USD. Neither operation rewrites ledger records.

### Conversion and rounding

- Resolve UAH by code, never a seeded numeric ID. Let q(C) be UAH per one C;
  q(UAH) is exactly 1. After initial NBU activation, effective q(C) is the manual
  value when present, otherwise the cached NBU value.
- Compute `amountB = amountA * q(A) / q(B)`. Identity conversion does not require
  a stored quote. Do not persist inverse coefficients or all cross pairs.
- Extend the existing CurrencyConverter and Decimal helpers rather than create
  an unrelated financial engine. Keep conversion policy outside views.
- Decode network decimal values directly into Decimal; never use Double,
  SQLite REAL, or a floating-point round trip. Normalize units once at the source
  boundary, especially quotes for 10/100/1000 units. Never divide a value already
  provided as rate_per_unit a second time.
- Preserve source precision. Use ValuationArithmetic for recurring quotients and
  retain available Decimal precision until the final conversion/aggregate.
  Monetary output uses MoneyCodec's existing .plain rounding and currency scale.
  Sum conversions before rounding the aggregate; keep the existing displayed
  difference equal to displayed income minus displayed expenses.
- Missing nonzero contributions make the relevant aggregate unavailable; do not
  silently omit an account. Preserve native figures and other available totals.
  An unavailable transfer suggestion must not prevent entering actual amounts.
- Changing the display currency changes presentation, not stored coefficients.
  Changing the account in a transaction draft preserves its typed amount.

### NBU request and validation contract

- Use the official date-range JSON endpoint for one explicit date:
  `https://bank.gov.ua/NBU_Exchange/exchange_site?start=YYYYMMDD&end=YYYYMMDD&sort=exchangedate&order=desc&json`.
  This documented response exposes exchangedate, cc, rate, units, and
  rate_per_unit. Do not silently switch endpoints with different unit semantics.
- Request the current calendar date in Europe/Kyiv, independently of the user's
  display currency or device timezone. Require the returned effective dates to
  match the requested day. Reject future-date, mixed-date, empty, duplicate-code,
  malformed, nonpositive, or unrepresentable required data. Retain old values if
  the provider cannot supply that day; do not stamp yesterday's value as today.
- Check HTTP success, expected JSON shape, bounded response size, timeout,
  cancellation, fiat-code mapping, units, and consistency of the per-unit value.
  A proposed request timeout is 20 seconds and response limit is 2 MiB.
- Download a single provider batch and save every returned rate matching a fiat
  entry in the existing currency catalog, including unused currencies. The Used
  filter remains based on accounts/display currency/manual overrides, not cached
  quotes. Do not create currencies or overwrite catalog names from provider text.
- Treat malformed/incomplete data for supported required currencies as a batch
  failure. An explicitly unsupported catalog currency is an unavailable automatic
  rate, not a fabricated value, and must not block CAD/USD/EUR updates. Verify the
  provider coverage classification against its official currency list; absence
  of a required code alone is not enough to claim that it is unsupported.
- Persist a validated batch atomically. Preserve overrides, remove obsolete NBU
  values for currencies confirmed no longer supported, and do not combine dates
  from different downloads into a supposedly single current NBU snapshot.
- A same-valued successful download still updates download metadata and satisfies
  the daily refresh. A different effective date is meaningful even with equal
  numbers. Do not invalidate monetary summaries for metadata-only changes.
- Use HTTPS with standard trust validation. Requests contain public date/rate
  parameters only, never account names, balances, transaction data, or credentials.
  No additional provider, API key, dependency, server, or authentication is needed.

### Foreground scheduling and concurrency

- Own one focused refresh coordinator under AppDependencies. Use URLSession away
  from the serial database worker; enqueue only short read/commit operations.
  Do not hold AppSession.isBusy across a network request or block transaction entry.
- Start a nonblocking check after database startup and on scene activation. Check
  again on currency/account/display-currency changes when an automatic rate is
  missing. Do not poll on amount keystrokes or on every view render.
- Automatic updates default on, persisted with the dataset. A successful refresh
  counts for the device-local calendar day of completion and requested Kyiv date.
  Refresh again if either day advances. No timer or daily guarantee while closed.
- If the app remains active through midnight, recheck on the next relevant user
  interaction or foreground activation; no always-running timer is required.
- After failure, permit another foreground attempt after a five-minute cooldown;
  manual Refresh bypasses it. Persist last attempt time to avoid restart loops.
  Do not mark failure as daily success. No tight-loop retry or reachability polling.
- Coalesce concurrent requests for the same dataset/day. Merge newly requested
  currency IDs before commit when the downloaded batch covers them; otherwise
  queue one follow-up check. Serialize commits and never allow an older response
  to overwrite a newer accepted snapshot.
- Capture dataset generation and a coordinator request token. Recheck generation,
  request ordering, automatic preference for automatic requests, current target
  currency IDs, and provider date inside the commit boundary. Import/reset or
  disabling automatic updates invalidates the corresponding pending request.
- A user manual edit during a fetch survives its commit. Read current overrides
  during commit; never write a stale full copy of a rate row from before the fetch.
- Clear in-memory retry/request state when the dataset changes. After restoring a
  backup, reject implausible future success timestamps for scheduling purposes
  rather than suppress updates indefinitely. Treat cancellation as cancellation,
  not as a replacement-database or financial error.

### Existing rates and first activation

- Existing exchange_rates contains directed coefficients; CurrencyConverter
  currently prefers direct edges and then an inverse/two-edge route. Adding new
  UAH edges alongside old direct pairs would keep some stale conversions active.
- Preserve exchange_rates intact during v6 migration as the legacy snapshot.
  Do not relabel its updated_at as an NBU effective date or claim its source.
  New storage starts empty and synchronization has not yet succeeded.
- Before the first accepted NBU batch, keep the legacy converter for unchanged
  automatic valuations, visibly labeled Previous rate. Opening offline must not
  discard previously usable conversions.
- Manual entry also works before the first download. For a conversion involving
  an override, resolve both UAH coefficients explicitly: manual first, otherwise
  a legacy conversion of one currency unit into UAH. If that anchor path is absent,
  report the missing conversion; do not mix an overridden coefficient with an old
  direct pair that bypasses it. Unrelated legacy conversions remain unchanged.
- On the first valid NBU commit, switch valuation_mode to uah in the same SQLite
  transaction as the rate batch and success metadata. From then on, all consumers
  use only manual/NBU UAH coefficients. Never fall back to old direct pairs after
  that switch. A legacy-only unsupported currency becomes unavailable unless
  supplied with a manual override; expose this in the currency list.
- Keep the old table as preserved migration data, not a second current rate
  source after activation. Do not delete it in this feature or add ongoing history.
  A later cleanup would need its own migration decision.
- Ensure UAH exists as a fiat reference during v6 migration without replacing an
  existing row or changing imported metadata. Resolve all IDs by code.

### Refresh integration and affected components

- Add small currency/rate DTOs, CurrencyRead/CurrencyWrite database helpers, a
  provider decoder/client, and a single coordinator. Keep SQLite on the existing
  DatabaseStore/DatabaseLifecycle worker; do not introduce a repository framework.
- Centralize the rate snapshot read now duplicated in HomeRead, HistoryRead, and
  TransactionEditorRead. AllHistoryRead uses the same global summary policy.
- Add a rate revision distinct from transaction/account/category revisions in
  AppSession. Increment only after successful effective-rate changes; reset on
  dataset replacement. Publish metadata refreshes to currency screens separately.
- Home reloads its valuation snapshot using existing guarded state. Histories
  update summary data only for rate changes, retaining rows, cursors, selected
  period, scroll anchor, and in-flight pagination. Guard summary responses against
  stale rate/account/transaction revisions and dataset replacement.
- Freeze the converter snapshot in an already-open transaction editor. A refresh
  must not modify amount, receiver amount, fee, account, category, date/time, or
  notes. New editors use latest committed rates. Existing draft suggestions keep
  their captured snapshot; no unsolicited Refresh Amount action is required.
- A new account currency or display currency can trigger a missing-rate check
  after save without changing that save's result or waiting for the network.
- Update DatabaseResources, DatabaseMigrator, DatabaseValidator, DatabaseLifecycle,
  schema-version guards, Xcode resource references, and synthetic fixture builders.
  Support staged v1-v5 upgrades to v6 and reject unsupported future schemas.
- Fresh creation/reset and the offline MMEX converter produce v6, with no network
  request from the converter. Preserve its original reconciliation against legacy
  rates until the first successful NBU activation in the app.
- Backups/exports include preferences, cached NBU values, overrides, and transition
  state. Imports replace all of them with the dataset; pending old-dataset fetches
  cannot write into the new one. No device-only UserDefaults copy of financial rates.

## Database Changes

Add database/migrations/006_currency_rates.sql and bundle it through the existing
resource mechanism. The following is the planned exact SQL. The migrator executes
it inside its existing transaction after version 5; do not embed BEGIN/COMMIT in
the resource. No amounts or existing exchange_rates records are rewritten.

```sql
INSERT INTO currencies (
    code, name, symbol, decimal_places, prefix_symbol, suffix_symbol,
    decimal_separator, group_separator, unit_name, subunit_name, currency_type
)
SELECT 'UAH', 'Ukrainian hryvnia', NULL, 2, '', 'UAH',
       '.', ',', 'Hryvnia', 'Kopiyka', 'fiat'
WHERE NOT EXISTS (SELECT 1 FROM currencies WHERE code = 'UAH');

CREATE TABLE currency_rates (
    currency_id INTEGER PRIMARY KEY REFERENCES currencies(id) ON DELETE RESTRICT,
    nbu_rate TEXT CHECK (
        nbu_rate IS NULL OR (
            typeof(nbu_rate) = 'text' AND nbu_rate GLOB '[0-9]*'
            AND nbu_rate NOT GLOB '*[^0-9.]*'
            AND nbu_rate NOT LIKE '%.%.%' AND substr(nbu_rate, -1) <> '.'
            AND replace(replace(nbu_rate, '0', ''), '.', '') <> ''
        )
    ),
    nbu_effective_date TEXT,
    nbu_fetched_at TEXT,
    manual_rate TEXT CHECK (
        manual_rate IS NULL OR (
            typeof(manual_rate) = 'text' AND manual_rate GLOB '[0-9]*'
            AND manual_rate NOT GLOB '*[^0-9.]*'
            AND manual_rate NOT LIKE '%.%.%' AND substr(manual_rate, -1) <> '.'
            AND replace(replace(manual_rate, '0', ''), '.', '') <> ''
        )
    ),
    manual_updated_at TEXT,
    CHECK (
        (nbu_rate IS NULL AND nbu_effective_date IS NULL AND nbu_fetched_at IS NULL)
        OR (nbu_rate IS NOT NULL AND nbu_effective_date IS NOT NULL
            AND nbu_fetched_at IS NOT NULL)
    ),
    CHECK (
        (manual_rate IS NULL AND manual_updated_at IS NULL)
        OR (manual_rate IS NOT NULL AND manual_updated_at IS NOT NULL)
    ),
    CHECK (nbu_rate IS NOT NULL OR manual_rate IS NOT NULL)
);

CREATE TABLE currency_sync_state (
    id INTEGER PRIMARY KEY CHECK (id = 1),
    auto_update INTEGER NOT NULL DEFAULT 1 CHECK (auto_update IN (0, 1)),
    valuation_mode TEXT NOT NULL DEFAULT 'legacy'
        CHECK (valuation_mode IN ('legacy', 'uah')),
    last_attempt_at TEXT,
    last_success_at TEXT,
    last_success_requested_date TEXT,
    CHECK (
        (last_success_at IS NULL AND last_success_requested_date IS NULL)
        OR (last_success_at IS NOT NULL AND last_success_requested_date IS NOT NULL)
    ),
    CHECK (valuation_mode <> 'legacy' OR last_success_at IS NULL)
);

INSERT INTO currency_sync_state(id) VALUES (1);

PRAGMA user_version = 6;
```

Application validation additionally enforces positive exact Decimal text, valid
ISO calendar dates, UTC timestamps, fiat currency references, no stored UAH rate,
one sync-state row, and coherent NBU batch dates. Do not use SQLite casts as decimal
validation. Reject a non-fiat existing UAH row instead of silently modifying it.

Keep schema validation compatible with canonical versions 1-6. Update the reference
schema construction to capture v5 before applying v6. Apply content checks only
when their corresponding schema exists.

Upgrade working databases through the existing backup/staging/replacement flow;
advance version only after success. Extend the Before-v5 recovery naming/threshold
to v6. Imported candidates upgrade and validate before replacement. A failed
migration leaves the original usable. A failed refresh rolls back its whole data
commit but may retain last_attempt_at, written before the network request.

There is no automatic destructive down-migration. Recover through the preserved
pre-upgrade database when necessary. Earlier application builds will reject v6;
do not claim backward write compatibility.

## Tasks

- [x] Inspect existing conversion, schema, lifecycle, page, and refresh boundaries.
- [x] Record agreed behavior, implementation defaults, migration SQL, and risks.
- [x] Verify the chosen NBU endpoint against real public responses before coding.
  - [x] Confirm exact-day response, source coverage, units, rate_per_unit, dates,
    weekends, and unsupported-currency behavior; save synthetic English fixtures.
  - [x] Confirm the existing Decimal decoder preserves JSON number precision.
- [x] Implement and verify v6 persistence integration.
  - [x] Add canonical migration/resource wiring, validator, model, lifecycle, and
    converter changes; update every schema-version assumption and fixture.
  - [x] Add rate reads/writes, manual conflict checks, atomic batches, and dataset
    guards using existing serialized SQLite access.
  - [x] Verify offline legacy compatibility and first-activation behavior.
- [x] Implement and verify the shared financial conversion policy.
  - [x] Cover identity/direct/inverse/cross conversions, UAH anchor, manual
    precedence, missing rates, final rounding, and aggregate availability.
  - [x] Preserve legacy behavior before activation and disable legacy fallback
    afterward in every consumer.
- [x] Implement and verify NBU decoding and refresh coordination.
  - [x] Cover explicit dates, unit normalization, HTTP failures, malformed data,
    timeout, cancellation, daily checks, cooldown, and concurrent requests.
  - [x] Cover manual edits, disabling auto-update, date rollover, restored future
    timestamps, import/reset, and out-of-order completion during a fetch.
- [x] Implement the currency list, details, and manual-rate editor.
  - [x] Implement Used/All, search, source/date labels, loading/empty/error/offline
    states, missing rates, return to NBU, dirty-draft cancellation, and save failure;
    compile UI and verify the write rules on native fixtures. Device UI is below.
  - [x] Integrate the automatic preference and manual Refresh without blocking
    transaction entry or introducing currency catalog editing.
- [x] Integrate rate revision and summary-only refresh.
  - [x] Implement summary-only publication and verify retained history rows/cursors
    on native fixtures. Actual device scroll/navigation behavior is checked below.
  - [x] Preserve open transaction drafts and their captured conversion snapshot.
- [x] Update documentation and run focused automated verification.
  - [x] Update docs/database.md, docs/architecture.md, specs/database-design.md,
    specs/database-schema.md, specs/application-screens.md, development guidance,
    and converter documentation to distinguish legacy/current behavior.
  - [x] Run synthetic financial, rate, lifecycle/migration/import/export, editor,
    and MMEX-converter tests. Check that original amounts/IDs/metadata survive.
  - [x] Build the application/test target with the installed iOS 27 SDK using an
    appropriate compile-only destination. Do not launch Simulator.
- [ ] Complete physical-device acceptance with the user.
  - [ ] Verify compact/large text, numeric keyboard, errors/retry, manual/automatic
    transitions, offline reopen, and nonblocking transaction creation.
  - [ ] Verify foreground refresh does not move history or change an open transfer;
    verify import/reset cancels old-dataset publication.
  - [ ] Verify backup/restore retains the settings, rates, overrides, and dates.
- [ ] Record verification evidence and move the plan to completed only after its
  acceptance criteria and required checks are satisfied.

## Verification Results

- Implemented additive schema v6, legacy preservation, shared UAH conversion,
  manual/NBU layers, foreground scheduling, rate UI, lifecycle integration, and
  summary-only refresh. Offline MMEX conversion produces v6 with no downloads.
- Public NBU requests for 2026-11-20 and 2026-11-21 returned 45 entries with the
  requested effective dates; Friday/Saturday values matched. CAD/USD/EUR use one
  unit, and VND supplies units=1000 with a distinct rate_per_unit. The native Swift
  client also decoded a live 45-entry batch for its requested Kyiv date,
  2026-11-22, without printing or transmitting ledger data.
- Fourteen native host currency scenarios passed, including exact Decimal JSON,
  VND normalization, invalid/duplicate/date/size responses, canonical/manual/legacy
  conversion, final aggregate rounding, migration rollback, failed-batch atomicity,
  override restoration, scheduling/cooldown, old request tokens, backup/import/reset,
  concurrent request coalescing/manual edits, replacement and disablement during a
  fetch, failure retry, metadata-only publication, retained history pages, native
  record preservation, and a frozen editor converter.
- Existing eight account and eight category native scenario groups passed,
  including their six-boundary interrupted-upgrade cases. The complete 25-test
  Python MMEX-converter suite passed. Native scenarios use committed Swift test
  methods with test attributes removed in a temporary local host runner; this is
  not a Simulator test execution. HTTP status/timeout/transport handling was code
  reviewed; not every URLSession transport failure was injected end to end.
- Generic iPhone build-for-testing passed using Xcode 27/iOS 27 with signing
  disabled. Tests were compiled, not executed on an iPhone or Simulator. The
  existing AppIntents metadata-extraction notice is nonblocking.
- ASCII, local documentation links, canonical migration/plan agreement, and
  whitespace checks passed. New storage and financial logic
  were exercised only with synthetic temporary fixtures; personal ledgers were
  not opened or edited.
- Physical-device layout, accessibility text, keyboard, actual scroll position,
  foreground UX, and backup/restore interaction remain pending by user request.
  Keep the plan active until that acceptance is recorded. Simulator was not launched.

### Implementation clarifications

- The bounded client validates every returned quote and stores all matching fiat
  catalog entries, including unused currencies. Known supported fiat codes are recorded in NBUClient from the verified
  source list; a missing known required code fails the batch. Catalog entries
  outside that coverage remain unavailable instead of blocking supported entries.
  Review this coverage set if the provider adds or removes currencies.
- Automatic checks also run on entry to currency management and when opening the
  creation sheet, without awaiting the network before opening the editor. This
  supplies a user-interaction check after an active-app day rollover.
- Persisted retry cooldown applies to failed/incomplete attempts, not a completed
  success; adding a required currency can therefore trigger another same-day fetch.
- Current provider and override rows are separate columns in currency_rates. No
  new rate history or private data files are introduced.

References:

- [NBU date-range API documentation](https://bank.gov.ua/admin_uploads/article/Instr_API_KURS_VAL_data_Full_eng.pdf).
- [NBU official currency units list](https://bank.gov.ua/admin_uploads/law/Order_28052025_298-no_01012026_2-no_eng.pdf).
- [Database schema](../specs/database-schema.md).
- [Existing database lifecycle](../specs/database-lifecycle.md).
- [Financial foundations](completed/financial-foundations.md).

### Follow-up: cache all available catalog rates

- [x] Revise batch storage to save all returned quotes matching fiat catalog entries,
  while retaining required-code validation, atomic publication, and manual values.
- [x] Add a regression for unused CAD/GBP/VND, unchanged Used membership, ignored
  unknown codes, and refreshing the inactive NBU layer beneath a manual override.
- [x] Run native currency/regression checks and a generic iPhone compile-only build.
  All 15 currency scenarios and the account/category regression groups passed;
  build-for-testing succeeded without launching Simulator.

After installing this update, manual Refresh fills previously uncached quotes
immediately; otherwise the next due automatic refresh fills them. No new schema
migration or personal-database operation is required during development.

### Subsequent currency detail UI

The [currency detail comparison plan](currency-detail-comparisons.md) supersedes
the original fixed detail-quote rows with amount-based tiles and introduces schema
v7 for shared ordered comparison preferences. Existing v6 financial storage and
source semantics remain unchanged. The original v6 migration SQL above is retained
as its historical contract.
