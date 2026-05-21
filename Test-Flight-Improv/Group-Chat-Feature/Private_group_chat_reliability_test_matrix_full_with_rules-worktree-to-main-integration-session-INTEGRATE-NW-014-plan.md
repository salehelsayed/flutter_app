# INTEGRATE-NW-014 Plan - Minimal Standard Integration Contract

Status: accepted

Mode: standard worktree-to-main integration. This is import/reconcile/verify work for already-covered source row `NW-014`; it is not gap-closure mode and must not recreate or rewrite the historical source implementation plan.

## Planning Progress

| timestamp | role | files inspected since last update | decision/blocker | next action |
|---|---|---|---|---|
| 2026-05-20 | Evidence Collector completed | Current integration breakdown; historical source NW-014 plan and closure evidence; current dirty-state summary | Source `NW-014` is covered, current integration row `INTEGRATE-NW-014` is pending, and accepted dirty `NW-013` edits are present. | Use the historical source plan as source of truth and keep future execution scoped to row-owned import/reconcile/verify only. |
| 2026-05-20 | Planner completed | Historical proof evidence, current row-owned file list, proof requirements, exclusion list, verification command set | Contract is execution-safe for standard integration and records the live proof profile with current iOS 26.2 device ids. | Future executor may import only missing NW-014 deltas, preserve NW-012/NW-013 state, and report one allowed terminal status. |

## Real Scope

Own exactly integration row `INTEGRATE-NW-014`, sourced from historical row `NW-014`: "Flaky network chaos run maintains model invariants."

The row contract is: Alice, Bob, Charlie, and Dana run under random delays, drops, duplicates, and reconnects with a fixed seed; final model comparison proves every message is visible exactly to active entitled members and all peers eventually converge.

Historical source truth:

- Source worktree: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline`.
- Historical source plan: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-NW-014-plan.md`.
- Historical fake-network proof passed: `NW-014 deterministic network chaos run maintains model invariants`.
- Historical criteria proof passed: `flutter test test/integration/group_multi_party_device_criteria_test.dart --plain-name "NW-014"` (`+3`).
- Historical preservation proof passed: `flutter test test/integration/group_multi_party_device_criteria_test.dart --plain-name "RA-018 accepts private_readd_alternating_churn proof verdicts"` (`+1`).
- Historical scoped format/analyze/diff passed.
- Historical iOS 26.2 four-role live proof passed as run `1778701469795` on Alice `560D3E2D-78F8-4D28-A010-16B399581C99`, Bob `511B36DA-7113-41A7-A718-4450C87C0E62`, Charlie `DE36DBBE-64FC-4652-AAD9-17329A1BA245`, Dana `A369E083-CFED-40F7-8925-72A088575E38`.

## Closure Bar

`INTEGRATE-NW-014` is good enough when current main has the row-owned fake-network chaos selector, criteria validation, runner registration, live harness proof fields, and criteria tests reconciled from the covered source row; focused NW-014 host selectors pass; RA-018 criteria behavior is preserved; current iOS 26.2 four-role app-peer proof for `private_network_chaos_invariants` passes or is exactly fixture-blocked; broad groups/completeness residuals are classified as non-NW-014 when red.

Allowed terminal status options are exactly:

- `accepted`
- `skipped_already_present`
- `blocked_conflict`
- `blocked_external_fixture`

## Source Of Truth

- Controlling integration breakdown: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-breakdown.md`.
- Current integration row: `NW-014` / `INTEGRATE-NW-014`, source `covered`, current status `pending_integration`.
- Historical source plan and closure evidence are the source of truth for behavior, proof shape, and accepted row-owned deltas.
- Current main wins over stale source implementation details when reconciling with accepted `NW-012` harness/criteria/runner support and accepted dirty `NW-013` selector/import changes.

## Write Scope For Future Execution

Future execution under this contract may import, reconcile, or verify only these row-owned current files when needed:

- `test/features/groups/integration/group_messaging_smoke_test.dart`
- `integration_test/group_multi_party_device_real_harness.dart`
- `integration_test/scripts/run_group_multi_party_device_real.dart`
- `integration_test/scripts/group_multi_party_device_criteria.dart`
- `test/integration/group_multi_party_device_criteria_test.dart`

This planning task writes only this contract file. Future execution must not overwrite unrelated dirty edits and must preserve accepted `NW-012` harness/criteria/runner support plus accepted dirty `NW-013` selector/import changes.

## Explicit Exclusions

Do not import, rewrite, or edit:

- `ST-001`, `ST-013`, or `ST-014` proof fields/tests: `st001ModelOracleProof`, `st013RelayChaosProof`, `st014SoakProof`.
- Source matrix docs, source session breakdowns, source worktree docs, `COMPLETE_1` docs, ledgers, inventories, or non-row closure docs during execution from this contract unless a later closure instruction explicitly authorizes doc closure.
- Production code, migrations, Go/native code, UI, notifications, media, privacy, relay shared-state architecture, Android, physical iOS, macOS app-peer roles, or `NW-015+`.

## Device/Relay Proof Profile

Profile: iOS 26.2 four-role app-peer proof.

Required live scenario: `private_network_chaos_invariants`.

The fake-network host selector owns random delay, drop, duplicate, reconnect replay, fixed-seed model comparison, and active-entitled-exactly-once chaos behavior. The live app-peer proof is only the churn/convergence subset and must not claim artificial random delay/drop/duplicate coverage.

Current required iOS 26.2 simulator ids:

- Alice: `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`
- Bob: `279B82AE-2BB9-4924-9AAE-581870ED3FA9`
- Charlie: `116B4AF6-C1A9-4F36-B929-0A7130B5E83C`
- Dana: `CD5929A6-EA0A-421D-A6D3-55BD707E0F76`

Preflight must verify availability with `flutter devices --machine` and `xcrun simctl list devices available`. If any required simulator is unavailable, classify as `blocked_external_fixture` and do not substitute another platform or device family.

## Implementation Contract

1. Start with `git status --short` and treat the existing dirty `NW-013` state as accepted context, not as work to revert.
2. Compare current main against the historical source row only for the five row-owned files listed above.
3. If all NW-014 behavior and proof surfaces are already present, verify and classify as `skipped_already_present`.
4. If import is needed, reconcile only missing row-owned deltas:
   - deterministic fake-network selector `NW-014 deterministic network chaos run maintains model invariants`;
   - `private_network_chaos_invariants` runner registration and harness proof fields;
   - criteria validation for `nw014ChaosInvariantProof`, row id `NW-014`, iOS 26.2 app-peer platform, fixed seed `14014`, active-entitled-exactly-once invariant, fake-network chaos proof requirement, four roles, no removed-window plaintext, no visible duplicates, and final convergence;
   - focused criteria acceptance/rejection tests and RA-018 preservation.
5. Do not weaken existing NW-012 or NW-013 selectors, imports, runner support, criteria logic, or harness behavior.
6. Stop on any non-row conflict that would require production, migration, source-doc, or later-row edits; classify it as `blocked_conflict`.

## Verification Commands

Focused row proof:

```bash
flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name "NW-014 deterministic network chaos run maintains model invariants"
flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name "NW-014"
flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name "RA-018 accepts private_readd_alternating_churn proof verdicts"
dart run integration_test/scripts/run_group_multi_party_device_real.dart --list-scenarios | rg "private_network_chaos_invariants"
```

Scoped maintenance:

```bash
dart format --set-exit-if-changed test/features/groups/integration/group_messaging_smoke_test.dart integration_test/group_multi_party_device_real_harness.dart integration_test/scripts/run_group_multi_party_device_real.dart integration_test/scripts/group_multi_party_device_criteria.dart test/integration/group_multi_party_device_criteria_test.dart
flutter analyze test/features/groups/integration/group_messaging_smoke_test.dart integration_test/group_multi_party_device_real_harness.dart integration_test/scripts/run_group_multi_party_device_real.dart integration_test/scripts/group_multi_party_device_criteria.dart test/integration/group_multi_party_device_criteria_test.dart
git diff --check -- test/features/groups/integration/group_messaging_smoke_test.dart integration_test/group_multi_party_device_real_harness.dart integration_test/scripts/run_group_multi_party_device_real.dart integration_test/scripts/group_multi_party_device_criteria.dart test/integration/group_multi_party_device_criteria_test.dart Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-INTEGRATE-NW-014-plan.md
```

Broad residual classification:

```bash
FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups
./scripts/run_test_gates.sh completeness-check
```

If broad gates remain red, acceptance requires exact classification that failures are pre-existing or non-NW-014 residuals, not caused by this row.

Live iOS 26.2 proof template:

```bash
flutter devices --machine
xcrun simctl list devices available
MKNOON_RELAY_ADDRESSES='/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g' dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario private_network_chaos_invariants -d 5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3,279B82AE-2BB9-4924-9AAE-581870ED3FA9,116B4AF6-C1A9-4F36-B929-0A7130B5E83C,CD5929A6-EA0A-421D-A6D3-55BD707E0F76
```

## Execution Evidence

Executor run date: 2026-05-20.

Imported missing row-owned NW-014 deltas only:

- Added deterministic fake-network selector `NW-014 deterministic network chaos run maintains model invariants`.
- Added `private_network_chaos_invariants` runner registration, scenario listing, and help text.
- Added live harness support that emits only `nw014ChaosInvariantProof` for `private_network_chaos_invariants`.
- Added criteria validation for `nw014ChaosInvariantProof` only.
- Added focused NW-014 criteria acceptance/rejection tests and preserved RA-018 criteria behavior.

Explicitly excluded ST proof surfaces: `st001ModelOracleProof`, `st013RelayChaosProof`, and `st014SoakProof` were not imported.

Focused and scoped verification:

- `dart format --set-exit-if-changed test/features/groups/integration/group_messaging_smoke_test.dart integration_test/group_multi_party_device_real_harness.dart integration_test/scripts/run_group_multi_party_device_real.dart integration_test/scripts/group_multi_party_device_criteria.dart test/integration/group_multi_party_device_criteria_test.dart` passed after formatting one criteria file, then rerun clean.
- `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name "NW-014 deterministic network chaos run maintains model invariants"` passed (`+1`).
- `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name "NW-014"` passed (`+3`).
- `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name "RA-018 accepts private_readd_alternating_churn proof verdicts"` passed (`+1`).
- `dart run integration_test/scripts/run_group_multi_party_device_real.dart --list-scenarios | rg '^private_network_chaos_invariants$'` passed.
- `flutter analyze test/features/groups/integration/group_messaging_smoke_test.dart integration_test/group_multi_party_device_real_harness.dart integration_test/scripts/run_group_multi_party_device_real.dart integration_test/scripts/group_multi_party_device_criteria.dart test/integration/group_multi_party_device_criteria_test.dart` passed with no issues.
- `git diff --check --` over the five row-owned Dart files and this plan passed before and after plan evidence update.

Live proof preflight:

- `flutter devices --machine` and `xcrun simctl list devices available` found the required iOS 26.2 simulators:
  - Alice `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`
  - Bob `279B82AE-2BB9-4924-9AAE-581870ED3FA9`
  - Charlie `116B4AF6-C1A9-4F36-B929-0A7130B5E83C`
  - Dana `CD5929A6-EA0A-421D-A6D3-55BD707E0F76`
- No stale `run_group_multi_party_device_real` process was present by `ps aux | rg '[r]un_group_multi_party_device_real'`.
- No ambient `MKNOON_` environment variables were present.

Live proof attempt:

- Command: `MKNOON_RELAY_ADDRESSES=... dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario private_network_chaos_invariants -d 5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3,279B82AE-2BB9-4924-9AAE-581870ED3FA9,116B4AF6-C1A9-4F36-B929-0A7130B5E83C,CD5929A6-EA0A-421D-A6D3-55BD707E0F76`
- Run id: `1779289126608`.
- Shared path: `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_private_network_chaos_invariants_AJx7Lo`.
- Result: failed before verdict with external live-fixture symptoms. Bob timed out in existing RA-018 key-epoch wait path (`_waitForKeyEpoch` inside `_runRa018Bob`) and exited without writing a verdict; Dana timed out waiting for `gmp_1779289126608_alice_sent_ra018Cycle3_charlieRemoved_alice.json` after repeated group discovery dial failures (`context deadline exceeded`, relay fallback failures, and dial backoff). This is classified as `blocked_external_fixture`, not an NW-014 import conflict.

Broad residual classification:

- `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` failed (`+246 -9`). Exact non-NW-014 failure rows:
  - `BB-007 accepted pending invite joins with exact full config and replays accepted epoch`
  - `IR-003 timestamp replay boundary drains same-ms fake-network messages once`
  - `BB-012 restart recovery drains replay before ack and stays live`
  - `NW-004 reconnect recovery stays live after ack across multiple groups`
  - `IR-018 restart recovery keeps recovering state until replay drains and live stays active`
  - `GE-017 seeded random membership operations preserve invariants`
  - `GE-019 seeded random key rotations preserve access windows`
  - `GE-020 long soak private group with churn preserves convergence`
  - `GM-029 config version monotonicity converges across A/B/C shuffled delivery`
- These failures do not include the NW-014 selector or NW-014 criteria tests and are classified as non-NW-014 residuals.
- `./scripts/run_test_gates.sh completeness-check` failed: `734/735 test files classified`; unmatched file `test/shared/fakes/fake_group_pubsub_network_test.dart`. This is unrelated to NW-014 import ownership.

Live fixture recovery 2026-05-21:

- Recovery scope: focused shared `private_network_chaos_invariants` blocker recovery for `INTEGRATE-NW-014` and `INTEGRATE-ST-001` only; no code, test, harness, criteria, runner, production, or source-matrix changes were made.
- Preflight: `git status --short` showed only unrelated `info.plist`; no stale `run_group_multi_party_device_real`, Flutter test/drive, Xcode, or simctl launch/proof processes matched; ambient `MKNOON_RELAY_ADDRESSES` was unset; `flutter devices --machine` and `xcrun simctl list devices available` showed all four required iOS 26.2 CoreSimulator devices booted/available; scenario discovery listed `private_network_chaos_invariants`.
- Command: `MKNOON_RELAY_ADDRESSES='/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g' dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario private_network_chaos_invariants -d 5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3,279B82AE-2BB9-4924-9AAE-581870ED3FA9,116B4AF6-C1A9-4F36-B929-0A7130B5E83C,CD5929A6-EA0A-421D-A6D3-55BD707E0F76`.
- Run id: `1779390864533`.
- Shared dir: `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_private_network_chaos_invariants_CI0XjH`.
- Devices: Alice `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`, Bob `279B82AE-2BB9-4924-9AAE-581870ED3FA9`, Charlie `116B4AF6-C1A9-4F36-B929-0A7130B5E83C`, Dana `CD5929A6-EA0A-421D-A6D3-55BD707E0F76`.
- Orchestrator verdict: `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_private_network_chaos_invariants_CI0XjH/gmp_1779390864533_private_network_chaos_invariants_orchestrator_verdict.json`, `ok=true`, detail `private_network_chaos_invariants verdicts valid for alice, bob, charlie, dana`.
- Role verdicts: Alice/Bob/Charlie/Dana verdict files exist and each includes `nw014ChaosInvariantProof` and `st001ModelOracleProof`; `nw014ChaosInvariantProof.rowId` is `NW-014`, `appPeerPlatform` is `ios_26_2_core_simulator`, `fixedSeed` is `14014`, `modelInvariant` is `active_entitled_exactly_once`, `fakeNetworkChaosProofRequired` is `true`, `messageOperationCount` and `membershipOperationCount` are `12`, `churnCycles` is `3`, `churnTargets` are Charlie/Dana, removed-window plaintext counts are `0`, `duplicateVisibleMessageCount` is `0`, `inactiveSenderAttemptCount` is `0`, `finalEpoch` is `13`, and final member-list/epoch convergence are `true`.
- Focused checks after rerun: `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name "NW-014 deterministic network chaos run maintains model invariants"` passed (`+1`); `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name "NW-014"` passed (`+3`); `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name "ST-001"` passed (`+1`); `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name "ST-001"` passed (`+3`); `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name "RA-018 accepts private_readd_alternating_churn proof verdicts"` passed (`+1`).
- Earlier failed run `1779289126608` remains preserved as historical blocker evidence, but the current required `private_network_chaos_invariants` proof is recovered and accepted.

Terminal status: `accepted`.

Closure note 2026-05-21: breakdown ledger and `test-inventory.md` were updated to reclassify `INTEGRATE-NW-014` from `blocked_external_fixture` to `accepted` after live fixture recovery. No code, tests, harnesses, scripts, production files, source matrix docs, COMPLETE_1 docs, or source worktree files were edited during this recovery closure. Unrelated `info.plist` remained unstaged and untouched.

## Final Verdict Guidance

- Use `accepted` only when focused row proof, scoped maintenance, scenario discovery, residual classification, and required live proof all satisfy the closure bar.
- Use `skipped_already_present` only when current main already has the row-owned behavior and the same verification commands pass or are exactly classified.
- Use `blocked_conflict` for in-repo conflicts that cannot be resolved inside the five row-owned files without touching excluded surfaces.
- Use `blocked_external_fixture` for unavailable iOS 26.2 simulators, relay/device-lab failure, or live-proof fixture failure after host proof is otherwise green.
