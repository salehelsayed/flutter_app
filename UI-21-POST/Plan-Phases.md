# Posts Implementation Checklist

This plan assumes the product contract in `../kitchen/landing-screen-claude/neighbourhood_spec.md` is the source of truth and that Posts will ride on the existing app-level messaging transport before we add any dedicated libp2p protocol.

## Working Rules

- Build Posts as JSON envelopes over the existing direct send and offline inbox paths in `lib/core/services/p2p_service.dart`, `lib/core/services/p2p_service_impl.dart`, `lib/core/bridge/p2p_bridge_client.dart`, and `lib/core/bridge/go_bridge_client.dart`.
- Do not add a new `go-mknoon/node/node.go` protocol in early phases unless an actual transport gap appears. For this feature, most complexity is product logic, persistence, and UI, not libp2p framing.
- Keep every phase vertically complete: DB migration, router/listener wiring, sender flow, receiver flow, restart behavior, and tests.
- Every phase that adds or changes schema must also bump the DB version in `lib/main.dart`, register the migration there, and add migration-regression coverage for upgrade paths.
- Follow the repo pattern: `domain/`, `application/`, `presentation/`, helper-backed repositories, and `Wired` screens.
- Make live delivery, offline inbox replay, and push-triggered wake-up drain converge into the same Posts ingestion path. Do not create a separate "push-only" code path for posts.
- Reuse the existing conversation voice/media stack where semantics already match. Do not create a second recorder, waveform, upload, or audio-player implementation for Posts when the current app already provides one.

## Strict TDD Rules

- Every phase must follow strict `RED -> GREEN -> REFACTOR`. Do not write production code for a phase slice until the targeted failing tests for that slice exist and have been observed failing.
- Start at the lowest proving layer first:
  - pure logic, payload parsing, model mapping, DB helpers, migrations, and widget-state tests
  - then repository, listener, and use-case integration tests with fakes
  - then simulator or CLI smoke coverage for multi-device, lifecycle, notification, media, and permission flows
- Reuse existing harnesses before inventing new ones:
  - `test/shared/fakes/fake_p2p_network.dart`
  - `test/shared/fakes/fake_p2p_service_integration.dart`
  - the in-memory repositories under `test/shared/fakes/`
  - the existing `integration_test/` flows and `integration_test/scripts/`
- Build a lightweight in-memory Posts repository fake as soon as Phase 1 tests need one. Do not let the first vertical slice couple RED-only tests to SQLite when a fake would prove the behavior faster.
- If a phase needs a new fake, stub, or simulator harness to make RED-first practical, build that harness as the first test task of the phase before production code.
- A phase cannot exit on unit tests alone if it changes any of:
  - inbox replay
  - startup or resume behavior
  - notifications or tap routing
  - media delivery or rendering
  - multi-device delivery
  - location permissions or proximity eligibility
- Refactor only after the new targeted tests are green. Keep refactors phase-scoped and rerun the targeted suite after each refactor step.
- The implementation notes or PR for each phase must record the initial RED evidence: the exact failing test names or commands written before the implementation.

## UI Scope That Must Be Carried Through The Phases

- [ ] The post-card design is part of the implementation scope, not a later polish pass. The Posts widgets must cover the full card anatomy from the spec:
  - reshare attribution
  - author row
  - direct-friend badge where applicable
  - scope badge
  - text expansion
  - media rendering
  - action bar
  - expiry footer
- [ ] The feed structure is also in scope:
  - header
  - compose prompt
  - pinned section
  - time-grouped feed
  - caught-up state
- [ ] Compose states are in scope:
  - audience chooser
  - nearby radius chooser
  - nearby availability and error states in compose
  - pick-people selection
  - keep-available toggle
  - post confirmation
- [ ] Post detail states are in scope:
  - comments sheet
  - passed-along cards
  - nearby cards with distance
  - pinned cards
  - own-post management states
- [ ] If any of these UI pieces are intentionally deferred, note that explicitly in the phase exit gate instead of silently dropping them.

## Phase 0 Assumptions

- `Posts` is the final feature name.
- `Posts` is its own primary tab in the app shell. Do not treat this as an open nav experiment later.
- `People Nearby` means direct friends inside a radius, not strangers.
- Friend-of-friend content only arrives through explicit pass-along.
- Pass-along is one explicit extra hop in v1, not an open-ended reshare chain.
- Pinned posts have no preset expiry in v1.
- There is no persistent privacy panel on the Posts feed.
- Settings owns the persistent nearby/privacy controls, and compose shows nearby status only when it affects posting.

Remaining cleanup before coding:

- [ ] Keep reshared trust context simple in v1: no mutual-friends badge on reshared posts, only the `passed this along` attribution line.
- [ ] Keep reactions simple in v1: heart-only on posts and comments. Do not inherit the broader emoji-reaction model from chat.

### Agent Skills

- Primary: `$senior-ui-ux-designer`
- Also use: `$future-mobile-chat-social-ux`
- Use this phase to lock the trust-context and UI-scope assumptions before implementation starts. Do not write production code in Phase 0.

## Phase 1: Direct-Friend Posts MVP

Outcome: a real Posts tab where direct friends can publish text posts to `All Friends` or `Pick People`, receive them live or via inbox replay, and see them after app restart.

### Agent Skills

- Primary: `$flutter-feature-module-implementer`
- Also use: `$flutter-sqlite-migrations-and-repositories`, `$mobile-notification-routing-and-deep-linking`, `$flutter-test-orchestrator`
- Use `$senior-ui-ux-designer` only if the implemented Posts tab, card anatomy, or compose flow drifts from the UI scope above.

### Transport and routing

- [ ] Extend `lib/core/services/incoming_message_router.dart` with a `postCreateStream` and route `type == 'post_create'`.
- [ ] Keep `lib/core/services/p2p_service.dart` and `lib/core/services/p2p_service_impl.dart` unchanged at the API level. Reuse `sendMessageWithReply`, `storeInInbox`, and `drainOfflineInbox`.
- [ ] Do not add new bridge commands in `lib/core/bridge/go_bridge_client.dart`, `lib/core/bridge/p2p_bridge_client.dart`, `go-mknoon/bridge/bridge.go`, or `go-mknoon/node/node.go` for this phase.

### Notifications and replay

- [ ] Wire Posts into the existing app startup and wake-up paths so inbox-drained post payloads are handled exactly like live post payloads:
  - `lib/main.dart`
  - `lib/features/identity/presentation/startup_router.dart`
  - `lib/core/lifecycle/handle_app_resumed.dart`
- [ ] Add one pending post-target handoff path that all notification entry points use:
  - local notification taps from `NotificationService.onNotificationTap`
  - warm-start opens from `FirebaseMessaging.onMessageOpenedApp`
  - terminated-start opens from `getInitialMessage` via `handleInitialRemoteMessage`
- [ ] Keep that post-target flow explicit:
  - parse and store the target post id and optional focus state
  - trigger inbox drain
  - wait for local Posts ingest to persist the target post
  - then select the Posts tab and scroll or focus the card
  - do not navigate directly to a post detail route before local ingest finishes
- [ ] Add Posts notification handling by following the same local notification pattern already used by chat and groups:
  - `lib/core/notifications/notification_service.dart`
  - `lib/core/notifications/flutter_notification_service.dart`
  - `lib/features/push/application/background_message_handler.dart`
- [ ] Extend `lib/features/push/application/background_push_notification_fallback.dart` for post payloads instead of relying on the current closed message-type switch and generic fallback path.
- [ ] Generalize notification payload routing so it can open a post target, not only a 1:1 contact/conversation target.
- [ ] Decide the initial tap target for a post notification in this phase: open the Posts tab and scroll to the post, not a conversation route.

### Database

- [ ] Bump the database version in `lib/main.dart`.
- [ ] Add a new migration file such as `lib/core/database/migrations/027_posts_core.dart`.
- [ ] Register the migration in `lib/main.dart`.
- [ ] Add helper files for the new tables, for example:
  - `lib/core/database/helpers/posts_db_helpers.dart`
  - `lib/core/database/helpers/post_recipients_db_helpers.dart`
- [ ] Start with the minimum core schema:
  - `posts`
  - `post_recipients`
  - `post_feed_state` or equivalent local state for hide/read/delivery bookkeeping
- [ ] Keep post storage separate from `messages` and `media_attachments`. The existing conversation tables are optimized for thread chat, not broadcast posts.

### Domain and application

- [ ] Add a new feature module under `lib/features/posts/`.
- [ ] Create domain models for post identity, author, audience, expiry, and receiver scope, for example:
  - `lib/features/posts/domain/models/post_model.dart`
  - `lib/features/posts/domain/models/post_audience.dart`
- [ ] Add repository interfaces and implementations:
  - `lib/features/posts/domain/repositories/post_repository.dart`
  - `lib/features/posts/domain/repositories/post_repository_impl.dart`
- [ ] Add core use cases:
  - `lib/features/posts/application/send_post_use_case.dart`
  - `lib/features/posts/application/load_posts_feed_use_case.dart`
  - `lib/features/posts/application/handle_incoming_post_use_case.dart`
- [ ] Add a listener similar to the existing message listeners:
  - `lib/features/posts/application/post_listener.dart`

### App wiring

- [ ] In `lib/main.dart`, construct the Posts repository and listener beside the existing conversation, reaction, group, and introduction wiring.
- [ ] Start the Posts listener from the same app lifecycle point where the other listeners are started.
- [ ] Keep the listener ordering simple: router first, then typed listeners.
- [ ] Add a shell-level tab and target owner under `lib/features/feed/` instead of letting `FeedWired`, `SettingsWired`, and notification handlers switch tabs ad hoc:
  - one source of truth for `activeTab`
  - initial tab selection on app boot
  - pending post-target handoff after notification opens
  - tab changes returned from Settings or sibling surfaces
- [ ] Thread Posts dependencies through the concrete app-shell constructors that currently carry typed repos and listeners:
  - `MyApp` in `lib/main.dart`
  - `lib/features/identity/presentation/startup_router.dart`
  - `FirstTimeExperienceWired` call sites inside `StartupRouter`
  - `_buildPendingShareRoute` in `StartupRouter`
  - `_buildSharePickerRoute` in `lib/main.dart`
  - `lib/features/feed/presentation/screens/feed_wired.dart`
  - `lib/features/orbit/presentation/screens/orbit_wired.dart`
  - `lib/features/qr_code/presentation/screens/qr_scanner_wired.dart`
- [ ] If Posts or nearby replay hooks are added to `lib/core/lifecycle/handle_app_resumed.dart`, change its named-parameter signature and all call sites together. Do not tack on hidden global lookups.
- [ ] Add Posts teardown to `_MyAppState.dispose()` in `lib/main.dart`.
- [ ] Extend `IncomingMessageRouter.dispose()` so every new post-related `StreamController` is closed there too.

### UI

- [ ] Add a Posts feature surface:
  - `lib/features/posts/presentation/screens/posts_screen.dart`
  - `lib/features/posts/presentation/screens/posts_wired.dart`
  - `lib/features/posts/presentation/widgets/post_card.dart`
  - `lib/features/posts/presentation/widgets/compose_post_sheet.dart`
- [ ] Host the composer as a Posts-owned sheet or route. Do not model it on `lib/features/conversation/presentation/screens/conversation_wired.dart`, because chat compose is inline rather than a bottom sheet.
- [ ] Use `lib/features/groups/presentation/screens/contact_picker_wired.dart` as the closest existing analogue for `Pick People`, then adapt it for active direct-contact multi-select. Do not reuse `share_target_picker_wired.dart`, which is for OS share intents.
- [ ] Add Posts to `lib/features/feed/presentation/widgets/feed_navigation_bar.dart`.
- [ ] Add a real Posts nav asset such as `assets/icons/nav_posts.svg` before wiring the tab. The nav bar is SVG-asset backed today.
- [ ] Replace scattered bare tab strings with a shared tab-id constant or equivalent typed source of truth before adding `posts`.
- [ ] Update any surfaces that embed the nav bar and tab state:
  - `lib/features/feed/presentation/screens/feed_screen.dart`
  - `lib/features/feed/presentation/screens/feed_wired.dart`
  - `lib/features/orbit/presentation/screens/orbit_wired.dart`
  - `lib/features/qr_code/presentation/screens/qr_scanner_wired.dart`
  - `lib/features/settings/presentation/screens/settings_wired.dart`
  - `lib/features/settings/presentation/screens/settings_screen.dart`
- [ ] Update the route handoff sites that need to reopen or seed the app shell with the correct active tab:
  - `lib/features/identity/presentation/startup_router.dart`
  - `FirstTimeExperienceWired` builders in `StartupRouter`
  - `_buildPendingShareRoute` in `StartupRouter`
  - `_buildSharePickerRoute` in `lib/main.dart`
- [ ] Posts is the new fourth tab beside Feed, Remember, and Orbit in Phase 1. Do not rename Feed or move the conversation list as part of this rollout, and do not leave tab ownership implicit inside `FeedWired`.
- [ ] Phase 1 post-card minimum design coverage:
  - direct-friend card
  - `Pick People` scoped card
  - empty/caught-up state
  - compose sheet
  - basic feed time-grouping
  - post-confirmation copy for `All Friends` and `Pick People`

### Tests and exit gate

- [ ] Start RED with targeted failing tests for:
  - `post_create` routing and payload parsing
  - the `027_posts_core` migration and DB helpers
  - `send_post`, `load_posts_feed`, and `handle_incoming_post`
  - `PostsWired`, compose-sheet, shell-tab ownership, and empty or caught-up widget states
- [ ] If Phase 1 needs new fakes, add the in-memory Posts repository fake first so routing and use-case tests can start RED without SQLite.
- [ ] Add router tests for `post_create`.
- [ ] Add repository and migration tests for the new core tables.
- [ ] Add integration-with-fakes coverage that proves live delivery and offline inbox replay converge into the same local repository path.
- [ ] Add a 2-device smoke flow: create post on device A, receive live on device B, then repeat with B offline and verify inbox replay on resume.
- [ ] Add a push-wake smoke check: simulated remote wake-up triggers inbox drain and the post lands in the same local repository path as a live delivery.
- [ ] Add notification tests that cover the explicit `post_create` fallback path in `background_push_notification_fallback.dart`.
- [ ] Add notification-open tests for the shared pending post-target flow:
  - local notification tap
  - `onMessageOpenedApp`
  - `getInitialMessage`
  - all three must wait for local ingest, then land on the Posts tab with the target post focused
- [ ] Add a repeatable simulator or CLI-backed Phase 1 smoke command under `integration_test/` or `integration_test/scripts/`.
- [ ] Exit only when the Posts tab works without any debug-only shortcuts.

## Phase 2: Comments, Reactions, Media, and Expiry

Outcome: posts behave like a real feed item, not just a one-shot text broadcast, and normal posts age out according to the spec.

### Agent Skills

- Primary: `$flutter-feature-module-implementer`
- Also use: `$flutter-sqlite-migrations-and-repositories`, `$flutter-test-orchestrator`
- Use `$senior-ui-ux-designer` only if comments, media rendering, or compose interaction quality needs a deliberate refinement pass.

### Transport and routing

- [ ] Extend `lib/core/services/incoming_message_router.dart` with typed streams for:
  - `post_comment`
  - `post_reaction`
  - `post_comment_reaction`
- [ ] Keep the transport path app-layer only. Still no new Go bridge command unless attachments expose a real limitation.

### Database

- [ ] Bump the database version in `lib/main.dart` and register the Phase 2 migration there.
- [ ] Add a migration such as `lib/core/database/migrations/028_posts_engagement.dart`.
- [ ] Add helper files for:
  - `lib/core/database/helpers/post_comments_db_helpers.dart`
  - `lib/core/database/helpers/post_reactions_db_helpers.dart`
  - `lib/core/database/helpers/post_comment_reactions_db_helpers.dart`
  - `lib/core/database/helpers/post_media_db_helpers.dart`
- [ ] Add tables for:
  - `post_comments`
  - `post_reactions`
  - `post_comment_reactions`
  - `post_media_attachments`
- [ ] Extend the `posts` schema or companion helpers for expiry bookkeeping:
  - `expires_at`
  - `last_engagement_at`
  - local cleanup bookkeeping for expired rows and attached media
- [ ] Store post media separately from conversation media. Do not overload `message_id` semantics from `lib/core/database/helpers/media_attachments_db_helpers.dart`.
- [ ] Keep the post-media schema field-compatible with conversation attachments for audio and video metadata:
  - `mime`
  - `size`
  - `media_type`
  - `duration_ms`
  - `local_path`
  - `download_status`
  - `waveform`

### Domain and application

- [ ] Add models and repos for comments, comment counts, heart-only reactions, comment-heart state, post media, and expiry lifecycle.
- [ ] Add a typed Posts engagement listener layer instead of treating router streams as the final ingress step:
  - `post_comment_listener.dart`
  - `post_reaction_listener.dart`
  - or a combined `post_engagement_listener.dart`
- [ ] Make the engagement listener do the same class of work the current chat and reaction listeners do:
  - validate sender and trust context
  - persist to repos
  - emit typed UI updates
  - trigger notification decisions where needed
- [ ] Add use cases:
  - `send_post_comment_use_case.dart`
  - `send_post_reaction_use_case.dart`
  - `send_post_comment_reaction_use_case.dart`
  - `load_post_comments_use_case.dart`
  - `attach_post_media_use_case.dart`
- [ ] Add expiry lifecycle use cases:
  - reset or extend expiry when a new comment lands
  - sweep expired posts and their local attachments
  - load feed items with the current countdown state
- [ ] Keep post reactions heart-only in v1, including comment hearts. Do not mirror the conversation emoji-reaction system.
- [ ] Lock the multi-recipient engagement rule now:
  - persist the canonical recipient set for each post at creation time
  - reuse that stored set for comment and reaction fanout instead of recomputing audience later
  - include the original author in engagement delivery even when the audience is otherwise stored as recipients
  - use the same recipient set to build media `allowedPeers` for post attachments and later engagement blobs
- [ ] Keep voice as part of generic post-media handling. Do not add a separate `send_post_voice_use_case.dart` unless Posts later needs behavior that truly diverges from the existing media pipeline.
- [ ] Do not call `lib/features/conversation/application/send_voice_message_use_case.dart` directly from Posts. It is conversation-specific. Reuse its lower-level pieces and orchestration pattern instead of cloning its logic.
- [ ] Do not call `lib/features/conversation/application/upload_media_use_case.dart` as-is with a fake recipient peer id. Extract or wrap the shared upload logic so Posts can upload once and fan out with post-specific allowlists instead of 1:1 recipient semantics.
- [ ] Extend `lib/core/media/media_file_manager.dart` or add a sibling helper so post media uses a post-scoped path scheme. Do not store Posts attachments under `media/<contactPeerId>/...`.
- [ ] Reuse existing media infrastructure where it already works:
  - `lib/core/media/image_processor.dart`
  - `lib/core/media/media_picker.dart`
  - `lib/core/media/media_file_manager.dart`
  - `lib/core/media/amplitude_buffer.dart`
  - `lib/core/media/normalize_amplitude.dart`
  - `lib/core/media/audio_recorder_service.dart`
  - `lib/core/media/record_audio_recorder_service.dart`
  - `lib/core/media/downsample_waveform.dart`
  - `lib/features/conversation/application/upload_media_use_case.dart`
  - `lib/features/conversation/domain/models/audio_recording.dart`
  - `lib/features/conversation/domain/models/media_attachment.dart`
  - `lib/features/conversation/presentation/widgets/recording_overlay.dart`
  - `lib/shared/widgets/media/audio_player_widget.dart`
  - `lib/shared/widgets/media/*`
- [ ] If `RecordingOverlay` is reused directly, extract or move the shared recorder chrome out of `lib/features/conversation/` first. Do not create a long-term cross-feature import from Posts into a conversation-only presentation folder.
- [ ] Fix the existing `AudioRecorderService.start()` signature mismatch before routing Posts recording through the interface.

### App wiring

- [ ] Construct and start the Posts engagement listener(s) in `lib/main.dart` beside the current chat, reaction, and group listeners.
- [ ] Dispose of the new engagement listener(s) in `_MyAppState.dispose()`.
- [ ] Treat router streams as the first hop only. Posts comments and reactions should reach the UI through the typed engagement listener layer, not directly from `IncomingMessageRouter`.

### Notifications and lifecycle

- [ ] Add notification handling for the original poster when new `post_comment` or `post_reaction` events arrive, and route taps into the relevant post or comments surface instead of a conversation thread.
- [ ] Run the expired-post sweep from a predictable lifecycle point such as app startup, app resume, and feed open so auto-delete behavior does not depend on a background job that v1 does not have.
- [ ] Lock a post-media hydration policy now instead of leaving receive behavior implicit:
  - v1 should auto-download received post attachments after ingest or replay, mirroring chat and group media handling
  - persist hydrated local paths so restart restores renderable cards
  - re-emit updated post models after hydration so feed widgets refresh without a full reload

### UI

- [ ] Add a comments sheet under `lib/features/posts/presentation/widgets/comments_sheet.dart`.
- [ ] Add post-specific media layout widgets only where the Posts card chrome differs. Do not fork shared media playback just to restyle it.
- [ ] Reuse shared media viewers where possible instead of duplicating image and video presentation logic.
- [ ] Cover the spec's image-post variant:
  - multi-image carousel
  - swipe navigation
  - dot indicators
  - current-image counter badge
- [ ] Cover the spec's video-post variant:
  - thumbnail
  - play overlay
  - duration badge
  - inline progress state
- [ ] Reuse `lib/shared/widgets/media/audio_player_widget.dart` for voice-post playback. If Posts needs different padding or framing, wrap it rather than cloning it.
- [ ] Make the compose attachment entry points match the current product contract:
  - `Media` opens image/video picking
  - `Voice` enters inline voice-note recording in the compose sheet
- [ ] Reuse the current voice-note pipeline for capture:
  - `AudioRecorderService` / `RecordAudioRecorderService` for recording
  - `RecordingOverlay` as the base inline recording state
  - `downsample_waveform.dart` for waveform persistence
- [ ] It is acceptable for Posts to use a different entry gesture than 1:1 chat. Reuse the recorder stack even if Posts starts recording from a dedicated `Voice` attachment button instead of the chat mic's long-press affordance.
- [ ] After stopping a recording, show the voice clip as an attached draft preview in compose before posting. Do not send immediately on record stop unless the product contract changes.
- [ ] Update the compose sheet to support attachments while staying within the spec's "one media type per post" rule.
- [ ] Add heart-only reactions on comments inside the comments sheet.
- [ ] Render the expiry footer and countdown state on cards, and update it when comments extend the post lifetime.

### Tests and exit gate

- [ ] Start RED with targeted failing tests for:
  - `post_comment`, `post_reaction`, and `post_comment_reaction` payload parsing
  - comment, reaction, comment-heart, expiry, and post-media persistence helpers and repos
  - `send_post_comment`, `send_post_reaction`, `send_post_comment_reaction`, expiry lifecycle, `load_post_comments`, and media-attach use cases
  - comments-sheet, image-carousel, video-card, expiry-footer, and compose-attachment widget states
- [ ] Add payload parsing tests for `post_comment`, `post_reaction`, and `post_comment_reaction`.
- [ ] Add DB tests that verify comment insertion resets expiry bookkeeping and expired posts clean up attached media rows.
- [ ] Add integration-with-fakes coverage for comment replay after offline drain, reaction idempotency, comment-heart idempotency, expiry sweep, notification routing, and media metadata restore after restart.
- [ ] Add integration tests that prove the persisted post recipient set is reused for:
  - comment fanout
  - reaction fanout
  - media `allowedPeers`
- [ ] Add 2-device tests for image, video, and voice post delivery, comment replay after offline inbox drain, comment-heart behavior, reaction idempotency, and hydrated media restore after restart.
- [ ] Add a repeatable simulator or CLI-backed media-post smoke command that covers image, video, and voice flows.
- [ ] Exit only when media posts, comment hearts, and expiry lifecycle all behave correctly after restart and replay.

## Phase 3: People Nearby and Privacy

Outcome: nearby-scoped posts work with real location privacy rules instead of a UI-only radius selector.

### Agent Skills

- Primary: `$mobile-location-privacy-and-eligibility`
- Also use: `$flutter-feature-module-implementer`, `$flutter-sqlite-migrations-and-repositories`, `$flutter-test-orchestrator`
- Use `$mobile-notification-routing-and-deep-linking` only if nearby/privacy changes require new notification payloads or tap targets.

Why this is a real phase: `lib/features/contacts/domain/models/contact_model.dart` exists, but it currently has no location fields or nearby-presence model, there are no settings controls for location/privacy, and there is no persistence layer for proximity eligibility. This is not just a filter on the receiver's feed.

### Product and data model

- [ ] Lock the Phase 3 implementation contract before coding:
  - use `geolocator` in `pubspec.yaml` for foreground location access and distance calculation in v1
  - do not add `permission_handler`; keep permission flow inside the location service layer
  - do not add background location, geofencing, or always-on tracking in v1
- [ ] Keep the audience rule as sender-side recipient selection using the freshest known friend locations.
- [ ] Represent shared nearby presence as a rounded coordinate snapshot, not precise live tracking:
  - store and transmit `lat_e3` and `lng_e3` rounded to 3 decimal places
  - include `captured_at` and reported `accuracy_m`
  - use the same coarse snapshot for card distance labels and nearby eligibility
- [ ] Set the v1 freshness rule now: a nearby snapshot is fresh for 30 minutes, then becomes ineligible until refreshed.
- [ ] Set the v1 refresh cadence now:
  - refresh local nearby presence on app startup and app resume only when permission is already granted and location services are available
  - refresh when the Posts screen opens if the current snapshot is stale
  - refresh when the user selects `People Nearby` in compose and the snapshot is stale
  - do not run periodic background refresh jobs in v1
- [ ] Keep startup and resume refresh silent and non-interactive:
  - never trigger a location permission prompt from startup or resume recovery
  - only interactive Settings or compose actions may request permission
- [ ] Invalidate nearby presence immediately, not only by TTL:
  - when nearby sharing is turned off
  - when OS permission is revoked
  - when device location services are disabled
  - when the stored local snapshot is explicitly cleared
- [ ] Keep coarse location data out of `ContactModel` unless it becomes a first-class contact property. Prefer a Posts-specific nearby presence table.
- [ ] Persist recipient qualification results at send time so inbox replay does not re-run the nearby filter later with different location data.
- [ ] Persist the sender snapshot used for eligibility on the post record so later pass-along checks use the original nearby anchor, not a new location sample.

### Platform dependencies and permissions

- [ ] Add `geolocator` to `pubspec.yaml`.
- [ ] Add Android foreground location permissions in `android/app/src/main/AndroidManifest.xml`:
  - `ACCESS_COARSE_LOCATION`
  - `ACCESS_FINE_LOCATION`
- [ ] Add iOS foreground usage copy in `ios/Runner/Info.plist`:
  - `NSLocationWhenInUseUsageDescription`
- [ ] Keep the v1 permission flow explicit:
  - request location only when the user enables nearby sharing in Settings or chooses `People Nearby` in compose
  - if permission is denied, keep nearby posting disabled and explain why in UI
  - if permission is denied forever, show an `Open Settings` action instead of retrying blindly
- [ ] Keep nearby browsing passive in v1: users can still read already-delivered nearby posts without granting location, but they cannot publish new nearby posts or refresh nearby participation without permission.

### Database

- [ ] Bump the database version in `lib/main.dart` and register the Phase 3 migration there.
- [ ] Add a migration such as `lib/core/database/migrations/029_posts_nearby.dart`.
- [ ] Add helper files for nearby state, for example:
  - `lib/core/database/helpers/post_location_presence_db_helpers.dart`
  - `lib/core/database/helpers/post_privacy_state_db_helpers.dart`
- [ ] Add local tables for:
  - last known coarse friend location snapshot keyed by friend peer id
  - local user nearby sharing state
  - location freshness timestamp and last permission status
- [ ] Make the nearby schema concrete enough for replay-safe behavior:
  - friend snapshot rows store `peer_id`, `lat_e3`, `lng_e3`, `captured_at`, `accuracy_m`, and `updated_at`
  - local privacy state stores `sharing_enabled`, `permission_state`, `last_local_lat_e3`, `last_local_lng_e3`, and `last_local_captured_at`
  - `posts` or `post_recipients` stores the sender snapshot and radius metadata used at qualification time
- [ ] Treat the DB-backed nearby privacy state as the single source of truth for sharing enablement and freshness. Do not introduce a parallel SecureKeyStore boolean for nearby sharing.

### Domain and application

- [ ] Add nearby-specific models and repos under `lib/features/posts/`:
  - `contact_presence_snapshot.dart`
  - `posts_privacy_settings.dart`
  - `nearby_eligibility_service.dart`
- [ ] Add a wrapper over `geolocator` under `lib/features/posts/` instead of calling the plugin from widgets:
  - `nearby_location_service.dart`
- [ ] Add use cases for:
  - refreshing own coarse location
  - computing eligible recipients for a nearby post
  - expiring stale location snapshots
- [ ] Add a nearby-presence listener layer for `post_presence_update` envelopes instead of writing presence rows straight from the router:
  - validate and persist direct-friend snapshots
  - emit refresh signals for nearby eligibility consumers
- [ ] Hook resume behavior into `lib/core/lifecycle/handle_app_resumed.dart` so nearby state is refreshed when the app becomes active again.
- [ ] When nearby refresh is added to `handleAppResumed`, update its named-parameter signature and callers explicitly instead of reaching into nearby state through globals.
- [ ] Add a typed presence envelope for nearby participation, for example `post_presence_update`, and route it through `lib/core/services/incoming_message_router.dart`.
- [ ] Keep nearby presence fanout limited to direct friends only. Do not relay presence to friends-of-friends.

### App wiring

- [ ] Construct and start the nearby-presence listener in `lib/main.dart` beside the other typed listeners.
- [ ] Dispose of the nearby-presence listener in `_MyAppState.dispose()`.
- [ ] Make Settings read and write nearby-sharing state through the Posts nearby repository, not through a separate preference helper in secure storage.

### Settings and UI

- [ ] Add nearby/location controls to Settings:
  - `lib/features/settings/presentation/screens/settings_wired.dart`
  - `lib/features/settings/presentation/screens/settings_screen.dart`
  - new widgets such as `posts_nearby_settings_card.dart`
- [ ] Remove any feed-level privacy status panel from the Posts screen. Do not mirror nearby state persistently in feed chrome.
- [ ] Update the compose sheet to be the only contextual nearby status surface:
  - disable `People Nearby` posting when location sharing is off or stale
  - show inline nearby status and next-step actions in compose instead of a feed banner or panel
- [ ] Make the compose error states explicit:
  - permission missing
  - device location services off
  - nearby sharing off in Settings
  - nearby snapshot stale and refresh in progress
- [ ] Make the stale nearby CTA explicit in compose copy and interaction:
  - the blocked stale state should clearly tell the user `Refresh nearby before posting`
  - the primary next action in that state should be `Refresh nearby`
- [ ] Render nearby distance labels on eligible cards using the same stored coarse snapshot and distance calculation used for qualification.
- [ ] Keep the privacy copy concrete:
  - nearby uses approximate location only
  - nearby does not expose live maps or strangers
  - nearby sharing is with direct friends only
  - the feed itself does not need a persistent privacy summary

### Bridge and Go

- [ ] Keep `go-mknoon/bridge/bridge.go` and `go-mknoon/node/node.go` unchanged unless nearby delivery proves too slow with normal envelopes.
- [ ] If a later optimization is needed, add it only after measuring a real bottleneck. Do not front-load native complexity here.

### Tests and exit gate

- [ ] Start RED with targeted failing tests for:
  - fresh vs stale snapshot eligibility
  - rounded-coordinate distance decisions around the configured radius boundaries
  - permission missing, denied forever, and device-location-off states
  - Settings and compose-sheet UI state when nearby is unavailable or stale
- [ ] Add deterministic location-service and permission-state fakes before production code so Phase 3 can stay strict TDD.
- [ ] Add tests for stale vs fresh location eligibility.
- [ ] Add tests for rounded-coordinate distance eligibility around the 500m and 1km thresholds.
- [ ] Add tests for privacy-off behavior, immediate nearby invalidation, and app-resume refresh behavior.
- [ ] Add tests for permission denied and denied-forever UI behavior.
- [ ] Add tests that startup and resume refresh stay silent when permission is missing instead of prompting.
- [ ] Add integration-with-fakes coverage for nearby presence updates, stale-snapshot expiry, and replay-safe recipient qualification.
- [ ] Add a 2-device test where only friends inside the chosen radius receive the post.
- [ ] Add an offline replay test where a recipient who qualified at send time still receives the nearby post after coming back online, without recomputing eligibility on replay.
- [ ] Add a repeatable simulator smoke command for permission flow plus nearby send eligibility.
- [ ] Exit only when nearby posts are privacy-correct, not just visually labeled.

## Phase 4: Pass Along and Extended-Network Delivery

Outcome: a friend can explicitly pass a post along, and the receiver sees trustworthy attribution instead of system-driven stranger discovery.

### Agent Skills

- Primary: `$flutter-feature-module-implementer`
- Also use: `$flutter-sqlite-migrations-and-repositories`, `$flutter-test-orchestrator`
- Use `$senior-ui-ux-designer` only if pass-along attribution, scope badges, or trust-chain readability need focused refinement.

### Transport and routing

- [ ] Extend `lib/core/services/incoming_message_router.dart` with `post_pass`.
- [ ] Keep pass-along as a regular message envelope sent through the same P2P and inbox path.

### Database

- [ ] Bump the database version in `lib/main.dart` and register the Phase 4 migration there.
- [ ] Add a migration such as `lib/core/database/migrations/030_posts_pass_along.dart`.
- [ ] Add helper files for:
  - `lib/core/database/helpers/post_passes_db_helpers.dart`
  - `lib/core/database/helpers/post_origin_db_helpers.dart`
- [ ] Persist enough metadata to render:
  - a fully renderable original-post snapshot
  - original author
  - pass-along actor
  - original audience scope
  - original nearby radius if applicable

### Domain and application

- [ ] Add models for pass-along attribution and origin chain.
- [ ] Add use cases:
  - `pass_post_along_use_case.dart`
  - `handle_incoming_passed_post_use_case.dart`
- [ ] Enforce spec rules in application code, not UI only:
  - pass-along is a single extra hop in v1
  - transport sender must match the passing friend in the payload
  - the passing friend must still be a known direct contact locally
  - `Pick People` posts cannot be passed along
  - nearby-scoped reshares keep the original radius anchor
- [ ] Keep the pass-along payload renderable without network reconstruction:
  - include the original post content snapshot needed to render the card locally
  - do not depend on fetching or inferring the original post later from a missing direct-contact thread
  - do not add mutual-friend badge metadata in v1
- [ ] Persist an anonymous sender-side share count for the original author's own cards. Receivers still only see attribution, not a social-proof badge.
- [ ] Lock the pass-along dedupe rule now:
  - dedupe repeated deliveries by original post identity, not by transport message id alone
  - do not create multiple feed cards for the same original post when duplicates or repeated pass deliveries arrive
  - if a duplicate pass arrives later, merge or ignore it without destabilizing the visible attribution line in v1

### UI

- [ ] Update post cards to show:
  - pass-along attribution
  - no mutual-friends badge on reshared posts
  - correct scope badge combinations
- [ ] Show the original poster's share count only on their own cards and management states.
- [ ] Hide or disable the pass-along action on `Pick People` posts in the Posts card widget.
- [ ] Ensure passed-along items render in the same feed ordering as direct posts.

### Bridge and Go

- [ ] No dedicated Go transport changes planned in this phase.
- [ ] If payload growth becomes a problem, measure it first in `go-mknoon/bridge/bridge_test.go` and `go-mknoon/integration/*` before changing native code.

### Tests and exit gate

- [ ] Start RED with targeted failing tests for:
  - pass-along rule enforcement in application code
  - origin-chain and attribution persistence
  - post-card and detail-state rendering for passed-along content, including sender-only share counts
- [ ] Add tests that prove `Pick People` posts cannot be reshared.
- [ ] Add tests that prove v1 pass-along stops after one explicit extra hop.
- [ ] Add tests that reject pass envelopes when the passing friend does not match `message.from` or is not a known direct contact.
- [ ] Add tests that prove nearby pass-along still respects the original radius.
- [ ] Add tests that duplicate pass deliveries merge into one local feed item instead of creating multiple cards.
- [ ] Add integration-with-fakes coverage for original author -> passing friend -> receiving friend-of-friend before running device smoke.
- [ ] Add 3-device integration coverage: original author, passing friend, receiving friend-of-friend.
- [ ] Add a repeatable simulator or CLI-backed 3-device pass-along smoke command.
- [ ] Exit only when the trust chain is visible and rules are enforced serverless.

## Phase 5: Pinned Posts and Lifecycle Controls

Outcome: standing offers behave correctly across normal feed, pinned section, dismissal, sender edits, and sender removal.

### Agent Skills

- Primary: `$flutter-feature-module-implementer`
- Also use: `$flutter-sqlite-migrations-and-repositories`, `$flutter-test-orchestrator`
- Use `$senior-ui-ux-designer` only if pinned-section hierarchy, management affordances, or dismissal clarity need a targeted polish pass.

### Transport and routing

- [ ] Extend `lib/core/services/incoming_message_router.dart` with:
  - `post_pin_update`
  - `post_pin_remove`
- [ ] Keep pin-update and pin-remove delivery on the same direct-send and inbox path as other Posts envelopes.

### Database

- [ ] Bump the database version in `lib/main.dart` and register the Phase 5 migration there.
- [ ] Add a migration such as `lib/core/database/migrations/031_posts_pins.dart`.
- [ ] Add helper files for:
  - `lib/core/database/helpers/post_pins_db_helpers.dart`
  - `lib/core/database/helpers/post_pin_dismissals_db_helpers.dart`
- [ ] Persist:
  - active pin state
  - sender pin updates/removals
  - local dismissals per receiver

### Domain and application

- [ ] Add use cases:
  - `pin_post_use_case.dart`
  - `remove_pin_use_case.dart`
  - `dismiss_pin_use_case.dart`
  - `edit_pinned_post_use_case.dart`
- [ ] Add incoming handlers for `post_pin_update` and `post_pin_remove`.
- [ ] Make sure a sender removal updates both the pinned section and the regular feed entry correctly.

### UI

- [ ] Add a pinned section and full-screen "see all" flow under `lib/features/posts/presentation/widgets/`.
- [ ] Match the collapsed pinned-header design from the spec:
  - stacked author avatars
  - `+N` overflow badge when needed
- [ ] Add sender-only management affordances for edit/remove.
- [ ] Add receiver-only dismiss behavior that stays local.
- [ ] Add the compact pinned-card action set, including `Message [name]` for direct contact follow-up from a pin.
- [ ] Add the compose-time active-pins banner and manage affordance when the author already has active pinned posts.
- [ ] Ensure pinned posts still appear in the normal feed for the initial 24-hour window.

### Tests and exit gate

- [ ] Start RED with targeted failing tests for:
  - `post_pin_update` and `post_pin_remove` routing and payload parsing
  - pin lifecycle state transitions and persistence
  - sender edit/remove propagation
  - pinned-section, stacked-avatar header, compose-banner, and local-dismiss widget states
- [ ] Add router tests for `post_pin_update` and `post_pin_remove`.
- [ ] Add tests for local dismiss persistence.
- [ ] Add tests for sender edit/remove propagation.
- [ ] Add tests for the sender-only active-pins banner and `Message [name]` pinned-card action.
- [ ] Add integration-with-fakes coverage for sender edit/remove and receiver-only local dismiss interacting correctly.
- [ ] Add restart coverage: pinned posts and dismissals must survive app restart.
- [ ] Add a repeatable simulator or CLI-backed pinned-post lifecycle smoke command.
- [ ] Exit only when pinned posts behave as standing offers, not duplicated or orphaned records.

## Final Hardening Gate

### Agent Skills

- Primary: `$flutter-test-orchestrator`
- Also use: `$mobile-notification-routing-and-deep-linking`
- Use `$mobile-network-resilience-qa` for simulator or device validation of replay, startup, resume, and notification-triggered catch-up.

- [ ] Add feature-level tests under `test/features/posts/`.
- [ ] Add router coverage for every post envelope in `test/core/services/`.
- [ ] Add migration regression coverage for every new DB version touched in `lib/main.dart`.
- [ ] Add at least one end-to-end integration flow under `integration_test/` for the full sequence:
  - create post
  - receive post
  - comment
  - pass along
  - pin
  - restart and recover state
- [ ] Add notification coverage for:
  - foreground local notification
  - background push fallback notification
  - tap-through into the Posts surface
- [ ] Add targeted Go-side regression tests only if native changes were actually made:
  - `go-mknoon/bridge/bridge_test.go`
  - `go-mknoon/integration/local_relay_harness_test.go`
  - additional `go-mknoon/integration/*` tests only when a native behavior changes
- [ ] Keep at least one repeatable CLI or simulator command per user-visible Posts smoke scenario and document those commands in the phase notes or PR.

## Recommended Delivery Order

1. Phase 1
2. Phase 2
3. Phase 3
4. Phase 4
5. Phase 5

This order keeps the hardest ambiguity out of the first vertical slice. It gives you a real Posts feature quickly, then adds engagement, then privacy-sensitive nearby logic, then trust-mediated extended reach, and finally long-lived pin lifecycle.
