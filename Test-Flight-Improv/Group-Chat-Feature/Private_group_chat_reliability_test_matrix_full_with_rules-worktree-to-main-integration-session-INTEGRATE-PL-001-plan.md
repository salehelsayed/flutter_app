# INTEGRATE-PL-001 Plan - Minimal Standard Integration Contract

Status: accepted

Mode: standard worktree-to-main integration. This is import/reconcile/verify work for already-covered source row `PL-001`; it is not gap-closure mode and must not recreate, rewrite, or rerun the historical source implementation plan.

## Real Scope

Own exactly integration row `INTEGRATE-PL-001`, sourced from historical row `PL-001`: "Unicode and multiline text survives live and replay delivery."

The source row contract is: emoji, RTL Arabic/Hebrew text, combining marks, and multiline/tabbed group text must survive live publish and offline replay identically without breaking encryption, rendering, or dedupe.

Historical source truth:

- Source worktree: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline`.
- Historical source plan: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-PL-001-plan.md`.
- Historical source proof passed: `flutter test test/features/groups/application/send_group_message_use_case_test.dart --plain-name "PL-001 outgoing unicode and multiline text is identical in live publish and replay payloads"` (`+1`).
- Historical source proof passed: `flutter test test/features/groups/integration/group_resume_recovery_test.dart --plain-name "PL-001 unicode and multiline text survives live delivery and offline replay"` (`+1`).
- Historical scoped format, analyze, and `git diff --check` passed.
- 3-Party E2E is Recommended, not required. No simulator, app-peer, or live proof is required or claimed for this row.

## Closure Bar

`INTEGRATE-PL-001` is good enough when current main either already has, or receives by row-owned import, the two focused PL-001 host/fake-network selectors in the allowed test files; both selectors pass; feasible preservation selectors around text sanitizer, incoming dedupe, `DE-003`, `DE-004`, and `IR-015` pass or receive exact non-PL-001 residual classification; scoped format/analyze and `git diff --check` pass; and broad groups/completeness residuals are classified without claiming live proof.

Allowed terminal status options are exactly:

- `accepted`
- `skipped_already_present`
- `blocked_conflict`
- `blocked_external_fixture`

## Source Of Truth

- Controlling integration breakdown: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-breakdown.md`.
- Current integration row: `PL-001` / `INTEGRATE-PL-001`, source `covered`, current status `pending_integration`.
- Historical source plan and closure evidence are the source of truth for behavior, proof shape, and accepted row-owned deltas.
- Current main wins over stale source implementation details when reconciling with accepted dirty `NW-013`/`NW-015` changes and blocked `NW-014` changes.
- Source matrix docs, source session breakdown docs, source worktree docs, `COMPLETE_1` docs, ledgers, inventories, and source closure docs are excluded from import scope. Current integration doc closure happens later.

## Future Execution Write Scope

Future execution under this contract may import, reconcile, or verify only these current files:

- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-INTEGRATE-PL-001-plan.md`
- `test/features/groups/application/send_group_message_use_case_test.dart`
- `test/features/groups/integration/group_resume_recovery_test.dart`

This planning task writes only this contract file. Future execution must not overwrite unrelated dirty edits and must preserve accepted dirty `NW-013`/`NW-015` state plus blocked `NW-014` state.

## Explicit Exclusions

Do not import, rewrite, or edit production code, migrations, harnesses, scripts, criteria files, ledgers, inventories, source matrix docs, source session breakdown docs, `COMPLETE_1` docs, UI rendering/layout, notifications, media, quotes, reactions, privacy, Android, physical iOS, macOS app-peer roles, NW-014 live fixture repair, or `PL-002+`.

No iOS 26.2 proof is required. No live proof command should be run for PL-001 acceptance.

## Implementation Contract

1. Start with `git status --short` and treat existing dirty `NW-013`, `NW-015`, and blocked `NW-014` work as context to preserve, not work to revert.
2. Compare current main against the historical source row only for the two row-owned test files.
3. Current scouts found main lacks exact PL-001 selectors; still rerun row-anchor searches before editing because other agents may have changed the worktree.
4. If both PL-001 selectors and equivalent assertions are already present, do not import; verify and classify as `skipped_already_present`.
5. If import is needed, reconcile only missing row-owned test deltas:
   - `PL-001 outgoing unicode and multiline text is identical in live publish and replay payloads`;
   - `PL-001 unicode and multiline text survives live delivery and offline replay`.
6. Do not touch production code. If the row cannot pass without production, harness, script, source-doc, or later-row edits, stop and classify as `blocked_conflict`.
7. NW-014 external live fixture blocker does not block PL-001 host/fake-network import.

## Verification Commands

Focused row proof:

```bash
flutter test test/features/groups/application/send_group_message_use_case_test.dart --plain-name "PL-001 outgoing unicode and multiline text is identical in live publish and replay payloads"
flutter test test/features/groups/integration/group_resume_recovery_test.dart --plain-name "PL-001 unicode and multiline text survives live delivery and offline replay"
```

Feasible preservation selectors:

```bash
flutter test test/features/groups/application/send_group_message_use_case_test.dart --plain-name "strips dangerous bidi controls and preserves safe markers across publish, inbox, save, and encrypted inbox payload"
flutter test test/features/groups/application/send_group_message_use_case_test.dart --plain-name "DE-003 preserves caller messageId in publish, replay, and retry payloads"
flutter test test/features/groups/integration/group_resume_recovery_test.dart --plain-name "GP-026 same message is not duplicated if both pubsub and group inbox deliver it"
flutter test test/features/groups/integration/group_resume_recovery_test.dart --plain-name "DE-003 caller-supplied message id survives live replay and retry"
flutter test test/features/groups/integration/group_resume_recovery_test.dart --plain-name "DE-004 live plus inbox replay duplicate keeps one row and commits replay evidence"
flutter test test/features/groups/integration/group_resume_recovery_test.dart --plain-name "IR-015 fake-network replay drains text quote image video file GIF and voice uniformly"
```

Scoped maintenance:

```bash
dart format --set-exit-if-changed test/features/groups/application/send_group_message_use_case_test.dart test/features/groups/integration/group_resume_recovery_test.dart
flutter analyze test/features/groups/application/send_group_message_use_case_test.dart test/features/groups/integration/group_resume_recovery_test.dart
git diff --check -- test/features/groups/application/send_group_message_use_case_test.dart test/features/groups/integration/group_resume_recovery_test.dart Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-INTEGRATE-PL-001-plan.md
```

Broad residual classification:

```bash
FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups
./scripts/run_test_gates.sh completeness-check
```

If broad gates remain red, acceptance requires exact classification that failures are pre-existing or non-PL-001 residuals, not caused by this row.

## Done Criteria And Status Guidance

- Use `accepted` only when the focused row proof, feasible preservation selectors or classifications, scoped maintenance, and residual classification satisfy this contract.
- Use `skipped_already_present` only when current main already has the row-owned selectors and equivalent assertions, and verification satisfies this contract.
- Use `blocked_conflict` for in-repo conflicts that cannot be resolved inside the two row-owned test files plus this plan.
- Use `blocked_external_fixture` only for unavailable host tooling or external test fixture failure that prevents required host/fake-network verification; do not use the blocked NW-014 live fixture as a PL-001 blocker.

## Execution Result

Status: accepted.

Imported the two missing PL-001 row-owned selectors into current main:

- `test/features/groups/application/send_group_message_use_case_test.dart`: `PL-001 outgoing unicode and multiline text is identical in live publish and replay payloads`.
- `test/features/groups/integration/group_resume_recovery_test.dart`: `PL-001 unicode and multiline text survives live delivery and offline replay`.

Current-main reconciliation was limited to the PL-001 integration test timestamp: the replay message is timestamped after membership/key setup so current pre-join replay filtering does not discard the row-owned offline replay payload.

Required focused proof, feasible preservation selectors, scoped format, scoped analyze, and scoped `git diff --check` passed. No iOS/live proof was run. Broad groups/completeness gates were not run for this row; residual classification remains no PL-001 host/fake-network residual observed in the required scoped verification.
