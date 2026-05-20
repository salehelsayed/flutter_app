Status: accepted

# INTEGRATE-BB-014 Standard Integration Plan

## Planning Progress

- 2026-05-17T06:44:00+02:00 - Inspected source matrix row `BB-014`, source session breakdown row, historical source plan/closure evidence, source test-inventory note, source `go_bridge_client_test.dart`, current main command-routing coverage, and COMPLETE_1 command-map/bridge overlap. Decision/blocker: source BB-014 is a tests-only import. Main already has broad command-map coverage and the production command map, but lacks row-named private-group helper inventory coverage and per-command missing-plugin drift proof. Next action: import only the two missing BB-014 selectors into `test/core/bridge/go_bridge_client_test.dart`.

## Real Scope

This is a standard worktree-to-main integration contract for exactly `INTEGRATE-BB-014` / source row `BB-014`: GoBridge command map covers every private-group command used by helpers.

Reuse the historical source worktree BB-014 plan and closure as evidence only. Do not recreate, rewrite, or rerun the original implementation plan. Do not reimplement this row from scratch. Import only the missing meaningful BB-014-owned test delta into main, adapted to current main drift.

In scope:

- Add a row-named GoBridgeClient helper-command inventory test proving private-group helper commands route to the expected MethodChannel methods without `UNKNOWN_COMMAND`.
- Add a row-named missing-native-method drift test proving each private-group helper command returns `MISSING_PLUGIN` guidance containing the helper command and native method name.
- Reuse existing production `GoBridgeClient` command map behavior; production files stay untouched unless focused BB-014 proof exposes a real command-map gap.

Out of scope:

- Do not copy source matrix, source session breakdown, source test-inventory, or historical source plan docs into main.
- Do not edit COMPLETE_1 docs.
- Do not import source OB-001 flow-event tests, BB-015 malformed/null/platform response safety, BB-016 metadata/config drift, native Go implementation behavior, app state mutation behavior, device/relay proof, UI, notification, media, observability, or broader reliability work.

## Source Of Truth

- Source row: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules.md` row `BB-014`.
- Source breakdown: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md` session `BB-014`.
- Historical worktree plan/evidence: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-BB-014-plan.md`.
- Source closure evidence: source `test-inventory.md` row `BB-014` and source matrix `BB-014` covered note.
- Main integration controller: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-breakdown.md`.
- Main compatibility artifact: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md`.
- Current code and tests in main win over stale prose when they conflict.

## Source File Evidence

Meaningful source files for integration:

- `test/core/bridge/go_bridge_client_test.dart`

Source docs changed in the worktree closure are historical evidence only and must not be copied.

## Duplicate Presence In Main

Main already has broad command routing coverage and an `all 51 commands are covered` sanity test. It lacks exact `BB-014` selectors, the private-group helper inventory assertion that includes no-payload helper behavior, and the per-command missing-plugin drift proof. Import the missing selectors rather than duplicating existing broad routing tests.

## COMPLETE_1 Overlap Rows

Inspect and preserve:

- COMPLETE_1 bridge/client command-map and callback rows that rely on `GoBridgeClient.send` routing.
- COMPLETE_1 observability and bridge-diagnostic rows that may share `GO_BRIDGE_SEND`, `BRIDGE_CALL_TIMING`, missing-plugin, or privacy-safe diagnostic behavior.

No COMPLETE_1 row owns the exact BB-014 helper inventory plus missing-plugin drift contract.

## Tests And Gates To Run

Focused BB-014 proof:

```bash
flutter test --no-pub test/core/bridge/go_bridge_client_test.dart --plain-name "BB-014"
```

Preservation/backstop:

```bash
flutter test --no-pub test/core/bridge/go_bridge_client_test.dart --plain-name "command routing"
flutter test --no-pub test/core/bridge/go_bridge_client_test.dart --plain-name "MissingPluginException returns MISSING_PLUGIN"
flutter test --no-pub test/core/bridge/go_bridge_client_test.dart --plain-name "all 51 commands are covered"
FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups
dart format --set-exit-if-changed test/core/bridge/go_bridge_client_test.dart
flutter analyze --no-pub test/core/bridge/go_bridge_client_test.dart
git diff --check
```

## Final Status Contract

- `accepted`: missing meaningful BB-014 tests imported and required focused/preservation tests pass.
- `skipped_already_present`: all meaningful BB-014 selector evidence already exists in main.
- `blocked_conflict`: focused tests expose a production command-map gap or conflict with accepted COMPLETE_1 behavior.
- `blocked_external_fixture`: only if a required external fixture unexpectedly blocks closure.

## Execution Progress

- 2026-05-17T06:48:00+02:00 - Imported only the missing meaningful BB-014 test delta into `test/core/bridge/go_bridge_client_test.dart`: one helper-command routing selector and one missing-native-method drift selector. No production code was changed.
- 2026-05-17T06:51:00+02:00 - Focused BB-014 selector passed (`+2`). Full `go_bridge_client_test.dart` passed (`+76`), preserving existing command routing, generic missing-plugin handling, push diagnostics, and the `all 51 commands are covered` sanity test.
- 2026-05-17T07:20:00+02:00 - Scoped analyzer passed with no issues. `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` passed (`+167`). Dart format passed with `0 changed`, and `git diff --check` passed.

## Final Execution Result

Status: `accepted`

Accepted row-owned files:

- `test/core/bridge/go_bridge_client_test.dart`

Verification:

- `flutter test --no-pub test/core/bridge/go_bridge_client_test.dart --plain-name "BB-014"` passed (`+2`).
- `flutter test --no-pub test/core/bridge/go_bridge_client_test.dart` passed (`+76`).
- `flutter analyze --no-pub test/core/bridge/go_bridge_client_test.dart` passed with no issues.
- `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` passed (`+167`).
- `dart format --set-exit-if-changed test/core/bridge/go_bridge_client_test.dart` passed with `0 changed`.
- `git diff --check` passed.

Skipped as already present or out of scope: broad command routing and the production command map already existed in main; source docs were not copied; COMPLETE_1 docs were untouched; no OB-001 flow-event tests, BB-015 malformed/null/platform response safety, BB-016 metadata/config drift, native Go implementation behavior, app mutation behavior, device/relay proof, UI, notification, media, observability, or broader reliability work was imported. No conflict was found.
