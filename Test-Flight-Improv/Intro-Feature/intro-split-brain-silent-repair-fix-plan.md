# Intro Split-Brain Silent Repair Fix Plan

## Final verdict

`implementation-ready`

The current repo already covers the basic intro accept/replay flow and the
current relay already suppresses visible push for `key_exchange_retry`
`contact_request` envelopes. The remaining gap is on the Flutter client:

- one side can remain on `accepted + pending` if the counterpart `accept` never
  lands locally, and
- a later intro-adjacent `contact_request` repair from the same peer is still
  interpreted as a fresh request when that contact does not yet exist locally.

That is narrow enough to fix without changing the relay architecture or the
intro product contract.

## Final plan

### Real scope

- Add intro-aware incoming `contact_request` recovery on the Flutter client for
  the specific case where:
  - the sender matches the other party of an existing intro,
  - the local user already accepted that intro, and
  - the local intro is still unresolved on the `pending + own side accepted`
    path.
- Heal that intro silently instead of surfacing a new contact request.
- Ensure Orbit and Feed refresh when that silent recovery happens so a visible
  `Waiting for ...` row clears without manual reload.
- Keep standard direct contact requests, standard intro accept/pass handling,
  and current relay push classification unchanged.

### Closure bar

This session is good enough when the repo has direct automated proof that:

- a user stuck on `Waiting for <peer>` can recover to a completed intro when
  the same peer later sends intro-adjacent repair traffic,
- that repaired intro truth is fully consistent:
  - both party statuses are correct,
  - the overall status converges to `mutualAccepted` for the pending split-brain
    case,
  - and the row no longer loads as pending intro UI for that user,
- that repair traffic does not create a pending contact request or emit the
  normal request presentation path on the receiver,
- legitimate non-intro contact requests still behave exactly as before,
- mixed sender styles are covered:
  - current sender with `intent=key_exchange_retry`,
  - older sender style without the retry intent,
- Orbit and Feed refresh out of the stale intro state when the recovery lands,
  and
- the intro gate stays green, with Go verification remaining conditional only if
  implementation work actually touches Go code.

### Source of truth

- Problem audit:
  `Test-Flight-Improv/Intro-Feature/_Intro-reliability-gap-audit.md`
- Existing user-visible bug spec:
  `Test-Flight-Improv/38-mutual-intro-acceptance-leaves-one-side-waiting.md`
- Intro matrix:
  `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules.md`
- Gate definitions:
  `Test-Flight-Improv/test-gate-definitions.md`
- Current intro convergence logic:
  `lib/features/introduction/application/accept_introduction_use_case.dart`
  `lib/features/introduction/application/handle_incoming_introduction_use_case.dart`
  `lib/features/introduction/application/handle_mutual_acceptance_use_case.dart`
- Current contact-request receive path:
  `lib/features/contact_request/application/handle_incoming_message_use_case.dart`
  `lib/features/contact_request/application/contact_request_listener.dart`
- Current follow-up wiring:
  `lib/features/orbit/presentation/screens/orbit_wired.dart`
  `lib/features/feed/presentation/screens/feed_wired.dart`
  `lib/main.dart`

When docs and repo evidence disagree, current code and tests win.

### Session classification

`implementation-ready`

### Exact problem statement

- User-visible behavior that is broken:
  - one side can still show `Waiting for <peer>` after both people have
    effectively moved on to the connected state,
  - the receiver can later see intro-adjacent repair traffic as a fresh
    connection request, which is noisy and misleading.
- Why that happens in current code:
  - intro completion is only derived from locally stored intro party statuses,
  - `contact_request` handling only distinguishes `already contact` vs `not yet
    contact`,
  - a stale pending contact-request row can currently short-circuit later
    traffic as `duplicateRequest` before any intro-aware recovery logic runs,
  - `contact_request` payloads do not carry `introductionId`, so a safe fix
    needs an explicit ambiguity rule for selecting a qualifying intro row,
  - if the receiver missed the counterpart `accept`, the later repair message
    has no intro-aware recovery branch and falls into the fresh-request path.
- Behavior that must improve:
  - intro-related recovery traffic must silently heal the stuck intro and the
    missing key/contact state instead of reopening the connect UX.
- Behavior that must stay unchanged:
  - stranger contact requests,
  - one-sided intro waiting before the other person has accepted,
  - pass behavior,
  - current relay-side `key_exchange_retry` suppression logic,
  - current deferred intro replay behavior.

### Files and repos to inspect next

Production files:

- `lib/features/contact_request/application/handle_incoming_message_use_case.dart`
- `lib/features/contact_request/application/contact_request_listener.dart`
- `lib/features/contact_request/application/recover_intro_contact_request_use_case.dart`
- `lib/features/introduction/application/handle_mutual_acceptance_use_case.dart`
- `lib/features/introduction/application/introduction_listener.dart`
- `lib/features/introduction/domain/models/introduction_model.dart`
- `lib/features/contact_request/application/resolve_contact_request_notification_target_use_case.dart`
- `lib/main.dart`
- `lib/features/orbit/presentation/screens/orbit_wired.dart`
- `lib/features/feed/presentation/screens/feed_wired.dart`

Reference-only predicate source for branch semantics only. Do not reuse this
verbatim because it lacks the plan's exact-one / ambiguity guard:

- `lib/features/introduction/application/resolve_unknown_inbox_sender_use_case.dart`

Test files:

- `test/features/contact_request/application/handle_incoming_message_use_case_test.dart`
- `test/features/contact_request/application/contact_request_listener_test.dart`
- `test/features/contact_request/application/recover_intro_contact_request_use_case_test.dart`
- `test/features/contact_request/application/resolve_contact_request_notification_target_use_case_test.dart`
- `test/features/contact_request/integration/contact_request_flow_test.dart`
- `test/features/orbit/presentation/screens/orbit_wired_test.dart`
- `test/features/feed/presentation/screens/feed_wired_test.dart`

### Existing tests covering this area

- Split-brain intro convergence is already covered in
  `test/features/introduction/integration/introduction_multi_node_test.dart`.
- Startup stale-row repair is already covered in
  `test/features/introduction/application/expire_old_introductions_use_case_test.dart`.
- The waiting label itself is already covered in
  `test/features/introduction/presentation/widgets/intro_row_test.dart`.
- Existing-contact key update without fresh request presentation is already
  covered in
  `test/features/contact_request/application/contact_request_listener_test.dart`
  and
  `test/features/contact_request/application/handle_incoming_message_use_case_test.dart`.
- Notification target fallback from request to conversation is already covered
  in
  `test/features/contact_request/application/resolve_contact_request_notification_target_use_case_test.dart`.

Missing coverage:

- no direct receiver-side regression where a stuck intro is healed by a later
  intro-peer `contact_request`,
- no direct proof that stale pending request rows are cleaned or bypassed so
  they do not force the later repair message down the `duplicateRequest` path,
- no direct proof that the same stale pending-request trap is avoided when the
  intro pair is ambiguous and the message must fall back to the normal
  contact-request path,
- no direct proof for the ambiguity rule when more than one unresolved intro
  for the same peer pair exists across different introducers,
- no proof that older sender style without `intent=key_exchange_retry` is
  still recovered silently when it clearly belongs to an unresolved intro,
- no direct proof for `message.from == 'unknown'` on the same recovery path,
- no direct proof that silent recovery preserves intro provenance on the
  recovered contact (`introducedBy`, `introducedByPeerId`) instead of degrading
  to a generic contact-request conversion,
- no direct proof that the repaired intro converges to fully consistent stored
  truth instead of merely moving to a non-pending label,
- no mounted Orbit/Feed proof that this silent recovery clears the waiting UI
  and refreshes follow-up surfaces,
- no direct proof that any new silent-recovery outcome is still covered by the
  v2 replay-cache path in the listener,
- no direct proof that fresh resend envelopes with different `msgId` values
  stay idempotent on the receiver.

### Regression/tests to add first

Add these failing regressions before implementation:

1. `test/features/contact_request/application/handle_incoming_message_use_case_test.dart`
   - verified qualifying message invokes the recovery callback before the
     existing `alreadyContact` / `duplicateRequest` short-circuits,
   - recovery result mapping is correct for:
     - silent recovery,
     - ordinary fallback to standard contact-request handling,
     - and invalid/no-match guard paths,
   - stale pending request rows do not trap a qualifying repair in
     `duplicateRequest`,
   - ambiguous intro-pair fallback is also protected from the same stale
     pending-request trap,
   - same scenario with sender style that lacks `intent=key_exchange_retry`,
   - same scenario with `message.from == 'unknown'`,
   - guard regression:
     - same sender without a qualifying intro,
     - or qualifying intro exists but local side has not accepted yet,
     - result must stay on the normal contact-request path.

2. `test/features/contact_request/application/recover_intro_contact_request_use_case_test.dart`
   - matching intro peer, local side already accepted, intro still pending,
     contact missing:
     - contact is recovered through the intro path,
     - intro provenance is preserved on the recovered contact,
     - both party statuses become `accepted`,
     - the overall status becomes `mutualAccepted`,
     - and the row leaves pending intro queries for that user,
   - same qualifying intro but local contact already exists and is missing the
     ML-KEM key:
     - the contact key is filled once,
     - provenance is preserved,
     - and the intro still converges silently,
   - same qualifying intro but local contact already exists and already has the
     ML-KEM key:
     - the existing key is not overwritten,
     - no duplicate contact is created,
     - and the intro still converges silently,
   - same scenario with a stale preexisting pending request row for that peer:
     - cleanup happens before the final outcome is returned,
   - ambiguity regressions:
     - when there is exactly one qualifying unresolved intro for the pair,
       recovery is allowed,
     - when there is more than one qualifying unresolved intro for the pair
       across different introducers,
       silent recovery is refused and the helper leaves a normal request path
       possible,
   - explicitly reuse `handleMutualAcceptance(...)` for the pending split-brain
     contact creation path.

3. `test/features/contact_request/application/contact_request_listener_test.dart`
   - intro-recovery path does not emit `requestStream`,
   - any new recovery outcome still records the v2 `msgId` in the replay cache,
   - it invokes the narrow intro-refresh callback exactly once with the
     recovered intro model,
   - when a qualifying repair creates or updates a contact, the recovered
     `ContactModel` is available for downstream refresh,
   - when a qualifying repair also fills a missing ML-KEM key, it still emits
     `contactKeyUpdatedStream`,
   - duplicate repair traffic stays idempotent for:
     - same-envelope replay,
     - and fresh resend envelopes with different `msgId` values.

4. `test/features/contact_request/integration/contact_request_flow_test.dart`
   - primary receiver-side proof using offline inbox replay plus
     `IncomingMessageRouter` and `ContactRequestListener`,
   - B is locally stuck on a waiting intro state,
   - C later sends intro-adjacent repair traffic,
   - B silently converges without surfacing a new request,
   - the repaired contact retains intro provenance,
   - the builder covers the current retry sender shape (`version: '2'`,
     `intent`) plus one older no-intent variant.

5. `test/features/orbit/presentation/screens/orbit_wired_test.dart`
   - mounted waiting row transitions out of the waiting state when silent intro
     recovery lands,
   - and the recovered contact/orbit surface refreshes from the same recovery.

6. `test/features/feed/presentation/screens/feed_wired_test.dart`
   - intro follow-up surfaces refresh from the same silent recovery path so the
     stale pending intro count / intro-follow-up state does not linger,
   - and include one case where the contact already exists and already has the
     ML-KEM key so the intro refresh path, not a contact-key update, proves the
     fix.

7. `test/features/contact_request/application/resolve_contact_request_notification_target_use_case_test.dart`
   - stale pending request row cleaned by the recovery path plus recovered
     contact resolves to `conversation`, not `pendingRequest`.

8. Only if implementation touches notification materialization or warm-push
   sequencing, extend
   `test/integration/contact_request_notification_dedupe_integration_test.dart`
   so a silently recovered contact never resolves back to a pending request
   target.

### Step-by-step implementation plan

1. Add the direct failing receiver-side regressions listed above.
2. Add a narrow verified-request recovery hook in the receive path. Exact seam:
   - `handleIncomingMessage(...)` gains a narrow optional callback such as
     `attemptSilentIntroRecovery(...)`,
   - invoke it after sender verification succeeds,
   - invoke it before the existing `alreadyContact` / `duplicateRequest`
     short-circuits,
   - keep the heavy intro-healing logic out of the parser by delegating through
     that one callback instead of injecting the full intro repo graph directly
     into the parser logic.
3. Pin the helper/use-case seam explicitly:
   - add a focused helper such as
     `lib/features/contact_request/application/recover_intro_contact_request_use_case.dart`,
   - let that helper own intro selection, ambiguity guard, stale pending-request
     cleanup decisions, intro truth convergence, and contact recovery,
   - explicitly reuse `handleMutualAcceptance(...)` for the pending split-brain
     contact creation path so provenance and intro system-message behavior stay
     aligned with the rest of the repo,
   - do not do a parser refactor or message reparse pass in this session.
4. Pin the result/event contract explicitly:
   - `ContactRequestListener` passes the recovery callback into
     `handleIncomingMessage(...)`,
   - the receive path returns one new silent-recovery outcome instead of
     overloading `alreadyContact` or `contactKeyUpdated`,
   - that outcome carries the recovered `IntroductionModel` plus the recovered
     or updated `ContactModel?`,
   - do not add a broader coordinator/event layer unless the implementation
     actually needs it.
5. In the helper/recovery branch:
   - look up only pending intros between `ownPeerId` and the verified sender,
   - allow silent recovery only when there is exactly one qualifying unresolved
     intro for the pair,
   - require that the local user already accepted that intro,
   - if more than one unresolved row exists for the pair across different
     introducers, refuse silent recovery and leave the standard
     contact-request path available,
   - protect that ambiguity fallback from stale pending-request rows so it does
     not disappear behind `duplicateRequest`,
   - refuse to mutate passed or expired rows,
   - reuse existing intro response application/derivation machinery instead of
     hand-rolling intro status mutation,
   - fully converge stored truth so party statuses and overall status agree on
     `mutualAccepted`,
   - preserve intro provenance on the recovered contact,
   - merge the incoming ML-KEM key only when the local contact is missing it;
     do not overwrite an existing key.
6. Reuse the existing contact-update wiring for contact-backed refresh only.
7. Keep intro refresh ownership on `IntroductionListener`, not a new public UI
   bus:
   - add the smallest emitter/helper needed on
     `lib/features/introduction/application/introduction_listener.dart`,
   - use `main.dart` only to wire the callback, not as the primary logic seam,
   - Orbit and Feed should continue to refresh from the existing introduction
     status stream they already own.
8. Ensure the listener replay-cache path treats the new recovery outcome like
   the existing v2 success/update outcomes so the same encrypted repair message
   does not re-trigger recovery churn, and prove idempotence for both replayed
   envelopes and fresh resend envelopes with different `msgId` values.
9. Add the primary receiver-side contact-request integration regression and the
   mounted Orbit/Feed follow-up regressions.
10. If the first direct regressions unexpectedly pass against current code,
   stop and verify deployed client/relay version skew before changing product
   code. That would mean the remaining problem is rollout-only, not repo-local.
11. After green, update the relevant Intro-Feature audit and test inventory
   docs so this bug is no longer tracked as an unowned seam.

### Risks and edge cases

- The recovery criteria can be too broad and accidentally swallow a legitimate
  first-time contact request. The guard must require:
  - matching verified sender,
  - exactly one eligible unresolved intro for the pair,
  - and local-side acceptance already present.
- More than one qualifying unresolved intro for the same pair across different
  introducers is an ambiguity case and must fall back to the normal
  contact-request path unless a smaller repo-backed tie-break rule proves safe.
- The receiver may already have the contact but still miss the intro state; the
  path must stay idempotent for:
  - `contact missing`,
  - `contact exists but key missing`,
  - and `contact exists with key already present`.
- Stale pending request rows must not trap either:
  - the silent-recovery path,
  - or the ambiguity fallback path.
- Older senders may not populate the retry `intent`; recovery must not rely on
  that field alone.
- Current relay suppression cannot unsend an already-fired visible push from an
  outdated deployment. Client recovery fixes the local UX after receipt, but
  rollout still needs relay parity.
- Duplicate repair traffic from resume/reconnect overlap or repeated retries
  with fresh `msgId` values must not create duplicate contacts, duplicate
  system messages, or duplicate refresh storms.
- Deferred intro-response replay must keep working; this session must not
  weaken the current accept/pass intro transport contract.
- Reusing `resolve_unknown_inbox_sender_use_case.dart` verbatim would be unsafe
  because it lacks the plan's exact-one / ambiguity guard.

### Exact tests and gates to run

Direct Flutter suites:

```bash
flutter test --no-pub \
  test/features/contact_request/application/handle_incoming_message_use_case_test.dart \
  test/features/contact_request/application/contact_request_listener_test.dart \
  test/features/contact_request/application/recover_intro_contact_request_use_case_test.dart \
  test/features/contact_request/application/resolve_contact_request_notification_target_use_case_test.dart \
  test/features/contact_request/integration/contact_request_flow_test.dart \
  test/features/orbit/presentation/screens/orbit_wired_test.dart \
  test/features/feed/presentation/screens/feed_wired_test.dart
```

Companion named gate:

```bash
./scripts/run_test_gates.sh intro
```

Optional direct companions only if the implementation touches those seams:

```bash
flutter test --no-pub \
  test/integration/contact_request_notification_dedupe_integration_test.dart \
  test/features/introduction/application/resolve_unknown_inbox_sender_use_case_test.dart
```

Relay verification is outside the required evidence for this Flutter-only fix.
Only run Go tests if the implementation actually changes Go code:

```bash
cd go-relay-server && go test ./...
```

If a new `integration_test/` file or newly classified optional/manual suite is
added as part of this work, also run:

```bash
./scripts/run_test_gates.sh completeness-check
```

### Known-failure interpretation

- Treat any new failure in the direct intro/contact-request regressions as a
  current-session bug.
- Treat any targeted relay failure as a blocker only if this session changes Go
  code. Existing local relay evidence should not block a Flutter-only fix.
- Treat notification or device-only failures caused only by deployed-version
  skew as a rollout blocker, not proof that the local repo implementation is
  wrong.

### Done criteria

- Receiver-side intro-aware recovery exists for qualifying intro-peer repair
  traffic.
- That recovery does not create a pending request or emit the normal request
  presentation path.
- B can no longer remain stuck on `Waiting for C` after the later intro-peer
  repair message lands.
- When the repaired row was a pending split-brain intro, stored truth converges
  fully:
  - both party statuses are correct,
  - the overall status is `mutualAccepted`,
  - and the row no longer appears in pending intro UI for that user.
- Recovered contacts keep intro provenance instead of degrading to a generic
  contact-request conversion.
- Orbit and Feed update from that silent recovery path.
- Legitimate stranger contact requests remain unchanged.
- Both current retry-intent and old-sender/no-intent repair styles are covered.
- Any stale pending request row for the same peer no longer traps the repair
  path in `duplicateRequest`, including the ambiguity fallback path.
- Any new v2 recovery outcome is covered by replay-cache handling and fresh
  resend idempotence.
- Notification target resolution prefers the recovered conversation after stale
  pending-request cleanup.
- Direct suites and `./scripts/run_test_gates.sh intro` are green.
- Optional notification-sequencing or Go verification is green if that extra
  surface was touched during implementation.

### Scope guard

- Do not block or redesign the intro picker based on missing ML-KEM keys in
  this session.
- Do not add new relay-side intro graph state or server-side recipient
  validation logic.
- Do not invent a brand-new intro-specific transport message type unless the
  receiver-side regressions prove the current verified `contact_request` path
  cannot support silent recovery safely.
- Do not reuse `resolve_unknown_inbox_sender_use_case.dart` verbatim for this
  fix because it does not enforce the required exact-one / ambiguity guard.
- Do not redesign copy, badges, or notification wording.

### Accepted differences / intentionally out of scope

- This session does not prevent an already-sent visible push from an outdated
  deployed relay or outdated sender build. It ensures the current client heals
  the state and suppresses local re-presentation once the message is handled.
- This session does not remove support for older intros that lack ML-KEM keys;
  it makes the recovery path safer when that legacy state still exists.
- This session does not widen into a separate intro-only harness or smoke path
  unless the direct contact-request regressions prove insufficient.

### Dependency impact

- Rollout still requires deployed relay parity with the current
  `key_exchange_retry` suppression already present in local `go-relay-server`.
- After implementation, Intro-Feature docs should explicitly own this seam so
  it is no longer split between the intro audit and the contact-request retry
  tests.
- If this session cannot safely distinguish intro repair from real first-time
  contact requests, later work will need a broader protocol-level recovery
  contract and this plan should be reopened instead of widened ad hoc.

## Structural blockers remaining

- None in the local repo. The main external dependency is deployment parity for
  the relay suppression that already exists locally.

## Incremental details intentionally deferred

- Picker/preflight product rules for introducing peers with missing ML-KEM
  state.
- Broader relay trust hardening for misaddressed client writes.
- Promotion of a separate intro-only harness when the direct contact-request
  regression already covers the seam.

## Accepted differences intentionally left unchanged

- Current relay classification remains envelope-type based.
- The intro model still derives completion from stored intro truth; this plan
  only adds one narrow recovery input that can safely complete that truth when
  a verified intro-peer repair message arrives after local acceptance.

## Exact docs/files used as evidence

- `Test-Flight-Improv/Intro-Feature/_Intro-reliability-gap-audit.md`
- `Test-Flight-Improv/38-mutual-intro-acceptance-leaves-one-side-waiting.md`
- `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `lib/features/introduction/application/accept_introduction_use_case.dart`
- `lib/features/introduction/application/handle_incoming_introduction_use_case.dart`
- `lib/features/introduction/application/handle_mutual_acceptance_use_case.dart`
- `lib/features/contact_request/application/handle_incoming_message_use_case.dart`
- `lib/features/contact_request/application/contact_request_listener.dart`
- `lib/features/contact_request/application/recover_intro_contact_request_use_case.dart`
- `lib/features/contact_request/application/resolve_contact_request_notification_target_use_case.dart`
- `lib/features/introduction/application/introduction_listener.dart`
- `lib/features/orbit/presentation/screens/orbit_wired.dart`
- `lib/features/feed/presentation/screens/feed_wired.dart`
- `lib/main.dart`
- `test/features/introduction/application/expire_old_introductions_use_case_test.dart`
- `test/features/contact_request/application/contact_request_listener_test.dart`
- `test/features/contact_request/application/handle_incoming_message_use_case_test.dart`
- `test/features/contact_request/application/recover_intro_contact_request_use_case_test.dart`
- `test/features/contact_request/application/resolve_contact_request_notification_target_use_case_test.dart`
- `test/integration/contact_request_notification_dedupe_integration_test.dart`

## Why the plan is safe to implement now

- The plan stays on one coherent seam: receiver-side recovery of intro-related
  repair traffic.
- It does not require relay architecture changes to close the local state bug.
- It explicitly preserves stranger contact-request behavior with narrow guards.
- It now asks for proof at the handler, listener, mounted UI, and receiver-side
  integration layers, with only notification-sequencing and Go verification
  remaining conditional when that extra surface is actually touched.
