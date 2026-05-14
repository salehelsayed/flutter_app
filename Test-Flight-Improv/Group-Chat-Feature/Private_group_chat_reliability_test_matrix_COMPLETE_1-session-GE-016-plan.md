# GE-016 Session Plan: Concurrent Admin Membership Mutation

## Status

Status: accepted/closed

## Source Row

Source matrix row: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` row `GE-016`

## Gap-Closure Reconciliation

| Time | Actor | Inputs Compared | Finding | Action |
|---|---|---|---|---|
| 2026-05-14 05:12 CEST | Controller | Source matrix GE-016 row; breakdown session ledger row 222; existing group membership smoke tests; `group_test_user` membership helpers; `ge016` harness/criteria absence; current device proof requirements | The source row was still `Open` and classified `needs_code_and_tests`/`implementation-ready`. Existing concurrent admin tests covered generic convergence but did not prove two admins mutating membership concurrently under held delivery with deterministic winner semantics, nor did the relay-backed device harness expose a `ge016` proof. | Add exact host regression, close the versioned membership helper behavior needed for deterministic conflict resolution, add `ge016` relay criteria/runner/harness support, run focused/broader host gates, and run the required relay-backed three-party proof. |

## Scope

GE-016 owns concurrent admin membership mutation convergence for private group chat. The row closes when two admin-authored membership changes delivered in varied order converge deterministically for all active peers and the required relay-backed proof validates the same contract through the device harness.

Out of scope: unrelated membership policy changes, UI invite flows, media messages, quoted replies, and non-admin authorization rows.

## Execution Contract

1. Add an exact host test named `GE-016 two admins mutate membership concurrently and converge`.
2. Ensure `GroupTestUser` membership helper events carry deterministic membership version timestamps so concurrent add/remove/promote system payloads resolve by current row contract instead of arrival order.
3. Add `ge016` support to the multi-party device harness, runner, and criteria validator.
4. Prove the host path with held/released deliveries and active-peer convergence.
5. Prove the device path with Alice preparing a stale remove, Bob applying a newer add, delayed stale delivery after add, deterministic winner `bob_add_dana`, final A/B/C convergence, and Charlie/Dana retained.
6. Update the source matrix, breakdown ledger, and test inventory with concrete file/test/gate evidence.

## Required Gates

| Gate | Command |
|---|---|
| Format | `dart format test/features/groups/integration/group_membership_smoke_test.dart test/shared/fakes/group_test_user.dart integration_test/group_multi_party_device_real_harness.dart integration_test/scripts/run_group_multi_party_device_real.dart integration_test/scripts/group_multi_party_device_criteria.dart test/integration/group_multi_party_device_criteria_test.dart` |
| Focused GE-016 host proof | `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GE-016 two admins mutate membership concurrently and converge'` |
| Focused GE-016 criteria proof | `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'GE-016'` |
| Full criteria proof | `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart` |
| Scoped analyzer | `dart analyze integration_test/group_multi_party_device_real_harness.dart integration_test/scripts/run_group_multi_party_device_real.dart integration_test/scripts/group_multi_party_device_criteria.dart test/integration/group_multi_party_device_criteria_test.dart test/shared/fakes/group_test_user.dart test/features/groups/integration/group_membership_smoke_test.dart` |
| Adjacent group integration proof | `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart test/features/groups/integration/group_membership_smoke_test.dart test/features/groups/integration/group_resume_recovery_test.dart` |
| Required relay-backed three-party proof | `MKNOON_RELAY_ADDRESSES=/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario ge016 -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469,347FB118-10D0-40C8-A05B-B0C3BD6B8CCD,5BA69F1C-B112-47BE-B1FF-8C1003728C8F` |
| Hygiene | `git diff --check` |

## Dirty Worktree Snapshot

Captured before closure: worktree remained dirty with prior gap-closure rollout changes and accepted session artifacts. GE-016 scope is limited to row-owned group membership host proof, deterministic membership helper behavior, multi-party `ge016` harness/criteria/runner support, this adjacent plan, source/breakdown closure updates, and test inventory entries.

## Execution Evidence

Implemented row-owned host coverage in `test/features/groups/integration/group_membership_smoke_test.dart::GE-016 two admins mutate membership concurrently and converge`. The test creates Alice/Admin, Bob, Charlie, and Diana; promotes Bob to admin; holds delivery while Alice promotes Charlie and Bob removes Diana; releases held deliveries in varied order; then proves Admin/Bob/Charlie converge to the same active member map while Diana self-removes and unsubscribes.

Updated `test/shared/fakes/group_test_user.dart` so helper-generated membership/config payloads carry deterministic `lastMembershipEventAt` version values for add/remove/broadcast operations. This gives the host and harness tests a stable conflict-resolution contract for concurrently delivered admin membership events.

Added required relay-backed `ge016` support in:

- `integration_test/group_multi_party_device_real_harness.dart`
- `integration_test/scripts/run_group_multi_party_device_real.dart`
- `integration_test/scripts/group_multi_party_device_criteria.dart`
- `test/integration/group_multi_party_device_criteria_test.dart`

The device scenario promotes Bob to admin, has Alice prepare an older Charlie removal, has Bob apply a newer synthetic Dana add, publishes the stale removal after the newer add, and proves deterministic winner `bob_add_dana`. Criteria requires final membership/role convergence, Charlie and Dana both present, `lastMembershipEventAt == addDanaAt`, and active Alice/Bob/Charlie agreement.

## Verification

| Gate | Result |
|---|---|
| Dart format on six owned Dart files | Passed. |
| `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GE-016 two admins mutate membership concurrently and converge'` | Passed: `+1 All tests passed!`. |
| `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'GE-016'` | Passed: `+2 All tests passed!`. |
| `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart` | Passed: `+191 All tests passed!`. |
| Scoped analyzer on GE-016 owner files | Passed: `No issues found!`. |
| `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart test/features/groups/integration/group_membership_smoke_test.dart test/features/groups/integration/group_resume_recovery_test.dart` | Passed: `+133 All tests passed!`. |
| Required relay-backed `ge016` proof | Passed with shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_ge016_6ktSvg`, run id `1778727856388`, Alice `38FECA55-03C1-4907-BD9D-8E64BF8E3469`, Bob `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD`, Charlie `5BA69F1C-B112-47BE-B1FF-8C1003728C8F`, and final result `ge016 proof passed: ge016 verdicts valid for alice, bob, charlie`. |
| `git diff --check` | Passed after closure documentation updates. |

## Final Verdict

Accepted/closed. GE-016 is covered by exact host concurrent-admin membership mutation evidence plus required relay-backed three-party `ge016` proof. Residual-only none for GE-016. No final program verdict is written because unresolved rows remain.
