# A/B Baseline Results — "Claude + normal repo search" (2026-08-17)

Protocol: 30 fresh `general-purpose` agents, one question each (from
QUESTIONS.md, quarantined out of the repo during the run so no agent could
read the gold answers), instructed to answer from /workspace content only.
Metrics from the harness per-agent usage accounting; answers scored against
gold, with every gold/answer conflict re-verified against the repo by hand.

## Aggregates

| Metric | Value |
|---|---|
| Correct answers | **30 / 30** (Q18 correct, with one clause honestly flagged repo-unanswerable) |
| Wrong or stale agent answers | **0** |
| Gold answers overturned by the baseline | **5** (Q2, Q3, Q4, Q20 fully; Q5 partially) |
| Tokens (total / avg / range) | **~1.34M / ~45k / 31k–63k** per question |
| Tool calls (total / avg / range) | **329 / 11 / 5–33** |
| Wall time (median / mean / range) | **~2.2 min / ~3.1 min / 27s–12.2min** |

## Headline findings

1. **Correctness is not the graph's opportunity — cost is.** A fresh session
   answers these questions correctly from the repo because the plan corpus is
   disciplined (Status headers, refuted-findings sections, 00-INDEX). The bar
   for project-memory recall is therefore: the SAME correct facts at ~400
   tokens / milliseconds instead of ~45k tokens / ~3 minutes — a ~100x cost
   reduction, not an accuracy rescue.
2. **The curated memory layer was the stale one.** Five gold answers written
   from session memory were out of date; the repo was ground truth every
   time (plans 263-266 and 302/303 executed weeks ago, 259 committed, relay
   at v1.8.0 not v1.7.5). Any project-memory design MUST derive status
   deterministically from the artifacts on change — a memory snapshot ages
   in weeks here. This is the strongest empirical argument yet for the
   supersession/status fields, and against LLM-extract-once pipelines.
3. **Agents repeatedly flagged 00-INDEX.md rows as stale** (Q1, Q2, Q5)
   while plan Status headers were current — extraction should treat plan
   headers as authoritative and the index as derived (or generate the index
   from the graph).
4. **One memory-only fact surfaced** (Q18: `dart fix --apply` breaking
   final-field constructors is recorded nowhere in the repo). Small but real
   category: ops/incident knowledge that project-memory would need explicit
   ingestion for, since no document extraction can find it.
5. Caveat: subagents had the session-memory index visible in context, yet in
   all five divergences they sided with repo evidence over memory — the
   baseline is genuinely repo-grounded, arguably more than the gold was.

## Per-question results

Verdict: OK = matches verified ground truth. OK+ = correct AND richer/fresher
than the drafted gold (gold corrected in QUESTIONS.md).

| Q | Topic | Verdict | Tokens | Calls | Time |
|---|---|---|--:|--:|--:|
| 1 | Plan 377 status | OK (also flagged stale header stamp) | 36.9k | 5 | 30s |
| 2 | Plans 263-267 status | **OK+ (gold was stale: 263-266 executed 07-20/21; 267 Wave 0)** | 40.1k | 6 | 46s |
| 3 | Plan 302 status | **OK+ (gold stale: implemented-verified 07-29)** | 37.9k | 6 | 37s |
| 4 | Plan 303 status | **OK+ (gold stale: completed 07-30)** | 52.7k | 20 | 5.2m |
| 5 | Plan 259 state | **OK+ (gold stale in part: committed 2be07626e 07-19; QA still unproven)** | 35.3k | 8 | 49s |
| 6 | State-guard root cause | OK | 34.7k | 5 | 27s |
| 7 | host-all runnability | OK (verified live in-container too) | 62.7k | 22 | 3.8m |
| 8 | test/unit gate visibility | OK | 34.1k | 8 | 52s |
| 9 | Genesis-fix refuted | OK | 39.6k | 9 | 61s |
| 10 | transportPeerId "bug" | OK (found refutation in 3 docs + Go source) | 46.9k | 10 | 70s |
| 11 | Self-reaction [] by design | OK | 50.6k | 5 | 2.7m |
| 12 | Skia churn refuted | OK | 31.5k | 7 | 38s |
| 13 | Disappearing predicate asymmetry | OK (found plan 359 reverse-mutation proof) | 51.5k | 18 | 2.7m |
| 14 | E2E request suppression | OK | 49.5k | 19 | 3.4m |
| 15 | Custody admission flag | OK (incl. flip timestamp + live 218-refusal evidence) | 61.2k | 9 | 6.2m |
| 16 | Compiled-out features | OK | 53.8k | 15 | 5.5m |
| 17 | Private-media copy tone | OK | 33.0k | 6 | 66s |
| 18 | Analyzer policy | OK; dart-fix clause correctly flagged repo-unanswerable | 58.3k | 33 | 12.2m |
| 19 | Relay ACL / Android bg no-op | OK | 53.1k | 24 | 7.1m |
| 20 | Relay version state | **OK+ (gold stale: v1.8.0 since 08-16; v1.7.0 burned confirmed)** | 49.4k | 11 | 7.0m |
| 21 | Deploy provenance proof | OK | 33.5k | 5 | 49s |
| 22 | 377 device-tier necessity | OK (verified unexported closure in source) | 52.9k | 6 | 67s |
| 23 | Pinned device pair | OK | 48.2k | 5 | 51s |
| 24 | flutter test -d landmine | OK (incl. recovery path) | 37.4k | 11 | 4.4m |
| 25 | Pre-existing host-all reds | OK (9+13 baggage, 6 fixed f1165a010) | 51.1k | 14 | 5.8m |
| 26 | Linked-surface silent drop | OK | 36.4k | 11 | 4.5m |
| 27 | Remove-reaction deferral | OK (current line numbers too) | 36.5k | 8 | 3.8m |
| 28 | Persisted-reason gap | OK | 41.0k | 8 | 99s |
| 29 | host-all ownership | OK | 48.0k | 6 | 81s |
| 30 | Workspace stash policy | OK (found the plan-152/319 incident history) | 47.4k | 9 | 4.7m |

## What the injection arm must now beat

Per answered question: ≤ ~1k tokens and ≤ ~1s recall (vs 45k / 3.1min), with
zero wrong facts and staleness no worse than the artifacts themselves. Run
the same 30 questions with graph recall injected; kill the project if it
can't hold ~≥27/30 correct at that cost, per the eval discipline in
QUESTIONS.md. Category A (status) answers must come from deterministic
extraction of plan headers — the only layer proven fresh in this run.
