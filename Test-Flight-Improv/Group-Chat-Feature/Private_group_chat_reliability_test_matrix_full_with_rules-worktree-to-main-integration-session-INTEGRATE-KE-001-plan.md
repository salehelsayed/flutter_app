# INTEGRATE-KE-001 Integration Contract

Status: accepted

## Scope

Import and verify only source row `KE-001` into current main: initial private group creation and supported invite join must keep the first group key epoch exactly `1` on every joined peer, and the reusable `private_abc_create` proof must reject any converged initial epoch other than `1`.

This is standard integration mode. The historical source worktree remains the source of truth; this plan is only the minimal import/reconcile/verify contract for current main. Do not update or recreate the original worktree implementation plan.

## Source Evidence

- Source worktree: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline`
- Source plan: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-KE-001-plan.md`
- Historical accepted source proof: source focused KE-001 create selector passed `+1`, source focused KE-001 membership selector passed `+1`, source focused `private proof topic and key epoch divergence` selector passed `+1`, source focused `private A/B/C create` selectors passed `+2`, source groups gate passed, and source completeness-check passed.
- Historical live proof policy: KE-001 reuses the iOS 26.2 `private_abc_create` proof established by the prerequisite/ML-001 path rather than adding a duplicate device scenario.

## Import Contract

- Preserve current production create/join/key behavior; no KE-001 production code import was needed.
- Preserve current `private_abc_create` criteria enforcement in `integration_test/scripts/group_multi_party_device_criteria.dart`, which already rejects role verdicts and sent/received tuples whose initial key epoch is not exactly `1`.
- Import the missing row-owned create-use-case unit assertion proving generation `1` is persisted and generations `0` and `2` are absent.
- Import the missing row-owned negative criteria assertion proving a topic mismatch and a converged epoch `2` proof are rejected.
- Preserve existing ML-001/GM-001 private A/B/C smoke and reusable live-harness coverage as shared proof; do not import adjacent stale-key, downgrade, conflict, rotation, removal, re-add, UI, notification, media, or broader security rows.

## Device Reality

No fresh simulator proof was required or run for KE-001. The row cites the already-recorded `private_abc_create` iOS 26.2 proof from `INTEGRATE-ML-001`:

- Scenario: `private_abc_create`
- Run id: `1778990166558`
- Verdict directory: `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_private_abc_create_kxWDE7`
- Final proof line: `private_abc_create proof passed: private_abc_create verdicts valid for alice, bob, charlie`
- Alice, Bob, and Charlie verdicts all reported key epoch `1`, topic `/mknoon/group/ae4094ab-ce8f-4291-b963-96ff99d405ae`, matching active member peer ids, matching config hash `ba620583bf0b75af45111aa169208079cbd3c273307082e37922477031f95681`, and row-specific `ml001CreateInviteProof` fields.

## Verification Log

- PASS: `flutter test --no-pub test/features/groups/application/create_group_use_case_test.dart --plain-name 'KE-001'` (`+1`).
- PASS: `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'KE-001'` (`+1`).
- PASS: `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'private proof topic and key epoch divergence'` (`+1`) after reconciling current main's stricter error text (`keyEpoch must be exactly 1 for KE-001`).
- PASS: `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'private A/B/C create'` (`+2`).
- PASS: affected preservation selector `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name 'GM-001 creates private A/B/C group with shared epoch and exact fanout tuple'` (`+1`).
- PASS: affected preservation selector `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'ML-001'` (`+1`).
- PASS: affected preservation selector `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'accepts valid GM-001 A/B/C receiver persistence verdicts'` (`+1`).
- PASS: full `test/integration/group_multi_party_device_criteria_test.dart` (`+271`).
- PASS: scoped analyzer `dart analyze integration_test/scripts/group_multi_party_device_criteria.dart test/integration/group_multi_party_device_criteria_test.dart test/features/groups/application/create_group_use_case_test.dart test/features/groups/integration/group_messaging_smoke_test.dart test/features/groups/integration/group_membership_smoke_test.dart` (`No issues found!`). The attempted `dart analyze --no-pub ...` invocation failed before analysis because this SDK does not support that flag.
- PASS: `dart format --set-exit-if-changed` on the five scoped KE-001 Dart files (`0 changed`).
- PASS: scoped `git diff --check` on `test/features/groups/application/create_group_use_case_test.dart` and `test/integration/group_multi_party_device_criteria_test.dart`.
- GATE RESIDUAL: `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` remains red only on residual `BB-007 accepted pending invite joins with exact full config and replays accepted epoch` (`Expected: not null / Actual: <null>` at `test/features/groups/integration/invite_round_trip_test.dart:679`) and residual `GM-029 config version monotonicity converges across A/B/C shuffled delivery` (`Expected: MemberRole.writer / Actual: MemberRole.reader` at `test/features/groups/integration/group_membership_smoke_test.dart:8144` in the diagnostic JSON run).
- GATE RESIDUAL: `./scripts/run_test_gates.sh completeness-check` remains red on unrelated `test/shared/fakes/fake_group_pubsub_network_test.dart` classification (`732/733`).

## Final Integration Verdict

`accepted` for `INTEGRATE-KE-001`.

The row-owned KE-001 unit and negative criteria assertions are present in main, while the exact epoch-1 validator and private A/B/C smoke/live proof surfaces were already present from earlier imported rows. Focused selectors, affected preservation selectors, full criteria regression, scoped analyzer/format/diff hygiene, and historical iOS 26.2 proof citation all support closure. The remaining red gates are classified as non-KE-001 residuals: prior `BB-007`, known `GM-029`, and the existing completeness classification gap for `fake_group_pubsub_network_test.dart`.
