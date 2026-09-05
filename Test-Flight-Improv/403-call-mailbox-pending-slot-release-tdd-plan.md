# Plan 403 — Release the relay's pending-call slot for ended and never-stored calls (TDD)

Status: implemented 2026-09-05, deployed to the three phones 2026-09-05 17:42Z (device proof pending)
Origin: user report 2026-09-05 — "works... but when I locked pixel and tried to call it from iphone. got the error (Couldn't start voice call)".
Evidence: `Test-Flight-Improv/evidence/403/`

## Problem

Captures `docker-ws/deploy-captures/fresh-260905191258/` (iPhone 11 `1.0.0-d3ca67f80.d4.flowlog.t260905190931`, Pixel `1.0.0-d3ca67f80.d8.t260905191154`, relay v1.10.5), local time UTC+2:

| Local | Side | What happened |
|---|---|---|
| 19:14:33 | iPhone 11 | call B to the Pixel: `wakeRequested` → ringing (ringback played) |
| 19:14:37 | Pixel | headless worker: `call_retrieve_v1`, `MKNOON_CALL_PRESENTATION_DIAG result=PRESENTED` |
| 19:14:40 | iPhone 11 | user cancels; terminate stored (`CALL_CONTROL_SIGNAL_SEND_RESULT type=terminate`) |
| 19:14:43 | Pixel | headless worker: retrieve → terminal → `CALL_ANDROID_DISCONNECT source=explicit_end`. No `call_ack_v1` |
| 19:14:47 → 19:14:57 | both | call C: same sequence, again no `call_ack_v1` |
| 19:15:11 | iPhone 11 | call D: `CALL_MAILBOX_BRIDGE_FAILURE {call_store_v1, CALL_RECIPIENT_CAPACITY}`, `mailbox_store result=false`; the direct leg fails after 5 s (locked Pixel) → `CALL_CONTROL_SIGNAL_SEND_FAILED invite transportUnavailable` → `negotiationFailed`, `endReason=signalingFailed` = "Couldn't start voice call" |
| 19:15:16 → 19:15:56 | iPhone 11 | terminal cleanup: `call_cancel_v1` → `CALL_UNAUTHORIZED`, `CALL_TERMINAL_CLEANUP_RESULT blocked otherRequired`, repeated on every native replay (`CALL_NATIVE_OUTGOING_REGISTRATION_RESULT terminalReplay rejected terminalCleanupPending`) |

Two defects:

1. **The Pixel never acknowledges the rows of an ended call.** The relay keeps a call handle in the recipient's pending index until every row is acknowledged or the newest row expires (`go-relay-server/call_control_redis.go`: `keys.handles` scored by `meta.ExpiresAtMs`; the ack path drops the handle only when no row is left). `CallMaxPendingHandles = 2` per recipient. Every signal carries a 40 s lifetime (`CallControlEffectExecutor.defaultSignalLifetime`), so an ended call whose invite and terminate were consumed headlessly (presented, then ended natively) still occupies a slot for 40 s after the caller hung up. Calls B and C were both inside that window when call D was stored. The relay is type-blind (encrypted envelopes), so only the recipient can free the slot.
2. **A never-stored invite blocks the caller's terminal cleanup forever.** `CallControlEffectExecutor.retireOutgoingPreconnectInvite` cancels the mailbox invite when the invite was not confirmed stored. For a call the relay never held, the relay answers `CALL_UNAUTHORIZED` (no meta, no tombstone of ours), the client mapped that to `bridgeFailure`, the executor threw `transportUnavailable`, the `call_signaling_context` step (required for terminal ack) failed, and every native terminal replay was rejected. Nothing of ours can be behind that answer: the relay says `CALL_UNAUTHORIZED` on cancel only when it holds no call of ours for the handle (never stored, tombstone expired, or not ours).

## Design

- `MailboxProductionHeadlessCallAdmissionSession._evaluateOnce` (`lib/app/bootstrap/production_headless_call_admission.dart`): when the page holds an authenticated terminal row (`terminate`/`reject`), the session acknowledges the authenticated rows of the call (`call_ack_v1`, the same handle it retrieved) before returning `terminal`, i.e. before `close()` tears the bridge down. Rows that could not be judged (deferred/rejected) are left alone. The ack is best effort: a failure never changes the verdict (the rows then expire as before). Every non-terminal verdict (admitted, deferred, empty, permanent reject) still leaves the rows unacknowledged for foreground adoption.
- `BridgeCallMailboxClient.cancel` (`lib/features/call/infrastructure/call_mailbox_client.dart`): `CALL_UNAUTHORIZED` from `call_cancel_v1` resolves `true` ("nothing of ours is left to cancel"). The `CALL_MAILBOX_BRIDGE_FAILURE {call_cancel_v1, CALL_UNAUTHORIZED}` diagnostic is still emitted. Every other refusal still throws `bridgeFailure`, and `store`/`retrieve`/`ack` are unchanged. The executor and the cleanup coordinator are untouched: with the cancel resolved, `call_signaling_context` completes and the native terminal replay is accepted.
- Relay unchanged (v1.10.5).

## TDD rows

| Row | RED | GREEN | Evidence |
|---|---|---|---|
| `production_headless_call_admission_test.dart`: `a terminal page acknowledges its authenticated rows before close` (ack of both message ids on the call handle, ordered before `closeResources`), `a terminal page acknowledges only the rows it authenticated` (deferred third row excluded), `an acknowledgement failure never changes the terminal verdict`, `every non-terminal verdict leaves the rows for foreground adoption` | 2 failing (`Actual: []` — no ack) | 15/15 | `dart_pending_slot_red_2026-09-05.txt`, `dart_pending_slot_green_2026-09-05.txt` |
| `call_mailbox_client_test.dart`: `cancel treats an unauthorized relay answer as an absent invite`, `only cancel tolerates the unauthorized answer` (five other codes still throw; `ack` with `CALL_UNAUTHORIZED` still throws) | 1 failing (`bridgeFailure` thrown) | 11/11 | same files |
| affected set (`tdd_context.py affected`): composition, signaling service, pre-presentation admission, signaling runtime, production adapters, direct/mailbox convergence + executor + headless entrypoint | — | 161/161 | `dart_pending_slot_affected_2026-09-05.txt` |

## Gates

- `flutter analyze` on the four changed files: clean; `dart format`: clean.
- Tests already registered: `production_headless_call_admission_test.dart` in `BASELINE_TESTS` (`scripts/run_test_gates.sh`), `call_mailbox_client_test.dart` in both 1:1 arrays.
- Device proof (pending the user's "deploy"): lock the Pixel, call it from the iPhone 11 three times within 40 s, cancelling each; every call must ring back and the Pixel must present each one. Expect `call_ack_v1` in the Pixel logcat after each `CALL_ANDROID_DISCONNECT`, no `CALL_RECIPIENT_CAPACITY` on the iPhone, and `CALL_TERMINAL_CLEANUP_RESULT status=ready` after every call.

## Deploy

2026-09-05 17:42Z (`docker-ws/deploy_three_phones_403_result.txt`): iPhones `1.0.0-4d87486a2.d7.flowlog.t260905193900` (both verified, identities kept), Pixel `1.0.0-4d87486a2.d7.t260905193900` (verified, in place); captures `docker-ws/deploy-captures/fresh-260905194144/`; the Pixel app was killed after the capture start so the headless path runs on the next call.

## Follow-ups (not in this plan)

- A relay-refused invite still sends a terminate (a wasted 5 s direct attempt on the caller); harmless.
- A capacity refusal that is genuine (two calls really pending) still reads "Couldn't start voice call"; a busy-specific message would need `CallEndReason` plumbing.
- Headless `permanentReject` rows are left unacknowledged (40 s slot) — foreground adoption may still judge them.
- Missed-call history for headless-only calls: the acknowledged rows are gone for a later foreground drain; history for those calls must come from the native descriptor store (already an open follow-up of plan 402).
