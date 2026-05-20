# INTEGRATE-KE-010 Integration Contract - Key Before Config Authorization Guard

Status: accepted

Created: 2026-05-18

## Source Row

- Worktree source matrix row: `KE-010`
- Integration session: `INTEGRATE-KE-010`
- Title: `Out-of-order key-before-config does not grant unauthorized access`
- Historical worktree plan: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-KE-010-plan.md`
- Historical worktree plan status: `accepted`
- Reused live scenario: `private_readd_current`
- Active integration mode: standard worktree-to-main integration, not gap closure

## Row Contract

If Charlie has the current epoch key before Charlie's local recipient membership/config row has arrived, Charlie must not accept regular plaintext group messages for that epoch. After the local recipient membership/config arrives, Charlie may receive and persist current-epoch messages normally.

This row is independent of the KE-007/KE-009/KE-017 higher-epoch receive-repair blocker because KE-010 covers a local authorization precondition when a matching key already exists, not missing-key repair for messages ahead of local key state.

## Integration Decision

Current main had adjacent lower-bound and removed-window protections, but it did not reject regular incoming messages when the local self member row was absent. This session imported only the missing KE-010 row-owned delta:

- regular incoming messages now require a local self membership row when `selfPeerId` is known;
- focused listener and fake-network smoke tests for key-before-config ordering;
- `private_readd_current` criteria validation and negative criteria tests for `ke010KeyBeforeConfigProof`;
- KE-010 live-harness verdict fields in the existing `private_readd_current` Alice/Bob/Charlie blocks.

The integration preserved existing GK-024 `enforceSelfJoinedAtLowerBound` behavior and did not import adjacent KE-009, KE-011, KE-012, or RA proof fields from the source worktree.

## Owned Files

- `lib/features/groups/application/handle_incoming_group_message_use_case.dart`
- `test/features/groups/application/group_message_listener_test.dart`
- `test/features/groups/integration/group_messaging_smoke_test.dart`
- `integration_test/scripts/group_multi_party_device_criteria.dart`
- `test/integration/group_multi_party_device_criteria_test.dart`
- `integration_test/group_multi_party_device_real_harness.dart`
- this integration contract
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-breakdown.md`

## Scope Guard

Do not import or repair KE-007, KE-009, KE-011, KE-012, KE-017, RA-006, stale old config/invite ordering, higher-epoch missing-key repair, UI compose, notification, media, source matrix rewrites, COMPLETE_1 docs, source `test-inventory.md`, BB-007, BB-012, GM-029, or ML-012 external-fixture work under this row.

If a test already had equivalent or stronger coverage in main, keep that coverage and merge only the missing KE-010 assertion. Do not wholesale copy source worktree blocks that include adjacent row fields.

## Required Evidence

- `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name 'KE-010'`
- `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name 'KE-010'`
- `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'private_readd_current'`
- full `test/integration/group_multi_party_device_criteria_test.dart`
- affected preservation selectors for GP-025, GE-011/GE-017/GE-019/GE-020, ML-007/GM-035, KE-008, IJ014, and handle-incoming dedupe behavior
- scoped format/analyzer/diff hygiene
- named `groups` and `completeness-check` gates, preserving known non-KE-010 residuals
- iOS 26.2 `private_readd_current` live proof

## Final Execution Verdict

Verdict: accepted.

Imported the KE-010 key-before-config authorization guard and row-owned proof surface into current main. A regular message now fails closed while the local recipient membership row is absent, then accepts current-epoch traffic once the config/member row arrives. System messages remain allowed so membership/config repair can still land.

Accepted files:

- `lib/features/groups/application/handle_incoming_group_message_use_case.dart`
- `test/features/groups/application/group_message_listener_test.dart`
- `test/features/groups/integration/group_messaging_smoke_test.dart`
- `integration_test/scripts/group_multi_party_device_criteria.dart`
- `test/integration/group_multi_party_device_criteria_test.dart`
- `integration_test/group_multi_party_device_real_harness.dart`
- this integration contract
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-breakdown.md`

Focused and preservation evidence:

- `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name 'KE-010'` PASS (`+1`).
- `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name 'KE-010'` PASS (`+1`).
- `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'private_readd_current'` PASS (`+9`).
- `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart` PASS (`+281`).
- `flutter test --no-pub test/features/groups/application/handle_incoming_group_message_use_case_test.dart --plain-name 'deduplicates by messageId'` PASS (`+1`).
- `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name 'GP-025'` PASS (`+1`) after adding the missing local self-member fixture required by the new guard.
- `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --name 'GE-011|GE-017|GE-019|GE-020'` PASS (`+4`).
- `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --name 'ML-007|GM-035'` PASS (`+2`).
- `flutter test --no-pub test/features/groups/application/accept_pending_group_invite_use_case_test.dart --plain-name 'KE-008'` PASS (`+1`).
- `flutter test --no-pub test/features/groups/application/accept_pending_group_invite_use_case_test.dart --plain-name 'IJ014 repaired pending invite can retry successfully after key material refresh'` PASS (`+1`).
- `flutter test --no-pub -d macos integration_test/group_real_crypto_onboarding_test.dart --plain-name 'ML-007'` PASS (`+1`), with only macOS deployment/Go framework/open foreground warnings.
- `flutter analyze --no-pub` on the six KE-010 touched code/test/harness files PASS (`No issues found!`).
- `dart format --set-exit-if-changed` on the six KE-010 touched code/test/harness files PASS (`Formatted 6 files (0 changed)` after formatting).
- Scoped `git diff --check` PASS before doc closure.

Named gate evidence:

- `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` remains red at `+185 -3` on preserved non-KE-010 residuals:
  - `BB-007 accepted pending invite joins with exact full config and replays accepted epoch` fails with `Expected: not null / Actual: <null>` at `test/features/groups/integration/invite_round_trip_test.dart:679`.
  - `BB-012 restart recovery drains replay before ack and stays live` fails with no replayed message at `test/features/groups/integration/group_startup_rejoin_smoke_test.dart:725`; isolated BB-012 reproduces the same failure because the fixture's May 11, 2026 replay timestamp is now older than the seven-day retention cutoff on May 18, 2026.
  - `GM-029 config version monotonicity converges across A/B/C shuffled delivery` fails with `Expected: MemberRole.writer / Actual: MemberRole.reader` at `test/features/groups/integration/group_membership_smoke_test.dart:8144`.
- Isolated full `group_messaging_smoke_test.dart` PASS (`+44`), including the KE-010 fake-network smoke proof.
- `./scripts/run_test_gates.sh completeness-check` remains red on the unrelated classification gap `test/shared/fakes/fake_group_pubsub_network_test.dart` (`732/733` classified).

Live proof evidence:

- iOS 26.2 devices: Alice `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`, Bob `279B82AE-2BB9-4924-9AAE-581870ED3FA9`, Charlie `116B4AF6-C1A9-4F36-B929-0A7130B5E83C`.
- `private_readd_current` exact-relay live proof PASS with run id `1779113848849`, shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_private_readd_current_OC0sJL`, and orchestrator detail `private_readd_current verdicts valid for alice, bob, charlie`.
- Alice verdict recorded `ke010KeyBeforeConfigProof.rowId=KE-010`, fake-network key-before-config ordering coverage, live authorized delivery coverage, post-config authorized send at current epoch, and final epoch `2`.
- Bob verdict recorded observed Charlie authorization, Charlie post-config/current-epoch receive, Bob post-config/current-epoch send, live authorized delivery coverage, and final epoch `2`.
- Charlie verdict recorded no pre-config plaintext despite having the key, Alice and Bob post-config/current-epoch receives, live authorized delivery coverage, and final epoch `2`.

Skipped/out-of-scope:

- KE-007, KE-009, and KE-017 higher-epoch missing-key repair remained blocked/out of scope.
- KE-011, KE-012, RA-006, source worktree docs, COMPLETE_1 docs, source `test-inventory.md`, BB-007 repair, BB-012 retention-fixture repair, GM-029 repair, ML-012 external-fixture repair, notification, media, UI, and broader lifecycle work were not imported.

Safe next action: continue with `INTEGRATE-KE-011` after ledger sanity and dirty-state safety checks, preserving KE-007 and KE-009 conflict blockers, ML-012 external-fixture blocker, BB-007/BB-012/GM-029 residual group-gate failures, and the completeness classification gap.
