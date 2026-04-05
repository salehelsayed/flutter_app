# 62 - Admin-Initiated Group Dissolve Session Breakdown

## Decomposition artifact updated

- Artifact path:
  `Test-Flight-Improv/62-admin-initiated-group-dissolve-session-breakdown.md`
- Proposal/source doc path:
  `Test-Flight-Improv/62-admin-initiated-group-dissolve.md`
- Decomposition date:
  `2026-04-05`
- Downstream workflow rule:
  - detailed planning happens one session at a time
  - later sessions must be refreshed against landed code before execution

## Recommended plan count

- `4`

## Overall closure bar

Report `62` is closed only when admin-initiated dissolve is a landed, truthful
product contract rather than explicit unsupported scope:

- an admin can explicitly dissolve a group for everyone instead of only leaving
  it locally
- dissolved groups remain locally visible as read-only history rather than
  silently disappearing or staying active
- local and remote members converge on the same dissolved state, including
  offline recipients who learn the dissolve later through the existing inbox
  recovery path
- post-dissolve sends are rejected predictably in both the local send path and
  the visible UI contract
- restart and recovery no longer rejoin dissolved groups to live pubsub topics
- the maintained audit and matrix docs no longer list `UX-014` as unsupported
  once code, tests, and shipped UI own the behavior

## Source of truth

Primary governing docs:

- `Test-Flight-Improv/62-admin-initiated-group-dissolve.md`
- `Test-Flight-Improv/11-group-discussion-use-case-audit.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/09-network-group-messaging.md`
- `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`
- `Test-Flight-Improv/libp2p_group_chat_matrix_features_did_not_exist.md`

Current repo facts that govern the split:

- `leaveGroup(...)` currently means local personal exit and deletes the local
  group row, so dissolve needs a distinct durable state instead of reusing that
  deletion path
- `GroupMessageListener` already owns authenticated system-message application,
  timeline emission, and offline replay parity, so remote dissolve convergence
  belongs in that listener seam rather than in UI-only code
- `sendGroupMessage(...)` and `rejoinGroupTopics(...)` are the two repo-owned
  seams that currently still treat every stored group as writable and rejoinable
- `GroupConversationWired` and `GroupInfoWired` already own the existing
  conversation read-only and group-management affordances, so dissolve UI can
  land without inventing a new surface
- maintained audit and matrix docs still call admin-initiated dissolve
  unsupported, so a final closure pass must update those long-lived docs after
  the code and tests land

Source-of-truth conflicts that materially affected decomposition:

- the product doc allowed either removal or read-only retention after dissolve;
  this breakdown chooses retained read-only history because it preserves
  timeline evidence, keeps offline convergence inspectable, and avoids
  reinterpreting `leaveGroup(...)`
- dissolve is not only a destructive button; it also changes transport,
  listener, replay, and send semantics, so storage and network enforcement must
  land before the UI can be truthful

## Session ledger

| Session ID | Title | Classification | Intended plan file | Depends on | Current status | Closure docs touched | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `1` | `Persist the dissolved-group state and read-only model contract` | `implementation-ready` | `Test-Flight-Improv/62-admin-initiated-group-dissolve-session-1-plan.md` | none | `accepted` | `Test-Flight-Improv/62-admin-initiated-group-dissolve-session-breakdown.md`, `Test-Flight-Improv/62-admin-initiated-group-dissolve-session-1-plan.md` | Landed durable `is_dissolved` / `dissolved_at` / `dissolved_by` storage, the new `052_groups_dissolve_columns.dart` migration, group-model and repository round-trip coverage, and a passing full migration-chain verification on `2026-04-05`. |
| `2` | `Ship authenticated dissolve propagation, offline convergence, and send/rejoin enforcement` | `implementation-ready` | `Test-Flight-Improv/62-admin-initiated-group-dissolve-session-2-plan.md` | `1` | `accepted` | `Test-Flight-Improv/62-admin-initiated-group-dissolve-session-breakdown.md`, `Test-Flight-Improv/62-admin-initiated-group-dissolve-session-2-plan.md` | Landed the admin dissolve use case, authenticated `group_dissolved` listener handling, offline replay parity, send rejection, rejoin skipping, and the multi-user dissolve convergence regression on `2026-04-05`. |
| `3` | `Expose dissolve and dissolved-state UI in shipped group surfaces` | `implementation-ready` | `Test-Flight-Improv/62-admin-initiated-group-dissolve-session-3-plan.md` | `1`, `2` | `accepted` | `Test-Flight-Improv/62-admin-initiated-group-dissolve-session-breakdown.md`, `Test-Flight-Improv/62-admin-initiated-group-dissolve-session-3-plan.md` | Landed the admin-only group-info dissolve action, retained-history dissolved status across info/conversation/list surfaces, distinct dissolved read-only copy, and direct presentation coverage on `2026-04-05`. |
| `4` | `Close UX-014 with maintained-doc updates and final verification` | `implementation-ready` | `Test-Flight-Improv/62-admin-initiated-group-dissolve-session-4-plan.md` | `1`, `2`, `3` | `accepted` | `Test-Flight-Improv/11-group-discussion-use-case-audit.md`, `Test-Flight-Improv/09-network-group-messaging.md`, `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`, `Test-Flight-Improv/libp2p_group_chat_matrix_features_did_not_exist.md`, `Test-Flight-Improv/62-admin-initiated-group-dissolve-session-breakdown.md` | Refreshed the maintained audit/matrix docs, removed `UX-014` from the unsupported tracker, and revalidated the full `groups` gate on `2026-04-05` after stabilizing the concurrent-admin membership smoke fixture. |

## Pipeline progress

- `2026-04-05`: Reusable doc-62 breakdown artifact created locally. Session
  `1` is the first runnable session.
- `2026-04-05`: Session `1` accepted after landing the dissolve columns in the
  fresh-install and upgrade schema paths, extending `GroupModel` and repo
  mapping with durable dissolved-state fields, and passing
  `test/core/database/migrations/052_groups_dissolve_columns_test.dart`,
  `test/features/groups/domain/models/group_model_test.dart`,
  `test/features/groups/domain/repositories/group_repository_impl_test.dart`,
  and `test/core/database/integration/full_migration_chain_test.dart`.
- `2026-04-05`: Session `2` accepted after landing
  `dissolve_group_use_case.dart`, `group_dissolved` listener handling,
  post-dissolve incoming/send/rejoin enforcement, and passing
  `test/features/groups/application/dissolve_group_use_case_test.dart`,
  `test/features/groups/application/group_message_listener_test.dart`,
  `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`,
  `test/features/groups/application/send_group_message_use_case_test.dart`,
  `test/features/groups/application/rejoin_group_topics_use_case_test.dart`,
  and `test/features/groups/integration/group_membership_smoke_test.dart`.
- `2026-04-05`: Session `3` accepted after landing the admin-only dissolve
  affordance in `GroupInfoWired`, dissolved read-only status/copy in
  `GroupInfoScreen` and `GroupConversationScreen`, group-list labeling in
  `GroupCard`, and passing
  `test/features/groups/presentation/group_info_screen_test.dart`,
  `test/features/groups/presentation/group_info_wired_test.dart`,
  `test/features/groups/presentation/group_conversation_screen_test.dart`,
  `test/features/groups/presentation/group_conversation_wired_test.dart`,
  and `test/features/groups/presentation/group_card_bidi_test.dart`.
- `2026-04-05`: Session `4` accepted after refreshing the maintained audit,
  network, and matrix docs so `UX-014` is described as landed behavior,
  removing it from the unsupported tracker, fixing the concurrent-admin smoke
  fixture to use deterministic pre-event timestamps, and passing both
  `flutter test test/features/groups/integration/group_membership_smoke_test.dart`
  and the same-day `./scripts/run_test_gates.sh groups` verification.

## Final program verdict

- Status:
  `closed`
- Last updated:
  `2026-04-05`
- Completion summary:
  - all four sessions are accepted and doc `62` now closes `UX-014` with
    landed code, direct tests, maintained-doc updates, and a passing full
    `groups` gate

## Ordered session breakdown

### Session 1

- Title:
  `Persist the dissolved-group state and read-only model contract`
- Session id:
  `1`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/62-admin-initiated-group-dissolve-session-1-plan.md`
- Exact scope:
  - add durable group columns that record whether a group is dissolved and who
    dissolved it
  - map the new dissolve fields through `GroupModel`, database helpers, and the
    repository implementation without changing existing non-dissolved behavior
  - make restart-time and fresh-install schema creation agree on the new
    columns
  - add direct model, repository, migration, and full-chain coverage for the
    new persisted state
- Why it is its own session:
  - later sessions need trustworthy stored dissolve facts before they can
    enforce send blocking, replay convergence, or UI state
  - keeping storage isolated reduces the risk of mixing schema regressions with
    network behavior changes
- Likely code-entry files:
  - `lib/core/database/migrations/017_groups_tables.dart`
  - `lib/core/database/migrations/*groups*.dart`
  - `lib/core/database/helpers/groups_db_helpers.dart`
  - `lib/features/groups/domain/models/group_model.dart`
  - `lib/features/groups/domain/repositories/group_repository_impl.dart`
  - `lib/main.dart`
  - `test/core/database/migrations/*groups*.dart`
  - `test/core/database/integration/full_migration_chain_test.dart`
  - `test/features/groups/domain/models/group_model_test.dart`
  - `test/features/groups/domain/repositories/group_repository_impl_test.dart`
- Likely named gates:
  - `flutter test test/core/database/integration/full_migration_chain_test.dart`

### Session 2

- Title:
  `Ship authenticated dissolve propagation, offline convergence, and send/rejoin enforcement`
- Session id:
  `2`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/62-admin-initiated-group-dissolve-session-2-plan.md`
- Exact scope:
  - add one admin-only dissolve use case that publishes a `group_dissolved`
    system event, attempts relay inbox fallback for offline members, marks the
    local group dissolved, stores a readable timeline event, and leaves the
    live topic without deleting history
  - teach `GroupMessageListener` to authenticate and apply
    `group_dissolved`, including duplicate/stale handling and offline replay
    parity
  - reject local sends to dissolved groups and ignore rejoin attempts for
    dissolved groups during startup/recovery
  - add direct application and integration regressions for local dissolve,
    remote receipt, duplicate handling, offline convergence, send rejection,
    and rejoin skipping
- Why it is its own session:
  - dissolve becomes truthful only when network, replay, and transport seams
    agree on the same final-state contract
  - this is the highest-risk logic seam and deserves isolated verification
- Likely code-entry files:
  - `lib/features/groups/application/*dissolve*.dart`
  - `lib/features/groups/application/group_message_listener.dart`
  - `lib/features/groups/application/group_membership_timeline_message.dart`
  - `lib/features/groups/application/send_group_message_use_case.dart`
  - `lib/features/groups/application/rejoin_group_topics_use_case.dart`
  - `test/features/groups/application/group_message_listener_test.dart`
  - `test/features/groups/application/send_group_message_use_case_test.dart`
  - `test/features/groups/application/rejoin_group_topics_use_case_test.dart`
  - `test/features/groups/integration/group_resume_recovery_test.dart`
- Likely named gates:
  - `./scripts/run_test_gates.sh groups`

### Session 3

- Title:
  `Expose dissolve and dissolved-state UI in shipped group surfaces`
- Session id:
  `3`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/62-admin-initiated-group-dissolve-session-3-plan.md`
- Exact scope:
  - add an admin-only dissolve action with confirmation in group info
  - show visible dissolved status in group info, group list, and conversation
  - make dissolved conversations read-only with explicit copy instead of the
    announcement-only banner
  - keep ordinary leave, member management, and metadata editing available only
    for non-dissolved groups
  - add widget and wired regressions for the dissolve action and visible
    read-only state
- Why it is its own session:
  - the UI should only land after the underlying dissolve state and network
    contract are already truthful
  - this keeps presentation regressions separate from storage and replay bugs
- Likely code-entry files:
  - `lib/features/groups/presentation/screens/group_info_screen.dart`
  - `lib/features/groups/presentation/screens/group_info_wired.dart`
  - `lib/features/groups/presentation/screens/group_conversation_screen.dart`
  - `lib/features/groups/presentation/screens/group_conversation_wired.dart`
  - `lib/features/groups/presentation/widgets/group_card.dart`
  - `test/features/groups/presentation/group_info_screen_test.dart`
  - `test/features/groups/presentation/group_info_wired_test.dart`
  - `test/features/groups/presentation/group_conversation_wired_test.dart`
  - `test/features/groups/presentation/group_card_test.dart`
- Likely named gates:
  - `./scripts/run_test_gates.sh groups`

### Session 4

- Title:
  `Close UX-014 with maintained-doc updates and final verification`
- Session id:
  `4`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/62-admin-initiated-group-dissolve-session-4-plan.md`
- Exact scope:
  - refresh the maintained audit, network, and matrix docs so
    admin-initiated dissolve is described as landed behavior with concrete
    proof references
  - remove `UX-014` from the unsupported-only tracker
  - persist the final doc-62 closure verdict once the maintained docs match the
    landed code and test truth
- Why it is its own session:
  - doc closure should happen only after code, tests, and shipped surfaces
    agree on the same dissolve contract
  - keeping it separate prevents premature matrix updates
- Likely code-entry files:
  - `Test-Flight-Improv/11-group-discussion-use-case-audit.md`
  - `Test-Flight-Improv/09-network-group-messaging.md`
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`
  - `Test-Flight-Improv/libp2p_group_chat_matrix_features_did_not_exist.md`
- Likely named gates:
  - reuse same-day passing `./scripts/run_test_gates.sh groups` evidence if the
    final pass is docs-only
