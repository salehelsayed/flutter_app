# INTEGRATE-KE-005 Integration Contract - Same-Epoch Different-Key Conflict

Status: accepted

Created: 2026-05-18

## Source Row

- Source plan: `worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-KE-005-plan.md`
- Row: `KE-005`
- Title: `Same-epoch different-key conflict is rejected`
- Source status: `accepted` / `Covered`
- COMPLETE_1 overlap: `GL-015`

## Integration Decision

Current main already contains the production conflict behavior:

- Flutter `GroupKeyUpdateListener` rejects same-generation different-material updates before a native `group:updateKey` promotion.
- Go `UpdateGroupKey` ignores same-or-lower epochs, and COMPLETE_1 `GL-015` already proves epoch-3 K2 cannot replace K1.

This session must not change production key-update semantics. It may only import the missing KE-005 row-owned proof delta:

- KE-005-named listener selector by adapting the existing same-generation conflict test.
- KE-005 fake-network conflict delivery proof and helper.
- KE-005 native Go selector reusing the existing GL-015 proof body.
- `private_same_epoch_key_conflict` criteria, runner, and iOS 26.2 harness flow.
- Integration ledger/doc evidence for this row only.

## Owned Files

- `test/features/groups/application/group_key_update_listener_test.dart`
- `test/features/groups/integration/group_messaging_smoke_test.dart`
- `go-mknoon/node/pubsub_key_rotation_grace_test.go`
- `integration_test/scripts/group_multi_party_device_criteria.dart`
- `test/integration/group_multi_party_device_criteria_test.dart`
- `integration_test/scripts/run_group_multi_party_device_real.dart`
- `integration_test/group_multi_party_device_real_harness.dart`
- this integration contract
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-breakdown.md`

## Scope Guard

Do not import source matrix or source test-inventory rewrites, adjacent KE-006+ key-rotation rows, key-distribution repair, UI, notification, media, relay, or unrelated harness scenarios. Preserve COMPLETE_1 `GL-015`, `GL-014`, KE-003, and KE-004 selectors.

## Required Evidence

- `flutter test --no-pub test/features/groups/application/group_key_update_listener_test.dart --plain-name 'KE-005'`
- `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name 'KE-005'`
- `cd go-mknoon && go test ./node -run 'TestKE005|TestGL015|TestUpdateGroupKey_IgnoresSameEpochDifferentMaterial' -count=1`
- `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'private_same_epoch_key_conflict'`
- runner discovery for `private_same_epoch_key_conflict`
- scoped format/analyzer/gofmt/diff hygiene
- preservation selectors for KE-003, KE-004, GL-014, and GL-015
- named `groups` and `completeness-check` gates, preserving known non-KE-005 residuals
- iOS 26.2 `private_same_epoch_key_conflict` live proof if device fixtures are available

## Final Execution Verdict

Verdict: accepted

KE-005 was integrated as a partial-present row. Current main already had the production same-epoch different-material rejection behavior in the Flutter listener and the native Go key update path, so this session imported only the missing row-owned proof artifacts and diagnostics:

- adapted the existing listener conflict test into a KE-005-named selector and asserted the conflict diagnostic event without duplicating behavior coverage
- added the KE-005 fake-network same-epoch different-key delivery proof and helper
- added a KE-005 Go selector that reuses the existing GL-015 proof body
- added `private_same_epoch_key_conflict` criteria, runner discovery, criteria tests, and iOS 26.2 harness flow

Focused and preservation evidence:

- `flutter test --no-pub test/features/groups/application/group_key_update_listener_test.dart --plain-name 'KE-005'` PASS (`+1`)
- `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name 'KE-005'` PASS (`+1`)
- `cd go-mknoon && go test ./node -run 'TestKE005|TestGL015|TestUpdateGroupKey_IgnoresSameEpochDifferentMaterial' -count=1` PASS (`ok github.com/mknoon/go-mknoon/node 1.681s`)
- `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'private_same_epoch_key_conflict'` PASS (`+2`)
- full criteria regression PASS (`+275`)
- runner discovery listed `private_same_epoch_key_conflict`
- KE-003/KE-004/GL-014/GL-015 adjacent preservation selectors passed
- scoped Dart format and Go format passed; scoped analyzer exited `0` with only pre-existing info-level style findings in `group_key_update_listener_test.dart`; scoped diff hygiene passed

iOS 26.2 live proof passed for `private_same_epoch_key_conflict` with run id `1779109291822`, shared directory `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_private_same_epoch_key_conflict_tY5ME5`, Alice device `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`, Bob device `279B82AE-2BB9-4924-9AAE-581870ED3FA9`, Charlie device `116B4AF6-C1A9-4F36-B929-0A7130B5E83C`, and orchestrator verdict `private_same_epoch_key_conflict verdicts valid for alice, bob, charlie`.

Named gates preserve existing non-KE-005 residuals:

- `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` remains red only on residual `BB-007 accepted pending invite joins with exact full config and replays accepted epoch` (`Expected: not null / Actual: <null>` at `test/features/groups/integration/invite_round_trip_test.dart:679`) and residual `GM-029 config version monotonicity converges across A/B/C shuffled delivery` (`Expected: MemberRole.writer / Actual: MemberRole.reader` at `test/features/groups/integration/group_membership_smoke_test.dart:8144`)
- `./scripts/run_test_gates.sh completeness-check` remains red on unrelated unmatched `test/shared/fakes/fake_group_pubsub_network_test.dart` (`732/733`)

Scope preserved: no production semantics changes, no source matrix/test-inventory import, no COMPLETE_1 doc update, and no KE-006+ row work was imported.
