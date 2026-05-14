# GE-021 Session Plan: Large Group With One Flaky Member

## Status

Status: accepted/closed

## Source Row

Source matrix row: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` row `GE-021`

## Gap-Closure Reconciliation

| Time | Actor | Inputs Compared | Finding | Action |
|---|---|---|---|---|
| 2026-05-14 06:01 CEST | Controller | Source matrix GE-021 row; breakdown session ledger row 223; existing group messaging/membership/resume tests; `ge021` criteria/runner/harness absence; current relay-backed three-device proof requirements | The source row was still `Open` while the breakdown classified the row as `needs_repo_evidence`/`evidence-gated`. No exact host proof or required multi-party `ge021` device proof existed. The first device attempt exposed a repo-owned harness prerequisite: synthetic large-group members used fake ML-KEM key material, causing Alice key rotation distribution to fail before the row could be proven. | Reclassify GE-021 as `needs_code_and_tests`, add the exact large-group flaky-member host regression, add `ge021` criteria/runner/harness support, generate real synthetic public crypto material and stub only synthetic transport acknowledgements, then rerun focused, adjacent, analyzer, and required relay-backed device proof gates. |

## Scope

GE-021 owns large private group delivery reliability when one member repeatedly goes offline/online and is removed/readded. The row closes when stable entitled members do not miss messages because one peer is flaky, and the required relay-backed proof validates the same contract with a large roster, real devices, and synthetic stable members.

Out of scope: media/attachments, quoted replies, non-repo external relay behavior changes, unrelated group UI flows, and later GE-023+ rows.

## Execution Contract

1. Add an exact host test named `GE-021 large group with one flaky member preserves stable delivery`.
2. Exercise at least 10 members with one flaky member offline/online, removed, and readded.
3. Prove stable members receive all entitled messages across the flaky member churn.
4. Add `ge021` support to the multi-party device harness, runner, and criteria validator.
5. Ensure synthetic large-group members use valid generated public crypto material so key rotation distribution exercises the real encryption path.
6. Stub only test-owned synthetic transport acknowledgements while real Alice/Bob/Charlie transport remains relay-backed.
7. Update the source matrix, breakdown ledger, and test inventory with concrete file/test/gate evidence.

## Device/Relay Proof Profile

Profile: `three-party/device-lab` plus synthetic stable members.

Required closure evidence uses the configured group real-network relay addresses:

```sh
MKNOON_RELAY_ADDRESSES=/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g \
  dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario ge021 -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469,347FB118-10D0-40C8-A05B-B0C3BD6B8CCD,5BA69F1C-B112-47BE-B1FF-8C1003728C8F
```

The three configured iOS targets represent Alice, Bob, and flaky Charlie. The harness adds eight synthetic stable members with generated crypto material to reach an 11-member roster.

## Required Gates

| Gate | Command |
|---|---|
| Format | `dart format integration_test/group_multi_party_device_real_harness.dart integration_test/scripts/run_group_multi_party_device_real.dart integration_test/scripts/group_multi_party_device_criteria.dart test/integration/group_multi_party_device_criteria_test.dart test/features/groups/integration/group_messaging_smoke_test.dart` |
| Focused GE-021 host proof | `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name 'GE-021 large group with one flaky member preserves stable delivery'` |
| Full criteria proof | `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart` |
| Scoped analyzer | `dart analyze integration_test/group_multi_party_device_real_harness.dart integration_test/scripts/run_group_multi_party_device_real.dart integration_test/scripts/group_multi_party_device_criteria.dart test/integration/group_multi_party_device_criteria_test.dart test/features/groups/integration/group_messaging_smoke_test.dart test/features/groups/integration/group_membership_smoke_test.dart test/shared/fakes/group_test_user.dart` |
| Adjacent group integration proof | `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart test/features/groups/integration/group_membership_smoke_test.dart test/features/groups/integration/group_resume_recovery_test.dart` |
| Required relay-backed three-party proof | `MKNOON_RELAY_ADDRESSES=/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario ge021 -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469,347FB118-10D0-40C8-A05B-B0C3BD6B8CCD,5BA69F1C-B112-47BE-B1FF-8C1003728C8F` |
| Hygiene | `git diff --check` |

## Dirty Worktree Snapshot

Captured before closure: worktree remained dirty with prior gap-closure rollout changes and accepted session artifacts. GE-021 scope is limited to the row-owned large-group host proof, `ge021` multi-party criteria/runner/harness support, synthetic large-group crypto fixture repair, this adjacent plan, source/breakdown closure updates, and test inventory entries.

## Execution Evidence

Implemented row-owned host coverage in `test/features/groups/integration/group_messaging_smoke_test.dart::GE-021 large group with one flaky member preserves stable delivery`. The test uses an 11-member private group, sends from several stable members, repeatedly holds/releases flaky-member delivery, removes and readds the flaky member, and proves all stable entitled members retain the expected message set with no stable delivery loss caused by the flaky peer.

Added required relay-backed `ge021` support in:

- `integration_test/group_multi_party_device_real_harness.dart`
- `integration_test/scripts/run_group_multi_party_device_real.dart`
- `integration_test/scripts/group_multi_party_device_criteria.dart`
- `test/integration/group_multi_party_device_criteria_test.dart`

The device scenario runs Alice and Bob as stable real devices, Charlie as the flaky real device, and eight synthetic stable members. It proves initial stable delivery, flaky live leave/rejoin, removal and readd, removed-window exclusion, final roster and epoch convergence, and no stable-member miss, stranded delivery, or removed-window plaintext leak. The harness now generates real synthetic signing and ML-KEM public material for large-group fixtures and only stubs P2P send acknowledgements for synthetic transport peer IDs.

## Verification

| Gate | Result |
|---|---|
| Dart format on GE-021 owner files | Passed. |
| `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name 'GE-021 large group with one flaky member preserves stable delivery'` | Passed: `+1 All tests passed!`. |
| `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart` | Passed: `+193 All tests passed!`. |
| Scoped analyzer on GE-021 owner files | Passed: `No issues found!`. |
| `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart test/features/groups/integration/group_membership_smoke_test.dart test/features/groups/integration/group_resume_recovery_test.dart` | Passed: `+134 All tests passed!`. |
| Required relay-backed `ge021` proof | Passed with shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_ge021_npLDuk`, run id `1778730737810`, Alice `38FECA55-03C1-4907-BD9D-8E64BF8E3469`, Bob `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD`, Charlie `5BA69F1C-B112-47BE-B1FF-8C1003728C8F`, and final result `ge021 proof passed: ge021 verdicts valid for alice, bob, charlie`. |
| `git diff --check` | Passed after closure documentation updates. |

## Final Verdict

Accepted/closed. GE-021 is covered by exact host large-group flaky-member evidence plus required relay-backed three-party `ge021` proof. Residual-only none for GE-021. No final program verdict is written because unresolved rows remain.
