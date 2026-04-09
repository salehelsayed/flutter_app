# 68 - Introduction Reliability Gap Audit

## 1. Title and Type

- Title: Introduction reliability gap audit
- Issue type: `bug`
- Output doc path: `Test-Flight-Improv/Intro-Feature/_Intro-reliability-gap-audit.md`

## 2. Problem Statement

The introduction feature is supposed to let an introducer connect two people and
then converge cleanly once the recipient and introduced user respond.

This audit groups the intro reliability gaps identified in the current repo and
in the recent review conversation. The most visible symptom is the reported
split-brain mutual-acceptance outcome where one user already sees the other as a
friend while the other user still sees `Waiting for ...`. The review also found
two adjacent reliability risks: a sender-side persistence window where outbound
intro delivery can survive without the sender's new local intro row, and a
post-mutual-acceptance avatar fetch that is only best-effort.

From the user's perspective, these gaps make introductions feel less
trustworthy than other core communication flows. The feature can look complete
on one device and incomplete on another, or complete without all expected
follow-up state being durable.

## 3. Impact Analysis

- Who is affected: introducers who send intros in batches, recipients and
  introduced users who accept across separate devices, and users who revisit the
  intro later after app resume or restart.
- When the issue appears: during mutual acceptance convergence, during sender
  restarts or crashes near intro creation, and after a connection is created but
  avatar follow-up work has not settled.
- Severity: moderate to high for the split `connected` / `waiting` outcome,
  because it breaks the trust contract of a social connection flow. Medium for
  sender-local persistence loss because the sender can lose local intro truth
  even when envelopes were staged. Low to medium for avatar follow-up because
  contact creation still succeeds, but the newly created connection can remain
  visually incomplete.
- Frequency: not established by repo evidence. Existing code and tests expose
  the seams and partial coverage, but the repo does not contain production
  frequency telemetry.
- User-visible consequences:
  - one side can see a completed connection while the other side still sees a
    pending intro,
  - a sender can potentially deliver an intro without preserving the expected
    new local intro row if the app dies in the wrong window,
  - a new contact can exist without its expected avatar follow-up ever
    completing.

## 4. Current State

### Group A: Mutual-acceptance convergence can still split across devices

- The current Orbit/Intro UI shows `Waiting for <username>` when the local
  user's own intro party status is already `accepted` but the overall intro
  status is still `pending`
  (`lib/features/introduction/presentation/widgets/intros_tab.dart`,
  `lib/features/introduction/presentation/widgets/intro_row.dart`).
- `acceptIntroduction(...)` only updates the local party status immediately. The
  other side's device only converges when it later processes the incoming
  `accept` payload through `handleIncomingIntroduction(...)`
  (`lib/features/introduction/application/accept_introduction_use_case.dart`,
  `lib/features/introduction/application/handle_incoming_introduction_use_case.dart`).
- `IntroductionModel.deriveStatus(...)` derives overall intro status only from
  `recipientStatus`, `introducedStatus`, and age. It does not derive from the
  fact that the contact already exists locally
  (`lib/features/introduction/domain/models/introduction_model.dart`).
- `alreadyConnected` is only set while storing the original incoming intro `send`
  when the target contact already exists at that time
  (`lib/features/introduction/application/handle_incoming_introduction_use_case.dart`).
- Startup repair only fixes stale rows whose stored party statuses already
  derive to a non-pending state, and only reruns contact creation when that
  derived state is `mutualAccepted`
  (`lib/features/introduction/application/expire_old_introductions_use_case.dart`).
- That means the reported user-visible split is plausible when one side already
  created the contact from mutual acceptance, but the opposite side never
  persisted or replayed the counterpart `accept` update and therefore remains on
  `accepted + pending`.
- Existing adjacent report: `Test-Flight-Improv/38-mutual-intro-acceptance-leaves-one-side-waiting.md`
  already documents the visible symptom. This audit keeps that bug in scope but
  groups it with the adjacent durability and coverage seams discovered during
  this review.
- Direct row-owned recovery proof landed on 2026-04-09 through the host-side
  `introduction_multi_node_test.dart` split-brain regression, the dedicated
  `INTRO_E2E_SCENARIO=split-brain ./smoke_test_friends.sh` three-simulator
  scenario, and a green rerun of `./scripts/run_test_gates.sh intro`.

### Group B: Sender-side intro durability gap was closed on 2026-04-09

- `sendIntroductions(...)` deletes any older intro row for the same pair before
  creating the new one
  (`lib/features/introduction/application/send_introduction_use_case.dart`).
- `_sendIntroductionChain(...)` now saves the new local
  `IntroductionModel` before outbound delivery staging begins
  (`lib/features/introduction/application/send_introduction_use_case.dart`).
- Each outbound delivery is durable at the envelope level because
  `deliverIntroductionPayloadReliably(...)` stages an
  `introduction_outbox_deliveries` row before send attempts
  (`lib/features/introduction/application/introduction_outbound_delivery.dart`).
- Resume and retrier wiring only retries those durable outbox deliveries
  (`lib/features/introduction/application/introduction_outbound_delivery.dart`,
  `lib/core/lifecycle/handle_app_resumed.dart`,
  `lib/core/services/pending_message_retrier.dart`,
  `lib/main.dart`).
- `send_introduction_test.dart` now includes a direct regression,
  `persists the sender local intro row before a later delivery-stage crash`,
  that forces a failure after one remote delivery has already succeeded and
  proves the sender-local row is still present.
- The row-owned acceptance evidence was completed with
  `INTRO_E2E_SCENARIO=repair ./smoke_test_friends.sh`,
  `./scripts/run_test_gates.sh intro`, and
  `FLUTTER_DEVICE_ID=347FB118-10D0-40C8-A05B-B0C3BD6B8CCD ./scripts/run_test_gates.sh transport`.
- This removes the previously open sender-local truth window without adding a
  separate outbox-to-intro reconstruction path.

### Group C: Post-mutual-acceptance avatar follow-up is only best-effort

- Once an intro reaches `mutualAccepted`, `handleMutualAcceptance(...)` creates
  the contact first and then starts avatar download as fire-and-forget work
  (`lib/features/introduction/application/handle_mutual_acceptance_use_case.dart`).
- The avatar path retries only once after a short delay and then swallows
  failure into an emitted flow event
  (`lib/features/introduction/application/handle_mutual_acceptance_use_case.dart`).
- This protects connection creation, which is good, but it does not provide a
  durable retry substrate comparable to the intro outbox or other recovered
  message flows.
- Existing coverage audit already records this as only partially covered with no
  smoke or e2e proof in the current tree
  (`Test-Flight-Improv/50-two-simulator-user-journey-tests-coverage-audit.md`).

### Group D: Coverage is strong around adjacent seams, but the exact grouped failures are still under-covered

- The intro test inventory is substantial and already includes unit,
  integration, regression, and three-simulator smoke entry points
  (`Test-Flight-Improv/_Intro-Tests.md`,
  `test/features/introduction/`,
  `test/features/introduction/integration/`).
- Existing tests already prove several adjacent contracts:
  - direct mutual acceptance state transitions,
  - deferred/out-of-order `accept` replay,
  - accept notification inbox fallback while peers are unreachable,
  - startup repair of stale `both accepted but still pending` rows,
  - and the waiting label itself in widget coverage.
- The remaining gaps are narrower and more specific:
  - no direct automated proof of the exact reported long-lived asymmetry where
    one side already has the contact while the other side still shows
    `Waiting for ...` after a later reopen or next-day resume,
  - no direct intro-specific top-level `integration_test/` acceptance journey;
    the top-level `integration_test/` tree currently includes intros routing
    smoke, but not a full intro handshake reliability journey,
  - no direct durable retry or reconciliation test for avatar download after
    mutual acceptance.

## 5. Scope Clarification

- In scope: documenting the grouped intro reliability gaps identified in this
  review, including user-visible split acceptance state, sender-local intro
  durability, and post-completion avatar follow-up reliability.
- In scope: the test-coverage picture for those gaps across unit, integration,
  smoke, and top-level `integration_test/` style evidence.
- In scope: the relationship between current intro UI behavior and the stored
  intro/contact state that drives it.
- Out of scope: proposing fixes, implementation sequencing, architecture
  changes, or rollout sessions.
- Out of scope: introduction picker filtering, intro swipe deletion, Orbit
  badge presentation, copy redesign, or unrelated feed/group reliability work.
- Out of scope: claiming production frequency or exact root-cause telemetry that
  the repo does not contain.
- Accepted ambiguity for later implementation: this audit does not claim that
  every listed gap has already reproduced in production. It records the current
  code and coverage seams that can affect intro reliability and that should be
  treated as open until explicitly closed.

## 6. Test Cases

### Happy Path

- `TC-68-HP-01` Given user-A introduces user-B to user-C, when both user-B and
  user-C accept the same intro in either order, then both devices eventually
  converge on the same completed intro state and neither device continues to
  show `Waiting for ...`.
- `TC-68-HP-02` Given both users accepted and the app is reopened later, then
  the intro still resolves as completed on both devices and does not regress
  back into a pending Orbit/Intros row.
- `TC-68-HP-03` Given the sender creates a new intro for a pair, then the
  sender's local intro record remains present and truthful even if delivery had
  to fall back to the durable outbox/retry path.
- `TC-68-HP-04` Given mutual acceptance creates a new contact, then the contact
  remains usable immediately and the follow-up avatar state eventually settles
  consistently instead of remaining indefinitely incomplete.

### Edge Cases

- `TC-68-EC-01` Given one side accepted yesterday and the opposite `accept`
  reaches the device only after a later resume/reopen, then the device repairs
  from `Waiting for ...` into the completed connection state without requiring a
  second manual accept.
- `TC-68-EC-02` Given one side already created the new contact from a mutually
  accepted intro, when that device or the opposite device reloads Orbit/Feed
  later, then the intro state and contact state do not disagree indefinitely.
- `TC-68-EC-03` Given the app stops after durable intro outbox rows were staged
  but before the sender finished saving the new intro row locally, then a later
  reopen still preserves or repairs the sender's local intro truth instead of
  losing the new intro locally.
- `TC-68-EC-04` Given avatar download fails during mutual-acceptance follow-up,
  then the new contact still exists and the app retains a recoverable path to
  settle the avatar later rather than silently abandoning it forever.

### Regressions To Preserve

- `TC-68-RG-01` Given only one participant has accepted so far, then the intro
  remains pending overall and `Waiting for ...` remains valid on the accepting
  side. This audit does not change the single-sided waiting contract.
- `TC-68-RG-02` Given one participant passes, then the intro still resolves as
  passed rather than connected.
- `TC-68-RG-03` Given an `accept` arrives before the intro `send`, then the
  existing deferred-response replay behavior still works and later converges
  correctly.
- `TC-68-RG-04` Given an intro is already truly completed, then Feed/Orbit
  still surface the completion correctly and do not recreate duplicate contacts
  or duplicate connection side effects.

### Existing Coverage And Gaps

- Existing partial coverage:
  - `test/features/introduction/application/accept_introduction_test.dart`
  - `test/features/introduction/application/handle_incoming_introduction_test.dart`
  - `test/features/introduction/application/introduction_listener_test.dart`
  - `test/features/introduction/application/introduction_outbound_delivery_test.dart`
  - `test/features/introduction/application/expire_old_introductions_use_case_test.dart`
  - `test/features/introduction/presentation/widgets/intro_row_test.dart`
  - `test/features/introduction/integration/introduction_smoke_test.dart`
  - `test/features/introduction/integration/introduction_multi_node_test.dart`
  - `Test-Flight-Improv/38-mutual-intro-acceptance-leaves-one-side-waiting.md`
  - `Test-Flight-Improv/50-two-simulator-user-journey-tests-coverage-audit.md`
- Covered on 2026-04-09: the repo now contains direct automated proof that one
  user can still show `Waiting for ...` while the opposite side has already
  connected, then later reconnect/restart heals that exact split.
- Current gap: current intro smoke guidance exists, but there is no explicit
  top-level `integration_test/` intro acceptance reliability journey in the
  checked-in `integration_test/` tree.
- Current gap: avatar follow-up after mutual acceptance is only partially
  covered today and lacks smoke/e2e proof for durable eventual settlement.
