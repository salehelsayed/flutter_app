# Libp2p Messaging Test Matrix for 1:1 and Group Messaging with Media Coverage


## Scope

This file covers **direct 1:1 messaging** and **group messaging** for the supported content types:
- **Text**
- **Image**
- **Video**
- **Voice message**

It keeps the same automation-layer approach you approved: do **not** force every journey into every test layer, but do make sure each meaningful journey is covered in the right layer.

## Actors

- **A** = primary sender, direct-chat initiator, or group admin
- **B** = direct-chat peer or regular group member
- **C** = third group member or the member being removed and later re-added
- **D** = newly added group member
- **X** = unauthorized or non-member peer

## Priority guide

- **P0** = release-blocking; core delivery, permissions, media correctness, security, and data integrity
- **P1** = important; should be covered before broad rollout
- **P2** = optional or feature-dependent; cover if the feature exists

## Media coverage model

### Media types in scope
- **Text**
- **Image**
- **Video**
- **Voice**

### How to read the `Media Types` column
- **Text**, **Image**, **Video**, or **Voice** means the journey is specific to that content type.
- **Image / Video / Voice** means the journey should be exercised for each supported non-text media type.
- **All** means the journey affects text and all supported media types.

### Media-specific expectations
- **Text**: supports normal text, long text, emoji, multiline content, and special characters.
- **Image**: send, receive, preview, download/open, and integrity of the stored media object.
- **Video**: send, receive, thumbnail/duration visibility if supported, download/open/playback, and integrity of the stored media object.
- **Voice**: record, send, receive, playback, duration integrity, and interruption-safe state handling.

### Important rule for media coverage
Because **text, image, video, and voice are all shipping features**, keep at least one **positive happy-path smoke test** for each supported type in:
- **1:1 messaging**
- **group messaging**

That keeps media coverage visible in release gates without forcing every media edge case into smoke.

## Coverage policy used in this matrix

### Coverage legend
- **Required** = should exist before you treat the journey as production-ready.
- **Recommended** = high-value coverage, but not mandatory for every release gate.
- **N/A** = do not force this layer for this journey.

### Rules

**Unit**  
Use for logic-heavy pieces:
- role checks
- identity checks
- dedupe
- replay protection
- ordering
- epoch/key rotation
- notification suppression after removal or block
- unread counter logic
- media validation such as type, size, and duration
- state transitions such as `removed -> rejoined`, `sending -> failed`, and `recording -> sent`

**Integration**  
Use for most journeys:
- send/receive
- add/remove member
- promote admin
- re-invite
- notification behavior
- media upload/download handoff
- metadata sync

**Smoke**  
Keep this small and release-blocking:
- 1:1 conversation bootstrap
- 1:1 text send/receive
- one happy-path send/receive for image, video, and voice in 1:1
- create group
- group text fan-out
- one happy-path fan-out for image, video, and voice in group
- add member
- remove member
- removed member blocked
- re-invite works
- admin promotion works

**Fake Network**  
Use where network behavior is the main risk:
- retries
- duplicates
- offline recipient
- reconnect
- relay/store-and-forward
- partition healing
- upload/download interruption
- large media transfer timing
- removal boundary
- queued delivery after removal
- concurrent admin changes

**2-party E2E (2 of 3 simulators)**  
Use for direct-message user-visible flows:
- A sends to B
- B receives the right content
- media preview/playback works
- notification and deep-link behavior
- blocked peer behavior if supported

**3-party E2E (3 simulators)**  
Use for group user-visible flows:
- A sends and B/C receive
- A removes C
- C stops receiving and sending
- A re-invites C
- B becomes admin
- notification deep-link behavior
- member list and role badges stay in sync

## Matrix interpretation

- **Integration** is marked **Required** for nearly all rows because every row here is a multi-component behavior.
- Rows marked **P2** are optional only if the product feature itself is optional. If the feature exists in your app, the row is in scope.
- Rows that require malformed frames, forged senders, or raw protocol injection often have **Recommended** E2E rather than **Required** E2E because they are better proven with integration plus fake-network or debug-client tooling.
- For generic rows marked **All**, you do not need to explode the test count blindly. Keep explicit happy-path coverage for every supported type, then use representative media variants for shared transport/state rows unless your implementation diverges by type.

## Explicit media coverage map

| Scope | Text happy path | Image happy path | Video happy path | Voice happy path | Offline media | Media retry |
|---|---|---|---|---|---|---|
| 1:1 | DM-002 | DM-015 | DM-016 | DM-017 | DM-018 | DM-019 |
| Group | GM-003 | GM-016 | GM-017 | GM-018 | GM-019 | GM-020 |

## Direct 1:1 Messaging

| Test ID | Scenario | Media Types | Preconditions | Steps | Expected Result | Priority | Unit | Integration | Smoke | Fake Network | 2-party E2E (2 of 3 simulators) | Notes |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| DM-001 | Open or bootstrap 1:1 conversation | All | A and B are authenticated, discoverable, and allowed to chat. | 1. A opens a chat with B or sends the first message. 2. B syncs the thread. | A and B resolve the same direct thread or peer conversation; bootstrap happens once without duplicate threads. | P0 | Recommended | Required | Required | N/A | Required | If your product creates the thread only on first send, assert that behavior explicitly. |
| DM-002 | Online text send/receive | Text | A and B are online in the same direct thread. | 1. A sends a text message to B. | B receives the text once and A sees a clean sent state. | P0 | Recommended | Required | Required | Recommended | Required |  |
| DM-003 | Exactly-once display | All | A and B are online; dedupe is enabled. | 1. A sends one message. 2. Observe both timelines. | The message appears once in each timeline; no duplicate UI row or duplicate unread increment appears. | P0 | Required | Required | N/A | Required | Required |  |
| DM-004 | Sequential same-sender ordering | All | A and B are online. | 1. A sends M1 and then M2 in that order. | B renders M1 before M2 according to the product ordering rule. | P0 | Required | Required | N/A | Required | Required | Use both text-only and mixed-media variants if ordering code differs. |
| DM-005 | Simultaneous send / crossed messages | Text | A and B are online. | 1. A and B send messages at nearly the same time. | Both messages arrive and neither is lost, merged incorrectly, or duplicated. | P0 | Recommended | Required | N/A | Required | Required |  |
| DM-006 | Text retry without duplicates | Text | Connectivity is unstable; dedupe is enabled. | 1. A sends a text message. 2. A retries after timeout or reconnect. | B still sees one text message and sender state resolves without a ghost duplicate. | P0 | Required | Required | N/A | Required | Recommended |  |
| DM-007 | Offline recipient receives later | Text | B is offline; A is online. | 1. A sends a text message. 2. B reconnects later. | B receives the message once after reconnect or store-and-forward. | P0 | Recommended | Required | Recommended | Required | Required |  |
| DM-008 | Background notification for supported message types | All | B's app is backgrounded and notifications are enabled. | 1. A sends text, image, video, and voice messages in separate runs. | B gets exactly one notification per message, and the notification represents the content type correctly. | P0 | Recommended | Required | Recommended | N/A | Required | Useful to assert type-specific copy such as photo/video/voice labels if your UI shows them. |
| DM-009 | Notification deep link opens the correct 1:1 thread | All | B has received a direct-message notification. | 1. B taps the notification. | The app opens the correct direct thread and lands on the correct message context. | P1 | Required | Required | N/A | N/A | Required |  |
| DM-010 | App restart recovery | All | The direct thread contains recent text and media messages. | 1. Exchange messages. 2. Force close the app. 3. Reopen the app. | History reloads correctly, recent media remains resolvable, and unread state stays consistent. | P0 | Recommended | Required | N/A | N/A | Required |  |
| DM-011 | Sender disconnected behavior | All | A is disconnected or loses connection during send. | 1. A attempts to send a message while disconnecting or offline. | The app either queues correctly or fails clearly; it does not show a false sent state. | P0 | Required | Required | N/A | Required | Recommended |  |
| DM-012 | Mixed delivery paths | All | The harness can force direct delivery for one run and relay or store-and-forward for another. | 1. A sends the same style of message over different transport paths in separate runs. | B receives the message once and content integrity is preserved regardless of path. | P1 | Recommended | Required | N/A | Required | Recommended |  |
| DM-013 | Network partition and reconnect | All | A and B are temporarily partitioned by network conditions. | 1. Send while partitioned according to supported queueing rules. 2. Heal the partition. | Delivery, retries, and final state converge according to retention and queueing rules. | P1 | Recommended | Required | N/A | Required | Recommended |  |
| DM-014 | Text special characters and long content | Text | A and B are online. | 1. A sends long text, emoji, multiline text, and special characters. | B renders and stores the content correctly without truncation or corruption beyond the defined product limit. | P1 | Recommended | Required | N/A | N/A | Required |  |
| DM-015 | Image send/receive and preview | Image | A and B are online; image sending is supported. | 1. A sends an image. 2. B opens the preview. | B receives the image once, preview works, and the stored media object opens correctly. | P0 | Recommended | Required | Required | Recommended | Required | Use at least one small and one larger image sample in automation sets. |
| DM-016 | Video send/receive, open, and playback | Video | A and B are online; video sending is supported. | 1. A sends a video. 2. B opens or plays the video. | B receives the video once, thumbnail or duration metadata appears if supported, and playback works after fetch or download. | P0 | Recommended | Required | Required | Recommended | Required | Use representative small and larger video samples. |
| DM-017 | Voice message record, send, receive, and playback | Voice | A can record audio; A and B are online. | 1. A records a voice message. 2. A sends it. 3. B plays it. | B receives the voice message once and playback duration matches the sent clip within product tolerance. | P0 | Required | Required | Required | Recommended | Required | Include a short clip and a longer clip if duration handling differs. |
| DM-018 | Offline delivery for non-text media | Image / Video / Voice | B is offline; media sending is supported. | 1. A sends image, video, and voice messages in separate runs. 2. B reconnects later. | B receives each message once after reconnect, and media remains fetchable and playable or viewable. | P0 | Recommended | Required | N/A | Required | Required |  |
| DM-019 | Media retry without duplicates | Image / Video / Voice | Connectivity is unstable during media transfer. | 1. A sends media. 2. Interrupt transfer or acknowledgement. 3. Retry. | B gets one logical message and one final usable media object; no duplicate timeline entries remain. | P0 | Required | Required | N/A | Required | Recommended |  |
| DM-020 | Failed or canceled media send leaves no ghost message | Image / Video / Voice | A can cancel media send or a send can fail mid-transfer. | 1. Start sending media. 2. Cancel it or force failure. | The thread shows a clear failed or canceled state and does not leave a fake successful message. | P1 | Required | Required | N/A | Recommended | Recommended |  |
| DM-021 | Size, type, and duration validation | Image / Video / Voice | The app has defined size, type, or duration limits. | 1. Attempt to send unsupported or oversized media, or an over-limit voice duration if applicable. | The app rejects the send cleanly with a correct error and does not create a broken thread entry. | P1 | Required | Required | N/A | N/A | Recommended |  |
| DM-022 | Permission-denied capture flow if supported | Image / Video / Voice | In-app media capture or recording is supported. | 1. Deny camera, gallery, file, or microphone permission as relevant. 2. Attempt capture or record. | The app shows a clear, recoverable error and does not create a broken media message. | P1 | Recommended | Required | N/A | N/A | Recommended |  |
| DM-023 | Unknown sender or spoofed identity is rejected | All | The harness can inject or simulate a forged direct sender. | 1. Inject a message that claims to be from B but fails identity validation. | The message is rejected and no UI entry, notification, or unread increment appears. | P0 | Required | Required | N/A | Required | Recommended |  |
| DM-024 | Tampered message or media blob is rejected | All | The harness can tamper with ciphertext, signature, envelope, or media content hash. | 1. Deliver a tampered message or tampered media reference. | The client rejects it and does not render a valid message or playable media object. | P0 | Required | Required | N/A | Required | N/A | Prefer integration plus malformed-frame injection over plain UI E2E. |
| DM-025 | Replay protection | All | A previously valid message exists in history. | 1. Replay the same old envelope or message ID later. | The replay is not treated as a new message; no duplicate entry or duplicate notification appears. | P0 | Required | Required | N/A | Required | Recommended |  |
| DM-026 | Duplicate-path dedupe | All | The same valid message can arrive through more than one path. | 1. Deliver the same message through two paths. | Only one logical message remains in the thread and state updates exactly once. | P0 | Required | Required | N/A | Required | Recommended |  |
| DM-027 | Store-and-forward expiry or TTL behavior | All | Offline retention or expiry rules exist. | 1. Keep B offline beyond retention or TTL. 2. Send messages during that period. 3. Reconnect B. | Behavior matches the defined retention rule and fails clearly when data has expired. | P1 | Recommended | Required | N/A | Required | Recommended |  |
| DM-028 | Read receipt accuracy if supported | All | Read receipts are enabled. | 1. Exchange text and media messages. 2. Open them on the recipient side. | Receipt state changes once, maps to the correct message, and does not regress incorrectly. | P2 | Required | Required | N/A | N/A | Recommended |  |
| DM-029 | Typing indicator if supported | Text | Typing indicators are enabled. | 1. A starts and stops typing. 2. Disconnect and reconnect mid-typing if relevant. | B sees correct indicator transitions without stale stuck-typing state. | P2 | Recommended | Required | N/A | Recommended | Recommended |  |
| DM-030 | Blocked peer cannot send, receive, or notify if supported | All | Blocking is supported in direct messaging. | 1. A blocks B. 2. B attempts to send messages. 3. Unblock and retry if the feature exists. | Blocked behavior matches the product rule; unauthorized delivery or notification does not leak through. | P1 | Required | Required | N/A | Recommended | Required |  |
| DM-031 | Edit or delete message if supported | All | Edit or delete is supported. | 1. Edit or delete sent text and media messages according to feature scope. | State converges correctly across devices and no stale previews or playback entries remain. | P2 | Required | Required | N/A | Recommended | Recommended |  |

## Group Messaging

| Test ID | Scenario | Media Types | Preconditions | Steps | Expected Result | Priority | Unit | Integration | Smoke | Fake Network | 3-party E2E (3 simulators) | Notes |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| GM-001 | Create group successfully | N/A | A is allowed to create groups; B and C are valid peers. | 1. A creates a group with B and C. 2. B and C sync the group state. | All members resolve the same group ID, member list, and admin list. | P0 | Recommended | Required | Required | N/A | Required |  |
| GM-002 | Create or add with offline member bootstrap | N/A | C is offline during group creation or add. | 1. A creates the group or adds C while C is offline. 2. C reconnects. | C receives the group state or invite on reconnect and can participate according to product rules. | P1 | Recommended | Required | N/A | Required | Required |  |
| GM-003 | Online text fan-out | Text | A, B, and C are online in the same group. | 1. A sends a text message to the group. | B and C each receive the text once and A sees clean send state. | P0 | Recommended | Required | Required | Recommended | Required |  |
| GM-004 | Exactly-once display | All | A, B, and C are online; dedupe is enabled. | 1. A sends one group message. 2. Observe all timelines. | Each client shows one logical copy and state updates only once. | P0 | Required | Required | N/A | Required | Required |  |
| GM-005 | Sequential same-sender ordering | All | A, B, and C are online. | 1. A sends M1 and then M2 in that order. | Recipients render M1 before M2 according to the product ordering rule. | P0 | Required | Required | N/A | Required | Required |  |
| GM-006 | Simultaneous send | Text | A, B, and C are online. | 1. A and B send at nearly the same time. | C receives both messages and neither is lost or merged incorrectly. | P0 | Recommended | Required | N/A | Required | Required |  |
| GM-007 | Text retry without duplicates | Text | Connectivity is unstable; dedupe is enabled. | 1. A sends a text message. 2. Retry after timeout or reconnect. | Recipients still see one logical message and sender state resolves cleanly. | P0 | Required | Required | N/A | Required | Recommended |  |
| GM-008 | Offline recipient receives later | Text | C is offline; A and B are online. | 1. A sends a text message. 2. C reconnects later. | B receives immediately and C receives once after reconnect or store-and-forward. | P0 | Recommended | Required | Recommended | Required | Required |  |
| GM-009 | Background notification for supported message types | All | B's app is backgrounded and notifications are enabled. | 1. A sends text, image, video, and voice messages in separate runs. | B gets one correct notification per message and the content type is represented correctly. | P0 | Recommended | Required | Recommended | N/A | Required |  |
| GM-010 | Notification deep link opens the correct group | All | B has received a group notification. | 1. B taps the notification. | The app opens the correct group and lands on the correct message context. | P1 | Required | Required | N/A | N/A | Required |  |
| GM-011 | App restart recovery | All | The group contains recent text and media messages. | 1. Exchange messages. 2. Force close the app. 3. Reopen the app. | History, last-message preview, and unread state reload correctly. | P0 | Recommended | Required | N/A | N/A | Required |  |
| GM-012 | Mixed delivery paths | All | The harness can force direct delivery for one member and relay or store-and-forward for another. | 1. A sends the same class of message across mixed paths in separate runs. | Members still receive one logical message with correct content integrity. | P1 | Recommended | Required | N/A | Required | Recommended |  |
| GM-013 | Partial fan-out | All | One group member is temporarily unreachable. | 1. A sends a group message to a 3+ member group. | Reachable members receive immediately; unreachable members follow the defined later-delivery rule; send is not globally marked failed because one member is unavailable. | P0 | Recommended | Required | N/A | Required | Recommended |  |
| GM-014 | Sender disconnected behavior | All | A disconnects during send. | 1. A attempts to send while disconnecting or offline. | The app queues correctly or fails clearly; no false sent state remains. | P0 | Required | Required | N/A | Required | Recommended |  |
| GM-015 | Network partition and reconnect | All | The group is partitioned by temporary network conditions. | 1. Send during the partition according to supported queueing rules. 2. Heal the partition. | Messages, retries, and final state converge according to the defined retention and ordering rules. | P1 | Recommended | Required | N/A | Required | Recommended |  |
| GM-016 | Image fan-out | Image | A, B, and C are online; image sending is supported. | 1. A sends an image to the group. 2. B and C open the preview. | Each recipient gets one image message, preview works, and the stored media object opens correctly. | P0 | Recommended | Required | Required | Recommended | Required |  |
| GM-017 | Video fan-out | Video | A, B, and C are online; video sending is supported. | 1. A sends a video to the group. 2. B and C open or play it. | Each recipient gets one video message; thumbnail or duration appears if supported; playback works after fetch or download. | P0 | Recommended | Required | Required | Recommended | Required |  |
| GM-018 | Voice message fan-out | Voice | A can record audio; A, B, and C are online. | 1. A records a voice message. 2. A sends it. 3. B and C play it. | Each recipient gets one voice message and playback duration matches the sent clip within product tolerance. | P0 | Required | Required | Required | Recommended | Required |  |
| GM-019 | Offline delivery for non-text media | Image / Video / Voice | C is offline; A and B are online. | 1. A sends image, video, and voice messages in separate runs. 2. C reconnects later. | C receives the messages once after reconnect and media remains fetchable and playable or viewable. | P0 | Recommended | Required | N/A | Required | Required |  |
| GM-020 | Media retry without duplicates | Image / Video / Voice | Connectivity is unstable during media transfer. | 1. A sends media. 2. Interrupt transfer or acknowledgement. 3. Retry. | Recipients end with one logical message and one final usable media object; no duplicate timeline entries remain. | P0 | Required | Required | N/A | Required | Recommended |  |
| GM-021 | Failed or canceled media send leaves no ghost group message | Image / Video / Voice | A can cancel media send or a send can fail mid-transfer. | 1. Start sending media. 2. Cancel it or force failure. | The group shows a clear failed or canceled state and does not leave a fake successful group message. | P1 | Required | Required | N/A | Recommended | Recommended |  |
| GM-022 | Image preview and download integrity across members | Image | A, B, and C are online. | 1. A sends an image. 2. B and C preview and open it after fetch or download. | All recipients see the same final image content without corruption or wrong object mapping. | P1 | Recommended | Required | N/A | Recommended | Required |  |
| GM-023 | Video thumbnail, download, and playback integrity across members | Video | A, B, and C are online. | 1. A sends a video. 2. B and C download or play it. | All recipients see the correct video object, metadata if supported, and successful playback. | P1 | Recommended | Required | N/A | Recommended | Required |  |
| GM-024 | Voice playback state and duration integrity across members | Voice | A, B, and C are online. | 1. A sends a voice message. 2. B and C play it. | Playback state, duration, and final stored object remain consistent across members. | P1 | Required | Required | N/A | Recommended | Required |  |
| GM-025 | Size, type, and duration validation | Image / Video / Voice | The app has defined size, type, or duration limits. | 1. Attempt to send unsupported or oversized media, or an over-limit voice duration if applicable. | The app rejects the send cleanly and does not create a broken group message. | P1 | Required | Required | N/A | N/A | Recommended |  |
| GM-026 | Permission-denied capture flow if supported | Image / Video / Voice | In-app capture or recording is supported. | 1. Deny camera, gallery, file, or microphone permission as relevant. 2. Attempt capture or record. | The app shows a clear, recoverable error and does not create a broken group message. | P1 | Recommended | Required | N/A | N/A | Recommended |  |
| GM-027 | Only admin can add members | N/A | A is admin; B is non-admin; D is not in the group. | 1. A attempts to add D. 2. B attempts to add D in a separate run. | Admin add succeeds; non-admin add is blocked in UI and rejected by protocol or state validation. | P0 | Required | Required | Required | N/A | Required |  |
| GM-028 | Add member success and member list sync | N/A | A is admin; D is not yet a member. | 1. A adds D. 2. All members refresh or sync state. | D joins successfully and all current members see the same member list and role badges. | P0 | Recommended | Required | Required | Recommended | Required |  |
| GM-029 | Only admin can remove members | N/A | A is admin; B is non-admin; C is a member. | 1. A attempts to remove C. 2. B attempts the same in a separate run. | Admin remove succeeds; non-admin remove is blocked in UI and rejected by protocol or state validation. | P0 | Required | Required | N/A | Recommended | Recommended |  |
| GM-030 | Remove member confirmation and cancel path | N/A | A is admin; C is a member. | 1. A chooses remove member. 2. Cancel once. 3. Confirm in a second run. | Cancel keeps membership unchanged; confirm removes C and shows the correct warning copy. | P0 | Required | Required | Recommended | N/A | Required |  |
| GM-031 | Removed member loses send permission | All | C has been removed from the group. | 1. C attempts to send text, image, video, and voice messages in separate runs. | Post-removal sends are rejected for all supported content types. | P0 | Required | Required | Required | Required | Required |  |
| GM-032 | Removed member loses receive permission | All | C has been removed from the group; other members keep chatting. | 1. A or B sends new text and media messages after removal. | C does not receive any post-removal group messages for any supported content type. | P0 | Required | Required | Required | Required | Required |  |
| GM-033 | Removed member loses notifications | All | C has been removed and notifications had previously been enabled. | 1. A or B sends new text and media messages after removal. | C does not receive new group notifications after removal becomes effective. | P0 | Required | Required | N/A | Recommended | Required |  |
| GM-034 | Removed member is notified of removal | N/A | C is removed by an admin. | 1. C reconnects or opens the group after removal. | C sees a clear removed-state message and the input becomes unavailable according to product rules. | P0 | Recommended | Required | Recommended | Recommended | Required |  |
| GM-035 | Removed while offline | All | C is offline when A removes C. | 1. A removes C while C is offline. 2. Other members continue chatting. 3. C reconnects later. | C syncs removed state on reconnect and cannot send, receive, or notify for post-removal content. | P1 | Required | Required | N/A | Required | Required |  |
| GM-036 | Removed while typing or sending | All | C is composing or sending while A removes C. | 1. Interleave C's send with A's remove action near the boundary. | Messages after the removal boundary are rejected according to the defined ordering rule. | P0 | Required | Required | N/A | Required | Recommended |  |
| GM-037 | Admin can promote another admin | N/A | A is admin; B is a regular member. | 1. A promotes B to admin. 2. B performs an admin-only action. | B gains admin capability and the group reflects the new role consistently. | P0 | Required | Required | Required | Recommended | Required |  |
| GM-038 | Non-admin cannot self-promote or promote others | N/A | B is non-admin. | 1. B attempts to promote self or another member. | The action is blocked in UI and rejected by protocol or state validation. | P0 | Required | Required | N/A | Recommended | Recommended |  |
| GM-039 | At least one admin remains | N/A | There is exactly one admin in the group. | 1. The last admin attempts to leave or remove self without transferring admin. | The action is blocked until another admin exists or admin rights are transferred. | P0 | Required | Required | Recommended | N/A | Required |  |
| GM-040 | Admin leave flow with multiple admins | N/A | A and B are admins. | 1. A leaves the group. | The group remains healthy with at least one admin and consistent member state across peers. | P1 | Recommended | Required | N/A | Recommended | Required |  |
| GM-041 | Member can leave group | N/A | C is a non-admin member. | 1. C leaves the group. | C can no longer send or receive group content and remaining members see the leave effect according to product rules. | P0 | Recommended | Required | Recommended | Recommended | Required |  |
| GM-042 | Admin can re-invite removed member | N/A | A is admin; C was previously removed. | 1. A adds C back to the group. | Re-invite succeeds and C can bootstrap fresh group state. | P0 | Required | Required | Required | Required | Required |  |
| GM-043 | Non-admin cannot re-invite removed member | N/A | B is non-admin; C was previously removed. | 1. B attempts to add C back. | The action is blocked in UI and rejected by protocol or state validation. | P0 | Required | Required | N/A | Recommended | Recommended |  |
| GM-044 | Rejoined member can send again | All | C has been re-added and completed bootstrap. | 1. C sends text, image, video, and voice messages in separate runs. | Current members receive C's post-rejoin messages normally for each supported content type. | P0 | Required | Required | Required | Required | Required |  |
| GM-045 | Rejoined member can receive again | All | C has been re-added. | 1. A sends new text and media messages after rejoin. | C receives new post-rejoin content for each supported type once. | P0 | Required | Required | Required | Required | Required |  |
| GM-046 | Notifications resume after rejoin | All | C had been removed, then re-added; notifications are enabled. | 1. A sends new text and media messages after rejoin. | C receives notifications again only after rejoin becomes effective. | P1 | Required | Required | N/A | Recommended | Required |  |
| GM-047 | Rejoin clears removed state | N/A | C was previously shown as removed and is now re-added. | 1. C opens the group after successful rejoin. | Removed banners or input locks are cleared and the group is active again. | P0 | Required | Required | N/A | Recommended | Required |  |
| GM-048 | Rejoined member sees current membership and admin state | N/A | C was removed, group state changed, and C was re-added. | 1. C syncs the group after rejoin. | C sees the latest member list, admin list, and current metadata or epoch state. | P0 | Required | Required | N/A | Required | Required |  |
| GM-049 | Removed-period history is not exposed by default | All | C was removed at T1 and re-added at T2; messages exist between T1 and T2. | 1. C rejoins. 2. C attempts to access messages from T1 to T2. | C cannot access removed-period history unless that is an explicit product rule. | P0 | Required | Required | N/A | Required | Required |  |
| GM-050 | UI restriction is not the only restriction | N/A | A is admin; B is non-admin; raw or instrumented client access is available. | 1. B bypasses UI and submits raw privileged actions such as add, remove, or promote. | Unauthorized actions are rejected by protocol or state validation and no peer applies them. | P0 | Required | Required | N/A | Required | Recommended |  |
| GM-051 | Removed member cannot decrypt future messages | All | C was removed; cryptographic group messaging is enabled. | 1. A and B exchange new text and media after C's removal. 2. C captures or receives ciphertext. | C cannot decrypt any future group traffic after removal. | P0 | Required | Required | N/A | Required | Recommended | Use debug hooks or captured ciphertext; plain UI E2E alone is not enough. |
| GM-052 | Group key or epoch rotates on removal | All | Epoch or key rotation is enabled. | 1. A removes C. 2. Members send new messages afterward. | Post-removal messages use a new valid epoch or key state. | P0 | Required | Required | N/A | Required | Recommended |  |
| GM-053 | Group key or epoch updates correctly on re-invite | All | C was removed and later re-added. | 1. A re-adds C. 2. C syncs fresh state. 3. New messages are exchanged. | C receives the current epoch or key state and stale removed credentials are not reused. | P0 | Required | Required | N/A | Required | Recommended |  |
| GM-054 | Unknown or non-member sender is rejected | All | The harness can inject or simulate a forged group sender. | 1. Inject a message from X, a non-member. | Peers reject the message and no UI entry, notification, or unread increment appears. | P0 | Required | Required | N/A | Required | Recommended |  |
| GM-055 | Stale client resync | N/A | One client has stale cached membership or admin state. | 1. Keep one client offline during group changes. 2. Reconnect it later. | The stale client converges to the latest valid state before it can perform privileged actions. | P0 | Required | Required | N/A | Required | Required |  |
| GM-056 | Duplicate-path dedupe | All | The same valid group message can arrive through more than one path. | 1. Deliver the same message through two paths. | Only one logical group message remains and state updates once. | P0 | Required | Required | N/A | Required | Recommended |  |
| GM-057 | Tampered message or media blob is rejected | All | The harness can tamper with ciphertext, signature, envelope, or media content hash. | 1. Deliver a tampered group message or media reference. | Clients reject it and do not render a valid message or playable media object. | P0 | Required | Required | N/A | Required | N/A | Prefer integration plus malformed-frame injection over plain UI E2E. |
| GM-058 | Replay protection | All | A previously valid group message exists in history. | 1. Replay the same old envelope or message ID later. | The replay is not treated as a new message and does not create duplicate entries or notifications. | P0 | Required | Required | N/A | Required | Recommended |  |
| GM-059 | Post-removal store-and-forward cut-off | All | C is removed while peers still have queued messages for delivery. | 1. Queue messages after removal. 2. Attempt delivery to C later. | C cannot receive or decrypt post-removal queued messages of any supported content type. | P0 | Required | Required | N/A | Required | Required | This is one of the most important removal-boundary tests. |
| GM-060 | Membership change ordering vs in-flight messages | All | A removes C around the same time A or B sends new messages. | 1. Interleave removal and message sends near the boundary. | Messages are accepted or rejected according to the defined ordering or epoch rule and all peers converge consistently. | P0 | Required | Required | N/A | Required | Recommended |  |
| GM-061 | Concurrent admin changes converge safely | N/A | A and B are admins. | 1. A and B make different membership or role changes nearly simultaneously. | The group converges deterministically without split-brain member or admin state. | P1 | Required | Required | N/A | Required | Recommended |  |
| GM-062 | Only allowed role can edit group metadata if supported | N/A | Group rename, picture, or description editing is supported. | 1. Admin edits metadata. 2. Non-admin attempts the same in a separate run. | Authorized edits propagate correctly; unauthorized edits are rejected. | P1 | Required | Required | N/A | Recommended | Required |  |
| GM-063 | Mute notifications per group if supported | All | Per-group mute exists. | 1. B mutes the group. 2. A sends text and media messages. | Messages still arrive but notifications do not until mute is lifted. | P1 | Required | Required | N/A | N/A | Required |  |
| GM-064 | Unread count correctness | All | Unread counters are shown for groups. | 1. Send text and media messages. 2. Open, background, and revisit the thread. | Unread counts increment and clear correctly without duplicate increments. | P1 | Required | Required | N/A | Recommended | Required |  |
| GM-065 | Admins-only send mode if supported | All | Announcement-mode or admins-only send mode exists. | 1. Enable admins-only send. 2. Non-admin tries to send text and media. 3. Admin sends normally. | Only admins can send and the restriction applies consistently to all content types. | P2 | Required | Required | N/A | Recommended | Required |  |
| GM-066 | Admin demotion if supported | N/A | Admin demotion exists. | 1. A demotes B. 2. B attempts an admin-only action. | B loses admin capability and the role change propagates consistently. | P2 | Required | Required | N/A | Recommended | Required |  |


## Launch-gate subset for first release or major regression gates

### 1:1 launch gate
These are the highest-value direct-message tests to keep green at all times:
- **DM-001** Open or bootstrap 1:1 conversation
- **DM-002** Online text send/receive
- **DM-007** Offline recipient receives later
- **DM-008** Background notification for supported message types
- **DM-015** Image send/receive and preview
- **DM-016** Video send/receive and playback
- **DM-017** Voice message record, send, receive, and playback
- **DM-018** Offline delivery for non-text media
- **DM-019** Media retry without duplicates
- **DM-023** Unknown sender or spoofed identity is rejected

### Group launch gate
These are the highest-value group tests to keep green at all times:
- **GM-001** Create group successfully
- **GM-003** Online text fan-out
- **GM-016** Image fan-out
- **GM-017** Video fan-out
- **GM-018** Voice message fan-out
- **GM-027** Only admin can add members
- **GM-028** Add member success and member list sync
- **GM-030** Remove member confirmation and cancel path
- **GM-031** Removed member loses send permission
- **GM-032** Removed member loses receive permission
- **GM-037** Admin can promote another admin
- **GM-042** Admin can re-invite removed member
- **GM-044** Rejoined member can send again
- **GM-045** Rejoined member can receive again
- **GM-051** Removed member cannot decrypt future messages
- **GM-052** Group key or epoch rotates on removal
- **GM-053** Group key or epoch updates correctly on re-invite

## Suggested test data pack

Use a stable shared data pack for repeatable automation:
- **Text**: short text, long multiline text, emoji, Arabic or RTL sample, and special characters.
- **Image**: small image, larger image, portrait and landscape variants, and at least one image with metadata or orientation differences.
- **Video**: short clip, larger clip, and one sample near the size limit.
- **Voice**: short clip, longer clip, and one sample near the duration or size limit if you enforce one.

## Final recommendation

For coverage tracking, keep this file as the **source-of-truth test inventory**, and in your implementation tracker add:
- owner
- automation status
- last pass date
- linked test files
- linked bug IDs for known gaps

That will let you see very quickly which journeys are fully protected and which ones still need automation.

