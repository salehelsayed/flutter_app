# GP-010 Session Plan: Discovery Unregisters On Leave

## Status

Status: accepted/closed

## Source Row

Source matrix row: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` row `GP-010`

## Gap-Closure Reconciliation

| Time | Actor | Inputs Compared | Finding | Action |
|---|---|---|---|---|
| 2026-05-13 01:04:09 CEST | Controller | Source matrix GP-010 row; breakdown row 111; production `go-mknoon/node/pubsub.go::groupPeerDiscoveryLoop`; existing `TestGL008LeaveGroupTopicStopsDiscoveryAndInboundAfterLeave`; existing rendezvous register/discover test seams | Pre-closure row state was unresolved because existing GL-008 proves no post-leave discovery/inbound work, but no exact GP-010 proof asserted that a registered group discovery loop calls `RendezvousUnregister` exactly once on leave. Production had the unregister path, but lacked an unregister test seam equivalent to existing register/discover seams. | Add a row-owned Go regression and a narrow `rendezvousUnregisterHook` test seam. No behavior change is intended beyond test observability unless the focused regression exposes a production gap. |
| 2026-05-13 01:05:23 CEST | Controller | New GP-010 regression; focused/adjacent Go gates; source matrix row GP-010; breakdown row 111 | Row-owned proof now exists. `RendezvousUnregister` has a test hook matching the existing register/discover hooks, and `TestGP010DiscoveryLoopUnregistersOnceAndStopsAfterLeave` proves registered group discovery unregisters exactly once on leave and emits no further discovery work. | Close GP-010 as `Covered`/accepted with concrete code-plus-test evidence and continue from GI-031, the next unresolved P0 row. |

## Scope

GP-010 owns the group discovery loop exit contract after `LeaveGroupTopic`: once the loop has registered its group rendezvous namespace, leaving the group must cancel the loop, call `RendezvousUnregister` once for that namespace, remove local group pubsub/discovery state, and emit no further discovery work.

Out of scope: live message authorization after leave beyond the existing GL/LP rows, relay server protocol conformance, personal rendezvous refresh loops, Flutter durable inbox behavior, and UI state.

## Execution Contract

1. Add row-owned Go node regression `TestGP010DiscoveryLoopUnregistersOnceAndStopsAfterLeave`.
2. Join a group with relay readiness and rendezvous register/discover hooks so the group discovery loop reaches the registered state.
3. Leave the group and prove the unregister hook receives exactly one call for `groupRendezvousNamespace(groupId)`.
4. Assert local group topic/subscription/config/key/discovery state is removed.
5. Assert no post-leave discovery work or rendezvous discover calls continue after unregister.

## Required Gates

| Gate | Command |
|---|---|
| Focused GP-010 Go regression | `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'TestGP010')` |
| Adjacent leave/discovery selector | `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'GP010|GL008|LeaveGroupTopic|GroupPeerDiscoveryLoop|RendezvousUnregister')` |
| Hygiene | `gofmt` on changed Go files and `git diff --check` |

## Dirty Worktree Snapshot

Captured before execution: worktree remains dirty with prior rollout changes and GP-008 closure artifacts. GP-010 scope is limited to the unregister test seam, row-owned Go test, this plan, and closure documentation updates.

## Execution Progress

| Time | Phase | Files touched | Evidence |
|---|---|---|---|
| 2026-05-13 01:05:23 CEST | Executor/QA completed | `go-mknoon/node/node.go`; `go-mknoon/node/rendezvous.go`; `go-mknoon/node/pubsub_unsubscribe_exit_paths_test.go` | Added `rendezvousUnregisterHook` as a test seam parallel to existing register/discover hooks. Added `TestGP010DiscoveryLoopUnregistersOnceAndStopsAfterLeave`, which waits for group rendezvous registration, leaves, verifies exactly one unregister for `groupRendezvousNamespace(groupId)`, checks local group state removal, and asserts discovery remains stopped after leave. |

## Gate Evidence

| Gate | Result |
|---|---|
| Focused GP-010 Go regression | `GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'TestGP010'` passed (`ok github.com/mknoon/go-mknoon/node 4.480s`). |
| Adjacent leave/discovery selector | `GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'GP010\|GL008\|LeaveGroupTopic\|GroupPeerDiscoveryLoop\|RendezvousUnregister'` passed (`ok github.com/mknoon/go-mknoon/node 26.448s`). |
| Hygiene | `gofmt` passed on `go-mknoon/node/node.go`, `go-mknoon/node/rendezvous.go`, and `go-mknoon/node/pubsub_unsubscribe_exit_paths_test.go`; `git diff --check` passed. |

## Final Verdict

Accepted/closed. GP-010 is `Covered` by code-plus-test evidence: the group discovery loop now has direct test observability for unregister, and the row-owned regression proves a registered group discovery loop calls `RendezvousUnregister` exactly once on `LeaveGroupTopic`, removes local group discovery/pubsub state, and performs no further discovery after leave. Residual-only none for GP-010; no `accepted_with_explicit_follow_up` is used.

## Closure Bar

- Source row GP-010 is updated to `Covered` with concrete file/test/gate evidence.
- Breakdown row 111, row disposition, session ledger, ordered row, session closure ledger, and closure progress are updated to `covered/accepted`.
- No `accepted_with_explicit_follow_up` is used for row-owned gaps.
- Residual work, if any, is outside GP-010 ownership and does not mask a repo-owned blocker.
