  - [14-regression-test-strategy.md](/Users/I560101/Project-Sat/mknoon-2/flutter_app/Test-Flight-Improv/14-
  regression-test-strategy.md)
  - [test-gate-definitions.md](/Users/I560101/Project-Sat/mknoon-2/flutter_app/Test-Flight-Improv/test-gate-
  definitions.md)
  - [18-group-discussion-reliability-audit.md](/Users/I560101/Project-Sat/mknoon-2/flutter_app/Test-Flight-
  Improv/18-group-discussion-reliability-audit.md)
  - [13-announcement-use-case-audit.md](/Users/I560101/Project-Sat/mknoon-2/flutter_app/Test-Flight-Improv/13-
  announcement-use-case-audit.md)
  - [10-network-measurement-strategy.md](/Users/I560101/Project-Sat/mknoon-2/flutter_app/Test-Flight-Improv/10-
  network-measurement-strategy.md)
  - [00-INDEX.md](/Users/I560101/Project-Sat/mknoon-2/flutter_app/Test-Flight-Improv/00-INDEX.md)

  Use these skills where relevant:
  - `libp2p-phase-orchestrator` as the main controller
  - `flutter-test-orchestrator` for regression/test planning, gate selection, and QA
  - `mobile-network-resilience-qa` only when the active session touches lifecycle, pause/resume, startup,
  transport, recovery, or device/simulator resilience validation
  - `flutter-sqlite-migrations-and-repositories` only when the active session changes repository persistence
  contracts, DB helpers, or durable row/attachment persistence
  - `flutter-ui-performance-profiler` only if Session 29 unexpectedly requires real profiling evidence beyond
  local timing/event instrumentation

  Work through Sessions 24 through 29 in strict order.

  Use these session-plan files as the active session contracts:
  - `Test-Flight-Improv/session-24-plan.md`
  - `Test-Flight-Improv/session-25-plan.md`
  - `Test-Flight-Improv/session-26-plan.md`
  - `Test-Flight-Improv/session-27-plan.md`
  - `Test-Flight-Improv/session-28-plan.md`
  - `Test-Flight-Improv/session-29-plan.md`

  Global sequencing rule:
  - No agents may run in parallel.
  - Every phase must fully finish before the next phase starts.
  - Within a phase, each agent must fully finish before the next agent starts.
  - Do not start Session N+1 until Session N has reached one of:
    - `accepted`
    - `accepted_with_explicit_follow_up`
    - `blocked`
    - `skipped_due_to_dependency`

  Global blocker policy:
  - Distinguish these outcomes:
    - `hard blocker`
    - `stale/already-covered`
    - `prerequisite-blocked`
  - There is no expected cross-tree or external-handoff work in Sessions 24 through 29.
  - Do not invent external dependency blockers unless the repo evidence genuinely forces one.
  - A `hard blocker` means the session cannot be completed safely with repo-local work.
  - A `prerequisite-blocked` session means a required earlier session result is missing or not actually landed in
  the repo.
  - If a session is `blocked` or `prerequisite-blocked`, do not automatically stop the whole workflow.
  - First determine whether later sessions explicitly depend on that blocker.
  - Continue with later sessions that are independent.
  - Mark later dependent sessions as `skipped_due_to_dependency`.

  Global convergence rule:
  - Do not stop a session just because the first review or QA pass says `insufficient`.
  - Patch and retry the current session until it becomes:
    - `sufficient`
    - or `sufficient with explicit follow-up`
    - or `accepted_with_explicit_follow_up`
  - Mark a session `blocked` only if the same structural blockers repeat without meaningful reduction across 2
  consecutive fix rounds.
  - Do not loop forever over incremental details.

  For each session N in {24, 25, 26, 27, 28, 29}, use:
  - active session contract: `Test-Flight-Improv/session-N-plan.md`
  - governing docs by session:
    - Session 24: `18-group-discussion-reliability-audit.md`, `14-regression-test-strategy.md`, `test-gate-
  definitions.md`
    - Session 25: `18-group-discussion-reliability-audit.md`, `14-regression-test-strategy.md`, `test-gate-
  definitions.md`
    - Session 26: `18-group-discussion-reliability-audit.md`, `14-regression-test-strategy.md`, `test-gate-
  definitions.md`
    - Session 27: `18-group-discussion-reliability-audit.md`, `17-roadmap-closure-audit.md`, `14-regression-test-
  strategy.md`, `test-gate-definitions.md`
    - Session 28: `13-announcement-use-case-audit.md`, `09-network-group-messaging.md`, `14-regression-test-
  strategy.md`, `test-gate-definitions.md`
    - Session 29: `10-network-measurement-strategy.md`, `14-regression-test-strategy.md`, `test-gate-
  definitions.md`, plus `18-group-discussion-reliability-audit.md` and `13-announcement-use-case-audit.md` for
  messaging scope context

  ==================================================
  PHASE 0. CLASSIFY SESSION N
  ==================================================

  Before planning or execution, classify Session N as one of:
  - `implementation-ready`
  - `evidence-gated`
  - `stale`
  - `prerequisite-blocked`

  Classification rules:
  - `implementation-ready`: the repo gap is concrete and code changes should be made after the required
  regression/test is added first
  - `evidence-gated`: the session is an acceptance/closure/audit session where a valid outcome is “already
  sufficient, document it”
  - `stale`: the repo already covers the gap strongly enough and the session only needs doc closure
  - `prerequisite-blocked`: a required earlier session result is not actually landed in the repo

  Session-specific expectations:
  - Session 24: `implementation-ready`
  - Session 25: `implementation-ready`
  - Session 26: `implementation-ready`
  - Session 27: `evidence-gated`
  - Session 28: `evidence-gated`
  - Session 29: `implementation-ready`

  If Session N is `stale`:
  - update the session plan and any affected docs
  - document why the gap is already covered
  - mark the session `accepted`
  - continue

  If Session N is `prerequisite-blocked`:
  - record the missing prerequisite explicitly
  - mark Session N `blocked`
  - continue only with later sessions that do not depend on that prerequisite

  ==================================================
  PHASE A. PLAN SESSION N
  ==================================================

  Use 3 agents in strict sequence:
  1. Planner
  2. Reviewer
  3. Arbiter

  Do not implement app code in this phase.

  Planner:
  - read `Test-Flight-Improv/session-N-plan.md`
  - read the governing docs for Session N
  - inspect the listed code-entry files and direct-test files before patching the plan
  - create or update `Test-Flight-Improv/session-N-plan.md` only if it is stale, missing concrete repo evidence,
  or needs a tighter test contract
  - produce a detailed Session N plan with:
    1. real scope
    2. session classification
    3. files and repos to inspect next
    4. existing tests covering this area
    5. regression/tests to add first, if any
    6. evidence to capture first, if the session is evidence-gated
    7. step-by-step implementation or evidence-collection plan
    8. risks and edge cases
    9. exact tests to run after implementation, if code changes occur
    10. subsystem gate(s), if relevant
    11. whether Baseline Gate is required
    12. whether Transport Gate is required
    13. done criteria
    14. dependency impact on later sessions if this session blocks

  Planner rules:
  - Sessions 24, 25, 26, and 29 must add the required regression or direct proof first if the plan says the
  session is a risky shared-path change
  - Sessions 27 and 28 are acceptance/audit sessions, not default implementation sessions
  - Do not broaden Sessions 24 to 26 into product features, status redesign, receipt protocols, or large
  architecture work
  - Do not broaden Session 28 into new announcement feature work unless the audit proves a real announcement-
  specific regression
  - Keep Session 29 local and lean:
    - use existing `emitFlowEvent(...)` style instrumentation
    - do not create a new observability subsystem
    - do not broaden into exporter/dashboard work

  Reviewer:
  - only after Planner fully finishes
  - do a strict sufficiency review of `session-N-plan.md`
  - answer:
    - Is the plan sufficient as-is, sufficient with adjustments, or insufficient?
    - What files, tests, regressions, evidence steps, or gates are missing?
    - What assumptions are stale or incorrect?
    - What is overengineered?
    - What is the minimum needed to make the plan sufficient?
  - use concrete repo evidence
  - name files/tests when claiming something is missing

  Arbiter:
  - only after Reviewer fully finishes
  - classify review findings into:
    - structural blockers
    - incremental details

  Structural blocker means:
  - wrong session classification
  - wrong deliverable
  - wrong source of truth
  - wrong execution order
  - missing required regression-first step
  - missing required evidence-first step for an audit session
  - missing gate/test requirements from `14-regression-test-strategy.md` or `test-gate-definitions.md`
  - another issue that makes the session unsafe to execute

  Plan-fix loop:
  - If Arbiter finds structural blockers, patch `Test-Flight-Improv/session-N-plan.md`
  - Then rerun Reviewer
  - Then rerun Arbiter
  - Repeat in strict sequence until:
    - verdict becomes `sufficient`
    - or `sufficient with explicit follow-up`
    - or the same structural blockers repeat without meaningful reduction across 2 consecutive fix rounds, in
  which case mark Session N `blocked`

  Phase A output:
  1. create or update `Test-Flight-Improv/session-N-plan.md`
  2. planning verdict: sufficient / sufficient with explicit follow-up / blocked
  3. final Session N plan
  4. session classification
  5. structural blockers remaining, if any
  6. incremental details intentionally deferred
  7. exact docs/files updated
  8. why it is safe or unsafe to execute now

  ==================================================
  PHASE B. INDEPENDENT PLAN REVIEW + PLAN UPDATE
  ==================================================

  Run only after Phase A is complete.

  Use 2 agents in strict sequence:
  1. Independent Plan Reviewer
  2. Plan Updater

  Do not implement app code in this phase.

  Independent Plan Reviewer:
  - review `Test-Flight-Improv/session-N-plan.md` against:
    - the governing docs for Session N
    - `Test-Flight-Improv/14-regression-test-strategy.md`
    - `Test-Flight-Improv/test-gate-definitions.md`
  - do a strict sufficiency review:
    - Is the plan sufficient as-is, sufficient with adjustments, or insufficient?
    - What files, tests, regressions, evidence, or gates are missing?
    - What assumptions are stale or incorrect?
    - What is overengineered?
    - What is the minimum needed to make the plan sufficient?
  - use concrete repo evidence

  Plan Updater:
  - only after Independent Plan Reviewer fully finishes
  - if review says `sufficient as-is`, do not change the plan
  - if review says `sufficient with adjustments` or `insufficient`, patch `Test-Flight-Improv/session-N-plan.md`
  - keep the same format and structure
  - only patch what is missing or incorrect
  - do not broaden scope

  Phase B loop:
  - rerun Independent Plan Reviewer after each patch
  - continue until the plan becomes:
    - `sufficient`
    - or `sufficient with explicit follow-up`
  - if the same structural blockers repeat without meaningful reduction across 2 consecutive update rounds, mark
  Session N `blocked`

  Phase B output:
  1. plan review verdict: sufficient / sufficient with explicit follow-up / blocked
  2. what was missing
  3. whether `session-N-plan.md` was updated
  4. why the plan is safe or unsafe to execute now

  ==================================================
  PHASE C. EXECUTE SESSION N
  ==================================================

  Run only after Phase B is complete and the plan is safe to execute.

  Use 2 agents in strict sequence:
  1. Executor
  2. QA Reviewer

  Use the approved `Test-Flight-Improv/session-N-plan.md` as the source of truth.
  Do not replan from scratch unless the session plan or repo state is clearly stale.

  Execution mode rules by session type:
  - `implementation-ready`: add required regression first when the plan requires it, then implement
  - `evidence-gated`: verify the contract first; if current repo evidence is already sufficient, document it and
  stop without implementation
  - `stale`: no production implementation; only doc updates
  - `prerequisite-blocked`: do not execute

  Executor:
  - read the Session N plan, governing docs, code-entry files, and required test files
  - follow the scope guard exactly
  - if the session is evidence-gated, capture the required repo evidence before editing code
  - add the required regression/test first if the plan requires it
  - implement the smallest safe change set only if the evidence and plan justify it
  - run the exact direct tests from the plan for the code paths that changed
  - run the required subsystem gate(s) only if the session changed code in that subsystem
  - run the required Baseline Gate only if Flutter production code changed
  - run Transport Gate only if the plan requires it
  - then stop and report:
    1. files changed
    2. tests added/updated
    3. evidence captured
    4. exact tests and gates run
    5. failures/limitations
    6. whether done criteria appear satisfied

  Gate rules:
  - Baseline Gate is required only when Flutter production code changes
  - Groups Gate is required for Sessions 24, 25, 26 and usually for Session 27 and Session 28
  - Baseline Gate is usually required for Sessions 24, 25, 26, and 29 when production code changes land
  - Transport Gate is required only when the session affects lifecycle, pause/resume, startup, recovery wiring,
  or device-backed media flows
  - Session 27 and Session 28 may complete without production changes if the acceptance evidence is sufficient
  - Session 29 should prefer direct deterministic instrumentation tests first, then run the relevant gates based
  on what code actually changed

  QA Reviewer:
  - only after Executor fully finishes
  - do a strict execution sufficiency review
  - check:
    - scope adherence
    - correct session-type handling
    - behavior correctness
    - missing regressions/tests
    - missing required evidence
    - missing required test/gate runs
    - failed required tests
    - whether done criteria are actually met
  - classify findings into:
    - blocking issues
    - non-blocking follow-ups

  Blocking issue means:
  - wrong behavior
  - wrong session-type handling
  - missing required regression/test
  - missing required evidence for an evidence-gated session
  - missing required gate/test run
  - failed required test not addressed
  - scope violation
  - done criteria not met

  Execution-fix loop:
  - If QA finds blocking issues, return work to the Executor
  - Executor patches the implementation or evidence pack
  - Executor reruns only the necessary direct tests plus all required gates affected by the fix
  - Executor reports again
  - Then QA reviews again
  - Repeat in strict sequence until:
    - execution becomes `sufficient`
    - or `sufficient with explicit follow-up`
    - or the same blocking issues repeat without meaningful reduction across 2 consecutive fix rounds, in which
  case mark Session N `blocked`

  Do not keep looping over non-blocking follow-ups.

  Phase C sufficiency rule:
  Execution is sufficient when:
  - no blocking issues remain
  - required evidence has been captured for evidence-gated sessions
  - required tests/gates have been run when code changed
  - done criteria are met
  - only non-blocking follow-ups remain, if any

  Phase C output:
  1. execution verdict: sufficient / sufficient with explicit follow-up / blocked
  2. files changed
  3. tests added or updated
  4. evidence captured
  5. exact tests and gates run
  6. blocking issues remaining, if any
  7. non-blocking follow-ups deferred
  8. why Session N is safe or unsafe to consider complete

  ==================================================
  PHASE D. CONTINUE / SKIP / STOP
  ==================================================

  After each session:
  - If Session N is `accepted`, continue to Session N+1
  - If Session N is `accepted_with_explicit_follow_up`, continue to Session N+1
  - If Session N is `blocked`, determine whether Session N+1 depends on its missing artifact
  - If the next session depends on the blocker, mark it `skipped_due_to_dependency`
  - If the next session is independent, continue
  - Do not stop the whole workflow unless the remaining unprocessed sessions all depend on the blocker

  Session dependency expectations:
  - Session 25 depends on Session 24 being meaningfully landed
  - Session 26 depends on the core reliability work from Sessions 24 and 25 not being obviously missing
  - Session 27 depends on Sessions 24, 25, and 26 being landed enough to audit
  - Session 28 depends on the shared group reliability changes being landed enough to audit announcement safety
  - Session 29 is mostly independent and may still proceed if acceptance sessions are blocked for purely
  documentary reasons, but not if the underlying messaging reliability work is missing

  ==================================================
  FINAL OUTPUT
  ==================================================

  At the end, return:
  1. sessions accepted
  2. sessions accepted_with_explicit_follow_up
  3. sessions blocked
  4. sessions skipped_due_to_dependency
  5. for each processed session:
    - session classification
    - plan verdict
    - execution verdict
    - files changed
    - tests added/updated
    - evidence captured
    - exact tests and gates run
    - blocking issues remaining
    - non-blocking follow-ups deferred
  6. all docs/files updated across Sessions 24..29
  7. whether the overall workflow finished all sessions or which remaining sessions were skipped due to
  dependency

  Key differences from your 12..23 version:

  - it uses the actual governing docs for 24..29
  - it removes the cross-tree / external-handoff complexity you no longer need
  - it treats 27 and 28 as evidence-gated acceptance sessions
  - it keeps 29 lean and local instead of turning it into a broad observability project