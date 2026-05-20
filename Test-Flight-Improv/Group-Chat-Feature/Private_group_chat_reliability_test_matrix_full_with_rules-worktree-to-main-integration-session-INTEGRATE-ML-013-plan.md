Status: accepted
Acceptance Status: accepted
Mode: standard worktree-to-main integration, not gap-closure
Source row: `ML-013 | Non-admin or removed peer cannot create accepted membership changes`
Integration row: `INTEGRATE-ML-013`

# INTEGRATE-ML-013 Worktree-to-Main Integration Contract

## Planning Evidence

- 2026-05-18 - Started after `INTEGRATE-ML-012` reached `blocked_external_fixture` and the integration breakdown safe next action became `INTEGRATE-ML-013`.
- Source ML-013 is `Covered`/`accepted` in `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-ML-013-plan.md`.
- Source source-of-truth commits: `5320044f ML-013: plan membership authority rejection` and `d5a8c889 ML-013: close membership authority rejection`.
- Source changed-file inventory from the historical row plan/evidence:
  - `test/features/groups/application/add_group_member_use_case_test.dart`
  - `test/features/groups/application/remove_group_member_use_case_test.dart`
  - `test/features/groups/application/update_group_member_role_use_case_test.dart`
  - `test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart`
  - `test/features/groups/application/send_group_invite_use_case_test.dart`
  - `test/features/groups/application/group_message_listener_test.dart`
  - `test/features/groups/application/group_key_update_listener_test.dart`
  - `test/features/groups/integration/group_membership_smoke_test.dart`
  - source docs: source ML-013 plan, source breakdown, source matrix, and source `test-inventory.md`
- Source production delta: none. The source closure explicitly recorded `git diff -- lib | wc -l` as `0` and accepted ML-013 as proof-only against existing production behavior.
- Current-main classification before this row: production behavior was already present through app-side permission checks and receive-side authorization gates, but row-owned ML-013-labeled proof was missing or partial. The row-owned meaningful integration delta was therefore tests-only.
- COMPLETE_1/main preservation considered: delegated writer permission overrides, unauthorized mutation rejection, removed/non-member receive-side rejection, direct key-update authorization, and adjacent membership smoke behavior. No ML-014+ or broader lifecycle work was used as source material.

## Execution Evidence

- Imported row-owned ML-013 test proof only:
  - `test/features/groups/application/add_group_member_use_case_test.dart`: `ML-013 bare writer cannot add member or sync config`
  - `test/features/groups/application/remove_group_member_use_case_test.dart`: `ML-013 bare writer cannot remove active member or sync config`
  - `test/features/groups/application/update_group_member_role_use_case_test.dart`: `ML-013 bare writer cannot update member role or sync config`
  - `test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart`: `ML-013 bare writer and removed peer cannot rotate keys`
  - `test/features/groups/application/send_group_invite_use_case_test.dart`: `ML-013 bare writer cannot sign encrypt or deliver a group invite`
  - `test/features/groups/application/group_key_update_listener_test.dart`: row-labeled bare-writer direct key rejection and removed-peer direct key rejection
  - `test/features/groups/application/group_message_listener_test.dart`: row-labeled unauthorized writer mutation rejection and removed-peer injected membership/config rejection
  - `test/features/groups/integration/group_membership_smoke_test.dart`: row-labeled non-admin/non-member raw membership event rejection
- No production, Go, bridge, runner, criteria, device harness, source worktree docs, COMPLETE_1 docs, source matrix docs, or source `test-inventory.md` files were imported for this row.
- Existing production behavior stayed source-equivalent enough for ML-013: unauthorized app entry points fail before bridge config/key mutation, unauthorized receive-side membership/config payloads do not mutate local state or bridge validators, and unauthorized direct key updates do not save a new key or update bridge key state.

## Verification

Passed formatting:

```bash
dart format test/features/groups/application/add_group_member_use_case_test.dart test/features/groups/application/remove_group_member_use_case_test.dart test/features/groups/application/update_group_member_role_use_case_test.dart test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart test/features/groups/application/send_group_invite_use_case_test.dart test/features/groups/application/group_message_listener_test.dart test/features/groups/application/group_key_update_listener_test.dart test/features/groups/integration/group_membership_smoke_test.dart
```

Result: pass, `Formatted 8 files (0 changed)`.

Passed focused ML-013 verification:

```bash
flutter test --no-pub test/features/groups/application/add_group_member_use_case_test.dart test/features/groups/application/remove_group_member_use_case_test.dart test/features/groups/application/update_group_member_role_use_case_test.dart test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart test/features/groups/application/send_group_invite_use_case_test.dart test/features/groups/application/group_message_listener_test.dart test/features/groups/application/group_key_update_listener_test.dart test/features/groups/integration/group_membership_smoke_test.dart --plain-name ML-013
```

Result: pass, `+10`.

Passed affected delegated-permission and unauthorized-preservation selectors:

```bash
flutter test --no-pub test/features/groups/application/add_group_member_use_case_test.dart test/features/groups/application/remove_group_member_use_case_test.dart test/features/groups/application/update_group_member_role_use_case_test.dart test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart test/features/groups/application/send_group_invite_use_case_test.dart test/features/groups/application/group_key_update_listener_test.dart test/features/groups/application/group_message_listener_test.dart test/features/groups/integration/group_membership_smoke_test.dart --name "allows writer with invite permission override|allows writer with remove permission override|allows writer with manage-roles permission override|RP004 rotate-permission sender direct key update is accepted|PREREQ-INVITER-FRESHNESS|unauthorized writer mutation system events|non-admin and non-member raw membership events"
```

Result: pass, `+7`.

Passed full non-smoke touched application suites:

```bash
flutter test --no-pub test/features/groups/application/add_group_member_use_case_test.dart test/features/groups/application/remove_group_member_use_case_test.dart test/features/groups/application/update_group_member_role_use_case_test.dart test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart test/features/groups/application/send_group_invite_use_case_test.dart test/features/groups/application/group_message_listener_test.dart test/features/groups/application/group_key_update_listener_test.dart
```

Result: pass, `+243`.

Additional smoke-file evidence:

```bash
flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name "ML-008 repeated add-remove-re-add cycles stay convergent across restarts"
flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name "GM-029 config version monotonicity converges across A/B/C shuffled delivery"
flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart
```

Results: isolated ML-008 selector passed (`+1`); isolated GM-029 selector failed with `Expected: MemberRole.writer / Actual: MemberRole.reader` at `group_membership_smoke_test.dart:7683`; full smoke file failed with the same GM-029 role-convergence failure (`+61 -1`). This is recorded as a non-ML-013 residual smoke failure because ML-013's smoke delta is limited to the row-owned raw membership rejection selector, and the focused ML-013 selector passed.

Analyzer and diff hygiene:

```bash
flutter analyze --no-pub test/features/groups/application/add_group_member_use_case_test.dart test/features/groups/application/remove_group_member_use_case_test.dart test/features/groups/application/update_group_member_role_use_case_test.dart test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart test/features/groups/application/send_group_invite_use_case_test.dart test/features/groups/application/group_message_listener_test.dart test/features/groups/application/group_key_update_listener_test.dart test/features/groups/integration/group_membership_smoke_test.dart
git diff --check
```

Results: scoped analyzer exited `1` only for pre-existing info-level style findings in touched test files (`no_leading_underscores_for_local_identifiers` and `use_null_aware_elements`); `git diff --check` passed before and after doc closure. No Go files were touched for this row, so `gofmt` was not applicable.

## Scope

Allowed integration action was limited to importing or verifying ML-013 row-owned test proof for unauthorized membership/config/key mutation rejection.

Out of scope: production rewrites, Go bridge authority validation, device/relay proof, source docs, COMPLETE_1 docs, source matrix docs, ML-014+, membership ordering fixes, GM-029 repair, history, notification, media, UI, broader lifecycle churn, and original worktree plan regeneration.

## Final Verdict

`INTEGRATE-ML-013` is `accepted`.

The meaningful row-owned delta was tests-only and is now present in main. Focused ML-013 selectors, affected delegated-permission/unauthorized-preservation selectors, and the full non-smoke touched application suites passed. No live proof was required or claimed because the source row marks 3-Party E2E as recommended only.

Residual non-row evidence to preserve: `GM-029 config version monotonicity converges across A/B/C shuffled delivery` currently fails in `group_membership_smoke_test.dart` with Bob/Charlie role convergence seeing `reader` instead of expected `writer`. That failure is outside ML-013's row-owned import and should be handled by a future GM-029/ordering-focused pass, not by broadening ML-013.
