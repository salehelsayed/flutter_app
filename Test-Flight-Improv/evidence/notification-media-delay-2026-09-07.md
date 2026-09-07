# iPhone 13 → iPhone 11 media notification delay, 7 September 2026

The notification waited approximately **182 seconds before reaching the iPhone 11's Apple push daemon**. The phone's development APNs connection missed its expected keepalive; its existing 600-second interval plus 35-second grace period expired, iOS reconnected, and a stored notification immediately arrived. The relay accepted both photo uploads quickly and reported successful first-attempt push submissions. Mknoon's notification extension processed the delivered notification in approximately **38 ms**.

This independently reproduces the mechanism found earlier today in [the notification latency investigation](notification-latency-2026-09-07.md). It establishes the stalled connection and watchdog recovery, while leaving the cause of the missing network traffic unresolved.

## Current incident timeline

All displayed times are **Europe/Berlin, UTC+2, on 7 September 2026**. Relay logs use UTC; iPhone logs include their +0200 offset.

| Event | Local time | Evidence |
|---|---|---|
| First photo `bc14bb29…` upload completes | 16:55:10.598 | Relay: 342,134 encrypted bytes, upload took 189 ms |
| First message stored / provider success | 16:55:10.687 / 16:55:11.294 | 607 ms; success on attempt 1 |
| Second photo `7f27ae1f…` upload completes | 16:55:30.098 | Relay: 342,134 encrypted bytes, upload took 230 ms |
| Second message stored / provider success | 16:55:30.190 / 16:55:30.691 | 502 ms; success on attempt 1 |
| iOS watchdog reports `KeepAliveFailed` | 16:58:31.630 | Sandbox/noncellular APNs; development connection closes |
| New development connection established | 16:58:32.202 | Historical iPhone OS log |
| First matching incoming push bytes | 16:58:32.597 | 2,984 bytes; subsequent packet marked `LastFromStorage`, flags 0x03 |
| SpringBoard receives Mknoon push | 16:58:32.619 | Priority 10; request `2C26-4155` |
| Extension starts / returns authorized content | 16:58:32.666 / 16:58:32.704 | Decryption succeeds; active presentation; 38 ms |
| OS marks notification delivered | 16:58:32.728 | User-visible push `2C26-4155` |
| Banner begins appearing / sound command | 16:58:32.850 / 16:58:32.854 | Same notification request |
| Banner fully appeared | 16:58:34.307 | OS banner completion record |
| User taps notification | 16:58:39.243 | OS default-action record for `2C26-4155` |
| Recipient connects to relay | 16:58:41.468 | Four pending messages |
| Photos finish downloading | 16:58:41.822 / 16:58:42.205 | Second photo, then first photo |

The user explicitly confirmed the notification appeared before opening Mknoon. The OS banner and later tap records independently confirm this; media download times are not notification arrival times.

## Why the wait lasted about three minutes

At **16:47:56.618**, the sandbox push connection configured a **35-second grace period**. At **16:47:56.620**, it sent a keepalive with a **600-second interval**, receiving a successful acknowledgment at **16:47:56.860**. The next watchdog failure occurred **635.010 seconds** after that keepalive, at 16:58:31.630. The photo pushes arrived during the remaining portion of that preexisting watchdog window. This was not a three-minute retry timer started by the media send.

The failed connection used IPv6 TCP port 5223 over Wi-Fi (`en0`). At closure, iOS still classified the Wi-Fi path as satisfied, viable, and good link quality. Production APNs also reported `KeepAliveFailed` at 16:58:32.456. The development connection's local watchdog closure preceded the new connection and stored-message receipt.

The incoming packet carried timestamp **14:55:30.546925551 UTC**, aligning with the second photo's provider submission. APSD's calculated server time at receipt was **14:58:32.611377 UTC**, approximately **182.064 seconds** later. The acknowledgment integer `2426707545` links APSD receipt to SpringBoard delivery, followed by the exact Mknoon request. SpringBoard independently preserved the notification's original **14:55:30 UTC** timestamp.

The extension's own start-to-handoff interval was **37.981 ms**; the OS measured the broader extension operation as **75.519 ms**. Thus neither notification decryption nor media download accounts for the long wait. Approximate cross-machine provider-to-ingress time is 181.905 seconds; no independent historical relay/iPhone clock calibration was performed, so subsecond cross-machine precision is not claimed.

## Correlation and limits

- Both relay push successes were on attempt 1. The captured journal spans 14:45:02–15:02:40 UTC and contains no push retry/failure or coordinator-error marker. The live relay retained PID 1043663, zero automatic restarts, and the previously deployed SHA-256 `746107033681ea47c8d02d9869befa6b5e31ff0f550e3979a63e188d0abf3f94`.
- Push-success logs omit recipient/message IDs. Matching them to the two media sends is strong temporal correlation. Two additional untyped stores occurred between the photos, but no other push successes occurred in the captured window. The stored APNs timestamp and exact OS request establish the second send's delayed notification chain.
- Only one Mknoon remote notification request appears in the 14:54–15:00 UTC OS window. This review does not establish the first photo's separate notification fate or claim that APNs coalescing is proved.
- The failed connection and recovery are confirmed. These logs do not identify whether the router, ISP, firewall/NAT path, or Apple endpoint caused the missing keepalive/push traffic. Earlier same-day alternate-uplink controls support the original Wi-Fi internet path as a factor, without uniquely attributing the fault.
- Installed developer builds: iPhone 13 `260906021114`; iPhone 11 `260907113535`. This is physical-device development APNs evidence, not a new App Store distribution test.

## Retained evidence

Read-only collection; no test messages, device navigation, app restarts, installations, network changes, or production-code edits were performed. All owned collection processes completed.

- [Compact iPhone OS chain](../../build/notification-media-delay-20260907/iphone11-key-evidence.log)
- [Historical iPhone incident log](../../build/notification-media-delay-20260907/iphone11-incident-system.log)
- [Compact relay events](../../build/notification-media-delay-20260907/relay-key-evidence.log)
- [Relay journal](../../build/notification-media-delay-20260907/relay-journal.log)
- [Relay timeline measurements](../../build/notification-media-delay-20260907/relay-timeline.json)
- [Device build and media metadata](../../build/notification-media-delay-20260907/device-summary.json)

Full collected device archives and the earlier watchdog excerpt remain under `/tmp/notification-delay-20260907/os/`. Raw evidence under `build/` is local and ignored by Git.
