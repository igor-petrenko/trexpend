# More Navigation Hub

## Purpose

Keep infrequently used management pages out of the primary tab bar while making
Accounts, Categories, Currencies and later auxiliary features discoverable.

## Goal

Introduce a native More hub with three navigation rows: Accounts, Categories and
Currencies. Add full management screens in separate deliveries after discussing
those screens. Preserve current Home, All, Settings and database recovery behavior.

## Scope

Navigation scaffolding only. No account/category/currency editing, schema changes,
exchange-rate refresh or statistical reports in this delivery. No Simulator launch.

## Implementation Approach

- Use More with the ellipsis symbol. Its own NavigationStack opens destinations
  through standard list rows with an icon, title and trailing navigation indicator.
- Put Accounts, Categories and Currencies in a Management section. Do not render
  empty Statistics or other speculative sections before their features exist.
- Initially provide clearly identified placeholder destinations for the three
  future management screens; do not present nonfunctional edit/save controls.
- Currency management is distinct from the existing display-currency picker in
  Settings. Keep that working preference and database recovery actions accessible.
- Confirmed tab order: Home, All, More, Settings. Settings remains directly
  accessible; existing recovery shortcuts continue selecting the Settings tab.
- More remains reachable without a working database. Preserve the startup
  Import/Reset shortcuts; if Settings moves inside More, route those shortcuts to
  that nested destination explicitly.
- Add only the actual hub/destination scaffolding files under Features/More and
  update RootView. Do not create empty source directories for future editors.

## Database Changes

None.

## Tasks

- [x] Inspect current tabs, Settings and recovery navigation.
- [x] Settle Settings placement with the user.
- [x] Add More hub and the three temporary management destinations.
- [x] Preserve unavailable-database navigation and startup recovery shortcuts.
- [x] Update navigation specifications and verify an iPhone build without launching
  the app or Simulator.

## Verification Results

- Added MoreView with standard list navigation and Accounts/Categories/Currencies
  placeholder destinations. RootView now shows Home, All, More, Settings.
- Settings and startup recovery routing remain unchanged. More has no database
  dependency, so it remains reachable when the ledger is unavailable.
- iOS 27 generic-device build passed with signing disabled and no reported
  compiler warnings. No app or Simulator was launched, per the user's preference.
- Reviewed route ownership, resource-free destination rendering and existing
  generation-based navigation reset. Runtime tab/push navigation was not exercised.
- Documentation and git diff --check passed; authored files are English ASCII.
- Full account, category and currency management remains separate work.

