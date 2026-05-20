# INTEGRATE-KE-022 Key Update Diagnostics Import Contract

Status: accepted

## Historical Source Of Truth

- Source row: `KE-022 | Key update errors are visible in diagnostics and recovery UI`.
- Source worktree plan: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-KE-022-plan.md` in `worktrees/full-rules-pipeline`.
- Source closure status: `accepted` / `covered`.
- Integration mode: standard worktree-to-main import/reconcile/verify. This contract does not recreate the source implementation plan and does not expand the row beyond KE-022.

## Integration Scope

Import only the missing KE-022 row-owned delta into main:

- Add the explicit key-update failure repair reason.
- Wire `GroupKeyUpdateListener` to request key repair after failed native `group:updateKey` without saving the failed epoch.
- Wire production listener construction to `emitGroupKeyRepairRequest`.
- Add row-named direct listener, fake-network diagnostic/placeholder, and conversation UI degraded-state proofs.
- Update the worktree-to-main ledger and test inventory after verification.

Do not import unrelated source-worktree diagnostic fake-network helper infrastructure, source matrix/session docs, Go/native changes, criteria runners, live harnesses, or adjacent recovery rows.

## Verification Contract

- Focused KE-022 selectors in listener, fake-network smoke, and conversation UI tests.
- Affected preservation selectors for bridge failure behavior, diagnostic repair, UI placeholder safety, and GO-004 bridge helper coverage.
- Scoped format/analyze and `git diff --check`.
- `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups`, preserving known non-KE-022 residual failures.
- iOS 26.2 live proof: N/A for this row.

## Execution Evidence

Imported row-owned production deltas in `group_pending_key_repair_service.dart`, `group_key_update_listener.dart`, and `main.dart`; imported row-owned listener, fake-network, and UI tests in `group_key_update_listener_test.dart`, `group_messaging_smoke_test.dart`, and `group_conversation_screen_test.dart`; updated `test-inventory.md` and this integration ledger. The fake-network proof uses current main's existing direct diagnostic stream hook and intentionally does not import unrelated source-worktree fake-network diagnostic helper infrastructure.

Passed verification:

- `flutter test --no-pub test/features/groups/application/group_key_update_listener_test.dart test/features/groups/integration/group_messaging_smoke_test.dart test/features/groups/presentation/group_conversation_screen_test.dart --plain-name KE-022` (`+3`)
- `flutter analyze --no-pub lib/features/groups/application/group_pending_key_repair_service.dart lib/features/groups/application/group_key_update_listener.dart lib/main.dart test/features/groups/application/group_key_update_listener_test.dart test/features/groups/integration/group_messaging_smoke_test.dart test/features/groups/presentation/group_conversation_screen_test.dart` (`No issues found!`)
- `dart format` on the six touched Dart files (`0 changed`)
- `flutter test --no-pub test/features/groups/application/group_key_update_listener_test.dart --name 'KE-022|BB-002 group:updateKey NOT_INITIALIZED|BB-013 group:updateKey timeout|PREREQ-FUTURE-EPOCH-KEY-REPAIR|KE-019'` (`+6`)
- `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --name 'GO-004|KE-017'` (`+3`)
- `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --name 'PREREQ-FUTURE-EPOCH-KEY-REPAIR|GEK002'` (`+2`)
- `flutter test --no-pub test/features/groups/presentation/group_conversation_screen_test.dart --plain-name 'PREREQ-FUTURE-EPOCH-KEY-REPAIR renders pending and finalized repair placeholders safely'` (`+1`)
- `flutter test --no-pub test/core/bridge/bridge_group_helpers_test.dart --name 'group:updateKey preserves explicit failure exception|BB-013 group:updateKey timeout rethrows TimeoutException'` (`+2`)
- `flutter test --no-pub test/core/bridge/go_bridge_client_test.dart --plain-name 'GO-004 group decryption failure diagnostic reaches repair stream without message callback'` (`+1`)
- `git diff --check` passed.

Named gate evidence: `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` remains red at `+195 -3` only on preserved non-KE-022 residuals `BB-007 accepted pending invite joins with exact full config and replays accepted epoch` (`Expected: not null / Actual: <null>` at `invite_round_trip_test.dart:679`), `BB-012 restart recovery drains replay before ack and stays live` (`Expected: an object with length of <1> / Actual: WhereIterable<GroupMessage>:[]` at `group_startup_rejoin_smoke_test.dart:842`), and `GM-029 config version monotonicity converges across A/B/C shuffled delivery` (`Expected: MemberRole.writer / Actual: MemberRole.reader` at `group_membership_smoke_test.dart:8144`). `completeness-check` was not rerun because KE-022 added tests to existing files and did not change gate classification; the existing fake-network test classification residual remains preserved from prior rows.

## Final Verdict

Accepted. KE-022 is integrated with row-owned code, tests, diagnostics, UI proof, and inventory/ledger evidence. No iOS 26.2 live proof was required because the row is host-only.
