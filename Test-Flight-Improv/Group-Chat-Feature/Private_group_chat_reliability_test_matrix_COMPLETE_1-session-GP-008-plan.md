# GP-008 Session Plan: Publish Refresh Uses Latest Config

## Status

Status: accepted/closed

## Source Row

Source matrix row: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` row `GP-008`

## Gap-Closure Reconciliation

| Time | Actor | Inputs Compared | Finding | Action |
|---|---|---|---|---|
| 2026-05-13 00:47:17 CEST | Controller | Source matrix GP-008 row; breakdown row 110; production `go-mknoon/node/pubsub.go::UpdateGroupConfig`, `activeGroupMemberDialTargets`, and `ensureGroupTopicPeersBeforePublish`; production `lib/features/groups/application/send_group_message_use_case.dart`; existing GM-030/GM-031 config mutation discovery tests; existing Flutter recipient cutoff tests | Evidence-gated row remains Open because existing tests prove adjacent target selection/discovery behavior but not exact publish-refresh behavior after remove/add immediately before send. Current production appears to use the latest stored Go config and latest Flutter repository membership. | Add exact GP-008 Go and Flutter application regressions. No production code change is expected unless the row-owned tests expose a gap. |
| 2026-05-13 00:55:37 CEST | Controller | New GP-008 Go and Flutter regressions; focused/adjacent gates; source matrix row GP-008; breakdown row 110 | The exact Go regression exposed a repo-owned stale target gap: a background discovery pass could keep iterating a target list captured before `UpdateGroupConfig` and dial removed C after the remove/add update. Production now revalidates each discovered, known-member, and pre-relay direct dial target against the current active config immediately before attempting a dial. Exact Go and Flutter proofs now pass. | Close GP-008 as `Covered`/accepted with code-plus-tests evidence and continue from GI-031, the next unresolved P0 row. |

## Scope

GP-008 owns send-time membership freshness for publish peer refresh and durable recipient selection after a remove/add mutation. It must prove removed C is not dialed or included while newly added D is targeted for publish refresh and inbox fallback.

Out of scope: historical entitlement windows, re-add history visibility, device revocation policy, UI state, and rendezvous discovery filtering already covered by separate GM/GA/GP rows.

## Execution Contract

1. Add row-owned Go node regression `TestGP008PublishPeerRefreshUsesLatestConfigAfterAddRemove`.
2. Start with old config A/B/C, then update A to current config A/B/D immediately before publish.
3. Seed peerstore addresses for removed C and added D, publish while only B is initially live, and prove publish refresh uses expected peers B/D, dials D, does not emit known-member dial events for removed C, returns promoted peer count, and delivers to B/D without delivering to C.
4. Add row-owned Flutter application regression named with `GP-008` in `send_group_message_use_case_test.dart`.
5. Mutate repository membership from B/C to B/D immediately before send and assert `group:inboxStore` recipient ids include B/D and exclude C.

## Required Gates

| Gate | Command |
|---|---|
| Focused GP-008 Go regression | `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'TestGP008')` |
| Adjacent Go config-refresh selector | `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'GP008|GM030|GM031|UpdateGroupConfig|KnownMemberDial|PublishGroupMessage')` |
| Focused GP-008 Flutter regression | `flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --plain-name 'GP-008'` |
| Hygiene | `gofmt` on changed Go files, `dart format --set-exit-if-changed` on changed Dart tests, and `git diff --check` |

## Dirty Worktree Snapshot

Captured before execution: worktree remains dirty with prior rollout changes and GP-006 closure artifacts. GP-008 scope is limited to row-owned tests, this plan, and closure documentation updates unless a regression exposes a production gap.

## Execution Progress

| Time | Phase | Files touched | Evidence |
|---|---|---|---|
| 2026-05-13 00:55:37 CEST | Executor/QA completed | `go-mknoon/node/pubsub.go`; `go-mknoon/node/pubsub_delivery_test.go`; `test/features/groups/application/send_group_message_use_case_test.dart` | Added `TestGP008PublishPeerRefreshUsesLatestConfigAfterAddRemove` and Flutter test `GP-008 latest membership drives durable fallback after remove add`. Added `isCurrentActiveGroupDialTarget` guard and applied it before stale discovered, known-member, and pre-relay direct dial attempts. |

## Gate Evidence

| Gate | Result |
|---|---|
| Focused GP-008 Go regression | `GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'TestGP008'` passed (`ok github.com/mknoon/go-mknoon/node 2.643s`). |
| Adjacent Go config-refresh selector | `GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'GP008\|GM030\|GM031\|UpdateGroupConfig\|KnownMemberDial\|PublishGroupMessage'` passed (`ok github.com/mknoon/go-mknoon/node 6.902s`). |
| Focused GP-008 Flutter regression | `flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --plain-name 'GP-008'` passed (`+1`). |
| Hygiene | `gofmt` passed on `go-mknoon/node/pubsub.go` and `go-mknoon/node/pubsub_delivery_test.go`; `dart format --set-exit-if-changed test/features/groups/application/send_group_message_use_case_test.dart` passed (`0 changed`); `git diff --check` passed. |

## Final Verdict

Accepted/closed. GP-008 is `Covered` by code-plus-tests evidence: Go publish refresh now rejects stale removed-member dial targets from pre-update discovery snapshots, promotes newly added D from the current config, and delivers only to B/D; Flutter durable fallback recipient selection uses latest repository membership B/D and excludes removed C. Residual-only none for GP-008; no `accepted_with_explicit_follow_up` is used.

## Closure Bar

- Source row GP-008 is updated to `Covered` with concrete file/test/gate evidence.
- Breakdown row 110, row disposition, session ledger, ordered row, session closure ledger, and closure progress are updated to `covered/accepted`.
- No `accepted_with_explicit_follow_up` is used for row-owned gaps.
- Residual work, if any, is outside GP-008 ownership and does not mask a repo-owned blocker.
