
  Open [14-regression-test-strategy.md](/Users/I560101/Project-Sat/mknoon-2/flutter_app/Test-Flight-Improv/14-
  regression-test-strategy.md), [15-session-todo-roadmap.md](/Users/I560101/Project-Sat/mknoon-2/flutter_app/
  Test-Flight-Improv/15-session-todo-roadmap.md), and [16-session-todo-roadmap-2.md](/Users/I560101/Project-Sat/
  mknoon-2/flutter_app/Test-Flight-Improv/16-session-todo-roadmap-2.md).

  Use these skills where relevant:
  - `libp2p-phase-orchestrator` as the main controller
  - `flutter-test-orchestrator` for regression/test planning, gate selection, and QA
  - `flutter-ui-performance-profiler` for Sessions 15, 16, 17 and other profile-gated work
  - `go-libp2p-resilience-implementer` for cross-tree Go / bridge work
  - `mobile-network-resilience-qa` only when the active session touches startup, resume, transport, failover,
  inbox catch-up, or device/simulator resilience validation
  - `flutter-sqlite-migrations-and-repositories` only when the active session changes DB helpers, migrations, or
  repository persistence contracts

  Work through Sessions 12 through 23 from `Test-Flight-Improv/16-session-todo-roadmap-2.md` in strict order.

  Global sequencing rule:
  - No agents may run in parallel.
  - Every phase must fully finish before the next phase starts.
  - Within a phase, each agent must fully finish before the next agent starts.
  - Do not start Session N+1 until Session N has reached one of:
    - `accepted`
    - `accepted_with_external_follow_up`
    - `blocked`
    - `skipped_due_to_dependency`

  Global blocker policy:
  - Distinguish these outcomes:
    - `hard blocker`
    - `soft external dependency blocker`
    - `stale/already-covered`
    - `prerequisite-blocked`
  - A `soft external dependency blocker` means the remaining gap lives in an external CI host, external repo,
  external owner path, or inaccessible release system, and no more repo-local work can safely reduce uncertainty.
  - A `soft external dependency blocker` must NOT stop the whole workflow.
  - Instead, switch the session into `External Handoff Mode` and finish it as `accepted_with_external_follow_up`
  if the handoff criteria are met.
  - A `hard blocker` means the session cannot be completed safely even after all possible repo-local work is
  done, and the blocker is not just inaccessible external ownership.
  - A `prerequisite-blocked` session means a required artifact or prior session output is missing.
  - If a session is `blocked` or `prerequisite-blocked`, do not automatically stop the whole roadmap.
  - First determine whether later sessions explicitly depend on that blocker.
  - Continue with later sessions that are independent.
  - Mark later dependent sessions as `skipped_due_to_dependency`.

  Global convergence rule:
  - Do not stop a session just because the first review or QA pass says `insufficient`.
  - Patch and retry the current session until it becomes:
    - `sufficient`
    - or `sufficient with explicit follow-up`
    - or `accepted_with_external_follow_up`
  - Mark a session `blocked` only if the same structural blockers repeat without meaningful reduction across 2
  consecutive fix rounds.
  - Do not loop forever over incremental details.

  For each session N in {12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23}, use:
  - active roadmap item: Session N from `Test-Flight-Improv/16-session-todo-roadmap-2.md`
  - plan file: `Test-Flight-Improv/session-N-plan.md`

  ==================================================
  PHASE 0. CLASSIFY SESSION N
  ==================================================

  Before planning or execution, classify Session N as one of:
  - `implementation-ready`
  - `profile-gated`
  - `evidence-gated`
  - `cross-tree`
  - `stale`
  - `prerequisite-blocked`

  Classification rules:
  - `profile-gated`: the roadmap requires traces, profiling, measurements, or query-plan evidence before deciding
  whether code should change
  - `evidence-gated`: the roadmap requires proof of an existing contract and may validly end with “already
  sufficient, document it”
  - `cross-tree`: the work lives partly outside the Flutter tree, such as `go-mknoon/` or external CI/release
  config
  - `stale`: the repo already covers the gap strongly enough; update docs and stop without implementation
  - `prerequisite-blocked`: a required artifact from roadmap 15 or an earlier accepted session is missing

  Session-specific expectations:
  - Session 12: likely `cross-tree`; may become `accepted_with_external_follow_up` if the real CI/release host is
  inaccessible
  - Session 13: likely `implementation-ready`
  - Session 14: likely `cross-tree` and `evidence-gated`
  - Sessions 15, 16, 17: `profile-gated`
  - Session 18: likely `implementation-ready`
  - Session 19: `profile-gated` or `evidence-gated`
  - Session 20: likely `implementation-ready`
  - Session 21: likely `implementation-ready`
  - Session 22: likely `implementation-ready`
  - Session 23: likely `implementation-ready`, but `prerequisite-blocked` if roadmap 15 Session 11 observability
  artifacts do not exist yet

  If Session N is `stale`:
  - update the session plan and any affected roadmap/docs
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
  - read the Session N roadmap item, listed source reports, listed code-entry files, and any prerequisite outputs
  from roadmap 15 first
  - create or update `Test-Flight-Improv/session-N-plan.md`
  - produce a detailed Session N plan with:
    1. real scope
    2. session classification
    3. files and repos to inspect next
    4. existing tests covering this area
    5. regression/tests to add first, if any
    6. evidence to capture first, if the session is profile-gated or evidence-gated
    7. step-by-step implementation or evidence-collection plan
    8. risks and edge cases
    9. exact tests to run after implementation, if code changes occur
    10. subsystem gate(s), if relevant
    11. whether Baseline Gate is required
    12. whether Startup / Transport Gate is required
    13. done criteria
    14. dependency impact on later sessions if this session blocks

  Planner rules:
  - If the session is profile-gated, require evidence before proposing production edits
  - If the session is evidence-gated, allow a valid outcome of “no code change needed”
  - If the session is cross-tree, inspect and edit the relevant repo/config path instead of forcing the work into
  Flutter only
  - If the session encounters an inaccessible external repo / CI host / owner path, classify that as a possible
  `soft external dependency blocker`
  - For Session 12:
    - treat `Test-Flight-Improv/test-gate-definitions.md` as the intended canonical source of truth if it exists
    - if `Test-Flight-Improv/test-gates-reference.md` also exists, reconcile it instead of creating a third
  definition
    - if the real CI host is inaccessible, plan for `External Handoff Mode`
    - preferred handoff artifact path: `Test-Flight-Improv/ci-gate-handoff.md`
  - For Session 23:
    - if roadmap 15 Session 11 observability artifacts are missing, mark it `prerequisite-blocked`

  Reviewer:
  - only after Planner fully finishes
  - do a strict sufficiency review of `session-N-plan.md`
  - answer:
    - Is the plan sufficient as-is, sufficient with adjustments, or insufficient?
    - What files, repos, tests, regressions, evidence steps, or gates are missing?
    - What assumptions are stale or incorrect?
    - What is overengineered?
    - What is the minimum needed to make the plan sufficient?
  - use concrete repo evidence
  - name files/tests/repos when claiming something is missing

  Arbiter:
  - only after Reviewer fully finishes
  - classify review findings into:
    - structural blockers
    - incremental details
    - soft external dependency blockers

  Structural blocker means:
  - wrong repo or code tree
  - missing prerequisite
  - wrong deliverable
  - wrong source of truth
  - wrong execution order
  - missing required profiling/evidence step
  - another issue that makes the session unsafe to execute

  Soft external dependency blocker means:
  - the only remaining unresolved work lives in an external CI/release host, external repo, or external owner
  path that is not accessible from the current workspace
  - and no more repo-local work can safely reduce uncertainty

  Plan-fix loop:
  - If Arbiter finds structural blockers, patch `Test-Flight-Improv/session-N-plan.md`
  - Then rerun Reviewer
  - Then rerun Arbiter
  - Repeat in strict sequence until:
    - verdict becomes `sufficient`
    - or `sufficient with explicit follow-up`
    - or `accepted_with_external_follow_up`
    - or the same structural blockers repeat without meaningful reduction across 2 consecutive fix rounds, in
  which case mark Session N `blocked`

  External Handoff Mode:
  - If Arbiter finds only soft external dependency blockers, do not mark the session blocked
  - Instead patch `session-N-plan.md` so the execution phase completes all safe repo-local work and produces:
    - canonical local artifacts
    - exact external invocation contract
    - explicit missing external repo/path/owner
    - any remaining handoff notes
  - Then mark the planning phase `sufficient with explicit follow-up`

  Phase A output:
  1. create or update `Test-Flight-Improv/session-N-plan.md`
  2. planning verdict: sufficient / sufficient with explicit follow-up / blocked
  3. final Session N plan
  4. session classification
  5. structural blockers remaining, if any
  6. soft external dependency blockers remaining, if any
  7. incremental details intentionally deferred
  8. exact docs/files updated
  9. why it is safe or unsafe to execute now

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
    - `Test-Flight-Improv/16-session-todo-roadmap-2.md`
    - relevant prerequisites from `Test-Flight-Improv/15-session-todo-roadmap.md`
    - `Test-Flight-Improv/14-regression-test-strategy.md` when gates are involved
  - do a strict sufficiency review:
    - Is the plan sufficient as-is, sufficient with adjustments, or insufficient?
    - What files, repos, tests, regressions, evidence, or gates are missing?
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
  Do not replan from scratch unless the roadmap item or repo state is clearly stale.

  Execution mode rules by session type:
  - `implementation-ready`: add required regression first when the plan requires it, then implement
  - `profile-gated`: collect evidence first; if the evidence says “no code change justified,” document it and
  stop without speculative edits
  - `evidence-gated`: verify the contract first; if current evidence is already sufficient, document it and stop
  without implementation
  - `cross-tree`: inspect and edit the correct repo/config locations; do not force the work into Flutter only
  - `stale`: no production implementation; only doc updates
  - `prerequisite-blocked`: do not execute

  Executor:
  - read the Session N roadmap item, approved plan, source reports, code-entry files, and any required
  prerequisite outputs
  - follow the scope guard exactly
  - if the session is profile-gated or evidence-gated, capture the required evidence before editing code
  - add the required regression/test first if the plan requires it
  - implement the smallest safe change set only if the evidence and plan justify it
  - run the exact direct tests from the plan for the code paths that changed
  - run the required subsystem gate(s) only if the session changed code in that subsystem
  - run the required Baseline Gate only if Flutter production code changed
  - run Startup / Transport Gate only if the plan requires it
  - for Go-tree work, run the exact Go tests from the plan
  - for CI/release/config work, validate the exact invoked commands or wiring path from the plan
  - if the only remaining blocker is inaccessible external ownership, switch to `External Handoff Mode` instead
  of failing
  - then stop and report:
    1. files changed
    2. repos/config paths changed
    3. tests added/updated
    4. evidence captured
    5. exact tests and gates run
    6. failures/limitations
    7. whether done criteria appear satisfied

  External Handoff Mode:
  - Complete all repo-local work that can be done safely
  - Reconcile or create the canonical local artifacts that the external system would call
  - Create a handoff artifact with:
    - exact commands
    - expected invocation points
    - required job names or trigger points when known
    - missing external repo / path / owner
    - any device/manual notes still required
  - For Session 12, preferred handoff artifact path is `Test-Flight-Improv/ci-gate-handoff.md`
  - Mark the session `accepted_with_external_follow_up` if:
    1. no further repo-local work would reduce uncertainty
    2. the canonical local command surface is defined
    3. the external integration contract is documented clearly
    4. the missing external owner/path is recorded explicitly

  Gate rules:
  - Baseline Gate is required only when Flutter production code changes
  - Subsystem gates are required only when the session changes that subsystem
  - Startup / Transport Gate is required only when the session affects bootstrap, resume, transport fallback, DB-
  open startup, or device-backed media flows
  - Pure evidence-only or profile-only sessions may complete without Baseline Gate if no Flutter production code
  changed
  - For Session 12, validate the canonical gate runner / CI invocation contract rather than inventing a larger
  matrix
  - For Session 14, use the Go-side test commands from the plan and run Flutter gates only if Flutter-facing
  contracts changed

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
    - whether `accepted_with_external_follow_up` is justified when used
  - classify findings into:
    - blocking issues
    - non-blocking follow-ups
    - soft external dependency blockers

  Blocking issue means:
  - wrong behavior
  - wrong session-type handling
  - missing required regression/test
  - missing required evidence for a profile/evidence-gated session
  - missing required gate/test run
  - failed required test not addressed
  - scope violation
  - wrong repo edited
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
    - or `accepted_with_external_follow_up`
    - or the same blocking issues repeat without meaningful reduction across 2 consecutive fix rounds, in which
  case mark Session N `blocked`

  Do not keep looping over non-blocking follow-ups.

  Phase C sufficiency rule:
  Execution is sufficient when:
  - no blocking issues remain
  - required evidence has been captured for gated sessions
  - required tests/gates have been run when code changed
  - done criteria are met
  - only non-blocking follow-ups remain, if any

  Phase C output:
  1. execution verdict: sufficient / sufficient with explicit follow-up / accepted_with_external_follow_up /
  blocked
  2. files changed
  3. repos/config paths changed
  4. tests added or updated
  5. evidence captured
  6. exact tests and gates run
  7. blocking issues remaining, if any
  8. soft external dependency blockers remaining, if any
  9. non-blocking follow-ups deferred
  10. why Session N is safe or unsafe to consider complete

  ==================================================
  PHASE D. CONTINUE / SKIP / STOP
  ==================================================

  After each session:
  - If Session N is `accepted`, continue to Session N+1
  - If Session N is `accepted_with_external_follow_up`, continue to Session N+1
  - If Session N is `blocked`, determine whether Session N+1 depends on its missing artifact
  - If the next session depends on the blocker, mark it `skipped_due_to_dependency`
  - If the next session is independent, continue
  - Do not stop the whole roadmap unless the remaining unprocessed sessions all depend on the blocker

  ==================================================
  FINAL OUTPUT
  ==================================================

  At the end, return:
  1. sessions accepted
  2. sessions accepted_with_external_follow_up
  3. sessions blocked
  4. sessions skipped_due_to_dependency
  5. for each processed session:
    - session classification
    - plan verdict
    - execution verdict
    - files changed
    - repos/config paths changed
    - tests added/updated
    - evidence captured
    - exact tests and gates run
    - blocking issues remaining
    - soft external dependency blockers remaining
    - non-blocking follow-ups deferred
  6. all docs/files updated across Sessions 12..23
  7. whether the overall workflow finished all sessions or which remaining sessions were skipped due to
  dependency
