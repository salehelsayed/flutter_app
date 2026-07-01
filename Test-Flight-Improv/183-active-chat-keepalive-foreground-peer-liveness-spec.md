# 183 - Active-chat keepalive: proactively probe the live 1:1 peer connection while a chat is open  (Feature — Spec)

Status: awaiting-review (spec only — problem + current state + test cases; no solution design).

Sibling work (read first, to respect the boundaries):
- **182** `182-connectivity-restore-inbox-drain-tdd-plan.md` — wires an OS connectivity source (`connectivity_plus`) and drains the inbox when **my device's** connectivity returns. 183 must NOT re-wire that source or duplicate the drain.
- **181** `181-presence-lifecycle-wiring-*` — `SetPresenceUseCase`, a foreground-only `Timer.periodic` armed in `_onResumed` / cancelled in `_onPaused`. 183 mirrors this exact pattern.

---

## Problem Statement

While a 1:1 conversation is open, the libp2p connection to that peer is kept warm **only opportunistically**, and a dead connection is detected **only passively** — so the warm "fast send" path silently goes stale mid-conversation and a dropped peer isn't noticed for up to ~30 s.

Concretely, today:
- The active-peer connection is warmed by a **single, one-shot `warmPeer` speculative dial** fired once at chat-open (`conversation_wired.dart:568`), resume (`handle_app_resumed.dart:207`), or notification-open (`prepare_notification_open_use_case.dart:57`). **There is no periodic re-warm while the chat stays open** (`p2p_service_impl.dart:2522` — fire-and-forget, debounced, one per trigger).
- The libp2p **ping protocol is responder-only**: the Go node answers `/ipfs/ping/1.0.0` but **never initiates a ping** to a peer (`go-mknoon/node/node.go:381-404` — default `EnablePing=true`, no `ping.Ping(...)` caller anywhere). Nothing app-level keeps the active conversation's QUIC connection from lapsing at the **~30 s quic-go idle default** (no custom `MaxIdleTimeout`/`KeepAlivePeriod`; `connmgr` grace 1 min, `node.go:287`).
- The only periodic machinery is a **30 s relay-health poll** (`p2p_service_impl.dart:2711 → _performHealthCheck → drainOfflineInbox :3866`) — relay-state recovery + a slow drain backstop, **not** a per-active-peer liveness probe — and a **60 s presence heartbeat** to the relay (181). Neither probes the live 1:1 peer connection.

**User-visible consequences:**
1. **Sends go stale mid-conversation.** A connection warmed at chat-open lapses after ~30 s idle; the next send then pays the cold-dial (~900 ms) or the stale-reuse penalty (reuse times out 500 ms → *then* the race), instead of the warm ~150–215 ms fast path.
2. **A dropped peer is invisible for up to ~30 s.** If the peer's connection dies — the other side backgrounds, a relay circuit breaks, or the path silently fails **even though my own WiFi is fine** — nothing notices until the next send fails or the 30 s health poll ticks. For a live, back-and-forth conversation that's far too slow.

**Why 182 and the 30 s poll don't cover this:**
- **182** reacts to **my device's** OS connectivity edges (WiFi off→on / handoff). It does **not** detect the *peer's* connection dying while my own network is healthy.
- **The 30 s poll** is global relay-state recovery on a 30 s cadence — too coarse for the conversation you're actively in.
- **181's heartbeat** publishes *my* presence to the relay; it never probes a peer connection.

**What must improve:** while the app is foreground and a 1:1 chat is open, the app should **actively probe the live connection to that one peer on a short cadence** — keeping it warm (resetting the idle timer) and detecting a drop within **seconds**, then re-dialing (and letting the existing drain catch up) so the conversation stays on the fast path.

---

## Impact Analysis

| Dimension | Detail |
|---|---|
| Severity | Degraded latency + reliability for active conversations; not data loss (inbox + 30 s poll remain the delivery/catch-up backstop). |
| Frequency | Any conversation left open longer than ~30 s, or where the peer's connection drops mid-chat without a local network change. |
| User-visible | Mid-conversation sends intermittently fall back to cold-dial/relay/inbox; replies from a dropped-then-returned peer lag up to ~30 s. |
| Platforms | iOS + Android (foreground-only; the OS suspends background timers — see Scope). |
| Cost of NOT doing it | The "feels slow / first message after a pause is slow" class of complaints persists even with warm-peer + sticky, because the warm state decays unguarded. |

---

## Current State (verified, file:line)

### Warm / liveness machinery that EXISTS (none probes the active 1:1 peer)
| Element | Location | State |
|---|---|---|
| `warmPeer` | `lib/core/services/p2p_service_impl.dart:2522` | One-shot speculative dial per trigger; LAN-seed first (`discoverLocalPeer`, 1500 ms, `:2586`) else fire-and-forget `dialPeer(4000 ms, preferQuic)` (`:2615`); escalating 5 s→5 min cooldown (`:2515`); account-gated (`:2570`). **No periodic re-warm.** |
| warmPeer triggers | `conversation_wired.dart:568` (chat-open), `handle_app_resumed.dart:207` (resume), `prepare_notification_open_use_case.dart:57` (notif-open) | All one-shot. |
| libp2p ping | `go-mknoon/node/node.go:381-404` (default `EnablePing=true`, no `Ping(false)`) | **Responder only** — node answers pings, never sends them. No `ping.Ping`/`ping.NewPingService` caller in production. |
| QUIC idle | `node.go:339-353` (listen multiaddrs only); **no** custom `MaxIdleTimeout`/`KeepAlivePeriod` | Idle conns lapse at quic-go ~30 s default. |
| ConnMgr | `node.go:287` `NewConnManager(10,100, WithGracePeriod(1m))` | Trim watermarks, not liveness. |
| 30 s relay-health poll | `p2p_service_impl.dart:196`/`:351`/`:2711` → `_performHealthCheck` → drain `:3866` | Relay-state recovery + slow drain backstop; not a per-peer ping. |
| 60 s presence heartbeat | `set_presence_use_case.dart:43` (`kPresenceForegroundHeartbeat=60s`), armed `_onResumed`/cancelled `_onPaused` | Publishes presence to relay; not a peer ping. |

### Scope key + lifecycle seams
| Element | Location | Note |
|---|---|---|
| Active 1:1 peer | `lib/core/notifications/active_conversation_tracker.dart` — `setActive` `:16`, `clear`/`clearIfActive` `:21/:26`; set `conversation_wired.dart:504`, cleared `:4255` | Reliable non-null exactly for the chat-open window — the keepalive scope key. |
| Lifecycle seams | `main.dart` `_onResumed` `:4496`, `_onPaused` `:4425` | Where the foreground-only loop arms/cancels. |
| 181 precedent | `SetPresenceUseCase` field `main.dart:3644`, armed `:4512`, cancelled `:4454`, disposed `:4365`; `Timer? _heartbeat` `set_presence_use_case.dart:37` | Working template: lifecycle-driven, foreground-only `Timer.periodic`, capability-interface kept off base `P2PService`. |
| `_networkChangeSignal`/`onNetworkChanged` | `p2p_service_impl.dart:176/385/512/2659` | Null in prod (182 wires the source); `onNetworkChanged` only re-warms, never drains. |

### Test surface a keepalive would touch
- `test/core/services/p2p_service_impl_test.dart` (warmPeer + onNetworkChanged), `test/core/lifecycle/handle_app_resumed_warm_peer_test.dart`, `test/core/lifecycle/connectivity_lifecycle_test.dart`, `test/core/services/fake_p2p_service.dart` (the ~31-fakes hazard — see [[reference_p2pservice_interface_addition_breaks_all_fakes]]).

---

## Scope Clarification

| Area | Status |
|---|---|
| A foreground-only, active-1:1-peer-scoped periodic liveness probe (proactive libp2p ping) that keeps the connection warm + detects a drop in seconds | **In scope** — the whole feature. |
| A new Go bridge command to ping a specific peer (`peer:ping` → `ping.Ping`), since the node is responder-only today | **In scope** (Go + bridge + Dart). |
| Wiring the loop into `_MyAppState` lifecycle (arm in `_onResumed`, cancel in `_onPaused`), scoped by `ActiveConversationTracker.activePeerId`, following the 181 pattern | **In scope.** |
| On detected drop: re-dial via the existing `warmPeer`, and trigger the **existing** `drainOfflineInbox` (so the active conversation catches up) | **In scope — REUSE only.** Must not build new re-dial/drain machinery. |
| The ping capability on a **capability interface** (e.g. `PeerLivenessProbe`), NOT on base `P2PService` | **In scope** — spare the ~31 fakes (181 precedent). |
| Background pinging | **Out of scope — impossible.** OS suspends background timers; the loop is foreground-only (parity with 181 heartbeat / Berty / Waku). |
| The OS connectivity source + connectivity-restore drain | **Out of scope — owned by 182.** 183 reuses 182's `drainOfflineInbox`, never re-wires the source. |
| The 30 s relay-health poll | **Out of scope — unchanged backstop.** Do not remove/retune. |
| Pinging the roster / non-active peers | **Out of scope.** Active 1:1 peer only (battery). |
| Group conversations | **Out of scope** (1:1 only; groups use pubsub, a different liveness model). |

**Hard invariants:**
- Foreground-only; armed/cancelled on the same lifecycle seams as 181; also cancelled the instant the conversation closes (`activePeerId` clears).
- Bounded cadence (probe interval **N** well under the 30 s QUIC idle, with a sane floor) + flap debounce — never a tight loop, never a battery sink.
- Never blocks the UI or the send path; a failed/ambiguous ping is non-load-bearing (no thrown errors, no spam).
- Account-migration network gate respected (no probing while migration paused network side-effects).
- Reuses `warmPeer` + `drainOfflineInbox`; adds no parallel re-dial/drain path.

---

## Test Cases

IDs `TC-183-XX`. Host-tier unless marked `[device]`.

### Group A — Keepalive loop (host unit, `fakeAsync`, the 181-style use case)
- **TC-183-01** — Arms on foreground + active 1:1 peer: entering the foreground with a non-null `activePeerId` starts the periodic probe.
- **TC-183-02** — Probes on cadence: advancing fake time by N × 3 issues exactly 3 pings to the active peer.
- **TC-183-03** — Cancels on background: `onBackgrounded`/pause stops the loop (no further pings while suspended).
- **TC-183-04** — Cancels on conversation close: when `activePeerId` clears (chat dispose), the loop stops even if still foreground.
- **TC-183-05** — Success keeps it quiet: a successful ping does NOT trigger a re-dial and resets any failure count.
- **TC-183-06** — Drop detection → re-dial: M consecutive failed pings trigger exactly one `warmPeer(activePeer)` re-dial (debounced, not per-miss).
- **TC-183-07** — Drop → drain: the same drop also triggers the existing `drainOfflineInbox` once (REUSE), so the conversation catches up.
- **TC-183-08** — Never probes a group/null peer: a `group:`-prefixed or null `activePeerId` issues zero pings.
- **TC-183-09** — Account-migration gate: while network side-effects are paused, the loop issues no pings and never throws.
- **TC-183-10** — Non-load-bearing: a thrown/timed-out ping never propagates, never spams retries, never affects a concurrent send.
- **TC-183-11** — No tight loop / bounded cadence: rapid foreground↔background churn yields one armed loop, bounded ping count (no burst).

### Group B — Interface purity / wiring
- **TC-183-20** — The ping rides a capability interface (`PeerLivenessProbe` or similar) constructed from the concrete `P2PServiceImpl`; `peer:ping` is NOT added to base `P2PService` → the ~31 fakes compile unchanged.
- **TC-183-21** — Lifecycle wiring lock (source-assertion, TC-164/181 precedent): `_MyAppState` constructs the keepalive driver and arms/cancels it in `_onResumed`/`_onPaused`/dispose.

### Group C — Go bridge
- **TC-183-30** — `peer:ping` bridge command issues a real libp2p `ping.Ping` to the target and returns success/RTT or a typed failure (host-fakeable boundary; the Go half is device-proven).

### Group D — Degradation / non-regression
- **TC-183-40** — The 30 s relay-health poll and its drain are unchanged (preserved-green sentinel).
- **TC-183-41** — 182's connectivity-restore drain is unchanged; 183 only *reuses* `drainOfflineInbox`, adds no second source.
- **TC-183-42** — warmPeer's existing one-shot triggers + escalating cooldown are unchanged.

### Group E — Device-proof (PROD-CRITICAL)
- **TC-183-50 `[device]`** — Two phones in an open 1:1 chat. Force the peer's connection to drop (peer backgrounds, or kill its WiFi) **without changing the sender's network**. Expect: the sender's keepalive detects the drop within ~N s (a `KEEPALIVE_*` flow event), re-dials, and the **next send stays on the warm/live path** instead of paying the cold-dial/relay/inbox penalty — measurably faster than today's ~30 s-lagged recovery.
- **TC-183-51 `[device]`** — Battery/cadence sanity: over a multi-minute open chat, the ping cadence stays bounded (no runaway), and **zero pings fire while backgrounded**.

---

## Open decisions for the TDD plan
- Probe interval **N** and consecutive-miss threshold **M** (trade fast detection vs battery; N < 30 s idle, e.g. 7–10 s; M ≈ 2).
- Whether a drop also re-publishes presence (likely defer to 181) and whether drain-on-drop is unconditional or gated (avoid double-draining with 182's path on a simultaneous local-network change).
- Exact capability-interface name + the `peer:ping` payload/result shape.
