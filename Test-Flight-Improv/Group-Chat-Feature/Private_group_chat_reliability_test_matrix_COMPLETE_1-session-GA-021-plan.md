# GA-021 Session Plan: Duplicate Transport Peer Rejection

## Status

Status: accepted

## Source Row

Source matrix row: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` row `GA-021`

## Gap-Closure Reconciliation

| Time | Actor | Inputs Compared | Finding | Action |
|---|---|---|---|---|
| 2026-05-12 23:26:31 CEST | Controller | Source matrix GA-021 row; breakdown row 100; production `go-mknoon/node/pubsub.go::activeMemberDeviceForEnvelope`, `validateGroupConfigSigningKeyUniqueness`, `JoinGroupTopic`, `PublishGroupMessage`, `PublishGroupReaction`, and `groupTopicValidator`; adjacent GA-019 duplicate-signing-key proof and GA-020 duplicate-device proof | Source row GA-021 was still `Open` and implementation-ready. Existing code rejects reused active signing keys across members and validates the claimed member/device/transport tuple, but it does not reject active `transportPeerId` reuse across different member IDs at config/publish/validator boundaries. | Add a repo-owned config identity policy for duplicate active transport peer IDs across members, wire it through join/local publish/validator/pure validation, and add exact Go node regression evidence. |

## Scope

GA-021 owns duplicate active `transportPeerId` entries across different member IDs in group configs. It must not change same-member duplicate device-ID selection, key-package mismatch behavior, revoked/inactive device rejection, legacy single-device compatibility, signing-key uniqueness behavior, Flutter UI behavior, or relay transport routing.

## Execution Contract

1. Add production validation in `go-mknoon/node/pubsub.go` that rejects active transport peer ID reuse across different member IDs while preserving same-member duplicate-device normalization behavior.
2. Wire the validation through `JoinGroupTopic`, `PublishGroupMessage`, `PublishGroupReaction`, and `groupTopicValidator`.
3. Update pure test validation helper to expose a distinct `reject:ambiguous_transport_peer` reason.
4. Add a row-owned test named `TestGA021DuplicateTransportPeerAcrossMembersRejectsPolicy` in `go-mknoon/node/pubsub_delivery_test.go`.
5. Prove safe config delivery accepts, ambiguous config join is rejected without stored state, pure validation rejects as `ambiguous_transport_peer`, live raw publish emits only validation rejection, and local publish is blocked before attribution/decrypt/render.

## Required Gates

| Gate | Command |
|---|---|
| Focused GA-021 regression | `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'TestGA021')` |
| Adjacent transport identity selector | `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'GA021|GA020|TransportPeer|Ambiguous|DeviceBound|DuplicateTransport')` |
| Broader validator selector | `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node ./internal ./crypto -run 'GroupTopicValidator|GroupEnvelope|GroupMessage|TransportPeer|Ambiguous|DuplicateTransport|GA021')` |
| Race selector | `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test -race ./node -run 'TestGA021|TransportPeer|Ambiguous|DuplicateTransport')` |
| Hygiene | `gofmt` on changed Go files and `git diff --check` |

## Closure Bar

- Source row GA-021 is updated to `Covered` with concrete file/test/gate evidence.
- Breakdown row 100, row disposition, session ledger, ordered row, session closure ledger, and closure progress are updated to `covered/accepted`.
- No `accepted_with_explicit_follow_up` is used for row-owned gaps.
- Residual work, if any, is outside GA-021 ownership and does not mask a repo-owned blocker.

## Execution Progress

| Time | Phase | Result |
|---|---|---|
| 2026-05-12 23:30:14 CEST | Implementation completed | Added `go-mknoon/node/pubsub.go::validateGroupConfigTransportPeerUniqueness` plus `validateGroupConfigIdentityUniqueness`, and wired the identity policy through `JoinGroupTopic`, local message/reaction publish, production topic validation, and the pure validator helper. Added `go-mknoon/node/pubsub_delivery_test.go::TestGA021DuplicateTransportPeerAcrossMembersRejectsPolicy`, proving duplicate active transport peer IDs across different member IDs fail closed while a safe config still accepts. |
| 2026-05-12 23:30:14 CEST | Closure completed | Source matrix GA-021, breakdown row 100, row disposition, session ledger, ordered row, session closure ledger, and closure progress were updated to `Covered` / `covered/accepted`. |

## Gate Evidence

| Gate | Result |
|---|---|
| `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'TestGA021')` | Passed: `ok github.com/mknoon/go-mknoon/node 3.611s`. |
| `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'GA021\|GA020\|TransportPeer\|Ambiguous\|DeviceBound\|DuplicateTransport')` | Passed: `ok github.com/mknoon/go-mknoon/node 14.722s`. |
| `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node ./internal ./crypto -run 'GroupTopicValidator\|GroupEnvelope\|GroupMessage\|TransportPeer\|Ambiguous\|DuplicateTransport\|GA021')` | Passed: `ok node 13.119s`, `ok internal 0.480s`, `ok crypto 0.755s`. |
| `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test -race ./node -run 'TestGA021\|TransportPeer\|Ambiguous\|DuplicateTransport')` | Passed: `ok github.com/mknoon/go-mknoon/node 10.984s`. |
| `gofmt -w go-mknoon/node/pubsub.go go-mknoon/node/pubsub_test.go go-mknoon/node/pubsub_delivery_test.go` and `git diff --check` | Passed. |

## Final Verdict

`accepted` / `closed`. GA-021 is covered by code-plus-tests Go node proof. Duplicate active transport peer IDs across different member IDs now reject at config/join, pure validation, live receive-side validation, and local publish before decrypt/render attribution. Residual-only: none. GP-005 remains the next unresolved P0 row; no final program verdict is written.
