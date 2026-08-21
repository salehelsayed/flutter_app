# Codex document memory

`codex-memory/` is Codex CLI's own deterministic knowledge graph for plans,
specifications, PRDs, architecture notes, decisions, reviews, and selected
project history. It is separate from Graphify's code graph on purpose:

- Codex memory: **what was decided, specified, refuted, deferred, or
  superseded?**
- Graphify: **where is the code, what calls it, and what tests/impact does a
  change have?**

No source-code glob is accepted by the builder. No network, embedding, or model
call is used. The database and telemetry are local derived state.

## Normal commands

```sh
python3 codex-memory/memory.py query "why can delivery ack not cancel push?"
python3 codex-memory/memory.py status
python3 codex-memory/memory.py status --verify-content
python3 codex-memory/memory.py refresh --force
python3 codex-memory/memory.py stats --session current
python3 codex-memory/memory.py benchmark
python3 codex-memory/memory.py statusline
```

`query` auto-refreshes when the stat fingerprint is stale. The default output
budget is 300 estimated tokens, with a 900-token hard cap. A full content-hash
audit is opt-in because hashing every document on every query costs more than a
stat check; set `freshness.check` to `content` if that trade-off is preferable.

## What Codex controls

Tracked defaults live in [`config.json`](config.json):

- source roots, include/exclude globs, source floors, and trust priority;
- automatic refresh and stat-vs-content freshness checking;
- default/hard token budgets, seed breadth, traversal depth, snippets, and
  per-document diversity;
- local state and evaluation paths.

For local experiments, create ignored `config.local.json`. Dictionaries merge
recursively and source rows merge by `name`, so a small override is enough:

```json
{
  "freshness": {"check": "content"},
  "retrieval": {"default_budget": 240},
  "sources": [
    {"name": "selected-project-history", "enabled": false}
  ]
}
```

The default corpus has four configured sources over two adapters:

1. `tdd-plan-facts` imports the already test-proven deterministic status,
   supersession, refuted-finding, and deferred-owner extraction from
   `project-memory`. It does **not** import Claude's external session-memory
   directory.
2. `architecture-and-product-documents` indexes Markdown headings and bounded
   sections under `Network-Arch/`, `docs/`, and `UI-*`.
3. `selected-project-history` indexes explicitly named spec/decision/audit/
   roadmap/matrix/review-style documents in `Test-Flight-Improv/`, excluding
   TDD plans and session breakdowns already covered elsewhere.
4. `knowledge-system-documents` indexes the project-memory experiment/report
   and this Codex-memory guide, so future sessions can recall why the two-graph
   design and its measurement rules exist.

Every result carries `document:line @commit` provenance. The graph stores the
actual source SHA-256 in every entity and uses an atomic SQLite replacement plus
manifest update. Concurrent sessions serialize refreshes through a local lock.

## Measurement and privacy

Real CLI queries append to ignored `state/usage.jsonl`. Records contain hashed
question/session/thread IDs, budget, token estimate, hit/confidence/coverage,
latency, refresh cost, and graph fingerprint. They never contain question text.

The fail-open `PreToolUse` hook separately counts broad document searches and
whether a recall query preceded them. Reading one named document never causes a
reminder, but the hook anonymously measures partial/whole configured-document
reads and their estimated input tokens. `stats` joins the two anonymous ledgers,
which exposes:

- recall calls, hits/misses, broad answers, output tokens, coverage, and p95;
- broad document sweeps, grounded vs ungrounded sweeps, reminders, and
  auto-refreshes;
- configured-document read calls, whole-file reads, and estimated raw input
  tokens—without recording filenames or command text.

Disable query telemetry with `CODEX_MEMORY_TELEMETRY=0` or the reminder with
`CODEX_MEMORY_REMINDER=0`. Override the reminder cadence with
`CODEX_MEMORY_REMINDER_CEILING`.

## Current acceptance gate

`benchmark` runs the 12 established plan-recall questions plus three real
document questions spanning the notification PRD, connection architecture, and
QA docs. It scores required fragments only in the returned output, never in the
question. This prevents a vacuous benchmark and gives config changes a cheap
regression gate.
