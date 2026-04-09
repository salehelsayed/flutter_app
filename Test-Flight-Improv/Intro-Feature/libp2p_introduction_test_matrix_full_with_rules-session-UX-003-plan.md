# Session UX-003 Plan: Prove the wired picker full flow

## Real scope

- Close row `UX-003` from
  `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules.md`.
- Add row-owned proof that `FriendPickerWired` loads contacts, filters via
  search, updates selection state, sends introductions, exposes live progress,
  and returns the sent intro list through the parent callback.
- Keep the session test-only unless the new flow proof exposes a real bug.

## Closure bar

Session `UX-003` is good enough when the repo has direct automated proof that:

- the wired picker shows its loading state before contacts arrive,
- search and selection update the real wired picker state,
- sending intros exposes real progress while work is still in flight,
- the picker returns the final introduction list through
  `onIntroductionsSent`, and
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
  `test/features/introduction/presentation/screens/friend_picker_wired_test.dart`
  `test/features/introduction/presentation/screens/friend_picker_test.dart`

When docs and repo evidence disagree, repo code and tests win.

## Session classification

`implementation-ready`

## Exact problem statement

- The pure `FriendPickerScreen` widget already covers search, selection, and
  progress visuals in isolation.
- The wired wrapper currently only proves filtering and re-introduction
  eligibility.
- The row still lacks one integrated proof that the actual wired picker carries
  those states through loading, send progress, and the parent callback path.

## Files and repos to inspect next

- `test/features/introduction/presentation/screens/friend_picker_wired_test.dart`
- `lib/features/introduction/presentation/screens/friend_picker_wired.dart`
- `lib/features/introduction/presentation/screens/friend_picker_screen.dart`

## Existing tests covering this area

- `friend_picker_test.dart` covers the pure screen-state matrix.
- `friend_picker_wired_test.dart` covers filtering and same-pair reselection.
- No current wired test proves the full load/search/select/send/progress/callback
  path end to end.

## Regression/tests to add first

- Add one `FriendPickerWired` integration-style widget test that runs the full
  flow with a delayed fake transport so progress becomes observable before the
  callback resolves.

## Step-by-step implementation plan

1. Add the full-flow regression in
   `friend_picker_wired_test.dart`.
2. Run the targeted wired picker suite.
3. Run `./scripts/run_test_gates.sh intro`.
4. If green, refresh matrix, inventory, and breakdown for `UX-003`.

## Risks and edge cases

- Keep the assertions on the real row contract: loading, search, selection,
  progress, and callback output.
- Do not widen into intro delivery correctness, retry tiers, or parent route
  ownership outside the picker contract.

## Exact tests and gates to run

Direct suite:

```bash
flutter test --no-pub \
  test/features/introduction/presentation/screens/friend_picker_wired_test.dart
```

Required named gate:

```bash
./scripts/run_test_gates.sh intro
```

## Known-failure interpretation

- If the wired picker never exposes progress, loses selection state, or fails
  to return the introductions list, that is a current-session product bug.
- If the new regression passes and the gate stays green, the row can close as
  covered.

## Done criteria

- The wired picker full flow is directly covered.
- `./scripts/run_test_gates.sh intro` is green.
- The matrix, inventory, and breakdown are updated truthfully.

## Scope guard

- Do not widen into `UX-004`, `UX-006`, or intro transport rows unless the
  direct picker flow reveals a real defect.

## Accepted differences / intentionally out of scope

- This session does not add new production behavior unless the full-flow test
  exposes one.
- This session does not add simulator or parent-route smoke coverage.

## Dependency impact

- Later confirmation and notification rows can cite this row-owned picker test
  as the proof that the wired picker hands off truthful sent-intro results to
  its parent flow.
