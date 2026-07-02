# 191 — iOS foreground push forwarding: device runsheet

Status: **PENDING device execution** (host-green landed; closure = this runsheet).
The **Before** column is already recorded: the bug was device-proven on HEAD
2026-07-02 via 2 timed testpeer inbox injections (10:04:30Z → drain only on the
189 30 s grid at :34; 10:05:48Z → drain only at 10:06:04) — **zero**
push-triggered drains. This runsheet re-runs the same protocol on a **profile**
build carrying Fix N1 (+ D1/D2) and records the **After**.

> ⚠ **--profile builds ONLY on the phones.** `flutter run --debug` triggers
> `dev_keychain_wipe.dart` → identity + DB-key loss on first debug launch
> (2026-07-02 iPhone-11 incident). Every install below is `flutter build ios
> --profile` / `flutter build apk --profile` + device install, never `run
> --debug`.

## Devices / relay
- iPhone 11 (receiver): UDID `00008030-001A6D2801BB802E`.
- Pixel 6 (Android control receiver): `21071FDF600CSC`.
- A second paired contact (any device) as the **sender** identity that the
  testpeer injects on behalf of — or inject directly to the receiver peer id.
- Sender injector: `testpeer` (`cd go-mknoon && GOTOOLCHAIN=go1.25.0 make testpeer`).
- Prod relay: `/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g`
  (+ `/udp/4002/quic-v1/...`). Read-only journal: `ssh -i se.pem ubuntu@13.60.15.36`
  then `sudo journalctl -u mknoon-relay -f` (watch `[PUSH]` + reservation lines).
- FLOW capture: `idevicesyslog -u 00008030-001A6D2801BB802E | grep -E "PUSH_DIAG|PUSH_FOREGROUND|PUSH_LISTENERS_ARMED|willPresent_|fcm_plugin_ref"`.

## Testpeer injection pipeline (literal)
```bash
cd go-mknoon && GOTOOLCHAIN=go1.25.0 make testpeer
{ printf '{"cmd":"generate_identity"}\n'; sleep 1; printf '{"cmd":"start"}\n'; sleep 3; \
  printf '{"cmd":"wait_relay","params":{"timeoutSec":20}}\n'; sleep 5; \
  printf '{"cmd":"inbox_store_v1","params":{"peerId":"<IPHONE_PEER_ID>","text":"191 probe A1"}}\n'; sleep 8; } | ./bin/testpeer
```
Repeat with distinct text (`191 probe A2`, `A3`, …) for each iteration. Note the
UTC wall-clock at injection; compare against the ack in the relay journal + the
FLOW `PUSH_FOREGROUND_MESSAGE_RECEIVED`/`ROUTED` timestamps.

## Pre-flight (once)
- [ ] iPhone 11: install the **profile** build carrying this branch; open the
      app to the **foreground** (a 1:1 conversation surface is fine).
- [ ] Confirm the app registered a fresh push token this launch (relay journal:
      token upsert for `<IPHONE_PEER_ID>`; native log `didRegisterForRemoteNotifications`).
- [ ] Confirm the plugin ref was captured: FLOW/syslog shows
      `[PUSH_DIAG] fcm_plugin_ref found class=FLTFirebaseMessagingPlugin`
      (a `fcm_plugin_ref nil …` line here is a **stop-if** — see plan step 5).
- [ ] Confirm listeners armed: `PUSH_LISTENERS_ARMED{platform:ios,kinds:[onMessage,onMessageOpenedApp]}`
      emitted exactly once.

## §A — OS-boundary foreground push → drain (TC-191-01/02, PROD-CRITICAL)
App in **foreground**. Inject ×3 (A1/A2/A3), ≥30 s apart so each lands mid-grid
(the 189 periodic drain is 30 s — an off-grid ack proves the push, not the grid).

| Iter | Inject (UTC) | Ack (UTC) | Δ (s) | Off-grid? | `PUSH_FOREGROUND_MESSAGE_RECEIVED` | `…_ROUTED` |
|---|---|---|---|---|---|---|
| A1 | | | | | | |
| A2 | | | | | | |
| A3 | | | | | | |

- [ ] **PASS** = all three ack **≤5 s** post-injection AND **off** the 30 s grid,
      each with a `willPresent_forward_to_fcm_plugin` + `PUSH_FOREGROUND_MESSAGE_RECEIVED`
      + `PUSH_FOREGROUND_MESSAGE_ROUTED{kind:conversation}` FLOW anchor.
- Before (HEAD, 2026-07-02): 0/2 off-grid — acks only at the next 30 s tick.

## §B — presentation + NSE + single display (TC-191-04/05)
During §A, on each foreground injection:
- [ ] **No banner** appears while foregrounded (presentation options 0 preserved —
      the forward passes the persisted `setForegroundNotificationPresentationOptions`
      = alert/badge/sound false).
- [ ] NSE still runs for the same push class (syslog: `Service extension delivered
      mutated content` / preview render) when the app is **not** foreground.
- [ ] **Single** message materialises (no duplicate) — plugin
      `_foregroundUniqueIdentifier` dedupe + Dart drain coalescing.

## §C — delegate re-install cycle + tap/FLN preservation (TC-191-10/11)
- [ ] Background the app (home), wait 10 s, **foreground** it, then inject A4 →
      ack **≤5 s** off-grid (the didBecomeActive delegate re-install + captured
      plugin ref survive a bg→fg cycle).
- [ ] **Cold-start race**: force-quit, inject A5, cold-launch to foreground →
      either an immediate drain when the ref is captured, or a fail-safe fall to
      the ≤30 s grid (never a loss). Record which.
- [ ] **Tap routing unchanged (warm)**: background, inject A6, tap the delivered
      notification → lands on the correct 1:1 conversation **once** (manual
      `ios_notification_open` bridge; `onMessageOpenedApp` stays silent — no
      double navigation).
- [ ] **Tap routing unchanged (cold)**: force-quit, inject A7, cold-tap → correct
      conversation, single route.
- [ ] **FLN local notification** (e.g. a foreground fallback) still presents +
      taps correctly (super path byte-identical; `willPresent_super_path` in FLOW).

## §D — Android control + token half (TC-191-30/34)
- [ ] Pixel 6 foreground, inject to `<PIXEL_PEER_ID>` → ack **≤2 s**, exactly one
      `PUSH_FOREGROUND_MESSAGE_RECEIVED` (Android path unchanged — no willPresent
      forward on Android; the FCM plugin's own lifecycle chain works there).
- [ ] Relay journal shows the iPhone's **fresh token registration** this session
      (token half untouched by Fix N1).

## Closure (TC-191-40)
- [ ] §A ×3 iOS ack ≤5 s off-grid, with RECEIVED/ROUTED FLOW anchors.
- [ ] §B no banner, NSE intact, single display.
- [ ] §C bg→fg + cold race covered; tap (warm+cold) + FLN unchanged.
- [ ] §D Android control ≤2 s; fresh-token registration observed.
- [ ] Mutation re-red (optional): a build with the `willPresent` forward removed
      reproduces the Before column (0 push drains).

## Result
(pending device execution — record PASS + metrics table here)
