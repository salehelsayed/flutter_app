# INTEGRATE-DE-019 Worktree-To-Main Integration Contract

Status: accepted

## Scope

Import and reconcile only source row `DE-019`: EventChannel error or done states must trigger recovery or unhealthy state, not permanent silent push loss.

This is a standard integration contract, not a regeneration of the historical worktree implementation plan. The source plan and closure evidence remain the historical source of truth.

Out of scope: payload parse failure (`DE-015`), validation diagnostics (`DE-016`), unknown event handling (`DE-018`), dispatcher starvation (`DE-020`), broader health UI or lifecycle health proof (`OB-007`), rapid reinitialize-loop stress (`ST-011`), relay behavior, simulator/device proof, notification, UI, and adjacent row closure.

## Reconciliation

- Current main had partial EventChannel diagnostics only: `GoBridgeClient` emitted `GO_BRIDGE_EVENT_STREAM_ERROR` and `GO_BRIDGE_EVENT_STREAM_DONE`, but left `_initialized=true` and did not resubscribe.
- Imported only the DE-019-owned bridge recovery delta: EventChannel `onError` and `onDone` now route through a guarded recovery handler, mark `_initialized=false`, emit safe diagnostics plus recovery flow evidence, log push diagnostics, and asynchronously call `reinitialize()` to cancel/resubscribe while preserving callbacks.
- Intentional `reinitialize()` and `dispose()` cancellation is suppressed from recursive recovery. ST-011's rapid reinitialize coalescing and OB-007's lifecycle health proof were not imported.
- `go_bridge_client_test.dart` gained only the missing DE-019 EventChannel harness additions and two row-owned selectors for error and done recovery.

## Verification

Passed:

```bash
dart format lib/core/bridge/go_bridge_client.dart test/core/bridge/go_bridge_client_test.dart
flutter test --no-pub test/core/bridge/go_bridge_client_test.dart --plain-name 'DE-019'
flutter test --no-pub test/core/bridge/go_bridge_client_test.dart --name 'DE-009|DE-015|DE-016|DE-018|GO-003|GO-004|GO-008|OB-007'
flutter test --no-pub test/core/bridge/go_bridge_client_test.dart
flutter analyze --no-pub lib/core/bridge/go_bridge_client.dart test/core/bridge/go_bridge_client_test.dart
```

Focused result: DE-019 `+2`; adjacent bridge preservation result: `+9` with no current-main OB-007 selector present; full bridge owner suite result: `+81`; analyzer result: `No issues found`.

Named gate:

```bash
FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups
```

Result: red at `+208 -3` only on preserved non-DE-019 residuals:

- `BB-007 accepted pending invite joins with exact full config and replays accepted epoch`: `Expected: not null / Actual: <null>`
- `BB-012 restart recovery drains replay before ack and stays live`: `Expected: an object with length of <1> / Actual: WhereIterable<GroupMessage>:[]`
- `GM-029 config version monotonicity converges across A/B/C shuffled delivery`: `Expected: MemberRole.writer / Actual: MemberRole.reader`

Additional hygiene:

```bash
./scripts/run_test_gates.sh completeness-check
git diff --check
```

Result: completeness-check remains red on the unrelated `test/shared/fakes/fake_group_pubsub_network_test.dart` classification residual (`732/733`); `git diff --check` passed.

No iOS 26.2 live simulator proof was required or claimed because source `3-Party E2E` is `N/A`.
