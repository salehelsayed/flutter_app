# RSD-001 - NET-REL-03 Evidence Gate And Proceed/Defer Decision

Status: accepted

## Planning Progress

- 2026-05-30 09:24:53 CEST - Controller local plan fallback. Files inspected since last update: `Test-Flight-Improv/101-relay-springboard-direct-escalation-session-breakdown.md`, `Test-Flight-Improv/101-relay-springboard-direct-escalation.md`, `Test-Flight-Improv/NET-REL-04-baseline-decision-gate.md`, `Test-Flight-Improv/100-nat-traversal-dcutr-evidence.md`, `Test-Flight-Improv/100-nat-traversal-dcutr-evidence-session-DCUTR-004-plan.md`, `Test-Flight-Improv/99-transport-observability-and-metrics-HARVEST-DECISION.md`, `Network-Arch/Transport-Reliability/00-INDEX.md`, `Network-Arch/Transport-Reliability/02-nat-traversal-dcutr.md`, and `Network-Arch/Transport-Reliability/03-relay-springboard.md`. Decision/blocker: spawned planner wrote intake but stalled before an executable plan; current repo evidence is enough for a bounded evidence-gated plan. Next action: execute evidence search, device availability check, doc decision update, and `git diff --check`.

## Execution Progress

- 2026-05-30 09:26:30 CEST - Execution QA orchestrator - Before contract extraction. Files inspected: `Test-Flight-Improv/101-relay-springboard-direct-escalation-session-RSD-001-plan.md`, `Test-Flight-Improv/101-relay-springboard-direct-escalation-session-breakdown.md`, `git status --short`. Command currently running: none. Decision/blocker: beginning RSD-001 only; dirty worktree contains pre-existing unrelated transport/doc changes that must be preserved. Next action: extract the plan contract before any evidence edits.
- 2026-05-30 09:26:39 CEST - Execution QA orchestrator - Contract extracted. Files inspected: `Test-Flight-Improv/101-relay-springboard-direct-escalation-session-RSD-001-plan.md`, `Test-Flight-Improv/101-relay-springboard-direct-escalation-session-breakdown.md`. Command currently running: none. Decision/blocker: scope is docs/evidence only; no production code, migrations, or tests may change; valid proceed requires an existing real physical-device, discovery-enabled, debug-mode, 1:1 baseline harvest with raw delivered transport counts, hole-punch attempt/success/failure counts, relay-to-direct upgrade count, and cross-network/co-location decision-gate metadata. Next action: spawn the bounded Executor pass to run live device checks first, then search evidence and update allowed docs.
- 2026-05-30 09:27:14 CEST - Executor - Before Device/Relay Proof Profile checks. Files inspected: `Test-Flight-Improv/101-relay-springboard-direct-escalation-session-RSD-001-plan.md`. Command currently running: none. Decision/blocker: contract extracted; live inventory checks must run before any new device-backed proof claim, and simulator inventory is supporting only. Next action: run `git status --short`, `flutter devices --machine`, and `xcrun simctl list devices available`.
- 2026-05-30 09:27:43 CEST - Executor - After Device/Relay Proof Profile checks. Files inspected: `Test-Flight-Improv/101-relay-springboard-direct-escalation-session-RSD-001-plan.md`. Commands completed: `git status --short`, `flutter devices --machine`, `xcrun simctl list devices available`. Decision/blocker: dirty worktree has extensive pre-existing modified/untracked transport and rollout files; live Flutter inventory shows three physical mobile devices (`Pixel 6` `21071FDF600CSC`, `Saleh's iPhone` `00008030-001A6D2801BB802E`, `iPhone` `00008110-00184D622289801E`) plus simulators/macOS/Chrome; simulator inventory lists booted iOS 26.1 simulators and shutdown iOS 26.2/26.5 simulators. Physical devices alone do not satisfy the required already-captured 1:1 relay-to-direct harvest artifact. Next action: search repo evidence for the exact valid harvest fields.
- 2026-05-30 09:27:55 CEST - Executor - Before harvest evidence search. Files inspected: `Test-Flight-Improv/101-relay-springboard-direct-escalation-session-RSD-001-plan.md`. Command currently running: none. Decision/blocker: search must accept only an existing physical-device, discovery-enabled, debug-mode, 1:1-focused baseline harvest with delivered transport counts, hole-punch counts, relay-to-direct upgrades, cross-network/co-location metadata, and decision-gate context. Next action: inspect the source docs and targeted artifact terms.
- 2026-05-30 09:28:47 CEST - Executor - After harvest evidence search / before doc edits. Files inspected: `Test-Flight-Improv/NET-REL-04-baseline-decision-gate.md`, `Test-Flight-Improv/NET-REL-04-baseline-harvest-runbook.md`, `Test-Flight-Improv/99-transport-observability-and-metrics-HARVEST-DECISION.md`, `Test-Flight-Improv/100-nat-traversal-dcutr-evidence.md`, `Test-Flight-Improv/100-nat-traversal-dcutr-evidence-session-DCUTR-003-plan.md`, `Test-Flight-Improv/100-nat-traversal-dcutr-evidence-session-DCUTR-004-plan.md`, `Test-Flight-Improv/101-relay-springboard-direct-escalation.md`, `Test-Flight-Improv/101-relay-springboard-direct-escalation-session-breakdown.md`, `Network-Arch/Transport-Reliability/00-INDEX.md`, `Network-Arch/Transport-Reliability/02-nat-traversal-dcutr.md`, and `Network-Arch/Transport-Reliability/03-relay-springboard.md`; targeted `rg` terms searched across `Test-Flight-Improv` and `Network-Arch`. Command currently running: none. Decision/blocker: no valid existing harvest artifact was found. The closest docs record physical-device boot/classification and accepted host/simulator/Go relay-only evidence, but they either lack the copied `baselineReport()`/decision-gate raw counts, lack hole-punch attempt/success/failure plus relay-to-direct upgrade counts, lack cross-network/co-location metadata, or explicitly state production mobile DCUtR remains unproven. Next action: update only allowed RSD-001 docs with defer/no-proceed and keep RSD-002/RSD-003 prerequisite-blocked.
- 2026-05-30 09:29:39 CEST - Controller local execution fallback - Harvest evidence search and docs update. Files inspected/touched: `Test-Flight-Improv/101-relay-springboard-direct-escalation.md`, `Network-Arch/Transport-Reliability/03-relay-springboard.md`, `Test-Flight-Improv/NET-REL-04-baseline-decision-gate.md`, `Network-Arch/Transport-Reliability/00-INDEX.md`, and this plan. Commands completed: `flutter devices --machine`, `xcrun simctl list devices available`, targeted `rg` evidence search. Decision/blocker: no valid copied real-device, discovery-enabled, debug-mode 1:1 `baselineReport()`/decision-gate artifact with required transport counts, hole-punch counts, relay-to-direct upgrade count, and cross-network metadata was found. Next action: run `git diff --check` and QA the doc-only no-proceed result.
- 2026-05-30 09:30:23 CEST - Controller local execution fallback - Validation and QA completed. Files inspected/touched: same RSD-001 doc scope; no production code or test files were edited by RSD-001. Commands completed: `git diff --check` passed. Decision/blocker: `Test-Flight-Improv/test-gate-definitions.md` was not changed, so `./scripts/run_test_gates.sh completeness-check` was not required. Final execution verdict: accepted. Next action: session closure.

## real scope

RSD-001 decides whether NET-REL-03 relay springboard implementation may proceed now. The executor must inspect current repo evidence for a valid real-device, discovery-enabled, debug-mode, 1:1-focused baseline harvest with direct/relay/wifi/inbox/unknown counts, hole-punch attempt/success/failure counts, relay-to-direct upgrade count, and enough metadata to satisfy `Test-Flight-Improv/NET-REL-04-baseline-decision-gate.md`.

If the valid harvest artifact is absent, record a defer/no-proceed decision and keep RSD-002/RSD-003 prerequisite-blocked. This session is docs/evidence only: no production code, tests, migrations, reachability policy, routing policy, WebRTC/TURN/STUN, relay-server protocol, AutoRelay, or Go send-path changes.

## closure bar

The session is complete when the current repo state has a concrete proceed/defer decision for NET-REL-03:

- valid harvest found: cite the exact artifact and fields that satisfy the decision gate, then record the allowed proceed boundary for later RSD-002/RSD-003 planning without implementing it here.
- valid harvest absent: record that production mobile relay-to-direct DCUtR success remains unproven, NET-REL-03 implementation is deferred, and RSD-002/RSD-003 remain prerequisite-blocked.
- source and stable docs must continue distinguishing relay delivery, LAN/direct-address delivery, loopback feasibility, stream-label mapping, and real relay-to-direct upgrade.
- no code or test file changes are allowed in this session.

## source of truth

- Primary session contract: `Test-Flight-Improv/101-relay-springboard-direct-escalation-session-breakdown.md`.
- Product/source doc: `Test-Flight-Improv/101-relay-springboard-direct-escalation.md`.
- Decision gate: `Test-Flight-Improv/NET-REL-04-baseline-decision-gate.md`.
- Harvest/runbook context: `Test-Flight-Improv/NET-REL-04-baseline-harvest-runbook.md` and `Test-Flight-Improv/99-transport-observability-and-metrics-HARVEST-DECISION.md`.
- Adjacent accepted evidence: `Test-Flight-Improv/100-nat-traversal-dcutr-evidence.md` and `Test-Flight-Improv/100-nat-traversal-dcutr-evidence-session-DCUTR-004-plan.md`.
- Stable NET-REL docs: `Network-Arch/Transport-Reliability/00-INDEX.md`, `Network-Arch/Transport-Reliability/02-nat-traversal-dcutr.md`, and `Network-Arch/Transport-Reliability/03-relay-springboard.md`.
- Gate definitions: `Test-Flight-Improv/test-gate-definitions.md`.

Current code/tests beat stale prose if they conflict, but this session should not inspect code beyond validating already-cited evidence because the action is a decision gate, not implementation.

## session classification

evidence-gated

## exact problem statement

NET-REL-03 should not implement relay springboard direct escalation until the repo contains trustworthy evidence that production-shaped mobile 1:1 relay-to-direct upgrades are possible and worth pursuing. Existing docs and accepted DCUTR evidence show tracer/diagnostic and relay-only safety coverage, but they also state that production mobile DCUtR success remains unproven without a valid baseline harvest.

User-visible behavior must stay honest: relay-backed 1:1 delivery remains successful, direct must not be claimed from a stream label or LAN/loopback proof alone, and later implementation must not add repeated direct-attempt churn against unpunchable relay-only peers.

## Device/Relay Proof Profile

- Profile classification for this run: external-fixture-blocked unless execution finds an existing valid harvest artifact on disk.
- Required proof for a proceed verdict: a real physical-device, discovery-enabled, debug-mode, 1:1-focused baseline harvest with raw delivered transport counts (`direct`, `relay`, `wifi`, `inbox`, `unknown`), hole-punch attempt/success/failure counts, relay-to-direct upgrade count, cross-network/co-location metadata, and decision-gate validity context.
- Live availability checks to run during execution before claiming any new device-backed proof:
  - `flutter devices --machine`
  - `xcrun simctl list devices available` only as supporting simulator inventory; simulators do not satisfy the production mobile harvest requirement.
- Device ids: do not assume configured default simulator ids satisfy this row. A single `FLUTTER_DEVICE_ID` gate is not sufficient closure evidence for this row.
- Required closure evidence: an already-captured valid harvest artifact, or an explicit missing-fixture/defer decision. Execution should not attempt a new manual two-phone harvest unless the valid artifact already exists or the user provides the physical-device fixture during the run.
- Relay addresses: existing deployed relay references may support liveness context, but they do not prove relay-to-direct upgrade without the required harvest fields.

## files and repos to inspect next

- `Test-Flight-Improv/NET-REL-04-baseline-decision-gate.md`
- `Test-Flight-Improv/NET-REL-04-baseline-harvest-runbook.md`
- `Test-Flight-Improv/99-transport-observability-and-metrics-HARVEST-DECISION.md`
- `Test-Flight-Improv/100-nat-traversal-dcutr-evidence.md`
- `Test-Flight-Improv/100-nat-traversal-dcutr-evidence-session-DCUTR-004-plan.md`
- `Test-Flight-Improv/101-relay-springboard-direct-escalation.md`
- `Network-Arch/Transport-Reliability/00-INDEX.md`
- `Network-Arch/Transport-Reliability/02-nat-traversal-dcutr.md`
- `Network-Arch/Transport-Reliability/03-relay-springboard.md`
- `Test-Flight-Improv/test-gate-definitions.md` only if execution changes test/gate classifications.

## existing tests covering this area

No new test should be added for RSD-001. Adjacent accepted evidence is already recorded in DCUTR docs and includes:

- Go tracer/counter and anti-false-upgrade tests around `holepunch:attempt`, `holepunch:success`, `holepunch:failure`, and `transport:upgraded`.
- Dart bridge/metrics/settings diagnostic tests that surface aggregate hole-punch and relay-to-direct counters without privacy leakage.
- Relay-only/no-upgrade negative control and relay recovery/liveness evidence.

These tests support truthfulness and safety. They do not replace the required production mobile baseline harvest.

## regression/tests to add first

None. This is an evidence/doc decision session. Adding production tests or implementation code would be scope expansion. If execution discovers a missing repo-owned behavior proof that belongs to RSD-002/RSD-003, it must record the prerequisite/defer decision rather than implementing it in RSD-001.

## step-by-step implementation plan

1. Snapshot dirty state with `git status --short` and preserve unrelated existing changes.
2. Run the live device inventory check from the Device/Relay Proof Profile:
   - `flutter devices --machine`
   - `xcrun simctl list devices available` if available and useful for inventory only.
3. Search for a valid harvest artifact:
   - Inspect the source, decision-gate, harvest runbook, HARVEST-DECISION, DCUTR evidence, and NET-REL docs listed above.
   - Use targeted search for `baselineReport`, `direct/relay/wifi/inbox/unknown`, `hole-punch`, `relay-to-direct`, `transport:upgraded`, `debug-mode`, `discovery-enabled`, and `real-device`.
   - Accept only an artifact with the required production mobile 1:1 fields and decision-gate metadata.
4. If a valid artifact exists, update the source and NET-REL docs with the exact artifact path, required fields, and allowed proceed boundary for later sessions. Do not implement RSD-002/RSD-003.
5. If no valid artifact exists, update the source and NET-REL docs with a clear RSD-001 defer decision:
   - production mobile relay-to-direct DCUtR success remains unproven,
   - NET-REL-03 implementation is deferred,
   - RSD-002 and RSD-003 remain prerequisite-blocked,
   - RSD-004 may close the rollout as evidence-gated/residual-only or still-open according to final program policy.
6. Update `Test-Flight-Improv/test-gate-definitions.md` only if execution changes a test/gate classification. Otherwise leave it untouched.
7. Run `git diff --check`.
8. Review the diff for scope: allowed files are this plan and the current 101/NET-REL evidence docs. Any production code or test changes are out of scope and blocking unless separately justified as pre-existing.
9. Write a compact execution verdict in this plan under `## Execution Progress`, including the decision, exact docs changed, device inventory result, harvest search result, and tests/gates run.

## risks and edge cases

- A real-hardware transport mechanism proof is not automatically a valid NET-REL-03 production mobile relay-to-direct harvest.
- `99-transport-observability-and-metrics-HARVEST-DECISION.md` may contain useful real-device context but still fail this row if it lacks paired 1:1 baseline counts and relay-to-direct upgrade proof.
- Simulator, CLI, loopback, LAN direct, or stream-label evidence can support liveness/classifier/feasibility only; do not use it as production mobile DCUtR proof.
- The dirty worktree already contains unrelated transport and doc changes. Do not revert or normalize them.
- If the valid harvest is absent, this is not a product failure in RSD-001; it is the evidence-gated defer outcome the breakdown anticipates.

## exact tests and gates to run

Required:

```bash
flutter devices --machine
git diff --check
```

Supporting inventory only when available:

```bash
xcrun simctl list devices available
```

Conditional only if `Test-Flight-Improv/test-gate-definitions.md` changes or a new test is classified:

```bash
./scripts/run_test_gates.sh completeness-check
```

No Flutter named gate, Go test, or integration test is required if execution remains docs/evidence-only and does not edit gate definitions.

## known-failure interpretation

Pre-existing known red or residual evidence from adjacent docs does not block RSD-001 unless it directly contradicts the decision-gate inputs. The repeated DCUTR-003 `run_transport_e2e.dart` E8 media metadata residual is external/orchestrator evidence and does not prove or disprove production mobile relay-to-direct upgrade. Missing physical devices or missing valid harvest should be recorded as an external-fixture/evidence-gate blocker for proceeding, not as a failed implementation test.

## done criteria

- `RSD-001` has a documented proceed/defer decision grounded in current repo evidence.
- If defer/no valid harvest, docs explicitly prevent RSD-002/RSD-003 implementation from proceeding now.
- If proceed, docs cite a valid harvest artifact and exact proceed boundary for later sessions without implementing later sessions.
- Device inventory and harvest search results are recorded.
- `git diff --check` passes, or any failure is triaged as unrelated/pre-existing or blocking.
- No production code, migrations, or tests are changed.
- Execution verdict is `accepted` only when all required doc/evidence updates and commands are complete.

## scope guard

Do not implement relay springboard policy, direct escalation, send migration, cooldown/backoff, route selection, WebRTC/TURN/STUN, AutoRelay, relay-server changes, bridge payload changes, UI changes, or new tests in RSD-001. Do not reclassify simulator/loopback/LAN/direct-label evidence as production mobile relay-to-direct proof. Do not edit unrelated rollout docs or later-session plan paths.

## accepted differences / intentionally out of scope

- Relay remains a correct steady state for many cellular, symmetric-NAT, CGNAT, or otherwise unpunchable pairs.
- A stream label of `direct`, LAN/pre-relay direct dial, loopback feasibility result, or simulator/CLI liveness proof is not production mobile relay-to-direct proof.
- A missing valid harvest defers implementation; it does not require RSD-001 to invent policy or collect a new manual two-phone harvest.

## dependency impact

- RSD-002 may run only if RSD-001 records a proceed verdict and names an allowed policy boundary.
- RSD-003 may run only after RSD-001 proceeds and RSD-002 is accepted.
- RSD-004 should run after RSD-001 to reconcile the final program verdict. If RSD-001 defers implementation, RSD-004 should close or classify the rollout based on that evidence-gated residual without executing RSD-002/RSD-003.

## Final Planning Verdict

Final verdict: execution-ready via controller local plan fallback.

Structural blockers remaining: none for executing RSD-001 as an evidence/doc decision gate. The likely product blocker is the missing valid production mobile harvest; execution must verify and record it.

Incremental details intentionally deferred: no new harvest collection, no implementation policy, and no test additions in this session.

Accepted differences intentionally left unchanged: relay-only success, LAN/direct-label/loopback proof limits, and production reachability privacy remain unchanged.

## Final Execution Verdict

Final verdict: accepted.

Spawned-agent isolation used: partial. The outer controller spawned a fresh execution/QA child with `model: gpt-5.5` and `reasoning_effort: xhigh`; that child recorded contract and device-check progress but stalled during the nested Executor harvest-search phase. The outer pipeline used its single current-session local execution fallback to complete the evidence/doc-only contract.

Local execution fallback used: yes.

Files changed by RSD-001: this plan, `Test-Flight-Improv/101-relay-springboard-direct-escalation.md`, `Network-Arch/Transport-Reliability/03-relay-springboard.md`, `Test-Flight-Improv/NET-REL-04-baseline-decision-gate.md`, and `Network-Arch/Transport-Reliability/00-INDEX.md`.

Tests/gates run: `flutter devices --machine`, `xcrun simctl list devices available`, targeted `rg` evidence searches, and `git diff --check` (passed). `./scripts/run_test_gates.sh completeness-check` was not run because `Test-Flight-Improv/test-gate-definitions.md` was not changed.

Decision: no proceed verdict for relay springboard implementation. Physical devices are available, but no valid captured real-device, discovery-enabled, debug-mode 1:1 baseline harvest artifact exists in the repo. RSD-002/RSD-003 remain prerequisite-blocked; RSD-004 should close the rollout against this evidence-gated residual.

## Final Closure Verdict

Closure verdict: accepted for RSD-001.

RSD-001 is complete as an evidence-gate session: it records a no-proceed decision, preserves the distinction between relay delivery, LAN/direct-address delivery, loopback feasibility, stream-label mapping, and real relay-to-direct upgrade, and leaves production code/tests unchanged. The only follow-up is outside this session: capture a valid NET-REL-04 baseline harvest before reopening RSD-002/RSD-003.
