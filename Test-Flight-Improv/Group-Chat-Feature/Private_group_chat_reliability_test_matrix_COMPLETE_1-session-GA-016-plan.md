# GA-016 Session Plan: Device Public Key Mismatch Rejection

## Status

Status: accepted

## Source Row

Source matrix row: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` row `GA-016`

## Gap-Closure Reconciliation

| Time | Actor | Inputs Compared | Finding | Action |
|---|---|---|---|---|
| 2026-05-12 22:58:48 CEST | Controller | Source matrix GA-016 row; breakdown row 96; production `go-mknoon/node/pubsub.go::activeMemberDeviceForEnvelope`; adjacent GA-009 wrong public-key proof, GA-010 active-device proof, and GK-027 binding-tamper proof | Source row GA-016 was still `Open` and implementation-ready. Production already rejects a non-empty `SenderDevicePublicKey` that does not match the configured active device signing public key, but exact row-owned proof for matching device id plus wrong public key/signature was missing. | Add exact Go node regression. No production code change was required because the existing active-device selector already rejects wrong device public keys as unbound. |

## Scope

GA-016 owns only an active-device envelope whose device id, transport peer, and key package match the configured active device while its public key and signature come from another key. It must not change active-device acceptance, key-package mismatch rejection, revoked/inactive device rejection, membership, key rotation, relay behavior, or Flutter UI.

## Execution Contract

1. Add a row-owned test named for GA-016 in `go-mknoon/node/pubsub_delivery_test.go`.
2. Build a private chat group where logical member B has active device S bound to transport peer P with configured device signing public key PK1 and key package K.
3. Build a `group_message` envelope with matching sender/device/transport/key-package fields but `SenderDevicePublicKey == PK2`, signed by PK2.
4. Prove the signature verifies with PK2 and not PK1, then prove pure validation from P rejects as `reject:unbound_device`.
5. Publish the raw mismatched-public-key envelope from P after bypassing only P's local topic validator, then prove A emits `group:validation_rejected` reason `unbound_device` and no message/decrypt/payload side effects.

## Required Gates

| Gate | Command |
|---|---|
| Focused GA-016 regression | `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'TestGA016')` |
| Adjacent device selector | `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'GA016|GA015|SenderDevicePublicKey|DevicePublicKey|Unbound|BadSignature')` |
| Broader validator selector | `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node ./internal ./crypto -run 'GroupTopicValidator|GroupEnvelope|GroupMessage|SenderDevicePublicKey|DevicePublicKey|Unbound|BadSignature|GA016')` |
| Race selector | `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test -race ./node -run 'TestGA016|SenderDevicePublicKey|DevicePublicKey|Unbound|BadSignature')` |
| Hygiene | `gofmt` on changed Go files and `git diff --check` |

## Closure Bar

- Source row GA-016 is updated to `Covered` with concrete file/test/gate evidence.
- Breakdown row 96, row disposition, session ledger, ordered row, session closure ledger, and closure progress are updated to `covered/accepted`.
- No `accepted_with_explicit_follow_up` is used for row-owned gaps.
- Residual work, if any, is outside GA-016 ownership and does not mask a repo-owned blocker.

## Execution Progress

| Time | Phase | Result |
|---|---|---|
| 2026-05-12 22:58:48 CEST | Implementation completed | Added `go-mknoon/node/pubsub_delivery_test.go::TestGA016DevicePublicKeyMismatchRejects`. The test signs with an attacker device key while matching the configured device id, transport peer, and key package, proves the signature verifies with the claimed attacker key but not the configured active device key, proves pure validation from transport P rejects as `unbound_device`, raw-publishes from P after bypassing only P's local validator, and proves A rejects without payload side effects. |
| 2026-05-12 22:58:48 CEST | Closure completed | Source matrix GA-016, breakdown row 96, row disposition, session ledger, ordered row, session closure ledger, and closure progress were updated to `Covered` / `covered/accepted`. |

## Gate Evidence

| Gate | Result |
|---|---|
| Initial focused/adjacent compile pass | Failed as expected due to test setup issue: `node/pubsub_delivery_test.go:1578:2: declared and not used: activePriv`; fixed by removing the unused private key. |
| `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'TestGA016')` | Passed: `ok github.com/mknoon/go-mknoon/node 3.903s`. |
| `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'GA016\|GA015\|SenderDevicePublicKey\|DevicePublicKey\|Unbound\|BadSignature')` | Passed: `ok github.com/mknoon/go-mknoon/node 11.833s`. |
| `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node ./internal ./crypto -run 'GroupTopicValidator\|GroupEnvelope\|GroupMessage\|SenderDevicePublicKey\|DevicePublicKey\|Unbound\|BadSignature\|GA016')` | Passed: `ok node 9.376s`, `ok internal 0.691s`, `ok crypto 0.551s`. |
| `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test -race ./node -run 'TestGA016\|SenderDevicePublicKey\|DevicePublicKey\|Unbound\|BadSignature')` | Passed: `ok github.com/mknoon/go-mknoon/node 10.048s`. |
| `gofmt -w go-mknoon/node/pubsub_delivery_test.go` and `git diff --check` | Passed. |

## Final Verdict

`accepted` / `closed`. GA-016 is covered by exact row-owned Go node proof where an envelope matches the active device id/transport/key package but claims and signs with a different device public key and is rejected before decrypt/render. No production code changed because the existing active-device selector already rejects mismatched device public keys as unbound. Residual-only: none. GP-005 remains the next unresolved P0 row; no final program verdict is written.
