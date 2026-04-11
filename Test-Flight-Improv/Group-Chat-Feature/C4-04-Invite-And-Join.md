# C4 Model: Invite & Join Discussion

> Standalone C4 architecture document for the **Invite & Join** action in the Group Messaging feature. For the Discussion feature, this maps to wire/database group type `chat`, which the UI renders as the "Discussion" badge label, while some shared models and schema snippets below still expose the broader `announcement` and `qa` type set.

---

## Level 1: System Context

```
+------------------+         +---------------------------+         +------------------+
|   Group Admin    |         |   mknoon Mobile App       |         |   Invited User   |
|   (Person)       |-------->|   (Software System)       |-------->|   (Person)       |
|                  | sends   |                           | receives|                  |
+------------------+ invite  +---------------------------+ invite  +------------------+
                                     |
                                     | direct 1:1 send, topic join,
                                     | inbox store/retrieve
                                     v
                         +----------------------------------+
                         | libp2p Network + Relay Services  |
                         | direct P2P, GossipSub, 1:1 inbox,|
                         | group inbox                      |
                         +----------------------------------+
```

### Actors & Systems

| Element | Type | Description |
|---------|------|-------------|
| Group Admin | Person | Member with `admin` role who sends the invite |
| Invited User | Person | Contact who receives the invite and can accept/decline |
| mknoon Mobile App | Software System | Both sender and receiver run the app; sender-side Flutter + bridge-backed libp2p sends the invite, and receiver-side Flutter stores a device-local pending invite until the user accepts or declines |
| libp2p Network + Relay Services | External System | Direct peer-to-peer invite delivery, GossipSub topic delivery after join, 1:1 relay inbox fallback for invites, and relay-backed group inbox catch-up after acceptance |

### Interactions

1. **Admin -> App**: Opens the admin-only add-member flow from `GroupInfoWired` for a non-dissolved group, then selects contacts in `ContactPickerWired`
2. **App (Sender) -> Local State**: Adds each selected contact locally as a `writer` member with `syncBridgeConfig: false`; if at least one add succeeds, it builds one authoritative `groupConfig`, updates Go config once, and issues one `__sys: "members_added"` publish request for already-joined members; later `callGroupUpdateConfig()` or `callGroupPublish()` failures do not roll back those saved member rows
3. **App (Sender) -> libp2p Network + Relay Services**: If `groupRepo.getLatestKey()` returns a key, sends one ML-KEM encrypted v2 invite per successfully added recipient via `p2pService.sendMessage()`, with `p2pService.storeInInbox()` fallback; partial send failures are not rolled back
4. **libp2p Network + Relay Services -> App (Receiver)**: Delivers the encrypted invite to `p2pService.messageStream`, which `IncomingMessageRouter` routes to `GroupInviteListener`
5. **Receiver -> App**: The app stores a device-local 7-day pending invite keyed by `group_id`; the user can review it from Orbit Intros or the Groups screen and tap Accept or Decline, and pending-invite notification taps also redirect to Orbit Intros
6. **App -> libp2p Network + Relay Services**: On Accept, the app persists group/member/key state, optionally downloads the avatar file when blob metadata is present, joins via `callGroupJoinWithConfig()`, and drains the new group's relay-backed offline inbox only on `success`

---

## Level 2: Container

### Sender Side

```
+-----------------------------------------------------------------------+
|                    Sender's mknoon Mobile App                         |
|                                                                       |
|  +------------------+   +---------------------+   +------------------+ |
|  | Flutter UI       |-->| Dart Application    |-->| Go Native Bridge | |
|  | GroupInfoWired   |   | ContactPickerWired  |   | message.encrypt  | |
|  | ContactPicker... |   | batch invite flow   |   | group:update...  | |
|  +------------------+   +---------------------+   | group:publish    | |
|            |                    |                 +------------------+ |
|            |                    v                          |           |
|            |             +------------------+              |           |
|            +------------>| SQLCipher DB     |              v           |
|                          | groups           |    +------------------+  |
|                          | group_members    |    | P2PService       |  |
|                          | group_keys       |    | sendMessage()    |  |
|                          +------------------+    | storeInInbox()   |  |
|                                                  +------------------+  |
+-----------------------------------------------------------------------+
```

### Receiver Side

```
+-----------------------------------------------------------------------+
|                   Receiver's mknoon Mobile App                        |
|                                                                       |
|  +------------------+   +---------------------+  +------------------+ |
|  | P2PService       |-->| Dart Routing +      |->| Dart Application | |
|  | messageStream    |   | Listener            |  | storeIncoming... | |
|  | (bridge-backed)  |   | IncomingMessage...  |  | accept/decline   | |
|  +------------------+   | GroupInviteListener |  +------------------+ |
|                         +---------------------+         |              |
|                                     |                  v              |
|                                     |           +------------------+  |
|                                     |           | Go Native Bridge |  |
|                                     |           | message.decrypt  |  |
|                                     |           | group:join       |  |
|                                     |           | group:inbox...   |  |
|                                     |           +------------------+  |
|                                     v                                  |
|                              +----------------+  +-------------------+ |
|                              | SQLCipher DB   |  | Flutter UI        | |
|                              | pending_       |  | Orbit Intros /    | |
|                              | group_invites  |  | Groups + Card     | |
|                              | groups/members |  |                   | |
|                              | group_keys     |  |                   | |
|                              +----------------+  +-------------------+ |
+-----------------------------------------------------------------------+
```

### Containers

| Container | Technology | Responsibility |
|-----------|------------|----------------|
| Flutter UI (Sender) | Dart / Flutter | `GroupInfoWired` is the admin-only, non-dissolved entry point; `ContactPickerWired` owns the batch invite interaction |
| Dart Application (Sender) | Dart | `ContactPickerWired._inviteSelected()` orchestrates best-effort local member adds, one `groupConfig` rebuild, one `callGroupUpdateConfig()`, one `callGroupPublish()`, and invite fan-out only when a latest key exists; the current UI still pops with the locally added count even if some invite sends fail, and update/publish failures do not undo prior local member saves |
| Go Bridge (Sender) | Go / gomobile | `message.encrypt`, `group:updateConfig`, and `group:publish` bridge commands; `group:updateConfig` unmarshals into Go's `node.GroupConfig`, so Flutter-only avatar metadata fields in the same map are ignored on the Go side |
| P2P Service (Sender) | Dart / bridge-backed libp2p service | Direct send and 1:1 relay inbox fallback via `sendMessage()` and `storeInInbox()` |
| Dart Routing + Listeners (Receiver) | Dart | `IncomingMessageRouter` routes `group_invite` messages from `p2pService.messageStream`; `GroupInviteListener` filters blocked senders and stores pending invites |
| Dart Application (Receiver) | Dart | `storeIncomingPendingGroupInvite()`, `acceptPendingGroupInvite()`, and `declinePendingGroupInvite()` manage pending-invite lifecycle; the accept path persists local state first, then joins the native topic and drains retained backlog only on `success` |
| Go Bridge (Receiver) | Go / gomobile | `message.decrypt` resolves v2 invite envelopes; `group:join` subscribes the topic; `group:inboxRetrieveCursor` replays retained backlog after a successful accept |
| SQLCipher DB | SQLite + SQLCipher | Sender reads `groups` and writes `group_members`, then reads latest `group_keys` before invite fan-out; Receiver stores device-local `pending_group_invites` (upsert by `group_id`) and, on accept, persists `groups`, `group_members`, and `group_keys` |
| Flutter UI (Receiver) | Dart / Flutter | `PendingGroupInviteCard` is rendered from Orbit Intros and the Groups screen; `group_invite` notifications open Orbit Intros directly, while group-route resolution checks joined group or pending invite, may drain the 1:1 inbox, and redirects to Orbit Intros when only a pending invite exists |

---

## Level 3: Component

### Send Invite Flow

```
+-----------------------------------------------------------------------+
|                     Sender Application Layer                          |
|                                                                       |
|  +-----------------------------+                                        |
|  | ContactPickerWired          |                                        |
|  | _inviteSelected()           |                                        |
|  +-----------------------------+                                        |
|         |                                                             |
|         +--> ensureWithinGroupMembershipLimit()                       |
|         |                                                             |
|         +--> addGroupMember(syncBridgeConfig:false)                   |
|         |        |                                                    |
|         |        v                                                    |
|         |   GroupRepository.saveMember()                              |
|         |                                                             |
|         +--> buildGroupConfigPayload()                                |
|         +--> callGroupUpdateConfig()                                  |
|         +--> callGroupPublish(__sys:'members_added')                  |
|         |                                                             |
|         +--> GroupRepository.getLatestKey()                           |
|         +--> sendGroupInvitesInParallel()                             |
|                    |                                                  |
|                    v                                                  |
|             +---------------------------+                             |
|             | sendGroupInvite()         |                             |
|             +---------------------------+                             |
|                    |                       \                          |
|                    v                        \                         |
|             callEncryptMessage()        p2pService.sendMessage()      |
|                                         + storeInInbox() fallback     |
+-----------------------------------------------------------------------+
```

Note: `_inviteSelected()` skips invite fan-out entirely when `getLatestKey()` returns `null`, and it does not surface partial invite-send failures separately from the local "members added" result.

### Receive & Accept Invite Flow

```
+-----------------------------------------------------------------------+
|                    Receiver Application Layer                         |
|                                                                       |
|  +---------------------------+                                        |
|  | GroupInviteListener       |                                        |
|  | .start()                  |                                        |
|  +---------------------------+                                        |
|         |                                                             |
|         v                                                             |
|  +-------------------------------+                                    |
|  | storeIncomingPendingGroupInvite|                                    |
|  | use case (decrypt, validate,  |                                    |
|  | persist as pending)           |                                    |
|  +-------------------------------+                                    |
|         |                                                             |
|         v                                                             |
|  +---------------------------+                                        |
|  | PendingGroupInviteRepo   |                                        |
|  | .savePendingInvite()     |                                        |
|  +---------------------------+                                        |
|         |                                                             |
|         v (user taps Accept)                                          |
|  +---------------------------+                                        |
|  | acceptPendingGroupInvite  |                                        |
|  | use case                  |                                        |
|  +---------------------------+                                        |
|         |                                                             |
|         v                                                             |
|  +-------------------------------+                                    |
|  | materializeAcceptedGroup      |                                    |
|  | InvitePayload()               |                                    |
|  +-------------------------------+                                    |
|         |                                                             |
|         v                                                             |
|  +---------------------------+                                        |
|  | saveGroup() + saveMember()|                                        |
|  +---------------------------+                                        |
|         |                                                             |
|         v                                                             |
|  +---------------------------+                                        |
|  | saveKey()                 |                                        |
|  +---------------------------+                                        |
|         |                                                             |
|         v                                                             |
|  +---------------------------+                                        |
|  | downloadGroupAvatar()     |                                        |
|  | optional                  |                                        |
|  +---------------------------+                                        |
|         |                                                             |
|         v                                                             |
|  +---------------------------+                                        |
|  | callGroupJoinWithConfig() |                                        |
|  +---------------------------+                                        |
|         |                                                             |
|         v                                                             |
|  +---------------------------+                                        |
|  | drainGroupOfflineInbox    |                                        |
|  | ForGroup() on success     |                                        |
|  +---------------------------+                                        |
+-----------------------------------------------------------------------+
```

Note: `materializeAcceptedGroupInvitePayload()` is serialized in code: it saves the group, then members, then the key, optionally downloads the avatar file, and only then calls `callGroupJoinWithConfig()`.

### Components

| Component | File | Responsibility |
|-----------|------|----------------|
| `ContactPickerWired._inviteSelected()` | `lib/features/groups/presentation/screens/contact_picker_wired.dart` | Real sender-side controller: enforces membership limit, attempts best-effort local adds as `MemberRole.writer`, rebuilds `groupConfig`, does one config sync, publishes one `members_added` system message, then fans out encrypted invites only if a latest group key exists; it pops with the locally added count rather than the invite-send success count, and it does not roll back prior local member saves if config sync or publish later fails |
| `addGroupMember()` | `lib/features/groups/application/add_group_member_use_case.dart` | Validates admin + membership limit; in this invite path it is called with `syncBridgeConfig: false`, so it only persists local member rows and leaves bridge sync to the caller |
| `buildGroupConfigPayload()` | `lib/features/groups/application/group_config_payload.dart` | Builds the authoritative Flutter `groupConfig` snapshot used in invite payloads and membership system messages; this map includes avatar metadata fields that are useful to Flutter peers even though Go ignores them |
| `callGroupUpdateConfig()` | `lib/core/bridge/bridge_group_helpers.dart` | Updates Go's stored `groupConfig` once for the batched member set so publish and validator flows use the same membership snapshot, but only the fields in Go's `node.GroupConfig` are retained natively |
| `callGroupPublish()` | `lib/core/bridge/bridge_group_helpers.dart` | Issues the `members_added` publish request so already-joined members can receive the new membership/config snapshot; the invite flow does not inspect the returned `ok` flag |
| `sendGroupInvitesInParallel()` | `lib/features/groups/application/send_group_invite_use_case.dart` | Runs one encrypted invite send per recipient via `Future.wait`, returns the number of successful sends, and never throws aggregate failure back to the caller; the current caller does not roll back local membership if some sends fail |
| `sendGroupInvite()` | `lib/features/groups/application/send_group_invite_use_case.dart` | Builds `GroupInvitePayload`, encrypts with recipient's ML-KEM key, sends via `P2PService` with inbox fallback |
| `callEncryptMessage()` | `lib/core/bridge/bridge.dart` | ML-KEM-768 KEM encapsulation + AES-256-GCM encryption |
| `IncomingMessageRouter` | `lib/core/services/incoming_message_router.dart` | Routes `type == 'group_invite'` messages from `p2pService.messageStream` into `groupInviteStream` |
| `GroupInviteListener` | `lib/features/groups/application/group_invite_listener.dart` | Filters blocked senders, resolves `receivedAt` from `message.timestamp`, and emits `pendingInviteStream` when a pending invite is stored; `groupJoinedStream` exists but is not emitted by the current invite path |
| `storeIncomingPendingGroupInvite()` | `lib/features/groups/application/handle_incoming_group_invite_use_case.dart` | Decrypts invite, validates sender and transport sender match, validates sender is a known contact, stores in `pending_group_invites` with 7-day TTL |
| `handleIncomingGroupInvite()` | `lib/features/groups/application/handle_incoming_group_invite_use_case.dart` | Auto-accept path — decrypts and directly materializes group (not used by listener) |
| `acceptPendingGroupInvite()` | `lib/features/groups/application/accept_pending_group_invite_use_case.dart` | Loads pending invite, validates expiry and payload, delegates to `materializeAcceptedGroupInvitePayload()`, maps distinct outcomes, and drains the new group's offline inbox only on `success` |
| `declinePendingGroupInvite()` | `lib/features/groups/application/decline_pending_group_invite_use_case.dart` | Deletes invite from `pending_group_invites` |
| `materializeAcceptedGroupInvitePayload()` | `lib/features/groups/application/handle_incoming_group_invite_use_case.dart` | Shared logic: persists `GroupModel`, members, key, avatar metadata, optional avatar-file download, then calls `callGroupJoinWithConfig()`; join failure becomes non-fatal `bridgeError` after persistence |
| `joinGroup()` | `lib/features/groups/application/join_group_use_case.dart` | Generic join helper for other flows; invite acceptance does not use this use case |
| `PendingGroupInviteRepositoryImpl` | `lib/features/groups/domain/repositories/pending_group_invite_repository_impl.dart` | Device-local CRUD for `pending_group_invites`; `savePendingInvite()` upserts by `group_id`, so a later invite preview replaces the earlier row for the same group, and expired-row deletion exists but normal app flows mostly enforce expiry through UI/accept/decline checks instead of scheduled cleanup |
| `resolveGroupNotificationRouteTarget()` | `lib/features/push/application/resolve_group_notification_route_target_use_case.dart` | Resolves a group route target to either an existing joined group or a pending invite; `main.dart` uses the pending-invite result to redirect the UI to Orbit Intros instead of opening a group conversation |

---

## Level 4: Code

### GroupInvitePayload (Wire Format)

For the Discussion feature, `groupConfig['groupType']` is wire/database value `chat`; the UI layer converts that enum value to the "Discussion" label.

```dart
// lib/features/groups/domain/models/group_invite_payload.dart

class GroupInvitePayload {
  final String id;              // UUIDv4 invite instance ID
  final String groupId;
  final String groupKey;        // Base64 AES-256 key (current epoch)
  final int keyEpoch;           // Current key generation
  final Map<String, dynamic> groupConfig;  // Flutter-side authoritative config snapshot
  //   Go join/updateConfig consumes .name, .groupType, .description,
  //   .members[], .createdBy, .createdAt; Flutter also preserves
  //   .avatarBlobId?, .avatarMime?, .metadataUpdatedAt? in the same map.
  final String senderPeerId;
  final String senderUsername;
  final String timestamp;       // ISO 8601 UTC string

  String toInnerJson() => jsonEncode({ ... });   // Inner payload only (for encryption)
  String toJson() => jsonEncode(envelope);        // Full v1 envelope string
  static GroupInvitePayload? fromInnerJson(String innerJson) => ...;
  static GroupInvitePayload? fromJson(String jsonString) => ...;
  static String buildEncryptedEnvelope({...}) => ...; // Builds v2 envelope string
  static Map<String, dynamic>? parseEncryptedEnvelope(String jsonString) => ...; // Parses v2 envelope
}
```

### V2 Wire Envelope (Encrypted Invite)

```json
{
  "type": "group_invite",
  "version": "2",
  "id": "<inviteId>",                          // optional
  "senderPeerId": "12D3KooW...",               // required, cleartext for routing
  "senderUsername": "alice",                    // optional
  "groupId": "abc123...",                       // optional
  "groupName": "Engineering Team",             // optional
  "encrypted": {
    "kem": "<base64 ML-KEM-768 ciphertext>",
    "ciphertext": "<base64 AES-256-GCM encrypted payload>",
    "nonce": "<base64 nonce>"
  }
}
```

### sendGroupInvite() Use Case

```dart
// lib/features/groups/application/send_group_invite_use_case.dart

Future<SendGroupInviteResult> sendGroupInvite({
  required P2PService p2pService,
  required Bridge bridge,
  required String recipientPeerId,
  required String? recipientMlKemPublicKey,
  required String senderPeerId,
  required String senderUsername,
  required String groupId,
  required String groupKey,
  required int keyEpoch,
  required Map<String, dynamic> groupConfig,
}) async {
  // 1. Check P2P node is running
  if (!p2pService.currentState.isStarted) {
    return SendGroupInviteResult.nodeNotRunning;
  }

  // 2. Validate ML-KEM key exists
  if (recipientMlKemPublicKey == null) {
    return SendGroupInviteResult.encryptionRequired;
  }

  // 3. Build GroupInvitePayload
  final payload = GroupInvitePayload(
    id: _uuid.v4(),
    groupId: groupId,
    groupKey: groupKey,
    keyEpoch: keyEpoch,
    groupConfig: groupConfig,
    senderPeerId: senderPeerId,
    senderUsername: senderUsername,
    timestamp: DateTime.now().toUtc().toIso8601String(),
  );

  // 4. Encrypt inner JSON with recipient's ML-KEM public key
  final innerJson = payload.toInnerJson();
  final encryptResult = await callEncryptMessage(
    bridge: bridge,
    recipientMlKemPublicKey: recipientMlKemPublicKey,
    plaintext: innerJson,
  );
  if (encryptResult['ok'] != true) {
    return SendGroupInviteResult.sendFailed;
  }

  // 5. Build v2 envelope via static method
  final envelopeJson = GroupInvitePayload.buildEncryptedEnvelope(
    senderPeerId: senderPeerId,
    inviteId: payload.id,
    senderUsername: senderUsername,
    groupId: groupId,
    groupName: groupConfig['name'] as String?,
    kem: encryptResult['kem'] as String,
    ciphertext: encryptResult['ciphertext'] as String,
    nonce: encryptResult['nonce'] as String,
  );

  // 6. Send via P2P direct, with inbox fallback
  final sent = await p2pService.sendMessage(recipientPeerId, envelopeJson);
  if (sent) return SendGroupInviteResult.success;

  // Inbox fallback (store-and-forward)
  final stored = await p2pService.storeInInbox(recipientPeerId, envelopeJson);
  if (stored) return SendGroupInviteResult.success;

  return SendGroupInviteResult.sendFailed;
}
```

### storeIncomingPendingGroupInvite() Use Case

```dart
// lib/features/groups/application/handle_incoming_group_invite_use_case.dart

Future<(StorePendingGroupInviteResult, PendingGroupInvite?)>
storeIncomingPendingGroupInvite({
  required ChatMessage message,
  required GroupRepository groupRepo,
  required PendingGroupInviteRepository pendingInviteRepo,
  required ContactRepository contactRepo,
  required Bridge bridge,
  String? ownMlKemSecretKey,
  DateTime? receivedAt,
  Duration ttl = pendingGroupInviteTtl,   // 7 days
}) async {
  // 1. Resolve: parse v2 envelope, decrypt, validate sender is known contact
  final (resolveResult, resolvedInvite) = await _resolveIncomingGroupInvite(
    message: message,
    contactRepo: contactRepo,
    bridge: bridge,
    ownMlKemSecretKey: ownMlKemSecretKey,
  );
  // Returns invalidPayload / unknownSender / decryptionFailed on failure

  switch (resolveResult) {
    case _ResolveIncomingGroupInviteResult.invalidPayload:
      return (StorePendingGroupInviteResult.invalidPayload, null);
    case _ResolveIncomingGroupInviteResult.unknownSender:
      return (StorePendingGroupInviteResult.unknownSender, null);
    case _ResolveIncomingGroupInviteResult.decryptionFailed:
      return (StorePendingGroupInviteResult.decryptionFailed, null);
    case _ResolveIncomingGroupInviteResult.success:
      break;
  }

  // 2. Already a member? Skip
  final payload = resolvedInvite!.payload;
  final existingGroup = await groupRepo.getGroup(payload.groupId);
  if (existingGroup != null) {
    return (StorePendingGroupInviteResult.duplicateGroup, null);
  }

  // 3. Build PendingGroupInvite from payload with TTL
  final invite = PendingGroupInvite.fromPayload(
    payload,
    receivedAt: (receivedAt ?? DateTime.now()).toUtc(),
    ttl: ttl,
  );

  // 4. Persist (savePendingInvite() is a replace/upsert keyed by groupId)
  await pendingInviteRepo.savePendingInvite(invite);
  return (StorePendingGroupInviteResult.storedPending, invite);
}
```

### acceptPendingGroupInvite() Use Case

```dart
// lib/features/groups/application/accept_pending_group_invite_use_case.dart

Future<(AcceptPendingGroupInviteResult, GroupModel?)> acceptPendingGroupInvite({
  required PendingGroupInviteRepository pendingInviteRepo,
  required GroupRepository groupRepo,
  required GroupMessageRepository msgRepo,
  required Bridge bridge,
  required String groupId,
  MediaAttachmentRepository? mediaAttachmentRepo,
  GroupMessageListener? groupMessageListener,
  DateTime? now,
  DownloadGroupAvatarFn? downloadGroupAvatarFn,
}) async {
  // 1. Load pending invite
  final invite = await pendingInviteRepo.getPendingInvite(groupId);
  if (invite == null) return (AcceptPendingGroupInviteResult.notFound, null);

  // 2. Check expiry
  if (invite.isExpiredAt((now ?? DateTime.now()).toUtc())) {
    await pendingInviteRepo.deletePendingInvite(groupId);
    return (AcceptPendingGroupInviteResult.expired, null);
  }

  // 3. Parse payload from stored JSON (stored as normalized v1 envelope JSON)
  final payload = invite.toPayload();
  if (payload == null) {
    await pendingInviteRepo.deletePendingInvite(groupId);
    return (AcceptPendingGroupInviteResult.invalidPayload, null);
  }

  // 4. Delegate to shared materialization logic
  final (result, acceptedGroupId) = await materializeAcceptedGroupInvitePayload(
    payload: payload,
    groupRepo: groupRepo,
    bridge: bridge,
    downloadGroupAvatarFn: downloadGroupAvatarFn,
  );

  switch (result) {
    case HandleGroupInviteResult.success:
      await pendingInviteRepo.deletePendingInvite(groupId);
      await drainGroupOfflineInboxForGroup(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: acceptedGroupId ?? groupId,
        mediaAttachmentRepo: mediaAttachmentRepo,
        groupMessageListener: groupMessageListener,
      );
      final group = await groupRepo.getGroup(acceptedGroupId ?? groupId);
      return (AcceptPendingGroupInviteResult.success, group);
    case HandleGroupInviteResult.bridgeError:
      await pendingInviteRepo.deletePendingInvite(groupId);
      final group = await groupRepo.getGroup(acceptedGroupId ?? groupId);
      return (AcceptPendingGroupInviteResult.bridgeError, group);
    case HandleGroupInviteResult.duplicateGroup:
      await pendingInviteRepo.deletePendingInvite(groupId);
      return (AcceptPendingGroupInviteResult.duplicateGroup, null);
    case HandleGroupInviteResult.invalidPayload:
    case HandleGroupInviteResult.unknownSender:
    case HandleGroupInviteResult.decryptionFailed:
      await pendingInviteRepo.deletePendingInvite(groupId);
      return (AcceptPendingGroupInviteResult.invalidPayload, null);
  }
}
```

### materializeAcceptedGroupInvitePayload() (Shared Logic)

```dart
// lib/features/groups/application/handle_incoming_group_invite_use_case.dart

Future<(HandleGroupInviteResult, String?)>
materializeAcceptedGroupInvitePayload({
  required GroupInvitePayload payload,
  required GroupRepository groupRepo,
  required Bridge bridge,
  DownloadGroupAvatarFn? downloadGroupAvatarFn,
}) async {
  // 1. Duplicate check
  final existingGroup = await groupRepo.getGroup(payload.groupId);
  if (existingGroup != null) return (HandleGroupInviteResult.duplicateGroup, null);

  final config = payload.groupConfig;
  final avatarBlobId = config['avatarBlobId'] as String?;
  final avatarMime = config['avatarMime'] as String?;
  final createdAtStr = config['createdAt'] as String?;
  final metadataUpdatedAtStr = config['metadataUpdatedAt'] as String?;
  final createdAt = createdAtStr != null
      ? DateTime.tryParse(createdAtStr) ?? DateTime.now().toUtc()
      : DateTime.now().toUtc();
  final metadataUpdatedAt = metadataUpdatedAtStr != null
      ? DateTime.tryParse(metadataUpdatedAtStr)?.toUtc()
      : null;

  // 2. Build GroupModel from config (myRole hardcoded to member)
  final groupModel = GroupModel(
    id: payload.groupId,
    name: config['name'] as String? ?? 'Unnamed Group',
    type: _parseGroupType(config['groupType'] as String? ?? 'chat'),
    topicName: '/mknoon/group/${payload.groupId}',
    description: config['description'] as String?,
    avatarBlobId: avatarBlobId,
    avatarMime: avatarMime,
    createdAt: createdAt,
    createdBy: config['createdBy'] as String? ?? payload.senderPeerId,
    myRole: GroupRole.member,
    lastMetadataEventAt: metadataUpdatedAt,
  );
  await groupRepo.saveGroup(groupModel);

  // 3. Persist all members from config
  final membersList = config['members'] as List<dynamic>? ?? [];
  for (final memberMap in membersList) {
    final m = memberMap as Map<String, dynamic>;
    await groupRepo.saveMember(GroupMember(
      groupId: payload.groupId,
      peerId: m['peerId'] as String? ?? '',
      username: m['username'] as String?,
      role: _parseMemberRole(m['role'] as String? ?? 'writer'),
      publicKey: m['publicKey'] as String?,
      mlKemPublicKey: m['mlKemPublicKey'] as String?,
      joinedAt: DateTime.now().toUtc(),
    ));
  }

  // 4. Persist group key
  await groupRepo.saveKey(GroupKeyInfo(
    groupId: payload.groupId,
    keyGeneration: payload.keyEpoch,
    encryptedKey: payload.groupKey,
    createdAt: DateTime.now().toUtc(),
  ));

  if (avatarBlobId != null && avatarMime != null) {
    final avatarPath = await (downloadGroupAvatarFn ?? downloadGroupAvatar)(
      bridge: bridge,
      groupId: payload.groupId,
      blobId: avatarBlobId,
    );
    if (avatarPath != null) {
      await groupRepo.updateGroup(groupModel.copyWith(avatarPath: avatarPath));
    }
  }

  // 5. Join via bridge (bridge error is non-fatal — local state is already persisted)
  try {
    await callGroupJoinWithConfig(
      bridge,
      groupId: payload.groupId,
      groupConfig: config,
      groupKey: payload.groupKey,
      keyEpoch: payload.keyEpoch,
    );
  } catch (_) {
    return (HandleGroupInviteResult.bridgeError, payload.groupId);
  }

  return (HandleGroupInviteResult.success, payload.groupId);
}
```

### PendingGroupInvite Model

```dart
// lib/features/groups/domain/models/pending_group_invite.dart

class PendingGroupInvite {
  final String groupId;          // Primary key; later saves replace the row for this group
  final String inviteId;         // UUIDv4
  final String payloadJson;      // Normalized v1 envelope JSON (re-synthesized even from v2)
  final String groupName;
  final GroupType groupType;     // GroupType enum: chat | announcement | qa
  final String? groupDescription;
  final String? avatarBlobId;
  final String? avatarMime;
  final String senderPeerId;
  final String senderUsername;
  final String createdBy;        // Group creator's peerId
  final DateTime createdAt;
  final DateTime? metadataUpdatedAt;
  final DateTime receivedAt;
  final DateTime expiresAt;      // 7-day expiration

  bool isExpiredAt(DateTime now) => !expiresAt.isAfter(now.toUtc());
  GroupInvitePayload? toPayload() => GroupInvitePayload.fromJson(payloadJson);

  // fromMap() / toMap() for DB serialization
  // fromPayload() factory for creating from GroupInvitePayload + TTL
}
```

### Database Schema

```sql
-- Migration 051: pending_group_invites

CREATE TABLE pending_group_invites (
  group_id TEXT PRIMARY KEY,
  invite_id TEXT NOT NULL,
  payload_json TEXT NOT NULL,
  group_name TEXT NOT NULL,
  group_type TEXT NOT NULL CHECK(group_type IN ('chat','announcement','qa')),
  group_description TEXT,
  avatar_blob_id TEXT,
  avatar_mime TEXT,
  sender_peer_id TEXT NOT NULL,
  sender_username TEXT NOT NULL,
  created_by TEXT NOT NULL,
  created_at TEXT NOT NULL,
  metadata_updated_at TEXT,
  received_at TEXT NOT NULL,
  expires_at TEXT NOT NULL
);

CREATE INDEX idx_pending_group_invites_expires_at
  ON pending_group_invites(expires_at);
```

### Message Router (Invite Routing)

```dart
// lib/core/services/incoming_message_router.dart (relevant excerpt)

class IncomingMessageRouter {
  final P2PService p2pService;

  final _groupInviteController = StreamController<ChatMessage>.broadcast();

  Stream<ChatMessage> get groupInviteStream => _groupInviteController.stream;

  void _route(ChatMessage message) {
    if (!message.isIncoming) return;

    final json = jsonDecode(message.content) as Map<String, dynamic>;
    final type = json['type'] as String?;
    switch (type) {
      case 'group_invite':
        _groupInviteController.add(message);
        break;
      case 'group_key_update':
        _groupKeyUpdateController.add(message);
        break;
      // ... other message types
    }
  }
}
```

### GroupInviteListener

```dart
// lib/features/groups/application/group_invite_listener.dart

class GroupInviteListener {
  final Stream<ChatMessage> groupInviteStream;    // Injected from IncomingMessageRouter
  final GroupRepository groupRepo;
  final PendingGroupInviteRepository pendingInviteRepo;
  final ContactRepository contactRepo;
  final Bridge bridge;
  final Future<String?> Function() getOwnMlKemSecretKey;  // Callback, not SecureKeyStore

  StreamSubscription<ChatMessage>? _subscription;
  final _groupJoinedController = StreamController<GroupModel>.broadcast();
  final _pendingInviteController = StreamController<PendingGroupInvite>.broadcast();

  // Declared in code, but the current invite path only emits pending invites.
  Stream<GroupModel> get groupJoinedStream => _groupJoinedController.stream;
  Stream<PendingGroupInvite> get pendingInviteStream => _pendingInviteController.stream;

  void start() {
    if (_subscription != null) return;
    _subscription = groupInviteStream.listen(_onMessage);
  }

  void stop() {
    _subscription?.cancel();
    _subscription = null;
  }

  Future<void> _onMessage(ChatMessage message) async {
    // Check if sender is blocked
    final senderContact = await contactRepo.getContact(message.from);
    if (senderContact != null && senderContact.isBlocked) return;

    final ownSecretKey = await getOwnMlKemSecretKey();

    final (result, pendingInvite) = await storeIncomingPendingGroupInvite(
      message: message,
      groupRepo: groupRepo,
      pendingInviteRepo: pendingInviteRepo,
      contactRepo: contactRepo,
      bridge: bridge,
      ownMlKemSecretKey: ownSecretKey,
      receivedAt:
          DateTime.tryParse(message.timestamp)?.toUtc() ??
          DateTime.now().toUtc(),
    );

    if (result == StorePendingGroupInviteResult.storedPending && pendingInvite != null) {
      _pendingInviteController.add(pendingInvite);
    }
  }

  void dispose() {
    stop();
    _groupJoinedController.close();
    _pendingInviteController.close();
  }
}
```

### UI: Pending Invite Card

```dart
// lib/features/groups/presentation/widgets/pending_group_invite_card.dart

class PendingGroupInviteCard extends StatelessWidget {
  final PendingGroupInvite invite;
  final bool isProcessing;
  final VoidCallback? onAccept;
  final VoidCallback? onDecline;

  @override
  Widget build(BuildContext context) {
    final isExpired = invite.isExpiredAt(DateTime.now().toUtc());
    final acceptLabel = isExpired ? 'Expired' : 'Accept';
    final declineLabel = isExpired ? 'Dismiss' : 'Decline';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0x16FFFFFF),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: isExpired ? Color(0x26FF8A80) : Color(0x1FFFFFFF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(children: [
                  Text(invite.groupName),           // Bold title
                  Text('Invited by ${invite.senderUsername}'),
                ]),
              ),
              Column(children: [
                GroupTypeBadge(type: invite.groupType),
                Text(isExpired ? 'Expired' : _formatExpiry(invite.expiresAt)),
              ]),
            ],
          ),
          if (invite.groupDescription != null &&
              invite.groupDescription!.trim().isNotEmpty)
            Text(invite.groupDescription!),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: isProcessing ? null : onDecline,
                child: Text(declineLabel),
              ),
            ),
            Expanded(
              child: FilledButton(
                onPressed: isProcessing || isExpired ? null : onAccept,
                child: isProcessing
                    ? const CircularProgressIndicator()
                    : Text(acceptLabel),
              ),
            ),
            // Shows CircularProgressIndicator when isProcessing == true
          ]),
        ],
      ),
    );
  }
}
```
