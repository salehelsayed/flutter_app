# TDD Plan: Group Invite Key-Sharing Protocol Layer

## Overview

This plan implements the protocol layer for sharing group keys with contacts
via encrypted 1:1 P2P messages. When an admin invites a contact to a group,
the invite message carries the `groupId`, `groupKey`, `keyEpoch`, and
`groupConfig` encrypted with the recipient's ML-KEM public key. The receiving
side detects the invite, persists the group locally, and calls `group:join`
on the Go bridge to subscribe to the pubsub topic.

---

## Envelope Format

Group invites travel as encrypted 1:1 messages (the same ML-KEM-768 + AES-256-GCM
path used by `chat_message` v2). The outer envelope is routed by the
`IncomingMessageRouter` via a new `type` field.

### Outer Envelope (v1 plaintext -- only used if recipient lacks ML-KEM key, which should not happen for groups)

```json
{
  "type": "group_invite",
  "version": "1",
  "payload": {
    "id": "<uuid>",
    "groupId": "<uuid>",
    "groupKey": "<base64 AES-256 key>",
    "keyEpoch": 1,
    "groupConfig": {
      "name": "Book Club",
      "groupType": "chat",
      "description": "...",
      "members": [
        {
          "peerId": "12D3KooW...",
          "username": "Alice",
          "role": "admin",
          "publicKey": "<base64>",
          "mlKemPublicKey": "<base64>"
        }
      ],
      "createdBy": "12D3KooW...",
      "createdAt": "2026-03-02T..."
    },
    "senderPeerId": "12D3KooW...",
    "senderUsername": "Alice",
    "timestamp": "2026-03-02T..."
  }
}
```

### Outer Envelope (v2 encrypted -- the required path)

```json
{
  "type": "group_invite",
  "version": "2",
  "senderPeerId": "12D3KooW...",
  "encrypted": {
    "kem": "<base64>",
    "ciphertext": "<base64>",
    "nonce": "<base64>"
  }
}
```

The inner plaintext (before encryption) is the same `payload` object from the
v1 format above, JSON-encoded.

---

## Architecture Decisions

1. **Route through IncomingMessageRouter** -- A new `group_invite` case in the
   router's switch dispatches to a new `groupInviteStream`. This is consistent
   with how `contact_request`, `chat_message`, `profile_update`, and
   `message_reaction` types are routed today.

2. **GroupInviteListener** -- A new listener class (matching the existing
   `ChatMessageListener`, `ReactionListener` patterns) subscribes to the
   `groupInviteStream`, decrypts v2 envelopes, validates the payload, persists
   the group + members + key to the `GroupRepository`, and calls `callGroupJoin`
   on the bridge.

3. **sendGroupInvite use case** -- A top-level function that encrypts the
   invite payload with the recipient's ML-KEM public key and sends it via
   `p2pService.sendMessage` (or inbox fallback). This mirrors how
   `sendChatMessage` encrypts and sends.

4. **GroupInvitePayload model** -- A value class with `fromJson`/`toJson`/
   `toInnerJson`/`buildEncryptedEnvelope`/`parseEncryptedEnvelope` matching
   the `MessagePayload` pattern exactly.

5. **callGroupJoin must be updated** -- The existing `callGroupJoin` in
   `bridge_group_helpers.dart` only sends `groupId` + `topicName`. But the
   Go bridge `GroupJoinTopic` expects `groupId`, `groupConfig`, `groupKey`,
   and `keyEpoch`. A new `callGroupJoinWithConfig` helper (or updated
   `callGroupJoin`) is needed.

---

## File Inventory

### New Files

| File | Purpose |
|------|---------|
| `lib/features/groups/domain/models/group_invite_payload.dart` | Wire-format model for group invite messages |
| `lib/features/groups/application/group_invite_listener.dart` | Listener that processes incoming group invites |
| `lib/features/groups/application/handle_incoming_group_invite_use_case.dart` | Pure function: decrypt, validate, persist, join |
| `lib/features/groups/application/send_group_invite_use_case.dart` | Pure function: encrypt and send invite to a contact |
| `test/features/groups/domain/models/group_invite_payload_test.dart` | Tests for envelope serialization/parsing |
| `test/features/groups/application/group_invite_listener_test.dart` | Tests for the listener |
| `test/features/groups/application/handle_incoming_group_invite_use_case_test.dart` | Tests for the receive/process use case |
| `test/features/groups/application/send_group_invite_use_case_test.dart` | Tests for the send use case |

### Modified Files

| File | Change |
|------|--------|
| `lib/core/services/incoming_message_router.dart` | Add `group_invite` case + `groupInviteStream` |
| `test/core/services/incoming_message_router_test.dart` | Tests for the new route |
| `lib/core/bridge/bridge_group_helpers.dart` | Add `callGroupJoinWithConfig` helper |
| `test/core/bridge/bridge_group_helpers_test.dart` | Tests for the new helper |
| `lib/main.dart` | Wire up `GroupInviteListener` in DI chain |

---

## Mock/Fake Strategy

| Dependency | Fake | Location |
|-----------|------|----------|
| `Bridge` | `FakeBridge` / `PassthroughCryptoBridge` | `test/core/bridge/fake_bridge.dart` (existing) |
| `GroupRepository` | `InMemoryGroupRepository` | `test/shared/fakes/in_memory_group_repository.dart` (existing) |
| `ContactRepository` | `FakeContactRepository` | `test/features/contacts/domain/repositories/fake_contact_repository.dart` (existing) |
| `P2PService` | `FakeP2PService` | existing in test helpers |
| Incoming stream | `StreamController<ChatMessage>.broadcast()` | inline in tests |
| ML-KEM encryption | `PassthroughCryptoBridge` passes plaintext through as-is | existing |

---

## TDD Cycles

Each section below lists tests first (RED), then the implementation to make
them pass (GREEN), then any refactoring (REFACTOR).

---

### Cycle 1: GroupInvitePayload Model

**Goal:** Define the wire-format model for group invite messages.

#### 1.1 RED: `GroupInvitePayload.toInnerJson() serializes all fields`

**File:** `test/features/groups/domain/models/group_invite_payload_test.dart`

```
test name: toInnerJson serializes all required fields
asserts:
  - JSON string contains id, groupId, groupKey, keyEpoch, groupConfig, senderPeerId, senderUsername, timestamp
  - groupConfig contains name, groupType, members, createdBy, createdAt
  - groupConfig.members is a list of maps with peerId, role, publicKey
```

#### 1.2 RED: `GroupInvitePayload.fromInnerJson() parses valid JSON`

```
test name: fromInnerJson round-trips with toInnerJson
asserts:
  - Parsed payload fields match originals
  - groupConfig.members are properly deserialized
```

#### 1.3 RED: `GroupInvitePayload.fromInnerJson() returns null on malformed JSON`

```
test name: fromInnerJson returns null for missing required fields
asserts:
  - returns null when groupId is missing
  - returns null when groupKey is missing
  - returns null when groupConfig is missing
  - returns null when input is not valid JSON
```

#### 1.4 RED: `GroupInvitePayload.toJson() builds v1 envelope`

```
test name: toJson wraps payload in v1 envelope with type group_invite
asserts:
  - outer JSON has "type": "group_invite", "version": "1", "payload": {...}
```

#### 1.5 RED: `GroupInvitePayload.fromJson() parses v1 envelope`

```
test name: fromJson parses v1 group_invite envelope
asserts:
  - returns non-null GroupInvitePayload
  - all fields populated correctly
```

#### 1.6 RED: `GroupInvitePayload.fromJson() returns null for non-group_invite type`

```
test name: fromJson returns null for chat_message type
asserts:
  - returns null when type != "group_invite"
```

#### 1.7 RED: `GroupInvitePayload.buildEncryptedEnvelope() builds v2 envelope`

```
test name: buildEncryptedEnvelope produces v2 group_invite envelope
asserts:
  - outer JSON has "type": "group_invite", "version": "2"
  - "senderPeerId" is present at top level
  - "encrypted" block has kem, ciphertext, nonce
```

#### 1.8 RED: `GroupInvitePayload.parseEncryptedEnvelope() parses v2 envelope`

```
test name: parseEncryptedEnvelope parses v2 group_invite envelope
asserts:
  - returns non-null map for valid v2 group_invite
  - returns null for v2 chat_message (wrong type)
  - returns null for v1 group_invite
  - returns null for garbage JSON
  - returns null when encrypted block is missing kem/ciphertext/nonce
```

#### 1.9 GREEN

**File:** `lib/features/groups/domain/models/group_invite_payload.dart`

Implement `GroupInvitePayload` with:
- Constructor taking `id`, `groupId`, `groupKey`, `keyEpoch`, `groupConfig`
  (as `Map<String, dynamic>`), `senderPeerId`, `senderUsername`, `timestamp`
- `toInnerJson()` -- serializes payload fields (used as plaintext for encryption)
- `fromInnerJson(String)` -- static, parses inner JSON, returns null on invalid
- `toJson()` -- wraps in v1 envelope `{ "type": "group_invite", "version": "1", "payload": {...} }`
- `fromJson(String)` -- static, parses v1 envelope, returns null if type != group_invite
- `buildEncryptedEnvelope(...)` -- static, builds v2 envelope
- `parseEncryptedEnvelope(String)` -- static, returns parsed map or null

Pattern follows `MessagePayload` exactly.

#### 1.10 REFACTOR

None expected -- this is a pure data class.

---

### Cycle 2: callGroupJoinWithConfig Bridge Helper

**Goal:** Create a bridge helper that sends the full group config, key, and
keyEpoch to the Go bridge's `GroupJoinTopic` function.

#### 2.1 RED: `callGroupJoinWithConfig sends correct payload`

**File:** `test/core/bridge/bridge_group_helpers_test.dart`

```
test name: callGroupJoinWithConfig sends group:join with groupId, groupConfig, groupKey, keyEpoch
asserts:
  - bridge.lastSentMessage has cmd "group:join"
  - payload contains groupId, groupConfig (as map), groupKey (string), keyEpoch (int)
```

#### 2.2 RED: `callGroupJoinWithConfig completes without error on success`

```
test name: callGroupJoinWithConfig completes on ok response
asserts:
  - future completes normally
```

#### 2.3 RED: `callGroupJoinWithConfig rethrows TimeoutException`

```
test name: callGroupJoinWithConfig rethrows TimeoutException on timeout
asserts:
  - throws TimeoutException when bridge is slow
```

#### 2.4 GREEN

**File:** `lib/core/bridge/bridge_group_helpers.dart`

Add `callGroupJoinWithConfig`:

```dart
Future<void> callGroupJoinWithConfig(
  Bridge bridge, {
  required String groupId,
  required Map<String, dynamic> groupConfig,
  required String groupKey,
  required int keyEpoch,
  Duration timeout = const Duration(seconds: 30),
}) async { ... }
```

Sends: `{ "cmd": "group:join", "payload": { "groupId": ..., "groupConfig": ..., "groupKey": ..., "keyEpoch": ... } }`

Note: The Go bridge `GroupJoinTopic` expects these exact fields. The existing
`callGroupJoin` with `topicName` is NOT what Go expects -- it appears to be
an older signature that never matched the Go side. This new helper corrects
the mismatch.

#### 2.5 REFACTOR

Consider deprecating the old `callGroupJoin` that takes `topicName`.

---

### Cycle 3: IncomingMessageRouter -- group_invite Route

**Goal:** Add a `group_invite` case to the router so invites flow to their
own typed stream.

#### 3.1 RED: `IncomingMessageRouter routes group_invite to groupInviteStream`

**File:** `test/core/services/incoming_message_router_test.dart`

```
test name: routes group_invite messages to groupInviteStream
asserts:
  - message with type "group_invite" appears on groupInviteStream
  - message does NOT appear on chatMessageStream, contactRequestStream, etc.
```

#### 3.2 RED: `v2 group_invite envelope is routed to groupInviteStream`

```
test name: routes v2 group_invite envelope (type in top-level) to groupInviteStream
asserts:
  - v2 envelope with "type": "group_invite" appears on groupInviteStream
```

#### 3.3 GREEN

**File:** `lib/core/services/incoming_message_router.dart`

- Add `_groupInviteController = StreamController<ChatMessage>.broadcast()`
- Add `Stream<ChatMessage> get groupInviteStream => _groupInviteController.stream`
- Add `case 'group_invite':` to the switch in `_route()`
- Close the controller in `dispose()`

#### 3.4 REFACTOR

None -- minimal one-line addition to existing switch.

---

### Cycle 4: handleIncomingGroupInvite Use Case

**Goal:** Pure function that takes a decrypted invite payload, validates it,
persists the group + members + key, and calls `callGroupJoinWithConfig`.

#### 4.1 RED: `returns success and persists group for valid invite`

**File:** `test/features/groups/application/handle_incoming_group_invite_use_case_test.dart`

```
test name: persists group, members, and key for a valid invite payload
asserts:
  - groupRepo.getGroup(groupId) returns non-null GroupModel
  - GroupModel.name, type, topicName, createdBy, myRole match expected
  - groupRepo.getMembers(groupId) returns the members from config
  - groupRepo.getLatestKey(groupId) returns a GroupKeyInfo with correct key + keyGeneration
  - result == HandleGroupInviteResult.success
```

Uses: `InMemoryGroupRepository`, `FakeBridge` (for callGroupJoinWithConfig)

#### 4.2 RED: `calls callGroupJoinWithConfig with correct arguments`

```
test name: calls group:join bridge command with groupId, groupConfig, groupKey, keyEpoch
asserts:
  - bridge.lastCommand == 'group:join'
  - bridge payload contains groupId, groupConfig map, groupKey, keyEpoch
```

#### 4.3 RED: `returns duplicateGroup when group already exists in repo`

```
test name: returns duplicateGroup when group already exists
asserts:
  - result == HandleGroupInviteResult.duplicateGroup
  - group in repo is unchanged (not overwritten)
  - bridge group:join is NOT called
```

#### 4.4 RED: `returns invalidPayload when groupId is missing`

```
test name: returns invalidPayload for missing groupId
asserts:
  - result == HandleGroupInviteResult.invalidPayload
  - nothing persisted
```

#### 4.5 RED: `returns invalidPayload when groupKey is missing`

```
test name: returns invalidPayload for missing groupKey
asserts:
  - result == HandleGroupInviteResult.invalidPayload
```

#### 4.6 RED: `returns invalidPayload when groupConfig is missing`

```
test name: returns invalidPayload for missing groupConfig
asserts:
  - result == HandleGroupInviteResult.invalidPayload
```

#### 4.7 RED: `returns unknownSender when senderPeerId is not a known contact`

```
test name: returns unknownSender for invite from non-contact
asserts:
  - result == HandleGroupInviteResult.unknownSender
  - nothing persisted
```

#### 4.8 RED: `sets myRole to member (not admin) for the joining user`

```
test name: joining user gets myRole=member in the persisted GroupModel
asserts:
  - GroupModel.myRole == GroupRole.member
```

#### 4.9 RED: `handles bridge timeout gracefully`

```
test name: returns bridgeError when group:join times out
asserts:
  - group IS persisted to local DB (so we can retry join later)
  - result == HandleGroupInviteResult.bridgeError
```

#### 4.10 RED: `decrypts v2 envelope before processing`

```
test name: decrypts v2 invite envelope and processes inner payload
asserts:
  - bridge message.decrypt is called with kem, ciphertext, nonce
  - inner payload is parsed and group is persisted
```

Uses: `PassthroughCryptoBridge` to pass plaintext through

#### 4.11 RED: `returns decryptionFailed for v2 when decryption fails`

```
test name: returns decryptionFailed when bridge decrypt returns ok=false
asserts:
  - result == HandleGroupInviteResult.decryptionFailed
  - nothing persisted
```

#### 4.12 GREEN

**File:** `lib/features/groups/application/handle_incoming_group_invite_use_case.dart`

```dart
enum HandleGroupInviteResult {
  success,
  duplicateGroup,
  invalidPayload,
  unknownSender,
  decryptionFailed,
  bridgeError,
}

Future<HandleGroupInviteResult> handleIncomingGroupInvite({
  required ChatMessage message,
  required GroupRepository groupRepo,
  required ContactRepository contactRepo,
  required Bridge bridge,
  String? ownMlKemSecretKey,
}) async { ... }
```

Steps:
1. Try v2 parse -> decrypt -> fromInnerJson. Fallback to v1 fromJson.
2. Validate required fields (groupId, groupKey, groupConfig).
3. Verify sender is a known contact.
4. Check for duplicate group (getGroup(groupId) != null -> duplicateGroup).
5. Parse groupConfig into GroupModel, members, key.
6. Persist GroupModel with myRole = GroupRole.member.
7. Persist each GroupMember from config.
8. Persist GroupKeyInfo.
9. Call callGroupJoinWithConfig (catch timeout -> bridgeError, but group is still persisted).
10. Return success.

#### 4.13 REFACTOR

Extract config-to-model mapping into a private helper if the function grows large.

---

### Cycle 5: sendGroupInvite Use Case

**Goal:** Pure function that builds a GroupInvitePayload, encrypts it with
the recipient's ML-KEM public key, and sends it via the P2P service.

#### 5.1 RED: `builds and sends encrypted v2 invite envelope`

**File:** `test/features/groups/application/send_group_invite_use_case_test.dart`

```
test name: encrypts invite payload and sends to recipient via p2pService
asserts:
  - bridge message.encrypt is called with recipient's mlKemPublicKey
  - p2pService.sendMessage is called with the recipient's peerId
  - the sent message is a v2 group_invite envelope (parseable by GroupInvitePayload.parseEncryptedEnvelope)
  - result == SendGroupInviteResult.success
```

Uses: `PassthroughCryptoBridge`, `FakeP2PService`

#### 5.2 RED: `returns encryptionRequired when recipient has no ML-KEM key`

```
test name: returns encryptionRequired when recipientMlKemPublicKey is null
asserts:
  - result == SendGroupInviteResult.encryptionRequired
  - p2pService.sendMessage is NOT called
```

#### 5.3 RED: `returns nodeNotRunning when P2P node is stopped`

```
test name: returns nodeNotRunning when p2pService is not started
asserts:
  - result == SendGroupInviteResult.nodeNotRunning
```

#### 5.4 RED: `returns sendFailed when encryption fails`

```
test name: returns sendFailed when bridge encrypt returns ok=false
asserts:
  - result == SendGroupInviteResult.sendFailed
```

#### 5.5 RED: `returns sendFailed when p2pService.sendMessage fails`

```
test name: returns sendFailed when p2pService returns false
asserts:
  - result == SendGroupInviteResult.sendFailed
```

#### 5.6 RED: `falls back to inbox when direct send fails`

```
test name: stores invite in inbox when direct send fails
asserts:
  - p2pService.storeInInbox is called with recipient peerId + encrypted envelope
  - result == SendGroupInviteResult.success
```

#### 5.7 RED: `includes all groupConfig fields in the payload`

```
test name: invite payload includes full groupConfig with members array
asserts:
  - inner JSON (after decryption) contains groupConfig.members with peerId, role, publicKey, mlKemPublicKey
  - inner JSON contains groupId, groupKey, keyEpoch
```

#### 5.8 GREEN

**File:** `lib/features/groups/application/send_group_invite_use_case.dart`

```dart
enum SendGroupInviteResult {
  success,
  nodeNotRunning,
  encryptionRequired,
  sendFailed,
}

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
}) async { ... }
```

Steps:
1. Validate P2P node is running.
2. Validate recipientMlKemPublicKey is not null.
3. Build GroupInvitePayload.
4. Encrypt inner JSON with callEncryptMessage.
5. Build v2 envelope with GroupInvitePayload.buildEncryptedEnvelope.
6. Try p2pService.sendMessage -> if fails, try p2pService.storeInInbox.
7. Return result.

#### 5.9 REFACTOR

None expected -- thin orchestration function.

---

### Cycle 6: GroupInviteListener

**Goal:** Listener class that subscribes to the router's `groupInviteStream`,
calls `handleIncomingGroupInvite`, and broadcasts persisted groups to UI.

#### 6.1 RED: `processes valid v2 invite and emits to groupJoinedStream`

**File:** `test/features/groups/application/group_invite_listener_test.dart`

```
test name: processes v2 invite and broadcasts joined GroupModel
asserts:
  - groupJoinedStream emits a GroupModel with the correct groupId
  - groupRepo contains the new group
  - bridge group:join was called
```

Uses: `StreamController<ChatMessage>.broadcast()` as the incoming stream,
`PassthroughCryptoBridge`, `InMemoryGroupRepository`, `FakeContactRepository`

#### 6.2 RED: `ignores invites from non-contacts`

```
test name: does not broadcast for invite from unknown sender
asserts:
  - groupJoinedStream emits nothing
  - groupRepo is unchanged
```

#### 6.3 RED: `ignores duplicate group invites`

```
test name: does not broadcast for invite to a group already joined
asserts:
  - groupJoinedStream emits nothing
  - groupRepo still has original group (not overwritten)
```

#### 6.4 RED: `handles decryption failure gracefully`

```
test name: does not crash on decryption failure
asserts:
  - groupJoinedStream emits nothing
  - no exception thrown
```

#### 6.5 RED: `start is idempotent`

```
test name: calling start twice does not create duplicate subscriptions
asserts:
  - single invite produces one emission, not two
```

#### 6.6 RED: `stop cancels subscription`

```
test name: stop prevents further processing
asserts:
  - invite added after stop() produces no emission
```

#### 6.7 RED: `dispose closes stream`

```
test name: dispose closes groupJoinedStream
asserts:
  - no errors on dispose
```

#### 6.8 RED: `rejects blocked senders`

```
test name: does not process invite from blocked contact
asserts:
  - groupJoinedStream emits nothing
  - groupRepo is unchanged
```

#### 6.9 GREEN

**File:** `lib/features/groups/application/group_invite_listener.dart`

```dart
class GroupInviteListener {
  final Stream<ChatMessage> groupInviteStream;
  final GroupRepository groupRepo;
  final ContactRepository contactRepo;
  final Bridge bridge;
  final Future<String?> Function() getOwnMlKemSecretKey;

  StreamSubscription<ChatMessage>? _subscription;
  final _groupJoinedController = StreamController<GroupModel>.broadcast();

  Stream<GroupModel> get groupJoinedStream => _groupJoinedController.stream;

  void start() { ... }
  void stop() { ... }
  void dispose() { ... }

  Future<void> _onMessage(ChatMessage message) async {
    // Check blocked sender
    // Call handleIncomingGroupInvite
    // If success, emit GroupModel
  }
}
```

Pattern matches `ReactionListener` exactly.

#### 6.10 REFACTOR

None expected.

---

### Cycle 7: Wire Up in main.dart

**Goal:** Integrate `GroupInviteListener` into the DI chain in `main.dart`.

#### 7.1 RED (manual verification -- no automated test)

This is a wiring step. Verify by:
- The app compiles with `flutter build`.
- The `GroupInviteListener` is started after the router.
- The listener is passed to the widget tree if UI needs to react to new groups.

#### 7.2 GREEN

**File:** `lib/main.dart`

Changes:
1. Add `groupInviteStream` getter usage from `messageRouter.groupInviteStream`.
2. Create `GroupInviteListener` instance with all dependencies.
3. Call `groupInviteListener.start()` after `messageRouter.start()`.
4. Thread `groupInviteListener` through the DI chain if screens need
   `groupJoinedStream` (e.g., to refresh the group list).

```dart
// After messageRouter is created:
final groupInviteListener = GroupInviteListener(
  groupInviteStream: messageRouter.groupInviteStream,
  groupRepo: groupRepository,
  contactRepo: contactRepository,
  bridge: bridge,
  getOwnMlKemSecretKey: () async {
    final identity = await repository.loadIdentity();
    return identity?.mlKemSecretKey;
  },
);

// Start it:
groupInviteListener.start();
```

#### 7.3 REFACTOR

Review whether `GroupInviteListener` should be passed to `StartupRouter` ->
`FeedWired` -> ... for UI updates, or if UI screens poll the `GroupRepository`
directly.

---

## Edge Cases

### Duplicate Invites

**Covered in:** Cycle 4.3 and Cycle 6.3

When a user receives an invite for a group they already have in their local
database (`groupRepo.getGroup(groupId) != null`), the invite is silently
ignored. The result is `HandleGroupInviteResult.duplicateGroup`. The group
is NOT overwritten -- the existing local state is authoritative.

Rationale: The sender may re-send invites (e.g., after network retry). We
don't want to reset local state (messages, read markers, etc.).

### Invites for Groups You Are Already In (via different path)

Same as duplicate -- the `getGroup` check catches this. If the user was
already in the group (e.g., they created it), the group exists and the
invite is a no-op.

### Malformed Invites

**Covered in:** Cycle 4.4, 4.5, 4.6, Cycle 1.3

- Missing `groupId`, `groupKey`, or `groupConfig` -> `invalidPayload`
- Invalid JSON -> `GroupInvitePayload.fromJson()` returns null -> `invalidPayload`
- Missing fields in `groupConfig` (no `name`, no `members`) -> handled by
  the payload parser returning null

### Invites from Non-Contacts

**Covered in:** Cycle 4.7 and Cycle 6.2

Group invites from unknown peers are rejected with `unknownSender`. This
prevents spam group invites. The sender must be an existing contact.

### Invites from Blocked Contacts

**Covered in:** Cycle 6.8

The listener checks `contact.isBlocked` before processing, mirroring the
pattern in `ChatMessageListener` and `ReactionListener`.

### Decryption Failure

**Covered in:** Cycle 4.11 and Cycle 6.4

If ML-KEM decryption fails (corrupted ciphertext, wrong key), the invite is
silently dropped. The result is `HandleGroupInviteResult.decryptionFailed`.

### Bridge Timeout on group:join

**Covered in:** Cycle 4.9

If the Go bridge times out when calling `group:join`, the group is STILL
persisted locally. This means:
- The user can see the group in their group list.
- A background retry mechanism can call `group:join` later.
- Result is `HandleGroupInviteResult.bridgeError` so the listener knows
  not to emit a "fully joined" event.

### Recipient Has No ML-KEM Key (Send Side)

**Covered in:** Cycle 5.2

If the contact doesn't have an ML-KEM public key, the invite cannot be
encrypted. Result is `SendGroupInviteResult.encryptionRequired`. The UI
should prompt the user to exchange keys first (via contact request).

### Network Failure During Send

**Covered in:** Cycle 5.5, 5.6

Direct send failure falls back to inbox storage. If inbox also fails,
the result is `SendGroupInviteResult.sendFailed`. The UI can show a
retry option.

---

## Implementation Order

1. **Cycle 1** -- GroupInvitePayload model (pure data, no dependencies)
2. **Cycle 2** -- callGroupJoinWithConfig bridge helper (small, isolated)
3. **Cycle 3** -- IncomingMessageRouter group_invite route (one-line addition)
4. **Cycle 4** -- handleIncomingGroupInvite use case (core logic)
5. **Cycle 5** -- sendGroupInvite use case (send path)
6. **Cycle 6** -- GroupInviteListener (orchestration)
7. **Cycle 7** -- main.dart wiring (integration)

Each cycle is independently testable. Cycles 1-3 have no cross-dependencies.
Cycle 4 depends on 1 + 2. Cycle 5 depends on 1. Cycle 6 depends on 3 + 4.
Cycle 7 depends on all.

---

## Test Count Summary

| Cycle | Test Count |
|-------|-----------|
| 1. GroupInvitePayload | 8 tests |
| 2. callGroupJoinWithConfig | 3 tests |
| 3. IncomingMessageRouter route | 2 tests |
| 4. handleIncomingGroupInvite | 11 tests |
| 5. sendGroupInvite | 7 tests |
| 6. GroupInviteListener | 8 tests |
| **Total** | **39 tests** |
