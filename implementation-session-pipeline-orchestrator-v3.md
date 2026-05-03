---
name: implementation-session-pipeline-orchestrator
description: "Run one session-breakdown artifact to completion with a simple bounded controller loop: for each runnable session, prepare an execution-safe plan, execute it, close it, record the result, and continue until the breakdown has a persisted final program verdict. Use when a proposal is already decomposed and Codex should finish the current doc without upfront detailed planning for every session or layered controller retries."
---

# Implementation Session Pipeline Orchestrator (Improved)

This skill is a **thin session-level controller**.
It does not replace the downstream skills.
It owns the rollout until the breakdown artifact has a persisted **final program verdict**.

Its job is simple:

1. pick the next runnable session
2. make sure that session has an execution-safe plan
3. execute the plan
4. close the session
5. record the result in the breakdown ledger
6. repeat until no runnable sessions remain
7. run one final whole-program acceptance / closure pass

Keep the controller simple, bounded, and artifact-driven.
Do not add extra controller retry layers beyond the rules below.

---

## Core Contract

For each runnable session, the controller must do exactly this sequence:

1. **Prepare**
   - reuse an existing execution-safe doc-scoped plan when safe
   - otherwise create or tighten it with `$implementation-plan-orchestrator`
2. **Execute**
   - run the session with `$implementation-execution-qa-orchestrator`
3. **Close**
   - close the session with `$implementation-closure-audit-orchestrator`
4. **Record**
   - persist the session result in the breakdown ledger and any owned source docs

After all runnable sessions are resolved:

5. **Finalize**
   - run one final program acceptance / closure pass

The controller is complete only when the breakdown records one of the allowed final program verdicts.

---

## Required Inputs

Read only what defines the current rollout:

- the named `*-session-breakdown.md` artifact
- the proposal doc it references, only when needed
- the regression docs and gate definitions when the breakdown says they matter
- the stable closure or matrix docs referenced by the breakdown

If the breakdown is missing any of these, tighten it first or stop:

- `recommended plan count`
- `session ledger`
- `ordered session breakdown`
- `downstream execution path`

In implementation-committed gap-closure mode, also read the current source matrix or closure doc that row-owned sessions must update.

---

## Run Modes

Persist or refresh a short `Run Mode Snapshot` in the breakdown before selecting the first session.

The snapshot must record:

- active mode: `standard` or `implementation-committed gap-closure`
- whether degraded local continuation is explicitly allowed
- source proposal, matrix, or closure doc path
- source row/status vocabulary used by this rollout
- overall closure bar
- final verdict policy for this run

Do not silently change the active mode or closure bar during a run.

### 1) Standard Mode

Default mode.
Use normal planning -> execution -> closure -> final acceptance.

### 2) Implementation-Committed Gap-Closure Mode

Use this when the user explicitly says the codebase must match the remaining journeys or that the current gap must be closed now.

Signals include:

- implementation-committed
- gap closure
- make the codebase match these journeys
- make sure the gap is covered now
- do not leave residual open rows

In this mode:

- do not use broad reconciliation or doc-only updates as a substitute for row-owned implementation work
- do not downgrade a row-owned `implementation-ready` or `needs_code_and_tests` session into `acceptance-only` merely because the row is still open
- do not accept a row-owned session while its owned source row remains `Open`, `Partial`, or `Contract-undefined`
- require the owned source row to be updated to `Closed` or `Covered` with concrete file-and-test evidence before that session may finish as `accepted`
- if the row cannot yet be closed, leave it `blocked`, `prerequisite-blocked`, or keep the whole doc `still_open`
- allow `accepted_with_explicit_follow_up` only for non-row closure/admin work or for a row that is already `Closed` or `Covered` and only carries a narrow non-blocking note

### 3) Degraded Local Continuation Mode

This mode is **opt-in**.
It is a delivery-mode change only.
It does not weaken the closure bar.

Enter it only when all are true:

- unresolved runnable sessions still remain
- at least one fresh child planning, execution, or closure step has no-progressed under bounded wait for two consecutive session attempts or two consecutive continuation-controller passes
- the current breakdown entries and written plans are still execution-safe enough to continue with existing bounded local fallbacks
- no real product, test, or repo blocker prevents the next session
- the user explicitly preferred completion over strict fresh-child isolation

In degraded local continuation mode:

- continue session by session instead of stopping solely because fresh-child isolation is unreliable
- keep persisting artifacts after every session
- record clearly in the breakdown that degraded local continuation mode was entered and why
- keep the same row-owned closure bar

Do not use this mode to:

- silently skip sessions
- accept unresolved rows
- rewrite the matrix to look covered without evidence
- hide a real blocker behind controller-local recovery

---

## Key Definitions

### Runnable Session

A runnable session is a session that is:

- unresolved in the session ledger
- not already in ledger status `accepted`, `accepted_with_explicit_follow_up`, `stale/already-covered`, or `skipped_due_to_dependency`
- not currently `blocked` or `prerequisite-blocked`
- dependency-satisfied, if it has dependencies
- execution-safe or plan-preparable under this skill

A `stale/already-covered` session whose ledger is still unresolved is runnable only for the Resolution Without Execution path.

A blocked session is not runnable, but it still counts against final closure unless the final verdict policy explicitly allows that blocker.

### Resolved Session States

The controller may advance beyond a session only when it reaches one of:

- `accepted`
- `accepted_with_explicit_follow_up`
- `stale/already-covered`
- `skipped_due_to_dependency`

### Blocker Classes

Use exactly these blocker classes:

1. **implementation-owned gap**
   - the missing behavior is directly named by the current row
   - it belongs to the current row's owner files or adjacent implementation
   - action: reclassify the session to `needs_code_and_tests`, persist the correction, and return once to Plan Preparation

2. **prerequisite-owned gap**
   - the missing behavior clearly belongs to another unresolved row, prerequisite, or shared architecture session
   - action: record the exact dependency, mark the session `skipped_due_to_dependency` or `prerequisite-blocked`, and continue with later independent runnable sessions

3. **external-fixture blocker**
   - proof depends on unavailable device-lab, relay, OS-permission, raw-capture, product-scope, or other non-repo-owned fixtures
   - action: record the exact blocker honestly without overclaiming closure

This classification is a scope correction, not a new retry tier.
Do it at most once for the current discovered gap, then continue under the normal bounded recovery model.

---

## Source Status Normalization

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

Do not treat `N/A`, `Unsupported`, or `Out of scope` as resolved unless the breakdown explicitly classifies the row as `unsupported_product_scope` or `repo_external_proof` with supporting evidence.

---

## Ledger Sanity Check

Run ledger sanity checks:

- before trusting the session ledger
- before selecting the next session
- before skipping to final acceptance
- again before any local final acceptance fallback

Reconcile the persisted breakdown state against the current source matrix and on-disk artifacts.

Treat the ledger as stale and reopen affected row-owned sessions when any of these are true:

- a row-owned session is marked `accepted`, `accepted_with_explicit_follow_up`, or `stale/already-covered`, but its source row still reads `Open`, `Partial`, or `Contract-undefined`
- a row-owned session is marked `accepted`, but the source row was not updated to `Closed` or `Covered` with concrete evidence
- a row-owned session is marked `blocked`, `prerequisite-blocked`, or `skipped_due_to_dependency`, but its source row now reads `Closed` or `Covered`
- the ledger claims no runnable sessions remain, but row-owned source rows remain unresolved without a truthful persisted blocker classification
- a row-owned session is marked `accepted`, yet its intended plan path is missing and the source matrix still shows the row as unresolved

When stale ledger state is found:

- do not jump straight to final acceptance
- reset affected row-owned sessions to an unresolved runnable or blocked state that matches current evidence
- or promote stale blocked row-owned sessions to a truthful resolved state when the source row is already closed
- persist the ledger correction before continuing

In implementation-committed gap-closure mode, also classify existing blocked row-owned sessions during resume and ledger sanity:

- if a persisted blocker is actually an `implementation-owned gap`, reopen that session as `needs_code_and_tests`, persist the correction, and plan the missing implementation
- keep it blocked only when it is `prerequisite-owned`, `external-fixture-blocked`, unsupported by product scope, or unsafe to implement without a separate explicit prerequisite

In implementation-committed gap-closure mode, final acceptance is allowed only after ledger sanity passes cleanly.

---

## Isolation Contract

If spawned agents are available, the default path is:

- one fresh planning agent when planning is needed
- one fresh execution agent for the current session
- one fresh closure agent for the current session
- one fresh final program acceptance / closure agent at the end

Rules:

- each downstream skill invocation must run in its own fresh child-agent context
- when the pipeline advances to the next session, spawn fresh child agents again from persisted artifacts
- do not reuse one agent across multiple sessions
- do not reuse one agent for planning, execution, and closure on the same session
- do not carry broad prior-session child chat history into the next session when persisted artifacts are sufficient

If the environment cannot spawn agents at all, stop and say the isolation contract cannot be satisfied.

### Spawned Agent Model Rule

Every spawned agent created by this skill must explicitly request:

- `model: gpt-5.5`
- `reasoning_effort: xhigh`

---

## Controller State Machine

Run this loop until a final program verdict is persisted.

### Session Loop

1. `Run Mode Snapshot`
2. `Ledger Sanity Check`
3. `Select Next Runnable Session`
4. `Dependency Check`
5. `Resolution Without Execution Check`
6. `Plan Preparation`
7. `Dirty Worktree Snapshot`
8. `Execution`
9. `Session Closure`
10. `Session Completion Gate`
11. `Ledger Update`
12. loop back to `Ledger Sanity Check`

### Finalization

13. `Final Program Acceptance`

After `Ledger Update`, immediately return to the next runnable session.
Do not stop after one accepted session, one generated plan, or one ledger update.

---

## Generic Step Wrapper

Use the same bounded wrapper for `Plan`, `Execution`, `Closure`, and `Final Program Acceptance`.

For each step:

1. spawn the correct fresh child agent with bounded inputs
2. wait for a bounded interval
3. poll the relevant on-disk artifacts at least once before timeout
4. verify whether trustworthy progress landed on disk
5. if there is no trustworthy progress:
   - close the child
   - use the matching single local fallback
6. verify the fallback result on disk
7. if the fallback still does not leave a trustworthy result:
   - block the current session honestly
   - or leave the whole doc `still_open` for final acceptance

### Trustworthy Progress

Treat a step as having trustworthy progress only when the current session gains artifact or result state that the next step can safely use.

- **Planning**: a new or updated reusable doc-scoped session plan
- **Execution**: a trustworthy execution verdict, trustworthy code/test/doc delta, or trustworthy direct test / named gate results tied to the current session
- **Closure**: a breakdown ledger delta or updated closure / matrix docs tied to the current session
- **Final acceptance**: a persisted final program verdict and any whole-doc stable doc updates tied to that verdict

Progress notes such as `Planning Progress`, `Execution Progress`, `Closure Progress`, or `Controller Progress` are **wait-extension evidence only** until the real artifact/result exists.

### Controller Verification Rule

A child agent's final message is never sufficient by itself.
Always verify on disk before accepting claimed progress.

Inspect the relevant artifacts:

- plan file for planning
- git diff/status and touched files for execution
- direct test or gate output when claimed
- source matrix or closure doc updates when row closure is claimed
- breakdown ledger updates for closure
- final program verdict in the breakdown for final acceptance

If claimed progress is not visible on disk, treat the step as no-progress.

---

## Plan Preparation

### Reusable Plan Rule

Reuse an existing doc-scoped plan for the current session when all are true:

- the plan file exists at the intended session path
- it belongs to the current doc
- it is not obviously stale against the current breakdown entry
- it still contains explicit scope, tests, gates, done criteria, and scope guard
- when the row mentions devices, simulators, real-network, relay, multi-relay, three-party, or OS notification evidence, it contains an explicit `Device/Relay Proof Profile`

If these hold, do not rerun planning.
Go straight to execution.

### Execution-Safe Contract Rule

If no reusable plan exists yet, the current session may still be execution-safe from the breakdown entry itself only when all are true:

- the session classification is `implementation-ready`, `evidence-gated`, or `acceptance-only`
- the session entry has exact scope
- the session entry lists likely code-entry files
- the session entry lists likely direct tests or regressions
- the session entry lists likely named gates or explicitly says none apply
- the dependency state is explicit and currently satisfied
- the matrix or closure docs to update are named
- the session entry does not record unresolved structural blockers

In implementation-committed gap-closure mode:

- treat `acceptance-only` as execution-safe only for non-row closure/admin work or for a row already updated to `Closed` or `Covered`
- do not treat a row-owned unresolved gap as execution-safe under `acceptance-only`

### Planning Step

If a reusable plan does not exist:

- spawn one fresh `$implementation-plan-orchestrator` agent
- hand it only:
  - the breakdown artifact path
  - the current session row and session breakdown entry
  - the intended plan path
  - the instruction to include a `Device/Relay Proof Profile` whenever required
  - the instruction to use the intended plan file as the only planning progress artifact once enough initial context is gathered

If the spawned attempt does not leave an execution-safe plan, perform the single `Local Plan Fallback`.

### Local Plan Fallback

Use this only when:

- the current session still has no reusable plan
- the spawned planning step did not leave trustworthy planning progress
- the breakdown entry is already execution-safe

The fallback is bounded and artifact-only:

1. read the current session breakdown entry
2. read the breakdown's closure bar and source of truth
3. write the intended doc-scoped plan file with the minimum sections needed for execution safety
4. include a `Device/Relay Proof Profile` when required
5. return to normal plan verification

Do not use this fallback to execute code or close docs.
If it still does not leave an execution-safe plan, the session is blocked.

---

## Device / Relay Proof Profile Rule

Before planning or executing any session whose row mentions Flutter devices, simulators, device-lab, paired devices, multi-device, three-party proof, real-network, relay, multi-relay, OS push / notification state, `integration_test`, or `group-real-network-nightly`, classify the `Device/Relay Proof Profile` from the current session entry plus the source matrix, `test-inventory.md`, and gate definitions referenced by the breakdown.

Record the profile in the session plan before execution.
The profile must say:

- whether the row is `host-only`, `single-device`, `paired-device`, `three-party/device-lab`, `multi-relay`, `os-notification-device-lab`, or `external-fixture-blocked`
- the live device availability check used for this run, preferably `flutter devices --machine`; add `xcrun simctl list devices available` for iOS rows and `adb devices` for Android paired-device rows
- the exact device ids, simulator ids, script arguments, or environment variables to use
- whether the device run is required closure evidence or only supporting gate evidence
- whether a single `FLUTTER_DEVICE_ID` is sufficient for this row or only selects the Flutter host target

Default configured values when current docs do not provide a more specific command:

- single iOS Flutter target:
  `FLUTTER_DEVICE_ID=347FB118-10D0-40C8-A05B-B0C3BD6B8CCD`
- primary iOS paired-device proof:
  `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD` and `5BA69F1C-B112-47BE-B1FF-8C1003728C8F`
- spare iOS validation target:
  `1B098DFF-6294-407A-A209-BBF360893485`
- primary Android paired-device proof:
  `emulator-5554` and `emulator-5556`
- group real-network relay addresses:
  `MKNOON_RELAY_ADDRESSES=/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g`

Use the row-specific command form from the current docs when it exists.
For paired, three-party, CLI-peer, OS-permission, or multi-relay rows, do not treat a green single `FLUTTER_DEVICE_ID` gate as complete closure evidence unless the row's own closure bar says single-device proof is sufficient.
If the needed paired, three-party, CLI-peer, OS-permission, or multi-relay fixture is unavailable, record an exact fixture blocker instead of overclaiming closure.

Do not assume default ids or live devices are present.
If the live availability check does not show required devices, update the profile to `external-fixture-blocked` with the missing ids or simulator names before execution.
If a reusable plan has a device/relay profile but no current availability check, refresh the profile before executing it.

---

## Dirty Worktree And Scope Guard

Before each session execution, record `git status --short`.

After execution:

- inspect changed files
- verify they match the current session's scope
- do not revert unrelated user changes or prior-session changes
- if execution introduces changes outside the current session scope, require closure review to classify them as intentional, harmless, or blocking before accepting the session

---

## Execution

For an execution-safe current-session plan:

- spawn one fresh `$implementation-execution-qa-orchestrator` agent
- hand it only:
  - the current session plan path
  - the current session row when needed for orientation
  - the instruction to update `## Execution Progress` in the current plan before and after major execution phases
  - when the plan contains a `Device/Relay Proof Profile`, the instruction to verify live device availability first and then run the exact profile commands and inline environment variables

If the spawned attempt does not leave a trustworthy finished execution result, perform the single `Local Execution Fallback`.

### Implementation-Committed Discovered-Gap Rule

In implementation-committed gap-closure mode, when execution discovers a missing implementation surface, classify it before closure:

- `implementation-owned gap` -> reclassify to `needs_code_and_tests`, persist the correction, and return once to Plan Preparation
- `prerequisite-owned gap` -> record exact dependency, mark `skipped_due_to_dependency` or `prerequisite-blocked`
- `external-fixture blocker` -> record exact blocker honestly

A row-specific blocker is not by itself a reason to stop the whole rollout while later independent sessions remain runnable.

### Same-Session Recovery Rule

In implementation-committed gap-closure mode, a current-session implementation-owned blocker is not terminal until same-session recovery is exhausted.

Use this rule when the blocker is still inside the current row's owner files or tests, including focused test failures, `qa_blocking_issue`, incomplete scoped implementation, or partial current-row code/test deltas.

Before recording a controller stop state or moving to later sessions:

1. write a `Recovery Input` note in the session plan with blocker class, failing tests, missing contract, touched owner files, and a blocker signature
2. return to Plan Preparation for the same session
3. spawn a fresh planner to tighten the same session plan around that blocker
4. spawn fresh Execution + QA for the tightened plan
5. proceed to closure only after Execution + QA returns an acceptable verdict

Allow at most **two same-session recovery passes per distinct blocker signature**.
If the same signature still blocks after two recovery passes, record the session as blocked.
A genuinely different implementation-owned signature gets its own two-pass budget.

Do not use same-session recovery for prerequisite-owned blockers, external-fixture blockers, unsupported product scope, or unsafe dirty state that cannot be repaired inside the current row.

### Local Execution Fallback

Use this only when:

- the current session already has an execution-safe plan
- the spawned execution attempt did not leave a trustworthy execution result or trustworthy current-session code/test/doc progress

The fallback is bounded and current-session-only:

1. reuse the current session plan
2. locally apply the `$implementation-execution-qa-orchestrator` contract against that plan
3. stop as soon as the current session reaches a finished execution verdict or a real block

In implementation-committed gap-closure mode, this fallback is **verification-only** unless degraded local continuation mode was explicitly allowed.
The controller may inspect diffs, run tests or gates, verify artifacts, write execution notes, or record a blocker, but it must not write product code, migrations, or test code itself.

If the local execution fallback still does not produce a finished execution verdict, the current session is blocked.

---

## Session Closure

For a current session that finished execution acceptably:

- spawn one fresh `$implementation-closure-audit-orchestrator` agent
- hand it only:
  - the current session plan path
  - the current execution result
  - the breakdown artifact path
  - the instruction to maintain current-session `Closure Progress` entries before long audit, write, or review work

If the spawned attempt does not leave a trustworthy closure result, perform the single `Local Closure Fallback`.

### Local Closure Fallback

Use this only when:

- the current session finished execution acceptably
- the spawned closure attempt did not leave a trustworthy closure result

The fallback is bounded and current-session-only:

1. reuse the current session plan and execution result
2. locally apply the `$implementation-closure-audit-orchestrator` contract for that session
3. stop as soon as the current session gets a trustworthy closure result or a real block

If the local closure fallback still does not leave a trustworthy closure result, the session is blocked.

---

## Resolution Without Execution

Use this path for `stale/already-covered` sessions.

The controller must:

1. verify the cited current repo evidence still exists
2. verify the source matrix or closure doc is already compatible with that evidence, or update it with concrete file-and-test evidence when this rollout owns that doc
3. update the breakdown ledger as `stale/already-covered`
4. skip planning and execution for that session

Do not spawn an execution agent for an already-covered session unless current repo evidence contradicts the classification.

---

## Evidence-Gated Sessions

For an `evidence-gated` session, resolve the evidence state before accepting the session.

Allowed outcomes:

- current repo evidence proves the row is covered -> record concrete file-and-test evidence and close the session
- current repo evidence proves tests or code are missing -> reclassify the session to `implementation-ready` and continue through planning / execution
- proof depends on repo-external harnesses, raw protocol capture, device-lab orchestration, or non-Flutter-owned validators -> record the blocker and leave the session `blocked` or `prerequisite-blocked`

Do not accept an evidence-gated session with vague follow-up language.

---

## Bounded Recovery Model

Keep recovery simple and bounded.

For each session, allow at most:

1. one spawned planning attempt when planning is needed
2. one bounded local plan fallback only if the spawned planning step fails to leave a reusable execution-safe plan
3. one spawned execution attempt
4. one bounded local execution fallback only if the spawned execution step fails to leave a trustworthy current-session execution result or trustworthy code/test/doc progress
5. one spawned closure attempt
6. one bounded local closure fallback only if the spawned closure step fails to leave a trustworthy ledger/doc update

Implementation-committed code-writing exception:
when an execution plan requires code or test changes and the first execution child no-progresses, spawn **one fresh narrower execution child** before using local execution fallback.
This is the only allowed extra execution spawn for the session.

Same-session implementation-owned recovery is the only other bounded exception, and only under the Same-Session Recovery Rule.

After the session loop, allow:

7. one spawned final program acceptance / closure attempt
8. one bounded local final acceptance / closure fallback only if that step no-progresses

Do not add any other session-level retry tiers.

---

## Bounded Wait Rule

Do not wait indefinitely on spawned planning, execution, closure, or final acceptance agents.

For each spawned step:

1. wait for a bounded interval
2. during that interval, poll current-session artifacts at least once before timeout
3. inspect whether trustworthy current-session progress landed on disk
4. if the child is still running without a final result:
   - allow at most one additional bounded wait only when the first interval produced real current-session progress
   - otherwise close the child and move to the matching single local fallback

Planning exception:
if a fresh planning child produces no intended plan file after the first wait, send one concise progress request naming the intended plan path and asking it to either write `Status: planning-intake` plus `Planning Progress`, return a blocker, or finish the plan.
Allow one additional bounded wait for that communication.

Once a planning file exists, extend waits based on meaningful artifact activity rather than a fixed count.
Meaningful activity includes status movement, new files inspected, role boundary updates, reviewer findings, arbiter decisions, or mandatory section content.
If the plan file exists but is unchanged across a bounded poll, send one concise progress request asking the planner to update `Planning Progress`, return a blocker, or finish.
Close the planner only if it fails to update after that request.
A draft remains wait-extension evidence only; it is not executable until it satisfies the Reusable Plan Rule.

For planning, a changing intended-plan draft counts as current-session progress only for wait-extension decisions, not as an execution-safe plan.

Execution exception:
if an execution child produces no code/test/doc delta, no test/gate result, and no `Execution Progress` update after a bounded wait, send one concise progress request asking it to update `Execution Progress`, return a blocker, or finish.
If it still no-progresses, close it and use the allowed fallback path.

Do not leave the pipeline controller parked on a running child when nothing current-session-relevant is changing.

---

## Controller Progress Retention

`## Controller Progress` is a rolling live-status section, not a permanent audit log.

Keep at most the latest **8** controller progress entries.
Before writing a new entry, remove older progress entries beyond that limit.

Do not delete durable evidence such as:

- session plans
- session execution results
- session closure records
- source matrix rows
- test inventory entries
- final program verdicts

---

## Large Breakdown Rule

If the breakdown is large enough that one controller pass is likely to exceed a reasonable turn, token, or wait budget, still prefer visible main-controller orchestration over nested continuation controllers.

Strong default:
when the recommended plan count is greater than `20`, assume the main controller will process many sessions through repeated visible planner / executor / closure child spawns.
Do not spawn a continuation controller solely because the breakdown is large.

For large breakdowns:

- keep per-session chat output minimal
- rely on persisted artifacts as the source of truth between visible child phases
- continue automatically until the final program verdict exists or a real blocker prevents further safe progress
- use a handoff-only continuation controller only when the main controller is genuinely near context exhaustion or otherwise cannot safely continue visible orchestration

---

## Continuation Rule

When unresolved runnable sessions remain and no real blocker exists, the controller must continue the pipeline instead of returning a partial progress-only summary.

Preferred path:

1. the main controller keeps ownership of visible orchestration
2. for each current session, the main controller directly spawns the fresh planner, executor, closure, and final-acceptance children required by the isolation contract
3. after each child returns or produces progress, the main controller verifies on-disk artifacts before starting the next phase
4. after each session closes or blocks, the main controller selects the next runnable session and repeats the visible child sequence
5. continue until a final program verdict is persisted or a real blocker is recorded

Use a continuation controller only as a **last-resort handoff** when the main controller is genuinely near context exhaustion or cannot safely continue locally.
A continuation controller must be handoff-only by default.

Do not:

- return after one or a few accepted sessions merely because the turn is getting long
- tell the user “the next runnable session is X” as the normal successful stop point when runnable sessions still remain
- require the user to rerun the same pipeline command after an ordinary checkpoint when the main controller can continue
- treat “not finished in this turn” as an acceptable success-path reason to end the pipeline

If the environment truly cannot keep continuing, record that honestly as a real blocker or unfinished final verdict state.

---

## Session Completion Gate

Advance to the next session only when the current session reaches one of:

- `accepted`
- `accepted_with_explicit_follow_up`
- `stale/already-covered`
- `skipped_due_to_dependency`

In implementation-committed gap-closure mode:

- a row-owned session may advance as `accepted` only when its source row has been updated to `Closed` or `Covered`
- do not advance a row-owned unresolved gap as `accepted_with_explicit_follow_up`

If the current session remains blocked:

- first apply the discovered-gap classification rule when that mode is active
- if the blocker is implementation-owned, apply the Same-Session Recovery Rule before recording a hard blocked state or moving to later sessions
- if the session still remains blocked after recovery is exhausted, record it honestly in the ledger and continue with later independent runnable sessions only when the current dirty state is safe for them

Do not set the next runnable row to none solely because the current row is blocked unless no later session can proceed safely.

---

## Ledger Update

For each processed session, record:

- current status
- plan file path
- final execution verdict when known
- closure docs touched
- blocker class when blocked
- concise note

---

## Final Program Acceptance

After all runnable sessions are resolved:

- run `Ledger Sanity Check` again
- if accepted row-owned sessions still disagree with the source matrix, reopen them and return to the session loop
- otherwise spawn one fresh final acceptance / closure agent
- hand it only:
  - the breakdown artifact path
  - the stable closure and matrix docs touched by this rollout

If the spawned attempt does not leave a trustworthy final program verdict, perform the single `Local Final Acceptance Fallback`.

### Local Final Acceptance Fallback

Use this only when:

- all runnable sessions are already resolved for the current doc
- the spawned final acceptance step did not leave a trustworthy final program verdict
- no ledger sanity mismatches still exist between the row-owned session ledger and the source matrix

The fallback is bounded and doc-only:

1. reuse the current breakdown artifact
2. reuse the stable closure and matrix docs already touched by the doc
3. locally apply the final program acceptance / closure review once

If the local final acceptance fallback still does not leave a trustworthy final program verdict, the doc remains `still_open`.

---

## Final Program Verdicts

The final program verdict must be exactly one of:

- `closed`
- `accepted_with_explicit_follow_up`
- `residual_only`
- `still_open`

Use:

- `closed` when the overall closure bar is met with no meaningful deferred work
- `accepted_with_explicit_follow_up` when the closure bar is met and the remaining items are explicitly non-blocking
- `residual_only` when no broad program should reopen and only one narrow residual remains
- `still_open` when any required session remains blocked, any required closure result is missing, or the closure bar is not yet met

In implementation-committed gap-closure mode:

- use `closed` only when every row-owned source row is updated to `Closed` or `Covered`
- do not use `accepted_with_explicit_follow_up` or `residual_only` while any row-owned source row remains `Open`, `Partial`, or `Contract-undefined`
- keep the final verdict `still_open` until every required gap row is actually closed

---

## Resume Rule

On every resume, run `Ledger Sanity Check` before selecting the next session.
This includes the implementation-committed blocked-row reclassification rule above, even when no final program verdict exists yet.

If the breakdown already contains a final program verdict, rerun ledger sanity before reporting completion.

If the verdict is still consistent with the source matrix, closure docs, and current repo evidence, report the rollout as already complete.

If the verdict is stale:

- remove or supersede the stale verdict
- reopen affected sessions
- persist the correction
- continue the normal session loop

---

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

Do not emit the final output format until:

- the breakdown has a persisted final program verdict
- or continuation is no longer possible because of a real blocker

A mere “processed N sessions so far” checkpoint is not a valid success-path final output.

---

## Guardrails

- Do not fully detailed-plan all sessions up front.
- Do not rerun planning when a reusable current-session plan already exists.
- Do not rerun execution against a missing or unsafe plan.
- Do not invent extra session-level retry tiers.
- Do not silently collapse the whole pipeline into one giant shared context.
- Do not trust stale accepted row-owned ledger state without reconciling it against the source matrix.
- Do not downgrade unresolved row-owned sessions into `acceptance-only`, docs-only, or evidence-only closure in implementation-committed gap-closure rollouts.
- Do not stop the pipeline after the first accepted session or the first partial ledger delta when later sessions remain unresolved.
- Do not stop the pipeline just because the current controller turn is long when the main controller can continue through visible per-phase child agents.
- Do not stop solely because fresh-child isolation no-progressed if the user explicitly opted into degraded local continuation mode and no real blocker exists.
- Do not present “next runnable session is X” as the final successful outcome while unresolved runnable sessions remain.
- Do not treat per-session execution acceptance as automatic proof that the whole doc is closed.
- Do not reopen accepted differences from the decomposition unless a real landed regression forces it.
- Do not change doc-scoped plan paths into shared generic paths.
- Do not let child agents for planning, execution, closure, or final acceptance accumulate multiple sessions' work in one context when fresh child agents are available.
