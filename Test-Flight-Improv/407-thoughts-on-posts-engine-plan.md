# 407 — Thoughts on the Posts engine

Status: Step 1 implemented; validation in progress. Steps 2–4 not started.
Branch: UI-Update
Date: 2026-10-20 (line numbers checked after rebasing UI-Update on main 999a297ef). Scope cut to a first version the same day (owner decision).

## Goal

First version of "thoughts": a user writes a thought, all their friends see it on the orbit the app has today, and it is deleted after 24 hours. Nothing else is in this version. The orbit's design stays as it is today (owner decision 2026-10-20): thoughts are added to the current orbit, not to a redesigned one.

It reuses the hidden Posts feature (`lib/features/posts/`) instead of writing a new sharing system. Posts already sends a post to chosen friends, encrypted, with an inbox fallback, encrypted media and retries, and all of that runs today at app launch even though no screen shows posts. This plan keeps that engine, changes its rules (C1–C15), turns off what thoughts does not have, and adds only what this first version needs.

## What the first version does

- **Share.** A "+" on your own node in the middle of the orbit opens a composer. You write a thought, optionally with a photo, video or voice note, and share it. It goes to **all your friends**. There is no audience choice.
- **See.** On a friend's phone, a note bubble with your thought sits over your face on today's 2D orbit, like an Instagram note. The faces drift aside so no note covers anyone. Tapping the note opens a full-screen thought card; tapping the face opens your chat. A pinch puts the notes away and the orbit settles back to normal; a spread brings them back.
- **Gone after 24 hours.** 24 hours after you wrote it, the thought is deleted from every phone, yours included, with its media. It disappears from the screen at that moment, even if the app stays open.
- **Offline friends.** A friend whose phone is off gets it from the relay inbox when they come back, if the 24 hours aren't over. A copy that arrives later is thrown away.

Not in this version (see "Later"): choosing Close or picked people, reactions, replies that quote the thought, keeping your own thoughts longer, counts, any page showing a person's older thoughts, tags and Spaces.

## Background

### What Posts is today

- Hidden since commit `e8cba5e32` (2026-03-20), which removed `AppShellTab.posts`, the `PostsWired` screen and the `nav_posts` button. There is no feature flag.
- The listeners and the three retriers still start at launch (`production_application_bootstrap.dart`: `PostListener` and the other post listeners from line 6820, the three `PendingPost*Retrier`s at 9323-9343). Expired posts are cleaned up at startup and on resume.
- About 450 tests under `test/features/posts/` plus one test per posts migration (027–040).

### What the prototype shows (`prototypes/orbit_depth/`)

- A thought is text plus optional photo, video or voice (`you.dart:21-22`, `carousel.dart:3-11`).
- One live thought per friend (`spaces.dart:420-421`). Unseen thoughts sort first (`orbit_depth_prototype_screen.dart:277-286`).
- The old-orbit variant of the prototype (`OrbitDepthTuning.oldFlat`, `_OldFlatOrbit`, `_NoteBubble`; on the iPhone 11 since 2026-10-20) shows the note bubbles, the swim and the pinch described in N4.
- The prototype also has audiences, reactions, quoted replies, 30-day history and Spaces. None of those are in this first version.

## Mapping

### Keep as is

| Thoughts needs | Posts code |
|---|---|
| Per-recipient encrypted delivery with inbox fallback | `post_delivery_runner.dart` (direct send, then `storeInInbox`) |
| Encrypted photo, video, voice | `attach_post_media_use_case.dart`, `download_post_media_use_case.dart` |
| Retries | `pending_post_delivery_retrier.dart`, `pending_post_media_upload_retrier.dart` |
| Send to every friend | `PostAudience.allFriends()`: every active, unblocked contact (`send_post_use_case.dart:388-394`) |
| Seen / unseen | `post_feed_state.is_read`, `dbMarkPostFocused` (`post_feed_state_db_helpers.dart:3`) |
| Deletion when expired | `sweepExpiredPosts` (`sweep_expired_posts_use_case.dart`), `dbDeletePostCascade` |
| Receiving | `post_listener.dart`, `handle_incoming_post_use_case.dart` |

### Change

#### Sending side

| # | Rule | Today | Thoughts | Where |
|---|---|---|---|---|
| C1 | Lifetime | `_postExpiry = Duration(days: 3)` | `expires_at` = created + 24 h, on the author's phone too | `send_post_use_case.dart:27, 229` |
| C2 | Comment extends expiry | Each comment sets expiry to comment + 3 days | Remove. Comments are off | `refresh_post_expiry_for_comment_use_case.dart`, called from `send_post_comment_use_case.dart:141`, `handle_incoming_post_comment_use_case.dart:98` |
| C5 | Pass along | Blocked only for pick-people posts | Blocked for every thought | `pass_post_along_use_case.dart:150-153` |
| C6 | Audience | All friends / People nearby / Pick | Always `allFriends`. The composer offers no choice | `post_audience.dart`, composer |
| C7 | Notification tap | Opens the chats list (`// Posts tab hidden for TestFlight`) | Opens the orbit focused on that friend's thought | `post_notification_open_coordinator.dart:125-127` |
| C8 | Recipient list inside each copy | Every copy carries `recipient_peer_ids`, the full list of everyone it was sent to | Don't send it. With all friends as the audience, it would show every friend your whole friends list | `PostCreateEnvelope.toInnerJson` (`post_create_envelope.dart:335-361`), `post_delivery_runner.dart:552-580` |
| C9 | Missing key or failed encryption | A text-only post goes out unencrypted when the friend has no ML-KEM key or encryption fails | Never send a thought in plaintext. Record that friend's delivery as `failed` with a specific reason (`recipient_missing_mlkem_key` or `thought_encrypt_failed:<code>`). The thought's overall status becomes `partial` when other friends got it. See "Retries" below | `_buildWireEnvelope` (`post_delivery_runner.dart:527-585`), `aggregatePostDeliveryStatusFromDeliveries` |
| C10 | Inbox first for friends not connected | For every friend not already connected, the runner looks them up and dials for up to 4 s (`_interactivePostBudget`), then sends with another 4 s limit, and only then falls back to `storeInInbox`. With many offline friends this wait sets how long the whole send takes (25 friends at a time) | If `p2pService.isConnectedToPeer(friend)` is false, call `storeInInbox` straight away, with no lookup or dial. Friends already connected still get the direct send. Change only the thought send path; leave `post_follow_on_delivery.dart` (the other caller of the connect helper) as it is | `_deliverToRecipient` (`post_delivery_runner.dart:654-708`), `ensurePostRecipientDirectConnection` (`post_follow_on_delivery.dart:180`) |

**Retries.** The delivery retrier picks up every outgoing post whose status is `sending`, `partial` or `failed`, every 5 min (`dbLoadRetryableOutgoingPosts`, `posts_db_helpers.dart:374-375`). Rules:
- Each retry reloads the friend's contact and uses the ML-KEM key it has now, never the one seen on the first attempt.
- Retry eligibility is separate from the status shown. Changing the status alone would not stop the retrier, so add a predicate instead of a new status: select only thoughts created less than 24 h ago. After 24 h every copy is deleted (C1, C12), so a later delivery is useless for every failure reason.
- Within an eligible thought, retry only its unsettled recipient deliveries, as today. Delivered and inbox deliveries are never retried.
- After 24 h the thought keeps its last status (`partial` or `failed`) until it is deleted, and the retrier no longer selects it.
- The same cutoff applies to media-upload recovery, which has its own query (`loadPendingMediaUploadPosts`) and calls `PostDeliveryRunner` directly after uploading (`pending_post_media_upload_retrier.dart:175` onward). Its query also selects only thoughts created less than 24 h ago. Both retriers check the cutoff again right before `PostDeliveryRunner.execute`, because an upload can finish after the deadline. An expired recovery job makes no upload and no delivery attempt, and its recovery rows are removed so it is never selected again.

#### Receiving side

| # | Rule | Today | Thoughts | Where |
|---|---|---|---|---|
| C11 | Recipient lists in incoming copies | The receiver reads `recipient_peer_ids` and `selected_peer_ids` and stores a recipient row per peer (`handle_incoming_post_use_case.dart:232-235`) | Ignore both fields and store nothing from them, so copies from older app versions can't keep supplying the list. Rows already stored go with the migration in C14 | `post_create_envelope.dart:157-161`, `handle_incoming_post_use_case.dart:103, 153, 232-235` |
| C12 | Expiry on receive | The receiver keeps the sender's `expiresAt` as is (`handle_incoming_post_use_case.dart:209`), and the expiry query skips posts with `keep_available = 1` (`posts_db_helpers.dart:414-415`) | Both dates come from the sender, so check them. If the creation time is later than now, use now. Then store `expires_at` = creation + 24 h, ignoring the sender's expiry, and always store `keep_available = 0`. The expiry query deletes every thought whose time is up, whatever `keep_available` says. A copy that arrives after its 24 h are over is not stored at all. Example: a thought written 20 October 09:00 that says "delete in 2099" is stored to be deleted 21 October 09:00 | `handle_incoming_post_use_case.dart:209`, the expiry query (`posts_db_helpers.dart:414-415`) |
| C13 | Incoming messages thoughts don't have | Incoming `post_comment`, `post_reaction`, `post_comment_reaction`, `post_pass`, `post_presence_update`, `post_pin_update` and `post_pin_remove` are stored. The pin handler overwrites `expiresAt` and `keepAvailable` from the sender's snapshot (`handle_incoming_post_pins_use_case.dart:99-107`), so a pin could keep a copy forever | Reject all seven before storage, in the router or at the top of each handler, and log the drop | `incoming_message_router.dart:86-110, 225`, the matching `handle_incoming_post_*_use_case.dart` handlers and `handle_incoming_passed_post_use_case.dart` |
| C15 | Expiry while the app stays open | Cleanup (`sweepExpiredPosts`) runs only at startup (`production_application_bootstrap.dart:10570`), on resume (`application_root.dart:2920`) and from the hidden `PostsWired` screen. A phone left open across the deadline keeps the thought and its media | (a) Every read of thoughts filters out those whose `expires_at` has passed: the orbit query (N2) and the notification tap (C7). An expired thought disappears from the screen at once, even before it is deleted. (b) While the app is in the foreground, a timer runs the sweep at the earliest upcoming `expires_at`. It is re-armed after every sent or received thought, every sweep and every resume. (c) At expiry, cancel the thought's system notification, so its text doesn't stay in the notification tray. (d) While the app is suspended, nothing can run. Deletion then happens at the next chance (resume or startup), and (a) keeps it hidden until then | A small expiry scheduler owned by the app root, beside the existing resume sweep; the read helpers in `posts_db_helpers.dart`; the notification service |

#### Existing data

| # | Rule | Today | Thoughts | Where |
|---|---|---|---|---|
| C14 | Posts from before thoughts | TestFlight phones may still hold posts, comments, reactions, passes, pins, follow-on outbox jobs and media files from before the tab was hidden (2026-03-20). `dbDeletePostCascade` deletes database rows only, and it does not touch the two follow-on outbox tables (`post_follow_on_outbox_events`, `post_follow_on_outbox_recipient_deliveries`, migration 033). Those have no foreign-key cascade, keep raw envelopes, and are picked up by the follow-on retrier | Delete all of it when thoughts ships (owner decision 2026-10-20). (a) **Rows:** one migration deletes every row from every posts table, including both follow-on outbox tables, in one transaction. A transaction either completes or leaves everything as it was, so an interrupted upgrade simply runs the migration again. Confirm in step 1 that migrations finish when the database opens, before `PendingPostFollowOnRetrier` and the other post retriers start; if not, run the migration's check before they start. (b) **Files:** media lives in `<documents>/post_media/<postId>/` (`media_file_manager.dart:602-604`). At every startup, before the post retriers start, delete each `post_media/<id>` folder that has no matching `posts` row. This sweep is idempotent, so a cleanup interrupted by a crash or kill finishes on the next start, and it also removes any later orphans | New migration after the latest one; an orphan-folder sweep beside the startup `sweepExpiredPosts` call |

C8 and C11 are the privacy changes: today every copy lists everyone it was sent to, which with all friends as the audience would give each friend your whole friends list. C9 keeps the relay from ever seeing a thought's text. C12 and C13 keep a sender from making a thought live past 24 h on a friend's phone.

### Turn off (leave the code, make it unreachable, delete after thoughts ships)

- Comments, the comment sheet, reactions and comment reactions
- Nearby posts, location presence publishing and the nearby settings
- Pass-along, repost and pins
- `PostsScreen`, `PostsWired`, `PostCard` and its counts

Incoming messages for all of these are rejected by C13.

### New

| # | Piece | Notes |
|---|---|---|
| N2 | Live-thought query | On top of `dbLoadPostsFeed` (`posts_db_helpers.dart:262`): each friend's newest thought that has not expired, unseen first |
| N4 | Thoughts on today's orbit | On the app's current 2D orbit (`InnerCircleInteractiveSurface` / `OrbitalVisualization` / `OrbitalAvatar` in `lib/features/orbit/presentation/widgets/`). See "Thoughts on the orbit" below |
| N5 | Composer | Opened from a "+" on your own node in the middle of the orbit. Text plus optional photo, video or voice, wired to `SendPostUseCase` with `allFriends`. A note under it says "Your friends see this for 24 hours" |
| N7 | Larger default orbit | `OrbitGeometryPrefs.defaults` changes from 1.0 to the largest values the long-press controls allow: `avatarScale` 1.4 (`maxAvatarScale`) and `spacingScale` 1.5 (`maxSpacingScale`), so the notes have room. Reset in the long-press controls goes to these. Users who already saved their own sizes keep them. Applies to everyone's orbit |

### Thoughts on the orbit (N4)

Shown in the prototype's old-orbit variant on the iPhone 11 (2026-10-20).

- **Note bubbles, on by default.** Every friend on the two rings (the 13 seats) who has a live thought gets a note over their face. Friends on the "+N" arcs get none.
- **The note's look,** like an Instagram note: a dark-grey (`#262626`) rounded bubble (radius 14) with a soft shadow, as wide as its text needs between 40 and 96 px, padding 9 × 6. White (`#F5F5F5`) text at 11.5 pt, line height 1.22, centred, two lines at most, then "…". A thought tail of two dots under the bubble points at the face, and the bubble sits on the top of the face.
- **Unseen thoughts** read in a heavier weight (w600 instead of w400). That is the only unseen signal: the face's unread ring keeps meaning unread messages, and there is no separate green dot (owner decision 2026-10-20).
- **The faces swim.** A spring pulls each face to its seat, with a slow drift of its own, while faces, notes and your photo in the middle push each other apart, so no note covers a face or you. The orbit opens about 10% wider while the notes are out. Under Reduce Motion the faces take their resolved places without drifting.
- **Pinch and spread.** A two-finger pinch puts the notes away over about 0.7 s: the notes fade, the faces glide back to their seats and the orbit returns to its normal size. A spread brings them back. The choice lasts for the session.
- **Taps.** The note opens the full-screen thought card (name, how long ago, text and media, and "Message" for the 1:1 chat; nothing from the thought goes into the chat). The face opens the chat, as today. Opening the card marks the thought seen.
- **While the notes are out,** tapping "+N" first puts the notes away (tap again for the arcs), and the long-press size controls open only with the notes away.
- **Where it lives in the code.** Today's `OrbitalVisualization` places every face on its seat and cannot move one. It needs a per-seat offset (driven by the swim) and a note layer above the faces, owned by `InnerCircleInteractiveSurface` with the pinch. The prototype drew its own copy of the orbit for this; the app changes its own widget instead.

## Steps

Each step ends in a state that can be tested on its own. Every step is accepted through the validation procedure below, not only the tests listed under it.

### Step 1 — Engine rules, no UI

C1, C2, C5, C8–C15, plus stopping nearby location presence publishing at launch and resume (`nearbyLocationService` in `production_application_bootstrap.dart:6184-6196`, and `handle_app_resumed.dart`).

Tests:
- A sent thought has `expires_at` = created + 24 h, on the author's phone and on each friend's phone. Cleanup removes it, with its media, after 24 h, not after 3 days.
- Pass-along returns not-allowed for every thought.
- A decrypted copy received by one friend contains no other recipient's peer ID.
- An incoming copy that still carries `recipient_peer_ids` / `selected_peer_ids` (older app) stores no recipient rows from them.
- A friend without an ML-KEM key gets no copy, nothing is sent in plaintext, the delivery is `failed` with `recipient_missing_mlkem_key`, and the thought is `partial` when others got it.
- A retry after that friend's key arrives uses the new key and delivers.
- A `partial` or `failed` thought created more than 24 h ago is not returned by the retry query and gets no delivery attempt, while its status stays `partial` or `failed`. One created less than 24 h ago is still returned, and only its unsettled deliveries are attempted.
- An expired media-upload recovery job makes no upload and no delivery attempt and is not selected again. A media upload that finishes after the deadline does not lead to a delivery.
- An incoming thought saying "delete in 2099" is stored with `expires_at` = creation + 24 h. One with a creation time in the future is stored as created now. A copy that arrives more than 24 h after creation is not stored.
- A received thought whose envelope says `keep_available: true` is stored with `keep_available = 0` and deleted at 24 h.
- Incoming `post_comment`, `post_reaction`, `post_comment_reaction`, `post_pass`, `post_presence_update`, `post_pin_update` and `post_pin_remove` store nothing and change nothing. A pin update carrying a later expiry for a received thought is rejected, and the thought is still deleted at 24 h.
- Expiry while open: with a fake clock, receive a thought, keep the app in the foreground and move the clock past 24 h without a restart or resume. The thought and its media are deleted, the orbit query no longer returns it, and its notification is cancelled. Between the deadline and the sweep, the orbit query and the notification-tap lookup already treat it as gone.
- Upgrade test: start from a database holding old posts with media files, pending comments and pins in the follow-on outbox, and pending media-upload recovery rows. After the upgrade, no row in any posts table (both follow-on outbox tables included) and no `post_media/` folder remains, and the follow-on and media retriers send nothing. Repeat with the app killed after the migration but before the file sweep: the next start finishes the cleanup.
- A friend who is not connected gets the copy through `storeInInbox` with no `discoverPeer` or dial call, and the attempt ends as `inbox`. A friend who is connected still gets the direct send and ends as `delivered`.
- With 100 friends where 90 are not connected, the whole send finishes without any 4 s wait (fake P2P service that counts calls and records elapsed time).
- Update the existing `test/features/posts` tests that assert the old rules. Expect many in `phase2`–`phase4` and `improvement`. Change each to the new rule; don't delete them.

Done when: the validation procedure passes for this step and no test still asserts 3-day expiry, reaction or comment handling, plaintext fallback, recipient lists on the wire or stored pins.

Owner approved (2026-10-20) re-pinning the DTR-18 digest of `production_application_bootstrap.dart` for this step (see "Locked files").

Implementation (2026-10-20): the shared lifetime policy, receive/read/retry boundaries, migration 122, restart-safe orphan cleanup, disabled legacy handlers and nearby service, encrypted delivery without audience lists, and foreground expiry scheduler are implemented. The scheduler is composed in `production_application_bootstrap.dart` with its own lifecycle observer and existing teardown callbacks; `application_root.dart`, `handle_app_resumed.dart`, and the locked Posts repository adapter remain unchanged. Notification cancellation uses the exact post route, including deletions performed by the existing resume sweep. Failed cold cleanup releases its cached future so startup can retry.

Validation evidence is retained in ignored `.codex-test-logs/plan407-step1/`. Focused Posts and database checks passed after updating obsolete expectations; first-attempt failures remain preserved. The affected selection, required `core-host-all`, `feature-host-all`, and native Posts gate are still being completed. Step 1 is not accepted until those required checks pass. No full `host-all` or release certification is claimed.


### Step 2 — Thoughts on today's orbit

N2, N4, N7, C7. UI that appears: note bubbles over friends' faces on today's orbit, the faces drifting aside, the pinch, the larger default orbit and the full-screen thought card. Step 1 has no UI.

Tests:
- A friend on the two rings with a live thought has a note showing its start; a friend without one has none; friends on the arcs have none.
- With two thoughts from one friend, the note and the card show only the newest.
- A long thought shows two lines and "…"; a short one makes a narrower note (40 px at least, 96 px at most).
- After the swim settles, no note overlaps any face or your photo.
- An unseen thought's note uses the heavier weight; after opening the card it uses the normal weight. The face's unread ring does not change for a thought.
- Tapping a note opens the card; tapping the face opens the chat; tapping a face with no thought opens the chat, as today.
- The card shows the friend's name, how long ago, and the thought's text and media. "Message" opens the normal 1:1 chat with nothing from the thought in it.
- A pinch hides the notes and every face ends on its seat at the normal size; a spread brings the notes back.
- With the notes out, "+N" puts them away first; the long-press controls open only with them away.
- Reduce Motion: no drift; notes and faces appear and leave without animation.
- With no saved sizes, the orbit opens at avatar 1.4 and spacing 1.5; saved sizes are kept; Reset goes to 1.4 and 1.5. Update the existing orbit tests that pin today's 1.0 layout (`test/features/orbit/domain/orbit_arc_layout_test.dart`, the `orbital_*` widget tests); change each to the new default, don't delete it.
- 24 h after creation the thought is gone from the friend's phone: its note leaves while the app stays open, the card closes if it is open, its media is deleted.
- A thought notification opens that friend's card. Tapping one whose thought has since been deleted opens the orbit with no error.

Device check (two peers, not iOS-specific, so per `AGENTS.md` "Mobile device test availability"): resolve the live targets with `flutter devices --machine` and `adb devices`, then use one USB-connected physical Android device plus one available Android emulator, pinning both IDs. Drive setup and assertions through Appium MCP. Do not use an iPhone as the second endpoint. Share a thought on one (through a test hook until step 3 exists), see the note over that face on the other, open the card, then pinch the notes away and spread them back.

Device check for C10, same pair: with the receiver's app open but not connected to the sender, share a thought and time how long the receiver takes to show it. This answers whether a friend who is online but not connected picks up an inbox copy quickly enough. If it is slow, keep inbox first but also try a short direct dial (1 s) for friends seen online recently.

### Step 3 — Composer

N5, C6. UI that appears: the "+" on your node in the middle of the orbit, and the composer (text box, photo/video/voice button, Share, and "Your friends see this for 24 hours").

Tests:
- The "+" on your node opens the composer. Share is blocked while there is no text and no media.
- A shared thought goes to every active, unblocked friend and to nobody else.
- Photo, video and voice attach through the existing media path.
- The composer shows that friends see it for 24 hours.

Device check, same Android pair: write a thought with a photo on one phone and see it arrive on the other.

### Step 4 — Opening a chat from the orbit

Pending owner confirmation (2026-10-20): the orbit itself stays as it is, and this step only changes how a chat opens from it. The prototype's "Flatten" transition (`prototypes/orbit_depth/flatten.dart`, chosen by the owner on 2026-10-13 and confirmed on 2026-10-20). UI that appears:

- **Tapping a friend's face** on the orbit opens your 1:1 chat with them. Their face flies up to the top-left corner of the chat, and the other inner-ring faces fly in and line up next to it in a row.
- **The row:** the friend you tapped comes first, then the other inner-ring friends in their orbit order, as many as fit the screen width (`_openDmFromOrbit`). The open chat's face is larger and ringed. The order is fixed when the chat opens, so switching moves the highlight, never a face under your finger.
- **Tapping another face in the row** switches the chat to that friend, without leaving the screen.
- **Back** flies every face home to its seat on the orbit, which stays in place under the chat while it is open.
- **Reduce Motion:** the chat and its row appear at once, with no flight.

Real data: the faces are the friends on the inner ring of today's orbit (`mergeInnerCircleItems`; groups on the ring are left out of the row). The chat is the app's existing 1:1 chat screen. The row sits above it as its own layer, so the chat screen's construction sites stay untouched. Tapping the open chat's own face in the row does nothing in this version (the prototype opens that friend's world page, which is not in scope).

It does not depend on thoughts (steps 1–3), so it can be built in parallel with them or before them if wanted.

Tests (from `test/features/orbit/prototypes/orbit_depth_prototype_screen_test.dart`: "a face opens its chat under a row of Close; the row switches the chat and holds still; back sends the faces home" and "with Reduce Motion the chat and its row arrive at once", on real data):
- Tapping a friend's face opens their chat with the row above it, that friend first and highlighted.
- Tapping another face in the row switches the chat, and no face in the row moves.
- Back closes the chat, and every face is back at its seat on the orbit.
- With Reduce Motion the chat and the row appear without animation.
- A row with more inner-ring friends than fit the width shows only those that fit.

Device check: the Android pair, opening a chat from the orbit, switching once in the row, and going back.

## Validation procedure (every step)

Follow `AGENTS.md` ("Regression checks and testing memory", "TDD gate cadence"):

1. Before choosing tests, read the relevant entries in `docs/testing/TESTING.md` and consult `tool/testing/selection.json`.
2. Run `python3 scripts/mknoon_checks.py validate`.
3. Preview, then run, the change selection with an explicit verified `--base` (the commit the step starts from) and `--local` for working-tree changes.
4. Run the step's focused tests listed above and the affected curated lane gate.
5. Run `core-host-all` or `feature-host-all` only for production surfaces the step actually changed. Do not run full `host-all` per step; run it once after the last step and once at release.
6. Report every required check that was not run. A passing unrelated test or an inventory is not validation.
7. If a step renames or deletes tests or selectors (likely in step 1), update `tool/testing/selection.json` and keep the mandatory release checks.

### Locked files

- Step 1 edits `production_application_bootstrap.dart` (stopping nearby publishing), and steps 1 and 2 may edit `application_root.dart` (the expiry scheduler). The DTR-18 tests (`test/unit/dtr18_placement_closure_contract_test.dart`, `test/unit/dtr18_layering_relocation_contract_test.dart`) pin the SHA-256 of these files. Re-pin with a comment naming plan 407, only with owner approval, and never relax the check. Approved for `production_application_bootstrap.dart` in step 1; any other file needs its own approval. These tests run only in `core-host-all`, so that gate is required for any step that touches one of these files.
- A new `@pragma('vm:entry-point')` needs a root in `tool/runtime_roots/runtime_roots.json`. A new core-to-feature import needs a DTR-12 row in `architecture_boundary_exceptions.json`.

## Decisions

Owner decisions, 2026-10-20:

1. **Scope.** First version: share a thought with all friends, see it on the orbit, deleted after 24 hours. Everything else is "Later".
2. **24 hours everywhere.** The thought is deleted from friends' phones and from the author's phone after 24 hours.
3. **Old posts from TestFlight.** Delete them (C14).
4. **DTR-18 re-pin.** Approved for step 1: re-pin the digest of `production_application_bootstrap.dart` with a comment naming plan 407.
5. **The orbit keeps its current design.** No 3D world and no new 2D layout (2026-10-20); this replaces the earlier "3D world as step 4", "friends only in 3D" and "one orbit screen" decisions. The old-2D-plus-new-3D mockup on the iPhone 11 was the last look at it.
6. **Opening a chat from the orbit** ("Flatten": faces fly into a row above the chat) stays as step 4, pending confirmation that it still fits now that the orbit's design is kept.
7. **Thoughts on the orbit are note bubbles.** Instagram-style notes over faces on the two rings, on by default, faces drifting aside, pinch to hide and spread to show; the orbit opens at the largest avatar and ring sizes (N4, N7).
8. **Unseen is shown by the note's weight only** (option A). The unread ring stays for messages; no green dot.

From the 2026-10-20 reviews: incoming comments, reactions, passes, presence updates and pin messages are rejected before storage (C13); the expiry check on receive is part of step 1 (C12); thoughts expire while the app stays open (C15); the old-data cleanup covers the outbox tables and files and is recoverable (C14).

## Later

Decided or designed earlier on 2026-10-20, kept here for the next versions:


- **Choosing who sees it:** a Close list of up to 15 friends chosen by the user, and picked people (`pickPeople` with a "Close" label). Removing someone from Close never changes thoughts already sent.
- **Reactions:** six emoji (`❤️ 😍 😲 🔥 😂 👏`), one per person per thought, sent to the author only. Only the author sees counts, on their own thoughts.
- **Replies that quote the thought:** a `quoted_thought_id` field on chat messages; after the thought is gone the reply shows "Replied to a thought".
- **Keeping your own thoughts longer:** a "Keep my thoughts" setting, 7 days or Forever, for the author's copy only. Friends' copies stay at 24 h.
- **#tags and Spaces**, with their own retention, not pins.
- **One upload to the relay for big friend lists:** the locked thought once plus one locked key per friend, handed out by the relay. Needs a new relay request.

## Risks

- **Stale tests.** About 450 posts tests encode the old rules. Step 1 will touch many of them. Change each to the new rule; don't delete them.
- **Inbox first moves load to the relay.** Every friend who isn't connected now costs one relay inbox store per thought instead of a dial attempt first. Today those friends end up in the inbox anyway after the 4 s wait, so the number of stores barely changes. Watch the relay's inbox store count after release.
- **Moving faces in the app's orbit widget.** `OrbitalVisualization` seats are fixed today (`computeOrbitLayout`); the swim adds per-seat offsets and a note layer. Keep the seat math as it is and add the offsets on top, so the arcs, the badge and the long-press controls keep working unchanged when the notes are away.
- **Larger defaults for everyone.** N7 changes how every user's orbit looks, not only users with thoughts. The long-press controls still let anyone go smaller.
- **All friends is the only audience.** Every thought reaches every friend. The composer has to say so plainly until choosing an audience arrives.
- **Posts code still running.** Until the turned-off code is deleted, it still starts at launch. That is the state today. Step 1 stops nearby publishing, and C13 stops storing what thoughts never shows.
