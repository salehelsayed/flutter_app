# LAN-001 - Host Local-Delivery and Fallback Contract Plan

Status: execution-ready

## Planning Progress

- 2026-05-29T21:43:46Z - Planner completed. Files inspected since last update: none. Decision/blocker: draft plan written; no blocker. Next action: run strict reviewer pass against scope, proof profile, gates, and checklist coverage.
- 2026-05-29T21:45:11Z - Reviewer started. Files inspected since last update: `Test-Flight-Improv/49-lan-wifi-delivery-reliability-session-LAN-001-plan.md`. Decision/blocker: checking for missing gates, stale assumptions, simulator overclaim, and checklist parity. Next action: record sufficiency review.
- 2026-05-29T21:45:11Z - Reviewer completed. Files inspected since last update: plan artifact only. Decision/blocker: sufficient with minor adjustments; no structural blocker. Next action: arbiter classification and final execution-ready status.
- 2026-05-29T21:45:38Z - Arbiter started. Files inspected since last update: plan artifact only. Decision/blocker: classifying reviewer findings into structural blockers, incremental details, and accepted differences. Next action: finalize verdict.
- 2026-05-29T21:45:38Z - Arbiter completed. Files inspected since last update: plan artifact only. Decision/blocker: no structural blockers remain; accepted differences are explicit and aligned with LAN-002/LAN-003. Next action: hand off execution-ready LAN-001 plan.

## Controller Dirty Worktree Snapshot

Captured before LAN-001 execution at 2026-05-29T21:46:10Z:

```text
 M Network-Arch/Transport-Reliability/00-INDEX.md
 M Network-Arch/Transport-Reliability/01-lan-wifi-reliability.md
 M Network-Arch/Transport-Reliability/02-nat-traversal-dcutr.md
 M go-mknoon/bridge/events.go
 M go-mknoon/node/node.go
 M go-mknoon/node/transport_label_test.go
 M info.plist
 M integration_test/wifi_transport_test.dart
 M lib/core/bridge/bridge.dart
 M lib/core/bridge/go_bridge_client.dart
 M lib/core/local_discovery/bonsoir_discovery_service.dart
 M lib/core/local_discovery/disabled_local_discovery_service.dart
 M lib/core/local_discovery/local_discovery_service.dart
 M lib/core/local_discovery/local_p2p_service.dart
 M lib/core/local_discovery/local_ws_server.dart
 M lib/core/services/p2p_service.dart
 M lib/core/services/p2p_service_impl.dart
 M lib/core/utils/flow_event_emitter.dart
 M lib/features/conversation/application/send_chat_message_use_case.dart
 M lib/features/conversation/presentation/screens/conversation_wired.dart
 M lib/features/feed/presentation/screens/feed_wired.dart
 M lib/features/identity/presentation/startup_router.dart
 M lib/features/settings/presentation/screens/settings_wired.dart
 M lib/main.dart
 M test/core/bridge/go_bridge_client_test.dart
 M test/core/local_discovery/fake_local_discovery_service.dart
 M test/core/local_discovery/fake_local_p2p_service.dart
 M test/core/local_discovery/local_p2p_service_test.dart
 M test/core/resilience/c2_ack_drop_test.dart
 M test/core/resilience/c3_half_open_test.dart
 M test/core/services/fake_p2p_service.dart
 M test/core/services/incoming_message_router_posts_engagement_test.dart
 M test/core/services/incoming_message_router_posts_pass_test.dart
 M test/core/services/incoming_message_router_posts_pins_test.dart
 M test/core/services/incoming_message_router_posts_presence_test.dart
 M test/core/services/incoming_message_router_posts_test.dart
 M test/core/services/incoming_message_router_profile_test.dart
 M test/core/services/incoming_message_router_test.dart
 M test/core/services/p2p_service_fault_injection_test.dart
 M test/features/contact_request/application/accept_and_reciprocate_use_case_test.dart
 M test/features/contact_request/application/send_contact_request_use_case_test.dart
 M test/features/conversation/application/send_chat_message_no_bg_task_test.dart
 M test/features/conversation/application/send_chat_message_use_case_test.dart
 M test/features/conversation/application/send_voice_message_no_bg_task_test.dart
 M test/features/conversation/integration/send_then_lock_delivery_test.dart
 M test/features/conversation/integration/two_user_message_exchange_test.dart
 M test/features/conversation/presentation/screens/conversation_wired_bg_task_test.dart
 M test/features/conversation/presentation/screens/conversation_wired_gif_test.dart
 M test/features/conversation/presentation/screens/conversation_wired_sending_to_failed_test.dart
 M test/features/conversation/presentation/screens/conversation_wired_test.dart
 M test/features/feed/presentation/screens/feed_wired_bg_task_test.dart
 M test/features/groups/application/send_group_message_use_case_test.dart
 M test/features/identity/presentation/screens/startup_router_test.dart
 M test/features/introduction/integration/intro_wiring_smoke_test.dart
 M test/features/push/application/register_push_token_use_case_test.dart
 M test/features/settings/application/upload_profile_picture_use_case_test.dart
 M test/features/settings/presentation/screens/settings_wired_posts_nearby_test.dart
 M test/features/settings/presentation/screens/settings_wired_test.dart
 M test/shared/fakes/chaos_p2p_network.dart
 M test/shared/fakes/fake_p2p_service_integration.dart
 M tool/analyzer_baseline/flutter_analyze_baseline.tsv
?? Network-Arch/Transport-Reliability/01-lan-wifi-IMPLEMENTATION-PLAN.md
?? Network-Arch/Transport-Reliability/05-send-orchestration-IMPLEMENTATION-PLAN.md
?? Test-Flight-Improv/100-nat-traversal-dcutr-evidence-session-DCUTR-001-plan.md
?? Test-Flight-Improv/100-nat-traversal-dcutr-evidence-session-DCUTR-002-plan.md
?? Test-Flight-Improv/100-nat-traversal-dcutr-evidence-session-breakdown.md
?? Test-Flight-Improv/100-nat-traversal-dcutr-evidence.md
?? Test-Flight-Improv/49-lan-wifi-delivery-reliability-session-LAN-001-plan.md
?? Test-Flight-Improv/49-lan-wifi-delivery-reliability-session-breakdown.md
?? Test-Flight-Improv/49-lan-wifi-delivery-reliability.md
?? Test-Flight-Improv/99-transport-observability-and-metrics-HARVEST-DECISION.md
?? Test-Flight-Improv/99-transport-observability-and-metrics-session-TOM-001-plan.md
?? Test-Flight-Improv/99-transport-observability-and-metrics-session-TOM-002-plan.md
?? Test-Flight-Improv/99-transport-observability-and-metrics-session-TOM-003-plan.md
?? Test-Flight-Improv/99-transport-observability-and-metrics-session-TOM-004-plan.md
?? Test-Flight-Improv/99-transport-observability-and-metrics-session-TOM-005-plan.md
?? Test-Flight-Improv/99-transport-observability-and-metrics-session-breakdown.md
?? Test-Flight-Improv/99-transport-observability-and-metrics.md
?? Test-Flight-Improv/NET-REL-04-baseline-decision-gate.md
?? Test-Flight-Improv/NET-REL-04-baseline-harvest-runbook.md
?? go-mknoon/node/holepunch_feasibility_test.go
?? go-mknoon/node/holepunch_negative_control_test.go
?? go-mknoon/node/holepunch_tracer.go
?? go-mknoon/node/holepunch_tracer_test.go
?? go-relay-server/metrics_test.go
?? lib/core/debug/transport_metrics.dart
?? lib/features/settings/presentation/widgets/settings_transport_diagnostics_card.dart
?? test/core/debug/
?? test/core/local_discovery/local_peer_ttl_test.dart
?? test/core/local_discovery/local_ws_integration_i1_i2_test.dart
?? test/core/services/p2p_service_inbound_transport_test.dart
?? test/core/services/p2p_service_lan_availability_test.dart
?? test/core/services/p2p_service_local_media_wiring_test.dart
?? test/core/services/p2p_service_transport_census_test.dart
?? test/core/services/p2p_service_transport_latency_test.dart
?? test/features/settings/presentation/widgets/settings_transport_diagnostics_card_test.dart
```

## real scope

LAN-001 owns only host-verifiable same-WiFi 1:1 delivery contracts:

- Sender-side local text delivery through the local race leg, with delivered rows persisted as transport `local`.
- Stale, absent, denied-by-disabled-discovery, too-slow, or non-LAN local candidates falling through to direct, relay probe, or inbox without persisting `local`.
- Bounded discover-on-send before the local leg, so a same-LAN peer that was not already in the map can join the race.
- Incoming local WebSocket messages surfaced through the receiver-side WiFi/local transport bucket.
- Local media send/receive wiring, including production-like receive persistence and relay upload fallback when local media fails.
- Aggregate LAN diagnostics only: active/inactive discovery, discovered peer count, and suspected permission-denied heuristic.

LAN-001 does not prove true Bonjour/mDNS behavior on physical same-WiFi devices. It does not close final docs or matrix rows; LAN-003 owns closure docs after LAN-001 and LAN-002 evidence is available.

## closure bar

The session is closable when all LAN-001 host contracts are either already green or repaired with focused regressions:

| Source requirement | LAN-001 proof | Status target |
| --- | --- | --- |
| Visible same-WiFi peer can win the 1:1 send race and persist sender transport `local`. | `test/features/conversation/application/send_chat_message_use_case_test.dart` NET-REL-01 U1 and local send/budget tests. | Required. |
| Unknown-but-LAN-present peer can be found during bounded discover-on-send. | `send_chat_message_use_case_test.dart` NET-REL-01 U3 plus `LocalP2PService.discoverLocalPeer` coverage. | Required. |
| Stale, absent, too-slow, disabled, or non-LAN local path falls back without false `local`. | `send_chat_message_use_case_test.dart` NET-REL-01 U2/U-N1, relay probe/inbox tests, `test/core/resilience/f1_wifi_relay_fallback_test.dart`, `test/core/resilience/f2_transport_switch_recovery_test.dart`, `test/core/local_discovery/local_ws_integration_i1_i2_test.dart` I2. | Required. |
| Incoming local WebSocket messages surface as receiver-side WiFi/local bucket. | `test/core/services/p2p_service_inbound_transport_test.dart` T5 and `test/core/local_discovery/local_ws_integration_i1_i2_test.dart` I1. | Required. |
| Local media can be offered, received, verified, persisted, and linked; relay upload fallback remains intact when local media fails. | `test/core/services/p2p_service_local_media_wiring_test.dart`, `test/core/local_discovery/local_media_server_test.dart`, `test/core/local_discovery/local_media_integration_test.dart`, conversation media/voice tests if touched. | Required. |
| LAN diagnostics stay aggregate and privacy-safe. | `test/core/debug/transport_metrics_test.dart`, `test/core/debug/transport_metrics_privacy_test.dart`, `test/core/services/p2p_service_lan_availability_test.dart`, `test/features/settings/presentation/widgets/settings_transport_diagnostics_card_test.dart`. | Required. |
| Standard simulator runs with `DISABLE_LOCAL_DISCOVERY=true` are not treated as proof of real mDNS success or failure. | `reset_simulators.sh` and this plan's Device/Relay Proof Profile. | Required classification, not behavior work unless docs are edited. |
| Real same-WiFi physical-device mDNS proof records sender-side `local`. | Deferred to LAN-002. | Accepted out of scope for LAN-001. |

## source of truth

- Active planning contract: `Test-Flight-Improv/49-lan-wifi-delivery-reliability-session-breakdown.md`, LAN-001 row only.
- Product/source contract: `Test-Flight-Improv/49-lan-wifi-delivery-reliability.md`.
- Gate source of truth: `scripts/run_test_gates.sh`; if it disagrees with `Test-Flight-Improv/test-gate-definitions.md`, the script wins.
- Current code and tests beat stale prose. The working tree is dirty with many pre-existing edits; executor must not revert unrelated changes.

## session classification

`implementation-ready`

This is implementation-ready with an evidence-first posture: if current tests already pass, the session may close as validation and small repair only. It is not evidence-gated on physical devices because real mDNS proof is explicitly LAN-002.

## exact problem statement

Same-WiFi 1:1 delivery is risky if the app can appear reliable only because relay/direct/inbox fallback succeeds. LAN-001 must prove the host-verifiable contract: local text and media are actually attempted and labeled correctly when local is available, local misses do not block delivery or falsely record `local`, incoming local traffic is counted as WiFi/local, and diagnostics expose only aggregate LAN state. User-visible delivery through existing direct, relay, and inbox paths must stay unchanged.

## Device/Relay Proof Profile

- LAN-001 proof class: host and loopback evidence required.
- Required evidence type: unit/widget/host tests plus loopback `LocalWsServer` and `LocalMediaServer` tests using fake or localhost discovery. These prove transport mechanics, labels, time budgets, media persistence, fallback behavior, and aggregate diagnostics.
- `integration_test/wifi_transport_test.dart` profile: loopback/device-bound local WebSocket and media confidence only. It communicates over localhost and its header says it does not test mDNS. It may be run on a macOS/simulator target when available, but a green run is not real same-WiFi mDNS proof.
- Physical-device mDNS proof: explicitly excluded from LAN-001 and deferred to LAN-002. Do not require two physical devices, local-network permission prompts, or Bonjour discovery evidence to close LAN-001.
- Relay proof: relay/direct/inbox fallback must be preserved by host tests and relevant named gates. No external relay fixture is required for LAN-001 unless the executor changes bootstrap, reconnect, or transport gate wiring.
- Device availability inspection: not needed for LAN-001 planning or closure evidence. No live `flutter devices` command was run during planning because this session can close on host/loopback evidence, and device availability would not change the LAN-001 closure bar.

## files and repos to inspect next

Production and wiring files:

- `lib/core/local_discovery/local_discovery_service.dart`
- `lib/core/local_discovery/bonsoir_discovery_service.dart`
- `lib/core/local_discovery/disabled_local_discovery_service.dart`
- `lib/core/local_discovery/local_p2p_service.dart`
- `lib/core/local_discovery/local_ws_server.dart`
- `lib/core/local_discovery/local_media_server.dart`
- `lib/core/services/p2p_service.dart`
- `lib/core/services/p2p_service_impl.dart`
- `lib/core/debug/transport_metrics.dart`
- `lib/main.dart`
- `lib/features/conversation/application/send_chat_message_use_case.dart`
- `lib/features/conversation/presentation/screens/conversation_wired.dart`
- `lib/features/settings/presentation/widgets/settings_transport_diagnostics_card.dart`
- `reset_simulators.sh`
- `ios/Runner/Info.plist`
- `android/app/src/main/AndroidManifest.xml`

Tests and gate docs:

- `test/features/conversation/application/send_chat_message_use_case_test.dart`
- `test/core/resilience/f1_wifi_relay_fallback_test.dart`
- `test/core/resilience/f2_transport_switch_recovery_test.dart`
- `test/core/local_discovery/local_peer_ttl_test.dart`
- `test/core/local_discovery/local_p2p_service_test.dart`
- `test/core/local_discovery/local_ws_integration_i1_i2_test.dart`
- `test/core/local_discovery/local_media_server_test.dart`
- `test/core/local_discovery/local_media_integration_test.dart`
- `test/core/services/p2p_service_inbound_transport_test.dart`
- `test/core/services/p2p_service_local_media_wiring_test.dart`
- `test/core/services/p2p_service_lan_availability_test.dart`
- `test/core/services/p2p_service_transport_census_test.dart`
- `test/core/services/p2p_service_transport_latency_test.dart`
- `test/core/debug/transport_metrics_test.dart`
- `test/core/debug/transport_metrics_privacy_test.dart`
- `test/features/settings/presentation/widgets/settings_transport_diagnostics_card_test.dart`
- `integration_test/wifi_transport_test.dart`
- `Test-Flight-Improv/test-gate-definitions.md`
- `scripts/run_test_gates.sh`

## existing tests covering this area

- `send_chat_message_use_case_test.dart` has NET-REL-01 U1, U2, U3, and U-N1 coverage for local success, TTL/absent local fallback, discover-on-send, and non-LAN negative control.
- `local_peer_ttl_test.dart` pins `LocalPeer.ttl == 30 seconds` and strict stale-boundary behavior.
- `local_p2p_service_test.dart` covers start/stop, local peer delegation, local send, timeout forwarding, local media send, discovered peer stream, and incoming WS messages.
- `local_ws_integration_i1_i2_test.dart` covers loopback text ack, local media production-wiring persistence, silent-server ack timeout, stale host/port failure, and recovery.
- `local_media_server_test.dart` and `local_media_integration_test.dart` cover token, MIME, declared size, SHA-256, duplicate, path traversal, persistence, and transfer failure behavior.
- `p2p_service_inbound_transport_test.dart` T5 covers local WiFi messages surfacing as `wifi` and censused as WiFi/local.
- `p2p_service_local_media_wiring_test.dart` covers `P2PServiceImpl` consuming `mediaReadyStream` and negative media-server-unconfigured behavior.
- `p2p_service_lan_availability_test.dart`, `transport_metrics_test.dart`, `transport_metrics_privacy_test.dart`, and `settings_transport_diagnostics_card_test.dart` cover aggregate LAN diagnostics and privacy-safe rendering.
- `f1_wifi_relay_fallback_test.dart` and `f2_transport_switch_recovery_test.dart` cover fallback and WiFi/relay transition preservation.
- `integration_test/wifi_transport_test.dart` covers localhost LocalWsServer send/ack, pool reuse, idle disconnect, malformed input, concurrency, max connection recovery, remote close, media transfer, production wiring, and stale host failure. It is not mDNS proof.

## regression/tests to add first

Before changing production code, verify that each required proof already exists. Add or repair a focused regression only for a missing or failing proof:

- Missing sender-side local success or negative-control coverage: add to `test/features/conversation/application/send_chat_message_use_case_test.dart` under NET-REL-01.
- Missing TTL or stale map behavior: add to `test/core/local_discovery/local_peer_ttl_test.dart` or `test/core/local_discovery/local_p2p_service_test.dart`.
- Missing loopback ack, timeout, stale host, or local media receive proof: add to `test/core/local_discovery/local_ws_integration_i1_i2_test.dart`.
- Missing local media auth/hash/persistence edge coverage: add to `test/core/local_discovery/local_media_server_test.dart`, `test/core/local_discovery/local_media_integration_test.dart`, or `test/core/services/p2p_service_local_media_wiring_test.dart`.
- Missing receiver-side WiFi/local classification: add to `test/core/services/p2p_service_inbound_transport_test.dart`.
- Missing aggregate diagnostics or privacy coverage: add to `test/core/debug/transport_metrics_test.dart`, `test/core/debug/transport_metrics_privacy_test.dart`, `test/core/services/p2p_service_lan_availability_test.dart`, or `test/features/settings/presentation/widgets/settings_transport_diagnostics_card_test.dart`.

Do not add a broad simulator scenario or real-device fixture in LAN-001. If all proofs are already present and green, do not create duplicate tests.

## step-by-step implementation plan

1. Confirm the worktree state with `git status --short` and treat all unrelated dirty files as pre-existing user/agent work.
2. Run the focused direct tests listed in `exact tests and gates to run` before changing production code. If failures are unrelated and pre-existing, record them under known-failure interpretation before making LAN-001 edits.
3. For any missing or failing LAN-001 proof, add the smallest direct regression in the nearest test file from `regression/tests to add first`.
4. Repair only the failing host-verifiable seam:
   - Local text/discover/fallback: `send_chat_message_use_case.dart`, `local_p2p_service.dart`, `bonsoir_discovery_service.dart`, or `disabled_local_discovery_service.dart`.
   - Local WS/media mechanics: `local_ws_server.dart`, `local_media_server.dart`, `p2p_service_impl.dart`, or `main.dart`.
   - Media send fallback: `conversation_wired.dart`.
   - LAN metrics/diagnostics: `transport_metrics.dart`, `p2p_service_impl.dart`, or `settings_transport_diagnostics_card.dart`.
5. If production Flutter code changes, run the focused direct tests again and then the required named gate from the gate contract below.
6. Edit `Test-Flight-Improv/test-gate-definitions.md` only if a new direct test file or new classification is introduced; then run `./scripts/run_test_gates.sh completeness-check`.
7. Stop when LAN-001 host/loopback evidence is green or when a failure is proven to require physical-device mDNS evidence. Physical-device evidence reclassifies the finding to LAN-002; it is not fixed in LAN-001.

## risks and edge cases

- A local leg could win incorrectly because the test hard-codes `local`; U-N1 must remain in the proof set.
- Stale local peers could consume the interactive send budget; TTL and stale host tests must keep the failure bounded.
- Discover-on-send could block direct fallback; U2/U3 and resilience tests must show bounded local resolve and parallel fallback.
- Local media success could bypass relay upload but fail to persist or link the received file; local media wiring tests must cover persistent path behavior.
- Relay fallback could regress when local media fails; direct conversation media tests should be run if `conversation_wired.dart` changes.
- LAN diagnostics could expose peer IDs, hostnames, addresses, message content, or conversation IDs; privacy tests must remain exact.
- Simulator runs may report zero WiFi/local because discovery is disabled; do not interpret that as a LAN failure.

## exact tests and gates to run

Focused direct tests:

```bash
flutter test test/features/conversation/application/send_chat_message_use_case_test.dart
flutter test test/core/resilience/f1_wifi_relay_fallback_test.dart test/core/resilience/f2_transport_switch_recovery_test.dart
flutter test test/core/local_discovery/local_peer_ttl_test.dart test/core/local_discovery/local_p2p_service_test.dart test/core/local_discovery/local_ws_integration_i1_i2_test.dart test/core/local_discovery/local_media_server_test.dart test/core/local_discovery/local_media_integration_test.dart
flutter test test/core/services/p2p_service_inbound_transport_test.dart test/core/services/p2p_service_local_media_wiring_test.dart test/core/services/p2p_service_lan_availability_test.dart test/core/services/p2p_service_transport_census_test.dart test/core/services/p2p_service_transport_latency_test.dart
flutter test test/core/debug/transport_metrics_test.dart test/core/debug/transport_metrics_privacy_test.dart
flutter test test/features/settings/presentation/widgets/settings_transport_diagnostics_card_test.dart
```

Loopback/device-bound companion, not mDNS proof:

```bash
flutter test -d macos integration_test/wifi_transport_test.dart
```

Run this companion when `LocalWsServer`, `LocalMediaServer`, or local media production wiring changes and a macOS/simulator target is available. If unavailable, record the availability issue and rely on the host loopback suites for LAN-001 closure; do not mark it as real mDNS evidence.

Named gates:

```bash
./scripts/run_test_gates.sh 1to1
```

Run when shared 1:1 send, retry, upload, listener, inbox, or conversation media entry points change.

```bash
./scripts/run_test_gates.sh baseline
```

Run when production Flutter bootstrap or broad production wiring changes.

```bash
FLUTTER_DEVICE_ID=<device-id> ./scripts/run_test_gates.sh transport
```

Run only if bootstrap, app resume, reconnect, bridge, or transport fallback wiring changes. This is companion transport confidence, not real mDNS proof.

```bash
./scripts/run_test_gates.sh completeness-check
```

Run only if `Test-Flight-Improv/test-gate-definitions.md` or gate classification changes.

Always finish code edits with:

```bash
git diff --check
```

## known-failure interpretation

- The current worktree is dirty with many pre-existing changes. Do not attribute unrelated failures to LAN-001 without a failing diff-local proof.
- `Test-Flight-Improv/test-gate-definitions.md` records the latest `completeness-check` attempt on 2026-05-28 as failing `747/750` due to three pre-existing unmatched files: `test/l10n/l10n_integrity_test.dart`, `test/shared/fakes/fake_group_pubsub_network_test.dart`, and `test/shared/fakes/seeded_group_reproduction_log_test.dart`. If unchanged by LAN-001, this remains a known pre-existing gate-doc issue.
- Simulator runs with `DISABLE_LOCAL_DISCOVERY=true` showing zero WiFi/local are neutral for LAN-001 and cannot be used as mDNS failure evidence.
- A missing physical-device target is not a LAN-001 blocker unless the executor intentionally adds a device-bound closure requirement. Real mDNS proof is LAN-002.

## done criteria

- All required LAN-001 source requirements in the closure bar are mapped to a green direct test, repaired direct test, or explicit accepted difference.
- No real mDNS, two-device, or Local Network permission prompt claim is made for LAN-001.
- Sender-side local success persists `local`; fallback successes persist direct, relay, or inbox and never false `local`.
- Receiver-side local messages and media record WiFi/local transport metrics without changing user-visible rendering semantics.
- Local media local-first behavior and relay upload fallback both remain intact.
- LAN diagnostics remain aggregate and privacy-safe.
- Required direct tests and relevant named gates have been run, or any skipped companion gate has a documented reason consistent with this plan.
- `git diff --check` passes after code edits.
- LAN-003 remains the owner for final matrix/closure-doc updates unless this session adds a new test classification.

## scope guard

Do not do any of the following in LAN-001:

- Do not run or require true physical-device mDNS acceptance as closure.
- Do not broaden into group messaging, NAT traversal, DCUtR, relay springboard, or cross-network direct-delivery policy.
- Do not redesign local WebSocket encryption, metadata exposure, Noise/TLS, or LAN identity challenge behavior.
- Do not change final closure docs or test matrix language except for a narrowly required gate classification.
- Do not widen named gates just to include every new direct test.
- Do not change user-facing settings UX beyond preserving aggregate diagnostics.
- Do not revert unrelated dirty worktree changes.

## accepted differences / intentionally out of scope

- Real Bonjour/mDNS same-WiFi selection on two physical devices is deferred to LAN-002.
- Actual iOS Local Network permission dialog behavior is not proven by host tests. LAN-001 proves only the aggregate suspected-denied diagnostic heuristic and disabled-discovery fallback behavior.
- `integration_test/wifi_transport_test.dart` is loopback local WebSocket/media confidence. It is intentionally not accepted as mDNS discovery proof.
- Final product-closure wording and matrix updates are deferred to LAN-003.

## dependency impact

- LAN-002 depends on LAN-001 host contracts being green or explicitly classified; otherwise device evidence could mask a host fallback or labeling regression.
- LAN-003 depends on LAN-001 and LAN-002 outcomes before updating closure docs and test matrices.
- If LAN-001 discovers that a host seam is already fully covered and green, later sessions can proceed without new production code from LAN-001.
- If LAN-001 exposes a real mDNS-only failure, stop LAN-001 implementation and move that evidence to LAN-002 rather than adding host-only workarounds.

## regression contract

Any LAN-001 change must preserve:

- Existing 1:1 direct, relay, relay-probe, and inbox delivery behavior.
- Existing pending-message and wire-envelope persistence contracts.
- Existing media upload, pending attachment, and local playback behavior.
- Existing transport label semantics: outbound local success is `local`, inbound local receive is `wifi`, fallback is not `local`.
- Existing diagnostics privacy boundaries.
- Existing simulator reset behavior that disables local discovery for standard simulator runs.

## reviewer outcome

- Sufficiency: sufficient with minor adjustments already applied.
- Missing files, tests, or gates: no structural omissions. The direct host suites cover local send/fallback, TTL, loopback WS, local media, receiver-side `wifi` labeling, metrics, and diagnostics. `integration_test/wifi_transport_test.dart` is correctly classified as loopback/device-bound companion evidence, not mDNS proof.
- Simulator/reliability gate: no `$run-flutter-reliability-sims` closure gate is required for LAN-001. Standard simulator setup disables local discovery, so forcing a reliability-sim gate would overclaim or misclassify the LAN proof. LAN-002 owns real mDNS acceptance.
- Stale assumptions: none found. Current code/tests remain the source of truth and the dirty worktree warning is explicit.
- Overengineering: none found. The plan forbids LAN encryption redesign, group/NAT/DCUtR work, and gate widening.
- Decomposition: narrow enough for implementation because it names exact production seams, exact tests, stop conditions, and accepted deferrals.
- Minimum needed: arbiter pass only.

## arbiter outcome

- Structural blockers: none.
- Incremental details: executor may choose whether to run the `integration_test/wifi_transport_test.dart` loopback companion based on local target availability and touched files, but must document any skip.
- Accepted differences: physical mDNS, real iOS Local Network permission prompt behavior, and final matrix/closure docs are intentionally out of LAN-001 scope.
- Stop rule: no structural blocker remains, so planning stops here.

## Execution Progress

- 2026-05-29T21:50:30Z - Executor LAN-001 intake started. Files inspected/touched: `Test-Flight-Improv/49-lan-wifi-delivery-reliability-session-LAN-001-plan.md`, `Test-Flight-Improv/49-lan-wifi-delivery-reliability-session-breakdown.md`, `Test-Flight-Improv/49-lan-wifi-delivery-reliability.md`, `git status --short`, `git diff --stat`. Command: none running. Decision/blocker: scope confirmed as LAN-001 host/loopback validation only; existing dirty worktree is broad and pre-existing, including local discovery/P2P/diagnostics test files and docs. Next action: inspect LAN-001 implementation and direct-test files before deciding whether code changes are needed.
- 2026-05-29T21:50:53Z - Executor inspection completed. Files inspected/touched: `lib/core/local_discovery/`, `lib/core/services/p2p_service.dart`, `lib/core/services/p2p_service_impl.dart`, `lib/core/debug/transport_metrics.dart`, `lib/main.dart`, `lib/features/conversation/application/send_chat_message_use_case.dart`, `lib/features/conversation/presentation/screens/conversation_wired.dart`, `lib/features/settings/presentation/widgets/settings_transport_diagnostics_card.dart`, required LAN-001 direct test files, `integration_test/wifi_transport_test.dart`, `reset_simulators.sh`, platform manifest files. Command: none running. Decision/blocker: required LAN-001 seams and regression files appear present; no code change selected before validation. Next action: run required direct tests and classify failures before any repair.
- 2026-05-29T21:51:10Z - Direct test 1 started. Files inspected/touched: `test/features/conversation/application/send_chat_message_use_case_test.dart`. Command: `flutter test test/features/conversation/application/send_chat_message_use_case_test.dart`. Decision/blocker: validating local text send, discover-on-send, stale/absent/non-LAN fallback before edits. Next action: record outcome and classify any failure.
- 2026-05-29T21:51:37Z - Direct test 1 failed during load. Files inspected/touched: `test/features/conversation/application/send_chat_message_use_case_test.dart`, `lib/core/services/p2p_service.dart`. Command: `flutter test test/features/conversation/application/send_chat_message_use_case_test.dart` exited 1. Decision/blocker: required suite cannot compile because local test fakes implementing `P2PService` are missing `lastKnownGoodTransport` and `recordSuccessfulTransport`; classified as related required test-harness seam failure in the dirty pre-existing code under LAN-001 validation. Next action: inspect interface implementers and apply the smallest fake-only repair before rerunning this suite.
- 2026-05-29T21:52:24Z - Direct test 1 rerun started. Files inspected/touched: `test/features/conversation/application/send_chat_message_use_case_test.dart`, `lib/core/services/p2p_service.dart`. Command: `flutter test test/features/conversation/application/send_chat_message_use_case_test.dart`. Decision/blocker: current file inspection shows the reported fake classes already include the required interface methods, so rerun before making a duplicate patch in the shared dirty workspace. Next action: record current outcome and classify if still failing.
- 2026-05-29T21:52:42Z - Direct test 1 rerun passed. Files inspected/touched: `test/features/conversation/application/send_chat_message_use_case_test.dart`. Command: `flutter test test/features/conversation/application/send_chat_message_use_case_test.dart` exited 0, `00:00 +72: All tests passed!`. Decision/blocker: current code satisfies local text send, discover-on-send, stale/absent/non-LAN fallback proof; initial load failure is non-reproducible after current file inspection and classified as dirty-worktree/test-cache transient rather than a remaining LAN-001 blocker. Next action: run resilience fallback direct tests.
- 2026-05-29T21:52:55Z - Direct test 2 started. Files inspected/touched: `test/core/resilience/f1_wifi_relay_fallback_test.dart`, `test/core/resilience/f2_transport_switch_recovery_test.dart`. Command: `flutter test test/core/resilience/f1_wifi_relay_fallback_test.dart test/core/resilience/f2_transport_switch_recovery_test.dart`. Decision/blocker: validating WiFi/local loss and fallback transition contracts. Next action: record outcome and classify any failure.
- 2026-05-29T21:53:20Z - Direct test 2 passed. Files inspected/touched: `test/core/resilience/f1_wifi_relay_fallback_test.dart`, `test/core/resilience/f2_transport_switch_recovery_test.dart`. Command: `flutter test test/core/resilience/f1_wifi_relay_fallback_test.dart test/core/resilience/f2_transport_switch_recovery_test.dart` exited 0, `00:05 +8: All tests passed!`. Decision/blocker: WiFi/local to relay/direct/inbox fallback contracts remain green; no blocker. Next action: run local discovery, local WebSocket, and local media host suites.
- 2026-05-29T21:53:32Z - Direct test 3 started. Files inspected/touched: `test/core/local_discovery/local_peer_ttl_test.dart`, `test/core/local_discovery/local_p2p_service_test.dart`, `test/core/local_discovery/local_ws_integration_i1_i2_test.dart`, `test/core/local_discovery/local_media_server_test.dart`, `test/core/local_discovery/local_media_integration_test.dart`. Command: `flutter test test/core/local_discovery/local_peer_ttl_test.dart test/core/local_discovery/local_p2p_service_test.dart test/core/local_discovery/local_ws_integration_i1_i2_test.dart test/core/local_discovery/local_media_server_test.dart test/core/local_discovery/local_media_integration_test.dart`. Decision/blocker: validating TTL, local P2P delegation, loopback WS ack/timeout/stale host, and local media transfer/persistence. Next action: record outcome and classify any failure.
- 2026-05-29T21:54:01Z - Direct test 3 passed. Files inspected/touched: `test/core/local_discovery/local_peer_ttl_test.dart`, `test/core/local_discovery/local_p2p_service_test.dart`, `test/core/local_discovery/local_ws_integration_i1_i2_test.dart`, `test/core/local_discovery/local_media_server_test.dart`, `test/core/local_discovery/local_media_integration_test.dart`. Command: `flutter test test/core/local_discovery/local_peer_ttl_test.dart test/core/local_discovery/local_p2p_service_test.dart test/core/local_discovery/local_ws_integration_i1_i2_test.dart test/core/local_discovery/local_media_server_test.dart test/core/local_discovery/local_media_integration_test.dart` exited 0, `00:02 +53: All tests passed!`. Decision/blocker: TTL, loopback local WS, stale-host recovery, and local media host contracts are green; no blocker. Next action: run P2P service local media, LAN availability, census, and latency suites.
- 2026-05-29T21:54:14Z - Direct test 4 started. Files inspected/touched: `test/core/services/p2p_service_inbound_transport_test.dart`, `test/core/services/p2p_service_local_media_wiring_test.dart`, `test/core/services/p2p_service_lan_availability_test.dart`, `test/core/services/p2p_service_transport_census_test.dart`, `test/core/services/p2p_service_transport_latency_test.dart`. Command: `flutter test test/core/services/p2p_service_inbound_transport_test.dart test/core/services/p2p_service_local_media_wiring_test.dart test/core/services/p2p_service_lan_availability_test.dart test/core/services/p2p_service_transport_census_test.dart test/core/services/p2p_service_transport_latency_test.dart`. Decision/blocker: validating P2P inbound WiFi/local classification, local media production wiring, aggregate LAN availability, and metrics census/latency. Next action: record outcome and classify any failure.
- 2026-05-29T21:54:33Z - Direct test 4 passed. Files inspected/touched: `test/core/services/p2p_service_inbound_transport_test.dart`, `test/core/services/p2p_service_local_media_wiring_test.dart`, `test/core/services/p2p_service_lan_availability_test.dart`, `test/core/services/p2p_service_transport_census_test.dart`, `test/core/services/p2p_service_transport_latency_test.dart`. Command: `flutter test test/core/services/p2p_service_inbound_transport_test.dart test/core/services/p2p_service_local_media_wiring_test.dart test/core/services/p2p_service_lan_availability_test.dart test/core/services/p2p_service_transport_census_test.dart test/core/services/p2p_service_transport_latency_test.dart` exited 0, `00:00 +27: All tests passed!`. Decision/blocker: P2P inbound WiFi/local classification, production local media wiring, aggregate LAN availability, census, and latency proofs are green; no blocker. Next action: run transport metrics aggregate/privacy suites.
- 2026-05-29T21:54:47Z - Direct test 5 started. Files inspected/touched: `test/core/debug/transport_metrics_test.dart`, `test/core/debug/transport_metrics_privacy_test.dart`. Command: `flutter test test/core/debug/transport_metrics_test.dart test/core/debug/transport_metrics_privacy_test.dart`. Decision/blocker: validating aggregate LAN metrics, suspected-denied flag rendering in reports, and privacy boundaries. Next action: record outcome and classify any failure.
- 2026-05-29T21:55:15Z - Direct test 5 passed. Files inspected/touched: `test/core/debug/transport_metrics_test.dart`, `test/core/debug/transport_metrics_privacy_test.dart`. Command: `flutter test test/core/debug/transport_metrics_test.dart test/core/debug/transport_metrics_privacy_test.dart` exited 0, `00:00 +35: All tests passed!`. Decision/blocker: aggregate metrics, LAN suspected-denied reporting, and privacy boundaries are green; no blocker. Next action: run settings diagnostics widget suite.
- 2026-05-29T21:55:27Z - Direct test 6 started. Files inspected/touched: `test/features/settings/presentation/widgets/settings_transport_diagnostics_card_test.dart`. Command: `flutter test test/features/settings/presentation/widgets/settings_transport_diagnostics_card_test.dart`. Decision/blocker: validating settings transport diagnostics card aggregate rendering and suspected-denied state. Next action: record outcome and classify any failure.
- 2026-05-29T21:55:58Z - Direct test 6 passed. Files inspected/touched: `test/features/settings/presentation/widgets/settings_transport_diagnostics_card_test.dart`. Command: `flutter test test/features/settings/presentation/widgets/settings_transport_diagnostics_card_test.dart` exited 0, `00:00 +3: All tests passed!`. Decision/blocker: settings diagnostics card aggregate and suspected-denied rendering proof is green; no blocker. Next action: record conditional companion/gate decisions and final diff-check decision.
- 2026-05-29T21:56:15Z - Conditional companion/gate decisions recorded; diff check started. Files inspected/touched: plan progress only. Command: `git diff --check`. Decision/blocker: no Executor production or test-code edits were made, so `flutter test -d macos integration_test/wifi_transport_test.dart`, `./scripts/run_test_gates.sh 1to1`, `./scripts/run_test_gates.sh baseline`, `FLUTTER_DEVICE_ID=<device-id> ./scripts/run_test_gates.sh transport`, and `./scripts/run_test_gates.sh completeness-check` are not triggered by this pass; running `git diff --check` as a hygiene check despite doc-only progress edits. Next action: record diff-check outcome.
- 2026-05-29T21:56:44Z - Executor LAN-001 pass completed. Files inspected/touched: required LAN-001 implementation and test files, `git status --short`, progress entries in this plan. Command: `git diff --check` exited 0. Decision/blocker: no code/test changes were made by this Executor; current code/tests already satisfy LAN-001 host/loopback proof based on the required green direct suites. Final status remains broadly dirty with pre-existing/unrelated worktree changes; no LAN-001 blocker. Next action: hand off to separate QA Reviewer; do not execute QA, LAN-002, LAN-003, closure docs, or physical-device mDNS proof in this pass.
- 2026-05-29T21:57:21Z - QA Reviewer spawn requested. Files inspected/touched: plan progress, `/tmp/lan001-executor-result.txt`. Command: none running. Decision/blocker: Executor produced trustworthy evidence and no code/test delta beyond progress entries; spawn separate QA Reviewer with `model: gpt-5.5` and `reasoning_effort: xhigh`. Next action: wait for QA sufficiency review.
- 2026-05-29T21:57:59Z - QA Reviewer spawned/running. Files inspected/touched: plan progress only. Command: `codex --ask-for-approval never --sandbox danger-full-access --cd ... --model gpt-5.5 -c model_reasoning_effort="xhigh" exec -o /tmp/lan001-qa-result.txt -`. Decision/blocker: fresh QA Reviewer process is running. Next action: wait for QA result and inspect findings.
- 2026-05-29T21:49:00Z - Controller contract extraction started. Files inspected/touched: `Test-Flight-Improv/49-lan-wifi-delivery-reliability-session-LAN-001-plan.md`, `git status --short`. Command: none running. Decision/blocker: current run is scoped to LAN-001 only; dirty worktree has many pre-existing changes. Next action: extract LAN-001 scope, proof requirements, tests, conditional gates, done criteria, and non-goals.
- 2026-05-29T21:49:00Z - Controller contract extraction completed. Files inspected/touched: plan artifact only. Command: none running. Decision/blocker: host/loopback LAN delivery proof required; physical-device Bonjour/mDNS proof remains LAN-002; final matrix/docs remain LAN-003; no contract blocker. Next action: spawn fresh Executor with `model: gpt-5.5` and `reasoning_effort: xhigh`.
- 2026-05-29T21:49:36Z - Executor spawn retry prepared. Files inspected/touched: plan artifact only. Command: prior `codex exec --model gpt-5.5 -c model_reasoning_effort="xhigh" ... --ask-for-approval never` failed before child work because option placement was rejected. Decision/blocker: no Executor work materialized; retry with global option placement and same model/reasoning settings. Next action: spawn Executor.
- 2026-05-29T21:50:08Z - Executor spawned/running. Files inspected/touched: progress artifact only. Command: `codex --ask-for-approval never --sandbox danger-full-access --cd ... --model gpt-5.5 -c model_reasoning_effort="xhigh" exec -o /tmp/lan001-executor-result.txt -`. Decision/blocker: fresh Executor process is running. Next action: wait for Executor result and inspect evidence.
- 2026-05-29T21:47:16Z - Contract extraction started. Files inspected/touched: plan artifact, `git status --short`. Command: none running. Decision/blocker: executing LAN-001 only; no blocker. Next action: extract exact scope, proof profile, tests, gates, done criteria, and scope guard.
- 2026-05-29T21:47:16Z - Contract extraction completed. Files inspected/touched: plan artifact. Command: none running. Decision/blocker: host/loopback proof only; physical-device mDNS deferred to LAN-002; exact direct tests and conditional gates identified. Next action: spawn Executor with LAN-001 contract.
- 2026-05-29T21:47:29Z - Executor spawn requested. Files inspected/touched: progress artifact only. Command: none running. Decision/blocker: delegate implementation/verification pass to fresh Executor using `model: gpt-5.5`, `reasoning_effort: xhigh`. Next action: wait for Executor result.
- 2026-05-29T23:58:05+02:00 - QA Reviewer LAN-001 pass started. Files inspected/touched: `/Users/I560101/.codex/skills/implementation-execution-qa-orchestrator/SKILL.md`, `Test-Flight-Improv/49-lan-wifi-delivery-reliability-session-LAN-001-plan.md`. Commands finished: `sed -n '1,260p' /Users/I560101/.codex/skills/implementation-execution-qa-orchestrator/SKILL.md`; `sed -n '1,260p' Test-Flight-Improv/49-lan-wifi-delivery-reliability-session-LAN-001-plan.md`; `date '+%Y-%m-%d %H:%M:%S %Z'`; `rg -n "^## Execution Progress|^## " Test-Flight-Improv/49-lan-wifi-delivery-reliability-session-LAN-001-plan.md`; `sed -n '260,620p' /Users/I560101/.codex/skills/implementation-execution-qa-orchestrator/SKILL.md`; `sed -n '260,520p' Test-Flight-Improv/49-lan-wifi-delivery-reliability-session-LAN-001-plan.md`. Command currently running: none. Decision/blocker: QA role, LAN-001 host/loopback scope, conditional gate triggers, done criteria, and physical-device mDNS deferral extracted; no blocker. Next action: inspect Executor result, current status, and LAN-001 diff evidence before accepting or rejecting execution sufficiency.
- 2026-05-29T23:59:20+02:00 - QA Reviewer LAN-001 pass completed. Files inspected/touched: `Test-Flight-Improv/49-lan-wifi-delivery-reliability-session-LAN-001-plan.md`, `/tmp/lan001-executor-result.txt`, `git status --short`, `git diff -- Test-Flight-Improv/49-lan-wifi-delivery-reliability-session-LAN-001-plan.md`, `git ls-files --stage/--others -- Test-Flight-Improv/49-lan-wifi-delivery-reliability-session-LAN-001-plan.md`, required LAN-001 direct test files by narrow `rg`, `Test-Flight-Improv/49-lan-wifi-delivery-reliability-session-breakdown.md`, `Test-Flight-Improv/49-lan-wifi-delivery-reliability.md`. Commands finished: executor result read exited 0; status and plan diff checks exited 0; required-test `rg` evidence scans exited 0; orientation doc reads exited 0; pre-execution status snapshot comparison exited 1 only because unrelated `?? Test-Flight-Improv/100-nat-traversal-dcutr-evidence-session-DCUTR-003-plan.md` is now present outside LAN-001. Command currently running: none. Decision/blocker: no LAN-001 blocking issue found; direct-test evidence accepted; initial required-test load failure was triaged before any patch and passed on rerun without code repair, so it is not a remaining blocker; conditional companion/named-gate skips are consistent with no Executor production/test-code or gate-classification edits; physical-device mDNS remains LAN-002. Next action: hand compact QA result back to controller; do not fix code, close LAN-002/LAN-003, or claim real mDNS proof.
- 2026-05-29T22:00:08Z - Final execution verdict written. Files inspected/touched: plan progress and final verdict sections. Command: none running. Decision/blocker: QA found no blocking issues; sufficiency rule met for LAN-001 host/loopback scope; no fix pass required. Next action: report final accepted execution result.

## Final verdict

`accepted`

LAN-001 execution is accepted for host/loopback local-delivery, fallback, media,
and aggregate diagnostics proof. This does not claim physical-device
Bonjour/mDNS proof, which remains LAN-002.

## Final plan

Use the plan above as the LAN-001 execution contract. It is scoped to host/loopback local-delivery and fallback evidence, with physical mDNS proof deferred to LAN-002 and final closure docs deferred to LAN-003.

## Structural blockers remaining

None.

## Incremental details intentionally deferred

- Whether to run `flutter test -d macos integration_test/wifi_transport_test.dart` depends on touched local WS/media files and local Flutter target availability.
- `./scripts/run_test_gates.sh transport` is required only if bootstrap, resume, reconnect, bridge, or broader transport fallback wiring changes.
- `./scripts/run_test_gates.sh completeness-check` is required only if gate classifications change.

## Accepted differences intentionally left unchanged

- LAN-002 owns true physical-device same-WiFi mDNS acceptance.
- LAN-001 proves only host/loopback mechanics and aggregate diagnostics, not actual iOS Local Network permission prompt behavior.
- LAN-003 owns final matrix and closure-doc updates.

## Exact docs/files used as evidence

- `Test-Flight-Improv/49-lan-wifi-delivery-reliability-session-breakdown.md`
- `Test-Flight-Improv/49-lan-wifi-delivery-reliability.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `scripts/run_test_gates.sh`
- Production and test files listed in `files and repos to inspect next`.

## Why the plan is safe or unsafe to implement now

Safe to implement now. The plan has a narrow source row, a concrete host/loopback proof profile, exact files and tests, explicit named-gate triggers, a dirty-worktree guard, accepted LAN-002/LAN-003 deferrals, and no remaining structural blocker.
