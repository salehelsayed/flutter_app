# GA-012 Session Plan: Missing SenderTransportPeerId Rejection

## Status

Status: accepted

## Source Row

Source matrix row: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` row `GA-012`

## Gap-Closure Reconciliation

| Time | Actor | Inputs Compared | Finding | Action |
|---|---|---|---|---|
| 2026-05-12 22:33:40 CEST | Controller | Source matrix GA-012 row; breakdown row 92; production `go-mknoon/node/pubsub.go::groupEnvelopeMatchesTransportPeer` and `activeMemberDeviceForEnvelope`; adjacent GA-010 active-device acceptance proof; GA-011 missing-device rejection proof | Source row GA-012 is still `Open` and implementation-ready. Current production behavior rejects missing `SenderTransportPeerId` for logical multi-device members as `peer_mismatch` because transport binding falls back to account-level `SenderId`, which does not match the device transport peer. This satisfies the row's "otherwise rejected with diagnostics" branch, but exact row-owned proof is missing. | Add exact Go node regression. No production code change is expected unless the test exposes acceptance without deterministic binding or missing diagnostics. |

## Scope

GA-012 owns only the missing `SenderTransportPeerId` case for a member with a non-empty `Devices` list and a logical account `SenderId` distinct from the device transport peer. It must not change GA-010 active-device acceptance, GA-011 missing device-id rejection, revoked/inactive device rejection, key-package mismatch rejection, legacy single-device fallback, membership, discovery, key rotation, relay behavior, or Flutter UI.

## Execution Contract

1. Add a row-owned test named for GA-012 in `go-mknoon/node/pubsub_delivery_test.go`.
2. Build a private chat group where logical member B has active device S bound to transport peer P with a device signing key and key package K.
3. Build a valid device-bound envelope, then delete only top-level `senderTransportPeerId` without changing sender, device ID, device public key, key package, ciphertext, nonce, signature, group, type, or epoch.
4. Prove pure validation from transport P rejects as `reject:peer_mismatch`.
5. Publish the raw malformed envelope from P after bypassing only P's local topic validator, then prove A emits `group:validation_rejected` reason `peer_mismatch` and no message/decrypt/payload side effects.

## Required Gates

| Gate | Command |
|---|---|
| Focused GA-012 regression | `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'TestGA012')` |
| Adjacent multi-device selector | `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'GA012|GA011|GA010|DeviceBound|MissingTransport|PeerMismatch|TransportPeer')` |
| Broader validator selector | `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node ./internal ./crypto -run 'GroupTopicValidator|GroupEnvelope|GroupMessage|PeerMismatch|DeviceBound|GA012')` |
| Race selector | `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test -race ./node -run 'TestGA012|PeerMismatch|DeviceBound')` |
| Hygiene | `gofmt` on changed Go files and `git diff --check` |

## Closure Bar

- Source row GA-012 is updated to `Covered` with concrete file/test/gate evidence.
- Breakdown row 92, row disposition, session ledger, ordered row, session closure ledger, and closure progress are updated to `covered/accepted`.
- No `accepted_with_explicit_follow_up` is used for row-owned gaps.
- Residual work, if any, is outside GA-012 ownership and does not mask a repo-owned blocker.

## Execution Progress

| Time | Phase | Result |
|---|---|---|
| 2026-05-12 22:38:49 CEST | Implementation completed | Added `go-mknoon/node/pubsub_delivery_test.go::TestGA012MultiDeviceMissingSenderTransportPeerIDRejects`. The test deletes only `senderTransportPeerId` from an otherwise valid active-device envelope, proves pure validation from transport P rejects as `peer_mismatch`, raw-publishes from P after bypassing only P's local validator, and proves A rejects without payload side effects. |
| 2026-05-12 22:38:49 CEST | Closure completed | Source matrix GA-012, breakdown row 92, row disposition, session ledger, ordered row, session closure ledger, and closure progress were updated to `Covered` / `covered/accepted`. |

## Gate Evidence

| Gate | Result |
|---|---|
| `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'TestGA012')` | Passed: `ok github.com/mknoon/go-mknoon/node 3.570s`. |
| `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'GA012\|GA011\|GA010\|DeviceBound\|MissingTransport\|PeerMismatch\|TransportPeer')` | Passed: `ok github.com/mknoon/go-mknoon/node 11.430s`. |
| `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node ./internal ./crypto -run 'GroupTopicValidator\|GroupEnvelope\|GroupMessage\|PeerMismatch\|DeviceBound\|GA012')` | Passed: `ok node 9.366s`, `ok internal 0.854s`, `ok crypto 0.691s`. |
| `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test -race ./node -run 'TestGA012\|PeerMismatch\|DeviceBound')` | Passed: `ok github.com/mknoon/go-mknoon/node 7.822s`. |
| `gofmt -w go-mknoon/node/pubsub_delivery_test.go` and `git diff --check` | Passed. |

## Final Verdict

`accepted` / `closed`. GA-012 is covered by exact row-owned Go node proof for the source row's "otherwise rejected with diagnostics" branch. No production code changed because the existing transport-peer binding guard already rejects omitted `SenderTransportPeerId` for logical multi-device senders as `peer_mismatch`. Residual-only: none. GP-005 remains the next unresolved P0 row; no final program verdict is written.
