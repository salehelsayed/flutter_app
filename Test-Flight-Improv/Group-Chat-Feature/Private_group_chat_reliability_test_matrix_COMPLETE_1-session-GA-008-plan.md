# GA-008 Session Plan: Legacy Single-Device Wrong Device Rejection

## Status

Status: accepted

## Source Row

Source matrix row: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` row `GA-008`

## Gap-Closure Reconciliation

| Time | Actor | Inputs Compared | Finding | Action |
|---|---|---|---|---|
| 2026-05-12 22:10:00 CEST | Controller | Source matrix GA-008 row; breakdown row 88; legacy fallback code in `go-mknoon/node/pubsub.go::activeMemberDeviceForEnvelope`; adjacent device binding tests in `go-mknoon/node/pubsub_test.go` and `go-mknoon/node/pubsub_decryption_failure_test.go`; GA-007 closure evidence | Source row GA-008 is still `Open` and implementation-ready. Existing adjacent tests prove parts of wrong-device rejection, but there is no exact row-owned live proof for a legacy single-device member with no `Devices` list and a wrong `senderDeviceId`. | Add exact live Go node proof. No production code change is expected unless the exact test exposes a missing legacy fallback rejection. |

## Scope

GA-008 owns only legacy single-device rejection when an envelope supplies a `senderDeviceId` different from `member.PeerId`. It must not change default acceptance, transport mismatch, sender public-key mismatch, multi-device policy, membership, key rotation, relay behavior, or Flutter UI.

## Execution Contract

1. Add a row-owned test named for GA-008 in `go-mknoon/node/pubsub_delivery_test.go`.
2. Build a two-node private chat group where B is a current legacy member with no `Devices` list and `PublicKey == pubB`.
3. Build a valid B-signed envelope with `senderDeviceId != B` while leaving the transport peer as B.
4. Prove pure validation rejects as `reject:unbound_device`.
5. Bypass only B's local validator to allow raw fanout, publish from B, and prove A emits `group:validation_rejected` reason `unbound_device` with no message/reaction/decrypt/payload-parse/plaintext side effects.

## Required Gates

| Gate | Command |
|---|---|
| Focused GA-008 regression | `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'TestGA008')` |
| Adjacent device fallback selector | `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'GA008|GA007|Legacy|Unbound|DeviceBound|TransportPeer')` |
| Broader validator selector | `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node ./internal ./crypto -run 'GroupTopicValidator|GroupEnvelope|GroupMessage|Unbound|Legacy|GA008')` |
| Race selector | `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test -race ./node -run 'TestGA008|Unbound|Legacy')` |
| Hygiene | `gofmt` on changed Go files and `git diff --check` |

## Closure Bar

- Source row GA-008 is updated to `Covered` with concrete file/test/gate evidence.
- Breakdown row 88, row disposition, session ledger, ordered row, session closure ledger, and closure progress are updated to `covered/accepted`.
- No `accepted_with_explicit_follow_up` is used for row-owned gaps.
- Residual work, if any, is outside GA-008 ownership and does not mask a repo-owned blocker.

## Execution Progress

| Time | Phase | Files/Evidence | Result | Next Action |
|---|---|---|---|---|
| 2026-05-12 22:12:00 CEST | Executor completed | `go-mknoon/node/pubsub_delivery_test.go` | Added `TestGA008LegacySingleDeviceMemberRejectsWrongSenderDeviceID`, proving a legacy no-`Devices` member with a mismatched `senderDeviceId` rejects as `unbound_device` in pure validation and live A-side validation, with no payload side effects. No production code changed. | Record gate evidence and close GA-008. |
| 2026-05-12 22:12:00 CEST | QA completed | Same test plus `go-mknoon/node/pubsub.go::activeMemberDeviceForEnvelope` | Required evidence passed: focused, adjacent, broader node/internal/crypto, race, gofmt, and diff hygiene. Existing production fallback rejection satisfies the row once exact row-owned proof is present. | Close GA-008 as Covered in source matrix and breakdown. |

## Gate Evidence

| Gate | Result |
|---|---|
| Focused GA-008 regression | Pass: `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'TestGA008')` -> `ok node 3.590s` |
| Adjacent device fallback selector | Pass: `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'GA008\|GA007\|Legacy\|Unbound\|DeviceBound\|TransportPeer')` -> `ok node 11.035s` |
| Broader validator selector | Pass: `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node ./internal ./crypto -run 'GroupTopicValidator\|GroupEnvelope\|GroupMessage\|Unbound\|Legacy\|GA008')` -> `ok node 10.489s`, `ok internal 0.668s`, `ok crypto 0.346s` |
| Race selector | Pass: `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test -race ./node -run 'TestGA008\|Unbound\|Legacy')` -> `ok node 8.323s` |
| Hygiene | Pass: `gofmt -w go-mknoon/node/pubsub_delivery_test.go`; `git diff --check` |

## Final Verdict

Accepted and closed. GA-008 is `Covered` by tests-only Go node proof. Files changed: `go-mknoon/node/pubsub_delivery_test.go`; this GA-008 plan. No production code changed, no blockers remain, and GP-005 remains the next unresolved P0 row. No final program verdict was written.
