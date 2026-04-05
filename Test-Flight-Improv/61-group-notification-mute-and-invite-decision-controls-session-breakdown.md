# 61 - Group Notification Mute and Invite Decision Controls Session Breakdown

## Decomposition artifact updated

- Artifact path:
  `Test-Flight-Improv/61-group-notification-mute-and-invite-decision-controls-session-breakdown.md`
- Proposal/source doc path:
  `Test-Flight-Improv/61-group-notification-mute-and-invite-decision-controls.md`
- Decomposition date:
  `2026-04-05`
- Downstream workflow rule:
  - detailed planning happens one session at a time
  - later sessions must be refreshed against landed code before execution

## Recommended plan count

- `4`

## Overall closure bar

Report `61` is closed only when group mute and invite-decision behavior are a
landed, truthful product contract rather than explicit unsupported scope:

- members can mute one specific group without breaking delivery, unread state,
  or other group notification behavior
- unmuting restores normal future notifications for that group
- incoming invites no longer auto-join silently; they remain pending until the
  user accepts, declines, or the invite expires
- decline and expiry outcomes do not create ghost groups, ghost membership, or
  accidental topic joins
- accepting a pending invite still yields the same persisted group, join, and
  inbox-drain recovery contract expected for a successful join
- the maintained audit and matrix docs no longer mark per-group mute or
  explicit invite accept/decline as unsupported once the code and tests own
  those rows

## Source of truth

Primary governing docs:

- `Test-Flight-Improv/61-group-notification-mute-and-invite-decision-controls.md`
- `Test-Flight-Improv/11-group-discussion-use-case-audit.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/09-network-group-messaging.md`
- `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`
- `Test-Flight-Improv/libp2p_group_chat_matrix_features_did_not_exist.md`

Current repo facts that govern the split:

- `GroupMessageListener` already owns the exact notification suppression seam,
  so per-group mute belongs first in the repo-local persistence plus listener
  path rather than as a UI-only toggle
- `GroupInviteListener` currently auto-processes invites into joined groups via
  `handleIncomingGroupInvite`, so explicit accept/decline needs a new pending
  invite lifecycle before any UI surface can be truthful
- `GroupListWired` already listens to `groupJoinedStream`, making it the most
  likely existing group surface to extend with pending invite review and joined
  list refresh behavior
- the repo already has accept/decline product patterns in contact-request and
  introduction surfaces, which lowers UI risk for the invite-decision session
- the audit and matrix docs explicitly still call both rows unsupported, so a
  final closure pass must update long-lived docs after code/test truth lands

Source-of-truth conflicts that materially affected decomposition:

- mute and invite-decision look adjacent in the product doc, but they touch
  different repo seams: mute is notification gating on joined groups, while
  invite decisions require a pre-join persistence and lifecycle model
- the current invite flow is auto-joining by construction, so trying to land UI
  first would force screens to guess at unsupported pending-state behavior

## Session ledger

| Session ID | Title | Classification | Intended plan file | Depends on | Current status | Closure docs touched | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `1` | `Ship the per-group mute persistence and notification suppression contract` | `implementation-ready` | `Test-Flight-Improv/61-group-notification-mute-and-invite-decision-controls-session-1-plan.md` | none | `accepted` | `Test-Flight-Improv/61-group-notification-mute-and-invite-decision-controls-session-breakdown.md` | Landed `is_muted` persistence plus `setGroupMuted(...)`, muted-notification suppression, direct regressions, migration-chain proof, and a passing `./scripts/run_test_gates.sh groups` run on `2026-04-05`. |
| `2` | `Introduce pending group-invite decision lifecycle and acceptance use cases` | `implementation-ready` | `Test-Flight-Improv/61-group-notification-mute-and-invite-decision-controls-session-2-plan.md` | `1` | `accepted` | `Test-Flight-Improv/61-group-notification-mute-and-invite-decision-controls-session-breakdown.md`, `Test-Flight-Improv/61-group-notification-mute-and-invite-decision-controls-session-2-plan.md` | Landed durable pending invite persistence, pending invite receipt in `GroupInviteListener`, explicit accept/decline/expiry use cases, direct repository and application regressions, `test/core/database/integration/full_migration_chain_test.dart`, and a passing `./scripts/run_test_gates.sh groups` gate on `2026-04-05`. |
| `3` | `Expose mute controls and pending invite decisions in shipped surfaces` | `implementation-ready` | `Test-Flight-Improv/61-group-notification-mute-and-invite-decision-controls-session-3-plan.md` | `1`, `2` | `accepted` | `Test-Flight-Improv/61-group-notification-mute-and-invite-decision-controls-session-breakdown.md`, `Test-Flight-Improv/61-group-notification-mute-and-invite-decision-controls-session-3-plan.md` | Landed the shipped group-info mute toggle, the group-list pending invite review surface with accept/decline handling and joined-list refresh, direct presentation regressions, and a passing `./scripts/run_test_gates.sh groups` gate on `2026-04-05`. |
| `4` | `Close mute and invite-decision matrix rows with integration proof and doc updates` | `implementation-ready` | `Test-Flight-Improv/61-group-notification-mute-and-invite-decision-controls-session-4-plan.md` | `1`, `2`, `3` | `accepted` | `Test-Flight-Improv/11-group-discussion-use-case-audit.md`, `Test-Flight-Improv/09-network-group-messaging.md`, `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`, `Test-Flight-Improv/libp2p_group_chat_matrix_features_did_not_exist.md`, `Test-Flight-Improv/61-group-notification-mute-and-invite-decision-controls-session-breakdown.md`, `Test-Flight-Improv/61-group-notification-mute-and-invite-decision-controls-session-4-plan.md` | Closed `UX-004` and `UX-012` in the maintained audit/matrix docs, added the visible expired-invite UI regression, and revalidated the mute plus invite-decision proof on `2026-04-05`. |

## Pipeline progress

- `2026-04-05`: Reusable doc-61 breakdown artifact created locally. Session
  `1` is the first runnable session.
- `2026-04-05`: Session `1` accepted after landing the group mute column and
  model state, the `setGroupMuted(...)` mutation path, muted-group local
  notification suppression in `GroupMessageListener`, direct regressions,
  `test/core/database/integration/full_migration_chain_test.dart`, and a
  passing `./scripts/run_test_gates.sh groups` gate.
- `2026-04-05`: Session `2` planning started against the current invite seam:
  `GroupInviteListener` still auto-joins through
  `handleIncomingGroupInvite(...)`, so the next delta is a durable
  pending-invite store plus accept/decline/expiry use cases that preserve the
  existing join and inbox-drain path on explicit accept.
- `2026-04-05`: Session `2` accepted after landing the
  `pending_group_invites` migration and repository, refactoring
  `GroupInviteListener` to store pending review items instead of auto-joining,
  adding accept/decline/expiry use cases with explicit join plus inbox-drain
  reuse on acceptance, and passing the direct invite tests, the full migration
  chain, and `./scripts/run_test_gates.sh groups`.
- `2026-04-05`: Session `3` accepted after landing the shipped mute toggle in
  `GroupInfoWired`, the pending invite review section in `GroupListWired`,
  direct presentation regressions in `group_info_screen_test.dart`,
  `group_info_wired_test.dart`, `group_list_screen_test.dart`, and
  `group_list_wired_test.dart`, plus another same-day passing
  `./scripts/run_test_gates.sh groups` run.
- `2026-04-05`: Session `4` accepted after adding the visible expired-invite
  UI regression, refreshing the maintained audit/network/matrix docs so
  `UX-004` and `UX-012` now read as closed rather than unsupported, and
  re-running the mute and invite-decision direct tests while carrying forward
  the same-day passing `./scripts/run_test_gates.sh groups` evidence.

## Final program verdict

- Status:
  `closed`
- Closed on:
  `2026-04-05`
- Closure summary:
  - doc `61` is now a landed product contract rather than unsupported scope
  - the repo ships per-group mute with persisted `is_muted` notification
    suppression plus a shipped mute/unmute control in group info
  - the repo ships explicit invite accept, decline, and expiry through durable
    pending invite storage, a shipped review surface in the group list, and
    explicit non-join cleanup for decline and expired invites
  - the maintained audit and matrix docs now describe `UX-004` and `UX-012`
    as closed, and the unsupported-feature index no longer lists them
- Final verification:
  - `flutter test test/features/groups/presentation/group_info_screen_test.dart`
  - `flutter test test/features/groups/presentation/group_info_wired_test.dart`
  - `flutter test test/features/groups/application/set_group_muted_use_case_test.dart test/features/groups/application/group_message_listener_test.dart`
  - `flutter test test/features/groups/application/accept_pending_group_invite_use_case_test.dart test/features/groups/application/decline_pending_group_invite_use_case_test.dart test/features/groups/presentation/group_list_screen_test.dart test/features/groups/presentation/group_list_wired_test.dart`
  - `./scripts/run_test_gates.sh groups`

## Ordered session breakdown

### Session 1

- Title:
  `Ship the per-group mute persistence and notification suppression contract`
- Session id:
  `1`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/61-group-notification-mute-and-invite-decision-controls-session-1-plan.md`
- Exact scope:
  - add the repo-local group mute state required to remember whether a joined
    group should suppress local notifications
  - create a narrow mutation path to mute and unmute one joined group
  - make `GroupMessageListener` skip local notifications for muted groups while
    preserving delivery, persistence, and unread behavior
  - keep the existing active-conversation, duplicate, and self-removal
    notification suppression rules intact for unmuted groups
  - add direct model/repository/listener regressions for mute persistence and
    mute-aware notification gating
- Why it is its own session:
  - mute is a bounded persistence plus listener seam that can land safely
    before any new UI
  - separating it prevents invite-lifecycle work from obscuring notification
    regressions
- Likely code-entry files:
  - `lib/core/database/migrations/017_groups_tables.dart`
  - `lib/main.dart`
  - `lib/features/groups/domain/models/group_model.dart`
  - `lib/features/groups/domain/repositories/group_repository_impl.dart`
  - `lib/features/groups/application/group_message_listener.dart`
  - `test/features/groups/domain/models/group_model_test.dart`
  - `test/features/groups/domain/repositories/group_repository_impl_test.dart`
  - `test/features/groups/application/group_message_listener_test.dart`
- Likely named gates:
  - `./scripts/run_test_gates.sh groups`

### Session 2

- Title:
  `Introduce pending group-invite decision lifecycle and acceptance use cases`
- Session id:
  `2`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/61-group-notification-mute-and-invite-decision-controls-session-2-plan.md`
- Exact scope:
  - create repo-local pending invite persistence instead of auto-joining on
    receipt
  - refactor the invite listener so valid invites become pending review items
    rather than silently joined groups
  - add accept, decline, and expiry behavior that either materializes the group
    through the existing join/drain path or leaves no ghost group state behind
  - preserve current sender validation, duplicate-group protection, and bridge
    join/drain behavior once an invite is accepted
  - add direct application/integration regressions for pending, accept,
    decline, duplicate, and expiry outcomes
- Why it is its own session:
  - pending invite lifecycle needs new persistence and listener behavior before
    any UI can truthfully act on invites
  - this seam is broad enough to deserve isolated verification from mute and UI
- Likely code-entry files:
  - `lib/features/groups/application/group_invite_listener.dart`
  - `lib/features/groups/application/handle_incoming_group_invite_use_case.dart`
  - `lib/features/groups/application/*group_invite*_use_case.dart`
  - `lib/features/groups/domain/models/*invite*`
  - `lib/features/groups/domain/repositories/*invite*`
  - `test/features/groups/application/group_invite_listener_test.dart`
  - `test/features/groups/application/handle_incoming_group_invite_use_case_test.dart`
  - `test/features/groups/integration/invite_round_trip_test.dart`
- Likely named gates:
  - `./scripts/run_test_gates.sh groups`

### Session 3

- Title:
  `Expose mute controls and pending invite decisions in shipped surfaces`
- Session id:
  `3`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/61-group-notification-mute-and-invite-decision-controls-session-3-plan.md`
- Exact scope:
  - add a user-facing mute/unmute control to an existing joined-group surface
  - add a bounded pending-invite review surface that lets users accept or
    decline without silently joining
  - refresh the joined group list when invite decisions resolve
  - keep the UI honest about pending, expired, accepted, and declined states
  - add widget/wired regressions for the mute affordance, pending invite row,
    accept, decline, and joined-list refresh
- Why it is its own session:
  - the presentation and state-refresh seam is separate from the underlying
    invite lifecycle and mute persistence contracts
  - this split keeps UI regressions from being confused with persistence bugs
- Likely code-entry files:
  - `lib/features/groups/presentation/screens/group_info_screen.dart`
  - `lib/features/groups/presentation/screens/group_info_wired.dart`
  - `lib/features/groups/presentation/screens/group_list_screen.dart`
  - `lib/features/groups/presentation/screens/group_list_wired.dart`
  - `lib/features/home/presentation/screens/first_time_experience_wired.dart`
  - `test/features/groups/presentation/group_info_screen_test.dart`
  - `test/features/groups/presentation/group_list_wired_test.dart`
- Likely named gates:
  - `./scripts/run_test_gates.sh groups`

### Session 4

- Title:
  `Close mute and invite-decision matrix rows with integration proof and doc updates`
- Session id:
  `4`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/61-group-notification-mute-and-invite-decision-controls-session-4-plan.md`
- Exact scope:
  - add or tighten the exact row-closing regressions for `UX-004` and
    `UX-012`, especially mute-with-delivery and invite decline/expiry truth
  - refresh the maintained audit/network/matrix docs so they stop marking these
    journeys unsupported
  - persist the finished doc verdict after code, tests, and docs agree
- Why it is its own session:
  - row closure requires final evidence and long-lived doc truth, not just code
    landing
  - keeping it separate prevents accepting the doc before the matrix is honest
- Likely code-entry files:
  - `test/features/groups/application/group_message_listener_test.dart`
  - `test/features/groups/integration/invite_round_trip_test.dart`
  - `test/features/groups/integration/group_membership_smoke_test.dart`
  - `Test-Flight-Improv/11-group-discussion-use-case-audit.md`
  - `Test-Flight-Improv/09-network-group-messaging.md`
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`
  - `Test-Flight-Improv/libp2p_group_chat_matrix_features_did_not_exist.md`
- Likely named gates:
  - `./scripts/run_test_gates.sh groups`
