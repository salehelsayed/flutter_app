# Session UX-009 Plan: Local-relay / simulator exploratory push trigger path

## Final verdict

Reviewer result: sufficient with adjustments. Arbiter result: no structural blockers remain.

UX-009 is still an `evidence-gated` session, not a production-code session. The smallest safe repo-owned execution path is iOS-first on the exact simulator pair already owned by `reset_simulators.sh` (`347FB118-10D0-40C8-A05B-B0C3BD6B8CCD` + `5BA69F1C-B112-47BE-B1FF-8C1003728C8F`, with `1B098DFF-6294-407A-A209-BBF360893485` as spare), preceded by the existing direct push/open proofs and one simulator-backed `transport` gate run. Do not widen into full FCM/APNs delivery, Android parity, or new push automation unless the direct proofs expose a real repo-local mismatch.

## Final plan

### 1. real scope

- Collect row-owned evidence only for `UX-009` inside the narrowed simulator/local-relay boundary.
- Reconfirm the already-landed route/open behavior for `group_message` and `group_invite`.
- Run one manual exploratory proof on the listed iOS simulator targets and record whether the trigger/open behavior can be observed there.
- Do not change production code, notification architecture, relay/server code, or intro automation as part of this session.
- Do not broaden the row back into full real-device FCM/APNs delivery proof.

### 2. closure bar

- Existing direct push/open proofs are green on the current tree.
- The simulator-backed notification-open UI smoke runs on the chosen iOS targets.
- One same-environment `transport` gate run confirms the simulator/bridge/relay stack is healthy enough for exploratory work.
- An exploratory run on the iOS primary pair records observed behavior for both:
  - `group_invite` -> intros surface with the invite visible
  - `group_message` -> targeted group open after preparation/drain
- If simulator OS delivery cannot be observed even though route/open proofs remain green, the row stays honestly `evidence-gated` instead of reopening architecture or code scope.

### 3. source of truth

- Session contract:
  - `Test-Flight-Improv/Group-Chat-Feature/Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md`
- Source matrix row:
  - `Test-Flight-Improv/Group-Chat-Feature/Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md`
- Current inventory gap note:
  - `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- Current repo behavior and direct proofs:
  - `test/features/push/application/chat_and_group_push_open_flow_test.dart`
  - `test/integration/notification_deeplink_integration_test.dart`
  - `test/integration/notification_tap_smoke_test.dart`
  - `test/core/notifications/notification_push_tap_navigate_test.dart`
  - `integration_test/notification_open_ui_smoke_test.dart`
  - `integration_test/scripts/run_notification_open_ui_smoke.dart`
  - `lib/core/notifications/app_root_notification_open.dart`
  - `lib/core/notifications/notification_route_dispatch.dart`
  - `lib/features/push/application/prepare_notification_open_use_case.dart`
- Gate definitions:
  - `Test-Flight-Improv/test-gate-definitions.md`
  - `scripts/run_test_gates.sh`
- Simulator bootstrap helpers:
  - `reset_simulators.sh`
  - `smoke_test_friends.sh`
  - `integration_test/setup_device.dart`

On disagreement, current code/tests win over stale prose, and `Test-Flight-Improv/test-gate-definitions.md` plus `scripts/run_test_gates.sh` win over incidental notes about named gates.

### 4. session classification

`evidence-gated`

### 5. exact problem statement

The repo already proves push-open route extraction and prepare -> drain -> route sequencing for group and invite notification targets. What remains unproven for `UX-009` is the narrowed simulator/local-relay exploratory trigger path on the listed matrix devices. The user-visible behavior to confirm is:

- a backgrounded receiver can surface and open a `group_invite` notification into the intros surface
- a backgrounded receiver can surface and open a `group_message` notification into the targeted group after the group-specific drain path

What must stay unchanged:

- `group_invite` still maps to intros, not direct group navigation
- `group_message` still drains only the targeted group before route
- the session does not claim full FCM/APNs deliverability or Android+iOS parity

### 6. files and repos to inspect next

- First-pass evidence files:
  - `test/features/push/application/chat_and_group_push_open_flow_test.dart`
  - `test/integration/notification_deeplink_integration_test.dart`
  - `test/integration/notification_tap_smoke_test.dart`
  - `test/core/notifications/notification_push_tap_navigate_test.dart`
  - `integration_test/notification_open_ui_smoke_test.dart`
  - `integration_test/scripts/run_notification_open_ui_smoke.dart`
- Current routing helpers if the exploratory run contradicts the proofs:
  - `lib/core/notifications/app_root_notification_open.dart`
  - `lib/core/notifications/notification_route_dispatch.dart`
  - `lib/features/push/application/prepare_notification_open_use_case.dart`
- Environment/bootstrap helpers only as needed:
  - `reset_simulators.sh`
  - `smoke_test_friends.sh`
  - `integration_test/setup_device.dart`
  - `Test-Flight-Improv/test-gate-definitions.md`
  - `scripts/run_test_gates.sh`

Do not expand into unrelated group feature files unless the existing notification/open proofs are contradicted by the exploratory run.

### 7. existing tests covering this area

- `test/features/push/application/chat_and_group_push_open_flow_test.dart`
  - proves remote warm and terminated `group_message` opens only after group-specific drain
  - proves `group_invite` maps through the intros path rather than a direct group route
- `test/integration/notification_deeplink_integration_test.dart`
  - proves group push open follows prepare -> group drain -> route sequencing
  - proves local-notification group payload round-trips through open
- `test/core/notifications/notification_push_tap_navigate_test.dart`
  - proves route-target extraction for chat, group, and contact-request payloads
- `test/integration/notification_tap_smoke_test.dart`
  - broad notification-entry smoke across remote warm/cold and local tap entry points
- `integration_test/notification_open_ui_smoke_test.dart`
  - proves device/simulator UI routing for warm chat, cold chat, `group_invite` -> intros, and local chat
- `integration_test/scripts/run_notification_open_ui_smoke.dart`
  - provides the existing multi-device runner for the UI smoke

What is still missing:

- row-owned exploratory evidence on the listed simulator/emulator targets
- an automated device UI proof for `group_message` comparable to the existing `group_invite` UI smoke
- a row-owned note proving the simulator/local-relay trigger boundary without overstating it as full push-delivery proof

### 8. regression/tests to add first

- Default answer: none before the exploratory run.
- This session is evidence-only, so the first proof is to rerun the existing direct suites and simulator UI smoke.
- Only add a new test if the exploratory run contradicts the current repo truth:
  - add a narrow sequencing regression in `test/features/push/application/chat_and_group_push_open_flow_test.dart` or `test/integration/notification_deeplink_integration_test.dart` if mapping/drain order is wrong
  - add one narrow `integration_test/notification_open_ui_smoke_test.dart` case for `group_message` only if the bug is device-UI-specific and reproducible
- Do not create a new multi-device push harness under `UX-009`.

### 9. step-by-step implementation plan

1. Reconfirm the repo-owned notification/open seams with the direct suites listed below.
2. Run the existing notification-open UI smoke on the iOS primary pair to verify the current app-root/device-open harness still behaves on the exact row-owned targets.
3. Run one iOS simulator-backed `transport` gate preflight on a primary UX-009 target to prove the same environment can start, connect, and run real-stack transport tests before any manual push exploration.
4. Use `./reset_simulators.sh` as the default bootstrap path for UX-009 because it already:
   - targets the exact iOS matrix devices
   - pre-grants notification permission
   - builds, installs, and launches the app with `AUTO_SETUP_USERNAME` and `E2E_TEST_MODE`
5. Perform the manual exploratory run on `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD` + `5BA69F1C-B112-47BE-B1FF-8C1003728C8F`:
   - establish or confirm the relationship/group state in-app
   - background the receiver
   - trigger a `group_invite` flow and inspect whether the simulator surfaces/open path lands on intros with the invite visible
   - trigger a `group_message` flow and inspect whether the simulator surfaces/open path lands on the targeted group after the group drain
   - capture screenshots/logs/notes for both outcomes
6. Use `1B098DFF-6294-407A-A209-BBF360893485` only if one primary iOS simulator is unavailable or unstable.
7. Keep `smoke_test_friends.sh` and `integration_test/setup_device.dart` as fallback bootstrap helpers only if contact/identity setup is the blocker:
   - `smoke_test_friends.sh` already reuses `reset_simulators.sh` and seeds contacts during its handshake phase, but it is intro-specific and should not become the default UX-009 path
   - `integration_test/setup_device.dart` is only for narrow reseeding of a single device when a full reset is unnecessary
8. Stop and re-evaluate instead of coding if:
   - any direct notification/open proof fails
   - the `transport` gate fails on the same simulator environment
   - simulator notification delivery is the only thing missing while routing proofs remain green
   - the proof would require new relay hooks, Android-specific automation, or edits to intro/bootstrap scripts

### 10. risks and edge cases

- iOS simulator OS notification delivery can be flaky or absent even when app-owned route/open behavior is correct.
- `group_invite` intentionally routes to intros; treating “not the group screen” as a failure would be a false regression.
- `integration_test/notification_open_ui_smoke_test.dart` currently covers `group_invite` UI but not a device-level `group_message` UI case, so a green UI smoke run is necessary but not sufficient for row closure.
- `run_notification_open_ui_smoke.dart` runs devices sequentially, not as a live two-device push trigger harness.
- Android is an allowed matrix path, but the minimal repo-owned bootstrap discovered in this pass is iOS-first; choosing Android first would widen setup risk.
- Falling back to `smoke_test_friends.sh` adds intro-specific orchestration; use it only if manual pair setup is the real blocker.

### 11. exact tests and gates to run

Direct tests:

```bash
flutter test test/features/push/application/chat_and_group_push_open_flow_test.dart
flutter test test/integration/notification_deeplink_integration_test.dart
flutter test test/core/notifications/notification_push_tap_navigate_test.dart
flutter test test/integration/notification_tap_smoke_test.dart
```

Simulator/device UI smoke on the row-owned iOS pair:

```bash
dart run integration_test/scripts/run_notification_open_ui_smoke.dart -d 347FB118-10D0-40C8-A05B-B0C3BD6B8CCD,5BA69F1C-B112-47BE-B1FF-8C1003728C8F
```

Named gate preflight:

```bash
FLUTTER_DEVICE_ID=347FB118-10D0-40C8-A05B-B0C3BD6B8CCD ./scripts/run_test_gates.sh transport
```

Simulator bootstrap for the exploratory run:

```bash
./reset_simulators.sh
```

Fallback bootstrap commands only if setup becomes the blocker:

```bash
flutter test integration_test/setup_device.dart -d <device-id> --dart-define=USERNAME=<name>
```

Do not add `./scripts/run_test_gates.sh groups` or Android-specific commands to the default UX-009 run set unless the exploratory evidence shows a real need.

### 12. known-failure interpretation

- If any of the direct notification/open tests fail, treat that as a real repo regression that must be addressed before UX-009 evidence collection continues.
- If `run_notification_open_ui_smoke.dart` fails on a simulator while the direct suites pass, inspect simulator/build/environment state first; this file is an optional/manual direct suite, not a frozen named gate member.
- If `./scripts/run_test_gates.sh transport` fails on the same simulator environment, classify UX-009 as environment-blocked until transport health is restored; do not misclassify that as a group push-routing failure.
- If the OS banner or notification-center surface does not appear but the route/open proofs remain green, keep UX-009 `evidence-gated` and document the simulator limitation instead of reopening push architecture.
- If the observed result is “invite opens intros,” that matches the current repo contract and is not a failure.

### 13. done criteria

- The direct notification/open proofs above pass.
- The simulator/device UI smoke passes on the chosen iOS targets.
- One simulator-backed `transport` gate run passes on a primary iOS target.
- The manual exploratory run records observed outcomes for both `group_invite` and `group_message` on the listed iOS simulator environment.
- The row is updated later only with an honest narrowed-boundary result: either exploratory proof landed, or simulator/environment limitations blocked proof without exposing a repo-local behavior defect.

### 14. scope guard

- No full FCM/APNs or push-token registration work.
- No relay-server, bridge, or notification-payload redesign.
- No new Android automation or cross-platform parity requirement in this session.
- No edits to `reset_simulators.sh`, `smoke_test_friends.sh`, or the existing push/open harnesses just to make UX-009 easier.
- No intro feature work beyond optional bootstrap reuse if setup becomes the blocker.

### 15. accepted differences / intentionally out of scope

- iOS primary pair is the default path because the repo already owns exact bootstrap scripts for those devices; Android remains an alternate, not a requirement for UX-009 closure.
- The row is intentionally narrower than full real-device FCM/APNs delivery.
- `group_invite` opening intros is the intended behavior and stays unchanged.
- The repo does not yet own an automated multi-device `group_message` notification-trigger harness; manual exploratory evidence is acceptable before considering any further automation.

### 16. dependency impact

- If the exploratory iOS proof lands cleanly, later work only needs doc closure for UX-009 rather than new production sessions.
- If the exploratory run exposes a real route/open mismatch, the next session should reopen only the specific notification/open seam contradicted by the run.
- If the row remains blocked by simulator behavior rather than repo behavior, later work should keep it as evidence-only or external-device-lab work instead of widening this repo-owned session.

## Structural blockers remaining

- none

## Incremental details intentionally deferred

- Android-pair execution remains an alternate path, not part of the default UX-009 runbook.
- A future automated device-level `group_message` UI smoke may be useful, but it is not the minimum needed to execute UX-009 safely now.
- Optional bootstrap reuse from `smoke_test_friends.sh` is deferred unless setup becomes the blocker.

## Accepted differences intentionally left unchanged

- The row remains `evidence-gated`.
- iOS-first execution is preferred over Android-first because the exact repo-owned simulator bootstrap already exists there.
- The plan does not claim full push-trigger delivery parity outside the simulator/local-relay exploratory boundary.

## Exact docs/files used as evidence

- `Test-Flight-Improv/Group-Chat-Feature/Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md`
- `Test-Flight-Improv/Group-Chat-Feature/Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md`
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- `test/features/push/application/chat_and_group_push_open_flow_test.dart`
- `test/integration/notification_deeplink_integration_test.dart`
- `test/integration/notification_tap_smoke_test.dart`
- `test/core/notifications/notification_push_tap_navigate_test.dart`
- `integration_test/notification_open_ui_smoke_test.dart`
- `integration_test/scripts/run_notification_open_ui_smoke.dart`
- `lib/core/notifications/app_root_notification_open.dart`
- `lib/core/notifications/notification_route_dispatch.dart`
- `lib/features/push/application/prepare_notification_open_use_case.dart`
- `Test-Flight-Improv/test-gate-definitions.md`
- `scripts/run_test_gates.sh`
- `reset_simulators.sh`
- `smoke_test_friends.sh`
- `integration_test/setup_device.dart`

## Why the plan is safe or unsafe to implement now

This plan is safe to execute now because it does not invent new architecture, it starts from the existing repo-owned route/open proofs, it uses the current named `transport` gate as an environment preflight, and it chooses the iOS path where the exact matrix devices already have a maintained bootstrap script. It is intentionally not safe to declare UX-009 closed from tests alone: row closure still depends on a manual simulator/local-relay exploratory observation for `group_invite` and `group_message`, and the plan stops instead of widening scope if that observation is blocked by simulator delivery behavior rather than repo code.
