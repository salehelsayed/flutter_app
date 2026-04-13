# Session Plan: 3

## Real Scope

- Close only the maintained-doc and final-verdict work after Sessions `1` and
  `2` landed and verified green.
- Reuse the already-rerun direct suites and required named gates from this
  controller pass.
- Refresh the maintained matrix, audit, test inventory, and breakdown so they
  truthfully reflect the landed reaction sender-binding proof and the degraded
  invite-accept durable join contract.
- Keep the downgraded reaction replay durability concern explicit as residual
  follow-up; do not silently upgrade it to closed.

## Closure Bar

- The maintained docs no longer claim that degraded pending-invite acceptance
  lacks a durable `member_joined` owner.
- The maintained docs truthfully record that the shipped accept flow now
  catches up offline reactions in the immediate visible accept window when the
  supported dependencies are present.
- The final breakdown ledger marks Sessions `2` and `3` accepted and records
  one persisted final program verdict.
- The final verdict remains `accepted_with_explicit_follow_up` unless current
  execution proves the downgraded reaction replay durability concern is already
  fully owned.

## Source Of Truth

- Active session contract:
  `Test-Flight-Improv/Group-Chat-Feature/Two-Pass-Discussion-Announcement-Reliability-Audit-2026-04-13-session-breakdown.md`
- Governing audit:
  `Test-Flight-Improv/Group-Chat-Feature/Two-Pass-Discussion-Announcement-Reliability-Audit-2026-04-13.md`
- Supporting audit:
  `Test-Flight-Improv/Group-Chat-Feature/Narrowed-Discussion-Announcement-Audit-2026-04-13.md`
- Maintained closure docs:
  `Test-Flight-Improv/Group-Chat-Feature/Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md`
  `Test-Flight-Improv/Group-Chat-Feature/Discussion-And-Announcement-Feature-Audit.md`
  `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- Regression and gate definitions:
  `Test-Flight-Improv/14-regression-test-strategy.md`
  `Test-Flight-Improv/test-gate-definitions.md`

## Session Classification

- `acceptance-only`

## Exact Problem Statement

- Session `1` is already accepted for live/replay reaction sender binding.
- Session `2` now closes the degraded accept seam in code and tests, but the
  maintained docs still need a truthful closure pass.
- The residual reaction replay durability concern is narrower than the closed
  live/replay truth rows: sender-side reaction add/remove replay storage is
  still best-effort if `group:inboxStore` fails.
- This session must close doc truth without reopening unrelated group UX,
  transport, or replay redesign work.

## Files To Update

- `Test-Flight-Improv/Group-Chat-Feature/Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md`
- `Test-Flight-Improv/Group-Chat-Feature/Discussion-And-Announcement-Feature-Audit.md`
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- `Test-Flight-Improv/Group-Chat-Feature/Two-Pass-Discussion-Announcement-Reliability-Audit-2026-04-13-session-breakdown.md`

## Verification Evidence To Reuse

- `flutter test --no-pub test/features/groups/application/handle_incoming_group_reaction_use_case_test.dart`
- `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`
- `flutter test --no-pub test/features/groups/application/accept_pending_group_invite_use_case_test.dart`
- `flutter test --no-pub test/features/groups/presentation/group_list_wired_test.dart`
- `flutter test --no-pub test/features/groups/integration/invite_round_trip_test.dart`
- `./scripts/run_test_gates.sh groups`
- `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline`

## Step-By-Step Closure Plan

1. Create this missing Session `3` plan artifact.
2. Refresh the maintained matrix so invite-accept rows and notes match the
   landed Session `2` proof.
3. Refresh the maintained audit so it no longer describes durable join
   visibility, immediate accept-time reaction catch-up, or degraded
   bridge-error convergence as open gaps.
4. Refresh the test inventory closure rows with the new invite-accept evidence
   and add one explicit residual note for reaction replay durability.
5. Update the breakdown ledger, pipeline progress, and final program verdict.

## Risks And Edge Cases

- Do not let doc cleanup silently imply sender-side reaction replay store
  failures have a retry owner when they still do not.
- Do not reopen broader invite-review or replay-architecture scope just because
  the residual note remains.
- Keep the final verdict tied to the evidence actually rerun in this controller
  pass.

## Done Criteria

- Session `3` plan exists.
- Maintained docs align with the landed code and test evidence from Sessions
  `1` and `2`.
- The downgraded reaction replay durability concern remains explicit residual
  follow-up.
- The breakdown records a persisted final verdict of
  `accepted_with_explicit_follow_up` unless a real blocker appears.

## Scope Guard

- Do not add new product requirements, architecture proposals, or recovery
  owners.
- Do not widen into reaction inspection UX, non-friend onboarding, or
  encrypted replay redesign.
- Do not rerun unrelated gates or suites unless a touched claim truly depends
  on them.
