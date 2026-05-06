# Session N — sim-side noises observed during 2026-05-05 hardware soak

Carved out of
[`lock-window-fix-followups-tdd-plan-2026-05-04.md`](./lock-window-fix-followups-tdd-plan-2026-05-04.md)
final-program-verdict `closed` on 2026-05-05.

These two log signatures appeared in the Pixel + 2 iOS-sim soak run that
verified the Android `MainActivity.onNewIntent` fix. They are **not** related
to that fix (the tap path was clean), but they were unfamiliar enough during
log review that they warrant their own session to either confirm-as-expected
or root-cause. Both are sim-only as observed; either may behave differently
on real iOS hardware, and one of the two (relay `NO_RESERVATION`) could be
a real production-relay capacity issue surfaced by chance.

Soak evidence files referenced below were on `/tmp/...` at capture time; they
will not survive a reboot. Re-run the soak in this session to regenerate
unless the symptoms can be reproduced from a clean local repro recipe.

Branch under test during original soak: `new-background` (commits
`5fec83b3` + the orchestrator's MainActivity edit, debug build, fresh
install on all 3 devices).

---

## Item 1 — iOS-sim push-token registration error

### Symptom

Both iOS sims emitted exactly one `P2P_SERVICE_REGISTER_PUSH_TOKEN_ERROR`
flow event during M1 startup, immediately after the Go bridge initialised
and the existing push token was restored from secure storage.

```
flutter: [FLOW] {"event":"P2P_SERVICE_PUSH_TOKEN_RESTORED","details":{"platform":"ios"}}
flutter: [FLOW] {"event":"P2P_SERVICE_REGISTER_PUSH_TOKEN_ERROR","details":{"platform":"ios"}}
```

- Sim A (`347FB118…` iPhone Air): emit at 10:56:25.429 UTC.
- Sim B (`5BA69F1C…` iPhone 17): emit at 10:57:12.031 UTC.
- The `details` payload was the redacted form, so the actual `errorMessage`
  field (if any) is not in the captured log.
- No follow-up retries observed; no later `…REGISTER_PUSH_TOKEN_SUCCESS`
  events. The error is one-shot per app launch.

### Why it is probably benign on simulator

Apple's iOS Simulator (until very recent macOS / Xcode combinations with
limited APNS-via-sandbox plumbing) does not deliver real APNs device tokens
to apps. `UIApplication.registerForRemoteNotifications()` either calls
`didFailToRegisterForRemoteNotificationsWithError:` or hands back a fake /
empty token. Any app code that tries to POST that token to a relay /
push-server would predictably error.

### What is unknown / why this needs a session

We do **not** know from the captured logs:

1. Whether the error is the simulator-APNS limitation above (expected,
   ignore on sim, succeeds on hardware) or something else (e.g., relay
   reachability, identity-not-yet-registered race, etc.).
2. Whether real iPhone hardware reproduces it (the orchestrator soak only
   used sims as senders).
3. Whether the rest of the app degrades gracefully when register-push-token
   fails — i.e., does the user still receive messages over P2P / mDNS / relay
   even though the push leg is dead?
4. Whether this error has been silently present on every TestFlight build
   to date and we just haven't grepped for it.

### Suggested session shape (when picked up)

**Diagnose first, fix only if needed.** This is a "is this expected?"
session, not a "this is broken, write the fix" session.

1. Read `lib/...` for the registration call path. Likely entry is
   `P2PService.registerPushToken` or similar; trace to the exact failure
   site that emits the FLOW event and log the actual error string at that
   site (one-line addition, not a refactor).
2. Re-run the soak with the same fresh-install recipe but use **a real
   iPhone** in addition to the sims. Compare:
   - Does the real iPhone emit `…REGISTER_PUSH_TOKEN_SUCCESS` instead?
   - Does the sim-error string explicitly say "simulator does not support
     remote notifications" or similar (in which case: confirm-as-expected,
     close the loop)?
3. If real hardware also errors, this becomes a real bug → spawn a fix
   session at that point. Otherwise: add a debug-only `[FLOW]` field
   noting `simulator=true` so future log readers know to ignore it on sim.

### Verification

- The decision recorded in this artifact must be one of:
  - `confirmed-simulator-only — production-real-hardware-OK` (most likely).
  - `real-bug — separate-fix-session-spawned` (link the new session here).
- If the former: append a one-liner to the project's "expected sim noises"
  list (search the repo for prior such lists; if none, this artifact
  itself becomes the index entry).

### Pointers

- Flow-event emit site: grep
  `lib/ -rn "P2P_SERVICE_REGISTER_PUSH_TOKEN_ERROR"` to find the catch
  block that emits this string.
- Push-token storage: see `SecureKeyStore` in
  `lib/core/secure_storage/secure_key_store.dart` — token is restored from
  there at boot per the `P2P_SERVICE_PUSH_TOKEN_RESTORED` event right
  before the failure.

---

## Item 2 — Sim-B relay `NO_RESERVATION (204)` across all candidates + `LOCAL_WS_SEND_TIMEOUT`

### Symptom

Sim B (`5BA69F1C…` iPhone 17) was unable to dial a specific peer through
**any** of its 5 GossipSub-relay circuit candidates. The full event
sequence at 10:59:55–10:59:56 UTC:

```
flutter: [FLOW] P2P_SERVICE_DIAL_PEER_ERROR — failed to dial 12D3KooWB97exzEinFaKwaG2KtavbabjkQ4rcfCBLTqKRg2vBMGo:
  all dials failed
    * [redacted:multiaddr] error opening relay circuit: NO_RESERVATION (204)
    * [redacted:multiaddr] error opening relay circuit: NO_RESERVATION (204)
    * [redacted:multiaddr] error opening relay circuit: NO_RESERVATION (204)
    * [redacted:multiaddr] error opening relay circuit: NO_RESERVATION (204)
    * [redacted:multiaddr] concurrent active dial through the same relay failed with a protocol error
flutter: [FLOW] LOCAL_WS_SEND_TIMEOUT — to=12D3KooWB97exz… error=TimeoutException(0:00:01.499734)
flutter: [FLOW] P2P_RELAY_PROBE_RESPONSE — ok=false errorCode=RELAY_PROBE_ERROR
```

Five circuit-relay attempts: the first four all returned libp2p reservation
error code `204 (NO_RESERVATION)`; the fifth was a "concurrent active dial
through the same relay failed with a protocol error" (the libp2p stack
detecting it had already attempted the same target through that relay).

This was **not** observed on sim A or on the Pixel during the same soak
window, so it is not a global outage — it is target-peer-specific or
sim-B-specific.

### Why this is the more interesting of the two items

`NO_RESERVATION (204)` is a real libp2p signal: the relay node has either
(a) refused to accept a reservation from the source for this dial, or
(b) the reservation expired between issuing and attempting to use it. It
is **not** a simulator-only artifact. Possible production causes:

1. Relay-server reservation TTL expired and was not refreshed (could be a
   client-side reservation-renewal bug in
   `groupPeerDiscoveryLoop` / circuit-relay refresh code).
2. The target peer (`12D3KooWB97exz…`) is not actually announced through
   any of the relays sim-B tried (stale rendezvous data).
3. The 5 relay candidates returned by discovery were exhausted /
   over-subscribed at that moment (`NO_RESERVATION` happens when the relay
   node has hit its per-source reservation cap).
4. A protocol mismatch between client and relay versions causing the
   reservation handshake to silently bottom out at 204.

The follow-on `LOCAL_WS_SEND_TIMEOUT` and `RELAY_PROBE_ERROR` are
downstream symptoms of the same root failure, not independent issues.

### Why it did not affect the Android tap-fix soak

The notification-tap fix is purely about Android-side intent forwarding;
GossipSub relay reachability is only relevant for **delivering** group
messages, which was not the path under test. The tap soak never got to
the point of needing sim-B → group-publish → Pixel-receive over relay
because the test exercised 1:1 chat notifications instead. This is why
the `closed` verdict on the parent artifact is unaffected — but the
relay symptom was visible in the same logs and is worth its own diagnosis.

### What is unknown / why this needs a session

1. **Reproducibility.** Was this a one-shot failure (relay-side hiccup)
   or does it repeat every time sim B tries to reach this peer / any peer?
2. **Reservation-refresh state on sim B at the moment of failure.** The
   `groupPeerDiscoveryLoop` (per project memory) re-registers every 30s;
   was sim B in the gap between two registration cycles when the dial
   was attempted?
3. **Relay capacity vs. target unreachable.** `NO_RESERVATION` ambiguates
   between "I don't have you reserved" and "I have you reserved but the
   target isn't reachable through me right now". A debug log on the
   relay binary side or a deeper Go-bridge log would disambiguate.
4. **Real hardware behaviour.** Same as Item 1 — does this reproduce
   on real iOS hardware, or is the simulator's network stack subtly
   biasing relay selection?

### Suggested session shape (when picked up)

This is a **bug-investigation** session; assume there is something real
to fix until proven otherwise.

1. Re-run the soak with all 3 devices fresh (Pixel + 2 sims) and **drive
   group messaging specifically** so sim B has to dial group peers via
   relay. Capture the full Go-bridge `[FLOW]` event stream on sim B
   plus, if accessible, the relay-binary's logs from the same window.
2. Narrow down: does `NO_RESERVATION` occur on first-dial after a fresh
   `groupPeerDiscoveryLoop` cycle (suggests relay side-state) or only
   when the loop has already cycled (suggests reservation TTL)?
3. Check the existing `rejoinGroupTopics` use case (per project memory)
   — does it re-establish reservations on app resume, or only rejoin
   topics? If the latter, that gap may be the bug.
4. Cross-reference with any already-open follow-ups in
   `Test-Flight-Improv/Group-Chat-Feature/` that touch relay / circuit
   reservation — there may be related work in flight.

### Verification

- A reproducible recipe that produces `NO_RESERVATION (204)` (or a
  recorded inability to reproduce after N runs).
- One of:
  - `flaky-relay-side — no client fix needed` (low confidence; only
    accept after evidence).
  - `client-side-reservation-bug — fix-session-spawned` (high
    confidence path; link the spawn here).
  - `target-peer-unreachable — discovery / rendezvous TTL bug` (likely
    on a feature gap rather than a mainline bug).

### Pointers

- Flow-event emit sites:
  - `lib/...` grep `P2P_SERVICE_DIAL_PEER_ERROR`,
    `LOCAL_WS_SEND_TIMEOUT`, `P2P_RELAY_PROBE_RESPONSE` /
    `RELAY_PROBE_ERROR`.
- Go-side relay circuit code: `go-mknoon/` — search for `NO_RESERVATION`
  / `204` / `Reservation`.
- Group discovery loop (per project memory): `groupPeerDiscoveryLoop`
  registers/discovers on `/mknoon/group/<groupId>` every 30s and dials
  via `DialPeerViaRelay`.

---

## Cosmetic note (not a session — just record it)

Both `NOTIFICATION_TAP_TO_MESSAGE_TIMING` events on the Pixel during the
soak had `messageId:""`:

```
{"event":"NOTIFICATION_TAP_TO_MESSAGE_TIMING","details":{"elapsedMs":573,"routeKind":"conversation","messageId":""}}
{"event":"NOTIFICATION_TAP_TO_MESSAGE_TIMING","details":{"elapsedMs":442,"routeKind":"conversation","messageId":""}}
```

The notification payload only carried the peer id
(`12D3KooWEr6zD84YKvyzwf98R28q4tRk`), so the route opens the conversation
without a specific message anchor. This is consistent with per-peer 1:1
chat notifications (no need to deep-link to a specific message inside
the thread). If the field is meant to be populated for some notification
kinds and not others, current behaviour is correct; if it is meant to
always carry the most-recent unread `messageId`, this is a minor missing
field. Resolve as part of whichever session next touches
`NOTIFICATION_TAP_TO_MESSAGE_TIMING` emit code — do not spawn a session
just for this.

Pointer: search `lib/` for `NOTIFICATION_TAP_TO_MESSAGE_TIMING` to find
the emit site.

---

## Out of scope for this artifact

- Android `EPERM` / `netlink_route_socket` AVC denials (Google bug
  `b/155595000`) observed on the Pixel during the same soak. These are a
  long-standing kernel SELinux rule preventing libp2p from enumerating
  local interface addresses; they are not a session-worthy follow-up
  because they are an OS-level constraint, not application logic. The
  app already degrades gracefully (interface enumeration is
  best-effort).
- The notification-tap fix itself — `closed` on the parent artifact.
