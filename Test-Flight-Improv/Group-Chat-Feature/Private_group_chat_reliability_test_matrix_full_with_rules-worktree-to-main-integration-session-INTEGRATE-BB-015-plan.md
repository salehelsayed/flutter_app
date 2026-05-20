Status: accepted

# INTEGRATE-BB-015 Standard Integration Plan

## Planning Progress

- 2026-05-17T07:22:00+02:00 - Inspected source matrix row `BB-015`, source session breakdown row, historical source plan/closure evidence, source test-inventory note, source production/test files, current main bridge response handling, current main tests, and COMPLETE_1 malformed/native-response overlap rows. Decision/blocker: main already has generic null/platform/missing-plugin/redaction coverage, but still returns raw invalid native JSON from `_sanitizeBridgeResult` and lacks exact BB-015 selectors. Next action: import the row-owned malformed-response sanitizer fix plus four focused tests only.

## Real Scope

This is a standard worktree-to-main integration contract for exactly `INTEGRATE-BB-015` / source row `BB-015`: native null, missing plugin, platform error, malformed JSON, and `{ok:false}` responses are explicit, sanitized, and do not create ghost group/send state.

Reuse the historical source worktree BB-015 plan and closure as evidence only. Do not recreate, rewrite, or rerun the original implementation plan. Do not reimplement this row from scratch. Import only the missing meaningful BB-015-owned delta into main, adapted to current main drift.

In scope:

- Update `GoBridgeClient._sanitizeBridgeResult` so invalid native JSON and non-map native JSON return structured `{ok:false, errorCode:MALFORMED_RESPONSE}` without echoing raw native payload text.
- Add row-named tests covering private-group native null, missing plugin, platform error, malformed JSON, and native ok-false responses.
- Add helper-level structured failure surfacing coverage.
- Add create no-ghost-state coverage for native response failures.
- Add send failed/retryable-row coverage for native publish response failures.

Out of scope:

- Do not copy source matrix, source session breakdown, source test-inventory, or historical source plan docs into main.
- Do not edit COMPLETE_1 docs.
- Do not import BB-016 metadata/config drift, BB-014 command-map work beyond preserving it, BB-013 timeout behavior, native Go behavior, device/relay proof, UI, notification, media, observability, security rows beyond response sanitization, or broad retry architecture.

## Source Of Truth

- Source row: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules.md` row `BB-015`.
- Source breakdown: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md` session `BB-015`.
- Historical worktree plan/evidence: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-BB-015-plan.md`.
- Source closure evidence: source `test-inventory.md` row `BB-015` and source matrix `BB-015` covered note.
- Main integration controller: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-breakdown.md`.
- Main compatibility artifact: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md`.
- Current code and tests in main win over stale prose when they conflict.

## Source File Evidence

Meaningful source files for integration:

- `lib/core/bridge/go_bridge_client.dart`
- `lib/core/bridge/bridge_group_helpers.dart`
- `test/core/bridge/go_bridge_client_test.dart`
- `test/core/bridge/bridge_group_helpers_test.dart`
- `test/features/groups/application/create_group_use_case_test.dart`
- `test/features/groups/application/send_group_message_use_case_test.dart`

Source docs changed in the worktree closure are historical evidence only and must not be copied.

## Duplicate Presence In Main

Main already has generic null, platform, missing-plugin, and redaction tests in `go_bridge_client_test.dart`; broad command-map coverage; and BB-013 timeout no-ghost-state coverage. Main lacks exact BB-015 selectors and still lacks structured malformed/non-map native JSON handling. Import only those missing deltas.

## COMPLETE_1 Overlap Rows

Inspect and preserve:

- COMPLETE_1 bridge/client response-safety, malformed-payload, and privacy-safe diagnostics rows.
- Existing BB-013 timeout failure semantics and BB-014 command-map selectors in this integration artifact.

No COMPLETE_1 row owns the exact BB-015 MethodChannel response failure plus no-ghost-state contract.

## Tests And Gates To Run

Focused BB-015 proof:

```bash
flutter test --no-pub test/core/bridge/go_bridge_client_test.dart test/core/bridge/bridge_group_helpers_test.dart test/features/groups/application/create_group_use_case_test.dart test/features/groups/application/send_group_message_use_case_test.dart --plain-name "BB-015"
```

Preservation/backstop:

```bash
flutter test --no-pub test/core/bridge/go_bridge_client_test.dart --plain-name "error handling"
flutter test --no-pub test/core/bridge/go_bridge_client_test.dart --plain-name "BB-014"
flutter test --no-pub test/core/bridge/bridge_group_helpers_test.dart --plain-name "BB-013"
flutter test --no-pub test/features/groups/application/create_group_use_case_test.dart --plain-name "BB-013"
flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --plain-name "BB-013"
FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups
dart format --set-exit-if-changed lib/core/bridge/go_bridge_client.dart lib/core/bridge/bridge_group_helpers.dart test/core/bridge/go_bridge_client_test.dart test/core/bridge/bridge_group_helpers_test.dart test/features/groups/application/create_group_use_case_test.dart test/features/groups/application/send_group_message_use_case_test.dart
flutter analyze --no-pub lib/core/bridge/go_bridge_client.dart lib/core/bridge/bridge_group_helpers.dart test/core/bridge/go_bridge_client_test.dart test/core/bridge/bridge_group_helpers_test.dart test/features/groups/application/create_group_use_case_test.dart test/features/groups/application/send_group_message_use_case_test.dart
git diff --check
```

## Execution Progress

- 2026-05-17T07:25:00+02:00 - Imported the missing BB-015 malformed/non-map native JSON sanitizer into `GoBridgeClient._sanitizeBridgeResult`, returning structured `MALFORMED_RESPONSE` errors instead of raw malformed payloads.
- 2026-05-17T07:28:00+02:00 - Added the BB-015 row-named MethodChannel, helper, create-use-case, and send-use-case tests. The first focused run exposed that `callGroupKeygen` still cast `groupKey` on native `ok:false`; imported the source worktree's row-owned fail-closed `callGroupKeygen` guard and invalid-response check.
- 2026-05-17T07:35:00+02:00 - Focused BB-015 tests passed (`+4`); full `go_bridge_client_test.dart` passed (`+77`); BB-014 preservation selector passed (`+2`); affected BB-013 preservation selectors passed (`+10`).
- 2026-05-17T07:38:00+02:00 - Scoped analyzer command failed only on pre-existing/non-row style diagnostics: `use_null_aware_elements` in `lib/core/bridge/bridge_group_helpers.dart:46` and `:48`, and `unnecessary_non_null_assertion` in `test/features/groups/application/create_group_use_case_test.dart:674`. These diagnostics are not introduced by BB-015 and were not fixed under this row scope.
- 2026-05-17T07:39:00+02:00 - Broad affected main guard passed: `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` (`+167`). Formatting passed for the six row-owned code/test files (`0 changed`). Row-scoped `git diff --check` passed.

## Final Status Contract

- `accepted`: missing meaningful BB-015 code/tests imported and required focused/preservation tests pass.
- `skipped_already_present`: all meaningful BB-015 code and selector evidence already exists in main.
- `blocked_conflict`: focused tests expose a conflict with accepted COMPLETE_1/main behavior.
- `blocked_external_fixture`: only if a required external fixture unexpectedly blocks closure.

## Final Verdict

`accepted` - BB-015's missing meaningful row-owned delta has been imported into main. The integration accepted only structured malformed native response handling, `callGroupKeygen` structured failure safety, and BB-015-focused tests. Source docs and unrelated worktree changes were not copied.
