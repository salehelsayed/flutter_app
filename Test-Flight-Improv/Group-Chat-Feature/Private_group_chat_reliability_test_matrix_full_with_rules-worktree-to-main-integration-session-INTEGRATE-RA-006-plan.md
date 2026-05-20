# INTEGRATE-RA-006 - Partial-Present Integration Contract

Status: accepted

Created: 2026-05-19

## Source Row Contract

Source row: `RA-006 | Old key update delivered after re-add cannot downgrade C | P0 | Remove and Re-add Regression Suite`

Historical source plan:
`/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-RA-006-plan.md`

The source contract covers delayed stale key material after a newer re-add:

- Charlie is removed and then re-added at the current epoch.
- A delayed old key update arrives after Charlie has the current re-add epoch.
- Charlie keeps the current epoch and stores the stale key only as historical material.
- The stale key does not replace native current key material, does not request repair, and does not break Alice/Bob/Charlie post-stale current-epoch delivery.

Historical source proof passed with RA-006-named listener, fake-network, criteria, and live-harness proof fields on `private_readd_current`, including iOS 26.2 live run `1778637530914`.

## Controller Classification

Classification: `partial_present`.

Current main already has the underlying behavior and KE-011 proof surface: production lower-epoch key handling stores stale material historically, the KE-011 listener and fake-network selectors prove the delayed-old-key-after-readd contract, and `private_readd_current` validates `ke011DelayedOldKeyAfterReaddProof`.

Current main is missing the row-owned RA-006 traceability surface from the source worktree: RA-006 selector names, `ra006DelayedOldKeyAfterReaddProof` live verdict fields, RA-006 criteria validation, RA-006 criteria tests, and test-inventory closure.

## Integration Scope

Import only the missing RA-006-owned proof/criteria/test/doc deltas:

- Add `RA-006` to the existing KE-011 listener and fake-network selector names without duplicating the tests.
- Add `ra006DelayedOldKeyAfterReaddProof` fields beside existing `ke011DelayedOldKeyAfterReaddProof` fields in `private_readd_current`.
- Generalize/reuse the existing delayed-old-key criteria validator so RA-006 validates the same contract with `rowId: RA-006`.
- Add RA-006 criteria positive and negative checks without importing RA-007+ or unrelated source proof rows.
- Update `test-inventory.md` for RA-006 only.

Production code changes are out of scope. RA-007+, stale config rollback, higher-epoch repair, UI, notification, media, relay architecture, BB-007, BB-012, accepted-row IR-018 fixture aging, GM-029, GE-018, ML-008, GI-017, replay-window residuals, listener/drain residuals, ML-012 external fixture work, and KE-007/KE-009 re-reconciliation are out of scope.

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

Record run id, shared dir, role devices, and RA-006 proof facts. Do not substitute iOS 26.1, iOS 26.5, Android, physical iOS, macOS, Chrome, or single-device proof for the app-peer roles.

## Required Verification

```bash
flutter test --no-pub test/features/groups/application/group_key_update_listener_test.dart --plain-name 'RA-006'
flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name 'RA-006'
flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'RA-006'
flutter test --no-pub test/features/groups/application/group_key_update_listener_test.dart --plain-name 'KE-011'
flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name 'KE-011'
flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'private_readd_current'
dart analyze test/features/groups/application/group_key_update_listener_test.dart test/features/groups/integration/group_messaging_smoke_test.dart integration_test/group_multi_party_device_real_harness.dart integration_test/scripts/group_multi_party_device_criteria.dart test/integration/group_multi_party_device_criteria_test.dart
dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario private_readd_current --list-scenarios
git diff --check
```

Named gates to classify after focused checks:

```bash
FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups
./scripts/run_test_gates.sh completeness-check
```

Known unrelated residuals from RA-005/RA-004 are expected to remain outside RA-006 unless changed by this row.

## Execution Result

Completed on 2026-05-19.

Imported only the missing RA-006-owned traceability/proof surface around the existing KE-011 stale-old-key-after-readd behavior. Production code stayed untouched.

Changes:

- Renamed the existing KE-011 listener and fake-network selector titles to include `RA-006 KE-011` while preserving `--plain-name KE-011`.
- Added `ra006DelayedOldKeyAfterReaddProof` beside `ke011DelayedOldKeyAfterReaddProof` for Alice, Bob, and Charlie in the `private_readd_current` live harness path, with the same proof facts and `rowId: RA-006`.
- Generalized the delayed-old-key-after-readd criteria validator and wired an RA-006 wrapper into `private_readd_current`.
- Added RA-006 criteria fixture fields plus valid, missing-proof, and Charlie-downgrade criteria tests.
- Added one concise RA-006 row to `test-inventory.md`.

Host verification:

- PASS: `flutter test --no-pub test/features/groups/application/group_key_update_listener_test.dart --plain-name 'RA-006'` (`+1`)
- PASS: `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name 'RA-006'` (`+1`)
- PASS: `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'RA-006'` (`+3`)
- PASS: `flutter test --no-pub test/features/groups/application/group_key_update_listener_test.dart --plain-name 'KE-011'` (`+1`)
- PASS: `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name 'KE-011'` (`+1`)
- PASS: `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'private_readd_current'` (`+18`)
- PASS: `dart analyze test/features/groups/application/group_key_update_listener_test.dart test/features/groups/integration/group_messaging_smoke_test.dart integration_test/group_multi_party_device_real_harness.dart integration_test/scripts/group_multi_party_device_criteria.dart test/integration/group_multi_party_device_criteria_test.dart` (`No issues found!`)
- PASS: `dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario private_readd_current --list-scenarios` (`private_readd_current`)
- PASS: `git diff --check`

Live iOS 26.2 proof:

- PASS: `private_readd_current` with run id `1779189231413`.
- Shared dir: `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_private_readd_current_Ov7FOR`.
- Devices: Alice `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`, Bob `279B82AE-2BB9-4924-9AAE-581870ED3FA9`, Charlie `116B4AF6-C1A9-4F36-B929-0A7130B5E83C`.
- Orchestrator verdict: `ok: true`, `private_readd_current verdicts valid for alice, bob, charlie`.
- Alice `ra006DelayedOldKeyAfterReaddProof`: `rowId: RA-006`, delivered delayed old key after re-add, sent post-stale at current epoch, stale epoch `1`, final epoch `2`.
- Bob `ra006DelayedOldKeyAfterReaddProof`: observed Charlie re-added, received Charlie post-stale at current epoch, sent Bob post-stale at current epoch, stale epoch `1`, final epoch `2`.
- Charlie `ra006DelayedOldKeyAfterReaddProof`: kept current epoch after delayed old key, stored delayed old key as historical, accepted post-stale publish, received Alice and Bob post-stale at current epoch, stale epoch `1`, epoch before/after delayed old key both `2`, final epoch `2`.

Named gates:

- RED as expected/preserved: `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` (`+223 -4`) only on `BB-007` (`Expected: not null / Actual: <null>` at `invite_round_trip_test.dart:679`), `BB-012` (`Expected: length <1> / Actual length <0>` at `group_startup_rejoin_smoke_test.dart:859`), accepted-row `IR-018` fixture-aging replay residual (`Expected: length <1> / Actual length <0>` at `group_startup_rejoin_smoke_test.dart:1027`), and `GM-029` (`Expected: MemberRole.writer / Actual: MemberRole.reader` at `group_membership_smoke_test.dart:8725`).
- RED as expected/preserved: `./scripts/run_test_gates.sh completeness-check` (`733/734`) only on unrelated `test/shared/fakes/fake_group_pubsub_network_test.dart` classification.

Final status: accepted.
