# GP-011 Session Plan: Rendezvous Filters Non-Members

## Status

Status: accepted/closed

## Source Row

Source matrix row: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` row `GP-011`

## Gap-Closure Reconciliation

| Time | Actor | Inputs Compared | Finding | Action |
|---|---|---|---|---|
| 2026-05-13 01:06:30 CEST | Controller | Source matrix GP-011 row; breakdown row 112; production `go-mknoon/node/pubsub.go::discoverAndConnectGroupPeers` and `filterDiscoveredGroupMembers`; existing `TestGM030MembershipMutationUpdatesDiscoveryAllowedMemberFilter`, `TestRP017RemovedPeerExcludedFromKnownAndDiscoveredDialsAfterConfigUpdate`, and `TestGL005PrivateGroupDiscoveryFiltersNonMembersBeforeDialUse` | Existing tests prove adjacent and broader filtering, but the source row remains unresolved because no exact GP-011 row-owned regression covers the B/current, C/removed, X/unknown discovery return shape and the required `ignoredNonMembers` count. Current production appears to satisfy the row. | Add exact GP-011 Go node regression. No production code change is expected unless the row-owned test exposes a gap. |
| 2026-05-13 01:11:21 CEST | Controller | New GP-011 regression; focused/adjacent Go gates; source matrix row GP-011; breakdown row 112 | Row-owned proof now exists. `TestGP011RendezvousDiscoveryFiltersNonMembers` proves only current member B is dialed from B/C/X rendezvous results, removed C and unknown X are not connected or imported into peerstore, and `ignoredNonMembers == 2`. | Close GP-011 as `Covered`/accepted with concrete tests-only evidence and continue from GI-031, the next unresolved P0 row in session-ledger order. |

## Scope

GP-011 owns rendezvous discovery filtering for private group discovery results: only current active member transport peers should be dialed, removed and unknown peers must remain unconnected, and the discovery diagnostic must report the ignored non-member count accurately.

Out of scope: config mutation freshness already covered by GM-030/GP-008, invalid peer IDs covered by GP-012/GA-022, leave/unregister behavior covered by GP-010, and Flutter durable fallback behavior.

## Execution Contract

1. Add row-owned Go node regression `TestGP011RendezvousDiscoveryFiltersNonMembers`.
2. Configure current group membership as admin plus active member B only.
3. Make `RendezvousDiscover` return B, removed C, and unknown X with usable direct addresses.
4. Run `discoverAndConnectGroupPeers`.
5. Prove B connects, C and X remain disconnected, and `discover_result` reports `totalFound == 3`, `newPeers == 1`, and `ignoredNonMembers == 2`.

## Required Gates

| Gate | Command |
|---|---|
| Focused GP-011 Go regression | `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'TestGP011')` |
| Adjacent discovery filter selector | `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'GP011|GM030|RP017|GL005|FilterDiscoveredGroupMembers|discoverAndConnectGroupPeers')` |
| Hygiene | `gofmt` on changed Go files and `git diff --check` |

## Dirty Worktree Snapshot

Captured before execution: worktree remains dirty with prior rollout changes and GP-010 closure artifacts. GP-011 scope is limited to row-owned Go test coverage, this plan, and closure documentation updates unless the regression exposes a production gap.

## Execution Progress

| Time | Phase | Files touched | Evidence |
|---|---|---|---|
| 2026-05-13 01:11:21 CEST | Executor/QA completed | `go-mknoon/node/pubsub_test.go` | Added `TestGP011RendezvousDiscoveryFiltersNonMembers`. The test makes rendezvous return current B, removed C, and unknown X, then proves only B connects, C/X remain disconnected and are not imported into peerstore, and discovery diagnostics report `totalFound == 3`, `newPeers == 1`, `ignoredNonMembers == 2`. |

## Gate Evidence

| Gate | Result |
|---|---|
| Focused GP-011 Go regression | `GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'TestGP011'` passed (`ok github.com/mknoon/go-mknoon/node 0.679s`). |
| Adjacent discovery filter selector | `GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'GP011\|GM030\|RP017\|GL005\|FilterDiscoveredGroupMembers\|discoverAndConnectGroupPeers'` passed (`ok github.com/mknoon/go-mknoon/node 3.835s`). |
| Hygiene | `gofmt` passed on `go-mknoon/node/pubsub_test.go`; `git diff --check` passed. |

## Final Verdict

Accepted/closed. GP-011 is `Covered` by tests-only Go node evidence: existing production filters rendezvous results through the current active member set before peerstore import or dial, and the row-owned regression proves accurate ignored-non-member diagnostics for current B, removed C, and unknown X. Residual-only none for GP-011; no `accepted_with_explicit_follow_up` is used.

## Closure Bar

- Source row GP-011 is updated to `Covered` with concrete file/test/gate evidence.
- Breakdown row 112, row disposition, session ledger, ordered row, session closure ledger, and closure progress are updated to `covered/accepted`.
- No `accepted_with_explicit_follow_up` is used for row-owned gaps.
- Residual work, if any, is outside GP-011 ownership and does not mask a repo-owned blocker.
