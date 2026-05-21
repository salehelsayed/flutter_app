# INTEGRATE-ST-011 Plan - Standard Integration Contract

Status: accepted

## Scope

Import and verify historical row `ST-011`: "Rapid EventChannel reinitialize loop does not drop group callbacks permanently."

This was standard worktree-to-main integration, not gap-closure. The historical source plan and closure evidence stayed the source of truth; no original implementation plan was regenerated.

## Source Evidence

- Historical source plan: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-ST-011-plan.md`.
- Source row-owned proof selectors:
  - `flutter test test/core/bridge/go_bridge_client_test.dart --plain-name "ST-011"`
  - `flutter test test/features/groups/integration/group_messaging_smoke_test.dart --plain-name "ST-011"`
- Source 3-party E2E: `N/A`.

## Imported Delta

- Imported the row-owned `GoBridgeClient.reinitialize()` in-flight coalescing guard so overlapping rapid calls share one cancel/resubscribe cycle instead of racing the single EventChannel subscription.
- Imported the row-owned bridge test proving a rapid reinitialize burst coalesces, later bursts still reinitialize, and the final group callback remains live.
- Imported the row-owned group integration test proving repeated reinitialize bursts around group-message push events still persist callback-delivered group messages exactly once.
- Added the source row's required test binding initialization for `group_messaging_smoke_test.dart` so the mocked EventChannel can be used in that integration file.

## Verification

Passed:

- `flutter test --no-pub test/core/bridge/go_bridge_client_test.dart --plain-name "ST-011"`
- `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name "ST-011"`
- `dart format --set-exit-if-changed lib/core/bridge/go_bridge_client.dart test/core/bridge/go_bridge_client_test.dart test/features/groups/integration/group_messaging_smoke_test.dart`
- `dart analyze lib/core/bridge/go_bridge_client.dart test/core/bridge/go_bridge_client_test.dart test/features/groups/integration/group_messaging_smoke_test.dart`
- `git diff --check`

## Verdict

`accepted`

ST-011 is imported and verified. The integration stayed limited to row-owned EventChannel reinitialize coalescing and proof artifacts. Existing blocked rows remain unchanged.
