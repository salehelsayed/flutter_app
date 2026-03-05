## File Structure

```
lib/
├── main.dart                                    # App entry point, Firebase init, SecureKeyStore + encrypted DB setup (v18), secret migration, DI; MyApp = StatefulWidget + WidgetsBindingObserver (lifecycle, push listeners, orderly dispose)
├── smoke_test_main.dart                         # Smoke test entry point
├── smoke_test_restore.dart                      # Smoke test for identity restore
├── smoke_test_messages.dart                     # Smoke test for messages DB layer
├── core/
│   ├── bridge/
│   │   ├── bridge.dart                          # Bridge abstract interface (send, initialize, checkHealth, reinitialize, dispose, callbacks) + identity/crypto helper functions (callIdentityGenerate, callSignPayload, callVerifyPayload, callMlKemKeygen, callEncryptMessage, callDecryptMessage)
│   │   ├── bridge_group_helpers.dart            # Group-specific bridge helpers (callGroupJoinWithConfig, callGroupPublish, callGroupEncrypt, callGroupDecrypt, etc.)
│   │   ├── go_bridge_client.dart               # GoBridgeClient: MethodChannel/EventChannel → Go native; _cmdMap maps cmd→MethodChannel method names
│   │   └── p2p_bridge_client.dart              # P2P-specific bridge calls (callP2PNodeStart/Stop/Status, rendezvous, peer, message, inbox) + defaultRendezvousAddress constant
│   ├── constants/
│   │   └── network_constants.dart              # Rendezvous address
│   ├── database/
│   │   ├── encrypted_db_opener.dart              # Opens SQLCipher DB with key from secure storage
│   │   ├── migrations/
│   │   │   ├── 001_identity_table.dart         # Schema v1 (identity, contacts, contact_requests)
│   │   │   ├── 002_messages_table.dart         # Schema v2 (messages table + indexes)
│   │   │   ├── 003_mlkem_keys.dart             # Schema v3 (ML-KEM key columns on identity, contacts, contact_requests)
│   │   │   ├── 004_nullify_secret_columns.dart # Schema v4 (makes private_key, mnemonic12 nullable)
│   │   │   ├── 005_secret_null_checks.dart     # Schema v5 (CHECK constraints + avatar_blob BLOB)
│   │   │   ├── 006_read_at_column.dart         # Schema v6 (read_at TEXT on messages table)
│   │   │   ├── 007_archive_columns.dart        # Schema v7 (is_archived, archived_at on contacts)
│   │   │   ├── 008_block_columns.dart          # Schema v8 (is_blocked, blocked_at on contacts)
│   │   │   ├── 009_quoted_message_id.dart     # Schema v9 (quoted_message_id TEXT on messages)
│   │   │   ├── 010_media_attachments.dart     # Schema v10 (media_attachments table + indexes)
│   │   │   ├── 011_avatar_version.dart        # Schema v11 (avatar_version INTEGER on identity and contacts)
│   │   │   ├── 012_transport_column.dart     # Schema v12 (transport TEXT on messages)
│   │   │   ├── 013_waveform_column.dart      # Schema v13 (waveform TEXT on media_attachments)
│   │   │   ├── 014_wire_envelope_column.dart # Schema v14 (wire_envelope TEXT on messages)
│   │   │   ├── 015_message_status_cleanup.dart # Schema v15 (normalize legacy outgoing 'queued' rows)
│   │   │   ├── 016_message_reactions.dart    # Schema v16 (message_reactions table for emoji reactions)
│   │   │   ├── 017_groups_tables.dart        # Schema v17 (groups, group_members tables)
│   │   │   └── 018_group_messages_tables.dart # Schema v18 (group_keys, group_messages tables)
│   │   └── helpers/
│   │       ├── identity_db_helpers.dart        # Identity DB CRUD
│   │       ├── contacts_db_helpers.dart        # Contacts DB CRUD
│   │       ├── contact_requests_db_helpers.dart # Contact Requests DB CRUD
│   │       ├── messages_db_helpers.dart        # Messages DB CRUD
│   │       ├── media_attachments_db_helpers.dart # Media Attachments DB CRUD
│   │       ├── reactions_db_helpers.dart       # Message Reactions DB CRUD
│   │       ├── groups_db_helpers.dart          # Groups DB CRUD
│   │       ├── group_members_db_helpers.dart   # Group Members DB CRUD
│   │       ├── group_keys_db_helpers.dart      # Group Keys DB CRUD
│   │       └── group_messages_db_helpers.dart  # Group Messages DB CRUD
│   ├── secure_storage/
│   │   ├── secure_key_store.dart                 # SecureKeyStore abstract interface
│   │   ├── flutter_secure_key_store.dart         # FlutterSecureKeyStore impl (iOS Keychain / Android EncryptedSharedPrefs)
│   │   └── migrate_secrets_to_secure_storage.dart # One-time DB→secure storage migration
│   ├── services/
│   │   ├── p2p_service.dart                    # P2PService abstract interface (incl. inbox, sendMessageWithReply, startNodeCore, warmBackground, isLocalPeer, sendLocalMessage)
│   │   ├── p2p_service_impl.dart               # P2PServiceImpl with streams, offline inbox drain, local WiFi discovery (mDNS/Bonsoir), periodic health check (30s)
│   │   ├── incoming_message_router.dart        # Routes P2P messages by type to streams
│   │   ├── pending_message_retrier.dart        # PendingMessageRetrier: subscribes to stateStream, retries failed messages on reconnect (5s debounce)
│   │   ├── chat_message_listener.dart          # Stub ChatMessageListener (core-level; real impl in features/conversation)
│   │   ├── contact_request_listener.dart       # Stub ContactRequestListener (core-level; real impl in features/contact_request)
│   │   └── chat_message.dart                   # ChatMessage type re-export
│   ├── media/
│   │   ├── image_processor.dart                # ImageProcessor: EXIF strip, quality compress (injectable CompressFileFn)
│   │   ├── media_file_manager.dart             # MediaFileManager: local file path management for attachments
│   │   ├── video_process_result.dart           # VideoProcessResult data class
│   │   ├── audio_recorder_service.dart         # AudioRecorderService abstract interface
│   │   ├── record_audio_recorder_service.dart  # Production AudioRecorderService impl (wraps record package)
│   │   ├── amplitude_buffer.dart               # Fixed-size circular buffer for normalized amplitude values
│   │   ├── normalize_amplitude.dart            # dBFS amplitude → [0.0, 1.0] normalization
│   │   └── downsample_waveform.dart            # Downsample/pad amplitude list to fixed target size
│   ├── notifications/
│   │   ├── notification_service.dart           # NotificationService abstract interface
│   │   ├── flutter_notification_service.dart   # Production impl using flutter_local_notifications
│   │   └── active_conversation_tracker.dart    # Tracks active conversation to suppress notifications
│   ├── lifecycle/
│   │   └── handle_app_resumed.dart             # Handles app resume: reconnect, retry key exchanges, drain inbox
│   ├── theme/
│   │   ├── app_colors.dart                     # Color constants (Custom1 dark)
│   │   ├── app_theme.dart                      # ThemeData configuration
│   │   ├── feed_colors.dart                    # FeedColors: purple/teal palette for feed cards
│   │   └── glassmorphism.dart                  # GlassmorphicContainer widget
│   ├── config/
│   │   └── startup_config.dart                 # StartupConfig class with deferredStartupMode flag
│   ├── local_discovery/
│   │   ├── local_discovery_service.dart        # LocalDiscoveryService abstract interface (mDNS)
│   │   ├── bonsoir_discovery_service.dart      # BonsoirDiscoveryService impl (Bonsoir mDNS)
│   │   ├── local_p2p_service.dart              # LocalP2PService: combines mDNS discovery + WebSocket
│   │   ├── local_ws_server.dart                # LocalWsServer: local WebSocket server for WiFi peers
│   │   ├── local_media_server.dart             # LocalMediaServer: HTTP server for local WiFi media transfer
│   │   └── local_media_sender.dart             # LocalMediaSender: HTTP client for local WiFi media transfer
│   └── utils/
│       ├── flow_event_emitter.dart             # Logging utility
│       ├── key_conversion.dart                 # base64 ↔ hex conversion
│       ├── ring_avatar_spec.dart               # Ring avatar constants + data models
│       ├── ring_avatar_generator.dart          # Deterministic avatar from peerId
│       ├── chat_console_logger.dart           # Chat message debug logging + wire envelope logging
│       ├── startup_timing.dart                # StartupTiming singleton for debug timing marks
│       ├── text_sanitizer.dart                # Message/username length limits + sanitization
│       └── url_parser.dart                    # URL detection + TextSegment model for linkable text
│
├── features/
│   ├── home/
│   │   └── presentation/
│   │       ├── screens/
│   │       │   ├── first_time_experience_screen.dart   # Pure UI (animated)
│   │       │   └── first_time_experience_wired.dart    # Business logic + CR listener
│   │       └── widgets/
│   │           ├── profile_avatar_widget.dart          # Avatar + camera
│   │           ├── editable_username_widget.dart       # Tap-to-edit username
│   │           ├── qr_code_section.dart                # QR with glow
│   │           ├── scan_friend_card.dart               # Scan action card
│   │           ├── empty_circle_state.dart             # Pulsing circles
│   │           ├── ring_avatar.dart                    # RingAvatar widget
│   │           ├── ring_avatar_painter.dart            # Canvas renderer
│   │           └── user_avatar.dart                    # UserAvatar widget (profile picture or RingAvatar fallback)
│   │
│   ├── feed/
│   │   ├── domain/
│   │   │   ├── models/
│   │   │   │   ├── feed_item.dart              # FeedItem base + ConnectionFeedItem + MessageFeedItem + ThreadFeedItem + ThreadMessage
│   │   │   │   └── session_reply.dart         # SessionReply + SessionReplyTracker models
│   │   │   └── utils/
│   │   │       ├── format_message_time.dart    # Message timestamp formatting + formatRelativeTime()
│   │   │       ├── group_messages_into_threads.dart  # Groups incoming messages into ThreadFeedItems by contact and read session
│   │   │       ├── group_group_messages_into_threads.dart  # Groups incoming group messages into ThreadFeedItems by group
│   │   │       ├── split_thread_by_time_gap.dart     # Splits thread messages by significant time gaps
│   │   │       └── has_significant_time_gap.dart     # Returns true if gap >= 2h or crosses AM/PM boundary
│   │   ├── application/
│   │   │   └── load_feed_use_case.dart         # Load initial feed from DB
│   │   └── presentation/
│   │       ├── screens/
│   │       │   ├── feed_screen.dart            # Pure UI feed display
│   │       │   └── feed_wired.dart             # Feed business logic + CR listener
│   │       ├── widgets/
│   │       │   ├── feed_header.dart            # Sticky header (username + avatar)
│   │       │   ├── feed_navigation_bar.dart    # Bottom glass nav bar (3 tabs)
│   │       │   ├── nav_bar_button.dart         # Individual nav button widget
│   │       │   ├── nav_bar_theme.dart          # Design tokens for Signal-inspired nav bar
│   │       │   ├── connection_card.dart        # Contact connection card
│   │       │   ├── feed_card.dart             # FeedCard: open/collapsed modes (replaces message_feed_card + thread_card)
│   │       │   ├── collapsed_mode_card_body.dart  # Collapsed mode card body
│   │       │   ├── open_mode_card_body.dart    # Open mode card body with scrollable messages
│   │       │   ├── expanded_compose_input.dart # Multi-line auto-growing compose input for expanded thread cards
│   │       │   ├── inline_reply_input.dart    # Inline reply input within feed cards
│   │       │   ├── scrollable_message_preview.dart  # Scrollable message preview
│   │       │   ├── swipe_to_quote_bubble.dart # Swipe-to-quote bubble
│   │       │   ├── quote_preview_bar.dart     # Quote preview bar
│   │       │   ├── view_earlier_link.dart     # View earlier messages link
│   │       │   ├── more_messages_hint.dart    # More messages hint
│   │       │   ├── replied_indicator.dart     # Replied indicator
│   │       │   ├── message_bubble.dart        # Single message bubble within feed card
│   │       │   ├── session_divider.dart       # Session divider between message groups
│   │       │   ├── time_gap_divider.dart      # Time gap divider for significant pauses
│   │       │   ├── unread_count_badge.dart   # Circular unread count badge
│   │       │   └── checkmark_burst_animation.dart  # Animated checkmark
│   │       └── navigation/
│   │           └── feed_route_transition.dart   # Slide-up route transition
│   │
│   ├── conversation/
│   │   ├── domain/
│   │   │   ├── models/
│   │   │   │   ├── conversation_message.dart   # ConversationMessage model (+ quotedMessageId, media list)
│   │   │   │   ├── message_payload.dart        # Wire-format envelope model (+ quoted msg, media support)
│   │   │   │   ├── media_attachment.dart       # MediaAttachment model + MediaType enum + DownloadStatus enum
│   │   │   │   ├── audio_recording.dart        # AudioRecording model (filePath, durationMs, mime, sizeBytes)
│   │   │   │   ├── message_reaction.dart       # MessageReaction model (emoji reaction on a message)
│   │   │   │   └── reaction_payload.dart       # Wire-format model for emoji reactions (v1/v2 envelope)
│   │   │   └── repositories/
│   │   │       ├── message_repository.dart     # Abstract interface
│   │   │       ├── message_repository_impl.dart # DB-backed implementation
│   │   │       ├── media_attachment_repository.dart      # MediaAttachmentRepository abstract interface
│   │   │       ├── media_attachment_repository_impl.dart # DB-backed implementation
│   │   │       ├── reaction_repository.dart    # ReactionRepository abstract interface
│   │   │       └── reaction_repository_impl.dart # DB-backed implementation
│   │   ├── application/
│   │   │   ├── send_chat_message_use_case.dart # Send: encrypt (v2) or plaintext (v1), 3x retry, inbox fallback
│   │   │   ├── handle_incoming_chat_message_use_case.dart  # Receive: decrypt v2 or parse v1
│   │   │   ├── load_conversation_use_case.dart # Load messages for contact
│   │   │   ├── mark_conversation_read_use_case.dart # Mark unread messages as read
│   │   │   ├── retry_failed_messages_use_case.dart  # Retry failed outgoing messages on reconnect
│   │   │   ├── retry_unacked_messages_use_case.dart # Retry 'sent' messages via inbox relay (no re-encrypt)
│   │   │   ├── upload_media_use_case.dart      # Upload media attachment to relay
│   │   │   ├── download_media_use_case.dart    # Download media attachment from relay
│   │   │   ├── chat_message_listener.dart      # Background chat listener + ML-KEM decryption; rejects blocked contacts, suppresses UI for archived
│   │   │   ├── send_voice_message_use_case.dart # Record + upload + send voice message
│   │   │   ├── send_reaction_use_case.dart     # Send emoji reaction to a message
│   │   │   ├── handle_incoming_reaction_use_case.dart # Handle incoming emoji reaction
│   │   │   ├── remove_reaction_use_case.dart   # Remove emoji reaction from a message
│   │   │   ├── load_reactions_use_case.dart    # Load reactions for a list of message IDs
│   │   │   └── reaction_listener.dart          # Background P2P listener for incoming reactions
│   │   └── presentation/
│   │       ├── screens/
│   │       │   ├── conversation_screen.dart    # Pure UI: letter cards, compose
│   │       │   └── conversation_wired.dart     # Business logic + optimistic UI
│   │       ├── widgets/
│   │       │   ├── letter_card.dart            # Full-width message card
│   │       │   ├── compose_area.dart           # Text field + send button
│   │       │   ├── empty_conversation_state.dart # Breathing glow empty state
│   │       │   ├── conversation_header.dart    # Frosted-glass header
│   │       │   ├── compact_origin_marker.dart  # Connection origin marker
│   │       │   ├── date_separator.dart         # Date divider
│   │       │   ├── blocked_banner.dart         # Blocked contact banner with "Unblock" button
│   │       │   ├── attachment_preview_strip.dart # Horizontal strip showing attachment previews
│   │       │   ├── voice_record_button.dart    # Mic button for voice recording (long press)
│   │       │   ├── recording_overlay.dart      # Overlay shown during active recording
│   │       │   ├── amplitude_bars.dart         # Row of vertical bars for audio amplitude
│   │       │   ├── reaction_bar.dart           # Quick-reaction emoji bar (6 preset emojis)
│   │       │   ├── reaction_display.dart       # Emoji reaction chips below a message
│   │       │   └── full_emoji_picker.dart      # Full emoji picker with categories
│   │       └── navigation/
│   │           └── conversation_route_transition.dart
│   │
│   ├── groups/
│   │   ├── domain/
│   │   │   ├── models/
│   │   │   │   ├── group_model.dart            # GroupModel + GroupType enum (chat, announcement, qa)
│   │   │   │   ├── group_member.dart           # GroupMember + MemberRole enum (admin, writer, reader)
│   │   │   │   ├── group_message.dart          # GroupMessage model (maps to group_messages table)
│   │   │   │   ├── group_message_payload.dart  # Wire format for group messages (v3 envelope)
│   │   │   │   ├── group_invite_payload.dart   # Wire format for group invite messages over P2P
│   │   │   │   └── group_key_info.dart         # GroupKeyInfo model (maps to group_keys table)
│   │   │   └── repositories/
│   │   │       ├── group_repository.dart       # GroupRepository abstract interface (groups, members, keys)
│   │   │       ├── group_repository_impl.dart  # DB-backed implementation
│   │   │       ├── group_message_repository.dart     # GroupMessageRepository abstract interface
│   │   │       └── group_message_repository_impl.dart # DB-backed implementation
│   │   ├── application/
│   │   │   ├── create_group_use_case.dart              # Create group locally + join GossipSub topic
│   │   │   ├── create_group_with_members_use_case.dart # Create group + invite initial members
│   │   │   ├── join_group_use_case.dart                # Join group from invite (save + subscribe topic)
│   │   │   ├── leave_group_use_case.dart               # Leave group (unsubscribe topic)
│   │   │   ├── add_group_member_use_case.dart          # Add member to existing group
│   │   │   ├── remove_group_member_use_case.dart       # Remove member from group + rotate key
│   │   │   ├── send_group_invite_use_case.dart         # Send group invite via P2P
│   │   │   ├── handle_incoming_group_invite_use_case.dart # Handle received group invite
│   │   │   ├── send_group_message_use_case.dart        # Send encrypted group message via GossipSub
│   │   │   ├── handle_incoming_group_message_use_case.dart # Handle received group message
│   │   │   ├── group_message_listener.dart             # Background GossipSub listener for group messages
│   │   │   ├── group_invite_listener.dart              # Background P2P listener for group invites
│   │   │   ├── group_key_update_listener.dart          # Background listener for group key updates
│   │   │   ├── rotate_group_key_use_case.dart          # Generate + store new group key
│   │   │   ├── rotate_and_distribute_group_key_use_case.dart # Rotate key + distribute to all members
│   │   │   ├── rejoin_group_topics_use_case.dart       # Re-subscribe active groups on app restart
│   │   │   ├── drain_group_offline_inbox_use_case.dart # Drain offline inbox for group messages
│   │   │   ├── archive_group_use_case.dart             # Archive group (hide from active list)
│   │   │   ├── unarchive_group_use_case.dart           # Unarchive group (restore to active list)
│   │   │   └── delete_group_and_messages_use_case.dart # Delete group, messages, and leave
│   │   └── presentation/
│   │       ├── screens/
│   │       │   ├── group_list_screen.dart              # Pure UI: list of groups
│   │       │   ├── group_list_wired.dart               # Group list business logic
│   │       │   ├── group_conversation_screen.dart      # Pure UI: group chat with letter cards
│   │       │   ├── group_conversation_wired.dart       # Group conversation business logic
│   │       │   ├── group_info_screen.dart              # Pure UI: group details + member list
│   │       │   ├── group_info_wired.dart               # Group info business logic
│   │       │   ├── create_group_screen.dart            # Pure UI: group name + type selection
│   │       │   ├── create_group_wired.dart             # Create group business logic
│   │       │   ├── create_group_picker_screen.dart     # Pure UI: contact picker for new group
│   │       │   ├── create_group_picker_wired.dart      # Contact picker business logic (create flow)
│   │       │   ├── contact_picker_screen.dart          # Pure UI: contact picker for adding members
│   │       │   └── contact_picker_wired.dart           # Contact picker business logic (add member flow)
│   │       └── widgets/
│   │           ├── group_card.dart                     # Group card in group list
│   │           ├── group_compose_area.dart             # Compose area for group conversations
│   │           ├── group_member_row.dart               # Member row with role badge + actions
│   │           ├── group_name_panel.dart               # Group name input panel
│   │           ├── group_type_badge.dart               # Group type badge with color coding
│   │           ├── contact_picker_row.dart             # Contact row in picker
│   │           ├── expandable_fab.dart                 # Expandable floating action button
│   │           └── glow_fab.dart                       # Circular FAB with blue glowing ring
│   │
│   ├── orbit/
│   │   ├── domain/
│   │   │   └── models/
│   │   │       ├── orbit_friend.dart             # OrbitFriend composite model
│   │   │       ├── orbit_group.dart              # OrbitGroup composite model (group + activity data)
│   │   │       └── orbit_item.dart               # OrbitItem union type (friend or group)
│   │   ├── application/
│   │   │   ├── load_orbit_data_use_case.dart     # Load contacts + message counts
│   │   │   └── load_orbit_groups_use_case.dart   # Load groups + message counts for orbit
│   │   └── presentation/
│   │       ├── screens/
│   │       │   ├── orbit_screen.dart             # Pure UI: orbital viz, friend list, search
│   │       │   └── orbit_wired.dart              # Business logic + 3 AnimationControllers
│   │       ├── navigation/
│   │       │   └── orbit_route_transition.dart   # Slide-up transition for orbit screen
│   │       └── widgets/
│   │           ├── orbital_visualization.dart     # 320x320 Stack with ring painter + avatars
│   │           ├── orbital_ring_painter.dart      # CustomPainter: 2 dashed concentric circles
│   │           ├── orbital_avatar.dart            # Positioned avatar with staggered scale-in
│   │           ├── overflow_badge.dart            # "+N" badge with delayed entrance
│   │           ├── orbit_close_button.dart        # 36x36 glass circle X button
│   │           ├── friends_list_header.dart        # "Friends" title + QR/Scan pill buttons
│   │           ├── friend_row.dart                # Glassmorphic friend card
│   │           ├── group_row.dart                 # Glassmorphic group card for orbit list
│   │           ├── swipeable_friend_row.dart      # Swipeable friend row with slide-to-reveal actions (Block/Delete/Archive)
│   │           ├── swipe_action_buttons.dart       # Block/Delete/Archive action buttons for swipe
│   │           ├── friends_filter_toggle.dart      # Segmented toggle "All (N)" / "Archived (N)"
│   │           ├── archived_empty_state.dart       # Empty state for archived contacts list
│   │           ├── confirmation_dialog.dart        # Confirmation dialog for destructive actions
│   │           ├── qr_action_cards.dart            # QR action cards (My QR / Scan QR)
│   │           ├── orbit_search_trigger.dart       # Floating glass pill search button
│   │           └── orbit_search_dock.dart          # Bottom-docked search TextField
│   │
│   ├── settings/
│   │   ├── application/
│   │   │   ├── image_quality_preference_use_cases.dart    # Read/write image quality preference from SecureKeyStore
│   │   │   ├── upload_profile_picture_use_case.dart       # Upload profile picture to relay
│   │   │   ├── download_profile_picture_use_case.dart     # Download profile picture from relay
│   │   │   └── profile_update_listener.dart               # Monitors profile update events
│   │   ├── domain/
│   │   │   └── models/
│   │   │       └── image_quality_preference.dart            # ImageQualityPreference enum
│   │   └── presentation/
│   │       ├── screens/
│   │       │   ├── settings_screen.dart                     # Pure UI settings display
│   │       │   └── settings_wired.dart                      # Settings business logic
│   │       ├── navigation/
│   │       │   └── settings_route_transition.dart           # Slide-up transition for settings screen
│   │       └── widgets/
│   │           ├── settings_profile_section.dart             # Profile section widget
│   │           ├── settings_peer_id_card.dart                # Peer ID display card
│   │           ├── settings_recovery_phrase_card.dart        # Recovery phrase card
│   │           └── image_quality_toggle.dart                 # Image quality toggle widget
│   │
│   ├── push/
│   │   └── application/
│   │       ├── background_message_handler.dart     # @pragma('vm:entry-point') Firebase handler; defers inbox drain to next app resume
│   │       ├── request_push_permission_use_case.dart # Requests notification permission
│   │       ├── register_push_token_use_case.dart    # Registers FCM token via P2P inbox protocol
│   │       └── show_notification_use_case.dart      # Show local notification (suppressed if conversation active)
│   │
│   ├── identity/
│   │   ├── domain/
│   │   │   ├── models/
│   │   │   │   └── identity_model.dart         # IdentityModel class
│   │   │   └── repositories/
│   │   │       ├── identity_repository.dart    # Abstract interface
│   │   │       └── identity_repository_impl.dart
│   │   ├── application/
│   │   │   ├── startup_decision.dart           # decideStartupRoute() (3-way)
│   │   │   ├── generate_identity_use_case.dart
│   │   │   └── restore_identity_use_case.dart
│   │   └── presentation/
│   │       ├── startup_router.dart                     # Routes to feed, home, or onboarding
│   │       ├── screens/
│   │       │   ├── identity_choice_screen.dart
│   │       │   ├── identity_choice_wired.dart
│   │       │   ├── mnemonic_input_screen.dart
│   │       │   └── mnemonic_input_wired.dart
│   │       └── widgets/
│   │           ├── ambient_background.dart     # Animated glow background
│   │           ├── brand_header.dart           # Logo/title header
│   │           ├── choice_card.dart            # Glassmorphic tap card
│   │           └── identity_loading_card.dart  # Loading card during identity generation/restore
│   │
│   ├── qr_code/
│   │   ├── domain/
│   │   │   └── models/
│   │   │       └── qr_payload_model.dart
│   │   ├── application/
│   │   │   ├── build_qr_payload_use_case.dart  # Sign and build QR
│   │   │   ├── parse_qr_payload_use_case.dart  # Validate scanned QR
│   │   │   └── handle_scanned_qr_use_case.dart # End-to-end scan → add contact + send CR
│   │   └── presentation/
│   │       ├── screens/
│   │       │   ├── qr_display_screen.dart
│   │       │   ├── qr_display_wired.dart
│   │       │   ├── qr_scanner_screen.dart      # Camera scanner UI
│   │       │   └── qr_scanner_wired.dart       # Scanner business logic
│   │       └── widgets/
│   │           └── scan_overlay.dart            # Canvas scan overlay
│   │
│   ├── contacts/
│   │   ├── domain/
│   │   │   ├── models/
│   │   │   │   └── contact_model.dart          # ContactModel class
│   │   │   └── repositories/
│   │   │       ├── contact_repository.dart     # Abstract interface
│   │   │       └── contact_repository_impl.dart
│   │   └── application/
│   │       ├── add_contact_use_case.dart        # Add with duplicate check
│   │       ├── archive_contact_use_case.dart    # Archive contact
│   │       ├── unarchive_contact_use_case.dart  # Unarchive contact
│   │       ├── block_contact_use_case.dart      # Block contact
│   │       ├── unblock_contact_use_case.dart    # Unblock contact
│   │       └── delete_contact_use_case.dart     # Delete contact and messages
│   │
│   ├── contact_request/
│   │   ├── domain/
│   │   │   ├── models/
│   │   │   │   └── contact_request_model.dart  # ContactRequestModel + status enum
│   │   │   └── repositories/
│   │   │       ├── contact_request_repository.dart      # Abstract interface
│   │   │       └── contact_request_repository_impl.dart
│   │   ├── application/
│   │   │   ├── send_contact_request_use_case.dart       # Build, sign, discover, dial, send
│   │   │   ├── accept_contact_request_use_case.dart     # Request → contact
│   │   │   ├── accept_and_reciprocate_use_case.dart     # Accept + send reciprocal CR
│   │   │   ├── decline_contact_request_use_case.dart    # Update status
│   │   │   ├── handle_incoming_message_use_case.dart    # Parse, validate, store
│   │   │   ├── contact_request_listener.dart            # Background P2P listener
│   │   │   ├── retry_incomplete_key_exchanges_use_case.dart # Retry incomplete ML-KEM key exchanges
│   │   │   └── key_exchange_retrier.dart                # Periodic key exchange retry service
│   │   └── presentation/
│   │       └── widgets/
│   │           ├── contact_request_dialog.dart           # Accept/Decline modal
│   │           └── pending_requests_badge.dart           # Count badge
│   │
│   └── p2p/
│       ├── domain/
│       │   └── models/
│       │       ├── node_state.dart              # NodeState (isStarted, connections, etc.)
│       │       ├── connection_state.dart         # ConnectionState (peerId, direction)
│       │       ├── discovered_peer.dart          # DiscoveredPeer (id, addresses)
│       │       ├── chat_message.dart             # ChatMessage (from, to, content)
│       │       └── send_message_result.dart      # SendMessageResult class (sent, reply, acknowledged)
│       ├── application/
│       │   ├── start_node_use_case.dart          # Start node with identity
│       │   ├── stop_node_use_case.dart           # Stop running node
│       │   ├── send_message_use_case.dart        # Send P2P message
│       │   └── discover_peer_use_case.dart       # Discover + dial peer
│       └── presentation/
│           └── widgets/
│               └── connection_status_indicator.dart  # Online/Offline badge
│
├── shared/
│   └── widgets/
│       ├── linkable_text.dart                       # LinkableText widget: auto-detects URLs and makes them tappable
│       └── media/
│           ├── media_grid.dart                       # Grid layout for media attachments
│           ├── media_grid_cell.dart                   # Individual cell in the media grid
│           ├── media_display_helpers.dart             # Media display helper functions
│           ├── media_preview_text.dart                # Text preview for media attachments
│           ├── full_screen_image_viewer.dart          # Full-screen image viewer with zoom
│           ├── video_thumbnail_overlay.dart           # Video thumbnail with play overlay
│           ├── audio_player_widget.dart               # Audio player with controls
│           └── waveform_seek_bar.dart                 # Waveform-based seek bar for audio playback

go-mknoon/
├── Makefile                                    # Build targets: `make all` (iOS + Android), `make ios`, `make android`
├── go.mod / go.sum                             # Go module dependencies
├── tools.go                                    # Blank import to keep golang.org/x/mobile in go.mod
├── bridge/
│   ├── bridge.go                               # HandleCommand() dispatch → identity, crypto, node, inbox, media handlers
│   └── events.go                               # EventCallback interface for Flutter push events (incoming messages, peer connects)
├── identity/
│   └── identity.go                             # BIP39 mnemonic + Ed25519 keypair + ML-KEM-768 keygen + restore
├── crypto/
│   ├── mlkem.go                                # ML-KEM-768 keygen (circl/kem/mlkem768)
│   ├── encrypt.go                              # ML-KEM encapsulate + AES-256-GCM encrypt
│   ├── decrypt.go                              # ML-KEM decapsulate + AES-256-GCM decrypt
│   ├── x25519.go                               # X25519 ECDH + HKDF-SHA256 + AES-256-GCM for contact request encryption; Ed25519->X25519 key conversion
│   ├── sign.go                                 # Ed25519 signing + verification
│   └── group.go                                # Group message encryption/decryption (AES-256-GCM with symmetric group key)
├── internal/
│   ├── envelope.go                             # V1Envelope unencrypted wire format
│   └── group_envelope.go                       # V3 group envelope: encrypted + signed wire format
├── cmd/
│   └── testpeer/                               # Headless Go CLI peer for E2E transport testing; stdin/stdout JSON protocol
├── node/
│   ├── node.go                                 # libp2p host lifecycle, chat protocol (/mknoon/chat/1.0.0), event broadcasting
│   ├── config.go                               # Node configuration (timeouts, addresses)
│   ├── rendezvous.go                           # Rendezvous register/discover with protobuf signed peer records
│   ├── inbox.go                                # Offline inbox protocol (/mknoon/inbox/1.0.0): store/retrieve/register FCM token
│   ├── media.go                                # Media protocol (/mknoon/media/1.0.0): upload/download/delete/list + profile upload/download
│   ├── pubsub.go                               # GossipSub pubsub: topic join/leave/publish, peer discovery loop
│   ├── group.go                                # GroupType definition + group command dispatch
│   └── group_inbox.go                          # Group offline inbox: store/retrieve group messages via relay
├── stub/
│   └── gosigar/                                # iOS stub for gosigar (libproc.h not available)
└── testdata/
    └── interop_vectors.json                    # Cross-platform test vectors for crypto interop

ios/
├── Runner/GoBridge.swift                       # iOS platform wrapper: MethodChannel + EventChannel → GoMknoon framework
└── Podfile                                     # CocoaPods config (includes GoMknoon.xcframework)

android/
└── app/src/main/kotlin/.../GoBridge.kt         # Android platform wrapper: MethodChannel + EventChannel → GoMknoon AAR

assets/
└── icons/
    ├── nav_feed.svg                             # Feed tab icon
    ├── nav_orbit.svg                            # Orbit/circle tab icon
    └── nav_remember.svg                         # Remember tab icon
```

---
