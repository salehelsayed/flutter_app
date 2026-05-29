# Promoted Admin Scenario 3 Session Breakdown

## Run Mode Snapshot

- active mode: `implementation-committed gap-closure`
- degraded local continuation explicitly allowed: no
- source proposal, matrix, or closure doc path: `Test-Flight-Improv/Group-Chat-Feature/promoted-admin-scenario3-session-breakdown.md`
- related stable docs: `Test-Flight-Improv/_current-test-map.md`, `Test-Flight-Improv/test-gate-definitions.md`, `Test-Flight-Improv/test-gates-reference.md`, `Test-Flight-Improv/Group-Chat-Feature/libp2p_group_chat_missing_test_matrix_full_with_rules.md`
- source row/status vocabulary: session ledger statuses in this artifact; related matrix rows may remain broader `Partial` if the exact user journey is covered but the matrix row owns wider product scope
- overall closure bar: the exact user-reported Scenario 3 is reproduced through production-facing group invite, promoted-admin metadata/photo, membership replay, and group send paths; the fix must prove B-as-promoted-admin can update metadata/photo, B can invite C, A learns C before C sends, C sends to A and B, and A photo updates reach all current members.
- final verdict policy: `closed` only if all runnable sessions are accepted with concrete code/test evidence, the named group gate is green, and a final program verdict is persisted; `accepted_with_explicit_follow_up` if the exact scenario is accepted but a documented unrelated gate failure remains; `still_open` if the exact scenario cannot be proven through production-facing tests.

## Recommended Plan Count

1

## Session Ledger

| Session ID | Status | Plan File | Final Execution Verdict | Closure Docs Touched | Blocker Class | Notes |
|---|---|---|---|---|---|---|
| GM-SC3-001 | accepted_with_explicit_follow_up | `Test-Flight-Improv/Group-Chat-Feature/promoted-admin-scenario3-session-01-plan.md` | accepted_with_explicit_follow_up | `promoted-admin-scenario3-session-01-plan.md`; `promoted-admin-scenario3-session-breakdown.md` | unrelated_gate_failure | Exact Scenario 3 has regression-first production evidence and host proof. `./scripts/run_test_gates.sh groups` remains blocked by unrelated `UP-001` stale membership event. |

## Ordered Session Breakdown

### GM-SC3-001: promoted-admin Scenario 3 production-path fix

- classification: `accepted_with_explicit_follow_up`
- dependencies: none
- exact scope:
  - Diagnose why the app still fails when B is promoted to admin, B changes group metadata/photo, B invites C, C sends, and A later changes photo.
  - Fix production paths that fail to broadcast or apply promoted-admin metadata, membership, and photo updates.
  - Add or strengthen tests so the exact Scenario 3 runs through production-facing paths, not a fake-only shortcut.
- likely code-entry files:
  - `lib/features/groups/presentation/screens/group_info_wired.dart`
  - `lib/features/groups/application/group_membership_update_listener.dart`
  - `lib/features/groups/application/update_group_metadata_use_case.dart`
  - `lib/features/groups/application/add_group_member_use_case.dart`
  - `lib/features/groups/application/send_group_invite_use_case.dart`
  - `lib/features/groups/application/accept_pending_group_invite_use_case.dart`
  - `lib/features/groups/application/send_group_message_use_case.dart`
  - `lib/features/groups/presentation/screens/group_conversation_wired.dart`
  - `lib/core/database/helpers/group_db_helpers.dart`
- likely direct tests or regressions:
  - `flutter test --no-pub test/features/groups/integration/group_admin_metadata_convergence_test.dart --plain-name "exact Scenario 3" -r expanded`
  - `flutter test --no-pub test/features/groups/integration/group_admin_metadata_convergence_test.dart -r expanded`
  - `flutter test --no-pub test/features/groups/presentation/group_info_wired_test.dart --plain-name "EK004 promote member stores signed member_role_updated replay envelope" -r expanded`
  - `flutter test --no-pub test/features/groups/application/send_group_invite_use_case_test.dart --plain-name "promoted admin invite includes the full current membership snapshot" -r expanded`
  - `flutter test --no-pub test/features/groups/application/member_removal_integration_test.dart --plain-name "direct membership update rejects relay sender mismatch" -r expanded`
  - consider `integration_test/group_admin_metadata_convergence_simulator_test.dart` or its wrapper coverage because the current wrapper does not run the exact Scenario 3 test.
- likely named gates:
  - `./scripts/run_test_gates.sh groups`
  - direct simulator/device proof if the plan classifies the row as device-required and devices are available
- matrix or closure docs to update:
  - this breakdown artifact session ledger and final program verdict
  - existing group gate docs only if the implemented evidence changes gate scope or required direct commands
  - group-chat matrix notes only if the exact evidence changes row wording; do not mark broad rows `Covered` if their wider product scope remains partial
- done criteria:
  - exact Scenario 3 test proves A receives B metadata/photo, C receives latest photo on accept, A learns C, C's message targets and reaches A and B, and A's later photo update reaches A/B/C as appropriate.
  - production code is fixed where the real path was broken; tests do not only assert fake direct helper behavior.
  - direct tests and `git diff --check` pass; any unrun device proof is recorded explicitly.

## Downstream Execution Path

For `GM-SC3-001`:

1. Plan with `$implementation-plan-orchestrator` into `Test-Flight-Improv/Group-Chat-Feature/promoted-admin-scenario3-session-01-plan.md`.
2. Execute and QA with `$implementation-execution-qa-orchestrator`.
3. Close with `$implementation-closure-audit-orchestrator`.
4. Run final program acceptance and persist a final program verdict in this artifact.

## Controller Progress

- 2026-05-28: closure completed for `GM-SC3-001` with verdict `accepted_with_explicit_follow_up`. Scenario 3 evidence is accepted; the named group gate is not closed because unrelated `UP-001 create add remove and re-add keep DB and bridge groupConfig snapshots aligned` still fails with `Bad state: Stale group membership event` at `add_group_member_use_case.dart:281`.
- 2026-05-28: planning completed for `GM-SC3-001`; plan path `Test-Flight-Improv/Group-Chat-Feature/promoted-admin-scenario3-session-01-plan.md` verified as `Status: execution-ready`. Dirty worktree snapshot recorded in the plan. Next action: spawn fresh execution/QA orchestrator.
- 2026-05-28: controller created this breakdown because the user supplied a bug journey rather than a pre-existing session-breakdown artifact. Next action: spawn a fresh planner for `GM-SC3-001`.

## Final Program Verdict

Verdict: `accepted_with_explicit_follow_up`

What is now closed:

- `GM-SC3-001` exact Scenario 3 is accepted for the durable recipient gap: C's send now preserves explicit A/B inbox recipients through both initial group inbox store and retry replay paths.
- The regression-first evidence is preserved: `Scenario 3 C send preserves A and B as durable inbox recipients` failed before the fix with `Expected: true Actual: <null>` for `inboxPayload['preserveRecipientPeerIds']`, then passed after the production fix.
- Supporting host proof passed for the new C-send regression, retry inbox store preserve flag, offline replay explicit-recipient store, promoted-admin invite picker path, EK004 role replay path, and the exact Scenario 3 host journey.

Residual-only items:

- `./scripts/run_test_gates.sh groups` cannot be claimed green until the unrelated `UP-001 create add remove and re-add keep DB and bridge groupConfig snapshots aligned` failure is fixed. The failure remains `Bad state: Stale group membership event` at `add_group_member_use_case.dart:281`, including after the Scenario 3 fix and individual `UP-001` rerun.

Still-open items:

- No `GM-SC3-001` product-scope item remains open on the recorded evidence.
- The group gate follow-up remains open only for the unrelated `UP-001` stale-membership failure.

Accepted differences:

- Broad GL-004 role-policy completeness remains out of scope and may stay broader than this accepted Scenario 3 session.
- No device or real-relay proof is claimed here; maintenance safety is the recorded host/direct proof plus the named group gate once the unrelated `UP-001` blocker is resolved.

Maintenance-time safety:

- Keep the direct checks named in the plan as the regression contract, especially the new C-send durable-recipient regression, the retry inbox store test, the promoted-admin invite picker proof, EK004 role replay proof, and the exact Scenario 3 host journey.
- Reopen `GM-SC3-001` only if the exact A/B/C Scenario 3 path regresses or real-app/device logs show the same journey failing again. Do not reopen this session solely because `UP-001` is still failing.
