# GE-006 Session Plan: Remove/Re-add While C Offline

Status: accepted

## Gap-Closure Reconciliation

At planning time, GE-006 source row was `Open`: Alice, Bob, and Charlie start joined; Charlie is offline while Alice removes and re-adds Charlie; when Charlie comes back, Charlie must receive exactly post-readd messages and be able to send, and Alice/Bob must receive Charlie's send. The breakdown ledger row 165 was classified as `needs_code_and_tests` / `implementation-ready`; after this session it is `covered/accepted`. This was repo-owned runnable work because the membership code, offline replay drain, fake-network harness, criteria validator, real multi-party runner, and relay/device harness are all in this repository.

GE-005 closes online repeated remove/re-add stress and direct membership update delivery. It does not close GE-006 because Charlie is offline across the mutation window and must catch up through durable replay/invite state, not live pubsub.

## Scope

- Add exact host fake-network proof for GE-006.
- Add `ge006` three-role simulator harness/runner support.
- Add `ge006` criteria validation and criteria tests.
- Update the source matrix and breakdown only after gates pass.

Out of scope: unrelated group membership behavior, unrelated GE rows, and broad refactors.

## Execution Contract

The row closes only if:

- Alice/Bob/Charlie start in one private group.
- Charlie is offline before removal and remains offline through remove, re-add, and post-readd durable sends.
- Alice removes Charlie and sends a removed-window message that Bob receives and Charlie never renders.
- Alice re-adds Charlie; Alice and Bob send post-readd messages with durable recipients including Charlie.
- Charlie comes back, retrieves durable replay, renders exactly the post-readd messages, and does not render removed-window traffic.
- Charlie sends after catch-up and Alice/Bob receive it exactly once.
- Final membership contains Alice, Bob, and Charlie.
- The same contract passes in the three-simulator `ge006` relay harness.

## Required Gates

| Gate | Command |
|---|---|
| Focused fake-network proof | `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name 'GE-006'` |
| Criteria focused proof | `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'GE-006'` |
| Criteria full regression | `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart` |
| Static analysis | `flutter analyze --no-pub integration_test/scripts/group_multi_party_device_criteria.dart integration_test/scripts/run_group_multi_party_device_real.dart integration_test/group_multi_party_device_real_harness.dart test/integration/group_multi_party_device_criteria_test.dart test/features/groups/integration/group_messaging_smoke_test.dart` |
| Three-device relay proof | `MKNOON_RELAY_ADDRESSES=... dart integration_test/scripts/run_group_multi_party_device_real.dart --scenario ge006 -d <alice,bob,charlie>` |
| Broader group smoke gate | `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart test/features/groups/integration/group_membership_smoke_test.dart test/features/groups/integration/group_resume_recovery_test.dart` |
| Formatting | `dart format --set-exit-if-changed test/features/groups/integration/group_messaging_smoke_test.dart integration_test/scripts/group_multi_party_device_criteria.dart integration_test/scripts/run_group_multi_party_device_real.dart integration_test/group_multi_party_device_real_harness.dart test/integration/group_multi_party_device_criteria_test.dart` |
| Hygiene | `git diff --check` |

## Execution Evidence

Implementation added row-owned GE-006 proof in `test/features/groups/integration/group_messaging_smoke_test.dart`, `integration_test/scripts/group_multi_party_device_criteria.dart`, `integration_test/scripts/run_group_multi_party_device_real.dart`, `integration_test/group_multi_party_device_real_harness.dart`, and `test/integration/group_multi_party_device_criteria_test.dart`.

Passed gates:

- `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name 'GE-006'` (`+1`).
- `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'GE-006'` (`+3`).
- `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart` (`+151`).
- `flutter analyze --no-pub integration_test/scripts/group_multi_party_device_criteria.dart integration_test/scripts/run_group_multi_party_device_real.dart integration_test/group_multi_party_device_real_harness.dart test/integration/group_multi_party_device_criteria_test.dart test/features/groups/integration/group_messaging_smoke_test.dart` (`No issues found!`).
- `MKNOON_RELAY_ADDRESSES=... dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario ge006 -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469,347FB118-10D0-40C8-A05B-B0C3BD6B8CCD,5BA69F1C-B112-47BE-B1FF-8C1003728C8F` passed with shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_ge006_yCcSao`, run id `1778663062209`, and verdict `ge006 proof passed: ge006 verdicts valid for alice, bob, charlie`.
- `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart test/features/groups/integration/group_membership_smoke_test.dart test/features/groups/integration/group_resume_recovery_test.dart` (`+119`).
- `dart format --set-exit-if-changed test/features/groups/integration/group_messaging_smoke_test.dart integration_test/scripts/group_multi_party_device_criteria.dart integration_test/scripts/run_group_multi_party_device_real.dart integration_test/group_multi_party_device_real_harness.dart test/integration/group_multi_party_device_criteria_test.dart` (`0 changed`).
- `git diff --check` passed.

Supporting note: repo-wide `flutter analyze --no-pub` still reports the pre-existing broader analyzer backlog; the scoped analyzer over GE-006-owned files is clean.

## Current Verdict

Accepted. GE-006 is covered by concrete host, criteria, broad smoke, and three-device relay evidence. No row-owned blocker remains; GE-007 is the next unresolved P0 session.
