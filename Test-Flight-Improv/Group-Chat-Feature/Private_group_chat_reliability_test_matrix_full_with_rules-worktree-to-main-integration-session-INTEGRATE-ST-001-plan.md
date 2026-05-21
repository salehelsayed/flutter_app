# INTEGRATE-ST-001 Recipient Oracle Integration Contract

Status: accepted

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
Required iOS 26.2 live proof was attempted on the current main checkout during the original ST-001 integration pass and failed before writing an orchestrator verdict. That failed run remains preserved as historical blocker evidence:

- Command: `MKNOON_RELAY_ADDRESSES=/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario private_network_chaos_invariants -d 5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3,279B82AE-2BB9-4924-9AAE-581870ED3FA9,116B4AF6-C1A9-4F36-B929-0A7130B5E83C,CD5929A6-EA0A-421D-A6D3-55BD707E0F76`
- Run id: `1779353772571`
- Shared dir: `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_private_network_chaos_invariants_CyPstO`
- Devices: Alice `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`, Bob `279B82AE-2BB9-4924-9AAE-581870ED3FA9`, Charlie `116B4AF6-C1A9-4F36-B929-0A7130B5E83C`, Dana `CD5929A6-EA0A-421D-A6D3-55BD707E0F76`.
- Failure: Bob exited before writing a verdict; Alice timed out waiting for `gmp_1779353772571_bob_ra018_charlie_removed_key_c3`; Charlie and Dana timed out waiting for `gmp_1779353772571_alice_sent_ra018Cycle3_charlieRemoved_alice.json`.

Live fixture recovery 2026-05-21:

- Recovery scope: focused shared `private_network_chaos_invariants` blocker recovery for `INTEGRATE-NW-014` and `INTEGRATE-ST-001` only; no code, test, harness, criteria, runner, production, or source-matrix changes were made.
- Preflight: `git status --short` showed only unrelated `info.plist`; no stale `run_group_multi_party_device_real`, Flutter test/drive, Xcode, or simctl launch/proof processes matched; ambient `MKNOON_RELAY_ADDRESSES` was unset; `flutter devices --machine` and `xcrun simctl list devices available` showed all four required iOS 26.2 CoreSimulator devices booted/available; scenario discovery listed `private_network_chaos_invariants`.
- Command: `MKNOON_RELAY_ADDRESSES='/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g' dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario private_network_chaos_invariants -d 5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3,279B82AE-2BB9-4924-9AAE-581870ED3FA9,116B4AF6-C1A9-4F36-B929-0A7130B5E83C,CD5929A6-EA0A-421D-A6D3-55BD707E0F76`.
- Run id: `1779390864533`.
- Shared dir: `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_private_network_chaos_invariants_CI0XjH`.
- Devices: Alice `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`, Bob `279B82AE-2BB9-4924-9AAE-581870ED3FA9`, Charlie `116B4AF6-C1A9-4F36-B929-0A7130B5E83C`, Dana `CD5929A6-EA0A-421D-A6D3-55BD707E0F76`.
- Orchestrator verdict: `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_private_network_chaos_invariants_CI0XjH/gmp_1779390864533_private_network_chaos_invariants_orchestrator_verdict.json`, `ok=true`, detail `private_network_chaos_invariants verdicts valid for alice, bob, charlie, dana`.
- Role verdicts: Alice/Bob/Charlie/Dana verdict files exist and each includes `st001ModelOracleProof` and `nw014ChaosInvariantProof`; `st001ModelOracleProof.rowId` is `ST-001`, `appPeerPlatform` is `ios_26_2_core_simulator`, `fixedSeed` is `14014`, `modelInvariant` is `active_recipient_set_exactly_once`, `oracleProofSource` is `app_peer_core_simulator_model_oracle`, `messageOperationCount` and `membershipOperationCount` are `12`, `oracleMessageCount` is `12`, `churnCycles` is `3`, `churnTargets` are Charlie/Dana, duplicate/restart/replay coverage are `true`, removed-window plaintext counts are `0`, `duplicateVisibleMessageCount` is `0`, `inactiveSenderAttemptCount` is `0`, `finalEpoch` is `13`, and final member-list/epoch convergence are `true`.
- Focused checks after rerun: `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name "ST-001"` passed (`+1`); `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name "ST-001"` passed (`+3`); `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name "NW-014 deterministic network chaos run maintains model invariants"` passed (`+1`); `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name "NW-014"` passed (`+3`); `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name "RA-018 accepts private_readd_alternating_churn proof verdicts"` passed (`+1`).

## Closure Verdict
Accepted for `INTEGRATE-ST-001`. Row-owned host and criteria proof artifacts are imported and focused checks pass. The shared `private_network_chaos_invariants` iOS 26.2 proof recovered on run `1779390864533`, and all Alice/Bob/Charlie/Dana role verdicts contain valid `st001ModelOracleProof` plus preserved `nw014ChaosInvariantProof`. The breakdown ledger and `test-inventory.md` were updated to reclassify `INTEGRATE-ST-001` from `blocked_external_fixture` to `accepted`. Unrelated `info.plist` remained unstaged and untouched.
