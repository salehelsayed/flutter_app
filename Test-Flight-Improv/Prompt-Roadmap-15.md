Open [15-session-todo-roadmap.md](/Users/I560101/Project-Sat/mknoon-2/flutter_app/Test-Flight-Improv/15-session-todo-roadmap.md) and plan Session <N>.

  Do not implement yet.

  Read the roadmap item, the listed source reports, and the listed code-entry files first. Then give me:
  1. scope
  2. files to inspect next
  3. existing tests covering this area
  4. regression/tests to add first
  5. step-by-step implementation plan
  6. risks and edge cases
  7. exact tests to run after implementation
  8. subsystem gate(s) and whether startup/transport tests are needed
  9. done criteria

  If the session looks stale, say how it should be adjusted before implementation.

  Example:

  Open [15-session-todo-roadmap.md](/Users/I560101/Project-Sat/mknoon-2/flutter_app/Test-Flight-Improv/15-session-todo-roadmap.md) and plan Session 1 in an .md file under Test-Flight-Improv/

  Do not implement yet.

  Read the roadmap item, the listed source reports, and the listed code-entry files first. Then give me:
  1. scope
  2. files to inspect next
  3. existing tests covering this area
  4. regression/tests to add first
  5. step-by-step implementation plan
  6. risks and edge cases
  7. exact tests to run after implementation
  8. subsystem gate(s) and whether startup/transport tests are needed
  9. done criteria

  If the session looks stale, say how it should be adjusted before implementation.



1,2,3,4,5,6
  ======
  # 3 agent prompt - PLAN

    Open [14-regression-test-strategy.md](/Users/I560101/Project-Sat/mknoon-2/flutter_app/Test-Flight-Improv/14-
  regression-test-strategy.md) and [15-session-todo-roadmap.md](/Users/I560101/Project-Sat/mknoon-2/flutter_app/
  Test-Flight-Improv/15-session-todo-roadmap.md).

  Plan Session 7 <N> using 3 agents in strict sequence:
  1. Planner
  2. Reviewer
  3. Arbiter

  Do not implement app code.

  Critical sequencing rule:
  - The 3 agents must NOT run in parallel.
  - Start the Planner first.
  - Wait for the Planner to fully finish and produce the Session 7 <N> draft plan.
  - Only after the Planner is done, start the Reviewer.
  - Only after the Reviewer is done, start the Arbiter.
  - If the Arbiter finds structural blockers, patch the Session 7 <N> plan once, then run one final Reviewer pass and
  one final Arbiter pass in sequence.
  - Do not run Planner, Reviewer, or Arbiter at the same time.

  Follow the Sufficiency Boundary and Review Exit Rule from report 14 and report 15.

  Phase 1. Planner
  Planner must:
  - read the Session 7 <N> oadmap item, the listed source reports, and the listed code-entry files first
  - produce a detailed Session 6 plan with:
    1. scope
    2. files to inspect next
    3. existing tests covering this area
    4. regression/tests to add first
    5. step-by-step implementation plan
    6. risks and edge cases
    7. exact tests to run after implementation
    8. subsystem gate(s) and whether startup/transport tests are needed
    9. done criteria
  - create or update:
    - `Test-Flight-Improv/session-7-plan.md`

  Phase 2. Reviewer
  Only after Phase 1 is complete, Reviewer must:
  - do a strict sufficiency review of the Session 7 <N> plan
  - answer:
    - Is the plan sufficient as-is, sufficient with adjustments, or insufficient?
    - What files, tests, regressions, or gates are missing?
    - What assumptions are stale or incorrect?
    - What is overengineered?
    - What is the minimum needed to make the plan sufficient?
  - use concrete repo evidence
  - name files/tests when claiming something is missing

  Phase 3. Arbiter
  Only after Phase 2 is complete, Arbiter must:
  - classify the review findings into:
    - structural blockers
    - incremental details

  Definitions:
  - Structural blocker = missing directory/category of tests, wrong deliverable, wrong source of truth, wrong
  execution order, missing completeness policy, missing stop-rule, or another issue that would make Session 6
  unsafe to execute.
  - Incremental detail = one more candidate file, alternate gate placement, wording cleanup, or another non-
  structural refinement.

  Patch rule:
  - If the Arbiter finds structural blockers, patch `Test-Flight-Improv/session-7-plan.md` once.
  - Then run one final Reviewer pass.
  - Then run one final Arbiter pass.
  - These final passes must also run in sequence, not in parallel.

  Stop rule:
  - If the Arbiter finds no new structural blocker, stop and return the plan as sufficient or sufficient with
  explicit follow-up.
  - Do not continue looping over incremental details.
  - Maximum flow:
    1. Planner
    2. Reviewer
    3. Arbiter
    4. optional one patch
    5. optional final Reviewer
    6. optional final Arbiter
  - Then stop.

  Output:
  1. create or update `Test-Flight-Improv/session-7-plan.md`
  2. final verdict: sufficient / sufficient with explicit follow-up / insufficient
  3. final Session 7 <N> plan
  4. structural blockers remaining, if any
  5. incremental details intentionally deferred
  6. exact docs/files updated
  7. why it is safe or unsafe to execute now

  ===========
# Review Plan 1 agent

    Review my session-7-plan.md against [15-session-todo-roadmap.md](/Users/I560101/Project-Sat/mknoon-2/flutter_app/Test-Flight-Improv/15-session-todo-roadmap.md).

  Do not implement.

  I want a strict sufficiency review:
  - Is the plan sufficient as-is, sufficient with adjustments, or insufficient?
  - What files, tests, regressions, or gates are missing?
  - What assumptions are stale or incorrect?
  - What is overengineered?
  - What is the minimum needed to make the plan sufficient?

  Use concrete file/test evidence from the repo.



======
# Execution 2 agents 


  Open [15-session-todo-roadmap.md](/Users/I560101/Project-Sat/mknoon-2/flutter_app/Test-Flight-Improv/15-
  session-todo-roadmap.md) and execute Session-6-plan.mde <N> using 2 agents in strict sequence:

  1. Executor
  2. QA Reviewer

  Use the approved Session-7-plan.md <N> plan as the source of truth.
  Do not replan from scratch unless the roadmap item or repo state is clearly stale.

  Critical sequencing rule:
  - The 2 agents must NOT run in parallel.
  - Start the Executor first.
  - Wait for the Executor to fully finish implementation and testing.
  - Only after the Executor has completed and reported results, start the QA Reviewer.
  - If QA finds blocking issues, return work to the Executor for one fix pass.
  - After that fix pass completes, run QA one final time.
  - Do not run Executor and QA at the same time.

  Required execution flow:

  Phase 1. Executor pass
  Executor must:
  - read the Session 7 <N> roadmap item, source reports, code-entry files, and approved plan
  - follow the scope guard exactly
  - add the required regression/test first if the plan requires it
  - implement the smallest safe change set
  - run the exact direct tests from the plan
  - run the required subsystem gate(s)
  - run the required Baseline Gate
  - run startup/transport tests only if the plan requires them
  - then stop and report:
    1. files changed
    2. tests added/updated
    3. exact tests and gates run
    4. failures/limitations
    5. whether done criteria appear satisfied

  Required Baseline Gate:
  - use the exact Baseline Gate defined in the approved Session-7-plan.md <N> plan and [14-regression-test-strategy.md](/
  Users/I560101/Project-Sat/mknoon-2/flutter_app/Test-Flight-Improv/14-regression-test-strategy.md)
  - do not replace it with a smaller or different set of tests

  Phase 2. QA review
  Only after Phase 1 is complete, QA Reviewer must:
  - do a strict execution sufficiency review
  - check scope adherence
  - check behavior correctness
  - check missing regressions/tests
  - check missing required test/gate runs
  - check failed required tests
  - check whether done criteria are actually met
  - classify findings into:
    - blocking issues
    - non-blocking follow-ups

  Blocking issue means:
  - wrong behavior
  - missing required regression/test
  - missing required gate/test run
  - failed required test not addressed
  - scope violation
  - done criteria not met

  Phase 3. Optional fix pass
  - If QA finds blocking issues, hand control back to the Executor
  - Executor gets exactly one fix pass
  - Executor reruns only the necessary direct tests plus all required gates affected by the fix
  - Executor reports again
  - Then QA runs one final review
  - Stop after that final QA review

  Loop rule:
  - Executor pass once
  - QA pass once
  - optional Executor fix pass once
  - optional final QA pass once
  - then stop
  - do not keep looping over non-blocking follow-ups

  Sufficiency rule:
  Execution is sufficient when:
  - no blocking issues remain
  - required tests/gates have been run
  - done criteria are met
  - only non-blocking follow-ups remain, if any

  Output:
  1. final verdict: sufficient / sufficient with explicit follow-up / insufficient
  2. files changed
  3. tests added or updated
  4. exact tests and gates run
  5. blocking issues remaining, if any
  6. non-blocking follow-ups deferred
  7. why Session 7 <N> is safe or unsafe to consider complete

===

# Review 1 agent

  Review the completed execution for Session-5-plan.md <N> against the approved Session 4 <N> plan and [15-session-todo-
  roadmap.md](/Users/I560101/Project-Sat/mknoon-2/flutter_app/Test-Flight-Improv/15-session-todo-roadmap.md).

  Do not implement anything.

  I want a strict execution sufficiency review.

  Check:
  - did the implementation stay within Session 5 <N> scope?
  - does the behavior match the approved plan?
  - were the required regression/tests added first if needed?
  - were the exact direct tests run?
  - were the required subsystem gate(s) run?
  - was the baseline gate run?
  - were startup/transport tests run if the plan required them?
  - are the done criteria actually satisfied?

  Classify findings into:
  - blocking issues
  - non-blocking follow-ups

  Blocking issue means:
  - wrong behavior
  - missing required regression/test
  - missing required gate/test run
  - failed required test not addressed
  - scope violation
  - done criteria not met

  Use concrete repo evidence. Name files and tests when something is missing or wrong.

  Output:
  1. final verdict: sufficient / sufficient with explicit follow-up / insufficient
  2. blocking issues
  3. non-blocking follow-ups
  4. tests/gates missing or incorrectly run, if any
  5. why Session 5 <N> is safe or unsafe to consider complete

==============
# If not sufficient
    Use this if review finds structural blockers in the plan/docs.

  Open [14-regression-test-strategy.md](/Users/I560101/Project-Sat/mknoon-2/flutter_app/Test-Flight-Improv/14-
  regression-test-strategy.md), [15-session-todo-roadmap.md](/Users/I560101/Project-Sat/mknoon-2/flutter_app/
  Test-Flight-Improv/15-session-todo-roadmap.md), and any related reports for Session 1 <N>.

  Do not implement app code.

  Use the review findings below to update the markdown docs under `Test-Flight-Improv/` so Session 1 <N> is
  sufficient by the Sufficiency Boundary and Review Exit Rule.

  Keep the same report format.

  Review findings:










  ============================================================================================================================================


  Open [14-regression-test-strategy.md](/Users/I560101/Project-Sat/mknoon-2/flutter_app/Test-Flight-Improv/14-
  regression-test-strategy.md) and [15-session-todo-roadmap.md](/Users/I560101/Project-Sat/mknoon-2/flutter_app/
  Test-Flight-Improv/15-session-todo-roadmap.md).

  Use these skills where relevant:
  - `libp2p-phase-orchestrator` as the main phase/session controller
  - `flutter-test-orchestrator` for regression/test planning, gate selection, and QA
  - `mobile-network-resilience-qa` only if the active session touches startup, resume, transport, failover, inbox
  catch-up, or device/simulator resilience validation

  Work through Sessions 7 through 11 in strict order.
  For each session, complete planning, review, plan-fix, execution, and QA before moving to the next session.

  Global sequencing rule:
  - No agents may run in parallel.
  - Every phase must fully finish before the next phase starts.
  - Within a phase, each agent must fully finish before the next agent starts.

  Global convergence rule:
  - Do NOT stop a session just because the first review or QA pass says `insufficient`.
  - Instead, patch and retry the current session until it becomes `sufficient` or `sufficient with explicit
  follow-up`.
  - Only stop a session as `blocked` if the same structural blockers repeat without meaningful reduction across 2
  consecutive fix rounds.
  - If a session becomes `blocked`, stop the overall workflow and report why.

  For each session N in {7, 8, 9, 10, 11}, use:
  - roadmap item: Session N from [15-session-todo-roadmap.md](/Users/I560101/Project-Sat/mknoon-2/flutter_app/
  Test-Flight-Improv/15-session-todo-roadmap.md)
  - plan file: `Test-Flight-Improv/session-N-plan.md`

  ==================================================
  PHASE A. PLAN SESSION N
  ==================================================

  Use 3 agents in strict sequence:
  1. Planner
  2. Reviewer
  3. Arbiter

  Do not implement app code in this phase.

  Planner:
  - read the Session N roadmap item, listed source reports, and listed code-entry files first
  - create or update `Test-Flight-Improv/session-N-plan.md`
  - produce a detailed Session N plan with:
    1. scope
    2. files to inspect next
    3. existing tests covering this area
    4. regression/tests to add first
    5. step-by-step implementation plan
    6. risks and edge cases
    7. exact tests to run after implementation
    8. subsystem gate(s) and whether startup/transport tests are needed
    9. done criteria

  Reviewer:
  - only after Planner fully finishes
  - do a strict sufficiency review of `session-N-plan.md`
  - answer:
    - Is the plan sufficient as-is, sufficient with adjustments, or insufficient?
    - What files, tests, regressions, or gates are missing?
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

  Definitions:
  - Structural blocker = missing directory/category of tests, wrong deliverable, wrong source of truth, wrong
  execution order, missing completeness policy, missing stop-rule, or another issue that would make Session N
  unsafe to execute.
  - Incremental detail = one more candidate file, alternate gate placement, wording cleanup, or another non-
  structural refinement.

  Plan-fix loop:
  - If Arbiter finds structural blockers, patch `Test-Flight-Improv/session-N-plan.md`.
  - Then run Reviewer again.
  - Then run Arbiter again.
  - Repeat in strict sequence until:
    - verdict becomes `sufficient` or `sufficient with explicit follow-up`, or
    - the same structural blockers repeat without meaningful reduction across 2 consecutive fix rounds, in which
  case mark Session N as `blocked`.

  Do not keep looping over incremental details only.

  Phase A output:
  1. create or update `Test-Flight-Improv/session-N-plan.md`
  2. planning verdict: sufficient / sufficient with explicit follow-up / blocked
  3. final Session N plan
  4. structural blockers remaining, if any
  5. incremental details intentionally deferred
  6. exact docs/files updated
  7. why it is safe or unsafe to execute now

  If Phase A ends as `blocked`, stop the whole workflow.

  ==================================================
  PHASE B. INDEPENDENT PLAN REVIEW + PLAN UPDATE
  ==================================================

  Run only after Phase A is complete.

  Use 2 agents in strict sequence:
  1. Independent Plan Reviewer
  2. Plan Updater

  Do not implement app code in this phase.

  Independent Plan Reviewer:
  - review `Test-Flight-Improv/session-N-plan.md` against [15-session-todo-roadmap.md](/Users/I560101/Project-
  Sat/mknoon-2/flutter_app/Test-Flight-Improv/15-session-todo-roadmap.md)
  - do a strict sufficiency review:
    - Is the plan sufficient as-is, sufficient with adjustments, or insufficient?
    - What files, tests, regressions, or gates are missing?
    - What assumptions are stale or incorrect?
    - What is overengineered?
    - What is the minimum needed to make the plan sufficient?
  - use concrete file/test evidence from the repo

  Plan Updater:
  - only after Independent Plan Reviewer fully finishes
  - if review says `sufficient as-is`, do not change the plan
  - if review says `sufficient with adjustments` or `insufficient`, patch `Test-Flight-Improv/session-N-plan.md`
  - keep the same format and structure
  - only patch what is missing or incorrect
  - do not broaden scope

  Phase B loop:
  - rerun Independent Plan Reviewer after each patch
  - continue until the plan becomes `sufficient` or `sufficient with explicit follow-up`
  - if the same structural blockers repeat without meaningful reduction across 2 consecutive update rounds, mark
  Session N as `blocked`

  Phase B output:
  1. plan review verdict: sufficient / sufficient with explicit follow-up / blocked
  2. what was missing
  3. whether `session-N-plan.md` was updated
  4. why the plan is safe or unsafe to execute now

  If Phase B ends as `blocked`, stop the whole workflow.

  ==================================================
  PHASE C. EXECUTE SESSION N
  ==================================================

  Run only after Phase B is complete and the plan is safe to execute.

  Use 2 agents in strict sequence:
  1. Executor
  2. QA Reviewer

  Use the approved `Test-Flight-Improv/session-N-plan.md` as the source of truth.
  Do not replan from scratch unless the roadmap item or repo state is clearly stale.

  Executor:
  - read the Session N roadmap item, source reports, code-entry files, and approved plan
  - follow the scope guard exactly
  - add the required regression/test first if the plan requires it
  - implement the smallest safe change set
  - run the exact direct tests from the plan
  - run the required subsystem gate(s)
  - run the required Baseline Gate
  - run startup/transport tests only if the plan requires them
  - then stop and report:
    1. files changed
    2. tests added/updated
    3. exact tests and gates run
    4. failures/limitations
    5. whether done criteria appear satisfied

  Required Baseline Gate:
  - use the exact Baseline Gate defined in the approved `session-N-plan.md` and [14-regression-test-strategy.md]
  (/Users/I560101/Project-Sat/mknoon-2/flutter_app/Test-Flight-Improv/14-regression-test-strategy.md)
  - do not replace it with a smaller or different set of tests

  QA Reviewer:
  - only after Executor fully finishes
  - do a strict execution sufficiency review
  - check:
    - scope adherence
    - behavior correctness
    - missing regressions/tests
    - missing required test/gate runs
    - failed required tests
    - whether done criteria are actually met
  - classify findings into:
    - blocking issues
    - non-blocking follow-ups

  Blocking issue means:
  - wrong behavior
  - missing required regression/test
  - missing required gate/test run
  - failed required test not addressed
  - scope violation
  - done criteria not met

  Execution-fix loop:
  - If QA finds blocking issues, return work to the Executor
  - Executor patches the implementation
  - Executor reruns only the necessary direct tests plus all required gates affected by the fix
  - Executor reports again
  - Then QA reviews again
  - Repeat in strict sequence until:
    - execution becomes `sufficient` or `sufficient with explicit follow-up`, or
    - the same blocking issues repeat without meaningful reduction across 2 consecutive fix rounds, in which case
  mark Session N as `blocked`

  Do not keep looping over non-blocking follow-ups.

  Sufficiency rule for Phase C:
  Execution is sufficient when:
  - no blocking issues remain
  - required tests/gates have been run
  - done criteria are met
  - only non-blocking follow-ups remain, if any

  Phase C output:
  1. execution verdict: sufficient / sufficient with explicit follow-up / blocked
  2. files changed
  3. tests added or updated
  4. exact tests and gates run
  5. blocking issues remaining, if any
  6. non-blocking follow-ups deferred
  7. why Session N is safe or unsafe to consider complete

  If Phase C ends as `blocked`, stop the whole workflow.

  ==================================================
  PHASE D. CONTINUE OR STOP
  ==================================================

  - If Session N planning and execution are sufficient, continue to Session N+1.
  - If Session N finishes with only explicit non-blocking follow-ups, continue to Session N+1.
  - If Session N is blocked, stop immediately and report:
    - which session failed
    - which phase failed
    - what blockers remain
    - what must be fixed before continuing

  ==================================================
  FINAL OUTPUT
  ==================================================

  At the end, return:
  1. sessions completed successfully
  2. sessions blocked, if any
  3. for each completed session:
    - plan verdict
    - execution verdict
    - files changed
    - tests added/updated
    - exact tests and gates run
    - blocking issues remaining
    - non-blocking follow-ups deferred
  4. all docs/files updated across Sessions 7..11
  5. whether the overall workflow finished all sessions or stopped because a session was blocked

  Short answer to your concern:

  - yes, we can use the skills
  - no, I would not let it loop forever
  - the right rule is: loop until sufficient, or stop as blocked if no meaningful progress is happening
