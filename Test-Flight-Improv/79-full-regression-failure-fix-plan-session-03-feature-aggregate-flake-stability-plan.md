# Session 03 Plan: Feature Aggregate Flake Stability

## Final verdict

`stale/already-covered`.

Session 03 did not reproduce the historical aggregate failures in the current tree. Isolated, plain-name, together, serial aggregate, and normal aggregate feature commands passed, so no code, test, gate-definition, or serial-bucket change was made.

Execution evidence captured on 2026-04-27:

- `flutter test test/features/groups/presentation/group_conversation_wired_test.dart --reporter expanded` -> exit 0, `+69`, all tests passed.
- `flutter test test/features/conversation/presentation/screens/conversation_wired_test.dart --reporter expanded` -> exit 0, `+62`, all tests passed.
- `flutter test test/features/groups/presentation/group_conversation_wired_test.dart --plain-name "voice send blocks text send while the voice pipeline is active and releases after failure" --reporter expanded` -> exit 0, `+1`, all tests passed.
- `flutter test test/features/groups/presentation/group_conversation_wired_test.dart --plain-name "voice stop cleanup still runs after unmount when group lookup resolves to not found" --reporter expanded` -> exit 0, `+1`, all tests passed.
- `flutter test test/features/conversation/presentation/screens/conversation_wired_test.dart --plain-name "durable media prep stores upload_pending rows in app-owned storage when MediaFileManager is available" --reporter expanded` -> exit 0, `+1`, all tests passed.
- `flutter test test/features/groups/presentation/group_conversation_wired_test.dart test/features/conversation/presentation/screens/conversation_wired_test.dart --reporter expanded` -> exit 0, `+131`, all tests passed.
- `flutter test test/features --reporter expanded --concurrency=1` -> exit 0, `+4147 ~5`, all tests passed.
- `flutter test test/features --reporter expanded` -> exit 0, `+4147 ~5`, all tests passed.

The historical failure is therefore classified as stale/already-covered for this session. The current evidence supersedes `.full_regression_logs/20260427_185248/010_all_feature_tests.log` for the Session 03 target failures.

## Closure audit result

- Closed for Session 03 only: the aggregate feature-test stability bullet from doc 79 is stale/already-covered in the current tree.
- Residual-only items: none for Session 03. No serial bucket, code fix, test helper change, or gate-definition change remains pending from this session.
- Accepted differences: the `groups` gate was not run because execution changed no group send, receive, retry, resume, invite, announcement, or listener behavior.
- Reopen only on a real regression: reopen this session only if one of the three named historical tests, either implicated file, both implicated files together, or the normal full `test/features` aggregate fails again in the current tree.
- Maintenance-time safety: use the three historical plain-name tests, the two direct file commands, the together-file command, `flutter test test/features --reporter expanded --concurrency=1`, and `flutter test test/features --reporter expanded`; run `./scripts/run_test_gates.sh groups` only after production group behavior changes.
- Overall doc 79 status: still open. Session 04 feed performance and Session 05 final full-regression acceptance remain unresolved.

## Final plan

### 1. real scope

Fix or classify only aggregate feature-test instability involving:

- `test/features/groups/presentation/group_conversation_wired_test.dart`
- `test/features/conversation/presentation/screens/conversation_wired_test.dart`
- the aggregate command `flutter test test/features --reporter expanded`

The session may adjust test cleanup, test synchronization, fake media/voice plumbing, or narrowly related production code only when current reproduction proves that the contract is wrong outside the test harness.

Do not work on relay/device startup, feed performance, message retry UX, full-regression scripts, or unrelated group listener behavior unless current evidence directly ties those files to the aggregate failures.

### 2. closure bar

The session is complete when one of these is true:

- isolated, together, serial, and full `test/features` commands pass after a narrow code/test fix
- the failures are proven to be aggregate-only parallel test isolation issues and the affected files are put behind an intentional documented serial/direct bucket with evidence
- the failures no longer reproduce in the current tree, and the source doc plus breakdown record the current pass evidence as stale/already-covered for this session

### 3. source of truth

- `Test-Flight-Improv/79-full-regression-failure-fix-plan.md`
- `Test-Flight-Improv/79-full-regression-failure-fix-plan-session-breakdown.md`
- `.full_regression_logs/20260427_185248/010_all_feature_tests.log`
- `test/features/groups/presentation/group_conversation_wired_test.dart`
- `test/features/conversation/presentation/screens/conversation_wired_test.dart`
- `Test-Flight-Improv/test-gate-definitions.md`
- `scripts/run_test_gates.sh`

Current code and current rerun evidence beat the historical log. If gate docs and `scripts/run_test_gates.sh` disagree, the script wins.

### 4. session classification

`evidence-gated`.

The historical failure appeared in the full feature-directory run and the source doc says isolated reruns passed, so reproduction order and concurrency must be established before changing behavior.

### 5. exact problem statement

The source full feature run failed with three concrete assertion/timeouts:

1. `GroupConversationWired voice send blocks text send while the voice pipeline is active and releases after failure`
   - `group_conversation_wired_test.dart:966`
   - timed out after 30 seconds waiting for `uploadStarted.future`

2. `GroupConversationWired voice stop cleanup still runs after unmount when group lookup resolves to not found`
   - `group_conversation_wired_test.dart:4623` timed out after 6 seconds waiting for `uploadStarted.future`
   - `group_conversation_wired_test.dart:4628` then found `msgRepo.getLatestMessage(group.id)` was `null`

3. `ConversationWired durable media prep stores upload_pending rows in app-owned storage when MediaFileManager is available`
   - `conversation_wired_test.dart:1597`
   - expected durable copied files to be non-empty, but `Directory(.../pending_uploads).listSync(recursive: true).whereType<File>()` returned `[]`

The user-visible risk is low if this is only test-isolation behavior, but the release risk is high because aggregate `test/features` is a broad confidence gate.

### 6. files and repos to inspect next

- `test/features/groups/presentation/group_conversation_wired_test.dart`
- `test/features/conversation/presentation/screens/conversation_wired_test.dart`
- `lib/features/groups/presentation/screens/group_conversation_wired.dart`
- `lib/features/conversation/presentation/screens/conversation_wired.dart`
- shared fake media picker/file-manager/audio-recorder helpers imported by the two tests
- `lib/features/groups/application/group_message_listener.dart` and `test/features/groups/application/group_message_listener_test.dart` only because they are already modified in the worktree and may influence aggregate group behavior; do not revert them
- `Test-Flight-Improv/test-gate-definitions.md` only if a direct/serial classification is needed

### 7. existing tests covering this area

- `group_conversation_wired_test.dart` already covers group voice send blocking, upload pending persistence, unmount cleanup, publish failure quote restoration, and media upload state.
- `conversation_wired_test.dart` already covers conversation durable media prep, upload pending rows, optimistic media send, relay/local media paths, voice send, retry/delete controls, and quote/edit state.
- `flutter test test/features/groups/presentation/group_conversation_wired_test.dart` and `flutter test test/features/conversation/presentation/screens/conversation_wired_test.dart` are direct suites for the failing files.
- `flutter test test/features --reporter expanded --concurrency=1` distinguishes serial order sensitivity from ordinary parallel shard interference.

Missing:

- current reruns after Sessions 01-02 and current unrelated group listener edits
- together-file reproduction for the two implicated files
- explicit classification of whether the aggregate failure is a stale historical failure, a test synchronization bug, or a real UI/media pipeline bug

### 8. regression/tests to add first

Do not add a brand-new test before reproduction. The failing tests already exist and are the regressions.

If reproduction proves a shared test helper is racing, add or tighten only the smallest existing-test assertion/cleanup needed to make the current regression deterministic, such as:

- waiting for durable copy completion rather than an unrelated call-order signal
- completing fake upload gates after the intended in-flight state is reached
- using unique temp roots and addTearDown cleanup for every media test path
- ensuring voice stop tests wait for recording/audio temp file readiness before invoking stop

### 9. step-by-step implementation plan

1. Record current dirty worktree for the relevant files and do not revert unrelated edits.
2. Run isolated target files:
   - `flutter test test/features/groups/presentation/group_conversation_wired_test.dart --reporter expanded`
   - `flutter test test/features/conversation/presentation/screens/conversation_wired_test.dart --reporter expanded`
3. Run the exact failing tests by plain name if isolated files fail:
   - `flutter test test/features/groups/presentation/group_conversation_wired_test.dart --plain-name "voice send blocks text send while the voice pipeline is active and releases after failure" --reporter expanded`
   - `flutter test test/features/groups/presentation/group_conversation_wired_test.dart --plain-name "voice stop cleanup still runs after unmount when group lookup resolves to not found" --reporter expanded`
   - `flutter test test/features/conversation/presentation/screens/conversation_wired_test.dart --plain-name "durable media prep stores upload_pending rows in app-owned storage when MediaFileManager is available" --reporter expanded`
4. Run both implicated files together:
   - `flutter test test/features/groups/presentation/group_conversation_wired_test.dart test/features/conversation/presentation/screens/conversation_wired_test.dart --reporter expanded`
5. Run serial aggregate:
   - `flutter test test/features --reporter expanded --concurrency=1`
6. If serial passes but normal full aggregate fails, inspect shared global state and classify/fix as parallel test isolation:
   - static fake singletons
   - global platform channels/clipboard/path-provider/test binding state
   - unclosed stream controllers or listeners
   - temp directory collisions
   - timers/futures left pending across tests
7. If isolated or together runs fail, fix the narrow failing test/product path:
   - for group voice timeouts, inspect whether `onRecordStop` reaches upload start and whether fake recorder/file/group lookup gates are ordered correctly
   - for unmount cleanup, inspect whether optimistic message creation happens before upload start or group not-found resolution
   - for conversation durable media, inspect `TrackingDurableConversationMediaFileManager.copyToDurableStorage` and the widget flow to ensure `copyCalls == 1` implies a file exists before the assertion
8. Run the exact failing plain-name tests after any fix.
9. Run both target files, then `flutter test test/features --reporter expanded --concurrency=1`, then full `flutter test test/features --reporter expanded`.
10. If production group send/receive/listener behavior changes, run `./scripts/run_test_gates.sh groups`; otherwise no frozen named gate is required.
11. Update source doc 79 and the breakdown with terminal evidence.

### 10. risks and edge cases

- Do not hide a product bug by only increasing timeouts.
- Do not mark tests serial unless serial-vs-parallel evidence proves isolation interference.
- Do not revert existing group listener changes; inspect and work with them if directly implicated.
- Widget tests that use `tester.runAsync` can race with fake gate completion; synchronization should target the intended state.
- Temp directories under `Directory.systemTemp` must be unique and cleaned.
- Background stream controllers/listeners must be closed to avoid cross-test pollution.

### 11. exact tests and gates to run

Direct reproduction:

```bash
flutter test test/features/groups/presentation/group_conversation_wired_test.dart --reporter expanded
flutter test test/features/conversation/presentation/screens/conversation_wired_test.dart --reporter expanded
flutter test test/features/groups/presentation/group_conversation_wired_test.dart test/features/conversation/presentation/screens/conversation_wired_test.dart --reporter expanded
flutter test test/features --reporter expanded --concurrency=1
flutter test test/features --reporter expanded
```

Plain-name checks when needed:

```bash
flutter test test/features/groups/presentation/group_conversation_wired_test.dart --plain-name "voice send blocks text send while the voice pipeline is active and releases after failure" --reporter expanded
flutter test test/features/groups/presentation/group_conversation_wired_test.dart --plain-name "voice stop cleanup still runs after unmount when group lookup resolves to not found" --reporter expanded
flutter test test/features/conversation/presentation/screens/conversation_wired_test.dart --plain-name "durable media prep stores upload_pending rows in app-owned storage when MediaFileManager is available" --reporter expanded
```

Conditional named gate:

```bash
./scripts/run_test_gates.sh groups
```

Run the groups gate only if execution changes group send, receive, retry, resume, invite, announcement, or listener behavior.

### 12. known-failure interpretation

- Session 02 emulator DNS/relay blocker is unrelated; do not run transport gates here.
- Feed P99 failures belong to Session 04.
- Readiness proof semantics are already closed by Session 01.
- A normal full `test/features` pass supersedes the historical aggregate feature failure.
- A serial-only pass is not full closure unless the repo explicitly documents a serial/direct classification.

### 13. done criteria

- The three historical failing test names are rerun and classified.
- Both implicated files pass together.
- `flutter test test/features --reporter expanded --concurrency=1` passes, or any remaining failure is proven unrelated and documented.
- Full `flutter test test/features --reporter expanded` passes, or the affected files have an intentional serial/direct classification with evidence.
- Source doc 79 and the breakdown record the Session 03 terminal status.

### 14. scope guard

Do not:

- edit relay/device startup code
- edit feed performance code or thresholds
- broaden group listener work unless the failing target tests directly prove it
- change production media send semantics from test evidence alone
- delete assertions or loosen tests without replacing them with equivalent deterministic checks
- add sleeps as the primary fix when a stream/state/fake gate can prove completion

### 15. accepted differences / intentionally out of scope

- Flutter test scheduler noise is acceptable only when captured as serial-vs-parallel evidence and documented.
- The current unrelated group listener worktree changes are accepted as present context, not automatically part of this session.
- Gate definition edits are out of scope unless execution proves an intentional serial/direct classification is required.

### 16. dependency impact

Session 05 can treat the Session 03 aggregate feature-test bullet as stale/already-covered because the current tree passed the normal full feature aggregate. Session 04 can proceed independently; overall doc 79 closure still depends on Sessions 04-05.

## Structural blockers remaining

None for execution planning. Current reproduction decides whether this is code/test work, stale historical evidence, or serial-bucket classification.

## Incremental details intentionally deferred

- New helper abstractions are deferred unless repeated synchronization fixes prove useful.
- Gate-definition edits are deferred unless serial classification is proven.

## Accepted differences intentionally left unchanged

- Sessions 01 and 02 terminal states are not reopened.
- Group listener edits already present in the worktree are not reverted by this plan.

## Exact docs/files used as evidence

- `/Users/I560101/.codex/skills/implementation-plan-orchestrator/SKILL.md`
- `Test-Flight-Improv/79-full-regression-failure-fix-plan.md`
- `Test-Flight-Improv/79-full-regression-failure-fix-plan-session-breakdown.md`
- `.full_regression_logs/20260427_185248/010_all_feature_tests.log`
- `test/features/groups/presentation/group_conversation_wired_test.dart`
- `test/features/conversation/presentation/screens/conversation_wired_test.dart`
- `Test-Flight-Improv/test-gate-definitions.md`
- `scripts/run_test_gates.sh`

## Why the plan is safe to execute now

The plan starts from existing failing tests, establishes isolated/together/serial/full behavior before code changes, and allows only narrow synchronization, cleanup, or directly proven product/test fixes.
