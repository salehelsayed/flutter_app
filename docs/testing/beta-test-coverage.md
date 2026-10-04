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
| T34 | Landscape | Pixel FAIL in R2 (R2-7, source fix 09-28, not re-tested on a device); iPhone stays portrait |
| T35 | Arabic + large text | PASS on both |
| O12 a, d | "Photo" bubble label, media viewer Back label | PASS (iPhone, 10-01) |
| O13 c, d | No Firebase "not configured" log at launch; `readiness_proof` routed | PASS (iPhone, 10-01) |

## Not tested yet (candidates for the next round)

- T17 group reactions and replies; T22 member leaves; T21 re-add a removed member.
- T34 landscape on Android after the R2-7 fix.
- O12 g, h: Arabic call-end texts and the Arabic status pill (needs the phone's language changed).
- O9 voice notes recorded on Android, played on iPhone.
- R2-5 offline "failed" status (user chose to skip it for now).
- The CallKit-off iPhone build in the background (O1 fix target).
- Fix C clock-lag call wake (callee clock behind the caller's); B7 late terminate.
- Android physical phones; anything on the 1.0.1 (121) store build.
- Video longer than the emulator fixtures, on real phones (R2-4 follow-up).
