# 108 - GFR-001 Stable Group Retry Attempt Contract Plan

Status: closed

Session id: `GFR-001`

Breakdown artifact:
`Test-Flight-Improv/108-group-failed-message-retry-duplicate-send-ux-session-breakdown.md`

Source doc:
`Test-Flight-Improv/108-group-failed-message-retry-duplicate-send-ux.md`

Planning fallback used: yes. The spawned planner created the file and initial
heartbeats but stopped updating this artifact while still running terminal-only
inspection. The parent pipeline terminated that child and completed this
bounded artifact-only plan from the execution-safe breakdown entry.

## Planning Progress

- 2026-06-06 11:36:21 CEST - Role: Parent pipeline progress heartbeat.
  Files inspected since last update: GFR-001 closed plan header and Report 108
  breakdown ledger row. Decision/blocker: GFR-001 reusable plan is finished and
  closed; no GFR-001 blocker. Current phase is GFR-002 planning in a fresh
  downstream context. Next action: finish reusable GFR-002 plan, then launch
  isolated GFR-002 execution/QA.
- 2026-06-06 11:16:04 CEST - Role: Parent pipeline progress heartbeat.
  Files inspected since last update: GFR-001 reusable plan status,
  breakdown artifact tail, and current execution progress. Decision/blocker:
  reusable plan remains complete with `Status: execution-ready`; no planning
  blocker. Current phase is local GFR-001 execution/QA fallback after spawned
  execution no-progress. Next action: add the receiver-side GFR-001 duplicate
  replay proof, run focused and direct suites sequentially, then record the
  execution verdict for closure.
- 2026-06-06 11:05:30 CEST - Role: Parent pipeline verification. Files
  inspected since last update: completed fallback plan file and breakdown
  ledger. Decision/blocker: reusable GFR-001 plan is persisted with
  `Status: execution-ready`; no planning blocker. Next action: record dirty
  worktree snapshot and launch isolated GFR-001 execution/QA.
- 2026-06-06 11:04:45 CEST - Role: Arbiter completed. Files inspected since
  last update: breakdown GFR-001 entry, source Report 108 current-state and
  acceptance sections, gate docs summary, owner code/test snippets gathered by
  the spawned planner, and scoped graphify query output. Decision/blocker: no
  structural blocker remains; plan is execution-ready via local fallback. Next
  action: run isolated execution/QA for GFR-001.
- 2026-06-06 11:03:55 CEST - Role: Reviewer completed. Files inspected since
  last update: fallback plan sections and GFR-001 scope guard. Decision/blocker:
  sufficient after keeping auto-readiness, presentation UX, simulator evidence,
  and final docs out of this session. Next action: Arbiter classifies findings.
- 2026-06-06 11:02:55 CEST - Role: Planner completed. Files inspected since
  last update: GFR-001 owner files/tests listed below. Decision/blocker: no
  blocker; draft covers stable attempt identity, failed/pending retry
  eligibility, same-row coalescing, receiver duplicate proof, media boundary,
  and reaction retry boundary. Next action: Reviewer sufficiency pass.
- 2026-06-06 11:01:55 CEST - Role: Evidence Collector completed. Files inspected
  since last update: `send_group_message_use_case.dart`,
  `retry_failed_group_messages_use_case.dart`, `handle_incoming_group_message_use_case.dart`,
  `group_message_repository.dart`, `group_message_repository_impl.dart`,
  `group_messages_db_helpers.dart`, and direct group application/repository test
  suites. Decision/blocker: current code has no row-scoped retry in-flight
  contract, retry only loads failed rows, pending rows already exist, logical
  delivery lookup is available, and direct tests are the right closure level.
  Next action: draft smallest implementation plan.
- 2026-06-06 11:00:15 CEST - Role: Evidence Collector in progress. Files
  inspected since last update: scoped graphify query output and source doc grep
  from `Test-Flight-Improv/108-group-failed-message-retry-duplicate-send-ux.md`.
  Decision/blocker: graph output is broad but confirms group retry/reaction
  replay seams; no blocker. Next action: inspect gate contract and likely owner
  code/tests for GFR-001 only.

## Dirty Worktree Snapshot

Captured before GFR-001 execution at 2026-06-06 11:05:45 CEST:

```text
 M Test-Flight-Improv/Group-Chat-Feature/Improvement-Review-2026-06/02-P0-undecryptable-messages-self-heal.md
 M Test-Flight-Improv/Group-Chat-Feature/Improvement-Review-2026-06/03-P0-removal-rotation-fails-closed.md
 M Test-Flight-Improv/Group-Chat-Feature/Improvement-Review-2026-06/04-P0-notifications-respect-settings-and-membership.md
 M Test-Flight-Improv/Group-Chat-Feature/Improvement-Review-2026-06/05-P1-recovery-orchestration-hardening.md
 M Test-Flight-Improv/Group-Chat-Feature/Improvement-Review-2026-06/06-P1-relay-inbox-catchup-integrity.md
 M Test-Flight-Improv/Group-Chat-Feature/Improvement-Review-2026-06/07-P1-membership-convergence-consistency.md
 M Test-Flight-Improv/Group-Chat-Feature/Improvement-Review-2026-06/08-P1-invite-join-reliability.md
 M Test-Flight-Improv/Group-Chat-Feature/Improvement-Review-2026-06/09-P1-media-bounded-and-honest.md
 M Test-Flight-Improv/Group-Chat-Feature/Improvement-Review-2026-06/10-P2-reaction-reliability.md
 M Test-Flight-Improv/Group-Chat-Feature/Improvement-Review-2026-06/11-P2-in-conversation-feedback-and-i18n-polish.md
?? .agents/
?? .claude/CLAUDE.md
?? .claude/settings.json
?? .claude/skills/graphify/
?? .codex/
?? AGENTS.md
?? CLAUDE.md
?? Test-Flight-Improv/108-group-failed-message-retry-duplicate-send-ux-session-GFR-001-plan.md
?? Test-Flight-Improv/108-group-failed-message-retry-duplicate-send-ux-session-breakdown.md
?? Test-Flight-Improv/108-group-failed-message-retry-duplicate-send-ux.md
?? graphify-out/
```

## real scope

GFR-001 owns the application/repository contract that one outgoing group text
attempt keeps one stable message id and logical delivery identity across
`failed`, retrying, `pending`/in-doubt, `sent`, and already-settled states.

Production scope is limited to these surfaces:

- same-row manual retry idempotency in
  `retry_failed_group_messages_use_case.dart`, including rapid repeated calls
  for the same row and overlap with another same-attempt recovery path
- retry eligibility for in-doubt outgoing text rows that are currently
  `pending` and still have retry payload or wire-envelope evidence
- send-path same-attempt reuse in `send_group_message_use_case.dart` when the
  caller supplies the original message id/logical delivery id/timestamp for a
  retryable row
- repository/helper lookup support only if needed to load retryable failed or
  pending outgoing rows in deterministic order
- receiver/self-echo duplicate proof in
  `handle_incoming_group_message_use_case.dart` tests, using current message id
  and logical delivery id semantics
- preservation tests for failed media retry/delete boundaries and
  `retryFailedGroupInboxStores(...)` message-first/reaction-replay ownership

This session must not implement relay-ready drains, app-level node-state
listeners, open-conversation composer changes, widget/UI affordance changes,
multi-device simulator proof, or final stable closure/matrix doc rewriting.

## closure bar

GFR-001 is good enough when all of the following are true:

- calling failed-row retry repeatedly for the same eligible group text row starts
  at most one underlying resend at a time and leaves one sender-visible row
- a retryable in-doubt `pending` group text row can enter the same stable retry
  path instead of being stranded outside manual/application recovery
- same-attempt retry preserves original `messageId`, `logicalDeliveryId`,
  timestamp, quote context, text, sender identity, wire envelope, and inbox retry
  payload as applicable
- if the same attempt has already settled to `sent` or `delivered`, another
  retry call becomes a no-op or returns the settled row without creating a new
  outgoing row
- distinct intentional same-text messages after settlement remain representable
  when they use new ids/timestamps
- receiver-side handling still dedupes same-id/logical-delivery replay and the
  prior fresh-id/fresh-timestamp duplicate path is no longer reachable through
  this session's same-attempt retry path
- failed media behavior is not absorbed into text retry idempotency, and
  `retryFailedGroupInboxStores(...)` still owns message inbox-store retry before
  reaction replay capacity
- direct TDD evidence is added/updated first for the GFR-001 regressions, the
  direct suites pass, and `./scripts/run_test_gates.sh groups` is run if any
  production group send/retry/repository/receive behavior changes

No simulator or device proof is required for GFR-001. Cross-seam lifecycle and
multi-user proof belongs to GFR-004 after GFR-001 through GFR-003 land.

## source of truth

- Current code and direct tests win over stale prose.
- Active session contract:
  `Test-Flight-Improv/108-group-failed-message-retry-duplicate-send-ux-session-breakdown.md`,
  session `GFR-001`.
- Product source:
  `Test-Flight-Improv/108-group-failed-message-retry-duplicate-send-ux.md`.
- Regression contract:
  `Test-Flight-Improv/14-regression-test-strategy.md`.
- Named gate source:
  `Test-Flight-Improv/test-gate-definitions.md`.
- Final closure/matrix docs are not updated in this session except the
  breakdown ledger during closure.

## session classification

`implementation-ready`

## exact problem statement

Report 108 identifies a group text duplicate-send trust bug. The current retry
path targets one failed outgoing row by id and re-enters `sendGroupMessage(...)`
with the original row's identity, but it lacks a row-scoped in-flight/idempotent
contract. Repeated retry calls for the same failed row, or same-attempt overlap
with another recovery path, can start independent work while the UI still
presents one user intent.

The current retry loader only targets `failed` rows. The send path can mark a
bridge-timeout in-doubt row as `pending`; those rows keep retry evidence but are
outside manual failed-message retry. Separately, receiver dedupe protects same
message id/logical delivery id replay, but a fresh composer send with a new id
and timestamp can bypass content fallback. GFR-001 must make the lower-layer
same-attempt retry path stable before later auto-recovery and UI sessions call
it.

Must stay unchanged: media retry/delete UX, 1:1 retry behavior, group wire
protocol/relay semantics, DB uniqueness policy for logical delivery id,
membership/key repair, app-resume ordering, and reaction replay semantics.

## files and repos to inspect next

Production files:

- `lib/features/groups/application/send_group_message_use_case.dart`
- `lib/features/groups/application/retry_failed_group_messages_use_case.dart`
- `lib/features/groups/application/retry_failed_group_inbox_stores_use_case.dart`
- `lib/features/groups/application/handle_incoming_group_message_use_case.dart`
- `lib/features/groups/domain/models/group_message.dart`
- `lib/features/groups/domain/repositories/group_message_repository.dart`
- `lib/features/groups/domain/repositories/group_message_repository_impl.dart`
- `lib/core/database/helpers/group_messages_db_helpers.dart`

Direct tests:

- `test/features/groups/application/send_group_message_use_case_test.dart`
- `test/features/groups/application/retry_failed_group_messages_use_case_test.dart`
- `test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart`
- `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`
- `test/features/groups/domain/repositories/group_message_repository_impl_test.dart`
- shared fakes used by those tests, especially
  `test/shared/fakes/in_memory_group_message_repository.dart`

## existing tests covering this area

- `send_group_message_use_case_test.dart` already covers pre-persisted outgoing
  rows, logical delivery id behavior, reliable-send timeout/in-doubt handling,
  failed publish restoration, no-custody failed rows, and inbox retry payloads.
- `retry_failed_group_messages_use_case_test.dart` already covers retrying
  failed rows, preserving ids/timestamps/quote/media metadata, and retry
  interaction with group send.
- `retry_failed_group_inbox_stores_use_case_test.dart` already covers sent and
  pending message inbox-store retry, same pending id once, retry state clearing,
  and reaction replay capacity ownership.
- `handle_incoming_group_message_use_case_test.dart` already covers same-id
  self-echo reconciliation for pending outbound rows, failed outgoing self replay
  repair, duplicate message id behavior, and logical delivery dedupe.
- `group_message_repository_impl_test.dart` already covers logical delivery
  lookup, failed outgoing loads, outgoing status events, rows-changed events,
  and status updates.

Missing GFR-001 evidence:

- rapid repeated retry of the same row coalesces into one resend/outcome
- retry eligibility includes in-doubt `pending` outgoing text rows without
  sweeping unrelated sent/inbox-store-only rows
- retrying an already-settled same-attempt row is idempotent/no-op rather than a
  fresh send
- send/retry reuse includes `pending` rows when the same message id/logical
  delivery id/timestamp is supplied
- distinct post-settlement same-text sends remain possible
- receiver duplicate tests prove same-id/logical-delivery replay remains caught
  while the fresh-id/fresh-timestamp path is avoided by same-attempt retry

## regression/tests to add first

Add focused RED tests before production changes:

1. In `retry_failed_group_messages_use_case_test.dart`, add a test for two
   concurrent or rapid `retryFailedGroupMessage(...)` calls against the same
   failed text row. Use a fake bridge that delays `group:publish` so both calls
   overlap. Assert one publish for the row id, one row in the repository, and a
   stable final status/payload.
2. In `retry_failed_group_messages_use_case_test.dart`, add a test that a
   `pending` outgoing text row with retry payload or wire envelope is eligible
   for the same retry path and reuses the original message id,
   `logicalDeliveryId`, timestamp, quote, and text.
3. In `send_group_message_use_case_test.dart`, add or update a same-attempt
   reuse test proving a retry call with the original id/logical delivery
   identity can reuse an existing `pending` row and does not create a second row.
4. In `send_group_message_use_case_test.dart` or
   `retry_failed_group_messages_use_case_test.dart`, add a distinct
   post-settlement same-text test: after the original attempt is `sent` or
   delivered, a new explicit send with a new id/timestamp remains a distinct
   intentional message.
5. In `handle_incoming_group_message_use_case_test.dart`, add or tighten a
   logical delivery replay proof that same-id/logical-delivery receiver replay
   is still suppressed/reconciled while same-attempt retry preserves the
   identity needed for that suppression.
6. In `retry_failed_group_inbox_stores_use_case_test.dart`, add a guard if
   needed showing the GFR-001 retry changes do not consume reaction replay rows
   or change message-first capacity behavior.
7. In `group_message_repository_impl_test.dart` and the in-memory fake tests as
   needed, add repository coverage for loading retryable outgoing rows if a new
   API replaces `getFailedOutgoingMessages()` with failed-or-pending semantics.

If an existing test already covers an item exactly after inspection, keep it and
record it as existing proof in execution notes instead of duplicating it.

## step-by-step implementation plan

1. Extract the current retry/send contracts in the execution notes before
   coding: current loader status filter, retry payload reconstruction,
   `sendGroupMessage(...)` row reuse status filter, logical delivery lookup, and
   status event behavior.
2. Add the focused RED tests above, starting with same-row concurrent retry and
   pending-row eligibility.
3. Add the narrow repository contract needed by the tests:
   - preferred: introduce a `getRetryableOutgoingMessages()` or targeted
     `getRetryableOutgoingMessage(id)` API that includes outgoing `failed` and
     retryable `pending` text rows while preserving `getFailedOutgoingMessages()`
     for existing callers, or
   - accepted: extend retry use-case targeted lookup to allow `pending` for the
     specific requested id while keeping batch failed retry semantics unchanged.
4. Add a row-scoped in-flight coalescer in
   `retry_failed_group_messages_use_case.dart`, keyed by message id. Concurrent
   calls for the same row should share the same future/result. Calls for
   different rows must still run independently.
5. Update retry eligibility so text rows in `failed` or retryable `pending`
   state with retry evidence can re-enter `sendGroupMessage(...)` with the
   original message id, logical delivery id, timestamp, quote, sender, and
   media context. Do not include sent/delivered rows in batch retry.
6. Update `sendGroupMessage(...)` row reuse to treat an existing outgoing
   `pending` row as same-attempt reusable when the supplied message id/sender
   text/quote/timestamp/logical delivery identity match. The reuse must not make
   a fresh same-text send after settlement collapse into the old row.
7. Preserve existing receiver dedupe and self-echo reconciliation. If tests show
   logical delivery id handling needs a small guard, keep it in
   `handle_incoming_group_message_use_case.dart` and do not introduce a DB
   uniqueness migration.
8. Preserve failed media behavior. If retry eligibility changes could include
   media rows, keep existing media-specific retry/delete behavior intact and add
   a direct preservation assertion.
9. Preserve `retryFailedGroupInboxStores(...)` behavior. Do not make GFR-001
   text retry consume reaction replay capacity or alter inbox-store retry order.
10. Run the exact direct tests listed below. Fix only failures caused by this
    session.
11. Run `./scripts/run_test_gates.sh groups` if production group send, retry,
    repository, receive, or inbox-store behavior changed.
12. Run `git diff --check` and format only touched Dart files.

Stop and return `blocked` instead of broadening scope if implementation requires
relay/node readiness listeners, lifecycle order changes, UI composer changes,
database uniqueness migrations, or wire-protocol/relay changes.

## risks and edge cases

- A global retry coalescer could suppress independent messages; key only by
  message id and keep different rows independent.
- A `pending` row with no retry evidence may represent inbox-store ownership,
  not a publish retry; do not sweep it into failed-message retry blindly.
- Same-text duplicate protection must not erase distinct intentional messages
  created after settlement with new ids/timestamps.
- Logical delivery id lookup is nullable and non-unique by design; do not add a
  uniqueness migration.
- `sendGroupMessage(...)` status reuse must not resurrect deleted/local tombstone
  rows or system removal cutoff rows.
- Media rows have separate retry/delete controls; text retry idempotency must
  not redesign media UX.
- Reaction replay rows share the inbox-store retry pass; text retry must not
  count or mutate them as group message rows.
- Existing local outgoing status events should remain accurate when rows move
  `failed`/`pending` -> retrying/sending -> `sent` or back to `failed`.

## exact tests and gates to run

Run focused regressions first:

```bash
flutter test test/features/groups/application/retry_failed_group_messages_use_case_test.dart --plain-name "GFR-001"
flutter test test/features/groups/application/send_group_message_use_case_test.dart --plain-name "GFR-001"
flutter test test/features/groups/application/handle_incoming_group_message_use_case_test.dart --plain-name "GFR-001"
```

Then run required direct suites:

```bash
flutter test test/features/groups/application/retry_failed_group_messages_use_case_test.dart
flutter test test/features/groups/application/send_group_message_use_case_test.dart
flutter test test/features/groups/application/handle_incoming_group_message_use_case_test.dart
flutter test test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart
flutter test test/features/groups/domain/repositories/group_message_repository_impl_test.dart
```

Run formatting/diff hygiene for touched Dart files:

```bash
dart format <touched dart files>
git diff --check
```

Named gate:

```bash
./scripts/run_test_gates.sh groups
```

`groups` is mandatory when production group send, retry, repository, receive, or
inbox-store behavior changes. `transport` is not required unless the
implementation expands into bridge lifecycle, transport readiness ordering, or
node-state wiring, which this plan marks out of scope.

## known-failure interpretation

Direct tests listed above are required evidence. Any failure in those direct
suites is blocking unless it is proven pre-existing and unrelated to the touched
files before this session changes behavior.

For `./scripts/run_test_gates.sh groups`, use
`Test-Flight-Improv/test-gate-definitions.md` as the source of truth. If the
gate has a documented pre-existing carried failure, preserve the exact failing
test name/assertion in execution notes and classify it as known only when the
touched GFR-001 files could not have caused or widened it. Any new or changed
groups-gate failure is blocking.

If `transport` becomes necessary because execution expands into readiness or
bridge lifecycle, stop and replan; that belongs to GFR-002, not GFR-001.

## done criteria

- The retry/send application layer has a stable same-attempt contract for
  failed and retryable pending group text rows.
- Same-row rapid/concurrent retry coalesces into one resend and one sender row.
- Pending in-doubt text attempts are eligible for the same stable retry path
  when retry evidence exists.
- Existing same-id/logical-delivery receiver dedupe and self-echo reconciliation
  still pass.
- Distinct intentional same-text messages after settlement still pass.
- Failed media behavior and `retryFailedGroupInboxStores(...)` message/reaction
  ownership still pass.
- Required direct suites pass, `groups` gate is run if production behavior
  changes, and any known failure interpretation is recorded exactly.
- No GFR-002 readiness owner, GFR-003 UI composer behavior, GFR-004
  integration/simulator proof, or GFR-005 final stable docs are changed in this
  session.

## scope guard

Do not change:

- relay-side or wire-protocol dedupe
- database uniqueness for logical delivery id
- app lifecycle ordering, relay-ready listeners, node-state wiring, or feature
  flags
- group conversation composer restoration, retry button visual state, widget
  copy/icons, or failed media controls
- group membership, invite, key repair, notification routing, or reaction replay
  semantics
- 1:1 failed-message retry behavior
- final source, matrix, gate-definition, or closure-reference docs beyond
  closure notes requested by the outer pipeline

If any of those are required to make a test pass, record an implementation-owned
or prerequisite-owned blocker for the pipeline instead of broadening GFR-001.

## accepted differences / intentionally out of scope

- No relay-side duplicate suppression is planned.
- No DB uniqueness mandate for `logical_delivery_id` is planned.
- No automatic relay-ready queued-send owner is planned in GFR-001; that belongs
  to GFR-002.
- No open conversation composer/retry affordance change is planned in GFR-001;
  that belongs to GFR-003.
- No simulator or multi-device closure is required in GFR-001; that belongs to
  GFR-004.
- No final Report 108 stable closure/matrix reconciliation is planned in
  GFR-001; that belongs to GFR-005.

## dependency impact

GFR-002 and GFR-003 depend on this session. They may proceed only after GFR-001
has an accepted execution/closure result or a truthful blocker classification.

If GFR-001 changes the same-attempt API shape, GFR-002 must call that API for
queued/relay-ready drains and GFR-003 must call it for open conversation retry
or send-now nudges. If GFR-001 blocks on a prerequisite-owned gap, dependent
sessions should be marked `skipped_due_to_dependency` until the blocker is
resolved.

## Reviewer Findings

- Sufficiency: sufficient as a GFR-001 execution contract.
- Missing files/tests/gates: none structural; execution may add a repository
  helper test only if it introduces a helper/API for retryable outgoing rows.
- Stale assumptions: none identified; current code snippets confirm failed-only
  retry loading, pending in-doubt rows, and logical delivery lookup support.
- Overengineering: avoid schema uniqueness, broad dedupe services, lifecycle
  drains, and UI changes in this session.
- Minimum needed: focused TDD plus the narrow retry/send/repository contract.

## Arbiter Decision

- Structural blockers: none.
- Incremental details intentionally deferred: exact helper/API name and exact
  coalescer implementation can be chosen by the executor after reading current
  code.
- Accepted differences: GFR-001 remains host/direct and does not attempt
  lifecycle, UI, simulator, relay, or final closure-doc work.
- Final planning verdict: execution-ready.

## Execution Progress

- 2026-06-06 11:19:59 CEST - Phase: GFR-001 gate verification passed;
  graph update next. Files inspected/touched: GFR-001 scoped production/test
  files and group gate output. Commands passed: `git diff --check` and
  `./scripts/run_test_gates.sh groups` (`00:54 +321: All tests passed!`).
  Decision/blocker: no blocker; GFR-001 implementation and required gate are
  accepted by local execution evidence. Next action: run `graphify update .`,
  perform the QA/closure audit, and update the breakdown ledger.
- 2026-06-06 11:18:36 CEST - Phase: full direct suites complete.
  Files inspected/touched: GFR-001 scoped production/test files and direct
  group application/repository test suites. Commands passed:
  `flutter test test/features/groups/application/retry_failed_group_messages_use_case_test.dart`,
  `flutter test test/features/groups/application/send_group_message_use_case_test.dart`,
  `flutter test test/features/groups/application/handle_incoming_group_message_use_case_test.dart`,
  `flutter test test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart`,
  and `flutter test test/features/groups/domain/repositories/group_message_repository_impl_test.dart`.
  Decision/blocker: no blocker; the direct GFR-001 contract is green. Next
  action: run `git diff --check`, then the named `groups` gate required by this
  production group send/retry change.
- 2026-06-06 11:17:35 CEST - Phase: focused GFR-001 tests complete.
  Files inspected/touched: scoped production/test files listed in this plan.
  Commands: `flutter test test/features/groups/application/retry_failed_group_messages_use_case_test.dart --plain-name "GFR-001"`
  passed, `flutter test test/features/groups/application/send_group_message_use_case_test.dart --plain-name "GFR-001"`
  passed, and `flutter test test/features/groups/application/handle_incoming_group_message_use_case_test.dart --plain-name "GFR-001"`
  passed. Decision/blocker: no blocker; focused retry coalescing, pending-row
  reuse, settled-row non-retry, same-attempt send reuse, distinct settled sends,
  and receiver logical replay proof are green. Next action: run the required
  full direct suites sequentially.
- 2026-06-06 11:17:00 CEST - Phase: local Executor receiver proof added;
  focused tests starting sequentially. Files inspected/touched:
  `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`.
  Command: `dart format test/features/groups/application/handle_incoming_group_message_use_case_test.dart`.
  Decision/blocker: no blocker; added a GFR-001-named logical delivery replay
  regression so the receiver-side focused command has owned coverage. Next
  action: run the three focused `flutter test --plain-name "GFR-001"` commands
  sequentially, then full direct suites.
- 2026-06-06 11:10:15 CEST - Phase: spawned execution no-progress; local
  execution fallback starting. Files inspected/touched: GFR-001 plan and scoped
  git status. Command: spawned execution process
  `019e9c2e-06fc-72b1-b860-8a28d0c3c449` with nested Executor
  `019e9c2f-6976-7253-b454-ad980c874829` was terminated after no scoped
  code/test diff and no new plan heartbeat beyond Executor handoff. Decision/blocker:
  no product blocker; classify as spawned-child materialization/no-progress
  recovery, not a GFR-001 implementation blocker. Next action: parent pipeline
  performs bounded local execution/QA from this plan, preserving scope.
- 2026-06-06 11:12:05 CEST - Phase: local Executor implementation starting.
  Files inspected/touched: `retry_failed_group_messages_use_case.dart`,
  `send_group_message_use_case.dart`, `retry_failed_group_messages_use_case_test.dart`,
  `send_group_message_use_case_test.dart`, `InMemoryGroupMessageRepository`,
  `FakeBridge`. Command: source inspection only. Decision/blocker: no blocker;
  implementation can stay in retry/send use cases plus direct tests with no
  repository interface, DB helper, lifecycle, relay, or UI change. Next action:
  add GFR-001 tests and production edits for row-keyed retry coalescing,
  pending-row targeted retry eligibility, and pending-row send reuse.
- 2026-06-06 11:17:15 CEST - Phase: local Executor implementation complete;
  formatting/tests starting. Files inspected/touched:
  `lib/features/groups/application/retry_failed_group_messages_use_case.dart`,
  `lib/features/groups/application/send_group_message_use_case.dart`,
  `test/features/groups/application/retry_failed_group_messages_use_case_test.dart`,
  `test/features/groups/application/send_group_message_use_case_test.dart`.
  Command: pending `dart format` and focused `flutter test --plain-name
  "GFR-001"` runs. Decision/blocker: no blocker; production change is scoped to
  row-keyed retry coalescing, targeted pending retry eligibility, and matching
  pending-row send reuse. Next action: format touched files and run focused
  GFR-001 regressions.
- 2026-06-06 11:07:26 CEST - Phase: Executor spawned/running. Files
  inspected/touched: GFR-001 plan, graphify skill guidance, scoped graphify
  query output. Command: `graphify query "GFR-001 stable group retry attempt
  identity failed pending group text retry send_group_message
  retry_failed_group_messages handle_incoming_group_message repository lookup"
  --budget 1800`. Decision/blocker: no blocker; graph output was broad but
  confirmed this should stay within explicit group retry/send/receive/repository
  owner files. Next action: inspect owner files and add focused GFR-001 RED
  tests before production edits.
- 2026-06-06 11:06:08 CEST - Phase: contract extraction starting. Files
  inspected/touched: execution plan, execution QA skill, scoped graphify query.
  Command: none. Decision/blocker: no blocker; extracting exact scope, tests,
  gates, known-failure rules, done criteria, and scope guard before spawning
  Executor. Next action: persist extracted contract heartbeat.
- 2026-06-06 11:06:08 CEST - Phase: contract extracted. Files inspected/touched:
  execution plan. Command: none. Decision/blocker: source of truth is the
  GFR-001 plan and breakdown; scope is stable group retry attempt identity in
  group application/repository code and direct tests only; required direct tests
  are the three GFR-001 focused runs plus five full direct suites; `groups` gate
  is mandatory if production group send/retry/repository/receive behavior
  changes; known failures must match `test-gate-definitions.md`; non-goals are
  GFR-002 readiness drains, GFR-003 UI composer behavior, GFR-004 simulator
  proof, GFR-005 closure docs, relay/wire/db uniqueness/lifecycle/1:1 changes.
  Next action: spawn isolated Executor with model gpt-5.5 and reasoning xhigh.
- 2026-06-06 11:06:40 CEST - Phase: Executor spawned/running. Files
  inspected/touched: execution plan. Command: spawned agent
  `019e9c2f-6976-7253-b454-ad980c874829`. Decision/blocker: no blocker;
  Executor has bounded GFR-001 implementation scope and required tests/gates.
  Next action: wait for Executor completion evidence.

## QA Review

- 2026-06-06 11:23:06 CEST - Reviewer: parent pipeline local QA fallback.
  Files reviewed: `retry_failed_group_messages_use_case.dart`,
  `send_group_message_use_case.dart`,
  `retry_failed_group_messages_use_case_test.dart`,
  `send_group_message_use_case_test.dart`, and
  `handle_incoming_group_message_use_case_test.dart`. Findings: no blocking
  defects found. Scope review: implementation stays inside GFR-001 and does not
  add lifecycle, relay, DB uniqueness, UI, or 1:1 behavior. Test review:
  focused tests, full direct suites, `git diff --check`, `groups` gate, and
  `graphify update .` all passed. Residual risk: none beyond later-session
  work already owned by GFR-002 through GFR-005.

## Execution Verdict

Verdict: accepted

Accepted at: 2026-06-06 11:23:06 CEST

Blocker: none

Evidence:

- `flutter test test/features/groups/application/retry_failed_group_messages_use_case_test.dart --plain-name "GFR-001"`
- `flutter test test/features/groups/application/send_group_message_use_case_test.dart --plain-name "GFR-001"`
- `flutter test test/features/groups/application/handle_incoming_group_message_use_case_test.dart --plain-name "GFR-001"`
- `flutter test test/features/groups/application/retry_failed_group_messages_use_case_test.dart`
- `flutter test test/features/groups/application/send_group_message_use_case_test.dart`
- `flutter test test/features/groups/application/handle_incoming_group_message_use_case_test.dart`
- `flutter test test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart`
- `flutter test test/features/groups/domain/repositories/group_message_repository_impl_test.dart`
- `git diff --check`
- `./scripts/run_test_gates.sh groups` (`00:54 +321: All tests passed!`)
- `graphify update .`

## Closure Notes

- 2026-06-06 11:27:16 CEST - Phase: spawned closure audit in progress.
  Closure child: `019e9c3f-2f17-71d1-9adc-6ccd8a4b726f`. Files
  inspected/touched: GFR-001 plan, GFR-001 scoped code/test diff, gate script,
  gate definitions, and direct suites. Decision/blocker: no blocker; child
  reran focused/direct GFR-001 verification successfully and is rerunning
  `./scripts/run_test_gates.sh groups` before writing closure. Next action:
  wait for the closure child gate result and ledger update.
- 2026-06-06 11:23:45 CEST - Phase: closure audit launching. Closure input:
  accepted GFR-001 execution verdict, scoped code/test diff, direct suites,
  `groups` gate, and graphify update evidence. Decision/blocker: no blocker.
  Next action: run fresh closure-audit context, then update this plan and the
  breakdown ledger with the session closure verdict.
- 2026-06-06 11:28:27 CEST - Phase: completion audit accepted. Closure verdict:
  `closed` for GFR-001 only. Audited current diff in
  `retry_failed_group_messages_use_case.dart`, `send_group_message_use_case.dart`,
  `retry_failed_group_messages_use_case_test.dart`,
  `send_group_message_use_case_test.dart`, and
  `handle_incoming_group_message_use_case_test.dart`. The landed change is the
  scoped same-attempt contract: row-keyed single-message retry coalescing,
  targeted failed-or-pending outgoing retry eligibility, matching pending-row
  send reuse, and receiver logical-delivery replay proof.
- 2026-06-06 11:28:27 CEST - Phase: closure gate verification. Current-worktree
  verification passed: the three focused `--plain-name "GFR-001"` runs, the
  combined required direct suites, `git diff --check`, and
  `./scripts/run_test_gates.sh groups` (`00:54 +321: All tests passed!`).
  Closure bar satisfied: same-row rapid retry starts one publish, retryable
  pending rows reuse the original id/logical delivery/timestamp/quote/text,
  settled rows are no-op for retry, distinct post-settlement same-text sends
  remain distinct, receiver logical-delivery replay dedupes to one row, and
  media/inbox-store/reaction replay ownership remains covered by existing
  direct suites.
- 2026-06-06 11:28:27 CEST - Phase: closure reviewer accepted. Residual-only
  items are later-session work: GFR-002 readiness/queued auto-send coalescing,
  GFR-003 open-conversation UX, GFR-004 lifecycle/integration acceptance, and
  GFR-005 final stable doc reconciliation. Still-open items inside GFR-001:
  none. Accepted differences: no relay/wire/db uniqueness/lifecycle/UI/1:1 or
  simulator expansion. Reopen GFR-001 only on a real regression in same-attempt
  retry coalescing, pending-row reuse, settled-row no-op behavior, receiver
  dedupe, or the recorded direct/group gate contract. This resolves the
  transient 11:27 closure-child note above; no closure-child blocker remains.
