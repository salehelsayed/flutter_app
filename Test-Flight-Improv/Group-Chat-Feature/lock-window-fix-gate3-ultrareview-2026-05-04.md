# Gate 3 — `/ultrareview` triage closure (lock-window fix on PR #1)

Three free `/ultrareview 1` runs were used between 2026-05-03 and 2026-05-04 against
`salehelsayed/flutter_app#1` (branch `new-background` → `main`).

## Run-by-run findings

### Run 1 (commit `4730f6d9`)

| Bug | Severity | Category | Verdict |
|---|---|---|---|
| merged_bug_009 — drain Phase 1/2/3 atomicity loss (3 NEW regressions: history-gap loss, local-delivered receipt loss, orphan messages on mid-page sys-removal; +1 pre-existing reaction try/catch nit) | normal | drainGroupOfflineInbox / data loss | **🛑 ship-blocker — fixed** in `67442851` |
| merged_bug_001 — committed `.codex-bin/` + `.codex-gocache/` cruft | normal | repo hygiene | fixed in `f82f778e` |
| bug_002 — orchestrator agent def has invalid `gpt-5.5` model id + hardcoded user-specific memory path | normal | tooling file | fixed in `f82f778e` |
| bug_010 — `PassthroughCryptoBridge` and `ZeroPeerPublishBridge` subclasses bypass `dbWriteTransaction` guard for 3 commands | nit | test infra | fixed in `<this commit>` |
| merged_bug_011 — `no_raw_db_transaction_calls` lint regex misses `_db.transaction(...)` and Windows path normalization is a no-op | normal | dbWriteTransaction guardrail correctness | **🛑 ship-blocker — fixed** in `67442851` |

### Run 2 (commit `67442851`)

All ship-blockers from run 1 confirmed gone. Two `normal`-severity hygiene findings re-surfaced:

| Bug | Severity | Verdict |
|---|---|---|
| merged_bug_003 — orchestrator agent def (re-flag of bug_002) | normal | fixed in `f82f778e` |
| bug_001 — `.codex-bin/` + `.codex-gocache/` cruft (re-flag of merged_bug_001) | normal | fixed in `f82f778e` |

### Run 3 (commit `f82f778e`)

Both run 2 findings gone. One new normal-severity hygiene finding:

| Bug | Severity | Verdict |
|---|---|---|
| bug_001 — `.codex-home/` (1602 files of analyzer-driver scratch + per-developer CLIENT_ID UUID + telemetry session) was missed by `f82f778e` | normal | fixed in `7dc6376f`; same recipe broadened to `.codex-home/` + 4 sibling dirs proactively swept (`CompilationCache.noindex/`, `Logs/`, `output/`, `.playwright-cli/`) |

## Pass criteria check (per the plan in `~/.claude/plans/binary-growing-aurora.md`)

- [x] **Zero High-severity findings** across all three runs.
- [x] **Zero findings in the must-be-zero categories** (data loss / lock contention / transaction atomicity / drainGroupOfflineInbox races / dbWriteTransaction breakage) after run 1's fixes landed in `67442851`. Runs 2 and 3 returned no findings in these categories.
- [x] **All Medium (`normal`) findings either fixed or accepted** — every `normal` finding from runs 1, 2, and 3 has been fixed in a follow-up commit on this branch (`67442851`, `f82f778e`, `7dc6376f`, plus this commit for the `bug_010` nit).
- [x] **Lows / nits explicitly addressed** — `bug_010` (FakeBridge subclass guard bypass) was a `nit`-severity test-infra finding with no production impact (real `GoBridgeClient.send` always asserts the guard); patched anyway for consistency, with two new tests in `db_write_transaction_guard_test.dart` pinning the contract per subclass.

## Why we stop here without a 4th run

The `/ultrareview` free quota is exhausted (3 of 3 used). The pattern across runs is:

- Run 1 surfaced the real correctness regressions in the lock-window refactor + every outstanding hygiene class on the branch.
- Runs 2 and 3 only surfaced **one more sandbox-cache directory each** that the previous cleanup commit had missed.

After run 3 we proactively grepped the top-level tree and swept 4 additional sibling cache classes (`CompilationCache.noindex/`, `Logs/`, `output/`, `.playwright-cli/`) under the same `.gitignore` pattern. Tracked-file count dropped from 8947 → 2977. A 4th paid run is most likely to surface another obscure file path of the same class, which we cannot mechanically enumerate ahead of time. The remaining diff vs `main` is dominated by the deliberate WIP scope on `new-background` (the user's choice from the plan: "ship `new-background` as-is"), not by any cache-hygiene class we have not addressed.

## Decision

Gate 3 **closed**. Proceeding to Gate 4 (version bump → Android AAB + iOS IPA builds).

## PR head at closure

`<this commit>` on branch `new-background`, four commits ahead of the lock-window fix:

```
4730f6d9  Fix offline-inbox drain holding SQLCipher write lock across bridge calls
67442851  Fix drain Phase 2/3 atomicity gaps surfaced by /ultrareview
f82f778e  Stop tracking local Codex sandbox artifacts and fix orchestrator agent definition
7dc6376f  Untrack remaining sandbox / build caches missed by f82f778e
<this>    Patch FakeBridge subclass guard bypass (/ultrareview run 1 bug_010)
```
