# Session 1 Plan: Contact bootstrap and request replay journey coverage

## Real scope

- Close the Session 1 journey-evidence gaps for `1.1`, `1.2`, `1.3`, and `1.4`
  from `Test-Flight-Improv/50-two-simulator-user-journey-tests-coverage-audit.md`.
- Strengthen the current deterministic contact bootstrap evidence so one narrow
  direct suite proves request arrival, accept/decline handling, reconnect replay,
  and truthful post-accept surface state without requiring simulator camera
  automation or a new host orchestrator.
- Keep the session on contact bootstrap and request replay only. Do not widen
  into generic notification-open routing, later 1:1 thread behavior, or the
  speculative Session 51 command-executor design.

## Closure bar

Session 1 is good enough when the repo has direct automated evidence that:

- a new contact request can arrive and become pending,
- the accept path still creates the contact and enables the first handshake path,
- the decline path is exercised in a realistic follow-up journey rather than as
  an isolated unit behavior,
- incomplete key exchange or offline bootstrap replay is covered honestly, and
- Orbit/Feed-facing state remains truthful after the contact-bootstrap outcome.

The session does not need literal QR-camera automation. It needs honest
bootstrap-path proof using the repo's current deterministic helpers.

## Source of truth

- Active controller doc:
  `Test-Flight-Improv/50-two-simulator-user-journey-tests-todo-session-breakdown.md`
- Proposal/source doc:
  `Test-Flight-Improv/50-two-simulator-user-journey-tests-todo.md`
- Coverage matrix and gap statements:
  `Test-Flight-Improv/50-two-simulator-user-journey-tests-coverage-audit.md`
- Regression policy:
  `Test-Flight-Improv/14-regression-test-strategy.md`
- Gate source of truth:
  `Test-Flight-Improv/test-gate-definitions.md`

When docs disagree with code, current repo code and tests win. This session does
not change frozen gate definitions unless execution proves that a new permanent
direct suite must also be classified there.

## Session classification

`implementation-ready`

## Exact problem statement

The repo already has useful split coverage for contact bootstrap, but the
current evidence is fragmented:

- `1.1` has identity creation, contact acceptance, and first-message proof in
  `test/integration/onboarding_golden_path_test.dart`, but not one explicit
  bootstrap-focused flow that also proves post-accept surface truth.
- `1.2` has duplicate and already-contact handling in
  `test/features/contact_request/integration/contact_request_flow_test.dart`,
  but not a near-simultaneous dual-request race that proves stable outcome.
- `1.3` has a decline path, but not the exact "decline then later rescan/accept"
  follow-up journey.
- `1.4` has retry and inbox fallback coverage in
  `test/features/contact_request/integration/key_exchange_retry_flow_test.dart`,
  but not the exact new-contact bootstrap replay story the matrix calls out.

The goal is to add the smallest honest direct integration coverage needed to
close those gaps without changing unrelated bootstrap, startup, or notification
contracts.

## Files and repos to inspect next

Production files:

- `lib/core/debug/smoke_test_runner.dart`
- `lib/features/contact_request/application/send_contact_request_use_case.dart`
- `lib/features/contact_request/application/accept_contact_request_use_case.dart`
- `lib/features/contact_request/application/decline_contact_request_use_case.dart`
- `lib/features/contact_request/application/retry_incomplete_key_exchanges_use_case.dart`
- `lib/features/contact_request/application/handle_incoming_message_use_case.dart`
- `lib/features/orbit/presentation/screens/orbit_wired.dart`
- `lib/features/feed/presentation/screens/feed_wired.dart`

Primary direct tests:

- `test/features/contact_request/integration/contact_request_flow_test.dart`
- `test/features/contact_request/integration/key_exchange_retry_flow_test.dart`
- `test/integration/onboarding_golden_path_test.dart`
- `test/integration/contact_request_notification_dedupe_integration_test.dart`

Candidate adjacent checks if execution touches presentation truth:

- `test/features/orbit/presentation/screens/orbit_wired_test.dart`
- `test/features/feed/presentation/screens/feed_wired_test.dart`

## Existing tests covering this area

- `test/features/contact_request/integration/contact_request_flow_test.dart`
  already covers incoming request persistence, accept, decline, duplicate
  rejection, and already-contact rejection.
- `test/features/contact_request/integration/key_exchange_retry_flow_test.dart`
  already covers incomplete key-exchange retry, blocked-contact skip, and
  offline inbox storage shape.
- `test/integration/onboarding_golden_path_test.dart` already covers fresh
  identity creation, accepted contact request, and first encrypted message.
- `test/integration/contact_request_notification_dedupe_integration_test.dart`
  already covers replay-after-warm-push suppression and request materialization.

What is still missing is a tighter direct story for the matrix rows, especially
the mutual-request race, decline-then-rescan follow-up, and exact offline
bootstrap replay framing.

## Regression/tests to add first

- Add the smallest direct integration coverage to
  `test/features/contact_request/integration/contact_request_flow_test.dart`
  for:
  - near-simultaneous dual request / mutual-scan race behavior, if the current
    fake network harness can express it deterministically;
  - decline-then-second-request acceptance flow;
  - any missing bootstrap-state assertions needed to make Orbit/Feed truth
    explicit after accept/decline.
- Extend
  `test/features/contact_request/integration/key_exchange_retry_flow_test.dart`
  or add one adjacent narrow integration to prove the exact new-contact offline
  replay/bootstrap sequence if the current retry tests are still too abstract.
- Only add a presentation test if the matrix gap cannot be closed honestly from
  the existing integration surfaces.

## Step-by-step implementation plan

1. Re-read the Session 1 matrix rows and the four direct suites above to decide
   which gaps are genuinely still open in current code.
2. Prefer test-only strengthening first. If current production code already
   supports the missing journeys, add or extend the direct integrations without
   touching production.
3. If a coverage gap reveals a real bootstrap-state bug, make the smallest
   production fix in the contact-request/bootstrap seam only.
4. Run the direct Session 1 suites after each coherent landing.
5. If execution touched Orbit/Feed presentation truth, run the matching direct
   presentation suite.
6. Run `./scripts/run_test_gates.sh baseline` only if execution touched shared
   app-root, notification, or bootstrap wiring outside the narrow contact
   bootstrap seam.
7. Stop once the matrix rows have direct proof or are honestly shown to be
   already covered by the strengthened direct suites.

## Risks and edge cases

- Dual-request race tests can become flaky if they rely on timing instead of
  deterministic fake-network ordering.
- A bootstrap replay test can accidentally restate existing retry behavior
  without proving the new-contact journey the matrix is asking for.
- Orbit/Feed truth assertions can drag the session into broader presentation or
  notification-routing scope if not kept narrow.
- Shared bootstrap helpers may already be under active user edits in this dirty
  worktree; execution must accommodate existing changes rather than overwrite
  them.

## Exact tests and gates to run

Direct suites required for Session 1:

```bash
flutter test test/features/contact_request/integration/contact_request_flow_test.dart
flutter test test/features/contact_request/integration/key_exchange_retry_flow_test.dart
flutter test test/integration/onboarding_golden_path_test.dart
flutter test test/integration/contact_request_notification_dedupe_integration_test.dart
```

Run only if execution touches Orbit/Feed presentation files:

```bash
flutter test test/features/orbit/presentation/screens/orbit_wired_test.dart
flutter test test/features/feed/presentation/screens/feed_wired_test.dart
```

Run only if execution touches shared bootstrap, startup, or notification wiring:

```bash
./scripts/run_test_gates.sh baseline
```

## Known-failure interpretation

- Treat pre-existing unrelated red tests in the dirty worktree as historical
  noise unless the failing suite is one of the exact Session 1 commands above.
- Do not classify a pre-existing transport, intro, or notification failure as a
  new Session 1 regression unless the same changed files or direct commands tie
  it back to this seam.

## Done criteria

- Session 1 direct suites are green after the accepted landing.
- The direct coverage story for `1.1`, `1.2`, `1.3`, and `1.4` is materially
  stronger and honest against the coverage audit.
- No speculative simulator-camera or command-executor infrastructure was added.
- The breakdown ledger is updated with the session result and exact tests run.

## Scope guard

- No new host orchestrator, command-executor layer, or Session 51 infrastructure
  adoption.
- No reopening of stale Feed-targeted notification-open expectations.
- No widening into generic 1:1 message-state, intro, or transport-lifecycle
  work.
- No gate-definition refactor unless a gate file truly must change to classify a
  new permanent test.

## Accepted differences / intentionally out of scope

- Actual QR camera automation remains out of scope.
- Session 1 proves bootstrap truth with deterministic helpers, not with a real
  multi-simulator camera flow.
- Broader notification-open and feed-card routing differences remain for Session
  10 closure refresh, not this session.

## Dependency impact

- Session 1 has no prerequisite session dependency.
- Its outcome informs only the final Session 10 matrix refresh; it should not
  block Sessions 2 through 8 unless execution unexpectedly finds a shared
  bootstrap contract bug outside the stated scope.
