# INTEGRATE-NW-008 Minimal Integration Contract

Status: accepted

Session id: `INTEGRATE-NW-008`

Source row: `NW-008 | Duplicate libp2p connections do not duplicate visible messages | P1 | Network, libp2p Topic Mesh, Relay, and Mobile Lifecycle`

Historical source of truth:

- Source matrix: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules.md`
- Historical accepted plan: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-NW-008-plan.md`
- Source inventory evidence: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`

Do not recreate or rerun the historical implementation plan. This contract governs only importing and verifying the already-accepted NW-008 row delta into the main checkout.

## Current-Main Classification

NW-008 was partially present in main. Production duplicate handling was already present: incoming group messages dedupe by `messageId`, listener stream/notification work is skipped when the handler returns `null`, and native direct address filtering already removes relay-circuit paths while preserving unique direct multiaddrs.

The exact row-owned proof selectors and integration inventory entry were missing from the current checkout before this row. Therefore this row was not `skipped_already_present`. Only the missing meaningful NW-008 row-owned test/doc delta was accepted.

## Import Scope

Allowed row-owned imports:

- Go duplicate direct-address proof `TestNW008DuplicateConnectionPathsDedupedBeforeGroupDial` in `go-mknoon/node/pubsub_test.go`
- listener duplicate-delivery proof `NW-008 duplicate connection path delivery keeps one visible row and status` in `test/features/groups/application/group_message_listener_test.dart`
- fake-network duplicate-delivery proof `NW-008 duplicate libp2p-style deliveries keep one visible message per receiver` in `test/features/groups/integration/group_resume_recovery_test.dart`
- one concise `test-inventory.md` row

Not imported: production code, source docs, COMPLETE_1 docs, runner scenarios, criteria files, live harness files, relay env/shared-dir/run-id proof, iOS/Android/physical-device work, NW-009 relay probe behavior, or broader relay shared-state architecture.

## Verification

Focused checks run:

```sh
gofmt -w go-mknoon/node/pubsub_test.go
dart format test/features/groups/application/group_message_listener_test.dart test/features/groups/integration/group_resume_recovery_test.dart
cd go-mknoon && go test ./node -run 'TestNW008' -count=1
flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name 'NW-008'
flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'NW-008'
```

Affected-row preservation checks run:

```sh
cd go-mknoon && go test ./node -run 'TestNW008|TestNW005RendezvousRediscoveryUsesCurrentMembershipOnly|TestGP013DirectAddressPreferenceExcludesRelayCircuitAddrs' -count=1
flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --name 'NW-006|NW-005|DE-004|DE-005|GP-026'
flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --name 'DE-005|shows notification for incoming group message|deduplicates by messageId|duplicate replay'
flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name 'DE-005 self echo emits reconciled outbound row once'
```

Analyzer and hygiene checks run:

```sh
gofmt -l go-mknoon/node/pubsub_test.go
dart format --set-exit-if-changed test/features/groups/application/group_message_listener_test.dart test/features/groups/integration/group_resume_recovery_test.dart
dart analyze test/features/groups/application/group_message_listener_test.dart test/features/groups/integration/group_resume_recovery_test.dart
git diff --check
```

Results:

- Go focused NW-008 selector: PASS (`ok github.com/mknoon/go-mknoon/node 0.557s`)
- Flutter focused NW-008 listener selector: PASS (`+1`) after rerunning a parallel native-assets startup race serially
- Flutter focused NW-008 fake-network selector: PASS (`+1`)
- Go affected NW-005/GP-013 duplicate-address preservation bundle: PASS (`ok github.com/mknoon/go-mknoon/node 0.449s`)
- affected fake-network NW-005/NW-006/DE-004/DE-005/GP-026 selectors: PASS (`+5`)
- affected listener DE-005 selector: PASS (`+1`)
- broad listener preservation command reran the existing notification selector and reproduced the preserved notification-count residual (`Expected: an object with length of <1> / Actual: []`), outside NW-008; the row-owned NW-008 listener selector and DE-005 preservation selector passed.
- `gofmt -l`: PASS with no output
- Dart format: PASS (`Formatted 2 files (0 changed)`)
- scoped Dart analyzer: PASS (`No issues found!`)
- `git diff --check`: PASS

Preflight before execution found no stale proof runner processes, no ambient `MKNOON_` env, and the required iOS 26.2 devices booted and available for later live-proof rows:

- Alice `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`
- Bob `279B82AE-2BB9-4924-9AAE-581870ED3FA9`
- Charlie `116B4AF6-C1A9-4F36-B929-0A7130B5E83C`
- Dana `CD5929A6-EA0A-421D-A6D3-55BD707E0F76`

No relay env, shared directory, run id, or live simulator proof is required or claimed for NW-008 because the historical source row marks 3-party E2E as `N/A`.
