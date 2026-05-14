# GP-003 Session Plan: Publish Preserves Caller-Provided Message ID

## Status

Status: accepted/closed

## Source Row

Source matrix row: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` row `GP-003`

## Gap-Closure Reconciliation

| Time | Actor | Inputs Compared | Finding | Action |
|---|---|---|---|---|
| 2026-05-13 00:21:33 CEST | Controller | Source matrix GP-003 row; breakdown row 107; production `go-mknoon/node/pubsub.go::PublishGroupMessage`; existing `TestPublishGroupMessage_DuplicateProvidedMessageIdRemainsVisibleAfterDecrypt`; Flutter `send_group_message_use_case_test.dart` provided-id coverage | Planning-time gap: existing tests prove adjacent behavior, including duplicate provided ids, but the row lacked exact row-owned `GP-003` proof tying the returned id, publish diagnostic id, and decrypted receive-event id to the same caller-provided id. | Add exact Go node regression evidence. No production code change is expected unless the row-owned test exposes a gap. |

## Scope

GP-003 owns the Go node live publish contract for a non-empty caller-provided `messageId`. It must not change generated-id behavior, duplicate-id behavior, durable inbox retry semantics, Flutter repository behavior, or UI state unless the row-owned regression proves the Go publish contract is wrong.

## Execution Contract

1. Add a row-owned Go node regression named `TestGP003PublishUsesCallerProvidedMessageIDInPayloadAndReceivedEvent`.
2. Join a two-node chat group with sender and receiver collectors.
3. Publish with a non-empty caller-provided `messageId`.
4. Assert `PublishGroupMessage` returns the provided id and a positive topic peer count.
5. Assert sender `group:publish_debug.messageId` and receiver decrypted `group_message:received.messageId` both equal the provided id, with matching group, sender, text, and key epoch.

## Required Gates

| Gate | Command |
|---|---|
| Focused GP-003 regression | `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'TestGP003')` |
| Adjacent message-id selector | `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'GP003|DuplicateProvidedMessageId|PublishGroupMessage|MessageId')` |
| Broader publish/event selector | `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node ./internal ./crypto -run 'PublishGroupMessage|GroupMessage|GroupEnvelope|MessageId|GP003')` |
| Race selector | `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test -race ./node -run 'TestGP003|DuplicateProvidedMessageId|PublishGroupMessage')` |
| Hygiene | `gofmt` on changed Go files and `git diff --check` |

## Closure Bar

- Source row GP-003 is updated to `Covered` with concrete file/test/gate evidence.
- Breakdown row 107, row disposition, session ledger, ordered row, session closure ledger, and closure progress are updated to `covered/accepted`.
- No `accepted_with_explicit_follow_up` is used for row-owned gaps.
- Residual work, if any, is outside GP-003 ownership and does not mask a repo-owned blocker.

## Execution Progress

| Time | Phase | Result |
|---|---|---|
| 2026-05-13 00:23:23 CEST | Implementation completed | Added `go-mknoon/node/pubsub_delivery_test.go::TestGP003PublishUsesCallerProvidedMessageIDInPayloadAndReceivedEvent`. The test proves the caller-provided message id is returned by publish, emitted in sender publish diagnostics, and carried through the decrypted receiver event. |
| 2026-05-13 00:23:23 CEST | Closure completed | Source matrix GP-003 and breakdown row 107 were updated to `Covered`/`covered/accepted` with exact row-owned evidence. |

## Gate Evidence

| Gate | Result |
|---|---|
| Focused GP-003 regression | `GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'TestGP003'` passed (`ok github.com/mknoon/go-mknoon/node 1.060s`). |
| Adjacent message-id selector | `GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'GP003\|DuplicateProvidedMessageId\|PublishGroupMessage\|MessageId'` passed (`ok github.com/mknoon/go-mknoon/node 1.728s`). |
| Broader publish/event selector | `GOCACHE=/private/tmp/codex-go-build-cache go test ./node ./internal ./crypto -run 'PublishGroupMessage\|GroupMessage\|GroupEnvelope\|MessageId\|GP003'` passed (`ok node 1.708s`, `ok internal 0.523s`, `ok crypto 0.708s`). |
| Race selector | `GOCACHE=/private/tmp/codex-go-build-cache go test -race ./node -run 'TestGP003\|DuplicateProvidedMessageId\|PublishGroupMessage'` passed (`ok github.com/mknoon/go-mknoon/node 3.106s`). |
| Hygiene | `gofmt` on `go-mknoon/node/pubsub_delivery_test.go` and `git diff --check` passed. |

## Final Verdict

`accepted` / `closed`. GP-003 is covered by exact row-owned Go node proof. No production code changed because existing `PublishGroupMessage` already preserves a non-empty caller-provided `messageId` through the returned value, encrypted payload extra, publish diagnostic, and decrypted receive event. Residual-only: none for GP-003. GI-031 remains the next unresolved P0 row; no final program verdict is written.
