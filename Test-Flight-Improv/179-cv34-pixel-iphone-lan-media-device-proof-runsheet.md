# 179 / CV-34 — Pixel→iPhone LAN-media device-proof runsheet (TC-179-D1)

Turnkey two-phone proof for the plan-179 closure. Closes **CV-34-both-ways + FDC-S6 i→A**, and
pins WHICH advertiser-side branch produced the portless iPhone TXT. Build from HEAD = `208be686`
(plan-179 fix) or later. Host suite is already green; this proves the wire leg + selects the branch.

> Why manual: the libp2p-LAN media leg cannot be proven by host fakes, and the both-on-WiFi rig is
> the only way to reproduce the asymmetry. mDNS dies in the background, so KEEP BOTH APPS FOREGROUND.

## 0. Rig
- **Pixel 6** (discoverer for the failing direction): `adb -s 21071FDF600CSC`
- **iPhone 11** (advertiser for the failing direction): `idevicesyslog -u 00008030-001A6D2801BB802E`
  (devicectl id `5763A494-757C-5B37-AC70-3AA2775FBEFF`). **Avoid iPhone 13** (Keychain-migration brick risk).
- Same WiFi **Vodafone-CA38** (`192.168.0.x`; iPhone ≈.211, Pixel ≈.240, Mac ≈.60).
- Dart-only change ⇒ gomobile `.aar`/`.xcframework` are cached ⇒ fast build (no `make all` needed).

## 1. Build (post-179 HEAD, flag ON, flow logging ON)
```bash
cd /Users/I560101/Project-Sat/mknoon-2/flutter_app
git rev-parse --short HEAD   # expect 208be686 (or later)

# Android (Pixel)
flutter build apk --profile \
  --dart-define=FDC_FLOW_LOG=1 \
  --dart-define=MKNOON_ENABLE_LIBP2P_LAN_MEDIA=true

# iOS (iPhone)
flutter build ios --profile \
  --dart-define=FDC_FLOW_LOG=1 \
  --dart-define=MKNOON_ENABLE_LIBP2P_LAN_MEDIA=true
# then install the built .app via Xcode/devicectl (do NOT process-launch --terminate-existing).
```

## 2. Install + launch
```bash
# Pixel: install + re-grant the LAN/location perms (mDNS needs them on Android 13+)
adb -s 21071FDF600CSC install -r build/app/outputs/flutter-apk/app-profile.apk
for p in ACCESS_FINE_LOCATION ACCESS_COARSE_LOCATION NEARBY_WIFI_DEVICES; do
  adb -s 21071FDF600CSC shell pm grant <APP_ID> android.permission.$p
done
```
- **iPhone: TAP-LAUNCH the app on the phone.** Do NOT `devicectl ... process launch --terminate-existing`
  — it trips an AGXAccelerator `CommandSubmissionEnabled` deny → black screen (app alive, can't draw).
- Bring BOTH apps to the foreground and keep them there for the whole run.

## 3. Confirm both are advertising (from the Mac)
```bash
dns-sd -B _mknoon._tcp local.    # both phones must appear as mknoon-<peerId…>; Ctrl-C when seen
```

## 4. Capture (two terminals, started BEFORE sending)
```bash
# Terminal A — Pixel (discoverer). Scratchpad: …/scratchpad/cv34/
adb -s 21071FDF600CSC logcat -v time | grep -E \
 'FLOW.*(LOCAL_MDNS_DISCOVERY_START|LOCAL_MDNS_PEER_FOUND|LOCAL_MDNS_PEER_SKIPPED_NO_LIBP2P_ADDR|LOCAL_MDNS_PEER_LOST_RETAINED|P2P_LAN_PEER_FOUND_REQUEST|P2P_LAN_PEER_FOUND_RESPONSE|node:lan_dial_ready|LOCAL_MEDIA_SEND_START|LIBP2P_LAN_MEDIA_SEND|P2P_LAN_MEDIA_SEND_REQUEST|P2P_LAN_MEDIA_SEND_RESPONSE)' \
 | tee pixel_179.log

# Terminal B — iPhone (advertiser)
idevicesyslog -u 00008030-001A6D2801BB802E | grep -E \
 '(LOCAL_MDNS_ADVERTISE_START|LOCAL_MDNS_ADVERTISE_SKIPPED_SUSPECTED_DENIED|LOCAL_MDNS_SUSPECTED_DENIED_GATE_LATCHED|FDC_LAN_ADVERT_PORTS|FDC_LAN_ADVERT_PORTS_DEFERRED|FDC_LAN_ADVERT_PORTS_DEFERRED_GATED|addresses:updated)' \
 | tee iphone_179.log
```

## 5. Action
1. **Failing direction first:** on the **Pixel**, send a 1:1 **image** to the iPhone contact.
2. Wait ~30s (covers ≥1 mDNS resolve + the 20s refresh re-resolve).
3. **Control (known-good):** on the **iPhone**, send an image to the Pixel — should still work end-to-end.

## 6. Decision table — Pixel→iPhone (the failing direction)
Read the **Pixel** log for the discoverer outcome, the **iPhone** log for the advertiser branch.

| Pixel observations | iPhone observations | Verdict |
|---|---|---|
| `…PEER_FOUND` **then** `P2P_LAN_PEER_FOUND_REQUEST addrCount≥1` → `node:lan_dial_ready` → `P2P_LAN_MEDIA_SEND_RESPONSE{ok:true}` | `FDC_LAN_ADVERT_PORTS` published | ✅ **CLOSED both-ways.** The advert healed and the Pixel forwarded. CV-34-both-ways + FDC-S6 i→A pass. |
| `…PEER_FOUND` then **`LOCAL_MDNS_PEER_SKIPPED_NO_LIBP2P_ADDR`** (≥1), no `PEER_FOUND_REQUEST` initially, then later a forward after a re-resolve | `FDC_LAN_ADVERT_PORTS_DEFERRED_GATED` then `FDC_LAN_ADVERT_PORTS` (after a peer resolved) | ✅ **Fix engaged (sub-cause B confirmed).** The gated re-advert deferred (didn't tear down), the Pixel's bounded re-resolve picked up the healed TXT. Branch = **B (iOS suspected-denied gate)**. |
| `…PEER_FOUND` + **`SKIPPED_NO_LIBP2P_ADDR`** persists, never forwards | `FDC_LAN_ADVERT_PORTS_DEFERRED` (not `_GATED`) repeating, never `FDC_LAN_ADVERT_PORTS` | ⚠️ **Branch A live** (`_localNetworkProven` hold). Route the **`_localNetworkProven` decouple** follow-up session (device-gated; was deferred for the iOS-watchdog risk). |
| `…PEER_FOUND` + **`SKIPPED_NO_LIBP2P_ADDR`** persists | `FDC_LAN_ADVERT_PORTS` published (iPhone says ports ARE advertised) but Pixel still sees empty | ⚠️ **Branch C/D** — Pixel stale-cache re-resolve or **NsdManager dropping the iOS TXT**. Capture a raw NSD TXT dump; route the NsdManager probe. |
| **No** `LOCAL_MDNS_PEER_FOUND` for the iPhone at all | (any) | ❗ **Never-resolved**, not resolved-but-empty. Different failure — check the Pixel browse / `dns-sd` and the 178 gate (should be Android-disarmed). |

**Control row (iPhone→Pixel):** iPhone log shows `P2P_LAN_PEER_FOUND_REQUEST addrCount≥1` + Pixel commits the image, `P2P_LAN_MEDIA_SEND_RESPONSE{ok:true}`. If this regressed, STOP — something broke the working direction.

## 7. After the run
- Save `pixel_179.log` + `iphone_179.log` to `…/scratchpad/cv34/`.
- Tick **TC-179-D1** in `179-…-tdd-plan.md` Done Criteria with the verdict + which branch fired.
- Update the FDC-CONVERGENCE-CHECKLIST: CV-34 both-ways status; FDC-S6 i→A.
- Route the follow-up named by the decision row (none / `_localNetworkProven` decouple / NsdManager probe).

## Do-NOTs (hard-won)
- Do NOT `devicectl process launch --terminate-existing` the iPhone (black-screen deny). Tap-launch.
- Do NOT background either app mid-run (mDNS dies).
- Do NOT flip `EnableLibp2pLANMedia`/`EnableDcutrUpgrade` defaults — pass them as dart-defines only.
- Do NOT revert 175/177/178. The flag stays dark in shipped builds (also gated on the parked FDC-S6 verdict).
