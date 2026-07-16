# TDD Plan Skeleton (read in Step 3 — emit this structure)

Fill every section. Replace `NN`, `<…>`, and example rows. Reuse the spec's NN if chaining off one; else next-free from `00-INDEX.md`. Save to `docs/tdd/NN-<slug>-tdd-plan.md`.

```markdown
# NN - <Title>  (Bug | Feature Improvement | New Feature | Modification)

Status: (awaiting-review / accepted)
Spec: <path to NN-*.md, or "free-text intent (no formal spec)">

## Planning Progress
| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| | Evidence Collector | | | |
| | Planner | | | |
| | Reviewer (sufficiency) | | | |
| | Arbiter | | (final structural verdict) | hand off to execution |

## Execution Progress
| Time | Phase | Files touched | Command/evidence | Decision/blocker | Next |
|---|---|---|---|---|---|
| | contract extraction (git status --short) | | | scope confirmed | |
| | RED tests added | | (cmd proving they FAIL) | RED for expected reason | |
| | implementation | | | scoped files only | |
| | direct GREEN | | (exact cmd) | reds now green | |
| | preservation GREEN | | (exact cmd) | sentinels green | |
| | named gates | | (exact cmd + counts) | gate green | |
| | QA (independent) | | (re-run cmds) | blocking: none/list | verdict |

## Source Of Truth
- Spec / intent: <path or "inline below">
- Harness map (runner cmds, registration rules): docs/tdd/HARNESS.md  (script/CI config wins over prose)
- Gate definitions: <the project's gate scripts / CI jobs>
- Numbering / index: docs/tdd/00-INDEX.md

## Session Classification
(acceptance-only / evidence-only / implementation-ready)

## Exact Problem Statement
<2-3 paragraphs: what is broken/missing, who experiences it, why it matters>
What must improve: …
What must stay unchanged: …  (→ preserved-green sentinels)

## Root Cause (verify → refute confirmed)
<file:line mechanism that SURVIVED the adversarial refute pass>
Refuted / do-NOT-re-introduce: <findings shown already-fixed / wrong-RC / environment-artifact>

## Real Scope
In scope: <concrete changes> | Out of scope (follow-up X owns): <deferred>

## Files To Inspect Next
Production (entrypoints/use-cases, models, repositories, helpers): …
Direct tests + integration tests: …
Dependency-only context: …

## Existing Tests Covering This Area
- <test> covers <what> (exists / MISSING)
Missing coverage gaps: …
Already registered in curated suites/gates?: <which gates list these>

## RED Test Catalog  (add BEFORE any production code — INV-RED-FIRST)
1. <file>::<test name>
   - Tier: (unit | component/UI | integration | E2E | real-environment proof)
   - Shape/setup: …
   - RED on HEAD because: …
   - GREEN after fix asserts: …
   - Mutation that re-reds: revert <edit> → this test red
   - Distinct-event discriminator (if shared result): assert <EVENT_A> AND NOT <EVENT_B>
2. …

## Test Coverage Matrix  (ZERO empty cells in tier / mutation / gate / registration)
| Spec case | Behavior props | Tier | Test file::name | RED reason on HEAD | Mutation revert | Acceptance gate cmd | Harness registration |
|---|---|---|---|---|---|---|---|
| TC-01 | pure logic | unit | …::… | … | revert … | <unit-suite cmd> | AUTO (runner glob) |
| TC-02 | persistence | integration | …::… | … | … | <integration gate cmd> | add to <suite/gate list> |
| TC-03 | migration | migration (real engine) | …::… | schema/idempotency | … | <migration gate cmd> | AUTO / suite list |
| TC-04 | OS-boundary / cross-process | real-environment proof | …::… | … | … | <proof-runner cmd> | register scenario in <runner> |

## Blind-Spot Sweep  (evergreen classes the spec cases above don't name — row added OR justified N/A)
- **Lifecycle / derived-state durability** (reopen / process-restart reconstructs derived state, not just the row): <TC-NN / N/A because …>
- **Sibling-surface consistency** (new gate applied across all parallel actions, or asymmetry test-locked): <TC-NN / N/A because …>
- **Destructive-action side-effects** (delete/cleanup/cancel asserts what is removed + preserved, not just the affordance): <TC-NN / N/A because …>
- **Invariant re-verification under new transitions** (self-heal/reset/release re-checks pre-transition invariants; asserts full post-transition state): <TC-NN / N/A because …>

## Invariants (locked by tests)
- INV-1: <property> → locked by <test>
- INV-RED-FIRST and INV-MUTATION-VERIFIED apply to every row above.

## Step-By-Step Implementation Plan
1. Add RED tests; run focused cmds; confirm they fail for the expected reason.
2. <class/method/seam edit — name the exact seam, not "fix the subsystem">
3. … Stop-if: <blocker> → replan, do not hack around it.
4. Rerun direct → preservation → named gates.

## Risks And Edge Cases
- <hazard / concurrency / stale state> → pinned by <test>

## Real-Environment Proof Profile
(unit/integration-only for closure  /  requires <E2E / device / multi-process proof> for closure)
Closure scenario: <literal proof-runner cmd>   (flip any feature flag ON only AFTER real-environment evidence)
Deferred proof work → follow-up X: <cmd>

## Acceptance Gates  (literal — copy/paste, with expected counts)
```bash
# RED (before production edits) — must FAIL for the documented reason
<runner cmd for the focused red test>

# Direct GREEN (after fix)
<runner cmd for the red test file>

# Preservation sentinels (must stay green)
<named gate cmd>                              # expect: NNNN/NNNN pass

# Migration (real engine), if schema changed
<migration test cmd>

# Named gate(s) for the touched subsystem
<subsystem gate cmd>

# E2E / proof discovery + run (if any E2E/proof rows)
<proof-runner list/dry-run cmd>               # new scenario MUST appear
<proof-runner run cmd>

# Hygiene
<linter/typecheck cmd>     # 0 new issues
git diff --check
```

## Known-Failure Interpretation
- Expected RED: <test> before fix.
- Pre-existing dirty: <unrelated modified files in tree>.
- Environment blocker (NOT product): missing emulator/service/container.
- Scope drift (BLOCKING): any failure outside the Scope Guard.

## Done Criteria
- [ ] RED added first, failed for the expected reason.
- [ ] Mutation-verified (each fix has a re-red revert).
- [ ] Direct GREEN + preservation sentinels + named gates pass.
- [ ] Migration has a real-engine test (if schema changed).
- [ ] OS-boundary / cross-process paths proven in the real environment, not a fake.
- [ ] Every new test's harness-registration step done & verified in a gate run.
- [ ] Linter/typecheck 0 new; git diff --check clean; no Scope Guard violations.

## Scope Guard (hard "Do not")
- Do not <forbidden change that belongs to other work>

## Accepted Differences / Intentionally Out Of Scope
- <could-do, not-here, follow-up X owns it, why>

## Dependency Impact
- Follow-up X depends on this because: <contract>

## Reviewer Findings
<verbatim sufficiency / missing-coverage / scope-risk verdict>

## Arbiter Decision
Structural blockers: … | Deferred details: … | Accepted differences: …

## Final Execution Verdict
Verdict: (accepted/rejected) | Files changed: … | Tests run (+counts): … | Blocking: … | QA verdict: … | Non-blocking follow-ups (owner):
```
