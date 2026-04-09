# Session UX-006 Plan: Close intro notification copy across local and push-backed paths

## Real scope

- Close row `UX-006` from
  `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules.md`.
- Reuse the existing local-notification copy proof in
  `introduction_listener_test.dart`.
- Add only the missing push-backed fallback copy proof for intro notifications
  so title/body content is pinned for both new-intro and mutual-accept
  notification shapes.

## Closure bar

Session `UX-006` is good enough when the repo has direct automated proof that:

- local new-intro notifications use the expected title/body copy,
- local mutual-accept notifications use the expected title/body copy,
- push-backed intro fallback notifications preserve explicit intro-review and
  mutual-accept title/body content when those payload fields are present, and
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
  `test/features/introduction/application/introduction_listener_test.dart`
  `test/features/push/application/background_push_notification_fallback_test.dart`

When docs and repo evidence disagree, repo code and tests win.

## Session classification

`implementation-ready`

## Exact problem statement

- `introduction_listener_test.dart` already pins the exact local notification
  title/body copy for both new intros and mutual acceptance.
- The remaining gap is the push-backed fallback path: current tests only prove
  generic `intros` routing, not exact intro-specific title/body passthrough.
- Without those fallback regressions, the row remains only partially pinned.

## Files and repos to inspect next

- `test/features/push/application/background_push_notification_fallback_test.dart`
- `lib/features/push/application/background_push_notification_fallback.dart`
- `test/features/introduction/application/introduction_listener_test.dart`

## Existing tests covering this area

- `introduction_listener_test.dart` already proves local `New Introduction`
  and `New Connection` title/body copy.
- `background_push_notification_fallback_test.dart` already proves generic
  `intros` routing, but not intro-specific copy.

## Regression/tests to add first

- Add one fallback regression for a new-intro push payload with explicit
  `title`/`body`.
- Add one fallback regression for a mutual-accept push payload with explicit
  `title`/`body`.

## Step-by-step implementation plan

1. Add the two missing push-fallback copy regressions in
   `background_push_notification_fallback_test.dart`.
2. Run the targeted fallback suite.
3. Run `./scripts/run_test_gates.sh intro`.
4. If green, refresh matrix, inventory, and breakdown for `UX-006`.

## Risks and edge cases

- Keep the scope on copy truth, not routing or deep-link behavior already owned
  by `UX-007`.
- Do not widen into background notification suppression or duplicate-guard
  policy unless the copy regressions expose a real bug.

## Exact tests and gates to run

Direct suite:

```bash
flutter test --no-pub \
  test/features/push/application/background_push_notification_fallback_test.dart
```

Required named gate:

```bash
./scripts/run_test_gates.sh intro
```

## Known-failure interpretation

- If the fallback drops the explicit intro notification title/body, that is a
  current-session product bug.
- If the regressions pass and the gate stays green, the row can close as
  covered.

## Done criteria

- Exact intro-notification copy is covered across local and push-backed paths.
- `./scripts/run_test_gates.sh intro` is green.
- The matrix, inventory, and breakdown are updated truthfully.

## Scope guard

- Do not widen into `UX-007` deep-linking or `UX-011` Orbit banner coverage
  unless the fallback copy regressions reveal a real product gap.

## Accepted differences / intentionally out of scope

- This session does not change product copy.
- This session does not add simulator push smoke coverage.

## Dependency impact

- Later notification routing rows can cite this row-owned proof that the intro
  copy survives both the local listener path and the background fallback path.
