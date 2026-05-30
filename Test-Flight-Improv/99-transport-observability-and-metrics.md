# 1. Title and Type

- Title: Trustworthy Transport Diagnostics for TestFlight Reliability
- Issue type: feature-improvement
- Output doc path: `Test-Flight-Improv/99-transport-observability-and-metrics.md`

# 2. Problem Statement

TestFlight users and maintainers need to understand which delivery paths messages
actually use - direct, relay, WiFi, inbox, or unknown - and whether those paths
are fast enough, without exposing message content or user identifiers.

The repo now has partial session-scoped diagnostics, but the observable contract
is still not complete across all relevant transport flows. Local session counters,
latency summaries, and a settings diagnostics card exist, but LAN availability is
not updated by production code, relay metrics are not pinned by a dedicated
contract test, send-path flow events still include message-derived preview text,
and the client-side census is not clearly evidenced across every transport family
that reliability work depends on.

That makes transport reliability changes hard to evaluate. A tester can see a
message send succeed, but still lack a trustworthy baseline for how often the
app used WiFi, direct stream, relay stream, inbox fallback, or an unknown label.

# 3. Impact Analysis

- Affected users: TestFlight users, developers, and maintainers validating
  messaging reliability, slow sends, relay dependence, and LAN behavior.
- When it appears: during 1:1 sends, inbound message handling, offline inbox
  fallback, relay-backed delivery, settings diagnostics review, and transport
  regression runs.
- Severity: medium-high for release confidence. Messaging can still work, but
  transport improvements cannot be evaluated safely without exact aggregate
  evidence.
- Frequency: recurring whenever transport behavior changes or a tester needs to
  compare direct, relay, WiFi, and inbox behavior over a session.
- Confusion cost: a partial or stale diagnostic can imply the app is using a
  transport path that was not actually observed, or can hide that a path is never
  being exercised.
- Privacy risk: any expansion of diagnostics must preserve the current
  aggregate-only shape and must not introduce peer IDs, message text,
  message-derived previews, multiaddrs, conversation IDs, or per-conversation
  traces.

# 4. Current State

This section records the intake state before the TOM-001 through TOM-005
rollout. See Section 7 for final closure evidence and residuals.

- Source investigation: `Network-Arch/Transport-Reliability/04-transport-observability.md`
  identified the original need for a client transport census, fallback-rung
  distribution, per-transport latency, LAN availability, relay metric clarity,
  and privacy-safe acceptance evidence.
- Go transport labels exist per stream. `go-mknoon/node/node.go` classifies
  `/p2p-circuit` streams as `relay` and non-circuit streams as `direct`, returns
  `streamOpenMs`, `writeMs`, and `ackWaitMs` for sends, and emits `transport` on
  inbound `message:received` events. `go-mknoon/bridge/bridge.go` includes those
  fields in the `node:send` response.
- Dart no longer defaults missing inbound transport labels to `relay` in the
  observed receive path. `lib/core/services/p2p_service_impl.dart` now records a
  post-classification transport and falls back to `unknown` when no transport or
  connection inference exists. Local WiFi messages are surfaced as `wifi`.
- Client session diagnostics exist in `lib/core/debug/transport_metrics.dart`.
  They track aggregate transport counts, fallback-rung counts, per-transport
  median/p95 latency samples, a LAN availability snapshot, and a text baseline
  report. The data model is session-scoped and aggregate-only.
- Terminal 1:1 send exits record transport diagnostics in
  `lib/features/conversation/application/send_chat_message_use_case.dart`. The
  current behavior records delivered direct/relay/WiFi/inbox outcomes, latency,
  fallback rung, and failed-rung outcomes without incrementing a transport bucket
  for failed sends.
- Settings exposes a read-only diagnostic surface through
  `lib/features/settings/presentation/widgets/settings_transport_diagnostics_card.dart`
  and `lib/features/settings/presentation/screens/settings_wired.dart` when a
  `TransportMetrics` instance is provided.
- App wiring creates and passes a shared `TransportMetrics` instance through
  `lib/main.dart`, including the P2P service, startup/feed surfaces, settings,
  and conversation routes.
- Relay-side Prometheus metrics exist in `go-relay-server/metrics.go`, including
  connection gauges/counters, inbox counters, active stream gauges, stream error
  counters, and `relay_stream_duration_seconds`. `go-relay-server/main.go`
  serves `/metrics` on port `2112`.
- Current test evidence partially covers the desired behavior:
  `test/core/debug/transport_metrics_test.dart`,
  `test/core/debug/transport_metrics_privacy_test.dart`,
  `test/core/services/p2p_service_inbound_transport_test.dart`,
  `test/core/services/p2p_service_transport_census_test.dart`, and
  `test/core/services/p2p_service_transport_latency_test.dart`.
- `lib/core/utils/flow_event_emitter.dart` now has broader redaction for
  peer-like keys, bare base58 libp2p peer IDs, multiaddrs, and secret-bearing
  fields. `test/core/debug/transport_metrics_privacy_test.dart` includes a
  negative control for bare peer IDs under both peer-like and arbitrary keys.
- Current send-path flow events in
  `lib/features/conversation/application/send_chat_message_use_case.dart`
  still include `textPreview` on send start, success, and failed events. That is
  message-derived text, and the current transport privacy evidence appears to
  cover the receive path and aggregate metrics surfaces rather than the full
  send path.
- Current integration evidence in `integration_test/transport_e2e_test.dart`
  checks persisted message status and transport labels across transport
  scenarios, but it does not appear to assert the user-visible diagnostics
  report or cross-check the client census against the relay-visible subset.
- Evidence gaps remain:
  - `updateLanAvailability` currently appears only in the metrics class and
    tests, so production diagnostics can keep showing the default LAN snapshot.
  - The relay server has many tests, but no dedicated `metrics_test.go` appears
    in `go-relay-server/` to pin metric deltas or the live metric contract.
  - A repo scan found `TransportMetrics` wired through chat/P2P/settings paths,
    but not as an explicit group-message transport census surface.
  - Standard simulator transport runs have documented limits around true LAN
    discovery in `Network-Arch/Transport-Reliability/06-test-and-simulation-strategy.md`,
    so LAN acceptance must avoid false claims from a setup that cannot produce a
    real local transport.

# 5. Scope Clarification

- In scope:
  - A user-visible, session-scoped diagnostics contract for transport mix,
    fallback-rung distribution, per-transport latency, LAN availability, and a
    readable baseline report.
  - Exact observable behavior for direct, relay, WiFi, inbox, failed, and
    unknown outcomes.
  - Privacy expectations for diagnostics, logs, flow events, relay metrics, and
    settings surfaces.
  - Explicit treatment of message-derived preview text on transport-adjacent
    diagnostics and flow-event surfaces.
  - Acceptance evidence that distinguishes true relay use from unknown labels,
    and relay-visible traffic from direct or LAN traffic.
- Non-goals:
  - No routing-policy change, NAT traversal change, relay protocol change, or
    delivery semantics change.
  - Out of scope: relay 1:1-vs-group classification, opt-in aggregate
    collectors, and hole-punch counters. These are Go-side concerns and are
    untouched by this spec.
  - No analytics exporter, dashboard product decision, opt-in telemetry policy,
    or metric naming architecture decision.
  - No per-conversation tracing, message-content telemetry, peer-identity
    telemetry, or user profiling.
  - No claim that transport reliability itself is fixed by diagnostics.
- Accepted ambiguities:
  - Whether diagnostics remain debug-only or become a local TestFlight-visible
    surface is intentionally open; any opt-in collector remains out of scope.
  - The exact UI placement, wording, and refresh cadence for diagnostics remain
    open as long as the observable contract is satisfied.
  - The exact acceptance path for true LAN availability remains open because the
    standard simulator setup is not reliable evidence for local discovery.
  - This spec does not claim all current diagnostics are absent; it captures the
    complete product-facing contract and the remaining evidence gaps.

# 6. Test Cases

## Happy Path

- A session with a known delivered mix of direct, relay, WiFi, and inbox messages
  shows exact transport counts for each bucket and a total sample count equal to
  the delivered message count.
  - Acceptance evidence: unit and integration.
  - Existing partial coverage: `test/core/debug/transport_metrics_test.dart`,
    `test/core/services/p2p_service_transport_census_test.dart`, and
    `test/core/services/p2p_service_inbound_transport_test.dart`.
- A session with known send outcomes shows exact fallback-rung counts for reuse,
  local race, direct race, relay probe, inbox fallback, and failed sends.
  - Acceptance evidence: unit and integration.
  - Existing partial coverage: `test/core/services/p2p_service_transport_census_test.dart`.
- A session with known latency samples shows median and p95 values under the
  correct transport bucket, with no slow relay sample changing the direct bucket
  and no direct sample changing the relay bucket.
  - Acceptance evidence: unit.
  - Existing partial coverage: `test/core/services/p2p_service_transport_latency_test.dart`.
- The settings diagnostics card shows the same aggregate transport mix, fallback
  rungs, latency summary, LAN state, and baseline report available from the
  session metrics object, and refreshes after new session activity.
  - Acceptance evidence: smoke.
  - Current gap: no current test found that proves the full settings card
    journey updates from live session activity.
- Relay-visible traffic appears in relay aggregate metrics, while direct or LAN
  traffic does not inflate relay-only counters.
  - Acceptance evidence: integration.
  - Current gap: existing relay metrics are present, but no dedicated relay
    metric contract test was found.
- A user or maintainer can produce a baseline report that includes transport
  percentages summing to 100 for non-empty sessions, per-transport median
  latency, fallback-rung counts, and LAN state, without any identifiers.
  - Acceptance evidence: unit and smoke.
  - Existing partial coverage: `test/core/debug/transport_metrics_test.dart` and
    `test/core/debug/transport_metrics_privacy_test.dart`.

## Edge Cases

- A missing, empty, or unrecognized inbound transport label is surfaced as
  `unknown` unless there is a true live connection inference. It is never
  silently counted as `relay`.
  - Acceptance evidence: unit.
  - Existing partial coverage: `test/core/services/p2p_service_inbound_transport_test.dart`.
- A genuine explicit relay label remains `relay`, and a true circuit connection
  inference remains `relay`.
  - Acceptance evidence: unit.
  - Existing partial coverage: `test/core/services/p2p_service_inbound_transport_test.dart`.
- A genuine non-circuit connection inference remains `direct`.
  - Acceptance evidence: unit.
  - Existing partial coverage: `test/core/services/p2p_service_inbound_transport_test.dart`.
- A failed send records the failed fallback rung but does not increment direct,
  relay, WiFi, inbox, or unknown transport buckets.
  - Acceptance evidence: unit.
  - Existing partial coverage: `test/core/services/p2p_service_transport_census_test.dart`.
- LAN availability diagnostics reflect the real discovery state, a disabled
  discovery state, or an unavailable/denied state in a way that testers cannot
  confuse with a successful zero-peer LAN scan.
  - Acceptance evidence: integration or simulator when the environment can
    credibly exercise the device context.
  - Current gap: production callers for `updateLanAvailability` were not found.
- Diagnostics remain aggregate-only when rendered outside the flow-event
  sanitizer, including baseline report text and settings surfaces.
  - Acceptance evidence: unit and smoke.
  - Existing partial coverage: `test/core/debug/transport_metrics_privacy_test.dart`.
- Flow events and diagnostic payloads that contain transport timing or transport
  labels do not contain message text, message-derived previews, long peer IDs,
  multiaddrs, keys, conversation IDs, or per-conversation traces.
  - Acceptance evidence: unit.
  - Existing partial coverage: `test/core/debug/transport_metrics_privacy_test.dart`
    and `lib/core/utils/flow_event_emitter.dart`.
  - Current gap: send-path flow events in
    `lib/features/conversation/application/send_chat_message_use_case.dart`
    still include `textPreview`, and no current transport privacy test was found
    that exercises those send-path events.
- Simulator acceptance for relay, direct, and inbox paths does not claim LAN
  success from a simulator setup that has local discovery disabled or structurally
  cannot produce true local discovery.
  - Acceptance evidence: simulator.
  - Existing adjacent evidence: `Network-Arch/Transport-Reliability/06-test-and-simulation-strategy.md`.

## Regressions to Preserve

- Preservation/regression: missing inbound transport must not regress to the old
  fabricated `relay` default. Unknown remains distinguishable from real relay.
  - Acceptance evidence: unit.
- Preservation/regression: current successful send behavior remains unchanged
  from the user's perspective. Direct, relay, WiFi, and inbox sends still produce
  the same visible message status and transport labels that existing flows rely
  on.
  - Acceptance evidence: integration and simulator.
  - Existing partial coverage: `integration_test/transport_e2e_test.dart`.
- Preservation/regression: failed sends remain visibly failed and are not counted
  as delivered by a diagnostic transport bucket.
  - Acceptance evidence: unit and integration.
- Preservation/regression: the settings screen, feed navigation, startup routing,
  and conversation routes continue to work when transport metrics are present,
  and remain safe when the metrics dependency is absent in tests or alternate
  wiring.
  - Acceptance evidence: smoke.
- Preservation/regression: relay `/metrics` remains available and existing relay
  aggregate metrics continue to report operational state without exposing message
  content or peer identities.
  - Acceptance evidence: integration.
- Preservation/regression: diagnostics do not weaken the existing privacy
  posture. No new metric, flow event, or rendered report may include plaintext
  message content, message-derived preview text, secret material, peer IDs,
  multiaddrs, conversation IDs, or per-conversation traces.
  - Acceptance evidence: unit, smoke, and simulator where diagnostics are viewed
    during a device-context journey.

# 7. Rollout Closure - 2026-05-29

Final verdict: closed.

The in-scope transport diagnostics contract is now closed for TestFlight
reliability work. The app has aggregate, session-scoped diagnostics for the
existing direct, relay, WiFi, inbox, failed-rung, unknown, latency, and LAN
availability states; send-path flow events no longer emit message-derived
previews; relay Prometheus metrics have a focused contract test; and group
transport-family metrics are explicitly closed as unsupported by current group
signals rather than inferred from identity or fanout fields.

Landed evidence:

- TOM-001 removed `textPreview` from 1:1 send flow events and added send-path
  privacy regression coverage in
  `test/features/conversation/application/send_chat_message_use_case_test.dart`.
- TOM-001 added a settings diagnostics card smoke in
  `test/features/settings/presentation/widgets/settings_transport_diagnostics_card_test.dart`
  proving the rendered aggregate mix, rung counts, latency, LAN state, and
  baseline report refresh from `TransportMetrics`.
- TOM-002 wired production LAN availability snapshots in
  `lib/core/services/p2p_service_impl.dart` from local discovery lifecycle and
  discovered-peer count, without storing peer IDs, hosts, ports, or multiaddrs.
- TOM-002 added
  `test/core/services/p2p_service_lan_availability_test.dart` for inactive,
  active zero-peer, and active nonzero-peer LAN snapshots plus report privacy.
- TOM-003 added `go-relay-server/metrics_test.go`, pinning representative relay
  Prometheus counter, gauge, gauge-vector, counter-vector, histogram, and scrape
  output behavior without identifier or message-content fragments.
- TOM-004 added
  `group send diagnostics expose fanout evidence without transport identity labels`
  in `test/features/groups/application/send_group_message_use_case_test.dart`.
  That test proves group diagnostics expose only aggregate fanout/custody
  evidence such as `topicPeers`, `expectedRecipientCount`, `liveFanoutState`,
  `inboxStored`, `inboxPending`, and `recipientReceiptClaimed`.

Verification evidence:

- `flutter test test/features/conversation/application/send_chat_message_use_case_test.dart`
  passed.
- `flutter test test/features/settings/presentation/widgets/settings_transport_diagnostics_card_test.dart`
  passed after a standalone rerun; the first attempt hit a Flutter native-assets
  startup race while another Flutter command was resolving dependencies.
- `flutter test test/core/debug/transport_metrics_privacy_test.dart` passed.
- `flutter test test/core/utils/flow_event_emitter_test.dart` passed.
- `./scripts/run_test_gates.sh 1to1` passed.
- `flutter test test/core/services/p2p_service_lan_availability_test.dart`
  passed.
- `flutter test test/core/debug/transport_metrics_test.dart` passed.
- `flutter test test/core/services/p2p_service_inbound_transport_test.dart`
  passed.
- `FLUTTER_DEVICE_ID=5BA69F1C-B112-47BE-B1FF-8C1003728C8F ./scripts/run_test_gates.sh transport`
  passed. The unpinned transport-gate attempt stopped before running tests
  because multiple Flutter devices were available.
- `cd go-relay-server && go test ./...` passed.
- `flutter test test/features/groups/application/send_group_message_use_case_test.dart --plain-name "group send diagnostics expose fanout evidence without transport identity labels"`
  passed.

Accepted residuals:

- Standard simulator runs are still not proof of true LAN discovery or WiFi
  transport success. The closed contract is production LAN snapshot wiring plus
  fake local-discovery test evidence, without claiming physical LAN behavior
  from the standard simulator setup.
- Group transport-family census remains unsupported until the native/bridge
  layer exposes a trustworthy terminal signal. Current safe group evidence is
  aggregate fanout and durable inbox custody, not direct, relay, or WiFi
  transport family.
- Relay 1:1-vs-group traffic classification, analytics exporters, dashboards,
  telemetry policy, routing behavior, NAT traversal, hole punching, and relay
  protocol changes remain out of scope.
