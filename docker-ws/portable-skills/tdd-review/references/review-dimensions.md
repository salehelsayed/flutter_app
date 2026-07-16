# The 5 Review Dimensions (read in Step 2 — one assessor agent per dimension)

Each dimension answers one question about the plan. For each, the agent returns: verdict (`strong`/`adequate`/`weak`), a 0–100 score, strengths, gaps (each `material` / `moderate` / `nit` + concrete fix), and up to 3 **verify-prompts** (explicit yes/no decisions to put to the user).

Scoring bands (apply consistently across dimensions):
- **strong (75–100):** the property holds; only nits or one moderate gap.
- **adequate (55–74):** the skeleton is there but a material gap weakens it.
- **weak (<55):** a material gap defeats the property; an executor could satisfy the plan's letter and miss its intent.

A single **material** gap caps the dimension at "adequate" at best; two material gaps → "weak".

---

## D1 — Goal clarity (does the plan uncover the true goal + the decisions it drives?)

**What GOOD looks like**
- The goal is a **measurable outcome** ("open drops from ~500ms to ≤15ms; startup ~0.5s faster"), not an activity ("switch to the new mechanism").
- Anchored to a **captured baseline**, not a remembered number.
- The **conclusion is airtight and pre-refuted** — the reasons someone might reverse it mid-execution are enumerated and killed up front (e.g. "removing the key-derivation step weakens security → False, because the key is already full-entropy").
- The **decisions the plan forces** are explicit: which mechanism, ship-vs-STOP, migrate-vs-fresh — each with a named gate.
- It answers **one clear question**, and correctly scopes OUT adjacent work with justification.

**Smells (failure signatures)**
- The target is stated **multiple inconsistent ways** (single-digit / tens / ≤50ms) — a spread means no one number is committed.
- The **ship/STOP gate keys on the wrong thing** (e.g. on "does the mechanism work" but not on "did we hit the number") → a partial win has no decision branch.
- A hard requirement (e.g. "data-preserving migration") is asserted **without the why**, so it can be reopened under schedule pressure.
- "Biggest lever" claims that aren't defended against the alternative that was scoped out.

**Verify-prompts this dimension raises:** the single measurable definition of "done"; whether the ship/STOP gate should key on the goal metric, not just feasibility.

---

## D2 — Agile / compartmentalization (small buckets · real checkpoints · early payoff · review-adjust-repeat)

**What GOOD looks like**
- Work is split into **small, independently reviewable increments**; each produces a reviewable result before the next starts.
- There is a genuine **STOP/GO checkpoint BEFORE the risky/irreversible work** (a feasibility gate that runs before any production edit and cannot be skipped).
- The **payoff is observed early** — the metric the whole plan exists for is measured at the earliest point it's observable, not only at the final step.
- The riskiest slice (the one that can brick/corrupt) is **reviewed in isolation**, not bundled with trivial edits.

**Smells**
- **One monolithic production edit** that turns all tests green at once → a reviewer can't localize which concern regressed; the risky slice shares a checkpoint with the trivial one.
- The **payoff proof is the very last step**, gated behind risky work it doesn't depend on → late feedback on the deliverable.
- **Progress tables are status-theater** — a log with no GO/STOP semantics; the real gate lives only in prose an executor can skim past.
- "Author ALL red tests, then make ALL green" — a waterfall inside TDD.

**Verify-prompts:** whether to split the production edit into named slices each RED→GREEN→pause; whether to pull the payoff measurement forward.

---

## D3 — Precision / anti-drift (can an executor confidently do the WRONG thing?)

**What GOOD looks like**
- A hard **Scope Guard "Do not" list** and explicit **Stop-if** conditions.
- **Every cited `file:line` actually does what the plan says** — verified (this is where audits earn their keep).
- **All sibling surfaces enumerated**, including the one that does NOT inherit the change.
- **Under-specified seams are pinned**: how a marker is stored/keyed; the exact atomic-swap file protocol; how a threshold is quantified; which target environments; the literal build command (not "+ the other platform's equivalent").

**Smells (the expensive ones)**
- **Precise-but-wrong line numbers** — worse than vague ones, because they invite a green-tested wrong edit. "These must all change together or X breaks" framings are frequently **backwards** (changing them is the break).
- A **grep-gate / invariant that is provably false** (a missed open-site makes "all sites use the new mode" a lie).
- "**Model on existing code X**" where X is itself unsafe (non-atomic delete-before-verify, duplicated export).
- A marker/flag whose **storage is never committed** ("keychain key OR sentinel file") — the executor improvises the branch that decides whether user data gets migrated/recreated/mis-opened.
- The test can be satisfied while the goal is missed (green without the real win).

**Verify-prompts:** confirm any de-scope of off-target edits; confirm the added sibling-site + its test; confirm the marker storage choice.

---

## D4 — Evaluation criteria defined up front ("define good with precision" BEFORE work starts)

**What GOOD looks like**
- **One hard, pre-committed pass/fail number** for the goal metric — no tildes, no "≤ ~50ms".
- A **reproducibly captured baseline** (same build/environment/protocol, N samples, a percentile — not a remembered figure).
- The acceptance gate is **actually runnable** — the command greps a field the code actually emits; the measured span and which run is measured are pinned.
- Every spec case maps to **tier + test + mutation + gate cmd + harness-registration** with zero empty cells; preservation sentinels enumerated as must-stay-green.
- "Not done" conditions are pre-committed (fast-tests-green-only is insufficient for real-environment legs; a no-op ships nothing).

**Smells**
- The PROD-CRITICAL threshold is a **soft hope** ("≤ ~50ms") or stated 3 ways.
- The gate **greps a log field that doesn't exist**, or measures the **wrong run** (e.g. the one-time migration run that is legitimately slower → false FAIL).
- The baseline is **remembered, not re-measured** → the "N× better" claim is asserted, not proven.
- A "Done" checkbox names **no event pair and no baseline** ("startup ~0.5s faster") — un-checkable, gets ticked by inference.
- Single-shot timings with **no N / no percentile** → flaky pass/fail reflecting scheduler jitter.

**Verify-prompts:** the one hard "done" number; whether a freshly captured pre-fix baseline (not the remembered one) is required before execution.

---

## D5 — Do the tests actually profile / verify THE GOAL?

**What GOOD looks like**
- The goal has an **automated regression gate on the REAL production path** — not only a synthetic in-test measurement, not only a manual eyeball.
- A **no-op discriminator on the real artifact**: the test proves the change actually happened at the production DB/file/path (e.g. the on-disk data fails to open the OLD way and succeeds the NEW way), not via a self-referential flag the code itself sets.
- **Real failure modes** are injected for destructive/atomic steps (crash mid-swap, truncated copy, crash-after-swap-before-marker), not just the trivially-safe case.
- **Durability across a REAL restart** (not a same-process reopen that an in-memory cache can fool).
- **Cross-platform / cross-environment parity is RUN**, not asserted in prose, when the underlying path diverges.

**Smells**
- The PROD-CRITICAL win is guarded **only by a manual log-grep** → silent regression after the plan closes.
- Preservation "proven" by **sampling a few tables** of many, or by a check that doesn't discriminate the thing under test (a version probe that returns the same answer regardless of mode).
- Atomicity test injects failure at the **safe** moment (before anything is touched).
- A "convert once" test that a **same-process reopen** can pass while the flag never actually persists.
- "Test on the other platform too" with **no target id and no literal command**.
- A negative assertion ("opening with the wrong key fails") that **any** failure satisfies (bad path, missing file) → false green on the discriminator.

**Verify-prompts:** promote the manual perf proof to an automated real-path assertion; strengthen preservation to a full-data checksum + schema-version check; inject the real failure-mode in the atomicity test; run the platform-divergent leg on both platforms as literal gates.
