# Hazard Fixes — TDD Plan

> **Scope:** Test-driven implementation plan for the 5 hazard fixes listed in `03b-timing-improvement-plan.md` Section 4.
> **Depends on:** `03-timing-and-performance.md` (hazard descriptions), `03b-timing-improvement-plan.md` (fix designs and rationale).
> **Does not cover:** Instrumentation changes (see `03c`), routing changes (see `04b`).

---

## Conventions

### Dart Test Pattern

Tests use `captureFlowEvents` to verify events and standard `expect` matchers. Timeout tests use `FakeBridge` that never completes:

```dart
class _HangingBridge extends FakeBridge {
  @override
  Future<String> send(String message) => Completer<String>().future; // never completes
}
```

### Go Test Pattern

Go tests use `testEventCollector` + `waitForCollectedEvent` (from `node_test.go:1222` and `group_security_harness_test.go:13`). Recovery tests use the existing `relay_session_test.go` harness.

---

## 1. Add Dart-Side `.timeout()` to `callP2PInboxStore`

**What:** Wrap `bridge.send()` in `callP2PInboxStore` with `.timeout(const Duration(seconds: 15))`.

**Why:** Today, if the bridge hangs (MethodChannel stall, Go runtime deadlock), Dart blocks **indefinitely**. Go's `InboxTimeout = 15s` only fires if the call reaches Go. The Dart-side timeout is a safety net that matches the Go-side budget.

**File to change:** `lib/core/bridge/p2p_bridge_client.dart` (line 401)
**Test file:** `test/core/bridge/p2p_bridge_client_test.dart`

**Current code (line 401):**
```dart
final responseJson = await bridge.send(jsonEncode(request));
```

**After fix:**
```dart
final responseJson = await bridge.send(jsonEncode(request)).timeout(
  const Duration(seconds: 15),
);
```

### Tests (write first)

**Test 1: Successful inbox store still works (no regression)**
```
Setup:   FakeBridge that returns { "ok": true, "stored": true } immediately.
Act:     callP2PInboxStore(bridge, toPeerId: 'abc', message: 'hello').
Assert:  Returns { "ok": true, "stored": true }.
         No TimeoutException thrown.
```

**Test 2: Bridge hang triggers TimeoutException after 15s**
```
Setup:   _HangingBridge (Completer that never completes).
Act:     callP2PInboxStore(bridge, toPeerId: 'abc', message: 'hello').
Assert:  Throws TimeoutException.
         Exception thrown within 16s (15s timeout + margin).
```

**Test 3: Service wrapper catches timeout and returns false**
```
Setup:   _HangingBridge.
Act:     p2pService.storeInInbox('abc', 'hello') (the service wrapper in p2p_service_impl.dart:1804).
Assert:  Returns false (existing catch block handles TimeoutException).
```

**Test 4: Send use case marks message as failed on inbox timeout**
```
Setup:   FakeP2PService where:
         - direct send fails (peer not found)
         - relay probe fails
         - storeInInbox hangs (triggers timeout)
Act:     sendChatMessage(...).
Assert:  Message saved with status: 'failed'.
         wireEnvelope is retained (not null).
         CHAT_MSG_SEND_TIMING emitted with outcome: 'failed'.
```

**Test 5: PendingMessageRetrier picks up the failed message**
```
Setup:   Message in DB with status: 'failed', wireEnvelope present.
         P2P state transitions to online.
Act:     Wait for retrier debounce (5s) + sweep.
Assert:  retryFailedMessages called.
         Message retried via sendChatMessage with original messageId.
```

### Implementation

2 lines changed in `p2p_bridge_client.dart`:

```dart
// Before:
final responseJson = await bridge.send(jsonEncode(request));

// After:
final responseJson = await bridge
    .send(jsonEncode(request))
    .timeout(const Duration(seconds: 15));
```

The existing call sites (`p2p_service_impl.dart:1804`, `send_chat_message_use_case.dart:443,953`) already catch exceptions and handle failure — no changes needed there.

---

## 2. Add Dart-Side `.timeout()` to `callP2PRelayProbe`

**What:** Wrap `bridge.send()` in `callP2PRelayProbe` with `.timeout(const Duration(seconds: 5))`.

**Why:** Same bridge-hang risk as inbox store. Go's `RelayProbeTimeout = 5s` only fires Go-side. If the bridge stalls, the 1:1 send path hangs at the probe step instead of falling through to inbox.

**File to change:** `lib/core/bridge/p2p_bridge_client.dart` (line 162)
**Test file:** `test/core/bridge/p2p_bridge_client_test.dart`

**Current code (line 162):**
```dart
final responseJson = await bridge.send(jsonEncode(request));
```

**After fix:**
```dart
final responseJson = await bridge.send(jsonEncode(request)).timeout(
  const Duration(seconds: 5),
);
```

### Tests (write first)

**Test 1: Successful probe still works (no regression)**
```
Setup:   FakeBridge that returns { "ok": true } immediately.
Act:     callP2PRelayProbe(bridge, peerId: 'abc').
Assert:  Returns { "ok": true }.
```

**Test 2: Bridge hang triggers TimeoutException after 5s**
```
Setup:   _HangingBridge.
Act:     callP2PRelayProbe(bridge, peerId: 'abc').
Assert:  Throws TimeoutException.
         Exception thrown within 6s (5s + margin).
```

**Test 3: Service wrapper returns RelayProbeResult.error on timeout**
```
Setup:   _HangingBridge.
Act:     p2pService.probeRelay('abc') (service wrapper in p2p_service_impl.dart:1997).
Assert:  Returns RelayProbeResult.error (existing catch block).
```

**Test 4: Send path falls through to inbox on probe timeout**
```
Setup:   FakeP2PService where:
         - direct send fails (peer not found, relay probe eligible)
         - probeRelay hangs (triggers 5s timeout → returns error)
         - storeInInbox succeeds
Act:     sendChatMessage(...).
Assert:  Message delivered via inbox.
         CHAT_MSG_SEND_TIMING includes sendPath: 'inbox'.
         Total elapsed is roughly 2s (direct budget) + 5s (probe timeout) + inbox time.
```

### Implementation

2 lines changed in `p2p_bridge_client.dart`:

```dart
// Before:
final responseJson = await bridge.send(jsonEncode(request));

// After:
final responseJson = await bridge
    .send(jsonEncode(request))
    .timeout(const Duration(seconds: 5));
```

The existing call site (`p2p_service_impl.dart:1997`) already catches exceptions and returns `RelayProbeResult.error`. The send use case (line 721) handles `error` result by falling through to inbox.

---

## 3. Profile Upload Progress Events

**What:** Wrap `ProfileUpload`'s bare `io.Copy(s, f)` with `mediaUploadProgressReader`, emitting `profile:upload_progress` events — same pattern as `MediaUpload`.

**Why:** Profile upload can stall 5 minutes with zero UI feedback. `MediaUpload` already wraps the reader with `mediaUploadProgressReader` emitting progress every 256 KB or 250 ms. `ProfileUpload` at line 358 uses bare `io.Copy(s, f)` — no events, no visibility.

**File to change:** `go-mknoon/node/media.go` (lines 355-358)
**Test file:** `go-mknoon/integration/media_test.go` (or new `go-mknoon/node/media_test.go`)

**Current code (lines 355-358):**
```go
if _, err := io.Copy(s, f); err != nil {
    return fmt.Errorf("stream profile data: %w", err)
}
```

**After fix:**
```go
progressReader := &mediaUploadProgressReader{
    reader:     f,
    totalBytes: fi.Size(),
    lastEmitAt: time.Now(),
    emitProgressFn: func(sentBytes, totalBytes int64) {
        n.emitEvent("profile:upload_progress", map[string]interface{}{
            "sentBytes":  sentBytes,
            "totalBytes": totalBytes,
        })
    },
}
progressReader.emitProgressFn(0, fi.Size())
if _, err := io.Copy(s, progressReader); err != nil {
    return fmt.Errorf("stream profile data: %w", err)
}
progressReader.emitProgressFn(fi.Size(), fi.Size())
```

### Tests (write first)

**Test 1: Profile upload emits initial progress event (0 bytes)**
```
Setup:   Two test nodes connected, relay with media handler.
         Create 10 KB test file.
Act:     nodeA.ProfileUpload("image/jpeg", testFilePath).
Assert:  waitForCollectedEvent "profile:upload_progress" with:
         - data.sentBytes == 0
         - data.totalBytes == 10240
```

**Test 2: Profile upload emits final progress event (all bytes)**
```
Setup:   Same as Test 1.
Act:     nodeA.ProfileUpload("image/jpeg", testFilePath).
Assert:  Collect all "profile:upload_progress" events.
         Last event has sentBytes == totalBytes == 10240.
```

**Test 3: Large file emits intermediate progress events**
```
Setup:   Create 1 MB test file (exceeds 256 KB chunk threshold).
Act:     nodeA.ProfileUpload("image/jpeg", testFilePath).
Assert:  At least 3 "profile:upload_progress" events emitted:
         - Initial (0 bytes)
         - At least one intermediate (around 256 KB)
         - Final (all bytes)
```

**Test 4: Upload failure still works (no regression)**
```
Setup:   Relay that rejects profile upload (returns error).
Act:     nodeA.ProfileUpload("image/jpeg", testFilePath).
Assert:  Returns error.
         Initial progress event (0 bytes) may have been emitted.
         No crash.
```

**Test 5: Event structure matches MediaUpload pattern**
```
Setup:   Upload 10 KB file.
Act:     nodeA.ProfileUpload("image/jpeg", testFilePath).
Assert:  All "profile:upload_progress" events have exactly:
         { "sentBytes": int, "totalBytes": int }
         No extra fields. No "id" or "toPeerId" (profile is not peer-specific).
```

### Implementation

~10 lines Go. Replace bare `io.Copy` with `mediaUploadProgressReader` wrapper (reuses existing struct). Add two bookend calls for initial/final progress.

---

## 4. Add Timeout to `recoveryPromise.Wait()` (Go Relay Recovery Coalescing)

**What:** Replace the unbounded `<-p.done` in `Wait()` with a `select` that includes a timeout. Return a structured `RECOVERY_TIMEOUT` error when the timeout fires. Clear the shared recovery gate so the next attempt can start fresh.

**Why:** If the owning recovery goroutine stalls (panic, deadlock, network hang), every concurrent caller of `BeginRecovery().Wait()` blocks permanently. The node's relay functionality is dead until app restart.

**File to change:** `go-mknoon/node/relay_session.go`
**Test file:** `go-mknoon/node/relay_session_test.go`

### Design (from 03b)

- Timeout: 30s (generous — recovery involves relay dial 15s + circuit address 10s)
- On timeout: return `RecoveryResult{RecoveryMode: "timeout"}` with error `RECOVERY_TIMEOUT`
- Clear the shared gate: set `m.recovering = false`, `m.recovery = nil` so next `BeginRecovery()` can start fresh
- Do NOT retry in Go — Dart owns retry via periodic health check (30s) and `relay:reconnect`
- Do NOT add new relay state — existing `relayState != online` already means degraded

### Tests (write first)

**Test 1: Normal recovery still works — all waiters get result**
```
Setup:   RelaySessionManager.
Act:     Goroutine A calls BeginRecovery() → gets isNew=true.
         Goroutines B, C call BeginRecovery() → get isNew=false, same promise.
         Goroutine A calls CompleteRecovery(successResult, nil) after 100ms.
Assert:  All three goroutines receive successResult.
         No timeout error.
```

**Test 2: Stalled recovery triggers timeout after 30s**
```
Setup:   RelaySessionManager.
Act:     Goroutine A calls BeginRecovery() → gets isNew=true.
         Goroutine A NEVER calls CompleteRecovery (simulates stall).
         Goroutine B calls BeginRecovery() → gets isNew=false, waits.
Assert:  Goroutine B's Wait() returns error after ~30s.
         Error contains "RECOVERY_TIMEOUT".
         Result is nil or RecoveryResult{RecoveryMode: "timeout"}.
```

**Test 3: Timeout clears the recovery gate**
```
Setup:   RelaySessionManager.
Act:     Goroutine A starts recovery, never completes.
         Goroutine B waits, times out after 30s.
         Goroutine C calls BeginRecovery() AFTER B's timeout.
Assert:  Goroutine C gets isNew=true (gate was cleared).
         New recovery can proceed.
```

**Test 4: Late completion after timeout is ignored**
```
Setup:   RelaySessionManager.
Act:     Goroutine A starts recovery, never completes within 30s.
         All waiters time out. Gate is cleared.
         Goroutine A finally calls CompleteRecovery() (late).
Assert:  No panic. No crash.
         Late completion is silently ignored.
         New recovery started by a subsequent BeginRecovery() is unaffected.
```

**Test 5: Concurrent waiters all receive timeout simultaneously**
```
Setup:   RelaySessionManager.
Act:     Goroutine A starts recovery, never completes.
         Goroutines B, C, D all wait on the same promise.
Assert:  All three receive timeout error within 1s of each other.
         (Not sequential — the channel close wakes all.)
```

**Test 6: Dart-side relay:reconnect surfaces timeout as failure**
```
Setup:   Node with RelaySessionManager where recovery will stall.
Act:     Call ReconnectRelays() (which calls BeginRecovery + Wait).
Assert:  Returns error containing "RECOVERY_TIMEOUT".
         Error is NOT swallowed — propagates to bridge response.
         Dart receives { "ok": false, "errorCode": "RELAY_ERROR" }.
```

### Implementation

**Step 1:** Add a timeout constant:

```go
const RecoveryWaitTimeout = 30 * time.Second
```

**Step 2:** Replace `Wait()` (relay_session.go:328):

```go
func (p *recoveryPromise) Wait() (*RecoveryResult, error) {
    if p == nil {
        return nil, nil
    }
    select {
    case <-p.done:
        return p.result, p.err
    case <-time.After(RecoveryWaitTimeout):
        return &RecoveryResult{RecoveryMode: "timeout"}, fmt.Errorf("RECOVERY_TIMEOUT")
    }
}
```

**Step 3:** Clear the gate on timeout in the helper functions (relay_session.go:581, 603):

```go
func waitForSharedRecoveryResult(recovery *recoveryPromise) *RecoveryResult {
    result, err := recovery.Wait()
    if err != nil && err.Error() == "RECOVERY_TIMEOUT" {
        // Gate will be cleared by the timeout path — callers retry later
        log.Printf("[RELAY_SESSION] Recovery wait timed out")
    }
    if result != nil {
        return result
    }
    return &RecoveryResult{RecoveryMode: "unknown"}
}
```

**Step 4:** Clear the shared gate when timeout fires. Add a cleanup method to `RelaySessionManager`:

```go
func (m *RelaySessionManager) ClearStalledRecovery() {
    m.mu.Lock()
    defer m.mu.Unlock()
    if m.recovering {
        m.recovering = false
        m.recovery = nil
        m.recomputeAggregateLocked()
    }
}
```

Call `ClearStalledRecovery()` from the helper functions when they detect a timeout. The next `BeginRecovery()` call will start a fresh recovery.

**Step 5:** Handle late completion. In `CompleteRecovery()` (line 338), the existing `if recovery != nil` guard already handles this — if the promise has been cleared, `recovery` is nil and `close(recovery.done)` is not called. Add a nil check before close:

```go
func (m *RelaySessionManager) CompleteRecovery(result *RecoveryResult, err error) {
    m.mu.Lock()
    recovery := m.recovery
    // ... existing state updates ...
    m.recovery = nil
    m.mu.Unlock()

    if recovery != nil {
        recovery.result = result
        recovery.err = err
        close(recovery.done)
    }
    // If recovery is nil (cleared by timeout), this is a no-op. Safe.
}
```

~25 lines Go.

---

## 5. Media Idle Timeout — Add Throughput Floor to `io.Copy`

**What:** Replace `io.Copy(s, reader)` and `io.CopyN(f, s, size)` in media operations with a stall-detecting wrapper that fails after 10s of no bytes flowing.

**Why:** A stalled connection trickling 1 byte/s runs for the full 5-min `MediaTimeout` before dying. The idle timeout catches stalls fast (10s), while the existing 5-min absolute deadline remains the outer guard.

**Files to change:** `go-mknoon/node/media.go`
**Test file:** `go-mknoon/node/media_test.go` (new file) or `go-mknoon/integration/media_test.go`

### Design (from 03b)

- Stall = no bytes copied for 10s
- On stall: return `io.ErrUnexpectedEOF` or a custom `ErrStallTimeout`
- Existing 5-min deadline remains as outer guard
- Treat stall as normal transient failure — existing retry paths handle recovery
- Applied to: `MediaUpload` (line 201), `MediaDownload` (line 256), `ProfileUpload` (line 358), `ProfileDownload` (line 408)

### Tests (write first)

**Test 1: Normal upload completes (no regression)**
```
Setup:   Connected test nodes, relay with media handler.
         Create 100 KB test file.
Act:     nodeA.MediaUpload(id, toPeerId, "image/jpeg", filePath, nil).
Assert:  Returns nil (success).
         File transferred correctly.
```

**Test 2: Stalled upload fails after idle timeout**
```
Setup:   Custom io.Reader that writes 1 KB then blocks forever.
         idleTimeoutReader wrapping it with 1s timeout (shortened for test speed).
Act:     io.Copy(writer, idleTimeoutReader).
Assert:  Returns ErrStallTimeout after ~1s.
         Bytes written == 1024 (partial transfer).
```

**Test 3: Slow but steady upload succeeds (no false positive)**
```
Setup:   Custom io.Reader that writes 100 bytes every 500ms (slow but continuous).
         idleTimeoutReader with 2s timeout.
Act:     io.Copy(writer, idleTimeoutReader).
Assert:  Completes successfully (no timeout).
         Each 500ms chunk resets the idle timer.
```

**Test 4: Stalled download fails after idle timeout**
```
Setup:   Custom io.Reader that writes 1 KB then blocks forever.
         idleTimeoutReader wrapping it with 1s timeout.
Act:     io.CopyN(writer, idleTimeoutReader, 100*1024).
Assert:  Returns ErrStallTimeout after ~1s.
```

**Test 5: Idle timer resets on each chunk**
```
Setup:   Custom io.Reader that writes 1 KB, pauses 800ms, writes 1 KB, pauses 800ms, etc.
         idleTimeoutReader with 1s timeout.
Act:     io.Copy(writer, idleTimeoutReader) until reader exhausted.
Assert:  Completes successfully.
         Each 800ms pause is within the 1s idle budget — timer resets on each Read.
```

**Test 6: ProfileUpload stall fails with idle timeout**
```
Setup:   Test node with stalling stream (custom net.Conn or pipe that blocks after partial write).
Act:     nodeA.ProfileUpload("image/jpeg", filePath).
Assert:  Returns error containing "stall" or "idle timeout".
```

**Test 7: ProfileDownload stall fails with idle timeout**
```
Setup:   Test node with stalling stream on read side.
Act:     nodeA.ProfileDownload(ownerPeerId, outputPath).
Assert:  Returns error containing "stall" or "idle timeout".
```

### Implementation

**Step 1:** Define the idle timeout constant and error:

```go
const MediaIdleTimeout = 10 * time.Second

var ErrStallTimeout = fmt.Errorf("media transfer stalled: no bytes for %v", MediaIdleTimeout)
```

**Step 2:** Create an `idleTimeoutReader` wrapper:

```go
// idleTimeoutReader wraps an io.Reader and fails if no bytes
// are read within the idle timeout period. The timer resets
// on every successful Read that returns n > 0.
type idleTimeoutReader struct {
    reader      io.Reader
    idleTimeout time.Duration
    timer       *time.Timer
}

func newIdleTimeoutReader(r io.Reader, timeout time.Duration) *idleTimeoutReader {
    return &idleTimeoutReader{
        reader:      r,
        idleTimeout: timeout,
        timer:       time.NewTimer(timeout),
    }
}

func (r *idleTimeoutReader) Read(p []byte) (int, error) {
    type readResult struct {
        n   int
        err error
    }
    ch := make(chan readResult, 1)
    go func() {
        n, err := r.reader.Read(p)
        ch <- readResult{n, err}
    }()

    select {
    case res := <-ch:
        if res.n > 0 {
            r.timer.Reset(r.idleTimeout) // reset idle timer on progress
        }
        return res.n, res.err
    case <-r.timer.C:
        return 0, ErrStallTimeout
    }
}
```

**Step 3:** Apply to all four media operations:

In `MediaUpload` (line 201):
```go
// Before:
if _, err := io.Copy(s, progressReader); err != nil {

// After:
idleReader := newIdleTimeoutReader(progressReader, MediaIdleTimeout)
if _, err := io.Copy(s, idleReader); err != nil {
```

In `MediaDownload` (line 256):
```go
// Before:
written, sErr := io.CopyN(f, s, resp.Size)

// After:
idleReader := newIdleTimeoutReader(s, MediaIdleTimeout)
written, sErr := io.CopyN(f, idleReader, resp.Size)
```

Same pattern for `ProfileUpload` (line 358) and `ProfileDownload` (line 408).

**Step 4:** Add constant to `config.go`:

```go
MediaIdleTimeout = 10 * time.Second
```

~40 lines Go: struct + Read method + constant + 4 call site changes.

### Retry Path (no changes needed)

When `io.Copy` returns `ErrStallTimeout`:
- **MediaUpload:** Error propagates to bridge → Dart sees upload failure → existing `upload_pending` retry flow kicks in (`retry_incomplete_uploads_use_case.dart`)
- **MediaDownload:** Error propagates → Dart retries download on next access
- **ProfileUpload:** Error propagates → user retries manually (profile upload is user-initiated)
- **ProfileDownload:** Error propagates → profile shows placeholder, re-fetched later

No new retry logic needed — existing mechanisms handle transient failures.

---

## Implementation Order

| Priority | Item | Effort | Why first |
|---|---|---|---|
| 1 | **§1 `callP2PInboxStore` timeout** | 2 lines Dart | Highest risk (final fallback hangs), trivial fix |
| 2 | **§2 `callP2PRelayProbe` timeout** | 2 lines Dart | Same risk class, trivial fix |
| 3 | **§3 Profile upload progress** | ~10 lines Go | Low risk, reuses existing pattern |
| 4 | **§4 Recovery promise timeout** | ~25 lines Go | Needs design care (gate clearing, late completion) |
| 5 | **§5 Media idle timeout** | ~40 lines Go | Most complex (new wrapper, 4 call sites, goroutine in Read) |

Items 1–2 are Dart-only (no rebuild). Items 3–5 require `make all` + `pod install`.

### Dependencies

- §1 and §2 are fully independent — can ship immediately.
- §3 is independent — can ship with any Go rebuild.
- §4 is independent — existing tests in `relay_session_test.go` provide harness.
- §5 is independent — but should be tested with §3's progress events to verify stall detection interacts correctly with progress emission.
