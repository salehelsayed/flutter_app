# GA-024 Session Plan: Known-Member Dial Uses Active Device Transports

## Status

Status: accepted/closed

## Source Row

Source matrix row: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` row `GA-024`

## Gap-Closure Reconciliation

| Time | Actor | Inputs Compared | Finding | Action |
|---|---|---|---|---|
| 2026-05-12 23:47:13 CEST | Controller | Source matrix GA-024 row; breakdown row 103; production `go-mknoon/node/pubsub.go::activeGroupMemberDialTargets`, `dialKnownGroupMembers`, `dialKnownGroupMembersDirectOnly`, `countRemoteGroupMembers`, and `expectedConnectedGroupMembers`; adjacent GA-023 revoked-device allowed-set proof | Planning-time gap: GA-024 lacked exact row-owned proof. Current production already derived known-member dial targets from active device `TransportPeerId` values when a member has devices, but the source row note still reflected older member-peer dialing behavior. | Add exact Go node regression evidence. No production code change is expected unless the row-owned test exposes a gap. |

## Scope

GA-024 owns known-member dialing target selection for members with active devices. It must not change revoked-device filtering, malformed-ID filtering, expected peer count semantics, duplicate transport-peer policy, or Flutter UI/repository behavior.

## Execution Contract

1. Add a row-owned test named `TestGA024KnownMemberDialingUsesActiveDeviceTransports` in `go-mknoon/node/pubsub_test.go`.
2. Build a config where a logical member has a valid member `PeerId` plus two active device transports.
3. Prove target/counter APIs include the two active device transports and not the logical member `PeerId`.
4. Run known-member direct dialing with peerstore addresses for the logical peer and both active devices.
5. Prove only the active device transports connect and emit known-member direct dial events; the logical member peer remains undialed.

## Required Gates

| Gate | Command |
|---|---|
| Focused GA-024 regression | `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'TestGA024')` |
| Adjacent active-device dialing selector | `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'GA024|GA023|ActiveDevice|KnownMemberDial|DeviceTransport')` |
| Broader discovery selector | `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node ./internal ./crypto -run 'GroupDiscovery|KnownMemberDial|Device|Transport|GA024')` |
| Race selector | `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test -race ./node -run 'TestGA024|KnownMemberDial|ActiveDevice|DeviceTransport')` |
| Hygiene | `gofmt` on changed Go files and `git diff --check` |

## Closure Bar

- Source row GA-024 is updated to `Covered` with concrete file/test/gate evidence.
- Breakdown row 103, row disposition, session ledger, ordered row, session closure ledger, and closure progress are updated to `covered/accepted`.
- No `accepted_with_explicit_follow_up` is used for row-owned gaps.
- Residual work, if any, is outside GA-024 ownership and does not mask a repo-owned blocker.

## Execution Progress

| Time | Phase | Result |
|---|---|---|
| 2026-05-12 23:55:32 CEST | Implementation completed | Added `go-mknoon/node/pubsub_test.go::TestGA024KnownMemberDialingUsesActiveDeviceTransports`. The test covers a logical member with two active device transports, verifies target/counter APIs use those transports and not the logical member peer, runs known-member direct dial with peerstore addresses for all peers, and proves only active devices connect. |
| 2026-05-12 23:55:32 CEST | Test repair | The first focused run exposed a test timing issue where the event collector was read before async discovery summary events settled. The test now polls for the summary and per-device success events before asserting, without changing production code. |
| 2026-05-12 23:55:32 CEST | Closure completed | Source matrix GA-024 and breakdown row 103 were updated to `Covered`/`covered/accepted` with exact row-owned evidence. |

## Gate Evidence

| Gate | Result |
|---|---|
| Focused GA-024 regression | `GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'TestGA024'` passed (`ok github.com/mknoon/go-mknoon/node 0.532s`). |
| Adjacent active-device dialing selector | `GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'GA024\|GA023\|ActiveDevice\|KnownMemberDial\|DeviceTransport'` passed (`ok github.com/mknoon/go-mknoon/node 3.163s`). |
| Broader discovery selector | `GOCACHE=/private/tmp/codex-go-build-cache go test ./node ./internal ./crypto -run 'GroupDiscovery\|KnownMemberDial\|Device\|Transport\|GA024'` passed (`ok node 51.544s`, `ok internal 0.276s`, `ok crypto 0.898s`). |
| Race selector | `GOCACHE=/private/tmp/codex-go-build-cache go test -race ./node -run 'TestGA024\|KnownMemberDial\|ActiveDevice\|DeviceTransport'` passed (`ok github.com/mknoon/go-mknoon/node 3.632s`). |
| Hygiene | `gofmt` on `go-mknoon/node/pubsub_test.go` and `git diff --check` passed. |

## Final Verdict

`accepted` / `closed`. GA-024 is covered by exact row-owned Go node proof. No production code changed because existing known-member dial target selection already uses active device transport peer IDs when a member has a `Devices` list. The proof verifies the logical member peer remains undialed even when it has peerstore addresses, while both active device transports connect and emit known-member direct dial evidence. Residual-only: none for GA-024. GP-005 remains the next unresolved P0 row; no final program verdict is written.
