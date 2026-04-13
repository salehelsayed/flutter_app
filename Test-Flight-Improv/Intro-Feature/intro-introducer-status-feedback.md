# 1. Title and Type

Title: Introducer-side intro status messaging is misleading and incomplete

Issue type: `bug`

Output doc path: `Test-Flight-Improv/Intro-Feature/intro-introducer-status-feedback.md`

# 2. Problem Statement

An introducer can currently send an intro and see the initial thread message in
the right place, but the follow-up acceptance feedback is not role-correct.

When User A introduces User B to User C or User D, User A correctly gets the
initial system message in the A<->B conversation that says A introduced those
people to B. After that, the flow becomes unclear for the introducer:

- A does not get an incremental thread-level message when one side accepts.
- When the second acceptance makes B and C mutually connected, A can receive a
  notification that says `Sarah also accepted! You're now connected.`

That wording is wrong for the introducer because A is not the newly connected
party. From A's perspective, the product needs to say who accepted, who the
intro was for, and which pair is now connected.

# 3. Impact Analysis

The affected user is the introducer, especially when they send multiple intros
to the same recipient and need to track progress pair by pair.

This appears after the initial intro send, during the acceptance phase:

- on first acceptance, the introducer gets status persistence but no visible
  thread-level progress message
- on mutual acceptance, the introducer can get copy that incorrectly implies
  they personally became connected
- on background or offline push paths, the relay side is even less specific and
  falls back to generic intro copy

Severity is medium from a product perspective. Repo evidence indicates the
underlying B/C connection sequence is already reliable, so this is not the same
class of issue as a dropped accept or split-brain state. The problem is that
the introducer-facing status signal is misleading or missing at the moments
where the user is trying to confirm whether their intro succeeded.

# 4. Current State

The initial introducer message is implemented and covered today.

- `lib/features/conversation/presentation/screens/conversation_wired.dart:970`
  inserts the send-time system message into the A<->B thread using
  `formatIntroducerIntroductionSystemMessage(...)`.
- `test/features/introduction/integration/intro_wiring_smoke_test.dart:431`
  verifies the stored message `You introduced Sarah to Lina`.
- `test/features/introduction/application/introduction_copy_test.dart:27`
  covers the existing introducer send copy formatter.

The accept delivery and state convergence path itself looks sound.

- `lib/features/introduction/application/accept_introduction_use_case.dart:102`
  builds an `accept` payload that includes `responderId` and
  `responderUsername`, then sends it to both the introducer and the other
  party.
- `test/features/introduction/application/accept_introduction_test.dart:196`
  covers that accept sends to the introducer.
- `lib/features/introduction/application/introduction_outbound_delivery.dart:24`
  assigns action-scoped envelope IDs.
- `go-relay-server/inbox_dedup_test.go:121` and
  `go-relay-server/inbox_dedup_test.go:174` prove `send` and `accept` for the
  same `introductionId` do not collide in relay dedupe.
- `test/features/introduction/integration/introduction_multi_node_test.dart:1158`
  and `test/features/introduction/integration/introduction_multi_node_test.dart:1283`
  show all three intro rows converge and B/C become contacts.

The introducer-facing presentation gap starts when incoming `accept` messages
are processed.

- `lib/features/introduction/application/introduction_listener.dart:353`
  handles `accept` and `pass` by emitting `introStatusChangedStream`.
- On mutual acceptance, `lib/features/introduction/application/introduction_listener.dart:356`
  shows a local notification with the hard-coded body
  `$responderName also accepted! You're now connected.`
- `test/features/introduction/application/introduction_listener_test.dart:419`
  currently locks in that exact notification for the intro listener path.

There is no introducer-side thread insertion on `accept` or `pass`.

- `lib/features/introduction/application/introduction_listener.dart:321`
  inserts a system message only for incoming `send` actions.
- There is no matching system-message insertion branch for `accept` or `pass`
  in that listener.
- `lib/features/feed/presentation/screens/feed_wired.dart:1962` and
  `lib/features/orbit/presentation/screens/orbit_wired.dart:736` react to
  status changes by refreshing counts or contact rows, not by writing
  conversation history.

Mutual-acceptance thread messages exist only for the newly connected pair, not
for the introducer's existing thread with the recipient.

- `lib/features/introduction/application/handle_mutual_acceptance_use_case.dart:31`
  computes the "other party" from the recipient/introduced perspective.
- If that other party is already a contact, the function exits early at
  `lib/features/introduction/application/handle_mutual_acceptance_use_case.dart:39`
  without inserting a system message.
- When a new contact is created, `lib/features/introduction/application/handle_mutual_acceptance_use_case.dart:87`
  inserts `You and Sarah are now connected — introduced by Noor` into the new
  B<->C conversation.
- `test/features/introduction/application/create_connection_on_mutual_acceptance_test.dart:146`
  covers that participant-side message.

The intro surfaces already expose status labels for the two introduced parties,
but not the requested A-thread timeline.

- `lib/features/introduction/presentation/widgets/intro_row.dart:120` shows
  `Connected` for mutual acceptance.
- `test/features/introduction/presentation/widgets/intro_row_test.dart:143`
  covers the `Waiting for Charlie` state.

The relay and fallback push layers do not currently provide meaningful
introducer-specific accept copy.

- `go-relay-server/inbox.go:432` maps every introduction envelope to the
  generic route type `intros` with `Open Mknoon to review`.
- `go-relay-server/inbox.go:272` then turns that into generic push title/body
  and omits `sender_id` for intros.
- `go-relay-server/inbox_test.go:692` explicitly tests that generic intro push
  behavior.
- `lib/features/introduction/domain/models/introduction_payload.dart:56`
  places `action`, `responderId`, and `responderUsername` in the inner intro
  payload, but `lib/features/introduction/domain/models/introduction_payload.dart:190`
  shows the encrypted v2 envelope only exposes `messageId`, `senderPeerId`, and
  encrypted bytes at the top level.
- `test/features/push/application/background_push_notification_fallback_test.dart:239`
  currently preserves the same participant-style mutual-accept copy
  `Sarah also accepted! You're now connected.` when intro-specific copy is
  already present.

Targeted verification on 2026-04-13 matched the code review:

- `flutter test --no-pub test/features/introduction/application/introduction_listener_test.dart test/features/push/application/background_push_notification_fallback_test.dart`
  passed and confirmed the current introducer notification copy is codified.
- `go test -run 'TestBuildIntroductionPushMessage_UsesIntrosRouteAndGenericCopy|TestInboxStoreDedup_IntroductionPlaintextDifferentActionMessageIDs|TestInboxStoreDedup_IntroductionEncryptedDifferentActionMessageIDs' ./...`
  passed in `go-relay-server`.

# 5. Scope Clarification

This spec is about introducer-facing status clarity, not intro transport
correctness.

In scope:

- the notification body shown to the introducer after mutual acceptance
- short system-message visibility in the introducer's main chat thread with the
  intro recipient
- first-accept progress feedback for the introducer
- mutual-accept feedback that clearly states which two people are now connected

Not in scope:

- changing how recipient and introduced users see their own intro copy
- changing how B and C become contacts or how mutual acceptance is derived
- redesigning the Intros tab, Orbit routing, or feed layout
- broad push architecture changes beyond what is needed to make introducer
  feedback user-meaningful

Accepted ambiguity for later implementation:

- exact final wording can vary from the user examples as long as it is
  unambiguous about the actor and the connected pair
- for a batch intro such as B being introduced to both C and D, progress may be
  surfaced as one event per intro pair rather than one aggregated summary

# 6. Test Cases

Happy path:

1. When A introduces C and D to B, the A<->B thread still shows the existing
   send-time summary such as `You introduced C and D to B`.
   Existing partial coverage: `test/features/introduction/integration/intro_wiring_smoke_test.dart:431`.

2. When B accepts A's intro to C while C is still pending, A sees a short
   system message in the A<->B thread that clearly means `B accepted your intro
   to C`, and the message does not imply that A or C already connected.
   Current gap: no direct test appears to cover introducer-side first-accept
   thread messaging.

3. When C later accepts and B/C become connected, A receives a notification
   that clearly means `C accepted your intro to B; they are now connected`.
   The notification must name the accepter and the connected pair without
   implying that A is one of the connected users.
   Current gap: the intro listener test currently expects the wrong wording at
   `test/features/introduction/application/introduction_listener_test.dart:419`.

4. When C later accepts and B/C become connected, A also sees a short system
   message in the A<->B thread that clearly means `B and C are now connected`.
   Current gap: no direct test appears to cover introducer-side mutual-connect
   thread messaging.

5. The same progress model works independently for the second pair B/D, so A
   can tell that C connected even while D is still pending.

Edge cases:

1. If C accepts first and B accepts second, the introducer-facing copy is still
   actor-correct and pair-correct.

2. If B accepts C but D remains pending, A's B-thread feedback reflects only
   the C pair and does not collapse all introduced users into one completed
   state.

3. If the app is backgrounded or relaunched and the intro notification comes
   through the push fallback path, the resulting copy is either meaningful for
   the introducer or explicitly neutral; it must not say `You're now connected`
   to A unless A is actually one of the connected users.
   Current gap: relay tests currently lock intros pushes to generic copy, and
   fallback tests only preserve the current participant-style mutual-accept
   body.

4. If B and C are already connected, the introducer does not receive false
   `now connected` progress for that pair, and the existing already-connected
   semantics remain intact.

Regressions to preserve:

1. B and C still reach `mutualAccepted` reliably, including delayed inbox
   healing and relay-deduped accept delivery.
   Existing coverage: `test/features/introduction/integration/introduction_multi_node_test.dart:1158`,
   `test/features/introduction/integration/introduction_multi_node_test.dart:1283`,
   `go-relay-server/inbox_dedup_test.go:121`, and
   `go-relay-server/inbox_dedup_test.go:174`.

2. Recipient and introduced users still keep their current role-aware intro
   system messages and participant-side mutual-connection message.
   Existing coverage: `test/features/introduction/application/introduction_copy_test.dart:49`
   and `test/features/introduction/application/create_connection_on_mutual_acceptance_test.dart:146`.

3. Duplicate accept replay must not duplicate any introducer-side thread
   message or notification once the correct copy exists.

Bug regression:

1. When A is only the introducer and not one of the introduced parties, no
   notification or system message may tell A `You're now connected` for B/C or
   B/D.

# 7. Multi-Pass Audit Update

Date: 2026-04-13

Method:

- two audit cycles
- three sequential spawned explorer agents per cycle
- local adjudication against the client and `go-relay-server` after each cycle

The agent passes were useful for breadth, but not authoritative on their own.
Several suggestions were down-ranked after direct code review because they
would add test surface without materially improving intro reliability.

## Final Call

The Intro feature is broadly reliable today. I do not see a new relay-side or
core handshake hole that needs reopening. The current open work is narrower:

1. the introducer-facing status copy bug already described in this doc remains
   the highest-value open issue
2. a handful of non-happy-path client branches still lack direct regression
   coverage
3. one lower-priority outbound-delivery branch set is still untested

The relay/delivery foundation itself stays closed on current repo evidence.

## Accepted Findings After Adjudication

### 7.1 Primary Open Bug

Keep open: introducer-side accept and mutual-accept feedback is still wrong or
missing in the user-visible flow.

Why this stays open:

- `lib/features/introduction/application/introduction_listener.dart:356`
  still emits `'$responderName also accepted! You\'re now connected.'` on
  mutual acceptance.
- `test/features/introduction/application/introduction_listener_test.dart:419`
  still codifies that wrong introducer-facing notification body.
- Helper-level copy coverage in
  `lib/features/introduction/application/introduction_copy.dart:44` and
  `test/features/introduction/application/introduction_copy_test.dart:97`
  does not cover the actual introducer listener path.

Practical call:

- keep this as the top intro UX/reliability item
- do not treat helper-copy tests as closure for the real introducer flow

### 7.2 Listener Non-Happy-Path Coverage Is Still Thin

Keep open: `IntroductionListener` still lacks direct tests for several
meaningful error and edge branches.

Verified gaps:

- missing ML-KEM secret branch:
  `lib/features/introduction/application/introduction_listener.dart:191`
- missing own peer id branch:
  `lib/features/introduction/application/introduction_listener.dart:292`
- direct nonce confirmation failure logging:
  `lib/features/introduction/application/introduction_listener.dart:140`
- already-connected user-visible emission path:
  `lib/features/introduction/application/introduction_listener.dart:321`
  combined with
  `lib/features/introduction/application/introduction_copy.dart:53`

Closest current coverage:

- `test/features/introduction/application/introduction_listener_test.dart:216`
  covers the normal receive path
- `test/features/introduction/application/introduction_listener_test.dart:570`
  covers successful nonce confirmation
- `test/features/introduction/application/introduction_copy_test.dart:80`
  covers the helper suffix for `alreadyConnected`

Practical call:

- this is worth closing with focused listener tests
- it is a real gap, but still secondary to the introducer copy bug

### 7.3 UI Edge-State Coverage Is Thinner Than The Happy Path

Keep open, but lower priority: a couple of user-visible intro states are only
partially covered.

Verified gaps:

- Orbit refreshes intro rows from `introStatusChangedStream` in
  `lib/features/orbit/presentation/screens/orbit_wired.dart:736`, but the
  nearest pass coverage in
  `test/features/orbit/presentation/screens/orbit_intros_wiring_test.dart:139`
  only proves pending-count effects after pass, not a direct live remote-pass
  screen refresh on the Intros surface.
- `IntroRow` has a blocked-counterparty branch that renders `Unavailable` in
  `lib/features/introduction/presentation/widgets/intro_row.dart:115`, while
  `test/features/introduction/presentation/widgets/intro_row_test.dart:174`
  covers `alreadyConnected`, not that blocked-action branch.

Practical call:

- these are worth a small amount of additional coverage
- do not elevate them above the introducer copy bug or listener edge coverage

### 7.4 Lower-Priority Delivery Hardening Gap

Keep as residual hardening only: `introduction_outbound_delivery.dart` still
has a couple of untested branches.

Verified gaps:

- already-connected direct-send fast path:
  `lib/features/introduction/application/introduction_outbound_delivery.dart:207`
- inbox retry exception branch that records `INTRO_OUTBOX_RETRY_ERROR` and
  `inbox_retry_failed`:
  `lib/features/introduction/application/introduction_outbound_delivery.dart:127`
  and `:148`

Closest current coverage:

- `test/features/introduction/application/introduction_outbound_delivery_test.dart:45`
  through `:352` covers live send, relay probe, inbox fallback success, inbox
  fallback failure, and retry replay, but not those specific branches.

Practical call:

- this is real, but lower-priority than the user-visible and listener-path
  items above
- treat it as hardening, not as evidence that intro delivery is currently
  unreliable

## Rejected Or Down-Ranked Findings

Rejected after local review:

- `FriendPickerWired` failure-path tests as a priority item. The screen wrapper
  is thin, and the meaningful send semantics are already covered lower in the
  stack by `send_introduction_test.dart`. This is not where current intro risk
  sits.
- feed-card introducer avatar-row detail in
  `IntroductionConnectionCard`. That is a cosmetic branch, not a reliability
  seam.
- reopening relay dedupe, replay, or inbox-routing concerns. Current relay and
  multi-node coverage is already strong enough here.
- top-level `integration_test/` symmetry for Intro. The current host-side,
  relay-side, and simulator-backed coverage is sufficient without adding a new
  top-level artifact just for shape.
- end-to-end FCM/APNs trigger delivery as an intro-specific blocker. That is a
  broader push infrastructure gap, explicitly noted in
  `Test-Flight-Improv/Intro-Feature/test-inventory.md:827`, but it is not a
  reason to reopen the intro relay/delivery implementation itself.

## Safe Next Step

If this doc is used for rollout, keep the scope narrow:

1. fix the introducer-facing accept and mutual-accept copy/message flow
2. add targeted `IntroductionListener` edge-path tests
3. optionally add the smaller Orbit/IntroRow and outbound-delivery hardening
   tests afterward

That ordering improves reliability without reopening already-closed transport
or relay work.
