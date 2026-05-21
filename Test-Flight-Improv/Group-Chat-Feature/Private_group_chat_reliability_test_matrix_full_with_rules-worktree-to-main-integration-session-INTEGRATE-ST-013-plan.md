# INTEGRATE-ST-013 Plan - Standard Integration Contract

Status: blocked_external_fixture

## Scope

Import and verify historical row `ST-013`: "Relay chaos with store, retrieve, cursor, and repair failures."

This was standard worktree-to-main integration, not gap-closure. The historical source plan and closure evidence stayed the source of truth; no original implementation plan was regenerated.

## Source Evidence

- Historical source plan: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-ST-013-plan.md`.
- Source row-owned proof selectors:
  - `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name "ST-013"`
  - `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name "ST-013"`
  - `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name "ST-013"`
- Source 3-party E2E: required on `private_network_chaos_invariants`.

## Imported Delta

- Imported the row-owned direct drain proof for retrieve retry, cursor-page retry, history-repair failure surfacing, media replay retry, synthetic cursor advancement, and no silent completion.
- Imported the row-owned fake-network proof for inbox store retry ownership, retrieve failure visibility, offline media replay recovery, and unrecoverable gap surfacing.
- Imported `st013RelayChaosProof` live-harness emission for `private_network_chaos_invariants`.
- Imported criteria validation and accept/missing/weak proof tests for the ST-013 proof.

## Verification

Passed:

- `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name "ST-013"`
- `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name "ST-013"`
- `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name "ST-013"`
- `dart format --set-exit-if-changed test/features/groups/application/drain_group_offline_inbox_use_case_test.dart test/features/groups/integration/group_resume_recovery_test.dart integration_test/group_multi_party_device_real_harness.dart integration_test/scripts/group_multi_party_device_criteria.dart test/integration/group_multi_party_device_criteria_test.dart`
- `dart analyze test/features/groups/application/drain_group_offline_inbox_use_case_test.dart test/features/groups/integration/group_resume_recovery_test.dart integration_test/group_multi_party_device_real_harness.dart integration_test/scripts/group_multi_party_device_criteria.dart test/integration/group_multi_party_device_criteria_test.dart`
- `git diff --check`

Blocked live proof:

- Run id: `1779365107177`
- Scenario: `private_network_chaos_invariants`
- Shared dir: `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_private_network_chaos_invariants_D1rFZn`
- Devices:
  - Alice `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`
  - Bob `279B82AE-2BB9-4924-9AAE-581870ED3FA9`
  - Charlie `116B4AF6-C1A9-4F36-B929-0A7130B5E83C`
  - Dana `CD5929A6-EA0A-421D-A6D3-55BD707E0F76`
- Failure: Bob exited before writing a verdict in `_runRa018Bob` while waiting for key epoch; Alice timed out waiting for `gmp_1779365107177_bob_ra018_charlie_removed_key_c3`; Charlie and Dana timed out waiting for `gmp_1779365107177_alice_sent_ra018Cycle3_charlieRemoved_alice.json`.

## Verdict

`blocked_external_fixture`

ST-013 row-owned host, fake-network, harness, and criteria artifacts are imported and verified. The required iOS 26.2 live proof is blocked by the shared `private_network_chaos_invariants` fixture. Stop before `INTEGRATE-ST-014` because that next row uses the same shared live path; resume at `INTEGRATE-ST-014` only after fixture recovery.
