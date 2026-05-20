# INTEGRATE-DE-009 Bridge Reinitialize Callback Import Contract

Status: accepted

## Historical Source Of Truth

- Source row: `DE-009` Group message events are routed to the group callback after Dart bridge reinitialize.
- Source worktree plan: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-DE-009-plan.md`.
- Source status: accepted/covered with a host Dart bridge callback preservation proof. The source plan classified DE-009 as tests/docs-only; production behavior was already sufficient.

## Integration Scope

Import only the missing row-owned host proof and documentation. Current main already preserves `onGroupMessageReceived` across `GoBridgeClient.reinitialize()` and routes `group_message:received` to that callback, so production code stayed untouched.

In scope:
- `test/core/bridge/go_bridge_client_test.dart`: add a test-local EventChannel listen/cancel mock and `DE-009 group message callback survives reinitialize and receives event once`.
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`, this plan, and the integration breakdown ledger.

Out of scope:
- Production behavior rewrites, DE-010+, native dispatcher panic handling, dispatcher pressure/overflow recovery, receipt protocol generation, group listener/app-level delivery, fake-network tests, Go/native changes, relay behavior, UI, notifications, media, source docs wholesale, COMPLETE_1 docs, simulator/device proof, and 3-party E2E.

## Verification

Focused row check:
- `flutter test --no-pub test/core/bridge/go_bridge_client_test.dart --plain-name 'DE-009 group message callback survives reinitialize and receives event once'` passed (`+1`).

Affected preservation checks:
- `flutter test --no-pub test/core/bridge/go_bridge_client_test.dart` passed (`+78`), covering the DE-009 callback proof plus adjacent GO-003/GO-004/GO-008 diagnostic and raw group-message routing behavior.

Static and hygiene checks:
- `dart format --set-exit-if-changed test/core/bridge/go_bridge_client_test.dart` passed after formatting (`0 changed` on rerun).
- `flutter analyze --no-pub lib/core/bridge/go_bridge_client.dart test/core/bridge/go_bridge_client_test.dart` passed with `No issues found!`.
- Scoped `git diff --check` on `test/core/bridge/go_bridge_client_test.dart` passed before doc closure.

Named gates:
- `./scripts/run_test_gates.sh completeness-check` remains red on unrelated `test/shared/fakes/fake_group_pubsub_network_test.dart` classification (`732/733`).
- `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` remains red only on preserved non-DE-009 residuals `BB-007`, `BB-012`, and `GM-029`.

## Verdict

Accepted. DE-009 is host Dart bridge callback proof only; no iOS 26.2 simulator/live proof was required or run.
