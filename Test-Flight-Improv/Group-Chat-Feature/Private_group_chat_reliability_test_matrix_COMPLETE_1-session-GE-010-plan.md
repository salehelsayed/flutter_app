# GE-010 Session Plan: Zero Live Topic Peers Plus Inbox Fallback

Status: accepted

## Gap-Closure Reconciliation

Preflight found GE-010 source row `Open`: Alice sends when Bob and Charlie are not live topic peers, the sender must report the zero-live-peer fallback honestly, and Bob/Charlie must retrieve entitled messages after returning.

The breakdown ledger row 169 classifies GE-010 as `needs_repo_evidence` / `evidence-gated`. Repo inspection found lower-level zero-peer send coverage (`GP-005`/`GP-015` in `send_group_message_use_case_test.dart`) and related GM-035 zero-peer rejoin coverage, but no exact `GE-010` fake-network regression, no `ge010` criteria contract, no `ge010` runner scenario, and no three-device harness path. Because the missing proof/harness pieces are repo-owned, this row is reclassified for execution as `needs_code_and_tests`.

## Scope

- Add exact host fake-network proof for GE-010 zero-live-topic-peer durable fallback.
- Add `ge010` three-role simulator harness/runner support.
- Add `ge010` criteria validation and criteria tests.
- Update source matrix, breakdown, and test inventory only after gates pass.

Out of scope: unrelated GE rows, broad transport refactors, and final program verdict.

## Execution Contract

The row closes only if:

- Alice/Bob/Charlie start from a private group state.
- Bob and Charlie retain group/member/key state but are not live topic peers when Alice sends.
- Alice's send reports `successNoPeers`, `topicPeers == 0`, `status == sent`, and durable inbox custody for Bob and Charlie.
- No live delivery is used for Bob or Charlie during the send window.
- Bob and Charlie return to the topic, drain replay/inbox, and each persist the Alice message exactly once.
- Alice/Bob/Charlie remain converged on final A/B/C membership and key epoch.
- The same contract passes in the three-device `ge010` relay harness.

## Required Gates

| Gate | Command |
|---|---|
| Focused fake-network proof | `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name 'GE-010'` |
| Criteria focused proof | `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'GE-010'` |
| Criteria full regression | `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart` |
| Static analysis | `dart analyze integration_test/scripts/group_multi_party_device_criteria.dart integration_test/scripts/run_group_multi_party_device_real.dart integration_test/group_multi_party_device_real_harness.dart test/integration/group_multi_party_device_criteria_test.dart test/features/groups/integration/group_messaging_smoke_test.dart` |
| Three-device relay proof | `MKNOON_RELAY_ADDRESSES=... dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario ge010 -d <alice,bob,charlie>` |
| Broader group smoke gate | `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart test/features/groups/integration/group_membership_smoke_test.dart test/features/groups/integration/group_resume_recovery_test.dart` |
| Formatting | `dart format --set-exit-if-changed test/features/groups/integration/group_messaging_smoke_test.dart test/integration/group_multi_party_device_criteria_test.dart integration_test/scripts/group_multi_party_device_criteria.dart integration_test/scripts/run_group_multi_party_device_real.dart integration_test/group_multi_party_device_real_harness.dart` |
| Hygiene | `git diff --check` |

## Execution Evidence

Code/test changes:

- Added exact fake-network host proof in `test/features/groups/integration/group_messaging_smoke_test.dart`: `GE-010 zero live topic peers use durable inbox fallback and receivers recover`.
- Added `ge010` device scenario support in `integration_test/group_multi_party_device_real_harness.dart` and `integration_test/scripts/run_group_multi_party_device_real.dart`.
- Added `ge010` criteria validation in `integration_test/scripts/group_multi_party_device_criteria.dart`.
- Added criteria tests in `test/integration/group_multi_party_device_criteria_test.dart` for valid GE-010 proof, dishonest sender fallback proof, and missing receiver inbox recovery proof.

Passed gates:

- Formatting rerun: `dart format --set-exit-if-changed test/features/groups/integration/group_messaging_smoke_test.dart test/integration/group_multi_party_device_criteria_test.dart integration_test/scripts/group_multi_party_device_criteria.dart integration_test/scripts/run_group_multi_party_device_real.dart integration_test/group_multi_party_device_real_harness.dart` -> `Formatted 5 files (0 changed)`.
- Static analysis: `dart analyze integration_test/scripts/group_multi_party_device_criteria.dart integration_test/scripts/run_group_multi_party_device_real.dart integration_test/group_multi_party_device_real_harness.dart test/integration/group_multi_party_device_criteria_test.dart test/features/groups/integration/group_messaging_smoke_test.dart` -> `No issues found!`.
- Focused criteria: `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'GE-010'` passed (`+3`).
- Focused fake-network proof: `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name 'GE-010'` passed (`+1`).
- Full criteria regression: `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart` passed (`+163`).
- Required three-device relay proof: `MKNOON_RELAY_ADDRESSES=... dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario ge010 -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469,347FB118-10D0-40C8-A05B-B0C3BD6B8CCD,5BA69F1C-B112-47BE-B1FF-8C1003728C8F` passed with shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_ge010_28Xi9i`, run id `1778672213356`, and verdict `ge010 proof passed: ge010 verdicts valid for alice, bob, charlie`.
- Broader group host gate: `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart test/features/groups/integration/group_membership_smoke_test.dart test/features/groups/integration/group_resume_recovery_test.dart` passed (`+123`).
- Hygiene: `git diff --check` passed.

## Current Verdict

Accepted/closed for GE-010. The source row is now covered by exact fake-network host proof, `ge010` criteria/runner/device-harness support, scoped static analysis, full criteria regression, broader group host proof, and required three-device relay proof. No product runtime code change was required; the repo-owned gap was missing exact proof and harness support. Residual-only: none for GE-010. GE-011 remains the next unresolved P0 session in ledger order.
