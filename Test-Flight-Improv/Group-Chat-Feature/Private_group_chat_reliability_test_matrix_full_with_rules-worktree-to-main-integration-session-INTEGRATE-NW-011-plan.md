# INTEGRATE-NW-011 Plan - Worktree To Main Integration Contract

Status: accepted

Mode: standard worktree-to-main integration. This is not gap closure and must not recreate or rewrite the historical source worktree implementation plan.

## Planning Progress

- 2026-05-20 02:28:56 CEST | Role: Arbiter completed | Files inspected since last update: reviewer pass, integration breakdown current row state, source closure result, current-main selector/status scout. | Decision/blocker: execution-ready for `INTEGRATE-NW-011`; no structural blocker remains if the executor imports/verifies only row-owned NW-011 deltas and preserves existing main changes. | Next action: hand off this contract for row-scoped import/verification only.
- 2026-05-20 02:27:00 CEST | Role: Reviewer completed | Files inspected since last update: draft contract, allowed file list, focused host commands, already-present/partial/missing handling. | Decision/blocker: sufficient with explicit dirty-file conflict handling and host-only device profile. | Next action: arbiter stop decision.
- 2026-05-20 02:25:00 CEST | Role: Planner completed | Files inspected since last update: source NW-011 plan final closure, source matrix row, source breakdown session block, controlling integration breakdown. | Decision/blocker: plan should import/verify test-only proof surfaces; production, native, harness, source docs, and adjacent rows stay out of scope. | Next action: reviewer sufficiency pass.
- 2026-05-20 02:22:00 CEST | Role: Evidence Collector completed | Files inspected since last update: target plan path, source worktree selectors, current main focused selector search, targeted git status. | Decision/blocker: source row is closed/accepted; current main has `INTEGRATE-NW-011` pending and no `NW-011` selector anchors in the five target files; three target files are already modified in main. | Next action: draft minimal integration contract.

## Execution Progress

- 2026-05-20 02:32:51 CEST | Phase: before contract extraction | Files inspected or touched: current integration plan, targeted git status, five-file `NW-011` selector scout. | Command/evidence: `rg -n "NW-011"` across the five target files returned no matches; status shows three modified target files and this untracked plan file. | Decision/blocker: proceed with contract extraction and then inspect current diffs before any test-file edits. | Next action: extract exact import/test contract from source and current plan.
- 2026-05-20 02:33:25 CEST | Phase: contract extraction completed | Files inspected or touched: current integration plan, historical source NW-011 plan, source selector anchors, current target diffs. | Command/evidence: source `rg -n "NW-011"` identifies five row-owned selectors in the five allowed test files; current diff inspection is in progress and shows existing non-NW-011 edits in modified target files. | Decision/blocker: import only the five missing row-owned selectors and preserve current-main edits; no production, native, harness, or closure-doc scope. | Next action: inspect source/current insertion contexts and apply minimal test-file hunks.
- 2026-05-20 02:34:51 CEST | Phase: before import | Files inspected or touched: source selector blocks and current insertion contexts in all five target files. | Command/evidence: helper drift identified only inside allowed test files (`publishStarted` on `_GatedPublishBridge`, optional retry fields on `_makeGroupSendingMessage`, `GroupMessage` import for resumed test). | Decision/blocker: no hunk conflict found; proceed with minimal row-owned test/helper imports. | Next action: apply NW-011-only patches.
- 2026-05-20 02:36:28 CEST | Phase: import completed / before focused tests | Files inspected or touched: five allowed target test files. | Command/evidence: `rg -n "NW-011"` now finds all five source-owned selectors in current main; early scoped format changed only `test/core/lifecycle/handle_app_paused_group_test.dart`. | Decision/blocker: import completed without source-doc, production, native, harness, or adjacent-row edits. | Next action: run the five required focused `flutter test --plain-name 'NW-011'` selectors.
- 2026-05-20 02:37:36 CEST | Phase: focused tests completed / before scoped checks | Files inspected or touched: five allowed target test files. | Command/evidence: all five required `flutter test --no-pub ... --plain-name 'NW-011'` selectors passed: wired route-unmount, send-use-case pre-persist, pause, resume, and fake-network recovery. | Decision/blocker: no focused production gap or hunk conflict exposed. | Next action: run scoped format/analyze and `git diff --check`.
- 2026-05-20 02:39:04 CEST | Phase: scoped checks completed / before QA | Files inspected or touched: five allowed target test files. | Command/evidence: `dart format --set-exit-if-changed` passed with 0 changes; `flutter analyze` over the five target test files passed with no issues; `git diff --check` passed. | Decision/blocker: required focused and scoped host evidence is green; preservation gates remain skipped under this execution prompt. | Next action: QA review scope, diff ownership, and final verdict.
- 2026-05-20 02:39:36 CEST | Phase: QA completed / final verdict written | Files inspected or touched: five target test files and this plan file. | Command/evidence: QA confirmed edits stayed within allowed files, all five `NW-011` selectors are present, no production/native/harness/source-doc/closure-doc files were touched, and required host checks passed. | Decision/blocker: no blocking issue remains for `INTEGRATE-NW-011`. | Next action: return final execution summary.
- 2026-05-20 02:47:53 CEST | Phase: controller post-closure affected-test evidence | Files inspected or touched: this plan only. | Command/evidence: affected preservation selectors passed serially after closure: `GR-017 recovery preserves failed direct and pending inbox retry state`; `NW-010 foreground resume rejoins drains then acknowledges background group recovery`; `NW-010 background pause resumes ordered group delivery after membership edit`; `NW-007 topic peer count zero keeps active member recipients and no receipt claims`; `NW-007 zero topic peers keep membership and replay recovery for all active members`. | Decision/blocker: NW-011 acceptance remains valid and no additional code/test import is required. | Next action: record the same evidence in the controlling breakdown and inventory, then run ledger sanity before NW-012.

## Execution Result

Final verdict: `accepted` for `INTEGRATE-NW-011` only.

Imported/verified row-owned selectors:

- `test/features/groups/presentation/screens/group_conversation_wired_bg_task_test.dart`: `NW-011 route unmount during group send leaves durable or retryable row, never hidden`
- `test/features/groups/application/send_group_message_use_case_test.dart`: `NW-011 send pre-persist survives lifecycle cancellation window`
- `test/core/lifecycle/handle_app_paused_group_test.dart`: `NW-011 pause transitions in-flight group send to retryable failed without deleting custody`
- `test/core/lifecycle/handle_app_resumed_group_recovery_test.dart`: `NW-011 resume retries failed or pending background send after rejoin and drain`
- `test/features/groups/integration/group_resume_recovery_test.dart`: `NW-011 backgrounded sender send is delivered or remains retryable with no invisible send`

Required focused tests: all five `flutter test --no-pub ... --plain-name 'NW-011'` commands passed.

Scoped checks: `dart format --set-exit-if-changed` over the five target files passed with 0 changes after the import-format pass; `flutter analyze` over the five target files passed with no issues; `git diff --check` passed.

Controller affected preservation checks: passed `GR-017 recovery preserves failed direct and pending inbox retry state`, `NW-010 foreground resume rejoins drains then acknowledges background group recovery`, `NW-010 background pause resumes ordered group delivery after membership edit`, `NW-007 topic peer count zero keeps active member recipients and no receipt claims`, and `NW-007 zero topic peers keep membership and replay recovery for all active members`.

Skipped gates: `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups`, `./scripts/run_test_gates.sh completeness-check`, and live simulator/device proofs were not run under this execution prompt. No iOS 26.2 or live simulator proof is required for this row.

Spawned-agent isolation used: no nested spawned-agent capability is available in this environment; execution and QA were performed sequentially in this write-active execution agent.

## Closure Audit Result

Closure verdict: `accepted` for `INTEGRATE-NW-011` only.

Closure audit on 2026-05-20 confirmed the accepted execution result imported only the five row-owned host test selectors listed above. No production, native, harness, source-doc, source matrix, source breakdown, COMPLETE_1, or adjacent-row plan edits are claimed for this row. The controlling breakdown and test inventory carry the durable closure record; the program verdict remains `still_open` because later integration rows are still pending, with `INTEGRATE-NW-012` next.

No iOS, Android, physical-device, macOS app-peer, or live simulator proof is required for NW-011 because the row is host-only and `3-Party E2E` is `N/A`.

## real scope

Own exactly integration row `INTEGRATE-NW-011`, sourced from historical row `NW-011`: "Send during background or app unmount is either durable or blocked."

The only implementation import target is the missing row-owned NW-011 host proof from the source worktree. Source closure says production code stayed untouched, no Go/native proof was required, and no live simulator proof was run or required. Therefore this integration session should be a test/proof import plus focused verification unless current-main evidence proves the row is already present.

Do not import or close NW-012, NW-013, NW-014, NW-015, UP-008, UP-013, media, notification, stress, broader lifecycle, broader relay/shared-state, source-doc, COMPLETE_1, or harness work.

## closure bar

The row is integration-accepted only when current main has row-owned proof that a started outbound group send during route unmount or app backgrounding either:

- has exactly one durable/retryable sender row, with retry material preserved for `pending` or `failed` states; or
- is explicitly blocked before any local hidden row, bridge publish, or inbox-store side effect exists.

Accepted current-main proof must cover route unmount, send-use-case pre-persist, pause, resume ordering, and fake-network recipient/sender outcome. Recipient delivery must be exact-once when delivery succeeds; otherwise the sender must retain one retryable row. Duplicate visible rows, invisible sends, lost retry material, retry-before-rejoin/drain, or false local-only success fail the row.

## source of truth

- Controlling integration breakdown: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-breakdown.md`.
- Historical source plan: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-NW-011-plan.md`.
- Historical source matrix row: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules.md`, row `NW-011`.
- Historical source breakdown session: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`, session `NW-011`.
- Current main code/tests win over stale prose for import conflicts. The source closure evidence wins for intended row ownership and device profile. The controlling integration breakdown wins for current integration status.

## session classification

`implementation-ready`

This is ready for a narrow integration executor because source row `NW-011` is `Covered` / `accepted`, the source closure identifies exact row-owned tests, and current main marks `INTEGRATE-NW-011` as `pending_integration`.

## exact problem statement

The source worktree closed the send-cancellation risk with tests proving that route unmount or app pause during send startup cannot create an invisible send. Current main has not yet integrated that proof. The integration task is to bring only the row-owned NW-011 test deltas into main, or verify they are already present, without overwriting unrelated current-main changes.

User-visible behavior under proof: starting a group send while the route unmounts or the app backgrounds must leave a delivered message or a retryable sender-owned row; it must not silently discard composer/optimistic state while recipients may or may not receive an untracked message.

## current-main known state

Quick scout on 2026-05-20:

- Controlling integration breakdown lists `NW-011` / `INTEGRATE-NW-011` as `pending_integration`; `INTEGRATE-NW-010` is accepted and the program is stopped after NW-010 until explicitly resumed.
- `rg -n "NW-011"` across the five row-owned target test files in current main returned no matches.
- Targeted git status shows existing main modifications in:
  - `test/core/lifecycle/handle_app_resumed_group_recovery_test.dart`
  - `test/features/groups/application/send_group_message_use_case_test.dart`
  - `test/features/groups/integration/group_resume_recovery_test.dart`
- Do not overwrite those modified files. Inspect and merge only missing NW-011 hunks if execution proceeds.

## files and repos to inspect next

Allowed row-owned import/test files:

- `test/features/groups/presentation/screens/group_conversation_wired_bg_task_test.dart`
- `test/features/groups/application/send_group_message_use_case_test.dart`
- `test/core/lifecycle/handle_app_paused_group_test.dart`
- `test/core/lifecycle/handle_app_resumed_group_recovery_test.dart`
- `test/features/groups/integration/group_resume_recovery_test.dart`

Allowed current integration docs after successful execution, if the executor is granted doc ownership for closure:

- this integration plan file
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-breakdown.md`
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`

Read-only source evidence:

- source matrix, source breakdown, and source NW-011 plan listed above.

Do not edit production code, Go/native code, harness scripts, runner scripts, source worktree docs, source matrix, source breakdown, COMPLETE_1 docs, or adjacent row plans for this integration row.

## existing tests covering this area

Historical source closure says these exact selectors passed:

- `group_conversation_wired_bg_task_test.dart`: `NW-011 route unmount during group send leaves durable or retryable row, never hidden`
- `send_group_message_use_case_test.dart`: `NW-011 send pre-persist survives lifecycle cancellation window`
- `handle_app_paused_group_test.dart`: `NW-011 pause transitions in-flight group send to retryable failed without deleting custody`
- `handle_app_resumed_group_recovery_test.dart`: `NW-011 resume retries failed or pending background send after rejoin and drain`
- `group_resume_recovery_test.dart`: `NW-011 backgrounded sender send is delivered or remains retryable with no invisible send`

Current main quick scout found none of those anchors by `NW-011`, so treat the row as missing unless a fresh executor scout proves equivalent row-named coverage.

## regression/tests to add first

Do not design new regressions. This is integration mode.

First import or verify the five source-owned NW-011 selectors above. If a selector already exists under equivalent current-main wording, keep the current-main version only if it proves the same route-unmount, pre-persist, pause, resume-ordering, and fake-network outcomes with row-owned `NW-011` naming or an explicit mapping in this plan's execution notes.

## step-by-step implementation plan

1. Re-run a safe dirty-state check for the five allowed test files and this plan file. Preserve all unrelated edits.
2. Re-run the current-main `NW-011` selector search across the five allowed test files.
3. If all five source-equivalent selectors are already present, run the focused host selectors and classify as `skipped_already_present` or `accepted` with exact proof.
4. If some selectors are present and some are missing, inspect the current diffs in modified files before editing. Merge only missing NW-011 hunks from the source worktree; do not replace whole files.
5. If selectors are missing, import only the row-owned NW-011 test deltas from the source worktree into the five allowed test files.
6. Run the focused host selectors. If failures are caused by incomplete import or local test fixture drift, fix only the row-owned test import within the allowed files.
7. If a focused selector exposes a real production behavior gap in current main, stop and classify `blocked_conflict`; do not invent production, native, harness, or broader lifecycle fixes under this contract because source NW-011 closed without production changes.
8. Run scoped format/analyze and hygiene. Run broader named gates only as preservation/classification checks, recording any pre-existing residuals separately from NW-011.
9. After green focused evidence, update only the integration-owned closure docs permitted by the executor's prompt. Do not edit source docs.

## risks and edge cases

- The three already-modified current-main test files may contain newer unrelated row work; wholesale copy from source would overwrite others' changes.
- Current main after NW-010 has a different history than the source worktree; imported tests may need minimal fixture adaptation inside allowed test files.
- Source closure was test-only. Any production failure in main is an integration conflict, not permission to broaden this row.
- Broader `groups` or `completeness-check` residuals may pre-exist after NW-010; focused NW-011 failures are blockers, unrelated residuals are not.
- Route-unmount, pause, and resume tests must preserve retry material and same-message identity, not merely assert that a send future completes.

## exact tests and gates to run

Focused host selectors:

```bash
flutter test --no-pub test/features/groups/presentation/screens/group_conversation_wired_bg_task_test.dart --plain-name 'NW-011'
flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --plain-name 'NW-011'
flutter test --no-pub test/core/lifecycle/handle_app_paused_group_test.dart --plain-name 'NW-011'
flutter test --no-pub test/core/lifecycle/handle_app_resumed_group_recovery_test.dart --plain-name 'NW-011'
flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'NW-011'
```

Scoped maintenance:

```bash
dart format --set-exit-if-changed test/features/groups/presentation/screens/group_conversation_wired_bg_task_test.dart test/features/groups/application/send_group_message_use_case_test.dart test/core/lifecycle/handle_app_paused_group_test.dart test/core/lifecycle/handle_app_resumed_group_recovery_test.dart test/features/groups/integration/group_resume_recovery_test.dart
flutter analyze test/features/groups/presentation/screens/group_conversation_wired_bg_task_test.dart test/features/groups/application/send_group_message_use_case_test.dart test/core/lifecycle/handle_app_paused_group_test.dart test/core/lifecycle/handle_app_resumed_group_recovery_test.dart test/features/groups/integration/group_resume_recovery_test.dart
git diff --check
```

Preservation/classification gates:

```bash
FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups
./scripts/run_test_gates.sh completeness-check
```

Device profile: host-only. `3-Party E2E` is `N/A`; no iOS proof, physical device proof, Android proof, macOS app-peer proof, or live harness run is required or accepted as a substitute for the focused host selectors.

## known-failure interpretation

- A failure in any focused `NW-011` selector blocks acceptance unless it is proven to be a pre-existing harness/environment issue unrelated to the row and the row still has equivalent focused proof.
- Existing residual classifications through `INTEGRATE-NW-010` must remain preserved and must not be reassigned to NW-011 without direct row evidence.
- If `groups` or `completeness-check` is red only on known non-NW-011 residuals, record the exact residuals and continue only if all focused NW-011 selectors and scoped checks pass.
- If a modified current-main file has unrelated edits, merge around them. If the NW-011 source hunk cannot be merged without overwriting unrelated changes, stop as `blocked_conflict` and record the exact file/hunk.

## done criteria

- Current main has all five row-owned NW-011 selectors, or an explicit already-present mapping proving equivalent coverage.
- Focused NW-011 host selectors pass in the five allowed test files.
- Scoped format, scoped analyze, and `git diff --check` pass, or unchanged pre-existing analyzer issues are explicitly classified and not introduced by NW-011.
- Any broader gate residuals are classified as pre-existing/non-row or fixed only if they are directly caused by NW-011 test import.
- Integration ledger/test-inventory updates, if performed by the executor, record exact imported files, tests, proof commands, residuals, and terminal status.
- No source docs, source worktree plan, production code, native code, harness, runner scripts, or adjacent rows are edited.

## scope guard

Do not:

- import source docs or rewrite the original source implementation plan;
- copy whole files over current main files;
- revert, reset, or overwrite changes made by others;
- touch production code, Go/native code, live harness, scripts, relay architecture, notification, media, or UI behavior;
- add new NW-011 product behavior beyond importing/verifying the source row-owned tests;
- require iOS, Android, physical-device, or 3-party proof;
- close NW-012 or any adjacent row by implication.

## accepted differences / intentionally out of scope

- Source NW-011 production code stayed untouched; this integration contract preserves that as the expected import shape.
- Source `3-Party E2E` is `N/A`; host-only proof is sufficient.
- No Go/native proof is required or claimed.
- NW-010 background-resume delivery and NW-011 send-start durability are separate. NW-010 acceptance does not close NW-011.
- Media-send parity, restart survival, notification routing, stress/chaos, and long-offline convergence remain separate rows.

## dependency impact

Accepting `INTEGRATE-NW-011` gives later main integration rows a narrow sender-side guarantee: a started group send cannot vanish during route unmount or app backgrounding without delivery or retryable custody. If this row is blocked, later lifecycle/restart rows that depend on send-start durability should not cite NW-011 as integrated in main.

## reviewer pass

Sufficiency: sufficient with adjustments already incorporated.

Missing files/tests/gates: none structurally. The exact five source selectors, host-only device profile, scoped maintenance checks, and preservation gates are named.

Stale assumptions: current-main quick scout is lightweight and must be repeated by the executor before import because three target files are already modified.

Overengineering: none. The contract forbids production and harness work unless a separate controller grants new ownership.

Minimum needed: preserve current-main changes, import or verify only missing NW-011 selectors, run focused host proof, then update integration closure docs if allowed.

## arbiter decision

Final verdict: execution-ready for `INTEGRATE-NW-011` only.

Structural blockers remaining: none in the plan. Execution must stop as `blocked_conflict` if source NW-011 hunks cannot be merged without overwriting current-main edits or if focused selectors require production changes not present in the source row.

Incremental details intentionally deferred: exact hunk-level merge choices are deferred to the executor after a fresh dirty-state check.

Accepted differences intentionally left unchanged: no iOS proof, no Go/native proof, no production-code import, no adjacent-row closure.

Why safe to implement now: the source row is closed with concrete test-only evidence, the current integration row is pending, the allowed files and tests are exact, the device profile is host-only, and the conflict/stop rules prevent overwriting unrelated work.
