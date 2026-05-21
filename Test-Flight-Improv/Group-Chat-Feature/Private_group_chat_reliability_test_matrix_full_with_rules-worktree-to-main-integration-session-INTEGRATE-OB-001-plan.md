# INTEGRATE-OB-001 Minimal Integration Contract

Status: accepted

## Scope

Import/reconcile source row `OB-001` from the full-with-rules worktree into main: every private group bridge helper command must have host-side proof for request/response or send/timing flow-event observability.

This is standard worktree-to-main integration, not a new implementation rollout and not gap closure. The historical source plan remains the source of truth:

`/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-OB-001-plan.md`

## Reconciliation

- Source status: accepted/covered in the historical worktree.
- Main status before import: partial. Current main already had the bridge helper flow-event production surfaces and BB-014 private-command map coverage; it lacked the two row-named OB-001 test selectors.
- Imported delta: row-owned tests only.
- Current-main adaptation: merged the two row-owned selectors into current-main test files without replacing existing SV-013, SV-015, SV-016, BB-014, or bridge-owner coverage.
- Live proof: not required. Source 3-Party E2E is `N/A`; no iOS 26.2 simulator proof is claimed.

## Imported Artifacts

- `test/core/bridge/bridge_group_helpers_test.dart`
  - Adds `OB-001 core group helpers emit request and response flow events`, proving create, join, publish, update config, generate key, update key, inbox store, inbox retrieve, history repair, and leave emit matching request/response flow events with UTC timestamps, detail maps, and success outcomes.
- `test/core/bridge/go_bridge_client_test.dart`
  - Adds `OB-001 private group commands emit send and timing flow events`, proving every private group helper command emits `GO_BRIDGE_SEND` and `BRIDGE_CALL_TIMING` with command, native method, elapsed bridge milliseconds, and success outcome.
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-breakdown.md`
- This contract.

## Already Present

- Bridge helper and GoBridge production flow-event emission surfaces were already present in current main and were preserved unchanged.
- BB-014 private group command map coverage was already present and was used as the adjacent preservation selector.

## Verification

- PASS: `flutter test --no-pub test/core/bridge/bridge_group_helpers_test.dart --plain-name "OB-001"`
- PASS: `flutter test --no-pub test/core/bridge/go_bridge_client_test.dart --plain-name "OB-001"`
- PASS: `flutter test --no-pub test/core/bridge/go_bridge_client_test.dart --plain-name "BB-014 helper private-group commands route through GoBridge map"`
- PASS: `flutter analyze --no-pub test/core/bridge/bridge_group_helpers_test.dart test/core/bridge/go_bridge_client_test.dart`
- PASS: `dart format --set-exit-if-changed test/core/bridge/bridge_group_helpers_test.dart test/core/bridge/go_bridge_client_test.dart`
- PASS: scoped `git diff --check`

## Closure

`INTEGRATE-OB-001` is accepted as host-only tests import. Later observability and stress rows remain separate pending integration sessions.
