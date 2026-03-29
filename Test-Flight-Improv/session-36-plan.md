# Session 36 Plan: Direct CLI-Backed Post-Verify Residual Reds

## Final verdict
`implementation-ready`

Reviewer outcome: sufficient with one contract guard. Repo evidence shows the remaining direct-run reds are post-verify proof-retention and stale-verifier issues in the standalone orchestrator, not new shared transport regressions. The only place where fresh reproduction still matters is `RECV-A6`: if the reproduced run still offers no durable receiver-side proof surface for that scenario, the plan must retire or downgrade the stale post-verify red instead of inventing sender-side proxy proof.

## Final plan

### real scope
- Fix only the residual post-verify reds from the standalone direct command: `E8`, `RECV-A1`, `RECV-A4`, `RECV-A6`.
- Primary edit target: `integration_test/scripts/run_transport_e2e.dart`.
- Conditional edit target only if the reproduced `A6` seam proves it is required: `integration_test/transport_e2e_test.dart`.
- Conditional new helper/test files are allowed only if needed to unit-test extracted post-verify parsing logic.
- Do not change shared Flutter 1:1 production code, Go transport semantics, relay/media behavior, or the testpeer collector lifecycle unless fresh evidence disproves the current script-only diagnosis.

### closure bar
- `dart run integration_test/scripts/run_transport_e2e.dart -d <device-id>` finishes without `E8`, `RECV-A1`, `RECV-A4`, or `RECV-A6` red in the orchestrator summary.
- `E8` passes from actual receiver-side proof even when Flutter sends it via `inbox` rather than a live collector-visible stream.
- `RECV-A1` and `RECV-A4` no longer depend on the final `get_messages` collector snapshot after stop/restart cycles.
- `RECV-A6` is either proven from a real retained receiver-side proof surface or explicitly removed/downgraded as a stale post-verify contract that no longer matches the authoritative Flutter-side scenario.
- The named `transport` gate still passes, but direct CLI-backed validation remains the closure proof.

### source of truth
- Current direct-run evidence: `/tmp/session34_direct_run.log`.
- Active residual classification: `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`.
- Active closure/audit context: `Test-Flight-Improv/17-roadmap-closure-audit.md`.
- Authoritative Flutter scenario contracts: `integration_test/transport_e2e_test.dart`.
- Residual verifier implementation: `integration_test/scripts/run_transport_e2e.dart`.
- Gate execution source of truth: `scripts/run_test_gates.sh`.
- Gate explanation only: `Test-Flight-Improv/test-gate-definitions.md`.
- If these disagree, current code plus the reproduced direct-run evidence beats stale verifier assumptions.

### session classification
- `implementation-ready`

### exact problem statement
- `E8` is a false red in the current direct run because the orchestrator only searches the final live collector via `get_messages`, but the reproduced run shows Flutter sent `E8` with `via":"inbox"` and the later `G3` `inbox_retrieve` response still contained the exact `E8` envelope while `media_download` succeeded.
- `RECV-A1` and `RECV-A4` are false reds because the CLI process already emitted `message:received` async events for both messages early in the run, but the orchestrator throws away that proof and instead verifies against `get_messages` after `C1` and `B8` stop/restart cycles recreated the testpeer collector.
- `RECV-A6` is currently a stale or unsupported post-verify check. In the reproduced run, Flutter `A6` passed with `connected=false status=delivered` and sender-side `via":"inbox"`, while the final verifier still insisted on a retained raw CLI collector envelope. That mismatch must be resolved by real retained receiver-side proof if one exists, or by retiring/downgrading the stale post-verify red if it does not.
- User-visible behavior that must improve: the standalone direct command should stop reporting false post-verify regressions once the authoritative scenario contracts have already passed.
- Must stay unchanged: shared 1:1 delivery semantics, honest transport labels, inbox fallback behavior, named gate membership, and the testpeer node lifecycle semantics.

### files and repos to inspect next
- `integration_test/scripts/run_transport_e2e.dart`
- `integration_test/transport_e2e_test.dart`
- `/tmp/session34_direct_run.log`
- `Test-Flight-Improv/session-34-plan.md`
- `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`
- `Test-Flight-Improv/17-roadmap-closure-audit.md`
- `scripts/run_test_gates.sh`
- `Test-Flight-Improv/test-gate-definitions.md`
- Evidence-only CLI lifecycle references: `go-mknoon/cmd/testpeer/commands.go`, `go-mknoon/cmd/testpeer/listener.go`

### existing tests covering this area
- The only real end-to-end proof surface for these residuals is the standalone direct command: `dart run integration_test/scripts/run_transport_e2e.dart -d <device-id>`.
- `integration_test/transport_e2e_test.dart` already defines the authoritative Flutter-side scenario contracts for `A1`, `A4`, `A6`, and `E8`.
- There is no existing unit-test seam for the post-verify logic in `run_transport_e2e.dart`.
- `go-mknoon/cmd/testpeer/commands_test.go` covers `get_messages`, `clear_messages`, and command validation basics, but not orchestrator proof retention across stop/restart.
- `./scripts/run_test_gates.sh transport` does not prove these residuals on its own when no CLI fixture/orchestrator is active.

### regression/tests to add first
- First add a small pure-Dart regression only if the implementation extracts post-verify parsing/aggregation helpers out of `run_transport_e2e.dart`. The narrow target is a helper test that proves:
  - retained async `message:received` evidence survives later collector resets for `RECV-A1` / `RECV-A4`,
  - inbox-retrieved envelopes can satisfy `E8` when live collector evidence is absent,
  - `RECV-A6` classification does not fabricate proof when no retained receiver-side evidence exists.
- If no helper extraction is needed, do not invent a broad new test harness. The regression-first proof is the reproduced direct CLI-backed run itself, because that is the only existing deterministic seam for these residuals.
- If execution evidence shows `A6` requires a new explicit Flutter signal, add the smallest direct regression in `integration_test/transport_e2e_test.dart` before changing the script contract.

### step-by-step implementation plan
1. Reproduce the direct CLI-backed run once and capture the exact proof sources for the four residuals:
   - confirm `A1` and `A4` still emit async `message:received` events from the CLI process,
   - confirm `G3` or an earlier `inbox_retrieve` still contains the `E8` envelope carrying the blob metadata,
   - determine whether `A6` appears in any durable receiver-side proof surface at all during the run.
   Stop and rescope if the reproduced run contradicts the current session-34 evidence.
2. In `integration_test/scripts/run_transport_e2e.dart`, add an orchestrator-side durable evidence buffer for Flutter-to-CLI envelopes. It should persist in the Dart script process and append evidence from:
   - async `message:received` events parsed in `TestPeer._handleLine`,
   - any `inbox_retrieve` responses the orchestrator already performs (`C1`, `B8`, `G3`, and any narrow new retrieval needed for `E8`).
   Do not rely on the testpeer collector surviving `stop` / `start`.
3. Refactor `E8` verification to search the durable evidence buffer first, including inbox-retrieved raw envelopes, and keep receiver-side `media_download` success as a required proof. `media_list` remains diagnostic only.
4. Refactor `RECV-A1` and `RECV-A4` verification to read from the durable orchestrator evidence buffer instead of the final `get_messages` collector snapshot.
5. Resolve `RECV-A6` from reproduced evidence:
   - if a real retained receiver-side envelope exists in async events or inbox retrievals, verify it from that buffer;
   - if no such proof exists and the active Flutter contract remains sender-side delivered status only, retire or downgrade the stale `RECV-A6` hard red instead of adding fake proof or widening into shared send behavior changes.
6. Only if the script becomes too tangled to verify safely, extract the narrow post-verify parsing logic into a helper and add the small pure-Dart regression described above. Keep the execution surface and scenario order otherwise unchanged.
7. Run the exact direct command and named gate below. If the only remaining direct-command failure is a newly disproved `A6` proof assumption, stop and reopen planning instead of broadening scope.

### risks and edge cases
- `E8` can legitimately succeed via inbox; a verifier that only watches the live collector will continue to false-fail.
- `A1` / `A4` live async events happen early in the run and are currently lost only because the script never retains them independently of the testpeer collector.
- `A6` may have no durable receiver-side proof surface in the current architecture once it succeeds via inbox and the later run phases consume or bypass that state. The plan must allow narrowing or deleting the stale hard red if the evidence proves that.
- Pulling `inbox_retrieve` earlier for proof can consume inbox messages; if that is needed for `E8`, keep `G3` success criteria count-agnostic.
- Event/inbox evidence aggregation must filter only Flutter-originated CLI receipts to avoid false positives from orchestrator-to-Flutter traffic or later reply traffic.
- Do not let a convenience refactor turn into a full orchestrator rewrite.

### exact tests and gates to run
- If a helper extraction test is added: `flutter test test/integration_scripts/transport_orchestrator_postverify_test.dart`
- Required named gate: `FLUTTER_DEVICE_ID=<device-id> ./scripts/run_test_gates.sh transport`
- Required direct proof: `dart run integration_test/scripts/run_transport_e2e.dart -d <device-id>`
- Optional auto-detect form only when a fixed device id is not required: `dart run integration_test/scripts/run_transport_e2e.dart -p ios`
- Only if `go-mknoon/cmd/testpeer/commands.go` changes, which this plan does not currently expect: `cd go-mknoon && go test ./cmd/testpeer`

### known-failure interpretation
- Treat only `E8`, `RECV-A1`, `RECV-A4`, and `RECV-A6` as the in-scope red set for this session.
- A run where the Flutter transport matrix passes but the orchestrator summary still shows these four post-verify reds is the exact target bug surface for this session.
- A plain `./scripts/run_test_gates.sh transport` pass without the direct CLI-backed command does not close this session.
- If fresh reproduction shows `RECV-A6` has no real receiver-side proof surface and the Flutter-side contract still passes, that is evidence for stale verifier cleanup, not evidence for changing shared transport code.

### done criteria
- The standalone direct command no longer reports `E8`, `RECV-A1`, `RECV-A4`, or `RECV-A6` as red.
- `E8` passes from real retained receiver evidence plus successful CLI-side media download, even when the sender used inbox fallback.
- `RECV-A1` and `RECV-A4` pass from retained async-event or inbox evidence that survives node restart and collector reset.
- `RECV-A6` is either proven from a real retained receiver-side evidence surface or explicitly removed/downgraded because the authoritative contract no longer guarantees such proof.
- `./scripts/run_test_gates.sh transport` still passes after the orchestrator changes.
- No shared Flutter production send/receive code or Go transport code changes unless fresh evidence disproves this script-only diagnosis.

### scope guard
- Non-goals: changing `send_chat_message_use_case.dart`, `p2p_service_impl.dart`, relay media semantics, test gate membership, or the broader transport matrix.
- Overengineering to avoid: making the named gate run the orchestrator automatically, rewriting the whole script around a new architecture, persisting proof in the Go testpeer binary when the Dart orchestrator can retain it, or adding sender-side proxy signals just to make a red line disappear.
- Must not change: honest transport semantics, inbox success semantics, Session 34’s closed seams, or the CLI node’s stop/start lifecycle behavior unless evidence proves that lifecycle itself is wrong.

### accepted differences / intentionally out of scope
- The direct CLI-backed command remains a separate maintenance-time proof in addition to the named `transport` gate.
- The testpeer collector may continue resetting on `stop` / `start`; this session fixes the orchestrator’s proof retention instead of changing the CLI binary’s lifecycle contract.
- If `RECV-A6` is proven stale, the accepted result is a narrower post-verify contract, not a demand that every delivered Flutter send also leave a durable CLI-side collector envelope.
- No closure docs or index updates belong in this planning session.

### dependency impact
- This session is the prerequisite for claiming the standalone direct CLI-backed transport command is fully green again instead of “green except residual post-verify reds.”
- A later execution/QA session can stay narrow if this plan holds: it should touch only the orchestrator proof logic unless the reproduced `A6` evidence forces a very small Flutter-side signal change.
- Closure/audit docs should not be updated until the direct command is green without the four residual reds.

## Reviewer pass
- Verdict: sufficient with adjustments.
- Adjustment applied: `RECV-A6` cannot force a new proof mechanism if fresh reproduction still shows no real retained receiver-side evidence surface; the plan now makes stale-check retirement an allowed safe outcome instead of assuming an implementation exists.
- Missing source-of-truth gap patched: the plan now treats `/tmp/session34_direct_run.log` as concrete evidence for the current residual behavior instead of inferring from the closure docs alone.

## Arbiter pass
- Structural blockers: none.
- Incremental detail: if execution extracts a pure helper to make the new regression practical, keep that helper local to the orchestrator script area and do not broaden into reusable framework code.
- Accepted difference: the direct command stays a separate proof path from the named gate.

## Structural blockers remaining
- None.

## Incremental details intentionally deferred
- Any doc/index closure updates for the residual session after implementation.
- Any refactor of unrelated post-verify or group/announcement orchestrator logic.
- Any change to `go-mknoon/cmd/testpeer/commands.go` unless script-level proof retention is unexpectedly insufficient.

## Accepted differences intentionally left unchanged
- Session 34’s closed seams remain closed and should not be reopened by this work.
- The CLI testpeer collector lifecycle remains reset-on-stop/restart.
- The direct CLI-backed orchestrator remains the only authoritative proof for these residuals.

## Exact docs/files used as evidence
- `/tmp/session34_direct_run.log`
- `integration_test/scripts/run_transport_e2e.dart`
- `integration_test/transport_e2e_test.dart`
- `go-mknoon/cmd/testpeer/commands.go`
- `go-mknoon/cmd/testpeer/listener.go`
- `Test-Flight-Improv/session-34-plan.md`
- `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`
- `Test-Flight-Improv/17-roadmap-closure-audit.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `scripts/run_test_gates.sh`

## Why the plan is safe or unsafe to implement now
- Safe to implement now because the evidence points to one narrow orchestrator seam: proof is already observable for `A1`, `A4`, and `E8`, but the script either discards it or looks in the wrong place after lifecycle resets. The only ambiguous case, `RECV-A6`, has an explicit reproduce-first stop rule so execution does not invent a fake receiver guarantee or spill into unrelated transport code.
