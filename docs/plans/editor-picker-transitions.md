# Transaction Editor Picker Transitions

## Purpose

The supplied device recording shows form values remaining over the category list
while navigation, keyboard dismissal, and sheet contraction happen together.
The current code clears focus in destination onAppear and immediately restores
restingDetent on focus loss, changing presentation geometry during the push.

## Goal

Trial a separate compact category selection sheet above the transaction form.
Present its final compact height from the outset, rather than shrinking a pushed
category list. Preserve the parent form and its draft without resizing it on
selection or cancellation. Device acceptance will decide whether to keep this UX.

## Scope

- Category presentation in transaction creation and editing only.
- Existing account/recipient picker navigation retains its behavior.
- No database, financial, category-list content, or field-order changes.
- Do not launch Simulator under the user's standing instruction.

## Implementation Approach

Present the existing CategoryPickerView inside its own NavigationStack in a native
sheet with a 510-point compact detent and optional manual expansion. Add a Close
button. Selection dismisses the child sheet through its own dismiss environment;
Close or a downward swipe leaves the draft selection unchanged.

Set the picker guard before clearing editor focus. While the child sheet is
presented, do not restore the parent form's compact height. On child dismissal,
release the guard and retain the parent's current resting height without setting
another detent. Explicitly allow interactive dismissal of the child even when
the parent editor has a dirty draft. The parent's discard protection remains.

Remove category routing and source-disappearance contraction from the editor's
NavigationStack. Keep account/recipient routing and its completed-pop handling.
This local presentation change is intentionally easy to reverse after user testing.
Use native presentation without timer delays or custom animation suppression.

## Trial Decision

The user approved trying this variant and may prefer reverting after testing.
The previous delayed contraction worked but felt awkward because the visible
category list moved downward after the navigation push. A successful build does
not establish that this new presentation feels better on-device.

## Database Changes

None.

## Tasks

- [x] Inspect the recording and current keyboard/navigation/detent callbacks.
- [x] Implement the isolated category sheet and remove delayed contraction.
- [x] Compile the category-sheet trial without Simulator execution.
- [x] Update the screen specification and trial verification limits.
- [ ] Verify compact category selection, reachable favorites, category/account/recipient push and pop, search keyboard, cancelled
      back gestures, manual detents, and preserved draft values on a device.

## Verification Results

- Inspected sampled frames from the supplied recording in ignored local storage.
- No private video frames or financial records are added to version control.
- The user confirmed the overlapping form values disappeared on-device.
- Generic iPhone application build passed with signing disabled; the build log
  contains no warnings or errors. git diff --check and authored ASCII checks passed.
- Applied the same navigation guard to source, recipient, and category selection.
  No financial calculations or persisted records changed.
- No Simulator or device was launched by the agent. The user reported that the
  artifact disappeared, then requested keeping the form expanded after picker
  return. Removed the return-time contraction and retained the current detent as
  the new resting height. Device acceptance of this refinement remains pending.

- Latest user steering: category Favorites must remain reachable in a compact
  creation sheet. The previous always-expanded picker behavior is superseded.
  The revised source-disappearance sequencing still requires device verification.
- Revised compact category flow: generic iPhone build passed with signing disabled
  and no warnings/errors. Source and plan ASCII checks and git diff --check passed.
  No Simulator was launched; transition timing and absence of artifacts still need
  a user-operated phone check, including search keyboard and manual expansion.

- Separate category-sheet trial: generic iPhone application build passed with
  signing disabled and no warnings/errors. Source/plan ASCII checks and
  git diff --check passed. No Simulator was launched. Device checks remain:
  opening from amount/notes keyboards, immediate compact presentation, selection
  dismissing only the child, Close/swipe cancellation preserving the selection,
  manual expansion/search, unchanged parent height/draft, and UX preference.
