# Session 13 Plan: Add Announcement-Specific Create-Group Regression

**Date:** 2026-03-26
**Status:** Plan only

## 1. Real Scope

Add a direct, easy-to-find Flutter-tree regression that proves announcement creation itself, without relying on the broader announcement happy path to infer correctness.

The minimum proof target is:
- the submitted group type is `announcement`
- the created `GroupModel` remains `announcement`
- the creator still becomes admin and the creation metadata stays correct
- announcement type persistence/mapping is pinned directly at the DB/helper or repository round-trip layer

The real product entry path also needs direct proof:
- Orbit launches announcement creation with `GroupType.announcement`
- `OrbitWired` routes that into `CreateGroupPickerWired`
- `CreateGroupPickerWired` forwards the type into `createGroupWithMembers`
- the plan should prove that route preserves `GroupType.announcement` without broadening into the full announcement happy path

Out of scope:
- the broader create -> send -> read-only -> react flow already covered elsewhere
- Go-side announcement auth or validator work
- new announcement product behavior

## 2. Session Classification

`implementation-ready`

Why:
- all relevant code and tests live in this Flutter tree
- the gap is an app-side regression coverage gap, not a cross-repo contract issue
- the current code paths are already visible and implementation-ready

## 3. Files and Repos to Inspect Next

Primary code paths:
- `Test-Flight-Improv/01-unit-test-coverage.md`
- `Test-Flight-Improv/13-announcement-use-case-audit.md`
- `lib/features/groups/application/create_group_use_case.dart`
- `lib/features/groups/application/create_group_with_members_use_case.dart`
- `lib/features/groups/presentation/screens/create_group_wired.dart`
- `lib/features/groups/presentation/screens/create_group_picker_wired.dart`
- `lib/features/groups/presentation/screens/create_group_screen.dart`
- `lib/features/groups/presentation/screens/create_group_picker_screen.dart`
- `lib/features/groups/domain/models/group_model.dart`
- `lib/core/bridge/bridge_group_helpers.dart`
- `lib/features/groups/domain/repositories/group_repository_impl.dart`
- `lib/core/database/helpers/groups_db_helpers.dart`

Primary tests to extend or reuse:
- `test/features/groups/application/create_group_use_case_test.dart`
- `test/features/groups/application/create_group_with_members_use_case_test.dart`
- `test/features/groups/presentation/create_group_screen_test.dart`
- `test/features/groups/presentation/create_group_picker_wired_test.dart`
- `test/features/groups/domain/models/group_model_test.dart`
- `test/features/groups/domain/repositories/group_repository_impl_test.dart`
- `test/core/database/helpers/groups_db_helpers_test.dart`
- `test/features/groups/integration/announcement_happy_path_test.dart`

## 4. Existing Tests Covering This Area

Already useful coverage exists:
- `test/features/groups/integration/announcement_happy_path_test.dart` already proves the broader announcement create/send/read-only/react flow and shows the group type stays `announcement`
- `test/features/groups/presentation/create_group_screen_test.dart` already proves `initialType: GroupType.announcement` is preselected at the pure screen layer
- `test/features/groups/domain/models/group_model_test.dart` already proves `GroupType.fromValue('announcement')` and `toValue()` work
- `test/features/groups/application/create_group_use_case_test.dart` already proves the direct create path for `chat`, including saving group/member/key
- `test/features/groups/application/create_group_with_members_use_case_test.dart` already proves create-with-members orchestration for `chat`, including `group:updateConfig`
- `test/core/database/helpers/groups_db_helpers_test.dart` already proves generic group insert/load/update behavior, but only with the default `type = 'chat'`

What is still missing in an easy-to-find place:
- a direct announcement create-path regression in the create use-case area
- a direct announcement persistence/mapping regression in a real repository round-trip area
- a direct proof that the real Orbit announcement entry path preserves `GroupType.announcement` through `CreateGroupPickerWired` into `createGroupWithMembers`

## 5. Regression / Tests To Add First

Minimum safe regressions to add first:

1. `test/features/groups/application/create_group_use_case_test.dart`
- Add one focused test for `GroupType.announcement`
- Assert the bridge create request carries `groupType: 'announcement'`
- Assert the returned `GroupModel.type` is `GroupType.announcement`
- Assert the saved group in the repo remains `GroupType.announcement`
- Assert `createdBy`, `myRole`, and the self-member admin role still behave correctly

2. `test/features/groups/domain/repositories/group_repository_impl_test.dart`
- Add one focused announcement repository round-trip
- Save a `GroupModel` with `type: GroupType.announcement`
- Load it back through `repo.getGroup(...)`
- Assert the loaded `GroupModel.type` is still `GroupType.announcement`
- Assert the stored `createdBy`, `myRole`, and other creation metadata survive the mapped round-trip

3. `test/features/groups/presentation/create_group_picker_wired_test.dart`
- Add one narrow regression that builds `CreateGroupPickerWired(groupType: GroupType.announcement, ...)`
- Select a contact and start creation
- Assert the created/saved group is `GroupType.announcement`
- Assert the real announcement entry route survives into the final create call
- Require this because the actual product path runs through Orbit -> `CreateGroupPickerWired`, not the pure `CreateGroupScreen` path

Optional adjacent raw-row persistence check:
- `test/core/database/helpers/groups_db_helpers_test.dart` may add one `type: 'announcement'` row case, but only as raw-row persistence evidence
- do not call that test full mapping proof by itself

4. `test/features/groups/application/create_group_with_members_use_case_test.dart`
- Add one required announcement-path regression
- Assert `result.group.type == GroupType.announcement`
- Assert the emitted `group:updateConfig` payload carries `groupType: 'announcement'`
- Treat this as required because the real product route uses `createGroupWithMembers`, not only the lower-level `createGroup` helper

## 6. Evidence To Capture First

Capture these before editing:
- the exact bridge payload emitted by `createGroup` for announcement creation
- the exact saved group retrieved from the repo after the announcement create test
- the exact repository round-trip result for an announcement group loaded through `GroupRepositoryImpl`
- the exact Orbit announcement entry path from `orbit_screen.dart` -> `orbit_wired.dart` -> `CreateGroupPickerWired` -> `createGroupWithMembers`
- the exact `group:updateConfig` payload emitted by `createGroupWithMembers` for announcement creation
- the fact that `announcement_happy_path_test.dart` is broader adjacent evidence, not the primary regression location for this session

## 7. Step-by-Step Implementation Or Evidence-Collection Plan

1. Add the direct application-layer announcement regression in `create_group_use_case_test.dart`.
2. Add the mapped announcement round-trip in `group_repository_impl_test.dart`.
3. Add the required announcement-path regression in `create_group_with_members_use_case_test.dart` so the real create-with-members flow proves `groupType` propagation into `group:updateConfig`.
4. Add the required Orbit-entry announcement-path regression in `create_group_picker_wired_test.dart`.
5. Only if a raw-row persistence sanity check adds value while editing nearby files, add one `announcement` row case in `groups_db_helpers_test.dart`, but keep it clearly labeled as raw-row coverage.
6. Re-run only the touched direct test set.
7. Run the Group Messaging Gate.
8. Run the Baseline Gate.

## 8. Risks And Edge Cases

- `announcement_happy_path_test.dart` already proves the broader flow, so this session can easily drift into duplicate coverage if not kept narrow.
- The current create use-case tests use `InMemoryGroupRepository`, which does not exercise DB row mapping. Without a repository round-trip, announcement persistence remains indirect.
- `create_group_screen_test.dart` already covers the pure `initialType` preselect, but that is not the actual product announcement entry route.
- `create_group_picker_wired_test.dart` currently exercises only `groupType: GroupType.chat`, so the Orbit announcement route still lacks direct proof until one focused announcement-path regression lands.
- `create_group_with_members_use_case_test.dart` is also chat-only today, so `group:updateConfig` announcement propagation can regress silently without a direct test.
- The test must keep admin/member role expectations intact while focusing on type, or it risks proving only the enum and missing creation metadata regressions.
- Do not drift into Go-side announcement writer enforcement; that is Session 14.

## 9. Exact Tests To Run After Implementation

Default direct tests:

```bash
flutter test test/features/groups/application/create_group_use_case_test.dart
flutter test test/features/groups/application/create_group_with_members_use_case_test.dart
flutter test test/features/groups/domain/repositories/group_repository_impl_test.dart
flutter test test/features/groups/presentation/create_group_picker_wired_test.dart
```

Conditional direct tests:

```bash
flutter test test/core/database/helpers/groups_db_helpers_test.dart
```

Only run this broader adjacent test if the execution pass intentionally touches it:

```bash
flutter test test/features/groups/integration/announcement_happy_path_test.dart
```

## 10. Subsystem Gate(s)

Required subsystem gate:

```bash
./scripts/run_test_gates.sh groups
```

Why:
- the change lives in shared group creation behavior
- Session 13 is explicitly a Group Messaging area change

## 11. Whether Baseline Gate Is Required

Yes.

Reason:
- Session 13 changes Flutter production/test code in a shared group creation path
- the roadmap item explicitly marks Baseline Gate as required

## 12. Whether Startup / Transport Gate Is Required

No.

Reason:
- the scoped work is group creation, type propagation, and persistence coverage
- it does not touch bootstrap, reconnect, resume, or transport fallback behavior

## 13. Done Criteria

This session is complete when:
- there is a direct, easy-to-find test proving announcement creation specifically
- the primary create path no longer relies on the broader announcement happy path as its only evidence
- announcement persistence/mapping is directly pinned at the repository round-trip layer
- the real Orbit announcement entry path proves `GroupType.announcement` survives through `CreateGroupPickerWired` into the final create call without broadening the flow
- the real create-with-members path proves `group:updateConfig` keeps `groupType: 'announcement'`
- no Go-side auth or broader send/read/react scope has been added
- the direct test set, Group Messaging Gate, and Baseline Gate have been run

## 14. Dependency Impact On Later Sessions If This Session Blocks

- Session 14 does not require Session 13 to land first; Go-side announcement writer enforcement can still proceed independently.
- Later profile-gated Sessions 15, 16, and 17 are independent of this create-group regression.
- If Session 13 blocks, Session 21 through Session 23 also remain independent.
- The main impact of a Session 13 block is local: announcement creation proof stays fragmented, and later reviewers still have to infer app-side correctness from broader announcement tests.

## 15. Scope Guard

- Do not drift into the broader create -> send -> read-only -> react flow already covered by `announcement_happy_path_test.dart`.
- Do not broaden into Go-side announcement auth or validator work.
- Do not add new announcement product features.
- Do not add redundant pure screen tests if `create_group_screen_test.dart` already proves the `initialType` preselect.
- Prefer the smallest proof layer that directly answers the coverage gap.
