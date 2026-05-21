# INTEGRATE-OB-007 Integration Contract

Status: accepted

Source of truth: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-OB-007-plan.md`

This is a minimal worktree-to-main integration contract for importing and verifying the historical OB-007 row. It does not recreate or replace the original worktree implementation plan.

## Row Scope

- Verify EventChannel `onError` emits safe failure/recovery diagnostics and attempts EventChannel resubscription.
- Verify EventChannel `onDone` emits safe done/recovery diagnostics and attempts EventChannel resubscription.
- Verify lifecycle resume treats false bridge health as unhealthy, calls `bridge.reinitialize()`, and records readiness reset evidence.
- Preserve adjacent DE-019 EventChannel recovery behavior already present in main.

## Integrated Files

- `test/core/bridge/go_bridge_client_test.dart`
- `test/core/lifecycle/app_lifecycle_recovery_test.dart`
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-breakdown.md`

## Already Present And Preserved

- `lib/core/bridge/go_bridge_client.dart`
- `lib/core/lifecycle/handle_app_resumed.dart`

## Evidence

- PASS: `dart format --set-exit-if-changed test/core/bridge/go_bridge_client_test.dart test/core/lifecycle/app_lifecycle_recovery_test.dart`
- PASS: `flutter test --no-pub test/core/bridge/go_bridge_client_test.dart --plain-name "OB-007"` after serial rerun. An earlier parallel attempt hit the known native-assets startup race.
- PASS: `flutter test --no-pub test/core/lifecycle/app_lifecycle_recovery_test.dart --plain-name "OB-007"`
- PASS: `flutter test --no-pub test/core/bridge/go_bridge_client_test.dart --plain-name "DE-019"`
- PASS: `flutter test --no-pub test/core/lifecycle/app_lifecycle_recovery_test.dart --plain-name "reinitializes bridge when health check fails"`
- PASS: `flutter analyze --no-pub test/core/bridge/go_bridge_client_test.dart test/core/lifecycle/app_lifecycle_recovery_test.dart`
- PASS: `git diff --check`

## Residuals

- `flutter test --no-pub test/core/bridge/go_bridge_client_test.dart --name "DE-009|DE-015|DE-016|DE-018|DE-019|GO-003|GO-004|GO-008|OB-006|OB-007"` is red only on `GO-008 diagnostic flow logs redact JSON-encoded sensitive payload strings`, which also fails when run alone. OB-007 did not touch the GO-008 redaction selector or production redaction code, so this residual is recorded outside the EventChannel health row.

## Closure Verdict

Accepted. The integration imported only the missing OB-007 row-owned bridge and lifecycle proof selectors. Current main already had the production EventChannel recovery and lifecycle health behavior, so no production, native, harness, fixture, script, criteria, simulator, Android, or physical-iOS delta was imported.
