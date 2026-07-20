---
name: tdd-plan
description: "Create source-grounded, project-adapted TDD implementation plans for bugs, features, modifications, migrations, and reliability gaps. Discover the repository's Graphify interface, test levels, fixtures, gates, and registration; map each behavior to causal proof or a justified real-boundary proof; and hand an execution-ready contract to implementation."
---

# TDD Plan

## Overview

Create a rollout-ready TDD implementation plan for the current repository.
Design the change and its proof; do not claim RED, GREEN, mutation, benchmark,
or environment evidence that has not actually been run. Planning names the
expected baseline, GREEN outcome, counterfactual, gates, and registration.
Execution later records the results.

This handoff uses `<repository-root>/docs/tdd/` as its default plan root. When
the repository is `~/piqube`, that resolves to `~/piqube/docs/tdd/` regardless
of the shell's current subdirectory.

Use `references/sufficiency-checklist.md` as the single source of truth for
plan sufficiency. Keep the plan's Done Criteria concise instead of copying the
full checklist into every plan.

Invoking `$tdd-plan` does not authorize `$tdd-review` or an implementation
skill. Use Graphify only when the destination repository permits implicit
Graphify selection or the user also authorizes `$graphify`.

## Invocation Guard

Proceed only when the current user message affirmatively names `$tdd-plan`.
Task similarity, a plan or issue document, a prior recommendation, or a request
to continue/execute stored work is not invocation. Permission to use another
skill does not authorize this one, and permission for `$tdd-plan` does not
authorize another skill.

## Required References

Read these bundled files at the named steps; do not work from memory:

- `references/project-discovery.md`: read in Step 0.
- `references/tier-matrix.md`: read while deriving proof and fixture
  obligations.
- `references/plan-template.md`: read before emitting the plan.
- `references/sufficiency-checklist.md`: read for the blocking final check.

## Step 0 - Resolve Repository Conventions And Input

Read `references/project-discovery.md`, then read the applicable repository
instructions before browsing source. Resolve and record the repository root
from those instructions and version-control/workspace evidence. Interpret all
relative paths below from that root, not from the current shell directory.

Resolve the input:

- Explicit spec, issue, or plan path: read it in full. Preserve a stable issue
  or spec identifier in the output filename when one exists.
- Bare identifier: resolve it using the repository's documented issue/spec
  convention, then the default plan root. Ask one focused question only when
  matches are ambiguous.
- Free-text bug, feature, modification, migration, or reliability gap: ground
  it directly; a separate spec is not required.
- Too vague to identify an observable behavior, area, or symptom: ask one
  focused question.

Resolve the output directory independently from the filename:

- Directory: use an explicit output directory/file requested by the user;
  otherwise use `<repository-root>/docs/tdd/`.
- Filename: use an explicit filename, then a documented repository convention,
  then `<stable-identifier>-<slug>-tdd-plan.md`, otherwise
  `YYYY-MM-DD-<slug>-tdd-plan.md`.
- On collision, insert `-2`, `-3`, and so on immediately before
  `-tdd-plan.md`.

Never overwrite a plan silently. Creating the resolved plan directory is part
of the authorized plan write when it does not exist and repository policy does
not forbid it. Use or update an index only when one already exists or
repository instructions require it. Recheck the filename and index immediately
before saving.

Record the type (`bug`, `feature improvement`, `new feature`, `modification`,
`migration`, or `reliability`), affected area, identifier/slug, intended plan
path, classification, and highest required proof boundary.

Use these classifications when applicable:

- `implementation-ready`
- `evidence-gated`
- `acceptance-only`
- `stale-already-covered`
- `prerequisite-blocked`

## Step 1 - Ground And Classify Evidence

When the request or repository policy authorizes Graphify, follow the adapter
in `references/project-discovery.md` and use the destination repository's
Graphify skill and commands, not a command copied from this bundle. Otherwise,
use targeted source discovery and record `Graphify: N/A - not authorized or
unavailable`. A graph is a compact navigation index, never proof.

Then verify in current source:

1. Locate the production seam and plausible callers or entrypoints. Cite
   durable symbols plus `file:line` evidence.
2. Inventory existing tests at every relevant repository-defined level, the
   fixtures they use, and the gates or discovery rules that execute them.
3. Discover literal focused, affected-suite, broad-suite, and static-quality
   commands from source, manifests, task runners, or CI configuration.
4. Classify every material finding:
   - `confirmed`: current source plus a test, probe, or authoritative contract
     supports it;
   - `refuted`: contradictory evidence disproves it;
   - `unresolved`: evidence is incomplete, so the plan remains evidence-gated.
5. For a bug, identify a confirmed cause. For new behavior, identify the
   current mechanism and confirmed gap without inventing a root cause.
6. Read `references/tier-matrix.md` and derive the lowest causal proof level,
   fixture, registration, compatibility, migration, and real-boundary
   obligations.

Persist a compact `Project Convention Snapshot` and `Graph Grounding Snapshot`
using the shapes in `references/project-discovery.md`. When Graphify did not
run, the latter records the reason and targeted-source fallback. Record
material refuted and unresolved findings.

Use an independent refute pass when it can challenge a risky assumption; do
not add roles for ceremony. If current HEAD already satisfies and tests the
request, classify it `stale-already-covered`, name exact verification gates,
and do not fabricate a RED, cause, production edit, or mutation obligation.

## Step 2 - Build One Test Contract

For every spec case or grounded behavior, create one canonical row:

`Case | Behavior / invariant | Named test or proof | Level / fixture | Baseline -> GREEN | Counterfactual / mutation | Command / discovery / registration`

Rules:

- Map every behavior to a named automated test or a justified boundary/manual
  proof when automation cannot exercise the real boundary.
- Label behavior-changing rows with the honest baseline: causal RED, intended
  compile-time gap, or boundary-only proof. State the expected GREEN result.
- Label preservation-only coverage `GREEN sentinel`; do not pretend it is RED.
- Name one meaningful counterfactual or mutation per distinct behavior
  contract and the test expected to re-red. When direct mutation is unsafe or
  unsupported, name an equivalent causal perturbation and why it is adequate.
- Use the lowest repository-defined test level that can fail for the causal
  reason. Add another level only when it proves a distinct obligation.
- Require a production-equivalent fixture only when the claim depends on its
  semantics: persistence, compatibility, provider behavior, process/runtime,
  native/OS, browser, device, hardware, security, distributed coordination,
  or another external boundary.
- A manual proof needs an automation infeasibility or disproportionality reason
  under repository policy, exact setup, operator steps, observable evidence,
  success/failure interpretation, and an owner.
- The final cell contains a literal focused command or independently
  reproducible proof procedure plus concrete discovery/registration when
  applicable: verified auto-discovery, manifest, suite, tag, build target, CI
  job, matrix entry, dispatcher, or scenario registry.
- Use `N/A - <reason>` instead of an empty cell. An unproven load-bearing row
  keeps the plan evidence-gated.
- One proof may cover multiple behaviors only when each assertion and causal
  relationship is explicit.

Add detailed notes only for non-obvious setup, event/result discriminators,
fault injection, compatibility direction, or relationships that do not fit in
the table.

## Step 3 - Define Gate Strategy And Emit The Plan

Use proportionate gates based on repository policy:

- focused causal tests;
- exact preservation sentinels;
- the nearest affected suite, lane, or package gate;
- only the broader validation justified or mandated for this change.

An aggregate suite does not replace focused causality. If a full suite is cheap
or required, it may be a per-plan gate. If it is expensive and owned by CI,
integration, a batch, or release closure, name that owner and cadence instead
of inventing a universal rule. Numeric counts belong only when the repository
gate contract fixes them; otherwise state semantic outcomes such as selection,
exit status, and zero relevant failures.

Read `references/plan-template.md`, fill its core sections, create the resolved
directory if needed, and save at the Step 0 path (normally
`<repository-root>/docs/tdd/`). Update an existing required index after
rechecking for collisions.

Keep these rules:

- Put the Test Contract before implementation steps.
- Put in-scope work, preservation obligations, hard `Do not` limits, accepted
  differences, and deferred owners in one Scope Contract And Guard.
- Give literal commands with working directories when relevant and semantic
  outcomes.
- Include `## Boundary Proof Profile` only for a real environment, external
  system, compatibility matrix, process/runtime, native/OS, device/hardware,
  or manual proof obligation.
- Include migration/compatibility details only when triggered: actual source
  versions or snapshots, real engine/codec/service, before/after assertions,
  idempotency, rollback/recovery, and directionality as applicable.
- Include quantitative baselines and thresholds only for genuinely
  quantitative goals, using a comparable environment and sample method.
- Append reviewer findings or execution results only when those phases have
  actually run. Do not emit empty ceremony.

## Step 4 - Blocking Sufficiency Check

Read and apply every gate in `references/sufficiency-checklist.md`. Any `No`
leaves the plan `planning-draft` or `evidence-gated`. Patch structural gaps
before presenting it; do not paper over a missing real-boundary strategy with a
lower-level fake.

Planning records expected evidence, not execution completion. If the user
separately authorizes a preliminary command during planning, label its result
`preliminary`; it informs the plan but does not satisfy the later execution
contract or mutation/closure record.

## Step 5 - Handoff

Summarize:

- plan path, type, classification, status, and highest proof boundary;
- behavior count and Test Contract row count;
- test levels, real fixtures, manual proofs, and registration changes;
- migration, compatibility, or quantitative obligations when present;
- focused and preservation commands plus broader-gate cadence;
- first expected causal RED command, or a source-backed `N/A` for stale,
  acceptance-only, or boundary-only work;
- confirmed, refuted, and unresolved findings.

Offer `$tdd-review` as an independent counterexample audit. Run it only when
the user explicitly requests that skill.
