# INTEGRATE-DE-005 Sender Self-Echo Reconciliation Import Contract

Status: accepted

## Historical Source Of Truth

- Source row: `DE-005 | Sender self-echo is reconciled with the pending local row`.
- Source worktree plan: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-DE-005-plan.md` in `worktrees/full-rules-pipeline`.
- Source evidence commits: plan `c709ead5fa548f8053eec35558741d545ad8a6c8`; implementation `f097a809c92fe417b90ea4d41c00e0276edee312`.
- Source closure status: `accepted` / `covered`.
- Integration mode: standard worktree-to-main import/reconcile/verify. This contract does not recreate the source implementation plan and does not expand the row beyond DE-005.

## Integration Scope

Import only the missing DE-005 row-owned delta into main:

- Reconcile sender self-echo duplicate receives against an existing pending/sending outgoing row in `handle_incoming_group_message_use_case.dart`.
- Promote the existing outgoing row to `sent`, preserve local text/timestamp/created-at/inbox retry evidence, clear the wire envelope, save incoming media metadata, and emit `GROUP_HANDLE_INCOMING_MSG_SELF_ECHO_RECONCILED`.
- Add the DE-005 direct handler selectors for matched and mismatched transport identity.
- Add the DE-005 listener selector proving exactly one reconciled outbound row is emitted.
- Add the DE-005 fake-network resume selector proving self echo plus inbox duplicate reconciles once.
- Update the worktree-to-main ledger and test inventory after verification.

Do not import DE-006+, publish-result receipt semantics, timeout handling, callback routing, native dispatcher panic handling, Go/native changes, criteria/live-harness changes, real device proof, source matrix/session docs, or unrelated source-worktree changes.

## Verification Contract

- Focused DE-005 direct handler selector bundle.
- Focused DE-005 listener selector.
- Focused DE-005 fake-network resume selector.
- Affected handler, listener, resume, and GM-001/DE-001 smoke preservation selectors from COMPLETE_1/main overlap.
- Scoped analyzer, format, and `git diff --check`.
- `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups`, preserving known non-DE-005 residual failures.
- `./scripts/run_test_gates.sh completeness-check`, preserving unrelated fake-network classification residuals.
- No iOS 26.2 live proof is required for DE-005; this row is accepted with host/fake-network proof.

## Execution Evidence

Imported row-owned production/test deltas in `lib/features/groups/application/handle_incoming_group_message_use_case.dart`, `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`, `test/features/groups/application/group_message_listener_test.dart`, and `test/features/groups/integration/group_resume_recovery_test.dart`; updated `test-inventory.md` and this integration ledger.

Passed verification:

- `flutter test --no-pub test/features/groups/application/handle_incoming_group_message_use_case_test.dart --plain-name "DE-005 self echo"` (`+2`; rerun serially after an initial parallel native-assets startup race)
- `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name "DE-005 self echo emits reconciled outbound row once"` (`+1`)
- `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name "DE-005 sender self echo plus inbox duplicate reconciles pending row once"` (`+1`)
- `flutter test --no-pub test/features/groups/application/handle_incoming_group_message_use_case_test.dart --name "persists same-self delivery as local sent history|deduplicates by messageId when pubsub and group inbox deliver same message|duplicate replay enriches a missing quotedMessageId|duplicate replay with the same messageId ignores conflicting content"` (`+4`)
- `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name "GP-025 LP013 duplicate PubSub delivery preserves first row and notification state"` (`+1`)
- `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --name "DE-004 live plus inbox replay duplicate keeps one row and commits replay evidence|GP-026 same message is not duplicated if both pubsub and group inbox deliver it"` (`+2`)
- `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --name "sender saves outgoing locally and others save incoming"` (`+1`)
- `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name "GM-001 DE-001 creates private A/B/C group with shared epoch and exact fanout tuple"` (`+1`)
- Scoped analyzer over DE-005 owner files (`No issues found!`)
- `dart format --set-exit-if-changed` on DE-005 owner Dart files (`0 changed` after the resume test format update)
- Scoped `git diff --check` on DE-005 owner Dart files passed before doc closure.

Preserved residual evidence:

- `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` remains red at `+198 -3` only on preserved non-DE-005 residuals `BB-007 accepted pending invite joins with exact full config and replays accepted epoch` (`Expected: not null / Actual: <null>` at `invite_round_trip_test.dart:679`), `BB-012 restart recovery drains replay before ack and stays live` (`Expected: an object with length of <1> / Actual: WhereIterable<GroupMessage>:[]` at `group_startup_rejoin_smoke_test.dart:842`), and `GM-029 config version monotonicity converges across A/B/C shuffled delivery` (`Expected: MemberRole.writer / Actual: MemberRole.reader` at `group_membership_smoke_test.dart:8144`).
- `./scripts/run_test_gates.sh completeness-check` remains red on unrelated `test/shared/fakes/fake_group_pubsub_network_test.dart` classification (`732/733`).

## Final Verdict

Accepted. DE-005 is integrated with sender self-echo reconciliation plus row-owned direct, listener, and fake-network selectors. No live simulator proof, Go/native work, criteria/harness support, UI, notification, publish-result, or adjacent DE row closure is claimed.
