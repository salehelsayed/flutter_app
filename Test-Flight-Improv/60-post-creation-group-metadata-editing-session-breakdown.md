# 60 - Post-Creation Group Metadata Editing Session Breakdown

## Decomposition artifact updated

- Artifact path:
  `Test-Flight-Improv/60-post-creation-group-metadata-editing-session-breakdown.md`
- Proposal/source doc path:
  `Test-Flight-Improv/60-post-creation-group-metadata-editing.md`
- Decomposition date:
  `2026-04-05`
- Downstream workflow rule:
  - detailed planning happens one session at a time
  - later sessions must be refreshed against landed code before execution

## Recommended plan count

- `3`

## Overall closure bar

Report `60` closed only when post-creation group metadata editing is a landed,
truthful product contract rather than explicit unsupported scope:

- group admins can rename a group and change its description after creation
  without forking peer-visible metadata
- group admins can add, replace, or remove a group avatar after creation and
  peers later converge to the same image or no-image outcome
- non-admin metadata edits fail deterministically both in the local mutation
  path and when raw unauthorized update envelopes arrive
- group list, conversation header, group info, invite/rejoin config, and
  offline recovery all resolve to the same final metadata state
- repeated or out-of-order metadata edits settle on one explicit final name,
  description, and avatar contract under tests rather than informal arrival
  order assumptions
- the maintained audit and matrix docs no longer mark rename, description edit,
  or avatar/photo management as unsupported once code and tests own them

## Source of truth

Primary governing docs:

- `Test-Flight-Improv/60-post-creation-group-metadata-editing.md`
- `Test-Flight-Improv/11-group-discussion-use-case-audit.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/09-network-group-messaging.md`
- `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`
- `Test-Flight-Improv/libp2p_group_chat_matrix_features_did_not_exist.md`

Current repo facts that govern the split:

- the repo already persists post-creation group rows and rebuilds group config
  maps in several send/rejoin paths, so metadata editing is primarily a
  correctness-and-propagation seam rather than a greenfield feature module
- `GroupInfoScreen` and `GroupInfoWired` already own the existing admin-only
  group-management controls, so the edit entry point should extend that
  surface rather than introduce a separate settings screen
- `GroupMessageListener` already owns authoritative config-application and
  stale-event handling for membership events, making it the right convergence
  seam for metadata updates too
- the repo still renders placeholder-only group avatars and does not persist a
  post-creation group image contract today, so avatar support needs both local
  storage and relay/config propagation
- the maintained audit docs currently keep group avatar/name/description work
  as unsupported scope, so final acceptance requires a doc-closure pass

Source-of-truth conflicts that materially affected decomposition:

- the proposal keeps exact image constraints and UI placement open, but the
  repo already has a narrow admin management surface and an existing avatar
  normalization/media-upload stack, so the safe split is by technical seam
  rather than by each visible control
- description and avatar removal need explicit null-clearing semantics in the
  group config, which is broader than a pure UI session and therefore belongs
  in the core metadata contract before the edit form lands

## Session ledger

| Session ID | Title | Classification | Intended plan file | Depends on | Current status | Closure docs touched | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `1` | `Ship the metadata mutation, persistence, and convergence contract` | `implementation-ready` | `Test-Flight-Improv/60-post-creation-group-metadata-editing-session-1-plan.md` | none | `accepted` | `Test-Flight-Improv/60-post-creation-group-metadata-editing-session-breakdown.md` | Accepted on `2026-04-05` after landing group metadata DB/model fields, the shared metadata config builder, admin-authorized rename/description/avatar mutation, invite/listener avatar propagation plus stale-event rejection, and the direct migration/model/repository/invite/listener regressions, then verifying `flutter test test/core/database/migrations/049_groups_metadata_columns_test.dart`, `flutter test test/core/database/integration/full_migration_chain_test.dart`, `flutter test test/features/groups/domain/models/group_model_test.dart`, `flutter test test/features/groups/domain/repositories/group_repository_impl_test.dart`, `flutter test test/features/groups/application/update_group_metadata_use_case_test.dart`, `flutter test test/features/groups/application/handle_incoming_group_invite_use_case_test.dart`, `flutter test test/features/groups/application/group_message_listener_test.dart`, and `./scripts/run_test_gates.sh groups`. |
| `2` | `Expose admin metadata editing in the shipped group surfaces` | `implementation-ready` | `Test-Flight-Improv/60-post-creation-group-metadata-editing-session-2-plan.md` | `1` | `accepted` | `Test-Flight-Improv/60-post-creation-group-metadata-editing-session-breakdown.md` | Accepted on `2026-04-05` after landing the shared group-avatar surface, the admin-only group-info metadata editor, route-return conversation refresh, and the leave/announcement permission regressions uncovered during verification, then revalidating `flutter test test/features/groups/presentation/group_info_screen_test.dart`, `flutter test test/features/groups/presentation/group_info_wired_test.dart`, `flutter test test/features/groups/presentation/group_card_test.dart`, `flutter test test/features/groups/presentation/group_list_wired_test.dart`, `flutter test test/features/groups/presentation/group_conversation_wired_test.dart`, and `./scripts/run_test_gates.sh groups`. |
| `3` | `Close the metadata rows with recovery proof and doc updates` | `implementation-ready` | `Test-Flight-Improv/60-post-creation-group-metadata-editing-session-3-plan.md` | `1`, `2` | `accepted` | `Test-Flight-Improv/11-group-discussion-use-case-audit.md`, `Test-Flight-Improv/09-network-group-messaging.md`, `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`, `Test-Flight-Improv/libp2p_group_chat_matrix_features_did_not_exist.md`, `Test-Flight-Improv/60-post-creation-group-metadata-editing-session-breakdown.md` | Accepted on `2026-04-05` after landing the direct admin metadata-edit widget proof, the offline repeated-metadata recovery regression, and the maintained doc refresh for `MR-023`, `SC-002`, `UX-002`, and `UX-003`, then verifying `flutter test test/features/groups/presentation/group_info_wired_test.dart --plain-name "admin metadata edit updates repo state, timeline, and bridge payloads"`, `flutter test test/features/groups/application/group_message_listener_test.dart`, `flutter test test/features/groups/integration/group_resume_recovery_test.dart --plain-name "offline member reconnects after repeated metadata edits and converges to the final metadata state"`, and `./scripts/run_test_gates.sh groups`. |

## Pipeline progress

- `2026-04-05`: Reusable doc-60 breakdown artifact created locally. Session
  `1` was the first runnable session.
- `2026-04-05`: Session `1` moved to `accepted` after the metadata
  persistence/convergence contract landed, the direct migration/model/
  repository/use-case/listener suites passed sequentially, and
  `./scripts/run_test_gates.sh groups` passed cleanly. Session `2` is now the
  next runnable session.
- `2026-04-05`: Session `2` moved to `accepted` after the shipped metadata
  editing surface landed, the direct presentation suites were rerun
  sequentially, the stale route-permission regression in
  `GroupConversationWired` was fixed, and `./scripts/run_test_gates.sh groups`
  passed cleanly again. Session `3` is now the next runnable session.
- `2026-04-05`: Session `3` moved to `accepted` after the admin metadata-edit
  widget proof and offline repeated-metadata recovery proof landed, the
  maintained audit/network/matrix docs were refreshed, and
  `./scripts/run_test_gates.sh groups` passed cleanly again.

## Final program verdict

- Status:
  `closed`
- Closed on:
  `2026-04-05`
- Closure summary:
  - doc `60` is now a landed product contract rather than unsupported scope
  - the repo ships post-creation group rename, description editing, and photo
    metadata propagation with admin-only UI access, unauthorized raw metadata
    rejection, and stale/offline final-state convergence under
    `lastMetadataEventAt`
  - the maintained audit and matrix docs now describe those rows as closed,
    and the unsupported-feature index no longer lists the metadata rows
- Final verification:
  - `flutter test test/features/groups/presentation/group_info_wired_test.dart --plain-name "admin metadata edit updates repo state, timeline, and bridge payloads"`
  - `flutter test test/features/groups/application/group_message_listener_test.dart`
  - `flutter test test/features/groups/integration/group_resume_recovery_test.dart --plain-name "offline member reconnects after repeated metadata edits and converges to the final metadata state"`
  - `./scripts/run_test_gates.sh groups`

## Ordered session breakdown

### Session 1

- Title:
  `Ship the metadata mutation, persistence, and convergence contract`
- Session id:
  `1`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/60-post-creation-group-metadata-editing-session-1-plan.md`
- Exact scope:
  - add the repo-local group metadata fields and migration support required for
    post-creation name, description, and avatar state
  - create or tighten the admin-authorized mutation path for metadata edits,
    including explicit null-clearing for description/avatar removal
  - propagate the authoritative metadata snapshot through invite, rejoin,
    membership, and dedicated metadata-update envelopes so offline peers can
    converge later
  - download and persist group avatar blobs on recipients so group metadata can
    carry a real image rather than a placeholder-only contract
  - reject unauthorized raw metadata updates and stale metadata events under
    direct tests
- Why it is its own session:
  - this is the core correctness seam; UI work should not guess at unsupported
    transport, persistence, or convergence behavior
  - avatar support requires durable storage and relay/config wiring that is
    broader than a presentation-only patch
- Likely code-entry files:
  - `lib/core/database/migrations/017_groups_tables.dart`
  - `lib/core/database/migrations/049_groups_metadata_columns.dart`
  - `lib/main.dart`
  - `lib/features/groups/domain/models/group_model.dart`
  - `lib/features/groups/application/group_message_listener.dart`
  - `lib/features/groups/application/handle_incoming_group_invite_use_case.dart`
  - `lib/features/groups/application/rejoin_group_topics_use_case.dart`
  - `lib/features/groups/application/create_group_with_members_use_case.dart`
  - `lib/features/groups/application/add_group_member_use_case.dart`
  - `lib/features/groups/application/remove_group_member_use_case.dart`
  - `lib/features/groups/application/update_group_member_role_use_case.dart`
  - `lib/features/groups/presentation/screens/contact_picker_wired.dart`
- Likely direct tests/regressions:
  - `test/features/groups/domain/models/group_model_test.dart`
  - `test/features/groups/domain/repositories/group_repository_impl_test.dart`
  - `test/features/groups/application/group_message_listener_test.dart`
  - `test/features/groups/application/handle_incoming_group_invite_use_case_test.dart`
  - `test/features/groups/integration/group_resume_recovery_test.dart`
- Likely named gates:
  - `./scripts/run_test_gates.sh groups`
- Matrix/closure docs to update when done:
  - required:
    - `Test-Flight-Improv/60-post-creation-group-metadata-editing-session-breakdown.md`
  - intentionally deferred to Session `3`:
    - `Test-Flight-Improv/11-group-discussion-use-case-audit.md`
    - `Test-Flight-Improv/09-network-group-messaging.md`
    - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`
    - `Test-Flight-Improv/libp2p_group_chat_matrix_features_did_not_exist.md`
- Dependency on earlier sessions:
  - none
- Downstream execution path:
  - `$implementation-plan-orchestrator`
  - `$implementation-execution-qa-orchestrator`
  - `$implementation-closure-audit-orchestrator`

### Session 2

- Title:
  `Expose admin metadata editing in the shipped group surfaces`
- Session id:
  `2`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/60-post-creation-group-metadata-editing-session-2-plan.md`
- Exact scope:
  - add the admin edit affordances to the existing group info surface without
    regressing add/remove member or leave flows
  - support editing the name, description, and avatar from the shipped UI
  - block non-admins from seeing or completing the edit flow
  - make the conversation header, group list, and group info surface reflect
    the new metadata after the edit syncs
  - add widget/wired regressions for the edit entry point, submission path,
    image-change affordance, snackbar feedback, and non-admin blocking
- Why it is its own session:
  - the product surface and state-refresh contract are a different failure seam
    from the underlying metadata transport/storage work
  - separating it prevents backend convergence bugs from hiding behind UI noise
- Likely code-entry files:
  - `lib/features/groups/presentation/screens/group_info_screen.dart`
  - `lib/features/groups/presentation/screens/group_info_wired.dart`
  - `lib/features/groups/presentation/screens/group_conversation_wired.dart`
  - `lib/features/groups/presentation/screens/group_conversation_screen.dart`
  - `lib/features/groups/presentation/widgets/group_card.dart`
  - `lib/features/groups/presentation/widgets/group_avatar.dart`
- Likely direct tests/regressions:
  - `test/features/groups/presentation/group_info_screen_test.dart`
  - `test/features/groups/presentation/group_info_wired_test.dart`
  - `test/features/groups/presentation/group_card_test.dart`
  - `test/features/groups/presentation/group_list_wired_test.dart`
- Likely named gates:
  - `./scripts/run_test_gates.sh groups`
- Matrix/closure docs to update when done:
  - required:
    - `Test-Flight-Improv/60-post-creation-group-metadata-editing-session-breakdown.md`
  - intentionally deferred to Session `3`:
    - `Test-Flight-Improv/11-group-discussion-use-case-audit.md`
    - `Test-Flight-Improv/09-network-group-messaging.md`
    - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`
    - `Test-Flight-Improv/libp2p_group_chat_matrix_features_did_not_exist.md`
- Dependency on earlier sessions:
  - Session `1`
- Downstream execution path:
  - `$implementation-plan-orchestrator`
  - `$implementation-execution-qa-orchestrator`
  - `$implementation-closure-audit-orchestrator`

### Session 3

- Title:
  `Close the metadata rows with recovery proof and doc updates`
- Session id:
  `3`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/60-post-creation-group-metadata-editing-session-3-plan.md`
- Exact scope:
  - add or tighten the exact regressions that close `MR-023`, `SC-002`,
    `UX-002`, and `UX-003`, especially offline convergence and repeated edit
    ordering
  - document the final explicit metadata propagation contract that the landed
    code implements
  - update the maintained docs that currently record avatar/name/description
    editing as unsupported scope
  - persist the final finished verdict in this breakdown after code, tests, and
    docs all agree
- Why it is its own session:
  - row closure requires final evidence and doc truth, not just code landing
  - keeping the proof pass separate prevents accepting the feature before the
    long-lived matrix and audit docs are corrected
- Likely code-entry files:
  - `test/features/groups/application/group_message_listener_test.dart`
  - `test/features/groups/integration/group_resume_recovery_test.dart`
  - `test/features/groups/presentation/group_info_wired_test.dart`
  - `Test-Flight-Improv/11-group-discussion-use-case-audit.md`
  - `Test-Flight-Improv/09-network-group-messaging.md`
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`
  - `Test-Flight-Improv/libp2p_group_chat_matrix_features_did_not_exist.md`
- Likely direct tests/regressions:
  - `test/features/groups/application/group_message_listener_test.dart`
  - `test/features/groups/integration/group_resume_recovery_test.dart`
  - `test/features/groups/presentation/group_info_wired_test.dart`
- Likely named gates:
  - `./scripts/run_test_gates.sh groups`
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/11-group-discussion-use-case-audit.md`
  - `Test-Flight-Improv/09-network-group-messaging.md`
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`
  - `Test-Flight-Improv/libp2p_group_chat_matrix_features_did_not_exist.md`
  - `Test-Flight-Improv/60-post-creation-group-metadata-editing-session-breakdown.md`
- Dependency on earlier sessions:
  - Session `1`
  - Session `2`
- Downstream execution path:
  - `$implementation-plan-orchestrator`
  - `$implementation-execution-qa-orchestrator`
  - `$implementation-closure-audit-orchestrator`
