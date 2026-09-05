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

## Device finding 2026-09-05 15:50Z — the wake works, the hang-up did not end the ring

With the token in place, iPhone 11 → killed Pixel app: the invite went to the mailbox (`mailboxStored: true`), the FCM wake started a headless admission, the Pixel rang at 17:50:35. The caller hung up at 15:50:36; the terminate was stored behind the unacknowledged invite and its wake started a second admission at 17:50:37.6, which reported success while the Pixel rang on until a timeout at 17:51:10.

Cause (capture `fresh-260905174750`, relay probe, code): the second admission retrieved the page and stopped within 18 ms without a single crypto call. `IncomingCallPrePresentationAdmission.authenticateMailboxEvent` requires every row's expiry to equal the wake's (`wakeExpiresAtMs != event.expiresAtMs` → `permanentReject`), and `MailboxProductionHeadlessCallAdmissionSession._evaluateOnce` aborted the whole evaluation on the first failing row. The terminate's wake carried the terminate's expiry; the invite row (stored 6 s earlier, its own expiry) came first, so the page was judged `permanentReject` and the terminate was never authenticated. The relay was innocent: `TestCallRetrieveReturnsTerminateBehindAnUnackedInvite` (new, green by construction) pins that both rows are returned.

Fix: the session judges every row. The wake binds only the row it was issued for; other rows of the same call are authenticated against their own expiry (the per-row guard stays as pinned by its test). An authenticated reject/terminate dominates → `terminal` (the worker's existing `terminalizeAuthenticated` ends the Telecom call); an unjudged (deferred) row defers the page; exactly one bound invite → `admitted`; a companion invite without a bound row → `emptyOrAlreadyAcked` (a stale wake never re-rings).

| Row | RED | GREEN | Evidence |
|---|---|---|---|
| `production_headless_call_admission_test.dart` +4: terminate wake behind an earlier invite → `terminal` (bindings `[E1, E2]`); stale wake → `emptyOrAlreadyAcked`; terminate stored after the invite wake → `terminal`; deferred companion → `deferred` | three `Actual: permanentReject` | 11/11; analyzer clean | `dart_headless_terminate_red_2026-09-05.txt`, `dart_headless_terminate_green_2026-09-05.txt` |
| relay `call_terminate_after_unacked_invite_test.go` | (contract pin, green) | pass | — |

Device proof pending: killed Pixel app, iPhone 11 calls, hangs up while ringing → the Pixel stops ringing within ~2 s (`MknoonCallRingtone stage=lifecycle result=stopped` right after the second `HeadlessCallAdmissionWorker`).

## Device findings 2026-09-05 16:10Z — three more (after the terminate fix worked)

User: (1) killed-app Pixel rings and now stops on hang-up, but the iPhone 11 hears no ringback; (2) a locked Pixel later showed no incoming call at all; (3) iPhone → iPhone ringback fine. Capture `docker-ws/deploy-captures/fresh-260905180840/`.

**(c) An ended headless call blocked the next presentation (report 2).** The locked Pixel's wake ran an admission that verified and decrypted the new invite and then presented nothing: the previous call's descriptor (ended natively, never acknowledged because headless admission has no Dart owner) was still on disk, so `PendingNativeCallStore.create` answered `Busy` and `presentAuthenticated` silently returned false. Fix: `create` retires a stored descriptor whose call already ended exactly as a terminal acknowledgement would (receipt, then deletion), so the next call replaces it, a late acknowledgement still succeeds through the receipt, and the old wake stays a duplicate. `MknoonCallAndroidRuntime.present` now logs `MKNOON_CALL_PRESENTATION_DIAG result=<…>` (tag `MknoonCallPresentation`).

| Row | RED | GREEN | Evidence |
|---|---|---|---|
| `PendingNativeCallStoreTest`: ended call never blocks the next call and leaves its receipt; a live call still makes another busy; controller presents the next call after a headless call ended (real store) | two tests FAILED (`Busy`/`BUSY`) | call package BUILD SUCCESSFUL | `kotlin_orphaned_terminal_red_2026-09-05.txt`, `kotlin_orphaned_terminal_green_2026-09-05.txt` |

**(d) No ringback on the wake path (report 1).** A headless callee rings from the relay's wake but sends `ringing` only once it is answered, so the caller's `remoteRinging` never comes. The relay now reports the wake outcome on the store receipt (`CallStoreReceipt.WakeStatus`: `dispatched` after a successful push, `failed` after a refused one, empty when nothing was sent), surfaced on the wire as `wake` — opt-in through the client's `wakeReceipt` request flag because both wire decoders refuse unknown fields (deploy the relay first). The Go node asks for it and passes it through (`CallStoreReceipt.Wake`, bridge key `wake`); the Dart mailbox client reads `CallMailboxWakeStatus`; the signaling service dispatches `CallEventType.wakeRequested` after `mailboxStored` when the wake was dispatched; the reducer turns `inviting` + `wakeRequested` into `ringing` (the outgoing screen shows Ringing and the ringback plays), and a later `remoteRinging` is the usual duplicate. The relay is also no longer silent about a skipped wake: the receipt says so.

| Row | RED | GREEN | Evidence |
|---|---|---|---|
| relay `TestCallStoreReceiptReportsTheWakeOutcome` (dispatched / failed / attached-skip) | mutation (status never set): `dispatched wake receipt = ""` | pass + full suite + race | `relay_wake_status_mutation_red_2026-09-05.txt`, `relay_wake_receipt_green_2026-09-05.txt` |
| relay handler `TestCallStoreResponseCarriesTheWakeOutcomeOnlyWhenAsked` | (opt-in written with the feature) | pass | same |
| go node `TestCallStoreReceiptCarriesTheWakeOutcome` (+ request opts in, unknown value rejected) + bridge map | `receipt.Wake undefined`, `unknown field Wake` | node + bridge suites ok | `go_wake_receipt_red_2026-09-05.txt`, `go_wake_receipt_green_2026-09-05.txt` |
| Dart: mailbox client `wake` parse; reducer `inviting + wakeRequested → ringing` (+ outside inviting unchanged); service dispatches `…:wake-dispatched` and the session rings | `Undefined name 'CallMailboxWakeStatus'` | 78/78 in the three files; affected dependents 135/135 | `dart_wake_receipt_red_2026-09-05.txt`, `dart_wake_receipt_green_2026-09-05.txt`, `dart_wake_receipt_affected_2026-09-05.txt` |

Deploy order: relay v1.10.5 (`docker-ws/deploy_relay_v1105.sh`) BEFORE any phone build; then Pixel (c)+(d) and both iPhones (d, ringback on the wake path to a Pixel).

## Device findings 2026-09-05 16:47Z–17:00Z — (d) shipped twice without effect, then found

Two more reasons the caller never rang back, both invisible to per-layer tests:

1. **The iPhone linked the previous Go framework.** `ensure_go_ios_bindings.sh` rebuilt `GoMknoon.xcframework` during the Xcode build (18:46:50, symbol present), but the GoMknoon Pod had already copied the older slice into the build products, so the Runner (18:47) carried `call_store_v1` and no `wakeReceipt`. The store request never opted in and the relay, correctly, omitted `wake`. Fix `d3af2c01f`: the flowlog, iOS-only and fresh-three-phones scripts run `scripts/ensure_go_ios_bindings.sh` before `flutter build ios`; `docker-ws/binding_probe.sh <literal>` proves what a build carries (Runner binary count, xcframework mtime, AAR .so count). Second iPhone build `1.0.0-8ac7078d3.d8.flowlog.t260905185610`: Runner count 1.
2. **Production never ran the service's receipt dispatch.** With the binding right, the caller still logged only `mailboxStored`: the production adapter (`ProductionCallControlSignalingAdapter.send`) uses `CallSignalingService.transmit()` and the executor dispatches its own single follow-up, so `_dispatchReceipts` (where (d) put `wakeRequested`) is dead in production. Fix: `CallControlSendResult.wakeDispatched` (adapter maps it; visible in the send diagnostics), the executor's invite follow-up is `wakeRequested` instead of `mailboxStored` when the wake was dispatched, and the reducer confirms mailbox custody on `wakeRequested` before ringing; the store leg's `CALL_SIGNALING_LEG_RESULT` prints the wake value the relay answered.

| Row | RED | GREEN | Evidence |
|---|---|---|---|
| executor `a dispatched wake turns the mailbox custody follow-up into ringing` | `No named parameter with the name 'wakeDispatched'` | 194 → 196 across executor, adapter, reducer, service, client, composition, coordinator | `dart_wake_executor_path_red_2026-09-05.txt`, `dart_wake_executor_path_green_2026-09-05.txt` |
| adapter `the relay wake outcome reaches the executor result without a receipt of its own`; reducer custody on `wakeRequested` | mutation (mapping removed / custody removed) | same | `dart_wake_executor_path_mutation_red_2026-09-05.txt` |

Lesson: a cross-layer feature needs one end-to-end proof on the production path (here: caller flow log shows `trigger: wakeRequested` → `ringing`), not seven green layers.

## Follow-ups (not in this plan)

- Endpoint records expire 6 h after the last advertisement and are refreshed only on start/resume: a phone left locked longer loses its wake route on both platforms.
- The relay skips an unroutable wake silently; a log line or metric is needed.
- The full-screen incoming-call permission prompt on Android 14+ (separate finding).
