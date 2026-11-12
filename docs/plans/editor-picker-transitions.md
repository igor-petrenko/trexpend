# Transaction Editor Picker Transitions

## Purpose

The supplied device recording shows form values remaining over the category list
while navigation, keyboard dismissal, and sheet contraction happen together.
The current code clears focus in destination onAppear and immediately restores
restingDetent on focus loss, changing presentation geometry during the push.

## Goal

Account/category navigation preserves the draft and uses a stable sheet height
through push and pop. Retain the current sheet height after returning from a
picker, without automatic contraction. Device acceptance must confirm no overlay of
form values, normal back navigation, and correct manual sheet sizing.

## Scope

- Shared transaction editor account, recipient, and category navigation.
- Sheet sizing coordination with keyboard focus and picker lifecycle.
- No database, financial, picker-content, or transaction-field order changes.
- Do not launch Simulator under the user's standing instruction.

## Implementation Approach

Use a small typed NavigationStack path and explicit picker buttons. Mark picker
navigation active before clearing focus, and retain the current detent while a
picker is active. Do not record picker-driven height changes as a new resting
height during navigation. On completed picker disappearance with an empty path,
keep the current detent and adopt it as the new resting height. This leaves an
expanded form expanded even after a later keyboard dismissal; manual resizing
still updates the resting height. Interactive cancelled pops
must retain the active navigation guard. Preserve the draft in its current state
owner. Avoid fixed animation delays and disabling all navigation animations.

The recording and source identify overlapping state changes; the absence of the
visual artifact after this correction still requires a new device recording.

## Database Changes

None.

## Tasks

- [x] Inspect the recording and current keyboard/navigation/detent callbacks.
- [x] Coordinate typed picker routing, focus loss, and retained return height.
- [x] Compile the iPhone application without Simulator execution.
- [x] Update the screen specification and record verification limits.
- [ ] Verify category/account/recipient push and pop, search keyboard, cancelled
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
