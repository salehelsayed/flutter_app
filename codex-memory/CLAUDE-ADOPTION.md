# Claude-side adoption of codex-memory (2026-08-25)

What the Claude Code sessions in this repository adopted from the Codex-side
knowledge tooling, and the measurement protocol that governs widening it.
Decision record: items 1 and 2 were adopted as mechanisms, item 3 as
discipline; the Codex hook stack itself (`codex_memory_reminder.py`,
`context_rollover.py`, `task_run.py`) was deliberately NOT ported — it is
~500KB of hook code plus ~500KB of tests solving gaps the Claude harness
mostly covers natively (output caps, file-state tracking, compaction).

## 1. Document recall for Claude sessions

Rule (in `/workspace/CLAUDE.md`, "Document memory"): for document questions —
PRDs/specs (`UI-*`), architecture (`Network-Arch/`, `docs/`), non-plan
`Test-Flight-Improv` history (decisions, audits, reviews, matrices) — run

    CODEX_MEMORY_TELEMETRY=0 python3 codex-memory/memory.py query "<question>"

BEFORE raw-reading those documents.

Routing: code → graphify; plan status / supersession / refuted findings /
session memory → `project-memory/src/recall.py` (the gated 18/18 authority;
codex-memory deliberately does not ingest the Claude session-memory folder);
documents → codex-memory. Fallbacks: a miss or broad answer → read the named
document section directly; when EXECUTING a named plan/spec, read the
document itself — recall never substitutes for the primary document.

Telemetry stays OFF for Claude queries on purpose: `state/usage.jsonl` and
the hook ledgers feed Codex's OFF/SHADOW/ACTIVE cohorts, and unlabeled
Claude traffic would contaminate them. Adoption is measured CLAUDE-side
instead (added 2026-08-25 at the user's request), in the grep gate's own
ledger (`graphify-out/gate_stats.jsonl`):

- numerator — `doc_query` (PreToolUse) and `doc_query_read` with actual
  output tokens (PostToolUse) for every `codex-memory/memory.py query`;
- denominator — `doc_raw_read` with actual tokens for Bash read tools
  (cat/sed/head/tail/awk/less/more/bat/nl; `sed -i` excluded as an edit)
  over corpus documents, plus `doc: true` on Read-tool `source_read`
  records.

View it with `python3 .claude/hooks/graphify_savings.py` ("document memory
adoption" block; the statusline shows `docmem N` for the current session).
These events earn ZERO savings credit, per §3 — a substitution claim still
needs the matched A/B.

The Claude grep gate (`.claude/hooks/graphify_grep_gate.py`) appends a
routing line pointing at this command whenever a denied or GRAPH_OK-bypassed
raw search targets the document corpus (ledger field `doc_sweep` on
`grep_denied` / `grep_tool_denied` events).

## 2. Affected-closure gate (enforced)

`.claude/hooks/affected_closure_gate.py` denies `run_test_gates.sh` /
`run_host_test_gates.sh` lane launches while the session has edited
app-owned code (`lib/ test/ integration_test/ go-mknoon/ go-relay-server/`,
`.dart`/`.go`) without a `tdd_context.py affected` pass covering those
files. `--list`/`--dry-run` stay free. Ported from
`graphify-arch/codex_graphify_reminder.py`'s affected-closure gate.

Controls: one-shot bypass `AFFECTED_OK=1` on the lane command (logged) ·
shadow mode `GRAPHIFY_AFFECTED_ENFORCE=0` · `GRAPHIFY_LOCAL_DEV_BYPASS=1`
telemetry-only · `GRAPHIFY_STATS=0` disables the ledger.
State/ledger: `graphify-arch/graphify-out/cache/claude-affected-gate/`
(gitignored). Tests: `.claude/hooks/tests/test_affected_closure_gate.py`.
Registered in `.claude/settings.json`; hook changes load at the NEXT
session start.

Why enforce instead of advise: grep-gate ledger 2026-07-25→08-17 — advisory
(bypass) mode doubled raw-grep volume (~2,600/week) with zero query uptake.

Accepted gaps (all fail-open): bash-driven edits (`sed -i`), lanes launched
inside host-run wrapper scripts, `|`/newline command segments, and the graph
blind spot — path-string census tests have no import edge, so the lane stays
the final word even after a clean affected pass.

## 3. Measurement protocol (the discipline, not the tool)

Distilled from `task_run.py` / README; applies to ANY new Claude-side
enforcement or recall behavior before it is widened:

- **Arms**: OFF (hook removed/disabled), SHADOW (log, never deny or inject),
  ACTIVE. Apply one arm per fresh session, never mid-session.
- **Negative control**: OFF vs SHADOW must agree within 5% absolute median
  input and total tokens on at least 3 comparable pairs, or ACTIVE savings
  are confounded (the hook's own presence changed behavior).
- **Savings claims**: at least 3 matched replicates (same task, starting
  HEAD, model, gate set), at least 20% median token reduction. Injected or
  advisory context earns ZERO savings credit; only a denied raw intent
  counts, minus the delivered recall context and any confirmed
  fallback-read overhead. A later bypass or whole read removes that credit.
- **Quality claims**: read counts, recall adoption, and agent-written tests
  are not quality proof. A quality claim needs predeclared required plus
  held-out gates and repeated blinded review showing fewer critical/major
  defects. An observed declared-gate failure permanently fails that run,
  even if a retry later passes.
- Compare within one policy-version cohort only.

## Baselines at adoption (2026-08-25)

- codex-memory benchmark: 15/15 correct, ~146 avg tokens/question, warm p95
  21.9 ms; corpus 584 files / 7,126 entities (`memory.py status`).
- The same 12 plan questions on project-memory recall: ~680 tokens/question
  (codex-memory is ~78% smaller on them).
- 7-day Codex telemetry at adoption: 143 queries (140 hit, 220.7 avg
  tokens) while raw document reads requested ~1.35M tokens in the same
  window — the substitution target.
- Claude-side precedent: enforcement changes behavior here, advisory does
  not (grep-gate ledger, above).
