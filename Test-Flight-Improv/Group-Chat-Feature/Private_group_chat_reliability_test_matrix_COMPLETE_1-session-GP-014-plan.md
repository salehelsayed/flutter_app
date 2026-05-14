# GP-014 Session Plan: Relay Fallback After Topic Missing

## Status

Status: accepted/closed

## Source Row

Source matrix row: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` row `GP-014`

## Gap-Closure Reconciliation

| Time | Actor | Inputs Compared | Finding | Action |
|---|---|---|---|---|
| 2026-05-13 01:13:00 CEST | Controller | Source matrix GP-014 row; breakdown row 113; production `go-mknoon/node/pubsub.go::dialKnownGroupMembers`, `discoverAndConnectGroupPeers`, and `waitForLiveGroupTopicPeer`; existing discovery and publish-refresh tests | Row is repo-owned `needs_code_and_tests`: production intends to call `DialPeerViaRelay` when a direct host connection succeeds but the peer never becomes a live group topic peer, but no exact row-owned proof observes the relay fallback call or the resulting topic-missing diagnostic. | Add a narrow relay-dial test hook and exact GP-014 Go regression for the known-member path. Extend production only if the regression exposes missing behavior. |
| 2026-05-13 01:16:18 CEST | Controller | New GP-014 regression; focused/adjacent Go gates; source matrix row GP-014; breakdown row 113 | Row-owned proof now exists. `TestGP014RelayFallbackAfterDirectConnectTopicMissing` proves a direct-connected known member that does not become a live topic peer triggers `DialPeerViaRelay` exactly once and emits `known_member_topic_missing` with relay fallback diagnostics. | Close GP-014 as `Covered`/accepted with concrete code-plus-test evidence and continue from GI-031, the next unresolved P0 row. |

## Scope

GP-014 owns relay fallback after direct host connectivity is insufficient for PubSub delivery: when a known member can be direct-connected but does not appear as a live topic peer within `GroupPublishPartialPeerSettleWait`, the code must attempt `DialPeerViaRelay` and emit a topic-missing event that records relay fallback state.

Out of scope: full relay server connectivity, rendezvous non-member filtering, direct-address filtering, publish retry/durable inbox behavior, Flutter UI, and simulator E2E proof.

## Execution Contract

1. Add a test hook for `DialPeerViaRelay` so the row can prove the relay fallback call without requiring an external relay fixture.
2. Add row-owned Go regression `TestGP014RelayFallbackAfterDirectConnectTopicMissing`.
3. Configure a known group member with direct addresses but no live topic subscription.
4. Run `dialKnownGroupMembers`.
5. Prove direct host connection succeeds, relay fallback is attempted exactly once for that peer, and the emitted `known_member_topic_missing` diagnostic reports `path == relay_fallback`, `attemptedDirect == true`, `usedRelayFallback == true`, and positive direct address count.

## Required Gates

| Gate | Command |
|---|---|
| Focused GP-014 Go regression | `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'TestGP014')` |
| Adjacent relay/topic-missing selector | `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'GP014|topic_missing|relay_fallback|KnownMemberDial|DialPeerViaRelay|connectGroupPeerPreferDirect')` |
| Hygiene | `gofmt` on changed Go files and `git diff --check` |

## Dirty Worktree Snapshot

Captured before execution: worktree remains dirty with prior rollout changes and GP-011 closure artifacts. GP-014 scope is limited to the relay-dial test seam, row-owned Go test, this plan, and closure documentation updates unless the regression exposes a production gap.

## Execution Progress

| Time | Phase | Files touched | Evidence |
|---|---|---|---|
| 2026-05-13 01:16:18 CEST | Executor/QA completed | `go-mknoon/node/node.go`; `go-mknoon/node/pubsub_test.go` | Added `dialPeerViaRelayHook` as a narrow test seam and `TestGP014RelayFallbackAfterDirectConnectTopicMissing`. The test connects a known member directly without a live topic subscription, proves relay fallback is attempted exactly once, and verifies the topic-missing diagnostic carries `relay_fallback`, `attemptedDirect`, `usedRelayFallback`, and positive direct address count. |

## Gate Evidence

| Gate | Result |
|---|---|
| Focused GP-014 Go regression | `GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'TestGP014'` passed (`ok github.com/mknoon/go-mknoon/node 0.505s`). |
| Adjacent relay/topic-missing selector | `GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'GP014\|topic_missing\|relay_fallback\|KnownMemberDial\|DialPeerViaRelay\|connectGroupPeerPreferDirect'` passed (`ok github.com/mknoon/go-mknoon/node 5.567s`). |
| Hygiene | `gofmt` passed on `go-mknoon/node/node.go` and `go-mknoon/node/pubsub_test.go`; `git diff --check` passed. |

## Final Verdict

Accepted/closed. GP-014 is `Covered` by code-plus-test evidence: direct host connection alone is not treated as live PubSub delivery, the known-member path attempts relay fallback when the peer remains absent from the group topic, and the row-owned diagnostic records the fallback and topic-missing state. Residual-only none for GP-014; no `accepted_with_explicit_follow_up` is used.

## Closure Bar

- Source row GP-014 is updated to `Covered` with concrete file/test/gate evidence.
- Breakdown row 113, row disposition, session ledger, ordered row, session closure ledger, and closure progress are updated to `covered/accepted`.
- No `accepted_with_explicit_follow_up` is used for row-owned gaps.
- Residual work, if any, is outside GP-014 ownership and does not mask a repo-owned blocker.
