# Session 3 Plan: Durable Send-Path Parity Between Conversation and Feed Inline Reply

**Final Verdict:** sufficient

## 1. Scope

- Fix only the durable-send parity gap for feed-originated 1:1 inline replies.
- The current mismatch is between `lib/features/feed/presentation/screens/feed_wired.dart`, which still calls `sendChatMessage(...)` directly for inline reply, and `lib/features/conversation/presentation/screens/conversation_wired.dart`, which saves an optimistic row first and then passes `messageId:` into the shared send path.
- Use the existing failing Session 2 regression in `test/features/feed/presentation/screens/feed_wired_test.dart` as the RED proof.
- Do not broaden into read receipts, typing, groups, posts, notifications, or startup/transport work.

## 2. Files To Inspect Next

- Primary production contract files, in this order:
  - `lib/features/feed/presentation/screens/feed_wired.dart`
  - `lib/features/conversation/presentation/screens/conversation_wired.dart`
  - `lib/features/conversation/application/send_chat_message_use_case.dart`
- Supporting Session 3 code-entry files to verify shared-path impact before editing:
  - `lib/features/conversation/application/upload_media_use_case.dart`
  - `lib/features/conversation/application/send_voice_message_use_case.dart`
  - `lib/features/conversation/application/retry_incomplete_uploads_use_case.dart`
  - `lib/features/conversation/application/chat_message_listener.dart`
- Existing test owners and contract references:
  - `test/features/feed/presentation/screens/feed_wired_test.dart`
  - `test/features/conversation/presentation/screens/conversation_wired_test.dart`
  - `test/features/conversation/application/send_chat_message_use_case_test.dart`
  - `test/features/conversation/application/retry_unacked_messages_use_case_test.dart`
  - `test/features/conversation/application/retry_incomplete_uploads_use_case_test.dart`
  - `test/core/services/pending_message_retrier_stuck_sending_test.dart`
  - `test/features/conversation/integration/send_then_lock_delivery_test.dart`
  - `test/shared/fakes/in_memory_message_repository.dart` if helper or repo semantics matter
- Current test-gate source of truth:
  - `scripts/run_test_gates.sh`
  - `Test-Flight-Improv/test-gate-definitions.md`
  - `Test-Flight-Improv/test-gates-reference.md`

## 3. Existing Tests Covering This Area

- Feed surface and Session 2 regression:
  - `test/features/feed/presentation/screens/feed_wired_test.dart`
  - `test/features/feed/integration/feed_card_flow_test.dart`
  - `test/features/feed/integration/expanded_collapsed_card_test.dart`
- Session 2 conversation-path coverage:
  - `test/features/conversation/integration/two_user_message_exchange_test.dart`
  - `test/features/conversation/integration/offline_inbox_roundtrip_test.dart`
  - `test/features/conversation/integration/send_then_lock_delivery_test.dart`
  - `test/features/conversation/integration/stuck_sending_recovery_test.dart`
- Session 3 shared-pipeline guardrails:
  - `test/features/conversation/presentation/screens/conversation_wired_test.dart`
  - `test/features/conversation/application/send_chat_message_use_case_test.dart`
  - `test/features/conversation/integration/media_attachment_flow_test.dart`
  - `test/features/conversation/integration/media_retry_smoke_test.dart`
  - `test/features/conversation/integration/voice_message_exchange_test.dart`
  - `test/features/conversation/integration/incomplete_upload_recovery_test.dart`
- If shared retry/recovery helpers are touched:
  - `test/features/conversation/application/retry_unacked_messages_use_case_test.dart`
  - `test/features/conversation/application/retry_incomplete_uploads_use_case_test.dart`
  - `test/core/services/pending_message_retrier_stuck_sending_test.dart`

## 4. Regressions/Tests To Add First

- No new broad regression file first.
- Keep the existing Session 2 feed parity regression as the RED driver.
- Keep `test/features/conversation/presentation/screens/conversation_wired_test.dart` as explicit companion parity evidence for the conversation-side optimistic contract.
- Keep `test/features/conversation/application/send_chat_message_use_case_test.dart` as the direct contract proof if implementation reaches the shared send use case.
- Add only a minimal helper-level assertion if the implementation forces extraction.

## 5. Step-By-Step Implementation Plan

- Reconfirm the contract boundary in `feed_wired.dart`, `conversation_wired.dart`, and `send_chat_message_use_case.dart`.
- Make `feed_wired.dart` the primary edit zone.
- Prefer keeping the fix local to `feed_wired.dart`; only touch shared send/retry code if feed cannot adopt the existing conversation contract without it.
- Generate a stable `messageId` and timestamp before the inline send, persist an optimistic `ConversationMessage` with `status: 'sending'`, then call `sendChatMessage(...)` with the same ID/timestamp so `updateWireEnvelope(...)` can run before transport completion.
- Keep the optimistic row and final send result on the same ID to avoid duplicates.
- Preserve current feed success behavior: mark read, refresh the feed item, keep session-reply collapse behavior coherent with repo updates.
- Preserve failure restore behavior: draft text, quote state, and session reply.
- If `send_chat_message_use_case.dart` changes, preserve the existing Section 4 contract that `updateWireEnvelope(...)` happens before the transport race.
- If retry/recovery helpers are touched, preserve existing unacked cleanup and pending-message retrier expectations instead of redefining that behavior in Session 3.
- Leave shared send/retry semantics alone unless a minimal refactor is required.

## 6. Risks And Edge Cases

- Missing stable `messageId` or timestamp keeps the row non-durable.
- ID mismatch creates duplicate rows.
- Repo-change-driven refresh can break current session-reply UX.
- Failure restore can lose draft or quote state.
- Shared-send edits can accidentally break early `wireEnvelope` persistence or `messageId` reuse even if feed UI tests go green.
- Retry/recovery helper edits can regress unacked cleanup or pending-message retrier behavior outside the immediate feed surface.
- Scope creep into bootstrap, inbox drain, reconnect, or transport fallback would exceed Session 3.
- Baseline and transport already have documented unrelated reds; do not misclassify them as Session 3 regressions.

## 7. Exact Tests To Run After Implementation

- `flutter test test/features/feed/presentation/screens/feed_wired_test.dart --plain-name 'feed inline 1:1 reply becomes retry-discoverable before network completes'`
- `flutter test test/features/feed/presentation/screens/feed_wired_test.dart`
- `flutter test test/features/conversation/presentation/screens/conversation_wired_test.dart --plain-name 'sanitized optimistic text stays consistent before and after persistence'`
- `flutter test test/features/conversation/presentation/screens/conversation_wired_test.dart` if changes reach `conversation_wired.dart` or the conversation-side optimistic contract
- `flutter test test/features/conversation/application/send_chat_message_use_case_test.dart --plain-name 'RED: wireEnvelope is persisted to DB before discover is called'` if changes reach `send_chat_message_use_case.dart`
- `flutter test test/features/conversation/application/send_chat_message_use_case_test.dart` if the change modifies early wire-envelope persistence, message ID resolution, or direct-send ordering
- `flutter test test/features/conversation/application/retry_unacked_messages_use_case_test.dart` if changes reach unacked/inbox retry behavior
- `flutter test test/features/conversation/application/retry_incomplete_uploads_use_case_test.dart` if changes reach incomplete-upload recovery behavior
- `flutter test test/core/services/pending_message_retrier_stuck_sending_test.dart` if changes reach pending-message retrier or stuck-sending recovery behavior
- `./scripts/run_test_gates.sh feed`
- `./scripts/run_test_gates.sh 1to1`
- `./scripts/run_test_gates.sh baseline`
- `./scripts/run_test_gates.sh transport` only if bootstrap, inbox drain, reconnect, or transport fallback semantics are touched
- Optional wider confidence only, not required for sufficiency: `flutter test test/features/feed`
- Optional wider confidence only, not required for sufficiency: `flutter test test/features/conversation/integration`

## 8. Subsystem Gates And Whether Startup/Transport Tests Are Needed

- Required: Feed / Surface and 1:1 Reliability.
- Required source of truth: `./scripts/run_test_gates.sh feed` and `./scripts/run_test_gates.sh 1to1`.
- Required companion direct coverage: `test/features/feed/presentation/screens/feed_wired_test.dart` because feed-originated 1:1 send changes sit outside the frozen named gate lists.
- Required parity companion: keep at least one deterministic conversation-side optimistic-send test green so the plan still proves feed matches the current conversation contract.
- Baseline is required by the roadmap, but only preexisting documented reds may remain.
- Startup / Transport is not required unless the fix spills into bootstrap, inbox drain, reconnect, or transport fallback behavior.

## 9. Done Criteria

- The existing feed parity regression passes.
- Feed inline reply and conversation send both persist a durable row before the transport race using the same contract.
- Required companion direct tests stay green for feed parity, conversation optimistic send, and any touched shared send/retry helper.
- `./scripts/run_test_gates.sh feed` and `./scripts/run_test_gates.sh 1to1` pass with no new failures.
- If `send_chat_message_use_case.dart` changes, the direct `wireEnvelope` contract tests stay green.
- If retry/recovery helpers change, the matching direct retry/recovery suites stay green.
- Any remaining baseline or transport red is limited to the already documented unrelated issues.
- The change stays inside durable send-path parity.

## Structural Blockers Remaining

- None.

## Incremental Details Intentionally Deferred

- `test/features/conversation/presentation/screens/conversation_wired_test.dart` remains a full-file rerun only when the conversation-side optimistic contract is touched; the targeted parity test stays the minimum companion proof.
- `flutter test test/features/feed` and `flutter test test/features/conversation/integration` stay optional wider confidence runs, not required gate evidence.

## Why It Is Safe To Execute Now

- The plan includes the required production contract files first.
- It stays anchored to the real failing feed regression.
- It uses the current gate source of truth in `scripts/run_test_gates.sh` plus the Session 1 gate docs.
- No structural blocker remained after the final reviewer and arbiter pass.
