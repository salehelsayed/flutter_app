# 181 — Presence lifecycle wiring: device-proof runsheet (TC-181-33 / TC-181-34 / TC-181-51)

Status: **PASS** — device-proven 2026-06-30.
Spec: `Test-Flight-Improv/181-presence-lifecycle-wiring-offline-detection-spec.md`
Plan: `Test-Flight-Improv/181-presence-lifecycle-wiring-offline-detection-tdd-plan.md`

The host wiring locks (TC-181-W1–W6) are source-assertion; the producer→relay→consumer loop is only provable on real devices, so this leg is **PROD-CRITICAL**. Result below.

---

## Rig

- **Pixel 6** `adb -s 21071FDF600CSC` — the **181 build** (this session): `flutter build apk --profile --dart-define=FDC_FLOW_LOG=1`, `app-profile.apk`, `adb install -r` (data/identity preserved). Plays the **target** (announces `background`/`foreground`).
- **iPhone 11** `idevicesyslog -u 00008030-001A6D2801BB802E` — its existing 180-era build (commit `53b8d6fc`), which already carries the committed consumer short-circuit (`a32454c2`, an ancestor of the 180 build) and `FDC_FLOW_LOG`. Plays the **sender**.
- Why this role split: 181 is the **producer** wiring, so the phone that must run the new build is the one that *announces* (the Pixel). The sender only needs the pre-committed consumer, so no iOS rebuild was required.
- iPhone 13 (`00008110-*`, Keychain-brick risk) was attached but **not flashed**.

## ⚠️ Precondition that makes or breaks TC-181-33 (Finding-1, confirmed on device)

The send-side short-circuit only runs when the **sender** has `unknownPresence==true` — no live connection to the target, **not even a stale relay `/p2p-circuit`** (`send_chat_message_use_case.dart:704-707`; `isConnectedToPeer` at `p2p_service_impl.dart:4928` is transport-blind, so a circuit counts as "connected"). This was not theoretical:

- **1st send attempt (stale circuit held):** cutting the *Pixel's* WiFi dropped the Pixel, but the abrupt drop didn't propagate a clean libp2p close, so the iPhone still held a dead circuit → `unknownPresence==false` → it **skipped the presence block entirely** (no `EMPHASIS`, full race → inbox at 1858ms). This is exactly the documented stale-circuit limitation (TC-181-50 / the out-of-scope follow-up) — reproduced live.
- **Fix that worked:** an **iPhone WiFi toggle (off → on)** force-drops the stale circuit; with the Pixel offline no new circuit re-forms, so the next send evaluates `unknownPresence==true`.

**Runsheet rule:** to exercise TC-181-33, after backgrounding the target, *toggle the sender's WiFi* before sending. If `CHAT_MSG_PRESENCE_EMPHASIS` is absent from the sender log, the sender still held a connection — toggle and retry. (The relay verdict itself does not need the target disconnected: rule-1 `fresh background self-state → unreachable` wins regardless of connectedness. The disconnect is only to make the *sender* enter the presence block.)

---

## Step 1 — producer wiring (Pixel only, the 181 change). PASS

Driven over adb (`monkey` launch / `KEYCODE_HOME`), `FDC_FLOW_LOG` capture:

```
HOME (pause/hidden):
  APP_LIFECYCLE_STATE_CHANGED{state:"hidden"}  → PRESENCE_SELF_PUBLISH{state:"background", bestEffort:true}
  APP_LIFECYCLE_STATE_CHANGED{state:"paused"}  → PRESENCE_SELF_PUBLISH{state:"background", bestEffort:true}
  GO_BRIDGE_SEND{relay:presence_set} → BRIDGE_CALL_TIMING{relay:presence_set, outcome:"success", 56–114ms}
re-foreground (resumed):
  APP_LIFECYCLE_STATE_CHANGED{state:"resumed"} → PRESENCE_SELF_PUBLISH{state:"foreground"}   (no bestEffort → bestEffort:false)
  BRIDGE_CALL_TIMING{relay:presence_set, outcome:"success", 44–101ms}
HOME again → PRESENCE_SELF_PUBLISH{state:"background"}   (repeatable)
```

Confirms: `_onPaused`→`onBackgrounded`→`background` (best-effort), `_onResumed`→`onForegrounded`→`foreground` (awaited), and the relay round-trip **succeeds** — the relay now actually knows this peer's state. The `hidden`+`paused` double-publish (plan Risk) is present and **harmless** (both land `success`; relay dedups by TTL refresh). Cold-start's first `resumed` is missed (observer registers a beat late) — expected; the wiring fires on every subsequent edge.

## TC-181-33 — backgrounded peer short-circuit (PROD-CRITICAL). PASS

Pixel backgrounded (announced fresh `background`, relay `success` at 16:25:07) → Pixel WiFi off → **iPhone WiFi toggled** → iPhone sends:

```
CHAT_MSG_SEND_START{targetPeerId:"12D3KooWFF"}
GO_BRIDGE_SEND{relay:presence_get} → BRIDGE_CALL_TIMING{relay:presence_get, outcome:"success", 54ms}
CHAT_MSG_PRESENCE_EMPHASIS{presence:"unreachable"}      ← relay returned unreachable (fresh background self-state)
CHAT_MSG_PRESENCE_INBOX_FIRST                            ← short-circuit FIRED, custody committed ~100ms
CHAT_MSG_SEND_SUCCESS{status:"inboxed", via:"inbox"}
CHAT_MSG_SEND_TIMING{elapsedMs:1639, sendPath:"inbox"}
```

Proves the full chain that was dormant before 181: Pixel's 181 wiring published `background` → relay returned `unreachable` → iPhone's committed consumer short-circuited.

## TC-181-34 — reachable peer NOT short-circuited (negative control). PASS

Pixel brought foreground+online (announced `foreground`, relay `success` at 16:28:45); iPhone reconnected and sent:

```
CHAT_MSG_SEND_START{targetPeerId:"12D3KooWFF"}
CHAT_MSG_SEND_LAN_ACK{kind:"committed"}
CHAT_MSG_SEND_SUCCESS{status:"delivered", via:"local"}
CHAT_MSG_SEND_TIMING{elapsedMs:205, sendPath:"local"}
```

**No `EMPHASIS`, no `INBOX_FIRST`** — live LAN delivery in 205ms. (Landed via the connected fast path / TC-181-62 because the iPhone reconnected to the now-online Pixel; the `EMPHASIS{reachable}` variant is host-covered by `send_presence_emphasis_test.dart::C5`.)

## Behavioral contrast (one rig, minutes apart)

| Target state | relay verdict | EMPHASIS | INBOX_FIRST | path / latency |
|---|---|---|---|---|
| backgrounded (181 `background`) | `unreachable` | yes | **fired** | inbox-first, custody ~100ms (elapsed 1639ms) |
| stale circuit (1st attempt) | — (block skipped) | — | — | full race → inbox (1858ms) |
| foreground / connected | `reachable` | — | — | live LAN (205ms) |

---

## Verdict: PASS

The 181 producer wiring is device-proven; the dormant `unreachable` short-circuit now fires in production for a backgrounded, no-live-connection target, and stays inert for a reachable one.

## Notes / accepted limitations (unchanged from spec scope)

- **Latency:** `INBOX_FIRST`/custody/push-to-wake front-load at ~100ms (the win), but `SEND_TIMING` stays ~1.6s because the committed consumer keeps running the live legs after the inbox-first commit (TC-181-31, pre-existing, out of 181 scope).
- **Stale-circuit (TC-181-50):** confirmed real on device — a sender holding a circuit to the target bypasses the presence block. Out of scope here (would require changing `unknownPresence`'s connection-classification); tracked as a follow-up.
- **TC-181-51 (transient-background publish loss):** not separately forced on device; best-effort behavior is host-covered (`set_presence_use_case_test.dart::TC-09-05`). Accepted (non-load-bearing; ~180s self-TTL → `unknown`).
- **WiFi-off / radio-off target:** a target that loses network while foregrounded cannot self-publish `background`, so the relay returns `reachable`/`unknown`, never `unreachable` — this mechanism covers *app-backgrounded-with-network*, not network-loss; relay-side connection-drop detection is a separate follow-up.
