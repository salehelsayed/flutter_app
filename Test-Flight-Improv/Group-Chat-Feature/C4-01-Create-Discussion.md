# C4 Model: Create Discussion

> Standalone C4 architecture document for the **Create Discussion** action in the Group Messaging feature.

---

## Level 1: System Context

```text
+------------------+          +---------------------------+
|   Group Admin    |--------->|   mknoon Mobile App       |
|   (Person)       | creates  |   (Software System)       |
|                  | discussion                           |
+------------------+          +---------------------------+
                                     |            |
                                     | group:create / updateConfig / publish
                                     v            v
                              +-----------+  +-----------+
                              | libp2p    |  | Relay     |
                              | Network   |  | Server    |
                              | (Ext Sys) |  | (Ext Sys) |
                              +-----------+  +-----------+
```

### Actors & Systems

| Element | Type | Description |
|---------|------|-------------|
| Group Admin | Person | The user starting a new **discussion** (`GroupType.chat`) from Orbit |
| mknoon Mobile App | Software System | Flutter app that orchestrates contact selection, group creation, local persistence, config sync, and invite fanout |
| libp2p Network | External System | Go/libp2p runtime used for GossipSub topic join, validator registration, and group message publish |
| Relay Server | External System | Rendezvous and inbox infrastructure used by the Go discovery loop and by invite inbox fallback |

### Interactions

1. **Admin -> App**: In Orbit, the admin taps the discussion create action, selects contacts, and optionally enters a group name. The current shipped discussion flow does **not** collect a description.
2. **App -> libp2p**: Flutter calls `group:create`; Go generates `groupId` and the initial group key, joins the creator to the group topic, registers the validator, and starts background discovery.
3. **App -> App DB**: Flutter persists the new group row, the creator as `admin`, and the initial group key in SQLCipher.
4. **App -> libp2p**: Flutter attempts to save each selected contact locally as a `writer` member, skips contacts whose `addGroupMember()` call fails, rebuilds the current `groupConfig`, sends `group:updateConfig`, and publishes a `members_added` system message for the successfully added subset.
5. **App -> Relay / Peers**: If a latest group key is available, Flutter encrypts one invite per successfully added recipient. `sendGroupInvite()` returns early if the P2P node is stopped or the recipient has no ML-KEM key; otherwise it tries `P2PService.sendMessage()` first and falls back to `storeInInbox()` when the live send returns `false` or throws.
6. **App -> Admin**: On success, the picker route is replaced with `GroupConversationWired` for the new discussion.

Current code gaps that the document must preserve as source of truth:
- The active discussion UI does not expose description entry, even though lower-level Dart APIs accept `description`.
- Go `GroupCreate()` does not currently parse `description` and does not return `topicName`; creator-side Dart persistence therefore falls back to `group-$groupId`, which does not match Go's real `/mknoon/group/$groupId` topic namespace.

---

## Level 2: Container

```text
+-----------------------------------------------------------------------+
|                         mknoon Mobile App                             |
|                                                                       |
|  +-------------------+    +-------------------+    +---------------+  |
|  | Flutter UI        |--->| Dart Application  |--->| Go Native     |  |
|  | Orbit + Picker    |    | Use Cases / Wired |    | Bridge        |  |
|  +-------------------+    +-------------------+    +---------------+  |
|           |                         |                      |           |
|           |                         |                      v           |
|           |                         |                +-----------+     |
|           |                         +--------------->| libp2p    |     |
|           |                         |                | (Go)      |     |
|           v                         v                +-----------+     |
|    +-------------------+    +-------------------+          |           |
|    | SQLCipher DB      |    | Dart P2P Service  |----------+           |
|    | groups/members/   |    | live send +       |                      |
|    | keys              |    | inbox fallback    |                      |
|    +-------------------+    +-------------------+                      |
+-----------------------------------------------------------------------+
```

### Containers

| Container | Technology | Responsibility |
|-----------|------------|----------------|
| Flutter UI | Dart / Flutter | `OrbitScreen` launches the create-discussion flow; `CreateGroupPickerScreen` collects recipients, and `GroupNamePanel` shows the selected contacts while collecting an optional name |
| Dart Application | Dart | `CreateGroupPickerWired`, `createGroupWithMembers()`, `createGroup()`, `addGroupMember()`, and invite fanout orchestration, including per-member failure skipping |
| Dart P2P Service | Dart | `P2PService` performs the live `sendMessage()` attempt for already-encrypted invite envelopes and falls back to relay inbox storage via `storeInInbox()` |
| SQLCipher DB | SQLite + SQLCipher | Persists `groups`, `group_members`, and `group_keys` rows used by create-discussion |
| Go Native Bridge | Go / gomobile | Receives `group:create`, `group:updateConfig`, and `group:publish` bridge commands |
| libp2p (Go) | Go / libp2p | Joins the topic, registers validators, subscribes the creator, publishes system messages, and runs background direct-member recovery plus group rendezvous registration/discovery |

### Data Flow

```text
OrbitScreen ExpandableFab
  --> OrbitWired._onCreateGroup(GroupType.chat)
    --> Navigator.push(CreateGroupPickerWired)
      --> CreateGroupPickerWired._onStartGroup(name?)
        --> createGroupWithMembers(...)
          --> _resolveName() / ensureWithinGroupMembershipLimit()
          --> createGroup(...)
            --> callGroupCreate(...)
              --> Go GroupCreate()
                --> uuid.New().String()
                --> GenerateGroupKey()
                --> JoinGroupTopic(groupId, config, keyInfo)
          --> GroupRepository.saveGroup()
          --> GroupRepository.saveMember(self as admin)
          --> GroupRepository.saveKey()
          --> attempt addGroupMember(... syncBridgeConfig: false) for each selected contact
             --> skip/log individual add failures
          --> buildGroupConfigPayload(group, allMembers)
          --> callGroupUpdateConfig(...)
          --> callGroupPublish(__sys: members_added, addedMembers, groupConfig)
          --> sendGroupInvitesInParallel(successfullyAddedRecipients) if latest key exists
             --> sendGroupInvite(...) per successfully added recipient
               --> precheck: node running + recipient ML-KEM key
               --> callEncryptMessage(...)
               --> P2PService.sendMessage(...)
               --> fallback: P2PService.storeInInbox(...)
        --> Navigator.pushReplacement(GroupConversationWired)
```

Important implementation details:
- The active discussion route is the picker-based flow above.
- Creator-side `topicName` persistence currently falls back to `group-$groupId` because Go `group:create` does not return `topicName`, even though Go actually joins `/mknoon/group/$groupId`.
- Group rendezvous namespace registration happens indirectly inside Go's background discovery loop after relay readiness/circuit setup, not as a direct Flutter-side create RPC.

---

## Level 3: Component

```text
+-------------------------------------------------------------------------+
|                        Dart Application Layer                           |
|                                                                         |
|  +--------------------------+     +----------------------------------+  |
|  | OrbitWired /             |---->| CreateGroupPickerWired          |  |
|  | CreateGroupPickerScreen  |     | _onStartGroup(name?)            |  |
|  +--------------------------+     +----------------------------------+  |
|                                             |                            |
|                                             v                            |
|                              +----------------------------------------+  |
|                              | createGroupWithMembers()               |  |
|                              | - resolveName / limit check            |  |
|                              | - createGroup()                        |  |
|                              | - addGroupMember(..., sync=false) xN   |  |
|                              | - buildGroupConfigPayload()            |  |
|                              | - callGroupUpdateConfig()              |  |
|                              | - callGroupPublish(members_added)      |  |
|                              | - sendGroupInvitesInParallel()         |  |
|                              +----------------------------------------+  |
|                                       |                 |                |
|                                       v                 v                |
|                            +------------------+   +------------------+   |
|                            | GroupRepository  |   | bridge helpers   |   |
|                            | saveGroup/member |   | create/update/   |   |
|                            | /key             |   | publish/encrypt  |   |
|                            +------------------+   +------------------+   |
|                                       |                 |                |
|                                       v                 v                |
|                            +------------------+   +------------------+   |
|                            | DB helpers       |   | P2PService       |   |
|                            | groups/members/  |   | sendMessage /    |   |
|                            | keys inserts     |   | storeInInbox     |   |
|                            +------------------+   +------------------+   |
+-------------------------------------------------------------------------+
```

### Components

| Component | File | Responsibility |
|-----------|------|----------------|
| `OrbitWired._onCreateGroup()` | `lib/features/orbit/presentation/screens/orbit_wired.dart` | Launches the group-create route; the discussion FAB calls it with `GroupType.chat` |
| `CreateGroupPickerWired._onStartGroup()` | `lib/features/groups/presentation/screens/create_group_picker_wired.dart` | Collects selected contacts and optional name, invokes `createGroupWithMembers()`, and navigates to the conversation route |
| `createGroupWithMembers()` | `lib/features/groups/application/create_group_with_members_use_case.dart` | Main create-discussion orchestration for the current shipped flow |
| `createGroup()` | `lib/features/groups/application/create_group_use_case.dart` | Creates the base group, persists the creator as `admin`, and stores the initial key |
| `callGroupCreate()` | `lib/core/bridge/bridge_group_helpers.dart` | Sends the primitive create payload to Go (`name`, `groupType`, creator keys, optional description) |
| `addGroupMember()` | `lib/features/groups/application/add_group_member_use_case.dart` | Attempts to save each selected contact as a local `writer` member during creation with `syncBridgeConfig: false`; `createGroupWithMembers()` logs and skips per-member failures |
| `buildGroupConfigPayload()` | `lib/features/groups/application/group_config_payload.dart` | Builds the full post-create member/config payload sent back into Go |
| `callGroupUpdateConfig()` | `lib/core/bridge/bridge_group_helpers.dart` | Syncs the full `groupConfig` into Go after local member persistence |
| `callGroupPublish()` | `lib/core/bridge/bridge_group_helpers.dart` | Publishes the `members_added` system message to the group topic |
| `sendGroupInvitesInParallel()` / `sendGroupInvite()` | `lib/features/groups/application/send_group_invite_use_case.dart` | Encrypts one invite per successfully added recipient, requires a recipient ML-KEM key, and tries live `sendMessage()` delivery before inbox fallback |
| `GroupRepositoryImpl` | `lib/features/groups/domain/repositories/group_repository_impl.dart` | Persists group, member, and key rows through DB helper functions |

### Interaction Sequence

```text
1. Orbit launches create-discussion with GroupType.chat.
2. CreateGroupPickerWired loads contacts, excludes self, and lets the admin
   select recipients plus an optional name.
3. createGroupWithMembers() resolves the final name:
   - explicit name when provided
   - auto-generated from selected usernames when blank
   It also enforces the 50-member contract before any bridge call.
4. createGroup() calls callGroupCreate().
5. Go GroupCreate():
   - generates groupId (UUID)
   - generates the initial group key
   - builds the creator-only GroupConfig
   - joins the topic and starts background discovery
   - returns { ok, groupId, groupKey, keyEpoch, groupConfig }
6. createGroup() persists:
   - GroupModel(... myRole = admin ...)
   - creator GroupMember(role = admin)
   - GroupKeyInfo(initial key)
   Current creator-side topicName uses
   result['topicName'] ?? 'group-$groupId' because Go omits topicName,
   even though Go actually joined `/mknoon/group/$groupId`.
7. createGroupWithMembers() attempts to save each selected contact locally as
   MemberRole.writer using addGroupMember(... syncBridgeConfig: false).
   Individual add failures are caught, logged, and skipped rather than aborting
   the whole create flow.
8. buildGroupConfigPayload() rebuilds the full config from the persisted group
   and members, then callGroupUpdateConfig() syncs it into Go.
9. createGroupWithMembers() calls callGroupPublish() with a
   __sys = members_added payload for the successfully added subset; the use
   case awaits the bridge call but does not inspect the returned `ok` flag.
10. If a latest group key exists, sendGroupInvitesInParallel() encrypts and
    delivers one invite per successfully added recipient.
    Live P2PService.sendMessage() is attempted first; relay inbox fallback is
    second. Recipients without an ML-KEM public key, or sends while the P2P
    node is not started, reduce `invitesSent` but do not abort creation.
11. The route is replaced with GroupConversationWired for the new discussion,
    and the replacement returns `FeedRouteChanges(changedGroupIds: {result.group.id})`
    to the caller.
```

---

## Level 4: Code

### GroupModel (Domain)

```dart
// lib/features/groups/domain/models/group_model.dart

enum GroupType { chat, announcement, qa }
enum GroupRole { admin, member }

class GroupModel {
  final String id;               // UUID from Go bridge or test harness
  final String name;
  final GroupType type;          // This document models the chat/discussion path
  final String topicName;        // Creator path currently persists 'group-$groupId' even though Go joins '/mknoon/group/$groupId'
  final String? description;     // Supported by model/use cases, not by current picker UI
  final String? avatarBlobId;
  final String? avatarMime;
  final String? avatarPath;
  final DateTime createdAt;
  final String createdBy;
  final GroupRole myRole;        // admin for the creator
  final bool isMuted;
  final bool isDissolved;
  final DateTime? dissolvedAt;
  final String? dissolvedBy;
  final bool isArchived;
  final DateTime? archivedAt;
  final DateTime? lastMembershipEventAt;
  final DateTime? lastMetadataEventAt;
  final DateTime? lastBacklogExpiredAt;
  final DateTime? lastBacklogRetainedAt;

  // fromMap(), toMap(), copyWith(), equality helpers...
}
```

### createGroupWithMembers() Use Case

```dart
// lib/features/groups/application/create_group_with_members_use_case.dart

Future<CreateGroupWithMembersResult> createGroupWithMembers({
  required Bridge bridge,
  required GroupRepository groupRepo,
  required P2PService p2pService,
  required IdentityModel identity,
  required List<ContactModel> selectedContacts,
  required GroupType type,
  String? name,
  String? description,
}) async {
  final resolvedName = _resolveName(name, selectedContacts);

  ensureWithinGroupMembershipLimit(
    currentMemberCount: 1,
    requestedAdditionalMembers: selectedContacts.length,
  );

  final group = await createGroup(
    bridge: bridge,
    groupRepo: groupRepo,
    name: resolvedName,
    type: type,
    creatorPeerId: identity.peerId,
    creatorPublicKey: identity.publicKey,
    creatorMlKemPublicKey: identity.mlKemPublicKey ?? '',
    description: description,
  );

  final addedMembers = <GroupMember>[];
  for (final contact in selectedContacts) {
    try {
      final newMember = GroupMember(
        groupId: group.id,
        peerId: contact.peerId,
        username: contact.username,
        role: MemberRole.writer,
        publicKey: contact.publicKey,
        mlKemPublicKey: contact.mlKemPublicKey,
        joinedAt: DateTime.now().toUtc(),
      );

      await addGroupMember(
        bridge: bridge,
        groupRepo: groupRepo,
        groupId: group.id,
        newMember: newMember,
        selfPeerId: identity.peerId,
        syncBridgeConfig: false,
      );
      addedMembers.add(newMember);
    } catch (_) {
      // Per-member add failures are logged and skipped by the real use case.
    }
  }

  final allMembers = await groupRepo.getMembers(group.id);
  final groupConfig = buildGroupConfigPayload(group, allMembers);

  await callGroupUpdateConfig(
    bridge,
    groupId: group.id,
    groupConfig: groupConfig,
  );

  await callGroupPublish(
    bridge,
    groupId: group.id,
    text: jsonEncode({
      '__sys': 'members_added',
      'members': addedMembers.map((m) => {
        'peerId': m.peerId,
        'username': m.username,
        'role': m.role.toValue(),
        'publicKey': m.publicKey,
        if (m.mlKemPublicKey != null) 'mlKemPublicKey': m.mlKemPublicKey,
      }).toList(),
      'groupConfig': groupConfig,
    }),
    senderPeerId: identity.peerId,
    senderPublicKey: identity.publicKey,
    senderPrivateKey: identity.privateKey,
    senderUsername: identity.username,
  );

  var invitesSent = 0;
  final keyInfo = await groupRepo.getLatestKey(group.id);
  if (keyInfo != null) {
    invitesSent = await sendGroupInvitesInParallel(
      p2pService: p2pService,
      bridge: bridge,
      senderPeerId: identity.peerId,
      senderUsername: identity.username,
      groupId: group.id,
      groupKey: keyInfo.encryptedKey,
      keyEpoch: keyInfo.keyGeneration,
      groupConfig: groupConfig,
      recipients: selectedContacts
          .where((c) => addedMembers.any((m) => m.peerId == c.peerId))
          .map((c) => (peerId: c.peerId, mlKemPublicKey: c.mlKemPublicKey))
          .toList(),
    );
  }

  return CreateGroupWithMembersResult(
    group: group,
    membersAdded: addedMembers.length,
    invitesSent: invitesSent,
  );
}
```

### callGroupCreate() Bridge Helper

```dart
// lib/core/bridge/bridge_group_helpers.dart

Future<Map<String, dynamic>> callGroupCreate(
  Bridge bridge, {
  required String name,
  required String type,
  required String creatorPeerId,
  required String creatorPublicKey,
  String? creatorMlKemPublicKey,
  String? description,
  Duration timeout = const Duration(seconds: 30),
}) async {
  final request = {
    'cmd': 'group:create',
    'payload': {
      'name': name,
      'groupType': type,
      'creatorPeerId': creatorPeerId,
      'creatorPublicKey': creatorPublicKey,
      if (creatorMlKemPublicKey != null)
        'creatorMlKemPublicKey': creatorMlKemPublicKey,
      if (description != null) 'description': description,
    },
  };

  final responseJson = await bridge.send(jsonEncode(request)).timeout(timeout);
  return jsonDecode(responseJson) as Map<String, dynamic>;

  // Real Go success shape today:
  // { ok, groupId, groupKey, keyEpoch, groupConfig }
  //
  // Current Go gap:
  // - no topicName in the response
  // - description is ignored by GroupCreate()
}
```

### Database Schema

```sql
-- Effective v53 schema used by create-discussion persistence

CREATE TABLE IF NOT EXISTS groups (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  type TEXT NOT NULL CHECK(type IN ('chat','announcement','qa')),
  topic_name TEXT NOT NULL UNIQUE,
  description TEXT,
  avatar_blob_id TEXT,
  avatar_mime TEXT,
  avatar_path TEXT,
  created_at TEXT NOT NULL,
  created_by TEXT NOT NULL,
  my_role TEXT NOT NULL CHECK(my_role IN ('admin','member')),
  is_muted INTEGER NOT NULL DEFAULT 0,
  is_dissolved INTEGER NOT NULL DEFAULT 0,
  dissolved_at TEXT,
  dissolved_by TEXT,
  is_archived INTEGER NOT NULL DEFAULT 0,
  archived_at TEXT,
  last_membership_event_at TEXT,
  last_metadata_event_at TEXT,
  last_backlog_expired_at TEXT,
  last_backlog_retained_at TEXT
);

CREATE TABLE IF NOT EXISTS group_members (
  group_id TEXT NOT NULL,
  peer_id TEXT NOT NULL,
  username TEXT,
  role TEXT NOT NULL CHECK(role IN ('admin','writer','reader')),
  public_key TEXT,
  ml_kem_public_key TEXT,
  joined_at TEXT NOT NULL,
  PRIMARY KEY (group_id, peer_id)
);
CREATE INDEX IF NOT EXISTS idx_group_members_group ON group_members(group_id);

CREATE TABLE IF NOT EXISTS group_keys (
  group_id TEXT NOT NULL,
  key_generation INTEGER NOT NULL,
  encrypted_key TEXT NOT NULL,
  created_at TEXT NOT NULL,
  PRIMARY KEY (group_id, key_generation)
);
```

### Go Side (group:create handler)

```go
// go-mknoon/bridge/bridge.go

func GroupCreate(paramsJSON string) (result string) {
    nodeMu.Lock()
    n := singletonNode
    nodeMu.Unlock()
    if n == nil {
        return errJSON("NOT_INITIALIZED", "call Initialize first")
    }

    var params struct {
        Name                  string `json:"name"`
        GroupType             string `json:"groupType"`
        CreatorPeerId         string `json:"creatorPeerId"`
        CreatorPublicKey      string `json:"creatorPublicKey"`
        CreatorMlKemPublicKey string `json:"creatorMlKemPublicKey"`
    }
    if err := json.Unmarshal([]byte(paramsJSON), &params); err != nil {
        return errJSON("INVALID_INPUT", fmt.Sprintf("invalid JSON: %v", err))
    }
    if params.Name == "" || params.GroupType == "" ||
        params.CreatorPeerId == "" || params.CreatorPublicKey == "" {
        return errJSON("INVALID_INPUT", "missing name, groupType, creatorPeerId, or creatorPublicKey")
    }

    groupId := uuid.New().String()
    groupKey, err := mcrypto.GenerateGroupKey()
    if err != nil {
        return errJSON("INTERNAL_ERROR", err.Error())
    }

    config := &node.GroupConfig{
        Name:      params.Name,
        GroupType: node.GroupType(params.GroupType),
        Members: []node.GroupMember{
            {
                PeerId:         params.CreatorPeerId,
                Role:           node.GroupRoleAdmin,
                PublicKey:      params.CreatorPublicKey,
                MlKemPublicKey: params.CreatorMlKemPublicKey,
            },
        },
        CreatedBy: params.CreatorPeerId,
        CreatedAt: time.Now().UTC().Format(time.RFC3339Nano),
    }

    keyInfo := &node.GroupKeyInfo{
        Key:      groupKey,
        KeyEpoch: 1,
    }

    configMap := map[string]interface{}{
        "name":      config.Name,
        "groupType": string(config.GroupType),
        "members":   config.Members,
        "createdBy": config.CreatedBy,
        "createdAt": config.CreatedAt,
    }

    // JoinGroupTopic registers the validator, subscribes to
    // /mknoon/group/<groupId>, and starts background direct-member recovery
    // plus group rendezvous discovery.
    if err := n.JoinGroupTopic(groupId, config, keyInfo); err != nil {
        return errJSON("GROUP_ERROR", err.Error())
    }

    return okJSON(map[string]interface{}{
        "ok":          true,
        "groupId":     groupId,
        "groupKey":    groupKey,
        "keyEpoch":    1,
        "groupConfig": configMap,
    })
}

// Current Go gaps for this create action:
// - GroupCreate does not parse "description"
// - GroupCreate does not return topicName
```

### UI Entry Point

```dart
// lib/features/orbit/presentation/screens/orbit_wired.dart
// lib/features/groups/presentation/screens/create_group_picker_wired.dart

void _onCreateGroup(GroupType type) {
  final groupRepository = widget.groupRepository;
  final groupMessageRepository = widget.groupMessageRepository;
  final groupMessageListener = widget.groupMessageListener;
  if (groupRepository == null ||
      groupMessageRepository == null ||
      groupMessageListener == null) {
    return;
  }

  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => CreateGroupPickerWired(
        groupType: type, // discussion route passes GroupType.chat
        groupRepo: groupRepository,
        msgRepo: groupMessageRepository,
        groupMessageListener: groupMessageListener,
        contactRepo: widget.contactRepo,
        bridge: widget.bridge,
        identityRepo: widget.identityRepo,
        p2pService: widget.p2pService,
      ),
    ),
  );
}

Future<void> _onStartGroup(String? name) async {
  final identity = await widget.identityRepo.loadIdentity();
  if (identity == null) throw StateError('No identity found');

  final selectedContacts = _contacts
      .where((c) => _selectedPeerIds.contains(c.peerId))
      .toList();

  final result = await createGroupWithMembers(
    bridge: widget.bridge,
    groupRepo: widget.groupRepo,
    p2pService: widget.p2pService,
    identity: identity,
    selectedContacts: selectedContacts,
    type: widget.groupType,
    name: name,
  );

  Navigator.of(context).pushReplacement(
    MaterialPageRoute(
      builder: (_) => GroupConversationWired(
        group: result.group,
        groupRepo: widget.groupRepo,
        msgRepo: widget.msgRepo,
        groupMessageListener: widget.groupMessageListener,
        bridge: widget.bridge,
        identityRepo: widget.identityRepo,
        contactRepo: widget.contactRepo,
        p2pService: widget.p2pService,
      ),
    ),
    result: FeedRouteChanges(changedGroupIds: {result.group.id}),
  );
}

// Discussion creation enters through Orbit -> CreateGroupPickerWired.
```
