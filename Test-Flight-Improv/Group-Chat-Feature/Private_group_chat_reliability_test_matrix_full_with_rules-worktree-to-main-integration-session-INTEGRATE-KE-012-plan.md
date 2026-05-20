# INTEGRATE-KE-012 Integration Contract - Delayed Old Config After Re-add

Status: accepted

Created: 2026-05-18

## Source Row

- Worktree source matrix row: `KE-012`
- Integration session: `INTEGRATE-KE-012`
- Title: `Delayed old config after re-add does not remove active members`
- Historical worktree plan: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-KE-012-plan.md`
- Historical worktree plan status: `accepted`
- Reused live scenario: `private_readd_current`
- Active integration mode: standard worktree-to-main integration, not gap closure

## Row Contract

After Alice, Bob, and Charlie converge on the final re-add config at the current epoch, a delayed older config snapshot must not remove Bob or Charlie, roll back membership, downgrade the epoch, or issue stale `group:updateConfig` writes. Post-stale Alice/Bob/Charlie delivery must remain authorized at the current epoch.

This row is independent of the KE-007/KE-009/KE-017 higher-epoch receive-repair blocker because KE-012 covers stale lower-membership config handling after re-add, not missing local key repair for a message ahead of local key state.

## Integration Decision

Current main already preserved the production stale-membership watermark behavior used by this row. This session imported only the missing KE-012 row-owned proof surface:

- listener proof that a delayed old `member_added` config snapshot after re-add cannot remove active Bob/Charlie or emit stale `group:updateConfig`;
- fake-network smoke proof that Alice/Bob/Charlie stay active and deliver at the current epoch after the stale config;
- `private_readd_current` criteria validation and negative criteria tests for `ke012DelayedOldConfigAfterReaddProof`;
- KE-012 live-harness delayed old config publication, Bob/Charlie stale-event ignore waits, and Alice/Bob/Charlie verdict fields in the existing `private_readd_current` flow.

No production files were changed. Adjacent KE-007/KE-009/KE-017 higher-epoch receive-repair work, source docs, and unrelated worktree deltas were not imported.

## Owned Files

- `test/features/groups/application/group_message_listener_test.dart`
- `test/features/groups/integration/group_membership_smoke_test.dart`
- `integration_test/scripts/group_multi_party_device_criteria.dart`
- `test/integration/group_multi_party_device_criteria_test.dart`
- `integration_test/group_multi_party_device_real_harness.dart`
- this integration contract
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-breakdown.md`

## Scope Guard

Do not import or repair KE-007, KE-009, KE-013+, KE-017, RA-006, higher-epoch missing-key repair, stale invite ordering, BB-007, BB-012, GM-029, ML-012 external-fixture work, source matrix docs, COMPLETE_1 docs, source `test-inventory.md`, UI, media, notification, relay, or broader key-safety work under this row.

If a test already had equivalent or stronger coverage in main, keep that coverage and merge only the missing KE-012 assertion. Do not duplicate GM-012 stale-remove coverage or overwrite existing shared criteria fixtures.

## Required Evidence

- `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name 'KE-012'`
- `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'KE-012'`
- `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'private_readd_current'`
- affected GM-012 preservation selectors
- full `test/integration/group_multi_party_device_criteria_test.dart`
- scoped format/analyzer/diff hygiene
- named `groups` and `completeness-check` gates, preserving known non-KE-012 residuals
- iOS 26.2 `private_readd_current` live proof

## Final Execution Verdict

Verdict: accepted.

Imported the KE-012 delayed-old-config-after-readd proof surface into current main without changing production code. A stale older config snapshot after Charlie is re-added is ignored, Bob and Charlie remain active, the final epoch stays current, and Alice/Bob/Charlie post-stale delivery remains valid at epoch `2`.

Accepted files:

- `test/features/groups/application/group_message_listener_test.dart`
- `test/features/groups/integration/group_membership_smoke_test.dart`
- `integration_test/scripts/group_multi_party_device_criteria.dart`
- `test/integration/group_multi_party_device_criteria_test.dart`
- `integration_test/group_multi_party_device_real_harness.dart`
- this integration contract
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-breakdown.md`

Focused and preservation evidence:

- `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name 'KE-012'` PASS (`+1`).
- `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'KE-012'` PASS (`+1`).
- `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'private_readd_current'` PASS (`+13`).
- `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name 'GM-012'` PASS (`+1`).
- `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-012 add then stale remove arrives out of order'` PASS (`+1`).
- `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name GM-012` PASS (`+7`).
- `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart` PASS (`+285`).
- `flutter analyze --no-pub` on the five touched code/test/harness files PASS (`No issues found!`).
- `dart format --set-exit-if-changed` on the five touched code/test/harness files PASS (`Formatted 5 files (0 changed)`).
- `dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario private_readd_current --list-scenarios` PASS (`private_readd_current` listed).
- `git diff --check` PASS before doc closure.

Named gate evidence:

- `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` remains red at `+187 -3` on preserved non-KE-012 residuals:
  - `BB-007 accepted pending invite joins with exact full config and replays accepted epoch` fails with `Expected: not null / Actual: <null>` at `test/features/groups/integration/invite_round_trip_test.dart:679`.
  - `BB-012 restart recovery drains replay before ack and stays live` fails with no replayed message at `test/features/groups/integration/group_startup_rejoin_smoke_test.dart:725`; previous isolated evidence ties this to the May 11, 2026 replay fixture being older than the seven-day retention cutoff on May 18, 2026.
  - `GM-029 config version monotonicity converges across A/B/C shuffled delivery` fails with `Expected: MemberRole.writer / Actual: MemberRole.reader` at `test/features/groups/integration/group_membership_smoke_test.dart:8144`.
- `./scripts/run_test_gates.sh completeness-check` remains red on the unrelated classification gap `test/shared/fakes/fake_group_pubsub_network_test.dart` (`732/733` classified).

Live proof evidence:

- iOS 26.2 devices: Alice `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`, Bob `279B82AE-2BB9-4924-9AAE-581870ED3FA9`, Charlie `116B4AF6-C1A9-4F36-B929-0A7130B5E83C`.
- `private_readd_current` exact-relay live proof PASS with run id `1779116430158`, shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_private_readd_current_CUTfkK`, and orchestrator detail `private_readd_current verdicts valid for alice, bob, charlie`.
- Alice verdict recorded `ke012DelayedOldConfigAfterReaddProof.rowId=KE-012`, delayed old config delivery after re-add, Alice post-stale config send at current epoch, and final epoch `2`.
- Bob verdict recorded `keptActiveAfterDelayedOldConfig=true`, observed Charlie re-add, Charlie post-stale config/current-epoch receive, Bob post-stale config/current-epoch send, and final epoch `2`.
- Charlie verdict recorded `keptFinalMembersAfterDelayedOldConfig=true`, `keptCurrentEpochAfterDelayedOldConfig=true`, post-stale publish acceptance, Alice/Bob post-stale config receives at current epoch, `epochBeforeDelayedOldConfig=2`, `epochAfterDelayedOldConfig=2`, and final epoch `2`.

Skipped/out-of-scope:

- Production `lib/features/groups/application/group_message_listener.dart` stale-membership watermark behavior was already present and was not changed.
- KE-007, KE-009, KE-013+, KE-017, RA-006, source worktree docs, COMPLETE_1 docs, source `test-inventory.md`, BB-007 repair, BB-012 retention-fixture repair, GM-029 repair, ML-012 external-fixture repair, notification, media, UI, relay, and broader lifecycle work were not imported.

Safe next action: continue with `INTEGRATE-KE-013` after ledger sanity and dirty-state safety checks, preserving KE-007 and KE-009 conflict blockers, ML-012 external-fixture blocker, BB-007/BB-012/GM-029 residual group-gate failures, and the completeness classification gap.
