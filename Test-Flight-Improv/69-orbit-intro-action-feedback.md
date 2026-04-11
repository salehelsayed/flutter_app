# 69 - Orbit Intro Action Feedback and Duplicate-Tap Guard

## Closure Verdict

`closed`

## What Is Now Closed

- Report `69` is closed through Session `1` in
  `Test-Flight-Improv/69-orbit-intro-action-feedback-session-breakdown.md`.
- Orbit intro rows now show immediate in-flight feedback on first tap, block
  duplicate `Accept` and `Pass` submits while work is running, and use proper
  Material button semantics instead of the previous raw `GestureDetector`.
- Final verification for the closed seam passed with:
  - `flutter test --no-pub test/features/introduction/presentation/widgets/intro_row_test.dart`
  - `flutter test --no-pub test/features/orbit/presentation/screens/orbit_wired_test.dart`
  - `flutter test --no-pub test/features/orbit/presentation/screens/orbit_intros_wiring_test.dart`
  - `./scripts/run_test_gates.sh intro`
  - `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline`

## Maintenance-Time Safety

- Use
  `Test-Flight-Improv/69-orbit-intro-action-feedback-session-breakdown.md`
  together with
  `Test-Flight-Improv/69-orbit-intro-action-feedback-session-1-plan.md`
  as the closure-time references for what is closed versus intentionally
  unchanged.
- Default maintenance-time safety for this seam is:
  - `flutter test --no-pub test/features/introduction/presentation/widgets/intro_row_test.dart`
  - `flutter test --no-pub test/features/orbit/presentation/screens/orbit_wired_test.dart`
  - `flutter test --no-pub test/features/orbit/presentation/screens/orbit_intros_wiring_test.dart`
  - `./scripts/run_test_gates.sh intro`
  - `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline`

## Residual-Only Items

- None for Report `69`. Existing macOS linker/deployment warnings and
  intermittent `Failed to foreground app; open returned 1` logs were observed
  during the Baseline Gate rerun, but the command exited `0` and this rollout
  does not treat that harness noise as an Orbit intro blocker.

## Problem

The Orbit `Intros` surface currently lets users tap `Accept` or `Pass` with no
immediate visible acknowledgment. The first tap likely succeeds, but the row
does not change until the full intro accept/pass workflow finishes. Users then
tap again because the UI still looks idle.

Repo evidence behind the symptom:

- `OrbitWired._onAcceptIntro(...)` awaits the full intro use case before
  reloading the list in
  `lib/features/orbit/presentation/screens/orbit_wired.dart`.
- `acceptIntroduction(...)` writes local intro state early, then still performs
  outbound delivery work to the introducer and the other party in
  `lib/features/introduction/application/accept_introduction_use_case.dart`.
- the intro CTA in `lib/features/introduction/presentation/widgets/intro_row.dart`
  is a small custom `GestureDetector` with no pressed, disabled, or loading
  state.

## Intended rollout scope

This report is intentionally narrow.

What should change:

- Orbit intro rows gain per-intro in-flight state for `Accept` and `Pass`
- a first tap immediately disables duplicate submits and shows clear feedback
- the intro CTA uses proper Material buttons instead of a raw
  `GestureDetector`

What should not change:

- intro transport, outbox, retry-on-resume, or background lifecycle semantics
- swipe behavior for intro rows
- optimistic protocol changes that rewrite intro status before the existing
  accept/pass use cases run

## Closure bar

Report `69` is closed only when all of the following are true:

- a single tap on Orbit intro `Accept` shows immediate processing feedback
- repeated taps on the same intro while work is in flight do not start repeated
  accept/pass work
- the same duplicate-tap guard applies to `Pass`
- existing intro accept/pass outcomes remain unchanged
- direct Orbit intro regressions and the required named gates pass without
  widening into transport or lifecycle work

## Accepted differences

- intro accept remains durable plus retryable, but this rollout does not claim
  guaranteed completion while the app is immediately backgrounded or locked
- intro transport remains different from 1:1 media/text flows that explicitly
  acquire `bg:begin/bg:end`

## Reopen Only On Real Regression

- Reopen this report only if Orbit intro rows stop acknowledging the first tap
  immediately, repeated taps start multiple accept/pass actions again, or the
  intro CTA regresses away from the landed button/disabled-state semantics.
