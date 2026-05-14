# GR-015 Session Plan: Relay Reconnect Keeps Private Group Receive Alive

## Status

Status: accepted/closed

## Source Row

Source matrix row: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` row `GR-015`

## Gap-Closure Reconciliation

| Time | Actor | Inputs Compared | Finding | Action |
|---|---|---|---|---|
| 2026-05-13 06:13:00 CEST | Controller | Source matrix GR-015 row; breakdown row 157; existing partition/replay tests; `go-mknoon/node/pubsub.go` group delivery/recovery behavior; `go-mknoon/node/node.go::RefreshRelaySession`; `lib/features/groups/application/send_group_message_use_case.dart`; `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`; fake group network harness | The source row was `Open` and the breakdown marked GR-015 `needs_repo_evidence` / `evidence-gated`. Existing production already preserves native group runtime state on in-place refresh, stages durable inbox fallback for recipients, drains cursor replay, and resumes live fake-network delivery after a healed subscription. Existing tests covered adjacent partition/rejoin and native refresh behavior, but no exact row-owned test proved a same-app relay disconnect/reconnect without user/app restart, with during-outage replay plus post-reconnect live delivery exactly once. | Add exact row-owned Flutter fake-network integration proof; run focused GR-015, adjacent partition/replay, native in-place relay recovery selector, format, and diff hygiene gates. |

## Scope

GR-015 owns user-visible private group receive behavior across a relay path outage that is recovered without app/user object restart. The closure bar is that messages sent during the outage are recovered from durable inbox after reconnect, and messages sent after reconnect arrive live exactly once.

Out of scope: watchdog/full restart rejoin, pending retry loss during recovery, and physical three-device relay-lab proof. Those are separate GR/GE rows.

## Execution Contract

1. Add a row-named fake-network Flutter integration test in `test/features/groups/integration/group_resume_recovery_test.dart`.
2. Start Alice/Bob/Carol in one private group and prove baseline live delivery.
3. Simulate Carol's relay path disconnect by unsubscribing her from the fake group network without disposing or recreating her app/user instance.
4. Send two messages during the outage; prove Bob receives them live, Carol does not, and Alice stages durable inbox custody for Carol.
5. Simulate in-place reconnect by resubscribing Carol and draining her relay inbox pages with the same app/user instance.
6. Prove Carol receives the two outage messages from cursor replay in order.
7. Send one post-reconnect message and prove Bob and Carol both receive the full ordered message set exactly once.
8. Run focused GR-015, adjacent partition/replay, native in-place relay recovery selector, formatter, and diff hygiene gates.

## Required Gates

| Gate | Command |
|---|---|
| Focused Flutter proof | `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'GR-015'` |
| Adjacent fake-network recovery proof | `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'temporary partition replays missed backlog in cursor order and resumes live delivery after heal'` |
| Native in-place recovery proof | `GOCACHE=/private/tmp/codex-go-build-cache GOTMPDIR=/private/tmp/codex-go-tmp go test ./node -run 'TestGR004|RefreshRelaySession|ReconnectRelays|GroupRecovery|RelaySession'` from `go-mknoon` |
| Formatting | `dart format --set-exit-if-changed test/features/groups/integration/group_resume_recovery_test.dart` |
| Hygiene | `git diff --check` |

## Dirty Worktree Snapshot

Captured before execution: worktree already contained prior rollout edits and accepted GR-004 through GR-014 changes. GR-015 scope is limited to `test/features/groups/integration/group_resume_recovery_test.dart`, this plan, the source matrix row GR-015, and breakdown closure documentation unless focused gates expose a production defect.

## Execution Evidence

- Added `test/features/groups/integration/group_resume_recovery_test.dart::GR-015 relay reconnect replays outage messages and resumes live delivery without restart`.
- No production code changed for GR-015. Existing app send/replay behavior and native in-place refresh behavior already satisfy the row once exact proof was added.
- The test creates Alice, Bob, and Carol in one private group, starts all three listeners, and proves baseline live delivery to Bob and Carol.
- It unsubscribes Carol from the fake group network without disposing or recreating Carol, sends `During relay drop 1` and `During relay drop 2`, proves Bob receives both live, proves Carol still has only the baseline message, and proves Alice staged durable inbox stores for Carol.
- It adds the two durable inbox payloads to Carol's cursor pages, resubscribes Carol, drains the inbox with the same Carol instance, and proves Carol receives the two outage messages in order.
- It then sends `After relay reconnect` and proves Bob and Carol both have exactly `Before relay drop`, both outage messages, and the post-reconnect message.
- It verifies exactly two cursor retrieve commands with cursors `''` and `cursor-gr015-reconnect-2`.

## Verification

- `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'GR-015'` passed (`+1`).
- `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'temporary partition replays missed backlog in cursor order and resumes live delivery after heal'` passed (`+1`).
- `GOCACHE=/private/tmp/codex-go-build-cache GOTMPDIR=/private/tmp/codex-go-tmp go test ./node -run 'TestGR004|RefreshRelaySession|ReconnectRelays|GroupRecovery|RelaySession'` passed (`ok github.com/mknoon/go-mknoon/node 22.023s`).
- `dart format --set-exit-if-changed test/features/groups/integration/group_resume_recovery_test.dart` passed.
- `git diff --check` passed.

## Final Verdict

Accepted/closed. GR-015 is `Covered` by row-owned Flutter fake-network evidence proving same-app relay reconnect recovers during-outage durable messages and resumes post-reconnect live delivery exactly once, backed by native in-place refresh evidence. Residual-only: no production code changed; physical relay-device E2E remains for later GE rows. GR-016 is the next unresolved P0 session in ledger order; no final program verdict was written.
