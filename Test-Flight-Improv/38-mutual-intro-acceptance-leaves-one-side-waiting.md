# 38 - Mutual Introduction Acceptance Leaves One Side Waiting

## 1. Title and Type

- Title: Mutual introduction acceptance leaves one side waiting
- Issue type: `bug`
- Output doc path: `Test-Flight-Improv/38-mutual-intro-acceptance-leaves-one-side-waiting.md`

## 2. Problem Statement

User-A introduces user-B to user-C so they can connect through a mutual friend.
After both user-B and user-C accept the same introduction, both people should
see the introduction complete and the new connection surfaced consistently.

Instead, the reported outcome is asymmetric: user-B receives the successful
connection card, while user-C still sees `Waiting for user-B` in Orbit Intros.
From the user's perspective, the same introduction appears complete on one side
and incomplete on the other. That makes the handshake hard to trust and leaves
one user unsure whether the connection actually finished.

## 3. Impact Analysis

- Who is affected: users on either side of a friend introduction when both
  people accept but one device still holds the introduction in a pending state.
- When the issue appears: after the second acceptance has happened, and at least
  one side has already surfaced the successful connection.
- Severity: moderate to high. The flow reaches an inconsistent user-visible end
  state in a core social action.
- Frequency: not established by repo evidence. The repo shows the state machine
  for this flow, but no telemetry or durable bug frequency data exists here.
- User-visible consequence: one user can believe the other person never
  finished accepting, even though the other side already sees a completed
  connection.
- Likely side effects from current repo behavior, inferred from the pending-only
  intro queries: if a device remains on overall intro status `pending`, Orbit
  keeps treating that intro as live, so the stale row and pending intro count
  can remain visible on that side.

## 4. Current State

- Orbit Intros renders a live row from pending intro records loaded by
  `loadIntroductionsForUser()`
  (`lib/features/introduction/application/load_introductions_use_case.dart:5-27`,
  `lib/features/orbit/presentation/screens/orbit_wired.dart:602-624`).
- The underlying DB query only loads rows whose overall status is
  `pending` or `already_connected`
  (`lib/core/database/helpers/introductions_db_helpers.dart:393-417`).
  A row that still appears in Orbit after both users accepted therefore implies
  that device never moved its local intro record to `mutual_accepted`.
- The Orbit row text is driven by the combination of the current user's own
  party status and the overall intro status. `IntrosTab` computes
  `ownPartyStatus` and `waitingForUsername`
  (`lib/features/introduction/presentation/widgets/intros_tab.dart:81-113`),
  then `IntroRow` shows `Waiting for <username>` when the local user is already
  `accepted` but the overall intro status is still `pending`
  (`lib/features/introduction/presentation/widgets/intro_row.dart:123-156`).
  The row only shows `Connected` when the overall status is
  `mutualAccepted`
  (`lib/features/introduction/presentation/widgets/intro_row.dart:123-158`,
  `lib/features/introduction/presentation/widgets/intro_row.dart:211-227`).
- Local acceptance alone does not complete the intro. `acceptIntroduction()`
  updates the local party status to `accepted`, derives a new overall status,
  sends an accept payload to the introducer and the other party, and only runs
  mutual-acceptance follow-up immediately if the recomputed overall status is
  already `mutualAccepted`
  (`lib/features/introduction/application/accept_introduction_use_case.dart:42-130`).
- The opposite side's local intro record is updated only when the incoming
  accept is processed. `handleIncomingIntroduction()` applies the responder's
  new party status, derives the new overall status, and triggers
  `handleMutualAcceptance()` when the intro reaches `mutualAccepted`
  (`lib/features/introduction/application/handle_incoming_introduction_use_case.dart:146-235`).
- `IntroductionListener` publishes that updated model through
  `introStatusChangedStream`, and only shows the `New Connection` notification
  when the updated intro is `mutualAccepted`
  (`lib/features/introduction/application/introduction_listener.dart:267-283`).
- Once an intro becomes `mutualAccepted`, `handleMutualAcceptance()` creates the
  new contact and inserts the `Connected through <introducer>` system message
  (`lib/features/introduction/application/handle_mutual_acceptance_use_case.dart:10-18`,
  `lib/features/introduction/application/handle_mutual_acceptance_use_case.dart:26-121`).
- Feed surfaces the completed connection from that mutual-acceptance path.
  `FeedWired` refreshes on intro status changes and only refreshes the contact
  feed item when the intro status is `mutualAccepted`
  (`lib/features/feed/presentation/screens/feed_wired.dart:1889-1917`).
  `FeedScreen` then renders `IntroductionConnectionCard` for contacts created
  through introductions
  (`lib/features/feed/presentation/screens/feed_screen.dart:690-705`,
  `lib/features/feed/presentation/widgets/introduction_connection_card.dart:7-22`).
- `test/features/introduction/application/mutual_acceptance_test.dart:68-98`
  proves a local accept plus explicit incoming accept reaches
  `mutualAccepted`.
- `test/features/introduction/integration/introduction_multi_node_test.dart:148-224`
  and `test/features/introduction/integration/introduction_smoke_test.dart:316-350`
  prove both nodes can reach `mutualAccepted`, but both tests manually call
  `receiveAcceptNotification(...)` on the opposite node after each accept.
- `test/shared/fakes/intro_test_user.dart:138-160` explicitly documents
  `receiveAcceptNotification(...)` as a simulation of the cross-node effect.
- `test/features/orbit/presentation/screens/orbit_intros_wiring_test.dart:198-226`
  manually injects the remote accept before asserting the Orbit-side status
  update.
- `test/features/feed/presentation/screens/feed_wired_test.dart:2531-2551`
  proves Feed can show `IntroductionConnectionCard` when a `mutualAccepted`
  intro status change arrives.
- `test/features/introduction/presentation/widgets/intro_row_test.dart:65-76`
  covers the `Connected` label, but no current test directly asserts the
  `Waiting for <username>` state or the user-visible transition from waiting
  to connected on both peers.

## 5. Scope Clarification

- In scope: documenting the user-visible expectation that once both participants
  accept the same introduction, both sides converge on a completed connection
  state rather than a split `connected` / `waiting` outcome.
- In scope: the agreement between Orbit intro status, pending intro count, and
  feed connection surfacing for the same introduction after mutual acceptance.
- In scope: both role directions. The behavior should be correct whether the
  current user is the original recipient or the introduced friend.
- Out of scope: redesigning the intro UI, changing copy styling, or changing
  the visual design of the connection card.
- Out of scope: introduction picker filtering, batch intro sending, intro
  deletion behavior, notification badge design, or already-connected product
  rules beyond preserving their current behavior.
- Out of scope: determining whether the failure originates in transport
  delivery, listener processing, persistence, screen refresh, or another seam.
- Accepted ambiguity for later implementation: this spec does not claim the
  precise root cause. It only defines the observable bug and the user-visible
  completion contract that must hold.

## 6. Test Cases

### Happy Path

- `TC-38-HP-01` Given user-A introduces user-B to user-C, when user-B accepts
  first and user-C accepts second, then both user-B and user-C eventually stop
  showing `Waiting for ...` for that intro and both surfaces agree that the
  introduction completed.
- `TC-38-HP-02` Given the same introduction, when user-C accepts first and
  user-B accepts second, then both users still converge on the same completed
  connection state. Acceptance order must not matter.
- `TC-38-HP-03` Given both users accepted the same introduction, when each user
  returns to Feed and Orbit after the status sync settles, then Feed can show
  the introduction connection card and Orbit no longer treats that intro as a
  pending live intro on either device.
- `TC-38-HP-04` Given one user is already viewing Orbit Intros while the other
  person's acceptance arrives, when the remote acceptance is processed, then the
  visible row updates out of the waiting state without the user needing to
  perform the second acceptance again.

### Edge Cases

- `TC-38-EC-01` Given only one side has accepted so far, then the accepting user
  may still see `Waiting for <other user>`, and the other user can still see the
  actionable intro state. That single-sided waiting behavior remains valid.
- `TC-38-EC-02` Given one user already has the successful connection surfaced,
  when the other user reopens Orbit after both accepts are complete, then the
  stale `Waiting for ...` row does not persist across screen reload or app
  restart.
- `TC-38-EC-03` Given both users accepted and the contact has already been
  created from that intro, when either side reloads Feed or Orbit later, then
  the app does not resurrect the same intro as pending on that device.

### Regressions To Preserve

- `TC-38-RG-01` Given only one participant accepts, then the intro remains
  pending overall until the other participant responds. Single-sided accept must
  not prematurely become a completed connection.
- `TC-38-RG-02` Given one participant passes instead of accepting, then the intro
  still resolves as passed rather than connected.
- `TC-38-RG-03` Given an intro reaches `mutualAccepted`, then the existing
  completed-connection experience still works: the contact exists, the
  introduction-based connection card can surface, and the `Connected through
  <introducer>` conversation context remains intact.
- `TC-38-RG-04` Given an intro is truly still pending, then Orbit pending intro
  count and badge behavior remain truthful. Given an intro is truly completed,
  that same intro is no longer counted as pending on either side.

### Existing Coverage And Gaps

- Existing partial coverage: `test/features/introduction/application/mutual_acceptance_test.dart`,
  `test/features/introduction/integration/introduction_multi_node_test.dart`,
  `test/features/introduction/integration/introduction_smoke_test.dart`,
  `test/features/orbit/presentation/screens/orbit_intros_wiring_test.dart`,
  and `test/features/feed/presentation/screens/feed_wired_test.dart`.
- Current gap: no automated test in the repo currently proves the full reported
  user-visible outcome where both devices accept through the live flow and both
  Orbit surfaces converge without relying on manual
  `receiveAcceptNotification(...)` helper injection.
- Current gap: no direct widget assertion currently covers the `Waiting for
  <username>` copy or the waiting-to-connected UI transition for the same intro
  on both peers.
