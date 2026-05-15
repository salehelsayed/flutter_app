

## Task

Implement the TDD plan in `@UI-TestFlight-1/message-delivery-reliability-tdd-plan.md` using a disciplined agent loop. The plan covers the 1:1 send-then-lock bug for text, media, and voice messages.

## Execution Model

For each **phase** below, follow this loop:

1. **Implement**: Launch one agent per work unit in the phase. Each agent reads its section of the plan, writes the red tests (failing), then the green implementation, then refactors. It must follow the plan's code exactly — file paths, function signatures, test names. If the plan says "create file X with test Y", do exactly that.

2. **QA**: When the implementation agent finishes, launch a QA agent (in a worktree for isolation) that:
   - Reads the same plan section
   - Reads every file the implementation agent created or modified
   - Runs the tests (`flutter test <specific_test_file>`)
   - Checks: Do all new tests pass? Do existing tests still pass? Does the code match the plan? Are there any regressions?
   - Returns a verdict: **PASS** (move on) or **FAIL** with a numbered list of findings

3. **Fix**: If QA returns FAIL, launch a fix agent with the QA findings. It fixes each finding and re-runs the tests. Then send it back to a new QA agent. Repeat until QA returns PASS.

4. **Next phase**: Only after ALL work units in a phase pass QA, move to the next phase.

**Parallelism rule**: Launch ALL independent work units within a phase simultaneously. Wait for all to pass QA before starting the next phase.

## Phase Breakdown

### Phase 1 — Foundation (4 parallel work units)

These have ZERO code dependencies on each other. Launch all 4 simultaneously.

| Unit | Plan Section | What to implement | Key files |
|------|-------------|-------------------|-----------|
| **1A** | Section 1 Part A (lines 115-865) | Stuck-sending recovery: DB helper `dbRecoverStuckSendingMessages`, repo method, use case, integration test, then green implementation | `lib/core/database/helpers/messages_db_helpers.dart`, `lib/features/conversation/domain/repositories/message_repository.dart`, `message_repository_impl.dart` |
| **1B** | Section 5 Bugs A+C (lines 12962-13207) | FCM `sender_id` fix + Redis requirement: Dart unit test + one-line fix in `notification_route_target.dart`, verification test for Redis | `lib/core/notifications/notification_route_target.dart` |
| **1C** | Section 3 steps 3.1-3.2 (lines 10155-10485) | iOS background task Swift + Dart bridge: XCTest for bgBegin/bgEnd MethodChannel, Dart contract test, Swift implementation in GoBridge.swift, GoBridgeClient._cmdMap | `ios/Runner/GoBridge.swift`, `lib/core/bridge/go_bridge_client.dart` |
| **1D** | Section 4 steps 4.1-4.5 (lines 11477-12468) | Direct-first send: early wireEnvelope persistence, media attachment persistence at optimistic write, inbox-handoff idempotency (Go relay dedup + Dart transport guard) | `lib/features/conversation/application/send_chat_message_use_case.dart`, `go-relay-server/inbox.go` |

### Phase 2 — Retrier + Lifecycle (3 parallel work units)

Depends on Phase 1A (stuck-sending recovery methods exist). Phase 1B/1C/1D are not dependencies.

| Unit | Plan Section | What to implement | Key files |
|------|-------------|-------------------|-----------|
| **2A** | Section 1 Part B (lines 866-1688) | Expand PendingMessageRetrier to cover 'sending' status: repo interface, DB helper, retrier unit tests, smoke test, green implementation | `lib/core/services/pending_message_retrier.dart`, test fakes |
| **2B** | Section 1 Part C (lines 1689-3252) | Make `retryFailedMessages` replay-safe for media: 7 unit tests for media-aware retry, 4 null-guard tests, green implementation with `mediaAttachmentRepo` parameter | `lib/features/conversation/application/retry_failed_messages_use_case.dart`, `retry_unacked_messages_use_case.dart` |
| **2C** | Section 3 steps 3.3-3.6 (lines 10486-10974) | Dart presentation-layer bg:begin tests: `_onSend`, `_onVoiceRecordingStopped`, `_onInlineSend` (feed_wired), regression guard that `sendVoiceMessage` does NOT call bg:begin | `test/` files only (tests for Phase 3 green) |

### Phase 3 — Wiring + Media Recovery Foundation (3 parallel work units)

Depends on Phase 2A (retrier expanded) and Phase 2B (retry is media-safe).

| Unit | Plan Section | What to implement | Key files |
|------|-------------|-------------------|-----------|
| **3A** | Section 1 Part D (lines 3253-3873) | Wire retrier into handleAppResumed + cold-start sweep: 4-step execution ordering (recoverStuck → retryIncompleteUploads → retryFailed → retryUnacked), fault isolation tests, green implementation, main.dart DI wiring | `lib/features/conversation/application/handle_app_resumed_use_case.dart`, `lib/main.dart` |
| **3B** | Section 1 Part F (lines 3874-4931) | Re-upload incomplete media/voice: retry decision tree, 3-branch dispatch, `_reuploadAttachments` helper, Stable-ID contract (F.7.1), `uploadMedia` signature change to accept `blobId`, `sendVoiceMessage` stable-ID threading | `lib/features/conversation/application/retry_failed_messages_use_case.dart`, `upload_media_use_case.dart`, `send_voice_message_use_case.dart` |
| **3C** | Section 3 steps 3.7-3.12 (lines 10975-11476) | iOS background task green implementation: Swift bgBegin/bgEnd handlers, GoBridgeClient cmd map, Android no-op, presentation-layer call site guards in conversation_wired + feed_wired, refactor to callBgBegin/callBgEnd helpers | `ios/Runner/GoBridge.swift`, `lib/core/bridge/go_bridge_client.dart`, `lib/features/conversation/presentation/screens/conversation_wired.dart`, `lib/features/feed/presentation/screens/feed_wired.dart` |

### Phase 4 — Pre-Upload Persistence (1 work unit)

Depends on Phase 3B (stable-ID contract and re-upload helper exist).

| Unit | Plan Section | What to implement | Key files |
|------|-------------|-------------------|-----------|
| **4A** | Section 1 Part G (lines 4932-7685) | Full Part G: `upload_pending` DB helper, `MediaAttachmentRepository` interface extension, `retryIncompleteUploads` use case (canonical design: transient retry with `upload_retry_count`, `resolveStoredPath`, per-message grouping), optimistic pre-upload persistence in conversation_wired, durable storage (G.9), voice local-WiFi end-to-end (G.10), smoke tests | `lib/core/database/helpers/media_attachments_db_helpers.dart`, `lib/features/conversation/domain/repositories/media_attachment_repository.dart`, `lib/features/conversation/presentation/screens/conversation_wired.dart`, new `lib/core/media/media_file_manager.dart` extensions |

### Phase 5 — Lifecycle Pause Handler (1 work unit)

Depends on Phase 1A (recoverStuckSendingMessages), Phase 3A (handleAppResumed wiring), and Phase 4A (retryIncompleteUploads).

| Unit | Plan Section | What to implement | Key files |
|------|-------------|-------------------|-----------|
| **5A** | Section 2 (lines 7686-10103) | Full Section 2: `handleAppPaused` use case (steps 2.1-2.7), MyApp lifecycle handler, sender-side UI recovery (`_shouldRefreshFromRepositoryChange` includes 'failed'), widget tests, smoke tests | `lib/core/lifecycle/handle_app_paused.dart` (new), `lib/main.dart`, `lib/features/conversation/presentation/screens/conversation_wired.dart` |

### Phase 6 — Notification Body Quality (1 work unit)

Depends on Phase 1B (sender_id fix landed). Can overlap with Phase 5 if desired.

| Unit | Plan Section | What to implement | Key files |
|------|-------------|-------------------|-----------|
| **6A** | Section 5 Bugs B+D (lines 13065-14048) | Group push Notification struct (out of 1:1 scope but in plan), `notificationBodyForMessage` helper, `handleIncomingChatMessage` media hydration prerequisite, stale test updates | `lib/features/conversation/application/handle_incoming_chat_message_use_case.dart`, new `lib/core/notifications/notification_body_for_message.dart` |

### Phase 7 — Integration Tests (1 work unit)

Depends on ALL previous phases.

| Unit | Plan Section | What to implement | Key files |
|------|-------------|-------------------|-----------|
| **7A** | Section 6 (lines 14049-16410) | Full Section 6: shared test infrastructure (fakes, fixtures, BobTestHarness), B.1 acceptance proof (11 sub-tests: text same-row recovery, real media upload_pending recovery, real voice recovery, WiFi-interrupted voice, direct-first offline delivery), B.2-B.4 integration tests, smoke test checklist | `test/` integration files, extended fakes |

## Agent Instructions Template

When launching each **implementation agent**, use this prompt structure:

```
You are implementing Phase {N} Unit {X} of the message delivery reliability TDD plan.

**Plan file:** `UI-TestFlight-1/message-delivery-reliability-tdd-plan.md`
**Your section:** Lines {start}-{end} ({section name})

Follow the plan EXACTLY:
1. Read your plan section completely before writing any code
2. RED phase: Create all test files listed in the plan. Write the exact tests specified. Run them — they MUST fail (compile errors or assertion failures are expected).
3. GREEN phase: Implement the production code specified in the plan. Run the tests — they MUST pass.
4. REFACTOR phase: Apply any refactoring the plan specifies.
5. Run `flutter test` on all files you created/modified to verify everything passes.
6. Run `flutter test test/` to check for regressions (if this takes too long, run only the test directories related to your changes).

Rules:
- Follow file paths, function names, and signatures from the plan exactly
- Do not add code the plan doesn't specify
- Do not skip tests the plan specifies
- If something in the plan doesn't compile or work, fix it minimally and note what you changed
- After all phases, list every file you created or modified
```

When launching each **QA agent**, use this prompt structure:

```
You are QA reviewing Phase {N} Unit {X} implementation.

**Plan file:** `UI-TestFlight-1/message-delivery-reliability-tdd-plan.md`
**Plan section:** Lines {start}-{end}

Review checklist:
1. Read the plan section
2. Read every file the implementation agent created or modified: {file list}
3. Run `flutter test {specific_test_files}` — do they all pass?
4. Check: Does the code match the plan's specifications? (function signatures, file paths, test names, behavior)
5. Check: Do existing tests still pass? Run `flutter test test/features/conversation/ test/core/`
6. Check: Are there any security issues, memory leaks, or obvious bugs?
7. Check: Does the implementation handle the edge cases the plan specifies?

Return one of:
- **PASS** — all checks passed, ready for next phase
- **FAIL** — with a numbered list of specific findings that must be fixed
```

## Visualization

```
Phase 1:  [1A: S1 Part A] [1B: S5 A+C] [1C: S3 bridge] [1D: S4 direct-first]
              ↓                ↓              ↓                 ↓
          QA→Fix loop      QA→Fix loop    QA→Fix loop      QA→Fix loop
              ↓                               ↓
Phase 2:  [2A: S1 Part B] [2B: S1 Part C] [2C: S3 tests]
              ↓                ↓              ↓
          QA→Fix loop      QA→Fix loop    QA→Fix loop
              ↓                ↓
Phase 3:  [3A: S1 Part D] [3B: S1 Part F] [3C: S3 green]
              ↓                ↓              ↓
          QA→Fix loop      QA→Fix loop    QA→Fix loop
                               ↓
Phase 4:  [4A: S1 Part G]
              ↓
          QA→Fix loop
              ↓
Phase 5:  [5A: Section 2]          Phase 6: [6A: S5 B+D] (parallel with 5)
              ↓                         ↓
          QA→Fix loop              QA→Fix loop
              ↓                         ↓
Phase 7:  [7A: Section 6 integration tests]
              ↓
          QA→Fix loop
              ↓
           ✅ DONE
```

## Important Notes

- **TDD discipline**: Red tests MUST fail before green implementation. If a test passes before implementation, the test is wrong.
- **Plan is the source of truth**: The plan has exact test code, file paths, and function signatures. Follow them.
- **Stable-ID contract**: Every media/voice attachment uses a pre-generated UUID that survives through upload. `uploadMedia` and `sendVoiceMessage` accept `blobId` parameter. This is critical — orphan rows are a P0 bug.
- **retryIncompleteUploads canonical design**: Transient failure stays `upload_pending` (retryable). Only terminal after `kMaxUploadRetries` (3). Uses `resolveStoredPath()` before filesystem checks. Groups by messageId.
- **bg:begin/bg:end**: Presentation layer ONLY (Wired widgets). Never in use cases.
- **Direct-first send**: Inbox is a fallback on failure/unacked only. Not unconditional. Relay has messageId-based dedup.
- **Go code**: Section 4 Step 4.5 and Section 5 Bug B require Go changes. Build with `cd go-mknoon && PATH="$PATH:$(go env GOPATH)/bin" make all && cd ../ios && pod install`.
- **Section 5.2 (group push)**: Out of scope for 1:1 reliability. Implement if time allows but don't block on it.
- **Section 5.4 scope**: Local notification body quality only. Server-side push body is out of scope.
