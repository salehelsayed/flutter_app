# 276 - Remove the dormant chat-only relay-probe helper (DTR-05)

Status: Plan-green
Type: Modification
Spec: free-text intent (no formal spec). Roadmap owner row:
`Test-Flight-Improv/dead-code-and-technical-debt-removal-roadmap.md` — DTR-05
(registry row, Wave 1) and ledger row `DTR08-COMP-003`.
Classification: implementation-complete
Closure tier: host

`DTR05-AUTH-01` remains the authorization of record for the chat-helper-only
removal and leaf-only two-peer waiver. Plan 276 atomically removed the
unreachable chat `_tryRelayProbeSend` helper, its `unused_element` suppression,
the ratchet's only handwritten entry, and stale serial-probe prose. Causal
RED/GREEN and mutation re-reds, TC-02 through TC-08, `1to1`, strict analysis,
discovery, the physical Pixel 6 transport preservation gate, the 821-path
`feature-host-all` sweep, and Graphify closure are green. The live shared relay
protocol is retained; protected protocol files and executable
`relayProbeEligible` plumbing are unchanged. The later Wave 1 aggregate
`host-all` passed and is recorded separately in the master roadmap; it is not a
per-plan claim.

## Planning Progress
| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-07-25 | Evidence Collector | `send_chat_message_use_case.dart`, `introduction_outbound_delivery.dart`, `delete_message_use_case.dart`, `tool/analyzer_guard/*`, `tool/runtime_roots/runtime_roots.json`, `scripts/run_test_gates.sh`, `scripts/run_host_test_gates.sh`, `scripts/check_flutter_analyze_strict.sh`, `scripts/test/flutter_analyze_strict_contract_test.sh`, FDC-00/02/03 plans, FDC-CONVERGENCE-CHECKLIST | Helper has **zero call sites**; FDC-03's conditional retention guard resolves to *delete*; no DTR-01 runtime-root coupling | Hand to Planner |
| 2026-07-25 | Planner | `test/unit/analyzer_suppression_ratchet_test.dart`, `test/features/conversation/application/send_chat_message_use_case_test.dart`, `test/core/services/p2p_service_fault_injection_test.dart`, `test/features/introduction/application/introduction_outbound_delivery_test.dart` | Only a **structural** RED is possible (a behavioral RED would prove the code is *not* dead) — canonical ratchet inventory test is the RED vehicle | Emit matrix |
| 2026-07-25 | Reviewer (sufficiency) | this plan | Harness hole found: `test/unit/**` is carried by **no** curated family and only by `host-all` (forbidden as a per-plan gate, roadmap:61) → direct path gate named | Arbiter |
| 2026-07-25 | Auditor (`/tdd-review`) | `routing_smoke_harness.dart`, `run_routing_smoke_e2e.dart`, `check_reliability_simulation_discovery.sh`, `run_test_gates.sh`, `analyzer_suppression_ratchet_test.dart`, helper extent `:2155-2165` | Initial core bet verified; telemetry, citations, and rollback findings applied. Its ready verdict was superseded by the later current-source sufficiency pass. | Remediate literal gates and contract shape |
| 2026-07-25 | Reviewer (current-source sufficiency) | plan, ratchet implementation/test, Dart bridge tests, Go selectors, host-gate registration, roadmap, live device matrix | Found reversed M-2/M-3, a vacuous Go regex, a false missing-selector claim, false Go registration/mutation claims, unsafe checkout, incomplete scope accounting, and missing required plan sections | Patch once; keep prerequisite-blocked |
| 2026-07-25 | Planner (remediation) | same files plus current Graphify snapshot | Structural blockers patched; authorization and target-path cleanliness remain external prerequisites | Re-run focused plan validation |
| 2026-07-25 | Reviewers (post-remediation validation) | final plan structure, literal Acceptance block, exact Flutter/Go selectors, device fallback, Graphify scope, and status lifecycle | No intrinsic plan-structure, command, scope, device, or final-status blocker remains; ratchet baseline is green at four reviewed occurrences | Keep evidence-gated until authorization lands and all target paths are tracked and clean |
| 2026-07-26 | Critical reviewer (`$tdd-review`) | current source, exact Test Contract selectors, ratchet scanner/test, relay Dart/Go/native boundary, Graphify nodes, roadmap proof floors, rollback, and live device discovery | Core bet confirmed; direct helper-absence proof, stale-comment scope, literal mutations, boundary guards, Graphify expectations, device selection, and rollback needed tightening. Deltas applied below; authorization/proof-floor reconciliation and clean targets remain external blockers. | Keep `not-ready` / prerequisite-blocked until both external prerequisites land |
| 2026-07-26 | Project owner / sole implementation authority | Plan 276 exact scope; roadmap registry, categorical Wave-1 proof floor, decision ledger, and `DTR08-COMP-003` | Approved `DTR05-AUTH-01`, including the helper-only two-peer waiver; explicitly retained the live shared relay protocol and executable classification plumbing | Land the coherent DTR-01 through DTR-04 + DTR-05 planning baseline, then run Gate 0 |

## Source Of Truth
- Roadmap / disposition: `Test-Flight-Improv/dead-code-and-technical-debt-removal-roadmap.md` (DTR-05 row; `DTR08-COMP-003`)
- Retention condition of record: `Test-Flight-Improv/Network-Transport-libp2p-Feature/fast-direct-connection/FDC-03-concurrent-durable-inbox-safety-net-tdd-plan.md:240` and `:326`
- Historical removal condition: the DTR-05 entry in
  `tool/analyzer_guard/production_unused_suppressions.json` at prerequisite
  commit `ec86247eb`; the current inventory intentionally contains only the
  three generated l10n entries.
- Gate definitions: `scripts/run_test_gates.sh`, `scripts/run_host_test_gates.sh` (script wins over prose)
- Numbering / index: `Test-Flight-Improv/00-INDEX.md`

## Problem And Pre-Edit Evidence

`lib/features/conversation/application/send_chat_message_use_case.dart:2025-2159`
held `_tryRelayProbeSend`, a ~135-line private helper (including its comment
block) that **no code calls**. FDC-03 removed the serial relay-probe→inbox tail
from the 1:1 send path; live relay recovery became FDC-02's in-race staggered
relay-live leg. Rather than delete the helper, FDC-03 retained it behind
`// ignore: unused_element` under a *conditional* scope guard, and DTR-02 later
pinned that suppression as the **single handwritten entry** in the production
suppression ratchet, owned by `roadmap:DTR-05`.

The cost was not runtime — the symbol was unreachable — but comprehension and
gate weight: ~135 lines of plausible-looking relay logic sat inside the live
send path's file, eight production comment blocks described a serial probe/tail
that did not run or claimed the helper remained retained, and two test files
carried three stale mutation recipes. The analyzer ratchet also carried a
handwritten exception whose own `removalCondition` required this atomic cleanup.

**Implemented change.** The dormant chat-only helper, its suppression, its
ratchet inventory entry, and every stale retention/serial-probe comment were
removed together, leaving the production suppression ratchet with only its
three generated l10n entries.

**What remained unchanged** (→ preserved-green sentinels):
- `relayProbeSendAttempts` (`send_chat_message_use_case.dart:55`) — **live**, consumed by `introduction_outbound_delivery.dart:580` and `delete_message_use_case.dart:985`.
- The **identically named, live** `_tryRelayProbeSend` in `introduction_outbound_delivery.dart:559` (called at `:347`).
- `P2PService.probeRelay`, its `p2p_service_impl.dart` implementation,
  `p2p_bridge_client.dart`, `go_bridge_client.dart` `relay:probe`, Android/iOS/
  macOS `relayProbe` dispatch, and `go-mknoon/bridge/bridge.go` `RelayProbe`.
- `_RaceResult.relayProbeEligible` plumbing in the edited file.
- FDC-03 invariant 4 ("no serial relay-probe carrier") — behaviourally asserted today by `probeRelayCallCount == 0` sentinels, which must remain green.

**Pre-edit confirmation (`ec86247eb`):** the chat helper had no invocation; its
suppression and `roadmap:DTR-05` inventory entry existed; the same-named
introduction helper was live; and the ratchet exited 0 with four reviewed
occurrences. **Post-edit confirmation:** the chat helper/call/event surface and
handwritten entry are absent, the ratchet exits 0 with three generated
occurrences, and the live introduction twin remains.

**Refuted:** the roadmap selector
`relay:probe calls relayProbe with payload JSON` is not missing. It is generated
by the payload-command table in `go_bridge_client_test.dart:175,211-212`, and
the exact `--plain-name` selector runs one passing test. The prior plan text that
proposed replacing that selector was wrong and is removed below.

**Resolved prerequisite:** `DTR05-AUTH-01` authorizes the exact helper-only
disposition and two-peer waiver; both categorical proof floors retain the live
protocol while recording that waiver. The completed predecessor tree and this
planning state are landed before implementation so Gate 0 can require an
attributable clean target/protected baseline.

## Graph Grounding Snapshot

- Pre-edit planning graph fingerprint / freshness: `d97359e0fa25bc6b`;
  `freshness=current` at planning time.
- Query / profile: `python3 graphify-arch/tdd_context.py query "Plan 276 remove dormant _tryRelayProbeSend send_chat_message_use_case.dart analyzer_suppression_ratchet_test.dart go_bridge_client_test.dart run_host_test_gates.sh" --profile tdd --budget 700`.
- Anchors: `_tryRelayProbeSend` ->
  `lib/features/conversation/application/send_chat_message_use_case.dart:2030`;
  `run_host_test_gates.sh script` -> `scripts/run_host_test_gates.sh:1`;
  `writePackageConfig` ->
  `test/unit/analyzer_suppression_ratchet_test.dart:1031`.
- Surfaced proof/gate files:
  `send_chat_message_use_case_test.dart`,
  `analyzer_suppression_ratchet_test.dart`,
  `scripts/run_test_gates.sh`, and `scripts/run_host_test_gates.sh`.
- Graph gaps requiring source search: the dynamically generated
  `relay:probe calls relayProbe with payload JSON` test name; the exact
  M-2/M-3 issue-code direction; the four Go selector registrations; and current
  device availability.
- Counterexample query / profile:
  `python3 graphify-arch/tdd_context.py query "_tryRelayProbeSend send_chat_message_use_case.dart exact deletion counterexample" --profile review --budget 800`.
  The compact result surfaced the introduction twin but not the same-named chat
  node even though both exact nodes existed in the pre-edit `graph.json`. Therefore
  compact-query output is navigation only. The post-refresh graph gate checks
  the two exact node IDs, while TC-01 and the literal source scan are the
  authoritative deletion proof.
- Closure refresh: `./graphify-arch/refresh_arch_graph.sh --incremental` exited
  0 with 4 changed code paths, 2,899 unchanged, and 0 deleted. The current
  fingerprint is `a79b2f04386f2be9`; the exact chat node is absent, the exact
  introduction node remains once at line 559, and only `graph.json` plus
  `manifest.json` changed as tracked Graphify outputs.
- Reuse rule: these anchors may be handed to review/execution, but current
  source and literal command output remain the proof.

---

## Root Cause (verify → refute confirmed)

This is a **disposition**, not a defect. The finding that survived the
adversarial pass is that the helper's retention condition is *already
discharged*, and was written as a testable condition:

> "Audit `_tryRelayProbeSend` for now-dead references; **leave the helper if
> FDC-02 still references it in-race, else mark dead-code for a follow-up
> cleanup** (do not delete cross-plan symbols speculatively)."
> — `FDC-03-concurrent-durable-inbox-safety-net-tdd-plan.md:240`, restated `:326`

Verified against real source:

| Claim | Evidence |
|---|---|
| Helper has zero call sites | Only three tokens of `_tryRelayProbeSend` exist in the file: declaration `:2030`, doc comment `:54`, narrative comment `:1403`. No invocation. |
| FDC-02's in-race leg is landed and does **not** reference it | `send_chat_message_use_case.dart:1395-1405` records the tail removal and names FDC-02's in-race relay-live leg as the live recovery path. |
| The ratchet's own removal condition is met | `production_unused_suppressions.json`: `reason` = retained "while its in-race replacement is completed"; `removalCondition` = "DTR-05 removes or rewires the exact helper and deletes this entry in the same change." |
| Re-wiring is counter-indicated | `FDC-02-staggered-ranked-race-lan-priority-tdd-plan.md:620` lists "**relay-live leg double-fires with the serial probe tail** (`_tryRelayProbeSend`) → two relay sends" as a hazard. |
| The architecture direction is settled against it | `FDC-CONVERGENCE-CHECKLIST.md` CV-10 (verdict 2026-07-01, 3-agent verify→refute): 1:1 cross-network transport is **store-and-forward by design**; Go never holds a peer `/p2p-circuit`; **Option B (hold live 1:1 circuits) was declined**. |

**Refuted / do-NOT-re-introduce:**

1. *"The helper is still needed for the online-relay-only peer whose circuit is not yet established."* — Refuted. That peer class is covered **by design** by FDC-03's concurrent durable-inbox custody plus push-to-wake; the transport-tier difference is an accepted FDC-03 outcome, not a regression this plan creates. Re-adding a probe leg re-opens the FDC-02 `:620` double-fire hazard. Do not "restore" the helper as a fix for slow relay-only delivery.
2. *"`_RaceResult.relayProbeEligible` in this file is dead too, delete it."* — Refuted. It **is** read at `:1104` to aggregate per-leg failures, and written at `:1012`, `:1949`, `:1972`, `:2001` from live failure classification. Retiring it means editing live classification code, which roadmap safety invariant (roadmap:56, "deletion and behavior refactoring are not combined in the same plan") forbids here. → DTR-11 candidate.
3. *"DTR-01's runtime-root inventory has a row to update."* — Refuted. `tool/runtime_roots/runtime_roots.json` contains no `relay` or `send_chat` record; the only tool-owned file naming this source path is `production_unused_suppressions.json`. No `runtime-roots` gate coupling.
4. *"A behavioral RED can prove the removal."* — Refuted, and importantly so:
   a behavioral test that changes when an **uncalled private function** is
   deleted would prove the function is *not* dead. The honest
   mutation-verifiable RED is **structural**: the ratchet's real-tree
   suppression AST scan plus TC-01's path-specific helper/call/event absence
   assertions. This is stated explicitly so a reviewer does not read the
   absence of a behavioral RED as a coverage hole.

---

## Authorization Recorded (`DTR05-AUTH-01`)

The roadmap decision-ledger row is Approved 2026-07-26. The current
authenticated project owner stated that they are the sole implementation
authority and approved this plan as Transport + Protocol owner.
`DTR08-COMP-003` preserves the split this approval relies on: helper disposition
is authorized, while protocol retirement still requires a separate floor and
plan.

`DTR05-AUTH-01` records, in the `DTR03-AUTH-01/02` style:
1. Approval of the **exact** removal set in
   *Scope Contract And Guard → In scope*.
2. Explicit **non**-authorization of: `relayProbeSendAttempts`, the introduction-feature twin, `P2PService.probeRelay`, `relay:probe`, Go `RelayProbe`, and the `relayProbeEligible` plumbing.
3. The **two-peer proof waiver** and its reason (below). No supported-client or
   protocol-retirement floor is required because no protocol surface changes,
   and `DTR08-COMP-003`'s UNKNOWN floor continues to govern the untouched
   protocol. The same landed authorization change amends the categorical
   DTR-05 proof floor and the helper-specific two-peer clause in
   `DTR08-COMP-003`, explicitly recording this leaf-only waiver without
   weakening the transport/protocol floor for any future live-boundary change.
   Both amended proof-floor sites use the stable marker
   `DTR05-AUTH-01 leaf-only two-peer waiver` so Gate 0 can verify them
   independently from the decision-ledger row.

**Approved two-peer proof waiver.** The roadmap otherwise requires "a named availability-bounded
two-peer proof" before removing the dormant helper (the Wave-1 DTR-05 waiver
paragraph and `DTR08-COMP-003`).
That bar is correct for a **protocol** change and disproportionate here: the
target is a library-private symbol whose fail-closed pre-edit census requires
one declaration, zero executable references/tear-offs, no Dart `part` linkage,
and no VM-entrypoint pragma. The suppressed `unused_element` diagnostic
corroborates that source proof; it is not, by itself, the waiver premise. A
two-phone run cannot observe a difference because no code path reaches the
deleted symbol. The waiver must be recorded **as a waiver with this reason** —
it must **not** be filed as `N/A (target unavailable by project policy)`
(roadmap:69-70), which is the mechanism for missing hardware and would put a
false claim in the ledger. The "conditional Go/native proof" self-resolves to
N/A by its own condition (no protocol boundary is touched).

## Execution Preconditions

1. **Satisfied by the prerequisite baseline: `DTR05-AUTH-01` and its proof-floor
   reconciliation are landed.** The decision-ledger row beginning
   `Disposition the dormant chat relay-probe helper` records the decision, and
   the Wave-1 DTR-05 waiver paragraph plus `DTR08-COMP-003` record the approved
   leaf-only waiver. An approval that leaves either categorical two-peer
   requirement intact is contradictory and does not authorize E1.
2. **Satisfied by the prerequisite baseline: DTR-04 and the planning artifacts
   are landed.** DTR-04 is Plan-green. Before the first implementation edit,
   Gate 0 still independently requires every DTR-05 target and protected
   source-diff path to be tracked and clean. Unrelated dirty paths, if any, are
   snapshotted and preserved; they are not overwritten, stashed, or reverted.
3. **Ratchet green at baseline.** Before any edit, `dart
   tool/analyzer_guard/analyzer_suppression_ratchet.dart check` must exit 0. If
   DTR-04's l10n regeneration drifted the three generated `unused_import`
   identities, that is a **pre-existing** condition to resolve first — never
   inside this change.
4. **Satisfied: waiver branch resolved.** `DTR05-AUTH-01` approves the named
   helper-only waiver. Any later proposal to touch the live protocol is outside
   this approval and must add its own registered, fully automated
   physical-Android + Android-emulator scenario.
5. **Dormancy census matches the reviewed source.** Before E4/E5 or any
   production edit, the Acceptance Gate 0 census must prove exactly three
   `_tryRelayProbeSend` tokens (one declaration plus two comments), no other
   executable reference or tear-off by exhaustion, no `part`/`part of`
   linkage, and no `vm:entry-point` pragma. Any drift is a stop-and-review
   condition; do not infer dormancy from the suppression alone.

---

## Scope Contract And Guard

**In scope** (one atomic change):

| # | Edit | Location |
|---|---|---|
| E1 | Delete the helper and its retention comment block | `lib/features/conversation/application/send_chat_message_use_case.dart:2025-2159` (incl. `// ignore: unused_element` at `:2029`). Verified extent: `:2159` is the function's closing brace, `:2160` is blank, `:2161` begins `Future<void> _persistOutgoingMedia({`. **This also deletes nine flow events** — see *Telemetry surface* below. |
| E2 | Delete the DTR-05 entry | `tool/analyzer_guard/production_unused_suppressions.json` (4 entries → 3) |
| E3 | Rewrite all eight stale production comment blocks; prose only | same file: `:51-68` (the **dartdoc of the live `relayProbeSendAttempts` constant**), `:1005-1009`, `:1372-1379`, `:1395-1405`, `:1881-1891`, `:1922-1936`, `:1977-1981`, and `:2436-2442`. State the current truth: FDC-02 owns the in-race relay-live leg; an all-fail race uses concurrent custody or one sequential inbox fallback; `relayProbeEligible` remains classification plumbing but does not trigger a serial probe; the success funnel covers relay-live race wins, not relay-probe wins. |
| E4 | Correct three stale mutation recipes, add stable RED discriminators, and add the shared-constant value sentinel | At `send_chat_message_use_case_test.dart:2946`, point the broad group comment to TC-03 as the canonical probe-tail mutation; keep/correct the TC-03 recipe at `:4580` using the exact temporary call block in the RED Catalog; add reason `DTR05-MUTATION serial-probe-count` to the existing `probeRelayCallCount == 0` assertion at `:4598`. At `p2p_service_fault_injection_test.dart:556`, replace the false probe-tail claim with the exact one-line TC-04 short-circuit mutation and a TC-03 cross-reference; add reason `DTR05-MUTATION concurrent-custody-store-count` to the existing one-store assertion at `:559`. Add `relayProbeSendAttempts remains one for live introduction and delete consumers` to `send_chat_message_use_case_test.dart` before production edits. |
| E5 | Rewrite the canonical inventory/source-removal assertions (the RED) | `test/unit/analyzer_suppression_ratchet_test.dart:866-949` — rename the test to `canonical inventory has three generated l10n identities and no dormant chat relay helper`; edit the count assertions at `:887-888`, adding reason `DTR05-RED inventory-count-3` to the first; reduce the path set at `:893-899`; replace the handwritten-entry block at `:913-929` with an `expect(inventory.entries.where((entry) => entry.sourceKind == 'handwritten'), isEmpty)` assertion; keep the generated-entry loop at `:930-948`; then read the exact chat source and assert it contains none of `_tryRelayProbeSend`, `RegExp(r'\.probeRelay\s*\(')`, or `CHAT_MSG_SEND_RELAY_PROBE_`, adding reason `DTR05-M4 helper-absent` to the symbol assertion. |
| E6 | Roadmap bookkeeping | Verify the decision-ledger authorization and categorical proof-floor waiver are resolved in the landed baseline; reconcile the DTR-02 and DTR-05 registry rows, the Wave-1 gate-ledger row, and `DTR08-COMP-003` without weakening its retained-protocol floor. Preserve the runnable dynamic Dart `relay:probe calls relayProbe with payload JSON` selector and the four exact single-test Go commands. |
| E7 | Reconcile the affected index rows after GREEN closure | `Test-Flight-Improv/00-INDEX.md` — preserve Plan 273's historical four-identity landing while recording the current three-generated state; verify Plan 275 remains `Plan-green`; only after every DTR-05 gate passes, promote Plan 276 to `Plan-green` / `implementation-complete` and cite the resolved `DTR05-AUTH-01` plus its approved waiver. Never leave the final row authorization-gated after successful execution. |
| E8 | Preserve the pre-execution `execution-ready` / `implementation-ready` state until implementation evidence exists, then atomically reconcile this plan's final state after GREEN closure | This plan's header `Status` / `Classification` and opening synopsis, `Device/Relay Proof Profile`, `Arbiter Decision`, `Handoff`, and `Execution Progress`. Do not pre-populate a success verdict. Only after every gate passes, change the plan itself to `Plan-green` / `implementation-complete`, retain the approved waiver record, replace pre-execution text with actual closure evidence, and append the bounded final heartbeat. |

**E3 is the trap:** `:51-68` is the dartdoc of a **live** constant, and four
other blocks describe still-live `relayProbeEligible` classification sites.
Every E3 edit rewrites prose only — the constant's name/value (`1`), the
classification expressions, and all executable identities remain unchanged.

The eight base edit paths above exclude generated Graphify output. The
architecture graph's exact expected refresh outputs,
`graphify-arch/graphify-out/graph.json` and
`graphify-arch/graphify-out/manifest.json`, are already dirty at planning time
from repository hooks. Execution records their baseline status and diff stat
before editing, then allows the incremental refresh to coalesce deterministic
changes in those two files. They are not claimed as plan-exclusive source
changes. No wildcard Graphify exception and no third **tracked or unignored**
graph-output path is allowed. `refresh_arch_graph.sh` also rebuilds the ignored
`graphify-arch/tdd-overlay.json`; that expected scratch output remains outside
the diff allowlist.

### Telemetry surface deleted by E1 (sibling enumeration)

E1 removes the **only** emitter of nine `emitFlowEvent` names:
`CHAT_MSG_SEND_RELAY_PROBE_` + `BEGIN` · `CONNECTED` · `DIAL` · `DIAL_ERROR` ·
`ERROR` · `FALLBACK` · `NO_RESERVATION` · `SEND_ERROR` · `SEND_RETRY`.

**None of them fires today.** `CHAT_MSG_SEND_RELAY_PROBE_BEGIN` is emitted at
exactly one place in `lib/` — `send_chat_message_use_case.dart:2040`, inside the
uncalled helper — so every one of the nine has been unreachable since FDC-03.
Deleting them changes no observable telemetry. Two consumers exist and were
verified:

| Consumer | What it does | Effect of E1 |
|---|---|---|
| `integration_test/routing_smoke_harness.dart:845-856` | filters `…PROBE_BEGIN` into `s15ProbeEvents`, writes `'probeAttempted': s15ProbeEvents.isNotEmpty` to the `s15_alice_sent` signal | **none** — already always `false`. `run_routing_smoke_e2e.dart:494` only *prints* it (`probe=${…}`); no assertion, no pass/fail. classify_path records the file as `"support"` (`check_reliability_simulation_discovery.sh:313`), not a `--only N` scenario. |
| `send_chat_message_use_case_test.dart:4568` | `expect(names, isNot(contains('CHAT_MSG_SEND_RELAY_PROBE_CONNECTED')))` | **none** — a negative assertion; stays green. It becomes permanently vacuous, which is acceptable: it still guards against re-introducing the event. |

**Residual, accepted:** `routing_smoke_harness.dart` keeps a filter for an event
string that no longer exists in production — dead telemetry that *reads* as live.
It is left in place rather than cleaned, because editing a registered simulator
harness for a cosmetic reason widens this change's blast radius past a dead-code
deletion. Recorded as a DTR-11 candidate, and gate 8 runs the discovery check so
a registration break would surface.

### Must preserve

- `relayProbeSendAttempts` name/value/identity -> TC-05 and TC-06.
- The live introduction `_tryRelayProbeSend` -> TC-05.
- `P2PService.probeRelay`, Dart `relay:probe`, Go `RelayProbe`, and Go relay
  selection/dial behavior, including the Dart service/command maps and Android,
  iOS, and macOS platform dispatch -> TC-07, TC-08, and the source-diff guard.
- `_RaceResult.relayProbeEligible` classification plumbing -> TC-03/TC-04 plus
  the source-diff guard.
- FDC-03 invariant 4 (zero serial relay-probe calls) -> TC-03 and TC-04.

### Hard `Do not`

- Do not change `relayProbeSendAttempts`; only its dartdoc prose changes.
- Do not edit
  `lib/features/introduction/application/introduction_outbound_delivery.dart`,
  `lib/features/conversation/application/delete_message_use_case.dart`,
  `lib/core/services/p2p_service.dart`,
  `lib/core/services/p2p_service_impl.dart`,
  `lib/core/bridge/p2p_bridge_client.dart`,
  `lib/core/bridge/go_bridge_client.dart`,
  `android/app/src/main/kotlin/com/mknoon/app/GoBridge.kt`,
  `ios/Runner/GoBridge.swift`,
  `macos/Runner/MainFlutterWindow.swift`,
  `go-mknoon/bridge/bridge.go`, or anything under `go-mknoon/node/`.
- Do not remove or refactor `_RaceResult.relayProbeEligible` or its live
  failure-classification sites.
- Do not weaken or delete a `probeRelayCallCount == 0` assertion.
- Do not add `test/unit/**` to a curated family in this change.
- Do not run full `host-all` as a per-plan gate.
- Do not use `git stash`, `git checkout`, or another destructive reset on this
  shared checkout.

### Deferred / accepted differences

- `_RaceResult.relayProbeEligible` plumbing → **DTR-11** (write-heavy but genuinely read at `:1104`; retiring it is a behavior refactor).
- Any `probeRelay` / `relay:probe` / `RelayProbe` protocol retirement → **a separate plan with its own supported-client floor** (`DTR08-COMP-003`).
- Adding `test/unit/**` to a curated family array → **DTR-02 / DTR-11** tooling registration (see *Harness registration gap*).
- The `routing_smoke_harness.dart:845-856` filter for the now-unreachable event
  remains inert and is owned by DTR-11.

### Dependencies

- DTR-02's ratchet loses its only handwritten entry.
- Wave 1 aggregate `host-all` was owned by the DTR-03/DTR-04/DTR-05 wave
  closure and is now accepted in the roadmap; final rollout/release owns the
  second aggregate `host-all`.
- FDC-03 supplies the discharged retention condition; no FDC production change
  is part of this plan.
- `DTR05-AUTH-01` owns the disposition and two-peer-waiver decision.

## Files To Inspect Next
- **Production (edited):** `lib/features/conversation/application/send_chat_message_use_case.dart`
- **Production (read-only, must not change):** `lib/features/introduction/application/introduction_outbound_delivery.dart` (`:347`, `:559`, `:580`), `lib/features/conversation/application/delete_message_use_case.dart` (`:536`, `:985`), `lib/core/services/p2p_service_impl.dart` (`:5128-5142`), `lib/core/bridge/go_bridge_client.dart` (`:124`), and the Android/iOS/macOS `relayProbe` dispatch cases named under *Hard Do not*
- **Tooling:** `tool/analyzer_guard/production_unused_suppressions.json`, `tool/analyzer_guard/analyzer_suppression_ratchet.dart` (`_compareInventory` `:735-775`)
- **Tests (edited):** `test/unit/analyzer_suppression_ratchet_test.dart`, and the three comment sites in E4
- **Dependency-only context:** `scripts/check_flutter_analyze_strict.sh:20-23`, `scripts/test/flutter_analyze_strict_contract_test.sh:290-305`

## Existing Tests Covering This Area

| Test | Covers | Status |
|---|---|---|
| `analyzer_suppression_ratchet_test.dart::canonical inventory has three generated l10n identities and no dormant chat relay helper` | Real-tree ratchet scan; entry count, occurrence count, path set, handwritten fingerprint, and exact chat-source absence | **causal RED → GREEN** |
| `analyzer_suppression_ratchet_test.dart::rejects unexpected relocated duplicate and stale identities` (`:253`) | `unexpected-suppression`, `stale-inventory-entry`, `duplicate-suppression` | **exists** — atomicity already tool-tested; no new test needed |
| `send_chat_message_use_case_test.dart::FDC-03-03b race-fail whose concurrent copy ALSO fails reaches the former probe location WITHOUT running the probe (invariant #4 lock)` (`:4571`) | reaches the removed-probe location and asserts `probeRelayCallCount == 0` | **exists** — preservation |
| `p2p_service_fault_injection_test.dart::discover-miss send to an online peer takes durable inbox custody without the relay probe, and drains to the recipient` (`:533`) | custody, not live delivery; `probeRelayCallCount == 0` | **exists** — preservation |
| `introduction_outbound_delivery_test.dart::relay-probe fallback delivers after the direct path fails` (`:175`) | the **live twin** + the shared constant | **exists** — preservation (guards over-broad delete) |
| `introduction_outbound_delivery_test.dart::retryPendingIntroductionDeliveries delivers a failed row through relay probe when inbox storage fails` (`:367`) | same | **exists** — preservation |
| `delete_message_use_case_test.dart::deleteMessageForEveryone keeps a sender-visible failed tombstone on send failure` (`:704`) | compiles and traverses the delete-message consumer of the live constant | **exists** — preservation |
| `p2p_bridge_client_test.dart::callP2PRelayProbe timeout / successful probe still works (no regression)` and `… / bridge hang triggers TimeoutException after 5s`; `go_bridge_client_test.dart::command routing - with payload / relay:probe calls relayProbe with payload JSON` | Dart relay-probe wrapper, its five-second timeout boundary, and command dispatch remain | **exists** — preservation |

**Coverage added by this plan:** E4 added the shared constant's value-`1` GREEN
sentinel, and E5 added path-specific helper/call/event absence assertions to
TC-01 because the ratchet scan alone cannot prove a helper body disappeared. The
over-broad-delete risk for the identically named introduction twin is already
covered by two existing sentinels and is not duplicated.

**Already in curated family arrays?**
- `send_chat_message_use_case_test.dart` → `ONE_TO_ONE_TESTS` (array declared `run_test_gates.sh:21`, entry at `:45`) **and** `ONE_TO_ONE_HOST_TESTS` (`run_host_test_gates.sh:36`).
- `p2p_service_fault_injection_test.dart` → **no curated family**; auto-globs into `core-host-all` (`test/core/**`).
- `introduction_outbound_delivery_test.dart` → **no curated family**; auto-globs into `feature-host-all`.
- `analyzer_suppression_ratchet_test.dart` → **no curated family and no per-plan host scope** (see below).

### Harness registration gap (finding)

`scripts/run_host_test_gates.sh:378-422` builds each scope by path:
`feature-host-all` = `rg --files test/features`, `core-host-all` = `rg --files
test/core`. **Neither includes `test/unit/`.** Only `host-all` (`rg --files test`,
`:384`) covers it — and roadmap:61 forbids `host-all` as a per-plan gate.

Consequence: the RED test auto-registers only in the later aggregate
`host-all`, not in a per-plan family. This plan therefore names its exact
`flutter test ... --plain-name ...` command as the direct per-plan gate.
Adding `test/unit/**` to a family is owned by DTR-02/DTR-11, not by this plan.
The **tool** contract is separately gated everywhere:
`check_flutter_analyze_strict.sh:20-23` runs
`analyzer_suppression_ratchet.dart check` and exits on its status.

---

## RED Test Catalog  (add BEFORE any production edit — INV-RED-FIRST)

**1. `test/unit/analyzer_suppression_ratchet_test.dart::canonical inventory has three generated l10n identities and no dormant chat relay helper`**
- **Tier:** unit (tool + source-removal contract). `AnalyzerSuppressionRatchet(repoRoot: …, inventory: …).check()` performs a real AST scan of suppression directives in the real tree. Separate path-specific source assertions prove the body/call/event surface is absent; the ratchet alone cannot prove that.
- **Shape/setup:** unchanged from `:866` — load the real `production_unused_suppressions.json`, run `.check()` against `Directory.current`.
- **RED on pre-edit baseline `ec86247eb` because:** after E5 changed the
  expectations, the baseline still had
  `inventory.entries` length **4**, so the first new `hasLength(3)` assertion
  fails with stable reason `DTR05-RED inventory-count-3`. The source also still
  has four occurrences, the send-path entry, and one handwritten entry; those
  are GREEN contract clauses, not additional failure messages expected from
  the same fail-fast run.
- **GREEN after the change asserts:** `inventory.entries` has length **3**; `result.occurrences` has length **3**; the path set is exactly the three `lib/l10n/app_localizations_{ar,de,en}.dart` files; `entries.where((e) => e.sourceKind == 'handwritten')` **is empty**; `result.exitCode == 0`, `trustworthy`, `hasPolicyDrift == false` all still hold; and the exact chat source contains none of `_tryRelayProbeSend`, `RegExp(r'\.probeRelay\s*\(')`, or `CHAT_MSG_SEND_RELAY_PROBE_`.
- **Exact source clauses:**
  `final chatSource = File('$repoRoot/lib/features/conversation/application/send_chat_message_use_case.dart').readAsStringSync();`,
  then
  `expect(chatSource, isNot(contains('_tryRelayProbeSend')), reason: 'DTR05-M4 helper-absent');`,
  `expect(RegExp(r'\.probeRelay\s*\(').hasMatch(chatSource), isFalse);`, and
  `expect(chatSource, isNot(contains('CHAT_MSG_SEND_RELAY_PROBE_')));`.
- **Mutation that re-reds (M-1):** restore E1 + E2 together (helper, `// ignore`, JSON entry) → counts return to 4/4 and the handwritten set is non-empty → RED.
- **Mutation that closes the retained-body counterexample (M-4, from GREEN):**
  restore the E1 helper body **without** its suppression, inventory entry, or
  retention comment. Ratchet counts remain 3/3, but the path-specific
  `_tryRelayProbeSend` assertion fails. Reverse only that temporary patch.
- **Distinct discriminator:** the two count assertions come from **different sources** — `inventory.entries` reads the JSON, `result.occurrences` reads the **scanned source tree**. A one-sided edit moves only one of them, and the tool additionally raises a distinctly coded issue (below). They cannot both be satisfied by an incomplete change.

**2. Atomicity — locked by the tool's existing bidirectional contract (no new test).**
`analyzer_suppression_ratchet.dart:735-775` (`_compareInventory`) emits:
- `unexpected-suppression` — a suppression exists in source with no inventory entry (JSON-only removal);
- `stale-inventory-entry` — an inventory entry with no matching source suppression (source-only removal).

Both codes already have fixture coverage in
`rejects unexpected relocated duplicate and stale identities`,
so they need **executing**, not authoring:
- **Mutation M-2 (from GREEN):** restore E2 only (inventory entry present,
  source suppression absent) → `check` exits non-zero with
  `stale-inventory-entry`.
- **Mutation M-3 (from GREEN):** restore E1 only (source suppression present,
  inventory entry absent) → `check` exits non-zero with
  `unexpected-suppression`.

**3. Mutation-recipe correctness (E4) — verified by execution, not prose.**
Only TC-03 reaches the former probe location: its concurrent inbox copy is
forced to fail. The broad send-test comment and the service fault-injection
comment must stop claiming every custody fixture re-reds on probe-tail restore.
The corrected canonical recipe is proven once during execution: reapply the
inverse of E1 from the recorded patch, then insert this exact temporary block
immediately before `// All active paths failed — try offline inbox fallback
once.`:

```dart
if (raceResult.relayProbeEligible) {
  await _tryRelayProbeSend(
    p2pService,
    targetPeerId,
    jsonString,
    failureReason: failureReason,
    messageId: resolvedMessageId,
  );
}
```

TC-03 must observe `probeRelayCallCount == 1` and red; reverse both temporary
patches. Its existing zero-count assertion carries stable reason
`DTR05-MUTATION serial-probe-count`, so compile/unrelated failures cannot satisfy
the RED gate. TC-04 succeeds concurrent custody and returns before that seam.
Its exact mutation is one line: replace
`return persistInboxAccepted(recordInboxAttempt: false);` with
`await persistInboxAccepted(recordInboxAttempt: false);`. Falling through to
the sequential store violates the existing one-store/one-copy assertion with
stable reason `DTR05-MUTATION concurrent-custody-store-count`; reverse that line
immediately after the red.

---

## Test Contract

| Case | Behavior | Named test/proof | Tier / fixture | Pre-edit baseline -> GREEN | Mutation | Gate / registration |
|---|---|---|---|---|---|---|
| **TC-01** | Helper body/call/events, suppression, and inventory entry disappear atomically | `test/unit/analyzer_suppression_ratchet_test.dart::canonical inventory has three generated l10n identities and no dormant chat relay helper` | unit/tool + exact chat-source contract; real repository AST suppression scan and path-specific source assertions | causal RED: edited expectations see 4 entries/occurrences first with `DTR05-RED inventory-count-3` -> GREEN: 3 generated entries/occurrences, three l10n paths, zero handwritten, and no chat helper/call/event tokens | M-1 restores E1+E2 -> same count discriminator; M-4 restores only the unsuppressed helper body -> `DTR05-M4 helper-absent` while ratchet stays 3/3 | `flutter test test/unit/analyzer_suppression_ratchet_test.dart --plain-name 'canonical inventory has three generated l10n identities and no dormant chat relay helper'`; AUTO (`host-all` glob), exact direct per-plan gate |
| **TC-02** | One-sided removal fails closed | `test/unit/analyzer_suppression_ratchet_test.dart::rejects unexpected relocated duplicate and stale identities` | unit/tool fixture | GREEN sentinel -> GREEN sentinel | M-2 restore E2 only -> `stale-inventory-entry`; M-3 restore E1 only -> `unexpected-suppression` | `flutter test test/unit/analyzer_suppression_ratchet_test.dart --plain-name 'rejects unexpected relocated duplicate and stale identities'` plus `dart tool/analyzer_guard/analyzer_suppression_ratchet.dart check` under each mutation; AUTO (`host-all` glob), exact direct per-plan gate, and strict-analyze tool gate |
| **TC-03** | FDC-03 invariant 4 remains: reaching the former probe location performs zero serial probes | `test/features/conversation/application/send_chat_message_use_case_test.dart::FDC-03-03b race-fail whose concurrent copy ALSO fails reaches the former probe location WITHOUT running the probe (invariant #4 lock)` | application host; fake P2P/inbox | GREEN sentinel -> GREEN sentinel | restore the helper and insert the exact RED-Catalog call block before `CHAT_MSG_SEND_RACE_ALL_FAILED` -> `probeRelayCallCount == 1` with `DTR05-MUTATION serial-probe-count` | `flutter test test/features/conversation/application/send_chat_message_use_case_test.dart --plain-name 'FDC-03-03b race-fail whose concurrent copy ALSO fails reaches the former probe location WITHOUT running the probe (invariant #4 lock)'`; AUTO feature glob + `ONE_TO_ONE_TESTS` |
| **TC-04** | Discover-miss still takes durable inbox custody rather than live probe delivery | `test/core/services/p2p_service_fault_injection_test.dart::discover-miss send to an online peer takes durable inbox custody without the relay probe, and drains to the recipient` | host fault-injection; fake network | GREEN sentinel -> GREEN sentinel | replace `return persistInboxAccepted(recordInboxAttempt: false);` with `await persistInboxAccepted(recordInboxAttempt: false);` -> fall-through reds with `DTR05-MUTATION concurrent-custody-store-count` | `flutter test test/core/services/p2p_service_fault_injection_test.dart --plain-name 'discover-miss send to an online peer takes durable inbox custody without the relay probe, and drains to the recipient'`; AUTO core glob, direct per-plan gate |
| **TC-05 — PROD-CRITICAL** | Same-named live introduction helper and shared attempt constant survive | `test/features/introduction/application/introduction_outbound_delivery_test.dart::relay-probe fallback delivers after the direct path fails`; `test/features/introduction/application/introduction_outbound_delivery_test.dart::retryPendingIntroductionDeliveries delivers a failed row through relay probe when inbox storage fails` | application host; relay-probe fake | GREEN sentinel -> GREEN sentinel | delete the introduction helper or shared constant -> both tests red/compile red | `flutter test test/features/introduction/application/introduction_outbound_delivery_test.dart --plain-name 'relay-probe fallback delivers after the direct path fails'`; `flutter test test/features/introduction/application/introduction_outbound_delivery_test.dart --plain-name 'retryPendingIntroductionDeliveries delivers a failed row through relay probe when inbox storage fails'`; AUTO feature glob, direct per-plan gates |
| **TC-06** | Shared attempt constant stays present with value `1`, and its delete-message consumer survives | added `test/features/conversation/application/send_chat_message_use_case_test.dart::relayProbeSendAttempts remains one for live introduction and delete consumers`; existing `test/features/conversation/application/delete_message_use_case_test.dart::deleteMessageForEveryone keeps a sender-visible failed tombstone on send failure` | unit/application host; constant assertion + fake P2P | GREEN sentinel before production edit -> GREEN sentinel after deletion | change constant to `2` -> value sentinel red; delete it -> both proofs compile red | `flutter test test/features/conversation/application/send_chat_message_use_case_test.dart --plain-name 'relayProbeSendAttempts remains one for live introduction and delete consumers'`; `flutter test test/features/conversation/application/delete_message_use_case_test.dart --plain-name 'deleteMessageForEveryone keeps a sender-visible failed tombstone on send failure'`; AUTO feature glob + `ONE_TO_ONE_TESTS` |
| **TC-07** | Dart relay-probe wrapper, its timeout boundary, and `relay:probe` command dispatch remain | `test/core/bridge/p2p_bridge_client_test.dart::callP2PRelayProbe timeout / successful probe still works (no regression)`; `… / bridge hang triggers TimeoutException after 5s`; `test/core/bridge/go_bridge_client_test.dart::command routing - with payload / relay:probe calls relayProbe with payload JSON` | unit/application host; fake/hanging bridge | GREEN sentinel -> GREEN sentinel | remove the wrapper invocation/timeout or the `relay:probe` map entry -> corresponding exact test red | two exact `p2p_bridge_client_test.dart` selectors (`successful probe…`, `bridge hang…`) plus `flutter test test/core/bridge/go_bridge_client_test.dart --plain-name 'relay:probe calls relayProbe with payload JSON'`; AUTO core glob + existing `ONE_TO_ONE_TESTS` entries |
| **TC-08** | Existing Go active-send timing/config and relay-selector smoke coverage remains green; `go-mknoon/node` remains byte-unchanged | `go-mknoon/node/config_test.go::TestForegroundRelayProbeIsNotRequiredForActiveSendPath`; `go-mknoon/node/node_test.go::TestDialPeerViaRelayTriesAllAddresses`; `go-mknoon/node/multi_relay_test.go::TestDialPeerViaRelay_TriesSecondRelayWhenFirstFails`; `go-mknoon/node/multi_relay_test.go::TestDialPeerViaRelay_SingleRelayStillWorks` | Go host; duration assertions plus selector/error-path smoke fixtures | GREEN sentinel -> GREEN sentinel | the config test can red on exceeded interactive dial/discover ceilings; the three relay tests are smoke selectors and do **not** causally prove every dial/failover attempt. Any Go implementation edit is rejected by the clean-baseline and staged/unstaged source-diff guards. | four exact single-test `go test ./node -v -run '^TestName$' -count=1` commands in Acceptance Gate 6; DIRECT existing Go selectors, N/A — no new harness registration |

### Selector verification

`relay:probe calls relayProbe with payload JSON` is generated by
`go_bridge_client_test.dart:175,211-212`; its exact `--plain-name` selector runs
one test and passes. E6 preserves that Dart selector and replaces only the
vacuous escaped-pipe Go command in the roadmap. The four Go selectors are
direct exact per-plan preservation commands; they are **not** pinned in
`host-all`'s enumerated Go tail, and TC-08 no longer claims they mutate or prove
the Go `RelayProbe` bridge implementation. Specifically,
`TestForegroundRelayProbeIsNotRequiredForActiveSendPath` checks only dial and
discover duration ceilings; the three relay selectors inspect grouped
addresses/error outcomes and are smoke coverage, not proof that every
address/relay was attempted. The protected `go-mknoon/node` no-diff guard is the
causal preservation proof for this deletion plan.

**PROD-CRITICAL leg — TC-05.** It is the only row whose failure ships a
user-visible regression: deleting the introduction-feature twin (same exact
symbol name, live, called at `introduction_outbound_delivery.dart:347`) silently
removes the relay-probe fallback from introduction delivery. Do **not** treat
TC-01's green as sufficient on its own — TC-01 only asserts what disappeared from
the *chat* file. Run TC-05 explicitly, every time.

Gate economy: per-row gates are focused paths or one curated family. Exactly one
full sweep appears (`feature-host-all`, final pre-close) because `DTR08-COMP-003`
requires it for a feature-code change, and it is always run in batch-parallel form.

## Risks And Blind Spots

- **Lifecycle / derived-state durability** — **N/A, justified.** No state, latch, cache, or derived UI is added or changed; the change deletes an uncalled private function and edits comments plus a JSON inventory. There is no reopen/restart surface to reconstruct.
- **Sibling-surface consistency** — **APPLIES → TC-05, TC-06, TC-07.** The parallel surfaces of "relay probe" are the introduction-delivery twin, the delete-message consumer, and the bridge/Go protocol. The dormancy condition applies to the **chat** helper only; the asymmetry is deliberate and is test-locked by three preservation rows rather than asserted in prose. This is the plan's single highest-risk class — the twin shares an **exact symbol name** with the deletion target.
- **Destructive-action side-effects** — **APPLIES → TC-01 (removed) + TC-05/TC-06/TC-07/TC-08 (preserved).** This change *is* a destructive action. TC-01 asserts precisely what disappears (the helper/call/event tokens, one suppression occurrence, one inventory entry, and one path from the set); the preservation rows assert what survives. Nothing asserts merely that "an affordance appeared".
- **Invariant re-verification under new transitions** — **N/A with a note.** No new state transition is introduced. FDC-03's invariant 4 ("no serial relay-probe carrier") was previously justified by *behavior* (the block was not called); after E1 it is additionally guaranteed *structurally* (the callee does not exist). The behavioral assertions are **not** retired on that basis — TC-03 and TC-04 keep asserting `probeRelayCallCount == 0`, so the invariant remains locked at the tier where it was originally proven.

## Invariants (locked by tests)
- **INV-1** The production suppression ratchet contains exactly three entries, all `sourceKind: generated`, all `flutter.gen-l10n`-owned → **TC-01**.
- **INV-2** No suppression of any kind and no dormant helper/call/event token remains in `send_chat_message_use_case.dart` → **TC-01** (path-set assertion plus exact source assertions and the literal source scan).
- **INV-3** A non-atomic removal cannot pass the tool gate → **TC-02** (M-2/M-3).
- **INV-4** FDC-03 invariant 4 holds behaviourally: the 1:1 send path performs zero relay probes → **TC-03, TC-04**.
- **INV-5** Every live shared relay-probe file outside the edited chat file
  (introduction twin, service implementation, Dart/native command maps, Go
  bridge/node) is byte-unchanged → **TC-05, TC-06, TC-07, TC-08** plus staged
  and unstaged no-diff guards. Inside the edited chat file, the
  `relayProbeSendAttempts` declaration/value and executable
  `relayProbeEligible` plumbing are semantically unchanged; TC-03/TC-04/TC-06
  and explicit hunk review lock that narrower claim while E3 legitimately
  changes their surrounding prose.
- **INV-RED-FIRST** and **INV-MUTATION-VERIFIED** apply to every row above.

## Implementation Steps

1. **Contract extraction.** Record `git status --short`. Confirm
   `DTR05-AUTH-01`, the Wave-1 DTR-05 waiver paragraph, and
   `DTR08-COMP-003` contain one consistent landed leaf-only waiver;
   DTR-04/planning artifacts have landed; and every DTR-05 target/protected path
   is tracked and clean. Run the exact Gate 0 dormancy census and stop on any
   count, library-boundary, entrypoint, or target-path drift. Preserve unrelated
   dirty paths. Separately record the pre-existing status and diff stat of the
   two exact tracked Graphify outputs named in the scope contract; their dirt is
   expected and does not waive any source-path precondition.
2. **Baseline.** Run `dart tool/analyzer_guard/analyzer_suppression_ratchet.dart check` — **must exit 0** before any edit. **Stop-if** non-zero: that is pre-existing drift (likely l10n regeneration); resolve it in its own change, not here.
3. **Test-first contracts (E4, E5).** Add TC-06's exact value-`1` GREEN
   sentinel and run it successfully on the pre-edit baseline. Then rewrite
   `analyzer_suppression_ratchet_test.dart:866-949` to the
   three-generated-entry contract: rename the test; change the two count
   assertions at `:887-888`; reduce the path set at `:893-899`; replace
   `:913-929` with an explicit handwritten-entry `isEmpty` assertion; retain
   the generated loop at `:930-948`; and add the exact chat-source absence
   assertions and stable reasons from E5. Run the exact TC-01 command and
   require non-zero with `DTR05-RED inventory-count-3`, not a compile error.
4. **GREEN step A (E1).** Delete `send_chat_message_use_case.dart:2025-2159` — the retention comment block, the `// ignore: unused_element`, and the function body through its closing brace. **Seam:** delete the top-level function only; do not touch `_RaceResult`, `relayProbeSendAttempts`, or any failure-classification site.
5. **GREEN step B (E2).** Delete the DTR-05 object from `production_unused_suppressions.json`, leaving the three generated entries and a valid JSON array.
6. **GREEN step C (E3).** Rewrite only the eight E3 comment blocks. The live
   constant's dartdoc describes its introduction/delete consumers; failure
   classification comments no longer promise a serial probe/tail; the custody
   block describes concurrent custody followed only by the single sequential
   inbox fallback; and the success funnel says relay-live race win. Run the
   stale-phrase source scan. **Stop-if** any executable token, the constant's
   value/identity, or a `relayProbeEligible` expression changes → replan.
7. **GREEN step D (E4) + recipe verification.** Correct the three recipe
   comments with the TC-03/TC-04 distinction above. Temporarily restore the
   helper and insert the exact RED-Catalog call block, run TC-03's exact
   `--plain-name` command, require RED with
   `DTR05-MUTATION serial-probe-count` and `probeRelayCallCount == 1`, then
   reverse both temporary changes with explicit patches. Apply the exact
   one-line TC-04 fall-through mutation, require
   `DTR05-MUTATION concurrent-custody-store-count`, and reverse it. Record both
   outputs.
8. **Direct GREEN.** Run TC-01 exactly and require exit 0/zero failures. Run the
   fail-closed helper/call/event/stale-comment source scan, then
   `./scripts/check_flutter_analyze_strict.sh`; both must exit 0.
9. **Mutation re-red.** Execute M-1, then from GREEN restore E2 only for M-2,
   then restore E1 only for M-3, then restore the unsuppressed/inventory-free
   helper body for M-4. Reverse each temporary mutation with an explicit patch;
   never use `git checkout`. Require the exact failure code or source assertion
   documented in the RED Catalog.
10. **Preservation and family sweeps.** Run Acceptance sections 4 through 8 in
    order and require every applicable gate green.
11. **Non-verdict bookkeeping (E6, E7).** Verify the landed decision-ledger
    authorization and categorical proof-floor reconciliation; reconcile the
    DTR-02 registry and index entries; preserve the already-runnable dynamic
    `relay:probe calls relayProbe with payload JSON` selector; and replace the
    escaped-pipe Go regex with the same four exact single-test commands used
    below. Do not promote DTR-05 or its index row yet. **Stop-if** the named
    decision-ledger authorization is missing or open.
12. **Graphify refresh.** `./graphify-arch/refresh_arch_graph.sh --incremental`
    once — an app-owned symbol was removed. Check the exact graph IDs: the chat
    node must be absent and the introduction node present. Treat the compact
    query as navigation only because its same-name ranking omitted the live chat
    node during review. The ignored `tdd-overlay.json` rebuild is expected.
    (Authoring this plan needed no refresh; documentation-only changes are
    exempt under the roadmap's Graph Maintenance policy.)
13. **Diff scope review.** Review staged, unstaged, and untracked paths. The
    DTR-05 allowlist contains eight base paths: one production Dart file, one
    inventory JSON file, three test files, the roadmap, `00-INDEX.md`, and this
    plan. Only the already-snapshotted `graph.json` and `manifest.json` may
    additionally change when the required incremental refresh coalesces their
    generated state. Any newly changed path outside those ten exact paths is
    blocking scope drift. The ignored `graphify-arch/tdd-overlay.json` is
    expected scratch output and is not a tracked/unignored changed path.
14. **Final-state bookkeeping (E6, E7, E8).** Only after steps 1-13 are green,
    promote the roadmap DTR-05 registry, Wave-1 gate-ledger, and
    `DTR08-COMP-003` rows; the Plan 276 index row; and this plan's own header
    status/classification to `Plan-green` / `implementation-complete`, citing
    the resolved authorization and waiver plus device-preservation evidence.
    Reconcile the opening synopsis, `Device/Relay Proof Profile`,
    `Arbiter Decision`, `Handoff` status/unresolved-evidence fields, and
    `Execution Progress` in the same edit so no blocked-state prose survives
    successful closure. Rerun `git diff --check`, `git diff --cached --check`,
    both protected-path `--exit-code` guards, and the
    staged/unstaged/untracked path-list checks so this final documentation edit
    cannot bypass hygiene or scope closure.

## Execution Hazards

| Hazard | Mitigation |
|---|---|
| **Over-broad delete of the same-named live twin** (`introduction_outbound_delivery.dart:559`) — a repo-wide grep-and-delete looks correct and compiles nothing away visibly | TC-05 (two named introduction tests) + the explicit source-diff guard |
| **Non-atomic removal** (source without JSON, or JSON without source) | TC-02 / M-2 / M-3 — the tool fails closed with distinct codes; `check_flutter_analyze_strict.sh` gates it everywhere |
| **The live constant's dartdoc edit drifts into a value change** | Step 6 stop-if + TC-06 (both consumers fail to compile if the constant moves) |
| **Ratchet drift from DTR-04's l10n regeneration** masquerading as this change's failure | Precondition 3 + step 2 baseline: the ratchet must be green *before* the first edit |
| **Stale mutation recipes silently rot** FDC-03's re-red story | E4 + step 7, which executes the corrected recipe once rather than asserting it in prose |
| **Concurrent-session collision** on this shared checkout | Precondition 2; never `stash`/`checkout` shared files; `git status --short` before starting |

## Rollback

Rollback reverts the **entire atomic E1-E8 implementation change**, including
E5's three-entry/source-absence contract and final roadmap/index/plan outcome
bookkeeping. Selectively restoring E1/E2 while leaving E5 at three entries
would make the repository intentionally red. If the change is committed, use a
plain `git revert` of that exact implementation commit; if it is not committed,
apply the recorded inverse patch across all eight edit paths. Then rerun the
ratchet, TC-01, strict analysis, and the incremental Graphify refresh so source,
inventory, tests, graph, and status agree.

The already-landed owner decision and categorical waiver authorization are
historical evidence and remain recorded; rollback changes the implementation
outcome, not the fact that the disposition was authorized. This is why the
authorization/proof-floor reconciliation must land before and separately from
the implementation change.

No storage, wire, native, Go, or protocol rollback applies — none of those
surfaces is touched. **Do not** restore or alter `relayProbeSendAttempts`; it is
never removed, so it is never part of a rollback. There is no released-artifact
or data-format dimension: the deleted symbol is unreachable, so no shipped build
behaves differently before or after, and a revert is a plain `git revert` with no
forward-fix obligation.

## Device/Relay Proof Profile

- Profile: `host-closure + conditional-device-preservation`;
  `DTR05-AUTH-01` records the helper-only two-peer waiver. A future live
  protocol change is outside this profile and requires its own paired-device
  scenario.
- Boundary being proven: no real relay behavior changes. The conditional
  `transport` run is a roadmap preservation gate, not causal proof of deleting
  an unreachable private symbol.
- Live availability check:
  `flutter devices --machine; adb devices; xcrun simctl list devices available`
  -> captured 2026-07-26: physical Pixel 6 Android `21071FDF600CSC` (API 36)
  and Android emulators `emulator-5554` / `emulator-5556` were available. The
  physical Android appeared as ADB-ready and Flutter-supported and was selected.
- Executed setup/result:
  `FLUTTER_DEVICE_ID=21071FDF600CSC ./scripts/run_test_gates.sh transport`
  exited 0; every host and physical-device transport suite passed.
- Two-peer default for any future scope expansion: one rediscovered USB
  physical Android plus one Android emulator with fully automated interaction
  and no user taps. It is not a DTR-05 helper-deletion closure leg under the
  approved waiver.
- Closure role: host tests are required closure evidence; the single-target
  transport gate is preservation evidence.
- `FLUTTER_DEVICE_ID`: sufficient only for the single-target transport gate.
- Registration: existing `transport` array in `scripts/run_test_gates.sh`; no
  new `classify_path`, dart-define, or orchestrator scenario.
- Discovery command/result: the live availability command above recorded the
  exact IDs and selected the physical Pixel 6.
- Closure command/result: the pinned transport command above exited 0 with zero
  failures. The policy-defined target-unavailable N/A branch was not used.
- Deferred device work: none for the approved helper-only scope.

## Gate Cadence

- Per-plan closure: TC-01/TC-02 exact tool gates; TC-03…TC-08 exact
  preservation sentinels; `1to1`; strict analysis; simulator discovery; the
  conditional `transport` preservation gate; and one justified
  `feature-host-all` sweep because the production edit is under
  `lib/features/**`.
- Do not run full `host-all` for this individual plan. Run
  `./scripts/run_host_test_gates.sh host-all` once when the DTR-03/DTR-04/DTR-05
  Wave 1 batch closes, and once again at final rollout/release closure.
- Shared tests outside feature/core globs:
  `test/unit/analyzer_suppression_ratchet_test.dart` and the four TC-08 Go
  selectors run by their exact direct commands.

## Acceptance Gates  (literal — copy/paste)

```bash
# Run sections 0-10 in one Bash session; Gate 0 defines variables/functions
# reused later. Apply and reverse each catalogued temporary mutation at its
# comment before running the following command.
set -eu
dtr05_expect_red() {
  local label="$1"
  local discriminator="$2"
  shift 2
  local output=''
  local status=0
  output="$("$@" 2>&1)" || status=$?
  printf '%s\n' "$output"
  if [ "$status" -eq 0 ]; then
    printf '%s unexpectedly passed\n' "$label" >&2
    exit 1
  fi
  local discriminator_status=0
  printf '%s\n' "$output" |
    rg -q -- "$discriminator" || discriminator_status=$?
  case "$discriminator_status" in
    0)
      printf '%s produced expected discriminator %s (exit %s)\n' \
        "$label" "$discriminator" "$status"
      ;;
    1)
      printf '%s failed for the wrong reason; missing discriminator %s\n' \
        "$label" "$discriminator" >&2
      exit 1
      ;;
    *)
      printf 'discriminator scan failed for %s (exit %s)\n' \
        "$label" "$discriminator_status" >&2
      exit "$discriminator_status"
      ;;
  esac
}

# --- 0. Preconditions + clean overlapping targets ---------------------------
git status --short
DTR05_OVERLAP_STATUS="$(git status --short -- \
  lib/features/conversation/application/send_chat_message_use_case.dart \
  tool/analyzer_guard/production_unused_suppressions.json \
  test/unit/analyzer_suppression_ratchet_test.dart \
  test/features/conversation/application/send_chat_message_use_case_test.dart \
  test/core/services/p2p_service_fault_injection_test.dart \
  Test-Flight-Improv/dead-code-and-technical-debt-removal-roadmap.md \
  Test-Flight-Improv/00-INDEX.md \
  Test-Flight-Improv/276-dormant-chat-relay-probe-helper-removal-tdd-plan.md \
  lib/features/introduction/application/introduction_outbound_delivery.dart \
  lib/features/conversation/application/delete_message_use_case.dart \
  lib/core/services/p2p_service.dart \
  lib/core/services/p2p_service_impl.dart \
  lib/core/bridge/p2p_bridge_client.dart \
  lib/core/bridge/go_bridge_client.dart \
  android/app/src/main/kotlin/com/mknoon/app/GoBridge.kt \
  ios/Runner/GoBridge.swift \
  macos/Runner/MainFlutterWindow.swift \
  go-mknoon/bridge/bridge.go \
  go-mknoon/node \
  go-mknoon/testdata/interop_vectors.json)"
if [ -n "$DTR05_OVERLAP_STATUS" ]; then
  printf 'dirty DTR-05 target/protected paths block execution:\n%s\n' \
    "$DTR05_OVERLAP_STATUS" >&2
  exit 1
fi
# expect: empty. Any overlapping dirt exits 1.

DTR05_ROADMAP=Test-Flight-Improv/dead-code-and-technical-debt-removal-roadmap.md
DTR05_LEDGER_ROW="$(
  rg '^\| Disposition the dormant chat relay-probe helper' "$DTR05_ROADMAP"
)" || {
  printf 'DTR-05 decision-ledger row missing\n' >&2
  exit 1
}
test "$(
  rg --count-matches --no-filename \
    '^\| Disposition the dormant chat relay-probe helper' "$DTR05_ROADMAP"
)" -eq 1 || {
  printf 'DTR-05 decision-ledger row is not unique\n' >&2
  exit 1
}
printf '%s\n' "$DTR05_LEDGER_ROW" |
  rg -q 'Approved' || {
    printf 'DTR-05 decision-ledger row is not Approved\n' >&2
    exit 1
  }
printf '%s\n' "$DTR05_LEDGER_ROW" |
  rg -q 'DTR05-AUTH-01' || {
    printf 'DTR-05 decision-ledger row lacks DTR05-AUTH-01\n' >&2
    exit 1
  }

DTR05_WAVE_FLOOR="$(
  awk '
    /^DTR-05 owns only/ {
      capture = 1
    }
    capture {
      print
    }
    capture && /^Exit:$/ {
      closed = 1
      exit
    }
    END {
      if (!closed) {
        exit 1
      }
    }
  ' "$DTR05_ROADMAP"
)" || {
  printf 'bounded Wave-1 DTR-05 proof floor missing\n' >&2
  exit 1
}
printf '%s\n' "$DTR05_WAVE_FLOOR" |
  rg -Fq 'DTR05-AUTH-01 leaf-only two-peer waiver' || {
    printf 'Wave-1 DTR-05 proof floor lacks the approved waiver marker\n' >&2
    exit 1
  }

DTR05_COMP_ROW="$(
  rg '^\| DTR08-COMP-003 \|' "$DTR05_ROADMAP"
)" || {
  printf 'DTR08-COMP-003 row missing\n' >&2
  exit 1
}
test "$(
  rg --count-matches --no-filename '^\| DTR08-COMP-003 \|' "$DTR05_ROADMAP"
)" -eq 1 || {
  printf 'DTR08-COMP-003 row is not unique\n' >&2
  exit 1
}
printf '%s\n' "$DTR05_COMP_ROW" |
  rg -Fq 'DTR05-AUTH-01 leaf-only two-peer waiver' || {
    printf 'DTR08-COMP-003 lacks the approved waiver marker\n' >&2
    exit 1
  }
printf '%s\n' "$DTR05_COMP_ROW" |
  rg -qi --pcre2 \
    '(live shared relay protocol|shared relay protocol|global relay protocol).*(retained|untouched)' || {
    printf 'DTR08-COMP-003 does not retain the live shared relay protocol\n' >&2
    exit 1
  }
# expect: three independently bounded checks pass. Repetition in one location
# cannot satisfy another; any missing/ambiguous/contradictory site exits 1.

DTR05_CHAT_SOURCE=lib/features/conversation/application/send_chat_message_use_case.dart
dtr05_expect_absent_in_file() {
  local pattern="$1"
  local file="$2"
  local label="$3"
  local status=0
  rg -n --pcre2 "$pattern" "$file" || status=$?
  case "$status" in
    1) return 0 ;;
    0)
      printf 'unexpected %s in %s\n' "$label" "$file" >&2
      return 1
      ;;
    *)
      printf 'rg failed while checking %s in %s (exit %s)\n' \
        "$label" "$file" "$status" >&2
      return "$status"
      ;;
  esac
}
DTR05_TOKEN_COUNT="$(
  rg --count-matches --no-filename '_tryRelayProbeSend' "$DTR05_CHAT_SOURCE"
)"
DTR05_DECL_COUNT="$(
  rg --count-matches --no-filename \
    '^[[:space:]]*Future<_RaceResult>[[:space:]]+_tryRelayProbeSend[[:space:]]*\(' \
    "$DTR05_CHAT_SOURCE"
)"
DTR05_COMMENT_COUNT="$(
  rg --count-matches --no-filename \
    '^[[:space:]]*//.*_tryRelayProbeSend' "$DTR05_CHAT_SOURCE"
)"
test "$DTR05_TOKEN_COUNT" -eq 3 || {
  printf 'expected 3 _tryRelayProbeSend tokens, found %s\n' \
    "$DTR05_TOKEN_COUNT" >&2
  exit 1
}
test "$DTR05_DECL_COUNT" -eq 1 || {
  printf 'expected 1 _tryRelayProbeSend declaration, found %s\n' \
    "$DTR05_DECL_COUNT" >&2
  exit 1
}
test "$DTR05_COMMENT_COUNT" -eq 2 || {
  printf 'expected 2 _tryRelayProbeSend comment tokens, found %s\n' \
    "$DTR05_COMMENT_COUNT" >&2
  exit 1
}
dtr05_expect_absent_in_file \
  "^[[:space:]]*(part[[:space:]]+['\"]|part[[:space:]]+of\\b)" \
  "$DTR05_CHAT_SOURCE" 'Dart part linkage'
dtr05_expect_absent_in_file \
  "@pragma\\(['\"]vm:entry-point['\"]\\)" \
  "$DTR05_CHAT_SOURCE" 'VM entrypoint pragma'
# expect: exact reviewed census. Three total tokens are exhausted by one
# declaration plus two comments, proving zero executable references/tear-offs
# in a standalone library file. Any upstream drift blocks the waiver premise.

git status --short -- \
  graphify-arch/graphify-out/graph.json \
  graphify-arch/graphify-out/manifest.json
git diff --stat -- \
  graphify-arch/graphify-out/graph.json \
  graphify-arch/graphify-out/manifest.json
git diff --cached --stat -- \
  graphify-arch/graphify-out/graph.json \
  graphify-arch/graphify-out/manifest.json
# record this generated-output baseline. Pre-existing dirt in these two exact
# files is expected and non-blocking; it grants no exception for another
# tracked/unignored path. graphify-arch/tdd-overlay.json is ignored scratch and
# is expected to rebuild.

dart tool/analyzer_guard/analyzer_suppression_ratchet.dart check
# expect: exit 0; 4 reviewed occurrences before edits.

# --- 1. RED (after E5, before E1/E2) — MUST FAIL ----------------------------
flutter test test/features/conversation/application/send_chat_message_use_case_test.dart \
  --plain-name 'relayProbeSendAttempts remains one for live introduction and delete consumers'
# expect: exit 0, one selected GREEN sentinel, zero failures.

dtr05_expect_red 'TC-01 first RED' 'DTR05-RED inventory-count-3' \
  flutter test test/unit/analyzer_suppression_ratchet_test.dart \
  --plain-name 'canonical inventory has three generated l10n identities and no dormant chat relay helper'
# expect: non-zero at the first 4-vs-3 count assertion, not compile failure.

# --- 2. Direct GREEN (after E1-E5) ------------------------------------------
flutter test test/unit/analyzer_suppression_ratchet_test.dart \
  --plain-name 'canonical inventory has three generated l10n identities and no dormant chat relay helper'
# expect: exit 0, one selected test, zero failures.
dtr05_expect_absent_in_file \
  '_tryRelayProbeSend' "$DTR05_CHAT_SOURCE" 'chat helper token'
dtr05_expect_absent_in_file \
  '\.probeRelay[[:space:]]*\(' "$DTR05_CHAT_SOURCE" 'chat probeRelay call'
dtr05_expect_absent_in_file \
  'CHAT_MSG_SEND_RELAY_PROBE_' "$DTR05_CHAT_SOURCE" 'dormant flow-event prefix'
dtr05_expect_absent_in_file \
  'post-probe|single retained attempt|probe establishes the circuit|relay tail (still runs|runs)|sequential relay-probe|trigger the live relay|relay probe runs|relay-probe-win' \
  "$DTR05_CHAT_SOURCE" 'stale serial-probe commentary'
# expect: all four absence checks return 0. rg exit >1 fails closed.
./scripts/check_flutter_analyze_strict.sh
# expect: exit 0; ratchet green and zero strict-analyzer issues.

# --- 3. Mutation re-red; apply/reverse each mutation with explicit patches --
# M-1: restore E1+E2.
dtr05_expect_red 'M-1 atomic restore' 'DTR05-RED inventory-count-3' \
  flutter test test/unit/analyzer_suppression_ratchet_test.dart \
  --plain-name 'canonical inventory has three generated l10n identities and no dormant chat relay helper'
# expect: non-zero at the first 4-vs-3 count assertion.

# M-2 from GREEN: restore E2 only (inventory present, source absent).
dtr05_expect_red 'M-2 inventory-only restore' 'stale-inventory-entry' \
  dart tool/analyzer_guard/analyzer_suppression_ratchet.dart check
# expect: non-zero with stale-inventory-entry.

# M-3 from GREEN: restore E1 only (source present, inventory absent).
dtr05_expect_red 'M-3 source-only restore' 'unexpected-suppression' \
  dart tool/analyzer_guard/analyzer_suppression_ratchet.dart check
# expect: non-zero with unexpected-suppression.

# M-4 from GREEN: restore only the helper body, with no suppression/inventory.
dtr05_expect_red 'M-4 unsuppressed helper restore' 'DTR05-M4 helper-absent' \
  flutter test test/unit/analyzer_suppression_ratchet_test.dart \
  --plain-name 'canonical inventory has three generated l10n identities and no dormant chat relay helper'
# expect: non-zero at the _tryRelayProbeSend source-absence assertion while
# ratchet counts remain 3/3.

# TC-03 recipe: restore helper + insert the exact RED-Catalog call block.
dtr05_expect_red 'TC-03 restored serial probe' \
  'DTR05-MUTATION serial-probe-count' \
  flutter test test/features/conversation/application/send_chat_message_use_case_test.dart \
  --plain-name 'FDC-03-03b race-fail whose concurrent copy ALSO fails reaches the former probe location WITHOUT running the probe (invariant #4 lock)'
# expect: non-zero with probeRelayCallCount actual 1 vs expected 0.

# TC-04 recipe: replace the custody `return` with the exact catalogued `await`.
dtr05_expect_red 'TC-04 custody fall-through' \
  'DTR05-MUTATION concurrent-custody-store-count' \
  flutter test test/core/services/p2p_service_fault_injection_test.dart \
  --plain-name 'discover-miss send to an online peer takes durable inbox custody without the relay probe, and drains to the recipient'
# expect: non-zero at the existing store/copy count after fall-through.
# Reverse every temporary patch before continuing.

# --- 4. Exact preservation sentinels; each exits 0 with one selected test ---
flutter test test/unit/analyzer_suppression_ratchet_test.dart \
  --plain-name 'rejects unexpected relocated duplicate and stale identities'
flutter test test/features/conversation/application/send_chat_message_use_case_test.dart \
  --plain-name 'FDC-03-03b race-fail whose concurrent copy ALSO fails reaches the former probe location WITHOUT running the probe (invariant #4 lock)'
flutter test test/core/services/p2p_service_fault_injection_test.dart \
  --plain-name 'discover-miss send to an online peer takes durable inbox custody without the relay probe, and drains to the recipient'
flutter test test/features/introduction/application/introduction_outbound_delivery_test.dart \
  --plain-name 'relay-probe fallback delivers after the direct path fails'
flutter test test/features/introduction/application/introduction_outbound_delivery_test.dart \
  --plain-name 'retryPendingIntroductionDeliveries delivers a failed row through relay probe when inbox storage fails'
flutter test test/features/conversation/application/send_chat_message_use_case_test.dart \
  --plain-name 'relayProbeSendAttempts remains one for live introduction and delete consumers'
flutter test test/features/conversation/application/delete_message_use_case_test.dart \
  --plain-name 'deleteMessageForEveryone keeps a sender-visible failed tombstone on send failure'
flutter test test/core/bridge/p2p_bridge_client_test.dart \
  --plain-name 'successful probe still works (no regression)'
flutter test test/core/bridge/p2p_bridge_client_test.dart \
  --plain-name 'bridge hang triggers TimeoutException after 5s'
flutter test test/core/bridge/go_bridge_client_test.dart \
  --plain-name 'relay:probe calls relayProbe with payload JSON'

# --- 5. Named curated gate --------------------------------------------------
./scripts/run_test_gates.sh 1to1
# expect: exit 0, zero failures.

# --- 6. Go preservation (DTR08-COMP-003 selectors) --------------------------
(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node -v -run '^TestForegroundRelayProbeIsNotRequiredForActiveSendPath$' -count=1)
(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node -v -run '^TestDialPeerViaRelayTriesAllAddresses$' -count=1)
(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node -v -run '^TestDialPeerViaRelay_TriesSecondRelayWhenFirstFails$' -count=1)
(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node -v -run '^TestDialPeerViaRelay_SingleRelayStillWorks$' -count=1)
# expect: each exits 0 and selects its one named test.
git status --short -- go-mknoon/testdata/interop_vectors.json
# expect: no output; any change is blocking scope drift and must not be overwritten.

# --- 7. Conditional device gate (only if a target is discoverable) ----------
DTR05_FLUTTER_DEVICES_JSON="$(flutter devices --machine)" || {
  printf 'flutter device discovery failed\n' >&2
  exit 1
}
printf '%s\n' "$DTR05_FLUTTER_DEVICES_JSON"
DTR05_ADB_OUTPUT="$(adb devices)" || {
  printf 'adb devices failed; transport availability is unknown\n' >&2
  exit 1
}
printf '%s\n' "$DTR05_ADB_OUTPUT"
if command -v xcrun >/dev/null 2>&1; then
  xcrun simctl list devices available || exit 1
fi
DTR05_ANDROID_ID="$(
  DTR05_FLUTTER_DEVICES_JSON="$DTR05_FLUTTER_DEVICES_JSON" \
  DTR05_ADB_OUTPUT="$DTR05_ADB_OUTPUT" \
  python3 - <<'PY'
import json
import os

flutter_devices = json.loads(os.environ["DTR05_FLUTTER_DEVICES_JSON"])
adb_ids = set()
for line in os.environ["DTR05_ADB_OUTPUT"].splitlines():
    fields = line.split()
    if len(fields) >= 2 and fields[1] == "device":
        adb_ids.add(fields[0])
candidates = [
    device
    for device in flutter_devices
    if device.get("isSupported") is True
    and str(device.get("targetPlatform", "")).startswith("android-")
    and device.get("id") in adb_ids
]
candidates.sort(key=lambda device: bool(device.get("emulator")))
print(candidates[0]["id"] if candidates else "")
PY
)" || {
  printf 'supported Android target selection failed\n' >&2
  exit 1
}
if [ -n "$DTR05_ANDROID_ID" ]; then
  printf 'Pinned transport target: %s\n' "$DTR05_ANDROID_ID"
  FLUTTER_DEVICE_ID="$DTR05_ANDROID_ID" ./scripts/run_test_gates.sh transport
else
  printf 'N/A (target unavailable by project policy): transport gate\n'
fi
# expect: choose only the intersection of ADB `device` IDs and Flutter-supported
# Android targets, physical before emulator; available branch exits 0/zero
# failures. Do not use an iOS target for this non-iOS-specific gate.

# --- 8. Simulator-harness discovery + final sweep ---------------------------
./scripts/check_reliability_simulation_discovery.sh
# expect: exit 0 and zero unclassified paths.
./scripts/run_host_test_gates.sh feature-host-all --batch-flutter --concurrency 4 --reporter failures-only
# expect: exit 0 and zero failures.

# --- 9. Graphify (an app-owned symbol was removed) --------------------------
./graphify-arch/refresh_arch_graph.sh --incremental
DTR05_GRAPH=graphify-arch/graphify-out/graph.json
dtr05_expect_absent_in_file \
  '"id": "lib_features_conversation_application_send_chat_message_use_case_tryrelayprobesend"' \
  "$DTR05_GRAPH" 'chat Graphify node'
rg -n \
  '"id": "lib_features_introduction_application_introduction_outbound_delivery_tryrelayprobesend"' \
  "$DTR05_GRAPH"
python3 graphify-arch/tdd_context.py query "_tryRelayProbeSend send_chat_message_use_case" --profile review --budget 800
# expect: exact chat node absent and exact introduction node present. Compact
# query output is navigation only and may rank only the same-named live twin.

# --- 10. Hygiene + scope ----------------------------------------------------
git diff --check
git diff --cached --check
git diff --unified=20 -- \
  lib/features/conversation/application/send_chat_message_use_case.dart
git diff --cached --unified=20 -- \
  lib/features/conversation/application/send_chat_message_use_case.dart
# inspect every hunk: executable changes are exactly E1; every other hunk is E3
# prose. `relayProbeSendAttempts = 1` and executable `relayProbeEligible` sites
# are unchanged.
git diff --exit-code -- \
  lib/features/introduction/application/introduction_outbound_delivery.dart \
  lib/features/conversation/application/delete_message_use_case.dart \
  lib/core/services/p2p_service.dart \
  lib/core/services/p2p_service_impl.dart \
  lib/core/bridge/p2p_bridge_client.dart \
  lib/core/bridge/go_bridge_client.dart \
  android/app/src/main/kotlin/com/mknoon/app/GoBridge.kt \
  ios/Runner/GoBridge.swift \
  macos/Runner/MainFlutterWindow.swift \
  go-mknoon/bridge/bridge.go \
  go-mknoon/node \
  go-mknoon/testdata/interop_vectors.json
git diff --cached --exit-code -- \
  lib/features/introduction/application/introduction_outbound_delivery.dart \
  lib/features/conversation/application/delete_message_use_case.dart \
  lib/core/services/p2p_service.dart \
  lib/core/services/p2p_service_impl.dart \
  lib/core/bridge/p2p_bridge_client.dart \
  lib/core/bridge/go_bridge_client.dart \
  android/app/src/main/kotlin/com/mknoon/app/GoBridge.kt \
  ios/Runner/GoBridge.swift \
  macos/Runner/MainFlutterWindow.swift \
  go-mknoon/bridge/bridge.go \
  go-mknoon/node \
  go-mknoon/testdata/interop_vectors.json
git diff --name-only
git diff --cached --name-only
git ls-files --others --exclude-standard
git diff --stat
git status --short
# expect: zero whitespace errors; protected files unchanged; newly changed paths
# limited to the eight base allowlist paths plus the exact snapshotted
# graphify-arch/graphify-out/{graph.json,manifest.json} generated outputs. The
# ignored graphify-arch/tdd-overlay.json may rebuild but must not become tracked.
```

> **Not run as a per-plan gate:** `host-all` (roadmap:61). It is the only scope
> that auto-registers `test/unit/**`; the exact per-plan command is above.

## Execution Interpretation And Done Criteria

- Observed REDs: TC-01 first failed with
  `DTR05-RED inventory-count-3`; M-1 through M-4 failed with their documented
  count/tool/source discriminators; TC-03 observed one probe call with
  `DTR05-MUTATION serial-probe-count`; and TC-04 observed two custody stores
  with `DTR05-MUTATION concurrent-custody-store-count`. No compile or unrelated
  failure was accepted as a causal RED.
- Observed GREEN: TC-01 through TC-08; `1to1` (2,441 tests plus its relay
  notification/Go tail); strict analysis (three reviewed suppressions, zero
  issues); all four exact Go selectors; discovery with zero unclassified paths;
  physical Pixel 6 transport; and `feature-host-all` (`+8550 ~1`, one skipped,
  all others passed across 821 paths).
- Scope result: the five implementation/test/tool paths, three closure docs,
  and two snapshotted Graphify outputs are the complete changed set. Protected
  protocol sources and the generated interop vector are unchanged.

- [x] `DTR05-AUTH-01` records the exact disposition, approves the helper-only
      two-peer waiver, and is reconciled in the decision ledger, Wave-1 waiver
      paragraph, and `DTR08-COMP-003`.
- [x] The pre-edit dormancy census proved exactly one declaration plus two
      comment tokens, no other executable reference/tear-off, no Dart part
      linkage, and no VM entrypoint.
- [x] The four-occurrence ratchet baseline was green before the first edit.
- [x] TC-01 emitted `DTR05-RED inventory-count-3` first, then passed with
      exactly three generated identities, zero handwritten identities, and
      helper/call/event absence.
- [x] M-1, M-2, M-3, and M-4 re-red with the documented, correctly directed
      results.
- [x] The corrected E4 recipes re-red: TC-03 observed
      `probeRelayCallCount == 1`, and TC-04 observed two stores, each with its
      stable DTR-05 discriminator.
- [x] TC-02 through TC-08, `1to1`, strict analysis, four exact Go selectors,
      discovery, and the 821-path `feature-host-all` sweep passed.
- [x] The pinned physical Pixel 6
      `FLUTTER_DEVICE_ID=21071FDF600CSC` transport gate exited 0; the
      target-unavailable N/A branch was not used.
- [x] Graphify was refreshed once incrementally; current fingerprint
      `a79b2f04386f2be9` has no chat helper node and exactly one live
      introduction helper node, with only the two expected tracked graph
      outputs changed.
- [x] Staged and unstaged whitespace checks pass; protected sources remain
      unchanged; the final path set matches the ten-path allowlist.
- [x] The DTR-02/DTR-05 registry rows, Wave-1 gate ledger,
      `DTR08-COMP-003`, and index Plans 273/276 reflect current state; Plan 275
      remains Plan-green. The dynamic Dart `relay:probe` selector and four exact
      Go commands are retained.
- [x] This plan's header, opening synopsis, device profile, Arbiter Decision,
      Handoff, and Execution Progress reconcile to
      `Plan-green` / `implementation-complete`.
- [x] Migration: N/A — no schema change.

## Reviewer Findings

The original `/tdd-review` established the sound core premise; a later
current-source sufficiency pass corrected mutation direction, selector
registration, command safety, and status lifecycle. The 2026-07-26 critical
`$tdd-review` then re-ran counterexamples against current source and this
revision applied only its source-backed contract deltas:

1. TC-01 now proves the helper/call/event surface itself is absent, not merely
   its suppression; M-4 closes the retained-unsuppressed-body counterexample.
2. E3 covers all eight false serial-probe/retention comment blocks and a
   fail-closed phrase scan, without changing the live constant or
   `relayProbeEligible` expressions.
3. TC-01/M-4/TC-03/TC-04 have stable test-owned RED reasons; the literal RED
   wrapper captures output and rejects compile/unrelated failures that lack the
   required discriminator. TC-03 and TC-04 also have executable temporary
   patches.
4. TC-08 labels the existing Go tests honestly as duration/selector smoke
   coverage; clean-baseline and no-diff guards, not error-string tests, prove
   the Go implementation stayed unchanged.
5. The protected boundary now includes the live Dart service/command map and
   Android, iOS, and macOS relay dispatch files; INV-5 distinguishes those
   byte-unchanged files from legitimate prose edits in the chat file.
6. The waiver premise now fails closed on a private-library source census, and
   execution requires the named decision-ledger authorization plus both
   categorical two-peer proof floors to be reconciled before E1; Gate 0 checks
   all three locations independently.
7. Device selection intersects ADB-ready IDs with Flutter-supported Android
   targets and prefers physical Android before emulator.
8. Rollback reverts E1-E8 in lockstep, including E5 and outcome metadata, while
   preserving the separately landed owner decision.
9. Graphify closure checks exact chat/introduction node IDs and acknowledges the
   expected ignored TDD overlay; the compact same-name query is not treated as
   deletion proof.

Execution then validated those review corrections: the causal first RED,
M-1 through M-4, and both behavioral mutation recipes re-red with their stable
discriminators; all direct preservation selectors, four Go selectors, `1to1`,
strict analysis, discovery, pinned Pixel transport, `feature-host-all`, and
Graphify closure passed.

## Arbiter Decision

Current disposition: `Plan-green / implementation-complete`.
`DTR05-AUTH-01` and both categorical proof-floor reconciliations remain
recorded. The helper-only atomic removal passed its causal RED/GREEN, all six
mutation re-reds, exact preservation tests, `1to1`, strict analysis, four Go
selectors, discovery, physical Pixel 6 transport preservation, the 821-path
`feature-host-all` sweep, Graphify, protected-scope, and diff gates. No DTR-05
blocker remains. The live protocol-retirement floor remains UNKNOWN and
retirement is not authorized. This per-plan verdict did not itself claim Wave 1
acceptance; the later full `host-all` acceptance is recorded below.

## Wave 1 Acceptance Addendum

Plan 276 remains `Plan-green`; its DTR-05 registry row was promoted separately
to `Wave-accepted` on 2026-07-26. The complete Wave 1 `host-all` retry passed at
concurrency 1: 1,265 exact Dart paths, 12,863 tests passed and 1 skipped, and
all eight Go tails passed. The non-green first attempt, test-only assertion
correction, accepted retry, original-log hashes, and stable archives are
recorded in the
[master roadmap](dead-code-and-technical-debt-removal-roadmap.md#wave-gate-ledger).
No production source changed between the two Wave 1 attempts.

## Handoff

- Plan: `Test-Flight-Improv/276-dormant-chat-relay-probe-helper-removal-tdd-plan.md`.
- Classification/status: `implementation-complete` / `Plan-green`.
- Test Contract: eight rows; Dart unit/application host plus direct Go host
  preservation; fake P2P/bridge fixtures; no SQLCipher or migration.
- Observed causal RED:
  `flutter test test/unit/analyzer_suppression_ratchet_test.dart --plain-name 'canonical inventory has three generated l10n identities and no dormant chat relay helper'`.
- Primary preservation passed:
  `flutter test test/features/conversation/application/send_chat_message_use_case_test.dart --plain-name 'FDC-03-03b race-fail whose concurrent copy ALSO fails reaches the former probe location WITHOUT running the probe (invariant #4 lock)'`.
- Manual registration: TC-01/TC-02 run directly per plan and auto-register in
  aggregate `host-all`; TC-08 uses four direct existing Go selectors. No new
  test registration is added.
- Boundary closure: host-causal closure plus the conditional single-target
  Android preservation gate under the recorded helper-only waiver.
- Remaining work: Wave 1 aggregate `host-all` is complete and accepted.
  Final-rollout `host-all` remains required at release closure; neither gate is
  a per-plan DTR-05 gate.

## Execution Progress

| Time | Phase | Files | Last command/result | Current evidence | Decision/blocker | Next |
|---|---|---|---|---|---|---|
| 2026-07-26 | prerequisite landing | Roadmap registry/proof floors/decision ledger/compatibility row; index; Plan 276; completed DTR-01 through DTR-04 tree | Commit `ec86247eb`; clean Gate 0 exited 0 | `DTR05-AUTH-01` recorded; exact census was 3 tokens = 1 declaration + 2 comments, with no part/VM entrypoint; four-occurrence ratchet baseline green | No decision blocker | Add E4/E5 tests and establish the causal RED |
| 2026-07-26 | causal implementation and mutation verification | Chat send source; suppression inventory; ratchet, chat-send, and P2P fault-injection tests | TC-01 emitted `DTR05-RED inventory-count-3` then GREEN; M-1 through M-4 re-red; TC-03 observed one probe; TC-04 observed two stores | Helper/suppression/handwritten identity removed atomically; all six mutation recipes discriminated the intended fault and were immediately reversed | No causal-evidence blocker | Run preservation, family, device, and graph closure |
| 2026-07-26 | preservation and closure | Eight Test Contract rows; `1to1`; analyzer; Go; discovery; Pixel transport; feature family; Graphify; protected scope | TC-02 through TC-08 GREEN; `1to1` 2,441; strict 3/0; Go 4/4; Pixel `21071FDF600CSC` transport exit 0; `feature-host-all` `+8550 ~1` across 821 paths; Graph fingerprint `a79b2f04386f2be9` | Exact chat node absent, introduction node present once; live shared protocol and protected files unchanged; final ten-path allowlist clean | `Plan-green`; no DTR-05 blocker | await the cadence-owned Wave 1 aggregate gate |
| 2026-07-26 | Wave 1 acceptance | DTR-03, DTR-04, DTR-05 integrated tree | accepted full `host-all`: Flutter `+12863 ~1`; Go 8/8 PASS; exit 0 | complete attempt history and stable log archives recorded in the master roadmap | DTR-05 promoted to `Wave-accepted`; no remaining wave blocker | final-rollout `host-all` remains a separate later gate |
