# 183 — Active-chat keepalive: two-phone device-proof runsheet

Status: PENDING (PROD-CRITICAL closure — host floor is GREEN; the real `peer:ping`
leg + drop-detection are only provable on hardware)

Spec: `Test-Flight-Improv/183-active-chat-keepalive-foreground-peer-liveness-spec.md`
Plan: `Test-Flight-Improv/183-active-chat-keepalive-foreground-peer-liveness-tdd-plan.md`

> The host floor proves the whole loop with a faked `PeerLivenessProbe` + fakeAsync
> (arm/cancel/cadence/M-miss→reuse/gate/non-load-bearing/churn/resume). What ONLY a
> device can prove: the new gomobile `peer:ping` binding actually resolves on the
> handset, `ping.Ping` round-trips a real peer, and a real peer drop is detected in
> ~seconds → re-dial → the next send stays on the warm path.

## Build (needs the new gomobile symbols — `BridgePeerPing` / `GoMknoon.peerPing`)

The prebuilt `ios/Runner/GoMknoon.xcframework` + Android `.aar` do NOT yet contain
`PeerPing`; rebuild the bindings first, then build the apps:

```bash
# 1. Regenerate gomobile bindings (adds the new exported bridge.PeerPing).
cd go-mknoon && PATH="$PATH:$(go env GOPATH)/bin" GOTOOLCHAIN=go1.25.0 make all
cd ../ios && pod install && cd ..
# (verify the symbol landed)
cd go-mknoon && make verify-bindings ; cd ..

# 2. Profile builds with flow logging on (so KEEPALIVE_PEER_DROP / peer:ping land in logs).
flutter build apk --profile --dart-define=FDC_FLOW_LOG=1 --dart-define=MKNOON_ENABLE_NATIVE_MDNS=true
flutter build ios --profile --dart-define=FDC_FLOW_LOG=1 --dart-define=MKNOON_ENABLE_NATIVE_MDNS=true
```

## Rig

- Pixel 6 (Alice): `adb -s 21071FDF600CSC logcat | grep -E 'FLOW|peer:ping|KEEPALIVE'`
- iPhone 11 (Bob): `idevicesyslog -u 00008030-001A6D2801BB802E | grep -E 'FLOW|peer_ping|KEEPALIVE'`
- Both signed into accounts that are mutual 1:1 contacts; same warmed conversation.

## TC-183-50 (PROD-CRITICAL) — drop detected in seconds → re-dial → next send fast

1. Open the SAME 1:1 chat on both phones, both foreground. Exchange one message each
   way to confirm the warm/direct path (look for the upgraded/direct transport glyph,
   and `peer:ping` ticks appearing on the SENDER ≈ every 8 s).
2. On the SENDER (Alice), confirm steady-state: a `peer:ping` ≈ every 8 s and NO
   `KEEPALIVE_PEER_DROP` while Bob stays reachable.
3. Force ONLY THE PEER's (Bob's) connection to drop WITHOUT touching Alice's network:
   background Bob, OR turn Bob's WiFi off (leave Alice fully online).
4. **Expected on Alice within ≈ `kKeepAliveMissThreshold` × 8 s (≈16 s):**
   - `KEEPALIVE_PEER_DROP` fires, `details.peerId` = Bob's (short) id.
   - a `warmPeer` re-dial for Bob (`P2P_SERVICE_WARM_PEER_*`).
   - a `drainOfflineInbox` (`P2P_SERVICE_INBOX_DRAIN*` / coalesced with any 182 drain).
5. Immediately send a message from Alice → it must take the warm/recovering path, NOT
   sit on the ~30 s-lagged cold-dial/relay fallback that HEAD exhibits.
6. **Contrast run (same build, keepalive disabled):** repeat steps 1–5 with the loop
   off (e.g. comment the `_keepAliveUseCase.onForegrounded()` wire, or background the
   chat so the loop never arms) and observe the ~30 s lag before the drop is noticed —
   the delta IS the feature.

PASS = the drop is surfaced in ≈seconds (not ~30 s) and the post-drop send stays warm.

## TC-183-51 — bounded cadence + ZERO background pings (battery)

1. Keep the 1:1 chat open + foreground for several minutes. Count `peer:ping` events:
   `count ≈ elapsed / 8 s` (bounded — NOT a tight radio loop).
2. Background the app (home button). **Expect ZERO `peer:ping` while suspended**
   (`onBackgrounded()` cancelled the timer).
3. Foreground again → pings resume (`onForegrounded()` re-armed).

PASS = cadence ≈ elapsed/8 s in foreground; exactly zero `peer:ping` while backgrounded.

> Do NOT flip any feature-flag default ON for this proof. No DB migration is involved.

## Result log

| Date | Tester | TC-183-50 | TC-183-51 | Build SHA | Notes |
|---|---|---|---|---|---|
| | | | | | |
