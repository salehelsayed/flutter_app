# Report 108 Session GFR-003 Plan - Open Conversation Recovery UX

Status: closed

## Planning Progress

- 2026-06-06 12:41:32 CEST - Role: Arbiter completed. Files inspected since
  last update: GFR-003 plan draft, source/breakdown GFR-003 checklist, group
  conversation wired/screen seams, `LetterCard` failed action widget, current
  group presentation tests, `GroupRecoveryGate`, and graphify query/explain
  output. Decision/blocker: no structural planning blocker remains; local
  fallback plan is reusable and execution-ready. Next action: update the
  breakdown ledger to `execution-ready`, then launch fresh GFR-003
  execution/QA.
- 2026-06-06 12:41:05 CEST - Role: Reviewer completed. Files inspected since
  last update: mandatory plan sections, closure bar, GFR-003 checklist mapping,
  and named gate contract. Decision/blocker: host widget/wired proof is
  sufficient for this UI session; whole-journey simulator acceptance remains
  the explicit GFR-004 dependency. Next action: arbiter classification.
- 2026-06-06 12:40:48 CEST - Role: Planner completed. Files inspected since
  last update: `group_conversation_wired.dart`, `group_conversation_screen.dart`,
  `letter_card.dart`, `group_conversation_wired_test.dart`, and
  `group_conversation_screen_test.dart`. Decision/blocker: plan targets the
  existing presentation/wired seams without touching GFR-001/GFR-002 lower
  layers. Next action: reviewer pass.
- 2026-06-06 12:40:40 CEST - Role: Local fallback recovery. Files/processes
  inspected since last update: missing GFR-003 plan path, active planner process
  list, exited planner PTY session, breakdown controller progress, GFR-003
  breakdown row, and child planner output captured before termination.
  Decision/blocker: no product blocker has been found; the spawned planner was
  stopped because it left this required current-doc artifact absent during a
  draft rewrite. Next action: complete the local fallback plan from the
  gathered evidence, run a quick graphify/code sanity pass, then set `Status:
  execution-ready` or persist an exact blocker before GFR-003 execution.

## real scope

GFR-003 changes only the open group conversation UX for already-persisted
outgoing group text attempts:

- keep a failed or queued text attempt represented as one row and remove the
  restored same-text composer path as an obvious second independent Send path
  when the row remains recoverable
- expose retry/send-now recovery as a row-scoped action that visibly disables or
  settles while that row is in flight
- coalesce repeated Retry taps for the same row in the wired UI before they can
  call the retry use case twice
- suppress retry affordances while write permission, dissolved/read-only state,
  or active `GroupRecoveryGate` would make recovery impossible or duplicate the
  lower-level recovery pass
- preserve failed media retry/delete behavior and keep text rows out of media
  controls
- preserve quote context on the persisted row without leaving a stale quote/text
  draft that can resend the same attempt independently
- prove an already-open conversation observes local outgoing status changes in
  place through the existing `GroupOutgoingLocalMessageChangeSource`

Out of scope: message identity and retry-use-case locking already closed by
GFR-001, auto retry/readiness orchestration already closed by GFR-002, lifecycle
or multi-device acceptance owned by GFR-004, and final source-doc closure owned
by GFR-005.

## closure bar

GFR-003 is good enough when every checklist item below is covered by a focused
host test or an accepted downstream dependency:

| GFR-003 requirement | Planned proof |
| --- | --- |
| Failed/queued text represented once | `group_conversation_wired_test.dart` proves failed no-transport text remains one row and composer text is empty rather than restored as a second Send opportunity. |
| Retry/send-now in-progress state | `group_conversation_screen_test.dart` proves row action can be disabled/relabelled while a message id is retrying; `group_conversation_wired_test.dart` proves the wired retry Future holds that state until completion. |
| Repeated Retry tap suppression | `group_conversation_wired_test.dart` calls/taps the same retry twice while the first is pending and expects one `group:publish`/retry invocation. |
| Read-only/dissolved/recovery-gate behavior | `group_conversation_screen_test.dart` and/or wired test proves failed text retry is absent or disabled when `canWrite` is false or `isRecovering` is true. Existing read-only screen coverage must remain green. |
| Failed media preservation | Existing failed-media screen test remains and is extended only if shared action props change. Media rows must still show retry/delete and text rows must not show media controls. |
| Quote/draft behavior | Wired test seeds a failed quoted text row, retries or fails again, and verifies quote remains on the row while composer text/quote are not restored as a duplicate draft. |
| Open conversation row updates | Wired test uses `InMemoryGroupMessageRepository`/local outgoing event stream to update `failed -> sending/sent` and verifies the already-open `GroupConversationScreen` row changes in place without a manual reload. |

Simulator acceptance is not required to close GFR-003 itself because this session
owns presentation/wired UX. The multi-device sender/recipient proof remains a
required GFR-004 closure dependency before the overall Report 108 final verdict.

## source of truth

- Primary: `Test-Flight-Improv/108-group-failed-message-retry-duplicate-send-ux-session-breakdown.md`, Session GFR-003.
- Secondary: `Test-Flight-Improv/108-group-failed-message-retry-duplicate-send-ux.md`, especially the user-visible composer/Retry/recovery acceptance bullets.
- Upstream constraints: GFR-001 and GFR-002 plan closure notes are accepted and must not be reopened except as assumptions.
- Code truth: current Flutter code and tests win over stale prose if a detail conflicts.
- Gate truth: `Test-Flight-Improv/test-gate-definitions.md` and `scripts/run_test_gates.sh`.

`graphify query` was run first for the GFR-003 presentation/wiring question, but
it returned a broad, low-signal subgraph. `graphify explain GroupConversationWired`
confirmed the primary source node, so the fallback plan uses exact file
inspection for details.

## session classification

`implementation-ready`

## exact problem statement

The lower layers can now retry one persisted attempt, but the open group
conversation still risks an untrustworthy recovery experience: the composer may
restore the same failed text and quote while the failed row also offers Retry,
row retry has no visible in-flight state, and repeated Retry taps can appear to
start independent recovery actions. The UI must guide the user toward one
recoverable row and avoid presenting the same failed text as a fresh send path.

## files and repos to inspect next

- `lib/features/groups/presentation/screens/group_conversation_wired.dart`
- `lib/features/groups/presentation/screens/group_conversation_screen.dart`
- `lib/features/conversation/presentation/widgets/letter_card.dart`
- `lib/features/conversation/presentation/widgets/compose_area.dart`
- `lib/features/groups/application/group_recovery_gate.dart`
- `lib/l10n/app_en.arb`, `lib/l10n/app_ar.arb`, `lib/l10n/app_de.arb`, and generated `lib/l10n/app_localizations*.dart` only if new visible copy is introduced
- `test/features/groups/presentation/group_conversation_wired_test.dart`
- `test/features/groups/presentation/group_conversation_screen_test.dart`
- `test/features/conversation/presentation/widgets/letter_card_test.dart` only if `LetterCard` API changes

## existing tests covering this area

- `group_conversation_screen_test.dart` already proves failed outgoing text-only
  rows show Retry, failed media rows show retry/delete, text rows avoid failed
  media controls, and read-only text rows do not show retry.
- `group_conversation_wired_test.dart` already proves failed publish shows a
  failed message and currently keeps the draft, and proves targeted failed text
  retry re-sends one row.
- Repository tests already prove outgoing local status events fire on outgoing
  status changes; GFR-003 needs a wired/open-screen proof consuming those events.
- `GroupRecoveryGate` is already observed by `GroupConversationWired` as
  `isRecovering`; current screen uses `isRecovering` for loading state, not yet
  as row-action disabling evidence.

## regression/tests to add first

Add focused RED tests before production edits:

1. In `group_conversation_wired_test.dart`, add `GFR-003 failed text recovery clears duplicate composer path`: force a failed text send, assert one visible failed row, retry affordance present, composer text empty, and no second row is created by stale restored text.
2. In `group_conversation_wired_test.dart`, add `GFR-003 repeated retry taps coalesce while row retry is in flight`: hold the retry bridge/use-case path pending, trigger retry twice for the same message id, expect one publish/retry call and an in-flight row state until completion.
3. In `group_conversation_screen_test.dart`, add `GFR-003 retry action reflects in-flight and recovery-gate state`: with a failed text row and a retrying id or `isRecovering: true`, assert the Retry action is disabled/absent according to implementation and cannot invoke the callback.
4. In `group_conversation_screen_test.dart`, extend or add `GFR-003 failed media controls are preserved`: after any shared `LetterCard` action change, failed media retry/delete remain visible and text rows still do not show media controls.
5. In `group_conversation_wired_test.dart`, add `GFR-003 quoted failed text does not restore stale duplicate quote draft`: seed/produce a failed quoted text row and prove the row preserves `quotedMessageId` while composer text and active quote are cleared after failure/retry handling.
6. In `group_conversation_wired_test.dart`, add `GFR-003 open conversation applies outgoing local status update in place`: update an existing outgoing row through the fake repository/status stream and assert the visible screen row changes status without route reload.

## step-by-step implementation plan

1. Add the RED tests above, keeping names prefixed with `GFR-003` for focused runs.
2. In `GroupConversationWired`, add row-scoped retry tracking such as
   `_retryingFailedMessageIds` and helpers to begin/end a retry by message id.
   Guard `_onRetryFailedMessage` so a second call for the same id returns
   without invoking `retryFailedGroupMessage`.
3. In `GroupConversationWired`, make retry availability depend on write
   permission, media repo presence, no active `GroupRecoveryGate`, and the row
   not already being retried. Pass the retrying id set or a predicate/state down
   to `GroupConversationScreen`.
4. In `GroupConversationScreen`, add a minimal retry-state prop and use it when
   deciding whether failed text Retry is enabled. Keep failed media logic
   separate.
5. If `LetterCard` needs disabled action support, extend its failed action API
   narrowly with optional enabled/loading semantics while preserving existing
   keys and semantics labels. Avoid broad card redesign.
6. Change failed text send failure handling in `GroupConversationWired` so a
   text-only persisted failed row does not restore the same draft/quote as a
   second composer send opportunity. Preserve restoration for failed media and
   active upload continuation paths where the existing durable media retry flow
   depends on it.
7. Ensure retry completion updates the visible row through
   `_refreshMessageWithHydratedMedia`, `_updateLocalMessageStatus`, or the
   existing local outgoing status stream. Do not add a new global event bus.
8. Keep read-only and dissolved behavior aligned with `_canWrite`; clear active
   quote when write access is lost as current code already does.
9. Run format, focused tests, direct suites, `groups` gate, `graphify update .`,
   and diff hygiene checks.

Stop and record a same-session recovery note if tests show the required behavior
cannot be implemented without reopening GFR-001/GFR-002 lower-layer contracts.

## risks and edge cases

- Text-only failure must clear the duplicate draft, but media upload failures
  must still preserve media continuation affordances.
- A retry Future can throw; the retrying id must be cleared in `finally`.
- Active `GroupRecoveryGate` should not invite another manual retry that races
  the resume/auto recovery owner.
- Read-only or dissolved groups must not expose actions that will only fail.
- Quote metadata belongs on the failed/retried row; the composer quote preview
  should not remain as a stale second-send path.
- Local outgoing status events may arrive for other groups; existing filtering
  must remain.

## exact tests and gates to run

Focused GFR-003 tests:

```bash
flutter test test/features/groups/presentation/group_conversation_wired_test.dart --plain-name "GFR-003"
flutter test test/features/groups/presentation/group_conversation_screen_test.dart --plain-name "GFR-003"
```

Direct suites:

```bash
flutter test test/features/groups/presentation/group_conversation_wired_test.dart
flutter test test/features/groups/presentation/group_conversation_screen_test.dart
flutter test test/features/conversation/presentation/widgets/letter_card_test.dart
```

Named and hygiene gates:

```bash
./scripts/run_test_gates.sh groups
dart format lib/features/groups/presentation/screens/group_conversation_wired.dart lib/features/groups/presentation/screens/group_conversation_screen.dart lib/features/conversation/presentation/widgets/letter_card.dart test/features/groups/presentation/group_conversation_wired_test.dart test/features/groups/presentation/group_conversation_screen_test.dart test/features/conversation/presentation/widgets/letter_card_test.dart
graphify update .
git diff --check
```

If no `LetterCard` file changes are made, the `letter_card_test.dart` direct
suite and formatter entry may be skipped only if the execution notes explicitly
say the card API was untouched.

## known-failure interpretation

- Existing unrelated dirty docs under
  `Test-Flight-Improv/Group-Chat-Feature/Improvement-Review-2026-06/` and
  generated `info.plist` timestamp changes are not GFR-003 regressions and must
  not be reverted.
- A failure in a new `GFR-003` test is a GFR-003 product/test issue until proven
  to be a stale test assumption.
- A failure in GFR-001/GFR-002 application/retrier tests after UI-only changes
  is likely unintended lower-layer drift; do not broaden GFR-003 to fix it
  without a recovery note.
- Simulator/device unavailability belongs to GFR-004 final acceptance, not to
  this GFR-003 host UI closure.

## done criteria

- The plan's GFR-003 checklist coverage ledger has passing focused proof.
- Failed text rows provide one clear recovery target and no restored duplicate
  same-text composer path.
- Repeated Retry taps for the same row are visibly/behaviorally coalesced.
- Read-only, dissolved, and active recovery states do not invite impossible or
  duplicate recovery.
- Failed media retry/delete controls still work.
- Quoted failed text recovery does not leave stale quote/draft composer state.
- Open conversations observe outgoing status updates in place.
- Required focused tests, direct suites, `groups` gate, `graphify update .`, and
  `git diff --check` are recorded in Execution Progress.

## scope guard

Do not change group protocol payloads, message-id generation, repository retry
eligibility, receiver dedupe, pending-message auto recovery, lifecycle resume
ordering, media upload encryption, reactions, notification routing, or
membership/key repair. Those are GFR-001, GFR-002, GFR-004, or unrelated owners.

## accepted differences

- GFR-003 may prove recovery-gate behavior with disabled/absent controls rather
  than a final polished loading copy, provided the user cannot start a duplicate
  manual recovery while recovery is active.
- GFR-003 may keep the visible label as "Retry" if disabled/in-flight semantics
  and tests prove it cannot be triggered repeatedly.
- Multi-device recipient-visible proof is explicitly deferred to GFR-004 and is
  not a blocker for this UI/wired session plan.

## dependency impact

- Depends on GFR-001 for row-scoped same-attempt retry idempotency.
- Depends on GFR-002 for queued/pending recovery and local outgoing status
  events that an open conversation can observe.
- GFR-004 must include whole-journey acceptance after this UI behavior lands.
- GFR-005 must update the final source/closure docs after GFR-004 acceptance.

## sufficiency review

Reviewer finding: the plan covers every GFR-003 checklist item with focused
tests or an explicit GFR-004 downstream dependency. It stays in presentation and
wired UI seams, names exact files, and includes gates. No structural blocker was
found. Incremental detail: execution should avoid adding new copy/localization
unless disabled action semantics cannot be expressed with existing labels.

## arbiter decision

Structural blockers: none.

Incremental details:

- Prefer a tiny row-state prop over broad composer state changes.
- Keep failed media restoration behavior intact even if text-only failures stop
  restoring drafts.

Accepted differences:

- GFR-003 closes host UI/wired behavior only; final simulator proof remains
  GFR-004.

Decision: `execution-ready`.

## Execution Progress

- 2026-06-06 13:14:05 CEST - Phase: local execution recovery accepted. Files
  inspected or touched since last update: graphify output mtimes, full
  `git diff --check`, final GFR-003 scoped diff, and stopped execution recovery
  child session. Current command: none. Decision/blocker: no blocker; graphify
  output files (`graph.json`, `manifest.json`, labels, report) were updated at
  13:11 CEST, full `git diff --check` produced no output, and the child was
  stopped only after its subprocess work had completed but the Codex wrapper no
  longer had a visible `graphify`, Flutter, or gate process. Final GFR-003
  execution verdict: `accepted`. Next action: launch fresh GFR-003 closure
  audit and update the breakdown ledger.
- 2026-06-06 13:12:20 CEST - Phase: graphify finalize recovered locally. Files
  inspected or touched since last update: `graphify-out/graph.json`,
  `graphify-out/manifest.json`, `graphify-out/.graphify_labels.json`,
  `graphify-out/GRAPH_REPORT.md`, process table, and full worktree whitespace
  check. Current command: none. Decision/blocker: no product blocker; the
  graph files were refreshed by the child-run `graphify update .`, but the
  child wrapper stalled without an active graphify subprocess, so the parent
  completed the remaining verification locally. Next action: persist accepted
  execution verdict.
- 2026-06-06 13:08:55 CEST - Phase: groups gate passed. Files inspected or
  touched since last update: `./scripts/run_test_gates.sh groups` output and
  scoped GFR-003 diff stat. Current command: none. Decision/blocker: no
  blocker; the required named `groups` gate passed. Next action: rerun the
  exact formatter command after the test-only fix, then run `graphify update .`
  and full `git diff --check`.
- 2026-06-06 13:07:31 CEST - Phase: direct suites passed. Files inspected or
  touched since last update: LetterCard direct suite output and scoped diff
  whitespace check. Current command: none. Decision/blocker: no blocker;
  `flutter test
  test/features/conversation/presentation/widgets/letter_card_test.dart`
  passed, and the three required direct suites are now green. Scoped
  `git diff --check` on GFR-003 files produced no output. Next action: run the
  required named `groups` gate.
- 2026-06-06 13:07:03 CEST - Phase: screen direct suite passed. Files
  inspected or touched since last update: screen direct suite output and scoped
  GFR-003 diff stat. Current command: none. Decision/blocker: no blocker;
  `flutter test
  test/features/groups/presentation/group_conversation_screen_test.dart`
  passed. Next action: run `letter_card_test.dart` direct suite because the
  LetterCard failed-action API changed.
- 2026-06-06 13:06:35 CEST - Phase: wired direct suite passed. Files inspected
  or touched since last update: full wired suite output and scoped GFR-003 diff
  stat. Current command: none. Decision/blocker: no blocker; `flutter test
  test/features/groups/presentation/group_conversation_wired_test.dart` passed
  after the focused test expectation fix. Next action: run
  `group_conversation_screen_test.dart` direct suite.
- 2026-06-06 13:05:49 CEST - Phase: direct wired test fix pass completed.
  Files inspected or touched since last update:
  `test/features/groups/presentation/group_conversation_wired_test.dart` and
  focused triage command output. Current command: none. Decision/blocker: no
  blocker; stale wired expectations were updated and the focused triage rerun
  passed for `sending a message calls bridge and refreshes`, `failed text row
  retry reuses the failed group row id after composer clears`, and `manual
  edited composer send after text failure creates a new group row id`. Next
  action: rerun full wired direct suite.
- 2026-06-06 13:04:48 CEST - Phase: direct wired failure triaged. Files
  inspected or touched since last update: JSON test reporter output at
  `/tmp/gfr003-wired-test.json`, failing wired test slices, and
  `send_group_message_use_case.dart` membership timeline lookup. Current
  command: none. Decision/blocker: no blocker; the three failures are
  classified as stale test expectations after GFR-003/GFR-001 behavior rather
  than product regressions. The page-load expectation counts the send use
  case's membership timeline `getMessagesPage` lookup, and the two text-only
  restored-composer tests contradict the GFR-003 requirement that failed text
  no longer restores the duplicate composer path. Next action: update only
  those test expectations, then rerun focused slices and the full wired suite.
- 2026-06-06 13:02:21 CEST - Phase: direct wired suite failed, triage started.
  Files inspected or touched since last update: full wired suite output and
  failing source slice around
  `test/features/groups/presentation/group_conversation_wired_test.dart:1415`.
  Current command: none. Decision/blocker: `flutter test
  test/features/groups/presentation/group_conversation_wired_test.dart` failed
  with three failures; first visible failure is `sending a message calls bridge
  and refreshes`, where `msgRepo.getMessagesPageCalls` was `2` instead of `1`
  after send. Classification state: `pending_triage`. Next action: run focused
  failing slices with the failures-only reporter before any fix.
- 2026-06-06 13:01:22 CEST - Phase: focused GFR-003 tests passed. Files
  inspected or touched since last update: focused wired/screen GFR-003 command
  output and current diff summary. Current command: none. Decision/blocker: no
  blocker; `flutter test
  test/features/groups/presentation/group_conversation_wired_test.dart
  --plain-name "GFR-003"` passed and `flutter test
  test/features/groups/presentation/group_conversation_screen_test.dart
  --plain-name "GFR-003"` passed after the production seam. Next action: run
  required direct suites for wired, screen, and LetterCard.
- 2026-06-06 13:00:45 CEST - Phase: formatter completed. Files inspected or
  touched since last update: all GFR-003 production/test files in the exact
  formatter command. Current command: none. Decision/blocker: no blocker;
  `dart format` completed successfully and changed the wired test, wired
  screen, and letter card test formatting only as needed. Next action: rerun
  focused GFR-003 wired and screen tests after the production seam.
- 2026-06-06 13:00:21 CEST - Phase: production seam patched. Files inspected
  or touched since last update:
  `lib/features/groups/presentation/screens/group_conversation_wired.dart`,
  `lib/features/groups/presentation/screens/group_conversation_screen.dart`,
  and `lib/features/conversation/presentation/widgets/letter_card.dart`.
  Current command: none. Decision/blocker: no blocker; production changes add
  row-scoped retry in-flight/coalescing, disabled retry action semantics, active
  recovery-gate retry suppression, and text-only failure composer/quote
  clearing while leaving media restoration paths intact. Next action: run the
  exact formatter command, then rerun focused GFR-003 tests.
- 2026-06-06 12:58:35 CEST - Phase: focused RED commands completed.
  Files inspected or touched since last update: GFR-003 tests and focused
  command output. Current command: none. Decision/blocker: no blocker; both
  focused commands failed at the expected missing production seam
  (`retryingFailedMessageIds` not yet defined on `GroupConversationScreen`),
  so the RED failure is classified as caused by this session's planned
  test-first API addition. Next action: land the narrow production seam for
  retry in-flight state, recovery-gate disabling, and text-only failure
  composer clearing.
- 2026-06-06 12:57:28 CEST - Phase: RED tests added. Files inspected or
  touched since last update:
  `test/features/groups/presentation/group_conversation_wired_test.dart`,
  `test/features/groups/presentation/group_conversation_screen_test.dart`, and
  `test/features/conversation/presentation/widgets/letter_card_test.dart`.
  Current command: none. Decision/blocker: no blocker; focused GFR-003
  regressions now cover text-only composer clearing, quoted draft clearing,
  row retry coalescing/in-flight state, recovery-gate disabling, failed media
  preservation, and open-row status updates. Next action: run the focused
  GFR-003 tests to capture the expected RED failure before production edits.
- 2026-06-06 12:51:44 CEST - Phase: local fallback contract extracted.
  Files inspected or touched since last update: execution-QA orchestrator skill,
  GFR-003 plan/breakdown/source docs, current dirty-tree summary, `graphify
  query` for the GFR-003 presentation seam, and `graphify explain
  GroupConversationWired`. Current command: none. Decision/blocker: no blocker;
  local sequential fallback is allowed because the nested Executor failure was
  a no-progress `spawn_or_tool_failure`, this context is isolated, and the
  plan remains concrete enough to execute safely. Next action: inspect exact
  owner files/tests and add focused GFR-003 RED coverage before production
  edits.
- 2026-06-06 12:50:07 CEST - Phase: execution child no-progress recovery.
  Files inspected or touched since last update: GFR-003 plan Execution
  Progress, scoped GFR-003 owner-file diff, process list, and stopped
  execution/QA controller session `019e9c88-3bda-7c53-93bf-a2ceb5677c48`.
  Current command: none. Decision/blocker: nested Executor agent
  `019e9c89-a448-7af1-85e4-3f3b2328291a` recorded intake but produced no
  code/test delta, no command evidence, and no final result across bounded
  waits; classify that attempt as `spawn_or_tool_failure` for the nested
  Executor materialization, not as a GFR-003 product blocker. Next action:
  launch a fresh isolated GFR-003 execution recovery context using the
  execution-QA local sequential fallback rule, with no overlapping stale child
  process.
- 2026-06-06 12:46:12 CEST - Phase: Executor intake. Files inspected or touched
  since last update: GFR-003 plan scope/tests/gates/done criteria, GFR-003
  breakdown scope, `git status --short`, and scoped `graphify query` output.
  Current command: none. Decision/blocker: no blocker; graph query was
  low-signal for the presentation seam, so execution will use the plan's exact
  file list and rerun graphify against concrete identifiers before source
  edits. Next action: inspect the focused group conversation presentation tests
  and add GFR-003 RED coverage first.
- 2026-06-06 12:45:33 CEST - Phase: Executor spawned/running. Files inspected
  or touched since last update: GFR-003 plan Execution Progress. Current
  command: isolated Executor agent `019e9c89-a448-7af1-85e4-3f3b2328291a`
  (`Halley`) running against the GFR-003 plan. Decision/blocker: no blocker;
  waiting for Executor code/test/doc delta and required evidence. Next action:
  bounded wait, then inspect assigned files and Executor result before QA.
- 2026-06-06 12:44:54 CEST - Phase: contract extracted. Files inspected or
  touched since last update: GFR-003 plan, source Report 108 doc, session
  breakdown ledger, current dirty-tree summary, execution-QA orchestrator skill,
  and graphify scoped query output for the group conversation presentation
  surface. Current command: none. Decision/blocker: no stale or unsafe plan
  issue found; exact GFR-003 scope, closure bar, code-entry files, RED tests,
  direct tests, named gates, known-failure interpretation, done criteria, and
  non-goals are explicit. Next action: spawn isolated Executor for GFR-003 only.
- 2026-06-06 12:43:34 CEST - Phase: execution/QA launch. Files inspected or
  touched since last update: execution-ready GFR-003 plan, breakdown ledger,
  and execution-QA orchestrator skill. Current command: none yet.
  Decision/blocker: no execution blocker; contract is concrete enough to spawn
  fresh GFR-003 execution/QA. Next action: launch isolated
  `$implementation-execution-qa-orchestrator` child for this plan.

## Final Execution Verdict

Verdict: `accepted`

Blocker: none.

Accepted evidence:

- Focused RED tests failed first on the planned missing
  `retryingFailedMessageIds` presentation seam, then passed after production
  changes.
- Focused GFR-003 tests passed:
  `flutter test test/features/groups/presentation/group_conversation_wired_test.dart --plain-name "GFR-003"`
  and
  `flutter test test/features/groups/presentation/group_conversation_screen_test.dart --plain-name "GFR-003"`.
- Direct suites passed:
  `flutter test test/features/groups/presentation/group_conversation_wired_test.dart`,
  `flutter test test/features/groups/presentation/group_conversation_screen_test.dart`,
  and
  `flutter test test/features/conversation/presentation/widgets/letter_card_test.dart`.
- Named gate passed: `./scripts/run_test_gates.sh groups`.
- Formatter completed with no remaining changes on GFR-003 production/test
  files.
- `graphify update .` refreshed graph outputs at 13:11 CEST.
- Full `git diff --check` produced no output.

Residual/dependency: whole-journey simulator and cross-seam lifecycle
acceptance remains the explicit `GFR-004` owner; it is not a GFR-003 blocker.

## Closure Audit

- 2026-06-06 13:17 CEST - Role: Completion Auditor completed. Files inspected:
  this GFR-003 plan, Report 108 breakdown ledger, Report 108 source doc,
  current dirty-tree summary, scoped production diffs in
  `group_conversation_wired.dart`, `group_conversation_screen.dart`, and
  `letter_card.dart`, plus focused GFR-003 test additions in wired, screen, and
  LetterCard tests. Decision/blocker: no repo evidence contradicts the accepted
  execution verdict. GFR-003 landed the row-scoped retry in-flight set, same-row
  Retry coalescing, recovery-gate/read-only retry suppression, disabled retry
  action semantics, text-only failed-send composer/quote clearing, media retry
  preservation, and open-conversation local status update proof.
- 2026-06-06 13:17 CEST - Role: Closure Writer completed. Files updated: this
  plan and the Report 108 session breakdown. Decision/blocker: GFR-003 is
  recorded as `closed`; no stable source-doc reconciliation was made because
  final source/closure docs are explicitly owned by GFR-005 after GFR-004
  acceptance.
- 2026-06-06 13:17 CEST - Role: Closure Reviewer completed. Files reviewed:
  this closure section and the breakdown ledger update. Decision/blocker: the
  docs no longer overclaim simulator, lifecycle, or recipient-visible
  whole-journey acceptance. GFR-004 remains a downstream program dependency,
  not a GFR-003 still-open item.

Closure verdict: `closed`

What is now closed for GFR-003:

- The open group conversation represents a failed text attempt as one row and
  no longer restores the same text/quote as an independent duplicate composer
  send path for text-only failures.
- Failed text Retry is row-scoped, coalesces repeated taps while in flight, and
  disables the row action while that row is retrying or while group recovery is
  active.
- Read-only/write-blocked state does not expose text retry, failed media
  retry/delete controls remain preserved, and failed text rows stay out of
  failed-media controls.
- Existing local outgoing row-change handling is covered by a wired
  open-conversation test that observes status changes in place.
- The recorded focused tests, direct suites, `groups` gate, formatter,
  `graphify update .`, and full `git diff --check` evidence remain accepted.

Residual-only items for GFR-003: none.

Still-open items for GFR-003: none.

Accepted differences:

- The visible failed text recovery label remains `Retry`; the accepted
  behavior is disabled/in-flight/idempotent semantics, not new copy.
- Host widget and wired proof is sufficient for this session. Multi-device,
  lifecycle, reconnect, and recipient-visible whole-journey acceptance remains
  the explicit GFR-004 owner.
- Final Report 108 stable source-doc reconciliation remains the explicit
  GFR-005 owner.

Reopen rule: reopen GFR-003 only on a real regression in open-conversation
failed text row recovery UX, row retry coalescing/disabled state, composer quote
clearing for text-only failures, failed media preservation, or local outgoing
status updates. Do not reopen GFR-003 only because GFR-004 or GFR-005 remains
pending.
