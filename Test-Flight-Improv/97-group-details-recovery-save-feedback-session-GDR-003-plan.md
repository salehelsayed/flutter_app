Status: execution-ready

# GDR-003 Plan - Close Report 97 matrix, gate, and closure evidence

## Real Scope

Record the accepted Report 97 recovery-save feedback work in the stable docs:

- update the existing group matrix rows `SC-007`, `UX-002`, and `UX-003`
- update the current test map for group recovery/metadata-photo evidence
- update the group closure reference with the Report 97 final proof
- mark the Report 97 source spec and this breakdown with the final doc verdict

No production code, gate-definition, or new test-file changes are in scope.

## Source Of Truth

- Source spec: `Test-Flight-Improv/97-group-details-recovery-save-feedback.md`
- Session split: `Test-Flight-Improv/97-group-details-recovery-save-feedback-session-breakdown.md`
- Accepted GDR-001 plan: `Test-Flight-Improv/97-group-details-recovery-save-feedback-session-GDR-001-plan.md`
- Accepted GDR-002 plan: `Test-Flight-Improv/97-group-details-recovery-save-feedback-session-GDR-002-plan.md`
- Stable matrix: `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`
- Current test map: `Test-Flight-Improv/_current-test-map.md`
- Closure reference: `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`

## Evidence To Record

- `flutter test --no-pub test/features/groups/presentation/group_info_wired_test.dart`
- `flutter test --no-pub test/features/groups/application/update_group_metadata_use_case_test.dart`
- `flutter test --no-pub test/l10n/l10n_integrity_test.dart`
- `flutter test --no-pub test/features/groups/integration/group_admin_metadata_convergence_test.dart --plain-name 'promoted admin recovery-blocked save waits then metadata and photo converge'`
- `flutter test --no-pub test/features/groups/integration/group_admin_metadata_convergence_test.dart`
- `./scripts/run_test_gates.sh groups`

## Execution Steps

1. Add narrow closure notes to the matrix rows already named by the decomposition.
2. Add the recovery-save feedback proof to the current test map without widening named gates.
3. Add a Report 97 section to the closure reference, preserving the existing Report 96 section already present in the dirty worktree.
4. Mark the source spec and breakdown with the final verdict.
5. Run `git diff --check`; rerun a targeted/doc-relevant gate only if the edits touch code or gate classification.

## Scope Guard

- Do not create a new matrix doc.
- Do not change `scripts/run_test_gates.sh` or gate definitions.
- Do not claim Report 97 closes the full stale-client-resync matrix row; it only adds recovery-window privileged-operation save proof.

## Execution Progress

- 2026-05-29T17:36:00+02:00 - Phase: plan prepared. Files inspected/touched: Report 97 source/breakdown/plans, group matrix rows `SC-007`, `UX-002`, `UX-003`, `_current-test-map.md`, and the closure reference. Command: none. Decision/blocker: closure can cite same-turn GDR-001/GDR-002 green evidence; no gate-definition changes required. Next action: apply narrow doc updates.
- 2026-05-29T17:38:00+02:00 - Phase: closure docs updated. Files inspected/touched: `Test-Flight-Improv/97-group-details-recovery-save-feedback.md`, `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`, `Test-Flight-Improv/_current-test-map.md`, `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`. Command: none. Decision/blocker: stable docs now cite Report 97 without changing gate definitions or claiming full stale-client-resync closure.
- 2026-05-29T17:38:30+02:00 - Phase: final hygiene. Files inspected/touched: docs and accepted GDR evidence. Command: `git diff --check`. Result: passed.

## Execution Verdict

Accepted. Report 97 closure is recorded in the source spec, stable group matrix, current test map, closure reference, and session breakdown. Same-turn GDR-001 and GDR-002 evidence remains green, and `git diff --check` passed. No new gates, simulator files, or gate-definition changes were required.
