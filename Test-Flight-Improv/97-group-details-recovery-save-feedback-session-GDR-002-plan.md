Status: execution-ready

# GDR-002 Plan - Promoted-admin A/B/C recovery-save acceptance proof

## Real Scope

Add acceptance coverage only for the Report 97 multi-user outcome:

- A and B are connected, B and C are connected, and A/C are not modeled as direct contacts.
- A creates the group, B joins, B is promoted, B brings C into the group, then C is promoted.
- While the shared group recovery gate is active, C's metadata/photo save is rejected and no local repo shows the blocked name/description/avatar as saved group state.
- After recovery clears, C saves name, description, and photo metadata and the update converges to A, B, and C.

No production behavior, simulator harness, gate-definition, or stable matrix doc changes are in scope for this session.

## Source Of Truth

- Product intent: `Test-Flight-Improv/97-group-details-recovery-save-feedback.md`
- Session split: `Test-Flight-Improv/97-group-details-recovery-save-feedback-session-breakdown.md`
- Existing acceptance harness: `test/features/groups/integration/group_admin_metadata_convergence_test.dart`
- Simulator wrapper: `integration_test/group_admin_metadata_convergence_simulator_test.dart`
- Named gate: `./scripts/run_test_gates.sh groups`

## Device/Relay Proof Profile

Profile: `host-only acceptance plus existing simulator wrapper awareness`.

GDR-002 adds host integration proof in the existing convergence suite. It does not require a live Flutter device because no new `integration_test` file or simulator-only behavior is introduced. The existing simulator wrapper imports this suite; GDR-003 may cite or run simulator evidence when a device is available.

## Implementation Steps

1. Add a new exported scenario function in `group_admin_metadata_convergence_test.dart` for the recovery-save A/B/C path.
2. Import and reset `groupRecoveryGate` around the suite or scenario so the active gate cannot leak across tests.
3. Build the scenario from existing helpers:
   - create A/B/C users and direct membership harness
   - A invites B
   - A promotes B
   - B invites C and replays membership to A
   - A promotes C
   - activate `groupRecoveryGate`
   - assert C's metadata/photo update throws the lower-level recovery `StateError`
   - assert A, B, and C still have the old metadata/avatar
   - clear recovery and have C update name, description, and photo
   - wait for A and B to converge and assert C's local state also matches
4. Add the scenario to both the host test group and the existing simulator wrapper import list when appropriate.

## Exact Tests And Gates To Run

```bash
flutter test --no-pub test/features/groups/integration/group_admin_metadata_convergence_test.dart --plain-name 'promoted admin recovery-blocked save waits then metadata and photo converge'
flutter test --no-pub test/features/groups/integration/group_admin_metadata_convergence_test.dart
./scripts/run_test_gates.sh groups
```

Do not add or require a new named gate.

## Scope Guard

- Do not change production group metadata, recovery, membership, transport, relay, invite, key rotation, or UI code in GDR-002.
- Do not add a new simulator file.
- Do not update stable matrix/closure docs; GDR-003 owns final docs.

## Done Criteria

- The new acceptance case proves blocked recovery save does not persist blocked name/description/avatar metadata locally.
- The post-recovery promoted-admin save converges to all A/B/C members.
- Existing group metadata convergence suite and `groups` gate pass.

## Execution Progress

- 2026-05-29T17:30:00+02:00 - Phase: plan prepared. Files inspected/touched: `Test-Flight-Improv/97-group-details-recovery-save-feedback-session-breakdown.md`, `test/features/groups/integration/group_admin_metadata_convergence_test.dart`, `integration_test/group_admin_metadata_convergence_simulator_test.dart`. Command: none. Decision/blocker: existing host convergence helpers are sufficient; no production code or new simulator file required. Next action: add the acceptance scenario.
- 2026-05-29T17:32:51+02:00 - Phase: targeted acceptance verification. Files inspected/touched: `test/features/groups/integration/group_admin_metadata_convergence_test.dart`, `integration_test/group_admin_metadata_convergence_simulator_test.dart`. Command: `flutter test --no-pub test/features/groups/integration/group_admin_metadata_convergence_test.dart --plain-name 'promoted admin recovery-blocked save waits then metadata and photo converge'`. Result: passed, `00:00 +1`.
- 2026-05-29T17:33:04+02:00 - Phase: convergence-suite verification. Files inspected/touched: same. Command: `flutter test --no-pub test/features/groups/integration/group_admin_metadata_convergence_test.dart`. Result: passed, `00:02 +12`.
- 2026-05-29T17:34:08+02:00 - Phase: named gate verification. Files inspected/touched: same plus existing groups gate coverage. Command: `./scripts/run_test_gates.sh groups`. Result: passed, `00:55 +313`.

## Execution Verdict

Accepted. The host acceptance suite now proves a promoted admin in the A/B/C chain cannot persist blocked recovery-window name, description, or avatar metadata locally, and that the same promoted admin's post-recovery metadata and avatar update converges to all three current group members. No production code or gate-definition changes were required for this session.
