# INTRO-REL-007 Execution Plan

Status: execution-ready

## Planning Progress

- 2026-05-22T21:10:56+02:00 | current role: Planner completed | files inspected since last update: draft sections in this plan file | decision/blocker: draft includes scope, owner files, regression-first plan, gates, done criteria, dirty-worktree handling, and host-only no Device/Relay Proof Profile note | next action: run Reviewer sufficiency pass.
- 2026-05-22T21:11:18+02:00 | current role: Reviewer started | files inspected since last update: draft sections in this plan file | decision/blocker: review will check mandatory sections, gate strictness, scope drift, and stale assumptions | next action: record sufficiency findings.
- 2026-05-22T21:11:51+02:00 | current role: Reviewer completed | files inspected since last update: full draft plan file | decision/blocker: sufficient with adjustment; tightened done criteria and known-failure wording so `INTRO-REL-007` cannot be marked `Covered` unless the direct test and `intro` gate pass | next action: run Arbiter classification.
- 2026-05-22T21:12:31+02:00 | current role: Arbiter started | files inspected since last update: reviewer findings and adjusted plan sections | decision/blocker: classify the reviewer adjustment and decide whether another plan patch is required | next action: write final arbiter verdict.
- 2026-05-22T21:12:49+02:00 | current role: Arbiter completed | files inspected since last update: final plan and reviewer findings | decision/blocker: no structural blockers remain; the gate strictness adjustment is already incorporated; plan is execution-ready | next action: execute `INTRO-REL-007` in a later implementation pass.

## Evidence Collector Notes

- Source matrix row `INTRO-REL-007` is still `Open` and requires proof that a passed or expired intro cannot be revived by a late stale `accept`; it also requires no B-C contact creation from that stale accept.
- Breakdown row `INTRO-REL-007` classifies the session as `needs_tests_only` / `tests-only` and names the exact scope: add explicit expired-state late-accept coverage and no-B-C-contact-created assertion for stale accept after `passed` or `expired`.
- `handle_incoming_introduction_test.dart` already has `late accept does not revive a passed intro`, but it does not assert `contactRepo.contactExists('peer-C')` remains false and has no expired-state variant.
- `accept_introduction_test.dart` already has local accept coverage for a passed intro and verifies no fan-out, but the stale inbound accept path is owned by `handleIncomingIntroduction`.
- `expire_old_introductions_use_case_test.dart` already proves startup repair for stale pending passed/expired rows does not create contacts; it does not cover a late inbound accept after terminal state.
- `handle_incoming_introduction_use_case.dart` routes terminal `passed` and `expired` response replays through `_handleTerminalResponseReplay`, returning `rejected` without calling `handleMutualAcceptance`; this is the production seam the new test should pin.
- `accept_introduction_use_case.dart` no-ops on terminal `passed` and `expired` before staging fan-out, which is adjacent evidence but not the stale inbound response seam.
- `test/shared/fakes/in_memory_introduction_repository.dart` guards status updates and overall updates so non-pending introductions cannot be overwritten by normal status mutation methods.
- `scripts/run_test_gates.sh intro` and `Test-Flight-Improv/test-gate-definitions.md` define the Intro / Reintroduction Gate and include `accept_introduction_test.dart` and `handle_incoming_introduction_test.dart`.

## real scope

This session is scoped to `INTRO-REL-007` only: prove that stale late `accept` payloads cannot revive introductions that are already `passed` or `expired`, and prove that no B-C contact is created from those stale accepts.

The intended implementation is tests-only. The primary owner is `test/features/introduction/application/handle_incoming_introduction_test.dart`, because the source row describes a stale inbound accept arriving after terminal state. Product code may be edited only if the new exact assertions fail and the failure exposes a real regression in the stale inbound response path.

The source matrix row `INTRO-REL-007` must remain `Open` during planning. It may be updated to `Covered` only after execution adds or confirms the assertions and the required gates pass.

## closure bar

Good enough for this row means a deterministic host-side test proves both terminal states:

- a `passed` introduction receives a late `accept`, returns `HandleIntroductionResult.rejected`, keeps party statuses and overall status terminal, and leaves `contactRepo.contactExists('peer-C') == false`
- an `expired` introduction receives a late `accept`, returns `HandleIntroductionResult.rejected`, keeps party statuses and overall status terminal, and leaves `contactRepo.contactExists('peer-C') == false`
- the direct touched test passes
- `./scripts/run_test_gates.sh intro` passes
- after those gates pass, the source matrix row and breakdown ledger can be updated with concrete file/test/gate evidence

## source of truth

Current code and tests are authoritative over stale prose. For this session:

- Source row: `Test-Flight-Improv/Intro-Feature/Introduction_reliability_test_matrix_TOP_15.md` row `INTRO-REL-007`
- Breakdown/session contract: `Test-Flight-Improv/Intro-Feature/Introduction_reliability_test_matrix_TOP_15-session-breakdown.md` entries for `INTRO-REL-007`
- Gate source of truth: `scripts/run_test_gates.sh`; `Test-Flight-Improv/test-gate-definitions.md` is companion documentation
- Behavior seams: `lib/features/introduction/application/handle_incoming_introduction_use_case.dart`, `lib/features/introduction/application/accept_introduction_use_case.dart`, and `test/shared/fakes/in_memory_introduction_repository.dart`
- Direct proof surface: `test/features/introduction/application/handle_incoming_introduction_test.dart`

If these disagree, current executable code/tests win, then `scripts/run_test_gates.sh`, then the active breakdown/source row.

## session classification

`implementation-ready`

Row-level execution classification remains `tests-only`: add or tighten tests first, and change product code only if the new assertions expose a real regression.

## exact problem statement

The matrix requires explicit proof that a passed or expired introduction cannot be revived by a late stale `accept`. The repo already has a passed-state late-accept handler test, but it does not assert that no B-C contact is created and it does not cover the expired terminal state.

The user-visible behavior to preserve is that a stale accept cannot create a relationship after a user has passed or after the intro has expired. A future connection must require a new valid introduction flow. Existing valid mutual-acceptance behavior, pending-response replay, pass handling, and intro send repair behavior must remain unchanged.

## files and repos to inspect next

Owner files for execution:

- `test/features/introduction/application/handle_incoming_introduction_test.dart` as the primary test owner
- `lib/features/introduction/application/handle_incoming_introduction_use_case.dart` only if the new handler assertions fail
- `test/shared/fakes/in_memory_introduction_repository.dart` only if fake behavior blocks a faithful assertion

Candidate adjacent files, inspect only if evidence demands it:

- `test/features/introduction/application/accept_introduction_test.dart` for local accept no-op coverage
- `lib/features/introduction/application/accept_introduction_use_case.dart` for local accept terminal no-op behavior
- `test/features/introduction/application/expire_old_introductions_use_case_test.dart` for startup repair no-contact precedent
- `lib/core/database/helpers/introductions_db_helpers.dart` only if a repository/DB guard regression is exposed outside the fake

## existing tests covering this area

- `handle_incoming_introduction_test.dart` has `late accept does not revive a passed intro`, asserting `HandleIntroductionResult.rejected` and unchanged passed status.
- `accept_introduction_test.dart` has `accepting a passed intro does not revive terminal state or send fan-out`, asserting local accept on a passed intro returns the passed row and does not deliver/store outbound work.
- `expire_old_introductions_use_case_test.dart` has no-contact startup repair coverage for stale pending rows that derive to `passed` or `expired`.
- The missing direct proof is the expired-state late inbound accept plus explicit `contactExists('peer-C') == false` for stale accepts after both `passed` and `expired`.

## regression/tests to add first

Add the direct host regression in `test/features/introduction/application/handle_incoming_introduction_test.dart`.

Preferred shape: convert or complement the existing `late accept does not revive a passed intro` test with two explicit cases:

- `passed`: seed `intro-terminal-passed` with `recipientStatus: passed`, `introducedStatus: accepted`, `status: passed`; assert no `peer-C` contact before delivery; deliver a late `accept`; assert rejected result, unchanged statuses, `status: passed`, and no `peer-C` contact after delivery.
- `expired`: seed `intro-terminal-expired` with an old or explicitly expired row, `status: expired`; assert no `peer-C` contact before delivery; deliver a late `accept` from one party; assert rejected result, unchanged statuses, `status: expired`, and no `peer-C` contact after delivery.

Use existing fakes and helpers in the file. Cover both recipient/introduced response branches if it stays simple; do not add harness infrastructure for this row.

## step-by-step implementation plan

1. Confirm the dirty worktree before editing and avoid reverting unrelated changes. If `handle_incoming_introduction_test.dart` already contains user changes, preserve them and make the smallest additive assertion/test edits around the existing late-accept test.
2. Add the passed-state no-contact assertion to the existing stale late-accept handler test.
3. Add an expired-state stale late-accept handler test, or a small table-driven variant if that fits the local test style without obscuring the assertions.
4. Run `flutter test test/features/introduction/application/handle_incoming_introduction_test.dart`.
5. If the direct test fails because a stale accept creates a contact or mutates terminal state, stop treating this as tests-only and fix only the stale inbound response guard in `handle_incoming_introduction_use_case.dart` or the repository/fake guard that made the proof invalid. Then rerun the direct test.
6. Run `./scripts/run_test_gates.sh intro`.
7. Only after direct test and intro gate pass, update `INTRO-REL-007` in the source matrix to `Covered` and update this breakdown ledger with exact evidence. Do not update those docs during planning.

## risks and edge cases

- A stale accept can look idempotent but still trigger `handleMutualAcceptance`; the no-contact assertion is the critical guard.
- The expired case must be explicitly terminal before delivering the accept. Do not rely on wall-clock flakiness when a direct `status: expired` seed is clearer.
- The fake repository already blocks non-pending status mutation; if the test passes only because the fake is stricter than production DB helpers, inspect DB helper guards before closure.
- Existing dirty worktree changes in introduction files may already alter behavior; execution must not revert them and must attribute any unrelated failures separately.

## exact tests and gates to run

Required direct test:

```bash
flutter test test/features/introduction/application/handle_incoming_introduction_test.dart
```

Required named gate:

```bash
./scripts/run_test_gates.sh intro
```

No iOS simulator E2E is required. No Device/Relay Proof Profile is required because this row is host-only application-state coverage: it proves terminal status/contact mutation semantics in the application handler, not device transport, relay storage, or multi-node delivery.

## known-failure interpretation

The direct touched test must pass before closure. A failure in the new stale-accept assertions is a real `INTRO-REL-007` regression until fixed or proven to be a test setup error.

For `./scripts/run_test_gates.sh intro`, pre-existing failures outside the touched stale-accept path should be recorded with exact failing test names and compared against the dirty worktree context. They still block `Covered` for this row until the intro gate is rerun and passes or the user explicitly changes the closure contract in a later instruction.

## done criteria

- `handle_incoming_introduction_test.dart` explicitly covers stale late accept after `passed` and after `expired`.
- Both terminal-state variants assert no B-C contact is created.
- Direct test command passes.
- `./scripts/run_test_gates.sh intro` passes.
- Source matrix row `INTRO-REL-007` is updated to `Covered` only after execution/gates, with concrete direct-test and intro-gate evidence.
- Breakdown artifact is updated after execution with final row disposition and evidence.
- No unrelated dirty-worktree changes are reverted.

## scope guard

Do not modify send fan-out, outbox retry, relay/inbox delivery, ML-KEM encryption, listener subscription timing, contact creation UX, or simulator E2E harnesses for this row.

Do not update `INTRO-REL-007` to `Covered` during planning. Do not close adjacent rows. Do not add broad integration infrastructure. Do not rewrite fake repositories unless the direct proof cannot be expressed faithfully. Do not change product code unless the new assertions fail and identify a real stale-accept regression.

## accepted differences / intentionally out of scope

- Device-backed proof is intentionally out of scope; the defect class is deterministic application-state mutation after terminal status.
- Relay proof is intentionally out of scope; no transport, inbox, or delivery behavior changes are required to prove this row.
- Local user accept no-op behavior in `accept_introduction_test.dart` is adjacent evidence, not the primary stale inbound response proof. It may receive a small no-contact assertion only if execution chooses to tighten adjacent coverage without broadening the scope.
- Pending-response replay cleanup and forged sender-binding are owned by `INTRO-REL-008`, `INTRO-REL-009`, and `INTRO-REL-010`, not this session.

## dependency impact

Closing `INTRO-REL-007` removes one open P0 terminal-state gap from the introduction reliability TOP 15 matrix. Later closure work can rely on the invariant that stale late accepts after `passed` or `expired` do not create B-C contacts. If the new assertions expose a product regression, later matrix closure should pause on this row until the narrow handler/repository fix and required gates pass.

## dirty-worktree handling

The worktree is already dirty, including introduction application, domain, database, and test files. Execution must:

- inspect `git status --short` before editing
- preserve all unrelated modified and untracked files
- make only the minimal row-owned test edits, plus a narrow product fix only if required by a failing assertion
- avoid formatting or rewriting unrelated files
- report any pre-existing failures separately from failures introduced by `INTRO-REL-007` edits

## Reviewer Findings

Reviewer verdict: sufficient with adjustment.

- Missing files/tests/gates: none after the plan names `handle_incoming_introduction_test.dart` as primary owner and requires `./scripts/run_test_gates.sh intro`.
- Stale or incorrect assumptions: the draft's first done-criteria wording allowed an unrelated intro-gate failure to be documented as done; this has been tightened so coverage requires the intro gate to pass unless a later user instruction changes the contract.
- Overengineering: none; the plan keeps execution to host-side handler assertions and avoids simulator, relay, and outbox work.
- Decomposition: sufficient; implementation can add the exact missing assertions without touching adjacent rows.
- Minimum needed for sufficiency: keep the direct stale-accept test and named intro gate mandatory, and leave the source row `Open` until execution evidence exists.

## Arbiter Decision

Structural blockers: none remaining.

Incremental details: none required before execution. The reviewer-identified gate wording ambiguity was patched in the plan.

Accepted differences: no Device/Relay Proof Profile and no iOS simulator E2E are required because this is host-only application-state coverage. Adjacent local accept, pending replay, forged sender, relay, and retry concerns remain intentionally out of scope for their own rows.

Final verdict: execution-ready for `INTRO-REL-007` only.

## Execution Progress

- 2026-05-22T21:14:26+02:00 | phase: before contract extraction | files inspected/touched: plan read, `git status --short`, `test/features/introduction/application/handle_incoming_introduction_test.dart` read/diff inspected | command: none | decision/blocker: beginning execution under `implementation-execution-qa-orchestrator`; worktree dirty with unrelated intro/relay changes, preserving unrelated edits | next action: extract exact scope, acceptance bar, owner files, tests, gates, non-goals, and spawn Executor if child-agent isolation is available.
- 2026-05-22T21:14:53+02:00 | phase: after contract extraction | files inspected/touched: plan contract, `test/features/introduction/application/handle_incoming_introduction_test.dart`, `lib/features/introduction/application/handle_incoming_introduction_use_case.dart`, `test/shared/fakes/in_memory_contact_repository.dart` | command: none | decision/blocker: scope is `INTRO-REL-007` tests-only; add stale late-accept coverage for `passed` and `expired` terminal rows with explicit `contactRepo.contactExists('peer-C') == false`; product code remains forbidden unless direct assertions expose a real stale inbound accept regression; required commands are `flutter test test/features/introduction/application/handle_incoming_introduction_test.dart` and `./scripts/run_test_gates.sh intro` | next action: spawn Executor child with `model=gpt-5.5` and `model_reasoning_effort=xhigh`.
- 2026-05-22T21:15:35+02:00 | phase: Executor spawn retry | files inspected/touched: plan progress only | command: `codex exec ... -a never ...` | decision/blocker: first child launch failed before materializing because this CLI rejected short approval flag `-a`; no code/test files were touched by the failed child | next action: retry Executor spawn once with `--ask-for-approval never`.
- 2026-05-22T21:16:52+02:00 | phase: Executor child before implementation | files inspected/touched: this plan, `git status --short`, `test/features/introduction/application/handle_incoming_introduction_test.dart`, `lib/features/introduction/application/handle_incoming_introduction_use_case.dart`, `test/shared/fakes/in_memory_contact_repository.dart`, `test/shared/fakes/in_memory_introduction_repository.dart` | command: `git status --short` | decision/blocker: worktree and owner test already contain unrelated edits; implementation will stay tests-only by adding no-B-C-contact assertions to the existing passed late-accept case and a neighboring expired late-accept case | next action: patch only `handle_incoming_introduction_test.dart`.
- 2026-05-22T21:18:26+02:00 | phase: Executor child after implementation | files inspected/touched: `test/features/introduction/application/handle_incoming_introduction_test.dart`, this plan | command: none | decision/blocker: tests-only edit landed; passed terminal case now asserts no `peer-C` contact before/after stale accept and uses `ownPeerId: 'peer-B'`; expired terminal case added with rejected result, unchanged terminal state, and no `peer-C` contact before/after | next action: run required direct test.
- 2026-05-22T21:18:45+02:00 | phase: before required direct test | files inspected/touched: this plan | command: `flutter test test/features/introduction/application/handle_incoming_introduction_test.dart` | decision/blocker: no blocker; direct owner suite must pass before named intro gate | next action: run direct test.
- 2026-05-22T21:19:29+02:00 | phase: after required direct test | files inspected/touched: this plan, `test/features/introduction/application/handle_incoming_introduction_test.dart` | command: `flutter test test/features/introduction/application/handle_incoming_introduction_test.dart` | decision/blocker: passed; new stale late-accept assertions did not expose a product regression, so no product code edit is permitted or needed | next action: record gate start and run `./scripts/run_test_gates.sh intro`.
- 2026-05-22T21:19:42+02:00 | phase: before required named gate | files inspected/touched: this plan | command: `./scripts/run_test_gates.sh intro` | decision/blocker: no blocker; intro gate remains required for closure | next action: run named intro gate.
- 2026-05-22T21:20:17+02:00 | phase: after required named gate | files inspected/touched: this plan | command: `./scripts/run_test_gates.sh intro` | decision/blocker: passed; intro gate completed with all tests passing, and no stale inbound accept regression was exposed | next action: record Executor completed handoff.
- 2026-05-22T21:20:17+02:00 | phase: Executor completed handoff | files inspected/touched: `test/features/introduction/application/handle_incoming_introduction_test.dart`, this plan, `git status --short` | command: `git status --short` | decision/blocker: executor scope complete; product code not touched; source matrix and session breakdown intentionally not updated per strict user scope; worktree remains dirty with unrelated pre-existing changes | next action: hand off to QA Reviewer with direct test and intro gate pass evidence.
- 2026-05-22T21:21:02+02:00 | phase: QA Reviewer spawned/running | files inspected/touched: this plan, `test/features/introduction/application/handle_incoming_introduction_test.dart` line readback | command: `codex exec ...` QA Reviewer child | decision/blocker: Executor evidence is complete; spawning separate QA Reviewer to verify scope adherence, required stale late-accept coverage, no product-code touch, and exact test/gate evidence | next action: wait for QA verdict.
- 2026-05-22T21:22:33+02:00 | phase: QA Reviewer completed | files inspected/touched: this plan, `test/features/introduction/application/handle_incoming_introduction_test.dart` lines 749-831, scoped `git status --short`/diff evidence; QA touched only this execution-progress entry | command: `flutter test test/features/introduction/application/handle_incoming_introduction_test.dart` passed with 30 tests; `./scripts/run_test_gates.sh intro` passed with 203 tests | decision/blocker: no blocking issues; scoped coverage proves stale late `accept` after `passed` and `expired` returns rejected, preserves terminal state, persists terminal state, and leaves `contactRepo.contactExists('peer-C') == false` before and after; source matrix and breakdown remain intentionally unchanged per user scope | next action: return no-blocking QA verdict.
- 2026-05-22T21:23:30+02:00 | phase: final verdict written | files inspected/touched: this plan, `git status --short` scoped to plan and owner test | command: none | decision/blocker: accepted; required direct test and named intro gate passed in Executor and QA, no blocking issues remain, product code not touched, no source matrix or breakdown update performed | next action: final response to user.
