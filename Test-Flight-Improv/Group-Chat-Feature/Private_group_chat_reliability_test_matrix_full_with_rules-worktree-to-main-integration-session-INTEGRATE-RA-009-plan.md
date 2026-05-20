# INTEGRATE-RA-009 - Partial-Present Integration Contract

Status: accepted

Created: 2026-05-19

## Source Row Contract

Source row: `RA-009 | First message sent by re-added member is visible to existing members | P0 | Remove and Re-add Regression Suite`

Historical source plan:
`/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-RA-009-plan.md`

The source contract covers the first publish after re-add:

- Alice removes Charlie, then re-adds Charlie at the current epoch.
- Charlie sends the first post-readd message immediately after re-add.
- Alice receives Charlie's first post-readd message immediately.
- Bob has not yet processed the held re-add update when Charlie sends, then receives the re-add update before Charlie's held first message.
- Bob receives Charlie's first post-readd message exactly once after activation.

Historical source proof passed with RA-009-named fake-network, criteria, and live-harness proof fields on `private_readd_current`, including iOS 26.2 live run `1778641060159`.

## Controller Classification

Classification: `partial_present_missing_row_owned_delta`.

Current main already has shared `private_readd_current` immediate post-readd message mechanics and `charlieAfterImmediateReadd` fixtures from earlier accepted rows, but it has no exact RA-009 selector, no `ra009FirstReaddPublishProof`, no RA-009 criteria validation/tests/fixtures, and no RA-009 test-inventory closure row. This row is therefore not `skipped_already_present`.

Existing blockers `ML-012`, `KE-007`, and `KE-009` are recorded and dependency-independent for this row. They must not be repaired or re-reconciled inside INTEGRATE-RA-009.

## Integration Scope

Import only the missing RA-009-owned proof/test/doc deltas from the historical source worktree:

- Add the RA-009 fake-network selector to `group_membership_smoke_test.dart`.
- Add `ra009FirstReaddPublishProof` fields beside existing `private_readd_current` proof fields for Alice, Bob, and Charlie.
- Add RA-009 criteria validation and RA-009 criteria positive/negative checks without importing RA-010+ or unrelated source proof rows.
- Update `test-inventory.md` for RA-009 only.

Production app code changes are out of scope. Do not import source matrix rewrites, source session-breakdown rewrites, source RA-009 historical plan rewrites, runner-script changes, RA-010+ rows, restart persistence, stale leave completion, rotated-device identity, UI, notification, media, relay architecture, Android, physical iOS, macOS app-peer role work, BB-007, BB-012, accepted-row IR-018 fixture aging, GM-029, ML-008, GE-018, retained-history drain follow-up, COMPLETE_1 GI-017, replay-window residuals, listener/drain residuals, ML-012 external-fixture work, or KE-007/KE-009 re-reconciliation.

## Device/Relay Proof Profile

Profile: exact iOS 26.2 three-party simulator proof required after host verification.

Use only iOS 26.2 CoreSimulator app-peer devices for the live proof:

- Alice `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`
- Bob `279B82AE-2BB9-4924-9AAE-581870ED3FA9`
- Charlie `116B4AF6-C1A9-4F36-B929-0A7130B5E83C`

The live proof must run:

```bash
MKNOON_RELAY_ADDRESSES='/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g' dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario private_readd_current -d 5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3,279B82AE-2BB9-4924-9AAE-581870ED3FA9,116B4AF6-C1A9-4F36-B929-0A7130B5E83C
```

Record run id, shared dir, role devices, and RA-009 proof facts. Do not substitute iOS 26.1, iOS 26.5, Android, physical iOS, macOS, Chrome, or single-device proof for the app-peer roles.

## Required Verification

```bash
flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'RA-009'
flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'RA-009'
flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'private_readd_current'
flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'RA-008'
flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'RA-008'
dart analyze test/features/groups/integration/group_membership_smoke_test.dart integration_test/group_multi_party_device_real_harness.dart integration_test/scripts/group_multi_party_device_criteria.dart test/integration/group_multi_party_device_criteria_test.dart
dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario private_readd_current --list-scenarios
git diff --check
```

Named gates to classify after focused checks:

```bash
FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups
./scripts/run_test_gates.sh completeness-check
```

Known unrelated residuals from RA-008 are expected to remain outside RA-009 unless changed by this row.

## Execution Result

Verdict: `accepted`.

Imported only the missing RA-009 row-owned proof/test/doc delta:

- `test/features/groups/integration/group_membership_smoke_test.dart` adds the fake-network selector `RA-009 first re-added publish reaches existing members after activation` for group `grp-ra009-first-readd-publish` and message `ra009-charlie-first-readd-publish`.
- `integration_test/group_multi_party_device_real_harness.dart` adds `ra009FirstReaddPublishProof` fields for Alice, Bob, and Charlie within the existing `private_readd_current` scenario.
- `integration_test/scripts/group_multi_party_device_criteria.dart` validates RA-009 proof fields without changing runner scenario routing.
- `test/integration/group_multi_party_device_criteria_test.dart` adds RA-009 positive, missing-proof, and missing-Bob-visibility checks plus fixture fields.
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` records the RA-009 worktree-to-main integration coverage row.

Focused verification passed:

```bash
flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'RA-009' # +1
flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'RA-009' # +3
flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'private_readd_current' # +27
flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'RA-008' # +1
flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'RA-008' # +3
flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-035' # +1
flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'GM-035' # +4
dart analyze test/features/groups/integration/group_membership_smoke_test.dart integration_test/group_multi_party_device_real_harness.dart integration_test/scripts/group_multi_party_device_criteria.dart test/integration/group_multi_party_device_criteria_test.dart # No issues found!
dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario private_readd_current --list-scenarios # private_readd_current listed
```

iOS 26.2 live proof passed:

- Scenario: `private_readd_current`.
- Run id: `1779194384378`.
- Shared dir: `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_private_readd_current_PU54l8`.
- Alice: `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`.
- Bob: `279B82AE-2BB9-4924-9AAE-581870ED3FA9`.
- Charlie: `116B4AF6-C1A9-4F36-B929-0A7130B5E83C`.
- Orchestrator verdict: `private_readd_current proof passed: private_readd_current verdicts valid for alice, bob, charlie`.
- Alice RA-009 proof: `rowId=RA-009`, fake-network ordering covered, live first-readd publish covered, Charlie re-added, Charlie first post-readd message received at current epoch, message key `charlieAfterImmediateReadd`, final epoch `2`.
- Bob RA-009 proof: `rowId=RA-009`, fake-network ordering covered, live first-readd publish covered, Charlie re-add observed, Charlie first post-readd message received at current epoch, message key `charlieAfterImmediateReadd`, final epoch `2`.
- Charlie RA-009 proof: `rowId=RA-009`, fake-network ordering covered, live first-readd publish covered, first post-readd send accepted, message key `charlieAfterImmediateReadd`, Alice/Bob/Charlie visible in membership, final epoch `2`.

Named gates were run and residuals were preserved rather than repaired:

- `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` remains red at `+226 -4` only on preserved `BB-007`, `BB-012`, accepted-row `IR-018` fixed-date replay fixture aging, and `GM-029`.
- `./scripts/run_test_gates.sh completeness-check` remains red only on unrelated `test/shared/fakes/fake_group_pubsub_network_test.dart` classification (`733/734`).
- `git diff --check` passed before closure.

Out of scope remained untouched: production code, Go code, runner scripts, source docs, COMPLETE_1 docs, source matrix/session docs, RA-010+ rows, stale/restart/rotated-device rows, unrelated fixtures, relay architecture, notifications, Android, physical iOS, macOS app-peer role work, BB-007/BB-012/IR-018/GM-029 repairs, ML-012 external-fixture work, and KE-007/KE-009 re-reconciliation.
