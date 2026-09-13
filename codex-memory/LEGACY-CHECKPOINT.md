# Legacy checkpoint workflow (disabled)

Status: historical implementation reference. Ordinary project sessions use
native compaction; the lifecycle hooks described below are not registered.
Keep this material for the retained implementation, tests, and historical
telemetry. It does not authorize enabling checkpoint orchestration.

The current workflow is documented in [README.md](README.md#native-context-compaction-checkpoint-rollover-disabled).

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

Inside each session, run the same arm-blind `task_run.py start` command in
[the benchmark instructions](README.md#task-level-offshadowactive-benchmark), with the same task, replicate ID, required gate, and independent
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
