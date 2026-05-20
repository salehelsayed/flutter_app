# INTEGRATE-NW-004 Minimal Integration Contract

Status: accepted

Session id: `INTEGRATE-NW-004`

Source row: `NW-004 | Relay reconnect preserves or repairs group topic subscriptions | P0 | Network, libp2p Topic Mesh, Relay, and Mobile Lifecycle`

Historical source of truth:

- Source matrix: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules.md`
- Historical accepted plan: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-NW-004-plan.md`
- Source inventory evidence: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`

Do not recreate or rerun the historical implementation plan. This contract governs only importing and verifying the already-accepted NW-004 row delta into the main checkout.

## Current-Main Classification

NW-004 was missing as an exact row-owned import in main. Current main had accepted NW-001, NW-002, and NW-003 network coverage plus COMPLETE_1 overlap around restart/rejoin and relay state handling, but it did not contain the exact NW-004 row anchors before this integration:

- `private_relay_reconnect_group_recovery`
- `nw004RelayReconnectRecoveryProof`
- `TestNW004RefreshRelaySessionPreservesJoinedGroupTopicState`
- `TestNW004WatchdogRestartSignalsGroupRecoveryUntilFlutterAck`
- focused Flutter selectors for relay reconnect recovery ordering, group topic repair, retry ack gating, startup rejoin, and resume drain
- criteria rejection coverage for fake-only or incomplete relay-reconnect recovery proof

Therefore this row was not `skipped_already_present`. Only the missing meaningful NW-004 row-owned delta was imported.

## Import Scope

Allowed row-owned imports:

- NW-004 Flutter lifecycle, P2P service, pending retrier, resume recovery, and startup rejoin selectors
- NW-004 Go local relay reconnect/topic-state and watchdog recovery selectors
- `private_relay_reconnect_group_recovery` runner/live-harness/criteria support and strict `nw004RelayReconnectRecoveryProof` validation
- NW-004 criteria accept/reject tests
- one concise `test-inventory.md` row

Not imported: NW-005 rendezvous rediscovery, NW-006 disconnect semantics, broader relay shared-state architecture, source docs, COMPLETE_1 docs, UI, notifications, media, Android, physical iOS, macOS app-peer role work, or unrelated worktree changes.

## Verification

Focused checks run:

```sh
dart analyze test/core/lifecycle/handle_app_resumed_group_recovery_test.dart test/core/services/p2p_service_impl_test.dart test/core/services/pending_message_retrier_test.dart test/features/groups/integration/group_resume_recovery_test.dart test/features/groups/integration/group_startup_rejoin_smoke_test.dart test/integration/group_multi_party_device_criteria_test.dart integration_test/scripts/group_multi_party_device_criteria.dart integration_test/scripts/run_group_multi_party_device_real.dart integration_test/group_multi_party_device_real_harness.dart lib/core/lifecycle/handle_app_resumed.dart lib/core/services/p2p_service_impl.dart lib/core/services/pending_message_retrier.dart lib/features/groups/application/rejoin_group_topics_use_case.dart lib/features/groups/application/drain_group_offline_inbox_use_case.dart lib/core/bridge/bridge_group_helpers.dart
flutter test --no-pub test/core/lifecycle/handle_app_resumed_group_recovery_test.dart --plain-name 'NW-004'
flutter test --no-pub test/core/services/p2p_service_impl_test.dart --plain-name 'NW-004'
flutter test --no-pub test/core/services/pending_message_retrier_test.dart --plain-name 'NW-004'
flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'NW-004'
flutter test --no-pub test/features/groups/integration/group_startup_rejoin_smoke_test.dart --plain-name 'NW-004'
flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'NW-004'
(cd go-mknoon && go test ./node -run 'TestNW004|TestGroupRecovery_PreservesTopicStateAcrossInPlaceRefresh|TestRefreshRelaySession_PreservesPubSubMaps|TestWatchdog_MarksNeedsGroupRecoveryForFlutter' -count=1)
dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario private_relay_reconnect_group_recovery --list-scenarios
git diff --check
```

Affected-row preservation checks run:

```sh
(cd go-mknoon && go test ./node -run '^TestGL017StopClearsGroupRuntimeStateAndRequiresExplicitRejoinAfterRestart$' -count=1)
flutter test --no-pub test/features/groups/integration/group_startup_rejoin_smoke_test.dart --plain-name 'GL-018 restart rejoin restores all persisted groups exactly once and resumes delivery'
flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'GR-015'
flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'GR-016'
flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'NW-003'
flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'NW-003'
flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name 'NW-001'
flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name 'NW-002'
(cd go-mknoon && go test ./node -run 'TestNW001|TestNW002|TestNW003' -count=1)
```

Results:

- scoped analyzer: PASS with only pre-existing info-level style lints in `handle_app_resumed.dart` and `p2p_service_impl.dart`
- NW-004 lifecycle selector: PASS (`+1`)
- NW-004 P2P service selector: PASS (`+1`)
- NW-004 pending retrier selectors: PASS (`+2`)
- NW-004 resume-recovery selector: PASS (`+1`)
- NW-004 startup-rejoin selector: PASS (`+1`)
- NW-004 criteria selectors: PASS (`+7`)
- Go selector bundle: PASS (`ok github.com/mknoon/go-mknoon/node 21.366s`)
- runner discovery: PASS (`private_relay_reconnect_group_recovery`)
- overlap/preservation checks for GL-017, GL-018, GR-015, GR-016, NW-001, NW-002, and NW-003: PASS
- post-run stale runner process check: PASS
- `git diff --check`: PASS

Required live proof:

```sh
MKNOON_RELAY_ADDRESSES=/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario private_relay_reconnect_group_recovery -d 5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3,279B82AE-2BB9-4924-9AAE-581870ED3FA9,116B4AF6-C1A9-4F36-B929-0A7130B5E83C
```

Live proof result: PASS.

- Run id: `1779225612219`
- Shared dir: `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_private_relay_reconnect_group_recovery_sy6Dnj`
- Devices: Alice `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`, Bob `279B82AE-2BB9-4924-9AAE-581870ED3FA9`, Charlie `116B4AF6-C1A9-4F36-B929-0A7130B5E83C`
- Orchestrator verdict: `private_relay_reconnect_group_recovery verdicts valid for alice, bob, charlie`

Role verdicts recorded `nw004RelayReconnectRecoveryProof` with `rowId=NW-004`, `scenario=private_relay_reconnect_group_recovery`, `appPeerPlatform=ios_26_2_core_simulator`, forced relay drop, relay reconnect, Bob `needsGroupRecoveryObserved=true`, group topics rejoined after reconnect, group replay drain completed, missed-during-drop message recovered by replay, post-reconnect live delivery to the recovered peer, recovered peer publish-back live, recovery ack after rejoin and drain on Bob, unchanged membership, final Alice/Bob/Charlie membership convergence, final key epoch convergence, and duplicate visible message count `0`.

## Final Execution Verdict

Verdict: `accepted`

NW-004 is accepted in main. The imported row-owned delta proves relay reconnect preserves or repairs group topic subscriptions through host, Go, criteria, runner, and iOS 26.2 live evidence without importing NW-005+ rediscovery/disconnect/lifecycle scope.

Residual classifications from earlier integration rows are preserved unchanged: non-row `BB-007`, `BB-012`, accepted-row `IR-018` fixture aging, `GM-029`, non-RA `IR-003`, `GE-017`, `GE-019`, `GE-020`, sampled retained-history drain follow-up invariant, sampled `ML-008`, sampled COMPLETE_1 `GI-017`, sampled replay-window residuals `GM-033`/`GK-023`/`GI-019`, drain `GEK003` and `GE-018`, full-listener notification/self-peer-cache failures, strict-analyzer pre-existing infos/warnings, completeness classification failure, and `KE-007`/`KE-009` blocked-conflict records remain for future row-owned/follow-up work.
