# INTEGRATE-DE-012 Dispatcher Overflow Replay Recovery Import Contract

Status: accepted

## Historical Source Of Truth

- Source row: `DE-012` Dispatcher overflow triggers replay recovery for dropped group events.
- Source worktree plan: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-DE-012-plan.md`.
- Source status: accepted/covered with Go dispatcher, Flutter listener, runtime wiring, and fake-network replay proof evidence.

## Integration Scope

Imported only the missing row-owned overflow recovery path and proof artifacts. Current main already emitted native `group:dispatcher_overflow` diagnostics and forwarded them through the bridge, but did not consume them in `GroupMessageListener` to trigger group offline inbox replay.

In scope:
- `lib/features/groups/application/group_message_listener.dart`: add `RecoverGroupDispatcherOverflow`, filter `group:dispatcher_overflow` to `lastEvent == group_message:received`, coalesce in-flight recovery, and emit bounded flow evidence.
- `lib/main.dart`: wire overflow recovery to `drainGroupOfflineInbox` using the live listener replay path and current group repositories.
- `test/shared/fakes/group_test_user.dart`: expose diagnostic stream and overflow recovery callback plumbing for row-owned fake-network tests.
- `go-mknoon/node/node_test.go`: add `TestDE012EventDispatcherOverflowDiagnosticIdentifiesDroppedGroupEventForReplayRecovery`.
- `test/features/groups/application/group_message_listener_test.dart`: add the DE-012 listener coalescing proof.
- `test/features/groups/integration/group_resume_recovery_test.dart`: add the DE-012 fake-network inbox replay proof.
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`, this plan, and the integration breakdown ledger.

Out of scope:
- DE-013 schema validation, DE-014 decryption repair, DE-015 payload parse continuity, DE-019 EventChannel recovery, DE-020 starvation, source docs wholesale, COMPLETE_1 docs, criteria/live-harness changes, simulator/device proof, 3-party E2E, UI, notification, media, relay durability, receipt protocol, and unrelated fake-network helper expansion.

## Verification

Focused row checks:
- `(cd go-mknoon && go test ./node -run 'TestDE012|TestEventDispatcher_EmitsPressureAndOverflowDiagnostics|TestDE011EventDispatcherPreservesGroupMessagesBelowCapacityUnderPressure' -count=1)` passed (`ok github.com/mknoon/go-mknoon/node 0.857s`).
- `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name 'DE-012'` passed (`+1`).
- `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'DE-012'` passed (`+1`).

Affected preservation checks:
- `flutter test --no-pub test/core/bridge/go_bridge_client_test.dart --plain-name 'group dispatcher overflow push event reaches diagnostics stream and flow logs without invoking group message callback'` passed (`+1`).

Static and hygiene checks:
- `gofmt -w go-mknoon/node/node_test.go` completed.
- `dart format lib/features/groups/application/group_message_listener.dart lib/main.dart test/shared/fakes/group_test_user.dart test/features/groups/application/group_message_listener_test.dart test/features/groups/integration/group_resume_recovery_test.dart` completed (`0 changed` after patch formatting).
- `flutter analyze --no-pub lib/features/groups/application/group_message_listener.dart lib/main.dart test/shared/fakes/group_test_user.dart test/features/groups/application/group_message_listener_test.dart test/features/groups/integration/group_resume_recovery_test.dart` passed (`No issues found!`).
- Scoped `git diff --check` passed before ledger closure.

Named gates:
- `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` remains red at `+203 -3` only on preserved non-DE-012 residuals `BB-007`, `BB-012`, and `GM-029`.
- `./scripts/run_test_gates.sh completeness-check` remains red on unrelated `test/shared/fakes/fake_group_pubsub_network_test.dart` classification (`732/733`).

## Verdict

Accepted. DE-012 required host Go, Flutter listener, bridge preservation, and fake-network replay proof only; no iOS 26.2 simulator/live proof was required or run.
