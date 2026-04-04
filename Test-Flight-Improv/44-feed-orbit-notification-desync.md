# 44 - Feed clears a notification while Orbit still shows it as pending

## 1. Title and Type

- Title: Feed clears a notification while Orbit still shows it as pending
- Issue type: `bug`
- Output doc path: `Test-Flight-Improv/44-feed-orbit-notification-desync.md`

## 2. Problem Statement

- Users are trying to understand and clear one incoming 1:1 message notification across the app's two messaging surfaces: the Feed stack card and the Orbit contact row.
- Today, when a notification opens the message on Feed, the user can collapse that stack card or send a reply from it and see Feed move on, but later the same contact can still appear on Orbit as if that same notification is still pending.
- From the user's perspective, one side of the app says the message was already seen or handled while the other side still presents it as new work. That duplicates attention, makes unread state feel unreliable, and creates avoidable confusion about whether the message still needs action.

## 3. Impact Analysis

- Who is affected:
  - users who receive 1:1 message notifications
  - users who use Feed stack cards to collapse or reply instead of immediately opening the full conversation
  - users who later check the same contact from Orbit
- When the issue appears:
  - a contact sends a new 1:1 message
  - the message is surfaced on Feed as the notification-led stack card state
  - the user collapses that card or replies inline from Feed
  - the user later views the same contact on Orbit and still sees the same notification state represented there
- Severity:
  - medium-high, because the bug affects core message-state trust across two primary navigation surfaces
- Frequency:
  - repo evidence supports a repeatable cross-surface risk whenever Feed and Orbit are used for the same thread in one session
  - no precise production frequency is established by repo evidence alone
- User-visible cost:
  - the same message can appear to need attention twice
  - users have to guess which surface is telling the truth
  - the app can feel inconsistent even when message delivery itself succeeded

## 4. Current State

- Affected code areas:
  - `lib/features/feed/presentation/screens/feed_wired.dart`
  - `lib/features/feed/presentation/screens/feed_screen.dart`
  - `lib/features/feed/domain/models/feed_item.dart`
  - `lib/features/orbit/presentation/screens/orbit_wired.dart`
  - `lib/features/orbit/presentation/screens/orbit_screen.dart`
  - `lib/features/orbit/presentation/widgets/friend_row.dart`
  - `lib/features/orbit/application/load_orbit_data_use_case.dart`
  - `lib/features/conversation/application/mark_conversation_read_use_case.dart`
  - `lib/features/conversation/domain/repositories/message_repository_impl.dart`
- Existing user-visible flow today:
  - Feed places unread and active conversation cards above the divider and shows open-mode stack cards from thread unread state. Evidence: `lib/features/feed/presentation/screens/feed_screen.dart` and `lib/features/feed/domain/models/feed_item.dart`.
  - A successful inline reply from Feed creates a local session reply, calls `markConversationRead(...)`, refreshes the Feed contact snapshot, and reloads the total Feed unread count. Evidence: `lib/features/feed/presentation/screens/feed_wired.dart` and `lib/features/conversation/application/mark_conversation_read_use_case.dart`.
  - Collapsing an unread or active Feed card also calls `markConversationRead(...)` and refreshes only the Feed contact snapshot for that card. Evidence: `lib/features/feed/presentation/screens/feed_wired.dart`.
  - Orbit builds each friend row from an `OrbitFriend` summary. That row keeps the latest activity text and shows `UnreadCountBadge` when `friend.unreadCount > 0`. Evidence: `lib/features/orbit/application/load_orbit_data_use_case.dart`, `lib/features/orbit/domain/models/orbit_friend.dart`, and `lib/features/orbit/presentation/widgets/friend_row.dart`.
  - Orbit keeps its own in-memory friend lists and refreshes a single row on incoming chat events, contact updates, and Orbit-owned route-return changes. Evidence: `lib/features/orbit/presentation/screens/orbit_wired.dart`.
  - Feed and Orbit can remain mounted together inside the shared swipe host once Orbit has been opened from Feed. Evidence: `lib/features/feed/presentation/screens/feed_wired.dart`.
  - Feed-owned clear/handle actions do not travel back through Orbit's `FeedRouteChanges` path, which is currently used when Orbit-triggered routes return. Evidence: `lib/features/feed/domain/models/feed_route_changes.dart`, `lib/features/feed/presentation/screens/feed_wired.dart`, and `lib/features/orbit/presentation/screens/orbit_wired.dart`.
  - `markConversationRead(...)` delegates to `messageRepo.markConversationAsRead(...)`, and the current repository implementation marks database rows read without publishing a repository change event for that read-state mutation. Evidence: `lib/features/conversation/application/mark_conversation_read_use_case.dart` and `lib/features/conversation/domain/repositories/message_repository_impl.dart`.
- Important constraints and adjacent coverage already present:
  - `Test-Flight-Improv/32-notification-card-interactions.md` already covers notification-opened Feed-card interaction issues after messages are visible on Feed, not cross-surface Feed/Orbit consistency.
  - `Test-Flight-Improv/40-feed-stack-card-keeps-earlier-notification-messages-after-inline-reply.md` already covers Feed-only unread-stack truth after inline reply, not whether Orbit also clears the same handled notification state.
  - `test/features/feed/presentation/screens/feed_wired_test.dart` already covers Feed-side unread clearing after inline reply and open-card collapse behavior.
  - `test/features/orbit/presentation/screens/orbit_wired_test.dart` already covers Orbit row refresh on incoming message events.
  - `test/features/feed/presentation/screens/feed_wired_test.dart` already covers Feed handling of `FeedRouteChanges` returned from Orbit-owned actions.
  - No existing test was found for the user-visible sequence `notification opens Feed stack card -> user collapses or replies inline on Feed -> user later checks Orbit -> the same contact no longer appears to carry that same pending notification state`.

## 5. Scope Clarification

- In scope:
  - 1:1 message-notification state shared between Feed and Orbit
  - user-visible consistency after a notification-led Feed stack card is collapsed
  - user-visible consistency after a successful inline reply is sent from that Feed stack card
  - both same-session cases where Orbit is already mounted and later-view cases where Orbit is opened after Feed interaction
- Explicit non-goals:
  - redesigning Orbit list layout or Feed card layout
  - broader notification routing or notification-open delivery issues already covered by other reports
  - group-thread and introduction-surface behavior unless the same bug is separately confirmed there
  - redefining how normal read conversations show their latest message preview when no unread/new-message state is pending
  - choosing an implementation seam for cross-surface synchronization
- Accepted ambiguities to keep open for the later implementation pass:
  - whether "remove the same notification from Orbit" means clearing only the unread badge, changing row styling, suppressing a specific preview treatment, or a combination of those as long as Orbit no longer implies the same handled message is still pending
  - whether Feed collapse and successful inline reply share one underlying state-sync cause or multiple causes
  - whether the stale Orbit state reproduces only when Orbit was already mounted in the shared host or also when Orbit is opened fresh after Feed already handled the message

## 6. Test Cases

### Happy Path

- `TC-44-H01` Given user-B receives a new 1:1 message from user-A and that notification opens the Feed stack card, when user-B collapses the Feed card, then Orbit no longer presents user-A as still carrying that same pending unread/new-message notification state.
- `TC-44-H02` Given user-B receives a new 1:1 message from user-A and replies successfully from the Feed stack card, when user-B later opens Orbit, then Orbit no longer presents that already-handled message as still pending for user-A.
- `TC-44-H03` Given Orbit has already been mounted in the shared Feed/Orbit host during the same session, when user-B clears the notification from Feed and switches back to Orbit, then the Orbit row updates during that same session without requiring an app restart or a full route recreation.

### Edge Cases

- `TC-44-E01` Given multiple unread messages were shown in the Feed stack card and user-B collapses that card without any newer messages arriving afterward, when user-B later views Orbit, then Orbit does not keep showing those same already-seen messages as still waiting for attention.
- `TC-44-E02` Given user-B successfully replies inline from Feed and user-A later sends a newer message, when Orbit is viewed, then Orbit shows only the newer unread state and does not continue to represent the earlier Feed-handled message as still pending.
- `TC-44-E03` Given user-B handles the notification from Feed before Orbit has been opened in that session, when Orbit is opened for the first time afterward, then the initial Orbit state already reflects that the earlier notification was handled.
- `TC-44-E04` Given user-B handles the notification from Feed while Orbit is already mounted but offscreen in the shared swipe host, when user-B returns to Orbit, then Orbit matches the cleared Feed state instead of showing stale unread/new-message UI for that same handled message.

### Regressions To Preserve

- `TC-44-R01` Bug regression: The same incoming 1:1 notification must not remain presented as pending on Orbit after the user already collapsed or successfully replied from the corresponding Feed stack card.
- `TC-44-R02` Given a genuinely new message arrives after the earlier Feed-handled one, when Feed and Orbit refresh, then both surfaces still surface that later unread state normally.
- `TC-44-R03` Given Orbit refreshes because of an incoming chat event or an Orbit-owned route return, when that existing behavior occurs, then Orbit row refreshes continue to work while cross-surface notification truth stays consistent.
- `TC-44-R04` Given the Feed-only unread-stack behavior from `Test-Flight-Improv/40-feed-stack-card-keeps-earlier-notification-messages-after-inline-reply.md` is already preserved, when this cross-surface bug is addressed later, then Feed must still avoid resurfacing earlier handled unread rows inside Feed itself.
- Existing tests that partially cover this area today:
  - `test/features/feed/presentation/screens/feed_wired_test.dart`
  - `test/features/orbit/presentation/screens/orbit_wired_test.dart`
  - `Test-Flight-Improv/32-notification-card-interactions.md`
  - `Test-Flight-Improv/40-feed-stack-card-keeps-earlier-notification-messages-after-inline-reply.md`
- Current test gap:
  - no existing test was found for Feed-originated notification clearance propagating into Orbit's mounted row state for the same contact
  - no existing test was found for opening Orbit after Feed already handled the notification and confirming the first Orbit render reflects that cleared state
