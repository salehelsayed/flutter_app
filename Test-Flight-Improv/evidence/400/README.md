# Plan 400 evidence — host closure 2026-09-04

Toolchain: host Mac Flutter (via `/claude-host-bin/flutter`), Xcode simulator for Swift, Gradle JVM for Kotlin.
Checkpoint commit before execution: `f2974b067`.

| Row | RED (before production edit) | GREEN | Notes |
|---|---|---|---|
| TC-400-01 | `Expected: null / Actual: CallAudioRouteException(selectionFailed)` | adapter file 59/59 | mutation re-red: `_releaseEndedHandleAudio` short-circuit removed → `selectionFailed`; restored → GREEN. Also asserts `deactivateAudio` after end makes no native call |
| TC-400-01b | GREEN sentinel | 59/59 | native terminal event → `_releaseRetainedTerminalAudio` |
| TC-400-02 | `Expected: CallAudioFailure.none / Actual: cleanupFailed` | audio controller 26/26 | second `close()` makes no further engine calls |
| TC-400-03 | `Expected: length 1 / Actual: []` (no `CALL_MEDIA_CLOSE_FAILURE_STAGE`) | diagnostics 7/7 | stages `audio_cleanup` / `engine_release` (+ `interruption_release`) |
| TC-400-04/05 | GREEN sentinels | 59/59, 26/26 | |
| TC-400-07/07b/07c/08 | revokes + `failClosed` recorded, `isStarted == false` (HEAD) | live-call guard 6/6 | 08b GREEN sentinel; 08c GREEN after 08 |
| TC-400-09 | `Expected: true / Actual: false` (`isStarted`) | composition 58/58 | `CALL_SIGNALING_RECONCILE_RESULT outcome=advertisement_deferred` |
| TC-400-10/12 | GREEN sentinels | 58/58, 19/19 | |
| TC-400-11 | `Expected: empty / Actual: [(epoch: 31, kind: iosVoip)]` | coordinator 19/19 | second publish is a real `publishToken` (2 publications) |
| TC-400-14/15 | not recorded separately | Swift 25/25 (`swift_runner_tests_2026-09-04.txt`) | `MknoonVoipPushRegistryTests` + `IosCallConfigurationTests` unchanged |
| TC-400-17/17b/17c/19 | `endpointMismatch` / `signalingUnavailable`, no pin | adapters 15/15 | 17c GREEN on HEAD; census `pinnedEndpoint(` = 4 |
| TC-400-18/18b | GREEN sentinels | 15/15 | |
| TC-400-06/13/16/20 | — | PENDING | device proofs are user-driven; tooling: `docker-ws/relay_ssh.py`, `docker-ws/relay_call_registry_probe.sh` |

Gates: `curated_1to1_lane_2026-09-04.txt` (Flutter leg 4165/4165; trailing device leg unselected → exit 1),
`host_1to1_batch_2026-09-04.txt` (PASS, 191 paths), `kotlin_call_unit_sentinel_2026-09-04.txt` (BUILD SUCCESSFUL),
`swift_runner_tests_2026-09-04.txt` (TEST SUCCEEDED). `affected` → 21 unit files 316/316. `completeness-check` PASS 1549/1549.
`flutter analyze`: No issues found. `git diff --check`: clean.

## Addendum 2026-09-05 — refresh-epoch advance on `CALL_STALE_EPOCH`

| Row | RED | GREEN | Notes |
|---|---|---|---|
| TC-400-21 authority client relay code | getter missing (compile) | authority client 10/10 | `CallAuthorityException.relayErrorCode` / `isStaleEpoch` |
| TC-400-22 advance once + re-publish | `Expected: true / Actual: false` | coordinator 24/24 | mutation (branch disabled) → RED; restored → GREEN |
| TC-400-23 second rejection retryable | `Expected: [11, 12] / Actual: [11]` | 24/24 | |
| TC-400-25 native failure retryable | advance calls `Expected: 1 / Actual: 0` | 24/24 | |
| TC-400-26 refused answer | advance calls `Expected: 1 / Actual: 0` | 24/24 | |
| TC-400-27 graph flow event | coordinator-side emission rejected by the privacy census | live-guard 7/7 | outcome stream → `CALL_VOIP_TOKEN_EPOCH_ADVANCE_RESULT` |
| TC-400-28/29 Swift | build error `no member 'advanceRefreshEpoch'` | 27/27 (`swift_runner_tests_epoch_advance_2026-09-05.txt`) | |
| TC-400-30 device | — | see `epoch_advance_device_proof_2026-09-05.txt` | iPhone 11 + production relay |

## Addendum 2026-09-05 (b) — locked callee: call answered, never ended (four fixes)

Symptom (captures `docker-ws/deploy-captures/fresh-260905024353/`): iPhone 13 locked, VoIP-woken, answered; iPhone 11 hung up; the call never ended on iPhone 13 (and, earlier, rang a second time after a hang-up).

| Fix | Row | RED | GREEN | Notes |
|---|---|---|---|---|
| 1 background admission on VoIP wake | `call_signaling_composition_test` ×3, live-guard ×2, `ios_call_wake_channel_test` ×3 | seams missing (`CallSignalingWakeDrain`, `onCallWake`, `IosCallWakeChannel`) | 73 across the three files | `CALL_SIGNALING_WAKE_RESULT` outcomes; PushKit `runtimeWake` → `mknoon/ios_call_wake` channel; relay recovery drains once |
| 2 answered-but-unadopted native call | `MknoonCallKitLifecycleTests` ×3 (`testAnswerNobodyConsumesEndsTheCallAtTheAdoptionBound`, `...ConsumedByTheRuntimeIsNotEnded...`, `...IgnoresOtherCalls`) | build error `no member 'enforceAnswerAdoptionBound'` | 45 tests, 3 new pass (`swift_runner_tests_callkit_answer_bound_2026-09-05.txt`) | `answerAdoptionBoundMs` = 10 s; consumed answers leave `events` through ack. One PRE-EXISTING red: `testConcurrentPushKitAndAuthenticatedPresentationCoalesceOneCallKitReportAndOnePresentedEvent` fails identically at HEAD (`swift_callkit_concurrency_test_preexisting_red_2026-09-05.txt`) |
| 3 caller cancel keeps the mailbox, orders the terminate behind the invite | executor test `a mailbox-stored invite cancelled before ringing keeps the mailbox and stores the terminate after the invite settles` | `Expected: ['invite'] / Actual: ['invite', 'terminate']` (terminate raced the invite's custody) | executor 16/16 | retirement now waits for the in-flight pre-connect terminate so the context purge cannot starve it |
| 3b late drain never rings a cancelled invite | runtime ×2, handler ×3 (`peek`, `superseded`), convergence contract rewritten | compile: `IncomingCallSignalPeek`/`peekIncoming`/`terminalFollows` missing | 40/40 (runtime + handler + convergence) | convergence: `cancelCalls 1 → 0`, `storeCalls 2`, `acked 2`, outcomes `[superseded, non-deferred]`; production runtime wired with `peekIncoming: handler.peek` |
| 4 relay wakes only when needed | `call_wake_attached_recipient_test.go` ×3 | two VoIP routes for an attached recipient | 3/3 + full relay suite ok (`relay_wake_attached_recipient_2026-09-05.txt`) | `redisCallMeta.AckedEvents` (omitempty; old records → never attached); Android standard route unchanged. NOT DEPLOYED to the production relay (needs explicit approval) |

Gates: affected union 258/258 (13 files); `flutter analyze` clean; arch graph `--incremental` refreshed; host `1to1` batch PASS 191 paths (`host_1to1_batch_locked_callee_2026-09-05.txt`); curated `1to1` lane Flutter leg 4186 passed / 11 skipped, trailing device leg unselected with three phones attached, as on 09-04 (`curated_1to1_lane_locked_callee_2026-09-05.txt`). Commits: relay `3e7c02d57`, app `c6817c873`.

## Addendum 2026-09-05 (c) — answered call dropped: CallKit never activated the audio session

After (b) the locked callee dropped ~2 s after answering (`CALL_AUDIO_START_RESULT audioSessionFailed` → `mediaFailed`). Native NSLog lines never reach the captures (all `<private>`), so CallKit diagnostics were moved to a public `os_log` helper (`mknoonCallKitDiag`, commit `52d06e039`); the next capture showed `activate_audio=refused reason=session_not_activated` ×37 and no `audio_session=latched` (`locked_callee_audio_refusal_diag_2026-09-05.txt`): CallKit never delivered `didActivate`, because the AVAudioSession category was configured only inside `didActivate`. Fix `058962862`: configure the session in the answer action (before fulfil) and the start action, as Apple's CallKit sample does.

| Row | RED | GREEN | Notes |
|---|---|---|---|
| Swift `testAnswerConfiguresTheCallAudioSessionBeforeFulfilment` | `prepareCount` 0 != 1 | CallKit suite 46 tests, only the pre-existing concurrency test red | existing latch test now expects 2 (answer + activation) |
| iOS adapter ordering tests ×2 (`…observed before its invite…`, `…handled before the native journal…`) | GREEN sentinels | 2/2 | Dart adoption is correct in both orderings; the refusal was native |
| Device proof (user-driven) | — | `locked_callee_device_proof_2026-09-05.txt` | callee `audio_session=latched` 100 ms after answer, `mediaConnected` both sides, hang-up → callee `remoteTerminate`/`terminal=remoteCancelled` in 0.45 s, no second ring |

Residual: during negotiation the caller's offer/ICE burst still produced two VoIP pushes to the attached callee (older events not yet drained → `recipientAttachedTx` false); CallKit answered `presentation=duplicate`, no ring. A burst-tolerant rule (attached = any acknowledged event) is a follow-up. Closed in addendum (d).

## Addendum 2026-09-05 (d) — follow-ups closed: burst-tolerant relay attachment, CallKit coalescing red

| Row | RED | GREEN | Notes |
|---|---|---|---|
| Relay `TestCallStoreSkipsIOSVoIPWakeForAnAttachedRecipientDuringABurst` | two VoIP routes (invite + second burst event) under the v1.10.3 "nothing older pending" rule (`relay_wake_attached_burst_2026-09-05.txt`) | 4/4 attached-recipient tests, full relay suite ok, `-race` on `TestCall*` ok | `recipientAttached(meta)` = `AckedEvents > 0`; pending events no longer consulted; `keys.events` dropped from the `ClaimWake` WATCH; `TestCallStoreWakesIOSVoIPAgainWhileEarlierEventsAreUnread` renamed `…ForEveryEventOfAnUnattachedRecipient` (a recipient that never acknowledged anything still wakes per event); Android unchanged. Relay `version` 1.10.4, binary sha `cca91cb72a5b…`, deploy script `docker-ws/deploy_relay_v1104.sh` — NOT deployed (needs explicit approval) |
| Swift `testConcurrentPushKitAndAuthenticatedPresentationCoalesceOneCallKitReportAndOnePresentedEvent` (pre-existing red) | 4 asserts at HEAD (`swift_callkit_concurrency_test_preexisting_red_2026-09-05.txt`): every coalesced presentation issued a second `reportNewIncomingCall`, and the fake provider's single delayed slot then dropped the first completion | 47 tests, 0 failures (`swift_callkit_coalesced_report_green_2026-09-05.txt`) | `reportIncoming(…, reportRequired:)`: a presentation that coalesces onto an in-flight report reports again only when PushKit requires it (`reportPolicy != .notRequired`); diag `presentation=coalesced report=pushkit|none`; the test's PushKit leg now passes `reportRequired: true` |
| Swift `testPushKitPresentationDuringAnInFlightAuthenticatedReportStillReportsToCallKit` (guard) | mutation `guard !reportRequired`: `[callA]` != `[callA, callA]` (`swift_callkit_coalesced_report_mutation_red_2026-09-05.txt`) | same 47/0 run | PushKit compliance kept: authenticated first, PushKit second → two reports; the first completion settles both (`true` / `.duplicate`); CallKit's already-exists answer to the second leaves the call intact. `FakeCallProvider.delayedReportCompletions` keeps every delayed completion |

Phones keep builds `1.0.0-52d06e039.d8.flowlog.t260905124526` (iPhones) and `1.0.0-c6817c873.d9.t260905034852` (Pixel); the Swift change reaches them with the next iOS build.
