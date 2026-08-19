# B-Arm Results — "Claude + project-memory graph recall" (2026-08-17)

Companion to `BASELINE-RESULTS.md` (A arm: Claude + normal repo search). Same 30
questions from `QUESTIONS.md`. Produced by plan 381
(`Test-Flight-Improv/381-project-memory-deterministic-recall-tdd-plan.md`).

Protocol: `project-memory/src/build_graph.py` extracts the graph deterministically
from `Test-Flight-Improv/*-tdd-plan.md`; `recall.py` answers each question from
`graph.db` alone; `run_eval.py --report` scores every answer's REQUIRED substrings
against the recall OUTPUT (never against the question — TC-381-10 pins that with a
mutation). No model call, no network, no embeddings anywhere in the arm.

Reproduce: `bash scripts/test/project_memory_recall_contract_test.sh`, then
`python3 project-memory/src/run_eval.py --report`.

## A vs B

| Metric | A: repo search | B: graph recall |
|---|---|---|
| Tokens per question | ~45k (31k–63k) | **~680** (627–690) |
| Wall time per question | ~3.1 min mean (27s–12.2 min) | **~3.5 ms** median (2.0–5.7 ms) |
| Tool calls per question | 11 (5–33) | **1** |
| v1-scope questions answered | 12 / 12 | **12 / 12** |
| Whole-corpus rebuild | n/a | 0.87 s (269 files, 1.6 MB db) |

That is a ~66x token reduction and a ~50,000x latency reduction on the 12
questions v1 is contracted to answer, with the facts carrying `doc:line @commit`
provenance on every line.

## Graph shape

269 PLAN + 238 FINDING + 44 GAP entities; 238 `refutes`, 44 `deferred_to`, 1
`supersedes` relation; 6,312 aliases. 82 plans contribute refuted findings, 37
contribute deferred items with owners.

Plan status distribution: executed 159, closed 63, execution-ready 21, proposed
10, unknown 9, unnormalized 3, superseded 2, refuted 2.

## Per-question results

`v1` rows are gated by `run_eval.py --gate`. `phase-2` rows are reported only;
their `required` terms are single loose keywords, so a HIT there means "the graph
surfaced related grounded facts", not "the question was answered".

| Q | scope | tokens | hit | missing |
|---|---|--:|---|---|
| Q1 | v1 | 686 | HIT | - |
| Q2 | v1 | 681 | HIT | - |
| Q3 | v1 | 654 | HIT | - |
| Q4 | v1 | 661 | HIT | - |
| Q5 | v1 | 627 | HIT | - |
| Q6 | v1 | 679 | HIT | - |
| Q7 | phase-2 | 642 | HIT | - |
| Q8 | phase-2 | 37 | MISS | test/unit |
| Q9 | v1 | 690 | HIT | - |
| Q10 | phase-2 | 656 | MISS | transportPeerId |
| Q11 | v1 | 678 | HIT | - |
| Q12 | v1 | 683 | HIT | - |
| Q13 | phase-2 | 647 | HIT | - |
| Q14 | phase-2 | 653 | HIT | - |
| Q15 | phase-2 | 653 | MISS | custody |
| Q16 | phase-2 | 660 | HIT | - |
| Q17 | phase-2 | 670 | HIT | - |
| Q18 | phase-2 | 638 | HIT | - |
| Q19 | phase-2 | 639 | MISS | custody |
| Q20 | phase-2 | 684 | HIT | - |
| Q21 | phase-2 | 631 | MISS | deploy |
| Q22 | phase-2 | 681 | HIT | - |
| Q23 | phase-2 | 627 | HIT | - |
| Q24 | phase-2 | 663 | HIT | - |
| Q25 | phase-2 | 631 | MISS | host-all |
| Q26 | v1 | 680 | HIT | - |
| Q27 | v1 | 687 | HIT | - |
| Q28 | v1 | 672 | HIT | - |
| Q29 | phase-2 | 656 | HIT | - |
| Q30 | phase-2 | 646 | MISS | worktree |

Q8's 37-token row is the honest failure mode working as designed: nothing in the
plan corpus aliases to that phrasing, so recall printed `No facts found for: ...`
rather than a guess.

## Headline findings

1. **The A arm's conclusion holds: cost was the opportunity, not correctness.**
   B answers the same 12 questions at ~680 tokens / ~3.5 ms.

2. **Extraction found 36 plans whose `Status:` header is stale-open.** In-file
   closure evidence outranks the header (21 `proposed → executed`, 4
   `execution-ready → closed`, 3 `proposed → closed`, 3 `executed → closed`, 3
   `execution-ready → executed`, 2 from unnormalizable headers). Plans 377 and
   317 are the pinned examples: both headers still read `execution-ready`, and
   both are closed in their own execution records. Header-only extraction would
   have reproduced exactly the staleness this layer exists to kill.

3. **Placeholders are the main false-fact hazard, and they are everywhere.** 11
   of the 92 `Final Execution Verdict` sections are unfilled (`(pending)`,
   `<pending execution>`, `(to be filled at execution)`); most `Deferred device
   work:` lines read `none.`; and `CLOSED` appearing deeper in a verdict section
   usually refers to bugs or contract rows, not the plan (plan 135: "all 6 bugs
   CLOSED host-side"). Each of these is a pinned negative case in the suite.

4. **Prose about supersession is not supersession.** `superseded by plan NN`
   occurs in 3 files; only one (148 → 327) is a real supersession. The others
   describe *wording* being superseded (231) and quote the syntax in a spec (381,
   this plan). The seam is restricted to markdown heading lines, so the graph
   records 1 `supersedes` edge instead of 3, two of which would have been wrong.

5. **The alias layer, not the traversal, is the recall bottleneck.** Every v1
   answer is reached in ≤2 hops, and the misses in the phase-2 set are all
   seeding misses on vocabulary that never appears in the plan corpus (Q8
   `test/unit`, Q15/Q19 relay-flag names, Q30 `git worktree`) — i.e. exactly the
   facts QUESTIONS.md predicted live only in session memory or in non-plan docs.

## Known limitations (phase-2 decision input)

- **Fidelity is capped by the artifacts.** The graph is exactly as fresh as the
  plan files; it cannot know a closure that was never written down. This is the
  intended trade: rebuild is free (0.87 s) and drift-proof, versus a curated
  snapshot that the A-arm run proved goes stale in weeks.
- **Multi-stage plans report their strongest stage.** Plan 326 is `closed` on the
  strength of its Stage-1 `## Execution Result` while Stage 2 is still blocked.
  `status_raw` preserves the full header for drill-down; recall renders only the
  normalized status.
- **Corpus is `*-tdd-plan.md` only.** PRDs, C4 docs, `00-INDEX.md` (deliberately
  excluded — the A run proved its rows stale), Network-Arch and the session
  memory directory are unread. Categories C/D/F answers therefore mostly come
  back as related-but-not-answering facts.
- **3 plan headers remain `unnormalized` and 9 are headerless.** They are printed
  in full by every build rather than silently bucketed.

## Go / no-go

The kill criterion in QUESTIONS.md was "≥27/30 correct at ≤ ~1k tokens and ≤ ~1s".
Within the v1 contract (12 questions) the arm is 12/12 at ~680 tokens and ~3.5 ms.
Extending to the remaining 18 is an ingestion problem, not a retrieval problem:
they need sources the v1 corpus does not include. That is the phase-2 decision —
broader corpus first, and embeddings only if alias seeding proves insufficient
after the corpus grows.

---

# v2 — session-memory ingestion (2026-08-17, plan 382)

Everything above is the plan-381 record and is unchanged. This section reports
the second corpus pass added by
`Test-Flight-Improv/382-project-memory-session-memory-ingestion-tdd-plan.md`,
which ingests the account-scoped session-memory directory
(`/claude-home/.claude/projects/-workspace/memory`, 64 fact files + a generated
index) and closes 6 of the 18 questions v1 left ungated.

Reproduce: `bash scripts/test/project_memory_recall_contract_test.sh`, then
`python3 project-memory/src/run_eval.py --report`.

## What changed

| | v1 (plan 381) | v2 (plan 382) |
|---|---|---|
| Gated questions | 12 | **18** (12 v1 + 6 v2) |
| Gate result | 12/12 | **18/18** |
| Tokens per gated answer | ~680 | **~669 median** (626–684) |
| Recall latency | ~3.5 ms median | **1.8 ms median** (0.8–3.8) |
| Entities | 270 PLAN + 246 FINDING + 46 GAP | + **64 MEMORY + 64 NOTE** |
| Relations | 246 refutes, 46 deferred_to, 1 supersedes | + **120 references, 64 asserts** |
| Aliases | 6,412 | **8,590** |
| Whole-corpus rebuild | 0.81 s / 1.7 MB | **0.69 s / 2.2 MB** |

Memory status distribution: active 59, corrected 3, superseded 2. Frontmatter
types: project 49, feedback 9, reference 6. `references` splits 102
memory→memory (from `[[wiki-links]]`) + 18 memory→plan.

## The six flips

| Q | was | now | gold fragments that had to appear in the OUTPUT |
|---|---|---|---|
| Q8 | MISS `test/unit` | HIT | `core-host-all` + `test/unit` |
| Q15 | MISS `custody` | HIT | `DIRECT_INBOX_ACK_CUSTODY_ADMISSION_ENABLED` + `offline` |
| Q19 | MISS `custody` | HIT | `leaks blobs` + `TTL` |
| Q21 | MISS `deploy` | HIT | `versionName` + `post-install` |
| Q25 | MISS `host-all` | HIT | `9 long-standing` + `concurrency-4-only` |
| Q30 | MISS `worktree` | HIT | `worktree` + `concurrent` |

Each v2 row carries TWO specific fragments, not the single loose keyword it had
while ungated — `custody` / `deploy` / `host-all` prove only that related facts
surfaced. The suite pins that: `TC-382-07` fails if any v2 row drops below two
fragments, and separately fails if the same rows can be answered against a
plan-only graph (which would mean the memory pass is not what closes them).

## Honest reading of the 30-row table

`run_eval.py --report` now shows 30/30 HIT. **That headline is not 30/30
answered.** The 12 rows still labelled `phase-3` keep their v1-era single loose
keywords (`relay`, `device`, `release`, `linked`, `analyze`, …), so their HIT
means "the graph surfaced related grounded facts". Only the 18 gated rows are
scored against fragments strong enough to mean the question was answered.

## Design notes worth keeping

1. **Memory is the lower-trust layer, by construction.** On the same day this
   was written, 5 memory entries were caught claiming plan statuses the plan
   corpus refutes. The memory pass therefore runs strictly after the plan pass
   and may only add its own nodes and edges out of them; it can never create or
   move a plan fact. Proven both synthetically (a fixture memory that asserts
   "plan 999 is execution-ready" against a `CLOSED` plan 999) and over the real
   corpus: plan facts are byte-identical with and without the memory pass.

2. **Two nodes per memory file, for budget reasons.** The first implementation
   folded the description into the MEMORY node's name. Recall echoes both
   endpoint names on every edge line, so one memory seed then cost ~920 of a
   700-token budget and knocked Q11 — a plan-381 gate row — out of its own
   answer. Splitting into a short `MEMORY` node (frontmatter `name`) plus a
   `NOTE` node (description, capped at 200 chars) joined by `asserts` fixed it;
   `asserts` sorts before every other rtype, which is what wins the seed's
   first-pass slots against cross-references.

3. **Markers are case-sensitive.** `SUPERSEDED` and `CORRECTED` are markers;
   lowercase "superseded"/"supersession" in prose is history being described.
   Two memories (`project-memory-recall-layer`, `relay-ec2-deployment`) discuss
   supersession and must stay `active` — both are pinned.

4. **Approximations are not plan references.** `~150 test closures` is prose
   about magnitude; plan 150 exists, so a naive bare-number rule would have
   drawn a wrong edge. Numbers with no plan in the corpus (`uid 501`) are
   counted and printed, never invented — as are the 2 unresolved `[[links]]`.

5. **`updated_date` rides the provenance tail.** Memory files live outside git,
   so a bare HEAD stamp would overstate their freshness. Every memory fact
   renders `@<head>+mem:<YYYY-MM-DD>`; 57 of 64 dates come from
   `metadata.modified`, the other 7 from file mtime.

## Portability

The memory directory is account-scoped and absent on other machines, in CI
containers and for Codex. An absent directory produces a graph byte-identical to
a plan-only build (exit 0, `memory source absent (0 files)`), the real-memory
test pins skip, and `--gate` announces that it is dropping the 6 v2 rows rather
than failing on them. v1 stays gated everywhere.

## Phase-3 decision input

Still unread: `**Why:**` / `**How to apply:**` memory bodies (v2 extracts
frontmatter + markers + links only), PRDs, C4 docs, Network-Arch. The 12
remaining questions need those sources, or stronger required terms, before their
HITs mean anything. Embeddings remain excluded until alias seeding demonstrably
runs out — it has not yet.
