# Test Gate Definitions

Session 1 source of truth for named regression gates.

If this document and `scripts/run_test_gates.sh` ever disagree, the script wins.

## Session 1 Decisions

- Canonical loading-state baseline file: `integration_test/loading_states_smoke_test.dart`
- `test/features/loading_states_smoke_test.dart` stays out of the Baseline Gate. It is a lighter widget/render smoke, not the startup-wiring smoke.
- The 1:1 Reliability Gate stays at 9 tests.
- `test/features/conversation/integration/quote_reply_thread_test.dart` stays in the 1:1 gate because quoted-message persistence rides the same shared send/persist path that Session 2 and Session 3 will touch.
- `test/features/conversation/integration/emoji_reaction_exchange_test.dart` stays out of the 1:1 gate because it validates the reaction pipeline, not the shared durable send / retry / media / voice contract.
- `test/features/feed/presentation/screens/feed_wired_test.dart` now carries the Session 2 feed inline 1:1 parity regression as required companion direct coverage for feed-originated 1:1 send changes; it stays outside the frozen named gate lists.
- `test/features/groups/integration/announcement_happy_path_test.dart` carries the Session 6 announcement create/send/read-only/react regression and stays in the Optional / Manual direct-suite bucket so the frozen named gate lists do not widen.
- `test/features/groups/integration/group_startup_rejoin_smoke_test.dart` stays in the Group Messaging Gate, not Startup / Transport. It validates group-topic rejoin behavior with fake infrastructure rather than the real transport gate.
- `integration_test/multi_relay_failover_test.dart` stays nightly-only because it needs multi-relay runtime configuration and composes heavier real-stack coverage than the named transport gate.

## Bulk-Classification Policy

- Named gates use exact file paths only. No folder shorthands.
- The public gate command is always the script command. Internally, the script may split host-side `test/` files from `integration_test/` files and may fan out integration-backed files into separate `flutter test` invocations when the combined app launch is unreliable.
- Feature-local tests under `test/features/<feature>/application`, `domain`, `presentation`, `phase*`, `improvement`, and `regression` stay implicitly covered by direct feature-level runs unless they are explicitly named below.
- High-value integration, cross-feature, service, lifecycle, resilience, and orchestration suites must be classified intentionally, even when they stay outside the named gates.
- Red tests are not removed from a gate definition to make the gate look green. They stay documented as known failures until fixed.
- When adding a new integration, cross-feature, core-service, lifecycle, resilience, or orchestration test, classify it here and keep `./scripts/run_test_gates.sh completeness-check` green.

## Named Gates

### Baseline Gate

Run on every PR.

Command:

```bash
./scripts/run_test_gates.sh baseline
```

Files:

- `test/features/identity/presentation/screens/startup_router_recovery_test.dart`
- `test/features/qr_code/presentation/screens/qr_scanner_wired_test.dart`
- `test/features/conversation/integration/offline_inbox_roundtrip_test.dart`
- `integration_test/loading_states_smoke_test.dart`
- `integration_test/posts_phase1_fake_test.dart`
- `test/features/groups/integration/group_messaging_smoke_test.dart`

### 1:1 Reliability Gate

Run when shared 1:1 send, retry, upload, listener, inbox, or feed-originated 1:1 entry points change.

Command:

```bash
./scripts/run_test_gates.sh 1to1
```

Files:

- `test/features/conversation/integration/two_user_message_exchange_test.dart`
- `test/features/conversation/integration/offline_inbox_roundtrip_test.dart`
- `test/features/conversation/integration/media_attachment_flow_test.dart`
- `test/features/conversation/integration/media_retry_smoke_test.dart`
- `test/features/conversation/integration/voice_message_exchange_test.dart`
- `test/features/conversation/integration/incomplete_upload_recovery_test.dart`
- `test/features/conversation/integration/send_then_lock_delivery_test.dart`
- `test/features/conversation/integration/stuck_sending_recovery_test.dart`
- `test/features/conversation/integration/quote_reply_thread_test.dart`

### Feed / Surface Gate

Run when feed cards, feed composer, inline reply, or feed-to-conversation handoff changes.

Command:

```bash
./scripts/run_test_gates.sh feed
```

Files:

- `test/features/feed/integration/feed_card_flow_test.dart`
- `test/features/feed/integration/expanded_collapsed_card_test.dart`
- `test/features/feed/integration/feed_color_smoke_test.dart`

Required companion rule:

- If feed can enter the 1:1 send path, also run `./scripts/run_test_gates.sh 1to1`.

### Group Messaging Gate

Run when group send, receive, retry, resume, invite, or announcement behavior changes.

Command:

```bash
./scripts/run_test_gates.sh groups
```

Files:

- `test/features/groups/integration/group_messaging_smoke_test.dart`
- `test/features/groups/integration/group_resume_recovery_test.dart`
- `test/features/groups/integration/group_edge_cases_smoke_test.dart`
- `test/features/groups/integration/invite_round_trip_test.dart`
- `test/features/groups/integration/group_membership_smoke_test.dart`
- `test/features/groups/integration/group_startup_rejoin_smoke_test.dart`

Supplemental direct suite when invite or contact-entry flows are touched:

- `test/features/contact_request/integration/contact_request_flow_test.dart`

### Posts / Privacy Gate

Run when posts delivery, nearby presence, privacy filters, or replay behavior changes.

Command:

```bash
./scripts/run_test_gates.sh posts
```

Files:

- `integration_test/posts_phase1_fake_test.dart`
- `integration_test/posts_phase2_fake_test.dart`
- `integration_test/posts_phase3_fake_test.dart`
- `integration_test/posts_phase4_fake_test.dart`
- `integration_test/posts_phase5_fake_test.dart`
- `test/features/posts/phase3/post_presence_listener_test.dart`

### Startup / Transport Gate

Run when bridge, resume, reconnect, transport fallback, or app bootstrap changes.

Command:

```bash
./scripts/run_test_gates.sh transport
```

Files:

- `integration_test/background_reconnect_test.dart`
- `integration_test/wifi_relay_fallback_smoke_test.dart`
- `integration_test/transport_e2e_test.dart`
- `integration_test/media_stable_id_smoke_test.dart`

Raw device command when a specific simulator or device is required:

```bash
flutter test -d <device-id> \
  integration_test/background_reconnect_test.dart \
  integration_test/wifi_relay_fallback_smoke_test.dart \
  integration_test/transport_e2e_test.dart \
  integration_test/media_stable_id_smoke_test.dart
```

Optional script form with an explicit device:

```bash
FLUTTER_DEVICE_ID=<device-id> ./scripts/run_test_gates.sh transport
```

## Nightly / Release Pool

These stay outside the named gates because they are heavier, device-bound, env-bound, or real-stack confidence tests.

- `integration_test/smoke_test.dart`
- `integration_test/conversation_bridge_test.dart`
- `integration_test/wifi_transport_test.dart`
- `integration_test/voice_message_e2e_test.dart`
- `integration_test/group_recovery_e2e_test.dart`
- `integration_test/group_recovery_cli_e2e_test.dart`
- `integration_test/multi_relay_failover_test.dart`
- `integration_test/relay_chaos_soak_test.dart`
- `integration_test/soak_e2e_test.dart`
- `integration_test/bidi_text_smoke_test.dart`

## Optional / Manual Direct Suites

These are intentionally classified, but not promoted into the frozen named gates.

### Standalone High-Value Files

| File | Classification | Reason |
|------|----------------|--------|
| `test/features/groups/integration/announcement_happy_path_test.dart` | Optional / manual direct suite | Session 6 focused announcement create/send/read-only/react regression without widening frozen named gates |
| `test/features/conversation/integration/emoji_reaction_exchange_test.dart` | Optional / manual direct suite | Reaction pipeline coverage, not shared durable-send coverage |
| `test/features/contact_request/integration/contact_request_flow_test.dart` | Optional / manual direct suite | Contact bootstrap and acceptance flow; run with invite or onboarding entry work |
| `test/features/contact_request/integration/key_exchange_retry_flow_test.dart` | Optional / manual direct suite | Contact key-bootstrap retry logic, not a named gate member |
| `test/features/introduction/integration/intro_wiring_smoke_test.dart` | Optional / manual direct suite | Onboarding / introduction wiring |
| `test/features/introduction/integration/introduction_multi_node_test.dart` | Optional / manual direct suite | Multi-node introduction behavior |
| `test/features/introduction/integration/introduction_smoke_test.dart` | Optional / manual direct suite | Intro happy-path and edge-case behavior |
| `test/features/settings/integration/profile_picture_flow_test.dart` | Optional / manual direct suite | Profile media / broadcast / download flow |
| `test/features/share/integration/share_to_contact_smoke_test.dart` | Optional / manual direct suite | Share target routing and compose hydration |
| `test/integration/onboarding_golden_path_test.dart` | Optional / manual direct suite | Session 7 onboarding confidence flow spanning identity create, accepted contact request, and first 1:1 send without widening frozen named gates |
| `test/integration/notification_deeplink_integration_test.dart` | Optional / manual direct suite | Notification routing boundary; Session 4 work will harden this area |
| `test/integration/rapid_lock_unlock_integration_test.dart` | Optional / manual direct suite | Lifecycle retry edge case, narrower than the named gates |
| `test/integration/relay_down_degradation_integration_test.dart` | Optional / manual direct suite | 1:1 degradation and exact-once retry edge case |
| `integration_test/feed_performance_test.dart` | Optional / manual direct suite | Performance-only validation |
| `integration_test/identity_progress_performance_test.dart` | Optional / manual direct suite | Performance-only validation |

### Explicit Out-of-Gate File

| File | Classification | Reason |
|------|----------------|--------|
| `test/features/loading_states_smoke_test.dart` | Out of gate | Widget/render smoke only; keep the startup-wiring smoke canonical in `integration_test/` |

### Directory-Level Direct Suites

These directories are intentionally outside the named gates, but they are not accidental leftovers.

| Scope | Classification | Reason |
|------|----------------|--------|
| `test/core/services/*.dart` | Direct suite | Service, router, retrier, and orchestration coverage for the exact module being edited |
| `test/core/lifecycle/*.dart` | Direct suite | Pause/resume ordering and lifecycle hardening; kept separate so the transport gate stays bounded |
| `test/core/resilience/*.dart` | Direct suite | Deterministic chaos/failover coverage; broader than the frozen transport gate |
| `test/core/notifications/*.dart` | Direct suite | Notification route/dispatch helpers without promoting them into the baseline |
| `test/core/bridge/*.dart` | Direct suite | Bridge adapter and helper behavior |
| `test/core/database/*.dart` | Direct suite | Database helper and migration coverage |
| `test/core/inbox/*.dart` | Direct suite | Lower-level inbox behavior |
| `test/core/local_discovery/*.dart` | Direct suite | WiFi/local discovery support coverage |
| `test/core/media/*.dart` | Direct suite | Media helper and processing behavior |
| `test/core/secure_storage/*.dart` | Direct suite | Secure storage behavior |
| `test/core/constants/*.dart`, `test/core/theme/*.dart`, `test/core/utils/*.dart` | Direct suite | Component-level contracts, not gate members |
| `test/shared/widgets/*.dart` | Direct suite | Shared widget behavior |
| `test/unit/*.dart` | Direct suite | Unit-level leaf coverage |

## Completeness Check

Run after any gate edits:

```bash
./scripts/run_test_gates.sh completeness-check
```

Session 1 rule:

- Every `*_test.dart` file under `test/` and `integration_test/` must resolve to one of:
  - a named gate
  - the nightly / release pool
  - the optional / manual direct suites
  - the explicit out-of-gate list
  - an implicit feature-local or component direct-suite bucket described above

## Known Failures

Validation run date: 2026-03-25.

- Completeness check: `./scripts/run_test_gates.sh completeness-check` passed with `564/564` test files classified.
- Baseline Gate: host-side files passed. `integration_test/loading_states_smoke_test.dart` fails to build because `StartupRouter` now requires `postRepository`; see `integration_test/loading_states_smoke_test.dart:288` and `lib/features/identity/presentation/startup_router.dart:154`.
- Baseline Gate: `integration_test/posts_phase1_fake_test.dart` still ran and passed in the same integration invocation, but the gate remains red because of the loading-states build failure.
- 1:1 Reliability Gate: passed via `./scripts/run_test_gates.sh 1to1`.
- Feed / Surface Gate: passed via `./scripts/run_test_gates.sh feed`.
- Group Messaging Gate: passed via `./scripts/run_test_gates.sh groups`.
- Posts / Privacy Gate: `test/features/posts/phase3/post_presence_listener_test.dart` passed, and `integration_test/posts_phase1_fake_test.dart` ran successfully on macOS. `integration_test/posts_phase2_fake_test.dart` through `integration_test/posts_phase5_fake_test.dart` failed to start on macOS with `Error waiting for a debug connection` / `Unable to start the app on the device`.
- Startup / Transport Gate: `integration_test/background_reconnect_test.dart` passed on macOS. `integration_test/wifi_relay_fallback_smoke_test.dart:197` and `integration_test/transport_e2e_test.dart:240` fail to build because `MessageRepositoryImpl` now requires `dbRecoverStuckSendingMessages`. `integration_test/media_stable_id_smoke_test.dart` failed to start on macOS with `Error waiting for a debug connection` / `Unable to start the app on the device`.
- Top-level script validation: `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh all` exits non-zero in the Baseline Gate for the same `loading_states_smoke_test.dart` build failure.
- Device note: when multiple Flutter targets are attached, set `FLUTTER_DEVICE_ID=<device-id>` for integration-backed gates. Session 1 validation used `FLUTTER_DEVICE_ID=macos`.
