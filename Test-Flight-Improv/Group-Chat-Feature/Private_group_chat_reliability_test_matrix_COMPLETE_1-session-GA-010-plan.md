# GA-010 Session Plan: Multi-Device Active Device Publish Acceptance

## Status

Status: accepted

## Source Row

Source matrix row: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` row `GA-010`

## Gap-Closure Reconciliation

| Time | Actor | Inputs Compared | Finding | Action |
|---|---|---|---|---|
| 2026-05-12 22:18:00 CEST | Controller | Source matrix GA-010 row; breakdown row 90; pure device-bound acceptance tests in `go-mknoon/node/pubsub_test.go`; live device rejection tests in `go-mknoon/node/pubsub_decryption_failure_test.go`; production device selector in `go-mknoon/node/pubsub.go::activeMemberDeviceForEnvelope` | Source row GA-010 is still `Open` and evidence-gated. Existing pure tests prove an active registered device validates, and adjacent live tests prove invalid device states reject, but there is no exact `GA-010` row-owned live proof that an active device with matching `senderDeviceId`, `senderTransportPeerId`, `senderDevicePublicKey`, and `senderKeyPackageId` can publish and be received. | Add exact live Go node proof. No production code change is expected unless the exact test exposes a missing active-device acceptance path. |

## Scope

GA-010 owns only positive publication from an active registered device for a multi-device member. It must not change missing-device-field behavior, revoked/inactive device rejection, key-package mismatch rejection, legacy single-device fallback, membership, key rotation, relay behavior, or Flutter UI.

## Execution Contract

1. Add a row-owned test named for GA-010 in `go-mknoon/node/pubsub_delivery_test.go`.
2. Build a two-node private chat group where logical member B has an active device S with `TransportPeerId == nodeP.PeerId`, `DeviceSigningPublicKey == devicePub`, and key package K.
3. Build a valid `group_message` envelope with `SenderId == B`, `SenderDeviceId == S`, `SenderTransportPeerId == P`, `SenderDevicePublicKey == devicePub`, and `SenderKeyPackageId == K`, signed by the device signing key.
4. Prove pure validation from transport peer P accepts.
5. Publish from nodeP and prove A emits `group_message:received` with the expected member/device attribution and no validation/decrypt side effects.

## Required Gates

| Gate | Command |
|---|---|
| Focused GA-010 regression | `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'TestGA010')` |
| Adjacent multi-device selector | `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'GA010|DeviceBound|ActiveDevice|SenderDevice|KeyPackage|TransportPeer')` |
| Broader validator selector | `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node ./internal ./crypto -run 'GroupTopicValidator|GroupEnvelope|GroupMessage|ActiveDevice|DeviceBound|GA010')` |
| Race selector | `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test -race ./node -run 'TestGA010|DeviceBound|ActiveDevice')` |
| Hygiene | `gofmt` on changed Go files and `git diff --check` |

## Closure Bar

- Source row GA-010 is updated to `Covered` with concrete file/test/gate evidence.
- Breakdown row 90, row disposition, session ledger, ordered row, session closure ledger, and closure progress are updated to `covered/accepted`.
- No `accepted_with_explicit_follow_up` is used for row-owned gaps.
- Residual work, if any, is outside GA-010 ownership and does not mask a repo-owned blocker.

## Execution Progress

| Time | Phase | Result |
|---|---|---|
| 2026-05-12 22:27:36 CEST | Implementation completed | Added `go-mknoon/node/pubsub_delivery_test.go::TestGA010MultiDeviceActiveDeviceCanPublish`. The test builds logical member B with active device S bound to transport P, signs with S's device key, proves pure validation from P accepts, raw-publishes from P, and verifies A receives the message with expected group/member/device/transport attribution and no validation/decrypt side effects. |
| 2026-05-12 22:27:36 CEST | Closure completed | Source matrix GA-010, breakdown row 90, row disposition, session ledger, ordered row, session closure ledger, and closure progress were updated to `Covered` / `covered/accepted`. |

## Gate Evidence

| Gate | Result |
|---|---|
| `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'TestGA010')` | Passed: `ok github.com/mknoon/go-mknoon/node 2.145s`. |
| `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'GA010\|DeviceBound\|ActiveDevice\|SenderDevice\|KeyPackage\|TransportPeer')` | Passed: `ok github.com/mknoon/go-mknoon/node 12.081s`. |
| `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node ./internal ./crypto -run 'GroupTopicValidator\|GroupEnvelope\|GroupMessage\|ActiveDevice\|DeviceBound\|GA010')` | Passed: `ok node 4.836s`, `ok internal 0.854s`, `ok crypto 0.605s`. |
| `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test -race ./node -run 'TestGA010\|DeviceBound\|ActiveDevice')` | Passed: `ok github.com/mknoon/go-mknoon/node 3.410s`. |
| `gofmt -w go-mknoon/node/pubsub_delivery_test.go` and `git diff --check` | Passed. |

## Final Verdict

`accepted` / `closed`. GA-010 is covered by exact row-owned Go node proof. No production code changed because the existing active-device validator path already satisfies the row once a live acceptance regression exists. Residual-only: none. GP-005 remains the next unresolved P0 row; no final program verdict is written.
