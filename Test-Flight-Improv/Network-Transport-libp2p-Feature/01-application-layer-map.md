# Application Layer Map — Data Flow Above the Bridge

> **Scope:** Everything between the bridge and the UI widgets.
> **Includes:** P2P service, IncomingMessageRouter dispatch table, all listeners (constructor deps, repos written, streams exposed, cross-feature side effects), repository registry, cross-feature connections, DI construction order.
> **Excludes:** Go protocols and bridge commands (see `00`), Wired widgets and navigation (see `02`), timeouts and performance (see `03`), routing decision logic (see `04`).

---

## 1. Layer Stack Overview

```
+------------------------------------------------------+
|  UI (Wired widgets — see 02-ui-wiring-map.md)        |
|  subscribe to listener streams, call use cases        |
+------------------------------------------------------+
|  Listeners (per-feature, process incoming messages)   |
|  decrypt → validate → persist → emit to UI streams    |
+------------------------------------------------------+
|  IncomingMessageRouter (dispatch by type field)       |
|  single subscriber to P2PService.messageStream        |
+------------------------------------------------------+
|  P2PService (wraps bridge, merges local WiFi)         |
|  exposes messageStream + stateStream                  |
+------------------------------------------------------+
|  Bridge (MethodChannel / EventChannel — see 00-*)     |
+------------------------------------------------------+
```

Group messages bypass the router — they flow from bridge callbacks directly to GroupMessageListener.

---

## 2. P2P Service Layer

**Interface**: `lib/core/services/p2p_service.dart` (19 methods + 4 getters)
**Implementation**: `lib/core/services/p2p_service_impl.dart`

### Constructor Dependencies

```
P2PServiceImpl({
  required Bridge bridge,
  LocalP2PService? localP2PService,
  PushTokenStore? pushTokenStore,
  required InboxStagingRepository inboxStagingRepository,
  ReplayRecoveredInboxChatMessage? replayRecoveredInboxChatMessage,
  ReplayRecoveredInboxIntroductionMessage? replayRecoveredInboxIntroductionMessage,
})
```

### What It Does

- Wraps all bridge send/receive operations
- Merges local WiFi messages into the same `_messageController` stream (same downstream stream, but tagged with `transport: 'wifi'`)
- Manages node state (`_stateController`) from bridge callbacks: peer connect/disconnect, address changes, relay state
- Durable staging: direct incoming `chat_message` envelopes with a non-null `confirmNonce` are written to `InboxStagingRepository` before replay; `introduction` entries are staged and replayed through the relay inbox drain path

### Streams Exposed

| Stream | Consumers |
|---|---|
| `messageStream` | IncomingMessageRouter (sole subscriber) |
| `stateStream` | Retriers (PendingMessageRetrier, KeyExchangeRetrier, PendingPostDeliveryRetrier, PendingPostFollowOnRetrier, PendingPostMediaUploadRetrier), ConnectionStatusIndicator |

### Key Public Methods

| Method | Purpose |
|---|---|
| `startNode` / `startNodeCore` / `warmBackground` / `stopNode` | Node lifecycle |
| `sendMessage` / `sendMessageWithReply` | Unicast P2P send |
| `discoverPeer` / `dialPeer` | Rendezvous + circuit relay connect |
| `storeInInbox` / `retrieveInbox` / `drainOfflineInbox` | Relay store-and-forward |
| `probeRelay` | Lightweight relay reservation check |
| `performImmediateHealthCheck` | On-demand node health probe |
| `isConnectedToPeer` | Peer connection status check |
| `isLocalPeer` / `sendLocalMessage` / `sendLocalMedia` | WiFi-first path |
| `registerPushToken` | FCM token registration |
| `dispose` | Cleanup / teardown |

### Bridge Callback Wiring

| Bridge Callback | P2PServiceImpl Handler |
|---|---|
| `onMessageReceived` | `_handleMessageReceived` → classify → emit or durable-stage |
| `onPeerConnected` / `onPeerDisconnected` | Update `_currentState.connections` |
| `onAddressesUpdated` / `onRelayStateChanged` | Update state stream |
| `onGroupMessageReceived` | NOT wired here — wired in main.dart to a separate StreamController |
| `onGroupReactionReceived` | NOT wired here — wired in main.dart to a separate StreamController |

### Durable Staging (Inbox Replay)

When a live direct `chat_message` arrives with a non-null `confirmNonce` (deferred ACK), P2PServiceImpl stages it to `InboxStagingRepository`, confirms the nonce to the bridge, then immediately replays via closure:
- `chatMessageListener.processIncomingMessage`

Introduction messages are NOT staged via this direct-message path. They arrive in `InboxStagingRepository` only through the relay inbox drain path (`_drainOfflineInboxDurably`), and are replayed via:
- `introductionListener.processIncomingMessage`

The chat message replay closure also invokes `resolveUnknownInboxSender` on `unknownSender` result, reading `IntroductionRepository` and potentially writing `ContactRepository`. The introduction replay closure does NOT call `resolveUnknownInboxSender` — it simply maps the outcome to a disposition.

This creates a **direct coupling from the service layer into two feature-layer listeners** at construction time. The `late final` pattern in main.dart allows `P2PServiceImpl` to be constructed before those listeners are assigned; the replay closures are only invoked later during staged replay.

---

## 3. IncomingMessageRouter

**File**: `lib/core/services/incoming_message_router.dart`
**Constructor**: `IncomingMessageRouter({required P2PService p2pService})`

Subscribes to `p2pService.messageStream` on `.start()`. Filters out outgoing messages, JSON-decodes content, dispatches by `type` field.

### Dispatch Table

| `type` String | Output Stream | Listener |
|---|---|---|
| `contact_request` | `contactRequestStream` | ContactRequestListener |
| `chat_message` | `chatMessageStream` | ChatMessageListener |
| `profile_update` | `profileUpdateStream` | ProfileUpdateListener |
| `message_reaction` | `reactionStream` | ReactionListener |
| `message_deletion` | `messageDeletionStream` | MessageDeletionListener |
| `group_invite` | `groupInviteStream` | GroupInviteListener |
| `group_key_update` | `groupKeyUpdateStream` | GroupKeyUpdateListener |
| `introduction` | `introductionStream` | IntroductionListener |
| `post_create` | `postCreateStream` | PostListener |
| `post_comment` | `postCommentStream` | PostCommentListener |
| `post_reaction` | `postReactionStream` | PostReactionListener |
| `post_comment_reaction` | `postCommentReactionStream` | PostReactionListener |
| `post_presence_update` | `postPresenceStream` | PostPresenceListener |
| `post_pass` | `postPassStream` | PostPassListener |
| `post_pin_update` | `postPinUpdateStream` | PostPinListener |
| `post_pin_remove` | `postPinRemoveStream` | PostPinListener |
| `delivery_receipt` | (dropped — no-op) | Legacy, no listener |
| anything else | `unknownMessageStream` | No production subscriber |

All StreamControllers are `.broadcast()`. The router also parses a `version` field from the envelope for diagnostic logging, but routing is purely by `type`.

### What Does NOT Go Through the Router

Group pubsub messages (`group_message:received`, `group_reaction:received`) bypass the router entirely. They flow from bridge callbacks through dedicated StreamControllers in main.dart directly to GroupMessageListener.

---

## 4. Listener Catalogue

Each listener subscribes to a router stream (or direct bridge callback), processes incoming messages, writes to repos, and exposes streams for UI consumption.

### ChatMessageListener

**File**: `lib/features/conversation/application/chat_message_listener.dart`

| Aspect | Detail |
|---|---|
| Input | Injected `Stream<ChatMessage> chatMessageStream` (from router in production) |
| Repos written | `MessageRepository`, `ContactRepository` (avatar/key updates), `MediaAttachmentRepository` (auto-download) |
| Bridge commands | `callP2PConfirmDirectMessage` (deferred ACK). Decryption (`callDecryptMessage` v2) is delegated to `handleIncomingChatMessage` use case. |
| Constructor deps (notable) | `RecentRemoteNotificationGate`, `ActiveConversationTracker`, `backgroundNotificationDuplicateGuardDelay` (APNs/FCM dedup) |
| Streams exposed | `incomingMessageStream`, `contactUpdatedStream` |
| Side effects | Auto-downloads media attachments, shows notifications, downloads profile pictures. Archived-sender suppression: message is persisted but notification and `incomingMessageStream` emission are both suppressed. |
| Public API | `processIncomingMessage({suppressNotification})` — callers (e.g. durable replay) can suppress notification via flag |

**Special role**: Acts as the **central contact-update bus** for wired surfaces that need refreshed contact data. `main.dart` forwards profile/avatar updates and ML-KEM key updates into `emitContactUpdate()`, and `FeedWired`, `OrbitWired`, and `ConversationWired` subscribe to `chatMessageListener.contactUpdatedStream`. The listener also has its own internal contact-update path from `handleIncomingChatMessage` returning an `updatedContact` - these are separate emission paths into the same `contactUpdatedStream`.

### ContactRequestListener

**File**: `lib/features/contact_request/application/contact_request_listener.dart`

| Aspect | Detail |
|---|---|
| Input | `messageRouter.contactRequestStream` |
| Repos written | `ContactRequestRepository`, `ContactRepository` (ML-KEM key update) |
| Bridge commands | Delegated to `handleIncomingMessage` use case (`callVerifyPayload`, `callDecryptMessage` v2) — not called directly in the listener |
| Constructor deps (notable) | `downloadProfilePictureFn` (avatar prefetch), `shouldSuppressPresentationForPeerId`, `getOwnPrivateKey` (v2 key resolution), `getOwnPeerId`, `emitRecoveredIntroductionStatus: void Function(IntroductionModel)?` |
| Streams exposed | `requestStream`, `contactKeyUpdatedStream` |
| Dedup | Own `ReplayCache` (LRU, 1000 entries, 25h TTL) |

**Cross-feature**: The `emitRecoveredIntroductionStatus` closure (injected from main.dart, not a direct reference to IntroductionListener) publishes to `introStatusChangedStream` when silent intro recovery succeeds. Also calls `AttemptSilentIntroContactRequestRecovery` (aliased `attemptSilentIntroRecovery`) which reads `IntroductionRepository` and writes to `MessageRepository`.

### ReactionListener

**File**: `lib/features/conversation/application/reaction_listener.dart`

| Aspect | Detail |
|---|---|
| Input | `messageRouter.reactionStream` |
| Repos written | `ReactionRepository` (upsert/delete) |
| Bridge commands | Delegated to `handleIncomingReaction` use case (`callDecryptMessage` v2) |
| Constructor deps (notable) | `ContactRepository` (blocked-sender check) |
| Streams exposed | `incomingReactionStream`, `incomingReactionChangeStream` |

Reads `MessageRepository` to verify target message exists.

### MessageDeletionListener

**File**: `lib/features/conversation/application/message_deletion_listener.dart`

| Aspect | Detail |
|---|---|
| Input | `messageRouter.messageDeletionStream` |
| Repos written | `MessageRepository` (soft-delete), `ReactionRepository?` (cascade-delete, nullable), `MediaAttachmentRepository?` (hard-delete, nullable) |
| Bridge commands | Delegated to `handleIncomingMessageDeletion` use case (`callDecryptMessage` v2) |
| Constructor deps (notable) | `ContactRepository` (required, sender validation), `getOwnMlKemSecretKey` (optional) |
| Streams exposed | `incomingDeletionStream` |
| Side effects | Deletes local media files from disk via `MediaFileManager` |

### GroupMessageListener

**File**: `lib/features/groups/application/group_message_listener.dart`

| Aspect | Detail |
|---|---|
| Input | **NOT from router** — receives `Stream<Map<String,dynamic>>` as argument to `start()` (from dedicated StreamControllers in main.dart wired to `bridge.onGroupMessageReceived` / `bridge.onGroupReactionReceived`) |
| Repos written | `GroupMessageRepository`, `GroupRepository` (member updates from system msgs), `ReactionRepository`, `MediaAttachmentRepository` |
| Bridge commands | `callGroupUpdateConfig` (syncs group config), `callGroupLeave` (on self-removal AND `group_dissolved`) |
| Constructor deps (notable) | `NotificationService`, `ActiveConversationTracker`, `AppLifecycleState` getter, `RecentRemoteNotificationGate`, `DownloadGroupAvatarFn`, `getSelfPeerId` |
| Streams exposed | `groupMessageStream`, `groupRemovedStream`, `groupReactionChangeStream` |
| Side effects | Shows notifications (mute-aware), auto-downloads media, downloads group avatars |
| System messages | Handles `member_added`, `members_added`, `member_removed`, `member_role_updated`, `group_dissolved`, `group_metadata_updated`, `member_joined`, `key_rotated` - membership/config events update `GroupRepository` state; `key_rotated` is currently logged but does not mutate `GroupRepository` state in this listener |
| Internal | Per-group serialized config work queue (`_groupConfigWorkQueue`), stale-event watermark filtering |

**Cross-feature**: Uses `ReactionRepository` and `MediaAttachmentRepository` from the conversation feature. Exposes `handleReplayEnvelope()` as a public method for `drainGroupOfflineInbox` to replay offline messages.

### GroupInviteListener

**File**: `lib/features/groups/application/group_invite_listener.dart`

| Aspect | Detail |
|---|---|
| Input | `messageRouter.groupInviteStream` |
| Repos written | `PendingGroupInviteRepository` |
| Bridge commands | Delegated to `storeIncomingPendingGroupInvite` use case (`callDecryptMessage` v2 ML-KEM) |
| Constructor deps (notable) | `GroupRepository` (required), `ContactRepository` (required, blocked-sender check), `GroupMessageRepository?` (optional), `MediaAttachmentRepository?` (optional) |
| Streams exposed | `groupJoinedStream` (exists but **never emitted** — dead code), `pendingInviteStream` |

Does NOT auto-join. Join requires explicit user action.

### GroupKeyUpdateListener

**File**: `lib/features/groups/application/group_key_update_listener.dart`

| Aspect | Detail |
|---|---|
| Input | `messageRouter.groupKeyUpdateStream` |
| Repos written | `GroupRepository` (saveKey) |
| Bridge commands | `callDecryptMessage`, `callGroupUpdateKey` (pushes key into Go's pubsub validator) |
| Streams exposed | None — pure side-effect |

### IntroductionListener

**File**: `lib/features/introduction/application/introduction_listener.dart`

| Aspect | Detail |
|---|---|
| Input | `messageRouter.introductionStream` |
| Repos written | `IntroductionRepository`, `MessageRepository?` (system messages in conversation threads — **nullable**), `ContactRepository` (new contact on mutual acceptance via `handleMutualAcceptance` → `contactRepo.addContact()`) |
| Bridge commands | `callDecryptMessage` (v2, called directly), `callP2PConfirmDirectMessage` |
| Constructor deps (notable) | `getOwnPeerId` (required), `getOwnMlKemSecretKey` (required) |
| Streams exposed | `introReceivedStream`, `introStatusChangedStream` |
| Side effects | Shows notifications via `NotificationService` (conditional on `mutualAccepted` status for accept events). V1 fallback parsing (`IntroductionPayload.fromJson`) is also present. |

**Cross-feature**: Writes system messages into `MessageRepository` (conversation feature) via `insertIntroSystemMessage` and multiple use cases (5+ files import `MessageRepository`). Also has public `emitIntroStatusChanged()` called by ContactRequestListener.

### ProfileUpdateListener

**File**: `lib/features/settings/application/profile_update_listener.dart`

| Aspect | Detail |
|---|---|
| Input | `messageRouter.profileUpdateStream` |
| Repos written | `ContactRepository` (avatar version) |
| Bridge commands | Calls injectable `downloadProfilePictureFn` (the actual bridge command is determined by the injected use case, not this file) |
| Streams exposed | `contactUpdatedStream` |
| Retry logic | Attempts download twice with configurable `retryDelay` (default 5s) before giving up |
| Dedup | Skips download if `contact.avatarVersion == avatarVersion` (no-op on same version) |

**Routing**: No direct UI subscription. Output is forwarded in main.dart to `chatMessageListener.emitContactUpdate` (the contact-update bus).

### PostListener

**File**: `lib/features/posts/application/post_listener.dart`

| Aspect | Detail |
|---|---|
| Input | `messageRouter.postCreateStream` |
| Repos written | `PostRepository` |
| Repos read | `ContactRepository` (sender lookup, blocked-sender check) |
| Bridge commands | Optional `Bridge?` + `getOwnMlKemSecretKey` (delegated to use case for v2 decryption) |
| Constructor deps (notable) | `hydratePostMediaFn` (injectable media hydration) |
| Streams exposed | `incomingPostStream` |
| Side effects | Shows notifications via `NotificationService` (suppressed for archived senders) |

### PostCommentListener

**File**: `lib/features/posts/application/post_comment_listener.dart`

| Aspect | Detail |
|---|---|
| Input | `messageRouter.postCommentStream` |
| Repos written | `PostRepository` |
| Repos read | `ContactRepository` (sender lookup) |
| Streams exposed | `incomingCommentStream` |
| Side effects | Shows notifications via `NotificationService` (when comment is on own post, sender not archived). Calls `reconcilePendingPostChildEvents`. |

Serializes processing via future chain (`_pendingMessageHandling`) to prevent dedup races.

### PostReactionListener

**File**: `lib/features/posts/application/post_reaction_listener.dart`

| Aspect | Detail |
|---|---|
| Input | **Two streams**: `messageRouter.postReactionStream` + `messageRouter.postCommentReactionStream` |
| Repos written | `PostRepository` |
| Repos read | `ContactRepository` (sender lookup) |
| Streams exposed | `incomingPostReactionStream`, `incomingCommentReactionStream` |
| Side effects | Shows notifications via `NotificationService` (post reactions only, not comment reactions) |

### PostPresenceListener

**File**: `lib/features/posts/application/post_presence_listener.dart`

| Aspect | Detail |
|---|---|
| Input | `messageRouter.postPresenceStream` |
| Repos written | `ContactPresenceSnapshotRepository` |
| Repos read | `ContactRepository` (blocked/unknown-sender check) |
| Streams exposed | `incomingPresenceStream` |

### PostPassListener

**File**: `lib/features/posts/application/post_pass_listener.dart`

| Aspect | Detail |
|---|---|
| Input | `messageRouter.postPassStream` |
| Repos written | `PostRepository` |
| Repos read | `ContactRepository` (sender lookup) |
| Bridge commands | Optional `Bridge?` + `getOwnMlKemSecretKey` (delegated to use case for v2 decryption) |
| Constructor deps (notable) | `hydratePostMediaFn` (injectable media hydration) |
| Streams exposed | `incomingPostPassStream` |

### PostPinListener

**File**: `lib/features/posts/application/post_pin_listener.dart`

| Aspect | Detail |
|---|---|
| Input | **Two streams**: `messageRouter.postPinUpdateStream` + `messageRouter.postPinRemoveStream` |
| Repos written | `PostRepository` |
| Repos read | `ContactRepository` (sender lookup) |
| Streams exposed | None — fire-and-forget writes via `handleIncomingPostPinUpdate` / `handleIncomingPostPinRemove` use cases |

---

## 5. Repository Layer

All repos use constructor-injected DB helper functions (not raw DB references).

### Repository Registry

| Repository | Tables | Feature |
|---|---|---|
| `IdentityRepositoryImpl` | `identity` | identity |
| `ContactRepositoryImpl` | `contacts` | contacts (shared by nearly every feature) |
| `ContactRequestRepositoryImpl` | `contact_requests` | contact_request |
| `MessageRepositoryImpl` | `messages` | conversation |
| `MediaAttachmentRepositoryImpl` | `media_attachments` | conversation (also used by groups) |
| `ReactionRepositoryImpl` | `message_reactions` | conversation (also used by groups) |
| `GroupRepositoryImpl` | `groups`, `group_members`, `group_keys` | groups |
| `GroupMessageRepositoryImpl` | `group_messages` | groups |
| `PendingGroupInviteRepositoryImpl` | `pending_group_invites` | groups |
| `GroupReactionReplayOutboxRepositoryImpl` | `group_reaction_replay_outbox` | groups |
| `IntroductionRepositoryImpl` | `introductions`, `pending_introduction_responses`, `introduction_outbox_deliveries` | introduction |
| `PostRepositoryImpl` | `posts`, `post_comments`, `post_reactions`, `post_comment_reactions`, `post_media_attachments`, `post_passes`, `post_pins`, `post_pin_dismissals`, `post_recipients`, `post_pending_child_events`, `post_follow_on_outbox_events`, `post_follow_on_outbox_recipient_deliveries`, `post_media_upload_recovery`, `post_feed_state`, `post_origin`, `post_repost_engagement_participants`, `post_repost_heart_baseline_peers`, `post_repost_projection_state`, `post_pass_avatar_snapshots` | posts |
| `PostsPrivacySettingsRepositoryImpl` | `post_privacy_state` | posts |
| `ContactPresenceSnapshotRepositoryImpl` | `post_location_presence` | posts |
| `InboxStagingRepositoryImpl` | `inbox_staging_entries` | core (durable staging) |

### Abstract Repository Interfaces (no standalone Impl)

These are secondary interfaces implemented by the primary Impl classes above. They exist as mixin-style contracts used by downstream features via runtime downcast.

| Interface | Implemented By | Consumer |
|---|---|---|
| `ConversationThreadSummaryRepository` | `MessageRepositoryImpl` | Orbit use cases (downcast `MessageRepository` at runtime) |
| `GroupThreadSummaryRepository` | `GroupMessageRepositoryImpl` | Orbit use cases (downcast `GroupMessageRepository` at runtime) |

### Cross-Feature Repo Usage

These are repos consumed outside their owning feature:

| Repo | Owning Feature | Also Used By | Why |
|---|---|---|---|
| `MessageRepository` | conversation | IntroductionListener (5+ files), ContactRequestListener, Share, Feed, Orbit (via downcast) | System messages, feed snapshots, thread summaries |
| `MediaAttachmentRepository` | conversation | GroupMessageListener, Share, Push, Feed | Shared media storage (GroupInviteListener accepts it in constructor but never uses it) |
| `ReactionRepository` | conversation | GroupMessageListener, Share, Push | Group reactions share the `message_reactions` table |
| `ContactRepository` | contacts | Nearly every listener | Universal contact lookup |
| `IntroductionRepository` | introduction | ContactRequestListener, Settings, Share | Silent intro recovery, settings display |
| `GroupRepository` | groups | Share, Push, Feed | Group metadata for delivery, notifications, feed |
| `GroupMessageRepository` | groups | Share, Feed, Orbit (via downcast) | Group thread summaries, feed snapshots |
| `PendingGroupInviteRepository` | groups | Push | Group notification route resolution |
| `PostsPrivacySettingsRepository` | posts | Settings | Privacy settings display/edit |

---

## 6. Cross-Feature Connections

These are the hidden dependencies that couple features together. They are the most important thing in this document for understanding blast radius.

### Connection 1: ContactRequest -> Introduction (one-directional)

```
ContactRequestListener                    IntroductionListener
  |                                          |
  |--emitRecoveredIntroductionStatus()------>|  (publishes to introStatusChangedStream)
  |    (injected closure, not direct ref)    |
  |                                          |
  |--AttemptSilentIntroContactRequestRecovery()
  |    reads IntroductionRepository          |
  |    writes MessageRepository              |
```

When a contact request matches an existing introduction, ContactRequestListener calls an injected closure that publishes to IntroductionListener's output stream, and writes system messages into the conversation feature's message store. The dependency is **one-directional**: ContactRequest → Introduction. Introduction does not import ContactRequestRepository anywhere.

### Connection 2: ProfileUpdate + ContactRequest -> ChatMessage (contact-update bus via stream subscriptions)

```
ProfileUpdateListener.contactUpdatedStream  (avatar updates)
  |
  +--(main.dart subscription)---> chatMessageListener.emitContactUpdate()
                                    |
ContactRequestListener              |
  .contactKeyUpdatedStream          |  (ML-KEM key updates)
  |                                 |
  +--(main.dart subscription)------>+
                                    |
                                    v
                          chatMessageListener.contactUpdatedStream
                                    |
                          +---------+---------+
                          |         |         |
                       FeedWired OrbitWired ConversationWired
```

This is a **stream-level subscription wired in main.dart**, not a repo-level cross-feature dependency. ChatMessageListener is the **single contact-update bus** consumed by the wired screens above. ProfileUpdateListener and ContactRequestListener each expose their own contact streams, and `main.dart` forwards those updates through ChatMessageListener.

### Connection 3: P2PService -> ChatMessage + Introduction (durable replay)

```
P2PServiceImpl._handleMessageReceived
  |
  +--(incoming direct chat_message with confirmNonce)---> InboxStagingRepository
  |    then replay via closure:              chatMessageListener.processIncomingMessage()
  |    if unknownSender:                     resolveUnknownInboxSender()
  |      reads IntroductionRepository, can write ContactRepository (handleMutualAcceptance)
  |
  +--(recoverable staged introduction entry from inbox drain)---> InboxStagingRepository
       then replay via closure:              introductionListener.processIncomingMessage()
```

The service layer has functional references to two feature-layer listeners, created via `late final` closures in main.dart.

### Connection 4: Introduction -> Conversation (broad MessageRepository usage)

```
IntroductionListener
  |
  +--insertIntroSystemMessage()--> MessageRepository (conversation feature)
  |                                  |
  |                                  v
  |                               ConversationWired sees system message in thread
  |
Multiple introduction use cases also import MessageRepository:
  - handle_incoming_introduction_use_case.dart
  - accept_introduction_use_case.dart
  - handle_mutual_acceptance_use_case.dart
  - expire_old_introductions_use_case.dart
```

Introduction events appear as system messages in the 1:1 conversation with the introducer. The dependency is broader than a single insertion helper — 5+ files in the introduction feature directly import `MessageRepository` from conversation.

Additionally, `introduction_outbound_delivery.dart` imports timing constants (`interactiveDirectBudget`, `interactiveLocalBudget`, `relayProbeSendAttempts`, `relayProbeRetryBackoff`) from `send_chat_message_use_case.dart` in conversation. This means introduction delivery performance is silently coupled to conversation-feature send timeout values.

### Connection 5: Group -> Conversation repos (shared tables)

```
GroupMessageListener
  |
  +--saves group reactions-----> ReactionRepository (conversation feature, message_reactions table)
  +--saves group media---------> MediaAttachmentRepository (conversation feature, media_attachments table)
```

Group features share the `message_reactions` and `media_attachments` tables with conversation features.

### Connection 6: PendingMessageRetrier (broadest coupling point)

```
PendingMessageRetrier
  |
  +-- direct deps: p2pService, messageRepo, identityRepo, contactRepo, bridge, mediaAttachmentRepo
  +-- direct static imports (not injectable — hardcoded coupling):
      +-- conversation: retryFailedMessages (retry_failed_messages_use_case.dart)
      +-- conversation: retryUnackedMessages (retry_unacked_messages_use_case.dart)
  +-- via injected closures:
      +-- conversation: recoverStuckSendingMessagesFn, retryIncompleteUploadsFn
      +-- groups: retryFailedGroupMessagesFn, retryIncompleteGroupUploadsFn, retryFailedGroupInboxStoresFn, recoverStuckSendingGroupMessagesFn, drainGroupOfflineInboxFn, rejoinGroupTopicsWithRecoveryAckEligibilityFn, acknowledgeGroupRecoveryFn
      +-- introduction: retryPendingIntroductionDeliveriesFn
      +-- (posts handled by separate PendingPostDeliveryRetrier / PendingPostMediaUploadRetrier / PendingPostFollowOnRetrier, not by PendingMessageRetrier)
```

Note: In production main.dart, the wired closure is `rejoinGroupTopicsWithRecoveryAckEligibilityFn` (the recovery-ack-eligible variant). The simpler `rejoinGroupTopicsFn` slot exists on the class but is not set in production.

This is the single widest cross-feature coupling point. It orchestrates retries across all features that can have pending outbound messages.

### Connection 7: ContactRequest -> Conversation (direct repo import)

```
recover_intro_contact_request_use_case.dart
  |
  +--imports MessageRepository (conversation feature)
  +--passes to handleMutualAcceptance → inserts system messages
```

This is a ContactRequest → Conversation connection that is distinct from the Introduction → Conversation connection in #4.

### Connection 8: Share -> Conversation + Groups + Introduction

```
share_batch_delivery_coordinator.dart
  |
  +-- imports MessageRepository (conversation)
  +-- imports MediaAttachmentRepository (conversation)
  +-- imports GroupMessageRepository (groups)
  +-- imports GroupRepository (groups)

share_target_picker_wired.dart
  +-- imports all of the above + ReactionRepository + IntroductionRepository
```

The Share feature is a broad consumer of multiple feature repos.

### Connection 9: Push -> Conversation + Groups

```
prepare_notification_route_target_use_case.dart
  |
  +-- imports MediaAttachmentRepository (conversation)
  +-- imports ReactionRepository (conversation)
  +-- imports GroupMessageRepository (groups)
  +-- imports GroupRepository (groups)

resolve_group_notification_route_target_use_case.dart
  +-- imports GroupRepository + PendingGroupInviteRepository (groups)
```

### Connection 10: Feed -> Conversation + Groups

```
load_feed_use_case.dart
  |
  +-- imports MessageRepository (conversation)
  +-- imports MediaAttachmentRepository (conversation)
  +-- imports GroupMessageRepository (groups)
  +-- imports GroupRepository (groups)

load_contact_feed_snapshot_use_case.dart
  +-- imports MessageRepository (conversation) + MediaAttachmentRepository (conversation)
  +-- imports loadConversation use case (conversation application layer — deeper than repo-level coupling)

load_group_feed_snapshot_use_case.dart
  +-- imports MediaAttachmentRepository (conversation) + GroupMessageRepository (groups)
```

### Connection 11: Orbit -> Conversation + Groups (runtime downcast)

```
load_orbit_data_use_case.dart
  |
  +-- downcasts MessageRepository → ConversationThreadSummaryRepository (at runtime)

load_orbit_groups_use_case.dart
  +-- downcasts GroupMessageRepository → GroupThreadSummaryRepository (at runtime)
```

This is an unusual runtime downcast pattern (not constructor injection). The secondary abstract interfaces (`ConversationThreadSummaryRepository`, `GroupThreadSummaryRepository`) are implemented by the primary Impl classes but not exposed in the normal DI graph.

### Connection 12: Settings <-> Introduction + Posts (bidirectional)

```
Settings → Introduction + Posts (settings consuming their repos):
  settings_wired.dart
    +-- imports IntroductionRepository (introduction feature)
    +-- imports PostsPrivacySettingsRepository (posts feature)

Introduction → Settings (introduction consuming settings use cases):
  expire_old_introductions_use_case.dart
    +-- imports download_profile_picture_use_case.dart (settings feature)
  handle_mutual_acceptance_use_case.dart
    +-- imports download_profile_picture_use_case.dart (settings feature)

Posts → Settings (posts consuming settings use cases):
  attach_post_media_use_case.dart
    +-- imports image_quality_preference_use_cases.dart (settings feature)

Groups → Settings (groups consuming settings helpers):
  group_avatar_storage.dart
    +-- imports avatar_normalization_helper.dart (settings feature)
```

### Connection 13: KeyExchangeRetrier (ML-KEM key exchange recovery)

```
KeyExchangeRetrier (lib/features/contact_request/application/key_exchange_retrier.dart)
  |
  +-- direct deps: P2PService (required, subscribes to stateStream for online-transition detection), ContactRepository, IdentityRepository, Bridge
  +-- triggered on P2P reconnect (online transition debounce, same as PendingMessageRetrier)
  +-- also triggered on app resume
```

Retries incomplete ML-KEM key exchanges. Constructed and started in main.dart alongside the other 4 retriers. Lives in the contact_request feature but touches contacts and identity repos.

### Connection 14: Contacts -> Conversation + ContactRequest + Introduction (delete cascade)

```
delete_contact_use_case.dart (lib/features/contacts/application/)
  |
  +-- imports ContactRequestRepository (contact_request feature)
  +-- imports MessageRepository (conversation feature)
  +-- imports MediaAttachmentRepository (conversation feature)
  +-- imports ReactionRepository (conversation feature)
  +-- imports IntroductionRepository (introduction feature)
```

On contact deletion, cascades: deletes reactions, media attachments, messages, introductions linked to the peer, and the contact request record. This is the widest fan-out in a single non-retrier use case — blast radius for any interface change to these 5 repos.

### Connection 15: Posts -> Feed (notification tab switching)

```
post_notification_open_coordinator.dart (lib/features/posts/application/)
  |
  +-- imports AppShellController (feed feature)
  +-- imports AppShellTab (feed feature)
```

When a post notification is opened, this coordinator switches the visible shell tab. Constructed in `_MyAppState.initState()` (Phase 9).

---

## 7. DI Construction Order (main.dart)

The construction sequence matters because of forward references via `late final`.

### Phase 0: Pre-Storage Initialization

1. `ShareIntentService` constructed, `captureInitialIntent()` awaited → determines `isShareLaunch` flag
2. `ensureFirebaseReady()` defined as local closure — called eagerly on normal launch path (NOT deferred to `startLiveServices()` unless `isShareLaunch` is true)
3. `UserAvatar.setDocumentsDir()` — sets documents directory for avatar storage
4. Platform FFI setup for desktop (`sqfliteFfiInit()`, `databaseFactory = databaseFactoryFfi`) — only on desktop platforms

### Phase 1: Storage

1. `FlutterSecureKeyStore` + `PushTokenStoreImpl`
2. Encrypted database opened, migrations run
3. `migrateSecretsToSecureStorage` (one-time)
4. `runSecretNullChecksMigration`

### Phase 2: Repositories

5. `IdentityRepositoryImpl` + `ContactRepositoryImpl` + `ContactRequestRepositoryImpl`
6. `MessageRepositoryImpl` + `InboxStagingRepositoryImpl`
7. `PostRepositoryImpl` + `PostsPrivacySettingsRepositoryImpl` + `ContactPresenceSnapshotRepositoryImpl`
8. `MediaAttachmentRepositoryImpl` + `ReactionRepositoryImpl`
9. `GroupReactionReplayOutboxRepositoryImpl` + `GroupRepositoryImpl` + `PendingGroupInviteRepositoryImpl` + `GroupMessageRepositoryImpl`
10. `IntroductionRepositoryImpl`

### Phase 3: Services

11. `MediaFileManager` + `ImageProcessor` + `RecordAudioRecorderService`
12. `GoBridgeClient` (Bridge)
13. `AUTO_SETUP_USERNAME` block (conditional) — generates identity + QR payload via bridge for auto-setup builds
14. `BonsoirDiscoveryService` + `LocalWsServer` + `LocalP2PService`

### Phase 4: P2P Service (with forward references)

15. `ChatMessageListener` and `IntroductionListener` declared `late final`
16. `P2PServiceImpl` constructed with closure references to the not-yet-initialized listeners
17. `NearbyLocationServiceImpl`
18. `IncomingMessageRouter`
19. `ContactRequestPresentationGate`

### Phase 5: Listeners + Controllers

20. `ContactRequestListener` (references `introductionListener` via closure)
21. `FlutterNotificationService` + `PushRegistrationCoordinator`
22. `ActiveConversationTracker` (x2: one for conversations, one for groups) + `AppShellController` + `PendingPostTargetStore`
23. `ChatMessageListener` (assigned to `late final`)
24. Post listeners: `PostListener`, `PostCommentListener`, `PostReactionListener`, `PostPresenceListener`, `PostPassListener`, `PostPinListener`
25. `ReactionListener` + `MessageDeletionListener` + `ProfileUpdateListener`
26. `GroupMessageListener` + bridge callback StreamControllers (`groupMessageStreamController`, `groupReactionStreamController` + `bridge.onGroupMessageReceived` / `bridge.onGroupReactionReceived` assignments)
27. `GroupInviteListener` + `GroupKeyUpdateListener`
28. `IntroductionListener` (assigned to `late final`)

### Phase 6: Retriers

29. `PendingMessageRetrier`
30. `PendingPostMediaUploadRetrier`
31. `PendingPostDeliveryRetrier` — constructed with `beforeRetry: pendingPostMediaUploadRetrier.retryNow` (flushes pending media uploads before each delivery retry cycle)
32. `PendingPostFollowOnRetrier`
33. `KeyExchangeRetrier`

### Phase 7: Start

`startLiveServices()`:
1. `ensureFirebaseReady()` — Firebase SDK lazy-init barrier (async, gates everything below). On normal launch, Firebase was already initialized eagerly in Phase 0, so this is a no-op guard. On share launch, this is the first Firebase init.
2. `bridge.initialize()`
3. `notificationService.initialize()`
4. `messageRouter.start()`
5. All listeners `.start()` in sequence:
   `contactRequestListener` → `chatMessageListener` → `postListener` → `postCommentListener` → `postReactionListener` → `postPresenceListener` → `postPassListener` → `postPinListener` → `reactionListener` → `messageDeletionListener` → `profileUpdateListener` → `groupMessageListener` (receives stream args) → `groupInviteListener` → `groupKeyUpdateListener` → `introductionListener`
6. Retriers started
7. Cross-listener subscriptions wired:
   - `profileUpdateListener.contactUpdatedStream` -> `chatMessageListener.emitContactUpdate`
   - `contactRequestListener.contactKeyUpdatedStream` -> `chatMessageListener.emitContactUpdate`

**Conditional execution**: If `isShareLaunch` is true, `startLiveServices()` is NOT called eagerly — instead it is passed as `deferredRuntimeStartup` to `MyApp` and called lazily when the app transitions from share flow to normal mode.

### Phase 8: Widget Tree

`MyApp` receives all dependencies as named constructor params and passes them down through `StartupRouter` -> feature Wired widgets. Notable params beyond the primary services and listeners include: `contactRequestPresentationGate`, `groupConversationTracker` (second `ActiveConversationTracker`), `shareIntentService`, `pushRegistrationCoordinator?`, `deferredRuntimeStartup?`, `isDesktop`, `groupReactionReplayOutboxRepository`, `messageRouter`, and all 3 post retriers.

### Phase 9: Post-runApp() Initialization

These run after `runApp()` returns:

1. `sweepExpiredPosts()` — called unawaited, sweeps expired posts at startup
2. `startIntroE2EPoller()` — starts a debug/test poller for intro E2E config files

Additionally, inside `_MyAppState.initState()`:
3. `PostNotificationOpenCoordinator` constructed
4. `ContactRequestNotificationMaterializer` constructed

### Phase 10: App Lifecycle Handlers

Two core lifecycle coordinators sit in `lib/core/lifecycle/` and are called from `_MyAppState.didChangeAppLifecycleState`:

**`handleAppResumed`** (`lib/core/lifecycle/handle_app_resumed.dart`) — 8-step recovery sequence on every app resume:
1. Bridge health check (reinitialize if dead)
2. `p2pService.performImmediateHealthCheck()`
3. `p2pService.drainOfflineInbox()`
4. `rejoinGroupTopics` + `drainGroupOfflineInbox` (passes `GroupMessageListener` directly - one of the direct calling sites outside `PendingMessageRetrier`; also used from `StartupRouter`)
5. `retryIncompleteKeyExchanges`
6. `nearbyLocationService.refreshSilentlyOnResume()`
7. Post media/delivery retries
8. Message recovery sweep: recoverStuckSendingMessages, retryIncompleteUploads, retryFailedMessages, retryUnackedMessages, retryPendingIntroductionDeliveries, retryFailedGroupInboxStores

Cross-feature imports: `ContactRepository`, `IdentityRepository`, `GroupRepository`, `GroupMessageRepository`, `GroupMessageListener`, `MediaAttachmentRepository`, `ReactionRepository`, `NearbyLocationService`, `retryIncompleteKeyExchanges` (contact_request), `drainGroupOfflineInbox` / `rejoinGroupTopics` (groups).

**`handleAppPaused`** (`lib/core/lifecycle/handle_app_paused.dart`) — transitions all in-flight `sending` messages and group messages to `failed` status at background time, so they are eligible for retry on resume. Imports `MessageRepository` (conversation) and `GroupMessageRepository` (groups).

### Phase 11: Disposal Order

`_MyAppState.dispose()` tears down in reverse construction order:

1. Retriers: `keyExchangeRetrier` → `pendingPostFollowOnRetrier` → `pendingPostDeliveryRetrier` → `pendingPostMediaUploadRetrier` → `pendingMessageRetrier`
2. Listeners: `introductionListener` → `groupKeyUpdateListener` → `groupInviteListener` → `groupMessageListener` → `profileUpdateListener` → `reactionListener` → `messageDeletionListener` → post listeners → `chatMessageListener` → `contactRequestListener`
3. Coordinators: `postNotificationOpenCoordinator` → `pushRegistrationCoordinator`
4. Repos: `contactPresenceSnapshotRepository` → `postRepository`
5. Core: `messageRouter` → `p2pService` → `bridge` → `audioRecorderService` → `notificationService`
