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

## Reusable project records

- [Physical-iPhone XCUITest harness](physical-iphone-xcuitest-harness.md):
  canonical locations, physical execution recipe, safety invariants, Apple
  references, and the extension pattern for new permissions or device flows.

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

## Task-level OFF/SHADOW/ACTIVE benchmark

Use `task_run.py` to measure the incremental effect of the automatic Graphify
and Codex-memory hooks on exact Codex tokens while checking that implementation
quality does not regress. Manual graph-first behavior stays enabled and
identical in every cohort, so this benchmark does **not** measure graphs versus
no graphs. Apply one profile in the parent shell **before launching a fresh
Codex session**:

```sh
eval "$(python3 codex-memory/task_run.py profile --variant shadow)"
codex
```

Repeat with `off`, `shadow`, and `active`. The measured request must be the
first task in that fresh session. Inside it, after the request has created the
task boundary, predeclare at least one required gate and at least one held-out
gate. The command prints the private run hash:

```sh
python3 codex-memory/task_run.py start \
  --task-id notification-fix-v1 --replicate 1 \
  --required-gate focused-tests --held-out-gate independent-review \
  --review-rubric-id independent-review-v1 \
  --device-matrix android-usb-plus-emulator
```

Once that Codex turn has emitted `task_complete`, use the parent shell or a
different session—with the same profile environment still applied—to execute a
declared gate, or record a gate already run by an external harness, and then
finish the run:

```sh
python3 codex-memory/task_run.py gate --run <run> --gate-id focused-tests -- \
  flutter test test/path/to/focused_test.dart
python3 codex-memory/task_run.py record-gate --run <run> \
  --gate-id independent-review --status pass \
  --evidence-id independent-review-v1
python3 codex-memory/task_run.py finish --run <run> --acceptance pass \
  --critical-defects 0 --major-defects 0 --minor-defects 0 --repair-turns 0
python3 codex-memory/task_run.py report --run <run> --json
python3 codex-memory/task_run.py compare --task-id notification-fix-v1 --json
```

Use the same task, starting HEAD and worktree, model, reasoning effort, Codex
CLI, device matrix, graph/config fingerprints, and gate set. Collect at least
three matched replicate IDs for each comparison and randomize the variant order
manually. The start command intentionally omits the arm: it infers the validated
`CODEX_TASK_RUN_VARIANT` set by the profile, keeping the model-visible command
identical across cohorts. Normal starts reject reused sessions, missing held-out
evidence, and profile drift. `--diagnostic-only` permits exploratory measurement
but makes the run permanently ineligible for a savings claim. The tool validates
recorded comparability fields, including a keyed fingerprint of the full ordered
user-request stream (initial request plus any steering), but it does not launch
Codex, restore the tree, randomize runs, choose gates, judge defects, or run an
independent review. External gate and review evidence IDs are hashed in the
ledger and must refer to evidence that was actually produced. Any observed
declared-gate failure permanently fails that run even if a later retry passes;
use the retry diagnostically, then measure a fresh replicate so post-task repair
work cannot disappear from the comparison.

Exact token totals come from Codex rollout counters for the root turn and its
descendants. Cached input is a subset of input, and reasoning output is a subset
of output; neither is added to total again. Graphify, memory, raw-read, and
output-token estimates are attribution diagnostics only and never enter exact
token savings. Failed, incomplete, quality-regressed, policy-changed, or
otherwise mismatched runs cannot earn a savings verdict.

A `proven` comparison means only that this matched task set retained its
predeclared quality evidence, passed the OFF-to-SHADOW negative control (at
least three comparable pairs within 5% absolute median input and total tokens),
and met the 20% minimum median token threshold (the CLI accepts only stricter
overrides). A failed or insufficient negative control makes active savings
confounded or insufficient. A quality-improvement claim additionally requires
repeated blinded-review evidence with fewer critical or major defects; read
counts, recall adoption, and agent-written tests alone are not quality proof. An
individual `report` can only mark a run as a pair candidate; only task-level
`compare` can issue a savings verdict.

`shadow` leaves both hooks and telemetry running under non-enforcing settings,
recording retrieval opportunities and advisory outcomes rather than replaying
every active denial/state transition. Observe-only mode suppresses all
model-visible hook context and denial output. The same manual graph-first policy
still applies in every variant.
`active` fixes memory secondary retrieval to non-blocking `inject`; it can
therefore show real adoption while direct memory deny-based savings remain
zero. The append-only default ledger is
`codex-memory/state/task-runs.jsonl`, is forced to mode `0600`, and retains only
aggregates and short hashes—not prompts, commands, paths, model output, or raw
Codex identifiers. Its adjacent `0600` HMAC key protects request and workspace
fingerprints from low-entropy dictionary guessing; deleting or replacing that
key invalidates unfinished runs rather than silently re-keying them.

## Native context compaction (checkpoint rollover disabled)

This checkout now uses Codex's native automatic compaction. Project-local
token-budget reminders are disabled, and `.codex/hooks.json` does not register
`PreCompact`, `PostCompact`, compact `SessionStart`, or checkpoint `Stop` hooks.
Codex therefore does not run `context_rollover.py prepare`, build task-scope
manifests, require `READY`, call `functions.new_context`, or inject a private
checkpoint before continuing.

The standalone `context_rollover.py` implementation and its metrics remain in
the repository for historical analysis and explicit experiments. They are
dormant in ordinary project sessions. Already-open Codex sessions may retain
configuration loaded at startup; start a new session to guarantee native-only
behavior.

### Retained legacy implementation reference

The following describes the disabled checkpoint workflow for readers of its
tests and telemetry. It is not the active project configuration.

That reminder is the ordinary early path: `prepare` runs without
`--advisory-reset-on-not-ready`, a missing semantic anchor may be repaired at
most once, and only `READY` authorizes `functions.new_context`. If the context
instead reaches the hard exhausted fallback, its controller runs exactly one
`prepare --advisory-reset-on-not-ready`. It then calls
`functions.new_context` immediately when the command reports either `READY` or
the distinct `ADVISORY_RESET` status. No task edit, other tool call,
`final_answer`, `task_complete`, or return to the user may occur between that
prepare and the transition, so continuation never depends on a user nudge.
`ADVISORY_RESET` does not validate or make the checkpoint ready; it only arms a
fresh context whose SessionStart payload is advisory.

The root `Stop` hook enforces that boundary: while the advisory-reset arm is
pending, an attempted terminal response is rejected with an immediate
`functions.new_context` continuation directive. Automatic PreCompact consumes
the arm atomically when that transition begins, so ordinary completed turns and
the fresh post-reset context are not blocked.

A `NOT_READY` prepare also opens a privacy-safe liveness episode that survives
the next checkpoint generation. A READY retry or advisory arm is recorded as
remediation but does not close that episode; PreCompact/compaction or recovery
must actually begin. If the task terminates first, the Stop hook records
`terminal_after_not_ready`, and task-run quality remains failed even if a later
user turn rescues the conversation. This distinguishes a successful repair, a
pending hard fallback, a prevented terminal, an actual terminal failure, and a
later rescue without retaining prompt content or raw identifiers.

Automatic PreCompact never blocks or aborts the conversation. A fresh
`prepare` creates a short-lived, one-shot continuation arm; when that exact
checkpoint still validates, SessionStart injects the trusted bounded capsule.
The global Git HEAD and plan contents always remain strict. When the checkpoint
has a complete cumulative set of task-owned changed paths, only those declared
paths are fingerprinted for worktree drift; dirty paths written by another
session no longer invalidate it. A change to a declared task path still makes
the checkpoint stale. An unbound empty, incomplete, legacy, or otherwise
unusable task scope conservatively falls back to whole-worktree validation
rather than trusting a partial scope.

The token-budget guidance creates one opaque `--task-scope-id` for each root
task and reuses it automatically at every rollover. The raw ID is hashed before
persistence. The same ID merges a private cumulative path manifest across
checkpoint generations; a different ID isolates another task in the same
session. Codex never asks the user to choose or preserve this identifier.

The guidance builds the cumulative set automatically from exact `Execution
Progress` file cells, the private manifest, and the files Codex changed. It
appends one repeated, exact repo-relative `--changed-path` argument for each
created, modified, or deleted file, and both old and new endpoints of each
rename, then adds `--task-scope-complete` only after checking that the cumulative
set is complete. An intentionally empty complete scope is valid only when the
stable ID and completeness flag are both present with zero `--changed-path`
arguments. An empty scope without both remains on conservative whole-worktree
validation. Ignored runtime state, telemetry, rollover files, caches, and
incidental derived graph/build output are excluded unless an artifact is itself
a required task deliverable.
Fingerprint capture still fails closed with `repo_fingerprint_unavailable`,
while status, CLI output, telemetry, and advisory recovery also expose a fixed
privacy-safe `repo_fingerprint_failure` code and stage. Bounded byte counts may
be reported, but raw paths are never included in those diagnostics.
Plan-extracted paths augment the set but never authorize scoped validation by
themselves. This is agent bookkeeping, not something the user must assemble. If
the agent cannot establish the full set confidently, it must omit both a partial
override and the completeness flag, and accept the global fallback.

If a checkpoint is missing, stale, consumed, or fails repository validation,
the exhausted controller receives `ADVISORY_RESET` and explicitly invokes
`functions.new_context`; SessionStart injects only a recovery advisory plus a
verified plan locator (when available). That payload is orientation, never
trusted execution state. The fresh agent must reload and reconcile current
repository state, the active plan, current diff, and recent gates before acting;
it never trusts the invalid checkpoint's phase, evidence, changed paths, gate
results, blocker, or next action. Invalid user-requested `/compact` (the manual
hook trigger) remains fail-closed; `new_context` uses Codex's automatic trigger
and therefore takes the non-interrupting prepared-or-advisory path without a
user message.
Codex CLI 0.149 cannot inject SessionStart context into a compacted subagent, so
the guidance keeps workers bounded and asks them to hand their result to root;
an unavoidable automatic worker compaction is allowed rather than aborting it.

The legacy commands remain useful for inspection or explicit experiments; the
active native-compaction configuration does not run them automatically:

```sh
python3 codex-memory/context_rollover.py status --json
python3 codex-memory/context_rollover.py prepare \
  --from-plan Test-Flight-Improv/NN-example-tdd-plan.md \
  --outstanding-work none \
  --task-scope-id "<stable-root-task-id>" \
  --changed-path lib/example.dart \
  --changed-path test/example_test.dart \
  --task-scope-complete
python3 codex-memory/context_rollover.py complete
python3 codex-memory/memory.py stats --session current
```

Checkpoint state is kept in ignored private `0600` files under
`codex-memory/state/context-rollover/`; lifecycle telemetry is appended to
`codex-memory/state/context-rollover-events.jsonl`. The regular memory report
shows prepared and recovery continuations separately, checkpoint-validation
misses separately from actual interruptions, Pre/PostCompact observations,
resumes, reason codes, root/subagent splits, task-scoped versus legacy
whole-worktree checkpoint attempts, READY completeness-asserted scoped adoption,
validated scoped resumes, READY declared-path counts, advisory-reset requests,
unresolved `NOT_READY` episodes, cross-generation repairs, blocked and actual
terminal attempts, later user rescues, checkpoint bytes, and estimated
model-visible capsule tokens. Failed scoped attempts stay visible but do not
inflate adoption or path totals. Telemetry stores only fixed categories,
integer counts, timestamps, ordinals, and hashes—never path names, prompt
content, commands, or raw identifiers. An advisory recovery is not counted as a
failure or as a validated resume. The report intentionally labels within-run
pre/post context reduction as **context dropped, not savings**.

Historical rollover experiments compare the same long task with automatic
Graphify and memory behavior held active in both arms. Running a new active-arm
experiment now requires explicitly restoring the removed lifecycle hook
registrations in addition to enabling `token_budget`; ordinary project sessions
remain on native compaction.

```sh
# Control replicate, in the parent shell before starting a fresh Codex session
eval "$(python3 codex-memory/task_run.py rollover-profile --arm control)"
codex --disable token_budget

# Active replicate, likewise in a separate fresh session
eval "$(python3 codex-memory/task_run.py rollover-profile --arm active)"
codex --enable token_budget
```

Inside each session, run the same arm-blind `task_run.py start` command shown
above, with the same task, replicate ID, required gate, and independent
held-out gate. Finish the run from the parent shell, then compare at least three
matched pairs:

```sh
python3 codex-memory/task_run.py compare \
  --task-id notification-fix-v1 --experiment rollover --json
```

Each report includes exact root/subagent/combined tokens before the first
rollover and after rollover, context-window count, attempts/completions/failures,
checkpoint footprint, and repeated code/document reads after reset. Those
within-run segments diagnose continuity but are not a counterfactual. Only the
matched control-to-active comparison can report `input_tokens_saved`, input and
total percentage reductions, and a `proven` verdict—and only when at least
three exact pairs pass identical required and held-out quality evidence. Each
active rollover must correlate one root `new_context` call with the same
prepared checkpoint lifecycle; fallback-only, mixed prepared/fallback, or
uncorrelated runs remain diagnostic and cannot claim savings. Each control run
must contain neither intervention, and there can be no policy, request,
environment, gate, defect, repair-turn, or completeness mismatch. Checkpoint
and tool-output estimates never enter that calculation.

The project config and hooks are intentionally local to this checkout. After
their first installation or a hook-definition change, review and trust them
with `/hooks` (or the startup review), then start a new thread. Once trust is
stored, `/new` is sufficient to reload the project config; an already-running
thread does not gain the new context tool retroactively.

## What Codex controls

Tracked defaults live in [`config.json`](config.json):

- source roots, include/exclude globs, source floors, and trust priority;
- automatic refresh and stat-vs-content freshness checking;
- default/hard token budgets, seed breadth, traversal depth, snippets, and
  per-document diversity;
- secondary-document adoption mode, shared-primary idle reset, preflight
  budget, and minimum enforceable raw-read size;
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

The `PreToolUse` hook runs bounded deterministic recall before an ungrounded
broad document search and again when its cadence is due. It injects the compact
result before the search; classification, refresh, and recall failures fail open
with a ready-to-run command. Only the explicit retrieval enforcement and narrow
primary output-safety decisions described below deny a call. A targeted search
inside one named document does not count as a corpus sweep.

The root task marks its explicitly named plan/spec by prefixing the first
document-only read with `CODEX_MEMORY_PRIMARY_READ=1`. That root-only marker
resets a session-shared hashed primary identity when a long-lived Codex thread
is reused; subagents inherit the identity instead of each receiving another
unguarded full-read exception. When no marker or shared state exists, the root
agent's first clean broad configured-document read becomes the primary. A
subagent that arrives first remains provisional: it may receive injected recall
but cannot claim or rotate the primary or trigger enforcement.

A broad/full read of a different configured document is a secondary retrieval
opportunity. The hook runs bounded path-anchored recall and requires provenance
for that exact document. `inject` mode (the tracked default) supplies focused
context without blocking. `shadow` records the outcome without supplying it;
`enforce` denies only an exact or focused, non-truncated, same-document hit and
directs Codex to a targeted search or a window of at most 120 lines. Broad or
truncated answers, misses, errors, provenance mismatches, mixed document/code
cells, changed documents, and classification failures all allow the original
read. Because the tracked default is `inject`, healthy default-mode adoption can
increase retrieval and delivered context while direct deny-only savings remain
zero.

Per session and agent, the hook also tracks a hashed document identity,
content-version hash, and merged line coverage. Direct `cat`, `sed`, `head`,
`read_file`, and bounded `nl ... | sed -n ...` forms are measured. Sequential
`nl` sizing includes conservative line-number prefix overhead. Sequential
primary chunks may therefore complete the required first pass without recall
between chunks. For a secondary document, one genuinely targeted window stays
open, but cumulative same-version windows trigger one preflight before they
cross the targeted-read threshold; splitting a full read into small chunks does
not bypass adoption. For a clean single primary or candidate-primary read,
PreToolUse narrowly denies only when the measured request exceeds 90% of the
visible outer output cap (`functions.exec` defaults to 10,000 tokens and honors
an `@exec` `max_output_tokens` pragma). The denial gives a byte-sized next
missing range based on session-shared confirmed coverage, the minimum higher cap
for the original read, and a one-shot
`CODEX_MEMORY_PRIMARY_OUTPUT_BYPASS=1` escape hatch. A root selection keeps
`CODEX_MEMORY_PRIMARY_READ=1` until the first safe chunk is confirmed, then
omits it so later chunks extend rather than reset coverage. Subagents may use the
next globally missing range to complete shared coverage, but can still request a
targeted window of at most 120 lines for the exact section they need. Mixed or
unparsed calls fail open, and the output-safety block is measured separately
from retrieval savings. Coverage and fallback success are committed only by the
matching `PostToolUse` event after its payload, exit status, truncation signals,
and delivered line count pass the conservative checks. This is evidence of a
complete hook response, not byte-for-byte proof of what the model retained.
Failed, clipped, denied, bypassed-over-cap, or unconfirmed attempts cannot create
complete coverage, clear fallback debt, or cause a later repeat block.

After complete first-pass coverage, small line windows and targeted `rg`/`find`
lookups remain allowed. A later broad overlapping or whole-document reread of
the unchanged version triggers one bounded exact recall. The hook denies that
read only when the recall result contains provenance for the same document; a
miss, error, provenance mismatch, mixed command cell, or changed file fails
open. An exact denied retry reuses the compact context and stays denied instead
of issuing another query.

The hook anonymously measures partial/whole configured-document reads and
estimated input tokens. `stats` joins the two anonymous ledgers, which exposes:

- recall calls, hits/misses, broad answers, output tokens, coverage, and p95;
- broad document sweeps, automatically grounded vs ungrounded sweeps,
  automatic/manual query counts, fallback reminders, anonymous agent count,
  multi-command cells, and auto-refreshes;
- unique configured documents, cumulative first-pass line coverage,
  unconfirmed ranges, targeted revisits, whole-file reads, and estimated raw
  input tokens;
- redundant broad attempts, same-provenance blocks, cached blocks, fail-opens,
  bypasses, repeat-guard automatic queries, and estimated avoided tokens;
- measured primary exemptions plus eligible secondary, broad-sweep, and
  repeat-read retrieval opportunities; attempted/focused/broad/miss/error
  outcomes and eligible-but-non-enforceable constraint reasons;
  injection/enforcement modes; root/subagent splits; targeted follow-ups; and
  direct net avoided tokens after delivered recall context and confirmed
  fallback-read overhead;
- no filenames or command text in telemetry. Hashed document/version, tool,
  input, command, batch, decision, and semantic raw-read identities allow joins
  and exact-retry deduplication without retaining raw identifiers. Equivalent
  whole-read forms share one raw intent even when their hook decisions differ.
  Query-output production and constructed model-context cost are reported
  separately. The latter is conservatively measured before the host's local
  additional-context cap. Injection alone receives no saved-token credit; only
  a unique denied raw-read intent can contribute estimated direct savings, and
  a later whole/bypass read removes that gross credit. Compare savings within a
  single policy-version cohort; query-production tokens are operational cost and
  are not subtracted again from model-visible context.

The privacy guarantee above applies to the telemetry ledgers. The local SQLite
corpus and private hook state/cache necessarily retain indexed or recalled text,
provenance, and document identities; they remain local derived state and are not
telemetry.

Disable query telemetry with `CODEX_MEMORY_TELEMETRY=0` or the reminder with
`CODEX_MEMORY_REMINDER=0`. Disable only automatic recall with
`CODEX_MEMORY_AUTO_RECALL=0`. Override the cadence with
`CODEX_MEMORY_REMINDER_CEILING`.

This checkout's ignored local `.codex/hooks.json` registers both `PreToolUse` and
`PostToolUse`; clones and other machines do not inherit it. After that hook
definition changes, start a fresh Codex CLI session and approve the updated
trusted hook definition; script/config changes then apply on subsequent
invocations without rebuilding the memory database. Its matcher covers the
named shell/read/search tool families only. Renamed tools, MCP reads, processes
outside the Codex hook pipeline, a non-Git working directory, or a hook timeout
remain unmeasured fail-open gaps rather than recorded misses. Graphify and memory
Pre hooks are independent; only a matching successful memory Post can confirm a
read.

For secondary-document adoption:

- set tracked defaults under `adoption` in `config.json`, or override them with
  `CODEX_MEMORY_SECONDARY_MODE`, `CODEX_MEMORY_PRIMARY_IDLE_SECONDS`, and
  `CODEX_MEMORY_SECONDARY_BUDGET`; enforcement also honors
  `CODEX_MEMORY_SECONDARY_MIN_RAW_TOKENS`, so recall cannot cost at least as
  much as the blocked read;
- use `CODEX_MEMORY_PRIMARY_READ=1` on the root task's first named-plan read to
  mark or reset the shared primary document;
- use `CODEX_MEMORY_SECONDARY_BYPASS=1` to force one secondary broad read;
- keep document reads/searches in document-only execution cells, with one
  configured document per broad-read cell, and carry any subagent recall as a
  separately labeled document-memory packet, never as Graphify code context.

For the repeat-read guard specifically:

- prefix one shell read with `CODEX_MEMORY_REPEAT_GUARD_BYPASS=1` to force that
  single read;
- set `CODEX_MEMORY_REPEAT_GUARD=0` for a persistent environment-level opt-out;
- set `CODEX_MEMORY_TARGETED_READ_LINES` to change the small-window threshold
  (120 lines by default);
- set `CODEX_MEMORY_REPEAT_GUARD_BUDGET` to change its bounded recall budget.

## Current acceptance gate

`benchmark` runs the 12 established plan-recall questions plus three real
document questions spanning the notification PRD, connection architecture, and
QA docs. It scores required fragments only in the returned output, never in the
question. This prevents a vacuous benchmark and gives config changes a cheap
regression gate.
