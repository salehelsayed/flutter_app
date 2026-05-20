# INTEGRATE-PL-010 Worktree-to-Main Integration Contract

Status: accepted

Source of truth:
- Source worktree: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline`
- Historical source plan: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-PL-010-plan.md`
- Source row: `PL-010` / Removed member reaction is rejected and does not mutate visible state
- Row-owned source anchors:
  - `test/features/groups/application/send_group_reaction_use_case_test.dart`: `PL-010 removed member reaction send is rejected without publish or local mutation`
  - `test/features/groups/application/handle_incoming_group_reaction_use_case_test.dart`: `PL-010 removed sender reaction is ignored without mutating visible state`
  - `test/features/groups/integration/group_reaction_roundtrip_test.dart`: `PL-010 removed member reaction is ignored by Alice and Bob without visible mutation`
  - `integration_test/group_multi_party_device_real_harness.dart`: `private_removed_reaction_rejected`
  - `integration_test/scripts/group_multi_party_device_criteria.dart`: `private_removed_reaction_rejected` criteria
  - `integration_test/scripts/run_group_multi_party_device_real.dart`: `private_removed_reaction_rejected` scenario registration
  - `test/integration/group_multi_party_device_criteria_test.dart`: PL-010 criteria accept/reject selectors

Imported delta:
- Added row-owned app tests proving a removed member's reaction send is rejected without publish, local mutation, replay outbox, or extra save, and an incoming removed-sender reaction is ignored without mutating preexisting visible reaction state.
- Added the row-owned fake-network proof that Charlie retains an old local target message, is removed, attempts a stale reaction, and Alice/Bob observe no visible reaction mutation.
- Added `private_removed_reaction_rejected` live-harness, runner, criteria, and criteria-test coverage proving Alice and Bob exclude Charlie and observe unchanged reactions while Charlie proves local removal/exclusion, old-message retention, rejected app-peer reaction outcome, and zero local reaction persistence.
- Adapted the source criteria to current main by allowing Charlie top-level `keyEpoch: 0` for this removed-member verdict while still requiring the retained target message to carry epoch `1`.

Out of scope:
- No original source worktree plan recreation or rerun.
- No PL-011+ re-added reaction rows, media payload rows, notifications, privacy, stress, Android, physical iOS, source-doc, COMPLETE_1 doc, or unrelated fixture repair.
- No production reaction path rewrite; current main already rejects local non-member sends and ignores unknown/removed incoming reaction senders before visible mutation.

Verification evidence:
- `flutter test --no-pub test/features/groups/application/send_group_reaction_use_case_test.dart --plain-name "PL-010 removed member reaction send is rejected without publish or local mutation"` - pass
- `flutter test --no-pub test/features/groups/application/handle_incoming_group_reaction_use_case_test.dart --plain-name "PL-010 removed sender reaction is ignored without mutating visible state"` - pass
- `flutter test --no-pub test/features/groups/integration/group_reaction_roundtrip_test.dart --plain-name "PL-010 removed member reaction is ignored by Alice and Bob without visible mutation"` - pass
- `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --name "PL-010 (accepts removed reaction rejection verdicts|rejects visible reaction mutation on remaining member|rejects accepted app-peer reaction after removal)"` - pass
- Preservation selectors passed: PL-009 reaction send, incoming reaction idempotence, existing fake-network reaction roundtrip/no-roundtrip selectors, GM-004/GM-016 removed-member smoke selectors, and Go native `TestGL008|TestGK025|TestGK033|TestGA003`.
- `dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario private_removed_reaction_rejected --list-scenarios` - pass, lists `private_removed_reaction_rejected`.
- `dart format --set-exit-if-changed` over the seven touched Dart files - pass with 0 changed after formatting.
- Scoped `dart analyze` over the seven touched Dart files - pass, `No issues found!`.
- `git diff --check` - pass.
- Required iOS 26.2 live proof passed: run id `1779311981796`, shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_private_removed_reaction_rejected_3Ssozo`, Alice `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`, Bob `279B82AE-2BB9-4924-9AAE-581870ED3FA9`, Charlie `116B4AF6-C1A9-4F36-B929-0A7130B5E83C`, orchestrator verdict `private_removed_reaction_rejected proof passed: private_removed_reaction_rejected verdicts valid for alice, bob, charlie`.

Controller acceptance evidence:
- Read-only scouts confirmed current main already had the core production fail-closed behavior, while PL-010-specific app-visible tests, fake-network proof, live scenario, runner registration, criteria validation, and criteria fixtures were missing or partial.
- The controller rechecked row-owned file inventory before execution and imported only PL-010 removed-member reaction deltas, leaving PL-011+ and adjacent payload/media rows untouched.
- All required focused row tests, affected PL-009/COMPLETE_1 preservation selectors, scoped maintenance checks, and iOS 26.2 live proof passed.
