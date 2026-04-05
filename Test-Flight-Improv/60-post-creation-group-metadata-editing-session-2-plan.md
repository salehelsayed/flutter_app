# 60 Session 2 Plan: Group Metadata Editing Surface and Visible Refresh

## Final verdict

- `implementation-ready`

## Final plan

### Real scope

- extend the existing group-info surface with an admin-only metadata editor
  instead of creating a second settings route
- support post-creation rename, description edit, avatar add/replace, and
  avatar removal through the landed session `1` metadata contract
- refresh the visible group-info, conversation-header, and group-list surfaces
  from repo truth after a metadata edit rather than relying on stale
  navigation-time `GroupModel` snapshots
- reuse the existing media picker, avatar normalization, and relay upload stack
  so the shipped photo flow matches the repo’s image-handling contract
- add direct presentation regressions for admin visibility, edit submission,
  image-change/remove affordances, snackbar feedback, and surface refresh

Out of scope for this session:

- audit/matrix/doc closure, which belongs to session `3`
- broader group settings redesign beyond what metadata editing requires
- notification mute, invite-decision, or dissolve controls from later docs

### Closure bar

Session `2` is done only when:

- an admin can open the shipped group-info surface and edit the group name,
  description, and photo from there
- the surface supports both adding/replacing a group photo and removing an
  existing one without leaving stale avatar state behind
- non-admin viewers do not see dead metadata-edit affordances
- successful edits show truthful feedback and refresh the group-info surface
  from repo state
- returning from group info refreshes the conversation header to the latest
  metadata, and the group-list card surface can render the updated avatar/name
- the direct presentation suites pass, plus the required named `groups` gate

### Source of truth

- active session contract:
  `Test-Flight-Improv/60-post-creation-group-metadata-editing-session-breakdown.md`
- product intent:
  `Test-Flight-Improv/60-post-creation-group-metadata-editing.md`
- gate definitions:
  `Test-Flight-Improv/test-gate-definitions.md`
- regression strategy:
  `Test-Flight-Improv/14-regression-test-strategy.md`
- landed session `1` code/test truth wins over stale prose on disagreement

### Session classification

- `implementation-ready`

### Exact problem statement

Session `1` landed the persistence and convergence contract, but the shipped UI
still exposes no metadata editor, still renders placeholder-only group avatars,
and still passes stale group snapshots into the conversation/info surfaces.
This session must ship the admin edit affordance on group info, reuse the
landed avatar pipeline, and refresh the visible surfaces from repo truth.

### Files and repos to inspect next

Production files:

- `lib/features/groups/presentation/screens/group_info_screen.dart`
- `lib/features/groups/presentation/screens/group_info_wired.dart`
- `lib/features/groups/presentation/screens/group_conversation_screen.dart`
- `lib/features/groups/presentation/screens/group_conversation_wired.dart`
- `lib/features/groups/presentation/screens/group_list_wired.dart`
- `lib/features/groups/presentation/widgets/group_card.dart`
- `lib/features/groups/presentation/widgets/group_member_row.dart`
- `lib/features/groups/application/update_group_metadata_use_case.dart`
- `lib/features/groups/application/group_avatar_storage.dart`
- `lib/features/conversation/application/upload_media_use_case.dart`
- `lib/core/media/media_picker.dart`
- `lib/features/settings/application/helpers/avatar_normalization_helper.dart`

Direct tests and helpers:

- `test/features/groups/presentation/group_info_screen_test.dart`
- `test/features/groups/presentation/group_info_wired_test.dart`
- `test/features/groups/presentation/group_card_test.dart`
- `test/features/groups/presentation/group_list_wired_test.dart`
- `test/features/groups/presentation/group_conversation_wired_test.dart`
- `test/shared/fakes/in_memory_group_repository.dart`
- `test/core/bridge/fake_bridge.dart`

### Existing tests covering this area

- `group_info_screen_test.dart` already proves the current member list and
  admin-only management affordance visibility
- `group_info_wired_test.dart` already proves add/remove member and admin-role
  flows on the shipped info surface
- `group_card_test.dart` and `group_list_wired_test.dart` already prove the
  group-list rendering and reload seam
- `group_conversation_wired_test.dart` already proves the group header route
  and refresh-sensitive screen behavior

Missing direct proof for this session:

- admin-only edit affordance visibility on group info
- successful rename/description/avatar edit submission through the shipped UI
- avatar removal from the UI
- conversation-header refresh after returning from group info
- list-card rendering of the stored group avatar

### Regression/tests to add first

- extend `test/features/groups/presentation/group_info_screen_test.dart` to
  prove the edit affordance is admin-only
- extend `test/features/groups/presentation/group_info_wired_test.dart` to
  prove:
  - rename/description/photo edits flow through the UI and persist to repo
  - the group metadata publish payload uses the landed `group_metadata_updated`
    contract
  - success feedback appears and the visible info surface refreshes
  - an existing avatar can be removed
- extend `test/features/groups/presentation/group_card_test.dart` and/or
  `group_list_wired_test.dart` to prove the list surface can render the stored
  avatar and reload to the updated metadata
- extend `test/features/groups/presentation/group_conversation_wired_test.dart`
  to prove the header refreshes after returning from group info

### Step-by-step implementation plan

1. Add a reusable group-avatar presentation widget so list, info, and
   conversation surfaces share one avatar-or-initials contract.
2. Add an admin-only edit-details affordance to `GroupInfoScreen`.
3. Teach `GroupInfoWired` to open a bounded metadata editor, pick/remove an
   avatar, upload it through the existing media pipeline, then call
   `updateGroupMetadata(...)` and publish the aligned `group_metadata_updated`
   system payload.
4. Refresh local group/member state after success or failure, and record a
   local timeline artifact when the UI performs the edit so the conversation
   route can show the same contract immediately after returning.
5. Refresh `GroupConversationWired` from repo truth when the info route
   returns after a mutation; let `GroupListWired` keep using its existing
   reload seam.
6. Land the direct presentation regressions first, then run the required
   `groups` gate sequentially.
7. Stop and return `blocked` if truthful surface refresh requires a wider
   live-subscription architecture than bounded route-return reloads.

### Risks and edge cases

- replacing an avatar at the same canonical path can leave stale image caches
  unless the presentation widget uses an explicit cache-busting key
- local metadata edits need the same `group_metadata_updated` payload shape as
  session `1`, or remote convergence will drift from the shipped UI
- the edit flow must not expose dead controls to non-admin members
- avatar removal must clear both repo metadata and the on-disk file
- the session must not regress the existing member add/remove, role-change, or
  leave flows already covered on the group-info route

### Exact tests and gates to run

Direct tests:

- `flutter test test/features/groups/presentation/group_info_screen_test.dart`
- `flutter test test/features/groups/presentation/group_info_wired_test.dart`
- `flutter test test/features/groups/presentation/group_card_test.dart`
- `flutter test test/features/groups/presentation/group_list_wired_test.dart`
- `flutter test test/features/groups/presentation/group_conversation_wired_test.dart`

Required named gates:

- `./scripts/run_test_gates.sh groups`

### Known-failure interpretation

- treat unrelated pre-existing failures outside the touched group metadata
  surfaces as known only if they reproduce on unchanged code and do not touch
  group-info editing, avatar rendering, or group-header/list refresh
- do not waive new failures in the presentation suites or the `groups` gate

### Done criteria

- a doc-scoped code/test delta lands for the shipped metadata-editing surface
- the direct presentation regressions exist and pass
- the required `groups` gate passes
- the session `2` ledger entry can truthfully move out of `pending`
- session `3` can close the matrix/doc rows against a stable shipped surface

### Scope guard

- do not widen into doc closure, mute controls, invite decisions, or dissolve
  work
- do not create a second metadata-management route outside the existing group
  info seam
- do not refactor unrelated message-list or live-subscription architecture
- do not update audit/matrix docs in this session except the breakdown/plan
  artifacts needed for pipeline bookkeeping

### Accepted differences / intentionally out of scope

- the metadata editor can be a bounded modal/sheet instead of a dedicated full
  screen settings flow
- exact avatar-source affordances can stay narrow as long as the shipped UI can
  truthfully add, replace, and remove a group photo

### Dependency impact

- session `3` depends on this plan landing the truthful shipped surface for
  `MR-023`, `UX-002`, and `UX-003`
- if this plan blocks materially, do not start session `3`

## Structural blockers remaining

- none

## Incremental details intentionally deferred

- final matrix-row wording and closure docs
- any extra multi-device proof beyond the named presentation suites and the
  `groups` gate

## Accepted differences intentionally left unchanged

- the app keeps the existing `GroupInfoScreen` plus `GroupInfoWired` split
- route-return reloads are sufficient for this session; no broader live
  subscription layer is introduced

## Exact docs/files used as evidence

- `Test-Flight-Improv/60-post-creation-group-metadata-editing-session-breakdown.md`
- `Test-Flight-Improv/60-post-creation-group-metadata-editing.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `lib/features/groups/presentation/screens/group_info_screen.dart`
- `lib/features/groups/presentation/screens/group_info_wired.dart`
- `lib/features/groups/presentation/screens/group_conversation_screen.dart`
- `lib/features/groups/presentation/screens/group_conversation_wired.dart`
- `lib/features/groups/presentation/screens/group_list_wired.dart`
- `lib/features/groups/presentation/widgets/group_card.dart`
- `lib/features/groups/application/update_group_metadata_use_case.dart`
- `lib/features/groups/application/group_avatar_storage.dart`
- `lib/features/conversation/application/upload_media_use_case.dart`
- `test/features/groups/presentation/group_info_screen_test.dart`
- `test/features/groups/presentation/group_info_wired_test.dart`
- `test/features/groups/presentation/group_card_test.dart`
- `test/features/groups/presentation/group_list_wired_test.dart`
- `test/features/groups/presentation/group_conversation_wired_test.dart`

## Why the plan is safe to implement now

- it builds directly on the landed session `1` metadata contract instead of
  reopening transport/persistence design
- it keeps the work inside the existing group-info/list/conversation seams and
  names exact direct regressions plus the required gate
- it leaves row closure and maintained-doc truth to session `3`, so this
  session stays focused on shipped product behavior
