# GM-032 Group Dissolve / Empty Membership Closure Plan

Status: accepted/closed

## Planning Progress

- 2026-05-13 23:22 CEST - Local gap-closure pass reached GM-032 after GL-020 closure. Source matrix row GM-032 was `Open` at planning start and is now `Covered`; session ledger row 189 started as `implementation-ready` / `needs_code_and_tests`; no adjacent GM-032 plan existed. Inspected `dissolve_group_use_case.dart`, `group_message_listener.dart`, `send_group_message_use_case.dart`, existing dissolve/listener tests, and `group_membership_smoke_test.dart`.
- 2026-05-13 23:25 CEST - GM-032 implementation and closure evidence completed. Source matrix row GM-032 is `Covered`; session ledger row 189 is `covered/accepted`; residual-only none. Continue from GK-028.

## Source Row

| Row | Scenario | Setup | Steps | Expected | Priority | Status | Unit | Smoke | 3-Party E2E | Fake Network | Soak | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| GM-032 | Group dissolve/removal of all members stops delivery | Group is dissolved or membership becomes empty. | 1. Apply dissolve/all-removed event. 2. Try publish/receive/inbox store. 3. Reopen history. | Live send is disabled, topic left, and historical messages remain according to product rules. | P1 | Covered | Required | Required | Required | Recommended | Recommended | Covered by private-chat empty-membership send blocking, authoritative all-members-removed listener closure, exact host proofs, combined owner suite, named groups gate, and diff hygiene. |

## Gap Classification

GM-032 remains repo-owned. Explicit `group_dissolved` handling already marks groups dissolved, stores history, and leaves the topic, but reconciliation found an implementation-owned empty-membership gap:

- `sendGroupMessage` blocks `group.isDissolved`, but a private chat with an empty local member list could still proceed to native publish/inbox work instead of disabling send.
- `group_message_listener` applies authoritative `member_removed` snapshots with empty `members`, but does not explicitly mark the group dissolved/read-only or leave the topic.
- Existing dissolve tests are not row-owned GM-032 proof and do not pin the empty-membership edge.

## Scope

Own exactly GM-032:

- Disable private-chat send when the active local membership list is empty, without changing announcement-channel send semantics.
- Treat an authoritative member removal/config snapshot with no active members as a terminal local group closure: preserve group history, mark the group dissolved, record the membership watermark, and leave the native topic.
- Add exact GM-032 tests for explicit dissolve send blocking/history and all-members-removed snapshot closure.
- Update the source matrix, breakdown, and test inventory only after the exact tests and gates pass.

## Out Of Scope

- New product UI flows beyond already-shipped dissolved read-only surfaces.
- Three-party/device-lab harness changes unless existing host/fake coverage exposes a real repo-owned gap that cannot be proven otherwise.
- Rewriting historical membership semantics for ordinary non-empty member removal rows.

## Owner Files

- `lib/features/groups/application/send_group_message_use_case.dart`
- `lib/features/groups/application/group_message_listener.dart`
- `test/features/groups/application/dissolve_group_use_case_test.dart`
- `test/features/groups/application/send_group_message_use_case_test.dart`
- `test/features/groups/application/group_message_listener_test.dart`
- `test/features/groups/integration/group_membership_smoke_test.dart`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md`
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`

## Device / Relay Proof Profile

GM-032 mentions `3-Party E2E`, fake-network, and soak as recommended/required matrix columns, but the row-owned implementation gap is host-app lifecycle behavior. Required closure proof for this pass is host-only:

- Direct Flutter app tests in dissolve/listener/membership smoke files.
- Named groups gate after focused tests.
- No live device/relay command is required unless host execution reveals the existing fake-network smoke cannot prove topic leave and send blocking.

## Execution Evidence

- Code changed: `send_group_message_use_case.dart` now returns `SendGroupMessageResult.groupDissolved` before `group:publish` or `group:inboxStore` when a `GroupType.chat` group has no active local members. The guard is scoped to private chat groups so announcement sends with empty member fixtures keep their existing behavior.
- Code changed: `group_message_listener.dart` now treats authoritative raw `groupConfig.members: []` member-removal snapshots as terminal local closure: it preserves prior timeline/history, applies the empty config, marks the group dissolved, records `dissolvedAt`/membership watermark, and calls `group:leave`.
- Exact tests added/updated:
  - `dissolve_group_use_case_test.dart::GM-032 dissolved group disables publish and inbox while preserving history`
  - `send_group_message_use_case_test.dart::GM-032 empty active membership disables publish and inbox`
  - `group_message_listener_test.dart::GM-032 all-members-removed snapshot dissolves, leaves, and preserves history`
  - `group_membership_smoke_test.dart::GM-032 offline member converges to dissolved state through replay, cannot send afterwards, and can delete locally without affecting others`
- Validation passed: Dart format; focused GM-032 dissolve/send/listener/smoke selectors (`+1` each); full `send_group_message_use_case_test.dart` (`+86`); full `group_message_listener_test.dart` (`+107`); combined owner suite (`+253`); `./scripts/run_test_gates.sh groups` (`+159`); `git diff --check` on owned files plus closure docs.

## Final Verdict

Accepted/closed. GM-032 has code and row-owned tests for both explicit dissolve and all-members-removed private-chat closure, and the source row is `Covered`. No `accepted_with_explicit_follow_up` is used; residual-only none. The next unresolved session in ordered ledger order is GK-028.

## Tests And Gates

Run after implementation:

```sh
dart format --set-exit-if-changed lib/features/groups/application/send_group_message_use_case.dart lib/features/groups/application/group_message_listener.dart test/features/groups/application/dissolve_group_use_case_test.dart test/features/groups/application/send_group_message_use_case_test.dart test/features/groups/application/group_message_listener_test.dart test/features/groups/integration/group_membership_smoke_test.dart
flutter test --no-pub test/features/groups/application/dissolve_group_use_case_test.dart --plain-name 'GM-032'
flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --plain-name 'GM-032'
flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name 'GM-032'
flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-032'
flutter test --no-pub test/features/groups/application/dissolve_group_use_case_test.dart test/features/groups/application/send_group_message_use_case_test.dart test/features/groups/application/group_message_listener_test.dart test/features/groups/integration/group_membership_smoke_test.dart
./scripts/run_test_gates.sh groups
git diff --check -- lib/features/groups/application/send_group_message_use_case.dart lib/features/groups/application/group_message_listener.dart test/features/groups/application/dissolve_group_use_case_test.dart test/features/groups/application/send_group_message_use_case_test.dart test/features/groups/application/group_message_listener_test.dart test/features/groups/integration/group_membership_smoke_test.dart Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md Test-Flight-Improv/Group-Chat-Feature/test-inventory.md Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GM-032-plan.md
```

## Dirty Worktree Snapshot

`git status --short` before GM-032 execution showed a large pre-existing dirty worktree from prior rollout sessions. GM-032 edits must stay within the owner files above plus closure docs; unrelated dirty files must not be reverted.

## Done Criteria

- Source row GM-032 is `Covered` with concrete file/test/gate evidence.
- `sendGroupMessage` returns `groupDissolved` without `group:publish` / `group:inboxStore` when membership is empty.
- Incoming all-members-removed snapshot marks the group dissolved, leaves the topic, and preserves historical timeline rows.
- Existing explicit dissolve behavior remains green.
- Breakdown session ledger row 189 and closure ledger record `covered/accepted`.
- No `accepted_with_explicit_follow_up` is used for unresolved GM-032 gaps.
