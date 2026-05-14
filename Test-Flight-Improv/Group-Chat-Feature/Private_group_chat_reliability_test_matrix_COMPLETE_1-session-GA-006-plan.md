# GA-006 Session Plan: Sender Transport Peer Mismatch Rejection

## Status

Status: accepted

## Source Row

Source matrix row: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` row `GA-006`

## Gap-Closure Reconciliation

| Time | Actor | Inputs Compared | Finding | Action |
|---|---|---|---|---|
| 2026-05-12 22:01:00 CEST | Controller | Source matrix GA-006 row; breakdown row 86; existing pure transport-peer mismatch tests in `go-mknoon/node/pubsub_test.go`; adjacent GK-027 device/transport tamper tests in `go-mknoon/node/pubsub_decryption_failure_test.go`; production transport-peer binding in `go-mknoon/node/pubsub.go` | Source row GA-006 is still `Open` and implementation-ready. Existing adjacent tests prove the underlying guard, but there is no exact `GA-006` row-owned live proof that an envelope claiming sender B but delivered by transport peer X is rejected as `peer_mismatch` with no payload side effects. | Add exact live Go node proof. No production code change is expected unless the exact test exposes a missing transport-peer guard. |

## Scope

GA-006 owns only top-level sender/transport-peer binding for group envelopes. It may add Go node validator/delivery tests. It must not change device binding, multi-device policy, membership, role authorization, key rotation, relay behavior, or Flutter UI.

## Execution Contract

1. Add a row-owned test named for GA-006 in `go-mknoon/node/pubsub_authorization_forward_test.go`.
2. Build a group where B is a current configured member and X is a joined publishing transport peer.
3. Build a valid B-signed envelope that omits `senderTransportPeerId`, so the expected transport peer defaults to B.
4. Prove pure validation against the receiver config rejects the envelope as `reject:peer_mismatch` when delivered from X.
5. Bypass only X's local topic validator to allow raw fanout, publish the B-claimed envelope from X, and prove A emits `group:validation_rejected` reason `peer_mismatch` with no message/reaction/decrypt/payload-parse/plaintext side effects.

## Required Gates

| Gate | Command |
|---|---|
| Focused GA-006 regression | `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'TestGA006')` |
| Adjacent transport selector | `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'GA006|GK027|TransportPeer|PeerMismatch|ValidationReject')` |
| Broader validator selector | `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node ./internal ./crypto -run 'GroupTopicValidator|GroupEnvelope|GroupMessage|TransportPeer|PeerMismatch|GA006')` |
| Race selector | `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test -race ./node -run 'TestGA006|TransportPeer|PeerMismatch|ValidationReject')` |
| Hygiene | `gofmt` on changed Go files and `git diff --check` |

## Closure Bar

- Source row GA-006 is updated to `Covered` with concrete file/test/gate evidence.
- Breakdown row 86, row disposition, session ledger, ordered row, session closure ledger, and closure progress are updated to `covered/accepted`.
- No `accepted_with_explicit_follow_up` is used for row-owned gaps.
- Residual work, if any, is outside GA-006 ownership and does not mask a repo-owned blocker.

## Execution Progress

| Time | Phase | Files/Evidence | Result | Next Action |
|---|---|---|---|---|
| 2026-05-12 22:04:00 CEST | Executor completed | `go-mknoon/node/pubsub_authorization_forward_test.go` | Added `TestGA006SenderTransportPeerMismatchRejects`, proving a valid B-signed envelope that omits `senderTransportPeerId` accepts from B but rejects from transport peer X as `peer_mismatch`; live raw fanout from X reaches A after bypassing only X's local validator, and A emits `group:validation_rejected` reason `peer_mismatch` with no payload side effects. No production code changed. | Record gate evidence and close GA-006. |
| 2026-05-12 22:04:00 CEST | QA completed | Same test plus `go-mknoon/node/pubsub.go` transport-peer validator path | Required evidence passed: focused, adjacent, broader node/internal/crypto, race, gofmt, and diff hygiene. Existing production transport-peer binding satisfies the row once exact row-owned proof is present. | Close GA-006 as Covered in source matrix and breakdown. |

## Gate Evidence

| Gate | Result |
|---|---|
| Focused GA-006 regression | Pass: `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'TestGA006')` -> `ok node 3.554s` |
| Adjacent transport selector | Pass: `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'GA006\|GK027\|TransportPeer\|PeerMismatch\|ValidationReject')` -> `ok node 10.009s` |
| Broader validator selector | Pass: `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node ./internal ./crypto -run 'GroupTopicValidator\|GroupEnvelope\|GroupMessage\|TransportPeer\|PeerMismatch\|GA006')` -> `ok node 6.401s`, `ok internal 0.946s`, `ok crypto 0.696s` |
| Race selector | Pass: `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test -race ./node -run 'TestGA006\|TransportPeer\|PeerMismatch\|ValidationReject')` -> `ok node 4.768s` |
| Hygiene | Pass: `gofmt -w go-mknoon/node/pubsub_authorization_forward_test.go`; `git diff --check` |

## Final Verdict

Accepted and closed. GA-006 is `Covered` by tests-only Go node proof. Files changed: `go-mknoon/node/pubsub_authorization_forward_test.go`; this GA-006 plan. No production code changed, no blockers remain, and GP-005 remains the next unresolved P0 row. No final program verdict was written.
