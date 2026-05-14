# GA-015 Session Plan: Key Package Mismatch Rejection

## Status

Status: accepted

## Source Row

Source matrix row: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` row `GA-015`

## Gap-Closure Reconciliation

| Time | Actor | Inputs Compared | Finding | Action |
|---|---|---|---|---|
| 2026-05-12 22:54:15 CEST | Controller | Source matrix GA-015 row; breakdown row 95; production `go-mknoon/node/pubsub.go::activeMemberDeviceForEnvelope`; adjacent GA-010 active-device proof and GM-021 fresh key-package binding proof | Source row GA-015 was still `Open` and implementation-ready. Production already rejects non-empty `SenderKeyPackageId` values that do not match the configured active device `KeyPackageId`, but exact row-owned proof was missing. | Add exact Go node regression. No production code change was required because the existing active-device selector already rejects key-package mismatches as unbound. |

## Scope

GA-015 owns only publication from an otherwise active device whose envelope claims a stale or wrong sender key package id. It must not change active-device acceptance, inactive/revoked device rejection, missing field rejection, key rotation, membership, discovery, relay behavior, or Flutter UI.

## Execution Contract

1. Add a row-owned test named for GA-015 in `go-mknoon/node/pubsub_delivery_test.go`.
2. Build a private chat group where logical member B has active device S bound to transport peer P with device signing key and active key package K1.
3. Build a device-signed `group_message` envelope from S with matching sender/device/transport/public-key fields but mismatched `SenderKeyPackageId == K2`.
4. Prove pure validation from P rejects as `reject:unbound_device`.
5. Publish the raw mismatched-key-package envelope from P after bypassing only P's local topic validator, then prove A emits `group:validation_rejected` reason `unbound_device` and no message/decrypt/payload side effects.

## Required Gates

| Gate | Command |
|---|---|
| Focused GA-015 regression | `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'TestGA015')` |
| Adjacent device selector | `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'GA015|GA014|KeyPackage|Unbound|DeviceBound')` |
| Broader validator selector | `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node ./internal ./crypto -run 'GroupTopicValidator|GroupEnvelope|GroupMessage|KeyPackage|Unbound|GA015')` |
| Race selector | `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test -race ./node -run 'TestGA015|KeyPackage|Unbound')` |
| Hygiene | `gofmt` on changed Go files and `git diff --check` |

## Closure Bar

- Source row GA-015 is updated to `Covered` with concrete file/test/gate evidence.
- Breakdown row 95, row disposition, session ledger, ordered row, session closure ledger, and closure progress are updated to `covered/accepted`.
- No `accepted_with_explicit_follow_up` is used for row-owned gaps.
- Residual work, if any, is outside GA-015 ownership and does not mask a repo-owned blocker.

## Execution Progress

| Time | Phase | Result |
|---|---|---|
| 2026-05-12 22:54:15 CEST | Implementation completed | Added `go-mknoon/node/pubsub_delivery_test.go::TestGA015KeyPackageIDMismatchRejects`. The test signs with the active device's own signing key while claiming a different sender key package id, proves pure validation from transport P rejects as `unbound_device`, raw-publishes from P after bypassing only P's local validator, and proves A rejects without payload side effects. |
| 2026-05-12 22:54:15 CEST | Closure completed | Source matrix GA-015, breakdown row 95, row disposition, session ledger, ordered row, session closure ledger, and closure progress were updated to `Covered` / `covered/accepted`. |

## Gate Evidence

| Gate | Result |
|---|---|
| `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'TestGA015')` | Passed: `ok github.com/mknoon/go-mknoon/node 3.599s`. |
| `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'GA015\|GA014\|KeyPackage\|Unbound\|DeviceBound')` | Passed: `ok github.com/mknoon/go-mknoon/node 6.995s`. |
| `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node ./internal ./crypto -run 'GroupTopicValidator\|GroupEnvelope\|GroupMessage\|KeyPackage\|Unbound\|GA015')` | Passed: `ok node 6.240s`, `ok internal 0.912s`, `ok crypto 0.659s`. |
| `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test -race ./node -run 'TestGA015\|KeyPackage\|Unbound')` | Passed: `ok github.com/mknoon/go-mknoon/node 4.697s`. |
| `gofmt -w go-mknoon/node/pubsub_delivery_test.go` and `git diff --check` | Passed. |

## Final Verdict

`accepted` / `closed`. GA-015 is covered by exact row-owned Go node proof where an active device signs the envelope but claims a mismatched key package id and is rejected before decrypt/render. No production code changed because the existing active-device selector already rejects key-package mismatches as unbound. Residual-only: none. GP-005 remains the next unresolved P0 row; no final program verdict is written.
