# Introduction Feature — Full Integration Spec

**Feature:** Peer-to-peer friend introductions
**Actors:** User-A (introducer), User-B (new friend, e.g. Lina), User-C/D/E (introduced friends)
**Kitchen screens referenced:** Conv. (1st)-2, Circle 2 (Intros tab)

---

## Design Reference Screenshots

All mockup screenshots are in the `intros-images/` directory. Reference these for exact visual implementation:

| Screenshot | File | Description |
|---|---|---|
| Conversation + Banner | `intros-images/conv.png` | User-A's conversation with Lina showing the "Help Lina meet your circle" banner card, "Make introductions" CTA, "Maybe later" dismiss with footnote, and compose bar at the bottom |
| Friend Picker (empty) | `intros-images/make-intros-1.png` | Bottom sheet with "Who should Lina meet through you?" — no friends selected yet. Shows search bar, privacy note, and scrollable friend list with circle checkboxes |
| Friend Picker (selected) | `intros-images/make-intros-2.png` | Same picker with 3 friends selected (Sarah, Mike, Emma) — green check circles, highlighted rows, and "Introduce (3)" button at the bottom |
| Sent Confirmation | `intros-images/Introduction-sent.png` | Confirmation shown to User-A after sending — checkmark, "Introductions sent", "Lina will see these as 'Introduced by Noor.'", avatar row of introduced friends |
| Intros Tab (User-B) | `intros-images/Intros-tab.png` | Circle 2 screen → Intros tab showing received introductions grouped by sender ("From Noor", "From Kai"), with Accept buttons, "Introduced by [name]" labels, badge count, and the context line "These are people your friends know well. Once you both accept, you can start chatting." |

---

## Overview

When User-A adds a new friend (User-B), the app prompts User-A to introduce User-B to people from their existing circle. User-B receives these introductions and can accept or pass each one individually. User-C (the introduced friend) also receives the introduction and must accept. **No connection is created until both User-B and User-C have accepted the introduction.** This is a mutual-consent model.

This is a **mutual acceptance introduction flow**: User-A introduces User-B to User-C. Both User-B and User-C receive the intro in their Intros tab. Once **both** accept, a connection is created, a "Connected" card appears on the Feed screen for both users, and they appear in each other's Orbit screen (Friends list / Inner Circle).

---

## Data Model

### Introduction Record

```
Introduction {
  id:                 string (UUID)
  introducerId:       string (User-A's peer ID)
  recipientId:        string (User-B's peer ID — the newly added friend)
  introducedId:       string (User-C's peer ID — the person being introduced)
  recipientStatus:    'pending' | 'accepted' | 'passed'    // User-B's response
  introducedStatus:   'pending' | 'accepted' | 'passed'    // User-C's response
  status:             'pending' | 'mutual_accepted' | 'passed' | 'expired'  // derived overall status
  createdAt:          timestamp
  recipientRespondedAt:  timestamp | null
  introducedRespondedAt: timestamp | null
}
```

**Status derivation rules:**
- `status = 'mutual_accepted'` when BOTH `recipientStatus` AND `introducedStatus` are `'accepted'`
- `status = 'passed'` when EITHER side is `'passed'`
- `status = 'expired'` when 30 days pass and `status` is still `'pending'`
- `status = 'pending'` otherwise (waiting for one or both to respond)

### Per-Friendship Metadata

Add to the existing friendship/connection record:

```
FriendshipMeta {
  ...existing fields,
  introsBannerDismissed:  boolean (default false)
  introsSentAt:           timestamp | null
}
```

- `introsBannerDismissed` — set to `true` when User-A taps "Maybe later" OR when auto-dismissed after 3+ messages
- `introsSentAt` — set when User-A sends introductions; prevents the banner from re-appearing

**Data model unit tests:**
- New Introduction record initializes with `recipientStatus: 'pending'`, `introducedStatus: 'pending'`, `status: 'pending'`
- Setting `recipientStatus = 'accepted'` while `introducedStatus = 'pending'` → `status` stays `'pending'`
- Setting `introducedStatus = 'accepted'` while `recipientStatus = 'pending'` → `status` stays `'pending'`
- Setting both to `'accepted'` → `status` becomes `'mutual_accepted'`
- Setting `recipientStatus = 'passed'` (regardless of other side) → `status` becomes `'passed'`
- Setting `introducedStatus = 'passed'` (regardless of other side) → `status` becomes `'passed'`
- Record with `createdAt` older than 30 days and `status = 'pending'` → `status` becomes `'expired'`
- `FriendshipMeta` defaults: `introsBannerDismissed = false`, `introsSentAt = null`

---

## Step-by-Step Implementation

### Step 1: Banner Display Conditions (User-A side)

> **Design reference:** `intros-images/conv.png` — shows the full conversation screen with the banner card

**What to build:**
Logic that determines whether to show the "Help [name] meet your circle" banner card inside the conversation screen.

**Rules — show the banner when ALL are true:**
1. This is User-A's conversation with User-B
2. `introsSentAt` is null (User-A has NOT already sent intros to User-B)
3. `introsBannerDismissed` is false
4. User-A has **>= 1 other active friend** besides User-B (i.e., `friendsList.filter(f => f.id !== userB.id && !f.blocked).length >= 1`)
5. User-B is not blocked
6. The friendship is active (User-B hasn't disconnected or blocked User-A)

**Rules — hide/auto-dismiss the banner:**
- If User-A and User-B exchange **3 or more total messages** (sent + received combined), auto-dismiss the banner and set `introsBannerDismissed = true`
- If User-A blocks User-B, immediately remove the banner
- If User-B disconnects, immediately remove the banner

**Banner position behavior:**
- On the **empty conversation** screen (no messages yet): banner renders inside the empty state, below the "Write the first letter" prompt
- After **first message is sent or received**: banner slides to appear as an inline card within the conversation scroll area, above the message compose area but below actual messages
- After **3+ total messages**: banner auto-dismisses with exit animation

**Files to modify:**
- Conversation screen component (currently `ConversationFirstScreen2.jsx` in kitchen)
- Friendship data store/model

**Unit tests:**
- `showIntroBanner()` returns `true` when all conditions met
- `showIntroBanner()` returns `false` when User-A has 0 other friends
- `showIntroBanner()` returns `false` when `introsSentAt` is set
- `showIntroBanner()` returns `false` when `introsBannerDismissed` is true
- `showIntroBanner()` returns `false` when User-B is blocked
- `showIntroBanner()` returns `false` when friendship is inactive (User-B disconnected)
- Banner renders inside empty state when no messages exist
- Banner moves to inline position (below messages) after first message is sent
- Banner moves to inline position after first message is received
- Banner auto-dismisses when message count reaches 3 (sent + received combined)
- Auto-dismiss sets `introsBannerDismissed = true` in the data store
- Banner removal on block is immediate (no animation delay)

---

### Step 2: "Maybe later" Dismiss Behavior

> **Design reference:** `intros-images/conv.png` — see the "Maybe later" button and footnote "You can always introduce from ⋮ at the top"

**What to build:**
When User-A taps "Maybe later," persist the dismissal and ensure the banner doesn't reappear.

**Behavior:**
1. User-A taps "Maybe later"
2. Banner plays exit animation (slide down + fade, 300ms)
3. Set `introsBannerDismissed = true` on this friendship record
4. Banner never reappears in this conversation

**The card currently reads (already updated in kitchen mockup):**
```
[ Make introductions ]      ← primary CTA
[ Maybe later ]             ← secondary
You can always introduce from ⋮ at the top   ← footnote
```

The overflow menu ( ⋮ ) in the conversation header already contains an "Introduce to your circle" option — this is the re-entry point after dismissal.

**Re-entry via ⋮ menu:**
- The "Introduce to your circle" option in the ⋮ menu should ALWAYS be available (regardless of banner state), as long as:
  - User-A has >= 1 other active friend
  - User-B is not blocked
- Tapping it opens the Friend Picker bottom sheet directly (same as tapping "Make introductions" on the banner)
- If User-A already sent intros previously (`introsSentAt` is set), this option should still work — it allows sending additional introductions to the same person

**Files to modify:**
- Conversation screen component
- Friendship data store

**Unit tests:**
- Tapping "Maybe later" sets `introsBannerDismissed` to `true`
- Banner does not render after dismissal (re-opening conversation)
- Banner exit animation plays before removal (300ms)
- ⋮ menu "Introduce to your circle" option visible when >= 1 other friend exists
- ⋮ menu "Introduce to your circle" option hidden when 0 other friends
- ⋮ menu "Introduce to your circle" option hidden when User-B is blocked
- ⋮ menu "Introduce to your circle" opens the Friend Picker sheet
- ⋮ menu "Introduce to your circle" still works after `introsSentAt` is set (allows sending additional intros)

**Integration tests:**
- Dismiss banner → reopen conversation → banner not shown → tap ⋮ → "Introduce to your circle" → picker opens successfully

---

### Step 3: Friend Picker Bottom Sheet

> **Design reference:** `intros-images/make-intros-1.png` (empty state, no selection) and `intros-images/make-intros-2.png` (3 friends selected, "Introduce (3)" button visible)

**What to build:**
A bottom sheet that lets User-A select which friends to introduce to User-B.

**Behavior:**
1. Opens when User-A taps "Make introductions" (banner) or "Introduce to your circle" ( ⋮ menu)
2. Shows a searchable list of User-A's friends, **excluding User-B** and any friends **already introduced to User-B** in a previous session
3. Each friend row has a checkbox (circle style)
4. Selected friends appear as avatar thumbnails in the send bar at the bottom
5. Send bar shows "Introduce (N)" button, only visible when >= 1 friend is selected
6. Tapping "Introduce (N)" sends the introductions

**Already-introduced filter:**
- Query existing Introduction records where `introducerId = User-A` and `recipientId = User-B`
- Exclude any `introducedId` that already has a record (regardless of status)
- This prevents duplicate introductions

**Privacy note** at top of sheet: "No one is added automatically."

**Files to modify:**
- Friend Picker component (currently `FriendPickerSheet` in kitchen)
- Introduction data store (to check for existing intros)

**Unit tests:**
- User-B is excluded from the pickable list
- Already-introduced friends are excluded from the pickable list
- Blocked friends are excluded from the pickable list
- "Introduce (N)" button shows correct count
- "Introduce (N)" button hidden when 0 selected
- Search filters the list by name
- Search filters the list by username
- Selecting a friend shows green check and highlights the row
- Deselecting a friend reverts to empty circle and removes highlight
- Selecting/deselecting updates the button count correctly
- Picker opens from "Make introductions" banner CTA
- Picker opens from ⋮ menu "Introduce to your circle"
- Picker closes on X button tap
- Picker closes on backdrop tap
- Picker closes on Escape key

---

### Step 4: Sending Introductions (User-A action)

**What to build:**
When User-A confirms the introduction, create Introduction records and notify all parties.

**Behavior:**
1. User-A taps "Introduce (N)" in the picker
2. Close the picker sheet
3. For each selected friend (User-C, User-D, etc.):
   - Create an `Introduction` record with status `pending`
4. Set `introsSentAt = now()` on the User-A ↔ User-B friendship
5. Set `introsBannerDismissed = true` (banner should never reappear)
6. Navigate to the **Sent Confirmation** screen

**Notifications to send (via the app's P2P messaging layer):**
- **To User-B (recipient):** "New introductions from [User-A name]" — single notification regardless of how many people were introduced
- **To each User-C/D/E (introduced friends):** "[User-A name] introduced you to [User-B name]"

**System message in conversation:**
After returning to the conversation from the confirmation screen, insert a **system message bubble** in the chat history:
```
You introduced [N] people to [User-B name] · [date]
```
This is a non-deletable, non-editable system event. It appears as a centered, muted-style bubble (similar to date separators but with text content).

**Files to modify:**
- Introduction data store (create records)
- Notification/messaging layer
- Conversation message store (insert system message)
- Friendship metadata store

**Unit tests:**
- N Introduction records created for N selected friends
- Each record has correct `introducerId`, `recipientId`, `introducedId`
- Each record initializes with `recipientStatus: 'pending'`, `introducedStatus: 'pending'`, `status: 'pending'`
- `introsSentAt` is set on the User-A ↔ User-B friendship
- `introsBannerDismissed` is set to true
- System message is inserted into User-A ↔ User-B conversation history
- System message text matches: "You introduced [N] people to [User-B name] · [date]"
- Notification sent to User-B: "New introductions from [User-A name]"
- Notification sent to each User-C: "[User-A name] introduced you to [User-B name]"
- Picker sheet closes after sending
- Navigation goes to Sent Confirmation screen

**Integration tests:**
- Full flow: open picker → select 3 friends → tap "Introduce (3)" → verify 3 Introduction records created → verify confirmation screen shown → verify system message appears in conversation → verify notifications sent to User-B (1 notification) and each User-C (3 notifications)

---

### Step 5: Sent Confirmation Screen (User-A sees)

> **Design reference:** `intros-images/Introduction-sent.png` — checkmark, "Introductions sent", introducer attribution, avatar row

**What to build:**
A confirmation screen shown to User-A immediately after sending introductions.

**Content:**
- Animated checkmark icon (draw-on SVG animation)
- Title: "[N] introductions sent"
- Subtitle: "[User-B name] will see these as 'Introduced by [User-A name].'"
- Avatar row of the introduced friends (up to 6 shown, overflow as "+N")
- Notification preview section:
  - "To your friends: '[User-A name] introduced you to [User-B name].'"
  - "To [User-B name]: 'New introductions from [User-A name].'"
- Primary CTA: "See what [User-B name] receives" → navigates to the Received Intros screen (preview mode, read-only)
- Secondary CTA: "Back to conversation" → returns to conversation

**Files to modify:**
- Sent Confirmation component (currently `SentConfirmation` in kitchen)

**Unit tests:**
- Correct count displayed in title
- Avatar row renders correct friends (up to 6 + overflow)
- "See what [name] receives" navigates to received view
- "Back to conversation" navigates to conversation

---

### Step 6: Receiving Introductions (User-B / Lina's side)

> **Design reference:** `intros-images/Intros-tab.png` — Circle screen with Intros tab active, showing groups "From Noor" (3 people) and "From Kai" (2 people), Accept buttons, "Introduced by" labels, badge count, and context text at top

**What to build:**
User-B receives introductions and can review them in two places:
1. **Conversation with User-A** — a notification/system message appears
2. **Circle screen → Intros tab** — all pending introductions are listed

#### 6a. Notification & Conversation Entry Point

When introductions arrive for User-B:
- Push notification: "New introductions from [User-A name]"
- Tapping the notification opens the **Intros tab** in the Circle screen
- In the conversation with User-A, a system message appears:
  ```
  [User-A name] introduced [N] people to you
  ```
  Tapping this system message navigates to the Intros tab filtered to User-A's introductions.

#### 6b. Intros Tab (Circle 2 screen)

The Intros tab in the Circle screen shows all pending and resolved introductions, grouped by sender.

**Layout per group:**
```
From [Sender Name]                    [N] people
─────────────────────────────────────────────────
  [Avatar] Friend Name                [Accept] [Pass]
           Introduced by [Sender]
  [Avatar] Friend Name                [Accepted ✓]
           Introduced by [Sender]
```

**Per-introduction actions (applies to both User-B and User-C's Intros tab):**
- **Accept** → Sets the accepting user's status (`recipientStatus` or `introducedStatus`) to `accepted`. Then checks if the **other side has also accepted**:
  - If **both accepted** → `status` becomes `mutual_accepted`. Triggers the **Mutual Acceptance Flow** (see Step 6c below).
  - If **only one accepted so far** → The row shows "Accepted — waiting for [other name]" on the accepting user's side. No connection is created yet.
- **Pass** → Sets the passing user's status to `passed`. Overall `status` becomes `passed`. No notification is sent to anyone. The row visually dims and shows "Passed" label. If the other user had already accepted, they see "Passed by [name]" (without revealing who passed — just that the intro didn't go through).

**Trust/privacy indicator at top of Intros tab:**
- "These are people your friends know well. Once you both accept, you can start chatting."

**Badge on Intros tab:**
- Show count of pending introductions as a badge number on the "Intros" filter button
- When count is 0, no badge

**Incoming intros banner (on "All" tab):**
- When there are pending intros and User-B is viewing the "All" friends list, show a banner:
  ```
  [icon] N introduction(s) from [Sender(s)]    [New]  >
         Review and accept to start chatting
  ```
- Tapping this banner switches to the Intros tab

**Files to modify:**
- Circle screen component (currently `CircleScreen2.jsx` in kitchen)
- Introduction data store (query by `recipientId`)
- Friendship/connection creation logic (on accept)
- Notification layer

**Unit tests:**
- Intros tab shows pending introductions grouped by sender (User-B's view)
- User-C also sees the introduction in their Intros tab (User-C's view, grouped under User-A as sender)
- User-B accepting sets `recipientStatus` to `accepted`
- User-C accepting sets `introducedStatus` to `accepted`
- Single-side accept does NOT create a connection
- Single-side accept shows "Accepted — waiting for [name]" label on the accepting user's side
- Both sides accepting sets `status` to `mutual_accepted`
- Pass changes the passing user's status to `passed` and overall `status` to `passed`
- Pass does NOT create a connection
- Pass does NOT send any notification
- If one side passes after the other accepted, the accepted side sees "Didn't go through" (without revealing who passed)
- Badge count reflects only `pending` introductions (not accepted-waiting or passed)
- Badge hidden when 0 pending
- Incoming intros banner shows on "All" tab when pending count > 0
- Incoming intros banner hidden when pending count = 0
- Tapping the incoming intros banner switches to Intros tab
- Notification tap opens Intros tab in Circle screen
- Tapping system message in conversation navigates to Intros tab
- Context text "These are people your friends know well..." renders at top of Intros tab

**Integration tests:**
- User-A sends 3 intros to User-B → User-B opens Intros tab → sees 3 pending → accepts 1 → verify no connection yet (User-C hasn't accepted), badge shows 2 remaining
- User-B accepts intro from User-C → User-C also accepts → verify mutual acceptance triggers connection flow
- User-B accepts but User-C passes → verify no connection created, User-B sees "Didn't go through"
- User-C receives intro notification → taps notification → Intros tab opens with correct group visible
- User-A sends intros → User-B sees system message in conversation → taps it → navigates to Intros tab

---

### Step 6c: Mutual Acceptance — Connection & Surface in Feed/Orbit

**What to build:**
A mechanism that detects when both User-B and User-C have accepted the same introduction, and triggers the full connection flow.

**When `status` transitions to `mutual_accepted`:**

1. **Create a new friendship/connection** between User-B and User-C
   - The connection record should reference the introduction (`introductionId`) for provenance
   - Set `connectedVia: 'introduction'` and `introducedBy: User-A's peer ID` on the friendship record

2. **Create a new conversation** between User-B and User-C
   - Insert a system message: "You and [other name] are now connected — introduced by [User-A name]"

3. **"Connected" card on the Feed screen** — for BOTH User-B and User-C:
   - A card appears in the Feed (same style as when User-A originally added User-B)
   - Card content: "[Name] — Introduced by [User-A name]"
   - Shows the new friend's avatar and a "Send Message" CTA
   - The card should reference the introducer so both users see who brought them together

4. **Friend appears in Orbit screen** — for BOTH User-B and User-C:
   - The new friend is added to the **Friends list** in the Orbit/Circle screen (same placement logic as any new friend)
   - The friend row in the list should show a subtle "Introduced by [User-A name]" badge/label for context

5. **Notifications:**
   - To User-B: "[User-C name] also accepted! You're now connected."
   - To User-C: "[User-B name] also accepted! You're now connected."
   - To User-A (the introducer): "[User-B name] and [User-C name] are now connected through your introduction." (optional celebratory notification)

6. **Update the Intros tab row** for both User-B and User-C:
   - Status changes from "Accepted — waiting" to a final "Connected ✓" label
   - Optionally, a "Send Message" shortcut appears on the row

**Files to modify:**
- Introduction data store (mutual acceptance detection logic)
- Friendship/connection creation logic
- Conversation creation logic
- Feed screen component (new "Connected via intro" card type)
- Orbit/Circle screen (add friend to list)
- Notification layer

**Unit tests:**
- `mutual_accepted` status triggers connection creation between User-B and User-C
- Connection record has `connectedVia: 'introduction'` and `introducedBy: User-A peer ID` fields
- Connection record references the `introductionId`
- New conversation is created between User-B and User-C
- New conversation contains system message: "You and [name] are now connected — introduced by [User-A name]"
- "Connected" card appears in Feed for User-B with correct friend info
- "Connected" card appears in Feed for User-C with correct friend info
- "Connected" card shows introducer name ("Introduced by [User-A name]")
- "Connected" card has "Send Message" CTA that opens the new conversation
- New friend appears in User-B's Orbit Friends list
- New friend appears in User-C's Orbit Friends list
- Friend row in Orbit shows "Introduced by [User-A name]" label
- Intros tab row updates from "Accepted — waiting" to "Connected ✓" for User-B
- Intros tab row updates from "Accepted — waiting" to "Connected ✓" for User-C
- Notification sent to User-B: "[User-C name] also accepted! You're now connected."
- Notification sent to User-C: "[User-B name] also accepted! You're now connected."
- Notification sent to User-A: "[User-B name] and [User-C name] are now connected through your introduction."
- Concurrent acceptance (both accept within milliseconds): only ONE connection is created (idempotency guard)

**Integration tests:**
- Full mutual acceptance flow: User-A introduces User-B to User-C → User-B accepts → User-C accepts → verify connection created → verify Feed card for both → verify Orbit list updated for both → verify conversation created with system message → verify Intros tab shows "Connected ✓" for both → verify notifications sent to all 3 users
- Order independence: User-C accepts first, then User-B accepts → exact same result (connection, Feed, Orbit, notifications)
- One passes after other accepts: User-B accepts → User-C passes → verify NO connection, NO Feed card, NO Orbit update → User-B's Intros row shows "Didn't go through"
- Multiple introductions: User-A introduces User-B to User-C AND User-D → User-B accepts both → User-C accepts → User-D does not → verify only User-B ↔ User-C connection created, User-B ↔ User-D stays pending

---

### Step 7: System Messages in Conversation History

**What to build:**
System event messages that appear in conversation threads as a permanent record of introductions.

**System message types:**

| Context | Message text | Where it appears |
|---|---|---|
| User-A sends intros | "You introduced [N] people to [User-B name] · [date]" | User-A ↔ User-B conversation |
| User-B receives intros | "[User-A name] introduced [N] people to you" | User-A ↔ User-B conversation (User-B's view) |
| User-B accepts User-C | "You and [User-C name] are now connected · Introduced by [User-A name]" | User-B ↔ User-C conversation (new) |

**System message rendering:**
- Centered text, muted color (similar to date separators but distinct)
- Non-deletable, non-editable
- Tappable where noted (e.g., User-B tapping "introduced N people" navigates to Intros tab)

**Unit tests:**
- System message for "You introduced N people" renders in User-A ↔ User-B conversation (User-A's view)
- System message for "[User-A] introduced N people to you" renders in User-A ↔ User-B conversation (User-B's view)
- System message for "You and [name] are now connected — introduced by [User-A]" renders in User-B ↔ User-C conversation
- System message text includes the correct count, names, and date
- System message renders as centered, muted-style bubble (visually distinct from regular messages)
- System message is not editable
- System message is not deletable
- System message does not have reply/react actions
- Tapping "introduced N people to you" system message navigates to Intros tab
- Non-tappable system messages (e.g., "You introduced...") do not have tap handlers

**Integration tests:**
- Full flow: User-A sends intros → system message appears for User-A → User-B receives → system message appears for User-B → both accept → system message appears in new User-B ↔ User-C conversation → verify all 3 messages have correct text and are in the correct conversations

---

### Step 8: Edge Cases & Guards

**Implement these guard checks throughout the flow:**

| Scenario | Behavior |
|---|---|
| User-A has 0 other friends | Banner not shown. ⋮ menu "Introduce" option hidden. |
| User-A blocks User-B | Banner removed. Pending intros stay as-is (User-B already has them). |
| User-B blocks User-A | Banner removed on User-A's side. User-B's pending intros from User-A remain visible but labeled "Connection unavailable" if User-A is blocked. |
| User-B disconnects (leaves the app / deletes account) | Banner removed. Pending intros from this User-B to others are marked `expired`. |
| User-C (introduced friend) blocks User-B before User-B accepts | The Accept button for that row should show "Unavailable" instead. |
| User-A sends intros, then later sends MORE intros | Allowed. New Introduction records are created. Previously introduced friends are filtered out of the picker. |
| Rapid friend additions (User-A adds 5 people in 10 minutes) | Show the banner only in the **most recently opened** conversation. Do not stack banners across conversations. |
| User-A sends intro, then User-B messages User-A | Banner (if still visible) gracefully moves below the incoming message. |
| Introduction records older than 30 days with status `pending` | Auto-expire: set status to `expired`. Remove from Intros tab. |

**Unit tests:**
- 0 friends: `showIntroBanner()` returns false, ⋮ menu hides "Introduce to your circle"
- User-A blocks User-B: banner removed immediately, pending intros remain accessible to User-B
- User-B blocks User-A: banner removed on User-A side, User-B's intros from User-A show "Connection unavailable" on Accept
- User-B disconnects: banner removed, pending intros where User-B is recipient/introduced are marked `expired`
- User-C blocks User-B before acceptance: Accept button for that intro shows "Unavailable" instead
- Additional intros: User-A can send more intros via ⋮ menu, previously introduced friends filtered out of picker
- Rapid additions: banner shown only in the most recently opened conversation, not stacked across multiple conversations
- Incoming message with banner visible: banner repositions below the message without jarring jump
- 30-day expiration: pending records auto-expire, do not appear in Intros tab, badge count decremented

**Integration tests:**
- Block during pending intro: User-A sends intro → User-A blocks User-B → User-B still sees intro in Intros tab → User-B accepts → accept handler checks User-A block status → shows "Connection unavailable"
- Expiration flow: create intro with `createdAt` = 31 days ago → open Intros tab → intro not shown → verify `status = 'expired'` in data store

---

## Smoke Tests

Run these end-to-end scenarios on the **multi-node CLI harness** (3 nodes, real P2P, no simulator). Each test chains multiple steps and verifies cumulative data store state across all nodes after each step:

1. **Happy path — full cycle with mutual acceptance:**
   User-A adds User-B → sees banner → taps "Make introductions" → selects 2 friends (User-C, User-D) → sends → sees confirmation → goes back to conversation → system message visible → User-B opens Intros tab → sees 2 pending → accepts User-C → User-C also accepts → verify: connection created, "Connected" card on Feed for both User-B and User-C, User-C appears in User-B's Orbit Friends list and vice versa, conversation created between them

2. **Dismiss and re-enter via menu:**
   User-A sees banner → taps "Maybe later" → banner disappears → taps ⋮ → taps "Introduce to your circle" → picker opens → selects 1 friend → sends → confirmation shown

3. **Auto-dismiss after messages:**
   User-A sees banner → sends 1 message → banner moves below message → receives 1 message → sends 1 more → banner auto-dismisses → verify `introsBannerDismissed` is true

4. **No friends to introduce:**
   User-A has only User-B as friend → no banner shown → ⋮ menu does not show "Introduce to your circle"

5. **Block during flow:**
   User-A sees banner → blocks User-B → banner immediately removed → unblocks User-B → banner does NOT reappear (it was dismissed by the block action)

6. **Duplicate prevention:**
   User-A introduces User-C to User-B → later opens ⋮ → "Introduce to your circle" → User-C is NOT in the picker list

7. **User-B passes all intros:**
   User-B receives 3 intros → passes all 3 → Intros tab badge goes to 0 → no connections created → no notifications sent

8. **Expired introductions:**
   Create a pending intro with `createdAt` = 31 days ago → verify it does not appear in User-B's Intros tab → verify its status is `expired`

9. **One-sided accept (no connection yet):**
   User-B accepts intro from User-C → User-C has NOT responded yet → verify NO connection created, NO Feed card, NO Orbit update → User-B sees "Accepted — waiting for [User-C]" → User-C later accepts → verify connection + Feed card + Orbit update now happen

10. **Mutual acceptance surfaces correctly:**
    User-B and User-C both accept → verify "Connected" card appears on Feed for both → verify both appear in each other's Orbit Friends list → verify new conversation has system message "introduced by [User-A]"

11. **Full end-to-end chain (cross-step):**
    User-A opens conversation with User-B → banner appears (Step 1) → taps "Make introductions" (Step 2) → picker opens (Step 3) → selects 3 friends → sends (Step 4) → confirmation shown (Step 5) → goes back → system message in conversation (Step 7) → User-B opens Intros tab → sees 3 pending (Step 6) → accepts User-C → User-C opens their Intros tab → accepts User-B → connection created, Feed card, Orbit update (Step 6c) → both open conversation → system message "introduced by [User-A]" present (Step 7)

---

## Testing Strategy

### Test environments

| Level | Environment | P2P Layer | Speed |
|---|---|---|---|
| **Unit tests** | Single process | **Mocked** — P2P send/receive is stubbed, assertions on payloads only | Fast (ms) |
| **Integration tests** | **Multi-node CLI** — 3 CLI instances (User-A, User-B, User-C) on same machine | **Real** — actual P2P message passing between nodes | Medium (seconds) |
| **Smoke tests** | **Multi-node CLI** — same 3-node setup, but running longer chained scenarios | **Real** — actual P2P message passing between nodes | Medium-slow (seconds) |

**No simulator dependency.** All automated tests run against CLI nodes only. Visual/UI correctness is verified through the kitchen mockups (`intros-images/`) and manual QA — not automated smoke tests. This keeps the test suite stable and deterministic.

Smoke tests differ from integration tests only in **scope**: integration tests verify a single step or interaction between 2-3 nodes, while smoke tests chain multiple steps into full end-to-end scenarios and verify cumulative state across all nodes.

### Multi-node CLI test harness

For integration and smoke tests, spin up 3 CLI nodes in the test runner:

```
Node-A (User-A / Noor):  --peer-id=test-user-a  --data-dir=/tmp/intro-test-a  --port=9001
Node-B (User-B / Lina):  --peer-id=test-user-b  --data-dir=/tmp/intro-test-b  --port=9002
Node-C (User-C / Sarah): --peer-id=test-user-c  --data-dir=/tmp/intro-test-c  --port=9003
```

Each node has its own data store, peer identity, and send/receive handlers. They communicate over the real P2P transport (localhost). The test script sends commands to each node and verifies results across all three.

**Setup:** Before each integration test, establish friendships: A↔B connected, A↔C connected. B and C are NOT connected (that's what introductions will create).

**Teardown:** After each test, wipe all 3 data directories.

### Which tests need multi-node

**Single-node (mocked P2P) — 113 unit tests:**
All unit tests run on a single node with the P2P layer mocked. These test local logic only:
- Data model status derivation
- Banner display conditions (`showIntroBanner()`)
- Dismiss behavior and persistence
- Picker filtering, search, selection UI
- Introduction record creation (local)
- Confirmation screen rendering
- System message rendering
- Edge case guards (local checks)

The P2P mock captures outgoing messages so you can assert:
- "Did Node-A produce the correct introduction payload?"
- "If Node-B received this payload, would the Intros tab render correctly?"

**Multi-node (real P2P) — 14 integration tests + 11 smoke tests:**
These require actual message passing between CLI nodes:

| Test | Nodes involved | What it verifies across nodes |
|---|---|---|
| Step 2: Dismiss → ⋮ re-entry → picker opens | A only | Local flow (can run single-node, but included for completeness) |
| Step 4: Send intros → verify records + notifications | A → B, A → C | B receives notification, C receives notification, Introduction records exist on all nodes |
| Step 6: B opens Intros tab → sees pending intros | A → B | Intros sent by A actually appear on B's Intros tab |
| Step 6: C opens Intros tab → sees pending intros | A → C | Intros sent by A actually appear on C's Intros tab |
| Step 6: B accepts → C's view updates | A, B, C | B's acceptance is propagated; C doesn't see a connection yet |
| Step 6: B accepts, C passes → no connection | A, B, C | Pass propagated; B sees "Didn't go through"; no friendship created on any node |
| Step 6: Notification tap → Intros tab | A → B | Notification arrives on B, tapping opens correct screen |
| Step 6: System message tap → Intros tab | A → B | System message on B's conversation navigates correctly |
| Step 6c: Mutual acceptance → connection | A, B, C | B accepts, C accepts → friendship record exists on BOTH B and C nodes |
| Step 6c: Mutual acceptance → Feed card | A, B, C | "Connected" card appears in Feed on both B and C nodes |
| Step 6c: Mutual acceptance → Orbit list | A, B, C | New friend appears in Orbit on both B and C nodes |
| Step 6c: Mutual acceptance → conversation | B, C | New conversation exists on both nodes with system message |
| Step 6c: Mutual acceptance → notifications | A, B, C | B, C get "You're now connected" notification; A gets "connected through your introduction" |
| Step 6c: Order independence | A, B, C | C accepts first, then B → same result as B-first |
| Step 6c: Concurrent acceptance | A, B, C | Both accept within ms → only 1 connection created (idempotency) |
| Step 7: System messages across conversations | A, B, C | Correct message text in A↔B conversation AND B↔C conversation |
| Step 8: Block during pending | A, B, C | A blocks B → B's accept shows "Connection unavailable" |
| Step 8: Expiration | A, B | 31-day-old intro not visible on B's Intros tab |
| Smoke 1: Full happy path | A, B, C | A sends intros → B receives → B accepts C → C accepts B → connection on B+C nodes, Feed entries on B+C, Orbit entries on B+C, conversation on B+C, notifications on A+B+C |
| Smoke 2: Dismiss + re-entry | A, B, C | A dismisses banner → A uses ⋮ menu → sends intros → B receives on their node |
| Smoke 3: Auto-dismiss | A, B | A and B exchange 3 messages → verify `introsBannerDismissed` on A's node |
| Smoke 4: No friends | A, B | A has only B → verify no intro option available on A's node |
| Smoke 5: Block during flow | A, B | A blocks B → verify banner flag on A's node, intros still on B's node |
| Smoke 6: Duplicate prevention | A, B, C | A introduces C to B → A tries again → C filtered out on A's node |
| Smoke 7: Ignore (no action) | A, B, C | B receives 3 intros → does nothing → no connections on any node |
| Smoke 8: Expiration | A, B | Old intro → verify expired status on B's node |
| Smoke 9: One-sided accept | A, B, C | B accepts → C hasn't → no connection on any node → C accepts → connection on B+C |
| Smoke 10: Mutual acceptance surfaces | A, B, C | Both accept → verify Feed, Orbit, conversation, notifications across B+C+A nodes |
| Smoke 11: Full cross-step chain | A, B, C | Every step in sequence, cumulative state verified on all 3 nodes after each step |

### Test Summary

| Step | Unit (single-node, mocked P2P) | Integration (multi-node CLI) | Smoke (multi-node CLI, chained) | Total |
|---|---|---|---|---|
| Data Model | 8 | — | — | 8 |
| Step 1 (Banner) | 12 | — | — | 12 |
| Step 2 (Dismiss) | 8 | 1 | — | 9 |
| Step 3 (Picker) | 15 | — | — | 15 |
| Step 4 (Send) | 11 | 1 | — | 12 |
| Step 5 (Confirmation) | 4 | — | — | 4 |
| Step 6 (Receiving) | 18 | 5 | — | 23 |
| Step 6c (Mutual) | 18 | 4 | — | 22 |
| Step 7 (System Msgs) | 10 | 1 | — | 11 |
| Step 8 (Edge Cases) | 9 | 2 | — | 11 |
| Smoke (E2E) | — | — | 11 | 11 |
| **Total** | **113** | **14** | **11** | **138** |

All 25 multi-node tests (14 integration + 11 smoke) run against **CLI nodes only** — no simulator, no UI automation. They verify data store state, message delivery, and side effects by querying each node directly.

---

## File Inventory (expected new/modified files)

| File | Action | Purpose |
|---|---|---|
| `models/introduction.ts` | **New** | Introduction data model & CRUD |
| `models/friendship.ts` | **Modify** | Add `introsBannerDismissed`, `introsSentAt` fields |
| `components/IntroduceBanner.tsx` | **New** | Banner card component (extract from kitchen) |
| `components/FriendPickerSheet.tsx` | **New** | Friend picker bottom sheet (extract from kitchen) |
| `components/SentConfirmation.tsx` | **New** | Confirmation screen (extract from kitchen) |
| `components/SystemMessage.tsx` | **New** | System event message bubble |
| `screens/ConversationScreen.tsx` | **Modify** | Integrate banner, picker, confirmation, system messages |
| `screens/CircleScreen.tsx` | **Modify** | Intros tab data from real Introduction records |
| `services/notifications.ts` | **Modify** | Add intro notification types |
| `utils/introductionHelpers.ts` | **New** | `showIntroBanner()`, `filterPickableFriends()`, etc. |
| `__tests__/introduction.test.ts` | **New** | Unit tests for data model (mocked) |
| `__tests__/introBanner.test.ts` | **New** | Unit tests for banner display logic (mocked) |
| `__tests__/introPickerSheet.test.ts` | **New** | Unit tests for picker filtering (mocked) |
| `__tests__/introMultiNode.test.ts` | **New** | Integration tests — multi-node CLI (real P2P) |
| `__tests__/introSmoke.test.ts` | **New** | Smoke/E2E tests — multi-node CLI (real P2P) |
| `__tests__/helpers/testHarness.ts` | **New** | Multi-node CLI test harness (setup/teardown 3 nodes) |

---

## Implementation Order

Execute steps **in order** — each step builds on the previous:

1. **Step 1** — Banner conditions (data model + display logic)
2. **Step 2** — Dismiss behavior (persistence + ⋮ re-entry)
3. **Step 3** — Friend Picker (selection UI + filtering)
4. **Step 4** — Send introductions (record creation + notifications)
5. **Step 5** — Sent Confirmation (UI only, uses data from Step 4)
6. **Step 6** — Receiving side (Intros tab + accept/pass)
7. **Step 6c** — Mutual acceptance detection (connection creation + Feed card + Orbit list)
8. **Step 7** — System messages (conversation history events)
9. **Step 8** — Edge cases & guards (hardening)

After each step, run that step's unit tests before proceeding. After Step 6c, run integration tests. After Step 8, run all smoke tests.
