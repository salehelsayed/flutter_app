Status: execution-ready

# INTEGRATE-BB-011 Standard Integration Plan

## Planning Progress

- 2026-05-17T05:27:00+02:00 - Spawned planner fallback invoked. Files inspected since last update: integration breakdown, source BB-011 matrix row, source BB-011 breakdown entry, source BB-011 plan, source commit `e3660ee5`, main COMPLETE_1 compatibility artifact, current main duplicate searches, and dirty status. Decision/blocker: spawned planner left only `planning-intake` after bounded waits; local plan fallback is artifact-only and current-session-only. Next action: write execution-safe integration contract.
- 2026-05-17T05:33:00+02:00 - Local planner completed. Files inspected since last update: source commit changed-file list/stat, source selector names, source plan final execution result, main exact-symbol searches, and source matrix closure evidence. Decision/blocker: BB-011 source delta is tests-only across three Flutter test files; production files stayed untouched in source. Next action: execute BB-011 only.

## Real Scope

This is a standard worktree-to-main integration contract for exactly `INTEGRATE-BB-011` / source row `BB-011`: start, stop, and restart rejoin every persisted private group before acknowledging recovery.

The executor must import, reconcile, or skip only the meaningful BB-011 delta already implemented in the source worktree. Do not recreate the source implementation plan, do not rerun the original rollout plan, and do not broaden into new gap closure.

In scope:

- Inspect the source BB-011 row, source BB-011 plan/evidence/closure, source commit, and main duplicate state before editing.
- Import only missing BB-011-owned test delta into main:
  - `test/features/groups/application/rejoin_group_topics_use_case_test.dart`
  - `test/core/lifecycle/handle_app_resumed_group_recovery_test.dart`
  - `test/features/groups/integration/group_startup_rejoin_smoke_test.dart`
- Preserve accepted main integration rows BB-001 through BB-010.
- Preserve overlapping COMPLETE_1 behavior for recovery/rejoin/leave rows that share these test surfaces, especially GL-018, GR-006, GR-016, GM-016, and BB-012-adjacent drain-before-ack behavior.
- Update only this integration plan and the integration breakdown ledger after execution.

Out of scope:

- Do not copy source matrix, source session breakdown, source test-inventory, or the historical source BB-011 plan into main.
- Do not edit main COMPLETE_1 docs for this row.
- Do not import BB-012 drain-before-ack semantics, RA-015 re-add convergence, real device/relay/3-party harness work, UI, notifications, media, observability, or broad security work.
- Do not change production files unless imported source tests expose a true current-main BB-011 product regression inside rejoin-before-ack ordering.

## Closure Bar

The row is good enough when main contains the BB-011 source proof or proves it was already present:

1. `rejoinGroupTopics` rejoins every persisted active private group with latest local config, members, state hash, key material, and newest key epoch.
2. `rejoinGroupTopics` itself does not directly acknowledge recovery.
3. Node-requested recovery sends `group:acknowledgeRecovery` only after every required `group:join` future completes.
4. If one required group rejoin fails, all eligible groups are still attempted and no recovery ack is sent.
5. A host fake-network startup/rejoin smoke proves restart recovery rejoins all persisted groups before ack and post-ack publish into every group remains live.
6. Focused BB-011 selectors, preservation selectors, host macOS `groups`, and `git diff --check` pass.
7. The integration ledger records one terminal status: `accepted`, `skipped_already_present`, `blocked_conflict`, or `blocked_external_fixture`.

## Source Of Truth

- Source row: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules.md` row `BB-011`.
- Source breakdown: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md` session `BB-011`.
- Historical worktree plan/evidence: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-BB-011-plan.md`.
- Source closure evidence: source `test-inventory.md` BB-011 row and source matrix BB-011 covered note.
- Source commit evidence: `e3660ee5` (`BB-011: prove recovery rejoin before ack`).
- Main integration controller: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-breakdown.md`.
- Main compatibility artifact: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md`.
- Current code and tests in main win over stale prose when they conflict.

## Session Classification

`implementation-ready`

Reason: source BB-011 has tests-only deltas, green host closure evidence, and no production file changes. Current main lacks exact BB-011 selectors, so execution should import row-owned tests unless duplicate evidence appears during execution.

## Source Commit And File Evidence

Source commit:

```text
e3660ee5 BB-011: prove recovery rejoin before ack
```

Changed files in that commit:

```text
A Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-BB-011-plan.md
M Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md
M Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules.md
M Test-Flight-Improv/Group-Chat-Feature/test-inventory.md
M test/core/lifecycle/handle_app_resumed_group_recovery_test.dart
M test/features/groups/application/rejoin_group_topics_use_case_test.dart
M test/features/groups/integration/group_startup_rejoin_smoke_test.dart
```

Meaningful integration files are the three Flutter test files. The four source docs are historical evidence only and must not be copied into main.

Source test evidence:

- `rejoin_group_topics_use_case_test.dart` adds `BB-011 rejoins every persisted active private group with latest config and key material`.
- `handle_app_resumed_group_recovery_test.dart` adds:
  - `BB-011 acknowledges recovery only after every persisted group rejoin succeeds`
  - `BB-011 does not acknowledge recovery when any persisted group rejoin fails`
- `group_startup_rejoin_smoke_test.dart` adds `BB-011 restart recovery rejoins all persisted groups before ack and remains live` using `FakeGroupPubSubNetwork`.
- Source closure reports production files stayed untouched.

## Duplicate Presence In Main

Observed main state during planning:

- Searches found no exact `BB-011` / `BB011` selectors in the three candidate files.
- Main already has BB-008/BB-010 and many COMPLETE_1 recovery/rejoin tests in the same areas; do not duplicate or rewrite them.
- Current diffs in `rejoin_group_topics_use_case_test.dart` include prior accepted BB-008 and BB-002 work. Preserve them while importing only BB-011 selectors.

If execution-time searches show BB-011 has landed since this plan was written, skip code/test edits and classify the row `skipped_already_present` with exact selector evidence.

## COMPLETE_1 Overlap Rows

Inspect these before resolving conflicts:

- `GL-018`: persisted app rejoin sends current config/key after restart.
- `GR-006`: recovery acknowledgement waits for app recovery work.
- `GR-016`: watchdog restart rejoins private groups and resumes delivery.
- `GM-016`: removed member unsubscribe/rejoin state must not be weakened by fake-network smoke.
- `BB-012` source row: drain-before-ack is adjacent but not part of BB-011.

These rows are compatibility constraints, not an invitation to import their broader work.

## Files To Inspect Or Update

Before editing, inspect:

```bash
git status --short
git diff -- test/features/groups/application/rejoin_group_topics_use_case_test.dart test/core/lifecycle/handle_app_resumed_group_recovery_test.dart test/features/groups/integration/group_startup_rejoin_smoke_test.dart
git -C /Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline show --name-status --no-renames e3660ee5
rg -n "BB-011|BB011|acknowledges recovery only after|does not acknowledge recovery|restart recovery rejoins all persisted|rejoins every persisted active private group" test/features/groups/application/rejoin_group_topics_use_case_test.dart test/core/lifecycle/handle_app_resumed_group_recovery_test.dart test/features/groups/integration/group_startup_rejoin_smoke_test.dart
```

Source files to compare:

```text
/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/test/features/groups/application/rejoin_group_topics_use_case_test.dart
/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/test/core/lifecycle/handle_app_resumed_group_recovery_test.dart
/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/test/features/groups/integration/group_startup_rejoin_smoke_test.dart
```

Main files to update only if missing the BB-011 delta:

```text
test/features/groups/application/rejoin_group_topics_use_case_test.dart
test/core/lifecycle/handle_app_resumed_group_recovery_test.dart
test/features/groups/integration/group_startup_rejoin_smoke_test.dart
```

Docs to update after execution:

```text
Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-INTEGRATE-BB-011-plan.md
Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-breakdown.md
```

## Device/Relay Proof Profile

Required closure profile: `host-only`.

BB-011 source closure claims host fake-network proof only because the `FakeGroupPubSubNetwork` startup rejoin selector was added and run. 3-Party E2E remains recommended and unclaimed. No paired device, external relay, or device-lab run is required for standard integration of this row.

Do not mark the row `blocked_external_fixture` unless execution unexpectedly discovers that required BB-011 acceptance now depends on unavailable external fixtures.

## Step-By-Step Integration Plan

1. Reconfirm `INTEGRATE-BB-010` is accepted in the integration breakdown and BB-011 is still `pending_integration`.
2. Re-run duplicate searches for exact BB-011 selectors.
3. Inspect uncommitted main diffs in the three candidate files. If an uncommitted change overlaps the exact source BB-011 hunks, stop and classify `blocked_conflict` unless the overlap is plainly the same BB-011 delta.
4. Compare source commit `e3660ee5` hunks against current main:
   - Bring over the `rejoinGroupTopics` latest-material selector only if absent.
   - Bring over the two `handleAppResumed` ack-order selectors only if absent.
   - Bring over the `group_startup_rejoin_smoke` fake-network liveness selector only if absent.
5. Preserve main-local line drift and existing accepted tests. Use source behavior as the semantic source, not as a blind patch.
6. Do not import source doc changes.
7. Run focused BB-011 tests and affected preservation tests below.
8. Assign one terminal status:
   - `accepted`: missing meaningful BB-011 delta imported and required tests/gates pass.
   - `skipped_already_present`: all meaningful BB-011 delta was already present in main with concrete selector evidence.
   - `blocked_conflict`: main has overlapping unmerged changes or COMPLETE_1 behavior that cannot be reconciled within row scope.
   - `blocked_external_fixture`: only if execution discovers a truly required external fixture is unavailable.

## Conflict Stop/Map Rule

Stop before editing and map conflicts if any of these are true:

- Current main already has differently named BB-011-equivalent tests with incompatible helper assumptions.
- Imported BB-011 tests fail because current main intentionally changed recovery acknowledgement policy outside the source row's contract.
- COMPLETE_1 GL-018, GR-006, GR-016, GM-016, or adjacent BB-012 behavior would be weakened by the import.
- Passing BB-011 would require BB-012 drain-before-ack semantics, RA-015 re-add convergence, or device/relay/3-party proof.

When stopped, record:

- exact conflicting files/hunks
- source rows implicated: `BB-011` and any adjacent source rows, especially `BB-012`
- main/COMPLETE_1 rows implicated: at minimum the overlap rows above if touched
- recommended next action

Do not resolve such conflicts inside this row without a new controller decision.

## Tests And Gates To Run

Focused BB-011 proof:

```bash
flutter test --no-pub test/features/groups/application/rejoin_group_topics_use_case_test.dart --plain-name 'BB-011'
flutter test --no-pub test/core/lifecycle/handle_app_resumed_group_recovery_test.dart --plain-name 'BB-011'
flutter test --no-pub test/features/groups/integration/group_startup_rejoin_smoke_test.dart --plain-name 'BB-011'
```

Affected COMPLETE_1/main preservation:

```bash
flutter test --no-pub test/features/groups/application/rejoin_group_topics_use_case_test.dart --plain-name 'BB-008'
flutter test --no-pub test/core/lifecycle/app_lifecycle_recovery_test.dart --plain-name 'GR-006'
flutter test --no-pub test/features/groups/integration/group_startup_rejoin_smoke_test.dart --plain-name 'GL-018'
flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'GR-016'
flutter test --no-pub test/core/services/pending_message_retrier_test.dart --plain-name 'ack'
flutter test --no-pub test/core/bridge/bridge_group_helpers_test.dart --plain-name 'callGroupAcknowledgeRecovery'
flutter test --no-pub test/core/bridge/go_bridge_client_test.dart --plain-name 'group:acknowledgeRecovery'
```

Smoke/backstop:

```bash
FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups
dart format --set-exit-if-changed test/features/groups/application/rejoin_group_topics_use_case_test.dart test/core/lifecycle/handle_app_resumed_group_recovery_test.dart test/features/groups/integration/group_startup_rejoin_smoke_test.dart
git diff --check
```

Run `baseline` only if execution unexpectedly touches production or broad non-row Flutter surfaces. Source BB-011 closure did not require baseline.

## Known-Failure Interpretation

- Failures in any `BB-011` focused selector are in scope.
- Failures in BB-008, GR-006, GL-018, GR-016, pending retrier ack, bridge acknowledge-recovery helper, or go-bridge-client acknowledge recovery are integration blockers unless proven pre-existing from unchanged main.
- A `groups` gate failure may be classified unrelated only with exact failing test names and a clear reason they do not touch startup/rejoin/recovery ack behavior.
- Missing device/relay fixtures should not block BB-011 unless execution unexpectedly makes them required.

## Done Criteria

- Source BB-011 row, source plan/closure, source commit, exact changed files, duplicate presence, and COMPLETE_1 overlaps were inspected.
- Main contains the row-owned BB-011 test selectors, or the row is explicitly `skipped_already_present`.
- No duplicate adjacent BB/GL/GR/GM work was imported.
- Required focused tests and affected preservation selectors pass.
- `git diff --check` passes.
- Integration breakdown ledger is updated with one terminal status and concrete evidence.
- This plan records execution outcome, changed files, tests run, skipped duplicate/unrelated work, conflicts, and next session.

## Scope Guard

Do not:

- Change recovery acknowledgement production code unless the source BB-011 tests expose a true current-main regression.
- Move ack behind inbox drain; that is BB-012.
- Implement RA-015, device/relay proof, or 3-party E2E.
- Rewrite rejoin orchestration, pending retrier, or fake-network harness beyond source BB-011 test needs.
- Touch COMPLETE_1 docs.
- Use this row to fix unrelated dirty worktree changes.

## Accepted Differences / Intentionally Out Of Scope

- Source BB-011 was tests-only; production files staying untouched is acceptable if imported tests pass.
- Host fake-network proof may be claimed only through the imported `FakeGroupPubSubNetwork` selector; 3-party E2E remains recommended and unclaimed.
- BB-012 drain-before-ack semantics remain separate.
- Source docs remain evidence only and are not copied.

## Execution Progress

- 2026-05-17T04:44:00+02:00 - Reconfirmed source commit `e3660ee5`, source BB-011 test-file scope, main duplicate state, and COMPLETE_1 overlap rows. Exact BB-011 selectors were missing in main, so this row required import rather than `skipped_already_present`.
- 2026-05-17T04:46:00+02:00 - Imported only BB-011-owned test deltas into the three owned Flutter test files. Source matrix/breakdown/test-inventory docs, BB-012 drain-before-ack behavior, RA-015, production code, and device/relay/3-party work were not imported.
- 2026-05-17T04:47:00+02:00 - Focused BB-011 selectors, affected preservation selectors, macOS `groups`, formatting, and diff hygiene passed. Classification: `accepted`.

## Final Execution Result

Status: `accepted`

Changed files:

- `test/features/groups/application/rejoin_group_topics_use_case_test.dart`
- `test/core/lifecycle/handle_app_resumed_group_recovery_test.dart`
- `test/features/groups/integration/group_startup_rejoin_smoke_test.dart`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-INTEGRATE-BB-011-plan.md`

Accepted evidence:

- Imported source selector `BB-011 rejoins every persisted active private group with latest config and key material`.
- Imported source selector `BB-011 acknowledges recovery only after every persisted group rejoin succeeds`.
- Imported source selector `BB-011 does not acknowledge recovery when any persisted group rejoin fails`.
- Imported source selector `BB-011 restart recovery rejoins all persisted groups before ack and remains live`.
- No production files were changed; this matches source closure evidence for BB-011.
- Source docs remained evidence only and were not copied into main.
- BB-012 drain-before-ack semantics and 3-party E2E proof remain out of scope and unclaimed.

Tests and checks run:

- `dart format --set-exit-if-changed test/features/groups/application/rejoin_group_topics_use_case_test.dart test/core/lifecycle/handle_app_resumed_group_recovery_test.dart test/features/groups/integration/group_startup_rejoin_smoke_test.dart` PASS (`0 changed`)
- `flutter test --no-pub test/features/groups/application/rejoin_group_topics_use_case_test.dart --plain-name 'BB-011'` PASS (`+1`)
- `flutter test --no-pub test/core/lifecycle/handle_app_resumed_group_recovery_test.dart --plain-name 'BB-011'` PASS (`+2`)
- `flutter test --no-pub test/features/groups/integration/group_startup_rejoin_smoke_test.dart --plain-name 'BB-011'` PASS (`+1`)
- `flutter test --no-pub test/features/groups/application/rejoin_group_topics_use_case_test.dart --plain-name 'BB-008'` PASS (`+1`)
- `flutter test --no-pub test/core/lifecycle/app_lifecycle_recovery_test.dart --plain-name 'GR-006'` PASS (`+1`)
- `flutter test --no-pub test/features/groups/integration/group_startup_rejoin_smoke_test.dart --plain-name 'GL-018'` PASS (`+1`)
- `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'GR-016'` PASS (`+1`)
- `flutter test --no-pub test/core/services/pending_message_retrier_test.dart --plain-name 'ack'` PASS (`+4`)
- `flutter test --no-pub test/core/bridge/bridge_group_helpers_test.dart --plain-name 'callGroupAcknowledgeRecovery'` PASS (`+3`)
- `flutter test --no-pub test/core/bridge/go_bridge_client_test.dart --plain-name 'group:acknowledgeRecovery'` PASS (`+1`)
- `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` PASS (`+166`)
- `git diff --check` PASS

Conflicts/blockers: none.

Next integration session: `INTEGRATE-BB-012`.

## Dependency Impact

BB-012 may rely on BB-011 only for rejoin-before-ack ordering across persisted groups. It must not assume inbox drain-before-ack was integrated here. BB-013+ and recovery rows may rely on ack not firing when rejoin fails, but not on device/relay proof.

If BB-011 blocks, keep `INTEGRATE-BB-012+` pending until the conflict is mapped and resolved or explicitly accepted by the integration controller.

## Reviewer Pass

Verdict: sufficient for a standard integration execution pass.

Findings:

- The plan names the source row, source closure, source commit, exact changed files, duplicate state in main, and relevant overlap rows.
- The plan prevents source doc copying and gap-closure expansion.
- The plan has an explicit conflict stop/map rule and terminal status contract.
- The plan requires focused BB-011 tests plus affected BB-008/GL-018/GR-006/GR-016/pending-retrier/ack-helper preservation and the `groups` gate.

## Arbiter Decision

Final verdict: `accepted`.

Structural blockers remaining: none.

Incremental details intentionally deferred:

- Exact helper placement in main test files because line numbers have drifted.
- Whether `baseline` is run; it is conditional and not part of source BB-011 required closure.

Accepted differences intentionally left unchanged:

- No 3-party E2E proof claim.
- No BB-012 drain-before-ack import.
- No COMPLETE_1 doc edits.
