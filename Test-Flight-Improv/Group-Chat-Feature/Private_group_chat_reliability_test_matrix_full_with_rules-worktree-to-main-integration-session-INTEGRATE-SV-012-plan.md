# INTEGRATE-SV-012 Minimal Integration Contract

Status: accepted

## Scope

Import/reconcile source row `SV-012` from the full-with-rules worktree into main: peer-id text variants must not create duplicate active group identities or bypass membership checks for sends.

This is standard worktree-to-main integration, not new implementation rollout and not gap closure. The historical source plan remains the source of truth:

`/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-SV-012-plan.md`

## Reconciliation

- Source status: accepted/covered in the historical worktree.
- Main status before import: partial. Current main already had stronger native signing-key and transport-peer uniqueness checks; it lacked the row-owned peer-id canonicalization and duplicate-variant rejection layer in Flutter persistence/config handling and native config handling.
- Imported delta: peer-id canonicalization helpers, duplicate variant rejection before Flutter member persistence/config acceptance, native config peer identity validation before join/update/refresh/publish/validation, and row-owned domain/listener/native proof selectors.
- Current-main adaptation: existing native `ambiguous_signing_key` and `ambiguous_transport_peer` checks were preserved and now run after peer identity validation.
- Live proof: not required. Source 3-Party E2E is `N/A`; no iOS 26.2 simulator proof is claimed.

## Imported Artifacts

- `lib/features/groups/domain/models/group_member.dart`
  - peer-id reject helpers and duplicate variant config/member checks.
- `lib/features/groups/domain/repositories/group_repository_impl.dart`
  - rejects malformed or duplicate-variant peer ids before member save/update/remove.
- `test/shared/fakes/in_memory_group_repository.dart`
  - mirrors repository peer-id validation in fake storage.
- `go-mknoon/node/pubsub.go`
  - rejects noncanonical peer ids, alternate decodable peer encodings, and duplicate member/device peer variants while preserving existing signing/transport uniqueness checks.
- `test/features/groups/domain/models/group_member_test.dart`
  - SV-012 peer-id helper tests.
- `test/features/groups/application/group_message_listener_test.dart`
  - SV-012 duplicate variant member-add/send-bypass proof.
- `go-mknoon/node/pubsub_test.go`
  - `TestSV012GroupConfigPeerIdentityRejectsVariants`
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-breakdown.md`
- This contract.

## Verification

- PASS: `flutter test --no-pub test/features/groups/domain/models/group_member_test.dart --plain-name "SV-012"`
- PASS: `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name "SV-012"`
- PASS: `cd go-mknoon && go test ./node -run TestSV012 -count=1`
- PASS: `flutter test --no-pub test/features/groups/domain/models/group_member_test.dart`
- PASS: `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name "member_added saves member and calls updateConfig"`
- PASS: `cd go-mknoon && go test ./node -run 'TestSV012|TestGM017|TestGK033|TestGA003' -count=1`
- PASS: `dart format --set-exit-if-changed lib/features/groups/domain/models/group_member.dart lib/features/groups/domain/repositories/group_repository_impl.dart test/shared/fakes/in_memory_group_repository.dart test/features/groups/domain/models/group_member_test.dart test/features/groups/application/group_message_listener_test.dart`
- PASS: `flutter analyze --no-pub lib/features/groups/domain/models/group_member.dart lib/features/groups/domain/repositories/group_repository_impl.dart test/shared/fakes/in_memory_group_repository.dart test/features/groups/domain/models/group_member_test.dart test/features/groups/application/group_message_listener_test.dart`
- PASS: `test -z "$(gofmt -l go-mknoon/node/pubsub.go go-mknoon/node/pubsub_test.go)"`
- PASS: scoped `git diff --check`

## Closure

`INTEGRATE-SV-012` is accepted as host/native-only. Adjacent rows `SV-013` and later remain separate pending integration sessions.
