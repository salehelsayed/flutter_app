# Portable /tdd-plan and /tdd-review skills

Stack-agnostic versions of the TDD planning + plan-audit skills. No dependency on graphify, /sims, Flutter, or any other project tooling — safe to drop into any repository.

## Install

Copy both directories into the target project:

```bash
cp -r tdd-plan tdd-review <target-repo>/.claude/skills/
```

They are then invocable as `/tdd-plan` and `/tdd-review` (both have `disable-model-invocation: true`, so they only run when you ask by name).

## Conventions they create on first use

- `docs/tdd/` — plans live here as `NN-<slug>-tdd-plan.md`, indexed in `docs/tdd/00-INDEX.md`. Change the path in both SKILL.md files if your project prefers another location.
- `docs/tdd/HARNESS.md` — written by /tdd-plan's Step 0.5 bootstrap on first run: the project's literal test commands, test-directory conventions, gate scripts, and test-registration rules. Later plans reuse it.

## Flow

```
/tdd-plan "<bug/feature description or spec path>"   → docs/tdd/NN-…-tdd-plan.md
/tdd-review NN                                       → scored audit + fix-list / in-place revision
(execute the plan)
```

## Contents

- `tdd-plan/SKILL.md` + `references/` — tier matrix, sufficiency checklist, plan template
- `tdd-review/SKILL.md` + `references/` — 5 review dimensions, evergreen blind-spot sweep (B-1..B-10), audit workflow + report/fix-list templates
