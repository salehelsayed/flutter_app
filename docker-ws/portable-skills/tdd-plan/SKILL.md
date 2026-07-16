---
name: tdd-plan
description: "Generate a source-verified, tier-complete, harness-integrated TDD implementation plan from EITHER an existing plan/spec doc (docs/tdd/NN-*.md) OR a free-text description of a bug / feature / modification. Produces an adversarially-verified root cause, a RED test catalog, a Test Coverage Matrix (spec-case → tier → test file → mutation revert → acceptance gate → harness registration), literal acceptance-gate commands, and a sufficiency self-check. Chains into /tdd-review. Trigger: /tdd-plan"
disable-model-invocation: true
argument-hint: "[path to a spec doc  OR  a free-text description of a bug / feature / modification]"
---

# TDD Plan Generator

You are producing a **TDD implementation plan** for: **$ARGUMENTS**

This skill designs both the fix and the tests. The plan it emits must be **sufficient**, which here has a precise meaning:

1. **Spec-case totality** — every behavior/test-case maps to ≥1 concrete test, named (file + test name), at the *right tier*.
2. **Mutation-verifiable** — every behavior-bearing production edit has a test that goes **RED on HEAD for a documented reason** and GREEN after the fix; reverting the edit re-reds it. A test that cannot fail is not coverage.
3. **Literal acceptance gates** — copy-paste commands for THIS project's test runner, with expected pass counts — never prose like "run the relevant suite".
4. **Named harness-registration per test** — for every new test, state how it actually gets executed (auto-discovered by the runner's glob / added to a suite list / registered in a CI job / wired into a scenario runner). A test that runs in no gate is invisible coverage.

The decision rules and skeleton live in bundled reference files — **READ them at the steps below; do not work from memory**:
- `references/tier-matrix.md` — spec→obligation mapping + tier-selection decision matrix + harness-registration rules
- `references/sufficiency-checklist.md` — the yes/no gates the finished plan must pass
- `references/plan-template.md` — the exact section skeleton to emit

This skill is **TDD-first**: RED tests are designed before any production edit, and every factual claim is grounded in real source before it is trusted.

---

## Step 0 — Resolve and classify the input

Decide what `$ARGUMENTS` is:

- **A path to an existing spec/plan doc** (e.g. `docs/tdd/134-foo.md`, or a bare `134`): READ it. It is your spec. **Reuse its NN number** for the plan filename (`NN-<slug>-tdd-plan.md`) so the plan sits next to its spec.
- **Free-text description** of a bug / feature / modification: this is the raw intent. You do NOT need a spec doc first — you will ground it yourself in Step 1. Allocate the **next free number** from `docs/tdd/00-INDEX.md` (create the directory and index on first use).
- **Too vague to be actionable** (no identifiable behavior, area, or symptom): ask exactly one focused clarifying question, then proceed. Do not guess a whole feature out of nothing.

Record: type (`bug` | `feature improvement` | `new feature` | `modification`), affected area, the chosen plan number `NN`, and a short kebab-case `<slug>`.

> **Path convention:** this skill defaults to `docs/tdd/` for plans and the index. If the project already keeps plans elsewhere, use that location instead and keep it consistent.

---

## Step 0.5 — Harness bootstrap (first use in a project, or when the harness map is stale)

The plan cannot contain literal gates without knowing how THIS project runs tests. If `docs/tdd/HARNESS.md` exists and looks current, read it and skip ahead. Otherwise discover and record:

- **Stack + test runner(s)** — the exact commands to run one test file, one named test, and the full suite (e.g. `pytest path::name`, `go test ./pkg -run Name`, `npx jest path -t "name"`, `flutter test path --plain-name '…'`).
- **Test-directory conventions** — where unit / integration / e2e tests live, and which of those the runner auto-discovers by glob vs which require manual registration (a suite list, a CI job matrix entry, a tag, a scenario case in a runner script).
- **CI / gate scripts** — any repo scripts or CI jobs that constitute "the gates" (lint, typecheck, test shards, e2e). The script wins over prose.
- **Real-fixture facilities** — how the project spins up a real DB / real service / real environment in tests (testcontainers, in-memory engine, docker-compose, emulator), vs its fakes/mocks.

Write the findings to `docs/tdd/HARNESS.md` (one page: commands, conventions, registration rules) so later plans reuse it instead of re-discovering.

---

## Step 1 — Source-verified grounding (verify → refute)

Never trust a claimed root cause or "this is broken" statement until it is confirmed in real code AND an adversarial pass has failed to refute it. Run a multi-agent **verify→refute** pass. The recommended vehicle is the **Workflow** tool — invoking it from this skill is an explicit opt-in. (If Workflow is unavailable, run the same roles as parallel `Explore` subagents instead.)

Require `file:line` evidence on every claim. When several agents need overlapping context, do one scouting pass first and embed its digest verbatim in every worker prompt — workers should not each re-derive the map.

**Phase A — Ground (parallel):**
- **Locate the seam** — trace the end-to-end data/control flow for the behavior in real source. Return it with `file:line`, and keep a compact digest (anchors, files, gaps) for review and execution.
- **Existing-test inventory** — what tests already cover this area (by tier), which pass today, and the explicit coverage *gaps*. Note which gates/suites already run them.

**Phase B — Verify each finding (per claim):** confirm the symptom reproduces *on HEAD* for the stated mechanism, with `file:line`.

**Phase C — Refute (adversarial, per claim):** actively try to kill it — is it **already fixed** on HEAD? Is the root cause **wrong** (a different path produces the symptom)? Is it an **environment/build artifact** rather than a code bug? Default to "refuted" when uncertain. Only findings that survive C are trusted.

**Phase D — Derive per-tier obligations:** for each *surviving* behavior, read `references/tier-matrix.md` and decide: required tier(s), fake-vs-real-fixture, and the harness-registration consequence. Also flag anything needing a schema/data migration or a real-environment proof.

Synthesize: **(1)** confirmed findings (with the refuted ones listed as "do not re-introduce"), **(2)** per-behavior test obligations, **(3)** existing-coverage gaps, **(4)** migration/real-environment flags.

---

## Step 2 — Build the Test Coverage Matrix

READ `references/tier-matrix.md` now. For **every** spec case / behavior, produce one matrix row with NO empty cells:

| Spec case | Behavior props | Tier | Test file::name | RED reason on HEAD | Mutation that re-reds | Acceptance gate cmd | Harness registration |

- Pick the **lowest** tier that can still fail for the real reason; climb only when the boundary (OS callback, real persistence engine, real network peer, cross-process, real external service) physically demands it.
- One spec case routinely yields **multiple rows** (unit floor → integration → real-environment proof). The unit/fast row is mandatory; the real-environment row is the closure gate for OS-boundary / cross-process / external-system specs.
- Each row's **harness registration** must be concrete, in this project's terms (from `HARNESS.md`): `AUTO (runner glob)` | `add to <suite/CI job/list>` | `register scenario in <runner script>` | `tag + tag-filtered gate`.
- **Run the blind-spot sweep before moving on** (the matrix only covers scenarios you enumerated): force the four evergreen classes in `references/sufficiency-checklist.md` → "Blind-spot sweep" — lifecycle/derived-state durability (reopen/restart), sibling-surface consistency, destructive-action side-effects, and invariant-re-verification under new transitions — adding a row for each that applies or recording a justified N/A. These are the misses review most often surfaces after the fact.

---

## Step 3 — Emit the plan

READ `references/plan-template.md`. Fill **every** section from Steps 0–2. Write to:

```
docs/tdd/NN-<slug>-tdd-plan.md
```

(reuse the spec's NN if chaining off one; else the next-free number). Add an entry to `docs/tdd/00-INDEX.md`.

Hard rules while writing:
- **RED tests first**: the RED Test Catalog precedes the implementation steps; each RED entry states the file, the shape/setup, *why it fails on HEAD*, the GREEN assertion, and the exact revert that re-reds it.
- **Literal gates only** in the Acceptance Gates block — real, runnable commands with expected counts, using this project's runner.
- **Scope guard** is a hard "Do not" list; out-of-scope items name the follow-up work that owns them.
- Where two code paths return the same result, assert a **distinct observable discriminator** (a distinct log/flow event, metric, or side-effect — e.g. `EVENT_DEDUP_HIT` AND NOT `EVENT_FULL_FETCH`) so the test can actually distinguish them.

---

## Step 4 — Sufficiency self-check (blocking)

READ `references/sufficiency-checklist.md` and run every gate against the emitted plan. **Any "No" means the plan is a draft — fix it before presenting.** In particular: no spec case without a tiered test; every fix has a re-red mutation; every schema/data-migration change has a test against the real persistence engine; OS-boundary / cross-process / external-system paths have a real-environment proof (not a fake standing in); every new test has a harness-registration step; the Test Coverage Matrix has zero empty cells in *tier*, *mutation*, *gate*, and *harness-registration*; and the **blind-spot sweep** has been run with a row or a justified N/A for each class — and no "Accepted Difference" / "stays unchanged" claim left as an untested assumption.

---

## Step 5 — Present and hand off

Summarize for the user:
- plan type + file path,
- number of spec cases covered and matrix rows,
- which tiers are involved and which rows are **manual-registration** vs auto-discovered,
- migration flag (if any) and whether a real-environment proof is the closure gate,
- the **next command to run** — typically the first RED gate.

Flag any finding that was **refuted** in Step 1 (so the user knows what was investigated and deliberately *not* planned), and any area where evidence was thin. Recommend running `/tdd-review` on the plan before executing it.
