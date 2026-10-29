# Preserve History Position Across Tabs

## Purpose

Returning to All or an open account history currently restarts its view task,
replaces loaded pages with the first 50 rows, and leaves SwiftUI reconciling a
previous scroll offset against a shorter list. This can move the visible date.

## Goal

Switching tabs preserves independent history content, loaded pages, and scroll
position. Returning to Home keeps its open account destination. Explicit refresh
reloads history, while a changed dataset clears old navigation/content safely.

## Scope

Account and All history appearance/loading behavior and focused regression tests.
No database migration, financial changes, persistent cross-launch scroll storage,
editor invalidation framework, or unrelated navigation redesign.

## Implementation Approach

- Distinguish appearance loading from explicit refresh in both history states.
- Ensure existing content for the same generation/account/display currency/month
  is reused when a view task restarts. Do not truncate rows or reset its cursor.
- Use that path on appearance and ordinary foregrounding. No background source
  changes are supported; import/reset generation changes and display currency/month
  changes still invalidate the content. Future writes must explicitly invalidate it.
- Keep explicit pull-to-refresh and Retry as actual reloads. Preserve request and
  cancellation guards and page-error retry semantics.
- Initially preserve native ScrollView ownership and stable IDs. Verify tab switching
  with multiple loaded pages. Add explicit scroll anchoring only if native retention
  still moves after fixing the demonstrated content replacement.
- Back out of an account and open it again: a fresh account screen starts at the top.
  Retention applies while its navigation destination remains open. App relaunch is
  not required to restore scroll positions.

## Database Changes

None.

## Tasks

- [x] Inspect appearance tasks, state loading, and tab/navigation ownership.
- [x] Add ensure-loaded behavior and use it for appearance/foreground events.
- [x] Test retained pages/cursors without a fresh database read and explicit refresh.
- [ ] Verify build and account/All tab switching on the existing Simulator.
- [x] Update screen behavior documentation and record verification results.

## Verification Results

- Added ensureLoaded to both states and routed view appearance/foregrounding through
  it. Explicit refresh/retry retains the existing actual-load behavior.
- iOS 27 build succeeded. All 13 focused account/All history tests passed, with no
  failures or skips. Regression assertions retain all 65 loaded rows and their
  snapshot/cursor even while the store is closed, proving appearance did not query
  and replace them. Currency changes and replacement still invalidate correctly;
  explicit refresh still returns the first page.
- Native account navigation opened successfully. CUA drag/wheel inputs and MCP
  scroll gestures did not reliably move the displayed list; MCP repeatedly reported
  an unsettled runtime snapshot. Therefore deep-scroll tab retention could not be
  visually confirmed in this run. The Simulator was not rebooted or erased, and
  app CPU was idle when checked. Do not infer visual success from the tool's gesture
  success status. The runtime task above remains pending and this plan stays active.
- No explicit scroll anchoring was introduced without evidence it is needed after
  removing the demonstrated content-replacement cause. No schema/data changes.
- Documentation, authored ASCII, and diff whitespace checks are recorded at completion.
