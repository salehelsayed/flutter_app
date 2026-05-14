# GO-007 Session Plan: Metrics Distinguish Host Connection From Live Topic Peer

## Status

Status: accepted/closed

## Source Row

Source matrix row: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` row `GO-007`

## Gap-Closure Reconciliation

| Time | Actor | Inputs Compared | Finding | Action |
|---|---|---|---|---|
| 2026-05-14 08:28 CEST | Controller | Source matrix GO-007 row; breakdown session ledger row 228; existing `go-mknoon/node/pubsub.go` topic-peer metrics; adjacent GP-015 connected-host proof; GO-006 discovery diagnostic fields; app send/drain owner gates | The source row was still `Open` while the breakdown classified the row as `needs_repo_evidence`/`evidence-gated`. Production already relied on `topic.ListPeers` through `liveGroupTopicPeerSet` / `countConnectedGroupMembers`, `PublishGroupMessage` emitted `group:publish_debug.topicPeers`, and GO-006 added publish-refresh `expectedPeers` / `missingPeers` diagnostics. The missing closure item was an exact GO-007 selector proving a host-connected peer that has not joined the topic is not counted as a live topic peer and is surfaced diagnostically as missing. | Close as tests-only under existing production behavior, add exact `TestGO007MetricsDistinguishHostConnectionFromLiveTopicPeer`, and run exact, adjacent, selected race, app-facing, and diff hygiene gates before updating source/breakdown/inventory evidence. |

## Scope

GO-007 owns observability for the difference between libp2p host connectedness and live PubSub topic membership. The row closes when a host-connected member that has not joined the group topic remains excluded from `topic.ListPeers`-derived metrics and publish diagnostics make that absence visible.

Out of scope: missing-peer discovery-field production changes already closed by GO-006, zero-peer sender status already closed by GO-001/GP-007, validation diagnostic privacy/rate limiting, and goroutine leak checks (`GO-010`).

## Execution Contract

1. Preserve production reliance on `topic.ListPeers` for live group topic peer counts.
2. Prove a remote member can be host-connected while absent from the live topic peer set.
3. Prove `PublishGroupMessage` returns `peerCount == 0` for that host-connected/non-topic peer.
4. Prove publish-refresh diagnostics report `topicPeers == 0`, `expectedPeers == 1`, `missingPeers == 1`, and `backingOff == false`.
5. Prove `group:publish_debug.topicPeers == 0` for the sent message.
6. Prove the host-connected peer receives no group message event without joining the topic.
7. Run the ledger's native race and app-facing send/drain gates.
8. Update the source matrix, breakdown ledger, and test inventory with concrete file/test/gate evidence.

## Required Gates

| Gate | Command |
|---|---|
| Format | `gofmt -w go-mknoon/node/pubsub_delivery_test.go` |
| Focused GO-007 proof | `(cd go-mknoon && go test ./node -run '^TestGO007MetricsDistinguishHostConnectionFromLiveTopicPeer$' -count=1)` |
| Adjacent topic-peer proof | `(cd go-mknoon && go test ./node -run 'TestGO007|TestGP015ConnectedHostPeerDoesNotCountAsLiveTopicPeer|TestGP007ZeroPeerPublishUsesBoundedSettleWait|TestGO006DiscoveryEventsExposeMissingPeerCondition' -count=1)` |
| Native race gate | `(cd go-mknoon && go test -race ./node -run 'Group|PubSub|Relay' -count=1)` |
| App-facing send/drain gate | `flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart test/features/groups/application/drain_group_offline_inbox_use_case_test.dart` |
| Hygiene | `git diff --check` |

## Dirty Worktree Snapshot

Captured before closure: worktree remained dirty with prior gap-closure rollout changes and accepted session artifacts. GO-007 scope is limited to `go-mknoon/node/pubsub_delivery_test.go`, this adjacent plan, source/breakdown closure updates, and test inventory entries.

## Execution Evidence

Implemented exact row coverage in `go-mknoon/node/pubsub_delivery_test.go`.

Production behavior inspected:

- `go-mknoon/node/pubsub.go::liveGroupTopicPeerSet` reads `topic.ListPeers()` and filters it to active group members.
- `go-mknoon/node/pubsub.go::countConnectedGroupMembers` returns the live topic peer count, not host connection count.
- `go-mknoon/node/pubsub.go::ensureGroupTopicPeersBeforePublish` emits publish-refresh diagnostics with `topicPeers`, `expectedPeers`, `missingPeers`, and `backingOff`.
- `go-mknoon/node/pubsub.go::PublishGroupMessage` returns the topic peer count and emits `group:publish_debug.topicPeers`.

Exact test:

- `go-mknoon/node/pubsub_delivery_test.go::TestGO007MetricsDistinguishHostConnectionFromLiveTopicPeer` starts two libp2p nodes, joins only node A to a private group that expects node B, connects A and B at the host layer, and proves `network.Connected` while `countConnectedGroupMembers(groupID) == 0` and `liveGroupTopicPeerSet(groupID)` is empty. It then publishes a message, proves `peerCount == 0`, confirms the host connection remains live, observes publish-refresh diagnostics with `topicPeers == 0`, `expectedPeers == 1`, `missingPeers == 1`, and `backingOff == false`, observes `group:publish_debug.topicPeers == 0`, and proves node B receives no group message event.

## Verification

| Gate | Result |
|---|---|
| `gofmt -w go-mknoon/node/pubsub_delivery_test.go` | Passed. |
| `(cd go-mknoon && go test ./node -run '^TestGO007MetricsDistinguishHostConnectionFromLiveTopicPeer$' -count=1)` | Passed: `ok github.com/mknoon/go-mknoon/node 2.773s`. |
| `(cd go-mknoon && go test ./node -run 'TestGO007|TestGP015ConnectedHostPeerDoesNotCountAsLiveTopicPeer|TestGP007ZeroPeerPublishUsesBoundedSettleWait|TestGO006DiscoveryEventsExposeMissingPeerCondition' -count=1)` | Passed: `ok github.com/mknoon/go-mknoon/node 5.810s`. |
| `(cd go-mknoon && go test -race ./node -run 'Group|PubSub|Relay' -count=1)` | Passed: `ok github.com/mknoon/go-mknoon/node 98.541s`. |
| `flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart test/features/groups/application/drain_group_offline_inbox_use_case_test.dart` | Passed: `+168 All tests passed!`. |
| `git diff --check` | Passed before and after closure documentation updates. |

## Final Verdict

Accepted/closed. GO-007 is covered by exact native topic-peer versus host-connected proof, adjacent topic-peer/zero-peer/discovery proof, selected native race proof, and app-facing send/drain gates. Residual-only none for GO-007. No final program verdict is written because unresolved rows remain.
