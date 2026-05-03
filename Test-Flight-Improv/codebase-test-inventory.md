# Codebase Test Inventory by Feature

Generated 2026-05-02. Sweep of all `*_test.dart`, `integration_test/*.dart`, `*_test.go` across the repo.

## Summary
- Dart unit/widget tests (`test/**`): **683**
- Flutter integration tests/harnesses (`integration_test/**`): **78**
- Go (`go-mknoon/**`) tests: **80** (includes 27 vendored `third_party/go-libp2p-pubsub/*_test.go`)
- Go (`go-relay-server/**`) tests: **13**
- **Total**: **854**

## Feature index

App features (`test/features/<feature>/`):
- [contact_request](#contact_request) — 19 tests
- [contacts](#contacts) — 9 tests
- [conversation](#conversation) — 78 tests
- [feed](#feed) — 37 tests
- [groups](#groups) — 88 tests
- [home](#home) — 9 tests
- [identity](#identity) — 19 tests
- [introduction](#introduction) — 34 tests
- [orbit](#orbit) — 22 tests
- [p2p](#p2p) — 10 tests
- [posts](#posts) — 92 tests (multi-phase: improvement, phase1–phase5)
- [push](#push) — 16 tests
- [qr_code](#qr_code) — 7 tests
- [settings](#settings) — 17 tests
- [share](#share) — 6 tests
- [features-loose](#features-loose) — 1 test (top-level under `test/features/`)

Cross-cutting:
- [Core infrastructure](#core-infrastructure) — 175 tests (`test/core/**`)
- [Top-level integration](#top-level-integration) — 9 tests (`test/integration/**`)
- [Shared widgets / fixtures](#shared) — 9 tests (`test/shared/**`)
- [Performance & benchmarks](#performance) — 23 tests (`test/performance/**`)
- [Security](#security) — 1 test (`test/security/**`)
- [Unit (analyzer / path utils)](#unit-bucket) — 2 tests (`test/unit/**`)
- [Flutter on-device integration & harnesses](#flutter-integration) — 78 files (`integration_test/**`)
- [Go P2P node (`go-mknoon`)](#go-mknoon) — 80 tests
- [Go relay server (`go-relay-server`)](#go-relay-server) — 13 tests

---

<a id="contact_request"></a>
## contact_request
**Where it lives in the app**: `lib/features/contact_request/` (send/accept/decline + key exchange retries).
**Test count**: Dart unit 14 | Domain/integration 5 | Go 0

### Application use cases & listeners (`test/features/contact_request/application/`)
- `accept_and_reciprocate_use_case_test.dart` — Auto-accept + send reciprocal request happy path.
- `accept_contact_request_use_case_test.dart` — Manual accept of pending request, contact creation.
- `decline_contact_request_use_case_test.dart` — Decline removes from pending, no contact created.
- `send_contact_request_use_case_test.dart` — Outbound CR, signs/encrypts payload.
- `handle_incoming_message_use_case_test.dart` — Routes inbound CR to repo + listener.
- `contact_request_listener_test.dart` — Listener filters incoming CR messages on p2p stream.
- `contact_request_notification_materializer_test.dart` — Translates CRs into local notifications.
- `resolve_contact_request_notification_target_use_case_test.dart` — Resolves a CR notification tap to its target route/screen.
- `key_exchange_retrier_test.dart` — Retrier loop for incomplete ML-KEM key exchanges.
- `key_exchange_retry_coordinator_test.dart` — Coordinator that schedules retries.
- `key_exchange_retry_smoke_test.dart` — Smoke roundtrip of retry path.
- `recover_intro_contact_request_use_case_test.dart` — Recovers CRs that arrived via introduction flow.
- `retry_incomplete_key_exchanges_use_case_test.dart` — Sweeps DB for incomplete exchanges and retries them.

### Domain models & repository
- `domain/models/contact_request_model_test.dart` — model toMap/fromMap, JSON.
- `domain/repositories/contact_request_repository_impl_test.dart` — CRUD + state transitions on DB helpers.

### Integration (`test/features/contact_request/integration/`)
- `contact_request_flow_test.dart` — End-to-end CR happy path with fake p2p service.
- `key_exchange_retry_flow_test.dart` — Multi-step ML-KEM retry/recovery flow.

### Presentation widgets
- `contact_request_dialog_test.dart` — Accept/decline dialog widget.
- `pending_requests_badge_test.dart` — Badge count widget.

### Notes
- Solid coverage for both happy paths and key-exchange edge cases.

---

<a id="contacts"></a>
## contacts
**Where it lives in the app**: `lib/features/contacts/` (post-CR contact lifecycle).
**Test count**: Dart unit 9 | Integration 0 | Go 0

### Application
- `add_contact_use_case_test.dart` — Insert new contact (typically from accepted CR).
- `delete_contact_use_case_test.dart` — Hard delete contact.
- `archive_contact_use_case_test.dart` / `unarchive_contact_use_case_test.dart` — Toggle archived state.
- `block_contact_use_case_test.dart` / `unblock_contact_use_case_test.dart` — Toggle blocked state.

### Domain
- `domain/models/contact_model_test.dart` — model serialization.
- `domain/models/contact_safety_number_test.dart` — Safety-number derivation.
- `domain/repositories/contact_repository_impl_test.dart` — Contact repo impl over DB helpers.

### Notes
- No dedicated integration or presentation tests; UI is exercised via orbit/feed widget tests.

---

<a id="conversation"></a>
## conversation
**Where it lives in the app**: `lib/features/conversation/` (1:1 letter-card chat, media, voice, reactions).
**Test count**: Dart unit/widget 78 | Integration 11 | Go 0 (handled by go-mknoon node tests)

### Application — send/receive pipeline (`test/features/conversation/application/`)
- `send_chat_message_use_case_test.dart` / `send_chat_message_no_bg_task_test.dart` — Outbound encryption, persistence, ack handling; no-background-task variant.
- `send_voice_message_use_case_test.dart` / `send_voice_message_no_bg_task_test.dart` — Voice send pipeline with audio attachment.
- `send_reaction_use_case_test.dart` — Outbound emoji reaction.
- `delete_message_use_case_test.dart` — Local + remote tombstone.
- `remove_reaction_use_case_test.dart` — Toggle off.
- `chat_message_listener_test.dart` — p2p messageStream filter for chat envelopes.
- `reaction_listener_test.dart` / `message_deletion_listener_test.dart` — Listeners for reactions/deletions.
- `handle_incoming_chat_message_use_case_test.dart` — Decrypt v2 / parse v1, persist, broadcast.
- `handle_incoming_chat_message_media_hydration_test.dart` — Hydrates media attachment metadata on inbound msg.
- `handle_incoming_message_deletion_use_case_test.dart` — Apply remote tombstone.
- `handle_incoming_reaction_use_case_test.dart` — Apply remote reaction.
- `load_conversation_use_case_test.dart` / `load_reactions_use_case_test.dart` — Read paths.
- `mark_conversation_read_use_case_test.dart` — read_at bookkeeping.
- `outbound_envelope_policy_test.dart` — Enforces v1/v2 envelope choice based on contact ML-KEM key.
- `stable_id_contract_test.dart` — Stable-id invariants for media messages.
- `optimistic_upload_persistence_test.dart` — Optimistic UI rows persist across restart.
- `durable_storage_recovery_test.dart` — Storage durability after crash/reopen.
- `voice_local_wifi_recovery_test.dart` — Voice resume over local-wifi transport.

### Application — retries / recovery
- `recover_stuck_sending_messages_use_case_test.dart` — Re-arms messages stuck in SENDING.
- `retry_failed_messages_use_case_test.dart` — Retries FAILED messages.
- `retry_failed_messages_media_test.dart` / `retry_failed_messages_media_reupload_test.dart` — Media-aware retries (re-upload path).
- `retry_incomplete_uploads_use_case_test.dart` — Resumes incomplete media uploads on resume.
- `retry_unacked_messages_use_case_test.dart` / `retry_unacked_messages_null_guard_test.dart` — Inbox ack retry; null-guard regression.

### Application — media
- `download_media_use_case_test.dart` — Download with key/nonce, integrity check.
- `upload_media_use_case_test.dart` — Encrypted upload to relay.

### Domain models (`test/features/conversation/domain/models/`)
- `conversation_message_test.dart` — Core message model.
- `audio_recording_test.dart` — Audio recording model.
- `media_attachment_test.dart` — Media attachment model.
- `message_payload_test.dart` / `reaction_payload_test.dart` / `message_deletion_payload_test.dart` — Wire payload models.
- `message_reaction_test.dart` — Reaction model.

### Domain repositories
- `message_repository_impl_test.dart` — Message CRUD + queries.
- `message_repository_impl_stuck_sending_test.dart` / `fake_message_repository_stuck_sending_query_test.dart` — Stuck-sending query semantics.
- `media_attachment_repository_impl_test.dart` / `media_attachment_repository_upload_pending_test.dart` — Media repo + pending upload state.
- `reaction_repository_impl_test.dart` — Reactions repo.

### Integration (`test/features/conversation/integration/`)
- `two_user_message_exchange_test.dart` — Roundtrip baseline.
- `voice_message_exchange_test.dart` — Voice e2e through fake p2p.
- `emoji_reaction_exchange_test.dart` — Reaction roundtrip.
- `media_attachment_flow_test.dart` / `media_retry_smoke_test.dart` — Media full flow + retry.
- `incomplete_upload_recovery_test.dart` — Recovery from interrupted upload.
- `message_deletion_roundtrip_test.dart` — Tombstone roundtrip.
- `offline_inbox_roundtrip_test.dart` — Store-and-forward via relay inbox.
- `quote_reply_thread_test.dart` — Quote-reply threading.
- `send_then_lock_delivery_test.dart` — Lifecycle: send → lock → delivery.
- `stuck_sending_recovery_test.dart` — Recovery from SENDING state.

### Presentation — screens
- `conversation_screen_test.dart` — Pure screen render.
- `conversation_wired_test.dart` — Wired widget happy path.
- `conversation_wired_bg_task_test.dart` — Background-task isolation.
- `conversation_wired_gif_test.dart` — GIF send/render path.
- `conversation_wired_sending_to_failed_test.dart` — State transition rendering.
- `conversation_audio_source_regression_test.dart` — Audio-source regression guard.
- `conversation_banner_test.dart` / `conversation_overflow_intro_test.dart` — Header/banner states.

### Presentation — widgets
- `letter_card_test.dart` — Core message bubble.
- `compose_area_test.dart` / `attachment_preview_strip_test.dart` — Composer.
- `voice_record_button_test.dart` / `recording_overlay_test.dart` / `amplitude_bars_test.dart` — Voice recording UI.
- `reaction_bar_test.dart` / `reaction_display_test.dart` / `full_emoji_picker_test.dart` — Reactions UI.
- `message_context_overlay_test.dart` — Long-press context.
- `compact_origin_marker_test.dart` / `empty_conversation_state_test.dart` / `date_separator_test.dart` / `conversation_header_test.dart` / `blocked_banner_test.dart` — Misc states/widgets.

### Notes
- Largest application-layer test surface in the app after `groups` and `posts`.

---

<a id="feed"></a>
## feed
**Where it lives in the app**: `lib/features/feed/` (incoming-only feed; cards split into connection vs message).
**Test count**: Dart unit/widget 37 | Integration 3 | Go 0

### Application
- `feed_projection_test.dart` — Pure projection of repo data into FeedItems.
- `feed_store_test.dart` / `feed_reaction_store_test.dart` — In-memory store + reaction join.
- `load_feed_use_case_test.dart` — Load feed from repos.

### Domain models & utils
- `domain/models/feed_item_test.dart` — Abstract base + concrete subclasses.
- `domain/models/session_reply_test.dart` — Session reply model.
- `domain/utils/format_message_time_test.dart` — Time formatter.
- `domain/utils/group_messages_into_threads_test.dart` / `group_group_messages_into_threads_test.dart` — Threading algorithm (1:1 + group variants).
- `domain/utils/has_significant_time_gap_test.dart` / `split_thread_by_time_gap_test.dart` — Time gap heuristics.

### Integration
- `feed_card_flow_test.dart` — End-to-end card render flow.
- `feed_color_smoke_test.dart` — Color theming smoke.
- `expanded_collapsed_card_test.dart` — Card expand/collapse.

### Presentation — screens
- `feed_screen_test.dart` / `feed_wired_test.dart` / `feed_wired_bg_task_test.dart` — Screen + wired + background-task variants.

### Presentation — widgets
- `feed_card_test.dart` / `connection_card_test.dart` / `introduction_connection_card_test.dart` — Card variants.
- `collapsed_mode_card_body_test.dart` / `open_mode_card_body_test.dart` — Card body states.
- `expanded_compose_input_test.dart` / `inline_reply_input_test.dart` / `quote_preview_bar_test.dart` — Inline composer.
- `swipe_to_quote_bubble_test.dart` — Swipe-to-quote gesture.
- `feed_navigation_bar_test.dart` / `nav_bar_button_test.dart` — Bottom nav.
- `message_bubble_test.dart` / `replied_indicator_test.dart` / `more_messages_hint_test.dart` / `view_earlier_link_test.dart` / `scrollable_message_preview_test.dart` — Message list elements.
- `session_divider_test.dart` / `time_gap_divider_test.dart` — Dividers.
- `unread_count_badge_test.dart` / `checkmark_burst_animation_test.dart` — Status indicators.

### Notes
- Heavy widget coverage; threading utils have separate per-rule tests.

---

<a id="groups"></a>
## groups
**Where it lives in the app**: `lib/features/groups/` (private libp2p group chat — biggest feature).
**Test count**: Dart unit/widget 88 | Integration 12 | Go (group-relevant) ≈14 across `go-mknoon/node` & `internal`

### Application — lifecycle (`test/features/groups/application/`)
- `create_group_use_case_test.dart` / `create_group_with_members_use_case_test.dart` — Group creation paths.
- `join_group_use_case_test.dart` / `leave_group_use_case_test.dart` — Membership transitions.
- `archive_group_use_case_test.dart` / `unarchive_group_use_case_test.dart` — Archive toggle.
- `dissolve_group_use_case_test.dart` — Owner dissolves group.
- `delete_group_and_messages_use_case_test.dart` — Local purge.
- `update_group_metadata_use_case_test.dart` — Name/avatar metadata propagation.
- `set_group_muted_use_case_test.dart` — Mute preference.
- `group_avatar_storage_test.dart` — Encrypted avatar blob storage.

### Application — invites
- `send_group_invite_use_case_test.dart` / `revoke_pending_group_invite_use_case_test.dart` — Outbound invite + revocation.
- `accept_pending_group_invite_use_case_test.dart` / `decline_pending_group_invite_use_case_test.dart` — Inbound choice.
- `store_pending_group_invite_use_case_test.dart` — Persist pending state.
- `handle_incoming_group_invite_use_case_test.dart` — Inbound invite processing.
- `group_invite_listener_test.dart` — Stream filter for invite envelopes.

### Application — membership management
- `add_group_member_use_case_test.dart` / `remove_group_member_use_case_test.dart` — Roster mutations (admin only).
- `update_group_member_role_use_case_test.dart` — Role change.
- `member_removal_integration_test.dart` — End-to-end member removal flow.

### Application — messaging & reactions
- `send_group_message_use_case_test.dart` — Outbound v3 envelope publish.
- `send_group_reaction_use_case_test.dart` / `remove_group_reaction_use_case_test.dart` — Group reactions.
- `group_message_listener_test.dart` — Inbound msg listener.
- `handle_incoming_group_message_use_case_test.dart` / `handle_incoming_group_reaction_use_case_test.dart` — Inbound processing.
- `group_offline_replay_envelope_test.dart` — Offline-replay envelope semantics.

### Application — keys
- `rotate_group_key_use_case_test.dart` / `rotate_and_distribute_group_key_use_case_test.dart` — Key rotation paths.
- `group_key_update_listener_test.dart` — Key-update listener.

### Application — recovery / retries
- `drain_group_offline_inbox_use_case_test.dart` — Drains relay inbox on resume.
- `recover_stuck_sending_group_messages_use_case_test.dart` — Stuck-sending recovery for groups.
- `rejoin_group_topics_use_case_test.dart` — App-restart re-subscribe loop.
- `retry_failed_group_messages_use_case_test.dart` / `retry_failed_group_inbox_stores_use_case_test.dart` / `retry_incomplete_group_uploads_use_case_test.dart` — Retry sweep variants.

### Domain models (`test/features/groups/domain/models/`)
- `group_model_test.dart` / `group_member_test.dart` — Core models.
- `group_message_test.dart` / `group_message_payload_test.dart` — Message + wire payload.
- `group_reaction_payload_test.dart` — Reaction wire payload.
- `group_invite_payload_test.dart` / `group_invite_revocation_payload_test.dart` / `pending_group_invite_test.dart` — Invite models.
- `group_welcome_key_package_test.dart` / `group_key_info_test.dart` — Welcome packet + key state.
- `group_backlog_retention_policy_test.dart` / `group_membership_limit_policy_test.dart` / `group_multi_device_policy_test.dart` — Policy models.

### Domain repositories
- `group_repository_impl_test.dart` — Group/member/key repo.
- `group_message_repository_impl_test.dart` — Group messages repo.
- `pending_group_invite_repository_impl_test.dart` — Pending invites repo.
- `group_pending_key_repair_repository_impl_test.dart` — Pending key-repair repo.

### Integration (`test/features/groups/integration/`)
- `group_messaging_smoke_test.dart` — End-to-end roundtrip.
- `group_membership_smoke_test.dart` — Add/remove member smoke.
- `group_edge_cases_smoke_test.dart` — Edge-case bundle.
- `group_media_fanout_test.dart` — Media fanout to N members.
- `group_multi_device_convergence_test.dart` — Multi-device state convergence.
- `group_new_member_onboarding_test.dart` — Welcome packet flow for new members.
- `group_reaction_roundtrip_test.dart` — Reaction roundtrip.
- `group_resume_recovery_test.dart` — Backgrounded → resumed delivery.
- `group_startup_rejoin_smoke_test.dart` — Startup re-subscribe.
- `invite_round_trip_test.dart` — Invite full cycle.
- `announcement_happy_path_test.dart` / `announcement_new_reader_onboarding_test.dart` — Announcement-group variant flows.

### Presentation — screens
- `group_list_screen_test.dart` / `group_list_wired_test.dart` / `group_list_screen_bidi_test.dart` — Group list (RTL/LTR).
- `group_conversation_screen_test.dart` / `group_conversation_wired_test.dart` / `screens/group_conversation_wired_bg_task_test.dart` — Group chat screen.
- `group_info_screen_test.dart` / `group_info_wired_test.dart` — Group info/details.
- `contact_picker_screen_test.dart` / `contact_picker_wired_test.dart` / `contact_picker_multi_select_integration_test.dart` — Picker for adding members.
- `create_group_picker_screen_test.dart` / `create_group_picker_wired_test.dart` — Create-group picker.

### Presentation — widgets
- `group_card_test.dart` / `group_card_bidi_test.dart` — Group list card.
- `group_type_badge_test.dart` — Type badge.
- `widgets/contact_picker_row_test.dart` — Picker row.
- `widgets/expandable_fab_test.dart` / `widgets/glow_fab_test.dart` — Compose FABs.
- `widgets/group_name_panel_test.dart` — Name panel.
- `widgets/group_reaction_details_sheet_test.dart` — Reaction details sheet.

### Notes
- Single largest feature area. Many recent additions track the trusted-private-libp2p group chat hardening; see `Test-Flight-Improv/Group-Chat-Feature/` for ongoing coverage tracking.

---

<a id="home"></a>
## home
**Where it lives in the app**: `lib/features/home/` (post-FTE landing surface).
**Test count**: Dart unit/widget 9 | Integration 0 | Go 0

### Application
- `identity_avatar_resolver_test.dart` — Resolves avatar bytes for current identity.

### Presentation — screens
- `first_time_experience_screen_test.dart` / `first_time_experience_wired_test.dart` — FTE screen + wired.

### Presentation — widgets
- `editable_username_widget_test.dart` — Username editor.
- `profile_avatar_widget_test.dart` / `user_avatar_test.dart` — Avatar render variants.
- `qr_code_section_test.dart` — Embedded QR section.
- `scan_friend_card_test.dart` — Scan-friend CTA card.
- `empty_circle_state_test.dart` — Empty state.

### Notes
- Coverage is widget-only; no dedicated home integration suite.

---

<a id="identity"></a>
## identity
**Where it lives in the app**: `lib/features/identity/` (generate, restore, secrets storage, startup routing).
**Test count**: Dart unit/widget 19 | Integration 0 | Go (`go-mknoon/identity`) 1

### Application
- `generate_identity_use_case_test.dart` — Generates Ed25519 + ML-KEM + mnemonic, persists.
- `restore_identity_use_case_test.dart` — Restore from mnemonic.
- `recover_identity_from_secure_store_use_case_test.dart` — Recovery path from secure storage.
- `startup_decision_test.dart` — Decides FTE vs Home vs Recovery.

### Domain
- `domain/models/identity_model_test.dart` — Model.
- `domain/repositories/identity_repository_impl_test.dart` — Repo (secure-storage-aware).

### Presentation — navigation
- `presentation/navigation/startup_route_transition_test.dart` — Route transition logic.

### Presentation — screens
- `identity_choice_screen_test.dart` / `identity_choice_wired_test.dart` — Choice screen.
- `identity_progress_screen_test.dart` — Progress UI during identity generation.
- `mnemonic_input_screen_test.dart` — Restore mnemonic input.
- `startup_router_test.dart` / `startup_router_recovery_test.dart` / `startup_router_notification_open_test.dart` — Top-level startup router flows.

### Presentation — widgets
- `ambient_background_test.dart` / `brand_header_test.dart` / `choice_card_test.dart` / `identity_loading_card_test.dart` / `startup_loading_gate_test.dart` — UI bits.

### Go (`go-mknoon/identity/`)
- `identity_test.go` — libp2p identity generation/marshal roundtrip.

### Notes
- Solid coverage; key generation also exercised via `go-mknoon/crypto` tests.

---

<a id="introduction"></a>
## introduction
**Where it lives in the app**: `lib/features/introduction/` (intro/friends flow — introduce two contacts).
**Test count**: Dart unit/widget 34 | Integration 3 | Regression 1 | Go 0

### Application
- `send_introduction_test.dart` / `pass_introduction_test.dart` — Outbound send / forwarding.
- `accept_introduction_test.dart` — Accept incoming intro.
- `handle_incoming_introduction_test.dart` — Inbound processing.
- `introduction_listener_test.dart` — p2p stream listener.
- `introduction_outbound_delivery_test.dart` — Outbound delivery semantics.
- `introduction_payload_test.dart` / `introduction_payload_extended_test.dart` — Wire payload variants.
- `mutual_acceptance_test.dart` / `create_connection_on_mutual_acceptance_test.dart` — Mutual accept → contact create.
- `check_intro_banner_test.dart` / `check_intro_banner_extended_test.dart` / `dismiss_banner_test.dart` — Banner state.
- `expire_old_introductions_use_case_test.dart` — Expiry sweep.
- `load_introductions_test.dart` — Read.
- `resolve_unknown_inbox_sender_use_case_test.dart` — Resolves an inbox sender as an unknown intro source.
- `edge_cases_test.dart` — Edge-case bundle.
- `introduction_copy_test.dart` — Copy/i18n.

### Domain
- `domain/models/introduction_model_test.dart` — Model.
- `domain/repositories/introduction_repository_impl_test.dart` — Repo.

### Integration
- `intro_wiring_smoke_test.dart` — DI wiring smoke.
- `introduction_smoke_test.dart` — Single-node smoke.
- `introduction_multi_node_test.dart` — Multi-node end-to-end.

### Presentation — screens
- `friend_picker_test.dart` / `friend_picker_wired_test.dart` — Pick a friend to introduce.
- `sent_confirmation_test.dart` / `sent_confirmation_wired_test.dart` — Sent confirmation.

### Presentation — widgets
- `intro_banner_test.dart` — Top banner.
- `intro_group_header_test.dart` / `intro_row_test.dart` — List items.
- `intro_system_message_test.dart` — System message bubble.
- `intros_tab_test.dart` / `intros_tab_extended_test.dart` — Tab containers.

### Regression
- `regression/introduction_regression_test.dart` — Regression-bucket guards.

### Notes
- Sizable feature with both broad and edge-case coverage.

---

<a id="orbit"></a>
## orbit
**Where it lives in the app**: `lib/features/orbit/` (friends/groups orbital visualization).
**Test count**: Dart unit/widget 22 | Integration 0 | Go 0

### Application
- `load_orbit_data_use_case_test.dart` — Loads friends + intros + active threads.
- `load_orbit_groups_use_case_test.dart` — Loads groups for orbit list.

### Domain
- `domain/models/orbit_friend_test.dart` — Friend orbit model.

### Presentation — screens
- `orbit_screen_loading_test.dart` / `orbit_wired_test.dart` — Loading / wired states.
- `orbit_screen_archived_groups_test.dart` — Archived-groups screen branch.
- `orbit_intros_wiring_test.dart` — Intros card wiring on orbit.

### Presentation — widgets
- `orbital_visualization_test.dart` / `orbital_avatar_test.dart` — Core visualization.
- `friend_row_test.dart` / `group_row_bidi_test.dart` — Row variants.
- `swipeable_friend_row_test.dart` / `swipeable_group_row_test.dart` / `swipe_action_buttons_test.dart` — Swipe interactions.
- `friends_filter_toggle_test.dart` / `overflow_badge_test.dart` — Filter toggle + overflow.
- `archived_empty_state_test.dart` — Empty state.
- `confirmation_dialog_test.dart` — Action confirmation.
- `qr_action_cards_test.dart` / `orbit_search_dock_test.dart` / `orbit_search_trigger_test.dart` / `orbit_close_button_test.dart` — Top-level orbit chrome.

### Notes
- Visualization tested in isolation; integration covered transitively via top-level smoke tests.

---

<a id="p2p"></a>
## p2p
**Where it lives in the app**: `lib/features/p2p/` (Dart-side wrappers; transport lives in Go).
**Test count**: Dart unit/widget 10 | Integration 0 | Go = entire `go-mknoon/`

### Application
- `start_node_use_case_test.dart` / `stop_node_use_case_test.dart` — Bridge `node:start` / `node:stop` lifecycle.
- `discover_peer_use_case_test.dart` — Peer discovery wrapper.
- `send_message_use_case_test.dart` — Send wrapper.

### Domain models
- `chat_message_test.dart` — Inbound/outbound model.
- `connection_state_test.dart` / `node_state_test.dart` — State machines.
- `discovered_peer_test.dart` — Peer discovery model.
- `send_message_result_test.dart` — Result/Error model.

### Presentation
- `presentation/widgets/connection_status_indicator_test.dart` — Status indicator widget.

### Notes
- Almost all p2p logic is in the Go layer (see `go-mknoon` and `go-relay-server` sections); Dart wrappers are thin.

---

<a id="posts"></a>
## posts
**Where it lives in the app**: `lib/features/posts/` (multi-phase rollout: core / engagement / nearby / pass-along / pins / improvement).
**Test count**: Dart unit/widget 92 | Integration 5 (`integration_test/posts_phase{1..5}_fake_test.dart`) | Go 0

### Phase 1 — core posts (`test/features/posts/phase1/`)
- `app_shell_controller_test.dart` — Tab/route controller.
- `compose_post_sheet_test.dart` / `compose_post_sheet_bidi_test.dart` — Compose sheet (LTR/RTL).
- `posts_screen_test.dart` / `posts_wired_test.dart` — Posts feed screen + wired.
- `posts_core_repository_test.dart` — Core posts repo.
- `send_post_use_case_test.dart` — Outbound post.
- `handle_incoming_post_use_case_test.dart` — Inbound processing.
- `post_listener_test.dart` — Stream listener.
- `load_posts_feed_use_case_test.dart` — Read.
- `post_notification_open_flow_test.dart` / `post_push_wake_test.dart` — Push wake / open flow.

### Phase 2 — engagement (`test/features/posts/phase2/`)
- `compose_post_sheet_media_test.dart` / `attach_post_media_use_case_test.dart` — Media attach to post.
- `send_post_media_use_case_test.dart` / `handle_incoming_post_media_test.dart` / `load_posts_feed_media_test.dart` — Media send/receive/load.
- `send_post_comment_use_case_test.dart` / `handle_incoming_post_comment_use_case_test.dart` / `load_post_comments_use_case_test.dart` / `post_comment_listener_test.dart` — Comments.
- `send_post_reaction_use_case_test.dart` / `handle_incoming_post_reaction_use_case_test.dart` / `post_reaction_listener_test.dart` — Reactions.
- `posts_engagement_repository_test.dart` — Engagement repo.
- `comments_sheet_test.dart` / `comments_sheet_bidi_test.dart` / `comments_sheet_engagement_test.dart` — Comments UI.
- `post_card_test.dart` (alias of `post_card_bidi_test.dart`) / `post_card_engagement_test.dart` / `post_card_media_test.dart` — Card variants.
- `posts_wired_comments_test.dart` — Wired w/ comments.
- `load_posts_feed_engagement_test.dart` / `load_posts_feed_viewer_metrics_query_test.dart` — Engagement queries.
- `sweep_expired_posts_use_case_test.dart` — Sweeper.

### Phase 3 — nearby (`test/features/posts/phase3/`)
- `nearby_eligibility_service_test.dart` / `nearby_location_service_test.dart` — Eligibility + location.
- `publish_post_presence_update_use_case_test.dart` / `handle_incoming_post_presence_use_case_test.dart` / `post_presence_listener_test.dart` — Presence.
- `contact_presence_snapshot_repository_test.dart` — Presence snapshot repo.
- `posts_privacy_settings_repository_test.dart` — Privacy settings.
- `load_posts_feed_nearby_test.dart` / `send_post_nearby_test.dart` / `posts_wired_nearby_compose_test.dart` — Nearby read/send/compose.
- `post_card_nearby_distance_test.dart` — Distance widget.
- `refresh_nearby_on_startup_use_case_test.dart` / `handle_app_resumed_nearby_test.dart` / `startup_router_nearby_wiring_test.dart` — Nearby lifecycle wiring.

### Phase 4 — pass-along (`test/features/posts/phase4/`)
- `pass_post_along_use_case_test.dart` / `handle_incoming_passed_post_use_case_test.dart` — Pass-along send/receive.
- `posts_pass_repository_test.dart` — Pass repo.
- `post_pass_envelope_test.dart` — Wire envelope.
- `post_card_pass_action_test.dart` / `post_card_passed_along_test.dart` / `posts_wired_pass_along_test.dart` / `posts_wired_share_count_test.dart` — UI.

### Phase 5 — pins (`test/features/posts/phase5/`)
- `pin_post_use_case_test.dart` / `handle_incoming_post_pins_use_case_test.dart` / `load_pinned_posts_use_case_test.dart` — Pin lifecycle.
- `posts_pins_repository_test.dart` — Pins repo.
- `compose_post_sheet_pins_test.dart` / `edit_pinned_post_sheet_bidi_test.dart` / `pinned_posts_section_chrome_test.dart` / `posts_wired_pinned_section_test.dart` / `posts_wired_sender_pin_action_test.dart` — Pins UI.

### Improvement (`test/features/posts/improvement/`) — 26 tests
- `create_local_post_use_case_test.dart` — Local-first creation.
- `post_delivery_runner_test.dart` / `post_delivery_runner_parallel_test.dart` — Delivery runner serial + parallel.
- `post_delivery_retry_integration_test.dart` / `post_pass_retry_integration_test.dart` / `post_follow_on_retry_integration_test.dart` / `post_pin_retry_integration_test.dart` — Retry integrations.
- `post_engagement_fanout_test.dart` — Engagement fanout.
- `post_follow_on_delivery_test.dart` / `post_follow_on_outbox_repository_test.dart` — Follow-on outbox.
- `post_media_restart_recovery_test.dart` / `post_media_upload_recovery_repository_test.dart` — Media recovery.
- `post_pass_direct_merge_integration_test.dart` / `post_pass_encrypted_delivery_integration_test.dart` / `post_pass_encrypted_media_integration_test.dart` / `post_pass_engagement_baseline_integration_test.dart` / `post_pass_media_avatar_smoke_test.dart` / `post_pass_shared_thread_integration_test.dart` — Pass-along delivery suite.
- `post_pin_delivery_support_test.dart` / `post_pin_remove_delivery_integration_test.dart` — Pin delivery.
- `post_repost_visual_metrics_test.dart` / `post_repost_visual_refresh_test.dart` / `post_repost_visual_state_widget_test.dart` — Repost visual state.
- `posts_wired_optimistic_send_test.dart` — Optimistic UI.
- `send_post_facade_test.dart` / `send_post_media_background_test.dart` — Send facade + background-isolation send.

### Notes
- Largest single feature by file count. Posts are organized by rollout phase, not by clean architecture layer — so application/domain/presentation are interleaved within each phase folder.

---

<a id="push"></a>
## push
**Where it lives in the app**: `lib/features/push/` (FCM/APNs integration + local notifications).
**Test count**: Dart unit/widget 16 | Integration 0 | Go 0

### Application
- `register_push_token_use_case_test.dart` / `request_push_permission_use_case_test.dart` — Permission + token.
- `push_registration_coordinator_test.dart` — Coordinator that ties permission + token + registration.
- `handle_foreground_remote_message_use_case_test.dart` / `handle_initial_remote_message_use_case_test.dart` / `background_message_handler_test.dart` — Foreground / cold / background handlers.
- `prepare_notification_open_use_case_test.dart` — Pre-open hooks.
- `show_notification_use_case_test.dart` / `notification_body_for_message_test.dart` — Notification body composition.
- `push_decrypt_preview_test.dart` / `push_preview_telemetry_gate_test.dart` — Decrypted preview + telemetry gate.
- `chat_and_group_push_open_flow_test.dart` — Open flow for chat + group pushes.
- `intro_notification_orbit_route_test.dart` — Intro push routes to orbit.
- `resolve_group_notification_route_target_use_case_test.dart` — Resolves group notification route.
- `background_push_notification_fallback_test.dart` — Fallback when push payload incomplete.
- `ios_push_project_config_test.dart` — Static iOS config sanity.

### Notes
- All tests live in `application/`; presentation surface is exercised via core notifications tests.

---

<a id="qr_code"></a>
## qr_code
**Where it lives in the app**: `lib/features/qr_code/` (display + scan).
**Test count**: Dart unit/widget 7 | Integration 0 | Go 0

### Application
- `build_qr_payload_use_case_test.dart` — Build payload for display.
- `parse_qr_payload_use_case_test.dart` — Parse scanned payload.
- `handle_scanned_qr_use_case_test.dart` — Dispatches scanned payload (CR vs intro vs unknown).

### Domain
- `qr_payload_model_test.dart` — Payload model.

### Presentation
- `qr_display_wired_test.dart` / `qr_scanner_wired_test.dart` — Wired screens.
- `widgets/scan_overlay_test.dart` — Scan overlay UI.

### Notes
- Coverage is thin but proportional to feature surface.

---

<a id="settings"></a>
## settings
**Where it lives in the app**: `lib/features/settings/` (profile, image quality, video quality, background, posts/nearby).
**Test count**: Dart unit/widget 17 | Integration 1 | Go 0

### Application
- `image_quality_preference_use_cases_test.dart` / `video_quality_preference_use_cases_test.dart` / `background_preference_use_cases_test.dart` — Preference get/set.
- `upload_profile_picture_use_case_test.dart` / `download_profile_picture_use_case_test.dart` — Profile picture.
- `profile_update_listener_test.dart` — Listens for inbound profile updates.

### Domain
- `image_quality_preference_test.dart` — Enum/model.

### Integration
- `profile_picture_flow_test.dart` — End-to-end profile picture exchange.

### Presentation — screens
- `settings_screen_test.dart` / `settings_wired_test.dart` / `settings_wired_posts_nearby_test.dart` — Screens (with nearby variant).

### Presentation — widgets
- `image_quality_toggle_test.dart` / `background_choice_control_test.dart` / `posts_nearby_settings_card_test.dart` — Pref widgets.
- `settings_peer_id_card_test.dart` / `settings_recovery_phrase_card_test.dart` / `settings_profile_section_test.dart` — Identity surfacing.

---

<a id="share"></a>
## share
**Where it lives in the app**: `lib/features/share/` (OS share-sheet entry).
**Test count**: Dart unit/widget 6 | Integration 1 | Go 0

### Application
- `handle_share_intent_use_case_test.dart` — Routes incoming share intent.
- `settle_share_intent_flow_test.dart` — Post-share settle flow.
- `share_batch_delivery_coordinator_test.dart` — Batch delivery to multiple targets.

### Integration
- `share_to_contact_smoke_test.dart` — Smoke through to a contact target.

### Presentation
- `share_target_picker_screen_test.dart` / `share_target_picker_wired_test.dart` — Target picker.

### Notes
- iOS/Android intent platform code is tested under `test/core/services/share_intent_*`.

---

<a id="features-loose"></a>
## features-loose (top-level under `test/features/`)
- `loading_states_smoke_test.dart` — Generic loading-state smoke shared across features.

---

<a id="core-infrastructure"></a>
## Core infrastructure (`test/core/**`) — 175 tests
**Where it lives in the app**: `lib/core/**` (bridge, database, lifecycle, media, notifications, services, etc.).

### Bridge (`test/core/bridge/`) — 6
- `go_bridge_client_test.dart` — `GoBridgeClient` MethodChannel/EventChannel impl.
- `go_bridge_background_task_test.dart` — Background-task isolate variant.
- `bridge_helpers_test.dart` — `callSignPayload` etc. helpers.
- `bridge_group_helpers_test.dart` — Group-specific bridge helpers.
- `bridge_contact_request_crypto_test.dart` — CR-related crypto bridging.
- `p2p_bridge_client_test.dart` — Lower-level p2p bridge client.

### Constants (`test/core/constants/`) — 1
- `network_constants_test.dart` — Network constant invariants.

### Database (`test/core/database/`) — 88
- `encrypted_db_opener_test.dart` — Plaintext→encrypted migration / opener.
- `helpers/*_test.dart` (27 files) — Per-table DB helpers (identity, contacts, contact_requests, messages, groups, group_*, media_attachments, reactions, intros, posts, post_passes, post_recipients, post_repost_state, post_schema_capabilities, inbox_staging, etc.). Also stuck-sending and reliability variants.
- `integration/full_migration_chain_test.dart` — Full migration chain v1→latest.
- `migrations/*` (60+ files) — One file per migration step (001 through 066) plus `intro_migrations_test.dart`. Each verifies forward migration semantics + idempotency.

### Device (`test/core/device/`) — 1
- `upload_wake_lock_test.dart` — Upload wake-lock acquisition/release.

### Inbox (`test/core/inbox/`) — 1
- `inbox_round_trip_test.dart` — Relay-inbox roundtrip.

### Lifecycle (`test/core/lifecycle/`) — 16
- `handle_app_paused_test.dart` / `handle_app_paused_edge_cases_test.dart` / `handle_app_paused_group_test.dart` — Pause handlers.
- `handle_app_resumed_*` (5 files) — Resume handlers (group inbox retry, group recovery, group stuck-sending, stuck-sending, upload ordering).
- `app_lifecycle_pause_integration_test.dart` / `app_lifecycle_recovery_test.dart` — Lifecycle integration.
- `background_reconnect_smoke_test.dart` — Reconnect on resume.
- `connectivity_lifecycle_test.dart` — Connectivity changes.
- `main_resume_group_upload_wiring_test.dart` — DI wiring for resume.
- `pause_resume_retry_smoke_test.dart` — Pause/resume retry smoke.
- `sending_messages_query_test.dart` — Query used during pause/resume.

### Local discovery (`test/core/local_discovery/`) — 5
- `local_p2p_service_test.dart` — Local discovery p2p service.
- `local_media_sender_test.dart` / `local_media_server_test.dart` / `local_media_integration_test.dart` — Local-WiFi media transport.
- `local_ws_server_test.dart` — Local WebSocket server.

### Media (`test/core/media/`) — 12
- `image_processor_test.dart` — EXIF strip + compression.
- `audio_recorder_service_test.dart` / `audio_recorder_smoke_test.dart` — Audio recording.
- `amplitude_buffer_test.dart` / `normalize_amplitude_test.dart` / `downsample_waveform_test.dart` — Waveform pipeline.
- `media_file_manager_test.dart` — Media files on disk.
- `pending_composer_media_test.dart` — Pending composer media model.
- `video_process_result_test.dart` — Video processing result.
- `group_media_size_policy_test.dart` / `group_media_mime_policy_test.dart` / `group_media_integrity_policy_test.dart` — Group media policies.

### Notifications (`test/core/notifications/`) — 10
- `flutter_notification_service_test.dart` / `local_notification_support_test.dart` — Local notification service.
- `app_root_notification_open_test.dart` — Root-level open handling.
- `notification_push_tap_navigate_test.dart` — Tap-to-navigate.
- `notification_route_target_test.dart` / `notification_route_target_sender_id_test.dart` — Route target resolution.
- `notification_route_dispatch_test.dart` / `notification_route_contract_matrix_test.dart` — Dispatcher matrix.
- `recent_background_notification_gate_test.dart` / `recent_remote_notification_gate_test.dart` — Dedupe gates.

### Resilience (`test/core/resilience/`) — 8
- `c2_ack_drop_test.dart` / `c3_half_open_test.dart` / `c4_partial_drain_test.dart` — Connection-level chaos cases.
- `f1_wifi_relay_fallback_test.dart` / `f2_transport_switch_recovery_test.dart` — Failover scenarios.
- `network_chaos_test.dart` / `network_failover_test.dart` — Generic chaos + failover.
- `soak_test.dart` — Soak harness.

### Secure storage (`test/core/secure_storage/`) — 3
- `flutter_secure_key_store_test.dart` — Production secure key store.
- `migrate_secrets_to_secure_storage_test.dart` — One-time secret migration.
- `legacy_group_secret_storage_scrub_test.dart` — Legacy scrub.

### Services (`test/core/services/`) — 21
- `incoming_message_router_test.dart` + 5 posts variants (engagement, pass, pins, presence, posts) + profile variant — Router dispatch matrix.
- `p2p_service_impl_test.dart` / `p2p_service_addresses_updated_test.dart` / `p2p_service_fault_injection_test.dart` / `p2p_service_stop_race_test.dart` / `fake_p2p_service_test.dart` — P2PService impl + fakes + edge cases.
- `pending_message_retrier_test.dart` / `_stuck_sending_test.dart` / `_upload_ordering_test.dart` — Pending-message retrier variants.
- `pending_post_delivery_retrier_test.dart` / `pending_post_follow_on_retrier_test.dart` / `pending_post_media_upload_retrier_test.dart` — Posts-side retriers.
- `contact_request_listener_test.dart` — CR listener (placed under core).
- `share_intent_service_test.dart` / `share_intent_android_test.dart` / `share_intent_ios_test.dart` — Share intent platform glue.
- `android_build_configuration_test.dart` — Android Gradle config sanity.

### Theme (`test/core/theme/`) — 2
- `feed_colors_test.dart` — Feed accent colors.
- `background_readable_colors_test.dart` — Light/dark adaptive colors.

### Utils (`test/core/utils/`) — 5
- `flow_event_emitter_test.dart` — Structured-logging emitter.
- `key_conversion_test.dart` — Key encoding helpers.
- `ring_avatar_generator_test.dart` — Deterministic avatar generator.
- `text_direction_utils_test.dart` / `text_sanitizer_test.dart` / `url_parser_test.dart` — Text helpers.

### Notes
- This is the deepest single area in the repo (175 tests). Database migrations are tested per-step which is excellent for forward compatibility.

---

<a id="top-level-integration"></a>
## Top-level integration (`test/integration/**`) — 9
- `chat_notification_dedupe_integration_test.dart` — 1:1 push dedupe.
- `contact_request_notification_dedupe_integration_test.dart` — CR push dedupe.
- `group_notification_dedupe_integration_test.dart` — Group push dedupe.
- `notification_deeplink_integration_test.dart` — Deeplink open through notification.
- `notification_tap_smoke_test.dart` — Notification tap smoke.
- `onboarding_golden_path_test.dart` — Golden-path onboarding (FTE → first connection).
- `rapid_lock_unlock_integration_test.dart` — App lifecycle rapid lock/unlock.
- `relay_down_degradation_integration_test.dart` — Behaviour when relay is down.
- `routing_smoke_group_criteria_test.dart` — Group-routing criteria smoke.

---

<a id="shared"></a>
## Shared widgets / fixtures (`test/shared/**`) — 9
- `widgets/linkable_text_test.dart` — URL/email auto-linking.
- `widgets/media/audio_player_widget_test.dart` — Shared audio player.
- `widgets/media/full_screen_image_viewer_test.dart` — Image viewer.
- `widgets/media/media_grid_test.dart` / `media_grid_cell_test.dart` — Media grid.
- `widgets/media/media_thumbnail_image_test.dart` — Thumbnail.
- `widgets/media/media_preview_text_test.dart` — Preview text.
- `widgets/media/video_thumbnail_overlay_test.dart` — Video play overlay.
- `widgets/media/waveform_seek_bar_test.dart` — Waveform seek-bar.

---

<a id="performance"></a>
## Performance & benchmarks (`test/performance/**`) — 23
Benchmark harnesses (Dart-side, run as unit tests):
- `benchmark_1_1_send_test.dart` — 1:1 send latency.
- `benchmark_voice_send_test.dart` — Voice send.
- `benchmark_media_transfer_test.dart` — Media transfer throughput.
- `benchmark_inbox_roundtrip_test.dart` / `benchmark_inbox_delivery_timing_test.dart` — Inbox timing.
- `benchmark_relay_recovery_test.dart` — Relay-recovery time.
- `benchmark_routing_paths_test.dart` — Routing path costs.
- `benchmark_node_startup_test.dart` / `benchmark_time_to_online_test.dart` — Startup and online latency.
- `benchmark_background_resume_test.dart` — Resume latency.
- `benchmark_bridge_crossing_test.dart` — Bridge call cost.
- `benchmark_connection_reuse_test.dart` — Connection reuse.
- `benchmark_deferred_ack_test.dart` — Deferred ack timing.
- `benchmark_event_queue_test.dart` — Event queue.
- `benchmark_encryption_test.dart` — ML-KEM encryption cost.
- `benchmark_notification_tap_to_message_test.dart` — Tap to first message.
- `benchmark_timeout_accuracy_test.dart` — Timeout-accuracy regression.
- `benchmark_harness_test.dart` — Harness self-tests.
- `timing_test_bridge_test.dart` — Timing bridge.
- `conversation_wired_performance_test.dart` / `conversation_wired_subscription_performance_test.dart` — Conversation wired widget perf.
- `feed_wired_init_performance_test.dart` — Feed init perf.
- `orbit_performance_test.dart` — Orbit render perf.

---

<a id="security"></a>
## Security (`test/security/**`) — 1
- `forbidden_field_classifier_test.dart` — Classifier that flags forbidden fields in payloads/logs (mirrors `go-relay-server/forbidden_field_classifier_test.go`).

---

<a id="unit-bucket"></a>
## Unit bucket (`test/unit/**`) — 2
- `analyzer_baseline_parser_test.dart` — Parses Flutter analyzer baseline file.
- `path_exists_test.dart` — File-existence helper used by tooling.

---

<a id="flutter-integration"></a>
## Flutter on-device integration & harnesses (`integration_test/**`) — 78
**Where they run**: real device or simulator via `flutter test integration_test/...` or `flutter drive`.

### Top-level smoke / e2e
- `smoke_test.dart` — Bare app boot smoke.
- `bidi_text_smoke_test.dart` — RTL/LTR rendering smoke.
- `setup_device.dart` — One-time device setup helper.
- `cold_start_sendable_no_user_action_test.dart` — Cold-start ready-to-send timing.
- `loading_states_smoke_test.dart` — Loading state smoke.
- `notification_open_ui_smoke_test.dart` — Notification → UI open.
- `settings_background_choice_smoke_test.dart` — Background choice setting.

### Conversation / messaging e2e
- `conversation_bridge_test.dart` — Conversation through bridge.
- `media_message_journey_e2e_test.dart` — Media journey end-to-end.
- `media_stable_id_smoke_test.dart` — Stable id across send/recv.
- `voice_message_e2e_test.dart` — Voice e2e.

### Group e2e
- `foreground_group_push_drain_test.dart` — Foreground group push drain.
- `foreground_group_push_simulator_alice_harness.dart` / `foreground_group_push_simulator_bob_harness.dart` — Two-process driver harness.
- `group_multi_device_real_harness.dart` — Real multi-device harness.
- `group_new_member_media_simulator_proof_test.dart` — New-member media simulator.
- `group_real_crypto_onboarding_test.dart` — Real-crypto onboarding.
- `group_recovery_e2e_test.dart` / `group_recovery_cli_e2e_test.dart` — Recovery e2e (UI + CLI variants).
- `group_smoke_alice_harness.dart` / `group_smoke_bob_harness.dart` — Two-process group smoke.

### Routing / transport / relay
- `routing_smoke_alice_harness.dart` / `routing_smoke_bob_harness.dart` — Routing smoke.
- `multi_relay_failover_test.dart` — Multi-relay failover.
- `relay_chaos_soak_test.dart` — Relay chaos soak.
- `transport_e2e_test.dart` — Transport e2e.
- `wifi_transport_test.dart` / `wifi_relay_fallback_smoke_test.dart` — Wi-Fi transport + relay fallback.
- `background_reconnect_test.dart` — Background reconnect (skipped on some platforms — has `skip:`).
- `soak_e2e_test.dart` — End-to-end soak.

### Performance harnesses
- `feed_performance_test.dart` / `feed_wired_init_performance_harness.dart` — Feed perf.
- `conversation_wired_performance_harness.dart` / `conversation_wired_subscription_performance_harness.dart` — Conversation perf.
- `orbit_performance_harness.dart` — Orbit perf.
- `identity_progress_performance_test.dart` — Identity progress perf.
- `benchmark_*_harness.dart` (≈18 files) — Benchmark harness companions to `test/performance/benchmark_*` (1:1 send, ack, background resume, bridge crossing, connection reuse, encryption, event queue, group publish, helpers, inbox, media, node startup, notification tap, relay recovery, routing paths, time to online, timeout accuracy, voice).

### Notification / sound smoke
- `notification_sound_smoke_alice_harness.dart` / `notification_sound_smoke_bob_harness.dart` — Push sound smoke (two-process).

### Posts e2e
- `posts_phase1_fake_test.dart` … `posts_phase5_fake_test.dart` — Per-phase posts integration with fake p2p.

### Scripts (`integration_test/scripts/`)
- `_android_app_package.dart` — Android package id resolver.
- `routing_smoke_group_criteria.dart` — Routing criteria runner.
- `run_benchmark_suite.dart`, `run_group_publish_benchmark.dart`, `run_timeout_accuracy_benchmark.dart` — Benchmark drivers.
- `run_foreground_group_push_simulator_smoke.dart`, `run_group_multi_device_real.dart`, `run_group_recovery_e2e.dart` — Group multi-process drivers.
- `run_media_delivery_ui_smoke.dart`, `run_media_message_journey_e2e.dart`, `run_media_stable_id_smoke.dart` — Media drivers.
- `run_notification_open_ui_smoke.dart`, `run_notification_sound_smoke.dart` — Notification drivers.
- `run_routing_smoke_e2e.dart`, `run_soak_e2e.dart`, `run_transport_e2e.dart`, `run_wifi_relay_fallback_smoke.dart` — Routing/transport/soak drivers.

### Notes
- Several `*_harness.dart` files are not standalone tests; they expose helpers driven by the `scripts/run_*` entrypoints (see `reset_simulators.sh` / `--dart-define` pattern in project memory).
- `skip:` markers found in: `background_reconnect_test.dart`, `conversation_wired_performance_harness.dart`, `conversation_wired_subscription_performance_harness.dart`, `feed_wired_init_performance_harness.dart`, `media_message_journey_e2e_test.dart`, `multi_relay_failover_test.dart`, `orbit_performance_harness.dart`, `relay_chaos_soak_test.dart`, `voice_message_e2e_test.dart` — usually conditional on host capability (real device, real relay, simulator pair).

---

<a id="go-mknoon"></a>
## Go P2P node — `go-mknoon/**` — 80 tests

### `bridge/` (gomobile-exposed surface) — 2
- `bridge_test.go` — End-to-end bridge tests for command dispatch.
- `bridge_generate_next_key_test.go` — Key generation bridge command.

### `cmd/testpeer/` — 2
- `commands_test.go` — `testpeer` CLI command parser.
- `envelope_test.go` — Envelope round-trip.

### `crypto/` — 7
- `mlkem_test.go` — ML-KEM-768 keygen + encapsulate/decapsulate.
- `x25519_test.go` — X25519 KEM (legacy/interop).
- `sign_test.go` / `signature_test.go` — Ed25519 sign/verify.
- `file_crypto_test.go` — Per-file media encryption (AES-256-GCM).
- `group_test.go` — Group key derivation + envelope.
- `interop_test.go` — Interop fixtures (`testdata/interop_vectors.json`).

### `identity/` — 1
- `identity_test.go` — Identity generation + persistence.

### `integration/` — 7
- `relay_test.go` — Single-relay flow.
- `multi_relay_test.go` — Multi-relay flow.
- `local_relay_harness_test.go` — Local relay harness for tests.
- `media_test.go` — Media upload/download via relay.
- `profile_test.go` — Profile broadcast/receive.
- `personal_discoverability_test.go` — Discoverability rules.
- `ipv6_dual_stack_test.go` — IPv6 dual-stack listening.
- `watchdog_failover_test.go` — Watchdog/failover behaviour.

### `internal/` — 1
- `group_envelope_test.go` — Internal group envelope (v3).

### `node/` — 32 (own files)
- `node_test.go` — Top-level node lifecycle.
- `config_test.go` / `feature_flags_runtime_test.go` — Config + feature flags.
- `protocol_version_test.go` — Protocol version negotiation.
- `transport_label_test.go` — Transport label classifier.
- `relay_session_test.go` / `multi_relay_test.go` — Relay session + multi-relay.
- `rendezvous_test.go` — Rendezvous register/discover.
- `autorelay_metrics_test.go` — Autorelay metrics.
- `stream_timeout_test.go` — Stream timeouts.
- `media_test.go` — Media path on node.
- `send_message_recovery_test.go` — Send recovery.
- `group_inbox_test.go` — Group offline inbox.
- `group_security_harness_test.go` — Group security adversarial harness.
- `pubsub_test.go` / `pubsub_delivery_test.go` / `pubsub_decryption_failure_test.go` / `pubsub_authorization_forward_test.go` / `pubsub_key_rotation_grace_test.go` / `pubsub_unsubscribe_exit_paths_test.go` — Group pubsub paths.
- `benchmark_*_test.go` (10 files: ack, crypto, event_queue, harness, inbox, media, relay_recovery, send, startup, timeout_accuracy) — Go-side performance benchmarks.

### `third_party/go-libp2p-pubsub/` — 27
- Vendored upstream go-libp2p-pubsub test suite (gossipsub, floodsub, score, validation, topic, blacklist, backoff, mcache, peer_gater, rpc_queue, fuzz_helpers, etc.).
- Note: these are NOT mknoon tests. They run as part of `go test ./...` but cover the embedded pubsub library.

### Notes
- Excludes vendored 27 = 53 mknoon-owned Go tests.

---

<a id="go-relay-server"></a>
## Go relay server — `go-relay-server/**` — 13

- `server_bootstrap_test.go` — Server boot sequence.
- `inbox_test.go` / `inbox_dedup_test.go` — 1:1 inbox + dedupe.
- `group_inbox_test.go` — Group inbox.
- `media_test.go` — Encrypted media object store (upload/download).
- `profile_test.go` — Profile broadcast.
- `rendezvous_test.go` — Rendezvous registration table.
- `quic_smoke_test.go` — QUIC transport smoke.
- `failover_test.go` — Backend failover.
- `redis_failover_integration_test.go` — Redis backend failover integration.
- `backend_redis_test.go` — Redis backend impl.
- `limits_test.go` — Quota / rate limits.
- `forbidden_field_classifier_test.go` — Forbidden-field classifier (mirrors Dart side).

### Notes
- Backed by both in-memory and Redis backends; `failover_test.go` exercises switching.

---

## Cross-cutting observations

- **Per-phase organization for `posts`** breaks the `application/domain/integration/presentation` taxonomy used elsewhere — this is intentional (rollout-aligned) but worth flagging for new contributors.
- **`groups` recently grew** in line with the trusted-private-libp2p-group-chat work (see `Test-Flight-Improv/Group-Chat-Feature/`). Many `group_*_test.dart` files were added together; some functional duplication exists between `group_resume_recovery_test.dart`, `handle_app_resumed_group_*_test.dart`, and `drain_group_offline_inbox_use_case_test.dart` — these cover overlapping recovery surfaces from different layers.
- **Migration tests are exhaustive** (per-step files 001–066, plus `intro_migrations_test.dart` and a full chain test). Numbering gaps exist (014, 015, 019–025, 041, 043, 047) — those migration files exist in `lib/core/database/migrations/` but were either bundled into adjacent tests or are fixture-only.
- **Skipped tests** are concentrated in `integration_test/` (real-device-only; conditional `skip:` on host capability). No conditional skips found in `test/` unit tests.
- **Features without dedicated integration tests**: `contacts`, `home`, `p2p` (Dart side only — covered by Go), `qr_code`, `push`, `orbit`. Their flows are exercised transitively via `test/integration/**` and `integration_test/**` smoke tests.
- **No tests** for any `lib/features/<name>/` directory not listed above — every feature in the canonical taxonomy has at least application-layer coverage.
- **Dart `test/security/`** has only one file; most security/adversarial coverage actually lives in `go-mknoon/node/group_security_harness_test.go` and the resilience chaos suite.
- **Vendored pubsub tests** (`go-mknoon/third_party/go-libp2p-pubsub/**/*_test.go`, 27 files) inflate the Go test count. Excluding them, mknoon-owned Go test count is 53 in `go-mknoon` and 13 in `go-relay-server`.
