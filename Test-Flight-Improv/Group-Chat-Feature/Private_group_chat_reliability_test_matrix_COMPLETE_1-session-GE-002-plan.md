# GE-002 Session Plan: A Removes C, B Keeps Receiving A

Status: accepted/closed

## Gap-Closure Reconciliation

GE-002 source row is still `Open`: A/B/C are joined, Alice removes Charlie, Alice sends 10 messages, Bob must see all 10, and Charlie must see none after the removal cutoff. The breakdown session ledger and ordered row 161 still classify GE-002 as `needs_repo_evidence` / `evidence-gated`. No adjacent GE-002 plan existed before this pass, and existing GM-004/GM-020 evidence covers related removal behavior but not this row's exact 10-message continuity contract. The gap is repo-owned because the fake-network smoke test, multi-party simulator harness, criteria validator, and runner all live in this repo.

## Scope

- Add exact host fake-network proof for GE-002.
- Add `ge002` three-role simulator harness support.
- Add `ge002` criteria validation and tests.
- Update the source matrix and breakdown only after gates pass.

Out of scope: product behavior changes unless the exact GE-002 proof fails for a product reason.

## Execution Contract

The row closes only if:

- Alice/Bob/Charlie start in one private group.
- Alice removes Charlie.
- Alice sends exactly 10 post-removal messages.
- Bob persists every post-removal Alice message exactly once.
- Charlie persists none of those post-removal messages.
- Durable recipient proof for Alice's sends excludes Charlie and includes Bob only.
- The same contract passes in the three-simulator `ge002` relay harness.

## Required Gates

| Gate | Command |
|---|---|
| Focused fake-network proof | `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name 'GE-002'` |
| Criteria focused proof | `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'GE-002'` |
| Criteria full regression | `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart` |
| Static analysis | `dart analyze integration_test/scripts/group_multi_party_device_criteria.dart integration_test/scripts/run_group_multi_party_device_real.dart integration_test/group_multi_party_device_real_harness.dart test/integration/group_multi_party_device_criteria_test.dart test/features/groups/integration/group_messaging_smoke_test.dart` |
| Three-device relay proof | `MKNOON_RELAY_ADDRESSES=... dart integration_test/scripts/run_group_multi_party_device_real.dart --scenario ge002 -d <alice,bob,charlie>` |
| Broader group smoke gate | `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart test/features/groups/integration/group_membership_smoke_test.dart test/features/groups/integration/group_resume_recovery_test.dart` |
| Formatting | `dart format --set-exit-if-changed integration_test/scripts/group_multi_party_device_criteria.dart integration_test/scripts/run_group_multi_party_device_real.dart integration_test/group_multi_party_device_real_harness.dart test/integration/group_multi_party_device_criteria_test.dart test/features/groups/integration/group_messaging_smoke_test.dart` |
| Hygiene | `git diff --check` |

## Device/Relay Proof Profile

Required three-role relay proof used currently booted iOS simulators:

| Role | Device ID |
|---|---|
| Alice | `38FECA55-03C1-4907-BD9D-8E64BF8E3469` |
| Bob | `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD` |
| Charlie | `5BA69F1C-B112-47BE-B1FF-8C1003728C8F` |

Relay command:

```sh
MKNOON_RELAY_ADDRESSES=/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g dart integration_test/scripts/run_group_multi_party_device_real.dart --scenario ge002 -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469,347FB118-10D0-40C8-A05B-B0C3BD6B8CCD,5BA69F1C-B112-47BE-B1FF-8C1003728C8F
```

The run passed with shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_ge002_Bl4Jlh`, run id `1778649273954`, and orchestrator verdict `ge002 proof passed: ge002 verdicts valid for alice, bob, charlie`.

Compact verdict facts:

- Alice: key epoch 1, remaining members Alice/Bob only, ten sent post-removal messages, `removedCharlie == true`, `actualDurablePayloadProof == true`, `everyPostRemovalExcludedCharlie == true`, and `postRemovalMessageCount == 10`.
- Bob: key epoch 1, remaining members Alice/Bob only, ten received post-removal messages, `receivedEveryPostRemovalMessage == true`, and `postRemovalReceiptCount == 10`.
- Charlie: key epoch 0, no active member list, zero received post-removal messages, `selfRemoved == true`, `groupPresentAfterRemoval == false`, `postRemovalPlaintextCount == 0`, and `checkedPostRemovalMessageCount == 10`.

## Execution Evidence

| Gate | Result |
|---|---|
| Formatting | `dart format --set-exit-if-changed integration_test/scripts/group_multi_party_device_criteria.dart integration_test/scripts/run_group_multi_party_device_real.dart integration_test/group_multi_party_device_real_harness.dart test/integration/group_multi_party_device_criteria_test.dart test/features/groups/integration/group_messaging_smoke_test.dart` passed after formatting touched files once; rerun reported `Formatted 5 files (0 changed)`. |
| Static analysis | `dart analyze integration_test/scripts/group_multi_party_device_criteria.dart integration_test/scripts/run_group_multi_party_device_real.dart integration_test/group_multi_party_device_real_harness.dart test/integration/group_multi_party_device_criteria_test.dart test/features/groups/integration/group_messaging_smoke_test.dart` passed with `No issues found!`. |
| Focused fake-network proof | `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name 'GE-002'` passed (`+1`). |
| Criteria focused proof | `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'GE-002'` passed (`+2`). |
| Criteria full regression | `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart` passed (`+142`). |
| Three-device relay proof | Required `ge002` relay scenario passed with Alice/Bob/Charlie device verdicts valid. |
| Broader group smoke gate | `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart test/features/groups/integration/group_membership_smoke_test.dart test/features/groups/integration/group_resume_recovery_test.dart` passed (`+115`). |
| Hygiene | `git diff --check` passed before closure documentation updates. |

## Final Verdict

Accepted/closed. GE-002 is now covered by row-owned fake-network proof, repo-owned criteria and device harness support, required three-simulator relay evidence, focused and broad host regressions, static analysis, formatting, and diff hygiene. No product runtime code change was required beyond test/harness coverage because existing private group removal, durable inbox targeting, and listener behavior satisfied the row once exact proof existed. Residual-only none for GE-002; GE-005 is the next unresolved P0 session in ledger order.
