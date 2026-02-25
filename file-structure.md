# File Structure

## Project Structure Overview

```
flutter_app/
├── assets/
│   └── icons/
│       ├── nav_feed.svg                             # Feed tab icon
│       ├── nav_orbit.svg                            # Orbit/circle tab icon
│       └── nav_remember.svg                         # Remember tab icon
│
├── lib/
│   ├── main.dart                               # App entry point (StatefulWidget + WidgetsBindingObserver), SecureKeyStore + encrypted DB setup, secrets migration, Firebase init, background message handler, DI (dbCountMessagesForContact, dbMarkConversationAsRead, dbCountUnreadForContact, dbCountTotalUnread wired to MessageRepositoryImpl), app lifecycle (resume → bridge health check → P2P health check → inbox drain), foreground push listeners (Firebase onMessage/onMessageOpenedApp → inbox drain), orderly dispose chain (chatMessageListener → contactRequestListener → messageRouter → p2pService → bridge), params: messageRouter, isDesktop
│   ├── smoke_test_main.dart                    # Smoke test entry point
│   ├── smoke_test_restore.dart                 # Smoke test for identity restore
│   ├── smoke_test_messages.dart                # Smoke test for messages DB layer (null-safety fix for nullable map access)
│   │
│   ├── core/
│   │   ├── bridge/
│   │   │   ├── bridge.dart                     # Bridge abstract interface (send, initialize, checkHealth, reinitialize, dispose, callback fields) + identity/crypto helper functions (callIdentityGenerate, callIdentityRestore, callSignPayload, callVerifyPayload, callMlKemKeygen, callEncryptMessage, callDecryptMessage)
│   │   │   ├── go_bridge_client.dart           # GoBridgeClient: MethodChannel/EventChannel → Go native, command mapping, event routing
│   │   │   └── p2p_bridge_client.dart          # P2P-specific bridge calls (callP2PNodeStart, callP2PNodeStop, callP2PNodeStatus, callP2PRendezvousRegister, callP2PRendezvousDiscover, callP2PPeerDial, callP2PPeerDisconnect, callP2PMessageSend) + inbox store/retrieve + callP2PInboxRegisterToken
│   │   │
│   │   ├── config/
│   │   │   └── startup_config.dart             # StartupConfig feature flags (deferredStartupMode)
│   │   │
│   │   ├── constants/
│   │   │   └── network_constants.dart          # Rendezvous address constant
│   │   │
│   │   ├── database/
│   │   │   ├── encrypted_db_opener.dart        # SQLCipher DB open + plaintext→encrypted migration
│   │   │   ├── migrations/
│   │   │   │   ├── 001_identity_table.dart     # Schema v1 (identity, contacts, contact_requests)
│   │   │   │   ├── 002_messages_table.dart     # Schema v2 (messages table + indexes)
│   │   │   │   ├── 003_mlkem_keys.dart         # Schema v3 (ML-KEM key columns on identity, contacts, contact_requests)
│   │   │   │   ├── 004_nullify_secret_columns.dart  # Schema v4 (nullable secret columns)
│   │   │   │   ├── 005_secret_null_checks.dart      # Schema v5 (CHECK constraints + avatar_blob BLOB)
│   │   │   │   ├── 006_read_at_column.dart          # Schema v6 (read_at column on messages table)
│   │   │   │   ├── 007_archive_columns.dart         # Schema v7 (is_archived, archived_at columns on contacts)
│   │   │   │   ├── 008_block_columns.dart           # Schema v8 (is_blocked, blocked_at columns on contacts)
│   │   │   │   ├── 009_quoted_message_id.dart         # Schema v9 (quoted_message_id column on messages table)
│   │   │   │   ├── 010_media_attachments.dart         # Schema v10 (media_attachments table for image/video/audio)
│   │   │   │   └── 011_avatar_version.dart            # Schema v11 (avatar_version column on identity table)
│   │   │   └── helpers/
│   │   │       ├── identity_db_helpers.dart     # Identity table CRUD
│   │   │       ├── contacts_db_helpers.dart     # Contacts table CRUD
│   │   │       ├── contact_requests_db_helpers.dart  # Contact requests table CRUD
│   │   │       ├── messages_db_helpers.dart     # Messages table CRUD (insert, load, update status, count for contact, mark conversation read, count unread per contact, count total unread)
│   │   │       └── media_attachments_db_helpers.dart   # Media attachments table CRUD (insert, load for message/messages, update local path, update download status)
│   │   │
│   │   ├── media/
│   │   │   ├── image_processor.dart              # ImageProcessor: strips EXIF, quality compression (85 compressed/100 original), avatar resizing (512x512), injectable CompressFileFn
│   │   │   ├── media_file_manager.dart           # MediaFileManager: manages local media file paths (media/<contactPeerId>/<blobId>.<ext>), relative DB paths, absolute file I/O
│   │   │   └── video_process_result.dart         # VideoProcessResult model (path, width, height, durationMs)
│   │   │
│   │   ├── local_discovery/
│   │   │   ├── local_discovery_service.dart     # LocalPeer model + LocalChatMessage model + LocalDiscoveryService abstract interface (mDNS)
│   │   │   ├── bonsoir_discovery_service.dart   # BonsoirDiscoveryService: mDNS impl using bonsoir package (_mknoon._tcp)
│   │   │   ├── local_p2p_service.dart           # LocalP2PService: composed facade pairing mDNS discovery + WebSocket messaging
│   │   │   └── local_ws_server.dart             # LocalWsServer: local WiFi WebSocket server for direct peer messaging
│   │   │
│   │   ├── services/
│   │   │   ├── chat_message.dart               # ChatMessage canonical model (from, to, content, timestamp, isIncoming)
│   │   │   ├── chat_message_listener.dart      # ChatMessageListener: listens to routed chat messages, broadcasts to UI
│   │   │   ├── contact_request_listener.dart   # ContactRequestListener: listens to routed contact request messages, broadcasts to UI
│   │   │   ├── p2p_service.dart                # P2PService abstract interface (incl. inbox, registerInboxToken, performImmediateHealthCheck, drainOfflineInbox)
│   │   │   ├── p2p_service_impl.dart           # P2PServiceImpl with reactive streams + offline inbox + registerInboxToken + performImmediateHealthCheck + drainOfflineInbox
│   │   │   ├── incoming_message_router.dart    # Routes P2P messages by type to typed streams + onError/onDone stream handlers
│   │   │   └── pending_message_retrier.dart    # PendingMessageRetrier: auto-retries failed messages on P2P reconnect (5s debounce)
│   │   │
│   │   ├── theme/
│   │   │   ├── app_colors.dart                 # Color constants (dark theme)
│   │   │   ├── feed_colors.dart                 # Feed color palette: purple (#a78bfa) + teal (#81e6d9) accents, card surfaces, message bubbles, border tints
│   │   │   ├── app_theme.dart                  # ThemeData configuration
│   │   │   └── glassmorphism.dart              # GlassmorphicContainer widget
│   │   │
│   │   ├── secure_storage/
│   │   │   ├── secure_key_store.dart           # SecureKeyStore abstract interface (read, write, delete, containsKey)
│   │   │   ├── flutter_secure_key_store.dart   # Production impl (iOS Keychain / Android EncryptedSharedPreferences)
│   │   │   └── migrate_secrets_to_secure_storage.dart  # One-time DB→secure storage migration with sentinel
│   │   │
│   │   └── utils/
│   │       ├── flow_event_emitter.dart         # Structured logging utility
│   │       ├── key_conversion.dart             # base64 ↔ hex key conversion
│   │       ├── ring_avatar_spec.dart           # Ring avatar constants + data models
│   │       ├── ring_avatar_generator.dart      # Deterministic avatar from peerId (DJB2 hash)
│   │       ├── chat_console_logger.dart        # Chat message debug logging with shortened IDs
│   │       └── startup_timing.dart             # StartupTiming: lightweight startup milestone timing utility (debug only)
│   │
│   └── features/
│       ├── home/
│       │   └── presentation/
│       │       ├── screens/
│       │       │   ├── first_time_experience_screen.dart   # Pure UI (staggered animations)
│       │       │   └── first_time_experience_wired.dart    # Business logic + CR listener + avatar blob storage + onError/onDone stream handlers
│       │       └── widgets/
│       │           ├── profile_avatar_widget.dart           # Avatar display (Image.memory) + camera button
│       │           ├── user_avatar.dart                    # User avatar displaying ring or photo
│       │           ├── editable_username_widget.dart        # Tap-to-edit username
│       │           ├── qr_code_section.dart                 # QR code with green glow
│       │           ├── scan_friend_card.dart                # Glassmorphic scan action card
│       │           ├── empty_circle_state.dart              # Pulsing dashed circles
│       │           ├── ring_avatar.dart                     # RingAvatar widget (peerId → avatar)
│       │           └── ring_avatar_painter.dart             # CustomPainter canvas renderer
│       │
│       ├── feed/
│       │   ├── domain/
│       │   │   ├── models/
│       │   │   │   ├── feed_item.dart                       # FeedItem base + ConnectionFeedItem + ThreadMessage + ThreadFeedItem (thread-based feed with ConversationState enum: unread, active, replied, read)
│       │   │   │   └── session_reply.dart                     # SessionReply model + SessionReplyTracker for per-contact session-local reply tracking
│       │   │   └── utils/
│       │   │       ├── format_message_time.dart             # Message timestamp formatting + relative time ("2m ago")
│       │   │       ├── group_messages_into_threads.dart     # Groups messages into ThreadFeedItems by contact and 24-hour time gap, derives ConversationState, includes sent+received, blocked status, quotedMessageId propagation
│       │   │       ├── has_significant_time_gap.dart        # Detects 2+ hour gaps or AM/PM boundary crossings between timestamps
│       │   │       └── split_thread_by_time_gap.dart      # Splits message list into thread chunks by 24-hour gaps with burst handling and reply soft-close
│       │   ├── application/
│       │   │   └── load_feed_use_case.dart                  # Load initial feed from DB (contacts + latest messages + unread counts per contact)
│       │   └── presentation/
│       │       ├── screens/
│       │       │   ├── feed_screen.dart                     # Pure UI feed display
│       │       │   └── feed_wired.dart                      # Feed business logic + CR/chat listeners + orbit navigation + passes unread counts, total unread badge on nav bar + onError/onDone stream handlers
│       │       ├── widgets/
│       │       │   ├── feed_header.dart                     # Sticky header (username + avatar from memory bytes)
│       │       │   ├── feed_navigation_bar.dart             # Bottom glass nav bar (3 tabs) + total unread badge on feed tab
│       │       │   ├── nav_bar_button.dart                  # Individual nav button widget + badge overlay support
│       │       │   ├── connection_card.dart                 # Contact connection card (inline green badge)
│       │       │   ├── feed_card.dart                     # Auto-selects open/collapsed mode based on ConversationState; flat glassmorphic card with purple/teal accent
│       │       │   ├── collapsed_mode_card_body.dart      # Collapsed mode: friend header, single-line preview, optional reply indicator, "Continue..." inline input
│       │       │   ├── open_mode_card_body.dart           # Open mode: friend header, scrollable unread message preview, inline reply input
│       │       │   ├── expanded_compose_input.dart        # Multi-line auto-growing compose input for expanded thread cards
│       │       │   ├── inline_reply_input.dart            # Inline reply composer for collapsed/open card modes
│       │       │   ├── scrollable_message_preview.dart    # Scrollable preview of messages in open mode card
│       │       │   ├── message_bubble.dart                  # Individual message bubble within expanded thread (text + timestamp, unread highlight)
│       │       │   ├── swipe_to_quote_bubble.dart         # Swipe-to-quote interaction on message bubbles
│       │       │   ├── quote_preview_bar.dart             # Preview of quoted message in compose area
│       │       │   ├── view_earlier_link.dart             # Link to view earlier messages in conversation
│       │       │   ├── more_messages_hint.dart            # Hint indicating more messages available
│       │       │   ├── replied_indicator.dart             # "You replied" indicator on feed cards
│       │       │   ├── session_divider.dart                 # "PREVIOUSLY SEEN" divider between unread and read thread cards
│       │       │   ├── time_gap_divider.dart                # Thin time-label divider between messages with significant time gaps
│       │       │   ├── unread_count_badge.dart              # Circular unread count badge widget
│       │       │   └── checkmark_burst_animation.dart       # Animated checkmark with rings (unused/orphaned)
│       │       └── navigation/
│       │           └── feed_route_transition.dart            # Slide-up route transition
│       │
│       ├── conversation/
│       │   ├── domain/
│       │   │   ├── models/
│       │   │   │   ├── conversation_message.dart            # ConversationMessage (id, text, status, isIncoming, readAt, quotedMessageId, media list)
│       │   │   │   ├── media_attachment.dart                # MediaAttachment (id, messageId, mime, size, mediaType, width, height, durationMs, localPath, downloadStatus, createdAt)
│       │   │   │   └── message_payload.dart                 # Wire-format envelope model (chat_message type, supports quoted messages and media attachments)
│       │   │   └── repositories/
│       │   │       ├── message_repository.dart              # Abstract interface (save, load, update status, count for contact, markConversationAsRead, getUnreadCountForContact, getTotalUnreadCount)
│       │   │       ├── message_repository_impl.dart         # DB-backed implementation (incl. getMessageCountForContact, markConversationAsRead, getUnreadCountForContact, getTotalUnreadCount)
│       │   │       ├── media_attachment_repository.dart      # Abstract interface (save, load for message/messages, update local path, update download status, delete for message/contact, get pending downloads)
│       │   │       └── media_attachment_repository_impl.dart # DB-backed implementation
│       │   ├── application/
│       │   │   ├── send_chat_message_use_case.dart          # Send message with 3x retry, inbox fallback + optimistic persist
│       │   │   ├── handle_incoming_chat_message_use_case.dart  # Parse, validate sender, detect name changes
│       │   │   ├── load_conversation_use_case.dart          # Load all messages for a contact
│       │   │   ├── mark_conversation_read_use_case.dart     # Mark all unread messages for a contact as read
│       │   │   ├── retry_failed_messages_use_case.dart      # Retry all failed outgoing messages (loads identity, queries failed, re-sends via sendChatMessage)
│       │   │   ├── upload_media_use_case.dart          # Upload media to relay, store locally, create MediaAttachment records
│       │   │   ├── download_media_use_case.dart        # Download media from relay to local device
│       │   │   └── chat_message_listener.dart               # Background listener for chat_message stream + onError/onDone stream handlers
│       │   └── presentation/
│       │       ├── screens/
│       │       │   ├── conversation_screen.dart             # Pure UI: header, letter cards, compose area
│       │       │   └── conversation_wired.dart              # Business logic: load, send, listen, optimistic UI, marks conversation as read on load and on incoming messages + onError/onDone stream handlers
│       │       ├── widgets/
│       │       │   ├── letter_card.dart                     # Full-width message card (left/right accent, queued/delivered status)
│       │       │   ├── compose_area.dart                    # Auto-growing text field + send button
│       │       │   ├── attachment_preview_strip.dart    # Preview strip for pending media attachments
│       │       │   ├── empty_conversation_state.dart        # Breathing glow avatar + connection info
│       │       │   ├── conversation_header.dart             # Frosted-glass header with back + contact info
│       │       │   ├── compact_origin_marker.dart           # Compact connection origin at conversation top
│       │       │   ├── date_separator.dart                  # Date divider between letter cards
│       │       │   └── blocked_banner.dart                  # Banner with block icon + "Unblock" button (replaces compose area when contact blocked)
│       │       └── navigation/
│       │           └── conversation_route_transition.dart    # Slide-up route transition (420ms)
│       │
│       ├── orbit/
│       │   ├── domain/
│       │   │   └── models/
│       │   │       └── orbit_friend.dart                    # Composite model: contact + messageCount + lastActivity + unreadCount
│       │   ├── application/
│       │   │   └── load_orbit_data_use_case.dart            # Top-level function: loads contacts with message counts + unread counts, sorted desc
│       │   └── presentation/
│       │       ├── screens/
│       │       │   ├── orbit_screen.dart                    # StatelessWidget: pure UI layout with 4-layer Stack
│       │       │   └── orbit_wired.dart                     # StatefulWidget: state, 3 animation controllers, streams, DI (8 deps) + onError/onDone stream handlers
│       │       ├── widgets/
│       │       │   ├── orbital_visualization.dart           # 320x320 Stack: rings + center + friend avatars + overflow badge
│       │       │   ├── orbital_ring_painter.dart            # CustomPainter: 2 dashed concentric circles (teal + purple)
│       │       │   ├── orbital_avatar.dart                  # Positioned avatar on ring with staggered scale-in animation
│       │       │   ├── overflow_badge.dart                  # "+N" circle badge on outer ring (1000ms delayed entrance)
│       │       │   ├── orbit_close_button.dart              # 36x36 glass circle X button with BackdropFilter
│       │       │   ├── orbit_header.dart                    # Right-aligned user avatar (44px)
│       │       │   ├── friends_list_header.dart             # "Friends" title + My QR / Scan pill buttons
│       │       │   ├── friend_row.dart                      # Glassmorphic tappable friend card + AnimatedFriendRow wrapper + unread count badge
│       │       │   ├── swipeable_friend_row.dart            # Swipeable wrapper with slide-to-reveal action buttons (Block/Unblock + Delete + Archive/Unarchive)
│       │       │   ├── swipe_action_buttons.dart            # BlockActionButton, UnblockActionButton, DeleteActionButton, ArchiveActionButton, UnarchivePillButton
│       │       │   ├── friends_filter_toggle.dart           # Segmented filter toggle: "All (N)" / "Archived (N)" with count badges
│       │       │   ├── archived_empty_state.dart            # Empty state for archived tab (no archived friends)
│       │       │   ├── confirmation_dialog.dart             # Confirmation dialog with title, description, and danger action button
│       │       │   ├── qr_action_cards.dart                 # Two side-by-side bottom QR cards (unused/created but removed from screen)
│       │       │   ├── orbit_search_trigger.dart            # Floating glass pill at bottom (search + close)
│       │       │   └── orbit_search_dock.dart               # Bottom-docked search input panel with native keyboard
│       │       └── navigation/
│       │           └── orbit_route_transition.dart           # Slide-up route (matches conversation pattern, 420ms)
│       │
│       ├── push/
│       │   └── application/
│       │       ├── background_message_handler.dart          # Firebase background message handler (@pragma('vm:entry-point')) + inbox drain deferral note
│       │       ├── request_push_permission_use_case.dart    # Push permission request utility
│       │       └── register_push_token_use_case.dart        # Register FCM token with relay server via P2P inbox protocol
│       │
│       ├── settings/
│       │   ├── domain/
│       │   │   └── models/
│       │   │       └── image_quality_preference.dart       # ImageQualityPreference enum (compressed quality 85 / original quality 100)
│       │   ├── application/
│       │   │   ├── image_quality_preference_use_cases.dart # Get/set image quality preference from SecureKeyStore
│       │   │   ├── video_quality_preference_use_cases.dart # Get/set video quality preference
│       │   │   ├── upload_profile_picture_use_case.dart    # Upload avatar to relay, update identity avatarVersion, broadcast profile_update to contacts
│       │   │   ├── download_profile_picture_use_case.dart  # Download contact's profile picture from relay
│       │   │   └── profile_update_listener.dart            # Listener for incoming profile_update messages
│       │   └── presentation/
│       │       ├── screens/
│       │       │   ├── settings_screen.dart                # Pure UI settings screen (profile, peer ID, recovery phrase, image quality toggle)
│       │       │   └── settings_wired.dart                 # Settings business logic + state management
│       │       ├── navigation/
│       │       │   └── settings_route_transition.dart      # Slide-up route transition
│       │       └── widgets/
│       │           ├── settings_profile_section.dart       # Profile section with avatar and username
│       │           ├── settings_peer_id_card.dart          # Peer ID display card with copy button
│       │           ├── settings_recovery_phrase_card.dart  # Recovery phrase card (reveal/hide/copy)
│       │           └── image_quality_toggle.dart           # Toggle for image quality preference
│       │
│       ├── identity/
│       │   ├── domain/
│       │   │   ├── models/
│       │   │   │   └── identity_model.dart                 # IdentityModel (peerId, keys, mnemonic, avatarBlob, avatarVersion, etc.)
│       │   │   └── repositories/
│       │   │       ├── identity_repository.dart            # Abstract interface
│       │   │       └── identity_repository_impl.dart       # DB-backed impl + SecureKeyStore for secrets
│       │   ├── application/
│       │   │   ├── startup_decision.dart                   # decideStartupRoute() use case (3-way)
│       │   │   ├── generate_identity_use_case.dart         # generateNewIdentity() use case
│       │   │   └── restore_identity_use_case.dart          # restoreIdentityFromMnemonic() use case
│       │   └── presentation/
│       │       ├── startup_router.dart                     # Routes to feed, home, or onboarding + push token registration after P2P node starts
│       │       ├── screens/
│       │       │   ├── identity_choice_screen.dart         # "I'm new" / "Load my key" UI
│       │       │   ├── identity_choice_wired.dart          # Choice screen business logic
│       │       │   ├── mnemonic_input_screen.dart          # Recovery phrase input UI
│       │       │   └── mnemonic_input_wired.dart           # Mnemonic input business logic
│       │       └── widgets/
│       │           ├── ambient_background.dart             # Animated glow background
│       │           ├── brand_header.dart                   # Logo/title header
│       │           ├── choice_card.dart                    # Glassmorphic tappable card
│       │           └── identity_loading_card.dart          # Branded loading overlay for identity generation/restore (stage-based text transitions)
│       │
│       ├── qr_code/
│       │   ├── domain/
│       │   │   └── models/
│       │   │       └── qr_payload_model.dart               # QR payload Dart model
│       │   ├── application/
│       │   │   ├── build_qr_payload_use_case.dart          # Build signed QR payload
│       │   │   └── parse_qr_payload_use_case.dart          # Validate scanned QR (sig, expiry, self)
│       │   └── presentation/
│       │       ├── screens/
│       │       │   ├── qr_display_screen.dart              # Full-screen QR display + long-press copy (debug)
│       │       │   ├── qr_display_wired.dart               # QR display business logic
│       │       │   ├── qr_scanner_screen.dart              # Camera scanner UI (mobile_scanner)
│       │       │   └── qr_scanner_wired.dart               # Scanner logic: parse, add, send request
│       │       └── widgets/
│       │           └── scan_overlay.dart                    # Canvas overlay with corner markers
│       │
│       ├── contacts/
│       │   ├── domain/
│       │   │   ├── models/
│       │   │   │   └── contact_model.dart                  # ContactModel (from QR or P2P, incl. avatarPath, avatarVersion)
│       │   │   └── repositories/
│       │   │       ├── contact_repository.dart             # Abstract interface
│       │   │       └── contact_repository_impl.dart        # DB-backed implementation
│       │   └── application/
│       │       ├── add_contact_use_case.dart                # Add contact with duplicate check
│       │       ├── archive_contact_use_case.dart            # Archive contact (hide from active list, preserve messages)
│       │       ├── unarchive_contact_use_case.dart          # Unarchive contact (restore to active list)
│       │       ├── block_contact_use_case.dart              # Block contact (prevent messages)
│       │       ├── unblock_contact_use_case.dart            # Unblock contact (allow messages again)
│       │       └── delete_contact_use_case.dart             # Delete contact and all their messages
│       │
│       ├── contact_request/
│       │   ├── domain/
│       │   │   ├── models/
│       │   │   │   └── contact_request_model.dart          # ContactRequestModel + status enum
│       │   │   └── repositories/
│       │   │       ├── contact_request_repository.dart     # Abstract interface (6 methods)
│       │   │       └── contact_request_repository_impl.dart
│       │   ├── application/
│       │   │   ├── send_contact_request_use_case.dart      # Build, sign, discover, dial, send (3x retry)
│       │   │   ├── accept_contact_request_use_case.dart    # Convert request → contact
│       │   │   ├── decline_contact_request_use_case.dart   # Update status to declined
│       │   │   ├── handle_incoming_message_use_case.dart   # Parse, validate sig, store request
│       │   │   └── contact_request_listener.dart           # Background P2P message listener service + onError/onDone stream handlers
│       │   └── presentation/
│       │       └── widgets/
│       │           ├── contact_request_dialog.dart          # Accept/Decline modal with RingAvatar
│       │           └── pending_requests_badge.dart          # Circular count badge (99+ max)
│       │
│       └── p2p/
│           ├── domain/
│           │   └── models/
│           │       ├── node_state.dart                     # NodeState (isStarted, connections, addresses)
│           │       ├── connection_state.dart                # ConnectionState (peerId, direction, status)
│           │       ├── discovered_peer.dart                 # DiscoveredPeer (id, addresses)
│           │       ├── chat_message.dart                    # ChatMessage (from, to, content, isIncoming)
│           │       └── send_message_result.dart             # SendMessageResult enum
│           ├── application/
│           │   ├── start_node_use_case.dart                 # Start P2P node with identity
│           │   ├── stop_node_use_case.dart                  # Stop running node
│           │   ├── send_message_use_case.dart               # Send message to peer
│           │   └── discover_peer_use_case.dart              # Discover + dial peer via rendezvous
│           └── presentation/
│               └── widgets/
│                   └── connection_status_indicator.dart     # Online/Offline status badge
│
│   └── shared/
│       └── widgets/
│           └── media/
│               ├── media_grid.dart                    # Grid layout for image/video attachments (1-4+ item layouts)
│               ├── media_grid_cell.dart               # Single grid cell for media with tap handling
│               ├── media_display_helpers.dart          # Constants (mediaGridGap, mediaGridContainerRadius) + formatDurationMs()
│               ├── media_preview_text.dart             # Text preview for media attachments
│               ├── full_screen_image_viewer.dart       # Full-screen image viewer with pinch-to-zoom
│               ├── video_thumbnail_overlay.dart        # Play icon overlay for video thumbnails
│               └── audio_player_widget.dart            # Audio player widget for audio attachments
│
├── go-mknoon/                                             # Go native library (gomobile → .xcframework / .aar)
│   ├── go.mod                                             # Go module definition + dependencies
│   ├── go.sum                                             # Dependency checksums
│   ├── Makefile                                           # Build targets: ios, android, all (gomobile bind)
│   ├── tools.go                                           # Blank import to keep golang.org/x/mobile in go.mod for gomobile bind
│   ├── bridge/
│   │   ├── bridge.go                                      # Go bridge entry: exported functions (GenerateIdentity, RestoreIdentity, HandleCommand, etc.) dispatching to identity/crypto/node/media/profile packages
│   │   ├── events.go                                      # EventCallback interface for Go → Flutter push events (message:received, peer:connected, peer:disconnected, addresses:updated)
│   │   └── bridge_test.go                                 # Bridge unit tests
│   ├── identity/
│   │   ├── identity.go                                    # GenerateIdentity + RestoreIdentity (BIP39 + Ed25519 + libp2p peer ID)
│   │   └── identity_test.go                               # Identity unit tests
│   ├── crypto/
│   │   ├── sign.go                                        # Ed25519 SignPayload + VerifyPayload
│   │   ├── mlkem.go                                       # ML-KEM-768 key pair generation (cloudflare/circl)
│   │   ├── encrypt.go                                     # ML-KEM encapsulate + AES-256-GCM encrypt
│   │   ├── decrypt.go                                     # ML-KEM decapsulate + AES-256-GCM decrypt
│   │   ├── sign_test.go                                   # Sign/verify unit tests
│   │   ├── signature_test.go                              # Signature round-trip tests
│   │   ├── mlkem_test.go                                  # ML-KEM keygen/encrypt/decrypt tests
│   │   └── interop_test.go                                # Cross-platform interop tests (uses testdata/interop_vectors.json)
│   ├── internal/
│   │   └── envelope.go                                    # V1Envelope (plaintext) + V2Envelope (encrypted) wire format structs + ParseEnvelopeVersion
│   ├── node/
│   │   ├── node.go                                        # libp2p Node: start/stop, relay circuit, peer dial, message send/receive, event subscription
│   │   ├── config.go                                      # Constants: relay addresses, protocol IDs, timeouts, NodeConfig struct
│   │   ├── inbox.go                                       # Offline inbox: store/retrieve/register-token via relay server protocol
│   │   ├── media.go                                     # Media upload/download protocol: upload, download, delete, list + profile_upload, profile_download
│   │   ├── rendezvous.go                                  # Rendezvous register/discover via relay server protocol
│   │   └── node_test.go                                   # Node unit tests
│   ├── integration/
│   │   ├── relay_test.go                                  # Integration test: relay connectivity (build tag: integration)
│   │   └── profile_test.go                              # Profile upload/download integration tests
│   ├── stub/
│   │   └── gosigar/                                       # gosigar stub for iOS (can't use libproc.h)
│   │       ├── sigar.go                                   # Stub Mem struct with zero values
│   │       └── go.mod                                     # Stub module definition
│   └── testdata/
│       └── interop_vectors.json                           # Cross-platform test vectors for identity/crypto
│
├── integration_test/
│   ├── smoke_test.dart                                    # Integration smoke test
│   ├── conversation_bridge_test.dart                      # Full DI stack conversation test
│   └── feed_performance_test.dart                         # Feed performance benchmarks
│
├── test/
│   ├── core/
│   │   ├── bridge/
│   │   │   ├── go_bridge_client_test.dart                 # GoBridgeClient unit tests
│   │   │   └── bridge_helpers_test.dart                   # Bridge helper function tests
│   │   ├── database/
│   │   │   ├── helpers/
│   │   │   │   └── media_attachments_db_helpers_test.dart  # Media attachment DB tests
│   │   │   └── migrations/
│   │   │       └── 010_media_attachments_test.dart         # Media attachments migration test
│   │   ├── local_discovery/
│   │   │   ├── fake_local_discovery_service.dart           # In-memory test fake for LocalDiscoveryService
│   │   │   ├── fake_local_p2p_service.dart                # In-memory test fake for LocalP2PService
│   │   │   ├── local_ws_server_test.dart                  # LocalWsServer unit tests
│   │   │   └── local_p2p_service_test.dart                # LocalP2PService unit tests
│   │   ├── media/
│   │   │   ├── image_processor_test.dart                   # Image processing tests
│   │   │   ├── media_file_manager_test.dart                # Media file management tests
│   │   │   └── video_process_result_test.dart              # Video process result model tests
│   │   ├── services/
│   │   │   ├── incoming_message_router_test.dart           # IncomingMessageRouter unit tests
│   │   │   ├── incoming_message_router_profile_test.dart   # Profile message routing tests
│   │   │   └── p2p_service_addresses_updated_test.dart     # P2P address update tests
│   │   ├── theme/
│   │   │   └── feed_colors_test.dart                       # Feed color palette tests
│   │   └── secure_storage/
│   │       ├── fake_secure_key_store.dart                  # In-memory test fake
│   │       └── migrate_secrets_to_secure_storage_test.dart # Migration unit tests
│   └── features/
│       ├── identity/
│       │   └── application/
│       │       ├── generate_identity_use_case_test.dart    # Identity generation tests
│       │       └── restore_identity_use_case_test.dart     # Identity restore tests
│       ├── qr_code/
│       │   └── application/
│       │       ├── build_qr_payload_use_case_test.dart     # QR payload build tests
│       │       └── parse_qr_payload_use_case_test.dart     # QR payload parse tests
│       ├── contacts/
│       │   ├── domain/
│       │   │   ├── models/
│       │   │   │   └── contact_model_test.dart             # ContactModel serialization tests
│       │   │   └── repositories/
│       │   │       └── contact_repository_impl_test.dart   # ContactRepositoryImpl unit tests
│       │   └── application/
│       │       ├── archive_contact_use_case_test.dart      # Archive contact tests
│       │       ├── unarchive_contact_use_case_test.dart    # Unarchive contact tests
│       │       ├── block_contact_use_case_test.dart        # Block contact tests
│       │       ├── unblock_contact_use_case_test.dart      # Unblock contact tests
│       │       └── delete_contact_use_case_test.dart       # Delete contact tests
│       ├── contact_request/
│       │   └── application/
│       │       ├── send_contact_request_use_case_test.dart # Send contact request tests
│       │       └── handle_incoming_message_use_case_test.dart # Handle incoming message tests
│       ├── feed/
│       │   ├── application/
│       │   │   └── load_feed_use_case_test.dart            # Feed loading tests
│       │   ├── domain/
│       │   │   ├── models/
│       │   │   │   ├── feed_item_test.dart                 # FeedItem model tests
│       │   │   │   └── session_reply_test.dart             # Session reply model tests
│       │   │   └── utils/
│       │   │       ├── format_message_time_test.dart       # Time formatting tests
│       │   │       ├── group_messages_into_threads_test.dart # Thread grouping tests
│       │   │       ├── has_significant_time_gap_test.dart  # Time gap detection tests
│       │   │       └── split_thread_by_time_gap_test.dart  # Thread splitting tests
│       │   ├── presentation/
│       │   │   └── widgets/
│       │   │       ├── feed_card_test.dart                  # Feed card mode tests
│       │   │       ├── collapsed_mode_card_body_test.dart   # Collapsed card body tests
│       │   │       ├── open_mode_card_body_test.dart        # Open card body tests
│       │   │       ├── message_bubble_test.dart             # Message bubble tests
│       │   │       ├── scrollable_message_preview_test.dart # Scrollable preview tests
│       │   │       ├── more_messages_hint_test.dart         # More messages hint tests
│       │   │       ├── view_earlier_link_test.dart          # View earlier link tests
│       │   │       └── replied_indicator_test.dart          # Replied indicator tests
│       │   └── integration/
│       │       ├── feed_card_flow_test.dart                 # Feed card state flow integration test
│       │       └── feed_color_smoke_test.dart               # Feed color smoke test
│       ├── conversation/
│       │   ├── integration/
│       │   │   └── two_user_message_exchange_test.dart    # Integration: full send/receive flow
│       │   ├── application/
│       │   │   ├── send_chat_message_use_case_test.dart
│       │   │   ├── handle_incoming_chat_message_use_case_test.dart
│       │   │   ├── load_conversation_use_case_test.dart
│       │   │   ├── chat_message_listener_test.dart         # ChatMessageListener tests
│       │   │   ├── download_media_use_case_test.dart       # Download media tests
│       │   │   └── upload_media_use_case_test.dart         # Upload media tests
│       │   ├── domain/
│       │   │   ├── models/
│       │   │   │   ├── conversation_message_test.dart
│       │   │   │   ├── message_payload_test.dart
│       │   │   │   └── media_attachment_test.dart          # MediaAttachment model tests
│       │   │   └── repositories/
│       │   │       ├── message_repository_impl_test.dart
│       │   │       └── media_attachment_repository_impl_test.dart  # Media attachment repo tests
│       │   └── presentation/
│       │       ├── screens/
│       │       │   ├── conversation_screen_test.dart
│       │       │   └── conversation_wired_test.dart
│       │       └── widgets/
│       │           ├── blocked_banner_test.dart
│       │           ├── empty_conversation_state_test.dart
│       │           ├── compact_origin_marker_test.dart
│       │           ├── conversation_header_test.dart
│       │           ├── letter_card_test.dart
│       │           ├── date_separator_test.dart
│       │           ├── compose_area_test.dart
│       │           └── attachment_preview_strip_test.dart  # Attachment preview tests
│       ├── orbit/
│       │   ├── application/
│       │   │   └── load_orbit_data_use_case_test.dart      # Orbit data loading tests
│       │   └── presentation/
│       │       └── widgets/
│       │           ├── archived_empty_state_test.dart       # Archived empty state widget tests
│       │           ├── confirmation_dialog_test.dart        # Confirmation dialog tests
│       │           ├── friend_row_test.dart                 # Friend row widget tests
│       │           ├── friends_filter_toggle_test.dart      # Filter toggle widget tests
│       │           └── swipeable_friend_row_test.dart       # Swipeable friend row tests
│       └── settings/
│           ├── domain/
│           │   └── models/
│           │       └── image_quality_preference_test.dart      # Image quality preference model tests
│           ├── application/
│           │   ├── image_quality_preference_use_cases_test.dart # Image quality use case tests
│           │   ├── video_quality_preference_use_cases_test.dart # Video quality use case tests
│           │   └── profile_update_listener_test.dart           # Profile update listener tests
│           └── presentation/
│               ├── widgets/
│               │   ├── settings_peer_id_card_test.dart         # Peer ID card tests
│               │   ├── settings_recovery_phrase_card_test.dart  # Recovery phrase card tests
│               │   ├── settings_profile_section_test.dart       # Profile section tests
│               │   └── image_quality_toggle_test.dart           # Image quality toggle tests
│               └── screens/
│                   ├── settings_screen_test.dart               # Settings screen tests
│                   └── settings_wired_test.dart                # Settings wired tests
│
├── android/
│   └── app/
│       └── src/
│           └── main/
│               ├── kotlin/.../MainActivity.kt               # Android main activity
│               ├── kotlin/.../GoBridge.kt                   # Android platform wrapper: MethodChannel/EventChannel → Go library (32 methods including media and profile operations)
│               └── res/
│                   └── xml/
│                       ├── backup_rules.xml               # Android <12 backup rules (exclude all)
│                       └── data_extraction_rules.xml      # Android 12+ extraction rules (exclude all)
│
├── ios/
│   └── Runner/
│       ├── AppDelegate.swift                              # iOS app delegate
│       └── GoBridge.swift                                 # iOS platform wrapper: MethodChannel/EventChannel → Go .xcframework (32 methods including media and profile operations)
│
├── pubspec.yaml                                           # Flutter dependencies (sqflite_sqlcipher, sqlcipher_flutter_libs, flutter_secure_storage, firebase_core, firebase_messaging, bonsoir, video_compress, just_audio)
├── rendezvous-relay-server-inbox-v5.js                    # Relay server v5 (libp2p relay + rendezvous + offline inbox)
├── C4_MODEL.md                                            # C4 architecture documentation
└── file-structure.md                                      # This file
```

---

## Feature → File Mapping

### Identity (M1)

| Component | File(s) | Description |
|-----------|---------|-------------|
| Identity model | `identity_model.dart` | Immutable data class (peerId, keys, mnemonic, username, avatarBlob, avatarVersion, mlKemPublicKey?, mlKemSecretKey?) |
| Identity repository | `identity_repository.dart`, `identity_repository_impl.dart` | Load/save identity, SecureKeyStore for secrets |
| Generate identity | `generate_identity_use_case.dart` | Go bridge call + DB save |
| Restore identity | `restore_identity_use_case.dart` | Validate mnemonic + Go bridge + DB save |
| Startup routing | `startup_decision.dart`, `startup_router.dart` | Check identity + contacts → route to feed, home, or onboarding + push token registration after P2P node starts |
| Startup config | `startup_config.dart` | Feature flags for startup behavior (deferredStartupMode) |
| Startup timing | `startup_timing.dart` | Lightweight debug-only startup milestone timing |
| Encrypted DB opener | `encrypted_db_opener.dart` | SQLCipher DB open + plaintext→encrypted migration |
| Secure key store | `secure_key_store.dart`, `flutter_secure_key_store.dart` | Abstract interface + production impl (iOS Keychain / Android EncryptedSharedPreferences) |
| Secrets migration | `migrate_secrets_to_secure_storage.dart` | One-time DB→secure storage migration with sentinel |
| DB migration | `001_identity_table.dart` | Creates identity, contacts, contact_requests tables |
| DB helpers | `identity_db_helpers.dart` | Identity table CRUD |
| Bridge | `bridge.dart`, `go_bridge_client.dart` | Flutter ↔ Go native communication (identity, signing, ML-KEM encryption/decryption) via MethodChannel/EventChannel + checkHealth(), reinitialize() + helper functions (callIdentityGenerate, callIdentityRestore, callSignPayload, callVerifyPayload, callMlKemKeygen, callEncryptMessage, callDecryptMessage) |
| Loading overlay | `identity_loading_card.dart` | Branded loading card for identity generation/restore with stage-based text transitions |

### QR Code (M2)

| Component | File(s) | Description |
|-----------|---------|-------------|
| QR payload model | `qr_payload_model.dart` | Dart model for QR JSON |
| Build QR | `build_qr_payload_use_case.dart` | Create signed QR payload |
| Parse QR | `parse_qr_payload_use_case.dart` | Validate scanned QR (sig, expiry, self-scan) |
| QR display | `qr_display_screen.dart`, `qr_display_wired.dart` | Show QR code UI + long-press copy (debug) |
| QR scanner | `qr_scanner_screen.dart`, `qr_scanner_wired.dart` | Camera scan + process |
| Scan overlay | `scan_overlay.dart` | Canvas overlay with corner markers |
| Go signing | `crypto/sign.go` | `payload.sign` + `payload.verify` handlers (both in one file) |

### P2P Networking

| Component | File(s) | Description |
|-----------|---------|-------------|
| P2P service | `p2p_service.dart`, `p2p_service_impl.dart` | Reactive P2P interface + implementation with offline inbox + registerInboxToken + performImmediateHealthCheck + drainOfflineInbox |
| P2P bridge | `p2p_bridge_client.dart` | Low-level Go bridge calls for P2P + inbox store/retrieve + callP2PInboxRegisterToken |
| Message router | `incoming_message_router.dart` | Routes P2P messages by envelope type to typed streams + onError/onDone stream handlers |
| Chat message (core) | `core/services/chat_message.dart` | ChatMessage canonical model (from, to, content, timestamp, isIncoming) with factory constructors |
| Chat message listener | `core/services/chat_message_listener.dart` | Listens to routed chat messages, broadcasts to UI layer |
| Contact request listener | `core/services/contact_request_listener.dart` | Listens to routed contact request messages, broadcasts to UI layer |
| Pending message retrier | `pending_message_retrier.dart` | Auto-retries failed outgoing messages on P2P reconnect (5s debounce) |
| Node state | `node_state.dart` | P2P node state model |
| Connection state | `connection_state.dart` | Active connection model |
| Discovered peer | `discovered_peer.dart` | Peer discovery result model |
| Chat message (P2P) | `p2p/domain/models/chat_message.dart` | P2P message model |
| Send result | `send_message_result.dart` | SendMessageResult enum |
| Start node | `start_node_use_case.dart` | Start node with identity key |
| Stop node | `stop_node_use_case.dart` | Stop running node |
| Send message | `send_message_use_case.dart` | Send P2P message |
| Discover peer | `discover_peer_use_case.dart` | Discover + dial via rendezvous |
| Status indicator | `connection_status_indicator.dart` | Online/Offline UI badge |

### Local Discovery (WiFi)

| Component | File(s) | Description |
|-----------|---------|-------------|
| Discovery models | `local_discovery_service.dart` | LocalPeer + LocalChatMessage models + LocalDiscoveryService abstract interface |
| Bonsoir discovery | `bonsoir_discovery_service.dart` | mDNS-based impl using bonsoir package (_mknoon._tcp service type) |
| Local P2P service | `local_p2p_service.dart` | Composed facade pairing mDNS discovery + WebSocket messaging |
| WebSocket server | `local_ws_server.dart` | Local WiFi WebSocket server for direct peer-to-peer messaging (pooled connections, idle timeout) |

### Contacts

| Component | File(s) | Description |
|-----------|---------|-------------|
| Contact model | `contact_model.dart` | Contact data (from QR scan or P2P, incl. mlKemPublicKey?, avatarPath, avatarVersion) |
| Contact repository | `contact_repository.dart`, `contact_repository_impl.dart` | CRUD for contacts |
| Add contact | `add_contact_use_case.dart` | Add with duplicate check |
| Archive contact | `archive_contact_use_case.dart` | Archive contact (hide from active list, preserve messages) |
| Unarchive contact | `unarchive_contact_use_case.dart` | Restore contact to active list |
| Block contact | `block_contact_use_case.dart` | Block contact (prevent messages) |
| Unblock contact | `unblock_contact_use_case.dart` | Unblock contact (allow messages again) |
| Delete contact | `delete_contact_use_case.dart` | Delete contact and all their messages |
| DB helpers | `contacts_db_helpers.dart` | Contacts table CRUD |

### Contact Requests

| Component | File(s) | Description |
|-----------|---------|-------------|
| Request model | `contact_request_model.dart` | Request data + status enum (incl. mlKemPublicKey?) |
| Request repository | `contact_request_repository.dart`, `contact_request_repository_impl.dart` | CRUD for requests |
| Send request | `send_contact_request_use_case.dart` | Build, sign, discover, dial, send (3x retry) |
| Accept request | `accept_contact_request_use_case.dart` | Convert request → contact |
| Decline request | `decline_contact_request_use_case.dart` | Update status to declined |
| Handle incoming | `handle_incoming_message_use_case.dart` | Parse P2P message, validate, store |
| Listener service | `contact_request_listener.dart` | Background P2P message monitor + onError/onDone stream handlers |
| Request dialog | `contact_request_dialog.dart` | Accept/Decline modal UI |
| Requests badge | `pending_requests_badge.dart` | Count badge widget |
| DB helpers | `contact_requests_db_helpers.dart` | Contact requests table CRUD |

### Conversation (UI-4)

| Component | File(s) | Description |
|-----------|---------|-------------|
| Message model | `conversation_message.dart` | ConversationMessage (id, text, status, isIncoming, readAt, quotedMessageId, media list) |
| Media attachment model | `media_attachment.dart` | MediaAttachment (id, messageId, mime, size, mediaType, width, height, durationMs, localPath, downloadStatus, createdAt) |
| Wire payload | `message_payload.dart` | MessagePayload envelope: v1 plaintext or v2 encrypted (ML-KEM-768 + AES-256-GCM), supports quoted messages and media attachments |
| Message repository | `message_repository.dart`, `message_repository_impl.dart` | Save, load, update status, count for contact, markConversationAsRead, getUnreadCountForContact, getTotalUnreadCount |
| Media attachment repository | `media_attachment_repository.dart`, `media_attachment_repository_impl.dart` | Save, load for message/messages, update local path, update download status, delete for message/contact, get pending downloads |
| Send message | `send_chat_message_use_case.dart` | Build payload, encrypt with ML-KEM if available (v2) or plaintext (v1), discover + dial peer, 3x retry, offline inbox fallback, optimistic persist |
| Handle incoming | `handle_incoming_chat_message_use_case.dart` | Detect v2 encrypted envelope and decrypt, or parse v1 plaintext, validate sender, detect name changes, persist |
| Load conversation | `load_conversation_use_case.dart` | Load all messages for a contact by timestamp ASC |
| Mark read | `mark_conversation_read_use_case.dart` | Mark all unread incoming messages for a contact as read |
| Retry failed | `retry_failed_messages_use_case.dart` | Retry all failed outgoing messages (loads identity, queries failed, re-sends with original messageId) |
| Upload media | `upload_media_use_case.dart` | Upload media to relay, store locally, create MediaAttachment records |
| Download media | `download_media_use_case.dart` | Download media from relay to local device |
| Chat listener | `chat_message_listener.dart` | Background listener on chatMessageStream, resolves ML-KEM secret key for decryption, broadcasts to UI + onError/onDone stream handlers |
| Conversation screen | `conversation_screen.dart` | Pure UI: header, letter cards, empty state, compose area |
| Conversation logic | `conversation_wired.dart` | Business logic: load messages, optimistic send, listen for incoming, marks conversation as read on load and on incoming messages + onError/onDone stream handlers |
| Letter card | `letter_card.dart` | Full-width card with left accent (received) / right accent (sent), supports queued/delivered/failed status |
| Compose area | `compose_area.dart` | Auto-growing text field + animated send button |
| Attachment preview | `attachment_preview_strip.dart` | Preview strip for pending media attachments |
| Empty state | `empty_conversation_state.dart` | Breathing glow avatar + "Connected!" + writing prompt |
| Header | `conversation_header.dart` | Frosted-glass header with back button + contact info |
| Origin marker | `compact_origin_marker.dart` | Compact connection origin at conversation top |
| Date separator | `date_separator.dart` | Date divider between letter cards on different days |
| Blocked banner | `blocked_banner.dart` | Banner with block icon + "Unblock" button (replaces compose area when contact blocked) |
| Route transition | `conversation_route_transition.dart` | Slide-up transition (420ms easeOutCubic) |
| DB migration | `002_messages_table.dart` | Creates messages table with contact + timestamp indexes |
| DB migration | `003_mlkem_keys.dart` | Adds ml_kem_public_key, ml_kem_secret_key columns to identity; ml_kem_public_key to contacts and contact_requests |
| DB migration | `004_nullify_secret_columns.dart` | Schema v4: makes secret columns nullable for secure storage migration |
| DB migration | `005_secret_null_checks.dart` | Schema v5: CHECK constraints on secret columns + avatar_blob BLOB column |
| DB migration | `006_read_at_column.dart` | Schema v6: adds read_at TEXT column to messages table |
| DB migration | `007_archive_columns.dart` | Schema v7: adds is_archived INTEGER + archived_at TEXT to contacts table |
| DB migration | `008_block_columns.dart` | Schema v8: adds is_blocked INTEGER + blocked_at TEXT to contacts table |
| DB migration | `009_quoted_message_id.dart` | Schema v9: adds quoted_message_id TEXT to messages table |
| DB migration | `010_media_attachments.dart` | Schema v10: creates media_attachments table |
| DB migration | `011_avatar_version.dart` | Schema v11: adds avatar_version INTEGER to identity table |
| DB helpers | `messages_db_helpers.dart` | Messages table CRUD (insert, load, update status, count for contact, mark conversation read, count unread per contact, count total unread) |
| DB helpers | `media_attachments_db_helpers.dart` | Media attachments table CRUD (insert, load for message/messages, update local path, update download status) |

### Orbit (UI-5)

| Component | File(s) | Description |
|-----------|---------|-------------|
| Orbit friend model | `orbit_friend.dart` | Composite model: contact + messageCount + lastActivity + unreadCount |
| Load orbit data | `load_orbit_data_use_case.dart` | Top-level function: loads contacts with message counts + unread counts, sorted desc |
| Orbit screen | `orbit_screen.dart` | Pure UI: 4-layer Stack layout (header, visualization, friends list, search) |
| Orbit logic | `orbit_wired.dart` | State management: 3 animation controllers, streams, DI (8 deps) + onError/onDone stream handlers |
| Orbital visualization | `orbital_visualization.dart` | 320x320 Stack: rings + center avatar + friend avatars + overflow badge |
| Ring painter | `orbital_ring_painter.dart` | CustomPainter: 2 dashed concentric circles (teal + purple) |
| Orbital avatar | `orbital_avatar.dart` | Positioned avatar on ring with staggered scale-in animation |
| Overflow badge | `overflow_badge.dart` | "+N" circle badge on outer ring (1000ms delayed entrance) |
| Close button | `orbit_close_button.dart` | 36x36 glass circle X button with BackdropFilter |
| Orbit header | `orbit_header.dart` | Right-aligned user avatar (44px) |
| Friends list header | `friends_list_header.dart` | "Friends" title + My QR / Scan pill buttons |
| Friend row | `friend_row.dart` | Glassmorphic tappable friend card + AnimatedFriendRow wrapper + unread count badge |
| Swipeable friend row | `swipeable_friend_row.dart` | Swipeable wrapper with slide-to-reveal action buttons (Block/Unblock + Delete + Archive/Unarchive) |
| Swipe action buttons | `swipe_action_buttons.dart` | BlockActionButton, UnblockActionButton, DeleteActionButton, ArchiveActionButton, UnarchivePillButton |
| Filter toggle | `friends_filter_toggle.dart` | Segmented filter: "All (N)" / "Archived (N)" with count badges |
| Archived empty state | `archived_empty_state.dart` | Empty state for archived tab |
| Confirmation dialog | `confirmation_dialog.dart` | Confirmation dialog with title, description, and danger action button |
| QR action cards | `qr_action_cards.dart` | Two side-by-side bottom QR cards (unused/created but removed from screen) |
| Search trigger | `orbit_search_trigger.dart` | Floating glass pill at bottom (search + close) |
| Search dock | `orbit_search_dock.dart` | Bottom-docked search input panel with native keyboard |
| Route transition | `orbit_route_transition.dart` | Slide-up route (matches conversation pattern, 420ms) |

### Home / First-Time Experience

| Component | File(s) | Description |
|-----------|---------|-------------|
| Home screen | `first_time_experience_screen.dart` | Animated home UI |
| Home logic | `first_time_experience_wired.dart` | QR build, username edit, avatar blob storage, scan, CR listener + onError/onDone stream handlers |
| Profile avatar | `profile_avatar_widget.dart` | Avatar display (Image.memory) + camera button |
| Username edit | `editable_username_widget.dart` | Tap-to-edit username |
| QR section | `qr_code_section.dart` | QR code with glow |
| Scan card | `scan_friend_card.dart` | Glassmorphic scan action |
| Empty state | `empty_circle_state.dart` | Pulsing circles animation |
| Ring avatar | `ring_avatar.dart`, `ring_avatar_painter.dart` | Deterministic peerId avatar |

### Feed

| Component | File(s) | Description |
|-----------|---------|-------------|
| Feed item model | `feed_item.dart` | FeedItem base + ConnectionFeedItem + ThreadMessage + ThreadFeedItem (thread-based feed with ConversationState enum: unread, active, replied, read) |
| Session reply | `session_reply.dart` | SessionReply model + SessionReplyTracker for per-contact session-local reply tracking |
| Time formatting | `format_message_time.dart` | Message timestamp formatting + relative time ("2m ago") |
| Thread grouping | `group_messages_into_threads.dart` | Groups messages into ThreadFeedItems by contact and 24-hour time gap, derives ConversationState, includes sent+received, blocked status, quotedMessageId propagation |
| Time gap detection | `has_significant_time_gap.dart` | Detects 2+ hour gaps or AM/PM boundary crossings |
| Thread splitting | `split_thread_by_time_gap.dart` | Splits message list into thread chunks by 24-hour gaps with burst handling and reply soft-close |
| Load feed | `load_feed_use_case.dart` | Load initial feed from DB (contacts + latest messages + unread counts per contact) |
| Feed screen | `feed_screen.dart` | Pure UI feed display (connection + thread cards) |
| Feed logic | `feed_wired.dart` | Feed orchestration, identity load, CR/chat listeners, orbit navigation, passes unread counts, total unread badge on nav bar + onError/onDone stream handlers |
| Feed header | `feed_header.dart` | Sticky header with username + avatar from memory bytes |
| Navigation bar | `feed_navigation_bar.dart` | Bottom glass nav bar (3 tabs) + total unread badge on feed tab |
| Nav button | `nav_bar_button.dart` | Individual tab button (active/inactive) + badge overlay support |
| Connection card | `connection_card.dart` | Contact connection display card (inline green checkmark badge) |
| Feed card | `feed_card.dart` | Auto-selects open/collapsed mode based on ConversationState; flat glassmorphic card with purple/teal accent |
| Collapsed mode body | `collapsed_mode_card_body.dart` | Collapsed mode: friend header, single-line preview, optional reply indicator, "Continue..." inline input |
| Open mode body | `open_mode_card_body.dart` | Open mode: friend header, scrollable unread message preview, inline reply input |
| Inline reply input | `inline_reply_input.dart` | Inline reply composer for collapsed/open card modes |
| Scrollable preview | `scrollable_message_preview.dart` | Scrollable preview of messages in open mode card |
| Message bubble | `message_bubble.dart` | Individual message bubble within expanded thread (text + timestamp, unread highlight) |
| Swipe to quote | `swipe_to_quote_bubble.dart` | Swipe-to-quote interaction on message bubbles |
| Quote preview | `quote_preview_bar.dart` | Preview of quoted message in compose area |
| View earlier link | `view_earlier_link.dart` | Link to view earlier messages in conversation |
| More messages hint | `more_messages_hint.dart` | Hint indicating more messages available |
| Replied indicator | `replied_indicator.dart` | "You replied" indicator on feed cards |
| Session divider | `session_divider.dart` | "PREVIOUSLY SEEN" divider between unread and read thread cards |
| Time gap divider | `time_gap_divider.dart` | Thin time-label divider between messages with significant time gaps |
| Unread badge | `unread_count_badge.dart` | Circular unread count badge widget |
| Checkmark anim | `checkmark_burst_animation.dart` | Animated checkmark with expanding rings (unused/orphaned) |
| Route transition | `feed_route_transition.dart` | Slide-up page transition |

### Push Notifications

| Component | File(s) | Description |
|-----------|---------|-------------|
| Background handler | `background_message_handler.dart` | Firebase background message handler (`@pragma('vm:entry-point')`) + inbox drain deferral note |
| Push permission | `request_push_permission_use_case.dart` | Request notification permission from user |
| Token registration | `register_push_token_use_case.dart` | Register FCM token with relay server via P2P inbox protocol |

### Settings

| Component | File(s) | Description |
|-----------|---------|-------------|
| Image quality preference | `image_quality_preference.dart` | ImageQualityPreference enum (compressed quality 85 / original quality 100) |
| Image quality use cases | `image_quality_preference_use_cases.dart` | Get/set image quality preference from SecureKeyStore |
| Video quality use cases | `video_quality_preference_use_cases.dart` | Get/set video quality preference |
| Upload profile picture | `upload_profile_picture_use_case.dart` | Upload avatar to relay, update identity avatarVersion, broadcast profile_update to contacts |
| Download profile picture | `download_profile_picture_use_case.dart` | Download contact's profile picture from relay |
| Profile update listener | `profile_update_listener.dart` | Listener for incoming profile_update messages |
| Settings screen | `settings_screen.dart` | Pure UI settings screen (profile, peer ID, recovery phrase, image quality toggle) |
| Settings logic | `settings_wired.dart` | Settings business logic + state management |
| Route transition | `settings_route_transition.dart` | Slide-up route transition |
| Profile section | `settings_profile_section.dart` | Profile section with avatar and username |
| Peer ID card | `settings_peer_id_card.dart` | Peer ID display card with copy button |
| Recovery phrase card | `settings_recovery_phrase_card.dart` | Recovery phrase card (reveal/hide/copy) |
| Image quality toggle | `image_quality_toggle.dart` | Toggle for image quality preference |

### Core Utilities

| Component | File(s) | Description |
|-----------|---------|-------------|
| Ring avatar gen | `ring_avatar_generator.dart`, `ring_avatar_spec.dart` | DJB2 hash → deterministic rings |
| Key conversion | `key_conversion.dart` | base64 ↔ hex utilities |
| Flow events | `flow_event_emitter.dart` | Structured logging (DB/FL/Go layers) |
| Chat logger | `chat_console_logger.dart` | Debug logging for chat messages with shortened peer IDs |
| Startup timing | `startup_timing.dart` | Debug-only startup milestone timing utility |
| Network constants | `network_constants.dart` | Rendezvous multiaddr |
| Startup config | `startup_config.dart` | Feature flags (deferredStartupMode) |
| Theme | `app_colors.dart`, `feed_colors.dart`, `app_theme.dart`, `glassmorphism.dart` | Dark theme + glass effects + feed color palette (purple/teal accents) |
| Image processor | `image_processor.dart` | ImageProcessor: strips EXIF, quality compression, avatar resizing, injectable CompressFileFn |
| Media file manager | `media_file_manager.dart` | MediaFileManager: manages local media file paths, relative DB paths, absolute file I/O |
| Video process result | `video_process_result.dart` | VideoProcessResult model (path, width, height, durationMs) |

### Shared Widgets

| Component | File(s) | Description |
|-----------|---------|-------------|
| Media grid | `media_grid.dart` | Grid layout for image/video attachments (1-4+ item layouts) |
| Media grid cell | `media_grid_cell.dart` | Single grid cell for media with tap handling |
| Media display helpers | `media_display_helpers.dart` | Constants (mediaGridGap, mediaGridContainerRadius) + formatDurationMs() |
| Media preview text | `media_preview_text.dart` | Text preview for media attachments |
| Full screen image viewer | `full_screen_image_viewer.dart` | Full-screen image viewer with pinch-to-zoom |
| Video thumbnail overlay | `video_thumbnail_overlay.dart` | Play icon overlay for video thumbnails |
| Audio player widget | `audio_player_widget.dart` | Audio player widget for audio attachments |

### Relay Server (Infrastructure)

| Component | File(s) | Description |
|-----------|---------|-------------|
| Relay server v5 | `rendezvous-relay-server-inbox-v5.js` | libp2p relay + rendezvous + offline inbox (/mknoon/inbox/1.0.0 protocol) |

---

## Database Tables

| Table | Primary Key | Migration | Description |
|-------|-------------|-----------|-------------|
| `identity` | `id` (always 1) | v1 (`001`), v3 (`003`: ml_kem_public_key, ml_kem_secret_key), v4 (`004`: nullable secret columns), v5 (`005`: CHECK constraints + avatar_blob), v11 (`011`: avatar_version) | Single-row identity storage, secrets in secure storage (DB columns always NULL via CHECK), avatar as BLOB, avatar_version for profile picture versioning |
| `contacts` | `peer_id` | v1 (`001`), v3 (`003`: ml_kem_public_key), v7 (`007`: is_archived, archived_at), v8 (`008`: is_blocked, blocked_at) | Contacts added via QR scanning, with archive and block support, avatarPath and avatarVersion for profile pictures |
| `contact_requests` | `peer_id` | v1 (`001`), v3 (`003`: ml_kem_public_key) | Incoming P2P contact requests |
| `messages` | `id` (UUID) | v2 (`002`), v6 (`006`: read_at TEXT), v9 (`009`: quoted_message_id TEXT) | Conversation messages (indexes on contact_peer_id, timestamp), read_at column for unread tracking, quoted_message_id for quote/reply |
| `media_attachments` | `id` (UUID) | v10 (`010`) | Media attachments for messages (mime, size, mediaType, width, height, durationMs, localPath, downloadStatus) |

Database version: **11** (set in `main.dart` `openDatabase` call). Migrations: v4 (`004_nullify_secret_columns.dart`: makes secret columns nullable), v5 (`005_secret_null_checks.dart`: CHECK constraints ensuring secret columns stay NULL + avatar_blob BLOB column), v6 (`006_read_at_column.dart`: adds read_at TEXT column to messages table), v7 (`007_archive_columns.dart`: adds is_archived INTEGER + archived_at TEXT to contacts), v8 (`008_block_columns.dart`: adds is_blocked INTEGER + blocked_at TEXT to contacts), v9 (`009_quoted_message_id.dart`: adds quoted_message_id TEXT to messages), v10 (`010_media_attachments.dart`: creates media_attachments table), v11 (`011_avatar_version.dart`: adds avatar_version INTEGER to identity).

---

## Notes on Go Native Library

The Go native library in `go-mknoon/` is compiled via `gomobile bind` into platform-specific binaries (`.xcframework` for iOS, `.aar` for Android). After modifying any `.go` file in `go-mknoon/`, you **must** rebuild:

```bash
cd go-mknoon
PATH="$PATH:$(go env GOPATH)/bin" make all
cd ../ios && pod install
```

`make all` builds both iOS and Android targets. `flutter run` alone does **not** rebuild the Go library — you must run `make` + `pod install` first. Platform wrappers (`GoBridge.swift` / `GoBridge.kt`) expose 32 methods (including media upload/download and profile operations) to Flutter via MethodChannel and EventChannel.
