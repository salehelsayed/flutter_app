# Android audio calls: implementation and unattended beta-testing handover

Prepared 2026-09-16 for a fresh Codex session in `/Volumes/CrucialX9/flutter_app`.

**Status:** this is the user's requested handover, not an implementation or beta-test completion report. The visual mismatch and requested outgoing Connecting → Ringing experience remain unfinished. The previous functional lock-screen repair is already in the working tree and installed as debug build 1.0.1(127).

## User's instructions for the next session

1. Make the locked Android call screen match the existing unlocked Flutter call screen.
2. When the user starts a call to a friend, immediately show a call screen saying **Connecting**, followed by the **Ringing** screen as call setup progresses.
3. Act as an unattended beta tester focused on audio calls, using the connected physical Android phone and Android emulator. Exercise a broad range of functionality, reliability, ease of use, UI/UX, accessibility and audio scenarios. Document the scenarios and provide a detailed findings report in plain language the user can easily understand.

Implement the two UI changes, build and deploy fresh candidates to both targets, then test the resulting installed builds. Investigate and fix regressions introduced by those changes. Record other discovered defects clearly and prioritize fixes within the audio-call scope; do not silently expand into unrelated product work. Continue independently while the user is absent. This handover does not authorize a store/server release, destructive account/data resets or contacting other people's devices.

## Authorized test-device unlocking

The user explicitly supplied the physical Android test PIN for this work and asked that it be remembered. It is stored locally at:

`/Volumes/CrucialX9/flutter_app/.codex-test-logs/android-audio-beta/device-credentials.local.json`

That file is Git-ignored and has mode 0600. Read the PIN from its `pin` field only inside the local automation. The credential is bound to physical serial `21071FDF600CSC`. It is deliberately not repeated in this handover, tracked files or reports. A copy of this handover on another machine will not contain the credential.

**Normal PIN entry is authorized; a lock bypass is not needed.** Do not ask the absent user to unlock this test phone as the default workflow. Before the main campaign, prove the full automated sequence on the discovered physical target: wake → display the ordinary PIN entry UI → enter the configured PIN → verify keyguard is unlocked → open Mknoon → lock again → repeat successfully. PIN automation has NOT yet been verified on this phone. Earlier statements that the assistant could not unlock it referred to having no authorized credential; do not perpetuate that as a categorical tool limitation.

Keep the PIN out of tool output, shell command arguments, recordings, screenshots, log exports and findings. Use a local runner with private credential input, and avoid capturing the credential-entry interval. Do not change/remove the PIN or biometric configuration. If normal entry fails, inspect focus/layout and report the actual limitation; do not guess credentials or retry blindly into a device lockout. Continue independent emulator/unlocked cases if necessary and label dependent cases NOT RUN rather than pretending secure-unlock coverage passed.

## Repository rules and starting state

Read root `AGENTS.md` and any applicable narrower instructions first. In particular:

- No skill is authorized by this handover. Only invoke a skill if the current user message explicitly asks for that skill by name. Do not automatically invoke Appium, TDD, release-check or rollout/session orchestration skills.
- Use targeted `rg`, file discovery, source reads and test inspection. Query `codex-memory/memory.py` before broad document/history searches; current source establishes behavior. Do not search historical plans to rediscover code relationships.
- Before choosing tests for code changes, consult relevant entries in `docs/testing/TESTING.md` and `tool/testing/selection.json`. Use the underlying check wrapper directly with a verified explicit base and `--local`. Do not default to full `host-all` for each small fix. Report required checks not executed.
- Preserve existing user edits and the previous lock-screen repair. **The working tree is intentionally dirty and the repair is uncommitted. HEAD alone does not contain build127's fixes.** Do not reset it or start from a clean checkout that loses those changes.
- Recorded HEAD: `ece276853014fedebc8cd77d5f742a43b5846b72`. Re-verify current HEAD/status before choosing a comparison base. A starting status snapshot is in `.codex-test-logs/android-audio-beta/working-tree-before-handover.txt`.
- Existing unrelated work includes Go relay/node recovery, app diagnostics, diagnostic harnesses and test infrastructure. Preserve it. Some files contain both prior user edits and the call repair, including `docs/testing/TESTING.md`, `tool/testing/selection.json`, and `test/unit/dtr18_layering_relocation_contract_test.dart`.
- Use available hardware only. Missing Android API versions, iPhones or accessories are N/A where the project policy applies, not reasons to block the Android pair.

## Devices, accounts and toolchain

Rediscover the live matrix using the pinned Flutter executable's `devices --machine` and `adb devices -l`. Pin every device command explicitly. Expected targets, which must be confirmed rather than assumed:

| Role | Target ID | Last observed state |
| --- | --- | --- |
| Physical Pixel 6 | `21071FDF600CSC` | Android17/API37; app account `pixel`; secure PIN lock |
| Android emulator | `emulator-5554` | API37; app account `Username` |

Use this Android pair in both caller/receiver directions. Do not substitute an iPhone or ask the user to operate another device. The emulator has an old stale contact also named `pixel`: the current paired conversation header is `pixel / Connected Sep 16, 2026`. Select and verify the current pairing instead of blindly tapping the first matching label. Preserve app data and pairings.

- Package: `com.mknoon.app`.
- Flutter: `/Users/I560101/development/flutter-3.47.2/bin/flutter` (PATH's older Flutter was not the validated toolchain).
- JDK: `/Applications/Android Studio.app/Contents/jbr/Contents/Home`.
- Last installed APK on BOTH targets: debug **1.0.1(127)**, SHA-256 `4cdde69dcdf8200cea24455f204ca7aed966b58fc8402ca75a6cf1e2816d8795`.
- Native calls enabled; production-provider FCM configuration retained. Microphone, notifications and full-screen access were available during the successful proof; recheck current state.

Previously successful build command (choose a fresh build number after checking installed/candidate identities):

```sh
ORG_GRADLE_PROJECT_enableAndroidNativeCalls=true \
JAVA_HOME='/Applications/Android Studio.app/Contents/jbr/Contents/Home' \
/Users/I560101/development/flutter-3.47.2/bin/flutter build apk \
  --debug --target-platform android-arm64 \
  --build-name=1.0.1 --build-number=<fresh-number> \
  --dart-define-from-file=tool/build/voice_call_release_defines.json
```

The Go AAR prebuild verifies its input digest/toolchain. Use the normal build pipeline and preserve that check. Install in place on both explicit targets; verify installed version AND base.apk SHA-256 against the built candidate. Do not claim candidate proof against an older installation. Do not mistake the recorded HEAD for a published-release baseline.

## Previous repair: evidence and invariants to preserve

Read `.codex-test-logs/android-incoming-fix-20260916T134938Z/report.md` and the relevant local-Android-audio entry in `docs/testing/TESTING.md`. The report includes the candidate configuration/source hashes, all failed attempts and corrections, and the final proof. Evidence is local and ignored; this is not a signed-release certification.

Build127 was verified on the actual pair through: genuinely process-absent locked incoming Decline → another call answered with bidirectional RTP progress → native End → another incoming Decline. Incoming/answered accessibility contained only the intended call surface. Accepted controls persisted beyond the original ring TTL. Final state had no pending native call file, active call service or app notification; secure keyguard was restored. The locked layout remained basic and visually different from Flutter.

258 native tests passed across 18 classes. Presentation tests covered API24/26/27/34. Earlier targeted startup and call-related check families also passed. The broader 36 selected checks in the report remained NOT RUN; do not inherit an all-suite/release-green claim. A separate original provider-to-device ingress miss remains unexplained.

Important preservation rules, established through actual failed builds and repairs:

1. Grant `showWhenLocked`/`turnScreenOn` only for a validated, exact incoming call after an opaque call surface is mounted. Keep unrelated Flutter routes/private content inaccessible while locked. Revoke flags safely at terminal/stop/unlock.
2. **Do not hide Flutter before its first frame.** Flutter's pre-draw gate can otherwise leave the entire shared window black with visible XML nodes but inert buttons. Current code waits for an actual cover draw, then hides the native ancestor; previously drawn warm views hide immediately.
3. Accessibility importance alone did not hide Flutter virtual nodes from uncompressed or cached queries. Preserve an effective hierarchy/visibility boundary, including accessibility and touch/focus. Update tests for the NEW intended call content without allowing unrelated chat semantics back in.
4. Qualified identity/node/call startup must not wait for a rendered home frame. Ancillary navigation work retains its home-route boundary. Preserve startup qualification and migration/linked-device gates.
5. Ordinary native bridge detach must allow same-engine reattachment. Disposal, superseded owners, stale callbacks and stale call IDs remain fenced.
6. Dart end after native Decline/End must acknowledge an exact retained terminal once cleanup completes, rather than treating “no new terminal appended” as failure. The old response invalidated calling authority and revoked the receiver endpoint, breaking the next call. Unknown/ACK-retired IDs and successor calls remain protected.
7. Keep permission-gated full-screen intent behavior on ringing notification updates, including the fallback when Android does not allow full-screen presentation.

Key current files:

- `android/app/src/main/kotlin/com/mknoon/app/call/MknoonIncomingCallPresentation.kt`
- `android/app/src/main/kotlin/com/mknoon/app/MainActivity.kt`
- Native `MknoonCallAndroidRuntime.kt`, `MknoonCallNativeBridge.kt`, `MknoonCallLifecycleController.kt`, `MknoonCallNotificationFactory.kt`, and their tests under `android/app/src/test/kotlin/com/mknoon/app/call/`.
- `lib/features/identity/presentation/startup_router.dart`
- `lib/app/application_root.dart`
- `lib/features/call/presentation/foreground_call_overlay.dart`
- Relevant startup recovery, overlay, native lifecycle and notification tests, plus `scripts/test/run_call_native_unit_tests.sh`.

## Work item 1: match locked and unlocked call screens

Use the actual existing Flutter screens and theme as the design reference; inspect/capture them before changing the locked UI:

- `lib/features/call/presentation/screens/incoming_call_screen.dart`
- `lib/features/call/presentation/screens/active_call_screen.dart`
- `lib/features/call/presentation/widgets/call_controls.dart`
- `lib/core/theme/background_readable_colors.dart`
- `lib/features/home/presentation/widgets/user_avatar.dart`
- `test/features/call/presentation/call_screens_test.dart`

The current Flutter incoming screen uses an avatar measuring 112 logical pixels, centered caller identity, a 28-size title, smaller status text, and circular 68-size Decline/Answer controls near the bottom (red decline, theme-accent answer). The native lock screen currently uses generic text and wide default rectangular buttons on navy. Matching only a color will not satisfy the user's request.

Match layout, typography, avatar/caller presentation, colors, icon shapes, button placement, spacing and states. Use the same visual language for the continuing locked call screen. Present only controls that are correctly wired and available. Keep English/German/Arabic labels and RTL, safe areas, large text and meaningful accessibility labels in view. Capture side-by-side evidence for comparable incoming and active states.

Validated caller identity belongs to the intended call screen; unrelated chats, contact lists, restored routes and private navigation do not. Follow existing privacy settings and use a styled fallback if call identity is genuinely unavailable. Do not expose the whole Flutter app merely to achieve visual parity. Evaluate architecture from current code; preserve the proven cold-start/draw and lifecycle invariants rather than replacing them casually.

Acceptance: the phone's locked call screen is visibly consistent with its unlocked call screen; Answer/Decline/End and any shown audio controls work; wake/secure unlock/relock and terminal cleanup remain correct; screenshots and accessibility attest to the intended call surface only.

## Work item 2: immediate Connecting, then Ringing

Source inspection during handover preparation established the following; this is NOT a latency measurement or an implemented fix:

- `lib/features/conversation/presentation/screens/conversation_wired.dart`: `_startOutgoingCall` → `_startOutgoingCallInTrace` sets `_outgoingCallStartInFlight`. Currently only the disabled voice button's tooltip/semantics changes to “Starting voice call”; the chat remains visible.
- `lib/features/conversation/presentation/widgets/conversation_header.dart`: `_ConversationCallAction`; wired through `conversation_screen.dart`.
- Preflight awaits readiness/contact checks, microphone permission, capability advertisement, wake authority, endpoint resolution and native reconciliation before `coordinator.placeCall`. See `lib/app/bootstrap/call_signaling_composition.dart` and `lib/app/bootstrap/production_call_signaling_graph.dart:prepareOutgoingCall`.
- `foreground_call_overlay.dart:_surfaceKind` shows `OutgoingCallScreen` for preparing/inviting/ringing. `outgoing_call_screen.dart:_status` currently says **Calling** before Ringing. Accepted/negotiating use `ActiveCallScreen`, which says Connecting until media establishes Connected.
- **Ringing is not currently restricted to receiver acknowledgement.** `call_signaling_service.dart` interprets mailbox `wake: dispatched`; `call_control_effect_executor.dart` produces `wakeRequested`; `call_state.dart` promotes inviting → ringing. Another path receives the real remote ringing signal after receiver `systemUiPresented`, through `handle_incoming_call_signal.dart`. Existing outgoing-screen/ringback comments claiming remote-only behavior are stale. Existing reducer/executor tests explicitly cover receipt-driven promotion.

Implement visible **Connecting immediately after a valid call-start tap**, including the preflight interval, with caller/contact context and usable cancellation. It must not depend on a late canonical session merely to show feedback. Use clear state ownership; do not introduce a second competing call lifecycle.

Then transition to **Ringing** based on a truthful protocol state, not an artificial delay. Working UX interpretation: “Ringing” should indicate the recipient is being alerted; provider acceptance alone does not prove that. Audit the receipt-driven promotion and ringback expectations together with the existing protocol/tests. Preserve setup deadlines, fast-answer paths, terminal precedence and cancellation. Do not delay a real answer solely to force a Ringing animation.

Cancellation during any await must prevent a late future from opening another screen or placing a ghost call. Duplicate taps must produce one attempt. Denied microphone access, offline/unreachable peers, failed preflight, decline and timeout must all leave clear feedback and allow another attempt. Distinguish pre-answer Connecting from post-answer media connection in evidence, even if both use the same displayed word.

Relevant tests to inspect/update as appropriate:

- `test/features/conversation/presentation/screens/conversation_wired_test.dart` (bounded authority recheck and in-flight startup cases)
- `test/features/conversation/presentation/widgets/conversation_header_test.dart`
- `test/core/bootstrap/call_signaling_composition_test.dart`
- `test/features/call/presentation/call_screens_test.dart`
- `test/features/call/presentation/foreground_call_overlay_test.dart`
- `test/features/call/domain/call_state_machine_test.dart`
- `test/features/call/application/call_control_effect_executor_test.dart`
- `test/features/call/application/call_ringback_coordinator_test.dart`

Acceptance: recording and event evidence show immediate Connecting, an honest Ringing transition where applicable, and working cancellation at each stage. No unexplained dead period on the chat screen, duplicate call or late resurrection. Measure actual preflight latency rather than guessing which await dominates it.

## Unattended beta-test campaign

First establish automated device wake/unlock/lock, app navigation, permissions, current pairing and network readiness. Run relevant focused checks for implementation changes, deploy matching fresh builds, and verify identities. Then test both **physical → emulator** and **emulator → physical** for every applicable scenario. Keep the physical phone secured for secure-lock cases; a no-PIN emulator is not a substitute for that boundary.

The following is the planned scenario inventory, not a claim that these cases have already run. Expand it when testing reveals another meaningful risk. Document each executed direction/state as a separate result.

| ID | Scenario | What to verify |
| --- | --- | --- |
| SET01 | Automated PIN unlock and relock | Repeat normal UI entry successfully; no credential recorded; correct app and target. |
| SET02 | Fresh build / current pairing / permissions | Matching APK hashes, correct contact, ready endpoints, recoverable setup failures. |
| UX01 | Call-start feedback | Connecting appears immediately; status remains visible during slow preflight. |
| UX02 | Connecting → Ringing → answered | Status and ringback match real progress; fast answers remain responsive. |
| UX03 | Locked versus unlocked incoming and active screens | Matching design, appropriate identity/controls, no unrelated app exposure. |
| UX04 | Readability and accessibility | Labels, focus, touch targets, contrast, large text, supported themes, RTL/localized labels, safe areas. |
| UX05 | Navigation and orientation | Home/Back/app switch/rotation where supported; no missing controls or stale screen. |
| CALL01 | Normal answer and End from either side | Both peers agree on outcome; call screen, notification, Telecom and resources retire. |
| CALL02 | Decline and immediate next call | Caller receives decline; subsequent call remains possible. |
| CALL03 | Unanswered call and timeout | Ringing stops, clear outcome, no late resurrection; next call succeeds. |
| CALL04 | Caller cancels during preflight | No later invite or screen after asynchronous work completes. |
| CALL05 | Cancel during invite/admission/ringing | Correct current attempt cancelled on both sides; no lingering ring. |
| CALL06 | Answer races with cancel or timeout | One final result, no duplicate answer/session or stuck audio. |
| CALL07 | Double taps / simultaneous calls / simultaneous End | Duplicate suppression, clear busy/conflict behavior, correct ownership. |
| CALL08 | Stale notification/action from a previous call | Cannot answer/end a successor or reopen an ended call. |
| LIFE01 | Foreground receiver | Visible incoming UI and functional controls. |
| LIFE02 | Background receiver with screen awake | Appropriate Android heads-up/notification behavior and actionable call UI; do not demand an OS-forbidden forced launch. |
| LIFE03 | Screen off and securely locked | Wake, visible call controls, Answer/Decline without unlocking where supported. |
| LIFE04 | Genuinely absent receiver process | Prove PID absence without force-stop; FCM ingress, admission, visible ringing, action and cleanup. |
| LIFE05 | Lock/unlock/relock while ringing | Screen handoff preserves the same call and privacy; no duplicate actions. |
| LIFE06 | Lock/unlock/relock during active call | Audio continues appropriately; controls restore; End remains possible. |
| LIFE07 | Background/app switch/return during call | State/timer/route remain truthful; no lost call or extra screen. |
| LIFE08 | Process interruption and explicit force-stop | Characterize separately; force-stop push suppression is not ordinary cold-start proof. Restore the fixture afterward. |
| AUDIO01 | Two-way media and actual signal | Measure both directions; add injected/recorded signal oracle where supported; detect silence and one-way audio. |
| AUDIO02 | Mute/unmute from either side | UI matches real mic state; transmission/signal behavior changes and recovers. |
| AUDIO03 | Speaker/earpiece and volume | Actual route matches display; changes do not silently disconnect or restart media. |
| AUDIO04 | Wired/Bluetooth attach/detach/route change | Run only with available accessories; verify fallback and unavailable-control feedback. |
| AUDIO05 | Audio focus and other available interruptions | Pause/duck/resume behavior, truthful status and recovery; no unavailable extra handset required. |
| AUDIO06 | Sustained call | No unexpected disconnect, long silence, stuck timer, thermal/resource growth or lost controls. |
| NET01 | Caller unavailable/offline before starting | Useful Connecting/failure/cancel behavior and recovery. |
| NET02 | Receiver offline then returns | Honest status, bounded timeout, no stale ring on return. |
| NET03 | Network loss during Connecting/Ringing | No indefinite spinner, fake connection, duplicate delivery or stuck notification. |
| NET04 | Network loss/recovery during active call | Reconnection or clean failure within defined bounds; media and next-call recovery. |
| NET05 | Available network transitions / latency / loss | Measure recovery and media continuity using target-local controls; restore settings. |
| SYS01 | Microphone denied/revoked | Truthful permission/error UI; no claimed audio when mic cannot work. |
| SYS02 | Notifications/channel/full-screen access denied | Correct fallback and settings guidance; no false missing-screen diagnosis. |
| SYS03 | DND/ringer/volume and background restrictions | Separate user/OS policy from app failure; respect policy and restore configuration. |
| REL01 | Repeated short calls | Alternate directions and answer/decline/cancel/timeout; measure first-attempt success and trends. |
| REL02 | Cleanup and next-call health after every outcome | No orphan call file, ongoing call notification/service, leaked authority or stuck keyguard surface. |
| REL03 | Relaunch after prior terminal state | No stale invitation, expired action or duplicate history; callable again. |

Suggested starting endurance coverage: 20 short attempts per direction, including at least 5 answered-and-ended calls per direction and a mixture of other terminal outcomes, plus one 10-minute connected call per direction. Extend based on failures or unexplored risk. These are proposed campaign targets, not pre-recorded passes. If a limit prevents completion, report actual counts/durations and why; avoid endless repetition that adds no evidence.

Measure tap-to-Connecting, invite-to-visible-ring, Answer-to-connection, Answer-to-first media/signal, End-to-cleanup, success/failure counts and recovery time. Calibrate device clock offsets or measure within each device's timebase. Report sample sizes; use median/worst and percentiles only when the sample warrants them. Record crashes, ANRs, unexpected disconnects and resource trends where measurable.

Test only the designated accounts/devices. Record and restore any changed network, permission, notification, audio or orientation settings. Do not disable host/production relay services to simulate a device outage. Wired/Bluetooth cases without real available accessories are N/A; don't infer physical-route quality from an emulator.

## Reuse evidence and automation carefully

Prior local helpers live in `.codex-test-logs/android-incoming-fix-20260916T134938Z/`: `ui.py`, `locked-proof.py` (latest harness version 3), `finish-answer.py`, and `deploy-candidate.py`. Review before reuse. They are task artifacts, not a maintained universal test framework. They pin old target IDs, account navigation, labels and styling. In particular, the old navy-pixel threshold and generic-label whitelist must be replaced with assertions appropriate to the redesigned UI, while retaining genuine drawing/privacy/action proof. Include all newly added production files in candidate provenance.

The repository also has `integration_test/scripts/run_production_audio_call_sims.dart`, `production_audio_call_local_fixture.dart`, `android_production_audio_call_campaign.dart`, `integration_test/support/android_production_audio_call_evidence.dart`, and `tool/call_audio_oracle/`. Inspect their current contracts before choosing execution. The documented SIMS `--prepare-builds` path is build preparation only; it does not execute audio capability. Local oracle fixtures have a separate app/provider identity: do not silently replace the production-FCM pair or claim local-oracle results prove FCM delivery.

Evidence rules:

- Bind each result to a NEW exact call attempt, both device states, installed APK hash and timestamps. Never use old chat history or a tap with no new attempt as a pass.
- Distinguish provider receipt → device ingress → validated admission → visible ring → native Answer → peer acceptance → connection → media/signal. None alone proves the next.
- Prove rendered UI using actual screenshots/window draw state and interaction, not XML nodes or notification count alone. Serialize UIAutomator access per device.
- RTP progress is not proof of audible/intelligible speech. Use available signal/oracle evidence for objective sound measurements; identify human listening judgments as unverified when no listener is present.
- Preserve first failures and retries. Per-call diagnostic caps may drop events: corroborate with positive raw cleanup logs and live OS state. Neither missing capped evidence nor an unrelated later success is an automatic pass.
- Keep verdicts separate for behavior, visual parity, accessibility/privacy, reliability, measured audio and subjective quality. A privacy bypass for diagnosis is still a privacy failure.
- Android APP_BACKGROUND networking restrictions and the earlier explicit endpoint revocation bug are different conditions. Inspect readiness and native ingress before labeling a missing screen a presentation bug.

## Deliverables and finish criteria

Create or update these human-readable deliverables (check for existing files first):

1. `docs/testing/audio-call-beta-scenarios.md`: scenario catalog, preconditions, directions/states, steps, expected outcomes, actual outcomes, PASS/FAIL/N/A/NOT RUN, and evidence links. Distinguish planned from executed cases.
2. `docs/testing/audio-call-beta-findings.md`: detailed plain-language report. Start with whether normal users can reliably place/answer/end calls and whether the two UI requests are fulfilled. Include a coverage table and measured counts, what works, each problem's user impact/severity/reproduction/frequency, fixes and retests, remaining limitations and priorities. Explain technical terms once; keep raw logs out of the main narrative.
3. An ignored run-evidence directory with build/source/configuration identities, screenshots/recordings, redacted logs, per-attempt results, first-failure records and machine-readable scenario results. Never include the PIN.
4. Relevant verified regression/testing knowledge updates in `docs/testing/TESTING.md`, and executable mappings in `tool/testing/selection.json` if code/tests/fixtures require them. Do not duplicate the manifest's executable selection into prose.
5. A concise final user reply linking the findings and scenario documents, identifying the build installed on BOTH targets, the two UI changes, key reliability/audio results and remaining failed/unrun cases.

Finish when both requested UI changes are implemented and visually/behaviorally verified on the installed candidate; the available-device campaign is executed and documented with honest limits; introduced defects are fixed and retested; required affected checks are run or explicitly identified as incomplete; and temporary test changes are restored. Do not call the work complete merely because the screen compiles or one call succeeds. Leave no test call running, restore temporary settings, and leave the physical phone securely locked with its original credential configuration. No release publication or commit is requested by this handover.
