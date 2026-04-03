# Two-Simulator User Journey Tests

Manual E2E tests using two (or three) iOS simulators to validate real user behavior.

**Setup:** Each simulator runs the app with a separate identity. Use `smoke_test_friends.sh` pattern or `--dart-define` for pre-seeded identities.

**Legend:**
- A = Device A (Simulator 1)
- B = Device B (Simulator 2)
- C = Device C (Simulator 3, when needed)

---

## 1. Contact Exchange

### 1.1 Normal QR Scan Flow
1. A opens QR display screen
2. B opens QR scanner, scans A's QR
3. **Assert A:** receives contact request notification
4. **Assert A:** taps notification → routes to pending request screen
5. A accepts the request
6. **Assert A:** B appears in Orbit friends list
7. **Assert B:** A appears in Orbit friends list
8. **Assert both:** Feed shows a ConnectionFeedItem for the new contact

### 1.2 Mutual QR Scan Race
1. A and B both open QR scanner simultaneously
2. A scans B's QR, B scans A's QR within ~1 second
3. **Assert:** No duplicate contacts created
4. **Assert:** No crash, no orphaned contact requests
5. **Assert:** Both end up as connected contacts (one request wins, other is deduplicated or auto-accepted)

### 1.3 Decline Contact Request
1. A scans B's QR → request sent
2. B receives request → declines
3. **Assert B:** A does not appear in contacts
4. **Assert A:** No error, request stays in "pending" 
5. A scans B's QR again → new request sent
6. **Assert B:** Can accept the second request normally

### 1.4 QR Scan While Offline
1. B turns off network (airplane mode)
2. A scans B's QR (offline — request queued in outbox)
3. B turns network back on
4. **Assert B:** Request arrives after reconnect

---

## 2. 1:1 Text Messaging

### 2.1 Basic Send & Receive
1. A sends a text message to B
2. **Assert A:** Message shows "sending" → "sent" → "delivered"
3. **Assert B:** Exactly 1 push notification arrives
4. B taps the notification
5. **Assert B:** App prepares inbox catch-up and opens the conversation with A
6. **Assert B:** A's message is visible in that conversation
7. **Assert B:** Returning to Feed later shows truthful unread state rather
   than a stale notification badge

### 2.2 Rapid Back-and-Forth
1. A sends message to B
2. B replies immediately
3. A replies to B's reply
4. Repeat 5 times quickly
5. **Assert both:** All messages appear in correct order
6. **Assert both:** No duplicates
7. **Assert both:** Delivery status reaches "delivered" for all

### 2.3 Long Message
1. A sends a message with 5000+ characters
2. **Assert B:** Full message received, not truncated
3. **Assert B:** Letter card renders correctly (scrollable or expanded)

### 2.4 Send While Recipient Has Conversation Open
1. B opens conversation with A (empty)
2. A sends a message
3. **Assert B:** Message appears in real-time in the open conversation (no need to refresh)
4. **Assert B:** No duplicate push notification (already viewing conversation)

---

## 3. Voice & Media Messages

### 3.1 Voice Message
1. A records and sends a voice message to B
2. **Assert B:** Notification arrives
3. **Assert B:** Voice message appears with waveform visualization
4. **Assert B:** Can play the voice message, audio is audible

### 3.2 Image Message
1. A sends an image to B
2. **Assert B:** Thumbnail appears in conversation
3. **Assert B:** Tap to view full image — EXIF metadata stripped (no location data)
4. **Assert A:** Status reaches "delivered"

### 3.3 Video Message
1. A sends a video to B
2. **Assert B:** Video thumbnail appears
3. **Assert B:** Can play the video

### 3.4 Multiple Attachments in One Message
1. A sends text + 3 images in a single message
2. **Assert B:** All 3 images arrive, text is visible
3. **Assert B:** Can view each image individually

### 3.5 Large Video Upload
1. A sends a large video (~50MB)
2. **Assert A:** Progress indicator visible during upload
3. **Assert B:** Video eventually arrives and is playable
4. **Assert A:** Status reaches "delivered"

---

## 4. Message Interactions

### 4.1 Emoji Reaction
1. A sends a message
2. B long-presses the message → adds emoji reaction
3. **Assert A:** Reaction appears on the message in real-time
4. B removes the reaction
5. **Assert A:** Reaction disappears

### 4.2 Quote / Reply
1. A sends "Hello"
2. B quotes A's message and replies "Hi back!"
3. **Assert A:** B's reply shows with quoted context of "Hello"
4. **Assert B:** Quote reference is tappable / visible

### 4.3 Edit Message
1. A sends "Hello wrold"
2. A edits the message to "Hello world"
3. **Assert B:** Message text updates to "Hello world"
4. **Assert B:** "Edited" indicator visible

### 4.4 Delete Message (for everyone)
1. A sends a message
2. B confirms receipt
3. A deletes the message (delete for everyone)
4. **Assert B:** Message replaced with deletion tombstone
5. **Assert A:** Message hidden locally (sender privacy)

### 4.5 Delete Message (local only)
1. A sends a message
2. A deletes the message locally
3. **Assert A:** Message disappears from A's view
4. **Assert B:** Message still visible (not affected)

---

## 5. Message Reliability — Send & Lock

### 5.1 Send and Immediately Lock Phone
1. A types a message and hits send
2. A locks the phone within 1 second (press power button)
3. **Assert B:** Message still arrives (send should complete in background)
4. A unlocks phone
5. **Assert A:** Message status is "delivered" (not stuck on "sending")

### 5.2 Send and Immediately Background the App
1. A sends a message
2. A swipes to home screen immediately
3. **Assert B:** Message arrives
4. A reopens the app
5. **Assert A:** Message status reflects actual state (sent or delivered, not stuck on "sending")

### 5.3 Send and Kill the App
1. A sends a message
2. A force-kills the app (swipe up from app switcher) within 1 second
3. **Two possible outcomes:**
   - Message was flushed to transport before kill → B receives it
   - Message was persisted to DB but not sent → status is "failed"
4. A reopens the app
5. **Assert A:** If message was "failed", retry mechanism picks it up
6. **Assert B:** Eventually receives the message (either from original send or retry)

### 5.4 Send During Network Transition (WiFi → Cellular)
1. A starts sending a message over WiFi
2. WiFi drops mid-send (toggle WiFi off on simulator)
3. **Assert A:** Message either completes via cellular or falls to "failed"
4. **Assert A:** If failed, retry succeeds once network stabilizes
5. **Assert B:** No duplicate messages received

---

## 6. Offline & Reconnect Scenarios

### 6.1 Recipient Offline — Inbox Delivery
1. B puts phone in airplane mode (or kill the app)
2. A sends a message to B
3. **Assert A:** Status goes to "sent" (stored in relay inbox)
4. B comes back online
5. **Assert B:** Inbox drains → message arrives
6. **Assert A:** Status updates to "delivered"

### 6.2 Multiple Messages While Offline
1. B goes offline
2. A sends 5 messages to B
3. B comes online
4. **Assert B:** All 5 messages arrive in correct chronological order
5. **Assert B:** No duplicates

### 6.3 Both Offline, Then Both Online
1. Both A and B go offline
2. A queues 2 messages, B queues 2 messages (to each other)
3. Both come online simultaneously
4. **Assert both:** All 4 messages arrive in correct order
5. **Assert both:** No message loss or duplication

### 6.4 Offline for Extended Period (>5 minutes)
1. B goes offline for 10 minutes
2. A sends 3 messages during that window
3. B comes back online
4. **Assert B:** All 3 messages arrive from inbox
5. **Assert:** Relay inbox held messages for the full duration

### 6.5 Cold Start After Push Notification
1. B's app is killed (not running)
2. A sends message → FCM push arrives on B's device
3. B taps the notification → app cold starts
4. **Assert B:** App starts → drains inbox → routes to conversation → message visible
5. **Assert:** No crash during cold start + drain + route sequence

---

## 7. Push Notification Journeys

**Core Contract:** Each message produces exactly 1 push notification. Tapping a
message notification prepares inbox catch-up and opens the directly targeted
conversation. Group notifications open the targeted group. Intro
notifications open Orbit intros. Feed unread badges remain the source of truth
when the user later returns to Feed.

### 7.1 Single Message — Tap Notification
1. B backgrounds the app (home screen)
2. A sends a single message to B
3. **Assert B:** Exactly 1 push notification appears in notification center
4. B taps the notification
5. **Assert B:** App drains any pending inbox work, then opens the
   conversation with A
6. **Assert B:** The incoming message is visible in that conversation
7. **Assert B:** No duplicate route or stale intermediate Feed state appears

### 7.2 Multiple Messages — Tap Notification
1. B backgrounds the app
2. A sends 3 messages to B with ~5 second gaps
3. **Assert B:** Exactly 3 push notifications appear (1 per message)
4. B taps any one of the notifications
5. **Assert B:** App opens directly to the conversation with A
6. **Assert B:** All 3 incoming messages are visible in chronological order
7. **Assert B:** Returning to Feed later reflects truthful unread state for A

### 7.3 Multiple Senders — Separate Notifications
1. B backgrounds the app
2. A sends a message to B
3. C sends a message to B
4. **Assert B:** 2 push notifications (1 from A, 1 from C)
5. B taps A's notification
6. **Assert B:** The conversation with A opens and shows A's message
7. **Assert B:** Returning to Feed later still shows C's thread with its own
   unread state

### 7.4 Notification While App is Foregrounded (Different Screen)
1. B has the app open on the Settings screen (not Feed, not conversation with A)
2. A sends a message
3. **Assert B:** In-app notification or badge update appears (no system push — app is foregrounded)
4. B navigates to Feed
5. **Assert B:** A's stack card shows the message with badge **1**

### 7.5 Notification While Viewing Feed
1. B has the Feed screen open
2. A sends a message
3. **Assert B:** A's stack card updates in real-time (message preview, badge increments)
4. **Assert B:** No system push notification (already on Feed)

### 7.6 Notification While Viewing That Conversation
1. B has the conversation with A open
2. A sends a message
3. **Assert B:** Message appears in-line in real-time
4. **Assert B:** No push notification at all (already viewing A's messages)
5. B goes back to Feed
6. **Assert B:** Stack card for A does NOT show unread badge (message already read)

### 7.7 Stale Notification Tap
1. A sends a message → notification appears on B's device
2. B does NOT tap the notification
3. B manually opens the app → reads the message in conversation or via Feed
4. B backgrounds the app, then taps the old notification from notification center
5. **Assert B:** App opens the conversation target without crashing
6. **Assert B:** The message is still visible, but unread state is already
   cleared

### 7.8 Notification Tap — Cold Start
1. B's app is killed (not running)
2. A sends a message → FCM push arrives
3. B taps the notification
4. **Assert B:** App cold starts → drains inbox → opens the conversation with
   A
5. **Assert B:** The tapped message is visible
6. **Assert B:** No crash occurs during cold start + drain + route

### 7.9 Notification Badge Accuracy After Reading
1. B backgrounds the app
2. A sends 2 messages → B receives 2 notifications
3. B taps a notification → the conversation with A opens
4. B reads both messages
5. B backgrounds and foregrounds the app
6. **Assert B:** When B later returns to Feed, A's unread badge is cleared
   (0 or hidden)

### 7.10 Notification Badge Accumulation
1. B backgrounds the app
2. A sends 1 message → badge = 1
3. A sends another message → badge = 2
4. A sends a third → badge = 3
5. B opens the app or later returns to Feed
6. **Assert B:** A's Feed thread shows badge **3** (accumulated, not just the
   latest)
7. **Assert B:** Opening the conversation with A shows all 3 messages

### 7.11 No Duplicate Notifications
1. A sends a single message to B
2. **Assert B:** Exactly 1 notification — not 2 or more
3. B does NOT tap the notification
4. B opens app manually → reads message → backgrounds
5. **Assert B:** No new notification for the same message

### 7.12 Notification for Different Message Types
1. B backgrounds the app
2. A sends a text message → **Assert:** 1 notification, tap → Feed → stack card with text
3. A sends a voice message → **Assert:** 1 notification, tap → Feed → stack card with voice indicator
4. A sends an image → **Assert:** 1 notification, tap → Feed → stack card with image thumbnail

### 7.13 Notification for Non-Message Events
1. B backgrounds the app
2. A sends a contact request → B receives `contact_request` notification
3. B taps → **Assert:** Routes to appropriate screen (contact request UI)
4. A sends an introduction (requires C) → B receives `intros` notification
5. B taps → **Assert:** Routes to Orbit introductions section
6. A creates a post mentioning B → B receives `post_create` notification
7. B taps → **Assert:** Routes to post detail

---

## 8. Feed & Stack Card UI State

### 8.1 Stack Card Updates After Message
1. A sends a message to B
2. **Assert B:** Feed shows A's stack card with message preview text
3. **Assert B:** Notification badge visible on the stack card (shows **1**)
4. **Assert B:** Sender name / avatar visible on the card
5. B taps the stack card → card expands showing the message
6. B reads the message
7. **Assert B:** Badge clears on A's stack card

### 8.2 Stack Card Expands with Multiple Messages
1. A sends 3 messages to B
2. **Assert B:** A's stack card shows badge **3**
3. B taps the stack card → card expands
4. **Assert B:** All 3 messages visible inside the expanded stack card
5. **Assert B:** Messages in chronological order

### 8.3 Feed Ordering
1. B has conversations with A and C
2. C sends a message to B
3. A sends a message to B (after C)
4. **Assert B:** Feed shows A's stack card above C's (most recent first)
5. **Assert B:** Both cards show their respective badges

### 8.4 Stack Card Badge Decrements on Read
1. A sends 3 messages to B → badge = **3**
2. B expands the stack card, reads 1 message
3. **Assert B:** Badge decrements appropriately
4. B reads remaining messages
5. **Assert B:** Badge fully cleared

### 8.5 Connection Card on New Contact
1. A and B exchange QR and connect
2. **Assert both:** Feed shows a ConnectionFeedItem (not a stack card with messages — no messages yet)
3. A sends first message
4. **Assert B:** Feed transitions from ConnectionFeedItem to stack card with message and badge **1**

### 8.6 Conversation After Notification Tap
1. B's app is backgrounded
2. A sends a message → notification arrives
3. B taps the notification
4. **Assert B:** The conversation with A opens after inbox preparation
5. **Assert B:** The message is visible immediately
6. **Assert B:** Returning to Feed later shows truthful unread state

### 8.7 Multiple Senders on Feed
1. A sends 2 messages to B
2. C sends 1 message to B
3. **Assert B:** Feed shows two stack cards: A (badge **2**) and C (badge **1**)
4. B taps A's card → expands showing 2 messages
5. B collapses A's card → taps C's card → expands showing 1 message
6. **Assert:** Each card independently tracks its own badge and expanded state

---

## 9. Introduction Flow (Three Simulators)

### 9.1 Normal Introduction
1. A is connected to both B and C (B and C are NOT connected)
2. A opens Friend Picker → selects B and C → sends introduction
3. **Assert B:** Receives notification → Orbit shows pending introduction from A (showing C's username)
4. **Assert C:** Receives notification → Orbit shows pending introduction from A (showing B's username)
5. B accepts the introduction
6. C accepts the introduction
7. **Assert:** Mutual acceptance detected → B and C are now contacts
8. **Assert B:** C appears in Orbit friends list
9. **Assert C:** B appears in Orbit friends list
10. B sends a message to C
11. **Assert C:** Message received (encrypted, key exchange completed during introduction)

### 9.2 One Accepts, One Passes
1. A introduces B and C
2. B accepts
3. C passes (declines)
4. **Assert:** B and C are NOT connected
5. **Assert A:** Introduction status shows "passed"

### 9.3 Simultaneous Accept Race
1. A introduces B and C
2. B and C both tap "Accept" at the exact same moment
3. **Assert:** Mutual acceptance works correctly — B and C become contacts
4. **Assert:** No duplicate contacts, no crash

### 9.4 Introduction Response Arrives Before Introduction
1. A introduces B and C
2. B's device is slow (or A's message to B delayed)
3. C accepts quickly → acceptance message reaches B before A's introduction message
4. **Assert B:** Pending response is stored
5. **Assert B:** When A's introduction message arrives, pending response replays → mutual acceptance triggers

### 9.5 Introduction Expiry
1. A introduces B and C
2. Neither B nor C responds for 30+ days
3. **Assert:** Introduction status becomes "expired"
4. **Assert:** No stale introduction cards in Orbit

---

## 10. Group Messaging (Two or Three Simulators)

### 10.1 Create Group & Invite
1. A creates a group named "Test Group" (type: chat)
2. A invites B to the group
3. **Assert B:** Receives group invite notification
4. B accepts the invite
5. **Assert B:** Group appears in group list
6. **Assert A:** B shows as a member

### 10.2 Group Message Send & Receive
1. A and B are in the same group
2. A sends a message in the group
3. **Assert B:** Message appears in group conversation
4. B sends a reply
5. **Assert A:** Reply appears in group conversation

### 10.3 Group Message Before Mesh Formed
1. A creates group and invites B
2. B accepts the invite
3. A immediately sends a message (before GossipSub mesh is fully formed)
4. **Assert:** Message either delivers via pubsub (if mesh ready) or falls back to inbox relay
5. **Assert B:** Message eventually arrives

### 10.4 Group Message While Recipient Offline
1. A and B are in a group
2. B goes offline
3. A sends a group message
4. B comes back online
5. **Assert B:** Message arrives via inbox relay (store-and-forward)

### 10.5 Group Reactions
1. A sends a group message
2. B adds a reaction
3. **Assert A:** Reaction appears on the message

### 10.6 Leave Group
1. A and B are in a group
2. B leaves the group
3. A sends a message
4. **Assert B:** Does NOT receive the message (no longer subscribed)

---

## 11. Posts

### 11.1 Post Creation & Discovery
1. A creates a text post (audience: B)
2. **Assert B:** Notification arrives
3. **Assert B:** Post visible in posts feed (shows A's username, post text)

### 11.2 Post with Media
1. A creates a post with text + image
2. **Assert B:** Post shows in feed with image thumbnail
3. **Assert B:** Tap to view full image

### 11.3 Heart a Post
1. A creates a post, B sees it
2. B hearts the post
3. **Assert A:** Heart count increments
4. **Assert B:** Heart icon shows "hearted" state

### 11.4 Comment on a Post
1. A creates a post
2. B writes a comment
3. **Assert A:** Comment notification arrives
4. **Assert A:** Comment visible on the post

### 11.5 Pass a Post Along (Three Simulators)
1. A creates a post (audience: B)
2. B passes the post along to C
3. **Assert C:** Post appears in feed (shows original author A, forwarded by B)

---

## 12. Encryption Edge Cases

### 12.1 v1 → v2 Encryption Upgrade
1. A and B connect (B has no ML-KEM key — old client)
2. A sends message → **Assert:** v1 plaintext envelope used
3. B upgrades client (ML-KEM key generated)
4. B sends a new contact request or key update to A
5. A sends another message → **Assert:** v2 encrypted envelope used
6. **Assert B:** Both v1 and v2 messages are readable

### 12.2 ML-KEM Key Missing at Send Time
1. A has a contact B with no ML-KEM public key stored
2. A sends a message
3. **Assert:** Message falls back to v1 (plaintext envelope) — no crash
4. **Assert B:** Message received and readable

### 12.3 Decryption Failure Handling
1. Manually corrupt a v2 message envelope (if possible via debug tooling)
2. **Assert B:** Decryption fails gracefully
3. **Assert B:** Message shows error state (not a crash)
4. **Assert B:** Other messages in the conversation are unaffected

---

## 13. Contact Management Edge Cases

### 13.1 Block a Contact
1. A and B are connected
2. A blocks B
3. B sends a message to A
4. **Assert A:** Message does NOT appear (blocked)
5. A unblocks B
6. B sends another message
7. **Assert A:** Message now appears

### 13.2 Archive a Contact
1. A archives B
2. **Assert A:** B disappears from active Orbit list
3. **Assert A:** B visible when "Archived" filter toggled
4. B sends a message
5. **Assert A:** B's thread card still appears in Feed (archive doesn't block messages)

### 13.3 Delete Contact While Messages In-Flight
1. A sends a message to B
2. Before delivery confirmation, A deletes contact B
3. **Assert:** No crash, message either delivers or fails gracefully
4. **Assert A:** B removed from contacts, conversation history cleared

### 13.4 Delete Contact and Re-Add
1. A and B are connected
2. A deletes B
3. A scans B's QR again → new contact request
4. B accepts
5. **Assert:** Fresh contact, no stale conversation data from before

---

## 14. Race Conditions

### 14.1 Double-Tap Send
1. A types a message
2. A taps "Send" rapidly twice
3. **Assert:** Only one message sent (not duplicated)
4. **Assert B:** Receives exactly one message

### 14.2 Send While Reconnecting
1. A's network drops briefly
2. While P2P service is in `relay:reconnect` recovery phase, A hits send
3. **Assert:** Message either queues for retry or waits for reconnect — no crash
4. **Assert:** Message eventually delivers after reconnect completes

### 14.3 Notification Tap During Inbox Drain
1. B's app is resuming from background (inbox drain in progress)
2. B taps a push notification during this window
3. **Assert:** App does not crash
4. **Assert:** Navigation completes to correct conversation after drain finishes
5. **Assert:** No duplicate messages from both drain + notification paths

### 14.4 Start Node While Recovery In Progress
1. B's app triggers a health check recovery (`relay:reconnect`)
2. Simultaneously, a notification tap triggers `startNode()`
3. **Assert:** Only one start/recovery runs (coalescing works)
4. **Assert:** No duplicate P2P connections

### 14.5 Simultaneous Messages from Both Sides
1. A and B both type messages at the same time
2. Both tap send within ~100ms of each other
3. **Assert both:** Both messages arrive
4. **Assert both:** Conversation shows both messages in correct time order
5. **Assert:** No delivery status confusion (A's message doesn't get B's ACK)

### 14.6 Message Arrives During Contact Deletion
1. A is deleting contact B (in progress)
2. B's message arrives at exact same moment
3. **Assert:** No crash
4. **Assert:** Either message is discarded (contact gone) or deletion waits

### 14.7 Accept Contact Request While Offline Message Queued
1. B sends a contact request to A
2. Before A accepts, B also sends a message (via relay inbox, since not yet contacts)
3. A accepts the contact request
4. **Assert:** Message from B (sent before acceptance) is either received or gracefully discarded
5. **Assert:** No orphaned messages in inbox

### 14.8 App Kill During Retry Loop
1. A has a failed message in retry queue
2. Retry mechanism kicks in and starts re-sending
3. A force-kills the app mid-retry
4. A reopens the app
5. **Assert:** Retry picks up again from persisted state
6. **Assert B:** Receives exactly one copy (no duplicate from interrupted retry)

### 14.9 Two Conversations Racing for Same Relay
1. A sends a message to B via relay
2. A sends a message to C via the same relay simultaneously
3. **Assert:** Both messages delivered to correct recipients
4. **Assert:** No cross-contamination (B doesn't get C's message)

---

## 15. Background / Foreground Lifecycle

### 15.1 Background → Message → Foreground
1. B backgrounds the app
2. A sends a message
3. B foregrounds the app
4. **Assert B:** Message appears (either via push handler or resume inbox drain)
5. **Assert:** No "stuck on loading" state

### 15.2 Repeated Background/Foreground Cycling
1. B backgrounds → foregrounds → backgrounds → foregrounds (5 times rapidly)
2. A sends a message during one of the background phases
3. **Assert B:** Message arrives, app is stable
4. **Assert:** No leaked timers, no duplicate health checks, no zombie connections

### 15.3 Background for Extended Period (>1 hour)
1. B backgrounds the app for 1+ hour
2. A sends messages during this period
3. B foregrounds the app
4. **Assert B:** All messages arrive via inbox drain
5. **Assert:** P2P node reconnects cleanly (health check triggers recovery)

### 15.4 App Suspended by OS
1. B's app is suspended by iOS (memory pressure, or just time)
2. A sends a message → push notification arrives
3. B taps notification
4. **Assert:** App resumes or cold-starts → drains inbox → navigates to conversation
5. **Assert:** Identity and keys are loaded correctly from secure storage

---

## 16. Network Fault Scenarios

### 16.1 Direct Connection → Relay Fallback
1. A and B are connected directly (same WiFi)
2. Move B to different network (toggle WiFi on simulator)
3. A sends a message
4. **Assert:** Direct send times out (4s budget) → relay probe kicks in → relay delivery
5. **Assert B:** Message received via relay path
6. **Assert A:** Status still reaches "delivered"

### 16.2 Relay Down → Inbox Fallback
1. A sends a message to B
2. Direct connection fails, relay probe also fails
3. **Assert A:** Message falls back to inbox store (`storeInInbox`)
4. **Assert A:** Status goes to "sent" (unacked)
5. B comes online later → drains inbox
6. **Assert B:** Message arrives

### 16.3 Network Flapping
1. A toggles network on/off every 5 seconds (5 cycles)
2. A sends a message during one of the "on" windows
3. **Assert:** Message eventually delivers (retry handles flapping)
4. **Assert:** No duplicate messages
5. **Assert:** P2P service doesn't get stuck in recovery loop

### 16.4 Slow Network (High Latency)
1. Use Network Link Conditioner to add 2000ms latency on B's simulator
2. A sends a message
3. **Assert:** Message delivers (may take longer but succeeds)
4. **Assert A:** Status transitions are correct (no premature "failed")

---

## 17. Startup & First-Run Edge Cases

### 17.1 Fresh Install → First Message
1. A is a fresh install → generates identity
2. B is a fresh install → generates identity
3. A and B exchange QR codes → become contacts
4. A sends first-ever message
5. **Assert:** Empty conversation state transitions to letter cards correctly
6. **Assert B:** First message appears, origin marker visible

### 17.2 App Update with Migration
1. B has existing data (contacts, messages)
2. B "updates" the app (install new version with higher DB version)
3. A sends a message during B's startup (migration running)
4. **Assert B:** Migration completes → message arrives → no data corruption
5. **Assert:** Old messages and contacts preserved

### 17.3 Identity Restore on New Device
1. A has an identity with existing contacts
2. A restores identity on a new simulator (enter 12-word mnemonic)
3. **Assert:** PeerID is the same as before
4. B sends a message to A
5. **Assert A:** Message arrives on new device (same peer identity)

---

## 18. Multi-Conversation Scenarios

### 18.1 Switching Between Conversations Rapidly
1. B has conversations with A and C
2. B opens conversation with A → A sends a message → B sees it
3. B immediately switches to conversation with C → C sends a message → B sees it
4. B switches back to A
5. **Assert:** Messages are in correct conversations, no cross-talk

### 18.2 Receiving Messages from Multiple Contacts
1. A and C both send messages to B within 1 second
2. **Assert B:** Both messages arrive in correct conversations
3. **Assert B:** Feed shows both thread cards updated
4. **Assert B:** Notifications are distinct (not merged)

---

## How to Run

### Simulator Setup
```bash
# Boot two simulators
xcrun simctl boot "iPhone 16"     # Simulator A
xcrun simctl boot "iPhone 16 Pro" # Simulator B

# Install and launch on both
flutter run -d <sim-A-id> --dart-define=TEST_USER=alice
flutter run -d <sim-B-id> --dart-define=TEST_USER=bob
```

### Network Manipulation
```bash
# Toggle airplane mode equivalent
xcrun simctl status_bar <sim-id> override --dataNetwork wifi
xcrun simctl status_bar <sim-id> clear

# For real network faults: use Network Link Conditioner
# (System Preferences → Developer → Network Link Conditioner)
```

### Observation Checklist per Test
- [ ] Message delivery status transitions (sending → sent → delivered)
- [ ] Push notification received
- [ ] Correct screen navigation on notification tap
- [ ] Feed/Orbit UI updates in real-time
- [ ] No crashes in device logs (`xcrun simctl spawn <id> log stream`)
- [ ] No duplicate messages
- [ ] Database state consistent (check via debug screen if available)

---
---

# Introduction User Journey Tests

Exhaustive two/three-simulator tests for the introduction feature.

**Actors:**
- **A (Introducer):** knows both B and C, initiates introductions
- **B (Recipient):** the person A is introducing friends TO
- **C (Introduced):** the friend being introduced to B
- **D (Second Introducer):** used in multi-introducer scenarios

**Status Reference:**
- Per-party: `pending` → `accepted` | `passed`
- Overall: `pending` → `mutualAccepted` | `passed` | `expired` | `alreadyConnected`
- `mutualAccepted` requires BOTH parties accepted
- `passed` triggers if EITHER party passes (terminal)
- `expired` after 30 days of `pending`

---

## I-1. Happy Path — Full Introduction Lifecycle

### I-1.1 Basic Introduction: Both Accept
1. A opens Friend Picker, selects B and C
2. A sends introduction
3. **Assert A:** Local intro record saved with `recipientStatus=pending, introducedStatus=pending`
4. **Assert B:** Notification arrives → Orbit shows pending intro from A (C's username visible)
5. **Assert C:** Notification arrives → Orbit shows pending intro from A (B's username visible)
6. B opens Orbit → taps Accept on C's intro
7. **Assert B:** `recipientStatus=accepted`, overall still `pending`
8. **Assert A:** Receives B's accept → `recipientStatus=accepted` on A's local record
9. **Assert C:** Receives B's accept → `recipientStatus=accepted` on C's local record
10. C opens Orbit → taps Accept on B's intro
11. **Assert C:** `introducedStatus=accepted`, overall = `mutualAccepted`
12. **Assert:** Auto-contact creation fires — B and C are now contacts
13. **Assert B:** C appears in Orbit friends list with correct username
14. **Assert C:** B appears in Orbit friends list with correct username
15. **Assert B:** System message "Connected through A" in conversation with C
16. **Assert C:** System message "Connected through A" in conversation with B
17. B sends a text message to C
18. **Assert C:** Message received (encrypted with ML-KEM keys from intro)

### I-1.2 Basic Introduction: Recipient Accepts First
1. A introduces B to C
2. B accepts before C even opens the app
3. C comes online, sees intro, accepts
4. **Assert:** Same outcome as I-1.1 — order doesn't matter

### I-1.3 Basic Introduction: Introduced Accepts First
1. A introduces B to C
2. C accepts first
3. B accepts second
4. **Assert:** Same outcome — `mutualAccepted`, contacts created

### I-1.4 First Message After Introduction Uses Encryption
1. Complete I-1.1 (B and C are now contacts)
2. B sends message to C
3. **Assert:** Message uses v2 envelope (ML-KEM encrypted), not v1 plaintext
4. **Assert C:** Decrypts and reads message successfully
5. C replies to B
6. **Assert B:** Decrypts and reads reply successfully

---

## I-2. Pass / Decline Scenarios

### I-2.1 Recipient Passes
1. A introduces B to C
2. B receives intro → taps Pass
3. **Assert B:** `recipientStatus=passed`, overall = `passed`
4. **Assert A:** Receives B's pass → overall = `passed`
5. **Assert C:** Receives B's pass → overall = `passed`
6. **Assert:** B and C are NOT contacts
7. **Assert C:** Cannot accept anymore (intro is terminal)

### I-2.2 Introduced Passes
1. A introduces B to C
2. C receives intro → taps Pass
3. **Assert:** Same as I-2.1 but with C as the passer
4. **Assert:** B and C are NOT contacts

### I-2.3 Both Pass
1. A introduces B to C
2. B passes, C passes (either order)
3. **Assert:** Overall = `passed`, no contacts created

### I-2.4 One Accepts, Then Other Passes
1. A introduces B to C
2. B accepts the intro
3. C passes the intro
4. **Assert:** Overall = `passed` (pass is terminal, trumps accept)
5. **Assert:** B and C are NOT contacts
6. **Assert B:** No system message about connection

### I-2.5 One Passes, Then Other Tries to Accept
1. A introduces B to C
2. B passes
3. C sees intro → tries to accept
4. **Assert:** Overall stays `passed` (terminal)
5. **Assert:** No contact creation triggered

---

## I-3. Timing & Delivery Races

### I-3.1 Accept Arrives Before Introduction (Deferred Response)
1. A sends intro to B and C
2. C's device receives and processes the intro quickly → C accepts immediately
3. C's accept message reaches B BEFORE A's intro 'send' message reaches B
4. **Assert B:** C's accept stored as `PendingIntroductionResponse` (no intro record yet)
5. A's intro 'send' finally arrives at B
6. **Assert B:** Intro created → `_replayPendingResponses()` fires → C's accept applied
7. **Assert B:** If B also accepts → `mutualAccepted` → contact created
8. **Assert:** No pending responses left in DB after replay

### I-3.2 Both Accepts Arrive Before Introduction
1. A sends intro to B and C
2. Both B and C somehow accept before A's 'send' reaches the other party
   (e.g., each receives 'send' from A, accepts, but cross-accepts arrive before cross-sends)
3. **Assert:** Both accepts stored as `PendingIntroductionResponse`
4. When 'send' arrives → both replayed → `mutualAccepted` immediately
5. **Assert:** Contacts created, no intermediate `pending` visible in UI

### I-3.3 Simultaneous Accept from Both Parties
1. A introduces B to C
2. Both B and C receive the intro
3. B and C both tap Accept at the exact same moment
4. **Assert:** Both send accept messages to each other and to A
5. **Assert:** `mutualAccepted` detected on both devices
6. **Assert:** Contact created on both devices (idempotent — no duplicate)
7. **Assert:** Exactly one contact per device (not two)

### I-3.4 Accept During Network Flap
1. A introduces B to C
2. B taps Accept, but network drops mid-send
3. B's accept message fails to reach C and A
4. B's local status updates to `accepted` anyway
5. Network returns → B's accept retried (or C separately accepts)
6. **Assert:** Introduction eventually resolves correctly
7. **Assert:** No stuck `accepted` on B with `pending` on C forever

### I-3.5 Introducer Offline After Sending
1. A sends intro to B and C
2. A immediately goes offline (airplane mode / kill app)
3. B and C both accept
4. **Assert B:** Contact with C created
5. **Assert C:** Contact with B created
6. **Assert:** A's local record stays `pending` (never received accepts)
7. A comes back online
8. **Assert A:** Eventually receives accepts, record updates to `mutualAccepted`

### I-3.6 Introducer Offline Permanently
1. A sends intro to B and C, then A's device is destroyed
2. B and C both accept
3. **Assert:** B and C still become contacts (A is not required for handshake)
4. **Assert:** A's accept messages are simply undelivered (no harm)

### I-3.7 One Recipient Never Receives Intro
1. A sends intro to B and C
2. B receives intro, accepts
3. C's device is offline indefinitely (or relay loses the message)
4. **Assert B:** Intro stays `pending` (waiting for C)
5. After 30 days → **Assert B:** Intro status = `expired`
6. **Assert:** No contact created

---

## I-4. Already-Connected Scenarios

### I-4.1 Recipients Already Contacts
1. B and C are already contacts (exchanged QR previously)
2. A introduces B to C
3. **Assert B:** Intro arrives, status set to `alreadyConnected`
4. **Assert B:** System message "A introduced C to you — you're already connected"
5. **Assert B:** Intro appears in pending list but cannot be accepted
6. **Assert C:** Same behavior on C's side

### I-4.2 Become Contacts Between Intro Send and Receive
1. A sends intro to B and C
2. Before B receives the intro, B and C independently exchange QR and connect
3. B receives the intro
4. **Assert B:** Detects C is already a contact → `alreadyConnected`
5. **Assert:** No duplicate contact created

### I-4.3 Already Connected + Accept Race
1. B and C are already contacts
2. A introduces B to C
3. B receives intro (`alreadyConnected`)
4. C receives intro (`alreadyConnected`)
5. **Assert:** No `mutualAccepted` flow triggered (would be redundant)
6. **Assert:** No duplicate contacts

---

## I-5. Multiple Introduction Scenarios

### I-5.1 Batch Introduction (A Introduces Multiple Friends to B)
1. A has 5 contacts: B, C, D, E, F
2. A opens Friend Picker → selects C, D, E, F to introduce to B
3. A sends all 4 introductions
4. **Assert B:** Receives 4 separate intro notifications
5. **Assert B:** Orbit shows 4 pending intros, grouped under A as introducer
6. B accepts C, D, E → passes F
7. C, D, E each accept B
8. **Assert B:** 3 new contacts (C, D, E), F is passed
9. **Assert F:** Intro is `passed`, F and B are not contacts

### I-5.2 Same Pair Introduced by Different Introducers
1. A introduces B to C
2. Separately, D also introduces B to C
3. **Assert B:** Two distinct intro records (different IDs)
4. **Assert B:** Both appear in Orbit (grouped under A and D separately)
5. B accepts A's intro, C accepts A's intro → `mutualAccepted`
6. **Assert:** B and C become contacts via A's intro
7. D's intro still shows in B's Orbit as `pending`
8. B and C are now already connected
9. If B receives D's intro after connecting → **Assert:** `alreadyConnected`

### I-5.3 Same Pair Introduced Twice by Same Introducer
1. A introduces B to C
2. A introduces B to C again (UI bug, network retry, or intentional)
3. **Assert B:** Two intro records with different IDs
4. **Assert:** Both functional — accepting either one works
5. **Assert:** No crash, no data corruption

### I-5.4 Chain Introduction
1. A knows B and C → A introduces B to C → they connect
2. B now knows C → B introduces C to D (B's other contact)
3. **Assert:** C and D go through normal intro flow
4. **Assert C:** `introducedBy` field on D's contact shows B, not A

### I-5.5 Circular Introduction
1. A introduces B to C → they connect
2. B introduces C to A (A and C are already contacts)
3. **Assert A:** Intro arrives, status = `alreadyConnected`
4. **Assert C:** Intro arrives, status = `alreadyConnected`

---

## I-6. Block & Contact State Interactions

### I-6.1 Introducer Blocked by Recipient
1. B blocks A
2. A sends intro of C to B
3. **Assert B:** Intro rejected (IntroductionListener blocks 'send' from blocked contacts)
4. **Assert B:** No intro record saved
5. **Assert C:** C receives intro normally (C didn't block A)
6. C accepts → but B never received it → intro stuck on C as `pending`

### I-6.2 Block Introduced Party After Accepting
1. A introduces B to C
2. B accepts
3. B blocks C (before C accepts)
4. C accepts → sends accept to B
5. **Assert B:** C's accept is still processed (accept/pass bypass block check)
6. **Assert:** `mutualAccepted` triggers, contact created
7. **Assert B:** C is a contact BUT also blocked — blocking should take precedence for messages

### I-6.3 Block Introducer After Receiving Intro
1. A introduces B to C
2. B receives intro
3. B blocks A
4. B still has the intro in Orbit
5. B accepts the intro
6. **Assert:** Accept message sent to A and C (A being blocked doesn't prevent B from acting)
7. C accepts → mutual acceptance → contact created
8. **Assert:** B and C connected despite B blocking A

### I-6.4 Delete Introducer as Contact
1. A introduces B to C
2. B receives intro
3. B deletes A as a contact
4. B accepts the intro
5. **Assert:** Accept payload still sent (uses intro record, not contact record for routing)
6. C accepts → mutual acceptance works
7. **Assert:** B and C connected

### I-6.5 Delete Introduced Party After Mutual Acceptance
1. A introduces B to C → both accept → contacts created
2. B deletes C as a contact
3. **Assert:** Intro record stays `mutualAccepted` (no cascade)
4. **Assert B:** C no longer in Orbit friends list
5. C sends message to B → **Assert B:** Message not received (contact deleted)

---

## I-7. Notification & UI Journeys

### I-7.1 Intro Notification → Orbit Navigation
1. B's app is backgrounded
2. A sends intro of C to B
3. **Assert B:** Push notification arrives (type: `intros`)
4. B taps notification
5. **Assert B:** App opens → navigates to Orbit → introductions section visible
6. **Assert B:** C's intro card visible under A as introducer

### I-7.2 Mutual Acceptance Notification
1. A introduces B to C
2. B accepts
3. C's app is backgrounded
4. B's accept reaches C
5. C comes to foreground, accepts
6. **Assert B:** Notification arrives — "You and C are now connected" (or similar)
7. **Assert B:** Tapping notification navigates to conversation with C (or Orbit)

### I-7.3 Multiple Intro Notifications Stacked
1. B's app is backgrounded
2. A introduces B to C, D, and E (3 separate intros)
3. **Assert B:** 3 notifications arrive
4. B taps one notification
5. **Assert B:** Orbit shows all 3 pending intros (not just the tapped one)

### I-7.4 Stale Intro Notification
1. A introduces B to C → notification on B
2. B ignores notification
3. C passes the intro → intro becomes `passed`
4. B taps the old notification
5. **Assert B:** App opens Orbit → intro shows as `passed` (not actionable)
6. **Assert:** No crash, no stale accept button

### I-7.5 Intro Count Badge
1. B has 0 pending intros
2. A introduces B to C → B receives
3. **Assert B:** Orbit badge shows "1"
4. A introduces B to D → B receives
5. **Assert B:** Orbit badge shows "2"
6. B accepts C's intro
7. **Assert B:** Badge updates (may still show 1 if D's is pending)
8. B passes D's intro
9. **Assert B:** Badge shows "0"

### I-7.6 System Message in Conversation
1. A introduces B to C → both accept → contacts created
2. B opens conversation with C
3. **Assert B:** First item is system message "Connected through A"
4. **Assert:** System message styled differently (centered, muted — not a letter card)
5. B sends first real message
6. **Assert:** System message remains above the sent message

---

## I-8. Encryption Edge Cases

### I-8.1 Introduction with ML-KEM Keys (v2 Envelope)
1. A, B, C all have ML-KEM keys (modern clients)
2. A introduces B to C
3. **Assert:** Intro payload sent as v2 encrypted envelope to both B and C
4. **Assert B:** Decrypts successfully, sees C's username and crypto keys
5. **Assert C:** Decrypts successfully, sees B's username and crypto keys

### I-8.2 Introduction Without ML-KEM Keys (v1 Fallback)
1. B has no ML-KEM public key (old client / not yet generated)
2. A introduces B to C
3. **Assert:** Payload to B sent as v1 plaintext envelope (graceful fallback)
4. **Assert:** Payload to C sent as v2 (C has ML-KEM key)
5. **Assert B:** Receives and parses v1 payload correctly
6. Both accept → contacts created
7. **Assert:** B's new contact for C has C's ML-KEM key (from intro payload)
8. **Assert:** C's new contact for B has NO ML-KEM key (B didn't have one)

### I-8.3 ML-KEM Key in Intro vs Contact Key Mismatch
1. C rotates their ML-KEM key after A looked it up but before A sends intro
2. A sends intro with C's OLD ML-KEM key
3. B accepts, gets C's old key in contact record
4. B tries to send message to C using old key
5. **Assert:** Either decryption fails on C → fallback, or key exchange protocol handles it

### I-8.4 Decryption Failure on v2 Intro Envelope
1. A sends v2 encrypted intro to B
2. B's ML-KEM secret key is missing from secure storage (edge case)
3. **Assert B:** Listener returns `retryableError`
4. **Assert B:** Message stays in stream for reprocessing
5. B's key becomes available (app restart, key load)
6. **Assert B:** Intro eventually processes successfully

### I-8.5 Crypto Material Preserved Through Full Chain
1. A introduces B to C
2. **Assert:** Intro record stores B's `publicKey`, `mlKemPublicKey`, C's `publicKey`, `mlKemPublicKey`
3. Both accept → contact created
4. **Assert B:** C's contact has `publicKey` and `mlKemPublicKey` matching what A originally sent
5. **Assert C:** B's contact has `publicKey` and `mlKemPublicKey` matching what A originally sent
6. B sends encrypted message to C → C decrypts → **Assert:** Content matches

---

## I-9. Offline & Delivery Fault Scenarios

### I-9.1 Recipient Offline When Intro Sent
1. B is offline (app killed)
2. A sends intro of C to B
3. **Assert:** Intro stored in B's relay inbox
4. B comes online → inbox drains
5. **Assert B:** Intro arrives, appears in Orbit

### I-9.2 Both Recipients Offline
1. B and C are both offline
2. A sends intro
3. **Assert:** Both intros stored in relay inbox
4. B comes online first → sees intro → accepts
5. B's accept stored in C's relay inbox
6. C comes online → drains inbox → receives intro AND B's accept
7. **Assert C:** Pending response replayed if accept arrived before send
8. C accepts → `mutualAccepted`
9. **Assert:** Contacts created on both

### I-9.3 Accept Message Lost
1. A introduces B to C
2. B accepts → accept message fails to deliver to C (relay down, etc.)
3. C never receives B's accept
4. C accepts independently
5. **Assert C:** C's side sees `mutualAccepted` (C accepted + own status)
   - Wait — actually C needs to know B accepted. If B's accept never arrives:
6. **Assert C:** C's side stays `pending` for B's status
7. **Assert:** No contact created on C until both statuses converge
8. Eventually B's accept is retried or drains from inbox
9. **Assert:** Contact created after both accepts received

### I-9.4 Introduction Sent Over Relay (No Direct Connection)
1. A has no direct P2P connection to B (different network, relay only)
2. A sends intro → direct send fails → falls back to relay inbox
3. **Assert:** Intro stored in B's relay inbox
4. B polls inbox → receives intro
5. **Assert:** Full intro flow works identically via relay path

### I-9.5 Network Partition Between B and C
1. A introduces B to C
2. B and C can both reach A but NOT each other
3. B accepts → accept reaches A but not C
4. C accepts → accept reaches A but not B
5. **Assert A:** Both accepts received, A's record shows `mutualAccepted`
6. **Assert B:** C's accept eventually arrives (via A's relay? or direct inbox?)
7. **Assert C:** B's accept eventually arrives
8. **Assert:** Contacts created on both once cross-accepts delivered

---

## I-10. Expiry Scenarios

### I-10.1 Both Parties Ignore for 30+ Days
1. A introduces B to C
2. Neither B nor C responds
3. 30 days pass
4. **Assert:** `deriveStatus()` returns `expired`
5. **Assert B:** Intro card in Orbit shows expired state (no accept/pass buttons)
6. **Assert:** `countPendingIntroductions()` returns 0 (expired not counted)

### I-10.2 One Accepts, Other Ignores for 30+ Days
1. A introduces B to C
2. B accepts
3. C never responds
4. 30 days pass
5. **Assert:** Overall status = `expired` (still has one `pending`)
6. **Assert:** No contact created
7. **Assert B:** B sees expired intro (their accept was wasted)

### I-10.3 Accept After Expiry
1. A introduces B to C
2. 30+ days pass with no response
3. C opens app, sees expired intro
4. C tries to accept
5. **Assert:** UI should prevent accept on expired intro
6. **Assert:** Even if accept sent, no `mutualAccepted` triggers

### I-10.4 Expiry Cleanup on App Startup
1. B has 3 pending intros: one 10 days old, one 25 days old, one 35 days old
2. B opens app → `expireOldIntroductions()` runs
3. **Assert:** 35-day intro marked `expired`
4. **Assert:** 10-day and 25-day intros still `pending`
5. **Assert:** Badge shows 2 (not 3)

---

## I-11. Race Conditions

### I-11.1 Double-Tap Accept
1. A introduces B to C
2. B taps Accept twice rapidly
3. **Assert:** Only one accept message sent
4. **Assert:** No duplicate status updates
5. **Assert:** `recipientStatus` set to `accepted` once (idempotent overwrite is fine)

### I-11.2 Accept and Pass Simultaneously
1. A introduces B to C
2. B rapidly taps Accept then Pass (or vice versa) before UI updates
3. **Assert:** One action wins (last-write-wins on status)
4. **Assert:** No crash, no contradictory state

### I-11.3 Accept While Offline — Then Network Returns
1. A introduces B to C
2. B taps Accept while offline
3. **Assert B:** Local status updates to `accepted`
4. **Assert:** Accept message queued but not delivered
5. Network returns
6. **Assert:** Accept message delivered to A and C
7. C accepts → `mutualAccepted` → contact created

### I-11.4 Two Intros for Same Pair — Accept One, Other Auto-Detects
1. A introduces B to C (intro #1)
2. D introduces B to C (intro #2)
3. B and C both accept intro #1 → become contacts
4. B receives intro #2 from D
5. **Assert:** Intro #2 detects B and C already connected → `alreadyConnected`

### I-11.5 Introduction During App Background/Foreground Cycle
1. B backgrounds the app
2. A sends intro to B
3. B foregrounds the app
4. **Assert:** Intro arrives (via push handler or inbox drain)
5. **Assert:** Orbit updates with new pending intro
6. **Assert:** No duplicate intros from both push + inbox paths

### I-11.6 Contact Deletion Racing with Mutual Acceptance
1. A introduces B to C
2. B and C both accept → `mutualAccepted`
3. Simultaneously, B deletes the contact with A (introducer)
4. **Assert:** Contact creation for C still works (doesn't depend on A being a contact)
5. **Assert:** System message may reference A even though A is no longer B's contact

### I-11.7 Introduction Arrives During DB Migration
1. B's app is upgrading (DB migration running)
2. A sends intro to B
3. Intro arrives via P2P stream while migration is in progress
4. **Assert:** Either message is queued until migration completes, or fails gracefully
5. **Assert:** No crash, no data corruption
6. After migration → **Assert:** Intro eventually processed

### I-11.8 Concurrent Introductions for Same Recipient
1. A introduces B to C
2. D introduces B to E
3. Both arrive at B within 100ms
4. **Assert B:** Both intros saved as separate records
5. **Assert B:** Orbit shows both, grouped by introducer
6. **Assert:** No cross-contamination (C's keys don't leak to E's record)

---

## I-12. Edge Cases & Boundary Conditions

### I-12.1 Self-Introduction Attempt
1. A tries to introduce B to B (same person)
2. **Assert:** UI prevents this (Friend Picker should not allow selecting B as both parties)
3. If it somehow bypasses UI → **Assert:** No crash, intro either rejected or creates harmless record

### I-12.2 Introduction to a Contact You're About to Delete
1. A starts introducing B to C
2. While intro is in-flight, A deletes B as a contact
3. **Assert:** Intro already sent — B and C can still complete the flow
4. **Assert A:** Local intro record may have dangling reference to deleted contact

### I-12.3 Introduction with Empty/Null Username
1. C has no username set (edge case during identity setup)
2. A introduces B to C
3. **Assert B:** Intro shows C's peer ID or placeholder (no crash)
4. **Assert:** Accept/pass still functional

### I-12.4 Very Long Username in Introduction
1. C has a 200-character username
2. A introduces B to C
3. **Assert:** Intro payload sends full username
4. **Assert B:** Orbit card renders without overflow/crash

### I-12.5 Introducer Has No ML-KEM Key
1. A (introducer) has no ML-KEM key (very old client)
2. A introduces B to C
3. **Assert:** Payload includes A's EC public key but null ML-KEM key
4. **Assert:** B and C can still exchange ML-KEM keys (from each other's fields in payload)
5. **Assert:** Mutual acceptance creates contacts with correct keys

### I-12.6 PendingIntroductionResponse Never Replayed
1. C accepts intro that A sent — but A's 'send' never reaches B
2. C's accept stored as PendingIntroductionResponse on B
3. **Assert:** Pending response sits in DB indefinitely
4. **Assert:** No memory leak, no performance degradation
5. **Assert:** If intro arrives months later, response is replayed correctly

### I-12.7 Avatar Download After Mutual Acceptance
1. A introduces B to C → both accept → contacts created
2. **Assert B:** Avatar download fires for C (fire-and-forget)
3. If download fails → **Assert:** Retry once after 5 seconds
4. If retry also fails → **Assert:** No crash, C's contact shows default avatar
5. **Assert:** Avatar download does NOT block contact creation

### I-12.8 Introduce Someone Who Then Changes Username
1. A introduces B to C (C's username is "Charlie")
2. C changes username to "Charles" before B accepts
3. B accepts (still sees "Charlie" from intro payload)
4. C accepts → mutual acceptance → contact created
5. **Assert B:** C's contact username is "Charlie" (from intro payload at time of send)
6. **Assert:** Username may update later via separate contact update mechanism

---

## I-13. Observability Checklist for Intro Tests

For each test, verify these flow events in device logs:

**Send Path (A's device):**
- [ ] `SEND_INTRODUCTIONS_START`
- [ ] `SEND_INTRODUCTION_SENT` (one per friend)
- [ ] `SEND_INTRODUCTIONS_DONE`

**Receive Path (B/C's device):**
- [ ] `INTRO_LISTENER_MESSAGE_RECEIVED`
- [ ] `HANDLE_INCOMING_INTRO_SAVED` (new intro)
- [ ] OR `HANDLE_INCOMING_INTRO_ALREADY_EXISTS` (duplicate)
- [ ] OR `HANDLE_INCOMING_INTRO_ALREADY_CONNECTED`
- [ ] `INTRO_LISTENER_NEW_INTRO` (stream broadcast)

**Accept/Pass Path:**
- [ ] `ACCEPT_INTRO_START` / `PASS_INTRO_START`
- [ ] `ACCEPT_INTRO_DONE` / `PASS_INTRO_DONE`

**Deferred Response Path:**
- [ ] `HANDLE_INCOMING_INTRO_RESPONSE_DEFERRED`
- [ ] `HANDLE_INCOMING_INTRO_REPLAY_PENDING_RESPONSES_START`
- [ ] `HANDLE_INCOMING_INTRO_REPLAY_PENDING_RESPONSES_SUCCESS`

**Mutual Acceptance Path:**
- [ ] `INTRO_MUTUAL_ACCEPTANCE`
- [ ] `MUTUAL_ACCEPTANCE_CONTACT_CREATED`
- [ ] `INSERT_INTRO_SYSTEM_MESSAGE`

**Error Indicators (should NOT appear in happy path):**
- [ ] `INTRO_LISTENER_DECRYPT_FAILED`
- [ ] `INTRO_LISTENER_PARSE_FAILED`
- [ ] `INTRO_LISTENER_BLOCKED_REJECT`
- [ ] `ACCEPT_INTRO_NOT_FOUND`
