# Notification delay investigation — 2026-09-07

This follow-up separates three observations: the user's private iPhone reaction delay on the same Wi-Fi as the test phones; another user's Android **text-message** notifications appearing only after opening the app, with model/network unknown; and controlled tests on the available devices. Neither external incident has a device-log correlation. The original review and deployment evidence are in [notification-review-2026-09-07.md](notification-review-2026-09-07.md).

## iPhone: reproduced delay before the app receives the push

The USB test iPhone missed an expected Apple push keepalive. iOS waited for its already scheduled connection watchdog, reconnected, and immediately received the stored notification. The receiver remained backgrounded and untouched throughout. This establishes the delayed-delivery mechanism; it does not identify whether the missing traffic was caused by the Wi-Fi/router path, an Apple endpoint, or another transport fault.

The controlled warm-background reaction reached Apple's push daemon about **0.57 seconds** after the Android send. Its connection scheduled a 600-second keepalive interval plus 35-second grace period, explicitly forecasting a watchdog at 11:21:39 UTC. After leaving the iPhone idle, a single new reaction reproduced the delay at that exact watchdog:

| Milestone | UTC |
|---|---|
| Physical Android send tap | 11:19:37.632551 |
| Relay durable custody | 11:19:37.845395 |
| Provider reports success | 11:19:38.358882 |
| iOS reports `KeepAliveFailed` | 11:21:39.459523 |
| New Apple push connection response | 11:21:40.263255 |
| First matching incoming push bytes | 11:21:40.671610 |
| Notification extension starts | 11:21:40.836851 |
| Extension hands back authorized alert | 11:21:40.858238 |
| SpringBoard requests sound playback | 11:21:41.823862 |

After measured clock correction, provider acceptance to first incoming bytes was **122.27 seconds**; the extension's own processing took **21 milliseconds**. The incoming message was marked as coming from storage. Its acknowledgement integer links the Apple push daemon to the exact app request `0908-A3BF`, independently of private payload contents. The iPhone did not need an app reopen to receive it.

The earlier approximately 118-second and 19-second iPhone cases show the same keepalive-failure/reconnect/stored-delivery sequence. The older 19.4-second number was sender FLOW-log to SpringBoard, not an independently measured provider interval. Both development and production Apple push connections exhibit watchdog failures on this test phone; the tested app itself uses development APNs signing. No App Store distribution parity is claimed.

iOS initiated the observed TLS/TCP closes **after** its watchdog fired. The later peer FIN/RST is not evidence of an earlier Apple-initiated disconnect. Wi-Fi remained reported as satisfied with good link quality. USB packet capture corroborates flow ordering, but its tool writes host read-time timestamps, so syslogs are the timing authority. This evidence supersedes the original report's unassigned iPhone pre-ingress delay, while leaving the underlying missing-packet cause unresolved. Same-Wi-Fi exposure makes the private incident relevant but does not prove it had the same cause.

## Android: both text lanes delivered before opening on both networks

Sender: existing emulator `emulator-5554` (Android 15). Receiver: USB Pixel 6 `21071FDF600CSC` (Android 16). Both used Android build 114, with accounts preserved. Each case confirmed the receiver process absent using `am stop-app`, with the package not force-stopped. A fresh marker was verified in the actual notification shade and OS notification records before opening the receiver. Group membership was accepted and the group unmuted.

| Receiver network | Message lane | Send to observed OS card | Result |
|---|---|---:|---|
| Validated Wi-Fi | 1:1 text | 12.89 s | Delivered before opening |
| Validated Wi-Fi | Group text | 12.81 s | Delivered before opening |
| Validated LTE cellular internet; Wi-Fi off | 1:1 text | 17.21 s | Delivered before opening |
| Validated LTE cellular internet; Wi-Fi off | Group text | 15.18 s | Delivered before opening |
| Validated LTE cellular internet; Wi-Fi off | Group reaction | 15.00 s | Delivered before opening |
| Restored validated Wi-Fi | Group reaction | 15.04 s | Delivered before opening |

OS observation is a polling upper bound. The Wi-Fi direct case reached Android's FCM receiver about **0.60 seconds after provider success**, then spent about **11.93 seconds** starting and processing the background client before posting. Independent direct/group traces split this into approximately 5.1–5.3 seconds before the Dart handler and 6.6–6.8 seconds inside it. The installed Android APK is a **debug build** with VM/JDWP activity; these are not release-performance measurements. The normal handler budget applies (8-second aggregate/2-second phases), and it starts after Flutter/Firebase startup. There was no observed ANR, fatal exception, or notification-deadline failure in these cases.

Mobile data was enabled only for the cellular cases, and Wi-Fi was disabled to prove cellular internet was actually the default validated path. The original Pixel settings were restored and verified: Wi-Fi on, mobile data off. Both connected test iPhones report no SIM. Native iOS cellular-radio testing is **N/A (target unavailable by project policy)**. The private wireless phone was never controlled.

These results exercise the external Android report's ordinary-text category, but they do not reproduce or establish the cause of that user's incident. The earlier test Pixel's approximately two-minute delay ended at a GCM heartbeat/retry boundary before app opening; its retained logs do not prove a transport reconnect or Wi-Fi fault.

## iPhone comparison using a cellular internet uplink

Appium connected the iPhone to the Pixel's existing secured hotspot. The Pixel had Wi-Fi reception disabled, mobile data enabled, one associated tether client, and a validated LTE internet upstream. The iPhone still used its Wi-Fi radio; this does not turn the unavailable native iOS cellular-radio leg into a pass. The original hotspot name/security/password were unchanged, and the temporary credential copy was deleted after testing.

| Hotspot control | Result before app reopening |
|---|---|
| Warm direct text, 12:13:41.812 UTC | APSD ingress in approximately 1.34 seconds; active alert/sound request `01A7-5A78`. |
| Warm group text, 12:14:28.009 UTC | APSD ingress in approximately 1.33 seconds; active alert/sound request `44B2-594A`. |
| Direct text after approximately 9.5 minutes idle, 12:24:00.005 UTC | APSD ingress in approximately 1.23 seconds; active alert/sound request `95B4-0417`. Independent review confirms the unchanged development courier C818/P0737 had no protocol activity for 571 seconds before this message. |
| Group text 20 seconds later, 12:24:20.005 UTC | APSD ingress in approximately 1.12 seconds; active alert/sound request `E2C1-87D9`. This is a warm group preservation control: the preceding direct receipt reset the connection keepalive. |

Exact direct/group markers were visible together in Notification Center before reopening. There was no stored-delivery flag or keepalive-failure recovery in these receipts. Both paths used IPv6 TCP port 5223 on the iPhone's Wi-Fi interface. Production-courier activity during the idle window belonged to a different connection and did not reset this app's development courier.

This comparison supports the shared Wi-Fi internet path as a factor in the reproduced iPhone delay. It does not uniquely identify a router, ISP, firewall, or Apple peer fault, and a successful bounded control is not a guarantee that cellular delivery can never be delayed. The iPhone's temporary hotspot entry was forgotten and its original Wi-Fi selection verified at 12:31:09 UTC. The Pixel was restored to Wi-Fi on, mobile data off, hotspot off, with validated Wi-Fi internet. See [cellular-uplink evidence](notification-review-2026-09-07/ios-cellular-uplink-results.md).

## Separate relay recovery defect fixed and validated

Current-source audits found that ordinary direct text uses durable custody regardless of presence. Stale online presence and write-only direct-send acknowledgements do not cancel this route. Group-topic and strict group-content routes are separate. The previously deployed reaction wake-authorization fix therefore cannot explain every ordinary-text report.

A deterministic provider-failure counterexample found a separate recovery gap: after the immediate Android notification sends exhaust transient retries, durable message custody alone does not schedule a later ordinary rich notification retry. Provider recovery without another event/app open can leave the notification unsent. This is a reproduced conditional defect, **not an attribution of the external Android incident**.

The new Android-only path atomically retains filtered encrypted notification material and its retry obligation with new direct, protected-direct, group-topic, or strict-group custody. It uses the existing coordinator's immediate first claim, backoff and five-second provider deadline. Failed attempts can recover automatically after provider recovery or relay restart, even when ordinary message retrieval has removed the inbox row. Each attempt resolves the current Android provider route. No provider token or plaintext notification preview is retained in the retry snapshot.

Accepted provider results and terminal outcomes remove active retry material and keep an exact completion marker until the original custody deadline, at most seven days. Completion markers have separate keys so successful traffic does not fill the existing 512 active-job slots. Active-capacity fallback retains the existing immediate-send behavior; this is bounded recovery, not an unlimited durable queue. Existing opaque authentication, strict-group gates, iOS ambiguity handling and provider-size rescue are preserved. Redis bootstrap enables the path without a new feature flag. It applies to newly admitted eligible messages and does not backfill older custody rows.

Focused tests cover automatic recovery across both legacy and encrypted registration backends, direct/group/protected/strict stores, restart after message ACK, token rotation, privacy rejection, atomic storage failure, 520 successful completions without exhausting active slots, expiry, cancellation/deadline recovery and concurrent workers. A separate regression preserved the existing one-shot provider-size rescue. The final complete relay module and full race sweep each passed **1,118 test/subtest records, one existing skip, zero failures**; `go vet` passed. Independent source/test review found no remaining blocker.

The tested binary was deployed at **12:28:08 UTC**. Live SHA-256: `746107033681ea47c8d02d9869befa6b5e31ff0f550e3979a63e188d0abf3f94`; previous binary retained at `/usr/local/bin/relay-server.pre-android-rich-retry-20260907T122807Z`. Checksum, durable-backend and service-health checks passed; PID 1043663 remained active with zero automatic restarts. The version string remains v1.10.5; the SHA identifies this build. See [deployment evidence](notification-review-2026-09-07/android-rich-deployment.json) and [validation](notification-review-2026-09-07/android-rich-validation.json).

Post-deployment emulator-to-Pixel ordinary direct and group texts both produced their exact fresh OS cards with the Pixel process absent and before reopening. Send-to-observed-card intervals were 17.16 and 12.78 seconds on the installed debug client. A read-only aggregate Redis probe moved from zero completed markers before deployment to exactly two expiring completed markers after these two controlled sends, with zero retained material keys and no due-index key. The markers had less than seven days remaining. The probe used only SCAN/PTTL and disclosed no payload, credentials, or complete Redis keys. It is an aggregate observation, not a transactional snapshot or an induced live provider-failure test.

A designated physical-Pixel-to-iPhone group text then passed against the new relay: `LAT-RELAY2-IOS-GROUP-260907-1235`, send 12:35:39.486 UTC, APSD ingress in approximately 1.08 seconds, request `9E3D-D3FC`, authorized active alert and OS sound-play command before reopening. Healthy direct/group catch-up completed at 12:36:32.503 UTC with zero group-drain errors. No new app local/remote notification, OS-add, or sound request appeared through 12:38:12 UTC, more than 99 seconds afterward.

Provider acceptance and Redis settlement remain separate operations, so a lost settlement can cause an at-least-once resend; existing client event deduplication still matters. No destructive storage migration occurs. The old binary preserves message custody and registrations on rollback but does not understand new pending rich retry jobs and can strand their retry progress; rollback must not be described as preserving that new progress. Added material/completion keys retain their bounded original expiry.

## Accepted-group iPhone checks and Appium

Detailed traces and clock/state controls are under `build/notification-review-20260907/delay-investigation/`: `ios-delay-forensic-review.md`, `probe-c-independent-courier-chain.log`, `probe-c-independent-timing.json`, `android-network-matrix.md`, `android-network-os-events.log`, and `android-cold-start-review.md`. Raw syslogs/logcats remain in that directory. Relay journal, provider audit, counterexample output, and USB packet-capture metadata are under `build/notification-latency-20260907/`. Raw transport material is retained locally rather than copied into this compact report.

Appium MCP established actual physical-iPhone UI control. The first attempt reused cached WebDriverAgent 16.9.1 and signed it with the existing recommended development profile. Logs showed successful launch/automation access followed by host-requested termination at the 30-second timeout. A single corrected attempt reused that installed driver, omitted the reinstall path, and allowed 90 seconds; it connected in 14.9 seconds. No Xcode harness rebuild was needed. The MCP summary's generic `iPhone Simulator` display name was misleading; the explicit USB UDID and matching device-log process IDs establish the physical target.

The group invitation was accepted through the UI at 11:50:44 UTC. The conversation displayed history and the local member-joined event. After backgrounding, both Appium state 2 (suspended) and SpringBoard page source confirmed the receiver state.

| Check | Observed result |
|---|---|
| Accepted group ordinary text | Pixel sent `LAT-IOS-WIFI-GROUP-260907-1152` at 11:52:34.024 UTC; relay stored it at .663768 and the iOS provider attempt was accepted at 11:52:35.022230. Apple push ingress waited until 11:53:39.799, immediately after another keepalive failure/reconnect. Request `440A-474A` was authorized, added as active alert/sound, and issued an actual OS sound-play command at 11:53:40.806. Receiver was unopened. |
| Notification Center text | Actual Appium screenshot and accessibility source show the correct group title and `picel: LAT-IOS-WIFI-GROUP-260907-1152` before app reopening. |
| Group notification tap | Tapping that exact notification at 11:57:02 UTC opened the group conversation with the matching message visible. |
| Group reaction to recipient-authored message | iPhone sent `LAT-IOS-GROUP-REACTION-TARGET-260907-1157`, then returned to confirmed suspended state. Pixel reacted with a heart at 11:58:35.644 UTC. Push ingress followed in about 1.13 seconds; request `8D13-1B27` was authorized active and issued an OS sound-play command at 11:58:38.275 before reopening. |
| Group video | Exact synthetic fixture `notification-review.mp4` was sent at 12:00:02.745 UTC. Push ingress followed in about 2.09 seconds; request `DCCE-42B8` was authorized active and issued an OS sound-play command. Appium source and screenshot show `picel: Video` before reopening. |
| Group voice | One test clip was sent by the recorder's Stop action at approximately 12:02:01.216 host UTC. Request `8024-5D51` reached APSD at 12:02:03.799, was authorized active, and issued an OS sound-play command at 12:02:05.259. Appium source and screenshot show `picel: Voice message` while the app remains backgrounded. An accidentally started second recording was cancelled without sending. |
| Group photo | One synthetic photo was sent at 12:04:21.523 UTC. Push ingress followed in about 2.07 seconds; request `5050-AE63` was authorized active and issued an OS sound-play command at 12:04:24.853. Appium source and screenshot show `picel: Photo` before reopening. |

The approximately 65-second accepted-group text delay reproduces the same pre-app Apple push connection mechanism as direct reactions. Subsequent group reaction/video/voice/photo checks show prompt delivery on the reconnected route. The reaction's actual visual copy is `picel reacted ❤️ to your message`. The rejected/pending-group sanitizer boundary and the earlier full iOS native suite retain their passing evidence in the original review. The alternate-uplink comparison is documented above. Older generic Notification Center cards visible behind fresh test cards are marked three hours old; they are not evidence of newly duplicated alerts.

An independent catch-up review found 16 updates to the same local summary request during initial invitation acceptance, with one sound followed by 15 silent updates. This happened while the acceptance UI was still processing, before the conversation was confirmed visible. The later 11:57 notification-tap resume created no new local or remote requests. The retained traces therefore do not reproduce another duplicate-alert defect.

Compact detailed reports are retained in `notification-review-2026-09-07/`: [Android network matrix](notification-review-2026-09-07/android-network-matrix.md), [iPhone accepted-group matrix](notification-review-2026-09-07/ios-accepted-group-matrix.md), [iPhone transport forensics](notification-review-2026-09-07/ios-delay-forensic-review.md), [Android startup timing](notification-review-2026-09-07/android-cold-start-review.md), and [group catch-up audit](notification-review-2026-09-07/ios-group-accept-catchup-review.md).

## Closure

All owned device captures stopped at 12:39:59 UTC, and the read-only relay journal capture stopped at 12:40:02 UTC. The owned Appium session was deleted, both phones returned to their original networks, temporary hotspot credentials were removed from owned evidence, and test accounts were preserved. The relay remained healthy on the deployed checksum at the final check. The client-side fixes from the original review still require an updated app release on private phones. The external Android text incident remains unattributed; these tests do not identify that phone’s model or original network.

Graphify impact coverage is complete with no pending changed paths, and the architecture graph was refreshed. Workflow telemetry retains two historical navigation failures (5/7 diagnostic gates); these are not reported as passing workflow gates or as notification-test failures. The earlier full Dart invocation history and focused repairs remain accurately recorded in the original review.
