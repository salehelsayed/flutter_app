# 39 - Introducer Intro Follow-up Copy And Completion Card Session Breakdown

## Decomposition artifact updated

- Artifact path:
  `Test-Flight-Improv/39-introducer-intro-follow-up-copy-and-completion-card-session-breakdown.md`
- Proposal/source doc path:
  `Test-Flight-Improv/39-introducer-intro-follow-up-copy-and-completion-card.md`
- Decomposition date:
  `2026-03-31`
- Downstream workflow rule:
  - detailed planning happens one session at a time
  - later sessions must be refreshed against landed code before execution

## Downstream execution path

- Session `1` should next run through:
  1. `$implementation-plan-orchestrator`
  2. `$implementation-execution-qa-orchestrator`
  3. `$implementation-closure-audit-orchestrator`
- Session `2` should next run through the same ordered pipeline after Session
  `1` lands and the plan is refreshed against current repo state:
  1. `$implementation-plan-orchestrator`
  2. `$implementation-execution-qa-orchestrator`
  3. `$implementation-closure-audit-orchestrator`

## Recommended plan count

- `2`
- The smallest safe split is one sender-side conversation-copy session and one
  introducer-side completion-card plus closure session.

## Session ledger

| Session ID | Title | Classification | Intended plan file | Depends on | Initial status |
| --- | --- | --- | --- | --- | --- |
| `1` | Truthful introducer conversation summary copy | `implementation-ready` | `Test-Flight-Improv/39-introducer-intro-follow-up-copy-and-completion-card-session-1-plan.md` | none | `pending` |
| `2` | Introducer completion card projection, live follow-up wiring, and report closure | `implementation-ready` | `Test-Flight-Improv/39-introducer-intro-follow-up-copy-and-completion-card-session-2-plan.md` | `1` | `prerequisite-blocked` |

## Overall closure bar

Report `39` is closed only when the introducer gets a truthful durable record
of what they sent and a durable visible result when that introduction succeeds,
without reopening protocol or participant-side introduction architecture:

- after user-A introduces user-C to user-B from the conversation with user-B,
  the durable conversation history names user-C rather than collapsing to
  `1 person`
- after user-A introduces multiple people to user-B, the durable conversation
  history shows a readable truthful multi-name summary instead of count-only
  copy
- when a user-A-created introduction later reaches `mutualAccepted`, user-A
  gets a persistent in-app completion card that clearly shows which introduced
  pair is now connected
- the persistent completion card remains discoverable after the transient
  notification is dismissed
- multi-intro sends do not blur different outcomes together; completed pairs
  stay distinguishable from pending, passed, or already-connected outcomes
- the existing participant-side connection card, intro-notification routing,
  and pending-intro truth remain intact
- the work stays inside existing Flutter intro/follow-up surfaces and local
  intro state; no new intro protocol, transport, or contact-creation contract
  is invented

## Source of truth

Primary governing docs:

- `Test-Flight-Improv/39-introducer-intro-follow-up-copy-and-completion-card.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/00-INDEX.md`
- `Test-Flight-Improv/29-batch-parallel-intro-sending-session-breakdown.md`
- `Test-Flight-Improv/34-orbit-intros-swipe-delete-missing-session-breakdown.md`
- `Test-Flight-Improv/38-mutual-intro-acceptance-leaves-one-side-waiting.md`

Current code and test seams that governed the split:

- `lib/features/conversation/presentation/screens/conversation_wired.dart`
- `lib/features/introduction/application/insert_intro_system_message.dart`
- `lib/features/introduction/presentation/widgets/intro_system_message.dart`
- `lib/features/introduction/presentation/screens/sent_confirmation_screen.dart`
- `lib/features/introduction/presentation/screens/sent_confirmation_wired.dart`
- `lib/features/introduction/application/introduction_listener.dart`
- `lib/features/introduction/presentation/screens/friend_picker_wired.dart`
- `lib/features/introduction/domain/repositories/introduction_repository.dart`
- `lib/features/introduction/domain/repositories/introduction_repository_impl.dart`
- `lib/features/feed/domain/models/feed_item.dart`
- `lib/features/feed/application/load_feed_use_case.dart`
- `lib/features/feed/application/feed_store.dart`
- `lib/features/feed/presentation/screens/feed_wired.dart`
- `lib/features/feed/presentation/screens/feed_screen.dart`
- `lib/features/feed/presentation/widgets/introduction_connection_card.dart`
- `lib/features/settings/presentation/screens/settings_wired.dart`
- `lib/features/settings/presentation/widgets/settings_introduction_debug_card.dart`
- `test/features/conversation/presentation/screens/conversation_overflow_intro_test.dart`
- `test/features/conversation/presentation/screens/conversation_wired_test.dart`
- `test/features/introduction/presentation/widgets/intro_system_message_test.dart`
- `test/features/introduction/presentation/screens/sent_confirmation_test.dart`
- `test/features/introduction/application/introduction_listener_test.dart`
- `test/features/feed/presentation/screens/feed_wired_test.dart`
- `test/features/feed/presentation/widgets/introduction_connection_card_test.dart`
- `test/features/orbit/presentation/screens/orbit_wired_test.dart`
- `test/features/orbit/presentation/screens/orbit_intros_wiring_test.dart`
- `test/features/introduction/integration/intro_wiring_smoke_test.dart`
- `test/features/introduction/integration/introduction_smoke_test.dart`
- `test/features/introduction/integration/introduction_multi_node_test.dart`
- `test/features/introduction/regression/introduction_regression_test.dart`
- `test/features/push/application/intro_notification_orbit_route_test.dart`

Source-of-truth conflicts and architectural constraints that shaped the split:

- current code beats the looser product phrasing: the only existing
  introduction-card layout lives on Feed, while the conversation surface
  currently persists intro follow-up as `transport = 'system'` text messages
  only
- the send path already has the introduced usernames available at the
  conversation boundary and on the transient confirmation screen, so the
  count-only conversation summary is a bounded copy-composition issue rather
  than a missing data or transport issue
- introducer-side intro rows already exist in local storage via
  `getIntroductionsByIntroducer(...)`, but they are only consumed by duplicate
  filtering and debug UI today, so the durable completion card is a follow-up
  projection/presentation problem rather than a missing persistence primitive
- current Feed connection items are contact-derived via `ConnectionFeedItem`,
  which means introducer-side completion surfacing is not a pure widget-only
  tweak; the projection/store/presentation seam should stay together in one
  session instead of splitting data and UI artificially
- no frozen named gate directly owns intro-to-Orbit / intro-to-Feed follow-up
  wiring today; `00-INDEX.md` and `test-gate-definitions.md` treat this area
  as a direct-suite plus `baseline` maintenance seam

## Evidence collector summary

- `ConversationWired` currently inserts the sender-side durable message as
  `You introduced $count $noun to ${_contact.username}` even though the same
  callback already has `List<IntroductionModel> intros` with the introduced
  usernames.
- `SentConfirmationScreen` already renders introduced usernames directly and
  already owns a bounded `and N more` overflow convention, which proves the
  username data and a readable multi-name summary pattern already exist in the
  repo.
- `IntroSystemMessage` already renders arbitrary intro-related strings, and its
  tests already cover both count-only and name-based copy.
- `IntroductionListener` already emits `introStatusChangedStream` and a local
  `New Connection` notification when an intro reaches `mutualAccepted`.
- the intro notification currently deep-links to Orbit `Intros`, but Orbit
  loads only pending or already-connected intros for the recipient or
  introduced party; it is not an introducer-history surface today.
- the current participant-side completion card is Feed-specific and contact-
  derived. That is useful reuse for card language/layout, but it does not by
  itself give the introducer a card because the introducer does not receive a
  new contact from the mutual-accept flow.
- sender-side intro rows already exist locally and are queryable through
  `getIntroductionsByIntroducer(...)`, which gives Session `2` a local state
  source to build on without inventing a new transport or DB primitive.
- `test-gate-definitions.md` and `00-INDEX.md` already classify intro follow-up
  work as direct `feed_wired` / `orbit_wired` / `orbit_intros_wiring` plus
  intro listener/regression/integration suites, with `baseline` as the
  companion top-level sanity gate.

## Closure mapper

- Real closure target:
  ship truthful sender-side intro history plus a durable introducer-visible
  completion card using existing intro follow-up semantics, without widening
  intro protocol or participant connection architecture.
- Correctness and reliability work:
  truthful one-name versus multi-name summaries, durable summary persistence,
  durable introducer-visible completion surfacing after mutual acceptance,
  stable distinction between completed and unresolved pairs, preserved
  participant-side connection card behavior, preserved notification routing,
  and preserved intro pending-truth semantics.
- Evidence-only or acceptance-only work:
  no separate evidence-only or closure-only session is required on current repo
  evidence; Session `2` can own final report closure and matrix updates once
  the introducer card lands.
- Explicit non-goals:
  no intro transport redesign, no new contact-creation rule for the introducer,
  no intro picker redesign, no reopening of Report `38` participant-side
  waiting-state scope, no Orbit loader expansion into an introducer history
  browser, and no frozen named-gate expansion unless execution adds a genuinely
  new high-value test path that must be classified.

## Session splitter

- Split result:
  Session `1` owns sender-side durable summary copy, and Session `2` owns the
  introducer-side persistent completion card plus final closure updates.
- Why this is the smallest meaningful set:
  the copy bug is a bounded conversation/message-history seam that can land
  safely before any card work, while the completion card is a separate
  follow-up projection/presentation seam that likely touches Feed- or
  equivalent card-host logic, intro follow-up wiring, and closure docs.

## Reviewer pass

- Sufficiency:
  `2` sessions are sufficient.
- Merge candidates:
  none. Merging both slices would combine a bounded conversation-copy change
  with a broader follow-up card/projection seam and weaken planning clarity.
- Required splits:
  none. There is no separate persistence or protocol slice because the repo
  already stores introducer rows and already emits mutual-accept listener
  updates.
- Missing tests or named gates:
  no missing gate definition at decomposition time, but Session `2` must honor
  the direct intro follow-up maintenance suite and should use the Feed gate if
  the current Feed card surface is the chosen host.
- Meaningful verified state:
  yes. Session `1` leaves the app in a truthful sender-history state, and
  Session `2` then completes the introducer follow-up contract and closes the
  report.
- Matrix responsibility:
  clear. Reuse this doc-scoped breakdown artifact plus `Test-Flight-Improv/00-INDEX.md`;
  do not invent a new matrix doc.
- Minimum safe session set:
  `2`.

## Arbiter outcome

- Structural blockers:
  none.
- Mergeable sessions:
  none.
- Required splits:
  none.
- Accepted differences:
  - the exact introducer host surface for the persistent completion card can
    stay a planning-time choice inside Session `2`, but it must remain an
    existing user-facing Flutter surface and must reuse current intro follow-up
    semantics rather than inventing a second protocol or notification-only
    state machine
  - `SentConfirmationScreen` remains a transient send-time confirmation surface
    and is not promoted into the durable completion surface
  - participant-side mutual-accept behavior from Report `38` stays separate and
    should not be silently folded into this report

## Ordered session breakdown

### Session 1

- Title:
  `Truthful introducer conversation summary copy`
- Session id:
  `1`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/39-introducer-intro-follow-up-copy-and-completion-card-session-1-plan.md`
- Exact scope:
  - replace the current count-only sender-side conversation summary with a
    truthful introduced-username summary when introductions are sent from the
    conversation with user-B
  - preserve correct single-name versus multi-name behavior, including a
    readable bounded summary for multiple introduced usernames
  - keep the stored row as a normal `transport = 'system'` conversation
    message and preserve the current conversation reload path after insertion
  - preserve the existing transient `SentConfirmationScreen` count and
    username-summary behavior; this session fixes durable conversation history,
    not the transient confirmation flow
  - keep intro overflow-menu visibility and send entry behavior unchanged
- Why it is its own session:
  - one bounded conversation/history seam
  - different direct regression family from introducer completion-card
    projection and follow-up wiring
  - can land in a meaningful verified state without deciding the persistent
    card host for Session `2`
- Likely code-entry files:
  - `lib/features/conversation/presentation/screens/conversation_wired.dart`
  - `lib/features/introduction/application/insert_intro_system_message.dart`
  - `lib/features/introduction/presentation/widgets/intro_system_message.dart`
    only if rendering assumptions need a narrow bidi or layout adjustment
  - `lib/features/introduction/presentation/screens/sent_confirmation_screen.dart`
    only if execution extracts or reuses the existing multi-name summary rule
    rather than duplicating it
- Likely direct tests/regressions:
  - `flutter test test/features/conversation/presentation/screens/conversation_overflow_intro_test.dart`
    or a new narrow sibling intro-summary test file if the current overflow test
    is too indirect
  - `flutter test test/features/conversation/presentation/screens/conversation_wired_test.dart`
    if the actual send callback or post-insert reload path is asserted there
  - `flutter test test/features/introduction/presentation/widgets/intro_system_message_test.dart`
  - `flutter test test/features/introduction/presentation/screens/sent_confirmation_test.dart`
    to preserve existing transient overflow-summary behavior
- Likely named gates:
  - no frozen named gate directly owns this seam
  - use the direct conversation/introduction presentation tests above
  - run `./scripts/run_test_gates.sh baseline` only if execution widens from
    bounded copy composition into broader conversation-screen or message-load
    wiring
  - do not widen into `1to1`; this session should not change shared durable
    send, retry, inbox, or transport behavior
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/39-introducer-intro-follow-up-copy-and-completion-card-session-breakdown.md`
  - do not update `Test-Flight-Improv/00-INDEX.md` yet unless execution
    unexpectedly lands the full report in one session
- Dependency on earlier sessions:
  - none

### Session 2

- Title:
  `Introducer completion card projection, live follow-up wiring, and report closure`
- Session id:
  `2`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/39-introducer-intro-follow-up-copy-and-completion-card-session-2-plan.md`
- Exact scope:
  - add a persistent introducer-visible completion card for a mutual-accepted
    introduction pair, using the existing introduction-card language/layout
    contract rather than a second notification-only summary
  - derive that card from existing local introducer-side intro state and
    mutual-accept follow-up events without widening intro transport or
    participant contact-creation rules
  - ensure the introducer can still revisit the completion result after the
    transient notification is gone
  - keep multiple introducer-created pairs distinguishable so one completed
    pair does not incorrectly imply that sibling pairs are also complete
  - preserve existing participant-side `IntroductionConnectionCard`,
    intro-notification routing, pending-intro truth, and blocked-accept /
    listener behavior
  - close Report `39` and refresh stable maintenance docs after the direct
    regressions pass
- Why it is its own session:
  - this is a separate intro follow-up projection and presentation seam from
    Session `1`'s sender-side copy fix
  - current repo evidence shows the card work is not widget-only; it likely
    needs coordinated projection/store plus UI surfacing
  - the direct regression family is different and broader: feed/orbit intro
    follow-up wiring, listener updates, and intro integration behavior
  - it can land as a meaningful verified state after Session `1` without
    reopening protocol or persistence architecture
- Likely code-entry files:
  - `lib/features/introduction/application/introduction_listener.dart`
  - `lib/features/introduction/domain/repositories/introduction_repository.dart`
  - `lib/features/introduction/domain/repositories/introduction_repository_impl.dart`
    only if execution needs a bounded introducer-side read helper or filtered
    application seam rather than ad-hoc screen queries
  - `lib/features/feed/domain/models/feed_item.dart`
  - `lib/features/feed/application/load_feed_use_case.dart`
  - `lib/features/feed/application/feed_store.dart`
  - `lib/features/feed/presentation/screens/feed_wired.dart`
  - `lib/features/feed/presentation/screens/feed_screen.dart`
  - `lib/features/feed/presentation/widgets/introduction_connection_card.dart`
    or a narrow sibling widget if the introducer card should stay visually
    aligned while carrying different data
  - conditional only if the chosen host is not Feed:
    `lib/features/conversation/presentation/screens/conversation_wired.dart`,
    related conversation presentation tests, and/or
    `test/features/push/application/intro_notification_orbit_route_test.dart`
- Likely direct tests/regressions:
  - `flutter test test/features/feed/presentation/screens/feed_wired_test.dart`
  - `flutter test test/features/feed/presentation/widgets/introduction_connection_card_test.dart`
    or a new sibling card test file if the introducer card should have a
    separate widget contract
  - `flutter test test/features/introduction/application/introduction_listener_test.dart`
  - `flutter test test/features/orbit/presentation/screens/orbit_wired_test.dart`
    and
    `flutter test test/features/orbit/presentation/screens/orbit_intros_wiring_test.dart`
    if follow-up freshness or notification-opened intro route behavior is
    touched while preserving current intro truth
  - `flutter test test/features/introduction/integration/intro_wiring_smoke_test.dart`
  - `flutter test test/features/introduction/integration/introduction_smoke_test.dart`
  - `flutter test test/features/introduction/integration/introduction_multi_node_test.dart`
  - `flutter test test/features/introduction/regression/introduction_regression_test.dart`
    for multi-pair and preserved follow-up behavior as needed
  - conditional:
    `flutter test test/features/push/application/intro_notification_orbit_route_test.dart`
    only if the notification-opened host or route contract is adjusted
- Likely named gates:
  - expected companion named gate:
    `./scripts/run_test_gates.sh feed` if the current Feed card surface is the
    chosen host or Feed card projection changes materially
  - regardless of host, no frozen named intro gate directly owns the follow-up
    seam; run the direct intro/orbit/feed maintenance suite called out in
    `Test-Flight-Improv/00-INDEX.md` and `test-gate-definitions.md`
  - run `./scripts/run_test_gates.sh baseline` as the companion top-level
    sanity gate for intro follow-up wiring work
  - run `./scripts/run_test_gates.sh completeness-check` only if execution adds
    a brand-new integration, cross-feature, or other explicitly classified
    test path that must be recorded in `test-gate-definitions.md`
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/39-introducer-intro-follow-up-copy-and-completion-card-session-breakdown.md`
  - `Test-Flight-Improv/00-INDEX.md`
  - `Test-Flight-Improv/test-gate-definitions.md` only if execution adds a
    new explicitly classified high-value test file
- Dependency on earlier sessions:
  - Session `1`

## Why this is not fewer sessions

- One session would bundle two different core seams:
  sender-side conversation summary composition and introducer-side durable
  completion-card projection/presentation.
- The direct regressions are materially different:
  Session `1` is anchored in conversation/introduction presentation tests,
  while Session `2` needs intro follow-up wiring, feed/orbit listener refresh,
  and intro integration coverage.
- Session `1` can land safely and truthfully on its own, which reduces later
  planning ambiguity for Session `2` instead of forcing one large plan to make
  copy, host-surface, projection, and closure decisions together.

## Why this is not more sessions

- No separate persistence session is needed because introducer rows already
  exist via `getIntroductionsByIntroducer(...)`.
- No separate protocol or listener-state session is needed because
  `introStatusChangedStream` and the mutual-accept notification already exist.
- No separate closure-only session is needed because Session `2` can honestly
  own the final direct regressions and `00-INDEX.md` refresh once the durable
  introducer card lands.
- No separate evidence-only host-selection session is needed because current
  repo evidence already bounds the likely host surfaces and the planner can
  choose within Session `2` without inventing new architecture.

## Regression and gate contract

- Cross-session source of truth:
  `Test-Flight-Improv/14-regression-test-strategy.md` and
  `Test-Flight-Improv/test-gate-definitions.md`.
- Intro follow-up maintenance rule:
  use the direct intro/orbit/feed maintenance suite plus `baseline` when intro
  follow-up wiring changes, exactly as recorded in
  `Test-Flight-Improv/00-INDEX.md`.
- Session `1` contract:
  stay out of frozen named gates unless execution widens beyond bounded
  conversation-summary composition; prefer direct presentation tests.
- Session `2` contract:
  run the direct intro follow-up suites, and use the Feed / Surface Gate if the
  current Feed card/projection seam is touched materially.
- Completeness rule:
  if execution adds a new high-value integration, cross-feature, lifecycle, or
  orchestration test file, classify it in `test-gate-definitions.md` and keep
  `./scripts/run_test_gates.sh completeness-check` green.

## Matrix update contract

- Existing stable matrix/closure doc for this area:
  `Test-Flight-Improv/00-INDEX.md`
- Session responsibility:
  Session `2` owns the final maintenance-time update because it is the first
  session that can honestly close the whole report.
- Artifact responsibility:
  this breakdown artifact must be updated after each executed session so the
  later pipeline has a stable reusable ledger.
- New matrix-doc rule:
  do not create a new matrix doc for this seam unless future repo evidence
  proves `00-INDEX.md` insufficient.

## Structural blockers remaining

- none

## Accepted differences intentionally left unchanged

- the repo keeps the existing transient `SentConfirmationScreen`; this report
  is about durable follow-up, not replacing the send-time confirmation surface
- participant-side mutual-accept connection behavior and waiting-state fixes
  remain governed by existing intro follow-up seams and Report `38`
- no new intro transport payload, no new contact type for the introducer, and
  no widening of Orbit pending-intro loading into a general introducer history
  browser are implied by this decomposition

## Exact docs/files used as evidence

- `Test-Flight-Improv/39-introducer-intro-follow-up-copy-and-completion-card.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/00-INDEX.md`
- `Test-Flight-Improv/29-batch-parallel-intro-sending-session-breakdown.md`
- `Test-Flight-Improv/34-orbit-intros-swipe-delete-missing-session-breakdown.md`
- `Test-Flight-Improv/38-mutual-intro-acceptance-leaves-one-side-waiting.md`
- `lib/features/conversation/presentation/screens/conversation_wired.dart`
- `lib/features/introduction/application/insert_intro_system_message.dart`
- `lib/features/introduction/presentation/widgets/intro_system_message.dart`
- `lib/features/introduction/presentation/screens/sent_confirmation_screen.dart`
- `lib/features/introduction/presentation/screens/sent_confirmation_wired.dart`
- `lib/features/introduction/application/introduction_listener.dart`
- `lib/features/introduction/presentation/screens/friend_picker_wired.dart`
- `lib/features/introduction/domain/repositories/introduction_repository.dart`
- `lib/features/introduction/domain/repositories/introduction_repository_impl.dart`
- `lib/features/feed/domain/models/feed_item.dart`
- `lib/features/feed/application/load_feed_use_case.dart`
- `lib/features/feed/application/feed_store.dart`
- `lib/features/feed/presentation/screens/feed_wired.dart`
- `lib/features/feed/presentation/screens/feed_screen.dart`
- `lib/features/feed/presentation/widgets/introduction_connection_card.dart`
- `lib/features/settings/presentation/screens/settings_wired.dart`
- `lib/features/settings/presentation/widgets/settings_introduction_debug_card.dart`
- `test/features/conversation/presentation/screens/conversation_overflow_intro_test.dart`
- `test/features/conversation/presentation/screens/conversation_wired_test.dart`
- `test/features/introduction/presentation/widgets/intro_system_message_test.dart`
- `test/features/introduction/presentation/screens/sent_confirmation_test.dart`
- `test/features/introduction/application/introduction_listener_test.dart`
- `test/features/feed/presentation/screens/feed_wired_test.dart`
- `test/features/feed/presentation/widgets/introduction_connection_card_test.dart`
- `test/features/orbit/presentation/screens/orbit_wired_test.dart`
- `test/features/orbit/presentation/screens/orbit_intros_wiring_test.dart`
- `test/features/introduction/integration/intro_wiring_smoke_test.dart`
- `test/features/introduction/integration/introduction_smoke_test.dart`
- `test/features/introduction/integration/introduction_multi_node_test.dart`
- `test/features/introduction/regression/introduction_regression_test.dart`
- `test/features/push/application/intro_notification_orbit_route_test.dart`

## Why the decomposition is safe to send into downstream planning/execution

- the split follows real repo seams rather than the number of product test
  cases
- each session ends in a meaningful verified state
- the gate contract is bounded and reuses existing intro follow-up maintenance
  rules instead of inventing a new gate
- matrix ownership is explicit
- no structural blocker remains before doc-scoped planning begins
