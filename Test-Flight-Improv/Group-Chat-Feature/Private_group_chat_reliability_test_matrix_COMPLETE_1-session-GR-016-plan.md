# GR-016 Session Plan: Watchdog Restart Rejoins Every Private Group

## Status

Status: accepted/closed

## Source Row

Source matrix row: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` row `GR-016`

## Gap-Closure Reconciliation

| Time | Actor | Inputs Compared | Finding | Action |
|---|---|---|---|---|
| 2026-05-13 07:19:00 CEST | Controller | Source matrix GR-016 row; breakdown row 158; existing GR-005/GR-006/GR-015/GR-014 evidence; `lib/features/groups/application/rejoin_group_topics_use_case.dart`; `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`; `test/features/groups/integration/group_resume_recovery_test.dart`; native relay-session watchdog selectors | The source row was still `Open` and the breakdown marked GR-016 `needs_code_and_tests` / `implementation-ready`. Existing production already exposes the required app rejoin and inbox-drain behavior, and prior native tests prove watchdog/full restart clears group runtime state and signals recovery, but no exact row-owned proof covered multiple active private groups after runtime topic maps were lost. | Add exact row-owned multi-group fake-network integration proof; run focused GR-016, adjacent watchdog and recovery-ack selectors, native watchdog recovery selector, format, and diff hygiene gates. |

## Scope

GR-016 owns private group receive recovery after a watchdog/full restart clears native topic maps and the app must rejoin every stored private group. The closure bar is that no active group remains deaf: every group receives missed durable messages after retrieve and then receives subsequent live messages.

Out of scope: in-place relay reconnect without app topic rejoin, startup-only recovery, and physical multi-device relay-lab proof. Those are covered by GR-015, startup rows, and later GE rows.

## Execution Contract

1. Add a row-named Flutter fake-network integration test in `test/features/groups/integration/group_resume_recovery_test.dart`.
2. Start Alice, Bob, and Carol in two private groups, save group keys for every participant, and prove baseline live delivery in both groups.
3. Simulate watchdog restart topic loss by unsubscribing Bob from both fake group topics while keeping Alice and Carol online.
4. Send one message per group during the outage through the bridge-backed send path; prove Carol receives both live, Bob misses both, and Alice stages durable inbox custody for Bob in each group.
5. Call `rejoinGroupTopics(reason: RejoinReason.watchdogRestart)` for Bob and prove the result joins both groups with no skips/errors and is eligible to acknowledge group recovery.
6. Prove Bob's bridge receives exactly one `group:join` command for each active group with the expected key material and epoch.
7. Re-subscribe Bob in the fake network, drain Bob's group offline inbox, and prove both missed messages render in the correct groups.
8. Send one post-watchdog live message per group and prove Bob and Carol both receive the complete ordered message set for every group.

## Required Gates

| Gate | Command |
|---|---|
| Focused Flutter proof | `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'GR-016'` |
| Adjacent app watchdog live proof | `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'watchdog restart rejoins topics and receives subsequent live messages'` |
| Adjacent watchdog drain/live proof | `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'watchdog restart rejoins topics and resumes live delivery'` |
| Adjacent recovery acknowledgment proof | `flutter test --no-pub test/core/lifecycle/app_lifecycle_recovery_test.dart --plain-name 'GR-006 recovery ack waits until every active group topic rejoins'` |
| Native watchdog recovery proof | `GOCACHE=/private/tmp/codex-go-build-cache GOTMPDIR=/private/tmp/codex-go-tmp go test ./node -run 'TestGR005|RefreshRelaySession|ReconnectRelays|Watchdog|GroupRecovery|RelaySession'` from `go-mknoon` |
| Formatting | `dart format --set-exit-if-changed test/features/groups/integration/group_resume_recovery_test.dart` |
| Hygiene | `git diff --check` |

## Dirty Worktree Snapshot

Captured before execution: worktree already contained prior rollout edits and accepted GR-004 through GR-015 changes. GR-016 scope is limited to `test/features/groups/integration/group_resume_recovery_test.dart`, this plan, the source matrix row GR-016, and breakdown closure documentation unless focused gates expose a production defect.

## Execution Evidence

- Added `test/features/groups/integration/group_resume_recovery_test.dart::GR-016 watchdog restart rejoins every private group and resumes delivery`.
- No production code changed for GR-016. Existing `rejoinGroupTopics`, app recovery acknowledgment eligibility, durable inbox drain, and native watchdog recovery behavior satisfy the row once exact multi-group proof was added.
- The test creates Alice, Bob, and Carol in two private groups, saves keys for all participants, starts all listeners, and proves baseline live delivery to Bob and Carol in both groups.
- It drops Bob from both fake topics to model native runtime topic-map loss, sends one bridge-backed outage message per group, proves Carol receives both live while Bob remains at baseline, and proves Alice stages one durable inbox store for Bob per group.
- It calls `rejoinGroupTopics(reason: RejoinReason.watchdogRestart)`, proves `joinedGroupCount == 2`, `skippedNoKeyCount == 0`, `errorCount == 0`, and `canAcknowledgeGroupRecovery == true`.
- It verifies Bob's bridge emitted exactly two `group:join` commands, one for each group, with expected `groupKey` and `keyEpoch`.
- It re-subscribes Bob in the fake network, drains Bob's group inbox, proves the missed message renders in each group, sends one post-watchdog live message per group, and proves Bob and Carol both have exactly the baseline, outage, and post-watchdog messages for both groups.
- It verifies exactly two cursor retrieve commands, one per group, both starting at the empty cursor.

## Verification

- `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'GR-016'` passed (`+1`).
- `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'watchdog restart rejoins topics and receives subsequent live messages'` passed (`+1`) after a sequential rerun; the first parallel attempt collided with Flutter native-assets startup locking.
- `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'watchdog restart rejoins topics and resumes live delivery'` passed (`+1`).
- `flutter test --no-pub test/core/lifecycle/app_lifecycle_recovery_test.dart --plain-name 'GR-006 recovery ack waits until every active group topic rejoins'` passed (`+1`).
- `GOCACHE=/private/tmp/codex-go-build-cache GOTMPDIR=/private/tmp/codex-go-tmp go test ./node -run 'TestGR005|RefreshRelaySession|ReconnectRelays|Watchdog|GroupRecovery|RelaySession'` passed (`ok github.com/mknoon/go-mknoon/node 21.644s`).
- `dart format --set-exit-if-changed test/features/groups/integration/group_resume_recovery_test.dart` passed.
- `git diff --check` passed.

## Final Verdict

Accepted/closed. GR-016 is `Covered` by row-owned Flutter fake-network evidence proving watchdog restart app rejoin covers every active private group, recovers missed durable messages in both groups, and resumes live delivery in both groups, backed by native watchdog recovery and app recovery-ack evidence. Residual-only: no production code changed; physical multi-device relay E2E remains for later GE rows. GR-017 is the next unresolved P0 session in ledger order; no final program verdict was written.
