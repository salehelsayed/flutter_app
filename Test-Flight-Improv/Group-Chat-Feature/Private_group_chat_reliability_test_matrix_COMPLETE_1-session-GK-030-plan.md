# GK-030 Session Plan: Preserve Required Extra Fields

Status: accepted/closed

Source breakdown: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md`
Source matrix row: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` row `GK-030`

## Planning Progress

| Timestamp | Role | Files inspected since last update | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-05-12 20:49:55 CEST | Evidence Collector started | Source matrix GK-030 row; breakdown row 80; `go-mknoon/node/pubsub.go`; `go-mknoon/node/pubsub_test.go`; `go-mknoon/node/pubsub_delivery_test.go`; `go-mknoon/internal/group_envelope.go` | Source row GK-030 is `Open` and the plan file was missing. `PublishGroupMessage` stores all publish `opts` in `GroupMessagePayload.Extra`, but `buildGroupMessageReceivedEvent` forwards only `media`, `messageId`, and `quotedMessageId`, dropping attachments, delivery IDs, and unknown fields before the app can render or dedupe them. | Add event-extra preservation with protected canonical fields, plus unit and live publish proof. |
| 2026-05-12 20:49:55 CEST | Reviewer completed | Same files plus existing delivery/event collectors and publish tests | GK-030 is a repo-owned event mapping gap. The safe production change is limited to copying all payload `Extra` keys into the received event except canonical fields sourced from the envelope or parsed payload, so extras cannot spoof group/sender/device/transport/user/text/timestamp/epoch/decrypt/delivery values. | Implement the mapping helper and exact GK-030 tests, then run required Go gates. |

## Real Scope

GK-030 owns only preservation of app-required extra fields from encrypted group message payloads into `group_message:received` events. It may update `go-mknoon/node/pubsub.go`, pure node tests, and live node publish-delivery tests. It must not change signature data, encryption, payload marshal/unmarshal semantics, key epochs, replay entitlement, Flutter UI rendering, relay behavior, or reaction handling.

## Required Implementation

1. Preserve all non-canonical keys in `GroupMessagePayload.Extra` on `group_message:received`, including media, quote, attachments, delivery IDs, client IDs, publish timestamp, and unknown fields.
2. Keep canonical event attribution and body fields sourced from the envelope or parsed payload: `groupId`, `senderId`, `senderDeviceId`, `transportPeerId`, `senderUsername`, `keyEpoch`, `text`, and `timestamp`.
3. Keep runtime metrics owned by the receive path, not payload extras: `decryptMs` and `deliveryMs`.
4. Preserve existing message ID, quote, and media behavior.
5. Prove publish-time `opts` survive through encrypted payload receive events without mutating the input opts map.

## Required Evidence

| Evidence | Command |
| --- | --- |
| Focused GK-030 regression | `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'TestGK030')` |
| Adjacent publish/event mapping coverage | `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'BuildGroupMessageExtra|BuildGroupMessageReceivedEvent|PublishGroupMessage|GK030')` |
| Broader Go node/internal/crypto selector | `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node ./internal ./crypto -run 'GroupTopicValidator|GroupEnvelope|GroupMessage|PayloadParse|Delivery|GK030')` |
| Race check for live PubSub evidence | `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test -race ./node -run 'TestGK030|PublishGroupMessage')` |
| Formatting and whitespace | `gofmt -w go-mknoon/node/pubsub.go go-mknoon/node/pubsub_test.go go-mknoon/node/pubsub_delivery_test.go`; `git diff --check` |

## Done Criteria

- Source matrix GK-030 can move to `Covered` only after concrete file/test/gate evidence is recorded.
- Attachments, delivery IDs, client IDs, publish timestamp, media, quote, message ID, and unknown extras are emitted on `group_message:received`.
- Payload extras cannot override envelope or parsed-payload canonical event fields.
- Existing publish, parser, delivery, and message ID behavior remains compatible.
- Residual work, if any, must be outside GK-030 row ownership and must not hide an unresolved repo-owned blocker.

## Execution Progress

| Timestamp | Phase | Files inspected or touched | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-05-12 20:49:55 CEST | Contract extracted | `Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GK-030-plan.md`; `go-mknoon/node/pubsub.go`; `go-mknoon/node/pubsub_test.go`; `go-mknoon/node/pubsub_delivery_test.go` | Execute GK-030 locally in the controller. The row needs a small production receive-event mapper change because encrypted payload extras beyond `media`, `messageId`, and `quotedMessageId` were being dropped before app delivery. | Patch receive-event extra preservation and row-owned unit/live tests, then run required Go gates. |
| 2026-05-12 20:56:58 CEST | Executor completed | `go-mknoon/node/pubsub.go`; `go-mknoon/node/pubsub_test.go`; `go-mknoon/node/pubsub_delivery_test.go` | `buildGroupMessageReceivedEvent` now copies all payload `Extra` keys except canonical envelope/payload fields and receive-path metrics. Added pure proof that attachments, delivery IDs, client IDs, publish timestamp, media, quote, message ID, and unknown extras are preserved while canonical fields are protected, plus live publish proof that `opts` survive encrypted delivery. | Record gate evidence and close GK-030. |
| 2026-05-12 20:56:58 CEST | QA completed | Same files plus publish/decrypt event path | Required evidence passed. The first focused run exposed a test-input issue: live publish `opts` used `senderTransportPeerId`, which this API correctly treats as an envelope binding field and rejected as `peer_mismatch`; the live test was narrowed to payload-only canonical spoof attempts while envelope-field protection remains covered by the pure mapper test. | Close GK-030 as Covered in source matrix and breakdown. |

## Evidence Captured

| Evidence | Result |
|---|---|
| Focused GK-030 regression | Pass: `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'TestGK030')` -> `ok node 0.613s` after correcting the live test fixture to avoid envelope-binding opts |
| Adjacent publish/event mapping coverage | Pass: `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'BuildGroupMessageExtra\|BuildGroupMessageReceivedEvent\|PublishGroupMessage\|GK030')` -> `ok node 1.109s` |
| Broader Go node/internal/crypto selector | Pass: `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node ./internal ./crypto -run 'GroupTopicValidator\|GroupEnvelope\|GroupMessage\|PayloadParse\|Delivery\|GK030')` -> `ok node 24.226s`, `ok internal 0.629s`, `ok crypto 0.904s` |
| Race check for live PubSub evidence | Pass: `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test -race ./node -run 'TestGK030\|PublishGroupMessage')` -> `ok node 2.598s` |
| Formatting and whitespace | Pass: `gofmt -w go-mknoon/node/pubsub.go go-mknoon/node/pubsub_test.go go-mknoon/node/pubsub_delivery_test.go`; `git diff --check` |

## Final Verdict

Final verdict: accepted

Spawned-agent isolation used: no.

Local sequential fallback used: yes.

Files changed: `go-mknoon/node/pubsub.go`; `go-mknoon/node/pubsub_test.go`; `go-mknoon/node/pubsub_delivery_test.go`; this GK-030 plan.

Tests added or updated: `TestGK030BuildGroupMessageReceivedEventPreservesExtrasAndProtectsCanonicalFields`; `TestGK030PublishGroupMessagePreservesExtraFieldsInReceivedEvent`.

Blocking issues remaining: none.

Non-blocking follow-ups deferred: none.

Why safe to consider complete: required app extras now survive into `group_message:received`, canonical event attribution/body fields and receive-path metrics remain protected from payload extras, live encrypted publish delivery proves full `opts` preservation, and all required Go evidence passed.

## Closure Note

Controller closure recorded at 2026-05-12 20:56 CEST. The source matrix GK-030 row and breakdown GK-030 inventory, disposition, closure ledger, session ledger, and ordered session row are now `Covered`/`covered/accepted` with concrete code, tests, and gate evidence from this plan. No blockers or follow-ups remain. GK-033 is covered separately and GA-001 is covered separately and GA-002 is covered separately and GA-003 is covered separately and GP-005 remains the next unresolved P0 row, and no final program verdict was written.
