# UI-24 Android + iOS Simulator Validation

Date: 2026-09-03 (Europe/Berlin)

## Outcome

PASS for two-way 1:1 call signaling, answer/end UI lifecycle, connected WebRTC media, and relay-only RTP between:

- Physical Pixel 6: `21071FDF600CSC` (Android API 36)
- iOS Simulator iPhone 17 Pro: `674DFFF6-5F38-4235-93F6-AF7FBF86AE65` (iOS 26.5)

Both directions were exercised:

1. Pixel caller -> iOS Simulator callee: answered on iOS, both peers reached Connected, and ending on iOS restored both conversation screens.
2. iOS Simulator caller -> Pixel callee: answered through the Android system notification, the Pixel retained the in-call screen and reached Connected, and ending on Pixel restored both conversation screens.

The second direction directly covers the reported regression where answering on the Pixel previously returned to the normal chat screen.

## Runtime topology

- Local signaling relay PID: `47049`
- Relay listen address: TCP `*:4005`
- Relay multiaddress: `/ip4/192.168.0.60/tcp/4005/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g`
- Local Coturn container: `mknoon-vc205-turn-sandbox`
- TURN listener: UDP/TCP `3478`
- TURN relay allocation range: UDP `49160-49200`
- Pixel, iOS Simulator Runner, and the relay had established local TCP signaling connections at final verification.

## Deterministic media evidence

The Android production observer sampled WebRTC `getStats()` during each connected call. In both directions it recorded:

- active call UI observed
- structural media readiness observed
- local audio track enabled
- selected relay transport `turn_udp`
- relay-only route observed
- inbound audio RTP packets and bytes greater than zero
- outbound audio RTP packets and bytes greater than zero
- terminal state observed after hangup

Forward-call receipts:

- `pixel-live-rtp-observer.jsonl`
- `pixel-forward-observer-stop.json`
- `coturn-live-media-counters.txt`
- `coturn-post-call-counters.txt`

Reverse-call receipts:

- `pixel-reverse-proof-observer-arm.json`
- `pixel-reverse-proof-observer-live.json`
- `pixel-reverse-proof-observer-stop.json`
- `coturn-reverse-proof-live-counters.txt`
- `coturn-reverse-proof-post-counters.txt`

During the reverse call, Coturn changed by +116,872 received bytes / +979 received packets and +99,605 transmitted bytes / +719 transmitted packets over five seconds. After hangup, the equivalent five-second sample had zero byte and packet deltas and no relay allocation sockets.

This proves bidirectional RTP flow through the media pipeline and TURN. It does not prove human-perceived acoustic audibility through an iOS Simulator speaker/microphone. That final acoustic claim requires two physical endpoints or a deterministic audio injection/capture oracle.

## UI and signaling evidence

Forward Pixel -> iOS Simulator:

- `ios-connected-valid-call.png`
- `pixel-after-ios-end.png`
- `ios-after-end.png`
- `pixel-valid-call-complete.log`
- `ios-valid-call-complete.log`
- `valid-call-key-events.log`

Reverse iOS Simulator -> Pixel:

- `pixel-reverse-proof-incoming.png`
- `pixel-reverse-proof-answer-node.xml`
- `pixel-reverse-proof-connected.png`
- `ios-reverse-proof-connected.png`
- `pixel-reverse-proof-after-end.png`
- `ios-reverse-proof-after-pixel-end.png`
- `pixel-reverse-proof-complete.log`
- `pixel-reverse-proof-key-events.log`

`pixel-reverse-no-answer-automation-miss.log` is retained for diagnostic history only. That attempt timed out because the automation had not opened the Android notification shade; it is not product-failure evidence. The succeeding run opened the shade and tapped the exact `com.android.systemui` Answer action.

## Build configuration findings

- Android must be built with `--android-project-arg=enableAndroidNativeCalls=true`. The earlier manually built APK omitted this generated BuildConfig value and therefore correctly surfaced `Voice calling is unavailable right now`. The installed APK was rebuilt with the value enabled.
- The iOS Simulator must use `VOICE_CALL_IOS_NATIVE_ENABLED=false`. Enabling native CallKit on this simulator caused the OS call service to auto-decline because the simulator cannot host the physical-device CallKit path. This does not apply to the physical-iPhone build.
- Installed Android APK SHA-256: `8b6f396716315a1cabb91bbab863b9a43178496b162a5ec20a4a137e84290647`

## Automated gates

All Go commands and Go-backed Android Gradle tasks below ran with `GOTOOLCHAIN=go1.25.0`.

- Focused Flutter suite: PASS, 132 passed and 1 intentional skip.
- Call lifecycle/signaling Flutter suite: PASS, 61 passed.
- `mknoon` Go packages `./bridge ./node ./nsebridge`: PASS.
- `relay-server` `go test ./...`: PASS.
- Android `:app:buildGoAar --rerun-tasks`: PASS.
- Android call and Firebase unit-test selection via `:app:testDebugUnitTest`: PASS.

## Final live state

At handoff, there is no active call. Both apps remain running on their conversation screens, the local relay remains listening on port 4005, and local Coturn remains running.
