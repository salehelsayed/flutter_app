---
name: tdd-review
description: "Run an independent, source-grounded counterexample audit of an existing TDD implementation plan before execution. Discover repository and Graphify conventions; verify evidence, causal tests, scope, gates, real boundaries, compatibility, and reversibility; then report ready, plan-fixes-required, or not-ready."
---

# TDD Review

## Overview

Audit an existing TDD plan from a fresh adversarial angle before code is
written. `$tdd-plan` constructs a contract; `$tdd-review` treats that contract
as a set of claims and tries to falsify its load-bearing facts, tests, gates,
scope, and closure proof.

Do not recreate the planner's full checklist or rewrite the plan by default.
Produce a concise, evidence-backed delta: what is false, what can pass for the
wrong reason, what is missing, and what remains sound.

Default to read-only work. Static source/manifests/gate inspection and an
authorized read-only Graphify query are permitted. Do not execute tests,
gates, benchmarks, Graphify builds/updates, or environment scenarios; refresh
Graphify; edit the plan; write a fix-list; update an index; or save project
memory unless the user explicitly authorizes that action.

## Invocation Guard

Proceed only when the current user message affirmatively names `$tdd-review`.
Task similarity, an existing plan, a prior recommendation, or invocation of
`$tdd-plan` is not permission. Permission for `$tdd-review` does not authorize
another skill.

## Required References

Read these bundled files at the named steps:

- `references/project-discovery.md`: read in Step 0.
- `references/review-dimensions.md`: read before applying the five lenses.
- `references/evergreen-blindspots.md`: read before the risk-trigger sweep.
- `references/audit-workflow.md`: read before selecting workers and before
  emitting a report or fix-list.

## Step 0 - Resolve Repository Conventions And The Plan

Read `references/project-discovery.md` and all applicable repository
instructions. Resolve and record the repository root plus the selected plan
root, defaulting to `<repository-root>/docs/tdd/`. Interpret relative paths
from the repository root, not the current shell directory.

Resolve the input:

- Explicit path: read the named plan in full.
- Bare identifier: use the documented selected plan root, otherwise
  `<repository-root>/docs/tdd/`, and match the exact identifier/stem under its
  naming convention. Exclude indexes, fix-lists, review reports, session files,
  and other non-plan artifacts. On zero matches, perform one targeted plan-file
  search; on multiple matches, ask one focused question.
- Pasted plan: audit it in place and note that plan-file line links are absent.
- Empty request: identify the most recently modified actual TDD plan in the
  selected root, excluding indexes/fix-lists/reports/session artifacts, and
  confirm it with the user before auditing.

Record the plan's declared status, classification, type, highest proof
boundary, and risk triggers. Respect `implementation-ready`,
`evidence-gated`, `acceptance-only`, `stale-already-covered`, and
`prerequisite-blocked` when present. Normalize a legacy or differently
formatted plan into a conceptual Test Contract without demanding format-only
edits.

If the request or repository policy authorizes Graphify, follow the adapter in
`references/project-discovery.md`. Reuse a plan's graph snapshot only as
anchors and verify every load-bearing fact in current source. Otherwise use
targeted source discovery and record `Graphify: N/A - not authorized or
unavailable`. If stale or missing output blocks navigation, use source and
report the limitation. Do not refresh during a read-only review.

## Step 1 - Extract The Load-Bearing Contract

Extract only claims whose failure would change the implementation seam, proof
level, scope, closure verdict, or release decision:

- confirmed cause for a bug, confirmed gap for new behavior, or source/test
  proof for stale/already-covered work;
- each behavior, named proof, honest baseline, expected GREEN outcome,
  meaningful counterfactual/mutation for causal or preservation contracts (or
  source-backed `N/A`), literal command or reproducible proof procedure, and
  discovery/registration where applicable;
- preservation sentinels, hard exclusions, accepted differences, deferred
  owners, and stop-if conditions;
- intended implementation seam plus plausible wrappers, direct operations,
  alternate entrypoints, and lifecycle paths;
- highest-risk technical mechanism and fallback;
- triggered persistence, schema/format, external-service, network,
  process/thread/worker, browser, native/OS, device/hardware, security,
  compatibility, migration, destructive, or irreversible claims;
- quantitative baseline, sample method, and threshold only when the goal is
  genuinely quantitative;
- product or release decisions that source cannot resolve;
- focused/affected/broad gate cadence according to repository policy.

Verify every load-bearing citation. Spot-check supporting citations unless a
contradiction makes them material. Search both the shared wrapper and plausible
direct/raw operation for bypasses, including API, UI, CLI, worker, scheduler,
callback, startup, generated, plugin, native, or alternate-configuration paths
when relevant. Do not enumerate unrelated adjacent features for ceremony.

## Step 2 - Run The Counterexample Audit

Read all three audit references. Use the bounded topology in
`references/audit-workflow.md`:

- one fresh factual/counterexample verifier by default when agents are
  available;
- one domain specialist only for an uncertain dependency, platform, protocol,
  security, or external technical bet;
- one boundary/reversibility specialist only for migration, destructive or
  irreversible data, compatibility, process/runtime, OS/device, external
  service, or real-environment risk;
- main-agent synthesis and linchpin verification.

Use at most three workers. Never assign one worker per review lens. If agents
are unavailable, perform the same independent passes sequentially.

Try to answer five questions:

1. Can the Test Contract pass with a no-op, wrong handler/event/entity,
   unrelated failure, partial update, stale cache, or inert mutation?
2. Is the claimed cause, gap, stale disposition, or highest-risk bet false or
   unresolved?
3. Does a real caller, entrypoint, configuration, or lifecycle path bypass the
   planned seam?
4. Would the literal commands or procedures discover and execute the named
   proof, and does the closure level exercise the boundary actually claimed?
5. Could rollback, destructive effects, compatibility, concurrency, ordering,
   retry, duplicate work, restart, or an unresolved user decision invalidate
   the plan?

Broad-suite success does not replace focused causality. Judge gate breadth and
cadence against the destination repository's actual policy rather than
importing one from another project.

## Step 3 - Self-Verify Material Findings

Do not promote a worker result, graph inference, or suspicion directly to a
blocker. Verify its linchpin in current source, tests, gate definitions,
manifests, or authoritative version-matched dependency documentation:

- false cause/current gap or stale classification;
- vacuous baseline, GREEN assertion, mutation, negative assertion, or event
  discriminator;
- bypass site or off-target symbol/line;
- missing/incorrect discovery, registration, working directory, or command;
- rollback, migration, compatibility, concurrency, or real-boundary hazard.

Classify unproven concerns `unresolved - verify before execution`, not factual
errors. Never claim RED/GREEN evidence that was not run. By default, verify
command definitions, selectors, discovery, and registration statically; do not
run tests, gates, benchmarks, builds, or environment proof. If the user
authorizes live diagnostic proof, report its results separately from the
source audit and disclose artifacts or external state it touched.

## Step 4 - Decide The Verdict

Use exactly one verdict:

- `ready`: safe to begin the plan's declared execution or verification; no
  required plan delta remains.
- `plan-fixes-required`: the direction may be sound, but bounded plan edits
  must land before execution.
- `not-ready`: a core bet is refuted or unresolved, the required real-boundary
  strategy is absent, a user decision blocks the contract, or replanning is
  required.

Also state:

- core bet: `confirmed`, `refuted`, `unresolved`, or `N/A`;
- disposition: `execute`, `apply-plan-fixes`, `verify-and-close-stale`, or
  `replan`.

Map findings deterministically:

- any self-verified `blocker` or `block` -> `not-ready`;
- otherwise any `plan-fix` or `tighten` -> `plan-fixes-required`;
- only `clear`/`N/A` lenses plus optional notes -> `ready`.

Use `execute` with `ready`, `apply-plan-fixes` with
`plan-fixes-required`, `verify-and-close-stale` for an obsolete implementation
plan, and `replan` for other `not-ready` results.

For `stale-already-covered` and `acceptance-only`, judge the honesty and
sufficiency of the verification contract. Do not demand invented RED tests,
mutations, causes, or production edits. If an implementation-ready plan is
proven already covered, use `not-ready` with `verify-and-close-stale` because
obsolete production steps are unsafe to execute.

For a correctly classified stale/already-covered or acceptance-only plan,
`ready` plus `execute` means execute its verification contract only, never its
production-edit steps.

Apply the five lens states as `clear`, `tighten`, `block`, or `N/A`. Do not emit
numeric scores unless the user explicitly requests scoring.

## Step 5 - Surface User-Owned Decisions

Report findings first. Ask only decisions that materially change the contract
and cannot be answered from source: product behavior, irreversible
release/rollback strategy, accepted compatibility, or a genuinely quantitative
threshold. Do not ask the user to choose facts, obvious source-backed fixes, or
the next output format.

If a required user decision remains open, state it under findings and use
`not-ready` until it is resolved.

## Step 6 - Emit Without Unrequested Writes

Read `references/audit-workflow.md` and return its concise chat report by
default. Findings name the plan target, evidence, counterexample/consequence,
and smallest sufficient correction. Report blind-spot hits plus one summary
for the remaining clear/N/A classes; emit a full table only when requested.

Write a fix-list only when the user requests one. Unless repository
instructions specify another location, place it beside the plan as
`<plan-stem>-review-fixlist.md`. Edit the plan only on an explicit
revise-in-place request; patch source-backed deltas and rerun the five lenses
plus every triggered blind-spot class. Index, memory, Graphify, and other
project writes require separate authorization.
