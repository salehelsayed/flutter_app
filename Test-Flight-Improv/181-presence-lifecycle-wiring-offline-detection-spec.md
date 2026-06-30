# 181 - Presence lifecycle wiring: backgrounded peers never announce "background", so the send-side offline short-circuit is permanently dormant  (Bug — Spec)

**Bug** (latent integration gap: a committed, tested send-side consumer was shipped expecting a presence *producer* that was never connected to the app lifecycle).

Status: awaiting-review (spec only — no implementation).

---

## Problem Statement

The app has a complete, host-tested **presence self-publish** stack (FDC-08 read side + FDC-09 write side) whose entire purpose is to let the relay tell a *sender* whether a target peer is currently reachable, so the sender can route an offline-bound 1:1 message straight to durable custody instead of waiting for every live transport leg to time out. **Every layer of that stack is implemented and wired — except the one trigger that makes it run.**

- The **write-side lifecycle driver** `SetPresenceUseCase` (`lib/features/push/application/set_presence_use_case.dart`) is fully built and unit-tested, but it is **referenced nowhere in production code** — only in its own file and its own test. Nothing ever calls `onForegrounded()` or `onBackgrounded()`, and nothing constructs it. It is dead code in the shipped app.
- Because no peer ever publishes its `foreground`/`background` state, the relay's presence store never has a fresh self-published entry to key on. Its `Lookup` ladder therefore never returns the `unreachable` verdict that a backgrounded peer is supposed to produce — it falls through to the connectedness/last-seen rungs, which for a recently-seen peer return `reachable` (TTL-lagged for up to 180 s) or `unknown`.
- The **send-side consumer** that was built to act on `unreachable` (`lib/features/conversation/application/send_chat_message_use_case.dart`, committed `a32454c2`) is consequently **permanently dormant**. Its `unreachable → commit-to-inbox-first` short-circuit can fire only when the relay literally returns `unreachable`, which — with no producer — never happens.

**Current behavior.** When a user sends a 1:1 text message to a peer the sender has no live connection to, and that peer is backgrounded/offline, the send runs the full transport race (LAN + direct, and a relay-live leg if a circuit exists). With the peer unreachable, those legs all fail and the message falls to the durable inbox only **after the race times out** — on the order of ~1.9 s — with no early signal that the peer is known to be away and no early trigger of the relay's store-driven push-to-wake.

**What is wrong.** A shipped, tested capability (announce-then-detect offline peers) does nothing in production because a single lifecycle wiring was deliberately deferred (per the FDC-09 implementation memo, 2026-06-27) and never completed. The user-visible result is that sends to known-away peers feel slow, and the offline-detection / push-to-wake path the consumer was designed to drive is never exercised.

**Who is affected.** All users sending 1:1 text to a backgrounded or offline contact **that the sender does not already hold a live connection to** (see the explicit scope boundary below — a sender holding even a stale relay circuit to the target is a separate, out-of-scope case). Both platforms.

**Conditions.** Manifests whenever `unknownPresence` is true for a 1:1 send (sender has no live/local connection to the target) and the target is backgrounded/offline. It does **not** manifest for connected or same-LAN peers (delivered live on the fast path) and does **not** manifest for the specific stale-circuit case described under Scope.

### Device evidence (this session, Pixel 6 → iPhone 11, recipient Wi-Fi off)

A Wi-Fi-off 1:1 text send was captured end-to-end:

```
CHAT_MSG_SEND_START
CHAT_MSG_SEND_LAN_ACK { kind: "failed" }
CHAT_MSG_SEND_RACE_ALL_FAILED { reason: "direct_timeout" }   (~1744 ms after start)
CHAT_MSG_SEND_SUCCESS { via: "inbox" }
CHAT_MSG_SEND_TIMING { elapsedMs: 1910, sendPath: "inbox" }
```

No `CHAT_MSG_PRESENCE_EMPHASIS` and no `CHAT_MSG_PRESENCE_INBOX_FIRST` were logged for this send. `CHAT_MSG_PRESENCE_EMPHASIS` is emitted *unconditionally* inside the presence block, so its absence proves the block was skipped — i.e. `unknownPresence` was **false** on that send (the sender held a relay `/p2p-circuit` to the recipient's peerId). This device run is therefore **out of scope for two independent reasons** (see Scope): **(A)** the sender's stale `/p2p-circuit` bypassed the presence block, and **(B)** the recipient was Wi-Fi-off, so it had no network to publish `background` and the relay could never have returned `unreachable` regardless. It is recorded here as the motivating observation and as a falsifiable negative anchor, **not** as a case this fix changes — and fixing reason A alone would not fix it, because reason B still holds.

---

## Impact Analysis

| Dimension | Detail |
|---|---|
| Severity | Degraded experience + a fully-built capability inert. Not data loss — durable inbox + push remain the unconditional delivery guarantee. |
| Frequency | Every 1:1 text send to a backgrounded/offline peer the sender has no live connection to. |
| User-visible consequence | Send to a known-away peer takes ~1.9 s (full race timeout) to settle to "delivered to inbox" instead of committing immediately; the relay's store-driven push-to-wake is not front-loaded. |
| Latent-capability cost | The FDC-08/09 read+write stack and the committed send-side short-circuit produce zero behavior in production; no telemetry (`CHAT_MSG_PRESENCE_INBOX_FIRST`, `PRESENCE_SELF_PUBLISH`) is ever emitted. |
| Workaround | None user-facing. |
| Platforms | iOS and Android (lifecycle observer is shared). |

Latency comparison for an offline-bound, no-live-connection 1:1 text send:

| Scenario | Today (no producer) | With presence producer wired |
|---|---|---|
| Target backgrounded, relay returns `unreachable` | Settles to inbox after full race timeout (~1.9 s observed) | Existing consumer commits the durable copy first, then runs live legs best-effort (no second relay write); push-to-wake front-loaded |
| Target reachable / same-LAN / connected | Unchanged (fast path) | Unchanged (fast path) |
| Relay old / lookup error / move paused | Degrades to `unknown` → today's fully-concurrent behavior | Same (`unknown` degrade unchanged) |

---

## Current State

Factual inventory of what exists today. All paths verified first-hand against the working tree (clean for these files).

### Write side — the producer (built, **unwired**)

| Element | Location | Current state |
|---|---|---|
| `SetPresenceUseCase` | `lib/features/push/application/set_presence_use_case.dart:24-101` | Built + unit-tested. `onForegrounded()` (:51) publishes `'foreground'` then arms a 60 s heartbeat; `onBackgrounded()` (:62) cancels the heartbeat and fires an **unawaited** best-effort `'background'` publish; `dispose()` (:68) cancels the heartbeat. Emits `PRESENCE_SELF_PUBLISH` (:73). |
| State vocabulary | `set_presence_use_case.dart:53,64` | Exactly two coarse strings: `'foreground'` / `'background'`. No `reachable`/`unreachable`/`online` on the client. |
| Self-TTL / heartbeat consts | `set_presence_use_case.dart:42-43` | `kPresenceSelfTtl = 180 s`; `kPresenceForegroundHeartbeat = 60 s` (< TTL, so a missed beat does not expire the entry). |
| Production references | grep across `lib/` and `test/` | Only its own definition file and `test/features/push/application/set_presence_use_case_test.dart`. **No constructor call, no lifecycle call anywhere in `lib/`.** |
| `RelayPresenceSet` interface | `lib/core/services/p2p_service.dart:94-101` | `abstract interface class RelayPresenceSet { Future<PresenceSetResult> setPresence(String state, int ttlMs); }`. Deliberately kept **off** the base `P2PService` interface so the ~31 `P2PService` fakes need not grow it. |
| `PresenceSetResult` | `p2p_service.dart:81` | `enum PresenceSetResult { published, unsupported, blocked, failed }`. |
| `P2PServiceImpl.setPresence` | `lib/core/services/p2p_service_impl.dart:4879-4923` | Implements `RelayPresenceSet`. First line move-gates on `_allowsAccountNetworkSideEffects('p2p_set_presence')` (:4887) → returns `blocked` while an account move paused network side-effects. Degrades an old relay to `unsupported`. Never throws (catch → `failed`). |
| Bridge command | `lib/core/bridge/p2p_bridge_client.dart` → `callP2PRelayPresenceSet` | Sends `{ 'cmd': 'relay:presence_set', 'payload': { 'state': state, 'ttlMs': ttlMs } }`. **No peerId** in the payload. |
| Bridge cmd→method map | `lib/core/bridge/go_bridge_client.dart:133` | `'relay:presence_set' → _CmdSpec('relayPresenceSet', true)` (and `:128` `relay:presence_get → relayPresenceGet`). |
| Native dispatch (iOS) | `ios/Runner/GoBridge.swift:129-133` | `case "relayPresenceSet": BridgePresenceSet(args)` (and `relayPresenceGet → BridgePresenceGet`). **Present in committed source** — the 2026-06-27 "absent until gomobile rebuild" caveat is stale. |
| Native dispatch (Android) | `android/app/src/main/kotlin/com/mknoon/app/GoBridge.kt:118-120` | `"relayPresenceSet" -> GoMknoon.presenceSet(args)` (and `relayPresenceGet -> GoMknoon.presenceGet`). |
| Go bridge entry | `go-mknoon/bridge/bridge_presence.go:78` | `func PresenceSet(paramsJSON string)` validates state ∈ {`foreground`,`background`}, calls node `RelayPresenceSet`. |

### Relay side — the resolver (built, exercised only by the unit suite)

| Element | Location | Current state |
|---|---|---|
| Self-state field | `go-relay-server/presence_store.go:40` | `selfState string // "" | "foreground" | "background"`, with `selfPublishedAt` + `selfTTL`. |
| `SetSelfPublished` | `presence_store.go:100-108` | Records `selfState`, `selfPublishedAt = now`, `selfTTL`. |
| `Lookup` ladder | `presence_store.go:122-177` | **Rule 1** (`:149`): fresh self-state wins — `foreground → reachable`, `background → unreachable` (only while `now - selfPublishedAt < selfTTL`). Then live socket → reachable; fresh last-seen (< TTL) → reachable; stale last-seen (≥ TTL) → **unknown** (not unreachable); never-seen → unreachable. |
| TTL | `presence_store.go:28` | `relayPresenceTTL = 180 s`. |
| `presence_set` handler | `go-relay-server/inbox.go:1789, 1843` | `handlePresenceSet` validates state, clamps TTL to `maxPresenceSelfTTL = 10 min` (`:1827`), calls `SetSelfPublished`. Old relays answer "Unknown action: presence_set" → client degrades to `unsupported`. |

### Read side — the consumer (committed `a32454c2`, **inert**)

| Element | Location | Current state |
|---|---|---|
| `unknownPresence` gate | `send_chat_message_use_case.dart:704-707` | `!isAlreadyConnected && !isLocalPeer && !p2pService.isConnectedToPeer(targetPeerId)`. The entire presence block is inside `if (unknownPresence)` (`:718`). |
| Concurrent durable inbox | `send_chat_message_use_case.dart:727-737` | Fires for **every** `unknownPresence` send, regardless of presence value — custody is unconditional (`PRESENCE_NEVER_REPLACES_INBOX`). |
| Presence lookup | `send_chat_message_use_case.dart:747-758` | `is RelayPresenceLookup` cast → `lookupRelayPresence(targetPeerId)` bounded by `_presenceHintBudget = 400 ms`, degrading to `RelayPresence.unknown` on timeout. |
| `CHAT_MSG_PRESENCE_EMPHASIS` | `send_chat_message_use_case.dart:759-767` | Emitted **unconditionally** for every presence value (including `unknown`). |
| Short-circuit | `send_chat_message_use_case.dart:776-783` | `if (presenceEmphasis == RelayPresence.unreachable)` → emit `CHAT_MSG_PRESENCE_INBOX_FIRST` and `await concurrentInbox` (commit the durable copy first). Live legs still run afterwards (`:795+`), never dropped. |
| `lookupRelayPresence` | `p2p_service_impl.dart:4831-4865` | Calls `relay:presence_get`; returns `enum RelayPresence { reachable, unreachable, unknown }` (`p2p_service.dart:56`). `unreachable` is produced **only** when the relay returns the literal `unreachable`; every error/old-relay/move-paused/unparsed value degrades to `unknown`. |

### Lifecycle host — the injection point

| Element | Location | Current state |
|---|---|---|
| Central observer | `lib/main.dart:3611` | `_MyAppState extends State<MyApp> with WidgetsBindingObserver`; `addObserver(this)` at `:3640`, `removeObserver(this)` at `:4328`, `dispose()` at `:4327`. |
| Edge dispatch | `main.dart:4370-4401` | `didChangeAppLifecycleState`: `resumed → _onResumed()` (`:4380/4478`); `paused || hidden → _onPaused()` (`:4388/4414`); `detached → _onDetached()` (`:4398/4403`, teardown only — intentionally not on paused/hidden). |
| `_onPaused` | `main.dart:4414-4476` | Fire-and-forget; runs FDC-06 `handleAppPaused` (`enablePauseFlush: kFdcPauseFlushEnabled`). |
| `_onResumed` | `main.dart:4478+` | Reentry-guarded (`_isResuming`); awaits `handleAppResumed`, alongside existing **unawaited** warm-peer / drain re-prime. |
| Pause-flush bg window | `lib/core/lifecycle/handle_app_paused.dart:128,141` | `callBgBegin(bridge)` acquires the iOS `beginBackgroundTask` assertion **inside** the in-flight-send flush; `callBgEnd` releases it. The assertion is **not** taken when there are no in-flight sends to flush. |
| Unrelated subsystem | `lib/main.dart` (`PostPresenceListener`, `ContactPresenceSnapshotRepository`, `publishPostPresenceUpdate`) | The posts **location**-presence feature. Distinct from relay foreground/background presence. Must not be conflated or touched. |

### Why the producer was never wired

The FDC-09 implementation record (2026-06-27) explicitly deferred the "live wiring" (no `main.dart` construction, no `handle_app_resumed`/`handle_app_paused` hooks), host-green only, partly because the native MethodChannel dispatch was believed absent pending a gomobile rebuild. That native dispatch is now present in committed `GoBridge.swift`/`GoBridge.kt` (verified above), so the only remaining gap is the Dart lifecycle wiring.

---

## Scope Clarification

| Area | Status | Note |
|---|---|---|
| Lifecycle wiring of `SetPresenceUseCase` (`onForegrounded`/`onBackgrounded`/`dispose`) into the existing `_MyAppState` observer | **In scope** | The whole of this spec. |
| Construction of the use case from the existing concrete `P2PServiceImpl` | **In scope** | Must not require a new `P2PService` interface method. |
| Best-effort background publish (no dedicated background-task assertion) | **In scope (as the chosen behavior)** | Keep `onBackgrounded()`'s existing unawaited fire-and-forget. Must not block or widen the FDC-06 pause window. |
| The write transport (`setPresence` → bridge → native → Go → relay) | **Out of scope — unchanged** | Already built + tested. |
| The relay `Lookup` ladder and `handlePresenceSet` | **Out of scope — unchanged** | Already built + tested. |
| The send-side consumer / `unreachable` short-circuit | **Out of scope — unchanged** | Already committed; this spec only makes it *fire* by supplying a producer. |
| The account-move gate (`'p2p_set_presence'`) | **Out of scope — must remain** | A paused/migrating device must continue to not announce presence. |
| Presence payload shape (`{state, ttlMs}`, no peerId) | **Out of scope — unchanged** | Anti-spoof: relay binds to the authenticated stream identity. |
| Posts location-presence subsystem | **Out of scope — must not touch** | Unrelated feature. |
| **Stale-circuit-connected sends (`unknownPresence == false` because the sender holds even a stale `/p2p-circuit` to the target)** | **Out of scope — known limitation / follow-up (reason A)** | The presence block is bypassed whenever `isAlreadyConnected` or `isConnectedToPeer` is true. This is one reason the device evidence above is out of scope. Wiring presence does **not** change it; a separate fix (e.g. treating a circuit-only connection as not-truly-connected) would be required and is tracked separately. |
| **No-network / radio-off peers (the peer lost or never had network at/after pause time)** | **Out of scope — separate follow-up (reason B, independent of reason A)** | This mechanism announces `background` from the peer **only if the peer still has network at pause time** to reach the relay. A peer that is genuinely offline (Wi-Fi/radio off) — like the originally-observed device case — **cannot publish `background`**, so the relay returns `reachable` (TTL-lagged < 180 s) or `unknown`, **never `unreachable`**. Therefore the in-scope target is precisely *app-backgrounded-with-network-at-pause-time*, **not** *offline*. Detecting a peer that loses network while foregrounded (or after its announce-TTL lapses) requires **relay-side connection-drop detection** and is a genuinely separate follow-up. ⚠️ Reasons A and B are independent: fixing the circuit classification (reason A) alone would still **not** resolve the observed Wi-Fi-off report, because reason B still holds. |
| Reliable background flip on transient backgrounds (app-switcher / lock / control center with no in-flight sends) | **Out of scope — accepted limitation (two-sided)** | (i) *Publish lost:* a transient background may lose the `'background'` publish; the entry then lapses to `unknown` after the ~180 s self-TTL rather than flipping promptly to `unreachable`. (ii) *Publish briefly succeeds:* a transient background whose publish **does** land marks the peer `unreachable` until re-foreground re-publishes `foreground` — a short window in which senders **front-load the inbox await** (~the inbox-commit latency, ≈100–400 ms) for a peer that is actually present. Both are acceptable because presence is non-load-bearing **and** because `unreachable` is *not* inbox-only: it commits the durable copy first and **still runs every live leg** (§ the committed C6 ordering), so the message still delivers live. A producer-side re-foreground debounce is the lever if window (ii) is ever worth eliminating — that would edit the producer and is **separate scope**. |

**Hard invariants this change must preserve** (restated as non-goals):
- Client vocabulary stays exactly `{'foreground','background'}`.
- No new `WidgetsBindingObserver`; wire into the existing `_MyAppState`.
- `setPresence` is **not** added to the base `P2PService` interface.
- Background publish stays **unawaited**; it must not block or widen the bounded pause window.
- `dispose()` is called on teardown (the 60 s `Timer.periodic` leaks otherwise); resume re-arms the heartbeat that pause cancelled.
- Presence is **never load-bearing**: a `blocked`/`unsupported`/`failed` publish must never throw, must never affect delivery or UI, and must not trigger retry/spam (NET-REL-07).

---

## Test Cases

IDs are `TC-181-XX`. Host-tier unless marked `[device]`. Every case is falsifiable and independent.

### Group A — Producer behavior (`SetPresenceUseCase`, host unit)

> Note: these assert the *already-built* use case still behaves correctly once exercised in production. They guard the contract the wiring depends on.

- **TC-181-01 — Foreground publishes once + arms heartbeat.** Invoke `onForegrounded()` with a fake `RelayPresenceSet` recording calls. Expected: exactly one `setPresence('foreground', 180000)` call completes, and the foreground heartbeat is armed (`isHeartbeatActive == true`).
- **TC-181-02 — Heartbeat re-publishes within the TTL window.** After `onForegrounded()`, advance fake time by 60 s twice. Expected: an additional `setPresence('foreground', 180000)` per beat (2 more), so the relay entry is refreshed well before the 180 s self-TTL.
- **TC-181-03 — Background cancels heartbeat + publishes `background`.** With the heartbeat armed, call `onBackgrounded()`. Expected: heartbeat disarmed (`isHeartbeatActive == false`); exactly one `setPresence('background', 180000)` is issued.
- **TC-181-04 — Background publish is non-blocking.** Back the fake `RelayPresenceSet` with a `setPresence` future that never completes. Call `onBackgrounded()`. Expected: the returned future completes promptly (does not wait on the network round-trip) — the publish is fire-and-forget.
- **TC-181-05 — `dispose()` stops the timer (no leak).** Call `onForegrounded()` then `dispose()`, then advance fake time by 3 × 60 s. Expected: heartbeat disarmed and **zero** further `setPresence` calls after dispose.
- **TC-181-06 — `unsupported` result never throws and does not retry.** Fake returns `PresenceSetResult.unsupported`. Call `onForegrounded()` and `onBackgrounded()`. Expected: no exception; a single publish per call (no retry/spam); a `PRESENCE_SELF_PUBLISH_UNSUPPORTED` diagnostic is emitted.
- **TC-181-07 — `blocked` and `failed` results never throw.** Fake returns `blocked` (then in a second run, `failed`). Expected: no exception in either case; delivery-affecting state untouched; no retry.

### Group B — Lifecycle edge dispatch (from `_MyAppState`)

- **TC-181-10 — `resumed` triggers foreground announce.** Drive the observer to `AppLifecycleState.resumed`. Expected: the wired use case's `onForegrounded()` runs (a `foreground` publish is attempted) and is invoked **unawaited** so it adds no latency to the resume orchestration.
- **TC-181-11 — `paused` triggers background announce.** Drive to `AppLifecycleState.paused`. Expected: `onBackgrounded()` runs (a `background` publish is attempted) without blocking `_onPaused`.
- **TC-181-12 — `hidden` also triggers background announce.** Drive to `AppLifecycleState.hidden`. Expected: same as `paused` — `onBackgrounded()` runs (parity with the existing `paused || hidden` pause-flush trigger).
- **TC-181-13 — `detached` does NOT announce background.** Drive to `AppLifecycleState.detached`. Expected: **no** `background` publish (detached is teardown-only); only the existing teardown runs.
- **TC-181-14 — Resume after pause re-arms the heartbeat.** Sequence `resumed → paused → resumed`. Expected: after the second `resumed`, the foreground heartbeat is armed again (the pause cancelled it; resume must restore it).
- **TC-181-15 — App teardown disposes the producer.** Trigger `_MyAppState.dispose()`. Expected: the use case's `dispose()` is called and no heartbeat timer survives teardown/hot-restart.
- **TC-181-16 — Transient pause→resume does not leave a stuck state.** Sequence `resumed → paused → resumed` rapidly. Expected: end state has the heartbeat armed and exactly one net `foreground` announce outstanding (no duplicated or orphaned timers).

### Group C — DI / interface purity

- **TC-181-20 — Wiring uses the concrete impl, not a new interface method.** Static/structural check: the producer is constructed from the existing `P2PServiceImpl` (which implements `RelayPresenceSet`); `setPresence` is **not** added to the base `P2PService` interface.
- **TC-181-21 — Existing `P2PService` fakes compile unchanged.** The ~31 `P2PService` fakes/mocks across the test suite require **no** new method implementation; the full test suite compiles without touching them.
- **TC-181-22 — No second `WidgetsBindingObserver`.** Structural check: presence is driven by the existing `_MyAppState` observer; no new observer is registered for it.

### Group D — End-to-end consumer activation (the payoff)

- **TC-181-30 — `unreachable` relay verdict fires the short-circuit.** For an `unknownPresence`-true 1:1 send (sender not connected/local to the target), with the relay returning `unreachable`, send a text message. Expected: `CHAT_MSG_PRESENCE_EMPHASIS{presence:"unreachable"}` then `CHAT_MSG_PRESENCE_INBOX_FIRST` are emitted, and the durable inbox copy is committed **before** the live race legs build.
- **TC-181-31 — Live legs still run after the short-circuit.** Same as TC-181-30. Expected: after the inbox-first commit, the live transport legs still execute best-effort and are never dropped; no **second** relay inbox write occurs (the same single `storeInInbox` future is awaited).
- **TC-181-32 — `reachable`/`unknown` keep today's behavior.** Repeat TC-181-30 with the relay returning `reachable`, then `unknown`. Expected: `CHAT_MSG_PRESENCE_EMPHASIS` is still emitted, but **no** `CHAT_MSG_PRESENCE_INBOX_FIRST`; the send keeps the fully-concurrent inbox-races-live behavior unchanged.
- **TC-181-33 `[device]` — Backgrounded-peer send commits to inbox first.** Sender A (no live connection to B), B foregrounded then backgrounded long enough to announce `background`. A sends B a text. Expected: A logs `CHAT_MSG_PRESENCE_INBOX_FIRST`; B receives the message via the relay store push-to-wake; A's send settles to "delivered to inbox" without waiting the full ~1.9 s race timeout.
- **TC-181-34 `[device]` — Foregrounded peer is NOT short-circuited.** Same rig with B kept foregrounded (heartbeat refreshing `foreground`). A sends. Expected: relay returns `reachable`; **no** `CHAT_MSG_PRESENCE_INBOX_FIRST`; live delivery as today.

### Group E — Non-load-bearing / degradation invariants

- **TC-181-40 — Account-move pause blocks the announce, harmlessly.** With an account move pausing network side-effects, drive `paused`/`resumed`. Expected: `setPresence` returns `blocked`; no exception; the device correctly does **not** announce foreground/background; delivery unaffected.
- **TC-181-41 — Old relay degrades silently.** Relay does not understand `presence_set` (returns "Unknown action"). Drive `resumed`/`paused`. Expected: `unsupported` result, a single diagnostic, no retry/spam, no thrown error, sends unchanged.
- **TC-181-42 — A failed publish never blocks or breaks a send.** Force `setPresence` to fail (network drop) during a `paused` transition while a 1:1 send is in flight. Expected: the send still completes via the normal race/inbox path; the failed presence publish has no effect on delivery or UI.
- **TC-181-43 — No announce spam under rapid lifecycle churn.** Toggle `resumed↔paused` 10× quickly. Expected: bounded, de-duplicated publishes (one per edge), no unbounded burst of relay calls.

### Group F — Known limitations (negative / documentation anchors)

- **TC-181-50 — Stale-circuit-connected peer bypasses the gate (out-of-scope case).** Sender holds a (possibly stale) `/p2p-circuit` to the target so `isAlreadyConnected`/`isConnectedToPeer` is true (`unknownPresence == false`). Send a text to that backgrounded target. Expected: the presence block is **not** entered — **no** `CHAT_MSG_PRESENCE_EMPHASIS`, no short-circuit — exactly reproducing the device evidence above. This test documents that presence wiring does not change this case; it must remain true after the fix.
- **TC-181-51 — Transient background, two-sided accepted limitation.** *(i) Publish lost:* background the app momentarily (no in-flight sends, so no FDC-06 bg assertion held) and immediately suspend before the round-trip completes. Expected: it is acceptable for the `background` publish to not reach the relay; the entry lapses to `unknown` after the ~180 s self-TTL. *(ii) Publish briefly lands:* a transient background whose publish *does* reach the relay marks the peer `unreachable` until re-foreground re-publishes `foreground`. Expected: a sender hitting that window front-loads the inbox await (≈100–400 ms) but the message **still delivers live**, because `unreachable` commits the durable copy first and then runs every live leg (the C6 ordering locked by TC-181-30/31) — never inbox-only. Both directions: no crash, no stuck state, no thrown error. A producer-side re-foreground debounce (separate scope) is the lever if (ii) is ever worth eliminating.

### Group G — Regression (existing behavior must not break)

- **TC-181-60 — Pause-flush window is not widened.** Measure the `_onPaused` path with and without the wiring. Expected: the FDC-06 bounded pause-flush window and its bg-assertion lifetime are unchanged; the presence publish does not add a blocking await or a second bg assertion on the pause path.
- **TC-181-61 — Detached teardown unchanged.** Drive `detached`. Expected: node/DB teardown behaves exactly as today; no presence publish is attempted on detach.
- **TC-181-62 — Fast paths unchanged.** Send to a connected peer and to a same-LAN peer. Expected: both take the existing live/local fast path; the presence block is not entered (`unknownPresence == false`); no behavior or timing change.
- **TC-181-63 — Posts location-presence untouched.** Exercise the posts location-presence feature (`PostPresenceListener` start/dispose, `publishPostPresenceUpdate`). Expected: unchanged behavior; the relay foreground/background wiring does not interact with it.
