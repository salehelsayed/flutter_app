# GA-011 Session Plan: Missing SenderDeviceId Rejection

## Status

Status: accepted

## Source Row

Source matrix row: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` row `GA-011`

## Gap-Closure Reconciliation

| Time | Actor | Inputs Compared | Finding | Action |
|---|---|---|---|---|
| 2026-05-12 22:27:36 CEST | Controller | Source matrix GA-011 row; breakdown row 91; production `go-mknoon/node/pubsub.go::activeMemberDeviceForEnvelope`; adjacent GA-010 active-device acceptance proof; GK-027 device/transport tamper rejection proof | Source row GA-011 is still `Open` and implementation-ready. Production already rejects multi-device envelopes with empty `SenderDeviceId` as `unbound_device`, but there is no exact `GA-011` row-owned proof covering pure validation and live receive-side rejection. | Add exact Go node regression. No production code change is expected unless the row-owned test exposes acceptance or a missing diagnostic. |

## Scope

GA-011 owns only the missing `SenderDeviceId` case for a member with a non-empty `Devices` list. It must not change GA-010 active-device acceptance, missing transport fallback behavior, revoked/inactive device rejection, key-package mismatch rejection, legacy single-device fallback, membership, discovery, key rotation, relay behavior, or Flutter UI.

## Execution Contract

1. Add a row-owned test named for GA-011 in `go-mknoon/node/pubsub_delivery_test.go`.
2. Build a private chat group where logical member B has active device S bound to transport peer P with a device signing key and key package K.
3. Build a valid device-bound envelope, then delete only the top-level `senderDeviceId` field without changing sender, transport, device public key, key package, ciphertext, nonce, signature, group, type, or epoch.
4. Prove pure validation from transport P rejects as `reject:unbound_device`.
5. Publish the raw malformed envelope from P after bypassing only P's local topic validator, then prove A emits `group:validation_rejected` reason `unbound_device` and no message/decrypt/payload side effects.

## Required Gates

| Gate | Command |
|---|---|
| Focused GA-011 regression | `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'TestGA011')` |
| Adjacent multi-device selector | `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'GA011|GA010|DeviceBound|MissingDevice|Unbound|SenderDevice')` |
| Broader validator selector | `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node ./internal ./crypto -run 'GroupTopicValidator|GroupEnvelope|GroupMessage|Unbound|DeviceBound|GA011')` |
| Race selector | `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test -race ./node -run 'TestGA011|Unbound|DeviceBound')` |
| Hygiene | `gofmt` on changed Go files and `git diff --check` |

## Closure Bar

- Source row GA-011 is updated to `Covered` with concrete file/test/gate evidence.
- Breakdown row 91, row disposition, session ledger, ordered row, session closure ledger, and closure progress are updated to `covered/accepted`.
- No `accepted_with_explicit_follow_up` is used for row-owned gaps.
- Residual work, if any, is outside GA-011 ownership and does not mask a repo-owned blocker.

## Execution Progress

| Time | Phase | Result |
|---|---|---|
| 2026-05-12 22:33:40 CEST | Implementation completed | Added `go-mknoon/node/pubsub_delivery_test.go::TestGA011MultiDeviceMissingSenderDeviceIDRejects`. The test deletes only `senderDeviceId` from an otherwise valid active-device envelope, proves pure validation from transport P rejects as `unbound_device`, raw-publishes from P after bypassing only P's local validator, and proves A rejects without payload side effects. |
| 2026-05-12 22:33:40 CEST | Closure completed | Source matrix GA-011, breakdown row 91, row disposition, session ledger, ordered row, session closure ledger, and closure progress were updated to `Covered` / `covered/accepted`. |

## Gate Evidence

| Gate | Result |
|---|---|
| `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'TestGA011')` | Passed: `ok github.com/mknoon/go-mknoon/node 3.684s`. |
| `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'GA011\|GA010\|DeviceBound\|MissingDevice\|Unbound\|SenderDevice')` | Passed: `ok github.com/mknoon/go-mknoon/node 11.147s`. |
| `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node ./internal ./crypto -run 'GroupTopicValidator\|GroupEnvelope\|GroupMessage\|Unbound\|DeviceBound\|GA011')` | Passed: `ok node 6.565s`, `ok internal 0.889s`, `ok crypto 1.179s`. |
| `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test -race ./node -run 'TestGA011\|Unbound\|DeviceBound')` | Passed: `ok github.com/mknoon/go-mknoon/node 4.728s`. |
| `gofmt -w go-mknoon/node/pubsub_delivery_test.go` and `git diff --check` | Passed. |

## Final Verdict

`accepted` / `closed`. GA-011 is covered by exact row-owned Go node proof. No production code changed because the existing active-device selector already rejects empty `SenderDeviceId` for members with a `Devices` list. Residual-only: none. GP-005 remains the next unresolved P0 row; no final program verdict is written.
