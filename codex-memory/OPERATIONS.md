# Codex memory operations

This reference contains the detailed memory operating rules linked from root `AGENTS.md`. Consult it for memory maintenance, hook debugging, adoption measurements, or token-and-quality experiments. The everyday workflow stays in `AGENTS.md`.

For implementation details, commands, and current defaults, see [README.md](README.md), particularly “Task-level OFF/SHADOW/ACTIVE benchmark”, “Native context compaction (checkpoint rollover disabled)”, and “Measurement and privacy”. Local enablement can differ from tracked defaults; inspect local configuration and current evidence before describing automatic behavior as active.

## Retained operating rules

This project has a Codex-owned non-code knowledge graph at `codex-memory/`. Codex memory records what was specified, decided, refuted, deferred, or superseded; current source establishes code behavior and relationships.

- Before a broad multi-file search over plans, specs, PRDs, architecture documents, reviews, or project history, run `python3 codex-memory/memory.py query "<one focused document question>"`. Use the returned provenance to choose the small set of documents to inspect.
- A direct complete read of one explicitly named plan or spec is allowed and often necessary. In the root task, prefix its first document-only read with `CODEX_MEMORY_PRIMARY_READ=1`; this resets the shared hashed primary identity for resumed threads and prevents each subagent from gaining a separate full-read exception. Size a long document first, then read it in one non-overlapping pass: raise the outer `functions.exec` `max_output_tokens` pragma when safely sufficient, or use consecutive bounded ranges. A clean primary read that cannot fit the visible output cap is denied before execution with an exact next-range and minimum-cap retry; use `CODEX_MEMORY_PRIMARY_OUTPUT_BYPASS=1` only as a one-call acceptance of clipping risk. Never restart at line 1 merely because an oversized result was clipped. For implementation, extract only code paths/symbols/tests/gates and inspect those code anchors.
- `query` checks the configured corpus and auto-refreshes the Codex database when its source set, config, size, or mtime changes. Use `python3 codex-memory/memory.py status --verify-content` for a full hash audit and `python3 codex-memory/memory.py refresh --force` for an explicit rebuild.
- Change tracked defaults in `codex-memory/config.json`; put machine/session-specific overrides in ignored `codex-memory/config.local.json`. Never add source-code globs to this corpus.
- Keep plan/spec reads and searches in document-only tool cells, with one configured document per broad-read cell so its retrieval opportunity is attributable and independently recoverable. When spawning a document/history worker, pass a separately labeled `document memory context:` containing the focused question, returned provenance, and open document question; keep document context separate from code-navigation evidence.
- Measure real adoption with `python3 codex-memory/memory.py stats --session current`. Evaluate eligible/attempted/served/action counts, constraint reasons, focused grounded recalls, targeted fallbacks, first-pass coverage, answer coverage, and policy-version mix rather than maximizing recall calls. Treat savings separately: the estimate credits unique denied raw intents and subtracts delivered context plus confirmed model-visible fallback reads; query-production tokens are operational telemetry and are not double-subtracted.
- When enabled locally, the Codex-memory `PreToolUse` hook automatically runs bounded recall before an ungrounded broad corpus sweep, at the configured cadence, and before a broad/full or cumulatively broad read of a configured secondary document. Secondary mode defaults to non-blocking `inject`; `shadow` measures without injecting, while `enforce` denies only an exact or focused, non-truncated same-document hit and keeps targeted windows open. Separately, the primary output-safety gate denies only a clean cap-impossible primary read and never credits that denial as retrieval savings. The matching `PostToolUse` hook is the only leg that credits a conservatively validated successful, non-truncated document response or clears fallback debt. Misses, broad/truncated results, errors, provenance mismatches, mixed cells, changed files, and uncertain classifications fail open. Use `CODEX_MEMORY_PRIMARY_OUTPUT_BYPASS=1` for one output-risky primary read, `CODEX_MEMORY_SECONDARY_BYPASS=1` for one secondary read, `CODEX_MEMORY_REPEAT_GUARD_BYPASS=1` for one covered reread, or the corresponding mode/guard environment setting to opt out. Telemetry stores hashed identities and counters, never prompts, commands, questions, or filenames; this privacy statement does not describe the local SQLite corpus or private hook cache, which necessarily contain document text/provenance.
- For an incremental automatic-hook token-and-quality comparison, use `python3 codex-memory/task_run.py` as documented in `codex-memory/README.md`. Keep the code-navigation and manual memory policies constant across OFF/SHADOW/ACTIVE. Apply the chosen profile before launching each fresh Codex session; make the measured request its first task; use the same arm-agnostic `start` command with predeclared required and held-out gates; after `task_complete`, execute or record those gates and finish from a shell or another session. Keep the full ordered request/steering stream, starting tree, model, effort, CLI, device matrix, tool/config fingerprints, and gate set identical, randomize variant order manually, and collect at least three matched replicates per comparison. Active savings require the OFF-to-SHADOW negative control to stay within 5% median input and total tokens. Diagnostic or reused-session runs are permanently ineligible for savings claims.
- Treat only exact root-plus-descendant rollout counters as exact task tokens; cached input and reasoning output are subsets, while graph and raw-output estimates are diagnostic attribution. Failed, incomplete, quality-regressed, policy-changed, or mismatched runs never earn savings. A declared-gate failure is permanent for that run; a repaired pass belongs in a fresh replicate. Shadow records non-enforcing opportunity/advisory telemetry while suppressing context and denials; it is not an exact replay of every active state transition. Active defaults to non-blocking memory injection, so adoption can be nonzero while direct memory deny savings remain zero. The private `0600` task ledger stores aggregates and hashes, never prompts, commands, paths, model output, or raw Codex identifiers.

## Curation and retention

- Keep standing instructions short and durable. Store task-specific procedures with their canonical subsystem; link to them with an explicit condition for reading them.
- A durable memory record should name its status, source/revision or evidence, and what supersedes it when applicable. Current source establishes implementation behavior. Do not treat old plans as proof of current behavior.
- Do not persist transient device IDs, an old working-tree state, or an old published baseline as current facts. Discover these when the task requires them.
- Distinguish reproducible indexes and temporary build files from source records, session history, benchmark ledgers/keys, hook state, and diagnostic evidence. Age alone does not establish that a file is disposable.
- Before cleanup, identify exact paths, references, active processes/locks, and how regeneration or recovery works. Keep files with unknown consumers out of automatic cleanup.
- Evaluate changes to corpus selection or retrieval against the existing benchmark and quality gates. A smaller file or a successful recall alone does not prove lower task tokens or preserved answer quality.

## Cleanup procedure

1. Inventory exact candidate paths and both logical and allocated sizes without
   following symlinks. Classify each as a reproducible index, disposable scratch,
   installed software, curated data, session history, or evidence. Use a dry-run
   manifest in ignored local artifacts; do not infer disposability from `cache`
   in a directory name.
2. Check references, current installation targets, open handles, and running
   builders immediately before removal. Compare hashes before removing duplicate
   archive files, and preserve distinct curated labels. Do not delete lock files
   based on age. Keep uncertain candidates out of the removal manifest.
3. Remove only the approved exact paths. Preserve source/configuration, current
   useful indexes, active state, telemetry, benchmark ledgers and their keys,
   plugin/skill installations, generated user outputs, and conversation history.
   History retention needs a deliberate policy; no default expiry is assumed.
4. Record actual removals and skipped candidates in ignored artifacts. Recheck
   retained installation targets and index health. Index/cache removal may make
   the next query or extraction slower; it does not shorten standing context.

| Material | Recovery / retention rule |
| --- | --- |
| `codex-memory/state/graph.db` and its manifest | `python3 codex-memory/memory.py refresh --force` rebuilds the index; follow with `status --verify-content` and `benchmark`. Retain a healthy useful index during routine cleanup. |
| Abandoned `codex-memory/state/.graph.*` temporary files | Remove only exact files verified unused by a builder; keep `refresh.lock` and the current index. |
| Python `__pycache__` and Graphify AST/stat caches | Regenerated by the next Python invocation or normal graph extraction. Preserve enclosing directories that also contain source links, labels, events, or gate ledgers. |
| Memory/Graphify telemetry, benchmark ledgers and private keys | Historical evidence, not reproducible cache. Deleting keys can invalidate unfinished runs. |
| `~/.codex/plugins/cache` and skill source directories | Installed software; use supported uninstall/update operations if intentionally changing availability. Symlinks are not duplicate content. |
| Codex session/history/state databases | Preserve unless a separate explicit retention decision authorizes their alteration. Never manually remove live SQLite WAL/SHM files. |
| Free pages in the Codex logs database | Reclaim through SQLite maintenance with a consistent backup and controlled writer activity; do not delete remaining records or the database file as cache cleanup. |
