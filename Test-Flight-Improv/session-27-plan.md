# Session 27 Plan: Final Acceptance Audit For Group Discussion Reliability

## 1. real scope

Run the final acceptance/closure pass for the lean group-discussion reliability program defined in `18-group-discussion-reliability-audit.md`, but only after first proving that the Session 24 through 26 fixes are actually landed in the current repo.

This session is not another feature session. Its first job is to verify whether the three narrow reliability gaps targeted by Sessions 24 through 26 are actually landed in code + direct regressions + gate strategy. Only if that preflight passes should this session proceed to a final combined closure decision. Do not treat the session-plan docs themselves as execution proof; use current repo code, tests, and gate definitions as the authority.

Targeted gaps:
- Session 24: ordinary group media persists the parent `GroupMessage` row before upload starts
- Session 25: failed ordinary-media group messages retry successfully once persisted attachments are already complete
- Session 26: one group conversation screen cannot start overlapping local send pipelines

In scope:
- inspect the current repo code and tests for the Session 24 through 26 seams before assuming those sessions landed
- explicitly verify whether Session 25 and Session 26 are actually closed in the present repo
- run the combined direct suites needed to verify the three fixes together
- run the named gates required by the regression strategy
- interpret any red gate results against the known-failure ledger in `test-gate-definitions.md`
- decide whether the group reliability work is now:
  - accepted
  - accepted with explicit follow-up
  - or still blocked by a real remaining gap
- update the relevant docs if the acceptance result changes the closure state

Out of scope:
- new production features
- new architecture or transport changes
- reopening announcement auth scope
- adding more generic smoke tests just because this is a closure session
- broad cleanups unrelated to the three targeted reliability gaps
- using the session-plan files as the authoritative execution ledger

## 2. session classification

`evidence-gated`

Why:
- the preferred outcome is proof, not more production edits
- a valid completion is “the three group reliability gaps are now closed and documented”
- production changes should occur only if the audit exposes a real remaining blocker that must be fixed before acceptance
- a valid blocked completion is “Session 27 cannot run as final closure yet because one or more prerequisite fixes are not actually landed in the repo”

## 3. files and repos to inspect next

Primary planning / rationale docs:
- `Test-Flight-Improv/18-group-discussion-reliability-audit.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/17-roadmap-closure-audit.md`
- `Test-Flight-Improv/session-24-plan.md`
- `Test-Flight-Improv/session-25-plan.md`
- `Test-Flight-Improv/session-26-plan.md`

Primary code likely affected by Sessions 24 through 26:
- `lib/features/groups/presentation/screens/group_conversation_wired.dart`
- `lib/features/groups/presentation/screens/group_conversation_screen.dart`
- `lib/features/groups/application/retry_failed_group_messages_use_case.dart`
- `lib/features/groups/application/retry_incomplete_group_uploads_use_case.dart`
- `lib/features/groups/application/send_group_message_use_case.dart`
- `lib/main.dart` for the Session 25 resume wiring seam that threads `mediaAttachmentRepository` into failed group retry on app resume
- `lib/features/conversation/presentation/widgets/compose_area.dart` only if Session 26 touched the shared compose seam
- `lib/features/conversation/presentation/screens/conversation_wired.dart` as the existing 1:1 reference for explicit local send serialization
- `lib/features/conversation/presentation/screens/conversation_screen.dart` as the existing 1:1 reference for `isSending` wiring

Primary tests:
- `test/features/groups/presentation/group_conversation_wired_test.dart`
- `test/features/groups/presentation/group_conversation_screen_test.dart`
- `test/features/groups/presentation/screens/group_conversation_wired_bg_task_test.dart`
- `test/features/groups/application/retry_failed_group_messages_use_case_test.dart`
- `test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart`
- `test/features/groups/application/send_group_message_use_case_test.dart`
- `test/core/lifecycle/main_resume_group_upload_wiring_test.dart`
- `test/features/groups/integration/group_edge_cases_smoke_test.dart`
- `test/features/groups/integration/group_resume_recovery_test.dart`
- `test/features/conversation/presentation/widgets/compose_area_test.dart` only if Session 26 touched the shared widget

Gate / regression references:
- `./scripts/run_test_gates.sh groups`
- `./scripts/run_test_gates.sh baseline`
- `./scripts/run_test_gates.sh transport` only if any of Sessions 24 through 26 touched lifecycle / startup / recovery wiring

Execution note:
- `Test-Flight-Improv/test-gate-definitions.md` is the execution source of truth for named gates and known failures.
- `Test-Flight-Improv/14-regression-test-strategy.md` is the policy/rationale reference for how to interpret direct suites vs named gates.
- `Test-Flight-Improv/test-gates-reference.md` is not required for Session 27.
- `Test-Flight-Improv/17-roadmap-closure-audit.md` explicitly says the `session-*-plan.md` files are planning artifacts, not authoritative execution ledgers.

## 4. existing tests covering this area

Already present and relevant:
- `test/features/groups/presentation/group_conversation_wired_test.dart`
  - primary orchestration proof for ordinary media durability and local send behavior
- `test/features/groups/presentation/group_conversation_screen_test.dart`
  - screen-level composer wiring checks, but current repo evidence must confirm whether it actually covers explicit sending state
- `test/features/groups/presentation/screens/group_conversation_wired_bg_task_test.dart`
  - background-task / lock-unmount protection evidence for send paths
- `test/features/groups/application/retry_failed_group_messages_use_case_test.dart`
  - current proof for failed text retry behavior plus ordinary-media retry parity; voice publish-failure retry remains an explicit residual outside Session 27 acceptance
- `test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart`
  - lower-layer proof for unfinished upload recovery and parent-row dependency
- `test/features/groups/application/send_group_message_use_case_test.dart`
  - nearby safety net for the core send contract
- `test/core/lifecycle/main_resume_group_upload_wiring_test.dart`
  - direct proof that the Session 25 resume seam still threads `mediaAttachmentRepository` into failed group retry from `lib/main.dart`
- `test/features/groups/integration/group_edge_cases_smoke_test.dart`
  - integration-level edge-case pressure, but not by itself proof of concurrent local send serialization if the burst case is still sequential
- `test/features/groups/integration/group_resume_recovery_test.dart`
  - integration-level recovery safety net
- `test/features/conversation/presentation/widgets/compose_area_test.dart`
  - shared widget proof if the group send-sequencing change reused the existing `isSending` seam

What this session must prove:
- Session 24’s durability fix did not regress media send behavior
- Session 25’s retry-parity fix is actually landed in current production code and direct regressions, rather than still being deferred or skipped
- Session 25’s retry-parity fix did not collapse the ownership split between failed-send retry and incomplete-upload retry
- Session 26’s sequential-send fix is actually landed in current production code and direct regressions, rather than still being absent from the group send path
- Session 26’s sequential-send fix did not break media, voice, or background-task behavior
- together, those three changes are enough to close the lean reliability program without new architecture

Current repo risk to validate first:
- Session 24 appears likely landed, but Session 27 must still re-check the direct evidence
- Session 25 may still be absent if `retry_failed_group_messages_use_case.dart` still skips rows carrying ordinary-media retry metadata or if the resume wiring seam is missing
- Session 26 may still be absent if the group conversation path still lacks an explicit `_isSending`/reentry guard and does not wire `isSending` into `ComposeArea`

## 5. regression/tests to add first, if any

None by default.

This is an acceptance session, not a feature session.

Add a new regression only if the audit finds a real remaining uncovered gap that prevents acceptance. If that happens:
- add the smallest deterministic regression first
- keep it local to the uncovered behavior
- do not widen the named gate lists unless the current gate model is actually insufficient

Acceptance-session exception:
- if the preflight shows Session 25 or Session 26 never actually landed, do not add fresh regressions inside Session 27 just to rescue the closure pass
- instead, record the smallest missing prerequisite gap, mark Session 27 blocked, and hand the work back to the missing implementation session

## 6. evidence to capture first, if the session is profile-gated or evidence-gated

Required.

Before deciding the session is accepted, gather:
- a preflight verdict for each prerequisite:
  - Session 24 landed or not landed
  - Session 25 landed or not landed
  - Session 26 landed or not landed
- the final direct test results for the three reliability areas
- the direct result for the Session 25 resume wiring proof in `test/core/lifecycle/main_resume_group_upload_wiring_test.dart`
- the final `groups` gate result
- the final `baseline` gate result
- the `transport` gate result if any of Sessions 24 through 26 touched that layer
- a short file-level check of the landed implementation seams from Sessions 24 through 26
- explicit confirmation that the Session 25 resume wiring seam in `lib/main.dart` is still present
- a comparison of those results against the expected closure criteria in `18-group-discussion-reliability-audit.md`
- revalidation of any known-failure ledger note used to downgrade a red named gate result

## 7. step-by-step implementation or evidence-collection plan

1. Re-open `18-group-discussion-reliability-audit.md` and restate the three targeted gaps as the acceptance contract for this session.
2. Re-open the current repo code from Sessions 24 through 26 and confirm the actual implementation seams before assuming anything landed.
   - do not start by editing code
   - first confirm what actually changed
   - use `conversation_wired.dart` / `conversation_screen.dart` as the reference path for what explicit send serialization should look like
3. Run a prerequisite preflight before any closure decision:
   - if Session 24 ordinary-media parent-row durability is not actually present in code + direct tests, record that as a blocker and stop the acceptance pass
   - if Session 25 ordinary-media failed-send retry parity is not actually present in code + direct tests, record that as a blocker and stop the acceptance pass
   - if Session 26 sequential-send behavior is not actually present in code + direct tests, record that as a blocker and stop the acceptance pass
   - only continue to the full closure audit if all three prerequisites are truly landed
4. Run the combined direct suites that cover:
   - ordinary media parent-row durability
   - failed-send ordinary-media retry parity
   - the Session 25 resume wiring seam
   - explicit sequential send behavior
5. Run the Group Messaging Gate.
6. Run the Baseline Gate.
7. Run the Startup / Transport Gate only if the changed code from Sessions 24 through 26 actually crossed into lifecycle / startup / recovery wiring.
8. Interpret all red results against the known-failure ledger in `Test-Flight-Improv/test-gate-definitions.md`.
   - do not treat an already-documented unrelated red gate item as a new group-reliability failure
   - do not trust an old ledger note without checking that the cited file/line/failure still matches current repo state
9. Decide the outcome:
   - `accepted` if the three gaps are closed and only unrelated known failures remain
   - `accepted_with_explicit_follow_up` if the reliability work is effectively complete but one external or pre-existing unrelated issue still clouds the gate surface after revalidation
   - `blocked` if a real group-reliability gap remains in the changed scope
   - `blocked` if Session 25 or Session 26 turns out not to be landed yet in the present repo
10. If accepted, update the docs:
   - mark the group-discussion reliability work as closed or materially closed in `18-group-discussion-reliability-audit.md`
   - update `00-INDEX.md` only if its closure summary needs to reflect the final state more precisely
11. If blocked, record the smallest remaining gap and stop. Do not create new unrelated implementation work in this session.

## 8. risks and edge cases

- Do not turn this acceptance pass into another implementation session unless a real remaining blocker is proven.
- Do not misclassify pre-existing known-red gate items as failures of Sessions 24 through 26.
- Do not misclassify stale or incorrectly documented ledger notes as trustworthy evidence without revalidation.
- Do not reopen product-scope items such as receipts/search/typing just because the core reliability work is done.
- Do not require the `transport` gate unless the actual changed files crossed into that layer.
- Do not hide a real remaining gap behind “known failure” language if the changed scope clearly caused or widened it.
- Do not widen the gate model during acceptance unless the audit proves the current gates are insufficient to protect the fixed behavior.
- Do not let Session 24 evidence mask the possibility that Session 25 or Session 26 is still missing in current production code.
- Do not use `group_edge_cases_smoke_test.dart` as concurrency proof unless its relevant case actually exercises overlapping local sends rather than sequential await.

## 9. exact tests to run for this evidence-gated acceptance audit

These reruns are required evidence for Session 27 even if this session lands no
new production code.

Primary direct suites:
- `flutter test test/features/groups/presentation/group_conversation_wired_test.dart`
- `flutter test test/features/groups/presentation/screens/group_conversation_wired_bg_task_test.dart`
- `flutter test test/features/groups/application/retry_failed_group_messages_use_case_test.dart`
- `flutter test test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart`

Direct companion suites:
- `flutter test test/features/groups/presentation/group_conversation_screen_test.dart`
- `flutter test test/features/groups/application/send_group_message_use_case_test.dart`
- `flutter test test/core/lifecycle/main_resume_group_upload_wiring_test.dart`

Conditional shared-widget suite only if Session 26 touched the shared compose widget:
- `flutter test test/features/conversation/presentation/widgets/compose_area_test.dart`

Integration safety nets:
- `flutter test test/features/groups/integration/group_edge_cases_smoke_test.dart`
- `flutter test test/features/groups/integration/group_resume_recovery_test.dart`

Prerequisite interpretation note:
- if the direct suites show Session 24 still lacks the parent-row durability contract, Session 27 must stop as blocked
- if the direct suites show Session 25 still only supports text-only failed-send retry, Session 27 must stop as blocked
- if the direct suites show Session 26 still lacks explicit local send serialization in the group path, Session 27 must stop as blocked

## 10. subsystem gate(s), if relevant

Required:
- Group Messaging Gate
  - `./scripts/run_test_gates.sh groups`

Conditionally required:
- Startup / Transport Gate
  - only if Sessions 24 through 26 changed lifecycle, lock-unlock, startup, or recovery orchestration

Preflight note:
- do not spend time on closure-only gate interpretation if the prerequisite preflight already proved Session 25 or Session 26 is not landed

## 11. whether Baseline Gate is required

Yes.

This is a final acceptance pass over production changes in the group messaging surface.

Command:
- `./scripts/run_test_gates.sh baseline`

Interpretation note:
- evaluate any red result against the known-failure ledger in `Test-Flight-Improv/test-gate-definitions.md`
- only treat it as a group-reliability blocker if the changed scope clearly introduced or widened the failure
- do not require unconditional green while unrelated documented known failures remain unchanged
- revalidate the cited known-failure explanation against the current repo before accepting it as unrelated

## 12. whether Startup / Transport Gate is required

Only if the actual landed scope from Sessions 24 through 26 crossed into:
- lifecycle / pause-resume wiring
- startup / recovery orchestration
- background-task ordering around send completion
- device-backed recovery behavior beyond local screen/state management

Current expected answer:
- yes, because Session 25’s accepted scope includes the `lib/main.dart` resume wiring seam for failed group retry parity
- still re-check that this seam remains landed before treating `transport` as required evidence rather than stale plan text

Command when needed:
- `./scripts/run_test_gates.sh transport`

Interpretation note:
- if `transport` is run, use the same known-failure rule from `Test-Flight-Improv/test-gate-definitions.md`
- do not reopen unrelated existing transport-gate failures as part of Session 27 unless the changed reliability work clearly affects them
- revalidate any documented transport known failure against current code before downgrading it

## 13. done criteria

Session 27 is done when all of the following are true:
- a prerequisite preflight confirmed that Sessions 24 through 26 are actually landed in the current repo
- the final direct suites for Sessions 24 through 26 have been run
- the Group Messaging Gate has been run
- the Baseline Gate has been run
- the Startup / Transport Gate has been run only if the changed scope actually requires it
- gate results have been interpreted correctly against the known-failure ledger
- one final acceptance decision is recorded:
  - `accepted`
  - `accepted_with_explicit_follow_up`
- or `blocked`
- if accepted, the docs are updated to reflect the new closure state of the group-discussion reliability work
- no unrelated implementation work was bundled into the acceptance session
- if blocked because a prerequisite fix is not actually landed, that gap is recorded explicitly instead of being hidden inside gate-noise interpretation

## 14. dependency impact on later sessions if this session blocks

If Session 27 blocks:
- the group-discussion reliability program is not actually finished
- the most likely block classes are:
  - Session 24 ordinary-media parent-row durability is still not landed
  - Session 25 ordinary-media failed-send retry parity or its resume wiring seam is still not landed
  - Session 26 explicit local send serialization is still not landed
- future group cleanup/closure work should pause until the smallest remaining blocker is explicitly defined
- do not create broad new roadmap work; create only the smallest follow-up session needed to close the proven remaining gap
