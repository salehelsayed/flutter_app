# Beta audio call remediation — 2026-09-08

## Incident interpretation

The user confirmed that Android → private iPhone showed “call is unavailable” and the iPhone did not ring, while the reverse direction worked. Fresh relay metadata retained one admitted bidirectional call handle. Together these support a failure before call admission/ringing; the exact historical client failure cannot be recovered from encrypted relay signaling or the expired Redis records. The initial twelve-call timeline is in the adjacent review. Mailbox acknowledgements and push delivery do not prove answered calls or working audio.

The subsequent [individual investigation of all twelve earlier calls](initial-twelve-call-investigation.md) separates their post-storage patterns from the later inferred pre-admission failure. It correlates each handle with registration mutations and retained provider/credential metrics, identifies the 099/100 interleaving, and records the remaining limits on historical cause and audio outcome. The existing code fixes must not be treated as proven explanations for every one of those calls.

## Fixed application defects

- **Cached unavailability:** a conversation could retain a negative remote-endpoint result and only show the unavailable message on later taps. An explicit tap now rechecks current authority, with a ten-second limit, duplicate-tap suppression, and no call from a late result after timeout. Signature, roster, blocking, expiration, grant, and exact-receipt checks still apply.
- **Concurrent endpoint publication:** independent resume/contact/outgoing lanes could publish signed endpoint epochs out of order. Publications are now serialized. Shutdown and native invalidation fence late work, and shutdown waits for a pending write before revoking its exact epoch.
- **Old service disables its replacement:** a delayed failed advertisement from a withdrawn graph could set the replacement graph’s global readiness to false. Readiness is now changed only when withdrawing the currently owned graph. Four regressions cover delayed false/exception outcomes from both resume and contact refresh.
- **Short background reachability:** newly issued endpoint and wake-grant authority now use the same thirty-day lifetime as call push registration. Existing valid grants retain their exact bytes and remaining expiration; their lifetime is not silently extended. Expiry, epoch, and revocation checks remain effective.
- **Incoming controls and notification taps:** Android notification body taps now retain an immutable open-only intent when full-screen permission is denied. Automatic full-screen presentation remains permission-gated. Validated canonical ringing can show in-app Answer/Decline while foregrounded, including after resuming from a notification tap. Unvalidated, wrong-ID, background, and ended projections remain hidden; showing controls never automatically answers.
- **Native answer ownership:** physical validation exposed `audioSessionFailed` after the new foreground Android Answer. The graph was accepting directly in Dart while native Android audio requires a recorded native answer; the native bridge also omitted its existing Dart adapter’s `answer` command. Native-backed Android/iOS answers now require native acceptance, with no direct-Dart fallback on native refusal or exception. The repair passed 171 focused Dart tests, 18 native bridge tests, and the final curated lane. The failing device trace is retained in `android-foreground-answer-failure-before-native-fix.json`; the repaired final packages passed the same physical call direction and Answer surface.
- **TURN credential stalls:** native credential requests now share an absolute four-second budget across candidate relays, with fair remaining-time allocation, grouped transport/address-family dialing, stream deadlines, and cancellation that interrupts blocked reads. This finishes within the Dart caller’s five-second budget.

Each defect has a deterministic regression that failed before its fix. These are demonstrated defects; the relay history cannot identify every one as a cause of every reported failed beta call.

## Production changes already live

At **11:09:01 UTC**, coturn was repaired after checking that active allocations had drained. It now listens on IPv4 and IPv6 for UDP/TCP 3478 and TLS 5349. Matching EC2 ingress was added, the existing authentication secret and relay ACLs were preserved, and a certificate-renewal hook reloads coturn certificates. The rollback backup is `/var/backups/mknoon-turn/20260908T110901Z`.

At **11:16:19 UTC**, the relay was updated to advertise `turns:mknoun.xyz:5349?transport=tcp` alongside existing UDP/TCP URLs and to record fixed-cardinality call-control outcome/wake counters and selective identifier-free failure/withdrawal logs. The deployed Linux binary SHA-256 is `576185104855bfda08ad89c27675825209e76ded0a63074fda7dcf431ace54ec`. The rollback backup is `/var/backups/mknoon-relay/20260908T111619Z`. Service health passed after deployment; no automatic restart loop was observed.

TCP 443 remains the HTTPS listener. TLS 5349 provides another transport, but does not establish support for networks permitting only port 443.

## Validation record

- The complete relay Go test suite passed with Go 1.25.0.
- Native TURN deadline, cancellation, fallback, credential, lease, and bridge tests passed, including focused race detection.
- Publication lifecycle, grant lifetime, platform token, composition, and diagnostics tests passed. The call-button fix passed nine focused conversation call tests and fourteen header tests.
- The final incoming-control batch passed 40 native Android tests and 87 composition/lifecycle tests before its curated regression run.
- Relevant static analysis passed apart from confirmed unchanged `unawaited_return_in_try_block` warnings in `conversation_wired.dart:6844` and `android_call_lifecycle_adapter.dart:1398`. The adapter change is explanatory documentation only.
- External authenticated relay probes exchanged all ten packets over each IPv4/IPv6 UDP and TCP path. TLS certificate chain and hostname verification passed. An independent framed TLS client verified all 400 synthetic payloads across IPv4/IPv6 burst and 20 ms tests. The misleading coturn client count and reproductions are in [turn-tls-probe-investigation.md](turn-tls-probe-investigation.md).
- Android and iOS native bindings were rebuilt with Go 1.25.0; updated Flutter packages include all call feature flags. Source/artifact hashes, native binding checks, and build output are retained locally. Existing app data and the user’s unrelated dirty files were preserved.

The final curated 1to1 gate passed **3,494 tests (4 skipped, zero failures)** across 209 Dart files after all Dart fixes. Native notification checks passed **40/40**. The subsequent native Answer repair passed **18/18** bridge tests and **171/171** focused Dart tests. Six nonfatal widget hit-test warnings occurred in passing pre-existing interaction tests.

Final physical verification used the USB Pixel 6 (Android 16) and USB iPhone 11 (iOS 26.5), with the artifact hashes in [final-build-manifest.json](final-build-manifest.json). Three answered calls passed: iPhone → foreground Android using the in-app Answer button; Android → background iPhone using native CallKit Answer; and a fresh iPhone → Android retry after a declined call. Each reached accepted/connected, used relay-only TURN UDP, recorded inbound and outbound audio RTP, and terminated cleanly. The declined call ended without acceptance or connection. Both exact lab chats were idle with Start enabled and no remaining Answer/Decline/End controls at 12:25:29 UTC. See [final device proof](physical-device-ui-native-answer-final.md).

These checks prove bidirectional audio packet flow and lifecycle cleanup on the available lab pair; they do not measure subjective sound quality or establish the exact private beta iPhone's past failure. The Android observer only reads canonical state/media snapshots; UI/native actions place and answer the real calls. Earlier successful runs and the subsequently discovered foreground Answer failure remain in the adjacent evidence instead of being replaced by the final pass. One earlier click-only attempt remains unclassified because no pre-tap UI evidence survives; the helper now waits for the terminal notice and requires visible outgoing-call state before reporting a start.

The production health capture confirms both services active/running with zero automatic restarts since deployment and the expected relay binary hash. See [production-health-after-remediation.json](production-health-after-remediation.json).

The user explicitly requested enabling Android full-screen call permission. It was enabled on the connected Pixel and verified as `USE_FULL_SCREEN_INTENT: allow`; it remains enabled. This local setting does not alter beta tester phones. Mobile changes require distribution of an updated app build to beta testers; deploying the relay does not install those client fixes.

After QA, the final normal Android APK was restored and its installed SHA-256 matched the build manifest. The app launched, the existing lab conversation had an enabled Start button, and no call or unavailable/error UI remained. The three observer request/result files were removed and the five temporary phone loggers were stopped. Full-screen permission was verified again as `allow`. See [normal-android-restoration.json](normal-android-restoration.json). The Graphify incremental refresh completed; [workflow-audit.txt](workflow-audit.txt) retains the historical navigation-policy misses separately from application validation.
