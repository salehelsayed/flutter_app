# INTEGRATE-NW-006 Minimal Integration Contract

Status: accepted

Session id: `INTEGRATE-NW-006`

Source row: `NW-006 | Peer disconnect does not equal group removal | P0 | Network, libp2p Topic Mesh, Relay, and Mobile Lifecycle`

Historical source of truth:

- Source matrix: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules.md`
- Historical accepted plan: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-NW-006-plan.md`
- Source inventory evidence: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`

Do not recreate or rerun the historical implementation plan. This contract governs only importing and verifying the already-accepted NW-006 row delta into the main checkout.

## Current-Main Classification

NW-006 was missing its exact row-owned proof anchors from the dirty main integration checkout. NW-004 already covered relay reconnect recovery and overlap risk, but it did not prove the NW-006 contract that a disconnected active peer remains a member, stays an offline inbox recipient, recovers a missed send after reconnect, and can publish back without any membership removal side effect.

Therefore this row was not `skipped_already_present`. Only the missing meaningful NW-006 row-owned code/test/harness/doc delta was accepted.

## Import Scope

Allowed row-owned imports:

- durable-recipient proof selector in `test/features/groups/application/send_group_message_use_case_test.dart`
- resume recovery active-member-state selector in `test/core/lifecycle/handle_app_resumed_group_recovery_test.dart`
- fake-network disconnect/replay/publish-back selector in `test/features/groups/integration/group_resume_recovery_test.dart`
- `private_peer_disconnect_not_removal` criteria support and NW-006 criteria tests in `integration_test/scripts/group_multi_party_device_criteria.dart` and `test/integration/group_multi_party_device_criteria_test.dart`
- `private_peer_disconnect_not_removal` runner registration in `integration_test/scripts/run_group_multi_party_device_real.dart`
- `private_peer_disconnect_not_removal` live-harness role support and `nw006DisconnectNotRemovalProof` emission in `integration_test/group_multi_party_device_real_harness.dart`
- one concise `test-inventory.md` row

The first main live proof attempt `1779228190404` failed criteria only because Alice's proof read `missedDuringDisconnectRecoveredByReplay` from shared message JSON written before Bob's offline-drain wrapper added `usedOfflineDrain`; Bob's role verdict already proved `usedOfflineDrain: true`. The row-owned harness proof was corrected to compare Alice's missed-send message id with Bob's recovered missed message id while Bob still asserts `usedOfflineDrain: true` in its own role verdict.

Not imported: NW-004 relay reconnect repair, NW-005 rendezvous rediscovery, NW-007 topic-peer-zero semantics, NW-008 duplicate connection paths, NW-009 relay probe failures, broader relay shared-state architecture, source docs, COMPLETE_1 docs, UI, notifications, media, Android, physical iOS, macOS app-peer proof, or unrelated worktree changes.

## Verification

Focused checks run:

```sh
dart format test/features/groups/application/send_group_message_use_case_test.dart test/core/lifecycle/handle_app_resumed_group_recovery_test.dart test/features/groups/integration/group_resume_recovery_test.dart test/integration/group_multi_party_device_criteria_test.dart integration_test/scripts/group_multi_party_device_criteria.dart integration_test/scripts/run_group_multi_party_device_real.dart integration_test/group_multi_party_device_real_harness.dart
dart analyze integration_test/scripts/group_multi_party_device_criteria.dart test/integration/group_multi_party_device_criteria_test.dart integration_test/group_multi_party_device_real_harness.dart
dart analyze integration_test/group_multi_party_device_real_harness.dart
flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'NW-006'
flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --plain-name 'NW-006'
flutter test --no-pub test/core/lifecycle/handle_app_resumed_group_recovery_test.dart --plain-name 'NW-006'
flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'NW-006'
dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario private_peer_disconnect_not_removal --list-scenarios
```

Affected-row preservation checks run:

```sh
flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'NW-004'
flutter test --no-pub test/core/lifecycle/handle_app_resumed_group_recovery_test.dart --plain-name 'NW-004'
flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'NW-004'
```

Results:

- scoped analyzer before the harness correction: PASS (`No issues found!`)
- scoped harness analyzer after the harness correction: PASS (`No issues found!`)
- focused NW-006 criteria selectors: PASS (`+6`)
- focused NW-006 durable-recipient selector: PASS (`+1`)
- focused NW-006 lifecycle selector: PASS (`+1`)
- focused NW-006 fake-network selector: PASS (`+1`)
- runner discovery: PASS (`private_peer_disconnect_not_removal`)
- affected NW-004 criteria preservation selector: PASS (`+7`)
- affected NW-004 lifecycle preservation selector: PASS (`+1`)
- affected NW-004 fake-network preservation selector: PASS (`+1`)

Preflight before live proof found no stale proof runner processes, no ambient `MKNOON_` env, and the required iOS 26.2 devices booted and available:

- Alice `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`
- Bob `279B82AE-2BB9-4924-9AAE-581870ED3FA9`
- Charlie `116B4AF6-C1A9-4F36-B929-0A7130B5E83C`
- Dana `CD5929A6-EA0A-421D-A6D3-55BD707E0F76`

The required relay env was supplied inline:

```sh
MKNOON_RELAY_ADDRESSES='/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g'
```

iOS 26.2 live proof:

```sh
MKNOON_RELAY_ADDRESSES='/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g' dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario private_peer_disconnect_not_removal -d 5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3,279B82AE-2BB9-4924-9AAE-581870ED3FA9,116B4AF6-C1A9-4F36-B929-0A7130B5E83C
```

Live proof results:

- first attempt `1779228190404`: FAIL only on criteria detail `alice: nw006DisconnectNotRemovalProof.missedDuringDisconnectRecoveredByReplay must be true`, with all role app tests completed and Bob proving offline drain in his verdict
- corrected proof attempt `1779228575906`: PASS
- shared dir: `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_private_peer_disconnect_not_removal_kw0Cuf`
- orchestrator verdict: `private_peer_disconnect_not_removal verdicts valid for alice, bob, charlie`
- devices: Alice `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`, Bob `279B82AE-2BB9-4924-9AAE-581870ED3FA9`, Charlie `116B4AF6-C1A9-4F36-B929-0A7130B5E83C`
- role verdicts proved `nw006DisconnectNotRemovalProof`, `rowId=NW-006`, app-peer iOS 26.2 proof, Bob disconnected, Bob stayed present and active during disconnect, removed-signal count `0`, membership mutation count `0`, durable recipients included disconnected Bob, Bob recovered the missed Alice send by offline drain, Bob received post-reconnect live delivery, Bob published back after reconnect, duplicate visible message count `0`, Alice/Bob/Charlie final membership convergence, final key epoch convergence, and stable epoch `1`

## Final Execution Verdict

Verdict: `accepted`

NW-006 is accepted in main. The row-owned proof establishes that peer disconnect is a connectivity event only: it does not remove a private group member, does not mutate membership truth, does not suppress offline inbox targeting, and still converges replay plus live delivery after reconnect.

Residual classifications from earlier integration rows are preserved unchanged: non-row `BB-007`, `BB-012`, accepted-row `IR-018` fixture aging, `GM-029`, non-RA `IR-003`, `GE-017`, `GE-019`, `GE-020`, sampled retained-history drain follow-up invariant, sampled `ML-008`, sampled COMPLETE_1 `GI-017`, sampled replay-window residuals `GM-033`/`GK-023`/`GI-019`, drain `GEK003` and `GE-018`, full-listener notification/self-peer-cache failures, strict-analyzer pre-existing infos/warnings, completeness classification failure, and `KE-007`/`KE-009` blocked-conflict records remain for future row-owned/follow-up work.
