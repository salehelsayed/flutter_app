Status: accepted
Acceptance Status: accepted
Mode: standard worktree-to-main integration, not gap-closure
Source row: `ML-010 | Duplicate add is idempotent and does not duplicate members or keys`
Integration row: `INTEGRATE-ML-010`

# INTEGRATE-ML-010 Worktree-to-Main Integration Plan

## Planning Evidence

- 2026-05-18 09:02 CEST - Started after `INTEGRATE-ML-009` reached `accepted` and the integration breakdown safe next action became `INTEGRATE-ML-010`.
- Source ML-010 is `Covered`/`accepted` in the worktree by `Private_group_chat_reliability_test_matrix_full_with_rules-session-ML-010-plan.md`.
- Source contract: exact duplicate active add/re-add is a no-op with no duplicate row, bridge config sync, invite, key mutation, or key downgrade; conflicting duplicate adds still reject before bridge sync; `createGroupWithMembers` dedupes duplicate selected contacts before member insert, config update, system publish payload, and invite fanout; fake-network proof preserves one Charlie row/device, unique durable recipients, and A/B/C delivery.
- Current-main classification: `lib/features/groups/application/add_group_member_use_case.dart` already has strict identical duplicate-member/device no-op behavior from COMPLETE_1/GM-010; `test/features/groups/application/add_group_member_use_case_test.dart` already has an equivalent conflicting duplicate rejection selector but lacks the source ML-010 exact duplicate no-op selector; `lib/features/groups/application/create_group_with_members_use_case.dart` still uses raw `selectedContacts`; source ML-010 selectors are missing from add-member, create-with-members, and fake-network tests.
- COMPLETE_1 overlap: `GM-010` is the primary preservation row. Its accepted proof covers strict identical duplicate re-add/add no-op, conflicting duplicate rejection, exact live `gm010` proof, and adjacent GM-006 through GM-009 preservation. `GM-011`, `GM-012`, and `GM-014` are adjacent stale/race rows and must not be weakened, imported, or relabeled.

## Execution Evidence

- 2026-05-18 09:12 CEST - Imported the missing ML-010 source-owned delta only. `add_group_member_use_case.dart` duplicate no-op behavior was already present and was not changed. Added selected-contact dedupe by peer id in `create_group_with_members_use_case.dart`; added row-named ML-010 exact duplicate no-op, conflicting duplicate rejection, create-with-members dedupe, and fake-network delivery selectors.
- Changed files accepted for ML-010: `lib/features/groups/application/create_group_with_members_use_case.dart`; `test/features/groups/application/add_group_member_use_case_test.dart`; `test/features/groups/application/create_group_with_members_use_case_test.dart`; `test/features/groups/integration/group_membership_smoke_test.dart`; this integration plan; and the controlling integration breakdown.
- Focused ML-010 verification passed: `flutter test --no-pub test/features/groups/application/add_group_member_use_case_test.dart test/features/groups/application/create_group_with_members_use_case_test.dart test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'ML-010'` passed `+4`.
- Preservation verification passed: `flutter test --no-pub test/features/groups/application/add_group_member_use_case_test.dart --plain-name 'ML-010 rejects conflicting duplicate member before sync and preserves original row'` passed `+1`; `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-010'` passed `+1`.
- Hygiene passed: `dart format` over the four touched Dart files completed with `0 changed`; scoped `dart analyze` over add/create/focused test files reported `No issues found!`; `git diff --check` passed.
- No live proof was run or required. Source ML-010 marks 3-party E2E as recommended, not required, and COMPLETE_1/GM-010 remains the preservation-only live proof owner.

## Scope

Allowed ML-010 integration deltas only:

- add selected-contact dedupe by peer id in `createGroupWithMembers`, using the deduped list for contact count, name resolution, membership-limit checks, add loop, invite recipients, and result counts;
- add the source ML-010 exact duplicate active add no-op unit selector;
- add the source ML-010 duplicate selected contacts create-with-members selector;
- add the source ML-010 fake-network duplicate add selector;
- update this integration plan and the controlling integration breakdown.

Already-present and not duplicated: `add_group_member_use_case.dart` duplicate-member production no-op, the existing conflicting duplicate rejection selector `rejects duplicate member before sync and preserves original row`, and COMPLETE_1/GM-010 harness/criteria/device proof.

Out of scope: `ML-011`, stale add/remove ordering, concurrent edits, history, media, notification, key epoch policy, UI, new live proof harness work, source worktree docs, source matrix docs, COMPLETE_1 docs, and broader lifecycle cleanup.

## Required Verification

Focused ML-010 and overlap checks:

```bash
flutter test --no-pub test/features/groups/application/add_group_member_use_case_test.dart test/features/groups/application/create_group_with_members_use_case_test.dart test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'ML-010'
flutter test --no-pub test/features/groups/application/add_group_member_use_case_test.dart --plain-name 'rejects duplicate member before sync and preserves original row'
flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-010'
```

Hygiene:

```bash
dart format lib/features/groups/application/create_group_with_members_use_case.dart test/features/groups/application/add_group_member_use_case_test.dart test/features/groups/application/create_group_with_members_use_case_test.dart test/features/groups/integration/group_membership_smoke_test.dart
dart analyze lib/features/groups/application/add_group_member_use_case.dart lib/features/groups/application/create_group_with_members_use_case.dart test/features/groups/application/add_group_member_use_case_test.dart test/features/groups/application/create_group_with_members_use_case_test.dart test/features/groups/integration/group_membership_smoke_test.dart
git diff --check
```

3-party E2E is recommended in the source row, not required for ML-010 acceptance when host unit, integration, fake-network, and GM-010 preservation evidence are concrete.

## Final Verdict

Accepted for INTEGRATE-ML-010 only.

Structural blockers remaining: none.

Accepted row-owned delta: `createGroupWithMembers` now dedupes selected contacts by peer id before member add/config/publish/invite fanout, and ML-010 row-named host selectors prove exact duplicate active add no-op, conflicting duplicate rejection, duplicate selected-contact dedupe, and fake-network delivery uniqueness.

Accepted differences intentionally left unchanged: COMPLETE_1 `GM-010` harness/criteria/device proof stays preservation-only; source worktree docs, source matrix docs, COMPLETE_1 docs, ML-011+, stale ordering, concurrent edits, history, media, notification, key epoch, UI, and broader lifecycle work remain out of scope.

Next action: resume the pipeline at INTEGRATE-ML-011.
