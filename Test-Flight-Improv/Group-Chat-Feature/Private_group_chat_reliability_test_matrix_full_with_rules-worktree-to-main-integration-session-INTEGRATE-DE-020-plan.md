# INTEGRATE-DE-020 Worktree-To-Main Integration Contract

Status: accepted

## Scope

Import and reconcile only source row `DE-020`: a valid large group payload within the product text limit must not starve, block, or drop the immediately following normal group message.

This is a standard integration contract, not a regeneration of the historical worktree implementation plan. The source plan and closure evidence remain the historical source of truth.

Out of scope: dispatcher overflow replay recovery (`DE-012`), malformed/validation diagnostics (`DE-013` through `DE-016`), EventChannel recovery (`DE-019`), queue-storm pressure (`ST-005`), fake-network route-mode/delivery-record helper changes from other rows, production dispatcher or bridge changes, relay behavior, simulator/device proof, notification, UI, and adjacent row closure.

## Reconciliation

- Current main already had the production dispatcher FIFO/overflow behavior and bridge group-message routing needed for DE-020, but lacked the exact row-owned proofs.
- Imported only the DE-020-owned test deltas:
  - `go-mknoon/node/node_test.go` gained `TestDE020EventDispatcherLargeGroupPayloadDoesNotStarveLaterMessage`, proving a 10,000-character `group_message:received` payload followed by a normal message drains in FIFO order with delivered `2`, coalesced `0`, dropped `0`, and queue depth `0`.
  - `test/core/bridge/go_bridge_client_test.dart` gained `DE-020 large group payload does not starve later group callback`, proving a max-length text payload and a normal follow-up both reach `onGroupMessageReceived` once and in order.
  - `test/features/groups/integration/group_resume_recovery_test.dart` gained `DE-020 large payload does not starve later fake-network delivery`, proving max-length and normal fake-network sends persist exactly once, in order, with two publishes and two live deliveries.
- The source worktree's `FakeGroupPubSubNetwork.deliveryRecords` helper was not imported because it belongs to unrelated mixed fixture work. The fake-network assertion was reconciled to current main's existing `publishCallCount`, `totalDeliveries`, and persisted Bob message rows.

## Verification

Passed:

```bash
gofmt -w go-mknoon/node/node_test.go
dart format test/core/bridge/go_bridge_client_test.dart test/features/groups/integration/group_resume_recovery_test.dart
cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'TestDE020EventDispatcherLargeGroupPayloadDoesNotStarveLaterMessage' -count=1
flutter test --no-pub test/core/bridge/go_bridge_client_test.dart --plain-name 'DE-020'
flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'DE-020'
cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'TestDE011EventDispatcherPreservesGroupMessagesBelowCapacityUnderPressure|TestDE012EventDispatcherOverflowDiagnosticIdentifiesDroppedGroupEventForReplayRecovery|TestEventDispatcher_EmitsPressureAndOverflowDiagnostics' -count=1
flutter test --no-pub test/core/bridge/go_bridge_client_test.dart --name 'DE-019 EventChannel|group dispatcher overflow push event reaches diagnostics stream and flow logs without invoking group message callback'
flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name 'DE-012 dispatcher overflow triggers one replay recovery and coalesces duplicates'
flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'DE-012 dispatcher overflow diagnostic drains inbox replay for a dropped group message'
flutter analyze --no-pub test/core/bridge/go_bridge_client_test.dart test/features/groups/integration/group_resume_recovery_test.dart
git diff --check
```

Focused results: native DE-020 `ok github.com/mknoon/go-mknoon/node 0.543s`; bridge DE-020 `+1`; fake-network DE-020 `+1`. Preservation results: native DE-011/DE-012/dispatcher diagnostics `ok github.com/mknoon/go-mknoon/node 0.782s`; bridge DE-019/overflow `+3`; listener DE-012 `+1`; fake-network DE-012 `+1`; analyzer result `No issues found`.

Named gate:

```bash
FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups
```

Result: red at `+209 -3` only on preserved non-DE-020 residuals:

- `BB-007 accepted pending invite joins with exact full config and replays accepted epoch`: `Expected: not null / Actual: <null>`
- `BB-012 restart recovery drains replay before ack and stays live`: `Expected: an object with length of <1> / Actual: WhereIterable<GroupMessage>:[]`
- `GM-029 config version monotonicity converges across A/B/C shuffled delivery`: `Expected: MemberRole.writer / Actual: MemberRole.reader`

No iOS 26.2 live simulator proof was required or claimed because source `3-Party E2E` is only `Recommended`, not required, and current main has no DE-020 live scenario.

Additional hygiene:

```bash
./scripts/run_test_gates.sh completeness-check
```

Result: completeness-check remains red on the unrelated `test/shared/fakes/fake_group_pubsub_network_test.dart` classification residual (`732/733`); `git diff --check` passed.
