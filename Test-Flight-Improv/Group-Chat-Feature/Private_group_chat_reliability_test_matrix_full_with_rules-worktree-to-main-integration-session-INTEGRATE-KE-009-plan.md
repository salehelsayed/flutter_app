# INTEGRATE-KE-009 Integration Contract - Config Before Key Receive Gap

Status: accepted

Created: 2026-05-18

## Source Row

- Worktree source matrix row: `KE-009`
- Integration session: `INTEGRATE-KE-009`
- Title: `Out-of-order config-before-key does not create a receive-dead member`
- Historical worktree plan: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-KE-009-plan.md`
- Historical worktree plan status: `accepted`
- Active integration mode: standard worktree-to-main integration, not gap closure

## Row Contract

When Charlie receives membership/config state before the current group key, Charlie must not become a permanently receive-dead member:

- Charlie has active membership/config state while the current epoch key is still missing.
- A current-epoch message delivered during that window requests missing-key repair and remains replayable/visible after the current key arrives.
- Once the current key arrives, pending key repair retry runs for that epoch and Charlie continues receiving current-epoch messages.

## Source-Owned Historical Deltas

The accepted worktree plan lists these row-owned proof files:

- `test/features/groups/integration/group_messaging_smoke_test.dart`
- `integration_test/scripts/group_multi_party_device_criteria.dart`
- `test/integration/group_multi_party_device_criteria_test.dart`
- `integration_test/group_multi_party_device_real_harness.dart`
- source matrix, source session-breakdown, and source `test-inventory.md`

The source fake-network proof is `KE-009 config-before-key member repairs first current-epoch message`. It depends on the live receive path emitting `GROUP_RECEIVED_MESSAGE_KEY_EPOCH_AHEAD_OF_LOCAL` and requesting repair with `groupKeyRepairReasonReceivedMessageEpochMissingLocalKey` / `received_message_epoch_missing_local_key` when a normal received group message has an epoch higher than the receiver's local key state.

## Target Reconciliation

KE-017 is now accepted in main, so the original conflict blocker is stale. Current main contains the higher-epoch normal receive repair contract KE-009 needs:

- `groupKeyRepairReasonReceivedMessageEpochMissingLocalKey` is defined in `lib/features/groups/application/group_pending_key_repair_service.dart`.
- `group_message_listener.dart` emits `GROUP_RECEIVED_MESSAGE_KEY_EPOCH_AHEAD_OF_LOCAL` and calls the received-message key-repair path when a normal received message is ahead of local key state.
- KE-017 focused host/fake-network coverage is accepted in main.

This pass imported only missing KE-009 row-owned proof artifacts:

- `test/features/groups/integration/group_messaging_smoke_test.dart` adds `KE-009 config-before-key member repairs first current-epoch message`.
- `integration_test/group_multi_party_device_real_harness.dart` emits `ke009ConfigBeforeKeyProof` on `private_readd_current`.
- `integration_test/scripts/group_multi_party_device_criteria.dart` validates `ke009ConfigBeforeKeyProof`.
- `test/integration/group_multi_party_device_criteria_test.dart` adds KE-009 missing-proof and permanent-gap negative criteria coverage and updates the valid fixture.

The fake-network selector was reconciled to the accepted ST-013 acknowledgement contract: key sends are acknowledged, while Charlie's local key processing is delayed until the test releases the captured key update. This preserves real `P2PService.sendMessage` ack propagation and still proves the received-message repair retry path.

## External Fixture Recovery

Verdict: `accepted`.

The previous KE-017 dependency conflict is resolved. Focused host and criteria checks passed:

- `flutter test test/features/groups/integration/group_messaging_smoke_test.dart --name "KE-007|KE-009|KE-017"` -> `+3: All tests passed!`
- `flutter test test/integration/group_multi_party_device_criteria_test.dart --name "private_online_remove|private_readd_current|KE-007|KE-009|KE-008|KE-010"` -> `+63: All tests passed!`

Historical failed iOS 26.2 live-proof evidence is preserved:

- Failed run `1779398240276`, shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_private_readd_current_hkVYlv`: no `*verdict*.json`; Alice timed out waiting for `gmp_1779398240276_bob_delayed_old_config_checked`; Bob timed out in `_runGm006Bob`; Charlie timed out in `_runGm006Charlie`; logs included `peer_mismatch`, relay `NO_RESERVATION`, dial backoff, and direct dial deadline failures.
- Clean rerun `1779398971688`, shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_private_readd_current_mFi4Ox`: no `*verdict*.json`; Bob timed out in `_runGm006Bob` at `integration_test/group_multi_party_device_real_harness.dart:19573`; Charlie timed out in `_runGm006Charlie` at `integration_test/group_multi_party_device_real_harness.dart:20308`; Alice timed out waiting for `gmp_1779398971688_bob_delayed_old_config_checked`; Alice logs showed relay `NO_RESERVATION`, direct dial deadline failures, missing peers, and discovery backoff after Bob/Charlie stopped.
- Devices for both live attempts: Alice `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`, Bob `279B82AE-2BB9-4924-9AAE-581870ED3FA9`, Charlie `116B4AF6-C1A9-4F36-B929-0A7130B5E83C`, all iOS 26.2 CoreSimulator devices.

The focused fixture repair found that the delayed-old-config event was not absent in those failed logs; Bob and Charlie observed `GROUP_MESSAGE_LISTENER_STALE_MEMBER_REMOVED_REPAIRED`, while the harness waited only for `GROUP_MESSAGE_LISTENER_STALE_MEMBERSHIP_EVENT_IGNORED`. The repair is limited to `_runGm006Bob` and `_runGm006Charlie` in `integration_test/group_multi_party_device_real_harness.dart`, where the delayed-old-config checkpoint now treats either stale-membership ignore or repaired stale member removal as the preservation signal. Accepted `ML-007`, `KE-008`, `KE-010`, `KE-011`, `KE-012`, PL, UP, and SV `private_readd_current` contracts are preserved and were not broadened under KE-009.

Required iOS 26.2 live proof passed after the fixture repair:

- Run id `1779403310398`, scenario `private_readd_current`, shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_private_readd_current_hbU8Ze`.
- Devices: Alice `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`, Bob `279B82AE-2BB9-4924-9AAE-581870ED3FA9`, Charlie `116B4AF6-C1A9-4F36-B929-0A7130B5E83C`, all iOS 26.2 CoreSimulator devices.
- Relay env: `MKNOON_RELAY_ADDRESSES=/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g`.
- Orchestrator verdict file `gmp_1779403310398_private_readd_current_orchestrator_verdict.json`: `ok=true`, detail `private_readd_current verdicts valid for alice, bob, charlie`.
- Role verdict files `gmp_1779403310398_alice_verdict.json`, `gmp_1779403310398_bob_verdict.json`, and `gmp_1779403310398_charlie_verdict.json` each include `ke009ConfigBeforeKeyProof`.
- Proof summary: Alice records row `KE-009`, fake-network config-before-key coverage, live current-epoch delivery, post-readd current-epoch send, and final epoch `2`; Bob records observed Charlie re-added, received Charlie post-readd at current epoch, sent Bob post-readd at current epoch, and final epoch `2`; Charlie records no permanent invisible gap after key arrival, received Alice and Bob post-readd at current epoch, and final epoch `2`.

Focused preservation checks after the live proof passed:

- `flutter test test/features/groups/integration/group_messaging_smoke_test.dart --name "KE-007|KE-009|KE-017"` -> `+3: All tests passed!`
- `flutter test test/integration/group_multi_party_device_criteria_test.dart --name "private_online_remove|private_readd_current|KE-007|KE-009|KE-008|KE-010"` -> `+63: All tests passed!`

## Scope Guard

No production code was changed for KE-009. Source docs, COMPLETE_1 docs, source worktree files, unrelated KE rows, ML rows, UI, media, notification, Android, and physical iOS stayed out of scope. The unrelated dirty `info.plist` was left unstaged and untouched.

## Safe Next Action

No KE-009 blocker remains. The full integration program can close with accepted 198, skipped 4, blocked_conflict 0, and blocked_external_fixture 0 after the controlling breakdown and test inventory are updated.
