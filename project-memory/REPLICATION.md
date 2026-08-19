# Building a Deterministic Knowledge-Graph Recall Layer — Replication Guide

How mknoon's `project-memory/` layer was designed, measured, built, and wired
into Claude (2026-08-17), with the A/B numbers that justified each step.
Written so the same approach can be replicated in another project.

## 1. What it is, in one picture

```
                       Question from a session/agent
                                   │
              ┌────────────────────┴────────────────────┐
              │                                         │
       PROJECT-MEMORY                              CODE GRAPH (graphify)
       "what is true / decided / open?"            "where is it / who calls it?"
              │                                         │
       plan statuses, supersession,                symbols, files, callers,
       refuted findings, deferred items,           tests, gates, impact
       team memory (landmines, policies)                │
              │                                         │
       ~670 tokens, ~2-10 ms,                      ~600 tokens, ~4 s
       every fact carries doc:line @commit              │
              └────────────────────┬────────────────────┘
                                   ▼
                          raw file reads (grep/Read)
                          only for exact text and censuses
```

Two graphs, deliberately separate. The code graph answers *where/how*; the
knowledge graph answers *what should be true and why*. Raw search remains the
right tool for exact-text questions — no graph replaces it.

The knowledge layer itself is deliberately boring: **3 SQLite tables**
(entities / relations / aliases — pattern adapted from the MIT-licensed
[graph-memory-starter](https://github.com/Glitch-Cat-Club/graph-memory-starter),
no code vendored), a **deterministic extractor** (no LLM, no network, no
embeddings), and a **budget-bounded recall CLI** (alias seeding → ≤2-hop
recursive SQL traversal → fact lines). Rebuild: 0.7 s for ~330 documents.

## 2. The method (this is the part worth replicating)

### Step 1 — Questions first, never ontology first
We wrote **30 real questions** the project repeatedly pays to re-answer, each
with a **gold answer and provenance** (`QUESTIONS.md`). The entity/relation
vocabulary was then *derived from the questions* (8 entity types, 10
relations, one status vocabulary) — several types we'd guessed upfront earned
zero questions and were dropped. If a fact type answers no real question, it
does not enter the ontology.

### Step 2 — Measure the baseline BEFORE building anything
The A arm: 30 fresh agents, one question each, plain repo search, gold
answers quarantined out of reach. Result (`BASELINE-RESULTS.md`):

| Metric | A: repo search |
|---|---|
| Correctness | 30/30 |
| Tokens per question | ~45k (31k–63k) |
| Wall time per question | ~3.1 min (27 s–12.2 min) |
| Tool calls per question | 11 (5–33) |

**The baseline reframed the whole project.** Fresh search was *correct* —
and it exposed that our curated memory layer was the stale one (5 gold
answers written from memory were overturned by the repo, same week). Two
design rules fell out, and everything else followed from them:

1. **The target is cost, not correctness.** The graph must return the same
   facts ~100× cheaper, not "smarter" answers.
2. **Facts must be re-derived from the artifacts on every rebuild** —
   deterministic extraction, never a curated snapshot, never LLM-extract-once.
   Any snapshot layer goes stale in weeks; a free rebuild cannot.

### Step 3 — Census the documents, then write extraction rules with teeth
Before writing the parser we counted what actually exists: 267 plan files,
257 with `Status:` headers in **25+ raw shapes**, 86 refuted-findings
sections in 3 formats, supersession phrases where only 1 of 3 was real.
Hazards found by census, each turned into a pinned rule + test:

- **Headers lie.** Files' own execution records outrank their status
  headers (36 of 267 headers were stale-open). Rule: closure evidence >
  header.
- **Placeholders are not facts.** `(pending)`, `none.`, unfilled verdict
  sections must extract as nothing.
- **Prose about a thing is not the thing.** "superseded by plan NN" counts
  only on heading lines; a marker inside a code span is documentation.
- **Generated indexes are not sources.** Our human-maintained index file was
  proven stale; it is excluded as an input.

### Step 4 — Build it as a TDD plan, not a script
Plan 381: every parser rule got a synthetic fixture (drift-immune), a
real-corpus pin (proves the rule is reachable), and a **mutation that
re-reds it** (proves the test can fail). Non-negotiable properties, each
test-pinned:

- **Deterministic**: same corpus → byte-identical database, twice.
- **Provenance-total**: every fact carries `source_doc:line @commit`
  (NOT NULL columns — a fact that can't say where it came from can't enter).
- **Honest misses**: zero seeds → exactly `No facts found for: …`, never a
  guess; recall can only emit text that exists as a database row.
- **Budget-bounded**: output capped (default 700 tokens, hard 1000).
- **Non-vacuous scoring**: the eval scores recall *output* against required
  gold fragments — a mutation proves scoring the *question* instead fails.

### Step 5 — The B arm, same 30 questions (`RECALL-RESULTS.md`)

| Metric | A: repo search | B: graph recall |
|---|---|---|
| Tokens per question | ~45k | **~680** (626–690) |
| Wall time | ~3.1 min | **~2–10 ms** |
| Tool calls | 11 | **1** |
| Gated questions answered | — | 12/12 (v1), 18/18 after phase 2 |
| Whole-corpus rebuild | n/a | **0.7 s** |

~66× token reduction, ~50,000× latency reduction. The 12 questions that
still miss need *sources not yet ingested* (an ingestion gap), not better
retrieval — which is the finding that gates every future expansion.

### Step 6 — Wiring it into Claude (adoption is a feature, not an afterthought)
A tool nobody is told about sits unused. Five wires, in order of impact:

1. **Project instructions (CLAUDE.md)** — one bullet: for plan-status /
   supersession / refuted-finding / deferred-ownership questions, run
   `python3 project-memory/src/recall.py "<question>"` BEFORE any corpus
   sweep; rebuild after editing plan files; trust it over session memory and
   index files. *This is the single highest-leverage wire*: instructions
   load at session start, before the first bad habit forms.
2. **Skill/workflow prompts** — the planning skill queries recall before its
   verify pass (so refuted fixes aren't re-planned); the review skill checks
   whether a plan's bet matches an already-refuted finding.
3. **Deny messages** — the repo's search gate already redirects raw greps;
   its message names the graph tools at the exact moment of a bad search.
4. **Usage telemetry** — `recall.py` appends one JSONL line per CLI call
   (timestamp, hashed question, tokens, hit/miss, ms). Eval and tests call
   the function directly, so the ledger holds only real usage.
5. **A visible counter** — the CLI statusline shows `recall N (M hit)` for
   today, next to `graphify N reads · M redirected`. Deployed-but-unused
   renders as a visible `recall 0`.

**Proof the wiring matters** (natural experiment, same day, same repo): a
session started *before* wire 1 landed grepped the stale index for plan
status 297 times and never called recall. The first session started *after*
called recall as its **second command**. The rule at session start is the
difference.

### Step 7 — Phase 2 only after a measured miss (plan 382)
The 6 eval misses all lived in one un-ingested source (the account-scoped
session-memory folder — also invisible to subagents and Codex). Ingesting it
followed the same discipline plus one new **precedence law, proven by
incident**: the lower-trust source may create its own entities and
`references` edges but may **never create or update a fact owned by a
higher-trust source** (a poisoned-fixture test enforces it). Result: 18/18
gated, memory facts now shared with every agent, build still 0.7 s, and the
build stays green on machines that lack the memory folder entirely.

### Step 8 — What we deliberately did NOT build, and the tripwires
- **Embeddings** — alias seeding has produced zero phrasing-misses; every
  real miss was a missing *source*. Tripwire: the ledger shows `hit: false`
  on questions whose facts ARE in the graph.
- **LLM extraction in the build loop** — would make rebuilds expensive and
  non-reproducible, recreating the staleness problem. If unstructured docs
  must be ingested later: LLM as a *one-time author* of structured
  frontmatter (reviewed in git), deterministic parser forever after.
- **Automatic injection into every prompt** — pull-based adoption is
  working; push would tax the majority of prompts that don't need it.
  Tripwire: the statusline counter sits near zero for a week despite the
  rules.

## 3. The recipe for a new project

1. Write 20–30 real questions your project repeatedly pays to re-answer,
   each with a gold answer and its source. (Half a day. This file is the
   ontology, the eval set, and the go/no-go criterion in one.)
2. Run the baseline: fresh agents, one question each, gold answers
   quarantined. Record correctness, tokens, time, tool calls. Expect
   surprises — ours was that the *curated* layer was the stale one.
3. Census your documents' actual structure (status lines, marker sections,
   cross-references). Write extraction rules only for what the census
   proves, with a floor count so silent truncation is impossible.
4. Build: 3 tables, deterministic extractor, alias-seeded budget-bounded
   recall, an eval runner that gates only the deterministically-answerable
   subset and *reports* the rest. Every rule: synthetic fixture + real pin
   + mutation. Provenance NOT NULL. Honest misses.
5. Establish precedence: artifacts > snapshots; closure evidence > headers;
   lower-trust sources never overwrite higher-trust facts.
6. Wire adoption: project-instructions rule (the big one), skill prompts,
   usage ledger, visible counter.
7. Expand only when a ledger or eval shows a measured miss — and re-run the
   same eval after every expansion; it doubles as the regression suite.

## 4. File inventory (this repo)

| File | Role |
|---|---|
| `project-memory/QUESTIONS.md` | 30 questions + golds + derived ontology |
| `project-memory/BASELINE-RESULTS.md` | A-arm numbers + design pivots |
| `project-memory/RECALL-RESULTS.md` | B-arm numbers + limitations |
| `project-memory/src/schema.sql` | 3 tables, provenance NOT NULL |
| `project-memory/src/build_graph.py` | deterministic extractor (plans + memory passes) |
| `project-memory/src/recall.py` | budget-bounded recall CLI + usage ledger |
| `project-memory/src/run_eval.py` | `--gate` (18 gated Qs) / `--report` (all 30) |
| `project-memory/src/recall_statusline.py` | `recall N (M hit)` statusline fragment |
| `project-memory/tests/test_project_memory.py` | 22 tests, all mutation-verified |
| `scripts/test/project_memory_recall_contract_test.sh` | the registered gate: build → suite → eval |
| `Test-Flight-Improv/381-*.md`, `382-*.md` | the two TDD plans (design rationale + deviations) |

## 5. The five lessons that transfer

1. **Measure the baseline first.** Ours flipped the goal from "answer
   better" to "answer 66× cheaper", and killed a wrong assumption about
   which layer was stale — before any code existed.
2. **Deterministic extraction beats clever extraction** wherever documents
   have any structure. Free rebuilds are what make the graph trustworthy.
3. **Precedence rules must come from incidents, and become tests.** Both of
   ours (closure-evidence > headers; artifacts > memory) were proven by
   same-day staleness incidents and are enforced by poisoned-fixture tests.
4. **Adoption is a deliverable.** Instructions at session start, prompts at
   decision moments, a ledger, and a visible counter — without these the
   tool measures nothing because nobody uses it.
5. **Expansion waits for a measured miss.** Every capability we skipped has
   a named tripwire in the telemetry. The eval set is permanent — it gates
   every future phase as a regression suite.
