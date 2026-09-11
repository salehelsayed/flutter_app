# Graphify effectiveness: graph query vs ripgrep

Date: 2026-09-11. Branch `feat/ipv6-happy-eyeballs`, HEAD `e7e11bab2`.
Arch graph built 15:56Z: 91,456 nodes, 134,307 edges, `graph.json` 96 MB.
Web version of this report: https://claude.ai/code/artifact/756da146-8479-439c-b77e-758832d71bf8

## Verdict

The graph is a clear win only for questions with no known symbol, and it
answered 2 of 4 of those. For every question where a symbol or filename is
already known, one targeted `rg` is 5–15× cheaper, finds every user (recall
1.0 vs 0.10–0.75), and reads the working tree instead of HEAD.

The savings report's "~3.7M tokens saved" is not a measurement. It credits
every query with replacing a 10k-token sweep. Measured, the graph replaced a
24–200-token grep in 14 of 19 cases.

## At a glance

| Question kind | Cases | Graph tokens | Graph quality | Raw tokens | Raw quality | Cheaper | More complete |
|---|---:|---:|---|---:|---|---|---|
| Where is X defined | 6 | 163–432 | 6/6 found, 2/6 line numbers stale | 24–36 | 6/6, exact lines | raw | raw |
| Who uses X | 5 | 361–608 | recall 0.10–0.75 (avg 0.48) | 45–197 | recall 1.0 | raw | raw |
| Which tests cover file F | 3 | 487–520 | recall 0.25 / 0.11 / 1.0 | 16–158 | recall 1.0 | raw | raw |
| Natural language, no symbol | 4 | 607–742 | 2/4 hit | 23.6k–57.2k | 3/4 hit | graph, 35–85× | raw |
| Tests affected by my diff | 1 | 463 @600, 1,894 @3000 | 0/63 @600, 63/63 @3000 | 898 | 66/66 | raw | raw |

"Raw tokens" for the first three kinds is a single targeted ripgrep. For
natural-language questions it is three keyword greps plus reading the three
best-ranked files, which is what an agent does when it has no symbol to
search for. Graph queries took 1.0–3.5 s each (loading the 96 MB graph).
ripgrep took about 0.05 s.

## Setup

**Ground truth.** Exhaustive ripgrep over the working tree, computed before
any graph query and never from the graph.

- Definition: `rg -n "class X" lib`
- Users: `rg -l -w X lib test integration_test` minus the defining file
- Tests for a file: `rg -l <basename> test integration_test`
- Natural-language targets: the file that owns the concept, checked by grep

**Graph arm.** The exact commands CLAUDE.md prescribes.

- Define and natural language: `tdd_context.py query "…" --profile general --budget 600`
- Who uses: `--profile review --budget 800`
- Tests for file: `--profile tdd --budget 700`
- Diff: `tdd_context.py affected <files> --budget 600`
- On a `broad` answer: one refinement with the anchor the output suggested,
  then the `--level component --budget 500` fallback, as the rules say.

**Raw arm.** Two protocols.

- Targeted: the one grep an agent runs when it knows the symbol.
- Grep-and-read: grep across `lib test integration_test`, then a `Read` of
  the defining file (first 2000 lines, line-number prefix included).
- Natural language: `rg -il <keyword> lib` per content word, rank files by
  distinct keyword hits, read the top 3.

**Tokens.** Characters ÷ 4, the same approximation the repo ledger uses (no
tokenizer is installed in the container). Tool output capped at 30,000
characters to match the harness truncation. A grep that overflows costs
~7.5k tokens and loses data. None of the targeted greps overflowed.

**Quality.** Define: target file present, and line number equal to the
working tree. Users and tests: recall = found ÷ true set, plus a count of
listed files that are not users. Natural language: target file appears in
the output (graph) or in the three files read (raw).

**Environment.** Container Linux, Python 3, ripgrep. Graph built
2026-09-11 15:56Z from HEAD. The working tree carried 15 uncommitted
modified files (the branch's TURN/ICE work), which is the normal state
during a session.

**Script.** `graphify-arch/effectiveness_bench.py` writes
`effectiveness_bench_results.json`. Two follow-up checks were run by hand:
larger budgets, and the import-edge test under "Defects".

## Results

### Where is X defined

Six symbols from the current diff and the call feature. The graph found all
six. Two line numbers were stale: the graph matches HEAD, and the working
tree had shifted those files. The freshness header named only
`p2p_bridge_client.dart` as stale.

| Symbol | Graph tokens (@600) | secs | Line graph / tree | Targeted grep tokens | Grep + read file tokens |
|---|---:|---:|---|---:|---:|
| `BridgeCallIceServerProvider` | 173 | 2.47 | 15 / 17 (stale) | 28 | 1,782 |
| `CallAudioNegotiationPreparer` | 171 | 1.70 | 17 / 18 (stale) | 27 | 1,701 |
| `CallNegotiationEffectExecutor` | 187 | 1.68 | 69 / 69 | 36 | 13,134 |
| `FlutterWebRtcCallEngine` | 432 | 1.20 | 975 / 975 | 26 | 20,708 |
| `CallRingbackCoordinator` | 164 | 0.98 | 42 / 42 | 25 | 1,316 |
| `callP2PTurnCredentialsV1` | 163 | 1.04 | 186 / 186 | 24 | 19,632 |

The graph costs about 7× a targeted grep and about 8–100× less than reading
the file. Its only value here is the line number, which lets you read a
narrow range instead of the whole file. A targeted grep gives the same line
number for less.

### Who uses X

Same symbols, review profile (the profile that lists caller candidates).
Ground truth excludes the defining file.

| Symbol | True users | Graph tokens (@800) | Found | Recall | Non-users listed | Truncated | `rg -l -w` tokens | Recall |
|---|---:|---:|---:|---:|---:|---|---:|---:|
| `BridgeCallIceServerProvider` | 6 | 559 | 4 | 0.67 | 1 | yes | 116 | 1.0 |
| `CallAudioNegotiationPreparer` | 4 | 564 | 3 | 0.75 | 2 | no | 82 | 1.0 |
| `CallNegotiationEffectExecutor` | 11 | 608 | 4 | 0.36 | 2 | yes | 197 | 1.0 |
| `FlutterWebRtcCallEngine` | 10 | 591 | 1 | 0.10 | 11 | yes | 182 | 1.0 |
| `CallRingbackCoordinator` | 2 | 361 | 1 | 0.50 | 1 | no | 45 | 1.0 |

Raising the budget does not fix it. At `--budget 3000` (no truncation)
`CallNegotiationEffectExecutor` reached 6/11 for 780 tokens and
`FlutterWebRtcCallEngine` 5/10 for 1,111 tokens. The files still missing are
listed under "Defects".

### Which tests cover file F

| File | True tests | Graph tokens (@700) | secs | Recall | Truncated | `rg -l basename` tokens | Recall |
|---|---:|---:|---:|---:|---|---:|---:|
| `bridge_call_ice_server_provider.dart` | 4 | 520 | 1.10 | 0.25 | yes | 71 | 1.0 |
| `call_negotiation_effect_executor.dart` | 9 | 509 | 1.06 | 0.11 | yes | 158 | 1.0 |
| `call_ringback_coordinator.dart` | 1 | 487 | 3.54 | 1.0 | yes | 16 | 1.0 |

Here the budget is the problem: `call_negotiation_effect_executor.dart` at
`--budget 2000` reached 9/9 for 1,516 tokens (still truncated). The grep
reached 9/9 for 158.

### Natural language, no symbol known

The graph's intended case. Query, then one refinement with the anchor it
suggested, as the rules require. Raw is three keyword greps and a read of
the three best-ranked files.

| Question | Target file | Graph tokens (query + refine) | Confidence | Graph hit | Raw grep | Raw read | Raw total | Raw hit |
|---|---|---:|---|---|---:|---:|---:|---|
| how is the caller-side ringback tone started and stopped | `call_ringback_coordinator.dart` | 663 | broad | yes, after refine | 6,903 | 50,308 | 57,211 | yes |
| where does the app fetch TURN credentials from the Go bridge | `p2p_bridge_client.dart` | 607 | broad | yes | 11,417 | 40,299 | 51,716 | yes |
| android killed app call decline reply headless | `headless_call_decline_reply.dart` | 742 | broad | no | 2,624 | 44,480 | 47,104 | no |
| terminal call rows rendered in the 1:1 chat history | `call_history_projector.dart` | 678 | broad | no | 13,740 | 9,859 | 23,599 | yes |

On the two misses the graph anchored on generic words (`decline`, `reply`,
`terminal`, `rendered`) in unrelated files. The prescribed
`--level component --budget 500` fallback cost 242 and 262 more tokens and
rescued neither: it returned hub-named communities such as
`send_message_result.dart` and `group_exit_terminal_diagnostics.dart`. The
raw protocol's hit means the target was among the three files read; the
agent still has to read it.

### Tests affected by my diff

The current uncommitted change set: 6 files under `lib/` when the script
ran, 7 by the recount (another session added `call_state.dart` in between).
66 test files mention a changed basename; 63 of them import one.

| Arm | Tokens | Tests named | Note |
|---|---:|---:|---|
| `affected --budget 600` (the CLAUDE.md command) | 463 | 0 / 63 | Truncated inside the list of 23 lib importers before any test line. |
| `affected --budget 3000` | 1,894 | 63 / 63 | All importing tests. Cannot see the 3 path-string mentions (known blind spot). |
| 7 × `rg -l basename test integration_test` | 898 | 66 / 66 | Includes the 3 path-string mentions. |

## Defects found

### 1. Relative Dart imports are not graph edges

`lib/app/bootstrap/production_call_signaling_graph.dart:59` imports
`flutter_webrtc_call_engine.dart` with a relative path (`'../../features/…'`)
at HEAD. `affected flutter_webrtc_call_engine.dart --budget 3000` never lists
it. The same holds for `call_ringback_channel.dart:5` and
`production_call_signaling_graph.dart:60`, both relative importers of
`call_ringback_coordinator.dart`; `affected` lists only the test, which uses
a `package:` import. 298 files under `lib/` use relative imports (746 use
`package:`). Every lib→lib dependent reached through a relative import is
invisible to "who uses" and to `affected`.

A second, smaller gap: for `FlutterWebRtcCallEngine`, `affected` does list
`call_engine_event_delivery_test.dart` and `call_remote_ice_drain_test.dart`
as importers, but the review-profile query omits them from its caller list
even without truncation. The graph has those edges; the query renderer
drops them.

Files missed at budget 3000 (no truncation):

`CallNegotiationEffectExecutor` (5 of 11 users):

```
integration_test/support/android_foreground_webrtc_audio_probe.dart
lib/features/call/application/call_scoped_media_bundle_owner.dart
test/core/bootstrap/call_signaling_composition_test.dart
test/features/call/integration/call_engine_event_delivery_test.dart
test/integration/android_foreground_webrtc_audio_campaign_test.dart
```

`FlutterWebRtcCallEngine` (5 of 10 users):

```
integration_test/audio_peer_connection_proof_test.dart
integration_test/support/android_foreground_webrtc_audio_canonical_stack.dart
lib/app/bootstrap/production_call_signaling_graph.dart
test/features/call/integration/call_engine_event_delivery_test.dart
test/features/call/integration/call_remote_ice_drain_test.dart
```

### 2. `affected --budget 600` names no tests on a multi-file diff

Output lists lib importers first, then tests. With 6 changed files the lib
list alone exceeds 600 tokens, so the documented workflow ("run the affected
tests it names first") has nothing to run. The `affected_closure_gate.py`
hook accepts this run as a valid affected pass and unblocks the lane.

### 3. The freshness header under-reports

The header said `freshness=stale:lib/core/bridge/p2p_bridge_client.dart`.
At least two other modified files had shifted line numbers
(`bridge_call_ice_server_provider.dart` 15→17,
`call_audio_negotiation_preparer.dart` 17→18) and were not named.

## What the existing telemetry says

Repo counters at the time of the test:

- `python3 .claude/hooks/graphify_savings.py`: 193.5k tokens actually
  consumed across 396 graph reads (measured). "~3.7M saved" (estimate:
  390 queries × a 10k-token assumed sweep). 182 greps redirected,
  7,618 `GRAPH_OK=1` bypasses.
- `python3 graphify-arch/tdd_context.py stats --last 30`: average 444 output
  tokens, 63% of outputs truncated, 100% of queries anchored.

The measured 193.5k is real. The 3.7M is the 10k constant multiplied out.
This test puts the typical replaced cost at 24–200 tokens when a symbol is
known and 23k–57k when it is not.

## Recommendations

1. **Stop gating exact-symbol searches.** `rg -n "class X" lib` and
   `rg -l -w X lib test integration_test` beat the graph on cost, recall,
   freshness and time. Keep the gate for keyword and natural-language
   discovery, where the graph is 35–85× cheaper.
2. **Resolve relative imports in the Dart extractor patch**
   (`graphify-arch/patches/apply_dart_extractor_patch.py`). Until then,
   "who uses X" and `affected` results are not safe to act on alone.
3. **Make `affected` list tests before lib importers**, or change the
   documented budget to 3000. At 600 the command named zero tests on a real
   diff, and the closure gate accepted it.
4. **Retune or drop the 10k-per-query savings constant** in
   `graphify_savings.py` (`BASELINE_SWEEP_TOKENS`). It is the entire gap
   between the measured 193.5k and the reported 3.7M.

## Graphify machinery in this repo

Everything below exists today. Paths are repo-relative.

### The two graphs

| Graph | Location | Scope | Size now |
|---|---|---|---|
| Architecture (default) | `graphify-arch/graphify-out/graph.json` | app-owned code via `.graphify-arch-src/` symlinks (`lib`, `go-mknoon`, `go-relay-server`, `integration_test`, `test`, `scripts`, `ios`) filtered by `.graphify-arch-src/.graphifyignore` (no docs, images, Go third_party/cache/bin/testdata, build output, generated l10n) | 91,456 nodes, 134,307 edges, 96 MB |
| Full | `graphify-out/graph.json` | every detected code file including Pods, native iOS/Android, Go vendor, generated l10n | 125,920 nodes, 213,557 edges at the last comparison (`GRAPH_SELECTION.md`, 2026-07-28) |

`cwd` picks which graph a bare `graphify` command hits. The `graphify` CLI
itself runs only on the Mac host (memory: graphify CLI is host-only); the
container runs the Python helpers against the JSON.

### Claude Code hooks (`.claude/settings.json`)

| Hook file | Events | What it does |
|---|---|---|
| `.claude/hooks/graphify_grep_gate.py` | PreToolUse `Bash`, PreToolUse `Read\|Glob\|Grep`, PostToolUse `Bash` | Four Bash gates in order: (1) deny raw dumps of any `graphify-out/**/graph.json` via cat/less/jq/head/tail/awk/sed/git show; (2) deny `graphify query` without `--budget`; (3) `GRAPH_OK=1` bypass, scoped to the grep gate only; (4) deny `grep`/`rg`/`ack`/`ag`/`fd`/`find`/`git grep` at command position while a graph exists (pipe filters stay allowed). The dedicated `Grep` tool is always denied. `Read` of `graph.json` is denied, `Read` of `GRAPH_REPORT.md` gets a nudge, and repeated separate-round-trip reads of one file escalate nudge → deny. PostToolUse logs every executed query/path/explain as a `graph_read` event with actual output tokens (len/4). Also emits the codex-memory document-sweep nudge and logs `doc_query` / `doc_raw_read`. Ledger: `graphify-out/gate_stats.jsonl`. Enforcing; `GRAPHIFY_LOCAL_DEV_BYPASS=1` would make it telemetry-only (deliberately not set). |
| `.claude/hooks/affected_closure_gate.py` | PostToolUse `Edit\|Write\|MultiEdit\|NotebookEdit`, PreToolUse `Bash`, PostToolUse `Bash` | Records session-edited app code paths (`lib/ test/ integration_test/ go-mknoon/ go-relay-server/`, `.dart`/`.go`). Denies `scripts/run_test_gates.sh` and `scripts/run_host_test_gates.sh` lane launches while any recorded path has no `tdd_context.py affected` pass (`--list`/`--dry-run` free). A PostToolUse `affected` run clears the paths it names; success is assumed unless the tool result carries an explicit failure marker. Bypass: `AFFECTED_OK=1` prefix (logged). Shadow mode: `GRAPHIFY_AFFECTED_ENFORCE=0`. State and ledger under `graphify-arch/graphify-out/cache/claude-affected-gate/`. Enforcing since 2026-08-25. |
| `.claude/hooks/arch_graph_auto_refresh.sh` | Stop | At every turn end (~100 ms): skip if a refresh lock is held, no graph exists, the graph is younger than 10 min, or no app-owned code file is newer than the graph. Otherwise write the first newer path to `graphify-arch/.needs_incremental_refresh`. `ARCH_REFRESH_EAGER=1` spawns a detached `refresh_arch_graph.sh --incremental` instead. `ARCH_REFRESH_DRY_RUN=1` prints the decision. |
| statusLine command | statusline | Prints `graphify N reads · M redirected` from `graphify_savings.py --statusline`, the cumulative token meter from `session_tokens.py`, and `project-memory/src/recall_statusline.py`. |

Hook tests: `.claude/hooks/tests/test_graphify_token_discipline.py`,
`test_affected_closure_gate.py`, `test_doc_memory_measurement.py`,
`test_session_tokens.py`.

### Codex hooks (`.codex/hooks.json`)

| Hook file | Events | What it does |
|---|---|---|
| `graphify-arch/codex_graphify_reminder.py` | PreToolUse `.*` (3 s timeout, 300-char context) | Denies an ungrounded code browse, a plan/spec-to-code transition, an over-budget browse batch (default 8), a cadence breach (default ceiling 10), or a code-exploration spawn without a compact context packet (30-min TTL). An anchored compact query, an exact raw-search route, or a measured native fallback unlocks the branch; broad questions do not. Carries the Codex-side affected-closure gate that the Claude hook was ported from. Fail-open on any error. Telemetry is anonymous counters plus truncated SHA-256 ids in `graphify-arch/graphify-out/cache/codex-reminder/events.jsonl`. |
| `codex-memory/codex_memory_reminder.py` | Pre/PostToolUse on bash/read/grep/glob/search | Document-memory recall reminder (not graphify; listed because it shares the hook file). |

### Skills, agents, workflows

| Item | Path | Role |
|---|---|---|
| `graphify` skill | `.claude/skills/graphify/SKILL.md` + `references/` | The only skill the project allows to be selected implicitly. Documents the compact fast path (`tdd_context.py query` profiles, `--level component`, `affected`, `stats`), the refresh commands, and the native `graphify query/path/explain` fallback. |
| `graphify-explorer` agent | `.claude/agents/graphify-explorer.md` | Graph-first exploration subagent: query → narrow with `graphify path`/`explain` → verify hot spots in source → answer with `file:line`. CLAUDE.md names it as the required agent type for fan-outs over app-owned code. |
| Scout-then-fan-out template | `.claude/workflows/_template-scout-then-fanout.mjs` | One budgeted `graphify-explorer` scout; its digest is embedded verbatim in every worker prompt so workers never re-query (the 199 audit measured ~37.7k tokens per agent on fan-outs that re-derived the same context). |
| Multistage pipeline template | `.claude/workflows/_template-pipeline-multistage.mjs` | References graphify for the review stage. |
| Saved workflows | `.claude/workflows/one-to-one-media-unavailable-debug.js` (4 `graphify-explorer` uses), `.claude/workflows/vc-tdd-review.js` (1) | Skill-triggered workflows that spawn graphify-explorer agents. |
| Ad-hoc workflow scripts | `.claude/wf-harness-audit.mjs`, `.claude/wf-124-phase8-gaps.mjs`, `.claude/wf-124-phase8-device.mjs` | Reference graphify in their agent prompts. |

### Build and maintenance scripts

| Script | Purpose |
|---|---|
| `graphify-arch/refresh_arch_graph.sh [--incremental\|--full\|--rebuild]` | Re-applies the Dart extractor patch, runs `refresh_graph.py`, rebuilds the TDD overlay (`tdd_context.py build`), clears `.needs_incremental_refresh`. `--full`/`--rebuild` also run `graphify cluster-only --no-label` (keeps curated labels), `graphify export html`, and `compare_graphs.py` → `GRAPH_SELECTION.md`. Never runs `graphify label` (no LLM backend on the host). |
| `graphify-arch/refresh_graph.py` | Merge-safe incremental refresh using graphify's public detect/extract/build/export functions, working around the 0.8.33 `--no-cluster` overwrite bug. Sets `GRAPHIFY_SYMLINK_SCOPE_ROOT` so the symlink corpus is detected. |
| `graphify-arch/patches/apply_dart_extractor_patch.py` | Required local patch: Dart line numbers, nested/multi-line function capture, no fuzzy-merging of differently named symbols, `detect()` symlink-scope fix. Must be re-run after `uv tool upgrade graphifyy`, with both AST caches cleared. |
| `graphify-arch/tdd_context.py` | The compact helper. Subcommands: `build` (overlay), `query`, `native` (measured full-graph fallback), `affected`, `stats`, `session-stats`, `checkpoint`, `workflow-benchmark`, `benchmark`. Overlay: `graphify-arch/tdd-overlay.json` (5.7 MB). Query telemetry: `graphify-out/context_query_stats.jsonl`. |
| `graphify-arch/compare_graphs.py` | Full-vs-arch metrics table in `GRAPH_SELECTION.md` / `comparison.json`. |
| `graphify-arch/query-benchmark.json` | Deterministic precision cases for `tdd_context.py benchmark` (expected route, confidence, source and proof paths, required markers). |
| `graphify-arch/effectiveness_bench.py` | This report's head-to-head script. |
| `.claude/hooks/graphify_savings.py` | Ledger aggregator: human report, `--json`, `--statusline`. Holds `BASELINE_SWEEP_TOKENS = 10000`. |
| `docker-ws/graphify_*.sh` (11 scripts) | Host-side wrappers run through the Mac bridge: `full_update`, `full_update_preview`, `full_fixpoint`, `full_regen_report`, `apply_patch`, `patch_smoketest`, `apply_labels`, `label_arch`, `kill_update`, `upgrade_tool`, `run_tooling_tests`. |
| `graphify-arch/tests/` | `test_graphify_arch_tooling.py`, `test_graphify_reminder_closure.py`, `test_observe_only_hooks.py`, `test_tdd_context_metrics.py`. |

### Ledgers and state

| File | Written by |
|---|---|
| `graphify-out/gate_stats.jsonl` | `graphify_grep_gate.py` (every gate decision, `graph_read`, `doc_query`, `doc_raw_read`) |
| `graphify-out/context_query_stats.jsonl` | `tdd_context.py` (per-query output size, truncation, route, confidence, hashed session) |
| `graphify-arch/graphify-out/cache/claude-affected-gate/{session-*.json,ledger.jsonl}` | `affected_closure_gate.py` |
| `graphify-arch/graphify-out/cache/codex-reminder/events.jsonl` | `codex_graphify_reminder.py` |
| `graphify-arch/.needs_incremental_refresh` | `arch_graph_auto_refresh.sh` (Stop hook) |
| `graphify-arch/graphify-out/.graphify_labels.json` + `.sig` | curated community labels; preserved by `cluster-only --no-label` |

### Related documents

- `graphify-arch/GRAPH_SELECTION.md`: which graph to use, metrics, method.
- `Test-Flight-Improv/199-graphify-token-discipline-tdd-plan.md`: the plan
  that introduced the gates and ledger.
- `codex-memory/CLAUDE-ADOPTION.md`: adoption rationale and the measurement
  protocol behind enforcing (not advising) the gates.

### How the findings map onto the machinery

- The grep gate (gate 4) denies exactly the `rg -n "class X"` and
  `rg -l -w X` commands this test shows are cheaper and more complete than
  the query it redirects to.
- The affected-closure gate accepts an `affected --budget 600` run that
  named zero tests as a valid pass.
- The relative-import gap lives in the extractor patch, and it degrades both
  `affected` (the closure gate's whole premise) and the review profile.
- The statusline and the savings report show a number built from the 10k
  constant, not from measured replacement cost.

## Reproduce

```bash
# full run, ~45 s; the raw greps run with GRAPH_OK=1 because they are the census
python3 graphify-arch/effectiveness_bench.py graphify-arch/effectiveness_bench_results.json

# dependents at a budget that does not truncate
python3 graphify-arch/tdd_context.py query CallNegotiationEffectExecutor --profile review --budget 3000
python3 graphify-arch/tdd_context.py query FlutterWebRtcCallEngine --profile review --budget 3000

# affected at 3000, scored against tests that mention a changed basename
CH=$(git diff --name-only HEAD -- lib/ | grep '\.dart$')
python3 graphify-arch/tdd_context.py affected $CH --budget 3000

# is the missing edge a stale-graph effect or a missing edge? (HEAD has the import)
git show HEAD:lib/app/bootstrap/production_call_signaling_graph.dart | GRAPH_OK=1 rg -n flutter_webrtc_call_engine
python3 graphify-arch/tdd_context.py affected lib/features/call/infrastructure/flutter_webrtc_call_engine.dart --budget 3000 | grep -c production_call_signaling_graph   # 0

# relative vs package imports under lib/
GRAPH_OK=1 rg -l "^import '\.\.?/" lib | wc -l                  # 298
GRAPH_OK=1 rg -l "^import 'package:flutter_app/" lib | wc -l    # 746

# component-level fallback on the two natural-language misses
python3 graphify-arch/tdd_context.py query "android killed app call decline reply headless" --level component --budget 500
python3 graphify-arch/tdd_context.py query "terminal call rows rendered in the 1:1 chat history" --level component --budget 500
```
