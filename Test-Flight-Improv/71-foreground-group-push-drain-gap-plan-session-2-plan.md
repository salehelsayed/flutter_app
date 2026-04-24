# Session 2 Plan - Foreground integration proof and notification-matrix closure

## Final verdict

- Status:
  `accepted_with_explicit_follow_up`
- Last updated:
  `2026-04-22`
- Why:
  - `integration_test/foreground_group_push_drain_test.dart` now proves the
    four Report `71` foreground paths: targeted group drain, live-first
    no-duplicate behavior, preserved 1:1 drain routing, and no drain for post
    pushes.
  - `Test-Flight-Improv/52-notification-journey-test-matrix.md` now carries
    `JRN-FG-GRP-01`, and
    `Test-Flight-Improv/test-gate-definitions.md` now classifies the new
    foreground direct suites without widening the frozen named gates.
  - The acceptance run passed:
    `flutter test integration_test/foreground_group_push_drain_test.dart -d macos`,
    `flutter test test/integration/group_notification_dedupe_integration_test.dart`,
    `flutter test test/features/push/application/chat_and_group_push_open_flow_test.dart`,
    `flutter test test/features/push/application/handle_foreground_remote_message_use_case_test.dart`,
    and `./scripts/run_test_gates.sh groups`.
  - Remaining follow-up is explicit and non-blocking: one manual two-device
    mesh-gap smoke attestation and the post-land 48h TestFlight telemetry
    review.

## Final plan

### real scope

- Add `integration_test/foreground_group_push_drain_test.dart` with the four
  Report `71` scenarios:
  - foreground group push drains and surfaces the message
  - gossipsub-first then foreground push does not duplicate
  - foreground 1:1 push still uses the 1:1 drain path
  - foreground post push stays drain-free
- Reuse the existing fake group pubsub network, fake bridge, in-memory group
  repos, and fake notification service rather than inventing a new relay or UI
  stack.
- Update `Test-Flight-Improv/52-notification-journey-test-matrix.md` with the
  new `JRN-FG-GRP-01` row and evidence note.
- Update `Test-Flight-Improv/test-gate-definitions.md` so the new foreground
  direct suites are intentionally classified without widening frozen named
  gates.
- Close the report honestly by recording manual smoke and 48h TestFlight
  telemetry as explicit follow-up if they cannot be completed in this session.

Out of scope in this session:

- more production routing code unless the new integration proof exposes a real
  defect
- widening `scripts/run_test_gates.sh`
- inventing a new stable notification matrix or separate closure doc

### closure bar

- The new foreground integration test proves the relay-backed group drain path
  materializes the missed group message and exactly one in-app notification in
  a foreground session.
- The dedupe scenario proves a later foreground drain does not duplicate a
  message or local notification that already arrived live.
- The 1:1 and post parity scenarios prove the foreground router still honors
  the intended non-group behavior.
- `52-notification-journey-test-matrix.md` and
  `test-gate-definitions.md` truthfully describe the new coverage.
- Remaining manual two-device smoke and post-TestFlight telemetry are recorded
  as explicit follow-up, not implied complete.

### source of truth

- Governing docs:
  - `Test-Flight-Improv/71-foreground-group-push-drain-gap-plan.md`
  - `Test-Flight-Improv/71-foreground-group-push-drain-gap-plan-session-breakdown.md`
  - `Test-Flight-Improv/52-notification-journey-test-matrix.md`
  - `Test-Flight-Improv/test-gate-definitions.md`
  - `Test-Flight-Improv/14-regression-test-strategy.md`
- Current code and tests beat stale prose when they disagree.
- Verified repo seams:
  - `lib/features/push/application/handle_foreground_remote_message_use_case.dart`
  - `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`
  - `integration_test/group_recovery_e2e_test.dart`
  - `test/shared/fakes/group_test_user.dart`
  - `test/shared/fakes/fake_group_pubsub_network.dart`
  - `test/integration/group_notification_dedupe_integration_test.dart`
  - `test/features/push/application/chat_and_group_push_open_flow_test.dart`

### session classification

`implementation-ready`

### exact problem statement

- Report `71` is not honestly closed by unit/regression proof alone because the
  user-visible foreground gap is specifically about a foregrounded client
  draining the relay-backed group inbox and surfacing the missed message within
  the same session.
- The repo already has fake-network and fake-bridge group recovery harnesses,
  but no dedicated integration proof that foreground routing triggers the
  targeted group drain and respects the no-duplicate boundary.
- The stable notification docs currently have no row or direct-suite
  classification that names this foreground drain proof.

### files and repos to inspect next

- Test / harness files:
  - `integration_test/foreground_group_push_drain_test.dart`
  - `integration_test/group_recovery_e2e_test.dart`
  - `test/shared/fakes/group_test_user.dart`
  - `test/shared/fakes/fake_group_pubsub_network.dart`
  - `test/shared/fakes/fake_notification_service.dart`
  - `test/integration/group_notification_dedupe_integration_test.dart`
  - `test/features/push/application/chat_and_group_push_open_flow_test.dart`
- Docs:
  - `Test-Flight-Improv/52-notification-journey-test-matrix.md`
  - `Test-Flight-Improv/test-gate-definitions.md`
  - `Test-Flight-Improv/71-foreground-group-push-drain-gap-plan-session-breakdown.md`

### existing tests covering this area

- `group_recovery_e2e_test.dart` already proves fake-bridge group inbox drains,
  replay, and dedupe patterns with the same repo-owned fake infrastructure.
- `group_notification_dedupe_integration_test.dart` already proves the shared
  remote-announcement suppression boundary for later local group notifications.
- `chat_and_group_push_open_flow_test.dart` already proves the shared route
  preparation contract for group pushes and neighboring notification targets.
- Missing today:
  - no integration test that starts from the new foreground router and proves
    a relay-backed group drain surfaces the message in the same foreground
    session
  - no stable matrix row naming this exact foreground group drain journey
  - no explicit gate-doc classification for the new foreground direct suites

### regression/tests to add first

- Add `integration_test/foreground_group_push_drain_test.dart` first so the
  repo has the user-visible acceptance proof before the docs are updated.
- Keep the test on the existing fake group network / fake bridge stack so the
  scenario stays deterministic and local.
- Use the existing dedupe and notification-open suites as acceptance neighbors,
  not replacements for the new foreground drain test.

### step-by-step implementation plan

1. Build a small foreground-drain integration harness around the existing fake
   group network, fake bridge inbox pages, in-memory repos, and fake
   notification service.
2. Add the four Report `71` integration scenarios and get them green.
3. Run the exact direct tests below plus the `groups` gate.
4. Update `52-notification-journey-test-matrix.md` with the new
   `JRN-FG-GRP-01` row and truthful evidence note.
5. Update `test-gate-definitions.md` to classify the new foreground direct
   suites without widening frozen named gates.
6. Refresh the breakdown ledger and record the final report verdict as accepted
   or accepted_with_explicit_follow_up depending on the remaining manual /
   telemetry follow-up state.

### risks and edge cases

- Keep the new integration harness deterministic; do not rely on live EC2,
  real FCM delivery, or multi-device timing races.
- Make the dedupe scenario use the same message identity across live delivery
  and relay drain so the assertion proves the real duplicate boundary.
- Do not let the integration harness mutate production code just to make the
  test easy.
- Record manual two-device smoke and TestFlight telemetry honestly as external
  follow-up if they remain incomplete.

### exact tests and gates to run

- Direct tests:
  - `flutter test integration_test/foreground_group_push_drain_test.dart`
  - `flutter test test/integration/group_notification_dedupe_integration_test.dart`
  - `flutter test test/features/push/application/chat_and_group_push_open_flow_test.dart`
  - `flutter test test/features/push/application/handle_foreground_remote_message_use_case_test.dart`
- Named gates:
  - `./scripts/run_test_gates.sh groups`
  - do not rerun `baseline` unless this session unexpectedly touches Flutter
    production code

### known-failure interpretation

- The new foreground integration test has no accepted failure exemption.
- If `groups` fails, treat it as a blocker unless the failure is an unchanged
  pre-existing issue already documented in the current breakdown and clearly
  unrelated to this session's new test/doc work.
- If the new integration proof reveals a real production bug, stop and reopen
  the breakdown instead of hiding the need for more code under doc-only
  closure.

### done criteria

- `integration_test/foreground_group_push_drain_test.dart` exists and passes.
- The neighboring dedupe and notification-route direct suites pass.
- `./scripts/run_test_gates.sh groups` passes.
- `52-notification-journey-test-matrix.md` includes `JRN-FG-GRP-01`.
- `test-gate-definitions.md` classifies the new foreground direct suites
  without widening named gates.
- The breakdown ledger records the truthful final doc verdict.

### scope guard

- Do not widen named gates or change `scripts/run_test_gates.sh`.
- Do not add more production routing work unless the new integration proof
  reveals a real gap.
- Do not create a second notification matrix or a broad closure doc for this
  narrow report.

### accepted differences / intentionally out of scope

- Manual two-device smoke attestation remains external to repo-local CI and can
  finish as explicit follow-up.
- The 48h TestFlight telemetry requirement is a post-land monitoring step, not
  a repo-local gate.
- The session does not broaden into posts/intros/contact-request notification
  matrices beyond the parity assertions already named above.

### dependency impact

- A green Session `2` closes the current rollout unless the manual / telemetry
  follow-up forces `accepted_with_explicit_follow_up` instead of `closed`.
- If the integration harness reveals a production gap, the breakdown must
  reopen before any closure claim is made.
