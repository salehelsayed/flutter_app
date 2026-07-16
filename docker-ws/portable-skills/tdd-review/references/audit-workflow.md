# Audit Workflow · Report · Fix-List · Decisions (read in Steps 2, 5, 6)

## 1. The multi-agent audit recipe

Author the audit as a **Workflow** (invoking this skill is the opt-in). Scale the fleet to the ask:
- **Quick pass:** 5 dimension agents only (skip the domain-risk verifier + critic). For a sanity check or a small plan.
- **Thorough (default):** 2 verifiers → 5 dimension assessors (parallel) → 1 completeness critic. This is the shape below.
- If the Workflow tool is unavailable, run the same roles as parallel `Explore` subagents and synthesize by hand.

**Common prompt preamble for every agent** (embed verbatim): the plan path, the primary source file paths it references, the ground-truth facts you established in Step 1 ("already verified — build on it, don't re-litigate"), the project's proof reality (fast tests use fakes; crypto/OS-boundary/external-system legs need the real environment), and "return raw structured data — your output is consumed by an orchestrator, not shown to a human; cite `file:line` and plan line numbers."

**Phase Verify (parallel), schema per agent = `VERIFY_SCHEMA`:**
- *Factual/root-cause verifier* — confirm/refute each Step-1 claim against real source. MUST independently grep every caller/sibling open-site (B-2) and read every cited edit line (B-3).
- *Domain-risk verifier* — WebSearch + read the dependency/library/native source to verify the plan's #1 bet AND its fallback (B-7). (Skip in quick pass.)

**Phase Assess (parallel), schema = `DIM_SCHEMA`:** one agent per dimension in `review-dimensions.md`.

**Phase Critique, schema = `CRITIC_SCHEMA`:** one agent reads ALL prior outputs; force the `evergreen-blindspots.md` sweep into its prompt.

### JSON schemas (reuse verbatim)
```
DIM_SCHEMA = { dimension, verdict:enum[strong,adequate,weak], score_0_100:int,
  strengths:[str], gaps:[{issue, severity:enum[material,moderate,nit], why_it_matters, concrete_fix}],
  verify_prompts:[str] }   // up to 3 user yes/no decisions

VERIFY_SCHEMA = { area, claims:[{claim, verdict:enum[confirmed,refuted,uncertain], evidence}],
  material_errors:[str], summary }

CRITIC_SCHEMA = { missing_dimensions:[str], contradictions:[str],
  top_material_risks:[{risk, why, recommended_action}],
  plan_is_ready_to_execute:enum[yes,yes-with-tightening,no], one_line_verdict }
```

### Pipeline note
Dimension agents are independent → `parallel()` them. The critic needs ALL outputs → it comes after a barrier. Verifiers and dimensions can all run in the first fan-out; only the critic waits. Return `{verification, assessments, critique}`.

---

## 2. Report template (present in chat, Step 6)

```
# Review: <plan file>

## Verdict
<one line>: core bet <verified sound / unverified / refuted>; <ready / ready-with-tightening / NOT ready>.
Critic verdict: <yes / yes-with-tightening / no>.

| Your criterion            | Dimension                 | Score | Verdict |
| (1) Goal/decisions        | Goal clarity              |  NN   | …       |
| (2) Agile/checkpoints     | Compartmentalization      |  NN   | …       |
| (3) Precise/no-drift      | Anti-drift                |  NN   | …       |
| (4) Eval criteria up front| Define "good"             |  NN   | …       |
| (5) Tests verify the goal | Goal-verification         |  NN   | …       |

## Is the core bet sound?
<state plainly if verified — good news counts. Note the #1-risk misconception / unsound-fallback if found (B-7).>

## Material blockers (ranked, each with file:line proof + fix)
1. …  2. …  3. …

## Evergreen sweep
<table: B-1..B-10 → hit/clear → evidence → fix>

## What the plan does WELL (keep these)
<an audit that only lists faults isn't trustworthy — name the real strengths.>
```

Lead with the verdict. Report the dimension scores. Rank blockers most-severe first. Always include "what it does well".

---

## 3. Fix-list template (write to `docs/tdd/NN-review-fixlist.md`, Step 6)

Header block:
```
# NN Review — Fix-List (apply against `NN-<slug>-tdd-plan.md`)

Source: <N-agent audit + source-verification>, <date>. Plan is <not/…> execution-ready; <core bet status>.

Decisions locked with the user:
- <release-risk decision>
- <the single hard "done" number>

Verified facts this list relies on (checked against source):
- <claim> — <file:line>. ✅   (list the load-bearing ones you confirmed yourself in Step 3)
```

Then group findings by theme into lettered sections (§A, §B, …), each item = an ID + the **exact edit** + **why**:
```
## §A — <theme, e.g. Rollback safety>
- **A1.** <the exact change to make in the plan / code, concrete enough to apply without re-deriving>. <one-line why.>
- **A2.** …
```

End with a **priority order**:
```
## Priority order to apply
1. <blockers that gate the whole ship model / would break a feature>
2. <make the win verifiable + the migration non-bricking>
3. <slice the work + make tests guard the goal>
4. <specs, mechanism corrections, cleanup>
```

Rules: give a **plain-English gloss** for any project term the plan assumes ("Move = the account-migration feature" style); do NOT edit the plan file itself (unless the user chose "revise in place"); every material item cites the `file:line` that proves it.

---

## 4. The user-owned decisions (AskUserQuestion, Step 5)

Ask ONLY the 2–3 decisions that are genuinely the user's and that change what the revised plan says. Recommended set (adapt to the plan):

1. **Release-risk strategy** — only if the plan has a one-way/irreversible change (B-1). Options e.g.:
   - *Forward-compat opener first* (ship a read-both release before the migrating one) — safest, costs a release cycle.
   - *Kill-switch + staged rollout (+ keep backup N launches)* — no prior release needed.
   - *Accept the risk* — small/controlled cohort; document the one-way boundary with a test.

2. **The single hard "done" number** for the goal metric (B-4). Offer concrete options, e.g.:
   - *Ratio + absolute* (recommended): `new_p50 ≤ old_p50 / K` AND `new_p50 ≤ Xms`, N≥5 median, steady-state run — environment-robust.
   - *Absolute only* — simpler, more environment-sensitive.
   - *Ratio only* — environment-independent, no absolute floor.

3. **Next action** — *revise the plan in place* · *findings only* · *findings + a written fix-list*.

Do NOT ask about de-scopes you have `file:line` evidence for (state them as recommendations and let the user push back), or anything with an obvious default. Reserve the question budget for real forks.

---

## 5. After the audit
- Cross-check every **material** finding's linchpin in source yourself before reporting it as fact (Step 3). Downgrade unconfirmable findings to "plausible — verify at execution".
- Record durable, non-obvious findings (verified root-cause corrections, rollback hazards, sibling-site landmines) wherever the project keeps such notes. Don't record what the plan or git already captures.
- If the plan is indexed in `00-INDEX.md`, note the audit verdict next to it.
