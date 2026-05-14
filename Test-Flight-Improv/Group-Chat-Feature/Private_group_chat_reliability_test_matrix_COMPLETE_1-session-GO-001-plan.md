# GO-001 Sender Status Distinguishes PubSub Success With Zero Peers Plan

Status: accepted/closed

## Planning Progress

- 2026-05-13 20:00 CEST - Local plan created after GE-020 closure selected GO-001 as the next unresolved P0 row. Files inspected: source matrix GO-001 row, session-breakdown GO-001 row, `lib/features/groups/application/send_group_message_use_case.dart`, `test/features/groups/application/send_group_message_use_case_test.dart`, `go-mknoon/node/pubsub_delivery_test.go`, `test/features/groups/integration/group_messaging_smoke_test.dart`, `test/features/groups/presentation/group_conversation_wired_test.dart`, `integration_test/scripts/group_multi_party_device_criteria.dart`, `integration_test/scripts/run_group_multi_party_device_real.dart`, `integration_test/group_multi_party_device_real_harness.dart`, and `test/integration/group_multi_party_device_criteria_test.dart`. Decision: GO-001 remains repo-owned `needs_code_and_tests` because the source row is `Open`, no adjacent GO-001 plan existed, and existing zero-peer coverage is GE/GP-named rather than row-owned GO-001 evidence.

## Original Source Row

| Test ID | Scenario | Preconditions | Steps | Expected Result | Priority | Current status | Unit | Integration | Smoke | Fake Network | 3-Party E2E | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| GO-001 | Sender status distinguishes pubsub success with zero peers | Publish succeeds but topicPeerCount=0. | 1. Send with zero peers. 2. App observes return and inbox result. 3. Inspect status. | Sender UI/API shows not-live/fallback-pending or durable status, not misleading delivered-to-all. | P0 | Open | Recommended | Required | Required | Recommended | Required | Publish returns peerCount; app must use it. |

## Reconciliation Verdict

The app already routes `topicPeers == 0` plus successful inbox custody to `SendGroupMessageResult.successNoPeers` and a stored `sent` message, and GE-010 has a three-device zero-live-topic proof. The GO-001 row remains open because there is no exact GO-001 host selector, no GO-001 multi-party scenario, and the zero-peer success flow event does not expose the same explicit `topicPeers`, `status`, and `inboxStored` facts that the returned message and timing event carry. This is repo-owned proof and observability hardening, not an external blocker.

## Scope

Own exactly GO-001:

- Add explicit zero-peer durable-custody observability fields in `send_group_message_use_case.dart` for the success-no-peers path.
- Add exact `GO-001` application proof in `test/features/groups/application/send_group_message_use_case_test.dart`.
- Add exact `GO-001` Go node peer-count proof if existing Go behavior needs a row-named selector.
- Add exact `go001` multi-party device scenario support by reusing the zero-live-topic proof path and criteria contract.
- Update the GO-001 source matrix row, this plan, the session breakdown GO-001 ledger entries, and `test-inventory.md` only after concrete proof exists.

## Out Of Scope

- Changing sender status semantics away from durable `sent` when inbox custody succeeds.
- Altering GE-010 behavior, message encryption, relay storage semantics, or non-zero-peer send paths.
- Product UI redesign; widget proof only needs to confirm the sent durable row is not shown as pending or failed.

## Owner Files

- `lib/features/groups/application/send_group_message_use_case.dart`
- `test/features/groups/application/send_group_message_use_case_test.dart`
- `go-mknoon/node/pubsub_delivery_test.go`
- `integration_test/scripts/group_multi_party_device_criteria.dart`
- `integration_test/scripts/run_group_multi_party_device_real.dart`
- `integration_test/group_multi_party_device_real_harness.dart`
- `test/integration/group_multi_party_device_criteria_test.dart`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md`
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GO-001-plan.md`

## Required Validation

```sh
dart format --set-exit-if-changed lib/features/groups/application/send_group_message_use_case.dart test/features/groups/application/send_group_message_use_case_test.dart integration_test/scripts/group_multi_party_device_criteria.dart integration_test/scripts/run_group_multi_party_device_real.dart integration_test/group_multi_party_device_real_harness.dart test/integration/group_multi_party_device_criteria_test.dart
gofmt -w go-mknoon/node/pubsub_delivery_test.go
dart analyze lib/features/groups/application/send_group_message_use_case.dart test/features/groups/application/send_group_message_use_case_test.dart integration_test/scripts/group_multi_party_device_criteria.dart integration_test/scripts/run_group_multi_party_device_real.dart integration_test/group_multi_party_device_real_harness.dart test/integration/group_multi_party_device_criteria_test.dart
flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --plain-name 'GO-001'
flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'GO-001'
(cd go-mknoon && go test ./node -run 'TestGO001|TestPublishGroupMessage_ReturnsPeerCountZero_WhenNoPeers' -count=1)
./scripts/run_test_gates.sh groups
git diff --check -- lib/features/groups/application/send_group_message_use_case.dart test/features/groups/application/send_group_message_use_case_test.dart go-mknoon/node/pubsub_delivery_test.go integration_test/scripts/group_multi_party_device_criteria.dart integration_test/scripts/run_group_multi_party_device_real.dart integration_test/group_multi_party_device_real_harness.dart test/integration/group_multi_party_device_criteria_test.dart Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md Test-Flight-Improv/Group-Chat-Feature/test-inventory.md Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GO-001-plan.md
```

Required device proof when the fixture is available:

```sh
MKNOON_RELAY_ADDRESSES=/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g dart integration_test/scripts/run_group_multi_party_device_real.dart --scenario go001 -d 347FB118-10D0-40C8-A05B-B0C3BD6B8CCD,5BA69F1C-B112-47BE-B1FF-8C1003728C8F,1B098DFF-6294-407A-A209-BBF360893485
```

## Done Criteria

- Source row GO-001 is `Covered` only after exact GO-001 host and required device proof pass, or after a truthful external-fixture blocker is recorded.
- The app result, saved row, flow event, and timing event all distinguish zero-live-peer publish success from normal fanout and from failure.
- The device verdict proves `successNoPeers`, `topicPeers == 0`, sender row `sent`, durable inbox custody, no live delivery during the zero-peer window, receiver catch-up, and no duplicate persistence.
- No `accepted_with_explicit_follow_up` is used for unresolved GO-001 gaps.

## Execution Evidence

- Code/test implementation:
  - `lib/features/groups/application/send_group_message_use_case.dart` now emits explicit `status`, `topicPeers: 0`, `inboxStored: true`, and `inboxPending: false` details on `GROUP_SEND_MSG_USE_CASE_SUCCESS_NO_PEERS` and `GROUP_SEND_MSG_TIMING` for durable zero-live-peer sends.
  - `test/features/groups/application/send_group_message_use_case_test.dart::GO-001 zero topic peers exposes durable fallback sender status` proves the returned result is `successNoPeers`, the saved message remains durable `sent`, inbox custody stores the recipient set, no retry payload is created, and both flow/timing events expose zero-peer durable-fallback facts.
  - `go-mknoon/node/pubsub_delivery_test.go::TestGO001PublishGroupMessageReportsZeroTopicPeers` proves native publish succeeds with the caller-provided id and `peerCount == 0` when the topic has no live peers.
  - `integration_test/scripts/group_multi_party_device_criteria.dart`, `integration_test/scripts/run_group_multi_party_device_real.dart`, `integration_test/group_multi_party_device_real_harness.dart`, and `test/integration/group_multi_party_device_criteria_test.dart` add `go001` scenario support using the zero-live-topic durable fallback proof contract.
- Passed validation:
  - `dart format --set-exit-if-changed integration_test/group_multi_party_device_real_harness.dart integration_test/scripts/group_multi_party_device_criteria.dart integration_test/scripts/run_group_multi_party_device_real.dart lib/features/groups/application/send_group_message_use_case.dart test/features/groups/application/send_group_message_use_case_test.dart test/integration/group_multi_party_device_criteria_test.dart`
  - `gofmt -w go-mknoon/node/pubsub_delivery_test.go`
  - `dart analyze integration_test/group_multi_party_device_real_harness.dart integration_test/scripts/group_multi_party_device_criteria.dart integration_test/scripts/run_group_multi_party_device_real.dart lib/features/groups/application/send_group_message_use_case.dart test/features/groups/application/send_group_message_use_case_test.dart test/integration/group_multi_party_device_criteria_test.dart` (`No issues found!`)
  - `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'GO-001'` (`+2`)
  - `flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --plain-name 'GO-001'` (`+1`)
  - `(cd go-mknoon && go test ./node -run 'TestGO001|TestPublishGroupMessage_ReturnsPeerCountZero_WhenNoPeers' -count=1)` (`ok github.com/mknoon/go-mknoon/node 0.566s`)
  - `./scripts/run_test_gates.sh groups` (`+159`)
  - `flutter devices --machine` showed required iOS simulators `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD`, `5BA69F1C-B112-47BE-B1FF-8C1003728C8F`, and `1B098DFF-6294-407A-A209-BBF360893485`.
  - `MKNOON_RELAY_ADDRESSES=/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g dart integration_test/scripts/run_group_multi_party_device_real.dart --scenario go001 -d 347FB118-10D0-40C8-A05B-B0C3BD6B8CCD,5BA69F1C-B112-47BE-B1FF-8C1003728C8F,1B098DFF-6294-407A-A209-BBF360893485` passed with `go001 proof passed: go001 verdicts valid for alice, bob, charlie`; shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_go001_2Xf4af`; run id `1778696136962`.
  - `git diff --check` on GO-001 owner files plus closure docs passed.

Initial focused Dart test execution was rerun sequentially after a parallel Flutter native-assets race; the rerun passed and the race left no row-owned failure.

## Final Verdict

GO-001 is accepted/closed. The source matrix row is `Covered` with exact app, Go, named gate, and required relay-backed three-party proof. Residual-only: none. Accepted difference: sender UI/API semantics remain durable `sent` when inbox custody succeeds; GO-001 closes by making zero-live-peer durable fallback explicit in result, stored row, flow/timing events, and device verdicts rather than changing successful custody into failure. GO-002 is covered separately; continue from GO-003, the next unresolved P0 session.
