# INTEGRATE-KE-021 Integration Contract

Status: accepted

## Source Contract

- Source row: `KE-021`
- Scenario: Removed member key material is not used for future direct or group inbox payloads.
- Expected behavior: after member `C` is removed, future direct key-update fanout and future group inbox/replay payloads exclude `C`; old local key material cannot decrypt future payloads.
- Source proof profile: host unit/integration/fake-network only; 3-party E2E and iOS 26.2 live proof are `N/A`.

## Integration Decision

Tests-only import. Current main production behavior already derives direct key fanout and group inbox recipients from current active membership, so no production, Go, relay, criteria, runner, fixture, or live-harness files were imported.

Imported only the row-owned proof artifacts from the historical KE-021 implementation commit:

- `test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart`
- `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`
- `test/features/groups/integration/group_messaging_smoke_test.dart`
- `test/features/groups/application/member_removal_integration_test.dart` preservation-only setup/order update
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` row-owned selector inventory updates

## Verification

Focused KE-021 selectors passed:

- `flutter test --no-pub test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart --plain-name 'KE-021 removed member is excluded from future direct key update fanout'`
- `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'KE-021 future group inbox replay excludes removed member and stale key cannot decrypt'`
- `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name 'KE-021 removed member is not targeted by future fake-network key or inbox payloads'`

Affected preservation checks passed:

- `ML-013 bare writer and removed peer cannot rotate keys`
- `KE-006 removal rotates key and excludes removed member; rotated key is NOT distributed to removed member`
- `GI-004 group inbox recipients follow current remove and re-add entitlement windows`
- `GM-019 removed-window durable recipients exclude re-added member until re-add`
- `GK-022 removed member with old key cannot decrypt post-removal inbox replay`
- full `retry_failed_group_inbox_stores_use_case_test.dart`

Hygiene and gates:

- `dart format` reported `0 changed`.
- Scoped `dart analyze` reported `No issues found!`.
- `git diff --check` passed.
- `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` remains red at `+194 -3` only on preserved non-KE-021 residuals `BB-007`, `BB-012`, and `GM-029`.
- `./scripts/run_test_gates.sh completeness-check` remains red on unrelated `test/shared/fakes/fake_group_pubsub_network_test.dart` classification (`732/733`).

## Out Of Scope

Source matrix row rewrites, source session-breakdown rewrites, COMPLETE_1 docs, Go/native changes, relay changes, criteria scripts, live harnesses, simulator proofs, iOS 26.2 devices, IR-006 active-recipient closure, KE-007/KE-009 re-reconciliation, BB-007 repair, BB-012 retention-fixture repair, GM-029 repair, listener/drain/replay-window residuals, ML-012 external-fixture work, UI, media, notification, and broader lifecycle/key-safety behavior.

Safe next action: continue with `INTEGRATE-KE-022` after ledger sanity and dirty-state safety checks. Separately, KE-007 and KE-009 remain recorded as `blocked_conflict` until explicitly re-reconciled after KE-017.
