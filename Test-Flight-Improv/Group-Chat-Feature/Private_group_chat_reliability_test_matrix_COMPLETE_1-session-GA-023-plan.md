# GA-023 Session Plan: Revoked Device Removed From Discovery

## Status

Status: accepted

## Source Row

Source matrix row: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` row `GA-023`

## Gap-Closure Reconciliation

| Time | Actor | Inputs Compared | Finding | Action |
|---|---|---|---|---|
| 2026-05-12 23:39:07 CEST | Controller | Source matrix GA-023 row; breakdown row 102; production `go-mknoon/node/pubsub.go::UpdateGroupConfig`, `activeGroupMemberDialTargets`, `discoverAndConnectGroupPeers`, `dialKnownGroupMembersDirectOnly`, `countRemoteGroupMembers`, and `expectedConnectedGroupMembers`; adjacent GM-023 inactive-shadow proof and GA-022 malformed-ID diagnostics proof | Source row GA-023 was still `Open` and implementation-ready. Current code filters revoked devices from active dial targets after `UpdateGroupConfig`, but exact row-owned config-update/discovery/dial/counter proof was missing; regression-first execution also exposed that rendezvous filtering treated an empty non-nil allowed-member set as allow-all. | Add exact Go node regression evidence and fix the empty allowed-set filter so a config with zero active targets ignores all discovered peers instead of dialing revoked transports. |

## Scope

GA-023 owns revoked device transports in discovery allowed sets after config update. It must not change duplicate member normalization, malformed-ID handling, known-member active-device dialing for active devices, expected peer count for active devices, or Flutter UI/repository behavior.

## Execution Contract

1. Add a row-owned test named `TestGA023ConfigUpdateRemovesRevokedDeviceFromDiscoveryAllowedSet` in `go-mknoon/node/pubsub_test.go`.
2. Build an initial config where a member has active device S and verify S is an active remote target.
3. Apply `UpdateGroupConfig` with device S revoked.
4. Prove target/counter APIs no longer include S, known-member direct dial does not connect S even with peerstore addresses, rendezvous discovery returns S but it is reported as ignored/non-member and not connected.

## Required Gates

| Gate | Command |
|---|---|
| Focused GA-023 regression | `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'TestGA023')` |
| Adjacent revoked discovery selector | `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'GA023|GA022|Revoked|GroupDiscovery|KnownMemberDial|Device')` |
| Broader discovery selector | `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node ./internal ./crypto -run 'GroupTopicValidator|GroupEnvelope|GroupMessage|GroupDiscovery|KnownMemberDial|Revoked|GA023')` |
| Race selector | `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test -race ./node -run 'TestGA023|Revoked|GroupDiscovery|KnownMemberDial')` |
| Hygiene | `gofmt` on changed Go files and `git diff --check` |

## Closure Bar

- Source row GA-023 is updated to `Covered` with concrete file/test/gate evidence.
- Breakdown row 102, row disposition, session ledger, ordered row, session closure ledger, and closure progress are updated to `covered/accepted`.
- No `accepted_with_explicit_follow_up` is used for row-owned gaps.
- Residual work, if any, is outside GA-023 ownership and does not mask a repo-owned blocker.

## Execution Progress

| Time | Phase | Result |
|---|---|---|
| 2026-05-12 23:47:13 CEST | Implementation completed | Updated `go-mknoon/node/pubsub.go::filterDiscoveredGroupMembers` so only a nil allowed set means unfiltered discovery; an empty non-nil allowed set now means no discovered peer is allowed. Added `go-mknoon/node/pubsub_test.go::TestGA023ConfigUpdateRemovesRevokedDeviceFromDiscoveryAllowedSet`, proving revoked device S drops out of active targets, counters, known-member direct dial, and rendezvous discovery after `UpdateGroupConfig`. |
| 2026-05-12 23:47:13 CEST | Closure completed | Source matrix GA-023, breakdown row 102, row disposition, session ledger, ordered row, session closure ledger, and closure progress were updated to `Covered` / `covered/accepted`. |

## Gate Evidence

| Gate | Result |
|---|---|
| `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'TestGA023')` | Passed after the empty allowed-set fix: `ok github.com/mknoon/go-mknoon/node 0.786s`. Regression-first run failed because `filterDiscoveredGroupMembers` treated an empty non-nil allowed-member set as allow-all, causing revoked S to remain discoverable. |
| `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'GA023\|GA022\|Revoked\|GroupDiscovery\|KnownMemberDial\|Device')` | Passed: `ok github.com/mknoon/go-mknoon/node 45.145s`. |
| `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node ./internal ./crypto -run 'GroupTopicValidator\|GroupEnvelope\|GroupMessage\|GroupDiscovery\|KnownMemberDial\|Revoked\|GA023')` | Passed: `ok node 12.606s`, `ok internal 0.545s`, `ok crypto 0.830s`. |
| `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test -race ./node -run 'TestGA023\|Revoked\|GroupDiscovery\|KnownMemberDial')` | Passed: `ok github.com/mknoon/go-mknoon/node 10.444s`. |
| `gofmt -w go-mknoon/node/pubsub.go go-mknoon/node/pubsub_test.go` and `git diff --check` | Passed. |

## Final Verdict

`accepted` / `closed`. GA-023 is covered by code-plus-tests Go node proof. After config update revokes device S, S is removed from active discovery/dial targets and expected counters, known-member direct dial does not connect S, and rendezvous discovery reports S as ignored/non-member instead of dialing it. Residual-only: none. GP-005 remains the next unresolved P0 row; no final program verdict is written.
