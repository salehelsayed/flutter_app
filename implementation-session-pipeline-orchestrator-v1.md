---
name: implementation-session-pipeline-orchestrator
description: "Run one reusable session-breakdown artifact to completion in a clean bounded pipeline: for each session, ensure an execution-safe doc-scoped plan exists, execute it, close it, and update the breakdown ledger before moving to the next session, repeating with fresh child-agent contexts until all sessions are resolved and the breakdown has a persisted final program verdict. Use when a proposal has already been decomposed and Codex should finish the current doc without planning every session up front or layering extra recovery logic."
---

# Implementation Session Pipeline Orchestrator

Use this skill after a proposal has already been decomposed into a reusable
markdown artifact such as `*-session-breakdown.md`.

This skill is a thin session-level controller. It does not replace the
downstream skills. For each session it should do only three things:

1. ensure there is an execution-safe doc-scoped plan or equivalent execution
   contract
2. execute that contract with `$implementation-execution-qa-orchestrator`
3. close that session with `$implementation-closure-audit-orchestrator`

After the last runnable session, it should run one final whole-program
acceptance/closure pass.

Do not add extra session-level recovery layers when those steps are enough.

## Default Downstream Order

For each session:

1. reuse existing doc-scoped plan when safe, otherwise create or tighten it
   with `$implementation-plan-orchestrator`
2. execute that plan with `$implementation-execution-qa-orchestrator`
3. close that session with `$implementation-closure-audit-orchestrator`

After all runnable sessions:

4. run one final program-level closure review

## Pipeline Completion Rule

This skill owns the full breakdown until a final program verdict is persisted.

That means:

- after one session finishes, loop to the next runnable session and repeat the
  same planning -> execution -> closure sequence
- do not stop after the first accepted session, first generated plan, or first
  ledger update
- the skill is only complete when every session is resolved and the breakdown
  records one of the allowed final program verdicts

## Implementation-Committed Gap-Closure Mode

If the user says the rollout should make the codebase match the remaining user
journeys or that the gap must be covered now, treat the current breakdown as an
implementation-committed gap-closure rollout.

Signals include phrases such as:

- implementation-committed
- gap closure
- make the codebase match these journeys
- make sure the gap is covered now
- do not leave residual open rows

In this mode:

- do not use broad residual truth-alignment, prior higher-level rollouts, or
  doc-only reconciliation as a substitute for the current row-owned session work
- do not downgrade a row-owned `implementation-ready` or
  `needs_code_and_tests` session into `acceptance-only` or evidence-only work
  merely because current evidence shows the row is still an open gap
- do not accept a row-owned session while its source row in the matrix remains
  `Open`, `Partial`, or `Contract-undefined`
- require the current source row to be updated to `Closed` or `Covered` with
  concrete file-and-test evidence before that row-owned session may finish as
  `accepted`
- if the row cannot yet be closed, leave it `blocked` or keep the whole doc
  `still_open` rather than using `accepted_with_explicit_follow_up` to mask the
  unresolved gap
- allow `accepted_with_explicit_follow_up` only for non-row closure/admin work
  or for a row that is already `Closed` or `Covered` and merely carries a narrow
  non-blocking note unrelated to the row's own closure bar

## Controller Continuation Rule

When unresolved runnable sessions remain and no real blocker exists, the
controller must continue the pipeline instead of returning a partial
progress-only summary.

Preferred continuation path when spawned agents are available:

1. persist the current breakdown, current session plan, and any touched docs
2. spawn one fresh continuation controller agent for the same breakdown
3. hand it only:
   - the breakdown artifact path
   - the source doc path when needed for orientation
   - the small set of touched stable docs or plan paths needed to resume safely
4. wait for that continuation controller to keep processing sessions
5. repeat this continuation chain as needed until:
   - a final program verdict is persisted
   - or a real blocker is recorded

Do not:

- return after one or a few accepted sessions merely because the current turn is
  getting long
- tell the user “the next runnable session is X” as the normal successful stop
  point when unresolved runnable sessions still remain
- require the user to manually rerun the same pipeline command after an ordinary
  progress checkpoint when a fresh continuation controller could keep going
- treat “not finished in this turn” as an acceptable success-path reason to end
  the pipeline

If the environment truly cannot keep continuing, record that honestly as a real
blocker or unfinished final verdict state in the breakdown rather than
presenting the partial progress checkpoint as normal completion.

If the user has explicitly opted into degraded local continuation mode, do not
treat fresh-child no-progress by itself as proof that the environment cannot
keep continuing.

## Large Breakdown Rule

If the breakdown is large enough that one controller pass is likely to exceed a
reasonable turn, token, or wait budget, prefer chained continuation controllers
over returning early.

Strong default: when the recommended plan count is greater than `20`, assume a
continuation chain will likely be needed unless current repo evidence quickly
reclassifies most sessions as already resolved.

For large breakdowns:

- keep per-session chat output minimal
- rely on persisted artifacts as the source of truth between continuation
  controllers
- continue automatically until the final program verdict exists or a real block
  prevents further safe progress

## Isolation Contract

If spawned agents are available, the default path is:

- one fresh planning agent when planning is needed
- one fresh execution agent for the current session
- one fresh closure agent for the current session
- one fresh final program acceptance/closure agent at the end

Each downstream skill invocation must run in its own fresh child-agent context.
When the pipeline advances to the next session, it should spawn fresh child
agents again from persisted artifacts rather than carrying prior-session child
context forward.

Do not:

- reuse one agent across multiple sessions
- reuse one agent for planning, execution, and closure on the same session
- fork the full controller thread when bounded artifact inputs are enough
- run multiple downstream skills for one or more sessions inside one reused
  child context when fresh child agents are available
- pass broad prior-session child chat history into the next session when the
  breakdown, current plan, and current execution artifacts are enough

If the environment cannot spawn agents, stop and say the isolation contract
cannot be satisfied.

## Degraded Local Continuation Mode

When the user explicitly prefers completing the rollout over strict fresh-child
isolation, the controller may degrade into controller-local continuation if
fresh child materialization repeatedly no-progresses.

This mode is opt-in. Enter it only when the prompt or breakdown explicitly says
completion should continue even if fresh-child isolation no-progresses.

Enter degraded local continuation mode only when all of these are true:

- unresolved runnable sessions still remain
- at least one fresh child planning, execution, or closure step has
  no-progressed under bounded wait for two consecutive session attempts or two
  consecutive continuation-controller passes
- the current breakdown entries and any written session plans remain execution
  safe enough to continue with the existing bounded local fallbacks
- no real product, test, or repo blocker is preventing the next session

In degraded local continuation mode:

- continue session by session rather than stopping solely because fresh-child
  isolation is unreliable in the current environment
- use the existing bounded local plan, execution, and closure fallbacks as the
  primary path for later sessions
- keep persisting artifacts after every session so a later fresh controller can
  still resume cleanly
- record clearly in the breakdown that degraded local continuation mode was
  entered and why
- keep the same row-owned closure bar; degraded continuation is only a delivery
  mode change, not a reason to weaken acceptance

Do not use degraded local continuation mode to:

- silently skip sessions
- accept unresolved rows
- rewrite the source matrix to look covered without code/test evidence
- hide a real blocker behind controller-local recovery

## Spawned Agent Model Rule

Every spawned agent created by this skill must explicitly request:

- `model: gpt-5.5`
- `reasoning_effort: xhigh`

## Start Here

Read only what defines the current doc rollout:

- the named session-breakdown artifact
- the proposal doc it references, only when needed
- the regression docs and gate definitions when the breakdown says they matter
- the stable closure or matrix docs referenced by the breakdown

If the breakdown file is missing any of these, tighten it first or stop:

- `recommended plan count`
- `session ledger`
- `ordered session breakdown`
- `downstream execution path`

In implementation-committed gap-closure mode, also read the current source
matrix or closure doc that the breakdown says row-owned sessions must update.

## Ledger Sanity Check

Before trusting the session ledger, before skipping to final acceptance, and
again before any local final acceptance fallback, reconcile the persisted
breakdown state against the current source matrix and available on-disk
artifacts.

Treat the ledger as stale and reopen the affected row-owned sessions when any
of these are true:

- a row-owned session is marked `accepted`,
  `accepted_with_explicit_follow_up`, or `stale/already-covered`, but its
  source row in the matrix still reads `Open`, `Partial`, or
  `Contract-undefined`
- a row-owned session is marked `accepted`, but the source matrix row was not
  updated to `Closed` or `Covered` with concrete evidence
- a row-owned session is marked `blocked`,
  `prerequisite-blocked`, or `skipped_due_to_dependency`, but its source row in
  the matrix now reads `Closed` or `Covered`
- the ledger claims there are no runnable sessions left, but row-owned source
  rows remain unresolved without a truthful persisted blocker classification
- a row-owned session is marked `accepted`, yet its intended plan path is
  missing and the source matrix still shows the row as unresolved

When stale ledger state is found:

- do not jump straight to final acceptance
- reset the affected row-owned sessions from stale accepted states back to an
  unresolved runnable or blocked state that matches their current session
  classification and notes
- or, when the source matrix already closes the row truthfully, promote stale
  blocked row-owned sessions into a resolved accepted or stale/already-covered
  state that matches the now-closed source row and current evidence
- persist that ledger correction before continuing the normal session loop
- treat the corrected breakdown as the new source of truth for the current run

In implementation-committed gap-closure mode, a final acceptance pass is only
allowed after this ledger sanity check passes cleanly.

## Reusable Plan Rule

Reuse an existing doc-scoped plan for the current session when all of these are
true:

- the plan file exists at the intended session path
- it belongs to the current doc
- it is not obviously stale against the current breakdown entry
- it still contains explicit scope, tests, gates, done criteria, and scope
  guard

If those conditions hold, do not rerun planning. Go straight to execution.

## Execution-Safe Contract Rule

If no reusable plan exists yet, the current session may still be execution-safe
from the breakdown entry itself only when all of these are true:

- the session classification is `implementation-ready`,
  `evidence-gated`, `acceptance-only`, or `stale/already-covered`
- the session entry has exact scope
- the session entry lists likely code-entry files
- the session entry lists likely direct tests or regressions
- the session entry lists likely named gates or explicitly says none apply
- the dependency state is explicit and currently satisfied
- the matrix or closure docs to update are named
- the session entry does not record unresolved structural blockers

If the entry is execution-safe but the plan file is missing, the controller may
write the minimal doc-scoped plan locally as a bounded artifact-only fallback.

In implementation-committed gap-closure mode:

- treat `acceptance-only` as execution-safe only for non-row closure/admin work
  or a row already updated to `Closed` or `Covered`
- do not treat a row-owned unresolved gap as execution-safe under
  `acceptance-only`

## Bounded Recovery Model

Keep recovery simple and bounded.

For each session, this skill allows at most:

1. one spawned planning attempt when planning is needed
2. one bounded local plan fallback only if the spawned planning step fails to
   leave a reusable execution-safe plan
3. one spawned execution attempt
4. one bounded local execution fallback only if the spawned execution step
   fails to leave a trustworthy current-session result or trustworthy
   code/test/doc progress
5. one spawned closure attempt
6. one bounded local closure fallback only if the spawned closure step fails to
   leave a trustworthy ledger/doc update

After the session loop, allow:

7. one spawned final program acceptance/closure attempt
8. one bounded local final acceptance/closure fallback only if that step
   no-progresses

Do not add any other session-level retry tiers.

Once degraded local continuation mode is entered legitimately, these same
bounded local fallbacks may be used across later sessions without treating the
rollout as failed solely because fresh-child isolation remained unavailable.

## Trustworthy Progress Rule

Treat a step as having trustworthy progress only when the current session gains
artifact or result state that the next step can safely use.

For planning, trustworthy progress means:

- a new or updated reusable doc-scoped session plan

For execution, trustworthy progress means one of:

- a trustworthy final execution verdict for the current session
- trustworthy code/test/doc delta tied to the current session
- trustworthy direct test or named gate results tied to the current session

For closure, trustworthy progress means one of:

- a current-session breakdown ledger delta
- updated closure or matrix docs tied to the current session

For final program acceptance, trustworthy progress means:

- a persisted final program verdict in the current breakdown artifact
- stable closure or matrix doc updates tied to the whole doc rollout

If a spawned step produces no trustworthy progress under bounded wait, close it
and use the matching single local fallback for that same step.

Trustworthy progress inside one session does not authorize the controller to end
the overall pipeline early. The controller must continue the session loop until
the breakdown has a persisted final program verdict.

In implementation-committed gap-closure mode, trustworthy progress for a
row-owned session is not enough unless the source matrix row itself is updated
from an unresolved state to `Closed` or `Covered` with concrete evidence.

## Local Plan Fallback

Use this only when:

- the current session still has no reusable plan
- the spawned planning step did not leave trustworthy planning progress
- the breakdown entry is already execution-safe

The fallback is bounded and artifact-only:

1. read the current session breakdown entry
2. read the breakdown artifact's overall closure bar and source of truth
3. write the intended doc-scoped plan file with the minimum sections needed for
   execution safety
4. return immediately to normal plan verification

Do not use this fallback to execute code or close docs.

If the local plan fallback still does not leave an execution-safe plan, the
current session is blocked.

## Local Execution Fallback

Use this only when:

- the current session already has an execution-safe plan
- the spawned execution attempt did not leave a trustworthy execution result or
  trustworthy current-session code/test/doc progress

The fallback is bounded and current-session-only:

1. reuse the current session plan
2. locally apply the
   `$implementation-execution-qa-orchestrator` contract against that plan
3. stop as soon as the current session reaches a finished execution verdict or
   a real block

This fallback does not authorize:

- replanning the session when the plan is already reusable
- reopening prior accepted sessions
- inventing extra execution retries

If the local execution fallback still does not produce a finished execution
verdict, the current session is blocked.

## Local Closure Fallback

Use this only when:

- the current session finished execution acceptably
- the spawned closure attempt did not leave a trustworthy closure result

The fallback is bounded and current-session-only:

1. reuse the current session plan and execution result
2. locally apply the
   `$implementation-closure-audit-orchestrator` contract for that session
3. stop as soon as the current session gets a trustworthy closure result or a
   real block

If the local closure fallback still does not leave a trustworthy closure
result, the current session is blocked.

## Local Final Acceptance Fallback

Use this only when:

- all runnable sessions are already resolved for the current doc
- the spawned final program acceptance/closure step did not leave a trustworthy
  final program verdict

Do not use this fallback while ledger sanity mismatches still exist between the
row-owned session ledger and the source matrix.

The fallback is bounded and doc-only:

1. reuse the current breakdown artifact
2. reuse the stable closure and matrix docs already touched by the doc
3. locally apply the final program acceptance/closure review once

If the local final acceptance fallback still does not leave a trustworthy final
program verdict, the doc remains `still_open`.

## Bounded Wait Rule

Do not wait indefinitely on spawned planning, execution, closure, or final
acceptance agents.

For each spawned step:

1. wait for a bounded interval
2. inspect whether trustworthy current-session progress landed on disk
3. if the child is still running without a final result:
   - allow at most one additional bounded wait only when the first interval
     produced real current-session progress
   - otherwise close the child and move to the matching single local fallback

Do not leave the pipeline controller parked on a running child when nothing
current-session-relevant is changing.

## Per-Session Workflow

Run this sequence for each session in order:

1. `Ledger Sanity Check`
2. `Breakdown Intake`
3. `Dependency Check`
4. `Plan Preparation`
5. `Execution`
6. `Session Closure`
7. `Session Completion Gate`
8. `Ledger Update`

After the session loop:

9. `Final Program Acceptance`

After `Ledger Update`, return to `Breakdown Intake` for the next unresolved
session and repeat until no runnable sessions remain.

Do not run multiple sessions in parallel unless the user explicitly changes
that contract.

### 1. Ledger Sanity Check

Before trusting the next unresolved session selection:

- reconcile accepted or stale row-owned ledger states against the source matrix
- reopen any stale accepted row-owned session whose source row still remains
  unresolved
- persist any required ledger correction before continuing

### 2. Breakdown Intake

For the current session only:

- read the session row
- read the session breakdown entry
- identify the intended doc-scoped plan path

### 3. Dependency Check

Proceed with the current session only when:

- it has no dependency
- or its dependency sessions already reached an accepted finished state

If a dependency is blocked, mark the current session
`skipped_due_to_dependency` and continue to later independent sessions.

### 4. Plan Preparation

If a reusable plan already exists, skip planning.

Otherwise:

- spawn one fresh `$implementation-plan-orchestrator` agent
- hand it only:
  - the breakdown artifact path
  - the current session row and session breakdown entry
  - the intended plan path

If that spawned attempt does not leave an execution-safe plan, perform the
single `Local Plan Fallback`.

### 5. Execution

For an execution-safe current-session plan:

- spawn one fresh `$implementation-execution-qa-orchestrator` agent
- hand it only:
  - the current session plan path
  - the current session row when needed for orientation

If that spawned attempt does not leave a trustworthy finished execution result,
perform the single `Local Execution Fallback`.

### 6. Session Closure

For a current session that finished execution acceptably:

- spawn one fresh `$implementation-closure-audit-orchestrator` agent
- hand it only:
  - the current session plan path
  - the current execution result
  - the breakdown artifact path

If that spawned attempt does not leave a trustworthy closure result, perform
the single `Local Closure Fallback`.

### 7. Session Completion Gate

Advance to the next session only when the current session reaches one of:

- `accepted`
- `accepted_with_explicit_follow_up`
- `stale/already-covered`
- `skipped_due_to_dependency`

In implementation-committed gap-closure mode, a row-owned session may advance
as `accepted` only when its source row has been updated to `Closed` or
`Covered`. Do not advance a row-owned unresolved gap as
`accepted_with_explicit_follow_up`.

If the current session remains:

- `blocked`
- or missing a trustworthy closure result after acceptable execution

record it honestly in the breakdown ledger and continue only with later
independent sessions.

### 8. Ledger Update

For each processed session record:

- current status
- plan file path
- final execution verdict when known
- closure docs touched
- blocker class when blocked
- concise note

### 9. Final Program Acceptance

After all runnable sessions are resolved:

- spawn one fresh final acceptance/closure agent
- hand it only:
  - the breakdown artifact path
  - stable closure and matrix docs touched by this doc

If that spawned attempt does not leave a trustworthy final program verdict,
perform the single `Local Final Acceptance Fallback`.

Before either the spawned final acceptance step or the local final acceptance
fallback, run the ledger sanity check one more time. If accepted row-owned
sessions still disagree with the source matrix, reopen them and return to the
session loop instead of writing a program verdict.

## Final Program Verdicts

The final program verdict must be exactly one of:

- `closed`
- `accepted_with_explicit_follow_up`
- `residual_only`
- `still_open`

Use:

- `closed` when the overall closure bar is met with no meaningful deferred work
- `accepted_with_explicit_follow_up` when the overall closure bar is met and
  the remaining items are explicitly non-blocking
- `residual_only` when no broad program should reopen and only one narrow
  residual remains
- `still_open` when any required session remains blocked, any required closure
  result is missing, or the overall closure bar is not yet met

In implementation-committed gap-closure mode:

- use `closed` only when every row-owned source row in the matrix is updated to
  `Closed` or `Covered`
- do not use `accepted_with_explicit_follow_up` or `residual_only` while any
  row-owned source row remains `Open`, `Partial`, or `Contract-undefined`
- keep the final verdict `still_open` until every required gap row is actually
  closed

## Output Format

Keep the final output compact and structured:

- `Breakdown artifact used`
- `Sessions processed`
- `Sessions accepted`
- `Sessions accepted_with_explicit_follow_up`
- `Sessions blocked`
- `Plan fallbacks used`
- `Execution fallbacks used`
- `Closure fallbacks used`
- `Final acceptance fallbacks used`
- `Sessions skipped_due_to_dependency`
- `Final program acceptance verdict`
- `Docs updated`
- `Why the rollout is safe to continue or complete`

Do not emit this final output format until one of these is true:

- the breakdown has a persisted final program verdict
- or continuation is no longer possible because of a real blocker

If continuation becomes impossible before a final verdict exists, say so
explicitly and name the blocker. A mere “processed N sessions so far” checkpoint
is not a valid success-path final output.

## Guardrails

- Do not fully detailed-plan all sessions up front.
- Do not rerun planning when a reusable current-session plan already exists.
- Do not rerun execution against a missing or unsafe plan.
- Do not invent extra session-level retry tiers.
- Do not silently collapse the whole pipeline into one giant shared context.
- Do not trust stale accepted row-owned ledger state without reconciling it
  against the source matrix in implementation-committed gap-closure rollouts.
- Do not downgrade unresolved row-owned sessions into `acceptance-only`,
  docs-only, or evidence-only closure in implementation-committed gap-closure
  rollouts.
- Do not stop the pipeline after the first accepted session or the first partial
  ledger delta when later sessions remain unresolved.
- Do not stop the pipeline just because the current controller turn is long when
  a fresh continuation controller can resume from persisted artifacts.
- Do not stop solely because fresh-child isolation no-progressed if the user has
  explicitly opted into degraded local continuation mode and no real blocker
  exists.
- Do not present “next runnable session is X” as the final successful outcome
  while unresolved runnable sessions remain.
- Do not treat per-session execution acceptance as automatic proof that the
  whole doc is closed.
- Do not reopen accepted differences from the decomposition unless a real
  landed regression forces it.
- Do not change doc-scoped plan paths into shared generic paths.
- Do not let child agents for planning, execution, closure, or final acceptance
  accumulate multiple sessions' work in one context when fresh child agents are
  available.
