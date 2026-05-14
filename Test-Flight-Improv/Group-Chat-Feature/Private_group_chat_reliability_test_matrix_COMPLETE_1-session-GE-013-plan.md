# GE-013 Session Plan: Device Revocation During Active Group

Status: accepted

## Gap-Closure Reconciliation

At session start, preflight found this source row unresolved. Its status at that time was `Open`. Bob device 2 is revoked while Bob device 1 remains active; B2 must be able to send before revocation, B2 post-revoke sends must be rejected, Alice/B1 must receive entitled traffic, and Alice/B1 must remain functional after the revoke. Closure later updated the source row to `Covered` with the evidence below.

At session start, breakdown ledger row 172 carried the old `needs_repo_evidence` / `evidence-gated` classification for this session. Supporting lower-level evidence existed in Go GA-013 revoked-device validation and Flutter GI-022 revoked-device replay tests, but those did not close the source row because they did not prove the exact private-group A/B1/B2 active-group revocation flow. The missing fake-network row proof, criteria contract, runner scenario, and three-device harness path were repo-owned, so this row was reclassified for this session as `needs_code_and_tests`.

## Scope

- Add exact host fake-network proof for Alice, Bob primary device B1, and Bob sibling device B2.
- Prove B2 sends before revocation, B2 is rejected after its device identity is revoked, and B1/Alice remain able to exchange messages.
- Add `ge013` three-role simulator harness/runner support where `charlie` acts as Bob's sibling B2 device.
- Add `ge013` criteria validation and criteria tests.
- Update source matrix, breakdown, and test inventory only after gates pass.

Out of scope: account deletion, full member removal, UI device-management screens, and unrelated property tests.

## Execution Contract

The row closes only if:

- Alice, Bob primary, and Bob sibling start from one private group where Bob is one logical member with two active devices.
- Bob sibling B2 sends before revocation and Alice/B1 receive that message exactly once.
- B2's group member device identity is revoked while B1 remains active in the same logical Bob member row.
- B2 post-revoke send is rejected locally as unauthorized/unbound and no post-revoke B2 plaintext appears on Alice or B1.
- B1 remains functional after the revoke by sending to Alice.
- Alice remains functional after the revoke by sending to B1.
- The exact contract passes in the three-device `ge013` relay harness.

## Required Gates

| Gate | Command |
|---|---|
| Focused fake-network proof | `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name 'GE-013'` |
| Criteria focused proof | `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'GE-013'` |
| Criteria full regression | `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart` |
| Static analysis | `dart analyze integration_test/scripts/group_multi_party_device_criteria.dart integration_test/scripts/run_group_multi_party_device_real.dart integration_test/group_multi_party_device_real_harness.dart integration_test/group_multi_device_real_harness.dart test/integration/group_multi_party_device_criteria_test.dart test/features/groups/integration/group_messaging_smoke_test.dart` |
| Three-device relay proof | `MKNOON_RELAY_ADDRESSES=... dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario ge013 -d <alice,bob-primary,bob-sibling>` |
| Broader group smoke gate | `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart test/features/groups/integration/group_membership_smoke_test.dart test/features/groups/integration/group_resume_recovery_test.dart` |
| Formatting | `dart format --set-exit-if-changed integration_test/group_multi_party_device_real_harness.dart integration_test/scripts/group_multi_party_device_criteria.dart integration_test/scripts/run_group_multi_party_device_real.dart test/integration/group_multi_party_device_criteria_test.dart test/features/groups/integration/group_messaging_smoke_test.dart` |
| Hygiene | `git diff --check` |

## Execution Evidence

| Gate | Result |
|---|---|
| Focused fake-network proof | `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name 'GE-013'` passed (`+1`). |
| Criteria focused proof | `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'GE-013'` passed (`+3`). |
| Criteria full regression | `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart` passed (`+172`). |
| Static analysis | Scoped `dart analyze` over GE-013 harness, criteria, runner, and test files passed with `No issues found!`. |
| Broader group smoke gate | `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart test/features/groups/integration/group_membership_smoke_test.dart test/features/groups/integration/group_resume_recovery_test.dart` passed (`+126`). |
| Required three-device relay proof | `MKNOON_RELAY_ADDRESSES=... dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario ge013 -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469,347FB118-10D0-40C8-A05B-B0C3BD6B8CCD,5BA69F1C-B112-47BE-B1FF-8C1003728C8F` passed. Shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_ge013_ypH6Cb`, run id `1778677974482`, verdict `ge013 proof passed: ge013 verdicts valid for alice, bob, charlie`. |
| Formatting and hygiene | `dart format --set-exit-if-changed ...` reported `Formatted 5 files (0 changed)`; `git diff --check` passed. |

## Current Verdict

Accepted/closed. GE-013 is covered with exact host and criteria coverage, broader group regression evidence, and the required three-device relay proof. Residual-only: none. GE-014 is the next unresolved P0 session.
