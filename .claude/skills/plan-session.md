---
description: Plan a session task using sequential Evidence Collector, Planner, Reviewer, and Arbiter agents
user-invocable: true
---

# Session Planning Skill

You are planning **$ARGUMENTS**.

Do NOT implement any app code. This skill produces a plan only.

## Step 0: Gather Context

Read the following files to understand the current project state:

- `Test-Flight-Improv/00-INDEX.md` (master index)
- `Test-Flight-Improv/test-gate-definitions.md` (gate contracts)
- `Test-Flight-Improv/17-roadmap-closure-audit.md` (closure status)
- `Test-Flight-Improv/14-regression-test-strategy.md` (regression strategy)

Then find and read whichever of these are relevant to **$ARGUMENTS**:

- Session plans: `Test-Flight-Improv/session-*-plan.md`
- Closure references: `Test-Flight-Improv/*-closure-reference.md`
- Use case audits: `Test-Flight-Improv/*-use-case-audit.md`, `Test-Flight-Improv/*-reliability-audit.md`
- Roadmap docs: `Test-Flight-Improv/*-roadmap*.md`, `Test-Flight-Improv/Prompt-Roadmap-*.md`
- Network docs: `Test-Flight-Improv/*-network-*.md`

Identify the exact production files, test files, and infrastructure files relevant to **$ARGUMENTS** by searching `lib/`, `test/`, `integration_test/`, `go-mknoon/`, and `go-relay-server/`.

## Step 1: Evidence Collector Agent

Launch an agent (subagent_type: `Explore`) with thoroughness `very thorough`.

Task for the Evidence Collector:

> You are gathering evidence for planning: **$ARGUMENTS**
>
> Search the codebase for ALL relevant:
> 1. Production code paths (in `lib/`)
> 2. Test coverage (in `test/` and `integration_test/`)
> 3. Go code (in `go-mknoon/` and `go-relay-server/`) if relevant
> 4. Related docs in `Test-Flight-Improv/`
>
> For each file found, note:
> - What it does
> - What behavior it pins (for tests)
> - What gaps exist vs the docs/audits
> - Whether it is a regression test, unit test, integration test, or e2e test
>
> Also check:
> - Are there known failures documented in `Test-Flight-Improv/test-gate-definitions.md`?
> - Are there open TODOs or FIXMEs in the relevant code?
> - What does git log show for recent changes in these files?
>
> Return a structured evidence report with:
> - **production files**: path, purpose, key behaviors
> - **test files**: path, what they cover, what they miss
> - **doc files**: path, what they claim, whether code matches
> - **gaps**: what the docs/audits say should exist but doesn't
> - **known failures**: pre-existing test failures relevant to this area
> - **recent changes**: relevant recent git commits

**WAIT for this agent to fully complete before proceeding.**

## Step 2: Planner Agent

Launch a Plan agent (subagent_type: `Plan`).

Pass it the full evidence report from Step 1, plus this task:

> You are creating an implementation plan for: **$ARGUMENTS**
>
> Use the evidence report below to create a plan with ALL of the following sections. Every claim must cite a specific file path or test name from the evidence.
>
> Evidence report:
> [paste full evidence report from Step 1]
>
> ## Required Plan Sections
>
> ### 1. Real Scope
> - Exactly what is changing
> - Exactly what is NOT changing
>
> ### 2. Closure Bar
> - What "good enough" means for this area in the current architecture
> - What the user should be able to trust after this work lands
>
> ### 3. Source of Truth
> - Which docs are authoritative
> - Which tests/gates are authoritative
> - If docs disagree with code/tests, say what wins
>
> ### 4. Session Classification
> Choose exactly one: `implementation-ready` | `evidence-gated` | `acceptance-only` | `stale/already-covered` | `prerequisite-blocked`
>
> ### 5. Exact Problem Statement
> - What is broken, missing, or risky
> - What user-visible behavior must improve
> - What behavior must remain unchanged
>
> ### 6. Files and Repos to Inspect Next
> - Exact production files
> - Exact tests
> - Exact infra / Go / config files if relevant
>
> ### 7. Existing Tests Covering This Area
> - What is already covered
> - What is missing
> - What current tests pin as intentional behavior
>
> ### 8. Regression/Tests to Add First
> - The direct regression or proof to add before implementation
> - Why it proves the exact seam being changed
>
> ### 9. Step-by-Step Implementation Plan
> - Smallest coherent steps
> - Do not bundle unrelated fixes
> - Note where the plan should stop if evidence disproves the need
>
> ### 10. Risks and Edge Cases
> Only include what is relevant from:
> - pause/resume, offline/online transition, duplicate sends, stale local state
> - missing files, upload succeeds but publish fails
> - foreground vs background recovery, auth/enforcement drift
>
> ### 11. Exact Tests and Gates to Run
> - Exact direct tests
> - Exact named gates from `test-gate-definitions.md`
> - When `baseline`, `groups`, `1to1`, `feed`, `posts`, or `transport` gates are required
> - Any Go/module-local test commands if needed
>
> ### 12. Known-Failure Interpretation
> - How to treat pre-existing known failures from the gate definitions
> - How to avoid misclassifying old red tests as new regressions
>
> ### 13. Done Criteria
> - Concrete, checkable exit conditions
> - No vague wording
>
> ### 14. Scope Guard
> - Explicit non-goals
> - What would count as overengineering
> - What must not be changed in this session
>
> ### 15. Accepted Differences / Intentionally Out of Scope
> - Especially important when comparing architectures (1:1 vs group)
> - List differences that are real but not bugs for this session
>
> ### 16. Dependency Impact
> - What later work depends on this plan
> - What should be skipped or revisited if this plan changes
>
> Planning rules:
> - Use concrete repo evidence. Name files and tests.
> - Prefer the smallest coherent implementation slice.
> - Do not broaden into product-scope work unless the task explicitly requires it.
> - If the repo already covers the gap, say so.
> - If the work is better treated as evidence-only or acceptance-only, say so.
> - Distinguish true correctness/reliability gaps from acceptable architectural differences.

**WAIT for this agent to fully complete before proceeding.**

## Step 3: Reviewer Agent

Launch a general-purpose agent.

Pass it the full plan from Step 2, plus this task:

> You are a strict sufficiency reviewer for the plan below.
>
> Plan:
> [paste full plan from Step 2]
>
> Do a strict sufficiency review. Answer each question:
>
> 1. **Sufficient as-is, sufficient with adjustments, or insufficient?**
> 2. **What files, tests, regressions, or gates are missing?** — Search the codebase to verify claims.
> 3. **What assumptions are stale or incorrect?** — Check that cited files exist and contain what the plan says.
> 4. **What is overengineered?** — Flag anything that goes beyond the smallest coherent slice.
> 5. **Is the work decomposed enough to minimize hallucination during implementation?**
> 6. **What is the minimum needed to make the plan sufficient?**
>
> For each finding, cite the specific file path or test name.
>
> Return a structured review with:
> - **verdict**: sufficient / sufficient-with-adjustments / insufficient
> - **missing items**: list with file paths
> - **stale assumptions**: list with evidence
> - **overengineered items**: list with reasoning
> - **decomposition issues**: list
> - **minimum fixes needed**: prioritized list

**WAIT for this agent to fully complete before proceeding.**

## Step 4: Arbiter Agent

Launch a general-purpose agent.

Pass it the plan from Step 2 and the review from Step 3, plus this task:

> You are the Arbiter. Classify every finding from the Reviewer into exactly one category:
>
> Plan:
> [paste full plan from Step 2]
>
> Review:
> [paste full review from Step 3]
>
> ## Categories
>
> **Structural blockers** = wrong source of truth, wrong scope, wrong execution order, missing regression-first rule, missing gate/test contract, missing closure bar, missing stop rule, or another issue that would make implementation unsafe.
>
> **Incremental details** = wording cleanup, one more candidate file, one more optional test, or another non-structural refinement.
>
> **Accepted differences** = a real architectural difference or deferred product-scope item that should be documented, not "fixed" in this session.
>
> ## Output
>
> 1. **Structural blockers**: list each with classification reasoning
> 2. **Incremental details**: list each (these are intentionally deferred)
> 3. **Accepted differences**: list each (these are intentionally left unchanged)
> 4. **Verdict**: Are there structural blockers? (yes/no)

**WAIT for this agent to fully complete before proceeding.**

## Step 5: Patch Loop (if needed)

If the Arbiter found structural blockers:

1. Patch the plan from Step 2 to address ONLY the structural blockers. Do not rewrite the entire plan.
2. Run one more Reviewer pass (same instructions as Step 3) on the patched plan.
3. Run one more Arbiter pass (same instructions as Step 4) on the patched plan + new review.
4. Stop. Do not loop again even if incremental details remain.

If the Arbiter found NO structural blockers, skip this step entirely.

## Step 6: Final Output

Present the final output to the user with these sections:

### Final Verdict
`sufficient` | `sufficient with explicit follow-up` | `insufficient`

### Final Plan
The complete plan (patched if Step 5 ran, original if not).

### Structural Blockers Remaining
List any that could not be resolved, or "None".

### Incremental Details Intentionally Deferred
List from Arbiter classification.

### Accepted Differences Intentionally Left Unchanged
List from Arbiter classification.

### Evidence Sources
Exact docs and files used as evidence.

### Safety Assessment
Why the plan is safe or unsafe to implement now.
