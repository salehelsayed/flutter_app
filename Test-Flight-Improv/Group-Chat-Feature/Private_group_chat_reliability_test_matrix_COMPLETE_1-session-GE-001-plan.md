# GE-001 Session Plan: A/B/C Private Chat Happy Path

## Status

Status: accepted/closed

## Source Row

Source matrix row: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` row `GE-001`

## Gap-Closure Reconciliation

| Time | Actor | Inputs Compared | Finding | Action |
|---|---|---|---|---|
| 2026-05-13 08:57:00 CEST | Controller | Source matrix GE-001 row; breakdown row 160; existing `GM-001` host/device proofs; `test/features/groups/integration/group_messaging_smoke_test.dart`; `integration_test/group_multi_party_device_real_harness.dart`; `integration_test/scripts/group_multi_party_device_criteria.dart`; `integration_test/scripts/run_group_multi_party_device_real.dart`; live `flutter devices --machine` and `xcrun simctl list devices available` output | The source row was still `Open` and breakdown row 160 was `needs_repo_evidence` / `evidence-gated`. Existing `GM-001` proofs covered A sending to B/C, and a 4-user round-robin covered a broader fake-network shape, but no exact GE-001 row-owned proof made A, B, and C each send one private-chat message and verified both fake-network and three-device relay evidence. The missing device scenario support was repo-owned harness code, not an external fixture blocker. | Add exact fake-network GE-001 regression, add a `ge001` three-role device-harness scenario and criteria validation, run host/criteria/broader gates, run the three-simulator real relay proof, then update the source row and breakdown ledgers. |

## Scope

GE-001 owns the minimum A/B/C private-chat release smoke: create a private group, join all three members, have each participant send exactly one message, and prove every other participant receives each sender's message exactly once with no failed or pending sender state.

Out of scope: removal/re-add, offline windows, replay gaps, stress loops, and later GE stateful journeys.

## Device/Relay Proof Profile

| Field | Value |
|---|---|
| Profile | `three-party/device-lab` |
| Live availability check | `flutter devices --machine` showed booted supported iOS simulators `38FECA55-03C1-4907-BD9D-8E64BF8E3469`, `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD`, and `5BA69F1C-B112-47BE-B1FF-8C1003728C8F`; `xcrun simctl list devices available` showed the same iOS 26.1 devices booted. `adb devices` was unavailable (`adb: command not found`), so iOS simulators were used. |
| Devices | Alice `38FECA55-03C1-4907-BD9D-8E64BF8E3469`; Bob `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD`; Charlie `5BA69F1C-B112-47BE-B1FF-8C1003728C8F` |
| Relay profile | `MKNOON_RELAY_ADDRESSES=/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g` |
| Closure command | `MKNOON_RELAY_ADDRESSES=... dart integration_test/scripts/run_group_multi_party_device_real.dart --scenario ge001 -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469,347FB118-10D0-40C8-A05B-B0C3BD6B8CCD,5BA69F1C-B112-47BE-B1FF-8C1003728C8F` |
| Closure evidence | Required closure evidence. A single `FLUTTER_DEVICE_ID` gate is not sufficient for this row. |

## Execution Contract

1. Add `GE-001 A/B/C happy-path private chat smoke delivers every sender exactly once` to `test/features/groups/integration/group_messaging_smoke_test.dart`.
2. Create a private A/B/C fake-network group, persist shared group state/key material for all participants, start all listeners, and send one bridge-backed message each from Alice, Bob, and Charlie.
3. Prove each send returns success, local outgoing status is `sent`, durable inbox storage succeeds, retry payloads are absent, publish count is three, and fake-network delivery count is six.
4. Prove every participant has exactly three GE-001 messages: one outgoing self message and two incoming messages from the other participants, each incoming sender/text/messageId tuple exactly once and no `failed` or `pending` row.
5. Add a `ge001` scenario to the real multi-party device harness and criteria, with Alice, Bob, and Charlie each sending once and the orchestrator validating all three role verdicts.
6. Run focused, adjacent, broad host, static-analysis, and three-simulator relay gates.

## Required Gates

| Gate | Command |
|---|---|
| Focused fake-network proof | `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name 'GE-001'` |
| Criteria focused proof | `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'GE-001'` |
| Criteria full regression | `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart` |
| Static analysis | `dart analyze integration_test/scripts/group_multi_party_device_criteria.dart integration_test/scripts/run_group_multi_party_device_real.dart integration_test/group_multi_party_device_real_harness.dart test/integration/group_multi_party_device_criteria_test.dart` |
| Adjacent GM-001 proof | `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name 'GM-001 creates private A/B/C group with shared epoch and exact fanout tuple'` |
| Adjacent round-robin proof | `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name '4 users: round-robin messaging'` |
| Broader group smoke gate | `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart test/features/groups/integration/group_membership_smoke_test.dart test/features/groups/integration/group_resume_recovery_test.dart` |
| Three-device relay proof | `MKNOON_RELAY_ADDRESSES=... dart integration_test/scripts/run_group_multi_party_device_real.dart --scenario ge001 -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469,347FB118-10D0-40C8-A05B-B0C3BD6B8CCD,5BA69F1C-B112-47BE-B1FF-8C1003728C8F` |
| Formatting | `dart format --set-exit-if-changed integration_test/scripts/group_multi_party_device_criteria.dart integration_test/scripts/run_group_multi_party_device_real.dart integration_test/group_multi_party_device_real_harness.dart test/integration/group_multi_party_device_criteria_test.dart test/features/groups/integration/group_messaging_smoke_test.dart` |
| Hygiene | `git diff --check` |

## Dirty Worktree Snapshot

Captured before GE-001 closure: worktree already contained prior rollout edits and accepted GR-017 and earlier row changes. GE-001 scope is limited to `test/features/groups/integration/group_messaging_smoke_test.dart`, `integration_test/group_multi_party_device_real_harness.dart`, `integration_test/scripts/group_multi_party_device_criteria.dart`, `integration_test/scripts/run_group_multi_party_device_real.dart`, `test/integration/group_multi_party_device_criteria_test.dart`, this plan, the source matrix row GE-001, and breakdown closure documentation.

## Execution Evidence

- Added `test/features/groups/integration/group_messaging_smoke_test.dart::GE-001 A/B/C happy-path private chat smoke delivers every sender exactly once`.
- Added `ge001` support to `integration_test/scripts/group_multi_party_device_criteria.dart`, `integration_test/scripts/run_group_multi_party_device_real.dart`, and `integration_test/group_multi_party_device_real_harness.dart`.
- Added GE-001 criteria coverage to `test/integration/group_multi_party_device_criteria_test.dart`, including accepted all-send verdicts and duplicate receiver-persistence rejection.
- The fake-network proof creates Alice/Bob/Charlie, starts all three subscribers, sends `ge001-alice-message`, `ge001-bob-message`, and `ge001-charlie-message`, proves three publishes and six deliveries, and proves each participant has exactly one outgoing self row plus exactly two incoming rows from the other participants with no failed/pending status.
- The device proof ran `ge001` across Alice/Bob/Charlie iOS simulators with the configured relay profile, produced role verdict files under `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_ge001_IKTEqB`, and the orchestrator accepted the run as `ge001 verdicts valid for alice, bob, charlie`.

## Verification

- `dart format --set-exit-if-changed ...` passed after formatting `integration_test/group_multi_party_device_real_harness.dart`; rerun passed with `0 changed`.
- `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'GE-001'` passed (`+2`).
- `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name 'GE-001'` passed (`+1`).
- `dart analyze integration_test/scripts/group_multi_party_device_criteria.dart integration_test/scripts/run_group_multi_party_device_real.dart integration_test/group_multi_party_device_real_harness.dart test/integration/group_multi_party_device_criteria_test.dart` passed (`No issues found!`).
- `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'scenario requirements map GM roles to device counts'` passed (`+1`).
- `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name 'GM-001 creates private A/B/C group with shared epoch and exact fanout tuple'` passed (`+1`).
- `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name '4 users: round-robin messaging'` passed (`+1`).
- `MKNOON_RELAY_ADDRESSES=... dart integration_test/scripts/run_group_multi_party_device_real.dart --scenario ge001 -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469,347FB118-10D0-40C8-A05B-B0C3BD6B8CCD,5BA69F1C-B112-47BE-B1FF-8C1003728C8F` passed; orchestrator verdict: `ge001 proof passed: ge001 verdicts valid for alice, bob, charlie`.
- `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart test/features/groups/integration/group_membership_smoke_test.dart test/features/groups/integration/group_resume_recovery_test.dart` passed (`+114`).
- `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart` passed (`+140`).

## Final Verdict

Accepted/closed. GE-001 is `Covered` by exact host fake-network evidence plus required three-device relay proof. The only implementation was repo-owned test/harness/criteria coverage needed to make the row provable; no product runtime behavior change was required. Residual-only: none for GE-001. GE-005 is the next unresolved P0 session in ledger order; no final program verdict was written.
