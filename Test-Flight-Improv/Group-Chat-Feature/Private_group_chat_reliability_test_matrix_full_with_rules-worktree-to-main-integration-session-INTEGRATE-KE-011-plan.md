# INTEGRATE-KE-011 Integration Contract - Delayed Old Key After Re-add

Status: accepted

Created: 2026-05-18

## Source Row

- Worktree source matrix row: `KE-011`
- Integration session: `INTEGRATE-KE-011`
- Title: `Delayed old key update after re-add does not break C again`
- Historical worktree plan: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-KE-011-plan.md`
- Historical worktree plan status: `accepted`
- Reused live scenario: `private_readd_current`
- Active integration mode: standard worktree-to-main integration, not gap closure

## Row Contract

After Charlie is removed and re-added at the current epoch, a delayed lower-epoch key update must not downgrade Charlie's latest key state or break current-epoch delivery. The delayed old key may be retained as historical material, but it must not trigger `group:updateKey`, repair, or replacement of the re-add epoch.

This row is independent of the KE-007/KE-009/KE-017 higher-epoch receive-repair blocker because KE-011 covers lower-epoch delayed key handling after re-add, not missing-key repair for a message ahead of local key state.

## Integration Decision

Current main already preserved latest-key lower-bound behavior in production. This session imported only the missing KE-011 row-owned proof surface:

- listener proof that delayed lower-epoch key material after re-add is stored historically without downgrading the latest key;
- fake-network smoke proof that Charlie remains on the re-add epoch and Alice/Bob current delivery still works;
- `private_readd_current` criteria validation and negative criteria tests for `ke011DelayedOldKeyAfterReaddProof`;
- KE-011 live-harness verdict fields in the existing `private_readd_current` Alice/Bob/Charlie blocks.

No production files were changed. Source worktree blocks that carried adjacent RA-006 or KE-012 proof fields were not copied.

## Owned Files

- `test/features/groups/application/group_key_update_listener_test.dart`
- `test/features/groups/integration/group_messaging_smoke_test.dart`
- `integration_test/scripts/group_multi_party_device_criteria.dart`
- `test/integration/group_multi_party_device_criteria_test.dart`
- `integration_test/group_multi_party_device_real_harness.dart`
- this integration contract
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-breakdown.md`

## Scope Guard

Do not import or repair KE-007, KE-009, KE-012, KE-017, RA-006, delayed old config, stale invite ordering, higher-epoch missing-key repair, BB-007, BB-012, GM-029, ML-012 external-fixture work, source matrix docs, COMPLETE_1 docs, source `test-inventory.md`, UI, media, notification, relay, or broader key-safety work under this row.

If a test already had equivalent or stronger coverage in main, keep that coverage and merge only the missing KE-011 assertion. Do not wholesale copy source worktree blocks that include adjacent row fields.

## Required Evidence

- `flutter test --no-pub test/features/groups/application/group_key_update_listener_test.dart --plain-name 'KE-011'`
- `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name 'KE-011'`
- `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'private_readd_current'`
- full `test/integration/group_multi_party_device_criteria_test.dart`
- affected preservation selectors for KE-003/KE-004/KE-005, KE-008/IJ014, KE-010, GE-011/GE-017/GE-019/GE-020, ML-007/GM-006/GM-007/GM-008/GM-019/GM-021/GM-024/GM-035, and macOS ML-007 real-crypto onboarding
- scoped format/analyzer/diff hygiene
- named `groups` and `completeness-check` gates, preserving known non-KE-011 residuals
- iOS 26.2 `private_readd_current` live proof

## Final Execution Verdict

Verdict: accepted.

Imported the KE-011 delayed-old-key-after-readd proof surface into current main without changing production code. Charlie keeps the current re-add epoch after receiving the delayed old key, stores the stale key historically, and Alice/Bob/Charlie post-stale delivery remains at the current epoch.

Accepted files:

- `test/features/groups/application/group_key_update_listener_test.dart`
- `test/features/groups/integration/group_messaging_smoke_test.dart`
- `integration_test/scripts/group_multi_party_device_criteria.dart`
- `test/integration/group_multi_party_device_criteria_test.dart`
- `integration_test/group_multi_party_device_real_harness.dart`
- this integration contract
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-breakdown.md`

Focused and preservation evidence:

- `flutter test --no-pub test/features/groups/application/group_key_update_listener_test.dart --plain-name 'KE-011'` PASS (`+1`).
- `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name 'KE-011'` PASS (`+1`).
- `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'private_readd_current'` PASS (`+11`).
- `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart` PASS (`+283`).
- `flutter test --no-pub test/features/groups/application/group_key_update_listener_test.dart --name 'KE-003|KE-004|KE-005'` PASS (`+2`; no KE-003 selector title exists in this file).
- `flutter test --no-pub test/features/groups/application/accept_pending_group_invite_use_case_test.dart --name 'KE-008|IJ014 repaired pending invite can retry successfully after key material refresh'` PASS (`+2`).
- `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name 'KE-010'` PASS (`+1`).
- `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --name 'KE-010|GE-011|GE-017|GE-019|GE-020'` PASS (`+5`).
- `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --name 'ML-007|GM-006|GM-007|GM-008|GM-019|GM-021|GM-024|GM-035'` PASS (`+8`).
- `flutter test --no-pub -d macos integration_test/group_real_crypto_onboarding_test.dart --plain-name 'ML-007'` PASS (`+1`), with only existing macOS deployment/linker/open foreground warnings.
- `dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario private_readd_current --list-scenarios` PASS (`private_readd_current` listed).
- Full `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart` PASS (`+45`).
- `dart format --set-exit-if-changed` on the five KE-011 touched code/test/harness files PASS (`Formatted 5 files (0 changed)` after formatting).
- `flutter analyze --no-pub` on the four touched files other than `group_key_update_listener_test.dart` PASS (`No issues found!`).
- `flutter analyze --no-pub` on all five touched files returned only pre-existing info-level lints in top-level helpers inside `test/features/groups/application/group_key_update_listener_test.dart` (`no_leading_underscores_for_local_identifiers` and `use_null_aware_elements`), not KE-011 logic failures.
- Scoped `git diff --check` PASS before doc closure.

Named gate evidence:

- `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` remains red at `+186 -3` on preserved non-KE-011 residuals:
  - `BB-007 accepted pending invite joins with exact full config and replays accepted epoch` fails with `Expected: not null / Actual: <null>` at `test/features/groups/integration/invite_round_trip_test.dart:679`.
  - `BB-012 restart recovery drains replay before ack and stays live` fails with no replayed message at `test/features/groups/integration/group_startup_rejoin_smoke_test.dart:725`; previous isolated evidence ties this to the May 11, 2026 replay fixture being older than the seven-day retention cutoff on May 18, 2026.
  - `GM-029 config version monotonicity converges across A/B/C shuffled delivery` fails with `Expected: MemberRole.writer / Actual: MemberRole.reader` at `test/features/groups/integration/group_membership_smoke_test.dart:8144`.
- `./scripts/run_test_gates.sh completeness-check` remains red on the unrelated classification gap `test/shared/fakes/fake_group_pubsub_network_test.dart` (`732/733` classified).

Live proof evidence:

- iOS 26.2 devices: Alice `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`, Bob `279B82AE-2BB9-4924-9AAE-581870ED3FA9`, Charlie `116B4AF6-C1A9-4F36-B929-0A7130B5E83C`.
- `private_readd_current` exact-relay live proof PASS with run id `1779115138816`, shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_private_readd_current_IoV4iz`, and orchestrator detail `private_readd_current verdicts valid for alice, bob, charlie`.
- Alice verdict recorded `ke011DelayedOldKeyAfterReaddProof.rowId=KE-011`, delayed old key delivery after re-add, Alice post-stale send at current epoch, stale epoch `1`, and final epoch `2`.
- Bob verdict recorded observed Charlie re-add, Charlie post-stale/current-epoch receive, Bob post-stale/current-epoch send, stale epoch `1`, and final epoch `2`.
- Charlie verdict recorded keeping epoch `2` after delayed old epoch `1`, storing the delayed old key as historical, post-stale publish acceptance, Alice/Bob post-stale receives at current epoch, and final epoch `2`.

Skipped/out-of-scope:

- Production `lib/features/groups/application/group_key_update_listener.dart` lower-epoch handling was already present and was not changed.
- KE-007, KE-009, KE-012, KE-017, RA-006, source worktree docs, COMPLETE_1 docs, source `test-inventory.md`, BB-007 repair, BB-012 retention-fixture repair, GM-029 repair, ML-012 external-fixture repair, notification, media, UI, and broader lifecycle work were not imported.

Safe next action: continue with `INTEGRATE-KE-012` after ledger sanity and dirty-state safety checks, preserving KE-007 and KE-009 conflict blockers, ML-012 external-fixture blocker, BB-007/BB-012/GM-029 residual group-gate failures, and the completeness classification gap.
