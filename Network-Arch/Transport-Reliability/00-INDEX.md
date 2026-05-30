# Transport Reliability — Improvement Tracking Index

Prepared on: 2026-05-29
Status: Living tracker; DCUTR evidence closure folded in, product decisions
baseline-gated
Owner: TBD

## Purpose

This folder tracks a set of related workstreams aimed at making mknoon's
peer-to-peer message delivery **fast, reliable, and seamless**. Each document
captures one problem: current behavior (with `file:line` evidence), the
problems identified, impact, proposed directions (options only — no
implementation), acceptance criteria, and a test plan. They are intended to be
living tracking docs as we improve each area.

These docs are living analysis and closure trackers. This DCUTR-004 pass changed
documentation only; production transport behavior remains governed by the
underlying implementation and the baseline decision gate.

## How transport & channel selection works today (one-paragraph primer)

When a user sends a message, two separate decisions happen at two layers:

- **Which transport** (TCP / QUIC / WebSocket / circuit-relay) is **not** chosen
  by our code — we hand libp2p a peer's full address set and let its dialer race
  them. We only *classify after the fact* whether the winning connection was
  `direct` or `relay` (`classifyStreamTransport`, `go-mknoon/node/node.go:111`).
- **Which channel** (same-WiFi local WS / live libp2p stream / relay
  store-and-forward inbox) **is** our code's decision, and it differs between
  1:1 (a Dart-orchestrated ladder/race) and group (a Go-orchestrated parallel
  dual-write).

In practice, cross-network 1:1 peers rest on **relay** for the conversation
lifetime; true direct connections only occur on the **same LAN** today.

## Documents

| ID | Document | Status | Problem |
|----|----------|--------|---------|
| NET-REL-04 | [04-transport-observability.md](04-transport-observability.md) | ✅ **Done** (Option A+D; per-leg attempt tracking added) — baseline harvest pending (needs 2 real debug devices) | No aggregate visibility into which transport messages use — every other fix is unmeasurable (foundational) |
| NET-REL-01 | [01-lan-wifi-reliability.md](01-lan-wifi-reliability.md) | 🔄 **In progress** (build order: P2 TTL → P1 discover-on-send → P3 two-part media) | Same-WiFi/LAN delivery: discovery requires prior discovery, no TTL on peer map, local media transfer dead in prod |
| NET-REL-05 | [05-send-orchestration.md](05-send-orchestration.md) | ⬜ Not started | 1:1 send-path ladder: sequential relay-probe tail, no grace window, no sticky/learned per-peer transport, inbox as last rung |
| NET-REL-02 | [02-nat-traversal-dcutr.md](02-nat-traversal-dcutr.md) | 🚫 **Deprioritized (closed on prior, 2026-05-30)** — baseline harvested: cross-network 100% relay, 0 hole-punch attempts; CGNAT prior adverse, probe not run. Reopen only on a non-zero DCUtR feasibility probe (see 02). | DCUtR hole-punching is observable and relay-only safety is accepted; cross-network direct pursuit + the NET-REL-03 build are closed on the measured baseline + adverse-NAT prior |
| NET-REL-03 | [03-relay-springboard.md](03-relay-springboard.md) | 🚫 **Deprioritized (closed on prior, 2026-05-30)** — baseline harvested; do NOT build the springboard ladder. Gap analysis retained. | Relay is a permanent resting state, not a springboard to direct |
| NET-REL-06 | [06-test-and-simulation-strategy.md](06-test-and-simulation-strategy.md) | 📋 Doctrine (applies to all) | **Cross-cutting test doctrine:** harness inventory, the negative-control principle, transport-proof primitives, happy/unhappy taxonomy, what to build. How we prove success without false results. |
| NET-REL-07 | [07-relay-backward-compatibility.md](07-relay-backward-compatibility.md) | 📋 Constraint (binding) | **Binding constraint:** the relay is a single shared host hard-coded into shipped apps with no version negotiation — a breaking change hits all un-updated users instantly. SAFE vs BREAKING change taxonomy; additive-only + multi-relay-migration rules. |
| NET-REL-08 | [08-relay-path-quality.md](08-relay-path-quality.md) | 📋 **Proposed (scoping)**; justified by baseline — relay is the cross-network lever (~100% relay @ ~1.1s). Measurement-first, additive-only per NET-REL-07. | Cross-network rests on relay; scope relay-path latency/reliability. Realizes NET-REL-02 Option C; supersedes the deprioritized NET-REL-03. |

## Dependency graph

```
NET-REL-06 (test/sim doctrine) ── underpins validation of ALL workstreams
NET-REL-04 (observability)     ── foundational; gates measuring all others
        │
        ├── NET-REL-01 (LAN reliability)      ── independent win, lowest risk
        ├── NET-REL-02 (NAT traversal/DCUtR)  ── CLOSED on prior (deprioritized 2026-05-30)
        │        │
        │        └── NET-REL-03 (relay springboard) ── CLOSED on prior (do not build)
        │
        ├── NET-REL-05 (send orchestration)   ── ties LAN + relay + inbox into one UX
        │
        └── NET-REL-08 (relay-path quality)   ── cross-network lever after 02/03 closed; additive-only (NET-REL-07)
```

**Testing doctrine (NET-REL-06):** every per-doc Test Plan is grounded in the
repo's real harnesses and follows the **negative-control principle** — each
"we succeeded" test is paired with a control that fails if the implementation
cheats or regresses. The known false-result trap to avoid: today's real-network
E2E tests accept the `{direct, relay, inbox}` *set* (to dodge flake), so they can
pass while a message silently used relay. Path-pinning tests must assert the
*specific* transport (e.g. `transport == 'local'` + `localSendCallCount == 1`,
or Go `conn.Stat().Limited == true/false`), never the set.

## Recommended sequencing (for discussion)

1. **NET-REL-04 first (instrument).** We cannot tell if anything improves
   without a direct/relay/local/inbox census and per-transport latency. Cheap,
   privacy-safe, unblocks measurement.
2. **NET-REL-01 next (LAN win).** The only place we reliably get direct
   connections today. Discover-on-send + TTL + restoring local media is a
   contained, high-value reliability improvement.
3. **NET-REL-05 (orchestration).** Hedged racing + sticky per-peer transport
   cuts seconds off unhappy paths; concurrent durable fallback improves
   reliability. Benefits from NET-REL-04 latency data.
4. **NET-REL-02 / NET-REL-03 (decide on direct cross-network).** Only after data
   shows how often we're stuck on relay. May conclude relay-as-steady-state is
   the honest answer for mobile-to-mobile over cellular.

## Hard constraints (read before any implementation)

- **Relay backward-compatibility (NET-REL-07):** the relay is a single shared host
  hard-coded into every shipped app binary, restarted in place, with no version
  negotiation. **A breaking relay change breaks chat for 100% of un-updated users
  instantly.** Every relay-touching change must be additive-only; genuinely breaking
  changes must go via the multi-relay migration path (new relay shipped in new app
  builds, old relay retired only after adoption). The one relay change currently
  proposed (NET-REL-04's 1:1-vs-group circuit metric) is additive = safe.
- **LAN tests can't use simulators:** iOS sims share the host mDNS stack, so sim runs
  force `DISABLE_LOCAL_DISCOVERY=true` and cannot prove the `local` transport. The
  same-WiFi proof (NET-REL-01 I3) needs two real physical devices.

## Changelog

- **2026-05-30 — NET-REL-02/03 deprioritized (closed on prior); NET-REL-08 scoped.**
  Baseline gate (real-device, N=50/condition, cold-start): cross-network 100% relay,
  0 hole-punch attempts, 0 relay→direct upgrades, relay ≈3.8× same-network (1114 vs
  297ms median). The DCUtR feasibility probe was NOT run (≈0% expected under cellular
  CGNAT). Closed: cross-network direct pursuit (NET-REL-02) + the NET-REL-03 springboard
  build. Reopen only if a future probe (experimentally relax `ForceReachabilityPrivate`
  on two real devices cross-network, N≥50) shows non-zero relay→direct success.
  Cross-network energy → **NET-REL-08 (relay-path quality)**, now justified-by-baseline
  (not gated). Device-validation runbooks added for NET-REL-01 I3 + NET-REL-05 E2
  (`Test-Flight-Improv/`).
- **2026-05-30 — NET-REL-03 RSD-001 no-proceed decision recorded.**
  The relay-springboard evidence gate found physical devices available but no
  copied real-device, discovery-enabled, debug-mode 1:1 `baselineReport()` or
  filled decision-gate artifact with the required transport and hole-punch
  counts. NET-REL-03 implementation remains deferred; RSD-002/RSD-003 stay
  prerequisite-blocked until a valid baseline harvest exists.
- **2026-05-30 — NET-REL-02 DCUTR evidence closure folded into stable docs.**
  DCUTR-001/002/003 evidence is now reflected in the NAT/DCUtR tracking doc,
  baseline decision gate, source evidence doc, and this index: Go hole-punch
  tracing, Dart aggregate diagnostics, and relay-only/no-upgrade behavior are
  accepted. Production mobile relay-to-direct DCUtR success remains unproven and
  evidence-gated until a concrete real-device, discovery-enabled, debug-mode
  baseline harvest exists. Simulator/CLI proof remains relay/recovery liveness
  evidence, not physical NAT traversal proof, and the repeated
  `run_transport_e2e.dart` E8 media metadata residual remains an external
  orchestrator residual.
- **2026-05-29 — Relay backward-compatibility constraint added (NET-REL-07) + test
  environment facts.** Investigated (a) iOS-simulator/real-network test usage and (b)
  relay change safety for un-updated users. Findings: the 4-sim harness + real-network
  nightly tests exist, but sims can't prove `local` (shared host mDNS → discovery
  disabled), so the same-WiFi proof needs real devices (noted in NET-REL-01 I3 /
  NET-REL-06 §5b). The relay is a single shared host hard-coded into shipped apps with
  no version negotiation → breaking changes hit all un-updated users instantly; captured
  the SAFE/BREAKING taxonomy and additive-only + multi-relay-migration rules in NET-REL-07
  and the Hard-constraints section above.
- **2026-05-29 — Test & simulation strategy added (NET-REL-06).** Mapped the real
  Go + Flutter test/simulation infrastructure and rewrote every per-doc Test Plan to
  be grounded and runnable, with explicit **happy and unhappy paths** and **negative
  controls** that prevent false-positive results. Established the transport-proof
  primitives (Go `conn.Stat().Limited`; Dart `FakeP2PService.sendMessageTransport`)
  and flagged the capabilities that must be BUILT (a real wifi-vs-relay pinning
  harness, LAN-block/relay-disable primitives, hard latency-budget gates, hole-punch
  observation tests, relay `metrics_test.go`, and an explicit `unknown` transport
  label to kill the default-to-`relay` bias).

## QA log (test plans)

- **2026-05-29 — QA iteration 2 (test plans, all docs + NET-REL-06).** Six
  code-explorer agents verified the test plans against the real harnesses with an
  end-to-end lens. References were accurate; the dominant finding was the **fidelity-tier
  problem** — most transport assertions live in fakes (T1) that prove decision logic,
  not the real bridge→Go→wire path; no test drives the real use-case→bridge→Go and pins
  a *specific* transport. Corrections applied:
  - **NET-REL-06:** added the **fidelity-tier table (T1/T2/T3)** and the headline E2E
    gap; clarified the **three distinct fake networks** (and that
    `f2_transport_switch_recovery_test.dart` doesn't actually switch transport);
    expanded the BUILD list with the bridge-boundary test, the `node` reachability+tracer
    seam, the real-stack concurrent-fallback liveness proof, and a discovery-enabled
    multi-device variant.
  - **NET-REL-02:** re-scoped I1 (relay→direct upgrade is **NOT** app-E2E testable —
    only component-level à la go-libp2p `holepunch_test.go`); made the stay-on-relay
    negative control the **primary** E2E test with expected attempt count **0**; fixed
    R1 (pion-unused is a lint/`go mod why` fact, not a runtime test) and the U2 "sampled
    once" wording.
  - **NET-REL-03:** corrected the I1 harness (NW002 lives in `pubsub_delivery_test.go`,
    not `local_relay_harness_test.go`); re-specified relay-drop-after-grace as "assert
    proactive close" (ConnManager trim isn't deterministic in a 2-node test); flagged
    that U1–U3 (the ledger) test **unbuilt** code and that U3's background signal
    doesn't exist in Go; split U-N2 (`Limited==true` needs a real conn, not the stub).
  - **NET-REL-04:** rebound U2 to the **receive path** (`:159` `onMessageReceived`, not
    the send fake); added the global-`promauto` delta/non-parallel/duplicate-count
    constraints for `metrics_test.go`; noted the real `flow_event_emitter` sanitization
    seam (PR1 feasible) and its known-keys-only caveat.
  - **NET-REL-05:** fixed the three-fake conflation and the I2/f2 mischaracterization;
    noted no budget-ENFORCEMENT test exists and which fake has the delay knobs; added a
    real-stack concurrent-fallback liveness proof (E2).
  - **NET-REL-01:** cited `local_p2p_service_test.dart` (closest real-stack integration,
    previously omitted); noted `BonsoirDiscoveryService` is never instantiated in tests;
    sequenced the media test (U4) after the P3 implementation.

## QA log

- **2026-05-29 — QA iteration 1 (code-explorer re-verification, all 5 docs).**
  Verdict: load-bearing claims across all docs CONFIRMED. Corrections applied:
  - **NET-REL-04 (material):** relay metrics are **already implemented and live**
    (`go-relay-server/metrics.go`, 40+ Prometheus metrics incl. a stream-latency
    histogram, served on `/metrics`:2112) — not "a plan." Option B scope shrunk
    accordingly. P4 softened (per-send latency components exist but aren't
    aggregated/bucketed).
  - **NET-REL-01:** P3 corrected — production *does* attempt local-media send
    (`conversation_wired.dart`); it fails because the receiver has no media server
    AND nothing consumes `mediaReadyStream` (fix needs both). Added Android NSD
    permission note and scope note (LAN path also serves introductions/contact
    requests/deletes/shares; groups confirmed not using it).
  - **NET-REL-03:** relay state machine corrected to include the `reserving`
    state; `OnRequestFailed → cooldown` is conditional. Noted relay conns aren't
    `Protect`-ed.
  - **NET-REL-05:** `queued` is log-only, not an active status; `~292` persists
    the envelope (the `sending` row is created by the optimistic UI);
    `WithAllowLimitedConn` permits (not "races") relay; noted unacked-success also
    does a sequential inbox handoff and there is no fg/bg budget split.
  - **NET-REL-02:** corrected Dart path (`core/services`), `connectGroupPeerPreferDirect`
    lives at `pubsub.go:1878`, added pion-indirect-deps footnote.

## Key environment facts (verified)

- go-libp2p **v0.39.1**; go-libp2p-pubsub **v0.15.0** (vendored at
  `go-mknoon/third_party/go-libp2p-pubsub`).
- Transports/security/muxers are **not explicitly configured** — we inherit
  go-libp2p defaults (TCP, QUIC-v1, WebSocket, WebTransport; Noise/TLS; yamux).
  **WebRTC is not enabled.**
- Relay endpoints: `mknoun.xyz` WSS `:4001` and QUIC `:4002`
  (`go-mknoon/node/config.go:9-15`).
- A privacy-safe **relay-side** metrics plan already exists
  (`UI-Grafana/privacy-safe-business-graf.md`, HyperLogLog aggregate-only).
