# INTEGRATE-IR-017 Minimal Integration Contract

Status: accepted

## Source Evidence

- Source row: `IR-017` / `Replay after dispatcher overflow restores dropped live events`.
- Source worktree plan: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-IR-017-plan.md`.
- Source closure state: covered/accepted with listener, fake-network, native dispatcher diagnostic, analyzer, host `groups`, completeness, and diff-hygiene evidence.
- Source proof profile: host-only. `3-Party E2E` is `N/A`; no simulator, paired-device, relay, device-lab, OS notification, or `integration_test` proof is required.

This contract is only for importing and verifying the already-closed source row in main. It does not recreate, replace, or rerun the historical source implementation plan.

## Integration Scope

IR-017 imports only the missing row-owned dispatcher-overflow replay proof artifacts:

- Production dispatcher-overflow recovery behavior is already present in main through the accepted DE-012 path and stays unchanged:
  - `lib/features/groups/application/group_message_listener.dart`
  - `lib/main.dart`
  - `test/shared/fakes/group_test_user.dart`
- Native dispatcher proof is already present in main and stays unchanged:
  - `go-mknoon/node/node_test.go`
  - Supporting selector: `TestDE012EventDispatcherOverflowDiagnosticIdentifiesDroppedGroupEventForReplayRecovery`.
- `test/features/groups/application/group_message_listener_test.dart`
  - Add `IR-017 dispatcher overflow diagnostic names replay recovery reason`.
  - Prove a `group:dispatcher_overflow` diagnostic for `lastEvent == group_message:received` invokes replay recovery once and preserves `state`, `lastEvent`, `droppedCount`, `queueDepth`, and `maxQueueSize` in requested/done flow events.
- `test/features/groups/integration/group_resume_recovery_test.dart`
  - Add `IR-017 fake-network dispatcher overflow replay restores and dedupes dropped live event`.
  - Prove Bob misses live delivery while unsubscribed, overflow-triggered replay restores the stored inbox message exactly once, and a second overflow-triggered drain does not duplicate the row.
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
  - Record IR-017 row closure and row-owned test inventory changes.

Out of scope: DE-012 production implementation changes, DE-011 dispatcher pressure below capacity, DE-013 malformed payload validation, IR-016 retention cutoff, IR-018 restart freshness, IR-019 hidden outer-id dedupe, OB-006 overflow observability, notifications, relay architecture, simulator/device proof, 3-party E2E, Android, physical iOS, macOS app-peer roles, and adjacent replay rows.

## Verification Contract

Focused selectors:

```bash
flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name 'IR-017'
flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'IR-017'
(cd go-mknoon && go test ./node -run TestDE012EventDispatcherOverflowDiagnosticIdentifiesDroppedGroupEventForReplayRecovery -count=1)
```

Preservation and hygiene:

```bash
flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name 'DE-012'
flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'DE-012'
flutter test --no-pub test/core/bridge/go_bridge_client_test.dart --plain-name 'group dispatcher overflow push event reaches diagnostics stream and flow logs without invoking group message callback'
(cd go-mknoon && go test ./node -run 'TestDE012EventDispatcherOverflowDiagnosticIdentifiesDroppedGroupEventForReplayRecovery|TestEventDispatcher_EmitsPressureAndOverflowDiagnostics' -count=1)
flutter analyze --no-pub test/features/groups/application/group_message_listener_test.dart test/features/groups/integration/group_resume_recovery_test.dart
dart format --set-exit-if-changed test/features/groups/application/group_message_listener_test.dart test/features/groups/integration/group_resume_recovery_test.dart
git diff --check
FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups
./scripts/run_test_gates.sh completeness-check
```

Expected existing residual classifications to preserve:

- `groups` can remain red only on unrelated preserved residuals `BB-007`, `BB-012`, and `GM-029`.
- `completeness-check` can remain red only on unrelated `test/shared/fakes/fake_group_pubsub_network_test.dart` classification.

## Verification Results

Focused selectors passed:

```bash
flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name 'IR-017'
flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'IR-017'
(cd go-mknoon && go test ./node -run TestDE012EventDispatcherOverflowDiagnosticIdentifiesDroppedGroupEventForReplayRecovery -count=1)
```

- Results: listener IR-017 `+1`, fake-network IR-017 `+1`, and native dispatcher diagnostic `ok github.com/mknoon/go-mknoon/node`.
- One initial parallel Flutter run was discarded because it hit the known native-asset `lipo` race while another Flutter command was active; the listener selector passed on sequential rerun.

Preservation and hygiene passed:

```bash
flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name 'DE-012'
flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'DE-012'
flutter test --no-pub test/core/bridge/go_bridge_client_test.dart --plain-name 'group dispatcher overflow push event reaches diagnostics stream and flow logs without invoking group message callback'
(cd go-mknoon && go test ./node -run 'TestDE012EventDispatcherOverflowDiagnosticIdentifiesDroppedGroupEventForReplayRecovery|TestEventDispatcher_EmitsPressureAndOverflowDiagnostics' -count=1)
flutter analyze --no-pub test/features/groups/application/group_message_listener_test.dart test/features/groups/integration/group_resume_recovery_test.dart
dart format --set-exit-if-changed test/features/groups/application/group_message_listener_test.dart test/features/groups/integration/group_resume_recovery_test.dart
git diff --check
```

- Results: listener DE-012 `+1`, fake-network DE-012 `+1`, bridge overflow routing `+1`, native overflow preservation `ok github.com/mknoon/go-mknoon/node`, scoped analyzer `No issues found!`, Dart format `0 changed`, and diff hygiene passed.

Classified residual gates:

```bash
FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups
# +218 -3, red only on preserved non-IR-017 residuals BB-007, BB-012, and GM-029:
# BB-007 accepted pending invite joins with exact full config and replays accepted epoch: Expected not null, Actual null.
# BB-012 restart recovery drains replay before ack and stays live: Expected an object with length of 1, Actual empty WhereIterable<GroupMessage>.
# GM-029 config version monotonicity converges across A/B/C shuffled delivery: Expected MemberRole.writer, Actual MemberRole.reader.

./scripts/run_test_gates.sh completeness-check
# 732/733, red only on unrelated test/shared/fakes/fake_group_pubsub_network_test.dart classification.
```

## Closure Verdict

`INTEGRATE-IR-017` is accepted. Main now has row-owned listener and fake-network proof that dispatcher-overflow diagnostics for dropped group message events trigger replay recovery, restore the dropped message exactly once, preserve overflow recovery reason details, and remain deduped across repeat overflow-triggered drains.
