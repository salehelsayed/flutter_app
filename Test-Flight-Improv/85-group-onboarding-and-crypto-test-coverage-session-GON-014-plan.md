# GON-014 Plan: Partition-Heal Durable Group Inbox Recovery

## real scope

- Tighten the focused fake-network partition/heal recovery proof for TC-19.
- Keep fake-network recovery evidence separate from real bridge/GossipSub simulator recovery residuals.
- Avoid adding a parallel `group_partition_heal_test.dart` when the existing recovery suite already owns this behavior.

## closure bar

- A partitioned group member misses live delivery while three messages are sent.
- The missed messages are staged in durable group inbox storage and replay through cursor-ordered drain.
- After heal, live delivery resumes and the receiver has every expected message exactly once.

## source of truth

- Active session contract: `Test-Flight-Improv/85-group-onboarding-and-crypto-test-coverage-session-breakdown.md`, session `GON-014`.
- Product intent: `Test-Flight-Improv/85-group-onboarding-and-crypto-test-coverage.md`, TC-19 and D-5.

## session classification

`implementation-ready`

## exact problem statement

Report 85's TC-19 asks for a partition/heal proof with three missed durable-inbox messages plus resumed live delivery. The existing `group_resume_recovery_test.dart` test already proved the right mechanism, but only with two missed messages. The test should match the documented contract directly.

## files and repos to inspect next

- `test/features/groups/integration/group_resume_recovery_test.dart`
- `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`
- `lib/features/groups/application/rejoin_group_topics_use_case.dart`

## existing tests covering this area

- `group_resume_recovery_test.dart` already covers cursor-ordered inbox drain, duplicate live+inbox dedupe, and partition/heal recovery.
- GON-013 revalidated the existing partition/heal test before this tightening.

## regression/tests to add first

- Extend the existing partition/heal test to stage and drain three missed split-window messages.

## step-by-step implementation plan

1. Update the existing partition/heal test from two split-window messages to three.
2. Assert three durable inbox stores and three cursor retrieval calls.
3. Re-run the focused test by exact name.
4. Update Report 85 and the ledger to mark TC-19 fake-network recovery covered with real-network residuals.

## risks and edge cases

- This still does not prove real Go bridge/GossipSub recovery under a physical network partition.
- The cursor assertions must remain order-specific so replay order regressions are visible.

## exact tests and gates to run

- `flutter test test/features/groups/integration/group_resume_recovery_test.dart --plain-name "temporary partition replays missed backlog in cursor order and resumes live delivery after heal"`

## known-failure interpretation

- A failure means the fake-network durable inbox recovery contract regressed and TC-19 cannot close locally.

## done criteria

- The focused test passes with three missed inbox messages and resumed live delivery.
- Docs record fake-network coverage as closed and real-network simulator recovery as residual under GON-010/GON-013.

## scope guard

- Do not claim real bridge/GossipSub recovery without a configured simulator run.

## accepted differences / intentionally out of scope

- A dedicated `group_partition_heal_test.dart` is unnecessary while the existing recovery suite owns the same contract.

## dependency impact

- GON-015 can treat TC-19 as covered for fake-network durable-inbox recovery, with real-network recovery still mapped to simulator/relay residual rows.
