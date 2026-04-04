# Session 9 Plan: Introduction notifications, conversation surfacing, and boundary coverage

## Real scope

- Close the remaining Session 9 coverage asks for `I-6.4`, `I-6.5`, `I-7.2`,
  `I-7.3`, `I-7.6`, `I-8.3`, `I-11.7`, `I-12.2`, `I-12.3`, `I-12.4`, and
  `I-13` from
  `Test-Flight-Improv/50-two-simulator-user-journey-tests-coverage-audit.md`.
- Revalidate the older boundary/UI audit against the current repo before
  adding any new tests:
  - delete-contact intro cleanup may already close `I-6.4`, `I-6.5`, and
    `I-12.2`,
  - intro flow-event logging already exists in production and may only need
    direct proof,
  - intro route/badge wiring is already stronger than the original audit for
    `I-7.1`, `I-7.4`, and `I-7.5`.
- Treat the still-real missing surface as:
  - local notifications for mutual acceptance and stacked incoming intros,
  - system-message insertion plus conversation-surface rendering/order,
  - v2 intro decrypt/key-mismatch failure handling,
  - migrated-schema intro persistence after the full upgrade path,
  - weird username fallback/rendering for null/empty and long intro names, and
  - one direct flow-event proof for the intro success/failure path.
- Keep the session test-first and test-only unless a failing proof exposes a
  real production bug.

## Closure bar

Session 9 is good enough when the repo has direct automated evidence that:

- intro send and mutual-accept flows show the intended local intro
  notifications, including stacked incoming intros,
- intro system messages are inserted with `transport = 'system'` and render as
  the intended conversation-surface system row rather than ordinary chat,
- a v2 intro decrypt/key mismatch is rejected cleanly without storing a bad
  introduction,
- post-migration intro persistence works on the fully upgraded schema,
- null/empty and long usernames render through the intro UI with honest
  fallbacks, and
- intro success/failure paths emit inspectable flow events.

Rows that are already honestly closed by current accepted evidence should be
recorded as such rather than duplicated with new tests.

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

When docs disagree with current repo evidence, repo evidence wins.

## Session classification

`implementation-ready`

## Exact problem statement

The current repo already has more Session 9 evidence than the old audit
recorded:

- `test/features/push/application/intro_notification_orbit_route_test.dart`
  already covers intro notification route targeting into Orbit.
- `test/features/orbit/presentation/screens/orbit_intros_wiring_test.dart`,
  `test/features/orbit/presentation/screens/orbit_wired_test.dart`, and
  `test/features/feed/presentation/screens/feed_wired_test.dart` already cover
  intro badge refresh, late mutual-accept surfacing, stale mutual-accept
  repair, and delete-row wiring on the Orbit/Feed side.
- `test/features/contacts/application/delete_contact_use_case_test.dart`
  already proves intro cleanup when a deleted peer is the recipient,
  introduced party, or introducer.
- Production intro flows already emit `[FLOW]` events via
  `emitFlowEvent(...)`; the missing part is direct proof that the important
  intro events are actually emitted on success/failure.

The audit is still right that the repo lacks direct notification-specific
proof for mutual acceptance and stacked intro arrivals, lacks a conversation
surface test for intro system rows, lacks an intro-specific v2 decrypt failure
proof, lacks a migrated-schema intro arrival proof, and lacks explicit weird
username rendering coverage.

The goal is to add only those missing proofs while honestly reclassifying any
delete/boundary rows already closed by current accepted evidence.

## Files and repos to inspect next

Primary direct tests:

- `test/features/introduction/application/introduction_listener_test.dart`
- `test/features/conversation/presentation/screens/conversation_screen_test.dart`
- `test/features/introduction/presentation/widgets/intro_row_test.dart`
- `test/features/introduction/presentation/widgets/intros_tab_extended_test.dart`
- `test/core/database/integration/full_migration_chain_test.dart`

Existing evidence to re-read before adding redundant tests:

- `test/features/contacts/application/delete_contact_use_case_test.dart`
- `test/features/orbit/presentation/screens/orbit_intros_wiring_test.dart`
- `test/features/orbit/presentation/screens/orbit_wired_test.dart`
- `test/features/feed/presentation/screens/feed_wired_test.dart`
- `test/features/push/application/intro_notification_orbit_route_test.dart`

Production files only if a failing proof exposes a real bug:

- `lib/features/introduction/application/introduction_listener.dart`
- `lib/features/introduction/application/insert_intro_system_message.dart`
- `lib/features/introduction/application/handle_incoming_introduction_use_case.dart`
- `lib/features/introduction/presentation/widgets/intro_row.dart`
- `lib/features/conversation/presentation/screens/conversation_screen.dart`

## Existing tests covering this area

- `intro_notification_orbit_route_test.dart` already covers notification open
  routing into Orbit.
- `orbit_intros_wiring_test.dart` already covers intro count refresh and
  accept-status stream delivery.
- `orbit_wired_test.dart` already covers intro delete confirmation, late
  mutual-accept surfacing, and stale mutual-accept row repair.
- `feed_wired_test.dart` already covers late mutual-accept card surfacing and
  the accepted difference that Feed shows a connection card instead of a
  notification-expanded intro card.
- `delete_contact_use_case_test.dart` already covers introduction cleanup for
  deleted peers across introducer/recipient/introduced roles.

## Regression/tests to add first

- Extend `introduction_listener_test.dart` with:
  - mutual-accept local notification proof,
  - stacked incoming intro notification proof,
  - v2 decrypt/key-mismatch rejection proof, and
  - flow-event capture for intro success/failure.
- Extend `conversation_screen_test.dart` with a system-message surface/order
  proof using `transport = 'system'`.
- Extend intro widget tests with null/empty and long-username rendering
  proofs.
- Extend `full_migration_chain_test.dart` with a migrated-schema introduction
  persistence proof after the full upgrade chain.
- Only add more delete-intro tests if the existing accepted delete evidence
  turns out not to close `I-6.4`, `I-6.5`, and `I-12.2` honestly.

## Step-by-step implementation plan

1. Tighten Session 9 against the current repo evidence listed above.
2. Add notification and decrypt-failure proofs to
   `introduction_listener_test.dart`.
3. Add one conversation-surface system-message render/order proof to
   `conversation_screen_test.dart`.
4. Add the smallest weird-username rendering proofs to intro widget tests.
5. Add one migrated-schema intro persistence proof to
   `full_migration_chain_test.dart`.
6. Re-run the exact direct Session 9 suites.
7. Run `./scripts/run_test_gates.sh 1to1` only if the final landed changes
   materially touch shared conversation surface behavior.
8. Run `./scripts/run_test_gates.sh baseline` only if execution touches app
   root/startup production paths.
9. Record delete-row closures by honest reclassification if the existing
   evidence is already sufficient.

## Risks and edge cases

- Notification tests should assert the actual generic notification title/body
  and payload, not only that a callback fired.
- The system-message proof must show the row is rendered through the system
  path, not merely that a message object can be stored.
- The decrypt/key-mismatch test must use the v2 intro envelope path and prove
  no bad introduction record is persisted.
- The migration proof should stay bounded to schema-readiness and persistence
  immediately after upgrade, not invent concurrent migration machinery that
  the repo does not currently model.
- Username rendering tests should close the real UI fallback contract instead
  of asserting arbitrary truncation details that are not part of the product
  contract.

## Exact tests and gates to run

Direct suites required for Session 9:

```bash
flutter test --no-pub test/features/introduction/application/introduction_listener_test.dart
flutter test --no-pub test/features/conversation/presentation/screens/conversation_screen_test.dart
flutter test --no-pub test/features/introduction/presentation/widgets/intro_row_test.dart test/features/introduction/presentation/widgets/intros_tab_extended_test.dart
flutter test --no-pub test/core/database/integration/full_migration_chain_test.dart
```

Required direct revalidation:

```bash
flutter test --no-pub test/features/contacts/application/delete_contact_use_case_test.dart
flutter test --no-pub test/features/push/application/intro_notification_orbit_route_test.dart test/features/orbit/presentation/screens/orbit_intros_wiring_test.dart test/features/orbit/presentation/screens/orbit_wired_test.dart test/features/feed/presentation/screens/feed_wired_test.dart
```

Conditional named gates:

```bash
./scripts/run_test_gates.sh 1to1
./scripts/run_test_gates.sh baseline
```

Run `1to1` only if final changes touch shared conversation/inbox behavior.
Run `baseline` only if final changes touch app-root/startup production paths.

## Known-failure interpretation

- Treat unrelated dirty-worktree failures as historical noise unless one of the
  exact Session 9 suites or a required gate fails.
- If a delete/boundary row closes by honest reclassification against current
  accepted evidence, record that explicitly instead of adding redundant tests.
- If a required row cannot be honestly closed without a product change, stop
  and record that as the real blocker instead of inflating the test harness.

## Done criteria

- Session 9 has direct proof or honest reclassification for `I-6.4`, `I-6.5`,
  `I-7.2`, `I-7.3`, `I-7.6`, `I-8.3`, `I-11.7`, `I-12.2`, `I-12.3`,
  `I-12.4`, and `I-13`.
- The exact direct Session 9 suites are green.
- Any conditional `1to1` or `baseline` gate run is green.
- No broader push architecture, unread badge redesign, or startup redesign was
  pulled in unnecessarily.
- The breakdown ledger is updated with the accepted outcome and exact evidence.
