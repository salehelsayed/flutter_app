Your understanding is almost correct. Let me clarify:

  Step 1: WiFi check — Is peer on local WiFi (Bonsoir)? If yes, send via WebSocket.

  Step 2: Fast path — Does libp2p connection manager have an active connection? If yes, send on it with 1s timeout. If stale,
   fails fast → falls through.

  Step 3: Relay probe — Dials the peer through the relay circuit address only. Three outcomes:
  - connected → relay circuit established, peer is online → send on that new connection
  - noReservation → peer is definitely offline → skip to inbox
  - error → unknown → fall through to step 4

  Step 4: Discover + dial — Single attempt. Discovers peer addresses via rendezvous (up to 9 addresses), dials all of them.
  This is the expensive path (5-10s if peer is offline).

  Step 5: Inbox — Store message on relay server for later pickup.





noReservation is a definitive answer from the relay server: "I know this peer, they have no active reservation." That's different from "I couldn't reach the relay server at all."


 Flowchart:

  User-A hits SEND
          │
          ▼
  ┌─────────────────┐
  │ Encrypt message  │
  └────────┬────────┘
           │
           ▼
  ┌─────────────────────────┐     YES    ┌──────────────────┐
  │ Bonsoir: isLocalPeer()?  ├──────────►│ Send via WebSocket │
  └────────┬────────────────┘            │ (WiFi, ~ms)       │
           │ NO                          └────────┬──────────┘
           │                              (don't return — fall through
           │                               for relay confirmation)
           ▼                                      │
  ┌──────────────────────────────┐                │
  │ libp2p: isConnectedToPeer()? │◄───────────────┘
  └────────┬─────────────────────┘
           │
      YES  │                    NO
           ▼                    │
  ┌─────────────────────┐       │
  │ FAST PATH            │       │
  │ sendMessageWithReply │       │
  │ timeoutMs: 1000      │       │
  └────────┬────────────┘       │
           │                    │
      ┌────┴────┐               │
      │         │               │
    ACK'd    timeout/fail       │
      │         │               │
      ▼         ▼               │
   DELIVERED  (fall through)    │
               │                │
               ▼◄───────────────┘
  ┌──────────────────────────────┐
  │ RELAY PROBE                   │
  │ DialPeerViaRelay (5s timeout) │
  │ Tries ONLY relay circuit addr │
  └────────┬──────────────────────┘
           │
      ┌────┼──────────────┐
      │    │              │
  connected  noReservation   error
      │         │              │
      ▼         │              │
  ┌────────┐   │              │
  │ Send on │   │              │
  │ relay   │   │              │
  │ conn    │   │              │
  └───┬────┘   │              │
      │        │              │
    ACK'd?     │              ▼
    yes→DONE   │    ┌──────────────────────┐
    no/fail    │    │ DISCOVER + DIAL       │
      │        │    │ Rendezvous lookup     │
      ▼        │    │ → up to 9 addrs       │
   (fall       │    │ PeerDialTimeout: 5s   │
    through)   │    │ Single attempt        │
      │        │    └───────┬──────────────┘
      │        │            │
      │        │       success → Send → ACK'd? → DONE
      │        │       fail ──┐
      │        │              │
      ▼        ▼              ▼
  ┌──────────────────────────────┐
  │ INBOX FALLBACK                │
  │ storeInInbox (~50-280ms)      │
  │ Relay server holds message    │
  │ for pickup                    │
  └───────────┬──────────────────┘
              │
         success → DELIVERED (via inbox)
         fail   → FAILED (save with wireEnvelope for retry)

  Use cases:

  Scenario: Both on same WiFi
  Path taken: WiFi send → fast path ACK
  Time: ~ms
  ────────────────────────────────────────
  Scenario: Both online, active connection
  Path taken: Fast path → ACK
  Time: ~ms
  ────────────────────────────────────────
  Scenario: Both online, stale connection
  Path taken: Fast path timeout 1s → relay probe connected → send → ACK
  Time: ~1.5s
  ────────────────────────────────────────
  Scenario: Both online, no connection yet (first add)
  Path taken: Relay probe connected → send → ACK
  Time: ~500ms
  ────────────────────────────────────────
  Scenario: Recipient offline
  Path taken: Relay probe noReservation → inbox
  Time: ~800ms
  ────────────────────────────────────────
  Scenario: Relay server unreachable
  Path taken: Relay probe error → discover+dial (fails) → inbox
  Time: ~5-10s
  ────────────────────────────────────────
  Scenario: Recipient offline + relay down
  Path taken: Relay probe error → discover+dial (fails) → inbox fails → FAILED
  Time: ~5-10s


sending to an offline peer takes ~15-24s (3 dial attempts) before reaching inbox