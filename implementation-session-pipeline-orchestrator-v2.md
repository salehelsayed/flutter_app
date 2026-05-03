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

## Runnable Session Definition

A runnable session is a session that is:

- unresolved in the session ledger
- not already in ledger status `accepted`, `accepted_with_explicit_follow_up`,
  `stale/already-covered`, or `skipped_due_to_dependency`
- not currently `blocked` or `prerequisite-blocked`
- dependency-satisfied, if it has dependencies
- execution-safe or plan-preparable under this skill's rules

A session whose classification is `stale/already-covered` but whose ledger
status is still unresolved is runnable only for the Resolution Without Execution
rule.

A blocked session is not runnable, but it still counts against final closure
unless the final verdict policy explicitly allows that blocker.

A `stale/already-covered` session is resolved only after its evidence is
recorded in the ledger and, when applicable, in the source matrix or closure doc.

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

## Implementation-Committed Discovered-Gap Rule

In implementation-committed gap-closure mode, do not treat a newly discovered
repo-owned missing implementation surface as a terminal blocker just because the
current plan was too narrow, evidence-only, or tests-only.

When execution discovers that the row remains `Open` or `Partial` because code,
schema, signed-event, protocol, repository, UI, or test-hook behavior is missing,
classify the gap before closure:

- `implementation-owned gap`: the missing behavior is directly named by the
  current row and can be designed within the current row's likely owner files or
  adjacent implementation. Reclassify the current session to
  `needs_code_and_tests`, persist the correction, and return once to Plan
  Preparation for a fresh implementation plan instead of blocking immediately.
- `prerequisite-owned gap`: the missing behavior clearly belongs to another
  unresolved row, prerequisite, or shared architecture session. Record the exact
  dependency, mark the current session `skipped_due_to_dependency` or
  `prerequisite-blocked`, and continue with the prerequisite or later
  independent sessions when they are runnable.
- `external-fixture blocker`: the missing evidence depends on unavailable
  device-lab, relay, OS-permission, raw-capture, product-scope, or other
  non-repo-owned fixtures. Record the exact blocker without overclaiming.

This reclassification is a scope correction, not an extra retry tier. Do it at
most once for the current discovered gap, then execute the corrected plan under
the normal bounded recovery model.

A row-specific blocker is not by itself a reason to stop the whole rollout while
later independent sessions remain runnable. Stop only when the blocker prevents
safe progress for every remaining unresolved session or when the final program
verdict is being written after all runnable sessions are resolved.

On resume or ledger sanity in implementation-committed gap-closure mode, apply
the same classification to existing blocked rows. If a persisted blocker is an
implementation-owned gap, reopen that row as `needs_code_and_tests` and plan the
missing implementation. Keep it blocked only when it is prerequisite-owned,
external-fixture-blocked, unsupported by product scope, or unsafe to implement
without a separate explicit prerequisite.

## Same-Session Recovery Rule

In implementation-committed gap-closure mode, a current-session
implementation-owned blocker is not terminal until same-session recovery is
exhausted.

Use this rule when the blocker is still inside the current row's owner files or
tests, including focused test failures, `qa_blocking_issue`, incomplete scoped
implementation, or partial current-row code/test deltas.

Before recording a controller stop state or moving to later sessions:

1. write a `Recovery Input` note in the session plan with the blocker class,
   failing tests, missing contract, touched owner files, and a blocker signature
2. return to Plan Preparation for the same session
3. spawn a fresh planner to tighten the same session plan around that blocker
4. spawn fresh Execution+QA for the tightened plan
5. proceed to closure only after Execution+QA returns an acceptable verdict

Allow at most two same-session recovery passes per distinct blocker signature.
The blocker signature is the session id plus blocker class, failing tests or
missing contract, and owner files. If the same signature still blocks after two
recovery passes, record the session as blocked. If a genuinely different
implementation-owned signature appears, it gets its own two-pass budget.

Do not use same-session recovery for prerequisite-owned blockers,
external-fixture blockers, unsupported product scope, or unsafe dirty state that
cannot be repaired inside the current row.

## Controller Continuation Rule

When unresolved runnable sessions remain and no real blocker exists, the
controller must continue the pipeline instead of returning a partial
progress-only summary.

Preferred continuation path when spawned agents are available:

1. the main controller keeps ownership of visible orchestration
2. for each current session, the main controller directly spawns the fresh
   planner, executor, closure, and final-acceptance children required by the
   Isolation Contract
3. after each child returns or produces progress, the main controller verifies
   the on-disk artifacts before starting the next phase
4. after each session closes or blocks, the main controller selects the next
   runnable session and repeats the visible child sequence
5. continue until:
   - a final program verdict is persisted
   - or a real blocker is recorded

Use a continuation controller only as a last-resort context handoff when the
main controller is genuinely near context exhaustion or cannot safely continue
locally. A continuation controller must be handoff-only by default: reconcile the
breakdown, identify the current session/phase, write a compact
`## Controller Progress` entry, and return the next visible action to the main
controller. It must not spawn hidden nested planner, executor, closure, or final
acceptance agents unless the user explicitly authorizes nested continuation.

Do not:

- return after one or a few accepted sessions merely because the current turn is
  getting long
- tell the user “the next runnable session is X” as the normal successful stop
  point when unresolved runnable sessions still remain
- require the user to manually rerun the same pipeline command after an ordinary
  progress checkpoint when the main controller can keep spawning visible
  per-phase children
- treat “not finished in this turn” as an acceptable success-path reason to end
  the pipeline

If the environment truly cannot keep continuing, record that honestly as a real
blocker or unfinished final verdict state in the breakdown rather than
presenting the partial progress checkpoint as normal completion.

If the user has explicitly opted into degraded local continuation mode, do not
treat fresh-child no-progress by itself as proof that the environment cannot
keep continuing.

## Controller Progress Retention Rule

`## Controller Progress` is a rolling live-status section, not a permanent audit
log.

Keep at most the latest 8 controller progress entries. Before writing a new
entry, remove older progress entries beyond that limit.

Do not preserve repeated wait, sanity-check, child-spawn, or stale next-action
notes after their durable result is recorded in the session plan, session
ledger, closure ledger, source matrix, test inventory, or final program verdict.

Never delete durable session evidence, closure ledgers, source-matrix rows,
test-inventory entries, session plan execution results, or final verdicts as
part of trimming controller progress.

## Large Breakdown Rule

If the breakdown is large enough that one controller pass is likely to exceed a
reasonable turn, token, or wait budget, still prefer visible main-controller
orchestration over nested continuation controllers.

Strong default: when the recommended plan count is greater than `20`, assume the
main controller will process many sessions through repeated visible
planner/executor/closure child spawns. Do not spawn a continuation controller
solely because the breakdown is large.

For large breakdowns:

- keep per-session chat output minimal
- rely on persisted artifacts as the source of truth between visible child-agent
  phases
- continue automatically until the final program verdict exists or a real block
  prevents further safe progress
- use a handoff-only continuation controller only when the main controller is
  genuinely near context exhaustion or otherwise cannot safely continue visible
  orchestration

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

## Run Mode Snapshot

Before selecting the first session, persist or refresh a short run-mode snapshot
in the breakdown artifact.

The snapshot must record:

- active mode: `standard` or `implementation-committed gap-closure`
- whether degraded local continuation is explicitly allowed
- source proposal, matrix, or closure doc path
- source row/status vocabulary used by the current doc
- overall closure bar
- final verdict policy for this run

Continuation controllers must read this snapshot before selecting a session and
must not silently change the active mode or closure bar.

## Resume Rule

If the breakdown already contains a final program verdict, rerun ledger sanity
check before reporting completion.

If the verdict is still consistent with the source matrix, closure docs, and
current repo evidence, report the rollout as already complete.

If the verdict is stale, remove or supersede the stale verdict, reopen the
affected sessions, persist the correction, and continue the normal session loop.

## Source Status Normalization Rule

Before ledger sanity checks, normalize source row statuses case-insensitively.

Treat these as unresolved unless the source doc defines otherwise:

- `Open`
- `Partial`
- `Contract-undefined`
- `Needs evidence`
- `Needs tests`
- `Blocked`

Treat these as resolved only when concrete evidence is present:

- `Closed`
- `Covered`

Do not treat `N/A`, `Unsupported`, or `Out of scope` as resolved unless the
breakdown explicitly classifies the row as `unsupported_product_scope` or
`repo_external_proof` with supporting evidence.

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
- when the row mentions devices, simulators, real-network, relay, multi-relay,
  three-party, or OS notification evidence, it contains an explicit
  device/relay proof profile

If those conditions hold, do not rerun planning. Go straight to execution.

## Execution-Safe Contract Rule

If no reusable plan exists yet, the current session may still be execution-safe
from the breakdown entry itself only when all of these are true:

- the session classification is `implementation-ready`, `evidence-gated`, or
  `acceptance-only`
- the session entry has exact scope
- the session entry lists likely code-entry files
- the session entry lists likely direct tests or regressions
- the session entry lists likely named gates or explicitly says none apply
- the dependency state is explicit and currently satisfied
- the matrix or closure docs to update are named
- the session entry does not record unresolved structural blockers

`stale/already-covered` is not an execution classification. It follows the
Resolution Without Execution rule unless contradictory current repo evidence
forces the session to be reopened.

If the entry is execution-safe but the plan file is missing, the controller may
write the minimal doc-scoped plan locally as a bounded artifact-only fallback.

In implementation-committed gap-closure mode:

- treat `acceptance-only` as execution-safe only for non-row closure/admin work
  or a row already updated to `Closed` or `Covered`
- do not treat a row-owned unresolved gap as execution-safe under
  `acceptance-only`

## Resolution Without Execution Rule

Use this path for `stale/already-covered` sessions.

The controller must:

1. verify the cited current repo evidence still exists
2. verify the source matrix or closure doc is already compatible with that
   evidence, or update it with concrete file-and-test evidence when this rollout
   owns that doc
3. update the breakdown ledger as `stale/already-covered`
4. skip planning and execution for that session

Do not spawn an execution agent for an already-covered session unless current
repo evidence contradicts the stale/already-covered classification.

## Evidence-Gated Session Rule

For an `evidence-gated` session, the controller must resolve the evidence state
before accepting the session.

Allowed outcomes:

- current repo evidence proves the row is covered, then record concrete
  file-and-test evidence and close the session
- current repo evidence proves tests or code are missing, then reclassify the
  session to `implementation-ready` and continue through planning/execution
- proof depends on repo-external harnesses, raw protocol capture, device-lab
  orchestration, or non-Flutter-owned validators, then record the blocker and
  leave the session `blocked` or `prerequisite-blocked`

Do not accept an evidence-gated session with vague follow-up language.

## Device And Relay Proof Profile Rule

Before planning or executing any session whose row mentions Flutter devices,
simulators, device-lab, paired devices, multi-device, three-party proof,
real-network, relay, multi-relay, OS push/notification state, `integration_test`,
or `group-real-network-nightly`, classify the device/relay proof profile from
the current session entry plus the source matrix, `test-inventory.md`, and gate
definitions referenced by the breakdown.

Record that profile in the session plan before execution. The profile must say:

- whether the row is `host-only`, `single-device`, `paired-device`,
  `three-party/device-lab`, `multi-relay`, `os-notification-device-lab`, or
  `external-fixture-blocked`
- the live device availability check used for this run, preferably
  `flutter devices --machine`; add `xcrun simctl list devices available` for
  iOS simulator/device-lab rows and `adb devices` for Android paired-device rows
- the exact device ids, simulator ids, script arguments, or environment
  variables to use
- whether the device run is required closure evidence or only supporting gate
  evidence
- whether a single `FLUTTER_DEVICE_ID` is sufficient for the row or only selects
  the Flutter host target

Default configured values for this repo when the current docs do not provide a
more specific command:

- single iOS Flutter target:
  `FLUTTER_DEVICE_ID=347FB118-10D0-40C8-A05B-B0C3BD6B8CCD`
- primary iOS paired-device proof:
  `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD` and
  `5BA69F1C-B112-47BE-B1FF-8C1003728C8F`
- spare iOS validation target:
  `1B098DFF-6294-407A-A209-BBF360893485`
- primary Android paired-device proof:
  `emulator-5554` and `emulator-5556`
- group real-network relay addresses:
  `MKNOON_RELAY_ADDRESSES=/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g`

Use the row-specific command form from the current docs when it exists. For
paired or three-party/device-lab rows, do not treat a green single
`FLUTTER_DEVICE_ID` gate as complete closure evidence unless the row's own
closure bar says a single-device proof is sufficient. If the needed paired,
three-party, CLI-peer, OS-permission, or multi-relay fixture is unavailable,
record an exact fixture blocker instead of overclaiming closure.

Do not assume the default ids are present. If the live availability check does
not show the required devices, update the profile to `external-fixture-blocked`
with the missing ids or required simulator names before execution. If a reusable
plan has a device/relay profile but no current availability check, refresh the
profile before executing it.

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

Implementation-committed code-writing exception: when an execution plan requires
code or test changes and the first execution child no-progresses, spawn one
fresh narrower execution child before using local execution fallback. This is
the only allowed extra execution spawn for the session.

Same-session implementation-owned recovery is the only other bounded exception
to the per-session counts above, and only under the Same-Session Recovery Rule.

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
- for spawned planners, the intended plan file may begin as a working draft
  after the planner has enough initial context. Draft updates count only as
  wait-extension evidence; the plan is not reusable until it satisfies the
  Reusable Plan Rule.

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

## Controller Verification Rule

A child agent's final message is never sufficient by itself.

Before accepting planning, execution, closure, or final acceptance progress, the
controller must inspect the relevant on-disk artifacts:

- plan file for planning progress
- git diff/status and touched files for execution progress
- direct test or gate output when claimed
- source matrix or closure doc updates when row closure is claimed
- breakdown ledger updates for closure progress
- final program verdict persisted in the breakdown for final acceptance

If the claimed progress is not visible on disk, treat the spawned step as
no-progress and use the matching bounded fallback.

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
   - include a `Device/Relay Proof Profile` when the current row mentions any
     device, simulator, real-network, relay, multi-relay, three-party,
     OS-notification, or `integration_test` evidence
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

In implementation-committed gap-closure mode, this fallback is verification-only
unless degraded local continuation mode was explicitly allowed. The controller
may inspect diffs, run tests or gates, verify artifacts, write execution notes,
or record a blocker, but it must not write product code, migrations, or test
code itself.

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
2. during that interval, poll current-session artifacts at least once before
   the timeout point: intended plan path for planning, scoped git diff/test
   output for execution, breakdown/source docs for closure, and final verdict
   docs for final acceptance
3. inspect whether trustworthy current-session progress landed on disk
4. if the child is still running without a final result:
   - allow at most one additional bounded wait only when the first interval
     produced real current-session progress
   - otherwise close the child and move to the matching single local fallback

Planning exception: if a fresh planning child produces no intended plan file
after the first wait, send one concise progress request naming the intended plan
path and asking it to either write `Status: planning-intake` plus
`Planning Progress`, return a blocker, or finish the plan. Allow one additional
bounded wait for that communication. If no plan file exists after that, close
the child and use the local plan fallback when the breakdown entry is
execution-safe.

Once a planning file exists, extend waits based on meaningful artifact activity
rather than a fixed count. Meaningful activity includes status movement, new
files inspected, role boundary updates, reviewer findings, arbiter decisions,
or mandatory section content. If the plan file exists but is unchanged across a
bounded poll, send one concise progress request asking the planner to update
`Planning Progress`, return a blocker, or finish. Close the planner only if it
fails to update after that request. A draft remains wait-extension evidence
only; it is not executable until it satisfies the Reusable Plan Rule.

Execution exception: `## Execution Progress` updates in the current session plan
count as wait-extension evidence only. They are not completion evidence. If an
execution child produces no code/test/doc delta, no test/gate result, and no
`Execution Progress` update after a bounded wait, send one concise progress
request asking it to update `Execution Progress`, return a blocker, or finish.
Close the execution child only if it fails to update after that request, then
use the matching fallback or narrower-child rule.

For implementation-committed execution steps whose plan requires code or test
changes, use one fresh narrower execution child before the local execution
fallback. Hand that child only the current plan path, current session id, owner
files/tests, and exact artifact or result expected. If the narrower child also
no-progresses, close it and use the verification-only local execution fallback
or record the current session as blocked.

For planning, a changing intended-plan draft counts as current-session progress
only for wait-extension decisions, not as an execution-safe plan.

For handoff-only continuation controllers, changes to `## Controller Progress`
in the breakdown count as current-session progress only for wait-extension
decisions; they are not session completion, execution evidence, or final verdict
evidence.

For closure agents, current-session `Closure Progress` entries in the
breakdown, source matrix, test inventory, or session closure section count as
progress only for wait-extension decisions. They are not completed closure
until the session ledger and closure verdict are persisted and verified.

Do not leave the pipeline controller parked on a running child when nothing
current-session-relevant is changing.

## Dirty Worktree And Scope Guard

Before each session execution, record the current `git status --short`.

After execution, inspect changed files and verify they match the current
session's scope.

Do not revert unrelated user changes or prior-session changes. If execution
introduces changes outside the current session scope, require closure review to
classify them as intentional, harmless, or blocking before accepting the
session.

## Per-Session Workflow

Run this sequence for each session in order:

1. `Ledger Sanity Check`
2. `Breakdown Intake`
3. `Dependency Check`
4. `Resolution Without Execution Check`
5. `Plan Preparation`
6. `Dirty Worktree Snapshot`
7. `Execution`
8. `Session Closure`
9. `Session Completion Gate`
10. `Ledger Update`

After the session loop:

11. `Final Program Acceptance`

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

### 4. Resolution Without Execution Check

If the current session is `stale/already-covered`, follow the Resolution
Without Execution Rule and then continue to Session Completion Gate.

If current repo evidence contradicts the `stale/already-covered`
classification, reopen or reclassify the session before planning.

### 5. Plan Preparation

If a reusable plan already exists, skip planning.

Otherwise:

- spawn one fresh `$implementation-plan-orchestrator` agent
- hand it only:
  - the breakdown artifact path
  - the current session row and session breakdown entry
  - the intended plan path
  - the instruction to include a `Device/Relay Proof Profile` section whenever
    the row mentions device, simulator, real-network, relay, multi-relay,
    three-party, OS notification, or `integration_test` evidence. That section
    must follow the Device And Relay Proof Profile Rule and must state which
    device setup is sufficient for this row.
  - the instruction to use the intended plan file as the only planning progress
    artifact once enough initial context is gathered, updating a `Planning
    Progress` section after initial evidence collection and while exploring.
    Keep only the latest 5 `Planning Progress` entries. The controller must not
    execute from it until it satisfies the Reusable Plan Rule.

If that spawned attempt does not leave an execution-safe plan, perform the
single `Local Plan Fallback`.

### 6. Dirty Worktree Snapshot

Before execution, record the current `git status --short` for scope comparison
after the execution step.

### 7. Execution

For an execution-safe current-session plan:

- spawn one fresh `$implementation-execution-qa-orchestrator` agent
- hand it only:
  - the current session plan path
  - the current session row when needed for orientation
  - the instruction to update `## Execution Progress` in the current session
    plan before and after contract extraction, Executor, required tests/gates,
    QA, fix pass, final QA, and final verdict work. These updates are
    wait-extension evidence only; final acceptance still requires a trustworthy
    execution verdict, code/test/doc delta, or exact test/gate result.
  - when the plan contains a `Device/Relay Proof Profile`, instruct it to run
    or verify the live device availability check first, then run the exact
    profile commands and inline environment variables. For a single-device
    group real-network gate, use
    `FLUTTER_DEVICE_ID=347FB118-10D0-40C8-A05B-B0C3BD6B8CCD` and
    `MKNOON_RELAY_ADDRESSES=/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g`. For paired,
    three-party, OS-notification, or multi-relay rows, use the device ids,
    script arguments, and fixture requirements named in the profile rather than
    substituting the single-device gate.

If that spawned attempt does not leave a trustworthy finished execution result,
perform the single `Local Execution Fallback`.

### 8. Session Closure

For a current session that finished execution acceptably:

- spawn one fresh `$implementation-closure-audit-orchestrator` agent
- hand it only:
  - the current session plan path
  - the current execution result
  - the breakdown artifact path
  - the instruction to maintain current-session `Closure Progress` entries in
    the breakdown before long audit, write, or review work, naming session id,
    closure phase, docs inspected or updated, tentative verdict, and next action

If that spawned attempt does not leave a trustworthy closure result, perform
the single `Local Closure Fallback`.

### 9. Session Completion Gate

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

first apply the Implementation-Committed Discovered-Gap Rule when that mode is
active. If the remaining blocker is implementation-owned, apply the
Same-Session Recovery Rule before recording a hard blocked state, writing a
controller stop state, or moving to later sessions. If the session still remains
blocked after recovery is exhausted, record it honestly in the breakdown ledger
and continue with later independent runnable sessions only when the current
dirty state is safe for them. Do not set the next runnable row to none solely
because the current row is blocked unless no later session can proceed safely.

### 10. Ledger Update

For each processed session record:

- current status
- plan file path
- final execution verdict when known
- closure docs touched
- blocker class when blocked
- concise note

### 11. Final Program Acceptance

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

When the final verdict is `still_open`, also include:

- unresolved session IDs
- unresolved source row IDs, when applicable
- current source row status
- blocker class
- exact evidence or prerequisite still missing
- next safe action

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
  the main controller can continue through visible per-phase child agents.
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
