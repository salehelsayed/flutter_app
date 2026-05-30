# 1. Title and Type

- Title: Reliable Same-WiFi 1:1 Delivery
- Issue type: feature-improvement
- Output doc path: `Test-Flight-Improv/49-lan-wifi-delivery-reliability.md`

# 2. Problem Statement

Users who are near each other on the same WiFi expect 1:1 messages and media to
send quickly, without depending on relay infrastructure when a local route is
available. If the local route is not available, the app should still deliver
through direct, relay, or inbox fallback without misleading the user or tester
about which path was used.

The app already has a same-WiFi transport path, but the product contract needs a
durable acceptance spec. The source tracking doc records prior risks where local
delivery could be skipped during first-send discovery, stale peer entries could
burn send time, local media could miss the receive pipeline, and iOS Local
Network permission denial could look like an ordinary zero-peer LAN.

In the current working tree, several of those gaps now have code and host-test
evidence. The remaining user-facing risk is that same-WiFi reliability can still
be overclaimed unless the product can prove that the local path is selected when
available, falls back cleanly when unavailable, handles media, and reports LAN
availability without false confidence from simulator runs that disable local
discovery.

# 3. Impact Analysis

- Affected users: people sending 1:1 chat messages, images, voice messages,
  introductions, contact requests, delete/tombstone updates, or share-batch
  deliveries to a peer on the same local network.
- When it appears: app cold open, foreground recovery, first send after both
  peers become active, peer departure from WiFi, local media transfer, and iOS
  Local Network permission denial.
- Severity: medium-high for latency, relay cost, and release confidence. Message
  correctness is protected by fallback paths, but users lose the fast local
  experience when the LAN path is skipped or misreported.
- Frequency: recurring for nearby 1:1 use cases. Repo evidence shows the local
  stack is production-wired, but standard simulator setup disables local
  discovery, so automated evidence can under-measure real LAN behavior.
- Confusion cost: a zero WiFi count from a simulator run can be mistaken for a
  LAN failure even though the harness disables discovery. A successful relay send
  can also mask whether the same-WiFi path was ever available.

# 4. Current State

- Source investigation: `Network-Arch/Transport-Reliability/01-lan-wifi-reliability.md`
  identifies NET-REL-01 as the same-WiFi reliability workstream and records the
  original reliability risks around discovery timing, stale peer entries, local
  media receive wiring, permission visibility, and transport proof.
- Production local discovery is enabled unless `DISABLE_LOCAL_DISCOVERY` is set.
  `lib/main.dart` chooses `BonsoirDiscoveryService` for normal builds and
  `DisabledLocalDiscoveryService` for disabled local discovery. `reset_simulators.sh`
  builds simulators with `DISABLE_LOCAL_DISCOVERY=true`, so standard simulator
  runs are not evidence of real mDNS discovery.
- iOS declares Bonjour and Local Network usage strings in `ios/Runner/Info.plist`.
  Android declares `CHANGE_WIFI_MULTICAST_STATE` in
  `android/app/src/main/AndroidManifest.xml`.
- The local stack is separate from go-libp2p: `BonsoirDiscoveryService` advertises
  and discovers `_mknoon._tcp` peers, `LocalP2PService` composes discovery with
  `LocalWsServer`, and `LocalWsServer` sends plaintext local WebSocket frames
  containing peer IDs, a nonce, and the already-built encrypted message envelope.
- The current local peer model has a 30-second freshness boundary. `LocalPeer.ttl`
  and `LocalPeer.isStale` define the rule, and `BonsoirDiscoveryService.getLocalPeer`
  drops stale entries at read time.
- The current send race adds the local leg for every interactive chat send.
  If the peer is not already local, `send_chat_message_use_case.dart` runs a
  bounded local resolve before attempting the local send, while the direct leg
  remains in the race. Existing tests cover discovered local success,
  stale/absent local fast-fail, discover-on-send success, and non-LAN negative
  control.
- Outbound local chat success is persisted with the sender-side transport label
  `local`. Incoming local WebSocket messages are merged by `P2PServiceImpl` with
  transport `wifi` and recorded into transport metrics.
- Local media is now production-wired. `lib/main.dart` configures
  `LocalMediaServer` on `LocalWsServer`, and `P2PServiceImpl` listens to
  `mediaReadyStream`. The app then persists received local media and links the
  matching pending attachment row when it is still pending.
- Conversation UI send paths try local media first when the peer is local, then
  fall back to relay upload when local media does not succeed. Evidence:
  `lib/features/conversation/presentation/screens/conversation_wired.dart`.
- LAN diagnostics are aggregate and privacy-safe. `TransportMetrics` tracks
  discovery active/inactive state, peer count, and a heuristic
  `suspectedPermissionDenied` flag; the settings diagnostics card renders those
  values without peer IDs, hostnames, raw addresses, or message content.
- Host and loopback evidence exists for major local contracts:
  `test/features/conversation/application/send_chat_message_use_case_test.dart`,
  `test/core/local_discovery/local_peer_ttl_test.dart`,
  `test/core/local_discovery/local_ws_integration_i1_i2_test.dart`,
  `test/core/services/p2p_service_lan_availability_test.dart`,
  `test/core/services/p2p_service_local_media_wiring_test.dart`,
  `test/core/local_discovery/local_p2p_service_test.dart`, and
  `integration_test/wifi_transport_test.dart`.
- Current evidence gap: repo-local tests use loopback or fake discovery for the
  local stack. `BonsoirDiscoveryService` is not exercised by current host tests,
  and standard simulator setup disables local discovery, so real mDNS same-LAN
  selection is not proven by those runs.

# 5. Scope Clarification

- In scope:
  - User-visible 1:1 delivery behavior when both peers are on the same WiFi.
  - Correct fallback behavior when the LAN path is unavailable, stale, denied, or
    too slow.
  - Local text and local media behavior for existing 1:1 surfaces that already
    call the local transport.
  - Truthful transport labels and aggregate LAN diagnostics that avoid exposing
    private peer or message data.
  - Acceptance criteria that distinguish loopback/fake discovery evidence from
    real local-network discovery evidence.
- Non-goals:
  - No change to group-message routing, NAT traversal, DCUtR, relay springboard,
    or cross-network direct-delivery policy.
  - No architecture decision about WebSocket metadata encryption, Noise/TLS, or
    identity challenge design for LAN routing.
  - No implementation session split, rollout order, ownership assignment, or
    code-level solution proposal.
  - No promise that every same-building or same-carrier peer is on the same LAN;
    the expectation only applies when local discovery can credibly see the peer.
- Accepted ambiguities:
  - The exact future UX surface for Local Network permission guidance remains
    open.
  - The exact acceptance environment for true mDNS same-LAN proof remains open;
    the spec only states that standard simulator runs with local discovery
    disabled must not be treated as that proof.
  - The acceptable long-term LAN metadata exposure model remains a product and
    security decision outside this spec.

# 6. Test Cases

## Happy Path

- When two existing 1:1 contacts are on the same WiFi and local discovery can see
  the target peer, a text message sends successfully through the local path and
  the sender-side stored transport is `local`.
  - Acceptance evidence: unit, integration, and smoke where local discovery is
    enabled.
  - Existing partial coverage:
    `test/features/conversation/application/send_chat_message_use_case_test.dart`
    and `test/core/resilience/f1_wifi_relay_fallback_test.dart`.
  - Current gap: standard simulator runs do not prove real mDNS discovery because
    local discovery is disabled there.
- When the sender opens a conversation before the peer has already been recorded
  in the local peer map, a bounded same-WiFi discovery window can still allow the
  peer to join the send race and deliver locally.
  - Acceptance evidence: unit and integration.
  - Existing partial coverage:
    `test/features/conversation/application/send_chat_message_use_case_test.dart`.
- When a same-WiFi peer sends a local WebSocket message, the receiver accepts the
  encrypted envelope, acknowledges it, and records the incoming transport in the
  WiFi/local transport bucket without exposing message plaintext.
  - Acceptance evidence: integration.
  - Existing partial coverage:
    `test/core/local_discovery/local_ws_integration_i1_i2_test.dart` and
    `integration_test/wifi_transport_test.dart`.
- When two 1:1 peers are local and media transfer succeeds, image or voice bytes
  are received through the local media path, pass token authorization and
  SHA-256 verification, are persisted outside the temporary area, and become
  linked to the pending attachment.
  - Acceptance evidence: integration and smoke.
  - Existing partial coverage:
    `test/core/services/p2p_service_local_media_wiring_test.dart`,
    `test/core/local_discovery/local_media_server_test.dart`,
    `test/core/local_discovery/local_media_integration_test.dart`, and
    `integration_test/wifi_transport_test.dart`.
- LAN diagnostics show discovery as active, show only an aggregate discovered
  peer count, and do not expose peer identifiers, hostnames, raw addresses,
  message content, or conversation identifiers.
  - Acceptance evidence: unit and smoke.
  - Existing partial coverage:
    `test/core/services/p2p_service_lan_availability_test.dart` and
    `lib/features/settings/presentation/widgets/settings_transport_diagnostics_card.dart`.

## Edge Cases

- When a previously discovered peer has left WiFi or the local entry is stale,
  the message does not wait through the full local send budget before another
  available transport carries it, and the final stored transport is not `local`.
  - Acceptance evidence: unit and integration.
  - Existing partial coverage:
    `test/core/local_discovery/local_peer_ttl_test.dart`,
    `test/features/conversation/application/send_chat_message_use_case_test.dart`,
    and `test/core/local_discovery/local_ws_integration_i1_i2_test.dart`.
- When a peer is not on the LAN, local discovery may be attempted inside the
  bounded window, but local send is not falsely reported as successful and the
  message uses direct, relay, or inbox fallback.
  - Acceptance evidence: unit and integration.
  - Existing partial coverage:
    `test/features/conversation/application/send_chat_message_use_case_test.dart`.
- When the local WebSocket server accepts a connection but never acknowledges the
  message, the local attempt fails inside the bounded local budget and the app
  continues through the fallback ladder without duplicating the delivered
  message.
  - Acceptance evidence: integration.
  - Existing partial coverage:
    `test/core/local_discovery/local_ws_integration_i1_i2_test.dart` and
    `integration_test/wifi_transport_test.dart`.
- When local media receives a missing token, wrong token, unknown media ID,
  oversized body, short body, disallowed type, duplicate offer, or SHA-256
  mismatch, no completed attachment is surfaced and relay fallback remains able
  to complete the user-visible send.
  - Acceptance evidence: unit and integration.
  - Existing partial coverage:
    `test/core/local_discovery/local_media_server_test.dart`,
    `test/core/local_discovery/local_media_integration_test.dart`, and
    `test/core/services/p2p_service_local_media_wiring_test.dart`.
- When iOS local discovery stays active with zero peers long enough to suspect a
  Local Network permission problem, diagnostics mark the state as
  `suspected-denied`; when a peer appears or discovery stops, that suspected
  state clears.
  - Acceptance evidence: unit and simulator only for the diagnostic UI state;
    not as proof of true mDNS LAN delivery.
  - Existing partial coverage:
    `test/core/services/p2p_service_lan_availability_test.dart`.
- When a standard simulator run reports zero WiFi/local transport, that result is
  not treated as proof that real LAN delivery failed, because the simulator build
  disables local discovery.
  - Acceptance evidence: smoke.
  - Existing partial coverage: `reset_simulators.sh` and
    `Test-Flight-Improv/99-transport-observability-and-metrics.md`.

## Regressions to Preserve

- Preservation/regression: direct, relay, relay-probe, and inbox fallback keep
  delivering 1:1 messages when the local path is unavailable, and a local miss
  does not block user delivery.
  - Acceptance evidence: unit, integration, and smoke.
  - Existing partial coverage:
    `test/features/conversation/application/send_chat_message_use_case_test.dart`
    and adjacent 1:1 reliability tests.
- Preservation/regression: non-LAN peers are never labeled `local` or counted as
  WiFi/local success just because the local race leg exists.
  - Acceptance evidence: unit.
  - Existing partial coverage:
    `test/features/conversation/application/send_chat_message_use_case_test.dart`.
- Preservation/regression: incoming local messages continue to enter the unified
  receive stream with the WiFi/local transport bucket, and existing message
  rendering and database transport persistence continue to handle that label.
  - Acceptance evidence: unit and integration.
  - Existing partial coverage:
    `test/core/services/p2p_service_inbound_transport_test.dart`,
    `test/features/conversation/application/chat_message_listener_test.dart`, and
    database transport-column tests.
- Preservation/regression: existing media relay upload fallback remains intact
  when local media is unavailable or rejected, including pending attachment
  handling and upload progress behavior.
  - Acceptance evidence: smoke and integration.
- Preservation/regression: LAN diagnostics remain aggregate and privacy-safe
  after any future same-WiFi reliability change.
  - Acceptance evidence: unit and smoke.
  - Existing partial coverage:
    `test/core/services/p2p_service_lan_availability_test.dart` and
    `test/core/debug/transport_metrics_test.dart`.
