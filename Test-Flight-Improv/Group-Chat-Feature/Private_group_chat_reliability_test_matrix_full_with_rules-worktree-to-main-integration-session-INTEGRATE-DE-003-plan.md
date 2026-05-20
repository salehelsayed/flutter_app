# INTEGRATE-DE-003 Stable Message Id Import Contract

Status: accepted

## Historical Source Of Truth

- Source row: `DE-003 | Caller-supplied message id is preserved across publish, event, replay, and retry`.
- Source worktree plan: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-DE-003-plan.md` in `worktrees/full-rules-pipeline`.
- Source closure status: `accepted` / `covered`, accepted on 2026-05-12.
- Integration mode: standard worktree-to-main import/reconcile/verify. This contract does not recreate the source implementation plan and does not expand the row beyond DE-003.

## Integration Scope

Import only the missing DE-003 row-owned delta into main:

- Add direct send/retry proof that a caller-supplied group message id is preserved in the publish payload, durable replay envelope, persisted local row, and failed-message retry payload.
- Add fake-network proof that live delivery, durable replay, duplicate replay dedupe, and failed-message retry all keep the caller-supplied id.
- Add `de003` scenario criteria requirements, expected proof messages, message-id proof validation, and positive/negative criteria tests.
- Add `de003` runner discovery and live-harness role/proof support.
- Update the worktree-to-main ledger and test inventory after verification.

Already-present and skipped as duplicate:

- Current main already preserves caller message ids through `send_group_message_use_case.dart`, incoming message handling, durable replay drain, and failed-message retry behavior.

Do not import DE-004+, self-echo reconciliation, publish result semantics, timeout handling, callback routing, native dispatcher panic handling, source matrix/session docs, or unrelated source-worktree changes.

## Verification Contract

- Focused DE-003 direct send/retry selector.
- Focused DE-003 fake-network replay/dedupe/retry selector.
- Focused DE-003 criteria selector.
- DE-001/DE-002 preservation selectors.
- Scoped analyzer, format, and `git diff --check`.
- `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups`, preserving known non-DE-003 residual failures.
- `./scripts/run_test_gates.sh completeness-check`, preserving unrelated fake-network classification residuals.
- iOS 26.2 live `de003` proof with exact simulator device ids and run id recorded.

## Execution Evidence

Imported row-owned tests/proof hooks in `test/features/groups/application/send_group_message_use_case_test.dart`, `test/features/groups/integration/group_resume_recovery_test.dart`, `integration_test/scripts/group_multi_party_device_criteria.dart`, `test/integration/group_multi_party_device_criteria_test.dart`, `integration_test/scripts/run_group_multi_party_device_real.dart`, and `integration_test/group_multi_party_device_real_harness.dart`; updated `test-inventory.md` and this integration ledger. No production code was changed for DE-003 because the source message-id preservation behavior was already present in main.

Passed verification:

- `flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --plain-name 'DE-003'` (`+1`)
- `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'DE-003'` (`+1`)
- `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'DE-003'` (`+3`)
- `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name 'DE-001'` (`+1`)
- `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name 'DE-002'` (`+1`)
- `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'DE-002'` (`+3`)
- `flutter test --no-pub test/core/bridge/bridge_group_helpers_test.dart --plain-name 'callGroupInboxRetrieveWithCursor'` (`+6`; rerun serially after an initial parallel native-assets `lipo` race)
- Scoped analyzer over DE-003 owner and already-present production files (`No issues found!`)
- `dart format --set-exit-if-changed` on DE-003 owner Dart files (`0 changed`)
- Scoped `git diff --check` on the DE-003 owner files passed before doc closure.

iOS 26.2 live proof evidence: `MKNOON_RELAY_ADDRESSES='/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g' dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario de003 -d 5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3,279B82AE-2BB9-4924-9AAE-581870ED3FA9,116B4AF6-C1A9-4F36-B929-0A7130B5E83C` passed with run id `1779135181457` and shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_de003_sv38qu`. Devices were Alice `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3` (`UP004 Alice iPhone 17 Pro iOS 26.2`), Bob `279B82AE-2BB9-4924-9AAE-581870ED3FA9` (`UP004 Bob iPhone Air iOS 26.2`), and Charlie `116B4AF6-C1A9-4F36-B929-0A7130B5E83C` (`UP004 Charlie iPhone 17 iOS 26.2`). Final result: `de003 proof passed: de003 verdicts valid for alice, bob, charlie`. Alice recorded `requestedMessageId=returnedMessageId=gmp_1779135181457_de003_aliceExplicit_alice`, `publishPathMessageIdPreserved=true`, `replayEnvelopeCoveredByHostGate=true`, and `retryPathCoveredByHostGate=true`; Bob and Charlie each recorded the same `receivedMessageId`, `receivedExplicitMessageOnce=true`, `matchedRequestedMessageId=true`, and `duplicateReplayDeduped=true`.

Named gate evidence: `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` remains red at `+196 -3` only on preserved non-DE-003 residuals `BB-007 accepted pending invite joins with exact full config and replays accepted epoch` (`Expected: not null / Actual: <null>` at `invite_round_trip_test.dart:679`), `BB-012 restart recovery drains replay before ack and stays live` (`Expected: an object with length of <1> / Actual: WhereIterable<GroupMessage>:[]` at `group_startup_rejoin_smoke_test.dart:842`), and `GM-029 config version monotonicity converges across A/B/C shuffled delivery` (`Expected: MemberRole.writer / Actual: MemberRole.reader` at `group_membership_smoke_test.dart:8144`). The DE-003 selectors passed independently before this named-gate run. `./scripts/run_test_gates.sh completeness-check` remains red on unrelated `test/shared/fakes/fake_group_pubsub_network_test.dart` classification (`732/733`).

## Final Verdict

Accepted. DE-003 is integrated with row-owned direct, fake-network, criteria, runner, and live-harness proof artifacts, iOS 26.2 live `de003` evidence, inventory update, and ledger evidence. Already-present message-id preservation behavior was verified and skipped as duplicate.
