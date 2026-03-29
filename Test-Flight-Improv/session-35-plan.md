# Session 35 Plan — Remaining Intro-to-Orbit State Race After Blocked-Accept Fix

## Final Verdict

- `closed`
- Completion auditor result: Session 35 landed as a narrow Orbit intro-state
  closure, not a listener or protocol reopen.
- Closure reviewer result: the closure bar is met; this work should reopen only
  on real intro-to-Orbit or intro-to-Feed regressions.

## Closure Addendum

### What Landed

- `lib/features/orbit/presentation/screens/orbit_wired.dart` now versions intro
  reload publication with `_introLoadRequestId` so stale pending-intro loads
  cannot overwrite a later `mutualAccepted` reload.
- Local accept/pass callbacks in Orbit now await their final
  `_loadIntroductions()` call instead of leaving a fire-and-forget stale reload
  behind.
- `test/features/orbit/presentation/screens/orbit_wired_test.dart` now proves
  delayed mutual acceptance plus an immediate later block cannot repopulate
  `Intros`.
- `test/features/feed/presentation/screens/feed_wired_test.dart` now proves a
  delayed mutual acceptance still surfaces the connection card immediately and a
  later block update keeps operating on that same contact card.

### Tests And Gate Actually Run

Direct tests run:
- `flutter test test/features/orbit/presentation/screens/orbit_wired_test.dart`
- `flutter test test/features/orbit/presentation/screens/orbit_intros_wiring_test.dart`
- `flutter test test/features/feed/presentation/screens/feed_wired_test.dart`
- `flutter test test/features/introduction/application/introduction_listener_test.dart`
- `flutter test test/features/introduction/regression/introduction_regression_test.dart`
- `flutter test test/features/introduction/integration/introduction_smoke_test.dart`
- `flutter test test/features/introduction/integration/introduction_multi_node_test.dart`

Named gate run:
- `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline`

### Maintenance-Time Meaning

- `closed`: the stale intro reload seam on Orbit is closed.
- `accepted differences`:
  - Session 35 did not reopen `IntroductionListener`, intro protocol payloads,
    or the 30-day intro expiry rule.
  - no named gate directly owns intro-to-Orbit or intro-to-Feed follow-up
    regressions; maintenance safety stays with the direct intro/orbit/feed
    suites above plus the Baseline Gate.
- `residual-only`: reopen only if a real regression makes a
  `mutualAccepted` contact reappear under `Intros`, fails to surface the Feed
  connection card, or breaks the blocked-accept listener contract.

## Final Plan

### Real Scope

What changes:
- Keep the shipped listener fix intact.
- Fix the remaining intro follow-up synchronization bug on User-B/User-C
  surfaces after mutual acceptance, especially when the two accepts happen days
  apart but still within the current non-expired intro window.
- Add regression coverage at the Orbit wiring layer so stale intro reloads
  cannot repopulate Intros after the intro is already `mutualAccepted`.
- Add regression coverage at the Feed wiring layer so a `mutualAccepted` intro
  immediately surfaces the connection card and later block updates still apply
  correctly to that same contact.

What does not change:
- `IntroductionListener` block semantics for `send` vs `accept`/`pass`
- `handleIncomingIntroduction`
- `handleMutualAcceptance`
- `acceptIntroduction` protocol payloads, inbox fallback, or bridge crypto
- delete/archive/block product rules outside the intro-to-orbit surface update
- the existing 30-day intro expiry rule

### Closure Bar

- User-B no longer sees User-C under `Intros` after mutual acceptance has
  completed on User-B's device.
- Both sides get the new contact row / chat entry under Orbit immediately after
  mutual acceptance, even when the two accepts happened days apart, as long as
  the intro has not already been expired by the current 30-day rule.
- Both sides get the connection card under Feed immediately after mutual
  acceptance under that same non-expired intro window.
- A stale earlier pending-intro reload cannot overwrite the later
  mutual-acceptance reload in Orbit state.
- If User-B blocks User-C immediately after the mutual-acceptance contact
  appears, User-C remains treated as a contact on User-B's device and does not
  regress back into Intros.
- If either side blocks the other after the connection card/contact row appears,
  the existing block refresh path still updates the same contact cleanly on
  Feed and Orbit instead of regressing it into intro state.
- Existing blocked-accept listener regressions stay green.

### Source of Truth

- Current listener behavior wins over stale Session 35 prose:
  `lib/features/introduction/application/introduction_listener.dart`
- Current Orbit intro loading and stream handling:
  `lib/features/orbit/presentation/screens/orbit_wired.dart`
- Current Feed intro follow-up handling:
  `lib/features/feed/presentation/screens/feed_wired.dart`
- Pending-intro repository contract:
  `lib/features/introduction/application/load_introductions_use_case.dart`
- Contact-feed snapshot contract:
  `lib/features/feed/application/load_contact_feed_snapshot_use_case.dart`
- Existing listener regressions:
  `test/features/introduction/application/introduction_listener_test.dart`
- Existing blocked-accept regression:
  `test/features/introduction/regression/introduction_regression_test.dart`
- Existing intro happy-path expectation that pending intros are empty after
  mutual acceptance:
  `test/features/introduction/integration/introduction_smoke_test.dart`
- Existing Feed mutual-acceptance refresh test:
  `test/features/feed/presentation/screens/feed_wired_test.dart`
- Gate/source-of-truth file for named gates:
  `Test-Flight-Improv/test-gate-definitions.md`

On disagreement:
- current production code and direct tests beat stale plan prose
- `Test-Flight-Improv/test-gate-definitions.md` beats assumptions about named
  gates

### Session Classification

- `implementation-ready`

### Exact Problem Statement

The previous Session 35 plan targeted an early blanket block check in
`IntroductionListener`. That fix is already present:

- `lib/features/introduction/application/introduction_listener.dart` now parses
  the payload first and only blocks `payload.action == 'send'`
- `test/features/introduction/application/introduction_listener_test.dart`
  already verifies:
  - blocked `send` messages are rejected
  - blocked `accept` messages still complete the handshake
- `test/features/introduction/regression/introduction_regression_test.dart`
  already verifies the blocked-accept handshake path

The still-reported symptom is now more consistent with an Orbit state race.
This is an inference from current code and test gaps:

- `OrbitWired._loadIntroductions()` publishes intro state directly into
  `_introsCount`, `_groupedIntros`, and `_introducerUsernames`
- `_loadIntroductions()` is triggered from multiple places:
  - `initState`
  - `_loadIdentity`
  - `introReceivedStream`
  - `introStatusChangedStream`
  - `_onAcceptIntro`
  - `_onPassIntro`
- those call sites do not serialize or version intro reload results
- a slower earlier pending reload can therefore finish after a later
  mutual-acceptance reload and overwrite the UI back to stale `Intros`

That race matches the user-visible symptom better than the old listener-drop
root cause: User-B can briefly get the new connection/contact state, then still
see User-C under `Intros` because an older pending reload wins last-write.

Feed already has a direct intro follow-up hook via
`FeedWired._startListeningForIntroductions()`, which refreshes the introduced
contact snapshot on `mutualAccepted`. What is still missing is an explicit
regression contract that proves:

- late mutual acceptance still surfaces immediately on Feed and Orbit
- a later block/unblock update on that intro-created contact stays in the
  contact/block lane rather than regressing back into intro state
- the current 30-day expiry rule remains the boundary for how long pending
  intros can sit before the app is expected to stop following them up

### Files and Repos to Inspect Next

Production:
- `lib/features/orbit/presentation/screens/orbit_wired.dart`
- `lib/features/feed/presentation/screens/feed_wired.dart`
- `lib/features/introduction/application/load_introductions_use_case.dart`
- `lib/features/orbit/application/load_orbit_data_use_case.dart`
- `lib/features/feed/application/load_contact_feed_snapshot_use_case.dart`

Tests:
- `test/features/orbit/presentation/screens/orbit_wired_test.dart`
- `test/features/orbit/presentation/screens/orbit_intros_wiring_test.dart`
- `test/features/feed/presentation/screens/feed_wired_test.dart`
- `test/features/introduction/application/introduction_listener_test.dart`
- `test/features/introduction/regression/introduction_regression_test.dart`
- `test/features/introduction/integration/introduction_smoke_test.dart`
- `test/features/introduction/integration/introduction_multi_node_test.dart`

Docs:
- `Test-Flight-Improv/test-gate-definitions.md`
- `UI-20-Intro-friends/intro-feature-spec.md`
- `UI-8-Del-Archive/delete-block-spec.md`

### Existing Tests Covering This Area

Covered now:
- `test/features/introduction/application/introduction_listener_test.dart`
  proves blocked `send` is rejected and blocked `accept` still updates status
- `test/features/introduction/regression/introduction_regression_test.dart`
  Area 14 proves blocked-accept mutual acceptance completes
- `test/features/introduction/integration/introduction_smoke_test.dart`
  already expects pending intros to be empty after mutual acceptance completes
- `test/features/feed/presentation/screens/feed_wired_test.dart`
  already proves a `mutualAccepted` intro status refreshes only the new contact
  snapshot on Feed

Missing now:
- no deterministic test that an earlier stale pending intro reload cannot
  overwrite a later mutual-acceptance reload inside `OrbitWired`
- no `OrbitWired` widget regression for:
  - B accepts first
  - C accepts later
  - Orbit receives status update
  - B blocks immediately after contact appears
  - Intros must stay empty on B
- no explicit Feed regression for:
  - accepts happening days later within the non-expired intro window
  - the connection card appearing immediately for that late mutual acceptance
  - a later block/contact update still applying correctly to that same card
- no direct Orbit test that the connection remains a contact-surface concern
  rather than reappearing as an intro-row concern

Tests pinning intentional behavior:
- blocked contacts still remain a contact/block concern, not an intro retry
  concern
- already-connected intros may still appear in pending-intro loads by design;
  this session must not change that contract

### Regression / Tests to Add First

1. Add a deterministic `OrbitWired` widget regression with a delayed intro repo
   or controlled load gates:
   - first intro reload resolves with stale `pending`
   - second intro reload resolves with `[]` after mutual acceptance
   - final rendered state must keep `Intros` empty

2. Add a direct Orbit regression for the reported flow on User-B:
   - intro exists
   - B accepted earlier
   - incoming mutual-acceptance status arrives
   - contact refresh succeeds
   - B blocks C immediately
   - User-C is not rendered as a pending intro on B afterward

3. Add a direct Feed regression for the same class of follow-up:
   - mutual acceptance notification arrives after a delayed accept
   - Feed immediately renders the connection card for the new contact
   - a later contact update carrying `isBlocked: true` updates that same card
     instead of losing the intro-created connection surface

4. Keep the existing listener/regression suites in the direct run list to
   ensure the original blocked-accept fix is not regressed while stabilizing the
   Orbit surface.

### Step-by-Step Implementation Plan

1. Extend `test/features/orbit/presentation/screens/orbit_wired_test.dart`
   harness support so the widget can receive a fake `IntroductionRepository`
   and fake `IntroductionListener`.

2. Reuse or extend the existing Feed wiring harness in
   `test/features/feed/presentation/screens/feed_wired_test.dart` so delayed
   mutual-acceptance and later block updates are covered by direct widget
   regressions.

3. Add a failing regression that proves `OrbitWired` can currently publish stale
   pending intro state when intro reloads complete out of order.

4. Add a failing regression for the user flow on B's device:
   mutual acceptance reaches Orbit, then block immediately, and the intro row
   must not reappear.

5. Add a failing Feed regression proving that a delayed mutual acceptance still
   creates the connection card immediately and that a later block update keeps
   operating on that same connection item.

6. Patch `lib/features/orbit/presentation/screens/orbit_wired.dart` so intro
   reloads are monotonic from the UI's perspective.
   Preferred fix:
   - add an intro-load request token / generation counter
   - only publish `_introsCount`, `_groupedIntros`, and `_introducerUsernames`
     for the latest completed request

7. In the same file, make local accept/pass callbacks await the final
   `_loadIntroductions()` call so they do not leave an unnecessary fire-and-
   forget stale reload behind.

8. Re-run the new Orbit and Feed regressions plus the existing Session 35
   listener and introduction regressions.

9. Stop if the new regression disproves the stale-reload hypothesis. In that
   case, do not broaden into protocol work; reclassify the session with the new
   evidence first.

### Risks and Edge Cases

- Out-of-order async completion between:
  - one-sided accept reload
  - intro status stream reload
  - identity-load-triggered reload
- Accepts that happen days apart but still inside the current intro lifetime
- Mutual acceptance followed immediately by block/unblock
- Duplicate accept/status events from inbox replay or duplicate delivery
- `alreadyConnected` intro behavior must remain unchanged
- Orbit friend refresh and intro reload can both happen in the same frame; the
  final UI must prefer the newest intro state
- Pending intros older than 30 days still expire under current product rules;
  this session should not silently change that TTL

### Exact Tests and Gates to Run

Direct tests:
- `flutter test test/features/orbit/presentation/screens/orbit_wired_test.dart`
- `flutter test test/features/orbit/presentation/screens/orbit_intros_wiring_test.dart`
- `flutter test test/features/feed/presentation/screens/feed_wired_test.dart`
- `flutter test test/features/introduction/application/introduction_listener_test.dart`
- `flutter test test/features/introduction/regression/introduction_regression_test.dart`
- `flutter test test/features/introduction/integration/introduction_smoke_test.dart`
- `flutter test test/features/introduction/integration/introduction_multi_node_test.dart`

Named gates:
- No named gate in `Test-Flight-Improv/test-gate-definitions.md` directly owns
  intro/orbit surface regressions today.

Relevant classified direct suites from `Test-Flight-Improv/test-gate-definitions.md`:
- `test/features/introduction/integration/intro_wiring_smoke_test.dart`
- `test/features/introduction/integration/introduction_multi_node_test.dart`
- `test/features/introduction/integration/introduction_smoke_test.dart`

### Known-Failure Interpretation

- If listener tests fail, treat that as a regression of the already-landed
  Session 35 blocked-accept fix, not as proof the Orbit race is wrong.
- If the new Orbit regression fails before the production patch, that is the
  expected proof of the stale-state seam.
- If the new Orbit regression still fails after intro-load versioning, stop and
  inspect `OrbitWired._refreshOrbitFriend` ordering rather than reopening the
  intro protocol.
- Existing non-functional avatar download noise in intro tests is not the bug
  under investigation unless it turns the suite red.

### Done Criteria

- Session 35 plan no longer points at `IntroductionListener` as the remaining
  production fix target.
- `OrbitWired` prevents stale intro reloads from restoring pending rows after
  mutual acceptance.
- `FeedWired` has direct regression coverage proving late mutual acceptance
  surfaces the connection card immediately and later block updates still apply
  to that same intro-created contact.
- A direct regression covers the reported B/C accept-then-block flow.
- Existing blocked-accept listener and regression tests still pass.
- No protocol-layer or bridge-layer behavior changes are introduced.

### Scope Guard

- Do not reopen `IntroductionListener` block semantics unless a new failing
  regression proves the current code is wrong.
- Do not change `handleIncomingIntroduction`, `handleMutualAcceptance`, or
  `acceptIntroduction` in this session unless the new Orbit regressions prove
  the UI race theory false.
- Do not add retry, replay, or inbox redelivery features.
- Do not redesign Orbit, Intros, or block UX.
- Do not widen into feed cards, notifications, or conversation bootstrap unless
  a direct regression shows those surfaces are part of the same bug.
- Do not change the current intro expiry duration in this session.

### Accepted Differences / Intentionally Out of Scope

- Blocked friends remaining a contact-level concern rather than an intro-level
  concern stays unchanged.
- `alreadyConnected` intro behavior stays unchanged.
- Pending intros older than 30 days staying subject to expiry remains unchanged.
- The existing delete/archive/block product rules from
  `UI-8-Del-Archive/delete-block-spec.md` stay unchanged.
- Introduction protocol order independence and duplicate delivery rules stay
  owned by existing intro tests, not this session's production scope.

### Dependency Impact

- This plan unblocks reliable verification of intro-to-orbit state for future
  TestFlight intro fixes.
- If the intro-load race fix changes shape, later Orbit intro/regression work
  should reuse the same request-versioning pattern rather than adding more
  ad-hoc `setState` ordering.

## Structural Blockers Remaining

- None after this patch. The plan is narrow, regression-first, and has a clear
  stop rule if the inferred Orbit race is disproved.

## Incremental Details Intentionally Deferred

- Whether to add a separate performance-oriented Orbit intro test
- Whether to add per-peer refresh versioning for `_refreshOrbitFriend` before a
  regression proves it is needed

## Accepted Differences Intentionally Left Unchanged

- Session 35's original listener fix remains valid and should stay in place.
- No named regression gate is being widened in this session.

## Exact Docs / Files Used as Evidence

- `Test-Flight-Improv/session-35-plan.md` (stale prior contract)
- `lib/features/introduction/application/introduction_listener.dart`
- `lib/features/orbit/presentation/screens/orbit_wired.dart`
- `lib/features/feed/presentation/screens/feed_wired.dart`
- `lib/features/introduction/application/load_introductions_use_case.dart`
- `lib/features/feed/application/load_contact_feed_snapshot_use_case.dart`
- `test/features/introduction/application/introduction_listener_test.dart`
- `test/features/introduction/regression/introduction_regression_test.dart`
- `test/features/introduction/integration/introduction_smoke_test.dart`
- `test/features/orbit/presentation/screens/orbit_intros_wiring_test.dart`
- `test/features/orbit/presentation/screens/orbit_wired_test.dart`
- `test/features/feed/presentation/screens/feed_wired_test.dart`
- `Test-Flight-Improv/test-gate-definitions.md`
- `UI-20-Intro-friends/intro-feature-spec.md`
- `UI-8-Del-Archive/delete-block-spec.md`

## Why The Plan Is Safe To Implement Now

It is safe because it corrects the stale root-cause assumption first, keeps the
already-landed listener fix untouched, adds a deterministic failing regression
before the production patch, and limits production changes to the Orbit intro
state publication seam unless the new evidence proves that seam wrong.
