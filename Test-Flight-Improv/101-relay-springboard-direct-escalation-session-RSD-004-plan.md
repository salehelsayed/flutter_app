# RSD-004 - Acceptance, Baseline Classification, And Stable Doc Closure

Status: accepted

## Planning Progress

- 2026-05-30 09:33:00 CEST - Local pipeline fallback - Closure-only plan created from the reusable breakdown after the spawned pipeline produced RSD-001 progress but did not persist a final program verdict. Files inspected: `Test-Flight-Improv/101-relay-springboard-direct-escalation-session-breakdown.md`, `Test-Flight-Improv/101-relay-springboard-direct-escalation-session-RSD-001-plan.md`, `Test-Flight-Improv/101-relay-springboard-direct-escalation.md`, `Network-Arch/Transport-Reliability/03-relay-springboard.md`, `Network-Arch/Transport-Reliability/00-INDEX.md`, and `Test-Flight-Improv/NET-REL-04-baseline-decision-gate.md`. Decision/blocker: RSD-001 accepted a no-proceed decision; RSD-002/RSD-003 are dependency-skipped for this rollout. Next action: persist final program verdict in the breakdown.

## real scope

RSD-004 closes doc 101 based on the actual RSD-001 outcome. No relay springboard policy, direct escalation, send migration, routing, reachability, WebRTC/TURN/STUN, AutoRelay, relay-server protocol, bridge payload, UI, or test changes are in scope.

## closure bar

The closure is accepted when the source doc, NET-REL tracking docs, baseline decision gate, and breakdown all state the same evidence-gated result:

- no valid repo-local real-device, discovery-enabled, debug-mode 1:1 baseline harvest artifact exists,
- NET-REL-03 relay springboard implementation has no proceed verdict,
- RSD-002/RSD-003 must not run until a valid harvest provides a proceed boundary,
- relay delivery, LAN/direct-address delivery, loopback feasibility, stream-label mapping, and real relay-to-direct upgrade remain distinct evidence types.

## Completion Audit

- RSD-001 result: accepted.
- Stable docs updated by RSD-001: `Test-Flight-Improv/101-relay-springboard-direct-escalation.md`, `Network-Arch/Transport-Reliability/03-relay-springboard.md`, `Test-Flight-Improv/NET-REL-04-baseline-decision-gate.md`, and `Network-Arch/Transport-Reliability/00-INDEX.md`.
- Production code/test changes for doc 101: none.
- RSD-002 status: skipped_due_to_dependency because RSD-001 did not provide a proceed verdict or policy boundary.
- RSD-003 status: skipped_due_to_dependency because RSD-001 did not proceed and RSD-002 did not execute.
- Residual: capture a valid NET-REL-04 baseline harvest before reopening implementation.

## Closure Writer

The stable closure references already record the no-proceed decision and residual. This plan and the session breakdown now carry the durable pipeline result so future runs do not treat RSD-002/RSD-003 as runnable without new baseline evidence.

## Closure Reviewer

Review verdict: accepted. The closure does not overclaim production mobile relay-to-direct success, does not treat simulator/CLI/loopback/LAN/direct-label evidence as physical NAT traversal proof, and does not authorize implementation work before the baseline decision gate is filled.

## tests and gates

- `flutter devices --machine` - run during RSD-001.
- `xcrun simctl list devices available` - run during RSD-001 as supporting inventory only.
- targeted `rg` evidence searches - run during RSD-001.
- `git diff --check` - passed during RSD-001 and passed again after final verdict edits.

No Flutter named gate, Go test, or integration test is required because this closure is docs/evidence-only and does not edit production code, tests, or `Test-Flight-Improv/test-gate-definitions.md`.

## Final Closure Verdict

Closure verdict: residual_only.

What is now closed: doc 101 has a durable no-proceed decision for NET-REL-03 implementation under current evidence, and the stable docs prevent RSD-002/RSD-003 from running until the NET-REL-04 baseline harvest exists.

Residual-only item: capture a valid real-device, discovery-enabled, debug-mode 1:1 baseline harvest with transport counts, hole-punch attempt/success/failure counts, relay-to-direct upgrade count, and cross-network/co-location metadata.

Still-open items: none inside the current doc 101 rollout without new baseline evidence. Implementation work should reopen only after the residual harvest changes the decision gate.

Accepted differences: relay remains a correct steady state for unpunchable peers; LAN/direct-label/loopback evidence remains insufficient for production mobile relay-to-direct proof; production reachability and relay architecture remain unchanged.
