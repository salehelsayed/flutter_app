# GE-004 Session Plan: A Re-adds C, All Three Exchange Messages

Status: accepted/closed

## Gap-Closure Reconciliation

GE-004 source row is `Open`: Charlie was removed, Alice re-adds Charlie, then Alice, Bob, and Charlie each send and all active members must receive every post-readd message exactly once. The breakdown session ledger and ordered row 163 classify GE-004 as `needs_repo_evidence` / `evidence-gated`, but reconciliation reclassifies it as repo-owned runnable work because exact fake-network proof, criteria validation, runner support, and the three-role simulator harness all live in this repo. Existing GM re-add rows cover related membership mechanics, but they do not close GE-004's exact A/B/C post-readd all-send exchange contract.

## Scope

- Add exact host fake-network proof for GE-004.
- Add `ge004` three-role simulator harness support.
- Add `ge004` criteria validation and tests.
- Update the source matrix and breakdown only after gates pass.

Out of scope: product behavior changes unless the exact GE-004 proof fails for a product reason.

## Execution Contract

The row closes only if:

- Alice/Bob/Charlie start in one private group.
- Alice removes Charlie and remaining members converge.
- Alice re-adds Charlie and all three active members converge.
- Alice, Bob, and Charlie each send one post-readd message.
- Each participant persists its own outgoing message once and the two other post-readd messages exactly once.
- Every durable recipient proof targets the two non-sender active members and excludes the sender.
- The same contract passes in the three-simulator `ge004` relay harness.

## Required Gates

| Gate | Command |
|---|---|
| Focused fake-network proof | `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name 'GE-004'` |
| Criteria focused proof | `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'GE-004'` |
| Criteria full regression | `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart` |
| Static analysis | `dart analyze integration_test/scripts/group_multi_party_device_criteria.dart integration_test/scripts/run_group_multi_party_device_real.dart integration_test/group_multi_party_device_real_harness.dart test/integration/group_multi_party_device_criteria_test.dart test/features/groups/integration/group_messaging_smoke_test.dart test/shared/fakes/group_test_user.dart` |
| Three-device relay proof | `MKNOON_RELAY_ADDRESSES=... dart integration_test/scripts/run_group_multi_party_device_real.dart --scenario ge004 -d <alice,bob,charlie>` |
| Broader group smoke gate | `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart test/features/groups/integration/group_membership_smoke_test.dart test/features/groups/integration/group_resume_recovery_test.dart` |
| Formatting | `dart format --set-exit-if-changed test/shared/fakes/group_test_user.dart test/features/groups/integration/group_messaging_smoke_test.dart` |
| Hygiene | `git diff --check` |

## Device/Relay Proof Profile

| Role | Device | Simulator |
|---|---|---|
| Alice | `38FECA55-03C1-4907-BD9D-8E64BF8E3469` | iPhone 17 Pro, iOS 26.1 |
| Bob | `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD` | iPhone Air, iOS 26.1 |
| Charlie | `5BA69F1C-B112-47BE-B1FF-8C1003728C8F` | iPhone 17, iOS 26.1 |

Command:

```sh
MKNOON_RELAY_ADDRESSES=/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g dart integration_test/scripts/run_group_multi_party_device_real.dart --scenario ge004 -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469,347FB118-10D0-40C8-A05B-B0C3BD6B8CCD,5BA69F1C-B112-47BE-B1FF-8C1003728C8F
```

Relay proof passed with shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_ge004_c4neXY`, run id `1778651826540`, and orchestrator verdict `ge004 proof passed: ge004 verdicts valid for alice, bob, charlie`.

## Execution Evidence

| Gate | Result |
|---|---|
| Formatting | `dart format --set-exit-if-changed test/shared/fakes/group_test_user.dart test/features/groups/integration/group_messaging_smoke_test.dart` passed with no changes. |
| Static analysis | `dart analyze integration_test/scripts/group_multi_party_device_criteria.dart integration_test/scripts/run_group_multi_party_device_real.dart integration_test/group_multi_party_device_real_harness.dart test/integration/group_multi_party_device_criteria_test.dart test/features/groups/integration/group_messaging_smoke_test.dart test/shared/fakes/group_test_user.dart` passed with no issues. |
| Focused fake-network proof | Initial focused GE-004 run exposed a deterministic timestamp gap in the fake membership helper; after adding `broadcastMemberAdded(eventAt:)` and using the re-add event time, `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name 'GE-004'` passed (`+1`). |
| Criteria focused proof | `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'GE-004'` passed (`+2`). |
| Criteria full regression | `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart` passed (`+146`). |
| Three-device relay proof | Required `ge004` relay command passed with Alice/Bob/Charlie devices above and verdict `ge004 proof passed: ge004 verdicts valid for alice, bob, charlie`. |
| Broader group smoke gate | `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart test/features/groups/integration/group_membership_smoke_test.dart test/features/groups/integration/group_resume_recovery_test.dart` passed (`+117`). |
| Hygiene | `git diff --check` passed before closure docs. |

## Final Verdict

Accepted/closed. GE-004 is covered by exact fake-network proof plus required three-simulator relay evidence. The implementation added the GE-004 host smoke, criteria validation/tests, runner support, and three-role harness support, and updated `test/shared/fakes/group_test_user.dart` so re-add membership events can use deterministic event timestamps. Alice removes Charlie, re-adds Charlie, Alice/Bob/Charlie each send one post-readd message, every durable target set includes exactly the two non-sender active members, and all three timelines contain exactly one outgoing self row plus two incoming post-readd rows with no failed/pending state. No product runtime code change was required. Residual-only none for GE-004; GE-005 is the next unresolved P0 session.
