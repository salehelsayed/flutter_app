# Beta test coverage (Claude beta-tester rounds, 2026-09-24 to 2026-10-01)

Read this before planning a beta round, so finished scenarios are not repeated.
All run folders are on the Mac checkout `/Volumes/CrucialX9/flutter_app`. They are **gitignored**
(`artifacts/beta-*`), so they exist only on that disk. Flows and runners are in `docker-ws/beta/`
(Maestro flows in `docker-ws/beta/flows/`, round 2 flows in `docker-ws/beta/flows/r2/`).

## Where the runs are

| Round | Devices | Report | Run folders |
|---|---|---|---|
| Round 1, 09-24 | iPhone 15 simulator + Pixel 7a emulator, production relay | `artifacts/beta-20260924/run-20260924-220502/BETA_REPORT.md` | `artifacts/beta-20260924/run-20260924-220502` |
| Round 1 reruns on fix builds, 09-25 to 09-27 | same | same report, sections "Fixed-build reruns" onward | `artifacts/beta-20260925/run-*` (full rerun: `run-20260926-185802`; TURN probe: `turnprobe/`; Jev scorecard: `jev/`) |
| Round 2, 09-27 | same | `artifacts/beta-20260927/BETA_REPORT_R2.md` | `artifacts/beta-20260927/run-20260927-174851` (phases A–E), `run-20260927-205235` (phase F), `run-20260927-210953` (re-run); crash reports in `crash/` |
| Round 2 fix validations, 09-28 to 09-30 | same | same report, sections "R2-1 fix validated" onward; handoffs `R2-8_…`, `R2-9_…`, `R2-10_…_HANDOFF.md` in `artifacts/beta-20260927/` | `artifacts/beta-20260928/run-*`, per-fix builds `build-r2-*`, evidence `r2-*` |
| iPhone check of the R2 open-issue fixes, 10-01 | USB iPhone 11 + iPhone 13 (real devices) | `artifacts/beta-20260927/R2-OPEN_REMAINING_ISSUES_HANDOFF.md`, last two sections | logs `docker-ws/deploy-captures/r2o-261001145252`, `r2o-261001155657`; screenshots `artifacts/beta-20260928/r2o-shots` |
| Round 3: Android checks on a real phone, 10-08 | Pixel 6 (physical, `21071FDF600CSC`, account "puxel") + USB iPhone 13 ("iphone-13"), production relay. Pixel: debug build `1.0.0-d54318060.d132.t261008194107` (current tree + R2-11 fix). iPhone 13: release + FDC_FLOW_LOG `1.0.054318060.135.261008195113` | `artifacts/beta-20261008/timeline.txt` | `artifacts/beta-20261008/{logs,shots,ui}`; scripts `docker-ws/beta/v3/` |

Each run folder holds the Android logcat, the iPhone app log, Maestro output per scenario (`maestro/`),
screen dumps (`ui/`) and a `timeline.txt`. Error scan: `python3 docker-ws/beta/r2_errors.py <run folder>`.

## What was tested (latest result)

### 1:1 messaging
| ID | Scenario | Result |
|---|---|---|
| S01–S03 | Text, reactions, edit / delete for everyone / reply, both ways | PASS (R1 and full rerun) |
| S04 | Voice note both ways | PASS |
| S06 | Offline delivery both ways, receiver force-stopped | PASS, no duplicates |
| S07 | Cold restart both apps, history kept | PASS |
| T09 | Arabic, emoji with skin tone, URL, 266 characters | PASS (1,200 characters not sent: Maestro too slow) |
| T10 | Both phones send 8 messages at once | PASS |
| T11 | Send 3 messages with no network | PASS delivery; shows "failed" + Retry meanwhile (R2-5, open, user skipped it) |
| T12 | Delete, react, edit while the receiver's app is stopped | PASS |
| T13 | Delete for me, copy | PASS |
| T14 | Archive, message while archived, unarchive | PASS (stale preview R2-9 fixed as O2, iPhone PASS 10-01) |
| T15 | Block: messages and calls dropped, unblock | PASS |

### Media
| ID | Scenario | Result |
|---|---|---|
| T01 | Photo Pixel → iPhone, view, save, info | PASS |
| T02 | 2 photos + 7 s video in one message, Shared media | PASS (transcode hang R2-4 fixed: 15 fps cap, 5/5 emulator clips) |
| T03 | View-once photo | PASS |
| T04 | Protected photo, no save, screenshots blocked | PASS |
| T05 | Photo through the iPhone Photos picker | PASS |
| O3 | Leave the chat while a voice note starts playing, 10 cycles | PASS (iPhone, 10-01) |
| O9 | Voice note length, iPhone → iPhone | PASS. Android-recorded notes not re-tested |
| O9b | Voice notes recorded on the Pixel 6 (13, 33, 63 s), played on the iPhone 13 | PASS (10-08): same length on both phones, the 1:03 note plays to the end. With the UI-Update build on the iPhone 13 (calls and logs off), 2 of 2 Pixel notes showed "Media unavailable" there; not seen with the main build |
| R2-11 | Profile picture download per incoming message (contact without a picture) | PASS (10-08, Pixel 6): 1 attempt in total, none for the following messages |

### Calls
| ID | Scenario | Result |
|---|---|---|
| S05a–e | Answer, decline, call again after decline, cancel while ringing, ring out | PASS |
| S09 | Back ×3 during a call (Android) | PASS |
| S10 | Network off 50 s during a call | PASS |
| S11 | iPhone CallKit ends an unanswered call | PASS |
| S12 | Swipe the app from Recents during a call | PASS |
| T24 | Mute / speaker | PASS |
| T25 | Pixel goes Home during a call | PASS |
| T26 | Both call each other at once | PASS |
| T27 | 4 quick call/cancel, then a call | PASS |
| T28 | Call arrives while recording a voice note | FAIL in R2 (R2-3); fix implemented and verified 09-28 |
| T29 | Wi-Fi off 40 s during a call, mobile data on | PASS |
| T30 | Call to the Pixel with the app in the background | PASS; caller name on the ringing notification fixed (R2-6) |
| T31 | Call to the iPhone with the app in the background | FAIL on the CallKit-off simulator build (R2-8 iPhone). With CallKit on (real iPhones, 10-01): PASS 14/14, banner in 3.3–4.0 s (background, after restart, killed) |
| T32 | Long call (4 min 15 s) | PASS |
| R2-8 F1/B1/B2/K1/P1/M1 | Pixel open / background / killed; push wakes; Pixel calls iPhone; killed-app text push | PASS (`run-20260929-085026`) |
| D1/D2 | Decline from the notification, app background / killed | PASS |
| L1 | Locked phone, app in the background | PASS (full-screen call screen) |
| L2/L3 | Locked phone, app killed | FAIL on 09-29; R2-9 fix: W1 PASS with a quiet Mac, W3 fixed 09-30 |
| R2-10 V1–V4 | Decline on a killed app reaches the caller | PASS (09-30) |
| O13a | Call from a blocked contact | PASS (logged `sender_blocked`) |

### Groups
| ID | Scenario | Result |
|---|---|---|
| S08 / T16 | Create, invite, accept, message both ways | PASS |
| T18 | Group photo + voice note, forward to 1:1 | PASS |
| T19 | Make admin, member renames, remove admin | PASS |
| T20 | Group messages while the member's app is stopped | PASS |
| T21 | Remove a member | FAIL in R2 (R2-1); fixed and device-validated 09-28 |
| T23 | Admin dissolves a group | FAIL in R2 (R2-1); fixed and device-validated 09-28 |
| O10 | Message sent before the invite is accepted | PASS (Pixel admin, iPhone 13 new invitee, 10-04, after the GE-009 fix): delivered once after accept, from the relay inbox; a second copy was dropped as a duplicate. Before accept the iPhone showed the invite card and a passive "Mknoon / Open the app to view updates." card with no text and no sound; the group did not exist in the app. "You joined" shown. The 10-01 result "not delivered" is replaced. Logs `docker-ws/deploy-captures/o10-20261004`, screenshots `artifacts/beta-20260928/r2o-shots/o10_*` |
| O12 b, c, e, f, i | Remove-member label, Add Member button, link node, no "Invite unknown" for non-admins, Edit Group sheet above the keyboard | PASS (iPhone, 10-01) |

### Notifications, layout, language
| ID | Scenario | Result |
|---|---|---|
| T33 | Message to a killed Pixel app, open from the notification | PASS |
| — | Tap an in-app message notification on the iPhone | PASS (opens the chat, 10-01) |
| T34 | Landscape | Pixel 6 PASS (10-08, R2-7 fix): with the keyboard open the composer and the last sent message stay visible (checked in the UI tree; screenshots are blocked in a chat with a protected photo); iPhone stays portrait |
| O7 | Pixel app 5 min in the background, then reopened | PASS (10-08): no relay redial loop, 0 "no good addresses" (old: 26 and 14 failed dials); remaining failed dials are group peer dials to offline phones. Reopened: "online … directly reachable" in 2.9 s |
| O8 | Pixel app open, call: first ringing notification | PASS 3/3 (10-08): titled with the caller's name from the start. A "MKnoon call / Checking an incoming call…" placeholder shows for 0.3–0.5 s before it |
| K1, D2 | Pixel 6 app killed, screen on: Answer / Decline from the notification | PASS (10-08): rang +5 s, connected; Decline reached the caller ("Call declined.") in about 5 s |
| O5 | Pixel 6 app killed, screen off, no lock screen | Screen turns on: PASS 3/3 (+6 s) |
| O6 | Pixel 6 app killed (cold start), screen off, no lock screen: first screen after wake | FAIL 3/3 before the fix (splash, then the chat list for about 9 s). FIXED 10-08: the native call screen now also shows without a lock screen until Flutter takes the call, and a call launch draws a first frame before startup, so the call screen is drawn 1.3 s after the call opens the app (was 4.8 s, 3/3). Answer on it connected 3/3 (3.5 to 5.3 s). 10-09: the app's own call screen now takes over 9.2/8.8/9.6 s after the call opens the app (was 10.4 to 10.8 s): the FCM call-token publication (about 2 s) no longer runs before the mailbox drain that delivers the invite. Locked phone, cold start: native call screen over the lock screen 2.2 to 2.4 s after open, Answer connected 2/2 |
| O4 | Full-screen access denied, app killed, swipe lock screen | Android cannot turn the screen on without this access (1 run rang 29 s with a dark screen). After the power key the call is a collapsed lock-screen notification; expanding it shows Answer, which connected. FIXED 10-08 as decided by the user: after such a call the app shows a card "Show calls on your lock screen" with Open settings (opens Android's Full-screen notifications page) and Not now (hidden for 7 days). Device check: no card before any affected call; card after one; gone after access is granted; Not now hides it across a reopen |
| O1 | iPhone with CallKit off, app in the background, Pixel calls | FAIL 3/3 before the fix (`signalingFailed`, "Call could not connect"). FIXED 10-08: ends as "No answer" after about 8 s, 3/3 on the USB iPhone 13 with a CallKit-off build |
| O11 | ANR in the headless call admission worker | Not seen: 0 ANRs in 17 call runs on the physical Pixel 6 (killed, locked, screen off). Treated as the emulator starvation seen in round 2 |
| O12 g, h | Arabic call texts and status pill (Android, per-app language) | PASS (10-08, Pixel 6): ringing, cancel, "call ended / no answer" and dismiss are Arabic; the status pill is Arabic and fits at font scale 2.0. New: Orbit's "Open chat with <name>" label (contacts with no unread messages) was hard-coded English; FIXED 10-08. 10-09, iPhone 13: the app could not be switched to Arabic on its own (no CFBundleLocalizations, so iOS offered no per-app language); FIXED. With Mknoon set to Arabic: status pill, Orbit labels and call texts (ringing, cancel, call ended / declined, dismiss) are Arabic. At iOS's largest accessibility text size the pill text and group initials were cut off; FIXED (pill text scale capped at 1.5x, initials sized by the avatar) |
| T35 | Arabic + large text | PASS on both |
| O12 a, d | "Photo" bubble label, media viewer Back label | PASS (iPhone, 10-01) |
| O13 c, d | No Firebase "not configured" log at launch; `readiness_proof` routed | PASS (iPhone, 10-01) |

## Not tested yet (candidates for the next round)

- T17 group reactions and replies; T22 member leaves; T21 re-add a removed member.
- R2-5 offline "failed" status (user chose to skip it for now).
- Fix C clock-lag call wake (callee clock behind the caller's); B7 late terminate.
- Anything on the 1.0.1 (121–123) store builds.
- Cold-start time to the app's own call screen is still about 9 s (general app startup); the native call screen covers it and Answer works on it.
- "Media unavailable" for Pixel voice notes (10-08) was seen only with the UI-Update branch build on the iPhone (calls and logs off). Not reproducible with main; plan 406's mixed-version harness passes NEW->OLD media, and main changed no message format since the UI-Update fork point.
- Calls between phones on different networks (one on cellular), which need the TURN relay. Every call so far had
  both phones on the same network, so the relay path was never used. coturn advertised the dead 13.60.250.19 until
  it was fixed on 2026-10-02.
- Video longer than the emulator fixtures, on real phones (R2-4 follow-up).
