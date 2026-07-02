# 189 — Degraded-relay drain starvation + restart loop: two-phone device runsheet

Status: **PENDING** — host-green + Go-integration-green achieved 2026-07-02; this
runsheet is the closure gate (host-green is NOT closure for 189).

Spec: `Test-Flight-Improv/189-degraded-relay-drain-starvation-restart-loop-spec.md`
Plan: `Test-Flight-Improv/189-degraded-relay-drain-starvation-restart-loop-tdd-plan.md`

> The host floor proves: drain-on-every-tick (incl. failed/throwing recoveries),
> truthful `phase=recovered` (bridge `success` serialized), recovery backoff, and —
> against a REAL local circuit-v2 hop service — reservation-truth exits the restart
> loop and the reservation is peer-dialable. What ONLY the phones can prove: the
> 2026-07-02 field wedge itself (prod relay over cellular CGNAT / home WiFi) stops
> flapping at 30 s, Pixel→iPhone store→ack collapses from 86–368 s+ to ≤35 s, and
> autorelay's on-device non-publish gets a captured explanation (TC-189-50).

## Build (Go changed — gomobile bindings MUST be rebuilt)

`node.go` / `relay_session.go` / `autorelay_metrics.go` / `bridge.go` changed
(reservation-truth + serialized `success`), so the prebuilt xcframework/.aar are
stale:

```bash
# 1. Regenerate gomobile bindings.
cd go-mknoon && PATH="$PATH:$(go env GOPATH)/bin" GOTOOLCHAIN=go1.25.0 make all
cd ../ios && pod install && cd ..
cd go-mknoon && make verify-bindings ; cd ..

# 2. Profile builds with flow logging on.
flutter build apk --profile --dart-define=FDC_FLOW_LOG=1 --dart-define=MKNOON_ENABLE_NATIVE_MDNS=true
flutter build ios --profile --dart-define=FDC_FLOW_LOG=1 --dart-define=MKNOON_ENABLE_NATIVE_MDNS=true
```

## Rig

- Pixel 6 (Alice, cellular): `adb -s 21071FDF600CSC logcat | grep -E 'FLOW|RELAY_|HEALTH|DRAIN|RECOVERY'`
- iPhone 11 (Bob, WiFi): `idevicesyslog -u 00008030-001A6D2801BB802E | grep -E 'FLOW|RELAY_|HEALTH|DRAIN|RECOVERY'`
- Prod relay journal (read-only): `ssh -i se.pem ubuntu@13.60.15.36` → follow the
  relay service journal; watch `Peer connected/disconnected` cadence and
  `retrieve_pending`/ack lines for both peer IDs (recipe in project memory).
- New flow anchors added by 189 (grep-verified in code):
  `RELAY_RECOVERY_BACKOFF_SKIP{backoffStep,skipsRemaining,consecutiveRefreshFailures}`,
  `P2P_HEALTH_CHECK_RECOVERY_FAILED{errorCode,consecutiveRefreshFailures}`; Go log
  lines `accepting explicit reservation as circuit truth ✓` and
  `Manual reservation opened for <relay> (hold until …)`.
- ⚠ Run AFTER any 173 relay redeploy, so relay-side changes are not conflated
  into these measurements (plan §Dependency Impact).

## TC-189-30 (PROD-CRITICAL) — receiver drains while degraded; no 30 s flap

Repeat the 2026-07-02 incident protocol (Pixel cellular, iPhone WiFi, both
foreground, receiver IDLE — no sends, no resume, no network toggles on the
receiver side):

1. Bring both apps foreground, confirm both connected to the prod relay
   (journal shows both peers).
2. From the Pixel, send 3–5 messages to the iPhone spaced ≥1 min apart. The
   iPhone must NOT be touched (no send, no background/resume).
3. **Expected (was 86–368 s / >10 min):** each message's relay store→ack gap
   ≤35 s (one 30 s health-check interval + drain), p95 ≤35 s.
4. Watch the relay journal for 10 minutes: **no metronomic 30 s
   `Peer connected/disconnected` flap** for either peer (was :10/:40 Pixel,
   :15/:45 iPhone).
5. On each phone capture `watchdogRestartCount` from `relay:state`/status FLOW
   at start and after 30 min: **Δ ≤ 2** (was ~60/30 min).
6. If a device enters the degraded-relay state, expect per-tick
   `RELAY_RECOVERY_START` (or `RELAY_RECOVERY_BACKOFF_SKIP` once backed off)
   ALWAYS paired with an inbox drain (`P2P_INBOX_RETRIEVE_PENDING_REQUEST`),
   and `RELAY_OUTAGE_TIMING phase=recovered` ONLY when the relay actually
   reports online afterward (no more false `recovered` every 30 s).

PASS = store→ack p95 ≤35 s with the receiver idle, no 30 s relay flap over
10 min, `watchdogRestartCount` Δ ≤2 over 30 min.

## TC-189-31 — reverse direction stays fast

iPhone → Pixel with the Pixel foreground: store→ack unchanged at 0–2 s (FCM
foreground push → drain). Confirms Fix A/B did not disturb the healthy path.

PASS = 0–2 s (unchanged from the 2026-07-02 baseline).

## TC-189-50 — autorelay non-publish diagnostic capture (carried, not blocking)

Why does relayFinder never publish `/p2p-circuit` on these devices under
default flags (Private reachability)? Host finding (2026-07-02, this plan's
execution): go-libp2p v0.39.1 `cleanupAddressSet` (autorelay/addrsplosion.go)
publishes circuit addrs ONLY for relay addresses that are public or DNS — the
prod relay IS `/dns/mknoun.xyz/…`, so the on-device trigger must be something
else (e.g. peerstore addr set at publish time, reservation churn). Capture:

1. **--profile build ONLY** (⚠ NEVER `--debug` on the phones — dev_keychain_wipe
   nukes identity+DB key on first debug launch) with
   `GOLOG_LOG_LEVEL=autorelay=debug` exported into the Go runtime env (or an
   equivalent logging-profile dart-define plumbed to the Go side).
2. Reproduce a degraded episode (toggle WiFi→cellular), capture 5 min of
   relayFinder `found node` / `adding new relay` / backoff lines.
3. Attach the capture + a one-paragraph reading to this runsheet's Result log.

## Result log

| Date | Tester | TC-189-30 | TC-189-31 | TC-189-50 capture | Build SHA | Notes |
|---|---|---|---|---|---|---|
| | | | | | | |
