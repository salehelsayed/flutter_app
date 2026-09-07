# Accepted iPhone group notifications on shared Wi-Fi

2026-09-07; Pixel6 `21071FDF600CSC` sender (Android114), USB test iPhone11 `00008030-001A6D2801BB802E` receiver (app260907113535). Existing group `f4d26c1d-a7ae-40c3-9c37-5577b0f6c31f`. Accounts retained.

Root reused signed installed WDA through Appium MCP with corrected readiness timeout; no Xcode build. iPhone accepted group11:50:44UTC and UI confirmed joined/history. Root backgrounded11:51:41, verified suspended11:51:55. Group notification tap later routed to this exact group and fresh text correctly. Root owns corresponding Appium page sources/screenshots under `build/notification-latency-20260907/`.

| Case | Sender action UTC | First APS receipt UTC (device clock) | OS request | Result |
|---|---|---|---|---|
| Ordinary text ce2ec7ce |11:52:34.024455|11:53:39.799230|440A-474A|Correct text, alert, actual sound, banner, list before reopen; ~64.7s provider-to-ingress wait|
|❤️ reaction to iPhone-authored5e328709|11:58:35.644099|11:58:36.812964|8D13-1B27|Correct reaction wording, alert/sound/banner before reopen|
| Synthetic video notification-review.mp4|12:00:02.744641|12:00:04.877528|DCCE-42B8|“picel: Video”, alert/sound/banner before reopen|
|19s test voice0ea648c6|~12:02:01.216 (Pixel raw stop12:02:02.007)|12:02:03.799180|8024-5D51|“picel: Voice message”, alert/sound/banner while UI locked|
| Synthetic photo notification-review.png|12:04:21.522817|12:04:23.635146|5050-AE63|“picel: Photo”, alert/sound/banner while UI locked|

All five NSE cases decrypted successfully and handed off authorized active content. Root independently captured exact Notification Center wording for each, including fresh text marker `LAT-IOS-WIFI-GROUP-260907-1152` and reaction `picel reacted ❤️ to your message`. The iPhone ordinary reaction target was created11:57:48.971, then receiver again suspended11:57:55. No receiver reopen occurred during any delivery observation.

Text latency again preceded iPhone ingress: relay provider acceptance11:52:35.022230; development APNs keepalive failed11:53:38.483805, reconnected11:53:39.217159, then delivered stored message with LastFromStorage0x03. NSE authorized by11:53:40.019114 and OS presentation followed promptly. This preserves the unresolved network-path finding; warm subsequent media/reaction deliveries do not prove idle latency resolved.

Voice timing note: Stop recording sends immediately. A subsequent tap accidentally began a second recording, which was cancelled without sending. Only one voice message/remote notification was sent; JSON records corrected to actual stop/send.

Exact cases: `ios-group-*-result.json` and `ios-group-*-receipt.log`; full evidence `iphone11-syslog-unfiltered.log`, `pixel-logcat.log`. Independent text chain `ios-accepted-group-independent-proof.log`. Raw iPhone clock is about40ms ahead of host; Pixel about791ms ahead. All times above UTC.


Closure: owned Pixel/emulator/iPhone log captures77752/77753/77754 stopped and verified absent at 2026-09-07T12:39:59.024928+00:00. Pixel restored to Wi-Fi1/mobileData0/hotspotOff with validated Wi-Fi110; original hotspot configuration unchanged. Root restored iPhone original Wi-Fi, forgot temporary hotspot association, backgrounded app and deleted owned Appium session. Accounts retained; Android114 remains installed on both Android targets and iPhone260907113535 retained. Private coordination credential file removed and two owned evidence files redacted. Final healthy iPhone catch-up produced zero new app notifications through12:38:12UTC (>99s after completion). Detailed state: `closure-state.json` in the parent delay-investigation directory.
