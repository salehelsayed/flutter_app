# Group Chat Feature -- Test Inventory

**Date:** 2026-04-11
**Scope:** All automated tests covering the Group Chat feature across unit, widget, integration, cross-feature, E2E, and Go-side categories.

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
  test/core/database/helpers/group_keys_db_helpers_test.dart
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

**E2E device tests (requires running simulator):**

```sh
flutter test integration_test/group_recovery_e2e_test.dart
flutter test integration_test/group_recovery_cli_e2e_test.dart
```

**Go-side group tests:**

```sh
cd go-mknoon && go test ./crypto/ ./internal/ ./node/ ./bridge/ ./cmd/testpeer/ -run 'Group|Announcement|Watchdog.*Group' -v
```

---

## Summary

### Dart Tests

| Category | Files | Test Cases |
|----------|------:|-----------:|
| Domain (models, repo impl) | 14 | 100 |
| Data (DB helpers) | 6 | 83 |
| Data (DB migrations) | 7 | 27 |
| Application (use cases, listeners) | 36 | 376 |
| Presentation (widgets, screens) | 20 | 252 |
| Integration (smoke, round-trip, recovery) | 9 | 93 |
| Core (lifecycle, bridge) | 6 | 74 |
| Cross-feature (feed, orbit, push, intro, share, resilience, services, notifications) | 32 | 182 |
| E2E / Device (`integration_test/`) | 2 | 5 |
| **Dart Total** | **132** | **1192** |

### Go Tests

| Category | Files | Group-Related Tests |
|----------|------:|--------------------:|
| Crypto (`crypto/`) | 1 | 14 |
| Envelope / Wire Format (`internal/`) | 1 | 11 |
| PubSub Core (`node/pubsub*.go`) | 4 | 93 |
| Shared Security Harness (`node/group_security_harness_test.go`) | 1 | 1 |
| Group Inbox (`node/group_inbox*.go`) | 1 | 8 |
| Multi-Relay (`node/multi_relay*.go`) | 1 | 3 |
| Rendezvous (`node/rendezvous*.go`) | 1 | 2 |
| Config (`node/config*.go`) | 1 | 1 |
| Node / Relay Session / Stream (`node/node*.go`, `node/relay_session*.go`, `node/stream_timeout*.go`) | 3 | 3 |
| Bridge API (`bridge/`) | 2 | 57 |
| CLI Test Peer (`cmd/testpeer/`) | 1 | 4 |
| Integration (`integration/`) | 2 | 3 |
| **Go Total** | **19** | **200** |

### Grand Total

| | Files | Tests |
|-|------:|------:|
| **All (Dart + Go)** | **151** | **1392** |

> **Note:** Dart file counts reflect distinct `_test.dart` files. Some inventory sections cover multiple files (e.g., 4.9 covers `archive_group_use_case_test.dart` + `unarchive_group_use_case_test.dart`; 4.30 covers three reaction test files). Dart test counts are `grep`-verified against `test()`/`testWidgets()` declarations in each file. Cross-feature test counts include only the group-relevant subset from shared test files. Go test counts reflect only group-related `func Test*` functions in files that may also contain non-group tests; counts are `grep`-verified against `func Test.*[Gg]roup` patterns and manual review for files with indirect group test names. Last verified: 2026-04-11.

## 0. Row Closure Crosswalk (2026-04-11)

| Row | Closure state | Concrete repo evidence |
|-----|---------------|------------------------|
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
| `MD-005` | Accepted | `orbit_wired_test.dart` and `feed_wired_test.dart` already pin Orbit and Feed message-level parity, while `group_conversation_wired_test.dart` now pins notification-anchor reaction inspection and `app_root_notification_open_test.dart`, `resolve_group_notification_route_target_use_case_test.dart`, and `chat_and_group_push_open_flow_test.dart` keep the push-entry route contract aligned with that shared surface. |
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
| | keeps local installation state device-specific | Local state scope |
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

---

## 3. Data Layer (DB Migrations)

### 3.1 Migration 026: group_messages.quoted_message_id
**File:** `test/core/database/migrations/026_group_quoted_message_id_test.dart`

| Test | What it covers |
|------|----------------|
| adds quoted_message_id column to group_messages | Schema addition |
| existing rows get null quoted_message_id on upgrade | Default value |
| can store a quoted parent id after migration | Write after migration |
| is idempotent | Migration safety |

### 3.2 Migration 048: groups.last_membership_event_at
**File:** `test/core/database/migrations/048_groups_last_membership_event_at_test.dart`

| Test | What it covers |
|------|----------------|
| adds last_membership_event_at column to groups | Schema addition |
| existing rows get null last_membership_event_at on upgrade | Default value |
| can store a membership-event watermark after migration | Write after migration |
| is idempotent | Migration safety |

### 3.3 Migration 049: groups metadata columns
**File:** `test/core/database/migrations/049_groups_metadata_columns_test.dart`

| Test | What it covers |
|------|----------------|
| adds avatar and metadata watermark columns to groups | Schema addition |
| existing rows get null metadata columns on upgrade | Default value |
| can store metadata fields after migration | Write after migration |
| is idempotent | Migration safety |

### 3.4 Migration 050: groups.is_muted
**File:** `test/core/database/migrations/050_groups_mute_column_test.dart`

| Test | What it covers |
|------|----------------|
| adds is_muted column to groups | Schema addition |
| existing rows get is_muted = 0 on upgrade | Default value |
| can store muted state after migration | Write after migration |
| is idempotent | Migration safety |

### 3.5 Migration 051: pending_group_invites
**File:** `test/core/database/migrations/051_pending_group_invites_test.dart`

| Test | What it covers |
|------|----------------|
| creates pending_group_invites table | Table creation |
| stores and loads pending invite rows | Read/write |
| is idempotent | Migration safety |

### 3.6 Migration 052: groups dissolve columns
**File:** `test/core/database/migrations/052_groups_dissolve_columns_test.dart`

| Test | What it covers |
|------|----------------|
| adds dissolve columns to groups | Schema addition |
| existing rows get non-dissolved defaults on upgrade | Default value |
| can store dissolved state after migration | Write after migration |
| is idempotent | Migration safety |

### 3.7 Migration 053: groups backlog retention columns
**File:** `test/core/database/migrations/053_groups_backlog_retention_columns_test.dart`

| Test | What it covers |
|------|----------------|
| adds backlog retention columns to groups | Schema addition |
| existing rows get null backlog retention defaults on upgrade | Default value |
| can store backlog retention state after migration | Write after migration |
| is idempotent | Migration safety |

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
| | rolls back staged members when `group:updateConfig` fails after local adds | Config rollback |
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
| | sends message with empty text and media (voice note) | Voice note |
| | rejects message with empty text and no media | Empty guard |
| | rejects message with whitespace-only text and no media | Whitespace guard |
| | sanitizes dangerous bidi controls from text before save | Bidi sanitization |
| | handles message with multiple media attachments | Multi-media |
| | handles message without media (backward compat) | Backward compat |
| | text-only message without media -- no media in payload | No-media path |
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
| `sendGroupInvite` | encrypts invite payload and sends to recipient via p2pService | Happy path |
| | returns encryptionRequired when recipientMlKemPublicKey is null | Key guard |
| | returns nodeNotRunning when p2pService is not started | Node guard |
| | returns sendFailed when bridge encrypt returns ok=false | Encrypt failure |
| | returns sendFailed when p2pService returns false and inbox fails | Send + inbox failure |
| | stores invite in inbox when direct send fails | Inbox fallback |
| | invite payload includes full groupConfig with members array | Payload shape |
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
| | deduplicates by messageId when pubsub and group inbox deliver same message | Cross-path dedup |
| | duplicate replay enriches a missing quotedMessageId | Quote enrichment |
| | duplicate replay with the same messageId ignores a tampered timestamp | Replay tamper dedup |
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
| rejects when caller is not admin | Auth guard |
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
| dissolves a group, stores a timeline event, and leaves the topic | Happy path |
| returns unauthorized for non-admin users | Auth guard |
| returns alreadyDissolved when the group is already closed | Idempotency guard |
| returns bridgeError when inbox fallback fails but still marks the group dissolved | Partial failure |

### 4.14 updateGroupMetadata
**File:** `test/features/groups/application/update_group_metadata_use_case_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `updateGroupMetadata` | updates name, description, avatar metadata, and watermark | Happy path |
| | clears blank description and avatar fields explicitly | Blank field clearing |
| | rejects non-admin edits | Auth guard |
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
| | handles bridge group:join timeout without losing persisted data | Timeout data safety |

### 4.19 storePendingGroupInvite
**File:** `test/features/groups/application/store_pending_group_invite_use_case_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `storeIncomingPendingGroupInvite` | stores validated invite as pending without creating group state | Happy path |
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
| | returns expired and removes stale invite | Expiry guard |
| | returns duplicateGroup and removes pending row when group already exists | Duplicate guard |
| | accepting on one device does not clear the sibling device pending invite | Multi-device |

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
| | retryFailedGroupMessage only retries the requested failed media row | Targeted retry |

### 4.26 retryIncompleteGroupUploads
**File:** `test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `retryIncompleteGroupUploads` | returns 0 when no upload_pending attachments exist | Empty state |
| | reuploads only group upload_pending attachments and uses blobId | Upload retry |
| | reuploads only pending GIF attachments while preserving done JPEG siblings | GIF retry |
| | emits RETRY_INCOMPLETE_GROUP_UPLOADS_TIMING with attachment and message counts | Flow event |
| | transient failure increments retry count and terminal state at max | Retry exhaustion |
| | skips retry work when upload_pending attachments have no parent group message row | Orphan skip |
| | skips the final group send when the parent row is deleted after uploads complete | Deleted parent skip |

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
| | unauthorized group_metadata_updated is ignored | Auth guard |
| | members_added saves all members and calls updateConfig | Batch member-add |
| | member_joined saves a durable join timeline event | Durable join timeline |
| | unauthorized members_added is ignored | Auth guard |
| `member_removed system messages` | unauthorized member_removed is ignored | Auth guard |
| | replayed unauthorized member_removed is ignored | Replay auth guard |
| | handles key_rotated system message without error | Key rotation |
| | removal of other member does NOT call leaveGroup | Non-self removal |
| | member_role_updated changes role and calls updateConfig | Role update |
| | unauthorized member_role_updated is ignored | Auth guard |
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
| saves key on successful decrypt | Happy path |
| promotes key only after group:updateKey succeeds | Ordering |
| returns early when encrypted field is null | Null guard |
| returns early when own ML-KEM secret key is null | Missing key guard |
| returns early when decrypt fails (ok: false) | Decrypt failure |
| saves key to DB AND updates Go via group:updateKey | Dual persistence |
| does not crash on malformed JSON | Error resilience |
| group:updateKey payload contains correct groupId, groupKey, keyEpoch | Payload shape |
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
| | skips dissolved groups | Dissolved exclusion |

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
| rotated key is NOT distributed to removed member | Removed member exclusion |
| receiver processes key update and syncs Go validator | Key update receipt |
| first post-removal send uses the rotated epoch | Epoch advancement |

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
| `GroupConversationWired Section 3 background-task protection` | bg:begin happens before media upload and bg:end happens after publish and inbox store | Background task lifecycle | skip: true |
| | bg:end fires on media upload failure early return | Upload failure cleanup | skip: true |
| | bg:end fires when upload throws | Upload throw cleanup | skip: true |
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
| | announcement media send preserves messageId, key epoch, and media metadata through wired path | Announcement media metadata | skip: true |
| | order-recording bridge proves no early cleanup | Bridge ordering | skip: true |

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
| | admin metadata edit updates repo state, timeline, and bridge payloads | Metadata edit |
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
| | joined sibling device converges membership updates without duplicate local membership | Membership convergence |
| | mute, unread, and local notifications stay device-local across joined sibling devices | Device-local state |

### 6.7 Group Resume Recovery
**File:** `test/features/groups/integration/group_resume_recovery_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `Group resume recovery integration tests` | member backgrounded during send receives missed group messages after resume | Background resume |
| | same message is not duplicated if both pubsub and group inbox deliver it | Cross-path dedup |
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

### 6.9 Announcement Happy Path
**File:** `test/features/groups/integration/announcement_happy_path_test.dart`

| Test | What it covers |
|------|----------------|
| announcement happy path: create, admin send, reader read-only receive, member react | Full announcement lifecycle |
| announcement admin can send GIF media and reader receives image/gif read-only | GIF announcement |

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
- **Group DB migrations before 026**: No tests for the original groups/group_messages/group_members/group_keys table creation migrations.
- **Group message full-text search**: No tests for any search/query by content.

### 10.2 Application Layer
- **GroupMessageListener**: Has 56 tests (the largest single test file) covering system messages, notifications, reactions, and media forwarding. System message handler coverage includes member_added, member_removed, members_added, group_dissolved, member_role_updated, group_metadata_updated, and key_rotated.
- **Flow-event contract inventory**: No dedicated tests pin group-specific event family names or validate their structured payloads.
- **Concurrent key rotation during member removal**: Only tested through the member_removal_integration_test; no isolated concurrency stress test.

### 10.3 Presentation Layer
- **GroupConversationWired background task skipped tests**: `group_conversation_wired_bg_task_test.dart` exists with 15 tests, but 5 are marked `skip: true` (bg:begin/bg:end lifecycle, announcement media metadata, order-recording bridge). These represent untested background-task coverage holes.

### 10.4 Integration / E2E
- **True multi-device E2E**: Multi-device tests use in-memory fakes in the repo-owned suite. Earlier 2026-04-12 spare iOS proof remains in `/tmp/md004_group_multi_device_real_rerun8_20260412.log`, and the final 2026-04-12 deployed-relay rerun on the primary iOS pair is recorded in `/private/tmp/acceptance_20260412/group_multi_device_real_primary_ios.log`.
- **Push notification trigger path**: Group push routing is tested. Earlier 2026-04-12 spare iOS proof remains in `/tmp/ux009_notification_open_ui_smoke_20260412_rerun16e_drive.log`, and the final 2026-04-12 deployed-relay rerun on the primary iOS pair is recorded in `/private/tmp/acceptance_20260412/notification_open_ui_primary_ios.log`.
- **Network partition healing**: Tested via `temporary partition replays missed backlog` in resume recovery, but no dedicated partition-heal scenario like the intro feature's multi-simulator proof.

### 10.5 Security
- **Replay attack on group messages**: Now covered by `handle_incoming_group_message_use_case_test.dart` and `group_resume_recovery_test.dart`, which pin timestamp-tampered replay dedup plus remove/dissolve cutoff enforcement on the Flutter-visible receive path.
- **Tampered group message payload**: Now covered by `pubsub_decryption_failure_test.go`, which pins wrong-key, tampered-nonce, tampered-ciphertext, and malformed-payload rejection without any `group_message:received` event, and `go_bridge_client_test.dart`, which keeps the owned Flutter diagnostics route pinned.
- **Key rotation race conditions**: Now covered at the repo-owned convergence seam by `group_key_update_listener_test.dart`, which collapses same-generation conflicts to one stored key and keeps higher-epoch convergence explicit, while `send_group_message_use_case_test.dart` and `group_resume_recovery_test.dart` keep the winning epoch sendable.
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
**File:** `go-mknoon/node/pubsub_test.go` (72 tests)

Covers topic creation, validator logic, config updates, discovery, and publish operations:

| Category | Key Tests |
|----------|-----------|
| Topic & Config | TestGroupTopicName, TestGroupConfig_Serialization, TestGroupKeyInfo_Serialization, TestGroupMember_Serialization, TestGroupMember_OmitEmpty |
| Writer Authorization | TestIsAllowedWriter_ChatAnyMember, _AnnouncementAdminOnly, _AnnouncementMemberBlocked, _QAAnyMember, _NonMember |
| Member Lookup | TestFindMember_Found, _NotFound, _DuplicatePeerId_ReturnsFirst |
| Validator | TestGroupTopicValidator_ValidMessage, _InvalidJSON, _UnknownGroup, _UnauthorizedSender, _AnnouncementNonAdminRejected, _BadSignature, _SpoofedPublicKey, _NotV3Envelope, _WrongKeyEpoch, _EmptyMembersList, _ConcurrentValidation |
| Join / Leave | TestJoinGroupTopic_WithMultiMemberConfig, _ValidatorAcceptsAllListedMembers, _FailsWithoutPubSub, _RejectsDoubleJoin, TestLeaveGroupTopic_CancelsDiscoveryContext |
| Config Update | TestUpdateGroupConfig_ReplacesConfigAtomically, _NonExistentGroup, _PreservesDiscoveryLoop, _ConcurrentUpdates |
| Invite Lifecycle | TestInviteLifecycle_AdminAddsNewMember_ValidatorAcceptsNewMember, _AnnouncementGroup_NewWriterCannotPublish |
| Discovery | TestGroupRendezvousNamespace, _MatchesTopicName, _EmptyGroupId, TestFilterDiscoveredPeers_*, TestFilterDiscoveredGroupMembers_*, TestGroupDiscoveryInterval, _WarmInterval, TestGroupDiscoveryConcurrency, TestGroupRecoveryLimiter_*, TestGroupDiscoveryLoop_BacksOff*, _DedupesConcurrentPeerDials |
| Recovery | TestGroupRecovery_PreservesTopicStateAcrossInPlaceRefresh |
| Publish | TestPublishGroupMessage_BuildsCorrectEnvelope, TestBuildGroupMessageExtra_PreservesQuotedMessageId, TestBuildGroupMessageReceivedEvent_IncludesQuotedMessageId |
| Encrypt Round-Trip | TestGroupMessage_EncryptDecryptRoundTrip |
| Diagnostics | TestAnnouncementGroup_AdminPublishWithZeroPeersStillUsesDurableFallback, TestPublishGroupMessage_EmitsLiveFanoutDiagnosticWithoutFailingDurableSend |
| Peer Preference | TestGroupDiscovery_UsesDiscoveredAddressesBeforeRelayFallback, TestKnownGroupMemberDial_PrefersExistingOrDirectPathBeforeRelay |
| Key Lookup | TestGetGroupKeyInfo_ReturnsCurrentKey, _ReturnsNilForUnknownGroup |
| Node Lifecycle | TestStopNode_CancelsAllDiscoveryContexts, TestGroupDiscoveryCtx_InitializedByInitPubSub, TestCountConnectedGroupMembers_UnknownGroup |

### 12.4 PubSub Delivery
**File:** `go-mknoon/node/pubsub_delivery_test.go` (8 tests)

| Test | What it covers |
|------|----------------|
| TestPublishGroupMessage_ReturnsPeerCountZero_WhenNoPeers | Zero-peer count |
| TestPublishGroupMessage_ReturnsPeerCountPositive_WhenPeersConnected | Positive peer count |
| TestPublishGroupMessage_RefreshesMissingKnownTopicPeersBeforePublish | Peer refresh before publish |
| TestPublishGroupMessage_ReturnsErrorForUnjoinedGroup | Unjoined group error |
| TestGroupPeerDiscoveryLoop_DialsKnownMembersBeforeCircuitAddressWait | Pre-circuit member dial |
| TestGroupPeerDiscoveryLoop_DialsKnownMembersBeforeRelayReadyWhenDirectAddrsKnown | Direct address preference |
| TestGroupPeerDiscoveryLoop_RetriesMissingThirdPeerDuringWarmWindow | Warm window retry |
| TestGroupPeerDiscoveryLoop_UsesWarmRetryImmediatelyAfterPartialInitialRecovery | Warm retry timing |

### 12.5 Key Rotation Grace Period
**File:** `go-mknoon/node/pubsub_key_rotation_grace_test.go` (7 tests)

| Test | What it covers |
|------|----------------|
| TestGroupTopicValidator_AcceptsPreviousEpochDuringGrace | Old key during grace |
| TestGroupTopicValidator_RejectsPreviousEpochAfterGraceExpires | Old key after grace |
| TestGroupTopicValidator_AcceptsCurrentEpochDuringGrace | Current key during grace |
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
**File:** `go-mknoon/node/group_inbox_test.go` (8 tests)

| Test | What it covers |
|------|----------------|
| TestBuildGroupInboxStoreRequest_MarshalsRecipientPeerIds | Recipient list marshaling |
| TestBuildGroupInboxStoreRequest_MarshalsPushTitle | Push title |
| TestBuildGroupInboxStoreRequest_MarshalsPushBody | Push body |
| TestGroupInboxRetrieveCursor_DefaultsLimitWhenZero | Default limit |
| TestGroupInboxRetrieveCursor_StableAcrossPages | Cursor stability |
| TestGroupInboxRetrieveCursor_NoDuplicateOnContinuation | No duplicate on continue |
| TestGroupInboxRetrieveCursor_RequiresStartedNode | Node startup guard |
| TestGroupInboxRetrieveCursor_NegativeLimitDefaultsTo50 | Negative limit default |

### 12.8 Multi-Relay (group-relevant subset)
**File:** `go-mknoon/node/multi_relay_test.go` (3 of 22 tests)

| Test | What it covers |
|------|----------------|
| TestNewRelaySelector_GroupsByPeerID | Relay grouping |
| TestGroupInboxRetrieve_TriesSecondRelayWhenFirstFails | Inbox relay failover |
| TestGroupInboxRetrieveCursor_TriesSecondRelayWhenFirstFails | Cursor relay failover |

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
| TestRelayGroupMediaUploadDownload | Group media relay round-trip |
| TestRelayGroupMediaVoiceNote | Group voice note relay |

**File:** `go-mknoon/integration/relay_test.go` (1 of 20 tests)

| Test | What it covers |
|------|----------------|
| TestRelayRefreshPreservesJoinedGroupTopics | Topic preservation on refresh |
