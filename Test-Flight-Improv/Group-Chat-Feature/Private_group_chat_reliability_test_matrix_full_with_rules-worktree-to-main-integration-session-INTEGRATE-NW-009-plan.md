# INTEGRATE-NW-009 Minimal Integration Contract

Status: accepted

Session id: `INTEGRATE-NW-009`

Source row: `NW-009 | Relay probe failure does not remove or mute group members | P1 | Network, libp2p Topic Mesh, Relay, and Mobile Lifecycle`

Historical source of truth:

- Source matrix: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules.md`
- Historical accepted plan: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-NW-009-plan.md`
- Source inventory evidence: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`

Do not recreate or rerun the historical implementation plan. This contract governs only importing and verifying the already-accepted NW-009 row delta into the main checkout.

## Current-Main Classification

NW-009 was partially present in main. Production group-send and replay behavior already derives durable recipients from active persisted membership rather than relay probe state, and relay-session request failure handling already keeps transport diagnostics separate from membership state.

The exact row-owned Go, send-use-case, fake-network selectors and integration inventory entry were missing from the current checkout before this row. Therefore this row was not `skipped_already_present`. Only the missing meaningful NW-009 row-owned test/doc delta was accepted.

## Import Scope

Allowed row-owned imports:

- Go relay-session proof `TestNW009RelayProbeFailureKeepsReservationHealth` in `go-mknoon/node/relay_session_test.go`
- send-use-case proof `NW-009 relay probe failure keeps active members as durable recipients` in `test/features/groups/application/send_group_message_use_case_test.dart`
- fake-network proof `NW-009 relay probe failure keeps membership and replay recovery active` in `test/features/groups/integration/group_resume_recovery_test.dart`
- one concise `test-inventory.md` row

Not imported: production code, source docs, COMPLETE_1 docs, runner scenarios, criteria files, live harness files, relay env/shared-dir/run-id proof, iOS/Android/physical-device work, NW-004 reconnect recovery, NW-006 generic disconnect semantics, NW-007 zero-topic-peer behavior, NW-008 duplicate connections, or broader relay shared-state/chaos work.

## Verification

Focused checks run:

```sh
gofmt -w go-mknoon/node/relay_session_test.go
dart format test/features/groups/application/send_group_message_use_case_test.dart test/features/groups/integration/group_resume_recovery_test.dart
cd go-mknoon && go test ./node -run 'TestNW009' -count=1
flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --plain-name 'NW-009'
flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'NW-009'
```

Affected-row preservation checks run:

```sh
cd go-mknoon && go test ./node -run 'TestNW009|TestRelaySession_RequestFailureDoesNotRestartHostImmediately|TestRelaySession_ReportsHealthyWhenReservationAndConnectednessAgree' -count=1
flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --name 'NW-006|NW-007|GP-005|GP-006|GP-007'
flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --name 'NW-006|NW-007|NW-008'
flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --name 'DE-004|DE-005|GP-026'
```

Analyzer and hygiene checks run:

```sh
gofmt -l go-mknoon/node/relay_session_test.go
dart format --set-exit-if-changed test/features/groups/application/send_group_message_use_case_test.dart test/features/groups/integration/group_resume_recovery_test.dart
dart analyze test/features/groups/application/send_group_message_use_case_test.dart test/features/groups/integration/group_resume_recovery_test.dart
git diff --check
```

Results:

- Go focused NW-009 selector: PASS (`ok github.com/mknoon/go-mknoon/node 0.571s`)
- Flutter focused NW-009 send-use-case selector: PASS (`+1`) after rerunning a parallel native-assets startup race serially
- Flutter focused NW-009 fake-network selector: PASS (`+1`)
- Go relay-session preservation bundle: PASS (`ok github.com/mknoon/go-mknoon/node 0.414s`)
- affected send-use-case NW-006/NW-007/GP-005/GP-006/GP-007 selectors: PASS (`+5`)
- affected fake-network NW-006/NW-007/NW-008 selectors: PASS (`+3`)
- affected fake-network DE-004/DE-005/GP-026 selectors: PASS (`+3`)
- `gofmt -l`: PASS with no output
- Dart format: PASS (`Formatted 2 files (0 changed)`)
- scoped Dart analyzer: PASS (`No issues found!`)
- `git diff --check`: PASS

Preflight before execution found no stale proof runner processes, no ambient `MKNOON_` env, and the required iOS 26.2 devices booted and available for later live-proof rows:

- Alice `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`
- Bob `279B82AE-2BB9-4924-9AAE-581870ED3FA9`
- Charlie `116B4AF6-C1A9-4F36-B929-0A7130B5E83C`
- Dana `CD5929A6-EA0A-421D-A6D3-55BD707E0F76`

No relay env, shared directory, run id, or live simulator proof is required or claimed for NW-009 because the historical source row marks smoke and 3-party E2E as `N/A`.
