# INTEGRATE-KE-015 Integration Contract - Partial Key Distribution Fail-Closed

Status: accepted

Created: 2026-05-18

## Source Row

- Worktree source matrix row: `KE-015`
- Integration session: `INTEGRATE-KE-015`
- Title: `Partial key distribution failure keeps sender state honest`
- Historical worktree plan: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-KE-015-plan.md`
- Historical worktree plan status: `accepted`
- Active integration mode: standard worktree-to-main integration, not gap closure

## Row Contract

If a private group key rotation cannot distribute the newly generated key to every active recipient, the sender must not promote the local current epoch, publish a `group:updateKey` event, or send later messages at an epoch that a failed recipient cannot read. The sender may attempt distribution, but partial success must leave sender-visible state honest.

## Integration Decision

Current main already fails closed on explicit partial distribution failure in `rotateAndDistributeGroupKey`: failed recipient delivery prevents local repository promotion, native `group:updateKey`, and group update publication. Current main also treats distribution timeout as fail-closed rather than promoting the timed-out recipient, so the source worktree timeout-promotion variant was not imported.

This session imported only the missing KE-015 row-owned proof delta:

- a rotation use-case test proving explicit partial distribution failure blocks sender promotion and keeps the latest key at epoch `1`;
- a fake-network smoke proving the sender can still deliver a post-failure epoch-1 message to both Bob and Charlie;
- criteria, criteria-test, runner, and live-harness support for `private_partial_key_distribution`;
- a three-party iOS 26.2 proof showing Bob receives the distributed epoch-2 key, Charlie does not, Alice remains at epoch `1`, and Alice's post-failure message remains readable by Bob and Charlie.

No production code was changed for KE-015.

## Owned Files

- `test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart`
- `test/features/groups/integration/group_messaging_smoke_test.dart`
- `integration_test/scripts/group_multi_party_device_criteria.dart`
- `test/integration/group_multi_party_device_criteria_test.dart`
- `integration_test/scripts/run_group_multi_party_device_real.dart`
- `integration_test/group_multi_party_device_real_harness.dart`
- this integration contract
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-breakdown.md`

Inspected and skipped already-present production behavior:

- `lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart`

## Scope Guard

Do not import or repair KE-016+, stale invite ordering, higher-epoch receive repair, pending-key receive repair, concurrent rotation allocation, KE-007/KE-009/KE-017 blockers, BB-007, BB-012, GM-029, ML-012 external-fixture work, source docs, COMPLETE_1 docs, source matrix docs, source `test-inventory.md`, unrelated harness scenarios, UI, media, notification, relay, or broader lifecycle work under this row.

## Device/Relay Proof Profile

- Profile: three-party iOS 26.2 simulator proof.
- Required scenario: `private_partial_key_distribution`.
- Required command shape:
  `MKNOON_RELAY_ADDRESSES='<relay-list>' dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario private_partial_key_distribution -d <alice>,<bob>,<charlie>`.
- Devices used for accepted proof:
  - Alice: `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`
  - Bob: `279B82AE-2BB9-4924-9AAE-581870ED3FA9`
  - Charlie: `116B4AF6-C1A9-4F36-B929-0A7130B5E83C`
- Relay addresses:
  `/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g`

## Required Evidence

- focused KE-015 rotation use-case selector
- adjacent rotation distribution preservation selectors
- full rotation use-case test file
- focused KE-015 fake-network selector
- full isolated group messaging smoke file
- focused and full criteria regression
- runner scenario discovery
- scoped analyzer/format/diff hygiene
- three-party iOS 26.2 live proof for `private_partial_key_distribution`
- named `groups` and `completeness-check` gates, preserving known non-KE-015 residuals

## Final Execution Verdict

Verdict: accepted.

Imported the KE-015 tests, criteria, runner, and live-harness proof artifacts. Production rotation behavior was inspected and left unchanged because current main already fails closed on explicit partial distribution failure.

Accepted files:

- `test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart`
- `test/features/groups/integration/group_messaging_smoke_test.dart`
- `integration_test/scripts/group_multi_party_device_criteria.dart`
- `test/integration/group_multi_party_device_criteria_test.dart`
- `integration_test/scripts/run_group_multi_party_device_real.dart`
- `integration_test/group_multi_party_device_real_harness.dart`
- this integration contract
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-breakdown.md`

Focused and preservation evidence:

- `flutter test --no-pub test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart --plain-name 'KE-015'` PASS (`+1`).
- `flutter test --no-pub test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart --plain-name 'continues distribution'` PASS (`+1`).
- `flutter test --no-pub test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart --plain-name 'distribution timeout'` PASS (`+2`).
- `flutter test --no-pub test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart` PASS (`+24`).
- `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name 'KE-015'` PASS (`+1`).
- `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --concurrency=1` PASS (`+46`).
- `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'private_partial_key_distribution'` PASS (`+1`).
- `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'partial key distribution'` PASS (`+3`).
- `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart` PASS (`+289`).
- `dart run integration_test/scripts/run_group_multi_party_device_real.dart --list-scenarios | rg "private_partial_key_distribution|private_same_epoch_key_conflict|private_stale_lower_key_update"` PASS and listed `private_partial_key_distribution`.
- `dart analyze lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart test/features/groups/integration/group_messaging_smoke_test.dart integration_test/scripts/group_multi_party_device_criteria.dart test/integration/group_multi_party_device_criteria_test.dart integration_test/scripts/run_group_multi_party_device_real.dart integration_test/group_multi_party_device_real_harness.dart` PASS (`No issues found!`).
- `dart format --set-exit-if-changed` on touched Dart files PASS after formatting.
- `git diff --check` PASS before doc closure.

Named gate evidence:

- `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` remains red at `+190 -3` only on preserved non-KE-015 residuals:
  - `BB-007 accepted pending invite joins with exact full config and replays accepted epoch` fails with `Expected: not null / Actual: <null>` at `test/features/groups/integration/invite_round_trip_test.dart:679`.
  - `BB-012 restart recovery drains replay before ack and stays live` fails with `Expected: an object with length of <1> / Actual: WhereIterable<GroupMessage>:[]` at `test/features/groups/integration/group_startup_rejoin_smoke_test.dart:842`.
  - `GM-029 config version monotonicity converges across A/B/C shuffled delivery` fails with `Expected: MemberRole.writer / Actual: MemberRole.reader` at `test/features/groups/integration/group_membership_smoke_test.dart:8144`.
- `./scripts/run_test_gates.sh completeness-check` remains red on the unrelated classification gap `test/shared/fakes/fake_group_pubsub_network_test.dart` (`732/733` classified).

Live proof evidence:

- `private_partial_key_distribution` iOS 26.2 proof PASS.
- Run id: `1779119400443`.
- Shared directory: `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_private_partial_key_distribution_nd6usn`.
- Devices: Alice `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`, Bob `279B82AE-2BB9-4924-9AAE-581870ED3FA9`, Charlie `116B4AF6-C1A9-4F36-B929-0A7130B5E83C`.
- Orchestrator detail: `private_partial_key_distribution proof passed: private_partial_key_distribution verdicts valid for alice, bob, charlie`.
- Proof meaning: Bob stored final key generation `2`; Alice and Charlie ended at key generation `1`; Alice sent `aliceAfterPartialKeyDistributionFailure` at epoch `1`; both Bob and Charlie received the post-failure message.

Skipped/out-of-scope:

- Production timeout-promotion behavior from the source worktree was not imported because current main's stricter timeout fail-closed semantics are safer and already covered by existing timeout selectors.
- KE-016+, stale invite ordering, higher-epoch receive repair, pending-key receive repair, concurrent rotation allocation, KE-007/KE-009/KE-017 blockers, source worktree docs, COMPLETE_1 docs, source matrix docs, source `test-inventory.md`, unrelated harness scenarios, BB-007 repair, BB-012 retention-fixture repair, GM-029 repair, ML-012 external-fixture repair, notification, media, UI, relay, and broader lifecycle work were not imported.

Safe next action: continue with `INTEGRATE-KE-016` after ledger sanity and dirty-state safety checks, preserving KE-007 and KE-009 conflict blockers, ML-012 external-fixture blocker, BB-007/BB-012/GM-029 residual group-gate failures, and the completeness classification gap.
