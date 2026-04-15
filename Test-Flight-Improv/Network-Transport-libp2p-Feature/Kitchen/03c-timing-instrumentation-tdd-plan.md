# Timing Instrumentation — TDD Plan

> **Scope:** Test-driven implementation plan for all 24 instrumentation changes — the 9 from `03b-timing-improvement-plan.md` Section 3, the 6 remaining blind spots from `03-timing-and-performance.md` Section 1 ("What's Blind"), group encrypt/decrypt timing (§16), sequential relay failover timing (§17), 6 benchmark-harness-enabling additions (§18–§23) that close the remaining gaps so every test scenario in `03b` Section 2 has the instrumentation a harness needs, and the user-perceived time-to-online-badge metric (§24).
> **Depends on:** `03-timing-and-performance.md` (blind spots, current instrumentation), `03b-timing-improvement-plan.md` (what to add and why).
> **Does not cover:** Hazard fixes (see `03d`), routing changes (see `04b`). Simulator benchmark harness design (the test runner that orchestrates scenarios and computes percentiles) is a separate deliverable — this plan ensures the events exist for it to collect.

---

## Conventions Used Throughout

### Dart Flow Event Pattern

Every existing `_TIMING` event follows this pattern. New instrumentation must match it exactly.

```dart
final stopwatch = Stopwatch()..start();

void emitTiming({required String outcome, Map<String, dynamic> details = const {}}) {
  emitFlowEvent(
    layer: 'FL',
    event: 'EVENT_NAME_TIMING',
    details: {
      'elapsedMs': stopwatch.elapsedMilliseconds,
      'outcome': outcome,
      ...details,
    },
  );
}

// Emit on EVERY exit path — success AND failure.
```

### Dart Test Pattern

All tests use the existing `captureFlowEvents` helper (duplicated per test file). It intercepts `debugPrint` output, parses `[FLOW]`-prefixed JSON, and returns `List<Map<String, dynamic>>`.

```dart
final events = await captureFlowEvents(() async {
  await functionUnderTest(...);
});

final timing = events.firstWhere((e) => e['event'] == 'EVENT_NAME_TIMING');
expect(timing['details']['elapsedMs'], isA<int>());
expect(timing['details']['outcome'], equals('success'));
```

### Go Test Pattern

Go tests use `testEventCollector` (defined in `node_test.go:1222`) and `waitForCollectedEvent` (defined in `group_security_harness_test.go:13`).

```go
collector := &testEventCollector{}
// ... start node with collector as callback ...
// ... trigger operation ...
data := waitForCollectedEvent(t, collector, "event:name", 5*time.Second)
if data["elapsedMs"] == nil {
    t.Fatal("missing elapsedMs")
}
```

---

## 1. Add `_TIMING` Summary Event for Post Delivery

**What:** `POST_CREATE_LOCAL_TIMING` — single summary event covering end-to-end local post creation.

**Why:** `send_post_use_case.dart` already has a `Stopwatch` (line 141: `createStopwatch`) and emits 6+ per-phase events with `elapsedMs`, but no single `_TIMING` summary. Can't aggregate or compare post send latency alongside other send paths.

**File to change:** `lib/features/posts/application/send_post_use_case.dart`
**Test file:** `test/features/posts/phase1/send_post_use_case_test.dart`

### Tests (write first)

**Test 1: Timing event emitted on successful text post**
```
Setup:   Valid post payload, contacts in DB, no media.
Act:     Call createLocalPost().
Assert:  captureFlowEvents contains event with:
         - event == 'POST_CREATE_LOCAL_TIMING'
         - details.elapsedMs is int >= 0
         - details.outcome == 'success'
         - details.hasMedia == false
         - details.recipientCount is int > 0
```

**Test 2: Timing event emitted on successful media post**
```
Setup:   Valid post payload with media draft.
Act:     Call createLocalPost().
Assert:  event 'POST_CREATE_LOCAL_TIMING' with:
         - details.outcome == 'success'
         - details.hasMedia == true
```

**Test 3: Timing event emitted on validation failure (invalid payload)**
```
Setup:   Post payload that fails sanitization (empty text, no media).
Act:     Call createLocalPost().
Assert:  event 'POST_CREATE_LOCAL_TIMING' with:
         - details.outcome == 'invalid_post'
         - details.elapsedMs is int >= 0
```

**Test 4: Timing event emitted on no eligible recipients**
```
Setup:   All contacts blocked or archived.
Act:     Call createLocalPost().
Assert:  event 'POST_CREATE_LOCAL_TIMING' with:
         - details.outcome == 'no_eligible_recipients'
```

### Implementation

In `send_post_use_case.dart`, add a `emitPostTiming` helper using the existing `createStopwatch` (line 141). Emit at each existing `return` statement:

| Return site | Outcome string |
|---|---|
| Line 155 (invalid payload) | `'invalid_post'` |
| Line 192 (no recipients) | `'no_eligible_recipients'` |
| Line 271 (save failed) | `'save_failed'` |
| Line 300 (text success) | `'success'` |
| Line 315 (media success) | `'success'` |

~15 lines: helper definition + 5 call sites.

---

## 2. Add `_TIMING` Summary Event for Local WiFi Transfer

**What:** `LOCAL_MEDIA_SEND_TIMING` — single summary event covering offer → accept → upload → confirm.

**Why:** `local_media_sender.dart` emits 9 per-phase events but none include elapsed duration. Can't measure end-to-end local transfer latency.

**File to change:** `lib/core/local_discovery/local_media_sender.dart`
**Test file:** `test/core/local_discovery/local_media_sender_test.dart`

### Tests (write first)

**Test 1: Timing event emitted on successful transfer**
```
Setup:   Mock receiver that accepts offer and confirms upload.
Act:     Call sendMedia().
Assert:  captureFlowEvents contains event with:
         - event == 'LOCAL_MEDIA_SEND_TIMING'
         - details.elapsedMs is int >= 0
         - details.outcome == 'success'
         - details.mediaId is String
         - details.sizeBytes is int > 0
```

**Test 2: Timing event emitted on offer timeout**
```
Setup:   Mock receiver that never responds to offer.
Act:     Call sendMedia() (times out after 5s).
Assert:  event 'LOCAL_MEDIA_SEND_TIMING' with:
         - details.outcome == 'offer_timeout'
         - details.elapsedMs >= 5000
```

**Test 3: Timing event emitted on offer rejected**
```
Setup:   Mock receiver that sends media_offer_rejected.
Act:     Call sendMedia().
Assert:  event 'LOCAL_MEDIA_SEND_TIMING' with:
         - details.outcome == 'offer_rejected'
```

**Test 4: Timing event emitted on upload HTTP error**
```
Setup:   Mock receiver that accepts offer but HTTP PUT returns 500.
Act:     Call sendMedia().
Assert:  event 'LOCAL_MEDIA_SEND_TIMING' with:
         - details.outcome == 'upload_http_error'
```

**Test 5: Timing event emitted on uploaded confirmation timeout**
```
Setup:   Mock receiver that accepts offer, HTTP succeeds, but never sends media_uploaded.
Act:     Call sendMedia() (times out after 30s).
Assert:  event 'LOCAL_MEDIA_SEND_TIMING' with:
         - details.outcome == 'uploaded_timeout'
```

**Test 6: Timing event emitted on file not found**
```
Setup:   Non-existent file path.
Act:     Call sendMedia().
Assert:  event 'LOCAL_MEDIA_SEND_TIMING' with:
         - details.outcome == 'file_not_found'
```

### Implementation

In `local_media_sender.dart`, add `Stopwatch` at line 37 (top of `sendMedia`). Add `emitSendTiming` helper. Emit before every `return`:

| Return site | Outcome string |
|---|---|
| Line 49 (file not found) | `'file_not_found'` |
| Line 135 (success) | `'success'` |
| Line 142 (catch) | `'error'` |
| Inside `_waitForOfferAccepted`: timeout → `'offer_timeout'`, rejected → `'offer_rejected'` |
| Inside `_waitForMediaUploaded`: timeout → `'uploaded_timeout'`, failed → `'upload_failed'` |
| Line 111 (HTTP error) | `'upload_http_error'` |

Note: The helper closures `_waitForOfferAccepted` and `_waitForMediaUploaded` are private methods that return bool. The timing emission stays in `sendMedia` body by mapping the return values to outcomes.

~20 lines: stopwatch + helper + 6 call sites.

---

## 3. Add `_TIMING` Summary Event for Group Send Per-Step

**What:** Enhance `GROUP_SEND_MSG_TIMING` with per-step sub-timings: `prepareMs`, `publishMs`, `inboxMs`.

**Why:** `send_group_message_use_case.dart` already emits `GROUP_SEND_MSG_TIMING` with total `elapsedMs`, but can't distinguish whether publish, inbox store, or pre-publish settle wait was slow.

**File to change:** `lib/features/groups/application/send_group_message_use_case.dart`
**Test file:** `test/features/groups/application/send_group_message_use_case_test.dart`

### Tests (write first)

**Test 1: Timing event includes publishMs on success**
```
Setup:   FakeBridge with instant group:publish success, group in DB.
Act:     Call sendGroupMessage().
Assert:  captureFlowEvents 'GROUP_SEND_MSG_TIMING' with:
         - details.outcome == 'success'
         - details.elapsedMs is int >= 0
         - details.publishMs is int >= 0
         - details.prepareMs is int >= 0
```

**Test 2: Timing event includes inboxMs when inbox fallback used**
```
Setup:   FakeBridge where publish returns topicPeers=0, inbox store succeeds.
Act:     Call sendGroupMessage().
Assert:  'GROUP_SEND_MSG_TIMING' with:
         - details.inboxMs is int >= 0
```

**Test 3: publishMs reflects actual publish duration**
```
Setup:   _SlowPublishBridge with 200ms delay.
Act:     Call sendGroupMessage().
Assert:  'GROUP_SEND_MSG_TIMING' with:
         - details.publishMs >= 200
```

**Test 4: prepareMs covers key load + recipient resolution**
```
Setup:   _DelayedGroupRepository with 100ms delay on getLatestKey.
Act:     Call sendGroupMessage().
Assert:  'GROUP_SEND_MSG_TIMING' with:
         - details.prepareMs >= 100
```

### Implementation

In `send_group_message_use_case.dart`:

1. Add `prepareStopwatch` at the start of preparation phase (before line 302).
2. Stop `prepareStopwatch` after preparation completes (after line 398). Record `prepareMs`.
3. Add `publishStopwatch` before `callGroupPublish` (before line 425). Stop after await returns. Record `publishMs`.
4. Add `inboxStopwatch` before `_tryInboxStore` (before line 438). Stop after await returns. Record `inboxMs`.
5. Include all three in the existing `emitGroupSendTiming` `details` map.

The existing `emitGroupSendTiming` helper already spreads `...details`. Each call site passes the sub-step durations:

```dart
emitGroupSendTiming(
  outcome: 'success',
  details: {
    'prepareMs': prepareMs,
    'publishMs': publishMs,
    'inboxMs': inboxMs,
    ...existingDetails,
  },
);
```

~20 lines: 3 stopwatches + recording + passing to existing helper.

---

## 4. Per-Step Timing Instrumentation in Go

**What:** Add `elapsedMs` fields to Go events for: stream open, relay warm, rendezvous RTT, and SendMessageWithTransport sub-steps.

**Why:** Go currently has almost no latency measurement. The only timing field in Go is `sinceStartMs` in `addresses:updated`.

**Files to change:**
- `go-mknoon/node/node.go` — `SendMessageWithTransport`, `warmRelayConnection`, `watchConnectionEvents`
- `go-mknoon/node/rendezvous.go` — `RendezvousRegister`, `RendezvousDiscover`

**Test file:** `go-mknoon/node/node_test.go` (existing test infrastructure)

### Tests (write first)

**Test 1: SendMessageWithTransport emits step timing**
```
Setup:   Two connected test nodes (existing test helper pattern).
Act:     Call SendMessageWithTransport from node A to node B.
Assert:  SendMessageResult includes:
         - StreamOpenMs >= 0
         - WriteMs >= 0
         - AckWaitMs >= 0
```

**Test 2: warmRelayConnection emits timing event**
```
Setup:   Test node with relay configured.
Act:     Call Start() which triggers warmRelayConnection.
Assert:  waitForCollectedEvent "relay:warm_timing" with:
         - data.elapsedMs >= 0
         - data.outcome is "success" or "failed"
```

**Test 3: RendezvousRegister includes round-trip timing**
```
Setup:   Test node with relay connected.
Act:     Call RendezvousRegister.
Assert:  waitForCollectedEvent "rendezvous:register_timing" with:
         - data.elapsedMs >= 0
```

**Test 4: RendezvousDiscover includes round-trip timing**
```
Setup:   Test node with relay and registered peer.
Act:     Call RendezvousDiscover.
Assert:  waitForCollectedEvent "rendezvous:discover_timing" with:
         - data.elapsedMs >= 0
```

### Implementation

**Pattern:** Follow `sinceStartMs` pattern from `node.go:1393`.

In `SendMessageWithTransport` (node.go:1042):
```go
func (n *Node) SendMessageWithTransport(...) (*SendMessageResult, error) {
    streamOpenStart := time.Now()
    s, transport, err := n.openChatStreamForSend(ctx, peerID)
    streamOpenMs := time.Since(streamOpenStart).Milliseconds()
    // ... existing code ...
    writeStart := time.Now()
    writeFrame(s, []byte(message))
    writeMs := time.Since(writeStart).Milliseconds()
    
    ackStart := time.Now()
    readFrame(s)
    ackWaitMs := time.Since(ackStart).Milliseconds()
    
    return &SendMessageResult{
        // ... existing fields ...
        StreamOpenMs: streamOpenMs,
        WriteMs:      writeMs,
        AckWaitMs:    ackWaitMs,
    }, nil
}
```

In `warmRelayConnection` — wrap with timing and emit event on completion.
In `RendezvousRegister`/`RendezvousDiscover` — wrap with timing and emit event.

~50 lines across 4 functions.

---

## 5. Add Correlation ID to 1:1 Messages

**What:** Thread an application-visible `messageId` through the Go transport layer for 1:1 messages, so sender and receiver events can be correlated.

**Why:** Group messages already thread `messageId` through `PublishGroupMessage` → `group_message:received`. 1:1 messages have no such correlation — the UUID is inside the encrypted blob, invisible to Go.

**Files to change:**
- `go-mknoon/node/node.go` — `SendMessageWithTransport` (accept + return messageId), `handleIncomingMessage` (parse + include in event)
- `lib/features/conversation/application/send_chat_message_use_case.dart` — pass messageId to bridge call

**Test files:**
- `go-mknoon/node/node_test.go` — new test
- `test/features/conversation/application/send_chat_message_use_case_test.dart` — new test

### Tests (write first)

**Go Test 1: SendMessageWithTransport accepts and returns correlationId**
```
Setup:   Two connected test nodes.
Act:     Send message with correlationId="test-uuid-123".
Assert:  SendMessageResult.CorrelationId == "test-uuid-123".
```

**Go Test 2: Receiver's message:received event includes correlationId**
```
Setup:   Two connected test nodes, receiver has event collector.
Act:     Send message with correlationId="test-uuid-123".
Assert:  waitForCollectedEvent "message:received" has data.correlationId == "test-uuid-123".
```

**Go Test 3: Missing correlationId defaults to empty (backward compat)**
```
Setup:   Send message without correlationId field.
Assert:  No panic. correlationId absent or empty in event.
```

**Dart Test 1: CHAT_MSG_SEND_TIMING includes correlationId in details**
```
Setup:   FakeP2PService, send message with known messageId.
Act:     Call sendChatMessage(messageId: 'abc-123').
Assert:  'CHAT_MSG_SEND_TIMING' details include 'correlationId': 'abc-123'.
```

### Implementation

**Go side:**
1. Extend the wire frame with an optional header: `{"correlationId":"...", "payload":"..."}`. Or simpler: accept `correlationId` as a bridge parameter and embed it in the stream frame alongside message bytes.
2. In `handleIncomingMessage`: after `readFrame`, if frame is JSON-wrapped with `correlationId`, extract and include in `msgData`.
3. Backward-compatible: if no `correlationId` in frame, field is simply absent.

**Dart side:**
1. In `send_chat_message_use_case.dart`: pass `messageId` as `correlationId` to the bridge `peer:send` command payload.
2. Include `correlationId` in `CHAT_MSG_SEND_TIMING` details.

~30 lines total.

---

## 6. Add Event Queue Wait Timing to Go EventDispatcher

**What:** Measure the delay between `Emit()` and actual callback delivery in `EventDispatcher`.

**Why:** Current timestamps are captured at `Emit()` time (event_dispatcher.go:97). The gap to callback delivery is unmeasured — could be <1ms or hundreds of ms under load.

**File to change:** `go-mknoon/node/event_dispatcher.go`
**Test file:** `go-mknoon/node/node_test.go` (alongside existing dispatcher tests at line 1483)

### Tests (write first)

**Test 1: Delivered events include queueWaitMs field**
```
Setup:   EventDispatcher with recording callback.
Act:     Emit a lossless event (e.g., "message:received").
Assert:  Delivered JSON includes "queueWaitMs" field with int >= 0.
```

**Test 2: queueWaitMs is small (<50ms) under idle conditions**
```
Setup:   EventDispatcher with recording callback, no load.
Act:     Emit 10 events sequentially.
Assert:  All delivered events have queueWaitMs < 50.
```

**Test 3: queueWaitMs increases under slow callback**
```
Setup:   EventDispatcher with slowEventCallback (100ms delay).
Act:     Emit 20 events rapidly.
Assert:  Later events have queueWaitMs > earlier events.
         (Queue builds up because callback is slow.)
```

**Test 4: Coalesced status events report queueWaitMs of latest emission**
```
Setup:   EventDispatcher with slow callback.
Act:     Emit 5 status events of same type rapidly (they coalesce).
Assert:  Delivered event has queueWaitMs measured from LAST Emit, not first.
```

### Implementation

In `event_dispatcher.go`:

1. Add `emittedAt time.Time` field to the `queuedEvent` struct (alongside existing `timestamp`).
2. In `Emit()` (line 97): set `emittedAt: time.Now()` on the queued item.
3. In `deliver()` (line 255): compute `queueWaitMs := time.Since(item.emittedAt).Milliseconds()` and include in the JSON payload.
4. For coalesced events: update `emittedAt` to the latest `Emit()` call's time when replacing in `statusLatest`.

~20 lines: struct field + 3 timestamp sites + JSON inclusion.

---

## 7. Add Connection Reuse Counters to 1:1 Send Path

**What:** Emit `CHAT_MSG_SEND_PATH` event with the transport path taken (reuse, direct, relay, inbox) and whether connection was reused.

**Why:** `isAlreadyConnected` already emits `CHAT_MSG_SEND_REUSE_CONNECTION` on reuse, but: (a) no event on cold start, (b) no aggregate counter, (c) can't compute reuse hit rate from current events.

**File to change:** `lib/features/conversation/application/send_chat_message_use_case.dart`
**Test file:** `test/features/conversation/application/send_chat_message_use_case_test.dart`

### Tests (write first)

**Test 1: Timing details include connectionReused=true when reused**
```
Setup:   FakeP2PService with targetPeerId in connections list.
Act:     Call sendChatMessage().
Assert:  'CHAT_MSG_SEND_TIMING' details include:
         - 'connectionReused': true
         - 'sendPath': 'reuse'
```

**Test 2: Timing details include connectionReused=false on cold start**
```
Setup:   FakeP2PService with empty connections list.
Act:     Call sendChatMessage().
Assert:  'CHAT_MSG_SEND_TIMING' details include:
         - 'connectionReused': false
         - 'sendPath': 'direct' or 'relay' or 'inbox' (depending on outcome)
```

**Test 3: sendPath reflects relay probe path**
```
Setup:   FakeP2PService where direct fails, relay probe succeeds.
Act:     Call sendChatMessage().
Assert:  'CHAT_MSG_SEND_TIMING' with details.sendPath == 'relay'.
```

**Test 4: sendPath reflects inbox fallback**
```
Setup:   FakeP2PService where direct and relay fail, inbox succeeds.
Act:     Call sendChatMessage().
Assert:  'CHAT_MSG_SEND_TIMING' with details.sendPath == 'inbox'.
```

### Implementation

In `send_chat_message_use_case.dart`:

1. After `isAlreadyConnected` check (line 247): set `var connectionReused = isAlreadyConnected;`
2. Track `sendPath` through the function: set to `'reuse'`, `'direct'`, `'local'`, `'relay'`, or `'inbox'` depending on which branch succeeds.
3. Include both fields in the existing `emitSendTiming` details spread at each success/failure call site.

The existing `CHAT_MSG_SEND_TIMING` already includes `'via': message.transport` on success (line 901). The new `connectionReused` and `sendPath` fields supplement this — `via` is the Go-side transport classification, `sendPath` is the Dart-side strategy that won the race.

~15 lines: 2 variables + inclusion at existing emit sites.

---

## 8. Split `VOICE_SEND_TIMING` into Upload/Send Sub-Steps

**What:** Add `uploadMs` and `sendMs` fields to the existing `VOICE_SEND_TIMING` event.

**Why:** `send_voice_message_use_case.dart` already has a Stopwatch covering the total flow. Can't tell if upload or send dominates.

**File to change:** `lib/features/conversation/application/send_voice_message_use_case.dart`
**Test file:** `test/features/conversation/application/send_voice_message_use_case_test.dart`

### Tests (write first)

**Test 1: Timing event includes uploadMs on success**
```
Setup:   FakeBridge with instant media:upload success, FakeP2PService succeeds.
Act:     Call sendVoiceMessage().
Assert:  'VOICE_SEND_TIMING' details include:
         - details.uploadMs is int >= 0
         - details.sendMs is int >= 0
         - details.elapsedMs >= details.uploadMs + details.sendMs
```

**Test 2: uploadMs reflects actual upload duration**
```
Setup:   FakeBridge where media:upload takes 200ms (via Future.delayed).
Act:     Call sendVoiceMessage().
Assert:  'VOICE_SEND_TIMING' with details.uploadMs >= 200.
```

**Test 3: On upload failure, uploadMs is present but sendMs is absent**
```
Setup:   FakeBridge where media:upload returns null.
Act:     Call sendVoiceMessage().
Assert:  'VOICE_SEND_TIMING' with:
         - details.outcome == 'upload_failed'
         - details.uploadMs is int >= 0
         - details.sendMs is null (key absent)
```

**Test 4: On send failure, both uploadMs and sendMs are present**
```
Setup:   FakeBridge upload succeeds, FakeP2PService send fails.
Act:     Call sendVoiceMessage().
Assert:  'VOICE_SEND_TIMING' with:
         - details.uploadMs is int >= 0
         - details.sendMs is int >= 0
```

### Implementation

In `send_voice_message_use_case.dart`:

1. Add `uploadStopwatch` at line 96 (before `VOICE_UPLOAD_START`), stop at line 115 (after `VOICE_UPLOAD_DONE`). Record `uploadMs`.
2. Add `sendStopwatch` at line 117 (before `sendChatMessage` call), stop after it returns. Record `sendMs`.
3. Pass both to the existing `emitVoiceTiming` helper via the `details` spread.

```dart
// Before upload:
final uploadStopwatch = Stopwatch()..start();

// After upload:
uploadStopwatch.stop();
final uploadMs = uploadStopwatch.elapsedMilliseconds;

// Before send:
final sendStopwatch = Stopwatch()..start();

// After send:
sendStopwatch.stop();
final sendMs = sendStopwatch.elapsedMilliseconds;

emitVoiceTiming(outcome: 'success', details: {
  'uploadMs': uploadMs,
  'sendMs': sendMs,
});
```

~20 lines: 2 stopwatches + inclusion in existing helper calls.

---

## 9. Add Deferred Direct ACK Timing Events

**What:** Measure three timing segments in the deferred ACK path:
1. **Receiver:** time from `message:received` emit to Dart's `confirmDirectAck` call.
2. **Receiver:** time from `confirmDirectAck` to ACK written on stream.
3. **Sender:** total round-trip from send to ACK received.

**Why:** The `DirectConfirmTimeout = 2s` budget exists but actual confirm latency is unmeasured. If confirms routinely take 1.8s, the margin is dangerously thin.

**Files to change:**
- `go-mknoon/node/node.go` — emit timing in `handleIncomingMessage` deferred ACK path
- `lib/features/conversation/application/send_chat_message_use_case.dart` — include ACK round-trip in timing details

**Test files:**
- `go-mknoon/node/node_test.go`
- `test/features/conversation/application/send_chat_message_use_case_test.dart`

### Tests (write first)

**Go Test 1: Deferred ACK path emits confirm timing event**
```
Setup:   Two connected nodes, receiver has deferred ACK enabled.
Act:     Send message, Dart-side resolves confirm after 100ms.
Assert:  waitForCollectedEvent "message:direct_ack_timing" with:
         - data.waitMs >= 100   (time waiting for Dart confirm)
         - data.ackWriteMs >= 0 (time to write ACK frame)
         - data.outcome == "confirmed"
```

**Go Test 2: Deferred ACK timeout emits timing with outcome=timeout**
```
Setup:   Two connected nodes, Dart-side never resolves confirm.
Act:     Send message, wait for DirectConfirmTimeout to fire.
Assert:  waitForCollectedEvent "message:direct_ack_timing" with:
         - data.waitMs >= 2000  (full DirectConfirmTimeout)
         - data.outcome == "timeout"
```

**Dart Test 1: Timing includes ackRoundTripMs when deferred ACK succeeds**
```
Setup:   FakeP2PService where send succeeds with deferred ACK.
Act:     Call sendChatMessage().
Assert:  'CHAT_MSG_SEND_TIMING' details include ackRoundTripMs >= 0.
```

### Implementation

**Go side** — in `handleIncomingMessage` deferred ACK branch (node.go:1265):

```go
// After emitting message:received:
waitStart := time.Now()
confirmed := n.waitForRegisteredDirectConfirm(nonce, confirmCh, timeout)
waitMs := time.Since(waitStart).Milliseconds()

if confirmed {
    ackStart := time.Now()
    writeFrame(s, ack)
    ackWriteMs := time.Since(ackStart).Milliseconds()
    n.emitEvent("message:direct_ack_timing", map[string]interface{}{
        "waitMs": waitMs, "ackWriteMs": ackWriteMs, "outcome": "confirmed",
    })
} else {
    n.emitEvent("message:direct_ack_timing", map[string]interface{}{
        "waitMs": waitMs, "outcome": "timeout",
    })
}
```

**Dart side** — the `sendMessageWithReply` already measures the full round-trip as part of the outer budget. The existing `CHAT_MSG_SEND_TIMING` `elapsedMs` implicitly includes ACK wait. No Dart-side change needed unless we want the ACK wait broken out separately (which requires Go to return it in the reply). Defer to a second pass.

~20 lines Go.

---

## 10. Per-Step Breakdown in 1:1 Send

**What:** Add `discoverMs`, `dialMs`, `sendMs`, `relayProbeMs`, `inboxMs` fields to the existing `CHAT_MSG_SEND_TIMING` event.

**Why:** `CHAT_MSG_SEND_TIMING` reports total `elapsedMs` but can't distinguish whether discover, dial, send, relay probe, or inbox fallback was the bottleneck. This is the #1 blind spot listed in `03-timing-and-performance.md`.

**File to change:** `lib/features/conversation/application/send_chat_message_use_case.dart`
**Test file:** `test/features/conversation/application/send_chat_message_use_case_test.dart`

### Tests (write first)

**Test 1: Timing includes discoverMs, dialMs, sendMs on direct success**
```
Setup:   FakeP2PService where discover succeeds (returns peer),
         dial succeeds, sendMessageWithReply succeeds. Not already connected.
Act:     Call sendChatMessage().
Assert:  'CHAT_MSG_SEND_TIMING' details include:
         - details.discoverMs is int >= 0
         - details.dialMs is int >= 0
         - details.sendMs is int >= 0
         - details.sendPath == 'direct'
```

**Test 2: discoverMs reflects actual discover duration**
```
Setup:   FakeP2PService where discoverPeer takes 100ms (via Future.delayed).
Act:     Call sendChatMessage().
Assert:  'CHAT_MSG_SEND_TIMING' with details.discoverMs >= 100.
```

**Test 3: Relay probe path includes relayProbeMs**
```
Setup:   FakeP2PService where direct fails (discover returns null),
         probeRelay returns connected, send succeeds.
Act:     Call sendChatMessage().
Assert:  'CHAT_MSG_SEND_TIMING' with:
         - details.relayProbeMs is int >= 0
         - details.sendPath == 'relay'
```

**Test 4: Inbox fallback includes inboxMs**
```
Setup:   FakeP2PService where direct fails, relay probe fails,
         storeInInbox succeeds.
Act:     Call sendChatMessage().
Assert:  'CHAT_MSG_SEND_TIMING' with:
         - details.inboxMs is int >= 0
         - details.sendPath == 'inbox'
```

**Test 5: Connection reuse path has no sub-step fields**
```
Setup:   FakeP2PService with target in connections list, send succeeds.
Act:     Call sendChatMessage().
Assert:  'CHAT_MSG_SEND_TIMING' with:
         - details.sendPath == 'reuse'
         - details.discoverMs is null (absent)
```

**Test 6: Local WiFi path includes localSendMs**
```
Setup:   FakeP2PService with local peer, sendLocalMessage succeeds.
Act:     Call sendChatMessage().
Assert:  'CHAT_MSG_SEND_TIMING' with:
         - details.localSendMs is int >= 0
         - details.sendPath == 'local'
```

### Implementation

Track sub-step timing through the send function using a mutable map that accumulates as each step completes.

1. **In `_tryDirectSend` (line 668):** Add Stopwatches around discover (line 676), dial (line 682), send (line 692). Return sub-step durations alongside the `_RaceResult`.

2. **In `_tryLocalSend` (line 648):** Stopwatch around `sendLocalMessage`. Return `localSendMs`.

3. **In `_tryRelayProbeSend` (line 707):** Stopwatch around `probeRelay` (line 721) and the send attempts. Return `relayProbeMs`.

4. **At inbox fallback (line 442):** Stopwatch around `storeInInbox`. Record `inboxMs`.

5. **Pass all sub-step fields** into the existing `emitSendTiming` details at each call site.

Approach: Extend `_RaceResult` with an optional `Map<String, int> stepTimings` field. Each `_try*` method populates its step timings. The winner's timings flow into the final `CHAT_MSG_SEND_TIMING` event.

~40 lines: Stopwatches in 3 methods + `_RaceResult` field + inclusion at emit sites.

---

## 11. Circuit Address Appearance Delay

**What:** Emit `circuit_address:timing` event measuring the gap between relay connection and first circuit address appearance.

**Why:** `waitForCircuitAddress` (node.go:1298) polls every 200ms for up to 10s, but the actual delay is unmeasured. This is the gap between `relayReady` closing (TCP connected) and AutoRelay processing the reservation into a circuit address.

**File to change:** `go-mknoon/node/node.go`
**Test file:** `go-mknoon/node/node_test.go`

### Tests (write first)

**Test 1: waitForCircuitAddress emits timing on success**
```
Setup:   Test node with relay configured, relay connects.
Act:     Start node (triggers waitForCircuitAddress internally).
Assert:  waitForCollectedEvent "circuit_address:timing" with:
         - data.elapsedMs >= 0
         - data.outcome == "found"
         - data.pollCount >= 1
```

**Test 2: waitForCircuitAddress emits timing on timeout**
```
Setup:   Test node with broken relay (never produces circuit address).
         Use waitForCircuitAddressHook to control behavior.
Act:     Call waitForCircuitAddress(1 * time.Second).
Assert:  waitForCollectedEvent "circuit_address:timing" with:
         - data.elapsedMs >= 1000
         - data.outcome == "timeout"
```

**Test 3: sinceRelayReadyMs is included when relay was ready**
```
Setup:   Test node where relay connects, then circuit address appears.
Act:     Start node.
Assert:  "circuit_address:timing" event includes:
         - data.sinceRelayReadyMs >= 0
         (measuring gap from relayReady close to circuit address)
```

### Implementation

In `waitForCircuitAddress` (node.go:1298):

```go
func (n *Node) waitForCircuitAddress(timeout time.Duration) bool {
    start := time.Now()
    pollCount := 0
    // ... existing poll loop ...
    for time.Now().Before(deadline) {
        pollCount++
        // ... existing address check ...
        if found {
            n.emitEvent("circuit_address:timing", map[string]interface{}{
                "elapsedMs": time.Since(start).Milliseconds(),
                "outcome":   "found",
                "pollCount": pollCount,
            })
            return true
        }
        time.Sleep(200 * time.Millisecond)
    }
    n.emitEvent("circuit_address:timing", map[string]interface{}{
        "elapsedMs": time.Since(start).Milliseconds(),
        "outcome":   "timeout",
        "pollCount": pollCount,
    })
    return false
}
```

~15 lines Go: start timestamp, poll counter, two emit sites.

---

## 12. Inbox Store/Retrieve Round-Trip Timing

**What:** Emit `inbox:store_timing` and `inbox:retrieve_timing` events with per-step sub-timings: `connectMs`, `streamOpenMs`, `writeMs`, `readMs`, `totalMs`.

**Why:** Inbox store is the final fallback in the 1:1 send path (Path A) and group offline delivery. The 15s `InboxTimeout` budget is opaque — can't tell if time is spent connecting, opening streams, or waiting for the relay response.

**File to change:** `go-mknoon/node/inbox.go`
**Test file:** `go-mknoon/node/node_test.go` (new test using existing multi-node harness)

### Tests (write first)

**Test 1: InboxStore emits timing event on success**
```
Setup:   Two test nodes connected via relay, receiver has inbox handler.
Act:     nodeA.InboxStore(nodeB.PeerId(), "test message").
Assert:  waitForCollectedEvent "inbox:store_timing" with:
         - data.connectMs >= 0
         - data.streamOpenMs >= 0
         - data.writeMs >= 0
         - data.readMs >= 0
         - data.totalMs >= 0
         - data.outcome == "success"
```

**Test 2: InboxStore timing on connection failure**
```
Setup:   Test node with unreachable relay (dial will fail).
Act:     InboxStore to unknown peer.
Assert:  "inbox:store_timing" with:
         - data.outcome == "connect_failed"
         - data.connectMs >= 0
         - data.totalMs >= data.connectMs
```

**Test 3: InboxRetrieve emits timing event**
```
Setup:   Relay with stored messages for test node.
Act:     nodeA.InboxRetrieve().
Assert:  waitForCollectedEvent "inbox:retrieve_timing" with:
         - data.totalMs >= 0
         - data.outcome == "success"
         - data.messageCount >= 0
```

### Implementation

In `InboxStore` (inbox.go:43), wrap each step with `time.Now()`:

```go
return rs.ForEach(func(relay RelayInfo) error {
    total := time.Now()

    connectStart := time.Now()
    err := h.Connect(ctx, ...)
    connectMs := time.Since(connectStart).Milliseconds()
    if err != nil {
        n.emitEvent("inbox:store_timing", map[string]interface{}{
            "connectMs": connectMs, "totalMs": time.Since(total).Milliseconds(),
            "outcome": "connect_failed",
        })
        return err
    }

    streamStart := time.Now()
    s, err := h.NewStream(ctx, ...)
    streamOpenMs := time.Since(streamStart).Milliseconds()
    // ... similar for write and read ...

    n.emitEvent("inbox:store_timing", map[string]interface{}{
        "connectMs": connectMs, "streamOpenMs": streamOpenMs,
        "writeMs": writeMs, "readMs": readMs,
        "totalMs": time.Since(total).Milliseconds(),
        "outcome": "success",
    })
    return nil
})
```

Same pattern for `InboxRetrieve`. Add `messageCount` to retrieve event.

~40 lines Go: timing in InboxStore + InboxRetrieve.

---

## 13. GossipSub Publish-to-Receive Latency

**What:** Measure cross-node delivery latency by embedding a publish timestamp in the group message and computing delta on receive.

**Why:** `topic.Publish` returning nil does NOT mean delivery. Actual publish-to-receive time is completely unmeasured — could be 50ms or 5s depending on mesh state.

**Files to change:**
- `go-mknoon/node/pubsub.go` — embed `publishedAtNano` in message extra, compute delta on receive
**Test file:** `go-mknoon/node/pubsub_delivery_test.go` (existing multi-node test infrastructure)

### Tests (write first)

**Test 1: Received group message event includes deliveryMs**
```
Setup:   Two connected test nodes (nodeA, nodeB) joined to same group topic.
         Wait for mesh formation (500ms).
Act:     nodeA.PublishGroupMessage(groupId, text, messageId).
Assert:  waitForCollectedEvent on nodeB "group_message:received" with:
         - data.deliveryMs >= 0
         - data.deliveryMs < 5000  (sanity: should be <5s on local test)
         - data.messageId == published messageId
```

**Test 2: deliveryMs is absent for messages from older publishers (backward compat)**
```
Setup:   Manually construct group envelope WITHOUT publishedAtNano field.
         Inject into nodeB's subscription.
Assert:  "group_message:received" event does NOT contain deliveryMs field.
         (No crash, no error.)
```

**Test 3: Self-published messages are excluded from deliveryMs**
```
Setup:   Single node, publishes to its own topic.
Assert:  Messages from self are already filtered (existing behavior at pubsub.go:491).
         No deliveryMs field emitted for self-messages.
```

### Implementation

**Publish side** — in `PublishGroupMessage` (pubsub.go:166), embed publish timestamp in the payload Extra map:

```go
payload.Extra["publishedAtNano"] = strconv.FormatInt(time.Now().UnixNano(), 10)
```

This goes inside the encrypted envelope, so it's only visible after decryption.

**Receive side** — in `handleGroupSubscription` (pubsub.go:521), after decryption, extract and compute delta:

```go
if pubNanoStr, ok := payload.Extra["publishedAtNano"].(string); ok {
    if pubNano, err := strconv.ParseInt(pubNanoStr, 10, 64); err == nil {
        deliveryMs := (time.Now().UnixNano() - pubNano) / 1e6
        event["deliveryMs"] = deliveryMs
    }
}
```

**Clock skew caveat:** On simulators (same machine), clocks are synchronized. On real devices across networks, this measurement includes clock skew. Document this limitation in the event. Sufficient for simulator benchmarks (03b Section 2).

~15 lines Go: 1 line publish, ~10 lines receive parsing + event field.

---

## 14. MethodChannel Bridge Crossing Time

**What:** Add `bridgeMs` field to timing events for operations that cross the Dart↔Go bridge, measuring the `_methodChannel.invokeMethod` round-trip.

**Why:** Every bridge call (encrypt, decrypt, send, discover, dial, inbox, media) crosses the MethodChannel. The serialization + channel + deserialization overhead is a complete blind spot.

**File to change:** `lib/core/bridge/go_bridge_client.dart`
**Test file:** `test/core/bridge/go_bridge_client_test.dart` (new file, or add to existing)

### Tests (write first)

**Test 1: Bridge send() captures round-trip timing**
```
Setup:   GoBridgeClient with mock MethodChannel that responds in 50ms.
Act:     Call bridge.send('{"cmd":"node:status"}').
Assert:  captureFlowEvents contains event with:
         - event == 'BRIDGE_CALL_TIMING'
         - details.cmd == 'node:status'
         - details.bridgeMs >= 50
```

**Test 2: Bridge timing emitted on failure**
```
Setup:   Mock MethodChannel that throws PlatformException after 10ms.
Act:     Call bridge.send('{"cmd":"node:status"}') — expect exception.
Assert:  'BRIDGE_CALL_TIMING' with:
         - details.outcome == 'error'
         - details.bridgeMs >= 10
```

**Test 3: Bridge timing is emitted for every command type**
```
Setup:   Mock MethodChannel, call multiple commands.
Act:     Call send() with 'node:status', 'message.encrypt', 'peer:dial'.
Assert:  3 separate 'BRIDGE_CALL_TIMING' events, each with correct cmd.
```

**Test 4: High-frequency calls don't cause timing overhead >5ms per call**
```
Setup:   Mock MethodChannel with instant response.
Act:     Call bridge.send() 100 times, measure wall-clock total.
Assert:  Average per-call overhead (total / 100 - mock latency) < 5ms.
         (Verifies Stopwatch + emitFlowEvent doesn't add meaningful cost.)
```

### Implementation

In `go_bridge_client.dart`, wrap the `invokeMethod` call in `send()` (line 396):

```dart
@override
Future<String> send(String message) async {
  final request = jsonDecode(message) as Map<String, dynamic>;
  final cmd = request['cmd'] as String;
  // ... existing validation ...

  final bridgeStopwatch = Stopwatch()..start();
  try {
    final result = await _methodChannel.invokeMethod<String>(...);
    bridgeStopwatch.stop();
    emitFlowEvent(
      layer: 'FL',
      event: 'BRIDGE_CALL_TIMING',
      details: {
        'cmd': cmd,
        'bridgeMs': bridgeStopwatch.elapsedMilliseconds,
        'outcome': 'success',
      },
    );
    return result ?? ...;
  } catch (e) {
    bridgeStopwatch.stop();
    emitFlowEvent(
      layer: 'FL',
      event: 'BRIDGE_CALL_TIMING',
      details: {
        'cmd': cmd,
        'bridgeMs': bridgeStopwatch.elapsedMilliseconds,
        'outcome': 'error',
      },
    );
    rethrow;
  }
}
```

**Note:** This emits a flow event for EVERY bridge call. In production (`kDebugMode = false`), `emitFlowEvent` is a no-op — the Stopwatch still runs but costs <1μs. If even that overhead is unwanted, gate the Stopwatch behind `flowEventLoggingEnabled`.

~20 lines Dart.

---

## 15. Encryption/Decryption Time

**What:** Add `encryptMs` / `decryptMs` fields to timing events for operations that use ML-KEM or group encryption.

**Why:** ML-KEM-768 keygen, encapsulation, AES-256-GCM encryption/decryption happen Go-side. Overhead per message is unknown — could be 1ms or 100ms.

**Files to change:**
- `lib/features/conversation/application/send_chat_message_use_case.dart` — measure `callEncryptMessage` duration
- `lib/features/conversation/application/chat_message_listener.dart` — measure `callDecryptMessage` duration (receive path)
- `lib/features/groups/application/send_group_message_use_case.dart` — measure `callGroupEncrypt` duration

**Test files:**
- `test/features/conversation/application/send_chat_message_use_case_test.dart`
- `test/features/groups/application/send_group_message_use_case_test.dart`

### Tests (write first)

**Test 1: 1:1 send timing includes encryptMs when ML-KEM key present**
```
Setup:   FakeBridge with encrypt response, recipientMlKemPublicKey provided.
Act:     Call sendChatMessage().
Assert:  'CHAT_MSG_SEND_TIMING' with details.encryptMs >= 0.
```

**Test 2: encryptMs absent when no ML-KEM key (v1 plaintext)**
```
Setup:   No recipientMlKemPublicKey.
Act:     Call sendChatMessage().
Assert:  'CHAT_MSG_SEND_TIMING' with details.encryptMs is null (absent).
```

**Test 3: encryptMs reflects actual bridge call duration**
```
Setup:   FakeBridge where message.encrypt takes 50ms (Future.delayed).
Act:     Call sendChatMessage().
Assert:  'CHAT_MSG_SEND_TIMING' with details.encryptMs >= 50.
```

**Test 4: Group send timing includes groupEncryptMs**
```
Setup:   FakeBridge with group:publish success (which internally encrypts).
Act:     Call sendGroupMessage().
Assert:  'GROUP_SEND_MSG_TIMING' with details.groupEncryptMs >= 0.
```

### Implementation

**1:1 send** — in `send_chat_message_use_case.dart`, wrap `callEncryptMessage` (around line 174):

```dart
final encryptStopwatch = Stopwatch()..start();
final encrypted = await callEncryptMessage(bridge, ...);
encryptStopwatch.stop();
final encryptMs = encryptStopwatch.elapsedMilliseconds;
```

Pass `encryptMs` into `emitSendTiming` details. Only record when encryption actually happens (ML-KEM key present).

**Group send** — in `send_group_message_use_case.dart`, the encryption happens inside `callGroupPublish` (Go-side). To measure it, either:
- (a) Wrap the entire `callGroupPublish` and label its timing as `publishMs` (already done in §3), OR
- (b) Add a separate `callGroupEncrypt` + `callGroupPublish` split. Since the current code calls `callGroupPublish` which does encrypt+publish atomically in Go, option (a) is simpler. The `publishMs` from §3 includes encryption.

For explicit crypto measurement, the Go side could return `encryptMs` in the publish response — see §16 below.

~15 lines Dart for 1:1 path.

---

## 16. Group Encrypt/Decrypt Timing (Go-side)

**What:** Add `encryptMs`, `signMs` fields to the `group:publish_debug` event, and `decryptMs`, `verifyMs` fields to `group_message:received`.

**Why:** Group v3 envelope processing involves AES-256-GCM encryption + Ed25519 signing on publish, and decryption + signature verification on receive. These happen Go-side inside `PublishGroupMessage` (pubsub.go:181-191) and `handleGroupSubscription` (pubsub.go:521). §3 adds `publishMs` from Dart which includes the full bridge call, but can't distinguish crypto cost from network cost. This measures the Go-side crypto operations directly.

**File to change:** `go-mknoon/node/pubsub.go`
**Test file:** `go-mknoon/node/pubsub_test.go`

### Tests (write first)

**Test 1: PublishGroupMessage event includes encryptMs and signMs**
```
Setup:   Test node with group topic joined, valid key material.
Act:     Call PublishGroupMessage().
Assert:  waitForCollectedEvent "group:publish_debug" with:
         - data.encryptMs >= 0
         - data.signMs >= 0
         - data.messageId is String
```

**Test 2: Received group message event includes decryptMs**
```
Setup:   Two connected test nodes joined to same group.
Act:     nodeA publishes group message.
Assert:  waitForCollectedEvent on nodeB "group_message:received" with:
         - data.decryptMs >= 0
```

**Test 3: Decryption failure event includes decryptMs**
```
Setup:   Two nodes, receiver has wrong group key (key mismatch).
Act:     nodeA publishes group message.
Assert:  waitForCollectedEvent on nodeB "group:decryption_failed" with:
         - data.decryptMs >= 0
         (Measures time spent before failure, not just that it failed.)
```

**Test 4: encryptMs and signMs are reasonable (<100ms on simulator)**
```
Setup:   Test node, publish 10 messages.
Act:     Collect all "group:publish_debug" events.
Assert:  All encryptMs < 100 and signMs < 100.
         (Sanity bound — AES-256-GCM + Ed25519 should be <10ms.)
```

### Implementation

**Publish side** — in `PublishGroupMessage` (pubsub.go:180-191):

```go
// 2. Encrypt payload with group key.
encryptStart := time.Now()
ctB64, nonceB64, err := mcrypto.EncryptGroupMessage(keyInfo.Key, payloadJSON)
encryptMs := time.Since(encryptStart).Milliseconds()

// 3. Build signature data and sign.
signStart := time.Now()
sigData := mcrypto.BuildGroupSignatureData(groupId, keyInfo.KeyEpoch, ctB64)
signature, err := mcrypto.SignPayload(privateKeyB64, sigData)
signMs := time.Since(signStart).Milliseconds()
```

Include in existing `group:publish_debug` event (pubsub.go:229):

```go
n.emitEvent("group:publish_debug", map[string]interface{}{
    "groupId":    groupId,
    "messageId":  msgId,
    "topicPeers": peerCount,
    "encryptMs":  encryptMs,
    "signMs":     signMs,
})
```

**Receive side** — in `handleGroupSubscription` (pubsub.go:521):

```go
decryptStart := time.Now()
plaintext, err := decryptGroupEnvelopePayload(env, keyInfo, time.Now())
decryptMs := time.Since(decryptStart).Milliseconds()

if err != nil {
    n.emitEvent("group:decryption_failed", map[string]interface{}{
        // ... existing fields ...
        "decryptMs": decryptMs,
    })
    continue
}
```

Include `decryptMs` in `buildGroupMessageReceivedEvent` return map.

~20 lines Go: 4 timestamps + inclusion in 3 existing events.

---

## 17. Sequential Relay Failover Timing

**What:** Emit `relay_selector:attempt_timing` event for each relay attempt in `ForEach`/`ForEachWithResult`, measuring per-relay latency and total failover cost.

**Why:** Rendezvous register/discover iterates relays sequentially via `RelaySelector.ForEach` (relay_selector.go:88). Each dead relay adds a full `DiscoverTimeout = 10s` before the next is tried. With 2 relays and the first down, the user waits 10s before the second is even attempted. This latency multiplier is currently invisible — no event, no metric, no count of relays tried.

**File to change:** `go-mknoon/node/relay_selector.go`
**Test file:** `go-mknoon/node/multi_relay_test.go` (existing test infrastructure)

### Tests (write first)

**Test 1: ForEach emits per-attempt timing for each relay tried**
```
Setup:   RelaySelector with 2 relays. First relay fails, second succeeds.
         Wrap fn to emit timing (or test via Node-level event).
Act:     Call ForEach with a function that fails on relay 1, succeeds on relay 2.
Assert:  Two "relay_selector:attempt_timing" events emitted:
         - Event 1: relayIndex=0, outcome="failed", elapsedMs >= 0
         - Event 2: relayIndex=1, outcome="success", elapsedMs >= 0
```

**Test 2: Total failover timing is sum of per-relay attempts**
```
Setup:   RelaySelector with 3 relays. First two fail (each takes ~100ms), third succeeds.
Act:     Call ForEach.
Assert:  "relay_selector:failover_timing" summary event with:
         - totalMs >= 200
         - relaysAttempted == 3
         - relaysFailed == 2
         - outcome == "success"
```

**Test 3: All relays fail — timing captures total cost**
```
Setup:   RelaySelector with 2 relays, both fail.
Act:     Call ForEach.
Assert:  "relay_selector:failover_timing" with:
         - relaysAttempted == 2
         - relaysFailed == 2
         - outcome == "all_failed"
```

**Test 4: Single relay success — no failover overhead**
```
Setup:   RelaySelector with 1 relay, succeeds immediately.
Act:     Call ForEach.
Assert:  "relay_selector:failover_timing" with:
         - relaysAttempted == 1
         - relaysFailed == 0
         - outcome == "success"
         - totalMs < 1000  (no dead relay penalty)
```

### Implementation

The challenge: `RelaySelector.ForEach` is a generic utility (relay_selector.go:88) that doesn't have access to the Node's `emitEvent`. Two approaches:

**Approach A (preferred): Instrument at call sites.** Wrap the `fn` callback passed to `ForEach` with timing at each call site (rendezvous.go:30, rendezvous.go:117, rendezvous.go:176, inbox.go ForEach calls). This keeps `RelaySelector` generic.

```go
// In RendezvousRegister (rendezvous.go:30):
totalStart := time.Now()
relaysAttempted := 0
relaysFailed := 0

err := rs.ForEach(func(relay RelayInfo) error {
    relaysAttempted++
    attemptStart := time.Now()
    
    // ... existing register logic ...
    err := existingLogic(relay)
    
    attemptMs := time.Since(attemptStart).Milliseconds()
    if err != nil {
        relaysFailed++
        n.emitEvent("relay_selector:attempt_timing", map[string]interface{}{
            "operation":  "register",
            "relayIndex": relaysAttempted - 1,
            "elapsedMs":  attemptMs,
            "outcome":    "failed",
        })
        return err
    }
    n.emitEvent("relay_selector:attempt_timing", map[string]interface{}{
        "operation":  "register",
        "relayIndex": relaysAttempted - 1,
        "elapsedMs":  attemptMs,
        "outcome":    "success",
    })
    return nil
})

n.emitEvent("relay_selector:failover_timing", map[string]interface{}{
    "operation":       "register",
    "totalMs":         time.Since(totalStart).Milliseconds(),
    "relaysAttempted": relaysAttempted,
    "relaysFailed":    relaysFailed,
    "outcome":         outcomeFromErr(err),
})
```

**Approach B: Add emitter to RelaySelector.** Pass an `emitFn` to ForEach. Cleaner but changes the generic interface.

Recommend Approach A — instrument the 3 rendezvous call sites + inbox call sites. Each site adds ~15 lines. Total:

~45 lines Go across 3 rendezvous call sites. Inbox call sites can follow the same pattern in a second pass.

---

## 18. Node Startup Timing Summary

**What:** Emit `node:startup_timing` event with per-phase sub-timings: `libp2pNewMs`, `pubsubInitMs`, `relayWarmMs`, `circuitAddressMs`, `rendezvousRegisterMs`, `totalToDiscoverableMs`.

**Why:** Node startup has 5 distinct phases (host creation, pubsub init, relay warm, circuit address acquisition, rendezvous registration), but no single event captures the full breakdown. `sinceStartMs` on `addresses:updated` only measures the gap from `startedAt` to address appearance — it doesn't tell you which phase was slow. This is the missing instrumentation for 03b Section 2 Test B (Node Startup Timing).

**Files to change:**
- `go-mknoon/node/node.go` — `Start()` method (lines 192–385), `autoRegisterPersonalNamespaceForStart()`
- `go-mknoon/node/personal_rendezvous_refresh.go` — auto-register flow

**Test file:** `go-mknoon/node/node_test.go`

### Tests (write first)

**Test 1: Start() emits startup timing with libp2pNewMs and pubsubInitMs**
```
Setup:   Test node with relay configured.
Act:     Call Start().
Assert:  waitForCollectedEvent "node:startup_timing" with:
         - data.libp2pNewMs >= 0
         - data.pubsubInitMs >= 0
         - data.phase == "host_ready"
```

**Test 2: Relay warm phase emits timing**
```
Setup:   Test node with 2 relays.
Act:     Call Start(), wait for relay connections.
Assert:  waitForCollectedEvent "node:startup_timing" with:
         - data.phase == "relay_warm"
         - data.relayWarmMs >= 0
         - data.relaysAttempted >= 1
```

**Test 3: Full startup emits totalToDiscoverableMs**
```
Setup:   Test node with relay, auto-register enabled.
Act:     Call Start(), wait for circuit address + rendezvous registration.
Assert:  waitForCollectedEvent "node:startup_timing" with:
         - data.phase == "discoverable"
         - data.totalToDiscoverableMs >= 0
         - data.circuitAddressMs >= 0
         - data.rendezvousRegisterMs >= 0
         - data.totalToDiscoverableMs >= data.libp2pNewMs
```

**Test 4: Startup with broken relay still emits timing (timeout path)**
```
Setup:   Test node with unreachable relay.
Act:     Call Start(), relay warm fails, circuit address times out.
Assert:  "node:startup_timing" with:
         - data.phase == "discoverable"
         - data.circuitAddressMs >= 10000  (10s timeout)
         - data.circuitAddressOutcome == "timeout"
```

**Test 5: totalToDiscoverableMs on simulator is < 5s (sanity bound)**
```
Setup:   Test node with working relay on same machine.
Act:     Start node, wait for discoverable.
Assert:  data.totalToDiscoverableMs < 5000
```

### Implementation

**Phase 1 — Host creation timing** in `Start()` (node.go:313):

```go
libp2pStart := time.Now()
h, err := libp2p.New(hostOpts...)
libp2pNewMs := time.Since(libp2pStart).Milliseconds()

// ... existing host setup ...

pubsubStart := time.Now()
if err := n.initPubSub(); err != nil { ... }
pubsubInitMs := time.Since(pubsubStart).Milliseconds()
```

Emit after event dispatcher is initialized (line 362):

```go
n.emitEvent("node:startup_timing", map[string]interface{}{
    "phase":        "host_ready",
    "libp2pNewMs":  libp2pNewMs,
    "pubsubInitMs": pubsubInitMs,
})
```

**Phase 2 — Relay warm timing** in the background goroutine (line 367):

```go
go func() {
    warmStart := time.Now()
    relaysAttempted := 0
    for _, info := range relayInfos {
        // ... existing warm logic ...
        relaysAttempted++
    }
    // After first relay ready (or all attempted):
    n.emitEvent("node:startup_timing", map[string]interface{}{
        "phase":           "relay_warm",
        "relayWarmMs":     time.Since(warmStart).Milliseconds(),
        "relaysAttempted": relaysAttempted,
    })
}()
```

**Phase 3 — Discoverable timing** in `autoRegisterPersonalNamespaceForStart()` (personal_rendezvous_refresh.go:13):

```go
func (n *Node) autoRegisterPersonalNamespaceForStart() {
    totalStart := time.Now()

    circuitStart := time.Now()
    ok := n.waitForCircuitAddressForStart(10 * time.Second)
    circuitAddressMs := time.Since(circuitStart).Milliseconds()
    circuitOutcome := "found"
    if !ok { circuitOutcome = "timeout" }

    registerMs := int64(0)
    if ok {
        regStart := time.Now()
        // ... existing register call ...
        registerMs = time.Since(regStart).Milliseconds()
    }

    n.emitEvent("node:startup_timing", map[string]interface{}{
        "phase":                   "discoverable",
        "circuitAddressMs":        circuitAddressMs,
        "circuitAddressOutcome":   circuitOutcome,
        "rendezvousRegisterMs":    registerMs,
        "totalToDiscoverableMs":   time.Since(totalStart).Milliseconds(),
    })
}
```

**Note:** `totalToDiscoverableMs` measures from relay warm start (Phase 2) through circuit address appearance and rendezvous registration. To get wall-clock startup, the benchmark harness adds `libp2pNewMs + pubsubInitMs + totalToDiscoverableMs`.

~30 lines Go: 3 emit sites across Start() and autoRegister.

---

## 19. Relay Recovery Detection & Outage Timing

**What:** Emit `relay:outage_timing` event measuring the full outage window: `detectionMs` (last healthy state → degradation detected), `recoveryMs` (recovery attempt duration), `totalOutageMs` (last successful send → first successful send after recovery).

**Why:** 03d §4 adds a timeout to recovery coalescing, but doesn't measure the detection latency or total outage window. A health check runs every 30s — if the relay dies 1s after a check, detection alone takes 29s. The benchmark harness needs these numbers to measure real outage impact. This is the missing instrumentation for 03b Section 2 Test C.

**Files to change:**
- `lib/core/services/p2p_service_impl.dart` — `_performHealthCheck()` (line 1262), `_handleRelayStateChanged()` (line 1656)

**Test file:** `test/core/services/p2p_service_impl_test.dart`

### Tests (write first)

**Test 1: Detection timing emitted when health check finds degradation**
```
Setup:   FakeBridge where node:status returns healthy, then degraded.
         P2PServiceImpl with healthCheckInterval = 1s (shortened for test).
Act:     Wait for first healthy poll, then switch bridge to return degraded.
Assert:  captureFlowEvents contains 'RELAY_OUTAGE_TIMING' with:
         - details.detectionMs >= 0
         - details.phase == 'detected'
```

**Test 2: Detection timing includes time since last healthy state**
```
Setup:   FakeBridge, first poll healthy at T=0, second poll healthy at T=1s,
         third poll degraded at T=2s.
Act:     Wait for degradation detection.
Assert:  'RELAY_OUTAGE_TIMING' with details.detectionMs approximately 1000
         (time from last healthy poll to degradation detected).
```

**Test 3: Recovery timing emitted after successful relay:reconnect**
```
Setup:   FakeBridge where relay:reconnect succeeds after 500ms.
Act:     Health check detects degradation, triggers reconnect.
Assert:  'RELAY_OUTAGE_TIMING' with:
         - details.phase == 'recovered'
         - details.recoveryMs >= 500
         - details.totalOutageMs >= details.detectionMs + details.recoveryMs
```

**Test 4: Push-based detection emits timing from relay:state event**
```
Setup:   P2PServiceImpl with onRelayStateChanged callback.
Act:     Simulate relay:state push with relayState='recovering'.
Assert:  'RELAY_OUTAGE_TIMING' with:
         - details.phase == 'detected'
         - details.detectionSource == 'push'  (vs 'poll' from health check)
```

**Test 5: totalOutageMs spans detection through successful recovery**
```
Setup:   FakeBridge, healthy → degraded → reconnect succeeds (200ms).
Act:     Full cycle: healthy state, degrade, detect, recover.
Assert:  'RELAY_OUTAGE_TIMING' with:
         - details.phase == 'recovered'
         - details.totalOutageMs >= details.detectionMs + details.recoveryMs
```

### Implementation

In `p2p_service_impl.dart`, add state tracking:

```dart
DateTime? _lastHealthyRelayAt;    // timestamp of last confirmed-healthy poll
DateTime? _outageDetectedAt;      // timestamp when degradation was first noticed
```

**In `_performHealthCheck()` (line 1291):** After confirming healthy relay, record timestamp:

```dart
if (_stateHasHealthyRelay(freshState)) {
  _hasEverBeenOnline = true;
  _lastHealthyRelayAt = DateTime.now();  // NEW
}
```

**At degradation detection (line 1298):** Record detection timestamp and emit:

```dart
if (_stateNeedsRelayRecovery(freshState) && _hasEverBeenOnline) {
  _outageDetectedAt ??= DateTime.now();  // only set on first detection
  final detectionMs = _lastHealthyRelayAt != null
      ? DateTime.now().difference(_lastHealthyRelayAt!).inMilliseconds
      : -1;
  emitFlowEvent(
    layer: 'FL',
    event: 'RELAY_OUTAGE_TIMING',
    details: {
      'phase': 'detected',
      'detectionMs': detectionMs,
      'detectionSource': 'poll',
    },
  );
```

**After successful recovery (line 1324):** Emit recovery + total outage timing:

```dart
if (reconnectResponse['ok'] == true) {
  final totalOutageMs = _outageDetectedAt != null
      ? DateTime.now().difference(_outageDetectedAt!).inMilliseconds
      : reconnectMs;
  emitFlowEvent(
    layer: 'FL',
    event: 'RELAY_OUTAGE_TIMING',
    details: {
      'phase': 'recovered',
      'recoveryMs': reconnectMs,
      'totalOutageMs': totalOutageMs,
      'recoveryMode': reconnectResponse['recoveryMode'],
    },
  );
  _outageDetectedAt = null;  // reset for next outage
```

**In `_handleRelayStateChanged()` (line 1656):** Emit push-based detection:

```dart
if (relayState != 'online' && _hasEverBeenOnline) {
  _outageDetectedAt ??= DateTime.now();
  final detectionMs = _lastHealthyRelayAt != null
      ? DateTime.now().difference(_lastHealthyRelayAt!).inMilliseconds
      : -1;
  emitFlowEvent(
    layer: 'FL',
    event: 'RELAY_OUTAGE_TIMING',
    details: {
      'phase': 'detected',
      'detectionMs': detectionMs,
      'detectionSource': 'push',
    },
  );
}
```

~25 lines Dart: 2 state fields + 3 emit sites.

---

## 20. Inbox End-to-End Delivery Timing

**What:** Emit `INBOX_DELIVERY_TIMING` event on the receiver side measuring the full round-trip: time from message stored in inbox (sender timestamp embedded in envelope) to message delivered to receiver after `InboxRetrieve`.

**Why:** §12 instruments `inbox:store_timing` and `inbox:retrieve_timing` independently (Go-side per-step), but doesn't measure the end-to-end delivery latency as experienced by the user: how long from sender pressing send (→ inbox store) until receiver gets the message (→ inbox retrieve → Dart delivery). This is the missing piece for 03b Section 2 Test D's `end_to_end_delivery_ms`.

**Files to change:**
- `go-mknoon/node/inbox.go` — embed `storedAtNano` timestamp when storing
- `lib/features/conversation/application/chat_message_listener.dart` — compute delivery delta when processing inbox-retrieved messages

**Test files:**
- `go-mknoon/node/node_test.go` — verify `storedAtNano` is embedded
- `test/features/conversation/application/chat_message_listener_test.dart` — verify timing event

### Tests (write first)

**Go Test 1: InboxStore embeds storedAtNano in stored envelope**
```
Setup:   Two test nodes connected via relay, receiver has inbox handler.
Act:     nodeA.InboxStore(nodeB.PeerId(), "test message").
Assert:  Stored message frame includes "storedAtNano" field.
         Value is a valid Unix nanosecond timestamp (within 5s of now).
```

**Go Test 2: InboxRetrieve returns messages with storedAtNano preserved**
```
Setup:   Store a message via InboxStore, then retrieve.
Act:     nodeB.InboxRetrieve().
Assert:  Retrieved message data includes storedAtNano from the store call.
```

**Dart Test 1: Inbox-delivered message emits INBOX_DELIVERY_TIMING**
```
Setup:   FakeP2PService delivering an inbox-retrieved message with
         storedAtNano = 500ms ago.
Act:     ChatMessageListener processes the message.
Assert:  captureFlowEvents contains 'INBOX_DELIVERY_TIMING' with:
         - details.deliveryMs >= 500
         - details.deliveryMs < 5000  (sanity)
         - details.messageId is String
```

**Dart Test 2: Direct message does NOT emit INBOX_DELIVERY_TIMING**
```
Setup:   FakeP2PService delivering a direct (non-inbox) message.
Act:     ChatMessageListener processes the message.
Assert:  No 'INBOX_DELIVERY_TIMING' event emitted.
```

**Dart Test 3: Missing storedAtNano gracefully skips timing**
```
Setup:   FakeP2PService delivering an inbox message WITHOUT storedAtNano
         (backward compat with older senders).
Act:     ChatMessageListener processes the message.
Assert:  No 'INBOX_DELIVERY_TIMING' event emitted. No crash.
```

### Implementation

**Go side** — in `InboxStore` (inbox.go), embed timestamp in the stored message frame:

```go
// Before writing the message to the relay:
storePayload := map[string]interface{}{
    "message":      message,
    "storedAtNano": strconv.FormatInt(time.Now().UnixNano(), 10),
}
```

The inbox protocol stores an opaque blob — the timestamp travels inside it. On retrieve, the blob is returned as-is, preserving `storedAtNano`.

**Dart side** — in `ChatMessageListener`, after decrypting an inbox-delivered message:

```dart
if (incomingMessage.source == 'inbox') {
  final storedAtNanoStr = incomingMessage.metadata?['storedAtNano'];
  if (storedAtNanoStr != null) {
    final storedAtNano = int.tryParse(storedAtNanoStr);
    if (storedAtNano != null) {
      final deliveryMs = (DateTime.now().microsecondsSinceEpoch * 1000 - storedAtNano) ~/ 1000000;
      emitFlowEvent(
        layer: 'FL',
        event: 'INBOX_DELIVERY_TIMING',
        details: {
          'deliveryMs': deliveryMs,
          'messageId': incomingMessage.messageId,
        },
      );
    }
  }
}
```

**Clock skew caveat:** Same as §13 (GossipSub delivery) — on simulators (same machine), clocks are synchronized. On real devices, this includes clock skew. Sufficient for benchmark harness.

~20 lines Go + Dart: timestamp embed on store, delta computation on receive.

---

## 21. Media Stream Open & Throughput Timing

**What:** Emit `media:stream_open_timing` event measuring the time to open a media stream (connect + `NewStream`), and add `throughputBytesPerSec` as a computed field on existing media progress/completion events.

**Why:** §12 instruments inbox per-step timing (connectMs, streamOpenMs), and §4 instruments chat stream open timing, but media streams use a separate `openMediaStream()` (media.go:80) that is uninstrumented. The 5-min `MediaTimeout` covers the full operation — can't tell if stream open is 200ms or 10s. Additionally, no throughput metric exists — progress events report bytes but not rate. This fills the gaps for 03b Section 2 Test E.

**Files to change:**
- `go-mknoon/node/media.go` — `openMediaStream()` (line 80), `MediaUpload` (line 148), `MediaDownload` (line 227)

**Test file:** `go-mknoon/node/node_test.go` or `go-mknoon/integration/media_test.go`

### Tests (write first)

**Test 1: openMediaStream emits stream open timing on success**
```
Setup:   Two test nodes connected via relay with media handler.
Act:     nodeA.MediaUpload(id, toPeerId, "image/jpeg", filePath, nil).
Assert:  waitForCollectedEvent "media:stream_open_timing" with:
         - data.connectMs >= 0
         - data.newStreamMs >= 0
         - data.totalMs >= 0
         - data.outcome == "success"
```

**Test 2: Stream open timing on connect failure**
```
Setup:   Test node with unreachable relay.
Act:     nodeA.MediaUpload (will fail at connect).
Assert:  "media:stream_open_timing" with:
         - data.connectMs >= 0
         - data.outcome == "connect_failed"
```

**Test 3: Stream open timing on NewStream failure**
```
Setup:   Test node where relay is reachable but doesn't support MediaProtocol.
Act:     nodeA.MediaUpload.
Assert:  "media:stream_open_timing" with:
         - data.connectMs >= 0
         - data.newStreamMs >= 0
         - data.outcome == "stream_failed"
```

**Test 4: MediaUpload completion includes throughput**
```
Setup:   Two test nodes, upload 100 KB file.
Act:     nodeA.MediaUpload(id, toPeerId, "image/jpeg", filePath, nil).
Assert:  waitForCollectedEvent "media:upload_complete" (or final progress event) with:
         - data.throughputBytesPerSec > 0
         - data.totalBytes == 102400
         - data.totalMs > 0
```

**Test 5: MediaDownload completion includes throughput**
```
Setup:   Upload file first, then download.
Act:     nodeB.MediaDownload(mediaId, outputPath).
Assert:  waitForCollectedEvent "media:download_complete" with:
         - data.throughputBytesPerSec > 0
         - data.totalBytes > 0
```

**Test 6: Throughput with 1MB, 5MB files (size-bucket sanity)**
```
Setup:   Create 1MB and 5MB test files.
Act:     Upload each file.
Assert:  Both emit "media:upload_complete" with throughputBytesPerSec > 0.
         5MB throughput is within 2x of 1MB throughput (no gross anomaly).
```

### Implementation

**Stream open timing** — in `openMediaStream()` (media.go:96):

```go
result, err := ForEachWithResult(rs, func(relay RelayInfo) (*streamResult, error) {
    totalStart := time.Now()
    ctx, cancel := context.WithTimeout(n.ctx, MediaTimeout)

    connectStart := time.Now()
    if err := h.Connect(ctx, peer.AddrInfo{ID: relay.ID, Addrs: relay.Addrs}); err != nil {
        cancel()
        n.emitEvent("media:stream_open_timing", map[string]interface{}{
            "connectMs": time.Since(connectStart).Milliseconds(),
            "totalMs":   time.Since(totalStart).Milliseconds(),
            "outcome":   "connect_failed",
        })
        return nil, fmt.Errorf("connect to relay: %w", err)
    }
    connectMs := time.Since(connectStart).Milliseconds()

    streamStart := time.Now()
    s, err := h.NewStream(ctx, relay.ID, MediaProtocol)
    if err != nil {
        cancel()
        n.emitEvent("media:stream_open_timing", map[string]interface{}{
            "connectMs":    connectMs,
            "newStreamMs":  time.Since(streamStart).Milliseconds(),
            "totalMs":      time.Since(totalStart).Milliseconds(),
            "outcome":      "stream_failed",
        })
        return nil, fmt.Errorf("open media stream: %w", err)
    }
    n.emitEvent("media:stream_open_timing", map[string]interface{}{
        "connectMs":   connectMs,
        "newStreamMs": time.Since(streamStart).Milliseconds(),
        "totalMs":     time.Since(totalStart).Milliseconds(),
        "outcome":     "success",
    })
    // ... existing stream deadline setup ...
```

**Throughput computation** — in `MediaUpload` (after io.Copy completes, line 201) and `MediaDownload` (after io.CopyN completes, line 256):

```go
transferMs := time.Since(transferStart).Milliseconds()
throughput := int64(0)
if transferMs > 0 {
    throughput = (totalBytes * 1000) / transferMs // bytes per second
}
n.emitEvent("media:upload_complete", map[string]interface{}{
    "totalBytes":           totalBytes,
    "totalMs":              transferMs,
    "throughputBytesPerSec": throughput,
})
```

Same pattern for download, ProfileUpload, ProfileDownload.

~35 lines Go: stream open timing in openMediaStream + throughput at 4 completion sites.

---

## 22. ML-KEM Keygen Timing

**What:** Emit `MLKEM_KEYGEN_TIMING` event measuring the time for ML-KEM-768 key generation, and add per-payload-size encryption timing to existing crypto instrumentation.

**Why:** §15 instruments `encryptMs`/`decryptMs` per message (Dart-side wrappers), but ML-KEM `keygen` happens during identity generation/restore and is uninstrumented. On a slow device, keygen could take 100ms+ — this is invisible today. Additionally, encryption cost may vary with payload size (1 KB chat vs 100 KB media metadata), but §15 doesn't break this down. This fills the gaps for 03b Section 2 Test G.

**Files to change:**
- `go-mknoon/bridge/bridge.go` — `MlKemKeygen()` (line 100), `EncryptMessage()`, `DecryptMessage()`
- `lib/features/identity/application/generate_identity_use_case.dart` — wrap keygen call with timing

**Test files:**
- `test/features/identity/application/generate_identity_use_case_test.dart`
- `go-mknoon/crypto/mlkem_test.go` (or `go-mknoon/bridge/bridge_test.go`)

### Tests (write first)

**Dart Test 1: Identity generation emits MLKEM_KEYGEN_TIMING**
```
Setup:   FakeBridge with mlkem.keygen response.
Act:     Call generateNewIdentity().
Assert:  captureFlowEvents contains 'MLKEM_KEYGEN_TIMING' with:
         - details.keygenMs is int >= 0
```

**Dart Test 2: Identity restore emits MLKEM_KEYGEN_TIMING**
```
Setup:   FakeBridge with mlkem.keygen + identity.restore responses.
Act:     Call restoreIdentity(mnemonic).
Assert:  'MLKEM_KEYGEN_TIMING' with details.keygenMs is int >= 0.
```

**Dart Test 3: keygenMs reflects actual bridge call duration**
```
Setup:   FakeBridge where mlkem.keygen takes 100ms (Future.delayed).
Act:     Call generateNewIdentity().
Assert:  'MLKEM_KEYGEN_TIMING' with details.keygenMs >= 100.
```

**Go Test 1: MlKemKeygen bridge function returns timing in response**
```
Setup:   Call bridge.MlKemKeygen().
Assert:  Response JSON includes "keygenMs" field with value >= 0.
```

**Go Test 2: EncryptMessage response includes payloadSizeBytes**
```
Setup:   Encrypt messages of 100 bytes, 1 KB, 10 KB.
Act:     Call EncryptMessage for each.
Assert:  Response includes "payloadSizeBytes" matching input length.
         Response includes "encryptMs" >= 0.
```

**Go Test 3: DecryptMessage response includes payloadSizeBytes and decryptMs**
```
Setup:   Encrypt then decrypt messages of various sizes.
Act:     Call DecryptMessage for each.
Assert:  Response includes "payloadSizeBytes" and "decryptMs" >= 0.
```

### Implementation

**Go side** — in `MlKemKeygen()` (bridge.go:100):

```go
func MlKemKeygen() (result string) {
    start := time.Now()
    kp, err := mcrypto.MlKemKeygen()
    keygenMs := time.Since(start).Milliseconds()
    // ... existing response building ...
    // Add keygenMs to response JSON:
    response["keygenMs"] = keygenMs
```

In `EncryptMessage()` and `DecryptMessage()`: add `payloadSizeBytes` (input length) and operation timing to response.

**Dart side** — in `generate_identity_use_case.dart`, wrap the `callMlKemKeygen` call:

```dart
final keygenStopwatch = Stopwatch()..start();
final mlkemResult = await callMlKemKeygen(bridge);
keygenStopwatch.stop();
emitFlowEvent(
  layer: 'FL',
  event: 'MLKEM_KEYGEN_TIMING',
  details: {'keygenMs': keygenStopwatch.elapsedMilliseconds},
);
```

Same for `restoreIdentity`.

The per-payload-size breakdown doesn't require code changes beyond what §15 already provides — the benchmark harness sends messages of various sizes and correlates `encryptMs` from §15 with `payloadSizeBytes` from the response. The Go-side `payloadSizeBytes` addition here enables that correlation.

~20 lines Go + Dart: keygen timing in bridge + Dart wrapper, payload size in encrypt/decrypt responses.

---

## 23. Pre-Existing Timeout Accuracy Instrumentation

**What:** Emit `timeout:fired` event whenever a pre-existing Go timeout fires, recording `timeoutName`, `configuredMs`, `actualMs`, and `context` (which operation timed out).

**Why:** 03d §1–§5 add and instrument 4 *new* timeouts, but the ~12 pre-existing timeouts (DialTimeout, PeerDialTimeout, SendTimeout, DiscoverTimeout, InboxTimeout, MediaTimeout, PubSubTimeout, DirectConfirmTimeout, InteractiveDialTimeout, InteractiveSendTimeout, InteractiveDiscoverTimeout, InteractiveInboxTimeout) fire silently. When a benchmark test forces an unresponsive peer/relay (03b Test H), there's no event to measure actual-vs-configured accuracy. This is the missing instrumentation for 03b Section 2 Test H.

**Files to change:**
- `go-mknoon/node/node.go` — timeout paths in `openChatStreamForSend`, `SendMessageWithTransport`, `warmRelayConnection`, `waitForRegisteredDirectConfirm`
- `go-mknoon/node/rendezvous.go` — timeout paths in `RendezvousRegister`, `RendezvousDiscover`
- `go-mknoon/node/inbox.go` — timeout paths in `InboxStore`, `InboxRetrieve`
- `go-mknoon/node/media.go` — timeout path in `openMediaStream`
- `go-mknoon/node/pubsub.go` — timeout path in `PublishGroupMessage`

**Test file:** `go-mknoon/node/node_test.go`

### Tests (write first)

**Test 1: DialTimeout fires and emits timeout:fired**
```
Setup:   Test node with unreachable relay address.
Act:     Call warmRelayConnection with the unreachable relay.
Assert:  waitForCollectedEvent "timeout:fired" with:
         - data.timeoutName == "DialTimeout"
         - data.configuredMs == 15000
         - data.actualMs >= 15000
         - data.actualMs < 20000  (not wildly over)
```

**Test 2: PeerDialTimeout fires within configured budget**
```
Setup:   Test node, attempt to dial unreachable peer.
Act:     Call DialPeer with unreachable peer ID.
Assert:  "timeout:fired" with:
         - data.timeoutName == "PeerDialTimeout"
         - data.configuredMs == 2000
         - data.actualMs >= 2000
```

**Test 3: SendTimeout fires on unresponsive peer**
```
Setup:   Two nodes, receiver drops stream after connect (never reads).
Act:     SendMessageWithTransport to receiver.
Assert:  "timeout:fired" with:
         - data.timeoutName == "SendTimeout"
         - data.configuredMs == 15000
```

**Test 4: DiscoverTimeout fires on unresponsive rendezvous**
```
Setup:   Test node with relay that doesn't support rendezvous protocol.
Act:     Call RendezvousDiscover.
Assert:  "timeout:fired" with:
         - data.timeoutName == "DiscoverTimeout"
         - data.configuredMs == 10000
```

**Test 5: DirectConfirmTimeout fires when Dart never confirms**
```
Setup:   Two nodes with deferred ACK, receiver never calls confirmDirectAck.
Act:     Send message.
Assert:  "timeout:fired" with:
         - data.timeoutName == "DirectConfirmTimeout"
         - data.configuredMs == 2000
         - data.actualMs >= 2000
```

**Test 6: Interactive timeouts fire with shorter budgets**
```
Setup:   Test node using InteractiveTimeoutProfile.
Act:     Send to unreachable peer (triggers InteractiveSendTimeout = 3s).
Assert:  "timeout:fired" with:
         - data.timeoutName == "InteractiveSendTimeout"
         - data.configuredMs == 3000
```

**Test 7: MediaTimeout fires on stalled media stream**
```
Setup:   Test node with relay that accepts connect but never responds to media request.
Act:     MediaUpload (will stall).
Assert:  "timeout:fired" with:
         - data.timeoutName == "MediaTimeout"
         - data.configuredMs == 300000  (5 min)
```

**Test 8: No timeout:fired emitted on successful operations**
```
Setup:   Two connected nodes, all operations succeed quickly.
Act:     Send message, discover peer, store inbox.
Assert:  No "timeout:fired" events collected.
```

### Implementation

**Pattern:** Add a helper function that wraps the timeout detection:

```go
func (n *Node) emitTimeoutFired(name string, configured time.Duration, start time.Time) {
    n.emitEvent("timeout:fired", map[string]interface{}{
        "timeoutName":  name,
        "configuredMs": configured.Milliseconds(),
        "actualMs":     time.Since(start).Milliseconds(),
    })
}
```

**At each timeout site**, check whether the error is a context deadline exceeded or timer fire, and emit:

In `warmRelayConnection` (node.go:542):
```go
func (n *Node) warmRelayConnection(info peer.AddrInfo) error {
    start := time.Now()
    ctx, cancel := context.WithTimeout(n.ctx, DialTimeout)
    defer cancel()
    if err := n.host.Connect(ctx, info); err != nil {
        if ctx.Err() == context.DeadlineExceeded {
            n.emitTimeoutFired("DialTimeout", DialTimeout, start)
        }
        return fmt.Errorf("dial relay: %w", err)
    }
    return nil
}
```

Same pattern applied to:
- `openChatStreamForSend` → `SendTimeout` / `InteractiveSendTimeout`
- `DialPeer` → `PeerDialTimeout` / `InteractiveDialTimeout`
- `RendezvousRegister` / `RendezvousDiscover` → `DiscoverTimeout` / `InteractiveDiscoverTimeout`
- `InboxStore` / `InboxRetrieve` → `InboxTimeout` / `InteractiveInboxTimeout`
- `openMediaStream` → `MediaTimeout`
- `PublishGroupMessage` → `PubSubTimeout`
- `waitForRegisteredDirectConfirm` → `DirectConfirmTimeout` (timer-based, not context)

For timer-based timeouts (DirectConfirmTimeout), emit in the `case <-timer.C:` branch:

```go
case <-timer.C:
    n.emitTimeoutFired("DirectConfirmTimeout", DirectConfirmTimeout, waitStart)
    return false
```

~40 lines Go: helper function + ~12 call site additions (1–3 lines each).

---

## 24. Time-to-Online Badge

**What:** Emit `TIME_TO_ONLINE_BADGE` event measuring the full user-perceived latency from app startup (or recovery trigger) to the moment the `ConnectionStatusIndicator` widget displays the green "Online" badge.

**Why:** §18 measures Go-side startup phases (`totalToDiscoverableMs`), but the user doesn't see a Go event — they see a green dot. Between Go emitting `relay:state online` and the badge turning green, the signal crosses: Go EventDispatcher queue → MethodChannel → Dart `_handleRelayStateChanged()` → `_emitState()` → `stateStream` → `ConnectionStatusIndicator._onState()` → `healthFromState()` → `setState()` → Flutter frame render. Each hop adds latency. No existing instrumentation measures this full chain. This is the single most user-visible latency metric in the app.

**Measurement points:**
1. **Cold start:** `startNodeCore()` call → green badge
2. **Recovery:** relay goes degraded → green badge restored (includes detection + recovery + UI propagation)

**Files to change:**
- `lib/core/services/p2p_service_impl.dart` — record `_nodeStartRequestedAt` timestamp, emit timing when first online state arrives
- `lib/features/p2p/presentation/widgets/connection_status_indicator.dart` — emit timing when widget transitions to `ConnectionHealth.online`

**Test files:**
- `test/core/services/p2p_service_impl_test.dart`
- `test/features/p2p/presentation/widgets/connection_status_indicator_test.dart`

### Tests (write first)

**Test 1: Cold start emits TIME_TO_ONLINE_BADGE after first online state**
```
Setup:   FakeBridge where node:start succeeds (returns isStarted=true,
         no circuit addresses yet). Then after 500ms, relay:state push
         delivers relayState='online'.
Act:     Call startNodeCore() + warmBackground().
Assert:  captureFlowEvents contains 'TIME_TO_ONLINE_BADGE' with:
         - details.totalMs >= 500
         - details.phase == 'cold_start'
         - details.source == 'relay_state_push'
```

**Test 2: Fast circuit check path emits timing**
```
Setup:   FakeBridge where node:start returns isStarted but no circuit
         addresses. Push event never arrives. After 2s, fast circuit
         check polls and finds relayState='online'.
Act:     Call startNodeCore() + warmBackground().
Assert:  'TIME_TO_ONLINE_BADGE' with:
         - details.totalMs >= 2000
         - details.source == 'health_check_poll'
```

**Test 3: Already-online start emits near-zero timing**
```
Setup:   FakeBridge where node:start returns isStarted=true WITH
         circuitAddresses populated (relay was already warm).
Act:     Call startNodeCore().
Assert:  'TIME_TO_ONLINE_BADGE' with:
         - details.totalMs < 100  (immediate)
         - details.phase == 'cold_start'
         - details.source == 'start_response'
```

**Test 4: Recovery emits TIME_TO_ONLINE_BADGE with phase='recovery'**
```
Setup:   P2PServiceImpl already online. Then relay:state push delivers
         relayState='recovering'. Then 3s later, relay:state delivers
         relayState='online'.
Act:     Simulate relay degradation → recovery.
Assert:  'TIME_TO_ONLINE_BADGE' with:
         - details.totalMs >= 3000
         - details.phase == 'recovery'
```

**Test 5: Widget-level timing includes Flutter frame delay**
```
Setup:   ConnectionStatusIndicator with FakeP2PService.
         Service starts in degraded state.
Act:     Push NodeState with relayState='online' to stateStream.
         Pump widgets to trigger rebuild.
Assert:  captureFlowEvents contains 'TIME_TO_ONLINE_BADGE_WIDGET' with:
         - details.widgetTransitionMs >= 0
         (Time from stateStream event to widget setState completing.)
```

**Test 6: No duplicate timing on transient flicker**
```
Setup:   P2PServiceImpl online. Push degraded then online within 100ms.
Act:     Simulate quick relay flicker.
Assert:  Only ONE 'TIME_TO_ONLINE_BADGE' event emitted
         (not one per flicker).
```

**Test 7: Hot restart emits timing from resync**
```
Setup:   FakeBridge where node:start returns 'already started', then
         node:status returns isStarted with circuitAddresses.
Act:     Call startNodeCore() (hot restart path).
Assert:  'TIME_TO_ONLINE_BADGE' with:
         - details.phase == 'hot_restart'
         - details.totalMs >= 0
```

### Implementation

**Step 1: Service-level timing** — in `p2p_service_impl.dart`:

Add state fields:

```dart
DateTime? _nodeStartRequestedAt;    // set when startNodeCore() is called
DateTime? _lastWentOfflineAt;       // set when state transitions away from online
bool _coldStartOnlineEmitted = false;  // prevent duplicate cold-start events
```

In `startNodeCore()` (line 180):

```dart
_nodeStartRequestedAt = DateTime.now();
_coldStartOnlineEmitted = false;
```

In `_emitState()` (line 1214), after the state is updated, check for online transition:

```dart
void _emitState(NodeState newState) {
  final wasOnline = _stateHasHealthyRelay(_currentState);
  _currentState = newState;
  if (!_stateController.isClosed) {
    _stateController.add(_currentState);
  }

  final nowOnline = _stateHasHealthyRelay(_currentState);

  // Cold start: first time reaching online after node start
  if (nowOnline && !wasOnline && !_coldStartOnlineEmitted &&
      _nodeStartRequestedAt != null) {
    _coldStartOnlineEmitted = true;
    final totalMs = DateTime.now()
        .difference(_nodeStartRequestedAt!)
        .inMilliseconds;
    emitFlowEvent(
      layer: 'FL',
      event: 'TIME_TO_ONLINE_BADGE',
      details: {
        'totalMs': totalMs,
        'phase': _lastWentOfflineAt != null ? 'recovery' : 'cold_start',
        'source': _detectOnlineSource(),
      },
    );
    _lastWentOfflineAt = null;
  }

  // Track when we lose online status (for recovery timing)
  if (!nowOnline && wasOnline) {
    _lastWentOfflineAt = DateTime.now();
  }
}
```

The `_detectOnlineSource()` helper returns `'start_response'`, `'relay_state_push'`, or `'health_check_poll'` based on which code path called `_emitState`. This can be implemented by passing an optional `source` string through each `_emitState` call site, or by tracking which handler is currently executing.

**Simpler approach:** Add an optional parameter to `_emitState`:

```dart
void _emitState(NodeState newState, {String? source}) {
  // ... existing logic ...
  // Use source in the timing event
}
```

Then tag each call site:
- `startNodeCore()` line 205: `_emitState(NodeState.fromJson(response), source: 'start_response')`
- `_handleRelayStateChanged()` line 1734: `_emitState(updatedState, source: 'relay_state_push')`
- `_performHealthCheck()` line 1474: `_emitState(freshState, source: 'health_check_poll')`
- `_handleAddressesUpdated()` line 1651: `_emitState(updatedState, source: 'addresses_push')`

**Step 2: Widget-level timing** — in `connection_status_indicator.dart`:

In `_onState()` (line 75), when transitioning to online, measure the gap:

```dart
void _onState(NodeState state) {
  final incoming = healthFromState(state);

  // ... existing logic ...

  // Upgrade to online: emit widget-level timing
  if (incoming == ConnectionHealth.online &&
      _displayedHealth != ConnectionHealth.online) {
    _downgradeTimer?.cancel();
    _downgradeTimer = null;

    emitFlowEvent(
      layer: 'FL',
      event: 'TIME_TO_ONLINE_BADGE_WIDGET',
      details: {
        'widgetTransitionMs': _lastStateReceivedAt != null
            ? DateTime.now().difference(_lastStateReceivedAt!).inMilliseconds
            : 0,
        'previousHealth': _displayedHealth.name,
      },
    );

    setState(() {
      _displayedHealth = incoming;
      _connectionCount = count;
    });
    return;
  }
  // ... rest of existing logic ...
}
```

Add `_lastStateReceivedAt = DateTime.now();` at the top of `_onState` to track when the stream event arrived, so `widgetTransitionMs` captures the processing + setState gap.

**Recovery path:** When `_lastWentOfflineAt` is set (online → degraded transition), the next online arrival computes `totalMs` from `_lastWentOfflineAt` instead of `_nodeStartRequestedAt`, giving the recovery-specific time-to-online-badge.

```dart
if (nowOnline && !wasOnline && _lastWentOfflineAt != null) {
  final recoveryTotalMs = DateTime.now()
      .difference(_lastWentOfflineAt!)
      .inMilliseconds;
  emitFlowEvent(
    layer: 'FL',
    event: 'TIME_TO_ONLINE_BADGE',
    details: {
      'totalMs': recoveryTotalMs,
      'phase': 'recovery',
      'source': source ?? 'unknown',
    },
  );
  _lastWentOfflineAt = null;
}
```

**Note on deduplication:** The `_coldStartOnlineEmitted` flag prevents duplicate events during startup (where multiple code paths may race to emit the first online state — the start response itself, the relay:state push, and the 2s fast circuit check). Only the first wins.

~30 lines Dart: 3 state fields + timing logic in `_emitState` + widget-level event in `ConnectionStatusIndicator`.

### What the Benchmark Harness Measures

With this instrumentation, the harness can collect:

| Metric | Source | What It Tells You |
|---|---|---|
| `TIME_TO_ONLINE_BADGE.totalMs` (cold_start) | Service layer | Wall-clock from `startNodeCore()` to first online state |
| `TIME_TO_ONLINE_BADGE.totalMs` (recovery) | Service layer | Wall-clock from degradation to online restored |
| `TIME_TO_ONLINE_BADGE.source` | Service layer | Which delivery path won the race (push vs poll) |
| `TIME_TO_ONLINE_BADGE_WIDGET.widgetTransitionMs` | Widget layer | stateStream → green dot (Dart processing + render) |
| `node:startup_timing` (§18) | Go layer | Per-phase Go-side breakdown |

The full user-perceived latency = `TIME_TO_ONLINE_BADGE.totalMs` + `TIME_TO_ONLINE_BADGE_WIDGET.widgetTransitionMs`. The Go-side §18 events let you decompose the service-layer time into libp2p, relay, circuit, and rendezvous sub-phases.

---

## Implementation Order

The items are independent — any can be implemented in isolation. Recommended order by value/effort ratio:

| Priority | Item | Effort | Why first |
|---|---|---|---|
| 1 | **§24 Time-to-online badge** | ~30 lines Dart | Most user-visible latency metric, zero Go changes |
| 2 | **§7 Connection reuse counters** | ~15 lines Dart | Immediate baseline data, zero Go changes |
| 3 | **§10 Per-step 1:1 send** | ~40 lines Dart | Fills #1 blind spot |
| 4 | **§8 Voice send sub-steps** | ~20 lines Dart | Simple, high-value (upload vs send split) |
| 5 | **§3 Group send per-step** | ~20 lines Dart | Fills biggest group messaging blind spot |
| 6 | **§15 1:1 encryption timing** | ~15 lines Dart | Low effort, answers key unknown |
| 7 | **§1 Post `_TIMING` summary** | ~15 lines Dart | Aligns post path with other send paths |
| 8 | **§2 Local WiFi `_TIMING`** | ~20 lines Dart | Completes local transfer observability |
| 9 | **§14 Bridge crossing time** | ~20 lines Dart | Reveals hidden Dart↔Go overhead |
| 10 | **§19 Relay outage timing** | ~25 lines Dart | Fills recovery detection blind spot (Test C) |
| 11 | **§22 ML-KEM keygen timing** | ~20 lines Go+Dart | Fills crypto baseline gap (Test G) |
| 12 | **§6 Event queue wait** | ~20 lines Go | Reveals hidden Go-side latency |
| 13 | **§16 Group encrypt/decrypt** | ~20 lines Go | Separates crypto cost from network cost |
| 14 | **§4 Go per-step timing** | ~50 lines Go | Fills major Go blind spots |
| 15 | **§12 Inbox round-trip** | ~40 lines Go | Fills inbox fallback blind spot |
| 16 | **§20 Inbox end-to-end delivery** | ~20 lines Go+Dart | Fills inbox round-trip gap (Test D) |
| 17 | **§18 Node startup timing** | ~30 lines Go | Fills startup breakdown gap (Test B) |
| 18 | **§21 Media stream open + throughput** | ~35 lines Go | Fills media blind spot (Test E) |
| 19 | **§17 Relay failover timing** | ~45 lines Go | Quantifies dead-relay penalty |
| 20 | **§23 Pre-existing timeout accuracy** | ~40 lines Go | Enables timeout accuracy testing (Test H) |
| 21 | **§11 Circuit address delay** | ~15 lines Go | Fills startup timing blind spot |
| 22 | **§13 GossipSub delivery** | ~15 lines Go | Cross-node latency (clock skew caveat) |
| 23 | **§5 Correlation ID** | ~30 lines Go+Dart | Enables end-to-end tracing |
| 24 | **§9 Deferred ACK timing** | ~20 lines Go | Validates 2s budget margin |

Items 1–10 are Dart-only (or Dart-primary). Items 11–24 require Go changes and a `make all` + `pod install` rebuild cycle.

### Benchmark Harness Coverage

After implementing all 24 items (§1–§24) plus the 5 hazard fixes from `03d`, every test scenario in `03b` Section 2 has the instrumentation needed for a benchmark harness to collect measurements:

| 03b Test | Instrumentation Source |
|---|---|
| **A. Per-Step 1:1 Send** | §4, §7, §10 |
| **B. Node Startup** | §4, §11, **§18**, **§24** |
| **C. Relay Recovery** | 03d §4, **§19**, **§24** (recovery phase) |
| **D. Inbox Round-Trip** | §12, **§20** |
| **E. Media Transfer** | §2, 03d §3, 03d §5, **§21** |
| **F. Bridge Crossing** | §14 |
| **G. Encryption Overhead** | §15, §16, **§22** |
| **H. Timeout Accuracy** | 03d §1–§5, **§23** |
| **I. Event Queue Wait** | §6 |
| **J. Connection Reuse Hit Rate** | §7, §10 |
| **K. Voice Sub-Steps** | §8 |
| **L. Deferred Direct ACK** | §9 |
| **User-Perceived Online** | **§24** + §18 (Go breakdown) |
