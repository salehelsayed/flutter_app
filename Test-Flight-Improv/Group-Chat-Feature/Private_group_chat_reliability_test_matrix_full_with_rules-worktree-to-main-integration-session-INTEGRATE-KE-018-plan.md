# INTEGRATE-KE-018 Integration Contract - History Replay Epoch Windows

Status: accepted

Created: 2026-05-18

## Source Row

- Worktree source matrix row: `KE-018`
- Integration session: `INTEGRATE-KE-018`
- Title: `History replay respects key epoch windows`
- Historical worktree plan: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-KE-018-plan.md`
- Historical worktree plan status: `accepted`
- Active integration mode: standard worktree-to-main integration, not gap closure

## Row Contract

History replay for a member who is added, removed, and re-added must respect membership/key epoch windows. Charlie may replay pre-removal epoch `1` and post-readd/current epoch `2` messages addressed to Charlie, but removed-window replay must remain inaccessible and must never become Charlie plaintext.

## Integration Decision

Current main already had the meaningful production behavior through recipient-aware replay envelopes, exact key-epoch lookup, pre-join/self-removal replay guards, and adjacent COMPLETE_1 replay-window coverage. This session imported only missing KE-018 row-owned proof surface:

- a direct replay-drain test with `KE-018` selector and recipient-window assertions;
- a `GM-007 KE-018` fake-network selector/title anchor;
- `ke018HistoryReplayEpochWindowProof` criteria validation;
- GM-007 criteria tests requiring the KE-018 proof fields;
- GM-007 live-harness verdict fields for Alice, Bob, and Charlie.

No production code, broad source helper drift, source docs, COMPLETE_1 docs, source matrix docs, source `test-inventory.md`, IR-005 proof fields, runner changes, or unrelated row tests were imported for KE-018.

## Owned Files

- `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`
- `test/features/groups/integration/group_membership_smoke_test.dart`
- `integration_test/scripts/group_multi_party_device_criteria.dart`
- `test/integration/group_multi_party_device_criteria_test.dart`
- `integration_test/group_multi_party_device_real_harness.dart`
- this integration contract
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-breakdown.md`

## Scope Guard

Do not import or repair production replay/key-window behavior already present in main, IR-005 proof fields, source helper rewrites, source docs, COMPLETE_1 docs, source matrix docs, source `test-inventory.md`, run-script churn, KE-019+, KE-007/KE-009 re-reconciliation, stale-invite ordering, concurrent rotation allocation, pending-key receive repair, BB-007, BB-012, GM-029, ML-012 external-fixture work, listener/drain residuals, UI, media, notification, relay, or broader lifecycle work under this row.

## Device/Relay Proof Profile

- Profile: three-party GM-007 live proof required.
- iOS 26.2 live proof: required and run.
- Devices:
  - Alice: `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`
  - Bob: `279B82AE-2BB9-4924-9AAE-581870ED3FA9`
  - Charlie: `116B4AF6-C1A9-4F36-B929-0A7130B5E83C`
- Relay addresses:
  - `/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g`
  - `/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g`

## Required Evidence

- focused KE-018 direct replay-drain selector;
- focused KE-018/GM-007 fake-network selector;
- GM-007 criteria tests with KE-018 proof requirements;
- affected replay-window preservation selectors, preserving known non-KE-018 residuals;
- scoped analyzer/format/diff hygiene;
- fresh iOS 26.2 GM-007 live proof;
- named `groups` and `completeness-check` gates, preserving known non-KE-018 residuals.

## Final Execution Verdict

Verdict: accepted.

Imported only the KE-018 row-owned proof surface. Production replay-window behavior was treated as already present in main and was not reimplemented.

Accepted files:

- `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`
- `test/features/groups/integration/group_membership_smoke_test.dart`
- `integration_test/scripts/group_multi_party_device_criteria.dart`
- `test/integration/group_multi_party_device_criteria_test.dart`
- `integration_test/group_multi_party_device_real_harness.dart`
- this integration contract
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-breakdown.md`

Focused and preservation evidence:

- `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'KE-018'` PASS (`+1`).
- `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'KE-018'` PASS (`+1`).
- `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'GM-007'` PASS (`+7`).
- `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --name 'GK-023|GI-019|GM-033'` remained red at `+0 -3`; individual reruns confirmed preserved non-KE-018 residuals:
  - `GI-019 re-added member replay keeps pre-remove skips removed-window and renders post-readd` fails with `Expected: null / Actual: GroupModel(...)` at `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart:4518`.
  - `GK-023 re-added member skips removed-window replay and renders post-readd replay` fails with `Expected: null / Actual: GroupModel(...)` at `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart:4223`.
  - `GM-033 replay resume rejects removed-window messages after self re-add` fails with `Expected: not null / Actual: <null>` at `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart:3905`.
- `dart analyze integration_test/scripts/group_multi_party_device_criteria.dart test/integration/group_multi_party_device_criteria_test.dart test/features/groups/application/drain_group_offline_inbox_use_case_test.dart test/features/groups/integration/group_membership_smoke_test.dart integration_test/group_multi_party_device_real_harness.dart` PASS (`No issues found!`).
- `dart format --set-exit-if-changed` on the five touched Dart files PASS (`0 changed` after formatting).
- `git diff --check` PASS before doc closure.

Live proof evidence:

- Fresh iOS 26.2 `gm007` proof PASS with run id `1779125525971`, shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_gm007_NqRwIj`, devices Alice `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`, Bob `279B82AE-2BB9-4924-9AAE-581870ED3FA9`, Charlie `116B4AF6-C1A9-4F36-B929-0A7130B5E83C`, and orchestrator detail `gm007 proof passed: gm007 verdicts valid for alice, bob, charlie`.
- Charlie verdict includes `ke018HistoryReplayEpochWindowProof` with `rowId: KE-018`, pre-removal replay received, post-readd replay absent before drain and drained at epoch `2`, removed-window plaintext count `0`, pre-removal epoch `1`, post-readd epoch `2`, and final epoch `2`.

Named gate evidence:

- `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` remains red at `+191 -3`, matching preserved non-KE-018 residuals:
  - `BB-007 accepted pending invite joins with exact full config and replays accepted epoch` fails with `Expected: not null / Actual: <null>` at `test/features/groups/integration/invite_round_trip_test.dart:679`.
  - `BB-012 restart recovery drains replay before ack and stays live` fails with `Expected: an object with length of <1> / Actual: WhereIterable<GroupMessage>:[]` at `test/features/groups/integration/group_startup_rejoin_smoke_test.dart:842`.
  - `GM-029 config version monotonicity converges across A/B/C shuffled delivery` fails with `Expected: MemberRole.writer / Actual: MemberRole.reader` at `test/features/groups/integration/group_membership_smoke_test.dart:8144`.
- `./scripts/run_test_gates.sh completeness-check` remains red on the unrelated classification gap `test/shared/fakes/fake_group_pubsub_network_test.dart` (`732/733` classified).
- Final `git diff --check` PASS after the KE-018 row import.

Skipped/out-of-scope:

- Production replay/key-window behavior was already present and was not changed.
- IR-005 proof fields, source docs, COMPLETE_1 docs, source matrix docs, source `test-inventory.md`, run-script changes, KE-019+, KE-007/KE-009 re-reconciliation, BB-007 repair, BB-012 retention-fixture repair, GM-029 repair, ML-012 external-fixture repair, listener/drain residuals, notification, media, UI, relay, and broader lifecycle work were not imported.

Safe next action: continue with `INTEGRATE-KE-019` after ledger sanity and dirty-state safety checks. Separately, KE-007 and KE-009 remain recorded as `blocked_conflict` until explicitly re-reconciled after KE-017.
