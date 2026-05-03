# RP-018 Session Plan - Membership add, remove, and role conflicts converge deterministically

Status: execution-accepted

## Planning Progress

| timestamp | role | files inspected | decision | next action |
| --- | --- | --- | --- | --- |
| 2026-05-01T06:51:16+02:00 | Local planner completed | `trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules-session-breakdown.md`; source matrix RP-018 row; `test-inventory.md`; `lib/features/groups/application/group_message_listener.dart`; `lib/features/groups/application/group_membership_event_watermark.dart`; `test/features/groups/integration/group_membership_smoke_test.dart`; `test/features/groups/application/group_message_listener_test.dart`; `test/features/groups/integration/group_resume_recovery_test.dart`; `test/shared/fakes/group_test_user.dart`; `test/shared/fakes/fake_group_pubsub_network.dart` | Existing evidence covers timestamp-ordered membership convergence and stale older events, but a partition can still deliver a stale role update before the removal it missed. RP-018 needs remove-over-role conflict handling for the same pre-existing member, missing-target role-update rejection, row-named fake-network proof, and diagnostics. | Patch receive-side membership conflict handling, add focused RP-018 tests, run focused gates, then close docs only if the source row can move to `Covered`. |

## real scope

Close RP-018 for shipped trusted-private membership convergence when admins perform conflicting add, remove, promote, and demote actions across a partition. The session owns receive-side conflict resolution for membership system events and focused fake-network/application proof that all peers converge on the same final member and permission map after replay, even when a stale role update is delivered before the removal it missed.

## closure bar

RP-018 can close only when:

- a receive-side test proves stale `member_role_updated` events cannot resurrect a member removed by a conflicting removal
- a receive-side test proves an older `member_removed` replay can still remove a pre-existing member after a newer stale role update, while preserving explicit diagnostics
- a row-named fake-network integration test proves add, remove, promote, and demote conflict replay converges every remaining peer on the same member/role map after partition heal
- focused membership/listener/resume/key conflict tests and the canonical groups gates pass
- source matrix, inventory, and breakdown record `Covered` with concrete file and test evidence

## session classification

`evidence-gated`, with targeted implementation because the current timestamp-only watermark is insufficient for same-member remove/role partition conflicts.

## Device/Relay Proof Profile

- Profile for this session: `host-only` closure with supporting real-network/nightly evidence unconfigured.
- RP-018 can close on repo-local fake-network proof because the row-owned gap is deterministic application-layer membership convergence, not transport capture.
- Supporting unrun gate: `FLUTTER_DEVICE_ID=<device> MKNOON_RELAY_ADDRESSES=<relays> ./scripts/run_test_gates.sh group-real-network-nightly`.

## files to touch

- `lib/features/groups/application/group_message_listener.dart`
- `test/features/groups/application/group_message_listener_test.dart`
- `test/features/groups/integration/group_membership_smoke_test.dart`
- `Test-Flight-Improv/Group-Chat-Feature/trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules.md`
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- `Test-Flight-Improv/Group-Chat-Feature/trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules-session-breakdown.md`

## step-by-step implementation plan

1. Add receive-side logic so a stale `member_removed` event can still apply when the target member currently exists from before that removal event. Keep old removal replays ignored when the member is absent or was explicitly re-added after the removal timestamp.
2. Reject `member_role_updated` for a missing target member before it can recreate a removed member from a stale snapshot, and emit a diagnostic flow event.
3. Add a focused listener test for remove-over-role conflict ordering and missing-target role-update rejection diagnostics.
4. Add a row-named fake-network integration test that simulates partitioned add, remove, promote, and demote replay, including stale-role-before-remove delivery, and asserts all remaining peers converge on the same member/role map.
5. Run focused and canonical groups gates, then update closure docs only after all RP-018 evidence passes.

## exact tests and gates to run

- `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name 'RP018'`
- `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'RP018'`
- `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart`
- `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart`
- `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'offline member reconnects after membership churn and converges to the final member list'`
- `flutter test --no-pub test/features/groups/application/group_key_update_listener_test.dart --plain-name 'conflicting same-generation key updates converge to one final stored key'`
- `./scripts/run_test_gates.sh groups`
- `flutter test --no-pub test/features/groups/integration`
- `git diff --check`

## done criteria

- RP-018 row-named fake-network convergence proof passes.
- Receive-side listener conflict proof passes with diagnostics.
- Existing membership smoke, resume, listener, and key-conflict regression coverage remains green.
- Source matrix RP-018 row is `Covered`.
- `test-inventory.md` RP-018 crosswalk is `Covered`.
- Breakdown counts, current-session closure state, matrix row inventory, session ledger, ordered session row, and closure progress record RP-018 as accepted/Covered.

## scope guard

Do not add a new CRDT, account/device registry, moderation policy, ban/unban feature, or real-device transport proof under RP-018. The row closes deterministic convergence for shipped membership events and fake-network replay, with supporting real-network nightly remaining a separate operational gate while relay/device fixtures are unset.

## Dirty Worktree Snapshot

Captured at `2026-05-01T06:51:16+02:00`: the tree already contains prior rollout changes in matrix/breakdown docs, Go node tests, Flutter group tests, and untracked prior session plan files. RP-018 execution is scoped to `group_message_listener.dart`, the two RP-018 test files, this plan, and RP-018 closure docs unless focused tests expose another row-owned conflict gap.

## Execution Progress

| timestamp | role | files inspected or changed | decision | next action |
| --- | --- | --- | --- | --- |
| 2026-05-01T06:57:00+02:00 | Local executor completed | `lib/features/groups/application/group_message_listener.dart`; `test/features/groups/application/group_message_listener_test.dart`; `test/features/groups/integration/group_membership_smoke_test.dart`; focused RP-018 listener/smoke gates; full listener/smoke files; resume churn and key conflict focused tests; `./scripts/run_test_gates.sh groups`; full groups integration; `git diff --check` | Implemented remove-over-role conflict handling, missing-target role-update rejection, and row-named fake-network partition-heal proof. All required host gates passed; supporting real-network nightly remains unrun because relay/device env is unset. | Update source matrix, inventory, and breakdown to `Covered`; continue to the next unresolved row. |

## Final Execution Verdict

Accepted. RP-018 is covered for shipped trusted-private membership add/remove/promote/demote convergence under partition replay. Remaining program closure is still open because later source rows remain unresolved; real-network nightly is supporting-only for RP-018 while `FLUTTER_DEVICE_ID` and `MKNOON_RELAY_ADDRESSES` are unset.
