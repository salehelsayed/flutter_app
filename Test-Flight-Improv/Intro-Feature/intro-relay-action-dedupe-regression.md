# Intro Relay Action Dedupe Regression

## 1. Title and Type

- Title: Intro relay action dedupe regression protection
- Issue type: `feature-improvement`
- Output doc path: `Test-Flight-Improv/Intro-Feature/intro-relay-action-dedupe-regression.md`

## 2. Problem Statement

Users rely on the Introduction flow to carry multiple distinct messages for the
same introduction over time: the initial `send`, then later `accept` or `pass`
responses.

Today the client intentionally gives those messages distinct transport-level
IDs, but the repo does not directly prove at the relay/inbox layer that two
different intro actions for the same `introductionId` both survive dedupe.

From the user's perspective, if a later `accept` were ever treated like a
duplicate of the earlier `send`, the intro could stay stuck in a waiting state
even though one side already responded correctly.

## 3. Impact Analysis

- Who is affected: users whose intro messages depend on relay/inbox storage,
  replay, or retry rather than one live direct delivery path.
- When the issue appears: when two distinct intro actions for the same
  `introductionId` reach relay-backed inbox storage, especially across retries,
  reconnects, or offline drain.
- Severity: medium to high if the contract regresses, because dropped accept or
  pass messages can recreate the same class of stale intro state users already
  complain about.
- Frequency: not established by repo evidence. The current concern is missing
  regression proof, not a newly confirmed production incident.
- User-visible consequence: one intro step can be silently lost while the app
  still looks partially complete on one side and incomplete on the other.

## 4. Current State

- The client already scopes intro envelope IDs by action and sender through
  `IntroductionPayload.buildEnvelopeMessageId(...)` in
  `lib/features/introduction/domain/models/introduction_payload.dart`.
- The outbound intro delivery path normalizes every envelope with that scoped
  `messageId` before send or inbox fallback in
  `lib/features/introduction/application/introduction_outbound_delivery.dart`.
- Existing client tests already prove this contract locally:
  - `test/features/introduction/application/introduction_payload_test.dart`
    covers action-scoped intro envelope IDs and normalization of legacy or
    missing `messageId` fields.
  - `test/features/introduction/application/introduction_outbound_delivery_test.dart`
    proves `send` and `accept` for the same intro produce distinct transport
    IDs.
- The relay inbox dedupe code extracts IDs from top-level `messageId`, top-level
  `id`, top-level `msgId`, then falls back to `payload.id` and finally
  `payload.introductionId` in `go-relay-server/inbox.go`.
- Existing relay tests cover:
  - duplicate plaintext intro dedupe in
    `go-relay-server/inbox_dedup_test.go`
  - duplicate encrypted intro dedupe in
    `go-relay-server/inbox_dedup_test.go`
  - intro push routing in `go-relay-server/inbox_test.go`
- What is still missing is one direct relay-owned proof that:
  - two intro envelopes with the same `introductionId`
  - but different action-scoped `messageId` values
  - are both stored and not collapsed into one deduped record.

## 5. Scope Clarification

- In scope: preserving the observable contract that different intro actions for
  the same introduction remain independently deliverable through relay/inbox
  dedupe.
- In scope: plaintext and encrypted intro envelope behavior where relay storage
  or relay-side push routing matters.
- In scope: user-visible recovery safety when intro actions are replayed after
  reconnect or inbox drain.
- Out of scope: redesigning the intro protocol, changing the intro state
  machine, or changing client-side action semantics.
- Out of scope: changing how duplicate retries of the exact same intro action
  are deduped. Exact duplicates should remain deduped.
- Out of scope: Orbit copy, feed presentation, or any avatar and contact
  follow-up behavior.
- Accepted ambiguity for later implementation: this spec does not require a
  particular relay code change. It only requires repo-owned proof that the
  action-distinct intro message contract holds at the relay seam.

## 6. Test Cases

### Happy Path

- `TC-IRAD-HP-01` Given an intro `send` for `introductionId=X` is stored for an
  offline recipient, when a later `accept` for the same `introductionId=X`
  arrives with its own scoped message ID, then both intro steps remain
  available for later replay and are not collapsed into one record.
- `TC-IRAD-HP-02` Given the intro send and later accept are both replayed from a
  relay-backed inbox after reconnect, when the device drains the inbox, then
  the later accept is still processed as a distinct response and the intro can
  converge.

### Edge Cases

- `TC-IRAD-EC-01` Given two exact retries of the same intro `send` with the same
  transport-level ID, when both reach relay storage, then only one copy is
  retained. This spec does not weaken true duplicate dedupe.
- `TC-IRAD-EC-02` Given two exact retries of the same intro `accept` with the
  same transport-level ID, when both reach relay storage, then only one copy is
  retained.
- `TC-IRAD-EC-03` Given a plaintext intro envelope and an encrypted intro
  envelope both use valid action-scoped message IDs for the same introduction,
  when they reach relay storage in different scenarios, then each action stays
  independently dedupe-safe.

### Regressions To Preserve

- `TC-IRAD-RG-01` Given a duplicate plaintext intro envelope is stored twice,
  then relay dedupe still prevents duplicate storage for that exact same intro
  message.
- `TC-IRAD-RG-02` Given a duplicate encrypted intro envelope is stored twice,
  then relay dedupe still prevents duplicate storage for that exact same intro
  message.
- `TC-IRAD-RG-03` Given an intro push notification is built from a relay-stored
  intro message, then the push still routes to `intros` and keeps the existing
  generic intro copy contract.
- `TC-IRAD-RG-04` Given one side later accepts an intro after the original send
  already exists in relay-backed storage, then the later response is not dropped
  as if it were merely the original send repeated.

### Existing Coverage And Gaps

- Existing partial coverage:
  - `test/features/introduction/application/introduction_payload_test.dart`
  - `test/features/introduction/application/introduction_outbound_delivery_test.dart`
  - `go-relay-server/inbox_dedup_test.go`
  - `go-relay-server/inbox_test.go`
- Current gap:
  - no direct relay-owned test currently stores two different intro actions for
    the same `introductionId` and proves both survive dedupe because their
    transport-level `messageId` values are distinct.
- Preservation note:
  - the client-side contract already appears correct today; this spec is about
    preventing relay-layer regression and keeping the multi-step intro flow
    reliable under offline or replayed delivery.
