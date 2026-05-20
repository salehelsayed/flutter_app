# INTEGRATE-RA-008 - Missing Integration Contract

Status: accepted

Created: 2026-05-19

## Source Row Contract

Source row: `RA-008 | C misses removal but receives re-add and does not retain removed-window access | P0 | Remove and Re-add Regression Suite`

Historical source plan:
`/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-RA-008-plan.md`

The source contract covers a removed-peer partition:

- Charlie is active before the partition, then Charlie's deliveries are held while Alice removes him.
- Alice sends removed-window traffic while Charlie is held and before re-add.
- Bob remains active and receives the removed-window message.
- Alice re-adds Charlie at the current epoch, Charlie heals, and final membership converges to Alice/Bob/Charlie.
- Charlie receives Alice/Bob post-readd current-epoch messages, can publish after heal, and never decrypts or persists the removed-window message.

Historical source proof passed with RA-008-named fake-network, criteria, and live-harness proof fields on `private_readd_current`, including iOS 26.2 live run `1778640009260`.

## Controller Classification

Classification: `missing_row_owned_delta`.

Current main has overlapping behavior but no exact RA-008 proof surface. COMPLETE_1/current coverage proves adjacent remove/re-add and removed-window access boundaries, including GM-007, IR-005, GM-019/GI-004, GE-009, RA-003, and RA-007. This row is not `skipped_already_present` because current main has no RA-008 selector, no `ra008PartitionedRemovedReaddProof`, no RA-008 criteria validation/tests/fixtures, and no RA-008 test-inventory closure row.

Existing blockers `ML-012`, `KE-007`, and `KE-009` are recorded and dependency-independent for this row. They must not be repaired or re-reconciled inside INTEGRATE-RA-008.

## Integration Scope

Import only the missing RA-008-owned proof/test/doc deltas from the historical source worktree:

- Add the RA-008 fake-network selector to `group_membership_smoke_test.dart`.
- Add `ra008PartitionedRemovedReaddProof` fields beside existing `private_readd_current` proof fields for Alice, Bob, and Charlie.
- Add RA-008 criteria validation and RA-008 criteria positive/negative checks without importing RA-009+ or unrelated source proof rows.
- Update `test-inventory.md` for RA-008 only.

Production app code changes are out of scope. Do not import source matrix rewrites, source session-breakdown rewrites, source RA-008 historical plan rewrites, runner-script changes, RA-009+ rows, first-message/restart/stale-leave/rotated-device rows, NW-003, BB-007, BB-012, accepted-row IR-018 fixture aging, GM-029, ML-008, GE-018, retained-history drain follow-up, COMPLETE_1 GI-017, replay-window residuals, listener/drain residuals, ML-012 external-fixture work, KE-007/KE-009 re-reconciliation, UI, notification, media, relay architecture, or broader stress rows.

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

Record run id, shared dir, role devices, and RA-008 proof facts. Do not substitute iOS 26.1, iOS 26.5, Android, physical iOS, macOS, Chrome, or single-device proof for the app-peer roles.

## Required Verification

```bash
flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'RA-008'
flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'RA-008'
flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'private_readd_current'
flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'RA-007'
flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-006'
flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'IR-005'
flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name 'GE-009'
dart analyze test/features/groups/integration/group_membership_smoke_test.dart integration_test/group_multi_party_device_real_harness.dart integration_test/scripts/group_multi_party_device_criteria.dart test/integration/group_multi_party_device_criteria_test.dart
dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario private_readd_current --list-scenarios
git diff --check
```

Named gates to classify after focused checks:

```bash
FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups
./scripts/run_test_gates.sh completeness-check
```

Known unrelated residuals from RA-007 are expected to remain outside RA-008 unless changed by this row.

## Execution Result

Verdict: accepted.

Integrated only the missing RA-008-owned proof/test/doc deltas:

- `test/features/groups/integration/group_membership_smoke_test.dart`: added the RA-008 selector for Charlie missing removal, being re-added, and not retaining removed-window access.
- `integration_test/group_multi_party_device_real_harness.dart`: added `ra008PartitionedRemovedReaddProof` verdict fields for Alice, Bob, and Charlie in `private_readd_current`.
- `integration_test/scripts/group_multi_party_device_criteria.dart`: added RA-008 criteria validation for the live proof.
- `test/integration/group_multi_party_device_criteria_test.dart`: added RA-008 positive and negative criteria fixtures/assertions.
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`: added the concise RA-008 inventory row.

Verification evidence:

- `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'RA-008'` passed (`+1`).
- `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'RA-008'` passed (`+3`).
- `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'private_readd_current'` passed (`+24`).
- Preservation checks passed: RA-007 host (`+1`), GM-006 host (`+1`), IR-005 host (`+1`), GE-009 host (`+1`), and RA-007 criteria (`+3`).
- Scoped analyzer passed with `No issues found!`.
- Runner discovery listed `private_readd_current`.
- iOS 26.2 live proof passed on Alice `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`, Bob `279B82AE-2BB9-4924-9AAE-581870ED3FA9`, and Charlie `116B4AF6-C1A9-4F36-B929-0A7130B5E83C` with run id `1779192689601` and shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_private_readd_current_j8fu8g`.
- RA-008 proof fields recorded fake-network partition ordering, live post-heal delivery, Alice/Bob/Charlie final epoch `2`, Charlie `removedWindowPlaintextCount=0`, Charlie post-heal publish accepted, and Alice/Bob post-heal current-epoch traffic received by Charlie.
- `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` remains red at `+225 -4` only on preserved residuals `BB-007`, `BB-012`, accepted-row `IR-018` fixture aging, and `GM-029`.
- `./scripts/run_test_gates.sh completeness-check` remains red on unrelated `test/shared/fakes/fake_group_pubsub_network_test.dart` classification (`733/734`).
- `git diff --check` passed.

Production code, Go code, runner scripts, source worktree docs, COMPLETE_1 docs, source matrix/session breakdown docs, RA-009+ rows, stale/restart/rotated-device rows, unrelated fixtures, and existing blocker repairs stayed out of scope.
