

in the case of 2 users exchanging contacts via QR , but there is not network at all.This is what will happen.


  QR Exchange With No Network

  Setup: User-A scans User-B's QR code. No WiFi, no cellular, no relay.

  What succeeds (local-only)

  - QR scan itself works — it's camera-based, no network needed
  - User-A adds User-B as a local contact from the QR payload, but with mlKemPublicKey: null (QR deliberately omits it)

  What fails

  sendContactRequest() tries to deliver User-A's identity + ML-KEM key to User-B:

  1. isLocalPeer() → false (no WiFi peers)
  2. discoverPeer() → null × 3 attempts (can't reach relay)
  3. storeInInbox() → fails (can't reach relay server)
  4. Result: sendFailed — the message is dropped

  Consequences

  ┌────────────────────┬─────────────────────────┬─────────────────────────────────────────┐
  │                    │      User-A's view      │              User-B's view              │
  ├────────────────────┼─────────────────────────┼─────────────────────────────────────────┤
  │ Has contact?       │ Yes (from QR)           │ No — never received the contact_request │
  ├────────────────────┼─────────────────────────┼─────────────────────────────────────────┤
  │ Has ML-KEM key?    │ No (null)               │ N/A                                     │
  ├────────────────────┼─────────────────────────┼─────────────────────────────────────────┤
  │ Can send messages? │ No — encryptionRequired │ Doesn't even know User-A exists         │
  └────────────────────┴─────────────────────────┴─────────────────────────────────────────┘

  The gap

  There is no persistent retry or outbox. sendContactRequest does 3 immediate retries with exponential backoff (~3 seconds
  total), then tries inbox, then gives up permanently. Once it returns sendFailed, that message is gone. When network
  eventually comes back, nothing re-triggers the send.

  So User-A is stuck with an unusable contact — they can see User-B in their feed/orbit, but every message attempt fails with
   the encryption error, and there's no automatic recovery path.

  The same gap exists in the reciprocal path (our new acceptAndReciprocateContactRequest) — if User-B accepts while offline,
  the reciprocal send also fails silently, leaving User-A permanently without User-B's ML-KEM key.


⏺ The Problem

  sendContactRequest is fire-and-forget with ~3 seconds of retries. If all fail, the message is gone forever. There's no
  persistent record that a send was attempted and failed.

  Suggested Fix: Opportunistic re-send at startup

  The key insight is that the contacts table already acts as an implicit outbox. Any contact with mlKemPublicKey: null
  represents an incomplete key exchange — either our send failed, or their reciprocal hasn't arrived yet. In both cases,
  re-sending our contact_request is the right move.

  The mechanism:

  After the P2P node starts (in main.dart, where we already do drainOfflineInbox), scan the contacts table for any contact
  where mlKemPublicKey is null. For each, fire-and-forget sendContactRequest(). That's it.

  Why this works:

  - sendContactRequest is already idempotent — handleIncomingMessage on the receiver gracefully handles duplicates
  (duplicateRequest if pending, contactKeyUpdated if already a contact)
  - Covers both failure modes: User-A's initial send failed, and User-B's reciprocal failed
  - By the time we have a contact row, we've always already attempted a send, so re-sending is always appropriate (pending
  requests live in the contact_requests table, not contacts)
  - Once the exchange completes and both sides have each other's ML-KEM key, mlKemPublicKey becomes non-null and the contact
  drops out of the retry set naturally

  What it doesn't need:

  - No new DB table or migration (contacts table is the queue)
  - No background worker or network listener
  - No outbox/dequeue/cleanup logic
  - No new columns or flags

  The trigger: Right after node start, same place as drainOfflineInbox. Something like a retryIncompleteKeyExchanges()
  function that queries contacts with null ML-KEM key and sends to each.
  ----




❯ orchestrate multiple agents to run in parallel or sequence to create that deatiled plan.   make sure our plan incudle sufficient integration test, unit tests, smoke tests ... all kind of needed test for a robust implementationbut take into consderation that
  following:

    What I’d tighten before shipping:

  1. Trigger point

  - Don’t hook this in generic main.dart; hook after successful node start (and optionally on resume/online transition).
    Startup-only means no recovery if network returns while app stays open.

  2. Retry set filter

  - mlKemPublicKey == null is a good heuristic, but skip blocked contacts at minimum (auto-sending to blocked peers is
    wrong).

  3. Guard on own key

  - If our own ML-KEM key is missing, resends are pointless (they won’t include mlkem), so skip and log.

  4. Avoid startup burst

  - Send sequentially (or with small bounded concurrency), with a small jitter, so a large null-key set doesn’t hammer
    startup/network.





