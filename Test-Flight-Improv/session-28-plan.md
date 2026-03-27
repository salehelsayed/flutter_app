# Session 28 Plan: Final Acceptance Audit For Announcement Reliability And Enforcement

## 1. real scope

Run a compact acceptance/closure pass for announcements after the shared group reliability work.

This session is not a duplicate of the group-discussion reliability program. Announcements already ride the same core group send/retry/recovery paths, and `13-announcement-use-case-audit.md` shows that the remaining work is much narrower: confirm that the shared reliability fixes did not regress announcement-specific guarantees and that admin-only enforcement still holds cleanly.

Announcement-specific acceptance contract:
- admin-only sending still holds at UI and use-case boundaries
- admin text/media/voice announcement sends still behave correctly on the shared group pipeline
- reader/member announcement receive + react behavior still works
- announcement resume/recovery behavior still works for text/media, and voice where the repo already carries direct proof
- announcement lock/unmount / background-task behavior still works

In scope:
- first prove the shared group reliability baseline is still landed enough to audit announcements safely
- inspect the landed shared group reliability changes as they affect announcements
- run the announcement-focused direct suites and relevant shared group safety nets
- run the named gates required by the regression strategy
- optionally rerun repo-local Go-side enforcement proof if the changed scope touched auth or publish-boundary behavior
- decide whether announcement behavior is:
  - accepted
  - accepted_with_explicit_follow_up
  - or blocked by a real announcement-specific gap
- update docs only if the acceptance result materially changes the announcement closure state

Out of scope:
- a new announcement feature roadmap
- scheduled announcements, read receipts, analytics, pinning, or other product-scope expansion
- broad transport or discovery work
- rebuilding the group reliability program specifically for announcements
- new bridge-package proof work unless the shared changes actually touched the Go/bridge auth boundary

## 2. session classification

`evidence-gated`

Why:
- the preferred outcome is proof that announcements remain solid after the shared group changes
- a valid completion is “announcement behavior remains accepted; no further implementation session is needed”
- production changes should happen only if this audit proves a real announcement-specific gap
- a valid blocked completion is “the shared group reliability baseline is not currently coherent enough to use as announcement acceptance evidence”

## 3. files and repos to inspect next

Primary planning / rationale docs:
- `Test-Flight-Improv/13-announcement-use-case-audit.md`
- `Test-Flight-Improv/09-network-group-messaging.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/session-27-plan.md`

Primary Flutter code likely relevant:
- `lib/features/groups/application/send_group_message_use_case.dart`
- `lib/features/groups/presentation/screens/group_conversation_wired.dart`
- `lib/features/groups/presentation/screens/group_conversation_screen.dart`
- `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`
- `lib/features/groups/application/retry_failed_group_messages_use_case.dart`
- `lib/features/groups/application/retry_incomplete_group_uploads_use_case.dart`
- `lib/features/groups/application/rejoin_group_topics_use_case.dart`
- `lib/features/groups/application/retry_failed_group_inbox_stores_use_case.dart` if inbox-store recovery is part of the shared scope under audit
- `lib/core/lifecycle/handle_app_resumed.dart`
- `lib/main.dart`
- any shared group retry/recovery files changed by Sessions 24 through 27

Primary Go/bridge code only if the shared work touched auth or publish-boundary behavior:
- `go-mknoon/node/pubsub.go`
- `go-mknoon/bridge/bridge.go`

Primary tests:
- `test/features/groups/integration/announcement_happy_path_test.dart`
- `test/features/groups/application/send_group_message_use_case_test.dart`
- `test/features/groups/application/send_group_reaction_use_case_test.dart`
- `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`
- `test/features/groups/application/rejoin_group_topics_use_case_test.dart`
- `test/features/groups/application/retry_failed_group_messages_use_case_test.dart`
- `test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart`
- `test/features/groups/integration/group_resume_recovery_test.dart`
- `test/features/groups/presentation/screens/group_conversation_wired_bg_task_test.dart`
- `test/features/groups/presentation/group_conversation_wired_test.dart`
- `test/features/groups/presentation/group_conversation_screen_test.dart`
- `test/core/lifecycle/handle_app_resumed_group_recovery_test.dart`
- `test/core/lifecycle/main_resume_group_upload_wiring_test.dart`

Gate / regression references:
- `./scripts/run_test_gates.sh groups`
- `./scripts/run_test_gates.sh baseline`
- `./scripts/run_test_gates.sh transport` only if the changed shared scope crossed into lifecycle / startup / recovery wiring
- `go test ./node && go test ./bridge` only if the changed scope touched Go/bridge announcement auth or publish-boundary behavior

Execution note:
- `Test-Flight-Improv/test-gate-definitions.md` is the execution source of truth for named gates and known failures.
- `Test-Flight-Improv/14-regression-test-strategy.md` is the policy/rationale reference for direct suites vs named gates.
- `Test-Flight-Improv/test-gates-reference.md` is not required for Session 28.

## 4. existing tests covering this area

Already present and relevant:
- `test/features/groups/integration/announcement_happy_path_test.dart`
  - compact create -> send -> read-only receive -> react coverage
- `test/features/groups/application/send_group_message_use_case_test.dart`
  - announcement admin send behavior
  - voice-only announcement send
  - successNoPeers / pending semantics
  - key-rotation delivery behavior
  - non-admin unauthorized rejection before network send
- `test/features/groups/integration/group_resume_recovery_test.dart`
  - announcement reader resume behavior
  - announcement media recovery with zero topic peers
  - announcement voice sender-path / push-body / resume proof already exists in repo-local acceptance coverage
  - announcement delivery after key rotation
- `test/features/groups/presentation/screens/group_conversation_wired_bg_task_test.dart`
  - announcement text/voice/media send path behavior through lock / unmount / background-task conditions
- `test/features/groups/presentation/group_conversation_wired_test.dart`
  - non-admin announcement write lockout
  - no hidden voice callbacks for non-admin readers
  - announcement admin voice UI availability
- `test/features/groups/presentation/group_conversation_screen_test.dart`
  - read-only compose behavior for announcement readers
- `test/features/groups/application/send_group_reaction_use_case_test.dart`
  - explicit reader/member reaction proof at the use-case boundary
- `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`
  - exact-once announcement reader inbox drain proof
- `test/features/groups/application/rejoin_group_topics_use_case_test.dart`
  - announcement groups rejoin on recovery/startup like normal groups
- `test/core/lifecycle/handle_app_resumed_group_recovery_test.dart`
  - resume ordering proof for rejoin -> drain -> recover -> retry chain
- `test/core/lifecycle/main_resume_group_upload_wiring_test.dart`
  - repo-local proof that resume wiring still passes the needed group upload dependencies

What this session must prove:
- the shared group reliability baseline is actually coherent enough to use as acceptance evidence for announcements
- shared group reliability fixes did not break announcement-specific send/retry/recovery behavior
- admin-only enforcement still holds
- announcement readers still stay read-only while receiving and reacting correctly
- no announcement-specific follow-on implementation program is needed unless a real gap is proven

## 5. regression/tests to add first, if any

None by default.

This is an acceptance session, not another implementation session.

Add a new regression only if the audit proves a real announcement-specific uncovered gap. If that happens:
- add the smallest deterministic regression first
- keep it local to the uncovered announcement behavior
- do not widen the named gate lists unless the current gate model is truly insufficient

## 6. evidence to capture first, if the session is profile-gated or evidence-gated

Required.

Before deciding the session is accepted, gather:
- a prerequisite preflight verdict on whether the shared group reliability seams are currently landed, compiling, and usable as acceptance evidence
- final direct test results for announcement happy-path, send auth, resume/media recovery, and background-task protection
- final direct test results for the announcement-relevant shared recovery seams:
  - inbox drain
  - rejoin
  - retry-incomplete-group-uploads
  - retry-failed-group-messages
  - resume ordering / main wiring
- the final `groups` gate result
- the final `baseline` gate result
- the `transport` gate result only if the changed shared scope actually touched that layer
- the Go-side `go test ./node && go test ./bridge` result only if the changed scope actually touched the Go/bridge auth boundary
- a short comparison of those results against the acceptance contract in `13-announcement-use-case-audit.md`
- explicit revalidation of any known-failure-ledger note used to downgrade a red named-gate result

## 7. step-by-step implementation or evidence-collection plan

1. Re-open `13-announcement-use-case-audit.md` and restate the narrow acceptance contract for announcements.
   - treat its gap list as historical context only
   - do not assume every listed “gap” is still current without repo verification
2. Re-open the shared group changes from Sessions 24 through 27 and identify whether any of them touched announcement-relevant seams.
   - do not start by editing code
   - first confirm whether the shared changes actually touch announcement behavior
3. Run a prerequisite preflight before any acceptance decision:
   - confirm the shared group reliability seams that announcements rely on are still landed, compiling, and coherent in the current repo
   - include the retry, upload-recovery, inbox-drain, rejoin, and resume-wiring seams
   - if that preflight fails, record Session 28 as `blocked` and stop rather than treating announcement-only suites as sufficient proof
4. Run the announcement-focused direct suites:
   - happy path
   - send auth / pending / key-rotation cases
   - react behavior at the direct use-case boundary
   - resume/media recovery cases
   - announcement-relevant lifecycle / resume-ordering proofs
   - announcement-relevant inbox-drain / rejoin / lifecycle ordering cases
   - background-task / lock-unmount cases
   - read-only UI enforcement checks
5. Run the Group Messaging Gate.
6. Run the Baseline Gate.
7. Run the Startup / Transport Gate only if the changed shared scope actually touched lifecycle / startup / recovery wiring.
   - do not treat the transport gate as a substitute for the repo-local lifecycle direct suites above
8. Run `go test ./node && go test ./bridge` only if the changed scope touched Go/bridge auth or publish-boundary behavior.
9. Interpret all red results against the known-failure ledger in `Test-Flight-Improv/test-gate-definitions.md`.
   - do not treat an already-documented unrelated red gate item as a new announcement failure
   - do not rely on an old ledger note without checking that the cited failure still matches the current repo state
10. Decide the outcome:
   - `accepted` if announcement behavior is still solid and only unrelated known failures remain
   - `accepted_with_explicit_follow_up` if the announcement surface is effectively complete but one unrelated pre-existing issue still clouds the gate surface
   - `blocked` if the shared group reliability prerequisite preflight is not currently coherent enough to support announcement acceptance
   - `blocked` only if a real announcement-specific gap remains in the changed scope
11. If accepted, update docs only if the closure wording should be tightened.
12. If blocked, record the smallest remaining announcement-specific gap or prerequisite shared-gap and stop. Do not create a broad new announcement roadmap in this session.

## 8. risks and edge cases

- Do not turn this acceptance pass into another implementation roadmap unless a real announcement-specific blocker is proven.
- Do not misclassify pre-existing known-red gate items as announcement failures.
- Do not treat the shared group pipeline as a black box; announcement resume/recovery evidence must include the actual lifecycle and wiring seams currently used by the app.
- Do not reopen product-scope items such as scheduling, receipts, analytics, or pinning just because this is an announcement session.
- Do not require Go-side tests unless the changed scope actually touched the Go/bridge auth boundary.
- Do not hide a real announcement-specific regression behind “shared known failure” language if the changed scope clearly caused or widened it.
- Do not create duplicate proof for node/bridge enforcement unless the current proof is actually no longer sufficient.
- Do not accept announcement closure if the prerequisite shared group retry/recovery surface is not currently compiling or coherent in the repo.
- Do not assume the `13-announcement-use-case-audit.md` gap list is still current; some entries may now be stale.

## 9. exact tests to run for this evidence-gated acceptance audit

Primary direct suites:
- `flutter test test/features/groups/integration/announcement_happy_path_test.dart`
- `flutter test test/features/groups/application/send_group_message_use_case_test.dart`
- `flutter test test/features/groups/application/send_group_reaction_use_case_test.dart`
- `flutter test test/features/groups/integration/group_resume_recovery_test.dart`

Direct companion suites:
- `flutter test test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`
- `flutter test test/features/groups/application/rejoin_group_topics_use_case_test.dart`
- `flutter test test/features/groups/application/retry_failed_group_messages_use_case_test.dart`
- `flutter test test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart`
- `flutter test test/core/lifecycle/handle_app_resumed_group_recovery_test.dart`
- `flutter test test/core/lifecycle/main_resume_group_upload_wiring_test.dart`
- `flutter test test/features/groups/presentation/screens/group_conversation_wired_bg_task_test.dart`
- `flutter test test/features/groups/presentation/group_conversation_wired_test.dart`
- `flutter test test/features/groups/presentation/group_conversation_screen_test.dart`

Conditional Go/bridge verification only if the changed scope touched that boundary:
- `cd go-mknoon && go test ./node && go test ./bridge`

## 10. subsystem gate(s), if relevant

Required:
- Group Messaging Gate
  - `./scripts/run_test_gates.sh groups`

Conditionally required:
- Startup / Transport Gate
  - only if the changed shared scope crossed into lifecycle, lock-unlock, startup, or recovery orchestration
  - this gate does not replace the direct `test/core/lifecycle/*.dart` suites required for the actual touched resume/wiring code

## 11. whether Baseline Gate is required

Yes.

This is a final acceptance pass over announcement behavior inside the shared group messaging surface.

Command:
- `./scripts/run_test_gates.sh baseline`

Interpretation note:
- evaluate any red result against the known-failure ledger in `Test-Flight-Improv/test-gate-definitions.md`
- only treat it as an announcement blocker if the changed scope clearly introduced or widened the failure
- do not require unconditional green while unrelated documented known failures remain unchanged
- do not downgrade a red baseline result without revalidating that the cited known-failure note still matches the current repo

## 12. whether Startup / Transport Gate is required

Only if the actual changed shared scope crossed into:
- lifecycle / pause-resume wiring
- startup / recovery orchestration
- background-task ordering around send completion
- device-backed recovery behavior beyond local announcement send/read-only handling

Command when needed:
- `./scripts/run_test_gates.sh transport`

Interpretation note:
- if `transport` is run, use the same known-failure rule from `Test-Flight-Improv/test-gate-definitions.md`
- do not reopen unrelated existing transport-gate failures as part of Session 28 unless the changed announcement-related scope clearly affects them
- do not use `transport` as the only proof for resume/recovery when repo-local lifecycle direct suites cover the touched seams more directly

## 13. done criteria

Session 28 is done when all of the following are true:
- the prerequisite shared-group preflight has been run and is coherent enough to support announcement acceptance
- the final announcement-focused direct suites have been run
- the final announcement-relevant shared recovery direct suites have been run
- the Group Messaging Gate has been run
- the Baseline Gate has been run
- the Startup / Transport Gate has been run only if the changed scope actually requires it
- the Go-side auth proof has been rerun only if the changed scope actually touched that boundary
- gate/test results have been interpreted correctly against the known-failure ledger
- one final acceptance decision is recorded:
  - `accepted`
  - `accepted_with_explicit_follow_up`
  - or `blocked`
- if accepted, docs are updated only if the announcement closure state needs refinement
- no unrelated announcement feature work was bundled into this acceptance session

## 14. dependency impact on later sessions if this session blocks

If Session 28 blocks:
- the shared group reliability baseline may still need closure before announcement acceptance can be trusted
- announcement behavior is not actually finished after the shared group reliability work
- future closure work should pause until the smallest remaining announcement-specific blocker is explicitly defined
- do not create a broad announcement program; create only the smallest follow-up session needed to close the proven remaining gap
