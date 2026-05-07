# Group Invitation Status TDD Plan Session Breakdown

## Decomposition Artifact

- Artifact path:
  `Test-Flight-Improv/Group-Chat-Feature/group-invitation-status-tdd-plan-session-breakdown.md`
- Proposal/source doc path:
  `Test-Flight-Improv/Group-Chat-Feature/group-invitation-status-tdd-plan.md`
- Supporting docs:
  - `Test-Flight-Improv/test-gate-definitions.md`
  - `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- Decomposition date:
  `2026-05-07`

## Downstream Execution Path

- reuse the existing doc-scoped TDD plan when safe, otherwise tighten it for
  execution safety with `$implementation-plan-orchestrator`
- execute the session with `$implementation-execution-qa-orchestrator`
- close the session with `$implementation-closure-audit-orchestrator`
- persist the final program verdict in this breakdown artifact

## Recommended Plan Count

- `1`

## Run Mode Snapshot

- Active mode: `standard`
- Degraded local continuation explicitly allowed: `no`
- Source proposal/matrix path:
  `Test-Flight-Improv/Group-Chat-Feature/group-invitation-status-tdd-plan.md`
- Source row/status vocabulary: TDD checklist items use unchecked/checked task
  markers; execution status values use `execution-ready`, `blocked`,
  `accepted`, and `closed`.
- Overall closure bar: the single invite-status TDD session is accepted only
  when local, backward-compatible invite delivery status tracking is implemented
  across persistence, application flows, Group Info UI, member-joined handling,
  resend behavior, direct tests, named gates, and diff hygiene without changing
  group invite wire protocol, `members_added`, group key format, or legacy app
  behavior.
- Final verdict policy: `closed` only when the single session is accepted and
  the TDD plan's done criteria are satisfied with concrete code, test, gate, and
  documentation evidence. Use `still_open` if execution is blocked, required
  evidence is missing, or the closure bar is not met.

## Overall Closure Bar

The rollout is complete when a user who creates or adds group members during
network failure can later open Group Info and tell which invitees likely
received an invite and which invitees need manual resend. The status must
survive app restart, must update when the existing `member_joined` event is
observed, and must be covered by direct tests plus the required named gates.

## Source Of Truth

- `Test-Flight-Improv/Group-Chat-Feature/group-invitation-status-tdd-plan.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- Current production code and tests

## Controller Progress

- `2026-05-07` - Controller intake: the user supplied the execution-ready TDD
  plan rather than a session-breakdown artifact. This single-session breakdown
  was created so the pipeline can maintain a ledger, reuse or tighten the
  existing plan, execute once through fresh downstream agents, and persist a
  final program verdict.

## Closure Progress

- `2026-05-07 17:51:55 CEST` - Closure Auditor started for `GIS-001`;
  inspected the plan execution-progress tail, current worktree status, changed
  file list, protocol-payload diff guard, migration/helper/repository/UI status
  evidence, and relevant test-inventory sections. Evidence supports closing the
  session as `accepted`; next action: update the session ledger, plan status,
  closure audit section, and any necessary inventory rows without writing the
  final program verdict.
- `2026-05-07 17:55:51 CEST` - Closure Writer completed for `GIS-001`;
  updated the session ledger, session closure audit, TDD plan status/checklist,
  and focused test-inventory rows. Closure Reviewer checked the doc diff,
  untracked breakdown content, no-program-verdict guard, current status, and
  `git diff --check`; no closure-doc blocker remains.

## Session Ledger

| Session ID | Title | Classification | Plan file path | Depends on | Current status | Final execution verdict | Closure docs touched | Blocker class | Note |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `GIS-001` | Local invite delivery status persistence, application mapping, Group Info UI, resend, and joined updates | `accepted` | `Test-Flight-Improv/Group-Chat-Feature/group-invitation-status-tdd-plan.md` | none | `accepted` | `accepted` | `group-invitation-status-tdd-plan.md`; `group-invitation-status-tdd-plan-session-breakdown.md`; `test-inventory.md` | none | Migration/helper/repository/use-case/UI deltas landed; direct persistence/application/presentation tests, invite round-trip, focused regressions, `baseline`, `groups`, device-pinned `transport`, `completeness-check` (`730/730`), and `git diff --check` passed; protocol payloads, `members_added`, and key format stayed out of scope. |

## GIS-001 Closure Audit

Session closure verdict: `accepted`. This section closes `GIS-001` only; the
outer pipeline still owns the final program verdict.

### Closed

- Local-only group invite delivery status persistence is landed through
  migration `067`, DB helpers, domain model/repository, and `lib/main.dart`
  version/repository wiring.
- Create-group and add-member invite flows now record per-recipient status:
  direct success as `sent`, inbox fallback as `queued`, hard failures as
  `needs_resend`, and missing secure key / invalid invite payload as
  `cannot_send`.
- Group Info loads and displays invite status labels, exposes `Send again` only
  for `needs_resend`, and the resend path sends an invite without adding the
  member again or publishing another membership event.
- Existing `member_joined` system-event handling now marks the corresponding
  invite delivery attempt as `joined`.
- Closure evidence is accepted from the plan's `## Execution Progress` record:
  all direct persistence/application/presentation tests listed by the plan,
  `flutter test test/features/groups/integration/invite_round_trip_test.dart`,
  focused groups application/presentation regressions, contact-request
  integration, `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline`,
  `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups`,
  `FLUTTER_DEVICE_ID=5BA69F1C-B112-47BE-B1FF-8C1003728C8F ./scripts/run_test_gates.sh transport`,
  `./scripts/run_test_gates.sh completeness-check` (`730/730`), and
  `git diff --check`.

### Residual-Only Items

- True recipient acknowledgments, delivery receipts, invite ACK protocol,
  remote acceptance receipts, and auto-resend remain intentionally outside this
  session. `sent` and `queued` are local attempt outcomes only.
- Legacy/pre-migration members without a local attempt row remain `unknown`;
  this is accepted compatibility behavior, not a reopen trigger.
- Broader paired-device, multi-relay, OS-notification, or device-lab proof is
  residual-only because the accepted closure profile for `GIS-001` is the
  required single-device `transport` gate plus host-pinned `baseline` and
  `groups` gates.

### Accepted Differences

- `SendGroupInviteResult` now distinguishes direct-fail/inbox-success as
  `queued` instead of generic success so UI status can remain truthful.
- Feed, orbit, startup, home, group-list, conversation, create-group, and
  contact-picker deltas are accepted typed-seam dependency pass-through needed
  to construct and forward the invite-status repository; they are not product
  scope drift.
- The `invite_round_trip_test.dart` stale expectation/time-source adjustment
  and `group_info_screen_test.dart` scroll interaction adjustment are accepted
  test repairs caused by the new truthful `queued` result and taller member
  rows.
- `test-inventory.md` was updated because this session added new migration,
  helper, repository, and resend tests, and reclassified existing
  create/invite/listener/Group Info coverage under the current inventory
  conventions.

### Still Open

- No `GIS-001` implementation or test blocker remains open.
- The unrelated untracked `Test-Flight-Improv/92-one-to-one-simulator-reliability-gaps.md`
  and `scripts/check_reliability_simulation_discovery.sh` files are not part of
  this closure and remain untouched.

### Reopen Only On Real Regression Criteria

Reopen `GIS-001` only if a future change breaks migration `067`/version wiring,
invite-attempt upsert/load/status projection, create/add-member status
recording, `member_joined` to `joined`, Group Info status/resend UI, resend
idempotence, the no-protocol-change guard, or one of the maintenance gates
below for a cause inside this scope. Do not reopen this session for future
protocol-level acknowledgment design, legacy `unknown` rows, or broader device
lab coverage requests.

### Maintenance Safety Gates

- `flutter test test/core/database/migrations/067_group_invite_delivery_attempts_test.dart`
- `flutter test test/core/database/helpers/group_invite_delivery_attempts_db_helpers_test.dart`
- `flutter test test/core/database/integration/full_migration_chain_test.dart`
- `flutter test test/features/groups/domain/repositories/group_invite_delivery_attempt_repository_impl_test.dart`
- `flutter test test/features/groups/application/send_group_invite_use_case_test.dart`
- `flutter test test/features/groups/application/create_group_with_members_use_case_test.dart`
- `flutter test test/features/groups/application/group_message_listener_test.dart`
- `flutter test test/features/groups/application/resend_group_invite_use_case_test.dart`
- `flutter test test/features/groups/presentation/contact_picker_wired_test.dart`
- `flutter test test/features/groups/presentation/create_group_picker_wired_test.dart`
- `flutter test test/features/groups/presentation/group_info_screen_test.dart`
- `flutter test test/features/groups/presentation/group_info_wired_test.dart`
- `flutter test test/features/groups/integration/invite_round_trip_test.dart`
- `flutter test test/features/groups/application test/features/groups/presentation`
- `flutter test test/features/contact_request/integration/contact_request_flow_test.dart`
- `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline`
- `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups`
- `FLUTTER_DEVICE_ID=5BA69F1C-B112-47BE-B1FF-8C1003728C8F ./scripts/run_test_gates.sh transport`
- `./scripts/run_test_gates.sh completeness-check`
- `git diff --check`

## Ordered Session Breakdown

### Session GIS-001

- Title:
  `Local invite delivery status persistence, application mapping, Group Info UI, resend, and joined updates`
- Session id:
  `GIS-001`
- Session classification:
  `accepted`
- Intended plan file:
  `Test-Flight-Improv/Group-Chat-Feature/group-invitation-status-tdd-plan.md`
- Depends on:
  none
- Exact scope:
  - add local, backward-compatible invite delivery status tracking for invited
    group members
  - persist status rows across restart through migration `067` and
    helper-backed repository code
  - map direct send, inbox fallback, hard failure, cannot-send, resend, and
    existing `member_joined` observations into the status model
  - show compact statuses and `Send again` only for `needs_resend` in Group
    Info
  - keep the group invite wire protocol, `members_added`, group key format, and
    legacy app behavior unchanged
- Likely code-entry files:
  - `lib/core/database/migrations/067_group_invite_delivery_attempts.dart`
  - `lib/core/database/helpers/group_invite_delivery_attempts_db_helpers.dart`
  - `lib/main.dart`
  - `lib/features/groups/domain/models/group_invite_delivery_attempt.dart`
  - `lib/features/groups/domain/repositories/group_invite_delivery_attempt_repository.dart`
  - `lib/features/groups/domain/repositories/group_invite_delivery_attempt_repository_impl.dart`
  - `lib/features/groups/application/send_group_invite_use_case.dart`
  - `lib/features/groups/application/create_group_with_members_use_case.dart`
  - `lib/features/groups/application/group_message_listener.dart`
  - `lib/features/groups/application/resend_group_invite_use_case.dart`
  - `lib/features/groups/presentation/screens/contact_picker_wired.dart`
  - `lib/features/groups/presentation/screens/create_group_picker_wired.dart`
  - `lib/features/groups/presentation/screens/group_conversation_wired.dart`
  - `lib/features/groups/presentation/screens/group_info_wired.dart`
  - `lib/features/groups/presentation/screens/group_info_screen.dart`
  - `lib/features/groups/presentation/widgets/group_member_row.dart`
- Likely direct tests and regressions:
  - `flutter test test/core/database/migrations/067_group_invite_delivery_attempts_test.dart`
  - `flutter test test/core/database/helpers/group_invite_delivery_attempts_db_helpers_test.dart`
  - `flutter test test/core/database/integration/full_migration_chain_test.dart`
  - `flutter test test/features/groups/domain/repositories/group_invite_delivery_attempt_repository_impl_test.dart`
  - `flutter test test/features/groups/application/send_group_invite_use_case_test.dart`
  - `flutter test test/features/groups/application/create_group_with_members_use_case_test.dart`
  - `flutter test test/features/groups/application/group_message_listener_test.dart`
  - `flutter test test/features/groups/application/resend_group_invite_use_case_test.dart`
  - `flutter test test/features/groups/presentation/contact_picker_wired_test.dart`
  - `flutter test test/features/groups/presentation/create_group_picker_wired_test.dart`
  - `flutter test test/features/groups/presentation/group_info_screen_test.dart`
  - `flutter test test/features/groups/presentation/group_info_wired_test.dart`
  - `flutter test test/features/groups/application test/features/groups/presentation`
  - `flutter test test/features/contact_request/integration/contact_request_flow_test.dart`
- Named gates:
  - `./scripts/run_test_gates.sh baseline`
  - `./scripts/run_test_gates.sh groups`
  - `./scripts/run_test_gates.sh transport`
  - `./scripts/run_test_gates.sh completeness-check`
  - `git diff --check`
- Dependency state:
  satisfied; no prerequisite sessions.
- Matrix or closure docs to update:
  - `Test-Flight-Improv/Group-Chat-Feature/group-invitation-status-tdd-plan.md`
  - `Test-Flight-Improv/Group-Chat-Feature/group-invitation-status-tdd-plan-session-breakdown.md`
  - `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or
    reclassified tests require inventory coverage
- Structural blockers:
  none known at intake. Device-backed named gates may require live simulator or
  integration-test fixture availability and must be classified in the current
  session plan before execution.

## Final Program Verdict

- Verdict: `closed`
- Last updated: `2026-05-07 17:58:12 CEST`
- Why: the only session, `GIS-001`, is accepted in the session ledger with no
  blocker class, no dependencies, and no unresolved implementation or test
  blocker. The source TDD plan is `Status: accepted` and
  `Session classification: accepted`; all done criteria are checked, including
  migration `067`, helper/repository persistence, create/add-member status
  recording, Group Info status/resend UI, `member_joined` convergence, typed
  seam coherence, named gates, and the no-protocol-change guard.
- Docs and gates evidence: the `GIS-001` closure audit in this breakdown,
  `group-invitation-status-tdd-plan.md`, and `test-inventory.md` all record the
  same closure profile. Accepted gate evidence includes the direct
  persistence/application/presentation tests, `invite_round_trip_test.dart`,
  focused groups application/presentation regressions, contact-request
  integration, `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline`,
  `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups`,
  `FLUTTER_DEVICE_ID=5BA69F1C-B112-47BE-B1FF-8C1003728C8F ./scripts/run_test_gates.sh transport`,
  `./scripts/run_test_gates.sh completeness-check` (`730/730`), and
  `git diff --check`.
- Residual-only scope: true recipient acknowledgments, delivery receipts,
  invite ACK protocol, remote acceptance receipts, auto-resend, legacy
  pre-migration `unknown` rows, and broader paired-device, multi-relay,
  OS-notification, or device-lab proof remain outside `GIS-001` and are not
  blockers for this rollout.
- Reopen-only criteria: reopen the program only for a real regression in
  migration `067`/version wiring, invite-attempt upsert/load/status projection,
  create/add-member status recording, `member_joined` to `joined`, Group Info
  status/resend UI, resend idempotence, the no-protocol-change guard, or a
  maintenance gate failure caused by this scope.
- Unresolved sessions: none.
