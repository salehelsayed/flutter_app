# Future Improvements (Out of Scope for UI-14)

## 1. Contact Request Send Path Optimization

The `send_contact_request_use_case.dart` uses the same discover/dial/retry loop as chat messages. It suffers from the same ~24s delay for offline peers. Once the relay probe is implemented for chat, the same pattern should be applied here for consistent UX.

**File:** `lib/features/contact_request/application/send_contact_request_use_case.dart` (line ~162)

## 2. Relay Inbox Durability

The relay server's inbox is **in-memory** — not persisted to disk. A server restart loses all queued messages. There is also no deduplication or idempotency guard, meaning a retry could store the same message twice.

**Files:**
- `go-relay-server/inbox.go` — in-memory map (line ~32), store (line ~173), retrieve (line ~186)

**Improvements needed:**
- Persist inbox to disk (SQLite, BoltDB, or append-only log)
- Add message ID deduplication on store
- Add idempotency key to prevent duplicate delivery on retrieve

## 3. Background Push Handling

When a push notification arrives while the app is backgrounded, the `backgroundMessageHandler` does not drain the inbox immediately. Messages are only surfaced when the user opens the app and `handleAppResumed` triggers an inbox drain.

**Files:**
- `lib/features/push/application/background_message_handler.dart` (line ~12)
- `lib/core/lifecycle/handle_app_resumed.dart` (line ~63)

**Improvement:** Drain inbox in the background handler (requires initializing the bridge and P2P service in isolate, which is non-trivial on iOS).

## 4. Stale WiFi / mDNS Entries

Bonsoir mDNS peer entries can become stale if a peer leaves the WiFi network without a clean goodbye. The WiFi send path has a 5-second ack timeout in `LocalWsServer`, so a stale entry wastes up to 5 seconds before falling through. Could be improved with shorter WiFi timeouts or periodic mDNS entry validation.

**File:** `lib/core/local_discovery/local_ws_server.dart` (line ~207 — ack timeout)
