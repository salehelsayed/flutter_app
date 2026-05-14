# Private Group Chat Reliability Matrix - Session GP-007 Plan

Status: accepted/closed

## Planning Progress

- 2026-05-14 00:02 CEST - Local gap-closure pass reached GP-007 after GA-026 closure. Source matrix row GP-007 was `Open`; session ledger row 196 was `implementation-ready` / `needs_tests_only`; no adjacent GP-007 plan existed. Inspected the source row, session ledger, existing GP-005/GP-006/GO-001 zero-peer evidence, `go-mknoon/node/pubsub.go::ensureGroupTopicPeersBeforePublish`, `go-mknoon/node/config.go` publish-settle constants, and current Flutter send/inbox fallback behavior.
- 2026-05-14 00:35 CEST - Implemented and validated the exact row-owned native, app, and integration proofs. Source matrix row GP-007 is now `Covered`; session ledger row 196 is now `covered/accepted`.

## Source Row

| Row | Title | Source Status | Ledger Status |
| --- | --- | --- | --- |
| GP-007 | Publish does not wait too long for zero-peer group | Covered | covered/accepted |

## Gap Classification

`needs_tests_only`.

Current production code already uses `GroupPublishZeroPeerSettleWait` for zero-live-peer publish preflight and delegates reliability to the durable inbox path when PubSub succeeds with `topicPeers == 0`. Existing GP-005 and GO-001 evidence proved durable zero-peer fallback and honest sender state, but GP-007 still lacked exact row-owned proof that the native preflight wait is bounded by the zero-peer settle policy and that the app/integration send path completes without visible delay or retry staging.

## Scope

Owned files:

- `go-mknoon/node/pubsub_delivery_test.go`
- `test/features/groups/application/send_group_message_use_case_test.dart`
- `test/features/groups/integration/group_resume_recovery_test.dart`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md`
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`

Out of scope:

- Production publish, discovery, retry, or relay-session behavior unless exact GP-007 proof exposed a runtime gap.
- Device-lab proof; GP-007 marks 3-Party E2E as N/A and the row-owned contract is host-native/app bounded send plus durable inbox delegation.
- Reclassifying GP-009 or later discovery rows; those remain separate row-owned sessions.

## Implementation Plan

1. Add an exact Go regression for zero-live-peer publish preflight with a valid offline expected member, asserting elapsed time stays bounded and discovery events record the zero-peer settle policy.
2. Add an exact Flutter send-use-case regression that forces `topicPeers: 0`, requires completion under one second, and proves durable inbox custody with no retry staging.
3. Add an exact integration regression that runs the GroupTestUser bridge path, measures visible send duration, verifies sender state, and drains the inbox to the offline recipient.
4. Run focused GP-007 tests, adjacent zero-peer/publish/discovery selectors, selected race proof, named groups gate, formatting, and diff hygiene.
5. Update the source matrix, breakdown ledger, adjacent plan, and test inventory with concrete evidence before accepting the row.

## Acceptance Bar

- Source matrix row GP-007 is `Covered`.
- Session ledger row 196 is `covered/accepted`.
- Tests include exact row-named native, app, and integration GP-007 coverage.
- Evidence records focused selector, adjacent Go/Flutter selectors, selected race proof, named groups gate, formatting, and `git diff --check`.
- Residual-only entry is `none`; no repo-owned blocker or dependency remains for GP-007.

## Execution Evidence

Implemented:

- `go-mknoon/node/pubsub_delivery_test.go::TestGP007ZeroPeerPublishUsesBoundedSettleWait`
- `test/features/groups/application/send_group_message_use_case_test.dart::GP-007 zero topic peers complete without retry staging and use inbox`
- `test/features/groups/integration/group_resume_recovery_test.dart::GP-007 zero-peer send delegates to inbox without visible delay`

The Go proof joins a sender and one valid offline member, so expected peers are non-zero while live topic peers are zero. It publishes with a caller-provided id, proves `peerCount == 0`, bounds elapsed publish time near `GroupPublishZeroPeerSettleWait`, verifies `publish_peer_refresh_begin` saw `topicPeers == 0` / `expectedPeers == 1`, verifies `publish_peer_refresh_done.settleWaitMs == GroupPublishZeroPeerSettleWait.Milliseconds()`, and asserts the zero-peer settle wait remains below the partial-peer wait.

The application proof forces bridge `group:publish` to return `topicPeers: 0`, requires send completion under one second, proves `successNoPeers`, durable `sent` sender state, `inboxStored == true`, no retry or wire payload, the expected inbox recipient set, and success-no-peers/timing events with `topicPeers == 0`, `inboxStored == true`, `inboxPending == false`, and `elapsedMs < 1000`.

The integration proof uses `GroupTestUser` plus `ZeroPeerPublishBridge`, unsubscribes the recipient, measures the full send, proves completion under one second, verifies the sender row is sent/inbox-stored with no retry payload, injects the stored inbox message, drains offline inbox, and proves the recipient sees exactly one incoming message with the expected id/text.

Validation passed:

- `gofmt -w go-mknoon/node/pubsub_delivery_test.go`
- `dart format test/features/groups/application/send_group_message_use_case_test.dart`
- `dart format test/features/groups/integration/group_resume_recovery_test.dart`
- `cd go-mknoon && go test ./node -run 'TestGP007' -count=1` (`ok node 1.111s`)
- `cd go-mknoon && go test ./node -run 'TestGP005|TestGP006|TestGP007|TestGP015|PublishGroupMessage|GroupPeerDiscoveryLoop|KnownGroupMemberDial' -count=1` (`ok node 17.397s`)
- `cd go-mknoon && go test ./node ./internal ./crypto -run 'TestGP005|TestGP006|TestGP007|TestGP015|PublishGroupMessage|GroupPeerDiscoveryLoop|KnownGroupMemberDial' -count=1` (`ok node 15.297s`, `ok internal 0.880s [no tests to run]`, `ok crypto 1.152s [no tests to run]`)
- `cd go-mknoon && go test -race ./node -run 'TestGP007|PublishGroupMessage|KnownGroupMemberDial' -count=1` (`ok node 3.336s`)
- `flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --plain-name 'GP-007 zero topic peers complete without retry staging and use inbox'` (`+1`)
- `flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --name 'GP-005|GP-007|GO-001|0-peer|topicPeers zero|successNoPeers'` (`+24`)
- `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'GP-007 zero-peer send delegates to inbox without visible delay'` (`+1`)
- `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --name 'GP-007|publish with zero peers falls back to inbox'` (`+2`)
- `./scripts/run_test_gates.sh groups` (`+160`)
- `git diff --check -- go-mknoon/node/pubsub_delivery_test.go test/features/groups/application/send_group_message_use_case_test.dart test/features/groups/integration/group_resume_recovery_test.dart Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GP-007-plan.md Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`

## Final Verdict

Accepted/closed. GP-007 is `Covered` with exact native bounded zero-peer publish evidence, exact Flutter send-use-case no-visible-delay evidence, and exact integration inbox-delegation evidence. No production runtime change was required because existing zero-peer settle and durable inbox behavior already satisfied the row once exact proof existed. Residual-only none. Continue from GI-034, the next unresolved session in ordered ledger order; do not write a final program verdict while later rows remain unresolved.
