# Owner UI-Update test logs, 2026-10-24

Collected read-only by flutter_app for Astra. No install, no app restart, no data change. Raw files stay on this Mac. Do not mail or paste message content, keys, tokens, peer IDs or PINs out of them.

## Devices and build
- Pixel 6: Mknoon UI-Update 1.0.1 build 127 (UI-Update HEAD 9aa28e7d4, release, debug-key re-signed). Known: the QR scanner fails on this build because R8 drops the ML Kit registrar constructors (fix 4d6065f9d is on main, not in UI-Update). Scan failures on the Pixel are expected.
- iPhone 11: Mknoon UI-Update 1.0.1 build 127, same source, release. Fresh install around 09:55 Berlin. Before that the app was not on the phone.

All times below are Berlin time (CEST, UTC+2). The Pixel log timestamps are Berlin time.

## Files
- `pixel6/logcat_all_dump.txt`: one-off `logcat -d -b all` dump taken 10:58 Berlin.
- `pixel6/logcat_crash_dump.txt`: crash buffer (empty).
- `pixel6/package.txt`, `pixel6/dropbox_mknoon.txt`: version and system dropbox entries for Mknoon.
- `pixel6/logcat_live.txt`: live capture of all buffers from 11:01 Berlin, still running.
- `iphone11/syslog_live_unfiltered.txt`: unfiltered device syslog 11:01 to 11:03 Berlin (stopped, large).
- `iphone11/syslog_live_runner.txt`: live syslog filtered to the Mknoon process `Runner` from 11:02:58 Berlin, still running (about 2 MB a minute).
- `iphone11/app_diagnostics__state.json`, `iphone11/MknoonAppDiagnostics__diagnostics-v1.json`, `iphone11/call_diagnostics__state.json`, `iphone11/MknoonCallDiagnostics__diagnostics-v1.json`: the app's own persisted diagnostics files from its container (copied 11:02 Berlin).
- `iphone11/container_listing.txt`: file list of the app container (names and sizes only).
- `iphone11/crash_reports/`: Mknoon crash and jetsam reports from today. None were found.

## Coverage gaps
- Pixel app logs: the logcat main buffer, which holds the app's own lines, only goes back to 10:48 Berlin. The system buffer goes back to 10:11 and the events buffer to 01:46. Owner testing before 10:48 is NOT covered for app lines. It shows only in system and events lines, such as activity starts, crashes and ANRs.
- iPhone 11: iOS keeps no past syslog that can be pulled without sudo. So there is NO iPhone log from before 11:01 Berlin, only the persisted diagnostics json files. Also this is a release build without FDC_FLOW_LOG, so the app's Dart [FLOW] and print lines do not reach the syslog at all. Only native and Go lines do. For deep iPhone app traces, a flow-log build would be needed.
- From 11:01 Berlin on, both live captures cover new owner testing.

## Repeat run (owner repeated the flow), snapshot folder `repeat-1104/`
Snapshot at 11:04 Berlin. It holds the live Pixel capture up to then, a fresh Pixel all-buffer dump, the iPhone Runner capture up to then, and freshly pulled iPhone diagnostics json files.
Window from the logs: about 11:02 to 11:04 Berlin. Both release builds print no app flow lines, so these marks are rough and come from platform lines:
- 11:02:12 Pixel: the app tried to cancel a notification and it FAILED. `flutter_local_notifications` threw `IllegalStateException: TypeToken must be created with a type argument` in `cancel`/`removeNotificationFromCache`. That is likely the same kind of R8 shrink problem as ML Kit (Gson TypeToken generic signature stripped). It happened again at 11:03:17. Possible effect is that notifications or popups are not cleared. Not verified.
- 11:02:13 Pixel: local discovery TXT record query retry.
- 11:02:52, 11:02:59, 11:03:00, 11:03:11 Pixel: back-handler swaps between the Flutter route and the activity. Each swap is a route push or pop in the app. That makes 4 changes in about 20 s.
- 11:03:03 to 11:03:21 iPhone: 11 keyboard focus requests (text field focus changes).
- 11:03:21 to 11:03:22 iPhone: Apple Neural Engine bursts in Runner, consistent with the camera QR scanner analysing frames.
- No crash, ANR or FATAL on either phone.
Scan decoded, request sent or received, popups and accept cannot be told apart from these logs. A flow-log iPhone build is being installed for the next run.

## iPhone 11 flow-log build 129 (installed 11:11 Berlin)
- The iPhone 11 now runs UI-Update 1.0.1 build 129. It is the same source as 127 (9aa28e7d4) and the same release config, plus `FDC_FLOW_LOG=1`. It was installed over 127 with the data kept.
- From now on, the app's Dart `[FLOW]` lines (JSON with `event` names, peer ids redacted) reach the iPhone syslog.
- `iphone11/syslog_runner_build127_until_1111.txt`: Runner capture of build 127, from 11:02:58 to 11:11 Berlin.
- `iphone11/syslog_live_runner.txt`: Runner capture of build 129 from 11:11 Berlin, still running. Grep `\[FLOW\]` for the app flow.

## Repeat 2 (owner repeated the flow), snapshot folder `repeat-2/`
Snapshot 11:26:52 Berlin. The iPhone 11 runs build 129 with flow logs. The Pixel runs release 127 with no flow lines (platform lines only).
Window of the owner's run: about 11:25:00 to 11:26:40 Berlin.
- 11:25:11 iPhone: the existing Pixel contact was deleted first (DELETE_CONTACT_SUCCESS).
- 11:25:40.27 iPhone: QR scanned and decoded (QR_SCAN_RECEIVED, QR_PARSE_SUCCESS).
- 11:25:40.31 and 11:25:40.98 iPhone: TWO contact requests sent for ONE scan, 0.7 s apart (CONTACT_REQUEST_SEND_START x2). Each tried LAN first and failed (CONTACT_REQUEST_SEND_LOCAL_FAILED), then went through the relay successfully.
- 11:25:41.44 and 11:25:41.95 Pixel: two message:received push events, matching the two requests.
- 11:25:43.4 iPhone: Feed and Orbit screens initialised again (second FEED_FL_SCREEN_INIT).
- 11:25:45.2 iPhone: chat screen opened.
- 11:25:48.96 iPhone: a message sent BEFORE accept failed with CHAT_MSG_SEND_ENCRYPTION_REQUIRED (missing_recipient_key). No retry in the window.
- About 11:25:52 Pixel: accept, inferred. The iPhone got the same contact_request twice (wifi and direct), and the second was flagged CONTACT_REQUEST_V2_REPLAY_DETECTED.
- 11:25:52.64 and 11:25:53.43 iPhone: two more contact requests sent back. 11:25:53.35 and 11:25:53.36: two more received, both CONTACT_REQUEST_ALREADY_CONTACT. iPhone totals: sent 4, received 4.
- Messages iPhone to Pixel: 2 presses, 1 delivered, 1 failed. Pixel to iPhone: 2, each also arrived a second time via the inbox and was dropped correctly as a duplicate.
- Pixel route back-handler changes: 6 route and 4 root between 11:25:13 and 11:26:13. The 11:26:13 pair flips within 2 ms, which may be a double push or pop.
Errors: Pixel notification cancel TypeToken failure x3 (known, fix be4d72e3f). iPhone LAN request send failed x2 (relay fallback OK). iPhone send before accept failed x1. iPhone profile picture download "not found" x2. No crash, ANR or FATAL.
Caveats: no flow event names a dialog or popup, so popups cannot be counted. The Pixel side is inferred, because it is a release build without flow lines.

## Rebuild to e37f4f50e build 130
Source UI-Update e37f4f50e (9aa28e7d4 plus main be4d72e3f merged, with the ML Kit and Gson keep rules). Uncommitted files in that tree are 2 harness files and the root info.plist only, with no app code.
- Pixel 6: release APK 1.0.1 build 130, debug-key re-signed, installed with install -r at 12:41:15 Berlin. Data kept (first install time unchanged). The live Pixel capture `pixel6/logcat_live.txt` kept running across the install.
- iPhone 11: release build 1.0.1 build 130 with FDC_FLOW_LOG=1, installed over 129 at about 12:46 Berlin. Data kept (identity found at launch).
  - The build 129 Runner segment is saved as `iphone11/syslog_runner_build129_until_1246.txt`.
  - The new live capture `iphone11/syslog_live_runner.txt` starts at 12:46 Berlin.

## Notes for Astra after build 130
- Pixel, about 12:42 Berlin, seen once and not repeated: on Settings then Scan, two system Back presses did not leave the scan screen. The close button worked. If the owner hits it, check the Pixel logcat around that time for WindowOnBackDispatcher lines.
- Pixel, about 13:00 Berlin: the old sims test package from TRANSFER-011 was uninstalled (that exact package only). Before that it had come to the front once after the scanner closed, showing its own "Local account data erased" screen, which is not Mknoon. Mknoon is still installed at build 130.
