# GE-009 Session Plan: Network Partition Heals After Membership Mutation

Status: accepted

## Gap-Closure Reconciliation

Preflight found GE-009 source row `Open`: Alice and Bob are in one partition while Charlie is isolated, Alice removes and re-adds Charlie, the partition heals, and replay/inbox recovery must leave all peers converged on final membership, key epoch, and entitled message set. The breakdown ledger row 168 classifies this as `needs_repo_evidence` / `evidence-gated`.

Repo inspection found adjacent GE-006, GE-007, and GE-008 coverage, but no exact `GE-009` fake-network regression, no `ge009` criteria contract, no `ge009` runner scenario, and no three-device harness path. Because the missing proof/harness pieces are repo-owned, this row is reclassified for execution as `needs_code_and_tests`.

## Scope

- Add exact host fake-network proof for GE-009 partition-heal convergence.
- Add `ge009` three-role simulator harness/runner support.
- Add `ge009` criteria validation and criteria tests.
- Update source matrix, breakdown, and test inventory only after gates pass.

Out of scope: unrelated GE rows, media/quote rows, broad transport refactors, and final program verdict.

## Execution Contract

The row closes only if:

- Alice/Bob/Charlie start from a private group state.
- Charlie is isolated from live topic delivery while Alice removes and re-adds Charlie.
- Alice/Bob converge on removal and re-add, and Charlie receives no removed-window plaintext.
- Alice/Bob send post-readd messages while Charlie is still isolated; those messages are durable for Charlie.
- After partition heal, Charlie drains replay/inbox, receives the post-readd messages exactly once, and can send a post-heal message to Alice/Bob.
- Alice, Bob, and Charlie converge to the same final active membership, key epoch, and GE-009 proof message set.
- The same contract passes in the three-simulator `ge009` relay harness.

## Required Gates

| Gate | Command |
|---|---|
| Focused fake-network proof | `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name 'GE-009'` |
| Criteria focused proof | `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'GE-009'` |
| Criteria full regression | `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart` |
| Static analysis | `dart analyze integration_test/scripts/group_multi_party_device_criteria.dart integration_test/scripts/run_group_multi_party_device_real.dart integration_test/group_multi_party_device_real_harness.dart test/integration/group_multi_party_device_criteria_test.dart test/features/groups/integration/group_messaging_smoke_test.dart` |
| Three-device relay proof | `MKNOON_RELAY_ADDRESSES=... dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario ge009 -d <alice,bob,charlie>` |
| Broader group smoke gate | `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart test/features/groups/integration/group_membership_smoke_test.dart test/features/groups/integration/group_resume_recovery_test.dart` |
| Formatting | `dart format --set-exit-if-changed test/features/groups/integration/group_messaging_smoke_test.dart test/integration/group_multi_party_device_criteria_test.dart integration_test/scripts/group_multi_party_device_criteria.dart integration_test/scripts/run_group_multi_party_device_real.dart integration_test/group_multi_party_device_real_harness.dart` |
| Hygiene | `git diff --check` |

## Execution Evidence

Files changed for GE-009:

- `test/features/groups/integration/group_messaging_smoke_test.dart`
- `integration_test/scripts/group_multi_party_device_criteria.dart`
- `integration_test/scripts/run_group_multi_party_device_real.dart`
- `integration_test/group_multi_party_device_real_harness.dart`
- `test/integration/group_multi_party_device_criteria_test.dart`

The exact fake-network host proof `GE-009 network partition heals after membership mutation and replay converges` now creates Alice/Bob/Charlie private group state, isolates Charlie from live topic delivery, removes and re-adds Charlie while isolated, sends Alice/Bob post-readd messages that remain durable for Charlie, heals Charlie through topic resubscribe plus inbox replay, proves Charlie receives exactly the post-readd messages, proves Charlie's post-heal send reaches Alice/Bob, and verifies common final membership, key epoch, and GE-009 proof timeline.

The repo-owned `ge009` criteria/runner/harness support now validates the same contract for all three roles, including partition/mutation/heal markers, final membership and timeline convergence, Charlie replay-drain proof, removed-window leak rejection, duplicate delivery de-dupe, and durable recipient proof for all GE-009 sends.

Gate evidence:

- `dart format --set-exit-if-changed ...GE-009 touched files...` passed on rerun: `Formatted 5 files (0 changed)`.
- `dart analyze integration_test/scripts/group_multi_party_device_criteria.dart integration_test/scripts/run_group_multi_party_device_real.dart integration_test/group_multi_party_device_real_harness.dart test/integration/group_multi_party_device_criteria_test.dart test/features/groups/integration/group_messaging_smoke_test.dart` passed: `No issues found!`.
- `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name 'GE-009'` passed: `+1 All tests passed!`.
- `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'GE-009'` passed: `+3 All tests passed!`.
- `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart` passed: `+160 All tests passed!`.
- `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart test/features/groups/integration/group_membership_smoke_test.dart test/features/groups/integration/group_resume_recovery_test.dart` passed: `+122 All tests passed!`.
- Required three-device relay proof passed with Alice `38FECA55-03C1-4907-BD9D-8E64BF8E3469`, Bob `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD`, Charlie `5BA69F1C-B112-47BE-B1FF-8C1003728C8F`; shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_ge009_HzR9rw`, run id `1778670455217`, verdict `ge009 proof passed: ge009 verdicts valid for alice, bob, charlie`.
- `git diff --check` passed after closure docs.

## Current Verdict

Accepted. GE-009 is Covered/closed with exact host partition-heal proof, criteria/runner/harness coverage, required three-device relay proof, and source matrix/breakdown/test inventory evidence. Residual-only: none. Continue to GE-010.
