# 188 - DCUtR-1:1 relay→direct upgrade: honest host-ceiling closure (Option A / Path 3)  (Verification / closure)

Status: **EXECUTED 2026-07-01** (was: awaiting-review; grounded via 2 verify→refute workflows). 3 guard tests landed GREEN-on-HEAD + mutation-verified (all mutations reverted, worktree-isolated); CV-10/11/12 closed at the host ceiling + CV-13/CV-30/P4.4-flag-row re-scoped in the checklist; spec stamped. NO production code changed.
Spec: `Test-Flight-Improv/188-dcutr-1to1-forced-circuit-verification-spec.md` (**premise revised — see Root Cause**)

## Planning Progress
| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-07-01 | Evidence Collector (wf `b0ea0dc5`) | send/warm path, node.go, inbox.go, holepunch_tracer.go, FDC-02/11/12 docs | verdict: store-and-forward by design; DCUtR-1:1 dead machinery | Option A chosen |
| 2026-07-01 | Evidence Collector (wf `77ef6f8d`) | go-libp2p holepunch (svc/holepuncher/tracer), node.go seams, holepunch_*_test.go | **deterministic loopback DCUtR-punch gate is NOT achievable** (punch is probabilistic; loopback short-circuits to a non-DCUtR direct dial) | Path 3 |
| 2026-07-01 | Planner | holepunch_tracer.go + holepunch_tracer_test.go (existing) | tracer mapping already deterministically tested; 3 guard gaps remain; no prod fix | emit plan |
| 2026-07-01 | Reviewer / Arbiter | this plan | see Reviewer Findings / Arbiter | hand off |
| 2026-07-01 | Executor | holepunch_tracer_test.go (+3 guards), checklist CV-10..13/30/P4.4, spec | all 3 GREEN on HEAD; mutation-verified RED (M1 flip-all → TC-188-03; M2 DirectDialEvt→upgrade hack → TC-188-10; M3 unconditional emit → TC-188-11) in an isolated worktree, mutations discarded with it; vet+gofmt clean | run -race gate + adversarial review |

## Source Of Truth
- Spec: `188-…-spec.md` (Path-3-revised). Verdicts: workflows `wf_b0ea0dc5` (store-and-forward) + `wf_77ef6f8d` (no deterministic punch gate).
- Gates: `go-mknoon` uses `GOTOOLCHAIN=go1.25.0`; after any Go run `git checkout -- go-mknoon/testdata/interop_vectors.json`.
- 00-INDEX: 183–187 plans are NOT indexed → 188 follows suit.

## Session Classification
implementation-ready (Go-host only; NO Dart, NO device, NO rig, NO relay deploy — fully executable regardless of the network that blocked the device campaign).

## Exact Problem Statement
DCUtR-for-1:1 is **dead machinery in production** (verdict `wf_b0ea0dc5`): mknoon's 1:1 cross-network transport is **store-and-forward inbox by design**, `warmPeer` deliberately avoids holding a peer circuit, so no `/p2p-circuit` exists for DCUtR to upgrade. CV-10/11/12 can never observe a real 1:1 upgrade on-device and would pass **vacuously**.

**Option A (verify-only) was chosen**, but its original premise — a *deterministic* loopback host test asserting a genuine `markPeerUpgradedToDirect` — is **refuted** (`wf_77ef6f8d`): a real hole-punch is inherently probabilistic (go-libp2p's own e2e punch is non-deterministic), and on loopback `holepuncher.directConnect` short-circuits to a plain forced-dial that is NOT a DCUtR upgrade. **A deterministic genuine-punch host gate cannot exist.**

**Path 3 (chosen): honest closure at the host ceiling.** What must improve: lock the DCUtR *upgrade-observable* semantics deterministically (the parts a host CAN prove) and guard the one dangerous regression the refutation flagged; then re-scope CV-10/11/12 to close on that honest basis. What must stay unchanged: store-and-forward remains the 1:1 prod transport; **no production code changes** (the DCUtR tracer + `markPeerUpgradedToDirect` are already correct); `EnableDcutrUpgrade` stays dark.

## Root Cause (verify → refute confirmed)
- **Deterministic genuine-punch is impossible on loopback** (`wf_77ef6f8d`, verdict `trigger-bypasses-dcutr`): `markPeerUpgradedToDirect` fires only on `EndHolePunchEvt{Success:true}` (`holepunch_tracer.go:63-94`), a real UDP simultaneous-open that lands; `holepuncher.directConnect` short-circuits to `WithForceDirectDial` for any directly-dialable peer (always true on loopback) → `DirectDialEvt`, a **non-counted breadcrumb** (`holepunch_tracer.go:113-120`) that is NOT wired to the upgrade; without a manet-public override `Service.DirectConnect` blocks forever (why the feasibility test `t.Skip`s).
- **The deterministic upgrade-observable machinery is ALREADY correct + tested**: `holepunch_tracer_test.go::TestHolePunchTracer_AttemptThenSuccess_CountsAndEmits` (synthetic `EndHolePunchEvt{Success:true}` on a seeded `Limited` entry → `Successes()==1` + `holepunch:success` + `transport:upgraded`), `..._SuccessClearsStaleLimitedConnectionState` (flips `Limited→false`), `..._FailureAndNoEnd_NoSuccessEmitted` (failure → no upgrade). Negative (`holepunch_negative_control_test.go`) + flag (`dcutr_upgrade_flag_test.go`) are deterministic. Feasibility (`holepunch_feasibility_test.go`, skip-tolerant) is the real-punch *observable* probe.

**Refuted / do-NOT-re-introduce:** (1) a deterministic loopback DCUtR-punch gate; (2) **the tempting hack of wiring `DirectDialEvt{Success:true}` → `markPeerUpgradedToDirect`** to force loopback determinism — that reclassifies every plain direct dial as a DCUtR upgrade (prod-semantics regression) and is explicitly rejected (locked by TC-188-10 below); (3) an off-loopback two-netns harness (Linux-only, not this macOS host; punch still probabilistic).

## Real Scope
**In scope (test + docs only; NO production edit):**
1. Three NEW deterministic guard tests extending `go-mknoon/node/holepunch_tracer_test.go` (peer-scoping, DirectDialEvt-breadcrumb anti-hack, tracer/Notifiee exactly-once dedup).
2. Documentation: revise `188-…-spec.md` to Path 3; re-scope CV-10/11/12 closure in `FDC-CONVERGENCE-CHECKLIST.md`.

**Out of scope (owned elsewhere / explicitly rejected):** Option B prod circuit-holding (declined); off-loopback punch harness (rejected); any Dart/relay/device change; flipping `EnableDcutrUpgrade`.

## Files To Inspect Next
`go-mknoon/node/holepunch_tracer_test.go` (extend), `holepunch_tracer.go` (SUT, unchanged), `node_test.go` (`testEventCollector`, `connectionInfo` seed pattern :47-113). Docs: `188-…-spec.md`, `FDC-CONVERGENCE-CHECKLIST.md` (CV-10/11/12).

## Existing Tests Covering This Area
- `holepunch_tracer_test.go` — success→upgrade + flip + failure→no-upgrade (deterministic, synthetic events). **exists.** Auto-globbed by `go test ./node/`.
- `holepunch_negative_control_test.go` (CV-12), `dcutr_upgrade_flag_test.go` (CV-13/TC-12-01), `holepunch_feasibility_test.go` (real-punch observable, skip-tolerant). **exist.**
Missing coverage gaps: (a) peer-scoping — a success for peer B must NOT flip a co-resident peer C; (b) `DirectDialEvt` breadcrumb must NOT emit `transport:upgraded`/count success (anti-hack); (c) exactly-once dedup — `markPeerUpgradedToDirect` returns false + no second emit when already-direct.

## RED Test Catalog  (guard/characterization — GREEN on HEAD, RED under the documented mutation)
> Path 3 has NO production fix (the SUT is already correct). These lock the correct semantics; each is **mutation-verifiable** against a documented regression (the "re-red" is applying the mutation to `holepunch_tracer.go`).

1. `holepunch_tracer_test.go`::`TestHolePunchTracer_SuccessIsPeerScoped_CoResidentCircuitUntouched` (TC-188-03)
   - Tier: unit (Go host). Setup: seed TWO `connections` entries — peerB `{Limited:true}` and peerC `{Limited:true}`; feed a synthetic `EndHolePunchEvt{Success:true, Remote:peerB}`.
   - GREEN asserts: peerB flips `Limited:false`; **peerC stays `Limited:true`**; exactly 1 `transport:upgraded` and its `remotePeerShort == shortPeerID(peerB)` (NOT peerC). Distinct-discriminator: `transport:upgraded{remotePeerShort==B}` AND NOT `==C`.
   - Mutation that re-reds: change `markPeerUpgradedToDirect` to flip all entries / ignore the `remote` key → peerC flips → RED. (Guards the 2026-07-01 device artifact where the punch targeted an unrelated peer.)

2. `holepunch_tracer_test.go`::`TestHolePunchTracer_DirectDialEvt_IsBreadcrumbOnly_NoUpgrade` (TC-188-10) — **PROD-CRITICAL invariant**
   - Tier: unit. Setup: seed peerB `{Limited:true}`; feed a synthetic `DirectDialEvt{Success:true, Remote:peerB}`.
   - GREEN asserts: `Successes()==0`; **zero** `transport:upgraded`; peerB stays `Limited:true`; a `holepunch:attempt{step:"direct_dial"}` breadcrumb IS emitted (present but non-load-bearing).
   - Mutation that re-reds: wire `DirectDialEvt` → `markPeerUpgradedToDirect` (the refuted hack) in `holepunch_tracer.go:113-120` → `transport:upgraded` fires + `Limited` flips → RED. **This test is the guard that prevents the rejected loopback-determinism hack from ever landing.**

3. `holepunch_tracer_test.go`::`TestHolePunchTracer_AlreadyDirect_NoDoubleUpgrade` (TC-188-11)
   - Tier: unit. Setup: seed peerB `{Limited:false}` (already direct — e.g. the FDC-12 Notifiee re-pointed first); feed `EndHolePunchEvt{Success:true, Remote:peerB}`.
   - GREEN asserts: `markPeerUpgradedToDirect` returns false → **zero** `transport:upgraded` (the "exactly once across tracer+Notifiee" invariant, `holepunch_tracer.go:78-86`); `Successes()` still increments + `holepunch:success` still emitted (success telemetry is not suppressed, only the duplicate upgrade emit).
   - Mutation that re-reds: emit `transport:upgraded` unconditionally (ignore the `markPeerUpgradedToDirect` bool at `:86`) → 1 upgrade for an already-direct entry → RED.

## Test Coverage Matrix  (zero empty cells)
| Spec case | Behavior props | Tier | Test file::name | RED reason (under mutation) | Mutation revert | Acceptance gate cmd | Harness registration |
|---|---|---|---|---|---|---|---|
| TC-188-03 | peer-scoped upgrade | unit (Go) | holepunch_tracer_test.go::…PeerScoped… | flip-all mutation flips co-resident C | flip only `remote` key | `GOTOOLCHAIN=go1.25.0 go test ./node/ -run HolePunchTracer` | AUTO (`go test ./node/`) |
| TC-188-10 | DirectDialEvt breadcrumb (anti-hack) | unit (Go) | holepunch_tracer_test.go::…DirectDialEvt_IsBreadcrumbOnly… | wiring DirectDialEvt→upgrade emits transport:upgraded | revert the hack | `GOTOOLCHAIN=go1.25.0 go test ./node/ -run HolePunchTracer` | AUTO |
| TC-188-11 | exactly-once dedup | unit (Go) | holepunch_tracer_test.go::…AlreadyDirect_NoDoubleUpgrade | unconditional emit double-fires | gate emit on the bool | `GOTOOLCHAIN=go1.25.0 go test ./node/ -run HolePunchTracer` | AUTO |
| CV-12 (covered) | negative / no-false-upgrade | unit (real nodes) | holepunch_negative_control_test.go (existing) | — (already green) | — | `go test ./node/ -run NegativeControl` | AUTO (existing) |
| CV-13 (covered) | flag gating | unit | dcutr_upgrade_flag_test.go (existing) | — | — | `go test ./node/ -run DcutrFlag` | AUTO (existing) |
| CV-10/11 real-punch | observable, non-deterministic | feasibility probe | holepunch_feasibility_test.go (existing, skip-tolerant) | N/A — cannot be a deterministic gate (documented) | — | `go test ./node/ -run Feasibility` (may skip) | AUTO (existing) |

## Blind-Spot Sweep
- **Lifecycle / derived-state durability:** the upgrade flips in-memory `n.connections`. TC-188-03/11 assert the map state post-event. A process-restart reopen is N/A — `connections` is live node state rebuilt from real conns on the next Start, not persisted; no derived UI. **N/A (justified).**
- **Sibling-surface consistency:** the upgrade emit has TWO producers (tracer + FDC-12 Notifiee `peer_session.go:157`). TC-188-11 locks the exactly-once dedup between them (the sibling surface). Covered.
- **Destructive-action side-effects:** N/A — no delete/cleanup/cancel.
- **Invariant re-verification under new transitions:** the anti-hack invariant (DirectDialEvt ≠ upgrade) is the load-bearing one; TC-188-10 re-verifies it as a standing guard. Covered.

## Invariants (locked by tests)
- INV-1 (peer-scoped): an upgrade flips ONLY the target peer → TC-188-03.
- INV-2 (anti-hack, PROD-CRITICAL): a plain direct dial is NEVER a DCUtR upgrade → TC-188-10.
- INV-3 (exactly-once): tracer+Notifiee emit `transport:upgraded` at most once → TC-188-11.
- INV-4 (unchanged, referenced): success→upgrade + failure→no-upgrade + flip → existing tracer tests; CV-12 negative + CV-13 flag → existing suites.

## Step-By-Step Implementation Plan
1. `git status --short` snapshot (185/186/187 already committed at `be440b1e`; expect only checklist/188 docs dirty).
2. Add the 3 guard tests to `holepunch_tracer_test.go` (reuse the `New(&testEventCollector{})` + `n.connections[remote.String()] = connectionInfo{Limited:true}` seed pattern from the existing tests :47-113 + `collector.collectEvents(...)`).
3. Confirm each is GREEN on HEAD (correct SUT), THEN mutation-verify each: apply its documented mutation to `holepunch_tracer.go`, confirm RED, revert. **Do NOT leave any mutation in.**
4. Revise `188-…-spec.md` to Path 3 (deterministic punch premise refuted; closure = tracer guards + existing coverage + documented ceiling).
5. Re-scope CV-10/11/12 in `FDC-CONVERGENCE-CHECKLIST.md`: CV-12 → closed (negative control); CV-13 → covered (flag test); CV-10/11 → closed at the host ceiling (deterministic upgrade-observable machinery via tracer tests + skip-tolerant feasibility probe; genuine-punch deterministic gate impossible + on-device 1:1 DCUtR unreachable per verdict).
6. Run gates; `git checkout -- go-mknoon/testdata/interop_vectors.json`.

## Risks And Edge Cases
- **The anti-hack hazard** (someone re-attempts loopback determinism by wiring DirectDialEvt→upgrade) → TC-188-10 is the standing guard.
- `connectionInfo`/`connections` field access from the test (same package `node` → OK; `n.host` nil in the unit test → the address-resample loop at `holepunch_tracer.go:169` is guarded by `if n.host != nil`, so a nil-host unit test is safe).
- go-libp2p event types (`holepunch.Event`, `EndHolePunchEvt`, `DirectDialEvt`) are exported + constructible (existing tracer tests already build `EndHolePunchEvt` — same pattern).

## Device/Relay Proof Profile
**host-only for closure.** No sim/device/relay. CV-10/11's genuine on-wire punch is deliberately NOT gated (impossible deterministically; unreachable on-device for 1:1). Feasibility test stays a skip-tolerant probe.

## Acceptance Gates  (literal)
```bash
# The 3 new guard tests (before mutation-verify: GREEN on HEAD)
cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node/ -run 'TestHolePunchTracer' -v   # expect: all PASS incl. 3 new
# Full node package (existing DCUtR suites stay green)
GOTOOLCHAIN=go1.25.0 go test ./node/ -run 'HolePunch|Dcutr|Feasibility|NegativeControl' -v
# Whole package + race (the FDC-08/11 -race closure gate; CV-50 already fixed the epoch race)
GOTOOLCHAIN=go1.25.0 go test -race ./node/ -count=1
# Hygiene
GOTOOLCHAIN=go1.25.0 go vet ./... ; cd .. ; git checkout -- go-mknoon/testdata/interop_vectors.json ; git diff --check
```
Expected: the 3 new tests PASS; `Feasibility` may `SKIP` (documented, not a failure); no `-race` regressions.

## Known-Failure Interpretation
- Expected: `TestHolePunchFeasibility_*` may `t.Skip` (loopback can't deterministically punch — documented, NOT a failure).
- Pre-existing dirty: none Go-side (185/186/187 were Dart; committed at `be440b1e`).
- Scope drift (BLOCKING): any change to `holepunch_tracer.go` production behavior (this plan adds tests only).

## Done Criteria
- [ ] 3 guard tests added + GREEN on HEAD + each mutation-verified (RED under its documented mutation, reverted).
- [ ] `go test ./node/` + `-race` green; feasibility skip documented.
- [ ] spec 188 revised to Path 3; CV-10/11/12 re-scoped in the checklist with the verdict pointers.
- [ ] `go vet` clean; `interop_vectors.json` reverted; `git diff --check` clean.
- [ ] NO production code change (SUT `holepunch_tracer.go` untouched).

## Scope Guard (hard "Do not")
- Do NOT wire `DirectDialEvt` → `markPeerUpgradedToDirect` (the refuted hack — a prod-semantics regression; TC-188-10 guards it).
- Do NOT build an off-loopback / two-netns punch harness (Linux-only, non-deterministic).
- Do NOT implement Option B (prod circuit-holding); do NOT touch the Dart send/warm path; do NOT flip `EnableDcutrUpgrade`.
- Do NOT change `holepunch_tracer.go` production behavior — tests only.

## Accepted Differences / Intentionally Out Of Scope
- A genuine on-wire DCUtR relay→direct punch is NOT deterministically gated — impossible in a host test (hole-punching is probabilistic) and architecturally unreachable on-device for 1:1 (store-and-forward verdict). The feasibility test remains a skip-tolerant observable probe; this is the honest ceiling, accepted by decision (Path 3, 2026-07-01).

## Reviewer Findings
Sufficient: every achievable behavior maps to a mutation-verifiable unit test at the right (lowest) tier; the refuted premise is documented as do-not-re-introduce with a standing guard (TC-188-10); CV-12/CV-13 closure is referenced to existing deterministic tests; CV-10/11 close honestly at the documented host ceiling. Thin-by-design: no production edit (the SUT is already correct) — the plan is verification-hardening + closure, and says so.

## Arbiter Decision
Structural blockers: none. The one real hazard (the loopback-determinism hack) is neutralized by a standing guard test. No DB migration, no device gate (impossible-by-nature, documented). Fully host-executable now regardless of the network. **Structurally sufficient — hand off to execution.**
