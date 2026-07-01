# 188 - DCUtR-1:1 relay→direct upgrade: deterministic forced-circuit verification (Option A)  (Bug/verification — Spec)

Status: **PREMISE REVISED → Path 3** (2026-07-01). The original "deterministic loopback DCUtR-punch gate" premise was **refuted** by workflow `wf_77ef6f8d`: a genuine hole-punch is inherently probabilistic (loopback short-circuits to a non-DCUtR forced dial; go-libp2p's own punch is non-deterministic), so a deterministic host gate asserting `markPeerUpgradedToDirect` **cannot exist**. Superseded by **`188-…-tdd-plan.md` (Path 3 — honest host-ceiling closure)**: lock the deterministic upgrade-*observable* tracer semantics + a standing anti-hack guard, and re-scope CV-10/11/12 to close at the host ceiling. Read the plan, not the Option-A test cases below.

**EXECUTED 2026-07-01 (plan 188 Path 3):** the 3 guard tests landed in `go-mknoon/node/holepunch_tracer_test.go` — `TestHolePunchTracer_SuccessIsPeerScoped_CoResidentCircuitUntouched` (TC-188-03), `TestHolePunchTracer_DirectDialEvt_IsBreadcrumbOnly_NoUpgrade` (TC-188-10, the standing anti-hack guard), `TestHolePunchTracer_AlreadyDirect_NoDoubleUpgrade` (TC-188-11) — each GREEN on HEAD and mutation-verified RED under its documented regression (flip-all / DirectDialEvt→upgrade hack / unconditional emit), mutations reverted. CV-10/11/12 closed at the host ceiling + CV-13 re-scoped to parked-dark in `FDC-CONVERGENCE-CHECKLIST.md`. NO production code changed. NOTE: the Group A/B/C TC numbering below is the superseded Option-A draft — TC-188-10/11 were RE-USED by the Path-3 plan for different (guard) cases; the plan's catalog is authoritative.

(original spec-only draft — problem + current state + test cases; the Group-A "deterministic positive upgrade" cases are the refuted premise.)

Relation to earlier work:
- Follows the **2026-07-01 root-cause verdict** (workflow `wf_b0ea0dc5`, recorded in `FDC-CONVERGENCE-CHECKLIST.md` CV-10): mknoon's 1:1 cross-network transport is **store-and-forward inbox by design**, and `warmPeer` deliberately **avoids** holding a `/p2p-circuit` to the peer (`p2p_service_impl.dart:2578` calls it *"wasteful"*). So **DCUtR-for-1:1 (FDC-12) is dead machinery in production** — normal ops never hold the circuit it would upgrade. The device rows **CV-10/11/12** can never observe a real 1:1 upgrade on-device and would pass **vacuously**.
- **Decision (2026-07-01): Option A — verify-only.** Keep store-and-forward as the prod 1:1 transport (do NOT add prod circuit-holding — that was Option B, declined). Instead, prove the DCUtR upgrade **machinery** is correct via a **deterministic forced-circuit host harness**, and **re-scope CV-10/11/12** off "real-NAT device proof" (architecturally unreachable) onto that harness.
- Builds on the existing `holepunch_*` Go test suite (FDC-12 / FDC-S2).

---

## Problem Statement

The DCUtR relay→direct upgrade **cannot be proven on-device** (verdict above), yet its machinery must be verified before `EnableDcutrUpgrade` could ever be trusted. The existing Go tests **almost** do this but leave the **positive** upgrade non-deterministic:

**The positive upgrade proof skips instead of asserting.** `TestHolePunchFeasibility_LoopbackUpgradeObservable` forces a real circuit via the production path (`nodeA.DialPeerViaRelay(nodeB.PeerId())`) and asserts the correct evidence when an upgrade happens (`directConn.Stat().Limited == false`) — but if the hole-punch does **not** auto-materialize (forced-public loopback hosts do not auto-hole-punch), it **`t.Skip`s** ("feasibility-only … expected to be flaky on loopback"). A test that can silently skip is not a closure gate: CV-10/CV-11 cannot rest on it.

**Root of the non-determinism:** the upgrade relies on go-libp2p's **auto** hole-punch (driven by AutoNAT/reachability), which does not fire reliably on a loopback/forced-public rig, and the node exposes **no active trigger** to initiate the punch on demand.

---

## Verified current state (file:line)

### Already deterministically covered (no new work — cite as covered when re-scoping)
- **Negative / no-false-upgrade (→ CV-12):** `go-mknoon/node/holepunch_negative_control_test.go::TestHolePunchNegativeControl_RelayOnly_NoUpgradeNoThrash` — with `ForceReachabilityPrivate`, `assertNW002LimitedCircuitConn` holds **throughout** a polled window (`Stat().Limited == true`) AND **zero** `transport:upgraded` events (`:120-137`). This IS the "symmetric-CGNAT graceful no-upgrade / no false direct badge" property at the host tier.
- **Flag gating (→ CV-13 / TC-12-01):** `go-mknoon/node/dcutr_upgrade_flag_test.go` — flag OFF → `ForceReachabilityPrivate` + zero punches (`:15`), flag ON → `ForceReachabilityPublic` (`:39`), plumbs through node config (`:55`).

### The gap (→ CV-10 / CV-11, positive upgrade)
- `go-mknoon/node/holepunch_feasibility_test.go::TestHolePunchFeasibility_LoopbackUpgradeObservable` (`:78`): sets up a local circuit relay (`startNW002LocalCircuitRelay` `:83`), two relay-connected nodes (`:90-91`), **forces the circuit via the production dial** (`DialPeerViaRelay(nodeB.PeerId())` `:94`), polls for a non-`Limited` direct conn (`:106-114`), and **PINS** the evidence if found (`Stat().Limited == false` `:127`). BUT `:116-121` **skips** if no upgrade materializes in 8 s. `..._TcpLane` (`:144`) has the same skip shape.
- **No active hole-punch trigger exists** on the node (grep of `node/*.go` non-test for `DirectConnect`/`holePuncher`/`ForceDirectConnect` is empty) — the go-libp2p holepuncher's on-demand `DirectConnect` is not surfaced through a test seam. So the test can only *wait* for an auto-punch, hence the skip.
- The production circuit-establishment path exists and is reachable from a harness: `DialPeerViaRelay` → `dialPeerViaRelayWithTimeout` (`node.go:1328`), also invoked by the `RelayProbe` bridge command (`bridge.go:926`). The forced-public test seam exists (`node.go:117-118,375`). The upgrade marker is `markPeerUpgradedToDirect`, which fires only on an `info.Limited` circuit entry (`holepunch_tracer.go:159-179`).

---

## Test cases

### Group A — deterministic positive upgrade (the residual; → CV-10 / CV-11)
- **TC-188-01** — with two relay-connected nodes and a **forced circuit** (`DialPeerViaRelay`), an **actively-triggered** hole-punch (on-demand, not auto) deterministically upgrades the relay circuit to a **non-`Limited` direct** connection to the *target peer* — the test **asserts** (never skips): `markPeerUpgradedToDirect` fires for `nodeB`'s peer id, `transport:upgraded` is emitted, and `firstDirectConn(nodeA, nodeB).Stat().Limited == false`.
- **TC-188-02 (sticks)** — after the upgrade, the direct (non-`Limited`) conn to the target **persists** across a subsequent send / poll window (the "fires **and sticks**" half of CV-11 / TC-12-12); the circuit conn is not immediately re-selected.
- **TC-188-03 (peer-scoped)** — the upgrade + `transport:upgraded` are attributed to the **conversation peer's** id, NOT an incidental relay peer (guards the 2026-07-01 device artifact where the only punch targeted an unrelated peer). Distinct-discriminator: assert `transport:upgraded{peerId==nodeB}` AND the tracer's success is for `nodeB`.

### Group B — invariants / no-regress (must stay green)
- **TC-188-10** — the negative control (`TestHolePunchNegativeControl…`) stays green: with the flag/seam OFF, the circuit stays `Limited` and **zero** `transport:upgraded` — the deterministic-trigger seam added for Group A must be **inert** unless explicitly invoked (no auto-upgrade leaks into the negative/flag-off path).
- **TC-188-11** — `dcutr_upgrade_flag_test.go` stays green (flag OFF → private/zero-punch; ON → public); the new trigger does not bypass the flag gate.
- **TC-188-12 (prod-unchanged)** — store-and-forward remains the 1:1 prod transport: no new production code holds a `/p2p-circuit` to the active peer; the trigger seam is **test-only** (asserted absent from the normal send/warm path — `warmPeer`'s circuit-avoidance at `p2p_service_impl.dart:2578-2604` is untouched).

### Group C — re-scope closure (documentation, tracked not tested)
- **TC-188-20** — CV-10/CV-11 are re-scoped: closure = the deterministic host harness (Group A), NOT an on-device real-NAT proof. The device rows are marked **not-reproducible (store-and-forward by design)** with a pointer to the verdict. CV-12 → covered by the negative control; CV-13/TC-12-01 → covered by the flag test.

---

## Scope guard (non-goals)

- **Do NOT implement Option B** (a prod `warmPeer`/keepalive that dials-and-holds a circuit to the active peer). Store-and-forward stays the 1:1 prod transport; `warmPeer`'s deliberate circuit-avoidance (`p2p_service_impl.dart:2578`) is **preserved**. Any active-trigger seam is **test-only**.
- **Do NOT** attempt an on-device real-NAT DCUtR proof for 1:1 — the verdict shows it is architecturally unreachable (no held circuit in normal ops). This spec replaces that with the host harness.
- **Do NOT** re-verify the negative (CV-12) or flag (CV-13) machinery — they are already deterministically covered; only reference them.
- **Do NOT** flip `EnableDcutrUpgrade` default-on. CV-13's flag flip remains gated on this verification (host lock), and staying dark in prod is intended (DCUtR-1:1 does nothing in the field under store-and-forward).
- Go-node/host only; no Dart send-path change, no relay deploy.
