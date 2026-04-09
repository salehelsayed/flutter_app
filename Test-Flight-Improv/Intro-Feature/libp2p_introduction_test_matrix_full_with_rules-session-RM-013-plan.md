# Session RM-013 Plan: Avatar retry failure must not roll back mutual-accept side effects

## Real scope

- Close row `RM-013` from
  `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules.md`.
- Reuse the existing system-message and notification proof already in the repo.
- Add the missing row-owned regression for avatar retry failure after mutual
  acceptance so contact creation remains durable.

## Closure bar

Session `RM-013` is good enough when the repo has direct automated proof that:

- mutual acceptance still creates the contact and system message,
- the repo already retains notification proof for the mutual-accept path, and
- an avatar retry failure does not roll back the created contact or system
  message.

## Source of truth

- Breakdown artifact:
  `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-breakdown.md`
- Source matrix:
  `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules.md`
- Intro inventory:
  `Test-Flight-Improv/Intro-Feature/test-inventory.md`
- Gate definitions:
  `Test-Flight-Improv/test-gate-definitions.md`
- Current code:
  `lib/features/introduction/application/handle_mutual_acceptance_use_case.dart`
- Current tests:
  `test/features/introduction/application/create_connection_on_mutual_acceptance_test.dart`
  and
  `test/features/introduction/application/introduction_listener_test.dart`

When docs and repo evidence disagree, repo code and tests win.

## Session classification

`implementation-ready`

## Exact problem statement

- The repo already proves the system message and the local new-connection
  notification in adjacent tests.
- The breakdown still marks this row partial because no regression proves that a
  failed avatar retry remains fire-and-forget and does not undo the contact.

## Files and repos to inspect next

- `lib/features/introduction/application/handle_mutual_acceptance_use_case.dart`
- `test/features/introduction/application/create_connection_on_mutual_acceptance_test.dart`
- `test/features/introduction/application/introduction_listener_test.dart`

## Existing tests covering this area

- `create_connection_on_mutual_acceptance_test.dart` already proves contact
  creation, direction-aware keys, and system-message insertion.
- `introduction_listener_test.dart` already proves the local new-connection
  notification on mutual acceptance.
- No current regression covers avatar retry failure after the contact exists.

## Regression/tests to add first

- Add a `handleMutualAcceptance(...)` regression where the avatar download
  returns `null`, retries once, then fails, while the created contact and system
  message remain intact.

## Step-by-step implementation plan

1. Add the avatar retry failure regression.
2. Run the targeted mutual-acceptance suite.
3. Run `./scripts/run_test_gates.sh intro`.
4. If green, refresh matrix, inventory, and breakdown for `RM-013`.

## Risks and edge cases

- Keep the proof scoped to durability of contact/system-message side effects.
- Do not widen into push notification payload content or full routing rows.

## Exact tests and gates to run

Direct suite:

```bash
flutter test --no-pub \
  test/features/introduction/application/create_connection_on_mutual_acceptance_test.dart
```

Required named gate:

```bash
./scripts/run_test_gates.sh intro
```

## Known-failure interpretation

- If the contact disappears after the avatar retry fails, that is a current
  product bug in the mutual-acceptance durability path.
- If the retry never happens when the first download returns `null`, that is a
  current retry-path bug.

## Done criteria

- Avatar retry failure no longer leaves this row as a test gap.
- `./scripts/run_test_gates.sh intro` is green.
- The matrix, inventory, and breakdown are updated truthfully.

## Scope guard

- Do not refactor avatar download orchestration unless the regression exposes a
  real behavior gap.

## Accepted differences / intentionally out of scope

- This session does not add push notification content assertions.
- This session does not add multi-device avatar synchronization proof.

## Dependency impact

- Later reliability docs can cite this regression as the mutual-accept avatar
  no-rollback proof.
