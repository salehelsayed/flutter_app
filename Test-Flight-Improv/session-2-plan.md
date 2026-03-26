# Session 2 Plan: Feed Inline Reply Durable-Send Regression

**Status:** Sufficient — safe to execute as a RED-first contract session
**Verdict:** Revised to add permanence/classification coverage, correct fake semantics, and remove stale assumptions

---

## 1. Scope

**Deliver:**

- Expand `test/features/feed/presentation/screens/feed_wired_test.dart` with a direct assertion that `InMemoryMessageRepository.updateWireEnvelope` performs a real write.
- Expand `test/features/feed/presentation/screens/feed_wired_test.dart` with one surface-driven `FeedWired` inline-reply parity regression that blocks network completion and asserts the conversation-style durable row exists before send completes.
- Fix `InMemoryMessageRepository.updateWireEnvelope` at `test/shared/fakes/in_memory_message_repository.dart:257` from no-op to real-write semantics that match the current group fake and real repository behavior: update the row if it exists, no-op if it does not.
- Add a minimal classification/reference update in:
  - `Test-Flight-Improv/test-gate-definitions.md`
  - `Test-Flight-Improv/test-gates-reference.md`
  stating that this regression is required companion direct coverage whenever feed-originated 1:1 send behavior changes, while keeping the named gate file lists frozen.

**Will NOT do:**

- Fix any behavior in `feed_wired.dart` or `send_chat_message_use_case.dart`
- Add a new `test/features/conversation/integration/` file
- Modify `scripts/run_test_gates.sh` or change the frozen named gate file lists
- Promote the new regression into a named gate in this session
- Refactor any production code

---

## 2. Files to Inspect Next (Execution Session)

| File | Why |
|------|-----|
| `test/features/feed/presentation/screens/feed_wired_test.dart` | Reuse the existing `FeedWired` harness and `_GatedP2PService` helper that already block in-flight sends at the real surface |
| `test/shared/fakes/in_memory_message_repository.dart` | Confirm `updateWireEnvelope` no-op, fix it |
| `test/shared/fakes/in_memory_group_message_repository.dart` | Use the group fake as the write-through precedent for `updateWireEnvelope` |
| `test/features/conversation/integration/send_then_lock_delivery_test.dart` | Reconfirm the existing conversation-path durable-send owner proof |
| `lib/features/feed/presentation/screens/feed_wired.dart` lines 1040-1080 | Re-confirm the actual `_onInlineSend` gap at the owning feed surface |
| `lib/features/conversation/presentation/screens/conversation_wired.dart` | Reconfirm optimistic pre-save + `messageId:` parity reference |
| `lib/features/conversation/application/send_chat_message_use_case.dart` | Reconfirm pre-persist contract and why the assertion must happen before network completion |
| `Test-Flight-Improv/test-gate-definitions.md` | Reconfirm how new high-value cross-feature regressions must be classified even when they stay outside the frozen named gates |
| `Test-Flight-Improv/test-gates-reference.md` | Add the plan-facing companion-direct-suite note without changing the script-owned gate lists |

---

## 3. Existing Tests Covering This Area

| Test | What It Proves | Feed Path? |
|------|---------------|------------|
| `feed_card_flow_test.dart` | Feed card UI/session-reply state transitions | No send |
| `expanded_collapsed_card_test.dart` | Feed card expand/collapse behavior | No send |
| `feed_wired_test.dart` | Real `FeedWired` widget harness; already covers inline optimism/failure and group retry-discoverable send, but not 1:1 durable pre-persist parity | Yes, but not the missing 1:1 contract |
| `two_user_message_exchange_test.dart` | Two-user send/receive, dedup, inbox | Conversation path only |
| `send_then_lock_delivery_test.dart` | Existing conversation-path durable-send owner proof across interruption/recovery | Conversation path only |
| `stuck_sending_recovery_test.dart` | Shared `recoverStuckSending` + `retryFailed` round-trip | Shared retry path only |
| `offline_inbox_roundtrip_test.dart` | Offline inbox fallback | Conversation path only |

**Gap confirmed in the current repo:** No existing test enters 1:1 send from `FeedWired` and inspects the message repository before network completion. Code evidence: `feed_wired.dart:1068` calls `sendChatMessage` without `messageId:`, so the pre-race `updateWireEnvelope` write at `send_chat_message_use_case.dart:188` is skipped.

By contrast, `conversation_wired.dart` at line 641 creates an optimistic message, saves it at line 662, and passes `messageId: optimisticMessage.id` at line 768 into `sendChatMessage`, which triggers the pre-persist contract at line 189. Existing conversation durability coverage already assumes that contract, for example `send_then_lock_delivery_test.dart` asserts a paused conversation-path message still has `wireEnvelope`.

---

## 4. Regression/Tests to Add

**File:** `test/features/feed/presentation/screens/feed_wired_test.dart`

**Location rationale:** The missing proof belongs at the real feed surface. Reusing `feed_wired_test.dart` keeps the work in the owning surface file, avoids a new `integration` path, and uses the exact `FeedWired` harness that already drives inline reply through `_onInlineSend`. Because this is still a new high-value cross-feature regression, Session 2 must also record it in the gate/reference docs as required companion direct coverage.

**Pre-requisite fix:** `test/shared/fakes/in_memory_message_repository.dart` — change `updateWireEnvelope` from no-op to null-safe write-through for existing rows only.

| Test | Proves |
|------|--------|
| **Test 1:** `updateWireEnvelope` writes through for an existing row | Prevents a false green caused by the current in-memory fake no-op; mirrors the existing group fake behavior |
| **Test 2:** feed inline 1:1 reply becomes retry-discoverable before network completes | Drives the real `FeedWired` inline reply path with `_GatedP2PService` still blocked and asserts the intended parity contract: outgoing row exists, `status == 'sending'`, `wireEnvelope != null`. This is the Session 2 RED regression against current production behavior. |

**Fakes/helpers reused (all confirmed present):**

- `InMemoryMessageRepository` (`test/shared/fakes/in_memory_message_repository.dart`) — after fix
- `FakeP2PService` / `_GatedP2PService` (`test/features/feed/presentation/screens/feed_wired_test.dart`)
- `FakeBridge` (`test/core/bridge/fake_bridge.dart`)
- `FakeContactRepository` (`test/features/contacts/domain/repositories/fake_contact_repository.dart`)
- `FakeIdentityRepository` (`test/features/identity/domain/repositories/fake_identity_repository.dart`)
- Existing `buildFeedWired()` harness in `feed_wired_test.dart`

**No new fakes required.**

---

## 5. Step-by-Step Implementation Plan

1. **Read** all files listed in Section 2
2. **Fix** `InMemoryMessageRepository.updateWireEnvelope` — replace `async {}` with null-safe existing-row write-through. Use `InMemoryGroupMessageRepository.updateWireEnvelope` and the real repository’s missing-row no-op semantics as the local precedent.
3. **Expand** `test/features/feed/presentation/screens/feed_wired_test.dart` — do not create a new `test/features/conversation/integration/` file
4. **Add a brief test comment only if needed** to explain the blocked-send assertion window: `feed_wired.dart:1068` omits `messageId:`, `send_chat_message_use_case.dart:188` gates `updateWireEnvelope` on `messageId != null`, so the assertion must happen while the send is still blocked
5. **Write Test 1:** seed a message row in `InMemoryMessageRepository`, call `updateWireEnvelope`, and assert the stored row now has the expected `wireEnvelope`
6. **Write Test 2 setup:** reuse `buildFeedWired()` + `_GatedP2PService`, seed identity/contact plus one read incoming message so the card starts in collapsed inline-reply mode
7. **Drive the real feed surface:** type into the inline reply composer, tap send, keep `_GatedP2PService.sendGate` closed, and inspect `messageRepo` before unblocking
8. **Assert the intended parity contract:** while the gate is still closed, expect an outgoing repo-backed message for the inline reply with `status == 'sending'` and `wireEnvelope != null`. This is expected RED on current code and is the key Session 2 evidence.
9. **Unblock** the gate and pump cleanup frames so the async send does not leak into later tests
10. **Update** `Test-Flight-Improv/test-gate-definitions.md` and `Test-Flight-Improv/test-gates-reference.md` to classify the new regression as required companion direct coverage for feed-originated 1:1 send changes, without changing `scripts/run_test_gates.sh` or the frozen named gate membership
11. **Run** the direct precondition test, the direct RED parity regression, and the full `feed_wired_test.dart` file, recording the parity regression as expected RED evidence unless later repo changes have already closed the gap
12. **Run** `./scripts/run_test_gates.sh feed` and `./scripts/run_test_gates.sh 1to1`
13. **Run** `./scripts/run_test_gates.sh baseline` and record only the existing unrelated `loading_states_smoke_test.dart` failure

---

## 6. Risks and Edge Cases

| Risk | Mitigation |
|------|-----------|
| `updateWireEnvelope` no-op in fake | Fix it as Step 2 with null-safe existing-row semantics (structural blocker, mandatory) |
| Shared fake edit could diverge from real repository behavior | Keep the fix minimal: existing-row write-through, missing-row no-op, no script-owned gate changes, and no new change-stream behavior |
| Post-failure assertions cannot distinguish pre-race durability from the later failure-save path | Assert repository state while `_GatedP2PService.sendGate` is still blocked; do not inspect only after send failure |
| Execution may happen after later repo edits | Current repo evidence still shows the gap. If later changes land before execution, revalidate `feed_wired.dart`, `conversation_wired.dart`, and `send_chat_message_use_case.dart` before assuming RED is still expected |
| Async send can leak across widget tests | Always complete `_GatedP2PService.sendGate` and pump cleanup frames before test exit |
| Baseline Gate is currently stale/red for unrelated reasons | Treat the known `loading_states_smoke_test.dart` build failure as pre-existing evidence, not as a Session 2 blocker |
| New regression is not permanent if it only exists as an unclassified direct test | Record it in `test-gate-definitions.md` and `test-gates-reference.md` as required companion direct coverage while keeping the named gate file lists frozen |

---

## 7. Exact Tests to Run After Implementation

```bash
# Direct fake-precondition proof
flutter test test/features/feed/presentation/screens/feed_wired_test.dart \
  --plain-name "updateWireEnvelope writes through for an existing row"

# Session 2 parity regression (expected RED until Session 3 fixes feed parity)
flutter test test/features/feed/presentation/screens/feed_wired_test.dart \
  --plain-name "feed inline 1:1 reply becomes retry-discoverable before network completes"

# Owning surface file after the shared fake + new regression edits
flutter test test/features/feed/presentation/screens/feed_wired_test.dart

# Classification/reference verification for the new permanent regression
rg -n "feed_wired_test.dart|feed inline 1:1|companion direct" \
  Test-Flight-Improv/test-gate-definitions.md \
  Test-Flight-Improv/test-gates-reference.md

# Feed / Surface Gate
./scripts/run_test_gates.sh feed

# 1:1 Reliability Gate (unchanged 9-file frozen gate)
./scripts/run_test_gates.sh 1to1

# Baseline Gate (currently known-red for unrelated loading-states build break)
./scripts/run_test_gates.sh baseline
```

---

## 8. Subsystem Gates

| Gate | Files | Needed? |
|------|-------|---------|
| **1:1 Reliability** | 9 files (unchanged frozen gate) | Yes — shared send-path owner gate |
| **Feed / Surface** | 3 files (unchanged frozen gate) plus one documented companion direct regression in `feed_wired_test.dart` | Yes — this is the trigger surface |
| **Startup / Transport** | 4 integration_test files | No — this session stays in fake/widget scope and does not touch bootstrap or transport fallback behavior |
| **Baseline** | 6 files (unchanged frozen gate) | Yes — run and record the existing known-red result separately |

---

## 9. Done Criteria

1. `test/features/feed/presentation/screens/feed_wired_test.dart` contains the new Session 2 durability block; no new `test/features/conversation/integration/` file was created
2. `InMemoryMessageRepository.updateWireEnvelope` performs a real write for an existing row and no-ops for a missing row, matching current repository semantics and verified by direct assertion
3. The targeted parity regression enters via real `FeedWired` inline reply, not by calling `sendChatMessage` directly
4. While `_GatedP2PService.sendGate` is still blocked, the regression asserts for a repo-backed outgoing row with `status == 'sending'` and `wireEnvelope != null`
5. The targeted parity regression produces expected RED evidence on the current repo state unless later upstream changes land before execution and close the gap first
6. `Test-Flight-Improv/test-gate-definitions.md` and `Test-Flight-Improv/test-gates-reference.md` explicitly classify/reference the new regression as required companion direct coverage for feed-originated 1:1 send changes
7. `flutter test test/features/feed/presentation/screens/feed_wired_test.dart` exits 0 aside from the intentional RED parity regression before Session 3
8. `./scripts/run_test_gates.sh feed` exits 0
9. `./scripts/run_test_gates.sh 1to1` exits 0
10. `./scripts/run_test_gates.sh baseline` shows only the known unrelated `loading_states_smoke_test.dart` failure already documented in Session 1 artifacts
11. `scripts/run_test_gates.sh` and the frozen named gate file lists remain unchanged
12. No behavior in `feed_wired.dart` or `send_chat_message_use_case.dart` was modified

---

## Review Findings Incorporated

### Structural Blockers (patched)

| Finding | Resolution |
|---------|-----------|
| Directly calling `sendChatMessage` without `messageId:` does not prove the feed surface; it only re-tests the use case in isolation | Moved the regression into `test/features/feed/presentation/screens/feed_wired_test.dart` so it drives real `FeedWired` inline reply through `_onInlineSend` |
| Treating the new regression as “already classified” just because it stays in `feed_wired_test.dart` would leave it non-permanent | Added minimal updates to `test-gate-definitions.md` and `test-gates-reference.md` so the regression is recorded as required companion direct coverage without changing `scripts/run_test_gates.sh` or the frozen named gate lists |
| A post-failure `wireEnvelope` assertion cannot prove pre-race durability because the failed-send path also writes `wireEnvelope` later | Replaced the design with a blocked-send assertion that inspects repository state before network completion |
| The prior verification section used stale raw gate commands and a stale 5-file baseline assumption | Switched verification to `./scripts/run_test_gates.sh` and recorded the current 6-file baseline plus its known unrelated failure |
| The proposed fake fix used force-unwrapped row access, which does not match the real repository or the group fake | Changed the fake-fix contract to existing-row write-through with missing-row no-op semantics |
| The prior risk section treated the feed gap as only a possible stale audit issue | Rebased the plan on the current repo state: `feed_wired.dart` still omits `messageId:` on the inline 1:1 send path |

### Incremental Details (deferred)

| Finding | Disposition |
|---------|------------|
| Existing conversation durability coverage already proves the owner contract | Reused `send_then_lock_delivery_test.dart` as existing evidence instead of duplicating that proof in a second harness |
| Gate promotion for the new feed-surface assertion | Deferred. Session 2 records the regression in the gate/reference docs as companion direct coverage, but leaves named gate promotion for a later session if the team wants it after the production fix lands. |
| Future repo edits could land before execution | Handled in Risks and Done Criteria: current repo evidence still shows the gap, but execution must revalidate if later merges land first |

---

## Why It Is Safe to Execute Now

- The plan now enters the actual owning surface at `feed_wired.dart:1041-1078`, not a use-case surrogate
- The blocked-send assertion cleanly distinguishes the missing pre-race durability contract from the later failure-save path in `send_chat_message_use_case.dart`
- The single fake blocker (`InMemoryMessageRepository.updateWireEnvelope`) still has a minimal mechanical fix, but now with semantics aligned to the real repository and the group fake
- The plan now records the regression in `test-gate-definitions.md` and `test-gates-reference.md`, so it becomes permanent coverage without widening the named gate file lists
- Verification now matches the Session 1 frozen source of truth: script-based gates, unchanged gate contents, and explicit handling of the already-known baseline failure
- The plan no longer relies on a stale “maybe already fixed” assumption: the current repo still shows the feed inline 1:1 `messageId:` gap
- The plan is explicit that Session 2 is a RED-first contract session and that Session 3 is responsible for flipping the parity regression green by fixing production behavior
