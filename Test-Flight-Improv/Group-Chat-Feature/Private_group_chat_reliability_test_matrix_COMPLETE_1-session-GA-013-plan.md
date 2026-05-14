# GA-013 Session Plan: Revoked Device Publish Rejection

## Status

Status: accepted

## Source Row

Source matrix row: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` row `GA-013`

## Gap-Closure Reconciliation

| Time | Actor | Inputs Compared | Finding | Action |
|---|---|---|---|---|
| 2026-05-12 22:38:49 CEST | Controller | Source matrix GA-013 row; breakdown row 93; production `go-mknoon/node/pubsub.go::activeMemberDeviceForEnvelope`; adjacent GK-027 binding tamper proof; GA-010 active-device acceptance proof | Source row GA-013 is still `Open` and implementation-ready. Adjacent GK-027 proves tampering a valid active envelope to a revoked device rejects, but GA-013 needs exact row-owned proof where the revoked device itself signs and publishes. Production already rejects non-active devices before signature/decrypt, but exact live proof is missing. | Add exact Go node regression. No production code change is expected unless the row-owned test exposes acceptance or missing diagnostics. |

## Scope

GA-013 owns only publication from a revoked device listed on an otherwise current member. It must not change active-device acceptance, missing field rejection, inactive-device rejection, key-package mismatch rejection, legacy fallback, membership, discovery, key rotation, relay behavior, or Flutter UI.

## Execution Contract

1. Add a row-owned test named for GA-013 in `go-mknoon/node/pubsub_delivery_test.go`.
2. Build a private chat group where logical member B has revoked device S bound to transport peer P with device signing key and key package K.
3. Build a device-signed `group_message` envelope from S with matching sender/device/transport/public-key/key-package fields.
4. Prove pure validation from P rejects as `reject:unbound_device`.
5. Publish the raw revoked-device envelope from P after bypassing only P's local topic validator, then prove A emits `group:validation_rejected` reason `unbound_device` and no message/decrypt/payload side effects.

## Required Gates

| Gate | Command |
|---|---|
| Focused GA-013 regression | `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'TestGA013')` |
| Adjacent device selector | `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'GA013|GA010|GA011|Revoked|Unbound|DeviceBound')` |
| Broader validator selector | `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node ./internal ./crypto -run 'GroupTopicValidator|GroupEnvelope|GroupMessage|Revoked|Unbound|GA013')` |
| Race selector | `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test -race ./node -run 'TestGA013|Revoked|Unbound')` |
| Hygiene | `gofmt` on changed Go files and `git diff --check` |

## Closure Bar

- Source row GA-013 is updated to `Covered` with concrete file/test/gate evidence.
- Breakdown row 93, row disposition, session ledger, ordered row, session closure ledger, and closure progress are updated to `covered/accepted`.
- No `accepted_with_explicit_follow_up` is used for row-owned gaps.
- Residual work, if any, is outside GA-013 ownership and does not mask a repo-owned blocker.

## Execution Progress

| Time | Phase | Result |
|---|---|---|
| 2026-05-12 22:43:14 CEST | Implementation completed | Added `go-mknoon/node/pubsub_delivery_test.go::TestGA013RevokedDeviceCannotPublish`. The test signs with the revoked device's own signing key, proves pure validation from transport P rejects as `unbound_device`, raw-publishes from P after bypassing only P's local validator, and proves A rejects without payload side effects. |
| 2026-05-12 22:43:14 CEST | Closure completed | Source matrix GA-013, breakdown row 93, row disposition, session ledger, ordered row, session closure ledger, and closure progress were updated to `Covered` / `covered/accepted`. |

## Gate Evidence

| Gate | Result |
|---|---|
| `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'TestGA013')` | Passed: `ok github.com/mknoon/go-mknoon/node 3.554s`. |
| `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'GA013\|GA010\|GA011\|Revoked\|Unbound\|DeviceBound')` | Passed: `ok github.com/mknoon/go-mknoon/node 13.436s`. |
| `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node ./internal ./crypto -run 'GroupTopicValidator\|GroupEnvelope\|GroupMessage\|Revoked\|Unbound\|GA013')` | Passed: `ok node 12.048s`, `ok internal 0.576s`, `ok crypto 1.070s`. |
| `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test -race ./node -run 'TestGA013\|Revoked\|Unbound')` | Passed: `ok github.com/mknoon/go-mknoon/node 9.880s`. |
| `gofmt -w go-mknoon/node/pubsub_delivery_test.go` and `git diff --check` | Passed. |

## Final Verdict

`accepted` / `closed`. GA-013 is covered by exact row-owned Go node proof where the revoked device itself signs the envelope and is rejected before decrypt/render. No production code changed because the existing active-device selector already rejects revoked devices as unbound. Residual-only: none. GP-005 remains the next unresolved P0 row; no final program verdict is written.
