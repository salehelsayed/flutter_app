# INTEGRATE-KE-003 Integration Contract

Status: accepted

## Scope

Import and verify only source row `KE-003`: a stale lower-epoch `updateKey` delivered after a newer committed key must be stored, if useful, as historical material without downgrading the active validator key, and delivery must continue on the newer epoch.

This is standard integration mode. The historical source worktree remains the source of truth; this plan is only the minimal import/reconcile/verify contract for current main. Do not update or recreate the original worktree implementation plan.

## Source Evidence

- Source worktree: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline`
- Source plan: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-KE-003-plan.md`
- Historical accepted source proof included focused listener, Go node, fake-network, criteria, groups, completeness, diff hygiene, and iOS 26.2 `private_stale_lower_key_update` run `1778568037747`.
- Source row-owned files inspected: `test/features/groups/application/group_key_update_listener_test.dart`, `go-mknoon/node/pubsub_key_rotation_grace_test.go`, `test/features/groups/integration/group_messaging_smoke_test.dart`, `integration_test/scripts/group_multi_party_device_criteria.dart`, `test/integration/group_multi_party_device_criteria_test.dart`, `integration_test/scripts/run_group_multi_party_device_real.dart`, and `integration_test/group_multi_party_device_real_harness.dart`.

## Current Main Classification

- Already present: production lower-epoch rejection in `lib/features/groups/application/group_key_update_listener.dart` and `go-mknoon/node/pubsub.go`.
- Already present: equivalent listener regression `delayed older key update after newer generation does not promote active key` in `test/features/groups/application/group_key_update_listener_test.dart`.
- Already present: equivalent Go validator/delivery regressions `TestUpdateGroupKey_IgnoresOlderEpochAfterCurrent` and `TestGL014UpdateGroupKeyIgnoresOlderEpochAndKeepsCurrentEpochDelivery` in `go-mknoon/node/pubsub_key_rotation_grace_test.go`.
- Missing: KE-003 row-owned fake-network proof, criteria validator/fixtures, runner allow-list entry, and live harness scenario.

## Import Contract

- Preserve current production behavior; do not import production code for KE-003.
- Do not duplicate already-present listener or Go validator tests only to add row names. Treat those deltas as `skipped_already_present` with exact evidence and run their equivalent current selectors.
- Import only the missing row-owned fake-network, criteria, runner, and live harness artifacts for `private_stale_lower_key_update`.
- Do not import adjacent source-worktree KE-004, KE-005, KE-015, KE-016, RA-006, same-epoch conflict, partial-distribution, source matrix docs, source test-inventory docs, or unrelated stress rows.

## Verification Plan

- Run equivalent current listener and Go validator selectors for the already-present monotonic lower-epoch behavior.
- Run focused KE-003 fake-network selector.
- Run focused `private_stale_lower_key_update` criteria selector and full criteria regression.
- Run scoped analyzer, formatter, and diff hygiene.
- Run a fresh iOS 26.2 live proof for `private_stale_lower_key_update` and record exact device ids, run id, and shared directory.

## Execution Result

Final verdict: accepted.

Imported row-owned missing KE-003 proof artifacts only:

- `test/features/groups/integration/group_messaging_smoke_test.dart`: fake-network proof `KE-003 stale lower key update cannot downgrade fake-network delivery`.
- `integration_test/scripts/group_multi_party_device_criteria.dart`: `private_stale_lower_key_update` requirement, expected message, dispatch, and KE-003 verdict validator.
- `test/integration/group_multi_party_device_criteria_test.dart`: scenario requirement coverage plus accept/reject KE-003 verdict fixtures.
- `integration_test/scripts/run_group_multi_party_device_real.dart`: scenario allow-list and CLI usage entry.
- `integration_test/group_multi_party_device_real_harness.dart`: iOS 26.2 three-role `private_stale_lower_key_update` flow and verdict proof fields.

Skipped as already present:

- Production lower-epoch rejection/historical storage behavior in `lib/features/groups/application/group_key_update_listener.dart`.
- Production Go lower-or-equal epoch rejection in `go-mknoon/node/pubsub.go`.
- Equivalent listener regression `delayed older key update after newer generation does not promote active key` in `test/features/groups/application/group_key_update_listener_test.dart`.
- Equivalent Go regressions `TestUpdateGroupKey_IgnoresOlderEpochAfterCurrent` and `TestGL014UpdateGroupKeyIgnoresOlderEpochAndKeepsCurrentEpochDelivery` in `go-mknoon/node/pubsub_key_rotation_grace_test.go`.

Verification:

- `flutter test --no-pub test/features/groups/application/group_key_update_listener_test.dart --plain-name 'delayed older key update after newer generation does not promote active key'` PASS (`+1`).
- `cd go-mknoon` then `go test ./node -run 'TestUpdateGroupKey_IgnoresOlderEpochAfterCurrent|TestGL014UpdateGroupKeyIgnoresOlderEpochAndKeepsCurrentEpochDelivery' -count=1` PASS (`ok github.com/mknoon/go-mknoon/node 1.113s`).
- `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name 'KE-003'` PASS (`+1`).
- `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'private_stale_lower_key_update'` PASS (`+2`).
- `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart` PASS (`+273`).
- `dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario private_stale_lower_key_update --list-scenarios` PASS (`private_stale_lower_key_update` listed).
- `dart analyze integration_test/group_multi_party_device_real_harness.dart integration_test/scripts/run_group_multi_party_device_real.dart integration_test/scripts/group_multi_party_device_criteria.dart test/integration/group_multi_party_device_criteria_test.dart test/features/groups/integration/group_messaging_smoke_test.dart` PASS (`No issues found!`).
- `dart format --set-exit-if-changed integration_test/group_multi_party_device_real_harness.dart integration_test/scripts/run_group_multi_party_device_real.dart integration_test/scripts/group_multi_party_device_criteria.dart test/integration/group_multi_party_device_criteria_test.dart test/features/groups/integration/group_messaging_smoke_test.dart` PASS (`Formatted 5 files (0 changed)`).
- Scoped `git diff --check` PASS.
- Fresh iOS 26.2 live proof PASS: `MKNOON_RELAY_ADDRESSES='/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g' dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario private_stale_lower_key_update -d 5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3,279B82AE-2BB9-4924-9AAE-581870ED3FA9,116B4AF6-C1A9-4F36-B929-0A7130B5E83C`; run id `1779107305679`; shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_private_stale_lower_key_update_nUDQX2`; device ids Alice `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`, Bob `279B82AE-2BB9-4924-9AAE-581870ED3FA9`, Charlie `116B4AF6-C1A9-4F36-B929-0A7130B5E83C`; orchestrator detail `private_stale_lower_key_update verdicts valid for alice, bob, charlie`.
- `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` remains red only on existing non-KE-003 residuals confirmed by focused reruns: `BB-007 accepted pending invite joins with exact full config and replays accepted epoch` (`Expected: not null / Actual: <null>` at `test/features/groups/integration/invite_round_trip_test.dart:679`) and `GM-029 config version monotonicity converges across A/B/C shuffled delivery` (`Expected: MemberRole.writer / Actual: MemberRole.reader` at `test/features/groups/integration/group_membership_smoke_test.dart:8144`).
- `./scripts/run_test_gates.sh completeness-check` remains red on the existing unrelated classification gap: `732/733 test files classified`; unmatched `test/shared/fakes/fake_group_pubsub_network_test.dart`.

Scope guard:

- No source worktree plan, source matrix, COMPLETE_1 docs, or source `test-inventory.md` were recreated or rewritten.
- No adjacent KE-004+, KE-005, KE-015, KE-016, RA-006, conflict, rotation, partial distribution, BB-007, GM-029, or completeness-classification repair work was imported.
