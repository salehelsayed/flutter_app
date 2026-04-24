# Session 5 Plan - Refresh maintained dissolve docs and persist the final frozen-state verdict

## Final verdict

- `closure-only`

## Real scope

- Refresh the maintained audit, network, matrix, gate-definition, and test
  inventory docs so they describe the stricter dissolved-group contract
  truthfully instead of stopping at "send is blocked."
- Record Session `4` acceptance in the breakdown, then move the breakdown to a
  finished program verdict only after the stable docs cite the landed proof.
- Keep the closure pass bounded to doc truth: no new product scope, no new
  code work, and no widening of named gates.

## Closure bar

- Stable docs say only currently authorized admins can dissolve, dissolved
  groups freeze both send and reaction mutation, feed surfaces project the
  frozen state truthfully, and users can later delete a dissolved group
  locally without affecting others.
- The matrix rows that actually govern dissolved behavior cite the current
  proof instead of older pre-Session-72 wording.
- The inventory lists the new dissolved local-delete, reaction-freeze, and
  feed-frozen-state regressions that landed across Sessions `2` through `4`.
- `test-gate-definitions.md` reflects the device-backed dissolved cleanup proof
  without widening any frozen named gate membership.
- The breakdown records Session `4` as accepted, Session `5` as accepted, and
  the final program verdict as closed.

## Source of truth

- Active session contract:
  - `Test-Flight-Improv/72-secure-frozen-state-for-dissolved-groups-session-breakdown.md`
- Governing product/problem docs:
  - `Test-Flight-Improv/72-secure-frozen-state-for-dissolved-groups.md`
- Stable docs to refresh:
  - `Test-Flight-Improv/11-group-discussion-use-case-audit.md`
  - `Test-Flight-Improv/09-network-group-messaging.md`
  - `Test-Flight-Improv/Group-Chat-Feature/Discussion-And-Announcement-Feature-Audit.md`
  - `Test-Flight-Improv/Group-Chat-Feature/Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md`
  - `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
  - `Test-Flight-Improv/test-gate-definitions.md`
- Evidence to cite:
  - `test/features/groups/application/dissolve_group_use_case_test.dart`
  - `test/features/groups/application/group_message_listener_test.dart`
  - `test/features/groups/application/send_group_reaction_use_case_test.dart`
  - `test/features/groups/application/remove_group_reaction_use_case_test.dart`
  - `test/features/groups/application/handle_incoming_group_reaction_use_case_test.dart`
  - `test/features/groups/application/delete_group_and_messages_use_case_test.dart`
  - `test/features/groups/presentation/group_conversation_wired_test.dart`
  - `test/features/groups/presentation/group_info_screen_test.dart`
  - `test/features/groups/presentation/group_info_wired_test.dart`
  - `test/features/groups/integration/group_membership_smoke_test.dart`
  - `test/features/feed/domain/models/feed_item_test.dart`
  - `test/features/feed/domain/utils/group_group_messages_into_threads_test.dart`
  - `test/features/feed/presentation/screens/feed_screen_test.dart`
  - `test/features/feed/presentation/screens/feed_wired_test.dart`
  - `test/features/feed/application/load_feed_use_case_test.dart`
  - `test/features/feed/application/feed_projection_test.dart`
  - `integration_test/group_recovery_e2e_test.dart`

On disagreement:

- current code and accepted tests beat older prose
- the matrix currently has `UX-002`, `RC-003`, and `RY-005` as the live
  dissolved rows; there is no current `UX-014` row, so closure should update
  the rows that actually exist instead of inventing a stale identifier
- `test-gate-definitions.md` should keep `integration_test/group_recovery_e2e_test.dart`
  outside the frozen named gates because it remains device-bound

## Session classification

- `closure-only`

## Exact problem statement

- Sessions `1` through `4` already closed the repo-owned code gaps, but the
  stable docs still under-describe the shipped dissolved contract.
- Several docs still speak about dissolve mainly as read-only history plus send
  blocking, without capturing the stricter current-admin-only authority,
  reaction freeze, feed frozen-state propagation, and local-only cleanup
  contract.
- The inventory is also missing the new direct proofs added in this rollout.
- This session must fix doc truth without reopening code scope.

## Files and docs to inspect next

- `Test-Flight-Improv/11-group-discussion-use-case-audit.md`
- `Test-Flight-Improv/09-network-group-messaging.md`
- `Test-Flight-Improv/Group-Chat-Feature/Discussion-And-Announcement-Feature-Audit.md`
- `Test-Flight-Improv/Group-Chat-Feature/Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md`
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/72-secure-frozen-state-for-dissolved-groups-session-breakdown.md`

## Existing doc drift to correct

- The use-case audit currently says dissolve is shipped, but it still frames
  the contract mainly as read-only history plus blocked send.
- The network doc does not yet call out that post-dissolve reaction mutation is
  frozen and that offline-recovered dissolved history can later be deleted
  locally without a new leave event.
- The feature audit row for dissolve is too narrow and does not mention the
  feed frozen-state or local-only cleanup truth.
- The matrix rows for dissolved behavior cite older shorter wording and do not
  mention reaction freeze or local-only cleanup where appropriate.
- The test inventory is missing the new local-delete, dissolved reaction, and
  feed-frozen-state regressions.
- `test-gate-definitions.md` classifies `integration_test/group_recovery_e2e_test.dart`
  as nightly/release only, but it does not yet mention that this file now
  carries the dissolved local-delete recovery proof.

## Step-by-step implementation plan

1. Update the breakdown ledger so Session `4` is accepted and Session `5`
   becomes the active runnable closure session.
2. Refresh the use-case audit, network doc, and feature audit with the stricter
   dissolved frozen-state wording and the new proof references.
3. Update the matrix rows that govern dissolved behavior (`UX-002`,
   `RC-003`, and `RY-005`) so they cite the current authority/freeze/local
   cleanup proof accurately.
4. Expand the test inventory for the new Session `2`, `3`, and `4` tests.
5. Add one bounded note to `test-gate-definitions.md` that
   `integration_test/group_recovery_e2e_test.dart` now carries the device-backed
   dissolved local-cleanup proof while staying outside frozen named gates.
6. Persist final acceptance in the breakdown and close the program verdict.

## Risks and edge cases

- Closure docs must not overclaim a broader product surface than what actually
  shipped; for example, the local-delete affordance is shipped on Group Info,
  not every possible group surface.
- The matrix must stay aligned to real row IDs already present in the file.
- The test inventory should capture the most important new tests without
  turning into a second changelog.

## Exact verification to cite

- Same-day accepted feed gate:
  - `./scripts/run_test_gates.sh feed`
- Session `4` direct suites:
  - `flutter test test/features/groups/application/delete_group_and_messages_use_case_test.dart`
  - `flutter test test/features/groups/presentation/group_info_screen_test.dart`
  - `flutter test test/features/groups/presentation/group_info_wired_test.dart`
  - `flutter test test/features/groups/integration/group_membership_smoke_test.dart`
- Session `4` device-backed proof:
  - `flutter test integration_test/group_recovery_e2e_test.dart -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469`
- Same-day accepted group gate:
  - `./scripts/run_test_gates.sh groups`

## Done criteria

- Stable docs describe the final dissolved contract truthfully.
- The inventory lists the new direct proofs from Sessions `2` through `4`.
- The breakdown records all sessions accepted and closes the program verdict.
- No named gate membership was widened accidentally.

## Scope guard

- Do not make additional product or code changes in this session.
- Do not reopen Session `4` UI or use-case work unless a doc claim cannot be
  made truthfully without a real code fix.
- Do not add new test files or new gate members here.
