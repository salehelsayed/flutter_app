# Test Gate Definitions

Session 1 source of truth for named regression gates.

If this document and `scripts/run_test_gates.sh` ever disagree, the script wins.

## Session 1 Decisions

- Canonical loading-state baseline file: `integration_test/loading_states_smoke_test.dart`
- `test/features/loading_states_smoke_test.dart` stays out of the Baseline Gate. It is a lighter widget/render smoke, not the startup-wiring smoke.
- The 1:1 Reliability Gate includes the 9 historical integration-smoke files,
  the 14 Dart host files from
  `111-one-to-one-p0-silent-message-loss-test-inventory.md`, and the Doc 115
  relay-inbox custody, delivery-receipt, retry, router, and migration pins.
- `test/features/conversation/integration/quote_reply_thread_test.dart` stays in the 1:1 gate because quoted-message persistence rides the same shared send/persist path that Session 2 and Session 3 will touch.
- Report 78 added encrypted v2 retry-envelope duplicate proof inside
  `test/features/conversation/integration/two_user_message_exchange_test.dart`,
  so the 1:1 Reliability Gate still covers receiver same-ID dedupe without
  adding a tenth gate file.
- Report 78's failed text retry UX and race proof lives in direct suites:
  `test/features/conversation/presentation/screens/conversation_wired_test.dart`,
  `test/features/conversation/presentation/screens/conversation_screen_test.dart`,
  `test/features/conversation/presentation/widgets/letter_card_test.dart`,
  `test/features/conversation/application/retry_failed_messages_use_case_test.dart`,
  `test/features/conversation/application/retry_unacked_messages_use_case_test.dart`,
  and `test/core/services/pending_message_retrier_test.dart`. These stay
  classified by the existing feature-local and core-services rules rather than
  widening frozen named gates.
- `test/features/conversation/integration/emoji_reaction_exchange_test.dart` stays out of the 1:1 gate because it validates the reaction pipeline, not the shared durable send / retry / media / voice contract.
- `test/features/feed/presentation/screens/feed_wired_test.dart` now carries the Session 2 feed inline 1:1 parity regression and the Session 35 delayed-mutual-acceptance / later-block follow-up regression; it stays outside the frozen named gate lists.
- `test/features/orbit/presentation/screens/orbit_wired_test.dart` and `test/features/orbit/presentation/screens/orbit_intros_wiring_test.dart` now carry the Session 35 stale-intro-reload and intro follow-up wiring regressions; they stay outside the frozen named gate lists and should be run directly with the Intro / Reintroduction Gate when intro-to-Orbit or intro-to-Feed follow-up wiring changes.
- `test/features/groups/integration/announcement_happy_path_test.dart` carries the Session 6 announcement create/send/read-only/react regression and stays in the Optional / Manual direct-suite bucket so the frozen named gate lists do not widen.
- `integration_test/group_recovery_e2e_test.dart` now carries the Session 72 device-backed dissolved local-cleanup recovery proof and stays in the Nightly / Release Pool because it remains simulator-bound and should not widen the frozen named gates.
- `test/features/groups/integration/group_admin_metadata_convergence_test.dart`
  stays in the Group Messaging Gate because its exact Scenario 3 promoted-admin
  invite, metadata, fanout, and photo journey covers promoted-admin
  metadata/photo authority, pre-join photo snapshots, promoted-admin invite
  propagation, and C-to-creator delivery after a promoted-admin invite as part
  of the group membership and metadata safety contract.
- `test/features/groups/integration/group_startup_rejoin_smoke_test.dart` stays in the Group Messaging Gate, not Startup / Transport. It validates group-topic rejoin behavior with fake infrastructure rather than the real transport gate.
- `integration_test/multi_relay_failover_test.dart` stays nightly-only because it needs multi-relay runtime configuration and composes heavier real-stack coverage than the named transport gate.
- `integration_test/multi_relay_failover_test.dart` now supports
  `--dart-define=MKNOON_REQUIRE_MULTI_RELAY=true` for fixture-backed closure
  jobs so missing relay addresses fail clearly instead of becoming skipped
  pseudo-evidence.
- `integration_test/scripts/run_group_multi_device_real.dart` remains a
  Nightly / Release Pool orchestrator rather than a named gate member because
  it launches two device processes plus a CLI peer fixture.
- `integration_test/scripts/run_group_invite_status_matrix_sim.dart` remains a
  Nightly / Release Pool orchestrator rather than a named gate member because
  it launches four simulator processes for seeded creator-side Group Info
  Members invite-status display proof; it does not claim relay/testpeer
  lifecycle evidence.
- `./scripts/run_test_gates.sh group-real-network-nightly` is the recurring
  fixture-backed group real-network command. It requires `FLUTTER_DEVICE_ID`
  and passes `MKNOON_REQUIRE_MULTI_RELAY=true`, so missing relay config fails
  clearly.
- `test/features/push/infrastructure/push_token_store_impl_test.dart` carries
  the Move Account MIG-003 device-bound push-token clear/regenerate storage
  policy. It stays outside the frozen named gates and should be run directly
  when push-token persistence or migration secure-storage policy changes.
- `test/features/account_migration/application/migration_file_manifest_builder_test.dart`,
  `migration_file_manifest_validator_test.dart`,
  `migration_storage_preflight_test.dart`, and
  `migration_file_import_cleanup_test.dart` carry the Move Account MIG-005
  app-owned file manifest, media metadata validation, storage preflight, and
  staged file cleanup proof. They stay classified by the feature-local direct
  suite rule and should be run directly when migration file manifest or storage
  preflight behavior changes.
- `test/features/account_migration/application/migration_group_manifest_builder_test.dart`
  and `migration_group_manifest_validator_test.dart` carry the Move Account
  MIG-006 group manifest and validation proof. They stay classified by the
  feature-local direct suite rule and should be run directly when migration
  group manifest, retained group-key, shared mirror, pending draft, pending
  key repair, pending membership, welcome tombstone, inbox cursor, or moved
  account group-device policy behavior changes.
- `test/features/account_migration/application/migration_transfer_manifest_test.dart`,
  `migration_segment_crypto_test.dart`,
  `migration_transfer_checkpoint_store_test.dart`, and
  `migration_segmented_transfer_service_test.dart` carry the Move Account
  MIG-007 migration-specific segmented transfer proof. They stay classified by
  the feature-local direct suite rule and should be run directly when migration
  transfer manifesting, segment crypto, checkpoint/resume, or migration route
  isolation behavior changes.
- `test/features/account_migration/application/migration_cutover_coordinator_test.dart`
  carries the Move Account MIG-008 durable cutover and server lease-cleanup
  proof. It stays classified by the feature-local direct suite rule and should
  be run directly when account migration cutover ordering, old-block proof,
  new-active commit, rendezvous unregister, inbox token unregister, or stale
  push-token cleanup behavior changes.
- `test/features/account_migration/application/account_migration_runtime_network_gate_test.dart`
  carries the Move Account MIG-009 migrated-out runtime network gate proof. It
  stays classified by the feature-local direct suite rule and should be run
  directly when account authority gating is threaded into startup, resume, P2P,
  push, inbox drain, group recovery, or retrier side-effect boundaries.
- `test/features/account_migration/application/migration_pending_work_manifest_builder_test.dart`
  and `migration_pending_work_manifest_validator_test.dart` carry the Move
  Account MIG-010 pending-work ownership and unsafe-row policy proof. They stay
  classified by the feature-local direct suite rule and should be run directly
  when migration pending-work ownership, new-phone-only resume policy, unsafe
  row blocking, pending upload file references, or sensitive pending-payload
  exclusion behavior changes.
- `test/features/account_migration/presentation/account_migration_journey_screen_test.dart`
  and `account_migration_blocked_screen_test.dart` carry the Move Account
  MIG-011 host-side journey, migration-specific scanner copy, progress/wake-lock,
  settings-entry, and migrated-out erase UX proof. They stay classified by the
  feature-local direct suite rule and should be run directly when migration
  presentation, QR scanner copy, settings move-account entry, wake-lock
  foreground behavior, or migrated-out UX changes.
- `integration_test/migration_database_sqlcipher_capability_test.dart` remains
  an Optional / manual direct suite, and is also classified in
  `$run-flutter-reliability-sims move-feature/all` as a Move Account concrete-target
  integration companion. It is not a group-messaging proof; it stays in the
  dedicated Move Account reliability scope.

## Bulk-Classification Policy

- Named gates use exact file paths only. No folder shorthands.
- The public gate command is always the script command. Internally, the script may split host-side `test/` files from `integration_test/` files and may fan out integration-backed files into separate `flutter test` invocations when the combined app launch is unreliable.
- Feature-local tests under `test/features/<feature>/application`, `domain`, `presentation`, `phase*`, `improvement`, and `regression` stay implicitly covered by direct feature-level runs unless they are explicitly named below.
- High-value integration, cross-feature, service, lifecycle, resilience, and orchestration suites must be classified intentionally, even when they stay outside the named gates.
- Red tests are not removed from a gate definition to make the gate look green. They stay documented as known failures until fixed.
- When adding a new integration, cross-feature, core-service, lifecycle, resilience, or orchestration test, classify it here and keep `./scripts/run_test_gates.sh completeness-check` green.

## Move Account Gate Capture

Use this section when validating the Move Account / account-migration inventory through the skill-backed broad gates.

Host command plan source:

```bash
"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-host-gates/scripts/run_host_gates.sh" feature-host-all --list
"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-host-gates/scripts/run_host_gates.sh" core-host-all --list
"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-host-gates/scripts/run_host_gates.sh" host-all --list
```

Host capture:

- `move-feature` captures all 40 dedicated `test/features/account_migration/**/*_test.dart` files, currently 226 declared `test` / `testWidgets` cases, plus the shared lifecycle, push, local-discovery, startup, and P2P move guards listed below.
- `feature-host-all` and `host-all` capture all 40 dedicated account-migration files plus the shared feature suites under identity, push, QR code, settings, and home.
- `core-host-all` and `host-all` capture the shared core-side move gates under lifecycle, local-discovery, and P2P services.

Shared host suites that should stay visible in Move Account reviews:

- `test/core/lifecycle/handle_app_resumed_export_pause_recovery_test.dart`
- `test/core/local_discovery/bonsoir_discovery_service_contract_test.dart`
- `test/core/services/p2p_service_impl_test.dart`
- `test/features/identity/application/startup_decision_test.dart`
- `test/features/identity/presentation/screens/startup_router_recovery_test.dart`
- `test/features/push/application/background_message_handler_test.dart`
- `test/features/push/application/push_registration_post_cutover_test.dart`
- `test/features/qr_code/application/handle_scanned_qr_use_case_test.dart`
- `test/features/qr_code/presentation/screens/qr_scanner_wired_test.dart`
- `test/features/settings/presentation/screens/settings_wired_test.dart`
- `test/features/home/presentation/screens/first_time_experience_wired_test.dart`

Reliability command plan source:

```bash
"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" move-feature --list
```

Reliability capture under `move-feature` / `all`:

- `integration_test/account_migration_group_media_durability_simulator_test.dart`
- `integration_test/account_migration_local_transfer_timeout_simulator_test.dart`
- `integration_test/account_migration_scale_benchmark_test.dart`
- `integration_test/migration_database_sqlcipher_capability_test.dart`

The SQLCipher capability test is a Move Account concrete-target integration companion, not a group chat scenario. The Android-to-iOS SQLCipher migration path remains a known acceptance gap outside this same-device probe.

## 111 P0 Silent 1:1 Message Loss Gate Capture

Use this section when validating
`111-one-to-one-p0-silent-message-loss-test-inventory.md` through the
skill-backed 1:1 gates.

Host command plan source:

```bash
"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-host-gates/scripts/run_host_gates.sh" 1to1 --list
```

Host capture:

- `1to1` captures the 9 historical 1:1 integration-smoke files plus the 14 Dart
  host files from the 111 inventory. Doc 115 extends the same gate with relay
  custody, delivery-receipt, retry, router, and migration pins.
- `host-all`, `feature-host-all`, and `core-host-all` also capture the matching
  111 Dart files through broad directory discovery.

Reliability command plan source:

```bash
"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" 1to1 --list
```

Reliability capture under `1to1` / `all`:

- The 111 inventory did not add a new `integration_test/*.dart` simulator file.
  The reliability-sim 1:1 scope still captures the existing 1:1 simulator/E2E
  entrypoints for text, media, voice, notification-open, push-decrypt,
  routing, cold-start, reconnect, Wi-Fi/relay fallback, and soak coverage.

Non-Flutter companions from the same inventory remain explicit Go gates, not
Flutter host/simulator gates:

```bash
(cd go-mknoon && make test)
(cd go-relay-server && go test ./...)
(cd go-mknoon && go test -tags integration ./integration/...)
```

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

Run when shared 1:1 send, retry, upload/download, listener, inbox,
decrypt/key-recovery, contact-key rotation, or feed-originated 1:1 entry
points change.

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
- `test/features/conversation/integration/edit_retry_round_trip_test.dart`
- `test/core/database/migrations/077_message_relay_custody_test.dart`
- `test/core/inbox/inbox_round_trip_test.dart`
- `test/core/lifecycle/handle_app_resumed_upload_ordering_test.dart`
- `test/core/services/incoming_message_router_test.dart`
- `test/core/services/pending_message_retrier_upload_ordering_test.dart`
- `test/features/conversation/application/handle_incoming_chat_message_use_case_test.dart`
- `test/features/conversation/application/chat_message_listener_test.dart`
- `test/features/conversation/application/send_chat_message_use_case_test.dart`
- `test/features/conversation/application/retry_unacked_messages_use_case_test.dart`
- `test/features/conversation/application/recovered_inbox_chat_disposition_test.dart`
- `test/features/conversation/application/delivered_status_minting_sites_test.dart`
- `test/features/conversation/application/delete_message_use_case_test.dart`
- `test/features/conversation/application/handle_incoming_message_deletion_use_case_test.dart`
- `test/features/conversation/application/handle_delivery_receipt_use_case_test.dart`
- `test/features/conversation/application/send_delivery_receipt_use_case_test.dart`
- `test/features/conversation/application/verify_inbox_custody_use_case_test.dart`
- `test/core/database/helpers/inbox_staging_db_helpers_test.dart`
- `test/core/services/p2p_service_impl_test.dart`
- `test/features/conversation/application/download_media_use_case_test.dart`
- `test/features/conversation/application/upload_media_use_case_test.dart`
- `test/features/conversation/integration/one_to_one_media_encryption_round_trip_test.dart`
- `test/core/bridge/go_bridge_client_test.dart`
- `test/core/bridge/p2p_bridge_client_test.dart`
- `test/features/conversation/application/media_download_slow_transfer_simulator_test.dart`
- `test/features/contact_request/application/handle_incoming_message_use_case_test.dart`
- `test/features/contact_request/application/retry_incomplete_key_exchanges_use_case_test.dart`
- `test/features/conversation/application/post_restore_stale_key_recovery_test.dart`
- `test/features/contact_request/application/contact_request_listener_test.dart`
- `test/features/identity/domain/repositories/identity_repository_impl_test.dart`

### 114 LAN Ack-After-Commit Gate Capture

Doc 114 host implementation is covered by focused direct suites plus the
current 1:1 Reliability Gate:

- `test/core/local_discovery/local_ws_server_test.dart` pins the committed ack
  wire contract, legacy ack classification, nacks, and raw old-matcher behavior.
- `test/core/local_discovery/local_ws_durable_ack_integration_test.dart` pins
  real loopback WebSocket committed-ack custody over a real staging DB,
  restart replay, quarantine, legacy classification, rejecting nacks, and media
  envelope preservation.
- `./scripts/run_test_gates.sh completeness-check` passed on 2026-06-13 with
	  `841/841` files classified; the new local-discovery file is currently
	  classified by the core component direct-suite rule.
- `./scripts/run_reliability_simulations.sh 1to1 --only 16` passed on
  2026-06-13 after `wifi_relay_fallback_smoke_test.dart` was aligned to DB
  version 77 and truthful `inboxed` fallback statuses; S1-S4 reported `4/4`
  passed.

The 114 local-discovery files remain classified by the core component
direct-suite rule. The coordinated 3-doc program `1to1` array edit is now
landed through the 115 relay-custody expansion plus the 116 edit-retry
integration entry below.

### 115 Relay Inbox Custody Gate Capture

Doc 115 host implementation is covered by the expanded 1:1 Reliability Gate
plus focused Go relay and go-mknoon contract gates:

- The expanded 1:1 gate includes the message relay-custody migration,
  inbox-staging round trip, resumed-upload ordering, incoming router,
  pending-message retrier, send/retry, delivery receipt, delete/deletion
  propagation, recovered-inbox disposition, bridge, media, encryption, and
  offline inbox round-trip suites that pin the Flutter-side custody contract.
- Relay server contract companions: `(cd go-relay-server && go test -count=1 ./...)`
  and focused protocol/backend tests pin full-inbox typed rejection, backend
  capacity policy, Redis no-trim semantics, metrics, and bootstrap capacity.
- go-mknoon companions: `(cd go-mknoon && make testpeer)`,
  `(cd go-mknoon && make verify-bindings)`, focused `node`, `bridge`, and
  `cmd/testpeer` tests, plus
  `(cd go-mknoon && go test -tags integration ./integration -run TestInboxStoreFull_TypedRejectionAgainstLocalRelay -count=1)`.
- Production relay deployment to `mknoun.xyz` is verified for Doc 115
  (`relay-server v1.5.1`, installed hash
  `3d732c11f4d4ce4ba72a03d2440571c66f2b183677f4e6c19850bddddffe1bf5`,
  active service, and SSH-local Doc 115 metrics counters). TestFlight and
  two-device relay-drain evidence remains unclaimed residual lab proof, not
  host-synthesized proof.

### 116 Edit Retry Fidelity Gate Capture

Doc 116 host implementation is covered by focused direct suites plus the
current 1:1 Reliability Gate:

- `test/features/conversation/integration/edit_retry_round_trip_test.dart`
  pins failed-edit retry convergence so sender and receiver keep the edited
  text and edited badge semantics after a failed-then-retried edit.
- `test/features/conversation/application/retry_failed_messages_use_case_test.dart`
  and `send_chat_message_use_case_test.dart` pin row-derived retry action,
  no-downgrade writer gates, single-flight retry, settled-row skips, and
  tombstone retry liveness.
- `test/features/conversation/application/delete_message_use_case_test.dart`
  pins the shared deletion-envelope builder and inbox-custody tombstone
  semantics.
- `test/features/conversation/application/handle_incoming_chat_message_use_case_test.dart`,
  `chat_message_listener_test.dart`, and
  `recovered_inbox_chat_disposition_test.dart` pin receiver duplicate mismatch
  telemetry, ignored-edit `ok=true` nonce confirmation, and staged ignored-edit
  replay disposition.
- The final 116 host closure on 2026-06-13 passed direct P3A/P3B suites,
	  `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline`,
	  `./scripts/run_test_gates.sh completeness-check`, `git diff --check`, and
	  `./graphify-arch/refresh_arch_graph.sh`. The final expanded
	  `./scripts/run_test_gates.sh 1to1` passed with `+793` after the aggregate
	  bridge timeout row and send-then-lock 7c stale expectation were closed.

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

### Intro / Reintroduction Gate

Run when introduction send, resend, accept, pass, listener, or intro picker behavior changes.

Command:

```bash
./scripts/run_test_gates.sh intro
```

Files:

- `test/features/introduction/application/accept_introduction_test.dart`
- `test/features/introduction/application/create_connection_on_mutual_acceptance_test.dart`
- `test/features/introduction/application/handle_incoming_introduction_test.dart`
- `test/features/introduction/application/introduction_listener_test.dart`
- `test/features/introduction/application/mutual_acceptance_test.dart`
- `test/features/introduction/application/pass_introduction_test.dart`
- `test/features/introduction/application/send_introduction_test.dart`
- `test/features/introduction/integration/intro_wiring_smoke_test.dart`
- `test/features/introduction/integration/introduction_multi_node_test.dart`
- `test/features/introduction/integration/introduction_smoke_test.dart`
- `test/features/introduction/presentation/screens/friend_picker_wired_test.dart`
- `test/features/introduction/regression/introduction_regression_test.dart`

Required companion rule:

- If intro changes affect Orbit or Feed follow-up surfaces, also run `test/features/orbit/presentation/screens/orbit_intros_wiring_test.dart` and the relevant intro-follow-up assertions in `test/features/feed/presentation/screens/feed_wired_test.dart` directly.

### Group Messaging Gate

Run when group send, receive, retry, resume, invite, metadata/photo authority, or announcement behavior changes.

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

### Runtime Telemetry Gate

Run when push decrypt telemetry, flow-event emission, or TestFlight soak
acceptance logic changes.

Command:

```bash
./scripts/run_test_gates.sh runtime-telemetry
```

Files:

- `test/features/push/application/push_preview_telemetry_gate_test.dart`

### Move Account Gate (`move-feature`)

Run whenever anything under `lib/features/account_migration/`, the migration
transport (`lib/core/local_discovery/local_ws_server.dart`), the runtime
network gate, or the cutover/authority model changes — and ALWAYS before a
physical-device move test.

Command:

```bash
./scripts/run_test_gates.sh move-feature
```

Equivalent skill-backed form:

```bash
"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-host-gates/scripts/run_host_gates.sh" move-feature
```

Files: all 40 dedicated `test/features/account_migration/**/*_test.dart`
files, currently 226 declared tests, including
`account_migration_end_to_end_test.dart` — the chained host E2E of the shipped
composition (production bundle source → real in-process `LocalWsServer` HTTP
wire → production receiver → cutover), with a realistic-scale ~12 MB / 50+
segment variant.

Shared host files included by the `move-feature` host plan:

- `test/core/lifecycle/handle_app_resumed_export_pause_recovery_test.dart`
- `test/core/local_discovery/bonsoir_discovery_service_contract_test.dart`
- `test/core/services/p2p_service_impl_test.dart`
- `test/features/identity/application/startup_decision_test.dart`
- `test/features/push/application/push_registration_post_cutover_test.dart`

Device/simulator companion (required pre-step for physical move tests, runs
the durability + transfer-timeout simulators and the SQLCipher capability
probe):

```bash
./scripts/run_test_gates.sh reliability-sim move
```

Cross-platform SQLCipher portability (spec gap G2, semi-manual two-step —
the artifact flow documented in
`integration_test/migration_database_sqlcipher_capability_test.dart`):

```bash
# 1. Source platform (Android device/emulator), then `adb pull` the dir:
flutter test integration_test/migration_database_sqlcipher_capability_test.dart \
  -d <android-device> --dart-define=MIGRATION_PORTABILITY_EXPORT_DIR=/data/local/tmp/mig_portability
# 2. Target platform (iOS simulator) against the pulled artifact:
flutter test integration_test/migration_database_sqlcipher_capability_test.dart \
  -d <ios-sim> --dart-define=MIGRATION_PORTABILITY_FIXTURE_DIR=<pulled-dir>
```

Run it whenever the SQLCipher plugin or cipher defaults change, and once per
release that touches the move feature.

Runtime gate definition:

```yaml
push_preview_degrade_rate_gate:
  source: production telemetry flow events
  window: trailing_7d_after_72h_soak
  numerator_events:
    - PUSH_NSE_DECRYPT_FAIL
    - PUSH_NSE_TIMEOUT
    - PUSH_ANDROID_DATA_DECRYPT_FAIL
  denominator_events:
    - PUSH_NSE_DECRYPT_OK
    - PUSH_NSE_DECRYPT_FAIL
    - PUSH_NSE_TIMEOUT
    - PUSH_ANDROID_DATA_DECRYPT_OK
    - PUSH_ANDROID_DATA_DECRYPT_FAIL
  excluded_reasons:
    - client_pre_decrypt
    - keychain_locked
    - migration_pending
  block_threshold: 0.03
```

Required companion evidence:

- iOS NSE flow events must use only `kind` and `reason` metadata.
- Android data-decrypt flow events must use only `kind` and `reason`
  metadata.
- Runtime telemetry must not include sender names, group names, message text,
  media descriptors, ciphertext, nonces, or canary values.

### Push Decrypt Simulator Smoke

Run when push decrypt fixtures, simulator injection scripts, iOS NSE payload
shape, or Android data-only push intake changes.

Script-shape check:

```bash
bash -n scripts/push_fixture_to_simulator.sh \
  scripts/push_fixture_to_android_emulator.sh \
  scripts/smoke_test_push_decrypt_simulator.sh
scripts/smoke_test_push_decrypt_simulator.sh --dry-run
```

App-installed preflight for full OS-delivery smoke:

```bash
flutter build ios --simulator --debug
xcrun simctl boot <iphone-17-udid-or-name> || true
xcrun simctl boot <iphone-17-pro-udid-or-name> || true
xcrun simctl install <iphone-17-udid-or-name> build/ios/iphonesimulator/Runner.app
xcrun simctl install <iphone-17-pro-udid-or-name> build/ios/iphonesimulator/Runner.app
xcrun simctl get_app_container <iphone-17-udid-or-name> com.mknoon.app
xcrun simctl get_app_container <iphone-17-pro-udid-or-name> com.mknoon.app

flutter build apk --debug
/Users/I560101/Library/Android/sdk/platform-tools/adb -s emulator-5554 install -r \
  build/app/outputs/flutter-apk/app-debug.apk
/Users/I560101/Library/Android/sdk/platform-tools/adb -s emulator-5554 shell pm path com.mknoon.app
```

Current full non-dry-run simulator matrix:

```bash
SIMULATOR_DEVICE=<iphone-17-udid-or-name> \
  IOS_SECONDARY_SIMULATOR_DEVICE=<iphone-17-pro-udid-or-name> \
  scripts/smoke_test_push_decrypt_simulator.sh --ios-only
SIMULATOR_DEVICE=<iphone-17-pro-udid-or-name> \
  IOS_SECONDARY_SIMULATOR_DEVICE=<iphone-17-udid-or-name> \
  scripts/smoke_test_push_decrypt_simulator.sh --ios-only
ANDROID_SERIAL=emulator-5554 scripts/smoke_test_push_decrypt_simulator.sh --android-only
```

This covers S-iOS-1 through S-iOS-19 and S-And-1 through S-And-19. The iOS
dual-simulator rows require `IOS_SECONDARY_SIMULATOR_DEVICE`; the Android
force-stop row requires an explicit `ANDROID_SERIAL`.

Required companion gates when closing plan 73 Session 8:

```bash
flutter test
(cd go-relay-server && go test ./...)
xcodebuild test -workspace ios/Runner.xcworkspace -scheme Runner \
  -destination 'platform=iOS Simulator,name=iPhone 17'
./scripts/run_test_gates.sh baseline
./scripts/run_test_gates.sh 1to1
./scripts/run_test_gates.sh groups
./scripts/run_test_gates.sh runtime-telemetry
./scripts/run_test_gates.sh completeness-check
scripts/check_push_release_gate.sh
```

CI placement:

- `--dry-run` is PR-safe and validates fixture-to-APNs/FCM payload shaping.
- Full OS delivery belongs in the simulator matrix job with iPhone 17, iPhone
  17 Pro, and Pixel 7 API 37 targets booted and the app installed.
- Full S-iOS-1 through S-iOS-19 and S-And-1 through S-And-19 coverage is the
  simulator-matrix acceptance gate, not a replacement for TestFlight telemetry.

## Nightly / Release Pool

These stay outside the named gates because they are heavier, device-bound, env-bound, or real-stack confidence tests.

- `integration_test/smoke_test.dart`
- `integration_test/conversation_bridge_test.dart`
- `integration_test/wifi_transport_test.dart`
- `integration_test/voice_message_e2e_test.dart`
- `integration_test/group_real_crypto_onboarding_test.dart`
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
| `test/features/groups/integration/announcement_new_reader_onboarding_test.dart` | Optional / manual direct suite | Report 85 focused announcement new-reader post-join image/video/voice plus no-backfill regression; Report 89 adds read-only text/image/video/voice send denial without widening frozen named gates |
| `test/features/groups/integration/group_media_fanout_test.dart` | Optional / manual direct suite | Report 85 focused existing-member discussion image/video/voice fan-out regression; Report 89 adds newly-added-member image/video/voice send fan-out; Report 90 GMAR-005 runs it directly for final all-recipient media acceptance without widening frozen named gates |
| `test/features/groups/integration/group_multi_device_convergence_test.dart` | Optional / manual direct suite | Report 85 same-account host oracle for sent-history, membership, mute, unread, and notification locality without widening frozen named gates |
| `test/features/groups/integration/group_new_member_onboarding_test.dart` | Optional / manual direct suite | Report 85 and Report 89 focused discussion new-member post-join text/image/video/voice plus no-backfill regression; Report 90 GMAR-005 runs it directly for final all-recipient media acceptance without widening frozen named gates |
| `test/features/conversation/integration/emoji_reaction_exchange_test.dart` | Optional / manual direct suite | Reaction pipeline coverage, not shared durable-send coverage |
| `test/features/contact_request/integration/contact_request_flow_test.dart` | Optional / manual direct suite | Contact bootstrap and acceptance flow; run with invite or onboarding entry work |
| `test/features/contact_request/integration/key_exchange_retry_flow_test.dart` | Optional / manual direct suite | Contact key-bootstrap retry logic, not a named gate member |
| `test/core/notifications/local_notification_support_test.dart` | Optional / manual direct suite | Shared Android/iOS message-notification detail sound contract used by Report 75 without widening frozen named gates |
| `test/features/push/application/background_message_handler_test.dart` | Optional / manual direct suite | Background fallback display, duplicate suppression, and Report 75 audible platform-specific detail proof without widening frozen named gates |
| `test/features/push/application/handle_foreground_remote_message_use_case_test.dart` | Optional / manual direct suite | Foreground FCM kind-aware drain regression for Report 71 without widening the frozen named gates |
| `test/features/push/application/ios_push_project_config_test.dart` | Optional / manual direct suite | iOS push project config, APNs diagnostics, and quiet foreground remote presentation contract for Report 75 without widening frozen named gates |
| `test/features/push/application/show_notification_use_case_test.dart` | Optional / manual direct suite | Notification display and suppression boundary, including the route-payload remote-announcement dedupe regression for group pushes |
| `test/features/push/application/chat_and_group_push_open_flow_test.dart` | Optional / manual direct suite | Notification open sequencing across chat, group, intros, and contact-request routes without widening named gates |
| `test/features/push/application/resolve_group_notification_route_target_use_case_test.dart` | Optional / manual direct suite | Group push recovery regression for missing local group state, stale removed-group route denial, pending invite discovery, inbox-drain retry, and Orbit intro redirect fallback |
| `test/features/settings/integration/profile_picture_flow_test.dart` | Optional / manual direct suite | Profile media / broadcast / download flow |
| `test/features/share/integration/share_to_contact_smoke_test.dart` | Optional / manual direct suite | Share target routing and compose hydration |
| `test/integration/group_notification_dedupe_integration_test.dart` | Optional / manual direct suite | Background group push announcement versus later local group notification dedupe regression without widening the frozen named gates |
| `test/integration/onboarding_golden_path_test.dart` | Optional / manual direct suite | Session 7 onboarding confidence flow spanning identity create, accepted contact request, and first 1:1 send without widening frozen named gates |
| `test/integration/notification_deeplink_integration_test.dart` | Optional / manual direct suite | Notification routing boundary; Session 4 work will harden this area |
| `test/integration/rapid_lock_unlock_integration_test.dart` | Optional / manual direct suite | Lifecycle retry edge case, narrower than the named gates |
| `test/integration/relay_down_degradation_integration_test.dart` | Optional / manual direct suite | 1:1 degradation edge-case coverage, including failed-send during transport loss -> foreground online-transition retry healing the same row exactly once |
| `test/integration/group_multi_party_device_criteria_test.dart` | Optional / manual direct suite | PREREQ-GM-MULTI-PARTY-DEVICE-HARNESS host-side guard that multi-party GM proof cannot pass with missing relay env, underspecified roles, sender-only evidence, receiver/sender message tuple mismatches, duplicate persistence, incomplete GM-002 convergence, or missing GM-003 offline catch-up proof |
| `test/integration/routing_smoke_group_criteria_test.dart` | Optional / manual direct suite | Report 85 host-side guard that the two-simulator group smoke G2/G4/G5/G7/G8 rows cannot pass with pending or sender-only receiver evidence |
| `integration_test/cold_start_sendable_no_user_action_test.dart` | Optional / manual direct suite | Cold-start sendability check without widening the startup or transport gates |
| `integration_test/account_migration_group_media_durability_simulator_test.dart` | Optional / manual direct suite; `$run-flutter-reliability-sims move-feature/all` | Move Account MIG-012 group-media durability and relay-free bundleability proof; classified in the reliability-sim discovery move-feature scope without widening frozen named gates |
| `integration_test/account_migration_local_transfer_timeout_simulator_test.dart` | Optional / manual direct suite; `$run-flutter-reliability-sims move-feature/all` | Move Account local segmented transfer timeout proof: 34-segment near-budget success with monotonic `ACCOUNT_MIGRATION_LOCAL_TRANSFER_SEGMENT_PROGRESS` telemetry plus over-budget typed `localTransferTimedOut` failure with `ACCOUNT_MIGRATION_LOCAL_TRANSFER_POST_FAILED` phase diagnostics and no `bundleSourceFailed` mislabel; classified in the reliability-sim discovery move-feature scope without widening frozen named gates |
| `integration_test/account_migration_scale_benchmark_test.dart` | Optional / manual direct suite; `$run-flutter-reliability-sims move-feature/all` with `--dart-define=MIGRATION_BENCH_MB=<N>` | Move Account P0-7 scale benchmark harness for 200/500/1000 MB Pixel evidence; emits `ACCOUNT_MIGRATION_SCALE_BENCHMARK` structured metrics and remains classified in the reliability-sim discovery move-feature scope without widening frozen named gates |
| `integration_test/cold_start_message_render_simulator_test.dart` | Optional / manual direct suite | Simulator-bound Orbit render smoke for previously received 1:1 and group message bodies after a cold restart |
| `integration_test/conversation_wired_performance_test.dart` | Optional / manual direct suite | Performance-only validation for conversation screen wiring |
| `integration_test/conversation_wired_subscription_performance_test.dart` | Optional / manual direct suite | Performance-only validation for conversation subscription churn |
| `integration_test/feed_performance_test.dart` | Optional / manual direct suite | Performance-only validation |
| `integration_test/foreground_group_push_drain_test.dart` | Optional / manual direct suite | Foreground group push targeted drain, no-duplicate, and Report 85 representative media descriptor/download regression without widening the frozen named gates. Companion simulator approximation: `dart run integration_test/scripts/run_foreground_group_push_simulator_smoke.dart -d <alice>,<bob>` for real-stack two-simulator gap + replay coverage. |
| `integration_test/group_delete_preserves_friends_simulator_test.dart` | Optional / manual direct suite | Simulator-bound Orbit delete regression proving deleting one group does not remove friends or 1:1 threads |
| `integration_test/group_invite_accept_spinner_simulator_test.dart` | Optional / manual direct suite | Simulator-bound pending group invite accept regression proving the spinner clears and the group joins |
| `integration_test/scripts/run_group_invite_status_matrix_sim.dart` | Optional / manual simulator orchestrator | Four-simulator seeded creator-side `GroupInfoWired` Members invite-status display proof for `Invite sent`, `In their inbox`, `Resend needed`, `Cannot send` with user-readable reason copy, `Joined`, and `Invite unknown`; remains outside named gates and does not claim relay/testpeer lifecycle proof |
| `integration_test/scripts/run_group_multi_party_device_real.dart` | Optional / manual simulator orchestrator | PREREQ-GM-MULTI-PARTY-DEVICE-HARNESS multi-party Flutter app peer proof for GM-001/GM-002/GM-003-shaped prerequisites with exact relay env; includes Report 103 `scenario7_group_invite_stale_metadata_recovery` for four-role stale-invite/latest-metadata recovery, pending retry, final roles, avatar bytes, and fan-out criteria; includes Report 106 `private_invite_terminal_states` proof fields for accepted-recipient delivery and terminal-invitee no-message/no-local-fallback notification evidence; remains outside named gates and does not close GM rows without row-specific sessions |
| `integration_test/feed_wired_init_performance_test.dart` | Optional / manual direct suite | Performance-only validation for feed initialization |
| `integration_test/group_new_member_media_simulator_proof_test.dart` | Optional / manual direct suite | Report 89 simulator-backed new discussion member video and voice render/play/reopen proof; Report 90 GMAR-005 configured-simulator proof without widening frozen named gates |
| `integration_test/identity_progress_performance_test.dart` | Optional / manual direct suite | Performance-only validation |
| `integration_test/media_message_journey_e2e_test.dart` | Optional / manual direct suite | End-to-end media delivery journey coverage that stays outside the frozen named gates; Report 90 GMAR-005 runs it directly as final media-journey evidence |
| `integration_test/migration_database_sqlcipher_capability_test.dart` | Optional / manual direct suite; `$run-flutter-reliability-sims move-feature/all` | Move Account MIG-004 plugin-registered SQLCipher export capability probe; classified as a reliability-sim Move Account concrete-target companion, not a group messaging proof |
| `integration_test/notification_open_ui_smoke_test.dart` | Optional / manual direct suite | Notification-open UI routing smoke without widening the frozen named gates |
| `scripts/run_ios_notification_tap_ui_smoke.sh` | Optional / manual direct suite | iOS simulator-bound APNs notification tap smoke using `simctl push` plus a real Springboard notification tap; release/nightly confidence only, not a PR gate |
| `integration_test/orbit_performance_test.dart` | Optional / manual direct suite | Performance-only validation for Orbit surface behavior |
| `integration_test/settings_background_choice_smoke_test.dart` | Optional / manual direct suite | Device-backed Settings background-choice smoke from the background/theme rollout archive; classified here to keep the test inventory complete without widening named gates |

### Explicit Out-of-Gate File

| File | Classification | Reason |
|------|----------------|--------|
| `test/features/loading_states_smoke_test.dart` | Out of gate | Widget/render smoke only; keep the startup-wiring smoke canonical in `integration_test/` |

### Directory-Level Direct Suites

These directories are intentionally outside the named gates, but they are not accidental leftovers.

| Scope | Classification | Reason |
|------|----------------|--------|
| `test/core/services/*.dart` | Direct suite | Service, router, retrier, and orchestration coverage for the exact module being edited |
| `test/features/account_migration/**/*.dart` | Direct suite; `$run-flutter-host-gates move-feature/feature-host-all/host-all` | All 40 dedicated Move Account host files, currently 226 declared test cases, covering transfer, bundle content, secure storage, database import, cutover/authority/gating, QR/pairing, presentation, chained host E2E, post-import behavior, and keep-alive |
| `test/features/account_migration/presentation/*.dart` | Direct suite | Move Account MIG-011 host-side presentation, scanner-copy, wake-lock, and migrated-out UX tests without widening frozen named gates |
| `test/core/lifecycle/*.dart` | Direct suite | Pause/resume ordering and lifecycle hardening; kept separate so the transport gate stays bounded |
| `test/core/resilience/*.dart` | Direct suite | Deterministic chaos/failover coverage; broader than the frozen transport gate |
| `test/core/notifications/*.dart` | Direct suite | Notification route/dispatch helpers without promoting them into the baseline |
| `test/core/debug/*.dart` | Direct suite | Transport/debug metrics diagnostics and privacy invariants |
| `test/core/bridge/*.dart` | Direct suite | Bridge adapter and helper behavior |
| `test/core/database/*.dart` | Direct suite | Database helper and migration coverage |
| `test/core/device/*.dart` | Direct suite | Device-level helpers such as wake-lock coordination without widening named gates |
| `test/core/inbox/*.dart` | Direct suite | Lower-level inbox behavior |
| `test/core/local_discovery/*.dart` | Direct suite | WiFi/local discovery support coverage |
| `test/core/media/*.dart` | Direct suite | Media helper and processing behavior |
| `test/core/secure_storage/*.dart` | Direct suite | Secure storage behavior |
| `test/core/constants/*.dart`, `test/core/theme/*.dart`, `test/core/utils/*.dart` | Direct suite | Component-level contracts, not gate members |
| `test/l10n/*.dart` | Direct suite | Generated/localized copy integrity |
| `test/shared/fakes/*.dart` | Direct suite | Test harness fakes and seeded reproduction fixtures |
| `test/security/*.dart` | Direct suite | Security invariant and forbidden-field classifier coverage without widening frozen named gates |
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

Validation run dates:
- 2026-03-25 initial gate validation
- 2026-03-26 Session 27 revalidation for `baseline`, `groups`, and `transport`
- 2026-04-29 Report 89 revalidation for `groups` and `completeness-check`
- 2026-04-29 Report 89 Android emulator simulator proof for newly-added group member video/voice render, play, and reopen
- 2026-04-29 Report 89 iPhone 17 simulator proof for newly-added group member video/voice render, play, and reopen
- 2026-05-03 Report 90 GMAR-005 final acceptance/recovery revalidation for direct GMAR suites, configured simulator media proofs, two-simulator routing/group and foreground group push smoke commands, device-pinned `all`, `completeness-check`, broad `flutter test`, Go module tests, and `git diff --check`
- 2026-05-28 promoted-admin group Scenario 3 regression validation for
  `group_admin_metadata_convergence_test.dart`,
  `group_info_wired_test.dart`, `send_group_invite_use_case_test.dart`,
  `member_removal_integration_test.dart`, and `git diff --check`
- 2026-05-31 Report 102 GIRD-007 completeness revalidation for direct-suite classification coverage.
- 2026-06-13 Doc 114 S4/S5 completeness revalidation for LAN ack-after-commit host integration coverage.
- 2026-06-13 Doc 115 P5 completeness and expanded 1:1 revalidation for relay inbox custody, receipts, retry, router, bridge, and local-relay `INBOX_FULL` acceptance.
- 2026-06-13 Doc 116 final host closure added `edit_retry_round_trip_test.dart` to the frozen 1:1 gate and revalidated direct P3A/P3B suites, baseline, completeness, Go scope-leak sanity, diff hygiene, and graph refresh.
- 2026-06-16 Finding 03 (removal-rotation fails-closed) Slice 1 security core: member removal is durable under a keyless remaining member. `rotateAndDistributeGroupKey` is promote-then-defer (the removed member loses the live key even when a remaining member is keyless/undelivered; undelivered members are recorded as deferred, not aborted), and `_onRemoveMember` no longer rolls back / re-adds the member once `member_removed` is broadcast (`removalBroadcast`-guarded rollback, INV-R2). Gate: `flutter test test/features/groups/` green (`2070`), `flutter analyze` no new issues. **Device proof PASSED** on iPhone 17 Pro simulator (`38FECA55-03C1-4907-BD9D-8E64BF8E3469`) and Pixel 6 (`21071FDF600CSC`) via `flutter test integration_test/group_removal_rotation_keyless_proof_test.dart -d <device>` — against the REAL Go ML-KEM/AES-GCM bridge: a removal with a keyless remaining bystander promotes a genuinely new real epoch, records the bystander as deferred, and the removed member's retained old key cannot decrypt new-epoch traffic.
- 2026-06-16 Finding 03 Slice 2 (deferred-distribution convergence): a member deferred at rotation time (keyless/undelivered) converges onto the promoted epoch once it regains a usable ML-KEM key. New `group_pending_key_distributions` table (migration `078`, DB v`79`), `GroupPendingKeyDistributionRunner` re-distributes the CURRENT key (never the row's stale epoch — INV-D2), enqueue + drain wired process-wide (mirrors `debugSetFlowEventSink`; covers all 3 rotate paths without UI-chain threading) + app-resume catch-all + member-key-arrival trigger. Gate: full groups suite + Slice 2 units green (`2093`), `flutter analyze` no new issues (INV-D1..D5; INV-R1..R5 preserved). **Device proof PASSED** on iPhone 17 Pro simulator (`38FECA55-03C1-4907-BD9D-8E64BF8E3469`) via `flutter test integration_test/group_removal_rotation_keyless_converge_proof_test.dart -d <device>` — real Go ML-KEM: keyless Carol is deferred, regains a real key, the drain re-distributes the current key, and Carol `message.decrypt`s the key-update + reads new-epoch traffic while the removed member's old key fails.
- 2026-06-16 Finding 02 Slice 2 (undecryptable-messages self-heal) — **Device proof PENDING**: zero permanently-undecryptable group messages after a membership change, including background > 10 min then foreground. Covers UDM-E (offline across a rotation), UDM-F (future-epoch recovery), and UDM-G (active key-pull round-trip). Gate is satisfied only when a real-device matrix shows every member that was offline across a membership change/rotation, or backgrounded beyond 10 minutes then foregrounded, ends with no message stuck undecryptable (placeholder/gravestone). Slice 1 (Dart self-heal, migration `080`, DB v`80`) is host-green but does NOT close this gate; UDM-E/F/G land in Slice 2 behind threat-model review.

- Completeness check: latest attempted on 2026-06-13 via `./scripts/run_test_gates.sh completeness-check` and passed with `841/841` test files classified. Docs 115 and 116 expanded the frozen `1to1` gate to 39 files for relay custody, edit retry fidelity, receipts, retry, router, bridge, media, identity, and migration coverage.
- Report 90 GMAR-005 final gate set: passed on 2026-05-03 via the required direct optional/manual suites, configured simulator commands on `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD`, paired simulator smoke commands on `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD,5BA69F1C-B112-47BE-B1FF-8C1003728C8F` with relay addresses, `FLUTTER_DEVICE_ID=347FB118-10D0-40C8-A05B-B0C3BD6B8CCD ./scripts/run_test_gates.sh all`, broad `flutter test`, `cd go-mknoon && go test ./...`, and `git diff --check`.
- Report 89 simulator proof: passed on 2026-04-29 via `flutter test -d emulator-5554 integration_test/group_new_member_media_simulator_proof_test.dart`, `flutter test -d emulator-5554 integration_test/media_message_journey_e2e_test.dart`, `flutter test -d emulator-5554 integration_test/media_stable_id_smoke_test.dart`, and `flutter test -d emulator-5554 integration_test/foreground_group_push_drain_test.dart`.
- Report 89 iOS simulator proof: passed on 2026-04-29 via `flutter test -d 5BA69F1C-B112-47BE-B1FF-8C1003728C8F integration_test/group_new_member_media_simulator_proof_test.dart`, `flutter test -d 5BA69F1C-B112-47BE-B1FF-8C1003728C8F integration_test/media_message_journey_e2e_test.dart`, `flutter test -d 5BA69F1C-B112-47BE-B1FF-8C1003728C8F integration_test/media_stable_id_smoke_test.dart`, and `flutter test -d 5BA69F1C-B112-47BE-B1FF-8C1003728C8F integration_test/foreground_group_push_drain_test.dart`.
- Baseline Gate: revalidated on 2026-03-29 via `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline` and passed.
- 1:1 Reliability Gate: revalidated on 2026-06-13 via `./scripts/run_test_gates.sh 1to1` and passed with `+793`. The prior aggregate-only `test/core/bridge/p2p_bridge_client_test.dart: callP2PInboxStore timeout bridge hang triggers TimeoutException after 15s` follow-up is closed by deterministic `fakeAsync` coverage. The subsequent `send_then_lock_delivery_test.dart` 7c custody-state expectation was corrected to Doc 115 semantics: retry stores the deletion tombstone as visible `inboxed`, then Bob's inbox drain and Alice's delivery receipt flip it to `delivered`/hidden.
- Feed / Surface Gate: passed via `./scripts/run_test_gates.sh feed`.
- Group Messaging Gate: revalidated on 2026-04-29 via `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` and passed.
- Posts / Privacy Gate: `test/features/posts/phase3/post_presence_listener_test.dart` passed, and `integration_test/posts_phase1_fake_test.dart` ran successfully on macOS. `integration_test/posts_phase2_fake_test.dart` through `integration_test/posts_phase5_fake_test.dart` failed to start on macOS with `Error waiting for a debug connection` / `Unable to start the app on the device`.
- Startup / Transport Gate: revalidated on 2026-03-26 via `FLUTTER_DEVICE_ID=5BA69F1C-B112-47BE-B1FF-8C1003728C8F ./scripts/run_test_gates.sh transport` and passed. During the first rerun, `integration_test/wifi_relay_fallback_smoke_test.dart` and `integration_test/transport_e2e_test.dart` exposed stale `MessageRepositoryImpl` constructor wiring; after those repo-local test harness fixes landed, the same simulator-backed gate reran green.
- Top-level script validation: earlier Session 41 reruns confirmed `completeness-check`, `baseline`, `1to1`, and `groups` green; the latest 2026-06-13 completeness-check attempt is green with `841/841` classified files after the Doc 115 P5 gate expansion listed above.
- Device note: when multiple Flutter targets are attached, set `FLUTTER_DEVICE_ID=<device-id>` for integration-backed gates. Session 27 revalidation used `FLUTTER_DEVICE_ID=5BA69F1C-B112-47BE-B1FF-8C1003728C8F`.
