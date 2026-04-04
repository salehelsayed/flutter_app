# Session GM-010 Plan - Background notification

## Final verdict

`acceptance-only`

Current repo evidence suggests row `GM-010` is already proven at the repo-owned
notification seam:

- `test/features/push/application/show_notification_use_case_test.dart`
  already has `keeps group payload contract for local group notifications`,
  which runs with `AppLifecycleState.paused`, asserts exactly one notification,
  and verifies the correct group payload fields.
- The same file already has `shows notification when app is backgrounded`,
  confirming the background lifecycle path still shows a notification.
- `GM-010` is narrower than notification tap routing (`GM-011`) and does not
  require simulator tap/open evidence inside this row-owned repo-local proof.

The safest session is therefore to rerun the existing direct notification use-
case proof on the current repo state and close the row with evidence only if it
remains green.

## Final plan

### real scope

- Resolve source row `GM-010` only: `Background notification`.
- Prefer no production or test edits.
- Update only the row truth in
  `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md` and
  `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
  after exact evidence is verified.
- Do not widen into notification deep-link routing, message visibility after
  tap, or device-lab push transport behavior.

### closure bar

- There is direct automated proof that a group message in a backgrounded app
  produces exactly one notification with the correct group payload.
- The direct notification proof passes on the current repo state.

### source of truth

- Governing docs:
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`
  - `Test-Flight-Improv/14-regression-test-strategy.md`
- Current code and tests beat stale prose when they disagree.
- Verified seam files:
  - `test/features/push/application/show_notification_use_case_test.dart`
  - `lib/features/push/application/show_notification_use_case.dart`
  - `lib/core/notifications/flutter_notification_service.dart`

### session classification

`acceptance-only`

### exact problem statement

- The matrix row needs explicit row-owned proof that a backgrounded group
  message results in one correct notification.
- The repo appears to already prove that via the local notification use-case
  seam, but the row is not yet classified closed in the matrix and breakdown.

### files and repos to inspect next

- Primary proof target:
  - `test/features/push/application/show_notification_use_case_test.dart`
- Supporting production seam:
  - `lib/features/push/application/show_notification_use_case.dart`
  - `lib/core/notifications/flutter_notification_service.dart`

### existing tests covering this area

- `show_notification_use_case_test.dart` already verifies the paused-app group
  payload contract and background notification behavior.
- Missing only if audit proves it:
  - a row-owned closure note tying that proof to `GM-010`

### regression/tests to add first

- First try to close the row without code changes by rerunning the existing
  notification use-case tests.
- Only if the existing proof is ambiguous, add the narrowest row-owned
  assertion needed in the use-case tests.

### step-by-step implementation plan

1. Re-read the current notification use-case tests and confirm they still match
   the exact row contract.
2. Rerun the direct notification proof on the current repo state.
3. If the proof stays exact and green, move straight to doc refresh.
4. Only if a gap appears, add the narrowest missing assertion and stop.

### risks and edge cases

- Overclaim risk: do not treat notification-open routing as proof of
  backgrounded notification display.
- Scope risk: do not reopen `GM-011` deep-link behavior or broader push/device
  infrastructure.

### exact tests and gates to run

- Direct tests:
  - `flutter test --no-pub test/features/push/application/show_notification_use_case_test.dart`
- Named gates:
  - none unless a production-code change is required

### known-failure interpretation

- Treat missing notification display, wrong group payload, or duplicate
  notification count as current-session blockers.

### done criteria

- `GM-010` has exact row-owned background-notification proof.
- No broader notification behavior is reopened.
- The source matrix and breakdown can truthfully mark the row resolved.

### scope guard

- Non-goals:
  - notification tap routing
  - message visibility after notification open
  - device-lab APNs/FCM transport validation

### accepted differences / intentionally out of scope

- `GM-010` does not own notification deep linking or simulator tap handling.
- `GM-010` does not claim external push infrastructure proof beyond the
  repo-owned local notification seam.

### dependency impact

- A truthful `GM-010` resolution informs `GM-011`, but it does not
  automatically close notification deep-link routing.
