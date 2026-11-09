# Account Management

## Purpose

Allow local account creation and maintenance without importing an existing database.
Expose account metadata without adding more root tabs.

## Goal

Accounts under More lists accounts grouped by bank. Users can create accounts,
edit existing accounts, and reach the same editor from account history. Images
survive standalone database exports, imports, and automatic backups.

Implementation was authorized after the planning discussion. The rules below
record the agreed scope. Data checks and builds have passed; device acceptance
remains pending.

## Scope

- Account list, bank grouping, open/closed filtering, and account editor.
- Shared bank catalog with optional logos; initial entries: PrivatBank, CIBC, monobank.
- Built-in image selection, optional custom images, and account color.
- Account status actions and safe deletion of unused accounts.
- Consistent refresh of all affected account and transaction projections.
- No category management, bank networking, reconciliation, interest accrual,
  available-credit calculations, or account currency changes.

## Implementation Approach

### Account list

- Use the existing More navigation destination and title Accounts.
- Add a trailing Add button and an empty-state creation action.
- Default to Open accounts; offer Open, Closed, and All selection.
- Group by bank name with optional logo; put accounts without a bank last.
- Order favorites first within each bank, then by name and stable ID.
- Show account image, full account name, favorite marker, type, currency,
  and calculated native-currency balance. Do not repeat bank details per row.
- Tapping the full row opens the editor. Offer View transactions in the editor
  so closed accounts also have a route to their retained history.
- Keep navigation available without a working database; show recovery guidance
  and disable database-dependent actions.

### Account editor

- Reuse one full-page create/edit form with Cancel and a persistent Save action.
- Identity: name, type, currency, optional bank, and favorite.
- Require a nonempty name when saving through the editor. Duplicate names remain
  valid. Preserve existing empty names during migration; require a name if such
  an account is subsequently saved through the editor.
- Initial balance remains editable even with transaction history and does not
  require a warning or confirmation. It changes calculated balances, not stored
  transaction amounts or monthly income/expense totals.
- Currency can be selected during creation and is read-only during editing,
  including accounts without transactions, following the existing contract.
- Financial details: initial balance, calculated read-only balance on edit,
  and optional credit limit. Negative initial balances are valid. Credit limits
  are informational and do not contribute to balance.
- Additional details: opening date, optional card expiry, account/card number,
  notes, optional color, and account image preview/selection.
- New accounts start open, with zero initial balance and today's opening date.
  Prefer the display currency initially, but allow explicit selection before save.
  Do not automatically change the default account setting.
- Show closure date for closed accounts. Propose Close and Reopen actions with
  explicit confirmation; reopening clears closure date. Closing a default
  account clears that setting atomically and explains the change.
- Offer Delete only when no transaction references the account, including fee
  references. Confirm deletion; otherwise offer closure and preserve history.
- Preserve optional fields when switching types; do not silently discard values
  hidden by the current type. Changing type uses its default image only when no
  account image override exists.
- Preserve a dirty draft on failures; confirm discarding unsaved changes.
- Add Edit account after the favorite button in the account-history toolbar.

### Banks and images

- Use reusable bank records with optional logos and nullable account bank
  references. Seed PrivatBank, CIBC, and monobank through the version 4 migration
  and initial database creation path. The current account form only selects a
  bank or No bank; it does not create or edit banks.
- Defer bank management to a separate future page. Shared bank renames will
  affect every linked account when that page is implemented.
- Official logo references are recorded in design/bank-icons/README.md. Bundle
  runtime copies under the application resources during implementation; never
  reference design/ directly from the target or fetch logos at runtime.
- Preserve existing bank text during migration; do not infer banks from account
  names or merge differently spelled names automatically.
- Recommend storing custom image bytes in SQLite to preserve the existing
  single-file backup contract. Do not store external photo-library identifiers
  or arbitrary filesystem paths as the only copy of an image.
- Use Photos/Files import, bounded decoding, normalized PNG encoding,
  metadata removal, and a maximum stored dimension of 512 pixels and 1 MiB.
  Reject unsupported images clearly.
- Use native symbols or bundled artwork as defaults and safe fallbacks. Current
  rendering uses type symbols; existing database asset identifiers do not yet
  correspond to dedicated bundled account artwork.
- Resetting an account image removes the override and restores its type default.
  Image cleanup must never delete accounts or shared images still in use.
- Load bundled bank logos and bounded account images without adding an external
  image-storage service or changing exports into archive packages.

### Persistence and refresh

- Follow DatabaseStore's serialized access and keep SQL outside views.
- Commit account, custom image, and default-setting changes atomically when they
  belong to the same save. Cancelled account drafts must not create orphan images.
  Bank catalog writes are limited to migration/seeding in this scope.
- Guard writes against replacement databases and stale edited records.
- Recalculate balances from initial balance and history; keep current_balance NULL.
- Refresh account management, Home, account history, All account captions and
  summaries, settings, and transaction-editor account catalogs after saving.
  All currently observes transaction revisions only, so metadata invalidation
  needs explicit handling without discarding unrelated history position.
- Closed accounts remain in historical reports, but are excluded from Home's
  current total and new-transaction pickers under existing rules.

### Final implementation decisions

- Open is the initial list filter; Closed and All are available.
- Closing/reopening is a staged draft action confirmed by the user and persisted
  on Save. Reopening clears closure date. Only unused accounts can be deleted.
- Name is required on editor save. Initial balance is freely editable.
- Preserve the released built-in image catalog. Store custom overrides in a
  separate table and nullable account FK, avoiding a rebuild of referenced tables.
- Custom images are normalized PNG, at most 512 pixels per dimension and 1 MiB.
  Raw imports are limited to 20 MiB and decoded dimensions to 20000 per axis and
  100 million pixels. Retry normalization at 256 pixels if 512 exceeds 1 MiB.
- Bank logos are bundled resources. Shared bank editing is outside this feature.
- Full account saves invalidate financial/history projections and cursors through
  the existing content revision; favorite-only writes keep the narrower path.

## Database Changes

Execute the following canonical migration as version 4 after versions 1-3, in a
SQLite transaction. Preserve legacy bank text exactly; link exact matching names
without guessing banks or merging case variants. No transactions are rewritten.
Fresh databases and converted exports execute the same migration. Before upgrading
an existing working file, retain its pre-upgrade standalone recovery snapshot.
Replacement imports migrate a staged copy before switching the working database.
No destructive rollback is proposed.

```sql
-- Shared bank identities and portable custom account images.
CREATE TABLE banks (
    id INTEGER PRIMARY KEY,
    name TEXT NOT NULL UNIQUE,
    asset_name TEXT
);
INSERT INTO banks (id,name,asset_name) VALUES
    (1,'PrivatBank','bank_privatbank'),
    (2,'CIBC','bank_cibc'),
    (3,'monobank','bank_monobank');
INSERT INTO banks (name)
SELECT DISTINCT bank FROM accounts
WHERE bank IS NOT NULL AND bank <> '' AND bank NOT IN (SELECT name FROM banks)
ORDER BY bank;

CREATE TABLE account_custom_images (
    id INTEGER PRIMARY KEY,
    png_data BLOB NOT NULL CHECK (typeof(png_data) = 'blob' AND length(png_data) BETWEEN 1 AND 1048576)
);
ALTER TABLE accounts ADD COLUMN bank_id INTEGER REFERENCES banks(id) ON DELETE RESTRICT;
ALTER TABLE accounts ADD COLUMN custom_image_id INTEGER REFERENCES account_custom_images(id) ON DELETE RESTRICT;
UPDATE accounts SET bank_id = (SELECT id FROM banks WHERE name = accounts.bank);
CREATE INDEX idx_accounts_bank ON accounts(bank_id);
CREATE INDEX idx_accounts_custom_image ON accounts(custom_image_id);
PRAGMA user_version = 4;
```

The released migrations remain unchanged. Extend schema validation for version 4
and validate custom image format, dimensions, and size during full import/export
validation. Thumbnail reads remain lazy and do not load all image bytes on launch.

## Tasks

- [x] Resolve pending decisions and finalize migration SQL.
- [x] Update specifications to match implemented behavior.
- [x] Implement and verify schema upgrade and converter compatibility.
- [x] Implement typed account/bank reads and atomic account writes.
- [x] Implement bounded image import, persistence, previews, and fallbacks.
- [x] Implement Accounts list and shared account editor.
- [x] Add seeded bank selection and account-history edit entry point.
- [x] Implement confirmed status/deletion behavior and cross-screen refresh.
- [x] Add synthetic financial, migration, backup, and write-failure checks.
- [x] Build application and test targets without launching Simulator.
- [ ] Verify layout, image selection, dirty cancellation, status actions, and
      navigation on a user-operated device or other explicitly authorized runtime.
- [x] Update documentation and record actual verification results.

## Verification Results

- Generic iPhone application and test target compilation passed with
  xcodebuild build-for-testing and CODE_SIGNING_ALLOWED=NO. Tests were compiled,
  not executed on iOS. The final build log contains no warnings or errors.
- Eight synthetic account-management scenarios passed natively on macOS against
  the production Models, Finance, Data, session, account editor state, and history
  states. The upgrade interruption scenario exercised all six replacement
  boundaries. Native checks reuse the committed suite bodies through an ignored
  local runner; they do not establish iPhone runtime acceptance.
- Verified v3-v4 field preservation, exact bank-name mapping, freely editable
  signed initial balances, unchanged transaction/monthly totals, currency/name
  validation, stale-row/dataset rejection, transactional image rollback, image
  export/import and daily-backup preservation, closure/default clearing,
  reopening, referenced-account deletion protection, unused-account deletion,
  and refresh of both histories while retaining 60 loaded transactions.
- All 24 Python converter tests passed, including v4 bank defaults and preservation
  of all financial reconciliation checks.
- Inspected the prepared bank logo PNG resources. New source/SQL/plan ASCII checks,
  canonical SQL/plan equality, and git diff --check passed.
- No Simulator was launched and no personal database was changed. Synthetic
  fixtures were used for data verification.
- Remaining device acceptance: More/list navigation, both editor entry points,
  bank grouping and logos, long names/amounts, large text, image selection via
  Photos/Files, keyboard/Save/Cancel behavior, status confirmations, and returning
  after account deletion. Keep this plan active until those checks are complete.
