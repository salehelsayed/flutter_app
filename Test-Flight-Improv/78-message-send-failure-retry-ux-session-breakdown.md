# 78 - Message Send Failure Retry UX Session Breakdown

## Decomposition artifact

- Artifact path:
  `Test-Flight-Improv/78-message-send-failure-retry-ux-session-breakdown.md`
- Proposal/source doc path:
  `Test-Flight-Improv/78-message-send-failure-retry-ux.md`
- Supporting closure docs:
  - `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`
  - `Test-Flight-Improv/47-message-reliability-roadmap.md`
- Decomposition date:
  `2026-04-27`
- Downstream workflow rule:
  - detailed planning happens one session at a time
  - later sessions must be refreshed against landed code before execution

## Recommended plan count

- `4`
- The smallest safe split is:
  - `1` implementation session for the same-attempt failed-message recovery
    contract and first-delivery wire semantics
  - `1` implementation session for the conversation UI, context actions,
    composer restoration, and accessibility behavior
  - `1` implementation session for automatic retry, unacked retry, pause/resume,
    periodic retry, and same-ID relay/receiver dedupe race proof
  - `1` closure-only session for the 1:1 reliability docs, named-gate
    classification, and final acceptance record

## Overall closure bar

Report `78-message-send-failure-retry-ux.md` is finished only when all of the
following are true at the same time:

- a failed 1:1 outgoing text message has an explicit user-visible recovery path
  that does not require the user to infer that normal Edit is the resend path
- manual failed-message recovery targets the original failed outgoing row and
  message ID, and a recovered failed attempt settles as one visible outgoing row
  rather than creating a second composer-send copy
- recovery of a never-delivered failed message uses first-delivery chat-message
  semantics, not an `actionEdit` payload as the first recipient-visible
  representation of that message
- failed outgoing messages do not enter the normal edit mental model in a way
  that can produce edit-only hidden placeholders, stale original content, or
  ordering-dependent sender/recipient histories
- automatic failed-row retry, automatic unacked retry, user-visible recovery,
  pause-to-failed recovery, and the 5-minute online retry sweep resolve one
  canonical failed-send attempt instead of independent visible sends
- same-ID receiver and relay dedupe remain observable for the recovery flow,
  including encrypted v2 `wireEnvelope` replay
- failed media retry/delete behavior remains available, and normal Edit remains
  available for eligible already-sent messages
- failed-message state and recovery affordances expose accessible semantics
  equivalent to the visible state and action
- direct automated proof exists for the composer-restore duplicate path,
  edit-as-resend wire-semantics path, Path A vs Path C race, Path B vs Path C
  race, pause force-failed-after-delivery race, periodic retry non-resurrection,
  and sender/recipient one-visible-copy histories
- `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`,
  `Test-Flight-Improv/47-message-reliability-roadmap.md`, and
  `Test-Flight-Improv/test-gate-definitions.md` truthfully reflect the landed
  evidence without widening frozen named gates unnecessarily

## Source of truth

Primary governing docs:

- `Test-Flight-Improv/78-message-send-failure-retry-ux.md`
- `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`
- `Test-Flight-Improv/47-message-reliability-roadmap.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`

Current repo facts that govern the split:

- `lib/features/conversation/presentation/screens/conversation_wired.dart`
  currently restores the composer snapshot after failed sends, and normal
  composer send creates a new optimistic UUID when `_editingMessageId` is not
  set. That is the source of the composer-restored duplicate path.
- `conversation_wired.dart` has `_onRetryFailedMedia(...)`, but the direct
  failed-message recovery path is currently wired for failed media controls
  rather than text-only failed rows.
- `lib/features/conversation/presentation/screens/conversation_screen.dart`
  shows failed media retry/delete controls, but failed text rows do not expose
  equivalent direct recovery controls.
- `_canEditMessage(...)` in `conversation_screen.dart` does not exclude
  `status == 'failed'`, so failed outgoing text can be routed through normal
  Edit when it is otherwise eligible.
- `lib/features/conversation/application/send_chat_message_use_case.dart`
  builds `actionEdit` payloads for edit sends and persists `wireEnvelope`
  before risky transport work when a message ID already exists.
- `lib/features/conversation/application/retry_failed_messages_use_case.dart`
  already has targeted same-row retry through `retryFailedMessage(messageId:)`,
  and `retry_unacked_messages_use_case.dart` replays persisted sent-but-unacked
  encrypted v2 envelopes.
- `lib/core/services/pending_message_retrier.dart` and
  `lib/core/lifecycle/handle_app_resumed.dart` can automatically retry failed
  and unacked rows, while `lib/core/lifecycle/handle_app_paused.dart` can
  locally mark in-flight `sending` rows as `failed`.
- Existing tests cover durable retry, failed media controls, pause-to-failed,
  same-ID duplicate suppression, edit payload semantics, and unacked retry in
  isolation, but not the user-visible failed text recovery path or the combined
  manual/automatic retry races from Report `78`.

## Session ledger

| Session ID | Title | Classification | Intended plan file | Depends on | Initial status | Current status | Final execution verdict | Blocker class | Closure docs touched | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `1` | `Same-attempt failed-send recovery contract` | `implementation-ready` | `Test-Flight-Improv/78-message-send-failure-retry-ux-session-1-plan.md` | none | `pending` | `accepted` | `accepted` | none | `Test-Flight-Improv/78-message-send-failure-retry-ux-session-breakdown.md` | Accepted on `2026-04-27` after `editChatMessage(...)` rejected failed outgoing rows and targeted failed text retry was proven to reuse the original row/message ID with first-delivery non-edit wire semantics. Direct suites passed: `flutter test --no-pub test/features/conversation/application/retry_failed_messages_use_case_test.dart` and `flutter test --no-pub test/features/conversation/application/send_chat_message_use_case_test.dart`. |
| `2` | `Conversation failed-message recovery UX and accessibility` | `implementation-ready` | `Test-Flight-Improv/78-message-send-failure-retry-ux-session-2-plan.md` | `1` | `prerequisite-blocked` | `accepted` | `accepted` | none | `Test-Flight-Improv/78-message-send-failure-retry-ux-session-breakdown.md` | Accepted on `2026-04-27` after failed text rows gained direct retry controls, failed rows were excluded from normal Edit, unchanged restored failed drafts retried the original row, failed media controls stayed available, and failed retry controls gained accessible semantics. Direct suites passed together: `letter_card_test.dart`, `conversation_screen_test.dart`, `conversation_wired_test.dart`, `retry_failed_messages_use_case_test.dart`, and `send_chat_message_use_case_test.dart`. |
| `3` | `Retry race, lifecycle, and dedupe acceptance proof` | `implementation-ready` | `Test-Flight-Improv/78-message-send-failure-retry-ux-session-3-plan.md` | `1`, `2` | `prerequisite-blocked` | `accepted` | `accepted` | none | `Test-Flight-Improv/78-message-send-failure-retry-ux-session-breakdown.md` | Accepted on `2026-04-27` after the automatic-retry/restored-draft race was closed, targeted failed retry and unacked retry no-op behavior after settlement were proven, encrypted v2 receiver same-ID dedupe was proven, periodic sweep non-resurrection was proven, and the named `1to1` gate passed. |
| `4` | `1:1 reliability closure docs and gate classification` | `closure-only` | `Test-Flight-Improv/78-message-send-failure-retry-ux-session-4-plan.md` | `1`, `2`, `3` | `prerequisite-blocked` | `accepted` | `accepted` | none | `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`, `Test-Flight-Improv/47-message-reliability-roadmap.md`, `Test-Flight-Improv/test-gate-definitions.md`, `Test-Flight-Improv/78-message-send-failure-retry-ux.md`, `Test-Flight-Improv/78-message-send-failure-retry-ux-session-breakdown.md` | Accepted on `2026-04-27` after stable closure docs and gate classification were updated from landed evidence without widening frozen named gates. |

## Downstream execution path

For each runnable session in ledger order:

- `$implementation-plan-orchestrator`
- `$implementation-execution-qa-orchestrator`
- `$implementation-closure-audit-orchestrator`

After all runnable sessions are resolved:

- run the `$implementation-session-pipeline-orchestrator` final program
  acceptance pass and persist a final program verdict in this breakdown.

## Ordered session breakdown

### Session 1

- Title:
  `Same-attempt failed-send recovery contract`
- Session id:
  `1`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/78-message-send-failure-retry-ux-session-1-plan.md`
- Exact scope:
  - introduce or tighten the application-level manual failed-message recovery
    path so it targets the existing failed outgoing row and message ID
  - ensure recovering a failed never-delivered text message sends a normal
    first-delivery chat payload for the same message ID rather than an
    `actionEdit` payload
  - preserve existing targeted failed-row retry behavior and encrypted v2
    `wireEnvelope` replay where the row already has a retryable envelope
  - prevent normal edit submission from being the recovery mechanism for
    failed outgoing rows at the application boundary
  - add deterministic application tests for same-row text recovery, no new
    optimistic UUID, no `actionEdit` first delivery, retryable envelope reuse,
    and already-settled row no-op behavior
- Why it is its own session:
  - the UI cannot safely expose a recovery affordance until the application
    layer has a single canonical same-attempt recovery contract
  - the key risk here is wire semantics and message identity, not button
    placement or visual affordance
- Likely code-entry files:
  - `lib/features/conversation/application/send_chat_message_use_case.dart`
  - `lib/features/conversation/application/retry_failed_messages_use_case.dart`
  - `lib/features/conversation/application/retry_unacked_messages_use_case.dart`
  - `lib/features/conversation/domain/models/conversation_message.dart`
  - `lib/features/conversation/domain/repositories/message_repository.dart`
  - `lib/features/conversation/domain/repositories/message_repository_impl.dart`
  - `lib/core/database/helpers/messages_db_helpers.dart`
- Likely direct tests/regressions:
  - `test/features/conversation/application/retry_failed_messages_use_case_test.dart`
  - `test/features/conversation/application/send_chat_message_use_case_test.dart`
  - `test/features/conversation/application/retry_unacked_messages_use_case_test.dart`
  - `test/features/conversation/domain/repositories/message_repository_impl_test.dart`
  - new focused application tests adjacent to the chosen recovery primitive
- Likely named gates:
  - direct application suites above are mandatory
  - `./scripts/run_test_gates.sh 1to1` if production send, retry, repository,
    or envelope behavior changes
  - `./scripts/run_test_gates.sh transport` only if execution expands into
    app lifecycle, resume, reconnect, or bridge ordering
- Matrix/closure docs to update when done:
  - refresh this breakdown artifact's ledger and closure note only
  - final stable 1:1 closure doc and gate-doc updates stay with Session `4`
- Dependency on earlier sessions:
  - none
- Downstream execution path:
  - `$implementation-plan-orchestrator`
  - `$implementation-execution-qa-orchestrator`
  - `$implementation-closure-audit-orchestrator`

### Session 2

- Title:
  `Conversation failed-message recovery UX and accessibility`
- Session id:
  `2`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/78-message-send-failure-retry-ux-session-2-plan.md`
- Exact scope:
  - expose a clear failed text-message recovery affordance in the 1:1
    conversation surface using the Session `1` same-attempt recovery contract
  - keep failed media retry/delete controls available and align failed text
    recovery expectations with media without redesigning the whole media row UI
  - stop failed outgoing rows from entering the normal Edit action path while
    preserving normal Edit for eligible already-sent messages
  - resolve the composer-restore duplicate path so sending from a restored
    failed-send draft cannot create a second independent visible outgoing copy
    for the same failed attempt
  - preserve quote, text, attachment, and draft state honestly when recovery
    fails again during a flaky network period
  - add accessible semantics for failed status and the recovery action
- Why it is its own session:
  - this session owns the user-visible trust bug: discoverability, context menu
    actions, composer state, and accessibility
  - it depends on Session `1` so the UI does not have to invent a separate
    resend implementation or route through normal Edit
- Likely code-entry files:
  - `lib/features/conversation/presentation/screens/conversation_wired.dart`
  - `lib/features/conversation/presentation/screens/conversation_screen.dart`
  - `lib/features/conversation/presentation/widgets/letter_card.dart`
  - `lib/features/conversation/presentation/widgets/message_context_overlay.dart`
  - any existing conversation action or semantics helper introduced by
    neighboring failed-media controls
- Likely direct tests/regressions:
  - `test/features/conversation/presentation/screens/conversation_wired_test.dart`
  - `test/features/conversation/presentation/screens/conversation_screen_test.dart`
  - `test/features/conversation/presentation/widgets/letter_card_test.dart`
  - `test/features/conversation/presentation/widgets/message_context_overlay_test.dart`
    if the context overlay changes
- Likely named gates:
  - direct widget/screen suites above are mandatory
  - `./scripts/run_test_gates.sh 1to1` if the UI work changes shared send or
    retry behavior beyond presentation wiring
  - no Feed gate unless execution expands into feed inline reply or
    feed-to-conversation handoff
- Matrix/closure docs to update when done:
  - refresh this breakdown artifact's ledger and closure note only
  - final stable closure doc updates stay with Session `4`
- Dependency on earlier sessions:
  - Session `1`
- Downstream execution path:
  - `$implementation-plan-orchestrator`
  - `$implementation-execution-qa-orchestrator`
  - `$implementation-closure-audit-orchestrator`

### Session 3

- Title:
  `Retry race, lifecycle, and dedupe acceptance proof`
- Session id:
  `3`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/78-message-send-failure-retry-ux-session-3-plan.md`
- Exact scope:
  - add or tighten deterministic tests proving Path A
    (`retry_failed_messages`) vs Path C (user-visible recovery) resolves to
    one sender row and one receiver-visible delivered copy
  - add or tighten tests proving Path B (`retry_unacked_messages`) vs Path C
    resolves to one sender row and one receiver-visible delivered copy
  - prove the all-three Path A/B/C eligibility case cannot produce duplicate
    visible histories for a single send attempt
  - prove pause force-failed-after-delivery plus resume retry plus
    user-visible recovery still settles one visible message for the attempt
  - prove the 5-minute periodic retry sweep does not resurrect a message that
    already settled through user-visible recovery
  - prove the recovery flow still exercises same-ID receiver and relay dedupe,
    including encrypted v2 envelope replay
  - fix any real coordination gaps exposed by those tests, without broadening
    into a transport architecture rewrite
- Why it is its own session:
  - this work is cross-service acceptance evidence over automatic retriers,
    lifecycle recovery, sender/receiver state, and relay/receiver dedupe
  - it should run after the core contract and UI affordance land so the race
    tests validate the real user-visible path rather than a hypothetical API
- Likely code-entry files:
  - `lib/core/services/pending_message_retrier.dart`
  - `lib/core/lifecycle/handle_app_resumed.dart`
  - `lib/core/lifecycle/handle_app_paused.dart`
  - `lib/features/conversation/application/retry_failed_messages_use_case.dart`
  - `lib/features/conversation/application/retry_unacked_messages_use_case.dart`
  - `lib/features/conversation/application/handle_incoming_chat_message_use_case.dart`
  - `go-relay-server/backend_memory.go` only if current evidence shows relay
    same-ID dedupe is not exercised by the new recovery path
- Likely direct tests/regressions:
  - `test/features/conversation/integration/two_user_message_exchange_test.dart`
  - `test/features/conversation/integration/send_then_lock_delivery_test.dart`
  - `test/features/conversation/integration/stuck_sending_recovery_test.dart`
  - `test/integration/relay_down_degradation_integration_test.dart`
  - `test/core/lifecycle/pause_resume_retry_smoke_test.dart`
  - `test/core/services/pending_message_retrier_test.dart`
  - `test/features/conversation/application/retry_failed_messages_use_case_test.dart`
  - `test/features/conversation/application/retry_unacked_messages_use_case_test.dart`
  - `test/features/conversation/application/handle_incoming_chat_message_use_case_test.dart`
  - `go-relay-server/inbox_dedup_test.go` if relay code or test harness proof
    changes
- Likely named gates:
  - `./scripts/run_test_gates.sh 1to1`
  - `./scripts/run_test_gates.sh transport` if lifecycle, reconnect, resume, or
    device-backed transport behavior changes
  - direct lifecycle/service suites above are mandatory
  - Go relay tests are mandatory if relay code or same-ID relay harness changes
- Matrix/closure docs to update when done:
  - refresh this breakdown artifact's ledger and closure note only
  - final stable closure doc and gate classification stay with Session `4`
- Dependency on earlier sessions:
  - Session `1`
  - Session `2`
- Downstream execution path:
  - `$implementation-plan-orchestrator`
  - `$implementation-execution-qa-orchestrator`
  - `$implementation-closure-audit-orchestrator`

### Session 4

- Title:
  `1:1 reliability closure docs and gate classification`
- Session id:
  `4`
- Session classification:
  `closure-only`
- Intended plan file:
  `Test-Flight-Improv/78-message-send-failure-retry-ux-session-4-plan.md`
- Exact scope:
  - reconcile the landed Report `78` behavior against
    `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`
    without reopening unrelated 1:1 reliability architecture debates
  - update `Test-Flight-Improv/47-message-reliability-roadmap.md` only if the
    manual failed-message recovery contract changes the durable send/retry bar
    or closes a roadmap-relevant ambiguity
  - classify any new direct, integration, lifecycle, or Go relay tests in
    `Test-Flight-Improv/test-gate-definitions.md` according to the existing
    named-gate policy
  - record final evidence in this breakdown artifact, including direct tests,
    named gates, any skipped simulator/manual evidence, and the final program
    verdict
  - leave only explicit non-blocking follow-up if the overall closure bar is
    otherwise met
- Why it is its own session:
  - stable reliability docs and gate definitions should be updated from landed
    evidence, not planned behavior
  - the closure pass has a different done bar from implementation sessions:
    truthfulness of maintenance docs and final acceptance classification
- Likely code-entry files:
  - `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`
  - `Test-Flight-Improv/47-message-reliability-roadmap.md`
  - `Test-Flight-Improv/test-gate-definitions.md`
  - `Test-Flight-Improv/78-message-send-failure-retry-ux-session-breakdown.md`
  - `Test-Flight-Improv/78-message-send-failure-retry-ux.md`
  - `Test-Flight-Improv/00-INDEX.md` only if the repo's index policy requires
    listing or status changes for this report
- Likely direct tests/regressions:
  - no new product tests should be created in this closure-only session
  - rerun the direct suites and named gates recorded by Sessions `1` through
    `3` if their evidence is stale or incomplete
  - `./scripts/run_test_gates.sh completeness-check` if new test files were
    added or gate definitions changed
- Likely named gates:
  - `./scripts/run_test_gates.sh 1to1`
  - `./scripts/run_test_gates.sh transport` only if Session `3` touched
    lifecycle, reconnect, resume, or device-backed transport behavior
  - `./scripts/run_test_gates.sh completeness-check` if test classification
    changed
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`
  - `Test-Flight-Improv/47-message-reliability-roadmap.md` if materially
    affected
  - `Test-Flight-Improv/test-gate-definitions.md`
  - `Test-Flight-Improv/78-message-send-failure-retry-ux-session-breakdown.md`
  - `Test-Flight-Improv/78-message-send-failure-retry-ux.md` if the source doc
    carries a status or evidence ledger convention
  - `Test-Flight-Improv/00-INDEX.md` only if required by existing index policy
- Dependency on earlier sessions:
  - Session `1`
  - Session `2`
  - Session `3`
- Downstream execution path:
  - `$implementation-plan-orchestrator`
  - `$implementation-execution-qa-orchestrator`
  - `$implementation-closure-audit-orchestrator`

## Why this is not fewer sessions

- Combining Session `1` and Session `2` would mix wire identity semantics with
  conversation controls and accessibility, making it too easy for UI work to
  reintroduce edit-as-resend semantics instead of using a proven recovery
  contract.
- Combining Session `2` and Session `3` would make the race/lifecycle proof
  depend on unfinished surface behavior, and the integration acceptance suite
  would have to guess at the final manual recovery path.
- Combining Session `3` and Session `4` would let stable reliability docs be
  updated before the automatic retry, pause/resume, periodic sweep, and dedupe
  evidence exists.
- Splitting further would create bookkeeping-only sessions around individual
  race cases that share the same 1:1 retry/lifecycle proof family and named
  gate contract.

## Reviewer notes

- Structural blockers:
  - none known after local decomposition fallback
- Mergeable sessions:
  - all four sessions are accepted as of `2026-04-27`
- Required splits:
  - none beyond the four sessions above
- Accepted differences:
  - no new transport architecture, relay redesign, group chat retry UX, or broad
    edit-message redesign is part of this rollout
  - exact visual copy and placement remain implementation decisions as long as
    the recovery action is discoverable, accessible, and not normal Edit

## Final program verdict

- Verdict:
  `accepted`
- Accepted date:
  `2026-04-27`
- Source doc:
  `Test-Flight-Improv/78-message-send-failure-retry-ux.md`
- Breakdown artifact:
  `Test-Flight-Improv/78-message-send-failure-retry-ux-session-breakdown.md`
- Decomposition status:
  local fallback created this reusable breakdown after the spawned
  decomposition agent did not land a trustworthy artifact.
- Pipeline status:
  local fallback executed all four sessions after the spawned pipeline
  controller did not land a doc-scoped plan, ledger delta, or final verdict.
- Final accepted behavior:
  failed outgoing text messages now have a clear same-row retry path; failed
  rows cannot enter normal Edit as resend; unchanged restored failed drafts
  retry or clear the original failed row instead of creating a second outgoing
  copy; automatic retry, unacked retry, periodic sweeps, and encrypted v2
  receiver dedupe all have direct no-duplicate evidence.
- Verification summary:
  - `flutter test --no-pub test/features/conversation/presentation/widgets/letter_card_test.dart test/features/conversation/presentation/screens/conversation_screen_test.dart test/features/conversation/presentation/screens/conversation_wired_test.dart test/features/conversation/application/retry_failed_messages_use_case_test.dart test/features/conversation/application/send_chat_message_use_case_test.dart`
  - `flutter test --no-pub test/features/conversation/application/retry_failed_messages_use_case_test.dart test/features/conversation/application/retry_unacked_messages_use_case_test.dart`
  - `flutter test --no-pub test/features/conversation/presentation/screens/conversation_wired_test.dart test/features/conversation/integration/two_user_message_exchange_test.dart`
  - `flutter test --no-pub test/features/conversation/presentation/screens/conversation_wired_test.dart --plain-name 'automatic retry settling a restored failed draft prevents a second send'`
  - `flutter test --no-pub test/features/conversation/integration/two_user_message_exchange_test.dart --plain-name 'encrypted v2 retry envelope duplicates materialize once for the receiver'`
  - `flutter test --no-pub test/core/services/pending_message_retrier_test.dart --plain-name 'periodic sweep does not replay a row already settled by manual recovery'`
  - `flutter test --no-pub test/core/services/pending_message_retrier_test.dart`
  - `./scripts/run_test_gates.sh 1to1`
  - `./scripts/run_test_gates.sh completeness-check`
- Remaining non-blocking evidence gap:
  simulator/device-backed lifecycle proof was not rerun in this local closure;
  the host-side 1:1 gate and direct lifecycle/retry tests passed.
