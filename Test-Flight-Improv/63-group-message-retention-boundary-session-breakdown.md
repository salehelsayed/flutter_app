# 63 - Group Message Retention Boundary Session Breakdown

## Decomposition artifact

- Artifact path:
  `Test-Flight-Improv/63-group-message-retention-boundary-session-breakdown.md`
- Proposal/source doc path:
  `Test-Flight-Improv/63-group-message-retention-boundary.md`
- Decomposition date:
  `2026-04-05`

## Downstream execution path

- detailed planning happens one session at a time
- later sessions must be refreshed against landed code before execution

## Recommended plan count

- `4`

## Overall closure bar

Report `63` closed only when the repo owns one explicit, testable retention
boundary for relay-backed group backlog instead of leaving `UX-008`
contract-undefined:

- reconnects inside the supported retention window still replay missed group
  messages normally
- reconnects outside that window get one clear, user-visible expired-backlog
  outcome instead of ambiguous partial recovery
- mixed windows where newer backlog is still retained and older backlog has
  expired recover the retained messages in order without duplicate timeline
  entries, ghost unread state, or surprise later reappearance of the expired
  backlog
- the retained-versus-expired rule is enforced in the shipped recovery path the
  repo actually owns today rather than only in prose
- the maintained group-architecture and matrix docs no longer keep `UX-008` in
  a policy-needed or contract-undefined state once the code, tests, and visible
  UX are truthful

## Source of truth

Primary governing docs:

- `Test-Flight-Improv/63-group-message-retention-boundary.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/09-network-group-messaging.md`
- `Test-Flight-Improv/libp2p_group_chat_policy_needed_matrix.md`
- `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`
- `Test-Flight-Improv/libp2p_group_chat_matrix_not_fully_implemented.md`

Current repo facts that govern the split:

- `drainGroupOfflineInbox(...)` currently drains every cursor page returned by
  the relay path and replays each message without any group-message retention
  cutoff, so the missing contract is real application behavior rather than a
  docs-only omission
- `callGroupInboxRetrieveWithCursor(...)` and `Node.GroupInboxRetrieveWithCursor`
  currently expose cursor paging but no retention-specific request parameter, so
  the repo can close the row by enforcing a truthful client-owned replay
  boundary instead of waiting on out-of-tree relay pruning work
- `handleIncomingGroupMessage(...)` and `GroupMessageListener` already own
  persistence, dedupe, notifications, and unread-affecting replay behavior, so
  expired backlog must be filtered before or during that path rather than papered
  over in the UI later
- the shipped group surfaces already have room for visible state contracts,
  including the conversation read-only banner and the group list invite-expired
  affordance, so retention-expired copy can land on existing UI seams without a
  brand-new feature surface
- maintained matrix docs still mark `UX-008` as `Contract-undefined`, so a
  final closure pass must update those docs only after code, tests, and visible
  UX agree on the same rule

Source-of-truth conflicts that materially affected decomposition:

- the source doc intentionally leaves the exact duration and copy open; this
  breakdown treats that as a repo-owned contract-selection session, not as a
  reason to block rollout indefinitely
- there is no relay-server implementation in this tree to prove upstream
  pruning, so the closure target is a truthful repo-owned retention contract at
  the replay boundary the app controls today

## Session ledger

| Session ID | Title | Classification | Intended plan file | Depends on | Current status | Closure docs touched | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `1` | `Define the repo-owned retention contract and durable backlog-gap state` | `implementation-ready` | `Test-Flight-Improv/63-group-message-retention-boundary-session-1-plan.md` | none | `accepted` | `Test-Flight-Improv/63-group-message-retention-boundary-session-breakdown.md`, `Test-Flight-Improv/63-group-message-retention-boundary-session-1-plan.md` | Accepted on `2026-04-05` after landing `group_backlog_retention_policy.dart`, the additive `053_groups_backlog_retention_columns.dart` migration, the new backlog-retention fields on `GroupModel`, `main.dart` DB version `53` wiring, and direct storage proof plus passing `groups` and `baseline` gates. |
| `2` | `Enforce the retention boundary during group inbox drain and mixed replay` | `implementation-ready` | `Test-Flight-Improv/63-group-message-retention-boundary-session-2-plan.md` | `1` | `accepted` | `Test-Flight-Improv/63-group-message-retention-boundary-session-breakdown.md`, `Test-Flight-Improv/63-group-message-retention-boundary-session-2-plan.md` | Accepted on `2026-04-05` after landing replay-time retention filtering in `drain_group_offline_inbox_use_case.dart`, persisting `lastBacklogExpiredAt` / `lastBacklogRetainedAt`, preserving system-envelope replay beyond the cutoff, and passing the direct drain/resume suites plus `groups` and `baseline` gates. |
| `3` | `Expose expired-backlog and mixed-window outcomes in shipped group UI` | `implementation-ready` | `Test-Flight-Improv/63-group-message-retention-boundary-session-3-plan.md` | `1`, `2` | `accepted` | `Test-Flight-Improv/63-group-message-retention-boundary-session-breakdown.md`, `Test-Flight-Improv/63-group-message-retention-boundary-session-3-plan.md` | Accepted on `2026-04-05` after landing the shared `group_backlog_retention_notice.dart` helper, truthful conversation/list retention copy, resume refresh wiring, and the direct presentation suites plus the `groups` gate. |
| `4` | `Close UX-008 with maintained-doc updates and final verification` | `implementation-ready` | `Test-Flight-Improv/63-group-message-retention-boundary-session-4-plan.md` | `1`, `2`, `3` | `accepted` | `Test-Flight-Improv/09-network-group-messaging.md`, `Test-Flight-Improv/libp2p_group_chat_policy_needed_matrix.md`, `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`, `Test-Flight-Improv/libp2p_group_chat_matrix_not_fully_implemented.md`, `Test-Flight-Improv/63-group-message-retention-boundary-session-breakdown.md` | Accepted on `2026-04-05` after updating the maintained network and matrix docs to close `UX-008`, removing the row from the contract-undefined/open trackers, and rerunning the direct replay/presentation suites plus `groups` and `baseline`. |

## Pipeline progress

- `2026-04-05`: Reusable doc-63 breakdown artifact created via bounded local
  decomposition fallback after the spawned decomposition attempt produced no
  doc-owned artifact. Session `1` is the first runnable session.
- `2026-04-05`: Bounded local planning fallback created
  `Test-Flight-Improv/63-group-message-retention-boundary-session-1-plan.md`
  after the spawned Session `1` planning attempt produced no doc-scoped plan
  artifact.
- `2026-04-05`: Session `1` accepted after bounded local execution/QA/closure
  fallback landed the domain retention policy, additive group-schema columns,
  `GroupModel` retention-state mapping, and database-version `53` wiring in
  `main.dart`, then passed:
  `flutter test test/core/database/migrations/053_groups_backlog_retention_columns_test.dart test/features/groups/domain/models/group_backlog_retention_policy_test.dart test/features/groups/domain/models/group_model_test.dart test/features/groups/domain/repositories/group_repository_impl_test.dart test/core/database/integration/full_migration_chain_test.dart`,
  `./scripts/run_test_gates.sh groups`, and
  `./scripts/run_test_gates.sh baseline`.
- `2026-04-05`: Local planning created
  `Test-Flight-Improv/63-group-message-retention-boundary-session-2-plan.md`
  for the replay-filtering slice after repeated fresh-child no-progress in the
  current doc pipeline.
- `2026-04-05`: Session `2` accepted after bounded local execution/QA fallback
  landed replay-time retention filtering, persisted
  `lastBacklogExpiredAt` / `lastBacklogRetainedAt`, preserved replayed system
  envelopes beyond the message cutoff, and passed:
  `flutter test test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`,
  `flutter test test/features/groups/integration/group_resume_recovery_test.dart`,
  `./scripts/run_test_gates.sh groups`, and
  `./scripts/run_test_gates.sh baseline`.
- `2026-04-05`: Local planning created
  `Test-Flight-Improv/63-group-message-retention-boundary-session-3-plan.md`
  for the user-visible retention-contract slice.
- `2026-04-05`: Session `3` accepted after bounded local execution/QA fallback
  landed the shared backlog-retention notice helper, truthful conversation and
  group-list copy, resume refresh wiring, and passed:
  `flutter test test/features/groups/presentation/group_conversation_screen_test.dart test/features/groups/presentation/group_conversation_wired_test.dart test/features/groups/presentation/group_list_screen_test.dart test/features/groups/presentation/group_list_wired_test.dart`
  and `./scripts/run_test_gates.sh groups`.
- `2026-04-05`: Local planning created
  `Test-Flight-Improv/63-group-message-retention-boundary-session-4-plan.md`
  for the maintained-doc closure pass.
- `2026-04-05`: Session `4` accepted after the bounded local closure pass
  updated `09-network-group-messaging.md`, closed `UX-008` in the full matrix,
  removed the row from the policy-needed and not-fully-implemented trackers,
  and passed:
  `flutter test test/features/groups/application/drain_group_offline_inbox_use_case_test.dart test/features/groups/integration/group_resume_recovery_test.dart`,
  `flutter test test/features/groups/presentation/group_conversation_screen_test.dart test/features/groups/presentation/group_conversation_wired_test.dart test/features/groups/presentation/group_list_screen_test.dart test/features/groups/presentation/group_list_wired_test.dart`,
  `./scripts/run_test_gates.sh groups`, and
  `./scripts/run_test_gates.sh baseline`.

## Final program verdict

- Status:
  `closed`
- Last updated:
  `2026-04-05`
- Completion summary:
  - decomposition is complete
  - sessions `1` through `4` are accepted
  - `UX-008` is closed in maintained docs with same-day replay, UI, and gate
    evidence

## Ordered session breakdown

### Session 1

- Title:
  `Define the repo-owned retention contract and durable backlog-gap state`
- Session id:
  `1`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/63-group-message-retention-boundary-session-1-plan.md`
- Exact scope:
  - choose one explicit repo-owned group-backlog retention rule, including the
    concrete supported window and the timestamp boundary later sessions will
    enforce
  - persist or deterministically derive the minimum local group-owned status
    needed to distinguish normal recovery from expired-backlog recovery
  - thread that status through the group model, repository, and schema paths
    without regressing existing active-group behavior
  - add direct migration, model, repository, and full-chain proof for the new
    retention-status contract if durable fields are added
- Why it is its own session:
  - later replay and UI work cannot be truthful until one concrete retention
    contract exists
  - isolating the contract and persistence layer reduces the risk of mixing
    storage drift with replay-path behavior changes
- Likely code-entry files:
  - `lib/features/groups/domain/models/group_model.dart`
  - `lib/features/groups/domain/repositories/group_repository_impl.dart`
  - `lib/core/database/helpers/groups_db_helpers.dart`
  - `lib/core/database/migrations/*groups*.dart`
  - `lib/main.dart`
  - `test/core/database/migrations/*groups*.dart`
  - `test/core/database/integration/full_migration_chain_test.dart`
  - `test/features/groups/domain/models/group_model_test.dart`
  - `test/features/groups/domain/repositories/group_repository_impl_test.dart`
- Likely named gates:
  - `flutter test test/core/database/integration/full_migration_chain_test.dart`

### Session 2

- Title:
  `Enforce the retention boundary during group inbox drain and mixed replay`
- Session id:
  `2`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/63-group-message-retention-boundary-session-2-plan.md`
- Exact scope:
  - apply the repo-owned retention rule during group inbox drain so replayed
    messages older than the boundary are treated as expired while newer retained
    messages still land in-order
  - make mixed retained/expired cursor pages deterministic so older backlog does
    not reappear on continuation drains or later retries once the app has
    already classified it as expired
  - keep dedupe, notifications, unread counts, and removal/dissolve boundaries
    truthful when retained messages arrive alongside expired ones
  - add direct application and integration regressions for within-window,
    beyond-window, and mixed-window recovery
- Why it is its own session:
  - this is the highest-risk correctness seam because it changes recovery,
    replay ordering, and duplicate prevention
  - it can be verified independently before any user-facing copy lands
- Likely code-entry files:
  - `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`
  - `lib/features/groups/application/handle_incoming_group_message_use_case.dart`
  - `lib/features/groups/application/group_message_listener.dart`
  - `lib/core/bridge/bridge_group_helpers.dart`
  - `go-mknoon/node/group_inbox.go`
  - `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`
  - `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`
  - `test/features/groups/application/group_message_listener_test.dart`
  - `test/features/groups/integration/group_resume_recovery_test.dart`
  - `test/features/groups/integration/group_membership_smoke_test.dart`
- Likely named gates:
  - `./scripts/run_test_gates.sh groups`

### Session 3

- Title:
  `Expose expired-backlog and mixed-window outcomes in shipped group UI`
- Session id:
  `3`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/63-group-message-retention-boundary-session-3-plan.md`
- Exact scope:
  - show one clear expired-backlog outcome in the shipped group surfaces after a
    reconnect crosses the retention boundary
  - make mixed-window recovery understandable when newer messages are restored
    but older backlog is no longer available
  - keep conversation, list, and any relevant notification-open surfaces honest
    without creating false unread or false “fully synced” impressions
  - add widget and wired regressions for the visible retention-boundary state
- Why it is its own session:
  - the UX copy must describe the real replay behavior from Session `2`, not a
    hypothetical policy
  - separating the UI work keeps presentation changes from obscuring recovery
    regressions
- Likely code-entry files:
  - `lib/features/groups/presentation/screens/group_conversation_wired.dart`
  - `lib/features/groups/presentation/screens/group_conversation_screen.dart`
  - `lib/features/groups/presentation/screens/group_list_wired.dart`
  - `lib/features/groups/presentation/screens/group_list_screen.dart`
  - `lib/features/push/application/prepare_notification_open_use_case.dart`
  - `test/features/groups/presentation/group_conversation_wired_test.dart`
  - `test/features/groups/presentation/group_conversation_screen_test.dart`
  - `test/features/groups/presentation/group_list_screen_test.dart`
  - `test/features/push/application/prepare_notification_open_use_case_test.dart`
- Likely named gates:
  - `./scripts/run_test_gates.sh groups`

### Session 4

- Title:
  `Close UX-008 with maintained-doc updates and final verification`
- Session id:
  `4`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/63-group-message-retention-boundary-session-4-plan.md`
- Exact scope:
  - update the maintained architecture and matrix docs so `UX-008` moves from
    `Contract-undefined` to landed behavior with concrete proof references
  - remove the row from the policy-needed tracker if the implementation now owns
    the contract completely
  - persist the final doc-63 program verdict only after the code, direct tests,
    visible UX, and maintained docs all agree on the same retention rule
- Why it is its own session:
  - matrix closure should happen only after the shipped behavior is real and
    verified
  - keeping closure separate prevents premature policy-doc cleanup
- Likely code-entry files:
  - `Test-Flight-Improv/09-network-group-messaging.md`
  - `Test-Flight-Improv/libp2p_group_chat_policy_needed_matrix.md`
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`
  - `Test-Flight-Improv/libp2p_group_chat_matrix_not_fully_implemented.md`
- Likely named gates:
  - `./scripts/run_test_gates.sh groups`
  - reuse same-day direct replay and UI regressions only if the final pass is
    docs-only and earlier gate evidence remains truthful
