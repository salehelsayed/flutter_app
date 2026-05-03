# RP-014 Session Plan - Voluntary leave key rotation policy

Status: execution-accepted

## Planning Progress

| timestamp | role | files inspected | decision | next action |
| --- | --- | --- | --- | --- |
| 2026-05-01T06:19:07+02:00 | Evidence Collector completed | `trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules.md`; `test-inventory.md`; session breakdown; `leave_group_use_case.dart`; `group_info_wired.dart`; `rotate_and_distribute_group_key_use_case.dart`; `member_removal_integration_test.dart`; `group_info_wired_test.dart` | Existing coverage proves an explicitly rotated voluntary-leave path excludes the leaver and sends future traffic on epoch 2, and the UI currently rotates before local cleanup. The gap remains row-owned because the rotate-on-leave policy is still embedded in a screen-private helper and there is no departed-peer replay/decrypt-failure proof after local cleanup. | Extract a first-class application helper for voluntary-leave broadcast plus rotation, wire the screen through it, and extend tests to prove remaining-member key convergence plus leaver replay exclusion after leave. |

## real scope

Close RP-014 for shipped voluntary leave behavior: when a non-sole-admin member leaves, the application sends a durable self-removal event to remaining members, rotates the group key only to remaining members, performs local cleanup through `leaveGroup`, and leaves the departed peer unable to process future offline replay for that group because the local group and key state are gone.

## closure bar

RP-014 can close only when:

- voluntary-leave broadcast and rotation are owned by an application-layer helper reusable outside `GroupInfoWired`
- remaining members receive the self-removal replay and new group key while the leaver is excluded from key recipients
- local `leaveGroup` cleanup removes group, members, and keys after the leave broadcast/rotation step
- a departed-peer replay attempt for post-leave traffic does not persist/decrypt future content
- source matrix, inventory, and breakdown record `Covered` with concrete file and test evidence

## session classification

`needs_code_and_tests`.

## files to touch

- `lib/features/groups/application/broadcast_voluntary_leave_use_case.dart`
- `lib/features/groups/presentation/screens/group_info_wired.dart`
- `test/features/groups/application/member_removal_integration_test.dart`
- `test/features/groups/presentation/group_info_wired_test.dart` if screen-level assertions need adjustment

## step-by-step implementation plan

1. Add an application-layer voluntary-leave helper that loads local identity, skips sole-admin leaves, publishes a `member_removed` self-removal message, stores durable replay for remaining members, and rotates/distributes the next group key to remaining members.
2. Replace `GroupInfoWired._broadcastSelfRemovalIfNeeded` with a call into the new helper while keeping the existing leave ordering before `leaveGroup`.
3. Extend voluntary-leave integration coverage to use the new helper, assert key-update recipients exclude the leaver, assert remaining members converge on epoch 2, assert future sends use epoch 2 and exclude the leaver from inbox recipients, and assert the leaver cannot process a future replay after local cleanup.
4. Run focused RP-014 tests, existing screen leave tests, group smoke/integration gates, and `git diff --check`.

## exact tests and gates to run

- `flutter test --no-pub test/features/groups/application/member_removal_integration_test.dart --plain-name 'voluntary leave rotation excludes leaver and remaining members send on rotated epoch'`
- `flutter test --no-pub test/features/groups/presentation/group_info_wired_test.dart --plain-name 'multi-admin leave broadcasts self-removal, rotates key, and pops to first route'`
- `flutter test --no-pub test/features/groups/presentation/group_info_wired_test.dart --plain-name 'writer leave broadcasts a durable left-the-group event before local cleanup'`
- `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart`
- `./scripts/run_test_gates.sh groups`
- `flutter test --no-pub test/features/groups/integration`
- `git diff --check`

## done criteria

- Focused voluntary-leave integration test passes with application-layer helper coverage.
- Existing screen leave tests continue to prove UI ordering through the extracted helper.
- Group membership smoke and canonical group gates pass or unrelated failures are explicitly classified.
- Source matrix RP-014 row is `Covered`.
- `test-inventory.md` RP-014 crosswalk is `Covered`.
- Breakdown counts, current-session closure state, matrix row inventory, session ledger, ordered session row, and closure progress record RP-014 as accepted/Covered.

## scope guard

Do not introduce a configurable leave-rotation product setting, change group dissolution semantics, add real-device relay proof, or claim cryptographic raw-capture evidence beyond the existing group key/envelope primitives. RP-014 closes the shipped voluntary-leave policy path and repo-local replay/departure proof; broader device-lab and transport-capture rows remain separate unless configured.

## Execution Progress

| timestamp | role | files inspected or changed | decision | next action |
| --- | --- | --- | --- | --- |
| 2026-05-01T06:25:47+02:00 | Executor completed | `broadcast_voluntary_leave_use_case.dart`; `group_info_wired.dart`; `member_removal_integration_test.dart` | RP-014 shipped voluntary-leave rotation is now an application-layer helper, wired by `GroupInfoWired` before `leaveGroup` cleanup. The helper publishes self-removal, stores durable replay for remaining members, rotates/distributes the next key to remaining members, and fails the leave preparation if rotation cannot complete while remaining members exist. | Update source matrix, inventory, and breakdown to `Covered`; run stale-status and diff hygiene checks. |
| 2026-05-01T06:25:47+02:00 | Verification completed | Focused RP-014 integration proof; existing leave UI tests; full `group_info_wired_test.dart`; group membership smoke; groups gate; full group integration | Focused RP-014 test now proves remaining-member epoch 2 convergence, leaver exclusion from key updates and future inbox recipients, local group/member/key cleanup after leave, normal post-cleanup drain skipping departed group state, and a forced post-leave replay attempt saving only an undecryptable placeholder rather than future content. | Record `group-real-network-nightly` as unconfigured supporting evidence; do not close real-device, packet-capture, or broader ban/removal rows under RP-014. |

## Final Execution Verdict

`accepted`: RP-014 is ready to mark `Covered` for the shipped voluntary-leave policy path. Rotation-on-leave is first-class application logic, remaining members converge on the new epoch, and the departed peer cannot decrypt post-leave replay content with only removed local group/key state. Unconfigured real-device proof remains outside this row's repo-local closure scope.
