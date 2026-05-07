# DIF-003 Folded Accept/Pass Group Actions Plan

Status: execution-ready

## Planning Progress

- 2026-05-06 19:34 CEST | Role: Arbiter completed | Files inspected since last update: reviewer findings and regression contract sections | Decision/blocker: structural blocker found; missing mixed-role direct coverage would make implementation unsafe against the source row | Next action: patch the plan once, then run one final reviewer and arbiter pass.
- 2026-05-06 19:35 CEST | Role: Reviewer final started | Files inspected since last update: patched closure bar, regression tests, implementation steps, and done criteria | Decision/blocker: no blocker; final reviewer will verify the structural patch is sufficient and did not broaden scope | Next action: record final sufficiency verdict.
- 2026-05-06 19:35 CEST | Role: Reviewer final completed | Files inspected since last update: patched plan sections and prior reviewer/arbiter findings | Decision/blocker: no blocker; plan is sufficient as-is after mixed-role test correction | Next action: final arbiter pass and execution-ready status if no new structural blocker appears.
- 2026-05-06 19:35 CEST | Role: Arbiter final started | Files inspected since last update: final reviewer findings and complete patched plan | Decision/blocker: no blocker; final arbiter will classify remaining items and stop if no structural blocker remains | Next action: set final verdict.
- 2026-05-06 19:35 CEST | Role: Arbiter final completed | Files inspected since last update: final reviewer findings, mandatory sections, test contract, scope guard, and closure bar | Decision/blocker: no blocker; no structural blockers remain and plan is execution-ready | Next action: stop planning for DIF-003.

## Execution Progress

- 2026-05-06 19:42 CEST | Phase: Orchestrator contract extraction started | Files inspected/touched: `Test-Flight-Improv/Intro-Feature/folded-duplicate-introductions-tdd-plan-session-DIF-003-plan.md`, `git status --short`, `codex --help` | Command: `sed -n '1,260p' Test-Flight-Improv/Intro-Feature/folded-duplicate-introductions-tdd-plan-session-DIF-003-plan.md`; `git status --short`; `command -v codex && codex --help | sed -n '1,180p'` | Decision/blocker: local `codex exec` is available for spawned Executor/QA isolation; dirty intake matches previous-session/controller-owned state | Next action: extract scope, closure bar, tests, gates, known failures, done criteria, and scope guard before coding.
- 2026-05-06 19:42 CEST | Phase: Orchestrator contract extracted | Files inspected/touched: `Test-Flight-Improv/Intro-Feature/folded-duplicate-introductions-tdd-plan-session-DIF-003-plan.md` | Command: none | Decision/blocker: contract is concrete: add RED folded response tests first, implement only application-layer folded accept/pass wrapper over existing single-intro paths, run required direct tests, and update only DIF-003 source row if closure evidence is green; intro gate is optional integrated-session evidence, not a required DIF-003 closure gate | Next action: spawn Executor with the bounded DIF-003 contract.
- 2026-05-06 19:43 CEST | Phase: Executor spawned/running | Files inspected/touched: `Test-Flight-Improv/Intro-Feature/folded-duplicate-introductions-tdd-plan-session-DIF-003-plan.md` | Command: `codex exec -m gpt-5.5 -c model_reasoning_effort=xhigh -C /Users/I560101/Project-Sat/mknoon-2/flutter_app --dangerously-bypass-approvals-and-sandbox -` | Decision/blocker: spawned Executor requested with model `gpt-5.5` and reasoning effort `xhigh`; it owns RED test addition, product implementation, required direct tests, and green evidence capture | Next action: bounded wait for Executor result, then spawn separate QA Reviewer.
- 2026-05-06 19:44 CEST | Phase: Executor inspection started | Files inspected/touched: `Test-Flight-Improv/Intro-Feature/folded-duplicate-introductions-tdd-plan-session-DIF-003-plan.md` | Command: `sed -n '1,260p' Test-Flight-Improv/Intro-Feature/folded-duplicate-introductions-tdd-plan-session-DIF-003-plan.md` | Decision/blocker: executor scope confirmed as DIF-003 only; no UI, simulator, feed/orbit, schema, or PR work | Next action: inspect owner files and dirty status before adding RED tests.
- 2026-05-06 19:45 CEST | Phase: Executor owner files inspected | Files inspected/touched: `git status --short`, `lib/features/introduction/application/accept_introduction_use_case.dart`, `lib/features/introduction/application/pass_introduction_use_case.dart`, `lib/features/introduction/application/load_introductions_use_case.dart`, `lib/features/introduction/domain/models/introduction_model.dart`, `lib/features/introduction/domain/repositories/introduction_repository.dart`, `test/shared/fakes/in_memory_introduction_repository.dart`, `test/shared/fakes/in_memory_contact_repository.dart`, `test/shared/fakes/fake_p2p_network.dart`, `test/shared/fakes/fake_p2p_service_integration.dart`, `test/core/bridge/fake_bridge.dart`, existing accept/pass tests | Command: `git status --short`; `sed`/`rg` owner reads | Decision/blocker: existing single-intro paths already own role checks, ML-KEM mismatch, status mutation, and two outbound sends; folded projection supplies ordered pending ids; no presentation or schema changes needed | Next action: add RED folded response use-case tests.
- 2026-05-06 19:48 CEST | Phase: RED test starts | Files inspected/touched: `test/features/introduction/application/folded_introduction_response_use_case_test.dart`, plan progress | Command: `flutter test test/features/introduction/application/folded_introduction_response_use_case_test.dart` | Decision/blocker: RED test file added first and formatted; expected failure is missing folded use-case API/symbols | Next action: run RED and verify failure shape before product implementation.
- 2026-05-06 19:48 CEST | Phase: RED test finished | Files inspected/touched: `test/features/introduction/application/folded_introduction_response_use_case_test.dart` | Command: `flutter test test/features/introduction/application/folded_introduction_response_use_case_test.dart` | Decision/blocker: expected RED confirmed: missing `folded_introduction_response_use_case.dart`, `acceptFoldedIntroduction`, `passFoldedIntroduction`, and `FoldedIntroductionActionOutcome`; no unrelated setup failure observed | Next action: implement the smallest application-layer folded wrapper.
- 2026-05-06 19:49 CEST | Phase: Implementation starts | Files inspected/touched: `lib/features/introduction/application/folded_introduction_response_use_case.dart` (new), `test/features/introduction/application/folded_introduction_response_use_case_test.dart`, plan progress | Command: none | Decision/blocker: product edit limited to new application use-case wrapper; no single-intro, projection, repository, presentation, or schema changes planned | Next action: add result model and folded accept/pass iterator over current pending ids.
- 2026-05-06 19:50 CEST | Phase: Implementation finished | Files inspected/touched: `lib/features/introduction/application/folded_introduction_response_use_case.dart`, `test/features/introduction/application/folded_introduction_response_use_case_test.dart` | Command: `dart format lib/features/introduction/application/folded_introduction_response_use_case.dart test/features/introduction/application/folded_introduction_response_use_case_test.dart` | Decision/blocker: folded wrapper added with per-id applied/skippedNotPending/failed outcomes, stale current-pending reload checks, and existing single-intro accept/pass calls; accept passes `messageRepo`; no projection or UI changes made | Next action: run required direct tests, starting with the new folded response suite.
- 2026-05-06 19:50 CEST | Phase: Direct test starts | Files inspected/touched: folded response use-case and direct test | Command: `flutter test test/features/introduction/application/folded_introduction_response_use_case_test.dart` | Decision/blocker: validating new folded API against mixed-role apply, stale duplicate skip, non-party failure, and ML-KEM mismatch failure coverage | Next action: inspect result and fix only DIF-003-owned issues if needed.
- 2026-05-06 19:50 CEST | Phase: Direct test finished | Files inspected/touched: folded response use-case and direct test | Command: `flutter test test/features/introduction/application/folded_introduction_response_use_case_test.dart` | Decision/blocker: GREEN, `+6: All tests passed`; folded accept/pass coverage satisfied | Next action: run existing single-intro accept test.
- 2026-05-06 19:51 CEST | Phase: Direct test starts | Files inspected/touched: `test/features/introduction/application/accept_introduction_test.dart`, folded wrapper context | Command: `flutter test test/features/introduction/application/accept_introduction_test.dart` | Decision/blocker: validating existing single-intro accept behavior remains unchanged | Next action: inspect result, then run pass suite.
- 2026-05-06 19:51 CEST | Phase: Direct test finished | Files inspected/touched: `test/features/introduction/application/accept_introduction_test.dart` | Command: `flutter test test/features/introduction/application/accept_introduction_test.dart` | Decision/blocker: GREEN, `+14: All tests passed`; existing accept behavior remains green | Next action: run existing single-intro pass test.
- 2026-05-06 19:51 CEST | Phase: Direct test starts | Files inspected/touched: `test/features/introduction/application/pass_introduction_test.dart`, folded wrapper context | Command: `flutter test test/features/introduction/application/pass_introduction_test.dart` | Decision/blocker: validating existing single-intro pass behavior remains unchanged | Next action: inspect result, then run mutual acceptance suite.
- 2026-05-06 19:52 CEST | Phase: Direct test finished | Files inspected/touched: `test/features/introduction/application/pass_introduction_test.dart` | Command: `flutter test test/features/introduction/application/pass_introduction_test.dart` | Decision/blocker: GREEN, `+9: All tests passed`; existing pass behavior remains green | Next action: run mutual acceptance direct test.
- 2026-05-06 19:52 CEST | Phase: Direct test starts | Files inspected/touched: `test/features/introduction/application/mutual_acceptance_test.dart`, folded wrapper context | Command: `flutter test test/features/introduction/application/mutual_acceptance_test.dart` | Decision/blocker: validating mutual-acceptance side effects remain on existing accept path | Next action: inspect result, then update source matrix if all required direct tests are green.
- 2026-05-06 19:52 CEST | Phase: Direct test finished | Files inspected/touched: `test/features/introduction/application/mutual_acceptance_test.dart` | Command: `flutter test test/features/introduction/application/mutual_acceptance_test.dart` | Decision/blocker: GREEN, `+17: All tests passed`; all required DIF-003 direct tests are green | Next action: update source matrix row `DIF-003` with RED/GREEN evidence.
- 2026-05-06 19:53 CEST | Phase: Direct test starts | Files inspected/touched: `test/features/introduction/application/folded_introduction_response_use_case_test.dart`, source matrix row `DIF-003` | Command: `flutter test test/features/introduction/application/folded_introduction_response_use_case_test.dart` | Decision/blocker: tightened ML-KEM coverage to partial folded result with one failed mismatched id and one applied id; rerunning folded suite after test-only refinement | Next action: update final evidence if green.
- 2026-05-06 19:54 CEST | Phase: Executor closed/controller verification recovery started | Files inspected/touched: `test/features/introduction/application/folded_introduction_response_use_case_test.dart`, `Test-Flight-Improv/Intro-Feature/folded-duplicate-introductions-tdd-plan.md`, process table | Command: `kill 66664 66665 || true`; `ps -Ao pid,etime,command | rg "codex exec -m gpt-5.5|flutter test" | head -80` | Decision/blocker: spawned Executor produced coherent DIF-003 code/test/docs and required direct-test evidence but did not return a final summary; controller stopped the stale child and verified the final tightened folded test file locally before QA | Next action: record verification result and spawn separate QA Reviewer.
- 2026-05-06 19:55 CEST | Phase: Controller direct verification finished | Files inspected/touched: final folded wrapper and folded response test | Command: `flutter test test/features/introduction/application/folded_introduction_response_use_case_test.dart` | Decision/blocker: GREEN, `+6: All tests passed`; final tightened ML-KEM mixed applied/failed folded batch coverage is current; existing accept/pass/mutual tests remained green after unchanged production wrapper (`+14`, `+9`, `+17`) | Next action: spawn QA Reviewer for scope, behavior, test, and closure sufficiency review.
- 2026-05-06 19:55 CEST | Phase: QA Reviewer spawned/running | Files inspected/touched: `Test-Flight-Improv/Intro-Feature/folded-duplicate-introductions-tdd-plan-session-DIF-003-plan.md` | Command: `codex exec -m gpt-5.5 -c model_reasoning_effort=xhigh -C /Users/I560101/Project-Sat/mknoon-2/flutter_app --dangerously-bypass-approvals-and-sandbox -` | Decision/blocker: separate QA Reviewer requested with model `gpt-5.5` and reasoning effort `xhigh`; QA must not edit code and must classify blocking versus non-blocking findings | Next action: wait for QA result, then write final execution verdict.
- 2026-05-06 19:58 CEST | Phase: QA Reviewer completed | Files inspected/touched: `lib/features/introduction/application/folded_introduction_response_use_case.dart`, `test/features/introduction/application/folded_introduction_response_use_case_test.dart`, `Test-Flight-Improv/Intro-Feature/folded-duplicate-introductions-tdd-plan.md`, plan evidence | Command: QA reran `flutter test test/features/introduction/application/folded_introduction_response_use_case_test.dart` | Decision/blocker: QA found no blocking issues and no DIF-003 non-blocking follow-ups; recommendation `accepted`; QA folded suite rerun passed `+6` | Next action: write final accepted execution verdict.
- 2026-05-06 19:58 CEST | Phase: Final verdict written | Files inspected/touched: `Test-Flight-Improv/Intro-Feature/folded-duplicate-introductions-tdd-plan-session-DIF-003-plan.md`, `git status --short`, process table | Command: `git status --short -- Test-Flight-Improv/Intro-Feature/folded-duplicate-introductions-tdd-plan-session-DIF-003-plan.md Test-Flight-Improv/Intro-Feature/folded-duplicate-introductions-tdd-plan.md lib/features/introduction/application/folded_introduction_response_use_case.dart test/features/introduction/application/folded_introduction_response_use_case_test.dart`; `ps -Ao pid,etime,command | rg "codex exec -m gpt-5.5|flutter test" | head -40` | Decision/blocker: final verdict `accepted`; no child agents or test processes remain; source row `DIF-003` is closed with direct evidence | Next action: return final status to pipeline controller.

## Execution Verdict

Final verdict: `accepted`

Spawned-agent isolation used: yes. Executor and QA Reviewer were both spawned with model `gpt-5.5` and reasoning effort `xhigh`.

Local sequential fallback used: no. Controller-side verification recovery was used after the Executor produced coherent artifacts and direct evidence but did not return a final summary; the final tightened folded suite was rerun before QA.

Files changed for `DIF-003`:

- `lib/features/introduction/application/folded_introduction_response_use_case.dart`
- `test/features/introduction/application/folded_introduction_response_use_case_test.dart`
- `Test-Flight-Improv/Intro-Feature/folded-duplicate-introductions-tdd-plan-session-DIF-003-plan.md`
- `Test-Flight-Improv/Intro-Feature/folded-duplicate-introductions-tdd-plan.md` row `DIF-003`

Exact tests and gates run:

- RED: `flutter test test/features/introduction/application/folded_introduction_response_use_case_test.dart` failed with missing folded response API symbols before implementation.
- GREEN: `flutter test test/features/introduction/application/folded_introduction_response_use_case_test.dart` passed `+6`.
- GREEN: `flutter test test/features/introduction/application/accept_introduction_test.dart` passed `+14`.
- GREEN: `flutter test test/features/introduction/application/pass_introduction_test.dart` passed `+9`.
- GREEN: `flutter test test/features/introduction/application/mutual_acceptance_test.dart` passed `+17`.
- Controller/QA verification: `flutter test test/features/introduction/application/folded_introduction_response_use_case_test.dart` passed `+6` after final test refinement.

Conditional tests/gates not run: `load_introductions_test.dart` was not required because no folded projection/item shape changed. `./scripts/run_test_gates.sh intro` was optional integrated-session evidence for this plan, not a required `DIF-003` direct closure gate.

Blocking issues remaining: none.

Non-blocking follow-ups deferred: none for `DIF-003`; UI wiring, simulator proof, and final integrated intro closure remain separate rows.

## Session Intake

- Session: `DIF-003` - Folded accept/pass group actions
- Source proposal/matrix doc: `Test-Flight-Improv/Intro-Feature/folded-duplicate-introductions-tdd-plan.md`
- Breakdown artifact: `Test-Flight-Improv/Intro-Feature/folded-duplicate-introductions-tdd-plan-session-breakdown.md`
- Dependency state from intake: `DIF-001` accepted and source row closed; projection helper/model exists in `lib/features/introduction/application/load_introductions_use_case.dart`. `DIF-002` accepted but not a dependency for this session.
- User constraint: planning only. Do not execute implementation or tests in this session.

## Evidence Collector Findings

- Source proposal action contract says one folded row exposes one Accept/Pass decision; accept/pass apply to every underlying active pending intro in the fold where the current user's party status is still `pending`; existing single-intro accept/pass remain source of truth for role checks, key mismatch checks, outbound response delivery, status derivation, and mutual acceptance side effects (`folded-duplicate-introductions-tdd-plan.md:86`-`104`).
- Source matrix row `DIF-003` is still `Open` and requires tests for folded accept/pass over two pending intro ids, both party-status updates, outbound response calls through existing single-intro paths, duplicate taps not double-applying, and non-party/key-mismatch failures not being hidden (`folded-duplicate-introductions-tdd-plan.md:158`).
- Breakdown ledger marks `DIF-001` and `DIF-002` accepted, while `DIF-003` remains pending and depends only on `DIF-001` (`folded-duplicate-introductions-tdd-plan-session-breakdown.md:191`-`193`).
- Breakdown entry classifies `DIF-003` as `implementation-ready`, scopes it to folded accept/pass use cases over all current pending intro ids, and names direct application tests plus existing accept/pass/mutual tests (`folded-duplicate-introductions-tdd-plan-session-breakdown.md:316`-`346`).
- `FoldedIntroductionReviewItem` already carries `introductionIds` and `pendingCurrentViewerDecisionIntroIds`; `foldIntroductionsForReview(...)` groups active review rows by target peer and adds an id to `pendingCurrentViewerDecisionIntroIds` only when the viewer's party status is pending and the overall status is pending (`load_introductions_use_case.dart:5`-`49`, `85`-`159`).
- Existing projection tests prove two duplicate pending rows fold to one item and expose both pending ids (`load_introductions_test.dart:119`-`169`).
- `acceptIntroduction(...)` and `passIntroduction(...)` each operate on one `introductionId`, reject missing/non-party/key-mismatch cases with `null`, mutate only the caller's party status, derive overall status, send outbound payloads to introducer and other party, and return the final model (`accept_introduction_use_case.dart:17`-`165`, `pass_introduction_use_case.dart:15`-`143`).
- The single-intro use cases are the correct outbound path because they call `deliverIntroductionPayloadReliably(...)`, which stages delivery rows and sends/retries through existing delivery semantics (`introduction_outbound_delivery.dart:10`-`79`).
- Existing direct tests cover non-party rejection, outbound notification counts, and ML-KEM mismatch no-mutation/no-send behavior for single accept/pass (`accept_introduction_test.dart:172`-`227`, `450`-`480`; `pass_introduction_test.dart:124`-`162`, `288`-`318`).
- `mutual_acceptance_test.dart` pins pass status derivation and notification behavior, and accept missing-intro behavior remains `null` (`mutual_acceptance_test.dart:391`-`424`, `473`-`485`).
- `InMemoryIntroductionRepository` supports status updates, retrieval by id, pending-user retrieval, outbox inspection, and clearing; it may need small test-helper instrumentation only if folded response tests need exact mutation-call counts beyond network/outbox evidence (`in_memory_introduction_repository.dart:17`-`124`, `231`-`248`).
- Current `OrbitWired` handlers still accept/pass one raw introduction id and suppress processing by raw id; that UI wiring belongs to later `DIF-005`, not this application-layer plan (`orbit_wired.dart:814`-`878`).
- The intro gate is `./scripts/run_test_gates.sh intro`; the script's `INTRO_TESTS` list includes existing accept, mutual, pass, and other intro suites. The gate definition says the script wins on disagreement (`Test-Flight-Improv/test-gate-definitions.md:117`-`144`, `scripts/run_test_gates.sh:35`-`47`).
- Dirty worktree at intake contained user/previous-session changes in the source/breakdown docs, folded projection code/tests, Feed/Orbit files/tests, and DIF-001/DIF-002 plan files. This plan must not revert or normalize those changes; implementation should inspect current files and edit only DIF-003-owned files unless evidence requires a scoped test-helper change.

## real scope

Implement and prove application-layer folded accept/pass orchestration for one folded review item. The implementation should add `acceptFoldedIntroduction(...)` and `passFoldedIntroduction(...)` style use cases, preferably in a small new file such as `lib/features/introduction/application/folded_introduction_response_use_case.dart`, with shared internals for ordering, current-state filtering, and result collection.

The folded use cases must:

- take a folded item or its `pendingCurrentViewerDecisionIntroIds` plus the same dependencies required by the existing single-intro accept/pass use cases
- reload each underlying intro before acting
- call `acceptIntroduction(...)` or `passIntroduction(...)` for each intro that is still an active pending decision for the current viewer
- skip ids that are no longer current pending decisions for this viewer so a stale folded item or duplicate tap does not send another outbound response
- return per-underlying-intro results that distinguish applied, skipped/stale, and failed/null outcomes enough for UI reload and QA assertions

The implementation must not wire UI buttons, render folded rows, alter count behavior, change persistence schema, merge/delete raw intro rows, or rewrite existing single-intro accept/pass logic beyond any tiny shared type export needed by the new folded use case.

## closure bar

`DIF-003` is good enough when folded accept and folded pass both apply one user action across two duplicate active pending intro ids through the existing single-intro paths, update the current viewer's `recipientStatus` in one underlying intro and `introducedStatus` in another, return explicit per-id outcomes, do not double-apply on a second call with a stale folded item, and surface non-party/key-mismatch failures as failed per-id results without suppressing existing single-intro safeguards.

The closure bar is direct-test based for this session: new folded response tests are green, existing `accept_introduction_test.dart`, `pass_introduction_test.dart`, and `mutual_acceptance_test.dart` remain green, and no UI, device, relay, or simulator proof is claimed for this row.

## source of truth

- Current code and tests win over stale prose.
- `Test-Flight-Improv/Intro-Feature/folded-duplicate-introductions-tdd-plan.md` owns the `DIF-003` scenario and closure evidence requirement.
- `Test-Flight-Improv/Intro-Feature/folded-duplicate-introductions-tdd-plan-session-breakdown.md` owns the session scope, dependency, likely files, and direct-test expectations.
- `lib/features/introduction/application/load_introductions_use_case.dart` owns the folded item shape and pending id projection.
- Existing `acceptIntroduction(...)` and `passIntroduction(...)` own role checks, key mismatch checks, status derivation, outbound response delivery, and mutual-acceptance side effects.
- `scripts/run_test_gates.sh` wins over `Test-Flight-Improv/test-gate-definitions.md` if intro gate membership differs.

## session classification

`implementation-ready`

No prerequisite blocker remains: `DIF-001` is accepted, and the folded projection model exposes pending underlying intro ids.

## exact problem statement

Users reviewing duplicate introductions folded into one target row need one Accept or Pass action to affect every underlying active pending intro in that folded group. Today the application has only single-intro `acceptIntroduction(...)` and `passIntroduction(...)` functions, and the current UI call site still passes one raw `introductionId`.

The missing behavior is an application-layer group action that can be called later by UI wiring. It must improve folded duplicate review correctness while keeping single-intro behavior unchanged for non-duplicate rows and preserving existing safeguards for non-party callers, ML-KEM key mismatch, outbound delivery, and mutual acceptance.

## files and repos to inspect next

Production owner files:

- `lib/features/introduction/application/folded_introduction_response_use_case.dart` (new preferred owner)
- `lib/features/introduction/application/accept_introduction_use_case.dart`
- `lib/features/introduction/application/pass_introduction_use_case.dart`
- `lib/features/introduction/application/load_introductions_use_case.dart`
- `lib/features/introduction/domain/models/introduction_model.dart`
- `lib/features/introduction/domain/repositories/introduction_repository.dart`

Test owner files:

- `test/features/introduction/application/folded_introduction_response_use_case_test.dart` (new preferred direct test file)
- `test/features/introduction/application/accept_introduction_test.dart`
- `test/features/introduction/application/pass_introduction_test.dart`
- `test/features/introduction/application/mutual_acceptance_test.dart`
- `test/features/introduction/application/load_introductions_test.dart` only if the folded item shape or pending-id projection is changed
- `test/shared/fakes/in_memory_introduction_repository.dart` only if exact mutation or outbox assertions need a small helper
- `test/shared/fakes/in_memory_contact_repository.dart`, `test/shared/fakes/fake_p2p_network.dart`, `test/shared/fakes/fake_p2p_service_integration.dart`, and `test/core/bridge/fake_bridge.dart` as existing test harness pieces

Docs/gates:

- `Test-Flight-Improv/Intro-Feature/folded-duplicate-introductions-tdd-plan.md`
- `Test-Flight-Improv/Intro-Feature/folded-duplicate-introductions-tdd-plan-session-breakdown.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `scripts/run_test_gates.sh`

## existing tests covering this area

- `test/features/introduction/application/load_introductions_test.dart` proves folded projection groups duplicate pending target rows and exposes `pendingCurrentViewerDecisionIntroIds`.
- `test/features/introduction/application/accept_introduction_test.dart` proves single accept status changes, mutual-accepted derivation, outbound notifications, non-party no-mutation/no-send behavior, stranger encryption behavior, and ML-KEM mismatch rejection.
- `test/features/introduction/application/pass_introduction_test.dart` proves single pass status changes, outbound notifications, non-party no-mutation/no-send behavior, stranger encryption behavior, and ML-KEM mismatch rejection.
- `test/features/introduction/application/mutual_acceptance_test.dart` covers mutual acceptance and pass derivation behavior across related application paths.

Missing coverage: no test currently calls one folded accept/pass action over two underlying duplicate pending intro ids, no test proves duplicate folded action calls are idempotent at the folded boundary, and no test proves folded batch results expose null/failure outcomes from the single-intro paths.

## regression/tests to add first

Add `test/features/introduction/application/folded_introduction_response_use_case_test.dart` before implementation. The initial failing command should be:

```bash
flutter test test/features/introduction/application/folded_introduction_response_use_case_test.dart
```

Required test cases:

- folded accept over two pending intro ids from different introducers to the same target, where the current viewer is `recipientId` in one intro and `introducedId` in the other, sets the viewer's `recipientStatus` to `accepted` for the first intro and `introducedStatus` to `accepted` for the second, leaves the other party's statuses pending, returns two applied results, and produces four outbound response attempts through the existing single-intro path
- folded pass over the same mixed-role folded shape sets the viewer's `recipientStatus` to `passed` for the first intro and `introducedStatus` to `passed` for the second, derives both overall statuses to `passed`, returns two applied results, and produces four outbound response attempts through the existing single-intro path
- calling folded accept a second time with the original stale folded item returns skipped/stale outcomes and does not increase network delivery or outbox evidence
- calling folded pass a second time with the original stale folded item returns skipped/stale outcomes and does not increase network delivery or outbox evidence
- non-party folded accept and non-party folded pass return failed per-id outcomes, leave statuses pending, and produce no outbound responses
- folded accept and folded pass with a current-viewer party but an intro/contact ML-KEM mismatch return failed per-id outcomes for the mismatched id, keep that intro pending, and do not hide the underlying single-intro `null` result

Use existing fakes and fixture style from accept/pass tests. Keep the folded tests at the use-case boundary; do not add widget tests in this session.

## step-by-step implementation plan

1. Start by checking `git status --short` and inspect any currently modified owner files before editing. Preserve user/previous-session changes and avoid formatting churn outside touched files.
2. Add the failing folded response test file with helper fixtures for two introducers, one current viewer, one shared target, contacts for introducers/target, registered fake peers, and a mixed-role folded item generated through `foldIntroductionsForReview(...)`: one intro should have `recipientId == ownPeerId` and `introducedId == targetPeerId`, and the other should have `recipientId == targetPeerId` and `introducedId == ownPeerId`.
3. Run only the new folded response test command to capture the expected RED from missing folded use case symbols. Stop if the failure is unrelated to the missing API or test setup.
4. Add the folded response use case file. Prefer a small public result model:
   - `FoldedIntroductionActionOutcome.applied`
   - `FoldedIntroductionActionOutcome.skippedNotPending`
   - `FoldedIntroductionActionOutcome.failed`
   - a per-id result containing `introductionId`, `outcome`, and `IntroductionModel? introduction`
   - optional batch helpers such as `appliedResults`, `failedResults`, and `hasFailures` only if tests or future UI need them immediately
5. Implement `acceptFoldedIntroduction(...)` and `passFoldedIntroduction(...)` wrappers that share one private iterator. The iterator should use the folded item's `pendingCurrentViewerDecisionIntroIds` as candidate ids, reload each id, skip only when the current repo state proves the same viewer no longer has a pending active decision, and otherwise call the existing single-intro accept/pass function.
6. Record a `failed` result when a single-intro call returns `null`; do not convert nulls to success or silently omit them. Continue processing the remaining ids because existing single-intro behavior is non-transactional and the required output is per-underlying-intro.
7. Pass `messageRepo` through folded accept to `acceptIntroduction(...)` so mutual-acceptance side effects remain on the existing path. Folded pass should not accept a message repo unless the existing single pass API changes first.
8. Keep the duplicate-tap guard in the folded layer only. Do not change `acceptIntroduction(...)` or `passIntroduction(...)` to become globally idempotent unless the new tests prove there is no way to avoid double sends from the folded wrapper.
9. If the tests need more precise evidence than `FakeP2PNetwork` counters and outbox inspection provide, add a minimal test-only helper to `InMemoryIntroductionRepository`; do not change the repository interface for test instrumentation.
10. Run the direct test set listed below. If all direct tests pass, update the source matrix row `DIF-003` with exact RED/GREEN evidence and leave later UI/simulator rows open.
11. Stop if evidence shows the folded item cannot reliably carry the action candidate ids; in that case, revise this plan before implementing UI or repository changes.

## risks and edge cases

- Stale folded item: the UI may call with ids captured before a previous action completed; reloading each intro and checking current viewer status prevents duplicate outbound responses.
- Non-party caller: the folded layer must not classify this as a harmless skip. It must return a failed outcome, preferably by letting the single-intro path return `null`.
- ML-KEM mismatch: the folded layer must call the single-intro path for still-pending party ids so mismatch checks remain centralized and visible as failed results.
- Partial success: one id may apply while another fails. The batch result must expose this explicitly so future UI can reload and QA can assert the partial state.
- Mutual acceptance: folded accept may make one or more underlying intros mutual accepted if the other party already accepted. Existing mutual-acceptance side effects must remain owned by `acceptIntroduction(...)`.
- Ordering: processing should be deterministic using the folded item's pending id order; tests should not depend on map iteration from the repository.
- Dirty worktree: existing modified docs/code/tests are presumed user or previous-session work; implementation must not revert them.

## exact tests and gates to run

First failing direct test:

```bash
flutter test test/features/introduction/application/folded_introduction_response_use_case_test.dart
```

Required direct green tests for `DIF-003` closure:

```bash
flutter test test/features/introduction/application/folded_introduction_response_use_case_test.dart
flutter test test/features/introduction/application/accept_introduction_test.dart
flutter test test/features/introduction/application/pass_introduction_test.dart
flutter test test/features/introduction/application/mutual_acceptance_test.dart
```

Conditional direct test:

```bash
flutter test test/features/introduction/application/load_introductions_test.dart
```

Run the conditional command only if implementation changes `load_introductions_use_case.dart` or folded item shape/projection behavior.

Named gate:

```bash
./scripts/run_test_gates.sh intro
```

For this session, the named intro gate is recorded as the integrated-session gate from the breakdown, not a required `DIF-003` direct closure gate. Run it after integrated folded UI/wired sessions or earlier only if the executor deliberately widens validation and has time. No device, relay, simulator, or `INTRO_E2E_SCENARIO=folded-duplicate` proof is required for `DIF-003`.

## known-failure interpretation

- No tests were run during planning.
- The first new folded response test should fail before implementation because the folded use case API does not exist. Treat missing-symbol failure as expected RED evidence.
- If existing `accept_introduction_test.dart`, `pass_introduction_test.dart`, or `mutual_acceptance_test.dart` fail before implementation, capture the failure and do not attribute it to `DIF-003` until reproduced after the folded change.
- After implementation, any failure in the new folded response test or the required existing direct tests is a `DIF-003` blocker unless clearly proven to be pre-existing with unchanged owner files.
- If `./scripts/run_test_gates.sh intro` is run voluntarily and fails in unrelated suites while the required direct tests pass, record it as broader gate debt and do not close `DIF-007`; do not expand `DIF-003` into unrelated listener, picker, or integration fixes.

## done criteria

- New folded response use case API exists and is imported by tests.
- Folded accept applies to both underlying pending ids, proves both current-viewer party-status columns can update inside one folded group, and returns applied per-id results.
- Folded pass applies to both underlying pending ids, proves both current-viewer party-status columns can update inside one folded group, and returns applied per-id results.
- Duplicate folded accept/pass calls with stale folded items do not create additional outbound responses and return skipped/stale per-id results.
- Non-party and ML-KEM mismatch cases are visible as failed per-id results and preserve pending state/no-send behavior for failed ids.
- Existing single-intro accept/pass behavior remains unchanged and direct tests pass.
- Source matrix row `DIF-003` is updated with exact commands and evidence after implementation closure.
- No UI, simulator, database migration, or unrelated gate/documentation changes are included.

## scope guard

Non-goals:

- Do not implement `DIF-004` UI rendering.
- Do not implement `DIF-005` Orbit wired processing state, folded button wiring, reload, or badge behavior.
- Do not implement `DIF-006` simulator scenario or any device/relay proof.
- Do not change Feed or Orbit presentation files for this session.
- Do not change persisted introduction schema or add repository methods for batch mutation.
- Do not merge, delete, or rewrite raw introduction rows.
- Do not make group delete semantics folded.
- Do not refactor `acceptIntroduction(...)`, `passIntroduction(...)`, outbound delivery, or mutual acceptance beyond what is strictly needed to call them from the folded wrapper.

Overengineering markers:

- Introducing transactions, background queues, new persistence tables, or global idempotency layers for single-intro accept/pass.
- Designing UI state objects before `DIF-005`.
- Adding broad gate fixes or unrelated test inventory updates to close this row.

## accepted differences / intentionally out of scope

- Repository `countPendingIntroductions(...)` remains raw-row based; folded count was handled by `DIF-002`.
- Current `OrbitWired` raw-id processing remains unchanged until `DIF-005`.
- Single-intro accept/pass may still send again if called directly twice; `DIF-003` only owns duplicate suppression for the folded wrapper.
- Partial folded results are acceptable and intentionally non-transactional because existing single-intro paths are non-transactional and own the real side effects.
- The plan does not require device, relay, or four-identity simulator evidence; that is `DIF-006`.

## dependency impact

- `DIF-005` depends on the folded response API and per-id result shape to wire one row action, processing suppression, reload behavior, and QA assertions.
- `DIF-006` depends indirectly on `DIF-005` using this API correctly in the simulator flow.
- If implementation changes the folded result API materially, update this plan and flag `DIF-005` for review before UI wiring begins.
- `DIF-004` can proceed independently for rendering as long as it uses the same folded item shape from `DIF-001`.

## dirty-worktree handling

- Treat all existing dirty files at planning intake as user or previous-session work.
- Before implementation, run `git status --short` and inspect any dirty owner file before editing.
- Do not revert, restyle, or normalize files outside the `DIF-003` owner set.
- If an owner file has unrelated modifications, make the smallest compatible patch around current content.
- If the new folded response test file already exists when implementation starts, read it first and preserve any user-authored durable content.

## expected docs updates when done

- Update source row `DIF-003` in `Test-Flight-Improv/Intro-Feature/folded-duplicate-introductions-tdd-plan.md` from `Open` to `Closed` only after the required direct tests pass, with exact RED/GREEN evidence and commands.
- Update the session breakdown ledger/closure notes only if the execution pipeline's closure step requires it; do not mark later rows closed.
- Do not update `DIF-004`, `DIF-005`, `DIF-006`, `DIF-007`, `test-inventory.md`, or simulator docs in this session.

## Reviewer Findings

Verdict: sufficient with one adjustment.

- Missing files, tests, regressions, or gates: the draft names the right owner files and commands, but the primary folded accept/pass tests are too narrow if they use two recipient-side intro ids only. The source row asks to assert both party statuses update, so the direct regression must include one intro where the current viewer is `recipientId` and one intro where the current viewer is `introducedId`, both folded to the same target peer.
- Stale or incorrect assumptions: no stale source-of-truth conflict found. The plan correctly treats current code/tests as authoritative and keeps `./scripts/run_test_gates.sh intro` as the named gate source.
- Overengineering: no blocking overengineering found. The result model is small and justified by the per-underlying-intro result requirement.
- Decomposition sufficiency: sufficient after the mixed-role test correction. UI rendering/wiring and simulator proof stay correctly deferred.
- Minimum needed to make sufficient: patch the regression/test section and implementation fixtures so folded accept/pass prove both current-viewer role branches in one folded group.

## Arbiter Findings

- Structural blockers: the regression contract must require mixed-role folded accept/pass coverage. Without it, the plan does not fully satisfy the source row requirement to assert both party statuses update.
- Incremental details: none requiring implementation scope expansion.
- Accepted differences: direct UI duplicate-tap suppression remains deferred to `DIF-005`; `DIF-003` only proves stale folded use-case calls do not double-apply.
- Arbiter decision: patch the plan once to make mixed-role folded fixtures required, then run one final reviewer pass and one final arbiter pass.

## Final Reviewer Findings

Verdict: sufficient as-is.

- Missing files, tests, regressions, or gates: none after the mixed-role correction. The plan names the new folded response test file, existing accept/pass/mutual regression tests, conditional load projection test, and the deferred integrated intro gate.
- Stale or incorrect assumptions: none found. The plan correctly relies on `DIF-001` projection output and existing single-intro accept/pass behavior.
- Overengineering: none requiring change. The result model remains small and directly tied to the per-underlying-intro result requirement.
- Decomposition sufficiency: sufficient. Application use-case behavior is isolated from later UI, wired, simulator, and final regression sessions.
- Minimum needed to make sufficient: no further changes.

## Final Arbiter Findings

- Structural blockers: none remaining.
- Incremental details: exact helper naming may be adjusted during implementation to match Dart style, as long as the public folded accept/pass API and per-id outcomes remain clear.
- Accepted differences: UI wiring, simulator proof, final intro gate closure, and source/breakdown closure updates beyond the `DIF-003` source row remain intentionally deferred to their own sessions.
- Arbiter decision: stop. The plan is execution-ready.

## Final Planning Output

- Final verdict: execution-ready for `DIF-003`; no blocker remains.
- Final plan: implement application-layer folded accept/pass orchestration using existing single-intro paths, prove it with mixed-role folded accept/pass tests, duplicate stale-call tests, and non-party/key-mismatch failure visibility tests, then run the required direct accept/pass/mutual regression commands.
- Structural blockers remaining: none.
- Incremental details intentionally deferred: exact internal helper names and optional batch convenience getters can be chosen during implementation without changing scope.
- Accepted differences intentionally left unchanged: `DIF-004` UI rendering, `DIF-005` wired Orbit/Feed behavior, `DIF-006` simulator proof, and `DIF-007` full regression/documentation closure stay out of this session.
- Exact docs/files used as evidence: `Test-Flight-Improv/Intro-Feature/folded-duplicate-introductions-tdd-plan.md`; `Test-Flight-Improv/Intro-Feature/folded-duplicate-introductions-tdd-plan-session-breakdown.md`; `Test-Flight-Improv/test-gate-definitions.md`; `scripts/run_test_gates.sh`; `lib/features/introduction/application/load_introductions_use_case.dart`; `lib/features/introduction/application/accept_introduction_use_case.dart`; `lib/features/introduction/application/pass_introduction_use_case.dart`; `lib/features/introduction/application/introduction_outbound_delivery.dart`; `lib/features/introduction/domain/models/introduction_model.dart`; `lib/features/introduction/domain/repositories/introduction_repository.dart`; `lib/features/orbit/presentation/screens/orbit_wired.dart`; `test/features/introduction/application/load_introductions_test.dart`; `test/features/introduction/application/accept_introduction_test.dart`; `test/features/introduction/application/pass_introduction_test.dart`; `test/features/introduction/application/mutual_acceptance_test.dart`; `test/shared/fakes/in_memory_introduction_repository.dart`; `test/shared/fakes/in_memory_contact_repository.dart`; `test/shared/fakes/fake_p2p_network.dart`; `test/shared/fakes/fake_p2p_service_integration.dart`; `test/core/bridge/fake_bridge.dart`.
- Why the plan is safe to implement now: dependency `DIF-001` is accepted, the folded projection exposes the underlying pending ids needed for this action layer, direct tests are defined before implementation, existing single-intro use cases remain the source of truth for sensitive side effects, and the scope guard prevents UI, persistence, simulator, or broad gate drift.
