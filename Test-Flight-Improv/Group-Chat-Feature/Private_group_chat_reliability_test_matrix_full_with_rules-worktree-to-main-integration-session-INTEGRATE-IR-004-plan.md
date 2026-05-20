# INTEGRATE-IR-004 Minimal Integration Contract

Status: accepted

## Row Source

- Source row: `IR-004` (`Replay does not expose post-removal messages to removed member`)
- Source worktree plan: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-IR-004-plan.md`
- Integration mode: standard worktree-to-main import/reconcile/verify.
- Guard: this contract reuses the historical worktree plan and closure evidence as source of truth. It does not recreate the original implementation plan and does not reimplement the row from scratch.

## Integration Contract

Import only the missing meaningful row-owned IR-004 proof deltas into main:

- Direct host replay proof in `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`.
- Row-owned `ir004PostRemovalReplayProof` criteria validation in `integration_test/scripts/group_multi_party_device_criteria.dart`.
- Criteria positive/negative coverage in `test/integration/group_multi_party_device_criteria_test.dart`.
- Existing `private_offline_remove` live harness proof fields in `integration_test/group_multi_party_device_real_harness.dart`.
- Documentation and ledger reconciliation in `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` and this integration breakdown.

Do not import unrelated IR-005+ re-add replay boundaries, relay ACL internals, media privacy, UI, notification, Android, physical iOS, or macOS app-peer role work.

## Reconciliation Notes

- Production recipient entitlement skip behavior was already present in main through the existing replay recipient check and `GROUP_DRAIN_OFFLINE_INBOX_REPLAY_RECIPIENT_SKIPPED` flow evidence.
- Current main also had equivalent or stronger removal-cutoff coverage through existing GI/GK removal replay tests. The missing meaningful row-owned delta was the IR-004-named skip-before-decrypt proof and live criteria/harness evidence.
- Production files stayed untouched for this row.
- The imported direct app test was reconciled to current main's local pre-join timestamp guard by using realistic post-join timestamps in the row-owned fixture.

## Verification Evidence

- `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'IR-004'` passed (`+1`).
- `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'IR-004'` passed (`+3`).
- `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'ML-006'` passed (`+1`).
- `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'private_offline_remove'` passed (`+8`).
- `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'GK-022 removed member with old key cannot decrypt post-removal inbox replay'` passed (`+1`).
- Scoped analyzer passed with `No issues found!` for the touched app test, criteria script, criteria test, and live harness files.
- Scenario discovery passed for `private_offline_remove`.
- iOS 26.2 relay-backed `private_offline_remove` proof passed with run id `1779160203612`, shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_private_offline_remove_S9tfia`, Alice `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`, Bob `279B82AE-2BB9-4924-9AAE-581870ED3FA9`, Charlie `116B4AF6-C1A9-4F36-B929-0A7130B5E83C`, and verdict `private_offline_remove proof passed: private_offline_remove verdicts valid for alice, bob, charlie`.
- `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` remains red at `+210 -3` only on preserved non-IR-004 residuals `BB-007`, `BB-012`, and `GM-029`.
- `./scripts/run_test_gates.sh completeness-check` remains red on unrelated `test/shared/fakes/fake_group_pubsub_network_test.dart` classification (`732/733`).
- `git diff --check` passed after the IR-004 code/test edits.

## Residuals

- `GK-023 re-added member skips removed-window replay and renders post-readd replay` remains red in current main with `Expected: null / Actual: GroupModel:<GroupModel(id: group-1, name: GK-023 Group, type: chat)>` at `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart:4665`. This is an existing replay-window residual and was not rewritten because it is outside IR-004.
- Existing non-row residuals `BB-007`, `BB-012`, `GM-029`, sampled `ML-008`, sampled COMPLETE_1 `GI-017`, and completeness classification remain for their own row-owned or explicit follow-up work.

## Final Verdict

Accepted for `INTEGRATE-IR-004`. The row-owned missing proof deltas were imported, already-present production behavior was preserved without duplication, focused verification and iOS 26.2 live proof passed, and remaining failures are non-IR-004 residuals.
