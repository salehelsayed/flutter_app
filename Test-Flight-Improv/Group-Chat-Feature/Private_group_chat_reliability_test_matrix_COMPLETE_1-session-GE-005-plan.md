# GE-005 Session Plan: Remove/Re-add Loop 20 Times With Sends Between Transitions

Status: accepted

## Gap-Closure Reconciliation

GE-005 source row is `Open`: Alice, Bob, and Charlie are joined, then Charlie is removed and re-added for 20 cycles with sends between transitions. The row requires every cycle to keep entitled delivery working and prevent Charlie from seeing removed-window traffic. The breakdown session ledger and ordered row 164 classify GE-005 as `needs_repo_evidence` / `evidence-gated`, but reconciliation reclassifies it as repo-owned runnable work because the fake-network smoke test, criteria validator, runner, and three-role simulator harness all live in this repo. GE-004 proves one remove/re-add exchange; it does not prove the repeated 20-cycle stress contract.

## Scope

- Add exact host fake-network proof for GE-005.
- Add `ge005` three-role simulator harness support.
- Add `ge005` criteria validation and tests.
- Update the source matrix and breakdown only after gates pass.

Out of scope: product behavior changes unless the exact GE-005 proof fails for a product reason.

## Execution Contract

The row closes only if:

- Alice/Bob/Charlie start in one private group.
- For 20 cycles, Alice removes Charlie and remaining members converge.
- During each removed window, Alice sends one message that Bob receives exactly once and Charlie does not receive.
- Alice re-adds Charlie and all active members converge.
- During each re-added window, Bob sends one message that Alice and Charlie receive exactly once.
- Durable recipient proof excludes Charlie during removed windows and includes Charlie after re-add.
- Final membership contains Alice, Bob, and Charlie.
- The same contract passes in the three-simulator `ge005` relay harness.

## Required Gates

| Gate | Command |
|---|---|
| Focused fake-network proof | `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name 'GE-005'` |
| Criteria focused proof | `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'GE-005'` |
| Criteria full regression | `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart` |
| Static analysis | `dart analyze integration_test/scripts/group_multi_party_device_criteria.dart integration_test/scripts/run_group_multi_party_device_real.dart integration_test/group_multi_party_device_real_harness.dart test/integration/group_multi_party_device_criteria_test.dart test/features/groups/integration/group_messaging_smoke_test.dart test/shared/fakes/group_test_user.dart` |
| Three-device relay proof | `MKNOON_RELAY_ADDRESSES=... dart integration_test/scripts/run_group_multi_party_device_real.dart --scenario ge005 -d <alice,bob,charlie>` |
| Broader group smoke gate | `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart test/features/groups/integration/group_membership_smoke_test.dart test/features/groups/integration/group_resume_recovery_test.dart` |
| Formatting | `dart format --set-exit-if-changed test/features/groups/integration/group_messaging_smoke_test.dart integration_test/scripts/group_multi_party_device_criteria.dart integration_test/scripts/run_group_multi_party_device_real.dart integration_test/group_multi_party_device_real_harness.dart test/integration/group_multi_party_device_criteria_test.dart` |
| Hygiene | `git diff --check` |

## Closure Evidence

GE-005 closed with code changes and exact proof. The first three-device run exposed a repo-owned key-rotation gap where local/admin key promotion could happen after incomplete P2P distribution; `lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart` now keeps rotation fail-closed until required recipient key updates are delivered. The second three-device run exposed a removed-peer receive stall when Charlie missed the pubsub self-removal and relay inbox retrieval repeatedly failed; `lib/features/groups/application/group_membership_update_listener.dart`, `lib/core/services/incoming_message_router.dart`, `lib/features/groups/presentation/screens/group_info_wired.dart`, `integration_test/group_multi_device_real_harness.dart`, `integration_test/group_multi_party_device_real_harness.dart`, and `lib/main.dart` now carry the existing signed/encrypted membership replay envelope over a direct `group_membership_update` message to the removed peer.

Passed gates:

- `dart analyze lib/core/services/incoming_message_router.dart lib/features/groups/application/group_membership_update_listener.dart lib/features/groups/presentation/screens/group_info_wired.dart integration_test/group_multi_device_real_harness.dart integration_test/group_multi_party_device_real_harness.dart lib/main.dart test/core/services/incoming_message_router_test.dart test/features/groups/application/member_removal_integration_test.dart test/features/groups/presentation/group_info_wired_test.dart`
- `flutter test --no-pub test/core/services/incoming_message_router_test.dart --plain-name group_membership_update` (`+1`)
- `flutter test --no-pub test/features/groups/application/member_removal_integration_test.dart` (`+18`)
- `flutter test --no-pub test/features/groups/presentation/group_info_wired_test.dart` (`+41`)
- `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name 'GE-005'` (`+1`)
- `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'GE-005'` (`+2`)
- `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart` (`+148`)
- `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart test/features/groups/integration/group_membership_smoke_test.dart test/features/groups/integration/group_resume_recovery_test.dart` (`+118`)
- Required three-device relay proof passed: `MKNOON_RELAY_ADDRESSES=... dart integration_test/scripts/run_group_multi_party_device_real.dart --scenario ge005 -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469,347FB118-10D0-40C8-A05B-B0C3BD6B8CCD,5BA69F1C-B112-47BE-B1FF-8C1003728C8F`

Device evidence: shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_ge005_bVllxB`, run id `1778657094153`, final orchestrator verdict `ge005 proof passed: ge005 verdicts valid for alice, bob, charlie`. The role verdicts record all 20 remove/re-add cycles: `charlie_ge005_self_removed_01..20`, `charlie_ge005_rejoined_01..20`, `bob_ge005_rotated_key_01..20`, Alice removed-window durable recipients limited to Bob, Bob re-add sends received by Charlie, final epoch 21, final A/B/C membership, and no Charlie removed-window plaintext.

## Current Verdict

Accepted/closed. Source GE-005 is `Covered` with concrete row-owned code, test, analyzer, criteria, broader host, and required three-device relay evidence. Residual-only: none. GE-006 is the next unresolved P0 session.
