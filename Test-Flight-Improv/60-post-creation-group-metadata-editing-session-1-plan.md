# 60 - Session 1 Plan

## Scope

Land the repo-owned metadata contract for post-creation group name,
description, and avatar changes before any UI-first edit flow is accepted.

## In Scope

- add the persisted group metadata fields and migration chain needed for
  post-creation avatar plus metadata event-watermark support
- create the admin-authorized group metadata mutation path
- propagate metadata through authoritative group config builders used by create,
  invite, membership, and rejoin flows
- handle `group_metadata_updated` envelopes in `GroupMessageListener`,
  including stale-event rejection and unauthorized sender rejection
- download and persist group avatars for recipients when new metadata arrives
- add direct repository/model/listener/invite regressions for the new contract

## Out of Scope

- the admin edit UI surface itself
- group list / group info / conversation header presentation changes except
  whatever narrow hooks session 1 needs to keep the core contract callable
- audit or matrix doc closure

## Closure Bar

Session 1 is accepted only when:

- the repo can persist canonical post-creation metadata state for a group,
  including avatar metadata and a metadata watermark
- an admin-authenticated mutation path can update name, description, and avatar
  state locally without leaving the group row internally inconsistent
- invite/join/rejoin/config-update paths preserve the same metadata contract
- recipients reject stale or unauthorized metadata updates
- recipients can recover the latest avatar metadata and commit the avatar file
  locally when a valid update arrives
- direct tests cover the above seams and the `groups` gate still passes

## Files Likely To Change

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

## Verification

- `flutter test test/features/groups/domain/models/group_model_test.dart`
- `flutter test test/features/groups/domain/repositories/group_repository_impl_test.dart`
- `flutter test test/features/groups/application/group_message_listener_test.dart`
- `flutter test test/features/groups/application/handle_incoming_group_invite_use_case_test.dart`
- `flutter test test/features/groups/integration/group_resume_recovery_test.dart`
- `./scripts/run_test_gates.sh groups`
