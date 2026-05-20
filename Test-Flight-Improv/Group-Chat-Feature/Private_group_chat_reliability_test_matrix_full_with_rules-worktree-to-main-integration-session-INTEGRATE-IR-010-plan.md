# INTEGRATE-IR-010 Minimal Integration Contract

Status: accepted

## Source Evidence

- Source row: `IR-010` / `History gaps from cursor retrieval are parsed and surfaced`.
- Source worktree plan: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-IR-010-plan.md`.
- Source closure state: covered/accepted with bridge parser and drain repair-lifecycle proofs.
- Source proof profile: host-only. Unit is required; Integration is recommended; Smoke, Fake Network, and `3-Party E2E` are `N/A`.

This contract is only for importing and verifying the already-closed source row in main. It does not recreate or replace the historical source implementation plan.

## Integration Scope

IR-010 imports only missing row-owned proof artifacts for cursor `historyGaps` parsing and drain-surfaced history repair lifecycle creation:

- `test/core/bridge/bridge_group_helpers_test.dart`
  - Added `IR-010 parses and surfaces valid cursor historyGaps while filtering invalid entries`.
  - The test proves valid cursor history gaps are parsed, invalid gap entries are ignored, and `historyGapCount` reflects the accepted gap count.
- `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`
  - Added `IR-010 drains valid cursor historyGaps into repair lifecycle and ignores invalid gaps`.
  - The test proves a valid cursor history gap is persisted into the repair lifecycle with the expected cursor/source identity while invalid gap entries do not create repairs or messages.

Production code stayed untouched because current main already had `GroupInboxHistoryGap` parsing, `historyGapCount`, and drain-side repair lifecycle persistence for cursor history gaps.

Out of scope: `IR-011` repair request validation, `IR-012` hash/head repair verification, relay ACLs, media, criteria/live harnesses, iOS 26.2 proof, UI, notification, and adjacent replay rows.

## Verification

Passed:

```bash
flutter test --no-pub test/core/bridge/bridge_group_helpers_test.dart --plain-name 'IR-010 parses and surfaces valid cursor historyGaps while filtering invalid entries'
flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'IR-010 drains valid cursor historyGaps into repair lifecycle and ignores invalid gaps'
flutter analyze --no-pub lib/core/bridge/bridge_group_helpers.dart lib/features/groups/application/drain_group_offline_inbox_use_case.dart test/core/bridge/bridge_group_helpers_test.dart test/features/groups/application/drain_group_offline_inbox_use_case_test.dart
flutter test --no-pub test/core/bridge/bridge_group_helpers_test.dart --name 'IR-010 parses and surfaces valid cursor historyGaps|parses valid history gap metadata from cursor response|IR-002 parses GroupInboxPage cursor metadata'
flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --name 'IR-010 drains valid cursor historyGaps|GI-026 history gap metadata|PREREQ-HISTORY-GAP-REPAIR detects|PREREQ-HISTORY-GAP-REPAIR rejects|PREREQ-HISTORY-GAP-REPAIR applies'
flutter test --no-pub test/features/groups/application/drain_followup_invariants_test.dart --plain-name 'detected history gaps are persisted before the cursor commit so they survive a Phase 2 transaction failure'
(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'TestGI011GroupInboxRetrieveWithCursorResultPreservesMessagesCursorAndHistoryGaps')
dart format --set-exit-if-changed test/core/bridge/bridge_group_helpers_test.dart test/features/groups/application/drain_group_offline_inbox_use_case_test.dart
git diff --check
```

Classified residual gates:

```bash
FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups
# +212 -3, red only on preserved non-IR-010 residuals BB-007, BB-012, and GM-029

./scripts/run_test_gates.sh completeness-check
# 732/733, red only on unrelated test/shared/fakes/fake_group_pubsub_network_test.dart classification
```

No iOS 26.2 simulator/live proof was run or required because source `3-Party E2E` is `N/A`.

## Closure Verdict

`INTEGRATE-IR-010` is accepted. Main now has the row-owned bridge parser and drain lifecycle proofs that valid cursor `historyGaps` are parsed, invalid entries are filtered, `historyGapCount` is surfaced, and only valid gaps are persisted into the repair lifecycle.
