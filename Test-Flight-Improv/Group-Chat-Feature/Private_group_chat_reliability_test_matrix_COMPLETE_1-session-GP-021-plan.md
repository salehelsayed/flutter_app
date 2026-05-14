# GP-021 Session Plan: Receive Event Identity Fields

## Status

Status: accepted/closed

## Source Row

Source matrix row: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` row `GP-021`

## Gap-Closure Reconciliation

| Time | Actor | Inputs Compared | Finding | Action |
|---|---|---|---|---|
| 2026-05-13 01:40:00 CEST | Controller | Source matrix GP-021 row; breakdown row 116; production `go-mknoon/node/pubsub.go::handleGroupSubscription` and `buildGroupMessageReceivedEvent`; existing pure mapping test `TestGK030BuildGroupMessageReceivedEventPreservesExtrasAndProtectsCanonicalFields`; existing live sibling-device proof `TestGA017SiblingDeviceMessageIsNotSkippedAsSelf` | Existing tests cover pieces of the receive event contract, but the row remains open because no exact row-owned live proof asserts the full emitted `group_message:received` field set: `groupId`, `senderId`, `senderDeviceId`, `transportPeerId`, `senderUsername`, `keyEpoch`, `text`, `timestamp`, and `messageId`. | Add exact Go node regression `TestGP021MessageReceiveEmitsIdentityTransportAndMessageFields`. No production code change is expected unless the test exposes a missing field. |
| 2026-05-13 01:47:00 CEST | Controller | New GP-021 Go regression; focused and adjacent Go gates; source matrix row GP-021; breakdown row 116 | Row-owned proof now exists. The test publishes a valid encrypted device-bound `group_message` through a live local PubSub path and asserts the receiver emits every required identity, transport, payload, epoch, timestamp, and message id field with no rejection/decrypt/parse diagnostics. | Close GP-021 as `Covered`/accepted with tests-only evidence and continue from GI-031, the next unresolved P0 row. |

## Scope

GP-021 owns the Go node receive event contract for valid incoming private group `group_message` envelopes. The receiver must emit the identity, device, transport, payload, epoch, timestamp, and message id fields needed by app-layer persistence and routing.

Out of scope: decryption failure diagnostics, malformed-payload continuation, duplicate delivery dedupe, UI rendering, and durable inbox replay; those are separate GP rows.

## Execution Contract

1. Add row-owned Go regression `TestGP021MessageReceiveEmitsIdentityTransportAndMessageFields`.
2. Build a valid encrypted `group_message` envelope from an active member device with explicit `senderDeviceId` and `senderTransportPeerId`.
3. Include payload `username`, `text`, `timestamp`, and `extra.messageId`.
4. Publish the raw envelope over a live local PubSub connection and assert the receiver emits exactly the required fields.
5. Assert no validation, decryption, or payload-parse diagnostic is emitted for the valid row-owned envelope.

## Required Gates

| Gate | Command |
|---|---|
| Focused GP-021 Go regression | `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'TestGP021')` |
| Adjacent receive-event selector | `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'GP021|GK030|GA017|MessageReceivedEvent|group_message:received|DeviceMessage')` |
| Hygiene | `gofmt` on changed Go files and `git diff --check` |

## Dirty Worktree Snapshot

Captured before execution: worktree remains dirty with prior rollout changes and GP-016 closure artifacts. GP-021 scope is limited to row-owned Go tests, this plan, and closure documentation updates unless the focused regression exposes a production gap.

## Execution Progress

| Time | Phase | Files touched | Evidence |
|---|---|---|---|
| 2026-05-13 01:47:00 CEST | Executor/QA completed | `go-mknoon/node/pubsub_delivery_test.go` | Added `TestGP021MessageReceiveEmitsIdentityTransportAndMessageFields`. The test builds a valid active-device `group_message` envelope with explicit `senderDeviceId`, `senderTransportPeerId`, device public key, key package id, payload username, text, timestamp, and `extra.messageId`; publishes it over a live local PubSub path; and proves the receiver emits all required fields without validation, decrypt, or parse diagnostics. |

## Gate Evidence

| Gate | Result |
|---|---|
| Focused GP-021 Go regression | `GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'TestGP021'` passed (`ok github.com/mknoon/go-mknoon/node 2.582s`). |
| Adjacent receive-event selector | `GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'GP021\|GK030\|GA017\|MessageReceivedEvent\|group_message:received\|DeviceMessage'` passed (`ok github.com/mknoon/go-mknoon/node 4.555s`). |
| Hygiene | `gofmt` passed on `go-mknoon/node/pubsub_delivery_test.go`; `git diff --check` passed. |

## Final Verdict

Accepted/closed. GP-021 is `Covered` by tests-only Go node evidence: a valid incoming device-bound `group_message` emits the required receive event fields exactly (`groupId`, `senderId`, `senderDeviceId`, `transportPeerId`, `senderUsername`, `keyEpoch`, `text`, `timestamp`, and `messageId`) over the live PubSub receive path. Residual-only none for GP-021; no `accepted_with_explicit_follow_up` is used.

## Closure Bar

- Source row GP-021 is updated to `Covered` with concrete file/test/gate evidence.
- Breakdown row 116, row disposition, session ledger, ordered row, session closure ledger, and closure progress are updated to `covered/accepted`.
- No `accepted_with_explicit_follow_up` is used for row-owned gaps.
- Residual work, if any, is outside GP-021 ownership and does not mask a repo-owned blocker.
