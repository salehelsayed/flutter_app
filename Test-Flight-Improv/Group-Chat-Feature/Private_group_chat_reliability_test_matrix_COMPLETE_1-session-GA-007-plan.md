# GA-007 Session Plan: Legacy Single-Device Default Binding Acceptance

## Status

Status: accepted

## Source Row

Source matrix row: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` row `GA-007`

## Gap-Closure Reconciliation

| Time | Actor | Inputs Compared | Finding | Action |
|---|---|---|---|---|
| 2026-05-12 22:06:00 CEST | Controller | Source matrix GA-007 row; breakdown row 87; existing default-device fallback tests in `go-mknoon/node/pubsub_test.go`; live private-chat delivery tests in `go-mknoon/node/pubsub_delivery_test.go`; production fallback in `go-mknoon/node/pubsub.go::activeMemberDeviceForEnvelope` | Source row GA-007 is still `Open` and implementation-ready. Existing adjacent tests and live no-device messages imply the fallback works, but there is no exact `GA-007` row-owned live proof covering both omitted device/transport fields and explicit default binding fields equal to `member.PeerId`. | Add exact live Go node proof. No production code change is expected unless the exact test exposes a missing legacy fallback. |

## Scope

GA-007 owns only the legacy single-device fallback for members whose `Devices` list is empty. It may add Go node tests around omitted and default-equal sender binding fields. It must not change multi-device policy, wrong-device rejection, transport mismatch rejection, membership, key rotation, relay behavior, or Flutter UI.

## Execution Contract

1. Add a row-owned test named for GA-007 in `go-mknoon/node/pubsub_delivery_test.go`.
2. Build a two-node private chat group where B is a current member with `Devices == nil` and `PublicKey == pubB`.
3. Prove an otherwise valid B envelope with omitted `senderDeviceId`, `senderTransportPeerId`, and `senderDevicePublicKey` accepts in pure validation and live delivery.
4. Prove an otherwise valid B envelope with `senderDeviceId == B`, `senderTransportPeerId == B`, and `senderDevicePublicKey == pubB` accepts in pure validation and live delivery.
5. Assert no validation/decrypt/payload-parse side effects are emitted for accepted legacy default-binding traffic.

## Required Gates

| Gate | Command |
|---|---|
| Focused GA-007 regression | `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'TestGA007')` |
| Adjacent device fallback selector | `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'GA007|Legacy|DefaultDevice|DeviceBound|Unbound|TransportPeer')` |
| Broader validator selector | `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node ./internal ./crypto -run 'GroupTopicValidator|GroupEnvelope|GroupMessage|DefaultDevice|Legacy|GA007')` |
| Race selector | `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test -race ./node -run 'TestGA007|DefaultDevice|Legacy')` |
| Hygiene | `gofmt` on changed Go files and `git diff --check` |

## Closure Bar

- Source row GA-007 is updated to `Covered` with concrete file/test/gate evidence.
- Breakdown row 87, row disposition, session ledger, ordered row, session closure ledger, and closure progress are updated to `covered/accepted`.
- No `accepted_with_explicit_follow_up` is used for row-owned gaps.
- Residual work, if any, is outside GA-007 ownership and does not mask a repo-owned blocker.

## Execution Progress

| Time | Phase | Files/Evidence | Result | Next Action |
|---|---|---|---|---|
| 2026-05-12 22:08:00 CEST | Executor completed | `go-mknoon/node/pubsub_delivery_test.go` | Added `TestGA007LegacySingleDeviceMemberAcceptsDefaultDeviceBinding`, proving the legacy no-`Devices` fallback accepts omitted sender binding fields and explicit default fields equal to B's peer/public key through pure validation and live delivery. No production code changed. | Record gate evidence and close GA-007. |
| 2026-05-12 22:08:00 CEST | QA completed | Same test plus `go-mknoon/node/pubsub.go::activeMemberDeviceForEnvelope` | Required evidence passed: focused, adjacent, broader node/internal/crypto, race, gofmt, and diff hygiene. Existing production fallback satisfies the row once exact row-owned proof is present. | Close GA-007 as Covered in source matrix and breakdown. |

## Gate Evidence

| Gate | Result |
|---|---|
| Focused GA-007 regression | Pass: `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'TestGA007')` -> `ok node 4.141s` |
| Adjacent device fallback selector | Pass: `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'GA007\|Legacy\|DefaultDevice\|DeviceBound\|Unbound\|TransportPeer')` -> `ok node 7.045s` |
| Broader validator selector | Pass: `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node ./internal ./crypto -run 'GroupTopicValidator\|GroupEnvelope\|GroupMessage\|DefaultDevice\|Legacy\|GA007')` -> `ok node 7.330s`, `ok internal 0.552s`, `ok crypto 0.394s` |
| Race selector | Pass: `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test -race ./node -run 'TestGA007\|DefaultDevice\|Legacy')` -> `ok node 5.198s` |
| Hygiene | Pass: `gofmt -w go-mknoon/node/pubsub_delivery_test.go`; `git diff --check` |

## Final Verdict

Accepted and closed. GA-007 is `Covered` by tests-only Go node proof. Files changed: `go-mknoon/node/pubsub_delivery_test.go`; this GA-007 plan. No production code changed, no blockers remain, and GP-005 remains the next unresolved P0 row. No final program verdict was written.
