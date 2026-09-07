# Android notification network matrix — 2026-09-07

**All4 primary ordinary-text lanes and2 additional reaction lanes passed:** a fresh OS notification appeared while the physical Pixel app was backgrounded and had no process immediately before the send. The receiver was never reopened before that case’s OS proof.

The primary ordinary-text cases match the clarified external Android symptom category. That user's network/device are unknown; these passing available test-device cases do not claim to reproduce or resolve that separate incident.

## Targets, setup and timing

Sender: emulator-5554, existing TC256-B account. Receiver: USB Pixel21071FDF600CSC, existing picel account. Both retain installed Android114, version1.0.0-807874437-notification260907-r4; no builds, reinstalls or resets during this latency matrix. Accepted groupf4d26c1d remained unmuted; receiver Group Info Switch checked=false and TC256-B Joined were captured in wifi-group-mute-state.xml. iPhone membership was Invite unknown at that moment; root's later iPhone UI work is separate.

Every case used ordinary Home then `am stop-app com.mknoon.app`, confirmed empty `pidof com.mknoon.app`, and sent from emulator. This is process-absent FCM delivery, not Android force-stop (which intentionally suppresses delivery). Opening/reading the receiver between completed cases was permitted only after OS proof, to clear unread baseline and prepare the next lane. For the final repeated generic-body reaction, the prior group notification was explicitly absent before send, avoiding a stale-card false pass.

All times are host UTC. OS-observed time is a polling upper bound, not exact native post time; exact FCM/native-post events are retained in android-network-os-events.log and raw pixel-logcat.log. Cross-host timeline comparisons must account for Pixel device clock+0.756s at baseline and+0.791s after the network cases (~35ms drift); emulator baseline−0.072s/final−0.033s. No clock was changed.

| Case | Send tap UTC | Fresh OS observed UTC | Tap→observation | Result |
|---|---|---|---|---|
| wifi-direct | 11:24:40.220 | 11:24:53.106 | 12.89s | PASS |
| wifi-group | 11:27:16.509 | 11:27:29.320 | 12.81s | PASS |
| cell-direct | 11:30:52.306 | 11:31:09.512 | 17.21s | PASS |
| cell-group | 11:32:22.926 | 11:32:38.101 | 15.18s | PASS |
| cell-group-reaction | 11:34:32.269 | 11:34:47.266 | 15.00s | PASS |
| wifi-group-reaction | 11:36:35.225 | 11:36:50.268 | 15.04s | PASS |

Ordinary markers are in each *-result.json: LAT-WIFI-DIRECT-260907-1124, LAT-WIFI-GROUP-260907-1128, LAT-CELL-DIRECT-260907-1130, LAT-CELL-GROUP-260907-1132. Reactions used target26af6e62 video in the accepted group, cellular🙏 then restored-Wi-Fi😢. OS direct ID1692567057 and group ID703171339 retained expected routing/title/body.

## Network validation and restoration

Initial Pixel global mobile_data0/Wi-Fi1, default validated Wi-Fi100. SIM loaded and LTE WWAN registered, but cellular internet was initially disabled (IMS over IWLAN was not an internet alternative).

Authorized switch11:29:12.895 enabled mobile data and disabled Wi-Fi. Cellular INTERNET validated11:29:15.191 on default network106; mobileData1/Wi-Fi0 confirmed. Push/wake registration succeeded on cellular before the first cellular send. Each text case includes a contemporaneous full connectivity snapshot.

Original settings restored and verified11:35:29.429: mobileData0/Wi-Fi1, validated default Wi-Fi107. The final Wi-Fi reaction used this restored connection. No hotspot/carrier/APN/router setting was changed. See pixel-network-restore-baseline.json, pixel-cellular-validation.json, pixel-network-restored.json and raw connectivity snapshots.

## What the timing does and does not establish

Messages arrived before reopening on both networks. Wi-Fi direct provider success11:24:40.493 (root journal), FCMraw11:24:41.844 (~41.088 host-adjusted) shows roughly0.60s provider→FCM, followed by about11.93s cold client work to shownraw11:24:53.770. The independent client reviewer owns detailed process/engine/background-handler timing. The observed12–17s cold delivery latency is distinct from the separately reproduced iPhone123s pre-APS-ingress wait at its connection watchdog.

Both USB test iPhones report SIMStatusNotInserted. Native iOS cellular-radio testing is N/A (target unavailable under project policy); no private wireless phone was controlled. Existing iPhone Wi-Fi direct and idle APS results are probe-a/b/c-result.json. Root owns any subsequent accepted-group iPhone Wi-Fi proof through newly available native accessibility control.

## Evidence

Each case has *-process-absent.txt, *-result.json, *-notifications.txt; ordinary cases also have *-network.txt, composed/source XML and notification shade screenshots. actions.jsonl records sends and network transitions. android-network-os-events.log is a focused cold delivery extract, with full raw logs preserved. Captures remain running at report creation because root owns subsequent iPhone work; final closure must append capture stop metadata. Accounts remain intact.


Closure: owned Pixel/emulator/iPhone log captures77752/77753/77754 stopped and verified absent at 2026-09-07T12:39:59.024928+00:00. Pixel restored to Wi-Fi1/mobileData0/hotspotOff with validated Wi-Fi110; original hotspot configuration unchanged. Root restored iPhone original Wi-Fi, forgot temporary hotspot association, backgrounded app and deleted owned Appium session. Accounts retained; Android114 remains installed on both Android targets and iPhone260907113535 retained. Private coordination credential file removed and two owned evidence files redacted. Final healthy iPhone catch-up produced zero new app notifications through12:38:12UTC (>99s after completion). Detailed state: `closure-state.json` in the parent delay-investigation directory.
