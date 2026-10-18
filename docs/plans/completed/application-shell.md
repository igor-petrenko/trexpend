# Application Shell

## Purpose

Replace the branded placeholder with the first runnable navigation structure so
the application can grow in small, inspectable steps without mixing UI, storage,
and financial logic.

## Goal

The app launches into Home with Home, All, and Settings tabs. Each tab has its own
NavigationStack. With storage not yet implemented, financial screens explicitly
show that no database is loaded, rather than an empty ledger or zero balances.
The existing icon, logo, Blue Slate accent, and fixed light appearance remain.

Implemented and verified on 2026-10-17. Storage and financial UI remain later stages.

## Scope

Include root ownership, tab selection, minimal screen views, and no-database
presentation. Exclude SQLite, file access, import/export, financial calculations,
transaction editing, account/category management, and fake financial records.

The next stage is [financial foundations](financial-foundations.md). Storage and
the functional import entry point follow those foundations, as ordered in the
[architecture](../../architecture.md).

## Implementation Approach

### Existing baseline

- TrexpendApp currently constructs ContentView, the branded placeholder.
- The Xcode project is apps/ios/Trexpend/Trexpend.xcodeproj, with a synchronized
  source folder at apps/ios/Trexpend/Trexpend/.
- The target is iPhone/iOS 27 with MainActor default isolation. Preserve its current
  language, signing, deployment, and concurrency settings.
- At planning time, no app storage layer or test target existed. Stage 2 adds the test target.

### Launch and ownership

1. TrexpendApp constructs and retains one AppSession for the running app.
2. TrexpendApp gives that instance to RootView using explicit injection.
3. RootView owns the selected tab as local view state and constructs the three
   tab roots. Each root owns its navigation stack.
4. Home and All read database availability from the shared session. In this
   stage its only real state is no database; do not simulate an imported dataset.
5. Settings contains only the minimal no-database presentation needed for the
   shell. Functional preference controls and file actions arrive with storage.

AppSession is a small MainActor observable object retained at the application
root, not recreated by a view's body. Selected tab and navigation stay in the
views. Do not add generation/revision counters before operations exist to change
them. Extend the session when database opening and replacement are implemented.

There is no database startup task, spinner, artificial delay, or filesystem scan
in this stage. Opening the shell should not wait for the finance or storage work.
The Simulator operating-system boot time is separate from app startup.

### Files

All paths below are relative to apps/ios/Trexpend/Trexpend/:

| File | Planned responsibility |
| --- | --- |
| TrexpendApp.swift | Retain AppSession, construct RootView, preserve light appearance |
| App/AppSession.swift | Observable database availability, initially no database |
| App/RootView.swift | Selected tab, native tabs, per-tab navigation roots |
| Features/Home/HomeView.swift | Home title and honest no-database presentation |
| Features/Transactions/History/AllHistoryView.swift | All title and no-database presentation |
| Features/Settings/SettingsView.swift | Settings title and minimal shell content |
| ContentView.swift | Retire once RootView replaces all references |

An AppTab value type can be declared with RootView unless it warrants a separate
file. A small repeated no-database view can live beside RootView initially. Do not
create a shared component library for a label or a feature state object for a
screen that does not load anything yet.

AppDependencies remains the agreed construction point for future services, but
is not needed as a one-property wrapper around AppSession. Add it during the
storage stage when DatabaseStore and the file/settings components actually exist.
Create no empty Data, Finance, Files, or Models directories in this stage.

### Navigation and presentation

- Start on Home after a fresh launch; persist no selected-tab preference yet.
- Keep all three tabs reachable without a loaded database.
- Use the existing restrained appearance and standard native controls.
- Do not show made-up accounts, balances, or transaction lists.
- Do not add inactive Import, Export, Save, or Create buttons. The functional
  first-import action is part of the storage stage; this shell is an intermediate
  developer checkpoint, not a first usable release.
- Introduce account-history destinations and editor sheets only with their real
  screens. No global router, empty destination enum, or navigation service is needed.
- Use English UI text and preserve Dynamic Type and accessibility labels.

### Risks and unresolved requirements

No outstanding financial or schema choice blocks this stage. Exact empty-state
wording and native tab symbols are presentation choices to review in Simulator.
The full first-launch import workflow is intentionally incomplete until storage.
Root lifetime and source target membership must be checked during implementation.

## Database Changes

None. Do not open, copy, modify, or bundle any personal database.

## Tasks

- [x] Add minimal root/session ownership.
  - [x] Add AppSession and retain one instance in TrexpendApp.
  - [x] Add RootView with local tab selection and explicit session injection.
- [x] Add the three real tab roots.
  - [x] Add HomeView and AllHistoryView with no-database presentation.
  - [x] Add the minimal SettingsView.
  - [x] Give each tab its own NavigationStack.
  - [x] Preserve assets, fixed light appearance, and accessibility behavior.
- [x] Replace the old placeholder without leaving duplicate entry points.
  - [x] Remove ContentView only after references and previews are replaced.
  - [x] Confirm new physical files belong to the application target.
- [x] Verify the shell.
  - [x] Build with the installed iOS 27 SDK without lowering the target.
  - [x] Launch in an already booted Simulator and switch among all tabs.
  - [x] Verify fresh launch starts on Home and shows no fake financial data.
  - [x] Compile no-database preview declarations; verify larger text and light appearance in Simulator.
  - [x] Confirm no database files or preferences are created by the shell.
- [x] Update architecture/development status and record actual verification.

## Verification Results

Completed on 2026-10-17 with Xcode 27.0 (27A266a), Swift 6.4, and iPhone 18 Pro
Simulator running iOS 27.0.

- The application built successfully with its existing deployment/isolation settings.
- New synchronized source files compile in the app target; ContentView was removed.
- Home, All, and Settings rendered, and selected-tab changes were confirmed from
  runtime UI snapshots. Touch down/up with a short hold worked where the automation
  tool's instantaneous taps did not change selection.
- Stop/relaunch returned to Home. No fake accounts, totals, or write actions appeared.
- The no-database layout remained readable at accessibility-extra-extra-extra-large
  text size; Simulator text size was restored to its prior large setting.
- Preview declarations compiled. Layout was rendered in Simulator; a separate
  interactive Xcode Canvas preview session was not run.
- The app container contained zero database files and no application preference
  file after launch. Personal databases were not bundled or accessed by the shell.
- A Device Hub inspection tool stalled during verification; subsequent screenshot
  and runtime checks completed. No app workaround or artificial delay was added.
- English/ASCII, local links, project plist, and diff whitespace checks passed.
