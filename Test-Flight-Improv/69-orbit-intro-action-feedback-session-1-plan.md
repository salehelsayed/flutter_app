# Session 1 Plan — Land Immediate Orbit Intro Action Feedback And Duplicate-Tap Guard

## Final Verdict

- `closed`
- Completion auditor result: Session `1` landed as a narrow Orbit intro
  interaction-contract fix, not a transport or lifecycle reopen.
- Closure reviewer result: the closure bar is met; this session should reopen
  only on a real Orbit intro-action regression.

## Closure Addendum

### What landed

- `lib/features/orbit/presentation/screens/orbit_wired.dart` now tracks
  per-introduction processing state, ignores duplicate taps while the intro is
  already in flight, and republishes Orbit view data immediately on first tap.
- `lib/features/orbit/presentation/screens/orbit_screen.dart` and
  `lib/features/introduction/presentation/widgets/intros_tab.dart` now thread
  per-intro processing state into the live Orbit intro rows.
- `lib/features/introduction/presentation/widgets/intro_row.dart` now uses
  proper Material buttons, disables both actions while processing, and shows a
  primary `Accepting...` spinner state.
- `test/features/introduction/presentation/widgets/intro_row_test.dart` now
  proves the processing UI contract, and
  `test/features/orbit/presentation/screens/orbit_wired_test.dart` now proves
  immediate feedback plus duplicate-tap suppression for both `Accept` and
  `Pass`.

### Tests And Gates Actually Run

Direct tests run:

- `flutter test --no-pub test/features/introduction/presentation/widgets/intro_row_test.dart`
- `flutter test --no-pub test/features/orbit/presentation/screens/orbit_wired_test.dart`
- `flutter test --no-pub test/features/orbit/presentation/screens/orbit_intros_wiring_test.dart`

Named gates run:

- `./scripts/run_test_gates.sh intro`
- `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline`

### Maintenance-Time Meaning

- `closed`: the Orbit intro first-tap feedback and duplicate-submit seam is
  now closed.
- `accepted differences`:
  - Session `1` did not reopen intro transport, retry semantics, background
    task acquisition, or swipe behavior.
  - the macOS Baseline Gate still emits existing linker/deployment warnings and
    can log `Failed to foreground app; open returned 1`; the rerun for this
    session still exited `0`, so that harness noise is not treated as an Orbit
    intro blocker.
- `residual-only`:
  - none for this session; future work should reopen only if the in-flight UI
    contract regresses.

## Final Plan

**Date:** 2026-04-09
**Status:** Accepted and closed on 2026-04-09

## real scope

What changes in this session:

- add per-intro in-flight state for Orbit intro `Accept` and `Pass`
- disable repeated taps on the same intro while work is running
- show immediate processing feedback on the affected intro row
- replace the custom intro CTA with proper Material buttons that support
  pressed and disabled states

What does not change in this session:

- no intro transport, retry, background-task, or lifecycle redesign
- no swipe-wrapper removal or swipe-behavior change for intro rows
- no optimistic protocol rewrite that changes intro truth before the existing
  accept/pass use cases run
- no gate-definition changes

## closure bar

Session `1` is sufficient when all of the following are true:

- a single tap on Orbit intro `Accept` shows visible processing feedback
  immediately
- a single tap on Orbit intro `Pass` shows disabled in-flight behavior
  immediately
- duplicate taps on the same intro while work is in flight do not start
  repeated accept/pass work
- the intro CTA now uses proper button semantics with safer hit targets and
  disabled-state handling
- existing accept/pass protocol behavior and resulting intro statuses remain
  unchanged
- direct regressions plus the required `intro` and `baseline` gates prove this
  without widening into transport or lifecycle work

## source of truth

Authoritative sources for this session:

- controlling breakdown:
  `Test-Flight-Improv/69-orbit-intro-action-feedback-session-breakdown.md`
- proposal/spec:
  `Test-Flight-Improv/69-orbit-intro-action-feedback.md`
- gate sources:
  `Test-Flight-Improv/test-gate-definitions.md`
  `Test-Flight-Improv/_current-test-map.md`
- current production seam:
  `lib/features/orbit/presentation/screens/orbit_wired.dart`
  `lib/features/orbit/presentation/screens/orbit_screen.dart`
  `lib/features/introduction/presentation/widgets/intro_row.dart`
  `lib/features/introduction/presentation/widgets/intros_tab.dart`
- nearby in-flight pattern to mirror:
  `lib/features/groups/presentation/widgets/pending_group_invite_card.dart`
  `lib/features/orbit/presentation/screens/orbit_wired.dart`
- current direct proof:
  `test/features/introduction/presentation/widgets/intro_row_test.dart`
  `test/features/introduction/presentation/widgets/intros_tab_test.dart`
  `test/features/orbit/presentation/screens/orbit_intros_wiring_test.dart`
  `test/features/orbit/presentation/screens/orbit_wired_test.dart`

Conflict rules:

- current code and tests beat stale prose
- the breakdown controls scope and order unless current repo evidence proves it
  stale
- `test-gate-definitions.md` and `./scripts/run_test_gates.sh` define the
  named gate contract

## session classification

`implementation-ready`

## exact problem statement

Orbit intro actions currently look idle after the first tap. The row does not
show an immediate in-flight state, so users tap `Accept` or `Pass` multiple
times. The production seam in `orbit_wired.dart` does not guard duplicate
submits per intro, and the current CTA in `intro_row.dart` is a small custom
`GestureDetector` with no pressed or disabled semantics.

This session must fix the interaction contract without changing intro delivery
semantics:

- first tap must visibly register immediately
- duplicate taps on the same intro while work is in flight must no-op
- accept/pass outcomes must remain whatever the current intro use cases already
  produce

## files and repos to inspect next

Primary production files:

- `lib/features/orbit/presentation/screens/orbit_wired.dart`
- `lib/features/orbit/presentation/screens/orbit_screen.dart`
- `lib/features/introduction/presentation/widgets/intro_row.dart`
- `lib/features/introduction/presentation/widgets/intros_tab.dart`

Reference-only compatibility files:

- `lib/features/introduction/application/accept_introduction_use_case.dart`
- `lib/features/introduction/application/pass_introduction_use_case.dart`
- `lib/features/groups/presentation/widgets/pending_group_invite_card.dart`

Primary direct tests:

- `test/features/introduction/presentation/widgets/intro_row_test.dart`
- `test/features/orbit/presentation/screens/orbit_wired_test.dart`
- `test/features/orbit/presentation/screens/orbit_intros_wiring_test.dart`

Compatibility-reference tests only if required:

- `test/features/introduction/presentation/widgets/intros_tab_test.dart`
- `test/features/introduction/presentation/widgets/intros_tab_extended_test.dart`
- `test/features/orbit/presentation/widgets/swipeable_friend_row_test.dart`

## existing tests covering this area

Already useful coverage exists:

- `test/features/introduction/presentation/widgets/intro_row_test.dart`
  proves the basic CTA and status rendering states
- `test/features/introduction/presentation/widgets/intros_tab_test.dart`
  proves the intro widget callback wiring
- `test/features/orbit/presentation/screens/orbit_intros_wiring_test.dart`
  proves intro accept/pass use-case behavior at the wiring level
- `test/features/orbit/presentation/screens/orbit_wired_test.dart`
  already covers Orbit intro presence and related Orbit surface behavior

What is still missing today:

- no proof that a processing state is shown immediately after the first tap
- no proof that duplicate taps on the same intro are blocked while processing
- no proof that the real Orbit screen honors the new in-flight guard, not just
  the isolated intro widget

## regression/tests to add first

Add or update these direct regressions before considering the session done:

1. In `test/features/introduction/presentation/widgets/intro_row_test.dart`
- add processing-state coverage that proves the primary CTA renders disabled
  feedback and the secondary CTA is disabled while work is running
- prove the new CTA still renders the existing non-processing states correctly

2. In `test/features/orbit/presentation/screens/orbit_wired_test.dart`
- add a delayed-accept regression where the first tap enters processing
  immediately and a second tap on the same intro does not start a second
  action
- add the same duplicate-tap guard proof for `Pass` if the implementation
  shares the same state path

3. In `test/features/orbit/presentation/screens/orbit_intros_wiring_test.dart`
- keep the accept/pass outcome proof green after the UI contract change so the
  repo does not confuse UX improvement with protocol change

## step-by-step implementation plan

1. Add the focused regressions in the intro-row and Orbit screen suites first
   so the in-flight UX contract is explicit.
2. Add a per-intro processing set to
   `lib/features/orbit/presentation/screens/orbit_wired.dart`.
3. Guard `_onAcceptIntro(...)` and `_onPassIntro(...)` so repeated taps on the
   same intro while processing return immediately, and clear the in-flight
   state in `finally`.
4. Thread the processing state through `OrbitIntrosViewData` in
   `lib/features/orbit/presentation/screens/orbit_screen.dart`.
5. Update `lib/features/introduction/presentation/widgets/intro_row.dart` to
   accept processing-state inputs and render proper Material buttons instead of
   the custom `GestureDetector`.
6. Keep `lib/features/introduction/presentation/widgets/intros_tab.dart`
   source-compatible by defaulting the new processing input to `false` outside
   the Orbit path unless repo evidence proves the widget itself must own the
   state.
7. Run the direct regressions first, then the named `intro` and `baseline`
   gates.
8. Stop the session if the direct tests prove that UI-only in-flight state is
   insufficient and the work would need transport or lifecycle changes.

## risks and edge cases

- failed accept/pass must clear the in-flight state so the row does not remain
  disabled
- listener-driven row refreshes must not strand a stale processing flag
- the new CTA must preserve current copy and status logic for accepted, passed,
  expired, already-connected, and blocked rows
- swipe-delete behavior must remain intact even though the row child is gaining
  proper buttons

## exact tests and gates to run

Direct tests:

- `flutter test --no-pub test/features/introduction/presentation/widgets/intro_row_test.dart`
- `flutter test --no-pub test/features/orbit/presentation/screens/orbit_wired_test.dart`
- `flutter test --no-pub test/features/orbit/presentation/screens/orbit_intros_wiring_test.dart`

Required named gates:

- `./scripts/run_test_gates.sh intro`
- `./scripts/run_test_gates.sh baseline`

## known-failure interpretation

- a failure in the new intro-row or Orbit direct tests is a blocker for this
  session
- if `intro` or `baseline` fails in an unrelated area, name the exact failing
  file and keep it documented as pre-existing only when the failure is clearly
  outside the touched Orbit intro seam
- do not “fix while here” unrelated transport, posts, groups, or startup
  failures just to make this session look closed

## done criteria

- the real Orbit intro row shows immediate processing feedback after one tap
- duplicate taps on the same intro while processing do not start repeated work
- the CTA is implemented with proper button semantics
- direct tests and required gates pass, or unrelated pre-existing failures are
  explicitly documented

## scope guard

- do not change intro transport, reliable outbox behavior, retry-on-resume,
  bridge budgets, or background-task acquisition
- do not remove intro swipe affordances
- do not add optimistic intro-state mutation outside the current intro use case
  flow
- do not expand this session into a general Orbit performance redesign

## accepted differences / intentionally out of scope

- no send-then-lock parity work for intro accept
- no `bg:begin/bg:end` addition to the intro path
- no transport-gate validation unless repo evidence during execution proves the
  session widened beyond the local Orbit intro seam

## dependency impact

- later work that wants deeper intro accept perceived-speed improvements can
  reuse this in-flight UI contract rather than starting from an idle row again
- if this session lands cleanly, any future transport/background parity work
  should be treated as a separate reliability report rather than a follow-up
  hidden inside this session
