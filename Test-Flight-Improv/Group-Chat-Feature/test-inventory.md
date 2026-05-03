# Group Chat Feature -- Test Inventory

**Date:** 2026-04-29
**Scope:** All automated tests covering the Group Chat feature across unit, widget, integration, cross-feature, E2E, Go-side categories, the Report 85 group-onboarding/crypto coverage addendum, and the Report 90 GMAR-005 closure addendum.

---

## How to Run

**Full host-side group suite:**

```sh
flutter test --no-pub test/features/groups
```

**Database helpers only:**

```sh
flutter test --no-pub \
  test/core/database/helpers/groups_db_helpers_test.dart \
  test/core/database/helpers/group_messages_db_helpers_test.dart \
  test/core/database/helpers/group_messages_db_helpers_sending_test.dart \
  test/core/database/helpers/group_messages_db_helpers_reliability_test.dart \
  test/core/database/helpers/group_members_db_helpers_test.dart \
  test/core/database/helpers/group_keys_db_helpers_test.dart \
  test/core/database/helpers/group_event_log_db_helpers_test.dart
```

**Background task protection only:**

```sh
flutter test --no-pub \
  test/features/groups/presentation/screens/group_conversation_wired_bg_task_test.dart
```

**Lifecycle recovery only:**

```sh
flutter test --no-pub \
  test/core/lifecycle/handle_app_paused_group_test.dart \
  test/core/lifecycle/handle_app_resumed_group_inbox_retry_test.dart \
  test/core/lifecycle/handle_app_resumed_group_recovery_test.dart \
  test/core/lifecycle/handle_app_resumed_group_stuck_sending_test.dart \
  test/core/lifecycle/main_resume_group_upload_wiring_test.dart
```

**Integration smoke tests only:**

```sh
flutter test --no-pub test/features/groups/integration
```

**Report 85 focused host/app-layer suites:**

```sh
flutter test --no-pub \
  test/features/groups/integration/group_new_member_onboarding_test.dart \
  test/features/groups/integration/announcement_new_reader_onboarding_test.dart \
  test/features/groups/integration/group_media_fanout_test.dart \
  test/integration/routing_smoke_group_criteria_test.dart
```

**E2E device tests (requires running simulator):**

```sh
flutter test integration_test/group_recovery_e2e_test.dart
flutter test integration_test/group_recovery_cli_e2e_test.dart
flutter test integration_test/group_real_crypto_onboarding_test.dart -d <device>
flutter test integration_test/foreground_group_push_drain_test.dart -d <device>
FLUTTER_DEVICE_ID=<device> MKNOON_RELAY_ADDRESSES=<relay1,relay2,...> \
  ./scripts/run_test_gates.sh group-real-network-nightly
```

**Go-side group tests:**

```sh
cd go-mknoon && go test ./crypto/ ./internal/ ./node/ ./bridge/ ./cmd/testpeer/ -run 'Group|Announcement|Watchdog.*Group' -v
```

---

## Summary (2026-04-29 Tracked Inventory)

### Dart Tests

| Category | Files | Test Cases |
|----------|------:|-----------:|
| Domain (models, repo impl) | 14 | 105 |
| Data (DB helpers) | 7 | 88 |
| Data (DB migrations) | 12 | 38 |
| Application (use cases, listeners) | 37 | 420 |
| Presentation (widgets, screens) | 20 | 253 |
| Integration (smoke, round-trip, recovery) | 9 | 98 |
| Core (lifecycle, bridge) | 6 | 74 |
| Cross-feature (feed, orbit, push, intro, share, resilience, services, notifications) | 32 | 182 |
| E2E / Device (`integration_test/`) | 2 | 5 |
| **Dart Total** | **139** | **1263** |

### Go Tests

| Category | Files | Group-Related Tests |
|----------|------:|--------------------:|
| Crypto (`crypto/`) | 1 | 14 |
| Envelope / Wire Format (`internal/`) | 1 | 11 |
| PubSub Core (`node/pubsub*.go`) | 4 | 99 |
| Shared Security Harness (`node/group_security_harness_test.go`) | 1 | 1 |
| Group Inbox (`node/group_inbox*.go`) | 1 | 9 |
| Multi-Relay (`node/multi_relay*.go`) | 1 | 3 |
| Rendezvous (`node/rendezvous*.go`) | 1 | 2 |
| Config (`node/config*.go`) | 1 | 1 |
| Protocol Version (`node/protocol_version_test.go`) | 1 | 4 |
| Node / Relay Session / Stream (`node/node*.go`, `node/relay_session*.go`, `node/stream_timeout*.go`) | 3 | 3 |
| Bridge API (`bridge/`) | 2 | 57 |
| CLI Test Peer (`cmd/testpeer/`) | 1 | 4 |
| Integration (`integration/`) | 2 | 3 |
| **Go Total** | **20** | **211** |

### Grand Total

| | Files | Tests |
|-|------:|------:|
| **All (Dart + Go)** | **159** | **1474** |

> **Note:** Dart file counts reflect distinct `_test.dart` files. Some inventory sections cover multiple files (e.g., 4.9 covers `archive_group_use_case_test.dart` + `unarchive_group_use_case_test.dart`; 4.30 covers three reaction test files). Dart test counts are `grep`-verified against `test()`/`testWidgets()` declarations in each file. Cross-feature test counts include only the group-relevant subset from shared test files. Go test counts reflect only group-related `func Test*` functions in files that may also contain non-group tests; counts are `grep`-verified against `func Test.*[Gg]roup` patterns and manual review for files with indirect group test names. Aggregate totals reflect the tracked 2026-04-29 inventory updates plus row closure notes below; DB-002 closure evidence is recorded in the crosswalk, and aggregate totals were not fully recounted during that row closure. Report 90 GMAR-005 closure on 2026-05-03 adds final acceptance evidence without a full aggregate recount: direct GMAR suites, configured simulator media proofs, paired simulator routing/group and foreground group push smoke commands, device-pinned `all`, `completeness-check` (`712/712`), broad `flutter test`, `cd go-mknoon && go test ./...`, and `git diff --check` all passed.

## 0. Row Closure Crosswalk (2026-04-11)

| Row | Closure state | Concrete repo evidence |
|-----|---------------|------------------------|
| `GL-001` | Covered | `test/features/groups/application/create_group_use_case_test.dart` now includes `duplicate bridge group id converges to one canonical local create state`, proving two `group:create` bridge calls with the same returned group id/topic/key/epoch converge to one group row, one creator membership, canonical topic persistence, and the latest canonical key. |
| `GL-002` | Covered | GL-002 covered on 2026-04-30 by `libp2p_group_chat_missing_test_matrix_full_with_rules-session-GL-002-plan.md`: `create_group_use_case.dart` signs a canonical `group_created` initial membership payload with creator identity, admin role, joined timestamp, public keys, topic, and initial key epoch, appends it through the group event-log callback, and rolls back group/member/key state if signing or append fails. `create_group_with_members_use_case.dart`, `create_group_picker_wired.dart`, `group_message_listener.dart`, and `main.dart` wire creator private key plus `dbAppendGroupEventLogEntry`; `group_event_log_db_helpers.dart` supplies deterministic canonical payload and durable hash-chain append/load/verify behavior. `create_group_use_case_test.dart` proves persisted creator identity/initial epoch, signed payload/signature evidence, no private-key leakage in the event payload, and rollback on signing or append failure; `group_event_log_db_helpers_test.dart` proves canonical ordering, hash-chain append, idempotent replay, conflict detection, and tamper detection. Verified during closure with `flutter test --no-pub test/features/groups/application/create_group_use_case_test.dart test/core/database/helpers/group_event_log_db_helpers_test.dart` passing `+17`. Execution evidence also records `group_message_listener_test.dart` `+72`, update metadata `+6`, dissolve `+6`, membership smoke `+23`, `./scripts/run_test_gates.sh completeness-check` `697/697`, `./scripts/run_test_gates.sh groups` `+94`, and `git diff --check` passing. The broad application-suite `flutter test --no-pub test/features/groups/application` failure remains non-blocking for GL-002 because it is the preexisting unrelated MD-011 future-media replay case already scoped outside this row. |
| `GL-005` | Covered | GL-005 covered on 2026-04-30 by `trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules-session-GL-005-plan.md`: `create_group_use_case_test.dart`, `create_group_with_members_use_case_test.dart`, `group_invite_listener_test.dart`, `group_list_wired_test.dart`, `go-mknoon/node/pubsub_test.go`, and `go-mknoon/bridge/bridge_test.go` now pin trusted-private create payloads, selected-member config/publish/invite fanout, public-preview-shaped invite rejection for unknown/blocked senders, repository-backed list visibility, non-member discovery filtering before dial/use, and raw bridge `GroupCreate` rejection for unsupported public/open `groupType` values. `go-mknoon/bridge/bridge.go` rejects unsupported `groupType` before topic join. Passed evidence: the direct Flutter owner suites including `handle_incoming_group_invite_use_case_test.dart` and `group_membership_smoke_test.dart`, targeted Go node `GL005\|GroupRendezvousNamespace\|GroupTopicAndRendezvousNamespace\|FilterDiscoveredGroupMembers\|DiscoverAndConnectGroupPeers\|GroupDiscovery`, bridge `GroupCreate\|GroupJoinTopic`, `./scripts/run_test_gates.sh groups`, and `git diff --check`. The broad Go node `Group\|PubSub\|Rendezvous` regex failed only the known unrelated LP-006 `TestPublishGroupMessage_ReturnsPeerCountZero_WhenNoPeers` sender/transport mismatch path. |
| `GL-008` | Covered | GL-008 covered on 2026-04-30 by `libp2p_group_chat_missing_test_matrix_full_with_rules-session-GL-008-plan.md`. `group_key_update_listener.dart` now returns for missing groups with `GROUP_KEY_UPDATE_LISTENER_GROUP_NOT_FOUND` and dissolved groups with `GROUP_KEY_UPDATE_LISTENER_GROUP_DISSOLVED` before `group:updateKey`, event-log append, or key save; `group_key_update_listener_test.dart` proves those missing/dissolved direct key-update paths keep bridge state, event-log state, and stored keys unchanged. `group_message_listener_test.dart` proves old `group_metadata_updated`, `member_added`, `member_role_updated`, and `key_rotated` replay after `group_dissolved` cannot mutate metadata, members, keys, or visible messages, and old system events after local delete do not recreate group/member/key/message rows. Existing dissolve/delete/rejoin/smoke coverage still proves durable dissolve fields, repeated dissolve idempotency, dissolved local cleanup, and dissolved-topic rejoin suppression. Plan-recorded gates passed: `group_key_update_listener_test.dart` `+16`, `group_message_listener_test.dart` `+74`, `dissolve_group_use_case_test.dart` `+6`, `delete_group_and_messages_use_case_test.dart` `+3`, `rejoin_group_topics_use_case_test.dart` `+18`, `group_membership_smoke_test.dart` `+23`, `./scripts/run_test_gates.sh groups` `+94`, `./scripts/run_test_gates.sh completeness-check` `697/697`, and `git diff --check`. |
| `GL-009` | Covered | GL-009 covered on 2026-04-30 by `libp2p_group_chat_missing_test_matrix_full_with_rules-session-GL-009-plan.md`. `group_config_payload.dart` owns the canonical metadata actor-event payload, signed-envelope fields, and equivalence checks; `group_info_wired.dart` signs admin metadata edits with `payload.sign` before local persistence, publish, or inbox-store and embeds `actorEvent` without leaking private keys; `group_message_listener.dart` verifies `actorEvent` with `payload.verify` before event-log append, metadata mutation, bridge config sync, or timeline insertion. `group_message_listener_test.dart` proves unsigned, signed-payload mismatch, invalid signature, stale/state-hash tamper, and valid signed metadata paths; `group_info_wired_test.dart` proves signed publish payloads, canonical signed content, no private-key leakage, and signing-failure abort; `update_group_metadata_use_case_test.dart` keeps deterministic `configVersion` and canonical `stateHash` proof; `group_resume_recovery_test.dart` now signs the repeated-metadata recovery fixture and proves final metadata convergence with stale replay ignored. Passed evidence: listener `+77`, wired `+28`, update metadata `+6`, create group `+13`, dissolve `+6`, membership smoke `+23`, full migration chain `+6`, focused metadata convergence `+1` with `payload.sign` and Bob/Charlie `payload.verify`, `./scripts/run_test_gates.sh completeness-check` `697/697`, `./scripts/run_test_gates.sh groups` `+94`, `flutter test --no-pub test/features/groups/integration` `+116`, and scoped `git diff --check`. The plan-recorded broad application failure is unrelated MD-011 future-media replay and non-blocking for GL-009. |
| `LP-001` | Covered | `go-mknoon/node/pubsub_test.go` now includes `TestGroupTopicAndRendezvousNamespace_DoNotUseHumanReadableMetadata`, proving topic names and rendezvous namespaces equal `/mknoon/group/<groupId>` and omit sensitive group name/description strings. `TestJoinGroupTopic_LogOmitsHumanReadableMetadata` proves the join log omits sensitive human-readable metadata after `go-mknoon/node/pubsub.go` removed the prior `config.Name` log field. |
| `LP-002` | Covered | LP-002 covered on 2026-04-30 by `trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules-session-LP-002-plan.md`. `go-mknoon/node/pubsub_authorization_forward_test.go` adds `TestLP002UnauthorizedRawPubSubRejectsBeforeAcceptAndForward`, proving a live X-B-C raw PubSub topology rejects stale/removed X on B before accepted/decrypt/parse events and does not forward to C for unauthorized message, reaction, membership, metadata, and key-rotation payloads. The same file adds `TestLP002UnauthorizedRejectDiagnosticsArePrivacySafeAndRateLimited`, proving validator reject diagnostics are hashed, privacy-safe, and rate-limited; `go-mknoon/node/pubsub.go` and `go-mknoon/node/node.go` implement those diagnostics without changing validation accept/reject semantics; `go-mknoon/node/pubsub_test.go` keeps `TestGroupTopicValidator_RejectsUnauthorizedEventFamiliesBeforeForward` as pure validator event-family proof. Focused LP-002 Go proof, `go test ./cmd/testpeer -run 'Group\|PubSub\|Rendezvous\|Protocol\|Inbox' -v`, and `git diff --check` passed. App-owned peer scoring remains non-applicable because `go-mknoon/node` has no `WithPeerScore`/`PeerScoreParams`; named Flutter gates were not run because no Dart-visible group behavior or bridge API contract changed. The broad owner command still has unrelated dirty-worktree sender/transport mismatch failures in `TestPublishGroupMessage_ReturnsPeerCountZero_WhenNoPeers` and `TestGroupPublish_ResponseIncludesTopicPeers`, outside LP-002. |
| `LP-003` | Covered | LP-003 covered on 2026-05-01 by `trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules-session-LP-003-plan.md`. `go-mknoon/node/pubsub_unsubscribe_exit_paths_test.go` adds `TestLP003LeaveGroupTopicStopsLiveDeliveryAfterExit`, proving with live Go/libp2p PubSub that an exited peer receives pre-exit traffic, calls `LeaveGroupTopic`, loses topic, subscription, subscription context, discovery context, config, and key state, receives no post-exit normal message, reaction, parse-failure, or decrypt-failure events, and fails closed on post-exit message/reaction publish with `group not joined`. Existing `go-mknoon/node/pubsub_test.go` keeps local cleanup coverage in `TestLeaveGroupTopic_RemovesPubSubStateAndBlocksFuturePublish` and discovery cancellation coverage in `TestLeaveGroupTopic_CancelsDiscoveryContext`. `leave_group_use_case_test.dart`, `delete_group_and_messages_use_case_test.dart`, and `group_message_listener_test.dart` now pin normal leave, active delete, self-removal/member_removed, replayed `group_dissolved`, and dissolved local-only cleanup without a second `group:leave`; focused offline-inbox replay and `group_membership_smoke_test.dart` keep removed-member cleanup/cutoff behavior green. Closure reruns passed the focused Go proof, the three focused Dart owner files, the focused offline-inbox member_removed rerun, `group_membership_smoke_test.dart`, and `git diff --check`. No LP-003 production code changed. Ban is documented as the current `member_removed` mapping because scoped execution found no first-class group ban surface. Known unrelated caveats remain outside LP-003: full offline inbox still has the MD-011 future-media replay failure, and the broad Go bridge owner slice still has the `TestGroupPublish_ResponseIncludesTopicPeers` peer-mismatch failure; `group-real-network-nightly` was not run because relay env is unset. |
| `LP-006` | Partial | `go-mknoon/node/pubsub_test.go` includes `TestGroupDiscoveryCycle_NoKnownPeersUsesRendezvousFallback`, and the 2026-04-30 targeted proof rerun passed that part of the direct gate. The same direct LP-006 gate now fails `TestPublishGroupMessage_ReturnsPeerCountZero_WhenNoPeers` with `publish to topic: validation failed` after a sender/transport peer mismatch rejection for `sender=sender-zero`. The row remains partial and is implementation-ready/needs code-and-test repair for the zero-peer safe-send proof, plus real bootstrap relay/device-lab fallback proof for rejoin/send from no useful known peers and the failed-fallback user-safe state. |
| `LP-007` | Partial | `go-mknoon/node/pubsub_test.go` now includes `TestGroupRelayVisibleMessageEnvelope_EncryptsContentBeforeRelay` and `TestGroupRelayVisibleReactionEnvelope_EncryptsContentBeforeRelay`, proving relay-visible raw group message and reaction envelopes omit plaintext while decrypting with the group key. `go-mknoon/node/group_inbox_test.go` extends `TestBuildGroupInboxStoreRequest_PreservesOpaqueReplayEnvelope` to prove offline inbox relay requests preserve an encrypted replay envelope without exposing message body, media key, invite token, or history text when the notification preview is safe. The row remains partial because live relay-only delivery convergence plus media metadata, invite, key-update, sync-traffic, and relay-visible capture proof are not directly proven. |
| `LP-011` | Partial | `go-mknoon/node/protocol_version_test.go` now proves chat, inbox/group inbox, rendezvous, and media protocol constants use semver-like `/.../1.0.0` IDs, current chat stream negotiation opens only `ChatProtocol` while an unsupported chat protocol ID is rejected, and group inbox store opens a local relay stream on `InboxProtocol`. Existing `TestGroupTopicValidator_NotV3Envelope` proves non-v3 group PubSub envelopes are rejected. The row remains partial because there is still no full compatible/incompatible negotiation matrix for group sync, invites, media metadata, receipts, and key-exchange streams before state mutation. |
| `LP-013` | Covered | LP-013 covered on 2026-05-01 by `trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules-session-LP-013-plan.md`. `go-mknoon/node/pubsub_delivery_test.go` now includes `TestLP013DefaultPubSubMessageIdUsesSourceAndSeqnoNotPayloadHash`, `TestLP013DuplicateWireEnvelopeWithDistinctPubSubSeqnosPreservesApplicationMessageId`, and `TestLP013ConflictingApplicationDuplicatePubSubPayloadsPreserveFirstWriterInputsForDartDedupe`, proving default PubSub IDs are source-plus-seqno instead of payload hash, duplicate identical encrypted wire envelopes preserve the application `messageId`, and conflicting duplicate app payloads still keep the same app `messageId` for Dart dedupe. Existing `TestPublishGroupMessage_DuplicateProvidedMessageIdRemainsVisibleAfterDecrypt` remains the same-provided-ID live publish anchor. `test/features/groups/application/group_message_listener_test.dart` now includes `LP013 duplicate PubSub delivery preserves first row and notification state`, proving duplicate app deliveries produce one saved row, one UI stream insertion, one local notification, one unread item, and preserve first trusted text/timestamp/status/key/quoted/media fields. Existing anchors passed: `handle_incoming_group_message_use_case_test.dart` duplicate replay with the same `messageId` ignores conflicting content; `group_resume_recovery_test.dart` same message is not duplicated if both pubsub and group inbox deliver it; `group_edge_cases_smoke_test.dart` duplicate delivery; and `group_notification_dedupe_integration_test.dart` notification dedupe. Verified commands: `cd go-mknoon && go test ./node -run 'TestLP013\|TestPublishGroupMessage_DuplicateProvidedMessageIdRemainsVisibleAfterDecrypt' -v`; `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name 'LP013'`; the focused existing duplicate anchors; `./scripts/run_test_gates.sh groups`; `flutter test --no-pub test/features/groups/integration`; and `git diff --check`. The broad Go owner command failed only known unrelated peer-mismatch tests `TestPublishGroupMessage_ReturnsPeerCountZero_WhenNoPeers` and `TestGroupPublish_ResponseIncludesTopicPeers`, with LP-013 tests passing inside that selection. No LP-013 production code changed; relay/device proof is supporting only while relay env is unset, and first-class group receipts remain out of scope because no scoped group receipt protocol exists. |
| `IJ-001` | Covered | IJ-001 covered on 2026-05-01 by `trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules-session-IJ-001-plan.md`. Production files: `lib/features/groups/domain/models/group_invite_policy.dart`, `lib/features/groups/domain/models/group_invite_payload.dart`, `lib/features/groups/domain/models/pending_group_invite.dart`, `lib/features/groups/application/send_group_invite_use_case.dart`, `lib/features/groups/application/handle_incoming_group_invite_use_case.dart`, and `lib/features/groups/application/accept_pending_group_invite_use_case.dart`. The implementation adds first-class `GroupInvitePolicy`, embeds `invitePolicy` only inside encrypted invite payload plaintext, keeps cleartext v2 envelopes to preview/routing fields, fails closed for parsing, send preflight, pending-store, direct-handle, materialization, and pending-accept repair, and derives pending expiry from the policy clamped no later than the local TTL. Exact tests: `group_invite_payload_test.dart` includes `IJ001 parses a first-class encrypted invite policy` and `IJ001 rejects missing or contradictory first-class invite policy`; `pending_group_invite_test.dart` includes `IJ001 clamps sender policy expiry no later than local TTL`; `send_group_invite_use_case_test.dart` includes `keeps join material and policy details inside encrypted invite payload` and `IJ001 returns invalidPayload before encryption or delivery when policy derivation fails`; `store_pending_group_invite_use_case_test.dart` includes `IJ001 rejects missing first-class policy before pending or group state` and `IJ001 rejects contradictory policy before pending or group state`; `handle_incoming_group_invite_use_case_test.dart` includes `IJ001 rejects invite missing first-class policy before group state or join` and `IJ001 rejects contradictory policy before group state or join`; `accept_pending_group_invite_use_case_test.dart` includes `IJ001 invalid pending policy stays pending for repair without state or join` and `IJ001 contradictory pending policy stays pending for repair without state or join`; `invite_round_trip_test.dart` proves both `full invite round-trip: admin sends invite -> receiver processes it -> group is persisted` and `GroupInviteListener stores pending invite and explicit accept completes the join flow` preserve the encrypted policy privately; `group_new_member_onboarding_test.dart` remained green for the authorized post-join state/history boundary. Commands relied on: RED `flutter test --no-pub test/features/groups/domain/models/group_invite_payload_test.dart test/features/groups/domain/models/pending_group_invite_test.dart` failed before production edits because `GroupInvitePolicy`/`invitePolicy` did not exist, then passed after implementation (`+21`); `flutter test --no-pub test/features/groups/application/send_group_invite_use_case_test.dart test/features/groups/application/store_pending_group_invite_use_case_test.dart test/features/groups/application/handle_incoming_group_invite_use_case_test.dart test/features/groups/application/accept_pending_group_invite_use_case_test.dart` passed (`+57`); `flutter test --no-pub test/features/groups/application/*invite*_test.dart` passed (`+72`); `flutter test --no-pub test/features/groups/integration/invite_round_trip_test.dart` passed (`+12`); `flutter test --no-pub test/features/groups/integration/group_new_member_onboarding_test.dart` passed (`+6`); `./scripts/run_test_gates.sh groups` passed (`+94`); `flutter test --no-pub test/features/groups/integration` passed (`+116`); controller reran `dart format --output=none --set-exit-if-changed` on IJ-001 Dart files, `git diff --check`, and the focused IJ-001 domain/application commands. Supporting `group-real-network-nightly` was not run because `FLUTTER_DEVICE_ID` and `MKNOON_RELAY_ADDRESSES` are unset. Current peer-bound `allowedDevices: [recipientPeerId]` is accepted for IJ-001 only; separate account/device policy remains outside the shipped Peer ID invite contract. Signed inviter auth, revocation, and reuse/replay remain IJ-002, IJ-003, and IJ-005 respectively; auto-join is covered by IJ-009; concurrent joins and history entitlement remain IJ-010 and IJ-011 respectively. |
| `IJ-002` | Covered | IJ-002 covered on 2026-05-01 by `trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules-session-IJ-002-plan.md`. Production files: `lib/features/groups/domain/models/group_invite_payload.dart`, `lib/features/groups/application/group_invite_auth.dart`, `lib/features/groups/application/send_group_invite_use_case.dart`, `lib/features/groups/application/handle_incoming_group_invite_use_case.dart`, `lib/features/groups/application/accept_pending_group_invite_use_case.dart`, `lib/features/groups/application/create_group_with_members_use_case.dart`, `lib/features/groups/domain/models/pending_group_invite.dart`, `lib/features/groups/presentation/screens/contact_picker_wired.dart`, `lib/features/groups/presentation/screens/group_list_wired.dart`, and `lib/features/orbit/presentation/screens/orbit_wired.dart`. Test helper: `test/core/bridge/fake_bridge.dart`. The implementation creates a signed canonical invite attestation before encryption, keeps the signature and policy inside encrypted invite plaintext, verifies receive/listener/direct-accept paths with the trusted contact public key, authorizes the inviter from the signed group snapshot, and revalidates at accept time so tampered, unsigned, unauthorized, invite-disabled, or removed-inviter payloads are rejected before pending/group/key/join/consumption side effects. Exact tests: `group_invite_payload_test.dart` includes `IJ002 requires signed invite attestation and rejects canonical mismatch`; `send_group_invite_use_case_test.dart` includes `IJ002 signs canonical invite payload before encryption and delivery` and `IJ002 returns invalidPayload without encryption or delivery when invite signing fails`; `handle_incoming_group_invite_use_case_test.dart` includes `IJ002 rejects invalid invite signature before group state or join`, `IJ002 rejects tampered signed invite fields before group state or join`, and `IJ002 rejects signed non-admin or removed inviters before state or join`; `group_invite_listener_test.dart` includes `IJ002 does not store pending invite when signature verification fails` and `IJ002 does not store pending invite from unauthorized or removed inviter`; `accept_pending_group_invite_use_case_test.dart` includes `IJ002 tampered persisted signed invite is deleted without state or join` and `IJ002 persisted signed snapshot must still authorize inviter at accept time`; `add_group_member_use_case_test.dart` and `create_group_with_members_use_case_test.dart` remained green for add/create authorization and invite fan-out boundaries; `invite_round_trip_test.dart` and `group_new_member_onboarding_test.dart` remained green for signed invite round trip and authorized onboarding. Commands relied on: RED `flutter test --no-pub test/features/groups/domain/models/group_invite_payload_test.dart test/features/groups/application/send_group_invite_use_case_test.dart test/features/groups/application/handle_incoming_group_invite_use_case_test.dart test/features/groups/application/accept_pending_group_invite_use_case_test.dart test/features/groups/application/group_invite_listener_test.dart` failed at 2026-05-01 02:07 CEST before production edits because invite signatures/signing/verification and accept-time authorization were missing; exact format command passed with `0 changed`; `flutter test --no-pub test/features/groups/domain/models/group_invite_payload_test.dart` passed (`+18`); `flutter test --no-pub test/features/groups/application/send_group_invite_use_case_test.dart test/features/groups/application/handle_incoming_group_invite_use_case_test.dart test/features/groups/application/accept_pending_group_invite_use_case_test.dart test/features/groups/application/group_invite_listener_test.dart` passed (`+69`); `flutter test --no-pub test/features/groups/application/*invite*_test.dart` passed (`+81`); `flutter test --no-pub test/features/groups/application/add_group_member_use_case_test.dart test/features/groups/application/create_group_with_members_use_case_test.dart` passed (`+30`); `flutter test --no-pub test/features/groups/integration/invite_round_trip_test.dart` passed (`+12`); `flutter test --no-pub test/features/groups/integration/group_new_member_onboarding_test.dart` passed (`+6`); `./scripts/run_test_gates.sh groups` passed (`+94`); `flutter test --no-pub test/features/groups/integration` passed (`+116`); `git diff --check` passed. Supporting `group-real-network-nightly` was not run because `FLUTTER_DEVICE_ID` and `MKNOON_RELAY_ADDRESSES` are unset. Stale/removed inviter rejection is closed for the self-contained signed snapshot plus accept-time trusted contact revalidation; no durable historical membership-index semantics are claimed. Revocation delivery is covered by IJ-003; direct invite replay/reuse is covered separately by IJ-005; auto-join is covered by IJ-009; concurrent joins are covered by IJ-010; separate account/device registry remains outside the shipped Peer ID invite contract; broad event-family signature parity remains EK-004. |
| `IJ-003` | Covered | IJ-003 covered on 2026-05-01 by `trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules-session-IJ-003-plan.md`. Production files: `lib/features/groups/domain/models/group_invite_revocation_payload.dart`, `lib/features/groups/application/group_invite_auth.dart`, `lib/features/groups/application/revoke_pending_group_invite_use_case.dart`, `lib/features/groups/application/handle_incoming_group_invite_use_case.dart`, `lib/features/groups/application/group_invite_listener.dart`, and `lib/core/services/incoming_message_router.dart`. The implementation adds signed canonical encrypted `group_invite_revocation` payloads, signs before encryption, direct-sends with inbox fallback, validates trusted signer/auth snapshot plus recipient binding, expiry, transport sender, and canonical signature before mutation, then stores a tombstone and deletes only the matching pending invite. Exact tests: `group_invite_revocation_payload_test.dart` covers privacy, tamper, binding, and expiry; `revoke_pending_group_invite_use_case_test.dart` covers sign-before-encrypt direct delivery, inbox fallback, and sender failure paths; `group_invite_listener_test.dart` covers listener dispatch, tombstone storage, pending refresh, and invalid signature fail-closed handling; `store_pending_group_invite_use_case_test.dart` covers delayed direct/mailbox original invite rejection after tombstone; `accept_pending_group_invite_use_case_test.dart` covers revoked accept with no pending/group/key/join/consumed side effects; `incoming_message_router_test.dart` covers router dispatch; `invite_round_trip_test.dart` covers integration-level revoked invite replay rejection. Preservation tests for invite payload, send, handle, and onboarding remained green. Commands relied on: RED `flutter test --no-pub test/features/groups/domain/models/group_invite_revocation_payload_test.dart test/features/groups/application/revoke_pending_group_invite_use_case_test.dart test/features/groups/application/group_invite_listener_test.dart test/features/groups/application/store_pending_group_invite_use_case_test.dart test/features/groups/application/accept_pending_group_invite_use_case_test.dart test/core/services/incoming_message_router_test.dart test/features/groups/integration/invite_round_trip_test.dart` failed before production because the revocation payload/API/router path was missing, then passed after implementation; `flutter test --no-pub test/features/groups/domain/models/group_invite_payload_test.dart test/features/groups/domain/models/group_invite_revocation_payload_test.dart` passed; `flutter test --no-pub test/features/groups/application/revoke_pending_group_invite_use_case_test.dart test/features/groups/application/group_invite_listener_test.dart test/features/groups/application/store_pending_group_invite_use_case_test.dart test/features/groups/application/accept_pending_group_invite_use_case_test.dart test/features/groups/application/send_group_invite_use_case_test.dart test/features/groups/application/handle_incoming_group_invite_use_case_test.dart` passed; `flutter test --no-pub test/features/groups/application/*invite*_test.dart` passed; `flutter test --no-pub test/core/services/incoming_message_router_test.dart`, `flutter test --no-pub test/features/groups/integration/invite_round_trip_test.dart`, `flutter test --no-pub test/features/groups/integration/group_new_member_onboarding_test.dart`, `./scripts/run_test_gates.sh groups`, `flutter test --no-pub test/features/groups/integration`, QA rerun smoke suites, and `git diff --check` passed. Supporting `group-real-network-nightly` was not run because `FLUTTER_DEVICE_ID` and `MKNOON_RELAY_ADDRESSES` are unset. This row does not close TP-SMOKE-01, invite replay/reuse policy, auto-join denial, concurrent joins, richer device binding, or broad event-family signature parity. |
| `IJ-005` | Covered | IJ-005 covered on 2026-05-01 by `trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules-session-IJ-005-plan.md` for direct signed invite credential reuse/replay. Production files: `lib/features/groups/domain/models/group_invite_policy.dart`, `lib/features/groups/domain/models/group_invite_payload.dart`, `lib/features/groups/application/send_group_invite_use_case.dart`, `lib/features/groups/application/handle_incoming_group_invite_use_case.dart`, `lib/features/groups/application/group_invite_listener.dart`, and `lib/features/groups/application/accept_pending_group_invite_use_case.dart`. The implementation adds explicit signed/encrypted `singleUse` and `multiUse` reuse policy, defaults direct sends to `singleUse`, supports an explicit `multiUse` direct send path, fails closed for missing/unknown/contradictory reuse policy, checks single-use consumption tombstones and expiry before pending/accept side effects, rejects direct replay to a different peer/device when local identity is available, and keeps multi-use replay idempotent without duplicate local membership, key, join, pending, or duplicate-group side effects. Direct evidence: `group_invite_payload_test.dart`, `send_group_invite_use_case_test.dart`, `store_pending_group_invite_use_case_test.dart`, `accept_pending_group_invite_use_case_test.dart`, `group_invite_listener_test.dart`, `handle_incoming_group_invite_use_case_test.dart`, `invite_round_trip_test.dart`, and onboarding/groups integration gates. Commands relied on: RED focused command failed before production because `GroupInviteReusePolicy`, `GroupInvitePolicy.reusePolicy`, and `sendGroupInvite(reusePolicy:)` were missing; focused IJ-005 command passed (`+81`); invite wildcard passed (`+96`) after listener compatibility fix; onboarding passed (`+6`); `./scripts/run_test_gates.sh groups` passed (`+96`); `flutter test --no-pub test/features/groups/integration` passed (`+118`); `git diff --check` passed. Supporting `group-real-network-nightly` was unconfigured with `FLUTTER_DEVICE_ID is required for Group Real-Network Nightly Gate.` and is non-blocking. Residual caveats: first-class link invite creation/claim remains prerequisite-owned or product-scope unsupported until a link-token surface exists, and shared account-wide cross-device consumption remains outside the shipped Peer ID invite contract and would require a separate account/device/shared-state model. |
| `IJ-009` | Covered | IJ-009 covered on 2026-05-01 by `trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules-session-IJ-009-plan.md`. Production files: `lib/features/groups/application/handle_incoming_group_invite_use_case.dart`, `lib/features/groups/application/group_invite_listener.dart`, and `lib/main.dart`. The implementation requires a current non-empty local peer id before direct or pending invite resolution, rejects mismatched `recipientPeerId`, rejects invites whose `invitePolicy.allowedDevices` does not contain the local peer id, and wires persisted identity into `GroupInviteListener`; rejection happens before pending invite rows, group rows, member/key state, notifications, or `group:join`. Exact tests: `handle_incoming_group_invite_use_case_test.dart` includes IJ-009 coverage for rejecting signed invites when local peer identity is unavailable before group/key/join state; `store_pending_group_invite_use_case_test.dart` includes IJ-009 coverage for rejecting missing and mismatched local peer identity before pending/group/key/join state; `group_invite_listener_test.dart` includes IJ-009 coverage for copied signed invite rejection and identity-unavailable listener rejection before pending stream, pending row, group/key, notification, or `group:join` state. Preservation tests in `accept_pending_group_invite_use_case_test.dart`, `join_group_use_case_test.dart`, `invite_round_trip_test.dart`, and `group_membership_smoke_test.dart` remained green. Commands relied on: RED focused command `flutter test --no-pub test/features/groups/application/handle_incoming_group_invite_use_case_test.dart test/features/groups/application/store_pending_group_invite_use_case_test.dart test/features/groups/application/group_invite_listener_test.dart` failed before production edits (`+54 -3`), then passed after implementation (`+57`); `dart format --output=none --set-exit-if-changed` on IJ-009 Dart files passed with `Formatted 9 files (0 changed)`; `flutter test --no-pub test/features/groups/application/accept_pending_group_invite_use_case_test.dart test/features/groups/application/join_group_use_case_test.dart` passed (`+19`); `flutter test --no-pub test/features/groups/application/*invite*_test.dart` passed (`+100`); `flutter test --no-pub test/features/groups/integration/invite_round_trip_test.dart` passed (`+14`); `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart` passed (`+23`); `./scripts/run_test_gates.sh groups` passed (`+96`); `git diff --check` passed. Supporting `group-real-network-nightly` failed only because `FLUTTER_DEVICE_ID` is unset. First-class link invite creation/claim remains out of scope until a link-token surface exists; first-class shared account/device semantics remain outside the shipped Peer ID invite contract; IJ-010 concurrent join convergence is covered separately; EK-004 broad event-family signature parity remains a separate row; TP-SMOKE-01 remains supporting-only. |
| `IJ-010` | Covered | IJ-010 covered on 2026-05-01 by `trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules-session-IJ-010-plan.md`. `test/features/groups/integration/group_membership_smoke_test.dart` adds `IJ010 concurrent direct invite accepts converge membership epoch and delivery`, proving with the fake-network multi-user harness that an admin and existing member converge after a batch `members_added` authoritative config, Charlie and Dave accept distinct signed direct pending invites concurrently, both joiners issue `group:join` and subscribe only after acceptance, admin/existing/Charlie/Dave converge on exactly the intended peer IDs and roles, all joined participants hold the same latest key epoch and encrypted key material, both pending invite rows clear with consumed tombstones, uninvited Eve has no group/key/subscription/messages, and post-join sends from both joiners are delivered to the existing member and trusted participants. Preservation evidence keeps `invite_round_trip_test.dart` coverage for `concurrent pending accepts converge members, key epoch, and sendability` green. Commands relied on: `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'IJ010'` passed (`+1`); `flutter test --no-pub test/features/groups/integration/invite_round_trip_test.dart --plain-name 'concurrent pending accepts converge members, key epoch, and sendability'` passed (`+1`); `flutter test --no-pub test/features/groups/application/*invite*_test.dart` passed (`+100`); `flutter test --no-pub test/features/groups/integration/invite_round_trip_test.dart` passed (`+14`); `flutter test --no-pub test/features/groups/integration/group_new_member_onboarding_test.dart` passed (`+6`); `./scripts/run_test_gates.sh groups` passed (`+97`); `git diff --check` passed. Supporting `group-real-network-nightly` was not run because `FLUTTER_DEVICE_ID` and `MKNOON_RELAY_ADDRESSES` are unset. The authorized history/state entitlement is covered by IJ-011; separate account/device registry, EK-004 broad event signatures, RP conflict semantics, and first-class real relay/device nightly proof are not closed by IJ-010. |
| `IJ-011` | Covered | IJ-011 covered on 2026-05-01 by `trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules-session-IJ-011-plan.md`. `group_new_member_onboarding_test.dart` now tightens `new member receives current metadata and roles without pre-join history`, proving a newly added member receives the latest metadata, creation fields, membership set, role snapshot, and explicit permission overrides after pre-join metadata and role changes. The test pins Charlie's reader role plus custom `GroupMemberPermissions` (`inviteMembers: false`, `editMetadata: false`, `pinMessages: true`) in Bob's new-member snapshot, verifies Bob's own member row has no custom permission overrides, verifies Bob has no pre-join message/timeline rows before post-join traffic, and verifies a post-join message is delivered while pre-join history remains inaccessible. Existing onboarding tests cover no pre-join text/media backfill, post-join media descriptors/downloads, post-join reactions without pre-join reaction state, quoted pre-join parent fallback, and deterministic add/send boundaries; `invite_round_trip_test.dart` preserves future-only history and post-join replay. Commands relied on: focused IJ-011 onboarding test passed (`+1`); full `group_new_member_onboarding_test.dart` passed (`+6`); `invite_round_trip_test.dart` passed (`+14`); `flutter test --no-pub test/features/groups/application/*invite*_test.dart` passed (`+100`); `./scripts/run_test_gates.sh groups` passed (`+97`); `git diff --check` passed. Supporting `group-real-network-nightly` was not run because `FLUTTER_DEVICE_ID` and `MKNOON_RELAY_ADDRESSES` are unset. First-class group pinned-message state is not a shipped group-chat surface in this repo, so IJ-011 covers the current pin-related group permission state (`pinMessages`) but does not claim product-level group pinned-item sync. IJ-013 is now covered for shipped Peer ID / `allowedDevices` invite binding and IJ-014 now covers shipped inline group-key repair state; separate account/device registry, RP authorization/conflict rows, EK signatures/key rows, and first-class real relay/device proof remain outside IJ-011. |
| `IJ-012` | Partial | `group_multi_device_convergence_test.dart` now includes `sibling device stays one member while new human admission adds a distinct member`, proving same-peer sibling devices share joined group state without a duplicate human membership row, while a separately invited peer becomes a distinct member across phone, sibling device, existing member, and new member repos and can send after admission. Existing policy and invite tests prove membership/metadata/history are shared only after joined-device materialization and pending invite review is device-local. The row remains partial because self-authenticated sibling-device admission, admin device approval, first-class per-device key packages, and live 3-party/device proof are absent. |
| `IJ-013` | Covered | IJ-013 covered on 2026-05-01 by `trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules-session-IJ-013-plan.md`. `accept_pending_group_invite_use_case.dart` now revalidates persisted pending invites against the current local identity (`senderPeerId`) before reuse checks, signature authorization, materialization, group key persistence, inbox drain, or `group:join` side effects: `recipientPeerId` must match and `invitePolicy.allowedDevices` must contain the local peer id, otherwise the pending row is deleted and `invalidPayload` is returned. `accept_pending_group_invite_use_case_test.dart` adds `IJ013 copied pending invite rejects wrong local identity before state or join`, proving a copied pending invite creates no pending row, consumed tombstone, group, key, message, or `group:join` side effect on the wrong local identity. Existing row-adjacent coverage remains green: `handle_incoming_group_invite_use_case_test.dart` proves matching bound invites accept and v1/v2 wrong-recipient invites reject before state; `store_pending_group_invite_use_case_test.dart` proves missing or mismatched local identity is not stored; `group_invite_listener_test.dart` proves copied signed invites do not enter pending state; `send_group_invite_use_case_test.dart` proves encrypted invite payloads bind `recipientPeerId` and `allowedDevices`. Commands relied on: focused IJ-013 accept-pending test passed (`+1`); handle recipient-peer tests passed (`+3`); store local-identity test passed (`+1`); listener copied-invite test passed (`+1`); `flutter test --no-pub test/features/groups/application/*invite*_test.dart` passed (`+101`); `invite_round_trip_test.dart` passed (`+14`); `group_new_member_onboarding_test.dart` passed (`+6`); `./scripts/run_test_gates.sh groups` passed (`+97`); `git diff --check` passed. Supporting `group-real-network-nightly` was not run because `FLUTTER_DEVICE_ID` and `MKNOON_RELAY_ADDRESSES` are unset. Current trusted-private invites bind to the shipped local libp2p Peer ID / `allowedDevices` identity unit; IJ-014 now covers shipped inline group-key repair state. IJ-013 does not claim a separate account/device registry, sibling-device approval, EK/RP signatures/authorization rows, TP-SMOKE real-device proof, or first-class real relay/device proof. |
| `IJ-014` | Covered | IJ-014 covered on 2026-05-01 by `trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules-session-IJ-014-plan.md`. `handle_incoming_group_invite_use_case.dart` now classifies explicit invalid, stale, or undecryptable join-material `BridgeCommandException` failures, rolls back partially materialized group, member, and group-key state, emits `GROUP_INVITE_HANDLE_JOIN_MATERIAL_REPAIR_PENDING`, and returns a repairable invalid-payload outcome instead of clearing the pending invite into an unusable joined group. `accept_pending_group_invite_use_case_test.dart` adds IJ-014 tests proving repairable join-material failure keeps the pending invite row, creates no consumed tombstone, group, member, key, message, publish, mailbox drain, or successful join side effect, and can retry successfully after fresh key material. `handle_incoming_group_invite_use_case_test.dart` proves direct materialization rolls back group/member/key state on a repairable welcome decrypt failure. `group_list_wired_test.dart` proves the pending invite remains visible and the UI shows the fresh key-material warning; full `group_list_wired_test.dart` also keeps valid accept and generic `bridgeError` behavior green. Commands relied on: focused IJ-014 accept tests passed (`+2`); focused IJ-014 direct handler test passed (`+1`); focused IJ-014 UI test passed (`+1`); adjacent UI preservation tests passed (`+2`); `flutter test --no-pub test/features/groups/application/*invite*_test.dart` passed (`+104`); `invite_round_trip_test.dart` passed (`+14`); `group_new_member_onboarding_test.dart` passed (`+6`); full `group_list_wired_test.dart` passed (`+17`); `./scripts/run_test_gates.sh groups` passed (`+97`); `git diff --check` passed. Supporting `group-real-network-nightly` was not run because `FLUTTER_DEVICE_ID` and `MKNOON_RELAY_ADDRESSES` are unset. IJ-014 does not claim first-class MLS welcome/key-package transport, a separate device identity registry, sibling-device approval, live three-party device proof, or first-class real relay/device proof. |
| `RP-002` | Partial | Migration 057 adds durable `permissions_json` storage for group members. `group_members_db_helpers_test.dart`, `057_group_member_permissions_test.dart`, and `group_repository_impl_test.dart` prove helper, migration, and repository persistence of permission overrides. `add_group_member_use_case_test.dart`, `remove_group_member_use_case_test.dart`, `update_group_member_role_use_case_test.dart`, and `rotate_and_distribute_group_key_use_case_test.dart` prove writer-role overrides can grant invite, remove, manage-role, and rotate capabilities while explicit false overrides deny admins. The row remains partial because pin/delete capabilities, receive-side remote enforcement, stale permission races, escalation protection, and live 3-party/device coverage are not directly proven. |
| `RP-003` | Partial | `leave_group_use_case_test.dart` proves a sole admin cannot leave while admin leave succeeds when another admin remains; `update_group_member_role_use_case_test.dart` proves the last admin cannot be demoted while self-demotion succeeds with another admin; `remove_group_member_use_case_test.dart` now proves last-admin removal is blocked before member deletion or bridge sync while removing an admin succeeds when another admin remains. The row remains partial because owner roles, ownership handoff APIs, simultaneous owner-transfer conflict handling, receive-side owner enforcement, and live 3-party/device proof are absent. |
| `RP-004` | Covered | RP-004 covered on 2026-05-01 by `trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules-session-RP-004-plan.md`. `GroupKeyUpdateListener` now re-authorizes direct `group_key_update` receive messages by requiring `message.from` to be a current group member with effective `rotateKeys` permission before `group:updateKey`, event-log append, or key save. `group_key_update_listener_test.dart` adds RP004 tests proving an unauthorized writer direct key update is ignored before bridge update, log, or key save while a writer with explicit `rotateKeys` override is accepted; the full listener file remains green. `member_removal_integration_test.dart` now seeds authorized sender membership for direct key-update receive fixtures and passes under the new auth contract. Existing RP-004 evidence remains green: local guards cover add, remove, role update, key rotation, metadata edit, send, send reaction, and remove reaction, while `group_message_listener_test.dart` proves writer-originated receive-side mutation events for `member_added`, `members_added`, `member_removed`, `member_role_updated`, `group_metadata_updated`, and `group_dissolved` leave state and bridge side effects unchanged. Commands relied on: focused RP004 key-update tests passed (`+2`); full `group_key_update_listener_test.dart` passed (`+18`); generic receive mutation guard passed (`+1`); focused local mutation guard tests each passed (`+1`); `member_removal_integration_test.dart` passed (`+5`); `group_membership_smoke_test.dart` passed (`+24`); `./scripts/run_test_gates.sh groups` passed (`+97`); `flutter test --no-pub test/features/groups/integration` passed (`+119`); `git diff --check` passed. The broad `flutter test --no-pub test/features/groups/application` command still fails unrelated existing MD-011 drain-inbox media replay coverage, which also fails in isolation and is not caused by RP-004. Supporting `group-real-network-nightly` was not run because `FLUTTER_DEVICE_ID` and `MKNOON_RELAY_ADDRESSES` are unset. RP-004 covers shipped role/metadata/key/send/reaction/invite/removal mutation paths; first-class group pin, message edit/delete, and ban product flows are not shipped and are not claimed by this row. |
| `RP-005` | Covered | RP-005 covered on 2026-05-01 by `trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules-session-RP-005-plan.md`. `GroupMessageListener` now rechecks current sender membership/role state for receive-side membership and metadata mutation events instead of trusting stored `createdBy` after a creator is demoted or removed. `group_message_listener_test.dart` adds `RP005 demoted creator receive-side mutations are rejected before side effects`, proving demoted creator-originated add, remove, role, and metadata mutation events leave group/member/timeline state unchanged and avoid `payload.verify`/`group:updateConfig` side effects. Existing local stale queued-action guards remain green for add, remove, role update, key rotation, metadata edit, send, and failed-message retry; existing receive stale watermark tests remain green for older metadata and role/member events after newer state. Commands relied on: focused RP005 listener test passed (`+1`); metadata/role watermark tests passed (`+1` each); focused local stale guard tests passed (`+1` each); full `group_message_listener_test.dart` passed (`+81`); `group_membership_smoke_test.dart` passed (`+24`); `./scripts/run_test_gates.sh groups` passed (`+97`); `flutter test --no-pub test/features/groups/integration` passed (`+119`). The broad `flutter test --no-pub test/features/groups/application` command still fails unrelated existing MD-011 drain-inbox media replay coverage, and the MD-011 test fails in isolation. Supporting `group-real-network-nightly` was not run because `FLUTTER_DEVICE_ID` and `MKNOON_RELAY_ADDRESSES` are unset. RP-005 covers shipped local stale-action rechecks and receive-side stale mutation rejection; broad cryptographic actor-signature proof, first-class real transport/device proof, and unshipped product surfaces remain outside this row. |
| `RP-006` | Covered | RP-006 covered on 2026-05-01 by `trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules-session-RP-006-plan.md`. `group_role_update_authorization.dart` now blocks non-admin actors from assigning admin or changing an existing admin role while preserving the existing unheld-permission grant rejection. `update_group_member_role_use_case.dart` now loads the target member before local escalation checks and passes current target role and permissions into the shared helper before mutation or bridge sync. `group_message_listener.dart` uses that helper for receive-side `member_role_updated`, so replayed limited-manager role changes cannot promote to admin, demote or touch an existing admin, or grant unheld permissions before member state, timeline rows, or `group:updateConfig` side effects. Direct evidence: `update_group_member_role_use_case_test.dart` covers local promote denial, admin-demotion denial, and allowed reader-to-writer override; `group_message_listener_test.dart` covers receive-side promote denial, admin-demotion denial, and unheld-permission denial; `drain_group_offline_inbox_use_case_test.dart` self-removal replay fixtures now include the current admin sender membership required by stricter receive-side authorization. Commands relied on: focused RP-006 local and listener tests passed; full `update_group_member_role_use_case_test.dart` passed (`+11`); full `group_message_listener_test.dart` passed (`+82`); focused self-removal replay fixtures passed; `group_membership_smoke_test.dart` passed (`+24`); `./scripts/run_test_gates.sh groups` passed (`+97`); `flutter test --no-pub test/features/groups/integration` passed (`+119`). Broad `flutter test --no-pub test/features/groups/application --reporter json` still fails only unrelated existing MD-011 future-media replay coverage. Supporting `group-real-network-nightly` was not run because relay/device env is unset. RP-006 does not claim a first-class permission-edit UI/API, broad cryptographic actor-signature matrix, account/device registry, real-device proof, or unshipped pin/delete product surfaces. |
| `RP-010` | Partial | `group_multi_device_convergence_test.dart` now includes `device-local unsubscribe preserves member account and sibling delivery`, proving the existing fake-network device hook can unsubscribe one same-peer sibling device while the shared `peerId` member row remains in every repo and the still-joined sibling continues receiving group traffic. The row remains partial because production membership remains keyed by `(groupId, peerId)`, group members have one ML-KEM key instead of per-device key packages, `rotateAndDistributeGroupKey` distributes by member peer id, and there is no device-removal UI/API, future-key exclusion proof, or live/equivalent 3-party device proof. |
| `RP-011` | Partial | `member_removal_integration_test.dart` proves removal updates the local member set before key rotation and the rotated key is distributed only to remaining members, excluding the removed peer. `invite_round_trip_test.dart` already proves a removed peer can return only through an explicit remove -> rotate -> re-invite flow and then sends on the rotated epoch. The row remains partial because true ban/unban is not implemented: there is no group ban tombstone, ban/unban use case, receive-side ban event, unban policy or surface, banned-invite rejection, or live/equivalent proof that banned identities cannot rejoin or receive future keys. |
| `RP-014` | Covered | RP-014 covered on 2026-05-01 by `trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules-session-RP-014-plan.md`. `broadcast_voluntary_leave_use_case.dart` now provides a first-class application helper for voluntary leave preparation: it publishes self-removal, stores durable replay only for remaining members, rotates/distributes the next key to remaining members, and fails before `leaveGroup` cleanup if rotation cannot complete while remaining members exist. `group_info_wired.dart` calls the helper before local cleanup. `member_removal_integration_test.dart` extends `voluntary leave rotation excludes leaver and remaining members send on rotated epoch` to prove key-update recipients exclude the leaver, remaining members save/promote epoch 2, `leaveGroup` removes leaver group/member/key state, post-leave send and inbox replay use epoch 2 with recipients excluding the leaver, normal drain skips deleted group state, and a forced post-leave replay attempt persists only `groupUndecryptablePlaceholderText` with `undecryptable` status instead of future plaintext. Commands relied on: focused RP-014 integration test passed (`+1`); focused multi-admin and writer leave UI tests passed (`+1` each); full `group_info_wired_test.dart` passed (`+27`); `group_membership_smoke_test.dart` passed (`+24`); `./scripts/run_test_gates.sh groups` passed (`+97`); `flutter test --no-pub test/features/groups/integration` passed (`+119`). Supporting `group-real-network-nightly` was not run because relay/device env is unset. RP-014 does not claim configurable leave policy, packet-capture/real-device proof, first-class ban/unban policy, or broader removed-peer dial/publish isolation. |
| `RP-016` | Partial | `invite_round_trip_test.dart` proves a removed peer can rejoin only through explicit direct or inbox-fallback re-invite carrying the rotated epoch, while `group_membership_smoke_test.dart` proves a removed member loses active group/subscription state, misses removed-period traffic and notifications, and resumes only after re-add with current member/key state. The row remains partial because this is removal/re-add policy, not ban policy: no first-class group ban tombstone, ban/unban use case, banned member role, receive-side ban event, unban surface, banned-invite rejection, or live/equivalent ban proof exists. |
| `RP-017` | Covered | RP-017 covered on 2026-05-01 by `trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules-session-RP-017-plan.md` for the shipped ignore/filter removed-peer isolation policy. `go-mknoon/node/pubsub_authorization_forward_test.go` adds `TestRP017RemovedPeerContinuedPublishesAreRejectedBeforeAcceptAndForward`, proving a removed peer's raw live message, reaction, membership, metadata, and key-rotation publishes are rejected as non-member traffic before accepted delivery or forwarding. `go-mknoon/node/pubsub_test.go` adds `TestRP017RemovedPeerExcludedFromKnownAndDiscoveredDialsAfterConfigUpdate`, proving `UpdateGroupConfig` removal excludes the removed peer from known-member and rendezvous discovery dials while a remaining member stays eligible. Focused Flutter evidence proves removed members cannot send/retry, future media ACLs, inbox recipients, and key updates exclude them, replayed self-removal cuts off later queued traffic, unauthorized `member_removed` is ignored, and future-media replay with only an old epoch saves only an `undecryptable` placeholder with no plaintext, media download, or decrypt. Commands relied on: focused RP-017 Go proof passed; focused membership/media/retry/inbox/key/listener Flutter tests passed; `./scripts/run_test_gates.sh groups` passed (`+97`); `flutter test --no-pub test/features/groups/integration` passed (`+119`); `git diff --check` passed. The shipped policy is ignore/filter rather than forced disconnect or peer downscore; supporting `group-real-network-nightly` was not run because relay/device env is unset. |
| `RP-018` | Covered | RP-018 covered on 2026-05-01 by `trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules-session-RP-018-plan.md`. `group_message_listener.dart` now applies stale `member_removed` events when the target member still exists from before the removal timestamp, ignores old removals after explicit re-adds, and rejects `member_role_updated` events for missing targets before a stale snapshot can recreate a removed member. `group_message_listener_test.dart` adds `RP018 stale removal beats role replay and later role cannot resurrect`, proving remove-over-role ordering, missing-target role rejection, no extra config update after the target is gone, and diagnostics (`GROUP_MESSAGE_LISTENER_STALE_MEMBER_REMOVED_CONFLICT_APPLIED`, `GROUP_MESSAGE_LISTENER_MEMBER_ROLE_UPDATE_MISSING_TARGET_IGNORED`). `group_membership_smoke_test.dart` adds `RP018 partitioned add remove promote demote replay converges membership`, proving fake-network add/remove/promote/demote replay after partition heal converges admin, Bob, Diana, and observer on the same final member/role map while Charlie is removed/unsubscribed. Commands relied on: focused RP-018 listener and smoke tests passed (`+1` each); full `group_message_listener_test.dart` passed (`+83`); full `group_membership_smoke_test.dart` passed (`+25`); resume membership churn and same-generation key conflict focused tests passed (`+1` each); `./scripts/run_test_gates.sh groups` passed (`+98`); `flutter test --no-pub test/features/groups/integration` passed (`+120`); `git diff --check` passed. Supporting `group-real-network-nightly` was not run because relay/device env is unset. |
| `MS-001` | Covered | `send_group_message_use_case.dart` resolves generated and explicit outgoing message ID collisions before pre-persist, allows only matching local failed/sending retry rows to reuse an ID, treats empty requested IDs as generated, and emits collision flow events. `send_group_message_use_case_test.dart` proves generated collision recovery, explicit collision recovery, and legitimate retry reuse; `handle_incoming_group_message_use_case_test.dart` proves conflicting same-ID replay cannot overwrite trusted content; `group_resume_recovery_test.dart` proves pubsub plus inbox replay preserves the live row under conflicting content; `group_messaging_smoke_test.dart` keeps rapid simultaneous sends covered; and `group_multi_device_convergence_test.dart` proves same-user sibling devices can send concurrently without message loss or ID collapse. Live GossipSub hash/sequence collision and receipt behavior remain tracked by LP-013, not MS-001. |
| `MS-002` | Covered | MS-002 covered on 2026-05-01 by `trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules-session-MS-002-plan.md`. `go-mknoon/node/pubsub.go` rejects claimed `senderId` versus libp2p transport Peer ID mismatches before member lookup, authorization, signature verification, decrypt, accept, or forwarding, and now includes `transportPeerId` in `group_message:received` events after that validation. Migration 061 adds nullable `group_messages.transport_peer_id`; `GroupMessage`, `group_messages_db_helpers.dart`, and `GroupMessageRepositoryImpl` persist and surface the verified transport identity. `handle_incoming_group_message_use_case.dart`, `group_message_listener.dart`, `drain_group_offline_inbox_use_case.dart`, and `send_group_message_use_case.dart` propagate live, retry, and offline inbox transport Peer IDs and reject nonempty transport/sender mismatches before event-log or message persistence side effects. Commands relied on: focused Go proof passed (`+3`); migration/helper/repository tests passed (`+2`, `+20`, `+29`); fresh full-migration-chain schema check passed (`+1`); focused handle-incoming, drain-inbox, and fake-network MS002 tests passed (`+2`, `+2`, `+1`); full group-message application wildcard passed (`+213`); `./scripts/run_test_gates.sh groups` passed (`+99`); `flutter test --no-pub test/features/groups/integration` passed (`+121`); `git diff --check` passed. Supporting `group-real-network-nightly` was not run because relay/device env is unset. The shipped device identity unit is the libp2p Peer ID; separate account/device registry and per-device key-package identity are outside MS-002. |
| `MS-003` | Covered | MS-003 covered on 2026-05-01 by `trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules-session-MS-003-plan.md`. `handle_incoming_group_message_use_case.dart` clamps incoming timestamps beyond the five-minute future-skew window to receive time before event-log append, membership cutoff checks, persistence, and latest-message selection. `group_conversation_wired.dart` and `group_group_messages_into_threads.dart` now use timestamp/id tie-breakers for live conversation upserts and group feed projection, matching the existing DB and fake-repository ordering contract. Focused tests prove direct handler past/current/near-future/far-future normalization, offline inbox far-future replay/latest selection, fake-network live skew convergence across recipients, wired equal-timestamp order, and feed equal-timestamp order. Commands relied on: focused handle-incoming (`+2`), drain-inbox (`+1`), fake-network live (`+1`), wired (`+1`), feed (`+1`), full group-message application wildcard (`+213`), `./scripts/run_test_gates.sh groups` (`+100`), full groups integration (`+122`), and `git diff --check` passed. Supporting `group-real-network-nightly` was not run because relay/device env is unset. MS-004 still owns causal references and concurrent ordering beyond timestamp/id ordering. |
| `MS-004` | Covered | MS-004 covered on 2026-05-01 by `trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules-session-MS-004-plan.md`. `group_message_ordering.dart` now provides shared timeline ordering: unrelated messages sort deterministically by timestamp/id, present `quotedMessageId` parents are placed before replies, and cycles fall back to stable timestamp/id order. `GroupMessageRepositoryImpl`, `InMemoryGroupMessageRepository`, `GroupConversationWired`, and `groupGroupMessagesIntoThreads` use that ordering for loaded pages, fake-network/user views, live conversation upserts, and feed projection. Focused tests cover DB and fake repository parent-before-reply when timestamp/id would invert the pair, feed and wired live parent-before-reply, fake-network A/B/C equal-timestamp concurrent sends plus quoted replies converging on every peer, and partition/offline replay preserving parent/reply order plus `quotedMessageId` despite reply ids sorting earlier. Commands relied on: focused repo (`+2`), feed (`+1`), wired (`+1`), fake-network live (`+1`), resume replay (`+1`), full group-message application wildcard (`+213`), `./scripts/run_test_gates.sh groups` (`+100`), full groups integration (`+122`), and `git diff --check` passed. Supporting `group-real-network-nightly` was not run because relay/device env is unset. This closes the shipped `quotedMessageId` causal parent reference; vector clocks, previous-state DAGs, account/device registry, and real-device packet proof are not claimed. |
| `MS-018` | Covered | MS-018 covered on 2026-05-01 by `trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules-session-MS-018-plan.md`. Existing app-layer tests prove `sendGroupMessage` snapshots the latest committed local key into both `GroupMessage.keyGeneration` and encrypted replay `keyEpoch`, keeps epoch 1 when epoch 2 is saved before publish returns, binds before/during/after rotation sends to epochs 1/1/2, keeps pending key-update sends on the old epoch until local commit, persists mixed epoch inbox replay under each envelope epoch, and stores unknown future-epoch replay as one safe undecryptable placeholder without wrong-epoch decrypt or plaintext fallback. `fake_group_pubsub_network.dart` now has a test-only held-delivery hook, and `group_messaging_smoke_test.dart` adds `MS018 rotation race preserves message epochs under out-of-order live delivery`: Alice rotates to epoch 2 while Bob sends before, during, and after Bob's local epoch-2 commit, Charlie receives the live deliveries in reverse order, and Bob, Alice, and Charlie all persist the same message ids under epochs 1/1/2 with no duplicate or rewritten epoch. Commands relied on: new fake-network MS018 proof (`+1`), send MS-018 suite (`+2`), pending key-update send proof (`+1`), epoch inbox replay proof (`+3`), group-message application wildcard (`+213`), `./scripts/run_test_gates.sh groups` (`+101`), full groups integration (`+123`), and `git diff --check` passed. Supporting `group-real-network-nightly` was not run because relay/device env is unset. Packet-capture/device-lab proof, account/device registry, MLS commit semantics, and new transport cryptography are not claimed. |
| `OS-001` | Covered | `retry_failed_group_messages_use_case_test.dart` now proves restart-style failed outgoing text, quote, and done-media rows inserted out of order republish in deterministic persisted `timestamp ASC, id ASC` order while preserving original message IDs, timestamps, quote IDs, text, and media attachment state. `retry_failed_group_inbox_stores_use_case_test.dart` proves failed message inbox-store rows drain before reaction replay rows, with each owner ordered deterministically by persisted timestamp/id. Focused deterministic tests, both full retry test files, `./scripts/run_test_gates.sh completeness-check`, and `git diff --check` passed. |
| `OS-003` | Open | OS-003 remains prerequisite-blocked by `missing_direct_peer_sync_protocol_primitives`. Evidence on 2026-04-30 found only adjacent relay inbox cursor replay, PubSub validation, topic rejoin, and watchdog recovery paths; no direct group peer sync command, request/response schema for ranges or known heads, hash-chain/state-head owner, signed or hash-verified direct response path, or tampered-response fail-closed direct-sync tests exist in the current repo. Focused drain cursor/tamper/future/replay/dedupe tests, focused group resume recovery partition/replay/resume/dedupe/gap tests, the Go node/bridge group inbox/recovery/PubSub evidence slice, `./scripts/run_test_gates.sh completeness-check`, and `git diff --check` passed. `FLUTTER_DEVICE_ID` and `MKNOON_RELAY_ADDRESSES` were unset, so live direct-peer proof was unavailable. |
| `OS-005` | Covered | OS-005 accepted with explicit follow-up on 2026-04-30. Go node/bridge tests prove group inbox-store request JSON preserves opaque encrypted replay envelopes, uses the versioned inbox protocol, and omits protected plaintext fragments. Flutter send, retry, drain, invite, and resume recovery tests prove pending retry storage, `group:inboxStore`, invite inbox fallback, encrypted replay drain, media descriptors, reactions, dedupe, and recipient-side authorization keep store-and-forward content encrypted or metadata-minimized. Go relay-server tests prove in-memory and Redis group inbox backends preserve opaque replay envelopes across store/retrieve and reject forbidden preview canaries. No production group receipt mailbox payload is shipped; receipt hits are routing-smoke criteria or legacy 1:1 delivery-receipt handling. Live relay/device packet-capture proof remains supplemental and fixture-blocked because `FLUTTER_DEVICE_ID` and `MKNOON_RELAY_ADDRESSES` were unset. |
| `OS-006` | Covered | OS-006 covered on 2026-05-01 by `trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules-session-PREREQ-HISTORY-GAP-REPAIR-plan.md`. Production now has durable `GroupHistoryGapRepair` lifecycle storage, relay-authorized cursor gap metadata, relay/Go/Dart `group:historyRepairRange` retrieval, Dart inbox-page history-gap parsing, drain orchestration that records detected/repairing/failed/repaired states, deterministic range-hash validation, authorized multi-source fallback, and repaired encrypted replay envelopes applied through the existing listener/replay path for validation and dedupe. UI coverage keeps active, failed, and repaired gap state separate from backlog-retention expiry. Direct evidence passed: migration/helper gap lifecycle tests (`+4`), bridge helper cursor history-gap parsing (`+4`), focused drain repair tests (`+3`), fake-network resume repair (`+1`), conversation UI repair state (`+1`), fresh full-migration-chain proof (`+1`), Dart bridge history repair (`+1`), retry inbox store regression (`+10`), Go node/bridge history gap and repair-range regex, `go-relay-server go test ./...`, targeted analyzer exit 0 with only info diagnostics, `./scripts/run_test_gates.sh groups` (`+102`), `./scripts/run_test_gates.sh completeness-check` (`708/708`), and `git diff --check`. Host/fake-network proof is primary; live device/relay proof is supporting only. Full MLS history, permanent server archive, packet capture, Android paired-device proof, and broad transport rewrites are not claimed. |
| `OS-008` | Covered | OS-008 accepted on 2026-04-30. `group_resume_recovery_test.dart` proves a removed offline member with a queued failed outgoing row drains the replayed self-removal, leaves/deletes local group state, then `retryFailedGroupMessages` returns zero without issuing any additional `group:publish` or `group:inboxStore` for the stale row; the stale row remains failed. Existing focused send, retry, drain, and resume-recovery tests prove local removed-sender sends are rejected before persistence/bridge calls, failed-message retry reuses that authorization check, replayed self-removal stops later cursor pages, and post-resume send attempts return group-not-found. Go PubSub validator tests prove removed/unauthorized sender traffic is rejected before forwarding. Live device/relay proof remains supplemental and fixture-blocked because `FLUTTER_DEVICE_ID` and `MKNOON_RELAY_ADDRESSES` were unset. |
| `OS-009` | Covered | OS-009 accepted on 2026-04-30. `drain_group_offline_inbox_use_case.dart` now persists a safe incoming `undecryptable` placeholder when an encrypted offline replay envelope carries a message id and key epoch but the local replay key is missing. The placeholder uses generic text only (`Message could not be decrypted.`), records the missing `keyGeneration`, preserves the replay `messageId` for dedupe/replacement, and does not call `group.decrypt` without a key. `drain_group_offline_inbox_use_case_test.dart` proves duplicate future-epoch replay creates one placeholder with no plaintext fallback, while mixed known-epoch replay still decrypts and persists under each envelope epoch. `group_conversation_screen_test.dart` proves the placeholder renders safe text without failed-media controls or guessed plaintext. Go PubSub tests still reject unknown/wrong live epochs before delivery. Live device/relay proof remains supplemental and fixture-blocked because `FLUTTER_DEVICE_ID` and `MKNOON_RELAY_ADDRESSES` were unset. |
| `OS-010` | Partial | OS-010 closure attempt on 2026-04-30 is fixture/prerequisite-blocked by missing fresh real same-account device-lab evidence. Host fake-network proof remains green: `group_multi_device_convergence_test.dart` covers same-peer sibling sent history, concurrent sends, membership convergence without duplicate local membership, sibling-device versus new-human distinction, device-local unsubscribe, and mute/unread/local notification locality. `group_multi_device_policy_test.dart` now pins composer drafts as device-local state alongside mute, unread counters, local notifications, and pending invite review, while membership, metadata, and message history stay shared across joined devices. The key-update listener slice keeps adjacent member-scoped key convergence/order behavior green. The row remains Partial because `FLUTTER_DEVICE_ID` and `MKNOON_RELAY_ADDRESSES` were unset and no fresh real/equivalent B1/B2 run proves messages, read state, key updates, drafts, and membership together. |
| `OS-012` | Partial | OS-012 closure audit on 2026-04-30 keeps this row Partial. Host/fake-network anchor passed: `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name "temporary partition replays missed backlog in cursor order and resumes live delivery after heal"` returned `00:00 +1: All tests passed!`, proving deterministic fake-network partition replay and post-heal live delivery. Configured real-network gate passed with supplied `FLUTTER_DEVICE_ID=347FB118-10D0-40C8-A05B-B0C3BD6B8CCD` and relay addresses: `./scripts/run_test_gates.sh group-real-network-nightly` returned `00:02 +4: All tests passed!`, but the output reported `No CLI peer fixture` and `No CLI peer — running self-contained scenarios only`; the real CLI peer group recovery path returned early instead of proving real bridge/GossipSub partition-heal backlog plus post-heal live delivery. Exact missing evidence: a configured real bridge/GossipSub or equivalent simulator/device-lab proof where B is actually partitioned from live group delivery while A/C continue, the split-window backlog is stored and replayed to B in order after heal, and post-heal live delivery resumes without duplicate visible rows. Blocker class: `missing_real_bridge_gossipsub_partition_heal_proof`; no production code/tests changed. |
| `NT-001` | Covered | NT-001 accepted on 2026-04-30. `background_push_notification_fallback.dart` now ignores push-visible `title` and `body` for protected data-only `new_message` and `group_message` pushes, keeping generic fallback copy until local decrypt resolves an on-device preview; visible `RemoteMessage.notification` payloads still suppress local fallback, and non-message fallbacks keep their explicit copy path. `background_push_notification_fallback_test.dart` and `background_message_handler_test.dart` prove protected chat and group data-only fallback privacy on Android-style and iOS data-only paths. `push_decrypt_preview_test.dart` proves current push fixtures plus post-phase1 frozen payload route data omit plaintext preview fields (`title`, `body`, `pushTitle`, `pushBody`, `senderUsername`, `groupName`, `messageText`, `text`, and `media`) while decrypted local previews still render 1:1 and group sender/body text after local decrypt. Supporting direct gates passed: `push_preview_telemetry_gate_test.dart`, `handle_foreground_remote_message_use_case_test.dart`, `chat_and_group_push_open_flow_test.dart`, `resolve_group_notification_route_target_use_case_test.dart`, `set_group_muted_use_case_test.dart`, and `group_notification_dedupe_integration_test.dart`. `./scripts/run_test_gates.sh completeness-check` and `git diff --check` passed. |
| `NT-006` | Covered | NT-006 accepted on 2026-04-30. `show_notification_use_case.dart` now checks the recent remote-push announcement gate before showing local notifications even when the app is resumed, while preserving active-conversation suppression and avoiding a foreground delay. `foreground_group_push_drain_test.dart` proves live-plus-foreground-push dedupe and background-announced-plus-foreground-drain dedupe: the same group `messageId` persists one incoming row, unread count stays at one, duplicate local notification is suppressed, unrelated gate entries remain consumable, and a distinct later group message increments unread and notifies normally. `group_notification_dedupe_integration_test.dart` and `group_message_listener_test.dart` prove background push announcements suppress later local PubSub/listener notifications for the same group message. Focused direct push/listener tests, focused drain replay tests, simulator foreground drain, groups integration, canonical `groups` gate, and completeness check passed. The broad ad hoc `flutter test --no-pub test/features/groups` folder sweep still fails one unrelated MD-011 media/epoch replay assertion in `drain_group_offline_inbox_use_case_test.dart`; the canonical `./scripts/run_test_gates.sh groups` command is green. |
| `DB-001` | Covered | DB-001 closed on 2026-04-30. `test/core/database/migrations/017_018_group_original_tables_test.dart` proves migrations 017/018 create the original group tables (`groups`, `group_members`, `group_keys`, and `group_messages`), expose expected baseline columns/defaults/indexes, support baseline group/member/key/message insert and query before migration 026, enforce original type, role, unique-topic, member primary-key, and key primary-key constraints, and rerun idempotently. Direct gate `flutter test --no-pub test/core/database/migrations/017_018_group_original_tables_test.dart` passed with 3 tests. No production migration code changed. |
| `DB-002` | Covered | DB-002 covered on 2026-05-01 by `trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules-session-DB-002-plan.md`. `lib/core/database/migrations/060_group_event_log.dart` and `lib/core/database/helpers/group_event_log_db_helpers.dart` provide the tamper-evident per-group hash-chain event log with canonical payloads, source-event uniqueness, idempotent exact replay, conflicting replay rejection, and row tamper verification. `lib/main.dart` wires `dbAppendGroupEventLogEntry` into the group message, invite, and direct key-update listeners; the DB-002 session added the missing production key-update listener wiring. Application anchors prove accepted incoming messages, membership/metadata/role system events, `key_rotated` system events, and direct key commits append or replay safely without silent local DB mutation. Focused commands passed: event-log migration/helper suite (`+5`), handle-incoming event-log slice (`+3`), new DB-002 membership/metadata listener proof (`+1`), role replay proof (`+1`), `key_rotated` duplicate proof (`+1`), direct key-update tamper proof (`+1`), exact duplicate direct key-update replay proof (`+1`), and fresh full migration-chain schema check (`+1`). DB-002 does not claim MLS signed commit-transition support, first-class key-package replay protection, external device proof, or a per-actor signed audit model. |
| `DB-004` | Covered | DB-004 covered on 2026-05-01 by `PREREQ-GROUP-SYNC-RECEIPTS` final QA. Migration 066 creates durable `group_inbox_cursors` and `group_message_receipts`, `group_sync_receipts_db_helpers.dart` persists cursors/receipts and applies message insert, receipt/read-state update, and cursor advancement inside one SQLite transaction, and `GroupMessageRepositoryImpl` plus `main.dart` expose transaction-scoped page apply to production. `drain_group_offline_inbox_use_case.dart` now loads the durable cursor before replay and advances it only through `runInboxPageTransaction`. `group_message_listener.dart` supports transaction-scoped normal and system replay with `msgRepoOverride` and `rethrowOnError: true`; system timeline saves use the supplied repository so listener failures roll back timeline rows/events together with receipts/read-state and cursor advancement. Direct evidence passed: migration 066 test (`+1`), sync helper tests (`+4`), repository PREREQ tests (`+2`), drain PREREQ tests (`+5`), v65-to-v66 and fresh-install full-chain migration proofs, full listener regression suite (`+88`), `./scripts/run_test_gates.sh groups` (`+102`), `./scripts/run_test_gates.sh completeness-check` (`710/710`), scoped analyzer with documented pre-existing listener warning debt outside the clean slice, and `git diff --check`. |
| `DB-006` | Covered | DB-006 covered on 2026-05-01 by `trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules-session-PREREQ-SECRET-STORAGE-WRAPPING-plan.md`. `lib/core/secure_storage/secret_storage_references.dart` defines deterministic `secure:` references for group media attachment keys and group key material, and `legacy_group_secret_storage_scrub.dart` migrates legacy plaintext-equivalent `media_attachments.encryption_key_base64` and `group_keys.encrypted_key` rows into `SecureKeyStore` while rewriting SQL to non-secret references. `MediaAttachmentRepositoryImpl` and `GroupRepositoryImpl` now store actual key material in the primary secure store, persist only references in ordinary SQL rows, hydrate models when secure material exists, fail closed when referenced material is missing, and avoid mirroring unresolved `secure:` reference text into shared push storage. `main.dart` runs the legacy scrub before group-key mirroring and injects the primary secure store into production media/group repositories. Evidence passed: PREREQ media repository tests (`+5`), PREREQ group repository tests (`+5`), PREREQ legacy scrub tests (`+3`), media/group helper tests, fresh full-migration-chain proof, targeted analyzer, `./scripts/run_test_gates.sh groups`, `./scripts/run_test_gates.sh completeness-check` (`711/711`), and `git diff --check`. This closes local ordinary-table secret persistence only; DB-012 and EK-012 remain separate event-family/replay rows. |
| `DB-012` | Covered | DB-012 covered on 2026-05-01 by `trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules-session-PREREQ-REMOTE-EVENT-FAMILIES-plan.md`. The last row-named event-family gaps now have production apply models/tests: trusted-private `member_banned`, `member_unbanned`, and `group_message_deleted` route through `GroupMessageListener` with deterministic tombstone/timeline rows, duplicate replay idempotency, stale-state guards, authorization, signed transition audit/event-log wiring, and offline replay through the existing transaction-scoped listener path. Existing evidence covers duplicate/idempotent apply for messages, media enrichment, reactions, `member_added`, `members_added`, non-self/self `member_removed`, `member_role_updated`, signed `group_metadata_updated`, `group_dissolved`, `key_rotated`, direct `group_key_update`, welcome/key-package tombstones, durable receipts, and live-plus-inbox duplicate replay. Evidence passed: `group_message_listener_test.dart --plain-name 'PREREQ-REMOTE-EVENT-FAMILIES'` (`+3`), `drain_group_offline_inbox_use_case_test.dart --plain-name 'PREREQ-REMOTE-EVENT-FAMILIES'` (`+1`), Go invalid-signature regex, `./scripts/run_test_gates.sh groups`, `./scripts/run_test_gates.sh completeness-check`, and `git diff --check`; targeted analyzer has only documented pre-existing listener warnings. |
| `ER-001` | Covered | ER-001 covered on 2026-05-01 by `trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules-session-ER-001-plan.md`. `go-mknoon/node/pubsub.go` now emits rate-limited `group:validation_rejected` diagnostics from validator reject paths using only `reason`, `groupHash`, `senderHash`, `transportPeerHash`, `localPeerHash`, `envelopeType`, and `keyEpoch`; validator logs use the same hashed identifiers. `go-mknoon/node/pubsub_authorization_forward_test.go` adds `TestER001InvalidSignatureDiagnosticsArePrivacySafeAndActionable`, which injects invalid signatures for shipped event families including messages, reactions, `member_added`, `members_added`, `member_removed`, `member_role_updated`, `group_metadata_updated`, `group_dissolved`, and `key_rotated`, then proves rejection, one actionable diagnostic, and no raw group IDs, peer IDs, group names, keys, signatures, ciphertexts, nonces, plaintext, or sensitive multiaddrs in logs or diagnostic events. `lib/core/bridge/go_bridge_client.dart` now forwards `group:validation_rejected` into Flutter's `groupDiagnosticEventStream`, and `go_bridge_client_test.dart` proves this does not invoke the normal group-message callback. Focused commands passed: Go ER-001/LP-002/security-family slice and the Flutter bridge validation-reject slice. Unmodeled bans, remote deletes, receipts, and commit/key-package transitions remain outside ER-001 until those event families are first-class. |
| `ER-002` | Covered | ER-002 covered on 2026-05-01 by `trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules-session-ER-002-plan.md`. `handle_incoming_group_message_use_case.dart` now rejects unknown senders with no persisted removal cutoff before event-log append or message persistence, while preserving intentional pre-removal cutoff tolerance and rejecting at-cutoff/later removed-sender replay. `handle_incoming_group_reaction_use_case.dart` now returns `unknownSender` before reaction storage when the sender is not a current member. `group_message_listener_test.dart` adds ER-002 proof that an unknown-sender group message creates no DB row, emits no group-message stream item, and shows no local notification. Existing fake-network membership smoke still proves removed members receive no notifications while removed and only resume after rejoin. Focused commands passed: handle-incoming unknown sender slice (`+3`), reaction unknown sender slice (`+1`), listener ER-002 slice (`+1`), and removed-member notification smoke (`+1`). First-class receipt traffic is not modeled and remains outside ER-002 until it exists. |
| `ER-004` | Covered | ER-004 covered on 2026-05-01 by `trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules-session-PREREQ-FUTURE-EPOCH-KEY-REPAIR-plan.md`. Go live wrong-key, tampered nonce, tampered ciphertext, unknown future epoch, and expired previous-epoch diagnostics remain green without normal `group_message:received`; Flutter bridge still forwards `group:decryption_failed` only to diagnostics. `GroupMessageListener` now turns live decryption-failure diagnostics into a safe pending repair placeholder, queues a durable pending item, and triggers scoped key repair without plaintext delivery. Offline missing/future-key replay shares the same pending/finalized status model, retries after key arrival, replaces placeholders on valid repair, and finalizes invalid or no-envelope repairs idempotently as safe `undecryptable` text. Commands relied on: focused Go diagnostics regex passed; Flutter bridge diagnostic preservation passed (`+1`); focused live placeholder test passed (`+1`); focused offline queue/repair test passed (`+1`); focused key-arrival and rejected-key tests passed (`+2`); focused pending/finalized UI test passed (`+1`); migration/helper/repository/full-chain tests passed (`+12`); direct owner suites, `groups`, `completeness-check`, and `git diff --check` passed. |
| `ER-005` | Covered | ER-005 covered on 2026-05-01 by `trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules-session-ER-005-plan.md`. `flow_event_emitter.dart` now sanitizes flow-event payloads before test sinks and debug logs, recursively redacting sensitive keys such as private keys, secret keys, public keys, ciphertext, plaintext, signatures, nonces, key material, relay/listen/circuit multiaddrs, and long Peer IDs. `bridge.dart` applies the same sanitizer to group diagnostic stream payloads before Flutter listeners receive them. `go_bridge_client.dart` sanitizes native `ok:false` bridge error messages and `PlatformException` or unexpected exception text before returning JSON responses or emitting flow events. Focused evidence passed: `flutter test --no-pub test/core/utils/flow_event_emitter_test.dart` (`+7`), `flutter test --no-pub test/core/bridge/go_bridge_client_test.dart --plain-name 'ER005'` (`+3`), `flutter test --no-pub test/core/bridge/go_bridge_client_test.dart --plain-name 'PlatformException'` (`+3`), full `go_bridge_client_test.dart` (`+68`), and `git diff --check`. ER-005 closes the shared bridge/diagnostics emission boundary without changing native command payloads. |
| `AB-006` | Covered | AB-006 covered on 2026-05-01 by `trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules-session-AB-006-plan.md`. Existing media policy, send, listener, offline replay, and fake-network tests prove suspicious media does not auto-download or reach side effects before validation. Policy tests cover dangerous/unsupported MIME, mediaType mismatch, oversized single and aggregate media, malformed remote sizes, content-hash display prerequisites, and tampered hash checks. Send tests prove dangerous MIME, oversized attachments, and mediaType mismatch reject before message/media persistence, group publish, or group inbox storage. Listener tests prove invalid, oversized, and hashless media reject before notification preview or `media:download`. Offline replay rejects dangerous encrypted media before message or attachment storage. Fake-network tests prove oversized recipient media is neither stored nor downloaded, and tampered downloads become integrity failures with deleted local files before done/display state. Focused AB-006 commands passed: core media policy suite (`+18`), send dangerous MIME (`+1`), send oversized (`+2`), send mediaType mismatch (`+1`), listener auto-download guards (`+3`), dangerous offline replay (`+1`), oversized fake-network fanout (`+1`), tampered fake-network integrity (`+1`), and `git diff --check`. |
| `UI-003` | Covered | UI-003 covered on 2026-05-01 by `trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules-session-UI-003-plan.md`. `group_security_status_view_state.dart` derives a display-only security state from latest group key epoch, verified saved-contact matches, identity-change warnings, unverified member counts, and member totals without exposing group key material. `group_info_screen.dart` now renders a scrollable security card with encrypted-state, current/key-changed epoch text, verified-member counts, and verification warnings while preserving existing first-screen member/admin controls. `group_conversation_screen.dart` now renders a compact encrypted/key-epoch and review warning strip. `group_info_wired.dart` and `group_conversation_wired.dart` populate those surfaces from `GroupRepository.getLatestKey`, group members, contacts, and existing `GroupMemberIdentitySafety.compare`. Direct evidence passed: focused UI-003 pure/wired tests, full `group_info_screen_test.dart` (`+18`), full `group_conversation_screen_test.dart` (`+35`), full `group_info_wired_test.dart` (`+28`), full `group_conversation_wired_test.dart` (`+74`), and `git diff --check`. Existing member-row safety-number warnings remain covered by the earlier group info tests. |
| `UI-005` | Covered | UI-005 covered on 2026-05-01 by `trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules-session-UI-005-plan.md`. `drain_group_offline_inbox_use_case.dart` uses `groupUndecryptablePlaceholderText` and saves one `status: 'undecryptable'` placeholder when future-epoch encrypted replay arrives without matching local key material, preserving key-generation metadata while avoiding `group.decrypt` and original plaintext exposure. `group_conversation_screen_test.dart` proves the conversation UI renders the generic safe text, hides the original future-epoch plaintext, and does not expose failed-media retry/delete controls on undecryptable rows. Focused evidence passed: `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'future epoch encrypted replay creates one undecryptable placeholder without decrypting'` (`+1`), `flutter test --no-pub test/features/groups/presentation/group_conversation_screen_test.dart --plain-name 'renders undecryptable epoch placeholders as safe text'` (`+1`), and `git diff --check`. The missing live repair lifecycle remains ER-004 scope. |
| `SP-001` | Covered | SP-001 covered on 2026-05-01 by `trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules-session-SP-001-plan.md`. `go-relay-server/inbox.go` now requires authenticated group inbox store callers to bind `from` to the libp2p `RemotePeer`, rejects empty `recipientPeerIds`, persists normalized per-message recipient ACLs through `backend_memory.go` and `backend_redis.go`, and filters `group_retrieve` / `group_retrieve_cursor` to the sender or stored recipients only. `go-relay-server/inbox_test.go` adds `TestHandleInboxStream_GroupStoreRejectsSpoofedFromPeer`, `TestHandleInboxStream_GroupRetrieveFiltersByRecipientAuthorization`, and `TestHandleInboxStream_GroupRetrieveCursorSkipsUnauthorizedMessages`. Existing Go proof covers the other shipped protocol surfaces: `go-mknoon/node/protocol_version_test.go` requires secure libp2p negotiation before mknoon protocols; `pubsub_test.go` and `pubsub_authorization_forward_test.go` prove PubSub sender/member/signature/system-event authorization; `go-relay-server/media_test.go` keeps unauthorized media download/delete/list ACLs pinned. Focused evidence passed: `cd go-relay-server && go test ./... -run 'GroupInbox|HandleInboxStream|Unauthorized|RedisGroupInbox|TwoRelayServers_SharedGroupInbox' -count=1`, `cd go-mknoon && go test ./node -run 'TestPublishGroupMessage_ReturnsPeerCountZero_WhenNoPeers|Protocol|PubSub|Group|Security' -v -count=1`, and `git diff --check`. Relay group inbox authorization enforces authenticated transport peer plus stored fanout ACL; live authoritative group-state control-plane semantics remain separate scope. |
| `SP-002` | Covered | SP-002 covered on 2026-05-01 by `trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules-session-SP-002-plan.md`. Existing node proof keeps group topics, rendezvous namespaces, join logs, and relay-visible PubSub envelopes free of human-readable group metadata and plaintext. This session removed the remaining native group inbox preview leak: `go-mknoon/node/group_inbox.go` no longer serializes retired `pushTitle` / `pushBody`, `group_inbox_test.go` proves caller-supplied preview fields are omitted, and `go-mknoon/bridge/bridge.go` ignores those legacy JSON fields on `group:inboxStore`. `retry_failed_group_inbox_stores_use_case_test.dart` proves stale persisted retry payloads containing old preview fields replay through the Flutter bridge without re-emitting them. Existing relay, push, and diagnostics tests prove encrypted group pushes are generic/data-only and diagnostic surfaces redact raw secrets, raw Peer IDs, and sensitive multiaddrs. Focused evidence passed: Go node metadata/request/protocol slice, Go bridge `GroupInboxStore` slice, relay `GroupPush|Push|Forbidden|GroupInbox|Unauthorized` slice, Flutter retry inbox-store suite (`+10`), push fallback/preview suite (`+34`), diagnostics regex slice (`+8`), and `git diff --check`. Relay-visible group IDs, recipient peer IDs, push tokens, relay addresses, and encrypted replay blobs remain unavoidable relay metadata and are not claimed hidden. |
| `SP-003` | Covered | SP-003 covered on 2026-05-01 by `trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules-session-SP-003-plan.md`. Added focused random-artifact proof across shipped surfaces: `go-mknoon/crypto/group_test.go` checks repeated group AES keys and AES-GCM nonces/ciphertexts for expected byte lengths and uniqueness; `go-mknoon/crypto/x25519_test.go` checks X25519 ephemeral public keys used as HKDF salts plus nonces/ciphertexts for uniqueness; `go-mknoon/identity/identity_test.go` checks repeated BIP39 identity mnemonics and Peer IDs; `go-mknoon/bridge/bridge_test.go` checks UUID v4 group IDs, UUID v4 native publish message IDs, and 32-byte group keys; Flutter send/invite use-case tests check unique UUID v4 message IDs and direct invite IDs. Gates passed: Go crypto/identity/bridge SP003 slice, Flutter SP003 group send/invite slice (`+2`), Go node `Protocol|PubSub|Group|Security`, Flutter push preview plus group-key DB helper suite (`+15`), Dart format, and `git diff --check`. No separate public/link invite-token generator is shipped; direct invites use UUID v4 invite IDs, push tokens are externally supplied, and contact safety numbers are deterministic rather than random salts. |
| `EC-001` | Covered | EC-001 covered on 2026-05-01 by `trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules-session-EC-001-plan.md`. `accept_pending_group_invite_use_case.dart` now returns `wrongIdentity` for copied pending invites whose signed `recipientPeerId` / `allowedDevices` do not match the current local Peer ID, keeping that case distinct from malformed/tampered `invalidPayload`; group list and Orbit pending-invite surfaces show a distinct wrong-identity snackbar. `accept_pending_group_invite_use_case_test.dart` adds `EC001 invalid invite accepts classify failures without group or key state`, proving expired, revoked, wrong-identity, malformed signed-payload, and already-used accepts produce the expected classifications and create no group, key, join, or message side effects. Supporting store-path evidence proves delayed revoked, already-used, expired, and local-identity-mismatched invite copies do not create pending or group state. Gates passed: focused EC001/IJ013 accept slice (`+2` after stale assertion recovery), full accept-pending suite (`+20`), supporting store-pending edge slice (`+4`), Dart no-change format, scoped analyzer with one non-blocking existing style info, and `git diff --check`. |
| `EC-003` | Covered | EC-003 covered on 2026-05-01 by `trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules-session-EC-003-plan.md` for shipped future-input behavior. `handle_incoming_group_message_use_case_test.dart` proves far-future incoming timestamps clamp to receive time and past/current/near-future timestamps retain chronological order. `group_messaging_smoke_test.dart` proves fake-network live skewed timestamps keep sane ordering/latest-message state after valid membership hydration; this session fixed the smoke fixture to broadcast Charlie's membership before Charlie publishes under strict sender validation. `go-mknoon/node/pubsub_key_rotation_grace_test.go` proves unknown live future epochs reject before delivery. `drain_group_offline_inbox_use_case_test.dart` proves offline future-epoch encrypted replay stores one generic undecryptable placeholder without decrypting/exposing future plaintext and that later valid replay can enrich sparse prior rows with quote/media dependencies. Focused Go, Flutter application, offline replay, fake-network smoke, duplicate-enrichment, Dart no-change format, and `git diff --check` evidence passed. Durable future-key queue/key-sync repair and live repair lifecycle remain EK-005/ER-004 scope. |
| `EC-004` | Covered | EC-004 covered on 2026-05-01 by `trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules-session-EC-004-plan.md` with evidence-only closure. `group_message_listener_test.dart` proves older metadata, member-added, member-removed, and member-role events cannot roll back newer finalized state across restart, and old system events after dissolve or local delete do not mutate metadata, members, keys, or visible messages. `handle_incoming_group_message_use_case_test.dart` and `handle_incoming_group_reaction_use_case_test.dart` prove pre-dissolve messages/reactions are accepted while at/after-cutoff replay is ignored without overwriting trusted rows. Fake-network membership and resume-recovery tests prove removed-sender replay is accepted only before the removal cutoff, conflicting promote/remove converges to removal, remove-vs-send backlog drain keeps the same cutoff outcome after resume, and offline metadata replay converges to the newer final state. Focused commands passed: listener old-event slice (`+6`), message dissolve-cutoff slice (`+3`), reaction dissolve-cutoff slice (`+3`), membership cutoff smoke (`+1`), promote/remove conflict smoke (`+1`), resume remove-vs-send backlog (`+1`), resume metadata convergence (`+1`), and `git diff --check`. No production code changed for this row. |
| `EC-006` | Covered | EC-006 covered on 2026-05-01 by `trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules-session-PREREQ-REMOTE-EVENT-FAMILIES-plan.md`. `trusted_private_group_system_event.dart` and `GroupMessageListener` now model the missing tombstone families: `member_banned`, `member_unbanned`, and `group_message_deleted`. Duplicate replay creates one deterministic tombstone/timeline row; stale ban replay after a later unban/rejoin does not remove current valid membership; unban is a tombstone/freshness event and does not recreate membership; remote delete removes only the exact same-group target message and ignores wrong-group, missing, stale, newer-message, or unauthorized deletes. Offline replay uses the same listener path through `drainGroupOfflineInbox`, preserving transaction/cursor behavior. Prior evidence still covers removal, voluntary leave, dissolve, local-delete, and re-invite tombstone paths. Evidence passed: PREREQ listener tests (`+3`), offline replay test (`+1`), Go invalid-signature regex, `groups`, `completeness-check`, and `git diff --check`; targeted analyzer caveat remains warning-only pre-existing listener debt. |
| `EC-007` | Covered | EC-007 covered on 2026-05-02 by `trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules-session-PREREQ-INVITER-FRESHNESS-plan.md`. `group_invite_payload.dart` adds signed `GroupInviteMembershipFreshnessProof` and binds it into canonical invite signing; `group_invite_auth.dart` validates proof structure, trusted inviter key, current inviter membership/permission snapshot, group config hash, recipient/device/key-package binding, issue time, and expiry. `send_group_invite_use_case.dart` reloads current `GroupRepository` membership/config state before proof/sign/encrypt/delivery, so stale caller configs from removed/demoted inviters fail before delivery. `handle_incoming_group_invite_use_case.dart`, `group_invite_listener.dart`, and `accept_pending_group_invite_use_case.dart` reject missing, malformed, tampered, mismatched, or stale proofs before pending/group/key/join/mailbox/notification/consumption side effects; accept-time stale proof deletes pending state without consumed or welcome-package tombstones. The fix pass made `GroupInviteListener` validate pending-store freshness against local receive time rather than replayed `ChatMessage.timestamp`, and tests keep the original queued timestamp while advancing local receipt beyond `groupInviteMembershipFreshnessTtl`. Evidence passed: PREREQ selectors for invite payload, send invite, create fanout, contact picker fanout, direct handle, listener, accept, and invite round trip; invite wildcard; full invite round trip; valid fresh and remove-rotate-reinvite preservation selectors; targeted analyzer; `groups`; `completeness-check`; and `git diff --check`. Existing queued role update, queued invite/add recheck, receive-side stale mutation rejection, and invalid signed-snapshot rejection evidence remains part of the row closure. |
| `MD-001` | Covered | `group_media_mime_policy_test.dart` proves the exact group media MIME allowlist, declared-MIME rejection, mediaType mismatch rejection, dangerous signature rejection, and known signature mismatch rejection. Upload, send, retry, live receive, encrypted replay, listener, download, and display tests prove invalid declared MIME and spoofed bytes fail before bridge upload, publish/inbox payload creation, local message/media storage, notification preview, auto-download, done-state marking, or thumbnail render. `group_media_fanout_test.dart` preserves existing allowed image/video/voice fan-out. `SMOKE-GAP-05` is satisfied by the focused direct suites plus the group media fanout, broad groups, groups integration, `groups` gate, and `completeness-check` gate; it is not a shell command. No Go/relay MD-001 tests were required because MD-001 changed only Flutter group boundaries. |
| `MD-002` | Covered | `group_media_size_policy_test.dart` proves exact boundary acceptance, per-media overage, total-message overage, malformed/missing/zero/negative/non-integer remote sizes, oversized integer rejection, GIF cap preservation, and MIME-policy separation. Upload, wired composer, voice, send, retry, live receive, encrypted replay, listener, foreground push drain, download, display, and fake-network fan-out tests prove oversized group media is rejected before bridge upload, durable pending-row storage, publish/inbox payload creation, retry resend, local message/media storage, notification preview, auto-download, `media:download`, done-state marking, or thumbnail render. The unqualified foreground integration command was not runnable as written because Flutter detected multiple devices and required `-d`; the same test passed with `-d macos`. `SMOKE-GAP-05` is satisfied by the focused direct suites plus group media fanout, broad groups, groups integration, `groups` gate, and `completeness-check` gate; it is not a shell command. No Go/relay MD-002 tests were required because MD-002 changed only Flutter group boundaries. |
| `MD-003` | Covered | `group_media_integrity_policy_test.dart` anchors SHA-256 normalization, malformed digest rejection, file hash verification, and display eligibility. Model, migration, DB helper, upload, download, send, retry, live receive, encrypted replay, listener, foreground push, feed, group conversation, media-grid, audio, fake-network fan-out, and hydration tests prove group media content hashes are first-class, sent in live/replay descriptors, required before storage, verified before `downloadStatus: done`, and required before display. Tampered downloads are deleted and marked `integrity_failed`; legacy hashless `done` group media renders unavailable instead of media bytes. Thumbnail closure is by absence of any production remote thumbnail display path plus generated thumbnails deriving only from verified content; optional `thumbnailHash` metadata still validates when present. `SMOKE-GAP-05` is satisfied by the focused direct suite, group media fanout, macOS foreground push drain, broad groups, groups integration, `groups` gate, `completeness-check`, and `git diff --check`; it is not a shell command. One plan-listed `feed_wired_test.dart` focus target remains blocked by an unrelated dirty-tree `orbit_wired.dart` switch exhaustiveness error for `AcceptPendingGroupInviteResult.repairPending`; narrower feed application/widget MD-003 tests passed. No Go/relay MD-003 tests were required because MD-003 did not change Go protocol structs or media responses. |
| `MD-004` | Covered | Proof-first upload regression failed on the previous contract because group media had no per-object encryption key/nonce metadata and uploaded the selected file path directly. `MediaAttachment`, DB migration 059, helper/model tests, upload/download use-case tests, send/receive/retry/listener tests, wired tests, fake-network media fanout, new-member onboarding, announcement onboarding, resume recovery, and foreground push drain now prove each group media object is encrypted before relay upload with fresh object key/nonce metadata, encrypted blob hashes are verified before decrypt, plaintext MIME/size is validated after decrypt, live publish plus encrypted replay preserve protected metadata, and cross-object wrong-key decrypt attempts fail without display. Focused suites passed, `flutter test --no-pub -d macos integration_test/foreground_group_push_drain_test.dart` passed, `flutter test --no-pub test/features/groups` passed with `+993`, `flutter test --no-pub test/features/groups/integration` passed with `+114`, `./scripts/run_test_gates.sh groups` passed with `+93`, `./scripts/run_test_gates.sh completeness-check` passed with `693/693` classified, and `git diff --check` passed. `SMOKE-GAP-05` is this evidence bundle, not a shell command. No Go/relay MD-004 tests were required because no Go or relay protocol code changed. |
| `CB-004` | Accepted | `create_group_with_members_use_case_test.dart` now pins mixed invite degradation; `create_group_picker_wired_test.dart` proves the create flow surfaces an explicit warning instead of implying full invite success. |
| `CB-005` | Accepted | `create_group_with_members_use_case_test.dart` now proves config-sync rollback and publish-warning truth; `contact_picker_wired_test.dart` keeps the add-member picker truthful under the same degraded branches. |
| `CB-006` | Accepted | `group_name_panel_test.dart` now proves the shipped create surface exposes only the name field, `create_group_picker_wired_test.dart` proves the create payload omits `description`, and `group_info_wired_test.dart` keeps later edit-time description handling explicit. |
| `CB-007` | Accepted | `create_group_use_case.dart` now falls back to `/mknoon/group/$groupId`, `create_group_use_case_test.dart` pins creator-path persistence on that namespace, and `rejoin_group_topics_use_case_test.dart` already proves rejoin callers consume the stored `topicName`. |
| `CB-008` | Accepted | `create_group_use_case_test.dart` now proves keyless create rolls back the local group and throws instead of returning success into an unusable state. |
| `DV-003` | Accepted | `group_message_listener_test.dart`, `contact_picker_wired_test.dart`, and `group_membership_smoke_test.dart` now pin durable `members_added` history across listener, picker, and recipient surfaces. |
| `DV-004` | Accepted | `accept_pending_group_invite_use_case_test.dart`, `group_list_wired_test.dart`, `group_message_listener_test.dart`, and `invite_round_trip_test.dart` now prove durable `member_joined` history across accept, shipped accept-surface, listener, and existing-member render flows, including the degraded `bridgeError` branch. |
| `DV-008` | Accepted | `group_info_wired_test.dart` and `group_membership_smoke_test.dart` now prove voluntary leave broadcasts a truthful self-removal event and remaining members persist `left the group` history. |
| `DV-013` | Accepted | `send_group_invite_use_case_test.dart`, `create_group_with_members_use_case_test.dart`, and `contact_picker_wired_test.dart` now pin per-recipient batch invite outcomes and user-visible warning surfaces. |
| `DV-014` | Accepted | `create_group_with_members_use_case_test.dart`, `contact_picker_wired_test.dart`, and `create_group_picker_wired_test.dart` now pin the explicit no-latest-key warning contract for create and add-member flows. |
| `ID-001` | Accepted | `create_group_use_case_test.dart`, `create_group_with_members_use_case_test.dart`, and `group_info_wired_test.dart` now prove the creator username is persisted, exported in `groupConfig`, and rendered for other members instead of falling back to a raw peer ID. |
| `ID-002` | Accepted | `group_member_row.dart` now reuses `UserAvatar`, and `group_info_screen_test.dart` plus `group_conversation_screen_test.dart` now prove member-list and conversation surfaces render participant identity with the same avatar component family. |
| `ID-004` | Unsupported | `create_group_picker_wired.dart` and `contact_picker_wired.dart` restrict onboarding selection to active contacts, while `handle_incoming_group_invite_use_case_test.dart` proves invites from non-contacts are rejected as `unknownSender`; the repo does not ship a non-friend onboarding path. |
| `ID-010` | Accepted | `group_info_screen_test.dart` and `group_conversation_screen_test.dart` now prove both group surfaces keep readable participant names and fall back to `RingAvatar` when no profile photo exists. |
| `CX-001` | Accepted | `group_conversation_screen.dart` now routes group long-press through `MessageContextOverlay`, and `group_conversation_screen_test.dart` proves the selected preview, reply/copy actions, and coherent overlay surface. |
| `CX-002` | Accepted | `group_conversation_screen_test.dart` now proves the long-press reply action enters the existing group quote-reply callback with the correct message id. |
| `CX-003` | Accepted | `group_conversation_screen_test.dart` now proves long-press copy writes exact multiline/emoji text to the clipboard, dismisses the overlay, and shows the copied snackbar. |
| `CX-004` | Accepted | `group_conversation_screen_test.dart` now proves the group context surface stays available for supported actions while unsupported edit/delete actions remain hidden. |
| `CX-005` | Accepted | `group_conversation_screen_test.dart` plus `group_conversation_wired_test.dart` now prove reply/copy stay available even when reaction handling is unavailable. |
| `CX-006` | Accepted | `group_conversation_screen_test.dart` now proves the overlay keeps reaction selection alive while the existing swipe-to-quote and row-render coverage remains intact. |
| `CX-007` | Accepted | `orbit_wired_test.dart`, `feed_wired_test.dart`, and `group_conversation_wired_test.dart` now pin the same long-press action contract from Orbit, Feed, and notification-anchor entry points. |
| `UI-001` | Accepted | `group_conversation_screen_test.dart` now proves the group row host keeps exactly one row-local shell across base text, quoted/reaction, and media variants. |
| `UI-002` | Accepted | `group_conversation_screen_test.dart` now re-renders the same row through media and reaction enrichment and proves the shell stays single after the update. |
| `RX-001` | Accepted | `group_reaction_details_sheet.dart` plus `group_conversation_wired_test.dart`, `feed_wired_test.dart`, and `orbit_wired_test.dart` now prove visible group chips open a participant-inspection surface instead of silently mutating. |
| `RX-002` | Accepted | `group_conversation_screen.dart` and `feed_screen.dart` now separate chip inspection from long-press mutation, and `group_conversation_wired_test.dart` proves chip taps leave stored reactions untouched. |
| `RX-003` | Accepted | `group_reaction_details_sheet.dart` now resolves `You`, member usernames, and readable peer-id fallback from group membership state, and `group_conversation_wired_test.dart` proves that lookup directly. |
| `RX-004` | Accepted | `orbit_wired_test.dart` and `feed_wired_test.dart` now pin the same reaction-inspection sheet contract after entering the group from Orbit or Feed. |
| `RX-005` | Accepted | `feed_screen_test.dart` now proves inline group chips route through inspection on both discussion and announcement-reader cards, while `feed_wired_test.dart` keeps Feed-to-conversation inspection parity. |
| `RX-006` | Accepted | `group_reaction_roundtrip_test.dart` proves live reaction fan-out, `announcement_happy_path_test.dart` now proves the announcement-reader path also lands a durable stored replay row, and `group_resume_recovery_test.dart` proves resume/rejoin replay keeps one truthful stored reactor after live-plus-replay dedupe and after post-rotation recovery on a rotated message. |
| `MM-009` | Accepted | `send_group_message_use_case_test.dart` pins the zero-peer plus inbox-fail branch, `retry_failed_group_messages_use_case_test.dart` proves the failed row recovers through the failed-message retry owner, and `group_resume_recovery_test.dart` now proves inbox-store retry skips that failed row while failed-message retry recovers it in place and restores offline delivery. |
| `MM-012` | Accepted | `send_group_message_use_case_test.dart` now proves discussion sends remain allowed while recovery is active, and `group_resume_recovery_test.dart` now proves the real `GroupConversationWired` sender path still sends discussion messages while blocking announcement-admin sends without leaving a stranded local bubble. |
| `RC-009` | Accepted | `pubsub_decryption_failure_test.go` now proves wrong-key, tampered-nonce, and malformed-payload failures emit diagnostics without any `group_message:received` event, while `go_bridge_client_test.dart` routes `group:decryption_failed` and `group:payload_parse_failed` into Flutter's `groupDiagnosticEventStream` without invoking the group message callback. |
| `RC-010` | Accepted | `go-mknoon/node/node_test.go` now proves bounded bursts emit `group:dispatcher_pressure` and `group:dispatcher_overflow` diagnostics with queue-depth, dropped-count, and last-event data, while `go_bridge_client_test.dart` proves overflow diagnostics reach Flutter's owned diagnostics stream and flow logs without invoking the group message callback. |
| `SV-004` | Accepted | `handle_incoming_group_message_use_case_test.dart` now proves same-`messageId` replays cannot rewrite an accepted row when timestamps are tampered or when the replay lands after removal/dissolve cutoffs, and `group_resume_recovery_test.dart` now proves a multi-page inbox replay with a tampered timestamp still materializes only one stored row. |
| `SV-005` | Accepted | `pubsub_decryption_failure_test.go` now proves wrong-key, tampered-nonce, tampered-ciphertext, and malformed-payload group envelopes emit rejection diagnostics without any `group_message:received` event, and `go_bridge_client_test.dart` keeps the owned Flutter diagnostics stream pinned for `group:decryption_failed`. |
| `SV-006` | Accepted | `pubsub_key_rotation_grace_test.go` now proves previous-epoch traffic emits `group_message:received` during grace and stays silent after grace expiry, while the existing `group_message_listener_test.dart` and `handle_incoming_group_message_use_case_test.dart` already pin the Flutter-visible receive-path materialization for any valid group message event. |
| `SV-007` | Accepted | `group_key_update_listener_test.dart` now proves competing same-generation key updates collapse to one stored key and the existing sequential `epoch 2 then epoch 3` proof keeps higher-epoch convergence explicit, while `send_group_message_use_case_test.dart` and `group_resume_recovery_test.dart` keep sending usable after rotation on the winning epoch. |
| `SV-011` | Accepted | `send_group_message_use_case_test.dart`, `rejoin_group_topics_use_case_test.dart`, `drain_group_offline_inbox_use_case_test.dart`, `retry_failed_group_messages_use_case_test.dart`, and `retry_failed_group_inbox_stores_use_case_test.dart` now pin stable begin/success/skip/error/timing flow-event names and required detail keys across the shipped group send, rejoin, drain, and retry owners. |
| `SV-012` | Accepted | `go-mknoon/node/node_test.go` now proves overflow diagnostics are emitted with dropped-count and queue-depth data, and `go_bridge_client_test.dart` proves `group:dispatcher_overflow` reaches Flutter's diagnostics stream and flow logs instead of remaining silent. |
| `RY-007` | Covered | `group_resume_recovery_test.dart` already proves the partitioned member misses split-window live delivery, replays the delayed backlog in cursor order after heal, and resumes later live delivery without duplicate visible rows. |
| `RY-010` | Accepted | `main.dart`, `startup_router.dart`, `handle_app_resumed.dart`, `prepare_notification_route_target_use_case.dart`, `group_list_wired.dart`, and `orbit_wired.dart` now carry full replay dependencies on supported paths, while `accept_pending_group_invite_use_case_test.dart` and `group_list_wired_test.dart` pin the repaired invite-accept drain with a real `GroupMessageListener` and `reactionRepo`. |
| `RY-011` | Accepted | `accept_pending_group_invite_use_case_test.dart` now proves invite acceptance drains backlog reactions when `reactionRepo` is supplied, and `group_list_wired_test.dart` proves the shipped accept flow persists the replayed message and reaction before the pending invite row disappears. |
| `RY-012` | Accepted | `accept_pending_group_invite_use_case_test.dart` now proves `bridgeError` keeps the group persisted, clears the pending invite row, and still stores the durable join event for replay even when live `group:publish` fails, `group_list_wired_test.dart` proves the shipped accept surface tells the user recovery is still catching up, and `invite_round_trip_test.dart` proves a later rejoin plus inbox drain converges without recreating the invite row or duplicating join history. |
| `RY-013` | Accepted | `group_offline_replay_envelope.dart` now stores only the approved replay wrapper plus ciphertext and nonce, and `go-mknoon/node/group_inbox_test.go`, `go-relay-server/group_inbox_test.go`, and `go-relay-server/backend_redis_test.go` now prove that opaque envelope survives request marshaling and cursor retrieval without exposing plaintext content. |
| `RY-014` | Accepted | `drain_group_offline_inbox_use_case_test.dart` now proves encrypted replay preserves quoted replies plus image, video, GIF, file, and audio attachments through the real drain path, while `group_resume_recovery_test.dart` keeps missed announcement replay, voice delivery, and post-rotation delivery readable after resume. |
| `RY-015` | Accepted | `group_resume_recovery_test.dart` now proves removed offline members drain the replayed removal, lose group access, and cannot send after resume while remaining members keep only the before-cutoff backlog, `group_info_wired_test.dart` proves voluntary leave persists a durable left-the-group event before cleanup, and `invite_round_trip_test.dart` proves rejoined members recover on the rotated epoch only. |
| `RY-016` | Accepted | `drain_group_offline_inbox_use_case_test.dart`, `group_resume_recovery_test.dart`, `rejoin_group_topics_use_case_test.dart`, `retry_failed_group_inbox_stores_use_case_test.dart`, `pending_message_retrier_upload_ordering_test.dart`, and the resume lifecycle tests now prove encrypted replay survives cursor continuation, multi-page drain, watchdog resume, sender-owned reaction add/remove replay retry, partition heal, and same-message dedupe without creating a degraded recovery owner. |
| `MD-005` | Partial | Executor evidence from 2026-04-30 confirms current repo behavior does not cover chunked media resume. `p2p_bridge_client.dart` sends whole-object `media:upload` payloads with `id`, `to`, `mime`, `filePath`, and optional `allowedPeers`, and whole-object `media:download` payloads with `id` and `outputPath` only. `upload_media_use_case.dart` encrypts and uploads one full file path; `download_media_use_case.dart` downloads one full blob, validates the completed encrypted hash/decrypt/plaintext, and deletes invalid or partial local files; `retry_incomplete_group_uploads_use_case.dart` retries whole `upload_pending` attachments by blob id. `go-mknoon/node/media.go` streams whole uploads with `io.Copy` and whole downloads with `io.CopyN`; `go-relay-server/media.go` stores only complete uploads and removes incomplete upload files. Passed adjacent whole-object/progress/integrity gates: `cd go-mknoon && go test ./node -run 'MediaUploadProgressReader\|IdleTimeoutReader' -v`; `cd go-relay-server && go test ./... -run 'Media\|GroupMedia' -v`; `flutter test --no-pub test/features/conversation/application/upload_media_use_case_test.dart`; `flutter test --no-pub test/features/conversation/application/download_media_use_case_test.dart`; `flutter test --no-pub test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart`; `flutter test --no-pub test/features/groups/integration/group_media_fanout_test.dart`. No current proof covers chunk manifests, per-chunk hashes, verified chunk reuse, same-peer or other-peer resume, progress without duplicated completed bytes, or corrupted-chunk redownload. `group-real-network-nightly` was fixture-blocked locally because `FLUTTER_DEVICE_ID` and `MKNOON_RELAY_ADDRESSES` were unset. |
| `MD-011` | Covered | Tests-only closure on 2026-04-30. `group_media_fanout_test.dart` proves the post-removal future-media path: after C is removed and A/B advance to epoch 2, B receives and downloads A's future media while C has no message, descriptor/media row, pending download, `media:download`, `blob:decrypt`, epoch-2 key, subscription, or local content. `retry_incomplete_group_uploads_use_case_test.dart` proves retry upload `allowedPeers` and `group:inboxStore` `recipientPeerIds` are rebuilt from the post-removal member set and exclude C. `drain_group_offline_inbox_use_case_test.dart` proves a removed peer with only epoch 1 skips an epoch-2 future media replay before message/media/download/decrypt persistence. Go relay media ACL tests prove a peer omitted from `allowedPeers` cannot download a group blob. Focused Dart files, adjacent removal/UI tests, the tagged Go integration command, Go relay media ACL command, groups integration, `groups`, `completeness-check`, and `git diff --check` passed in the execution evidence. The untagged Go integration command is invalid because integration tests require `-tags integration`; `flutter test --no-pub test/features/groups` still has an unrelated `group_conversation_wired_test.dart:4114` failure; device/real-relay proof is supplemental and fixture-blocked until `FLUTTER_DEVICE_ID` and `MKNOON_RELAY_ADDRESSES` are set. |
| `MD-012` | Covered | MD-012 closure on 2026-04-30. `group_media_integrity_policy_test.dart` pins the quarantine status helpers and keeps quarantine, download retry, and upload retry ownership separate. `download_media_use_case_test.dart` proves unsafe descriptor, relay MIME, content hash, encryption/decrypt, missing decrypted file, plaintext size, and plaintext MIME/signature failures become `integrity_failed` without displayable local paths, while bridge-level blob-not-found remains `failed`. `group_conversation_screen_test.dart`, `media_grid_cell_test.dart`, and `audio_player_widget_test.dart` prove visual and voice rows show explicit `Media unavailable` UI, stable `Retry unavailable media` semantics, and no thumbnail/open/play affordance until verified. `letter_card_test.dart`, `group_conversation_wired_test.dart`, and `retry_incomplete_group_uploads_use_case_test.dart` prove incoming/read-only retry is a per-attachment `downloadMedia(... enforceGroupMediaPolicy: true)` repair path, not failed-message resend or incomplete-upload retry, and never calls `retryFailedGroupMessage`, `retryIncompleteGroupUploads`, `group:publish`, or `group:inboxStore` for download-only repair. `group_conversation_wired_test.dart` proves targeted repaired retry becomes `done` only after verification and failed repair stays quarantined, clears the unsafe local path, deletes the stale file, and does not open full-screen media. `group_media_fanout_test.dart` keeps tampered fake-network downloads quarantined before `done`. Focused MD-012 suites, groups integration, broad `test/features/groups`, `./scripts/run_test_gates.sh groups`, `./scripts/run_test_gates.sh completeness-check`, and `git diff --check` passed. Device/real-relay proof is supplemental for this row and was unavailable in the host-side session. |
| `MD-014` | Partial | MD-014 targeted proof rerun on 2026-04-30 used configured `FLUTTER_DEVICE_ID=347FB118-10D0-40C8-A05B-B0C3BD6B8CCD` and the supplied relay addresses. `./scripts/run_test_gates.sh group-real-network-nightly` passed, including the real CLI peer group recovery test, so the row is no longer blocked only by absent device/relay fixtures. GMAR-004 later fixed the stale simulator media fixture metadata without weakening group media integrity policy, and `flutter test --no-pub -d 347FB118-10D0-40C8-A05B-B0C3BD6B8CCD integration_test/group_new_member_media_simulator_proof_test.dart` passed after clean rebuild. GMAR-004 also accepted host screen/wired visible-state, reopen hydration, retry visibility, and signed offline inbox duplicate-enrichment proof. Missing closure evidence for the broader MD-014 row still includes current full discussion and announcement media/recovery matrix proof, relay outage/recovery and duplicate-prevention breadth, OS-state breadth, and a decision on the file dimension while MD-013 remains unsupported. |
| `EK-001` | Covered | EK-001 closure on 2026-04-30. `go-mknoon/node/protocol_version_test.go` now includes `TestSecureLibp2pChannelRequiredBeforeMknoonProtocols`, proving a deliberately insecure `libp2p.NoSecurity` host cannot connect to a production mknoon node over the raw TCP address, cannot open `ChatProtocol`, and leaves no connected insecure peer on either side. The test is payload-free, so invite, sync, media, group key, and publish payloads are never handed to mknoon protocol handlers over the insecure channel. Existing protocol tests keep secure mknoon nodes negotiating current chat protocol, rejecting unsupported chat protocol versions, and using `InboxProtocol` for group inbox store. Focused EK-001 protocol suite and broader adjacent Go node security/protocol slice passed. App-layer encryption, signatures, and storage-path privacy remain separate rows. |
| `EK-002` | Covered | EK-002 closure on 2026-04-30. `go-mknoon/node/pubsub_test.go` proves relay-visible group message and reaction envelopes omit protected plaintext while carrying encrypted ciphertext/nonce, `go-mknoon/node/group_inbox_test.go` proves group inbox-store request JSON preserves an opaque encrypted replay envelope and omits sensitive plaintext fragments, and `send_group_message_use_case_test.dart` now includes `EK-002 pending inbox retry stores encrypted replay without protected plaintext`, proving persisted pending inbox retry JSON plus the attempted `group:inboxStore` command carry a `group_offline_replay` encrypted envelope and omit protected message body, invite/private-state fragments, media encryption keys, and plaintext push previews. Focused Go, focused Flutter, broader storage-path Dart bundle, `./scripts/run_test_gates.sh groups`, `./scripts/run_test_gates.sh completeness-check`, and `git diff --check` passed. EK-001 transport security, EK-004 signatures, EK-005 future epochs, EK-012 replay protection, and EK-013 secure-storage deletion remain separate rows. |
| `EK-003` | Covered | EK-003 covered by `PREREQ-DEVICE-IDENTITY` on 2026-05-01. Production now has a first-class group member device roster: `GroupMemberDeviceIdentity`, migration `062_group_member_device_identities.dart`, DB helper/model/repository/fake persistence, config snapshots, invite/admission paths, key distribution/listener paths, live/offline message and reaction paths, fake-network harnesses, and Go envelope/config validation all carry device id, transport peer id, device signing key, ML-KEM/key-package material, status, and key-package id while preserving `GroupMember.peerId` as the member/account identity. Regression evidence proves valid bound devices are accepted and same-member unbound devices, signing-key mismatches, transport mismatches, wrong local invite recipients, wrong key-update recipients, and invalid replay senders fail before message/key/event-log/listener/notification/bridge side effects. Passed commands: model/invite domain block, migration/helper/full-chain block, invite admission block, key distribution/listener block, message/listener/offline replay block, fake-network integration block, Go envelope/device validator blocks, `./scripts/run_test_gates.sh groups`, `./scripts/run_test_gates.sh completeness-check`, and `git diff --check`. Paired-iOS and real-relay proof were not required; Android paired proof remains fixture-blocked by missing `adb` and `emulator-5556`. |
| `EK-004` | Covered | EK-004 covered on 2026-05-02 by `trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules-session-EK-004-plan.md`. Production files: `lib/features/groups/application/group_offline_replay_envelope.dart`, `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`, `lib/features/groups/application/group_pending_key_repair_service.dart`, message/reaction/remove/retry/invite-accept/leave/dissolve/group-info sender call sites, direct key/audit/listener paths, and `go-mknoon/node/pubsub_test.go`. Current offline/pending/history replay envelopes are signed at generation and verified before decrypt/apply; unsigned legacy relay payloads, malformed/mismatched/invalid replay signatures, wrong sender/relay bindings, invalid history repair ranges, and pending-key repair replays fail closed before message, reaction, system/member/key/timeline, cursor, notification, receipt/read-state, or event-log mutation. Direct invite, invite revocation, welcome/key-package material embedded in invites, direct `group_key_update`, signed transition audit, local `group_created`, and Go live PubSub signature validation evidence are preserved. Evidence passed: focused EK004 Flutter bundle (`+16`), direct key/audit/remote-family selector (`+12`), local create/event-log (`+19`), invite wildcard (`+149`), key wildcard (`+49`), fake-network invite/resume/membership replay bundle (`+80`), Go invalid-signature selector for all shipped live event families, targeted format, scoped analyzer with info-only diagnostics, `groups` (`+103`), `completeness-check` (`712/712`), and `git diff --check`. `group_info_wired.dart` still has the documented pre-existing warning-only analyzer cluster and no analyzer errors. Real device/relay proof is supporting-only for EK-004 because the row closes on deterministic host/fake-network/Go replay-validation seams; full MLS semantics and separate account/device registry are not claimed. |
| `EK-005` | Covered | EK-005 covered on 2026-05-01 by `trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules-session-PREREQ-FUTURE-EPOCH-KEY-REPAIR-plan.md`. Migration `063_group_pending_key_repairs`, `group_pending_key_repairs_db_helpers.dart`, `GroupPendingKeyRepairRepositoryImpl`, and `group_pending_key_repair_service.dart` add a durable deduped future/missing-key repair queue. Offline replay with a missing epoch now stores a pending placeholder, preserves encrypted replay JSON, emits a scoped repair request, retries after a saved key update, re-enters normal verified replay handling, replaces the placeholder with the decrypted row on success, and finalizes invalid or unrecoverable repairs idempotently as safe `undecryptable` text without plaintext, media downloads, duplicate rows, or endless retry loops. Commands relied on: RED focused drain test failed before production; migration/helper tests passed (`+4`); repository tests passed (`+2`); focused drain/key-listener/message-listener/UI/bridge tests passed (`+5`); full migration chain passed (`+6`); direct owner Flutter suites passed (`+178`, `+36`, `+49`); Go focused and owner regexes passed; `./scripts/run_test_gates.sh groups` passed (`+101`); `./scripts/run_test_gates.sh completeness-check` passed (`703/703`); `git diff --check` passed. Unknown future live epochs may still reject before normal Go delivery; recovery is through durable offline replay/key-arrival repair. |
| `EK-006` | Covered | EK-006 accepted on 2026-05-01. `go-mknoon/node/pubsub_key_rotation_grace_test.go` proves the raw epoch policy: authorized previous-epoch traffic is accepted during grace, previous-epoch traffic is rejected after grace expiry, current-epoch traffic still accepts during grace, a removed/non-member sender using a valid previous-epoch envelope is rejected as `reject:non_member`, subscription handling decrypts previous-epoch traffic during grace, and subscription handling drops previous-epoch traffic after grace expiry without `group_message:received`. Flutter app-level proof covers the shipped UI/state outcome: `send_group_message_use_case_test.dart` rejects local stale sends before persistence or bridge publish; `handle_incoming_group_message_use_case_test.dart` accepts only pre-cutoff removed-sender messages and rejects at-cutoff/later replay without overwriting the accepted row; `drain_group_offline_inbox_use_case_test.dart` carries the removedAt cutoff across cursor pages; and `group_membership_smoke_test.dart` proves remaining peers accept only delayed pre-cutoff removed-sender envelopes while at-cutoff envelopes create no UI rows, plus a self-removed member cannot send after cleanup. Passed commands: focused Go EK-006 grace/expiry suite, focused handler removed-sender proof (`+3`), offline replay cutoff (`+1`), stale local send (`+1`), live fake-network cutoff (`+1`), self-removal send guard (`+1`), and `git diff --check`. Supporting real-network/device-lab/packet-capture proof remains supplemental and was not run. No first-class device identity, MLS commit semantics, or new transport cryptography is claimed. |
| `EK-007` | Partial | EK-007 closure attempt on 2026-04-30 is prerequisite-blocked by `missing_scheduled_rotation_primitives`. Manual/app-triggered rotation continuity is proven by Go `TestGroupRotateKey_IncrementsEpoch` and `TestGroupGenerateNextKey_DoesNotMutateStoredKeyState`, Flutter `rotate_group_key_use_case_test.dart`, `rotate_and_distribute_group_key_use_case_test.dart`, `group_key_update_listener_test.dart`, `send_group_message_use_case_test.dart`, `member_removal_integration_test.dart`, `invite_round_trip_test.dart`, and `group_resume_recovery_test.dart`. The row remains Partial because searches found no scheduled/periodic key rotation service, timer, policy, configuration, or background owner; therefore there is no row-specific scheduled-rotation proof that scheduled and manual rotations share the same monotonic distribution/promotion/send-binding contract. |
| `EK-008` | Open | EK-008 closure attempt on 2026-04-30 is prerequisite-blocked by `missing_first_class_device_identity_model`, `missing_device_compromise_recovery_primitives`, and `missing_per_device_key_package_and_future_key_exclusion`. Adjacent evidence proves only fake-network same-peer device-local unsubscribe while preserving sibling delivery, member-scoped key rotation/distribution, member removal/leave future-key exclusion, key-update save/promotion ordering, and Go member-level sender/transport/public-key/signature binding. The row remains Open because no production model can identify or revoke only B2, no per-device key package or distribution roster exists, and no live/equivalent proof shows B2 excluded from future epoch updates/content while B1 and other members continue. |
| `EK-010` | Open | EK-010 closure attempt on 2026-04-30 is prerequisite-blocked by `missing_signed_commit_transition_model`, `missing_group_transition_event_log`, `missing_commit_replay_and_fork_protection`, and `missing_independent_state_verification_from_commits`. Adjacent evidence proves PubSub security-family signatures fail closed, metadata `configVersion`/`stateHash` tamper checks reject invalid updates, membership watermarks block stale rollback after restart, and rotation/key-update ordering remains green. The row remains Open because there is no durable signed commit or transition-event model for create/add/remove/role/metadata/key-rotation/recovery changes, no previous-state dependency or commit-chain hash, no local append-only/tamper-evident group event log, and no replay/fork protection over signed transition history. |
| `EK-011` | Covered | EK-011 covered by `PREREQ-WELCOME-KEY-PACKAGE` Executor and recovery evidence on 2026-05-01. `GroupWelcomeKeyPackage` now models and validates package id/material/hash, recipient member/device/transport/ML-KEM binding, invite id, group id, epoch, issue/expiry, and schema version; `GroupInvitePayload` and `GroupInvitePolicy` include the package in the signed canonical encrypted invite payload. Send rejects weak package material before signing/encryption. Incoming store, direct handle, and pending accept reject stale, malformed, tampered, wrong-recipient, wrong-device, wrong-transport, wrong-package, and weak packages before pending/group/key/join/mailbox/publish/listener/notification/bridge side effects. Migration/helper/repository wiring adds durable package tombstones; successful accept records the tombstone after materialization, replay under a changed invite id fails before state, and file-backed repository tests prove close/reopen survival. The recovery pass adds `defaultGroupWelcomeKeyPackageIdForDevice`, wires `ownKeyPackageId` through `main.dart`, `GroupListWired`, and `OrbitWired`, and proves valid first-class package invites store/accept through production listener and UI pending-accept paths while a wrong local package id still rejects. Evidence passed: focused welcome-package owner suite (`120` tests), recovery listener/UI focused tests (`3` + `1` + `1` tests), invite wildcard (`117` tests), targeted analyzer, groups gate (`101` tests), completeness-check (`706/706`), and `git diff --check`. |
| `EK-012` | Covered | EK-012 covered on 2026-05-01 by `trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules-session-PREREQ-REMOTE-EVENT-FAMILIES-plan.md` plus prior replay prerequisites. The final missing event-family blockers are closed by trusted-private encrypted system-event support for `member_banned`, `member_unbanned`, and `group_message_deleted`: `trusted_private_group_system_event.dart` parses canonical tombstone fields, `GroupMessageListener` routes those families through existing device binding, authorization, signed transition audit/event-log integration, deterministic tombstone/timeline rows, duplicate replay idempotency, stale ban-after-unban/rejoin protection, and stale/wrong-group/newer-message delete protection. Go invalid-signature coverage now includes those new families. Prior prerequisites keep welcome/key-package tombstones, signed system-transition replay, durable receipt replay, future/missing-key repair replay, message/reaction replay, and invite replay covered. Evidence passed: listener PREREQ tests (`+3`), offline replay PREREQ test (`+1`), Go invalid-signature regex, `groups`, `completeness-check`, and `git diff --check`; targeted analyzer reports only documented pre-existing warning debt in `group_message_listener.dart` and no analyzer errors. EK-004 is covered separately for complete offline replay signature-equivalence. |
| `EK-013` | Covered | EK-013 closed on 2026-04-30. `GroupRepositoryImpl.saveKey` now enforces a latest-plus-previous group-key retention policy: saving generation 3 after generations 1 and 2 keeps generations 2 and 3, removes generation 1 from SQLCipher `group_keys`, and deletes the matching shared push `SecureKeyStore` mirror. `removeAllKeys` still clears all group keys and secure-store mirrors, `mirrorAllKeysToSecureStore` still mirrors approved persisted rows, and `InMemoryGroupRepository` follows the same bounded retention behavior for fake-backed group tests. Focused repository, rotation/key-update, and Go bridge/node validator gates passed. SQLCipher `group_keys` remains the approved app-local encrypted store for current/previous group-operation keys, while backup/export product policy, per-device key packages, debug export redaction, and memory wiping remain separate rows. |
| `EK-014` | Covered | EK-014 closed on 2026-04-30. `contact_safety_number.dart` builds stable grouped safety numbers from peer id plus Ed25519 and optional ML-KEM identity keys, and `group_member_identity_safety.dart` compares current group-member keys with the saved contact keys. `group_info_wired.dart`, `group_info_screen.dart`, and `group_member_row.dart` now surface `Identity changed`, `Current safety`, and `Saved safety` in the member list when saved and current identity keys differ. `contact_safety_number_test.dart`, `group_info_screen_test.dart`, and `group_info_wired_test.dart` prove deterministic/change-sensitive safety numbers, changed-key warnings, current/saved safety-number display, matching-key no-warning behavior, and no false warning without comparable saved contact/current key material. Focused and combined EK-014 gates, `./scripts/run_test_gates.sh completeness-check`, and `git diff --check` passed. First-class per-device verification remains EK-003/EK-008 scope. |
| `ID-003` | Covered | `group_messaging_smoke_test.dart` proves non-friend members can exchange discussion traffic once they share membership, and the `group_test_user.dart` harness avoids contact-repo shortcuts. |
| `ID-008` | Covered | `group_membership_smoke_test.dart`, `invite_round_trip_test.dart`, and `group_message_listener_test.dart` together cover duplicate re-add, duplicate invite, and stale membership replay de-duplication. |
| `ID-009` | Covered | `handle_incoming_group_invite_use_case_test.dart` proves avatar metadata persistence, and the accept path reuses the same payload materialization contract before the feed refresh assertions consume it. |
| `MM-008` | Covered | `send_group_message_use_case_test.dart` proves pending publish-success rows promote only through the owned inbox-store completion path. |
| `MM-010` | Covered | `group_conversation_wired_bg_task_test.dart` directly covers discussion and announcement sends across lock, route unmount, and zero-peer fallback branches. |
| `MM-013` | Covered | `group_resume_recovery_test.dart` covers media recovery through the real group sender path, and the integration harness keeps member transport independent from friendship edges. |
| `RC-006` | Covered | `handle_incoming_group_message_use_case_test.dart`, `group_message_listener_test.dart`, and `group_conversation_wired_test.dart` together prove row upsert, shared media download joining, and scroll preservation without duplicate rows. |
| `SV-008` | Covered | `group_membership_smoke_test.dart` and `invite_round_trip_test.dart` cover concurrent role/member conflict convergence plus rotated re-invite recovery. |
| `SV-010` | Accepted | `bridge_group_helpers_test.dart` already pins the canonical `/mknoon/group/...` bridge response and join payload contract, and `create_group_use_case_test.dart` now proves the creator fallback and persisted group row stay on that same namespace when `topicName` is omitted. |

### Explicit Residual Follow-Up (2026-04-13)

- None for sender-owned reaction replay durability after Report `70`:
  `send_group_reaction_use_case_test.dart`,
  `remove_group_reaction_use_case_test.dart`,
  `retry_failed_group_inbox_stores_use_case_test.dart`,
  `announcement_happy_path_test.dart`, and
  `group_resume_recovery_test.dart` now prove exact-payload staging plus
  retry/resume convergence for reaction add/remove.

### Shared Prerequisite Sessions

| Session | Closure state | Concrete repo evidence |
|---------|---------------|------------------------|
| `PREREQ-GROUP-OFFLINE-REPLAY` | Accepted | `group_offline_replay_envelope.dart` now materializes opaque encrypted replay envelopes on the Flutter side, `go-mknoon/node/group_inbox_test.go` plus `go-relay-server/group_inbox_test.go` and `backend_redis_test.go` prove those envelopes stay opaque across node and relay storage/retrieval, and the replay batch plus invite/rejoin/retry lifecycle batches passed with the new contract in place. |
| `PREREQ-GROUP-PROOF-HARNESS` | Accepted | `go-mknoon/node/group_security_harness_test.go` now centralizes raw-envelope mutation, local-node connect/publish, event wait, and grace-fixture helpers, while `pubsub_decryption_failure_test.go` and `pubsub_key_rotation_grace_test.go` now reuse that seam directly for later `RC-009` / `SV-004..007` closure work. |
| `PREREQ-GROUP-DISPATCHER-OVERFLOW` | Accepted | `go-mknoon/node/event_dispatcher.go` now surfaces dispatcher pressure/overflow diagnostics, `go-mknoon/node/node_test.go` proves those signals carry queue-depth and dropped-count data under burst load, and `go_bridge_client_test.dart` proves `group:dispatcher_overflow` reaches Flutter diagnostics and flow logs without pretending to be a delivered group message. |

## 0A. 2026-04-12 Deployed-Relay Acceptance

- Full suites green: Flutter host-side `/private/tmp/flutter_full_suite_20260412/flutter_test_dir.log` (`02:53 +5492 ~5: All tests passed!`), `go-mknoon` `/tmp/go-mknoon-full-suite.log`, and relay `/tmp/go-relay-server-full-suite.log`.
- Live-lane passes green: Android background reconnect after bounded local build-state reset `/private/tmp/acceptance_20260412/background_reconnect_android_rerun1.log`; transport E2E `/private/tmp/acceptance_20260412/lane2.log`; WiFi relay fallback smoke after the truthful direct-transport contract fix `/private/tmp/acceptance_20260412/lane3_rerun.log`; media stable-ID smoke `/private/tmp/acceptance_20260412/lane4.log`; group recovery E2E `/private/tmp/acceptance_20260412/lane5.log`; soak E2E `/private/tmp/acceptance_20260412/lane6.log`; notification-open UI smoke on the primary iOS pair `/private/tmp/acceptance_20260412/notification_open_ui_primary_ios.log`; real multi-device `MD-004` on the primary iOS pair `/private/tmp/acceptance_20260412/group_multi_device_real_primary_ios.log`.
- Truthful multi-relay skips: `/private/tmp/acceptance_20260412/lane7.log` and `/private/tmp/acceptance_20260412/lane8.log` both ended `All tests skipped.` because no two-relay `MKNOON_RELAY_ADDRESSES` environment was configured. They are not counted as multi-relay proof.

## 0B. Report 85 Group Onboarding And Crypto Coverage (2026-04-29)

Report 85 (`Test-Flight-Improv/85-group-onboarding-and-crypto-test-coverage.md`) added or tightened the following group-chat test evidence. These rows are intentionally classified by evidence type so fake-network/app-boundary coverage is not confused with paired-simulator or relay-lab proof.

| Area | Closure state | Concrete repo evidence |
|------|---------------|------------------------|
| New-member discussion media/no-backfill | Covered at fake-network/app layer; configured simulator/reopen proof accepted; broader matrix residuals remain | `group_new_member_onboarding_test.dart` proves Bob receives only post-join text/image/video/voice, preserves media descriptors, triggers downloads, and keeps pre-join history out. GMAR-003 adds Bob/Charlie multi-new-member proof where both independently download Alice's same post-join image/video/voice while pre-join text/media rows, attachment rows, pending downloads, and pre-join media download calls remain absent. GMAR-004 adds configured simulator visible video/voice proof plus host reopen hydration and retry/offline duplicate evidence. |
| Multi-add epoch convergence | Covered at fake-network/app layer | `group_new_member_onboarding_test.dart` proves Bob and Charlie converge on the same key epoch and receive the same post-add message. |
| Add/send boundary | Covered at fake-network/app layer | `group_new_member_onboarding_test.dart` pins the current contract: a staged but unsubscribed new member misses the racing message and receives the first post-subscription message exactly once. |
| New-member reactions and quoted replies | Covered at fake-network/widget layer | `group_new_member_onboarding_test.dart` proves post-join reaction fan-out without pre-join reaction state and renders `Message unavailable` for a post-join quote whose parent predates the join. |
| Announcement new-reader media/no-backfill | Covered at fake-network/app layer; simulator residual remains | `announcement_new_reader_onboarding_test.dart` proves post-join admin image/video/voice reaches a newly-added reader with descriptors and no pre-join admin post. |
| Integrated real crypto first-add/re-add | Covered at real Go-bridge app boundary; live GossipSub residual remains | `group_real_crypto_onboarding_test.dart` generates real bridge identities/ML-KEM keys, accepts encrypted invites through the app handler, decrypts first-add and re-add group ciphertext, and proves retained old key material cannot decrypt the current epoch. |
| Existing/newly-added/non-creator media fan-out | Covered at fake-network/app layer; configured simulator render proof accepted; live GossipSub/final matrix residuals remain | GMAR-002 tightened `group_media_fanout_test.dart` on 2026-05-02 so existing Bob and Charlie each independently complete Alice's image/video/voice downloads with matching message ids, attachment metadata, `done` status, local paths, and exact per-recipient download calls; the same suite proves one recipient's forced download failure remains observable while the other recipient succeeds. GMAR-003 adds newly-added Bob media to Alice/Charlie and existing non-creator Charlie media to Alice/Bob, both with completed downloads, sender identity, key epoch, metadata, and exact per-recipient download calls. GMAR-004 accepts the configured simulator preview/playback proof for representative visible video/voice rows. |
| Foreground push media drain | Covered by direct foreground-router/inbox integration; OS-state residual remains | `foreground_group_push_drain_test.dart` now covers targeted group media drain, descriptor preservation, one download trigger, and no duplicate row/notification. |
| Stale removed-group notification denial | Covered host-side; paired simulator residual remains | `resolve_group_notification_route_target_use_case_test.dart` covers stale removed-group route denial after local cleanup, and `group_message_listener_test.dart` proves self-removal suppresses later group notifications. |
| Paired group-smoke criteria | Covered by host criteria tests; configured paired run residual remains | `routing_smoke_group_criteria_test.dart` and `routing_smoke_group_criteria.dart` require receiver-visible G2/G4/G5/G7/G8 evidence instead of sender-only or pending results. |
| Retry/media recovery host safety net | Revalidated host-side; configured simulator UI proof accepted; broader device-lab residual remains | `retry_incomplete_group_uploads_use_case_test.dart`, `retry_failed_group_messages_use_case_test.dart`, and `group_conversation_screen_test.dart` cover incomplete-upload retry, failed-message retry, and failed-media row retry/delete controls. GMAR-004 adds configured simulator visible video/voice proof, wired reopen hydration, and signed offline inbox duplicate-enrichment coverage. |
| Relay fixture closure guard | Gate wiring covered; configured relay run required for pass | `multi_relay_failover_test.dart` now supports `MKNOON_REQUIRE_MULTI_RELAY=true`; `./scripts/run_test_gates.sh group-real-network-nightly` requires `FLUTTER_DEVICE_ID` and at least two relay addresses. |
| Partition/heal durable inbox recovery | Covered for fake-network durable-inbox contract; real network residual remains | `group_resume_recovery_test.dart` now stages three missed split-window messages across cursor-ordered durable inbox pages and proves post-heal live delivery resumes. |
| Same-account host convergence | Covered at host fake-network layer; real device residual remains | `group_multi_device_convergence_test.dart` remains the same-account oracle for sent history, membership, mute, unread, and notification locality; `group_multi_device_policy_test.dart` pins composer drafts as device-local state. |
| Go membership-event signature guard | Covered at Go envelope-validator layer | `pubsub_test.go` adds forged `members_added` signature rejection while accepting the same payload when signed by the real admin. |

## 0C. MD-001 Media MIME Safety Closure (2026-04-30)

MD-001 adds `test/core/media/group_media_mime_policy_test.dart` as the policy anchor and extends the existing upload, download, send, retry, live receive, replay, listener, and media-grid tests named in the row crosswalk. The focused MD-001 direct suite passed with `+243`, `group_media_fanout_test.dart` passed with `+2`, `flutter test --no-pub test/features/groups` passed with `+973`, `flutter test --no-pub test/features/groups/integration` passed with `+112`, `./scripts/run_test_gates.sh groups` passed with `+93`, and `./scripts/run_test_gates.sh completeness-check` passed. `SMOKE-GAP-05` maps to that evidence bundle; it is not a shell target.

## 0D. MD-002 Media Size Safety Closure (2026-04-30)

MD-002 adds `test/core/media/group_media_size_policy_test.dart` as the policy anchor and extends the existing upload, send, retry, live receive, encrypted replay, listener, foreground push, download, media-grid, wired composer, and fake-network fanout tests named in the row crosswalk. Focused direct suites passed, `flutter test --no-pub test/features/groups/integration/group_media_fanout_test.dart` passed, `flutter test --no-pub -d macos integration_test/foreground_group_push_drain_test.dart` passed after the unqualified command required device selection, `flutter test --no-pub test/features/groups` passed with `+985`, `flutter test --no-pub test/features/groups/integration` passed with `+113`, `./scripts/run_test_gates.sh groups` passed with `+93`, `./scripts/run_test_gates.sh completeness-check` passed with `690/690` classified, and `git diff --check` passed. `SMOKE-GAP-05` maps to that evidence bundle; it is not a shell target.

## 0E. MD-003 Media Integrity Closure (2026-04-30)

MD-003 adds `test/core/media/group_media_integrity_policy_test.dart` and extends the model, migration, DB helper, upload, download, send, retry, live receive, encrypted replay, listener, foreground push, feed, group conversation, media-grid, audio, and fake-network fanout tests named in the row crosswalk. Focused direct suites passed with `+435`, `flutter test --no-pub test/features/groups/integration/group_media_fanout_test.dart` passed with `+4`, `flutter test --no-pub -d macos integration_test/foreground_group_push_drain_test.dart` passed with `+7`, `flutter test --no-pub test/features/groups` passed with `+991`, `flutter test --no-pub test/features/groups/integration` passed with `+114`, `./scripts/run_test_gates.sh groups` passed with `+93`, and `./scripts/run_test_gates.sh completeness-check` passed with `692/692` classified. The plan-listed `feed_wired_test.dart` focus target is not a valid MD-003 signal in this dirty tree because it fails to compile in unrelated `orbit_wired.dart` missing a `repairPending` switch case; narrower feed application/widget MD-003 tests passed. Thumbnail closure is explicit: group code has no remote thumbnail blob/path display surface, optional thumbnail hashes validate when present, and generated thumbnails derive only from verified content. `SMOKE-GAP-05` maps to this evidence bundle; it is not a shell target.

## 0F. MD-004 Media Key Separation Closure (2026-04-30)

MD-004 adds per-object group media encryption metadata to `MediaAttachment`, migration 059, DB helpers, upload and download use cases, send/receive/retry/listener paths, foreground push drain, fake-network fanout, and onboarding/resume integrations. The proof-first regression failed before implementation because group media lacked `encryptionKeyBase64`/`encryptionNonce` and did not encrypt before relay upload. The final contract generates a fresh key/nonce per group media object, uploads encrypted bytes, computes `contentHash` over the encrypted blob, carries decrypt metadata inside the encrypted group message/replay descriptor, verifies encrypted hash before decrypt, validates plaintext MIME/size after decrypt, and rejects wrong-key/cross-object decrypt attempts before display. Focused MD-004 suites passed, required fanout/onboarding/resume/foreground integrations passed, `flutter test --no-pub test/features/groups` passed with `+993`, `flutter test --no-pub test/features/groups/integration` passed with `+114`, `./scripts/run_test_gates.sh groups` passed with `+93`, `./scripts/run_test_gates.sh completeness-check` passed with `693/693` classified, and `git diff --check` passed. `SMOKE-GAP-05` maps to this evidence bundle; it is not a shell target.

## 0G. MD-011 Removed-Member Future Media Closure (2026-04-30)

MD-011 is a tests-only closure. `group_media_fanout_test.dart` proves live post-removal future media reaches remaining B and not removed C after rotation to epoch 2; C has no descriptor, message, media row, pending download, `media:download`, `blob:decrypt`, epoch-2 key, subscription, or local decrypted content. `retry_incomplete_group_uploads_use_case_test.dart` proves retry media `allowedPeers` and inbox `recipientPeerIds` exclude removed C, while `drain_group_offline_inbox_use_case_test.dart` proves C with only epoch 1 cannot decode or persist epoch-2 future media replay. Go relay media ACL coverage proves omitted peers cannot download group blobs. The invalid untagged Go integration command is accepted as a plan-command defect because the test file is tagged `//go:build integration` and the tagged command passed. `flutter test --no-pub test/features/groups` still fails in unrelated `group_conversation_wired_test.dart:4114`; the named `groups` gate passed. Device/real-relay proof is supplemental and remains fixture-blocked until `FLUTTER_DEVICE_ID` and `MKNOON_RELAY_ADDRESSES` are configured.

## 0H. MD-012 Unsafe Media Quarantine And Retry UI Closure (2026-04-30)

MD-012 closes the unsafe media quarantine UI path. `integrity_failed` is the accepted quarantine status for unsafe group media, while bridge-level missing blobs stay `failed`. Download policy now quarantines unsafe descriptor, relay MIME, content hash, encryption/decrypt, missing decrypted file, plaintext size, and plaintext MIME/signature failures without leaving displayable local bytes. Visual and voice rows render explicit `Media unavailable` UI with stable `Retry unavailable media` semantics and no thumbnail/open/play affordance until verification succeeds. Incoming/read-only retry is scoped to per-attachment `downloadMedia(... enforceGroupMediaPolicy: true)` repair and does not call failed-message resend, incomplete-upload retry, `group:publish`, or `group:inboxStore`. Focused MD-012 suites, `group_media_fanout_test.dart`, `test/features/groups/integration`, broad `test/features/groups`, `./scripts/run_test_gates.sh groups`, `./scripts/run_test_gates.sh completeness-check`, and `git diff --check` passed. Device/real-relay proof is supplemental and remains outside this host-side row closure.

## 0I. MD-014 Simulator Media Matrix Targeted Recheck (2026-04-30)

MD-014 remains Partial. The targeted recheck used `FLUTTER_DEVICE_ID=347FB118-10D0-40C8-A05B-B0C3BD6B8CCD` and the supplied `MKNOON_RELAY_ADDRESSES`; `./scripts/run_test_gates.sh group-real-network-nightly` passed, including the real CLI peer group recovery test. GMAR-004 later fixed the configured simulator media proof by adding truthful fixture content hashes and encryption metadata, and `flutter test --no-pub -d 347FB118-10D0-40C8-A05B-B0C3BD6B8CCD integration_test/group_new_member_media_simulator_proof_test.dart` passed after clean rebuild. The configured video/voice render proof is no longer an open MD-014 blocker. Remaining closure evidence still includes the full discussion/announcement image/video/GIF/voice/file matrix, OS-state breadth, relay outage/recovery and duplicate-prevention breadth, and MD-013 file-dimension scope reconciliation.

## 0I-a. Targeted Evidence/Gate Recheck Summary (2026-04-30)

Rows rechecked at this earlier evidence-gate pass: GL-008, LP-002, LP-006, LP-007, LP-011, LP-013, IJ-010, EK-006, and MD-014. No target row moved to Covered during that pass; GL-008, LP-002, LP-013, IJ-010, and EK-006 moved to Covered later through their row-owned session plan evidence recorded in the row-closure crosswalk above.
The remaining rows LP-007 and LP-011 kept their existing Partial evidence with focused direct gates passing and exact live/raw/device proof still missing. LP-006 is reclassified to implementation-ready/needs code-and-test follow-up because its direct zero-peer publish proof is red. At this earlier pass, MD-014 was reclassified to implementation-ready because configured real-network proof passed but configured simulator media rendering proof failed; GMAR-004 later accepted that configured simulator proof, leaving only the broader MD-014 matrix residuals listed above.

## 0J. EK-001 Secure Libp2p Channel Closure (2026-04-30)

EK-001 closes with a Go host-level transport-security proof. `TestSecureLibp2pChannelRequiredBeforeMknoonProtocols` starts a production mknoon node through `Node.Start`, starts a `libp2p.NoSecurity` host, restricts the attempt to the mknoon node's raw TCP address, and proves the insecure host cannot connect or open `ChatProtocol`; both peers also report no retained insecure connection. The test sends no group payload or secret, so failure occurs before invite, sync, media, or publish handling. The focused EK-001 protocol command and broader adjacent Go node security/protocol slice passed. EK-002, EK-004, EK-005, and other app-layer cryptographic rows remain separate.

## 0K. EK-002 Storage-Path Privacy Closure (2026-04-30)

EK-002 closes with infrastructure-visible payload proof across live relay, mailbox/inbox-store, and persisted retry storage paths. Go PubSub tests prove live group message and reaction envelopes expose only encrypted ciphertext/nonce while protected plaintext remains decryptable only with the group key. Go inbox-store tests prove mailbox request JSON preserves an opaque encrypted replay envelope and omits sensitive plaintext. The new Flutter retry test keeps `group.encrypt` opaque, forces inbox-store failure, and proves both persisted pending retry JSON and the attempted `group:inboxStore` command omit protected message body, invite/private-state fragments, media encryption key material, and plaintext push previews while carrying a `group_offline_replay` envelope. Focused Go, focused Flutter, broader storage-path Dart bundle, `groups`, `completeness-check`, and `git diff --check` passed. Signature, future-epoch, replay-protection, transport-security, and secure-storage rows remain separate.

---

## 1. Domain Layer

### 1.1 GroupModel
**File:** `test/features/groups/domain/models/group_model_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `GroupModel` | fromMap/toMap round-trip preserves all fields | DB round-trip |
| | GroupType enum converts correctly | Enum mapping |
| | GroupRole enum converts correctly | Enum mapping |
| | copyWith creates new instance with updated fields | Immutable update |

### 1.2 GroupMessage
**File:** `test/features/groups/domain/models/group_message_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `GroupMessage` | fromMap/toMap round-trip preserves all fields | DB round-trip |
| | round-trip preserves quoted_message_id | Quoted reply persistence |
| | isIncoming bool correctly converts from int | DB bool mapping |
| | toMap converts isIncoming bool to int | DB bool mapping |
| | media defaults to empty list | Default state |
| | can be constructed with media attachments | Media construction |
| | copyWith preserves and replaces media | Immutable update |
| | copyWith preserves and replaces quotedMessageId | Immutable update |

### 1.3 GroupMember
**File:** `test/features/groups/domain/models/group_member_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `GroupMember` | fromMap/toMap round-trip preserves all fields | DB round-trip |
| | MemberRole enum converts correctly | Enum mapping |
| | equality based on groupId and peerId | Value equality |

### 1.4 GroupInvitePayload
**File:** `test/features/groups/domain/models/group_invite_payload_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `GroupInvitePayload` | toInnerJson serializes all required fields | Serialization |
| | fromInnerJson round-trips with toInnerJson | Round-trip |
| | toJson wraps payload in v1 envelope with type group_invite | v1 envelope construction |
| | fromJson parses v1 group_invite envelope | v1 envelope parsing |
| | fromJson returns null for chat_message type | Type guard |
| | buildEncryptedEnvelope produces v2 group_invite envelope | v2 envelope construction |
| `fromInnerJson returns null for missing required fields` | returns null when groupId is missing | Missing field guard |
| | returns null when groupKey is missing | Missing field guard |
| | returns null when groupConfig is missing | Missing field guard |
| | returns null when input is not valid JSON | Malformed input guard |
| `parseEncryptedEnvelope` | parses v2 group_invite envelope | v2 envelope parsing |
| | returns null for v2 chat_message (wrong type) | Type guard |
| | returns null for v1 group_invite | Version guard |
| | returns null for garbage JSON | Malformed input guard |
| | returns null when encrypted block is missing kem/ciphertext/nonce | Missing field guard |

### 1.5 GroupKeyInfo
**File:** `test/features/groups/domain/models/group_key_info_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `GroupKeyInfo` | fromMap/toMap round-trip preserves all fields | DB round-trip |
| | equality based on groupId and keyGeneration | Value equality |

### 1.6 GroupMessagePayload
**File:** `test/features/groups/domain/models/group_message_payload_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `GroupMessagePayload` | fromJson/toJson round-trip preserves all fields | Wire round-trip |
| | toJson omits null optional fields | Sparse serialization |

### 1.7 GroupReactionPayload
**File:** `test/features/groups/domain/models/group_reaction_payload_test.dart`

| Test | What it covers |
|------|----------------|
| round-trips add reaction | Serialization round-trip |
| round-trips remove reaction | Remove action round-trip |
| preserves multi-codepoint emoji | Unicode emoji handling |
| returns null for invalid JSON | Malformed input guard |
| returns null for missing fields | Missing field guard |
| toMessageReaction creates valid model | Model conversion |

### 1.8 PendingGroupInvite
**File:** `test/features/groups/domain/models/pending_group_invite_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `PendingGroupInvite` | fromPayload derives preview fields and expiry | Factory construction |
| | fromMap/toMap round-trip preserves fields | DB round-trip |
| | isExpiredAt returns true on or after expiry | Expiry logic |

### 1.9 GroupBacklogRetentionPolicy
**File:** `test/features/groups/domain/models/group_backlog_retention_policy_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `group backlog retention policy` | uses a 7 day retention window | Policy constant |
| | cutoff helper subtracts the retention window in UTC | Cutoff calculation |

### 1.10 GroupMembershipLimitPolicy
**File:** `test/features/groups/domain/models/group_membership_limit_policy_test.dart`

| Test | What it covers |
|------|----------------|
| pins the repo-owned max group size contract at 50 members | Limit constant |
| remaining slots counts total members including the creator | Slot counting |
| overflow count stays zero at the limit and grows past it | Overflow detection |
| ensureWithinGroupMembershipLimit throws with overflow metadata | Enforcement |

### 1.11 GroupMultiDevicePolicy
**File:** `test/features/groups/domain/models/group_multi_device_policy_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `group multi-device policy` | shares only joined-device group-authoritative state | Shared state scope |
| | keeps local installation state device-specific | Local state scope, including composer drafts |
| | shared and device-local helpers stay aligned with the mapping | Helper alignment |

### 1.12 GroupRepositoryImpl
**File:** `test/features/groups/domain/repositories/group_repository_impl_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `Groups` | saveGroup and getGroup round-trip | Persistence round-trip |
| | getAllGroups returns all groups | List query |
| | saveGroup and getGroup preserve announcement type through DB mapping | Announcement type |
| | updateGroup changes fields | Field update |
| | saveGroup and getGroup round-trip membership watermark | Watermark persistence |
| | saveGroup and getGroup round-trip metadata fields | Metadata persistence |
| | saveGroup and getGroup round-trip mute state | Mute persistence |
| | saveGroup and getGroup round-trip dissolved state | Dissolve persistence |
| | saveGroup and getGroup round-trip backlog retention state | Retention persistence |
| | deleteGroup removes the group | Deletion |
| | archiveGroup and unarchiveGroup work | Archive toggle |
| | getActiveGroups excludes archived | Active filter |
| `Members` | saveMember and getMember round-trip | Member persistence |
| | saveMember and getMember preserve permission overrides | Permission override persistence |
| | getMembers returns all members for group | Member list |
| | updateMemberRole changes the role | Role update |
| | removeMember and removeAllMembers work | Member deletion |
| `Keys` | saveKey and getLatestKey round-trip | Key persistence |
| | getKeyByGeneration returns correct key | Key lookup |
| | removeAllKeys clears all keys for group | Key cleanup |

### 1.13 GroupMessageRepositoryImpl
**File:** `test/features/groups/domain/repositories/group_message_repository_impl_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `saveMessage and getMessage` | round-trip preserves all fields | Persistence round-trip |
| | round-trip preserves quotedMessageId | Quoted reply |
| | returns null for non-existent | Missing record |
| `pause recovery` | transitionSendingToFailed transitions outgoing sending rows | Pause recovery |
| `getMessagesPage` | returns messages in chronological order | Sort order |
| | respects limit parameter | Pagination |
| `getLatestMessage` | returns null when no messages | Empty state |
| | returns the most recent message | Latest query |
| | getGroupThreadSummaries returns latest rows and zero defaults | Thread summary |
| | getGroupThreadSummaries preserves latest quotedMessageId | Thread quote |
| `updateMessageStatus` | updates the status field | Status mutation |
| `Section 1 recovery methods` | loads failed outgoing group messages | Failure query |
| | recovers stuck sending messages older than threshold | Stuck recovery |
| `getMessageCount` | returns correct count | Count query |
| `getUnreadCount` | counts only unread incoming messages | Unread filter |
| `getTotalUnreadCount` | counts across all groups | Cross-group count |
| `markAsRead` | marks unread incoming messages as read | Read marking |
| | does not mark outgoing messages | Direction guard |
| `deleteMessage` | removes the message | Message deletion |
| | does not affect other messages | Isolation |
| `existsByContent` | returns true for exact match | Content dedup |
| | returns false when no match exists | Negative case |
| | returns false for different sender | Sender discrimination |
| | returns false for different text | Text discrimination |
| | returns false for different timestamp | Timestamp discrimination |
| | does not match across groups | Group isolation |

### 1.14 PendingGroupInviteRepositoryImpl
**File:** `test/features/groups/domain/repositories/pending_group_invite_repository_impl_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `PendingGroupInviteRepositoryImpl` | savePendingInvite and getPendingInvite round-trip | Persistence round-trip |
| | getPendingInvites orders newest first | Sort order |
| | deleteExpiredPendingInvites removes expired rows only | Expiry cleanup |
| | saveRevokedInvite and getRevokedInvite round-trip | Revocation tombstone persistence |
| | deleteExpiredRevokedInvites removes expired revocations only | Revocation cleanup |
| | saveConsumedInvite and getConsumedInvite round-trip | Consumption tombstone persistence |
| | deleteExpiredConsumedInvites removes expired consumptions only | Consumption cleanup |

---

## 2. Data Layer (DB Helpers)

### 2.1 Groups DB Helpers
**File:** `test/core/database/helpers/groups_db_helpers_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `dbInsertGroup` | inserts a new group | Insert |
| `dbLoadAllGroups` | returns all groups ordered by created_at DESC | List + sort |
| `dbLoadGroup` | returns null for non-existent group | Missing record |
| | returns group when it exists | Lookup |
| `dbUpdateGroup` | updates group fields | Field update |
| `dbDeleteGroup` | deletes a group | Deletion |
| `dbCountGroups` | returns correct count | Count |
| `dbArchiveGroup` | sets is_archived to 1 and sets archived_at | Archive |
| `dbUnarchiveGroup` | sets is_archived to 0 and clears archived_at | Unarchive |
| `dbLoadActiveGroups` | returns only non-archived groups | Active filter |

### 2.2 Group Messages DB Helpers
**File:** `test/core/database/helpers/group_messages_db_helpers_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `dbInsertGroupMessage` | inserts a new message | Insert |
| `dbLoadGroupMessagesPage` | returns empty list for no messages | Empty state |
| | returns messages in chronological (ASC) order | Sort order |
| | respects limit parameter | Pagination |
| `dbLoadAllGroupMessages` | returns only messages for the given group | Group filter |
| `dbLoadLatestGroupMessage` | returns null when no messages | Empty state |
| | returns the most recent message | Latest query |
| `dbLoadGroupMessage` | returns null for non-existent message | Missing record |
| | returns message when it exists | Lookup |
| | round-trips quoted_message_id | Quoted reply |
| `dbUpdateGroupMessageStatus` | updates status field | Status mutation |
| `dbCountGroupMessages` | returns correct count for a group | Count |
| `dbCountUnreadGroupMessages` | counts only unread incoming messages for a group | Unread filter |
| `dbCountTotalUnreadGroupMessages` | counts across all groups | Cross-group count |
| `dbMarkGroupMessagesAsRead` | marks unread incoming messages as read | Read marking |
| `dbDeleteGroupMessage` | deletes a single message | Deletion |

### 2.3 Group Messages DB Helpers (Sending)
**File:** `test/core/database/helpers/group_messages_db_helpers_sending_test.dart`

| Test | What it covers |
|------|----------------|
| dbTransitionGroupSendingToFailed bulk transitions outgoing rows | Bulk transition |

### 2.4 Group Messages DB Helpers (Reliability)
**File:** `test/core/database/helpers/group_messages_db_helpers_reliability_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `migration 041` | adds wire_envelope column | Schema migration |
| | adds inbox_stored column with default 0 | Schema migration |
| | adds inbox_retry_payload column | Schema migration |
| | is idempotent | Migration safety |
| | preserves existing rows | Data preservation |
| `dbLoadStuckSendingGroupMessages` | returns empty list when no messages exist | Empty state |
| | returns only outgoing sending messages older than threshold | Stuck detection |
| | excludes incoming messages | Direction filter |
| | excludes non-sending statuses | Status filter |
| | ordered by timestamp ASC | Sort order |
| | respects limit | Pagination |
| `dbLoadFailedOutgoingGroupMessages` | returns only failed outgoing messages | Failure query |
| | does not return failed incoming messages | Direction filter |
| | ordered by timestamp ASC | Sort order |
| | respects limit | Pagination |
| `dbLoadGroupMessagesWithFailedInboxStore` | returns sent messages with inbox_stored=0 and inbox_retry_payload set | Inbox retry query |
| | excludes messages where inbox_stored=1 | Stored filter |
| | excludes messages with null inbox_retry_payload | Null payload filter |
| | includes pending messages with inbox_stored=0 and retry payload set | Pending inclusion |
| | excludes incoming messages | Direction filter |
| `dbTransitionGroupSendingToFailed` | transitions old sending messages to failed | Transition |
| | does not touch recent sending messages | Threshold guard |
| | does not touch incoming messages | Direction guard |
| | preserves wire_envelope on transitioned rows | Data preservation |
| | returns count of affected rows | Count accuracy |
| `update helpers` | dbUpdateGroupMessageInboxStored sets to 1 | Inbox stored flag |
| | dbUpdateGroupMessageInboxStored sets back to 0 | Flag reset |
| | dbUpdateGroupMessageInboxRetryPayload stores JSON | Retry payload |
| | dbUpdateGroupMessageInboxRetryPayload clears with null | Payload clear |
| | dbUpdateGroupMessageWireEnvelope stores JSON | Wire envelope |
| | dbUpdateGroupMessageWireEnvelope clears with null | Envelope clear |
| | does not affect other rows | Row isolation |
| `GroupMessage model` | fromMap reads wire_envelope | Deserialization |
| | fromMap defaults wire_envelope to null | Default state |
| | fromMap reads inbox_stored as bool | Bool mapping |
| | fromMap reads inbox_retry_payload | Deserialization |
| | toMap serializes inbox_stored as int | Int mapping |
| | copyWith sentinel clears wireEnvelope to null | Sentinel clear |
| | copyWith sentinel clears inboxRetryPayload to null | Sentinel clear |
| | copyWith preserves inboxRetryPayload when not specified | Preserve on copy |
| | copyWith preserves wireEnvelope when not specified | Preserve on copy |

### 2.5 Group Members DB Helpers
**File:** `test/core/database/helpers/group_members_db_helpers_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `dbInsertGroupMember` | inserts a new member | Insert |
| `dbLoadAllGroupMembers` | returns all members for a group ordered by joined_at ASC | List + sort |
| `dbLoadGroupMember` | returns null for non-existent member | Missing record |
| | returns member when it exists | Lookup |
| | preserves permissions_json | Permission override persistence |
| `dbUpdateGroupMemberRole` | updates the role field | Role update |
| `dbDeleteGroupMember` | deletes a single member | Deletion |
| `dbCountGroupMembers` | returns correct count | Count |
| `dbDeleteAllGroupMembers` | deletes all members for a group | Bulk deletion |

### 2.6 Group Keys DB Helpers
**File:** `test/core/database/helpers/group_keys_db_helpers_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `dbInsertGroupKey` | inserts a new key | Insert |
| `dbLoadLatestGroupKey` | returns null when no keys exist | Empty state |
| | returns the highest generation key | Latest query |
| `dbLoadGroupKeyByGeneration` | returns null for non-existent generation | Missing record |
| | returns the key for the given generation | Lookup |
| `dbLoadAllGroupKeys` | returns all keys ordered by generation ASC | List + sort |
| `dbDeleteAllGroupKeys` | deletes all keys for a group | Bulk deletion |

### 2.7 Group Event Log DB Helpers
**File:** `test/core/database/helpers/group_event_log_db_helpers_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `canonicalizeGroupEventLogPayload` | canonical payload ordering is deterministic | Stable canonical JSON for tamper-evident hashing |
| `dbAppendGroupEventLogEntry` | appends entries with per-group hash chain | Sequence, previous hash, and entry hash linkage |
| | exact duplicate source event is idempotent but changed replay is rejected | Replay idempotence and tamper rejection |
| `dbVerifyGroupEventLogChain` | chain verification detects row tampering | Manual DB tamper detection |

---

## 3. Data Layer (DB Migrations)

### 3.1 Migrations 017/018: original group tables
**File:** `test/core/database/migrations/017_018_group_original_tables_test.dart`

| Test | What it covers |
|------|----------------|
| create baseline group tables, columns, defaults, and indexes | Original `groups`, `group_members`, `group_keys`, and `group_messages` table creation plus baseline indexes and defaults |
| stores and reads baseline member, key, and message rows | Pre-026 group/member/key/message insert and query behavior |
| enforces original constraints and remains idempotent | Type/role/unique/primary-key constraints plus rerunnable migrations 017/018 |

### 3.2 Migration 026: group_messages.quoted_message_id
**File:** `test/core/database/migrations/026_group_quoted_message_id_test.dart`

| Test | What it covers |
|------|----------------|
| adds quoted_message_id column to group_messages | Schema addition |
| existing rows get null quoted_message_id on upgrade | Default value |
| can store a quoted parent id after migration | Write after migration |
| is idempotent | Migration safety |

### 3.3 Migration 048: groups.last_membership_event_at
**File:** `test/core/database/migrations/048_groups_last_membership_event_at_test.dart`

| Test | What it covers |
|------|----------------|
| adds last_membership_event_at column to groups | Schema addition |
| existing rows get null last_membership_event_at on upgrade | Default value |
| can store a membership-event watermark after migration | Write after migration |
| is idempotent | Migration safety |

### 3.4 Migration 049: groups metadata columns
**File:** `test/core/database/migrations/049_groups_metadata_columns_test.dart`

| Test | What it covers |
|------|----------------|
| adds avatar and metadata watermark columns to groups | Schema addition |
| existing rows get null metadata columns on upgrade | Default value |
| can store metadata fields after migration | Write after migration |
| is idempotent | Migration safety |

### 3.5 Migration 050: groups.is_muted
**File:** `test/core/database/migrations/050_groups_mute_column_test.dart`

| Test | What it covers |
|------|----------------|
| adds is_muted column to groups | Schema addition |
| existing rows get is_muted = 0 on upgrade | Default value |
| can store muted state after migration | Write after migration |
| is idempotent | Migration safety |

### 3.6 Migration 051: pending_group_invites
**File:** `test/core/database/migrations/051_pending_group_invites_test.dart`

| Test | What it covers |
|------|----------------|
| creates pending_group_invites table | Table creation |
| stores and loads pending invite rows | Read/write |
| is idempotent | Migration safety |

### 3.7 Migration 052: groups dissolve columns
**File:** `test/core/database/migrations/052_groups_dissolve_columns_test.dart`

| Test | What it covers |
|------|----------------|
| adds dissolve columns to groups | Schema addition |
| existing rows get non-dissolved defaults on upgrade | Default value |
| can store dissolved state after migration | Write after migration |
| is idempotent | Migration safety |

### 3.8 Migration 053: groups backlog retention columns
**File:** `test/core/database/migrations/053_groups_backlog_retention_columns_test.dart`

| Test | What it covers |
|------|----------------|
| adds backlog retention columns to groups | Schema addition |
| existing rows get null backlog retention defaults on upgrade | Default value |
| can store backlog retention state after migration | Write after migration |
| is idempotent | Migration safety |

### 3.9 Migration 055: group_invite_revocations
**File:** `test/core/database/migrations/055_group_invite_revocations_test.dart`

| Test | What it covers |
|------|----------------|
| creates revocation table and indexes | Table and index creation |
| can store a revoked invite row after migration | Write after migration |
| is idempotent | Migration safety |

### 3.10 Migration 056: group_invite_consumptions
**File:** `test/core/database/migrations/056_group_invite_consumptions_test.dart`

| Test | What it covers |
|------|----------------|
| creates consumption table and indexes | Table and index creation |
| can store a consumed invite row after migration | Write after migration |
| is idempotent | Migration safety |

### 3.11 Migration 057: group_member_permissions
**File:** `test/core/database/migrations/057_group_member_permissions_test.dart`

| Test | What it covers |
|------|----------------|
| adds permissions_json to group_members idempotently | Permission override schema addition and write/read after migration |

### 3.12 Migration 060: group_event_log
**File:** `test/core/database/migrations/060_group_event_log_test.dart`

| Test | What it covers |
|------|----------------|
| creates group event log table and indexes idempotently | Durable `group_event_log` table, uniqueness constraints, indexes, and insertability |

---

## 4. Application Layer

### 4.1 createGroup
**File:** `test/features/groups/application/create_group_use_case_test.dart`

| Test | What it covers |
|------|----------------|
| creates group successfully | Happy path |
| throws on empty name | Validation |
| throws on bridge error | Error handling |
| saves group, member, and key to repo | Persistence |
| persists creator identity and initial bridge epoch on create | Creator identity and initial key epoch persistence |
| persists the creator username on the admin membership row | Creator identity persistence |
| fails honestly and rolls back when no usable group key is available | Keyless-create rollback |
| creates announcement group with announcement bridge payload and admin metadata | Announcement type |

### 4.2 createGroupWithMembers
**File:** `test/features/groups/application/create_group_with_members_use_case_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `createGroupWithMembers` | creates group and returns GroupModel | Happy path |
| | adds all contacts as writer members | Member creation |
| | persists the creator username and exports it in group config | Creator identity propagation |
| | excludes failed add-member recipients from persisted members, config, publish payload, and invite fan-out | Partial member-add subset truth |
| | calls callGroupUpdateConfig once with full member list including self | Bridge config sync |
| | broadcasts members_added system message via callGroupPublish | System message |
| | sends individual encrypted P2P invites to each contact | Invite delivery |
| | rolls back staged members when `group:updateConfig` fails after local adds | Config rollback and no invite fan-out |
| | reports mixed or failed invite delivery as an explicit warning result | Invite-degradation truth |
| | reports missing latest key as explicit invite-delivery degradation | Missing-key truth |
| | reports `members_added` publish failure without pretending full invite success | Publish-warning truth |
| | uses auto-generated name from usernames when name is null | Auto-naming |
| | uses auto-generated name with +N suffix for 3+ contacts | Auto-naming overflow |
| | uses provided name when name is not null | Explicit naming |
| | rejects over-limit selection before creating a group | Membership limit |
| | succeeds locally even when P2P invite fails | Partial failure |
| | propagates announcement type into created group, saved group, and updateConfig | Announcement type |

### 4.3 sendGroupMessage
**File:** `test/features/groups/application/send_group_message_use_case_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| (top) | sends message successfully | Happy path |
| | emits GROUP_SEND_MSG_TIMING with group and media metadata | Flow event contract |
| | returns groupNotFound for unknown group | Guard |
| | returns groupDissolved for a dissolved group | Dissolve guard |
| | returns unauthorized for non-admin in announcement group | Announcement guard |
| | rejects stale send after local membership removal before persistence | Removed-sender stale send guard |
| | rejects message when group recovery is in progress | Recovery guard |
| | rejects unauthorized on announcement when recovery pending | Combined guard |
| | allows discussion send while group recovery is in progress | Discussion recovery contract |
| | saves message to repo on success | Persistence |
| | calls group:publish with encrypted wire envelope | Bridge call |
| | builds and encrypts complete wire envelope with timestamps | Envelope construction |
| | stores message in relay inbox on publish | Inbox store |
| | handles messages sent in rapid succession | Rapid-fire |
| | text group message builds preview body like Sender: hello | Push preview |
| | sends quotation as JSON __quote field in plaintext payload | Quoted reply |
| | sends media in plaintext media array within encrypted envelope | Media payload |
| | send succeeds even if inbox store throws | Inbox error isolation |
| | returns error when publish returns ok: false | Publish failure |
| | returns error when publish throws exception | Publish exception |
| | persists explicit inbox success when publish fails | Inbox-only success |
| | publish and inbox store run concurrently | Concurrency |
| | concurrent sending still emits timing event once | Event dedup |
| | inbox store runs even when publish fails | Inbox independence |
| `media attachments` | includes media in publish payload | Media publish |
| | includes media in inbox payload | Media inbox |
| | saves attachments to MediaAttachmentRepository | Media persistence |
| | includes GIF metadata in publish and inbox payloads | GIF metadata |
| | sanitizes text before message ID calculation | Text sanitization |
| | uses provided messageId when given | Explicit ID |
| | uses provided timestamp when given | Explicit timestamp |
| | generates messageId when not provided | Auto ID |
| | message id collision from generator uses a fresh id without overwriting trusted row | Generated collision resolution |
| | message id collision from explicit id resolves without overwriting trusted row | Explicit collision resolution |
| | message id collision guard still allows failed retry in place | Retry reuse |
| | sends message with empty text and media (voice note) | Voice note |
| | rejects message with empty text and no media | Empty guard |
| | rejects message with whitespace-only text and no media | Whitespace guard |
| | sanitizes dangerous bidi controls from text before save | Bidi sanitization |
| | handles message with multiple media attachments | Multi-media |
| | handles message without media (backward compat) | Backward compat |
| | text-only message without media -- no media in payload | No-media path |
| `MS-018: key rotation epoch binding` | send snapshots current epoch for row and replay envelope before publish completes | Send-time epoch snapshot |
| | messages before during and after rotation bind to the locally committed epoch | Before/during/after rotation commit |
| `WU-3: pre-persist and send contract` | pre-persist: message saved with sending status + wireEnvelope + inboxRetryPayload BEFORE bridge call | Crash-window durability |
| | pre-persist: unauthorized caller does NOT persist a row | Auth guard |
| | pre-persist: group-not-found does NOT persist a row | Not-found guard |
| `WU-3: 0-peer publish detection and 4-way matrix` | 0-peer + inbox OK -> successNoPeers, status sent | No-peer + inbox OK |
| | 0-peer + inbox fail -> error | No-peer + inbox fail + flow event contract |
| | peers > 0 + inbox OK -> success, both payloads cleared | Peers + inbox OK |
| | peers > 0 + inbox fail -> publishOnly, status publish_ok | Peers + inbox fail |
| | topicPeers null + inbox OK -> legacy success stays sent | Legacy + inbox OK |
| | topicPeers null + inbox fail -> legacy error | Legacy + inbox fail |
| | missing topicPeers + inbox OK -> legacy success stays sent | Missing peers + inbox OK |
| | missing topicPeers + inbox fail -> error | Missing peers + inbox fail |
| | inbox store ok:false is treated as inbox failure | Inbox ok:false |
| | missing topicPeers (old bridge) + success -> legacy behavior | Legacy bridge compat |

### 4.4 sendGroupInvite
**File:** `test/features/groups/application/send_group_invite_use_case_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `sendGroupInvite` | encrypts invite payload with recipient binding and sends to recipient via p2pService | Happy path |
| | returns encryptionRequired when recipientMlKemPublicKey is null | Key guard |
| | returns nodeNotRunning when p2pService is not started | Node guard |
| | returns sendFailed when bridge encrypt returns ok=false | Encrypt failure |
| | returns sendFailed when p2pService returns false and inbox fails | Send + inbox failure |
| | stores invite in inbox when direct send fails | Inbox fallback |
| | invite payload includes full groupConfig with members array | Payload shape |
| | keeps join material and policy details inside encrypted invite payload | Direct + inbox invite privacy |
| `sendGroupInvitesInParallel` | sends invites to all recipients and returns per-recipient outcomes | Batch send |
| | runs invites concurrently | Concurrency |
| | counts only successful invites when some fail | Partial failure |
| | returns 0 for empty recipients list | Empty input |
| | continues sending when one invite throws | Error isolation |

### 4.5 handleIncomingGroupMessage
**File:** `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| (top) | handles incoming message successfully | Happy path |
| | records incoming message in tamper-evident event log | DB-002 event-log append coverage |
| | event log rejects tampered duplicate before stored message changes | DB-002 event-log replay/tamper guard |
| | persists same-self delivery as local sent history | Multi-device |
| | strips dangerous bidi controls and preserves safe markers on incoming save | Bidi sanitization |
| | ignores message for unknown group | Unknown group guard |
| | saves message to repo | Persistence |
| | duplicate by messageId skips repeated group and member lookups | Dedup optimization |
| | persists quotedMessageId from incoming payload | Quoted reply |
| | still processes messages from unknown members | Unknown member tolerance |
| | accepts removed-sender message when it predates the persisted removal cutoff | Pre-cutoff tolerance |
| | rejects removed-sender message when it is at the persisted removal cutoff | At-cutoff rejection |
| | still processes unknown sender when persisted removal cutoff belongs to another peer | Peer-scoped cutoff |
| | accepts a message that predates the persisted dissolve cutoff | Pre-dissolve tolerance |
| | rejects a message at or after the persisted dissolve cutoff | Post-dissolve rejection |
| | deduplicates identical incoming messages | Content dedup |
| | deduplicates messages after sanitizing invisible bidi controls | Sanitized dedup |
| | allows messages with different text or timestamp | False-positive guard |
| | far future incoming timestamp is clamped to receive time | Future-skew clamp |
| | past current and near future timestamps retain chronological order | Clock-skew ordering |
| | deduplicates by messageId when pubsub and group inbox deliver same message | Cross-path dedup |
| | duplicate replay enriches a missing quotedMessageId | Quote enrichment |
| | duplicate replay with the same messageId ignores a tampered timestamp | Replay tamper dedup |
| | duplicate replay with the same messageId ignores conflicting content | Replay content tamper dedup |
| | duplicate group inbox replay does not resave media | Media dedup |
| | replayed removed-sender message after cutoff does not overwrite the accepted pre-cutoff row | Replay + removal cutoff |
| | replayed message after dissolve cutoff does not overwrite the accepted pre-dissolve row | Replay + dissolve cutoff |
| `media attachments` | saves media attachments when media list provided | Media persistence |
| | creates MediaAttachment with downloadStatus pending | Download status |
| | handles message without media (backward compat) | Backward compat |
| | ignores duplicate messages -- does not re-save media | Dedup + media |

### 4.6 addGroupMember
**File:** `test/features/groups/application/add_group_member_use_case_test.dart`

| Test | What it covers |
|------|----------------|
| adds member successfully when caller is admin | Happy path |
| allows adding the 50th member under the shared contract | Limit boundary |
| rejects when caller is not admin | Auth guard and no local/bridge side effects |
| allows writer with invite permission override to add a member | Permission override grant |
| denies admin whose invite permission override is false | Permission override deny |
| rechecks revoked invite permission before adding a queued member | Stale permission recheck |
| rejects while group recovery is in progress | Recovery guard |
| throws when group not found | Not-found guard |
| rejects duplicate member before sync and preserves original row | Duplicate guard |
| rejects adding a 51st member before config sync | Over-limit guard |
| saves member to repo | Persistence |
| rolls back DB when group:updateConfig fails | Rollback |
| syncBridgeConfig false skips bridge config sync | Skip-sync path |

### 4.7 removeGroupMember
**File:** `test/features/groups/application/remove_group_member_use_case_test.dart`

| Test | What it covers |
|------|----------------|
| removes member from DB | Deletion |
| calls group:updateConfig to update Go validator | Bridge sync |
| does NOT call group:rotateKey | No legacy rotate |
| throws when caller is not admin | Auth guard |
| allows writer with remove permission override to remove member | Permission override grant |
| denies admin whose remove permission override is false | Permission override deny |
| rechecks revoked remove permission before removing a queued target | Stale permission recheck |
| blocks removing the last admin before local or bridge changes | Last-admin guard |
| allows removing an admin when another admin remains | Multi-admin removal |
| rejects while group recovery is in progress | Recovery guard |
| rejects non-member before sync and preserves existing members | Non-member guard |
| removes member from DB before calling bridge | Order of operations |
| groupConfig sent to bridge excludes removed member | Config correctness |
| groupConfig has correct structure with all required fields | Config shape |
| restores removed member when group:updateConfig fails | Rollback |

### 4.8 updateGroupMemberRole
**File:** `test/features/groups/application/update_group_member_role_use_case_test.dart`

| Test | What it covers |
|------|----------------|
| promotes member to admin and syncs bridge config | Happy path |
| rejects non-admin caller | Auth guard |
| allows writer with manage-roles permission override to update role | Permission override grant |
| writer with manage-roles permission cannot promote a member to admin | Permission escalation guard |
| denies admin whose manage-roles permission override is false | Permission override deny |
| rechecks revoked manage-roles permission before applying queued role update | Stale permission recheck |
| rejects non-member target before sync | Non-member guard |
| blocks removing the last admin from the group | Last-admin guard |
| allows self demotion when another admin remains and updates myRole | Self-demotion |
| rejects while group recovery is in progress | Recovery guard |

### 4.9 archiveGroup / unarchiveGroup
**File:** `test/features/groups/application/archive_group_use_case_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `archiveGroup` | calls groupRepo.archiveGroup(groupId) successfully | Happy path |
| | propagates errors from repository | Error propagation |

**File:** `test/features/groups/application/unarchive_group_use_case_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `unarchiveGroup` | calls groupRepo.unarchiveGroup(groupId) successfully | Happy path |
| | propagates errors from repository | Error propagation |

### 4.10 joinGroup
**File:** `test/features/groups/application/join_group_use_case_test.dart`

| Test | What it covers |
|------|----------------|
| joins group successfully | Happy path |
| saves group, member, and key | Persistence |
| calls bridge join command | Bridge call |

### 4.11 leaveGroup
**File:** `test/features/groups/application/leave_group_use_case_test.dart`

| Test | What it covers |
|------|----------------|
| leaves group successfully | Happy path |
| cleans up all data (members, keys, group) | Cleanup |
| calls bridge leave command | Bridge call |
| blocks sole admin from leaving | Sole-admin guard |
| allows admin to leave when another admin exists | Multi-admin leave |

### 4.12 deleteGroupAndMessages
**File:** `test/features/groups/application/delete_group_and_messages_use_case_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `deleteGroupAndMessages` | deletes group messages first, then calls leaveGroup | Order of operations |
| | dissolved local cleanup deletes group state without publishing group leave | Device-local dissolved cleanup |
| | propagates errors from message deletion | Error propagation |

### 4.13 dissolveGroup
**File:** `test/features/groups/application/dissolve_group_use_case_test.dart`

| Test | What it covers |
|------|----------------|
| dissolves a group, stores a timeline event, and leaves the topic | Happy path + durable closure fields |
| returns unauthorized for non-admin users | Auth guard |
| returns alreadyDissolved when the group is already closed | Idempotency guard preserving closure fields |
| repeated dissolve preserves closure state and does not publish again | Repeated dissolve idempotency + duplicate publish guard |
| returns bridgeError when inbox fallback fails but still marks the group dissolved | Partial failure |

### 4.14 updateGroupMetadata
**File:** `test/features/groups/application/update_group_metadata_use_case_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `updateGroupMetadata` | updates name, description, avatar metadata, and watermark | Happy path |
| | builds stable version and canonical state hash for settings | Settings version + canonical hash |
| | clears blank description and avatar fields explicitly | Blank field clearing |
| | rejects non-admin edits | Auth guard |
| | rechecks demoted local role before applying queued metadata edit | Stale role recheck |
| | rejects empty names | Validation |

### 4.15 setGroupMuted
**File:** `test/features/groups/application/set_group_muted_use_case_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `setGroupMuted` | updates mute state for an existing group | Happy path |
| | throws when the group does not exist | Not-found guard |

### 4.16 rotateGroupKey
**File:** `test/features/groups/application/rotate_group_key_use_case_test.dart`

| Test | What it covers |
|------|----------------|
| rotates key successfully | Happy path |
| saves new key to repo | Persistence |
| returns GroupKeyInfo with correct data | Return value |

### 4.17 rotateAndDistributeGroupKey
**File:** `test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart`

| Test | What it covers |
|------|----------------|
| allows writer with rotate permission override to rotate keys | Permission override grant |
| denies admin whose rotate permission override is false | Permission override deny |
| rechecks revoked rotate permission before generating a queued key | Stale permission recheck |
| promotes generated key only after distribution completes | Ordering |
| distribution completes before admin update and broadcast | Ordering |
| calls bridge to encrypt key for each non-self member | Per-member encrypt |
| broadcasts key_rotated system message | System message |
| sends key update to each non-self member via p2p | Key distribution |
| returns null when generate-next-key fails (ok: false) | Keygen failure |
| skips members without mlKemPublicKey | Missing key skip |
| continues distribution when per-member encrypt fails | Error isolation |
| continues distribution when sendP2PMessage throws | Error isolation |
| distribution timeout does not block later recipients | Timeout isolation |
| updates admin key after distribution timeout | Timeout recovery |

### 4.18 handleIncomingGroupInvite
**File:** `test/features/groups/application/handle_incoming_group_invite_use_case_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `handleIncomingGroupInvite` | persists group, members, and key for a valid invite payload | Happy path |
| | persists avatar metadata and downloaded path when invite carries it | Avatar persistence |
| | calls group:join bridge command with groupId, groupConfig, groupKey, keyEpoch | Bridge call |
| | returns duplicateGroup when group already exists | Duplicate guard |
| | returns invalidPayload for missing groupId | Missing field guard |
| | returns invalidPayload for missing groupKey | Missing field guard |
| | returns invalidPayload for empty groupKey before state or join | Missing join material guard |
| | returns invalidPayload for missing groupConfig | Missing field guard |
| | returns unknownSender for invite from non-contact | Unknown sender guard |
| | joining user gets myRole=member in the persisted GroupModel | Role assignment |
| | returns bridgeError when group:join times out | Timeout handling |
| | decrypts v2 invite envelope and processes inner payload | v2 decryption |
| | returns decryptionFailed when bridge decrypt returns ok=false | Decrypt failure |
| | returns decryptionFailed when mlKemSecretKey is null and envelope is v2 | Missing key guard |
| | persists correct myRole as member (not admin) | Role validation |
| | persists all members from groupConfig, not just sender | Multi-member persistence |
| | rejects v1 invite where transport sender != payload sender | Sender mismatch guard |
| | rejects v2 encrypted invite where transport sender != payload sender | v2 sender mismatch guard |
| | accepts bound invite when recipient peer matches local identity | Recipient binding happy path |
| | rejects v1 invite bound to a different recipient peer | Wrong recipient guard |
| | rejects v2 encrypted invite bound to a different recipient peer | v2 wrong recipient guard |
| | handles bridge group:join timeout without losing persisted data | Timeout data safety |

### 4.19 storePendingGroupInvite
**File:** `test/features/groups/application/store_pending_group_invite_use_case_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `storeIncomingPendingGroupInvite` | stores validated invite as pending without creating group state | Happy path |
| | ignores delayed invite copy when invite was revoked | Revocation replay guard |
| | ignores delayed invite copy when invite was already used | Consumption replay guard |
| | returns duplicateGroup when group already exists | Duplicate guard |
| | returns unknownSender when contact is missing | Unknown sender guard |

### 4.20 acceptPendingGroupInvite
**File:** `test/features/groups/application/accept_pending_group_invite_use_case_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `acceptPendingGroupInvite` | accepts pending invite, persists group, and drains inbox | Happy path |
| | accept replays backlog reactions when reactionRepo is provided | Invite-accept immediate reaction catch-up |
| | successful accept publishes a durable join event for the group | Durable join history |
| | bridgeError keeps the persisted group and clears the pending invite row | Accepted-but-degraded persistence |
| | missing join material stays pending for repair without creating group state | Missing join material repair state |
| | returns expired and removes stale invite | Expiry guard |
| | returns revoked and removes stale pending row without joining | Revoked-accept guard |
| | returns alreadyUsed and removes stale pending row without joining | Consumption replay guard |
| | returns duplicateGroup and removes pending row when group already exists | Duplicate guard |
| | accepting on one device does not clear the sibling device pending invite | Multi-device |

### 4.20a revokePendingGroupInvite
**File:** `test/features/groups/application/revoke_pending_group_invite_use_case_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `revokePendingGroupInvite` | removes pending row and records a revocation tombstone | Revocation happy path |
| | returns notFound without writing a tombstone | Missing invite guard |

### 4.21 declinePendingGroupInvite
**File:** `test/features/groups/application/decline_pending_group_invite_use_case_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `declinePendingGroupInvite` | deletes pending invite on decline | Happy path |
| | returns expired when declining an expired invite | Expiry guard |
| | declining on one device does not clear the sibling device pending invite | Multi-device |

### 4.22 drainGroupOfflineInbox
**File:** `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| (top) | resume drains group inbox for every joined group | Happy path |
| | drain after watchdog restart retrieves messages exactly once | Idempotency |
| | drain after in-place recovery still allowed and idempotent | Recovery compat |
| | drains groups concurrently so one slow inbox does not serially stall others | Concurrency |
| | replayed member_removed routes through listener cleanup instead of saving a chat row | System message routing |
| | replayed reaction routes through reactionRepo when present | Reaction routing |
| | handles bad inbox data gracefully | Error handling |
| | skips backward compat v1 member_added messages without peerId | Legacy compat |
| | repeated drains do not resurrect expired backlog | Retention enforcement |
| | backlog expires after stale window | Stale backlog |
| | drain preserves quotedMessageId from inbox payload | Quoted reply |
| | filters out messages with null group | Null group guard |
| | deduplicates messages by messageId | Dedup |
| | saves correct status based on direction | Status mapping |
| | persists wire envelope and inbox retry payload | Payload persistence |
| | emits GROUP_DRAIN_OFFLINE_INBOX_TIMING with batch metadata | Batch flow event contract |
| | drains offline inbox and saves messages to repo | Persistence |
| | handles multiple pages with cursor pagination | Pagination |
| | does not crash on empty inbox | Empty state |
| | handles cursor null on empty inbox | Null cursor |
| | drains inbox for archived groups too | Archived inclusion |
| | drains inbox message with media -- saves media attachments | Media drain |
| | GMAR-004 duplicate live plus inbox replay enriches video and voice media once | Signed replay duplicate/enrichment proof: sparse live media is enriched once with video/voice metadata and one attachment set |
| | drains mixed epoch encrypted replay out of order without rewriting epochs | MS-018 mixed-epoch replay |
| | future epoch encrypted replay creates one undecryptable placeholder without decrypting | MS-018/OS-009 future-epoch placeholder |
| | MD-011 removed member cannot decode future media replay with only the old epoch | Removed peer with only epoch 1 skips epoch-2 future media before message, media, download, or decrypt persistence |
| | drains group_reaction items when reactionRepo is provided | Reaction drain |
| `drainGroupOfflineInbox use case` | resume drains all groups concurrently | Batch drain |
| | watchdog restart drains missed group messages exactly once | Watchdog idempotency |
| | in-place recovery allows resync while draining | Recovery sync |

### 4.23 recoverStuckSendingGroupMessages
**File:** `test/features/groups/application/recover_stuck_sending_group_messages_use_case_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `recoverStuckSendingGroupMessages` | returns count from repo and transitions stuck rows to failed | Happy path |
| | returns 0 when nothing is stuck | Empty state |
| | respects the supplied threshold | Threshold param |

### 4.24 retryFailedGroupInboxStores
**File:** `test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart`

| Test | What it covers |
|------|----------------|
| retries eligible sent messages and clears inbox retry state | Happy path + begin/ok/done/timing flow events |
| retries eligible pending messages and promotes them to sent | Pending promotion |
| skips messages that are already inbox_stored | Skip guard |
| handles callGroupInboxStore failure gracefully | Error handling + per-message flow event |
| respects batch limit | Batch size |
| returns 0 when no eligible messages | Empty state |
| skips legacy rows with null inbox_retry_payload | Legacy compat |

### 4.25 retryFailedGroupMessages
**File:** `test/features/groups/application/retry_failed_group_messages_use_case_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `retryFailedGroupMessages` | returns 0 when identity is null | Null identity guard |
| | emits RETRY_FAILED_GROUP_MESSAGES_TIMING with total and skipped counts | Start/found/success/complete/timing flow events |
| | retries a text-only failed row in place using the original ids | Text retry |
| | retries a zero-peer plus inbox-fail row through the failed-message retry owner | Zero-peer retry owner |
| | retries a failed text row even when inboxRetryPayload was cleared after inbox success | Cleared payload retry |
| | retries a failed media row from persisted done attachments when inboxRetryPayload was cleared after inbox success | Media retry |
| | retries a failed GIF row from persisted done attachments with image/gif preserved | GIF retry |
| | skips rows whose persisted media attachments are still upload_pending | Upload-pending skip + skipped-reason flow event |
| | skips media retry rows when no resendable persisted attachments exist | No-attachment skip |
| | continues after a per-message publish error | Error isolation |
| | does not replay a failed text row after sender was removed locally | Removed-sender retry guard |
| | retryFailedGroupMessage only retries the requested failed media row | Targeted retry |

### 4.26 retryIncompleteGroupUploads
**File:** `test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `retryIncompleteGroupUploads` | returns 0 when no upload_pending attachments exist | Empty state |
| | reuploads only group upload_pending attachments and uses blobId | Upload retry + recipient-only upload ACL |
| | reuploads only pending GIF attachments while preserving done JPEG siblings | GIF retry |
| | emits RETRY_INCOMPLETE_GROUP_UPLOADS_TIMING with attachment and message counts | Flow event |
| | transient failure increments retry count and terminal state at max | Retry exhaustion |
| | skips retry work when upload_pending attachments have no parent group message row | Orphan skip |
| | skips the final group send when the parent row is deleted after uploads complete | Deleted parent skip |
| | MD-011 retry excludes a removed member from media ACLs and inbox recipients | Post-removal retry upload `allowedPeers` and group inbox recipients exclude removed C |

### 4.27 GroupMessageListener
**File:** `test/features/groups/application/group_message_listener_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| (top) | processes valid message | Happy path |
| | forwards quotedMessageId from event into persisted message | Quoted reply forwarding |
| | caches self peer id across multiple handled messages | Self-ID cache |
| | ignores message for unknown group | Unknown group guard |
| | emits to stream on valid message | Stream emission |
| | disposes correctly | Cleanup |
| | handles malformed data without crashing | Error resilience |
| `system messages` | member_added saves member and calls updateConfig | Member-add system msg |
| | member_added emits readable timeline event on groupMessageStream | Durable add timeline |
| | unauthorized member_added is ignored | Auth guard |
| | group_metadata_updated refreshes group metadata and stores a timeline event | Metadata update |
| | tampered group_metadata_updated state hash is ignored without mutating group state | Metadata hash tamper guard |
| | unauthorized group_metadata_updated is ignored | Auth guard |
| | members_added saves all members and calls updateConfig | Batch member-add |
| | member_joined saves a durable join timeline event | Durable join timeline |
| | unauthorized members_added is ignored | Auth guard |
| `member_removed system messages` | unauthorized member_removed is ignored | Auth guard |
| | replayed unauthorized member_removed is ignored | Replay auth guard |
| | handles key_rotated system message without error | Key rotation |
| | removal of other member does NOT call leaveGroup | Non-self removal |
| | member_role_updated changes role and calls updateConfig | Role update |
| | member_role_updated logs event and rejects tampered replay before mutation | DB-002 system event-log replay/tamper guard |
| | unauthorized member_role_updated is ignored | Auth guard |
| | limited manager member_role_updated cannot promote a member to admin | Permission escalation guard |
| | limited manager member_role_updated cannot grant unheld permissions | Permission escalation guard |
| `media forwarding` | handles event without media field (backward compat) | Backward compat |
| `group notifications` | shows notification for incoming group message | Notification display |
| | suppresses notification when viewing group conversation | Active view suppression |
| | does not notify for own messages | Self-message suppression |
| | does not notify after self-removal deletes the group | Post-removal suppression |
| | does not notify when notification deps are null | Null deps guard |
| | shows notification when viewing different group | Cross-group notification |
| `group reactions` | emits removal ReactionChange when action is remove | Reaction removal |
| | ignores reaction when reactionRepo is null | Null repo guard |
| | ignores malformed reaction data | Malformed data guard |
| `group_dissolved system messages` | replayed group_dissolved is idempotent | Dissolve replay |
| | unauthorized group_dissolved is ignored | Auth guard |
| `system messages` | unauthorized mutation system events leave local state and bridge unchanged | Receive-side authorization matrix |

### 4.28 GroupInviteListener
**File:** `test/features/groups/application/group_invite_listener_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `GroupInviteListener` | stores a valid v2 invite as pending and does not join immediately | Happy path |
| | does not store pending invite from unknown sender | Unknown sender guard |
| | does not store pending invite for an already joined group | Duplicate guard |
| | does not crash on decryption failure | Decryption error |
| | calling start twice does not create duplicate subscriptions | Double-start guard |
| | stop prevents further processing | Stop lifecycle |
| | dispose is safe after start | Dispose lifecycle |
| | does not process invite from blocked contact | Block guard |
| | duplicate pending invite replaces the existing preview row | Upsert |

### 4.29 GroupKeyUpdateListener
**File:** `test/features/groups/application/group_key_update_listener_test.dart`

| Test | What it covers |
|------|----------------|
| logs key update and rejects tampered replay before replacing key | DB-002 key-update event-log replay/tamper guard |
| saves key on successful decrypt | Happy path |
| promotes key only after group:updateKey succeeds | Ordering |
| returns early when encrypted field is null | Null guard |
| returns early when own ML-KEM secret key is null | Missing key guard |
| returns early when decrypt fails (ok: false) | Decrypt failure |
| saves key to DB AND updates Go via group:updateKey | Dual persistence |
| does not crash on malformed JSON | Error resilience |
| group:updateKey payload contains correct groupId, groupKey, keyEpoch | Payload shape |
| send during pending key update uses old epoch until local update commits | MS-018 pending update send |
| handles sequential key updates (epoch 2 then epoch 3) | Higher-epoch convergence |
| conflicting same-generation key updates converge to one final stored key | Same-epoch convergence |
| group:updateKey bridge failure keeps the old key active | Bridge failure guard |

### 4.30 Reactions (send / handle / remove)
**File:** `test/features/groups/application/send_group_reaction_use_case_test.dart`

| Test | What it covers |
|------|----------------|
| chat member can react | Happy path |
| announcement member can react | Announcement react |
| dissolved chat group rejects reactions without publishing or storing | Dissolved send guard |
| dissolved announcement member cannot add a reaction | Dissolved announcement guard |
| non-member is rejected | Auth guard |
| unknown messageId is rejected | Missing message guard |
| unknown group is rejected | Missing group guard |
| publish failure returns publishFailed | Publish failure |

**File:** `test/features/groups/application/handle_incoming_group_reaction_use_case_test.dart`

| Test | What it covers |
|------|----------------|
| upserts reaction | Happy path |
| replaces prior emoji from same sender | Upsert replace |
| removes reaction on remove action | Remove action |
| returns unknownGroup for nonexistent group | Missing group guard |
| returns parseError for invalid JSON | Parse error |
| still processes reaction from unknown sender (stale member list) | Stale member tolerance |
| rejects add when payload sender mismatches outer sender | Sender auth guard |
| rejects remove when payload sender mismatches outer sender | Sender auth guard |
| ignores add reactions at or after the dissolve cutoff | Dissolve cutoff guard |
| ignores remove reactions at or after the dissolve cutoff | Dissolve cutoff guard |
| accepts late replayed reactions when the payload predates dissolve | Pre-dissolve replay tolerance |

**File:** `test/features/groups/application/remove_group_reaction_use_case_test.dart`

| Test | What it covers |
|------|----------------|
| removes own reaction | Happy path |
| is idempotent when reaction absent | Idempotency |
| non-member is rejected | Auth guard |
| dissolved group rejects remove and preserves the stored reaction | Dissolved remove guard |

### 4.31 rejoinGroupTopics
**File:** `test/features/groups/application/rejoin_group_topics_use_case_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `rejoinGroupTopics` | calls callGroupJoinWithConfig for each active group | Happy path |
| | emits GROUP_REJOIN_TOPICS_TIMING with batch metadata | Begin/joined/done/timing flow events |
| | skips groups with no key info | Missing key skip |
| | continues on individual join error | Error isolation |
| | does nothing when no active groups exist | Empty state |
| | builds correct groupConfig from stored members | Config construction |
| | rejoin is idempotent when topic already active | Idempotency |
| | rejoin runs after watchdog restart | Watchdog trigger |
| | node-requested recovery rejoins topics | Recovery trigger |
| | in-place recovery refreshes topics idempotently | In-place recovery |
| | announcement groups are rejoined and refreshed like normal groups | Announcement rejoin |
| | watchdog restart triggers group rejoin for all groups | Watchdog batch |
| | in place relay recovery still refreshes group topics | Relay recovery |
| | startup triggers group rejoin for all groups | Startup trigger |
| | groups without key material are skipped | Key guard |
| | error in one group does not prevent other groups from being rejoined | Error isolation + per-group error flow events |
| | rejoins archived groups | Archived inclusion |
| | skips dissolved groups | Dissolved exclusion + rejoin result counts |

### 4.32 groupAvatarStorage
**File:** `test/features/groups/application/group_avatar_storage_test.dart`

| Test | What it covers |
|------|----------------|
| downloadGroupAvatar creates the group avatar directory before bridge download | Directory creation |

### 4.33 Member Removal Integration
**File:** `test/features/groups/application/member_removal_integration_test.dart`

| Test | What it covers |
|------|----------------|
| complete admin removal flow produces correct bridge command sequence | Command order |
| rotated key is NOT distributed to removed member | Removed member future-key exclusion |
| receiver processes key update and syncs Go validator | Key update receipt |
| first post-removal send uses the rotated epoch | Epoch advancement |
| voluntary leave rotation excludes leaver and remaining members send on rotated epoch | Voluntary leave rotation baseline |

---

## 5. Presentation Layer

### 5.1 GroupListScreen
**File:** `test/features/groups/presentation/group_list_screen_test.dart`

| Test | What it covers |
|------|----------------|
| renders groups | Rendering |
| shows empty state when no groups | Empty state |
| shows loading placeholders while groups are loading | Loading state |
| shows group list when groups are available even if isLoading is still true | Loading + data |
| shows type badges | Badge rendering |
| renders pending invite review card and actions | Invite card |
| renders expired pending invite as non-joinable | Expired invite |
| does not show FAB (FAB moved to Orbit screen) | FAB removal |
| shows expired backlog summary on the group card | Backlog summary |
| shows mixed-window backlog summary alongside latest message | Retention summary |

### 5.2 GroupListScreen BiDi
**File:** `test/features/groups/presentation/group_list_screen_bidi_test.dart`

| Test | What it covers |
|------|----------------|
| does not flatten sender and body into a single preview string | BiDi preview |

### 5.3 GroupListWired
**File:** `test/features/groups/presentation/group_list_wired_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `GroupListWired` | loads and displays active groups on init | Init loading |
| | reloads renamed group metadata after a message refresh | Metadata reload |
| | shows loading placeholders before groups resolve | Loading state |
| | refreshes group list when groupMessageListener emits | Message stream |
| | refreshes group list when groupInviteListener emits | Invite stream |
| | loads pending invites on init | Invite loading |
| | refreshes pending invite list when pending invite stream emits | Invite stream |
| | accepting a pending invite joins the group and removes the row | Accept flow + immediate replay catch-up |
| | bridgeError accept keeps the joined group and shows recovery warning | Honest degraded state |
| | repair-pending accept keeps the invite row and shows key-material warning | Pending repair state |
| | declining a pending invite removes the row without joining | Decline flow |
| | tapping group navigates to conversation | Navigation |
| | shows unread counts | Unread badge |
| | loading skeleton replaced by empty state when no groups | Empty transition |
| | loading clears on error | Error recovery |

### 5.4 GroupCard
**File:** `test/features/groups/presentation/group_card_test.dart`

| Test | What it covers |
|------|----------------|
| renders group name and type badge | Rendering |
| shows unread count when > 0 | Unread badge |

### 5.5 GroupCard BiDi
**File:** `test/features/groups/presentation/group_card_bidi_test.dart`

| Test | What it covers |
|------|----------------|
| announcement preview separates sender label from Arabic-first mixed body | BiDi preview |
| group preview keeps English-first body LTR even with mixed sender name | LTR text |
| dissolved groups show a badge and fallback preview | Dissolved state |

### 5.6 GroupTypeBadge
**File:** `test/features/groups/presentation/group_type_badge_test.dart`

| Test | What it covers |
|------|----------------|
| renders correct text for each type | Badge text |
| each type has unique color | Badge color |

### 5.7 GroupConversationScreen
**File:** `test/features/groups/presentation/group_conversation_screen_test.dart`

| Test | What it covers |
|------|----------------|
| renders messages | Message rendering |
| renders sender identity with UserAvatar in conversation rows | Avatar consistency |
| keeps non-photo fallback identity readable in conversation rows | Readable avatar fallback |
| shows compose area when canWrite is true | Compose visibility |
| long-press opens one coherent context surface with selected preview and supported actions | Context overlay parity |
| long-press reply uses the existing quote-reply path | Long-press reply |
| long-press copy action copies exact text and dismisses once | Clipboard copy |
| local-only long-press actions remain available when reactions are unavailable | No-reaction local actions |
| long-press reaction selection preserves the reaction path | Reaction parity |
| passes isSending through to the compose send affordance | Send state |
| group rows keep a single glass shell across text, quote, reaction, and media variants | Single-shell row rendering |
| row shell stays single after reaction and media enrichment updates | Shell stability after enrichment |
| renders active quote preview and dismisses it | Quote preview |
| upload banner shows cancel affordance only when supplied | Cancel affordance |
| shows loading shell while initial group page is still loading | Loading state |
| shows empty state once group load completes with no messages | Empty state |
| hides compose area for readers in announcement group | Read-only mode |
| shows dissolved read-only copy and badge for ended groups | Dissolved state |
| shows expired backlog banner and empty-state override after retention expiry | Retention banner |
| shows mixed-window retention banner while retained messages stay visible | Retention + messages |
| composer listenable updates do not rebuild header or message list | Rebuild isolation |
| failed outgoing media rows show retry and delete controls | Failed media UI |
| renders text plus video, voice, and failed media rows visibly | GMAR-004 visible video/voice/failed-media rows remain present across rebuild/reopen-style rendering |
| incoming, text-only, and read-only announcement rows do not show failed-media controls | Negative UI check |
| wraps incoming messages with swipe-to-quote when enabled | Swipe to quote |
| does not wrap outgoing messages with swipe-to-quote | Outgoing guard |
| does not wrap incoming messages with swipe-to-quote for readers | Reader guard |
| renders quoted replies from existing parent messages | Quote rendering |
| renders unavailable fallback when quoted parent is missing | Missing parent |
| resolves quoted media-only parent from mediaMap | Media quote |

### 5.8 GroupConversationWired
**File:** `test/features/groups/presentation/group_conversation_wired_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `GroupConversationWired` | prefills shared text into the group composer | Share intent |
| | hydrated group initialPendingMedia uses budget bytes instead of file size | Media budget |
| | oversized gallery attachment compresses under budget and stages the processed file | Compression |
| | oversized gallery attachment that remains over budget after compression leaves no pending state | Over-budget guard |
| | blocks a second text send while the first local send is in flight and releases after success | Send lock |
| | voice send blocks text send while the voice pipeline is active and releases after failure | Voice lock |
| | media uploads pre-persist upload_pending rows and start in parallel from durable copies | Durable media |
| | ordinary media pre-persists the parent row before upload completes and finalizes after sendGroupMessage | Pre-persist |
| | failed media upload leaves durable pending rows retryable and avoids group publish | Upload failure |
| | ordinary media upload failure persists failed parent state and restores composer and quote | Failure recovery |
| | ordinary media group-not-found rejection removes the row and cleans durable media state | Not-found cleanup |
| | ordinary media unauthorized rejection removes the row and cleans durable media state | Auth cleanup |
| | non-durable media send reuses optimistic attachment IDs when uploader returns different IDs | ID reuse |
| | sending a message with zero topic peers keeps the row sent and does not restore the draft | Zero-peer send |
| | incoming message stream upserts without full message/media reloads | Upsert optimization |
| | swipe-to-reply sends quotedMessageId and clears preview | Quote send |
| | live removal timeline event from listener appears in UI | Removal timeline |
| | live re-add timeline event from listener appears in UI | Re-add timeline |
| | shows loading shell until the initial group page resolves | Loading state |
| | highlights the targeted message context when opened from a notification anchor | Notification anchor + long-press parity |
| | notification-anchor entry keeps group reaction inspection aligned with the shared conversation surface | Notification anchor reaction parity |
| | incoming message preserves scroll offset when reading older messages | Scroll preservation |
| | recording ticks update composer without rebuilding header or message list | Rebuild isolation |
| | voice record callbacks switch the group composer into and out of recording | Voice recording |
| | loads and displays messages on init | Init loading |
| | sending a message calls bridge and refreshes | Send flow |
| | info button navigates to group info | Navigation |
| | returning from group info reloads the latest group name | Name reload |
| | non-admin in announcement group cannot write | Read-only mode |
| | dissolved groups show read-only copy and no send controls | Dissolved state |
| | announcement readers stay read-only for compose but still keep reaction entry | Reaction-entry parity |
| | dissolved groups hide reaction entry even when reaction deps are wired | Dissolved reaction-entry guard |
| | stale reaction entry restores local state when the group dissolves before publish | Dissolve race recovery |
| | non-admin in announcement group still has no voice stop/cancel callbacks when durable voice deps are enabled | Voice guard |
| | read-only announcement members cannot keep hidden quote state | Quote guard |
| | stale writer callbacks cannot bypass read-only announcement mode | Stale callback guard |
| | current group removal shows a notice and exits the conversation route | Removal exit |
| | gallery multi-video batches keep one processing tile with honest batch context | Multi-video |
| | sent text message appears immediately before bridge responds | Optimistic UI |
| | publish timeout with inbox success keeps the message successful in UI | Timeout + inbox |
| | sets tracker active on init | Tracker init |
| | clears tracker on dispose | Tracker cleanup |
| | accepts empty initialAttachments without error | Empty attachments |
| | recorded single video keeps single-item processing copy | Video processing |
| | optimistic message is saved to DB before network ops | Pre-persist |
| | failed publish shows message with failed status | Failure UI |
| | upload failure restores quote draft and attachments | Quote restoration |
| | shows relay upload progress and blocks leaving mid-upload | Upload progress |
| | retry control re-sends only the targeted failed outgoing media row | Targeted retry |
| | GMAR-004 reopen hydration preserves video voice pending and failed media without duplicates | Reopen hydration keeps completed/pending/failed media metadata, one row/attachment set, and scoped unavailable-media retry wiring |
| | delete control removes only the targeted failed media row and owned files | Targeted delete |
| | publish failure restores quote draft and attachments | Quote restoration |
| | voice send path stays hidden unless both durable media dependencies exist | Voice deps guard |
| | voice stop pre-persists a durable pending attachment and threads a stable blob ID | Voice pre-persist |
| | voice upload failure keeps upload_pending retry data and restores the quote | Voice failure |
| | successful voice send uses the durable copy, cleans pending uploads, and survives temp deletion | Voice success |
| | voice record stop keeps the optimistic voice row caller-local until upload completes | Voice optimistic |
| | voice send with zero topic peers still persists the final row as sent | Voice zero-peer |
| | voice group-not-found rejection does not leave a persisted outgoing row | Voice not-found |
| | voice stop cleanup still runs after unmount when group lookup resolves to not found | Voice cleanup |
| | voice upload failure restores the quoted reply target | Voice quote restore |
| | voice publish failure restores the quoted reply target | Voice quote restore |
| | announcement admin sees mic button for voice recording | Announcement voice |
| | loads persisted reactions on init when reactionRepo is provided | Reaction loading |
| | local long-press actions stay available when reactionRepo is null | No-reaction long-press parity |
| | incoming reaction change stream updates UI state | Reaction stream |
| | group reaction chips open participant inspection without mutating stored reactions | Reaction inspection + non-destructive tap |
| | group reaction inspection resolves member usernames and readable peer-id fallback | Reaction identity resolution |

### 5.9 GroupConversationWired Background Task
**File:** `test/features/groups/presentation/screens/group_conversation_wired_bg_task_test.dart`

| Group | Test | What it covers | Notes |
|-------|------|----------------|-------|
| `GroupConversationWired Section 3 background-task protection` | bg:begin happens before media upload and bg:end happens after publish and inbox store | Background task lifecycle | Active; AN-008 direct evidence; `group:inboxStore` command issuance/started-before-cleanup only, not durable completion-before-cleanup |
| | bg:end fires on media upload failure early return | Upload failure cleanup | Active; AN-008 direct evidence |
| | bg:end fires when upload throws | Upload throw cleanup | Active; AN-008 direct evidence |
| | send proceeds normally when OS refuses background task | OS refusal resilience | |
| | bg:end fires when widget unmounts mid-send | Unmount cleanup | |
| | ordinary media upload failure after unmount still persists failed parent status | Unmount failure persistence | |
| | text-only send acquires background task before publish | Text send protection | |
| | voice send path is background-task protected | Voice send protection | |
| | announcement voice-only send uses durable path, exact push body, and sent status when no peers are live | Announcement voice zero-peer | |
| | ordinary group text send stays bg-task protected across lock/unmount with peers | Text send lock/unmount | |
| | ordinary group text send returns sent after lock/unmount when topic peers are zero | Text send zero-peer | |
| | announcement admin text send stays bg-task protected across lock/unmount with peers | Announcement text lock/unmount | |
| | announcement admin text send returns sent after lock/unmount when topic peers are zero | Announcement text zero-peer | |
| | announcement media send preserves messageId, key epoch, and media metadata through wired path | Announcement media metadata | Active; AN-008 direct evidence |
| | order-recording bridge proves no early cleanup | Bridge ordering | Active; AN-008 direct evidence; live-peer inbox response may finalize after `bg:end`, but `group:inboxStore` command issuance starts before cleanup |

### 5.10 GroupInfoScreen
**File:** `test/features/groups/presentation/group_info_screen_test.dart`

| Test | What it covers |
|------|----------------|
| shows members | Member rendering |
| uses UserAvatar for each member row | Avatar consistency |
| keeps fallback identity readable when no avatar photo exists | Readable avatar fallback |
| shows roles | Role rendering |
| shows leave button | Leave CTA |
| shows dissolve button for active admins | Dissolve CTA |
| shows mute switch state | Mute toggle |
| calls onMuteChanged when mute switch is toggled | Mute callback |
| shows Add Member button when isAdmin | Add-member CTA |
| hides Add Member button when not admin | Add-member guard |
| calls onAddMember callback when tapped | Add-member callback |
| shows role-management controls only for eligible admin rows | Role controls |
| shows Edit Details button when admin can edit metadata | Edit CTA |
| hides Edit Details button when viewer is not admin | Edit guard |
| dissolved groups show local cleanup and hide management controls | Dissolved local cleanup |

### 5.11 GroupInfoWired
**File:** `test/features/groups/presentation/group_info_wired_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `GroupInfoWired` | loads and displays group members on init | Init loading |
| | shows Add Member button for admin role | Add-member CTA |
| | shows the creator username from the real create flow for other members | Creator identity rendering |
| | hides Add Member button for non-admin role | Add-member guard |
| | admin can dissolve a group and the screen switches to read-only state | Dissolve flow |
| | toggles mute state and persists it to the repository | Mute toggle |
| | hides member remove controls for non-admin role | Remove guard |
| | uses repo myRole instead of stale navigation role on load | Fresh role |
| | admin metadata edit updates repo state, timeline, and bridge payloads | Metadata edit + actor keys + config hash |
| | promote member shows confirmation, updates badge, and emits member_role_updated payload | Promote flow |
| | demote admin shows confirmation, updates badge, and emits success feedback | Demote flow |
| | dissolved local delete clears local state without publishing group leave and pops to the first route | Local-only cleanup flow |
| | canceling dissolved local delete keeps the group state and route intact | Local-delete cancel guard |
| | leave group calls bridge and pops to first route | Leave flow |
| | sole admin leave stays on screen and shows an error | Sole-admin guard |
| | multi-admin leave broadcasts self-removal, rotates key, and pops to first route | Multi-admin leave |
| | writer leave broadcasts a durable left-the-group event before local cleanup | Voluntary leave timeline |
| | remove member updates config and refreshes member list | Remove flow |
| | remove member broadcasts system message and rotates key | Remove side-effects |
| | remove member calls bridge in correct order: updateConfig -> publish -> inboxStore -> generateNextKey | Bridge command order |
| | remove member distributes rotated key to remaining members via P2P | Key distribution |
| | remove member broadcast and replay artifact contain correct member_removed payload | Payload shape |
| | canceling remove member keeps membership unchanged | Cancel guard |
| | stale non-member removal shows error and emits no removal side effects | Stale member guard |

### 5.12 CreateGroupPickerScreen
**File:** `test/features/groups/presentation/create_group_picker_screen_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `CreateGroupPickerScreen` | renders header with New Group title | Header text |
| | renders search field | Search UI |
| | renders contact rows | Contact list |
| | shows empty state when no contacts | Empty state |
| | search filters contacts by username | Search filter |
| | tapping contact calls onToggle | Toggle callback |
| | GroupNamePanel hidden when no contacts selected | Panel visibility |
| | GroupNamePanel visible when contacts selected | Panel visibility |
| | back button calls onBack | Back callback |
| | shows loading state when isCreating | Loading state |

### 5.13 CreateGroupPickerWired
**File:** `test/features/groups/presentation/create_group_picker_wired_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `CreateGroupPickerWired` | loads and displays active contacts | Init loading |
| | excludes self from contact list | Self exclusion |
| | tapping contact toggles selection | Toggle |
| | panel appears after selecting a contact | Panel visibility |
| | tapping Start group chat creates group and navigates to conversation | Create flow |
| | announcement picker route creates announcement group and sends announcement payload | Announcement create |
| | shows an explicit warning when create succeeds with invite degradation | Degraded create feedback |
| | shows error snackbar on failure | Error feedback |
| | shows a size-limit snackbar when create selection exceeds the contract | Limit feedback |
| | back button pops screen | Navigation |

### 5.14 ContactPickerScreen
**File:** `test/features/groups/presentation/contact_picker_screen_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `ContactPickerRow` | renders username | Row rendering |
| | calls onTap when tapped | Tap callback |
| | shows check_circle when isSelected is true | Selected state |
| | shows add_circle_outline when isSelected is false (default) | Unselected state |
| `ContactPickerScreen` | renders header with title and back button | Header rendering |
| | renders list of contacts | List rendering |
| | shows empty state when no contacts available | Empty state |
| | calls onToggle when contact is tapped | Toggle callback |
| | calls onBack when back button is tapped | Back callback |
| | header shows "Add Members (N)" when contacts are selected | Selected count |
| | header shows "Add Member" when nothing selected | Default header |
| | shows check_circle for selected contacts in list | Selection UI |
| | shows Send Invites button when 1+ selected | Invite CTA |
| | hides Send Invites button when none selected | CTA guard |
| | calls onConfirm when Send Invites tapped | Confirm callback |
| | search still works in multi-select mode | Search + select |
| | shows loading indicator when isInviting | Loading state |

### 5.15 ContactPickerWired
**File:** `test/features/groups/presentation/contact_picker_wired_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `ContactPickerWired` | shows contacts excluding existing group members | Member exclusion |
| | excludes self from contact list | Self exclusion |
| | tapping contact toggles selection state | Toggle |
| | confirm button appears after selecting one contact | CTA visibility |
| | header shows selected count | Count display |
| | batch invite adds all selected members to DB | Batch persist |
| | batch invite broadcasts one members_added system message | System message |
| | batch invite sends individual P2P invites to each contact | P2P invites |
| | batch invite pops with an explicit completion result | Pop result |
| | back button pops with 0 | Cancel pop |
| | shows error snackbar when invite fails | Error feedback |
| | stale duplicate selection fails without config sync or members_added publish | Stale dedup |
| | over-limit batch selection fails without partial members or config sync | Over-limit guard |
| | invite keeps local membership but reports explicit warning details when delivery fails | Invite warning feedback |
| | reports the current key generation when invite encryption succeeds | Key proof |
| | invite skips sendGroupInvite when no group key exists | Missing key skip |
| | batch invite with no group key still adds members locally | Local-only add |
| | batch invite saves a durable members-added timeline locally | Durable add timeline |

### 5.16 ContactPicker Multi-Select Integration
**File:** `test/features/groups/presentation/contact_picker_multi_select_integration_test.dart`

| Test | What it covers |
|------|----------------|
| multi-select integration: full batch invite flow | End-to-end batch invite |

### 5.17 GroupNamePanel
**File:** `test/features/groups/presentation/widgets/group_name_panel_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `GroupNamePanel` | renders overlapping UserAvatars for selected contacts | Avatar rendering |
| | displays comma-separated usernames | Username list |
| | shows group name text field with placeholder | Name field |
| | shows Start group chat button | Start CTA |
| | calls onStartGroup when button tapped | Start callback |
| | passes text field value to nameController | Name binding |
| | shows loading indicator when isCreating | Loading state |
| | renders correctly with 1 contact | Single contact |
| | displays +N suffix for 3+ contacts | Overflow suffix |

### 5.18 ExpandableFab
**File:** `test/features/groups/presentation/widgets/expandable_fab_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `ExpandableFab` | initially shows + icon (closed state) | Default state |
| | tapping FAB opens menu and shows x icon | Open state |
| | shows all menu item labels when open | Menu labels |
| | hides menu item labels when closed | Hidden labels |
| | calls item callback when menu item tapped | Item callback |
| | closes menu after item is tapped | Auto-close |
| | tapping x closes the menu | Close action |
| | shows scrim overlay when open | Scrim overlay |
| | defaults to bottom-right positioning | Default position |
| | positions at top-right when anchor is topRight | Alt position |
| | menu items appear below FAB when anchor is topRight | Alt layout |
| | passes fabSize to GlowFab | Size pass-through |

### 5.19 GlowFab
**File:** `test/features/groups/presentation/widgets/glow_fab_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `GlowFab` | renders + icon by default | Default icon |
| | renders custom icon when provided | Custom icon |
| | calls onPressed when tapped | Tap callback |
| | defaults to 56 when no size given | Default size |
| | uses custom size when provided | Custom size |
| | has circular shape with blue border | Shape + border |

### 5.20 ContactPickerRow
**File:** `test/features/groups/presentation/widgets/contact_picker_row_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `ContactPickerRow` | renders UserAvatar with contact peerId | Avatar rendering |
| | renders UserAvatar at size 36 | Avatar sizing |
| | displays contact username | Username display |
| | displays truncated peerId | PeerId display |
| | shows add_circle_outline icon when not selected | Unselected state |
| | shows check_circle icon when selected | Selected state |
| | calls onTap when tapped | Tap callback |

---

## 6. Integration Tests

### 6.1 Group Messaging Smoke
**File:** `test/features/groups/integration/group_messaging_smoke_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `Multi-user group messaging smoke tests` | 3 users: basic fan-out -- sender does not receive own message | Fan-out + self exclusion |
| | 4 users: round-robin messaging -- all receive from all others | Full mesh |
| | simultaneous sends fan out to the third member without loss | Concurrent fan-out |
| | same sender sequential messages stay ordered for both recipients | Message ordering |
| | message to unknown group is ignored | Unknown group guard |
| | late joiner receives messages only after joining | Late-join boundary |
| | sender saves outgoing locally and others save incoming | Direction persistence |
| | quoted reply propagates to all recipients | Quote fan-out |
| | message is received after app restart with rejoin | Rejoin recovery |

### 6.2 Group Membership Smoke
**File:** `test/features/groups/integration/group_membership_smoke_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `Multi-user group membership smoke tests` | admin removes member -- removed member stops receiving messages | Removal enforcement |
| | admin removes member -- remaining members update their local member list | Member list sync |
| | non-admin raw membership removal event is ignored by peers | Auth guard |
| | self-removal -- removed user calls leaveGroup and cleans up | Self-removal |
| | sole admin cannot leave while only writer members remain | Sole-admin guard |
| | promoted admin gains admin role and can perform admin-only actions | Promotion flow |
| | multi-admin leave keeps remaining admin healthy and synchronized | Multi-admin leave |
| | concurrent admin changes converge to one final member/admin map | Concurrent convergence |
| | conflicting remove and promote of the same member converge to removal | Conflict resolution |
| | removed member cannot send after self-removal cleanup | Post-removal send guard |
| | remaining peers accept only delayed removed-sender envelopes from before the persisted cutoff | Cutoff enforcement |
| | add member syncs every member list and the new member can participate | Add-member sync |
| | writer leave emits a durable left-the-group event for remaining members | Voluntary leave timeline |
| | duplicate re-add returns error and leaves member lists unchanged | Duplicate guard |
| | non-member removal returns error and leaves member lists unchanged | Non-member guard |
| | new member cannot send before bootstrap key exists, then succeeds after bootstrap completes | Bootstrap key |
| | post-removal messaging -- admin can still send to remaining members | Post-removal send |
| | remaining member receives readable removal timeline event while member list updates | Timeline event |
| | removed member can be re-added with current state and resumes send/receive | Re-add flow |
| | removed member notifications stay off until rejoin becomes effective | Notification guard |
| | long mixed-content group text survives delivery and notification preview | Long message |
| | remaining member receives readable re-add timeline event while member list updates | Re-add timeline |
| | offline member converges to dissolved state through replay, cannot send afterwards, and can delete locally without affecting others | Offline dissolve + local cleanup |

### 6.3 Group Edge Cases Smoke
**File:** `test/features/groups/integration/group_edge_cases_smoke_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `Group edge cases and fault injection smoke tests` | delivery failure -- messages not delivered when network fails | Network failure |
| | duplicate delivery -- GroupMessageListener handles idempotently | Dedup |
| | delivery delay -- messages arrive after delay | Delayed delivery |
| | 5 users simultaneous messaging -- high fan-out | High fan-out |
| | leave group voluntarily -- user stops receiving | Voluntary leave |
| | rapid message burst -- 20 messages from single sender | Burst handling |
| | network counters track publish and delivery correctly | Counter accuracy |

### 6.4 Startup Rejoin Smoke
**File:** `test/features/groups/integration/group_startup_rejoin_smoke_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `Startup rejoin smoke tests` | rejoin topics then receive live messages after simulated restart | Rejoin + live delivery |
| | rejoin + drain handles groups with no offline messages | Empty drain |
| | rejoin sends correct groupConfig with all member public keys | Config correctness |

### 6.5 Group Reaction Roundtrip
**File:** `test/features/groups/integration/group_reaction_roundtrip_test.dart`

| Test | What it covers |
|------|----------------|
| chat-group reaction roundtrip reaches the original sender through the live listener stream | Reaction fan-out |

### 6.6 Multi-Device Convergence
**File:** `test/features/groups/integration/group_multi_device_convergence_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `same-user multi-device convergence` | joined sibling device stores same-user live publish as local sent history | Multi-device sent history |
| | same-user sibling devices can send concurrently without id collision loss | Same-user concurrent send identity |
| | joined sibling device converges membership updates without duplicate local membership | Membership convergence |
| | sibling device stays one member while new human admission adds a distinct member | IJ-012 sibling-device versus new-human admission distinction |
| | device-local unsubscribe preserves member account and sibling delivery | RP-010 fake-network device-local unsubscribe |
| | mute, unread, and local notifications stay device-local across joined sibling devices | Device-local state |

### 6.7 Group Resume Recovery
**File:** `test/features/groups/integration/group_resume_recovery_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `Group resume recovery integration tests` | member backgrounded during send receives missed group messages after resume | Background resume |
| | same message is not duplicated if both pubsub and group inbox deliver it | Cross-path dedup + content preservation |
| | live reaction replay on resume keeps a single truthful stored reaction after rejoin | Reaction replay dedupe after resume |
| | post-rotation reaction replay after rejoin keeps the truthful reactor on the rotated message | Post-rotation reaction recovery |
| | removed offline member drains replayed removal, loses group access, and cannot send after resume | Offline removal |
| | offline remaining member drains remove-vs-send backlog and keeps the same before-cutoff outcome after resume | Cutoff + resume |
| | watchdog restart rejoins topics and receives subsequent live messages | Watchdog rejoin |
| | announcement reader backgrounded during send receives missed announces after resume | Announcement resume |
| | zero-peer inbox failure stays owned by failed-message retry and recovers in place | Zero-peer retry ownership |
| | MM-012 acceptance uses real GroupConversationWired sender path to keep discussion sendable and announcement admin blocked during active recovery | Recovery send contract |
| | 10-A acceptance uses real GroupConversationWired sender path with reader lifecycle inbox recovery | Announcement wired send |
| | announcement media send with zero topic peers stays sent and readers recover intact media refs after resume | Zero-peer media |
| | 10-B acceptance uses real GroupConversationWired sender path for media + resume fallback | Media resume |
| | 10-C acceptance uses real GroupConversationWired sender path for voice + exact push body | Voice send path |
| | announcement admin send after key rotation uses the new epoch and remains deliverable | Post-rotation send |
| | 10-F acceptance uses real GroupConversationWired sender path after key rotation | Rotation + wired |
| | group discovery remains live across ttl refresh window without manual rejoin | Discovery TTL |
| | fake group network delivers live messages without explicit relay simulation | Test infra validation |
| | many joined groups resume without bursting recovery work all at once | Batch throttle |
| | resume drains missed group backlog exactly once across pages | Multi-page drain |
| | multi page backlog uses cursor continuation without duplication | Cursor pagination |
| | multi page replay with a tampered timestamp still keeps one stored row | Replay tamper dedup across pages |
| | long-offline mixed-window recovery keeps retained backlog and never resurrects expired pages | Retention enforcement |
| | watchdog restart rejoins topics and resumes live delivery | Watchdog recovery |
| `Section 11 test infrastructure` | publish with zero peers falls back to inbox | Zero-peer fallback |
| | inbox store failure doesn't block publish | Inbox error isolation |
| | rapid pause/resume closes a pending live-peer send via inbox retry exactly once | Rapid lifecycle |
| | stuck sending recovery after background | Stuck recovery |
| | partial delivery with inbox drain completion | Partial drain |
| | temporary partition replays missed backlog in cursor order and resumes live delivery after heal | Partition heal |
| | full lifecycle round-trip | End-to-end lifecycle |
| | failed message retry after network recovery | Network retry |
| | unread count stays correct across duplicate inbox drain, retry recovery, and read clear | Unread accuracy |
| | offline member reconnects after membership churn and converges to the final member list | Churn convergence |
| | offline member reconnects after repeated metadata edits and converges to the final metadata state | Metadata convergence |
| | multi-group resume doesn't burst all recovery at once | Multi-group throttle |

### 6.8 Invite Round-Trip
**File:** `test/features/groups/integration/invite_round_trip_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `Group invite round-trip integration` | full invite round-trip: admin sends invite -> receiver processes it -> group is persisted | End-to-end invite |
| | new member history stays future-only while post-join replay is allowed | History boundary |
| | remove -> rotate -> re-invite round-trip gives the rejoined member the rotated epoch | Re-invite after rotation |
| | offline removed member reconnects later from inbox-fallback re-invite on the rotated epoch | Offline re-invite |
| | full round-trip with PassthroughCryptoBridge verifies | Crypto round-trip |
| | receiver rejects invite from unknown sender (not in contacts) | Unknown sender guard |
| | receiver rejects duplicate invite for group already joined | Duplicate guard |
| | invite round-trip with multiple members in config | Multi-member config |
| | GroupInviteListener stores pending invite and explicit accept completes the join flow | Pending accept flow |
| | accept publishes a durable join event that existing members can render | Durable join timeline |
| | bridgeError accept later rejoin and drain converge without the pending invite row | Accepted-but-degraded later recovery |
| | concurrent pending accepts converge members, key epoch, and sendability | IJ-010 concurrent accept convergence |

### 6.9 Announcement Happy Path
**File:** `test/features/groups/integration/announcement_happy_path_test.dart`

| Test | What it covers |
|------|----------------|
| announcement happy path: create, admin send, reader read-only receive, member react | Full announcement lifecycle |
| announcement admin can send GIF media and reader receives image/gif read-only | GIF announcement |

### 6.10 Group New-Member Onboarding
**File:** `test/features/groups/integration/group_new_member_onboarding_test.dart`

Added for Report 85.

| Group | Test | What it covers |
|-------|------|----------------|
| `Group new-member onboarding` | new member receives only post-join text and media with descriptors | Discussion post-join text/image/video/voice, no pre-join backfill, descriptor persistence, media-download trigger |
| | multiple newly-added members converge on latest epoch and receive the same post-add message | Multi-add same-epoch convergence |
| | multiple newly-added members independently download the same post-join image, video, and voice without pre-join history | GMAR-003 Bob/Charlie same post-join image/video/voice completed downloads with sender/message/epoch/attachment metadata, exact per-recipient download calls, and no pre-join text/media rows, attachments, pending downloads, or pre-join media download calls |
| | new member receives current metadata and roles without pre-join history | IJ-011 current metadata, role snapshot, and future-only history |
| | add-send boundary delivers only after the new member is subscribed | Deterministic add/send boundary |
| | new member receives post-join reactions without pre-join reaction state | Reaction fan-out to newly-added member |
| | quoted reply to pre-join parent keeps missing-parent fallback for new member | Post-join quote with unavailable pre-join parent |

### 6.11 Announcement New-Reader Onboarding
**File:** `test/features/groups/integration/announcement_new_reader_onboarding_test.dart`

Added for Report 85.

| Group | Test | What it covers |
|-------|------|----------------|
| `Announcement new-reader onboarding` | new reader receives only post-join admin media with descriptors | Announcement image/video/voice delivery to newly-added reader, no pre-join admin-post backfill, media-download trigger |

### 6.12 Existing-Member Group Media Fan-Out
**File:** `test/features/groups/integration/group_media_fanout_test.dart`

Added for Report 85.

| Group | Test | What it covers |
|-------|------|----------------|
| `Existing-member group media fan-out` | discussion members independently download image, video, and voice for every eligible recipient | Existing Bob/Charlie receive Alice's image/video/voice rows with matching sender message ids and attachment metadata; both independently complete downloads with local paths and exactly three `media:download` calls each |
| | one recipient media download failure remains observable per recipient | A forced Charlie image download failure remains `failed`/non-done with no local path while Bob's image/video/voice and Charlie's video/voice downloads remain done |
| | MD-011 removed member is excluded from future media descriptors and downloads | After removal and epoch-2 rotation, remaining B receives/downloads future media while removed C has no descriptor, message, media row, pending download, download/decrypt bridge call, subscription, or future key |
| | newly-added discussion member media reaches every eligible recipient | GMAR-003 newly-added Bob sends image/video/voice after bootstrap; Alice and Charlie receive exact-once rows with Bob sender identity, sender message ids, key epoch, attachment metadata, completed downloads, and exactly three `media:download` calls each |
| | existing non-creator discussion member media reaches creator and every eligible recipient | GMAR-003 existing non-creator Charlie sends image/video/voice; Alice and Bob receive exact-once rows with Charlie sender identity, sender message ids, key epoch, attachment metadata, completed downloads, and exactly three `media:download` calls each |

---

## 7. Core Layer (Lifecycle & Bridge)

### 7.1 handleAppPaused (groups)
**File:** `test/core/lifecycle/handle_app_paused_group_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `handleAppPaused for groups` | transitions group alongside 1:1 | Parallel transition |
| | group error isolation leaves 1:1 transition intact | Error isolation |
| | null groupMsgRepo keeps pause handler backward compatible | Null compat |
| | group-only pending sends still transition when 1:1 count is zero | Group-only path |

### 7.2 handleAppResumed (group inbox retry)
**File:** `test/core/lifecycle/handle_app_resumed_group_inbox_retry_test.dart`

| Test | What it covers |
|------|----------------|
| resume handler Step 8e calls retryFailedGroupInboxStoresFn | Inbox retry wiring |
| resume handler Step 8e is fault-isolated from Step 8d | Error isolation |
| resume handler continues normally when retryFailedGroupInboxStoresFn is null | Null compat |

### 7.3 handleAppResumed (group recovery)
**File:** `test/core/lifecycle/handle_app_resumed_group_recovery_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `handleAppResumed group recovery` | calls rejoin, drain, recoverStuck, retryIncompleteGroupUploads, retryFailed, then retryFailedGroupInboxStores | Full recovery sequence |
| | feature gate disables group recovery callbacks | Feature gate |
| | blocks admin-only group actions until replayed membership removal settles | Recovery lock |

### 7.4 handleAppResumed (group stuck sending)
**File:** `test/core/lifecycle/handle_app_resumed_group_stuck_sending_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `handleAppResumed -- group stuck sending recovery` | calls rejoin, drain, recoverStuck, then retryFailed | Recovery sequence |

### 7.5 main resume group upload wiring
**File:** `test/core/lifecycle/main_resume_group_upload_wiring_test.dart`

| Test | What it covers |
|------|----------------|
| main.dart passes mediaFileManager into retryIncompleteGroupUploads on resume | DI wiring |
| main.dart passes mediaAttachmentRepository into retryFailedGroupMessages on resume | DI wiring |
| main.dart wires group retry callbacks into PendingMessageRetrier | Retry wiring |
| main.dart binds the pending retrier overlap guard to _isResuming | Guard wiring |

### 7.6 Bridge Group Helpers
**File:** `test/core/bridge/bridge_group_helpers_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `callGroupCreate` | sends group:create with correct payload fields | Payload shape |
| | sends groupType NOT type in the payload (bug fix) | Field naming |
| | includes optional description when provided | Optional field |
| | excludes optional fields when null | Null omission |
| | returns parsed response on success | Response parsing |
| | returns error map on bridge error | Error handling |
| | returns timeout error on timeout | Timeout handling |
| | includes creatorMlKemPublicKey when provided | Key inclusion |
| | groupType field carries the correct value for different types | Type mapping |
| `callGroupKeygen` | sends group.keygen and returns key string on success | Keygen |
| | rethrows TimeoutException on timeout | Timeout handling |
| `callGroupPublish` | sends group:publish with correct payload and returns messageId | Publish |
| | returns error map on bridge error | Error handling |
| | returns timeout error on timeout | Timeout handling |
| | includes media in payload when provided | Media inclusion |
| | includes quotedMessageId when provided | Quote inclusion |
| | omits media when null | Null media |
| | omits media when empty list | Empty media |
| `callGroupEncrypt` | sends group.encrypt with key and plaintext | Encrypt |
| | returns timeout error map on timeout | Timeout handling |
| `callGroupDecrypt` | sends group.decrypt with key, ciphertext, and nonce | Decrypt |
| | rethrows TimeoutException on timeout | Timeout handling |
| `callGroupJoin` | sends group:join with groupId and topicName | Join |
| | completes without error on success | Success path |
| | rethrows TimeoutException on timeout | Timeout handling |
| `callGroupJoinWithConfig` | sends group:join with groupId, groupConfig, groupKey, keyEpoch | Join with config |
| | completes without error on success | Success path |
| | rethrows TimeoutException on timeout | Timeout handling |
| `callGroupAcknowledgeRecovery` | sends group:acknowledgeRecovery | Recovery ack |
| | completes without error on success | Success path |
| | rethrows TimeoutException on timeout | Timeout handling |
| `callGroupLeave` | sends group:leave with groupId | Leave |
| | completes without error on success | Success path |
| | rethrows TimeoutException on timeout | Timeout handling |
| `callGroupUpdateConfig` | sends group:updateConfig with groupId and full groupConfig | Config update |
| | rethrows TimeoutException on timeout | Timeout handling |
| `callGroupGenerateNextKey` | sends group:generateNextKey and returns key info | Key generation |
| | returns timeout error on timeout | Timeout handling |
| `callGroupRotateKey legacy helper` | sends group:rotateKey and returns key info | Legacy rotate |
| | returns timeout error on timeout | Timeout handling |
| `callGroupInboxStore` | sends group:inboxStore with groupId and message | Inbox store |
| | includes recipientPeerIds, pushTitle, and pushBody when provided | Push fields |
| | omits empty optional push fields | Null omission |
| | throws BridgeCommandException on ok:false | Error handling |
| | rethrows TimeoutException on timeout | Timeout handling |
| `callGroupInboxRetrieve` | sends group:inboxRetrieve and returns list of messages | Inbox retrieve |
| | returns empty list when no messages | Empty state |
| | returns empty list when messages field is null | Null guard |
| | throws BridgeCommandException on ok:false | Error handling |
| | rethrows TimeoutException on timeout | Timeout handling |
| `callGroupInboxRetrieveWithCursor` | encodes cursor and page metadata and returns next cursor | Cursor pagination |
| | rethrows TimeoutException on timeout | Timeout handling |
| | throws BridgeCommandException on ok:false | Error handling |

### 7.7 Go Bridge Client (group diagnostics subset)
**File:** `test/core/bridge/go_bridge_client_test.dart`

| Test | What it covers |
|------|----------------|
| group decryption failure push event reaches diagnostics stream without invoking group message callback | Owned Flutter diagnostics without ghost message routing |
| group payload parse failure push event reaches diagnostics stream without invoking group message callback | Malformed payload diagnostics without ghost message routing |
| `BridgeCommandException on ok:false` | throws BridgeCommandException when group:join returns ok:false | Join error |
| | throws BridgeCommandException when group:join (with config) returns ok:false | Join-config error |
| | throws BridgeCommandException when group:leave returns ok:false | Leave error |
| | throws BridgeCommandException when group:updateConfig returns ok:false | Config error |

---

## 8. Cross-Feature Tests

### 8.1 groupMessagesIntoThreads (Feed)
**File:** `test/features/feed/domain/utils/group_messages_into_threads_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `groupMessagesIntoThreads` | empty input returns empty output | Empty state |
| | single unread incoming message produces unread state | Unread derivation |
| | sent + received messages both appear in thread | Bidirectional |
| | state derivation: unread -- unread incoming, no sent | State logic |
| | state derivation: active -- unread incoming + sent messages | State logic |
| | state derivation: replied -- all read + has sent | State logic |
| | state derivation: read -- all read, no sent | State logic |
| | 24-hour gap keeps single card per contact | Gap handling |
| | unread/active sort before read/replied | Sort priority |
| | exchangePreview returns last 2 messages | Preview window |
| | lastRepliedAt is set to latest sent message timestamp | Reply timestamp |
| | user sends first (no incoming) produces replied state | Send-first state |
| | ThreadMessage preserves isIncoming and status | Field preservation |
| | multiple contacts produce separate threads | Thread isolation |
| | blocked contact produces ThreadFeedItem with isBlocked=true | Block flag |
| | non-blocked contact produces ThreadFeedItem with isBlocked=false | Non-block flag |
| | quotedMessageId propagates to ThreadMessage | Quote propagation |
| | system messages are excluded from feed threads | System msg exclusion |
| | only system messages produces empty result | System-only guard |
| | burst within same contact stays in one thread | Burst handling |

### 8.2 groupGroupMessagesIntoThreads (Feed)
**File:** `test/features/feed/domain/utils/group_group_messages_into_threads_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `groupGroupMessagesIntoThreads` | returns empty list when no messages | Empty state |
| | returns empty list when no groups | No groups |
| | creates one thread per group | Thread per group |
| | derives unread state when unread incoming with no sent | State logic |
| | derives active state when unread incoming + sent messages | State logic |
| | derives replied state when all read + sent messages | State logic |
| | derives read state when all incoming are read, no sent | State logic |
| | sorts unread/active before read/replied | Sort priority |
| | ignores messages for unknown groups | Unknown group |
| | messages sorted chronologically within thread | Sort order |
| | preserves group type in thread item | Type preservation |
| | preserves myRole and derives canWrite for announcement groups | Role + write flag |
| | preserves dissolved state and freezes write and reaction entry | Dissolved frozen-state projection |
| | preserves quotedMessageId on projected thread messages | Quote propagation |
| | thread id is group_thread_ + groupId | ID construction |
| | timestamp is latest message timestamp | Timestamp derivation |
| | ThreadMessage includes senderUsername and senderPeerId from GroupMessage | Sender fields |
| | multiple unread groups sorted newest-first within above section | Multi-group sort |

### 8.3 loadOrbitGroups (Orbit)
**File:** `test/features/orbit/application/load_orbit_groups_use_case_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `loadOrbitGroups` | returns empty list when no groups | Empty state |
| | loads active groups only (excludes archived) | Archive filter |
| | includes latest message preview | Preview loading |
| | includes unread count | Unread count |
| | sorts by most recent activity first | Activity sort |
| | uses createdAt as fallback when no messages | Fallback sort |
| | returns null latestMessage when group has no messages | Null preview |
| | loads a single group snapshot by group id | Single lookup |
| | returns null when a group snapshot no longer exists | Missing group |

### 8.4 Orbit Archived Groups (group-relevant subset)
**File:** `test/features/orbit/presentation/screens/orbit_screen_archived_groups_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `OrbitScreen archived groups` | shows archived groups in archived tab even when no archived friends | Archived visibility |
| | shows empty state when no archived friends and no groups | Empty state |
| | shows groups in all tab | All-tab rendering |

### 8.5 GroupRow BiDi (Orbit)
**File:** `test/features/orbit/presentation/widgets/group_row_bidi_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `GroupRow` | renders LTR sender plus Arabic-first body with RTL body direction | BiDi preview |
| | renders Arabic sender plus English-first body with LTR body direction | BiDi preview |
| | renders empty preview fallback when no structured message | Empty preview |
| | renders mixed-script preview content | Mixed script |
| | renders announcement groups without throwing | Announcement compat |

### 8.6 Swipeable Group Row (Orbit)
**File:** `test/features/orbit/presentation/widgets/swipeable_group_row_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `Swipeable Group Row` | swiping left reveals only Delete + Archive (no Block) | Swipe actions |
| | tapping Archive fires onArchive callback | Archive callback |
| | tapping Delete fires onDelete callback | Delete callback |
| | archived group shows Unarchive on swipe | Unarchive action |

### 8.7 Push Open Flow (group-relevant subset)
**File:** `test/features/push/application/chat_and_group_push_open_flow_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `chat and group push open flow` | background group push opens group only after targeted group catch-up | Background push sequencing |
| | terminated group push opens group only after targeted group catch-up | Terminated push sequencing |

### 8.8 resolveGroupNotificationRouteTarget
**File:** `test/features/push/application/resolve_group_notification_route_target_use_case_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `resolveGroupNotificationRouteTarget` | returns the existing group without draining inbox | Existing group |
| | returns the existing pending invite without draining inbox | Existing invite |
| | drains inbox and resolves a newly stored pending invite | Inbox drain + invite |
| | drains inbox and resolves a newly materialized group | Inbox drain + group |
| | returns missing when neither group nor invite can be recovered | Missing guard |
| | returns missing for a stale removed-group notification after local cleanup | Removed-group stale notification denial |

### 8.9 Group Notification Dedup
**File:** `test/integration/group_notification_dedupe_integration_test.dart`

| Test | What it covers |
|------|----------------|
| background push announcement suppresses later local group notification for the same message | Notification dedup |

### 8.10 Intro Group Header
**File:** `test/features/introduction/presentation/widgets/intro_group_header_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `IntroGroupHeader` | renders mixed-script introducer usernames | Unicode rendering |
| | renders plain English usernames | Basic rendering |
| | dynamic Arabic-first username stays explicit inside header | RTL text |
| | dynamic English-first username stays explicit inside header | LTR text |

### 8.11 loadFeed with Group Messages (Feed)
**File:** `test/features/feed/application/load_feed_use_case_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `loadFeed with group messages` | returns group thread items when group repos provided | Group thread loading |
| | group items merge with contact items sorted by timestamp | Merge + sort |
| | dissolved groups stay visible but project frozen feed affordances | Dissolved feed visibility + frozen affordances |
| | no group items when group repos not provided | Feature gate |
| | archived groups excluded from feed | Archive filter |
| | groups with no messages produce no thread items | Empty group |
| | loadGroupFeedItems batch-loads media attachments | Media batch loading |
| | loadFeed includes group media attachments | Media inclusion |

### 8.12 Feed Projection Parity (group-relevant subset)
**File:** `test/features/feed/application/feed_projection_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `feed projection parity` | group message upsert and reorder matches cold load | Incremental upsert + frozen-state parity |
| | group message with media flows through to ThreadMessage | Media propagation |
| | archived group removal matches cold load | Archive removal |
| | loadGroupFeedSnapshot includes media attachments | Snapshot media |
| | loadGroupFeedSnapshot without media repos returns empty media | Null media repo |

### 8.13 FeedStore (group-relevant subset)
**File:** `test/features/feed/application/feed_store_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `FeedStore` | replaceGroupSnapshot updates one keyed group while preserving contact threads | Snapshot replace |

### 8.14 FeedItem GroupThreadFeedItem (Feed)
**File:** `test/features/feed/domain/models/feed_item_test.dart`

| Test | What it covers |
|------|----------------|
| ThreadFeedItem.isGroup returns false | Group discrimination |
| GroupThreadFeedItem.isGroup returns true | Group discrimination |
| GroupThreadFeedItem provides all CardThreadFeedItem getters | Interface |
| has type groupThread | Type identity |
| stores group type correctly for all types | Type mapping |
| active announcement readers stay read-only for compose but can still react | Announcement affordance split |
| dissolved groups disable both write and react affordances | Dissolved affordance freeze |

### 8.15 OpenModeCardBody (Feed group subset)
**File:** `test/features/feed/presentation/widgets/open_mode_card_body_test.dart`

| Test | What it covers |
|------|----------------|
| group header uses RTL for Arabic-first mixed display name | BiDi rendering |
| renders group avatar and group name for GroupThreadFeedItem | Group avatar |
| group message with media passes media to MessageBubble in open mode | Media propagation |
| group thread: tapping group avatar fires onViewEarlier | Avatar navigation |

### 8.16 FeedCard (Feed group subset)
**File:** `test/features/feed/presentation/widgets/feed_card_test.dart`

| Test | What it covers |
|------|----------------|
| renders OpenModeCardBody for unread GroupThreadFeedItem | Open mode |
| renders CollapsedModeCardBody for read GroupThreadFeedItem | Collapsed mode |
| session reply forces CollapsedModeCardBody for unread group card | Session reply |
| active group card without session reply stays in open mode | Mode persistence |

### 8.17 CollapsedModeCardBody (Feed group subset)
**File:** `test/features/feed/presentation/widgets/collapsed_mode_card_body_test.dart`

| Test | What it covers |
|------|----------------|
| renders group avatar for GroupThreadFeedItem | Group avatar |
| preview label uses per-message senderUsername for group | Sender label |
| group card shows thumbnail when message has downloaded image | Image thumbnail |
| group card shows icon fallback when media not yet downloaded | Download fallback |
| group card media-only message shows thumbnail + Photo label | Photo label |
| group card media-only GIF message shows thumbnail + GIF label | GIF label |
| group thread collapsed: tapping avatar navigates | Avatar navigation |

### 8.17a FeedScreen (Feed group subset)
**File:** `test/features/feed/presentation/screens/feed_screen_test.dart`

| Test | What it covers |
|------|----------------|
| inline group reaction chips route through the dedicated inspection callback | Inline discussion reaction inspection |
| announcement reader cards keep inline reaction inspection available while compose stays read-only | Inline announcement-reader parity |
| dissolved group cards show dissolved copy and hide reply and reaction entry | Dissolved inline frozen-state |

### 8.18 FeedWired (Feed group subset)
**File:** `test/features/feed/presentation/screens/feed_wired_test.dart`

| Test | What it covers |
|------|----------------|
| loads the Orbit badge from pending group invites on first load | Invite badge init |
| refreshes the Orbit badge when a pending group invite arrives | Invite badge stream |
| inline orbit return refreshes the Orbit badge after local pending group invite changes | Invite badge refresh |
| collapse from open-mode group card marks messages read and collapses | Read marking |
| displays group thread cards when group data exists | Group card rendering |
| refreshes feed on incoming group message | Message stream |
| incremental group message carries media attachments to feed card | Media propagation |
| incoming group message clears session reply so card shows open mode | Session reply clear |
| incoming group message updates only the affected group thread | Incremental update |
| orbit route result refreshes only the changed group snapshot | Snapshot refresh |
| changed group snapshot refresh updates the feed group avatar metadata | Avatar metadata |
| group card + button shows media picker bottom sheet | Media picker |
| group swipe-to-reply shows preview and persists quotedMessageId on send | Swipe to quote |
| group inline send wraps publish in a background task | Background task |
| group inline send becomes retry-discoverable before publish resolves | Retry discovery |
| group inline reply shows session reply immediately before network completes | Session reply |
| group inline reply restores quote and draft on send failure | Failure recovery |
| group inline reply shows session reply on success end-to-end | Session reply E2E |
| group inline reply treats zero-peer publish as success and keeps the message sent | Zero-peer send |
| incremental group updates preserve quoted replies in feed cards | Quote preservation |
| feed opens announcement admins with a writable group conversation | Announcement write |
| feed entry keeps group long-press actions aligned with the shared conversation surface | Feed long-press parity |
| feed entry keeps group reaction inspection aligned with the shared conversation surface | Feed reaction-inspection parity |
| stale dissolved feed reaction entry restores prior state and refreshes the card | Dissolve race recovery |

### 8.19 OrbitWired (Orbit group subset)
**File:** `test/features/orbit/presentation/screens/orbit_wired_test.dart`

| Test | What it covers |
|------|----------------|
| tapping FAB opens menu with New Group and New Announce | Create menu |
| displays group rows when groups exist | Group rendering |
| displays structured group rows with latest message preview | Preview rendering |
| refreshes only the affected group on incoming group message | Incremental refresh |
| create-group route result refreshes only the affected group | Create refresh |
| interleaves groups and friends sorted by last activity | Activity sort |
| pending group invites are visible from the Intros tab and counted in the Orbit badge | Invite badge |
| accepting a pending group invite from Intros joins the group | Invite accept |
| all tab renders active groups before archived hydration completes | Archived hydration |
| orbit entry keeps group long-press actions aligned with the shared conversation surface | Orbit long-press parity |
| orbit entry keeps group reaction inspection aligned with the shared conversation surface | Orbit reaction-inspection parity |

### 8.20 Notification Body for Group Messages (Push)
**File:** `test/features/push/application/notification_body_for_message_test.dart`

| Test | What it covers |
|------|----------------|
| group image-only message body is "Alice: Photo" | Image body |
| group GIF-only message body is "Alice: GIF" | GIF body |
| group audio-only message body is "Alice: Voice message" | Voice body |
| group captioned image body is "Alice: Check this out" | Caption body |

### 8.21 Background Push Notification Fallback (Push group subset)
**File:** `test/features/push/application/background_push_notification_fallback_test.dart`

| Test | What it covers |
|------|----------------|
| shows fallback for group_message type with groupId | Group fallback |
| shows group fallback on iOS when Flutter sees only the data payload | iOS data payload |
| skips group fallback on iOS when RemoteMessage already has a visible notification payload | iOS visible guard |
| skips fallback for group_message type without groupId | Missing ID guard |
| shows fallback for group_invite type and routes to intros | Invite fallback |

### 8.22 Notification Tap Smoke (group subset)
**File:** `test/integration/notification_tap_smoke_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `remote push tap (warm app)` | group_invite → intros | Warm invite tap |
| | group_message → group | Warm message tap |
| `remote push tap (terminated app)` | group_invite → intros | Terminated invite tap |
| | group_message → group | Terminated message tap |
| `local notification tap (warm app)` | group payload | Local group tap |
| `local notification initial launch` | group initial launch | Cold group launch |
| `background push fallback → show → tap → route` | group_invite push → fallback → tap → intros route | Invite fallback route |
| | group_message push → fallback → tap → group route | Message fallback route |
| `edge cases` | group_message without groupId → missing | Missing ID edge case |
| | group: with empty groupId → nothing fires | Empty ID edge case |
| `drain correctness per notification kind` | conversation drains 1:1 inbox, not group | 1:1 drain isolation |
| | contactRequest drains 1:1 inbox, not group | 1:1 drain isolation |
| | intros drains 1:1 inbox, not group | 1:1 drain isolation |
| | group_invite drains 1:1 inbox, not group | Invite drain isolation |
| | group drains targeted group inbox, not 1:1 | Group drain targeting |

### 8.23 Loading States Smoke (group subset)
**File:** `test/features/loading_states_smoke_test.dart`

| Test | What it covers |
|------|----------------|
| Group list loading renders without overflow | Group list loading |

### 8.24 Network Failover (group-relevant subset)
**File:** `test/core/resilience/network_failover_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `Phase 7 — Network failover: group send path` | group send path survives relay A loss | Group relay failover |
| `Phase 7 — Network failover: runtime recovery flags` | runtime feature flags can disable new recovery behaviors intentionally | Recovery feature gate |

### 8.25 Pending Message Retrier Upload Ordering (group-relevant subset)
**File:** `test/core/services/pending_message_retrier_upload_ordering_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `PendingMessageRetrier -- retryIncompleteUploads ordering` | online sweep runs rejoin, drain, group retries, shared 1:1 retries, then group inbox retry | Recovery step ordering |

### 8.26 Share to Contact Smoke (group-relevant subset)
**File:** `test/features/share/integration/share_to_contact_smoke_test.dart`

| Test | What it covers |
|------|----------------|
| 6a: share text can target multiple selected recipients from the picker | Multi-target share including group |
| 6i: announcement group where user is not admin is excluded from picker | Announcement write-guard in picker |

### 8.27 Share Batch Delivery Coordinator (group-relevant subset)
**File:** `test/features/share/application/share_batch_delivery_coordinator_test.dart`

| Test | What it covers |
|------|----------------|
| text-only group share wraps publish in a background task and stays sent on durable success | Group share bg task |
| group share keeps live-peer pending rows queued until inbox custody closes | Group share inbox custody |

### 8.28 Share Target Picker Wired (group-relevant subset)
**File:** `test/features/share/presentation/share_target_picker_wired_test.dart`

| Test | What it covers |
|------|----------------|
| 2j, 2q, 2r, 2s: loads only active contacts and writable groups | Group filtering in picker |
| send invokes the coordinator exactly once with selected targets | Multi-target group send |
| partial failure keeps only failed targets selected | Group share partial failure |

### 8.29 PendingMessageRetrier (group-relevant subset)
**File:** `test/core/services/pending_message_retrier_test.dart`

| Test | What it covers |
|------|----------------|
| group continuity sweep runs on a shorter cadence than full retry loop | Group sweep cadence |
| needsGroupRecovery false-to-true while online triggers immediate continuity sweep | Recovery trigger |
| immediate group recovery does not reset the 30-second fallback timer | Timer independence |
| successful retrier-owned nodeRequestedRecovery sends ack on immediate recovery | Recovery ack |
| successful retrier-owned recovery sends ack on the retry sweep path | Sweep ack |
| failed retrier-owned recovery does not send ack | Failed recovery guard |

### 8.30 NotificationRouteTarget (group-relevant subset)
**File:** `test/core/notifications/notification_route_target_test.dart`

| Test | What it covers |
|------|----------------|
| fromRemoteMessageData maps group_message to group route | Group route mapping |
| fromRemoteMessageData maps group_invite to intros route | Invite route mapping |
| group payload round-trips through toPayload and fromPayload | Payload round-trip |

### 8.31 NotificationPushTapNavigate (group-relevant subset)
**File:** `test/core/notifications/notification_push_tap_navigate_test.dart`

| Test | What it covers |
|------|----------------|
| group push navigates to group | Group push navigation |

### 8.32 ShareTargetPickerScreen (group-relevant subset)
**File:** `test/features/share/presentation/share_target_picker_screen_test.dart`

| Test | What it covers |
|------|----------------|
| 2c and 2d: renders contact and group sections | Group section rendering |
| tapping group toggles selection via callback | Group toggle |
| 2g: search filters both contacts and groups | Group search |
| 2i: empty contacts/groups shows empty state | Empty group state |

### 8.33 Routing Smoke Group Criteria
**File:** `test/integration/routing_smoke_group_criteria_test.dart`

Added for Report 85. These host-side criteria guard the paired simulator
orchestrator from passing on sender-only or pending receiver evidence.

| Group | Test | What it covers |
|-------|------|----------------|
| `routing smoke group criteria` | G2 requires all five warm messages | Warm-burst receive count |
| | G4 requires Bob receiver-visible inbox recovery | Offline inbox recovery evidence |
| | G5 rejects pending or missing receiver timeline evidence | Full-lifecycle receiver timeline completeness |
| | G7 requires rotation plus pre and post rotation receipts | Rotation traffic receive proof |
| | G8 requires Bob receipt in addition to Alice publish success | Flood-publish receiver proof |

---

## 9. Test Helpers & Fakes

The group test infrastructure includes the following shared fakes:

| File | Purpose |
|------|---------|
| `test/shared/fakes/fake_group_pubsub_network.dart` | Simulates GossipSub pubsub network with topic-based fan-out, fault injection, delivery delays, and drop rates |
| `test/shared/fakes/group_test_user.dart` | Encapsulates full per-user group stack (listener, bridge, repos) for multi-user integration tests |
| `test/shared/fakes/in_memory_group_repository.dart` | In-memory group repository for fast tests |
| `test/shared/fakes/in_memory_group_message_repository.dart` | In-memory group message repository for fast tests |
| `test/shared/fakes/in_memory_pending_group_invite_repository.dart` | In-memory pending invite repository for fast tests |

---

## 10. Coverage Gaps

Areas of the group chat feature that have **no dedicated test coverage** or only indirect coverage:

### 10.1 Data Layer
- **Group message full-text search**: No tests for any search/query by content.

### 10.2 Application Layer
- **GroupMessageListener**: Has broad coverage for system messages, notifications, reactions, media forwarding, and DB-002 event-log replay/tamper protection. System message handler coverage includes member_added, member_removed, members_added, group_dissolved, member_role_updated, group_metadata_updated, and key_rotated.
- **Flow-event contract inventory**: No dedicated tests pin group-specific event family names or validate their structured payloads.
- **Concurrent key rotation during member removal**: Only tested through the member_removal_integration_test; no isolated concurrency stress test.

### 10.3 Presentation Layer
- **GroupConversationWired background task AN-008 coverage**: `group_conversation_wired_bg_task_test.dart` keeps all 15 background-task tests active, including the former 5 skipped bg:begin/bg:end lifecycle, upload cleanup, announcement media metadata, and order-recording bridge rows. Direct suite and adjacent announcement media gates passed; no AN-008 skipped rows remain.

### 10.4 Integration / E2E
- **True multi-device E2E**: Multi-device tests use in-memory fakes in the repo-owned suite. OS-010 evidence on 2026-04-30 revalidated `group_multi_device_convergence_test.dart` as the host oracle, extended `group_multi_device_policy_test.dart` so composer drafts are explicitly device-local, and found `FLUTTER_DEVICE_ID` plus `MKNOON_RELAY_ADDRESSES` unset. Earlier 2026-04-12 spare iOS proof remains in `/tmp/md004_group_multi_device_real_rerun8_20260412.log`, and the final 2026-04-12 deployed-relay rerun on the primary iOS pair is recorded in `/private/tmp/acceptance_20260412/group_multi_device_real_primary_ios.log`; a fresh same-account two-device run covering messages, read state, keys, drafts, and membership remains device-lab evidence.
- **Push notification trigger path**: Group push routing is tested. Earlier 2026-04-12 spare iOS proof remains in `/tmp/ux009_notification_open_ui_smoke_20260412_rerun16e_drive.log`, and the final 2026-04-12 deployed-relay rerun on the primary iOS pair is recorded in `/private/tmp/acceptance_20260412/notification_open_ui_primary_ios.log`.
- **Network partition healing**: Report 85 tightened `temporary partition replays missed backlog` in `group_resume_recovery_test.dart` to three missed split-window messages across cursor-ordered durable inbox pages plus post-heal live delivery. A real bridge/GossipSub partition-heal simulator proof remains device-lab residual evidence.
- **Full simulator media and recovery matrix**: Report 85 added host/app-layer media onboarding, media fan-out, retry, foreground-drain, and strict paired-run criteria coverage. MD-014 targeted recheck on 2026-04-30 used configured `FLUTTER_DEVICE_ID=347FB118-10D0-40C8-A05B-B0C3BD6B8CCD` plus supplied relay addresses and `group-real-network-nightly` passed. GMAR-004 later made the configured `integration_test/group_new_member_media_simulator_proof_test.dart` proof green by fixing stale video/voice fixture metadata under group media integrity policy, and added host reopen/retry/offline duplicate proof. GMAR-005 closed Report 90's all-recipient media/gate-confidence layer on 2026-05-03 by passing configured simulator media proofs, `media_message_journey_e2e_test.dart`, `media_stable_id_smoke_test.dart`, the paired simulator routing/group and foreground group push smoke commands with relay addresses, the device-pinned `all` gate, completeness check, broad `flutter test`, Go module tests, and `git diff --check`. Full announcement-specific simulator media journeys, OS-state group notification matrix breadth, relay outage replay and duplicate-prevention breadth, broader failure/recovery UI breadth, and the file dimension while MD-013 is unsupported still require configured device-lab runs or an explicit scope decision.

### 10.5 Security
- **Replay attack on group messages**: Now covered by `handle_incoming_group_message_use_case_test.dart` and `group_resume_recovery_test.dart`, which pin timestamp-tampered replay dedup plus remove/dissolve cutoff enforcement on the Flutter-visible receive path.
- **Tampered group message payload**: Now covered by `pubsub_decryption_failure_test.go`, which pins wrong-key, tampered-nonce, tampered-ciphertext, and malformed-payload rejection without any `group_message:received` event, and `go_bridge_client_test.dart`, which keeps the owned Flutter diagnostics route pinned.
- **Real-crypto onboarding and re-add**: Now covered at the real Go-bridge app boundary by `integration_test/group_real_crypto_onboarding_test.dart`. Live GossipSub two-node delivery remains separate device-lab evidence.
- **Membership-event signature forgery**: Now covered at the Go envelope-validator layer by `TestGroupTopicValidator_RejectsForgedMembershipSystemEventSignature` in `pubsub_test.go`; app-layer authorization remains covered by `group_message_listener_test.dart`.
- **Key rotation race conditions**: MS-018 now has direct app-layer proof in `send_group_message_use_case_test.dart`, `group_key_update_listener_test.dart`, and `drain_group_offline_inbox_use_case_test.dart` for send-time epoch snapshots, before/during/after local rotation commit sends, pending receive-side key update sends, mixed old/new encrypted replay, and safe future-epoch undecryptable placeholder creation without wrong-epoch decrypt or plaintext fallback. The remaining gap is a combined true/equivalent 3-party or live proof where A rotates, B sends around B's commit boundary, and C receives out of order over the transport path.
- **Group observability contract drift**: Now covered by `send_group_message_use_case_test.dart`, `rejoin_group_topics_use_case_test.dart`, `drain_group_offline_inbox_use_case_test.dart`, `retry_failed_group_messages_use_case_test.dart`, and `retry_failed_group_inbox_stores_use_case_test.dart`, which pin stable begin/success/skip/error/timing flow-event names and required detail keys on the shipped Flutter-owned group send/recovery/retry paths.

### 10.6 Go / Dart Boundary
- **Create-time description remains intentionally unsupported**: Go `GroupCreate()` still does not parse `description`, and the shipped create surface does not expose it. Any future scope change will need new Go/Dart round-trip proof.

---

## 11. E2E / Device Tests

Tests in `integration_test/` that run on a real device or simulator via `flutter test integration_test/`.

Primary simulator / emulator targets for the remaining exploratory/device-proof rows:
- Android primary pair: `emulator-5554`, `emulator-5556`
- iOS primary pair: `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD` (`iPhone Air`), `5BA69F1C-B112-47BE-B1FF-8C1003728C8F` (`iPhone 17`)
- iOS spare validation: `1B098DFF-6294-407A-A209-BBF360893485` (`iPhone 16e`)

### 11.1 Group Recovery E2E
**File:** `integration_test/group_recovery_e2e_test.dart`

| Test | What it covers |
|------|----------------|
| group member receives missed group messages after resume drain | Resume drain delivery |
| announcement reader receives missed announcement after resume drain | Announcement resume drain |
| group inbox drain deduplicates message already received live | Cross-path dedup |
| offline recovered dissolved group exposes local-only cleanup on Group Info | Device-backed dissolved cleanup |
| watchdog restart rejoins topics and multi-group drain stays bounded | Watchdog batch recovery |

### 11.2 Group Recovery CLI E2E
**File:** `integration_test/group_recovery_cli_e2e_test.dart`

| Test | What it covers |
|------|----------------|
| real CLI peer drives live and inbox group recovery | CLI-driven recovery round-trip |

### 11.3 Real-Crypto Group Onboarding
**File:** `integration_test/group_real_crypto_onboarding_test.dart`

Added for Report 85.

| Group | Test | What it covers |
|-------|------|----------------|
| `real-crypto group onboarding` | Bob accepts a real encrypted invite, decrypts first-add and re-add group ciphertext | Real Go-bridge ML-KEM invite acceptance, group AES-GCM decrypt, re-add current epoch decrypt, retained old-key decrypt failure |

### 11.4 Foreground Group Push Drain
**File:** `integration_test/foreground_group_push_drain_test.dart`

Extended for Report 85.

| Group | Test | What it covers |
|-------|------|----------------|
| `foreground group push drain` | foreground group push drains the targeted group inbox and surfaces one in-app notification | Targeted group inbox drain and in-app notification |
| | foreground group push drains media exactly once with descriptor and download trigger | Representative image media drain, descriptor preservation, one download trigger |
| | foreground group push does not duplicate a message or notification already received live | Live-plus-push dedupe |
| | foreground 1:1 push still drains the 1:1 inbox only | Cross-kind isolation |
| | foreground post push does not trigger any drain | Unsupported-kind guard |

### 11.5 Multi-Relay Failover
**File:** `integration_test/multi_relay_failover_test.dart`

Tightened for Report 85.

| Mode | Test | What it covers |
|------|------|----------------|
| Strict fixture guard | multi-relay fixture is required for this closure run | Fails clearly when `MKNOON_REQUIRE_MULTI_RELAY=true` and fewer than two relay addresses are configured |
| No fixture | two relay failover keeps 1:1 delivery working (requires `MKNOON_RELAY_ADDRESSES`) | Truthful skip placeholder, not closure evidence |
| No fixture | two relay failover keeps group recovery working (requires `MKNOON_RELAY_ADDRESSES`) | Truthful skip placeholder, not closure evidence |
| Configured fixture | imports `transport_e2e.main()` and `group_recovery_e2e.main()` | Real-stack 1:1 and group recovery under multi-relay configuration |

### 11.6 Group New-Member Media Simulator Proof
**File:** `integration_test/group_new_member_media_simulator_proof_test.dart`

| Test | What it covers |
|------|----------------|
| group new-member media simulator proof | GMAR-004 configured simulator proof for visible incoming/outgoing text-plus-video/voice rows, `VideoThumbnailOverlay`, `AudioPlayerWidget`, voice play/pause, video open, and conversation-surface reopen preservation on `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD` |

**Recurring command:** `FLUTTER_DEVICE_ID=<device> MKNOON_RELAY_ADDRESSES=<relay1,relay2,...> ./scripts/run_test_gates.sh group-real-network-nightly`

---

## 12. Go-Side Tests

Group-related tests in `go-mknoon/`. Counts reflect only `func Test*` functions that exercise group messaging paths; files with mixed group/non-group tests show only the group-relevant subset.

### 12.1 Group Crypto
**File:** `go-mknoon/crypto/group_test.go` (14 tests)

| Test | What it covers |
|------|----------------|
| TestGenerateGroupKey_Length | Key is 32 bytes |
| TestGenerateGroupKey_Unique | Two keys differ |
| TestGroupEncryptDecrypt_RoundTrip | Encrypt/decrypt fidelity |
| TestGroupEncryptDecrypt_WrongKey | Wrong-key rejection |
| TestGroupEncryptDecrypt_TamperedCiphertext | Tampered ciphertext detection |
| TestGroupEncryptDecrypt_TamperedNonce | Tampered nonce detection |
| TestGroupEncryptDecrypt_UniqueNonces | Unique nonce per encrypt |
| TestGroupEncryptDecrypt_EmptyString | Empty plaintext |
| TestGroupEncryptDecrypt_LargeMessage | 1 MB message |
| TestEncryptGroupMessage_InvalidKey | Non-base64 key rejection |
| TestEncryptGroupMessage_WrongKeyLength | 16-byte key rejection |
| TestDecryptGroupMessage_InvalidBase64 | Base64 error handling |
| TestBuildGroupSignatureData_Format | Pipe-delimited signature format |
| TestBuildGroupSignatureData_Deterministic | Deterministic signature |

### 12.2 Group Envelope / Wire Format
**File:** `go-mknoon/internal/group_envelope_test.go` (11 tests)

| Test | What it covers |
|------|----------------|
| TestMarshalParseGroupEnvelope_RoundTrip | v3 envelope round-trip |
| TestParseGroupEnvelope_InvalidJSON | Malformed JSON rejection |
| TestParseGroupEnvelope_MissingFields | Required field validation |
| TestIsGroupEnvelope_V3GroupMessage | v3 detection |
| TestIsGroupEnvelope_V1Message | v1 rejection |
| TestIsGroupEnvelope_V2Message | v2 rejection |
| TestIsGroupEnvelope_InvalidJSON | Invalid JSON handling |
| TestMarshalParseGroupPayload_RoundTrip | Payload round-trip |
| TestMarshalParseGroupPayload_WithExtra | Extra field preservation |
| TestGroupMessagePayloadWithMediaExtra | Media metadata in payload |
| TestGroupMessagePayloadWithQuotedMessageIdExtra | Quoted reply support |

### 12.3 PubSub Core
**File:** `go-mknoon/node/pubsub_test.go` (82 tests)

Covers topic creation, validator logic, config updates, discovery, and publish operations:

| Category | Key Tests |
|----------|-----------|
| Topic & Config | TestGroupTopicName, TestGroupTopicAndRendezvousNamespace_DoNotUseHumanReadableMetadata, TestJoinGroupTopic_LogOmitsHumanReadableMetadata, TestGroupConfig_Serialization, TestGroupKeyInfo_Serialization, TestGroupMember_Serialization, TestGroupMember_OmitEmpty |
| Writer Authorization | TestIsAllowedWriter_ChatAnyMember, _AnnouncementAdminOnly, _AnnouncementMemberBlocked, _QAAnyMember, _NonMember |
| Member Lookup | TestFindMember_Found, _NotFound, _DuplicatePeerId_ReturnsFirst |
| Validator | TestGroupTopicValidator_ValidMessage, _TransportPeerIdMatchesEnvelopeSender, _RejectsTransportPeerIdMismatch, _InvalidJSON, _UnknownGroup, _UnauthorizedSender, _RejectsUnauthorizedEventFamiliesBeforeForward, _AnnouncementNonAdminRejected, _BadSignature, _SpoofedPublicKey, _RejectsForgedMembershipSystemEventSignature, _NotV3Envelope, _WrongKeyEpoch, _EmptyMembersList, _ConcurrentValidation |
| Join / Leave | TestJoinGroupTopic_WithMultiMemberConfig, _ValidatorAcceptsAllListedMembers, _FailsWithoutPubSub, _RejectsDoubleJoin, TestLeaveGroupTopic_CancelsDiscoveryContext, TestLeaveGroupTopic_RemovesPubSubStateAndBlocksFuturePublish |
| Config Update | TestUpdateGroupConfig_ReplacesConfigAtomically, _NonExistentGroup, _PreservesDiscoveryLoop, _ConcurrentUpdates |
| Invite Lifecycle | TestInviteLifecycle_AdminAddsNewMember_ValidatorAcceptsNewMember, _AnnouncementGroup_NewWriterCannotPublish |
| Discovery | TestGroupRendezvousNamespace, _MatchesTopicName, _EmptyGroupId, TestFilterDiscoveredPeers_*, TestFilterDiscoveredGroupMembers_*, TestGroupDiscoveryInterval, _WarmInterval, TestGroupDiscoveryConcurrency, TestGroupRecoveryLimiter_*, TestGroupDiscoveryLoop_BacksOff*, _DedupesConcurrentPeerDials, TestGroupDiscoveryCycle_NoKnownPeersUsesRendezvousFallback |
| Recovery | TestGroupRecovery_PreservesTopicStateAcrossInPlaceRefresh |
| Publish | TestPublishGroupMessage_BuildsCorrectEnvelope, TestBuildGroupMessageExtra_PreservesQuotedMessageId, TestBuildGroupMessageReceivedEvent_IncludesQuotedMessageId |
| Encrypt / Relay Visibility | TestGroupMessage_EncryptDecryptRoundTrip, TestGroupRelayVisibleMessageEnvelope_EncryptsContentBeforeRelay, TestGroupRelayVisibleReactionEnvelope_EncryptsContentBeforeRelay |
| Diagnostics | TestAnnouncementGroup_AdminPublishWithZeroPeersStillUsesDurableFallback, TestPublishGroupMessage_EmitsLiveFanoutDiagnosticWithoutFailingDurableSend |
| Peer Preference | TestGroupDiscovery_UsesDiscoveredAddressesBeforeRelayFallback, TestKnownGroupMemberDial_PrefersExistingOrDirectPathBeforeRelay |
| Key Lookup | TestGetGroupKeyInfo_ReturnsCurrentKey, _ReturnsNilForUnknownGroup |
| Node Lifecycle | TestStopNode_CancelsAllDiscoveryContexts, TestGroupDiscoveryCtx_InitializedByInitPubSub, TestCountConnectedGroupMembers_UnknownGroup |

### 12.4 PubSub Delivery
**File:** `go-mknoon/node/pubsub_delivery_test.go` (9 tests)

| Test | What it covers |
|------|----------------|
| TestPublishGroupMessage_ReturnsPeerCountZero_WhenNoPeers | Zero-peer count |
| TestPublishGroupMessage_ReturnsPeerCountPositive_WhenPeersConnected | Positive peer count |
| TestPublishGroupMessage_RefreshesMissingKnownTopicPeersBeforePublish | Peer refresh before publish |
| TestPublishGroupMessage_ReturnsErrorForUnjoinedGroup | Unjoined group error |
| TestPublishGroupMessage_DuplicateProvidedMessageIdRemainsVisibleAfterDecrypt | Duplicate live PubSub publishes preserve the same application messageId after decrypt |
| TestGroupPeerDiscoveryLoop_DialsKnownMembersBeforeCircuitAddressWait | Pre-circuit member dial |
| TestGroupPeerDiscoveryLoop_DialsKnownMembersBeforeRelayReadyWhenDirectAddrsKnown | Direct address preference |
| TestGroupPeerDiscoveryLoop_RetriesMissingThirdPeerDuringWarmWindow | Warm window retry |
| TestGroupPeerDiscoveryLoop_UsesWarmRetryImmediatelyAfterPartialInitialRecovery | Warm retry timing |

### 12.5 Key Rotation Grace Period
**File:** `go-mknoon/node/pubsub_key_rotation_grace_test.go` (9 tests)

| Test | What it covers |
|------|----------------|
| TestGroupTopicValidator_AcceptsPreviousEpochDuringGrace | Old key during grace |
| TestGroupTopicValidator_RejectsPreviousEpochAfterGraceExpires | Old key after grace |
| TestGroupTopicValidator_AcceptsCurrentEpochDuringGrace | Current key during grace |
| TestGroupTopicValidator_RejectsRemovedSenderPreviousEpochDuringGrace | Removed sender cannot use previous-epoch grace |
| TestGroupTopicValidator_RejectsUnknownFutureEpochBeforeDelivery | Unknown future epoch rejects before delivery |
| TestUpdateGroupKey_PreservesPreviousKeyAndGraceDeadline | Grace state preservation |
| TestJoinGroupTopic_InitialKeyHasNoGraceState | Initial key no grace |
| TestHandleGroupSubscription_DecryptsPreviousEpochDuringGrace | Decrypt with old key |
| TestHandleGroupSubscription_DropsPreviousEpochAfterGraceExpires | Old key after grace stays non-deliverable |

### 12.6 Decryption Failure Events
**File:** `go-mknoon/node/pubsub_decryption_failure_test.go` (4 tests)

| Test | What it covers |
|------|----------------|
| TestHandleGroupSubscription_EmitsDecryptionFailedEvent | Decryption failure event |
| TestHandleGroupSubscription_EmitsPayloadParseFailedEvent | Parse failure event |
| TestHandleGroupSubscription_EmitsDecryptionFailedEventForTamperedNonce | Wrong-nonce rejection with no ghost message event |
| TestHandleGroupSubscription_EmitsDecryptionFailedEventForTamperedCiphertext | Tampered-ciphertext rejection with no ghost message event |

### 12.6A Shared Security Proof Harness
**File:** `go-mknoon/node/group_security_harness_test.go` (1 test)

This file also owns the shared raw-envelope mutation, local-node connect/publish,
event wait, and grace-fixture helpers reused by the decryption-failure and
key-rotation suites.

| Test | What it covers |
|------|----------------|
| TestMutateGroupEnvelope_RewritesEncryptedFieldsWithoutChangingRoutingMetadata | Raw envelope mutation helper preserves routing metadata while tampering encrypted fields for later security-row proofs |

### 12.7 Group Inbox
**File:** `go-mknoon/node/group_inbox_test.go` (9 tests)

| Test | What it covers |
|------|----------------|
| TestBuildGroupInboxStoreRequest_MarshalsRecipientPeerIds | Recipient list marshaling |
| TestBuildGroupInboxStoreRequest_MarshalsPushTitle | Push title |
| TestBuildGroupInboxStoreRequest_MarshalsPushBody | Push body |
| TestBuildGroupInboxStoreRequest_PreservesOpaqueReplayEnvelope | Opaque encrypted replay envelope stays in the relay request message field without plaintext body, media key, invite token, or history text when notification preview text is safe |
| TestGroupInboxRetrieveCursor_DefaultsLimitWhenZero | Default limit |
| TestGroupInboxRetrieveCursor_StableAcrossPages | Cursor stability |
| TestGroupInboxRetrieveCursor_NoDuplicateOnContinuation | No duplicate on continue |
| TestGroupInboxRetrieveCursor_RequiresStartedNode | Node startup guard |
| TestGroupInboxRetrieveCursor_NegativeLimitDefaultsTo50 | Negative limit default |

### 12.8 Multi-Relay (group and Report 85 relay-recovery subset)
**File:** `go-mknoon/node/multi_relay_test.go` (8 of 22 tests)

| Test | What it covers |
|------|----------------|
| TestNewRelaySelector_GroupsByPeerID | Relay grouping |
| TestDialPeerViaRelay_TriesSecondRelayWhenFirstFails | Direct-to-relay fallback attempt |
| TestRendezvousRegister_TriesSecondRelayWhenFirstFails | Rendezvous register relay fallback |
| TestRendezvousDiscover_TriesSecondRelayWhenFirstFails | Rendezvous discover relay fallback |
| TestInboxStore_TriesSecondRelayWhenFirstFails | 1:1 inbox relay fallback prerequisite |
| TestGroupInboxRetrieve_TriesSecondRelayWhenFirstFails | Inbox relay failover |
| TestGroupInboxRetrieveCursor_TriesSecondRelayWhenFirstFails | Cursor relay failover |
| TestMediaUpload_TriesSecondRelayWhenFirstFails | Media relay fallback prerequisite |

### 12.9 Rendezvous
**File:** `go-mknoon/node/rendezvous_test.go` (2 tests)

| Test | What it covers |
|------|----------------|
| TestGroupRendezvousRefresh_KeepsRegistrationAlivePastTTL | TTL refresh |
| TestAnnouncementGroupRendezvousRefresh_UsesSameTTLRefreshPath | Announcement TTL |

### 12.10 Config (group-relevant subset)
**File:** `go-mknoon/node/config_test.go` (1 of 4 tests)

| Test | What it covers |
|------|----------------|
| TestGroupPublishPeerSettleWindows_StayShortForForegroundSend | Peer settle timing |

### 12.10A Protocol Version
**File:** `go-mknoon/node/protocol_version_test.go` (4 tests)

| Test | What it covers |
|------|----------------|
| TestGroupProtocolIDs_AreVersionedCurrentContracts | Current chat, inbox/group inbox, rendezvous, and media protocol IDs remain semver-like `/.../1.0.0` contracts |
| TestGroupProtocolChatStreamNegotiatesCurrentVersionOnly | Current chat protocol opens successfully and an unsupported chat protocol ID is rejected |
| TestSecureLibp2pChannelRequiredBeforeMknoonProtocols | Insecure `libp2p.NoSecurity` host cannot connect to the raw TCP mknoon node address or open `ChatProtocol`, and no insecure peer connection is retained |
| TestGroupProtocolInboxStoreUsesVersionedInboxProtocol | Group inbox store opens relay streams on `InboxProtocol` |

### 12.11 Node / Relay Session / Stream Timeout (group-relevant subset)
**Files:** `go-mknoon/node/node_test.go` (1 of 49 tests), `go-mknoon/node/relay_session_test.go` (1 of 17 tests), `go-mknoon/node/stream_timeout_test.go` (1 of 3 tests)

| Test | File | What it covers |
|------|------|----------------|
| TestPersonalRendezvousRefreshLoop_DoesNotStartForGroupNamespaceRegister | node_test.go | Group namespace exclusion |
| TestWatchdog_MarksNeedsGroupRecoveryForFlutter | relay_session_test.go | Watchdog group recovery flag |
| TestOutboundStreams_ApplyDeadlineAcrossChatInboxRendezvousGroupInboxAndMedia | stream_timeout_test.go | Group inbox stream deadline |

### 12.12 Bridge API
**File:** `go-mknoon/bridge/bridge_test.go` (53 of 133 tests)

| Category | Key Tests |
|----------|-----------|
| Crypto | TestGenerateGroupKey_ReturnsKey, TestGroupEncryptDecryptRoundTrip, TestGroupEncryptMessage_InvalidJSON, _MissingFields, TestGroupDecryptMessage_InvalidJSON, _MissingFields, _WrongKey |
| Create | TestGroupCreate_NodeNotInitialized, _InvalidJSON, _MissingFields |
| Join | TestGroupJoinTopic_NodeNotInitialized, _InvalidJSON, _MissingFields, _WithInviteData, _AlreadyJoinedIsIdempotent |
| Leave | TestGroupLeaveTopic_NodeNotInitialized, _InvalidJSON, _MissingGroupId |
| Publish | TestGroupPublish_NodeNotInitialized, _InvalidJSON, _MissingFields, _EmptyTextAndNoMedia_Fails, _MediaOnly_AcceptsEmptyText, _ResponseIncludesTopicPeers, TestBuildGroupPublishOpts_IncludesQuotedMessageId, _EmptyReturnsNil |
| Config Update | TestGroupUpdateConfig_NodeNotInitialized, _InvalidJSON, _MissingGroupId, _WithNewMember |
| Key Rotate | TestGroupRotateKey_NodeNotInitialized, TestRotateKey_InvalidJSON, TestGroupRotateKey_MissingGroupId, _IncrementsEpoch |
| Key Update | TestGroupUpdateKey_NodeNotInitialized, _InvalidJSON, _MissingFields, _UpdatesStoredKey |
| Inbox Store | TestGroupInboxStore_NodeNotInitialized, _InvalidJSON, _MissingFields, _AcceptsPushFanoutFields, _UsesProvidedServerAddresses |
| Inbox Retrieve | TestGroupInboxRetrieve_NodeNotInitialized, _InvalidJSON, _MissingGroupId, TestGroupInboxRetrieveCursor_NodeNotInitialized, _InvalidJSON, _MissingGroupId, _PassesOpaqueCursor, _CommandExposed |
| Recovery | TestGroupAcknowledgeRecovery_NotInitialized, _Success |

**File:** `go-mknoon/bridge/bridge_generate_next_key_test.go` (4 tests)

| Test | What it covers |
|------|----------------|
| TestGroupGenerateNextKey_NodeNotInitialized | Uninitialized guard |
| TestGroupGenerateNextKey_InvalidJSON | JSON validation |
| TestGroupGenerateNextKey_MissingGroupId | Missing ID guard |
| TestGroupGenerateNextKey_DoesNotMutateStoredKeyState | Non-destructive generation |

### 12.13 CLI Test Peer (group-relevant subset)
**File:** `go-mknoon/cmd/testpeer/commands_test.go` (4 of 29 tests)

| Test | What it covers |
|------|----------------|
| TestHandleCommandGroupJoinNotStarted | Join without node |
| TestHandleCommandGroupJoinMissingParams | Missing join params |
| TestHandleCommandGroupPublishWithoutIdentity | Publish without identity |
| TestHandleCommandGroupInboxStoreMissingText | Missing inbox text |

### 12.14 Go Integration (group-relevant subset)
**File:** `go-mknoon/integration/media_test.go` (2 of 3 tests)

| Test | What it covers |
|------|----------------|
| TestRelayGroupMediaUploadDownload | Group media relay round-trip with two authorized non-sender downloads and outsider rejection |
| TestRelayGroupMediaVoiceNote | Group voice note relay |

**File:** `go-mknoon/integration/relay_test.go` (1 of 20 tests)

| Test | What it covers |
|------|----------------|
| TestRelayRefreshPreservesJoinedGroupTopics | Topic preservation on refresh |
