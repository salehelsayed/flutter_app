# 39 - Introducer Intro Follow-up Copy And Completion Card

## 1. Title and Type

- Title: Introducer intro follow-up copy and completion card
- Issue type: `feature-improvement`
- Output doc path: `Test-Flight-Improv/39-introducer-intro-follow-up-copy-and-completion-card.md`

## 2. Problem Statement

User-A introduces one or more friends to user-B from the existing conversation
flow and expects the app to preserve a clear record of who was introduced and
what eventually happened.

Today, the durable conversation history between user-A and user-B collapses the
send event into generic count-only text such as `You introduced 1 person to
user-B`, even when the app already knows the specific introduced usernames.
Later, when both introduced users accept and become connected, user-A can get a
`New Connection` notification, but there is no persistent in-app card that
shows user-B and user-C are now connected. From the introducer's perspective,
the intro aftermath is not specific enough when it is sent and not visible
enough when it succeeds.

## 3. Impact Analysis

- Who is affected: users acting as the introducer in the friend introduction
  flow.
- When the issue appears: immediately after sending introductions from a
  conversation, and again later when the same introduction reaches mutual
  acceptance.
- Severity: moderate. The core introduction flow still works, but the
  introducer loses truthful history and durable completion feedback.
- Frequency: whenever an introducer relies on conversation history to remember
  who they introduced, or when they revisit a successful introduction after the
  transient mutual-accept notification has disappeared.
- User-visible confusion cost: count-only wording forces the introducer to
  reconstruct who was introduced from memory, and the later notification does
  not leave a stable card that confirms which pair actually connected.
- Existing mitigation already present in the repo: the immediate
  post-send confirmation screen can list introduced usernames, but that screen
  is transient and does not replace durable conversation/history follow-up.

## 4. Current State

- The conversation send callback currently inserts a system message using only
  the number of selected introductions plus the recipient username:
  `You introduced $count $noun to ${_contact.username}` in
  `lib/features/conversation/presentation/screens/conversation_wired.dart`.
- `insertIntroSystemMessage()` documents the same send-side pattern as
  `You introduced N people to [name]`, and stores it as a regular conversation
  message with `transport = 'system'` in
  `lib/features/introduction/application/insert_intro_system_message.dart`.
- The `IntroSystemMessage` widget is generic display-only UI. Its widget tests
  already prove the renderer can show both count-only and name-based strings,
  including `You introduced 3 people` and `Alice introduced Charlie, Dana to
  you`, in
  `test/features/introduction/presentation/widgets/intro_system_message_test.dart`.
- The send flow already has access to the actual introduced usernames. After
  sending, `ConversationWired` passes `introducedUsernames` into
  `SentConfirmationWired`, and `SentConfirmationScreen` renders those names
  directly, truncating after three names with `and N more`, in
  `lib/features/introduction/presentation/screens/sent_confirmation_wired.dart`,
  `lib/features/introduction/presentation/screens/sent_confirmation_screen.dart`,
  and `test/features/introduction/presentation/screens/sent_confirmation_test.dart`.
- When a later incoming accept moves an introduction to
  `mutualAccepted`, `IntroductionListener` emits `introStatusChangedStream` and
  shows a local notification with title `New Connection` and body
  `$responderName also accepted! You're now connected.` with payload `intros`
  in `lib/features/introduction/application/introduction_listener.dart`.
- That notification payload opens the Orbit route on the `Intros` tab through
  `NotificationRouteTargetKind.intros` and `openIntroNotificationOrbitRoute()`
  in `lib/main.dart`. Route behavior is covered in
  `test/features/push/application/intro_notification_orbit_route_test.dart`.
- Orbit Intros is not an introducer history surface. It loads only pending or
  already-connected intros where the current user is the `recipient` or the
  `introduced` party, via `loadIntroductionsForUser()` and the DB query in
  `lib/features/introduction/application/load_introductions_use_case.dart` and
  `lib/core/database/helpers/introductions_db_helpers.dart`.
- The existing mutual-accept completion card is built for the two people who
  become new contacts, not for the introducer. `handleMutualAcceptance()`
  creates the new contact with `introducedBy`, `FeedWired` refreshes that
  contact's feed item when the intro reaches `mutualAccepted`, and `FeedScreen`
  renders `IntroductionConnectionCard` for that contact in
  `lib/features/introduction/application/handle_mutual_acceptance_use_case.dart`,
  `lib/features/feed/presentation/screens/feed_wired.dart`,
  `lib/features/feed/presentation/screens/feed_screen.dart`, and
  `lib/features/feed/presentation/widgets/introduction_connection_card.dart`.
  Participant-side surfacing is covered in
  `test/features/feed/presentation/screens/feed_wired_test.dart`.
- Sender-side introduction rows do exist locally. The repo queries them through
  `getIntroductionsByIntroducer()` for duplicate filtering in the picker and for
  a debug-only settings card, but no normal user-facing feed/orbit/conversation
  surface currently loads those rows as a durable mutual-accept result in
  `lib/features/introduction/presentation/screens/friend_picker_wired.dart`,
  `lib/features/settings/presentation/screens/settings_wired.dart`, and
  `lib/features/settings/presentation/widgets/settings_introduction_debug_card.dart`.
- Adjacent repo context: Report `38`
  (`Test-Flight-Improv/38-mutual-intro-acceptance-leaves-one-side-waiting.md`)
  already covers participant-side convergence when both introduced users accept.
  This spec is narrower: introducer-side follow-up copy and durable completion
  surfacing after the introduction succeeds.

## 5. Scope Clarification

- In scope: introducer-side durable summary text after sending introductions
  from a conversation. The stored conversation message should identify the
  introduced person when there is one, and preserve a readable truthful summary
  when there are multiple introduced people.
- In scope: a persistent user-facing completion card for the introducer after
  both introduced users accept the same introduction, so the result remains
  visible after the transient notification.
- In scope: the completion card's user-visible semantics should match the
  existing introduction connection card pattern by clearly showing that the two
  introduced users are now connected.
- Out of scope: changing how introductions are sent over the network, how
  mutual acceptance is derived, or how the two newly connected users receive
  their own new-contact experience.
- Out of scope: redesigning the general intro picker, Orbit intro list,
  notification deep-link routing, or the participant-side waiting-state bug
  already captured in Report `38`.
- Out of scope: choosing the internal storage seam, event pipeline, or widget
  ownership for the new introducer-facing completion card.
- Accepted ambiguity for later implementation: the exact host surface for the
  persistent introducer card can remain open as long as it is a normal
  user-facing screen that the introducer can revisit after notification time.
- Accepted ambiguity for later implementation: the precise wording/truncation
  format for multi-name conversation summaries can remain open as long as the
  text stays truthful about which users were introduced.

## 6. Test Cases

### Happy Path

- `TC-39-HP-01` Given user-A introduces only user-C to user-B from the
  conversation with user-B, when the send completes, then the durable system
  message in the user-A/user-B conversation names user-C rather than only
  saying `1 person`.
- `TC-39-HP-02` Given user-A introduces multiple people to user-B in one send,
  when the send completes, then the durable system message in the user-A/user-B
  conversation shows a readable summary of the introduced usernames instead of
  only a numeric count.
- `TC-39-HP-03` Given user-B and user-C later both accept the same
  introduction, when user-A receives the mutual-accept result, then user-A has
  a persistent in-app card that states user-B and user-C are now connected.
- `TC-39-HP-04` Given user-A reopens the relevant app surface after the
  notification is gone, when the intro has already reached mutual acceptance,
  then the completion card is still visible to user-A without needing a fresh
  notification.
- `TC-39-HP-05` Given the app already shows an `IntroductionConnectionCard` to
  the newly connected users, when user-A sees the introducer-side completion
  result, then the card communicates the same user-visible outcome: the two
  introduced people are now connected.

### Edge Cases

- `TC-39-EC-01` Given user-A introduces multiple people to user-B, when only
  one introduced pair later reaches mutual acceptance, then user-A can
  distinguish the completed pair from other introductions that are still
  pending or passed.
- `TC-39-EC-02` Given the introduced usernames include more than one script or
  mixed-direction text, when the durable summary message is rendered in the
  conversation, then the text remains readable and directionally correct.
- `TC-39-EC-03` Given the app truncates multi-name summaries for space, when
  more names were introduced than can be shown inline, then the visible summary
  still remains truthful about the names shown and the number of additional
  introduced users.
- `TC-39-EC-04` Given user-A introduced user-B to user-C and also introduced
  user-B to user-D, when only the B/C pair becomes connected, then the durable
  follow-up surface for user-A does not incorrectly imply that B/D is also
  complete.

### Regressions To Preserve

- `TC-39-RG-01` Given the send succeeds, then the existing sent-confirmation
  screen still shows the count of introductions sent and the introduced
  usernames list before the user returns to the conversation.
- `TC-39-RG-02` Given user-B and user-C reach `mutualAccepted`, then the
  participant-side experience still works: the new contact exists for each side
  and the existing `IntroductionConnectionCard` can still surface for the newly
  connected users.
- `TC-39-RG-03` Given intro notifications are enabled, then the existing intro
  notification deep-link behavior still opens the Orbit intro route when the
  user taps the notification.
- `TC-39-RG-04` Given only one side has accepted so far, then the app must not
  prematurely surface the introducer completion state for that pair as if both
  sides were already connected.
- `TC-39-RG-05` Given an intro resolves as `alreadyConnected` or `passed`,
  then the app must preserve those outcomes rather than presenting them as a
  successful new connection.

### Existing Coverage And Gaps

- Existing partial coverage: `test/features/introduction/presentation/widgets/intro_system_message_test.dart`
  proves the system-message renderer can display both count-only and name-based
  copy.
- Existing partial coverage: `test/features/introduction/presentation/screens/sent_confirmation_test.dart`
  proves the send-confirmation surface already renders introduced usernames and
  overflow text.
- Existing partial coverage: `test/features/introduction/application/introduction_listener_test.dart`
  proves introduction listener stream updates, and
  `test/features/push/application/intro_notification_orbit_route_test.dart`
  proves intro-notification routing into Orbit.
- Existing partial coverage: `test/features/feed/presentation/screens/feed_wired_test.dart`
  proves the participant-side `IntroductionConnectionCard` can appear after late
  mutual acceptance.
- Current gap: no automated test currently asserts that the actual
  conversation-send path composes a name-aware durable system message from the
  introduced usernames instead of collapsing to count-only copy.
- Current gap: no automated test currently proves that the introducer receives
  a persistent in-app completion card after mutual acceptance, or that the card
  remains discoverable after the notification itself is dismissed.
- Current gap: no automated test currently covers mixed outcomes across
  multiple introduced people from the introducer's perspective, where one pair
  completes and another pair remains unresolved.
