# Group Invitation Status TDD Plan

Status: `accepted`

Session classification: `accepted`

## Planning Progress

- 2026-05-07 17:04:32 CEST | Evidence Collector started | inspected `Test-Flight-Improv/Group-Chat-Feature/group-invitation-status-tdd-plan.md`, `Test-Flight-Improv/Group-Chat-Feature/group-invitation-status-tdd-plan-session-breakdown.md`, and `Test-Flight-Improv/test-gate-definitions.md`; decision: plan is already execution-ready but lacks a current device/relay proof profile for transport/integration-backed gates; next action: gather live device inventory without running gates.
- 2026-05-07 17:05:19 CEST | Evidence Collector completed | live checks used: `flutter devices --machine`, `xcrun simctl list devices available`, `adb devices`, and `/Users/I560101/Library/Android/sdk/platform-tools/adb devices`; decision: `GIS-001` needs single explicit-device transport closure evidence, not paired-device, multi-relay, or OS-notification lab evidence; next action: add the proof profile while preserving existing scope/tests/gates.
- 2026-05-07 17:06:21 CEST | Planner completed | files inspected since last update: none beyond collected evidence; decision: add a compact `single-device` proof profile with exact current device IDs and command env vars, without changing scope, tests, gates, done criteria, or scope guard; next action: reviewer sufficiency check.
- 2026-05-07 17:06:31 CEST | Reviewer completed | files inspected since last update: intended plan profile draft only; decision: sufficient once the profile records required closure evidence versus supporting inventory and explains why paired/multi-relay/device-lab classes do not apply; next action: arbiter classification.
- 2026-05-07 17:06:31 CEST | Arbiter completed | files inspected since last update: intended plan profile draft only; structural blockers: none after this profile; incremental details deferred: rerunning actual gates belongs to execution, not planning; next action: pipeline may execute `GIS-001` from this `execution-ready` plan.

## Feedback Review Result

The feedback is accepted as structurally valid. The previous draft had placeholder test paths, did not name all production entry files, omitted the required named gates, and did not make the SQLite version/migration proof explicit enough for implementation.

Already sufficient and intentionally preserved: product behavior, non-goals, local-only/backward-compatible constraint, invite status states, TDD ordering, and the no-protocol-change guard.

## Real Scope

Add local, backward-compatible invite delivery status tracking so User A can open the Group Info `i` screen and see whether each invited member's invitation was sent, queued, failed, cannot be sent, or later joined.

This is a local app-state change only. It must not change the group invite wire protocol, `group_invite`, `members_added`, group key format, or legacy app behavior.

## Closure Bar

The work is good enough when a user who creates or adds group members during network failure can later open Group Info and tell which invitees likely received an invite and which invitees need manual resend. The status must survive app restart, must update when the existing `member_joined` event is observed, and must be covered by direct tests plus the required named gates.

## Source Of Truth

- Current production code and tests win over stale prose.
- `Test-Flight-Improv/test-gate-definitions.md` is authoritative for named gates; it requires `./scripts/run_test_gates.sh groups` for group invite changes and `./scripts/run_test_gates.sh baseline` for every PR.
- Because this plan wires a SQLite migration through `lib/main.dart`, the Startup / Transport Gate also applies: `./scripts/run_test_gates.sh transport`.
- Current database version is `66` in `lib/main.dart`; this plan requires migration `067` and version `67` wiring if a new SQLite table is added.
- This document is the implementation contract unless code evidence during TDD proves a narrower change is sufficient.

## Exact Problem Statement

When group creation or add-member invite delivery partially fails, the creator may still see the group and locally added members. The existing UI does not persist or display whether each invitation was actually sent, stored for later delivery, failed, or cannot be sent. That leaves the creator unable to decide whether to manually resend.

The user-visible fix is a per-member invite status on the Group Info member list, with a manual `Send again` action only when the local record says the invite needs resend.

## Files And Repos To Inspect Next

Database and app bootstrap:

- `lib/core/database/migrations/067_group_invite_delivery_attempts.dart`
- `lib/core/database/helpers/group_invite_delivery_attempts_db_helpers.dart`
- `lib/main.dart` for migration/version wiring and helper-backed repository construction
- `test/core/database/integration/full_migration_chain_test.dart`

Domain and repository:

- `lib/features/groups/domain/models/group_invite_delivery_attempt.dart`
- `lib/features/groups/domain/repositories/group_invite_delivery_attempt_repository.dart`
- `lib/features/groups/domain/repositories/group_invite_delivery_attempt_repository_impl.dart`
- `lib/features/groups/domain/repositories/pending_group_invite_repository_impl.dart` as the closest existing invite repository pattern

Application entry points:

- `lib/features/groups/application/send_group_invite_use_case.dart`
- `lib/features/groups/application/create_group_with_members_use_case.dart`
- `lib/features/groups/application/group_message_listener.dart`
- `lib/features/groups/application/resend_group_invite_use_case.dart`
- `lib/features/groups/presentation/screens/contact_picker_wired.dart`
- `lib/features/groups/presentation/screens/create_group_picker_wired.dart`

Group Info presentation entry points:

- `lib/features/groups/presentation/screens/group_conversation_wired.dart`
- `lib/features/groups/presentation/screens/group_info_wired.dart`
- `lib/features/groups/presentation/screens/group_info_screen.dart`
- `lib/features/groups/presentation/widgets/group_member_row.dart`

Typed seam files to keep coherent in one pass:

- `lib/main.dart` must construct the new helper-backed invite-status repository if production code depends on it.
- `lib/features/groups/presentation/screens/create_group_picker_wired.dart` calls `createGroupWithMembers`; update it if create-flow invite-status persistence adds repository dependencies or result semantics.
- `lib/features/groups/presentation/screens/group_conversation_wired.dart` constructs `GroupInfoWired`; update it if Group Info needs invite-status or resend dependencies.
- `lib/features/groups/presentation/screens/group_info_wired.dart` constructs `ContactPickerWired`; update both caller and callee if add-member invite-status persistence needs the same dependency.
- Any constructor, callback, repository, or route initialization change must update all callers and direct tests in the same Executor pass.

## Existing Tests Covering This Area

- `test/features/groups/application/send_group_invite_use_case_test.dart` covers invite send outcomes but must be extended because success currently does not provide enough direct-vs-inbox detail for UI status.
- `test/features/groups/application/create_group_with_members_use_case_test.dart` covers local group creation with invite batch results but does not prove persisted per-member invite status.
- `test/features/groups/presentation/contact_picker_wired_test.dart` covers add-member invite warnings but does not prove status persistence.
- `test/features/groups/application/group_message_listener_test.dart` covers incoming group events and should be extended for `member_joined` to `joined` status.
- `test/features/groups/presentation/group_info_screen_test.dart` and `test/features/groups/presentation/group_info_wired_test.dart` cover Group Info rendering/wiring but not invite delivery status rows.
- `test/features/groups/presentation/create_group_picker_wired_test.dart` covers create-flow navigation and warning snackbar behavior, but not invite-status repository wiring.
- `test/features/groups/domain/repositories/pending_group_invite_repository_impl_test.dart` is the closest repository proof pattern for invite-related persistence.

## Regression/Tests To Add First

Add these failing tests before production code:

1. `test/core/database/migrations/067_group_invite_delivery_attempts_test.dart`
   - Proves migration `067` creates `group_invite_delivery_attempts`.
   - Proves idempotency.
   - Proves the `(group_id, peer_id)` uniqueness contract and lookup indexes.

2. `test/core/database/helpers/group_invite_delivery_attempts_db_helpers_test.dart`
   - Proves helper upsert, load by group/member, load all for group, delete-by-group/member if needed, and status update semantics.

3. `test/core/database/integration/full_migration_chain_test.dart`
   - Proves fresh install includes migration `067`.
   - Proves upgrade from the current chain through `067` preserves seeded group/member data.
   - Proves the table exists after the full chain.

4. `test/features/groups/domain/repositories/group_invite_delivery_attempt_repository_impl_test.dart`
   - Proves repository round-trips all statuses.
   - Proves no-row legacy members project as `unknown`.
   - Proves repository maps helper rows without relying on UI logic.

5. Extend application tests:
   - `test/features/groups/application/send_group_invite_use_case_test.dart`
   - `test/features/groups/application/create_group_with_members_use_case_test.dart`
   - `test/features/groups/application/group_message_listener_test.dart`
   - Add `test/features/groups/application/resend_group_invite_use_case_test.dart`

6. Extend presentation tests:
   - `test/features/groups/presentation/contact_picker_wired_test.dart`
   - `test/features/groups/presentation/create_group_picker_wired_test.dart`
   - `test/features/groups/presentation/group_info_screen_test.dart`
   - `test/features/groups/presentation/group_info_wired_test.dart`

## Step-By-Step Implementation Plan

1. Write the failing persistence tests for migration `067`, DB helpers, full migration chain, and repository behavior.

2. Add migration `067_group_invite_delivery_attempts` and wire it into `lib/main.dart`:
   - import the new migration
   - bump encrypted DB version from `66` to `67`
   - call the migration in the fresh-install `onCreate` chain
   - add `if (oldVersion < 67) await runGroupInviteDeliveryAttemptsMigration(db);`

3. Add `group_invite_delivery_attempts` as a local-only table keyed by `(group_id, peer_id)`. Required status values:
   - `sent`: direct P2P invite succeeded
   - `queued`: direct failed but relay inbox store succeeded
   - `needs_resend`: direct and inbox failed, node stopped, or group key missing
   - `cannot_send`: missing secure key or invalid invite payload
   - `joined`: existing `member_joined` event observed for that peer
   - `unknown`: no local attempt record, mainly legacy/pre-migration rows

4. Add DB helpers, model, and repository. Repository tests own the proof that app code can upsert/load statuses; helper tests own SQL behavior.

5. Extend `send_group_invite_use_case.dart` so application code can distinguish direct success from inbox fallback success without changing the wire payload. Map direct success to `sent`, inbox fallback success to `queued`, and hard failures to `needs_resend` or `cannot_send`.

6. Wire create-group and add-member flows to persist one status row per selected invitee from `GroupInviteBatchResult`, including failure paths after local members have already been added.

7. Add resend use case. It must only rebuild and send the invite for the existing member, then update status. It must not add the member again and must not publish another `members_added`.

8. Extend `GroupMessageListener` handling of the existing `member_joined` system event to mark the matching member `joined`.

9. Wire helper-backed repository construction and typed callers coherently:
   - construct the new repository in `lib/main.dart`
   - pass dependencies through create/add-member and Group Info navigation seams only where needed
   - update caller-side tests whenever a constructor or callback signature changes

10. Update Group Info wired state and rows to load statuses, show compact status labels, and expose `Send again` only for `needs_resend`.

11. Run direct tests first, then named gates. Stop if any new direct test or gate failure is caused by this scope.

## Risks And Edge Cases

- `sendGroupInvite` success currently risks conflating direct delivery and inbox fallback. Tests must pin the mapping before UI status depends on it.
- `sent` and `queued` are delivery-attempt states, not acceptance states. Only `member_joined` may display `joined`.
- Legacy groups and old invite rows must show `unknown`, not failure.
- Manual resend must be idempotent and must not duplicate members or membership events.
- Missing secure key, invalid payload, and stopped node must not leave the user with a misleading `sent` label.
- If the app receives `member_joined` before a local invite status row exists, repository behavior should upsert `joined`.

## Device/Relay Proof Profile

Classification: `single-device`.

This row requires an explicit single Flutter target for closure because the named `transport` gate contains `integration_test/` transport coverage and `Test-Flight-Improv/test-gate-definitions.md` documents `FLUTTER_DEVICE_ID=<device-id> ./scripts/run_test_gates.sh transport` as the device-pinned form. It does not require `paired-device`, `three-party`, `device-lab`, `multi-relay`, `os-notification-device-lab`, or `external-fixture-blocked` evidence because the required gates for this plan are only `baseline`, `groups`, `transport`, `completeness-check`, and `git diff --check`; `group-real-network-nightly`, `integration_test/scripts/run_group_multi_device_real.dart`, `MKNOON_REQUIRE_MULTI_RELAY=true`, `IOS_SECONDARY_SIMULATOR_DEVICE`, push simulator smoke, and OS notification tap/device-lab suites are outside this plan's closure gates.

Live checks used on 2026-05-07:

- `flutter devices --machine`
  - Android physical: `Pixel 6`, id `21071FDF600CSC`, platform `android-arm64`, Android 16 API 36.
  - iOS physical: `Saleh's iPhone`, id `00008030-001A6D2801BB802E`, platform `ios`, iOS 26.4.2.
  - iOS simulator: `iPhone 17 Pro`, id `38FECA55-03C1-4907-BD9D-8E64BF8E3469`, runtime `com.apple.CoreSimulator.SimRuntime.iOS-26-1`.
  - iOS simulator: `iPhone Air`, id `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD`, runtime `com.apple.CoreSimulator.SimRuntime.iOS-26-1`.
  - iOS simulator: `iPhone 17`, id `5BA69F1C-B112-47BE-B1FF-8C1003728C8F`, runtime `com.apple.CoreSimulator.SimRuntime.iOS-26-1`.
  - iOS simulator: `iPhone 16e`, id `1B098DFF-6294-407A-A209-BBF360893485`, runtime `com.apple.CoreSimulator.SimRuntime.iOS-26-1`.
  - Host target: `macos`, id `macos`, platform `darwin`.
  - Web target: `Chrome`, id `chrome`, platform `web-javascript`; not valid closure evidence for these Flutter integration gates.
- `xcrun simctl list devices available`
  - Confirmed the iOS simulator ids above are currently available and booted.
  - Confirmed the historically referenced configured simulator ids `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD` and `5BA69F1C-B112-47BE-B1FF-8C1003728C8F` are present in the current simulator set.
- `adb devices`
  - Plain command is not available on `PATH` in this shell: `zsh:1: command not found: adb`.
- `/Users/I560101/Library/Android/sdk/platform-tools/adb devices`
  - Confirmed Android device id `21071FDF600CSC` is attached with state `device`.

Required closure evidence:

- Run the named transport gate with one explicit current Flutter device or simulator target. Preferred current simulator because it is booted and matches prior transport-gate evidence in the gate definitions:

```sh
FLUTTER_DEVICE_ID=5BA69F1C-B112-47BE-B1FF-8C1003728C8F ./scripts/run_test_gates.sh transport
```

- If that simulator is unavailable at execution time, rerun `flutter devices --machine` and choose another current single Flutter target. Current supporting alternates are `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD`, `38FECA55-03C1-4907-BD9D-8E64BF8E3469`, `1B098DFF-6294-407A-A209-BBF360893485`, `00008030-001A6D2801BB802E`, or `21071FDF600CSC`.
- Because multiple Flutter targets are attached, make host-capable named gates deterministic by pinning the intended host target when using the historical host shape:

```sh
FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline
FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups
./scripts/run_test_gates.sh completeness-check
```

Supporting evidence only:

- The Android physical target `21071FDF600CSC` and iOS physical target `00008030-001A6D2801BB802E` are live inventory evidence, not required closure evidence for this session unless the Executor intentionally chooses one as the single `FLUTTER_DEVICE_ID`.
- No relay address env vars, `MKNOON_REQUIRE_MULTI_RELAY=true`, paired simulator IDs, `IOS_SECONDARY_SIMULATOR_DEVICE`, or `ANDROID_SERIAL` are required for closure. `ANDROID_SERIAL=21071FDF600CSC` is only relevant if a future Android-specific manual script is deliberately added outside this plan.

## Exact Tests And Gates To Run

Direct persistence tests:

```sh
flutter test test/core/database/migrations/067_group_invite_delivery_attempts_test.dart
flutter test test/core/database/helpers/group_invite_delivery_attempts_db_helpers_test.dart
flutter test test/core/database/integration/full_migration_chain_test.dart
flutter test test/features/groups/domain/repositories/group_invite_delivery_attempt_repository_impl_test.dart
```

Direct application and presentation tests:

```sh
flutter test test/features/groups/application/send_group_invite_use_case_test.dart
flutter test test/features/groups/application/create_group_with_members_use_case_test.dart
flutter test test/features/groups/application/group_message_listener_test.dart
flutter test test/features/groups/application/resend_group_invite_use_case_test.dart
flutter test test/features/groups/presentation/contact_picker_wired_test.dart
flutter test test/features/groups/presentation/create_group_picker_wired_test.dart
flutter test test/features/groups/presentation/group_info_screen_test.dart
flutter test test/features/groups/presentation/group_info_wired_test.dart
```

Focused regression commands:

```sh
flutter test test/features/groups/application test/features/groups/presentation
flutter test test/features/contact_request/integration/contact_request_flow_test.dart
```

Named gates:

```sh
./scripts/run_test_gates.sh baseline
./scripts/run_test_gates.sh groups
./scripts/run_test_gates.sh transport
./scripts/run_test_gates.sh completeness-check
```

Final hygiene:

```sh
git diff --check
```

## Known-Failure Interpretation

Treat unrelated existing local worktree changes outside the invite-status scope as out of scope. Any new failure in the direct tests or named gates above is a blocker when it is caused by these files or by the new tests. If `baseline`, `groups`, `transport`, or `completeness-check` is already red before implementation, capture the pre-existing failure, keep the direct invite-status suite green, and do not classify old red tests as regressions from this work.

## Done Criteria

- [x] All new tests listed in `Regression/Tests To Add First` fail for the expected reason before production implementation.
- [x] Migration `067_group_invite_delivery_attempts` is added, idempotent, wired in `lib/main.dart`, and covered by `full_migration_chain_test.dart`.
- [x] Repository and DB helper tests prove status upsert/load and legacy `unknown` behavior.
- [x] Create-group and add-member flows persist per-recipient invite status for direct success, inbox fallback, send failure, node stopped, missing key, and invalid payload.
- [x] Group Info member list displays invite status and only shows `Send again` for `needs_resend`.
- [x] Resend sends an invite only, does not duplicate members, and updates the visible status.
- [x] Existing `member_joined` handling updates status to `joined`.
- [x] All changed typed seams are coherent: repository construction, constructor parameters, route builders, callbacks, and their direct widget/application tests compile and pass together.
- [x] Direct tests, `baseline`, `groups`, `transport`, `completeness-check`, and `git diff --check` pass or have documented unrelated pre-existing failures.
- [x] No group invite protocol, `members_added`, or key material wire format changes are introduced.

## Scope Guard

- Do not add invite ACK messages, delivery receipts, remote acceptance receipts, or new wire payload fields.
- Do not auto-resend in this session. Manual resend from Group Info only.
- Do not remove locally added group members when invite delivery fails; existing behavior stays unchanged.
- Do not infer acceptance from `sent` or `queued`.
- Do not require non-updated users to understand, write, or preserve the new local status table.
- Do not broaden this into a group protocol redesign.

## Accepted Differences / Intentionally Out Of Scope

- Updated apps get clearer local status in Group Info; older apps simply lack the new local table and UI labels.
- `unknown` is acceptable for legacy rows because old app versions never recorded invite-attempt state.
- `queued` means the app stored the invite in the fallback path; it does not guarantee the recipient accepted or joined.
- A future protocol-level invite acknowledgment system would be a separate compatibility design and is intentionally out of scope.

## Dependency Impact

This plan is safe to implement before any protocol work because it only records local invite-attempt outcomes and existing join observations. Later work that wants true recipient acknowledgments must not reuse `sent` or `queued` as acceptance proof; it should add a separate protocol and migration plan with explicit compatibility handling.

## Execution Progress

- 2026-05-07 17:49:07 CEST | final QA verdict accepted | final QA inspected `git status --short`, `git diff --stat`, owner diffs, route seam diffs, and no-protocol-change guard (`group_invite_payload.dart`, `group_invite_revocation_payload.dart`, and `group_config_payload.dart` have no diff); accidental simulator/Xcode timestamp delta in root `info.plist` was removed; final code deltas: migration 067, DB helpers, invite delivery model/repository, recording/resend use cases, send-result queued mapping, create/add invite recording, member-joined status update, Group Info status/resend UI, main migration/repository wiring, and route seam pass-through for feed/orbit/startup/home/group-list/group-conversation/create-group/contact-picker; final test deltas: new migration/helper/repository/resend tests plus updated create-group/send-invite/group-listener/group-info/invite-round-trip/full-migration-chain tests; all required direct tests and gates passed, including final `git diff --check`; final verdict: `accepted`; blocker class: none; scope classification: feed/orbit/startup/home/group-list caller surfaces are intentional seam fallout, untracked `Test-Flight-Improv/92-one-to-one-simulator-reliability-gaps.md` and `scripts/check_reliability_simulation_discovery.sh` are unrelated pre-existing/user changes, and no blocking scope drift remains.
- 2026-05-07 17:46:40 CEST | required gates finished, QA started | passed gates now include `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline`, `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups`, `FLUTTER_DEVICE_ID=5BA69F1C-B112-47BE-B1FF-8C1003728C8F ./scripts/run_test_gates.sh transport`, `./scripts/run_test_gates.sh completeness-check` (`730/730 test files classified`), and `git diff --check`; next action: local QA review of diff scope, no-protocol-change guard, route seam fallout, and final verdict evidence.
- 2026-05-07 17:46:11 CEST | transport gate finished | preferred device-backed command `FLUTTER_DEVICE_ID=5BA69F1C-B112-47BE-B1FF-8C1003728C8F ./scripts/run_test_gates.sh transport` passed on the booted iPhone 17 simulator; observed expected gate shape: `integration_test/background_reconnect_test.dart` skipped by its guard, WiFi/relay E2E smoke reported no CLI peer fixture and passed self-contained scenarios, transport E2E passed self-contained inbox/empty-message scenarios, and media stable-ID simulator smoke passed; next action: run `./scripts/run_test_gates.sh completeness-check` and `git diff --check`.
- 2026-05-07 17:41:31 CEST | groups gate fix pass finished | patched only `test/features/groups/integration/invite_round_trip_test.dart`: inbox-fallback re-invite now expects `SendGroupInviteResult.queued`, and IJ003 revocation replay uses a deterministic listener clock inside the revocation TTL; direct command `flutter test test/features/groups/integration/invite_round_trip_test.dart` passed; named gate `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` passed; next action: run preferred device-backed `FLUTTER_DEVICE_ID=5BA69F1C-B112-47BE-B1FF-8C1003728C8F ./scripts/run_test_gates.sh transport`.
- 2026-05-07 17:40:01 CEST | groups gate fix pass started | `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline` passed; `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` failed in `test/features/groups/integration/invite_round_trip_test.dart` only; inspected failing owner surfaces and found one stale expectation now requiring `SendGroupInviteResult.queued` for direct-fail/inbox-fallback invites, plus one date-sensitive revocation replay assertion where listener `now()` can outlive the pending-invite revocation TTL; next action: patch the integration test expectation/time source, rerun the direct integration test, then rerun the `groups` gate.
- 2026-05-07 17:34:15 CEST | device profile refreshed before gates | live commands completed: `flutter devices --machine` confirmed preferred iPhone 17 simulator `5BA69F1C-B112-47BE-B1FF-8C1003728C8F` is present, supported, and booted; `xcrun simctl list devices available` confirmed the same simulator is available and booted; `adb devices` remains unavailable on `PATH`; `/Users/I560101/Library/Android/sdk/platform-tools/adb devices` confirmed `21071FDF600CSC	device`; next action: run `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline`, `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups`, preferred `FLUTTER_DEVICE_ID=5BA69F1C-B112-47BE-B1FF-8C1003728C8F ./scripts/run_test_gates.sh transport`, `./scripts/run_test_gates.sh completeness-check`, and `git diff --check`.
- 2026-05-07 17:33:33 CEST | focused regressions finished | commands passed: `flutter test test/features/groups/application test/features/groups/presentation` and `flutter test test/features/contact_request/integration/contact_request_flow_test.dart`; known unrelated log noise observed in contact request avatar download binding initialization path but test result stayed green; next action: refresh live device availability with the proof-profile commands and run named gates.
- 2026-05-07 17:32:36 CEST | direct application/presentation tests finished | commands passed after targeted test fixes: `flutter test test/features/groups/application/send_group_invite_use_case_test.dart` (initial stale assertion expected inbox fallback `success`; classified session-caused test expectation, fixed to expect `queued`), `flutter test test/features/groups/application/create_group_with_members_use_case_test.dart`, `flutter test test/features/groups/application/group_message_listener_test.dart`, `flutter test test/features/groups/application/resend_group_invite_use_case_test.dart`, `flutter test test/features/groups/presentation/contact_picker_wired_test.dart`, `flutter test test/features/groups/presentation/create_group_picker_wired_test.dart`, `flutter test test/features/groups/presentation/group_info_screen_test.dart` (initial destructive-action finders needed scroll after status rows increased member-list height; fixed test interaction only), and `flutter test test/features/groups/presentation/group_info_wired_test.dart`; no production fix pass was needed for these failures; next action: run focused regression commands, then refresh device inventory and named gates.
- 2026-05-07 17:29:39 CEST | direct persistence tests finished | commands passed: `flutter test test/core/database/migrations/067_group_invite_delivery_attempts_test.dart`, `flutter test test/core/database/helpers/group_invite_delivery_attempts_db_helpers_test.dart`, `flutter test test/core/database/integration/full_migration_chain_test.dart`, and `flutter test test/features/groups/domain/repositories/group_invite_delivery_attempt_repository_impl_test.dart`; touched owner files verified by compile include migration 067, DB helpers, main migration chain, and repository row mapping; next action: run direct application and presentation tests sequentially.
- 2026-05-07 17:28:19 CEST | Executor resumed after progress request | inspected `git status --short`, skill contract, and current plan heartbeat; concrete code/test deltas now exist for migration 067, DB helpers, domain model/repository, invite recording, resend use case, application mapping, Group Info UI/wiring, joined update, and direct tests; previously running grouped Flutter test session no longer exists after context compaction (`Unknown process id`), so it will be rerun sequentially; scope-guard state: untracked `Test-Flight-Improv/92-one-to-one-simulator-reliability-gaps.md` and `scripts/check_reliability_simulation_discovery.sh` are treated as unrelated existing/user changes and will not be deleted, while feed/orbit/startup/home/group-list caller surfaces are being verified as intentional repository-seam pass-through only; next action: rerun required direct tests, then device availability refresh and named gates.
- 2026-05-07 17:09:08 CEST | contract extracted | inspected `Test-Flight-Improv/Group-Chat-Feature/group-invitation-status-tdd-plan.md`, `Test-Flight-Improv/Group-Chat-Feature/group-invitation-status-tdd-plan-session-breakdown.md`, `Test-Flight-Improv/test-gate-definitions.md`, skill contract, and `git status --short`; exact scope remains local invite delivery status persistence/UI/resend/joined updates with no group invite protocol, `members_added`, or key-format changes; required direct tests, focused regressions, named gates `baseline`, `groups`, `transport`, `completeness-check`, and `git diff --check` are explicit; next action: attempt nested Executor materialization.
- 2026-05-07 17:09:08 CEST | Executor spawn materialization failed | inspected available tool surface and found no callable nested-agent spawn facility for a `model: gpt-5.5` / `reasoning_effort: xhigh` child; no child produced partial code/test/doc work, so there is no hidden-state ambiguity; decision: use the skill's local sequential fallback because this invocation is the isolated execution agent requested by the outer controller; next action: run local Executor pass sequentially.
- 2026-05-07 17:14:20 CEST | Executor running | owner files inspected include `send_group_invite_use_case.dart`, `create_group_with_members_use_case.dart`, `contact_picker_wired.dart`, `group_message_listener.dart`, `group_info_wired.dart`, `group_info_screen.dart`, `group_member_row.dart`, `group_conversation_wired.dart`, `create_group_picker_wired.dart`, `main.dart`, `full_migration_chain_test.dart`, and peer migration/helper/repository tests; test files touched: added `test/core/database/migrations/067_group_invite_delivery_attempts_test.dart`, `test/core/database/helpers/group_invite_delivery_attempts_db_helpers_test.dart`, `test/features/groups/domain/repositories/group_invite_delivery_attempt_repository_impl_test.dart`, and `test/features/groups/application/resend_group_invite_use_case_test.dart`; current worktree now has concrete RED-test deltas beyond progress notes; next action: run first targeted RED persistence test, then add migration/helper/model/repository/use-case production code.
- 2026-05-07 17:15:08 CEST | RED test finished | command `flutter test test/core/database/migrations/067_group_invite_delivery_attempts_test.dart` failed as expected because `lib/core/database/migrations/067_group_invite_delivery_attempts.dart` and `runGroupInviteDeliveryAttemptsMigration` do not exist yet; classification: expected RED compile failure before production implementation, not a blocker; next action: add migration 067, DB helpers, domain model/repository, resend use case, and application/UI wiring.
- 2026-05-07 16:35:36 CEST | contract extracted | inspected `Test-Flight-Improv/Group-Chat-Feature/group-invitation-status-tdd-plan.md` and `Test-Flight-Improv/test-gate-definitions.md`; scope is local invite delivery status persistence/UI only; required direct tests, `baseline`, `groups`, `transport`, `completeness-check`, and `git diff --check` are explicit; next action: spawn isolated Executor.
- 2026-05-07 16:36:58 CEST | Executor running | isolated Executor inspected plan, gate definitions, current worktree status, and repo file inventory; only pre-existing worktree delta observed is this plan progress file; next action: inspect owner files and add RED tests first where feasible.
- 2026-05-07 16:43:17 CEST | Executor blocked | spawned Executor exceeded the bounded wait plus one progress-based extension and was closed while still running; inspected repo evidence showed no code/test/doc delta beyond this heartbeat section and no required tests or gates run; blocker class: `spawn_or_tool_failure`; next action: retry execution with a fresh isolated Executor or run this skill from an isolated outer pipeline context that permits local fallback if child materialization fails.
- 2026-05-07 16:46:24 CEST | contract extracted | fresh retry requested for this same plan; inspected the plan, `Test-Flight-Improv/test-gate-definitions.md`, repo file inventory, and `git status --short`; only current worktree delta before retry is this plan progress file; exact required direct tests and named gates remain `baseline`, `groups`, `transport`, `completeness-check`, and `git diff --check`; next action: spawn fresh isolated Executor.
- 2026-05-07 16:47:32 CEST | Executor running | isolated Executor inspected skill contract, plan, gate definitions, `scripts/run_test_gates.sh`, repo file inventory, and `git status --short`; only pre-existing worktree delta is this heartbeat section; next action: inspect owner code-entry files and add RED tests first where feasible.
- 2026-05-07 16:50:51 CEST | final verdict written | fresh Executor exceeded the bounded wait plus one progress-based extension and was closed while still running; repo inspection showed no assigned code/test/doc delta beyond this heartbeat section and no required direct tests or named gates run; QA was not spawned because Executor produced no trustworthy completion evidence; local sequential fallback not used because this controller is not an already-isolated child execution agent; final verdict: `blocked`; blocker class: `spawn_or_tool_failure`; next action: retry from a fresh isolated outer execution agent that can use the skill's local fallback if nested child materialization fails, or split this large vertical slice into smaller execution-ready session plans before rerunning.
