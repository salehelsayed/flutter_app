# GA-020 Session Plan: Duplicate Device ID Deterministic Binding

## Status

Status: accepted

## Source Row

Source matrix row: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` row `GA-020`

## Gap-Closure Reconciliation

| Time | Actor | Inputs Compared | Finding | Action |
|---|---|---|---|---|
| 2026-05-12 23:20:00 CEST | Controller | Source matrix GA-020 row; breakdown row 99; production `go-mknoon/node/pubsub.go::normalizeGroupMemberDevices` and `activeMemberDeviceForEnvelope`; adjacent GA-010 active-device proof, GA-015 key-package proof, and GA-019 duplicate-signing-key proof | Source row GA-020 was still `Open` and implementation-ready. Existing production already deduplicates devices by `DeviceId` when storing cloned group configs, but exact row-owned proof was missing for safe deterministic binding and shadow duplicate rejection. | Add exact Go node regression. No production code change is required because existing normalization already satisfies the deterministic-binding branch of the source row. |

## Scope

GA-020 owns only duplicate `DeviceId` entries within a single member. It must not change duplicate signing-key policy, duplicate transport-peer policy, key-package mismatch handling, revoked/inactive rejection, member-ID deduplication, Flutter group repository behavior, or UI behavior.

## Execution Contract

1. Add a row-owned test named `TestGA020DuplicateDeviceIDsWithinMemberUseDeterministicBinding` in `go-mknoon/node/pubsub_delivery_test.go`.
2. Build a private chat group where member B has two active devices with the same `DeviceId` but different transports/signing keys, and the selected device has the key-package-bearing binding.
3. Prove the stored cloned config contains exactly one selected device for that duplicate `DeviceId`.
4. Prove selected traffic accepts in pure validation and live delivery with expected device/transport/text attribution.
5. Prove the shadow duplicate rejects as pure/live `unbound_device` and emits no message/reaction/decrypt/payload side effects.

## Required Gates

| Gate | Command |
|---|---|
| Focused GA-020 regression | `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'TestGA020')` |
| Adjacent duplicate-device selector | `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'GA020|GA019|DuplicateDevice|DeviceBound|DeviceSigning|Unbound|KeyPackage')` |
| Broader validator selector | `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node ./internal ./crypto -run 'GroupTopicValidator|GroupEnvelope|GroupMessage|DuplicateDevice|DeviceBound|Unbound|GA020')` |
| Race selector | `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test -race ./node -run 'TestGA020|DuplicateDevice|DeviceBound|Unbound')` |
| Hygiene | `gofmt` on changed Go files and `git diff --check` |

## Closure Bar

- Source row GA-020 is updated to `Covered` with concrete file/test/gate evidence.
- Breakdown row 99, row disposition, session ledger, ordered row, session closure ledger, and closure progress are updated to `covered/accepted`.
- No `accepted_with_explicit_follow_up` is used for row-owned gaps.
- Residual work, if any, is outside GA-020 ownership and does not mask a repo-owned blocker.

## Execution Progress

| Time | Phase | Result |
|---|---|---|
| 2026-05-12 23:20:00 CEST | Implementation completed | Added `go-mknoon/node/pubsub_delivery_test.go::TestGA020DuplicateDeviceIDsWithinMemberUseDeterministicBinding`. The test proves stored configs collapse duplicate device IDs to one selected active/key-package-bearing binding, selected traffic accepts and delivers, and shadow duplicate traffic rejects without payload side effects. |
| 2026-05-12 23:20:00 CEST | Closure completed | Source matrix GA-020, breakdown row 99, row disposition, session ledger, ordered row, session closure ledger, and closure progress were updated to `Covered` / `covered/accepted`. |

## Gate Evidence

| Gate | Result |
|---|---|
| `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'TestGA020')` | Passed: `ok github.com/mknoon/go-mknoon/node 5.168s`. |
| `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'GA020\|GA019\|DuplicateDevice\|DeviceBound\|DeviceSigning\|Unbound\|KeyPackage')` | Passed: `ok github.com/mknoon/go-mknoon/node 11.983s`. |
| `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node ./internal ./crypto -run 'GroupTopicValidator\|GroupEnvelope\|GroupMessage\|DuplicateDevice\|DeviceBound\|Unbound\|GA020')` | Passed: `ok node 8.416s`, `ok internal 0.313s`, `ok crypto 0.606s`. |
| `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test -race ./node -run 'TestGA020\|DuplicateDevice\|DeviceBound\|Unbound')` | Passed: `ok github.com/mknoon/go-mknoon/node 6.241s`. |
| `gofmt -w go-mknoon/node/pubsub_delivery_test.go` and `git diff --check` | Passed. |

## Final Verdict

`accepted` / `closed`. GA-020 is covered by exact row-owned Go node proof for the source row's deterministic-binding branch. No production code changed because existing config normalization already stores a single selected duplicate `DeviceId`; selected traffic is accepted and shadow duplicate traffic is rejected before decrypt/render. Residual-only: none. GP-005 remains the next unresolved P0 row; no final program verdict is written.
