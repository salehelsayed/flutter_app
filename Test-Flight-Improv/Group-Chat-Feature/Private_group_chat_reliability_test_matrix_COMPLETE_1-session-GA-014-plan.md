# GA-014 Session Plan: Inactive Device Publish Rejection

## Status

Status: accepted

## Source Row

Source matrix row: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` row `GA-014`

## Gap-Closure Reconciliation

| Time | Actor | Inputs Compared | Finding | Action |
|---|---|---|---|---|
| 2026-05-12 22:49:10 CEST | Controller | Source matrix GA-014 row; breakdown row 94; production `go-mknoon/node/pubsub.go::activeMemberDeviceForEnvelope`; adjacent GA-010 active-device proof and GA-013 revoked-device proof | Source row GA-014 was still `Open` and implementation-ready. Production already skips devices whose `Status` is non-empty and not `active`, but exact row-owned proof for an inactive device signing its own envelope was missing. | Add exact Go node regression. No production code change was required because the existing active-device selector already rejects inactive devices as unbound. |

## Scope

GA-014 owns only publication from an inactive device listed on an otherwise current member. It must not change active-device acceptance, revoked-device rejection, missing field rejection, key-package mismatch rejection, legacy fallback, membership, discovery, key rotation, relay behavior, or Flutter UI.

## Execution Contract

1. Add a row-owned test named for GA-014 in `go-mknoon/node/pubsub_delivery_test.go`.
2. Build a private chat group where logical member B has inactive device S bound to transport peer P with device signing key and key package K.
3. Build a device-signed `group_message` envelope from S with matching sender/device/transport/public-key/key-package fields.
4. Prove pure validation from P rejects as `reject:unbound_device`.
5. Publish the raw inactive-device envelope from P after bypassing only P's local topic validator, then prove A emits `group:validation_rejected` reason `unbound_device` and no message/decrypt/payload side effects.

## Required Gates

| Gate | Command |
|---|---|
| Focused GA-014 regression | `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'TestGA014')` |
| Adjacent device selector | `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'GA014|GA013|Inactive|Unbound|DeviceBound')` |
| Broader validator selector | `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node ./internal ./crypto -run 'GroupTopicValidator|GroupEnvelope|GroupMessage|Inactive|Unbound|GA014')` |
| Race selector | `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test -race ./node -run 'TestGA014|Inactive|Unbound')` |
| Hygiene | `gofmt` on changed Go files and `git diff --check` |

## Closure Bar

- Source row GA-014 is updated to `Covered` with concrete file/test/gate evidence.
- Breakdown row 94, row disposition, session ledger, ordered row, session closure ledger, and closure progress are updated to `covered/accepted`.
- No `accepted_with_explicit_follow_up` is used for row-owned gaps.
- Residual work, if any, is outside GA-014 ownership and does not mask a repo-owned blocker.

## Execution Progress

| Time | Phase | Result |
|---|---|---|
| 2026-05-12 22:49:10 CEST | Implementation completed | Added `go-mknoon/node/pubsub_delivery_test.go::TestGA014InactiveDeviceCannotPublish`. The test signs with the inactive device's own signing key, proves pure validation from transport P rejects as `unbound_device`, raw-publishes from P after bypassing only P's local validator, and proves A rejects without payload side effects. |
| 2026-05-12 22:49:10 CEST | Closure completed | Source matrix GA-014, breakdown row 94, row disposition, session ledger, ordered row, session closure ledger, and closure progress were updated to `Covered` / `covered/accepted`. |

## Gate Evidence

| Gate | Result |
|---|---|
| `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'TestGA014')` | Passed: `ok github.com/mknoon/go-mknoon/node 3.662s`. |
| `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'GA014\|GA013\|Inactive\|Unbound\|DeviceBound')` | Passed: `ok github.com/mknoon/go-mknoon/node 7.117s`. |
| `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node ./internal ./crypto -run 'GroupTopicValidator\|GroupEnvelope\|GroupMessage\|Inactive\|Unbound\|GA014')` | Passed: `ok node 7.010s`, `ok internal 0.344s`, `ok crypto 0.622s`. |
| `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test -race ./node -run 'TestGA014\|Inactive\|Unbound')` | Passed: `ok github.com/mknoon/go-mknoon/node 4.826s`. |
| `gofmt -w go-mknoon/node/pubsub_delivery_test.go` and `git diff --check` | Passed. |

## Final Verdict

`accepted` / `closed`. GA-014 is covered by exact row-owned Go node proof where the inactive device itself signs the envelope and is rejected before decrypt/render. No production code changed because the existing active-device selector already rejects inactive devices as unbound. Residual-only: none. GP-005 remains the next unresolved P0 row; no final program verdict is written.
