# Codex-memory baseline

Measured 21 August 2026 with the tracked default configuration. This is a
retrieval benchmark, not yet an end-to-end Codex-agent A/B; real-session
adoption and raw document-read cost are measured separately by `stats`.

## Gate

Command:

```sh
CODEX_MEMORY_TELEMETRY=0 python3 codex-memory/memory.py benchmark
```

Result:

| Metric | Result |
|---|---:|
| Correctness | 15/15 |
| Established plan questions | 12/12 |
| New spec/architecture/QA questions | 3/3 |
| Average output | 146 estimated tokens |
| Same 12 plan questions | 152.5 estimated tokens/question |
| Warm recall p95 | 21.9 ms |
| End-to-end CLI, including startup + stat freshness check | 0.14–0.18 s |
| Full refresh | ~4–7 s |
| Local database | ~40 MiB |

The older project-memory B arm reported roughly 680 tokens over its plan gate;
on those same 12 established questions this default is about 78% smaller. The
original raw-search baseline was roughly 45,000 tokens/question, but that is a
historical reference rather than a same-session Codex A/B.

## Guardrails for configuration changes

- Correctness stays 15/15.
- Average output should stay below 220 estimated tokens unless a new gate
  proves that more context is necessary.
- Warm p95 should stay below 100 ms.
- A smaller token budget is not an improvement if it turns focused answers
  broad, omits one explicit plan anchor, or returns only a truncation header.
- Source expansion must answer a measured miss and must not add source-code
  files to the document graph.

## What real sessions should tell us next

After several new Codex sessions, run:

```sh
python3 codex-memory/memory.py stats --session all --days 7
```

The first optimization targets are, in order:

1. ungrounded broad document searches;
2. whole-document input tokens after recall already identified a narrower
   section;
3. broad/miss recall results (ranking or corpus gaps);
4. repeated auto-refreshes (source scope or freshness-policy cost).

Do not optimize for a higher recall call count. A named plan that genuinely
needs a complete read is correct behavior; the useful signal is whether broad
search and unrelated whole-file input fell without lowering answer coverage.
