# GA-022 Session Plan: Malformed Peer IDs In Config

## Status

Status: accepted

## Source Row

Source matrix row: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` row `GA-022`

## Gap-Closure Reconciliation

| Time | Actor | Inputs Compared | Finding | Action |
|---|---|---|---|---|
| 2026-05-12 23:30:14 CEST | Controller | Source matrix GA-022 row; breakdown row 101; production `go-mknoon/node/pubsub.go::activeGroupMemberDialTargets`, `discoverAndConnectGroupPeers`, `dialKnownGroupMembers`, `dialKnownGroupMembersDirectOnly`, `countRemoteGroupMembers`, and `expectedConnectedGroupMembers`; adjacent GM-027/GM-028 invalid/blank target-count proof and GA-021 transport identity proof | Source row GA-022 is still `Open` and implementation-ready. Existing code filters invalid dial targets, but GA-022 still lacks row-owned discovery/dial/counter proof and an explicit diagnostic count for invalid config peer IDs ignored during discovery/dial summaries. | Add a narrow diagnostic count for invalid active config peer IDs and exact Go node regression evidence proving malformed member/transport IDs do not crash discovery/dial/counters and valid members still connect. |

## Scope

GA-022 owns malformed peer IDs in group config discovery/dial target surfaces. It must not change envelope sender binding, signing-key uniqueness, duplicate transport-peer policy, active/revoked device semantics, Flutter role authorization, or UI behavior.

## Execution Contract

1. Extend Go node discovery/dial target scanning to count malformed active config peer IDs ignored by dial target construction.
2. Emit that count in discovery and known-member dial summary events without changing existing valid-target behavior.
3. Add a row-owned test named `TestGA022MalformedPeerIDsInConfigDoNotCrashDiscoveryDialAndCounters` in `go-mknoon/node/pubsub_test.go`.
4. Prove invalid legacy member peer IDs and invalid active device transport IDs are excluded from target/counter totals, diagnostic counts are emitted, known-member direct dial still connects a valid member, discovery still connects a valid member, and non-member discovery results remain ignored.

## Required Gates

| Gate | Command |
|---|---|
| Focused GA-022 regression | `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'TestGA022')` |
| Adjacent malformed discovery selector | `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'GA022|GA021|Malformed|Invalid|GroupDiscovery|KnownMemberDial|TransportPeer')` |
| Broader validator/discovery selector | `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node ./internal ./crypto -run 'GroupTopicValidator|GroupEnvelope|GroupMessage|GroupDiscovery|KnownMemberDial|Malformed|Invalid|GA022')` |
| Race selector | `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test -race ./node -run 'TestGA022|Malformed|Invalid|GroupDiscovery|KnownMemberDial')` |
| Hygiene | `gofmt` on changed Go files and `git diff --check` |

## Closure Bar

- Source row GA-022 is updated to `Covered` with concrete file/test/gate evidence.
- Breakdown row 101, row disposition, session ledger, ordered row, session closure ledger, and closure progress are updated to `covered/accepted`.
- No `accepted_with_explicit_follow_up` is used for row-owned gaps.
- Residual work, if any, is outside GA-022 ownership and does not mask a repo-owned blocker.

## Execution Progress

| Time | Phase | Result |
|---|---|---|
| 2026-05-12 23:39:07 CEST | Implementation completed | Added `go-mknoon/node/pubsub.go::activeGroupMemberDialTargetSummary`, preserving existing target filtering while counting malformed active config peer IDs skipped by discovery and known-member dial target construction. The diagnostic count is emitted as `ignoredInvalidConfigPeers` in `discover_result`, `direct_dial`, and `pre_relay_direct_dial` events. Added `go-mknoon/node/pubsub_test.go::TestGA022MalformedPeerIDsInConfigDoNotCrashDiscoveryDialAndCounters`. |
| 2026-05-12 23:39:07 CEST | Closure completed | Source matrix GA-022, breakdown row 101, row disposition, session ledger, ordered row, session closure ledger, and closure progress were updated to `Covered` / `covered/accepted`. |

## Gate Evidence

| Gate | Result |
|---|---|
| `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'TestGA022')` | Passed: `ok github.com/mknoon/go-mknoon/node 0.871s`. |
| `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'GA022\|GA021\|Malformed\|Invalid\|GroupDiscovery\|KnownMemberDial\|TransportPeer')` | Passed: `ok github.com/mknoon/go-mknoon/node 16.388s`. |
| `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node ./internal ./crypto -run 'GroupTopicValidator\|GroupEnvelope\|GroupMessage\|GroupDiscovery\|KnownMemberDial\|Malformed\|Invalid\|GA022')` | Passed: `ok node 9.021s`, `ok internal 0.437s`, `ok crypto 0.977s`. |
| `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test -race ./node -run 'TestGA022\|Malformed\|Invalid\|GroupDiscovery\|KnownMemberDial')` | Passed: `ok github.com/mknoon/go-mknoon/node 8.078s`. |
| `gofmt -w go-mknoon/node/pubsub.go go-mknoon/node/pubsub_test.go` and `git diff --check` | Passed. |

## Final Verdict

`accepted` / `closed`. GA-022 is covered by code-plus-tests Go node proof. Malformed legacy member peer IDs and active device transport peer IDs are ignored without panic, counters exclude invalid IDs, discovery/dial summaries expose `ignoredInvalidConfigPeers`, and valid members still connect through known-member direct dial and rendezvous discovery. Residual-only: none. GP-005 remains the next unresolved P0 row; no final program verdict is written.
