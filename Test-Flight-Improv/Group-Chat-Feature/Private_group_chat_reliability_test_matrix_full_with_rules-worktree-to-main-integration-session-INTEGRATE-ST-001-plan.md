# INTEGRATE-ST-001 Recipient Oracle Integration Contract

Status: blocked_external_fixture

## Source Of Truth
- Source row: `ST-001` / "Model-based membership state machine verifies every message recipient set".
- Historical source plan: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-ST-001-plan.md`.
- Source closure status: accepted/covered with focused host proof and iOS 26.2 `private_network_chaos_invariants` proof in the source worktree.

## Integration Scope
Import only the missing row-owned recipient-oracle proof artifacts:

- `test/features/groups/integration/group_messaging_smoke_test.dart`
- `integration_test/group_multi_party_device_real_harness.dart`
- `integration_test/scripts/group_multi_party_device_criteria.dart`
- `test/integration/group_multi_party_device_criteria_test.dart`

Out of scope: ST-002+ stress rows, NW-014 chaos invariant semantics beyond preserving the existing proof, unrelated fixture repairs, source matrix rewrites, COMPLETE_1 docs, source worktree docs, Android, physical iOS, and any broad live-fixture reimplementation.

## Imported Delta
- `group_messaging_smoke_test.dart` adds `ST-001 model-based membership oracle matches delivered and replayed recipient sets`, a deterministic Alice/Bob/Charlie/Dana recipient-oracle fake-network proof over active membership intervals, remove/re-add churn, duplicates, restart replay, and held replay.
- `group_multi_party_device_real_harness.dart` emits `st001ModelOracleProof` on `private_network_chaos_invariants` verdicts with fixed seed, operation counts, exact active-recipient oracle evidence, duplicate/restart/replay coverage, zero leakage, zero duplicate visibility, and final convergence.
- `group_multi_party_device_criteria.dart` validates `st001ModelOracleProof` in addition to the existing `nw014ChaosInvariantProof` for `private_network_chaos_invariants`.
- `group_multi_party_device_criteria_test.dart` adds ST-001 accept/missing/weak-proof criteria cases.

## Verification
- `dart format --set-exit-if-changed test/features/groups/integration/group_messaging_smoke_test.dart integration_test/group_multi_party_device_real_harness.dart integration_test/scripts/group_multi_party_device_criteria.dart test/integration/group_multi_party_device_criteria_test.dart`
- `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name "ST-001"` (`+1`)
- `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name "ST-001"` (`+3`)
- `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name "NW-014"` (`+3`)
- `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name "NW-014"` (`+1`)
- `flutter analyze --no-pub test/features/groups/integration/group_messaging_smoke_test.dart integration_test/group_multi_party_device_real_harness.dart integration_test/scripts/group_multi_party_device_criteria.dart test/integration/group_multi_party_device_criteria_test.dart` (`No issues found!`)
- `git diff --check`

## Device Proof
Required iOS 26.2 live proof was attempted on the current main checkout and failed before writing an orchestrator verdict, so ST-001 is terminally classified as `blocked_external_fixture`.

- Command: `MKNOON_RELAY_ADDRESSES=/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario private_network_chaos_invariants -d 5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3,279B82AE-2BB9-4924-9AAE-581870ED3FA9,116B4AF6-C1A9-4F36-B929-0A7130B5E83C,CD5929A6-EA0A-421D-A6D3-55BD707E0F76`
- Run id: `1779353772571`
- Shared dir: `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_private_network_chaos_invariants_CyPstO`
- Devices: Alice `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`, Bob `279B82AE-2BB9-4924-9AAE-581870ED3FA9`, Charlie `116B4AF6-C1A9-4F36-B929-0A7130B5E83C`, Dana `CD5929A6-EA0A-421D-A6D3-55BD707E0F76`.
- Failure: Bob exited before writing a verdict; Alice timed out waiting for `gmp_1779353772571_bob_ra018_charlie_removed_key_c3`; Charlie and Dana timed out waiting for `gmp_1779353772571_alice_sent_ra018Cycle3_charlieRemoved_alice.json`.

## Closure Verdict
Blocked external fixture for `INTEGRATE-ST-001`. Row-owned host and criteria proof artifacts are imported and focused checks pass, but the required current-main iOS 26.2 `private_network_chaos_invariants` proof failed in the shared RA-018/NW-014 live fixture before ST-001 verdict validation. The blocker is recorded so later host-only stress rows can proceed only after dirty-state safety and dependency independence checks. Unrelated `info.plist` remained unstaged and untouched.
