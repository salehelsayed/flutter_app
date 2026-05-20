# INTEGRATE-RA-010 - Partial-Present Integration Contract

Status: accepted

Created: 2026-05-19

## Source Row Contract

Source row: `RA-010 | First incoming message to re-added member is visible before and after restart | P0 | Remove and Re-add Regression Suite`

Historical source plan:
`/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-RA-010-plan.md`

The source contract covers incoming delivery to the re-added member across restart:

- Alice removes and re-adds Charlie at the current epoch.
- Alice sends the first incoming post-readd message to Charlie.
- Charlie receives that first incoming message before restart at the current epoch.
- Charlie restarts/reinitializes the group listener path without losing current group, key, config, or membership state.
- Alice sends a second incoming post-restart message.
- Charlie receives the second incoming message exactly once at the current epoch, and Bob observes Charlie re-added/current.

Historical source proof passed with RA-010-named fake-network, criteria, and live-harness proof fields on `private_readd_current`, including iOS 26.2 live run `1778642506410`.

## Controller Classification

Classification: `partial_present_missing_row_owned_delta`.

Current main already has adjacent remove/re-add and restart behavior through GM-008, GM-035, and accepted RA-009/RA-008/RA-007 overlays, but it has no exact RA-010 fake-network selector, no `ra010ReaddIncomingRestartProof`, no RA-010 criteria validation/tests/fixtures, and no RA-010 test-inventory closure row. This row is therefore not `skipped_already_present`.

Existing blockers and residuals `ML-012`, `KE-007`, `KE-009`, `BB-007`, `BB-012`, accepted-row `IR-018` fixture aging, `GM-029`, retained-history drain follow-up, `ML-008`, COMPLETE_1 `GI-017`, replay-window residuals, listener/drain residuals, and completeness classification failure are dependency-independent for this row. They must not be repaired or re-reconciled inside INTEGRATE-RA-010.

## Integration Scope

Import only the missing RA-010-owned proof/test/doc deltas from the historical source worktree:

- Add the RA-010 fake-network selector to `group_membership_smoke_test.dart`.
- Add `ra010ReaddIncomingRestartProof` fields beside existing `private_readd_current` proof fields for Alice, Bob, and Charlie.
- Add RA-010 criteria validation and RA-010 criteria positive/negative checks without importing RA-011+ or unrelated source proof rows.
- Update `test-inventory.md` for RA-010 only.

Production app code, Go code, runner script changes, source matrix rewrites, source session-breakdown rewrites, source RA-010 historical plan rewrites, COMPLETE_1 docs, RA-011+ rows, stale leave completion, rotated-device identity, UI, notification, media, relay architecture, Android, physical iOS, macOS app-peer role work, and existing blocker/residual repairs are out of scope.

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

Record run id, shared dir, role devices, and RA-010 proof facts. Do not substitute iOS 26.1, iOS 26.5, Android, physical iOS, macOS, Chrome, or single-device proof for the app-peer roles.

## Required Verification

```bash
flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'RA-010'
flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'RA-010'
flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'private_readd_current'
flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'RA-009'
flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'RA-009'
flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-008'
flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'GM-008'
flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-035'
flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'GM-035'
dart analyze test/features/groups/integration/group_membership_smoke_test.dart integration_test/group_multi_party_device_real_harness.dart integration_test/scripts/group_multi_party_device_criteria.dart test/integration/group_multi_party_device_criteria_test.dart
dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario private_readd_current --list-scenarios
git diff --check
```

Named gates to classify after focused checks:

```bash
FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups
./scripts/run_test_gates.sh completeness-check
```

Known unrelated residuals from RA-009 are expected to remain outside RA-010 unless changed by this row.

## Execution Result

Accepted on 2026-05-19.

Imported only the missing RA-010-owned integration delta:

- `test/features/groups/integration/group_membership_smoke_test.dart`: added the fake-network selector `RA-010 re-added member sees first incoming before and after restart`.
- `integration_test/group_multi_party_device_real_harness.dart`: added `aliceAfterCharlieRestart` coordination and `ra010ReaddIncomingRestartProof` fields on the existing `private_readd_current` path.
- `integration_test/scripts/group_multi_party_device_criteria.dart`: added RA-010 proof validation.
- `test/integration/group_multi_party_device_criteria_test.dart`: added RA-010 positive and negative criteria fixtures/tests; reconciled the existing `private_readd_current` missing-proof negative assertion so it still checks `bobAfterReaddCurrent` while allowing RA-010's additional required key.
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`: added the RA-010 inventory row.

No production code, Go code, runner scripts, source worktree docs, COMPLETE_1 docs, or RA-011+ deltas were imported. Exact RA-011/RA-012 marker checks in the touched files returned no leakage.

Verification passed:

- `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'RA-010'` (`+1`)
- `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'RA-010'` (`+3`)
- `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'private_readd_current'` (`+30`)
- RA-009 preservation: host `+1`, criteria `+3`
- GM-008 preservation: host `+1`, criteria `+7`
- GM-035 preservation: host `+1`, criteria `+4`
- Scoped analyzer on the four RA-010 owner files (`No issues found!`)
- `dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario private_readd_current --list-scenarios`
- `git diff --check`

iOS 26.2 live proof passed:

- Scenario: `private_readd_current`
- Run id: `1779195853020`
- Shared dir: `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_private_readd_current_8VDSwq`
- Alice device: `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`
- Bob device: `279B82AE-2BB9-4924-9AAE-581870ED3FA9`
- Charlie device: `116B4AF6-C1A9-4F36-B929-0A7130B5E83C`
- Orchestrator verdict: `private_readd_current verdicts valid for alice, bob, charlie`

RA-010 proof facts:

- Alice recorded `rowId=RA-010`, `liveIncomingBeforeAndAfterRestartCovered=true`, Charlie re-added, first incoming sent before Charlie restart at the current epoch, second incoming sent after Charlie restart at the current epoch, first key `aliceAfterImmediateReadd`, post-restart key `aliceAfterCharlieRestart`, final epoch `2`.
- Bob recorded `rowId=RA-010`, `liveIncomingBeforeAndAfterRestartCovered=true`, Charlie re-add observed, Alice post-restart message received at current epoch with key `aliceAfterCharlieRestart`, final epoch `2`.
- Charlie recorded `rowId=RA-010`, `liveIncomingBeforeAndAfterRestartCovered=true`, first incoming received before restart at current epoch, restart preserved current group/key/config state, second incoming received after restart at current epoch, first key `aliceAfterImmediateReadd`, post-restart key `aliceAfterCharlieRestart`, Alice/Bob/Charlie membership visible, final epoch `2`.

Named gates were run and remain red only outside the RA-010 row-owned delta:

- `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` returned `+226 -5`: preserved `BB-007`, `BB-012`, accepted-row `IR-018` fixture-aging replay residual, `GM-029`, plus newly observed non-RA-010 `IR-003` replay-boundary residual in `test/features/groups/integration/group_resume_recovery_test.dart`. Focused `IR-003` also failed `+0 -1`; RA-010 did not touch that file or the production replay path, so it remains future row-owned/follow-up work.
- `./scripts/run_test_gates.sh completeness-check` returned `733/734`, still unmatched only on unrelated `test/shared/fakes/fake_group_pubsub_network_test.dart`.
