# 71 - Foreground FCM Push Does Not Drain Group Inbox Session Breakdown

## Decomposition artifact updated

- Artifact path:
  `Test-Flight-Improv/71-foreground-group-push-drain-gap-plan-session-breakdown.md`
- Proposal/source doc path:
  `Test-Flight-Improv/71-foreground-group-push-drain-gap-plan.md`
- Decomposition date:
  `2026-04-22`
- Downstream workflow rule:
  - detailed planning happens one session at a time
  - later sessions must be refreshed against landed code before execution

## Recommended plan count

- `2`

## Overall closure bar

Report `71` is finished only when all of the following are true at the same
time:

- the foreground `FirebaseMessaging.onMessage` path no longer unconditionally
  drains only the 1:1 inbox
- routable foreground chat, contact-request, and intros pushes preserve the
  current 1:1 drain behavior
- routable foreground group pushes call the targeted
  `drainGroupOfflineInboxForGroup(groupId)` path and do not require a later
  resume or tap to surface the pending group message
- unroutable foreground pushes do not trigger an accidental 1:1 or group drain
- duplicate local-notification behavior remains governed by the existing
  message-aware dedupe paths rather than a new foreground gate write
- deterministic automated proof exists for the new foreground routing seam and
  for the relay-staged foreground group-drain scenario
- `Test-Flight-Improv/52-notification-journey-test-matrix.md` and
  `Test-Flight-Improv/test-gate-definitions.md` truthfully reflect the new
  coverage without widening the frozen named gates
- remaining manual smoke and post-TestFlight telemetry obligations are either
  completed or recorded honestly as explicit follow-up rather than implied done

## Source of truth

Primary governing docs:

- `Test-Flight-Improv/71-foreground-group-push-drain-gap-plan.md`
- `Test-Flight-Improv/52-notification-journey-test-matrix.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/notification-sound-smoke-plan.md`

Current repo facts that govern the split:

- `lib/main.dart` currently emits `PUSH_FOREGROUND_MESSAGE_RECEIVED` and then
  immediately calls `widget.p2pService.drainOfflineInbox()` from the foreground
  `FirebaseMessaging.onMessage` listener, so group pushes never hit the group
  drain seam.
- `lib/features/push/application/background_message_handler.dart` already uses
  `NotificationRouteTarget.fromRemoteMessageData(message.data)` for the
  background path, so the intended foreground parsing model is already present
  in the repo.
- `lib/features/push/application/prepare_notification_open_use_case.dart`
  already encodes the expected kind-aware drain policy for conversation,
  contact-request, intros, group, and post-like targets.
- `lib/core/notifications/notification_route_target.dart` plus
  `test/core/notifications/notification_route_contract_matrix_test.dart`
  already provide the canonical routing contract for remote payload parsing and
  drain policy, so the foreground fix should extend that shared contract rather
  than invent a second policy table.
- `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`
  already provides `drainGroupOfflineInboxForGroup`, and
  `lib/features/groups/application/group_message_listener.dart` already owns the
  replay-side dedupe and notification emission behavior that the new foreground
  route must reuse.
- Existing direct regressions already cover neighboring seams:
  `test/features/push/application/background_message_handler_test.dart`,
  `test/features/push/application/prepare_notification_open_use_case_test.dart`,
  `test/features/push/application/show_notification_use_case_test.dart`,
  `test/core/lifecycle/handle_app_resumed_group_recovery_test.dart`, and
  `test/integration/group_notification_dedupe_integration_test.dart`.
- `Test-Flight-Improv/52-notification-journey-test-matrix.md` already treats
  route parsing, group notification dedupe, and warm/cold group notification
  preparation as stable notification-contract rows, so report `71` should close
  by extending that existing matrix rather than inventing a new standalone
  matrix.

## Session ledger

| Session ID | Title | Classification | Intended plan file | Depends on | Current status | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| `1` | `Foreground route-aware drain implementation and deterministic seam coverage` | `implementation-ready` | `Test-Flight-Improv/71-foreground-group-push-drain-gap-plan-session-1-plan.md` | none | `accepted` | Accepted on `2026-04-22` after the new `handleForegroundRemoteMessage(...)` use case, the `lib/main.dart` foreground bridge, direct route-target edge coverage, and the new foreground unit suite landed. Direct tests passed in `handle_foreground_remote_message_use_case_test.dart`, `notification_route_target_test.dart`, `notification_route_contract_matrix_test.dart`, `prepare_notification_open_use_case_test.dart`, `background_message_handler_test.dart`, `show_notification_use_case_test.dart`, and `handle_app_resumed_group_recovery_test.dart`. Both `./scripts/run_test_gates.sh groups` and `./scripts/run_test_gates.sh baseline` passed. |
| `2` | `Foreground integration proof and notification-matrix closure` | `implementation-ready` | `Test-Flight-Improv/71-foreground-group-push-drain-gap-plan-session-2-plan.md` | `1` | `accepted_with_explicit_follow_up` | Accepted on `2026-04-22` after `integration_test/foreground_group_push_drain_test.dart` landed with the targeted group-drain, live-first dedupe, 1:1 parity, and post no-drain scenarios; `Test-Flight-Improv/52-notification-journey-test-matrix.md` gained `JRN-FG-GRP-01`; `Test-Flight-Improv/test-gate-definitions.md` classified the new direct suites; and the acceptance run passed `flutter test integration_test/foreground_group_push_drain_test.dart -d macos`, `flutter test test/integration/group_notification_dedupe_integration_test.dart`, `flutter test test/features/push/application/chat_and_group_push_open_flow_test.dart`, `flutter test test/features/push/application/handle_foreground_remote_message_use_case_test.dart`, and `./scripts/run_test_gates.sh groups`. Remaining follow-up is explicit and non-blocking: manual two-device mesh-gap smoke plus post-land 48h TestFlight telemetry review. |

## Final program verdict

- Status:
  `accepted_with_explicit_follow_up`
- Last updated:
  `2026-04-22`
- Completion summary:
  - decomposition finished through bounded local fallback after the isolated
    decomposition agent left no reusable artifact under bounded wait
  - pipeline execution finished through bounded local fallback after the
    isolated pipeline controller left no doc-owned progress under bounded wait
  - session `1` accepted with the route-aware foreground drain use case,
    `lib/main.dart` foreground bridge wiring, direct route/contract proof, and
    both `./scripts/run_test_gates.sh groups` and
    `./scripts/run_test_gates.sh baseline` passing
  - session `2` accepted_with_explicit_follow_up with the foreground
    relay-drain integration proof, stable matrix/gate-doc updates, focused
    direct suites, and `./scripts/run_test_gates.sh groups` passing
  - remaining follow-up is explicitly limited to manual two-device mesh-gap
    smoke attestation and the post-land 48h TestFlight telemetry review; both
    are external, non-blocking closure items rather than open repo gaps

## Ordered session breakdown

### Session 1

- Title:
  `Foreground route-aware drain implementation and deterministic seam coverage`
- Session id:
  `1`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/71-foreground-group-push-drain-gap-plan-session-1-plan.md`
- Exact scope:
  - add the new foreground-routing use case adjacent to the existing push
    application helpers so foreground push handling resolves
    `NotificationRouteTarget` once and dispatches by kind
  - replace the current unconditional foreground `drainOfflineInbox()` call in
    `lib/main.dart` with a thin bridge that delegates into the new use case via
    `unawaited(...)`
  - emit the new foreground routing and error flow events required by the
    source doc without adding a new foreground
    `recentRemoteNotificationGate` write
  - keep group pushes on the targeted
    `drainGroupOfflineInboxForGroup(groupId)` path and keep
    conversation/contact-request/intros pushes on the existing 1:1 drain path
  - make unroutable or malformed foreground payloads no-op safely instead of
    falling through to the old blanket 1:1 drain
  - add the direct unit and regression coverage for U1-U9 plus the nearby route
    contract and regression seams named in sections 10.1-10.3 and 10.6 of the source
    doc
- Why it is its own session:
  - this is the actual production seam that changes user-visible foreground
    behavior, and it already has a coherent direct-proof family under `test/`
  - the route parser, main-listener bridge, and existing regression suites all
    exercise the same notification-routing contract, so they should land
    together rather than be split into bookkeeping-only red/green sub-sessions
  - it can leave the repo in a truthful partially-verified state before the
    heavier foreground integration harness and stable-doc closure work land
- Likely code-entry files:
  - `lib/main.dart`
  - `lib/features/push/application/handle_foreground_remote_message_use_case.dart`
  - `lib/core/notifications/notification_route_target.dart`
  - `lib/features/push/application/prepare_notification_open_use_case.dart`
  - `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`
  - `lib/core/utils/flow_event_emitter.dart`
- Likely direct tests/regressions:
  - `test/features/push/application/handle_foreground_remote_message_use_case_test.dart`
  - `test/features/push/application/remote_message_fixtures.dart`
  - `test/core/notifications/notification_route_target_test.dart`
  - `test/core/notifications/notification_route_contract_matrix_test.dart`
  - `test/features/push/application/prepare_notification_open_use_case_test.dart`
  - `test/features/push/application/background_message_handler_test.dart`
  - `test/features/push/application/show_notification_use_case_test.dart`
  - `test/core/lifecycle/handle_app_resumed_group_recovery_test.dart`
- Likely named gates:
  - direct notification and lifecycle suites above are mandatory
  - `./scripts/run_test_gates.sh groups`
  - `./scripts/run_test_gates.sh baseline` because the foreground listener in
    `lib/main.dart` is expected to change
  - `./scripts/run_test_gates.sh transport` only if execution expands beyond
    the foreground-listener seam into broader resume/bootstrap/transport
    ordering
- Matrix/closure docs to update when done:
  - refresh
    `Test-Flight-Improv/71-foreground-group-push-drain-gap-plan-session-breakdown.md`
  - keep stable matrix and gate-doc updates deferred to Session `2`, because
    Session `1` alone does not yet provide the end-to-end foreground proof the
    source doc requires for closure
- Dependency on earlier sessions:
  - none
- Downstream execution path:
  - `$implementation-plan-orchestrator`
  - `$implementation-execution-qa-orchestrator`
  - `$implementation-closure-audit-orchestrator`

### Session 2

- Title:
  `Foreground integration proof and notification-matrix closure`
- Session id:
  `2`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/71-foreground-group-push-drain-gap-plan-session-2-plan.md`
- Exact scope:
  - add the foreground integration proof for I1-I4 using the existing Flutter
    integration rig or its closest repo-owned relay/group harness equivalent,
    keeping the test deterministic and local to the repo rather than dependent
    on a live EC2 environment
  - prove the target scenario where a foreground group push drains the relay
    group inbox and materializes one message/notification path without a later
    resume or tap
  - prove the nearby negative and parity cases that the source doc calls out:
    gossipsub-first no-duplicate behavior, preserved foreground 1:1 drain
    behavior, and no drain for post pushes
  - update the stable notification journey matrix with the new
    `JRN-FG-GRP-01` row and record the intended evidence chain
  - classify any new direct test files in
    `Test-Flight-Improv/test-gate-definitions.md` without widening the frozen
    named gates or changing `scripts/run_test_gates.sh`
  - close the report honestly by recording whether manual two-device smoke and
    post-TestFlight telemetry are complete now or remain explicit follow-up
- Why it is its own session:
  - this session owns a different direct-proof family from Session `1`:
    integration harness behavior plus stable closure docs
  - the source doc's user-visible acceptance bar is not met by unit/regression
    proof alone; the foreground drain path needs one dedicated integration pass
    and the stable notification docs need to be updated from that evidence
  - keeping this work after Session `1` allows the pipeline to tighten the
    integration harness against the landed production seam rather than guessing
    it upfront
- Likely code-entry files:
  - `integration_test/foreground_group_push_drain_test.dart`
  - existing integration harness helpers under `integration_test/` that already
    model group notification or relay-backed catch-up behavior
  - `Test-Flight-Improv/52-notification-journey-test-matrix.md`
  - `Test-Flight-Improv/test-gate-definitions.md`
  - `Test-Flight-Improv/71-foreground-group-push-drain-gap-plan-session-breakdown.md`
- Likely direct tests/regressions:
  - `integration_test/foreground_group_push_drain_test.dart`
  - `test/integration/group_notification_dedupe_integration_test.dart`
  - `test/features/groups/integration/group_resume_recovery_test.dart` if the
    chosen integration harness reuses the group recovery seam
  - `test/features/push/application/chat_and_group_push_open_flow_test.dart`
    as a nearby notification-route parity check when the acceptance run needs
    shared notification preparation evidence
- Likely named gates:
  - direct integration suites above are mandatory
  - `./scripts/run_test_gates.sh groups`
  - rerun `./scripts/run_test_gates.sh baseline` if Session `2` still touches
    app-root Flutter production code while hardening the harness
  - do not widen or add frozen named gates for this report
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/52-notification-journey-test-matrix.md`
  - `Test-Flight-Improv/test-gate-definitions.md`
  - refresh
    `Test-Flight-Improv/71-foreground-group-push-drain-gap-plan-session-breakdown.md`
  - update `Test-Flight-Improv/notification-sound-smoke-plan.md` only if the
    final acceptance wording truly needs the foreground-manual-smoke reference;
    otherwise keep the stable closure change bounded to the matrix and gate doc
- Dependency on earlier sessions:
  - Session `1`
- Downstream execution path:
  - `$implementation-plan-orchestrator`
  - `$implementation-execution-qa-orchestrator`
  - `$implementation-closure-audit-orchestrator`

## Why this is not fewer sessions

- One session would mix the production app-root routing seam with the heavier
  foreground integration harness and stable notification-doc closure work,
  making it harder to verify whether a failure is in the routing change itself
  or in the acceptance harness.
- The source doc requires both deterministic seam proof and a user-visible
  foreground drain proof. Those are distinct verification families with
  different artifacts and a natural dependency edge from production change to
  acceptance proof.
- Manual smoke and TestFlight telemetry obligations should be handled as part of
  the final closure pass after the automated foreground integration proof is in
  place, not interleaved into the first code-change session.

## Why this is not more sessions

- The source doc's forward-reference red/green split would create a session
  that intentionally leaves tests red and no independently trustworthy finished
  state; that is bookkeeping, not a meaningful session boundary.
- Route-target fixture hardening, the new foreground use case, and the nearby
  regression suites all exercise the same notification-routing seam and should
  land together.
- Stable matrix and gate-doc updates belong with the final acceptance session;
  splitting them into a third session would add orchestration overhead without
  independent verification value unless the repo later proves a real blocker.

## Regression and gate contract

- `Test-Flight-Improv/14-regression-test-strategy.md` applies here as a
  narrow-bug rule: add one permanent regression for the escaped defect and run
  the existing neighboring subsystem gates instead of inventing a new gate.
- Session `1` must leave direct unit/regression coverage for the foreground
  route contract and rerun the existing neighboring notification/lifecycle
  suites that protect resume, background handling, and local notification
  suppression.
- Session `1` should run `./scripts/run_test_gates.sh groups` and
  `./scripts/run_test_gates.sh baseline`; `transport` is conditional and only
  applies if scope widens into broader lifecycle/bootstrap behavior.
- Session `2` must leave the foreground integration proof green, rerun the
  `groups` gate, and keep any new direct integration files intentionally
  classified in `Test-Flight-Improv/test-gate-definitions.md` without changing
  the frozen named gate lists.
- If final execution discovers that the stable matrix row remains unresolved or
  the integration proof cannot be made deterministic with current harnesses,
  the report should remain `blocked` or `accepted_with_explicit_follow_up`
  rather than papering over that gap.

## Matrix update contract

- Reuse the existing stable notification journey matrix:
  `Test-Flight-Improv/52-notification-journey-test-matrix.md`.
- Session `2` owns the matrix update because the new `JRN-FG-GRP-01` row must
  be backed by landed foreground integration evidence, not just by the session
  `1` unit/regression suite.
- Session `2` also owns any required classification note in
  `Test-Flight-Improv/test-gate-definitions.md` for
  `integration_test/foreground_group_push_drain_test.dart` and the new
  foreground use-case direct test, while keeping the frozen named gates
  unchanged.
- The breakdown artifact itself must be refreshed after each session so the
  later pipeline and final acceptance pass can reason from persisted state.

## Downstream execution path

- Session `1` should next go through:
  - `$implementation-plan-orchestrator`
  - `$implementation-execution-qa-orchestrator`
  - `$implementation-closure-audit-orchestrator`
- Session `2` should next go through:
  - `$implementation-plan-orchestrator`
  - `$implementation-execution-qa-orchestrator`
  - `$implementation-closure-audit-orchestrator`
