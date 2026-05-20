# INTEGRATE-DE-017 Worktree-To-Main Integration Contract

Status: accepted

## Scope

Import and reconcile only source row `DE-017`: membership events must be applied before the first dependent content message.

This is a standard integration contract, not a regeneration of the historical worktree implementation plan. The source plan and closure evidence remain the historical source of truth.

Out of scope: unknown event recovery (`DE-018`), EventChannel recovery, dispatcher starvation, unrelated offline replay repairs, unrelated native/bridge behavior, UI, media, notification, relay changes, source docs, COMPLETE_1 docs, and adjacent row closure.

## Reconciliation

- `GroupMember` config JSON now preserves `joinedAt`, so invite/config replay can keep the membership interval needed by DE-017.
- `GroupMessageListener` gained the row-owned live membership-dependent content buffer. Live content from an unknown sender can wait for the matching `member_added`/`members_added` watermark; replay handling stays unbuffered to preserve existing offline replay semantics.
- Membership removal handling now deletes or buffers content at and after the removal boundary while retaining entitled pre-removal local history.
- The source global before-joined rejection in `handle_incoming_group_message_use_case.dart` was not imported because it conflicts with existing offline replay preservation contracts. The equivalent DE-017 live/content ordering rule is enforced in the listener flush path.
- The row-owned host tests, criteria tests, runner switch, and live harness scenario `de017` were imported. The DE-017 criteria exception for removed Charlie's nonnegative key epoch was preserved after the first local live proof exposed the mismatch.

## Verification

Passed:

```bash
flutter test --no-pub test/features/groups/domain/models/group_member_test.dart --plain-name 'config JSON preserves joined interval for invite replay'
flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name 'DE-017'
flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'DE-017'
flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'DE-017'
flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --name 'GM-014|ML-009|KE-012|DE-014'
flutter test --no-pub test/features/groups/application/group_key_update_listener_test.dart --plain-name 'GM-014'
flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --name 'GM-014|GM-034|GM-035|ML-009|KE-012'
flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --name 'GE-004|GE-008|GE-009'
flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --name 'DE-017|GM-014|GM-033|GM-034|GM-035|GE-004|GE-008|GE-009|ML-009|KE-012'
flutter analyze --no-pub lib/features/groups/domain/models/group_member.dart lib/features/groups/application/group_message_listener.dart lib/features/groups/application/handle_incoming_group_message_use_case.dart integration_test/group_multi_party_device_real_harness.dart integration_test/scripts/group_multi_party_device_criteria.dart integration_test/scripts/run_group_multi_party_device_real.dart test/features/groups/domain/models/group_member_test.dart test/features/groups/application/group_message_listener_test.dart test/features/groups/integration/group_resume_recovery_test.dart test/integration/group_multi_party_device_criteria_test.dart test/shared/fakes/group_test_user.dart test/features/groups/integration/group_messaging_smoke_test.dart test/features/groups/integration/group_edge_cases_smoke_test.dart
dart format lib/features/groups/domain/models/group_member.dart lib/features/groups/application/group_message_listener.dart integration_test/group_multi_party_device_real_harness.dart integration_test/scripts/group_multi_party_device_criteria.dart integration_test/scripts/run_group_multi_party_device_real.dart test/features/groups/domain/models/group_member_test.dart test/features/groups/application/group_message_listener_test.dart test/features/groups/integration/group_resume_recovery_test.dart test/integration/group_multi_party_device_criteria_test.dart
git diff --check
```

iOS 26.2 live proof passed:

```bash
MKNOON_RELAY_ADDRESSES=<configured relay list> dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario de017 -d 5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3,279B82AE-2BB9-4924-9AAE-581870ED3FA9,116B4AF6-C1A9-4F36-B929-0A7130B5E83C
```

Result: run id `1779152294735`, shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_de017_WC3Uvm`, Alice `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`, Bob `279B82AE-2BB9-4924-9AAE-581870ED3FA9`, Charlie `116B4AF6-C1A9-4F36-B929-0A7130B5E83C`, final result `de017 proof passed: de017 verdicts valid for alice, bob, charlie`.

Named gates:

```bash
FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups
```

Result: red at `+208 -3` only on preserved non-DE-017 residuals `BB-007`, `BB-012`, and `GM-029`.

```bash
./scripts/run_test_gates.sh completeness-check
```

Result: red on the unrelated `test/shared/fakes/fake_group_pubsub_network_test.dart` classification residual (`732/733`).

Affected drain preservation command:

```bash
flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --name 'GM-014|GM-033|GEK002|GEK003'
```

Result: `GM-014` and `GEK002` passed; `GM-033` and `GEK003` remain red as existing offline replay/drain residuals after the conflicting global source guard was removed and DE-017 buffering was scoped to live traffic.
