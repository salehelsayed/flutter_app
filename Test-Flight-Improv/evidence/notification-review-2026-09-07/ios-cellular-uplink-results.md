# iPhone via Pixel cellular hotspot

USB test iPhone11 remains Wi-Fi radio connected to Pixel6 hotspot; Pixel upstream is validated LTE cellular `rmnet1`, network108. This is **cellular internet uplink parity**, not native iOS cellular-radio proof (both USB iPhones have no SIM). Same installed app builds and accounts. No app build or production source change in this probe.

Pixel baseline was mobileData0/Wi-Fi1/hotspotOff. Original hotspot configuration reused without edits; password stored only in0600 private coordination file. Root Appium connected iPhone to hotspot and left MKnoon suspended in Settings. Pixel tethering reports one downstream client, TetheredState lastError0, rmnet1 upstream.

New iPhone APNs development connectionC818 used IPv6 TCP5223 over en0, matching original IPfamily/port/radio. Upstream network changed to cellular.

|Case|Host send UTC|APSD receipt UTC (device clock)|OS request|Result|
|---|---|---|---|---|
|Warm direct ordinarytext|12:13:41.811983|12:13:43.190025|01A7-5A78|PASS actual sound/banner before reopen|
|Warm group ordinarytext|12:14:28.009317|12:14:29.383430|44B2-594A|PASS actual sound/banner before reopen|
|Direct after9m30 idle|12:24:00.004916|12:24:01.273290|95B4-0417|PASS~1.23s send→ingress adjusted, actual sound/banner|
|Group20s after direct|12:24:20.004875|12:24:21.161278|E2C1-87D9|PASS~1.12s send→ingress adjusted, actual sound/banner|

All four NSE events decrypted successfully, authorized active content and showed before receiver reopening. No stored-message flag or courier keepalive failure accompanied either12:24 receipt. The direct idle case resets the APNs timer when it arrives, so the group case is a warm preservation check rather than a second independent9-minute idle case.

Compared with shared Wi-Fi: the same iPhone previously waited123s for an idle reaction and~65s for accepted group text, each ending at development APNs keepalive failure/reconnect with stored-message delivery. Hotspot idle direct passed promptly. This isolates a connection-path-dependent finding; it does not uniquely identify a router, ISP or Apple-side component, nor establish the separate external Android user's historical cause.

Evidence: `*-result.json`, `*-receipt.log`, `idle-live-receipt.log`, `iphone-apns-network-transition.log`, `tethering-associated.txt`, `connectivity-associated.txt`. Full original iPhone capture remains `../iphone11-syslog-unfiltered.log`. Baseline iPhone clock~40ms ahead of host, Pixel~791ms ahead.

Network restoration is tracked separately in `RESTORE_REQUIRED.json`; do not assume restored until pending=false and final device state proofs saved.


Closure: owned Pixel/emulator/iPhone log captures77752/77753/77754 stopped and verified absent at 2026-09-07T12:39:59.024928+00:00. Pixel restored to Wi-Fi1/mobileData0/hotspotOff with validated Wi-Fi110; original hotspot configuration unchanged. Root restored iPhone original Wi-Fi, forgot temporary hotspot association, backgrounded app and deleted owned Appium session. Accounts retained; Android114 remains installed on both Android targets and iPhone260907113535 retained. Private coordination credential file removed and two owned evidence files redacted. Final healthy iPhone catch-up produced zero new app notifications through12:38:12UTC (>99s after completion). Detailed state: `closure-state.json` in the parent delay-investigation directory.
