# C4 Model: Receive Message in Discussion

> Standalone C4 architecture document for the **Receive Message** action in the Group Messaging feature.
>
> In code, the product-facing "Discussion" variant maps to the group `chat` type. This document therefore follows the `GroupType.chat` receive path, while calling out shared group infrastructure where it materially affects the flow.
> It covers both plain-text group messages and attachment-backed messages, including photos, videos, GIFs, files, and recorded voice messages. On the receive side, voice is not a special transport type; it arrives as an audio attachment in the same `media` payload branch.

---

## Level 1: System Context

```
+------------------+          +---------------------------+
| Other Group      |          |   libp2p GossipSub        |
| Members          |--------->|   Network                 |
| (Persons)        | publish  |   (External System)       |
+------------------+          +---------------------------+
                                        |
                                        | v3 group envelope on
                                        | /mknoon/group/{groupId}
                                        v
                              +---------------------------+
                              |   mknoon Mobile App       |
                              |   (Go node + Flutter)     |
                              +---------------------------+
                                        |
                                        | UI update and/or
                                        | local notification
                                        v
                              +---------------------------+
                              |   Receiving Member        |
                              |   (Person)                |
                              +---------------------------+
```

### Actors & Systems

| Element | Type | Description |
|---------|------|-------------|
| Other Group Members | Person | Remote senders publishing encrypted group envelopes to the shared discussion topic; the inner payload may carry plain text, quoted metadata, and/or media attachment metadata such as image, video, or audio |
| libp2p GossipSub | External System | Topic-based pubsub transport used by the Go node for `/mknoon/group/{groupId}` |
| mknoon Mobile App | Software System | Validates, decrypts, routes, persists, and renders incoming discussion messages |
| Receiving Member | Person | The local user who sees the new message in the app UI or notification tray |

### Interactions

1. **Sender -> GossipSub**: Publishes a v3 `group_message` envelope to `/mknoon/group/{groupId}`. For Discussion (`chat`) groups, any member may publish; the stricter announcement-group write rule exists in shared validator code but is not the active path here. The decrypted inner payload can include a `media` array for image/video/file/audio attachments, including recorded voice messages.
2. **GossipSub -> App (Go)**: The Go node's registered `groupTopicValidator()` accepts or rejects the envelope. Accepted messages are read by `handleGroupSubscription()`, which parses the envelope, skips self-delivery, decrypts with the current key or previous key during grace, and builds the message event payload.
3. **Go -> App (Dart)**: `Node.emitEvent()` normally pushes JSON through `EventDispatcher` and the gomobile `EventCallback.OnEvent` bridge; if no dispatcher is present it falls back to synchronous JSON callback delivery. Flutter receives that payload on the `EventChannel`, `GoBridgeClient._handleEvent()` routes `group_message:received`, and `main.dart` forwards the payload into `groupMessageStreamController`.
4. **App -> User**: `GroupMessageListener` persists the message, emits it on `groupMessageStream`, and user-facing surfaces update (`GroupConversationWired`, `GroupListWired`, `FeedWired`, `OrbitWired`). A local notification is considered only when the group is not muted and notification suppression rules do not apply.

---

## Level 2: Container

```
+--------------------------------------------------------------------------------+
|                                mknoon Mobile App                               |
|                                                                                |
|  +------------------+   +--------------------+   +--------------------------+  |
|  | Go libp2p        |-->| Go handleGroup     |-->| Go EventDispatcher       |  |
|  | TopicValidator   |   | Subscription       |   | + EventCallback.OnEvent  |  |
|  |                  |   | (decrypt + emit)   |   +--------------------------+  |
|  +------------------+   +--------------------+                |                |
|                                                               v                |
|                                                  +--------------------------+  |
|                                                  | Dart Bridge              |  |
|                                                  | GoBridgeClient           |  |
|                                                  | _handleEvent()           |  |
|                                                  +--------------------------+  |
|                                                               |                |
|                                                               v                |
|                                                  +--------------------------+  |
|                                                  | main.dart wiring         |  |
|                                                  | groupMessage/Reaction    |  |
|                                                  | StreamControllers        |  |
|                                                  +--------------------------+  |
|                                                               |                |
|                                                               v                |
|                                                  +--------------------------+  |
|                                                  | GroupMessageListener     |  |
|                                                  | message / reaction /     |  |
|                                                  | system-message handling  |  |
|                                                  +--------------------------+  |
|                                                     |            |             |
|                                  +------------------+            +---------+   |
|                                  |                                       |   |
|                                  v                                       v   |
|                           +---------------+                   +----------------+|
|                           | SQLCipher DB  |                   | Flutter UI +   ||
|                           | group_messages|                   | notifications  ||
|                           +---------------+                   +----------------+|
+--------------------------------------------------------------------------------+
```

### Containers

| Container | Technology | Responsibility |
|-----------|------------|----------------|
| Go libp2p TopicValidator | Go / libp2p | `groupTopicValidator()` validates that the payload is a v3 group envelope, the `groupId` matches, the sender is a configured member, the sender is allowed to write for the current group type, and the envelope signature is valid for the current or grace-period previous key epoch |
| Go handleGroupSubscription | Go / libp2p | Reads accepted subscription messages, parses the envelope, skips self-sent traffic, decrypts with the current key or previous key during rotation grace, routes reactions separately, parses group-message payloads, and emits receive events |
| EventDispatcher | Go | Asynchronous bounded dispatcher. Non-coalesced events such as `group_message:received`, `group_reaction:received`, and group diagnostics share a FIFO queue capped at 1024 items; events are dropped on overflow. `addresses:updated`, `relay:state`, and `media:upload_progress` are coalesced by type. Message-queue items are dequeued before coalesced status events. If the dispatcher is unavailable, `Node.emitEvent()` falls back to synchronous JSON delivery. |
| Dart Bridge | Dart / MethodChannel + EventChannel | `GoBridgeClient._handleEvent()` decodes JSON from the native bridge and routes `group_message:received` and `group_reaction:received` to callback hooks. This receive path does **not** go through `IncomingMessageRouter` or `ChatMessageListener`. |
| `main.dart` wiring | Dart | Owns `groupMessageStreamController` and `groupReactionStreamController`, connects bridge callbacks to those broadcast streams, and starts `GroupMessageListener` with them |
| GroupMessageListener | Dart | Subscribes to the raw group message/reaction streams, routes system messages, calls `handleIncomingGroupMessage()`, emits `groupMessageStream`, emits removal and reaction side streams, triggers notifications, and optionally auto-downloads incoming media including recorded voice attachments |
| SQLCipher DB | SQLite + SQLCipher | Persists incoming messages in `group_messages`; inserts use `ConflictAlgorithm.replace`, which is relevant for duplicate enrichment and synthetic timeline updates |
| Flutter UI + notifications | Dart / Flutter | `GroupConversationWired`, `GroupListWired`, `FeedWired`, and `OrbitWired` consume `groupMessageStream`. The conversation UI renders image/video attachments through `MediaGrid` and audio attachments through `AudioPlayerWidget` inside `LetterCard`. `NotificationService` is invoked by the listener when mute and suppression checks allow a local notification. |

### Event Flow

```
Go: groupTopicValidator accepts/rejects
  --> Go: handleGroupSubscription reads from subscription
  --> Fetch selfPeerId + keyInfo under read lock
  --> Parse envelope: internal.ParseGroupEnvelope(data)
  --> Skip self-sent messages (env.SenderId == selfPeerId)
  --> Guard: skip if no key info for group
  --> Decrypt: decryptGroupEnvelopePayload(env, keyInfo, time.Now())
        (current epoch or previous epoch during grace)
        (on error -> emitEvent('group:decryption_failed'), continue)
  --> Route by type: group_reaction -> emitEvent('group_reaction:received'), continue
  --> Parse inner payload: internal.ParseGroupPayload(plaintext)
        (on error -> emitEvent('group:payload_parse_failed'), continue)
        (payload may include optional media[] metadata for photo/video/file/audio)
  --> emitEvent('group_message:received', buildGroupMessageReceivedEvent(...))
  --> Node.emitEvent() -> EventDispatcher FIFO queue
      (or synchronous JSON callback delivery if no dispatcher is present)
  --> EventCallback.OnEvent(JSON) -> Flutter EventChannel
  --> Dart: GoBridgeClient._handleEvent()
  --> bridge.onGroupMessageReceived(data)
  --> main.dart: groupMessageStreamController.add(data)
  --> GroupMessageListener._handleMessage(data)
  --> System-message short-circuit if text starts with '{"__sys":' and _bridge != null
      OR normal path into handleIncomingGroupMessage()
  --> GroupMessageRepository.saveMessage() -> dbInsertGroupMessage(... replace)
  --> MediaAttachmentRepository.saveAttachment(...) for each attachment row
  --> _messageController.add(result)
  --> GroupConversationWired / GroupListWired / FeedWired / OrbitWired react to groupMessageStream
  --> maybeShowNotification() if group not muted and suppression rules allow
  --> optional _autoDownloadMedia(result) -> re-emit message after downloads complete
  --> GroupConversationScreen/LetterCard renders image+video attachments in MediaGrid
      and audio attachments in AudioPlayerWidget
```

`group:decryption_failed` and `group:payload_parse_failed` are emitted by Go, but `GoBridgeClient` has no explicit Dart receive-case for them, so they do not feed the normal message listener path.

---

## Level 3: Component

```
+--------------------------------------------------------------------------------+
|                            Dart Application Layer                              |
|                                                                                |
|  +---------------------------+    +--------------------------+                 |
|  | GoBridgeClient            |--->| main.dart raw group      |                 |
|  | _handleEvent()            |    | StreamControllers        |                 |
|  +---------------------------+    +--------------------------+                 |
|                                              |                                 |
|                                              v                                 |
|  +---------------------------+   +----------------------------+                |
|  | GroupMessageListener      |-->| handleIncomingGroupMessage |                |
|  | _handleMessage()          |   | use case                   |                |
|  | _handleSystemMessage()    |   +----------------------------+                |
|  | _handleReaction()         |              |                                  |
|  | _autoDownloadMedia()      |              v                                  |
|  +---------------------------+   +----------------------------+                |
|          |         |             | GroupMessageRepositoryImpl |                |
|          |         |             +----------------------------+                |
|          |         |                           |                               |
|          |         +------> maybeShowNotification()                            |
|          |                                     |                               |
|          v                                     v                               |
|  +---------------------------+     +---------------------------+               |
|  | groupMessageStream        |---->| UI subscribers            |               |
|  | removed/reaction streams  |     | conversation/list/feed    |               |
|  +---------------------------+     +---------------------------+               |
+--------------------------------------------------------------------------------+
```

### Components

| Component | File | Responsibility |
|-----------|------|----------------|
| `GoBridgeClient._handleEvent()` | `lib/core/bridge/go_bridge_client.dart` | Decodes EventChannel JSON and invokes `onGroupMessageReceived` / `onGroupReactionReceived` for the group receive path |
| `groupMessageStreamController` / `groupReactionStreamController` | `lib/main.dart` | Bridge-to-listener wiring owned by the app composition root; this is the raw stream source consumed by `GroupMessageListener` |
| `GroupMessageListener` | `lib/features/groups/application/group_message_listener.dart` | Subscribes to raw Go events, routes system messages and reactions, dispatches chat messages to `handleIncomingGroupMessage()`, emits `groupMessageStream`, emits `groupRemovedStream` / `groupReactionChangeStream`, triggers notifications, and optionally auto-downloads media |
| `handleIncomingGroupMessage()` | `lib/features/groups/application/handle_incoming_group_message_use_case.dart` | Sanitizes text, deduplicates, validates group state and sender/removal boundaries, persists the message, and stores attachment metadata for image/video/file/audio payloads |
| `GroupMessageRepositoryImpl` | `lib/features/groups/domain/repositories/group_message_repository_impl.dart` | Persists and loads group messages; primary ID dedupe uses `dbLoadGroupMessage`, content dedupe uses `dbExistsGroupMessageByContent`, and removal cutoffs come from `dbLoadLatestGroupRemovalTimestampForSender` when available |
| `maybeShowNotification()` | `lib/features/push/application/show_notification_use_case.dart` | Suppresses notifications when the user is already viewing the group in the foreground or when a recent remote push already announced the same background message; otherwise delegates to `NotificationService.showMessageNotification()` |
| `groupMessageStream` / `groupRemovedStream` / `groupReactionChangeStream` | `lib/features/groups/application/group_message_listener.dart` | Broadcasts validated incoming messages, self-removal events, and reaction updates to UI consumers |
| `LetterCard` | `lib/features/conversation/presentation/widgets/letter_card.dart` | Shared group/1:1 message card UI that renders text, image/video grids, and audio attachments via `AudioPlayerWidget` |

### Validation Pipeline

```
0. BRIDGE ROUTING
   - Go emits `group_message:received`
   - `GoBridgeClient._handleEvent()` forwards that event to `bridge.onGroupMessageReceived`
   - `main.dart` pushes it into `groupMessageStreamController`
   - This path bypasses `IncomingMessageRouter` and `ChatMessageListener`

1. SYSTEM MESSAGE SHORT-CIRCUIT
   - If text starts with '{"__sys":' AND `_bridge != null`
     -> route to `_handleSystemMessage()`, return
   - This branch does not call `handleIncomingGroupMessage()`
   - It may update local group/member state, sync Go config, and emit synthetic
     timeline `GroupMessage`s for some system event types

2. DEDUPLICATION — primary (ID)
   - If `messageId` is present:
     `msgRepo.existsByMessageId(messageId)`
   - If true:
     `_enrichExistingDuplicateMessage()` may backfill `quotedMessageId` and
     media attachment metadata, then return `null`

3. GROUP EXISTS
   - `groupRepo.getGroup(groupId)`
   - If null -> ignore as unknown/stale local group

4. TIMESTAMP PARSING
   - `DateTime.parse(timestamp)` with fallback to `DateTime.now().toUtc()`
   - `normalizedTimestamp = parsedTimestamp.toUtc()` is used for boundary checks

5. DISSOLUTION BOUNDARY
   - If `group.isDissolved` and the incoming timestamp is at or after
     `dissolvedAt` (or `dissolvedAt` is unexpectedly null) -> reject

6. SENDER MEMBERSHIP / REMOVAL BOUNDARY
   - `groupRepo.getMember(groupId, senderId)`
   - Known sender -> continue
   - Unknown sender -> log flow event and consult
     `msgRepo.getLatestRemovalTimestampForSender(groupId, senderId)`
   - If removal cutoff exists and message timestamp is at/after that cutoff
     -> reject
   - Otherwise continue because local membership can be stale

7. DEDUPLICATION — fallback (content)
   - `msgRepo.existsByContent(groupId, senderId, sanitizedText, parsedTimestamp)`
   - Repository converts the timestamp to UTC ISO text before the DB lookup

8. PERSIST
   - `messageId`: wire ID when present, otherwise UUID v4
   - `status`: `sent` only for self-delivery; otherwise `delivered`
   - `isIncoming`: `false` only for self-delivery; otherwise `true`
   - `msgRepo.saveMessage(GroupMessage(...))`
   - `_saveIncomingMediaAttachments()` stores attachment rows for later download
   - Voice messages are stored here as ordinary audio attachments (`mediaType='audio'`)
     with duration/waveform metadata when present; they do not have a separate
     receive-only message type

9. POST-PERSIST FAN-OUT
   - `_messageController.add(result)`
   - Notification branch runs only when:
     `senderId != selfPeerId`,
     `_notificationService != null`,
     `_groupConversationTracker != null`,
     `_getAppLifecycleState != null`,
     and `group.isMuted == false`
   - `_autoDownloadMedia()` runs fire-and-forget only when bridge/media deps
     exist and the message has attachments; it re-emits the message after download

10. UI RENDER
   - `GroupConversationWired` reloads the persisted row plus resolved attachment state
   - `GroupConversationScreen` passes the message into `LetterCard`
   - `LetterCard` routes image/video attachments to `MediaGrid`
   - `LetterCard` routes audio attachments, including recorded voice messages,
     to `AudioPlayerWidget`
```

---

## Level 4: Code

### GroupMessageListener

```dart
// lib/features/groups/application/group_message_listener.dart

class GroupMessageListener {
  final GroupRepository _groupRepo;
  final GroupMessageRepository _msgRepo;
  final Bridge? _bridge;
  final Future<String?> Function()? _getSelfPeerId;
  final MediaAttachmentRepository? _mediaAttachmentRepo;
  final MediaFileManager? _mediaFileManager;
  final NotificationService? _notificationService;
  final ActiveConversationTracker? _groupConversationTracker;
  final AppLifecycleState Function()? _getAppLifecycleState;
  final RecentRemoteNotificationGate _remoteNotificationGate;
  final ReactionRepository? _reactionRepo;

  StreamSubscription<Map<String, dynamic>>? _subscription;
  StreamSubscription<Map<String, dynamic>>? _reactionSubscription;

  final _messageController = StreamController<GroupMessage>.broadcast();
  final _removedController = StreamController<String>.broadcast();
  final _reactionChangeController = StreamController<ReactionChange>.broadcast();

  Stream<GroupMessage> get groupMessageStream => _messageController.stream;
  Stream<String> get groupRemovedStream => _removedController.stream;
  Stream<ReactionChange> get groupReactionChangeStream =>
      _reactionChangeController.stream;

  void start(
    Stream<Map<String, dynamic>> incomingGroupMessages, {
    Stream<Map<String, dynamic>>? incomingGroupReactions,
  }) {
    if (_subscription != null) return;

    _subscription = incomingGroupMessages.listen(_handleMessage);
    if (incomingGroupReactions != null) {
      _reactionSubscription = incomingGroupReactions.listen(_handleReaction);
    }
  }

  Future<void> handleReplayEnvelope(Map<String, dynamic> data) {
    return _handleMessage(data);
  }

  Future<void> _handleMessage(Map<String, dynamic> data) async {
    final groupId = data['groupId'] as String? ?? '';
    final senderId = data['senderId'] as String? ?? '';
    final senderUsername = data['senderUsername'] as String? ?? '';
    final keyEpoch = data['keyEpoch'] as int? ?? 0;
    final text = data['text'] as String? ?? '';
    final timestamp = data['timestamp'] as String? ??
        DateTime.now().toUtc().toIso8601String();

    if (groupId.isEmpty || senderId.isEmpty) return;

    // System messages short-circuit normal persistence only when the bridge is available.
    if (text.startsWith('{"__sys":') && _bridge != null) {
      await _handleSystemMessage(
        groupId,
        text,
        timestamp,
        senderId: senderId,
        senderUsername: senderUsername,
      );
      return;
    }

    final media = (data['media'] as List<dynamic>?)?.cast<Map<String, dynamic>>();
    final wireMessageId = data['messageId'] as String?;
    final wireQuotedMessageId = data['quotedMessageId'] as String?;
    final selfPeerId = await _resolveSelfPeerId();

    final result = await handleIncomingGroupMessage(
      groupRepo: _groupRepo,
      msgRepo: _msgRepo,
      groupId: groupId,
      senderId: senderId,
      senderUsername: senderUsername,
      keyEpoch: keyEpoch,
      text: text,
      timestamp: timestamp,
      selfPeerId: selfPeerId,
      messageId: wireMessageId,
      quotedMessageId: wireQuotedMessageId,
      media: media,
      mediaAttachmentRepo: _mediaAttachmentRepo,
    );

    if (result == null) return;

    _messageController.add(result);

    if (senderId != selfPeerId &&
        _notificationService != null &&
        _groupConversationTracker != null &&
        _getAppLifecycleState != null) {
      final group = await _groupRepo.getGroup(groupId);
      if (!(group?.isMuted ?? false)) {
        final notifAttachments =
            media?.map((m) => MediaAttachment.fromJson(m)).toList() ??
            <MediaAttachment>[];

        maybeShowNotification(
          notificationService: _notificationService!,
          conversationTracker: _groupConversationTracker!,
          getAppLifecycleState: _getAppLifecycleState!,
          contactPeerId: 'group:$groupId',
          routePayload: NotificationRouteTarget.group(
            groupId,
            messageId: result.id,
          ).toPayload(),
          senderUsername: group?.name ?? 'Group',
          messageText:
              '$senderUsername: ${notificationBodyForMessage(text, notifAttachments)}',
          messageId: result.id,
          consumeRecentRemoteNotificationAnnouncement:
              ({required payload, String? messageId}) =>
                  _remoteNotificationGate.consumeIfRecentAnnouncement(
                    payload: payload,
                    messageId: messageId,
                  ),
          backgroundDuplicateGuardDelay: Duration.zero,
        );
      }
    }

    if (_bridge != null &&
        _mediaAttachmentRepo != null &&
        _mediaFileManager != null &&
        media != null &&
        media.isNotEmpty) {
      _autoDownloadMedia(result);
    }
  }
}
```

### handleIncomingGroupMessage() Use Case

```dart
// lib/features/groups/application/handle_incoming_group_message_use_case.dart

Future<GroupMessage?> handleIncomingGroupMessage({
  required GroupRepository groupRepo,
  required GroupMessageRepository msgRepo,
  required String groupId,
  required String senderId,
  required String senderUsername,
  required int keyEpoch,
  required String text,
  required String timestamp,
  String? selfPeerId,
  String? messageId,
  String? quotedMessageId,
  List<Map<String, dynamic>>? media,
  MediaAttachmentRepository? mediaAttachmentRepo,
}) async {
  final sanitizedText = sanitizeMessageText(text);

  if (messageId != null && messageId.isNotEmpty) {
    final existsById = await msgRepo.existsByMessageId(messageId);
    if (existsById) {
      await _enrichExistingDuplicateMessage(
        msgRepo: msgRepo,
        messageId: messageId,
        quotedMessageId: quotedMessageId,
        media: media,
        mediaAttachmentRepo: mediaAttachmentRepo,
      );
      return null;
    }
  }

  final group = await groupRepo.getGroup(groupId);
  if (group == null) return null;

  final now = DateTime.now().toUtc();
  DateTime parsedTimestamp;
  try {
    parsedTimestamp = DateTime.parse(timestamp);
  } catch (_) {
    parsedTimestamp = now;
  }
  final normalizedTimestamp = parsedTimestamp.toUtc();

  final dissolvedAt = group.dissolvedAt?.toUtc();
  if (group.isDissolved &&
      (dissolvedAt == null || !normalizedTimestamp.isBefore(dissolvedAt))) {
    return null;
  }

  final member = await groupRepo.getMember(groupId, senderId);
  if (member == null) {
    final removalCutoff = await msgRepo.getLatestRemovalTimestampForSender(
      groupId,
      senderId,
    );
    if (removalCutoff != null && !normalizedTimestamp.isBefore(removalCutoff)) {
      return null;
    }
  }

  final isDuplicate = await msgRepo.existsByContent(
    groupId,
    senderId,
    sanitizedText,
    parsedTimestamp,
  );
  if (isDuplicate) return null;

  final resolvedMessageId = (messageId != null && messageId.isNotEmpty)
      ? messageId
      : const Uuid().v4();
  final isSelfDelivery = selfPeerId != null && senderId == selfPeerId;

  final message = GroupMessage(
    id: resolvedMessageId,
    groupId: groupId,
    senderPeerId: senderId,
    senderUsername: senderUsername,
    text: sanitizedText,
    timestamp: parsedTimestamp,
    quotedMessageId: quotedMessageId,
    keyGeneration: keyEpoch,
    status: isSelfDelivery ? 'sent' : 'delivered',
    isIncoming: !isSelfDelivery,
    createdAt: now,
  );

  await msgRepo.saveMessage(message);

  await _saveIncomingMediaAttachments(
    messageId: resolvedMessageId,
    media: media,
    mediaAttachmentRepo: mediaAttachmentRepo,
  );

  return message;
}
```

### Go TopicValidator (Validation Only)

```go
// go-mknoon/node/pubsub.go

// groupTopicValidator validates a v3 group envelope before it reaches the
// subscription reader. For Discussion/chat groups, any member can write.
// Announcement-specific write restrictions remain in the shared validator but
// are not the active behavior for this document's path.
func (n *Node) groupTopicValidator(groupId string) func(context.Context, peer.ID, *pubsub.Message) pubsub.ValidationResult {
    return func(ctx context.Context, pid peer.ID, msg *pubsub.Message) pubsub.ValidationResult {
        data := string(msg.Data)

        if !internal.IsGroupEnvelope(data) {
            return pubsub.ValidationReject
        }

        env, err := internal.ParseGroupEnvelope(data)
        if err != nil {
            return pubsub.ValidationReject
        }

        if env.GroupId != groupId {
            return pubsub.ValidationReject
        }

        n.mu.RLock()
        config, ok := n.groupConfigs[groupId]
        n.mu.RUnlock()
        if !ok {
            return pubsub.ValidationReject
        }

        member := findMember(config, env.SenderId)
        if member == nil {
            return pubsub.ValidationReject
        }

        if env.Type == "group_message" && !isAllowedWriter(config, env.SenderId) {
            return pubsub.ValidationReject
        }

        n.mu.RLock()
        keyInfo, keyOk := n.groupKeys[groupId]
        n.mu.RUnlock()
        if !keyOk {
            return pubsub.ValidationReject
        }

        if !verifyGroupEnvelopeSignature(groupId, member.PublicKey, env, keyInfo, time.Now()) {
            return pubsub.ValidationReject
        }

        return pubsub.ValidationAccept
    }
}
```

### Go handleGroupSubscription (Decrypt + Emit)

```go
// go-mknoon/node/pubsub.go

func (n *Node) handleGroupSubscription(ctx context.Context, groupId string, sub *pubsub.Subscription) {
    for {
        msg, err := sub.Next(ctx)
        if err != nil {
            return
        }

        n.mu.RLock()
        selfPeerId := n.peerId
        keyInfo, keyOk := n.groupKeys[groupId]
        n.mu.RUnlock()

        env, err := internal.ParseGroupEnvelope(string(msg.Data))
        if err != nil {
            continue
        }
        if env.SenderId == selfPeerId {
            continue
        }
        if !keyOk {
            continue
        }

        // Decrypts with current key or previous key during rotation grace.
        plaintext, err := decryptGroupEnvelopePayload(env, keyInfo, time.Now())
        if err != nil {
            n.emitEvent("group:decryption_failed", map[string]interface{}{
                "groupId":       groupId,
                "senderId":      env.SenderId,
                "keyEpoch":      env.KeyEpoch,
                "localKeyEpoch": keyInfo.KeyEpoch,
                "error":         err.Error(),
            })
            continue
        }

        if env.Type == "group_reaction" {
            n.emitEvent("group_reaction:received", map[string]interface{}{
                "groupId":  groupId,
                "senderId": env.SenderId,
                "reaction": plaintext,
            })
            continue
        }

        payload, err := internal.ParseGroupPayload(plaintext)
        if err != nil {
            n.emitEvent("group:payload_parse_failed", map[string]interface{}{
                "groupId":      groupId,
                "senderId":     env.SenderId,
                "envelopeType": env.Type,
            })
            continue
        }

        n.emitEvent(
            "group_message:received",
            buildGroupMessageReceivedEvent(groupId, env, payload),
        )
    }
}

func buildGroupMessageReceivedEvent(groupId string, env *internal.GroupEnvelope, payload *internal.GroupMessagePayload) map[string]interface{} {
    event := map[string]interface{}{
        "groupId":        groupId,
        "senderId":       env.SenderId,
        "senderUsername": payload.Username,
        "keyEpoch":       env.KeyEpoch,
        "text":           payload.Text,
        "timestamp":      payload.Timestamp,
    }
    if payload.Extra != nil {
        if media, ok := payload.Extra["media"]; ok {
            event["media"] = media
        }
        if msgId, ok := payload.Extra["messageId"]; ok {
            event["messageId"] = msgId
        }
        if quotedMessageId, ok := payload.Extra["quotedMessageId"]; ok {
            event["quotedMessageId"] = quotedMessageId
        }
    }
    return event
}
```

### Bridge Event Wiring (main.dart)

```dart
// lib/main.dart (wiring excerpt)

final groupMessageListener = GroupMessageListener(
  groupRepo: groupRepository,
  msgRepo: groupMessageRepository,
  bridge: bridge,
  getSelfPeerId: () async {
    final identity = await repository.loadIdentity();
    return identity?.peerId;
  },
  mediaAttachmentRepo: mediaAttachmentRepository,
  mediaFileManager: mediaFileManager,
  notificationService: notificationService,
  groupConversationTracker: groupConversationTracker,
  getAppLifecycleState: () =>
      WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed,
  reactionRepo: reactionRepository,
);

final groupMessageStreamController =
    StreamController<Map<String, dynamic>>.broadcast();
bridge.onGroupMessageReceived = (data) {
  groupMessageStreamController.add(data);
};

final groupReactionStreamController =
    StreamController<Map<String, dynamic>>.broadcast();
bridge.onGroupReactionReceived = (data) {
  groupReactionStreamController.add(data);
};

groupMessageListener.start(
  groupMessageStreamController.stream,
  incomingGroupReactions: groupReactionStreamController.stream,
);
```

`IncomingMessageRouter` and `ChatMessageListener` are part of the direct 1:1 message stack, not the group receive path above.

UI consumers of `groupMessageListener.groupMessageStream` in this codebase:

- `GroupConversationWired`: re-fetches the persisted message by ID, loads resolved attachments, upserts it into the visible thread, restores scroll position, and marks the group as read
- `GroupListWired`: reloads the group list so thread previews and unread counts stay current
- `FeedWired`: incrementally refreshes the group thread snapshot used on the feed surface
- `OrbitWired`: marks the group as changed and refreshes the corresponding orbit group card

### Notification Handling

```dart
// Notification logic runs in GroupMessageListener._handleMessage()
// after a normal chat message has been persisted and emitted.

// Preconditions before maybeShowNotification():
// 1. senderId != selfPeerId
// 2. _notificationService != null
// 3. _groupConversationTracker != null
// 4. _getAppLifecycleState != null
// 5. group.isMuted == false

maybeShowNotification(
  notificationService: _notificationService!,
  conversationTracker: _groupConversationTracker!,
  getAppLifecycleState: _getAppLifecycleState!,
  contactPeerId: 'group:$groupId',
  routePayload: NotificationRouteTarget.group(
    groupId,
    messageId: result.id,
  ).toPayload(),
  senderUsername: groupName,
  messageText:
      '$senderUsername: ${notificationBodyForMessage(text, notifAttachments)}',
  messageId: result.id,
  consumeRecentRemoteNotificationAnnouncement:
      ({required payload, String? messageId}) =>
          _remoteNotificationGate.consumeIfRecentAnnouncement(
            payload: payload,
            messageId: messageId,
          ),
  backgroundDuplicateGuardDelay: Duration.zero,
);
```

`maybeShowNotification()` suppresses the local notification when:

- The app is in `AppLifecycleState.resumed` and `ActiveConversationTracker` says the user is already viewing `group:$groupId`
- The app is not resumed and a recent remote push already announced the same route payload / message ID

`notificationBodyForMessage()` returns:

- The trimmed text when message text is present
- Otherwise `GIF`, `Photo`, `Video`, `Voice message`, `File`, or `Media` based on attachments
- Otherwise `Message` when both text and attachments are empty
