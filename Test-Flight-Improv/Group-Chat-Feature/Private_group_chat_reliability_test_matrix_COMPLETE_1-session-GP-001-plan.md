# GP-001 Session Plan: Publish Fails Clearly When Group Is Not Joined

## Status

Status: accepted/closed

## Source Row

Source matrix row: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` row `GP-001`

## Gap-Closure Reconciliation

| Time | Actor | Inputs Compared | Finding | Action |
|---|---|---|---|---|
| 2026-05-13 00:11:04 CEST | Controller | Source matrix GP-001 row; breakdown row 105; production `go-mknoon/node/pubsub.go::PublishGroupMessage`; existing `go-mknoon/node/pubsub_delivery_test.go::TestPublishGroupMessage_ReturnsErrorForUnjoinedGroup` | Planning-time gap: production already returns `group not joined: <groupId>` with empty message id and peer count `0` before publish setup when topic/config/key state is absent, but the row lacked exact row-owned `GP-001` proof and source-matrix gate evidence. | Add exact Go node regression evidence. No production code change is expected unless the row-owned test exposes a gap. |

## Scope

GP-001 owns the local Go node `PublishGroupMessage` failure contract when the caller has not joined the group. It must not change join semantics, group config/key validation, retry behavior, relay behavior, Flutter repository code, UI behavior, or durable inbox state unless the row-owned regression proves the Go failure contract is wrong.

## Execution Contract

1. Add a row-owned Go node regression named `TestGP001PublishGroupMessageFailsClearlyWhenGroupNotJoined`.
2. Start a node without joining the target group.
3. Call `PublishGroupMessage` with valid sender key material and an explicit client message id.
4. Assert the call returns an error containing `group not joined: <groupId>`, an empty returned message id, and peer count `0`.
5. Assert the failed publish does not create topic, config, key, or subscription state for the unjoined group.

## Required Gates

| Gate | Command |
|---|---|
| Focused GP-001 regression | `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'TestGP001')` |
| Adjacent publish/unjoined selector | `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'GP001|PublishGroupMessage|GroupPeerDiscoveryLoop|KnownGroupMemberDial')` |
| Broader publish/discovery selector | `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node ./internal ./crypto -run 'PublishGroupMessage|GroupDiscovery|KnownMemberDial|GP001')` |
| Race selector | `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test -race ./node -run 'TestGP001|PublishGroupMessage_ReturnsErrorForUnjoinedGroup')` |
| Hygiene | `gofmt` on changed Go files and `git diff --check` |

## Closure Bar

- Source row GP-001 is updated to `Covered` with concrete file/test/gate evidence.
- Breakdown row 105, row disposition, session ledger, ordered row, session closure ledger, and closure progress are updated to `covered/accepted`.
- No `accepted_with_explicit_follow_up` is used for row-owned gaps.
- Residual work, if any, is outside GP-001 ownership and does not mask a repo-owned blocker.

## Execution Progress

| Time | Phase | Result |
|---|---|---|
| 2026-05-13 00:12:47 CEST | Implementation completed | Added `go-mknoon/node/pubsub_delivery_test.go::TestGP001PublishGroupMessageFailsClearlyWhenGroupNotJoined`. The test proves unjoined publish returns a clear `group not joined: <groupId>` error, empty returned message id even when a client message id is supplied, peer count `0`, and no topic/config/key/subscription state side effects. |
| 2026-05-13 00:12:47 CEST | Closure completed | Source matrix GP-001 and breakdown row 105 were updated to `Covered`/`covered/accepted` with exact row-owned evidence. |

## Gate Evidence

| Gate | Result |
|---|---|
| Focused GP-001 regression | `GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'TestGP001'` passed (`ok github.com/mknoon/go-mknoon/node 0.573s`). |
| Adjacent publish/unjoined selector | `GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'GP001\|PublishGroupMessage\|GroupPeerDiscoveryLoop\|KnownGroupMemberDial'` passed (`ok github.com/mknoon/go-mknoon/node 10.164s`). |
| Broader publish/discovery selector | `GOCACHE=/private/tmp/codex-go-build-cache go test ./node ./internal ./crypto -run 'PublishGroupMessage\|GroupDiscovery\|KnownMemberDial\|GP001'` passed (`ok node 1.743s`, `ok internal 0.273s`, `ok crypto 0.564s`). |
| Race selector | `GOCACHE=/private/tmp/codex-go-build-cache go test -race ./node -run 'TestGP001\|PublishGroupMessage_ReturnsErrorForUnjoinedGroup'` passed (`ok github.com/mknoon/go-mknoon/node 1.587s`). |
| Hygiene | `gofmt` on `go-mknoon/node/pubsub_delivery_test.go` and `git diff --check` passed. |

## Final Verdict

`accepted` / `closed`. GP-001 is covered by exact row-owned Go node proof. No production code changed because existing `PublishGroupMessage` already fails before publish setup when topic/config/key state is absent. The proof verifies the returned error, empty message id, zero peer count, and absence of side effects on group runtime state. Residual-only: none for GP-001. GI-031 remains the next unresolved P0 row; no final program verdict is written.
