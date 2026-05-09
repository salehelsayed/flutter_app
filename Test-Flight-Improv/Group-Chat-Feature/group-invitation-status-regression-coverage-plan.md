# Group Invitation Status Regression Coverage Plan

Status: `accepted_with_explicit_follow_up`

Session classification: `evidence-gated`

Created: 2026-05-09

## Planning Result (Historical)

This plan originally covered the remaining gaps identified after the first group invite status fix:

1. Re-invite stale join regression.
2. Full status matrix test for `sent`, `queued`, `needsResend`, `cannotSend`, `joined`, and `unknown`.
3. Four-iOS-simulator proof that the real app displays the expected creator-side member statuses across accepted, failed, and unaccepted invitees.

The host/widget regressions were ready to implement immediately. The simulator proof required a new runner or harness because the group multi-device runner only supported two devices.

## Closure Result

Session `01` closed this plan on 2026-05-09 as `accepted_with_explicit_follow_up`.

Closed by the session:

- The stale re-invite regression now proves old `member_joined` evidence does not make a newly re-invited pending member display `Joined`.
- Accepted-member `Joined` display is preserved, including the missing-attempt-row fallback.
- A deterministic `GroupInfoWired` host matrix covers `Invite sent`, `Invite queued`, `Needs resend`, `Cannot send`, `Joined`, and `Invite unknown`.
- `GroupInfoWired` invite status loading is timestamp-aware for current invite attempts, removal evidence, and durable join evidence.
- The direct test map and gate definitions point maintainers to the direct host coverage and the four-simulator runner.

Required gates passed:

```bash
flutter test test/features/groups/presentation/group_info_wired_test.dart
flutter test test/features/groups/application/group_message_listener_test.dart
./scripts/run_test_gates.sh groups
git diff --check
dart run integration_test/scripts/run_group_invite_status_matrix_sim.dart -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469,347FB118-10D0-40C8-A05B-B0C3BD6B8CCD,5BA69F1C-B112-47BE-B1FF-8C1003728C8F,1B098DFF-6294-407A-A209-BBF360893485
```

Simulator classification: the four-simulator command passed as seeded creator-side `GroupInfoWired` Members invite-status display proof. It does not claim real relay/testpeer lifecycle proof; verdicts intentionally record `relayLifecycleProof: false`.

Residual-only follow-up: add a separate real relay/testpeer lifecycle invite proof only if a future acceptance bar requires organic multi-device invite acceptance instead of seeded display proof.

The historical plan sections below remain useful as context for what was implemented. The closure result above is the authoritative current status.

## Real Scope

Add focused regression coverage and any narrowly required production fix for group invite status display in Group Info.

This work is limited to:

- Preventing stale durable `member_joined` timeline evidence from making a newly re-invited member display `Joined`.
- Proving every visible invite status label in the Members list.
- Adding a four-simulator scenario that proves the creator sees correct real app UI for accepted and failed or unaccepted invitees.

This plan must not redesign group membership, group invite transport, group keys, or the visible status copy.

## Closure Bar

The work is good enough when:

- A failing stale re-invite regression is added before the fix.
- The fix makes the stale re-invite test pass while preserving accepted-member `Joined` display.
- One deterministic host/widget test covers all six invite status labels.
- A four-iOS-simulator runner can prove the creator's Group Info Members UI, or fail with actionable logs and screenshots.
- Test map or gate documentation points future maintainers to the new tests.

## Source Of Truth

Current production code and tests win over older prose.

Primary production files:

- `lib/features/groups/presentation/screens/group_info_wired.dart`
- `lib/features/groups/presentation/screens/group_info_screen.dart`
- `lib/features/groups/presentation/widgets/group_member_row.dart`
- `lib/features/groups/application/group_message_listener.dart`
- `lib/features/groups/domain/repositories/group_invite_delivery_attempt_repository.dart`
- `lib/features/groups/domain/repositories/group_invite_delivery_attempt_repository_impl.dart`

Primary tests and harnesses:

- `test/features/groups/presentation/group_info_wired_test.dart`
- `test/features/groups/presentation/group_info_screen_test.dart`
- `test/features/groups/application/group_message_listener_test.dart`
- `integration_test/scripts/run_group_multi_device_real.dart`
- `integration_test/group_multi_device_real_harness.dart`

Primary documentation:

- `Test-Flight-Improv/Group-Chat-Feature/group-invitation-status-tdd-plan.md`
- `Test-Flight-Improv/Group-Chat-Feature/group-simulator-coverage-extension-plan.md`
- `Test-Flight-Improv/_current-test-map.md`
- `Test-Flight-Improv/test-gate-definitions.md`

## Session Classification

Use one implementation session with three internal stages:

1. Host regression tests.
2. Production fix for stale durable join overlay behavior.
3. Four-simulator display proof.

The session is `evidence-gated` because the host work can be completed on any development machine, but the simulator proof depends on four available iOS simulator IDs and a new four-device runner.

## Exact Problem Statement

`GroupInfoWired` currently resolves invite statuses from the invite delivery attempt repository and then overlays durable `member_joined` timeline evidence. That is useful because accepted members can still show `Joined` even if the invite attempt row is missing or stale.

The remaining risk is that the overlay may trust old history too much. If a member joined in the past, was removed, and was later re-invited, the old `member_joined` event must not make the current invite row display `Joined` before the member accepts the new invite.

The user-visible failure would be a creator opening Group Info and seeing incorrect status badges under Members.

## Files And Repos To Inspect Next

Before implementation, inspect:

- Whether `GroupMessageRepository.getLatestSystemEventTimestampForTarget` can query `member_removed` for the removed peer ID.
- Whether `GroupInviteDeliveryAttemptRepository.getAttemptsForGroup` exposes enough timestamp evidence to compare current invite attempts with older join events.
- Whether `GroupInviteDeliveryAttempt` has `attemptedAt`, `updatedAt`, or an equivalent current-attempt timestamp.
- Existing resend and cannot-send tests to avoid changing send semantics while fixing display logic.
- Existing integration harness setup helpers for identity, contact, and group fixture provisioning.

Likely simulator additions:

- `integration_test/scripts/run_group_invite_status_matrix_sim.dart`
- `integration_test/group_invite_status_matrix_harness.dart`

These names are proposed, not mandatory.

## Existing Tests Covering This Area

Current meaningful coverage:

- `test/features/groups/presentation/group_info_wired_test.dart` covers accepted members showing `Joined` from durable timeline state.
- `test/features/groups/application/group_message_listener_test.dart` covers `member_joined` marking invite delivery status joined.
- `test/features/groups/presentation/group_info_screen_test.dart` covers badge rendering.
- `./scripts/run_test_gates.sh groups` covers the group host gate.

Current gaps:

- No stale re-invite regression.
- No single full badge matrix covering all labels.
- No four-simulator proof of real app display across creator, accepted members, and failed or unaccepted invitees.

## Regression Tests To Add First

Add these tests before changing production code:

1. Stale re-invite regression in `test/features/groups/presentation/group_info_wired_test.dart`.

   Scenario:

   - A peer has an old `member_joined` timeline event.
   - The same peer has a later `member_removed` timeline event.
   - The same peer is present in the current group member list again.
   - The current invite attempt says `sent`.
   - No fresh `member_joined` exists after the re-invite.

   Expected result: the member displays `Invite sent`, not `Joined`.

2. Full status matrix in `test/features/groups/presentation/group_info_wired_test.dart`.

   Scenario:

   - Build one group with six non-self members.
   - Persist or provide statuses for `sent`, `queued`, `needsResend`, `cannotSend`, and `joined`.
   - Leave one member without an invite attempt row and without join evidence.

   Expected labels:

   - `sent` -> `Invite sent`
   - `queued` -> `Invite queued`
   - `needsResend` -> `Needs resend`
   - `cannotSend` -> `Cannot send`
   - `joined` -> `Joined`
   - missing row -> `Invite unknown`

3. Four-simulator UI proof.

   Scenario:

   - Creator/admin simulator creates or owns a group.
   - Two member simulators accept and publish or otherwise produce fresh joined evidence.
   - One member simulator remains pending, fails, or is intentionally made unable to complete the invite.
   - Creator opens Group Info and the harness asserts visible Members labels.

   Expected result: the runner exits zero only when creator-side visible text matches the expected status matrix.

## Step-By-Step Implementation Plan

1. Add the stale re-invite test and confirm it fails against current overlay behavior.
2. Update `GroupInfoWired` status loading to use enough invite attempt metadata to decide whether durable join evidence is current.
3. Overlay `Joined` only when latest join evidence is newer than the relevant removal watermark and not older than the current invite attempt that should still be pending.
4. Preserve the intended fallback where accepted members with missing attempt rows and valid current join evidence still show `Joined`.
5. Add the full badge matrix widget test.
6. Add or extend a four-device integration runner. Prefer a new runner over changing the existing two-device runner in place.
7. Add a harness with roles such as `creator`, `accepted_one`, `accepted_two`, and `pending_or_failed`.
8. Make the creator role assert actual Flutter UI text on the Group Info Members screen.
9. Use deterministic local seeded invite rows for hard-to-force display-only states if the real transport path is too brittle for simulator automation.
10. Update `_current-test-map.md`, gate docs, or simulator discovery docs so the new coverage is findable.

## Four-Simulator Design

Use four iOS simulators:

- Simulator A: creator/admin.
- Simulator B: accepted member one.
- Simulator C: accepted member two.
- Simulator D: pending, failed, or unaccepted invitee.

The simulator test should prove two things:

- Real accepted lifecycle: B and C reach visible `Joined` on the creator's Group Info screen.
- Real app display: the creator's actual Flutter UI renders the expected status labels.

For statuses that are hard to force reliably through real networking, such as `needsResend`, `cannotSend`, and `unknown`, the harness may seed deterministic creator-side repository rows and then open the real Group Info UI. That keeps the simulator test stable while the host tests continue to prove the full enum mapping and repository behavior.

## Risks And Edge Cases

- Old `member_joined` events can outlive current membership and must not override a later remove/re-invite cycle.
- A member with no invite row but valid current join evidence must still display `Joined`.
- A current invite attempt should win when its timestamp proves it happened after the old join event.
- A later `member_removed` event should block old join evidence until a fresh join arrives.
- Four-simulator tests can be slow and device-sensitive, so the runner must fail with enough logs to distinguish setup failure from product failure.
- Forcing all network failure states organically on simulators may be flaky; seeded display rows are acceptable for display-only proof.

## Exact Tests And Gates To Run

Host checks:

```bash
flutter test test/features/groups/presentation/group_info_wired_test.dart
flutter test test/features/groups/application/group_message_listener_test.dart
./scripts/run_test_gates.sh groups
git diff --check
```

Simulator proof after the runner is added:

```bash
dart run integration_test/scripts/run_group_invite_status_matrix_sim.dart \
  -d <creator_sim>,<accepted_one_sim>,<accepted_two_sim>,<pending_or_failed_sim>
```

If the new runner is registered with the reliability simulation scripts, also run the matching named simulator gate documented at implementation time.

## Known-Failure Interpretation

- The stale re-invite test should fail before the production fix. That confirms the regression is real.
- If accepted-member `Joined` tests fail after the fix, the overlay was made too strict.
- If the full status matrix fails, inspect the badge mapping before changing repository semantics.
- If the simulator runner fails before app launch or device attach, treat it as environment setup until logs prove a UI assertion mismatch.
- If the creator UI assertion fails, treat it as product behavior evidence.

## Done Criteria

This plan is complete only when:

- Stale re-invite shows the current invite status, not stale `Joined`.
- Accepted members still show `Joined`.
- All six badge labels are covered by one deterministic host/widget test.
- The four-simulator runner proves creator-side UI for accepted and failed or unaccepted invitees.
- New or changed docs point to the direct test and simulator runner.

## Scope Guard

Do not:

- Rename visible labels.
- Redesign the Members screen.
- Change invite wire protocol.
- Change group key or membership event format.
- Turn the simulator test into a full transport-failure certification suite.
- Rewrite existing group simulator infrastructure beyond what is required to run this scenario.

## Accepted Differences / Intentionally Out Of Scope

The full enum display matrix may be proven by host/widget tests.

The four-simulator test should prove real accepted-member lifecycle and creator-side display. It does not need to organically force every possible delivery failure through real networking if deterministic seeded rows give a stronger display regression signal.

Transport retry, inbox durability, key repair, push notification behavior, and group media delivery remain outside this plan unless implementation evidence shows they directly affect invite status display.

## Dependency Impact

Expected impact is limited to:

- Group Info status loading.
- Group invite status presentation tests.
- One new integration runner and harness.
- Current test map or simulator discovery documentation.

No database migration should be needed unless existing repository APIs cannot expose enough timestamp evidence for current versus stale join decisions.
