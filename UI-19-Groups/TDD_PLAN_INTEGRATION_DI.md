# TDD Plan: Group Member Invite -- Integration & DI Layer

## Overview

This plan covers the "invite a member to a group" and "accept a group invite" flows at the integration layer: use cases, listener, repository methods, and DI wiring. It follows the established codebase patterns (top-level functions for use cases, constructor-injected DB helpers, `emitFlowEvent()` at every layer, FakeBridge + InMemoryRepository for tests).

The invite flow is:
1. Admin invites a member: encrypts group metadata (groupId, topicName, groupKey, keyEpoch, member list) via 1:1 ML-KEM channel, sends to invitee's peer
2. Invitee receives the invite as a 1:1 P2P message with `type: "group_invite"`
3. A `GroupInviteListener` picks up the message, decrypts it, and surfaces it to the UI
4. Invitee accepts: calls `joinGroup` (bridge subscribes to topic), persists group + key + self-member

---

## Wire Format

The group invite is sent as a standard v2 ML-KEM encrypted 1:1 message. The plaintext inner payload:

```json
{
  "type": "group_invite",
  "version": "1",
  "payload": {
    "groupId": "uuid-...",
    "groupName": "My Group",
    "groupType": "chat",
    "topicName": "group-uuid-...",
    "groupKey": "base64-symmetric-key",
    "keyEpoch": 0,
    "createdBy": "peer-id-of-creator",
    "inviterPeerId": "peer-id-of-inviter",
    "inviterUsername": "Alice",
    "description": "optional",
    "members": [
      {"peerId": "peer-1", "role": "admin", "publicKey": "...", "mlKemPublicKey": "..."},
      {"peerId": "peer-2", "role": "writer", "publicKey": "...", "mlKemPublicKey": "..."}
    ]
  }
}
```

---

## New/Modified Files Summary

### New Files
| File | Purpose |
|------|---------|
| `lib/features/groups/domain/models/group_invite_payload.dart` | Model for the invite wire payload |
| `lib/features/groups/application/send_group_invite_use_case.dart` | Use case: build invite, encrypt, send via P2P |
| `lib/features/groups/application/accept_group_invite_use_case.dart` | Use case: join group via bridge, persist |
| `lib/features/groups/application/group_invite_listener.dart` | Listener: subscribes to group_invite messages, decrypts, broadcasts |
| `test/features/groups/domain/models/group_invite_payload_test.dart` | Tests for payload model |
| `test/features/groups/application/send_group_invite_use_case_test.dart` | Tests for send invite |
| `test/features/groups/application/accept_group_invite_use_case_test.dart` | Tests for accept invite |
| `test/features/groups/application/group_invite_listener_test.dart` | Tests for listener |

### Modified Files
| File | Change |
|------|--------|
| `lib/core/services/incoming_message_router.dart` | Add `groupInviteStream` for `type: "group_invite"` |
| `lib/main.dart` | Wire `GroupInviteListener` in DI chain |
| `lib/features/identity/presentation/startup_router.dart` | Thread `groupInviteListener` through |
| `lib/features/feed/presentation/screens/feed_wired.dart` | Accept `groupInviteListener` |
| `lib/features/groups/presentation/screens/group_list_wired.dart` | Listen to invite stream for UI refresh |

---

## Phase 1: GroupInvitePayload Model

### Step 1.1: GroupInvitePayload.fromJson parses valid JSON

**Test:** `test/features/groups/domain/models/group_invite_payload_test.dart`
```
test name: "fromJson parses all fields from valid JSON"
asserts:
  - groupId, groupName, groupType, topicName parsed correctly
  - groupKey, keyEpoch parsed correctly
  - createdBy, inviterPeerId, inviterUsername parsed correctly
  - members list parsed with correct peerId, role, publicKey, mlKemPublicKey
  - description parsed when present
```

**Implementation:** `lib/features/groups/domain/models/group_invite_payload.dart`

```dart
class GroupInvitePayload {
  final String groupId;
  final String groupName;
  final String groupType;
  final String topicName;
  final String groupKey;
  final int keyEpoch;
  final String createdBy;
  final String inviterPeerId;
  final String inviterUsername;
  final String? description;
  final List<GroupInviteMember> members;

  const GroupInvitePayload({...});

  factory GroupInvitePayload.fromJson(Map<String, dynamic> json);
  Map<String, dynamic> toJson();
}

class GroupInviteMember {
  final String peerId;
  final String role;
  final String? publicKey;
  final String? mlKemPublicKey;

  const GroupInviteMember({...});

  factory GroupInviteMember.fromJson(Map<String, dynamic> json);
  Map<String, dynamic> toJson();
}
```

### Step 1.2: GroupInvitePayload.toJson round-trips

**Test:**
```
test name: "toJson round-trips through fromJson"
asserts:
  - GroupInvitePayload.fromJson(payload.toJson()) produces identical fields
```

### Step 1.3: fromJson handles missing optional description

**Test:**
```
test name: "fromJson handles null description"
asserts:
  - description is null when not in JSON
  - no exception thrown
```

### Step 1.4: fromJson handles empty members list

**Test:**
```
test name: "fromJson handles empty members list"
asserts:
  - members is empty list, not null
```

---

## Phase 2: IncomingMessageRouter -- Add groupInviteStream

### Step 2.1: Router routes group_invite messages to groupInviteStream

**Test:** `test/core/services/incoming_message_router_test.dart` (add to existing test file)
```
test name: "routes group_invite messages to groupInviteStream"
asserts:
  - When a ChatMessage with type "group_invite" is incoming, it appears on groupInviteStream
  - It does NOT appear on chatMessageStream or contactRequestStream
```

**Implementation:** Modify `lib/core/services/incoming_message_router.dart`

Add:
```dart
final _groupInviteController = StreamController<ChatMessage>.broadcast();
Stream<ChatMessage> get groupInviteStream => _groupInviteController.stream;
```

In `_route()` switch statement, add:
```dart
case 'group_invite':
  _groupInviteController.add(message);
```

In `dispose()`:
```dart
_groupInviteController.close();
```

### Step 2.2: Router does not route group_invite to unknownMessageStream

**Test:**
```
test name: "group_invite messages are not routed to unknownMessageStream"
asserts:
  - unknownMessageStream receives nothing when group_invite is received
```

---

## Phase 3: sendGroupInvite Use Case

This use case orchestrates: gather group metadata, build payload, encrypt via ML-KEM, send via P2P 1:1 channel.

### Function Signature

```dart
Future<SendGroupInviteResult> sendGroupInvite({
  required Bridge bridge,
  required P2PService p2pService,
  required GroupRepository groupRepo,
  required String groupId,
  required String inviteePeerId,
  required String inviteeMlKemPublicKey,
  required String selfPeerId,
  required String selfUsername,
}) async
```

**Return type:**
```dart
enum SendGroupInviteResult {
  success,
  groupNotFound,
  notAdmin,
  noGroupKey,
  encryptionFailed,
  sendFailed,
}
```

### Step 3.1: sendGroupInvite throws groupNotFound when group does not exist

**Test:** `test/features/groups/application/send_group_invite_use_case_test.dart`
```
test name: "returns groupNotFound when group does not exist"
setup:
  - FakeBridge, InMemoryGroupRepository (empty)
asserts:
  - result == SendGroupInviteResult.groupNotFound
  - bridge.sendCallCount == 0 (no bridge calls made)
```

**Implementation:** `lib/features/groups/application/send_group_invite_use_case.dart`

```dart
final group = await groupRepo.getGroup(groupId);
if (group == null) {
  emitFlowEvent(layer: 'FL', event: 'GROUP_INVITE_USE_CASE_NOT_FOUND', details: {...});
  return SendGroupInviteResult.groupNotFound;
}
```

### Step 3.2: sendGroupInvite returns notAdmin when caller is not admin

**Test:**
```
test name: "returns notAdmin when caller is not admin"
setup:
  - Group with myRole: GroupRole.member in repo
asserts:
  - result == SendGroupInviteResult.notAdmin
```

**Implementation:**
```dart
if (group.myRole != GroupRole.admin) {
  emitFlowEvent(layer: 'FL', event: 'GROUP_INVITE_USE_CASE_NOT_ADMIN', details: {...});
  return SendGroupInviteResult.notAdmin;
}
```

### Step 3.3: sendGroupInvite returns noGroupKey when no key exists

**Test:**
```
test name: "returns noGroupKey when no group key is stored"
setup:
  - Admin group in repo, but no keys saved
asserts:
  - result == SendGroupInviteResult.noGroupKey
```

**Implementation:**
```dart
final latestKey = await groupRepo.getLatestKey(groupId);
if (latestKey == null) {
  emitFlowEvent(layer: 'FL', event: 'GROUP_INVITE_USE_CASE_NO_KEY', details: {...});
  return SendGroupInviteResult.noGroupKey;
}
```

### Step 3.4: sendGroupInvite builds correct payload with members

**Test:**
```
test name: "builds invite payload with all group members"
setup:
  - Admin group in repo with 2 members (admin + writer)
  - Group key at generation 0
  - FakeBridge with passthrough ML-KEM encrypt
  - FakeP2PService that records sent messages
asserts:
  - bridge.commandLog contains 'message.encrypt'
  - The plaintext passed to encrypt contains "group_invite" type
  - The plaintext contains correct groupId, groupName, topicName
  - The plaintext contains correct groupKey and keyEpoch
  - The plaintext members array has 2 entries
```

**Implementation:**
Build `GroupInvitePayload`, serialize to JSON, then:
```dart
final innerJson = jsonEncode({
  'type': 'group_invite',
  'version': '1',
  'payload': invitePayload.toJson(),
});
```

### Step 3.5: sendGroupInvite encrypts with invitee ML-KEM key and sends via P2P

**Test:**
```
test name: "encrypts with invitee ML-KEM key and sends via P2P"
setup:
  - Full happy path: admin group, key, members, FakeBridge, FakeP2PService
asserts:
  - bridge.commandLog contains 'message.encrypt'
  - The encrypt request payload contains inviteeMlKemPublicKey as recipientPublicKey
  - p2pService received a sendMessage or storeInInbox call to inviteePeerId
  - result == SendGroupInviteResult.success
```

**Implementation:**
```dart
// Encrypt
final encryptResult = await callEncryptMessage(
  bridge: bridge,
  recipientMlKemPublicKey: inviteeMlKemPublicKey,
  plaintext: innerJson,
);
if (encryptResult['ok'] != true) {
  return SendGroupInviteResult.encryptionFailed;
}

// Build v2 envelope
final envelope = jsonEncode({
  'version': '2',
  'senderPeerId': selfPeerId,
  'encrypted': {
    'kem': encryptResult['kem'],
    'ciphertext': encryptResult['ciphertext'],
    'nonce': encryptResult['nonce'],
  },
});

// Send via inbox (offline-safe)
final stored = await p2pService.storeInInbox(inviteePeerId, envelope);
if (!stored) {
  return SendGroupInviteResult.sendFailed;
}

return SendGroupInviteResult.success;
```

### Step 3.6: sendGroupInvite returns encryptionFailed when bridge encrypt fails

**Test:**
```
test name: "returns encryptionFailed when bridge encrypt returns ok=false"
setup:
  - FakeBridge with message.encrypt returning {ok: false}
asserts:
  - result == SendGroupInviteResult.encryptionFailed
  - p2pService has 0 sends (never reached)
```

### Step 3.7: sendGroupInvite returns sendFailed when P2P inbox store fails

**Test:**
```
test name: "returns sendFailed when P2P storeInInbox returns false"
setup:
  - FakeP2PService that returns false from storeInInbox
asserts:
  - result == SendGroupInviteResult.sendFailed
```

### Step 3.8: sendGroupInvite emits flow events at begin and end

**Test:**
```
test name: "emits GROUP_INVITE_USE_CASE_BEGIN and GROUP_INVITE_USE_CASE_SUCCESS flow events"
asserts:
  - (Verify via captured flow events or just check no exceptions thrown on happy path)
  - This is mainly a code-review assertion -- ensure emitFlowEvent calls exist
```

**Implementation:** Add `emitFlowEvent()` at:
- Begin: `GROUP_INVITE_USE_CASE_BEGIN` with groupId, inviteePeerId
- Success: `GROUP_INVITE_USE_CASE_SUCCESS`
- Each error path: `GROUP_INVITE_USE_CASE_NOT_FOUND`, `GROUP_INVITE_USE_CASE_NOT_ADMIN`, etc.

---

## Phase 4: acceptGroupInvite Use Case

This use case wraps the existing `joinGroup` use case with invite-specific logic: parses the payload and delegates to `joinGroup`.

### Function Signature

```dart
Future<AcceptGroupInviteResult> acceptGroupInvite({
  required Bridge bridge,
  required GroupRepository groupRepo,
  required GroupInvitePayload invite,
  required String selfPeerId,
  required String selfPublicKey,
}) async
```

**Return type:**
```dart
enum AcceptGroupInviteResult {
  success,
  alreadyJoined,
  joinFailed,
}
```

### Step 4.1: acceptGroupInvite returns alreadyJoined if group already exists in repo

**Test:** `test/features/groups/application/accept_group_invite_use_case_test.dart`
```
test name: "returns alreadyJoined when group already exists in repo"
setup:
  - GroupModel with same id already in InMemoryGroupRepository
asserts:
  - result == AcceptGroupInviteResult.alreadyJoined
  - bridge.sendCallCount == 0 (no group:join call)
```

**Implementation:**
```dart
final existing = await groupRepo.getGroup(invite.groupId);
if (existing != null) {
  emitFlowEvent(layer: 'FL', event: 'GROUP_ACCEPT_INVITE_ALREADY_JOINED', details: {...});
  return AcceptGroupInviteResult.alreadyJoined;
}
```

### Step 4.2: acceptGroupInvite calls joinGroup with correct parameters

**Test:**
```
test name: "calls bridge group:join and persists group, member, and key"
setup:
  - FakeBridge with group:join returning {ok: true}
  - Empty InMemoryGroupRepository
  - GroupInvitePayload with groupId, topicName, groupKey, keyEpoch, members
asserts:
  - bridge.commandLog contains 'group:join'
  - groupRepo.getGroup(invite.groupId) returns non-null group
  - groupRepo.getMember(invite.groupId, selfPeerId) returns non-null member
  - groupRepo.getLatestKey(invite.groupId) returns key with correct encryptedKey and keyGeneration
  - result == AcceptGroupInviteResult.success
```

**Implementation:**
```dart
final groupModel = GroupModel(
  id: invite.groupId,
  name: invite.groupName,
  type: GroupType.fromValue(invite.groupType),
  topicName: invite.topicName,
  createdAt: DateTime.now().toUtc(),
  createdBy: invite.createdBy,
  myRole: GroupRole.member,
  description: invite.description,
);

await joinGroup(
  bridge: bridge,
  groupRepo: groupRepo,
  group: groupModel,
  groupKey: invite.groupKey,
  keyEpoch: invite.keyEpoch,
  selfPeerId: selfPeerId,
  selfPublicKey: selfPublicKey,
  selfRole: MemberRole.writer,
);
```

### Step 4.3: acceptGroupInvite saves all invite members to repo

**Test:**
```
test name: "saves all members from the invite payload to the repo"
setup:
  - GroupInvitePayload with 3 members (admin + 2 writers)
asserts:
  - groupRepo.getMembers(groupId) returns 4 members (3 from invite + self)
  - Each member has correct role, publicKey, mlKemPublicKey
```

**Implementation:**
After `joinGroup()`, iterate invite.members and save each:
```dart
for (final m in invite.members) {
  final member = GroupMember(
    groupId: invite.groupId,
    peerId: m.peerId,
    role: MemberRole.fromValue(m.role),
    publicKey: m.publicKey,
    mlKemPublicKey: m.mlKemPublicKey,
    joinedAt: DateTime.now().toUtc(),
  );
  await groupRepo.saveMember(member);
}
```

### Step 4.4: acceptGroupInvite returns joinFailed when bridge throws

**Test:**
```
test name: "returns joinFailed when bridge group:join throws"
setup:
  - FakeBridge with throwOnSend = true
asserts:
  - result == AcceptGroupInviteResult.joinFailed
  - groupRepo.getGroup(invite.groupId) returns null (nothing persisted)
```

**Implementation:**
```dart
try {
  await joinGroup(...);
  // save invite members
  return AcceptGroupInviteResult.success;
} catch (e) {
  emitFlowEvent(layer: 'FL', event: 'GROUP_ACCEPT_INVITE_JOIN_FAILED', details: {...});
  return AcceptGroupInviteResult.joinFailed;
}
```

### Step 4.5: acceptGroupInvite emits flow events

**Test:**
```
test name: "emits begin and success flow events on happy path"
asserts:
  - (code review check) emitFlowEvent called with GROUP_ACCEPT_INVITE_BEGIN at start
  - emitFlowEvent called with GROUP_ACCEPT_INVITE_SUCCESS at end
```

---

## Phase 5: GroupInviteListener

Subscribes to the router's `groupInviteStream`, decrypts v2 envelopes, parses `GroupInvitePayload`, and broadcasts to UI.

### Class Signature

```dart
class GroupInviteListener {
  final Stream<ChatMessage> groupInviteStream;
  final Bridge bridge;
  final Future<String?> Function() getOwnMlKemSecretKey;

  Stream<GroupInvitePayload> get inviteStream;

  void start();
  void stop();
  void dispose();
}
```

### Step 5.1: GroupInviteListener broadcasts parsed invite on inviteStream

**Test:** `test/features/groups/application/group_invite_listener_test.dart`
```
test name: "broadcasts parsed GroupInvitePayload when v2 group_invite arrives"
setup:
  - StreamController<ChatMessage> as input
  - PassthroughCryptoBridge (encrypt/decrypt passthrough)
  - getOwnMlKemSecretKey returns a dummy key
  - Add a ChatMessage with v2-encrypted group_invite payload
asserts:
  - inviteStream emits exactly one GroupInvitePayload
  - The payload has correct groupId, groupName, etc.
```

**Implementation:**
```dart
void start() {
  _subscription = groupInviteStream.listen(_onMessage);
}

Future<void> _onMessage(ChatMessage message) async {
  // 1. Parse outer envelope
  final json = jsonDecode(message.content) as Map<String, dynamic>;

  // 2. Decrypt v2
  if (json['version'] == '2') {
    final secretKey = await getOwnMlKemSecretKey();
    if (secretKey == null) return;
    final encrypted = json['encrypted'] as Map<String, dynamic>;
    final decryptResult = await callDecryptMessage(
      bridge: bridge,
      ownMlKemSecretKey: secretKey,
      kem: encrypted['kem'] as String,
      ciphertext: encrypted['ciphertext'] as String,
      nonce: encrypted['nonce'] as String,
    );
    if (decryptResult['ok'] != true) return;
    final innerJson = jsonDecode(decryptResult['plaintext'] as String);
    if (innerJson['type'] != 'group_invite') return;
    final payload = GroupInvitePayload.fromJson(innerJson['payload']);
    _inviteController.add(payload);
  }

  // 3. Also handle v1 (unencrypted, for testing)
  if (json['type'] == 'group_invite' && json['version'] == '1') {
    final payload = GroupInvitePayload.fromJson(json['payload']);
    _inviteController.add(payload);
  }
}
```

### Step 5.2: GroupInviteListener ignores messages with wrong type

**Test:**
```
test name: "ignores messages with type != group_invite"
setup:
  - Send a ChatMessage with type "chat_message" to the input stream
asserts:
  - inviteStream emits nothing
```

### Step 5.3: GroupInviteListener handles decrypt failure gracefully

**Test:**
```
test name: "does not emit when decryption fails"
setup:
  - FakeBridge with message.decrypt returning {ok: false}
asserts:
  - inviteStream emits nothing
  - No exception thrown
```

### Step 5.4: GroupInviteListener handles missing ML-KEM secret key

**Test:**
```
test name: "does not emit when own ML-KEM secret key is null"
setup:
  - getOwnMlKemSecretKey returns null
asserts:
  - inviteStream emits nothing
```

### Step 5.5: GroupInviteListener stops and disposes cleanly

**Test:**
```
test name: "stop() cancels subscription, dispose() closes stream"
setup:
  - Start listener, then stop it
  - Verify no further messages processed
asserts:
  - After stop(), adding to input stream does not produce output
  - After dispose(), inviteStream is done
```

### Step 5.6: GroupInviteListener emits flow events

**Test:**
```
test name: "emits flow events on start, receive, and error"
asserts:
  - (code review) emitFlowEvent with GROUP_INVITE_LISTENER_START on start()
  - emitFlowEvent with GROUP_INVITE_LISTENER_RECEIVED on successful parse
  - emitFlowEvent with GROUP_INVITE_LISTENER_DECRYPT_FAILED on decrypt failure
```

---

## Phase 6: IncomingMessageRouter Integration Test

### Step 6.1: End-to-end: router correctly splits group_invite from chat_message

**Test:** `test/core/services/incoming_message_router_test.dart` (extend existing)
```
test name: "routes group_invite and chat_message to separate streams in same sequence"
setup:
  - FakeP2PService emitting 3 messages: chat_message, group_invite, chat_message
asserts:
  - chatMessageStream receives 2 messages
  - groupInviteStream receives 1 message
```

---

## Phase 7: DI Chain Wiring

### Step 7.1: main.dart creates GroupInviteListener and threads it

**Test:** This is a manual integration verification. No unit test (main.dart is not unit-testable). Verify by code review that the DI chain compiles.

**Implementation changes to `lib/main.dart`:**

```dart
// After messageRouter creation (around line 377), add:
// Note: groupInviteStream needs to be added to IncomingMessageRouter first

// Create group invite listener
final groupInviteListener = GroupInviteListener(
  groupInviteStream: messageRouter.groupInviteStream,
  bridge: bridge,
  getOwnMlKemSecretKey: () async {
    final identity = await repository.loadIdentity();
    return identity?.mlKemSecretKey;
  },
);

// After existing listener starts (around line 468), add:
groupInviteListener.start();

// In MyApp constructor, add:
// groupInviteListener: groupInviteListener,

// In _MyAppState.dispose(), add before groupMessageListener.dispose():
// widget.groupInviteListener.dispose();
```

### Step 7.2: MyApp accepts GroupInviteListener

**Implementation changes to MyApp class:**

```dart
// Add field:
final GroupInviteListener groupInviteListener;

// Add to constructor:
required this.groupInviteListener,
```

### Step 7.3: StartupRouter accepts and threads GroupInviteListener

**Implementation changes to `lib/features/identity/presentation/startup_router.dart`:**

```dart
// Add field:
final GroupInviteListener? groupInviteListener;

// Thread to FeedWired, FirstTimeExperienceWired in all 3 navigation paths
```

### Step 7.4: FeedWired accepts GroupInviteListener

**Implementation changes to `lib/features/feed/presentation/screens/feed_wired.dart`:**

```dart
// Add field:
final GroupInviteListener? groupInviteListener;

// Pass to GroupListWired when navigating to groups tab
```

### Step 7.5: GroupListWired accepts GroupInviteListener and refreshes on invite

**Implementation changes to `lib/features/groups/presentation/screens/group_list_wired.dart`:**

```dart
// Add field:
final GroupInviteListener? groupInviteListener;

// In _startListening(), additionally subscribe to inviteStream:
_inviteSubscription = widget.groupInviteListener?.inviteStream.listen(
  (_) => _loadGroups(),
);
```

### DI Chain Flow (updated)

```
main.dart
  -> SecureKeyStore
  -> EncryptedDB
  -> DB helpers (existing groups/members/keys/messages helpers)
  -> Repos (groupRepository, groupMessageRepository -- already exist)
  -> Bridge
  -> P2PService
  -> IncomingMessageRouter (add groupInviteStream)
  -> GroupInviteListener (NEW)
  -> GroupMessageListener (existing)
  -> MyApp (add groupInviteListener)
    -> StartupRouter (add groupInviteListener)
      -> FeedWired (add groupInviteListener)
        -> GroupListWired (add groupInviteListener)
```

---

## Phase 8: Fake/Mock Strategy

### Existing Fakes (reuse as-is)
| Fake | File | Used for |
|------|------|----------|
| `FakeBridge` | `test/core/bridge/fake_bridge.dart` | All bridge calls, pre-canned responses per command |
| `PassthroughCryptoBridge` | `test/core/bridge/fake_bridge.dart` | ML-KEM encrypt/decrypt passthrough |
| `InMemoryGroupRepository` | `test/shared/fakes/in_memory_group_repository.dart` | Group, member, key persistence |
| `InMemoryGroupMessageRepository` | `test/shared/fakes/in_memory_group_message_repository.dart` | Group message persistence |

### Existing FakeP2PService (reuse as-is)

| Fake | File | Used for |
|------|------|----------|
| `FakeP2PService` | `test/core/services/fake_p2p_service.dart` | P2P send/inbox calls, configurable return values, call tracking |

Key capabilities already built into `FakeP2PService`:
- `storeInInboxResult` (configurable bool) and `lastStoreInInboxPeerId`/`lastStoreInInboxMessage` tracking
- `sendMessageResult` (configurable bool) and `lastSendMessagePeerId`/`lastSendMessageContent` tracking
- `currentState` with `isStarted` support

### FakeBridge Response Configuration for Tests

For `sendGroupInvite` tests:
```dart
bridge.responses['message.encrypt'] = {
  'ok': true,
  'kem': 'fake-kem',
  'ciphertext': 'fake-ciphertext',
  'nonce': 'fake-nonce',
};
```

For `GroupInviteListener` tests:
```dart
// Use PassthroughCryptoBridge -- it already handles message.encrypt/decrypt passthrough
```

For `acceptGroupInvite` tests:
```dart
bridge.responses['group:join'] = {'ok': true};
```

---

## Phase 9: Flow Event Summary

Every layer emits structured flow events via `emitFlowEvent()`.

### sendGroupInvite events
| Event | When |
|-------|------|
| `GROUP_INVITE_USE_CASE_BEGIN` | Entry, with groupId + inviteePeerId |
| `GROUP_INVITE_USE_CASE_NOT_FOUND` | Group not found in repo |
| `GROUP_INVITE_USE_CASE_NOT_ADMIN` | Caller is not admin |
| `GROUP_INVITE_USE_CASE_NO_KEY` | No group key in repo |
| `GROUP_INVITE_USE_CASE_ENCRYPT_FAILED` | Bridge encrypt returned ok=false |
| `GROUP_INVITE_USE_CASE_SEND_FAILED` | P2P storeInInbox returned false |
| `GROUP_INVITE_USE_CASE_SUCCESS` | Invite sent successfully |

### acceptGroupInvite events
| Event | When |
|-------|------|
| `GROUP_ACCEPT_INVITE_BEGIN` | Entry, with groupId |
| `GROUP_ACCEPT_INVITE_ALREADY_JOINED` | Group already exists in repo |
| `GROUP_ACCEPT_INVITE_JOIN_FAILED` | joinGroup threw exception |
| `GROUP_ACCEPT_INVITE_SUCCESS` | Join + persist completed |

### GroupInviteListener events
| Event | When |
|-------|------|
| `GROUP_INVITE_LISTENER_START` | start() called |
| `GROUP_INVITE_LISTENER_RECEIVED` | Successfully parsed + broadcast invite |
| `GROUP_INVITE_LISTENER_DECRYPT_FAILED` | Decrypt returned ok=false |
| `GROUP_INVITE_LISTENER_NO_SECRET_KEY` | getOwnMlKemSecretKey returned null |
| `GROUP_INVITE_LISTENER_PARSE_ERROR` | JSON parse or type mismatch |
| `GROUP_INVITE_LISTENER_STOP` | stop() called |
| `GROUP_INVITE_LISTENER_STREAM_ERROR` | Input stream error |

---

## Implementation Order (Red-Green-Refactor)

Execute in this exact order. Each step is: write failing test -> write minimal code to pass -> refactor.

### Round 1: Model
1. Step 1.1 -- GroupInvitePayload.fromJson (RED: test fails, no file exists)
2. Step 1.1 -- Create model file (GREEN: test passes)
3. Step 1.2 -- toJson round-trip (RED -> GREEN)
4. Step 1.3 -- null description (RED -> GREEN)
5. Step 1.4 -- empty members (RED -> GREEN)
6. Refactor: clean up model

### Round 2: Router
7. Step 2.1 -- Route group_invite (RED: new stream doesn't exist)
8. Step 2.1 -- Add groupInviteStream to router (GREEN)
9. Step 2.2 -- Not routed to unknown (RED -> GREEN)
10. Refactor: verify dispose closes new controller

### Round 3: Send Invite Use Case
11. Step 3.1 -- groupNotFound (RED -> GREEN)
12. Step 3.2 -- notAdmin (RED -> GREEN)
13. Step 3.3 -- noGroupKey (RED -> GREEN)
14. Step 3.4 -- builds correct payload (RED -> GREEN)
15. Step 3.5 -- encrypts and sends (RED -> GREEN)
16. Step 3.6 -- encryptionFailed (RED -> GREEN)
17. Step 3.7 -- sendFailed (RED -> GREEN)
18. Step 3.8 -- flow events (code review)
19. Refactor: extract helpers if needed

### Round 4: Accept Invite Use Case
20. Step 4.1 -- alreadyJoined (RED -> GREEN)
21. Step 4.2 -- calls joinGroup, persists (RED -> GREEN)
22. Step 4.3 -- saves all invite members (RED -> GREEN)
23. Step 4.4 -- joinFailed (RED -> GREEN)
24. Step 4.5 -- flow events (code review)
25. Refactor: clean up

### Round 5: Listener
26. Step 5.1 -- broadcasts parsed invite (RED -> GREEN)
27. Step 5.2 -- ignores wrong type (RED -> GREEN)
28. Step 5.3 -- handles decrypt failure (RED -> GREEN)
29. Step 5.4 -- handles missing secret key (RED -> GREEN)
30. Step 5.5 -- stop/dispose (RED -> GREEN)
31. Step 5.6 -- flow events (code review)
32. Refactor: clean up

### Round 6: Router Integration
33. Step 6.1 -- end-to-end routing test (RED -> GREEN)

### Round 7: DI Wiring
34. Steps 7.1-7.5 -- Wire DI chain (compile-time verification)
35. Run `flutter analyze` to verify no type errors
36. Run full test suite to verify no regressions

---

## Dependencies Between Phases

```
Phase 1 (Model) -- no dependencies
Phase 2 (Router) -- no dependencies
Phase 3 (Send Invite) -- depends on Phase 1 (model)
Phase 4 (Accept Invite) -- depends on Phase 1 (model), uses existing joinGroup
Phase 5 (Listener) -- depends on Phase 1 (model)
Phase 6 (Router Integration) -- depends on Phase 2
Phase 7 (DI Wiring) -- depends on Phase 2 (router), Phase 5 (listener)
```

Phases 1 and 2 can be done in parallel. Phase 3, 4, and 5 can be done in parallel after Phase 1 is complete. Phase 7 comes last.

---

## No New DB Helpers or Migrations Needed

The existing DB helpers and repository methods are sufficient:
- `GroupRepository.saveGroup()` -- persist the group on accept
- `GroupRepository.saveMember()` -- persist each member on accept
- `GroupRepository.saveKey()` -- persist the group key on accept
- `GroupRepository.getGroup()` -- check admin role for send, check already-joined for accept
- `GroupRepository.getLatestKey()` -- get key material for invite payload
- `GroupRepository.getMembers()` -- get member list for invite payload

No new database tables or columns are required. The group_invite is a 1:1 P2P message, not a stored entity -- it's ephemeral (received, parsed, then the group/members/keys are persisted via existing group tables).

---

## No New Bridge Commands Needed

The invite flow uses only existing bridge commands:
- `message.encrypt` -- encrypt the invite payload with invitee's ML-KEM public key
- `message.decrypt` -- decrypt received invite on the listener side
- `group:join` -- join the group topic on accept (called by existing `joinGroup` use case)

The `group:create` command is NOT used -- the admin already created the group. The invitee only joins.
