Status: execution-ready

# INTRO-REL-006 Execution Plan

## Planning Progress

- 2026-05-22T20:52:02+0200 - Arbiter completed. Files inspected since last update: `Test-Flight-Improv/Intro-Feature/Introduction_reliability_test_matrix_TOP_15-session-INTRO-REL-006-plan.md`. Decision/blocker: no structural blockers remain; reusable plan rule is satisfied and status is `execution-ready`. Next action: execute this plan in a separate implementation pass, keeping matrix row `Open` until direct test and intro gate pass.
- 2026-05-22T20:52:02+0200 - Arbiter started. Files inspected since last update: `Test-Flight-Improv/Intro-Feature/Introduction_reliability_test_matrix_TOP_15-session-INTRO-REL-006-plan.md`. Decision/blocker: classify reviewer findings into structural blockers, incremental details, and accepted differences. Next action: finalize or return blocker.
- 2026-05-22T20:52:02+0200 - Reviewer completed. Files inspected since last update: `Test-Flight-Improv/Intro-Feature/Introduction_reliability_test_matrix_TOP_15-session-INTRO-REL-006-plan.md`. Decision/blocker: sufficient as-is; no missing required files, direct tests, named gates, dirty-worktree handling, or scope guard. Next action: run arbiter stop-rule check.
- 2026-05-22T20:51:38+0200 - Reviewer started. Files inspected since last update: `Test-Flight-Improv/Intro-Feature/Introduction_reliability_test_matrix_TOP_15-session-INTRO-REL-006-plan.md`. Decision/blocker: checking the draft for mandatory sections, direct/gate specificity, stale assumptions, and over-broad fallback paths. Next action: record sufficiency finding and required adjustments if any.
- 2026-05-22T20:49:11+0200 - Planner completed. Files inspected since last update: none. Decision/blocker: drafted a tests-only execution path with primary ownership in `handle_incoming_introduction_test.dart`, direct test plus intro gate, matrix status update deferred until execution evidence. Next action: run sufficiency review against mandatory plan sections and scope guard.

## real scope

This session owns tests-only closure for source row `INTRO-REL-006`: prove that an existing B-C contact remains after a delayed `pass` response is processed against a terminal introduction.

Primary execution target:

- `test/features/introduction/application/handle_incoming_introduction_test.dart`

Secondary/fallback target only if direct evidence during execution shows the source-row seam is better pinned there:

- `test/features/introduction/application/pass_introduction_test.dart`

Product files may be inspected but must not be changed unless the new strict assertion exposes a real regression:

- `lib/features/introduction/application/handle_incoming_introduction_use_case.dart`
- `lib/features/introduction/application/pass_introduction_use_case.dart`
- `lib/features/introduction/application/handle_mutual_acceptance_use_case.dart`

The source matrix row stays `Open` during planning. It can move to `Covered` only after execution adds the assertion and the required direct test plus intro gate pass.

## closure bar

Good enough for `INTRO-REL-006` means a host-side deterministic application test proves all of the following in the delayed-pass terminal-state path:

- The intro remains `mutualAccepted` or `alreadyConnected`.
- The existing B-C contact still exists by peer id after the late pass.
- The late pass is ignored, rejected, or consumed as stale without downgrading state.
- No production code changes are made unless the assertion fails and investigation confirms a real regression.

No Device/Relay Proof Profile is required because this is host-only application-state coverage. The breakdown explicitly says no iOS simulator E2E is required for this tests-only state-guard row.

## source of truth

Authoritative sources, in order:

- Current code and tests win over stale prose.
- `Test-Flight-Improv/Intro-Feature/Introduction_reliability_test_matrix_TOP_15.md` defines source row `INTRO-REL-006` and its current `Open` status.
- `Test-Flight-Improv/Intro-Feature/Introduction_reliability_test_matrix_TOP_15-session-breakdown.md` defines this session as tests-only closure with no iOS simulator E2E.
- `scripts/run_test_gates.sh` is the executable source of truth for named gates.
- `Test-Flight-Improv/test-gate-definitions.md` documents the intro gate; if it disagrees with the script, the script wins.

## session classification

`implementation-ready`

This is implementation-ready as a tests-only gap-closure session. Product implementation is conditionally allowed only if the new strict assertion exposes a real regression.

## exact problem statement

The source matrix requires proof that once B and C are connected through a mutual or already-connected introduction, a delayed `pass` response cannot downgrade the terminal intro state or remove the B-C contact. Existing tests cover terminal status monotonicity, but the strict source-matrix assertion that an existing B-C contact remains after the late pass is still missing.

User-visible behavior to protect: an established introduction-created contact must not disappear or regress because a stale pass arrives late.

Behavior that must stay unchanged: terminal intro states remain monotonic, stale terminal responses remain no-op/rejected as currently designed, and the intro gate membership does not change.

## files and repos to inspect next

Execution should inspect or touch only these files:

- `test/features/introduction/application/handle_incoming_introduction_test.dart` - primary test file to update.
- `test/features/introduction/application/pass_introduction_test.dart` - fallback only if the executor chooses the local-pass seam instead of incoming replay.
- `test/shared/fakes/in_memory_contact_repository.dart` - confirm `contactExists` and test-contact helpers.
- `lib/features/introduction/application/handle_incoming_introduction_use_case.dart` - inspect only unless the assertion fails.
- `lib/features/introduction/application/pass_introduction_use_case.dart` - inspect only unless the fallback path fails.
- `lib/features/introduction/application/handle_mutual_acceptance_use_case.dart` - inspect only if contact survival or idempotence fails.
- `scripts/run_test_gates.sh` and `Test-Flight-Improv/test-gate-definitions.md` - verify the intro gate command and membership if needed.
- `Test-Flight-Improv/Intro-Feature/Introduction_reliability_test_matrix_TOP_15.md` - update row `INTRO-REL-006` to `Covered` only after execution and gates.
- `Test-Flight-Improv/Intro-Feature/Introduction_reliability_test_matrix_TOP_15-session-breakdown.md` - update this session disposition only after execution and gates.
- `Test-Flight-Improv/Intro-Feature/test-inventory.md` - update only if execution changes documented intro-gate inventory expectations; this is not expected if the assertion is added to an existing intro-gate file.

## existing tests covering this area

- `handle_incoming_introduction_test.dart` already has `late pass does not downgrade a mutually accepted intro`, which seeds a `mutualAccepted` intro and asserts recipient, introduced, and overall status stay terminal after an incoming `pass`.
- `pass_introduction_test.dart` already has `passing a mutually accepted intro does not downgrade terminal state`, which asserts local pass is a no-op for terminal state and does not send outbound pass payloads.
- `pass_introduction_test.dart` also checks contact count does not change for a normal pass path, but that is weaker than the strict B-C peer-id survival assertion needed for this row.
- `handle_incoming_introduction_test.dart` has `deferred response replay does not downgrade an alreadyConnected intro`, which covers already-connected replay monotonicity but is not the exact late-pass contact-remains assertion.
- The intro gate already includes both likely direct test files, so no named-gate widening is needed.

## regression/tests to add first

Add the strict assertion in the existing `handle_incoming_introduction_test.dart` test named `late pass does not downgrade a mutually accepted intro`:

- Seed `peer-C` as an existing contact before delivering the delayed `pass`.
- Assert `await contactRepo.contactExists('peer-C')` is `true` before the delayed pass, so the test proves survival rather than creation.
- After `handleIncomingIntroduction(...)`, assert `await contactRepo.contactExists('peer-C')` is still `true`.
- Keep the existing terminal status assertions.

If execution evidence shows the handler test cannot express the row cleanly, use `pass_introduction_test.dart` only as a fallback and add the same peer-id contact survival proof there. Do not add both paths unless one assertion cannot close the matrix row.

## step-by-step implementation plan

1. Re-check the dirty worktree with `git status --short` and inspect diffs for the intended test file before editing. Do not revert unrelated changes.
2. In `handle_incoming_introduction_test.dart`, update the existing `late pass does not downgrade a mutually accepted intro` test with a `ContactModel` for `peer-C` using the local test style.
3. Add a precondition assertion that `peer-C` exists before the late pass is delivered.
4. Add the postcondition assertion that `peer-C` still exists after the late pass result/status assertions.
5. Run the direct touched test. If it passes, do not change product code.
6. If the direct test fails specifically because the late pass deletes, replaces incorrectly, or fails to preserve the existing contact, inspect the relevant application use case and fake repository, then make the smallest product fix needed. Product edits are allowed only for that confirmed regression.
7. Run `./scripts/run_test_gates.sh intro`.
8. After the direct test and intro gate pass, update the source matrix row `INTRO-REL-006` from `Open` to `Covered`, update this breakdown session disposition, and update `test-inventory.md` only if required by the repository's inventory convention.

## risks and edge cases

- The worktree is already dirty across introduction, database, relay, and test files. Execution must preserve unrelated changes and avoid broad formatting or cleanup.
- A contact-count assertion is not strict enough because it can miss delete-and-recreate behavior or the wrong peer. Assert `contactExists('peer-C')`.
- The source row mentions `mutualAccepted` or `alreadyConnected`; the existing mutual-accepted late-pass test is the smallest exact incoming-pass seam. Add an already-connected sibling only if execution concludes the source row cannot be closed without that variant.
- If the direct test or intro gate is already red because of unrelated dirty-worktree changes, capture the failing tests and do not mark the matrix row `Covered`.
- Do not treat simulator, relay, or real network absence as a blocker. This row is closed by deterministic host application-state coverage.

## exact tests and gates to run

Required direct test for the primary path:

```bash
flutter test test/features/introduction/application/handle_incoming_introduction_test.dart
```

Fallback direct test only if `pass_introduction_test.dart` is touched:

```bash
flutter test test/features/introduction/application/pass_introduction_test.dart
```

Required named gate:

```bash
./scripts/run_test_gates.sh intro
```

No iOS simulator E2E, relay fixture, or Device/Relay Proof Profile is required for this session.

## known-failure interpretation

No known failure is accepted for this plan. If the direct test or intro gate fails before the assertion is added, record that as pre-existing dirty-worktree evidence and do not claim new coverage. If failures appear only after the assertion is added, classify them as session-owned until proven unrelated. The source matrix row remains `Open` unless the direct touched test and `./scripts/run_test_gates.sh intro` pass or the team explicitly accepts a documented pre-existing gate failure outside this row.

## done criteria

- The strict B-C contact-remains assertion exists in a direct introduction application test.
- The assertion proves `peer-C` existed before the delayed pass and still exists afterward.
- Terminal status assertions for `mutualAccepted` or `alreadyConnected` remain in place.
- No product code changed unless the assertion exposed a real regression.
- The direct touched test passes.
- `./scripts/run_test_gates.sh intro` passes.
- Only after those gates pass, `INTRO-REL-006` is marked `Covered` in the source matrix and the breakdown disposition is updated.
- The dirty worktree remains respected: unrelated modified or untracked files are not reverted or folded into this session.

## scope guard

Non-goals:

- Do not implement new introduction delivery, retry, relay, inbox, pending-response, DB migration, UI, notification, or simulator behavior.
- Do not widen named gates or move test files between gate buckets.
- Do not add iOS simulator E2E or real-device proof for this row.
- Do not update matrix status during planning.
- Do not refactor introduction models, repositories, contact repositories, or terminal-state derivation as part of the tests-only path.

Overengineering for this session would include adding a new fake network scenario, parameterizing the whole matrix row family, rewriting terminal-state guards, or adding new architecture around contact retention when a single peer-id survival assertion closes the stated gap.

## accepted differences / intentionally out of scope

- The source matrix marks 3-party E2E as required in the generic row, but the session breakdown narrows `INTRO-REL-006` to host-only tests-only closure. This plan accepts that narrower proof because the behavior is terminal application state, not transport reachability.
- `alreadyConnected` late-pass parity is intentionally not required unless the executor finds the mutual-accepted late-pass assertion insufficient for matrix closure. Existing tests already cover already-connected replay monotonicity.
- Device/Relay Proof Profile is intentionally out of scope because no transport or relay behavior changes are planned.

## dependency impact

Closing this plan unblocks the `INTRO-REL-006` row in the TOP 15 introduction reliability matrix and reduces the remaining tests-only closure set. If the new assertion exposes a product regression, downstream matrix updates must pause until the product fix and required gates pass. If the intro gate is red for unrelated dirty-worktree reasons, keep the row open and carry the evidence into the execution report rather than marking closure prematurely.

## owner files

Planning artifact owned now:

- `Test-Flight-Improv/Intro-Feature/Introduction_reliability_test_matrix_TOP_15-session-INTRO-REL-006-plan.md`

Execution-owned files:

- `test/features/introduction/application/handle_incoming_introduction_test.dart`
- `test/features/introduction/application/pass_introduction_test.dart` only if fallback is used
- `Test-Flight-Improv/Intro-Feature/Introduction_reliability_test_matrix_TOP_15.md` only after gates pass
- `Test-Flight-Improv/Intro-Feature/Introduction_reliability_test_matrix_TOP_15-session-breakdown.md` only after gates pass
- `Test-Flight-Improv/Intro-Feature/test-inventory.md` only if inventory classification needs a note

Inspect-only unless a real regression is proven:

- `lib/features/introduction/application/handle_incoming_introduction_use_case.dart`
- `lib/features/introduction/application/pass_introduction_use_case.dart`
- `lib/features/introduction/application/handle_mutual_acceptance_use_case.dart`
- `test/shared/fakes/in_memory_contact_repository.dart`

## dirty-worktree handling

The repo has a dirty worktree with many modified and untracked files outside this plan. Execution must:

- Run `git status --short` before editing.
- Inspect `git diff -- <file>` for any file it intends to touch.
- Preserve unrelated user changes.
- Avoid formatting or cleanup in unrelated files.
- Report any pre-existing failing tests separately from failures caused by this session's assertion.

## reviewer pass

Verdict: sufficient as-is.

Sufficiency answers:

- The plan is sufficient as-is for `INTRO-REL-006`.
- Missing files, tests, regressions, or gates: none. The primary direct test file, fallback direct test file, required `./scripts/run_test_gates.sh intro`, matrix update timing, and dirty-worktree handling are explicit.
- Stale or incorrect assumptions: none found. The plan treats current code/tests as authoritative and keeps the source matrix row `Open` until execution/gates.
- Overengineering: none required by the plan. It explicitly blocks simulator E2E, relay proof, gate widening, DB migration, and product refactors for the tests-only path.
- Decomposition: narrow enough for implementation. It directs one peer-id contact-survival assertion in an existing test and stops unless that assertion exposes a real regression.
- Minimum needed to make the plan sufficient: already present.

## arbiter decision

Structural blockers: none.

Incremental details intentionally deferred:

- Add an `alreadyConnected` late-pass sibling only if the executor determines the mutual-accepted late-pass assertion cannot close the source row. The current plan does not require that extra test.
- Update `test-inventory.md` only if execution changes inventory expectations; adding an assertion to an existing intro-gate file likely does not require it.

Accepted differences intentionally left unchanged:

- No Device/Relay Proof Profile and no iOS simulator E2E are required because this is host-only application-state coverage.
- The source matrix row remains `Open` during planning and moves to `Covered` only after execution and gates.

Final reusable verdict: execution-safe for `INTRO-REL-006`.

## Execution Progress

- 2026-05-22T21:01:38+0200 - Final verdict preparing. Files inspected or touched: `Test-Flight-Improv/Intro-Feature/Introduction_reliability_test_matrix_TOP_15-session-INTRO-REL-006-plan.md`, `test/features/introduction/application/handle_incoming_introduction_test.dart`. Decision/blocker: spawned Executor and spawned QA completed; QA found no blocking issues under the user override; direct touched test passed; intro gate and closure artifacts remain deferred by override. Next action: write final verdict.
- 2026-05-22T21:01:38+0200 - Final verdict written. Files inspected or touched: `Test-Flight-Improv/Intro-Feature/Introduction_reliability_test_matrix_TOP_15-session-INTRO-REL-006-plan.md`. Decision/blocker: accepted_with_explicit_follow_up under the user override; no product code changed; non-blocking deferred items are full intro gate plus source matrix/session-breakdown closure. Next action: return concise execution verdict.
- 2026-05-22T21:00:34+0200 - QA Reviewer completed. Files inspected or touched: `Test-Flight-Improv/Intro-Feature/Introduction_reliability_test_matrix_TOP_15-session-INTRO-REL-006-plan.md`, `test/features/introduction/application/handle_incoming_introduction_test.dart`, `test/shared/fakes/in_memory_contact_repository.dart`, `lib/features/introduction/application/handle_incoming_introduction_use_case.dart`, `lib/features/introduction/application/handle_mutual_acceptance_use_case.dart`; source matrix, session breakdown, and inventory were checked only for no required update under the user override. Command not run: direct test was not rerun because executor already recorded exact passing evidence, `flutter test test/features/introduction/application/handle_incoming_introduction_test.dart` exited 0 with `00:00 +29: All tests passed!`; intro gate intentionally not run. Decision/blocker: accepted under the user override; no blocking issues found. Next action: report QA verdict with non-blocking note that full intro gate and source-matrix closure remain deferred by override.
- 2026-05-22T20:58:59+0200 - QA Reviewer started. Files inspected or touched: `Test-Flight-Improv/Intro-Feature/Introduction_reliability_test_matrix_TOP_15-session-INTRO-REL-006-plan.md`, `/Users/I560101/.codex/skills/implementation-execution-qa-orchestrator/SKILL.md`. Command result: `git status --short` confirms a dirty worktree with unrelated intro/relay/database changes plus the target test diff; no intro gate will be run under the user override. Decision/blocker: begin strict sufficiency review of scope, assertion behavior, product-code non-touch, direct-test evidence, and override compliance. Next action: inspect the target test diff and touched-file history before final QA verdict.
- 2026-05-22T20:58:11+0200 - QA Reviewer spawning. Files inspected or touched: `Test-Flight-Improv/Intro-Feature/Introduction_reliability_test_matrix_TOP_15-session-INTRO-REL-006-plan.md`, `test/features/introduction/application/handle_incoming_introduction_test.dart`. Command currently running: `codex exec -m gpt-5.5 -c model_reasoning_effort="xhigh" ...`. Decision/blocker: Executor completed with direct-test pass evidence; QA will review scope, assertion sufficiency, and user override compliance. Next action: QA Reviewer runs separately and records blocking/non-blocking findings.
- 2026-05-22T20:57:21+0200 - Direct test completed. Files inspected or touched: `test/features/introduction/application/handle_incoming_introduction_test.dart`. Command result: `flutter test test/features/introduction/application/handle_incoming_introduction_test.dart` exited 0 with `00:00 +29: All tests passed!`. Decision/blocker: the new B-C contact survival assertion passed; no product regression was exposed and no product code was touched. Next action: record intro-gate disposition under the user override.
- 2026-05-22T20:57:22+0200 - Intro gate skipped. Files inspected or touched: none. Command not run: `./scripts/run_test_gates.sh intro`. Decision/blocker: user override says not to run the full intro gate unless cheap and clearly within this session; after the required direct test, the full intro gate is broader than this tests-only assertion pass and the worktree contains unrelated dirty intro/relay changes that could confound gate attribution. Next action: leave source matrix, session breakdown, and test inventory unchanged for later closure.
- 2026-05-22T20:57:23+0200 - Executor pass completed. Files inspected or touched: `Test-Flight-Improv/Intro-Feature/Introduction_reliability_test_matrix_TOP_15-session-INTRO-REL-006-plan.md`, `test/features/introduction/application/handle_incoming_introduction_test.dart`, `test/shared/fakes/in_memory_contact_repository.dart`. Decision/blocker: implementation-owned test assertion is landed and directly verified; no fallback file, product file, source matrix, session breakdown, or test inventory was touched. Next action: hand off concise Executor summary without performing QA Reviewer duties.
- 2026-05-22T20:56:20+0200 - Executor implementation completed. Files inspected or touched: `test/features/introduction/application/handle_incoming_introduction_test.dart`. Decision/blocker: added an existing `peer-C` contact seed plus pre-pass and post-pass `contactExists('peer-C')` assertions in `late pass does not downgrade a mutually accepted intro`; terminal status assertions remain in place; no product code touched. Next action: run the required direct touched test.
- 2026-05-22T20:56:21+0200 - Direct test starting. Files inspected or touched: `Test-Flight-Improv/Intro-Feature/Introduction_reliability_test_matrix_TOP_15-session-INTRO-REL-006-plan.md`, `test/features/introduction/application/handle_incoming_introduction_test.dart`. Command currently running: `flutter test test/features/introduction/application/handle_incoming_introduction_test.dart`. Decision/blocker: direct test is required by the user override and is the only gate planned for this Executor pass; full intro gate will be skipped unless the direct test proves cheap room remains. Next action: record exact direct-test result.
- 2026-05-22T20:55:37+0200 - Executor implementation starting. Files inspected or touched: `Test-Flight-Improv/Intro-Feature/Introduction_reliability_test_matrix_TOP_15-session-INTRO-REL-006-plan.md`, `test/features/introduction/application/handle_incoming_introduction_test.dart`, `test/shared/fakes/in_memory_contact_repository.dart`. Command result: `git status --short` shows a dirty worktree with unrelated intro/relay changes and an existing diff in the owned target file; `git diff -- test/features/introduction/application/handle_incoming_introduction_test.dart` inspected before test edits. Decision/blocker: preserve existing target-file changes and add only the B-C contact survival assertion to the existing late-pass terminal-state test. Next action: patch `late pass does not downgrade a mutually accepted intro`.
- 2026-05-22T20:53:50+0200 - Contract extraction starting. Files inspected or touched: `Test-Flight-Improv/Intro-Feature/Introduction_reliability_test_matrix_TOP_15-session-INTRO-REL-006-plan.md`, `/Users/I560101/.codex/skills/implementation-execution-qa-orchestrator/SKILL.md`. Decision/blocker: execute this session with spawned Executor/QA isolation; user override keeps source matrix and breakdown updates out of this pass and requires at minimum `flutter test test/features/introduction/application/handle_incoming_introduction_test.dart`. Next action: spawn Executor after contract extraction.
- 2026-05-22T20:53:50+0200 - Contract extracted. Files inspected or touched: `Test-Flight-Improv/Intro-Feature/Introduction_reliability_test_matrix_TOP_15-session-INTRO-REL-006-plan.md`. Decision/blocker: tests-only scope; primary owned file is `test/features/introduction/application/handle_incoming_introduction_test.dart`; product code remains inspect-only unless the new assertion exposes a real regression; source matrix and breakdown closure are deferred. Next action: spawn Executor for implementation and direct test evidence.
- 2026-05-22T20:54:01+0200 - Executor spawning. Files inspected or touched: `Test-Flight-Improv/Intro-Feature/Introduction_reliability_test_matrix_TOP_15-session-INTRO-REL-006-plan.md`. Command currently running: `codex exec -m gpt-5.5 -c model_reasoning_effort="xhigh" ...`. Decision/blocker: none. Next action: Executor inspects dirty worktree, updates the target test, runs the direct touched test, and records evidence here.
- 2026-05-22T20:54:39+0200 - Executor spawn retry. Files inspected or touched: `Test-Flight-Improv/Intro-Feature/Introduction_reliability_test_matrix_TOP_15-session-INTRO-REL-006-plan.md`. Command result: first `codex exec` launch rejected unsupported `-a` flag before any child agent started. Decision/blocker: tooling invocation corrected; no repo files touched by a child agent. Next action: relaunch Executor with approval policy supplied via `-c approval_policy="never"`.
