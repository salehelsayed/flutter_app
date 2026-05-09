# Group Invitation Status Copy And Actions Plan

Status: `execution-ready`

Session classification: `implementation-ready`

Created: 2026-05-09

## Planning Progress

- 2026-05-09 | Arbiter completed | Files inspected: `group_member_row.dart`, `group_info_screen.dart`, `group_info_wired.dart`, invite attempt model/repository, presentation tests, existing four-simulator invite-status runner, `_current-test-map.md`, and `test-gate-definitions.md`. Decision: plan is safe to execute as one narrow UI/copy/test-hardening session. Next action: execute with regression-first tests.

## Real Scope

Improve the user-facing invite status copy and action clarity in Group Info Members.

This session changes only:

- The visible queued label from `Invite queued` to `In their inbox`.
- The visible retry-needed label from `Needs resend` to `Resend needed`.
- The retry button text from `Send again` to `Resend`.
- The retry busy state from `Sending` to `Sending...`.
- The `Cannot send` row so it explains why the invite was not sent in user-understandable language.
- The associated host/widget tests and four-simulator status-matrix expectations.

This session does not change:

- Group invite wire protocol.
- Invite delivery semantics.
- Group membership semantics.
- Encryption/key formats.
- Relay/offline inbox behavior.
- The existing resend use case, except for user-facing result copy if needed.

## Closure Bar

The work is good enough when an admin can open Group Info Members and understand:

- `Invite sent`: the invite was sent directly.
- `In their inbox`: the invite is saved for the friend to receive when they open the app.
- `Resend needed`: the invite likely did not reach the friend and can be retried.
- `Cannot send`: the app could not prepare a secure invite, with a clear reason.
- `Joined`: the friend has accepted/joined.
- `Invite unknown`: the app has no local invite delivery evidence.

The session is complete only when host tests and the four-simulator display proof assert the new labels and cannot-send explanations.

## Source Of Truth

Current code and tests win over older docs. `Test-Flight-Improv/test-gate-definitions.md` is authoritative for named gates.

Primary production files:

- `lib/features/groups/presentation/widgets/group_member_row.dart`
- `lib/features/groups/presentation/screens/group_info_screen.dart`
- `lib/features/groups/presentation/screens/group_info_wired.dart`
- `lib/features/groups/domain/models/group_invite_delivery_attempt.dart`
- `lib/features/groups/domain/repositories/group_invite_delivery_attempt_repository.dart`
- `lib/features/groups/application/record_group_invite_delivery_attempts.dart`
- `lib/features/groups/application/resend_group_invite_use_case.dart`

Primary tests and simulator artifacts:

- `test/features/groups/presentation/group_info_screen_test.dart`
- `test/features/groups/presentation/group_info_wired_test.dart`
- `test/features/groups/application/resend_group_invite_use_case_test.dart`
- `integration_test/group_invite_status_matrix_harness.dart`
- `integration_test/scripts/run_group_invite_status_matrix_sim.dart`

Primary docs:

- `Test-Flight-Improv/_current-test-map.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/Group-Chat-Feature/group-invitation-status-regression-coverage-plan.md`

## Session Classification

`implementation-ready`

The data needed for the copy change already exists. `GroupInviteDeliveryAttempt.lastError` records codes such as `missing_secure_key`, `invalid_invite_payload`, `send_failed`, `node_not_running`, and `group_key_missing`. The Members UI already has status badges and conditional resend wiring.

## Exact Problem Statement

The current Members invite status labels are technically accurate but not clear enough for a normal user.

Current issues:

- `Invite queued` sounds like an internal app queue, not that the invite is saved in the friend's inbox.
- `Needs resend` is passive, even though the admin can take action from the row.
- The resend button says `Send again`, which is less direct than `Resend`.
- `Cannot send` gives no user-readable reason, even though the app persists failure information.

The behavior must improve without claiming facts the app cannot prove. In particular, do not say a friend blocked the user or uninstalled the app unless the app has explicit proof.

## Files And Repos To Inspect Next

Inspect these before coding:

- `lib/features/groups/presentation/widgets/group_member_row.dart`
  - Current badge labels and resend button text.
- `lib/features/groups/presentation/screens/group_info_screen.dart`
  - Current status map, resend button visibility, and row construction.
- `lib/features/groups/presentation/screens/group_info_wired.dart`
  - Current invite attempts/status loading and resend snackbar copy.
- `lib/features/groups/domain/models/group_invite_delivery_attempt.dart`
  - `lastError` availability.
- `lib/features/groups/application/record_group_invite_delivery_attempts.dart`
  - Source of persisted failure codes.
- `lib/features/groups/application/resend_group_invite_use_case.dart`
  - Source of resend result statuses and `group_key_missing`.
- `test/features/groups/presentation/group_info_screen_test.dart`
  - Current resend button visibility coverage.
- `test/features/groups/presentation/group_info_wired_test.dart`
  - Current full status matrix and wired loading coverage.
- `integration_test/group_invite_status_matrix_harness.dart`
  - Existing four-role seeded `GroupInfoWired` display proof.
- `integration_test/scripts/run_group_invite_status_matrix_sim.dart`
  - Existing four-simulator runner.
- `Test-Flight-Improv/_current-test-map.md`
- `Test-Flight-Improv/test-gate-definitions.md`

## Existing Tests Covering This Area

Already covered:

- `group_info_screen_test.dart` proves `Needs resend` currently shows a resend action only for the retry-needed status.
- `group_info_wired_test.dart` proves invite statuses load into Members rows.
- `group_info_wired_test.dart` includes a full status matrix for `Invite sent`, `Invite queued`, `Needs resend`, `Cannot send`, `Joined`, and `Invite unknown`.
- `resend_group_invite_use_case_test.dart` proves resend records `sent` and `needsResend` outcomes.
- `integration_test/scripts/run_group_invite_status_matrix_sim.dart` already provides four-simulator seeded creator-side display proof for the current labels.

Missing:

- Tests for the new user-facing labels.
- Tests for `Cannot send` reason copy by `lastError`.
- Tests that the resend button label and busy label are exactly `Resend` and `Sending...`.
- Wired tests for resend snackbar copy after each result.
- Four-simulator assertion updates for the new labels and cannot-send reason text.

## Regression/Tests To Add First

Add or update these before production edits:

1. `group_info_screen_test.dart`
   - Assert queued status renders `In their inbox`.
   - Assert needs-resend status renders `Resend needed`.
   - Assert only needs-resend rows show a `Resend` button.
   - Assert the button is disabled and displays `Sending...` when `isResendingInvite` is true.
   - Assert cannot-send rows show `Cannot send` plus a reason message.

2. `group_info_wired_test.dart`
   - Update the full status matrix to expect:
     - `Invite sent`
     - `In their inbox`
     - `Resend needed`
     - `Cannot send`
     - `Joined`
     - `Invite unknown`
   - Add cannot-send reason cases for:
     - `missing_secure_key`
     - `invalid_invite_payload`
     - `group_key_missing`
     - unknown or null fallback.
   - Add resend interaction tests that tap `Resend` and assert snackbar copy for:
     - `sent`
     - `queued`
     - `needsResend`
     - `cannotSend`

3. `integration_test/group_invite_status_matrix_harness.dart`
   - Update creator assertions to the new labels.
   - Add assertion for cannot-send reason text.
   - Keep `relayLifecycleProof: false`; this is a display proof, not a real relay proof.

## Step-By-Step Implementation Plan

1. Add a small presentation helper for status copy.

   Recommended file:

   - `lib/features/groups/presentation/group_invite_status_presentation.dart`

   It should map `GroupInviteDeliveryStatus` plus optional `lastError` to:

   - badge label
   - optional detail text
   - action label
   - snackbar message helper if useful

2. Keep user-facing copy in presentation code.

   Do not add UI strings to domain models. Domain should keep status enum values and raw `lastError` codes.

3. Extend Members row inputs so `lastError` can reach the row.

   Current `GroupInfoScreen` receives only `inviteStatusesByPeerId`. Add a minimal way to pass the full invite attempt or reason by peer ID, for example:

   - `inviteAttemptsByPeerId`, or
   - `inviteFailureReasonsByPeerId`.

   Prefer passing full attempts only if it avoids duplicate maps and stays simple.

4. Update `GroupInfoWired` to retain invite attempts by peer ID.

   It already loads attempts to compute timestamp-aware status. Preserve that behavior and expose the relevant attempt data to the screen.

5. Update `GroupMemberRow`.

   Label mapping:

   - `sent`: `Invite sent`
   - `queued`: `In their inbox`
   - `needsResend`: `Resend needed`
   - `cannotSend`: `Cannot send`
   - `joined`: `Joined`
   - `unknown`: `Invite unknown`

   Button mapping:

   - idle retry action: `Resend`
   - busy retry action: `Sending...`

6. Add cannot-send details.

   Recommended detail text:

   - `missing_secure_key`: `We don't have the secure info needed to invite this friend. Ask them to open or reinstall the app, then try again.`
   - `group_key_missing`: `This group is missing the secure invite key. Reopen the app and try again.`
   - `invalid_invite_payload`: `This invite could not be prepared. Reopen the app and try again.`
   - fallback: `We could not prepare a secure invite for this friend. They may need to open or reinstall the app before you can invite them.`

   Do not show raw error codes.

7. Update resend snackbar copy.

   Recommended messages:

   - `sent`: `Invite sent to <name>`
   - `queued`: `Invite is in <name>'s inbox`
   - `needsResend`: `Invite still needs to be resent`
   - `cannotSend`: use the same user-readable reason family, shortened if needed
   - `joined`: `<name> already joined`
   - `unknown`: `Invite status unknown`

8. Update tests in the same pass as any constructor or map-seam changes.

   The seam change must update:

   - caller side
   - callee side
   - direct widget tests
   - wired tests
   - simulator harness assertions

9. Update documentation if label references are stale.

   At minimum, inspect and update:

   - `Test-Flight-Improv/_current-test-map.md`
   - `Test-Flight-Improv/test-gate-definitions.md`
   - this plan's execution progress if executed by the execution QA orchestrator

10. Stop if evidence disproves the need for a production seam change.

   If `lastError` is already available in a simpler way during implementation, use the smaller route and document it.

## Risks And Edge Cases

- Constructor or map seam drift between `GroupInfoWired`, `GroupInfoScreen`, and `GroupMemberRow`.
- Long cannot-send reason text may wrap poorly on mobile.
- The resend button and remove/admin action row can become crowded.
- `lastError` can be null or unknown for legacy rows.
- `Cannot send` should not imply the friend blocked the user.
- `In their inbox` should not imply the friend has opened or accepted the invite.
- Resend success can become either direct `sent` or inbox `queued`; both are successful delivery outcomes.
- Four-simulator runner is seeded display proof. It should not overclaim organic transport lifecycle proof.

## Exact Tests And Gates To Run

Direct host tests:

```bash
flutter test test/features/groups/presentation/group_info_screen_test.dart
flutter test test/features/groups/presentation/group_info_wired_test.dart
flutter test test/features/groups/application/resend_group_invite_use_case_test.dart
```

Named group gate:

```bash
./scripts/run_test_gates.sh groups
```

Four-simulator proof:

```bash
dart run integration_test/scripts/run_group_invite_status_matrix_sim.dart \
  -d <creator_sim>,<accepted_one_sim>,<accepted_two_sim>,<pending_unaccepted_sim>
```

Final hygiene:

```bash
git diff --check
```

If Flutter production code changes and the execution contract requires broader release confidence, also run:

```bash
./scripts/run_test_gates.sh baseline
```

## Known-Failure Interpretation

- A failure in `group_info_screen_test.dart` or `group_info_wired_test.dart` after this change is session-caused unless proven otherwise.
- A failure in `resend_group_invite_use_case_test.dart` should be treated as a status/result mapping regression until triaged.
- A four-simulator failure before app launch or device attach is environment/build related unless logs show a UI assertion mismatch.
- A four-simulator creator assertion failure is product UI evidence and must be fixed before acceptance.
- Existing unrelated dirty files, such as version bumps, must not be reverted or folded into this session.

## Done Criteria

This session is done only when:

- `Invite queued` no longer appears in Group Info Members tests or simulator assertions.
- Queued status displays `In their inbox`.
- Needs-resend status displays `Resend needed`.
- The retry action displays `Resend`.
- The retry busy state displays `Sending...`.
- `Cannot send` includes a clear user-readable reason for known and fallback error cases.
- Resend snackbar copy matches the new language.
- Host tests pass.
- `./scripts/run_test_gates.sh groups` passes.
- The four-simulator runner passes with the new expected labels.
- `git diff --check` passes.

## Scope Guard

Do not:

- Change status enum names or persisted values.
- Change delivery result mapping.
- Change retry behavior beyond visible copy and state display.
- Add claims about blocking, uninstalling, or user intent.
- Build a new diagnostics system.
- Redesign the Members section.
- Widen named gates.
- Replace the existing four-simulator runner with a second competing runner.

## Accepted Differences / Intentionally Out Of Scope

- The four-simulator test remains a seeded creator-side `GroupInfoWired` display proof.
- Real relay/testpeer lifecycle proof remains out of scope unless a future acceptance bar requires organic multi-device invite acceptance.
- Detailed friend recovery UX, such as contact re-verification or key refresh prompts, is out of scope.
- A future richer error taxonomy can replace the raw `lastError` mapping later, but this session should use the existing persisted evidence.

## Dependency Impact

Later work that depends on this plan:

- Any future group invite troubleshooting UI.
- Any product decision to explain blocked/uninstalled/unreachable states.
- Any future real relay/testpeer lifecycle acceptance proof.

If this plan changes during implementation:

- Revisit the four-simulator harness expected labels.
- Revisit `Test-Flight-Improv/test-gate-definitions.md` optional/manual suite description.
- Revisit `_current-test-map.md` if the direct test command changes.

## Reviewer Result

Sufficient with no structural blockers.

The plan is narrow enough to execute safely because it uses existing status data, existing resend behavior, existing widget tests, and the existing four-simulator display runner.

## Arbiter Result

Structural blockers remaining: none.

Incremental details intentionally deferred:

- Exact visual layout for long cannot-send copy can be adjusted during implementation, but must remain readable on mobile.
- A richer non-raw error taxonomy can be planned later.

Accepted differences intentionally left unchanged:

- Simulator proof is seeded display proof, not organic relay/testpeer lifecycle proof.

