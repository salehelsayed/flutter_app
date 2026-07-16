---
name: tdd-review
description: Audit an EXISTING TDD implementation plan (docs/tdd/NN-*.md, or a bare NN) BEFORE it is executed. Verifies the plan's root cause + cited line-targets + sibling open-sites against real source, adversarially verifies the plan's #1 technical bet (domain/library/dependency facts), scores it on 5 dimensions (goal clarity · agile compartmentalization · precision/anti-drift · up-front evaluation criteria · tests-verify-the-goal), sweeps for the recurring material blockers review keeps finding after the fact (rollback-brick, missed sibling sites, off-target line numbers, un-verifiable perf gates, migration atomicity), surfaces the genuinely user-owned decisions for explicit sign-off, and emits a scored report + a numbered fix-list. Chains after /tdd-plan and before execution. Trigger: /tdd-review
disable-model-invocation: true
argument-hint: "[path to a TDD plan (docs/tdd/NN-*.md) or a bare NN]"
---

# TDD Plan Auditor

You are auditing an existing **TDD implementation plan** — deciding whether it is **safe and correct to execute** — for: **$ARGUMENTS**

This is the adversarial counterpart to `/tdd-plan`. `/tdd-plan` *writes* the plan; `/tdd-review` tries to *break* it before any execution time is spent. A plan that reads well can still (a) misidentify its root cause, (b) cite line numbers that don't do what it claims, (c) miss a sibling code path that silently breaks, (d) ship a change that can't be proven to have worked, or (e) brick user data on a rollback. Those are the misses this skill exists to catch.

**A plan is "ready to execute" only when all of these hold — this is the definition you are auditing against:**
1. **Root cause + every cited `file:line` is verified in real source** — not asserted, not remembered. The plan's factual scaffolding is true.
2. **The plan's #1 technical bet is domain-verified** — the load-bearing assumption (a library behavior, a crypto property, an OS-callback ordering, a wire-format claim) is confirmed against docs/dependency source, not hoped.
3. **Every sibling surface is enumerated** — all callers / open-sites / adjacent features that the change touches, especially the one that does NOT inherit the change automatically.
4. **"Good" is defined up front with one hard number** — the goal is a measurable outcome with a single pre-committed pass/fail threshold and a captured baseline, and a real test (not a manual eyeball) guards it.
5. **The user-owned decisions are surfaced for explicit sign-off** — release-risk, the single "done" number, and any de-scope calls are decided by the user, not defaulted silently.

Be **source-grounded and proof-honest**: ground claims in real source before trusting them, and treat "fast tests green" as insufficient for any OS-boundary / crypto / cross-process / external-system claim — those need the real environment.

The decision rules, the recurring-blocker sweep, and the workflow/report/fix-list skeletons live in bundled reference files — **READ them at the steps below; do not work from memory:**
- `references/review-dimensions.md` — the 5 dimensions: what GOOD looks like, the failure smells, the scoring bands, and the verify-prompts each dimension raises.
- `references/evergreen-blindspots.md` — the material blockers review keeps finding AFTER the fact; sweep EVERY plan for these regardless of what it enumerates.
- `references/audit-workflow.md` — the multi-agent audit recipe (agent roles + JSON schemas), the report template, the fix-list template, and the AskUserQuestion decision set.

---

## Step 0 — Resolve the plan

Decide what `$ARGUMENTS` is:
- **A path** (`docs/tdd/218-*.md`) or a **bare number** (`218`) → that is the plan under audit. READ it in full.
- **Empty** → look for the most recently modified `docs/tdd/NN-*-tdd-plan.md` (or the project's plan location); confirm with the user before proceeding.
- **A free-text plan pasted inline** → audit it in place; there is no file to reference by `file:line`, so note that in the report.

Record: plan number `NN`, its stated goal in one sentence, its type (bug / feature / perf / migration), and whether it declares a **real-environment-proof / migration / OS-boundary** leg (those raise the bar — fast-tests-green is not closure).

---

## Step 1 — Ground truth & claim inventory

Before judging quality, establish what is TRUE. Read the plan and pull out its **factual load-bearing claims** into a checklist:
- the **root cause** (what line does what, and why that produces the symptom),
- every cited **`file:line`** the plan tells the executor to edit,
- the **caller / sibling-site count** ("N callers inherit this", "these are all the open-sites"),
- the **baseline metric** (the "was ~Xms" / "currently fails because" number),
- the **#1 technical bet** (the one assumption the whole payoff rests on).

Read the primary source files the plan names (the entrypoint, the migration, the seam) so you carry the real ground truth into the audit. You are looking for the gap between what the plan *says* the code does and what it *actually* does.

---

## Step 2 — Run the audit (multi-agent, source-grounded)

READ `references/audit-workflow.md` now and author the audit as a **Workflow** (invoking this skill is the explicit opt-in to the Workflow tool; if Workflow is unavailable or you want a quick pass, run the same roles as parallel `Explore` subagents). The recipe:

- **Phase Verify (parallel):**
  1. **Factual / root-cause verifier** — independently confirm/refute each claim from Step 1 against real source, with `file:line` evidence. Explicitly *count the sibling sites yourself* (grep every caller / open-site) — the plan's count is frequently an undercount, and the site that does NOT inherit the change is the bug.
  2. **Domain-risk verifier** — adversarially verify the plan's #1 bet using WebSearch AND by reading the actual dependency/library/native source. The plan's *stated* top risk is often a misconception, and its *documented fallback* is often unsound — check both.
- **Phase Assess (parallel):** one agent per dimension in `references/review-dimensions.md`. Each returns a verdict (strong/adequate/weak), a 0–100 score, strengths, gaps (each tagged material/moderate/nit with a concrete fix), and up to 3 verify-prompts for the user.
- **Phase Critique:** a completeness critic reads ALL prior outputs and returns: blind spots none of them raised, contradictions between them, the ranked top material risks, and a ready-to-execute verdict (yes / yes-with-tightening / no).

Force the **evergreen blind-spot sweep** (`references/evergreen-blindspots.md`) into the critic's prompt: every plan must be checked for those recurring classes even if the plan never mentions them.

---

## Step 3 — Cross-check the linchpins yourself

The workflow returns findings; agents can be wrong. Before you report a **material** finding as fact, **verify its linchpin in source yourself** (grep / read the exact lines). In practice the two highest-value self-checks are:
- the **sibling-site claim** ("there's a 5th open-site that doesn't inherit") — grep it, read the call, confirm the mode/secret/path.
- the **off-target line claim** ("editing `:NN` would break X, because `:NN` actually keys a different thing") — read `:NN` and confirm what it operates on.

Only promote a finding to **material** once you have `file:line` proof. Downgrade anything you cannot confirm to "plausible — verify at execution".

---

## Step 4 — Score, rank, and sweep

Assemble:
- the **dimension scorecard** (table: dimension → verdict → score),
- whether the **core bet is verified sound** (the good-news line — say it plainly if it is),
- the **material blockers, ranked** (most severe first), each with its `file:line` proof and concrete fix,
- **what the plan does WELL** (keep-these) — an audit that only lists faults is not trustworthy,
- the result of the **evergreen sweep**: for each recurring class in `references/evergreen-blindspots.md`, state "hit" (with the finding) or "clear / N-A".

Give an overall verdict: **ready / ready-with-tightening / not-ready**.

---

## Step 5 — Surface the user-owned decisions (do not default silently)

Some findings resolve to a **recommendation** (you have the evidence — state it). Others are genuinely the **user's call** and change what the revised plan should say. Per `references/audit-workflow.md`, ask the user — via **AskUserQuestion** — the decisions that are theirs, typically:
- **release-risk strategy** for any one-way / irreversible change (forward-compat-first release · kill-switch + staged rollout · accept-the-risk),
- **the single hard "done" number** for the goal metric (pick from concrete options),
- **the next action** (revise the plan in place · findings only · findings + a written fix-list).

Keep it to the 2–3 decisions that actually gate finalization. Do not ask about things you can verify yourself or that have an obvious default.

---

## Step 6 — Emit the report + (if chosen) the fix-list

Present the report from Step 4 in the chat (scored table, verified core-bet line, ranked blockers, keep-these, evergreen-sweep result, verdict). Then honor the Step-5 next-action choice:
- **Fix-list** → write `docs/tdd/NN-review-fixlist.md` using the template in `references/audit-workflow.md`: a header (verdict + locked decisions + verified facts), findings grouped by theme and numbered with an exact edit + why for each, and a priority order. Do NOT edit the plan itself unless the user chose "revise in place".
- **Revise in place** → apply the fixes to `docs/tdd/NN-*.md` directly, then re-run the Step-4 sweep to confirm the blockers are closed.
- **Findings only** → stop after the report.

Finally, if the plan is indexed (`docs/tdd/00-INDEX.md`), note the audit verdict next to it. If the audit surfaced durable, non-obvious project knowledge (a verified root-cause correction, a rollback hazard, a sibling-site landmine), record it wherever this project keeps such notes — do not save what the plan or git already records.
