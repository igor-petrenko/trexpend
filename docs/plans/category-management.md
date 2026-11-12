# Category Management

## Purpose

Provide category maintenance under More while preserving existing transaction
history, category identities, and the current editor's category defaults.

## Goal

Users can create root categories and subcategories, edit names and icons, move
categories to another parent, manage favorites and visibility, inspect usage, and
reorder siblings. The transaction picker uses the same stored sibling order.
Used categories cannot be deleted. Hiding a parent affects only that category;
active descendants remain reachable through an unselectable parent in the picker.

This document is the implementation plan. Implementation was authorized after the planning discussion. The mockup is illustrative and uses synthetic counts.

## Scope

- More -> Categories, shared create/edit form, parent picker, icon picker, and
  sibling reorder screen.
- Direct transaction counts in the list and direct/subtree usage in the editor.
- Active, Hidden, and All views; name/path search; retained multi-level hierarchy.
- Shared order and icon presentation in the transaction category picker.
- No category merging, transaction reassignment, cascade deletion, image uploads,
  custom category colors, or category restrictions by transaction type.

## Implementation Approach

### Category list

- Replace only the Categories placeholder under More. Keep navigation available
  without a working database, with recovery guidance for unavailable data.
- Use expandable tree rows with icon, name, yellow favorite star, direct-use count,
  and separate disclosure control. Tapping the name opens the editor.
- Show direct child count as secondary text where useful. Usage counts include
  all accounts and all retained transactions, including one count per transfer.
  Parent badges count only transactions assigned to that exact category.
- Read counts through one grouped query using transactions_category_idx, not a
  query for every row. Compute subtree totals from the validated hierarchy and
  direct counts; no persistent counter or monetary calculation is needed.
- Active and Hidden filters retain ancestor context when needed to display
  matching descendants. Clearly label context-only ancestors; filtering never
  changes another category's activity. Search uses full paths to disambiguate
  duplicate names. Do not require globally unique category names.
- The plus button creates a root category. A row action adds a child with that
  parent preselected. Existing default categories follow the same edit/hide/delete
  rules as user-created categories; names are not special protected identifiers.

### Create/edit category

- Use one draft-based full-page form with Cancel and fixed bottom Save.
- Fields: required nonempty name, nullable parent, nullable icon choice, Favorite,
  and Active. Preserve imported empty names on migration, but require a name on
  a subsequent editor save. Allow duplicate names.
- Show read-only direct transaction count, subtree transaction count, and direct
  subcategory count. Explain deletion eligibility rather than showing a button
  that silently does nothing.
- Reuse the existing 17-entry category_icons catalog in a searchable icon grid.
  NULL uses the general fallback; do not introduce parent icon inheritance.
  Preserve compatibility and existing category icon assignments. Additional
  catalog symbols can be considered separately if the current choices are too
  narrow; this migration does not silently expand or replace them.
- Use one visibility control (Active), saved with the draft, rather than duplicate
  Active and immediate Hide actions from the illustrative mockup.
- Confirm discarding a dirty draft. Failed writes preserve it. Save and Cancel
  are disabled only during the write, following existing editor conventions.
- Parent selection excludes self and all descendants. Recheck the entire proposed
  ancestor chain inside the write transaction; the UI filter is not sufficient.
- Reparenting retains the category ID and descendants and appends the moved node
  after the destination's existing siblings. New nodes append similarly. Reordering
  must be an explicit action rather than an incidental effect of renaming.

### Hiding and deletion

- Hiding updates only the chosen category's is_active. Do not cascade visibility
  or favorite changes. Reactivating likewise does not change descendants.
- A hidden parent with active descendants remains a nonselectable structural row
  in the new-transaction picker; expansion stays available. A hidden current
  category remains selectable when editing its existing transaction, matching
  the current validation exception.
- Used categories remain in history and reports. Rename/icon edits update their
  historical presentation via the same ID; financial amounts/dates are unchanged.
- Permit physical deletion only with zero direct transactions AND no children
  of any status. Check both again inside the write transaction and retain the
  existing restricting foreign keys. Confirm before deleting.
- Existing SET NULL foreign keys clear last_created_category_id and
  transfer_category_id when an unused referenced category is deleted. Renaming
  Transfer retains its ID-based default role. Hidden defaults are not offered
  for new operations; keep existing inactive-default guards and require a valid
  user selection when no active default is available. No guessed replacement
  category and no creation of a replacement Transfer record.

### Shared order

- Persist nonnegative integer sort_order per category, scoped to its parent.
  No global unique-order constraint is needed; break ties deterministically by
  name then ID. Initialization follows existing ORDER BY name,id among siblings.
- Build tree traversal from ordered siblings. Use it for management, transaction
  picker trees, full-path search results, and the separate selectable Favorites
  block. Favorite does not reorder the main tree.
- Reorder one sibling level at a time using a native move list with Save/Cancel.
  The main Reorder action targets roots; a parent's row action opens reorder for
  its children. Include hidden siblings with explicit labels so filtering cannot
  accidentally discard or renumber only part of the level.
- Reordering does not change parents. Validate the complete sibling ID set and
  original ordering before atomically storing contiguous positions. Reject stale
  lists after category insertion, deletion, reparenting, or another reorder.
- Store order in the database so imports and backups retain it. Do not use
  UserDefaults or derive the custom order again on every launch.

### Data boundaries and refresh

- Add focused category DTOs, CategoryRead/CategoryWrite helpers, DatabaseStore
  facade methods, and view-owned states following existing account patterns.
- Use the serial database worker, bound values, SQLite transactions, generation
  guards, and original-row checks. Keep SQL and counting outside views.
- Revalidate fresh category activity at transaction save. Refresh editor category
  catalogs on relevant changes without losing amount, date/time, account, notes,
  or the original transaction row used for stale-write protection.
- Publish committed category writes through the session's revision mechanism so
  All, account history, and pickers refresh names/icons/order/activity/defaults.
  Align worker content revision with history invalidation and preserve loaded
  ranges and scroll anchors. Do not recreate navigation stacks for category edits.
- Do not modify transactions to rename, hide, reorder, or reparent a category.

## Database Changes

Schema version 5 is implemented in 005_category_management.sql. Execute
inside the existing migration transaction after versions 1-4:

```sql
ALTER TABLE categories ADD COLUMN sort_order INTEGER NOT NULL DEFAULT 0
    CHECK (typeof(sort_order) = 'integer' AND sort_order >= 0);

WITH ranked AS (
    SELECT id,
           row_number() OVER (
               PARTITION BY parent_id ORDER BY name, id
           ) - 1 AS position
    FROM categories
)
UPDATE categories
SET sort_order = (SELECT position FROM ranked WHERE ranked.id = categories.id);

CREATE INDEX categories_parent_order_idx
    ON categories(parent_id, sort_order, name, id);

PRAGMA user_version = 5;
```

Released migrations remain unchanged. Existing category IDs, names, hierarchy,
activity, favorites, icons, transactions, and settings references are preserved.
The only data initialization is sibling order. Keep the existing parent index
unless measured query plans justify its removal in this migration.

Include the canonical SQL as an Xcode bundle resource; extend DatabaseResources,
DatabaseMigrator, canonical schema validation, and the offline converter. Fresh
creation, reset, supported old imports, and working-file upgrades use the same
chain. Preserve the existing pre-upgrade recovery snapshot and candidate-based
publication path. A failed migration/import must leave the previous database
recoverable. No destructive rollback SQL is proposed.

## Tasks

- [x] Inspect the implemented schema, icons, transaction picker, and FK behavior.
- [x] Confirm independent parent visibility and shared sibling ordering.
- [x] Define proposed screens, persistence rules, and exact migration SQL.
- [x] Implement canonical v5 migration, bundle inclusion, converter, and validation.
- [x] Implement category reads, usage aggregation, and atomic guarded writes.
- [x] Implement tree/filter/search and shared category editor.
- [x] Implement parent/icon selection and sibling reorder UI.
- [x] Update transaction picker order, icons, activity handling, and catalog refresh.
- [x] Verify synthetic migrations, cycle prevention, unchanged financial records,
      usage counts, delete guards, preference references, order preservation,
      stale writes, history refresh, and export/import/backups.
- [x] Build the iPhone app and tests without launching Simulator.
- [x] Update specifications and record actual implementation/check results.
- [ ] Complete user-operated device checks for tree disclosure, editing, icon
      grid, search, reorder, visibility, dirty cancellation, and accessibility.

## Verification Results

- Generic iPhone application and test-target compilation passed with
  xcodebuild build-for-testing and CODE_SIGNING_ALLOWED=NO. The final build log
  contains no warnings/errors. This compiled tests but did not execute them on iOS.
- All 25 Python converter tests passed, including v5 per-parent initialization,
  foreign-key validation, source preservation, and financial reconciliation.
- Eight category scenarios passed natively on macOS against production data and
  state code, reusing the committed suite bodies through an ignored local runner.
  These cover migration preservation/idempotence/rollback, creation/duplicate names,
  reparent append and cycle prevention, independent hiding, shared/partial/stale
  reorder, direct/subtree usage including transfers, deletion/FK/default guards,
  unchanged transaction records/finances, stale dataset/row rejection, export/import
  and daily-backup order, icon/favorite persistence, draft/original-row preservation,
  hidden original-category editing, fresh activity validation, and both histories'
  name/icon refresh while retaining 60 loaded rows.
- The v4 upgrade interruption scenario passed at all six replacement boundaries
  with preserved category metadata and a Before-v5 recovery snapshot. All eight
  existing account-management regression scenarios also passed, including their
  six upgrade-interruption boundaries and custom-image backup checks.
- Canonical migration SQL matches the planned SQL. New source/SQL/plan ASCII checks
  and git diff --check passed. No private data was changed or added to Git.
- No Simulator was launched. Remaining user-operated device acceptance includes
  disclosure/filter context, parent/icon picking, long names and large text,
  reorder gestures, dirty cancellation, hidden parent selection behavior, exact
  scroll position, and VoiceOver. Keep this plan active until acceptance is done.
