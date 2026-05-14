# GE-003 Session Plan: A Removes C, Then B Sends to A

Status: accepted/closed

## Gap-Closure Reconciliation

At the start of this GE-003 pass, the source row was `Open`: A/B remain after Alice removes Charlie, Bob sends 10 messages, Alice must receive all, and Charlie's stale state must not disrupt the remaining pair. The breakdown session ledger and ordered row 162 classified GE-003 as `needs_code_and_tests` / `implementation-ready` before closure. No adjacent GE-003 plan existed before this pass. Existing GE-002 proof covers Alice sending to Bob after removal; it does not cover the reverse remaining-member direction where Bob sends to Alice. The gap was repo-owned because the fake-network smoke test, multi-party simulator harness, criteria validator, and runner all live in this repo.

## Scope

- Add exact host fake-network proof for GE-003.
- Add `ge003` three-role simulator harness support.
- Add `ge003` criteria validation and tests.
- Update the source matrix and breakdown only after gates pass.

Out of scope: product behavior changes unless the exact GE-003 proof fails for a product reason.

## Execution Contract

The row closes only if:

- Alice/Bob/Charlie start in one private group.
- Alice removes Charlie.
- Bob sends exactly 10 post-removal messages.
- Alice persists every post-removal Bob message exactly once.
- Charlie persists none of those post-removal messages.
- Durable recipient proof for Bob's sends excludes Charlie and includes Alice only.
- The same contract passes in the three-simulator `ge003` relay harness.

## Required Gates

| Gate | Command |
|---|---|
| Focused fake-network proof | `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name 'GE-003'` |
| Criteria focused proof | `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'GE-003'` |
| Criteria full regression | `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart` |
| Static analysis | `dart analyze integration_test/scripts/group_multi_party_device_criteria.dart integration_test/scripts/run_group_multi_party_device_real.dart integration_test/group_multi_party_device_real_harness.dart test/integration/group_multi_party_device_criteria_test.dart test/features/groups/integration/group_messaging_smoke_test.dart` |
| Three-device relay proof | `MKNOON_RELAY_ADDRESSES=... dart integration_test/scripts/run_group_multi_party_device_real.dart --scenario ge003 -d <alice,bob,charlie>` |
| Broader group smoke gate | `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart test/features/groups/integration/group_membership_smoke_test.dart test/features/groups/integration/group_resume_recovery_test.dart` |
| Formatting | `dart format --set-exit-if-changed integration_test/scripts/group_multi_party_device_criteria.dart integration_test/scripts/run_group_multi_party_device_real.dart integration_test/group_multi_party_device_real_harness.dart test/integration/group_multi_party_device_criteria_test.dart test/features/groups/integration/group_messaging_smoke_test.dart` |
| Hygiene | `git diff --check` |

## Device/Relay Proof Profile

| Role | Device | Simulator |
|---|---|---|
| Alice | `38FECA55-03C1-4907-BD9D-8E64BF8E3469` | iPhone 17 Pro, iOS 26.1 |
| Bob | `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD` | iPhone Air, iOS 26.1 |
| Charlie | `5BA69F1C-B112-47BE-B1FF-8C1003728C8F` | iPhone 17, iOS 26.1 |

Command:

```sh
MKNOON_RELAY_ADDRESSES=/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g dart integration_test/scripts/run_group_multi_party_device_real.dart --scenario ge003 -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469,347FB118-10D0-40C8-A05B-B0C3BD6B8CCD,5BA69F1C-B112-47BE-B1FF-8C1003728C8F
```

Relay proof passed with shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_ge003_HDMm20`, run id `1778650374836`, and orchestrator verdict `ge003 proof passed: ge003 verdicts valid for alice, bob, charlie`.

## Execution Evidence

| Gate | Result |
|---|---|
| Formatting | `dart format --set-exit-if-changed integration_test/scripts/group_multi_party_device_criteria.dart integration_test/scripts/run_group_multi_party_device_real.dart integration_test/group_multi_party_device_real_harness.dart test/integration/group_multi_party_device_criteria_test.dart test/features/groups/integration/group_messaging_smoke_test.dart` passed after the first run formatted `integration_test/scripts/group_multi_party_device_criteria.dart`. |
| Static analysis | `dart analyze integration_test/scripts/group_multi_party_device_criteria.dart integration_test/scripts/run_group_multi_party_device_real.dart integration_test/group_multi_party_device_real_harness.dart test/integration/group_multi_party_device_criteria_test.dart test/features/groups/integration/group_messaging_smoke_test.dart` passed with no issues. |
| Focused fake-network proof | `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name 'GE-003'` passed (`+1`). |
| Criteria focused proof | `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'GE-003'` passed (`+2`). |
| Criteria full regression | `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart` passed (`+144`). |
| Three-device relay proof | Required `ge003` relay command passed with Alice/Bob/Charlie devices above and verdict `ge003 proof passed: ge003 verdicts valid for alice, bob, charlie`. |
| Broader group smoke gate | `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart test/features/groups/integration/group_membership_smoke_test.dart test/features/groups/integration/group_resume_recovery_test.dart` passed (`+116`). |
| Hygiene | `git diff --check` passed before closure docs. |

## Final Verdict

Accepted/closed. GE-003 is covered by exact fake-network proof plus required three-simulator relay evidence. The implementation added `ge003` host smoke, criteria validation/tests, runner support, and three-role harness support. Alice removes Charlie, Bob sends ten post-removal messages, Alice receives all ten exactly once, durable recipient proof excludes Charlie and includes Alice only, and Charlie receives none of Bob's post-removal plaintext. No product runtime code change was required because the existing private group removal and delivery path satisfied the row once exact proof and harness coverage were added. Residual-only none for GE-003; GE-005 is the next unresolved P0 session.
