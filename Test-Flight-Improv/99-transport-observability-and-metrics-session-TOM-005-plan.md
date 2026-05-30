# TOM-005 - Cross-Seam Acceptance And Closure Update Plan

Status: accepted

## Planning Progress

- 2026-05-29 21:17:17 CEST - Evidence/planning/reviewer/arbiter completed locally under the batch fallback. Files inspected: all TOM-001 through TOM-004 plan verdicts, `Test-Flight-Improv/99-transport-observability-and-metrics.md`, `Test-Flight-Improv/test-gate-definitions.md`, and the focused code/test files touched by earlier sessions. Decision/blocker: no structural blocker; source-doc closure can be recorded without changing gate definitions because the newly added group evidence is in an existing direct application test file and the named group gate was not widened. Next action: record final source-doc closure and update the breakdown final verdict.

## real scope

Close the rollout doc with exact evidence from TOM-001 through TOM-004. Do not add product scope, new telemetry collectors, bridge protocol changes, routing changes, or dashboard decisions during acceptance.

## closure bar

TOM-005 is closed when:
- The source doc records the landed evidence, tests/gates, and accepted residuals.
- The closure wording does not claim physical LAN proof from the standard simulator setup.
- The closure wording does not claim group direct/relay/wifi census where the current group stack only proves fanout/custody evidence.
- The breakdown ledger marks all sessions accepted and records a final program verdict.
- Final hygiene passes with `git diff --check`.

## source of truth

- Active session contract: TOM-005 in `Test-Flight-Improv/99-transport-observability-and-metrics-session-breakdown.md`.
- Closure doc: `Test-Flight-Improv/99-transport-observability-and-metrics.md`.
- Gate definitions: `Test-Flight-Improv/test-gate-definitions.md`.
- Prior verdicts: TOM-001, TOM-002, TOM-003, and TOM-004 plan files.

## session classification

`acceptance-only`

This session records closure and final verification. It does not own new production behavior.

## exact problem statement

The earlier sessions closed separate seams, but the source doc still needed a single final verdict tying together Dart diagnostics privacy, settings readout, LAN snapshot wiring, relay metrics tests, and the group evidence boundary without overstating simulator LAN or group transport-family proof.

## files and repos to inspect next

- `Test-Flight-Improv/99-transport-observability-and-metrics.md`
- `Test-Flight-Improv/99-transport-observability-and-metrics-session-breakdown.md`
- `Test-Flight-Improv/99-transport-observability-and-metrics-session-TOM-001-plan.md`
- `Test-Flight-Improv/99-transport-observability-and-metrics-session-TOM-002-plan.md`
- `Test-Flight-Improv/99-transport-observability-and-metrics-session-TOM-003-plan.md`
- `Test-Flight-Improv/99-transport-observability-and-metrics-session-TOM-004-plan.md`
- `Test-Flight-Improv/test-gate-definitions.md`

## step-by-step implementation plan

1. Read the four prior execution verdicts and gate evidence.
2. Add a closure section to the source doc with final verdict, landed evidence, verification evidence, and accepted residuals.
3. Leave `Test-Flight-Improv/test-gate-definitions.md` unchanged unless a named gate list needs widening.
4. Update the session breakdown ledger and final program verdict.
5. Run `git diff --check`.

## exact tests and gates to run

Direct evidence already passed during TOM-001 through TOM-004:

```bash
flutter test test/features/conversation/application/send_chat_message_use_case_test.dart
flutter test test/features/settings/presentation/widgets/settings_transport_diagnostics_card_test.dart
flutter test test/core/debug/transport_metrics_privacy_test.dart
flutter test test/core/utils/flow_event_emitter_test.dart
./scripts/run_test_gates.sh 1to1
flutter test test/core/services/p2p_service_lan_availability_test.dart
flutter test test/core/debug/transport_metrics_test.dart
flutter test test/core/services/p2p_service_inbound_transport_test.dart
FLUTTER_DEVICE_ID=5BA69F1C-B112-47BE-B1FF-8C1003728C8F ./scripts/run_test_gates.sh transport
cd go-relay-server && go test ./...
flutter test test/features/groups/application/send_group_message_use_case_test.dart --plain-name "group send diagnostics expose fanout evidence without transport identity labels"
```

Final hygiene:

```bash
git diff --check
```

## accepted differences / intentionally out of scope

- No physical-device LAN success claim is made from standard simulator evidence.
- No group direct/relay/wifi transport-family metric is inferred from `transportPeerId`, `topicPeers`, or inbox custody fields.
- No named gate list was widened for the added focused group application test.
- No relay 1:1-vs-group classifier, analytics exporter, dashboard, telemetry policy, routing, NAT traversal, hole-punch, or relay protocol change is included.

## Execution Verdict

Verdict: accepted.

Landed TOM-005 evidence:
- Added `# 7. Rollout Closure - 2026-05-29` to `Test-Flight-Improv/99-transport-observability-and-metrics.md`.
- The source doc now records final verdict `closed`, landed evidence from TOM-001 through TOM-004, verification commands, and accepted residuals.
- `Test-Flight-Improv/test-gate-definitions.md` remained unchanged because no named gate list needed widening.
- Updated `Test-Flight-Improv/99-transport-observability-and-metrics-session-breakdown.md` to mark TOM-005 accepted and record final program verdict `closed`.

Tests/gates:
- `git diff --check` passed.

Residuals: none for TOM-005. Accepted out-of-scope items are recorded in the source doc.
