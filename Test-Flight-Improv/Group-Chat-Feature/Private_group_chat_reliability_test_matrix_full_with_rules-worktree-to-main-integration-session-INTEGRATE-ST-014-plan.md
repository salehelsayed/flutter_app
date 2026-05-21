# INTEGRATE-ST-014 Worktree-To-Main Integration Contract

Status: execution-ready

Current session: `INTEGRATE-ST-014`
Source row: `ST-014` / "Long soak test with membership churn and periodic restarts"
Mode: standard integration, not gap closure
Writable artifact for this planning session: this file only

## Planning Progress

- 2026-05-21 16:58 CEST - Arbiter completed. Files inspected since last update: draft contract and reviewer findings. Decision/blocker: no structural blocker remains; contract is execution-ready. Next action: future executor may implement only this contract.
- 2026-05-21 16:58 CEST - Reviewer completed. Files inspected since last update: source/main changed-file inventory, ST-013 repair evidence, device proof profile. Decision/blocker: sufficient with explicit merge-only and live-proof guards. Next action: arbiter pass.
- 2026-05-21 16:58 CEST - Reviewer started. Files inspected since last update: draft plan sections. Decision/blocker: verify no scope drift into ST-015, source docs, COMPLETE_1 docs, or ledger edits. Next action: sufficiency review.
- 2026-05-21 16:58 CEST - Planner completed. Files inspected since last update: source ST-014 plan/matrix/test-inventory, current integration breakdown, current/source candidate files, `simctl` device list. Decision/blocker: current main lacks ST-014 proof surfaces; source deltas must be merged into current main, not copied wholesale. Next action: reviewer pass.
- 2026-05-21 16:58 CEST - Evidence Collector completed. Files inspected since last update: `group_messaging_smoke_test.dart`, `group_multi_party_device_real_harness.dart`, `group_multi_party_device_criteria.dart`, `group_multi_party_device_criteria_test.dart`, `run_group_multi_party_device_real.dart`, `test-inventory.md`, integration breakdown, source ST-014 plan, source matrix row, and current `git status`. Decision/blocker: no blocker; only unrelated `info.plist` is dirty besides this plan. Next action: planner pass.

## Execution Progress

- 2026-05-21 17:01 CEST - Contract extracted. Files inspected since last update: this ST-014 plan and `$implementation-execution-qa-orchestrator` skill contract. Decision/blocker: nested Executor/QA spawn tooling is unavailable in this session, so execution proceeds under the skill's local sequential fallback with separate Executor and QA phases. Next action: record dirty-state safety check before code edits.
- 2026-05-21 17:01 CEST - Dirty-state safety check recorded before code edits. Files inspected since last update: `git status --short`. Command: `git status --short`. Result: ` M info.plist`; `?? Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-INTEGRATE-ST-014-plan.md`. Decision/blocker: only the pre-existing unrelated `info.plist` and this plan are dirty; leave `info.plist` untouched. Next action: inspect source/current ST-014 files side by side.
- 2026-05-21 17:02 CEST - Side-by-side overlap inspection completed. Files inspected since last update: current/source `group_messaging_smoke_test.dart`, `group_multi_party_device_real_harness.dart`, `group_multi_party_device_criteria.dart`, `group_multi_party_device_criteria_test.dart`, and `run_group_multi_party_device_real.dart`. Decision/blocker: current main has RA-018/NW-014/ST-001/ST-013 `private_network_chaos_invariants` support and the `f9a31437` `_rotateRa018Key` real ack path, but lacks `ST-014` selectors, `st014SoakProof` validation, and 90-minute identity wait constants. Source runner is older/narrower, so only timeout constants/usages may be merged. Next action: patch only missing ST-014 fragments in allowed files.
- 2026-05-21 17:07 CEST - Executor patch completed. Files touched since last update: `test/features/groups/integration/group_messaging_smoke_test.dart`, `integration_test/group_multi_party_device_real_harness.dart`, `integration_test/scripts/group_multi_party_device_criteria.dart`, `test/integration/group_multi_party_device_criteria_test.dart`, `integration_test/scripts/run_group_multi_party_device_real.dart`. Decision/blocker: merged ST-014 fake-network selector, `st014SoakProof` live emission/criteria validation, criteria fixtures/tests, and minimal 90-minute identity wait support; preserved `_rotateRa018Key` as `return stack.p2pService.sendMessage(peerId, message)`. Next action: format and run focused ST-014 gates.
- 2026-05-21 17:08 CEST - Focused and preservation host gates completed. Files tested since last update: `test/features/groups/integration/group_messaging_smoke_test.dart`, `test/integration/group_multi_party_device_criteria_test.dart`. Commands/results: `dart format ...` -> `Formatted 5 files (0 changed)`; `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name "ST-014"` -> passed 1 test; `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name "ST-014"` -> passed 3 tests; `--plain-name "RA-018"` -> passed 8 tests; `--plain-name "NW-014"` -> passed 3 tests; `--plain-name "ST-001"` -> passed 3 tests; `--plain-name "ST-013"` -> passed 3 tests. Decision/blocker: no host/criteria blocker. Next action: run required format/analyze/diff hygiene gates.
- 2026-05-21 17:10 CEST - Hygiene and live-proof preflight completed. Files inspected since last update: touched Dart files, `git status --short`, process list, `simctl` device list. Commands/results: `dart format --set-exit-if-changed ...` -> passed with `Formatted 5 files (0 changed)`; `flutter analyze --no-pub ...` -> `No issues found!`; `git diff --check` -> passed; `git status --short` -> row-owned files plus pre-existing ` M info.plist`; stale process scan found no active `flutter test`, `flutter drive`, runner, `xcodebuild`, or `simctl launch` beyond the scan command; all four required iOS 26.2 devices are booted. Decision/blocker: live proof can start. Next action: run exact Alice/Bob/Charlie/Dana `private_network_chaos_invariants` proof.
- 2026-05-21 17:19 CEST - Exact iOS 26.2 live proof passed. Command: `MKNOON_RELAY_ADDRESSES='/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g' dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario private_network_chaos_invariants --device 5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3,279B82AE-2BB9-4924-9AAE-581870ED3FA9,116B4AF6-C1A9-4F36-B929-0A7130B5E83C,CD5929A6-EA0A-421D-A6D3-55BD707E0F76`. Result: orchestrator verdict `ok=true`, detail `private_network_chaos_invariants verdicts valid for alice, bob, charlie, dana`. Run id: `1779376259089`. Shared dir: `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_private_network_chaos_invariants_lhUqoc`. Verdict files: `gmp_1779376259089_alice_verdict.json`, `gmp_1779376259089_bob_verdict.json`, `gmp_1779376259089_charlie_verdict.json`, `gmp_1779376259089_dana_verdict.json`, `gmp_1779376259089_private_network_chaos_invariants_orchestrator_verdict.json`. Decision/blocker: no live-proof blocker. Next action: inspect verdict JSON proof fields and run final QA scope check.
- 2026-05-21 17:20 CEST - Live verdict JSON inspection completed. Files inspected since last update: all four role verdict JSONs and orchestrator verdict JSON in the shared dir. Result: every role has `runId=1779376259089`, `scenario=private_network_chaos_invariants`, `keyEpoch=13`, four members, four active members, preserved `nw014ChaosInvariantProof`, `st001ModelOracleProof`, `st013RelayChaosProof`, and new `st014SoakProof`. ST-014 proof summary per role: `rowId=ST-014`, `appPeerPlatform=ios_26_2_core_simulator`, `soakProofSource=app_peer_core_simulator_bounded_churn_soak_subset`, `fixedSeed=14014`, `modelComparisonCheckpoints=12`, `messageOperationCount=12`, `membershipOperationCount=12`, `churnCycles=3`, `finalEpoch=13`, `finalEpochConverged=true`, `finalMemberListConverged=true`, `receiveDeadPeerCount=0`, `duplicateVisibleMessageCount=0`, `inactiveSenderAttemptCount=0`. Decision/blocker: ST-014 proof contract is satisfied. Next action: final QA review and verdict.
- 2026-05-21 17:21 CEST - Final QA review completed under local sequential fallback. Files inspected since last update: `git diff --name-only`, `git diff --stat`, ST-014/proof symbol search, final `git status --short`. Result: changed files are limited to the five row-owned Dart files plus this plan, with pre-existing unrelated ` M info.plist` still unstaged and untouched. No integration breakdown ledger, test-inventory, source matrix, source breakdown, COMPLETE_1 docs, or ST-015 files were edited. Decision/blocker: accepted; do not stage or commit. Next action: hand off for closure-owned ledger/test-inventory update.

## real scope

Import or reconcile only the missing row-owned ST-014 deltas from `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline` into current main at `/Users/I560101/Project-Sat/mknoon-2/flutter_app`.

The row-owned delta is:

- deterministic bounded fake-network ST-014 soak selector;
- `st014SoakProof` emission for `private_network_chaos_invariants`;
- `st014SoakProof` criteria validation and focused criteria tests;
- runner timeout support only if still missing and only as a minimal merge into current main;
- test-inventory and integration ledger updates only after implementation evidence passes.

Do not recreate or rewrite the original source implementation plan. Do not import source matrix, source breakdown, COMPLETE_1 docs, or broad source-worktree file versions. Do not touch `info.plist`.

## closure bar

ST-014 is acceptable in main only when current main contains the missing ST-014 proof surfaces, all focused host/criteria/preservation gates pass, and a fresh exact iOS 26.2 Alice/Bob/Charlie/Dana `private_network_chaos_invariants` app-peer proof passes with all four role verdicts and an orchestrator verdict that includes valid `st014SoakProof` plus preserved `nw014ChaosInvariantProof`, `st001ModelOracleProof`, and `st013RelayChaosProof`.

If host/criteria gates pass but the required live proof fails before ST-014 verdict for simulator/relay fixture reasons, do not mark accepted or covered. Record/block as external fixture evidence in the future ledger update, preserving the failed run details.

## source of truth

Authoritative sources, in order:

1. Current main code and tests at commit `f9a31437` (`new-background`) win over stale source-worktree code.
2. Current integration breakdown: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-breakdown.md`.
3. Source ST-014 plan: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-ST-014-plan.md`.
4. Source matrix row and source `test-inventory.md` ST-014 entries.
5. Direct focused tests and the exact live proof run produced by the future integration execution.

Source evidence says ST-014 closed after harness stabilization in source commit `c84021b4`, with live run `1778945272086` on Alice `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`, Bob `279B82AE-2BB9-4924-9AAE-581870ED3FA9`, Charlie `116B4AF6-C1A9-4F36-B929-0A7130B5E83C`, and Dana `CD5929A6-EA0A-421D-A6D3-55BD707E0F76`.

Main evidence says current main already has the ST-013 repair in `f9a31437`: `_rotateRa018Key` returns the real `stack.p2pService.sendMessage(peerId, message)` ack. Preserve that behavior.

## session classification

`implementation-ready`

The gap is evidence-backed and narrow: current main has RA-018/NW-014/ST-001/ST-013 `private_network_chaos_invariants` support but does not yet contain `ST-014`, `st014SoakProof`, or the ST-014 criteria tests.

## exact problem statement

Main has not yet integrated the ST-014 bounded long-soak proof from the source worktree. Without this integration, current main can exercise the shared `private_network_chaos_invariants` path for RA-018/NW-014/ST-001/ST-013, but it cannot prove that repeated membership churn plus restart-style replay keeps all active peers receive-live and detects model divergence for ST-014.

What must improve: current main must gain row-owned ST-014 host, criteria, harness, and live proof validation.

What must stay unchanged: RA-018 alternating churn semantics, NW-014 chaos invariant validation, ST-001 model oracle validation, ST-013 relay chaos validation, and the ST-013 P2P ack repair from `f9a31437`.

## Main/overlap inspection requirements

Before editing, inspect current main and source side by side with targeted `rg`/diff, then merge only missing ST-014 fragments.

Required overlap checks:

- Confirm current main already has `nw014ChaosInvariantProof`, `st001ModelOracleProof`, and `st013RelayChaosProof`.
- Confirm current main lacks `st014SoakProof` before importing it. If it is already present and equivalent, skip the code delta and run proof gates only.
- Confirm `_rotateRa018Key` still propagates the real P2P send ack. Do not replace it with source code that weakens this.
- Confirm current `run_group_multi_party_device_real.dart` has a richer current-main scenario set than the source worktree. Do not overwrite it with the older source runner.
- If importing the 90-minute identity wait, merge only constants/usages needed for identity waiting; do not add source-only imports such as `group_multi_party_device_discovery.dart` unless current main already owns that dependency.

## files and repos to inspect next

Changed-file inventory to inspect/merge:

- `test/features/groups/integration/group_messaging_smoke_test.dart`: import only `ST-014 bounded soak with churn and periodic restart replays catches divergence`; preserve existing RA-018/NW-014/ST-015 and current-main imports/helpers.
- `integration_test/group_multi_party_device_real_harness.dart`: add `_st014SoakProof` and include it in Alice/Bob/Charlie/Dana `private_network_chaos_invariants` verdicts; preserve current-main `_rotateRa018Key`, health checks, inbox draining, and all later scenario support.
- `integration_test/scripts/group_multi_party_device_criteria.dart`: add `_validateSt014SoakProof` and call it after ST-013 validation for `private_network_chaos_invariants`; preserve NW-014/ST-001/ST-013 validators.
- `test/integration/group_multi_party_device_criteria_test.dart`: add focused ST-014 accept/missing/weak tests plus `st014SoakProof` fixture/helper changes; preserve RA-018/NW-014/ST-001/ST-013 tests.
- `integration_test/scripts/run_group_multi_party_device_real.dart`: inspect for missing 90-minute identity wait support; if needed, merge the minimal timeout constants/usages only.
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`: update only after gates/proof pass or after a concrete blocked-live-proof classification.
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-breakdown.md`: update only after implementation/proof, not during this planning session.

## existing tests covering this area

Current main already covers the shared live fixture through:

- RA-018 criteria tests for alternating Charlie/Dana churn;
- NW-014 `private_network_chaos_invariants` criteria validation;
- ST-001 model-oracle criteria validation;
- ST-013 relay-chaos criteria validation;
- ST-013 repair proof run `1779374192873` recorded in the current integration breakdown.

Missing in current main:

- ST-014 fake-network bounded soak selector;
- ST-014 criteria accept/missing/weak selectors;
- `st014SoakProof` role verdict emission and validation.

## regression/tests to add first

Add or merge tests before trusting harness changes:

1. Add the fake-network ST-014 soak test in `group_messaging_smoke_test.dart`.
2. Add ST-014 criteria tests in `group_multi_party_device_criteria_test.dart`.
3. Then add/merge the criteria validator and live-harness `st014SoakProof` emission so those tests prove the new fields are required.

If inspection shows current main already has equivalent ST-014 tests, do not duplicate them; run the existing selectors and document the skip.

## step-by-step implementation plan

1. Run dirty-state safety check. Only pre-existing `info.plist` may be dirty; leave it unstaged and untouched.
2. Side-by-side inspect source/current candidate files. Use targeted patches rather than wholesale copies.
3. Merge the fake-network ST-014 bounded soak selector.
4. Merge `st014SoakProof` fixture/criteria tests.
5. Merge `_validateSt014SoakProof` and wire it into `private_network_chaos_invariants`.
6. Merge `_st014SoakProof` live-harness emission into each role verdict for `private_network_chaos_invariants`.
7. Inspect runner identity wait behavior. If needed, add the 90-minute identity wait constants/usages without changing the current scenario catalog.
8. Run focused host/criteria/preservation gates.
9. Run exact iOS 26.2 live proof using only the current-main Alice/Bob/Charlie/Dana devices listed below.
10. Only after evidence is green, update test inventory and integration breakdown ledger. Commit only row-owned files and docs.

Stop early if current main already has an equivalent ST-014 delta; switch to evidence-only validation for that file.

## risks and edge cases

- Source worktree files are older/smaller than current main in several places; wholesale copy would regress later integrated scenarios.
- The shared `private_network_chaos_invariants` path carries RA-018/NW-014/ST-001/ST-013 proof fields. ST-014 must add to that contract, not replace it.
- Live proof can fail because of CoreSimulator or relay fixture health. Such failure is not acceptance unless all role verdicts and the orchestrator verdict pass.
- Runner timeout changes can accidentally shrink current scenario support or introduce missing imports. Keep that patch minimal.
- ST-014 depends on duplicate, held, delayed, restart-style replay, remove/re-add, and inactive-window privacy checks staying deterministic.

## Device/Relay Proof Profile

Use only these current-main available iOS 26.2 CoreSimulator app-peer devices if still available at execution time:

- Alice: `UP004 Alice iPhone 17 Pro iOS 26.2` / `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`
- Bob: `UP004 Bob iPhone Air iOS 26.2` / `279B82AE-2BB9-4924-9AAE-581870ED3FA9`
- Charlie: `UP004 Charlie iPhone 17 iOS 26.2` / `116B4AF6-C1A9-4F36-B929-0A7130B5E83C`
- Dana: `Gap Closure Dana iPhone 16e iOS 26.2` / `CD5929A6-EA0A-421D-A6D3-55BD707E0F76`

If any of these are unavailable, rerun simulator discovery and use only equivalent Alice/Bob/Charlie/Dana iOS 26.2 CoreSimulator devices from current main. Do not use iOS 26.1, iOS 26.4, Android, macOS, Chrome, or physical iOS as ST-014 acceptance proof.

Relay env:

```sh
MKNOON_RELAY_ADDRESSES='/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g'
```

Exact live proof command:

```sh
MKNOON_RELAY_ADDRESSES='/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g' dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario private_network_chaos_invariants --device 5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3,279B82AE-2BB9-4924-9AAE-581870ED3FA9,116B4AF6-C1A9-4F36-B929-0A7130B5E83C,CD5929A6-EA0A-421D-A6D3-55BD707E0F76
```

Preflight before live proof:

- no stale `flutter test`, `flutter drive`, runner, Xcode build, or `simctl launch` process is active;
- all four listed simulators are booted and available;
- `git status --short` shows only row-owned changes plus the pre-existing unrelated `info.plist`;
- relay env is exactly set.

## exact tests and gates to run

Focused gates:

```sh
flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name "ST-014"
flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name "ST-014"
```

Preservation gates:

```sh
flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name "RA-018"
flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name "NW-014"
flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name "ST-001"
flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name "ST-013"
```

Hygiene gates:

```sh
dart format --set-exit-if-changed test/features/groups/integration/group_messaging_smoke_test.dart integration_test/group_multi_party_device_real_harness.dart integration_test/scripts/group_multi_party_device_criteria.dart test/integration/group_multi_party_device_criteria_test.dart integration_test/scripts/run_group_multi_party_device_real.dart
flutter analyze --no-pub test/features/groups/integration/group_messaging_smoke_test.dart integration_test/group_multi_party_device_real_harness.dart integration_test/scripts/group_multi_party_device_criteria.dart test/integration/group_multi_party_device_criteria_test.dart integration_test/scripts/run_group_multi_party_device_real.dart
git diff --check
```

Live gate: run the exact iOS 26.2 command in the Device/Relay Proof Profile and inspect the shared artifact directory. Acceptance requires `ok=true`, all four role verdicts, final epoch convergence, and `st014SoakProof` present for Alice/Bob/Charlie/Dana.

## known-failure interpretation

Existing integration blockers outside this row remain outside ST-014 unless fresh evidence proves a new ST-014-owned regression:

- `KE-007` and `KE-009`: `blocked_conflict`;
- `ML-012`, `NW-014`, `UP-002`, `UP-004`, `UP-006`, `UP-009`, `UP-010`, `UP-011`, and prior `ST-001`: recorded external-fixture blockers until their own controller reclassification;
- broad `groups` and `completeness-check` residuals recorded in older ledger paragraphs are not ST-014 regressions unless a focused ST-014 or shared `private_network_chaos_invariants` preservation gate newly fails after this patch.

After `f9a31437`, the ST-013 live-fixture repair is accepted in main. Do not reopen or weaken it during ST-014.

## done criteria

Done means:

- row-owned ST-014 deltas are present or explicitly skipped as already equivalent;
- focused ST-014 host and criteria gates pass;
- RA-018/NW-014/ST-001/ST-013 preservation criteria gates pass;
- format, analyzer, and diff hygiene pass;
- exact iOS 26.2 Alice/Bob/Charlie/Dana live proof passes and writes valid role/orchestrator verdicts;
- future ledger and test-inventory updates accurately record accepted or blocked status;
- `info.plist` remains untouched and unstaged by this row.

## scope guard

Non-goals:

- no ST-015 seeded reproduction logs;
- no source matrix or source breakdown import;
- no COMPLETE_1 doc import;
- no Android, physical iOS, macOS, Chrome, or non-iOS-26.2 proof substitution;
- no broad live-harness rewrite;
- no RA-018/NW-014/ST-001/ST-013 contract redesign;
- no product behavior changes beyond row-owned proof support;
- no unrelated cleanup, formatting, or dependency import.

Overengineering includes adding a new soak engine, new relay logic, new simulator discovery workflow, or new acceptance semantics when the source row only needs the existing bounded deterministic proof and current live harness fields.

## accepted differences / intentionally out of scope

The source live proof used a source worktree whose runner/harness is not identical to current main. That difference is accepted: the executor must adapt the ST-014 proof fields into current main rather than force source parity.

ST-014 may use a bounded deterministic soak subset for host gates; the row's "hours in simulator" intent is closed only by the live `private_network_chaos_invariants` app-peer proof plus the bounded fake-network restart replay proof. Broader maximum-size churn, malformed bridge fuzzing, topic leak checks, relay chaos semantics, and seeded reproduction logs remain separate rows.

## dependency impact

`INTEGRATE-ST-015` should start only after ST-014 is accepted or explicitly blocked with ledger evidence. Later shared `private_network_chaos_invariants` users depend on this session preserving the RA-018/NW-014/ST-001/ST-013 proof fields and the ST-013 P2P ack repair.

## Ledger/commit instructions

This planning session did not update the integration breakdown ledger.

For the future implementation session:

- Update `test-inventory.md` and the integration breakdown only after focused gates and live proof have produced a concrete accepted or blocked result.
- Ledger row should list only row-owned files actually changed and the exact proof results.
- Commit only row-owned files, this plan, and any accepted ledger/test-inventory updates.
- Keep pre-existing `info.plist` unstaged and untouched.
- Suggested commit message after accepted proof: `Integrate ST-014 soak proof`.

## Reviewer Pass

Verdict: sufficient with adjustments already included.

Reviewer findings addressed in this contract:

- Whole-file source copying would be unsafe because current main is ahead of the source worktree in runner/harness scenario coverage.
- Runner timeout import must be minimal because source imports `group_multi_party_device_discovery.dart`, which is not present in current main.
- Acceptance must require a fresh live proof and cannot reuse source run `1778945272086` as main proof.
- Preservation gates for RA-018/NW-014/ST-001/ST-013 are mandatory because ST-014 shares the same `private_network_chaos_invariants` scenario.

## Arbiter Decision

Structural blockers remaining: none.

Incremental details intentionally deferred:

- Exact line placement of ST-014 helper/test blocks is left to the implementer after current-main file inspection.
- Broad `groups` and `completeness-check` gates are optional for this row unless the implementer changes broader shared behavior.

Accepted differences intentionally left unchanged:

- Current main may use a different runner/harness shape than the source worktree.
- Existing non-ST-014 blocker classifications remain ledger-owned by their original rows.

Why safe to implement now: the contract is narrow, source-backed, current-main-aware, and has explicit stop conditions for already-present deltas, live fixture failure, and preservation-gate regressions.

## Final Execution Verdict

Verdict: accepted for `INTEGRATE-ST-014`.

Blocker class: none.

Spawned-agent isolation: requested `$implementation-execution-qa-orchestrator` workflow was used in standard integration mode. Nested spawn tooling was unavailable in this session, so the skill's local sequential fallback was used with separate Executor and QA phases recorded in Execution Progress.

Files changed:

- `test/features/groups/integration/group_messaging_smoke_test.dart`
- `integration_test/group_multi_party_device_real_harness.dart`
- `integration_test/scripts/group_multi_party_device_criteria.dart`
- `test/integration/group_multi_party_device_criteria_test.dart`
- `integration_test/scripts/run_group_multi_party_device_real.dart`
- this ST-014 plan file, for Execution Progress and final verdict only

Tests added or updated:

- Added the focused fake-network selector `ST-014 bounded soak with churn and periodic restart replays catches divergence`.
- Added ST-014 criteria accept/missing/weak proof tests.
- Added `st014SoakProof` emission and validation for the existing `private_network_chaos_invariants` app-peer proof.
- Added minimal 90-minute identity wait support without replacing current-main runner scenario coverage.

Evidence captured:

- Focused ST-014 host gate passed: `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name "ST-014"` -> 1 test passed.
- Focused ST-014 criteria gate passed: `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name "ST-014"` -> 3 tests passed.
- Preservation gates passed: `RA-018` -> 8 tests, `NW-014` -> 3 tests, `ST-001` -> 3 tests, `ST-013` -> 3 tests.
- Hygiene passed: `dart format --set-exit-if-changed ...`, `flutter analyze --no-pub ...`, and `git diff --check`.
- Exact iOS 26.2 live proof passed with run id `1779376259089`.

Live proof details:

- Shared dir: `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_private_network_chaos_invariants_lhUqoc`
- Devices: Alice `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`, Bob `279B82AE-2BB9-4924-9AAE-581870ED3FA9`, Charlie `116B4AF6-C1A9-4F36-B929-0A7130B5E83C`, Dana `CD5929A6-EA0A-421D-A6D3-55BD707E0F76`
- Orchestrator verdict: `gmp_1779376259089_private_network_chaos_invariants_orchestrator_verdict.json`, `ok=true`, `private_network_chaos_invariants verdicts valid for alice, bob, charlie, dana`
- Role verdicts: `gmp_1779376259089_alice_verdict.json`, `gmp_1779376259089_bob_verdict.json`, `gmp_1779376259089_charlie_verdict.json`, `gmp_1779376259089_dana_verdict.json`
- Proof summary: all four role verdicts contain `st014SoakProof` with `rowId=ST-014`, `appPeerPlatform=ios_26_2_core_simulator`, `fixedSeed=14014`, 12 model comparison checkpoints, 12 message operations, 12 membership operations, 3 churn cycles, `finalEpoch=13`, `finalEpochConverged=true`, `finalMemberListConverged=true`, `receiveDeadPeerCount=0`, `duplicateVisibleMessageCount=0`, and `inactiveSenderAttemptCount=0`.
- Preservation summary: all four role verdicts also retain `nw014ChaosInvariantProof`, `st001ModelOracleProof`, and `st013RelayChaosProof`.

Blocking issues remaining: none for ST-014.

Non-blocking follow-ups:

- Closure-owned integration breakdown and test-inventory updates remain intentionally untouched in this execution session.
- Pre-existing unrelated `info.plist` remains unstaged and untouched.

Why safe complete: the row-owned deltas are present, focused and preservation gates passed, the exact required iOS 26.2 app-peer proof passed with valid role and orchestrator verdicts, and final scope review found no unrelated edits beyond the pre-existing dirty `info.plist`.

## Closure Documentation Note

2026-05-21 closure worker updated only the integration breakdown ledger and `test-inventory.md` to mark `INTEGRATE-ST-014` accepted with the execution evidence above. No production, test, harness, script Dart files, source matrix docs, source worktree docs, COMPLETE_1 docs, or ST-015 docs were edited during closure; no files were staged or committed; unrelated `info.plist` remained unstaged and untouched.
