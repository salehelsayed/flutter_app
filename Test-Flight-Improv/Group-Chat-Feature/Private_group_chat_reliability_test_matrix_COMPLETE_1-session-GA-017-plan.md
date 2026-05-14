# GA-017 Session Plan: Sibling Device Self-Skip Delivery

## Status

Status: accepted

## Source Row

Source matrix row: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` row `GA-017`

## Gap-Closure Reconciliation

| Time | Actor | Inputs Compared | Finding | Action |
|---|---|---|---|---|
| 2026-05-12 23:05:00 CEST | Controller | Source matrix GA-017 row; breakdown row 97; production `go-mknoon/node/pubsub.go::handleGroupSubscription`; adjacent GA-010 active-device delivery proof and GA-012 transport binding proof | Source row GA-017 was still `Open` and implementation-ready. `handleGroupSubscription` skipped every envelope whose logical `SenderId` equaled the local peer id, which can drop a sibling-device envelope when the local S1 peer id is also the account-level sender id and the actual transport peer is S2. | Add transport-aware self-echo handling plus exact Go node regression proving sibling-device delivery and same-transport echo preservation. |

## Scope

GA-017 owns only subscription self-echo classification for logical multi-device accounts. It must not change validator membership/device authorization, key package checks, revoked/inactive rejection, legacy missing-transport rejection, app-level Flutter group state, relay state, or UI behavior.

## Execution Contract

1. Add a narrow helper in `go-mknoon/node/pubsub.go` that classifies local transport echoes by explicit `SenderTransportPeerId` when present, with legacy `SenderId` fallback only when transport binding is omitted.
2. Change `handleGroupSubscription` to use that helper instead of dropping every envelope where `env.SenderId == selfPeerId`.
3. Add a row-owned test named `TestGA017SiblingDeviceMessageIsNotSkippedAsSelf` in `go-mknoon/node/pubsub_delivery_test.go`.
4. Build a private chat group with one logical member whose S1 local peer id equals account-level `SenderId`, and whose active S2 device is bound to a different transport peer.
5. Prove S2's signed envelope accepts in pure validation, is not classified as a local transport echo for S1, while an S1 same-transport envelope remains classified as local echo.
6. Raw-publish the S2 envelope and prove S1 emits `group_message:received` with expected group/sender/device/transport/text/key epoch and no validation/decrypt/payload side effects.

## Required Gates

| Gate | Command |
|---|---|
| Focused GA-017 regression | `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'TestGA017')` |
| Adjacent sibling/device selector | `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'GA017|GA016|Sibling|Self|TransportPeer|DeviceBound')` |
| Broader validator selector | `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node ./internal ./crypto -run 'GroupTopicValidator|GroupEnvelope|GroupMessage|Sibling|Self|TransportPeer|GA017')` |
| Race selector | `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test -race ./node -run 'TestGA017|Sibling|Self|TransportPeer')` |
| Hygiene | `gofmt` on changed Go files and `git diff --check` |

## Closure Bar

- Source row GA-017 is updated to `Covered` with concrete file/test/gate evidence.
- Breakdown row 97, row disposition, session ledger, ordered row, session closure ledger, and closure progress are updated to `covered/accepted`.
- No `accepted_with_explicit_follow_up` is used for row-owned gaps.
- Residual work, if any, is outside GA-017 ownership and does not mask a repo-owned blocker.

## Execution Progress

| Time | Phase | Result |
|---|---|---|
| 2026-05-12 23:05:00 CEST | Implementation completed | Added `go-mknoon/node/pubsub.go::groupEnvelopeOriginatesFromLocalTransport` and changed `handleGroupSubscription` to skip local transport echoes rather than all matching logical senders. Added `go-mknoon/node/pubsub_delivery_test.go::TestGA017SiblingDeviceMessageIsNotSkippedAsSelf`, which proves a valid S2 sibling-device message is received by S1 even when `SenderId == S1 peer id`, while same-transport S1 envelopes still classify as local echoes. |
| 2026-05-12 23:05:00 CEST | Closure completed | Source matrix GA-017, breakdown row 97, row disposition, session ledger, ordered row, session closure ledger, and closure progress were updated to `Covered` / `covered/accepted`. |

## Gate Evidence

| Gate | Result |
|---|---|
| `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'TestGA017')` | Passed: `ok github.com/mknoon/go-mknoon/node 2.602s`. |
| `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'GA017\|GA016\|Sibling\|Self\|TransportPeer\|DeviceBound')` | Passed: `ok github.com/mknoon/go-mknoon/node 11.759s`. |
| `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node ./internal ./crypto -run 'GroupTopicValidator\|GroupEnvelope\|GroupMessage\|Sibling\|Self\|TransportPeer\|GA017')` | Passed: `ok node 11.933s`, `ok internal 0.287s`, `ok crypto 0.568s`. |
| `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test -race ./node -run 'TestGA017\|Sibling\|Self\|TransportPeer')` | Passed: `ok github.com/mknoon/go-mknoon/node 10.081s`. |
| `gofmt -w go-mknoon/node/pubsub.go go-mknoon/node/pubsub_delivery_test.go` and `git diff --check` | Passed. |

## Final Verdict

`accepted` / `closed`. GA-017 is covered by a narrow transport-aware subscription self-echo fix plus exact row-owned Go node proof. Sibling S2 traffic with logical `SenderId == S1 peer id` is delivered to S1 when the explicit transport peer is S2, and same-transport S1 echoes remain skipped. Residual-only: none. GP-005 remains the next unresolved P0 row; no final program verdict is written.
