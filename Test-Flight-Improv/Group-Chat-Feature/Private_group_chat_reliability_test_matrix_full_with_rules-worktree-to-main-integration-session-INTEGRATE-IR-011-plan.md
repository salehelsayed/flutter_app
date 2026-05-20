# INTEGRATE-IR-011 Minimal Integration Contract

Status: accepted

## Source Evidence

- Source row: `IR-011` / `History repair range request validates gap identity and source peer`.
- Source worktree plan: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-IR-011-plan.md`.
- Source closure state: covered/accepted with native, bridge, drain, and fake-network repair-request validation proofs.
- Source proof profile: host-only. Unit, Integration, and Fake Network are required; Smoke and `3-Party E2E` are `N/A`.

This contract is only for importing and verifying the already-closed source row in main. It does not recreate or replace the historical source implementation plan.

## Integration Scope

IR-011 imports only missing row-owned proof artifacts for history repair range request identity/source validation:

- `go-mknoon/node/group_inbox_test.go`
  - Added `TestIR011GroupHistoryRepairRange_NormalizesAndRejectsIdentity`.
  - The test proves native repair requests trim group/gap/source identity, default the limit, and reject missing group, gap, or source before node/relay use.
- `test/core/bridge/go_bridge_client_test.dart`
  - Added `IR-011 history repair helper normalizes request identity and surfaces invalid input`.
  - The test proves typed bridge payload routing and `INVALID_INPUT` surfacing for invalid identity/source values.
- `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`
  - Added `IR-011 history repair request validates gap identity and source peer before mutation`.
  - The test proves wrong-group gaps are skipped, unauthorized/self sources are not requested, wrong group/gap/source responses insert no messages, and only the valid fallback repairs the gap.
- `test/features/groups/integration/group_resume_recovery_test.dart`
  - Added `IR-011 fake-network history repair validates request identity and source peer before mutation`.
  - The test proves the same source/request filtering and response identity validation through fake-network resume recovery.

Production code stayed untouched because current main already had native normalization, bridge invalid-input surfacing, Dart helper payload routing, and drain-side wrong-group/source validation.

Out of scope: `IR-010` history-gap parsing, `IR-012` hash/head validation, `IR-013` unauthorized source injection, retention cutoff, relay ACL/privacy, media, UI, notifications, criteria/live harnesses, iOS 26.2 proof, and adjacent replay rows.

## Verification

Passed:

```bash
(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run IR011)
flutter test --no-pub test/core/bridge/go_bridge_client_test.dart --plain-name 'IR-011'
flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'IR-011'
flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'IR-011'
dart format --set-exit-if-changed test/core/bridge/go_bridge_client_test.dart test/features/groups/application/drain_group_offline_inbox_use_case_test.dart test/features/groups/integration/group_resume_recovery_test.dart
gofmt -l go-mknoon/node/group_inbox_test.go
flutter analyze --no-pub lib/core/bridge/bridge_group_helpers.dart lib/features/groups/application/drain_group_offline_inbox_use_case.dart test/core/bridge/go_bridge_client_test.dart test/features/groups/application/drain_group_offline_inbox_use_case_test.dart test/features/groups/integration/group_resume_recovery_test.dart
(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'GI027|GI028|GI029|GI030|GroupHistoryRepairRange')
(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./bridge -run 'GroupHistoryRepairRange')
flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --name 'IR-010 drains valid cursor historyGaps|PREREQ-HISTORY-GAP-REPAIR|GI-026 history gap metadata|GI-031 repair range hash mismatch'
flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'PREREQ-HISTORY-GAP-REPAIR fake-network repair rejects bad source then restores range before live delivery'
git diff --check
```

Classified residual gates:

```bash
FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups
# +213 -3, red only on preserved non-IR-011 residuals BB-007, BB-012, and GM-029

./scripts/run_test_gates.sh completeness-check
# 732/733, red only on unrelated test/shared/fakes/fake_group_pubsub_network_test.dart classification
```

No iOS 26.2 simulator/live proof was run or required because source `3-Party E2E` is `N/A`.

## Closure Verdict

`INTEGRATE-IR-011` is accepted. Main now has row-owned native, bridge, drain, and fake-network proofs that repair range requests validate group/gap/source identity before history mutation, skip unauthorized or self sources, reject mismatched responses, and apply only the valid fallback repair.
