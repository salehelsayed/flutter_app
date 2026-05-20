# INTEGRATE-IR-005 Minimal Integration Contract

Status: accepted

## Row Source

- Source row: `IR-005` (`Re-added member receives only post-readd replay`)
- Source worktree plan: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-IR-005-plan.md`
- Integration mode: standard worktree-to-main import/reconcile/verify.
- Guard: this contract reuses the historical worktree plan and closure evidence as source of truth. It does not recreate the original implementation plan and does not reimplement the row from scratch.

## Integration Contract

Import only the missing meaningful row-owned IR-005 proof deltas into main:

- Extend the existing KE-018 direct drain proof in `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart` with the `IR-005` selector name and distinct decrypt-request assertion proving only allowed pre-removal and post-readd replay envelopes are decrypted.
- Extend the existing GM-007/KE-018 fake-network smoke selector in `test/features/groups/integration/group_membership_smoke_test.dart` with the `IR-005` row name.
- Add `ir005ReaddReplayProof` live-harness verdict fields to the existing `gm007` scenario in `integration_test/group_multi_party_device_real_harness.dart`.
- Add IR-005 criteria validation and focused positive/negative criteria tests in `integration_test/scripts/group_multi_party_device_criteria.dart` and `test/integration/group_multi_party_device_criteria_test.dart`.
- Add the source row-owned stale installed Runner app guard in `integration_test/scripts/run_group_multi_party_device_real.dart` so fresh non-stateful iOS launches uninstall the app before install.
- Reconcile documentation and ledger evidence in `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` and this integration breakdown.

Do not import unrelated IR-006+ active-recipient closure, relay ACL internals, media replay breadth, UI, notification, Android, physical iOS, or broader cursor/history repair work.

## Reconciliation Notes

- Production replay/key-window behavior was already present in main through recipient-aware replay envelopes, exact key-generation lookup, pre-join/self-removal guards, and existing GM-007/KE-018 coverage.
- Current main already had direct KE-018 and fake-network GM-007 proof bodies; the missing meaningful delta was IR-005 row identity, the distinct decrypt-attempt assertion, live harness verdict fields, and criteria enforcement for re-added replay boundaries.
- The source direct test used a bridge variant whose `commandLog` records decrypts once. Current main's `_CursorInboxBridge` logs each forwarded command twice through the fake bridge stack, so the imported assertion was reconciled to count distinct outbound `sentMessages` with `cmd == group.decrypt`.
- Production files stayed untouched for this row.

## Verification Evidence

- `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'IR-005'` passed (`+1`).
- `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'IR-005'` passed (`+1`).
- `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'IR-005'` passed (`+3`).
- `flutter analyze --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart test/features/groups/integration/group_membership_smoke_test.dart integration_test/group_multi_party_device_real_harness.dart integration_test/scripts/group_multi_party_device_criteria.dart test/integration/group_multi_party_device_criteria_test.dart integration_test/scripts/run_group_multi_party_device_real.dart` passed with `No issues found!`.
- Preservation selectors passed: KE-018 direct drain (`+1`), GM-007 smoke/criteria (`+9`), and GM-019 send/member-removal/smoke/criteria (`+8`).
- Existing replay-window residual selectors remain red and were not rewritten because they are outside IR-005: `GM-033` fails with `Expected: not null / Actual: <null>` at `drain_group_offline_inbox_use_case_test.dart:4347`; `GK-023` fails with `Expected: null / Actual: GroupModel:<GroupModel(id: group-1, name: GK-023 Group, type: chat)>` at `:4665`; `GI-019` fails with `Expected: null / Actual: GroupModel:<GroupModel(id: group-1, name: GI-019 Group, type: chat)>` at `:4960`.
- iOS 26.2 relay-backed `gm007` proof passed with run id `1779161721700`, shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_gm007_zTSoIb`, Alice `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`, Bob `279B82AE-2BB9-4924-9AAE-581870ED3FA9`, Charlie `116B4AF6-C1A9-4F36-B929-0A7130B5E83C`, and verdict `gm007 proof passed: gm007 verdicts valid for alice, bob, charlie`.
- `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` remains red at `+210 -3` only on preserved non-IR-005 residuals `BB-007`, `BB-012`, and `GM-029`.
- `./scripts/run_test_gates.sh completeness-check` remains red on unrelated `test/shared/fakes/fake_group_pubsub_network_test.dart` classification (`732/733`).

## Residuals

- Existing non-row residuals `BB-007`, `BB-012`, `GM-029`, sampled `ML-008`, sampled COMPLETE_1 `GI-017`, replay-window residuals `GM-033`/`GK-023`/`GI-019`, drain `GEK003`, full-listener notification/self-peer-cache failures, and completeness classification remain for their own row-owned or explicit follow-up work.

## Final Verdict

Accepted for `INTEGRATE-IR-005`. The row-owned missing proof deltas were imported, already-present production behavior was preserved without duplication, focused verification and iOS 26.2 live proof passed, and remaining failures are non-IR-005 residuals.
