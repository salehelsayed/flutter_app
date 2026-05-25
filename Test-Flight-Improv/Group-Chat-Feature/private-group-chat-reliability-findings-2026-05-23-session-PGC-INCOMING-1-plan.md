# PGC-INCOMING-1 Execution Plan

Status: execution-ready

## Planning Progress

- 2026-05-23T23:13:41+0200 - Planner completed. Files inspected since last update: none. Decision/blocker: draft plan narrows implementation to one incoming handler branch plus focused direct tests; no production/test code was edited during planning. Next action: Reviewer checks sufficiency, stale assumptions, gates, and scope drift.
- 2026-05-23T23:13:41+0200 - Reviewer started. Files inspected since last update: draft plan. Decision/blocker: no blocker yet. Next action: review the draft against PGC-007, source matrix, current handler/test evidence, and gate definitions.
- 2026-05-23T23:15:23+0200 - Reviewer completed. Files inspected since last update: draft plan. Decision/blocker: sufficient with adjustment; event-log path proof should be mandatory because `_FakeEventLog` already exists, and no structural blocker remains after tightening the closure/test wording. Next action: Arbiter classifies the reviewer adjustment and finalizes readiness.
- 2026-05-23T23:15:23+0200 - Arbiter started. Files inspected since last update: reviewer findings. Decision/blocker: no blocker yet. Next action: classify reviewer findings into structural blockers, incremental details, and accepted differences.
- 2026-05-23T23:15:54+0200 - Arbiter completed. Files inspected since last update: reviewer findings and final plan sections. Decision/blocker: no structural blockers; the reviewer adjustment was incremental and applied. Next action: plan is execution-ready for PGC-007 only.

## Execution Progress

- 2026-05-23T23:43:40+0200 - Final verdict written. Files inspected or touched: plan execution notes only. Command: none. Decision/blocker: blocked, blocker class `test_or_gate_failure`; exact blocker is the required `./scripts/run_test_gates.sh groups` gate remains without exact green evidence after the no-op fix-pass, and prior QA evidence recorded broad failures outside the PGC-007 row-owned handler/test scope. Next action: retry in a broader groups-gate triage/fix scope or after unrelated dirty group work is stabilized, then rerun the named groups gate.
- 2026-05-23T23:43:37+0200 - Final QA completed. Files inspected or touched: plan execution notes, scoped handler diff/read, focused handler test diff/read. Command: `git status --short -- ...`; `git diff -- lib/features/groups/application/handle_incoming_group_message_use_case.dart test/features/groups/application/handle_incoming_group_message_use_case_test.dart`; `nl -ba ... | sed -n '45,130p'`; `nl -ba ... | sed -n '392,535p'`; `nl -ba ... | sed -n '1240,1385p'`; `rg -n "PGC-007 selector passed|focused handler file passed|run_test_gates.sh groups|machine-reporter|smallest-selector|BB-007|GM-028|GM-029" ...`; `git diff --check -- ...`; `flutter test --no-pub test/features/groups/application/handle_incoming_group_message_use_case_test.dart --plain-name 'PGC-007'`. Decision/blocker: no concrete in-scope PGC-007 blocker remains; handler now uses a normalized non-empty stable ID for ID dedupe/source-event IDs/resolved IDs and runs `existsByContent` only when stable ID is absent, while both PGC-007 tests pass. The required named groups gate failure remains blocking because no exact green `./scripts/run_test_gates.sh groups` evidence exists. Next action: write final verdict.
- 2026-05-23T23:42:36+0200 - Final QA started. Files inspected or touched: plan execution notes only. Command: `date '+%Y-%m-%dT%H:%M:%S%z'`; `rg -n "^## Execution Progress|^## |Final verdict|QA|groups|PGC-007|existsByContent|messageId" ...`. Decision/blocker: final QA is reviewing the no-op fix-pass after the required `./scripts/run_test_gates.sh groups` failure; scope remains PGC-INCOMING-1 / PGC-007 only, with no production or test edits allowed. Next action: inspect the plan evidence, scoped diff, and handler/test snippets, then decide whether the named gate failure remains blocking.
- 2026-05-23T23:41:17+0200 - Executor fix-pass completed. Files inspected or touched: plan execution notes, scoped handler diff/read, focused handler test diff/read, scoped git status. Command: `sed -n '31,231p' ...`; `git diff -- lib/features/groups/application/handle_incoming_group_message_use_case.dart test/features/groups/application/handle_incoming_group_message_use_case_test.dart ...`; `git status --short -- ...`; `sed -n '40,135p' ...`; `sed -n '390,530p' ...`; `sed -n '1240,1375p' ...`. Decision/blocker: no concrete in-scope PGC-007 defect was found; current scoped code matches the plan by using a normalized non-empty stable message ID for ID dedupe/source-event IDs/resolved IDs and by calling `existsByContent` only when that stable ID is absent, while tests cover normal and event-log same-content/same-timestamp distinct-ID persistence. No code or test edits were made in this fix-pass. Remaining blocker is the required `./scripts/run_test_gates.sh groups` failure across non-PGC-007 rows/failures outside the allowed fix scope. Next action: retry in a broader groups-gate triage/fix scope or after unrelated dirty group work is stabilized; this PGC-007 fix-pass has no row-owned patch to apply.
- 2026-05-23T23:40:30+0200 - Executor fix-pass started. Files inspected or touched: plan execution notes only. Command: none. Decision/blocker: responding to QA's blocked verdict for required `./scripts/run_test_gates.sh groups`; direct PGC-007 evidence was reported sufficient, so this pass will inspect only the plan, QA entry, and scoped diff before deciding whether any in-scope handler/test fix exists. Next action: inspect the PGC-007 contract, scoped code/test diff, and current worktree state without broadening outside the allowed write scope.
- 2026-05-23T23:38:35+0200 - QA Reviewer completed. Files inspected or touched: plan execution notes, handler diff, focused handler test diff, gate script/definition reads. Command: PGC-007 selector passed; all six preservation selectors passed; focused handler file passed 60/60; `dart analyze ...` passed; `dart format --output=none --set-exit-if-changed ...` passed with 0 changed; `git diff --check` passed; `./scripts/run_test_gates.sh groups` failed; filtered rerun of the same named gate failed; machine-reporter equivalent listed failures in BB-007, IJ005, BB-012, NW-004, IR-018, PL-004, DE-004, IR-003, ST-004, GE-017, GE-019, GE-020, GM-029, and GM-028; smallest-selector reruns for GM-028 and BB-007 also failed. Decision/blocker: QA verdict is blocked with blocker class `test_or_gate_failure`; PGC-007 code/test behavior is sufficient, but the required Group Messaging Gate is not green and has not been fully closed by unrelated/pre-existing attribution inside this session. Next action: controller should run a fix/triage pass for the broader groups-gate failures or rerun after unrelated dirty group work is stabilized; no PGC-007 handler/test fix is indicated by the direct evidence.
- 2026-05-23T23:30:58+0200 - QA Reviewer started. Files inspected or touched: plan, scoped handler diff, focused handler test diff, git status. Command: `sed -n '1,260p' ...`; `git diff -- lib/features/groups/application/handle_incoming_group_message_use_case.dart test/features/groups/application/handle_incoming_group_message_use_case_test.dart ...`; `git status --short`. Decision/blocker: QA inspection is beginning; required after-test/gate evidence is still missing from the plan until verified directly. Next action: inspect implementation/test sufficiency and run missing required checks as needed.
- 2026-05-23T23:29:18+0200 - Executor child completed; QA handoff started. Files inspected or touched: handler owner file, focused handler test file, plan execution notes. Command: `git diff -- lib/features/groups/application/handle_incoming_group_message_use_case.dart test/features/groups/application/handle_incoming_group_message_use_case_test.dart Test-Flight-Improv/Group-Chat-Feature/private-group-chat-reliability-findings-2026-05-23-session-PGC-INCOMING-1-plan.md`; `git status --short -- ...`; `rg -n "stableMessageId|existsByContent|PGC-007" ...`. Decision/blocker: Executor landed the scoped PGC-007 code/test delta, but its captured final summary was obscured by large diff output and the plan is missing after-test/gate result entries after the groups gate started. Next action: spawn QA Reviewer to classify whether the landed work and evidence are sufficient or require a fix-pass.
- 2026-05-23T23:25:13+0200 - Before required green selectors and gates. Files inspected or touched: handler owner file, focused handler test file, plan execution notes. Command: none. Decision/blocker: production change is limited to normalizing a non-empty `stableMessageId`, using it on existing ID-dedupe paths, and running content fallback only when it is null. Next action: run the exact required selector list, focused file, static checks, diff check, and groups gate.
- 2026-05-23T23:24:28+0200 - RED PGC-007 selector completed. Files inspected or touched: focused handler test file, plan execution notes. Command: `flutter test --no-pub test/features/groups/application/handle_incoming_group_message_use_case_test.dart --plain-name 'PGC-007'`. Decision/blocker: failed as expected before production edits; both PGC-007 tests returned null for the second distinct stable-ID message after `GROUP_HANDLE_INCOMING_MSG_DUPLICATE` with `dedupeBy: content`. Next action: guard the content fallback so it only runs for null/empty message IDs.
- 2026-05-23T23:23:54+0200 - Before RED PGC-007 selector. Files inspected or touched: focused handler test file, plan execution notes. Command: none. Decision/blocker: added the two required PGC-007 tests only; production handler remains unchanged. Next action: run `flutter test --no-pub test/features/groups/application/handle_incoming_group_message_use_case_test.dart --plain-name 'PGC-007'` and stop as stale/already-covered if it unexpectedly passes.
- 2026-05-23T23:23:07+0200 - Owner-file inspection completed. Files inspected or touched: handler owner file, focused handler test file, plan execution notes. Command: `sed -n ...` owner file reads; `rg -n "deduplicates|duplicate replay|SV-010|messageId|event-log|event log|getMessagesPage|count" test/features/groups/application/handle_incoming_group_message_use_case_test.dart`; `wc -l lib/features/groups/application/handle_incoming_group_message_use_case.dart test/features/groups/application/handle_incoming_group_message_use_case_test.dart`. Decision/blocker: current handler still runs `existsByContent` unconditionally after stable-ID checks; existing tests cover no-ID content dedupe and same-ID replay but not distinct stable IDs with identical content/timestamp. Next action: add the two PGC-007 tests before production edits.
- 2026-05-23T23:22:31+0200 - Executor started. Files inspected or touched: plan, handler owner file, focused handler test file, git status. Command: `git status --short`. Decision/blocker: dirty worktree confirmed with many unrelated edits; allowed write scope remains the handler, focused test file, and this plan's execution notes only. Next action: finish owner-file inspection and add the PGC-007 tests before any production edit.
- 2026-05-23T23:20:33+0200 - Contract extraction started. Files inspected or touched: plan only. Command: none. Decision/blocker: execution controller is reading the PGC-INCOMING-1 / PGC-007 contract before coding; no production/test files touched. Next action: extract exact scope, tests, gates, done criteria, and scope guard.
- 2026-05-23T23:20:33+0200 - Contract extraction completed. Files inspected or touched: plan, skill instructions, git status, Codex CLI help. Command: `git status --short`; `codex --help`; `codex exec --help`. Decision/blocker: contract is execution-ready for PGC-007 only; spawned-agent path is available through `codex exec -m gpt-5.5 -c model_reasoning_effort=\"xhigh\"`; latest user scope limits writes to the handler, focused test file, and this plan's execution notes. Next action: spawn Executor for red-first tests, focused implementation, required tests/gates, and progress updates.
- 2026-05-23T23:21:34+0200 - Executor spawn attempted. Files inspected or touched: plan execution notes only. Command: `codex exec -m gpt-5.5 -c model_reasoning_effort=\"xhigh\" ... -a never`. Decision/blocker: spawn did not start because `codex exec` does not accept the root-level `-a` flag; no code/test files touched. Next action: retry Executor spawn with supported `codex exec` options.

## final verdict

`PGC-INCOMING-1` is execution-ready for row `PGC-007` only.

## real scope

This session owns only row `PGC-007`: content-based duplicate detection in `handleIncomingGroupMessage` must run only for legacy incoming messages that do not carry a stable non-empty wire `messageId`.

Allowed changes:

- Add focused PGC-007 tests in `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`.
- Change `lib/features/groups/application/handle_incoming_group_message_use_case.dart` so `msgRepo.existsByContent(...)` is skipped whenever `messageId` is non-null and non-empty.
- Keep the existing message-id duplicate path, duplicate conflict rejection, self-echo reconciliation, repair-placeholder enrichment, media enrichment, event-log append ordering, username refresh, membership checks, and legacy no-ID content dedupe behavior unchanged.

Out of scope: database save semantics, repository API changes, listener buffering, offline inbox drain, send status, Go node validation, relay ACLs, key retention, UI, notification behavior, and any adjacent PGC row.

## closure bar

Good enough for this session means:

- Two distinct incoming messages from the same sender with identical sanitized text and identical timestamp are both persisted when each has a different stable `messageId`.
- The same behavior is pinned for the normal handler path and the event-log append path.
- Legacy no-ID duplicate deliveries with identical sanitized content/timestamp still dedupe to one row.
- Same-`messageId` replay still dedupes before creating another visible row and still preserves existing conflict/self-echo/repair behavior.
- Focused direct tests, analyzer/format checks, `git diff --check`, and the Group Messaging Gate are either green or have exact unrelated-failure attribution.

## source of truth

- Primary row contract: `Test-Flight-Improv/Group-Chat-Feature/private-group-chat-reliability-findings-2026-05-23-matrix.md`, row `PGC-007`.
- Session decomposition: `Test-Flight-Improv/Group-Chat-Feature/private-group-chat-reliability-findings-2026-05-23-session-breakdown.md`, session `PGC-INCOMING-1`.
- Current behavior source: `lib/features/groups/application/handle_incoming_group_message_use_case.dart`.
- Focused test source: `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`.
- Gate source of truth: `Test-Flight-Improv/test-gate-definitions.md`; if it disagrees with `scripts/run_test_gates.sh`, the script wins.
- On disagreement, current code and focused tests beat stale prose. This plan beats broader rollout notes only for `PGC-INCOMING-1`/`PGC-007`.

## session classification

`implementation-ready`

## exact problem statement

The handler already prefers message-id dedupe: it checks `msgRepo.getMessage(messageId)` before group/member lookup when event-log logging is absent, and again after event-log append. However, after those message-id checks it always runs the content fallback:

- `lib/features/groups/application/handle_incoming_group_message_use_case.dart:490` says the fallback is for messages without a `messageId`.
- `lib/features/groups/application/handle_incoming_group_message_use_case.dart:491` still calls `existsByContent(...)` unconditionally.

User-visible risk: two legitimate private-group messages sent by the same member with the same text and timestamp but different stable wire IDs can collapse into one visible message. Fixing this must not weaken duplicate suppression for true same-ID replay or legacy no-ID replay.

## files and repos to inspect next

Production:

- `lib/features/groups/application/handle_incoming_group_message_use_case.dart`
- `lib/features/groups/domain/repositories/group_message_repository.dart`
- `lib/features/groups/domain/repositories/group_message_repository_impl.dart`
- `test/shared/fakes/in_memory_group_message_repository.dart`

Tests:

- `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`
- `test/features/groups/application/group_message_listener_test.dart` only if focused handler tests show listener-visible behavior is not covered.
- `test/features/groups/integration/group_resume_recovery_test.dart` only for follow-up triage if the Group Messaging Gate fails in a duplicate-delivery selector.

Gate/config:

- `Test-Flight-Improv/test-gate-definitions.md`
- `scripts/run_test_gates.sh`

Docs to update after implementation evidence:

- `Test-Flight-Improv/Group-Chat-Feature/private-group-chat-reliability-findings-2026-05-23-matrix.md`, row `PGC-007`
- `Test-Flight-Improv/Group-Chat-Feature/private-group-chat-reliability-findings-2026-05-23-session-breakdown.md`, `PGC-INCOMING-1` ledger

## existing tests covering this area

- `duplicate by messageId skips repeated group and member lookups` proves same-ID duplicate fast path avoids group/member reads when event-log logging is absent.
- `deduplicates identical incoming messages` proves legacy no-ID content/timestamp duplicate suppression.
- `deduplicates messages after sanitizing invisible bidi controls` proves sanitized no-ID content dedupe.
- `deduplicates by messageId when pubsub and group inbox deliver same message` proves same-ID pubsub/inbox replay creates one row.
- `duplicate replay with the same messageId ignores a tampered timestamp` and `duplicate replay with the same messageId ignores conflicting content` prove same-ID replay preserves the first trusted row.
- `SV-010 duplicate message id from different sender cannot overwrite valid row` proves same-ID conflict rejection remains guarded.

Missing coverage: no focused selector proves that different non-empty `messageId` values bypass content-based dedupe when sanitized text and timestamp match.

## regression/tests to add first

Add PGC-007 tests before production edits:

1. `PGC-007 distinct stable message IDs with same content and timestamp both persist`
   - Use the existing in-memory group and message repositories.
   - Send two incoming messages with the same `groupId`, `senderId`, sanitized `text`, and `timestamp`, but different non-empty `messageId` values.
   - Assert both calls return non-null, both IDs are preserved, `msgRepo.count == 2`, and both rows are visible in `getMessagesPage`.
   - This should fail on current code because the second message reaches `existsByContent` and returns `null`.

2. `PGC-007 event-log path keeps distinct stable message IDs despite same content`
   - Use `_FakeEventLog` as `appendGroupEventLogEntry`.
   - Repeat the same unique-ID duplicate-content scenario.
   - Assert two rows and two event-log entries, preserving the current event-log-before-dedupe ordering while preventing content fallback from dropping the second stable-ID message.
   - This is mandatory because the current focused test file already has `_FakeEventLog`; if it fails for a reason unrelated to content dedupe, stop and document the exact blocker instead of broadening the implementation.

Do not remove or weaken existing no-ID content-dedupe tests.

## step-by-step implementation plan

1. Reconfirm `git status --short` and do not touch unrelated dirty files.
2. Add the two PGC-007 failing tests in `handle_incoming_group_message_use_case_test.dart`.
3. Run `flutter test --no-pub test/features/groups/application/handle_incoming_group_message_use_case_test.dart --plain-name 'PGC-007'` and record the expected red result. If the selector already passes, stop and reclassify as `stale/already-covered` with evidence.
4. In `handle_incoming_group_message_use_case.dart`, introduce or reuse a local stable-ID predicate such as `final hasStableMessageId = messageId != null && messageId.isNotEmpty;`.
5. Replace repeated non-empty message-id condition checks with that predicate only where behavior stays equivalent.
6. Wrap the content fallback so `existsByContent(...)` is called only when `!hasStableMessageId`.
7. Do not move the event-log append earlier or later. Do not change same-ID dedupe, conflict rejection, self-echo reconciliation, repair-placeholder handling, media enrichment, membership checks, timestamp normalization, username refresh, or generated UUID behavior for no-ID messages.
8. Run the PGC-007 selector and preservation selectors. If legacy no-ID dedupe fails, stop and fix only the guard condition.
9. Run the full focused handler test file, analyzer/format checks, `git diff --check`, and the Group Messaging Gate.
10. After evidence is green or exactly triaged, update only row `PGC-007` and the `PGC-INCOMING-1` ledger in the source matrix/breakdown. Do not claim adjacent rows.

## risks and edge cases

- Same text and timestamp are plausible when retry/replay or clock coalescing occurs; stable IDs must win over content equality.
- Sanitized text can collapse visually distinct wire text. That is still correct only for no-ID legacy messages.
- Event-log append path must not turn a unique-ID message into an event-log-only phantom with no saved timeline row.
- Same-ID replay must remain idempotent and must not create a second row.
- Repair placeholders must remain eligible for replacement/enrichment by stable ID.
- Self-echo reconciliation for local outgoing rows must still run before duplicate skip.
- Generated UUID behavior for no-ID messages must stay after no-ID content-dedupe.

## exact tests and gates to run

Direct red/green selector:

```bash
flutter test --no-pub test/features/groups/application/handle_incoming_group_message_use_case_test.dart --plain-name 'PGC-007'
```

Focused preservation selectors:

```bash
flutter test --no-pub test/features/groups/application/handle_incoming_group_message_use_case_test.dart --plain-name 'deduplicates identical incoming messages'
flutter test --no-pub test/features/groups/application/handle_incoming_group_message_use_case_test.dart --plain-name 'deduplicates messages after sanitizing invisible bidi controls'
flutter test --no-pub test/features/groups/application/handle_incoming_group_message_use_case_test.dart --plain-name 'deduplicates by messageId when pubsub and group inbox deliver same message'
flutter test --no-pub test/features/groups/application/handle_incoming_group_message_use_case_test.dart --plain-name 'duplicate replay with the same messageId ignores a tampered timestamp'
flutter test --no-pub test/features/groups/application/handle_incoming_group_message_use_case_test.dart --plain-name 'duplicate replay with the same messageId ignores conflicting content'
flutter test --no-pub test/features/groups/application/handle_incoming_group_message_use_case_test.dart --plain-name 'SV-010 duplicate message id from different sender cannot overwrite valid row'
```

Focused file and static checks:

```bash
flutter test --no-pub test/features/groups/application/handle_incoming_group_message_use_case_test.dart
dart analyze lib/features/groups/application/handle_incoming_group_message_use_case.dart test/features/groups/application/handle_incoming_group_message_use_case_test.dart
dart format --output=none --set-exit-if-changed lib/features/groups/application/handle_incoming_group_message_use_case.dart test/features/groups/application/handle_incoming_group_message_use_case_test.dart
git diff --check
```

Named gate:

```bash
./scripts/run_test_gates.sh groups
```

If Flutter reports multiple attached targets, rerun the named gate with an explicit host target:

```bash
FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups
```

Not required unless a new test file or gate classification is added:

```bash
./scripts/run_test_gates.sh completeness-check
```

No Go, relay, simulator, migration, UI, notification, or full `flutter test` gate is required for this row unless implementation escapes the planned file set.

## known-failure interpretation

- There are no accepted known failures for the new `PGC-007` selector, the focused handler file, analyzer, format, or `git diff --check`.
- A failure in any PGC-007 selector is row-owned and must be fixed or reclassified with evidence.
- A failure in legacy no-ID content dedupe or same-ID replay preservation is a regression caused by this session unless reproduced on the exact pre-implementation worktree.
- A broad `groups` gate failure may be treated as unrelated only if the executor records the exact failing test name, reruns the smallest failing selector, and shows it is outside `handleIncomingGroupMessage`/PGC-007 or already present before this session's edits.
- Dirty-worktree failures from files outside this session must be documented, not reverted.

## done criteria

- PGC-007 regression test(s) are added before implementation and fail on current behavior or are documented as already covered.
- The handler only calls `existsByContent` for no-ID incoming messages.
- PGC-007 selector passes after the fix.
- Existing no-ID content dedupe, same-ID replay, conflict rejection, self-echo, and repair-placeholder behavior remain green through the listed preservation selectors or full handler file.
- `dart analyze`, `dart format --output=none --set-exit-if-changed`, `git diff --check`, and the Group Messaging Gate have passing evidence or exact unrelated-failure triage.
- Source matrix row `PGC-007` and the breakdown ledger are updated only after evidence is collected.

## scope guard

Do not change:

- Any file outside `handle_incoming_group_message_use_case.dart`, `handle_incoming_group_message_use_case_test.dart`, and final source docs unless a focused PGC-007 failure proves it necessary.
- Repository schema, DB helper insert/upsert behavior, migration files, generated UUID format, event-log storage, listener stream/notification behavior, offline inbox drain, send status, Go PubSub code, or relay code.
- Existing same-ID dedupe semantics, including conflicting duplicate rejection and duplicate replay enrichment.
- Existing legacy no-ID content dedupe semantics.

Overengineering for this session includes introducing a new dedupe service, changing repository interfaces, adding database uniqueness constraints, adding protocol fields, or trying to solve clock/timestamp collision beyond honoring stable message IDs.

## accepted differences / intentionally out of scope

- Content-based dedupe remains intentionally available for legacy/no-ID messages.
- Stable-ID messages may still have identical sender/content/timestamp; they are distinct by wire ID.
- This session does not attempt to verify whether upstream senders can generate duplicate IDs; same-ID behavior remains first-row-wins plus existing conflict checks.
- This session does not address PGC-005/PGC-006 DB read/save behavior, even though those rows may affect persistence reliability.
- This session does not add listener-level or simulator-level coverage unless the focused handler test cannot prove the row.

## dependency impact

- `PGC-DRAIN-1`, `PGC-LISTENER-1`, and future resume/offline replay work can rely on stable IDs preventing content-collision drops in the incoming handler once this closes.
- `PGC-DB-1` may later change message repository persistence semantics; if it touches `saveMessage`, `getMessage`, or `existsByContent`, rerun the PGC-007 selector.
- If this plan changes to require repository or DB-helper work, pause and split that into `PGC-DB-1` rather than expanding this session.

## reviewer findings

- Verdict: sufficient with adjustment.
- Missing files/tests/gates: none after making the event-log path mandatory; the plan names the exact owner file, focused test file, source docs, gate docs, direct selectors, static checks, and Group Messaging Gate.
- Stale/incorrect assumptions: none found. Current code evidence matches PGC-007: `existsByContent` is still unconditional after stable-ID checks.
- Overengineering: none; the plan forbids repository/schema/protocol changes and keeps the fix to a stable-ID guard.
- Decomposition: sufficient; one row, one handler branch, focused tests first.
- Minimum needed: keep the mandatory normal-path and event-log-path PGC-007 tests, then guard content dedupe behind `!hasStableMessageId`.

## arbiter decision

- Structural blockers: none.
- Incremental details: reviewer requested mandatory event-log-path wording; applied before final readiness.
- Accepted differences: legacy no-ID content dedupe remains intentionally unchanged; listener/integration/simulator coverage is not required unless focused handler proof becomes insufficient; DB/repository persistence hardening stays with `PGC-DB-1`.
- Stop rule: no structural blocker remains, so do not loop. Execute the plan as written and do not broaden the session.

## structural blockers remaining

None.

## incremental details intentionally deferred

None.

## accepted differences intentionally left unchanged

- Content-based dedupe remains for legacy messages without stable IDs.
- Same-ID duplicate replay stays first-row-wins with existing conflict/self-echo/repair enrichment behavior.
- Repository, schema, listener, offline drain, Go node, relay, UI, and simulator work stay outside this session.

## exact docs/files used as evidence

- `Test-Flight-Improv/Group-Chat-Feature/private-group-chat-reliability-findings-2026-05-23-matrix.md`
- `Test-Flight-Improv/Group-Chat-Feature/private-group-chat-reliability-findings-2026-05-23-session-breakdown.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `scripts/run_test_gates.sh`
- `lib/features/groups/application/handle_incoming_group_message_use_case.dart`
- `lib/features/groups/domain/repositories/group_message_repository.dart`
- `lib/features/groups/domain/repositories/group_message_repository_impl.dart`
- `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`
- `test/shared/fakes/in_memory_group_message_repository.dart`
- `git status --short`

## why the plan is safe to implement now

The plan has one row, one production owner branch, focused red-first tests, exact preservation selectors, a named group gate, known-failure handling for the dirty worktree, and an explicit scope guard that prevents drift into DB, listener, offline drain, Go, relay, UI, or simulator work.
