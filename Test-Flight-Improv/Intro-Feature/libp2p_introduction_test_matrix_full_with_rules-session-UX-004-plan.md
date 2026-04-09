# Session UX-004 Plan: Pin the wired confirmation handoff

## Real scope

- Close row `UX-004` from
  `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules.md`.
- Add a narrow row-owned wrapper test that proves `SentConfirmationWired`
  passes the sent result set through to `SentConfirmationScreen` and forwards
  the back-to-conversation callback.
- Keep the session test-only.

## Closure bar

Session `UX-004` is good enough when the repo has direct automated proof that:

- `SentConfirmationWired` renders the provided introduction count and usernames,
- tapping `Back to conversation` still triggers the wrapper callback, and
- the intro gate stays green.

## Source of truth

- Breakdown artifact:
  `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-breakdown.md`
- Source matrix:
  `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules.md`
- Intro inventory:
  `Test-Flight-Improv/Intro-Feature/test-inventory.md`
- Gate definitions:
  `Test-Flight-Improv/test-gate-definitions.md`
- Current tests:
  `test/features/introduction/presentation/screens/sent_confirmation_test.dart`

When docs and repo evidence disagree, repo code and tests win.

## Session classification

`implementation-ready`

## Exact problem statement

- The pure `SentConfirmationScreen` already has coverage for count text,
  username rendering, and the back button callback.
- The wrapper currently has no row-owned proof, so the matrix still treats it
  as open even though the implementation is a pass-through.

## Files and repos to inspect next

- `lib/features/introduction/presentation/screens/sent_confirmation_wired.dart`
- `test/features/introduction/presentation/screens/sent_confirmation_test.dart`

## Existing tests covering this area

- `sent_confirmation_test.dart` already covers the pure screen behavior.
- No current test proves the wired wrapper passes the sent result set and
  callback through unchanged.

## Regression/tests to add first

- Add one small `SentConfirmationWired` widget test that checks rendered count,
  rendered names, and callback passthrough.

## Step-by-step implementation plan

1. Add the new wrapper regression in
   `sent_confirmation_wired_test.dart`.
2. Run the targeted wrapper suite.
3. Run `./scripts/run_test_gates.sh intro`.
4. If green, refresh matrix, inventory, and breakdown for `UX-004`.

## Exact tests and gates to run

Direct suite:

```bash
flutter test --no-pub \
  test/features/introduction/presentation/screens/sent_confirmation_wired_test.dart
```

Required named gate:

```bash
./scripts/run_test_gates.sh intro
```

## Done criteria

- `SentConfirmationWired` is directly covered.
- `./scripts/run_test_gates.sh intro` is green.
- The matrix, inventory, and breakdown are updated truthfully.
