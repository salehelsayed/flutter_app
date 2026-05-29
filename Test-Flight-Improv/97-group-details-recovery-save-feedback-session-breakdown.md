Status: reusable

# Group Details Recovery Save Feedback Session Breakdown

## Decomposition Progress

- Current role or phase: Evidence Collector complete
  - Source doc path: `Test-Flight-Improv/97-group-details-recovery-save-feedback.md`
  - Intended breakdown path: `Test-Flight-Improv/97-group-details-recovery-save-feedback-session-breakdown.md`
  - Files inspected: source doc, regression/gate docs, group matrix/closure docs, group metadata/recovery code, localization files, direct widget/application/integration tests, simulator wrapper, and gate script.
  - Result: current code exposes a global active recovery gate and raw recovery error, but the group details editor does not listen to that gate and currently commits replacement avatar files before the metadata use case rejects active recovery.
- Current role or phase: Closure Mapper complete
  - Source doc path: `Test-Flight-Improv/97-group-details-recovery-save-feedback.md`
  - Intended breakdown path: `Test-Flight-Improv/97-group-details-recovery-save-feedback-session-breakdown.md`
  - Files inspected: same bounded evidence set.
  - Result: closure target is a group-details save safety/feedback contract over the existing active recovery gate, not a redesign of group recovery, relay, inbox replay, or periodic maintenance.
- Current role or phase: Session Splitter complete
  - Source doc path: `Test-Flight-Improv/97-group-details-recovery-save-feedback.md`
  - Intended breakdown path: `Test-Flight-Improv/97-group-details-recovery-save-feedback-session-breakdown.md`
  - Files inspected: same bounded evidence set.
  - Result: split into production/direct-regression, multi-user acceptance, and final closure sessions because they use different verification layers.
- Current role or phase: Reviewer complete
  - Source doc path: `Test-Flight-Improv/97-group-details-recovery-save-feedback.md`
  - Intended breakdown path: `Test-Flight-Improv/97-group-details-recovery-save-feedback-session-breakdown.md`
  - Files inspected: same bounded evidence set.
  - Result: three sessions are sufficient; separating avatar atomicity from the Save waiting UX would create a misleading half-fix, while merging acceptance and closure would obscure failed simulator evidence.
- Current role or phase: Arbiter complete
  - Source doc path: `Test-Flight-Improv/97-group-details-recovery-save-feedback.md`
  - Intended breakdown path: `Test-Flight-Improv/97-group-details-recovery-save-feedback-session-breakdown.md`
  - Files inspected: same bounded evidence set.
  - Result: no structural blockers remain; the artifact is reusable for downstream pipeline execution.

## Decomposition artifact updated

- Artifact path: `Test-Flight-Improv/97-group-details-recovery-save-feedback-session-breakdown.md`
- Proposal/source doc path: `Test-Flight-Improv/97-group-details-recovery-save-feedback.md`
- Downstream workflow rule:
  - detailed planning happens one session at a time
  - later sessions must be refreshed against landed code before execution
- Intended plan path rule: every session plan must be doc-scoped as `Test-Flight-Improv/97-group-details-recovery-save-feedback-session-<session-id>-plan.md`.

## Recommended plan count

Recommended plan count: `3`

## Run Mode Snapshot

- Active mode: `standard`
- Degraded local continuation explicitly allowed: `no`
- Source proposal, matrix, or closure doc path: `Test-Flight-Improv/97-group-details-recovery-save-feedback.md`
- Source row/status vocabulary: source proposal is a bug spec with test cases and regressions; stable matrix rows use `Open`, `Partial`, `Covered`, and `Closed` evidence notes in `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`
- Overall closure bar: Report `97` closes only when the group details editor blocks unsafe saves during an active `groupRecoveryGate` window, preserves draft name/description/photo state, avoids raw recovery/resync copy and local-only completed avatar state, keeps ordinary maintenance from disabling Save, preserves existing admin metadata/photo behavior, records direct and A/B/C acceptance evidence, and updates stable matrix/closure docs without creating a new matrix doc.
- Final verdict policy: use `closed`, `accepted_with_explicit_follow_up`, `residual_only`, or `still_open`; in standard mode, `closed` requires all three sessions to resolve with sufficient code/test/doc evidence and no meaningful deferred work.

## Controller Progress

- 2026-05-29T00:00:00+02:00 - session `GDR-001`, phase `Plan Preparation`: run-mode snapshot persisted; ledger sanity found no stale accepted sessions; next action is a fresh `$implementation-plan-orchestrator` child for `Test-Flight-Improv/97-group-details-recovery-save-feedback-session-GDR-001-plan.md`.
- 2026-05-29T17:29:24+02:00 - session `GDR-001`, phase `Session Closure`: local pipeline fallback accepted GDR-001 after direct widget/application/l10n tests and `./scripts/run_test_gates.sh groups` passed. Next action is GDR-002 plan preparation.
- 2026-05-29T17:34:08+02:00 - session `GDR-002`, phase `Session Closure`: local pipeline fallback accepted GDR-002 after the promoted-admin A/B/C recovery-save selector, full convergence suite, and `./scripts/run_test_gates.sh groups` passed. Next action is GDR-003 closure.
- 2026-05-29T17:38:30+02:00 - session `GDR-003`, phase `Final Closure`: local pipeline fallback accepted GDR-003 after matrix/current-test-map/closure-reference/source updates and `git diff --check` passed. Final program verdict is `closed`.

## Overall closure bar

Report `97` closes only when group admins editing group name, description, or photo during a real active group recovery/update window get a clear waiting state instead of a failed raw save:

- the Edit Group Details sheet disables Save while `groupRecoveryGate` is active and shows simple non-jargon waiting copy plus an elapsed waiting timer
- typed name/description edits and a selected replacement photo remain as unsaved draft state while recovery is active
- when recovery ends while the editor is open, Save becomes available without losing the draft
- if recovery starts after the editor opens, Save disables before the user sees a raw `resync`/`group recovery` error
- if recovery starts during the save attempt, the user still sees simple recovery-wait copy and the app does not show a new completed group photo only on the editing device
- normal online continuity scheduling, including the 30-second sweep timer, does not disable Save unless the shared active recovery gate is actually entered
- existing admin, non-admin, demoted-admin, promoted-admin, and A/B/C metadata/photo convergence behavior remains green
- final integration and simulator evidence proves the promoted-admin/non-friend A/B/C metadata and photo outcome still converges after a successful post-recovery save
- stable matrix/closure docs record the new recovery-save feedback regression without inventing a new matrix doc

## Source of truth

- `Test-Flight-Improv/97-group-details-recovery-save-feedback.md` is the product intent source for this bug.
- `Test-Flight-Improv/14-regression-test-strategy.md` requires a targeted permanent regression for escaped production bugs and change-based named gates.
- `Test-Flight-Improv/test-gate-definitions.md` is the execution source of truth for named gates; `./scripts/run_test_gates.sh groups` includes `test/features/groups/integration/group_admin_metadata_convergence_test.dart`.
- `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md` is the stable group matrix to extend for existing rows such as `SC-007`, `UX-002`, and `UX-003`; do not create a new matrix doc.
- `Test-Flight-Improv/_current-test-map.md` maps group metadata/photo authority and recovery-sensitive group behavior to the groups gate and direct suites.
- `Test-Flight-Improv/60-post-creation-group-metadata-editing.md` and its session breakdown show post-creation metadata editing is already shipped and should not be reopened as a greenfield metadata feature.
- `Test-Flight-Improv/96-group-admin-permissions-regression-checklist-gap.md` and its breakdown show current promoted-admin metadata/photo convergence evidence, but not the recovery-save waiting UX.
- `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md` is the stable closure reference to update only if final acceptance changes release-confidence claims.
- `lib/features/groups/application/group_recovery_gate.dart` owns the active recovery depth/listenable and raw internal recovery error.
- `lib/features/groups/application/update_group_metadata_use_case.dart` rejects metadata mutation while recovery is active.
- `lib/features/groups/presentation/screens/group_info_wired.dart` owns the editor, Save handling, avatar upload/commit, snackbar copy, and metadata publish/inbox replay path.
- `lib/core/services/pending_message_retrier.dart` proves the 30-second continuity sweep is scheduling; the active unsafe window is the work wrapped in `runWithGroupRecoveryGate`.
- `lib/features/groups/presentation/screens/group_conversation_wired.dart` already demonstrates using `groupRecoveryGate.activeDepthListenable` from a UI surface.
- `lib/l10n/app_en.arb`, `lib/l10n/app_ar.arb`, `lib/l10n/app_de.arb`, and generated localization files own user-facing copy.
- `test/features/groups/presentation/group_info_wired_test.dart`, `test/features/groups/application/update_group_metadata_use_case_test.dart`, `test/features/groups/integration/group_admin_metadata_convergence_test.dart`, and `integration_test/group_admin_metadata_convergence_simulator_test.dart` are the direct proof surfaces.

## Session ledger

| session id | title | classification | intended plan file | depends on | initial status |
|---|---|---|---|---|---|
| `GDR-001` | Block unsafe group-details saves and preserve draft/avatar state during recovery | `implementation-ready` | `Test-Flight-Improv/97-group-details-recovery-save-feedback-session-GDR-001-plan.md` | none | `accepted` |
| `GDR-002` | Add promoted-admin A/B/C recovery-save acceptance proof | `acceptance-only` | `Test-Flight-Improv/97-group-details-recovery-save-feedback-session-GDR-002-plan.md` | `GDR-001` | `accepted` |
| `GDR-003` | Close Report 97 matrix, gate, and closure evidence | `closure-only` | `Test-Flight-Improv/97-group-details-recovery-save-feedback-session-GDR-003-plan.md` | `GDR-001`, `GDR-002` | `accepted` |

## Session closure ledger

| session id | current status | plan file | execution verdict | closure docs touched | blocker class | note |
|---|---|---|---|---|---|---|
| `GDR-001` | `accepted` | `Test-Flight-Improv/97-group-details-recovery-save-feedback-session-GDR-001-plan.md` | `accepted` | breakdown ledger only; stable matrix/docs deferred to `GDR-003` | none | Editor recovery gating, localized wait/timer copy, raw-error mapping, and avatar commit/delete atomicity landed. Passed `group_info_wired_test.dart`, `update_group_metadata_use_case_test.dart`, `l10n_integrity_test.dart`, and `./scripts/run_test_gates.sh groups`. |
| `GDR-002` | `accepted` | `Test-Flight-Improv/97-group-details-recovery-save-feedback-session-GDR-002-plan.md` | `accepted` | breakdown ledger only; stable matrix/docs deferred to `GDR-003` | none | Promoted-admin A/B/C recovery-save acceptance landed. Passed targeted selector, full `group_admin_metadata_convergence_test.dart`, and `./scripts/run_test_gates.sh groups`. |
| `GDR-003` | `accepted` | `Test-Flight-Improv/97-group-details-recovery-save-feedback-session-GDR-003-plan.md` | `accepted` | `Test-Flight-Improv/97-group-details-recovery-save-feedback.md`, `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`, `Test-Flight-Improv/_current-test-map.md`, `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`, breakdown final verdict | none | Final closure docs landed and `git diff --check` passed. |

## Final Program Verdict

Final program verdict: `closed`

Report 97 is closed on `2026-05-29`. The group details editor now blocks unsafe Save actions only while the shared recovery gate is active, preserves unsaved name/description/photo draft state, avoids raw recovery/resync copy, prevents local-only completed avatar state when recovery rejects a save, and keeps post-recovery promoted-admin A/B/C metadata/photo convergence green. Stable matrix, current test map, closure reference, source spec, and this breakdown now record the accepted evidence.

## Ordered session breakdown

### GDR-001 - Block unsafe group-details saves and preserve draft/avatar state during recovery

- Session classification: `implementation-ready`
- Intended plan file: `Test-Flight-Improv/97-group-details-recovery-save-feedback-session-GDR-001-plan.md`
- Exact scope:
  - make the Edit Group Details sheet observe the existing `groupRecoveryGate.activeDepthListenable`
  - disable Save during active recovery and while the group name is empty
  - show simple localized waiting copy and an elapsed waiting timer while recovery is active
  - preserve entered name, description, and selected photo preview while waiting
  - map metadata-save recovery rejection to user-facing wait copy instead of showing `Group recovery is in progress. Try again after resync completes.`
  - prevent avatar upload/commit or visible completed-avatar state from getting ahead of a metadata save that is rejected by active recovery
  - keep Save enabled during ordinary online maintenance when the active recovery gate is not entered
- Why it is its own session: this is the production bug seam. The Save waiting UX, recovery snackbar fallback, and no-local-only-photo behavior all live in the same group info editor save path, so splitting them would leave a partial fix that still violates the source bug.
- Likely code-entry files:
  - `lib/features/groups/presentation/screens/group_info_wired.dart`
  - `lib/features/groups/application/group_recovery_gate.dart`
  - `lib/features/groups/application/update_group_metadata_use_case.dart`
  - `lib/features/groups/application/group_avatar_storage.dart`
  - `lib/l10n/app_en.arb`
  - `lib/l10n/app_ar.arb`
  - `lib/l10n/app_de.arb`
  - `lib/l10n/app_localizations.dart`
  - `lib/l10n/app_localizations_en.dart`
  - `lib/l10n/app_localizations_ar.dart`
  - `lib/l10n/app_localizations_de.dart`
- Likely direct tests/regressions:
  - `flutter test test/features/groups/presentation/group_info_wired_test.dart`
  - targeted `group_info_wired_test.dart` selectors proving active recovery disables Save, elapsed waiting copy increments, recovery ending re-enables Save without losing edits, recovery-start-after-open disables Save, name-empty validation still keeps Save disabled, raw recovery/resync text is not shown, and blocked photo replacement does not persist as completed group avatar
  - `flutter test test/features/groups/application/update_group_metadata_use_case_test.dart` for recovery rejection/no persistence if the use-case contract is touched or missing direct coverage
  - `flutter test test/l10n/l10n_integrity_test.dart` if localization keys are added
- Likely named gates:
  - `./scripts/run_test_gates.sh groups`
  - the Baseline Gate remains the normal every-PR gate, but this session should not widen it
  - run `transport` only if planning unexpectedly touches lifecycle, resume, reconnect, or transport recovery internals
- Matrix/closure docs to update when done:
  - update this breakdown ledger during closure audit for `GDR-001`
  - defer stable matrix and closure doc updates to `GDR-003`
- Dependency on earlier sessions: none

### GDR-002 - Add promoted-admin A/B/C recovery-save acceptance proof

- Session classification: `acceptance-only`
- Intended plan file: `Test-Flight-Improv/97-group-details-recovery-save-feedback-session-GDR-002-plan.md`
- Exact scope:
  - after `GDR-001` lands, add or extend acceptance coverage for the reported A/B/C flow where User A and User B are friends, User B and User C are friends, User A and User C are not friends, admin roles change, and a successful metadata/photo update converges after recovery clears
  - prove the successful post-recovery save reaches all current group members for name, description, and photo metadata
  - prove the recovery-blocked save path does not produce a local-only completed group photo before the successful post-recovery save
  - keep this as acceptance evidence over existing group metadata/photo and simulator harnesses, not a new product feature
- Why it is its own session: the source requires integration and simulator/E2E evidence. That evidence has different runtime cost and failure modes than the widget/application fix, and a red multi-user run after the direct fix should be classified as acceptance failure, not mixed with editor implementation.
- Likely code-entry files:
  - `test/features/groups/integration/group_admin_metadata_convergence_test.dart`
  - `integration_test/group_admin_metadata_convergence_simulator_test.dart`
  - `test/shared/fakes/group_test_user.dart`
  - `test/shared/fakes/fake_group_pubsub_network.dart`
  - `test/shared/fakes/in_memory_group_repository.dart`
  - `scripts/run_test_gates.sh` only if a new test file is added and must be classified
  - `Test-Flight-Improv/test-gate-definitions.md` only if gate classification changes
- Likely direct tests/regressions:
  - `flutter test test/features/groups/integration/group_admin_metadata_convergence_test.dart`
  - targeted selector for the new promoted-admin recovery-save acceptance case, if added
  - `flutter test -d <device-id> integration_test/group_admin_metadata_convergence_simulator_test.dart` when a simulator/device is available
  - `./scripts/run_test_gates.sh completeness-check` if a new test file is introduced
- Likely named gates:
  - `./scripts/run_test_gates.sh groups`
  - `integration_test/group_admin_metadata_convergence_simulator_test.dart` remains an optional/manual direct simulator proof unless gate definitions are intentionally changed
- Matrix/closure docs to update when done:
  - update this breakdown ledger during closure audit for `GDR-002`
  - defer stable matrix and closure doc updates to `GDR-003`
- Dependency on earlier sessions: `GDR-001`

### GDR-003 - Close Report 97 matrix, gate, and closure evidence

- Session classification: `closure-only`
- Intended plan file: `Test-Flight-Improv/97-group-details-recovery-save-feedback-session-GDR-003-plan.md`
- Exact scope:
  - reconcile Report 97 against landed direct tests, integration evidence, simulator evidence, and named gates
  - update the stable group matrix and closure docs with the recovery-save feedback regression and final evidence
  - keep doc changes narrow: this is a follow-up to shipped metadata editing, not a reopening of Report 60's core metadata feature
  - persist final status in this breakdown, including accepted tests/gates and any explicit residuals
- Why it is its own session: closure depends on both the editor fix and the multi-user acceptance proof. It should not update stable docs until implementation and acceptance evidence are both known.
- Likely code-entry files:
  - no production code expected
  - `Test-Flight-Improv/97-group-details-recovery-save-feedback-session-breakdown.md`
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`
  - `Test-Flight-Improv/_current-test-map.md`
  - `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`
  - `Test-Flight-Improv/test-gate-definitions.md` only if `GDR-002` changes classification or adds a new test file
  - `Test-Flight-Improv/97-group-details-recovery-save-feedback.md` only if the repo convention for closed source specs requires a final status note
- Likely direct tests/regressions:
  - rerun the accepted `GDR-001` direct widget/application selectors or cite same-session evidence if still fresh
  - rerun the accepted `GDR-002` integration/simulator selectors or cite same-session evidence if still fresh
  - `./scripts/run_test_gates.sh groups`
  - `./scripts/run_test_gates.sh completeness-check` if test classification changed
  - `git diff --check`
- Likely named gates:
  - `./scripts/run_test_gates.sh groups`
  - no new named gate should be created for this bug
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md` for existing relevant rows, especially `SC-007`, `UX-002`, and `UX-003`
  - `Test-Flight-Improv/_current-test-map.md` if the group metadata/photo authority direct-suite notes need the new recovery-save proof
  - `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md` only if final acceptance changes release-confidence or regression-retirement claims
  - this breakdown final ledger/verdict
- Dependency on earlier sessions: `GDR-001`, `GDR-002`

## Why this is not fewer sessions

Two sessions would either merge the production fix with multi-user simulator acceptance or merge acceptance with final matrix closure. Both merges are unsafe:

- the editor/direct-regression work can be verified with focused widget/application tests before expensive multi-user evidence runs
- the promoted-admin A/B/C acceptance flow can fail for harness, convergence, or simulator reasons even after the editor fix is correct
- stable matrix/closure docs should not be updated until both the direct bug regression and multi-user acceptance proof are known

## Why this is not more sessions

More than three sessions would be bookkeeping. The Save disabled state, elapsed copy, raw-error mapping, and no-local-only-photo guarantee are all one cohesive `_GroupMetadataEditorSheet` / `_applyMetadataEdit` save path. Splitting name, description, photo, localization, and timer work separately would invite partial fixes without independent closure value. Recovery internals, relay behavior, inbox replay, key rotation, and group permission policy are explicit non-goals.

## Regression and gate contract

- `Test-Flight-Improv/14-regression-test-strategy.md` applies because this is an escaped user-facing bug: add permanent targeted regressions instead of relying on generic smoke coverage.
- `Test-Flight-Improv/test-gate-definitions.md` applies because group metadata/photo authority changes require `./scripts/run_test_gates.sh groups`.
- Direct proof for `GDR-001` should start with `group_info_wired_test.dart`, `update_group_metadata_use_case_test.dart` if the use-case contract changes, and `test/l10n/l10n_integrity_test.dart` if localization keys change.
- Acceptance proof for `GDR-002` should use `group_admin_metadata_convergence_test.dart` and the existing `group_admin_metadata_convergence_simulator_test.dart` wrapper rather than creating a new simulator artifact by default.
- `transport` is not required unless a downstream plan touches lifecycle/resume/reconnect/bridge recovery internals, which this decomposition treats as out of scope.
- `completeness-check` is required only if a new test file is added or gate classification changes.

## Matrix update contract

Use existing stable docs. Do not create a new matrix doc.

- `GDR-003` owns final matrix and closure updates.
- Update `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md` in the relevant existing rows rather than adding a new row by default:
  - `SC-007` for stale/resync privileged-operation safety
  - `UX-002` for group rename user-visible behavior
  - `UX-003` for group picture/description update behavior
- Update `Test-Flight-Improv/_current-test-map.md` only if the new direct/simulator proof changes the maintained group metadata/photo authority evidence map.
- Update `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md` only if final evidence changes release-confidence claims.
- Do not reopen `Test-Flight-Improv/60-post-creation-group-metadata-editing-session-breakdown.md`; Report 97 is a recovery-save feedback regression over the shipped metadata feature.

## Downstream execution path

| session id | next downstream steps |
|---|---|
| `GDR-001` | `$implementation-plan-orchestrator` -> `$implementation-execution-qa-orchestrator` -> `$implementation-closure-audit-orchestrator` |
| `GDR-002` | `$implementation-plan-orchestrator` -> `$implementation-execution-qa-orchestrator` -> `$implementation-closure-audit-orchestrator` |
| `GDR-003` | `$implementation-plan-orchestrator` -> `$implementation-execution-qa-orchestrator` -> `$implementation-closure-audit-orchestrator` |

## Structural blockers remaining

None. The split has a clear source doc, doc-scoped intended plan paths, direct regression targets, named gate contract, and final matrix ownership.

## Accepted differences intentionally left unchanged

- Exact localized waiting copy and timer formatting can be decided in `GDR-001` planning, as long as it avoids `resync` and `group recovery` jargon.
- The raw internal `groupRecoveryPendingError` may remain in lower-level use cases for non-editor callers; Report 97 only requires the Group Info metadata editor not to surface it to users.
- Routine online maintenance is not itself a blocker. Save should react to active `groupRecoveryGate` depth, not to the existence of a 30-second continuity timer.
- No change is planned to admin permission policy, invite policy, relay/recovery mechanics, encryption, key rotation, or group metadata authority.
- Simulator acceptance stays as targeted direct evidence unless gate definitions are intentionally widened.

## Exact docs/files used as evidence

- `Test-Flight-Improv/97-group-details-recovery-save-feedback.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`
- `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix.md`
- `Test-Flight-Improv/60-post-creation-group-metadata-editing.md`
- `Test-Flight-Improv/60-post-creation-group-metadata-editing-session-breakdown.md`
- `Test-Flight-Improv/96-group-admin-permissions-regression-checklist-gap.md`
- `Test-Flight-Improv/96-group-admin-permissions-regression-checklist-gap-session-breakdown.md`
- `Test-Flight-Improv/_current-test-map.md`
- `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`
- `Test-Flight-Improv/09-network-group-messaging.md`
- `Test-Flight-Improv/11-group-discussion-use-case-audit.md`
- `scripts/run_test_gates.sh`
- `lib/features/groups/application/group_recovery_gate.dart`
- `lib/features/groups/application/update_group_metadata_use_case.dart`
- `lib/features/groups/application/group_avatar_storage.dart`
- `lib/features/groups/presentation/screens/group_info_wired.dart`
- `lib/features/groups/presentation/screens/group_conversation_wired.dart`
- `lib/core/services/pending_message_retrier.dart`
- `lib/l10n/app_en.arb`
- `lib/l10n/app_ar.arb`
- `lib/l10n/app_de.arb`
- `lib/l10n/app_localizations.dart`
- `lib/l10n/app_localizations_en.dart`
- `lib/l10n/app_localizations_ar.dart`
- `lib/l10n/app_localizations_de.dart`
- `test/features/groups/presentation/group_info_wired_test.dart`
- `test/features/groups/application/update_group_metadata_use_case_test.dart`
- `test/features/groups/integration/group_admin_metadata_convergence_test.dart`
- `integration_test/group_admin_metadata_convergence_simulator_test.dart`
- `test/shared/fakes/group_test_user.dart`
- `test/shared/fakes/fake_group_pubsub_network.dart`
- `test/shared/fakes/in_memory_group_repository.dart`

## Why the decomposition is safe to send into downstream planning/execution

- Every session has a doc-scoped intended plan file under `Test-Flight-Improv/97-group-details-recovery-save-feedback-session-<session-id>-plan.md`.
- `GDR-001` leaves a meaningful verified state: the editor no longer exposes raw recovery errors or local-only completed photo state under active recovery.
- `GDR-002` leaves a meaningful verified state: the reported promoted-admin/non-friend A/B/C flow has integration/simulator acceptance evidence after recovery clears.
- `GDR-003` leaves a meaningful verified state: matrix, gate, and closure docs match the landed evidence.
- The split uses existing group metadata/recovery code and existing test infrastructure, and it avoids broad recovery, relay, transport, permission, or key-management scope.
