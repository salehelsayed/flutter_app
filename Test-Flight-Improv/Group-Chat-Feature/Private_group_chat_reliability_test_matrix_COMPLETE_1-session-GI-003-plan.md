# GI-003 Session Plan: Group Inbox Store Omits Plaintext Push Preview

## Status

Status: accepted/closed

## Source Row

Source matrix row: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` row `GI-003`

## Gap-Closure Reconciliation

| Time | Actor | Inputs Compared | Finding | Action |
|---|---|---|---|---|
| 2026-05-13 03:28:00 CEST | Controller | Source matrix GI-003 row; breakdown row 124; `go-mknoon/node/group_inbox.go::buildGroupInboxStoreRequest`; existing builder tests for retired push fields and opaque replay envelope; GI-002 live framed-request proof | The source row remains `Open`. Production already ignores `pushTitle` and `pushBody` in `buildGroupInboxStoreRequest`, and builder-level tests prove those fields are omitted, but no exact live `GroupInboxStore` proof passes unique plaintext title/body and inspects the relay-visible frame. | Add a focused Go node regression that captures the live framed request and proves no `pushTitle`, `pushBody`, or unique plaintext preview strings are present. |

## Scope

GI-003 owns the relay-visible privacy contract for `GroupInboxStore` push preview parameters. Passing plaintext preview strings to the node API must not place those strings, or their retired JSON field names, into the framed `group_store` request unless a future explicit policy is added.

Out of scope: notification delivery policy, relay-side push fanout, app notification copy, GI-002 base request shape, relay retry/failover behavior, and Flutter durable inbox orchestration.

## Execution Contract

1. Add row-owned Go test `TestGI003GroupInboxStoreOmitsPlaintextPushPreviewFields` in `go-mknoon/node/group_inbox_test.go`.
2. Start a local libp2p fake relay that captures the raw request frame and returns `{"status":"OK"}`.
3. Start a local node, configure the fake relay, and call `GroupInboxStore` with a known opaque message plus unique plaintext `pushTitle` and `pushBody` strings.
4. Assert the raw relay-visible JSON contains neither the retired key names nor the unique plaintext strings.
5. Decode the request to confirm the opaque message remains exact and the normal `group_store` request shape is still valid.
6. Run focused GI-003 and adjacent group inbox push/privacy gates plus gofmt and diff hygiene.

## Required Gates

| Gate | Command |
|---|---|
| Focused GI-003 push-privacy proof | `GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'TestGI003'` |
| Adjacent group inbox push/privacy proof | `GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'GI002|GI003|BuildGroupInboxStoreRequest_OmitsRetiredPush|BuildGroupInboxStoreRequest_PreservesOpaqueReplayEnvelope|GroupInboxStore'` |
| Hygiene | `gofmt -w go-mknoon/node/group_inbox_test.go` and `git diff --check` |

## Dirty Worktree Snapshot

Captured before execution: worktree remains dirty with prior gap-closure rollout changes and accepted GI-001/GI-002 artifacts. GI-003 scope is limited to the row-owned Go node regression, this plan, and closure documentation updates unless the focused proof exposes a production defect.

## Execution Evidence

| Time | Actor | Evidence | Result |
|---|---|---|---|
| 2026-05-13 03:32:00 CEST | Executor | Added `go-mknoon/node/group_inbox_test.go::TestGI003GroupInboxStoreOmitsPlaintextPushPreviewFields`. The test starts a local libp2p fake relay, captures the raw request frame from a started node's `GroupInboxStore`, passes unique plaintext `pushTitle` and `pushBody`, and asserts the relay-visible JSON contains neither retired key name nor either plaintext string. It also decodes the frame to confirm the normal `group_store` metadata and exact opaque message remain intact. | Covered the row-owned relay-visible push-preview privacy contract with tests-only Go node evidence; no production code change required. |

## Verification

| Gate | Result |
|---|---|
| `GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'TestGI003'` | Passed (`ok github.com/mknoon/go-mknoon/node 0.569s`). |
| `GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'GI002\|GI003\|BuildGroupInboxStoreRequest_OmitsRetiredPush\|BuildGroupInboxStoreRequest_PreservesOpaqueReplayEnvelope\|GroupInboxStore'` | Passed (`ok github.com/mknoon/go-mknoon/node 0.421s`). |
| `gofmt -w go-mknoon/node/group_inbox_test.go` | Passed. |
| `git diff --check` | Passed after closure document updates. |

## Final Verdict

Accepted/closed. GI-003 is covered by exact tests-only Go node evidence, the source matrix is `Covered`, and no `accepted_with_explicit_follow_up` is used. Residual-only none for GI-003; continue to GI-031, the next unresolved P0 row.

## Closure Bar

- Source row GI-003 is updated to `Covered` with concrete file/test/gate evidence.
- Breakdown row 124, row disposition, session ledger, ordered row, session closure ledger, and closure progress are updated to `covered/accepted`.
- No `accepted_with_explicit_follow_up` is used for this row-owned gap.
- Residual work, if any, must be outside GI-003 ownership and must not mask a repo-owned blocker.
