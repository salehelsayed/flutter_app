# C4 Model: Send Message in Discussion

> Standalone C4 architecture document for the **Send Message** action in the Group Messaging feature.
> Focus: discussion (`chat` / `qa`) sends, while still calling out shared send-use-case branches that also affect announcement groups.
> This document covers both the ordinary `_onSend()` path for text / image / video / generic attachment sends and the group-specific `_onRecordStop()` path for recorded voice messages, because both ultimately converge on the same `sendGroupMessage()` publish + relay-inbox + persistence boundary.

---

## Level 1: System Context

```
+----------------------+          +---------------------------+
| Discussion Member    |          | mknoon Mobile App         |
| (Person)             |--------->| (Software System)         |
|                      |  sends   |                           |
+----------------------+  message +---------------------------+
                                       | publish | store | upload*
                                       v         v       v
                              +-----------+ +-----------+ +-------------+
                              | libp2p    | | Relay     | | Relay Media |
                              | GossipSub | | Inbox     | | Store       |
                              | (Ext Sys) | | (Ext Sys) | | (Ext Sys)   |
                              +-----------+ +-----------+ +-------------+
                                     |
                                     v
                              +------------------+
                              | Other Group      |
                              | Members          |
                              +------------------+
```

`*` Optional only when attachments are present.

### Actors & Systems

| Element | Type | Description |
|---------|------|-------------|
| Group Member | Person | A member sending in a discussion (`chat` / `qa`) group. In the shared send use case, announcement groups remain admin-only |
| mknoon Mobile App | Software System | Flutter UI orchestrates both the `_onSend()` discussion send flow and the `_onRecordStop()` recorded-voice flow, including UI-owned composer state, optimistic/update prep, durable media staging, and network send; the embedded Go runtime performs publish, inbox-store, and optional media-upload commands |
| libp2p GossipSub | External System | Decentralized pubsub protocol for real-time message delivery |
| Relay Inbox | External System | Store-and-forward relay for group catch-up. It stores a relay record `{from,message,timestamp,id}` whose `message` field is the plaintext replay payload JSON built by Flutter, not the v3 encrypted pubsub envelope |
| Relay Media Store | External System | Optional relay blob store used by the UI-owned media upload step before `sendGroupMessage()` runs |
| Other Group Members | Person | Recipients who receive the message live via GossipSub or later via relay inbox drain |

### Interactions

1. **Member -> App**: Composes text, optionally quotes a message, may attach media, or records a voice message through the compose mic control
2. **App -> Relay Media Store**: For sends with media, including recorded voice attachments, the UI uploads blobs via `media:upload` before `sendGroupMessage()` runs
3. **App -> GossipSub**: Publishes an encrypted + signed v3 envelope to `/mknoon/group/{groupId}`
4. **App -> Relay Inbox**: Concurrently stores a relay group-inbox record for all non-sender members; the stored `message` field contains the plaintext replay payload JSON
5. **GossipSub -> Members**: Delivers live fanout to connected peers; offline peers later catch up via relay inbox drain

---

## Level 2: Container

```
+-----------------------------------------------------------------------+
|                         mknoon Mobile App                             |
|                                                                       |
|  +------------------+   +---------------------+   +------------------+ |
|  | Flutter UI       |-->| Dart Application    |-->| Go Native Bridge | |
|  | GroupConversation|   | uploadMedia()       |   | group:publish    | |
|  | Wired + Screen   |   | sendGroupMessage()  |   | group:inboxStore | |
|  |                  |   | retry/finalization  |   | media:upload     | |
|  +------------------+   +---------------------+   +------------------+ |
|                                 |                        |             |
|                                 v                        v             |
|                          +--------------------+   +------------------+ |
|                          | SQLCipher DB       |   | libp2p + Relay   | |
|                          | group_messages     |   | (Go runtime)     | |
|                          | media_attachments  |   |                  | |
|                          +--------------------+   +------------------+ |
+-----------------------------------------------------------------------+
```

### Containers

| Container | Technology | Responsibility |
|-----------|------------|----------------|
| Flutter UI | Dart / Flutter | `GroupConversationWired` — composer state, optimistic UI, quote state, attachment staging, mic/recording overlay state, and the UI-owned durable-prep/upload step for ordinary media and recorded voice |
| Dart Application | Dart | `uploadMedia()` uploads attachment blobs before send when needed; `sendGroupMessage()` validates, pre-persists or reconciles the canonical row + retry inputs, races publish with relay inbox store, and resolves final status |
| Go Native Bridge | Go / gomobile | `group:publish` builds the encrypted live envelope; `group:inboxStore` stores the plaintext relay replay payload; `media:upload` writes attachment blobs to relay media storage |
| SQLCipher DB | SQLite + SQLCipher | `group_messages` stores send state/retry payloads; `media_attachments` stores attachment metadata/retry state |
| libp2p + Relay | Go / libp2p | Joins `/mknoon/group/{groupId}`; on publish, it may do a short known-member dial/settle step when live topic peers are below expected, then uses relay inbox storage, cursor-based replay, and relay media storage |

### Dual-Path Delivery

```
Optional ordinary-media pre-step (UI-owned, before `sendGroupMessage()`):
GroupConversationWired._onSend()
  |
  +---> _prepareDurableGroupMediaUploads()   // durable branch only; seeds upload_pending attachment rows
  |
  +---> _uploadPreparedGroupMediaUploads() / widget.uploadMediaFn (default `uploadMedia()`)
        ---> media:upload ---> relay media store

Recorded-voice variant (UI-owned, before `sendGroupMessage()`):
GroupConversationWired._onRecordStop()
  |
  +---> AudioRecorderService.stop()
  |
  +---> mediaFileManager.copyToDurableStorage()
  |     // stores the recorded audio under the pending-upload message dir
  |
  +---> mediaAttachmentRepo.saveAttachment(downloadStatus='upload_pending',
  |                                        mediaType='audio',
  |                                        durationMs, waveform)
  |
  +---> msgRepo.saveMessage(optimistic empty-text GroupMessage)
  |
  +---> widget.uploadMediaFn(...) / uploadMedia()
        ---> media:upload ---> relay media store
  |
  +---> sendGroupMessage(text: '', mediaAttachments: [stableVoiceAttachment])

sendGroupMessage()
  |
  +---> callGroupPublish()     ----> GossipSub topic (real-time, connected peers)
  |     returns { ok, topicPeers, messageId }
  |
  +---> _tryInboxStore()       ----> callGroupInboxStore() → relay (plaintext replay payload)
  |     returns bool (true=OK)       (Future<void>, throws on error)
  |
  +---> Status Resolution (6 paths):
        - Publish TIMEOUT + Inbox OK          => success, status='sent'
        - Publish fail (non-timeout)          => error, status='failed'
                                               (`wireEnvelope` retained for publish retry;
                                               `inboxRetryPayload` cleared only if inbox already succeeded)
        - Publish OK + topicPeers null        => success, status='sent'|'pending' (legacy compat)
        - Publish OK + topicPeers > 0         => success, status='sent'|'pending'
        - Publish OK + topicPeers=0 + Inbox OK => successNoPeers, status='sent'
        - Publish OK + topicPeers=0 + Inbox fail => error, status='failed'
        * 'sent' vs 'pending' depends on whether the inbox store already succeeded
        * 'pending' covers both "inbox still running" and "publish succeeded but inbox store failed"
        * Background finalization is only scheduled for the in-flight pending case; the helper then promotes to `sent` if that same inbox future later resolves true
        * Already-failed inbox stores are closed later by `retryFailedGroupInboxStores()`
```

---

## Level 3: Component

```
+-----------------------------------------------------------------------+
|                      Dart Application Layer                           |
|                                                                       |
|  +-----------------------------+                                      |
|  | sendGroupMessage()          |                                      |
|  | use case (with validation)  |                                      |
|  +-----------------------------+                                      |
|       |          |          |                                          |
|       v          v          v                                         |
|  +----------+ +----------+ +----------------------------+             |
|  | prePersist| | publish  | | _tryInboxStore()          |             |
|  | message   | | to topic | | (wraps callGroupInbox-    |             |
|  | (DB)      | | (bridge) | |  Store, returns bool)     |             |
|  +----------+ +----------+ +----------------------------+             |
|       |          |          |                                          |
|       v          v          v                                         |
|  +-----------------------------+    +------------------------------+  |
|  | Status Resolution (6 paths)|    | Background Finalization      |  |
|  | saveMessage() or            |    | _finalizeSuccessful...()     |  |
|  | updateMessageStatus()       |    | upgrades in-flight pending   |  |
|  | + retry payload retention   |    | only                         |  |
|  +-----------------------------+    +------------------------------+  |
|       |                                                               |
|       v                                                               |
|  +-----------------------------+                                      |
|  | GroupMessageRepositoryImpl  |                                      |
|  | saveMessage()               |                                      |
|  | updateMessageStatus()       |                                      |
|  | updateInboxStored()         |                                      |
|  +-----------------------------+                                      |
|       |                                                               |
|       v                                                               |
|  +-----------------------------+                                      |
|  | DB Helpers (db* prefix)     |                                      |
|  | dbInsertGroupMessage()      |                                      |
|  | dbUpdateGroupMessageStatus()|                                      |
|  +-----------------------------+                                      |
+-----------------------------------------------------------------------+
```

Note: in the durable ordinary-media UI branch, `GroupConversationWired`
pre-saves `media_attachments` rows with `downloadStatus='upload_pending'`
before upload and also pre-saves the optimistic parent `group_messages` row
before upload completion. `sendGroupMessage()` then replaces/reconciles that
canonical row with live-publish and relay-inbox retry state.

Recorded voice uses the same durable boundary, but it is reached through
`_onRecordStop()` rather than `_onSend()`: the recording is first copied into
durable group media storage, a pending `media_attachments` row is seeded with
`mediaType='audio'` plus `durationMs` and `waveform`, an optimistic empty-text
parent message row is saved, the audio blob is uploaded, and only then does the
flow call `sendGroupMessage()` with one finalized audio attachment.

### Components

| Component | File | Responsibility |
|-----------|------|----------------|
| `sendGroupMessage()` | `lib/features/groups/application/send_group_message_use_case.dart` | Orchestrates validation, canonical row pre-persist/reconciliation, publish, inbox store, retry-payload persistence, and final status resolution for the message row |
| `GroupConversationWired._onRecordStop()` | `lib/features/groups/presentation/screens/group_conversation_wired.dart` | UI-owned group voice-send path: stops recording, copies the file into durable storage, seeds an optimistic message + `upload_pending` audio attachment row with waveform and duration, uploads the blob, then calls `sendGroupMessage()` with `text=''` and one audio attachment |
| `AudioRecorderService` | `lib/core/media/audio_recorder_service.dart` | Starts, stops, and cancels microphone capture for the group compose surface; supplies the recorded file path, mime type, size, and duration consumed by `_onRecordStop()` |
| `callGroupPublish()` | `lib/core/bridge/bridge_group_helpers.dart` | Bridge: packages the publish request; Go encrypts/signs the v3 envelope, may do a short known-member peer settle when topic peers are below expected, and publishes to `/mknoon/group/{groupId}` |
| `callGroupInboxStore()` | `lib/core/bridge/bridge_group_helpers.dart` | Bridge helper: packages the relay inbox store request; Go stores the plaintext replay payload inside the relay group-inbox record and separately forwards transient recipient/push metadata for fanout |
| `_tryInboxStore()` | `lib/features/groups/application/send_group_message_use_case.dart` | Wraps `callGroupInboxStore` in try/catch, returns `bool` (true=success) |
| `_finalizeSuccessfulPublishInboxStoreInBackground()` | `lib/features/groups/application/send_group_message_use_case.dart` | Background helper scheduled only for the in-flight pending case; when the same inbox future later resolves `true`, it marks `inboxStored`, clears `inboxRetryPayload`, and sets status to `sent` |
| `_persistOutgoingMedia()` | `lib/features/groups/application/send_group_message_use_case.dart` | Persists finalized `media_attachments` rows for the sent message and clears stale `upload_pending` placeholders for the same message ID when needed |
| `GroupMessageRepositoryImpl` | `lib/features/groups/domain/repositories/group_message_repository_impl.dart` | Persists and updates outgoing/incoming `group_messages` rows plus reliability columns |
| `MediaAttachmentRepositoryImpl` | `lib/features/conversation/domain/repositories/media_attachment_repository_impl.dart` | Persists attachment metadata and upload retry state in `media_attachments`, including UI-seeded `upload_pending` rows in durable-media flows |
| `dbInsertGroupMessage()` | `lib/core/database/helpers/group_messages_db_helpers.dart` | SQL INSERT/replace for the full `group_messages` row, including reliability columns when present |
| `dbUpdateGroupMessageStatus()` | `lib/core/database/helpers/group_messages_db_helpers.dart` | SQL UPDATE status column |
| `uploadMedia()` | `lib/features/conversation/application/upload_media_use_case.dart` | UI-owned pre-step for media sends: uploads blobs to the relay media store before `sendGroupMessage()` is invoked |
| `retryFailedGroupMessages()` | `lib/features/groups/application/retry_failed_group_messages_use_case.dart` | Re-attempts failed sends: text-only rows retry directly, while media rows retry only after persisted attachments are already complete |
| `recoverStuckSendingGroupMessages()` | `lib/features/groups/application/recover_stuck_sending_group_messages_use_case.dart` | Transitions messages stuck in 'sending' to 'failed' for retry pickup |
| `retryIncompleteGroupUploads()` | `lib/features/groups/application/retry_incomplete_group_uploads_use_case.dart` | Re-uploads media attachments with `downloadStatus='upload_pending'`, then re-sends |
| `retryFailedGroupInboxStores()` | `lib/features/groups/application/retry_failed_group_inbox_stores_use_case.dart` | Retries relay inbox store for messages with `inbox_stored=0` + persisted retry payload |

Actual send/retry flows also use `updateInboxRetryPayload()` on the group
message repository plus shared `MediaAttachmentRepository` methods such as
`getAttachmentsForMessage()`, `getUploadPendingAttachments()`, and
`saveAttachment()`. For voice, the attachment is still just a `mediaType='audio'`
row from `media_attachments`; the difference is the UI-owned capture and
durable-recording step before upload.

### Message Status State Machine

```
  [composing]
      |
      v
  'sending'  -----> canonical row saved/reconciled in DB
                    (wireEnvelope + inboxRetryPayload cached)
      |
      +--- publish + inbox store (concurrent) --->
      |
      v
  Status Resolution:
      |
      +---> 'sent'       (publish OK + inbox OK, or timeout + inbox OK)
      +---> 'pending'    (publish OK but inbox store is still unresolved OR already failed; retry remains possible)
      +---> 'failed'     (publish failed, or 0 peers + inbox failed — user can retry)
      |
      v
  [wireEnvelope cleared on the 'sent'/'pending' publish-success paths;
   retained on publish-failure paths and on the 0-peers + inbox-failed path]
  [inboxRetryPayload cleared only on inbox success]
  [background: _finalizeSuccessfulPublishInboxStoreInBackground()
   is only scheduled for the in-flight pending case; once scheduled, it
   promotes to 'sent' if that same inbox future later resolves true]
  [retryFailedGroupInboxStores() closes already-failed inbox-store pending rows]
```

---

## Level 4: Code

### sendGroupMessage() Use Case

```dart
// lib/features/groups/application/send_group_message_use_case.dart
// Abridged to the control-flow that defines the send contract.

enum SendGroupMessageResult {
  success,
  groupNotFound,
  groupDissolved,
  unauthorized,
  error,
  /// Publish succeeded but 0 peers were connected to the topic.
  /// The relay inbox accepted custody for offline delivery.
  successNoPeers,
}

Future<(SendGroupMessageResult, GroupMessage?)> sendGroupMessage({
  required Bridge bridge,
  required GroupRepository groupRepo,
  required GroupMessageRepository msgRepo,
  required String groupId,
  required String text,
  required String senderPeerId,
  required String senderPublicKey,
  required String senderPrivateKey,
  required String senderUsername,
  String? messageId,                        // Optional override (used by retry paths)
  DateTime? timestamp,                      // Optional override
  String? quotedMessageId,
  List<MediaAttachment>? mediaAttachments,
  MediaAttachmentRepository? mediaAttachmentRepo,
  bool emitTimingEvent = true,
}) async {
  final sanitizedText = sanitizeMessageText(text);

  // 1. Pre-flight validation
  final group = await groupRepo.getGroup(groupId);
  if (group == null) return (SendGroupMessageResult.groupNotFound, null);
  if (group.isDissolved) return (SendGroupMessageResult.groupDissolved, null);
  if (group.type == GroupType.announcement && isGroupRecoveryInProgress()) {
    return (SendGroupMessageResult.error, null);
  }
  if (group.type == GroupType.announcement && group.myRole != GroupRole.admin) {
    return (SendGroupMessageResult.unauthorized, null);
  }
  if (sanitizedText.trim().isEmpty && !(mediaAttachments?.isNotEmpty ?? false)) {
    return (SendGroupMessageResult.error, null);
  }

  // 2. Prepare parameters (latest key + recipient list load in parallel)
  final now = timestamp ?? DateTime.now().toUtc();
  final latestKeyFuture = groupRepo.getLatestKey(groupId);
  final recipientPeerIdsFuture = _loadGroupPushRecipients(...);
  final latestKey = await latestKeyFuture;
  if (latestKey == null && group.myRole != GroupRole.admin) {
    return (SendGroupMessageResult.error, null); // bootstrap pending
  }
  final resolvedMessageId = messageId ?? const Uuid().v4();
  final keyEpoch = latestKey?.keyGeneration ?? 0;
  final recipientPeerIds = await recipientPeerIdsFuture;

  // 3. Build wireEnvelope (plaintext publish params for retry — NO senderPrivateKey)
  final wireEnvelope = jsonEncode({
    'groupId': groupId, 'text': sanitizedText,
    'senderPeerId': senderPeerId, 'senderPublicKey': senderPublicKey,
    'senderUsername': senderUsername, 'messageId': resolvedMessageId,
    if (quotedMessageId != null && quotedMessageId.isNotEmpty)
      'quotedMessageId': quotedMessageId,
    if (mediaJson != null && mediaJson.isNotEmpty) 'media': mediaJson,
  });

  // 3b. Build the plaintext inbox replay payload (exact `group:inboxStore`
  // message body, not the encrypted GossipSub envelope)
  final inboxPayload = jsonEncode({
    'groupId': groupId,
    'senderId': senderPeerId,
    'senderUsername': senderUsername,
    'keyEpoch': keyEpoch,
    'text': sanitizedText,
    'timestamp': now.toIso8601String(),
    'messageId': resolvedMessageId,
    if (quotedMessageId != null && quotedMessageId.isNotEmpty)
      'quotedMessageId': quotedMessageId,
    if (mediaJson != null && mediaJson.isNotEmpty) 'media': mediaJson,
  });

  // 3c. Build inboxRetryPayload (exact inputs for callGroupInboxStore)
  final inboxRetryPayload = jsonEncode({
    'groupId': groupId, 'message': inboxPayload,
    if (recipientPeerIds.isNotEmpty) 'recipientPeerIds': recipientPeerIds,
    if (pushTitle.isNotEmpty) 'pushTitle': pushTitle,
    if (pushBody.isNotEmpty) 'pushBody': pushBody,
  });

  // 4. Pre-persist with status='sending'
  final prePersistMessage = GroupMessage(
    id: resolvedMessageId, groupId: groupId,
    senderPeerId: senderPeerId, senderUsername: senderUsername,
    text: sanitizedText, timestamp: now,
    quotedMessageId: quotedMessageId, keyGeneration: keyEpoch,
    status: 'sending', isIncoming: false, createdAt: now,
    wireEnvelope: wireEnvelope, inboxStored: false,
    inboxRetryPayload: inboxRetryPayload,
  );
  await msgRepo.saveMessage(prePersistMessage);

  // 5. Concurrent publish + inbox store
  final publishFuture = callGroupPublish(bridge,
    groupId: groupId, text: sanitizedText, senderPeerId: senderPeerId,
    senderPublicKey: senderPublicKey, senderPrivateKey: senderPrivateKey,
    senderUsername: senderUsername, messageId: resolvedMessageId,
    quotedMessageId: quotedMessageId, media: mediaJson,
  );
  bool? inboxResult;
  final inboxFuture = _tryInboxStore(bridge: bridge, groupId: groupId,
    inboxPayload: inboxPayload,
    recipientPeerIds: recipientPeerIds.isNotEmpty ? recipientPeerIds : null,
    pushTitle: pushTitle, pushBody: pushBody,
  ).then((v) { inboxResult = v; return v; });

  // 6. Await publish result
  Map<String, dynamic>? publishResult;
  bool publishOk = false;
  String? publishErrorCode;

  try {
    publishResult = await publishFuture;
    publishOk = publishResult['ok'] == true;
    publishErrorCode = publishResult['errorCode']?.toString();
  } catch (_) {}

  // 7. Status resolution (6 paths)
  if (!publishOk) {
    final inboxOk = await inboxFuture;
    if (publishErrorCode == 'BRIDGE_TIMEOUT' && inboxOk) {
      final sentMessage = prePersistMessage.copyWith(
        status: 'sent', wireEnvelope: null, inboxStored: true, inboxRetryPayload: null);
      await msgRepo.saveMessage(sentMessage);
      return (SendGroupMessageResult.success, sentMessage);
    }

    final failedMessage = prePersistMessage.copyWith(
      status: 'failed',
      inboxStored: inboxOk,
      inboxRetryPayload: inboxOk ? null : prePersistMessage.inboxRetryPayload,
    );
    await msgRepo.updateMessageStatus(resolvedMessageId, 'failed');
    await msgRepo.updateInboxStored(resolvedMessageId, stored: inboxOk);
    if (inboxOk) {
      await msgRepo.updateInboxRetryPayload(resolvedMessageId, null);
    }
    return (SendGroupMessageResult.error, failedMessage);
  }

  final topicPeers = publishResult?.containsKey('topicPeers') == true
      ? publishResult!['topicPeers'] as int?
      : null;

  if (topicPeers == null || topicPeers > 0) {
    final resolvedInboxOk = inboxResult; // true, false, or null
    final finalMessage = prePersistMessage.copyWith(
      status: resolvedInboxOk == true ? 'sent' : 'pending',
      wireEnvelope: null,
      inboxStored: resolvedInboxOk == true,
      inboxRetryPayload: resolvedInboxOk == true ? null : prePersistMessage.inboxRetryPayload);
    await msgRepo.saveMessage(finalMessage);
    if (resolvedInboxOk == null) {
      _finalizeSuccessfulPublishInboxStoreInBackground(
        inboxFuture: inboxFuture, msgRepo: msgRepo, messageId: resolvedMessageId);
    }
    return (SendGroupMessageResult.success, finalMessage);
  }

  // topicPeers == 0
  final inboxOk = await inboxFuture;
  if (inboxOk) {
    final sentMessage = prePersistMessage.copyWith(
      status: 'sent', wireEnvelope: null, inboxStored: true, inboxRetryPayload: null);
    await msgRepo.saveMessage(sentMessage);
    return (SendGroupMessageResult.successNoPeers, sentMessage);
  } else {
    await msgRepo.updateMessageStatus(resolvedMessageId, 'failed');
    return (SendGroupMessageResult.error, prePersistMessage.copyWith(status: 'failed'));
  }
}
```

`pending` here means publish succeeded but durable inbox delivery is not yet
closed. That can be either "inbox future still running" or "inbox already
failed"; only the first case is upgraded by background finalization.

### callGroupPublish() Bridge Helper

```dart
// lib/core/bridge/bridge_group_helpers.dart

Future<Map<String, dynamic>> callGroupPublish(
  Bridge bridge, {
  required String groupId,
  required String text,
  required String senderPeerId,
  required String senderPublicKey,
  required String senderPrivateKey,
  String senderUsername = '',
  String? messageId,
  String? quotedMessageId,
  List<Map<String, dynamic>>? media,
  Duration timeout = const Duration(seconds: 10),
}) async {
  final payload = <String, dynamic>{
    'groupId': groupId,
    'text': text,
    'senderPeerId': senderPeerId,
    'senderPublicKey': senderPublicKey,
    'senderPrivateKey': senderPrivateKey,
    'senderUsername': senderUsername,
  };
  if (messageId != null && messageId.isNotEmpty) payload['messageId'] = messageId;
  if (quotedMessageId != null && quotedMessageId.isNotEmpty) payload['quotedMessageId'] = quotedMessageId;
  if (media != null && media.isNotEmpty) payload['media'] = media;

  final request = {'cmd': 'group:publish', 'payload': payload};
  try {
    final responseJson = await bridge.send(jsonEncode(request)).timeout(timeout);
    return jsonDecode(responseJson) as Map<String, dynamic>;
    // Success: { "ok": true, "messageId": "...", "topicPeers": N }
    // Error:   { "ok": false, "errorCode": "...", "errorMessage": "..." }
  } on TimeoutException {
    return {
      'ok': false,
      'errorCode': 'BRIDGE_TIMEOUT',
      'errorMessage': 'Bridge call timed out after ${timeout.inSeconds}s',
    };
  }
}
```

`callGroupPublish()` only packages the Flutter-side request and returns the raw bridge response. Topic naming, the short publish-time peer settle, envelope construction, and the final `topic.Publish()` call happen in Go. The same `/mknoon/group/{groupId}` string is also reused as the group's rendezvous namespace during background discovery. `callGroupInboxStore()` is a separate helper that forwards the plaintext replay payload plus optional `recipientPeerIds`, `pushTitle`, and `pushBody` to the Go bridge.

### V3 Wire Envelope (Go-side)

The v3 envelope has a **two-layer structure**: an outer envelope (cleartext metadata for routing/verification) and an inner encrypted payload (message content).

Important: this v3 envelope is published to GossipSub only. The relay inbox path stores a separate plaintext JSON replay payload built in Dart (`groupId`, `senderId`, `senderUsername`, `keyEpoch`, `text`, `timestamp`, `messageId`, and optional `quotedMessageId` / `media`).

**Outer Envelope** (`GroupEnvelope` in `go-mknoon/internal/group_envelope.go`):
```json
{
  "version": "3",
  "type": "group_message",
  "groupId": "abc123...",
  "senderId": "12D3KooW...",
  "senderPublicKey": "<base64 Ed25519 public key>",
  "signature": "<base64 Ed25519 signature over groupId|keyEpoch|ciphertext>",
  "keyEpoch": 1,
  "encrypted": {
    "ciphertext": "<base64 AES-256-GCM ciphertext>",
    "nonce": "<base64 12-byte nonce>"
  }
}
```

**Inner Encrypted Payload** (`GroupMessagePayload`, decrypted from `encrypted.ciphertext`):
```json
{
  "text": "hello world",
  "timestamp": "2026-04-10T12:00:00.000000000Z",
  "username": "alice",
  "extra": {
    "messageId": "uuid-v4",
    "quotedMessageId": "...",
    "media": [...]
  }
}
```

### Go Publish Handler

```go
// go-mknoon/bridge/bridge.go — GroupPublish (entry point)
// go-mknoon/node/pubsub.go   — Node.PublishGroupMessage (core logic)

func (n *Node) PublishGroupMessage(
    groupId, privateKeyB64, senderPeerId, senderPublicKeyB64,
    senderUsername, text, messageId string, opts map[string]interface{},
) (msgID string, topicPeerCount int, err error) {

    topic := n.groupTopics[groupId]
    keyInfo := n.groupKeys[groupId]  // { Key, KeyEpoch }

    // 1. Check write permission
    if !isAllowedWriter(config, senderPeerId) { return error }

    // 2. Build GroupMessagePayload (inner, will be encrypted)
    msgId := messageId  // use provided ID, or generate new UUID
    payload := &GroupMessagePayload{
        Text:      text,
        Timestamp: time.Now().UTC().Format(time.RFC3339Nano),
        Username:  senderUsername,
        Extra:     buildGroupMessageExtra(msgId, opts), // messageId, quotedMessageId, media
    }
    payloadJSON := marshal(payload)

    // 3. Encrypt payload with group AES-256-GCM key
    ctB64, nonceB64 := EncryptGroupMessage(keyInfo.Key, payloadJSON)

    // 4. Build signature data: "groupId|keyEpoch|ciphertext"
    sigData := BuildGroupSignatureData(groupId, keyInfo.KeyEpoch, ctB64)
    signature := SignPayload(privateKeyB64, sigData)  // Ed25519

    // 5. Build GroupEnvelope (v3, outer)
    envelope := &GroupEnvelope{
        Version:         "3",
        Type:            "group_message",
        GroupId:         groupId,
        SenderId:        senderPeerId,
        SenderPublicKey: senderPublicKeyB64,
        Signature:       signature,
        KeyEpoch:        keyInfo.KeyEpoch,
        Encrypted:       GroupEncryptedPayload{Ciphertext: ctB64, Nonce: nonceB64},
    }

    // 6. Briefly refresh/dial known topic peers, then publish to GossipSub
    peerCount := n.ensureGroupTopicPeersBeforePublish(groupId, config, senderPeerId, topic)
    err := topic.Publish(ctx, []byte(envelopeJSON))

    return msgId, peerCount, err
    // Bridge wrapper returns: { "ok": true, "messageId": msgId, "topicPeers": peerCount }
}
```

### GroupMessage Model

```dart
// lib/features/groups/domain/models/group_message.dart

class GroupMessage {
  final String id;                          // UUIDv4
  final String groupId;
  final String senderPeerId;
  final String? senderUsername;
  final String text;
  final DateTime timestamp;
  final String? quotedMessageId;
  final int keyGeneration;                  // Key epoch used for encryption (default 0)
  final String status;                      // 'pending' means publish succeeded but relay inbox work is still unresolved or needs retry
  final bool isIncoming;                    // false for outgoing (default true)
  final DateTime? readAt;
  final DateTime createdAt;
  final List<MediaAttachment> media;        // Loaded from media_attachments table (default [])
  final String? wireEnvelope;               // Cached plaintext publish params retained for failed-send recovery; current retry logic does not replay this blob directly
  final bool inboxStored;                   // true if relay accepted (default false)
  final String? inboxRetryPayload;          // Cached params for inbox retry

  // fromMap() / toMap() for DB serialization
  // copyWith() with sentinel pattern for nullable field clearing
}
```

### Database Schema

```sql
-- Migration 018: base table
CREATE TABLE group_messages (
  id TEXT PRIMARY KEY,
  group_id TEXT NOT NULL,
  sender_peer_id TEXT NOT NULL,
  sender_username TEXT,
  text TEXT NOT NULL,
  timestamp TEXT NOT NULL,
  key_generation INTEGER NOT NULL DEFAULT 0,
  status TEXT NOT NULL DEFAULT 'sent',
  is_incoming INTEGER NOT NULL DEFAULT 1,
  read_at TEXT,
  created_at TEXT NOT NULL
);

CREATE INDEX idx_group_messages_group ON group_messages(group_id);
CREATE INDEX idx_group_messages_ts ON group_messages(timestamp);

-- Migration 026: quoted message support
ALTER TABLE group_messages ADD COLUMN quoted_message_id TEXT;

-- Migration 041: send reliability columns
ALTER TABLE group_messages ADD COLUMN wire_envelope TEXT;              -- Plaintext retry params (cleared on success)
ALTER TABLE group_messages ADD COLUMN inbox_stored INTEGER NOT NULL DEFAULT 0;
ALTER TABLE group_messages ADD COLUMN inbox_retry_payload TEXT;       -- Relay retry params (cleared on success)
```

Attachment metadata lives separately in `media_attachments` (migration 010). Retry pickup starts from `downloadStatus='upload_pending'`, while `upload_retry_count` (migration 042) tracks attempts and eventually terminalizes rows to `upload_failed`. In the durable ordinary-media UI branch, those rows are seeded as `downloadStatus='upload_pending'` before the network upload starts; `sendGroupMessage()` and the retry use cases later finalize or reuse them. The attachment rows reference their parent message by `message_id`; `group_messages` does not embed attachment columns.

### UI Wiring

The send tap originates in `ComposeArea`, is forwarded by
`GroupConversationScreen`, and lands in `GroupConversationWired._onSend()`.

```dart
// lib/features/groups/presentation/screens/group_conversation_wired.dart

class GroupConversationWired extends StatefulWidget {
  // ...

  Future<void> _onSend(String text) async {
    if (!_canWrite) return;
    if (_ownPeerId == null) return;
    if (text.isEmpty && _pendingAttachments.isEmpty) return;
    if (!_tryBeginSendFlow()) return;

    final messageId = _uuid.v4();
    final now = DateTime.now().toUtc();
    final quotedMessageId = _activeQuoteMessageId;
    final mediaToUpload = List<PendingComposerMedia>.from(_pendingAttachments);

    // 1. Clear composer immediately, but keep a snapshot for restore-on-failure
    _pendingAttachments = [];
    _draftText = '';
    _activeQuoteMessageId = null;
    _updateComposerState(
      pendingAttachments: const [],
      isUploading: mediaToUpload.isNotEmpty,
    );

    // 2. Build an optimistic 'sending' row.
    final optimisticMessage = GroupMessage(
      id: messageId, groupId: widget.group.id,
      senderPeerId: _ownPeerId!, senderUsername: _senderUsername,
      text: text, timestamp: now, status: 'sending', isIncoming: false,
      quotedMessageId: quotedMessageId, createdAt: now,
    );
    // Attachments are tracked separately in _mediaMap, not on GroupMessage.media.

    final bgTaskId = await callBgBegin(widget.bridge);
    try {
      List<MediaAttachment>? uploadedAttachments;
      if (mediaToUpload.isNotEmpty) {
        if (_supportsDurableGroupMediaUploads) {
          final preparedUploads = await _prepareDurableGroupMediaUploads(...); // seeds upload_pending attachment rows
          await widget.msgRepo.saveMessage(optimisticMessage); // durable-media path only
          showOptimisticMessage();
          uploadedAttachments = await _uploadPreparedGroupMediaUploads(...);
        } else {
          showOptimisticMessage();
          uploadedAttachments = await widget.uploadMediaFn(...); // repeated per attachment in the non-durable path
        }
      } else {
        showOptimisticMessage();
      }

      // sendGroupMessage() owns the canonical send-state resolution even if
      // the durable-media path already pre-persisted the optimistic parent row.
      final (result, message) = await sendGroupMessage(
        bridge: widget.bridge,
        groupRepo: widget.groupRepo,
        msgRepo: widget.msgRepo,
        groupId: widget.group.id,
        text: text,
        senderPeerId: _ownPeerId!,
        senderPublicKey: _senderPublicKey,
        senderPrivateKey: _senderPrivateKey,
        senderUsername: _senderUsername,
        messageId: messageId,
        timestamp: now,
        quotedMessageId: quotedMessageId,
        mediaAttachments: uploadedAttachments,
        mediaAttachmentRepo: widget.mediaAttachmentRepo,
      );

      if (result == SendGroupMessageResult.success ||
          result == SendGroupMessageResult.successNoPeers) {
        // Upsert returned message, hydrate attachment paths, cleanup pending upload dir
      } else if (result == SendGroupMessageResult.groupNotFound ||
          result == SendGroupMessageResult.groupDissolved ||
          result == SendGroupMessageResult.unauthorized) {
        // Remove optimistic row and cleanup local media state
      } else {
        // Restore composer snapshot and leave the failed row retryable
      }
    } finally {
      await callBgEnd(widget.bridge, bgTaskId);
      _endSendFlow();
    }
  }
}
```
