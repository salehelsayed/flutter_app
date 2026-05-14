# GP-004 Session Plan: Publish Generates UUID When Message ID Is Empty

## Status

Status: accepted/closed

## Source Row

Source matrix row: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` row `GP-004`

## Gap-Closure Reconciliation

| Time | Actor | Inputs Compared | Finding | Action |
|---|---|---|---|---|
| 2026-05-13 00:27:07 CEST | Controller | Source matrix GP-004 row; breakdown row 195; production `go-mknoon/node/pubsub.go::PublishGroupMessage`; existing `TestPublishGroupMessage_ReturnsPeerCountZero_WhenNoPeers`; Flutter `send_group_message_use_case_test.dart` UUID coverage | Planning-time gap: adjacent tests prove non-empty ids and Flutter UUID defaults, but the Go node row lacked exact `GP-004` proof that empty publish ids generate a UUID and that the same generated id is stable through publish diagnostics and decrypted receive events. | Add exact Go node regression evidence. No production code change is expected unless the row-owned test exposes a gap. |

## Scope

GP-004 owns the Go node live publish contract for an empty caller `messageId`. It must not change caller-provided id behavior, durable inbox retry semantics, Flutter repository behavior, or UI state unless the row-owned regression proves the Go generated-id contract is wrong.

## Execution Contract

1. Add a row-owned Go node regression named `TestGP004PublishGeneratesUUIDWhenMessageIDEmpty`.
2. Join a two-node chat group with sender and receiver collectors.
3. Publish with an empty `messageId`.
4. Assert `PublishGroupMessage` returns a UUID v4 id and a positive topic peer count.
5. Assert sender `group:publish_debug.messageId` and receiver decrypted `group_message:received.messageId` both equal the generated id, with matching group, sender, text, and key epoch.

## Required Gates

| Gate | Command |
|---|---|
| Focused GP-004 regression | `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'TestGP004')` |
| Adjacent generated-id selector | `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'GP004|ReturnsPeerCountZero|PublishGroupMessage|MessageId')` |
| Broader publish/event selector | `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node ./internal ./crypto -run 'PublishGroupMessage|GroupMessage|GroupEnvelope|MessageId|GP004')` |
| Race selector | `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test -race ./node -run 'TestGP004|ReturnsPeerCountZero|PublishGroupMessage')` |
| Hygiene | `gofmt` on changed Go files and `git diff --check` |

## Closure Bar

- Source row GP-004 is updated to `Covered` with concrete file/test/gate evidence.
- Breakdown row 195, row disposition, session ledger, ordered row, session closure ledger, and closure progress are updated to `covered/accepted`.
- No `accepted_with_explicit_follow_up` is used for row-owned gaps.
- Residual work, if any, is outside GP-004 ownership and does not mask a repo-owned blocker.

## Execution Progress

| Time | Phase | Result |
|---|---|---|
| 2026-05-13 00:28:35 CEST | Implementation completed | Added `go-mknoon/node/pubsub_delivery_test.go::TestGP004PublishGeneratesUUIDWhenMessageIDEmpty`. The test proves empty message ids generate UUID v4 ids and the same generated id is emitted through publish diagnostics and decrypted receive events. |
| 2026-05-13 00:28:35 CEST | Closure completed | Source matrix GP-004 and breakdown row 195 were updated to `Covered`/`covered/accepted` with exact row-owned evidence. |

## Gate Evidence

| Gate | Result |
|---|---|
| Focused GP-004 regression | `GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'TestGP004'` passed (`ok github.com/mknoon/go-mknoon/node 1.084s`). |
| Adjacent generated-id selector | `GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'GP004\|ReturnsPeerCountZero\|PublishGroupMessage\|MessageId'` passed (`ok github.com/mknoon/go-mknoon/node 1.707s`). |
| Broader publish/event selector | `GOCACHE=/private/tmp/codex-go-build-cache go test ./node ./internal ./crypto -run 'PublishGroupMessage\|GroupMessage\|GroupEnvelope\|MessageId\|GP004'` passed (`ok node 1.710s`, `ok internal 0.868s`, `ok crypto 0.620s`). |
| Race selector | `GOCACHE=/private/tmp/codex-go-build-cache go test -race ./node -run 'TestGP004\|ReturnsPeerCountZero\|PublishGroupMessage'` passed (`ok github.com/mknoon/go-mknoon/node 3.122s`). |
| Hygiene | `gofmt` on `go-mknoon/node/pubsub_delivery_test.go` and `git diff --check` passed. |

## Final Verdict

`accepted` / `closed`. GP-004 is covered by exact row-owned Go node proof. No production code changed because existing `PublishGroupMessage` already generates a UUID when the caller leaves `messageId` empty and preserves that generated id through the returned value, encrypted payload extra, publish diagnostic, and decrypted receive event. Residual-only: none for GP-004. GI-031 remains the next unresolved P0 row; no final program verdict is written.
