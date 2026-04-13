Final verdict

- Reviewer verdict: sufficient with adjustments.
- Arbiter verdict: no plan-structure blocker after narrowing MD-004 to an evidence-gated acceptance path.
- Smallest safe repo-owned execution path now: prefer the primary iOS simulator pair `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD` (`iPhone Air`) + `5BA69F1C-B112-47BE-B1FF-8C1003728C8F` (`iPhone 17`) because the inspected repo already owns multi-simulator boot/install helpers there; do not widen into new group harness work.
- Session outcome classification: `evidence-gated`.

Final plan

1. real scope

- Plan only the MD-004 proof path for true simulator/emulator sibling-device evidence.
- Reuse existing repo-owned simulator/emulator helpers only where they already exist.
- Do not add product behavior, group logic, relay changes, or a new generalized multi-device harness in this session.

2. closure bar

- Good enough for MD-004 is one of these two outcomes only:
- Outcome A: capture true simulator/emulator proof on one approved primary pair showing the same-user sibling-device behaviors already pinned by the in-memory oracle.
- Outcome B: prove from current repo evidence that closure is blocked because the inspected repo does not provide a same-user simulator bootstrap path, and stop without inventing new harness scope.
- MD-004 is not closed by in-memory tests alone.

3. source of truth

- `Test-Flight-Improv/Group-Chat-Feature/Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md` is the source of truth for MD-004 ownership, target devices, and evidence-gated status.
- `Test-Flight-Improv/Group-Chat-Feature/Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md` is the source of truth for the row contract and required gates: `Integration` is `Recommended`; `3-Party E2E` is `Required`.
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` is the source of truth for the currently acknowledged gap: true simulator/device multi-device proof is still missing.
- Current code and tests beat stale prose on disagreement.
- `test/features/groups/integration/group_multi_device_convergence_test.dart` is the current oracle for expected sibling-device behavior, but not proof beyond fakes.

4. session classification

- `evidence-gated`

5. exact problem statement

- The repo currently claims same-user multi-device convergence for groups, but the inspected proof is still in-process and fake-network based.
- MD-004 specifically requires true simulator/emulator proof on the named Android or iOS pair, beyond `FakeGroupPubSubNetwork` and `GroupTestUser`.
- The user-visible contract that must be proven unchanged is:
- same-user send mirrors to the sibling device as local sent history without duplicate unread or notification confusion
- membership changes converge on the sibling device without duplicate self-membership
- mute, unread, and local notification behavior stays device-local while shared group state still converges

6. files and repos to inspect next

- No broader repo sweep is needed before execution.
- Use the already inspected files as the full execution boundary for MD-004:
- `Test-Flight-Improv/Group-Chat-Feature/Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md`
- `Test-Flight-Improv/Group-Chat-Feature/Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md`
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- `integration_test/setup_device.dart`
- `reset_simulators.sh`
- `smoke_test_friends.sh`
- `lib/main.dart`
- `lib/core/debug/intro_e2e_runner.dart`
- `lib/core/debug/e2e_test_mode.dart`
- `integration_test/scripts/run_transport_e2e.dart`
- `integration_test/scripts/run_group_recovery_e2e.dart`
- `integration_test/group_recovery_e2e_test.dart`
- `integration_test/group_recovery_cli_e2e_test.dart`
- `test/features/groups/integration/group_multi_device_convergence_test.dart`

7. existing tests covering this area

- `test/features/groups/integration/group_multi_device_convergence_test.dart` covers the exact same-user contracts MD-001 through MD-003 rely on, but it does so with `FakeGroupPubSubNetwork` plus in-memory `GroupTestUser` fixtures, so it does not close MD-004.
- `integration_test/group_recovery_e2e_test.dart` is a simulator-backed group smoke, but still uses fake-network style seams and runs inside one Flutter test process.
- `integration_test/scripts/run_group_recovery_e2e.dart` and `integration_test/group_recovery_cli_e2e_test.dart` prove the repo has a host-orchestrated group E2E pattern, but only for one simulator/emulator plus one CLI peer, not two sibling app devices.
- `reset_simulators.sh`, `smoke_test_friends.sh`, `lib/main.dart`, and `lib/core/debug/intro_e2e_runner.dart` prove the repo already has iOS multi-simulator boot/install/config/result plumbing, but that plumbing is introduction/chat-specific and distinct-user oriented.
- `integration_test/setup_device.dart` proves per-device real identity setup, but it generates a fresh identity per device rather than duplicating one user across sibling devices.

8. regression/tests to add first

- Do not add repo code or new tests first for MD-004.
- First run the in-memory oracle as a regression guard before any true-device proof attempt:
- `flutter test test/features/groups/integration/group_multi_device_convergence_test.dart`
- If this oracle fails, stop and treat that as a repo regression unrelated to device-lab execution.
- If the oracle passes, move to the simulator proof attempt without adding a new group harness in this session.

9. step-by-step implementation plan

- Step 1: Run the in-memory oracle test file to pin the expected same-user sibling-device behavior before any real-device proof work.
- Step 2: Prefer the iOS primary pair over Android because the inspected repo already contains a checked-in multi-simulator bootstrap for those exact iOS UUIDs, while the inspected Android scripts are single-device only.
- Step 3: Use `./reset_simulators.sh` only as the checked-in iOS boot/install/permission helper. Its default distinct-user seed state is not valid MD-004 evidence and must be replaced before proof execution.
- Step 4: Use only an already-existing same-user bootstrap method available to the proof owner outside this plan's inspected repo boundary. Acceptable examples are a pre-existing manual restore flow, pre-seeded simulator state, or device-lab provisioning that does not require new repo code. This plan does not authorize creating a new group-specific bootstrap path.
- Step 5: Execute the three real-device proof scenarios on the primary iOS pair, matching the oracle behaviors from `group_multi_device_convergence_test.dart`:
- send on device 1 and verify device 2 stores the message as local sent history with no duplicate unread / notification confusion
- perform a membership change on device 1 and verify device 2 converges without duplicate self-membership
- change mute/read state on device 1 and verify device-local state remains device-local while shared group message state converges
- Step 6: Capture proof artifacts for MD-004 only: device IDs, timestamps, screenshots/video, and concise notes mapping each observed result to the oracle scenario it matches.
- Step 7: If the same-user bootstrap cannot be achieved on the primary iOS pair without writing new repo code or inventing a new harness, stop immediately. Keep MD-004 open and record it as blocked on external proof ownership / device-lab bootstrap.
- Step 8: Use the spare iOS simulator `1B098DFF-6294-407A-A209-BBF360893485` (`iPhone 16e`) only if one primary iOS simulator is unavailable.
- Step 9: Treat the Android pair `emulator-5554` + `emulator-5556` as optional corroboration after iOS proof, not as required first work, because no inspected checked-in Android multi-emulator harness was found.

10. risks and edge cases

- The inspected bootstrap helpers create distinct users; using them as-is would produce the wrong proof for MD-004.
- Intro/chat simulator scripts can be mistaken for reusable group proof infrastructure, but they are not group-aware and would widen scope.
- Single-device host-orchestrated group E2E can be mistaken for sibling-device proof, but it does not satisfy MD-004.
- Notification permission setup may vary across simulator resets; `reset_simulators.sh` already pre-grants notifications and should remain the preferred iOS prep path.
- If a manual restore/bootstrap path changes app state outside the inspected helpers, that state must be documented in the proof notes so MD-004 is not misrepresented as fully repo-automated.

11. exact tests and gates to run

- Baseline oracle:
- `flutter test test/features/groups/integration/group_multi_device_convergence_test.dart`
- Preferred simulator prep helper only:
- `./reset_simulators.sh`
- Optional per-device prep helper, for controlled clean-state setup only and not as proof of same-user duplication:
- `flutter test integration_test/setup_device.dart -d 347FB118-10D0-40C8-A05B-B0C3BD6B8CCD --dart-define=USERNAME=a`
- `flutter test integration_test/setup_device.dart -d 5BA69F1C-B112-47BE-B1FF-8C1003728C8F --dart-define=USERNAME=b`
- Row gates from the source matrix:
- `Integration` gate: satisfied only by the baseline oracle plus supporting simulator execution notes
- `3-Party E2E` gate: satisfied only by true simulator/emulator sibling-device proof on one approved pair; it is not satisfied by the inspected in-memory or single-device tests

12. known-failure interpretation

- If `group_multi_device_convergence_test.dart` fails, treat that as a real repo regression and stop MD-004 execution.
- If simulator prep fails in `reset_simulators.sh`, treat that as environment/setup failure until reproduced against the same checked-in script.
- If the proof run cannot establish the same user on both devices without new code, treat that as an expected MD-004 blocker, not as a product regression.
- Failures in intro/chat smoke orchestration or single-device CLI group E2E do not count as MD-004 regressions unless those exact steps were intentionally reused during the proof attempt.

13. done criteria

- The baseline oracle passes.
- One approved primary simulator/emulator pair is prepared successfully.
- Proof evidence exists for all three same-user sibling-device scenarios, or the run is explicitly stopped because same-user bootstrap is unavailable without new non-row-owned harness work.
- No new production behavior or generalized harness scope was added under MD-004.

14. scope guard

- Do not build a new group multi-device orchestrator in this session.
- Do not generalize `intro_e2e_runner.dart` into a group harness here.
- Do not modify group feature code, notifications code, relay logic, or persistence behavior under MD-004.
- Do not absorb UX-009, push delivery, or broader device-lab modernization into this row.
- Do not claim closure from fake-network, single-device, or distinct-user evidence.

15. accepted differences / intentionally out of scope

- `smoke_test_friends.sh` and `intro_e2e_runner.dart` remain intro/chat-specific infrastructure and are only evidence of existing simulator orchestration patterns.
- `integration_test/scripts/run_group_recovery_e2e.dart` and `integration_test/group_recovery_cli_e2e_test.dart` remain single-device-plus-CLI patterns and are not promoted to sibling-device proof in this session.
- Android corroboration is intentionally deferred unless iOS proof is blocked by device availability alone.

16. dependency impact

- If MD-004 proof succeeds, the next dependent work is documentation only: update the MD-004 matrix row, the test inventory note, and the session breakdown ledger.
- If MD-004 remains blocked, no repo-owned implementation session should be reopened from this row alone; the blocker belongs to external proof ownership or a separately scoped harness session.
- `UX-009` should stay independent because its current scope is local-relay / simulator exploratory proof, not same-user sibling-device convergence beyond fakes.

Structural blockers remaining

- The inspected repo evidence does not show a checked-in same-user simulator bootstrap or a group-specific sibling-device multi-simulator harness.
- Because of that, MD-004 can be executed safely only as an evidence-gated run with a hard stop if the proof owner cannot establish the same user on both primary devices using an already-existing external/manual bootstrap path.

Incremental details intentionally deferred

- Android pair corroboration after successful iOS proof.
- Spare-device validation on `1B098DFF-6294-407A-A209-BBF360893485` unless a primary iOS simulator is unavailable.
- Any attempt to convert the intro or single-device group E2E scripts into reusable MD-004 automation.

Accepted differences intentionally left unchanged

- In-memory multi-device convergence tests remain the behavior oracle only.
- Intro smoke helpers remain distinct-user orchestration, not group same-user proof.
- Group recovery CLI E2E remains a single-device resilience path, not a sibling-device acceptance path.

Exact docs/files used as evidence

- `Test-Flight-Improv/Group-Chat-Feature/Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md`
- `Test-Flight-Improv/Group-Chat-Feature/Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md`
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- `integration_test/setup_device.dart`
- `reset_simulators.sh`
- `smoke_test_friends.sh`
- `lib/main.dart`
- `lib/core/debug/intro_e2e_runner.dart`
- `lib/core/debug/e2e_test_mode.dart`
- `integration_test/scripts/run_transport_e2e.dart`
- `integration_test/scripts/run_group_recovery_e2e.dart`
- `integration_test/group_recovery_e2e_test.dart`
- `integration_test/group_recovery_cli_e2e_test.dart`
- `test/features/groups/integration/group_multi_device_convergence_test.dart`

Why the plan is safe or unsafe to implement now

- Safe as a plan: it keeps MD-004 narrow, reuses only existing checked-in simulator seams, names the exact oracle test, and forces an immediate stop before any new harness invention.
- Unsafe to mark MD-004 closed immediately: the inspected repo still lacks a checked-in same-user sibling-device bootstrap path, so true proof remains evidence-gated until an external/manual bootstrap owner can run the approved simulator pair.
