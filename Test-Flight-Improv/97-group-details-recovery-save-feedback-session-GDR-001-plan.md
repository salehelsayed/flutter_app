Status: execution-ready

# GDR-001 Plan - Block unsafe group-details saves and preserve draft/avatar state during recovery

## Planning Progress

- 2026-05-29T16:54:30+02:00 - Local plan fallback completed. Files inspected since last update: `Test-Flight-Improv/97-group-details-recovery-save-feedback-session-breakdown.md`, `Test-Flight-Improv/97-group-details-recovery-save-feedback.md`, `lib/features/groups/application/group_recovery_gate.dart`, `lib/features/groups/application/update_group_metadata_use_case.dart`, `lib/features/groups/application/group_avatar_storage.dart`, `lib/features/groups/presentation/screens/group_info_wired.dart`. Decision/blocker: spawned planner produced only a partial draft, then no reusable plan; the breakdown entry is execution-safe, so this doc-scoped fallback plan is now the execution contract. Next action: spawn `$implementation-execution-qa-orchestrator` for GDR-001.

## Real Scope

Implement only the GDR-001 production bug seam:

- make the Edit Group Details dialog observe `groupRecoveryGate.activeDepthListenable`
- disable Save while recovery is active and while the trimmed group name is empty
- show localized, user-facing waiting copy with an elapsed waiting timer while recovery is active
- preserve typed name, description, and selected replacement-photo preview while waiting and when recovery ends
- map metadata-save recovery rejection to the same simple wait copy instead of surfacing `Group recovery is in progress. Try again after resync completes.`
- prevent a recovery-rejected save from committing a replacement/removal as the visible completed group avatar on only the editing device
- keep ordinary online maintenance from disabling Save unless the shared active recovery gate is entered

Out of scope:

- group recovery, relay, inbox replay, key rotation, transport, invite, admin-permission, or membership-policy redesign
- new simulator/device fixtures; GDR-002 owns A/B/C acceptance proof
- stable matrix/closure updates; GDR-003 owns final docs
- changing lower-level raw recovery errors for non-editor callers except where direct tests prove the existing use-case guard remains intact

## Closure Bar

GDR-001 is complete when all of these are true:

- the editor disables `group-edit-save` when `groupRecoveryGate` is active, even if the name is valid
- the editor still disables Save for empty-name validation after recovery ends
- the editor shows simple localized recovery-wait copy and a live elapsed timer while active recovery is present
- recovery ending while the dialog is open re-enables Save without losing typed name, description, or selected photo preview state
- recovery starting after the dialog opens disables Save before a user can see raw recovery/resync text
- a recovery rejection during save shows localized wait copy, not the raw `groupRecoveryPendingError`
- replacement/removal avatar disk commit does not happen before a metadata update that is rejected by active recovery
- existing successful admin metadata edit, non-admin rejection, demoted-admin rejection, empty-name rejection, signed replay/audit payload, and signing-failure rollback behavior remain green
- required direct tests and named gates below pass or any failure is classified as pre-existing/environmental with concrete evidence

## Source Of Truth

- Product intent: `Test-Flight-Improv/97-group-details-recovery-save-feedback.md`
- Current session contract: `Test-Flight-Improv/97-group-details-recovery-save-feedback-session-breakdown.md`
- Gate contract: `Test-Flight-Improv/14-regression-test-strategy.md`, `Test-Flight-Improv/test-gate-definitions.md`
- Active recovery API: `lib/features/groups/application/group_recovery_gate.dart`
- Metadata mutation guard: `lib/features/groups/application/update_group_metadata_use_case.dart`
- Group details editor/save path: `lib/features/groups/presentation/screens/group_info_wired.dart`
- Avatar commit helpers: `lib/features/groups/application/group_avatar_storage.dart`
- Localized copy: `lib/l10n/app_en.arb`, `lib/l10n/app_ar.arb`, `lib/l10n/app_de.arb`, generated `lib/l10n/app_localizations*.dart`
- Direct proof: `test/features/groups/presentation/group_info_wired_test.dart`, `test/features/groups/application/update_group_metadata_use_case_test.dart`, `test/l10n/l10n_integrity_test.dart`

When prose and code disagree, current code/tests win unless the source doc explicitly names the user-facing bug gap.

## Session Classification

`implementation-ready`

## Exact Problem Statement

The Group Info metadata editor currently disables Save only for an empty name. The lower-level metadata use case rejects active recovery with raw internal copy, and the save path can upload/commit a replacement group avatar before `updateGroupMetadata` rejects the metadata mutation. Admins therefore can see a confusing raw recovery/resync snackbar and, in the photo path, a local completed-avatar state that is not backed by a successful metadata update.

## Device/Relay Proof Profile

Profile: `host-only`.

No Flutter device, paired-device, relay, multi-relay, OS notification, or `integration_test` proof is required for GDR-001. This session changes a host-testable editor/use-case/avatar-atomicity seam. GDR-002 owns the A/B/C integration/simulator acceptance proof.

## Files And Repos To Inspect Next

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
- `test/features/groups/presentation/group_info_wired_test.dart`
- `test/features/groups/application/update_group_metadata_use_case_test.dart`
- `test/l10n/l10n_integrity_test.dart`
- `scripts/run_test_gates.sh`

## Implementation Steps

1. Add focused regressions first in `test/features/groups/presentation/group_info_wired_test.dart`:
   - active recovery before opening the editor disables `group-edit-save`, shows simple recovery-wait copy, and increments elapsed waiting copy after a pumped duration
   - recovery ending while the editor is open re-enables Save and preserves edited name/description plus selected-photo preview state
   - recovery starting after the editor opens disables Save and shows wait copy
   - empty-name validation still keeps Save disabled after recovery ends
   - a recovery rejection from the save path maps to localized wait copy and does not show `resync`, `group recovery`, or `groupRecoveryPendingError`
   - a blocked replacement/removal does not commit the canonical group avatar as completed saved state before metadata success
2. Add or extend `test/features/groups/application/update_group_metadata_use_case_test.dart` only if execution touches the use-case contract beyond observing its current recovery guard. Keep the existing raw internal `StateError(groupRecoveryPendingError)` contract green for lower-level callers unless a direct change is necessary.
3. Add localized keys in all ARB files for the editor waiting message and elapsed timer. Use simple user-facing copy that avoids `resync` and `group recovery`. Regenerate checked-in localization files with the repo's normal Flutter l10n generator, or update generated files consistently if the generator is unavailable.
4. In `group_info_wired.dart`, pass the shared `groupRecoveryGate.activeDepthListenable` into `_GroupMetadataEditorSheet`.
5. In `_GroupMetadataEditorSheet`, listen to the active depth without rebuilding or recreating text controllers. Track elapsed active-wait time with a timer while recovery is active, cancel it when inactive/disposed, and keep typed name/description/photo preview state intact.
6. Disable Save when either the trimmed name is empty or recovery is active. `_save()` must no-op while recovery is active even if the button handler is reached.
7. Show the localized wait message and elapsed timer near the action row while recovery is active. The timer must count elapsed seconds and must not promise remaining time.
8. In `_applyMetadataEdit`, map `StateError` with `groupRecoveryPendingError` to the localized wait snackbar. Do not change unrelated error copy.
9. Reorder avatar replacement/removal side effects so canonical local avatar commit/delete happens only after the metadata update has passed the active-recovery guard and is about to persist. A safe shape is:
   - perform a preflight `isGroupRecoveryInProgress()` check before avatar upload work
   - keep uploaded avatar metadata in local variables, but defer `commitPreparedGroupAvatar(...)` and `deleteGroupAvatar(...)` into the `beforePersist` callback or another point that cannot run when `updateGroupMetadata` rejects active recovery
   - add a fresh active-recovery check immediately before deferred local avatar commit/delete so recovery that starts during the save attempt returns the localized wait copy without leaving a canonical local-only avatar
10. Keep existing successful save ordering for signing, repo update, timeline message, publish, inbox store, direct membership update, `_loadGroupInfo()`, and success snackbar.

## Exact Tests And Gates To Run

Run these before the execution verdict:

```bash
flutter test --no-pub test/features/groups/presentation/group_info_wired_test.dart
flutter test --no-pub test/features/groups/application/update_group_metadata_use_case_test.dart
flutter test --no-pub test/l10n/l10n_integrity_test.dart
./scripts/run_test_gates.sh groups
```

Run `flutter gen-l10n` before l10n tests if ARB keys are added and generated localization files are stale.

Do not run `transport` unless execution unexpectedly touches lifecycle, resume, reconnect, bridge recovery, or transport internals.

## Known-Failure Interpretation

- Required direct tests or the `groups` gate failing in files touched by GDR-001 are blocking unless the failure is concretely triaged as pre-existing or environment/tooling-related.
- Existing unrelated dirty worktree changes are not part of GDR-001 and must not be reverted.
- Simulator/device unavailability is not a GDR-001 blocker because this session is host-only.

## Scope Guard

Do not change:

- group recovery gate semantics beyond reading `activeDepthListenable`/`isGroupRecoveryInProgress()`
- group membership, role, invite, relay, inbox replay, transport, encryption, key rotation, or group media authorization policy
- A/B/C acceptance tests except where needed only to keep compile shape after a local helper signature change; GDR-002 owns acceptance proof
- stable matrix or closure docs; GDR-003 owns those updates

## Done Criteria

- Production code and localization files implement the closure bar.
- Direct regressions prove disabled Save, timer copy, draft/photo preview preservation, recovery-start-after-open, raw-error mapping, empty-name behavior, and no local-only completed avatar on recovery rejection.
- Required commands in `Exact Tests And Gates To Run` are executed and recorded in `## Execution Progress`.
- No blocking QA findings remain.

## Reviewer Findings

- Required regression-first coverage is explicit and tied to the escaped bug.
- Host-only profile is acceptable for GDR-001 because GDR-002 owns multi-user A/B/C acceptance.
- Avatar atomicity must cover both replacement and removal paths because both mutate canonical local avatar state before metadata success in the current save shape.
- The plan must not weaken the lower-level raw recovery guard; the user-facing mapping belongs in the editor save path.

## Arbiter Decision

- Structural blockers: none.
- Incremental details: exact localized wording and timer formatting may be chosen during execution as long as copy remains simple and avoids `resync`/`group recovery`.
- Accepted differences: no simulator proof in GDR-001; that evidence is intentionally deferred to GDR-002.

## Execution Progress

- 2026-05-29T16:57:13+02:00 - Phase: contract extraction started. Files inspected/touched: `Test-Flight-Improv/97-group-details-recovery-save-feedback-session-GDR-001-plan.md`, `git status --short`. Command: none. Decision/blocker: plan is execution-ready, host-only, and contains explicit scope, tests, gates, done criteria, and scope guard. Next action: extract exact execution contract, then spawn Executor.
- 2026-05-29T16:57:13+02:00 - Phase: contract extraction completed. Files inspected/touched: current plan only. Command: none. Decision/blocker: execute only group details editor recovery save gating, localized wait copy/timer, raw-error mapping, and avatar commit atomicity; required commands are the three direct `flutter test --no-pub ...` commands plus `./scripts/run_test_gates.sh groups`; no known blocker. Next action: spawn fresh Executor agent.
- 2026-05-29T16:58:15+02:00 - Phase: contract extraction restarted by execution orchestrator. Files inspected/touched: `Test-Flight-Improv/97-group-details-recovery-save-feedback-session-GDR-001-plan.md`, `git status --short`, `codex exec --help`. Command: none. Decision/blocker: Codex CLI child-agent spawning is available; execute GDR-001 only and preserve unrelated dirty worktree changes. Next action: extract bounded contract and spawn fresh Executor.
- 2026-05-29T16:58:15+02:00 - Phase: contract extraction completed by execution orchestrator. Files inspected/touched: current plan only. Command: none. Decision/blocker: exact scope is editor recovery Save gating, localized wait copy/timer, raw recovery-error mapping, and avatar commit atomicity; required direct tests are `flutter test --no-pub test/features/groups/presentation/group_info_wired_test.dart`, `flutter test --no-pub test/features/groups/application/update_group_metadata_use_case_test.dart`, `flutter test --no-pub test/l10n/l10n_integrity_test.dart`; required named gate is `./scripts/run_test_gates.sh groups`; `flutter gen-l10n` is required if ARB/generated l10n files are stale after adding keys. Next action: spawn fresh Executor agent.
- 2026-05-29T16:58:36+02:00 - Phase: Executor spawn requested. Files inspected/touched: current plan only. Command: `codex exec -m gpt-5.5 -c model_reasoning_effort="xhigh" -C /Users/I560101/Project-Sat/mknoon-2/flutter_app -s danger-full-access -a never ...`. Decision/blocker: spawning isolated Executor for initial implementation pass. Next action: wait bounded interval, then inspect assigned-step evidence.
- 2026-05-29T16:59:01+02:00 - Phase: Executor spawn command corrected. Files inspected/touched: current plan only. Command: prior `codex exec ... -a never ...` returned CLI usage error before child materialized because approval policy is a top-level option. Decision/blocker: no child work started and no code/test files were touched by the failed command. Next action: retry Executor spawn with top-level `codex -a never ... exec`.
- 2026-05-29T16:59:35+02:00 - Phase: Executor initial implementation pass started. Files inspected/touched: current plan, `git status --short`. Command: none. Decision/blocker: honoring GDR-001 scope only; pre-existing dirty worktree is present and will not be reverted. Next action: inspect editor, recovery gate, avatar storage, l10n, and direct tests.
- 2026-05-29T16:59:35+02:00 - Phase: Executor inspection in progress. Files inspected/touched: `lib/features/groups/presentation/screens/group_info_wired.dart`, `lib/features/groups/application/group_recovery_gate.dart`, `lib/features/groups/application/update_group_metadata_use_case.dart`, `lib/features/groups/application/group_avatar_storage.dart`, `test/features/groups/presentation/group_info_wired_test.dart`. Command: `rg` over GDR-001 owner files. Decision/blocker: target seams found in `_applyMetadataEdit`, `_GroupMetadataEditorSheet`, `groupRecoveryPendingError`, and avatar commit/delete calls. Next action: read owner sections and add regression-first coverage.
- 2026-05-29T17:03:41+02:00 - Phase: regression-first tests added. Files inspected/touched: `test/features/groups/presentation/group_info_wired_test.dart`. Command: none. Decision/blocker: no exact existing regression covered GDR-001; added focused widget regressions for active recovery gating/timer, draft and photo preview preservation, recovery-start-after-open, empty-name-after-recovery, raw rejection mapping, and replacement/removal avatar atomicity. Next action: implement production/localization changes.
- 2026-05-29T17:04:59+02:00 - Phase: production and ARB edits completed. Files inspected/touched: `lib/features/groups/presentation/screens/group_info_wired.dart`, `lib/l10n/app_en.arb`, `lib/l10n/app_ar.arb`, `lib/l10n/app_de.arb`. Command: none. Decision/blocker: editor now observes the shared recovery gate, disables/no-ops Save while active, shows localized wait/timer copy, maps raw recovery rejection to wait copy, and defers avatar delete/commit into the signed metadata before-persist path. Next action: run `flutter gen-l10n` because ARB keys were added.
- 2026-05-29T17:05:15+02:00 - Phase: l10n generation completed. Files inspected/touched: generated `lib/l10n/app_localizations*.dart`. Command: `flutter gen-l10n`. Decision/blocker: command completed successfully after noting `l10n.yaml` controls options. Next action: format touched Dart files and run required direct tests/gate.
- 2026-05-29T17:06:01+02:00 - Phase: implementation refinement completed. Files inspected/touched: `lib/features/groups/presentation/screens/group_info_wired.dart`. Command: `dart format lib/features/groups/presentation/screens/group_info_wired.dart`. Decision/blocker: avatar disk delete/commit now occurs after both metadata signatures succeed and immediately after a fresh recovery check inside `beforePersist`. Next action: run required direct tests.
- 2026-05-29T17:06:10+02:00 - Phase: required direct test started. Files inspected/touched: none. Command: `flutter test --no-pub test/features/groups/presentation/group_info_wired_test.dart`. Decision/blocker: running touched widget suite first for GDR-001 compile and behavior proof. Next action: record result and triage failures if any.
- 2026-05-29T17:06:39+02:00 - Phase: required direct test failed and triaged. Files inspected/touched: `lib/features/groups/presentation/screens/group_info_wired.dart`, `test/features/groups/presentation/group_info_wired_test.dart`. Command: `flutter test --no-pub test/features/groups/presentation/group_info_wired_test.dart`. Decision/blocker: caused by this session; compile errors were missing `ValueListenable` import and non-nullable test upload stub return type. Next action: fix compile-shape issues and rerun the same required test.
- 2026-05-29T17:07:00+02:00 - Phase: required direct test restarted. Files inspected/touched: none. Command: `flutter test --no-pub test/features/groups/presentation/group_info_wired_test.dart`. Decision/blocker: rerunning after session-caused compile fixes. Next action: record result and triage failures if any.
- 2026-05-29T17:07:18+02:00 - Phase: required direct test failed and triaged. Files inspected/touched: `test/features/groups/presentation/group_info_wired_test.dart`. Command: `flutter test --no-pub test/features/groups/presentation/group_info_wired_test.dart`. Decision/blocker: caused by this session; upload stub still inferred `Future<GroupAvatarUpload>` instead of nullable typedef. Next action: return explicit `Future<GroupAvatarUpload?>` and rerun.
- 2026-05-29T17:07:32+02:00 - Phase: required direct test restarted. Files inspected/touched: none. Command: `flutter test --no-pub test/features/groups/presentation/group_info_wired_test.dart`. Decision/blocker: rerunning after explicit nullable upload stub fix. Next action: record result and triage failures if any.
- 2026-05-29T17:07:49+02:00 - Phase: required direct test failed and triaged. Files inspected/touched: `test/features/groups/presentation/group_info_wired_test.dart`. Command: `flutter test --no-pub test/features/groups/presentation/group_info_wired_test.dart`. Decision/blocker: caused by this session; test upload stub made `mime` required while `UploadGroupAvatarFn` defines it optional. Next action: match typedef signature exactly and rerun.
- 2026-05-29T17:08:06+02:00 - Phase: required direct test restarted. Files inspected/touched: none. Command: `flutter test --no-pub test/features/groups/presentation/group_info_wired_test.dart`. Decision/blocker: rerunning after exact upload typedef signature fix. Next action: record result and triage failures if any.
- 2026-05-29T17:24:38+02:00 - Phase: local execution fallback completed implementation and focused verification. Files inspected/touched: `lib/features/groups/presentation/screens/group_info_wired.dart`, `lib/l10n/app_en.arb`, `lib/l10n/app_ar.arb`, `lib/l10n/app_de.arb`, generated `lib/l10n/app_localizations*.dart`, `test/features/groups/presentation/group_info_wired_test.dart`. Commands: `flutter gen-l10n`, `dart format ...`, `flutter test --no-pub test/features/groups/presentation/group_info_wired_test.dart --name GDR-001 --timeout 60s`. Decision/blocker: all seven GDR-001 widget regressions passed after test helper fixes for fake-async avatar picking and visible Save taps. Next action: run required full direct suites.
- 2026-05-29T17:25:00+02:00 - Phase: required direct suites completed. Files inspected/touched: none. Commands: `flutter test --no-pub test/features/groups/presentation/group_info_wired_test.dart`, `flutter test --no-pub test/features/groups/application/update_group_metadata_use_case_test.dart`, `flutter test --no-pub test/l10n/l10n_integrity_test.dart`. Decision/blocker: all three direct suites passed. Next action: run named `groups` gate.
- 2026-05-29T17:28:07+02:00 - Phase: named gate failure triaged and repaired. Files inspected/touched: `test/features/groups/integration/group_membership_smoke_test.dart`. Commands: `./scripts/run_test_gates.sh groups`, `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'UP-001 create add remove and re-add keep DB and bridge groupConfig snapshots aligned'`. Decision/blocker: the gate failure was reproducible in UP-001 due to a fixed `2026-05-13` membership timestamp now stale against groups created on 2026-05-29; repaired the test fixture to derive the add/remove/re-add membership event timeline from the created group run. Next action: rerun `groups`.
- 2026-05-29T17:29:10+02:00 - Phase: named gate completed. Files inspected/touched: none. Command: `./scripts/run_test_gates.sh groups`. Decision/blocker: gate passed with exit 0. Next action: write execution verdict and close GDR-001.

## Execution Verdict

Accepted.

- Production result: Group Info metadata editing now observes `groupRecoveryGate.activeDepthListenable`, disables/no-ops Save during active recovery, shows localized waiting copy plus elapsed seconds, preserves text and picked-photo draft state while waiting, maps lower-level `groupRecoveryPendingError` to user-facing wait copy, and defers local avatar delete/commit until the metadata update's signed `beforePersist` path after a fresh recovery check.
- Tests added/updated: `group_info_wired_test.dart` now covers active recovery before opening, recovery ending with preserved draft/photo preview, recovery starting after open, empty-name validation after recovery, raw recovery rejection mapping, blocked replacement avatar atomicity, and blocked removal avatar atomicity. `group_membership_smoke_test.dart` has a time-stable UP-001 fixture repair needed to keep the required `groups` gate green on May 29, 2026 and later.
- Required verification passed:
  - `flutter test --no-pub test/features/groups/presentation/group_info_wired_test.dart`
  - `flutter test --no-pub test/features/groups/application/update_group_metadata_use_case_test.dart`
  - `flutter test --no-pub test/l10n/l10n_integrity_test.dart`
  - `./scripts/run_test_gates.sh groups`
- QA result: no blocking findings remain for GDR-001. GDR-002 still owns promoted-admin A/B/C acceptance evidence; GDR-003 still owns stable matrix/closure doc updates.

## Dirty Worktree Snapshot Before Execution

- 2026-05-29T16:54:30+02:00 controller command: `git status --short`
- Relevant doc-scoped pending paths before GDR-001 execution: `?? Test-Flight-Improv/97-group-details-recovery-save-feedback.md`, `?? Test-Flight-Improv/97-group-details-recovery-save-feedback-session-breakdown.md`, `?? Test-Flight-Improv/97-group-details-recovery-save-feedback-session-GDR-001-plan.md`
- Relevant stable closure path already dirty before GDR-001 execution: `M Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`
- Other pre-existing dirty worktree entries include `info.plist`, multi-party device harness/scripts, `lib/features/groups/application/group_message_listener.dart`, `test/features/groups/application/group_message_listener_test.dart`, `test/integration/group_multi_party_device_criteria_test.dart`, many `test-upload*` deletions, `Network-Arch/Transport-Reliability/`, and Report 95/96 docs. These are outside GDR-001 scope and must not be reverted by this session.
