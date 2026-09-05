# Plan 401 — Voice call: caller-side ringback tone (TDD)

Status: CLOSED 2026-09-05 15:19Z — proven on device (user: "works ! I can hear it ringing")
Origin: user report 2026-09-05 — "when I call from iPhone 11 to the Pixel or iPhone 13 and put the phone on my ear, I hear no sign that I am calling and that it rings on the other side."
Evidence: `Test-Flight-Improv/evidence/401/`

## Problem

Ringback is the tone a caller hears while the far end rings. The app had none on any platform: the outgoing screen only switched from "Calling" to "Ringing" (`outgoing_call_screen.dart:92`) when the callee's `ringing` signal arrived. Neither CallKit nor Android Telecom plays ringback for an app's own VoIP call; the app must. The PRD (§11.1) only specified the labels.

## Design

- **Policy (Dart, pure):** `ringbackWanted(session)` = outgoing direction AND state `ringing` AND not terminal. `inviting` stays silent (the far end has not confirmed ringing yet); `accepted` and later stop it. Only the caller ever hears it.
- **Coordinator (Dart, `lib/features/call/application/call_ringback_coordinator.dart`):** turns call snapshots into exactly one `start` and one `stop` per ringing outgoing call, runs port calls one at a time in order (a stop can never overtake its start), reports each outcome (`ok|refused|failed`) as `CALL_RINGBACK_RESULT`. A refused/failed start is not retried per snapshot; a failed stop keeps the coordinator armed so the next snapshot and `dispose` retry. Wired in `ProductionCallSignalingGraph` (`_onSessionSnapshot` feeds it first; `close()` disposes it).
- **Channel (`mknoon/call_ringback`, methods `start`/`stop`, `{version: 1, callHandle: <Dart call id>}`):** `MethodChannelCallRingbackPort`; a platform without a tone player (`MissingPluginException`) answers false and the call carries on silent.
- **iOS (`MknoonCallKitController.startRingback/stopRingback`, bridge cases `startRingback`/`stopRingback`):** plays only for the outgoing call CallKit knows, only once CallKit activated the call audio session (a wanted ringback before activation starts in `didActivate`), never after media claimed the call. Silenced natively on the media claim and on every terminal path; paused on session deactivation and resumed on re-activation. Tone: `MknoonCallRingbackTonePlayer`, an `AVAudioPlayer` looping a synthesised WAV (425 Hz, 1 s on / 4 s off, 16 kHz mono, 10 ms ramps) through the call session, so it follows the call route (earpiece when the phone is at the ear) and ignores the silent switch like any call audio.
- **Android (`MknoonOutgoingCallRingback`, bridge cases `startRingback`/`stopRingback`, runtime wiring in `MknoonCallAndroidRuntime`):** one best-effort `ToneGenerator(STREAM_VOICE_CALL, 70).startTone(TONE_SUP_RINGTONE)` session keyed by the Dart call handle (works with or without a Telecom connection); the runtime's native answer/terminal path (`stopIncomingRinger` hook) also stops it. Diag tag `MknoonCallRingback`.

## TDD rows

| Row | RED | GREEN | Evidence |
|---|---|---|---|
| Dart `call_ringback_coordinator_test.dart` (9) + `call_ringback_channel_test.dart` (6) | files missing: `Type 'CallRingbackCoordinator' not found`, `Undefined name 'MethodChannelCallRingbackPort'` | 15/15 | `dart_ringback_red_2026-09-05.txt`, `dart_ringback_green_2026-09-05.txt` |
| Kotlin `MknoonOutgoingCallRingbackTest` (4) + `MknoonCallNativeBridgeRingbackTest` (2) | `Unresolved reference 'MknoonOutgoingCallRingback'`, `No parameter with name 'ringbackStarter'` | 4/4 + 2/2; call-package JVM suite 13 suites, 122 tests, 0 failures | `kotlin_ringback_red_2026-09-05.txt`, `kotlin_ringback_green_2026-09-05.txt` |
| Swift lifecycle ×5 (`testRingbackWaitsForCallKitToActivateTheOutgoingCallAudio`, `…PlaysAtOnceOnAnActivatedSessionAndStopsExactlyOnce`, `…IsRefusedForIncomingUnknownAndTerminalCalls`, `testMediaClaimAndTerminalStopTheRingbackWithoutDart`, `testDeactivationSilencesTheRingbackAndReactivationResumesIt`) + bridge ×1 | `cannot find type 'MknoonCallRingbackPlaying'`, `extra argument 'ringback'` | lifecycle suite 52 tests / 0 failures, bridge suite 12 / 0 | `swift_ringback_red_2026-09-05.txt`, `swift_ringback_green_2026-09-05.txt` |

## Gates

- `tdd_context.py affected` names `call_signaling_composition_test`, `production_call_signaling_graph_diagnostics_test`, `production_call_signaling_graph_live_call_guard_test` plus the two new files: 92/92 (`dart_affected_2026-09-05.txt`).
- New Dart tests registered in `ONE_TO_ONE_TESTS` and `ONE_TO_ONE_HOST_TESTS` (also the previously unregistered `ios_call_wake_channel_test.dart` from plan 400 (b)).
- `flutter analyze` on the changed files: 0 issues; `dart format` clean.
- Host `1to1` batch (`--batch-flutter --concurrency 4`): PASS, 194 test paths, 3323 passed / 4 skipped / 0 failed (`host_1to1_batch_ringback_2026-09-05.txt`).
- Architecture graph refreshed (`--incremental`).

## Device proof (user-driven)

1. iPhone 11 → iPhone 13 (locked and unlocked) and iPhone 11 → Pixel: after the far end starts ringing, the iPhone 11 earpiece plays the 425 Hz cadence until the callee answers; the tone stops within a second of the answer and never overlaps the voice. Syslog: `[MKNOON_CALLKIT_DIAG] ringback=started` … `ringback=stopped reason=media` (answered) or `reason=terminal` (cancelled/timeout). Flow log: `CALL_RINGBACK_RESULT {"action":"start","outcome":"ok"}` then `{"action":"stop","outcome":"ok"}`.
2. Pixel → iPhone: the Pixel plays the platform ringback tone on the voice-call stream; logcat tag `MknoonCallRingback` shows `ringback stage=start result=playing` then `stage=stop result=stopped` (or `stage=lifecycle` when Telecom ends the call first).
3. Cancel from the caller while ringing: tone stops at once, nothing rings on after hang-up.
4. Speaker/headset route during ringing: the tone follows the route.

## Device finding 2026-09-05 15:01Z — no tone on the first deploy (channel mismatch)

Capture `docker-ws/deploy-captures/fresh-260905170004/`: iPhone 11 → iPhone 13, `remoteRinging` at 15:01:10.09, then `CALL_RINGBACK_RESULT {"action":"start","outcome":"refused"}` and no native `ringback=` line at all; `audio_session=latched` followed 180 ms later. The Dart port invoked `mknoon/call_ringback`, a channel nobody serves natively; the native methods live on the lifecycle bridges (`mknoon/ios_call_lifecycle`, `mknoon/android_call_lifecycle`), so the call returned `MissingPluginException` → false. Each language's tests were green; nothing pinned the cross-language contract.

| Row | RED | GREEN | Evidence |
|---|---|---|---|
| `call_ringback_channel_test.dart` rewritten: `MethodChannelCallRingbackPort.ios()/.android()` must use the adapters' `methodChannelName`, methods `startRingback`/`stopRingback`; a source census reads `MknoonCallNativeBridge.swift` and `.kt` and requires those channel constants and `case`/`->` handlers | `Member not found: 'MethodChannelCallRingbackPort.ios'` | contract + coordinator + affected graph suites 93/93; analyzer clean | `dart_ringback_channel_contract_red_2026-09-05.txt`, `dart_ringback_channel_contract_green_2026-09-05.txt` |

Graph wiring now picks the port from the native lifecycle adapter that exists (`iosLifecycleAdapter` → `.ios()`, `androidLifecycleAdapter` → `.android()`, else none). Lesson recorded in memory: the container's view of capture files written on the Mac lags by minutes — grep them on the Mac (`docker-ws/capture_grep.sh`).

## Device finding 2026-09-05 15:09Z — still no tone: the port named the call by its id

Capture `docker-ws/deploy-captures/fresh-260905170844/`: the request now reached the lifecycle bridge (`CALL_RINGBACK_RESULT {"action":"start","outcome":"failed"}` 4 ms after `remoteRinging`) but still no native `ringback=` line: the bridge answered `bad_args` before the controller ran. The native side knows a call only by the authenticated signaling handle the lifecycle adapter registered (`signalingContextStore.read(callId)?.callHandle`), never by the Dart `CallId`; the port sent the raw id, which `resolveCallHandle` cannot map.

| Row | RED | GREEN | Evidence |
|---|---|---|---|
| `call_ringback_channel_test.dart`: every port takes `resolveCallHandle` (the adapters' `AuthenticatedCallHandleResolver`); the wire carries the resolved handle and never the call id; a call without a handle is refused with no native call | `No named parameter with the name 'resolveCallHandle'` | contract 9/9 + coordinator 9/9; composition, graph diagnostics and live-call guard suites green in the same run | `dart_ringback_handle_red_2026-09-05.txt`, `dart_ringback_handle_green_2026-09-05.txt` |

Graph wiring passes the same resolver closure the lifecycle adapters get. Third deploy: `docker-ws/deploy_three_phones_ringback_r3_result.txt`.

## Device proof 2026-09-05 15:18Z — heard on the phone, matched in the captures

Captures `docker-ws/deploy-captures/fresh-260905171744/`, evidence `ringback_device_proof_2026-09-05.txt`.

| Caller | Far end rings | Tone | Stop |
|---|---|---|---|
| iPhone 11 (build `1.0.0-4ba725d42.d12.flowlog.t260905171408`) | `remoteRinging` 15:18:55.362 (session latched 6 ms earlier) | `[MKNOON_CALLKIT_DIAG] ringback=started` 15:18:55.470, `CALL_RINGBACK_RESULT start ok` | callee ended the call at 15:19:03.567: native `ringback=stopped reason=terminal` before `terminal=remoteCancelled`; Dart's own stop then answered `refused` (nothing left to stop), which the coordinator treats as silence |
| Pixel (build `1.0.0-3cc20cd6e.d7.t260905171659`) | `remoteRinging` 15:19:16.194 | `MknoonCallRingback: ringback stage=start result=playing` 15:19:16.245, `start ok` | 15:19:19.243 `stage=stop result=stopped`, `stop ok` |

Rows 1 and 3 of the device-proof profile are covered (tone while ringing; instant stop on a terminal). Rows 2 (Pixel → iPhone acoustics) and 4 (route change during ringing) were not separately observed.

## Known limits

- The tone cadence is fixed (European 425 Hz 1/4 s) on iOS; Android uses the platform's regional `TONE_SUP_RINGTONE`.
- No ringback while `inviting` (before the callee confirms ringing). If the callee is unreachable the caller stays silent until the ring timeout, as before.
