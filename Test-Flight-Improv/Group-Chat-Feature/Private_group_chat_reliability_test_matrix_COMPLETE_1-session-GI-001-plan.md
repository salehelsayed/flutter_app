# GI-001 Session Plan: Group Inbox Store Requires Started Node

## Status

Status: accepted/closed

## Source Row

Source matrix row: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` row `GI-001`

## Gap-Closure Reconciliation

| Time | Actor | Inputs Compared | Finding | Action |
|---|---|---|---|---|
| 2026-05-13 03:08:00 CEST | Controller | Source matrix GI-001 row; breakdown row 122; `go-mknoon/node/group_inbox.go::GroupInboxStore`; existing `group_inbox_test.go` node started-node tests; bridge `TestGroupInboxStore_NodeNotInitialized` | The source row remains `Open`. Production already returns `node not started` before relay selection when `n.host` is nil, but existing tests only cover bridge singleton initialization plus retrieve/repair nil-host paths. No row-owned node test proves `GroupInboxStore` itself returns the exact error and attempts no relay stream. | Add a focused Go node regression that configures a reachable relay stream handler, leaves the node unstarted, calls `GroupInboxStore`, asserts exact `node not started`, and asserts the relay stream handler was not invoked. |

## Scope

GI-001 owns the nil-host precondition for `Node.GroupInboxStore`. Calling store on an unstarted node must fail clearly with `node not started` before connect, stream, frame write, or relay request behavior can begin.

Out of scope: bridge singleton initialization, started-node relay success/failure behavior, group inbox retrieve pagination, history repair, and Flutter durable inbox flows.

## Execution Contract

1. Add row-owned Go test `TestGI001GroupInboxStoreRequiresStartedNodeBeforeRelayStream` in `go-mknoon/node/group_inbox_test.go`.
2. Start a reachable local libp2p relay host with an `InboxProtocol` stream handler that counts stream attempts.
3. Configure the unstarted node with that relay address while keeping `n.host == nil`.
4. Call `GroupInboxStore` with a valid-looking group id, opaque message, and recipient peer id.
5. Assert the exact error string is `node not started` and the relay stream attempt counter remains zero.
6. Run focused GI-001 and adjacent group inbox node gates plus gofmt and diff hygiene.

## Required Gates

| Gate | Command |
|---|---|
| Focused GI-001 node proof | `GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'TestGI001'` |
| Adjacent group inbox nil-host/store proof | `GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'GroupInboxStore|GroupInboxRetrieveCursor_RequiresStartedNode|GroupHistoryRepairRange_RequiresStartedNode|BuildGroupInboxStoreRequest'` |
| Hygiene | `gofmt -w go-mknoon/node/group_inbox_test.go` and `git diff --check` |

## Dirty Worktree Snapshot

Captured before execution: worktree remains dirty with prior gap-closure rollout changes and accepted GP-028 artifacts. GI-001 scope is limited to the row-owned Go node regression, this plan, and closure documentation updates unless the focused proof exposes a production defect.

## Execution Evidence

| Time | Actor | Evidence | Result |
|---|---|---|---|
| 2026-05-13 03:13:00 CEST | Executor | Added `go-mknoon/node/group_inbox_test.go::TestGI001GroupInboxStoreRequiresStartedNodeBeforeRelayStream`. The test starts a reachable local libp2p relay with an `InboxProtocol` handler that counts streams, configures an unstarted `NewNode()` with that relay address, calls `GroupInboxStore`, asserts exact error `node not started`, and asserts zero relay stream attempts. | Covered the row-owned nil-host/no-stream contract with tests-only Go node evidence; no production code change required. |

## Verification

| Gate | Result |
|---|---|
| `GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'TestGI001'` | Passed (`ok github.com/mknoon/go-mknoon/node 0.520s`). |
| `GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'GroupInboxStore\|GroupInboxRetrieveCursor_RequiresStartedNode\|GroupHistoryRepairRange_RequiresStartedNode\|BuildGroupInboxStoreRequest'` | Passed (`ok github.com/mknoon/go-mknoon/node 0.355s`). |
| `gofmt -w go-mknoon/node/group_inbox_test.go` | Passed. |
| `git diff --check` | Passed after closure document updates. |

## Final Verdict

Accepted/closed. GI-001 is covered by exact tests-only Go node evidence, the source matrix is `Covered`, and no `accepted_with_explicit_follow_up` is used. Residual-only none for GI-001; continue to GI-031, the next unresolved P0 row.

## Closure Bar

- Source row GI-001 is updated to `Covered` with concrete file/test/gate evidence.
- Breakdown row 122, row disposition, session ledger, ordered row, session closure ledger, and closure progress are updated to `covered/accepted`.
- No `accepted_with_explicit_follow_up` is used for this row-owned gap.
- Residual work, if any, must be outside GI-001 ownership and must not mask a repo-owned blocker.
