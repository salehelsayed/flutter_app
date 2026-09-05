# Plan 404 — Android headless decline reply: a natively declined call answers the caller (TDD)

Status: implemented 2026-09-05; first deploy 18:19Z refuted on device (reply rode the call id as handle), fixed 18:45Z (device proof pending the next deploy)
Origin: user report 2026-09-05 — "when canceling the call from pixel, the ringback on iphone keeps going".
Evidence: `Test-Flight-Improv/evidence/404/`

## Problem

Captures `docker-ws/deploy-captures/fresh-260905194144/` (plan 403 build, Pixel app killed, phone locked), local time UTC+2:

| Local | Side | What happened |
|---|---|---|
| 19:44:07 | iPhone 11 | invite stored, `wakeRequested` → ringing, ringback started |
| 19:44:11 | Pixel | headless worker: `call_retrieve_v1`, `MKNOON_CALL_PRESENTATION_DIAG result=PRESENTED`, ringtone playing |
| 19:44:14 | Pixel | user declines from the notification: `CALL_ANDROID_DISCONNECT source=explicit_end`, Telecom `DisconnectCause REJECTED`. No `call_store_v1`, no `reject` anywhere |
| 19:44:19 | iPhone 11 | still ringing back; the user cancels (`trigger: cancel, endReason: callerCancelled`) |
| 19:44:20 | Pixel | the caller's terminate wakes the worker: retrieve, `call_ack_v1` |

With the app killed, the call is presented by `HeadlessCallAdmissionWorker` and nothing Dart runs afterwards. The notification's Decline action reaches `MknoonCallActionReceiver` → `MknoonCallLifecycleController.terminate(DECLINE_REQUESTED)`, which ends the Telecom call and journals the decline for a Dart adoption that never comes (a later app start settles the terminal record without replaying it, `settleUnconsumableTerminalBeforeAttach`). Nobody sends the caller a `reject`, so the caller rings back until its own cancel or the 30 s no-answer timeout. The foreground path is unaffected: an adopted Dart lifecycle turns the decline into `CallEffectType.sendReject`.

## Design

A second headless run, the **decline reply**, reuses the admission runtime (SQLCipher identity, Go node, envelope crypto, trusted roster, mailbox client) and adds only what a reply needs.

- **Kotlin** (`android/app/src/main/kotlin/com/mknoon/app/call/`):
  - `MknoonCallLifecycleController` gains `onDeclineWithoutOwner: (PendingNativeCallDescriptor) -> Unit`. `terminateInternal` invokes it once for a first durable `DECLINE_REQUESTED` on a presented call that has no adopted Dart lifecycle. Other terminal types and adopted lifecycles never trigger it.
  - `MknoonCallRuntime` wires it to `HeadlessCallAdmissionWorkScheduler.enqueueDeclineReply(descriptor)`: the same unique work name as the call's admission job (`APPEND_OR_REPLACE`, so it runs after any pending admission job), expedited, network-constrained, input keys `call_id`, `wake_handle` (the descriptor's native wake handle), `expires_at_ms` (the invite's expiry) and `mode = decline_reply`.
  - `HeadlessCallAdmissionExecution.parseInput` accepts exactly the three admission keys, or those plus `mode = decline_reply`; any other mode value builds no engine. `HeadlessCallAdmissionRunIdentity.mode` reaches `FlutterHeadlessCallAdmissionEngineRunner`, which passes `decline_reply` as a fifth Dart argument. A decline-reply completion is authenticated exactly like an admission one but never presents or terminalizes.
- **Dart**:
  - `HeadlessCallAdmissionInvocation.parse` accepts four arguments (admission) or five with `decline_reply` (`HeadlessCallAdmissionMode`); the completion identity payload is unchanged.
  - `MailboxProductionHeadlessCallAdmissionSession` routes by mode. `_declineReplyOnce` retrieves the call's rows, authenticates each against its own expiry, and: acknowledges and reports `terminal` when the caller already ended the call; otherwise hands the authenticated invite (`HeadlessAuthenticatedMailboxEvent.signal`) to the `HeadlessDeclineReplySender`; on delivery acknowledges the rows and reports `terminal`; on no delivery leaves the rows and reports `deferred`; with no invite reports `permanentReject` (or `deferred` when a row could not be judged); empty page → `emptyOrAlreadyAcked`. Flow event `CALL_HEADLESS_DECLINE_REPLY_RESULT {outcome: sent|already_ended|unsent|no_invite|invite_deferred|no_sender|empty|page_incomplete|retrieve_failed|error}`.
  - `HeadlessCallDeclineReplyTransmitter` (`lib/features/call/application/headless_call_decline_reply.dart`) builds the reply from the invite: `reject`, reason `declined`, sender sequence 1, the invite's ICE generation, 40 s lifetime, addressed to the inviting device, signed with the account key, under the **mailbox handle the invite row was retrieved with** (`invocation.callId`), never the call id inside the envelope. It refuses anything but an invite addressed to this exact device, a caller endpoint whose device differs from the inviting device, and a handle that is malformed or equals the call id; it never throws.
  - Transport: `CallSignalingService.transmit` (direct race + mailbox custody with the caller's wake-handle grant) — the service's coordinator is now optional (`send` fails closed without one). Direct leg: new `BridgeCallDirectTransport` (`message:send` through the Go bridge, mapped like `P2PCallTransport`). Endpoint: the foreground's production resolution moved unchanged into `lib/features/call/infrastructure/production_call_endpoint_resolution.dart` (`resolveProductionCallEndpoint`) and is shared by the graph and the headless backend (`BridgeCallAuthorityClient`, `DatabaseCallTrustedRosterProvider`, `ReceivedCallWakeHandleStoreImpl` on the secure key store).
- Relay and iOS unchanged. The caller side already handles `remoteReject` (ended, `declined`), which stops the ringback.

## TDD rows

| Row | RED | GREEN | Evidence |
|---|---|---|---|
| `headless_call_admission_entrypoint_test.dart`: `invocation parser accepts the decline reply mode as a fifth field` | compile (`mode`, `HeadlessCallAdmissionMode` missing) | pass | `dart_decline_reply_red_2026-09-05.txt`, `dart_decline_reply_green_2026-09-05.txt` |
| `production_headless_call_admission_test.dart` group `decline reply mode` (6): reply + ack ordering, already-ended ack without reply, undelivered reply defers, no sender / no invite / deferred / empty, admission never replies, runner passes the mode | compile (`declineReplySender`, `signal` missing) | pass | same |
| `headless_call_decline_reply_test.dart` (5): signal shape, mailbox-only custody, exact-device refusal, endpoint device mismatch, failures report false | compile (type missing) | pass | same |
| `call_signaling_service_test.dart`: `transmit needs no coordinator and send fails closed without one` | compile (`coordinator` required) | pass | same |
| `bridge_call_direct_transport_test.dart` (3) | compile (type missing) | pass | same |
| Dart suites incl. affected (composition, graph diagnostics, live-call guard, adapters, mailbox client) | — | 154/154 | `dart_decline_reply_green_2026-09-05.txt` |
| `headless_call_decline_reply_test.dart`: `a reply under the call id itself or a malformed handle is refused` + handle assertions; session test asserts the handle passed to the sender is the retrieved one | compile (`callHandle` parameter) | 101/101 | `dart_decline_reply_handle_red_2026-09-05.txt`, `dart_decline_reply_handle_green_2026-09-05.txt` |
| Kotlin `HeadlessCallAdmissionWorkerTest` (3 new: scheduler decline job, decline mode never presents, unknown mode builds no engine), `MknoonCallLifecycleControllerTest` (1 new: decline without owner schedules once) | compile (`enqueueDeclineReply`, `INPUT_MODE`, `HeadlessCallAdmissionMode`, `onDeclineWithoutOwner` missing) | BUILD SUCCESSFUL, call package 129/129 (worker 14, controller 32) | `kotlin_decline_reply_red_2026-09-05.txt`, `kotlin_decline_reply_green_2026-09-05.txt` |

## Device finding (b) — 2026-09-05 18:23Z, captures `fresh-260905201908`

First deploy (`d5c404b87`): the Pixel side worked end to end — decline at 18:23:1x, a second worker run at 18:23:26, `CALL_ENDPOINT_RESOLUTION_RESULT available`, `mailbox_store result=true wake=dispatched`, `direct_send result=true` (relay), `call_ack_v1`, `CALL_HEADLESS_DECLINE_REPLY_RESULT outcome=sent`. The iPhone received the reject on both legs 1 s later (`P2P_SERVICE_MESSAGE_RECEIVED envelopeType=call_signal` decrypted; VoIP push `presentation=busy`, `call_retrieve_v1`, `CALL_SIGNALING_WAKE_RESULT drained`) and dropped it without a transition or diagnostic; the user cancelled at 18:23:28. Cause: the reply used the call id as its mailbox handle, but the caller mints the handle apart from the call id (`ProductionCallControlSignalingAdapter.prepareOutgoingInvite` forbids the two to be equal) and its incoming frames are checked against that handle (`expectedCallHandle`). Fix: the session hands the sender the handle it retrieved the rows with; the transmitter refuses the call id or a malformed handle. RED `dart_decline_reply_handle_red_2026-09-05.txt` (compile: the handle parameter), GREEN `dart_decline_reply_handle_green_2026-09-05.txt` 101/101 (transmitter, session, entrypoint, composition, graph diagnostics).

Follow-up worth its own row: the caller drops a mis-handled signal silently; a `CALL_INCOMING_SIGNAL_DROPPED {reason}` diagnostic would have named this in one grep.

## Gates

- `flutter analyze` on the changed Dart files: clean (one pre-existing `use_null_aware_elements` info in `call_signaling_service.dart` fixed on the way); `dart format` clean.
- New Dart tests registered in both 1:1 gate arrays: `headless_call_decline_reply_test.dart`, `bridge_call_direct_transport_test.dart`.
- Device proof (pending "deploy"): kill the Pixel app, lock it, call from the iPhone 11, decline from the Pixel notification. Expect on the Pixel: a second `HeadlessCallAdmissionWorker` run with `CALL_HEADLESS_DECLINE_REPLY_RESULT outcome=sent`, `call_store_v1` and `call_ack_v1`; on the iPhone: `CALL_STATE_TRANSITION trigger=remoteReject endReason=declined` and `ringback=stopped` within a few seconds, no `cancel` needed.

## Deploy

2026-09-05 18:19Z (`docker-ws/deploy_three_phones_404_result.txt`): iPhones `1.0.0-d5c404b87.d8.flowlog.t260905201506` (both verified, identities kept), Pixel `1.0.0-d5c404b87.d8.t260905201506` (verified, in place); captures `docker-ws/deploy-captures/fresh-260905201908/`.

## Follow-ups (not in this plan)

- App alive with Flutter attached but the call not adopted by Dart: the decline reply is scheduled but the runtime lease is held, so the run defers and no reject is sent; the foreground drain is expected to own such calls.
- A reply that reaches no custody is not retried (the worker runs once); the caller then times out as before.
- iOS callees are unaffected (PushKit keeps Dart alive for the decline).
