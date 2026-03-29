# 29 - Batch Parallel Introduction Sending with Concurrency Cap

**Feature Improvement**

---

## 1. Problem Statement

When user-A introduces multiple friends to user-C, all introduction messages
are sent **sequentially** in a `for` loop. Each introduction requires 2 P2P
sends (one to recipient, one to introduced friend) plus a DB save, all
`await`ed in sequence. For 5 friends, this means 10 sequential network calls
plus 5 DB writes, resulting in noticeable UI blocking.

**Current behavior** (send_introduction_use_case.dart:51–137):

```
for (final friend in friendsToIntroduce) {
    await _sendPayload(... to recipient ...);    // blocks
    await _sendPayload(... to friend ...);       // blocks
    await introRepo.saveIntroduction(...);        // blocks
}
```

- 5 friends = ~6–20 seconds total (depending on network latency and encryption)
- 100 friends would take minutes
- No concurrency cap — no batching
- No progress feedback during send (button disabled, no progress indicator)
- UI is blocked until all intros complete

**What is needed:**

- Introductions should be sent **simultaneously** (in parallel), not one after
  another.
- When many friends are selected (e.g., 100), send in **batches of 10** — 10
  intros dispatched concurrently, then the next 10, and so on.
- A cap of 10 concurrent intro sends prevents overwhelming the P2P layer.

**Who is affected:** Any user introducing more than 1 friend at a time.

---

## 2. Impact Analysis

| Dimension | Assessment |
|-----------|-----------|
| Severity | Moderate — blocks UI for several seconds per batch of friends |
| Frequency | Every time a user introduces multiple friends |
| User consequence | Long wait with no progress feedback; may think the app froze |
| Workaround | None — user must wait for sequential sends to complete |
| Platform scope | iOS and Android (Flutter) |

| Friends Selected | Current Sequential Time (est.) | Parallel Batch of 10 Time (est.) |
|-----------------|-------------------------------|----------------------------------|
| 5 | ~6–20s | ~1–4s (single batch) |
| 10 | ~12–40s | ~1–4s (single batch) |
| 20 | ~24–80s | ~2–8s (2 batches) |
| 100 | ~120–400s | ~10–40s (10 batches) |

---

## 3. Current State

### 3.1 Send Introduction Use Case

| File | Key Lines |
|------|-----------|
| `lib/features/introduction/application/send_introduction_use_case.dart` | Lines 51–137 |

**`sendIntroductions()`** (line 20):
- Parameters: `contactRepo`, `introRepo`, `p2pService`, `bridge`,
  `introducerPeerId`, `introducerUsername`, `recipientPeerId`,
  `recipientUsername`, `recipientMlKemPublicKey`, `friendsToIntroduce` (List).
- Sequential `for` loop over `friendsToIntroduce` (line 51).
- Per friend: builds 2 payloads (recipient + introduced), sends both via
  `_sendPayload()`, saves to DB — all `await`ed (lines 90, 100, 124).
- `_sendPayload()` (lines 154–187): encrypts (if ML-KEM key available), sends
  via `p2pService.sendMessage()`, falls back to `storeInInbox()` on failure.
- Flow events emitted: `SEND_INTRODUCTIONS_START`, `SEND_INTRODUCTION_SENT`
  (per friend), `SEND_INTRODUCTIONS_DONE`.

### 3.2 Friend Picker UI

| File | Key Lines |
|------|-----------|
| `lib/features/introduction/presentation/screens/friend_picker_wired.dart` | Lines 97–138 |
| `lib/features/introduction/presentation/screens/friend_picker_screen.dart` | Lines 40, 172 |

- **Selection:** `_selectedPeerIds` (Set<String>) — no upper bound on selection
  count (line 41 in wired).
- **Send trigger:** `_onSend()` passes all selected friends to
  `sendIntroductions()` in one call (line 121).
- **Progress state:** `_isSending` boolean (line 45); button disabled during
  send, no per-batch progress indicator.
- **Guard:** `if (_isSending || _selectedPeerIds.isEmpty) return` prevents
  double-send (line 98).

### 3.3 P2P Send Interface

| File | Key Lines |
|------|-----------|
| `lib/core/services/p2p_service.dart` | Lines 59, 105 |

- `sendMessage(String peerId, String message)` — single message to single peer.
- `storeInInbox(String toPeerId, String message)` — single message fallback.
- No batch or parallel send methods exist in the interface.

### 3.4 Go Bridge

- `bridge.go` `SendMessage()` (lines 702–743): accepts single `peerId` +
  `message`. No batch capability.
- `InboxStore()` (lines 750–783): single message storage. No batch.

### 3.5 Introduction Payload

| File | Key Lines |
|------|-----------|
| `lib/features/introduction/domain/models/introduction_payload.dart` | Lines 18–51 |

- Each payload represents one introduction (one introduced friend).
- `introductionId` is unique per introduction (UUID generated per friend).
- Payloads serialized individually for encryption.

### 3.6 Existing Tests

| File | Coverage |
|------|----------|
| `test/features/introduction/application/send_introduction_test.dart` | Tests 2-friend send; verifies 4 P2P deliveries (2 friends x 2 messages each) |
| `test/features/introduction/integration/introduction_smoke_test.dart` | Tests 2-friend intro flow end-to-end |

- No test exists for >10 friends.
- No test for concurrent/parallel sending.
- No test for batch progress.

---

## 4. Scope Clarification

| Area | Status | Notes |
|------|--------|-------|
| Parallel sending of intros within a batch | **In scope** | Core improvement |
| Batch size cap of 10 concurrent sends | **In scope** | Prevents P2P overload |
| Progress indicator for batch sending | **In scope** | User should see progress |
| Cap on maximum number of friends to introduce | **Out of scope** | No selection limit requested |
| P2P batch send API (Go bridge) | **Out of scope** | Use existing single-message API concurrently |
| Cancellation mid-batch | **Out of scope** | Not requested |
| Retry on individual send failure | **Unchanged** | Existing inbox fallback stays |
| Introduction payload structure | **Unchanged** | One payload per friend |
| Friend picker UI (selection) | **Unchanged** | No changes to selection flow |
| DB persistence per intro | **Unchanged** | Each intro still saved individually |

---

## 5. Test Cases

### Group A: Parallel Sending Within a Batch

**TC-29-A01** — 5 intros sent in parallel (single batch)
Given user-A selects 5 friends to introduce to user-C,
when user-A taps "Introduce 5 friends",
then all 5 introductions' P2P messages are dispatched concurrently (not
sequentially), and the total send time is approximately equal to the time of
the slowest single intro (not 5x a single intro).

**TC-29-A02** — 10 intros sent in parallel (single batch at cap)
Given user-A selects 10 friends to introduce to user-C,
when user-A taps "Introduce 10 friends",
then all 10 introductions are dispatched concurrently in a single batch.

**TC-29-A03** — Each intro still sends 2 P2P messages (recipient + introduced)
Given user-A introduces 3 friends to user-C,
when the batch completes,
then 6 P2P messages total were sent (3 to recipient + 3 to introduced friends),
and 3 introduction records were saved to the DB.

### Group B: Batching for Large Selections

**TC-29-B01** — 15 intros sent in 2 batches (10 + 5)
Given user-A selects 15 friends to introduce to user-C,
when user-A taps send,
then the first batch of 10 intros is sent concurrently, and after those
complete, the remaining 5 are sent concurrently.

**TC-29-B02** — 30 intros sent in 3 batches (10 + 10 + 10)
Given user-A selects 30 friends,
when user-A taps send,
then 3 sequential batches of 10 are processed, each batch's intros sent
concurrently within the batch.

**TC-29-B03** — 100 intros sent in 10 batches
Given user-A selects 100 friends,
when user-A taps send,
then 10 sequential batches of 10 are processed. No more than 10 concurrent
P2P send operations are active at any time.

**TC-29-B04** — Exact batch boundary (20 intros = exactly 2 batches)
Given user-A selects exactly 20 friends,
when user-A taps send,
then exactly 2 batches of 10 are processed with no leftover partial batch.

### Group C: Progress Feedback

**TC-29-C01** — Progress indicator shows during batch sending
Given user-A sends 20 intros (2 batches),
when the first batch is in progress,
then the UI shows progress feedback indicating how many intros have been
sent (e.g., "10 of 20 sent" or a progress bar).

**TC-29-C02** — Progress updates between batches
Given user-A sends 30 intros (3 batches),
when batch 1 completes and batch 2 begins,
then the progress indicator updates to reflect batch 1 completion.

**TC-29-C03** — Send button is disabled during entire send process
Given user-A taps send for 20 intros,
when batches are in progress,
then the send button remains disabled until all batches complete (no
double-send possible).

### Group D: Error Handling

**TC-29-D01** — One intro fails in a batch, others succeed
Given user-A sends 10 intros in one batch and 1 friend is offline with no
inbox available,
when 9 intros succeed and 1 falls back to inbox storage,
then all 10 intros are saved to the DB, the 9 successful ones are marked sent,
and the 1 that used inbox fallback is still recorded.

**TC-29-D02** — Multiple failures in a batch do not block the batch
Given 3 of 10 intros in a batch have P2P send failures,
when the batch processes,
then the 3 failures fall back to inbox storage (existing behavior), and the
batch completes without blocking on the failures.

**TC-29-D03** — Failure in batch 1 does not prevent batch 2 from starting
Given user-A sends 20 intros, and 2 intros in batch 1 fail (fall back to inbox),
when batch 1 finishes,
then batch 2 proceeds normally with the next 10 intros.

**TC-29-D04** — All intros in a batch fail (e.g., P2P node down)
Given the P2P node is unreachable,
when a batch of 10 intros is sent,
then all 10 fall back to inbox storage, all 10 are saved to the local DB,
and the next batch still proceeds.

### Group E: Data Integrity

**TC-29-E01** — All intros have unique IDs regardless of concurrency
Given user-A sends 10 intros concurrently,
when all intros complete,
then each introduction record has a unique UUID (no ID collisions from
concurrent UUID generation).

**TC-29-E02** — DB records are consistent after concurrent saves
Given 10 intros are sent and saved concurrently within a batch,
when all saves complete,
then the `introductions` table contains exactly 10 new rows with correct
data for each introduced friend.

**TC-29-E03** — Both parties receive correct payloads in concurrent sends
Given intros for friends C, D, E are sent concurrently,
when user-C receives their intro payload,
then the payload contains the correct `introducedId` (C's peer ID), not D's
or E's. Each recipient gets only their own introduction data.

**TC-29-E04** — `introsSentAt` set on recipient contact after all batches complete
Given user-A sends 20 intros to user-C in 2 batches,
when all batches complete,
then `contactRepo.setIntrosSentAt(recipientPeerId, ...)` is called once with
the final timestamp (not once per batch).

### Group F: Regression

**TC-29-F01** — Single friend introduction still works
Given user-A selects exactly 1 friend to introduce,
when user-A taps send,
then the intro is sent normally (2 P2P messages, 1 DB save) with no
batching overhead.

**TC-29-F02** — Introduction notifications still fire on receiver side
Given user-C receives 5 concurrent intro P2P messages,
when the `IntroductionListener` processes them,
then 5 local notifications fire and the intros appear in user-C's Intros tab.

**TC-29-F03** — Flow events still emitted correctly
Given user-A sends 10 intros in parallel,
when the batch completes,
then flow events `SEND_INTRODUCTIONS_START`, `SEND_INTRODUCTION_SENT` (x10),
and `SEND_INTRODUCTIONS_DONE` are all emitted (order of per-intro events
may vary due to concurrency).

**TC-29-F04** — Encryption still applied per message
Given all friends have ML-KEM public keys,
when 10 intros are sent concurrently,
then each of the 20 P2P messages is individually encrypted with the correct
recipient's key (no shared/reused ciphertext).
