# 381 - Project-Memory Deterministic Graph Recall (B arm of the knowledge-recall A/B)

Status: IMPLEMENTED — host-green 2026-08-17 (TC-381-01..10 GREEN, 3 named mutations re-red, completeness-check sentinel unchanged; see Execution Progress + Execution Result)
Type: New Feature
Spec: free-text intent (no formal spec) — requirements in `project-memory/QUESTIONS.md` (30 questions, verified golds, derived ontology) + `project-memory/BASELINE-RESULTS.md` (A-arm baseline, 2026-08-17)
Classification: implementation-ready
Closure tier: host (pure tooling; no app code, no device)

## Planning Progress
| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-08-17 | Evidence Collector (census) | 267 `*-tdd-plan.md`, 00-INDEX tail, `.gitignore`, `scripts/test/` listing, graphify-arch tests wiring, python/sqlite toolchain | Status-header surface is heterogeneous (25+ raw shapes, 10 headerless); header-vs-execution staleness proven BOTH directions (377, 212); refuted/deferred/supersession shapes censused; python3.9.2 + sqlite 3.34.1 + recursive CTE OK in-container; graphify-arch python tests run in NO gate (scripts/test/*_contract_test.sh is the tooling-gate convention); numbers 379 AND 380 claimed by a concurrent session mid-planning | Design contract |
| 2026-08-17 | Planner | tier-matrix, sufficiency-checklist, plan-template, QUESTIONS.md, BASELINE-RESULTS.md, graph-memory-starter (fetched, MIT) | All tests are tooling-host python (outside every Flutter tier by design); v1-scope = the 12 deterministically-answerable questions; NN=381 allocated after two races | Emit plan |

## Problem And Evidence
- Behavior to improve: answering project-knowledge questions (plan status, supersession, refuted findings, deferred ownership) costs a fresh session ~45k tokens and ~3.1 min each via raw repo search (A-arm baseline: 30/30 correct, ~1.34M tokens total). There is no queryable, deterministic recall layer; the graphify arch graph excludes markdown BY DESIGN, and session memory was proven the STALE layer (5 golds overturned by the baseline).
- Impact: every fresh session, subagent, and workflow re-pays the search cost; stale status snapshots (memory, 00-INDEX rows) mislead planning (baseline evidence: 263-267/302/303 "planned-only" memory vs executed reality; agents flagged 00-INDEX rows stale in Q1/Q2/Q5).
- Confirmed current gap (no root cause invented — this is new tooling): no `project-memory/` implementation exists; `project-memory/` holds only `QUESTIONS.md` + `BASELINE-RESULTS.md`. Extraction surface confirmed by census 2026-08-17 on 267 plan files: 257 carry `^Status:` headers; 86 carry refuted-findings sections (shapes: `- Refuted findings:` ×37, `(do NOT re-introduce)` variants ×~16, `### Refuted findings (do NOT re-introduce)` ×6); 7 modern `→ owner:` deferred lines + recurring `Deferred device work:` lines; 77 plans mention supersession with the deterministic seam `superseded by plan NN` (pinned live example: `148-minimum-parity-encrypted-push-spool-tdd-plan.md` → "## CLOSED — superseded by plan 327").
- **Header-staleness inversion (the headline extraction hazard, proven live):** plan 377's header reads `Status: execution-ready` (line 3) while its Execution Progress records "PLAN 377 CLOSED at device tier" and the 00-INDEX row reads CLOSED — and plan 212's closure verdict states the header was left `awaiting-review` deliberately. Header-only extraction reproduces exactly the staleness this layer exists to kill. Precedence rule: in-file closure evidence > `Status:` header. (00-INDEX verdicts are NOT a v1 source — baseline proved index rows stale for 265-267.)
- Existing coverage: none. `graphify-arch/tests/test_graphify_arch_tooling.py` is the only comparable python tooling suite and it is wired into no gate (grep-verified) — this plan does better via the `scripts/test/` contract-test convention.
- Missing coverage: everything (new feature): schema/build determinism, status normalization + precedence, refuted/deferred/supersession extraction, corpus floor, recall budget/determinism/no-fabrication, relationship rendering, eval scoring.
- Refuted findings (do NOT re-introduce):
  - "Plan `Status:` headers are always authoritative" — REFUTED (377 stale-open, 212 deliberately unstamped). Precedence extraction is mandatory (TC-381-03).
  - "LLM extraction for v1" — excluded by requirement; the baseline proved snapshot-style curation goes stale in weeks; v1 is deterministic-only so rebuilds are free and drift-proof.
  - "UserPromptSubmit push injection in v1" — excluded by decision (pull-based CLI only; most session traffic is code-shaped).
  - "Vendor the starter repo" — adapt the 3-table/alias/recursive-traversal PATTERN from github.com/Glitch-Cat-Club/graph-memory-starter (MIT; attribute in `schema.sql` header comment); import no code.
- Unresolved findings: none material.
- Affected production / test / gate files: NEW `project-memory/src/{schema.sql,build_graph.py,recall.py,run_eval.py}`, `project-memory/eval/expected_facts.json`, `project-memory/tests/test_project_memory.py`, `scripts/test/project_memory_recall_contract_test.sh`; EDIT `.gitignore` (+`project-memory/graph.db`). Zero Dart/Go/relay files.

## Graph Grounding Snapshot
- Graph fingerprint / freshness: `585839a9908225b8`; stale-marker present (`.needs_incremental_refresh`) — NOT refreshed for this plan: freshness is not load-bearing because the change surface is markdown + new python, both outside the arch graph's source set (`.dart/.go/.sh/.py` of EXISTING app code; md excluded by design per `GRAPH_SELECTION.md`). The Stop-hook auto-refresh owns the rebuild for the next code-touching session.
- Query / profile: `python3 graphify-arch/tdd_context.py query "project-memory recall extraction over Test-Flight-Improv plan corpus QUESTIONS.md eval runner" --profile tdd --budget 300` → `confidence=broad`, anchors unrelated (orbit/exit-intent noise) — CONFIRMS the premise: this knowledge layer has no graph presence and cannot be grounded there.
- Anchors: none usable; grounding for this plan is the corpus census in Problem And Evidence (command-verified 2026-08-17).
- Surfaced proof/gate files: none from the graph; convention source = `scripts/test/*_contract_test.sh` (8 live precedents, `ls`-verified).
- Graph gaps that required raw source search: the entire markdown corpus (by design), scripts/test conventions, `.gitignore`, toolchain probes.
- Reuse rule: anchors are search starting points only; every conclusion above carries a census command or file citation.

## Scope Contract And Guard
In scope:
- `project-memory/src/schema.sql`: SQLite, 3 tables — `entities(id, name, etype, status, status_raw, source_doc, source_line, source_commit, built_at)`, `relations(src_id, dst_id, rtype, source_doc, source_line)`, `aliases(alias, entity_id)` — every entity row REQUIRES non-null status/source_doc/source_commit (ontology "required fields").
- `project-memory/src/build_graph.py`: deterministic extractor over `Test-Flight-Improv/*-tdd-plan.md` ONLY (v1 corpus). Per file: one PLAN entity (aliases: `NN`, `plan NN`, `plan-NN`, slug); raw `Status:` header captured; closure-marker scan over the whole file (`PLAN \d+ CLOSED`, `Final Execution Verdict`, `Status:` containing `CLOSED|DEVICE-GREEN|device-proven`); ordered keyword normalization to the QUESTIONS.md status vocabulary with precedence closure-evidence > header, and an explicit `unnormalized` bucket (raw preserved in `status_raw`); refuted-findings sections (all three censused shapes) → FINDING entities (`status=refuted`, first bullet line as name, tokens ≥6 chars as aliases) + `refutes` edges from plan; `→ owner:` and `Deferred device work:` lines → GAP entities + `deferred_to` edge carrying owner text; `superseded by plan (\d+)` → `supersedes` edge (cited plan supersedes the file's plan) + `superseded` status on the older plan. Atomic write (tmp+rename); sorted iteration everywhere (byte-stable rebuilds); prints parsed/skipped/unnormalized counts and the full skip list; exits nonzero when parsed < 250.
- `project-memory/src/recall.py "<question>" [--budget 700]`: tokenize the question; seed via exact + case-insensitive alias match; traverse `relations` ≤2 hops (recursive CTE); emit one line per fact — `entity [etype/status] --rtype--> entity [status] (source_doc:line @commit)` — deterministically ordered, truncated at budget (chars/4 ≈ tokens, hard cap 1000); zero seeds → exactly `No facts found for: <terms>` (no fabrication ever).
- `project-memory/eval/expected_facts.json`: the 30 QUESTIONS.md questions as machine-checkable rows — `{id, category, query, required[], v1_scope}`; `v1_scope: true` for the 12 deterministically-answerable questions **Q1-Q6, Q9, Q11, Q12, Q26, Q27, Q28** (status/refuted/deferred facts); false for the rest (constraint/proof/policy narrative — phase-2 ingestion).
- `project-memory/src/run_eval.py`: `--gate` = run the 12 v1-scope questions through recall; exit 0 iff every `required[]` substring appears AND every output ≤ 1000 tokens; `--report` = all 30 with per-question tokens + hit/miss table (the B-arm artifact to set against BASELINE-RESULTS.md).
- `scripts/test/project_memory_recall_contract_test.sh`: build → unittest suite → `run_eval.py --gate`; pure python3, container-runnable (the scripts/test host-run rule binds dart/flutter invokers only — this script has none).
- `.gitignore`: add `project-memory/graph.db` (derived, regenerable).

Must preserve:
- Flutter test discovery/gates byte-untouched → guarded structurally: no file under `test/` or `integration_test/`, no `run_test_gates.sh` edit; `completeness-check` sentinel (TC-381-11).
- `project-memory/QUESTIONS.md` + `BASELINE-RESULTS.md` are read-only inputs — extractor and eval must not rewrite them.

Hard `Do not`:
- Do not parse `00-INDEX.md` as a status source in v1 (proven stale for 265-267); do not write to it from tooling.
- Do not add LLM calls, embeddings, network access, or a UserPromptSubmit hook (v1 boundaries; phase-2 candidates only after the B-arm report).
- Do not touch `graphify-arch/`, `graphify-out/`, or any Dart/Go/relay file.
- Do not let recall emit any text not present in `graph.db` rows (anti-fabrication invariant, TC-381-08).

Deferred / accepted difference:
- Constraint/proof/policy questions (the 18 `v1_scope:false`) → owner: phase-2 ingestion decision, taken from the `--report` numbers; v1 reports them without gating.
- Alias/synonym misses on unseen phrasings → owner: phase-2 (embedding seeding only if the report proves alias matching insufficient — starter repo's own guidance).
- Corpus beyond `*-tdd-plan.md` (PRDs, C4, Network-Arch) → owner: phase-2.
- Rollback: N/A — new isolated directory + one `.gitignore` line; `git revert` restores HEAD; `graph.db` is regenerable and untracked; no wire/schema/key/one-way change.

Dependencies:
- Upstream: none (QUESTIONS.md/BASELINE-RESULTS.md already exist). Downstream: the A/B go/no-go decision consumes `run_eval.py --report`.

## Test Contract
All rows: tier **tooling host / `python3 project-memory/tests/test_project_memory.py` (unittest, Python 3.9.2, sqlite3 3.34.1 — recursive CTE probe-verified in-container)**. Fixtures: SYNTHETIC mini-corpus in `tempfile` dirs for parser rules (drift-immune) + REAL-corpus pins for reachability (production writer = the plan corpus itself). Registration for every row: `scripts/test/project_memory_recall_contract_test.sh` (NEW gate script, house convention; grep-verified) — plus direct commands below. Outside all Flutter gates by design.

| Case | Behavior | Named test/proof | Tier / fixture | HEAD state → GREEN | Mutation that re-reds | Gate / registration |
|---|---|---|---|---|---|---|
| TC-381-01 | Build is deterministic + provenance-total: two builds over the same corpus → byte-identical `graph.db` content hash; EVERY entity row has non-null status, source_doc, source_line, source_commit | `project-memory/tests/test_project_memory.py::test_build_deterministic_and_provenance_total` | tooling host / synthetic corpus | causal RED (`ModuleNotFoundError: build_graph` — missing module IS the contract) → equal hashes + zero null-provenance rows | drop sorted iteration in `build_graph.py` (dict order) → hash mismatch red | `bash scripts/test/project_memory_recall_contract_test.sh`; grep-verify the script exists |
| TC-381-02 | Status normalization is a total function over the censused shapes: `execution-ready`→execution-ready; `awaiting-review`/`reviewed`→proposed; `IMPLEMENTED host-green`/`Plan-green`/`completed`/`accepted`/`EXECUTED`→executed; `CLOSED`/`DEVICE-GREEN`/`device-proven`→closed; junk→`unnormalized` (raw kept); headerless→`unknown` | `::test_status_normalization_rule_table` | tooling host / synthetic files, one per shape | causal RED (module missing) → each shape maps as specified | delete the `Plan-green` rule → that fixture red | same script |
| TC-381-03 | **Precedence: closure evidence outranks a stale-open header.** Synthetic plan with header `Status: execution-ready` + body `PLAN 999 CLOSED at device tier` → `closed` (both raws preserved). REAL pin: plan 377 → `closed` despite its line-3 header | `::test_closure_evidence_outranks_header` | tooling host / synthetic + real corpus | causal RED (module missing) → both assertions hold | make extraction header-only → synthetic AND 377 red | same script |
| TC-381-04 | Refuted-findings extraction across all three censused shapes → FINDING(status=refuted) + `refutes` edge + alias tokens. REAL pins: 377→finding containing "genesis"; 317→"skia"; 315→"H1" | `::test_refuted_findings_extraction` | tooling host / synthetic (3 shapes) + real corpus | causal RED (module missing) → findings + edges present | drop the `### Refuted findings` heading shape from the parser → synthetic-shape-3 red | same script |
| TC-381-05 | Deferred-with-owner extraction: `→ owner:` lines and `Deferred device work:` lines → GAP + `deferred_to` w/ owner text. REAL pin: 377 yields ≥4 deferred rows incl. owners "multi-device wave" and "future plan" | `::test_deferred_owner_extraction` | tooling host / synthetic + real corpus | causal RED (module missing) → rows + owners present | capture the item but drop the owner text → red | same script |
| TC-381-06 | Supersession: `superseded by plan NN` → `supersedes` edge + `superseded` status on the older plan. REAL pin: 327 supersedes 148; 148 → status superseded | `::test_supersession_edge` | tooling host / synthetic + real corpus | causal RED (module missing) → edge + status flip | drop the regex → red | same script |
| TC-381-07 | Corpus census floor + no silent truncation: real-corpus build parses ≥250 plan files, prints skipped list + unnormalized count, exits nonzero below floor | `::test_corpus_floor_and_skip_report` | tooling host / real corpus | causal RED (module missing) → parsed ≥250, report lines present; floor-violation path proven via a synthetic 3-file corpus with floor injected | narrow the glob to `3[0-9][0-9]-*` → red | same script |
| TC-381-08 | Recall: deterministic (same query twice → byte-identical), budget-bounded (default 700, hard 1000 tokens), and **fabrication-free** — every emitted `source_doc` exists in `graph.db`; zero seeds → exactly `No facts found for: <terms>` | `::test_recall_deterministic_budgeted_grounded` | tooling host / synthetic + real corpus | causal RED (`recall` module missing) → all four properties | remove the budget truncation → over-budget fixture red | same script |
| TC-381-09 | Relationship rendering (composite assertion): query `plan 377` → ONE output containing, in single fact lines, status `closed`, the `refutes`→genesis finding edge, and a `deferred_to` line with its owner — the relationship + provenance on the same line, not disconnected mentions | `::test_recall_renders_relationships` | tooling host / real corpus | causal RED (module missing) → composite lines present | render entity names without relation/source suffix → red | same script |
| TC-381-10 | Eval runner: `--gate` passes iff all 12 `v1_scope` questions hit every `required[]` substring within ≤1000 tokens each; `--report` emits all 30 with per-question token counts. Scorer is non-vacuous: flipping one required substring to a nonsense literal makes `--gate` fail | `::test_eval_gate_and_scorer_not_vacuous` | tooling host / real corpus + expected_facts.json | causal RED (`run_eval` missing) → gate exit 0 on the 12; doctored-expectation run exits nonzero | make the scorer substring-match against the QUERY instead of recall OUTPUT → doctored run passes → red | same script |
| TC-381-11 | Flutter harness untouched: no new path under `test/`/`integration_test/`; discovery gate unaffected | `./scripts/run_test_gates.sh completeness-check` | existing Flutter gate | GREEN sentinel (passes today) → still PASS, 0 unmatched | relocating the suite under `test/project_memory/` would red this gate (unmatched path) — the guarding seam is placement itself | existing gate; no registration |

### Test Notes
- TC-381-01 "compile-RED": the missing modules are the intentional contract (same convention as plan 377's TC-377-04 enum-RED). Record the exact `ModuleNotFoundError` before implementation.
- TC-381-03/04/05/06 real-corpus pins cite facts that are CLOSED and stable (377 closure, 317/315 refuted lists, 148→327). If a pin ever churns, fix the pin with a census, never by weakening the parser.
- TC-381-10's 12-question gate list is fixed in `expected_facts.json`; changing `v1_scope` flags is a reviewed edit, not a tuning knob.
- `sqlite3.sqlite_version` 3.34.1 supports recursive CTEs (probe-verified); no external deps — stdlib only.

## Implementation Steps
1. Snapshot `git status --short` (expect the standing docker-ws/go-relay/graphify-out/info.plist dirt + this plan file). Write `project-memory/tests/test_project_memory.py` + `expected_facts.json` FIRST; record the causal REDs (`ModuleNotFoundError` ×3 module groups; completeness-check green as sentinel baseline).
2. `schema.sql` (3 tables + indices on aliases.alias and relations.src_id/dst_id; header comment attributing the adapted MIT graph-memory-starter pattern). Stop-if: any required-field column would need to be nullable — replan, the ontology forbids it.
3. `build_graph.py` per the Scope spec. Stop-if: the census floor cannot reach 250 without loosening determinism — replan the corpus glob, do not lower the floor silently.
4. `recall.py` per the Scope spec (seeding, ≤2-hop recursive CTE, budget, no-fabrication).
5. `run_eval.py` (`--gate` / `--report`).
6. `scripts/test/project_memory_recall_contract_test.sh` (build → unittest → gate; `set -euo pipefail`). Add `project-memory/graph.db` to `.gitignore`.
7. Run focused GREEN → mutations (TC-381-01 sort-drop, TC-381-03 header-only, TC-381-10 scorer-vacuity at minimum) → sentinels → `--report` for the A/B verdict.

## Risks And Blind Spots
- Corpus drift breaks real-corpus pins → pins chosen from CLOSED/stable plans (377/317/315/148); synthetic fixtures carry the parser rules; TC-381-07's floor is a count, not a list.
- Lifecycle / derived-state durability: `graph.db` is derived + untracked + atomically rebuilt; TC-381-01 proves rebuild equality (delete-and-rebuild = same content).
- Sibling-surface consistency: N/A — no app surfaces; the one adjacent system (Flutter gates) is guarded by TC-381-11.
- Destructive-action side effects: build overwrites only `graph.db` via tmp+rename; TC-381-01; nothing else written outside `project-memory/`.
- Invariant re-verification under new transitions: normalization totality (TC-381-02's `unnormalized` bucket) — no raw status can crash or silently vanish.
- Construction/call-site census: TC-381-07 (files parsed vs skipped, printed, floored) — the extractor equivalent of a call-site census; no `lib/` symbols involved.
- Build-artifact provenance: N/A native artifacts; data provenance = required source_doc/source_line/source_commit fields (TC-381-01).
- Permission/ACL verb symmetry: N/A.
- Fake side-effect fidelity: synthetic fixtures replicate CENSUSED corpus shapes, and every parser rule also carries a real-corpus pin proving the shape is production-reachable.
- Composite-node/relationship assertions: TC-381-09.
- Scorer gaming (recall echoes the question): TC-381-08 anti-fabrication + TC-381-10 scorer-vacuity mutation.

## Gate Cadence
- Per-plan closure: the python suite + eval gate via `scripts/test/project_memory_recall_contract_test.sh`, the `completeness-check` sentinel, hygiene. No curated Flutter lane is affected (zero Dart edits) — running one would be ceremony.
- Graph-affected first: N/A — changed files are markdown/python outside the arch graph's source set; `tdd_context.py affected` has no import edges to report. Recorded as the reason, not skipped silently.
- Full `host-all`: not a per-plan gate and NOT owed by this plan (no `test/` files); the standing 36x-38x notification wave owns the next aggregate.
- Shared tests outside feature/core globs: none added (the suite lives under `project-memory/tests/`, walked by no Flutter gate — that is the design, and TC-381-11 proves the walked roots are untouched).
- `flutter analyze`: N/A — zero Dart files change; `git diff --check` covers hygiene.

## Acceptance Gates  (literal — copy/paste)
```bash
# Dirty-tree snapshot before execution (expect standing docker-ws/go-relay/graphify-out/info.plist dirt)
git status --short

# Causal RED (before implementation) — each must FAIL with ModuleNotFoundError for the missing module
python3 project-memory/tests/test_project_memory.py 2>&1 | grep -c "ModuleNotFoundError"   # expect: >=1
./scripts/run_test_gates.sh completeness-check                                             # sentinel baseline: PASS, 0 unmatched

# Focused GREEN (after implementation) — expect exit 0, zero failures, census floor satisfied
python3 project-memory/src/build_graph.py            # expect: "parsed >= 250", skip list printed, exit 0
python3 project-memory/tests/test_project_memory.py  # expect: OK, 0 failures

# Representative mutations (record re-red, then revert): TC-381-01 sort-drop; TC-381-03 header-only; TC-381-10 scorer-vacuity

# The registered gate (house tooling convention; pure python3 — container-runnable)
bash scripts/test/project_memory_recall_contract_test.sh   # expect: exit 0 (build + suite + eval --gate)
ls scripts/test/project_memory_recall_contract_test.sh     # registration check: file exists
GRAPH_OK=1 grep -c "run_eval.py --gate" scripts/test/project_memory_recall_contract_test.sh  # expect: 1

# Sentinel: Flutter harness untouched
./scripts/run_test_gates.sh completeness-check       # expect: PASS, 0 unmatched (same count as baseline)

# B-arm eval artifacts (the deliverable this plan exists for)
python3 project-memory/src/run_eval.py --gate        # expect: exit 0 — 12/12 v1-scope hits, all outputs <=1000 tokens
python3 project-memory/src/run_eval.py --report      # expect: 30-row table w/ per-question tokens; compare to BASELINE-RESULTS.md

# Hygiene
git diff --check                                     # expect: clean
GRAPH_OK=1 grep -c "project-memory/graph.db" .gitignore   # expect: 1
```

## Execution Interpretation And Done Criteria
- Expected RED: `ModuleNotFoundError` on the three module groups (build_graph/recall/run_eval) before implementation — the intentional new-feature contract.
- GREEN sentinel: `completeness-check` PASS with an unchanged unmatched-count, before AND after.
- Pre-existing dirty tree / known failure: standing `docker-ws`/`go-relay-server`/`graphify-out`/`info.plist` modifications; the 3 known environment failures in `graphify-arch/tests/` are unrelated and out of scope.
- Environment blocker (NOT a product blocker): none expected — pure in-container python; no device, simulator, relay, or host bridge involved.
- Scope drift (BLOCKING): any edit under `lib/`, `test/`, `integration_test/`, `scripts/run_test_gates.sh`, `graphify-arch/`, or any LLM/network call appearing in `project-memory/src/`.

- [x] Every behavior has a named test (TC-381-01..10) or the named sentinel (TC-381-11).
- [x] Causal RED (`ModuleNotFoundError: No module named 'build_graph'`), focused GREEN (10/10), and the three named mutation re-reds recorded.
- [x] Contract-test gate green; completeness-check sentinel unchanged (1466/1466 before and after).
- [x] Registration verified: gate script exists and invokes suite + eval gate (`run_eval.py --gate` count 1, `.gitignore` count 1).
- [x] `run_eval.py --report` produced and archived at `project-memory/RECALL-RESULTS.md`, next to BASELINE-RESULTS.md.
- [x] `git diff --check` clean; Scope Contract And Guard respected (zero edits under `lib/`, `test/`, `integration_test/`, `run_test_gates.sh`, `graphify-arch/`).

## Handoff
- First causal RED command: `python3 project-memory/tests/test_project_memory.py` (after writing the suite; expect ModuleNotFoundError).
- Preservation command: `./scripts/run_test_gates.sh completeness-check`.
- Manual registration: create `scripts/test/project_memory_recall_contract_test.sh` (the one registration surface; grep-verified, house convention).
- Migration: none — standalone tooling SQLite; explicitly NOT an app `DB v##` (migrations `100_`-`105_` untouched).
- Boundary closure: host-only; the "real boundary" is the live plan corpus, which the suite reads directly.
- Unresolved evidence: none. Go/no-go on phase 2 (broader ingestion, push injection, embeddings) is owned by the `--report` numbers vs BASELINE-RESULTS.md, not by this plan.

## Execution Progress
| Time | Phase | Files | Last command/result | Current evidence | Decision/blocker | Next |
|---|---|---|---|---|---|---|
| 2026-08-17 | Census re-verification (pre-implementation) | 269 `*-tdd-plan.md`, `.gitignore`, `scripts/test/` | corpus census re-run at execution time | 269 plan files (not 267 — 379/380/381 landed mid-plan); 259 `^Status:` headers + 1 bullet-form (`110`), 9 headerless; refuted shapes 37/8/6/4 + inline-after-colon variants; `→ owner:` 13 lines in 4 files; `Deferred device work:` 61 files, majority `none.`; `superseded by plan NN` in only 3 files; `PLAN \d+ CLOSED` in 2; `Final Execution Verdict` heading in 92 | Three planned rules would have written WRONG facts and were tightened before implementation (see Execution Deviations) | write suite first |
| 2026-08-17 | Causal RED | `tests/test_project_memory.py`, `eval/expected_facts.json` | `python3 project-memory/tests/test_project_memory.py` → `ModuleNotFoundError: No module named 'build_graph'` (count 1) | Sentinel baseline `./scripts/run_test_gates.sh completeness-check` → **PASS, 1466/1466 classified** | RED is the intended new-feature contract | implement |
| 2026-08-17 | Implementation | `src/schema.sql`, `src/build_graph.py`, `src/recall.py`, `src/run_eval.py` | `python3 project-memory/src/build_graph.py` → parsed **269**, entities 551, relations 283, skipped 0, unnormalized 5 (all printed), floor 250 satisfied | 269 PLAN + 238 FINDING + 44 GAP; 238 `refutes`, 44 `deferred_to`, 1 `supersedes`; 6,312 aliases; rebuild 0.87 s | Two real defects found by the suite and fixed: finding aliases lost hyphenated compounds; recall emitted facts alphabetically and truncated the on-question fact (Q9 genesis) | focused GREEN |
| 2026-08-17 | Focused GREEN | suite + gate script | `python3 project-memory/tests/test_project_memory.py` → **OK, 10/10, 0 failures**; `bash scripts/test/project_memory_recall_contract_test.sh` → **PASS** | `run_eval.py --gate` → **12/12 v1-scope hits**, 627–690 tokens each (cap 1000); recall latency 2.0/3.5/5.7 ms min/median/max | Gate green | mutations |
| 2026-08-17 | Mutations (3 named + revert) | `src/build_graph.py`, `src/run_eval.py` | TC-381-01 sort-drop (`sorted(set(...))`→`set(...)`) → RED "entities was not written in sorted order"; TC-381-03 header-only (closure override disabled) → RED (synthetic 999 AND real 377); TC-381-10 scorer-vacuity (`output`→`row["query"]`) → RED, 11 of 12 gate rows miss | Each reverted; suite re-GREEN after every revert. Echo-guard proven causal independently: under the mutation the query-only term scores `pass=True`, reverted `pass=False` | Mutation set complete | sentinels |
| 2026-08-17 | Sentinels + hygiene | none (guard is placement) | `./scripts/run_test_gates.sh completeness-check` → **PASS, 1466/1466** (identical to baseline) | `git diff --check` clean on this plan's files; `git check-ignore` confirms `project-memory/graph.db` ignored at `.gitignore:196`; zero edits under `lib/`, `test/`, `integration_test/`, `run_test_gates.sh`, `graphify-arch/` (those working-tree entries pre-date this session) | TC-381-11 GREEN | B-arm report |
| 2026-08-17 | B-arm artifact | `project-memory/RECALL-RESULTS.md` | `python3 project-memory/src/run_eval.py --report` → 30 rows archived | **A vs B: ~45k → ~680 tokens/question; ~3.1 min → ~3.5 ms; 11 → 1 tool call; 12/12 v1-scope.** Extraction surfaced **36 plans whose `Status:` header is stale-open** vs their own in-file execution records | Phase-2 go/no-go input recorded next to BASELINE-RESULTS.md | close |

### Execution Deviations (census-driven, all tightening — recorded, not silent)
The plan's Scope named three extraction seams that the execution-time census
proved would emit WRONG facts. Each was tightened before implementation, and
each tightening carries its own pinned negative case in the suite:

1. **`superseded by plan NN` is not a supersession seam on its own.** It occurs
   in 3 files; only 148 → 327 is real. Plan 231 uses it about *wording*, and this
   plan (381) quotes the syntax in its own spec text — a naive rule would have
   recorded "381 is superseded by plan 327". The seam is restricted to markdown
   HEADING lines. Pinned: `test_supersession_edge` asserts 381 is NOT superseded.
2. **`Final Execution Verdict` presence is not closure evidence.** 11 of the 92
   sections are unfilled placeholders — plan 259's reads `(pending)`, which is
   exactly the plan whose gold answer says "gates/QA still unproven". The body
   must carry a completion token, and the closed tier reads only the verdict's
   opening line (deeper in a section, `CLOSED` refers to bugs or contract rows —
   plan 135's "all 6 bugs CLOSED host-side" is the pin). The scan was also
   widened past `Final Execution Verdict` to the censused terminal-verdict
   titles, because plan 317's closure lives under `## Execution Result`
   (`**CLOSED 2026-08-01.**`) — without that, Q6 would have reported 317 as
   `execution-ready`, i.e. the stale header the plan exists to override.
3. **`PLAN \d+ CLOSED` must match the file's OWN plan number**, and
   `Deferred device work:`/`→ owner:` values that read `none.` (or sit inside
   backticks as syntax documentation) are skipped. Both hazards are live in this
   plan's own text.

Additive, census-backed and outside any contract row: the bullet-form
`- **Status:** …` header (1 file, plan 110) is recognized alongside `^Status:`;
finding/gap aliases include hyphenated compounds as well as ≥6-char tokens; and
recall orders facts by how many question terms each fact contains, which is what
makes the on-question fact survive budget truncation.

## Execution Result

**CLOSED at host tier 2026-08-17.** All 10 contract rows GREEN
(TC-381-01..10) plus the TC-381-11 placement sentinel unchanged at 1466/1466;
three named mutations re-red and reverted; the registered gate
`scripts/test/project_memory_recall_contract_test.sh` passes end to end
(build → suite → 12-question eval gate). B-arm numbers archived in
`project-memory/RECALL-RESULTS.md`: ~680 tokens and ~3.5 ms per answered
question against the A arm's ~45k tokens and ~3.1 min, 12/12 on the v1 scope,
every fact carrying `doc:line @commit` provenance. No Dart, Go, relay, device or
Flutter-gate surface was touched. Phase-2 (broader corpus, then embeddings only
if alias seeding proves insufficient) is owned by the report, not by this plan.
