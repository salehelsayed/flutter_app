# GA-019 Session Plan: Duplicate Signing Key Policy

## Status

Status: accepted

## Source Row

Source matrix row: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` row `GA-019`

## Gap-Closure Reconciliation

| Time | Actor | Inputs Compared | Finding | Action |
|---|---|---|---|---|
| 2026-05-12 23:15:00 CEST | Controller | Source matrix GA-019 row; breakdown row 98; production `go-mknoon/node/pubsub.go` validator/publish/config paths; adjacent GA-010 active-device proof, GA-017 sibling-device proof, and GK-026 senderId tamper proof | Source row GA-019 was still `Open` and implementation-ready. Signature data does not bind `senderId`, so a config that allows two different member IDs to share one active signing key can make claimed-sender attribution depend on ambiguous config identity alone. | Add active signing-key uniqueness policy and exact Go node regression proving config rejection plus fail-closed pure/live validation and local publish behavior. |

## Scope

GA-019 owns only active signing-key reuse across different member IDs. It must not change same-member multi-device handling, transport-peer binding, key-package binding, revoked/inactive rejection, duplicate device ID policy, duplicate transport policy, Flutter group repository behavior, or UI behavior.

## Execution Contract

1. Add a Go group-config policy helper that rejects active signing keys reused by different member IDs.
2. Apply the policy to initial `JoinGroupTopic`, local message/reaction publish checks, and production topic validation.
3. Update the pure validator helper so row-owned tests assert the same fail-closed contract without a host.
4. Add a row-owned test named `TestGA019PublicKeyReuseAcrossMemberIDsRejectsPolicy` in `go-mknoon/node/pubsub_delivery_test.go`.
5. Prove a safe config where only C owns the shared key accepts C traffic, while an ambiguous B/C duplicate active device signing key rejects at config policy and pure validation.
6. Prove initial join with the ambiguous config stores no topic/config state.
7. Prove live raw publish under an updated ambiguous receiver config emits `group:validation_rejected` reason `ambiguous_signing_key` and no payload side effects, and local publish is blocked.

## Required Gates

| Gate | Command |
|---|---|
| Focused GA-019 regression | `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'TestGA019')` |
| Adjacent signing-key/device selector | `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'GA019|GA017|SigningKey|DeviceSigning|Ambiguous|PublicKeyReuse|TransportPeer|DeviceBound')` |
| Broader validator selector | `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node ./internal ./crypto -run 'GroupTopicValidator|GroupEnvelope|GroupMessage|SigningKey|DeviceSigning|Ambiguous|PublicKeyReuse|GA019')` |
| Race selector | `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test -race ./node -run 'TestGA019|SigningKey|DeviceSigning|Ambiguous|PublicKeyReuse')` |
| Hygiene | `gofmt` on changed Go files and `git diff --check` |

## Closure Bar

- Source row GA-019 is updated to `Covered` with concrete file/test/gate evidence.
- Breakdown row 98, row disposition, session ledger, ordered row, session closure ledger, and closure progress are updated to `covered/accepted`.
- No `accepted_with_explicit_follow_up` is used for row-owned gaps.
- Residual work, if any, is outside GA-019 ownership and does not mask a repo-owned blocker.

## Execution Progress

| Time | Phase | Result |
|---|---|---|
| 2026-05-12 23:15:00 CEST | Implementation completed | Added `go-mknoon/node/pubsub.go::validateGroupConfigSigningKeyUniqueness`, wired it into `JoinGroupTopic`, local message/reaction publish, and production topic validation, and updated the pure validator helper in `go-mknoon/node/pubsub_test.go`. Added `go-mknoon/node/pubsub_delivery_test.go::TestGA019PublicKeyReuseAcrossMemberIDsRejectsPolicy`, which proves duplicate active device signing keys across member IDs fail closed. |
| 2026-05-12 23:15:00 CEST | Closure completed | Source matrix GA-019, breakdown row 98, row disposition, session ledger, ordered row, session closure ledger, and closure progress were updated to `Covered` / `covered/accepted`. |

## Gate Evidence

| Gate | Result |
|---|---|
| `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'TestGA019')` | Passed: `ok github.com/mknoon/go-mknoon/node 3.591s`. |
| `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'GA019\|GA017\|SigningKey\|DeviceSigning\|Ambiguous\|PublicKeyReuse\|TransportPeer\|DeviceBound')` | Passed: `ok github.com/mknoon/go-mknoon/node 12.514s`. |
| `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node ./internal ./crypto -run 'GroupTopicValidator\|GroupEnvelope\|GroupMessage\|SigningKey\|DeviceSigning\|Ambiguous\|PublicKeyReuse\|GA019')` | Passed: `ok node 6.290s`, `ok internal 0.601s`, `ok crypto 0.892s`. |
| `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test -race ./node -run 'TestGA019\|SigningKey\|DeviceSigning\|Ambiguous\|PublicKeyReuse')` | Passed: `ok github.com/mknoon/go-mknoon/node 4.688s`. |
| `gofmt -w go-mknoon/node/pubsub.go go-mknoon/node/pubsub_test.go go-mknoon/node/pubsub_delivery_test.go` and `git diff --check` | Passed. |

## Final Verdict

`accepted` / `closed`. GA-019 is covered by active signing-key uniqueness policy plus exact row-owned Go node proof. Duplicate active signing keys across different member IDs are rejected at initial join, pure validation, production live validation, and local publish, with no claimed-sender payload rendered. Residual-only: none. GP-005 remains the next unresolved P0 row; no final program verdict is written.
