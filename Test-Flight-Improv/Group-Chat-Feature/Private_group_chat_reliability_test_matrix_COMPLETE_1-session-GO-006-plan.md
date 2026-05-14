# GO-006 Session Plan: Discovery Events Expose Missing Peer Condition

## Status

Status: accepted/closed

## Source Row

Source matrix row: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` row `GO-006`

## Gap-Closure Reconciliation

| Time | Actor | Inputs Compared | Finding | Action |
|---|---|---|---|---|
| 2026-05-14 07:47 CEST | Controller | Source matrix GO-006 row; breakdown session ledger row 227; existing `group:discovery` bridge forwarding; `go-mknoon/node/pubsub.go` discovery/publish-refresh event payloads; adjacent discovery/backoff tests; app send/drain owner gates | The source row was still `Open` while the breakdown classified the row as `needs_code_and_tests`/`implementation-ready`. Flutter bridge forwarding for `group:discovery` already existed in `lib/core/bridge/go_bridge_client.dart`, but native discovery result and backoff events did not expose the exact row-owned `topicPeers`, `expectedPeers`, `missingPeers`, and `backingOff` diagnostic fields across the missing-peer condition. | Keep GO-006 as code-plus-tests, add the native missing-peer diagnostic fields and exact regression proof, then run exact, adjacent, race, app-facing, and diff hygiene gates before closing the row. |

## Scope

GO-006 owns native `group:discovery` observability for missing expected group peers. The row closes when discovery result and backoff diagnostics expose enough structured state to distinguish live topic peers from expected peers and diagnose the missing count.

Out of scope: topic-peer versus host-connected status metrics (`GO-007`), goroutine leak checks (`GO-010`), validation reject rate limiting (`GO-005`), and broader relay recovery event diagnostics.

## Execution Contract

1. Preserve existing Flutter bridge forwarding for `group:discovery`.
2. Add `topicPeers`, `expectedPeers`, `missingPeers`, and `backingOff` to discovery result diagnostics.
3. Add the same missing-peer shape to discovery backoff diagnostics.
4. Keep publish-refresh diagnostics aligned with missing-peer and backing-off state where they already expose topic and expected peer counts.
5. Add an exact Go test named `TestGO006DiscoveryEventsExposeMissingPeerCondition`.
6. Prove a missing expected member emits `discover_result` with `topicPeers == 0`, `expectedPeers == 1`, `missingPeers == 1`, and `backingOff == false`.
7. Prove backoff diagnostics carry connected/expected/topic/missing counts, consecutive-failure state, next interval fields, warm retry state, and `backingOff == true`.
8. Run the ledger's native race and app-facing send/drain gates.
9. Update the source matrix, breakdown ledger, and test inventory with concrete file/test/gate evidence.

## Required Gates

| Gate | Command |
|---|---|
| Format | `gofmt -w go-mknoon/node/pubsub.go go-mknoon/node/pubsub_test.go` |
| Focused GO-006 proof | `(cd go-mknoon && go test ./node -run '^TestGO006DiscoveryEventsExposeMissingPeerCondition$' -count=1)` |
| Adjacent discovery/backoff proof | `(cd go-mknoon && go test ./node -run 'TestGO006|TestGP012RendezvousDiscoverySkipsInvalidPeerIDsAndDialsValidMember|TestGroupDiscoveryLoop|TestGroupDiscoveryCycle|TestGP017|TestGP018|TestGP019|TestGP020' -count=1)` |
| Native race gate | `(cd go-mknoon && go test -race ./node -run 'Group|PubSub|Relay' -count=1)` |
| App-facing send/drain gate | `flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart test/features/groups/application/drain_group_offline_inbox_use_case_test.dart` |
| Hygiene | `git diff --check` |

## Dirty Worktree Snapshot

Captured before closure: worktree remained dirty with prior gap-closure rollout changes and accepted session artifacts. GO-006 scope is limited to `go-mknoon/node/pubsub.go`, `go-mknoon/node/pubsub_test.go`, this adjacent plan, source/breakdown closure updates, and test inventory entries.

## Execution Evidence

Implemented native row coverage in `go-mknoon/node/pubsub.go` and `go-mknoon/node/pubsub_test.go`.

Production changes:

- `discoverAndConnectGroupPeers` now emits `topicPeers`, `expectedPeers`, `missingPeers`, and `backingOff: false` on the `discover_result` `group:discovery` event.
- `ensureGroupTopicPeersBeforePublish` now includes `missingPeers` and `backingOff: false` on publish peer refresh begin/done diagnostics.
- `groupDiscoveryPeerSnapshot` centralizes topic/expected/missing peer calculation.
- `emitGroupDiscoveryBackoff` emits `group:discovery` `step: "backoff"` with connected/expected counts, topic/expected/missing peer counts, `backingOff: true`, consecutive failure count, next interval, next interval milliseconds, and warm retries remaining.

Exact test:

- `go-mknoon/node/pubsub_test.go::TestGO006DiscoveryEventsExposeMissingPeerCondition` starts a node with a test event collector, creates a group with one valid missing remote member, forces rendezvous discovery to return no peers, runs `discoverAndConnectGroupPeers`, and proves the `discover_result` missing-peer fields are emitted. It then calls `emitGroupDiscoveryBackoff` and proves the backoff diagnostic carries the same missing-peer shape plus backoff cadence fields.

Existing app bridge behavior inspected:

- `lib/core/bridge/go_bridge_client.dart` already allows and dispatches `group:discovery` into the group diagnostic stream.

## Verification

| Gate | Result |
|---|---|
| `gofmt -w go-mknoon/node/pubsub.go go-mknoon/node/pubsub_test.go` | Passed. |
| `(cd go-mknoon && go test ./node -run '^TestGO006DiscoveryEventsExposeMissingPeerCondition$' -count=1)` | Passed: `ok github.com/mknoon/go-mknoon/node 0.554s`. |
| `(cd go-mknoon && go test ./node -run 'TestGO006|TestGP012RendezvousDiscoverySkipsInvalidPeerIDsAndDialsValidMember|TestGroupDiscoveryLoop|TestGroupDiscoveryCycle|TestGP017|TestGP018|TestGP019|TestGP020' -count=1)` | Passed: `ok github.com/mknoon/go-mknoon/node 0.469s`. |
| `(cd go-mknoon && go test -race ./node -run 'Group|PubSub|Relay' -count=1)` | Passed: `ok github.com/mknoon/go-mknoon/node 99.377s`. |
| `flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart test/features/groups/application/drain_group_offline_inbox_use_case_test.dart` | Passed: `+168 All tests passed!`. |
| `git diff --check` | Passed before and after closure documentation updates. |

## Final Verdict

Accepted/closed. GO-006 is covered by native discovery diagnostic fields plus exact missing-peer/backoff proof, adjacent discovery/backoff proof, selected native race proof, and app-facing send/drain gates. Residual-only none for GO-006. No final program verdict is written because unresolved rows remain.
