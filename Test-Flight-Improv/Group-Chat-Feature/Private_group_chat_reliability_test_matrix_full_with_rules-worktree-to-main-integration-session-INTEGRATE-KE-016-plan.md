# INTEGRATE-KE-016 Integration Contract - Stale Re-Invite Obsolete Key Rejection

Status: accepted

Created: 2026-05-18

## Source Row

- Worktree source matrix row: `KE-016`
- Integration session: `INTEGRATE-KE-016`
- Title: `Re-invite package cannot carry an obsolete key after another rotation`
- Historical worktree plan: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-KE-016-plan.md`
- Historical worktree plan status: `accepted`
- Active integration mode: standard worktree-to-main integration, not gap closure

## Row Contract

If Charlie receives an epoch-N invite, then Alice rotates the private group to epoch N+1 before Charlie accepts, Charlie must reject the stale epoch-N package or accept only the current package/key. Charlie must not become active at epoch N while Alice and Bob speak epoch N+1, must not downgrade local key state, and must not receive removed-window plaintext.

## Integration Decision

Current main already had the production stale-invite safeguards:

- incoming stale pending invites cannot replace a newer pending re-add package;
- accepting an invite is rejected when local group/key state is newer than the invite package.

This session imported only the missing KE-016 row-owned proof delta:

- KE-016 anchors on the existing stale accept and stale replacement host tests;
- `ke016StaleReinviteProof` criteria validation for `private_stale_invite_readd`;
- criteria fixtures and negative assertions that reject missing KE-016 proof, missing stale-reject proof, and removed-window leakage;
- live-harness verdict fields for Alice, Bob, and Charlie.

No production code was changed for KE-016.

## Owned Files

- `test/features/groups/application/accept_pending_group_invite_use_case_test.dart`
- `test/features/groups/integration/invite_round_trip_test.dart`
- `integration_test/scripts/group_multi_party_device_criteria.dart`
- `test/integration/group_multi_party_device_criteria_test.dart`
- `integration_test/group_multi_party_device_real_harness.dart`
- this integration contract
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-breakdown.md`

Inspected and skipped already-present production behavior:

- `lib/features/groups/application/handle_incoming_group_invite_use_case.dart`
- `lib/features/groups/application/accept_pending_group_invite_use_case.dart`

## Scope Guard

Do not import RA-004 stale-invite-before-readd proof fields, KE-017 higher-epoch receive repair, KE-018 history replay, concurrent rotation allocation, pending-key receive repair, source docs, COMPLETE_1 docs, source matrix docs, source `test-inventory.md`, unrelated harness scenarios, BB-007, BB-012, GM-029, ML-012 external-fixture work, UI, media, notification, relay, or broader lifecycle work under this row.

## Device/Relay Proof Profile

- Profile: three-party iOS 26.2 simulator proof.
- Required scenario: `private_stale_invite_readd`.
- Required command shape:
  `MKNOON_RELAY_ADDRESSES='<relay-list>' dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario private_stale_invite_readd -d <alice>,<bob>,<charlie>`.
- Devices used for accepted proof:
  - Alice: `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`
  - Bob: `279B82AE-2BB9-4924-9AAE-581870ED3FA9`
  - Charlie: `116B4AF6-C1A9-4F36-B929-0A7130B5E83C`
- Relay addresses:
  `/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g`

## Required Evidence

- focused KE-016 stale-accept selector
- focused KE-016 stale re-add selector
- focused and full criteria regression
- runner scenario discovery
- affected ML-019 and GM-021 preservation selectors
- native GM-021 validator preservation
- scoped analyzer/format/diff hygiene
- three-party iOS 26.2 live proof for `private_stale_invite_readd`
- named `groups` and `completeness-check` gates, preserving known non-KE-016 residuals

## Final Execution Verdict

Verdict: accepted.

Imported the KE-016 test anchors, criteria validator, criteria fixtures, negative criteria assertions, and live-harness proof artifacts. Production stale invite behavior was inspected and left unchanged because current main already rejects stale replacement and stale accept paths.

Accepted files:

- `test/features/groups/application/accept_pending_group_invite_use_case_test.dart`
- `test/features/groups/integration/invite_round_trip_test.dart`
- `integration_test/scripts/group_multi_party_device_criteria.dart`
- `test/integration/group_multi_party_device_criteria_test.dart`
- `integration_test/group_multi_party_device_real_harness.dart`
- this integration contract
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-breakdown.md`

Focused and preservation evidence:

- `flutter test --no-pub test/features/groups/application/accept_pending_group_invite_use_case_test.dart --plain-name 'KE-016'` PASS (`+1`).
- `flutter test --no-pub test/features/groups/integration/invite_round_trip_test.dart --plain-name 'KE-016'` PASS (`+1`).
- `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'private_stale_invite_readd'` PASS (`+4`).
- `dart run integration_test/scripts/run_group_multi_party_device_real.dart --list-scenarios | rg "private_stale_invite_readd|private_partial_key_distribution|private_readd_current"` PASS and listed `private_stale_invite_readd`.
- `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart` PASS (`+290`).
- `flutter test --no-pub test/features/groups/application/store_pending_group_invite_use_case_test.dart --plain-name 'ML-019 delayed older invite cannot replace newer pending re-add package'` PASS (`+1`).
- `flutter test --no-pub test/features/groups/integration/invite_round_trip_test.dart --plain-name 'remove -> rotate -> re-invite round-trip gives the rejoined member the rotated epoch'` PASS (`+1`) after rerun; the first parallel attempt failed from a native asset code-sign race, not row behavior.
- `flutter test --no-pub test/features/groups/application/member_removal_integration_test.dart --plain-name 'GM-021'` PASS (`+1`) after rerun; the first parallel attempt failed from a native asset build race, not row behavior.
- `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-021'` PASS (`+1`).
- `(cd go-mknoon && go test ./node -run 'TestGroupTopicValidator_ReaddFreshKeyPackageRejectsRemovedPackage|TestGroupTopicValidator_Device' -count=1)` PASS.
- `dart analyze integration_test/scripts/group_multi_party_device_criteria.dart integration_test/group_multi_party_device_real_harness.dart test/integration/group_multi_party_device_criteria_test.dart test/features/groups/application/accept_pending_group_invite_use_case_test.dart test/features/groups/integration/invite_round_trip_test.dart` PASS (`No issues found!`).
- `dart format --set-exit-if-changed` on touched Dart files PASS after formatting.
- `git diff --check` PASS before doc closure.

Named gate evidence:

- `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` remains red at `+190 -3`, matching the preserved residual gate shape from KE-015:
  - `BB-007 accepted pending invite joins with exact full config and replays accepted epoch` fails with `Expected: not null / Actual: <null>` at `test/features/groups/integration/invite_round_trip_test.dart:679`.
  - `BB-012 restart recovery drains replay before ack and stays live` fails with `Expected: an object with length of <1> / Actual: WhereIterable<GroupMessage>:[]` at `test/features/groups/integration/group_startup_rejoin_smoke_test.dart:842`.
  - `GM-029 config version monotonicity converges across A/B/C shuffled delivery` fails with `Expected: MemberRole.writer / Actual: MemberRole.reader` at `test/features/groups/integration/group_membership_smoke_test.dart:8144`.
- `./scripts/run_test_gates.sh completeness-check` remains red on the unrelated classification gap `test/shared/fakes/fake_group_pubsub_network_test.dart` (`732/733` classified).

Live proof evidence:

- `private_stale_invite_readd` iOS 26.2 proof PASS.
- Run id: `1779123475636`.
- Shared directory: `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_private_stale_invite_readd_76HtAm`.
- Devices: Alice `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`, Bob `279B82AE-2BB9-4924-9AAE-581870ED3FA9`, Charlie `116B4AF6-C1A9-4F36-B929-0A7130B5E83C`.
- Orchestrator detail: `private_stale_invite_readd proof passed: private_stale_invite_readd verdicts valid for alice, bob, charlie`.
- Proof meaning: Alice and Bob reached final key generation `2`; Charlie rejected the delayed epoch-1 stale invite/accept path, accepted the current epoch-2 path, did not downgrade, and reported `removedWindowPlaintextCount=0`.

Skipped/out-of-scope:

- Production stale invite guards were not changed because current main already has equivalent behavior.
- RA-004 stale-invite-before-new-readd proof fields were not imported because RA-004 is a separate pending row.
- KE-017 higher-epoch receive repair, KE-018 history replay, concurrent rotation allocation, pending-key receive repair, source worktree docs, COMPLETE_1 docs, source matrix docs, source `test-inventory.md`, unrelated harness scenarios, BB-007 repair, BB-012 retention-fixture repair, GM-029 repair, ML-012 external-fixture repair, notification, media, UI, relay, and broader lifecycle work were not imported.

Safe next action: continue with `INTEGRATE-KE-017` after ledger sanity and dirty-state safety checks, preserving KE-007 and KE-009 conflict blockers, ML-012 external-fixture blocker, BB-007/BB-012/GM-029 residual group-gate failures, and the completeness classification gap.
