# "Definition of Sufficient" Checklist (read in Step 4 — blocking)

A TDD plan is **sufficient** only when ALL four core conditions and ALL gates below hold. Any **No** = the plan is a draft; fix it before presenting.

## Core conditions

1. **Spec-case totality** — every spec test-case ID / behavior maps to ≥1 named test (file + test name) at the right tier.
2. **Mutation-verifiable** — every behavior-bearing edit has a test that goes RED on HEAD for a documented reason and GREEN after the fix; reverting re-reds it.
3. **Literal acceptance gates** — real, copy-paste commands with expected pass counts.
4. **Named harness-registration per test** — auto-discovery / suite list / CI job / scenario registration stated for each new test.

## Yes/No gates

- [ ] **Spec-case totality:** every Test-Cases ID has ≥1 row in the RED Test Catalog (tier + file + name). No orphan IDs.
- [ ] **Every INV-\* has a test:** each invariant the plan declares is locked by a named test that goes red if violated.
- [ ] **Every fix is mutation-verified:** for each production edit, the plan names the test + the exact revert that re-reds it ("revert `<edit>` → §X assertion N flips RED").
- [ ] **No vacuous coverage:** every RED is shown failing on HEAD for the documented reason. Where two paths return the same result, a distinct observable discriminator is asserted (e.g. `EVENT_A` AND NOT `EVENT_B`).
- [ ] **Migration has a real-engine test:** any schema/data-migration change has a test against the real persistence engine with schema introspection, row preservation, and run-twice idempotency.
- [ ] **Boundaries proven for real, not faked:** OS-boundary / cross-process / protocol-convergence / external-service paths have a named E2E or real-environment proof — not a fake standing in.
- [ ] **PROD-CRITICAL leg named:** the single path that proves the deliverable end-to-end is named and marked PROD-CRITICAL ("do NOT treat unit coverage as sufficient on its own").
- [ ] **Preservation sentinels named:** the existing suites that must stay green (impact-adjacent behavior) are listed with their gate command + expected count.
- [ ] **Acceptance-gate commands are literal:** real runner invocations with expected counts, plus the project's linter/typecheck (0 new issues) and `git diff --check`.
- [ ] **Harness-registration step listed per new test:** auto-discovery / suite list / CI job / scenario case. No invisible tests.
- [ ] **Known-failure interpretation written:** which reds are expected-RED, which are pre-existing dirty-tree, which are environment blockers (missing emulator/service ≠ product blocker), which are scope drift (blocking).
- [ ] **Dirty-tree snapshot planned:** `git status --short` recorded before execution so unrelated changes are not reverted.
- [ ] **Refuted findings recorded:** anything investigated in verify→refute and found already-fixed / wrong-RC / environment-artifact is listed as "do NOT re-introduce", so it is not silently re-planned.

## Blind-spot sweep (evergreen — independent of the enumerated spec cases)

The matrix only covers scenarios you thought to enumerate. These four classes are *recurring* misses that no spec case names directly — review keeps finding them after the fact. For EACH, either add a matrix row or record an explicit, **justified** N/A — never skip silently. (An "Accepted Difference" or "what stays unchanged" claim is an **untested assumption** until a test guards it; a documented-but-unverified assumption is exactly where latent bugs hide.)

- [ ] **Lifecycle / derived-state durability:** does the change add in-memory state derived from an event (a latch, flag, cached reason, computed capability)? If the underlying *data* persists but the *derived state* does not, there is a fresh-mount / reopen / process-restart test asserting the derived UI/state **reconstructs** — not just that the row survives. Treat "rely on the existing round-trip for durability" as a red flag demanding its own reopen test.
- [ ] **Sibling-surface consistency:** if the change adds a condition to one capability gate (e.g. can-write / can-submit), list the *parallel* gates (edit, delete, retry, share, adjacent actions) and confirm the condition applies to all — or that the asymmetry is deliberate AND test-locked.
- [ ] **Destructive-action side-effects:** for every new or changed delete / cleanup / cancel, a test asserts **what is removed** (files, rows, directories) and what is preserved — not merely that the affordance appears. Audit whether an existing cleanup path should be reused rather than a fresh one written (a divergent copy silently drops a step).
- [ ] **Invariant re-verification under new transitions:** any newly-added state transition (self-heal, reset, release, re-entry — *especially* one added during review) re-verifies every invariant that was justified by the PRE-transition state ("Retry hidden because canWrite is false" breaks the moment a self-heal flips canWrite back). The transition's test asserts the FULL post-transition state of every artifact it touches, not just the headline flag.

## The matrix gate (the single most important check)

The **Test Coverage Matrix** has **zero empty cells** in the columns *tier*, *mutation*, *gate*, and *harness-registration* — for every spec case. An empty cell in any of those four columns means the plan is not sufficient yet.

> A spec case without a test at the right tier is a hole; a test that can't go red is theater; a test that runs in no gate is invisible. Sufficiency = none of the three.
