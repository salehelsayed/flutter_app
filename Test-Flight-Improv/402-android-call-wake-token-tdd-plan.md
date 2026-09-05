# Plan 402 — Android call wake token: publish the FCM token as the relay's standard call token (TDD)

Status: implemented 2026-09-05 (device proof pending)
Origin: user report 2026-09-05 — "sometimes after I lock the Pixel for a while and call it from iPhone 11, I hear no ringback on the iPhone and the Pixel receives nothing."
Evidence: `Test-Flight-Improv/evidence/402/`

## Problem

The relay wakes an Android callee only through a `standard_call` token record (`ClaimWake`, Android branch: `standard == nil → no route`). Nothing in the app published one: the relay's call registry held four `ios_voip` records and no `standard` record for the Pixel (`exists relay:call:v1:token:<pixel>:standard` = 0), the Pixel's start-up log had only the messaging push token (`P2P_SERVICE_REGISTER_PUSH_TOKEN_SUCCESS`), and `lib/` defined `CallTokenKind.standardCall` without a publisher (iOS has `IosVoipTokenCoordinator`). VC2-02 §9 planned "Android call capability can share the platform FCM token" but it was never wired.

While the Pixel's live relay connection is up, the invite goes direct (`sendMessageWithReply`, 5 s ack) and works. Once the phone has been locked long enough for that connection to drop, the invite is stored in the mailbox and the wake is skipped silently (no relay log, no metric, no wake status in the caller's receipt). The Pixel never rings, never sends `ringing`, so the iPhone plays no ringback and times out after 45 s.

## Design

- `AndroidCallTokenCoordinator` (`lib/features/call/infrastructure/android_call_token_coordinator.dart`) publishes the FCM token as `CallTokenRecord(kind: standardCall, platform: android, expiresAtMs: now + 30 d)` — no environment, topic, capability version or refresh epoch, exactly the shape the relay's `validCallTokenFields` accepts. `start()` subscribes to `onTokenRefresh` and publishes once; `ensurePublished()` (called on every capability advertisement) republishes only a changed token or one older than half its registration; outcomes `published|unchanged|no_token|deferred|rejected|failed` reach the flow log as `CALL_ANDROID_TOKEN_PUBLISH_RESULT`. Publication respects the network-effects gate, never throws, and never blocks the endpoint advertisement (direct calls work without a token).
- Never revoked on close: the relay must keep waking the app after the process is gone.
- Wiring in `ProductionCallSignalingGraph`: created when the Android native lifecycle is enabled (`androidCallTokenCoordinatorFactory`, default `_createFirebaseAndroidCallTokenCoordinator` reading `FirebaseMessaging.instance.getToken()` lazily); `start()` starts it, `advertiseCapability()` calls `ensurePublished()` at the new `android_call_token` stage, `close()` closes it. A refresh stream whose `listen` throws (Firebase not initialised) is tolerated and retried on the next publication.

## TDD rows

| Row | RED | GREEN | Evidence |
|---|---|---|---|
| `android_call_token_coordinator_test.dart` (7): record shape, no token, half-registration renewal, rejected/failed retry, refresh republish, network gate, close never revokes | types missing | 7/7 | `dart_android_call_token_red_2026-09-05.txt`, `dart_android_call_token_green_2026-09-05.txt` |
| composition wiring test `an Android graph publishes the FCM token as the relay standard call token` (`call_token_set_v1` before `call_endpoint_set_v1`, payload `{standard_call, android, token, now+30 d}`, published once, no revoke on shutdown) | mutation: graph `start`/`advertise` not calling the coordinator → `did not find … 'call_token_set_v1'` | composition suite | `dart_android_call_token_wiring_mutation_red_2026-09-05.txt`, `dart_android_call_token_wiring_green_2026-09-05.txt` |
| `a refresh stream that throws on listen is tolerated and retried later` (found by the composition suite on a Firebase-less host: `[core/no-app]`) | `Bad state: [core/no-app] no Firebase app` escaped `start()` | unit 8/8 + composition + graph diagnostics + live-call guard: 86/86 | `dart_android_call_token_listen_red_2026-09-05.txt`, `dart_android_call_token_affected_green_2026-09-05.txt` |

## Gates

- `tdd_context.py affected` set (composition, graph diagnostics, live-call guard, unit): 86/86; `flutter analyze` clean; `dart format` clean.
- New test registered in `ONE_TO_ONE_TESTS` and `ONE_TO_ONE_HOST_TESTS`.

## Device proof (user-driven)

1. After the Pixel redeploy, the relay probe (`python3 docker-ws/relay_ssh.py < docker-ws/relay_call_registry_probe.sh`) lists `relay:call:v1:token:<pixel>:standard` and the Pixel log shows `CALL_ANDROID_TOKEN_PUBLISH_RESULT {"outcome":"published"}`.
2. Killed-app wake: Pixel app sent to the background and its process killed (`am kill`, not force-stop), then iPhone 11 calls the Pixel: the iPhone's invite falls back to the mailbox, the relay sends the FCM wake, the Pixel rings (headless admission), and the iPhone plays ringback.
3. The original scenario: Pixel locked "for a while", then called.

## Follow-ups (not in this plan)

- Endpoint records expire 6 h after the last advertisement and are refreshed only on start/resume: a phone left locked longer loses its wake route on both platforms.
- The relay skips an unroutable wake silently; a log line or metric is needed.
- The full-screen incoming-call permission prompt on Android 14+ (separate finding).
