Status: accepted_with_explicit_follow_up

# Report 108 Session GFR-002 Plan

Session id: `GFR-002`

Breakdown artifact:
`Test-Flight-Improv/108-group-failed-message-retry-duplicate-send-ux-session-breakdown.md`

Source doc:
`Test-Flight-Improv/108-group-failed-message-retry-duplicate-send-ux.md`

Planning fallback used: yes. A fresh spawned planner created the initial
planning-intake file and collected useful evidence, but then stayed in
terminal-only inspection without advancing this artifact. The parent pipeline
terminated only that child process and completed this bounded GFR-002 plan from
the breakdown, source doc, graphify output, and targeted source/test reads.

## Planning Progress

- 2026-06-06 12:07:07 CEST - Role: Parent pipeline progress heartbeat.
  Files inspected since last update: GFR-002 plan header, Planning Progress,
  Execution Progress, and Report 108 breakdown controller progress.
  Decision/blocker: reusable GFR-002 planning is already complete with
  `Status: execution-ready`; no planning blocker exists. Current phase is
  GFR-002 execution verification/QA recovery after a spawned-agent final-result
  failure. Next action: continue the fresh isolated verification/QA recovery
  context against the landed GFR-002 delta, then persist either accepted
  execution evidence or an exact product/tool blocker before closure.
- 2026-06-06 11:43:19 CEST - Role: Parent pipeline progress heartbeat.
  Files inspected since last update: GFR-002 execution-ready plan header and
  Report 108 breakdown ledger. Decision/blocker: reusable GFR-002 plan is
  complete with `Status: execution-ready`; no GFR-002 planning blocker. Current
  phase is GFR-002 execution launch. Next action: spawn isolated
  GFR-002 execution/QA against this plan and update execution progress during
  long test or fix phases.
- 2026-06-06 11:40:05 CEST - Role: Arbiter completed. Files inspected since
  last update: plan draft, GFR-002 breakdown checklist, Report 108 source
  acceptance bullets, `PendingMessageRetrier`, `sendGroupMessage`, direct
  retrier/lifecycle tests, and reliability runner selector syntax.
  Decision/blocker: no structural planning blocker remains; plan is
  execution-ready with simulator acceptance explicitly carried into GFR-004 if
  not run during GFR-002. Next action: launch isolated GFR-002 execution/QA.
- 2026-06-06 11:39:35 CEST - Role: Reviewer completed. Files inspected since
  last update: mandatory plan-section checklist and reliability simulator
  closure rule. Decision/blocker: sufficient after adding the
  `$run-flutter-reliability-sims` commands, flag behavior, resume/auto
  coalescing proof, and accepted difference for GFR-003 composer UI ownership.
  Next action: Arbiter classification.
- 2026-06-06 11:39:05 CEST - Role: Planner completed. Files inspected since
  last update: `lib/core/services/pending_message_retrier.dart`,
  `lib/features/p2p/domain/models/node_state.dart`,
  `lib/features/groups/application/send_group_message_use_case.dart`,
  `test/core/services/pending_message_retrier_test.dart`, and
  `test/core/lifecycle/handle_app_resumed_group_recovery_test.dart`.
  Decision/blocker: smallest coherent implementation is to tighten the existing
  `PendingMessageRetrier` owner and preserve GFR-001 row identity; no new app
  service or DB migration is justified. Next action: reviewer sufficiency pass.
- 2026-06-06 11:38:15 CEST - Role: Evidence Collector completed via parent
  fallback. Files inspected since last update: spawned planner output,
  `graphify query` output, reliability scenario criteria for
  `private_relay_reconnect_group_recovery` and
  `private_background_resume_group_delivery`, direct group lifecycle tests, and
  group repository local-event code. Decision/blocker: current code has a
  retrier owner, but its readiness trigger is circuit-address based and does
  not explicitly coalesce send-readiness flaps with app-resume recovery. Next
  action: draft narrow plan.
- 2026-06-06 11:37:17 CEST - Role: Parent pipeline progress heartbeat. Files
  inspected since last update: live spawned planner terminal output and current
  GFR-002 plan header. Decision/blocker: fresh GFR-002 planner was still
  evidence-collecting and had not yet produced the reusable plan; no exact
  product blocker was known. Current phase was GFR-002 planning. Next action was
  to wait briefly, then parent-validate or fallback.

## real scope

GFR-002 owns automatic group text retry orchestration when transport/send
readiness returns. The implementation should tighten the existing
`PendingMessageRetrier` instead of adding another background owner.

Production scope is limited to:

- detecting the readiness transition that should trigger queued/failed group
  text recovery, using `NodeState.usabilityReady` / `relayReady` evidence where
  available while preserving existing cold-start and reconnect behavior
- coalescing repeated readiness events so a queued or failed group text attempt
  enters the existing ordered recovery chain at most once per active cycle
- reusing the existing `_retryIfNeeded()` group ordering:
  rejoin topics, drain group offline inbox, acknowledge recovery, recover stuck
  group sends, retry incomplete group uploads, retry failed/pending group text
  messages, then failed group inbox-store retry after the 1:1/intro steps
- preserving `GroupRecoveryGate` and `setExternalRecoveryInProgressProvider`
  behavior so app resume and relay-ready recovery do not run independent group
  recovery chains at the same time
- making feature-flag behavior explicit: GFR-002 auto group queued-send
  recovery follows `enableResumeGroupRecovery` unless execution finds a
  narrower existing flag that is already authoritative
- ensuring no-usable-transport group text sends leave one persisted outgoing
  retryable row (`failed` or in-doubt `pending` with retry evidence) that the
  recovery owner can drain; do not create a second row for the same attempt
- relying on existing repository `saveMessage` / `updateMessageStatus` outgoing
  local-event emission, with new tests only where GFR-002 introduces a new bulk
  or readiness transition

This session must not implement open conversation visual UX, composer clearing
or text restoration, Retry button presentation, manual retry tap suppression,
new DB uniqueness constraints, relay protocol changes, group membership/key
repair changes, notification behavior, or final stable doc reconciliation.

## closure bar

GFR-002 is good enough when all of the following are true:

- a group text send attempted with no usable transport leaves exactly one
  persisted retryable outgoing row with stable `messageId` and
  `logicalDeliveryId`
- when send/readiness returns, the existing retrier owner runs the group
  recovery sequence and drains eligible failed or in-doubt group text attempts
  without further user action
- repeated readiness flaps while an attempt is queued or retrying do not create
  one publish per transition
- app-resume recovery and relay-ready recovery coalesce through the existing
  external-recovery and in-flight guards; they do not run independent recovery
  chains for the same attempt
- `enableResumeGroupRecovery: false` explicitly disables this group auto
  recovery path, or execution documents and tests an existing narrower flag
- local outgoing status/row-change events remain observable when rows transition
  between queued/retrying/sent/failed states
- announcement `group_recovery_pending` and active `GroupRecoveryGate`
  protections remain intact
- direct TDD evidence is added before production changes, direct suites pass,
  and named `groups` plus readiness/transport gates are run as required below
- simulator-backed reconnect/resume proof is either run in this session or
  explicitly carried into GFR-004 before whole-program closure

## source of truth

- Current code and direct tests win over stale prose.
- Active session contract:
  `Test-Flight-Improv/108-group-failed-message-retry-duplicate-send-ux-session-breakdown.md`,
  session `GFR-002`.
- Product source:
  `Test-Flight-Improv/108-group-failed-message-retry-duplicate-send-ux.md`.
- Named gate source:
  `Test-Flight-Improv/test-gate-definitions.md`.
- Reliability simulator runner source:
  `/Users/I560101/.codex/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh`
  and `scripts/run_reliability_simulations.sh`.
- Final stable Report 108 and matrix docs are not updated in this session except
  the breakdown ledger during closure.

## session classification

`implementation-ready`

Implementation can proceed now. Final multi-device confidence remains
simulator-gated and is owned by GFR-004 if not executed during GFR-002.

## exact problem statement

Report 108 identifies a duplicate-send UX risk for group messages when a failed
or queued send can be recovered by multiple paths: manual retry, a restored
composer send, app resume, and relay/readiness recovery. GFR-001 fixed stable
same-attempt row identity and retry eligibility. GFR-002 must now make the
automatic readiness owner use that contract.

Current evidence:

- `PendingMessageRetrier` already listens to `P2PService.stateStream`,
  debounces online transitions, and runs group recovery in an ordered chain.
- Its current readiness predicate is `isStarted && circuitAddresses.isNotEmpty`,
  while `NodeState` now exposes `relayReady`, `usabilityReady`,
  `sendCapabilityReady`, and `inboxCapabilityReady`.
- Existing tests cover online debounce, `needsGroupRecovery` immediate
  continuity sweep, app-resume group recovery ordering, feature-flag disablement
  for resume recovery, and `GroupRecoveryGate` blocking.
- Missing evidence is the combined queued-send/readiness behavior: a failed or
  pending group text is retried automatically on send readiness, readiness
  flapping is coalesced, and app resume plus auto recovery do not duplicate the
  same attempt.

Must stay unchanged: GFR-001 row identity, media retry/delete behavior, inbox
store and reaction replay ownership, group membership/key repair, announcement
send blocking during recovery, 1:1 retry behavior, and final UI presentation.

## files and repos to inspect next

Production files:

- `lib/core/services/pending_message_retrier.dart`
- `lib/features/p2p/domain/models/node_state.dart`
- `lib/core/lifecycle/handle_app_resumed.dart`
- `lib/features/groups/application/send_group_message_use_case.dart`
- `lib/features/groups/application/retry_failed_group_messages_use_case.dart`
- `lib/features/groups/application/recover_stuck_sending_group_messages_use_case.dart`
- `lib/features/groups/application/retry_failed_group_inbox_stores_use_case.dart`
- `lib/features/groups/application/group_recovery_gate.dart`
- `lib/features/groups/domain/repositories/group_message_repository.dart`
- `lib/features/groups/domain/repositories/group_message_repository_impl.dart`

Direct tests and fakes:

- `test/core/services/pending_message_retrier_test.dart`
- `test/core/services/fake_p2p_service.dart`
- `test/core/lifecycle/handle_app_resumed_group_recovery_test.dart`
- `test/core/lifecycle/handle_app_resumed_group_inbox_retry_test.dart`
- `test/core/lifecycle/handle_app_resumed_group_stuck_sending_test.dart`
- `test/features/groups/application/send_group_message_use_case_test.dart`
- `test/features/groups/application/retry_failed_group_messages_use_case_test.dart`
- `test/features/groups/application/recover_stuck_sending_group_messages_use_case_test.dart`
- `test/features/groups/domain/repositories/group_message_repository_impl_test.dart`
- `test/shared/fakes/in_memory_group_message_repository.dart`

Simulator acceptance references:

- `integration_test/scripts/run_group_multi_party_device_real.dart`
- `integration_test/group_multi_party_device_real_harness.dart`
- `integration_test/scripts/group_multi_party_device_criteria.dart`

## existing tests covering this area

- `pending_message_retrier_test.dart` covers online debounce, timer
  cancellation, external recovery skips, group continuity sweeps,
  `needsGroupRecovery` false-to-true immediate sweeps, and recovery ack ordering.
- `handle_app_resumed_group_recovery_test.dart` covers app resume order:
  rejoin, drain, recover stuck group sends, retry incomplete uploads, retry
  failed group messages, and retry failed group inbox stores. It also covers
  pending/failed background send hooks and `enableResumeGroupRecovery: false`.
- `handle_app_resumed_group_stuck_sending_test.dart` covers stuck group send
  recovery before retry.
- `handle_app_resumed_group_inbox_retry_test.dart` covers failed group inbox
  store retry on resume.
- `send_group_message_use_case_test.dart` already covers many no-custody,
  timeout, failed publish, `pending`, and retry payload outcomes.
- `retry_failed_group_messages_use_case_test.dart` now includes GFR-001
  coalescing and pending retry eligibility.
- `group_message_repository_impl_test.dart` covers outgoing status events and
  row-change events for repository updates.

Missing GFR-002 evidence:

- a no-usable-transport group text attempt is represented as exactly one
  retryable outgoing row that auto recovery can drain
- `PendingMessageRetrier` reacts to send/readiness return, not only legacy
  circuit-address transitions
- repeated readiness transitions/flaps coalesce instead of scheduling multiple
  overlapping group failed-message retries
- relay-ready auto recovery skips/coalesces while app resume is active
- feature-flag behavior for auto queued-send recovery is explicit and tested
- local outgoing status events remain observable for new GFR-002 transitions

## regression/tests to add first

Add focused RED tests before production changes:

1. In `pending_message_retrier_test.dart`, add `GFR-002 readiness return runs
   queued group retry once`. Start from a node state that is started/relay
   visible but not `usabilityReady`, then emit a state with
   `sendCapabilityReady: true` and `inboxCapabilityReady: true`. Assert the
   ordered group recovery callbacks run once and `retryFailedGroupMessagesFn`
   is called once.
2. In `pending_message_retrier_test.dart`, add `GFR-002 readiness flapping
   coalesces queued group retry`. Emit ready, not-ready, ready transitions while
   the group retry callback is delayed. Assert one active group failed-message
   retry and no second publish/retry for the same cycle.
3. In `pending_message_retrier_test.dart`, add `GFR-002 app resume external
   recovery suppresses relay-ready auto recovery`. Set
   `isExternalRecoveryInProgressFn` true while emitting the readiness transition.
   Assert group rejoin/drain/retry callbacks do not run and the skip event path
   remains non-fatal.
4. In `pending_message_retrier_test.dart` or lifecycle tests, add
   `GFR-002 enableResumeGroupRecovery false disables auto group retry`. Use a
   ready `NodeState` with `featureFlags: {'enableResumeGroupRecovery': false}`
   and assert group callbacks are skipped while non-group 1:1 retry behavior
   remains controlled by the existing path.
5. In `send_group_message_use_case_test.dart`, add `GFR-002 no usable transport
   persists one queued retryable group text row`. Simulate reliable send failure
   and legacy publish/inbox failure as needed. Assert one row, stable
   `messageId`, `logicalDeliveryId`, retry evidence, and no second row when the
   same attempt is re-entered with the same id/logical delivery id.
6. In `retry_failed_group_messages_use_case_test.dart`, add or extend a
   GFR-002 integration-style unit test proving a queued/failed row retried by
   the retrier callback uses the GFR-001 same-row contract and emits one
   underlying publish for the attempt.
7. In `group_message_repository_impl_test.dart` only if production changes add a
   new bulk status transition, add an outgoing local event assertion for that
   transition. Do not duplicate existing `saveMessage` and
   `updateMessageStatus` event tests if those paths are reused unchanged.

If an existing test already covers an item exactly after inspection, keep it as
existing evidence and record that in execution notes instead of duplicating it.

## step-by-step implementation plan

1. Record the pre-change behavior in execution notes: current
   `PendingMessageRetrier._isOnline`, `_wasOnline`, `_needsGroupRecovery`,
   `_retryIfNeeded`, `_runGroupContinuitySweepIfNeeded`, feature flag check,
   and `sendGroupMessage` no-custody status outcomes.
2. Add the focused RED tests listed above, starting with
   `pending_message_retrier_test.dart` because it owns the GFR-002 orchestration
   contract.
3. In `PendingMessageRetrier`, introduce a small readiness helper for group
   auto recovery. It should key off explicit `NodeState.usabilityReady` /
   `relayReady` evidence where available and preserve cold-start/reconnect
   behavior covered by existing tests. Keep the helper local to the retrier
   unless multiple production owners need it.
4. Track readiness state separately from plain online state if needed, for
   example `_wasRecoveryReady` in addition to `_wasOnline`. A false-to-true
   recovery-ready transition should schedule the same debounced retry loop as
   the legacy online transition.
5. Ensure readiness flapping does not start overlapping group retries. Reuse
   `_debounceTimer`, `_isRetrying`, `_isGroupContinuitySweeping`, and the
   GFR-001 row-scoped retry coalescer. Do not add a second retry scheduler.
6. Keep app-resume coalescing through
   `setExternalRecoveryInProgressProvider(() => _isResuming)` in `main.dart`
   and the existing `_isExternalRecoveryInProgressFn` checks. If tests expose a
   gap, tighten the retrier checks; do not duplicate app-resume recovery.
7. Keep `enableResumeGroupRecovery` as the group auto recovery flag unless
   current code reveals a narrower existing flag. If a narrower flag is chosen,
   document it in execution notes and test both enabled and disabled states.
8. For no-usable-transport sends, prefer preserving existing status semantics:
   failed publish/no custody should persist `failed`, timeout or live publish
   without custody should persist retryable `pending`. Only change
   `sendGroupMessage` if a RED test proves a path returns an error without a
   retryable row after pre-persist. Do not change UI composer behavior here.
9. Verify repository local events through existing `saveMessage` and
   `updateMessageStatus` paths. Add new repository behavior only if a new bulk
   transition is introduced.
10. Run focused tests, then direct suites, then named gates. If the readiness
    helper touches transport/reconnect semantics, run the transport gate.
11. Run `graphify update .` after code modifications and `git diff --check`.
12. Stop and report blocked if implementation requires new relay protocol
    commands, a DB migration, a new global app service, or UI composer changes.

## risks and edge cases

- Requiring `usabilityReady` too strictly could break legacy states/tests that
  only expose circuit addresses. Preserve existing behavior unless explicit
  readiness fields prove a stricter path.
- Triggering on both `relayReady` and `usabilityReady` can double-schedule the
  same retry. Coalesce through one scheduler and one in-flight guard.
- If readiness becomes true while app resume is active, auto recovery must skip
  rather than run a parallel chain.
- A `pending` row without retry evidence may belong to inbox-store retry only;
  do not broaden failed-message retry beyond GFR-001's eligibility.
- Local status events should not be faked from the retrier if repository updates
  already emit them; duplicated events can cause open-conversation churn.
- Feature-flag disablement must not strand 1:1 retry behavior or disable
  unrelated non-group recovery.
- Announcement group send blocking during active group recovery must remain
  unchanged.

## exact tests and gates to run

Run focused GFR-002 regressions first:

```bash
flutter test test/core/services/pending_message_retrier_test.dart --plain-name "GFR-002"
flutter test test/features/groups/application/send_group_message_use_case_test.dart --plain-name "GFR-002"
flutter test test/features/groups/application/retry_failed_group_messages_use_case_test.dart --plain-name "GFR-002"
```

Run direct suites touched by the implementation:

```bash
flutter test test/core/services/pending_message_retrier_test.dart
flutter test test/core/lifecycle/handle_app_resumed_group_recovery_test.dart
flutter test test/core/lifecycle/handle_app_resumed_group_inbox_retry_test.dart
flutter test test/core/lifecycle/handle_app_resumed_group_stuck_sending_test.dart
flutter test test/features/groups/application/send_group_message_use_case_test.dart
flutter test test/features/groups/application/retry_failed_group_messages_use_case_test.dart
flutter test test/features/groups/application/recover_stuck_sending_group_messages_use_case_test.dart
flutter test test/features/groups/domain/repositories/group_message_repository_impl_test.dart
```

Run named host gates:

```bash
./scripts/run_test_gates.sh groups
```

Run the transport gate if execution changes the readiness predicate,
`NodeState` interpretation, reconnect timing, bridge fallback, app bootstrap, or
integration-test readiness wiring. This is expected for a non-trivial GFR-002
implementation:

```bash
./scripts/run_test_gates.sh transport
```

Run diff/format checks:

```bash
dart format <touched dart files>
git diff --check
graphify update .
```

Simulator acceptance command required before final Report 108 closure, either
in GFR-002 if devices are available or in GFR-004 if host execution is accepted
with explicit follow-up:

```bash
"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --list
"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --only integration_test/scripts/run_group_multi_party_device_real.dart:private_relay_reconnect_group_recovery
"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --only integration_test/scripts/run_group_multi_party_device_real.dart:private_background_resume_group_delivery
```

If simulator device resolution fails, persist the exact failure in the GFR-002
closure notes and keep the whole-program verdict open until GFR-004 records
run evidence or an explicit residual classification.

## known-failure interpretation

- Pre-existing dirty docs under
  `Test-Flight-Improv/Group-Chat-Feature/Improvement-Review-2026-06/` and
  untracked local agent/graphify artifacts are unrelated and must not be
  reverted.
- A failure in newly added `GFR-002` tests is a product regression until proven
  to be a stale test assumption.
- A pre-existing failure outside the touched group/retrier/lifecycle/transport
  surfaces should be recorded with command output and left for its owner.
- If `./scripts/run_test_gates.sh transport` fails only in an unrelated
  simulator/device prerequisite, record the exact command and prerequisite; do
  not weaken GFR-002 host assertions.
- If the reliability simulator commands cannot resolve enough booted devices,
  classify that as evidence unavailable for final Report 108 acceptance, not as
  proof that the behavior is correct.

## done criteria

- GFR-002 focused RED tests are added first and pass after implementation.
- One readiness-return event drains eligible group queued/failed/in-doubt text
  attempts through the existing ordered recovery chain.
- Readiness flapping and resume overlap do not duplicate an attempt.
- Feature-flag behavior is explicit and tested.
- No-usable-transport send behavior leaves one retryable persisted row for the
  same attempt, without adding UI composer behavior in this session.
- Existing GFR-001 retry identity tests still pass.
- Direct suites and named gates listed above pass, or any pre-existing/unowned
  failure is recorded with exact command and evidence.
- `graphify update .` has been run after code changes.
- Closure notes update this plan and the breakdown ledger before GFR-003 begins.

Coverage ledger for the GFR-002 checklist:

| Requirement | Planned proof |
| --- | --- |
| send with no usable transport queues once | `send_group_message_use_case_test.dart --plain-name "GFR-002"` |
| auto delivery on readiness return | `pending_message_retrier_test.dart --plain-name "GFR-002"` plus GFR-004 simulator |
| readiness flapping does not duplicate | `pending_message_retrier_test.dart --plain-name "GFR-002"` |
| app resume and auto recovery coalesce | `pending_message_retrier_test.dart` external recovery test plus lifecycle direct suite |
| feature flag explicit | `pending_message_retrier_test.dart` or lifecycle feature-gate test |
| local row/status signals observable | existing repository event tests, plus new repo test only if new transition added |
| `GroupRecoveryGate` protections preserved | existing lifecycle/group recovery tests and announcement guard remains out of code scope |
| recipients observe one copy | simulator command in GFR-002 or GFR-004 |

## Execution Progress

- 2026-06-06 12:24:39 CEST - Phase: final local QA completed.
  Files inspected or touched since last update: GFR-002 landed diff, transport
  gate rerun output, graphify output, `git diff --check`, current `git status`,
  and plan verdict section. Commands finished:
  `FLUTTER_DEVICE_ID=5BA69F1C-B112-47BE-B1FF-8C1003728C8F ./scripts/run_test_gates.sh transport`
  passed after the earlier no-device-selector invocation failure; `graphify update .`
  completed; `git diff --check` passed. Current command: none.
  Decision/blocker: no blocking QA issue remains for GFR-002. Next action:
  stop; do not proceed to GFR-003 from this recovery pass.
- 2026-06-06 12:13:10 CEST - Phase: named gate failure triaged.
  Files inspected or touched since last update: `scripts/run_test_gates.sh`,
  `Test-Flight-Improv/test-gate-definitions.md`, `flutter devices --machine`,
  and device-selection references. Current command: none. Decision/blocker:
  the first `transport` failure is environment invocation only: the gate
  supports `FLUTTER_DEVICE_ID`, docs require it when multiple targets are
  attached, and no transport test file started. Next action: rerun the full
  required named gate, not a focused slice, because the failed command reached
  no slice to isolate; command is
  `FLUTTER_DEVICE_ID=5BA69F1C-B112-47BE-B1FF-8C1003728C8F ./scripts/run_test_gates.sh transport`.
- 2026-06-06 12:12:37 CEST - Phase: named gate failure triage started.
  Files inspected or touched since last update: named gate output for
  `./scripts/run_test_gates.sh groups` and `./scripts/run_test_gates.sh transport`.
  Commands finished: `./scripts/run_test_gates.sh groups` passed;
  `./scripts/run_test_gates.sh transport` failed before tests ran with Flutter
  device selection ambiguity after listing Android, iOS simulators, macOS, and
  Chrome devices. Failing file/test name: none reached. Log path: terminal
  output only. Current command: none. Decision/blocker:
  `pending_triage`. Exact focused triage command about to run:
  `sed -n '1,220p' scripts/run_test_gates.sh` to inspect the transport gate
  membership and device-selection behavior before deciding whether an
  environment-qualified host rerun is possible or the required gate remains
  blocked.
- 2026-06-06 12:10:48 CEST - Phase: required direct suites passed.
  Files inspected or touched since last update: required GFR-002 direct test
  suites. Commands finished and passed: `flutter test test/core/services/pending_message_retrier_test.dart`;
  `flutter test test/core/lifecycle/handle_app_resumed_group_recovery_test.dart`;
  `flutter test test/core/lifecycle/handle_app_resumed_group_inbox_retry_test.dart`;
  `flutter test test/core/lifecycle/handle_app_resumed_group_stuck_sending_test.dart`;
  `flutter test test/features/groups/application/send_group_message_use_case_test.dart`;
  `flutter test test/features/groups/application/retry_failed_group_messages_use_case_test.dart`;
  `flutter test test/features/groups/application/recover_stuck_sending_group_messages_use_case_test.dart`;
  `flutter test test/features/groups/domain/repositories/group_message_repository_impl_test.dart`.
  Current command: none. Decision/blocker: no direct-suite blocker. Next
  action: run required named gates `groups` and `transport`.
- 2026-06-06 12:08:42 CEST - Phase: focused GFR-002 verification passed.
  Files inspected or touched since last update: focused GFR-002 retrier,
  send-group, and retry-failed-group test surfaces. Commands finished:
  `flutter test test/core/services/pending_message_retrier_test.dart --plain-name "GFR-002"`
  passed; `flutter test test/features/groups/application/send_group_message_use_case_test.dart --plain-name "GFR-002"`
  passed; `flutter test test/features/groups/application/retry_failed_group_messages_use_case_test.dart --plain-name "GFR-002"`
  passed. Current command: none. Decision/blocker: no focused regression
  blocker; formatting was run across touched Dart files and changed nothing.
  Next action: run the full required direct suites, then named gates.
- 2026-06-06 12:05:59 CEST - Phase: local verification/QA recovery started.
  Files inspected or touched since last update: GFR-002 plan, Report 108
  breakdown GFR-002 entry, execution-QA orchestrator skill, scoped diffs for
  `PendingMessageRetrier`, group send/retry/repository surfaces, and current
  `git status`. Current command: none. Decision/blocker: using the allowed
  local sequential fallback for verification/QA after the prior child
  `spawn_or_tool_failure`; no full Executor relaunch unless QA finds a blocking
  issue. Next action: finish scoped QA inspection, run required direct suites
  and named gates, run `graphify update .`, run `git diff --check`, then write
  the final execution verdict or exact blocker.
- 2026-06-06 12:04:42 CEST - Phase: execution-QA child final-result failure
  recovered. Files inspected or touched since last update: GFR-002 plan,
  process list, scoped diffs, and focused test evidence already recorded at
  12:02:24. Current command: none. Decision/blocker: second execution-QA child
  `019e9c59-5fd0-7e83-b738-fe8a2d35ceb6` and nested Executor
  `019e9c5b-0d6e-76f0-9ac2-5379080f7e87` landed coherent GFR-002 code/tests
  and focused passing evidence, but did not return a trustworthy final result
  after its final bounded wait; parent terminated only PIDs `41878` and
  `41879`. Blocker class for that child is `spawn_or_tool_failure`, not a
  product blocker. Next action: launch a fresh isolated verification/QA
  recovery context against the landed delta, with no GFR-003 scope.
- 2026-06-06 12:00:10 CEST - Phase: bounded wait extended after real
  Executor progress. Files inspected or touched since last update: GFR-002
  plan execution progress, `git status`, diff stat/scoped diff for
  `lib/core/services/pending_message_retrier.dart`,
  `test/core/services/pending_message_retrier_test.dart`,
  `test/features/groups/application/send_group_message_use_case_test.dart`,
  and
  `test/features/groups/application/retry_failed_group_messages_use_case_test.dart`.
  Current command: waiting once more on Executor agent
  `019e9c5b-0d6e-76f0-9ac2-5379080f7e87`. Decision/blocker: first bounded
  wait timed out, but plan progress and diffs show real assigned-step progress:
  focused RED evidence captured, readiness handling patched, and missing
  GFR-002 application tests added. Next action: one final bounded wait for
  Executor completion evidence; if no trustworthy final result returns, close
  the child and use the local sequential fallback.
- 2026-06-06 11:55:36 CEST - Phase: isolated Executor resumed intake.
  Files inspected or touched since last update: GFR-002 plan remaining gates and
  scope guard, Report 108 breakdown/source context, graphify skill instructions,
  `graphify query "GFR-002 PendingMessageRetrier relayReady usabilityReady sendCapabilityReady GroupRecoveryGate retryFailedGroupMessages auto recovery readiness flapping" --budget 1800`,
  current `git status`, `lib/core/services/pending_message_retrier.dart`,
  `lib/features/p2p/domain/models/node_state.dart`, and partial
  `test/core/services/pending_message_retrier_test.dart` GFR-002 tests. Current
  command: none. Decision/blocker: continuing GFR-002 only from the current
  dirty worktree; unrelated dirty docs/untracked graphify-agent files are
  preserved. Existing partial RED tests target readiness return, readiness
  flapping, external recovery suppression, and `enableResumeGroupRecovery`
  disabled behavior. Next action: run the focused GFR-002 commands to capture
  current RED evidence before production edits.
- 2026-06-06 11:56:37 CEST - Phase: focused RED evidence captured. Files
  inspected or touched since last update:
  `test/core/services/pending_message_retrier_test.dart`,
  `test/features/groups/application/send_group_message_use_case_test.dart`, and
  `test/features/groups/application/retry_failed_group_messages_use_case_test.dart`.
  Commands finished:
  `flutter test test/core/services/pending_message_retrier_test.dart --plain-name "GFR-002"`
  failed; `GFR-002 readiness return runs queued group retry once` showed the
  not-yet-send-ready relay-visible cold-start still ran the full group chain
  before readiness returned. The two application focused commands both exited
  79 with `No tests match "GFR-002"`. Decision/blocker: no blocker; the retrier
  RED is valid and the missing application GFR-002 labels must be added rather
  than treating GFR-001 tests as focused GFR-002 evidence. Next action: patch
  `PendingMessageRetrier` readiness handling and add the missing GFR-002
  send/retry focused tests within the plan scope.
- 2026-06-06 12:02:24 CEST - Phase: focused GFR-002 implementation passing.
  Files inspected or touched since last update:
  `lib/core/services/pending_message_retrier.dart`,
  `lib/features/groups/application/retry_failed_group_messages_use_case.dart`,
  `lib/features/groups/domain/repositories/group_message_repository.dart`,
  `lib/features/groups/domain/repositories/group_message_repository_impl.dart`,
  `lib/core/database/helpers/group_messages_db_helpers.dart`, `lib/main.dart`,
  `test/shared/fakes/in_memory_group_message_repository.dart`,
  `test/core/services/pending_message_retrier_test.dart`,
  `test/features/groups/application/send_group_message_use_case_test.dart`,
  `test/features/groups/application/retry_failed_group_messages_use_case_test.dart`,
  and
  `test/features/groups/domain/repositories/group_message_repository_impl_test.dart`.
  Commands finished:
  `flutter test test/core/services/pending_message_retrier_test.dart --plain-name "GFR-002"`
  passed;
  `flutter test test/features/groups/application/send_group_message_use_case_test.dart --plain-name "GFR-002"`
  passed;
  `flutter test test/features/groups/application/retry_failed_group_messages_use_case_test.dart --plain-name "GFR-002"`
  passed. Decision/blocker: no focused blocker; readiness-gated group recovery,
  feature-flag disablement, no-transport same-row persistence, and bulk pending
  retry evidence now pass. Next action: format touched Dart files and run the
  required direct suites/gates.
- 2026-06-06 11:54:37 CEST - Phase: Executor spawned/running.
  Files inspected or touched since last update: GFR-002 plan execution progress
  only. Current command: spawned Executor agent
  `019e9c5b-0d6e-76f0-9ac2-5379080f7e87`. Decision/blocker: spawn succeeded;
  model/reasoning request was included in the child prompt because this spawn
  API exposes no explicit model fields. Next action: bounded wait for Executor
  code/test/gate evidence, then inspect assigned files and plan progress before
  any extension or local fallback decision.
- 2026-06-06 11:54:03 CEST - Phase: resumed execution-QA contract extracted.
  Files inspected or touched since last update: GFR-002 plan, Report 108
  breakdown/source doc, `test/core/services/pending_message_retrier_test.dart`,
  `lib/core/services/pending_message_retrier.dart`,
  `lib/features/p2p/domain/models/node_state.dart`, current `git status`, and
  `graphify query "GFR-002 pending message retrier group failed retry duplicate
  send UX pending_message_retrier_test"`. Current command: none.
  Decision/blocker: continuing GFR-002 only from partial RED tests; no replan
  and no GFR-003 scope. Current child-spawn API exposes no explicit
  model/reasoning fields, so the requested `gpt-5.5`/`xhigh` requirement will
  be included in spawned child prompts. Next action: spawn a fresh isolated
  Executor to complete RED-first GFR-002 tests, implementation, focused direct
  tests, named gates, `git diff --check`, and `graphify update .`.
- 2026-06-06 11:52:20 CEST - Phase: partial Executor handoff recovered.
  Files inspected or touched since last update: GFR-002 plan, process list,
  `git status`, recent file mtimes, and diff for
  `test/core/services/pending_message_retrier_test.dart`. Current command:
  none. Decision/blocker: first execution-QA child was terminated by the parent
  after quiet polling, but inspection showed it had made partial assigned-step
  progress at 11:50:43 by adding focused GFR-002 RED tests; no GFR-002 child
  process remains. This is an interrupted child handoff, not a product blocker.
  Next action: launch a fresh isolated execution/QA context to continue from
  the partial RED tests and complete implementation plus QA.
- 2026-06-06 11:50:43 CEST - Phase: adding focused RED tests. Files inspected
  or touched since last update: `lib/core/services/pending_message_retrier.dart`,
  `lib/features/p2p/domain/models/node_state.dart`,
  `lib/features/groups/application/retry_failed_group_messages_use_case.dart`,
  `lib/features/groups/application/send_group_message_use_case.dart`,
  `test/core/services/pending_message_retrier_test.dart`,
  `test/features/groups/application/send_group_message_use_case_test.dart`,
  `test/features/groups/application/retry_failed_group_messages_use_case_test.dart`,
  group message repository fake/interface/impl query points, and graphify query
  result. Current command: none. Decision/blocker: existing GFR-001 tests cover
  targeted same-row retry, but bulk auto retry does not yet load pending
  in-doubt rows and retrier readiness still keys on legacy circuit-online state;
  adding focused GFR-002 tests before production edits. Next action: patch RED
  tests and run the three required `--plain-name "GFR-002"` commands.
- 2026-06-06 11:46:53 CEST - Phase: isolated Executor intake/contract refresh.
  Files inspected or touched since last update: GFR-002 plan, Report 108
  breakdown GFR-002 entry, source doc, execution-QA orchestrator skill, current
  `git status`, and `graphify-out/graph.json` existence. Current command:
  `graphify query "GFR-002 PendingMessageRetrier relayReady usabilityReady sendCapabilityReady GroupRecoveryGate retryFailedGroupMessages auto recovery readiness flapping" --budget 1800`.
  Decision/blocker: executing only GFR-002 as isolated Executor; no replanning;
  runtime cannot independently verify requested model/reasoning fields from
  inside this agent. Next action: inspect retrier/send/retry tests and add
  focused RED GFR-002 tests before production changes.
- 2026-06-06 11:46:19 CEST - Phase: Executor spawned/running. Files inspected
  or touched since last update: GFR-002 plan execution progress only. Current
  command: spawned Executor agent `019e9c53-7284-7610-af6a-6f3516143f76`.
  Decision/blocker: spawn succeeded; model/reasoning request was included in
  the child prompt because this spawn API exposes no explicit model fields.
  Next action: wait for Executor code/test/gate evidence.
- 2026-06-06 11:45:36 CEST - Phase: contract extracted. Files inspected or
  touched since last update: GFR-002 plan, Report 108 breakdown GFR-002 row,
  source doc, execution-QA orchestrator skill, `graphify-out/graph.json` via
  `graphify query`. Current command: none. Decision/blocker: exact scope is
  `PendingMessageRetrier` readiness-driven group auto recovery, GFR-001
  same-row send/retry preservation, explicit `enableResumeGroupRecovery`
  behavior, direct tests/gates from this plan, no GFR-003 UI/composer work.
  Next action: spawn isolated Executor for RED-first tests and implementation.
- 2026-06-06 11:43:45 CEST - Phase: execution launch. Files inspected or
  touched since last update: GFR-002 execution-ready plan and execution-QA
  orchestrator instructions. Current command: pending fresh Executor spawn.
  Decision/blocker: no execution blocker known; contract is execution-safe.
  Next action: spawn isolated GFR-002 Executor with model `gpt-5.5` and
  reasoning effort `xhigh`.

## scope guard

Do not implement:

- group conversation widget/composer clearing/restoration or visible Retry UI
- manual Retry button in-progress state or rapid tap presentation
- a new background recovery service separate from `PendingMessageRetrier`
- DB schema migrations or unique logical-delivery constraints
- relay/go protocol changes, bridge command changes, or membership/key repair
- notification routing, push fallback, or read receipt semantics
- final Report 108 source/stable matrix reconciliation

Overengineering signals:

- introducing a new queue table for rows that already exist in
  `group_messages`
- adding another timer/scheduler when `_debounceTimer`, periodic timers, and
  in-flight guards already exist
- sending synthetic local events outside repository writes just to satisfy UI
  tests
- changing 1:1 retry behavior to solve a group-only GFR-002 issue

## accepted differences / intentionally out of scope

- The source doc's visible "composer is left empty" acceptance bullet is not
  implemented in GFR-002. The breakdown assigns open-conversation composer and
  Retry presentation work to GFR-003. GFR-002 only ensures the persisted
  application/retry contract required for that UI.
- Full recipient-visible duplicate proof is not claimed from host tests alone.
  GFR-002 includes exact simulator commands, but GFR-004 remains the acceptance
  owner if those commands are not run during GFR-002.
- Failed media retry/delete UX remains separate. GFR-002 is text retry
  orchestration unless execution proves a shared status transition needs a
  preservation test.
- Reaction replay retry ownership remains in
  `retryFailedGroupInboxStores(...)`; GFR-002 must not absorb it into failed
  message retry.

## dependency impact

- GFR-003 depends on GFR-002 to provide one persisted queued/retrying row and a
  coalesced recovery owner that UI controls can observe without creating a fresh
  send attempt.
- GFR-004 depends on GFR-002 for direct evidence before running whole-journey
  lifecycle, simulator, and gate acceptance.
- GFR-005 depends on GFR-004 for final stable doc reconciliation and final
  program verdict.
- If GFR-002 changes the feature-flag decision, GFR-003 and GFR-004 must use
  the same flag behavior in UI and acceptance tests.

## sufficiency review

Verdict: sufficient with explicit simulator acceptance handling.

Reviewer findings:

- Required simulator-backed closure was initially missing; fixed by naming the
  `run-flutter-reliability-sims` group list and two exact
  `path:scenario` commands.
- Composer clearing was a scope ambiguity; fixed by recording it as a GFR-003
  accepted difference.
- The readiness predicate could break legacy circuit-address tests if made too
  strict; fixed by requiring RED tests and preserving existing cold-start
  behavior unless explicit readiness evidence is present.
- Repository local-event behavior is already covered; new repository tests are
  conditional on new bulk transitions.

## arbiter decision

Structural blockers: none remaining.

Incremental details deferred:

- exact helper names inside `PendingMessageRetrier`
- whether the final readiness helper keys on `usabilityReady` alone or
  `relayReady && usabilityReady` with legacy fallback
- whether simulator commands run in GFR-002 or are recorded for GFR-004

Accepted differences:

- visual composer clearing and Retry button state are GFR-003
- final cross-device recipient-visible acceptance may be GFR-004
- no DB migration or relay protocol change is planned

## Final Execution Verdict

Final verdict: `accepted_with_explicit_follow_up`

Spawned-agent isolation used:

- Earlier spawned execution-QA/Executor children produced the landed GFR-002
  code/test delta and focused passing evidence, but the last child failed to
  return a trustworthy final result.
- This recovery used the skill's local sequential fallback in this fresh
  isolated execution-QA context for verification and QA only.
- No full Executor was relaunched because QA found no blocking product issue.

Files changed for GFR-002 verification scope:

- `lib/core/services/pending_message_retrier.dart`
- `lib/core/database/helpers/group_messages_db_helpers.dart`
- `lib/features/groups/application/retry_failed_group_messages_use_case.dart`
- `lib/features/groups/application/send_group_message_use_case.dart`
- `lib/features/groups/domain/repositories/group_message_repository.dart`
- `lib/features/groups/domain/repositories/group_message_repository_impl.dart`
- `lib/main.dart`
- `test/core/services/pending_message_retrier_test.dart`
- `test/features/groups/application/send_group_message_use_case_test.dart`
- `test/features/groups/application/retry_failed_group_messages_use_case_test.dart`
- `test/features/groups/domain/repositories/group_message_repository_impl_test.dart`
- `test/shared/fakes/in_memory_group_message_repository.dart`
- `graphify-out/graph.json` and `graphify-out/GRAPH_REPORT.md` via
  `graphify update .`
- this plan file for execution evidence and final verdict

Tests added or updated:

- Focused GFR-002 retrier tests for readiness return, readiness flapping,
  external recovery suppression, and `enableResumeGroupRecovery: false`.
- Focused GFR-002 send/retry/repository tests for one retryable no-transport
  row, pending in-doubt bulk retry, and failed/pending retryable loading.
- Related GFR-001 identity/coalescing tests already landed in the same delta
  and were preserved as prerequisite evidence.

Exact tests and gates run:

- `flutter test test/core/services/pending_message_retrier_test.dart --plain-name "GFR-002"` - passed
- `flutter test test/features/groups/application/send_group_message_use_case_test.dart --plain-name "GFR-002"` - passed
- `flutter test test/features/groups/application/retry_failed_group_messages_use_case_test.dart --plain-name "GFR-002"` - passed
- `flutter test test/core/services/pending_message_retrier_test.dart` - passed
- `flutter test test/core/lifecycle/handle_app_resumed_group_recovery_test.dart` - passed
- `flutter test test/core/lifecycle/handle_app_resumed_group_inbox_retry_test.dart` - passed
- `flutter test test/core/lifecycle/handle_app_resumed_group_stuck_sending_test.dart` - passed
- `flutter test test/features/groups/application/send_group_message_use_case_test.dart` - passed
- `flutter test test/features/groups/application/retry_failed_group_messages_use_case_test.dart` - passed
- `flutter test test/features/groups/application/recover_stuck_sending_group_messages_use_case_test.dart` - passed
- `flutter test test/features/groups/domain/repositories/group_message_repository_impl_test.dart` - passed
- `./scripts/run_test_gates.sh groups` - passed
- `./scripts/run_test_gates.sh transport` - first invocation failed before any
  test file ran because multiple Flutter targets were attached and no device
  was selected; triaged as environment invocation, not product failure.
- `FLUTTER_DEVICE_ID=5BA69F1C-B112-47BE-B1FF-8C1003728C8F ./scripts/run_test_gates.sh transport` - passed
- `dart format` on touched Dart files - completed, 0 files changed
- `graphify update .` - completed
- `git diff --check` - passed

QA review:

- Scope adherence: passes. The delta stays in retrier/readiness, send/retry,
  repository, wiring, tests, graph, and plan evidence. No GFR-003 composer,
  Retry UI, DB migration, relay/go protocol, notification, or membership/key
  repair work was added.
- Behavior correctness: passes. Readiness-return group recovery now waits for
  explicit `relayReady && usabilityReady` when readiness evidence exists, keeps
  legacy circuit-address behavior when it does not, coalesces flapping through
  the existing scheduler/in-flight guards, and respects external recovery and
  `enableResumeGroupRecovery`.
- Test sufficiency: passes for GFR-002 host/direct/named-gate scope.
- Gate sufficiency: passes after rerunning `transport` with the documented
  `FLUTTER_DEVICE_ID` selector.
- Diff hygiene: passes.

Blocking issues remaining: none.

Non-blocking follow-ups deferred:

- GFR-004 remains responsible for the Report 108 whole-journey simulator
  acceptance commands if they are not run before final program closure:
  `run_with_devices.sh group --only integration_test/scripts/run_group_multi_party_device_real.dart:private_relay_reconnect_group_recovery`
  and
  `run_with_devices.sh group --only integration_test/scripts/run_group_multi_party_device_real.dart:private_background_resume_group_delivery`.
- `info.plist` has a simulator/Xcode `LastAccessedDate` timestamp change from
  the explicit-device transport gate. It is not part of the GFR-002 product
  delta and was preserved.

Why the session is safe to consider complete:

GFR-002's required RED/focused tests, required direct suites, `groups` gate,
device-selected `transport` gate, graph update, and diff hygiene all passed.
The final unresolved proof is explicitly outside GFR-002's host/direct
acceptance bar and remains assigned to GFR-004 before whole Report 108 closure.

## Closure Audit

Closure audit completed: 2026-06-06 12:29 CEST

Closure verdict: `accepted_with_explicit_follow_up`

Audited evidence:

- The final execution verdict above was treated as starting evidence, then
  checked against the current repo diff for the GFR-002 retrier, send/retry,
  repository, fake, and focused test changes.
- `graphify query` scoped the relevant code relationships back to
  `GroupRecoveryGate`, `retryFailedGroupMessages`, and the group recovery
  reliability area before code relationship review.
- The landed code keeps GFR-002 inside the existing `PendingMessageRetrier`
  owner, adds explicit group readiness handling while preserving legacy
  circuit-address behavior, gates group recovery with
  `enableResumeGroupRecovery`, and keeps external recovery/in-flight coalescing
  intact.
- The retry repository path now loads retryable outgoing rows including
  in-doubt `pending` rows, and same-message targeted retry has a per-message
  in-flight guard.
- Focused tests exist for readiness return, readiness flapping, external
  recovery suppression, feature-flag disablement, no-usable-transport
  one-row persistence, bulk pending retry, and retryable outgoing row loading.
- The recorded verification evidence remains sufficient for this session:
  focused GFR-002 tests, required direct suites, `groups` gate,
  device-selected `transport` gate, `graphify update .`, and
  `git diff --check` all passed during execution/QA.
- Closure audit reran the focused GFR-002 verification after the audit docs
  were updated:
  `flutter test test/core/services/pending_message_retrier_test.dart --plain-name "GFR-002"`,
  `flutter test test/features/groups/application/send_group_message_use_case_test.dart --plain-name "GFR-002"`,
  `flutter test test/features/groups/application/retry_failed_group_messages_use_case_test.dart --plain-name "GFR-002"`,
  and `git diff --check`; all passed.

What is now closed for GFR-002:

- Automatic queued/failed/pending group text retry orchestration on send
  readiness return.
- Readiness flapping and relay-ready/app-resume overlap coalescing through the
  existing retrier guards.
- Explicit `enableResumeGroupRecovery` behavior for this auto group recovery
  path.
- Host/direct and named-gate evidence required by the GFR-002 plan.

Residual-only / explicit follow-up:

- GFR-004 still owns whole-journey group simulator acceptance:
  `run_with_devices.sh group --only integration_test/scripts/run_group_multi_party_device_real.dart:private_relay_reconnect_group_recovery`
  and
  `run_with_devices.sh group --only integration_test/scripts/run_group_multi_party_device_real.dart:private_background_resume_group_delivery`.
- GFR-003 still owns composer clearing/restoration and visible Retry/send-now
  presentation. This audit did not plan or execute GFR-003.

Still-open GFR-002 blockers: none.

Accepted differences:

- Full recipient-visible simulator proof remains outside this host/direct
  GFR-002 closure and is explicitly carried to GFR-004.
- Final stable Report 108 source and matrix reconciliation remains assigned to
  GFR-005.
- The simulator/Xcode `info.plist` `LastAccessedDate` change is generated
  workspace state from the explicit-device transport gate and is preserved.

Closure reference safety:

The GFR-002 plan plus the breakdown ledger now describe the landed scope,
tests/gates, accepted differences, and GFR-004 simulator follow-up without
claiming whole Report 108 closure or reopening product-scope work.
