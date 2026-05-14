# GP-002 Session Plan: Publish Blocks Unauthorized Writer Before Encryption

## Status

Status: accepted/closed

## Source Row

Source matrix row: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` row `GP-002`

## Gap-Closure Reconciliation

| Time | Actor | Inputs Compared | Finding | Action |
|---|---|---|---|---|
| 2026-05-13 00:16:53 CEST | Controller | Source matrix GP-002 row; breakdown row 106; production `go-mknoon/node/pubsub.go::PublishGroupMessage`; existing GA-005 role-update proof around announcement-group write permission | Planning-time gap: production already checks `isAllowedWriter` before message id creation, payload marshal, encryption, signing, topic publish, and `group:publish_debug`, but the row lacked exact row-owned `GP-002` proof that the unauthorized branch cannot enter encrypt/sign/publish side effects. | Add exact Go node regression evidence using invalid-key/private-key sentinels and no-publish event assertions. No production code change is expected unless the row-owned test exposes a gap. |

## Scope

GP-002 owns the local Go node `PublishGroupMessage` authorization guard for senders that are group members but not allowed to write by the current group type and role. It must not change role semantics, receiver-side validator behavior, Flutter retry behavior, durable inbox behavior, or UI role handling unless the row-owned regression proves the Go publish guard is wrong.

## Execution Contract

1. Add a row-owned Go node regression named `TestGP002PublishBlocksUnauthorizedWriterBeforeEncryptSignAndPublish`.
2. Join announcement-group scenarios where the local sender is a writer, not an admin.
3. Use an invalid group key sentinel to prove unauthorized publish returns `not allowed to write` before encryption, while an authorized control reaches `encrypt group message`.
4. Use a valid group key plus invalid private-key sentinel to prove unauthorized publish returns `not allowed to write` before signing, while an authorized control reaches `sign group message`.
5. Assert unauthorized attempts return empty message id, peer count `0`, and emit no `group:publish_debug` or supplied message id/text marker.

## Required Gates

| Gate | Command |
|---|---|
| Focused GP-002 regression | `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'TestGP002')` |
| Adjacent publish/authorization selector | `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'GP002|GA005|PublishGroupMessage|Authorization|AllowedWriter|Unauthorized')` |
| Broader publish/security selector | `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node ./internal ./crypto -run 'PublishGroupMessage|GroupTopicValidator|GroupEnvelope|Authorization|Unauthorized|GP002')` |
| Race selector | `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test -race ./node -run 'TestGP002|GA005|PublishGroupMessage')` |
| Hygiene | `gofmt` on changed Go files and `git diff --check` |

## Closure Bar

- Source row GP-002 is updated to `Covered` with concrete file/test/gate evidence.
- Breakdown row 106, row disposition, session ledger, ordered row, session closure ledger, and closure progress are updated to `covered/accepted`.
- No `accepted_with_explicit_follow_up` is used for row-owned gaps.
- Residual work, if any, is outside GP-002 ownership and does not mask a repo-owned blocker.

## Execution Progress

| Time | Phase | Result |
|---|---|---|
| 2026-05-13 00:19:03 CEST | Implementation completed | Added `go-mknoon/node/pubsub_delivery_test.go::TestGP002PublishBlocksUnauthorizedWriterBeforeEncryptSignAndPublish`. The test proves unauthorized announcement-group writers are rejected before encryption and signing using invalid key/private-key sentinels with authorized controls, and emits no publish debug or supplied message-id/text marker. |
| 2026-05-13 00:19:03 CEST | Closure completed | Source matrix GP-002 and breakdown row 106 were updated to `Covered`/`covered/accepted` with exact row-owned evidence. |

## Gate Evidence

| Gate | Result |
|---|---|
| Focused GP-002 regression | `GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'TestGP002'` passed (`ok github.com/mknoon/go-mknoon/node 1.856s`). |
| Adjacent publish/authorization selector | `GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'GP002\|GA005\|PublishGroupMessage\|Authorization\|AllowedWriter\|Unauthorized'` passed (`ok github.com/mknoon/go-mknoon/node 9.670s`). |
| Broader publish/security selector | `GOCACHE=/private/tmp/codex-go-build-cache go test ./node ./internal ./crypto -run 'PublishGroupMessage\|GroupTopicValidator\|GroupEnvelope\|Authorization\|Unauthorized\|GP002'` passed (`ok node 7.616s`, `ok internal 0.576s`, `ok crypto 0.862s`). |
| Race selector | `GOCACHE=/private/tmp/codex-go-build-cache go test -race ./node -run 'TestGP002\|GA005\|PublishGroupMessage'` passed (`ok github.com/mknoon/go-mknoon/node 7.986s`). |
| Hygiene | `gofmt` on `go-mknoon/node/pubsub_delivery_test.go` and `git diff --check` passed. |

## Final Verdict

`accepted` / `closed`. GP-002 is covered by exact row-owned Go node proof. No production code changed because existing `PublishGroupMessage` already checks `isAllowedWriter` before payload construction, encryption, signing, topic publish, and publish-debug emission. The proof verifies unauthorized announcement writers return `not allowed to write`, empty message id, peer count `0`, and no publish-debug/message marker side effects, while authorized sentinel controls prove the test would catch late encryption or signing. Residual-only: none for GP-002. GI-031 remains the next unresolved P0 row; no final program verdict is written.
