# Lever 3 Run A: call rows on Android (2026-10-22)

Candidate: main fd74fe3c6 plus test-only 4b0e0a17d (bounded plan 399 fixture timeout, manual hold).
Devices: physical Pixel 6 plus one headless emulator (the plan 399 fixture needs two Androids, only one physical Android exists).
Network: plan 399 forced-relay local fixture (local libp2p relay plus local coturn). No push wake in this build.

## Automated campaign (Sims, run under the native lease)

| Case | Result | Rows |
|---|---|---|
| android.production_1to1_audio_call (27 assertions) | PASS | VC-027 normal hangup |
| kx0002, kx0003 | PASS | ongoing card, minimize and return |
| kx0005 | PASS | CALL-001 missed-call callback entry |
| kx0007 | PASS | CALL-004 busy callback while a call survives |
| kx0015, kx0016, kx0017 | PASS | VC-004 names on Android, no raw IDs |
| kx0008 | FAIL | VC-020: "Microphone permission is needed to make calls." not shown after Deny. Known app bug, fix f7e4bd558 is only on UI-Update. |
| kx0006 | FAIL | 60 s timeout on a callback snapshot (keyguard row VC-025, belongs to Run B) |

## Hand-driven legs (fixture held, no native lease)

Observer per device: live telecom calls of the package, package notifications, RECORD_AUDIO appop running state, audio mode.

Observer obs.py: telecom live calls for the package, package notification ids, open mic recordings (RecordActivityMonitor start without stop), audio mode.
- L1 unanswered (15:56:55): px called from chat header, em rang (telecom RINGING, card 504), nobody answered. ~35 s later both clean: no telecom call, no card, 0 mic, audio mode 0. History: px "No answer", em "Missed voice call", one row each. PASS.
- L8 CALL-001 history row (15:58:04): px Calls page row "Call back" started one call to the exact contact, em rang and answered, both Connected. PASS.
- L4a normal caller hangup (15:59:53): during active call px 1 mic, em telecom ACTIVE plus 1 mic, card 505 on both, audio mode 3. px End: within 6 s both no call, no card, 0 mic, mode 0. PASS.
- L4b callee (remote) hangup (16:00:26): connected, em End: within 6 s both no call, no card, 0 mic, mode 0. History one row each ("Voice call 0:00" on px, "0:01" on em, although the call was connected for about 6 s by wall clock; minor duration observation, not judged). PASS for cleanup.
- L2 decline (16:00:46): em telecom RINGING plus card, em Decline: within 10 s both clean. History px "Call declined", em "You declined", one row each. PASS.
- L3 CALL-002 cancel before answer plus late answer (16:01:05): em ringing (telecom RINGING, card), px "Cancel call", then an Answer tap on em at the Answer position right after. em showed "Call ended", no connection, both clean within 3 s (no call, no card, 0 mic, mode 0). History px "Cancelled", em "Missed voice call". PASS.
- L5 VC-016 glare (16:01:30): both tapped Call back at the same moment. Exactly one call survived (px caller, em ringing), one telecom call on em. Answered, connected, ended, both clean. History: one voice-call row each, plus em's own superseded outgoing shown as "Cancelled". No phantom ring. PASS.
- L6 CALL-003 callee offline (16:02:10): em airplane mode on. px showed "Connecting" (never Connected, never Ringing), ended "No answer" at about 30 s, px clean (no call, card, mic). em back online at 16:03:21: no late ring over 30 s (the expired invite did not revive). PASS for the offline part.
- L6b CALL-003 retry after restore: FAIL twice. px calls at 16:04:12 and 16:05:31 (1 and 2 min after em was back, em showed "online, relay reservation ready"): em never rang, px ended "No answer". px log: invite direct_send false, mailbox_store true (wake none). em log: no inbox delivery and no call events in that window. A text px->em at 16:07:04 also went "Sent to inbox" but em received it within seconds (INBOX_DELIVERY, CHAT_MSG_RECEIVE_STORED). After em called px once (16:07:45, worked), px->em calls worked again (16:08:30). FINDING (possible app/relay gap, not judged): after the callee's network change the caller's direct path stays stale, and call invites stored in the relay mailbox are not delivered live to an online callee (messages are), so calls fail until the callee contacts the caller. Note: this build has no push wake (fixture relay push provider off), so with FCM the mailbox invite might wake the callee. Logs: private/px_retry2.txt, em_retry2.txt, em_text.txt.
- Reverse direction em->px after restore (16:07:45): worked, em telecom DIALING then ACTIVE, both clean after end.
- L7a VC-026 callee process loss while ringing (16:12:35, em->px): px app force-stopped at 16:12:37 while ringing. px clean at once (no process, no card). em kept "Ringing" (telecom DIALING) until the original 30 s no-answer bound, ended "No answer" at about 16:13:10, clean. px restart: no phantom ring, fresh em->px call connected at 16:13:54. PASS. (A first attempt px->em at 16:10:21 never rang, see the mailbox finding.)
- L7b VC-026 callee process loss during an active call (16:14:11): px force-stopped. em showed "Reconnecting", then ended at about 16:14:33 (about 22 s), telecom call, card and mic released. px restart: no phantom ring. PASS.
- L7c VC-026 caller process loss during an active call (16:15:59, em caller): em force-stopped. px showed "Reconnecting", then "Call ended / Call could not reconnect." at about 16:16:23, card gone, audio mode 0, mic appop access closed (duration 27.5 s). em restart: no phantom ring. PASS. Note: force-stop is an OS process stop, not a native crash; a hard kill -9 needs root.
- Observer fix: the RecordActivityMonitor log keeps a "rec start" without "rec stop" when the process is killed, so it over-counts. Switched to the RECORD_AUDIO appop running state, validated during an active call (running on both) and idle after.
- L10 VC-020 notification-permission fallback: revoking POST_NOTIFICATIONS kills the app process (Android behaviour), and a backgrounded or killed callee cannot receive a call in this build (no push wake, and Android cuts background networking). In the foreground with notifications denied: attempt 1 (16:20:05) the invite arrived directly but px call control was still starting after the restart ("advertisement_unavailable" for about 42 s, CALL_CONTROL_UNAVAILABLE), the later mailbox copy was superseded, no ring; attempt 2 (16:21:06) direct_send false, mailbox only, no ring. INCOMPLETE (could not separate the permission effect from the delivery finding). Permission restored after.
- Measurement 1 (16:22-16:25, both apps foreground in the chat, 5 s gaps): 8 of 8 attempts rang and connected, alternating directions.
- Measurement 2 (16:28-16:37, both in the chat, 150 s idle gaps, alternating): 4 of 4 rang, direct_send true.
- Measurement 3 (em airplane on 20 s, restored 16:40:29, px->em from 16:40:59 every ~50 s): 5 of 5 rang, direct_send true.
- Measurement 4 (em on Orbit, not in the chat, 60 s idle, px->em, 16:46-16:49): 3 of 3 rang, direct_send true (relay mailbox_store returned false on attempts 2 and 3, the call still rang over the direct leg).
- Mailbox finding tally: 4 of 36 attempts with an online, foreground callee never rang (16:04:12, 16:05:31, 16:10:21, 16:21:06). In all 4 the caller log shows direct_send false and mailbox_store true (wake none), and the callee log shows no call event and no inbox delivery. In the 2 attempts after the callee network change (1 and 2 min after restore) a text sent right after was delivered live (em INBOX_DELIVERY plus CHAT_MSG_RECEIVE_STORED within seconds at 16:07). 0 of 20 controlled retries reproduced it, so it is intermittent. Excluded: 16:18:04 and 16:19:06 (callee process killed by the permission revoke, then backgrounded) and 16:20:05 (callee call control still starting after a restart).

## Row summary (Android only, Run A)

- VC-004: PASS (kx0015/16/17). The iOS CallKit name surface is Run B.
- VC-016: PASS (decline, cancel before answer, unanswered, glare, late answer refused, next call starts).
- VC-020: FAIL (kx0008 known app bug, fix not on main). Notification-permission fallback INCOMPLETE.
- VC-022: INCOMPLETE. Forged, replayed or out-of-authority call signals cannot be injected on a real device without a test-build hook (app code), so not run.
- VC-026: PASS for an OS process stop while ringing and while active, callee and caller (peer settles by its deadline, restart has no phantom ring, fresh call works). A hard native kill needs root. iOS is Run B.
- VC-027: PASS for caller hangup, callee hangup, decline, cancel, no-answer timeout, offline callee, process loss (telecom call, notification and mic go to zero once, one history row). Busy via kx0007. Media failure not exercised.
- CALL-001: PASS (chat header, call-history row, missed-call notification via kx0005).
- CALL-002: PASS.
- CALL-003: PARTIAL. Offline callee: no false Connected, ends by the bound, no late ring. Retry after restore failed 2 of 2 at 1 and 2 min (see the mailbox finding), later retries worked.
- CALL-004: PARTIAL. Busy callback PASS (kx0007). A third-party incoming call during a call needs a third device. The protected-media-viewer leg was not run.

## Finding: call invite misses an online callee (intermittent)

4 of 36 attempts with an online, foreground callee never rang. Caller log each time: direct_send false, mailbox_store true, wake none. Callee log: no call event, no inbox delivery. A text sent right after one of them reached the callee within seconds. The other 20 controlled retries (chat, Orbit, after a network change, 150 s idle) all rang. Without push wake, a call invite left only in the relay mailbox is not delivered live to an online callee, while messages are. Possible app or relay gap, not judged.

## Run B (release profile, 2026-10-22)

Build 251b93a67 with the voice-call release defines (force-relay off, always-relay toggle, production TURN) on both phones. Android peer: a headless emulator. iOS: the iPhone 13 (install over, identity kept).

- VC-023: PASS for "the real toggle governs the route" (both off: direct, one side on: relay on that side, media verified both ways). INCOMPLETE: relay loss without direct fallback, and restore (the production TURN cannot be cut, no root for a firewall).
- VC-028: PASS for direct, TURN UDP and TURN TCP profiles, media both ways, clean end. A forced TCP-only fallback was not controllable.
- VC-025 Android: PASS with a temporary credential-free swipe lock (only call controls while locked, Back returns to the lock screen, app content only after unlock). iOS: INCOMPLETE (the automation could not lock the iPhone, no passcode was set or changed).
- VC-004 and VC-010 iOS: PASS. The CallKit banner shows the app label and the contact name, never a raw identity. The revoked or unknown contact leg was not run (it would need deleting a contact on a protected phone).
- VC-020 iOS: PASS (microphone off shows "Microphone permission is needed to make calls." and the peer never rings).
- VC-026 iOS: FAIL, app bug, 2 of 2. After the iPhone app is killed while ringing or during a call, the next incoming call fails (native_lifecycle_failed) and the app switches calling off ("Voice calling is unavailable right now", no recovery in 5 min). A reinstall over it restores calling.
- kx0006 retry: not run.

## Idle-poll fix check (456674551)

The Run A "never rang" condition (invite stored only in the relay mailbox, no wake) rang 11 of 11 times with the fix, in 2.6-6.3 s (median 4.8 s), across callee restarts, callee network changes and resumes. The callee polls every 4 s while in the foreground and idle, and makes zero polls in the background. Cancelled and expired invites did not ring.

## Lever 4 (known-content audio): needs the test-build audio hook

Owner decision 2026-10-22: option (a). VC-009, VC-011, VC-014, VC-015, VC-017, VC-018, VC-019 and CALL-007 are recorded as "needs the test-build audio hook (not approved)". The no-hook energy option is not feasible for the production flow: the call stats sampler (lib/features/call/infrastructure/call_stats_sampler.dart) keeps only packet and byte counters and route fields, so no inbound audio level is readable without app code, and Android has no app-free way to read a playback signal level. Emulator peers must start with audio input off, since an AVD with hw.audioInput=yes captures the host microphone.
