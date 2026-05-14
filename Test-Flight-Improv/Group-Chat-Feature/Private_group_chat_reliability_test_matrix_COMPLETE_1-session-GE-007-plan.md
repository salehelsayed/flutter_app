# GE-007 Session Plan: Remove/Re-add While B Offline Observer Catches Up

Status: accepted

## Gap-Closure Reconciliation

GE-007 source row is `Open`: Alice, Bob, and Charlie start joined; Bob is a remaining member but offline while Alice removes and re-adds Charlie and sends traffic; when Bob returns, Bob must converge on the final membership and receive every message he was entitled to. The breakdown ledger row 166 classifies this as `needs_repo_evidence` / `evidence-gated`, but exact row inspection found repo-owned missing proof support: there is no dedicated GE-007 fake-network regression, no `ge007` criteria contract, no runner scenario, and no three-device harness path.

GE-006 does not close GE-007 because GE-006 proves the removed/re-added member catches up after being offline. GE-007 instead proves an offline remaining observer catches up across the same mutation window.

## Scope

- Add exact host fake-network proof for GE-007.
- Add `ge007` three-role simulator harness/runner support.
- Add `ge007` criteria validation and criteria tests.
- Update source matrix, breakdown, and test inventory only after gates pass.

Out of scope: unrelated GE rows, broad key-rotation policy changes, unrelated membership surfaces, and final program verdict.

## Execution Contract

The row closes only if:

- Alice/Bob/Charlie start in one private group.
- Bob is offline before Alice removes Charlie and remains offline through Charlie re-add plus post-readd sends.
- Alice removes Charlie and sends a removed-window message that Bob is entitled to and receives only after inbox catch-up.
- Alice re-adds Charlie; Alice and Charlie send post-readd messages with durable recipients including Bob.
- Bob reconnects, drains replay, renders exactly the removed-window message plus post-readd messages he was entitled to, and final membership contains Alice, Bob, and Charlie.
- Bob can send after catch-up and Alice/Charlie receive it exactly once.
- The same contract passes in the three-simulator `ge007` relay harness.

## Required Gates

| Gate | Command |
|---|---|
| Focused fake-network proof | `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name 'GE-007'` |
| Criteria focused proof | `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'GE-007'` |
| Criteria full regression | `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart` |
| Static analysis | `flutter analyze --no-pub integration_test/scripts/group_multi_party_device_criteria.dart integration_test/scripts/run_group_multi_party_device_real.dart integration_test/group_multi_party_device_real_harness.dart test/integration/group_multi_party_device_criteria_test.dart test/features/groups/integration/group_messaging_smoke_test.dart` |
| Three-device relay proof | `MKNOON_RELAY_ADDRESSES=... dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario ge007 -d <alice,bob,charlie>` |
| Broader group smoke gate | `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart test/features/groups/integration/group_membership_smoke_test.dart test/features/groups/integration/group_resume_recovery_test.dart` |
| Formatting | `dart format --set-exit-if-changed test/features/groups/integration/group_messaging_smoke_test.dart integration_test/scripts/group_multi_party_device_criteria.dart integration_test/scripts/run_group_multi_party_device_real.dart integration_test/group_multi_party_device_real_harness.dart test/integration/group_multi_party_device_criteria_test.dart` |
| Hygiene | `git diff --check` |

## Execution Evidence

| Gate | Result |
|---|---|
| Focused fake-network proof | `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name 'GE-007'` passed (`+1`). |
| Criteria focused proof | `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'GE-007'` passed (`+3`). |
| Criteria full regression | `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart` passed (`+154`). |
| Static analysis | `flutter analyze --no-pub integration_test/scripts/group_multi_party_device_criteria.dart integration_test/scripts/run_group_multi_party_device_real.dart integration_test/group_multi_party_device_real_harness.dart test/integration/group_multi_party_device_criteria_test.dart test/features/groups/integration/group_messaging_smoke_test.dart` passed with no issues. |
| Three-device relay proof | `MKNOON_RELAY_ADDRESSES=/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario ge007 -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469,347FB118-10D0-40C8-A05B-B0C3BD6B8CCD,5BA69F1C-B112-47BE-B1FF-8C1003728C8F` passed. Shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_ge007_ayKyo8`, run id `1778666286428`, verdict `ge007 proof passed: ge007 verdicts valid for alice, bob, charlie`. |
| Broader group smoke gate | `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart test/features/groups/integration/group_membership_smoke_test.dart test/features/groups/integration/group_resume_recovery_test.dart` passed (`+120`). |
| Formatting | `dart format --set-exit-if-changed test/features/groups/integration/group_messaging_smoke_test.dart test/integration/group_multi_party_device_criteria_test.dart integration_test/scripts/group_multi_party_device_criteria.dart integration_test/scripts/run_group_multi_party_device_real.dart integration_test/group_multi_party_device_real_harness.dart` passed (`Formatted 5 files (0 changed)`). |
| Hygiene | `git diff --check -- test/features/groups/integration/group_messaging_smoke_test.dart test/integration/group_multi_party_device_criteria_test.dart integration_test/scripts/group_multi_party_device_criteria.dart integration_test/scripts/run_group_multi_party_device_real.dart integration_test/group_multi_party_device_real_harness.dart` passed. |

## Current Verdict

Closed/accepted on 2026-05-13. GE-007 is covered by row-owned fake-network proof plus repo-owned `ge007` criteria, runner, and three-device harness support in `test/features/groups/integration/group_messaging_smoke_test.dart`, `test/integration/group_multi_party_device_criteria_test.dart`, `integration_test/scripts/group_multi_party_device_criteria.dart`, `integration_test/scripts/run_group_multi_party_device_real.dart`, and `integration_test/group_multi_party_device_real_harness.dart`.

The host proof verifies Bob is offline before Charlie removal through re-add and post-readd sends, Alice's removed-window message is durable to Bob, Alice/Charlie post-readd messages include Bob as a durable recipient, Bob drains exactly the three entitled messages after reconnect, Bob's final membership is Alice/Bob/Charlie, and Bob's post-catch-up send reaches Alice and Charlie. The required three-device relay verdict validates the same contract with Alice, Bob, and Charlie role verdicts. Residual-only: none for GE-007.
