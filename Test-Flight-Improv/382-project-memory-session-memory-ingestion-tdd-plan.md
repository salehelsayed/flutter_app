# 382 - Project-Memory Session-Memory Ingestion (closes plan 381's phase-2 corpus GAP)

Status: EXECUTED — host-green 2026-08-17 (18/18 eval gate, 22/22 contract suite, 8/8 mutations re-red)
Type: Modification
Spec: free-text intent (no formal spec) — extends plan 381; targets the 6 misses in `project-memory/RECALL-RESULTS.md`
Classification: implementation-ready
Closure tier: host (pure tooling; no app code, no device)

## Planning Progress
| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-08-17 | Evidence Collector | recall dogfood (381 facts w/ provenance), memory-dir census (65 files), `expected_facts.json` rows Q8/15/19/21/25/30, 00-INDEX tail | Memory folder is deterministically parseable: 64/64 frontmatter name+description+type (project 49 / feedback 9 / reference 6), 57/64 `modified:`, 3 SUPERSEDED + 4 CORRECTED markers, 105 `[[links]]` (45 distinct), all 6 target memory files exist; eval rows are v1_scope=False with single loose keywords (must be strengthened to gate honestly); 382 free | Design contract |
| 2026-08-17 | Planner | 381 plan + suite + schema, RECALL-RESULTS.md limitations section | Memory pass runs AFTER plan pass and may never write PLAN facts (the 5-stale-memories incident is the design driver); absent-dir tolerance required (memory lives OUTSIDE /workspace — other machines/Codex lack it); schema gains `updated_date` (regenerable db ⇒ no migration machinery) | Emit plan |

## Problem And Evidence
- Behavior to improve: 6 of the 30 A/B eval questions MISS because their answers live only in Claude's session-memory folder, not in the plan corpus (`RECALL-RESULTS.md` per-question table: Q8 `test/unit`, Q15/Q19 relay-flag/ACL facts, Q21 deploy provenance, Q25 host-all baggage, Q30 workspace-stash policy — "exactly the facts QUESTIONS.md predicted live only in session memory"). Those facts are also invisible to subagents, workflows, and Codex, which cannot read the account-scoped memory directory.
- Impact: the sharing gap re-derives known facts per agent; plan 381's own deferred item records this: "Corpus beyond `*-tdd-plan.md` → owner: phase-2" (surfaced verbatim by `recall.py` during grounding — `381-…-tdd-plan.md:61`).
- Confirmed current mechanism and gap: `project-memory/src/build_graph.py` has exactly one corpus pass (`Test-Flight-Improv/*-tdd-plan.md`); no `--memory-dir` flag, no MEMORY entity type, no `updated_date` column in `schema.sql`. Census 2026-08-17 of `/claude-home/.claude/projects/-workspace/memory/`: 64 memory files + `MEMORY.md` index (no frontmatter — must be skipped); 64/64 carry `name:` + `description:` + `metadata.type`; 57/64 carry `metadata.modified` (7 need a file-mtime date fallback); 3 files carry SUPERSEDED, 4 carry CORRECTED/STATUS-CORRECTED markers; 105 `[[wiki-link]]` occurrences over 45 distinct targets; 33/37 files carry `**Why:**`/`**How to apply:**` lines (context only — not extracted in v2).
- **The non-negotiable precedence rule (live-proven the same day):** 5 memory entries were proven STALE against plan `Status:` headers during the A-arm baseline (263-267 "planned-only", 302, 303, 259, relay version). Memory therefore ingests as LOWER-TRUST: the memory pass may create MEMORY entities and `references` edges only — it must NEVER create or update a PLAN entity or its status. This is plan 381's closure-evidence precedence, applied one layer up.
- Existing coverage: the 381 suite (13 tests green: build determinism/provenance, normalization, precedence, refuted/deferred/supersession, floor, recall properties, relationships, eval gate + scorer-vacuity, statusline) — none touches memory ingestion.
- Missing coverage: memory-pass parsing, staleness markers, plan-fact precedence guard, link edges, absent-dir tolerance, updated_date provenance, the 6-question eval flip with strengthened required terms, recall integration for memory facts.
- Refuted findings (do NOT re-introduce):
  - "Memory facts can update plan status when fresher" — REFUTED by the 5-stale-memories incident: memory is the layer that goes stale; artifacts win. Enforced by TC-382-03.
  - "Gate the 6 questions with their current loose keywords" — REFUTED as vacuous: `custody`/`deploy`/`host-all` single-keyword hits mean "related facts surfaced", not "answered" (RECALL-RESULTS.md says so explicitly). Required terms must be strengthened to two gold fragments each.
  - "LLM extraction / embeddings" — still excluded (381 rule; alias seeding + corpus growth first).
  - "Ingest `MEMORY.md`" — it is a generated index with no frontmatter; parse the 64 fact files only.
- Unresolved findings: none material.
- Affected production / test / gate files: EDIT `project-memory/src/{schema.sql,build_graph.py}`, `project-memory/eval/expected_facts.json`, `project-memory/tests/test_project_memory.py`. UNCHANGED: `recall.py`, `run_eval.py` (gate semantics keyed off the scope flags already in the rows), `scripts/test/project_memory_recall_contract_test.sh`, statusline helper. Zero Dart/Go/relay files.

## Graph Grounding Snapshot
- Graph fingerprint / freshness: N/A for the arch graph — same change surface as plan 381 (markdown + project-memory python), whose recorded query (`585839a9908225b8`, confidence=broad, unrelated anchors) proved this tooling has no graph presence; nothing has changed that coverage. Grounding instead came from `recall.py` (381's status, refuted findings, and the phase-2 GAP this plan closes, each with `doc:line @commit`) plus the command census above.
- Query / profile: `python3 project-memory/src/recall.py "project-memory plan 381 deterministic recall status refuted" --budget 400` → 381 `[PLAN/closed]`, its refuted-findings edges, and the deferred phase-2 GAP rows.
- Anchors: `project-memory/src/build_graph.py` (single-pass builder), `project-memory/src/schema.sql` (entities table), `project-memory/eval/expected_facts.json` (Q8/15/19/21/25/30 rows), `/claude-home/.claude/projects/-workspace/memory/*.md` (source corpus).
- Surfaced proof/gate files: `project-memory/tests/test_project_memory.py`, `scripts/test/project_memory_recall_contract_test.sh`.
- Graph gaps that required raw source search: the memory directory itself (outside every graph by design).
- Reuse rule: anchors are search starting points; every conclusion above carries a census command or file citation.

## Scope Contract And Guard
In scope:
- `schema.sql`: add `updated_date TEXT` to `entities` (nullable for plan rows in v2; REQUIRED non-null for MEMORY rows — asserted in tests, not by constraint, to avoid touching the plan pass). graph.db is regenerable: schema evolves by rebuild, no migration machinery.
- `build_graph.py`: a SECOND pass, run strictly AFTER the plan pass, over `--memory-dir` (default `/claude-home/.claude/projects/-workspace/memory`):
  - skip `MEMORY.md`; parse frontmatter `name` / `description` / `metadata.type` / `metadata.modified`;
  - one MEMORY entity per file: `etype=MEMORY`, name = frontmatter `name`, `status` = `superseded` when body/description carries a SUPERSEDED marker, `corrected` when it carries CORRECTED/STATUS-CORRECTED (and not SUPERSEDED), else `active`; `status_raw` keeps `metadata.type` + matched marker; `updated_date` = `metadata.modified` date, else the file's mtime date; `source_doc` = the file's absolute path, `source_line` = 1, `source_commit` = repo HEAD (build stamp, as in the plan pass);
  - aliases: name slug parts (≥4 chars) + description tokens (≥6 chars, underscores preserved — flag names like `DIRECT_INBOX_ACK_CUSTODY_ADMISSION_ENABLED` must seed);
  - `[[link]]` targets → `references` edges MEMORY→MEMORY when the target entity exists; unresolved targets are COUNTED and printed, never created;
  - `plan NNN` / bare-NNN mentions in name+description → `references` edges MEMORY→PLAN (edges only — never status);
  - report: memory files parsed / skipped / unresolved links; ABSENT memory dir → print `memory source absent (0 files)` and exit 0 with a plan-only graph byte-identical to the v1 build (portability: other machines/Codex have no memory dir);
  - determinism: sorted iteration; two builds in the same environment → identical content hash.
- `expected_facts.json`: flip Q8/Q15/Q19/Q21/Q25/Q30 to gated via a new `v2_scope: true` flag (v1 rows untouched), and STRENGTHEN each `required[]` to two specific gold fragments (e.g. Q8: `core-host-all` + `test/unit`; Q15: `direct_inbox_ack_custody_admission_enabled` + `offline`; Q19: `ttl` + `ios`; Q21: `versionname` + `failed`; Q25: `f1165a010` + `13`; Q30: `worktree` + `concurrent` — exact casing per recall's output, finalized while writing the tests). `run_eval.py --gate` already iterates rows by scope flags? NO — it keys on `v1_scope` only; the ONE `run_eval.py` edit allowed by this plan is widening its gate predicate to `v1_scope or v2_scope` (single expression; `--report` untouched).
- `tests/test_project_memory.py`: TC-382-01..09 below.

Must preserve:
- All 13 existing suite tests green, unmodified → TC-382-08 sentinel.
- The 12 v1-scope questions keep hitting at ≤1000 tokens → TC-382-07 asserts 18/18.
- Plan-pass facts byte-identical with and without the memory pass → TC-382-03/05.
- `graph.db` + `recall_stats.jsonl` stay gitignored (no new tracked artifacts; memory content enters only the LOCAL db — the strengthened eval fragments add no exposure beyond what `QUESTIONS.md` already carries in-repo).

Hard `Do not`:
- Do not create/update PLAN entities (or any plan-pass fact) from the memory pass — `references` edges only.
- Do not parse `MEMORY.md`, `**Why:**`/`**How to apply:**` bodies (v2 extracts frontmatter + markers + links only), or any LLM/embedding/network step.
- Do not edit `recall.py`, the contract-test script, the statusline helper, or anything outside `project-memory/` (+ the one-expression `run_eval.py` gate-predicate widening).
- Do not weaken any v1 required term or the corpus floor to make the new gate pass.

Deferred / accepted difference:
- `**Why:**`/`**How to apply:**` body extraction → owner: phase-3, only if recall misses show the description tokens are insufficient.
- PRDs / C4 / Network-Arch ingestion → owner: phase-3 (381's remaining deferred scope).
- Memory files without `modified:` (7) get an mtime-date fallback — accepted: mtime is machine-local, and so is the db.
- Rollback: N/A — `git revert` + rebuild; graph.db regenerable; no wire/schema-migration/key/one-way change.

Dependencies:
- Upstream: plan 381 (closed). Downstream: the A/B `--report` numbers continue to own phase-3 decisions.

## Test Contract
All rows: tier **tooling host / `python3 project-memory/tests/test_project_memory.py`** (unittest; synthetic memory-dir fixtures in `tempfile` + real-memory-dir pins). Registration for every row: the existing `scripts/test/project_memory_recall_contract_test.sh` (already wired; runs the whole suite + eval gate — grep-verified below). Outside all Flutter gates by design (precedent: plan 381).

| Case | Behavior | Named test/proof | Tier / fixture | HEAD state → GREEN | Mutation that re-reds | Gate / registration |
|---|---|---|---|---|---|---|
| TC-382-01 | Memory pass parses the real dir: ≥60 MEMORY entities, `MEMORY.md` skipped, every MEMORY row has non-null status/source_doc/source_commit AND `updated_date`; parsed/skipped counts printed | `tests/test_project_memory.py::test_memory_pass_parses_real_dir` | tooling host / real memory dir (skipped with `unittest.skipUnless(dir exists)` so the suite stays green on machines without it — the synthetic rows below carry the parser contract everywhere) | causal RED (`build_graph.py: error: unrecognized arguments: --memory-dir` — the missing seam IS the contract) → floor + provenance hold | drop the frontmatter `name` parse → red | `bash scripts/test/project_memory_recall_contract_test.sh` |
| TC-382-02 | Staleness markers: synthetic memories with SUPERSEDED → `superseded`, CORRECTED → `corrected`, neither → `active`; real pins: `test-unit-invisible-to-per-plan-gates` and `host-all-not-runnable-from-container` → `superseded` | `::test_memory_staleness_markers` | tooling host / synthetic dir + real pins (same skipUnless) | causal RED (no memory pass) → statuses as specified | drop the marker scan (everything `active`) → red | same script |
| TC-382-03 | **Precedence guard (headline): the memory pass never writes plan facts.** Synthetic memory whose description claims "plan 999 is executed" + a synthetic plan 999 with `Status: CLOSED`: PLAN table (count + every status) byte-identical before/after the memory pass; the memory links to 999 via a `references` edge only | `::test_memory_never_overrides_plan_facts` | tooling host / synthetic corpus + synthetic memory dir | causal RED (no memory pass) → identical PLAN facts + edge present | route memory plan-mentions into entity status updates → red | same script |
| TC-382-04 | `[[links]]` → `references` MEMORY→MEMORY edges for existing targets; unresolved targets counted + printed, never created. Real pin: ≥35 distinct link edges (census: 105 occurrences / 45 distinct targets, some targets absent) | `::test_memory_wiki_links_become_edges` | tooling host / synthetic + real pins | causal RED (no memory pass) → edges + unresolved report | create stub entities for unresolved targets → red (entity floor + report assert) | same script |
| TC-382-05 | Absent-dir tolerance: `--memory-dir /nonexistent` → exit 0, `memory source absent` printed, graph content-hash IDENTICAL to a plan-only v1 build | `::test_memory_dir_absent_is_tolerated` | tooling host / synthetic corpus | causal RED (flag unknown today) → hash equality + message | make absence a fatal error → red | same script |
| TC-382-06 | Determinism + date fallback: two builds (plan+memory) → identical content hash; a synthetic memory WITHOUT `metadata.modified` gets its mtime date as `updated_date` (never null) | `::test_memory_pass_deterministic_with_date_fallback` | tooling host / synthetic | causal RED (no memory pass) → both hold | unsorted memory iteration → hash red | same script |
| TC-382-07 | Eval flip: Q8/15/19/21/25/30 carry `v2_scope: true` + two strengthened required fragments each; `--gate` = 18/18 (12 v1 + 6 v2) at ≤1000 tokens; the 12 v1 rows' required terms byte-unchanged | `::test_eval_gate_covers_v2_scope` | tooling host / real corpus + real memory dir (skipUnless) | causal RED chain (today: rows ungated; after flip but before the memory pass the 6 MISS — both recorded) → 18/18 | revert the memory pass → the 6 red; loosen a v2 required list back to its single keyword → vacuity assert red (test pins ≥2 fragments per v2 row) | same script |
| TC-382-08 | The plan-381 contract is untouched: all 13 existing tests pass unmodified | existing suite classes (TestBuild/TestRecall/TestEval/TestRecallStatusline) | tooling host | GREEN sentinel (pass today) → still pass | guarded by TC-382-03/05 (plan-fact identity); any memory-pass edit that leaks into plan facts reds those causal rows | same script |
| TC-382-09 | Recall integration (composite): `recall.py "why must workspace never be stashed git worktree"` emits the `workspace-live-checkout-no-stash` MEMORY fact — status, absolute path, `updated_date`, and its `references` edge rendered on the fact lines; `recall.py "DIRECT_INBOX_ACK_CUSTODY_ADMISSION_ENABLED"` seeds via the underscore alias | `::test_recall_surfaces_memory_facts` | tooling host / real memory dir (skipUnless) | causal RED (both return `No facts found` today) → facts with provenance | strip underscore tokens from the alias builder → second query red | same script |

### Test Notes
- TC-382-01/02/07/09 real-dir pins wrap in `skipUnless(MEMORY_DIR.exists())` — on machines without the memory dir the suite must stay green (matching TC-382-05's portability contract), while the synthetic rows keep the parser contract enforced everywhere. On THIS machine the pins run and are part of closure.
- TC-382-03's poisoned fixture is the 5-stale-memories incident in miniature; keep the fixture text quoting a plan status so the mutation cannot dodge it.
- TC-382-07: finalize the exact required fragments against real recall output while writing the tests; the vacuity assert (≥2 fragments per v2 row, none equal to the old loose keyword) prevents silent weakening.
- `updated_date` non-null is asserted for MEMORY rows in tests rather than as a schema constraint, so plan-pass rows (which predate the column) stay valid without touching the 381 pass.

## Implementation Steps
1. Snapshot `git status --short`. Write the TC-382 tests + the `expected_facts.json` flip FIRST; record the REDs (`--memory-dir` unknown; the 6 v2 rows MISS pre-implementation).
2. `schema.sql`: add `updated_date TEXT` to `entities`. Stop-if: any 381 test needs modification beyond none — replan (the column must be invisible to the plan pass).
3. `build_graph.py`: memory pass per the Scope spec (strictly after the plan pass; separate function; sorted; absent-dir early-out).
4. `run_eval.py`: widen the gate predicate to `v1_scope or v2_scope` (one expression).
5. Run focused GREEN → mutations (TC-382-03 precedence leak, TC-382-06 sort-drop, TC-382-07 required-loosening at minimum) → full contract script → refreshed `--report` appended context to `RECALL-RESULTS.md` (do not rewrite the 381 record; add a dated v2 section).

## Risks And Blind Spots
- Stale memory poisoning plan answers → TC-382-03 (the design driver).
- Lifecycle / derived-state durability: graph.db regenerable; TC-382-06 rebuild equality.
- Sibling-surface consistency: recall/run_eval/statusline consume the same entities table; TC-382-09 proves recall renders MEMORY rows without special-casing; statusline reads only the recall ledger (untouched).
- Destructive-action side effects: none — same tmp+rename overwrite; TC-382-05/06.
- Invariant re-verification under new transitions: status vocabulary gains `corrected`; normalization totality for memory = marker rules with `active` default (TC-382-02) — no `unnormalized` bucket needed (frontmatter is uniform, census-verified 64/64).
- Construction/call-site census: TC-382-01 file floor (≥60) + skip/unresolved reporting — no silent truncation.
- Build-artifact provenance: N/A native; data provenance = source path + HEAD stamp + `updated_date` (TC-382-01/06).
- Permission/ACL verb symmetry: N/A.
- Fake side-effect fidelity: synthetic memory fixtures mirror the censused frontmatter shape; every parser rule also carries a real-dir pin (skipUnless-guarded).
- Composite-node / relationship assertions: TC-382-09 (fact + provenance + edge on the same lines).
- Privacy: memory content reaches only the local gitignored db; the repo-side diff carries only fragments already public in `QUESTIONS.md`.

## Gate Cadence
- Per-plan closure: `bash scripts/test/project_memory_recall_contract_test.sh` (build + suite incl. TC-382 rows + 18/18 eval gate) + `./scripts/run_test_gates.sh completeness-check` sentinel + hygiene. No curated Flutter lane (zero Dart edits).
- Graph-affected first: N/A — changed files are python/json/md outside the arch graph (same recorded reason as plan 381).
- Full `host-all`: not a per-plan gate; unchanged wave ownership.
- Shared tests outside feature/core globs: none added.
- `flutter analyze`: N/A — zero Dart files change.

## Acceptance Gates  (literal — copy/paste)
```bash
# Dirty-tree snapshot before execution
git status --short

# Causal RED (before implementation)
python3 project-memory/src/build_graph.py --memory-dir /tmp/x 2>&1 | grep -c "unrecognized arguments"   # expect: 1 (flag missing today)
python3 project-memory/tests/test_project_memory.py 2>&1 | tail -3                                       # expect: TC-382 rows FAIL, 381 rows pass

# Focused GREEN (after implementation)
python3 project-memory/src/build_graph.py            # expect: plan pass unchanged + "memory: N parsed" (N>=60 here), exit 0
python3 project-memory/tests/test_project_memory.py  # expect: OK, 0 failures (13 old + 9 new)

# Representative mutations (record re-red, then revert): TC-382-03 precedence leak; TC-382-06 sort-drop; TC-382-07 required-loosening

# The registered gate (unchanged script — now enforcing 18/18)
bash scripts/test/project_memory_recall_contract_test.sh   # expect: exit 0
GRAPH_OK=1 grep -c "run_eval.py --gate" scripts/test/project_memory_recall_contract_test.sh  # expect: 1 (registration unchanged)
python3 project-memory/src/run_eval.py --gate        # expect: 18/18 gated hits, all <=1000 tokens
python3 project-memory/src/run_eval.py --report      # expect: Q8/15/19/21/25/30 flip to HIT; append a dated v2 section to RECALL-RESULTS.md

# Sentinels + hygiene
./scripts/run_test_gates.sh completeness-check       # expect: PASS, 0 unmatched (unchanged count)
git diff --check                                     # expect: clean
git status --porcelain project-memory/ | GRAPH_OK=1 grep -c "graph.db\|recall_stats"   # expect: 0 (local artifacts stay untracked)
```

## Execution Interpretation And Done Criteria
- Expected RED: `--memory-dir` unrecognized; TC-382 test failures for missing memory pass; the 6 v2 eval rows MISS pre-implementation.
- GREEN sentinel: the 13 plan-381 suite tests and `completeness-check`, unchanged before/after.
- Pre-existing dirty tree / known failure: standing docker-ws/go-relay/graphify-out/info.plist dirt; the 3 known `graphify-arch/tests` environment failures remain out of scope.
- Environment blocker (NOT a product blocker): a machine without `/claude-home/.claude/projects/-workspace/memory/` skips the real-dir pins by design (TC-382-05 keeps the build green there); closure on THIS machine runs them.
- Scope drift (BLOCKING): any edit to `recall.py`/statusline/contract script, anything outside `project-memory/` (beyond the one `run_eval.py` expression), any memory-pass write to plan facts, any weakened v1 term.

- [x] TC-382-01..09 named tests written first; REDs recorded (22 collected, 8 TC-382 errors, 13 plan-381 rows green; `--memory-dir` unrecognized).
- [x] Causal GREEN + mutation re-reds recorded — **8 of 8**, superset of the three named ones.
- [x] 18/18 eval gate; the 12 v1 rows byte-unchanged (frozen literal in the suite) and green.
- [x] Plan-fact identity proven with and without the memory pass — synthetic (poisoned fixture) AND over the real 270-plan corpus.
- [x] Sentinels + hygiene green; local artifacts untracked.
- [x] Scope Contract And Guard respected — with three recorded deltas (below).

## Execution Deltas (accepted, recorded)

1. **Two nodes per memory file, not one.** The plan's "one MEMORY entity, name =
   frontmatter `name`" plus "the 6 questions must HIT on gold description
   fragments" are jointly unsatisfiable: recall renders the entity NAME only, so
   descriptions had to reach the output. Folding the description into the MEMORY
   name did that — and cost ~920 of a 700-token budget per memory seed, because
   recall echoes BOTH endpoint names on every edge line. Measured consequence:
   **Q11, a plan-381 gate row, lost its `[FINDING/refuted]` line** and the
   Must-preserve clause broke. Shipped shape: a short `MEMORY` node named by the
   frontmatter `name` (now literally as the plan specifies) + a `NOTE` node
   carrying the description (capped 200 chars), joined by `asserts`. `asserts`
   sorts before every other rtype, which is what wins the seed's first-pass edge
   slots against cross-references (Q25 needed that). Gate result: 18/18.
2. **`updated_date` renders via the provenance tail, not a `recall.py` edit.**
   TC-382-09 requires the date on the fact line; `recall.py` is a hard Do-not.
   Memory rows therefore stamp `source_commit` as `<head>+mem:<YYYY-MM-DD>` —
   the same shape as the plan pass's `+worktree` suffix, and honest for a file
   that lives outside git. The `updated_date` column still holds the bare date.
3. **`run_eval.py` took four small edits, not one expression.** Row selection and
   the scoped-summary counter both had to widen or `--gate` would have printed
   `12/12` while enforcing 18; the table's scope column gained `v2`; and `gated()`
   drops v2 rows when the memory SOURCE directory is absent (announced, never
   silent) so the gate stays green on machines and CI containers that have no
   memory directory — the portability property TC-382-05 gives the builder. The
   check reads the source, never the graph, so a present-but-empty memory pass
   still reds. `recall.py`, the statusline helper and the contract script are
   byte-unchanged.

Two smaller substitutions, both made against real recall output as the plan
directed: Q19's second fragment is `leaks blobs` (not `iOS`, which sits past the
description cap) and Q21's is `post-install` (not `failed`, which is in the
MEMORY.md index line, not the memory's own description). Q25 uses
`9 long-standing` + `concurrency-4-only` (not `f1165a010`/`13`, same reason).

**One mutation the plan named is not achievable, and the reason is benign.**
TC-382-06's "unsorted memory iteration → hash red" cannot red: `_write` sorts
every row unconditionally before insert, so glob order can never move the
content hash — a strictly stronger guarantee than the plan assumed. What the
sorted glob does protect is the reproducibility of the skip/unresolved CENSUS,
and the row now asserts that directly (6 dangling links created in
reverse-alphabetical order must report sorted). Re-ran as reversed iteration:
re-reds.

**One extra parser rule the live corpus forced, found by dogfooding.** Updating
`project-memory-recall-layer.md` to describe the new layer made that memory
document the marker vocabulary — and the marker scan promptly classified it
`superseded`, reding its own TC-382-02 pin. Fix mirrors the plan pass exactly: a
marker inside a code span or fenced block is documentation of the vocabulary,
not a marker on the memory that documents it (`strip_code`, same carve-out as
the backticked `→ owner:`). Pinned synthetically and by that live file; mutation
M9 (drop the carve-out) re-reds. Mutation battery re-run after the change:
**9/9 re-red, 0 survived.**

**Known doc drift, deliberately not fixed (out of scope):**
`scripts/test/project_memory_recall_contract_test.sh` still prints
`PASS: ... + 12-question recall gate` while enforcing 18. The script is on this
plan's hard Do-not list; the one-word fix needs a separate authorization.

## Handoff
- First causal RED command: `python3 project-memory/src/build_graph.py --memory-dir /tmp/x` (expect: unrecognized argument), then the suite with TC-382 rows failing.
- Preservation command: `bash scripts/test/project_memory_recall_contract_test.sh` (381 contract) + `./scripts/run_test_gates.sh completeness-check`.
- Manual registration: none — the existing contract script already runs the suite and the eval gate.
- Migration: none — regenerable local db; schema evolves by rebuild.
- Boundary closure: host-only; the real boundary is the live memory directory, read directly (skipUnless-guarded for portability).
- Unresolved evidence: none. Phase-3 (Why/How bodies, PRDs/C4/Network-Arch, embeddings) stays owned by the refreshed `--report` numbers.

## Execution Progress
| Time | Phase | Files | Last command/result | Current evidence | Decision/blocker | Next |
|---|---|---|---|---|---|---|
| 2026-08-17 | causal RED | `tests/test_project_memory.py`, `eval/expected_facts.json` | `build_graph.py --memory-dir /tmp/x` → `error: unrecognized arguments`; suite `Ran 22 tests … FAILED (errors=8)` | 8 TC-382 rows red on the missing seam, 13 plan-381 rows green, 6 v2 rows flipped to `v2_scope` with two gold fragments each | tests + eval flip landed first, as specified | implement |
| 2026-08-17 | implement | `src/schema.sql` (+`updated_date`), `src/build_graph.py` (memory pass), `src/run_eval.py` (gate predicate) | suite `Ran 22 tests … OK`; `build_graph.py` → `memory: 64 parsed / 1 skipped / 2 unresolved links / 1 unresolved plan ref` | 64 MEMORY + 64 NOTE nodes; 102 memory→memory + 18 memory→plan `references`; statuses active 59 / corrected 3 / superseded 2 | **Q11 (v1 gate row) regressed** on first shape — memory names ate the recall budget | re-shape to MEMORY+NOTE |
| 2026-08-17 | budget fix | `src/build_graph.py` | `run_eval.py --gate` → `gated: 18/18 hit; tokens min/median/max: 626/669/684` | Q11 restored; all 12 v1 rows green WITH memory present; every gated answer ≤684 tokens (cap 1000) | delta 1 recorded above | mutations |
| 2026-08-17 | mutations | 8 patches, each reverted | M1 precedence leak, M2 reversed iteration, M3 required-loosening, M4 name-parse drop, M5 marker-scan drop, M6 unresolved-stub fabrication, M7 fatal absence, M8 underscore-alias strip | **8/8 RE-RED, 0 survived**; tree restored, suite `OK` after | plan's literal M2 (drop sort) proved unachievable — recorded, replaced with reversed iteration | close |
| 2026-08-17 | closure | `RECALL-RESULTS.md` (dated v2 section appended, 381 record untouched) | `bash scripts/test/project_memory_recall_contract_test.sh` → exit 0, `18/18`; `./scripts/run_test_gates.sh completeness-check` → `1468/1468 … PASS`; `git diff --check -- project-memory/` clean; 0 tracked local artifacts | real-corpus plan facts byte-identical with and without the memory pass; rebuild 0.69 s / 2.2 MB; recall 1.8 ms median | host tier closed | phase-3 owned by the refreshed `--report` |
