What's there

  Integration test files

  ┌────────────────────────────────┬─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
  │              File              │                                                                          What it tests                                                                          │
  ├────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ smoke_test.dart                │ Identity generation, DI stack, startup router                                                                                                                   │
  ├────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ conversation_bridge_test.dart  │ Real Go bridge → P2PService → DB send path, inbox fallback                                                                                                      │
  ├────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ wifi_transport_test.dart       │ 9 WiFi/WebSocket scenarios (F1–F9): send/receive, ack timeout, pool reuse, idle disconnect, bidirectional, malformed, concurrent, max connections, remote close │
  ├────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ background_reconnect_test.dart │ Real device background→foreground: relay disconnect → handleAppResumed() → circuit recovery                                                                     │
  ├────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ feed_performance_test.dart     │ UI frame timing: scroll, expand/collapse, swipe-to-quote, compose input                                                                                         │
  ├────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ transport_e2e_test.dart        │ The big one — 30+ scenarios coordinated with the Go CLI peer                                                                                                    │
  └────────────────────────────────┴─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘

  transport_e2e_test.dart scenario map

  ┌─────────────┬───────┬────────────────────────────────────────────────────────────┬──────────────────────────┐
  │   Series    │  ID   │                          Scenario                          │     Needs CLI peer?      │
  ├─────────────┼───────┼────────────────────────────────────────────────────────────┼──────────────────────────┤
  │ A – Relay   │ A1    │ Send v1 plaintext                                          │ yes                      │
  ├─────────────┼───────┼────────────────────────────────────────────────────────────┼──────────────────────────┤
  │             │ A2    │ Receive v1 plaintext                                       │ yes                      │
  ├─────────────┼───────┼────────────────────────────────────────────────────────────┼──────────────────────────┤
  │             │ A3    │ Bidirectional send+receive                                 │ yes                      │
  ├─────────────┼───────┼────────────────────────────────────────────────────────────┼──────────────────────────┤
  │             │ A4    │ Send v2 encrypted                                          │ yes                      │
  ├─────────────┼───────┼────────────────────────────────────────────────────────────┼──────────────────────────┤
  │             │ A5    │ Receive v2 encrypted                                       │ yes                      │
  ├─────────────┼───────┼────────────────────────────────────────────────────────────┼──────────────────────────┤
  │             │ A6    │ Fast path (already connected)                              │ yes                      │
  ├─────────────┼───────┼────────────────────────────────────────────────────────────┼──────────────────────────┤
  │ B – Inbox   │ B1    │ Send to offline peer (fallback)                            │ no (self-contained)      │
  ├─────────────┼───────┼────────────────────────────────────────────────────────────┼──────────────────────────┤
  │             │ B2    │ Inbox message from CLI                                     │ yes                      │
  ├─────────────┼───────┼────────────────────────────────────────────────────────────┼──────────────────────────┤
  │             │ B3    │ 5 inbox messages                                           │ yes                      │
  ├─────────────┼───────┼────────────────────────────────────────────────────────────┼──────────────────────────┤
  │             │ B4    │ Inbox cleared after retrieval                              │ yes                      │
  ├─────────────┼───────┼────────────────────────────────────────────────────────────┼──────────────────────────┤
  │             │ B5    │ Unknown sender dropped                                     │ yes                      │
  ├─────────────┼───────┼────────────────────────────────────────────────────────────┼──────────────────────────┤
  │             │ B6    │ 60 inbox messages + multi-drain                            │ yes                      │
  ├─────────────┼───────┼────────────────────────────────────────────────────────────┼──────────────────────────┤
  │             │ B7    │ At-most-once semantics                                     │ documented only          │
  ├─────────────┼───────┼────────────────────────────────────────────────────────────┼──────────────────────────┤
  │ C – Drop    │ C1    │ Connection drop → inbox fallback                           │ yes (CLI stops mid-test) │
  ├─────────────┼───────┼────────────────────────────────────────────────────────────┼──────────────────────────┤
  │ D – Dedup   │ D3    │ Different messages, same content                           │ yes                      │
  ├─────────────┼───────┼────────────────────────────────────────────────────────────┼──────────────────────────┤
  │             │ D4    │ Cross-transport dedup (relay+inbox)                        │ yes                      │
  ├─────────────┼───────┼────────────────────────────────────────────────────────────┼──────────────────────────┤
  │ E – Edge    │ E1    │ Large message (100KB+)                                     │ yes                      │
  ├─────────────┼───────┼────────────────────────────────────────────────────────────┼──────────────────────────┤
  │             │ E3    │ Quote-reply                                                │ yes                      │
  ├─────────────┼───────┼────────────────────────────────────────────────────────────┼──────────────────────────┤
  │             │ E4    │ Rapid fire (10 messages)                                   │ yes                      │
  ├─────────────┼───────┼────────────────────────────────────────────────────────────┼──────────────────────────┤
  │             │ E6    │ Malformed envelope (no crash)                              │ yes                      │
  ├─────────────┼───────┼────────────────────────────────────────────────────────────┼──────────────────────────┤
  │             │ E7    │ Tampered v2 (no crash, no persist)                         │ yes                      │
  ├─────────────┼───────┼────────────────────────────────────────────────────────────┼──────────────────────────┤
  │ G – CLI ops │ G1–G5 │ status, encrypted inbox, retrieve, clear, restore_identity │ yes                      │
  └─────────────┴───────┴────────────────────────────────────────────────────────────┴──────────────────────────┘

  CLI test peer (go-mknoon/cmd/testpeer/)

  Headless Go process, stdin/stdout JSON protocol. 14+ commands: generate_identity, restore_identity, mlkem_keygen, start, stop, status, wait_relay, wait_circuit, register, discover, dial, send_v1, send_v2, send_raw, inbox_store_*,
  inbox_retrieve, get_messages, wait_message, clear_messages.

  The orchestrator is integration_test/scripts/run_transport_e2e.dart — it builds the CLI peer, starts it, exchanges fixture files (/tmp/cli_peer_fixture.json, /tmp/flutter_peer_fixture.json), launches flutter drive, runs scenarios, and
   does post-Flutter verification of what the CLI peer received.

  ---
  What's missing

  Missing from the E2E transport matrix

  ┌─────────────────────────────────────────────────┬──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
  │                       Gap                       │                                                                              Why it matters                                                                              │
  ├─────────────────────────────────────────────────┼──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ A7 – Rendezvous discovery E2E                   │ Dial uses hard-coded fixture addresses. Never exercises rendezvous:discover → peer:dial as the real app does for first contact.                                          │
  ├─────────────────────────────────────────────────┼──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ A8 – Relay reconnect E2E (Finding 1 regression) │ background_reconnect_test.dart does reconnect but doesn't verify the second reconnect cycle (AutoRegister preserved). No E2E equivalent of the unit tests we just wrote. │
  ├─────────────────────────────────────────────────┼──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ B – Inbox store v2 encrypted from Flutter       │ B1 stores plaintext to inbox. No scenario where Flutter sends a v2-encrypted message to an offline peer's inbox.                                                         │
  ├─────────────────────────────────────────────────┼──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ C2 – Relay crash (not just peer disconnect)     │ C1 disconnects the CLI peer. No scenario where the relay server itself becomes unreachable then recovers — the critical real-world failure mode.                         │
  ├─────────────────────────────────────────────────┼──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ C3 – Network transition (WiFi→cellular)         │ The unit test (2.2) covers it with fakes. No real-device E2E test that switches connectivity.                                                                            │
  ├─────────────────────────────────────────────────┼──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ D1/D2 – Duplicate relay messages                │ D3/D4 test different-content and cross-transport. No test for exact duplicate (same message ID arriving twice via relay).                                                │
  ├─────────────────────────────────────────────────┼──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ E2 – Empty/zero-length message                  │ E1 tests large. Nothing tests boundary "".                                                                                                                               │
  ├─────────────────────────────────────────────────┼──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ E5 – Unicode / RTL / emoji stress               │ Only ASCII text in test payloads.                                                                                                                                        │
  ├─────────────────────────────────────────────────┼──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ E8 – Media attachment E2E                       │ media:upload / media:download commands exist on the bridge but aren't exercised.                                                                                         │
  ├─────────────────────────────────────────────────┼──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ F (WiFi) – WiFi + Relay fallback E2E            │ wifi_transport_test.dart tests WiFi in isolation with a local WebSocket. No test where WiFi discovery finds a local peer and falls back to relay when WiFi drops.        │
  ├─────────────────────────────────────────────────┼──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ G6 – Profile upload/download                    │ Commands exist but not tested.                                                                                                                                           │
  └─────────────────────────────────────────────────┴──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘

  Missing from the test infrastructure

  ┌──────────────────────────────────┬──────────────────────────────────────────────────────────────────────────────────────┐
  │               Gap                │                                        Impact                                        │
  ├──────────────────────────────────┼──────────────────────────────────────────────────────────────────────────────────────┤
  │ No CI integration                │ No GitHub Actions workflow, no Makefile target for the full E2E. Manual-only.        │
  ├──────────────────────────────────┼──────────────────────────────────────────────────────────────────────────────────────┤
  │ No Android E2E path              │ Orchestrator hardcodes flutter drive for iOS simulator. No Android emulator variant. │
  ├──────────────────────────────────┼──────────────────────────────────────────────────────────────────────────────────────┤
  │ No timeout/retry in orchestrator │ If relay is slow (>60s), the orchestrator fails permanently. No retry with backoff.  │
  ├──────────────────────────────────┼──────────────────────────────────────────────────────────────────────────────────────┤
  │ No test isolation                │ Fixture files in /tmp/ clash if two runs overlap. No unique temp dir per run.        │
  ├──────────────────────────────────┼──────────────────────────────────────────────────────────────────────────────────────┤
  │ Signal files are fragile         │ /tmp/e2e_cli_stopped, /tmp/e2e_c1_sent — race-prone. No cleanup on abort.            │
  └──────────────────────────────────┴──────────────────────────────────────────────────────────────────────────────────────┘

  ---
  How to run it

  Prerequisites

  # 1. Go toolchain + gomobile (for building the bridge)
  # 2. Flutter SDK
  # 3. iOS Simulator booted (or device connected)
  # 4. Relay server reachable (mknoun.xyz)

  Individual integration tests (no CLI peer needed)

  # Smoke test
  flutter test integration_test/smoke_test.dart

  # Conversation bridge (uses real Go bridge — needs native build)
  flutter drive --driver=test_driver/integration_test.dart \
    --target=integration_test/conversation_bridge_test.dart

  # WiFi transport (local WebSocket only)
  flutter test integration_test/wifi_transport_test.dart

  # Feed performance
  flutter drive --driver=test_driver/integration_test.dart \
    --target=integration_test/feed_performance_test.dart

  # Background reconnect (needs real relay)
  flutter drive --driver=test_driver/integration_test.dart \
    --target=integration_test/background_reconnect_test.dart

  Full E2E transport suite (Flutter + CLI peer)

  # 1. Build the Go bridge (if not already done)
  cd go-mknoon && make all && cd ../ios && pod install && cd ..

  # 2. Build the CLI test peer
  cd go-mknoon && make testpeer && cd ..

  # 3. Run the orchestrator (builds testpeer, starts CLI peer, launches flutter drive)
  dart integration_test/scripts/run_transport_e2e.dart

  The orchestrator does everything:
  1. make testpeer → builds go-mknoon/bin/testpeer
  2. Spawns testpeer process (stdin/stdout JSON)
  3. Generates CLI peer identity + ML-KEM keys
  4. Starts CLI node, waits for relay + circuit
  5. Registers on rendezvous
  6. Writes /tmp/cli_peer_fixture.json
  7. Launches flutter drive --target=integration_test/transport_e2e_test.dart
  8. Flutter writes /tmp/flutter_peer_fixture.json back
  9. Orchestrator runs A/B/C/D/E/G scenarios in parallel
  10. Post-Flutter: verifies CLI peer received expected messages
  11. Cleanup + combined exit code

  Go CLI peer tests (standalone)

  cd go-mknoon && go test ./cmd/testpeer/ -v

✻ Churned for 1m 58s