# GA-001 Session Plan: Current Member Private Chat Publish

Status: accepted/closed

Source breakdown: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md`
Source matrix row: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` row `GA-001`

## Planning Progress

| Timestamp | Role | Files inspected since last update | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-05-12 21:22:03 CEST | Evidence Collector started | Source matrix GA-001 row; breakdown row 82; `go-mknoon/node/pubsub.go`; `go-mknoon/node/pubsub_delivery_test.go`; `go-mknoon/node/pubsub_test.go`; `go-mknoon/node/pubsub_authorization_forward_test.go` | Source row GA-001 is `Open`, evidence-gated, and the plan file was missing. Existing delivery tests prove general chat publish behavior, but no exact GA-001 row-owned test asserts current member publish in a private chat group emits exactly once to another member. | Add exact live Go node delivery proof for a current member in `GroupTypeChat`, then run scoped Go gates. |
| 2026-05-12 21:22:03 CEST | Reviewer completed | Same files plus existing collector and two-node group harness | GA-001 is currently a proof gap unless exact testing exposes a bug. The safe closure path is tests-only: use the existing local two-node chat harness, publish with an explicit message ID, assert peer count, assert exactly one received event, and assert event attribution/body fields. | Add row-owned test, run focused/adjacent/broader/race gates, then close the row or reclassify if code is needed. |

## Real Scope

GA-001 owns only proof that a current member can publish a message in a private chat group and the other current member receives exactly one event. It may add Go node delivery tests. It must not change authorization policy, device binding, role update behavior, reaction behavior, key epoch behavior, Flutter UI, relay behavior, or offline replay.

## Required Implementation

1. Prove a current `GroupTypeChat` member can call `PublishGroupMessage` successfully.
2. Prove the publish returns the explicit message ID and at least one topic peer.
3. Prove the receiving member emits exactly one `group_message:received` event for that message.
4. Prove the event carries the expected `groupId`, `senderId`, `senderUsername`, `messageId`, `text`, and `keyEpoch`.
5. Leave production unchanged if existing behavior satisfies the row.

## Required Evidence

| Evidence | Command |
| --- | --- |
| Focused GA-001 regression | `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'TestGA001')` |
| Adjacent publish/authorization coverage | `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'GA001|PublishGroupMessage|GroupTopicValidator|Authorization')` |
| Broader Go node/internal/crypto selector | `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node ./internal ./crypto -run 'GroupTopicValidator|GroupEnvelope|GroupMessage|PublishGroupMessage|GA001')` |
| Race check for live PubSub evidence | `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test -race ./node -run 'TestGA001|PublishGroupMessage')` |
| Formatting and whitespace | `gofmt -w go-mknoon/node/pubsub_delivery_test.go`; `git diff --check` |

## Done Criteria

- Source matrix GA-001 can move to `Covered` only after concrete file/test/gate evidence is recorded.
- A current private-chat member publish succeeds and emits exactly one received event to the other member.
- Event attribution and body fields match the sender/message.
- Residual work, if any, must be outside GA-001 row ownership and must not hide an unresolved repo-owned blocker.

## Execution Progress

| Timestamp | Phase | Files inspected or touched | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-05-12 21:22:03 CEST | Contract extracted | `Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GA-001-plan.md`; `go-mknoon/node/pubsub.go`; `go-mknoon/node/pubsub_delivery_test.go` | Execute GA-001 locally in the controller. Existing production appears to satisfy current-member chat publish; add exact live proof and avoid production changes unless the test fails. | Add row-owned delivery test, then run required Go gates. |
| 2026-05-12 21:24:57 CEST | Executor completed | `go-mknoon/node/pubsub_delivery_test.go` | Added `TestGA001CurrentMemberPublishesPrivateChatMessageExactlyOnce`, proving a current `GroupTypeChat` member publishes successfully with explicit message ID, topic peer count is positive, and the receiving member emits exactly one correctly attributed `group_message:received`. No production code changed. | Record gate evidence and close GA-001. |
| 2026-05-12 21:24:57 CEST | QA completed | Same file plus `go-mknoon/node/pubsub.go` publish/validator path | Required evidence passed: focused, adjacent, broader node/internal/crypto, race, gofmt, and diff hygiene. The row is satisfied by existing publish/authorization behavior plus exact tests. | Close GA-001 as Covered in source matrix and breakdown. |

## Evidence Captured

| Evidence | Result |
|---|---|
| Focused GA-001 regression | Pass: `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'TestGA001')` -> `ok node 1.161s` |
| Adjacent publish/authorization coverage | Pass: `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'GA001\|PublishGroupMessage\|GroupTopicValidator\|Authorization')` -> `ok node 3.797s` |
| Broader Go node/internal/crypto selector | Pass: `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node ./internal ./crypto -run 'GroupTopicValidator\|GroupEnvelope\|GroupMessage\|PublishGroupMessage\|GA001')` -> `ok node 4.109s`, `ok internal 0.898s`, `ok crypto 0.325s` |
| Race check for live PubSub evidence | Pass: `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test -race ./node -run 'TestGA001\|PublishGroupMessage')` -> `ok node 3.088s` |
| Formatting and whitespace | Pass: `gofmt -w go-mknoon/node/pubsub_delivery_test.go`; `git diff --check` |

## Final Verdict

Final verdict: accepted

Spawned-agent isolation used: no.

Local sequential fallback used: yes.

Files changed: `go-mknoon/node/pubsub_delivery_test.go`; this GA-001 plan.

Tests added or updated: `TestGA001CurrentMemberPublishesPrivateChatMessageExactlyOnce`.

Blocking issues remaining: none.

Non-blocking follow-ups deferred: none.

Why safe to consider complete: exact live Go node proof shows a current private chat member can publish and the other current member receives exactly one correctly attributed message event, and all required gates passed.

## Closure Note

Controller closure recorded at 2026-05-12 21:24 CEST. The source matrix GA-001 row and breakdown GA-001 inventory, disposition, closure ledger, session ledger, and ordered session row are now `Covered`/`covered/accepted` with concrete tests and gate evidence from this plan. No blockers or follow-ups remain. GA-002 is covered separately and GA-003 is covered separately and GP-005 remains the next unresolved P0 row, and no final program verdict was written.
