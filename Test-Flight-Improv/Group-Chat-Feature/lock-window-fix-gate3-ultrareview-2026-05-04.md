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

---

## Post-closure follow-up — malformed-envelope coverage gap (filed 2026-05-04 after Pixel +88 hardware soak)

### What slipped through

After Gate 3 closed and we shipped the +87 build, the Pixel hardware re-test surfaced a *separate* bug we conflated mid-debug with a residual lock-window:

- **Symptom**: opening an existing group on the Pixel showed three blank/grey bubbles in the conversation screen instead of the messages whose previews were visible from the Orbit list.
- **First diagnosis (wrong)**: I read the `database has been locked for 0:00:10` warnings in logcat and assumed the conversation screen's `getMessagesPage()` was queued behind a busy lock — i.e. another instance of the same lock-window class as the original Orbit-skeleton stall.
- **Actual root cause**: `GroupMessageListener._handleMessage` was persisting events with `text=""` and no media. Those rows came back from the DB and the conversation screen rendered them as empty bubbles. The lock warnings I saw were *unrelated* concurrent activity that happened to coincide. This was visible in `git diff` as uncommitted WIP modifications to `lib/features/groups/application/group_message_listener.dart` — I had treated those modifications as "user state, don't audit" rather than reviewing the diff.
- **Fix**: the listener empty-message drop guard the user had already drafted (uncommitted) — early-return inside `_handleMessage` if `text.isEmpty && media.isEmpty`, plus a `GROUP_MESSAGE_LISTENER_EMPTY_DROP` flow event. Landed in commit `dfb96e32` together with the simulator tests and other in-flight WIP.

### Why the original test plan missed it

The five reasons, each independently sufficient, that none of our +87-era tests caught this:

1. **Scope of TDD was set by the symptom we'd already named.** Tests optimized for proving the lock-window contract held. None exercised "what happens when upstream emits a malformed event."
2. **No fuzz / malformed-input coverage on the listener.** Existing listener tests validated well-formed envelopes (signed, decrypted, with text). No test for "what if `text` is empty after decode."
3. **Bug was in pre-existing WIP code I never reviewed.** `_handleMessage` had been on the branch as uncommitted-modified the entire time. I treated it as user state and didn't audit it.
4. **Hardware validation used clean inputs.** The 25-message reproduction had iOS sim "a" sending well-formed signed envelopes through `buildGroupOfflineReplayEnvelope` — exactly the path that *cannot* produce empty-text events. So the hardware test was incapable of exposing this bug.
5. **Release builds suppress `[FLOW]` events.** When I read the +86 logcat I saw `[BRIDGE-EVENT]` entries but no FL/UC/DB granular events, so I had to guess from indirect signals (the lock warning timing) instead of reading the actual symptom.

### What we added in response

- **Listener-side regression tests** (already in `dfb96e32` alongside the guard): three tests in `test/features/groups/application/group_message_listener_test.dart` covering `text` missing, `text == null`, and the legitimate "empty text + media" pass-through path.
- **Cross-system regression test** (added in *this* commit): `test/features/groups/application/drain_followup_invariants_test.dart` — "drain → listener: malformed envelope decoding to text-less, media-less payload does NOT persist an empty row." Pins the contract that the listener guard fires when a malformed envelope arrives via the offline-drain path, not just the live GossipSub stream.

### Outstanding follow-ups (do these before the next release with significant group-messaging changes)

1. **Hardware soak must include a malformed-envelope injection point.** The next time we hardware-validate group-messaging work, the test plan needs at least one upstream event that decodes to text-less / media-less. The simplest way: extend `_PageBridge` (or a sibling fake at the Go-bridge layer) to occasionally return a skeleton envelope, and run a soak where the conversation screen is opened repeatedly during ingest. If that soak takes >15 min on hardware, run it on simulator-only via `reset_simulators.sh`.
2. **Audit `handleIncomingGroupMessage` for parallel weakness.** The use case has many `return null;` branches (lines 69, 96, 108, 133, 154, 166, 181, 199, 248, 277). At least one of these may also persist empty rows in some path. A focused read with the same lens as the listener fix is worth ~30 min before this code area changes again.
3. **Extend the drain test scaffolding to inject malformed envelopes.** `_PageBridge` and the helpers in `drain_followup_invariants_test.dart` are now the canonical scaffolding for drain-side regression coverage. Adding a `addMalformedPage(...)` helper would make future malformed-envelope tests trivial to write.
4. **Mid-debug rule for next time:** if a UI symptom looks like "skeleton placeholder stuck", VERIFY whether the rows are real-but-empty before assuming it's a loader. Open a debug build (FLOW events visible) and check what `getMessagesPage` actually returns. The 10s lock warning is *not* a reliable indicator that the load itself is blocked — there are many paths that produce that warning concurrently with unrelated UI states.
5. **Consider stricter `dbWriteTransaction` guard** that also fails if the body awaits any method on a `Database`/`DatabaseExecutor` other than the supplied `txn`. The current guard catches bridge calls (which is the high-impact case) but not parent-DB awaits. A `Zone`-based proxy that intercepts non-`txn` calls inside the body would close that hole, at the cost of slightly heavier dev-build overhead.

### PR head at this update

```
dfb96e32  Land in-flight WIP: empty-msg listener guard, simulator tests, relay binary
a600a5cf  Bump 1.0.0+88: live-message symptom fix verified on hardware
e8066621  Bump 1.0.0+87: lock-window fix + dbWriteTransaction guard
f412df19  Patch FakeBridge subclass guard bypass + Gate 3 closure note
7dc6376f  Untrack remaining sandbox / build caches missed by f82f778e
f82f778e  Stop tracking local Codex sandbox artifacts and fix orchestrator agent definition
67442851  Fix drain Phase 2/3 atomicity gaps surfaced by /ultrareview
4730f6d9  Fix offline-inbox drain holding SQLCipher write lock across bridge calls
<this>    Add drain → listener empty-envelope cross-system test + post-closure follow-up note
```
