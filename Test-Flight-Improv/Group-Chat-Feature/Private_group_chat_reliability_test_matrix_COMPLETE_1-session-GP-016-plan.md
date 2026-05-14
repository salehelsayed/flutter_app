# GP-016 Session Plan: Dial Cooldown Recovers

## Status

Status: accepted/closed

## Source Row

Source matrix row: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` row `GP-016`

## Gap-Closure Reconciliation

| Time | Actor | Inputs Compared | Finding | Action |
|---|---|---|---|---|
| 2026-05-13 01:30:00 CEST | Controller | Source matrix GP-016 row; breakdown row 115; existing state-only tests `TestGroupDiscoveryLoop_BacksOffRepeatedDialFailures`, `TestGroupDiscoveryLoop_DedupesConcurrentPeerDials`, and `TestGroupDiscoveryBackoff_CapsAtMaximum`; production `go-mknoon/node/pubsub.go::dialKnownGroupMembers`, `beginGroupPeerDialWithMode`, `finishGroupPeerDial`, `groupPeerDialBackoff`, `waitForLiveGroupTopicPeer`, and `PublishGroupMessage` | Existing coverage proves the backoff state machine, but the row remains open because no row-owned proof combines repeated failed known-member dials, cooldown skip evidence, fake-time advancement, success clearing the cooldown, live topic reconnection, and message receipt. | Add exact Go node regression `TestGP016DialCooldownBacksOffThenClearsOnRecoveredDelivery`. No production code change is expected unless the test exposes a recovery gap. |
| 2026-05-13 01:36:00 CEST | Controller | New GP-016 Go regression; focused and adjacent Go gates; source matrix row GP-016; breakdown row 115 | Row-owned proof now exists. The test forces repeated known-member failures, verifies cooldown skip/no-storm behavior, advances the test-owned cooldown state, proves backoff growth, proves direct recovery clears `groupDialBackoff`, and proves B receives the post-recovery message. | Close GP-016 as `Covered`/accepted with tests-only evidence and continue from GI-031, the next unresolved P0 row. |

## Scope

GP-016 owns the known-member dial cooldown behavior for private group chat delivery. Repeated failed dials must not storm, the cooldown must increase, and an available peer must not be starved once the cooldown window has passed.

Out of scope: relay lab fixtures, Flutter retry queue behavior, UI state, durable inbox fallback, and broader discovery-loop cadence already covered by adjacent GP rows.

## Execution Contract

1. Add row-owned Go regression `TestGP016DialCooldownBacksOffThenClearsOnRecoveredDelivery`.
2. Join A/B to the same private chat group while A lacks B direct addresses and relay fixtures.
3. Force repeated known-member dial failures from A, prove cooldown skip behavior, and advance the backoff state by setting `nextAllowed` to the past in test scope.
4. Prove backoff count increases and the computed cooldown grows after repeated failures.
5. Add B direct addresses, advance the cooldown again, run the recovery dial, and prove B becomes a live topic peer.
6. Prove the successful dial clears `groupDialBackoff`, then publish from A and prove B receives the row-owned message.

## Required Gates

| Gate | Command |
|---|---|
| Focused GP-016 Go regression | `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'TestGP016')` |
| Adjacent Go discovery selector | `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'GP016|GroupDiscoveryLoop_BacksOffRepeatedDialFailures|GroupDiscoveryLoop_DedupesConcurrentPeerDials|GroupDiscoveryBackoff|KnownMemberDial|PublishGroupMessage')` |
| Hygiene | `gofmt` on changed Go files and `git diff --check` |

## Dirty Worktree Snapshot

Captured before execution: worktree remains dirty with prior rollout changes and GP-015 closure artifacts. GP-016 scope is limited to row-owned Go tests, this plan, and closure documentation updates unless the focused regression exposes a production gap.

## Execution Progress

| Time | Phase | Files touched | Evidence |
|---|---|---|---|
| 2026-05-13 01:36:00 CEST | Executor/QA completed | `go-mknoon/node/pubsub_delivery_test.go` | Added `TestGP016DialCooldownBacksOffThenClearsOnRecoveredDelivery`. The test joins A/B to the same private chat group without A knowing B direct addresses, forces a known-member dial failure, proves the immediate retry is skipped by cooldown, advances `nextAllowed` in test scope, repeats failures until `groupPeerDialBackoff` grows, adds B direct addresses, proves direct recovery emits `known_member_dial_success`, verifies cooldown state clears, publishes, and proves B receives the row-owned message. |

## Gate Evidence

| Gate | Result |
|---|---|
| Focused GP-016 Go regression | `GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'TestGP016'` passed (`ok github.com/mknoon/go-mknoon/node 1.124s`). |
| Adjacent Go discovery selector | `GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'GP016\|GroupDiscoveryLoop_BacksOffRepeatedDialFailures\|GroupDiscoveryLoop_DedupesConcurrentPeerDials\|GroupDiscoveryBackoff\|KnownMemberDial\|PublishGroupMessage'` passed (`ok github.com/mknoon/go-mknoon/node 1.786s`). |
| Hygiene | `gofmt` passed on `go-mknoon/node/pubsub_delivery_test.go`; `git diff --check` passed. |

## Final Verdict

Accepted/closed. GP-016 is `Covered` by tests-only Go node evidence: known-member dial cooldown prevents immediate retry storms, repeated failures increase backoff, advancing the cooldown allows recovery, successful direct recovery clears cooldown state, and the recovered peer receives a live group message. Residual-only none for GP-016; no `accepted_with_explicit_follow_up` is used.

## Closure Bar

- Source row GP-016 is updated to `Covered` with concrete file/test/gate evidence.
- Breakdown row 115, row disposition, session ledger, ordered row, session closure ledger, and closure progress are updated to `covered/accepted`.
- No `accepted_with_explicit_follow_up` is used for row-owned gaps.
- Residual work, if any, is outside GP-016 ownership and does not mask a repo-owned blocker.
