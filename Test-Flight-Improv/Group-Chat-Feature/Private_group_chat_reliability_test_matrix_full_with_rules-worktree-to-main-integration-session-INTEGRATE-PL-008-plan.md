# INTEGRATE-PL-008 Worktree-to-Main Integration Contract

Status: accepted

Source of truth:
- Source worktree: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline`
- Historical source plan: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-PL-008-plan.md`
- Source row: `PL-008` / Media upload progress coalescing never drops group messages
- Row-owned source anchors:
  - `go-mknoon/node/node_test.go`: `TestPL008EventDispatcherCoalescesMediaProgressWithoutDroppingGroupMessages`
  - `test/core/bridge/go_bridge_client_test.dart`: `PL-008 bridge routes group messages while media progress events arrive`
  - `test/features/groups/integration/group_messaging_smoke_test.dart`: `PL-008 media upload progress storm does not drop fake-network group messages`

Imported delta:
- Added the row-owned native dispatcher proof that `media:upload_progress` coalesces while interleaved `group_message:received` events remain FIFO, exact-once, and undropped below queue capacity.
- Added the row-owned Flutter bridge proof that media progress events do not suppress interleaved group-message callbacks.
- Added the row-owned fake-network proof that Alice/Bob group sends still reach Alice, Bob, and Charlie exactly once while media progress events are emitted and observed.

Out of scope:
- No production code changes.
- No PL-009+, media ACL/download/rendering, upload retry, reactions, notifications, privacy, stress, broader dispatcher-overflow, Android, physical iOS, or live-device import.
- No original source worktree plan recreation or rerun.

Verification evidence:
- `cd go-mknoon && go test ./node -run TestPL008` - pass
- `flutter test --no-pub test/core/bridge/go_bridge_client_test.dart --plain-name "PL-008 bridge routes group messages while media progress events arrive"` - pass
- `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name "PL-008 media upload progress storm does not drop fake-network group messages"` - pass on serial rerun after the first parallel Flutter attempt failed during native-asset install-name rewriting
- `go test ./node -run 'TestPL008|TestDE011|TestDE012|TestDE020'` - pass
- `flutter test --no-pub test/core/bridge/go_bridge_client_test.dart --plain-name "media:upload_progress push event forwards to upload stream"` - pass
- `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name "DE-012 dispatcher overflow triggers one replay recovery and coalesces duplicates"` - pass
- `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name "DE-020 large payload does not starve later fake-network delivery"` - pass
- `gofmt -w go-mknoon/node/node_test.go` - pass
- `dart format test/core/bridge/go_bridge_client_test.dart test/features/groups/integration/group_messaging_smoke_test.dart` - pass
- `flutter analyze --no-pub test/core/bridge/go_bridge_client_test.dart test/features/groups/integration/group_messaging_smoke_test.dart` - pass
- `git diff --check` - pass

Controller acceptance evidence:
- Read-only scouts confirmed PL-008 is host/native plus fake-network scoped with Unit, Integration, and Fake Network required; Smoke and 3-Party E2E are `N/A`, so no iOS 26.2 live proof is required or claimed.
- Current main already had the production dispatcher and bridge behavior required by PL-008; the imported delta is row-owned tests only.
- Adjacent DE-011, DE-012, DE-020, and media progress bridge preservation selectors passed.
