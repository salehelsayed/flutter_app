Status: reusable-breakdown

# Group Chat Invited vs Accepted Message Notifications Session Breakdown

## Recommended plan count

4 session plans.

## Decomposition artifact

- Artifact path: `Test-Flight-Improv/106-group-chat-invited-vs-accepted-message-notifications-session-breakdown.md`
- Proposal or source doc path: `Test-Flight-Improv/106-group-chat-invited-vs-accepted-message-notifications.md`
- Downstream workflow rule: detailed planning happens one session at a time.
- Refresh rule: later sessions must be refreshed against landed code before execution, especially after the recipient-eligibility session because it may change the Flutter-to-Go reliable send boundary.

## Overall closure bar

After all sessions finish, an invited-but-not-accepted group contact must not be treated as an ordinary group message recipient, must not receive a group-message push or local fallback notification that opens to no messages, and must remain distinguishable from an accepted/current member in creator/admin surfaces. Valid pending invites remain visible and actionable through the user-facing lifecycle; expired, declined, revoked, invalid, stale, or never-stored invites produce understandable non-joined outcomes rather than silent missing context. Accepted members keep the existing group message, notification, active-view suppression, duplicate-suppression, and notification-tap behavior. Final evidence must include direct regressions, integration/smoke proof for mixed accepted/unaccepted invitees, relay push fanout proof, foreground/background notification suppression proof, simulator evidence, and matrix/closure doc updates.

## Source of truth

- Product intent: `Test-Flight-Improv/106-group-chat-invited-vs-accepted-message-notifications.md`
- Regression model: `Test-Flight-Improv/14-regression-test-strategy.md`
- Named gates: `Test-Flight-Improv/test-gate-definitions.md`
- Stable notification matrix: `Test-Flight-Improv/52-notification-journey-test-matrix.md`
- Stable group matrix/closure docs: `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`, `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`
- Adjacent invite/status and foreground push docs: `Test-Flight-Improv/91-group-invitation-status-visibility.md`, `Test-Flight-Improv/71-foreground-group-push-drain-gap-plan.md`
- Invite lifecycle files inspected: `lib/features/groups/domain/models/pending_group_invite.dart`, `lib/features/groups/domain/models/group_invite_payload.dart`, `lib/features/groups/application/group_invite_auth.dart`, `lib/features/groups/application/send_group_invite_use_case.dart`, `lib/features/groups/application/handle_incoming_group_invite_use_case.dart`, `lib/features/groups/application/group_invite_listener.dart`, `lib/features/groups/domain/repositories/pending_group_invite_repository_impl.dart`
- Message eligibility and creator-status files inspected: `lib/features/groups/application/create_group_with_members_use_case.dart`, `lib/features/groups/application/send_group_message_use_case.dart`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/domain/models/group_invite_delivery_attempt.dart`, `lib/features/groups/presentation/screens/group_info_wired.dart`
- Native/relay files inspected: `go-mknoon/node/pubsub.go`, `go-mknoon/node/group_inbox.go`, `go-relay-server/inbox.go`, `go-relay-server/inbox_test.go`
- Push/routing files inspected: `lib/features/push/application/background_push_notification_fallback.dart`, `lib/features/push/application/background_message_handler.dart`, `lib/features/push/application/handle_foreground_remote_message_use_case.dart`, `lib/features/push/application/resolve_group_notification_route_target_use_case.dart`, `lib/core/notifications/notification_route_target.dart`, `lib/main.dart`
- Direct test families inspected or identified: group invite listener/payload/store/repository tests, group send/message/listener/status tests, push fallback/foreground/background/route tests, notification deeplink tests, group messaging smoke tests, foreground group push simulator/drain tests, and Go relay inbox tests.

## Run mode snapshot

- Last refreshed: 2026-06-04 20:12 CEST
- Active mode: `standard`
- Degraded local continuation explicitly allowed: not as a broad controller
  mode. Session `01-invite-lifecycle` used a recorded local sequential fallback
  after spawned planning/execution attempts no-progressed, and this closure
  audit accepts that evidence for session `01` only. Sessions `02`, `03`, and
  `04` now have their own execution, QA, evidence, and closure records under
  the current ledger.
- Source proposal path: `Test-Flight-Improv/106-group-chat-invited-vs-accepted-message-notifications.md`
- Source row/status vocabulary: this doc uses the session ledger statuses `pending`, `accepted`, `accepted_with_explicit_follow_up`, `stale/already-covered`, `skipped_due_to_dependency`, `blocked`, and `prerequisite-blocked`; final program verdicts are `closed`, `accepted_with_explicit_follow_up`, `residual_only`, and `still_open`.
- Overall closure bar: all four sessions must satisfy the closure bar above, including direct regressions, integration/smoke proof, relay push fanout proof, foreground/background notification suppression proof, simulator evidence, and matrix/closure doc updates.
- Final verdict policy for this run: `closed` only when every required session is accepted with final evidence and no meaningful deferred work remains; `still_open` when any required session cannot run, remains blocked, lacks execution/closure evidence, or the overall closure bar is unmet.

## Controller Progress

- 2026-06-04 20:27 CEST - Phase: session `03-notification-suppression-routing` planning completed and execution/QA handoff started. Files inspected/updated: this breakdown and `Test-Flight-Improv/106-group-chat-invited-vs-accepted-message-notifications-session-03-notification-suppression-routing-plan.md`. Decision/blocker: no blocker; a fresh `$implementation-plan-orchestrator` child produced an `execution-ready` plan with receiver-side notification suppression, tap-routing hardening, direct tests, named gates, and simulator closure requirements. Next action: spawn a fresh `$implementation-execution-qa-orchestrator` child with `model: gpt-5.5` and `reasoning_effort: xhigh` for session `03`.
- 2026-06-04 20:43 CEST - Phase: session `03-notification-suppression-routing` execution in progress. Files inspected/updated: this breakdown and `Test-Flight-Improv/106-group-chat-invited-vs-accepted-message-notifications-session-03-notification-suppression-routing-plan.md`; scoped notification suppression/routing code and focused tests are recorded in the session plan. Decision/blocker: no final session verdict yet; initial spawned Executor no-resulted and was closed, local fallback is now running under the execution skill contract, with RED evidence confirmed and the first three focused push suites passing after production wiring. Next action: continue remaining direct tests, named gates, simulator gate classification, then local QA and persisted session 03 execution verdict.
- 2026-06-04 21:11 CEST - Phase: session `03-notification-suppression-routing` execution QA handoff. Files inspected/updated: this breakdown and `Test-Flight-Improv/106-group-chat-invited-vs-accepted-message-notifications-session-03-notification-suppression-routing-plan.md`; existing foreground and notification-open simulator files were extended rather than adding new files. Decision/blocker: no final session verdict yet; direct tests, named gates, and both required reliability simulator commands are now recorded as passed in the session plan, including foreground S3 missing/non-current fallback suppression and notification-open pending/missing tap rows. Next action: run the fresh QA Reviewer, apply bounded fixes only if QA finds a blocker, then persist the session 03 execution/QA verdict without closing session `04`.
- 2026-06-04 21:18 CEST - Phase: session `03-notification-suppression-routing` fix loop 2 running. Files inspected/updated: this breakdown, active child-process state, and `Test-Flight-Improv/106-group-chat-invited-vs-accepted-message-notifications-session-03-notification-suppression-routing-plan.md`. Decision/blocker: no terminal current-doc blocker and no session verdict yet; post-fix QA found a second same-session issue where foreground fallback reused background eligibility and skipped current-member foreground `group_message` fallback when `RemoteMessage.notification` was present. A bounded fix loop is running under the fresh execution/QA contract to split foreground eligibility while preserving background provider-visible suppression. Next action: keep polling the fresh `$implementation-execution-qa-orchestrator` child to a persisted session 03 execution verdict, then run session `03` closure before advancing to session `04`.
- 2026-06-04 21:38 CEST - Phase: session `03-notification-suppression-routing` execution verdict persisted; closure audit handoff. Files inspected/updated: this breakdown and `Test-Flight-Improv/106-group-chat-invited-vs-accepted-message-notifications-session-03-notification-suppression-routing-plan.md`. Decision/blocker: no blocker; session `03` execution/QA verdict is `accepted` after two bounded QA fix loops, clean QA, post-fix direct rerun, named gates, runtime telemetry gate, and both simulator commands passed. The execution child completed evidence but its final artifact patch failed on stale context, so the controller used local bounded fallback for the verdict only. Next action: spawn a fresh `$implementation-closure-audit-orchestrator` child with `model: gpt-5.5` and `reasoning_effort: xhigh` to audit/close session `03`, update ledger/source as needed, then advance to session `04`.
- 2026-06-04 21:43 CEST - Phase: session `03-notification-suppression-routing` closure audit completed by bounded local fallback. Files inspected/updated: this breakdown, the source doc, and `Test-Flight-Improv/106-group-chat-invited-vs-accepted-message-notifications-session-03-notification-suppression-routing-plan.md`. Decision/blocker: no session `03` blocker; the fresh closure-audit child no-progressed after its Completion Auditor handoff and produced no artifact, so the controller terminated it and performed Completion Auditor, Closure Writer, and Closure Reviewer locally against the persisted execution evidence. Session `03` is closed as `accepted`; session `04-acceptance-closure` remains runnable and owns final mixed-recipient acceptance and matrix/final verdict closure. Next action: begin session `04` planning with a fresh `$implementation-plan-orchestrator` child using `model: gpt-5.5` and `reasoning_effort: xhigh`.
- 2026-06-04 21:45 CEST - Phase: session `04-acceptance-closure` planning started. Files inspected/updated: this breakdown and session `04` intended plan path. Decision/blocker: no blocker; no reusable session `04` plan exists, and dependencies `01`, `02`, and `03` are closed under their session contracts. Next action: spawn a fresh `$implementation-plan-orchestrator` child with `model: gpt-5.5` and `reasoning_effort: xhigh` to write `Test-Flight-Improv/106-group-chat-invited-vs-accepted-message-notifications-session-04-acceptance-closure-plan.md`.
- 2026-06-04 21:55 CEST - Phase: session `04-acceptance-closure` planning completed and execution/QA handoff started. Files inspected/updated: this breakdown and `Test-Flight-Improv/106-group-chat-invited-vs-accepted-message-notifications-session-04-acceptance-closure-plan.md`. Decision/blocker: no blocker; session `04` now has an `execution-ready` acceptance-only plan requiring final mixed-recipient acceptance evidence, simulator proof for `private_invite_terminal_states`, rerun foreground/open simulator proof, targeted Go/relay gates, named gates, completeness-check, and matrix/source/breakdown final verdict updates. The planning child no-progressed after `planning-draft`, so the controller completed Planner/Reviewer/Arbiter locally under bounded fallback and recorded that in the plan. Next action: spawn a fresh `$implementation-execution-qa-orchestrator` child with `model: gpt-5.5` and `reasoning_effort: xhigh` for session `04`.

## Closure Progress

- 2026-06-04 22:31 CEST | Session `04-acceptance-closure` closure audit started | Files inspected or updated: this breakdown, `Test-Flight-Improv/106-group-chat-invited-vs-accepted-message-notifications-session-04-acceptance-closure-plan.md`, `Test-Flight-Improv/106-group-chat-invited-vs-accepted-message-notifications.md`, scoped session 04 simulator harness/criteria files, and stable Report 106 matrix/closure docs as needed | Tentative verdict: evidence appears acceptable but is not final until Completion Auditor, Closure Writer, and Closure Reviewer finish against the persisted plan evidence and scoped diffs. | Next action: run the sequential closure audit/write/review pass and update stable docs plus this session ledger without writing the separate final program verdict.
- 2026-06-04 22:35 CEST | Session `04-acceptance-closure` closure audit write pass completed | Files inspected or updated: this breakdown, `Test-Flight-Improv/106-group-chat-invited-vs-accepted-message-notifications-session-04-acceptance-closure-plan.md`, `Test-Flight-Improv/106-group-chat-invited-vs-accepted-message-notifications.md`, `Test-Flight-Improv/52-notification-journey-test-matrix.md`, `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`, `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`, `Test-Flight-Improv/test-gate-definitions.md`, `integration_test/group_multi_party_device_real_harness.dart`, and `integration_test/scripts/group_multi_party_device_criteria.dart` | Decision: session `04` execution verdict is `accepted`; the `INV-106` host smoke, Report 106 `private_invite_terminal_states` simulator fields, targeted Go/relay evidence, named gates, foreground simulator, and notification-open reliability smoke satisfy the session closure bar. | Next action: Closure Reviewer pass for overclaiming, residual-only notes, and scoped diff hygiene.
- 2026-06-04 22:38 CEST | Session `04-acceptance-closure` Closure Reviewer completed | Files inspected or updated: this breakdown, source report, notification matrix, libp2p group matrix, group reliability closure reference, test gate definitions, scoped simulator harness/criteria diffs, stale-open wording scan, APNs/provider residual scan, `TestGL019ConcurrentJoinLeaveUpdateSameGroupIsRaceFree` residual scan, and diff hygiene checks | Decision: session `04` is `accepted` and closure docs are safe as stable references. No overclaim found: provider APNs/FCM proof is residual-only, `91-group-invitation-status-visibility.md` was left untouched because no new creator/status UI evidence landed, and the final program verdict was intentionally left for the separate acceptance agent at that checkpoint. | Next action: superseded by the final program verdict below; do not reopen session `04` unless the recorded host/simulator/Go/relay/named-gate evidence regresses.
- 2026-06-04 18:00 CEST | Session `01-invite-lifecycle` closure audit completed | Files inspected: session 01 plan, source doc, scoped invite lifecycle diffs, gate evidence, and this breakdown | Decision: session `01` is `accepted` and closed. The normal membership freshness proof now aligns with the visible pending invite lifecycle, delayed-but-policy-valid parse/store/listener/accept regressions passed, explicit shortened/stale freshness rejection remains covered, `./scripts/run_test_gates.sh groups` passed, and simulator scenario 5 passed. At that checkpoint, sessions `02-recipient-eligibility`, `03-notification-suppression-routing`, and `04-acceptance-closure` were still pending; the current ledger below supersedes that historical status. No final mixed-recipient, relay fanout, notification suppression, or matrix closure was claimed by session `01`. | Next action: plan/execute session `02-recipient-eligibility`.
- 2026-06-04 20:12 CEST | Session `02-recipient-eligibility` closure audit completed | Files inspected: session 02 plan, source doc, scoped send/retry/bridge/native reliable-send diffs, focused Flutter/Go regression evidence, latest `/tmp/session02-fixpass3-*` gate logs, and this breakdown | Decision: session `02` is `accepted_with_explicit_follow_up` and closed for recipient eligibility. Ordinary group-message sender fanout now excludes persisted non-joined invite attempts while preserving accepted `joined` members and legacy/current members without attempt rows; Dart replay, `group:inboxStore`, native `group:sendReliable`, and Go relay custody preserve the same explicit accepted recipient list, including explicit empty lists; creator/admin direct evidence keeps non-joined statuses distinct from accepted membership. The only follow-up is the out-of-scope full Go sweep failure `TestGL019ConcurrentJoinLeaveUpdateSameGroupIsRaceFree`, a native topic join/leave/update lifecycle issue unrelated to session 02 recipient eligibility. At that checkpoint, sessions `03-notification-suppression-routing` and `04-acceptance-closure` were not yet closed; the current ledger supersedes that historical status. | Next action at that checkpoint: plan/execute session `03-notification-suppression-routing`.
- 2026-06-04 21:43 CEST | Session `03-notification-suppression-routing` closure audit completed | Files inspected: session 03 plan, source doc, scoped push fallback/background/route diffs, foreground and notification-open simulator diffs, direct/named/simulator gate evidence in the plan, and this breakdown | Decision: session `03` is `accepted` and closed for receiver-side notification suppression and tap routing. Ordinary group-message fallback now requires current local membership, pending/missing/unknown/non-member states fail closed, legacy payload-only group routes are covered, accepted/current members keep foreground/background fallback behavior, and `group_invite` still routes to Intros. Direct push/route/deeplink/dedupe tests, `groups`, `baseline`, `runtime-telemetry`, foreground group push simulator S3, and notification-open current/pending/missing simulator rows are recorded as passed. At that checkpoint, session `04-acceptance-closure` was not yet closed; the current ledger supersedes that historical status and no final program verdict was claimed by session `03`. | Next action at that checkpoint: plan/execute session `04-acceptance-closure`.

## Session ledger

| Session id | Title | Classification | Intended plan file | Depends on | Current status |
|---|---|---|---|---|---|
| `01-invite-lifecycle` | Align invite freshness with visible pending/expired lifecycle | `implementation-ready` | `Test-Flight-Improv/106-group-chat-invited-vs-accepted-message-notifications-session-01-invite-lifecycle-plan.md` | none | `accepted` |
| `02-recipient-eligibility` | Gate group message recipients and relay push fanout on accepted membership | `implementation-ready` | `Test-Flight-Improv/106-group-chat-invited-vs-accepted-message-notifications-session-02-recipient-eligibility-plan.md` | `01-invite-lifecycle` | `accepted_with_explicit_follow_up` |
| `03-notification-suppression-routing` | Suppress dead-end group-message fallback notifications and harden tap routing | `implementation-ready` | `Test-Flight-Improv/106-group-chat-invited-vs-accepted-message-notifications-session-03-notification-suppression-routing-plan.md` | `01-invite-lifecycle`, `02-recipient-eligibility` | `accepted` |
| `04-acceptance-closure` | Prove mixed-recipient acceptance and close matrices/docs | `acceptance-only` | `Test-Flight-Improv/106-group-chat-invited-vs-accepted-message-notifications-session-04-acceptance-closure-plan.md` | `01-invite-lifecycle`, `02-recipient-eligibility`, `03-notification-suppression-routing` | `accepted` |

## Final program verdict

Final program verdict: `closed`

Recorded: 2026-06-04 final program acceptance pass.

Why closed:

- The session ledger is resolved as required: `01-invite-lifecycle` is
  `accepted`, `02-recipient-eligibility` is
  `accepted_with_explicit_follow_up`, `03-notification-suppression-routing` is
  `accepted`, and `04-acceptance-closure` is `accepted`.
- The source report records the Report 106 acceptance ledger as closed and no
  longer has active wording that session `04-acceptance-closure` still needs
  closure.
- Stable closure references now include the Report 106 rows/sections:
  notification matrix `INV-106`, libp2p group matrix `UX-016`, group
  reliability closure reference Report 106 section, and test gate definitions
  classification.
- The remaining notes are outside this report's closure bar: provider
  APNs/FCM/TestFlight delivery proof remains external to this repo-owned
  acceptance, and
  `TestGL019ConcurrentJoinLeaveUpdateSameGroupIsRaceFree` remains an unrelated
  native topic join/leave/update lifecycle follow-up.

Docs touched by session `04` closure: source report, notification journey
matrix, libp2p group chat matrix, group discussion closure reference, test gate
definitions, and this breakdown. `91-group-invitation-status-visibility.md`
was not changed because session `04` did not add or alter creator/status UI
evidence.

## Ordered session breakdown

### 1. Align invite freshness with visible pending/expired lifecycle

- Session id: `01-invite-lifecycle`
- Session classification: `implementation-ready`
- Intended plan file: `Test-Flight-Improv/106-group-chat-invited-vs-accepted-message-notifications-session-01-invite-lifecycle-plan.md`
- Exact scope: Align the hidden membership freshness proof and receive-time validation with the visible pending invite lifecycle. Preserve security rejection for tampered or invalid invites while preventing a shorter hidden freshness window from silently undercutting a still-valid pending invite. Keep stored-expired invite behavior distinguishable from receive-time non-storage, and ensure Orbit/Intro invite review can present valid, expired, or terminal invite states without collapsing them into a missing invite.
- Why it is its own session: This is a persistence/authentication/lifecycle seam. It has different direct tests from message fanout or push fallback and must land before downstream sessions rely on pending-vs-missing-vs-terminal state semantics.
- Likely code-entry files: `lib/features/groups/domain/models/group_invite_payload.dart`, `lib/features/groups/application/group_invite_auth.dart`, `lib/features/groups/application/send_group_invite_use_case.dart`, `lib/features/groups/application/handle_incoming_group_invite_use_case.dart`, `lib/features/groups/domain/models/pending_group_invite.dart`, `lib/features/groups/domain/repositories/pending_group_invite_repository_impl.dart`, `lib/core/database/helpers/pending_group_invites_db_helpers.dart`, `lib/features/orbit/presentation/screens/orbit_wired.dart`, `lib/features/groups/presentation/widgets/pending_group_invite_card.dart`
- Likely direct tests/regressions: `test/features/groups/domain/models/group_invite_payload_test.dart`, `test/features/groups/application/group_invite_listener_test.dart`, `test/features/groups/application/store_pending_group_invite_use_case_test.dart`, `test/features/groups/domain/repositories/pending_group_invite_repository_impl_test.dart`, Orbit/Intro pending invite widget or wired tests if visibility changes are needed.
- Likely named gates: direct invite suites first; `./scripts/run_test_gates.sh groups` because group invite behavior changes; direct Orbit/Intro tests if touched. Run `./scripts/run_test_gates.sh completeness-check` if new test files are added.
- Matrix/closure docs to update when done: defer durable matrix/closure updates to `04-acceptance-closure`; record any new test files in `Test-Flight-Improv/test-gate-definitions.md` only if classification is needed immediately.
- Dependency on earlier sessions: none.

### 2. Gate group message recipients and relay push fanout on accepted membership

- Session id: `02-recipient-eligibility`
- Session classification: `implementation-ready`
- Intended plan file: `Test-Flight-Improv/106-group-chat-invited-vs-accepted-message-notifications-session-02-recipient-eligibility-plan.md`
- Exact scope: Ensure ordinary group message recipient selection uses accepted/current membership evidence, not roster presence alone. Cover Flutter send-time recipient construction, offline replay recipient ids, reliable native group send behavior, group config or explicit recipient propagation, relay `group_store` fanout, and creator/admin status clarity that sent/queued/needs-resend/cannot-send/unknown is not accepted. Preserve normal delivery for accepted members in mixed groups.
- Why it is its own session: This is the core bug-prevention path. It crosses Flutter and native/relay code, but those halves are one behavioral boundary because a Dart-only filter is insufficient if native reliable send still derives recipients from a group config containing unaccepted invitees.
- Likely code-entry files: `lib/features/groups/application/send_group_message_use_case.dart`, `lib/features/groups/application/create_group_with_members_use_case.dart`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/domain/models/group_invite_delivery_attempt.dart`, `lib/features/groups/presentation/screens/group_info_wired.dart`, bridge/platform channel files that back `callGroupSendReliable` if explicit recipients are added, `go-mknoon/node/pubsub.go`, `go-mknoon/node/group_inbox.go`, `go-relay-server/inbox.go`
- Likely direct tests/regressions: `test/features/groups/application/send_group_message_use_case_test.dart`, `test/features/groups/application/create_group_with_members_use_case_test.dart`, `test/features/groups/application/group_message_listener_test.dart`, `test/features/groups/presentation/group_info_wired_test.dart`, `test/features/groups/presentation/group_info_screen_test.dart`, `test/features/groups/integration/group_messaging_smoke_test.dart`, `go-relay-server/inbox_test.go`, and Go tests under `go-mknoon` for reliable-send recipient behavior if the native boundary changes.
- Likely named gates: direct Flutter suites first; `./scripts/run_test_gates.sh groups`; `cd go-mknoon && go test ./...` if Go node code changes; `cd go-relay-server && go test ./...` if relay code or tests change; `./scripts/run_test_gates.sh baseline` after shared group behavior stabilizes.
- Matrix/closure docs to update when done: defer final evidence updates to `04-acceptance-closure`; if the session adds a new integration/simulator file, classify it in `Test-Flight-Improv/test-gate-definitions.md`.
- Dependency on earlier sessions: depends on `01-invite-lifecycle` for the accepted/pending/terminal state contract used by recipient eligibility tests.

### 3. Suppress dead-end group-message fallback notifications and harden tap routing

- Session id: `03-notification-suppression-routing`
- Session classification: `implementation-ready`
- Intended plan file: `Test-Flight-Improv/106-group-chat-invited-vs-accepted-message-notifications-session-03-notification-suppression-routing-plan.md`
- Exact scope: Add receiver-side defense so legacy, delayed, malformed, or incorrectly targeted `group_message` remote payloads do not produce foreground/background fallback notifications when the local recipient has no current group membership and no actionable pending invite. Preserve `group_invite` routing to Intros. Make missing group/missing invite tap handling produce an understandable outcome or telemetry-backed suppression rather than a silent dead end. Keep current-member group opens and pending-invite redirects intact.
- Why it is its own session: This is a push/routing seam, independent from sender recipient eligibility. It is needed for defense-in-depth and uses different direct tests and optional simulator evidence.
- Likely code-entry files: `lib/features/push/application/background_push_notification_fallback.dart`, `lib/features/push/application/background_message_handler.dart`, `lib/features/push/application/handle_foreground_remote_message_use_case.dart`, `lib/features/push/application/resolve_group_notification_route_target_use_case.dart`, `lib/core/notifications/notification_route_target.dart`, `lib/features/push/application/prepare_notification_route_target_use_case.dart`, `lib/features/push/application/prepare_notification_open_use_case.dart`, `lib/main.dart`
- Likely direct tests/regressions: `test/features/push/application/background_push_notification_fallback_test.dart`, `test/features/push/application/background_message_handler_test.dart`, `test/features/push/application/handle_foreground_remote_message_use_case_test.dart`, `test/features/push/application/resolve_group_notification_route_target_use_case_test.dart`, `test/features/push/application/chat_and_group_push_open_flow_test.dart`, `test/integration/notification_deeplink_integration_test.dart`, `test/integration/group_notification_dedupe_integration_test.dart`, `integration_test/foreground_group_push_drain_test.dart`
- Likely named gates: direct push suites first; `./scripts/run_test_gates.sh groups` if group drain/listener contracts are touched; `./scripts/run_test_gates.sh runtime-telemetry` if telemetry-gated push events change; optional foreground simulator command from `test-gate-definitions.md` if a simulator harness is used; `./scripts/run_test_gates.sh completeness-check` if adding new files.
- Matrix/closure docs to update when done: defer final matrix closure to `04-acceptance-closure`; update `Test-Flight-Improv/test-gate-definitions.md` immediately if new notification or simulator tests are added.
- Dependency on earlier sessions: depends on `01-invite-lifecycle` for pending-vs-missing semantics and on `02-recipient-eligibility` for the primary no-push invariant, but it must still defend against stale payloads.

### 4. Prove mixed-recipient acceptance and close matrices/docs

- Session id: `04-acceptance-closure`
- Session classification: `acceptance-only`
- Intended plan file: `Test-Flight-Improv/106-group-chat-invited-vs-accepted-message-notifications-session-04-acceptance-closure-plan.md`
- Exact scope: Run and, only where necessary, add acceptance evidence across the full reported journey: group creator invites multiple users, at least one accepts, at least one remains unaccepted or terminal/missing, creator sends ordinary group messages, accepted users receive normal message/notification behavior, and unaccepted or terminal invite states do not receive readable messages or dead-end group-message notifications. Include foreground/background fallback and tap routing states for current member, pending invite, terminal invite, and missing invite. Update stable matrices and closure docs with the final evidence.
- Why it is its own session: This validates all earlier implementation slices together and owns documentation closure. It should not run before the implementation sessions because otherwise it would either fail predictably or duplicate per-session direct tests.
- Likely code-entry files: primarily test harnesses and docs. Candidate harnesses include `test/features/groups/integration/group_messaging_smoke_test.dart`, `test/integration/notification_deeplink_integration_test.dart`, `integration_test/foreground_group_push_drain_test.dart`, `integration_test/scripts/run_foreground_group_push_simulator_smoke.dart`, `integration_test/scripts/run_group_multi_party_device_real.dart`, and notification tap simulator scripts if used.
- Likely direct tests/regressions: mixed accepted/unaccepted integration test, relay recipient and push fanout test, foreground fallback suppression test, background fallback/tap routing test, delayed invite freshness lifecycle test, and a negative matrix for pending, expired, declined, revoked/invalid, and missing-invite states.
- Likely named gates: `./scripts/run_test_gates.sh groups`, `./scripts/run_test_gates.sh baseline`, direct push and notification integration suites, `./scripts/run_test_gates.sh completeness-check`, Go test commands if cross-tree changes landed, and optional/nightly simulator commands documented in `test-gate-definitions.md` for foreground group push and multi-party group proof.
- Matrix/closure docs to update when done: `Test-Flight-Improv/52-notification-journey-test-matrix.md`, `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`, `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`, `Test-Flight-Improv/91-group-invitation-status-visibility.md` if creator/status evidence changed, `Test-Flight-Improv/test-gate-definitions.md` if new tests require classification, and the source doc's evidence/closure notes if the downstream closure workflow uses it.
- Dependency on earlier sessions: depends on `01-invite-lifecycle`, `02-recipient-eligibility`, and `03-notification-suppression-routing`.

## Why this is not fewer sessions

Three implementation seams have different contracts and failure modes: invite lifecycle/freshness controls whether a user has pending or terminal context; send/relay eligibility controls whether unaccepted invitees enter ordinary message and push fanout; receiver push/routing controls whether stale or legacy payloads produce dead-end notifications. Combining those with final acceptance would make failures hard to diagnose and would invite broad, cross-subsystem fixes without clear direct tests. The separate acceptance/closure session is required because the source doc explicitly rejects unit-only proof and requires integration, smoke, simulator, and matrix evidence across all earlier slices.

## Why this is not more sessions

Declined, expired, revoked, invalid, pending, and missing invite states should be test cases inside the same lifecycle, recipient-eligibility, and notification-suppression seams, not one session per state. Go/native/relay work is kept with recipient eligibility because splitting it from Flutter recipient selection would leave neither half able to prove the reported bug is fixed. Creator/admin wording is not a separate UI redesign session; it belongs to the accepted-vs-invited status checks in `02-recipient-eligibility` and the final smoke/closure pass. Exact copy, iconography, storage shape, and wire-format decisions remain downstream implementation details unless the plan finds a concrete blocker.

## Regression and gate contract

`Test-Flight-Improv/14-regression-test-strategy.md` applies because this is a production bug and needs at least one permanent regression, plus change-based gates for group, notification, and transport-adjacent seams. `Test-Flight-Improv/test-gate-definitions.md` is the named-gate source of truth.

- `01-invite-lifecycle`: run focused invite payload/store/listener/repository tests, any touched Orbit/Intro direct tests, then `./scripts/run_test_gates.sh groups`; run `completeness-check` if new files are added.
- `02-recipient-eligibility`: run focused group send/status/listener/integration tests, `./scripts/run_test_gates.sh groups`, Go tests for touched `go-mknoon` or `go-relay-server` code, then baseline once stable.
- `03-notification-suppression-routing`: run focused push fallback/background/foreground/route/open tests, notification deeplink/dedupe integration as applicable, `runtime-telemetry` only if telemetry-gated push events change, and optional simulator commands for foreground/background behavior.
- `04-acceptance-closure`: run the final direct/integration/smoke/simulator set, `groups`, `baseline`, `completeness-check`, and any Go gates touched by earlier sessions. Record known unrelated red tests rather than hiding them.

## Matrix update contract

Reuse existing stable docs; do not create a new matrix doc for this report.

- `Test-Flight-Improv/52-notification-journey-test-matrix.md`: add or update group notification rows for invited-but-unaccepted, terminal invite, and missing-invite group-message push suppression, plus pending invite redirect preservation.
- `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`: update invite accept/decline/expiry and group notification eligibility rows with final evidence.
- `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`: record final mixed-recipient and relay-fanout closure evidence if this doc remains the group closure reference.
- `Test-Flight-Improv/91-group-invitation-status-visibility.md`: update only if the implementation changes creator/admin status behavior or adds new evidence that sent/queued/needs-resend/cannot-send/unknown is not accepted.
- `Test-Flight-Improv/test-gate-definitions.md`: update only for new test-file classification or new optional/manual simulator commands.
- Closure responsibility belongs to `04-acceptance-closure`.

## Downstream execution path

| Session id | Next downstream path |
|---|---|
| `01-invite-lifecycle` | `$implementation-plan-orchestrator` -> `$implementation-execution-qa-orchestrator` -> `$implementation-closure-audit-orchestrator` |
| `02-recipient-eligibility` | `$implementation-plan-orchestrator` -> `$implementation-execution-qa-orchestrator` -> `$implementation-closure-audit-orchestrator` |
| `03-notification-suppression-routing` | `$implementation-plan-orchestrator` -> `$implementation-execution-qa-orchestrator` -> `$implementation-closure-audit-orchestrator` |
| `04-acceptance-closure` | `$implementation-plan-orchestrator` -> `$implementation-execution-qa-orchestrator` -> `$implementation-closure-audit-orchestrator` |

## Superseded controller blocker

- Superseded on: 2026-06-04 17:31 CEST
- Superseded verdict: `still_open`
- Prior blocker class: `spawn_or_tool_failure`
- Correction: a local `codex exec` spawn probe succeeded, so fresh downstream child agents are available for this controller run. The session ledger was reopened to `pending` at that time; the current ledger above supersedes that historical checkpoint. This section is retained only to explain the correction and must not be treated as the active final program verdict.

## Structural blockers remaining

None. The split has no known structural blocker and can be sent into downstream planning.

## Accepted differences intentionally left unchanged

- Exact UX wording for stale, expired, declined, missing, or resend-needed states is intentionally left to the session plans.
- No broad redesign of group creation, Group Info, Orbit, notification center, or notification visual design is included.
- Provider-backed APNs/TestFlight proof remains complementary unless a downstream acceptance plan explicitly scopes it; the required closure here is repo-owned direct, smoke, integration, Go, and simulator evidence.
- Legacy malformed payloads are treated as defense-in-depth for `03-notification-suppression-routing`, not as a reason to weaken sender-side recipient eligibility.

## Exact docs/files used as evidence

- `Test-Flight-Improv/106-group-chat-invited-vs-accepted-message-notifications.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/52-notification-journey-test-matrix.md`
- `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`
- `Test-Flight-Improv/91-group-invitation-status-visibility.md`
- `Test-Flight-Improv/71-foreground-group-push-drain-gap-plan.md`
- `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`
- `lib/features/groups/domain/models/pending_group_invite.dart`
- `lib/features/groups/domain/models/group_invite_payload.dart`
- `lib/features/groups/application/group_invite_auth.dart`
- `lib/features/groups/application/send_group_invite_use_case.dart`
- `lib/features/groups/application/handle_incoming_group_invite_use_case.dart`
- `lib/features/groups/application/group_invite_listener.dart`
- `lib/features/groups/domain/repositories/pending_group_invite_repository_impl.dart`
- `lib/features/groups/application/create_group_with_members_use_case.dart`
- `lib/features/groups/application/send_group_message_use_case.dart`
- `lib/features/groups/application/group_message_listener.dart`
- `lib/features/groups/domain/models/group_invite_delivery_attempt.dart`
- `lib/features/groups/presentation/screens/group_info_wired.dart`
- `go-mknoon/node/pubsub.go`
- `go-mknoon/node/group_inbox.go`
- `go-relay-server/inbox.go`
- `go-relay-server/inbox_test.go`
- `lib/features/push/application/background_push_notification_fallback.dart`
- `lib/features/push/application/background_message_handler.dart`
- `lib/features/push/application/handle_foreground_remote_message_use_case.dart`
- `lib/features/push/application/resolve_group_notification_route_target_use_case.dart`
- `lib/core/notifications/notification_route_target.dart`
- `lib/main.dart`
- Direct test families listed in each session above.

## Why the decomposition is safe to send into downstream planning/execution

Each session has a doc-scoped, non-colliding intended plan path and ends in a
meaningful verified state. The split follows current code boundaries instead of
only the source doc narrative: invite lifecycle, accepted-recipient fanout,
receiver fallback/tap safety, and final acceptance/closure are independently
testable while still ordered so later sessions refresh against landed behavior.
Sessions `01-invite-lifecycle` and `02-recipient-eligibility` are now accepted,
matrix ownership remains assigned to the final session, and sessions `03` and
`04` still need their own downstream planning, execution, and closure evidence
before the report can be closed.
