Status: final-program-closed

# Introduction Reliability Test Matrix TOP 15 Session Breakdown

## Decomposition Progress

| Timestamp | Phase | Inspected since last update | Decision / blocker | Next action |
|---|---|---|---|---|
| 2026-05-22 18:25 CEST | Matrix Intake completed | Read `Introduction_reliability_test_matrix_TOP_15.md`; no prior full adjacent breakdown existed. | Source has 15 P0 `INTRO-REL-*` rows, all `Open`. | Enumerate every matrix row into row-owned sessions. |
| 2026-05-22 18:27 CEST | Row Inventory completed | All 15 matrix rows `INTRO-REL-001` through `INTRO-REL-015`. | Every row is filename-safe and gets one row-owned session preserving the source row id. | Map concrete code/test evidence for each row. |
| 2026-05-22 18:27 CEST | Evidence Map started | Intro source bundle, intro test inventory, intro tests, gate docs. | Existing broad intro coverage must not satisfy rows without matching failure injection and final assertions. | Inspect likely code-entry files and direct tests per row. |
| 2026-05-22 18:31 CEST | Evidence Map completed | `send_introduction_use_case.dart`, `introduction_outbound_delivery.dart`, `accept_introduction_use_case.dart`, `handle_incoming_introduction_use_case.dart`, `introduction_listener.dart`, router/resume code, intro tests, gate docs. | Adjacent coverage exists, but each TOP 15 row remains an exact row-owned gap. | Assign row-level dispositions and pipeline classifications. |
| 2026-05-22 18:33 CEST | Row Disposition completed | Evidence map and all 15 source rows. | All rows map to `needs_code_and_tests` / `implementation-ready`; no duplicates, unsupported rows, or repo-external-only rows found. | Check dependencies and ordering. |
| 2026-05-22 18:35 CEST | Dependency Pass completed | All 15 row sessions. | No shared prerequisite, duplicate, final closure-only, or repo-external-only session is required for decomposition. | Write compatible session breakdown artifact. |
| 2026-05-22 18:35 CEST | Breakdown Write started | Required compatible-artifact sections and row-owned session entries. | Final artifact uses 15 row-owned implementation-ready sessions in source order. | Refresh target with decomposition-ready content. |
| 2026-05-22 18:44 CEST | Breakdown Write completed | Final artifact sections, matrix row inventory, evidence map, session ledger, ordered breakdown, traceability rule. | Artifact is reusable by the later rollout pipeline; no implementation was run. | Hand off for later planning/execution only. |
| 2026-05-22 20:25 CEST | Current-truth refresh completed | Rechecked current repo after INT-REL implementation pass, relay dedupe proof, durable inbox replay proof, and deployed relay v1.5.1. | Original "all 15 need code" decomposition is stale. Most rows are now covered or need only exact closure tests; `INTRO-REL-015` remains the clear code gap. | Use the refreshed disposition/evidence tables below before running any rollout pipeline. |

Rows before the `Current-truth refresh` entry are historical decomposition notes. The refreshed disposition/evidence tables below supersede them.

## Closure Progress - INTRO-REL-006

| Timestamp | Role | Inspected since last update | Decision / blocker | Next action |
|---|---|---|---|---|
| 2026-05-22 21:03 CEST | Completion Auditor started | `Introduction_reliability_test_matrix_TOP_15-session-INTRO-REL-006-plan.md`, `test/features/introduction/application/handle_incoming_introduction_test.dart`, source matrix row `INTRO-REL-006`, this breakdown. | Audit is limited to `INTRO-REL-006`; dirty worktree and unrelated intro/relay/database changes remain out of scope. | Classify landed assertion, direct test, and named gate evidence. |
| 2026-05-22 21:03 CEST | Completion Auditor completed | Execution result supplied for `INTRO-REL-006`; target test diff confirms `peer-C` contact seed plus pre/post `contactExists('peer-C')` assertions in `late pass does not downgrade a mutually accepted intro`. | Closure classification: `closed` for this row. Direct test passed with `00:00 +29: All tests passed!`; required `./scripts/run_test_gates.sh intro` passed with final `All tests passed!`; no product code is attributed to this session. | Run Closure Writer for row-scoped source-matrix and breakdown updates. |
| 2026-05-22 21:03 CEST | Closure Writer started | Closure auditor finding and row-owned plan/gate evidence. | `INTRO-REL-006` is ready to move from tests-only runnable work to accepted/covered documentation. | Update only `INTRO-REL-006` source row, disposition, session, and ledger evidence. |
| 2026-05-22 21:06 CEST | Closure Writer completed | `Introduction_reliability_test_matrix_TOP_15.md` row `INTRO-REL-006`; this breakdown's reconciliation, disposition, dependency, session ledger, and session detail entries. | Source row now reads `Covered`; breakdown marks `INTRO-REL-006` as `covered_in_repo` / `accepted/covered` with plan path, direct test evidence, intro-gate evidence, docs touched, and reopen condition. | Run Closure Reviewer against row-scoped edits. |
| 2026-05-22 21:06 CEST | Closure Reviewer completed | Row-scoped source-matrix and breakdown edits; closure docs are currently untracked, so review used direct file inspection rather than tracked diff attribution. | Accepted. The closure docs do not claim other rows are covered, do not reopen product scope, and preserve the dirty-worktree caveat. | Treat `INTRO-REL-006` as closed; continue later work only for remaining rows or a real regression. |

## Closure Progress - INTRO-REL-007

| Timestamp | Role | Inspected since last update | Decision / blocker | Next action |
|---|---|---|---|---|
| 2026-05-22 21:25 CEST | Completion Auditor started | `Introduction_reliability_test_matrix_TOP_15-session-INTRO-REL-007-plan.md`, `test/features/introduction/application/handle_incoming_introduction_test.dart`, source matrix row `INTRO-REL-007`, this breakdown, and supplied Executor/QA result. | Audit is limited to `INTRO-REL-007`; dirty worktree and unrelated intro/relay/database changes remain out of scope. | Classify tests-only coverage, direct test evidence, and required intro-gate evidence. |
| 2026-05-22 21:25 CEST | Completion Auditor completed | Execution result and target test readback for `late accept does not revive a passed intro` and `late accept does not revive an expired intro`; plan execution progress lines 198-209. | Closure classification: `closed` for this row. The passed case now asserts no `peer-C` contact before/after stale accept; the expired case asserts rejected result, unchanged terminal state, persisted terminal state, and no `peer-C` contact before/after. Direct test passed with 30 tests; required `./scripts/run_test_gates.sh intro` passed with 203 tests; no product code is attributed to this session. | Run Closure Writer for row-scoped source-matrix and breakdown updates. |
| 2026-05-22 21:25 CEST | Closure Writer started | Closure auditor finding and row-owned plan/gate evidence. | `INTRO-REL-007` is ready to move from tests-only runnable work to accepted/covered documentation. | Update only `INTRO-REL-007` source row, disposition, session, and ledger evidence. |
| 2026-05-22 21:25 CEST | Closure Writer completed | `Introduction_reliability_test_matrix_TOP_15.md` row `INTRO-REL-007`; this breakdown's reconciliation, disposition, dependency, session ledger, and session detail entries. | Source row now reads `Covered`; breakdown marks `INTRO-REL-007` as `covered_in_repo` / `accepted/covered` with plan path, direct test evidence, intro-gate evidence, docs touched, and reopen condition. | Run Closure Reviewer against row-scoped edits. |
| 2026-05-22 21:25 CEST | Closure Reviewer started | Row-scoped source-matrix and breakdown edits for `INTRO-REL-007`. | Review will check accuracy against the landed tests, absence of overclaiming, and no accidental closure of adjacent rows. | Inspect scoped diff and row readbacks. |
| 2026-05-22 21:27 CEST | Closure Reviewer completed | Source matrix row `INTRO-REL-007`; this breakdown's progress, reconciliation, disposition, dependency, session ledger, session detail, and downstream execution entries. | Accepted. The docs match the landed tests and gate evidence, remove `INTRO-REL-007` from runnable work, avoid claiming adjacent source rows are covered, and preserve the no-product-code/no-simulator accepted difference. | Treat `INTRO-REL-007` as closed; reopen only on stale late-accept terminal-state/no-contact regression or intro-gate regression. |

## Closure Progress - Evidence-Mapped Rows

| Timestamp | Role | Inspected since last update | Decision / blocker | Next action |
|---|---|---|---|---|
| 2026-05-22 21:29 CEST | Evidence verifier started | Source matrix rows `INTRO-REL-001` through `INTRO-REL-005`, `INTRO-REL-008`, `INTRO-REL-009`, and `INTRO-REL-011` through `INTRO-REL-014`; this breakdown's refreshed evidence map; cited direct tests. | These rows are `covered_in_repo`; no code execution sessions or plan files are required unless evidence regresses. | Rerun direct evidence tests, intro gate, and relay proof where required. |
| 2026-05-22 21:30 CEST | Evidence verifier completed | `test/core/database/helpers/intro_db_helpers_test.dart`, `send_introduction_test.dart`, `accept_introduction_test.dart`, `handle_incoming_introduction_test.dart`, `introduction_listener_test.dart`, `test/core/services/p2p_service_impl_test.dart`, `./scripts/run_test_gates.sh intro`, `go-relay-server` relay tests. | Direct evidence sweep passed with 154 tests; `./scripts/run_test_gates.sh intro` passed with 203 tests; `cd go-relay-server && go test .` passed with `ok github.com/mknoon/relay-server`. No repo-owned blocker remains for these evidence-mapped rows. | Update source matrix rows and breakdown ledger to accepted/covered. |
| 2026-05-22 21:31 CEST | Closure writer completed | Source matrix rows `INTRO-REL-001`-`005`, `008`, `009`, `011`-`014`; this breakdown's reconciliation and session ledger. | Source matrix rows now read `Covered` with concrete file/test/gate evidence. Breakdown removes these rows from unresolved evidence-closure work. | Continue with remaining runnable rows `INTRO-REL-010` and `INTRO-REL-015`. |

## Closure Progress - INTRO-REL-010

| Timestamp | Role | Inspected since last update | Decision / blocker | Next action |
|---|---|---|---|---|
| 2026-05-22 21:45 CEST | Completion Auditor started | `Introduction_reliability_test_matrix_TOP_15-session-INTRO-REL-010-plan.md`, `test/features/introduction/application/handle_incoming_introduction_test.dart`, source matrix row `INTRO-REL-010`, this breakdown, and supplied Executor/QA result. | Audit is limited to `INTRO-REL-010`; dirty worktree and unrelated intro/relay/database changes remain out of scope. | Classify tests-only coverage, direct test evidence, and required intro-gate evidence. |
| 2026-05-22 21:45 CEST | Completion Auditor completed | Execution result and target test readback for `valid existing intro rejects forged live accept and pass without state changes`; plan execution progress and supplied gate output. | Closure classification: `closed` for this row. The regression covers valid-existing-intro forged live `accept` and `pass` from `peer-forger` claiming `peer-C`, asserts rejected result/null model, unchanged stored intro fields, empty pending responses, and no `peer-C` contact. Direct test passed with 31 tests; required `./scripts/run_test_gates.sh intro` passed with 204 tests; no product code is attributed to this session. | Run Closure Writer for row-scoped source-matrix and breakdown updates. |
| 2026-05-22 21:45 CEST | Closure Writer started | Closure auditor finding and row-owned plan/gate evidence. | `INTRO-REL-010` is ready to move from tests-only runnable work to accepted/covered documentation. | Update only `INTRO-REL-010` source row, disposition, session, ledger evidence, and necessary aggregate remaining-session statements. |
| 2026-05-22 21:45 CEST | Closure Writer completed | `Introduction_reliability_test_matrix_TOP_15.md` row `INTRO-REL-010`; this breakdown's reconciliation, counts, disposition, dependency, session ledger, session detail, and downstream execution entries. | Source row now reads `Covered`; breakdown marks `INTRO-REL-010` as `covered_in_repo` / `accepted/covered` with plan path, direct test evidence, intro-gate evidence, docs touched, accepted host-only proof, and reopen condition. | Run Closure Reviewer against row-scoped edits. |
| 2026-05-22 21:45 CEST | Closure Reviewer started | Row-scoped source-matrix and breakdown edits for `INTRO-REL-010`. | Review will check accuracy against the landed test/gate evidence, absence of overclaiming, and no accidental closure of `INTRO-REL-015`. | Inspect scoped diff and row readbacks. |
| 2026-05-22 21:45 CEST | Closure Reviewer completed | Source matrix row `INTRO-REL-010`; this breakdown's progress, reconciliation, counts, disposition, dependency, session ledger, session detail, and downstream execution entries. | Accepted. The docs match the landed valid-existing-row forged accept/pass test and supplied gate evidence, mark only `INTRO-REL-010` as newly covered, keep `INTRO-REL-015` open, and preserve the no-product-code/no-simulator accepted difference. `git diff --check` for the touched handler test passed; doc trailing-whitespace scan found no hits. | Treat `INTRO-REL-010` as closed; reopen only on forged existing-row no-mutation/no-pending/no-contact regression or intro-gate regression. |

## Closure Progress - INTRO-REL-015

| Timestamp | Role | Inspected since last update | Decision / blocker | Next action |
|---|---|---|---|---|
| 2026-05-22 22:09 CEST | Completion Auditor started | `Introduction_reliability_test_matrix_TOP_15-session-INTRO-REL-015-plan.md`, scoped code/test diffs for `introduction_outbound_delivery.dart` and `introduction_outbound_delivery_test.dart`, source matrix row `INTRO-REL-015`, this breakdown, and `test-inventory.md`. | Audit is limited to `INTRO-REL-015`; dirty worktree and unrelated intro/relay/database changes remain out of scope. | Classify implementation, RED evidence, direct tests, named gate evidence, and conditional gate decision. |
| 2026-05-22 22:09 CEST | Completion Auditor completed | Executor and QA evidence for `INTRO-REL-015`; target test readback for direct-send and relay-probe failed-inbox retry regressions. | Closure classification: `closed` for this row. The implementation keeps inbox-success retry, then reuses the existing direct/relay delivery cascade after inbox storage fails with inbox fallback disabled for the second attempt. RED direct regression failed before implementation with `Expected: <1> Actual: <0>`; direct file passed with 11 tests; scoped `git diff --check` passed; `./scripts/run_test_gates.sh intro` passed with 204 tests. | Run Closure Writer for row-scoped source-matrix, breakdown, and inventory updates. |
| 2026-05-22 22:10 CEST | Closure Writer started | Closure auditor finding, source matrix row, breakdown reconciliation/counts/ledger/session detail/downstream execution entries, and `test-inventory.md`. | `INTRO-REL-015` is ready to move from implementation-ready to accepted/covered documentation. | Update only the named closure docs with concrete evidence and accepted differences. |
| 2026-05-22 22:10 CEST | Closure Writer completed | `Introduction_reliability_test_matrix_TOP_15.md` row `INTRO-REL-015`; this breakdown's reconciliation, counts, disposition, dependency, session ledger, session detail, and downstream execution entries; `test-inventory.md` outbound-delivery and coverage-gap entries. | Source row now reads `Covered`; breakdown marks all 15 rows as `covered_in_repo` / `accepted/covered`; inventory records the new direct/relay retry tests and the renamed resume inbox retry wording. | Run Closure Reviewer against row-scoped doc edits. |
| 2026-05-22 22:10 CEST | Closure Reviewer completed | Row-scoped doc edits for `INTRO-REL-015`; source row readback, breakdown readback, and inventory readback. | Accepted. The docs match the landed code/test evidence, preserve the conditional-gate rationale, and do not write the final whole-program verdict. Final program acceptance is ready because all 15 rows now reconcile to `accepted/covered`, but it has not been run in this closure pass. | Treat `INTRO-REL-015` as closed; run a separate final program acceptance step before writing any whole-program verdict. |
| 2026-05-22 23:05 CEST | Conditional Gate Addendum completed | `FLUTTER_DEVICE_ID=347FB118-10D0-40C8-A05B-B0C3BD6B8CCD ./scripts/run_test_gates.sh transport`; `INTRO_E2E_SCENARIO=pass-fallback ./smoke_test_friends.sh`; row `INTRO-REL-015` source/breakdown evidence. | The transport gate passed on the explicit simulator after an initial no-device-selector failure, and the targeted pass-fallback simulator smoke passed with `Intro E2E harness passed`. | Strengthen `INTRO-REL-015` closure and final verdict evidence with the now-run conditional gates. |

## Recommended plan count

- `0`
- Smallest safe split:
  - `0` implementation sessions for remaining retry-path gaps
  - `0` tests-only closure sessions
  - `0` non-row sessions
- Row disposition counts:
  - `needs_code_and_tests`: `0`
  - `needs_tests_only`: `0`
  - `needs_repo_evidence`: `0`
  - `repo_external_proof`: `0`
  - `covered_in_repo`: `15`
  - `unsupported_product_scope`: `0`
  - `blocked_by_prerequisite`: `0`

## Decomposition artifact

- Artifact path:
  `Test-Flight-Improv/Intro-Feature/Introduction_reliability_test_matrix_TOP_15-session-breakdown.md`
- Proposal/source doc path:
  `Test-Flight-Improv/Intro-Feature/Introduction_reliability_test_matrix_TOP_15.md`
- Decomposition date:
  `2026-05-22`
- Isolation note:
  - decomposition was launched in an isolated spawned agent with `model: gpt-5.5` and `reasoning_effort: xhigh`
  - the agent completed intake, row inventory, evidence map, row disposition, dependency pass, and final breakdown write in the file-backed progress log
  - the controller sent one neutral progress request when the final write appeared stalled, then verified the completed target artifact
- Scope guard:
  - this refresh is documentation-only
  - the code/test changes it references were implemented separately during the INT-REL pass
  - the initial refresh did not run the rollout pipeline; later row-closure passes and final program acceptance are recorded below

## Overall closure bar

`Introduction_reliability_test_matrix_TOP_15.md` is row-closure ready when every source row has row-owned closure evidence:

- each `INTRO-REL-*` row is implemented or directly mapped to an exact automated equivalent with the same failure injection, persistence boundary, and final convergence/trust assertion
- the source matrix row is updated from `Open` to `Covered` or `Closed` with concrete test and gate evidence
- pending-response, introduction outbox, visible intro state, final DB state, and B-C contact existence/non-existence are asserted where the row requires them
- row closure is reported per source row, not only by broad introduction subsystem
- the host-side intro gate passes for every row-owned change, with transport/reliability-sim or iOS simulator gates added only when the row touches public transport, relay/server, resume ordering, simulator-visible semantics, fake network, or 3-party E2E behavior

## Run Mode Snapshot

- Active mode: `implementation-committed gap-closure`
- Degraded local continuation explicitly allowed: `no`
- Source matrix path: `Test-Flight-Improv/Intro-Feature/Introduction_reliability_test_matrix_TOP_15.md`
- Source row/status vocabulary: `Open`, `Partial`, and `Contract-undefined` are unresolved; `Covered` and `Closed` are resolved only with concrete file-and-test evidence.
- Overall row-closure state: every `INTRO-REL-*` source row now reads `Covered` with concrete evidence.
- Final verdict policy: final program acceptance may write `closed` only after reviewing all 15 covered rows and confirming no truthfully blocked residual remains; this pass records that final acceptance below.
- Required host gate for Flutter-owned rows: direct touched tests plus `./scripts/run_test_gates.sh intro`.
- Relay-owned proof: `cd go-relay-server && go test .` only when relay behavior changes or row `INTRO-REL-013` evidence is refreshed.
- Conditional gates: after the `INTRO-REL-015` retry behavior change, `FLUTTER_DEVICE_ID=347FB118-10D0-40C8-A05B-B0C3BD6B8CCD ./scripts/run_test_gates.sh transport` passed and `INTRO_E2E_SCENARIO=pass-fallback ./smoke_test_friends.sh` passed with `Intro E2E harness passed`.

## Gap-Closure Reconciliation

Reconciled on `2026-05-22` before session execution. Initial dirty-worktree snapshot was recorded with `git status --short`; the worktree already contained intro, relay, DB, and test changes plus the untracked source matrix and this breakdown. No unrelated changes were reverted.

Source/breakdown/plan reconciliation:

- Source matrix state: `INTRO-REL-001` through `INTRO-REL-015` now read `Covered`.
- Breakdown disposition state: 15 rows are `covered_in_repo`, 0 rows are `needs_code_and_tests`, and 0 rows are `needs_tests_only`.
- Existing TOP_15 session plan files: `Test-Flight-Improv/Intro-Feature/Introduction_reliability_test_matrix_TOP_15-session-INTRO-REL-006-plan.md`, `Test-Flight-Improv/Intro-Feature/Introduction_reliability_test_matrix_TOP_15-session-INTRO-REL-007-plan.md`, `Test-Flight-Improv/Intro-Feature/Introduction_reliability_test_matrix_TOP_15-session-INTRO-REL-010-plan.md`, and `Test-Flight-Improv/Intro-Feature/Introduction_reliability_test_matrix_TOP_15-session-INTRO-REL-015-plan.md` exist for the accepted/covered rows; no plan file is changed by this closure pass.
- Existing final program verdict: `closed` recorded in `Final Program Verdict` after this reconciliation pass.
- Current session selection rule: no row session is runnable; final program acceptance is complete, and accepted/covered rows should not be re-executed unless a real regression invalidates their evidence.

| Row ID | Source status | Breakdown disposition | Plan verdict/evidence | Concrete repo / gate evidence | Reconciled action |
|---|---|---|---|---|---|
| `INTRO-REL-001` | `Open` -> `Covered` | `covered_in_repo` | No TOP_15 plan file needed; evidence closure. | `intro_db_helpers_test.dart` has atomic intro+both-send-outbox transaction tests; `send_introduction_test.dart` has delivery-stage crash staging coverage. Direct evidence sweep passed with 154 tests; `./scripts/run_test_gates.sh intro` passed with 203 tests. | Accepted/covered; reopen only on regression in atomic send staging or intro gate. |
| `INTRO-REL-002` | `Open` -> `Covered` | `covered_in_repo` | No TOP_15 plan file needed; evidence closure. | Same atomic fan-out DB coverage as `INTRO-REL-001`; `send_introduction_test.dart` covers both target rows before delivery-stage crash. Direct evidence sweep passed with 154 tests; `./scripts/run_test_gates.sh intro` passed with 203 tests. | Accepted/covered; reopen only on regression in fan-out staging or intro gate. |
| `INTRO-REL-003` | `Open` -> `Covered` | `covered_in_repo` | No TOP_15 plan file needed; evidence closure. | `intro_db_helpers_test.dart` has atomic local response+fan-out transaction tests; `accept_introduction_test.dart` has delivery-stage crash staging coverage. Direct evidence sweep passed with 154 tests; `./scripts/run_test_gates.sh intro` passed with 203 tests. | Accepted/covered; reopen only on regression in accept staging or intro gate. |
| `INTRO-REL-004` | `Open` -> `Covered` | `covered_in_repo` | No TOP_15 plan file needed; evidence closure. | `accept_introduction_test.dart` covers both accept fan-out rows before crash; `handle_incoming_introduction_test.dart` covers early accept deferral and replay. Direct evidence sweep passed with 154 tests; `./scripts/run_test_gates.sh intro` passed with 203 tests. | Accepted/covered; reopen only on regression in accept fan-out, pending replay, or intro gate. |
| `INTRO-REL-005` | `Open` -> `Covered` | `covered_in_repo` | No TOP_15 plan file needed; evidence closure. | `intro_db_helpers_test.dart` and `send_introduction_test.dart` cover pending-response rekey on replacement intro; intro gate includes repair/re-send multi-node coverage. Direct evidence sweep passed with 154 tests; `./scripts/run_test_gates.sh intro` passed with 203 tests. | Accepted/covered; reopen only on regression in pending-response rekey/repair evidence or intro gate. |
| `INTRO-REL-006` | `Open` -> `Covered` | `covered_in_repo` | `Test-Flight-Improv/Intro-Feature/Introduction_reliability_test_matrix_TOP_15-session-INTRO-REL-006-plan.md`; execution verdict `closed`. | `test/features/introduction/application/handle_incoming_introduction_test.dart` test `late pass does not downgrade a mutually accepted intro` now seeds existing `peer-C` contact and asserts `contactExists('peer-C')` before and after the late pass; direct test passed with `00:00 +29: All tests passed!`; `./scripts/run_test_gates.sh intro` passed with `All tests passed!`. | Accepted/covered; no further session action unless this terminal-state/contact-survival test or intro gate regresses. |
| `INTRO-REL-007` | `Open` -> `Covered` | `covered_in_repo` | `Test-Flight-Improv/Intro-Feature/Introduction_reliability_test_matrix_TOP_15-session-INTRO-REL-007-plan.md`; execution verdict `closed`. | `test/features/introduction/application/handle_incoming_introduction_test.dart` tests `late accept does not revive a passed intro` and `late accept does not revive an expired intro` assert rejected stale accepts, unchanged terminal state, persisted terminal state, and no `peer-C` contact before/after; direct test passed with 30 tests; `./scripts/run_test_gates.sh intro` passed with 203 tests. | Accepted/covered; no further session action unless these stale late-accept terminal-state/no-contact assertions or the intro gate regress. |
| `INTRO-REL-008` | `Open` -> `Covered` | `covered_in_repo` | No TOP_15 plan file needed; evidence closure. | `handle_incoming_introduction_test.dart` covers deferred replay against terminal/already-connected state and pending-row cleanup. Direct evidence sweep passed with 154 tests; `./scripts/run_test_gates.sh intro` passed with 203 tests. | Accepted/covered; reopen only on pending-replay cleanup or intro-gate regression. |
| `INTRO-REL-009` | `Open` -> `Covered` | `covered_in_repo` | No TOP_15 plan file needed; evidence closure. | `introduction_listener_test.dart` and `handle_incoming_introduction_test.dart` cover transport-sender mismatch before deferred staging. Direct evidence sweep passed with 154 tests; `./scripts/run_test_gates.sh intro` passed with 203 tests. | Accepted/covered; reopen only on forged pre-send rejection or intro-gate regression. |
| `INTRO-REL-010` | `Open` -> `Covered` | `covered_in_repo` | `Test-Flight-Improv/Intro-Feature/Introduction_reliability_test_matrix_TOP_15-session-INTRO-REL-010-plan.md`; execution verdict `closed`. | `test/features/introduction/application/handle_incoming_introduction_test.dart` test `valid existing intro rejects forged live accept and pass without state changes` seeds valid existing A/B/C rows, sends forged live `accept` and `pass` from `peer-forger` claiming `peer-C`, and asserts rejected/null result, unchanged stored intro state, no pending response, and no B-C contact; direct test passed with 31 tests; `./scripts/run_test_gates.sh intro` passed with 204 tests. | Accepted/covered; no further session action unless this forged existing-row no-mutation/no-pending/no-contact test or intro gate regresses. |
| `INTRO-REL-011` | `Open` -> `Covered` | `covered_in_repo` | No TOP_15 plan file needed; evidence closure. | `handle_incoming_introduction_test.dart` rejects misaddressed and malformed sends before local truth. Direct evidence sweep passed with 154 tests; `./scripts/run_test_gates.sh intro` passed with 203 tests. | Accepted/covered; reopen only on misaddressed-send rejection or intro-gate regression. |
| `INTRO-REL-012` | `Open` -> `Covered` | `covered_in_repo` | No TOP_15 plan file needed; evidence closure. | `send_introduction_test.dart` covers effective recipient ML-KEM key consistency for encryption and persisted metadata. Direct evidence sweep passed with 154 tests; `./scripts/run_test_gates.sh intro` passed with 203 tests. | Accepted/covered; reopen only on effective-key consistency or intro-gate regression. |
| `INTRO-REL-013` | `Open` -> `Covered` | `covered_in_repo` | No TOP_15 plan file needed; relay evidence closure. | `go-relay-server/inbox_dedup_test.go` has `TestInboxStoreDedup_SameIdDifferentRecipient`; `go-relay-server/backend_redis_test.go` has `TestRedisInboxBackend_DedupesByMessageIDPerRecipient`; `cd go-relay-server && go test .` passed with `ok github.com/mknoon/relay-server`. | Accepted/covered; reopen only on relay dedupe regression. |
| `INTRO-REL-014` | `Open` -> `Covered` | `covered_in_repo` | No TOP_15 plan file needed; evidence closure. | `test/core/services/p2p_service_impl_test.dart` covers committed introduction staging/ack/delete and retryable staged-row preservation; production wiring dispatches staged intro messages directly to `IntroductionListener.processIncomingMessage`. Direct evidence sweep passed with 154 tests; `./scripts/run_test_gates.sh intro` passed with 203 tests. | Accepted/covered; reopen only on durable inbox introduction replay or gate regression. |
| `INTRO-REL-015` | `Open` -> `Covered` | `covered_in_repo` | `Test-Flight-Improv/Intro-Feature/Introduction_reliability_test_matrix_TOP_15-session-INTRO-REL-015-plan.md`; execution verdict `accepted_with_explicit_follow_up` before docs, closure verdict `closed` after this pass. | `test/features/introduction/application/introduction_outbound_delivery_test.dart` tests `retryPendingIntroductionDeliveries delivers a failed row through direct send when inbox storage fails` and `retryPendingIntroductionDeliveries delivers a failed row through relay probe when inbox storage fails` seed failed retryable rows, force inbox storage failure, and assert acknowledged direct/relay retries deliver and clear the outbox. RED direct regression failed before implementation with `Expected: <1> Actual: <0>`; direct file passed with 11 tests; scoped `git diff --check` passed; `./scripts/run_test_gates.sh intro` passed with 204 tests; `FLUTTER_DEVICE_ID=347FB118-10D0-40C8-A05B-B0C3BD6B8CCD ./scripts/run_test_gates.sh transport` passed; `INTRO_E2E_SCENARIO=pass-fallback ./smoke_test_friends.sh` passed with `Intro E2E harness passed`. | Accepted/covered; reopen only on failed-inbox retry direct/relay delivery regression, direct-file regression, intro-gate regression, transport-gate regression, or pass-fallback simulator regression. |

Reconciled session ledger:

| Session ID | Reconciled status | Blocker class | Next safe action |
|---|---|---|---|
| `INTRO-REL-001` | `accepted_covered` | none | Closed by evidence verification, direct evidence sweep, and intro gate; reopen only on real regression. |
| `INTRO-REL-002` | `accepted_covered` | none | Closed by evidence verification, direct evidence sweep, and intro gate; reopen only on real regression. |
| `INTRO-REL-003` | `accepted_covered` | none | Closed by evidence verification, direct evidence sweep, and intro gate; reopen only on real regression. |
| `INTRO-REL-004` | `accepted_covered` | none | Closed by evidence verification, direct evidence sweep, and intro gate; reopen only on real regression. |
| `INTRO-REL-005` | `accepted_covered` | none | Closed by evidence verification, direct evidence sweep, and intro gate; reopen only on real regression. |
| `INTRO-REL-006` | `accepted_covered` | none | Closed by tests-only assertion plus direct test and intro gate; reopen only on real regression. |
| `INTRO-REL-007` | `accepted_covered` | none | Closed by tests-only assertions plus direct test and intro gate; reopen only on real regression. |
| `INTRO-REL-008` | `accepted_covered` | none | Closed by evidence verification, direct evidence sweep, and intro gate; reopen only on real regression. |
| `INTRO-REL-009` | `accepted_covered` | none | Closed by evidence verification, direct evidence sweep, and intro gate; reopen only on real regression. |
| `INTRO-REL-010` | `accepted_covered` | none | Closed by tests-only valid-existing-row forged accept/pass assertions plus direct test and intro gate; reopen only on real regression. |
| `INTRO-REL-011` | `accepted_covered` | none | Closed by evidence verification, direct evidence sweep, and intro gate; reopen only on real regression. |
| `INTRO-REL-012` | `accepted_covered` | none | Closed by evidence verification, direct evidence sweep, and intro gate; reopen only on real regression. |
| `INTRO-REL-013` | `accepted_covered` | none | Closed by relay evidence verification and `go test .`; reopen only on real relay dedupe regression. |
| `INTRO-REL-014` | `accepted_covered` | none | Closed by evidence verification, direct evidence sweep, and intro gate; reopen only on real regression. |
| `INTRO-REL-015` | `accepted_covered` | none | Closed by implementation-committed direct/relay failed-inbox retry proof plus direct file, diff check, and intro gate; reopen only on real regression. |

## Source of truth

Primary governing docs:

- `Test-Flight-Improv/Intro-Feature/Introduction_reliability_test_matrix_TOP_15.md`
- `Test-Flight-Improv/Intro-Feature/test-inventory.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `scripts/run_test_gates.sh`

## Gate Execution Model

The row-level TDD and closure gate is host-first:

- Required for any future Flutter-owned row change: direct touched tests plus `./scripts/run_test_gates.sh intro`.
- `./scripts/run_test_gates.sh intro` is host-side in this repo; it runs `test/features/introduction/**` files with `flutter test` and does not launch iOS simulators.
- Required for relay-owned proof: `cd go-relay-server && go test .` when row `INTRO-REL-013` or relay dedupe behavior changes.

iOS simulator E2E adds value as targeted release confidence, not as the default TDD gate:

| Use | Command | Applies to |
|---|---|---|
| Repair / re-send convergence | `INTRO_E2E_SCENARIO=repair ./smoke_test_friends.sh` | `INTRO-REL-005`; useful release proof for repaired intro truth |
| Partition-heal convergence | `INTRO_E2E_SCENARIO=partition ./smoke_test_friends.sh` | `INTRO-REL-004`, `INTRO-REL-005`, and any row with real A/B/C convergence risk |
| Offline/pass fallback inbox drain | `INTRO_E2E_SCENARIO=pass-fallback ./smoke_test_friends.sh` | `INTRO-REL-004`, `INTRO-REL-014`, and `INTRO-REL-015` if retry behavior changes real delivery paths |
| Full intro simulator sweep | `INTRO_E2E_SCENARIO=all ./smoke_test_friends.sh` | Pre-TestFlight or release-candidate confidence when time allows |

Do not require iOS simulator E2E for accepted tests-only rows `INTRO-REL-006`, `INTRO-REL-007`, or `INTRO-REL-010`; deterministic host tests prove those trust/state invariants more directly. For `INTRO-REL-015`, the conditional transport and targeted simulator proof was run after implementation: the explicit-device transport gate passed, and the targeted `pass-fallback` simulator smoke passed.

Current repo facts that shaped the refreshed classification:

- Intro creation now has atomic local truth plus both send outbox rows, covered by `dbSaveIntroductionWithOutboxDeliveries` tests and the send-side delivery-stage crash test.
- Accept/pass response persistence now has atomic local status plus both fan-out rows, covered by `dbSaveIntroductionResponseWithOutboxDeliveries` tests and accept-side delivery-stage crash coverage.
- Re-send/replacement now migrates pending responses to the replacement intro id, covered at DB helper and send use-case levels.
- Terminal-state guards exist in handler, accept, pass, and DB-helper tests; the accepted terminal-state source rows now include exact closure assertions for contact existence/non-existence.
- Transport sender binding exists in listener and handler tests, including deferred pre-send responses, v2 envelope sender mismatch, and the exact valid-existing-row live forged accept/pass no-mutation regression.
- Misaddressed intro sends and malformed peer ids are rejected in handler tests.
- Recipient ML-KEM key consistency is covered by a send use-case test that checks effective fresh key use in persisted intro metadata and encryption plaintext.
- Relay fan-out dedupe is target-scoped. Memory relay already had `TestInboxStoreDedup_SameIdDifferentRecipient`; Redis now has `TestRedisInboxBackend_DedupesByMessageIDPerRecipient`, and relay v1.5.1 was deployed with that contract.
- Durable inbox replay for introductions bypasses the broadcast router: `P2PServiceImpl` stages relay entries locally, acks after staging, and invokes `IntroductionListener.processIncomingMessage` directly for `messageType == introduction`. Existing P2P service tests cover committed and retryable staged introduction rows.
- `retryPendingIntroductionDeliveries` now preserves inbox-success retry and, after inbox storage failure, retries through the existing direct/relay delivery cascade with the second inbox fallback disabled. `INTRO-REL-015` is covered by direct-send and relay-probe failed-inbox retry regressions.

## Matrix row inventory

| Row ID | Scenario | Priority | Source section or table | Provisional row disposition | Intended session id |
|---|---|---|---|---|---|
| `INTRO-REL-001` | Crash after intro row save before any outbound leg is staged | `P0` | Matrix - maximum 15 rows | `covered_in_repo` | `INTRO-REL-001` |
| `INTRO-REL-002` | Crash between B and C fan-out staging | `P0` | Matrix - maximum 15 rows | `covered_in_repo` | `INTRO-REL-002` |
| `INTRO-REL-003` | Crash after local accept status update before accept outbox staging | `P0` | Matrix - maximum 15 rows | `covered_in_repo` | `INTRO-REL-003` |
| `INTRO-REL-004` | Crash after C's accept reaches A but before B is staged | `P0` | Matrix - maximum 15 rows | `covered_in_repo` | `INTRO-REL-004` |
| `INTRO-REL-005` | C accept pending under old intro ID survives A repair/re-send | `P0` | Matrix - maximum 15 rows | `covered_in_repo` | `INTRO-REL-005` |
| `INTRO-REL-006` | Mutual/connected terminal state cannot be downgraded by late pass | `P0` | Matrix - maximum 15 rows | `covered_in_repo` | `INTRO-REL-006` |
| `INTRO-REL-007` | Passed/expired terminal state cannot be revived by late accept | `P0` | Matrix - maximum 15 rows | `covered_in_repo` | `INTRO-REL-007` |
| `INTRO-REL-008` | Pending replay consumes idempotent `alreadyExists` responses | `P0` | Matrix - maximum 15 rows | `covered_in_repo` | `INTRO-REL-008` |
| `INTRO-REL-009` | Forged accept before original intro is rejected, not staged | `P0` | Matrix - maximum 15 rows | `covered_in_repo` | `INTRO-REL-009` |
| `INTRO-REL-010` | Forged accept after intro row exists is rejected | `P0` | Matrix - maximum 15 rows | `covered_in_repo` | `INTRO-REL-010` |
| `INTRO-REL-011` | Misaddressed intro `send` is rejected | `P0` | Matrix - maximum 15 rows | `covered_in_repo` | `INTRO-REL-011` |
| `INTRO-REL-012` | Recipient ML-KEM key consistency supports C->B early accept | `P0` | Matrix - maximum 15 rows | `covered_in_repo` | `INTRO-REL-012` |
| `INTRO-REL-013` | Fan-out message IDs are target-safe under relay dedupe | `P0` | Matrix - maximum 15 rows | `covered_in_repo` | `INTRO-REL-013` |
| `INTRO-REL-014` | Offline inbox drain cannot drop intro when listener starts late | `P0` | Matrix - maximum 15 rows | `covered_in_repo` | `INTRO-REL-014` |
| `INTRO-REL-015` | Retry uses direct/relay when inbox store fails | `P0` | Matrix - maximum 15 rows | `covered_in_repo` | `INTRO-REL-015` |

## Row traceability rule

Every source row maps to exactly one session id or one explicit `duplicate_of` relationship. This matrix has no duplicates, so every source row maps one-to-one to a session with the exact source row id. Later closure work must report final truth per source row, not only per introduction, delivery, persistence, or transport subsystem.

## Evidence Map

| Row ID | Likely code-entry files | Existing adjacent tests/evidence | Missing direct proof | Likely named gates | Proof owner |
|---|---|---|---|---|---|
| `INTRO-REL-001` | `send_introduction_use_case.dart`, `introduction_outbound_delivery.dart`, `introduction_repository_impl.dart`, outbox DB helpers | `intro_db_helpers_test.dart` - `commits the intro row and both outbound rows together`, `rolls back the intro row if any outbound row fails`; `send_introduction_test.dart` - `persists both outbound target rows before a delivery-stage crash` | none for current implementation; source matrix row can be closed with this evidence after gate rerun | `./scripts/run_test_gates.sh intro` | Flutter-owned |
| `INTRO-REL-002` | `send_introduction_use_case.dart`, `introduction_outbound_delivery.dart`, outbox repository/helpers | Same atomic intro/outbox DB tests as `INTRO-REL-001`; `send_introduction_test.dart` proves both B/C outbox rows exist before any delivery-stage crash can leave one missing | none for current implementation; source matrix row can be closed with this evidence after gate rerun | `intro` | Flutter-owned |
| `INTRO-REL-003` | `accept_introduction_use_case.dart`, `introduction_outbound_delivery.dart`, repository status/outbox methods | `intro_db_helpers_test.dart` - `commits the local response and accept fan-out rows together`, `rolls back the local response if any fan-out row fails`; `accept_introduction_test.dart` - `persists local accept and both fan-out rows before a delivery-stage crash` | none for current implementation; source matrix row can be closed with this evidence after gate rerun | `intro`; direct `accept_introduction_test.dart` | Flutter-owned |
| `INTRO-REL-004` | `accept_introduction_use_case.dart`, `introduction_outbound_delivery.dart`, pending response helpers, `handle_incoming_introduction_use_case.dart` | `accept_introduction_test.dart` crash test shows both C->A and C->B accept fan-out rows exist before delivery-stage crash; `handle_incoming_introduction_test.dart` - `accept before send is deferred and replayed when send arrives`; multi-node inbox fallback tests cover offline accept convergence | none for current implementation; targeted 3-party simulator smoke remains useful release evidence | host TDD: `intro`; release confidence: `INTRO_E2E_SCENARIO=partition` or `pass-fallback` | Flutter-owned |
| `INTRO-REL-005` | `handle_incoming_introduction_use_case.dart`, `introduction_repository_impl.dart`, pending response helpers, send repair path | `intro_db_helpers_test.dart` - `replaces old intro and rekeys staged responses to the new intro id`; `send_introduction_test.dart` - `re-sending the same pair rekeys pending responses from the replaced intro id`; multi-node test - `reintroducing the same pair repairs a missed side and ignores stale older delivery` | none for current implementation | host TDD: `intro`; release confidence: `INTRO_E2E_SCENARIO=repair` and optionally `partition` | Flutter-owned |
| `INTRO-REL-006` | `handle_incoming_introduction_use_case.dart`, `introductions_db_helpers.dart`, `pass_introduction_use_case.dart` | `handle_incoming_introduction_test.dart` - `late pass does not downgrade a mutually accepted intro` now seeds `peer-C` as an existing contact and asserts `contactExists('peer-C')` before and after the late pass; `pass_introduction_test.dart` - `passing a mutually accepted intro does not downgrade terminal state`; DB helper tests prevent terminal overwrite | none after `flutter test test/features/introduction/application/handle_incoming_introduction_test.dart` and `./scripts/run_test_gates.sh intro` passed | `intro`; direct regression test | Flutter-owned |
| `INTRO-REL-007` | `handle_incoming_introduction_use_case.dart`, `introductions_db_helpers.dart`, `accept_introduction_use_case.dart`, expiry/pass paths | `handle_incoming_introduction_test.dart` - `late accept does not revive a passed intro` now asserts rejected result, unchanged terminal state, persisted terminal state, and no `peer-C` contact before/after; `late accept does not revive an expired intro` asserts the same terminal/no-contact invariant; `accept_introduction_test.dart` covers adjacent local accept no-op on passed intros; DB helper tests prevent terminal overwrite | none after `flutter test test/features/introduction/application/handle_incoming_introduction_test.dart` and `./scripts/run_test_gates.sh intro` passed | `intro`; direct regression test | Flutter-owned |
| `INTRO-REL-008` | `handle_incoming_introduction_use_case.dart`, pending response helpers, repository pending response methods | `handle_incoming_introduction_test.dart` - `deferred response replay does not downgrade an alreadyConnected intro` and clears pending rows; duplicate/terminal `alreadyExists` paths no longer cause replay loops | none for current implementation | `intro`; direct handler/helper tests | Flutter-owned |
| `INTRO-REL-009` | `introduction_listener.dart`, `handle_incoming_introduction_use_case.dart`, pending response helpers | `introduction_listener_test.dart` - `rejects deferred response when transport sender does not match responder`; `handle_incoming_introduction_test.dart` - `transport sender mismatch rejects response before staging`; migration 071 test preserves transport sender on old pending rows | none for current implementation | `intro`; fake network/direct listener test | Flutter-owned |
| `INTRO-REL-010` | `introduction_listener.dart`, `handle_incoming_introduction_use_case.dart`, repository status/contact paths | `handle_incoming_introduction_test.dart` test `valid existing intro rejects forged live accept and pass without state changes` covers valid existing A/B/C rows plus live forged `accept` and `pass` from `peer-forger` claiming `peer-C`; adjacent replay safety remains covered by `pending response with mismatched transport sender is discarded during replay`. | none after `flutter test --no-pub test/features/introduction/application/handle_incoming_introduction_test.dart` and `./scripts/run_test_gates.sh intro` passed | `intro`; direct handler regression test | Flutter-owned |
| `INTRO-REL-011` | `handle_incoming_introduction_use_case.dart`, `introduction_listener.dart`, notification/system-message paths | `handle_incoming_introduction_test.dart` - `rejects send not addressed to this user`, `rejects send with missing or blank required peer ids`; listener duplicate/send tests cover no extra presentation on rejected paths | none for current implementation | `intro`; direct handler/listener test | Flutter-owned |
| `INTRO-REL-012` | `send_introduction_use_case.dart`, `accept_introduction_use_case.dart`, `IntroductionPayload`, key fields on `IntroductionModel` | `send_introduction_test.dart` - `uses the effective recipient ML-KEM key consistently for encryption and intro metadata`; accept/pass mismatch tests reject stale stranger key conflicts before mutation | none for current implementation; optional 3-party encrypted early-accept smoke is release confidence, not a code prerequisite | host TDD: `intro`; release confidence: `INTRO_E2E_SCENARIO=all` only if encrypted early accept must be proven end-to-end | Flutter-owned |
| `INTRO-REL-013` | relay backend dedupe, `IntroductionPayload.buildEnvelopeMessageId`, `introduction_outbound_delivery.dart` | `go-relay-server/inbox_dedup_test.go` - `TestInboxStoreDedup_SameIdDifferentRecipient`; `go-relay-server/backend_redis_test.go` - `TestRedisInboxBackend_DedupesByMessageIDPerRecipient`; deployed relay v1.5.1 includes this proof | no Flutter message-id change required because relay dedupe is target-scoped | `cd go-relay-server && go test .`; transport gate only if relay contract changes | Relay-owned proof |
| `INTRO-REL-014` | `P2PServiceImpl` durable inbox staging, `introduction_listener.dart`, router/resume code | `p2p_service_impl_test.dart` - `stages, acks, and deletes committed introduction entries`, `retryable introduction outcomes keep the staged row with exact reason`; production wiring calls `IntroductionListener.processIncomingMessage` directly for staged intro replay | no router buffering fix required for durable inbox intro messages; optional startup-order smoke can remain as a guard | host TDD: core P2P service test; release confidence: `INTRO_E2E_SCENARIO=pass-fallback` or `offline-chat` | Flutter-owned evidence |
| `INTRO-REL-015` | `retryPendingIntroductionDeliveries`, delivery race/direct/relay helpers, `handle_app_resumed.dart`, `PendingMessageRetrier` | `introduction_outbound_delivery_test.dart` covers retry through inbox, multiple retryable rows, direct-send retry after inbox storage failure, relay-probe retry after inbox storage failure, and resume-triggered inbox retry | none after the direct file passed with 11 tests, scoped `git diff --check` passed, `./scripts/run_test_gates.sh intro` passed with 204 tests, explicit-device `transport` passed, and targeted `pass-fallback` simulator smoke passed | host TDD: direct file plus `intro`; conditional `transport` and `pass-fallback` simulator proof completed | Flutter-owned |

## Row disposition

| Row ID | Row disposition | Session classification | Rationale |
|---|---|---|---|
| `INTRO-REL-001` | `covered_in_repo` | `evidence-mapped` | Atomic intro+both-send-outbox persistence and delivery-stage crash coverage exist. |
| `INTRO-REL-002` | `covered_in_repo` | `evidence-mapped` | Both send fan-out rows are staged together before delivery, removing the one-leg crash gap. |
| `INTRO-REL-003` | `covered_in_repo` | `evidence-mapped` | Atomic local accept+both-accept-outbox persistence and delivery-stage crash coverage exist. |
| `INTRO-REL-004` | `covered_in_repo` | `evidence-mapped` | Accept fan-out rows exist before delivery-stage crash, and early accept pending replay is covered. |
| `INTRO-REL-005` | `covered_in_repo` | `evidence-mapped` | Pending responses are rekeyed on replacement intro and repair/re-send has multi-node coverage. |
| `INTRO-REL-006` | `covered_in_repo` | `accepted-tests-only` | Exact contact-remains assertion landed in `handle_incoming_introduction_test.dart`; direct test and `intro` gate passed. |
| `INTRO-REL-007` | `covered_in_repo` | `accepted-tests-only` | Exact stale late-accept assertions landed for `passed` and `expired`, including no-contact-created checks; direct test and `intro` gate passed. |
| `INTRO-REL-008` | `covered_in_repo` | `evidence-mapped` | Idempotent/terminal pending replay is consumed without retry loops. |
| `INTRO-REL-009` | `covered_in_repo` | `evidence-mapped` | Forged pre-send accept is rejected before pending-response staging. |
| `INTRO-REL-010` | `covered_in_repo` | `accepted-tests-only` | Exact valid-existing-row forged accept/pass no-mutation assertion landed in `handle_incoming_introduction_test.dart`; direct test and `intro` gate passed. |
| `INTRO-REL-011` | `covered_in_repo` | `evidence-mapped` | Misaddressed and malformed sends are rejected before local truth/presentation. |
| `INTRO-REL-012` | `covered_in_repo` | `evidence-mapped` | Effective recipient ML-KEM key is consistent across encryption and intro metadata. |
| `INTRO-REL-013` | `covered_in_repo` | `evidence-mapped` | Relay memory and Redis backends prove dedupe is scoped per recipient. |
| `INTRO-REL-014` | `covered_in_repo` | `evidence-mapped` | Durable staged inbox replay dispatches intro messages directly to the listener and preserves retryable failures. |
| `INTRO-REL-015` | `covered_in_repo` | `accepted-code-and-tests` | Implementation-committed direct/relay failed-inbox retry parity landed in `introduction_outbound_delivery.dart` and `introduction_outbound_delivery_test.dart`; direct file and intro gate passed. |

## Dependency Pass

- Do not execute covered rows as code sessions unless a later regression invalidates their evidence.
- The remaining execution set is empty; all 15 row-owned sessions are accepted/covered.
- `INTRO-REL-010` is accepted/covered; do not execute it as new work unless the valid-existing-row forged accept/pass no-mutation proof regresses.
- Evidence-mapped rows `INTRO-REL-001`-`005`, `008`, `009`, and `011`-`014` are accepted/covered after direct evidence sweep, intro gate, and relay proof where applicable.
- `INTRO-REL-007` is accepted/covered; do not execute it as new work unless the stale late-accept terminal-state/no-contact proof regresses.
- `INTRO-REL-015` is accepted/covered after implementation-committed failed-inbox retry parity, direct file, scoped diff check, intro gate evidence, explicit-device transport gate, and targeted pass-fallback simulator smoke.
- Final program acceptance completed after `INTRO-REL-015` closure; verdict is recorded below.

## Session ledger

| Order | Session ID | Source row id | Classification | Intended plan file | Depends on |
|---:|---|---|---|---|---|
| 1 | `INTRO-REL-001` | `INTRO-REL-001` | `accepted/covered` | no new plan needed; evidence closure | none |
| 2 | `INTRO-REL-002` | `INTRO-REL-002` | `accepted/covered` | no new plan needed; evidence closure | none |
| 3 | `INTRO-REL-003` | `INTRO-REL-003` | `accepted/covered` | no new plan needed; evidence closure | none |
| 4 | `INTRO-REL-004` | `INTRO-REL-004` | `accepted/covered` | no new plan needed; evidence closure | none |
| 5 | `INTRO-REL-005` | `INTRO-REL-005` | `accepted/covered` | no new plan needed; evidence closure | none |
| 6 | `INTRO-REL-006` | `INTRO-REL-006` | `accepted/covered` | `Test-Flight-Improv/Intro-Feature/Introduction_reliability_test_matrix_TOP_15-session-INTRO-REL-006-plan.md` | none |
| 7 | `INTRO-REL-007` | `INTRO-REL-007` | `accepted/covered` | `Test-Flight-Improv/Intro-Feature/Introduction_reliability_test_matrix_TOP_15-session-INTRO-REL-007-plan.md` | none |
| 8 | `INTRO-REL-008` | `INTRO-REL-008` | `accepted/covered` | no new plan needed; evidence closure | none |
| 9 | `INTRO-REL-009` | `INTRO-REL-009` | `accepted/covered` | no new plan needed; evidence closure | none |
| 10 | `INTRO-REL-010` | `INTRO-REL-010` | `accepted/covered` | `Test-Flight-Improv/Intro-Feature/Introduction_reliability_test_matrix_TOP_15-session-INTRO-REL-010-plan.md` | none |
| 11 | `INTRO-REL-011` | `INTRO-REL-011` | `accepted/covered` | no new plan needed; evidence closure | none |
| 12 | `INTRO-REL-012` | `INTRO-REL-012` | `accepted/covered` | no new plan needed; evidence closure | none |
| 13 | `INTRO-REL-013` | `INTRO-REL-013` | `accepted/covered` | no new plan needed; relay evidence closure | none |
| 14 | `INTRO-REL-014` | `INTRO-REL-014` | `accepted/covered` | no new plan needed; evidence closure | none |
| 15 | `INTRO-REL-015` | `INTRO-REL-015` | `accepted/covered` | `Test-Flight-Improv/Intro-Feature/Introduction_reliability_test_matrix_TOP_15-session-INTRO-REL-015-plan.md` | none |

## Remaining Session Breakdown

Rows marked `accepted/covered` below are retained as closure ledger entries and should not be executed as new work. There are no remaining unresolved row sessions in this artifact.

### 1. `INTRO-REL-006` - accepted/covered

- Source row id: `INTRO-REL-006`
- Scenario title: Mutual/connected terminal state cannot be downgraded by late pass
- Row disposition: `covered_in_repo`
- Session classification: `accepted-tests-only`
- Intended plan file: `Test-Flight-Improv/Intro-Feature/Introduction_reliability_test_matrix_TOP_15-session-INTRO-REL-006-plan.md`
- Execution verdict: `closed` for this row; source matrix status is `Covered`.
- Docs touched for closure: `Test-Flight-Improv/Intro-Feature/Introduction_reliability_test_matrix_TOP_15.md` and this breakdown. The session plan above remains the inspected execution plan.
- Evidence: `test/features/introduction/application/handle_incoming_introduction_test.dart` test `late pass does not downgrade a mutually accepted intro` seeds `peer-C` as an existing contact and asserts `contactExists('peer-C')` before and after the late pass while terminal status remains `mutualAccepted`.
- Gate evidence: `flutter test test/features/introduction/application/handle_incoming_introduction_test.dart` exited 0 with `00:00 +29: All tests passed!`; `./scripts/run_test_gates.sh intro` exited 0 with final `All tests passed!`.
- Residual-only items: none for `INTRO-REL-006`; no product code changed for this session.
- Reopen only if: the late-pass terminal-state guard, the B-C contact-survival assertion, or the `intro` gate regresses.

### 2. `INTRO-REL-007` - accepted/covered

- Source row id: `INTRO-REL-007`
- Scenario title: Passed/expired terminal state cannot be revived by late accept
- Row disposition: `covered_in_repo`
- Session classification: `accepted-tests-only`
- Intended plan file: `Test-Flight-Improv/Intro-Feature/Introduction_reliability_test_matrix_TOP_15-session-INTRO-REL-007-plan.md`
- Execution verdict: `closed` for this row; source matrix status is `Covered`.
- Docs touched for closure: `Test-Flight-Improv/Intro-Feature/Introduction_reliability_test_matrix_TOP_15.md` and this breakdown. The session plan above remains the inspected execution plan.
- Evidence: `test/features/introduction/application/handle_incoming_introduction_test.dart` test `late accept does not revive a passed intro` asserts a stale accept returns `rejected`, preserves passed terminal status, persists the terminal row, and leaves `contactExists('peer-C')` false before and after. Test `late accept does not revive an expired intro` asserts the same rejected/terminal/persisted/no-contact invariant for expired state.
- Gate evidence: `flutter test test/features/introduction/application/handle_incoming_introduction_test.dart` passed with 30 tests; `./scripts/run_test_gates.sh intro` passed with 203 tests. Executor and QA both ran both commands.
- Residual-only items: none for `INTRO-REL-007`; no product code changed for this session.
- Accepted differences: no iOS simulator, relay, or transport proof is required because this row is closed by deterministic host-side terminal-state/contact mutation coverage.
- Reopen only if: the stale late-accept terminal-state guard, the no-B-C-contact assertion, or the `intro` gate regresses.

### 3. `INTRO-REL-010` - accepted/covered

- Source row id: `INTRO-REL-010`
- Scenario title: Forged accept after intro row exists is rejected
- Row disposition: `covered_in_repo`
- Session classification: `accepted-tests-only`
- Intended plan file: `Test-Flight-Improv/Intro-Feature/Introduction_reliability_test_matrix_TOP_15-session-INTRO-REL-010-plan.md`
- Execution verdict: `closed` for this row; source matrix status is `Covered`.
- Docs touched for closure: `Test-Flight-Improv/Intro-Feature/Introduction_reliability_test_matrix_TOP_15.md` and this breakdown. The session plan above remains the inspected execution plan.
- Evidence: `test/features/introduction/application/handle_incoming_introduction_test.dart` test `valid existing intro rejects forged live accept and pass without state changes` seeds valid existing A/B/C intro rows, then sends forged live `accept` and `pass` responses from `peer-forger` claiming `peer-C`; each case asserts `HandleIntroductionResult.rejected`, null returned model, unchanged stored intro identifiers/statuses/responded timestamps, empty pending responses, and no `peer-C` contact.
- Gate evidence: `flutter test --no-pub test/features/introduction/application/handle_incoming_introduction_test.dart` passed with 31 tests; `./scripts/run_test_gates.sh intro` passed with 204 tests. `git diff --check -- ...` passed for the scoped closure/test diff.
- Residual-only items: none for `INTRO-REL-010`; no product code changed for this session.
- Accepted differences: no iOS simulator, relay, or transport proof is required because this row is closed by deterministic host-side sender-binding and local state-mutation coverage.
- Reopen only if: the valid-existing-row forged accept/pass no-mutation/no-pending/no-contact assertion or the `intro` gate regresses.

### 4. `INTRO-REL-015` - accepted/covered

- Source row id: `INTRO-REL-015`
- Scenario title: Retry uses direct/relay when inbox store fails
- Row disposition: `covered_in_repo`
- Session classification: `accepted-code-and-tests`
- Intended plan file: `Test-Flight-Improv/Intro-Feature/Introduction_reliability_test_matrix_TOP_15-session-INTRO-REL-015-plan.md`
- Execution verdict: `closed` for this row; source matrix status is `Covered`.
- Docs touched for closure: `Test-Flight-Improv/Intro-Feature/Introduction_reliability_test_matrix_TOP_15.md`, this breakdown, and `Test-Flight-Improv/Intro-Feature/test-inventory.md`. The session plan above remains the inspected execution plan.
- Evidence: `test/features/introduction/application/introduction_outbound_delivery_test.dart` tests `retryPendingIntroductionDeliveries delivers a failed row through direct send when inbox storage fails` and `retryPendingIntroductionDeliveries delivers a failed row through relay probe when inbox storage fails` seed failed retryable rows, force `storeInInbox` failure, assert one inbox attempt, then prove acknowledged direct/relay retry increments delivered count and clears the outbox. The resume test wording changed to `handleAppResumed replays a sent intro row through inbox retry`.
- Implementation evidence: `retryPendingIntroductionDeliveries` preserves the inbox-success retry path, then calls the existing direct/relay delivery cascade after inbox storage fails with inbox fallback disabled for the second attempt. Acknowledged direct/relay retry saves delivered state, clears stale error/path state, and deletes the row.
- RED evidence: `flutter test --no-pub test/features/introduction/application/introduction_outbound_delivery_test.dart --plain-name 'retryPendingIntroductionDeliveries delivers a failed row through direct send when inbox storage fails'` failed before implementation with `Expected: <1> Actual: <0>`.
- Gate evidence: `flutter test --no-pub test/features/introduction/application/introduction_outbound_delivery_test.dart` passed with 11 tests; `git diff --check -- lib/features/introduction/application/introduction_outbound_delivery.dart test/features/introduction/application/introduction_outbound_delivery_test.dart` passed; `./scripts/run_test_gates.sh intro` passed with 204 tests; `FLUTTER_DEVICE_ID=347FB118-10D0-40C8-A05B-B0C3BD6B8CCD ./scripts/run_test_gates.sh transport` passed; `INTRO_E2E_SCENARIO=pass-fallback ./smoke_test_friends.sh` passed with `Intro E2E harness passed`. Executor and QA both reran the direct file, diff check, and intro gate before the conditional gates were added.
- Residual-only items: none for `INTRO-REL-015`.
- Accepted differences: no remaining transport/simulator evidence gap; the conditional transport gate and targeted pass-fallback simulator smoke were run and passed.
- Reopen only if: failed-inbox retry stops delivering through acknowledged direct/relay paths, direct/relay retry no longer clears delivered outbox rows, the direct file regresses, or the `intro` gate regresses.

## Downstream execution path

- `INTRO-REL-015` has completed the normal plan, implementation, QA, and closure pipeline.
- Do not regenerate a seam-bucket breakdown for this matrix; use this current-truth artifact as the reusable handoff.
- Row execution is complete for all 15 rows; each source matrix row is updated to `Covered` with concrete test/gate evidence.
- Final whole-program acceptance completed in the final acceptance pass; the persisted verdict is `closed`.
- Baseline named gate for future intro changes: direct touched tests plus `./scripts/run_test_gates.sh intro`.
- Conditional companion gates:
  - use host-side `test/features/introduction/**` tests for narrow application/helper rows
  - use `./scripts/run_test_gates.sh transport` or `./scripts/run_test_gates.sh reliability-sim intro` when the row changes real transport, relay/inbox, resume ordering, or reliability simulation behavior
  - use targeted iOS simulator E2E (`repair`, `partition`, or `pass-fallback`) as release confidence for real A/B/C convergence, offline inbox, repair/re-send, or direct/relay retry changes
  - run `INTRO_E2E_SCENARIO=all ./smoke_test_friends.sh` before TestFlight when time allows or when multiple intro reliability rows changed together
  - update `test-inventory.md` when new durable reliability tests become part of the intro suite

## Final Program Verdict

- Verdict: `closed`
- Final acceptance timestamp: `2026-05-22 23:05 CEST`
- Active mode: `implementation-committed gap-closure`
- Breakdown artifact: `Test-Flight-Improv/Intro-Feature/Introduction_reliability_test_matrix_TOP_15-session-breakdown.md`
- Source matrix: `Test-Flight-Improv/Intro-Feature/Introduction_reliability_test_matrix_TOP_15.md`
- Inventory reference: `Test-Flight-Improv/Intro-Feature/test-inventory.md`
- Blockers: none.

Final ledger sanity checks performed:

- Source matrix row count: 15 `INTRO-REL-*` rows; every row's `Current status` is `Covered`.
- Breakdown reconciliation: all 15 rows are `covered_in_repo`; counts are `needs_code_and_tests: 0`, `needs_tests_only: 0`, `needs_repo_evidence: 0`, `repo_external_proof: 0`, `blocked_by_prerequisite: 0`.
- Session ledger: all 15 row-owned sessions are `accepted/covered`; no row-owned session remains `Open`, `Partial`, `blocked`, `prerequisite-blocked`, `skipped_due_to_dependency`, or runnable.
- Remaining Session Breakdown: retained entries are accepted/covered closure ledger entries only; no unresolved implementation, tests-only, evidence, or dependency session remains.
- Dependency pass and downstream execution path: execution set is empty, no dependency blocker remains, and future gate guidance is maintenance-only.
- Test inventory references: `test-inventory.md` records the failed-inbox direct/relay retry tests, the renamed resume inbox retry wording, and the `./scripts/run_test_gates.sh intro` 204-test evidence for `INTRO-REL-015`; this verdict additionally records the explicit-device transport gate and targeted pass-fallback simulator smoke evidence.

Required evidence confirmed:

- Flutter-owned rows have direct touched-test or direct evidence-sweep evidence plus `./scripts/run_test_gates.sh intro` evidence recorded in the source matrix and breakdown.
- `INTRO-REL-006`, `INTRO-REL-007`, `INTRO-REL-010`, and `INTRO-REL-015` have row-specific plan files and direct test/gate evidence recorded.
- `INTRO-REL-013` is covered by relay target-scoped dedupe tests `TestInboxStoreDedup_SameIdDifferentRecipient` and `TestRedisInboxBackend_DedupesByMessageIDPerRecipient`, with `cd go-relay-server && go test .` recorded as passing.
- `INTRO-REL-015` records RED proof, the full direct file passing with 11 tests, scoped `git diff --check`, `./scripts/run_test_gates.sh intro` passing with 204 tests, `FLUTTER_DEVICE_ID=347FB118-10D0-40C8-A05B-B0C3BD6B8CCD ./scripts/run_test_gates.sh transport` passing, and `INTRO_E2E_SCENARIO=pass-fallback ./smoke_test_friends.sh` passing with `Intro E2E harness passed`.

Accepted differences:

- Evidence-mapped rows do not need new TOP_15 plan files because their exact direct automated evidence and gate results are recorded in the matrix and breakdown.
- Host-side deterministic tests are accepted for terminal-state, sender-binding, persistence, and retry-orchestration rows where they directly assert the row contract.
- `INTRO-REL-015` uses host tests as the primary row proof, with conditional transport and targeted simulator gates now added as release-confidence evidence.

Maintenance gates:

- For future Flutter-owned introduction changes, run the directly touched tests plus `./scripts/run_test_gates.sh intro`.
- For future relay dedupe changes affecting `INTRO-REL-013`, run `cd go-relay-server && go test .`.
- Add `./scripts/run_test_gates.sh transport`, `./scripts/run_test_gates.sh reliability-sim intro`, or targeted simulator E2E only when future work changes real transport, relay/inbox, resume ordering, reliability simulation, or simulator-visible behavior.
- Keep `test-inventory.md` in sync when new intro reliability tests become durable suite evidence.

Reopen conditions:

- Any `INTRO-REL-*` source row no longer reads `Covered` or `Closed` with concrete evidence.
- Any accepted/covered ledger row no longer reconciles with the source matrix, source test names, plan evidence, or inventory references.
- A direct row-owned regression, `./scripts/run_test_gates.sh intro` regression, or relay dedupe regression invalidates recorded evidence.
- `INTRO-REL-015` failed-inbox retry stops delivering through acknowledged direct/relay paths, stops clearing delivered outbox rows, regresses the explicit-device transport gate, or regresses the targeted pass-fallback simulator smoke.
