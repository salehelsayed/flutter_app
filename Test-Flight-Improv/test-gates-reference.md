# Test Gates Reference

Plan-facing Session 1 checklist for the named regression gates.

If this document, `Test-Flight-Improv/test-gate-definitions.md`, and `scripts/run_test_gates.sh` ever disagree, the script wins.

Use `Test-Flight-Improv/test-gate-definitions.md` for the deeper rationale, classification inventory, and scope decisions behind these frozen gates.

## Baseline Gate

When to run:

- Run on every PR.

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

## 1:1 Reliability Gate

When to run:

- Run when shared 1:1 send, retry, upload, listener, inbox, or feed-originated 1:1 entry points change.

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

## Feed / Surface Gate

When to run:

- Run when feed cards, feed composer, inline reply, or feed-to-conversation handoff changes.
- If feed can enter the 1:1 send path, also run `./scripts/run_test_gates.sh 1to1`.
- Companion direct coverage: `test/features/feed/presentation/screens/feed_wired_test.dart` must carry the Session 2 feed inline 1:1 parity regression whenever feed-originated 1:1 send behavior changes.

Command:

```bash
./scripts/run_test_gates.sh feed
```

Files:

- `test/features/feed/integration/feed_card_flow_test.dart`
- `test/features/feed/integration/expanded_collapsed_card_test.dart`
- `test/features/feed/integration/feed_color_smoke_test.dart`

## Group Messaging Gate

When to run:

- Run when group send, receive, retry, resume, invite, metadata/photo authority, or announcement behavior changes.
- If invite or contact-entry flows are touched, also run `test/features/contact_request/integration/contact_request_flow_test.dart`.

Command:

```bash
./scripts/run_test_gates.sh groups
```

Files:

- `test/features/groups/integration/group_messaging_smoke_test.dart`
- `test/features/groups/integration/group_admin_metadata_convergence_test.dart`
- `test/features/groups/integration/group_resume_recovery_test.dart`
- `test/features/groups/integration/group_edge_cases_smoke_test.dart`
- `test/features/groups/integration/invite_round_trip_test.dart`
- `test/features/groups/integration/group_membership_smoke_test.dart`
- `test/features/groups/integration/group_startup_rejoin_smoke_test.dart`

## Posts / Privacy Gate

When to run:

- Run when posts delivery, nearby presence, privacy filters, or replay behavior changes.

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

## Startup / Transport Gate

When to run:

- Run when bridge, resume, reconnect, transport fallback, or app bootstrap changes.

Command:

```bash
./scripts/run_test_gates.sh transport
```

Files:

- `integration_test/background_reconnect_test.dart`
- `integration_test/wifi_relay_fallback_smoke_test.dart`
- `integration_test/transport_e2e_test.dart`
- `integration_test/media_stable_id_smoke_test.dart`

Device-backed forms:

```bash
FLUTTER_DEVICE_ID=<device-id> ./scripts/run_test_gates.sh transport
```

```bash
flutter test -d <device-id> \
  integration_test/background_reconnect_test.dart \
  integration_test/wifi_relay_fallback_smoke_test.dart \
  integration_test/transport_e2e_test.dart \
  integration_test/media_stable_id_smoke_test.dart
```

## Known Failures And Notes

- Current completeness-check note: latest attempted on 2026-05-28 via `./scripts/run_test_gates.sh completeness-check` and failed with `747/750` test files classified because `test/l10n/l10n_integrity_test.dart`, `test/shared/fakes/fake_group_pubsub_network_test.dart`, and `test/shared/fakes/seeded_group_reproduction_log_test.dart` were unmatched. The worker reported those as pre-existing and unrelated to the promoted-admin regression task.
- Baseline Gate is red because `integration_test/loading_states_smoke_test.dart` fails to build: `StartupRouter` now requires `postRepository`.
- `integration_test/posts_phase1_fake_test.dart` still ran successfully in the Baseline integration invocation, but the Baseline Gate remains red because the loading-states build failed first.
- 1:1 Reliability Gate passed.
- Feed / Surface Gate passed.
- Group Messaging Gate passed.
- Posts / Privacy Gate is red on macOS because `integration_test/posts_phase2_fake_test.dart` through `integration_test/posts_phase5_fake_test.dart` fail to attach with `Error waiting for a debug connection` / `Unable to start the app on the device`. `test/features/posts/phase3/post_presence_listener_test.dart` passed, and `integration_test/posts_phase1_fake_test.dart` ran successfully.
- Startup / Transport Gate is red because `integration_test/wifi_relay_fallback_smoke_test.dart` and `integration_test/transport_e2e_test.dart` fail to build: `MessageRepositoryImpl` now requires `dbRecoverStuckSendingMessages`. `integration_test/background_reconnect_test.dart` passed, and `integration_test/media_stable_id_smoke_test.dart` failed to attach on macOS with `Error waiting for a debug connection` / `Unable to start the app on the device`.
- `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh all` exits non-zero in the Baseline Gate for the same `integration_test/loading_states_smoke_test.dart` build failure.
- When multiple Flutter targets are attached, set `FLUTTER_DEVICE_ID=<device-id>` for integration-backed gates.

## Maintenance Rule

- When adding a new integration, cross-feature, core-service, lifecycle, resilience, or orchestration test, classify it in `Test-Flight-Improv/test-gate-definitions.md` and keep `./scripts/run_test_gates.sh completeness-check` green.
- `test/integration/onboarding_golden_path_test.dart` is classified as an optional/manual direct suite for Session 7 and does not widen the frozen named gates.
