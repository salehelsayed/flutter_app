# INTEGRATE-ST-005 Plan - Standard Integration Contract

Status: accepted

## Scope

Import and verify historical row `ST-005`: "High-throughput event storm does not lose messages without recovery."

This was standard worktree-to-main integration, not gap-closure. The historical source plan and closure evidence stayed the source of truth; no original implementation plan was regenerated.

## Source Evidence

- Historical source plan: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-ST-005-plan.md`.
- Source row-owned proof selectors:
  - `cd go-mknoon && go test ./node -run TestST005EventDispatcherHighThroughputStormPreservesGroupMessagesAndCoalescesStatus -count=1`
  - `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name "ST-005 high-throughput listener storm persists all message events without recovery"`
  - `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name "ST-005 fake-network high-throughput message storm fanout is exact once without recovery"`
- Source 3-party E2E: `N/A`.

## Imported Delta

- Imported the missing row-owned native dispatcher storm proof in `go-mknoon/node/node_test.go`.
- Imported the missing row-owned direct listener storm proof in `group_message_listener_test.dart`.
- Imported the missing row-owned fake-network high-throughput fanout proof in `group_messaging_smoke_test.dart`.
- Current-main dispatcher pressure, overflow recovery, media-progress coalescing, large-payload, and adjacent fake-network ordering behavior was preserved and not rewritten.

## Verification

Passed:

- `cd go-mknoon && go test ./node -run TestST005EventDispatcherHighThroughputStormPreservesGroupMessagesAndCoalescesStatus -count=1`
- `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name "ST-005"`
- `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name "ST-005"`
- `cd go-mknoon && go test ./node -run 'TestDE011EventDispatcherPreservesGroupMessagesBelowCapacityUnderPressure|TestDE012EventDispatcherOverflowDiagnosticIdentifiesDroppedGroupEventForReplayRecovery|TestDE020EventDispatcherLargeGroupPayloadDoesNotStarveLaterMessage|TestPL008EventDispatcherCoalescesMediaProgressWithoutDroppingGroupMessages|TestEventDispatcher_EmitsPressureAndOverflowDiagnostics' -count=1`
- `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --name 'DE-012 dispatcher overflow triggers one replay recovery and coalesces duplicates|IR-017 dispatcher overflow diagnostic names replay recovery reason'`
- `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --name 'PL-008 media upload progress storm does not drop fake-network group messages|ST-003 fake-network randomized key epoch monotonicity keeps active epoch|DE-002 rapid 100 same-sender messages stay ordered for both recipients'`
- `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --name 'DE-012 dispatcher overflow diagnostic drains inbox replay for a dropped group message|DE-020 large payload does not starve later fake-network delivery'`
- `flutter analyze --no-pub test/features/groups/application/group_message_listener_test.dart test/features/groups/integration/group_messaging_smoke_test.dart`
- `gofmt -l go-mknoon/node/node_test.go`
- `git diff --check`

No iOS simulator/live proof was required because the source row is host/native/fake-network only.

## Verdict

`accepted`

ST-005 is imported and verified. The integration stayed limited to row-owned high-throughput storm proof selectors and documentation ledger updates. Existing blocked rows remain unchanged.
