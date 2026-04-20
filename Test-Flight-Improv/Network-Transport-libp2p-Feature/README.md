# Network Transport libp2p Feature

Reference documents for understanding, testing, and optimizing the Go libp2p transport layer and everything built on top of it.

---

## Documents

### 00-transport-dependency-matrix — "What exists in the Go transport layer?"

Inventory of Go protocols, bridge commands, push events, feature flags, and shared code paths. Lookup table for questions like "what bridge command does group publish use?" or "what Go files break if I change the inbox protocol?"

Scope: bridge and below. Changes when you add/remove/rename Go-side components.

### 01-application-layer-map — "How does data flow from bridge to UI?"

Traces each message from Go delivery through: P2P service -> router -> listener -> repo -> UI stream. Section 6 (cross-feature connections) maps the hidden couplings where changing one feature breaks another.

Scope: bridge to UI. Changes when you add/rename listeners, repos, or cross-feature wiring.

### 02-ui-wiring-map — "What does each screen depend on and construct?"

Widget dependency graph: what each Wired widget receives, what streams it subscribes to, what it navigates to. Answers "I'm changing groupMessageListener.groupMessageStream — which screens break?"

Scope: UI layer. Changes when you add screens or change navigation.

### 03-timing-and-performance — "Where does the time go?"

Maps every blocking operation, timeout, and wait point across the critical paths. Shows what we measure vs what we're blind to. Surfaces bottlenecks and hazards. Includes the complete timeout reference table.

Scope: runtime behavior. Changes when you tune timeouts or add instrumentation.

### 04-transport-routing-strategy — "How do we choose which transport path?"

The decision logic for message delivery: connection reuse, WiFi vs direct P2P race, relay probe, inbox fallback (1:1); GossipSub + inbox dual-path (group messages); sequential publish-then-inbox (group reactions). Includes test coverage matrix per decision branch and uncovered gaps.

Scope: routing decisions. Changes when you modify fallback behavior, add transport paths, or change the race strategy.

### 05-relay-recovery-improvement-tdd-plan — "How do we reduce degraded relay recovery safely?"

Experiment-driven TDD plan for reducing the current `~9.1s` degraded relay recovery by testing one client-side recovery hypothesis at a time, measuring the delta, and promoting only the changes that improve the benchmarks without regressions.

Scope: relay recovery and degraded background resume. Changes when recovery sequencing, relay-state truth, or resume orchestration changes.

### 06-sendable-online-badge-spec — "When should the badge say Online versus Online.?"

Product and verification spec for redefining the green badge so `Online` means the app is usable now (send + inbox) and `Online.` means relay reservation is also ready. Includes the required widget, service, integration, smoke, and benchmark coverage for a later Phase 6 implementation pass.

Scope: readiness semantics and user-visible connection-state UX. Changes when badge meaning, readiness proof, or Phase 6 verification coverage changes.

---

## How the documents relate

| Doc | What | How | Behavior | Decisions |
|---|---|---|---|---|
| 00 | Go transport components | | | |
| 01 | | Dart data flow wiring | | |
| 02 | | Dart UI wiring | | |
| 03 | | | Timing, bottlenecks, hazards | |
| 04 | | | | Routing strategy, test coverage |
| 05 | | | Relay recovery experiments | Candidate fixes, benchmark gates |
| 06 | | Dart/UI readiness semantics | Badge meaning, usability vs relay-ready | Phase 6 acceptance contract |

00 is the parts list. 01 and 02 are the wiring diagrams. 03 is the performance profile. 04 is the routing contract. 05 is the recovery experiment plan. 06 is the readiness-semantics contract for the optional Phase 6 product change.

---

## When to use which document

| Question | Doc |
|---|---|
| What bridge command does feature X use? | 00 |
| What Go files do I touch to change the inbox protocol? | 00 |
| What listener handles incoming introductions? | 01 |
| If I change ChatMessageListener, what else breaks? | 01 (Section 6) |
| Which screens subscribe to groupMessageStream? | 02 (Section 5) |
| How do I navigate from OrbitWired to a group conversation? | 02 (Section 3) |
| What's the timeout for relay probe? | 03 (Section 3) |
| Why is first-send to a new peer slow? | 03 (Section 4) + 04 (Section 1) |
| What happens when WiFi and direct P2P both fail? | 04 (Section 1) |
| Is the group inbox fallback tested when publish times out? | 04 (Section 5) |
| I'm adding a new transport path — what do I touch? | 04 (Section 7) |
| Which relay-recovery change should we benchmark first? | 05 |
| What should `Online` versus `Online.` mean to users? | 06 |
