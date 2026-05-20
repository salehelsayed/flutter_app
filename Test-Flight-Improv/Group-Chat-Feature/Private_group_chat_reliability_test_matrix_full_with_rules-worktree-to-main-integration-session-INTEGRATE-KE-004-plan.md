# INTEGRATE-KE-004 Integration Contract

Status: accepted

## Scope

Import and verify only source row `KE-004`: a same-epoch, same-material `updateKey` replay must be idempotent. The duplicate must not downgrade or mutate active key state, duplicate native `group:updateKey` calls, duplicate repair retries, emit conflict/error diagnostics, or break delivery on the current epoch.

This is standard integration mode. The historical source worktree remains the source of truth; this plan is only the minimal import/reconcile/verify contract for current main. Do not update or recreate the original worktree implementation plan.

## Source Evidence

- Source worktree: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline`
- Source plan: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-KE-004-plan.md`
- Historical source proof included focused KE-004 listener and fake-network selectors, native Go same-epoch same-material delivery proof, scoped format/analyzer/gofmt/diff hygiene, groups gate with unrelated reds, and completeness with an unrelated source-worktree classification gap.
- Source row-owned files inspected: `test/features/groups/application/group_key_update_listener_test.dart`, `test/features/groups/integration/group_messaging_smoke_test.dart`, and `go-mknoon/node/pubsub_key_rotation_grace_test.go`.

## Current Main Classification

- Already present: production duplicate same-generation/same-material no-op guard in `lib/features/groups/application/group_key_update_listener.dart`.
- Already present: production Go native same-or-lower epoch no-op in `go-mknoon/node/pubsub.go`.
- Partial: current listener test already proved one saved key, one `group:updateKey`, and one repair retry for duplicate same-generation same-material updates; missing row-owned KE-004 selector/diagnostic assertions were merged into that existing test instead of duplicating it.
- Missing: KE-004 row-owned fake-network delivery proof and native Go same-epoch same-material delivery proof.

## Import Contract

- Preserve current production behavior; do not import production code for KE-004.
- Merge missing assertions into the existing listener duplicate test instead of adding a duplicate listener test with the same behavioral contract.
- Import only the missing row-owned fake-network delivery proof and native Go delivery proof.
- Do not import adjacent KE-005 same-epoch different-key conflict, KE-003 stale lower-epoch behavior, key rotation, repair, criteria, runner, live harness, source matrix docs, source test-inventory docs, or unrelated stress rows.

## Verification Plan

- Run focused KE-004 Flutter selectors across the listener and fake-network suites.
- Run native Go KE-004 selector.
- Run adjacent preservation selectors for existing duplicate same-generation behavior and same-epoch conflict behavior.
- Run scoped analyzer, formatter, gofmt, and diff hygiene.
- Run `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` and preserve known non-KE-004 residual failures if unchanged.
- Run `./scripts/run_test_gates.sh completeness-check` and preserve known non-KE-004 classification residuals if unchanged.
- No criteria, runner, live harness, or iOS 26.2 proof is required for this row because the source row marks 3-Party E2E as `N/A`.

## Execution Result

Final verdict: accepted.

Imported row-owned missing KE-004 proof artifacts only:

- `test/features/groups/application/group_key_update_listener_test.dart`: merged row-owned KE-004 selector and duplicate/conflict/error flow-event assertions into the existing duplicate same-generation same-material test.
- `test/features/groups/integration/group_messaging_smoke_test.dart`: added fake-network proof `KE-004 same-epoch same-key update is idempotent and delivery remains readable`.
- `go-mknoon/node/pubsub_key_rotation_grace_test.go`: added `TestKE004UpdateGroupKeySameEpochSameMaterialIsIdempotentAndKeepsEpoch3Delivery`.

Skipped as already present:

- Production duplicate same-generation/same-material no-op guard in `lib/features/groups/application/group_key_update_listener.dart`.
- Production Go native same-or-lower epoch no-op in `go-mknoon/node/pubsub.go`.
- Criteria, runner, live harness, and iOS 26.2 proof surfaces, because source KE-004 marks 3-Party E2E as `N/A` and no KE-004-owned criteria/harness deltas exist.

Verification:

- `dart format --set-exit-if-changed test/features/groups/application/group_key_update_listener_test.dart test/features/groups/integration/group_messaging_smoke_test.dart` PASS (`Formatted 2 files (0 changed)`).
- `gofmt -w go-mknoon/node/pubsub_key_rotation_grace_test.go` PASS; `gofmt -l go-mknoon/node/pubsub_key_rotation_grace_test.go` returned no files.
- `flutter test --no-pub test/features/groups/application/group_key_update_listener_test.dart test/features/groups/integration/group_messaging_smoke_test.dart --plain-name 'KE-004'` PASS (`+2`).
- `cd go-mknoon` then `go test ./node -run TestKE004UpdateGroupKeySameEpochSameMaterialIsIdempotentAndKeepsEpoch3Delivery -count=1` PASS (`ok github.com/mknoon/go-mknoon/node 1.116s`).
- Existing duplicate selector preservation PASS: `flutter test --no-pub test/features/groups/application/group_key_update_listener_test.dart --plain-name 'duplicate same-generation key update with same material is idempotent'` (`+1`).
- Existing same-generation conflict preservation PASS: `flutter test --no-pub test/features/groups/application/group_key_update_listener_test.dart --plain-name 'conflicting same-generation key updates keep first accepted material'` (`+1`).
- Adjacent Go stale/conflict preservation PASS: `cd go-mknoon` then `go test ./node -run 'TestUpdateGroupKey_IgnoresSameEpochDifferentMaterial|TestGL015UpdateGroupKeyIgnoresSameEpochDifferentMaterialAndKeepsEpoch3Delivery|TestUpdateGroupKey_IgnoresOlderEpochAfterCurrent|TestGL014UpdateGroupKeyIgnoresOlderEpochAndKeepsCurrentEpochDelivery' -count=1` (`ok github.com/mknoon/go-mknoon/node 1.475s`).
- `dart analyze test/features/groups/application/group_key_update_listener_test.dart test/features/groups/integration/group_messaging_smoke_test.dart` exited `0` with only pre-existing info-level style findings in `group_key_update_listener_test.dart`.
- Scoped `git diff --check` PASS.
- `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` remains red only on existing non-KE-004 residuals; focused reruns confirmed `BB-007 accepted pending invite joins with exact full config and replays accepted epoch` still fails with `Expected: not null / Actual: <null>` at `test/features/groups/integration/invite_round_trip_test.dart:679`, and `GM-029 config version monotonicity converges across A/B/C shuffled delivery` still fails with `Expected: MemberRole.writer / Actual: MemberRole.reader` at `test/features/groups/integration/group_membership_smoke_test.dart:8144`.
- `./scripts/run_test_gates.sh completeness-check` remains red on the existing unrelated classification gap: `732/733 test files classified`; unmatched `test/shared/fakes/fake_group_pubsub_network_test.dart`.

Scope guard:

- No source worktree plan, source matrix, COMPLETE_1 docs, source `test-inventory.md`, criteria, runner, live harness, or production files were recreated or rewritten for KE-004.
- No adjacent KE-003, KE-005, key rotation, key repair, BB-007, GM-029, ML-012 external-fixture, UI, notification, media, relay, or broader key-safety work was imported.
