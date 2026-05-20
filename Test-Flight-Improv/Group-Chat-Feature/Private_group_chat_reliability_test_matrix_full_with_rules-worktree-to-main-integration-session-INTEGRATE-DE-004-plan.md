# INTEGRATE-DE-004 Live Plus Replay Dedupe Import Contract

Status: accepted

## Historical Source Of Truth

- Source row: `DE-004 | Live plus replay duplicate delivery dedupes without hiding state updates`.
- Source worktree plan: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-DE-004-plan.md` in `worktrees/full-rules-pipeline`.
- Source closure status: `accepted` / `covered`, accepted on 2026-05-11.
- Integration mode: standard worktree-to-main import/reconcile/verify. This contract does not recreate the source implementation plan and does not expand the row beyond DE-004.

## Integration Scope

Import only the missing DE-004 row-owned delta into main:

- Rehydrate the persisted message in the listener-backed replay branch of `drain_group_offline_inbox_use_case.dart` after `handleReplayEnvelope`, so duplicate replay can still derive the local delivered receipt without emitting a second UI row.
- Add the DE-004 direct drain selector proving one visible row, first live content/timestamp/sender/key/status preservation, quote/media enrichment, replay read receipt, local delivered receipt, read state, and cursor commit.
- Add the DE-004 fake-network selector proving live delivery followed by listener-backed inbox replay keeps one row and commits replay read/local-delivered evidence.
- Update the worktree-to-main ledger and test inventory after verification.

Do not import DE-005+, sender self-echo reconciliation, publish result semantics, timeout handling, callback routing, native dispatcher panic handling, Go/native changes, criteria/live-harness changes, real device proof, source matrix/session docs, or unrelated source-worktree changes.

## Verification Contract

- Focused DE-004 direct drain selector.
- Focused DE-004 fake-network replay selector.
- Affected duplicate/enrichment/notification/unread preservation selectors from COMPLETE_1 overlap.
- Scoped analyzer, format, and `git diff --check`.
- `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups`, preserving known non-DE-004 residual failures.
- `./scripts/run_test_gates.sh completeness-check`, preserving unrelated fake-network classification residuals.
- No iOS 26.2 live proof is required for DE-004; the source row treats 3-party E2E as recommended/supplemental only.

## Execution Evidence

Imported row-owned production/test deltas in `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`, `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, and `test/features/groups/integration/group_resume_recovery_test.dart`; updated `test-inventory.md` and this integration ledger.

Passed verification:

- `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'DE-004 listener-backed live plus replay dedupes while preserving replay receipts and metadata'` (`+1`)
- `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'DE-004 live plus inbox replay duplicate keeps one row and commits replay evidence'` (`+1`)
- `flutter test --no-pub test/features/groups/application/handle_incoming_group_message_use_case_test.dart --name 'deduplicates by messageId when pubsub and group inbox deliver same message|duplicate replay enriches a missing quotedMessageId|duplicate replay saves missing media attachments'` (`+3`)
- `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name 'GP-025 LP013 duplicate PubSub delivery preserves first row and notification state'` (`+1`)
- `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --name 'PREREQ-GROUP-SYNC-RECEIPTS duplicate receipt replay is idempotent|GP-026 GMAR-004 duplicate live plus inbox replay enriches video and voice media once|GI-024|GI-034 offline replay suppresses duplicate notifications and preserves unread state'` passed the GP-026 and GI-034 selected preservation cases while preserving pre-existing non-DE-004 fixture residuals in PREREQ-GROUP-SYNC-RECEIPTS and GI-024.
- `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --name 'GP-026 same message is not duplicated if both pubsub and group inbox deliver it|unread count stays correct across duplicate inbox drain, retry recovery, and read clear'` (`+2`)
- Scoped analyzer over DE-004 owner files (`No issues found!`)
- `dart format --set-exit-if-changed` on DE-004 owner Dart files (`0 changed`)
- Scoped `git diff --check` on DE-004 owner files passed before doc closure.

Preserved residual evidence:

- `group_message_listener_test.dart --name 'replayed duplicate group message does not create a second local notification|GP-025 LP013 duplicate PubSub delivery preserves first row and notification state'` ran the stronger GP-025/LP-013 selector green and exposed a pre-existing stale fixture in the older duplicate-notification selector: its initial notification is suppressed because the fixture does not seed local `peer-self` membership under the current membership guard.
- The drain preservation bundle exposed pre-existing stale fixture residuals outside DE-004: `PREREQ-GROUP-SYNC-RECEIPTS duplicate receipt replay is idempotent` skips before persistence because the fixture lacks local `peer-local` membership, and `GI-024 duplicate replay is idempotent without status rollback or notification spam` records no duplicate flow events under the current replay path. GP-026 and GI-034 in the same bundle passed.
- `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` remains red at `+197 -3` only on preserved non-DE-004 residuals `BB-007 accepted pending invite joins with exact full config and replays accepted epoch` (`Expected: not null / Actual: <null>` at `invite_round_trip_test.dart:679`), `BB-012 restart recovery drains replay before ack and stays live` (`Expected: an object with length of <1> / Actual: WhereIterable<GroupMessage>:[]` at `group_startup_rejoin_smoke_test.dart:842`), and `GM-029 config version monotonicity converges across A/B/C shuffled delivery` (`Expected: MemberRole.writer / Actual: MemberRole.reader` at `group_membership_smoke_test.dart:8144`).
- `./scripts/run_test_gates.sh completeness-check` remains red on unrelated `test/shared/fakes/fake_group_pubsub_network_test.dart` classification (`732/733`).

## Final Verdict

Accepted. DE-004 is integrated with the missing listener-backed replay receipt rehydration plus row-owned direct and fake-network selectors. No live simulator proof, Go/native work, criteria/harness support, UI, notification, publish-result, self-echo, or adjacent DE row closure is claimed.
