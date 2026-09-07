# iPhone latency forensics — independent log review

All timeline times below are UTC on 2026-09-07; raw iPhone syslog uses UTC+2. This is a passive review of retained logs, not another device action or code change.

## Historical delay is before app dispatch

| Milestone | Cleanup reaction d2033819 / 0AFB-A3E7 | Post-deployment reaction ce639f2b / A449-34FC |
|---|---|---|
| Prior relay acceptance | 09:42:54 (root correlation, second precision) | Exact provider acceptance not established by this review |
| Android FLOW sender start, raw device clock | 09:42:54.364 | 10:16:25.349 |
| Timestamp carried in incoming APS packet | 09:42:54.127101396 | 10:16:25.058148968 |
| APSD KeepAliveFailed | 09:44:50.567561 | 10:16:43.719526 |
| APSD closes development courier | 09:44:50.570179 | 10:16:43.723233 |
| APSD receives development connect response | 09:44:51.297834 | 10:16:44.321254 |
| First matching APSD incoming bytes (length 2686) | 09:44:51.615007 | 10:16:44.678581 |
| Parsed protocol incoming message | 09:44:51.647717 (P0715) | 10:16:44.738013 (P0720) |
| APSD receivedPushWithTopic | 09:44:51.668777 | 10:16:44.759195 |
| SpringBoard exact app remote request | 09:44:51.690031 | 10:16:44.781349 |
| NSE begins | 09:44:51.823977 | 10:16:44.833268 |
| NSE authorized active handoff | 09:44:51.862826 | 10:16:44.865040 |
| OS active sound-bearing request | 09:44:51.917548 | 10:16:44.934660 |

The approximately 117.7-second value originally ended at SpringBoard request creation, rather than the earliest APSD bytes. The first matching bytes are about 117.6 seconds after the second-precision relay acceptance. The carried packet timestamp precedes those bytes by 117.487906 seconds. The post-deployment 19.4-second value was raw Android FLOW-start to SpringBoard, not an independently measured provider-acceptance interval; its carried packet timestamp precedes first bytes by 19.620432 seconds. Timestamp origin and historical cross-device clock offset were not independently measured, so these carried timestamps are corroboration rather than asserted provider submission timestamps.

APSD receives and parses each packet immediately after its courier reconnects. Its acknowledgement integer is then repeated by SpringBoard's ApplePushService delegate: 1170500349 for cleanup and 2814272820 post-deployment. The following SpringBoard records explicitly identify com.mknoon.app, priority 10, and the exact request above. Both packets log LastFromStorage with flags 0x03. These records, together with the controlled single-send windows, strongly correlate the exact app requests to the incoming APSD messages without relying on private payload text or exposing tokens. FCM/APNs UUID correlation is unavailable because relevant fields are redacted.

The first incoming-byte record to NSE start takes approximately 209 ms and 155 ms, respectively. There is no approximately 118-second or 19-second app/NSE processing interval in either chain. Both OS presentations occur while the iPhone remains backgrounded, before the controlled reopen. Previously verified absence of duplicate requests after healthy resume remains unchanged.

## Preexisting 600+35-second watchdog, not a reaction retry timer

The cleanup log contains the timer's full origin. At 09:34:15.570 it reports interval 600 seconds, at .571982 grace period 35 seconds, and at .572283 serverOriginatedKeepAlive=1. At .575067 it explicitly schedules the timer for **09:44:50 UTC**. Development protocol P0713 sends a keepalive, and a successful NonCellular acknowledgement arrives at 09:34:15.826806. The timer later fires at 09:44:50.567 and APSD immediately reports KeepAliveFailed, closes that courier, reconnects in less than one second, and receives the queued app packet.

Thus the observed delay is consistent with a push waiting behind a courier that does not receive the expected server keepalive until the existing watchdog detects the failure. The residual wait from send time to that watchdog is the main delay. An unrelated loaded configuration field delayedReconnectTLSInterval=120 does not demonstrate a 120-second backoff: the measured reconnect here is subsecond.

This establishes the device-side recovery mechanism, not the underlying packet-loss cause. The retained logs do not establish whether a WiFi/NAT/firewall path discarded an idle session, an APNs peer failed to deliver, or another transport condition prevented the expected keepalive. No router fault, intentional APNs throttling, or specific TCP reset origin is proved. The earlier XPC interruption record alone was insufficient; this fuller APSD chain supersedes the earlier report's statement that no corroborated transport failure was found.

The issue is not limited to the development channel on this test iPhone: the same retained capture records KeepAliveFailed followed immediately by Closing[production] at 09:27:41.498/.500 and 09:38:21.176/.181, with successful production reconnects at .960 and .638. The user's private phone was on the same WiFi, making the shared path relevant to further tests, but there is no private-phone log proving its incident had this cause.

## Capture scope and current controls

Both historical captures were process-filtered idevicesyslog sessions, including Runner, NotificationService, SpringBoard, usernotificationsd, and apsd. They excluded powerd, networkd and runningboardd. The app wait windows show monotonic device timestamps and continuing records, not a whole-stream gap covering the delay. This does not establish complete network or power history, and the capture has no independent host receipt timestamp for every line.

The new unfiltered capture starts at 11:04:34 UTC. Probe A, event fd3f4f7c / request 727B-B11A, is a **foreground transport control**: the untouched receiver was already foreground. Measured host tap to APSD ingress is approximately 0.607 seconds after the device agent's clock correction; foreground presentation response 0 is expected in this case. Probe B, event 9cbd1cfd / request 1BF9-BB0E, follows explicit backgrounding and suspension. Corrected tap-to-APSD time is approximately 0.571 seconds, and an actual OS sound-play command occurs at 11:11:05.392550. These show prompt current delivery with a working connection, not disappearance of the historical idle failure.

Probe B arrives over P0728, followed by a server cancel-delay-keepalive command. APSD configures interval 600, grace 35, serverOriginatedKeepAlive=1, and explicitly schedules **11:21:39 UTC** at 11:11:04.446538. A successful NonCellular keepalive acknowledgement follows at 11:11:04.723054. This is a forecast for a later idle probe only while no subsequent event resets that timer. Root and the device operator own the next probe and controls.

## Evidence

- Historical raw: devices/iphone11-retention-final-syslog.log; deployment/iphone11-syslog.log.
- Exact incoming-byte/packet/dispatch chains: ios-delay-cleanup-first-byte-chain.log; ios-delay-deployed-first-byte-chain.log.
- Watchdog trigger/reconnect: ios-delay-cleanup-reconnect-trigger.log; ios-delay-deployed-reconnect-trigger.log.
- Full prior timer origin: ios-delay-cleanup-prior-keepalive.log (raw source lines 132913–133243).
- Production/development comparison: ios-delay-cleanup-all-environments.log.
- Current unfiltered raw: delay-investigation/iphone11-syslog-unfiltered.log.
- Current APSD timer/protocol excerpt: delay-investigation/apsd-courier-timing-review.log; apsd-environment-review.log.
- Operator clock/state/timing controls: delay-investigation/probe-a-result.json; probe-b-result.json.

Confidence: high that the historical delays precede app dispatch and delivery follows APSD keepalive-failure recovery; high that both APNs environments exhibit failures on this test phone; unresolved underlying network/peer cause and whether the private-phone incident matches. No source changes are justified by this evidence alone.

## Current unfiltered connection-close control

At 11:13:08.961849 the production courier independently reports KeepAliveFailed. APSD calls _disconnectStream with reason 15, cancels C803, and writes TLS close-notify followed by TCP FIN. Its TLS state was connected immediately beforehand; the path remains WiFi/satisfied/LQM good. A peer FIN arrives about 49 ms after the local FIN. Thus this observed close is locally initiated by the watchdog; it is not evidence of an earlier APNs-initiated close. The connection summary reports 637.244 seconds duration, RTT about 48 ms, and zero retransmitted/out-of-order bytes. Those counters do not exclude loss of inbound packets. Evidence: current-production-watchdog-review.log. Historical cleanup C787 and post-deployment C792 show the same local close-notify/FIN sequence after their watchdog failures (../ios-delay-cleanup-close-origin.log and ../ios-delay-deployed-close-origin.log).

The background B courier is separately identified as P0728/C804, IPv6 TCP5223 on en0/WiFi, not offloaded; timer scheduling explicitly names sandbox.push.apple.com. Production's 11:13:08 reconnect does not reset that separate sandbox timer.

## Predicted idle probe C reproduces the delay

The device operator left the iPhone in Preferences after B, without another iPhone action or network change. C sends one new reaction, event 34850a5a, at **11:19:37.632551 host UTC**. The relay journal stores it at 11:19:37.845395 and reports provider success at **11:19:38.358882**. No corresponding APSD/app ingress occurs until the previously forecast watchdog expires. The sandbox flow's byte/packet counters remain unchanged from immediately after B through 11:20:29, after C was accepted.

At **11:21:39.459523**, APSD reports KeepAliveFailed; it closes development courier C804, writes TLS close-notify at .465384, and sends FIN at .467378. A peer RST arrives at .648326, after this local shutdown begins. This reset cannot be cited as the preceding cause of the idle failure. APSD receives the new development connect response at 11:21:40.263255, then the first matching 2686-byte packet at **11:21:40.671610**. P0730 parses it at .730382; the callback at .755791 carries a timestamp of 11:19:38.279816900 and LastFromStorage0x03. Its ACK3602954237 repeats in SpringBoard's delegate, followed by the exact com.mknoon.app request **0908-A3BF at .790691**.

NSE begins at .836851, decrypts successfully, and hands authorized active content at .858238. SpringBoard adds a sound-bearing active alert at .913038. The exact sound-play decision is 1 at 11:21:41.817450 and an explicit Play sound command follows at .823862. No reopen or receiver touch caused this delivery.

After subtracting the measured iPhone-minus-host offset of approximately 40 ms, tap-to-first-APSD-bytes is **122.999 seconds**, provider-acceptance-to-first-bytes is **122.272 seconds**, and tap-to-APSD callback is **123.083 seconds**. First bytes to NSE start is 165 ms; NSE start to active handoff is 21 ms. These timings independently reproduce the long idle delay and its alignment with the already-scheduled keepalive watchdog, while warm background B took approximately 0.571 seconds.

Evidence: `probe-c-independent-courier-chain.log`, `probe-c-independent-timing.json`; root's journal `../../notification-latency-20260907/relay-journal.log`. The underlying cause of the missing expected server keepalive remains unresolved; this test does not identify which network device or APNs peer discarded or withheld traffic.
