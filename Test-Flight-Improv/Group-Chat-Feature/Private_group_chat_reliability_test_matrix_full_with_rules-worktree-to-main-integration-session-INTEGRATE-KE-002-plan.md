# INTEGRATE-KE-002 Integration Contract

Status: accepted

## Scope

Import and verify only source row `KE-002`: `group:generateNextKey` must compute the candidate epoch from the latest committed Go validator key state, return `latestEpoch + 1`, and avoid mutating validator key state until the caller explicitly commits the candidate through `group:updateKey`.

This is standard integration mode. The historical source worktree remains the source of truth; this plan is only the minimal import/reconcile/verify contract for current main. Do not update or recreate the original worktree implementation plan.

## Source Evidence

- Source worktree: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline`
- Source plan: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-KE-002-plan.md`
- Historical accepted source proof: `cd go-mknoon && go test ./bridge -run 'TestGroupGenerateNextKey' -count=1` passed, `cd go-mknoon && go test ./bridge -count=1` passed, and `git diff --check` passed.
- Source row marks Smoke, Fake Network, and 3-Party E2E as `N/A`; no live simulator proof is part of the row contract.

## Import Contract

- Preserve current production `GroupGenerateNextKey` and `GroupUpdateKey` behavior; no KE-002 production code import was needed.
- Import only the missing row-owned Go bridge regression `TestGroupGenerateNextKey_KE002UsesLatestCommittedEpochWithoutMutating`.
- Do not import adjacent source-worktree KE-013 restart/missing-memory tests, stale/downgrade behavior, Flutter runtime changes, source matrix docs, source session docs, or test-inventory rows.
- Preserve current main's BB-003 creator-material fixture adjustment by keeping `creatorMlKemPublicKey` in the create payload.

## Device Reality

No simulator or live proof was required or run for KE-002. The row is a Go bridge regression with Smoke, Fake Network, and 3-Party E2E marked `N/A` in the source evidence.

## Verification Log

- PASS: `gofmt -w bridge/bridge_generate_next_key_test.go`.
- PASS: `cd go-mknoon && go test ./bridge -run 'TestGroupGenerateNextKey' -count=1` (`ok github.com/mknoon/go-mknoon/bridge 0.544s`).
- PASS: `cd go-mknoon && go test ./bridge -count=1` (`ok github.com/mknoon/go-mknoon/bridge 108.925s`).
- PASS: `flutter test --no-pub test/core/bridge/bridge_group_helpers_test.dart --plain-name 'callGroupGenerateNextKey'` (`+2`).
- PASS: `flutter test --no-pub test/core/bridge/go_bridge_client_test.dart --plain-name 'group:generateNextKey'` (`+1`).
- PASS: scoped `git diff --check` on `go-mknoon/bridge/bridge_generate_next_key_test.go`.
- NOT RUN: `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` and `./scripts/run_test_gates.sh completeness-check`, because KE-002 imported only one Go bridge test and source KE-002 marks smoke/fake-network/live proof as `N/A`. Existing residuals remain preserved from prior row evidence: non-row `BB-007`, non-row `GM-029`, and the completeness classification gap for `test/shared/fakes/fake_group_pubsub_network_test.dart`.

## Final Integration Verdict

`accepted` for `INTEGRATE-KE-002`.

The row-owned Go regression is present in main and proves generation from a later committed epoch, non-mutation before explicit commit, explicit `GroupUpdateKey` commit, and a subsequent `N+2` candidate without mutating the committed state. Focused Go bridge tests, full Go bridge package tests, narrow Dart command-surface preservation, and scoped diff hygiene passed.
