# GO-002 Sender Status Distinguishes Inbox Store Failure Plan

Status: accepted/closed

## Planning Progress

- 2026-05-13 20:37 CEST - Local plan created after GO-001 closure selected GO-002 as the next unresolved P0 row. Files inspected: source matrix GO-002 row, session-breakdown GO-002 row, `lib/features/groups/application/send_group_message_use_case.dart`, `lib/features/groups/application/retry_failed_group_inbox_stores_use_case.dart`, `test/features/groups/application/send_group_message_use_case_test.dart`, `test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart`, `integration_test/scripts/group_multi_party_device_criteria.dart`, `integration_test/scripts/run_group_multi_party_device_real.dart`, `integration_test/group_multi_party_device_real_harness.dart`, and `test/integration/group_multi_party_device_criteria_test.dart`. Decision: GO-002 remained row-owned because the source row was `Open` and no adjacent GO-002 plan or exact row-named proof existed, but production send/retry behavior already staged inbox-store failures honestly once exact tests and harness proof were added.

## Original Source Row

| Test ID | Scenario | Preconditions | Steps | Expected Result | Priority | Current status | Unit | Integration | Smoke | Fake Network | 3-Party E2E | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| GO-002 | Sender status distinguishes inbox store failure | PubSub publish succeeds but GroupInboxStore fails. | 1. Force inbox failure. 2. Inspect sender status/retry queue. | Message is staged for retry or marked partial; not silently considered reliable. | P0 | Open | Recommended | Required | Required | Recommended | Required | Critical for trust. |

## Reconciliation Verdict

The production send path already returns success for live PubSub delivery while persisting an honest `pending` local row when fallback inbox storage fails. That row carries `inboxStored == false` and a retry payload, and `RetryFailedGroupInboxStoresUseCase` promotes it to `sent` only after a later durable inbox-store retry succeeds. The row stayed open because there was no exact GO-002 test, no exact retry proof, no GO-002 device scenario, and no criteria contract rejecting a sender verdict that silently marked the row reliable before retry.

## Scope

Own exactly GO-002:

- Add exact application send proof for PubSub success plus forced inbox-store failure.
- Add exact retry proof that the pending inbox-store failure promotes to `sent` only after durable retry succeeds.
- Add exact `go002` multi-party device scenario support that forces Alice's inbox-store call to fail, proves pending/retryable sender status before retry, then proves retry promotion and receiver convergence.
- Update the GO-002 source matrix row, this plan, the session breakdown GO-002 ledger entries, and `test-inventory.md` after concrete proof exists.

## Out Of Scope

- Changing live PubSub success semantics.
- Adding recipient acknowledgements for validator rejection; that remains GO-003.
- Changing Go PubSub validator behavior, encryption, relay storage, schema, UI rendering, or retry ordering unrelated to failed group inbox-store custody.

## Owner Files

- `test/features/groups/application/send_group_message_use_case_test.dart`
- `test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart`
- `integration_test/scripts/group_multi_party_device_criteria.dart`
- `integration_test/scripts/run_group_multi_party_device_real.dart`
- `integration_test/group_multi_party_device_real_harness.dart`
- `test/integration/group_multi_party_device_criteria_test.dart`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md`
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GO-002-plan.md`

## Required Validation

```sh
dart format --set-exit-if-changed integration_test/group_multi_party_device_real_harness.dart integration_test/scripts/group_multi_party_device_criteria.dart integration_test/scripts/run_group_multi_party_device_real.dart test/features/groups/application/send_group_message_use_case_test.dart test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart test/integration/group_multi_party_device_criteria_test.dart
dart analyze integration_test/group_multi_party_device_real_harness.dart integration_test/scripts/group_multi_party_device_criteria.dart integration_test/scripts/run_group_multi_party_device_real.dart test/features/groups/application/send_group_message_use_case_test.dart test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart test/integration/group_multi_party_device_criteria_test.dart
flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --plain-name 'GO-002'
flutter test --no-pub test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart --plain-name 'GO-002'
flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'GO-002'
./scripts/run_test_gates.sh groups
git diff --check -- integration_test/group_multi_party_device_real_harness.dart integration_test/scripts/group_multi_party_device_criteria.dart integration_test/scripts/run_group_multi_party_device_real.dart test/features/groups/application/send_group_message_use_case_test.dart test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart test/integration/group_multi_party_device_criteria_test.dart Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md Test-Flight-Improv/Group-Chat-Feature/test-inventory.md Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GO-002-plan.md
```

Required device proof when the fixture is available:

```sh
MKNOON_RELAY_ADDRESSES=/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g dart integration_test/scripts/run_group_multi_party_device_real.dart --scenario go002 -d 347FB118-10D0-40C8-A05B-B0C3BD6B8CCD,5BA69F1C-B112-47BE-B1FF-8C1003728C8F,1B098DFF-6294-407A-A209-BBF360893485
```

## Done Criteria

- Source row GO-002 is `Covered` only after exact GO-002 host and required device proof pass, or after a truthful external-fixture blocker is recorded.
- Sender status is not silently reliable when live PubSub succeeds but durable inbox storage fails.
- The retry path proves the pending inbox-store failure becomes `sent` only after durable inbox retry succeeds and clears the retry payload.
- The device verdict proves pending/retryable sender status before retry, durable retry success, receiver convergence, and no duplicate persistence.
- No `accepted_with_explicit_follow_up` is used for unresolved GO-002 gaps.

## Execution Evidence

- Test and harness implementation:
  - `test/features/groups/application/send_group_message_use_case_test.dart::GO-002 publish success with inbox failure stays pending and retryable` proves PubSub success with `topicPeers == 2` plus forced `group:inboxStore` failure returns success while saving and returning a `pending` message with `inboxStored == false`, a retry payload, no wire envelope, preserved durable recipients, and flow/timing events that expose `status: pending`, `inboxOk: false`, `inboxStored: false`, and `inboxPending: false`.
  - `test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart::GO-002 retry promotes pending inbox store failure to sent` proves a pending inbox-store failure retries exactly once, stores durable inbox payload id `go002-pending`, updates the local row to `sent`, sets `inboxStored == true`, clears the retry payload, and emits retry success/timing events.
  - `integration_test/scripts/group_multi_party_device_criteria.dart`, `integration_test/scripts/run_group_multi_party_device_real.dart`, `integration_test/group_multi_party_device_real_harness.dart`, and `test/integration/group_multi_party_device_criteria_test.dart` add `go002` scenario support. Alice sends through an inbox-store-failing bridge, records pending/retryable sender state, retries through the real bridge, records final `sent` durable status, and Bob/Charlie prove live receipt and post-retry convergence. Criteria rejects a sender verdict marked reliable before retry.
- Passed validation:
  - `dart format --set-exit-if-changed integration_test/group_multi_party_device_real_harness.dart integration_test/scripts/group_multi_party_device_criteria.dart integration_test/scripts/run_group_multi_party_device_real.dart test/features/groups/application/send_group_message_use_case_test.dart test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart test/integration/group_multi_party_device_criteria_test.dart`
  - `dart analyze integration_test/group_multi_party_device_real_harness.dart integration_test/scripts/group_multi_party_device_criteria.dart integration_test/scripts/run_group_multi_party_device_real.dart test/features/groups/application/send_group_message_use_case_test.dart test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart test/integration/group_multi_party_device_criteria_test.dart` (`No issues found!`)
  - `flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --plain-name 'GO-002'` (`+1`)
  - `flutter test --no-pub test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart --plain-name 'GO-002'` (`+1`)
  - `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'GO-002'` (`+2`)
  - `./scripts/run_test_gates.sh groups` (`+159`)
  - `flutter devices --machine` showed required iOS simulators `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD`, `5BA69F1C-B112-47BE-B1FF-8C1003728C8F`, and `1B098DFF-6294-407A-A209-BBF360893485`.
  - `MKNOON_RELAY_ADDRESSES=/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g dart integration_test/scripts/run_group_multi_party_device_real.dart --scenario go002 -d 347FB118-10D0-40C8-A05B-B0C3BD6B8CCD,5BA69F1C-B112-47BE-B1FF-8C1003728C8F,1B098DFF-6294-407A-A209-BBF360893485` passed with `go002 proof passed: go002 verdicts valid for alice, bob, charlie`; shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_go002_4BmY76`; run id `1778697742706`.
  - `git diff --check` on GO-002 owner files plus closure docs passed.

## Final Verdict

GO-002 is accepted/closed. The source matrix row is `Covered` with exact send-use-case proof, retry proof, criteria proof, named groups gate, and required relay-backed three-party proof. Residual-only: none. Accepted difference: no production runtime change was required because current send and retry behavior already staged failed inbox-store custody honestly; closure adds exact row-owned proof, retry proof, and live device evidence. Continue from GO-003, the next unresolved P0 session.
