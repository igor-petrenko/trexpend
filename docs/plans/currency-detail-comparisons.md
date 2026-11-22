# Currency Detail Comparisons

## Purpose

Replace fixed currency-detail quote rows with useful amount-based comparison tiles
and simplify provider metadata without changing stored rates or ledger amounts.

## Goal

- A comparison amount starts at 1 whenever currency details are newly opened.
  The same entered number applies independently to both directions in every tile.
- A shared saved currency selection/order controls all currency-detail pages.
- Show at most two equal-width tiles per row. A final single tile fills the row;
  accessibility text sizes may use one column throughout.
- A separate metadata block shows Source and Updated. NBU is displayed without
  its date; remove NBU rates for. Manual values remain honestly labeled Manual.
- Selection and order survive restart, backup, import, and reset according to the
  dataset lifecycle. Existing financial records and rate values are untouched.

## Scope

Include comparison amount input, responsive tiles, selection/reorder editor,
additive schema v7, persistence/validation/converter wiring, focused synthetic
checks, compile-only iPhone verification, and documentation updates. No provider,
network, historical-rate, monetary-storage, or transaction-editor behavior changes.
Simulator is not to be launched; device layout acceptance remains separate.

## Implementation Approach

- Reuse CurrencyConverter and Decimal arithmetic. Parse a nonnegative exact decimal
  amount without rounding it to any currency's monetary scale. Zero is valid;
  negative, malformed, and unrepresentable input shows an inline error. Input may
  use a comma decimal separator. Never use Double or persist the comparison amount.
- A THB page with amount 100 and a CAD tile shows `100 CAD = ... THB` first,
  followed by `100 THB = ... CAD`, as requested in the tile-order follow-up. Keep both currency codes explicit. Use existing reference
  number formatting; unavailable directions say Rate unavailable, never parity.
- Keep the entered text/focus during rate or selection refresh. New detail views
  initialize at 1. Typing requires no database writes or network calls.
- Use paired rows of tiles so an odd final tile fills the available width, rather
  than leaving an empty grid cell. Use one column at accessibility sizes and allow
  long numbers/codes to wrap instead of clipping essential information.
- Put Amount above the tiles and a Comparison Currencies action nearby. A native
  large sheet with navigation opens the searchable full catalog and a Selected
  section with move handles and remove actions. Search filters choices to add;
  selected ordering remains complete while editing. Allow an empty selection.
- The editor has a draft and explicit Save/Cancel, dirty-dismiss protection, write
  error retention, original-order conflict checks, and dataset generation guards.
  Choosing an unsupported currency is allowed and yields an unavailable tile.
- Default shared order is UAH, CAD, USD, EUR when present. Hide the currently opened
  currency from its own tiles without changing the global selection. Explain this
  in selection UI. Saving comparison settings publishes currency metadata only;
  it does not invalidate ledger summaries or captured transaction drafts.
- Store selections in SQLite, following existing serialized read/write methods.
  Reuse CurrencyCatalog with a defaulted comparisonIDs field for existing fixtures.
- Source is NBU for automatic provider values, Manual for overrides, Previous rate
  for legacy fallback, and UAH reference for the fixed anchor. Updated uses the
  manual edit time when active, otherwise the NBU download time. Keep existing
  localized date/time formatting; unknown timestamps are not invented. Provider
  effective date remains stored for validation and return-to-NBU confirmation.
- Update DatabaseResources, migrator, validator reference schemas, lifecycle version
  thresholds/recovery names, bundled SQL, offline converter, and affected fixtures.
  Support canonical v1-v7 imports, preserve staged replacement safety, and reject
  future versions. Do not modify an already released v6 migration.

## Database Changes

Add database/migrations/007_currency_comparisons.sql. Execute inside the existing
migration transaction after v6. IDs are resolved by currency code, not seeded IDs.

```sql
CREATE TABLE currency_comparison_currencies (
    currency_id INTEGER PRIMARY KEY REFERENCES currencies(id) ON DELETE RESTRICT,
    sort_order INTEGER NOT NULL UNIQUE
        CHECK (typeof(sort_order) = 'integer' AND sort_order >= 0)
);

INSERT INTO currency_comparison_currencies(currency_id, sort_order)
SELECT id, ROW_NUMBER() OVER (
    ORDER BY CASE UPPER(code)
        WHEN 'UAH' THEN 0 WHEN 'CAD' THEN 1 WHEN 'USD' THEN 2 WHEN 'EUR' THEN 3
    END
) - 1
FROM currencies
WHERE UPPER(code) IN ('UAH', 'CAD', 'USD', 'EUR');

PRAGMA user_version = 7;
```

Save the complete ordered unique ID list in a SQLite transaction using bound
parameters after validating references and the original list. An empty table is
an explicit empty selection; never silently reseed on a normal read. Application
validation checks positive currency references and valid ordering; SQLite ensures
foreign keys and unique nonnegative integer positions. Export/import includes this
table. Reset/fresh conversion seeds the default list once via the migration.

Preserve the original database through the existing Before-v7 staged upgrade.
Failure rolls back without switching the working dataset. No destructive downgrade
is provided; retain the pre-upgrade snapshot for older application builds.

## Tasks

- [x] Inspect current details, currency storage, native reorder, and lifecycle code.
- [x] Confirm shared selection/order and both-direction amount behavior with user.
- [x] Add v7 migration, resource wiring, validator, converter, and fixture updates.
- [x] Implement comparison persistence, validation, and stale-save protection.
- [x] Add exact comparison input and responsive bidirectional tiles.
- [x] Implement selection/reorder draft and Source/Updated metadata block.
- [x] Add focused tests for migration/defaults/rollback, save/order/empty selection,
  duplicate/invalid IDs, stale lists, amount parsing, both conversions, missing
  rates, and backup/import/reset preservation.
- [x] Run native synthetic currency/account/category regressions, converter tests,
  ASCII/path/whitespace checks, and generic iPhone build-for-testing.
- [x] Update architecture/schema/screen/development docs and record verification.
- [ ] Complete separate device acceptance for layout, odd rows, long values, large
  text, keyboard, selection, reordering, and cancellation. Do not launch Simulator.

## Verification Results

- Implemented amount-based bidirectional tiles, shared selection/reorder, separate
  Source/Updated metadata, exact input parsing, and additive schema v7 integration.
- Nineteen native host currency scenarios passed, including four new comparison
  scenarios for v6 migration rollback/defaults, selection/order/empty/conflict
  handling, exact amount input and both directions, and backup/import/reset with
  metadata-only publication. Existing eight account and eight category scenario
  groups passed, including their interrupted-upgrade boundary cases.
- The complete 25-test Python converter suite passed with v7 output. A synthetic
  full-migration smoke check confirmed v7 defaults and foreign-key integrity.
- Native checks execute committed test methods with testing attributes removed in
  the existing temporary local host runner. They do not launch Simulator or verify
  iPhone UI interactions.
- Generic iPhone build-for-testing compiled the application and test target using
  Xcode 27/iOS 27 with signing disabled. No device installation or Simulator launch.
- ASCII text, relative documentation links, exact plan/migration SQL agreement,
  and whitespace checks passed. Personal databases were not read or modified.
- Actual phone layout, keyboard, long-value wrapping, one/two-column sizing, odd
  final rows, native move handles, and cancellation UX remain pending. Keep this
  plan active until separate device acceptance is recorded.

### Follow-up: dismiss the comparison keyboard without intercepting controls

The first list-wide spatial gesture compiled, but the user reported that it
prevented comparison selection, manual-rate editing, and Refresh buttons from
responding. Remove that approach rather than relying on its simultaneous behavior.

- [x] Remove the list-wide gesture and its field-bound/coordinate-space tracking.
- [x] Attach dismissal only to noninteractive tiles, metadata rows, explanatory
  text, and the amount label. Each action button clears focus in its own action;
  no tap gesture wraps a button or the entire list. Keep Done and scroll dismissal.
- [x] Compile the app for a generic iPhone without launching Simulator.
  Build succeeded; ASCII and whitespace checks passed.
- [ ] Verify outside taps, cursor placement, comparison selection, manual-rate
  editing, and Refresh on the phone with the keyboard both shown and hidden.

This is a UI-only change with no database or financial behavior changes. Runtime
keyboard acceptance remains deferred to the user's physical-device check.
