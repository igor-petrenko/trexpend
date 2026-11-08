# Transaction Creation and Editing

## Purpose

Deliver the primary daily-entry workflow without sacrificing exact financial
storage, replacement safety, or the existing history navigation behavior.

## Goal

Create and edit expenses, income, and transfers through one shared draft and form.
Creation opens an amount-focused bottom sheet; editing opens a full-screen page
without autofocus. Save commits one logical operation atomically, updates the
affected screens, and closes only after success. Cancellation never persists the
draft. The agreed keyboard, type-switching, category, and recipient defaults work
with both an imported ledger and a fresh ledger with no accounts.

## Scope

Include editor entry points on Home, All, and account history; native account and
category pickers; date/time selection; transfer amounts and fee ownership; dataset
preferences; schema v3; converter compatibility; post-write refresh and tests.

Exclude transaction deletion, account/category management, favorite editing,
attachments, filters, scheduled operations, saved drafts, custom keyboards,
automatic exchange-rate downloads, and additional platforms. Existing read-only
favorite indicators remain unchanged. A fresh ledger still requires importing
accounts until account management is delivered.

## Implementation Approach

### Delivery order and affected files

Implement and verify each stage before the next:

1. Schema v3, default initialization, validator, resources, and converter.
2. Editor reads, typed draft transitions, validation, and atomic create/update.
3. Shared form, account/category pickers, native date/time controls, presentations.
4. Entry points, commit notifications, coherent history/summary refresh.
5. Focused integration tests, full relevant regression suite, and native UI checks.

Extend the existing serial DatabaseStore -> DatabaseLifecycle -> SQLiteConnection
path. Do not introduce another database connection, dependency, repository layer,
or framework for editing. Suggested new files, created only when implemented:

| Area | Files and responsibility |
| --- | --- |
| Models | TransactionDraft.swift: create/edit context, original snapshot, raw amount strings, explicit/manual value ownership |
| Data | TransactionEditorRead.swift: one-record reads, catalogs, defaults, recipient lookup |
| Data | TransactionWrite.swift: bound insert/update and related preference writes |
| Features/Transactions/Editor | TransactionEditorState.swift: loading, transitions, validation, saving, dirty state |
| Features/Transactions/Editor | TransactionEditorView.swift: sheet/page shell, persistent actions and focus |
| Features/Transactions/Editor | TransactionEditorView form section: shared controls and scrolling body |
| Features/Transactions/Pickers | AccountPickerView.swift and CategoryPickerView.swift |
| Existing app/state | AppSession, SettingsStore, Home/History/All views and states: entry points and explicit post-commit invalidation |
| Existing database | DatabaseMigrator, DatabaseValidator, DatabaseLifecycle, DatabaseStore and bundled resources |
| Converter | tools/convert_mmex.py and its synthetic tests |

File boundaries may stay smaller if a focused component does not need its own
file. Views must not execute SQL or calculate financial totals.

### Draft and defaults

- Load references and persisted edit values in a coherent serialized read. Keep
  raw amount strings separate from canonical stored amounts and the original edit
  record. Do not change the database while selecting controls.
- New type is Expense and occurrence is current local date/time. Home/All use
  the eligible settings default; account history uses its selected open account.
  An absent/closed default leaves account selection required rather than silently
  changing the user's configured default. Disable creation without open accounts.
- Use last_created_category_id when active. With no usable remembered category,
  propose the unique active root General category; otherwise require selection.
  Do not infer the last-created category from transaction date or edit history.
- Persist the last category only on successful creation, including a manually
  selected transfer category. Edit, cancel, view, and failed saves do not update it.
- Existing edits retain original closed accounts and inactive categories as
  selectable current values. New replacement choices are open accounts and active
  categories. Keep the original closed account eligible when changing only notes
  or other fields. Storage must not prohibit future historical corrections.
- Category picker: favorites first with full parent path, then expandable tree;
  parent selection allowed, duplicate labels distinguished by path. Traverse with
  visited-node protection so an invalid hierarchy cannot hang presentation.
- Preserve all draft values across picker navigation, including date/time, manual
  destination amount, and fee ownership. Autofocus and initial defaults alone do
  not mark the form dirty. Compare meaningful draft changes with its initial state.

### Presentation and keyboard

- Create: adjustable native bottom sheet, initially focus amount and show the
  standard decimal keyboard. Expanded during input, compact after dismissal unless
  the user chose an expanded resting height. Do not refocus after picker return.
- Edit: separate full-screen presentation, no initial input focus; all controls
  follow normal top-to-bottom order without flexible blank space in the middle.
- Expense/income order: type, date/time, account, amount, category, optional notes.
  Transfer order: type, date/time, source/category/destination, source amount,
  destination amount when applicable, fee, charged-side choice, optional notes.
- Right-align numbers before the currency code in every monetary input.
- The entire amount surface focuses input. Use moderate amount typography.
- Cancel remains in the header; a full-width separate Save stays in the bottom
  safe-area region above the keyboard. No keyboard-dismiss button beside Save.
  Only the body scrolls; keep both actions accessible at large text sizes.
- Background taps dismiss input without consuming control taps; interactive form
  scrolling dismisses the keyboard. Another input transfers focus. Opening a
  picker works on the first tap and does not require separate keyboard dismissal.
- Protect Cancel, page back, and interactive sheet dismissal when changed. Offer
  Discard changes / Continue editing. Confirmed discard clears and closes; no
  cross-opening draft storage. While committing, prevent duplicate Save and
  dismissal that would conceal the write outcome.
- Verify focus, sheet sizing, compact-screen scrolling, and action placement on
  the installed iOS 27 SDK. A custom compact detent may be needed; do not claim the
  exact keyboard transition until verified on the Simulator/device.

### Type and transfer behavior

- Expense <-> Income preserves account, amount, category, occurrence, and notes.
- Entering Transfer keeps source account/amount, occurrence, and notes and selects
  the designated Transfer category on every new transition. The user can change
  that category afterward. Do not apply this transition on initial edit loading.
- Leaving Transfer keeps source amount/account and current category. On saving
  an ordinary transaction, write NULL receiver fields, zero fee, NULL fee account;
  never add the fee into principal. Receiver-only draft controls are reset when
  leaving Transfer; returning starts the documented recipient suggestion again.
- Source account changes preserve entered numbers and only change their currency
  interpretation. Do not convert or round manual values on the account change.
- Same-currency new transfer: hide destination amount and synchronize it from
  source. Existing unequal amounts survive unrelated edits; if principal/accounts
  are deliberately changed, make resulting synchronization explicit in the form.
  There is no database equality requirement.
- Different currencies: suggest destination amount using the shared converter
  and receiver precision only while untouched. Manual destination input disables
  further suggestions; existing edit values start as protected. Missing rates
  require manual entry and do not block an otherwise valid transfer. Never use a
  fabricated rate of one. Rate updates must not change saved principal.
- Fee defaults to zero and charged side to source. One fee, one of the two accounts.
  Store charged side in the draft, resolve fee_account_id on Save, preserve the
  fee number when either account changes, and use that side's currency precision.
- Preserve local occurrence fields. Use TransactionDateRules; changing the day
  applies the existing midnight default, then allows explicit time selection.
  Do not regenerate date_with_offset on unrelated edits. created_at remains
  unchanged on edit; updated_at advances only after a successful write.

### Recipient preferences

- Read transfer_defaults by source ID for the normal path. Check that the target
  is open and differs from source. Initialization seeds one historical winner per
  source, not a stored ranking and not a history scan on every editor opening.
- If no valid stored candidate exists, perform a source-scoped indexed historical
  lookup using the same frequency/latest ordering. Cache the result for this
  draft/source; do not persist a replacement preference before successful Save.
  With no historical candidate, select the sole other open account or leave empty.
- Reevaluate only on entry into Transfer or source changes while receiver remains
  automatic. Never replace a manually chosen recipient with a suggestion. If it
  equals a newly selected source, retain the visible choice with a validation
  error and require another selection.
- Successful new Transfer creation upserts its pair in the same transaction as
  the operation. Editing, cancelling, or failing does not update pairs.

### Validation and atomic writes

- Reuse MoneyCodec, TransactionDateRules, and accounting validation. Input accepts
  one point/comma and outer whitespace, rejects grouping/mixed separators and
  malformed/nonfinite/negative operation amounts. Zero is valid. Apply existing
  explicit currency-scale rounding on Save, not on account switching. Any rounding
  of manual input must be visible before committing; do not silently change it.
- Validate account/category references, receiver/source inequality, applicable
  currency precision, fee ownership, future-day prohibition, and supported Decimal
  range. Recheck on the serial worker rather than trusting picker state.
- Use expected dataset generation for every read/write. An imported/reset dataset
  invalidates old editors; never save a former dataset's IDs into the replacement.
- Insert/update the complete logical transaction and creation preferences inside
  one SQLite transaction with bound values. Obtain the inserted ID on that same
  connection. Require the edited record to exist; detect an original-record change
  rather than overwriting stale values. Preserve unmodified imported text and
  optional values; do not normalize an untouched historical record unnecessarily.
- Close successfully only after COMMIT. Validation/write failure retains the
  draft and presents a safe error. Roll back preferences and transaction together.
  Serialize backup/export/replacement with writes using the existing worker.

### Refresh without navigation resets

- Add an in-memory transaction content revision distinct from dataset generation.
  Increment after commit only; publish the committed transaction ID and settings.
  Refresh all three financial screens rather than adding per-account subscriptions. Do not key NavigationStack identity to content revision.
- Invalidate Home and complete All/account summaries explicitly. Hidden tabs must
  observe the revision on return; discard late responses from earlier revisions.
- Existing history keyset cursors must not page across different content revisions.
  On a write, rebuild the loaded date range coherently and create a fresh cursor;
  preserve the top visible stable transaction ID and its visual anchor. Load far
  enough to retain that anchor rather than replacing many pages with page one.
- A moved/removed anchor falls back to the nearest surviving chronological row;
  if no rows remain, show the empty state. Do not jump an old scrolled history to a
  new current-date operation automatically. Ordinary tab switching still reuses
  pages and position when no write occurred.
- Present Save success independently of a subsequent read failure: a failed
  refresh must not invite duplicating an already committed transaction.

### Proposed edge-case policies

These implemented fallbacks handle unusual catalogs without adding management
screens or guessing category IDs:

- Seed Transfer designation only for one active root named Transfer. For missing
  or ambiguous matches, keep designation NULL; entering Transfer clears the prior
  category and asks for an explicit category. A successful new transfer may persist
  that choice as the designation only while it remains NULL. Never choose an
  arbitrary duplicate or silently create categories while opening the form.
- No eligible remembered/General category means an empty required category field.
- Technical history ties use transaction ID and then destination ID deterministically.

## Database Changes

Implemented version 3 migration: database/migrations/003_transaction_editor.sql.
Keep released v1/v2 definitions unchanged. Execute the following SQL in the existing
migration transaction after reaching v2; account status 1 is the fixed open status.

```sql
ALTER TABLE app_settings ADD COLUMN last_created_category_id INTEGER
    REFERENCES categories(id) ON DELETE SET NULL;
ALTER TABLE app_settings ADD COLUMN transfer_category_id INTEGER
    REFERENCES categories(id) ON DELETE SET NULL;

CREATE TABLE transfer_defaults (
    source_account_id INTEGER PRIMARY KEY
        REFERENCES accounts(id) ON DELETE CASCADE,
    destination_account_id INTEGER NOT NULL
        REFERENCES accounts(id) ON DELETE CASCADE,
    CHECK (source_account_id <> destination_account_id)
);
CREATE INDEX transfer_defaults_destination_idx
    ON transfer_defaults(destination_account_id);

UPDATE app_settings
SET transfer_category_id = (
    SELECT CASE WHEN count(*) = 1 THEN min(id) ELSE NULL END
    FROM categories
    WHERE parent_id IS NULL AND name = 'Transfer' AND is_active = 1
);

WITH scored AS (
    SELECT t.account_id, t.to_account_id, t.date, t.id,
           count(*) OVER (
               PARTITION BY t.account_id, t.to_account_id
           ) AS uses
    FROM transactions AS t
    JOIN accounts AS destination ON destination.id = t.to_account_id
    WHERE t.transaction_type = 3 AND destination.status = 1
      AND t.account_id <> t.to_account_id
), ranked AS (
    SELECT account_id, to_account_id,
           row_number() OVER (
               PARTITION BY account_id
               ORDER BY uses DESC, date DESC, id DESC, to_account_id ASC
           ) AS preference_rank
    FROM scored
)
INSERT INTO transfer_defaults(source_account_id, destination_account_id)
SELECT account_id, to_account_id FROM ranked WHERE preference_rank = 1;

PRAGMA user_version = 3;
```

last_created_category_id starts NULL: historical timestamps cannot identify the
last actual creation. No transaction, amount, occurrence, existing category, or
existing setting is rewritten. Bootstrap pairs use eligible history once.

Execution and compatibility:

- Upgrade existing v1 through v2 and v3 in the staged-copy replacement path;
  upgrade v2 through v3. Extend the current v1-only startup upgrade condition.
- Build fresh/reset ledgers through the same version chain, after seed/reference
  insertion, with no accounts/pairs and NULL last-created category.
- Bundle the new SQL in the iOS target via the existing external resource pattern.
  Extend DatabaseResources and validator reference schemas for v1/v2/v3, typed
  settings decoding, FK checks, preference distinctness, and fast/full validation.
- Preserve schema v3 preferences when importing v3. Do not reseed or overwrite
  them on every open. Imported older versions initialize once in staging.
- Update the offline converter to emit v3 after all transactions/settings have
  been inserted and validated. Its bootstrap uses the same SQL and tie rules.
- Migration failure leaves the previous working database available through existing
  recovery machinery. Use a pre-upgrade standalone backup; do not invent destructive
  downgrade SQL. Older app versions may reject v3, so retain the pre-upgrade file.

## Tasks

- [x] Inspect current screen specifications, money/date rules, settings, migration,
  serial database ownership, and history refresh behavior; draft this plan.
- [x] Implement and verify schema/default compatibility.
  - [x] Add v3 SQL, resources, staged upgrade chain, fresh/reset initialization.
  - [x] Extend validator/settings models and converter output.
  - [x] Test v1/v2/v3 import, bootstrap ties, missing/duplicate categories, reset,
    preference preservation, failed upgrade recovery, and financial reconciliation.
- [x] Implement editor state and persistence.
  - [x] Add coherent reads, draft/original models, typed field ownership and validation.
  - [x] Implement all type/account transitions and recipient/default rules.
  - [x] Implement atomic create/update, preference writes and stale-record checks.
  - [x] Test rollback, failed saves, stale generation, closed-account corrections,
    zero/precision cases, date preservation, fee side and transfer conversion.
- [x] Implement shared UI (native verification is tracked separately below).
  - [x] Add native account/category pickers, date/time controls and shared form.
  - [x] Add creation sheet, editing page, amount-only create autofocus and keyboard
    dismissal without another button; preserve values across picker navigation.
  - [x] Add persistent Save/Cancel, dirty-discard confirmation, duplicate-save guard,
    field validation messages and no-account/unavailable-data behavior.
- [x] Integrate application entry points and post-commit refresh.
  - [x] Enable 64-point create actions with safe trailing/bottom scroll clearance.
  - [x] Open edit from account/All rows, one editor for one transfer operation.
  - [x] Add content revision and refresh Home/All/affected account histories without
    recreating navigation stacks or reusing stale pagination cursors.
  - [x] Test edits that move date/accounts, retained deep scroll, hidden-tab updates,
    month boundaries and commit-success/read-failure separation.
- [ ] Complete native and regression verification.
  - [x] Run focused financial/editor/migration/converter/state tests with synthetic data.
  - [x] Build iOS app with the actual iOS 27 SDK and run relevant existing suites.
  - [ ] Verify on the existing Simulator without unnecessary reboot: creation
    autofocus, compact/expanded sheet, standard keyboard, background/scroll dismissal,
    one-tap picker opening, fixed actions, discard and retry after failed Save.
  - [ ] Verify edit without autofocus, long account/category names, small screen,
    Dynamic Type, VoiceOver and transfer controls with both fee sides/currencies.
  - [ ] Verify multi-page tab position after save and ordinary no-write tab switches;
    close the outstanding history retention runtime check only with actual evidence.
- [x] Update screen/settings/database/architecture/development documentation with
  implemented behavior and limitations.
- [ ] Move this plan only after the outstanding native acceptance checks pass.

## Verification Results

- Implemented schema v3, bundled SQL, validator/settings decoding, converter output,
  shared create/edit state and form, pickers, atomic persistence, entry points and
  explicit post-commit refresh. Released v1/v2 SQL was not changed.
- iOS 27 app builds passed without reported compiler warnings. The full existing
  plus editor suite passed 89 test functions with no failures/skips. After the last
  UI refinement and two added edge cases, all 13 TransactionEditorTests passed.
- All 23 Python converter tests passed, including v3 settings and pair portability.
- Synthetic tests cover rollback on a preference-write failure, zero/rounding,
  stale record/dataset protection, failed-save draft retention, duplicate Save,
  closed-account corrections, unequal saved transfer amounts, fee ownership,
  moved account/date summaries, v2 ambiguous Transfer defaults, import/export/reset
  preferences and coherent multi-page refresh with old-cursor rejection.
- Native Simulator checks confirmed create autofocus/standard keyboard, visible
  Save above the keyboard, amount visibility after focus scrolling, one-tap
  account/category navigation, retained amount/date/time and compact keyboard-free
  return, parent category selection, Discard/Continue buttons and Continue retaining
  the draft. No test operation was saved into the personal working ledger.
- Rendered and visually inspected isolated 375-by-667 edit layouts at normal and
  accessibility3 sizes. Save/Cancel remain visible; large-text date/time labels use
  vertical layout. These captures contain synthetic data and remain outside Git.
- XcodeBuildMCP accessibility capture timed out; native CUA worked for the checks
  above but intermittently returned noWindowsAvailable, including on swipe attempts.
  A single-method test filter reported success with zero executed tests; it is not
  counted as verification. The complete editor suite subsequently ran all 13 tests.
- Remaining acceptance checks: dirty swipe dismissal end-to-end, background/scroll
  keyboard dismissal and manually selected resting detent, full VoiceOver traversal,
  and precise visible history offset across post-save tab switches. Range/cursor
  correctness is tested; pixel-level scroll behavior is not claimed verified.
  The older history-tab-scroll-retention plan remains open for the same native gate.
- No Simulator reboot or erase was used. No dependencies or public personal-data
  fixtures were introduced. Final diff/ASCII checks passed.
