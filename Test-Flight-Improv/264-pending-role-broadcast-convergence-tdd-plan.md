# 264 - Pending Role-Broadcast Rows Must Converge Or Offer An Exit (Bug + Hardening)

Status: planned (v1 authored 2026-07-20; awaiting $tdd-review audit; NOT executed)
Type: bug + hardening
Closure tier: unit proof for drain convergence; widget proof for the recovery escape
hatch; on-device journey (role change while recipient offline, then leave) optional
Boundary triggers: Flutter-only (pending-broadcast drain, exit policy routing,
recovery sheet); no relay, bridge, native-handler, or wire-format production change
Spec: free-text intent — 2026-07-20 session: "I want the group administration to be
reliable." A member who initiated a role change that cannot finish syncing must never
be permanently trapped in the group.
Grounding: guard sites verified at HEAD ad073dd39; drain-defect claims below are
carried from the project's recorded landmine notes and MUST be re-verified against
source as the first execution step (they are hypotheses here, not verified findings).

## Planning Progress
| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-07-20 | Planner | leave_group_and_delete_local_history_use_case.dart, group_exit_policy.dart, orbit_wired.dart, group_info_wired.dart, group_pending_broadcast_sink.dart (partial), application/ dir listing | Guard chain verified; drain internals NOT yet read (runner/repush/086 migration pending) | Verify drain landmines against source, run $tdd-review 264, execute RED-first |

## Source Of Truth
- Spec / intent: inline above
- Gate definitions: scripts/run_test_gates.sh + scripts/run_host_test_gates.sh
- Numbering / index: Test-Flight-Improv/00-INDEX.md

## Session Classification
planning-only (no implementation in this session)

## Exact Problem Statement
Leaving a group is hard-blocked while any pending role-change broadcast row exists for
that group. The guard is correct in principle (leaving while your own promote/demote
has not reached the group can strand it — e.g. a promoted successor admin who never
learns of the promotion). But if a pending role row can get STUCK (never drains, never
reaches a terminal state), the guard converts a transient sync delay into a permanent
"Failed to leave group" / "role change must finish syncing" dead-end with no
user-reachable resolution from the Group Info screen.

## Verified Guard Chain (anchors at HEAD ad073dd39)
- lib/features/groups/application/leave_group_and_delete_local_history_use_case.dart:146-154
  — pre-prework guard: any pending role row → `preworkFailed`
  ("A member role change must finish syncing before leaving.").
- Same file :209-228 — the guard re-runs at the native boundary after prework, with
  tentative-artifact rollback.
- lib/features/groups/application/group_exit_policy.dart:83-91 — Orbit's snapshot maps
  pending role rows to `GroupExitDisposition.pendingRoleSync`.
- lib/features/orbit/presentation/screens/orbit_wired.dart:2960-2962 —
  `pendingRoleSync` routes to the recovery sheet (`_showGroupExitRecovery`, :3045+),
  which today DISPLAYS pending role broadcasts but offers no discard/resolve action
  for a row that will never drain.
- lib/features/groups/presentation/screens/group_info_wired.dart:456-490 — `_onLeave`
  bypasses the disposition system entirely: a pendingRoleSync state surfaces there as
  the generic "Failed to leave group" snackbar with zero guidance.

## Drain-Defect Hypotheses (MUST be source-verified first in execution)
Recorded landmine notes for this subsystem claim:
- H1: rows whose recipient list is empty skip their inbox leg yet stay pending.
- H2: orphaned rows retry forever — no attempt cap, no terminal state.
- H3: no drain mutex — concurrent drains can double-process or interleave.
Verification targets: lib/features/groups/application/group_pending_broadcast_sink.dart
(:11-28 drain sinks, :49+ prepared-row protection),
group_pending_broadcast_runner.dart, group_pending_broadcast_repush.dart,
lib/core/database/migrations/086_pending_group_broadcasts.dart, and every writer of
pending role rows (change_group_member_role_and_broadcast_use_case.dart).
Each hypothesis that survives verification becomes a RED test; each that does not is
recorded as refuted in this plan before implementation.

## Fix Outline (execution session implements)
1. Drain convergence (per surviving hypothesis): terminal states (delivered /
   abandoned) with an attempt cap or age cap; empty-recipient rows complete
   immediately; a drain mutex serializing `drainForGroup`/`drainAll`.
2. Escape hatch in the recovery sheet: for a pending role row, offer
   "Retry sync now" (drain that group) and — only when the row's live-publish leg
   never succeeded — "Discard role change" (delete the row + roll back the local
   tentative role if one was applied). A row whose live leg already published must
   NOT be discardable (state divergence); it needs the retry path only.
3. Route Group Info's leave through `resolveGroupExitSnapshot` (or map this
   `preworkFailed` cause to the recovery sheet) so the dead-end is reachable from
   every screen that offers Leave.
4. Distinct user copy for this cause (today it shares `group_info_leave_failed`).

## RED-First Test Plan
- Drain unit tests per verified hypothesis (empty-recipient completion, attempt-cap
  terminal state, mutex serialization).
- Exit-policy/UI tests: pendingRoleSync from Group Info reaches the recovery route,
  not the generic snackbar; discard action only offered for never-published rows;
  discard deletes the row and unblocks leave; retry action triggers a drain.
- Preservation: a legitimately in-flight role broadcast still blocks leave; the
  recovery sheet's existing sole-admin flows unchanged.

## Sibling Open-Sites
- group_list_wired.dart leave paths (same routing gap as group_info).
- Any other consumer of `isPendingGroupMemberRoleBroadcastKind`.

## Gates
- GROUP_TESTS: ./scripts/run_test_gates.sh groups
- AUTO_FEATURE_HOST: ./scripts/run_host_test_gates.sh feature-host-all
  --batch-flutter --concurrency 4 --reporter failures-only
- Explicit grep-gate registration for every new test (feature-local glob passes
  without registration — do not rely on it).
- flutter analyze clean.

## Risks / Open Questions
- Discard semantics when the live publish partially succeeded are the sharp edge;
  the leg-completion record must be authoritative before the action is shown.
- Attempt/age caps change delivery guarantees for genuinely-slow peers; pick caps
  from the existing retry cadence evidence during execution.
