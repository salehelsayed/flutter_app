# Implementation Prompt — Group Message Delivery Reliability

Implement the TDD plan at `UI-TestFlight-1/group-message-delivery-reliability-tdd-plan.md` using the execution model below. The plan has 11 sections + DB schema + Go changes + Wire Envelope design organized into 3 phases.

---

## Execution Model

For every work unit:

1. **Implement**: Launch one agent per work unit. The agent reads its plan section, writes RED tests (failing), then GREEN implementation, then refactors. It follows the plan exactly — file paths, function signatures, test names, SQL queries, code patterns. If the plan says "create file X with test Y", do exactly that.

2. **QA**: When the implementation agent finishes, launch a QA agent (in a worktree for isolation) that:
   - Reads the same plan section
   - Reads every file the implementation agent created or modified
   - Runs the tests (`flutter test <specific_test_file>`)
   - Checks: Do all new tests pass? Do existing tests still pass? Does the code match the plan? Are there any regressions?
   - Returns a verdict: **PASS** (move on) or **FAIL** with a numbered list of findings

3. **Fix**: If QA returns FAIL, launch a fix agent with the QA findings. It fixes each finding and re-runs the tests. Then send it back to a new QA agent. Repeat until QA returns PASS.

4. **Next step**: Only after ALL work units in a step pass QA, move to the next step.

**Parallelism rule**: Launch ALL independent work units within a step simultaneously. Wait for all to pass QA before starting the next step.

---

## Phase 1 (P0) — Foundation + Send Contract + Recovery

### Phase 1, Step 1 — Foundation (launch in parallel)

#### WU-1: DB Schema + GroupMessage Model + DB Helpers

**Plan sections to read:**
- "Database Schema Changes" (lines ~194–417)
- "Wire Envelope Persistence Design" (lines ~1628–1710) — for column semantics only

**Deliverables:**
1. New migration `lib/core/database/migrations/041_group_message_reliability_columns.dart` — 3 `ALTER TABLE` statements (wire_envelope, inbox_stored, inbox_retry_payload), each guarded by `PRAGMA table_info` check, matching `014_wire_envelope_column.dart` pattern
2. Register migration in the migration list (check existing pattern)
3. `GroupMessage` model changes in `lib/features/groups/domain/models/group_message.dart`:
   - 3 new fields: `wireEnvelope` (String?), `inboxStored` (bool, default false), `inboxRetryPayload` (String?)
   - `fromMap`, `toMap`, `copyWith` additions (use sentinel pattern for nullable clear, match plan exactly)
4. 7 new DB helper functions in `lib/core/database/helpers/group_messages_db_helpers.dart`:
   - `dbLoadStuckSendingGroupMessages`
   - `dbLoadFailedOutgoingGroupMessages`
   - `dbLoadGroupMessagesWithFailedInboxStore`
   - `dbTransitionGroupSendingToFailed` (with DateTime olderThan param)
   - `dbUpdateGroupMessageInboxStored`
   - `dbUpdateGroupMessageInboxRetryPayload`
   - `dbUpdateGroupMessageWireEnvelope`
5. Test file: `test/core/database/helpers/group_messages_db_helpers_reliability_test.dart` — 41 tests covering migration, each DB helper, and GroupMessage model serialization (tests 1–41 from the plan)

**Test command:** `flutter test test/core/database/helpers/group_messages_db_helpers_reliability_test.dart`

**Existing patterns to follow:** Read `lib/core/database/migrations/014_wire_envelope_column.dart` for migration pattern. Read existing `group_messages_db_helpers.dart` for helper function style. Read `GroupMessage` model for `fromMap`/`toMap`/`copyWith` conventions.

---

#### WU-2: Go 10.1 — Peer Count in Publish Response

**Plan sections to read:**
- "Go-Side Changes" section 10.1 (lines ~1582–1625)
- Section 8.2 "Go: Return Peer Count" (lines ~1284–1302)

**Deliverables:**
1. Change `PublishGroupMessage(...)` in `go-mknoon/node/pubsub.go` to return `(messageId string, topicPeers int, err error)`
2. Include `topicPeers` in bridge JSON response in `go-mknoon/bridge/bridge.go`: `{"ok": true, "messageId": "...", "topicPeers": N}`
3. Update `go-mknoon/cmd/testpeer/commands.go` to accept the new return value
4. Go tests in `go-mknoon/node/pubsub_delivery_test.go` (or extend existing test file):
   - Test 1: Returns peer count > 0 with two nodes both joined
   - Test 2: Returns 0 count when no peers, no error
5. Bridge test in `go-mknoon/bridge/bridge_test.go` for the updated response format

**Note:** After writing Go code, the human must run `cd go-mknoon && PATH="$PATH:$(go env GOPATH)/bin" make all && cd ../ios && pod install` manually. Agent writes code + tests only. Run Go tests with `cd go-mknoon && go test ./node/ -run TestPublishPeerCount -v` (adjust test name).

---

### Phase 1, Step 2 — Unified Send Contract (after Step 1 passes QA)

#### WU-3: S4 + S8 + Wire Envelope Send Flow (single work unit — all modify `sendGroupMessage`)

**Plan sections to read:**
- Section 4: "Inbox Store as Required Fallback" (lines ~803–922)
- Section 8: "0-Peer Publish Detection" (lines ~1272–1359)
- "Wire Envelope Persistence Design" — Send Flow Change (lines ~1694–1710)
- Section 8.2 "Dart: Conditional Inbox Store Escalation" (lines ~1303–1326)

**Deliverables:**

*Send contract changes in `lib/features/groups/application/send_group_message_use_case.dart`:*
1. Replace `_safeInboxStore` with `_tryInboxStore` returning `Future<bool>`
2. Pre-persist outgoing row with status `'sending'` + `wireEnvelope` + `inboxRetryPayload` BEFORE bridge call (all callers get this automatically)
3. Start exactly one inbox-store future before awaiting publish
4. Read `topicPeers` from publish result
5. Implement 4-way result matrix: publish OK/fail x inbox OK/fail
6. New enum variant: `SendGroupMessageResult.successNoPeers` returning non-null GroupMessage with `status: 'pending'`
7. On success with peers > 0: status `'sent'`, clear wireEnvelope, clear inboxRetryPayload if inbox succeeded
8. On success with 0 peers + inbox OK: status `'pending'`, clear both retry payloads
9. On 0 peers + inbox fail: return error
10. Missing `topicPeers` key: treat as legacy success (backward compat)

*New use case: `lib/features/groups/application/retry_failed_group_inbox_stores_use_case.dart`:*
11. Query retry-eligible rows (outgoing, status in sent/pending, inbox_stored=0, inbox_retry_payload not null)
12. Reconstruct inbox payload, call `callGroupInboxStore`, update inbox_stored on success
13. Batch limit 20

*Repository extensions:*
14. Add inbox retry query + inbox result update methods to `GroupMessageRepository` abstract + impl
15. Extend `InMemoryGroupMessageRepository` (test fake)

*Presentation changes:*
16. `GroupConversationWired`: treat `successNoPeers` as success (text + voice paths)
17. `FeedWired`: treat `successNoPeers` as success, align with pre-persist contract (FeedWired no longer pre-persists its own row — sendGroupMessage owns it)
18. UI rendering of `'pending'` status (distinct icon, color, accessibility) in:
    - `letter_card.dart`
    - `message_bubble.dart`
    - `scrollable_message_preview.dart`
19. `GroupMessage` model: recognize `'pending'` as first-class outgoing status

*Resume handler:*
20. Add Step 8e in `handle_app_resumed.dart` for `retryFailedGroupInboxStoresFn`
21. Wire in `main.dart`

**Test files and commands:**
- S4 tests (11): create test file for `retryFailedGroupInboxStores` use case and send contract inbox behavior
- S8 Dart tests (8): create test file for 0-peer detection and successNoPeers handling
- Send contract tests: extend `send_group_message_use_case_test.dart` for pre-persist and retry eligibility
- `flutter test test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart`
- `flutter test test/features/groups/application/send_group_message_use_case_test.dart`
- Run ALL existing group tests to check for regressions: `flutter test test/features/groups/`

**Critical patterns:** Read existing `sendGroupMessage` use case thoroughly before modifying. Read `send_chat_message_use_case.dart` for the 1:1 pre-persist pattern. Read `handle_app_resumed.dart` for Step numbering and group-recovery gate pattern. Read existing `FeedWired` group send path.

---

### Phase 1, Step 3 — Stuck-Sending Recovery (after Step 2 passes QA)

#### WU-4: Section 1 — Stuck-Sending Recovery

**Plan section to read:** Section 1 (lines ~420–598)

**Deliverables:**
1. New abstract methods on `GroupMessageRepository`:
   - `recoverStuckSendingMessages({required Duration olderThan})` → `Future<int>`
   - `getFailedOutgoingMessages()` → `Future<List<GroupMessage>>`
2. Implement in `GroupMessageRepositoryImpl` (inject 2 new DB helper functions in constructor)
3. Implement in `InMemoryGroupMessageRepository`
4. New use case: `lib/features/groups/application/recover_stuck_sending_group_messages_use_case.dart`
   - Calls repo, emits FLOW events, returns count
   - Threshold: `kStuckSendingGroupThreshold = Duration(seconds: 30)`
5. New use case: `lib/features/groups/application/retry_failed_group_messages_use_case.dart`
   - Load identity, load failed messages, retry only provably text-only rows
   - Reuse original messageId + timestamp (retry in place, no second row)
   - Re-run announcement auth checks on every retry
   - Skip media/voice rows with FLOW event
   - Catch per-message errors, continue
6. Wire into `handleAppResumed` as Steps 3d (recover) and 3e (retry), AFTER rejoinGroupTopics + drainGroupOfflineInbox, INSIDE the group-recovery gate
7. Wire in `main.dart`

**Test files (13 tests):**
- `test/core/database/helpers/group_messages_db_helpers_stuck_sending_test.dart` (tests 1–4)
- `test/features/groups/application/recover_stuck_sending_group_messages_use_case_test.dart` (tests 5–7)
- `test/features/groups/application/retry_failed_group_messages_use_case_test.dart` (tests 8–12)
- `test/core/lifecycle/handle_app_resumed_group_stuck_sending_test.dart` (test 13)

**Test commands:**
- `flutter test test/core/database/helpers/group_messages_db_helpers_stuck_sending_test.dart`
- `flutter test test/features/groups/application/recover_stuck_sending_group_messages_use_case_test.dart`
- `flutter test test/features/groups/application/retry_failed_group_messages_use_case_test.dart`
- `flutter test test/core/lifecycle/handle_app_resumed_group_stuck_sending_test.dart`
- Regression check: `flutter test test/features/groups/`

---

## Phase 2 (P1) — Lifecycle + Background Task + Media (after Phase 1 passes)

### Phase 2, Step 1 (launch all in parallel)

#### WU-5: Section 2 — Lifecycle Pause Handler

**Plan section to read:** Section 2 (lines ~601–695)

**Deliverables:**
1. Add `dbTransitionGroupSendingToFailed(Database db)` to DB helpers — bulk UPDATE without DateTime (no threshold needed for pause, unlike resume)
2. Extend `handleAppPaused` signature: add optional `GroupMessageRepository? groupMsgRepo`
3. Extend `AppPausedResult` with `groupTransitionedCount`
4. Add `transitionSendingToFailed()` to GroupMessageRepository abstract + impl + InMemory fake
5. Ensure group sweep runs even when 1:1 count is zero (no early return skip)
6. Error isolation: group errors caught, never propagate
7. Wire `groupMsgRepo` to `handleAppPaused` in `main.dart`

**Test file (7 tests):** Plan specifies 3 test files:
- `test/core/database/helpers/group_messages_db_helpers_sending_test.dart` (test 1)
- `test/core/lifecycle/handle_app_paused_group_test.dart` (tests 2–5)
- `test/core/lifecycle/handle_app_resumed_group_recovery_test.dart` (tests 6–7)

**Test commands:**
- `flutter test test/core/database/helpers/group_messages_db_helpers_sending_test.dart`
- `flutter test test/core/lifecycle/handle_app_paused_group_test.dart`
- `flutter test test/core/lifecycle/handle_app_resumed_group_recovery_test.dart`

---

#### WU-6: Section 3 — iOS Background Task Protection

**Plan section to read:** Section 3 (lines ~697–799)

**Deliverables:**
1. In `group_conversation_wired.dart` `_onSend`: insert `callBgBegin` AFTER optimistic DB persist, BEFORE I/O try block. `callBgEnd` in outer finally.
2. In `_onRecordStop` (voice): same pattern — acquire after optimistic row persist, release in finally
3. Cover all 4 exit paths: upload failure, exception, unmount, normal success
4. Bridge is non-nullable in GroupConversationWired — no null check needed. bgTaskId null check still needed.
5. Do NOT add to FeedWired (explicitly deferred)

**Test file (8 tests):** `test/features/groups/presentation/screens/group_conversation_wired_bg_task_test.dart`
- Use FakeBridge that records `bg:begin` and `bg:end` calls
- Use order-recording bridge to prove sequence: `bg:begin -> upload -> publish -> inbox store -> bg:end`

**Test command:** `flutter test test/features/groups/presentation/screens/group_conversation_wired_bg_task_test.dart`

**Critical pattern:** Read `conversation_wired.dart` (1:1) background task pattern first. Read existing `group_conversation_wired.dart` `_onSend` and `_onRecordStop` thoroughly.

---

#### WU-7: Section 5 — Parallel Media Upload + Group Media Retry

**Plan section to read:** Section 5 (lines ~925–1065)

**Deliverables:**
1. Replace sequential `for` loop in `group_conversation_wired.dart` with `Future.wait()` — fail-all strategy
2. In `sendGroupMessage` use case: keep `getGroup()` sequential, then parallelize `getLatestKey()` + `_loadGroupPushRecipients()` using Dart record destructuring `.wait`
3. Pre-upload persistence: copy to `pending_uploads/...`, persist `upload_pending` attachment with relative path + pre-generated `blobId`
4. New use case: `lib/features/groups/application/retry_incomplete_group_uploads_use_case.dart`
   - Groups attachments by messageId, re-uploads only `upload_pending`, calls `sendGroupMessage` once per message
   - Stable-ID contract: reuse same blobId
   - Delete pending dir only after final send success
5. Attachment-scoped `upload_retry_count` on `media_attachments` (not `group_messages`)
6. Wire into resume handler inside group-recovery gate, AFTER recoverStuck, BEFORE retryFailed

**Test file (11 tests):** Create appropriate test files per plan:
- Parallel upload timing tests
- Pre-upload persistence tests
- Retry use case tests
- Resume handler ordering test

**Test command:** `flutter test test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart` + related test files

---

#### WU-8: Go 10.2 + 10.3 — Grace Period + Decryption Events

**Plan sections to read:**
- "Go-Side Changes" 10.2 (lines ~1590–1594)
- "Go-Side Changes" 10.3 (lines ~1596–1613)
- Section 7.2 "Dual-Epoch Grace Period (Go)" (lines ~1142–1160)

**Deliverables:**
1. Extend `GroupKeyInfo` with `PrevKey`, `PrevKeyEpoch`, `GraceDeadline`
2. `groupTopicValidator`: dual-epoch verification with grace check
3. `UpdateGroupKey`: preserve previous key + set grace deadline; no-op on stale/equal epochs
4. `KeyRotationGracePeriod = 30 * time.Second` in config
5. Decryption: `handleGroupSubscription` grace-period fallback (try prevKey if current fails during grace)
6. Emit `group:decryption_failed` and `group:payload_parse_failed` events
7. Add `group:generateNextKey` bridge command
8. Go tests (6): grace period validator tests, UpdateGroupKey preserves prev key, first join no grace, old-epoch decrypt during grace

**Note:** Human runs `make all` manually after agent writes code.

---

### Phase 2, Step 2 — Only if Go 10.2 was needed for Dart S7 testing

No additional Dart work depends on Go 10.2 within Phase 2. Proceed to Phase 3.

---

## Phase 3 (P2–P3) — Voice + Key Rotation + Config Sync + Proofs + Infra

### Phase 3, Step 1 (launch in parallel)

#### WU-9: Section 6 — Voice Message Reliability

**Plan section to read:** Section 6 (lines ~1068–1121)

**Depends on:** WU-7 (S5 parallel media) must have passed QA.

**Deliverables:**
1. Refactor `_onRecordStop` in `group_conversation_wired.dart`:
   - Generate stable `attachmentId` and `messageId`
   - Copy to durable storage before upload
   - Persist `upload_pending` attachment row before upload
   - Pass `blobId: attachmentId` to uploadMediaFn
   - Resolve stored relative path to absolute for upload call
   - Delete pending_uploads dir only after final send success
2. Fail path: preserve retryable state (durable file, status failed, attachment upload_pending with same blobId)
3. Guard: voice path unavailable if `mediaAttachmentRepo` or `mediaFileManager` null
4. Preserve existing quote-restoration behavior on failure

**Test file (6 tests):** `test/features/groups/presentation/screens/group_voice_reliability_test.dart` (or per plan naming)

---

#### WU-10: Section 7 — Key Rotation Safety Window (Dart side)

**Plan section to read:** Section 7 (lines ~1124–1269)

**Depends on:** WU-8 (Go 10.2 grace period) must have passed QA.

**Deliverables:**
1. Refactor `rotateAndDistributeGroupKey`: generate next key without Go activation → distribute to all members first → update own Go validator last → broadcast key_rotated
2. New bridge helper: `callGroupGenerateNextKey` in `bridge_group_helpers.dart`
3. `GoBridgeClient`: add `group:generateNextKey` support
4. `GroupKeyUpdateListener`: promote only after `callGroupUpdateKey` succeeds
5. `group_info_wired.dart`: preserve current removal flow while using new rotation semantics
6. Distribution timeout: 15s global, concurrent per-member sends

**Test files (5 Dart tests, tests 7–11 from plan):**
- Rotation distribution order test
- Distribution timeout test
- Listener promotion test
- Generated key not persisted before promotion test
- `group_info_wired_test.dart` for removal flow compatibility

---

#### WU-11: Section 9 — Member Config Sync Atomicity

**Plan section to read:** Section 9 (lines ~1362–1438)

**Independent — no dependencies on other Phase 3 items.**

**Deliverables:**
1. `addGroupMember`: add `syncBridgeConfig` param, `callGroupUpdateConfig` + rollback on failure
2. `removeGroupMember`: capture member, restore on bridge failure
3. `GroupMessageListener`: add `_configUpdateLock` per-group future chain, resync-retry, CONFIG_SYNC_FAILED emission
4. Batch callers (`contact_picker_wired.dart`, `create_group_with_members_use_case.dart`): pass `syncBridgeConfig: false`, own final config update

**Test file (7 tests):** per plan Section 9.4

---

### Phase 3, Step 2 (after Step 1 passes QA)

#### WU-12: Section 10 — Announcement Acceptance Proofs

**Plan section to read:** Section 10 (lines ~1442–1501)

**Depends on:** S1 (WU-4), S3 (WU-6), S7 (WU-10), S8 (WU-3) must all be in place.

**Deliverables:** 6 acceptance proof test scenarios (10-A through 10-F):
- Admin text + lock → delivered
- Admin media + lock → delivered
- Admin voice + lock → delivered
- Non-admin rejection + no unauthorized row
- Reader catch-up on resume
- Post-rotation announcement authorization

These are primarily integration/widget tests exercising the full reliability pipeline for announcement groups.

---

### Phase 3, Step 3 (after Step 2 passes QA)

#### WU-13: Section 11 — Test Infrastructure

**Plan section to read:** Section 11 (lines ~1504–1577)

**Deliverables:**
1. `_ZeroPeerPublishBridge` helper (or equivalent response preset)
2. `GroupTestUser.sendGroupMessageViaBridge(...)` extension
3. Extend `InMemoryGroupMessageRepository` to mirror all new production methods
4. 7 integration test scenarios in `test/features/groups/integration/group_message_retry_smoke_test.dart`

---

## QA Agent Instructions Template

For every QA run, the QA agent must:

```
1. Read the plan section for this work unit (exact line range given above)
2. Read every file the implementation agent created or modified (use git diff to find them)
3. Run: flutter test <specific_test_file> --reporter=expanded
4. Run: flutter test test/features/groups/ (regression check)
5. Run: flutter analyze lib/ (no new warnings)
6. Check:
   a. Do ALL new tests pass?
   b. Do existing group tests still pass?
   c. Does the code match the plan? (file paths, function names, SQL queries, test names)
   d. Are function signatures exactly as specified?
   e. Are FLOW event names exactly as specified?
   f. Does the implementation follow existing codebase patterns? (DI injection style, repo patterns, fake patterns)
   g. Is the InMemoryGroupMessageRepository fake updated for any new abstract methods?
   h. Is main.dart DI wiring updated?
7. Return: PASS or FAIL with numbered findings
```

## Fix Agent Instructions Template

```
You are fixing QA findings for work unit [WU-N].

QA Findings:
[paste numbered findings]

For each finding:
1. Read the relevant file
2. Apply the fix
3. Run the specific test that failed
4. Verify it passes

After all fixes:
- Run the full test suite for the work unit
- Run flutter test test/features/groups/ for regression check
```

---

## Summary of Work Units

| WU | Section | Phase.Step | Parallel With | Key Test File |
|----|---------|------------|---------------|---------------|
| 1 | DB Schema + Model | 1.1 | WU-2 | `group_messages_db_helpers_reliability_test.dart` |
| 2 | Go 10.1 | 1.1 | WU-1 | `pubsub_delivery_test.go` |
| 3 | S4+S8+Wire Envelope | 1.2 | — | `send_group_message_use_case_test.dart` + new S4/S8 test files |
| 4 | S1 | 1.3 | — | 4 test files per plan |
| 5 | S2 | 2.1 | WU-6,7,8 | `handle_app_paused_group_test.dart` |
| 6 | S3 | 2.1 | WU-5,7,8 | `group_conversation_wired_bg_task_test.dart` |
| 7 | S5 | 2.1 | WU-5,6,8 | `retry_incomplete_group_uploads_use_case_test.dart` |
| 8 | Go 10.2+10.3 | 2.1 | WU-5,6,7 | `pubsub_test.go` |
| 9 | S6 | 3.1 | WU-10,11 | `group_voice_reliability_test.dart` |
| 10 | S7 | 3.1 | WU-9,11 | rotation + listener tests |
| 11 | S9 | 3.1 | WU-9,10 | config sync tests |
| 12 | S10 | 3.2 | — | announcement proof tests |
| 13 | S11 | 3.3 | — | `group_message_retry_smoke_test.dart` |

---

## Critical Rules

1. **Read before write.** Every agent MUST read the existing file before modifying it. Read the plan section. Read codebase patterns (DI, repos, fakes, bridge helpers).
2. **Plan is law.** Use exact file paths, function names, SQL queries, test names, and FLOW event names from the plan.
3. **TDD cycle.** Write the failing test first, then the implementation that makes it pass, then refactor.
4. **No Go compilation in agents.** Go agents write code + tests only. Human runs `make all` manually.
5. **Regression check.** Every QA run must include `flutter test test/features/groups/` to catch cross-section regressions.
6. **One work unit = one agent.** Do not combine work units. Each agent reads only its section.
7. **Fakes must stay in sync.** If a new abstract method is added to a repository, the InMemoryGroupMessageRepository (or other test fake) MUST be updated in the same work unit.
8. **DI wiring.** If a new dependency is introduced, `main.dart` must be updated. Check the DI chain documented in CLAUDE.md memory.
