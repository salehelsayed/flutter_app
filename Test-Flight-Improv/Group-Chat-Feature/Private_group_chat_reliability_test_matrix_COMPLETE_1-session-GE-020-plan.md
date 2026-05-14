# GE-020 Long Soak Private Group With Churn Plan

Status: accepted/closed

## Planning Progress

- 2026-05-13 19:25 CEST - Local plan fallback completed after the spawned planner left only a stale `planning-draft`. Files inspected: source matrix GE-020 row, session-breakdown GE-020 row, `test/features/groups/integration/group_messaging_smoke_test.dart`, `test/shared/fakes/fake_group_pubsub_network.dart`, `test/shared/fakes/group_test_user.dart`, `integration_test/scripts/run_group_multi_party_device_real.dart`, `integration_test/scripts/group_multi_party_device_criteria.dart`, `integration_test/group_multi_party_device_real_harness.dart`, and `test/integration/group_multi_party_device_criteria_test.dart`. Decision: GE-020 remains repo-owned and must be reclassified from `needs_repo_evidence`/`evidence-gated` to `needs_code_and_tests` because the source row is `Open` and the focused selector has no matching test.

## Execution Progress

- 2026-05-13 19:27 CEST - Phase: Executor owner files inspected. Files inspected: `test/features/groups/integration/group_messaging_smoke_test.dart`, `test/shared/fakes/fake_group_pubsub_network.dart`, `test/shared/fakes/group_test_user.dart`, `integration_test/scripts/group_multi_party_device_criteria.dart`, `integration_test/scripts/run_group_multi_party_device_real.dart`, `integration_test/group_multi_party_device_real_harness.dart`, and `test/integration/group_multi_party_device_criteria_test.dart`. Decision/blocker: no existing exact `GE-020` host selector or `ge020` scenario registration exists; GE-017/GE-019 host helpers and existing offline Charlie relaunch/device proof helpers are the matching implementation patterns. Next action: edit primary owner files to add `_runGe020Seed`, `ge020` scenario requirement/dispatch/harness role handlers, and GE-020 criteria tests.
- 2026-05-13 19:26 CEST - Phase: Executor local contract re-confirmed. Files inspected: this GE-020 plan, pre-edit `git status --short`, and owner-file search for existing GE-017/GE-019/ge020 patterns. Decision/blocker: worktree is dirty before this Executor pass, including every primary GE-020 owner file; no unrelated changes will be reverted. Next action: inspect owner file implementations in detail, then add only the exact GE-020 host selector and device scenario/criteria support required by the plan.
- 2026-05-13 19:31 CEST - Phase: spawned Executor stopped and local fallback started. Files inspected/touched: this plan and `test/features/groups/integration/group_messaging_smoke_test.dart`. Decision/blocker: spawned Executor produced only a partial implementation delta, adding the `GE-020 long soak private group with churn preserves convergence` selector while `_runGe020Seed` and all `ge020` device/criteria support remained absent; leaving that partial state would be an incomplete compile seam. Next action: complete the GE-020 host helper and `ge020` criteria/harness support locally, then run the required validations or return a blocker with exact failure class.
- 2026-05-13 19:36 CEST - Phase: local fallback implementation completed. Files touched: `test/features/groups/integration/group_messaging_smoke_test.dart`, `integration_test/scripts/group_multi_party_device_criteria.dart`, `integration_test/scripts/run_group_multi_party_device_real.dart`, `integration_test/group_multi_party_device_real_harness.dart`, `test/integration/group_multi_party_device_criteria_test.dart`, and this plan. Decision/blocker: exact `GE-020` host selector plus `_runGe020Seed` are present; exact `ge020` criteria requirement, runner scenario dispatch, harness role handlers, `ge020LongSoakChurnProof`, and valid/rejection criteria tests are present. Next action: run formatting and required host validations.
- 2026-05-13 19:36 CEST - Phase: formatting applied. Files touched: the five primary Dart owner files. Command finished: `dart format test/features/groups/integration/group_messaging_smoke_test.dart integration_test/scripts/group_multi_party_device_criteria.dart integration_test/scripts/run_group_multi_party_device_real.dart integration_test/group_multi_party_device_real_harness.dart test/integration/group_multi_party_device_criteria_test.dart` passed and formatted 3 files. Next action: run required `dart format --set-exit-if-changed ...` validation.
- 2026-05-13 19:37 CEST - Phase: required format validation started. Command running: `dart format --set-exit-if-changed test/features/groups/integration/group_messaging_smoke_test.dart integration_test/scripts/group_multi_party_device_criteria.dart integration_test/scripts/run_group_multi_party_device_real.dart integration_test/group_multi_party_device_real_harness.dart test/integration/group_multi_party_device_criteria_test.dart`. Next action: record pass/fail and continue to `dart analyze`.
- 2026-05-13 19:37 CEST - Phase: required format validation finished. Command result: `dart format --set-exit-if-changed ...` passed, formatted 5 files with 0 changes. Next action: run required `dart analyze` on the five primary Dart owner files.
- 2026-05-13 19:37 CEST - Phase: required analyze started. Command running: `dart analyze test/features/groups/integration/group_messaging_smoke_test.dart integration_test/scripts/group_multi_party_device_criteria.dart integration_test/scripts/run_group_multi_party_device_real.dart integration_test/group_multi_party_device_real_harness.dart test/integration/group_multi_party_device_criteria_test.dart`. Next action: record pass/fail and fix any GE-020-owned analyzer failures.
- 2026-05-13 19:38 CEST - Phase: required analyze finished. Command result: `dart analyze ...` passed with `No issues found!`. Next action: run focused host selector `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name 'GE-020'`.
- 2026-05-13 19:38 CEST - Phase: focused GE-020 host selector started. Command running: `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name 'GE-020'`. Next action: record pass/fail and triage any GE-020 proof failure before fixing.
- 2026-05-13 19:44 CEST - Phase: focused GE-020 host selector finished. Command result: `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name 'GE-020'` passed with `+1: All tests passed!`. Next action: run focused GE-020 criteria selector.
- 2026-05-13 19:44 CEST - Phase: focused GE-020 criteria selector started. Command running: `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'GE-020'`. Next action: record pass/fail and triage any GE-020 criteria failure before fixing.
- 2026-05-13 19:44 CEST - Phase: focused GE-020 criteria selector finished. Command result: `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'GE-020'` passed with `+2: All tests passed!`. Next action: run required named groups gate.
- 2026-05-13 19:44 CEST - Phase: required groups gate started. Command running: `./scripts/run_test_gates.sh groups`. Next action: record pass/fail and classify any failure before fixes.
- 2026-05-13 19:46 CEST - Phase: required groups gate finished. Command result: `./scripts/run_test_gates.sh groups` passed with `+159: All tests passed!`. Next action: run required `git diff --check` on GE-020 owner files and closure docs.
- 2026-05-13 19:46 CEST - Phase: required diff whitespace check started. Command running: `git diff --check -- test/features/groups/integration/group_messaging_smoke_test.dart integration_test/scripts/group_multi_party_device_criteria.dart integration_test/scripts/run_group_multi_party_device_real.dart integration_test/group_multi_party_device_real_harness.dart test/integration/group_multi_party_device_criteria_test.dart Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md Test-Flight-Improv/Group-Chat-Feature/test-inventory.md Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GE-020-plan.md`. Next action: record pass/fail and fix GE-020-owned whitespace issues only.
- 2026-05-13 19:46 CEST - Phase: required diff whitespace check finished. Command result: `git diff --check -- ...` passed with no output. Next action: re-check simulator availability for required GE-020 device proof.
- 2026-05-13 19:46 CEST - Phase: GE-020 device feasibility check started. Command running: `flutter devices --machine`. Next action: confirm the three plan simulator IDs remain available before running the relay-backed `ge020` device command.
- 2026-05-13 19:46 CEST - Phase: GE-020 device feasibility check finished. Command result: `flutter devices --machine` passed and listed the three plan simulator IDs as supported iOS simulators: `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD`, `5BA69F1C-B112-47BE-B1FF-8C1003728C8F`, and `1B098DFF-6294-407A-A209-BBF360893485`. Next action: run required relay-backed `ge020` three-device command.
- 2026-05-13 19:46 CEST - Phase: required GE-020 three-device proof started. Command running: `MKNOON_RELAY_ADDRESSES=/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g dart integration_test/scripts/run_group_multi_party_device_real.dart --scenario ge020 -d 347FB118-10D0-40C8-A05B-B0C3BD6B8CCD,5BA69F1C-B112-47BE-B1FF-8C1003728C8F,1B098DFF-6294-407A-A209-BBF360893485`. Next action: record pass/fail with failure class if any.
- 2026-05-13 19:56 CEST - Phase: required GE-020 three-device proof finished. Command result: relay-backed `ge020` device proof exited 0 with `ge020 proof passed: ge020 verdicts valid for alice, bob, charlie`; shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_ge020_9KMoiD`, run id `1778694622398`, role verdicts `gmp_1778694622398_alice_verdict.json`, `gmp_1778694622398_bob_verdict.json`, and `gmp_1778694622398_charlie_verdict.json`. Next action: close GE-020 source matrix, breakdown ledgers, and test inventory as `Covered`/accepted.
- 2026-05-13 19:24 CEST - Phase: contract extraction started. Files inspected: this GE-020 plan, `$implementation-execution-qa-orchestrator`, and pre-execution `git status --short`. Decision/blocker: worktree is already dirty, including GE-020 owner files; treat current status as baseline and do not revert unrelated edits. Next action: extract exact GE-020 scope, owner files, validations, and closure bar before coding.
- 2026-05-13 19:24 CEST - Phase: contract extracted. Scope: add exact `GE-020` host fake-network soak selector and exact `ge020` multi-party device scenario/criteria support in the plan owner files only. Required host validations: `dart format --set-exit-if-changed ...`, `dart analyze ...`, focused GE-020 host selector, focused GE-020 criteria selector, `./scripts/run_test_gates.sh groups`, and `git diff --check -- ...`. Required device validation when fixture is available: `dart integration_test/scripts/run_group_multi_party_device_real.dart --scenario ge020 -d 347FB118-10D0-40C8-A05B-B0C3BD6B8CCD,5BA69F1C-B112-47BE-B1FF-8C1003728C8F,1B098DFF-6294-407A-A209-BBF360893485`. Non-goals: production/Go/relay/UI changes unless a direct GE-020 proof failure requires adjacent owner code. Next action: spawn Executor child with `model: gpt-5.5` and `reasoning_effort: xhigh`.
- 2026-05-13 19:24 CEST - Phase: Executor spawned/running. Files assigned: primary GE-020 owner files and this plan. Command running: `codex exec -m gpt-5.5 -c model_reasoning_effort="xhigh" -s danger-full-access -a never -C /Users/I560101/Project-Sat/mknoon-2/flutter_app`. Decision/blocker: spawned-agent isolation is available through Codex CLI. Next action: wait for Executor result, then spawn separate QA Reviewer.
- 2026-05-13 19:24 CEST - Phase: Executor spawn retry. Files touched: this plan. Command result: initial `codex exec ... -a never` exited 2 because this CLI build does not accept `-a` on `codex exec`. Decision/blocker: tool-shape retry, not implementation progress. Next action: relaunch Executor with `approval_policy="never"` through Codex config.

## Execution Evidence

- Baseline: `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name 'GE-020'` exited 79 with `No tests match "GE-020"`, confirming the row-owned selector was absent.
- Implementation: added `test/features/groups/integration/group_messaging_smoke_test.dart::GE-020 long soak private group with churn preserves convergence` plus `_runGe020Seed`, running seeds `20020`, `20021`, and `20022` with 44 deterministic operations per seed over A/B/C/D. Operations include sends, offline held delivery, online recovery, relay refresh/rejoin, remove, re-add, inactive send, key rotation, restart, and duplicate send delivery. Assertions cover active-member delivery, removed-window privacy, inactive-send no-op behavior, active membership/key convergence, duplicate member/device prevention, and drained held-delivery queues.
- Implementation: added `ge020` scenario support in `integration_test/scripts/group_multi_party_device_criteria.dart`, `integration_test/scripts/run_group_multi_party_device_real.dart`, `integration_test/group_multi_party_device_real_harness.dart`, and `test/integration/group_multi_party_device_criteria_test.dart`, including `ge020LongSoakChurnProof` validation and valid/rejection criteria tests.
- Host gates passed: `dart format --set-exit-if-changed test/features/groups/integration/group_messaging_smoke_test.dart integration_test/scripts/group_multi_party_device_criteria.dart integration_test/scripts/run_group_multi_party_device_real.dart integration_test/group_multi_party_device_real_harness.dart test/integration/group_multi_party_device_criteria_test.dart`; `dart analyze ...` on the same five owner files with `No issues found!`; focused GE-020 host (`+1`); focused GE-020 criteria (`+2`); `./scripts/run_test_gates.sh groups` (`+159`); and `git diff --check -- ...` on owned files plus closure docs.
- Device proof passed: `MKNOON_RELAY_ADDRESSES=/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g dart integration_test/scripts/run_group_multi_party_device_real.dart --scenario ge020 -d 347FB118-10D0-40C8-A05B-B0C3BD6B8CCD,5BA69F1C-B112-47BE-B1FF-8C1003728C8F,1B098DFF-6294-407A-A209-BBF360893485` exited 0 with `ge020 proof passed: ge020 verdicts valid for alice, bob, charlie`; shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_ge020_9KMoiD`, run id `1778694622398`.

## Final Verdict

GE-020 is `accepted/closed`. The source row is now `Covered` with exact host fake-network and required relay-backed three-party device evidence. No production, Go, relay-server, schema, or UI runtime code was required; the repo-owned gap was missing exact host/device proof and criteria/runner/harness support. Residual-only: none for GE-020. Continue from GO-001, the next unresolved P0 row in session order; no final program verdict is written because unresolved source rows remain.

## Original Source Row

| Test ID | Scenario | Preconditions | Steps | Expected Result | Priority | Current status | Unit | Integration | Smoke | Fake Network | 3-Party E2E | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| GE-020 | Long soak private group with churn | Three or more devices over extended fake time. | 1. Run sends, disconnects, relay refreshes, add/remove/readd. 2. Periodically assert convergence. | No permanent deaf member, goroutine leak, or retry queue loss. | P0 | Open | Recommended | Required | N/A | Required | Required | Soak catches intermittent issue. |

## Reconciliation Verdict

At planning intake, the source matrix row is `Open`, the breakdown row is `needs_repo_evidence`/`evidence-gated`, and the baseline selector `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name 'GE-020'` exits 79 with `No tests match "GE-020"`. No exact `ge020` support exists in the multi-party device runner, criteria map, or harness. Under implementation-committed gap-closure rules this is repo-owned missing proof work, not an external blocker. Reclassify GE-020 to `needs_code_and_tests`.

## Scope

Own exactly GE-020:

- Add a deterministic host fake-network soak proof in `test/features/groups/integration/group_messaging_smoke_test.dart` with an exact `GE-020` test selector.
- The host proof must model at least A/B/C/D, run a long deterministic operation sequence over sends, disconnects/offline delivery holds, recovery/reconnects, relay refresh/rejoin, add/remove/readd, key rotations, restarts, and duplicate delivery, then periodically assert convergence.
- The host proof must fail if any active member becomes permanently deaf, if entitled messages are lost after recovery, if removed/not-yet-added peers render out-of-window plaintext, if inactive sends mutate local state or publish, if active membership/key state diverges, or if retry/held-delivery queues strand work after recovery.
- Add exact `ge020` repo-owned 3-party E2E support where the existing multi-party harness owns scenario registration and criteria evaluation:
  - `integration_test/scripts/group_multi_party_device_criteria.dart`
  - `integration_test/scripts/run_group_multi_party_device_real.dart`
  - `integration_test/group_multi_party_device_real_harness.dart`
  - `test/integration/group_multi_party_device_criteria_test.dart`
- Update only the GE-020 source matrix row, this plan, the session breakdown GE-020 ledger entries, and `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` during closure.

## Out Of Scope

- Production behavior changes unless the GE-020 proof exposes a concrete runtime defect that must be fixed to satisfy the row.
- Go transport, relay, SQLCipher migration, notification, unrelated group scenario, or UI changes unless a directly failing GE-020 proof identifies the file as the owner.
- Weakening existing GE-017, GE-018, or GE-019 proof expectations.

## Owner Files

Primary test/harness owner files:

- `test/features/groups/integration/group_messaging_smoke_test.dart`
- `integration_test/scripts/group_multi_party_device_criteria.dart`
- `integration_test/scripts/run_group_multi_party_device_real.dart`
- `integration_test/group_multi_party_device_real_harness.dart`
- `test/integration/group_multi_party_device_criteria_test.dart`

Closure/docs owner files:

- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md`
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GE-020-plan.md`

## Device/Relay Proof Profile

Profile: `three-party/device-lab` plus `host-only fake-network` proof.

Live availability check run by the controller:

```sh
flutter devices --machine
```

Relevant available devices:

- `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD` (`iPhone Air`, iOS simulator)
- `5BA69F1C-B112-47BE-B1FF-8C1003728C8F` (`iPhone 17`, iOS simulator)
- `1B098DFF-6294-407A-A209-BBF360893485` (`iPhone 16e`, iOS simulator)

The host fake-network GE-020 test is required closure evidence for the `Integration` and `Fake Network` cells. The 3-party E2E cell is also `Required`, so closure must either run the exact `ge020` three-role device command below successfully, or record a truthful external-fixture blocker if the live devices/relay fixture cannot be used at execution time.

Use the repo relay profile:

```sh
MKNOON_RELAY_ADDRESSES=/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g
```

Device proof command after `ge020` support exists:

```sh
dart integration_test/scripts/run_group_multi_party_device_real.dart --scenario ge020 -d 347FB118-10D0-40C8-A05B-B0C3BD6B8CCD,5BA69F1C-B112-47BE-B1FF-8C1003728C8F,1B098DFF-6294-407A-A209-BBF360893485
```

A single `FLUTTER_DEVICE_ID` is not sufficient for GE-020 because the source row requires 3-party E2E proof.

## Implementation Steps

1. Add a `GE-020 long soak private group with churn preserves convergence` test beside GE-017/GE-019 in `group_messaging_smoke_test.dart`.
2. Implement `_runGe020Seed(...)` using the local `GroupTestUser` and `FakeGroupPubSubNetwork` patterns:
   - deterministic seeds, at least three active members, and a fourth churn member;
   - a longer operation count than GE-017/GE-019;
   - operation log context in every assertion;
   - forced operations covering send, disconnect/offline hold, reconnect/release, relay refresh/rejoin, remove, re-add, key rotation, restart, duplicate delivery, and inactive send;
   - periodic convergence checks after each operation and a final recovery drain for all active peers.
3. Add exact `ge020` support to the multi-party device stack:
   - scenario requirement and supported-scenario text;
   - runner dispatch;
   - harness role map and role functions or scenario behavior that emits a `ge020LongSoakChurnProof` verdict;
   - criteria validator and criteria tests for valid and invalid GE-020 verdicts.
4. Run formatting on changed Dart files.
5. Run focused host and criteria tests, then the named groups gate.
6. Run the GE-020 device proof command if the three listed simulator IDs remain available. If it fails due to fixture availability rather than row-owned code, capture exact blocker details and do not mark the row `Covered`.
7. Update matrix/breakdown/inventory only after concrete proof exists.

## Required Validation

Minimum host gates:

```sh
dart format --set-exit-if-changed test/features/groups/integration/group_messaging_smoke_test.dart integration_test/scripts/group_multi_party_device_criteria.dart integration_test/scripts/run_group_multi_party_device_real.dart integration_test/group_multi_party_device_real_harness.dart test/integration/group_multi_party_device_criteria_test.dart
dart analyze test/features/groups/integration/group_messaging_smoke_test.dart integration_test/scripts/group_multi_party_device_criteria.dart integration_test/scripts/run_group_multi_party_device_real.dart integration_test/group_multi_party_device_real_harness.dart test/integration/group_multi_party_device_criteria_test.dart
flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name 'GE-020'
flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'GE-020'
./scripts/run_test_gates.sh groups
git diff --check -- test/features/groups/integration/group_messaging_smoke_test.dart integration_test/scripts/group_multi_party_device_criteria.dart integration_test/scripts/run_group_multi_party_device_real.dart integration_test/group_multi_party_device_real_harness.dart test/integration/group_multi_party_device_criteria_test.dart Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md Test-Flight-Improv/Group-Chat-Feature/test-inventory.md Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GE-020-plan.md
```

Required device proof when fixture is available:

```sh
dart integration_test/scripts/run_group_multi_party_device_real.dart --scenario ge020 -d 347FB118-10D0-40C8-A05B-B0C3BD6B8CCD,5BA69F1C-B112-47BE-B1FF-8C1003728C8F,1B098DFF-6294-407A-A209-BBF360893485
```

## Done Criteria

- The source matrix GE-020 row is `Covered` only after exact host fake-network proof and exact 3-party E2E proof, or after a persisted truthful external-fixture blocker if device proof cannot run.
- The GE-020 focused selector passes and did not exist at baseline.
- Criteria tests prove valid GE-020 verdict acceptance and at least one rejection for deaf-member, stranded-queue, or divergent-convergence failure.
- The session breakdown, session ledger, row disposition map, ordered breakdown row, and test inventory all cite concrete files, selectors, commands, and outcomes.
- No `accepted_with_explicit_follow_up` is used for unresolved row-owned gaps.

## Scope Guard

Use the pre-execution `git status --short` as the dirty-worktree baseline. Do not revert or rewrite unrelated existing changes. If execution touches files outside the owner list, closure must classify the change as intentional GE-020 scope or blocking before acceptance.

## Reviewer Notes

This plan is execution-safe for GE-020. The only known blocker would be live 3-device/relay fixture failure after repo-owned `ge020` harness support exists; that must be recorded as external-fixture-blocked with the command attempted, device IDs, relay profile, logs, and next safe action.

## Arbiter Verdict

Proceed to execution. GE-020 is `needs_code_and_tests`.
