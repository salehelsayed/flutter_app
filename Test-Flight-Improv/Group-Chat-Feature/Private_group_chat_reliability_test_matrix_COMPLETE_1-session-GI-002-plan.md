# GI-002 Session Plan: Group Inbox Store Request Shape

## Status

Status: accepted/closed

## Source Row

Source matrix row: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` row `GI-002`

## Gap-Closure Reconciliation

| Time | Actor | Inputs Compared | Finding | Action |
|---|---|---|---|---|
| 2026-05-13 03:18:00 CEST | Controller | Source matrix GI-002 row; breakdown row 123; `go-mknoon/node/group_inbox.go::GroupInboxStore`; `group_inbox_test.go` request-builder tests; `protocol_version_test.go::TestGroupProtocolInboxStoreUsesVersionedInboxProtocol` | The source row remains `Open`. Existing builder tests prove some JSON fields without a live node stream, and the protocol-version test captures a live request but only asserts protocol, action, and group id. No exact row-owned test starts a node with a fake relay and verifies the framed `group_store` request carries `groupId`, `from`, opaque encrypted message, and `recipientPeerIds`. | Add a focused Go node regression that captures the framed request from a fake relay and asserts the complete GI-002 request shape. |

## Scope

GI-002 owns the started-node `GroupInboxStore` relay request shape. A live store call must write one framed JSON request with `action == group_store`, the requested `groupId`, the node peer id in `from`, the exact opaque encrypted message, and the intended recipient peer ids.

Out of scope: nil-host failure, plaintext push preview leakage, retry/failover behavior, relay-side authorization, cursor retrieve, history repair, and Flutter durable inbox orchestration.

## Execution Contract

1. Add row-owned Go test `TestGI002GroupInboxStoreSendsGroupStoreRequestShape` in `go-mknoon/node/group_inbox_test.go`.
2. Start a local libp2p fake relay with an `InboxProtocol` handler that reads one frame and returns `{"status":"OK"}`.
3. Start a local node, configure it to use the fake relay, and call `GroupInboxStore` with a known group id, opaque encrypted message JSON, and two recipient peer ids.
4. Decode the captured frame and assert exact `action`, `groupId`, `from`, `message`, and ordered `recipientPeerIds`.
5. Run focused GI-002 and adjacent group inbox request-shape gates plus gofmt and diff hygiene.

## Required Gates

| Gate | Command |
|---|---|
| Focused GI-002 request-shape proof | `GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'TestGI002'` |
| Adjacent group inbox request/protocol proof | `GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'GroupInboxStore|BuildGroupInboxStoreRequest|GroupProtocolInboxStoreUsesVersionedInboxProtocol|GI001|GI002'` |
| Hygiene | `gofmt -w go-mknoon/node/group_inbox_test.go` and `git diff --check` |

## Dirty Worktree Snapshot

Captured before execution: worktree remains dirty with prior gap-closure rollout changes and accepted GI-001 artifacts. GI-002 scope is limited to the row-owned Go node regression, this plan, and closure documentation updates unless the focused proof exposes a production defect.

## Execution Evidence

| Time | Actor | Evidence | Result |
|---|---|---|---|
| 2026-05-13 03:24:00 CEST | Executor | Added `go-mknoon/node/group_inbox_test.go::TestGI002GroupInboxStoreSendsGroupStoreRequestShape`. The test starts a local libp2p fake relay, reads the frame written by a started node's `GroupInboxStore`, returns `{"status":"OK"}`, and asserts the captured request carries `action == group_store`, requested `groupId`, the node peer id in `from`, the exact opaque message, and ordered `recipientPeerIds`. | Covered the row-owned started-node request-shape contract with tests-only Go node evidence; no production code change required. |

## Verification

| Gate | Result |
|---|---|
| `GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'TestGI002'` | Passed (`ok github.com/mknoon/go-mknoon/node 0.526s`). |
| `GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'GroupInboxStore\|BuildGroupInboxStoreRequest\|GroupProtocolInboxStoreUsesVersionedInboxProtocol\|GI001\|GI002'` | Passed (`ok github.com/mknoon/go-mknoon/node 0.384s`). |
| `gofmt -w go-mknoon/node/group_inbox_test.go` | Passed. |
| `git diff --check` | Passed after closure document updates. |

## Final Verdict

Accepted/closed. GI-002 is covered by exact tests-only Go node evidence, the source matrix is `Covered`, and no `accepted_with_explicit_follow_up` is used. Residual-only none for GI-002; continue to GI-031, the next unresolved P0 row.

## Closure Bar

- Source row GI-002 is updated to `Covered` with concrete file/test/gate evidence.
- Breakdown row 123, row disposition, session ledger, ordered row, session closure ledger, and closure progress are updated to `covered/accepted`.
- No `accepted_with_explicit_follow_up` is used for this row-owned gap.
- Residual work, if any, must be outside GI-002 ownership and must not mask a repo-owned blocker.
