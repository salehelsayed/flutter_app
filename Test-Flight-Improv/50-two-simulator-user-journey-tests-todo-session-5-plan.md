# Session 5 Plan: Group reaction non-smoke proof and leave-path revalidation

## Real scope

- Close the remaining Session 5 coverage asks for `10.5` and `10.6` from
  `Test-Flight-Improv/50-two-simulator-user-journey-tests-coverage-audit.md`.
- Treat `10.5` as the real missing proof: normal chat-group reaction
  propagation from sender to receiver and back into UI-visible state.
- Treat `10.6` as a revalidation target first, not assumed new work, because
  the current repo already has strong smoke coverage for voluntary leave.
- Do not widen into announcement reliability redesign, intro routing, or
  generic transport work.

## Closure bar

Session 5 is good enough when the repo has direct automated evidence that:

- a normal chat-group message can receive a reaction from another member,
- that reaction is persisted and propagated back into a UI-observable reaction
  stream or rendered state for the original sender in the ordinary group-chat
  path, and
- the leave-group row `10.6` is either honestly reclassified as already
  sufficiently covered by current repo evidence or strengthened with one narrow
  extra proof only if the current smoke coverage turns out to miss a real
  product contract.

The session may finish as mostly test-only, and `10.6` may finish with no code
change if the current smoke coverage is already honest.

## Source of truth

- Active controller doc:
  `Test-Flight-Improv/50-two-simulator-user-journey-tests-todo-session-breakdown.md`
- Proposal/source doc:
  `Test-Flight-Improv/50-two-simulator-user-journey-tests-todo.md`
- Coverage matrix and gap statements:
  `Test-Flight-Improv/50-two-simulator-user-journey-tests-coverage-audit.md`
- Regression policy:
  `Test-Flight-Improv/14-regression-test-strategy.md`
- Gate source of truth:
  `Test-Flight-Improv/test-gate-definitions.md`

When docs disagree with current repo evidence, repo evidence wins.

## Session classification

`implementation-ready`

## Exact problem statement

The current repo already covers most of this area, but the proof is uneven:

- `test/features/groups/application/send_group_reaction_use_case_test.dart`
  and
  `test/features/groups/application/handle_incoming_group_reaction_use_case_test.dart`
  cover send/receive mechanics at the use-case layer.
- `test/features/groups/presentation/group_conversation_wired_test.dart`
  already proves the reaction UI can update from an incoming reaction stream,
  but not that a normal multi-user group path produces that reaction stream.
- `test/features/groups/integration/announcement_happy_path_test.dart`
  proves announcement-group reaction send storage, but the audit correctly
  calls out that ordinary chat-group end-to-end propagation back to the
  original sender is still missing.
- `test/features/groups/integration/group_edge_cases_smoke_test.dart` and
  `test/features/groups/integration/group_membership_smoke_test.dart` already
  provide strong voluntary leave/remove smoke coverage, so `10.6` may already
  be honest without new non-smoke work.

The goal is to add only the minimum direct proof still missing after this
current-repo refresh.

## Files and repos to inspect next

Production files:

- `lib/features/groups/application/send_group_reaction_use_case.dart`
- `lib/features/groups/application/handle_incoming_group_reaction_use_case.dart`
- `lib/features/groups/application/group_message_listener.dart`
- `lib/features/groups/presentation/screens/group_conversation_wired.dart`
- `lib/features/groups/application/leave_group_use_case.dart`

Primary direct tests:

- `test/features/groups/application/send_group_reaction_use_case_test.dart`
- `test/features/groups/application/handle_incoming_group_reaction_use_case_test.dart`
- `test/features/groups/integration/announcement_happy_path_test.dart`
- `test/features/groups/integration/group_edge_cases_smoke_test.dart`
- `test/features/groups/integration/group_membership_smoke_test.dart`
- `test/features/groups/presentation/group_conversation_wired_test.dart`

Likely narrow new integration only if existing suites become too contorted:

- `test/features/groups/integration/group_reaction_roundtrip_test.dart`

## Existing tests covering this area

- `send_group_reaction_use_case_test.dart` already proves reaction creation,
  persistence, and failure behavior at the sender use-case seam.
- `handle_incoming_group_reaction_use_case_test.dart` already proves reaction
  upsert/remove handling at the incoming use-case seam.
- `group_conversation_wired_test.dart` already proves the group conversation
  UI reacts to an incoming `ReactionChange` stream.
- `announcement_happy_path_test.dart` already proves announcement reaction send
  storage, which is adjacent evidence but not the ordinary chat-group path.
- `group_edge_cases_smoke_test.dart` already proves voluntary leave stops
  delivery, and `group_membership_smoke_test.dart` already proves self-removal
  cleanup via the live listener path.

## Regression/tests to add first

- Add the smallest normal chat-group reaction roundtrip proof, preferably in a
  dedicated integration file, that uses the real group listener/reaction path
  rather than only unit-level use cases or announcement-specific wiring.
- Reuse existing group smoke coverage for `10.6` unless execution discovers a
  real leave-path contract that those tests still miss.
- Prefer test-only additions first. Only touch production group reaction or
  listener code if a deterministic failing proof exposes a real gap.

## Step-by-step implementation plan

1. Re-read Session 5 rows in the coverage audit and the current worktree
   versions of the six primary test files above.
2. Reclassify `10.6` against the current smoke coverage before adding any new
   leave-path test.
3. Prefer one narrow normal-group reaction integration proof first:
   sender posts a group message, another member reacts, and the original sender
   observes the persisted reaction change through the ordinary group listener/UI
   seam.
4. Reuse existing group test users, listener helpers, and reaction repos
   instead of inventing a new transport harness.
5. Only add extra leave-path proof if the current smoke coverage is shown to
   miss a real voluntary-leave contract.
6. Run the exact direct Session 5 suites.
7. Run `./scripts/run_test_gates.sh groups`.
8. Run `./scripts/run_test_gates.sh baseline` only if execution touches shared
   Flutter production files beyond group surfaces.

## Risks and edge cases

- A new reaction test can regress into another use-case test unless it proves
  sender-visible roundtrip behavior through the listener/UI seam.
- Announcement-only reaction proof is not enough; the missing gap is ordinary
  chat-group propagation.
- Leave-path work can become redundant churn if `10.6` is already honestly
  covered by the current smoke tests.
- The repo already has unrelated group and conversation changes; execution must
  work with them instead of overwriting them.

## Exact tests and gates to run

Direct suites required for Session 5:

```bash
flutter test test/features/groups/application/send_group_reaction_use_case_test.dart
flutter test test/features/groups/application/handle_incoming_group_reaction_use_case_test.dart
flutter test test/features/groups/integration/announcement_happy_path_test.dart
flutter test test/features/groups/integration/group_edge_cases_smoke_test.dart
flutter test test/features/groups/integration/group_membership_smoke_test.dart
flutter test test/features/groups/presentation/group_conversation_wired_test.dart
```

If execution adds the planned narrow reaction integration file, run it too:

```bash
flutter test test/features/groups/integration/group_reaction_roundtrip_test.dart
```

Required named gate:

```bash
./scripts/run_test_gates.sh groups
```

Conditional named gate:

```bash
./scripts/run_test_gates.sh baseline
```

Run `baseline` only if execution touches shared Flutter production paths beyond
group-owned files.

## Known-failure interpretation

- Treat unrelated dirty-worktree failures as historical noise unless one of the
  exact Session 5 direct suites or the `groups` gate fails.
- If `10.6` remains covered by current smoke tests, that is an accepted
  outcome, not a blocker.

## Done criteria

- Session 5 has direct proof or honest reclassification for `10.5` and `10.6`.
- The exact direct suites are green.
- `./scripts/run_test_gates.sh groups` is green.
- No announcement, transport, or intro scope was pulled in unnecessarily.
- The breakdown ledger is updated with the accepted outcome and exact evidence.

## Scope guard

- No announcement-reliability redesign.
- No generic transport or reconnect work.
- No posts or 1:1 coverage.
- No gate-definition edits unless a new permanent direct suite truly needs
  classification.

## Accepted differences / intentionally out of scope

- Session 5 does not need a brand-new device harness if deterministic group
  integration and widget seams already prove the reaction contract honestly.
- Session 5 may conclude that `10.6` needs no new code because current smoke
  coverage is already sufficient.
- Session 5 does not own the final matrix refresh; Session `10` still does.

## Dependency impact

- Session `5` remains independent of Sessions `1`-`4`, but if execution lands
  any listener or UI seam changes then later group-related maintenance docs in
  Session `10` should be refreshed against them.
