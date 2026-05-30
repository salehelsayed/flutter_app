Status: accepted

# DCUTR-002 Dart Bridge Diagnostics And Privacy-Safe User-Visible Counters Plan

## Planning Progress

- 2026-05-29 23:46 CEST - Arbiter completed. Files inspected since prior update: reviewer findings and patched plan sections. Decision: no structural blockers remain; plan is execution-ready for DCUTR-002 only. Next: downstream execution/QA may consume this file.
- 2026-05-29 23:45 CEST - Arbiter started. Files inspected since prior update: reviewer findings and patched plan sections. Decision: classify reviewer feedback into structural blockers, incremental details, and accepted differences. Next: finalize status if no structural blocker remains.
- 2026-05-29 23:44 CEST - Reviewer completed. Files inspected since prior update: plan draft only. Decision: sufficient with adjustments; no missing simulator reliability gate, no source-doc closure leak, and no checklist coverage omission. Incremental fixes: add conditional Settings screen wiring test and avoid formatting unrelated dirty files. Next: patch draft and run Arbiter pass.
- 2026-05-29 23:43 CEST - Reviewer started. Files inspected since prior update: plan draft only. Decision: review checklist parity, gate/device classification, privacy coverage, and scope guard. Next: record sufficiency findings.
- 2026-05-29 23:41 CEST - Planner completed. Files inspected since prior update: current evidence notes only. Decision: draft written with checklist coverage, host Flutter proof profile, conditional named gate triggers, and no final source-doc closure. Next: Reviewer pass.

## Execution Progress

- 2026-05-29 23:36 CEST - Executor started. Files inspected since prior update: this plan, session breakdown, `git status --short`, execution QA skill. Decision: contract extracted for DCUTR-002 only; required direct host Flutter tests, conditional named-gate triggers, done criteria, and scope guard are explicit. Next: inspect scoped dirty production/test files and verify/add regressions before any production patch.
- 2026-05-29 23:36 CEST - Scoped inspection completed. Files inspected since prior update: `lib/core/bridge/bridge.dart`, `lib/core/bridge/go_bridge_client.dart`, `lib/core/services/p2p_service_impl.dart`, `lib/core/debug/transport_metrics.dart`, `lib/features/settings/presentation/widgets/settings_transport_diagnostics_card.dart`, focused DCUTR-002 tests, `go-mknoon/bridge/events.go`, `go-mknoon/node/holepunch_tracer.go`. Decision: production seams appear present, but bridge-boundary, service-boundary, settings hole-punch display, and transport-event privacy regressions need to be added/verified first. Next: patch focused tests only.
- 2026-05-29 23:36 CEST - Regressions added. Files touched since prior update: `test/core/bridge/go_bridge_client_test.dart`, `test/core/services/p2p_service_inbound_transport_test.dart`, `test/core/debug/transport_metrics_privacy_test.dart`, `test/features/settings/presentation/widgets/settings_transport_diagnostics_card_test.dart`. Decision: no production files patched yet. Next: run required direct host Flutter tests and triage failures before any fix attempt.
- 2026-05-29 23:40 CEST - RED triage completed. Command finished: required direct host Flutter test command. Result: failed. Failure triaged before fix: new bridge privacy regression showed `conversationId` and message text surviving in transport diagnostic stream/GO flow details; targeted service metrics/inference regression passed. Next: patch bridge transport diagnostic payload filtering only.
- 2026-05-29 23:41 CEST - Production patch completed. Files touched since prior update: `lib/core/bridge/bridge.dart`, `lib/core/bridge/go_bridge_client.dart`, `lib/core/services/p2p_service_impl.dart`. Decision: transport diagnostic payloads are allowlisted to accepted DCUTR fields before stream/flow emission; no Go names, reachability, relay, NAT policy, or Settings wiring changed. Targeted bridge forwarding/privacy regressions passed. Formatting command initially changed touched Dart files, then `dart format --set-exit-if-changed` passed with 0 changes. Next: rerun required direct host Flutter tests.
- 2026-05-29 23:41 CEST - Required direct host Flutter tests completed. Command finished: `flutter test test/core/bridge/go_bridge_client_test.dart test/core/debug/transport_metrics_holepunch_test.dart test/core/debug/transport_metrics_privacy_test.dart test/core/debug/transport_metrics_test.dart test/core/services/p2p_service_inbound_transport_test.dart test/core/services/p2p_service_transport_census_test.dart test/features/settings/presentation/widgets/settings_transport_diagnostics_card_test.dart`. Result: passed. Decision: `transport` named gate is triggered because runtime bridge/P2P service code changed; `completeness-check` and Settings screen direct test are not triggered. Next: run `./scripts/run_test_gates.sh transport`.

## real scope

This session owns only Dart-side diagnostic consumption and privacy-safe user-visible aggregate counters for the DCUTR-001 Go event contract.

In scope:

- Consume the existing DCUTR-001 event names and payload shape for `holepunch:attempt`, `holepunch:success`, `holepunch:failure`, and `transport:upgraded`.
- Verify or complete `GoBridgeClient` forwarding of those events into the Dart transport diagnostic stream.
- Verify or complete `P2PServiceImpl` recording of exact aggregate hole-punch attempts, successes, failures, and relay-to-direct upgrades in `TransportMetrics`.
- Preserve the inbound receive fallback where missing transport remains `unknown` unless a true live connection inference exists.
- Ensure settings/debug diagnostics distinguish `direct`, `relay`, `wifi`, `inbox`, `unknown`, hole-punch attempt/success/failure counts, and relay-to-direct upgrade counts.
- Ensure user-visible diagnostics, external metrics surfaces, and flow/debug diagnostics do not expose message content, raw/full peer IDs, conversation IDs, or raw multiaddrs.

Out of scope:

- No Go event-name changes unless execution finds a blocking mismatch between DCUTR-001 accepted code and Dart consumption.
- No production reachability, routing, AutoNAT, WebRTC/TURN/STUN, relay-server, or hole-punch policy changes.
- No 1:1 delivery, group delivery, relay-only recovery, or physical NAT traversal proof.
- No final update to `Test-Flight-Improv/100-nat-traversal-dcutr-evidence.md`; DCUTR-004 owns final source-doc and decision-doc closure.

## closure bar

DCUTR-002 is good enough when the Dart client can prove, with host Flutter tests, that accepted Go hole-punch events are converted into aggregate metrics and visible diagnostics without fabricating transport labels or leaking sensitive identifiers.

Coverage ledger:

| Requirement | Planned proof |
|------|------|
| Consume `holepunch:attempt` | Add or verify a `GoBridgeClient.debugHandleEventForTest` bridge-boundary test that emits the accepted Go JSON event and observes one transport diagnostic event. Add or verify a `P2PServiceImpl` service-boundary test that only `step: attempt` increments `TransportMetrics.holePunchAttempts`; `started`/`direct_dial` breadcrumbs must not inflate attempts. |
| Consume `holepunch:success` | Same boundary path must increment `TransportMetrics.holePunchSuccesses` exactly once and record the upgraded peer short ID only for internal inference. |
| Consume `holepunch:failure` | Same boundary path must increment `TransportMetrics.holePunchFailures` exactly once and must not increment success or upgrade counters. |
| Consume `transport:upgraded` | Same boundary path must increment `TransportMetrics.relayToDirectUpgrades` exactly once and enable direct inference only for a matching upgraded peer. |
| Exact aggregate counts | `test/core/debug/transport_metrics_holepunch_test.dart` must keep exact forced counts and exact `baselineReport()` line, not `> 0` assertions. |
| Missing inbound transport stays `unknown` | `test/core/services/p2p_service_inbound_transport_test.dart` must keep the null-transport/no-live-peer case as `unknown`, with explicit relay/direct inference only when current connection evidence or an accepted upgrade signal exists. |
| Visible diagnostics distinguish all buckets | `test/features/settings/presentation/widgets/settings_transport_diagnostics_card_test.dart` must assert `direct`, `relay`, `wifi`, `inbox`, `unknown`, hole-punch count line, and relay-to-direct upgrade count are visible after refresh. |
| Privacy-safe diagnostics | `test/core/debug/transport_metrics_privacy_test.dart` plus a bridge transport-event privacy regression must assert no message content, raw/full peer ID, conversation ID, or raw multiaddr appears in external metrics/report surfaces or flow/debug event details. |
| No production mobile DCUtR overclaim | Plan, test names/comments, and final execution summary must classify this as host-side diagnostic proof only, not production NAT traversal success. |
| Dirty worktree preserved | Executor must inspect files before editing and only patch DCUTR-002-scoped files; unrelated dirty files remain untouched. |

## source of truth

- Active session contract: `Test-Flight-Improv/100-nat-traversal-dcutr-evidence-session-breakdown.md`, row `DCUTR-002`.
- Product/test intent: `Test-Flight-Improv/100-nat-traversal-dcutr-evidence.md`.
- Accepted upstream event contract: `Test-Flight-Improv/100-nat-traversal-dcutr-evidence-session-DCUTR-001-plan.md`, `go-mknoon/bridge/events.go`, `go-mknoon/node/holepunch_tracer.go`.
- Dart bridge and stream contract: `lib/core/bridge/bridge.dart`, `lib/core/bridge/go_bridge_client.dart`.
- Metrics and service behavior: `lib/core/debug/transport_metrics.dart`, `lib/core/services/p2p_service_impl.dart`.
- User-visible diagnostics: `lib/features/settings/presentation/widgets/settings_transport_diagnostics_card.dart`, `lib/features/settings/presentation/screens/settings_wired.dart`, and the `lib/main.dart` wiring that passes `TransportMetrics`.
- Gate execution source: `scripts/run_test_gates.sh`; if it disagrees with `Test-Flight-Improv/test-gate-definitions.md`, the script wins.

Current code and focused tests win over stale prose. DCUTR-001 event names/payload shape win for this session unless execution proves Dart cannot consume them safely without a documented blocker.

## session classification

`implementation-ready`

Reason: the inspected Dart code already has the likely production seams, and the remaining work can start with deterministic host Flutter tests. No physical device, simulator, multi-device reliability run, or real NAT environment is required to prove this session's diagnostic parsing and aggregate rendering contract.

Device/simulator profile:

- Primary closure profile: host-only Flutter unit/widget tests.
- No `$run-flutter-reliability-sims` gate is required because this session does not prove cross-device delivery, OS background state, notification opening, or real libp2p NAT traversal.
- `./scripts/run_test_gates.sh transport` is a conditional named gate only if implementation changes runtime bridge, P2P service, startup/resume/reconnect, app bootstrap, or integration-test-covered transport behavior. That gate is device/simulator-backed and still must not be reported as production DCUtR success.

## exact problem statement

The Go tracer can emit DCUtR diagnostic events, but release confidence depends on the Dart side proving that those events are counted exactly and surfaced truthfully. The risky failure modes are: dropped bridge events, inflated attempt counters from breadcrumb events, false relay/default labels for unknown inbound transport, a settings/debug surface that hides hole-punch outcomes, and privacy leaks through debug diagnostics.

The user-visible behavior that must improve is diagnostic trust: the app should show aggregate transport and hole-punch evidence clearly enough for TestFlight/debug review without exposing message content or identifiers. Delivery behavior must stay unchanged, relay remains a valid successful steady state, and this session must not claim production mobile DCUtR success.

## files and repos to inspect next

Production files:

- `lib/core/bridge/bridge.dart`
- `lib/core/bridge/go_bridge_client.dart`
- `lib/core/services/p2p_service_impl.dart`
- `lib/core/debug/transport_metrics.dart`
- `lib/features/settings/presentation/widgets/settings_transport_diagnostics_card.dart`
- `lib/features/settings/presentation/screens/settings_wired.dart`
- `lib/main.dart` only if dependency injection or settings wiring appears inconsistent
- `go-mknoon/bridge/events.go` read-only for event contract verification
- `go-mknoon/node/holepunch_tracer.go` read-only for payload shape verification

Test/gate files:

- `test/core/bridge/go_bridge_client_test.dart`
- `test/core/debug/transport_metrics_holepunch_test.dart`
- `test/core/debug/transport_metrics_privacy_test.dart`
- `test/core/debug/transport_metrics_test.dart`
- `test/core/services/p2p_service_inbound_transport_test.dart`
- `test/core/services/p2p_service_transport_census_test.dart`
- `test/features/settings/presentation/widgets/settings_transport_diagnostics_card_test.dart`
- `test/features/settings/presentation/screens/settings_wired_test.dart` only if `settings_wired.dart` or Settings injection changes
- `Test-Flight-Improv/test-gate-definitions.md` only if a new test file needs explicit classification
- `scripts/run_test_gates.sh` only if gate classification must change

## existing tests covering this area

- `test/core/debug/transport_metrics_holepunch_test.dart` covers exact `TransportMetrics` hole-punch counters and exact baseline report line once counters are directly recorded.
- `test/core/debug/transport_metrics_privacy_test.dart` covers aggregate metrics/report privacy and receive-arm flow event privacy, but it does not yet clearly prove privacy for the Go hole-punch bridge events.
- `test/core/debug/transport_metrics_test.dart` covers canonical transport buckets, unknown canonicalization, reports, LAN snapshot, latency, rung, and reset behavior.
- `test/core/services/p2p_service_inbound_transport_test.dart` covers `unknown` for null inbound transport with no live peer, explicit relay, true circuit relay inference, true direct inference, and local WiFi census.
- `test/core/services/p2p_service_transport_census_test.dart` covers exact send-arm census for direct, relay, inbox, failed sends, and rung counts.
- `test/features/settings/presentation/widgets/settings_transport_diagnostics_card_test.dart` covers the settings diagnostics card refresh, transport mix, fallback rungs, latency, LAN rows, and baseline report, but current inspected assertions do not explicitly drive hole-punch counters into the rendered/report surface.
- `test/core/bridge/go_bridge_client_test.dart` covers many push-event routing cases via `debugHandleEventForTest`, but inspected searches did not show a direct transport-diagnostic bridge-boundary assertion for `holepunch:*` and `transport:upgraded`.

Current likely gaps to verify first:

- Missing bridge-boundary proof that accepted Go hole-punch JSON events reach `transportDiagnosticEventStream`.
- Missing service-boundary proof that those bridge events update `TransportMetrics` through the real `P2PServiceImpl` subscription.
- Missing explicit settings widget assertion that hole-punch and relay-to-direct upgrade counts are visible.
- Missing privacy assertion for transport diagnostic flow/debug events carrying hole-punch payloads.

## regression/tests to add first

Add or verify regressions before production edits:

1. In `test/core/bridge/go_bridge_client_test.dart`, add a focused push-event routing test:
   - Use `client.debugHandleEventForTest(jsonEncode(...))` for `holepunch:attempt`, `holepunch:success`, `holepunch:failure`, and `transport:upgraded`.
   - Observe `transportDiagnosticEventStream` events with exact event names and accepted payload fields.
   - Assert malformed payloads still follow existing malformed-event handling rather than reaching the stream.
   - Include a privacy subcase or companion test that injects a fabricated full `remotePeer`, `conversationId`, `multiaddr`, and message-like `text`; captured flow/debug details and transport diagnostic stream data must redact or omit those values.

2. In `test/core/services/p2p_service_inbound_transport_test.dart` or a narrow adjacent service test, add a `P2PServiceImpl` transport diagnostic subscription proof:
   - Construct `P2PServiceImpl` with `TransportMetrics`.
   - Emit transport diagnostic events through the existing bridge helper stream.
   - Assert exact counts: one real `holepunch:attempt` with `step: attempt`, one success, one failure, one upgrade.
   - Assert `holepunch:attempt` with `step: started` or `step: direct_dial` does not increment attempts.
   - Assert a later inbound null-transport message from a peer whose short ID matches `transport:upgraded.remotePeerShort` can infer `direct`, while a peer with no match and no live connection remains `unknown`.

3. In `test/features/settings/presentation/widgets/settings_transport_diagnostics_card_test.dart`, extend the refresh test:
   - Drive direct, relay, wifi, inbox, and unknown counts exactly as today.
   - Also call `recordHolePunchAttempt`, `recordHolePunchSuccess`, `recordHolePunchFailure`, and `recordRelayToDirectUpgrade`.
   - Assert the rendered/copyable diagnostics include the exact hole-punch line: `Hole punch (attempt/success/fail): A/S/F, relay->direct upgrades: U`.
   - Assert no raw peer ID, conversation ID, multiaddr, or message text appears in the `SelectableText` report.

If execution discovers equivalent regressions already exist, do not duplicate them; cite them and proceed to implementation verification.

## step-by-step implementation plan

1. Re-read the scoped dirty files before editing; treat all pre-existing changes as user/workstream-owned.
2. Verify the accepted DCUTR-001 Go event contract in `go-mknoon/bridge/events.go` and `go-mknoon/node/holepunch_tracer.go`; do not change Go event names or payload shape in this session.
3. Add or verify the bridge-boundary test in `test/core/bridge/go_bridge_client_test.dart`.
4. Add or verify the service-boundary metrics/inference test around `P2PServiceImpl` and `TransportMetrics`.
5. Add or verify the settings diagnostics widget/report test for hole-punch and relay-to-direct upgrade counts.
6. Run the direct host Flutter tests. If they all pass without production edits, stop implementation and record the session as already covered by added/verified tests.
7. If bridge-boundary tests fail, patch only `lib/core/bridge/bridge.dart` or `lib/core/bridge/go_bridge_client.dart` so accepted Go events reach the sanitized transport diagnostic stream.
8. If service metrics tests fail, patch only `lib/core/services/p2p_service_impl.dart` and/or `lib/core/debug/transport_metrics.dart` to keep exact aggregate counts and direct inference from true upgrade evidence.
9. If settings diagnostics tests fail, patch only `lib/features/settings/presentation/widgets/settings_transport_diagnostics_card.dart` or the minimum settings wiring needed to show aggregate counters. Prefer using existing `TransportMetrics` getters/baseline report rather than adding identifier-bearing state.
10. If privacy tests fail, patch the smallest sanitizer or diagnostics-surface code path needed to remove raw/full peer IDs, conversation IDs, raw multiaddrs, and message content from debug/user-visible output while preserving aggregate counts.
11. Update `Test-Flight-Improv/test-gate-definitions.md` and/or `scripts/run_test_gates.sh` only if a new test file is introduced in a path not already classified. Prefer extending existing test files to avoid expanding gate inventory.
12. Do not update the source doc, baseline decision docs, or final NAT/DCUtR closure docs; leave that to DCUTR-004.

## risks and edge cases

- The global `transportDiagnosticEventStream` is broadcast and sync; tests must avoid leaking events between cases by awaiting only events emitted inside the test and disposing service subscriptions.
- `holepunch:attempt` has multiple steps; only `step: attempt` should count as an attempt, while `started` and `direct_dial` are breadcrumbs.
- `remotePeerShort` is intentionally not a raw peer ID, but it should not appear in user-visible settings text. It may remain an internal inference key only if privacy tests prove raw/full identifiers are not exposed.
- A stale live connection map can still contain relay multiaddrs after an upgrade; direct inference from `_peersUpgradedToDirect` must be limited to a matching accepted upgrade signal, not a generic fallback.
- Sanitizer changes can break useful non-identifying flow diagnostics if too broad; tests should assert specific privacy constraints, not strip every numeric/string field.
- Settings/widget edits should not introduce layout-heavy UI scope or redesign the Settings page.
- Running `./scripts/run_test_gates.sh transport` may require `FLUTTER_DEVICE_ID`; absence of a simulator/device is an environment skip for the named gate, not proof of production DCUtR failure.

## exact tests and gates to run

Direct host Flutter tests required for closure:

```bash
flutter test \
  test/core/bridge/go_bridge_client_test.dart \
  test/core/debug/transport_metrics_holepunch_test.dart \
  test/core/debug/transport_metrics_privacy_test.dart \
  test/core/debug/transport_metrics_test.dart \
  test/core/services/p2p_service_inbound_transport_test.dart \
  test/core/services/p2p_service_transport_census_test.dart \
  test/features/settings/presentation/widgets/settings_transport_diagnostics_card_test.dart
```

Formatting/checks:

```bash
dart format --set-exit-if-changed <DCUTR-002 files edited by the executor>
```

```bash
git diff --check
```

Named gates:

```bash
./scripts/run_test_gates.sh transport
```

Run this Startup / Transport Gate if implementation changes runtime bridge, P2P service, startup/resume/reconnect, app bootstrap, or integration-test-covered transport behavior. If the environment requires an explicit simulator/device, use:

```bash
FLUTTER_DEVICE_ID=<device-id> ./scripts/run_test_gates.sh transport
```

```bash
./scripts/run_test_gates.sh completeness-check
```

Run this only if a new test file is introduced, gate docs/scripts are changed, or execution changes test classification. If it fails on pre-existing unmatched files outside DCUTR-002, record those exact files as pre-existing known failures and do not treat them as new regressions.

No `$run-flutter-reliability-sims` command is required for this session.

Conditional direct Flutter test:

```bash
flutter test test/features/settings/presentation/screens/settings_wired_test.dart
```

Run this only if implementation changes `lib/features/settings/presentation/screens/settings_wired.dart` or the Settings injection path in `lib/main.dart`.

## known-failure interpretation

- A failure in one of the direct host Flutter tests listed above is in scope unless clearly caused by unrelated dirty worktree changes outside the scoped files.
- A `transport` named-gate skip or failure caused solely by missing `FLUTTER_DEVICE_ID`, simulator unavailability, or app-launch infrastructure should be reported as environment-gated. It must not be converted into a production DCUtR success or failure claim.
- If `completeness-check` is run and reports pre-existing unmatched files, record the exact output. Only new DCUTR-002 test-file classification gaps must be fixed in this session.
- Existing dirty files not touched by DCUTR-002 are not to be reverted or "fixed" while chasing green gates.

## done criteria

- `Status` is updated by execution/closure tooling after implementation; this plan itself remains scoped to DCUTR-002.
- Bridge-boundary tests prove all four accepted Go event names reach Dart transport diagnostics.
- Service-boundary tests prove exact `TransportMetrics` counts for attempts, successes, failures, and relay-to-direct upgrades.
- Tests prove `step: started` and `step: direct_dial` do not inflate attempt counts.
- Inbound null transport remains `unknown` unless true connection inference or matching accepted upgrade evidence exists.
- Settings/debug diagnostics visibly distinguish direct, relay, wifi, inbox, unknown, hole-punch counts, and relay-to-direct upgrade counts.
- Privacy tests prove no message content, raw/full peer IDs, conversation IDs, or raw multiaddrs appear in user-visible diagnostics or flow/debug transport diagnostics.
- Required direct host Flutter tests pass, or any failure is documented with exact in-scope/out-of-scope classification.
- Conditional named gates are run when their trigger applies, or their environment limitation is recorded explicitly.
- No Go event names/payload shape, production reachability policy, routing policy, relay architecture, WebRTC/TURN/STUN behavior, or final source-doc closure is changed.

## scope guard

Do not broaden this session into NAT traversal implementation, relay-only acceptance, 1:1 delivery semantics, group transport classification, device harvest, or final evidence closure. Do not add per-peer, per-conversation, per-message, address, or raw identifier storage to `TransportMetrics`. Do not make settings diagnostics a user-facing product feature beyond the existing debug aggregate card. Do not change DCUTR-001 Go event names unless execution finds a documented Dart blocker and the blocker is recorded before any Go-adjacent patch.

Overengineering includes adding persistence for metrics, new analytics export, a new settings page, NAT simulation fixtures, a new relay probe policy, or broad app navigation changes.

## accepted differences / intentionally out of scope

- Host Flutter tests prove Dart diagnostic parsing, counting, inference, and display; they do not prove production mobile DCUtR success.
- A `direct` message count is not the same as a relay-to-direct DCUtR upgrade unless a `transport:upgraded` event was observed.
- A LAN/WiFi direct delivery remains distinct from DCUtR upgrade evidence.
- Relay delivery remains a successful and expected steady state for unpunchable peers.
- `remotePeerShort` may be used only as an internal short correlation key for true upgrade inference; raw/full peer IDs must not be stored or shown.
- DCUTR-003 owns relay-only/no-upgrade acceptance, and DCUTR-004 owns final source-doc, baseline, and decision-doc closure.

## dependency impact

- DCUTR-003 can rely on these aggregate counters and settings diagnostics when proving relay-only behavior does not manufacture upgrade evidence.
- DCUTR-004 can cite this session only as Dart diagnostics/counter evidence, not as production NAT traversal proof.
- If this plan changes to require Go event-name changes, DCUTR-003 and DCUTR-004 must refresh against the new event contract before execution.
- If device/simulator transport gates become required and cannot run, downstream closure should treat DCUTR-002 as evidence-limited for runtime integration, while host diagnostic unit/widget proof may still be valid.

## reviewer findings

Verdict: sufficient with adjustments.

- No structural blocker: the plan maps every DCUTR-002 checklist item to a concrete proof or accepted difference.
- No missing reliability simulator gate: the session proves host-side diagnostic parsing, counters, inference, and rendering, not a multi-device transport journey.
- Required adjustment applied: include `settings_wired_test.dart` as a conditional direct test if Settings screen wiring changes.
- Required adjustment applied: format only files edited by the executor, so unrelated dirty files do not become formatting blockers.
- Incremental detail: a future gate cleanup may classify `test/core/debug/` explicitly if new files are introduced there; this plan avoids requiring that unless execution adds a new test file or changes gate docs.

## arbiter decision

Classification: execution-ready for DCUTR-002.

Structural blockers: none.

Incremental details intentionally deferred:

- Do not proactively classify `test/core/debug/` unless execution creates a new test file there, changes gate docs/scripts, or `completeness-check` is triggered for another reason.
- Do not run the simulator/device Startup / Transport Gate unless production runtime bridge/P2P/startup transport code changes trigger it.

Accepted differences intentionally left unchanged:

- Host Flutter tests are sufficient for this diagnostic/counter session; they are not production mobile DCUtR proof.
- `remotePeerShort` may remain an internal short correlation signal for matching accepted upgrade events, but raw/full peer IDs must not be stored or shown.
- Final source-doc, baseline, and architecture-decision closure remain owned by DCUTR-004.

Why safe to implement now:

- The plan is narrow, starts with regressions, names exact direct tests and conditional named gates, preserves DCUTR-001 Go event names, preserves the dirty worktree, and includes an explicit privacy and no-overclaim closure bar.

## final execution verdict

Verdict: accepted

Recorded: 2026-05-29 23:52 CEST

Execution note:

- The spawned execution/QA child produced the scoped implementation and direct-test progress but stalled before returning a final verdict while running the triggered named gate. The controller closed that child and completed bounded local verification from the persisted repo state.

Files changed for DCUTR-002:

- `lib/core/bridge/bridge.dart`
- `lib/core/bridge/go_bridge_client.dart`
- `lib/core/services/p2p_service_impl.dart`
- `test/core/bridge/go_bridge_client_test.dart`
- `test/core/debug/transport_metrics_privacy_test.dart`
- `test/core/services/p2p_service_inbound_transport_test.dart`
- `test/features/settings/presentation/widgets/settings_transport_diagnostics_card_test.dart`
- `Test-Flight-Improv/100-nat-traversal-dcutr-evidence-session-DCUTR-002-plan.md`

Execution summary:

- Added a sanitized transport diagnostic stream for accepted DCUTR events and forwarded `holepunch:attempt`, `holepunch:success`, `holepunch:failure`, and `transport:upgraded` through `GoBridgeClient` without changing Go event names.
- Wired `P2PServiceImpl` to update aggregate `TransportMetrics` hole-punch counters and to infer `direct` only for matching accepted relay-to-direct upgrade evidence or true live connection inference.
- Preserved null inbound transport as `unknown` when no accepted upgrade or live connection evidence exists.
- Extended bridge, service, settings diagnostics, and privacy tests so the user-visible diagnostics show exact aggregate counts without full peer IDs, conversation IDs, raw multiaddrs, or message content.
- No Go, production reachability, relay-server, routing, NAT policy, WebRTC/TURN/STUN, or final source-doc closure changes were made.

Tests and gates:

- `dart format --set-exit-if-changed lib/core/bridge/bridge.dart lib/core/bridge/go_bridge_client.dart lib/core/services/p2p_service_impl.dart test/core/bridge/go_bridge_client_test.dart test/core/debug/transport_metrics_privacy_test.dart test/core/services/p2p_service_inbound_transport_test.dart test/features/settings/presentation/widgets/settings_transport_diagnostics_card_test.dart` -> PASS, 0 files changed.
- `flutter test test/core/bridge/go_bridge_client_test.dart test/core/debug/transport_metrics_holepunch_test.dart test/core/debug/transport_metrics_privacy_test.dart test/core/debug/transport_metrics_test.dart test/core/services/p2p_service_inbound_transport_test.dart test/core/services/p2p_service_transport_census_test.dart test/features/settings/presentation/widgets/settings_transport_diagnostics_card_test.dart` -> PASS.
- `git diff --check` -> PASS.
- `./scripts/run_test_gates.sh transport` -> first attempt blocked before tests because multiple devices were connected and no device was selected.
- `FLUTTER_DEVICE_ID=347FB118-10D0-40C8-A05B-B0C3BD6B8CCD ./scripts/run_test_gates.sh transport` -> PASS. The gate ran on the specified iOS simulator; background reconnect was skipped by its test conditions, WiFi relay fallback smoke passed self-contained paths, transport E2E passed self-contained paths, and media stable-ID smoke passed.
- `./scripts/run_test_gates.sh completeness-check` was not triggered because no new test file or gate classification was introduced.
- `flutter test test/features/settings/presentation/screens/settings_wired_test.dart` was not triggered because this session did not change Settings screen wiring.

Residuals:

- This is host Flutter and simulator gate evidence for Dart diagnostics/counters. It does not prove production mobile DCUtR success.
- DCUTR-003 still owns relay-only/no-upgrade acceptance, and DCUTR-004 owns final source-doc, baseline, and decision-doc closure.

## closure audit verdict

Recorded: 2026-05-29 23:53 CEST

Closure verdict: accepted for DCUTR-002 only.

Completion auditor classification:

- `closed`: Dart-side consumption of the accepted DCUTR-001 event names and payload fields; sanitized `transportDiagnosticEventStream` forwarding; exact aggregate `TransportMetrics` hole-punch and relay-to-direct counters; `unknown` inbound transport preservation unless a true live connection or matching accepted upgrade signal exists; settings/debug aggregate diagnostics without raw/full peer IDs, conversation IDs, raw multiaddrs, or message content.
- `accepted_with_explicit_follow_up`: final source-doc, baseline, and architecture-decision closure remain assigned to DCUTR-004.
- `residual_only`: recorded evidence is host Flutter and simulator transport-gate diagnostics/counter evidence only; it is not production mobile DCUtR success, real NAT traversal proof, routing-policy proof, or relay-only/no-upgrade acceptance.
- `still_open`: none for the DCUTR-002 session scope.
- `stale_doc`: top-level plan status was refreshed from `execution-ready` to `accepted`.

Evidence verified by this closure audit without re-running implementation, tests, or gates:

- Final execution verdict above is `accepted`.
- Scoped code artifacts inspected: `lib/core/bridge/bridge.dart`, `lib/core/bridge/go_bridge_client.dart`, `lib/core/services/p2p_service_impl.dart`, `lib/core/debug/transport_metrics.dart`, and `lib/features/settings/presentation/widgets/settings_transport_diagnostics_card.dart`.
- Scoped test artifacts inspected: `test/core/bridge/go_bridge_client_test.dart`, `test/core/debug/transport_metrics_holepunch_test.dart`, `test/core/debug/transport_metrics_privacy_test.dart`, `test/core/debug/transport_metrics_test.dart`, `test/core/services/p2p_service_inbound_transport_test.dart`, `test/core/services/p2p_service_transport_census_test.dart`, and `test/features/settings/presentation/widgets/settings_transport_diagnostics_card_test.dart`.
- Accepted recorded verification: required direct host Flutter test command passed, `dart format --set-exit-if-changed` passed with 0 files changed, `git diff --check` passed, and the triggered `FLUTTER_DEVICE_ID=347FB118-10D0-40C8-A05B-B0C3BD6B8CCD ./scripts/run_test_gates.sh transport` gate passed after the no-device-selection attempt was classified as environment-blocked before tests.
- Accepted non-triggers: `./scripts/run_test_gates.sh completeness-check` was not required because no new test file or gate classification was introduced; `flutter test test/features/settings/presentation/screens/settings_wired_test.dart` was not required because Settings screen wiring was not changed.

Closure reviewer note: no Go event names, production reachability, relay-server behavior, routing policy, NAT policy, WebRTC/TURN/STUN behavior, final source-doc wording, baseline decision docs, or architecture-decision docs are closed by this session.

## Execution Progress

- 2026-05-29 23:35 CEST - Contract extracted. Phase: controller setup. Files inspected: this plan, session breakdown row `DCUTR-002`, `Test-Flight-Improv/test-gate-definitions.md`, `scripts/run_test_gates.sh`, and `git status --short`. Decision: execute DCUTR-002 only; required direct host Flutter tests are the seven-test command in this plan; conditional `transport` gate runs only if runtime bridge/P2P/startup/settings wiring changes; conditional `completeness-check` runs only if new test files or gate classification changes are introduced; conditional `settings_wired_test.dart` runs only if Settings screen wiring changes. Scope guard: preserve dirty worktree, no Go event-name or production reachability/policy/relay changes, no final source-doc closure, no production mobile DCUtR success claim. Next: spawn fresh Executor with model `gpt-5.5` and reasoning effort `xhigh`.
