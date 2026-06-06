# 108 - Group Failed Message Retry Duplicate Send UX Session Breakdown

## Decomposition artifact

- Artifact path:
  `Test-Flight-Improv/108-group-failed-message-retry-duplicate-send-ux-session-breakdown.md`
- Proposal/source doc path:
  `Test-Flight-Improv/108-group-failed-message-retry-duplicate-send-ux.md`
- Supporting closure and matrix docs:
  - `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix.md`
  - `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md`
  - `Test-Flight-Improv/Group-Chat-Feature/Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md`
  - `Test-Flight-Improv/test-gate-definitions.md`
- Decomposition date:
  `2026-06-06`
- Downstream workflow rule:
  - detailed planning happens one session at a time
  - later sessions must be refreshed against landed code before execution
  - after all runnable sessions resolve, run the pipeline final whole-program
    acceptance pass and persist one allowed final program verdict in this
    breakdown

## Run Mode Snapshot

- Active mode: `standard`
- Degraded local continuation explicitly allowed: `no`
- Source proposal, matrix, or closure doc path:
  `Test-Flight-Improv/108-group-failed-message-retry-duplicate-send-ux.md`
- Source row/status vocabulary:
  source proposal is narrative spec-only; supporting closure/matrix docs use
  `Open`, `Partial`, `Contract-undefined`, `Needs evidence`, `Needs tests`,
  `Blocked`, `Closed`, and `Covered` where applicable.
- Overall closure bar:
  all Report 108 one-attempt/one-copy failed, queued, pending, retry,
  auto-recovery, lifecycle, open-conversation, preservation, and evidence/doc
  bullets in `## Overall closure bar` must be met truthfully.
- Final verdict policy:
  persist exactly one of `closed`, `accepted_with_explicit_follow_up`,
  `residual_only`, or `still_open` after all runnable sessions resolve and a
  final ledger sanity check passes.

## Controller Progress

- 2026-06-06 17:26:12 CEST - Phase: GFR-005 closure completed and final
  program verdict persisted. Session: `GFR-005`. Docs inspected/updated:
  source Report 108 doc, this breakdown, GFR-004 plan evidence, group
  discussion reliability closure reference, discussion/announcement matrix row
  `MM-006`, and gate-definition/gap-matrix scope. Decision: Report 108 final
  program verdict is `closed`. No gate-definition membership changed, and the
  open-gap matrix had no Report 108 row to reclassify. Final stable docs now
  record accepted behavior, accepted evidence, accepted architectural
  differences, no Report 108 residual-only items, and reopen rules.
- 2026-06-06 17:22:03 CEST - Phase: GFR-004 simulator acceptance completed.
  Session: `GFR-004`; dependent `GFR-005` is now unblocked. Docs/logs
  inspected: GFR-004 plan, this breakdown, required simulator command output,
  per-role logs, Bob proof JSONs, and role/orchestrator verdict JSONs for
  `private_relay_reconnect_group_recovery` run `1780758396971` and
  `private_background_resume_group_delivery` run `1780758894898`. Decision:
  GFR-004 is accepted. The stale simulator DB schema blocker remains cleared:
  Alice, Bob, and Charlie logged
  `GROUP_MESSAGE_LOGICAL_DELIVERY_ID_MIGRATION_SUCCESS` in both accepted runs,
  and no missing `logical_delivery_id` DB exception appeared. The Bob
  received-proof blocker is also cleared. Alice's `GROUP_PUBLISH_DEBUG` for
  `aliceMissedDuringRelayDrop` and `aliceDuringBackgroundBeforeEdit` showed
  `deliveryMode:"live_and_inbox"`, `expectedRecipientCount:2`, and
  `inboxStored:true`; Bob wrote both required received-proof JSONs with
  `liveOnly:false`, `usedOfflineDrain:true`, and `persistedCount:1`; both
  orchestrator verdicts were `ok:true`, and all Alice/Bob/Charlie role verdicts
  were written. Next action: run GFR-005 final stable doc closure and persist
  the final Report 108 program verdict.
- 2026-06-06 16:05:00 CEST - Phase: GFR-004 simulator blocker verification
  and final verdict refresh. Session: `GFR-004` plus dependent `GFR-005`.
  Docs/logs inspected: GFR-004 plan, this breakdown, required simulator
  command output, and per-role logs for reruns
  `private_relay_reconnect_group_recovery` run `1780753444911` and
  `private_background_resume_group_delivery` run `1780754053119`. Decision:
  the stale simulator DB schema blocker is cleared because Alice, Bob, and
  Charlie logged `GROUP_MESSAGE_LOGICAL_DELIVERY_ID_MIGRATION_SUCCESS` in both
  required scenarios and no missing `logical_delivery_id` DB exception
  appeared. Blocker: GFR-004 remains blocked by
  `simulator_bob_missing_received_proof_after_offline_drain_retry`; both
  required scenarios still exited `255` after the offline-drain wait kept
  draining while waiting because Bob failed to write the received-proof JSON.
  GFR-005 remains skipped due to GFR-004 dependency. Next action: run final
  hygiene and leave final program verdict `still_open`.
- 2026-06-06 14:58:00 CEST - Phase: final program acceptance.
  Session: whole doc. Docs inspected: GFR-004 blocked execution verdict,
  GFR-004 ledger row, GFR-005 dependency, and final verdict policy.
  Decision/blocker: all runnable sessions have resolved; GFR-005 is skipped
  because its only prerequisite, GFR-004, is blocked by the required simulator
  Bob received-proof failure. Next action: persist final program verdict
  `still_open` in this breakdown and leave source/stable closure docs
  untouched.
- 2026-06-06 13:31:56 CEST - Phase: GFR-004 execution/QA launch.
  Session: `GFR-004`. Docs/processes inspected: GFR-004 execution-ready plan,
  GFR-004 ledger row, stale GFR-004 planner process check, and
  execution-QA-orchestrator contract. Decision/blocker: no execution-start
  blocker; no active GFR-004 planning process remains, GFR-004 is
  `execution-ready`, and GFR-005 remains untouched. Next action: launch a fresh
  GFR-004 execution/QA child against the existing plan.
- 2026-06-06 13:20:32 CEST - Phase: GFR-004 planning launch.
  Session: `GFR-004`. Docs inspected: closed GFR-001 through GFR-003 ledger
  rows, GFR-004 acceptance-only scope, implementation-plan-orchestrator rules,
  and graphify usage rules. Decision/blocker: no prerequisite blocker remains;
  GFR-004 is now the active runnable session and must produce an
  execution-ready acceptance plan covering whole-journey simulator/lifecycle
  evidence before execution. Next action: launch a fresh GFR-004 planner with
  graphify-first evidence collection.
- 2026-06-06 13:17:19 CEST - Phase: GFR-003 closure audit completed.
  Session: `GFR-003`. Docs/code/tests inspected: GFR-003 plan final execution
  verdict and new closure section, source Report 108 scope boundaries, GFR-003
  scoped production diffs in wired/screen/LetterCard presentation files,
  focused GFR-003 wired/screen/LetterCard tests, recorded focused/direct/named
  gate evidence, and current dirty-tree summary. Decision/blocker: GFR-003 is
  `closed`; no repo evidence contradicts the accepted execution verdict, no
  GFR-003 still-open item remains, and GFR-004 whole-journey simulator/lifecycle
  acceptance remains a downstream program dependency rather than a GFR-003
  blocker. Next action: stop this closure audit; any GFR-004 work must launch
  in a separate scoped context.
- 2026-06-06 13:17:08 CEST - Phase: GFR-003 closure audit launch.
  Session: `GFR-003`. Docs inspected: GFR-003 plan status and breakdown ledger
  row. Decision/blocker: no GFR-003 closure blocker is known; execution is
  accepted and the row is ready for a fresh closure audit. Next action: launch
  the GFR-003 closure-audit agent, then either mark GFR-003 closed or persist
  the exact closure blocker before planning GFR-004.
- 2026-06-06 13:14:05 CEST - Phase: GFR-003 execution accepted.
  Session: `GFR-003`. Docs/code/tests inspected: GFR-003 plan final execution
  verdict, graphify output mtimes, full `git diff --check`, and recorded
  focused/direct/named gate evidence. Decision/blocker: no GFR-003 blocker;
  execution is `accepted` after focused GFR-003 tests, wired/screen/LetterCard
  direct suites, `groups` gate, formatter, graph refresh, and full whitespace
  check passed. The stopped child is classified as a post-graphify tool wrapper
  stall only. Next action: launch a fresh GFR-003 closure audit before moving
  to GFR-004.
- 2026-06-06 13:11:14 CEST - Phase: GFR-003 graph refresh wait.
  Session: `GFR-003`. Docs/processes inspected: active GFR-003 execution plan
  progress, child execution output, and current gate sequence. Decision/blocker:
  no GFR-003 product or gate blocker; focused tests, direct suites, scoped
  whitespace check, and the required `groups` gate have passed, and the child
  is waiting on `graphify update .` before full `git diff --check` and final
  execution verdict. Next action: bounded wait for graph refresh completion,
  then record graph/diff-check result and advance to GFR-003 closure audit or
  persist an exact tooling failure if graphify exits nonzero.
- 2026-06-06 13:00:37 CEST - Phase: GFR-003 execution production seam landed.
  Session: `GFR-003`. Docs/code inspected: active GFR-003 plan Execution
  Progress, focused RED output, and current diffs in
  `GroupConversationWired`, `GroupConversationScreen`, `LetterCard`, and their
  focused tests. Decision/blocker: no product blocker; the execution recovery
  child has moved past the missing `retryingFailedMessageIds` RED seam and has
  landed the row-scoped retry disabled/in-flight state plus text-only composer
  clearing production changes. Next action: bounded wait for focused and direct
  GFR-003 gate results, then either persist exact failures or advance GFR-003
  to closure audit.
- 2026-06-06 12:50:07 CEST - Phase: GFR-003 execution child recovery.
  Session: `GFR-003`. Docs/processes inspected: GFR-003 plan Execution
  Progress, scoped owner-file diff, execution child process state, and stopped
  execution/QA session. Decision/blocker: no GFR-003 product blocker; the
  nested Executor recorded intake but produced no code/test delta or final
  result across bounded waits, so the attempt is classified in the plan as
  nested `spawn_or_tool_failure`. Next action: launch a fresh GFR-003 execution
  recovery context using the execution-QA local fallback rule.
- 2026-06-06 12:41:45 CEST - Phase: GFR-003 planning fallback completed.
  Session: `GFR-003`. Docs inspected: recovered GFR-003 plan, source
  GFR-003 checklist, breakdown ledger, graphify query/explain output, and exact
  group presentation/wired code seams. Decision/blocker: no planning blocker;
  `Test-Flight-Improv/108-group-failed-message-retry-duplicate-send-ux-session-GFR-003-plan.md`
  exists with `Status: execution-ready`. Next action: launch a fresh GFR-003
  execution/QA agent against that plan.
- 2026-06-06 12:39:30 CEST - Phase: GFR-003 planning artifact recovery.
  Session: `GFR-003`. Docs/processes inspected: GFR-003 plan path, `find`
  output for `*GFR-003*`, active planner process list, and repeated child
  output after its draft rewrite started. Decision/blocker: no product blocker
  exists, but the fresh planner left the doc-scoped GFR-003 plan file absent
  while it continued reading source files; this violates the durable current-doc
  requirement. Next action: stop that stale planner process, recover the
  GFR-003 plan artifact with the gathered evidence, and persist either
  `Status: execution-ready` or an exact GFR-003 blocker before execution.
- 2026-06-06 12:36:23 CEST - Phase: GFR-003 planning evidence wait.
  Session: `GFR-003`. Docs inspected: active GFR-003 plan Planning Progress,
  process list for the fresh planner, and latest child output. Decision/blocker:
  no blocker yet; the planner process is visible and still gathering
  presentation/wiring evidence, but it has not written a post-intake role
  boundary update. Next action: continue bounded wait for the fresh GFR-003
  planner; if it exits or stalls without an execution-ready plan, persist an
  exact GFR-003 planning blocker or locally recover the plan artifact before
  execution.
- 2026-06-06 12:34:29 CEST - Phase: controller reconciliation after GFR-002
  planning progress check.
  Session: `GFR-003`. Docs inspected: GFR-002 plan header/closure notes,
  breakdown GFR-002/GFR-003 ledger rows, and current GFR-003 plan Planning
  Progress. Decision/blocker: no GFR-002 planning blocker exists because
  GFR-002 is already closed as `accepted_with_explicit_follow_up`; the current
  runnable phase is GFR-003 planning. Next action: wait for the fresh GFR-003
  planner to finish an execution-ready plan or persist an exact GFR-003
  blocker, then update the ledger before launching GFR-003 execution/QA.
- 2026-06-06 12:32:08 CEST - Phase: GFR-003 planning launch.
  Session: `GFR-003`. Docs inspected: closed GFR-001/GFR-002 ledger rows,
  GFR-003 breakdown scope, and GFR-002 closure audit follow-up notes.
  Decision/blocker: no dependency blocker remains; GFR-003 is the next
  runnable implementation session and owns only open-conversation recovery UX.
  Next action: launch a fresh GFR-003 planner for
  `Test-Flight-Improv/108-group-failed-message-retry-duplicate-send-ux-session-GFR-003-plan.md`.
- 2026-06-06 12:29:44 CEST - Phase: GFR-002 closure audit completed.
  Session: `GFR-002`. Docs/code/tests inspected: GFR-002 plan final execution
  verdict, breakdown GFR-002 ledger row, source Report 108 scope notes,
  `graphify query` scoped recovery output, landed retrier/send/retry/repository
  diffs, focused GFR-002 tests, and recorded direct/named gate evidence.
  Decision/blocker: GFR-002 is closeable as
  `accepted_with_explicit_follow_up`; no GFR-002 product or gate blocker was
  found. The explicit follow-up remains GFR-004's whole-journey group simulator
  acceptance for relay reconnect and background resume delivery. Next action:
  do not run or plan GFR-003 from this audit; GFR-003 remains pending until a
  separate session is launched.
- 2026-06-06 12:26:41 CEST - Phase: GFR-002 closure audit launch.
  Session: `GFR-002`. Docs inspected: GFR-002 final execution verdict,
  breakdown ledger row, and current controller progress. Decision/blocker:
  GFR-002 execution/QA is `accepted_with_explicit_follow_up` with no blocking
  QA issue; explicit follow-up is the already-scoped GFR-004 whole-journey
  simulator acceptance. Next action: launch a fresh GFR-002 closure audit to
  decide whether the ledger row can be marked `closed` or must reopen with an
  exact blocker.
## Recommended plan count

- `5`
- The smallest safe split is:
  - `1` implementation session for stable group attempt identity,
    same-row/manual retry idempotency, in-doubt `pending` recovery, and
    receiver/sender duplicate proof at the application layer
  - `1` implementation session for queued-send auto recovery on readiness,
    relay-ready/resume coalescing, feature-flag behavior, and local status
    events
  - `1` implementation session for the open conversation UX: composer clearing,
    retry/send-now in-progress state, repeated tap suppression, and failed media
    preservation
  - `1` acceptance session for lifecycle, resume, reaction replay ownership,
    integration/simulator evidence, and named gate reconciliation
  - `1` closure-only session for stable docs, gate classification, and the final
    program verdict

## Overall closure bar

Report `108-group-failed-message-retry-duplicate-send-ux.md` is finished only
when all of the following are true at the same time:

- one user intent for a group text send is represented by one stable outgoing
  attempt across failed, queued, retrying, pending/in-doubt, sent, and delivered
  states
- a failed or queued group text row can be recovered manually without creating a
  second independent composer-send row for the same text, quote, timestamp, or
  logical delivery identity
- repeated Retry taps, Retry overlapping Send, auto-retry overlapping manual
  retry, relay-ready recovery overlapping app-resume recovery, and readiness
  flapping all coalesce into at most one sender-visible row and one
  recipient-visible delivery for the same attempt
- a send attempted when transport is unusable leaves one queued/in-progress row,
  clears the composer of the same text, and auto-sends after connectivity or
  relay readiness returns without further user action
- in-doubt `pending` rows behind bridge timeout are not stranded; they either
  settle or are recoverable through the same stable-attempt path without a
  duplicate recipient-visible delivery
- the open group conversation observes queued, retrying, failed, sent, and
  delivered state transitions through local outgoing row-change or rows-changed
  signals without duplicate rows or stale composer restoration
- failed group media retry/delete behavior, failed text avoidance of media
  controls, distinct intentional same-text messages after settlement, receiver
  message-id/logical-delivery dedupe, resume group recovery order,
  `GroupRecoveryGate` protections, and reaction replay retry ownership remain
  intact
- direct TDD evidence exists for the old duplicate paths and the new single-copy
  behavior, and the applicable direct suites plus named gates are recorded in
  the session plans and closure docs
- stable group reliability docs and gate definitions are updated truthfully
  without widening frozen named gates unless the landed changes require it

## Source of truth

Primary governing docs:

- `Test-Flight-Improv/108-group-failed-message-retry-duplicate-send-ux.md`
- `Test-Flight-Improv/78-message-send-failure-retry-ux.md`
- `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix.md`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md`
- `Test-Flight-Improv/Group-Chat-Feature/Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md`

Current repo facts that govern the split:

- `lib/features/groups/presentation/screens/group_conversation_screen.dart`
  exposes a text-only failed-row Retry affordance while failed media rows use
  separate media retry/delete controls.
- `lib/features/groups/presentation/screens/group_conversation_wired.dart`
  restores failed text into the composer and tracks a restored continuation, but
  its `_onRetryFailedMessage(...)` path has no row-scoped in-flight guard.
- `_onSend` in `group_conversation_wired.dart` uses the local send guard, so the
  composer send path and failed-row retry path currently have asymmetric
  concurrency protection.
- `lib/features/groups/application/send_group_message_use_case.dart`
  pre-persists outgoing rows with retry payload and logical delivery identity,
  can reuse an existing row only for exact id/sender/text/quote/timestamp
  matches, and can mark bridge-timeout in-doubt rows `pending`.
- `lib/features/groups/application/retry_failed_group_messages_use_case.dart`
  targets failed rows by id and re-enters group send with original message id,
  logical delivery id, timestamp, quote, and media context, but it only loads
  rows whose status is `failed`.
- `lib/features/groups/application/retry_failed_group_inbox_stores_use_case.dart`
  owns message inbox-store retry first and reaction replay retry with remaining
  capacity, so queued text recovery must not consume or corrupt reaction replay
  rows.
- `lib/core/lifecycle/handle_app_resumed.dart` already runs group rejoin, group
  offline inbox drain, stuck-sending recovery, incomplete upload retry, failed
  group retry, and failed inbox-store retry under existing ordering and feature
  flags.
- `lib/features/groups/application/group_recovery_gate.dart` exposes active
  recovery depth; `GroupConversationWired` observes it and group send rejects
  announcement sends during active recovery in some paths.
- `lib/features/p2p/domain/models/node_state.dart` exposes `relayReady` and
  `usabilityReady`, but there is no explicit current owner that drains queued
  group text attempts on those readiness transitions.
- `lib/features/groups/application/handle_incoming_group_message_use_case.dart`
  dedupes incoming group messages by message id and logical delivery id, while
  the content fallback requires exact sender/text/timestamp identity; a fresh
  composer send with a new id and timestamp can bypass that protection.
- Existing direct tests cover retry visibility, failed media preservation,
  failed publish restoration, local outgoing status events, resume group
  recovery order, pending/background recovery hooks, `GroupRecoveryGate`, and
  inbox-store/reaction replay retry in isolation, but not the combined group
  failed/queued duplicate-send journey from Report 108.
- `graphify query "group failed message retry duplicate send queue auto
  reconnect pending relayReady GroupRecoveryGate retryFailedGroupMessages"`
  confirmed the relevant code communities around `retry_failed_group_messages`,
  `group_recovery_gate`, `send_group_message_use_case`, and group repository
  local status events before this decomposition fallback.

## Session ledger

| Session ID | Title | Classification | Intended plan file | Depends on | Initial status | Current status | Final execution verdict | Blocker class | Closure docs touched | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `GFR-001` | `Stable group retry attempt contract` | `implementation-ready` | `Test-Flight-Improv/108-group-failed-message-retry-duplicate-send-ux-session-GFR-001-plan.md` | none | `pending` | `closed` | accepted | none | GFR-001 plan and this breakdown | Closed on 2026-06-06 11:28 CEST. Same-attempt retry coalescing, failed/pending row eligibility, duplicate receiver proof, and row-scoped recovery are accepted; only GFR-002+ residual sessions remain. |
| `GFR-002` | `Queued auto-send and readiness coalescing` | `implementation-ready` | `Test-Flight-Improv/108-group-failed-message-retry-duplicate-send-ux-session-GFR-002-plan.md` | `GFR-001` | `prerequisite-blocked` | `closed` | accepted_with_explicit_follow_up | none | GFR-002 plan and this breakdown | Closure-audited on 2026-06-06 12:29 CEST. Execution/QA remains accepted after focused GFR-002 tests, all required direct suites, `groups` gate, device-selected `transport` gate, `graphify update .`, and `git diff --check` passed. Explicit follow-up carried forward: GFR-004 owns whole-journey group simulator acceptance scenarios. |
| `GFR-003` | `Open conversation recovery UX` | `implementation-ready` | `Test-Flight-Improv/108-group-failed-message-retry-duplicate-send-ux-session-GFR-003-plan.md` | `GFR-001`, `GFR-002` | `prerequisite-blocked` | `closed` | accepted | none | GFR-003 plan and this breakdown | Closure-audited on 2026-06-06 13:17 CEST. Execution remains accepted after focused GFR-003 tests, full wired/screen/LetterCard direct suites, `./scripts/run_test_gates.sh groups`, formatter, graph refresh, and full `git diff --check` passed. Closed scope: open-conversation one-row text recovery UX, row retry coalescing/disabled state, recovery-gate/read-only suppression, quote/draft clearing, failed media preservation, and local status update proof. GFR-004 whole-journey simulator/lifecycle acceptance remains a downstream program dependency, not a GFR-003 blocker. |
| `GFR-004` | `Lifecycle, integration, and gate acceptance` | `acceptance-only` | `Test-Flight-Improv/108-group-failed-message-retry-duplicate-send-ux-session-GFR-004-plan.md` | `GFR-001`, `GFR-002`, `GFR-003` | `prerequisite-blocked` | `closed` | accepted | none | GFR-004 plan and this breakdown | Accepted on 2026-06-06 17:22 CEST. Host acceptance tests, focused/direct prerequisite and direct suites, mandatory `groups`, device-selected `transport`, selected `baseline`, and `completeness-check` gates remain accepted from the GFR-004 plan. Required simulator reruns now pass: `private_relay_reconnect_group_recovery` run `1780758396971` and `private_background_resume_group_delivery` run `1780758894898` both wrote orchestrator verdict `ok:true` and Alice/Bob/Charlie role verdict JSONs. Schema inspection found only migration `074_group_message_logical_delivery_id` start/success entries and no missing-column failure. Alice's target-message publish debug showed `deliveryMode:"live_and_inbox"`, `expectedRecipientCount:2`, and `inboxStored:true` in both accepted scenarios. Bob wrote `gmp_1780758396971_bob_received_aliceMissedDuringRelayDrop.json` and `gmp_1780758894898_bob_received_aliceDuringBackgroundBeforeEdit.json`, each with `liveOnly:false`, `usedOfflineDrain:true`, and `persistedCount:1`. GFR-005 is unblocked. |
| `GFR-005` | `Group retry duplicate UX closure docs` | `closure-only` | `Test-Flight-Improv/108-group-failed-message-retry-duplicate-send-ux-session-GFR-005-plan.md` | `GFR-004` | `prerequisite-blocked` | `closed` | closed | none | source Report 108 doc, this breakdown, group closure reference, discussion matrix | Closed on 2026-06-06 17:26 CEST after GFR-004 simulator acceptance. Updated the source Report 108 final closure section, this breakdown final program verdict, `20-group-discussion-reliability-closure-reference.md`, and discussion/announcement matrix row `MM-006`. Gate definitions were inspected and not changed because no named-gate membership or classification changed; the open-gap matrix had no Report 108 row to reclassify. |

## Ordered session breakdown

### Session GFR-001

- Title:
  `Stable group retry attempt contract`
- Session id:
  `GFR-001`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/108-group-failed-message-retry-duplicate-send-ux-session-GFR-001-plan.md`
- Exact scope:
  - establish the application-layer contract that one group text send attempt
    keeps one stable row/message/logical delivery identity across failed,
    retrying, pending, sent, and already-settled states
  - make manual failed-row retry idempotent for one row under rapid repeated
    calls and under overlap with any same-attempt composer continuation
  - include in-doubt `pending` text attempts in the recovery model without
    broadening media, voice, membership, key repair, or notification behavior
  - preserve distinct intentional same-text messages after the original failed
    or queued attempt has settled
  - prove receiver duplicate suppression still catches same-id/logical-delivery
    replay, and prove the previous fresh-id/fresh-timestamp duplicate path is
    no longer reachable for the same attempt
  - preserve failed media retry/delete behavior and the existing
    `retryFailedGroupInboxStores(...)` message/reaction ownership boundary
- Why it is its own session:
  - every later UX or auto-recovery path must call one canonical same-attempt
    contract instead of independently sending new rows
  - the core risk is data identity and concurrency, not visual state
- Likely code-entry files:
  - `lib/features/groups/application/send_group_message_use_case.dart`
  - `lib/features/groups/application/retry_failed_group_messages_use_case.dart`
  - `lib/features/groups/application/retry_failed_group_inbox_stores_use_case.dart`
  - `lib/features/groups/application/handle_incoming_group_message_use_case.dart`
  - `lib/features/groups/domain/models/group_message.dart`
  - `lib/features/groups/domain/repositories/group_message_repository.dart`
  - `lib/features/groups/domain/repositories/group_message_repository_impl.dart`
  - `lib/core/database/helpers/group_messages_db_helpers.dart`
- Likely direct tests/regressions:
  - `test/features/groups/application/send_group_message_use_case_test.dart`
  - `test/features/groups/application/retry_failed_group_messages_use_case_test.dart`
  - `test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart`
  - `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`
  - `test/features/groups/domain/repositories/group_message_repository_impl_test.dart`
  - add focused tests for rapid same-row retry coalescing, pending recovery
    eligibility, same-attempt duplicate suppression, and distinct post-settlement
    same-text sends
- Likely named gates:
  - direct suites above are mandatory
  - `./scripts/run_test_gates.sh groups` if production group send, retry,
    repository, receive, or inbox-store behavior changes
  - `./scripts/run_test_gates.sh transport` only if execution expands into
    bridge lifecycle or transport readiness ordering in this session
- Matrix/closure docs to update when done:
  - update this breakdown ledger only during session closure
  - final source/stable doc updates stay with `GFR-005`
- Dependency on earlier sessions:
  - none
- Downstream execution path:
  - `$implementation-plan-orchestrator`
  - `$implementation-execution-qa-orchestrator`
  - `$implementation-closure-audit-orchestrator`

### Session GFR-002

- Title:
  `Queued auto-send and readiness coalescing`
- Session id:
  `GFR-002`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/108-group-failed-message-retry-duplicate-send-ux-session-GFR-002-plan.md`
- Exact scope:
  - make group text sends attempted with no usable transport persist as one
    queued/in-progress outgoing attempt rather than restoring the same text as a
    second composer opportunity
  - add or tighten a repo-owned recovery owner that drains eligible queued,
    failed, or in-doubt group text attempts when send readiness returns
  - coalesce relay-ready recovery with the existing app-resume order:
    group rejoin/drain, stuck-sending recovery, incomplete upload retry, failed
    message retry, and failed inbox-store retry
  - handle repeated readiness transitions without one send per transition
  - make feature-flag behavior explicit relative to `enableResumeGroupRecovery`
    or a narrower flag chosen during planning
  - emit local outgoing status or rows-changed signals for queued/retrying/sent
    transitions that an open conversation can observe
  - preserve `GroupRecoveryGate` protections and announcement
    `group_recovery_pending` behavior rather than bypassing active recovery
- Why it is its own session:
  - this session owns automatic recovery and lifecycle/readiness orchestration,
    which has a wider blast radius than manual retry identity
  - it depends on `GFR-001` so automatic recovery can be idempotent by design
- Likely code-entry files:
  - `lib/features/p2p/domain/models/node_state.dart`
  - the existing p2p/node-state listener or app wiring that observes
    `NodeState`
  - `lib/core/lifecycle/handle_app_resumed.dart`
  - `lib/features/groups/application/group_recovery_gate.dart`
  - `lib/features/groups/application/send_group_message_use_case.dart`
  - `lib/features/groups/application/retry_failed_group_messages_use_case.dart`
  - `lib/features/groups/application/recover_stuck_sending_group_messages_use_case.dart`
  - `lib/features/groups/domain/repositories/group_message_repository.dart`
  - `lib/features/groups/domain/repositories/group_message_repository_impl.dart`
- Likely direct tests/regressions:
  - `test/core/lifecycle/handle_app_resumed_group_recovery_test.dart`
  - `test/core/lifecycle/handle_app_resumed_group_inbox_retry_test.dart`
  - `test/core/lifecycle/handle_app_resumed_group_stuck_sending_test.dart`
  - `test/features/groups/application/send_group_message_use_case_test.dart`
  - `test/features/groups/application/retry_failed_group_messages_use_case_test.dart`
  - `test/features/groups/application/recover_stuck_sending_group_messages_use_case_test.dart`
  - `test/features/groups/domain/repositories/group_message_repository_impl_test.dart`
  - add focused tests for send-while-offline queued-once, relay-ready drain
    exactly-once, readiness flapping, resume/auto coalescing, flag behavior, and
    local status event emission
- Likely named gates:
  - direct lifecycle/application/repository suites above are mandatory
  - `./scripts/run_test_gates.sh groups` for group send/retry/resume changes
  - `./scripts/run_test_gates.sh transport` if the implementation touches
    bridge, reconnect, transport fallback, app bootstrap, or integration-test
    readiness wiring
- Matrix/closure docs to update when done:
  - update this breakdown ledger only during session closure
  - final stable group closure/gate docs stay with `GFR-005`
- Dependency on earlier sessions:
  - `GFR-001`
- Downstream execution path:
  - `$implementation-plan-orchestrator`
  - `$implementation-execution-qa-orchestrator`
  - `$implementation-closure-audit-orchestrator`

### Session GFR-003

- Title:
  `Open conversation recovery UX`
- Session id:
  `GFR-003`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/108-group-failed-message-retry-duplicate-send-ux-session-GFR-003-plan.md`
- Exact scope:
  - update the group conversation surface so a failed or queued text attempt is
    represented once and the composer does not present the same unchanged text
    as a second independent Send path
  - show retry/send-now, queued, or in-progress state as an idempotent nudge for
    the existing attempt rather than a fresh send opportunity
  - disable, coalesce, or visibly settle repeated Retry taps while recovery is
    already in flight
  - keep read-only, dissolved, and announcement `GroupRecoveryGate` states from
    inviting an impossible or duplicate recovery
  - keep failed media retry/delete controls available and keep text rows out of
    failed-media controls
  - preserve quote context behavior without leaving a stale quote/text draft
    that can resend the same failed attempt independently
  - prove an already-open conversation observes queued/retry/sent/failed
    updates in place through the existing local row-change mechanism
- Why it is its own session:
  - this session owns the user-visible trust bug after the data/recovery
    contracts exist
  - it can be verified through widget/wired tests without broadening lifecycle
    acceptance
- Likely code-entry files:
  - `lib/features/groups/presentation/screens/group_conversation_wired.dart`
  - `lib/features/groups/presentation/screens/group_conversation_screen.dart`
  - `lib/features/groups/presentation/widgets/group_compose_area.dart`
  - group message row/action presentation helpers adjacent to failed media
    retry/delete controls
- Likely direct tests/regressions:
  - `test/features/groups/presentation/group_conversation_wired_test.dart`
  - `test/features/groups/presentation/group_conversation_screen_test.dart`
  - add focused tests for failed text no restored duplicate composer path,
    rapid retry tap in-progress state, Retry-plus-Send same-attempt coalescing,
    queued row composer-cleared behavior, read-only/recovery-gate state, quote
    preservation, and failed media preservation
- Likely named gates:
  - direct presentation suites above are mandatory
  - `./scripts/run_test_gates.sh groups` if presentation wiring changes shared
    group send/retry behavior
  - no Startup/Transport gate unless this session expands into node readiness
    or app lifecycle wiring
- Matrix/closure docs to update when done:
  - update this breakdown ledger only during session closure
  - final stable docs stay with `GFR-005`
- Dependency on earlier sessions:
  - `GFR-001`, `GFR-002`
- Downstream execution path:
  - `$implementation-plan-orchestrator`
  - `$implementation-execution-qa-orchestrator`
  - `$implementation-closure-audit-orchestrator`

### Session GFR-004

- Title:
  `Lifecycle, integration, and gate acceptance`
- Session id:
  `GFR-004`
- Session classification:
  `acceptance-only`
- Intended plan file:
  `Test-Flight-Improv/108-group-failed-message-retry-duplicate-send-ux-session-GFR-004-plan.md`
- Exact scope:
  - verify the combined sender/recipient journey after `GFR-001` through
    `GFR-003`: failed text recovery, Retry-plus-Send, automatic retry racing
    manual retry, send-while-offline auto-delivery, pending/in-doubt recovery,
    multiple queued texts in order, app resume racing relay-ready recovery,
    active `GroupRecoveryGate`, and open-conversation status updates
  - verify `retryFailedGroupInboxStores(...)` still drains eligible message rows
    and reaction replay rows according to its existing message-first ownership
    model
  - run direct integration suites and named gates required by the landed diffs,
    and classify any unavailable simulator/device evidence honestly
  - update `Test-Flight-Improv/test-gate-definitions.md` only if the landed
    tests add or reclassify named-gate membership
  - leave the final stable source/closure doc verdict for `GFR-005`
- Why it is its own session:
  - this is cross-seam acceptance that should run after the implementation
    seams exist, so it can catch integration gaps without mixing them into UI or
    recovery-owner implementation
- Likely code-entry files:
  - primarily test and harness files; production edits are allowed only for
    defects discovered by acceptance proof inside the `GFR-001` through
    `GFR-003` scope
  - `test/features/groups/integration/group_messaging_smoke_test.dart`
  - `test/features/groups/integration/group_resume_recovery_test.dart`
  - `test/features/groups/integration/group_edge_cases_smoke_test.dart`
  - `integration_test/group_recovery_e2e_test.dart` or existing group
    multi-device scripts only when available and required
  - `Test-Flight-Improv/test-gate-definitions.md`
- Likely direct tests/regressions:
  - direct application, lifecycle, repository, wired, and screen suites touched
    by `GFR-001` through `GFR-003`
  - `test/features/groups/integration/group_messaging_smoke_test.dart`
  - `test/features/groups/integration/group_resume_recovery_test.dart`
  - `test/features/groups/integration/group_edge_cases_smoke_test.dart`
  - `test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart`
  - simulator/device proof for at least one multi-user group recovery journey
    when devices/fixtures are available; otherwise record an exact
    external-fixture blocker or residual-only limitation
- Likely named gates:
  - `./scripts/run_test_gates.sh groups` is mandatory
  - `./scripts/run_test_gates.sh transport` is mandatory if relay-ready,
    reconnect, transport fallback, app bootstrap, or integration-test lifecycle
    wiring changed
  - `./scripts/run_test_gates.sh baseline` should run before final acceptance
    if broad presentation or startup wiring changed
  - `./scripts/run_test_gates.sh completeness-check` is mandatory if new tests
    are added or gate docs change
- Matrix/closure docs to update when done:
  - this breakdown ledger
  - `Test-Flight-Improv/test-gate-definitions.md` only if classification changes
- Dependency on earlier sessions:
  - `GFR-001`, `GFR-002`, `GFR-003`
- Downstream execution path:
  - `$implementation-plan-orchestrator`
  - `$implementation-execution-qa-orchestrator`
  - `$implementation-closure-audit-orchestrator`

### Session GFR-005

- Title:
  `Group retry duplicate UX closure docs`
- Session id:
  `GFR-005`
- Session classification:
  `closure-only`
- Intended plan file:
  `Test-Flight-Improv/108-group-failed-message-retry-duplicate-send-ux-session-GFR-005-plan.md`
- Exact scope:
  - reconcile Report 108 against the landed implementation and acceptance
    evidence
  - update this breakdown ledger and write the final program verdict using only
    the allowed verdicts `closed`, `accepted_with_explicit_follow_up`,
    `residual_only`, or `still_open`
  - update `Test-Flight-Improv/108-group-failed-message-retry-duplicate-send-ux.md`
    with the final accepted behavior, evidence, residuals, and reopen rules
  - update `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`
    if the group discussion reliability closure bar or evidence changed
  - update the relevant group matrix docs only when landed evidence truthfully
    closes, covers, or reclassifies existing rows
  - update `Test-Flight-Improv/test-gate-definitions.md` only when named gate
    membership or classification changed
  - run closure review checks for stale open claims, overclaims, accidental
    1:1/media/reaction scope expansion, and diff hygiene
- Why it is its own session:
  - final documentation must be written from actual evidence after all
    implementation and acceptance sessions have finished
- Likely code-entry files:
  - no production code expected
  - `Test-Flight-Improv/108-group-failed-message-retry-duplicate-send-ux.md`
  - `Test-Flight-Improv/108-group-failed-message-retry-duplicate-send-ux-session-breakdown.md`
  - `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix.md`
  - `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md`
  - `Test-Flight-Improv/Group-Chat-Feature/Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md`
  - `Test-Flight-Improv/test-gate-definitions.md`
- Likely direct tests/regressions:
  - no new behavioral tests unless closure review finds a small doc-owned
    missing evidence check
  - `git diff --check`
  - targeted stale-wording and overclaim searches across touched docs
  - rerun only the minimum direct suite or gate needed if closure review exposes
    an evidence mismatch
- Likely named gates:
  - no new named gate unless docs or test classification changed
  - `./scripts/run_test_gates.sh completeness-check` if gate definitions or test
    classification changed
- Matrix/closure docs to update when done:
  - source doc, this breakdown, group closure reference, relevant group matrix
    docs, and gate definitions as scoped above
- Dependency on earlier sessions:
  - `GFR-004`
- Downstream execution path:
  - `$implementation-plan-orchestrator`
  - `$implementation-execution-qa-orchestrator`
  - `$implementation-closure-audit-orchestrator`

## Why this is not fewer sessions

- Manual retry identity, queued auto-send orchestration, and open conversation
  UX touch different risk surfaces and have different direct regressions.
- Combining `GFR-001` and `GFR-002` would mix row/message identity work with
  lifecycle/readiness ownership, making it too easy to accept one without
  proving the other.
- Combining `GFR-003` with lower-layer work would hide the exact composer and
  repeated-tap user-visible duplicate path behind application tests.
- Acceptance and closure must stay separate because the final docs can only be
  truthful after all code and gate evidence has landed.

## Why this is not more sessions

- Quote handling, failed media preservation, read-only behavior, and
  `GroupRecoveryGate` presentation are part of the same open conversation UX
  surface and should be verified together.
- `pending` recovery, same-row failed retry, and receiver duplicate suppression
  are one attempt-identity contract; splitting them would create redundant
  plans with shared owner files and shared tests.
- Reaction replay coexistence is an acceptance boundary for the existing inbox
  retry pass, not a new reaction feature implementation session.
- Device/simulator evidence should be planned in the acceptance session from
  the landed code, not guessed as a separate implementation seam up front.

## Regression and gate contract

- `Test-Flight-Improv/14-regression-test-strategy.md` applies because Report
  108 changes user-visible send recovery behavior and shared group reliability
  paths. Each production bug fixed by this rollout must leave a permanent
  focused regression.
- `Test-Flight-Improv/test-gate-definitions.md` is the named-gate source of
  truth. Current relevant gates are:
  - direct feature-local application, repository, lifecycle, wired, screen, and
    integration suites for the exact touched files
  - `./scripts/run_test_gates.sh groups` for group send, receive, retry,
    resume, invite, metadata/photo authority, or announcement behavior changes
  - `./scripts/run_test_gates.sh transport` if bridge, resume, reconnect,
    transport fallback, or app bootstrap wiring changes
  - `./scripts/run_test_gates.sh baseline` before final acceptance when broad
    startup/presentation behavior changes
  - `./scripts/run_test_gates.sh completeness-check` if new tests are added or
    gate classifications change
- Heavy simulator/device evidence belongs to `GFR-004`. It must be attempted
  when fixtures are available and recorded honestly as unavailable or residual
  when they are not.

## Matrix update contract

- During sessions `GFR-001` through `GFR-004`, update this breakdown ledger and
  session plans with evidence; do not prematurely rewrite stable group closure
  docs as fully closed.
- `GFR-005` owns final stable doc reconciliation:
  - source Report 108 final state and reopen rules
  - this breakdown final program verdict
  - `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`
    if the group discussion reliability closure statement changes
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix.md` only if a
    still-open or partial row is truthfully affected by landed evidence
  - `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md`
    and
    `Test-Flight-Improv/Group-Chat-Feature/Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md`
    only if existing covered rows need truthful evidence updates
  - `Test-Flight-Improv/test-gate-definitions.md` only if gate membership or
    classification changed

## Downstream execution path

For each runnable session in ledger order:

- `$implementation-plan-orchestrator`
- `$implementation-execution-qa-orchestrator`
- `$implementation-closure-audit-orchestrator`

After all runnable sessions are resolved:

- run the `$implementation-session-pipeline-orchestrator` final whole-program
  acceptance pass
- persist exactly one final program verdict in this breakdown:
  `closed`, `accepted_with_explicit_follow_up`, `residual_only`, or
  `still_open`

## Final Program Verdict

Final program verdict: `closed`

Verdict date: 2026-06-06 17:26 CEST

Reason: GFR-001 through GFR-005 have all resolved. Report 108's closure bar is
met for repo-owned group text failed/queued/pending retry duplicate-send UX:
one user intent is represented by one stable outgoing attempt across failed,
queued, retrying, pending/in-doubt, sent, and delivered states; manual Retry,
repeated Retry taps, Retry overlapping Send, relay-ready auto recovery, and
app-resume recovery coalesce; open group conversations observe one row
settling in place; failed media, reaction replay, receiver dedupe, distinct
intentional same-text sends, `GroupRecoveryGate`, and resume recovery ordering
remain preserved.

Closed sessions:

- `GFR-001`: stable group retry attempt contract accepted.
- `GFR-002`: queued auto-send and readiness coalescing accepted with explicit
  simulator follow-up.
- `GFR-003`: open conversation recovery UX closed.
- `GFR-004`: lifecycle, integration, named-gate, and simulator acceptance
  accepted.
- `GFR-005`: stable closure docs and final program verdict closed.

Accepted simulator evidence:

- `run_with_devices.sh group --list` passed and resolved a four-device group
  set:
  `279B82AE-2BB9-4924-9AAE-581870ED3FA9,116B4AF6-C1A9-4F36-B929-0A7130B5E83C,CD5929A6-EA0A-421D-A6D3-55BD707E0F76,5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`.
- `private_relay_reconnect_group_recovery` run `1780758396971` passed with
  orchestrator verdict `ok:true`, Alice/Bob/Charlie role verdicts, Alice
  publish debug `deliveryMode:"live_and_inbox"`, `expectedRecipientCount:2`,
  `inboxStored:true` for `aliceMissedDuringRelayDrop`, and Bob proof JSON
  `gmp_1780758396971_bob_received_aliceMissedDuringRelayDrop.json` with
  `liveOnly:false`, `usedOfflineDrain:true`, and `persistedCount:1`.
- `private_background_resume_group_delivery` run `1780758894898` passed with
  orchestrator verdict `ok:true`, Alice/Bob/Charlie role verdicts, Alice
  publish debug `deliveryMode:"live_and_inbox"`, `expectedRecipientCount:2`,
  `inboxStored:true` for `aliceDuringBackgroundBeforeEdit`, and Bob proof JSON
  `gmp_1780758894898_bob_received_aliceDuringBackgroundBeforeEdit.json` with
  `liveOnly:false`, `usedOfflineDrain:true`, and `persistedCount:1`.
- In both accepted simulator runs Alice, Bob, and Charlie logged migration
  `074_group_message_logical_delivery_id` success and no missing
  `logical_delivery_id` schema failure appeared.

Docs updated by GFR-005:

- `Test-Flight-Improv/108-group-failed-message-retry-duplicate-send-ux.md`
- `Test-Flight-Improv/108-group-failed-message-retry-duplicate-send-ux-session-breakdown.md`
- `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`
- `Test-Flight-Improv/Group-Chat-Feature/Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md`

Docs intentionally not changed:

- `Test-Flight-Improv/test-gate-definitions.md`, because no named-gate
  membership or classification changed.
- `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix.md`, because no
  open/partial row was reclassified by Report 108.
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md`,
  because the relevant private reliability rows were already covered and did
  not need a truthful status change for Report 108 closure.

Residual-only items: none for Report 108.

Accepted differences:

- This is a client-side group text send/retry/recovery closure, not a
  relay-side uniqueness guarantee, per-recipient ACK guarantee, read-receipt
  guarantee, or group status-model redesign.
- Existing receipt-less group semantics remain accepted: `sent` means the
  sender pipeline is durably closed under current group architecture, not that
  every member has acknowledged receipt.

Reopen rule: reopen Report 108 only if a failed, queued, retrying, pending, or
auto-recovered group text can again produce a second sender-visible row or
second recipient-visible delivery for one user intent; if no-usable-transport
group sends stop queueing once and auto-recovering once; if pending rows are
again stranded outside recovery; if open conversation recovery resurrects the
same failed text as a separate composer send opportunity; if receiver
message-id/logical-delivery dedupe regresses; or if the accepted GFR-004 target
messages stop producing Bob received-proof and role verdict artifacts in the
required simulator lifecycle scenarios.

## Reviewer and arbiter notes

- Recommended session count is sufficient rather than too coarse because the
  split follows the main ownership seams: application attempt identity, recovery
  orchestration, open-conversation UX, cross-seam acceptance, and closure docs.
- No proposed sessions should merge; the nearest merge candidates
  `GFR-001`/`GFR-002` have different triggers, direct tests, and blast radius.
- No proposed session needs an up-front split. If planning discovers schema
  migration or bridge/native work is unavoidable, that should be recorded in the
  active session plan and split only when the planner proves it has independent
  closure value.
- Structural blockers remaining:
  none for downstream planning.
- Accepted differences intentionally left unchanged:
  - no relay-side or wire-protocol dedupe change is planned from this spec
  - no database uniqueness mandate for logical delivery id is planned
  - no failed media UX redesign is planned beyond preservation
  - reaction replay UX stays out of scope except for preserving the existing
    retry ownership boundary

## Exact docs/files used as evidence

- `Test-Flight-Improv/108-group-failed-message-retry-duplicate-send-ux.md`
- `Test-Flight-Improv/78-message-send-failure-retry-ux-session-breakdown.md`
- `Test-Flight-Improv/78-message-send-failure-retry-ux.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`
- `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix.md`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md`
- `Test-Flight-Improv/Group-Chat-Feature/Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md`
- `lib/features/groups/presentation/screens/group_conversation_wired.dart`
- `lib/features/groups/presentation/screens/group_conversation_screen.dart`
- `lib/features/groups/application/send_group_message_use_case.dart`
- `lib/features/groups/application/retry_failed_group_messages_use_case.dart`
- `lib/features/groups/application/retry_failed_group_inbox_stores_use_case.dart`
- `lib/features/groups/application/handle_incoming_group_message_use_case.dart`
- `lib/core/lifecycle/handle_app_resumed.dart`
- `lib/features/groups/application/group_recovery_gate.dart`
- `lib/features/p2p/domain/models/node_state.dart`
- `lib/features/groups/domain/repositories/group_message_repository.dart`
- `lib/features/groups/domain/repositories/group_message_repository_impl.dart`
- `test/features/groups/presentation/group_conversation_screen_test.dart`
- `test/features/groups/presentation/group_conversation_wired_test.dart`
- `test/features/groups/application/send_group_message_use_case_test.dart`
- `test/features/groups/application/retry_failed_group_messages_use_case_test.dart`
- `test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart`
- `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`
- `test/features/groups/domain/repositories/group_message_repository_impl_test.dart`
- `test/core/lifecycle/handle_app_resumed_group_recovery_test.dart`
- `test/features/groups/integration/group_messaging_smoke_test.dart`
- `test/features/groups/integration/group_resume_recovery_test.dart`
- `test/features/groups/integration/group_edge_cases_smoke_test.dart`
- `graphify query "group failed message retry duplicate send queue auto reconnect pending relayReady GroupRecoveryGate retryFailedGroupMessages"`

## Why the decomposition is safe to send into downstream planning/execution

- It leaves a reusable artifact at the required adjacent path.
- Every intended plan path is doc-scoped and non-colliding.
- The ledger gives each session an explicit dependency state and current status.
- The ordered breakdown names exact scope, owner files, direct tests, named
  gates, and matrix/closure docs for each session.
- The final closure bar and matrix update contract prevent partial session
  progress from being mistaken for a completed Report 108 rollout.
