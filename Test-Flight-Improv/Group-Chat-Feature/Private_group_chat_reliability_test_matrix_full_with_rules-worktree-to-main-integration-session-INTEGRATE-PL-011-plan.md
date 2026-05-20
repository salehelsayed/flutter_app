# INTEGRATE-PL-011 Worktree-to-Main Integration Contract

Status: accepted

Source of truth:
- Source worktree: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline`
- Historical source plan: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-PL-011-plan.md`
- Source row: `PL-011` / Re-added member reaction after current key update succeeds
- Row-owned source anchors:
  - `test/features/groups/application/send_group_reaction_use_case_test.dart`: `PL-011 re-added member with current key publishes reaction and stores once`
  - `test/features/groups/application/handle_incoming_group_reaction_use_case_test.dart`: `PL-011 re-added sender reaction applies once after current membership update`
  - `test/features/groups/integration/group_reaction_roundtrip_test.dart`: `PL-011 re-added member reaction reaches Alice and Bob exactly once`
  - `integration_test/group_multi_party_device_real_harness.dart`: `private_readd_current` `pl011ReaddReactionProof`
  - `integration_test/scripts/group_multi_party_device_criteria.dart`: PL-011 validation inside `private_readd_current`
  - `test/integration/group_multi_party_device_criteria_test.dart`: PL-011 criteria accept/reject selectors

Imported delta:
- Added row-owned app tests proving a removed-then-re-added Charlie with the current epoch/device binding can publish a reaction, persist exactly one local reaction, and preserve the expected replay/inbox envelope fields.
- Added the row-owned incoming reaction test proving a re-added sender's reaction applies once after current membership state is restored.
- Added the row-owned fake-network proof that Charlie reacts to Alice's post-readd visible message and Alice/Bob observe the reaction exactly once.
- Added `pl011ReaddReactionProof` to the existing `private_readd_current` live proof path, with strict criteria for current-epoch target visibility, Charlie local storage, Alice/Bob receiver stream evidence, and no removed-window plaintext leakage.
- Reused the existing `private_readd_current` runner scenario; no new scenario registration was needed.

Out of scope:
- No original source worktree plan recreation or rerun.
- No PL-012+ media schema rows, notifications, privacy, stress, Android, physical iOS, source-doc, COMPLETE_1 doc, or unrelated fixture repair.
- No production reaction path rewrite; current main already had the required active/re-added reaction semantics, so this row imports the missing row-owned proof and regression coverage.

Verification evidence:
- `flutter test --no-pub test/features/groups/application/send_group_reaction_use_case_test.dart --plain-name "PL-011 re-added member with current key publishes reaction and stores once"` - pass
- `flutter test --no-pub test/features/groups/application/handle_incoming_group_reaction_use_case_test.dart --plain-name "PL-011 re-added sender reaction applies once after current membership update"` - pass
- `flutter test --no-pub test/features/groups/integration/group_reaction_roundtrip_test.dart --plain-name "PL-011 re-added member reaction reaches Alice and Bob exactly once"` - pass
- `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --name "PL-011"` - pass
- Preservation selectors passed: PL-009/PL-010 reaction send, incoming, fake-network, and criteria selectors; `PL-007 accepts private_readd_current`; `accepts private_readd_current PL-004`; `accepts private_readd_current ML-007`; `RA-016 accepts private_readd_current`; and GM-006/GM-007 membership smoke selectors.
- `dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario private_readd_current --list-scenarios` - pass, lists `private_readd_current`.
- `dart format --set-exit-if-changed` over the six touched Dart files - pass with 0 changed after formatting.
- Scoped `dart analyze` over the six touched Dart files - pass, `No issues found!`.
- `git diff --check` - pass.
- Required iOS 26.2 live proof passed: `private_readd_current` run id `1779313301896`, shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_private_readd_current_8mwrgL`, Alice `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`, Bob `279B82AE-2BB9-4924-9AAE-581870ED3FA9`, Charlie `116B4AF6-C1A9-4F36-B929-0A7130B5E83C`, orchestrator verdict `private_readd_current proof passed: private_readd_current verdicts valid for alice, bob, charlie`.

Controller acceptance evidence:
- Read-only scouts confirmed current main already had the core re-added reaction behavior, while PL-011-specific app tests, fake-network proof, live proof fields, criteria validation, and criteria fixtures were missing.
- The controller rechecked row-owned file inventory before execution and imported only PL-011 re-added reaction deltas, leaving PL-012+ payload/media rows untouched.
- All required focused row tests, affected PL-009/PL-010 and `private_readd_current` preservation selectors, scoped maintenance checks, and iOS 26.2 live proof passed.
