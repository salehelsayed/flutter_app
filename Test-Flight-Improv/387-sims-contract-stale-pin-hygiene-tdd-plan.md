# 387 - Sims-Contract Stale-Pin Hygiene: Unblock The Aborting Gate

Status: **EXECUTED 2026-08-19 — all three in-scope contracts HOST GREEN, every recorded mutation re-reds, gate UNBLOCKED. TC-387-04 is PARTIALLY met and not claimed otherwise: `sims-contracts` now runs every contract instead of aborting at #4 (43 of 44 PASS), but it still exits 1 at a FOURTH red that step 1's stop-if found and this plan deliberately does not fix — see H4.**
Type: Bug
Spec: free-text intent (no formal spec) — the stale pins recorded in `Test-Flight-Improv/380-notification-device-matrix-and-b12-sound-tdd-plan.md:548-554`
Classification: implementation-ready
Closure tier: host

Split out of [386](386-reaction-lane-evidence-repair-and-audience-device-legs-tdd-plan.md) on review
finding (wf_77341dcf-8b1): these three fixes share **zero files, zero symbols and zero tier** with
386's reaction-lane work. They were bundled only because they happen to share an aborting gate.
This plan has no device leg, no dependency on any other plan, and can land today.

## Planning Progress
| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-08-19 | Evidence Collector | the three red contracts (run on host), `run_test_gates.sh:1663-1760`, `dtr13_…_test.sh`, `intro_accept_…_test.sh`, `project-memory/{src/build_graph.py,tests/test_project_memory.py}` | 3 contracts red; 2 of Plan 380's 3 attributions are wrong | Verify each mechanism |
| 2026-08-19 | Planner | same + `git log` provenance for both drifted roots | All three mechanisms confirmed at source; split out of 386 | Emit plan |
| 2026-08-19 | Reviewer (wf_77341dcf-8b1) | this contract | 3 escapes found and closed (key-set delete, assertion delete, wrong-fix A/B) | Deltas applied below |

## Problem And Evidence

- **Behavior to improve:** `./scripts/run_test_gates.sh sims-contracts` aborts at its **4th** contract
  and returns non-zero, so **no contract after the 4th has run since at least 2026-08-17**. The gate
  enumerates `scripts/test/*_test.sh` sorted `LC_ALL=C` and returns on the first failure unless
  `--continue-on-failure` is passed (`scripts/run_test_gates.sh:1706-1760`).
- **Impact:** every sims contract after `dtr13_…` is unverified, including the ones plans 384/385
  register into. A gate that always aborts in the same place stops being read.
- **Confirmed root causes** — three independent stale pins, each verified by running the contract:

  **H1. `dtr13_profile_entrypoint_preservation_contract_test.sh` — TWO drifted hashes, not one.**
  `DTR13-AUTH-01` byte-locks four entrypoint roots (`:201-210`). Two have drifted:
  `lib/smoke_test_main.dart` (`522bc158…` → `c99e6212…`) and `lib/smoke_test_restore.dart`
  (`09cefe37…` → `43226bf4…`). Both drifted in the **same authorized commit** `87f0f7ba0`
  ("DTR Waves 4A-4C"), each by the identical one-line import relocation
  `features/identity/domain/repositories/…` → `features/identity/data/repositories/…` — which is
  precisely what DTR-18 did. The old path no longer exists and the new one does, so **re-pinning is
  the only correct fix**; reverting the files would break compilation. The assert lives inside
  `for path, expected_hash in expected_hashes.items()` (`:211-213`), so the loop dies on the first
  mismatch and the second drift is invisible. Plan 380 recorded only the first.

  **H2. `intro_accept_notification_sims_adapter_contract_test.sh` — the failing assertion is not the
  one Plan 380 named.** The failure is at contract file line 42 (`python3 <stdin>` line 11):
  `assert r"r'^Status:[ \t]+ok[ \t]*\r?$'" in launch`. The regex was extracted out of `_launchAll()`
  into the top-level helper `isAndroidActivityStartAccepted`
  (`integration_test/scripts/run_intro_accept_notification_android.dart:82-87`) and **widened** to
  `(?:ok|timeout)`, with the rationale documented at `:75-81` (an `am start -W` wait timeout does not
  mean the launch failed, and the next phase still requires a fresh identity export). Plan 380 blamed
  `'final output = await _adbShell'` — verified still present in the slice, so that attribution is wrong.

  **H3. `project_memory_recall_contract_test.sh` — a committed symlink-fragile comparison.**
  `test_memory_never_overrides_plan_facts` (`project-memory/tests/test_project_memory.py:840-912`)
  builds a synthetic two-tempdir fixture, then counts MEMORY/NOTE entities whose `source_doc` does
  not start with the temp memory dir. It passes the **unresolved** `TemporaryDirectory` name as the
  `LIKE` prefix (`:910`, and symmetrically `:902`) while `build_graph.py:699` stores
  `str(record["path"].resolve())`. On macOS `$TMPDIR` is `/var/folders/…` where `/var` is a symlink to
  `private/var`, so both memory rows fail the prefix and the count is 2. Plan 380 attributed this to
  "untracked plan-381 work in progress"; `project-memory/` is **clean at HEAD** and both files were
  landed by `90bc7d601`, so that attribution is also wrong.

- **Existing coverage:** the three contracts are themselves the tests; `run_sims_contracts`
  auto-discovers every `scripts/test/*_test.sh` (`run_test_gates.sh:1710-1714`), so no registration
  work exists for any of them.
- **Missing coverage:** H1's freeze has no key-set assertion, so an entry can be deleted rather than
  re-pinned (see TC-387-01). H2's contract does not pin the helper that now owns the rule.
- **Refuted findings (do NOT re-introduce):**
  - *"The intro-accept contract fails on `'final output = await _adbShell'`"* — refuted; that fragment
    matches today. The failing assertion is the `Status`-regex one at file line 42.
  - *"The DTR13 item is one stale hash"* — refuted; two roots drifted, the second shadowed by the
    loop's fail-fast.
  - *"`project_memory_recall_contract_test.sh` is red from untracked plan-381 work"* — refuted;
    `project-memory/` is clean at HEAD.
  - *"Resolving the tempdir prefix also de-vacuums the sibling `leaked` check at `:902`"* — **refuted
    by the review.** The two passes write `source_doc` in different *shapes*: the plan pass stores a
    **relative** path, the memory pass an **absolute** one. A relative string can never `LIKE`-match an
    absolute prefix, with or without `resolve()`. Resolving `:902` is still correct hygiene, but it
    does not make that assertion falsifiable — see TC-387-03's note.
- **Unresolved findings — RESOLVED by step 1's measurement.** The full set is four reds, not three:
  contracts #4, #13, #20 (this plan's H1/H2/H3) and #26 (H4 below). The other 40 all passed.

  **H4. `run_claude_docker_update_contract_test.sh` (contract #26) — a FOURTH red, recorded and NOT
  fixed here.** It fails at `:78`, `normal launch did not build the cached image`. Commit `ed7e07284`
  (2026-08-09, "chore: refresh local tooling paths, docker launch guard, and arch graph")
  intentionally changed `scripts/run_claude_docker.sh:473-478` so a normal launch builds **only** when
  `CLAUDE_DOCKER_REBUILD=1` or the image is absent, and passes `--pull` when it does build. The
  contract still pins the pre-change behavior in two places: `:78` (a normal launch must build) and
  `:79-80` (a normal launch must not pass `--pull`). It has been red for ten days, invisible because
  the gate aborted at #4 long before reaching #26 — precisely the harm this plan exists to describe.
  Unlike H1-H3 this is **not** a stale byte- or text-pin: the runner change was deliberate and
  documented in its own comment, so closing it means deciding which behavior is now correct and
  re-pinning the contract to that decision. That is a behavior call for the runner's owner, not
  gate hygiene, so step 1's stop-if was honored: recorded, not touched.
- **Affected files:** `scripts/test/dtr13_profile_entrypoint_preservation_contract_test.sh`,
  `scripts/test/intro_accept_notification_sims_adapter_contract_test.sh`,
  `project-memory/tests/test_project_memory.py`. No `lib/` change. No production change of any kind.

## Graph Grounding Snapshot
- Graph fingerprint / freshness: `9159ad66b3b286d0`, `freshness=current`.
- Query / profile: `python3 graphify-arch/tdd_context.py query "isAndroidActivityStartAccepted definition" --profile general --budget 400` (confidence=anchored).
- Anchors: `isAndroidActivityStartAccepted` → `integration_test/scripts/run_intro_accept_notification_android.dart:82`.
- Surfaced proof/gate files: none — the arch graph does not cover `scripts/test/*.sh` or
  `project-memory/`, which is why every claim here is source- or run-verified instead.
- Graph gaps that required raw source search: all three contracts, `run_test_gates.sh`, and the whole
  of `project-memory/`. This plan is essentially graph-invisible by construction.
- Reuse rule: anchors are search starting points; every conclusion here is command- or source-backed.

## Scope Contract And Guard

In scope:
- Re-pin `DTR13-AUTH-01` for both drifted roots, **after** verifying provenance, and add the key-set
  assertion that makes deletion-instead-of-re-pinning impossible.
- Re-point the intro-accept launch-acceptance assertions at the helper that now owns the rule, keeping
  the strictness (only `ok|timeout` accepted, never `monkey`).
- Make both project-memory prefix comparisons symlink-safe, test-side only.

Must preserve:
- The other two DTR-13 hashes (`lib/smoke_test_messages.dart`, `lib/core/debug/smoke_test_runner.dart`)
  and every non-hash assertion in that contract → `TC-387-01`.
- The intro-accept contract's other slices (install, documents-writer, `monkey` ban) → `TC-387-02`.
- Every other project-memory test (22 in the suite) → `TC-387-03`.

Hard `Do not`:
- **Do not weaken a pin to make a gate green.** Re-pin to a provenance-verified value or escalate.
  Deleting an entry from `expected_hashes`, or deleting a failing assertion, is the failure mode this
  plan exists to prevent — TC-387-01 and TC-387-02 make both impossible.
- **Do not change `project-memory/src/build_graph.py`.** The fix is test-side. Dropping `.resolve()`
  at `:699` would change stored provenance strings that other real-memory pins compare against.
- Do not touch `lib/`, `integration_test/scripts/run_intro_accept_notification_android.dart`, or any
  reaction/muted lane file — those belong to plan 386.
- Do not fix any sims contract red that is **not** one of these three without recording it first
  (see the stop-if in step 1).

Deferred / accepted difference:
- The `leaked` check at `test_project_memory.py:902` stays structurally vacuous even after this fix,
  because of the relative-vs-absolute `source_doc` shape mismatch described above. Owner: whoever next
  touches the project-memory schema. Recorded, not silently accepted — TC-387-03's note states it and
  the row does **not** claim to fix it.

Dependencies: none. This plan is independent of 384, 385 and 386.

## Test Contract
Zero empty cells. `HEAD state` is one of `causal RED` · `GREEN sentinel` · `manual/device-only proof`.

| Case | Behavior | Named test/proof | Tier / fixture | HEAD state → GREEN | Mutation that re-reds | Gate / registration |
|---|---|---|---|---|---|---|
| TC-387-01 | The DTR-13 freeze matches the authorized DTR-18 relocation, still bites on BOTH drifted roots, and cannot be satisfied by deleting an entry | `scripts/test/dtr13_profile_entrypoint_preservation_contract_test.sh` (the contract is the test) | sh contract / host, no fixture | causal RED (`AssertionError: DTR13-AUTH-01 byte lock changed: lib/smoke_test_main.dart`, exit 1; the `smoke_test_restore.dart` drift is shadowed behind it) → exit 0 with all four hashes matching **and** the new key-set assertion passing | TWO recorded mutations, both required: append one byte to `lib/smoke_test_main.dart` → red naming that path; separately append one byte to `lib/smoke_test_restore.dart` → red naming **that** path (proves the previously-shadowed pin is live). Third: delete either entry from `expected_hashes` → the new key-set assertion reds | `/claude-host-bin/host-run bash scripts/test/dtr13_profile_entrypoint_preservation_contract_test.sh`; AUTO — `run_sims_contracts` globs `scripts/test/*_test.sh` (`run_test_gates.sh:1710-1714`) |
| TC-387-02 | The intro-accept contract pins the launch-acceptance rule where it now lives, and cannot be satisfied by deleting the assertion | `scripts/test/intro_accept_notification_sims_adapter_contract_test.sh` | sh contract / host, no fixture | causal RED (bare `AssertionError`, `<stdin>` line 11 = file line 42) → exit 0, with the contract now slicing **two** regions: `_launchAll()` must contain `isAndroidActivityStartAccepted(`, and the top-level helper slice must contain the exact widened literal `r'^Status:[ \t]+(?:ok\|timeout)[ \t]*\r?$'` | BOTH mutations required (not either): (a) widen the helper regex to `r'^Status:'` → the helper-slice assertion reds; (b) delete the `isAndroidActivityStartAccepted(` call from `_launchAll` → the launch-slice assertion reds. Running only one is non-compliant | same host-run command; AUTO (glob) |
| TC-387-03 | The project-memory memory-pass contract compares source paths symlink-safely, test-side only | `project-memory/tests/test_project_memory.py::test_memory_never_overrides_plan_facts` | python unittest / synthetic two-tempdir corpus (reads neither the real corpus nor the real memory dir) | causal RED under a symlinked `TMPDIR` (`AssertionError: 2 != 0` at `:912`); GREEN in-container by default → 0, with the suite's other 21 tests unchanged | (a) revert the `:910` prefix to the unresolved form and run under a symlinked `TMPDIR` → red. (b) The wrong-fix guard: change `build_graph.py:699` to drop `.resolve()` instead → the suite passes, which is why that file is in the hard `Do not` and step 3 diffs it to prove it is untouched | `mkdir -p /tmp/pm387/real && ln -sfn /tmp/pm387/real /tmp/pm387/link && TMPDIR=/tmp/pm387/link python3 project-memory/tests/test_project_memory.py`; then `/claude-host-bin/host-run bash scripts/test/project_memory_recall_contract_test.sh`; AUTO (glob) |
| TC-387-04 | `sims-contracts` runs every contract to completion | `./scripts/run_test_gates.sh sims-contracts` | gate / host | causal RED (aborts at contract #4, exit 1) → exit 0, every contract `PASS` | re-introduce any one stale pin → the gate reds at that contract | `/claude-host-bin/host-run ./scripts/run_test_gates.sh sims-contracts`; AUTO (glob) |

### Test Notes
- **TC-387-01 provenance is recorded evidence, not prose.** The GREEN state requires capturing, into
  the execution log, the literal outputs of `git log -1 --format=%h -- <path>` (must be `87f0f7ba0`
  for both roots) and `git show 87f0f7ba0 -- <path>` (must show only the one-line
  `identity/domain/repositories` → `identity/data/repositories` change). Without those two artifacts
  the row is not satisfied — otherwise "re-pin" and "rubber-stamp whatever the file hashes to today"
  are indistinguishable, and the second is exactly what a byte lock exists to catch.
- **TC-387-01's new assertion, verbatim.** Immediately before the hash loop
  (`dtr13_…_test.sh:211`), add:
  `assert set(expected_hashes) == {"lib/smoke_test_main.dart", "lib/smoke_test_messages.dart", "lib/smoke_test_restore.dart", "lib/core/debug/smoke_test_runner.dart"}`.
  Without it the dict is only ever iterated, so deleting an entry silently removes a freeze and the
  contract still exits 0.
- **TC-387-03 does not claim to fix the `leaked` check.** Resolving the `:902` prefix is correct
  hygiene and is in scope, but that assertion remains structurally unfalsifiable: the plan pass writes
  a **relative** `source_doc` and the memory pass an **absolute** one, so no `LIKE` prefix over an
  absolute path can ever match a plan row regardless of symlink normalization. Making it falsifiable
  needs a different query shape (compare on a corpus basename prefix, with a seeded negative fixture
  that writes a memory note into the corpus dir) — deferred, with the owner named above.
- **TC-387-03 is environment-sensitive by nature, and the command handles it.** The red reproduces
  only when `tempfile.gettempdir()` traverses a symlink. The acceptance command therefore **creates**
  the symlink; pointing `TMPDIR` at a non-existent directory silently falls back to `/tmp` and the
  test passes, which would read as "already fixed".

## Implementation Steps
1. Snapshot `git status --short`. Run
   `./scripts/run_test_gates.sh sims-contracts --continue-on-failure` and record the **complete**
   current red set. Stop-if: any red beyond these three — record it and decide before touching
   anything. Plan 380's list is from 2026-08-17 and plans 384/385 have landed since.
2. **H1.** Verify provenance for both roots (step's stop-if: any commit other than `87f0f7ba0`, or any
   diff other than the single import relocation → do not re-pin, escalate). Then update both hashes
   **and** add the key-set assertion in the same edit.
3. **H2.** Extend the contract to slice `isAndroidActivityStartAccepted` as well as `_launchAll()`,
   assert the call in the launch slice and the exact widened regex literal in the helper slice, and
   keep the existing `monkey` ban and `am`/`-W`/`-n` fragments untouched.
4. **H3.** Resolve the prefix in both queries (`:902` and `:910`). Then run
   `git diff --stat project-memory/src/` and confirm it is **empty** — the fix is test-side.
5. Re-run each contract individually, then the full gate.

## Risks And Blind Spots
- **Re-pinning a freeze can rubber-stamp an unauthorized change** → guarded by TC-387-01's recorded
  provenance artifacts and step 2's stop-if.
- **Fixing the first assert can hide a second** — this is exactly how H1 was under-reported → guarded
  by TC-387-01's two separate mutations, one per drifted root.
- Lifecycle / derived-state durability: N/A — no runtime state, no persistence, no derived UI.
- Sibling-surface consistency: the two other DTR-13 hashes are verified unchanged (`94e604db…`,
  `852b835a…`) and stay pinned; TC-387-01's key-set assertion keeps all four in the set.
- Destructive-action side effects: N/A — no delete, cleanup or cancel path is touched.
- Invariant re-verification under new transitions: N/A — no new transition.
- Construction / call-site census: N/A — no symbol gains an argument or a seam. The only census is the
  `expected_hashes` key set, which TC-387-01 pins explicitly.
- Build-artifact provenance: N/A — nothing native, nothing shipped, no binary.
- Permission / ACL verb symmetry: N/A — no permission or ACL check is touched.
- Fake side-effect fidelity: the project-memory fixture is fully synthetic and reads neither the real
  corpus nor the real memory dir (`test_project_memory.py:840-863`), so no production-writer
  reachability question arises.
- Composite-node / relationship assertions: N/A — every assertion here is over a single value.

## Gate Cadence
- Per-plan closure: the three contracts individually, then `sims-contracts` whole. That is the entire
  cadence — this plan changes no production surface, so no curated lane, no `feature-host-all`, no
  `core-host-all` and no performance sweep is justified.
- Graph-affected: **N/A with reason** — `tdd_context.py affected` walks import edges, and none of the
  three changed files is imported by anything (two are shell contracts, one is a test module). Running
  it would return nothing and prove nothing.
- Full `host-all` is not a per-plan gate here and is not implied: `project-memory/tests/` is not under
  `test/`, so no host scope globs it at all.
- Shared tests outside the feature/core globs: none. `project-memory/tests/test_project_memory.py` is
  reached only by its own contract, which `sims-contracts` runs.

## Acceptance Gates  (literal — copy/paste)
```bash
# Dirty-tree snapshot
git status --short

# Measure the REAL red set first (do not trust the 2026-08-17 list)
/claude-host-bin/host-run ./scripts/run_test_gates.sh sims-contracts --continue-on-failure

# H1 causal RED, then provenance evidence, then GREEN
/claude-host-bin/host-run bash scripts/test/dtr13_profile_entrypoint_preservation_contract_test.sh
git log -1 --format=%h -- lib/smoke_test_main.dart        # expect: 87f0f7ba0
git log -1 --format=%h -- lib/smoke_test_restore.dart     # expect: 87f0f7ba0
git show 87f0f7ba0 -- lib/smoke_test_main.dart lib/smoke_test_restore.dart | grep '^[-+]import'
sha256sum lib/smoke_test_main.dart lib/smoke_test_restore.dart

# H2 causal RED, then GREEN
/claude-host-bin/host-run bash scripts/test/intro_accept_notification_sims_adapter_contract_test.sh

# H3 causal RED (the symlink must EXIST or TMPDIR silently falls back to /tmp and this passes)
mkdir -p /tmp/pm387/real && ln -sfn /tmp/pm387/real /tmp/pm387/link
TMPDIR=/tmp/pm387/link python3 project-memory/tests/test_project_memory.py
# expect exit 1: AssertionError: 2 != 0 at tests/test_project_memory.py:912

# H3 GREEN + the wrong-fix guard (must be EMPTY — the fix is test-side)
TMPDIR=/tmp/pm387/link python3 project-memory/tests/test_project_memory.py
git diff --stat project-memory/src/
/claude-host-bin/host-run bash scripts/test/project_memory_recall_contract_test.sh

# Closure — exit 0, every contract PASS, no FAIL: line
/claude-host-bin/host-run ./scripts/run_test_gates.sh sims-contracts

# Hygiene
git diff --check
```

Semantic outcomes: each contract exits 0 with no `FAIL:` line; `sims-contracts` exits 0 having run
every discovered contract (the plan line it prints at the top states the count — that count is the
gate's own contract, not a number this plan pins); the H3 RED command exits 1 with the exact
assertion above; `git diff --stat project-memory/src/` prints nothing.

## Rollback
- Reversible by: `git revert <this plan's commit>`. Three files, all test/gate source.
- What a PRIOR shipped build does with post-change data: **N/A — nothing ships.** No `lib/` code, no
  schema, no wire format, no artifact shape, no user data.
- NOT recoverable once landed: nothing.
- Staging: not required. The only one-way-shaped element is the freeze update, and it is guarded by
  recorded provenance plus the key-set assertion, so a wrong re-pin is visible in the diff.

## Execution Interpretation And Done Criteria
- Expected RED: TC-387-01 through TC-387-04 fail on HEAD for the documented reasons.
- GREEN sentinel: none — every row here is causal. The preservation obligations are covered inside
  TC-387-01/02/03 (the other two hashes, the other contract slices, the other 21 python tests).
- Pre-existing dirty tree / known failure: any sims-contract red beyond these three, discovered in
  step 1, is recorded and NOT fixed here.
- Environment blocker (NOT a product blocker): the host bridge being unavailable. Note that
  `scripts/test/*.sh` gates must run via `/claude-host-bin/host-run` — a container-local run uses
  different `dart`/`flutter` shims and its red is not a real red.
- Scope drift (BLOCKING): any `lib/` change, any `project-memory/src/` change, any edit to a
  reaction/muted lane file, or fixing a fourth contract without recording it first.

- [x] Every behavior has a named test.
- [x] Causal RED, focused GREEN, and every listed mutation re-red are recorded — including both
      TC-387-01 byte-appends and both TC-387-02 mutations.
- [x] Provenance artifacts for both drifted roots are captured in the execution log.
- [x] `git diff --stat project-memory/src/` is empty.
- [ ] `sims-contracts` exits 0 having run every contract. **NOT MET, and not claimed.** It now *runs*
      every contract (43 of 44 PASS, versus aborting at #4 before this plan), but exits 1 on H4 —
      the fourth red, out of scope by this plan's own hard `Do not`. Closing this box needs the H4
      behavior decision, not more work on H1-H3.
- [x] `git diff --check` is clean.
- [x] The Scope Contract And Guard is respected — no `lib/`, no `project-memory/src/`, no
      reaction/muted lane file, and the fourth red recorded rather than fixed.

## Handoff
- First causal RED command:
  `/claude-host-bin/host-run bash scripts/test/dtr13_profile_entrypoint_preservation_contract_test.sh`
  (expect exit 1, `DTR13-AUTH-01 byte lock changed: lib/smoke_test_main.dart`).
- Preservation command: `/claude-host-bin/host-run ./scripts/run_test_gates.sh sims-contracts`.
- Manual registration: none — `run_sims_contracts` auto-discovers `scripts/test/*_test.sh`.
- Migration: none.
- Boundary closure: host-only. No device, no relay, no simulator.
- Unresolved evidence: the full current red set of `sims-contracts` (measured in step 1); and the
  `leaked`-check vacuity, deferred with an owner.

## Execution Progress
| Time | Phase | Files | Last command/result | Current evidence | Decision/blocker | Next |
|---|---|---|---|---|---|---|
| 2026-08-19 | Step 1 — measure | none (read-only) | `run_test_gates.sh sims-contracts --continue-on-failure` -> exit 1, 40 PASS / 4 FAIL | #4 `DTR13-AUTH-01 byte lock changed: lib/smoke_test_main.dart`; #13 bare `AssertionError` at `<stdin>`:11 (= file line 42); #20 `AssertionError: 2 != 0` at `test_project_memory.py:912`; #26 `normal launch did not build the cached image` | **Stop-if FIRED**: a 4th red exists. Diagnosed to `ed7e07284` and recorded as H4; NOT fixed, per the hard `Do not` | provenance for H1 |
| 2026-08-19 | Step 2 — H1 provenance | `lib/smoke_test_main.dart`, `lib/smoke_test_restore.dart` | `git log -1 --format=%h` -> `87f0f7ba0` for BOTH; `git show 87f0f7ba0` -> one line each, `identity/domain/repositories` -> `identity/data/repositories` | old path absent, new path present, so revert would not compile | Re-pin authorized; stop-if not triggered | edit contract |
| 2026-08-19 | Steps 2-4 — fix | the three files in Affected files | H1 re-pin + key-set assertion; H2 helper slice; H3 both prefixes resolved | `git diff --stat project-memory/src/` EMPTY (wrong-fix guard) | All three contracts exit 0 individually on host-run | mutations |
| 2026-08-19 | Mutations | as above, each reverted | 7 mutations, all re-red their own row | TC-387-01: `smoke_test_main` append -> reds naming it; `smoke_test_restore` append -> reds naming **it** (the previously-shadowed pin is live); entry deletion -> `DTR13-AUTH-01 byte-lock key set changed`. TC-387-02: helper regex widened -> reds at `<stdin>`:20 (helper slice); call deleted from `_launchAll` -> reds at `<stdin>`:11 (launch slice). TC-387-03: unresolved `:910` under symlinked TMPDIR -> `2 != 0`; **wrong-fix mutation passes the suite (`OK`)**, caught only by the `project-memory/src/` diff guard | Every listed mutation recorded | closure |
| 2026-08-19 | Step 5 — closure | - | plain `sims-contracts` -> #1-#25 PASS, aborts at #26, exit 1 (was: aborted at #4). `--continue-on-failure` -> **43 PASS / 1 FAIL**, exit 1 | `git diff --check` clean; tree = exactly the 3 intended files | TC-387-01/02/03 CLOSED. TC-387-04 partially met: runs every contract, does not exit 0, blocked solely by H4 | H4 needs an owner decision |
