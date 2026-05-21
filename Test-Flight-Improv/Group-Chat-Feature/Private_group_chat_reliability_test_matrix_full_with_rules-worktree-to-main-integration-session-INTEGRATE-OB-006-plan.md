# INTEGRATE-OB-006 Integration Contract

Status: accepted

Source of truth: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-OB-006-plan.md`

This is a minimal worktree-to-main integration contract for importing and verifying the historical OB-006 row. It does not recreate or replace the original worktree implementation plan.

## Row Scope

- Verify dispatcher pressure and overflow diagnostics reach Flutter diagnostics, flow logs, and push diagnostics with bounded queue metadata.
- Verify dispatcher overflow diagnostics trigger replay recovery without normal message callback delivery.
- Verify overflow recovery request/done flow events preserve state, last event, dropped count, queue depth, and max queue size.
- Preserve adjacent DE-012 and IR-017 dispatcher overflow behavior already present in main.

## Integrated Files

- `test/core/bridge/go_bridge_client_test.dart`
- `test/features/groups/integration/group_resume_recovery_test.dart`
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-breakdown.md`

## Already Present And Preserved

- `lib/core/bridge/go_bridge_client.dart`
- `lib/features/groups/application/group_message_listener.dart`
- `lib/main.dart`
- `go-mknoon/node/event_dispatcher.go`
- `test/shared/fakes/group_test_user.dart`

## Evidence

- PASS: `dart format --set-exit-if-changed test/core/bridge/go_bridge_client_test.dart test/features/groups/integration/group_resume_recovery_test.dart`
- PASS: `flutter test --no-pub test/core/bridge/go_bridge_client_test.dart --plain-name "OB-006"`
- PASS: `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name "OB-006"`
- PASS: `flutter test --no-pub test/core/bridge/go_bridge_client_test.dart --plain-name "group dispatcher overflow push event reaches diagnostics stream and flow logs without invoking group message callback"`
- PASS: `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name "DE-012 dispatcher overflow triggers one replay recovery and coalesces duplicates"`
- PASS: `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name "DE-012 dispatcher overflow diagnostic drains inbox replay for a dropped group message"`
- PASS: `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name "IR-017 dispatcher overflow diagnostic names replay recovery reason"`
- PASS: `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name "IR-017 fake-network dispatcher overflow replay restores and dedupes dropped live event"`
- PASS: `flutter analyze --no-pub test/core/bridge/go_bridge_client_test.dart test/features/groups/integration/group_resume_recovery_test.dart`
- PASS: `git diff --check`

## Closure Verdict

Accepted. The integration imported only the missing OB-006 row-owned bridge and fake-network proof selectors. Current main already had the production dispatcher diagnostic and recovery behavior, so no production, native, harness, fixture, script, criteria, simulator, Android, or physical-iOS delta was imported.
