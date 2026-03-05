## Level 4: Code Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              CODE DIAGRAM                                    │
└─────────────────────────────────────────────────────────────────────────────┘


┌─────────────────────────────────────────────────────────────────────────────┐
│                              FLUTTER CLASSES                                 │
├─────────────────────────────────────────────────────────────────────────────┤

  ── Bridge Layer ─────────────────────────────────────────────────────────

  ┌─────────────────────────────────────┐
  │         <<abstract>>                │
  │         Bridge                      │
  ├─────────────────────────────────────┤
  │ + send(message: String): String     │
  │ + initialize(): Future<void>        │
  │ + checkHealth(): Future<bool>       │
  │ + reinitialize(): Future<void>      │
  │ + dispose(): Future<void>           │
  │ + onMessageReceived: callback?      │
  │ + onPeerConnected: callback?        │
  │ + onPeerDisconnected: callback?     │
  │ + onAddressesUpdated: callback?     │
  │   (listenAddrs, circuitAddrs)       │
  │ + onGroupMessageReceived: callback? │
  │   (Map<String, dynamic>)            │
  └──────────────────┬──────────────────┘
                     │
                     │ implements
                     ▼
  ┌─────────────────────────────────────┐
  │         GoBridgeClient              │
  ├─────────────────────────────────────┤
  │ - _methodChannel: MethodChannel     │
  │ - _eventChannel: EventChannel       │
  │ - _initialized: bool                │
  │ - _cmdMap: Map<String, _CmdSpec>     │
  │   (cmd→MethodChannel method map)    │
  ├─────────────────────────────────────┤
  │ + initialize(): Future<void>        │
  │ + send(message: String): String     │
  │   (maps cmd strings to MethodChan   │
  │    method names, JSON encode/decode │
  │    via MethodChannel)               │
  │ + checkHealth(): Future<bool>       │
  │   (sends node:status, 5s timeout)   │
  │ + reinitialize(): Future<void>      │
  │   (re-initializes Go bridge,        │
  │    preserves callback references)   │
  │ + dispose(): Future<void>           │
  │ + onMessageReceived(callback)       │
  │ + onPeerConnected(callback)         │
  │ + onPeerDisconnected(callback)      │
  │ - _handleEvent(Map): void           │
  │   (routes EventChannel push events) │
  └─────────────────────────────────────┘


  ── Identity Domain ──────────────────────────────────────────────────────

  ┌─────────────────────────────────────┐
  │         IdentityModel               │
  ├─────────────────────────────────────┤
  │ + peerId: String                    │
  │ + publicKey: String                 │
  │ + privateKey: String?               │
  │ + mnemonic12: String?               │
  │ + username: String                  │
  │ + avatarBlob: Uint8List?            │
  │ + createdAt: String                 │
  │ + updatedAt: String                 │
  │ + mlKemPublicKey: String?           │
  │ + mlKemSecretKey: String?           │
  │ + avatarVersion: int?               │
  ├─────────────────────────────────────┤
  │ + fromJson(Map): IdentityModel      │
  │ + toJson(): Map                     │
  └─────────────────────────────────────┘

  ┌─────────────────────────────────────┐
  │         <<abstract>>                │
  │         IdentityRepository          │
  ├─────────────────────────────────────┤
  │ + loadIdentity(): IdentityModel?    │
  │ + saveIdentity(IdentityModel): void │
  └──────────────────┬──────────────────┘
                     │ implements
                     ▼
  ┌─────────────────────────────────────┐
  │       IdentityRepositoryImpl        │
  ├─────────────────────────────────────┤
  │ - dbLoadIdentityRow: Function       │
  │ - dbUpsertIdentityRow: Function     │
  │ - secureKeyStore: SecureKeyStore    │
  ├─────────────────────────────────────┤
  │ + loadIdentity(): IdentityModel?    │
  │   (reads secrets from SecureKeyStore│
  │    falls back to DB for pre-migr.)  │
  │ + saveIdentity(IdentityModel): void │
  │   (writes secrets ONLY to secure    │
  │    storage, DB columns set to null) │
  └─────────────────────────────────────┘


  ── Contact Domain ───────────────────────────────────────────────────────

  ┌─────────────────────────────────────┐
  │         ContactModel                │
  ├─────────────────────────────────────┤
  │ + peerId: String                    │
  │ + publicKey: String                 │
  │ + rendezvous: String                │
  │ + username: String                  │
  │ + signature: String                 │
  │ + scannedAt: String                 │
  │ + avatarPath: String?               │
  │ + mlKemPublicKey: String?           │
  │ + isArchived: bool (default false)  │
  │ + archivedAt: String?               │
  │ + isBlocked: bool (default false)   │
  │ + blockedAt: String?                │
  │ + avatarVersion: int?               │
  ├─────────────────────────────────────┤
  │ + fromQRPayload(Map): ContactModel  │
  │ + fromMap(Map): ContactModel        │
  │ + toMap(): Map                      │
  │ + copyWith({clearArchivedAt,        │
  │     clearBlockedAt}): ContactModel  │
  └─────────────────────────────────────┘

  ┌─────────────────────────────────────┐
  │         <<abstract>>                │
  │         ContactRepository           │
  ├─────────────────────────────────────┤
  │ + addContact(ContactModel): void    │
  │ + getContact(peerId): ContactModel? │
  │ + getAllContacts(): List<Contact>    │
  │ + deleteContact(peerId): void       │
  │ + contactExists(peerId): bool       │
  │ + getContactCount(): int            │
  │ + archiveContact(peerId): void      │
  │ + unarchiveContact(peerId): void    │
  │ + getActiveContacts(): List<Contact>│
  │ + getArchivedContacts(): List       │
  │ + blockContact(peerId): void        │
  │ + unblockContact(peerId): void      │
  └──────────────────┬──────────────────┘
                     │ implements
                     ▼
  ┌─────────────────────────────────────┐
  │       ContactRepositoryImpl         │
  ├─────────────────────────────────────┤
  │ - dbLoadAllContacts: Function       │
  │ - dbLoadContact: Function           │
  │ - dbUpsertContact: Function         │
  │ - dbDeleteContact: Function         │
  │ - dbGetContactCount: Function       │
  │ - dbContactExists: Function         │
  │ - dbArchiveContact: Function        │
  │ - dbUnarchiveContact: Function      │
  │ - dbLoadActiveContacts: Function    │
  │ - dbLoadArchivedContacts: Function  │
  │ - dbBlockContact: Function          │
  │ - dbUnblockContact: Function        │
  └─────────────────────────────────────┘


  ── Contact Request Domain ───────────────────────────────────────────────

  ┌─────────────────────────────────────┐
  │       ContactRequestModel           │
  ├─────────────────────────────────────┤
  │ + peerId: String                    │
  │ + publicKey: String                 │
  │ + rendezvous: String                │
  │ + username: String                  │
  │ + signature: String                 │
  │ + receivedAt: String                │
  │ + status: ContactRequestStatus      │
  │ + mlKemPublicKey: String?           │
  ├─────────────────────────────────────┤
  │ + fromP2PPayload(Map): Model        │
  │ + fromMap(Map): Model               │
  │ + toMap(): Map                      │
  │ + toContactModel(): ContactModel    │
  │ + copyWith(): Model                 │
  └─────────────────────────────────────┘

  ┌─────────────────────────────────────┐
  │         <<abstract>>                │
  │       ContactRequestRepository      │
  ├─────────────────────────────────────┤
  │ + addRequest(Model): void           │
  │ + getRequest(peerId): Model?        │
  │ + getPendingRequests(): List<Model>  │
  │ + updateStatus(peerId, status): void│
  │ + deleteRequest(peerId): void       │
  │ + requestExists(peerId): bool       │
  └──────────────────┬──────────────────┘
                     │ implements
                     ▼
  ┌─────────────────────────────────────┐
  │   ContactRequestRepositoryImpl      │
  ├─────────────────────────────────────┤
  │ - dbLoadPendingRequests: Function   │
  │ - dbLoadRequest: Function           │
  │ - dbUpsertRequest: Function         │
  │ - dbUpdateRequestStatus: Function   │
  │ - dbDeleteRequest: Function         │
  │ - dbRequestExists: Function         │
  └─────────────────────────────────────┘


  ── Group Domain ───────────────────────────────────────────────────────

  ┌─────────────────────────────────────┐        ┌─────────────────────────┐
  │         <<enum>>                    │        │      <<enum>>           │
  │         GroupType                   │        │      GroupRole          │
  ├─────────────────────────────────────┤        ├─────────────────────────┤
  │ + chat                             │        │ + admin                 │
  │ + announcement                     │        │ + member                │
  │ + qa                               │        └─────────────────────────┘
  ├─────────────────────────────────────┤
  │ + toValue(): String                │        ┌─────────────────────────┐
  │ + fromValue(String): GroupType     │        │      <<enum>>           │
  └─────────────────────────────────────┘        │      MemberRole        │
                                                 ├─────────────────────────┤
                                                 │ + admin                 │
                                                 │ + writer                │
                                                 │ + reader                │
                                                 ├─────────────────────────┤
                                                 │ + toValue(): String     │
                                                 │ + fromValue(String)     │
                                                 └─────────────────────────┘

  ┌─────────────────────────────────────┐
  │         GroupModel                  │
  ├─────────────────────────────────────┤
  │ + id: String                       │
  │ + name: String                     │
  │ + type: GroupType                  │
  │ + topicName: String                │
  │ + description: String?             │
  │ + createdAt: DateTime              │
  │ + createdBy: String                │
  │ + myRole: GroupRole                │
  │ + isArchived: bool (default false) │
  │ + archivedAt: DateTime?            │
  ├─────────────────────────────────────┤
  │ + fromMap(Map): GroupModel         │
  │ + toMap(): Map                     │
  │ + copyWith(): GroupModel           │
  └─────────────────────────────────────┘

  ┌─────────────────────────────────────┐
  │         GroupMember                 │
  ├─────────────────────────────────────┤
  │ + groupId: String                  │
  │ + peerId: String                   │
  │ + username: String?                │
  │ + role: MemberRole                 │
  │ + publicKey: String?               │
  │ + mlKemPublicKey: String?          │
  │ + joinedAt: DateTime               │
  ├─────────────────────────────────────┤
  │ + fromMap(Map): GroupMember        │
  │ + toMap(): Map                     │
  └─────────────────────────────────────┘

  ┌─────────────────────────────────────┐
  │         GroupKeyInfo                │
  ├─────────────────────────────────────┤
  │ + groupId: String                  │
  │ + keyGeneration: int               │
  │ + encryptedKey: String             │
  │ + createdAt: DateTime              │
  ├─────────────────────────────────────┤
  │ + fromMap(Map): GroupKeyInfo       │
  │ + toMap(): Map                     │
  └─────────────────────────────────────┘

  ┌─────────────────────────────────────┐
  │         GroupMessage                │
  ├─────────────────────────────────────┤
  │ + id: String (UUID v4)             │
  │ + groupId: String                  │
  │ + senderPeerId: String             │
  │ + senderUsername: String?           │
  │ + text: String                     │
  │ + timestamp: DateTime              │
  │ + keyGeneration: int (default 0)   │
  │ + status: String                   │
  │   ('sending'|'sent'|'delivered'|   │
  │    'failed')                       │
  │ + isIncoming: bool (default true)  │
  │ + readAt: DateTime?                │
  │ + createdAt: DateTime              │
  ├─────────────────────────────────────┤
  │ + fromMap(Map): GroupMessage       │
  │ + toMap(): Map                     │
  │ + copyWith(): GroupMessage         │
  └─────────────────────────────────────┘

  ┌─────────────────────────────────────┐
  │       GroupMessagePayload          │
  │       (v3 wire format)             │
  ├─────────────────────────────────────┤
  │ + text: String                     │
  │ + timestamp: String                │
  │ + username: String?                │
  │ + extra: Map?                      │
  ├─────────────────────────────────────┤
  │ + fromJson(Map): Payload           │
  │ + toJson(): Map                    │
  └─────────────────────────────────────┘

  ┌─────────────────────────────────────┐
  │       GroupInvitePayload           │
  │       (v1/v2 wire format)          │
  ├─────────────────────────────────────┤
  │ + id: String                       │
  │ + groupId: String                  │
  │ + groupKey: String                 │
  │ + keyEpoch: int                    │
  │ + groupConfig: Map                 │
  │ + senderPeerId: String             │
  │ + senderUsername: String            │
  │ + timestamp: String                │
  ├─────────────────────────────────────┤
  │ + toJson(): String (v1 envelope)   │
  │ + toInnerJson(): String (payload)  │
  │ + fromJson(String): Payload?       │
  │ + fromInnerJson(String): Payload?  │
  │ + buildEncryptedEnvelope(          │
  │ │   senderPeerId, kem,             │
  │ │   ciphertext, nonce): String (v2)│
  │ + parseEncryptedEnvelope(          │
  │ │   json): Map? (v2 detection)     │
  └─────────────────────────────────────┘

  ┌─────────────────────────────────────┐
  │         <<abstract>>                │
  │       GroupRepository              │
  ├─────────────────────────────────────┤
  │ + saveGroup(GroupModel): void      │
  │ + getAllGroups(): List<GroupModel>  │
  │ + getGroup(id): GroupModel?        │
  │ + updateGroup(GroupModel): void    │
  │ + deleteGroup(id): void            │
  │ + getActiveGroups(): List<Group>   │
  │ + archiveGroup(id): void           │
  │ + unarchiveGroup(id): void         │
  │ + saveMember(GroupMember): void    │
  │ + getMembers(groupId): List<Mbr>  │
  │ + getMember(groupId, peerId): Mbr?│
  │ + updateMemberRole(gId, pId, r)   │
  │ + removeMember(groupId, peerId)   │
  │ + removeAllMembers(groupId): void │
  │ + saveKey(GroupKeyInfo): void      │
  │ + getLatestKey(groupId): KeyInfo? │
  │ + getKeyByGeneration(gId, gen)    │
  │ + removeAllKeys(groupId): void    │
  └──────────────────┬──────────────────┘
                     │ implements
                     ▼
  ┌─────────────────────────────────────┐
  │     GroupRepositoryImpl            │
  ├─────────────────────────────────────┤
  │ - dbInsertGroup: Function          │
  │ - dbLoadAllGroups: Function        │
  │ - dbLoadGroup: Function            │
  │ - dbUpdateGroup: Function          │
  │ - dbDeleteGroup: Function          │
  │ - dbLoadActiveGroups: Function     │
  │ - dbArchiveGroup: Function         │
  │ - dbUnarchiveGroup: Function       │
  │ - dbInsertGroupMember: Function    │
  │ - dbLoadAllGroupMembers: Function  │
  │ - dbLoadGroupMember: Function      │
  │ - dbUpdateGroupMemberRole: Function│
  │ - dbDeleteGroupMember: Function    │
  │ - dbDeleteAllGroupMembers: Fn      │
  │ - dbInsertGroupKey: Function       │
  │ - dbLoadLatestGroupKey: Function   │
  │ - dbLoadGroupKeyByGeneration: Fn   │
  │ - dbDeleteAllGroupKeys: Function   │
  └─────────────────────────────────────┘

  ┌─────────────────────────────────────┐
  │         <<abstract>>                │
  │     GroupMessageRepository         │
  ├─────────────────────────────────────┤
  │ + saveMessage(GroupMessage): void  │
  │ + getMessagesPage(groupId,         │
  │ │   {limit, offset}): List<Msg>   │
  │ + getMessage(id): GroupMessage?    │
  │ + getLatestMessage(groupId): Msg? │
  │ + updateMessageStatus(id, s)      │
  │ + getMessageCount(groupId): int   │
  │ + getUnreadCount(groupId): int    │
  │ + getTotalUnreadCount(): int      │
  │ + markAsRead(groupId): void       │
  │ + deleteMessage(id): void          │
  │ + deleteMessagesForGroup(gId): int│
  │ + existsByContent(gId, sender,    │
  │ │   text, timestamp): bool        │
  └──────────────────┬──────────────────┘
                     │ implements
                     ▼
  ┌─────────────────────────────────────┐
  │   GroupMessageRepositoryImpl       │
  ├─────────────────────────────────────┤
  │ - dbInsertGroupMessage: Function   │
  │ - dbLoadGroupMessagesPage: Function│
  │ - dbLoadGroupMessage: Function     │
  │ - dbLoadLatestGroupMessage: Fn     │
  │ - dbUpdateGroupMessageStatus: Fn   │
  │ - dbCountGroupMessages: Function   │
  │ - dbCountUnreadGroupMessages: Fn   │
  │ - dbCountTotalUnreadGroupMsgs: Fn  │
  │ - dbMarkGroupMessagesAsRead: Fn    │
  │ - dbDeleteGroupMessage: Function   │
  │ - dbExistsGroupMessageByContent: Fn│
  │ - dbDeleteGroupMessagesForGroup: Fn│
  └─────────────────────────────────────┘


  ── Group Listeners ────────────────────────────────────────────────────

  ┌─────────────────────────────────────┐
  │     GroupMessageListener           │
  ├─────────────────────────────────────┤
  │ - _groupRepo: GroupRepository      │
  │ - _msgRepo: GroupMessageRepository │
  │ - _bridge: Bridge?                 │
  │ - _getSelfPeerId: () => String?   │
  │ - _mediaAttachmentRepo: Repo?     │
  │ - _mediaFileManager: Manager?     │
  │ - _notificationService: NS?       │
  │ - _groupConversationTracker: Trk? │
  │ - _getAppLifecycleState: Fn?      │
  │ - _subscription: StreamSubscription│
  │ - _messageController: StreamCtrl  │
  │ - _removedController: StreamCtrl  │
  ├─────────────────────────────────────┤
  │ + groupMessageStream: Stream<Msg> │
  │ + groupRemovedStream: Stream<Str> │
  │ + start(Stream<Map>): void        │
  │ + stop(): void                     │
  │ + dispose(): void                  │
  │ - _handleMessage(Map): void       │
  │   (routes system msgs vs regular) │
  │ - _handleSystemMessage(): void    │
  │   (member_added/removed/key_rot.) │
  │ - _handleMemberAdded(): void      │
  │ - _handleMembersAdded(): void     │
  │ - _handleMemberRemoved(): void    │
  │   (if self → leaveGroup + emit)   │
  │ - _autoDownloadMedia(Msg): void   │
  └─────────────────────────────────────┘

  ┌─────────────────────────────────────┐
  │     GroupInviteListener            │
  ├─────────────────────────────────────┤
  │ + groupInviteStream: Stream<Chat> │
  │ + groupRepo: GroupRepository       │
  │ + contactRepo: ContactRepository   │
  │ + bridge: Bridge                   │
  │ + getOwnMlKemSecretKey: () => Str?│
  │ + msgRepo: GroupMessageRepository? │
  │ - _subscription: StreamSubscription│
  │ - _groupJoinedController: StrmCtrl│
  ├─────────────────────────────────────┤
  │ + groupJoinedStream: Stream<Group>│
  │ + start(): void                    │
  │ + stop(): void                     │
  │ + dispose(): void                  │
  │ - _onMessage(ChatMessage): void   │
  │   (blocked check → handle invite  │
  │    → drain group inbox → emit)    │
  │ - _drainGroupInbox(groupId): void │
  └─────────────────────────────────────┘

  ┌─────────────────────────────────────┐
  │     GroupKeyUpdateListener         │
  ├─────────────────────────────────────┤
  │ - _stream: Stream<ChatMessage>    │
  │ - _groupRepo: GroupRepository      │
  │ - _bridge: Bridge                  │
  │ - _getOwnMlKemSecretKey: Fn       │
  │ - _subscription: StreamSubscription│
  ├─────────────────────────────────────┤
  │ + start(): void                    │
  │ + stop(): void                     │
  │ + dispose(): void                  │
  │ - _handleMessage(ChatMessage)     │
  │   (decrypt → save key → updateKey)│
  └─────────────────────────────────────┘


  ── P2P Domain ───────────────────────────────────────────────────────────

  ┌─────────────────────────────────────┐
  │         NodeState                   │
  ├─────────────────────────────────────┤
  │ + peerId: String?                   │
  │ + isStarted: bool                   │
  │ + listenAddresses: List<String>     │
  │ + circuitAddresses: List<String>    │
  │ + connections: List<ConnectionState>│
  │ + registeredNamespaces: List<String>│
  ├─────────────────────────────────────┤
  │ + fromJson(Map): NodeState          │
  │ + toJson(): Map                     │
  │ + copyWith(): NodeState             │
  │ + static stopped: NodeState         │
  └─────────────────────────────────────┘

  ┌─────────────────────────────────────┐
  │         ConnectionState             │
  ├─────────────────────────────────────┤
  │ + peerId: String                    │
  │ + multiaddrs: List<String>          │
  │ + direction: String                 │
  │ + status: String                    │
  │ + connectedAt: String?              │
  ├─────────────────────────────────────┤
  │ + fromJson(Map): ConnectionState    │
  │ + toJson(): Map                     │
  │ + copyWith(): ConnectionState       │
  └─────────────────────────────────────┘

  ┌─────────────────────────────────────┐
  │         DiscoveredPeer              │
  ├─────────────────────────────────────┤
  │ + id: String                        │
  │ + addresses: List<String>           │
  ├─────────────────────────────────────┤
  │ + fromJson(Map): DiscoveredPeer     │
  │ + toJson(): Map                     │
  └─────────────────────────────────────┘

  ┌─────────────────────────────────────┐
  │         ChatMessage                 │
  ├─────────────────────────────────────┤
  │ + from: String                      │
  │ + to: String                        │
  │ + content: String                   │
  │ + timestamp: String                 │
  │ + isIncoming: bool                  │
  │ + transport: String?                │
  ├─────────────────────────────────────┤
  │ + fromJson(Map): ChatMessage        │
  │ + toJson(): Map                     │
  │ + copyWith(): ChatMessage           │
  └─────────────────────────────────────┘


  ── P2P Service ──────────────────────────────────────────────────────────

  ┌─────────────────────────────────────┐
  │         <<abstract>>                │
  │         P2PService                  │
  ├─────────────────────────────────────┤
  │ + currentState: NodeState           │
  │ + stateStream: Stream<NodeState>    │
  │ + messageStream: Stream<ChatMessage>│
  ├─────────────────────────────────────┤
  │ + startNode(privKey, peerId): bool  │
  │ + stopNode(): bool                  │
  │ + sendMessage(peerId, msg): bool    │
  │ + discoverPeer(peerId): Discovered? │
  │ + dialPeer(peerId, {addrs}): bool   │
  │ + storeInInbox(peerId, msg): bool  │
  │ + retrieveInbox(): List<Map>       │
  │ + registerPushToken(token, platform): bool │
  │ + sendMessageWithReply(peerId, msg): Map │
  │ + performImmediateHealthCheck(): void │
  │ + drainOfflineInbox(): void          │
  │ + startNodeCore(privKey, peerId)     │
  │ + warmBackground(): void             │
  │ + isLocalPeer(peerId): bool          │
  │ + sendLocalMessage(peerId, msg): bool│
  │ + dispose(): void                   │
  └──────────────────┬──────────────────┘
                     │ implements
                     ▼
  ┌─────────────────────────────────────┐
  │       P2PServiceImpl                │
  ├─────────────────────────────────────┤
  │ - _bridge: Bridge                   │
  │ - _localP2P: LocalP2PService?       │
  │ - _stateController: StreamController│
  │ - _messageController: StreamCtrl    │
  │ - _currentState: NodeState          │
  │ - _isStarting: bool                 │
  ├─────────────────────────────────────┤
  │ + startNode(privKey, peerId): bool  │
  │ + startNodeCore(privKey, peerId)    │
  │ + warmBackground(): void            │
  │ + stopNode(): bool                  │
  │ + sendMessage(peerId, msg): bool    │
  │ + sendMessageWithReply(peerId, msg) │
  │   (bidirectional chat with ACK)     │
  │ + discoverPeer(peerId): Discovered? │
  │ + dialPeer(peerId, {addrs}): bool   │
  │ + storeInInbox(peerId, msg): bool  │
  │ + retrieveInbox(): List<Map>       │
  │ + registerPushToken(token, plat.)   │
  │   (caches token/platform for        │
  │    recovery after relay reconnect)  │
  │ + performImmediateHealthCheck(): void │
  │   (public wrapper → _performHealthCheck) │
  │ + drainOfflineInbox(): void          │
  │   (public wrapper → _drainOfflineInbox)  │
  │ + isLocalPeer(peerId): bool         │
  │ + sendLocalMessage(peerId, msg)     │
  │ + dispose(): void                   │
  │ - _onMessageReceived(Map)           │
  │ - _onPeerConnected(Map)             │
  │ - _onPeerDisconnected(Map)          │
  │ - _performHealthCheck(): void      │
  │   (periodic 30s, detects degraded   │
  │    relay, auto-dials, re-registers) │
  │ - _drainOfflineInbox(): void       │
  └─────────────────────────────────────┘


  ── Contact Request Listener ─────────────────────────────────────────────

  ┌─────────────────────────────────────┐
  │     ContactRequestListener          │
  ├─────────────────────────────────────┤
  │ - p2pService: P2PService            │
  │ - requestRepo: ContactRequestRepo   │
  │ - contactRepo: ContactRepository    │
  │ - bridge: Bridge                    │
  │ - getOwnPeerId: () => String       │
  │ - _subscription: StreamSubscription │
  │ - _requestController: StreamCtrl    │
  ├─────────────────────────────────────┤
  │ + requestStream: Stream<Model>      │
  │ + start(): void                     │
  │ + stop(): void                      │
  │ + dispose(): void                   │
  │ - _onMessage(ChatMessage): void     │
  └─────────────────────────────────────┘


  ── First Time Experience ────────────────────────────────────────────────

  ┌─────────────────────────────────────┐
  │    FirstTimeExperienceWired         │
  ├─────────────────────────────────────┤
  │ + repository: IdentityRepository    │
  │ + contactRepository: ContactRepo    │
  │ + contactRequestRepository: CRRepo  │
  │ + contactRequestListener: Listener  │
  │ + bridge: Bridge                    │
  │ + p2pService: P2PService            │
  ├─────────────────────────────────────┤
  │ - _qrData: String?                  │
  │ - _username: String                 │
  │ - _avatarBlob: Uint8List?           │
  │ - _identity: IdentityModel?         │
  │ - _requestSubscription: StreamSub   │
  ├─────────────────────────────────────┤
  │ + _loadIdentityAndBuildQR()         │
  │ + _buildQRPayload()                 │
  │ + _onUsernameChanged(String)        │
  │ + _onCameraPressed()                │
  │ + _onScanPressed()                  │
  │ + _startListeningForContactRequests │
  │ + _onContactRequest(Model)          │
  │ + _acceptRequest(ctx, Model)        │
  │ + _declineRequest(ctx, Model)       │
  └─────────────────────────────────────┘


  ── Feed ───────────────────────────────────────────────────────────

  ┌─────────────────────────────────────┐
  │         <<enum>>                    │
  │         FeedItemType                │
  ├─────────────────────────────────────┤
  │ + connection                        │
  │ + message                           │
  │ + thread                            │
  │ + groupThread                       │
  └─────────────────────────────────────┘

  ┌─────────────────────────────────────┐
  │         <<enum>>                    │
  │       ConversationState             │
  ├─────────────────────────────────────┤
  │ + unread                            │
  │ + active                            │
  │ + replied                           │
  │ + read                              │
  └─────────────────────────────────────┘

  ┌─────────────────────────────────────┐
  │         <<abstract>>                │
  │         FeedItem                    │
  ├─────────────────────────────────────┤
  │ + id: String                        │
  │ + timestamp: DateTime               │
  │ + type: FeedItemType                │
  └──────────────────┬──────────────────┘
                     │ extends
                     ▼
  ┌─────────────────────────────────────┐
  │       ConnectionFeedItem            │
  ├─────────────────────────────────────┤
  │ + contactPeerId: String             │
  │ + contactUsername: String            │
  │ + contactAvatarPath: String?        │
  ├─────────────────────────────────────┤
  │ + fromContact(ContactModel): Self   │
  └─────────────────────────────────────┘

  ┌─────────────────────────────────────┐
  │       MessageFeedItem               │
  ├─────────────────────────────────────┤
  │ + contactPeerId: String             │
  │ + contactUsername: String            │
  │ + messageId: String                 │
  │ + messageText: String               │
  │ + messageTime: String               │
  │ + unreadCount: int                  │
  └─────────────────────────────────────┘

  ┌─────────────────────────────────────┐
  │       ThreadFeedItem                │
  │   (extends CardThreadFeedItem)      │
  ├─────────────────────────────────────┤
  │ + contactPeerId: String             │
  │ + contactUsername: String            │
  │ + messages: List<ThreadMessage>     │
  │ + unreadCount: int                  │
  │ + conversationState: ConvState      │
  │ + isUnreadCard: bool                │
  ├─────────────────────────────────────┤
  │ + isMultiMessage: bool (getter)     │
  │ + latestMessage: ThreadMessage      │
  │ + additionalCount: int (getter)     │
  │ + displayName: String (getter)      │
  │ + displayId: String (getter)        │
  └─────────────────────────────────────┘

  ┌─────────────────────────────────────┐
  │       ThreadMessage                 │
  ├─────────────────────────────────────┤
  │ + id: String                        │
  │ + text: String                      │
  │ + time: String                      │
  │ + timestamp: DateTime               │
  │ + isUnread: bool                    │
  │ + isIncoming: bool (default true)   │
  │ + status: String?                   │
  │ + quotedMessageId: String?          │
  │ + media: List<MediaAttachment>      │
  │ + senderUsername: String?            │
  │ + senderPeerId: String?             │
  └─────────────────────────────────────┘

  ┌─────────────────────────────────────┐
  │       <<abstract>>                  │
  │       CardThreadFeedItem            │
  │       (extends FeedItem)            │
  ├─────────────────────────────────────┤
  │ + messages: List<ThreadMessage>     │
  │ + unreadCount: int                  │
  │ + conversationState: ConvState      │
  │ + displayName: String (abstract)    │
  │ + displayId: String (abstract)      │
  │ + static maxPreview: int = 3        │
  └──────────────────┬──────────────────┘
                     │ extends
          ┌──────────┴──────────┐
          ▼                     ▼
  ┌────────────────────┐ ┌──────────────────────┐
  │ ThreadFeedItem     │ │ GroupThreadFeedItem   │
  │ (1:1 conversation) │ │ (group conversation)  │
  ├────────────────────┤ ├──────────────────────┤
  │ + contactPeerId    │ │ + groupId: String     │
  │ + contactUsername   │ │ + groupName: String   │
  │ + messages         │ │ + groupType: GroupType│
  │ + unreadCount      │ │ + messages            │
  │ + conversationState│ │ + unreadCount         │
  │ + isUnreadCard     │ │ + conversationState   │
  └────────────────────┘ └──────────────────────┘

  ┌─────────────────────────────────────┐
  │    FeedWired                        │
  ├─────────────────────────────────────┤
  │ + repository: IdentityRepository    │
  │ + contactRepository: ContactRepo    │
  │ + contactRequestRepository: CRRepo  │
  │ + contactRequestListener: Listener  │
  │ + messageRepository: MessageRepo    │
  │ + bridge: Bridge                    │
  │ + p2pService: P2PService            │
  │ + initialContact: ContactModel      │
  ├─────────────────────────────────────┤
  │ - _identity: IdentityModel?         │
  │ - _feedItems: List<FeedItem>        │
  │ - _totalUnreadCount: int            │
  │ - _requestSubscription: StreamSub   │
  ├─────────────────────────────────────┤
  │ + _loadIdentity()                   │
  │ + _buildInitialFeed()               │
  │ + _startListeningForContactRequests │
  │ + _onContactRequest(Model)          │
  │ + _acceptRequest(ctx, Model)        │
  │ + _declineRequest(ctx, Model)       │
  │ + _onSwitchView('orbit')            │
  │     → Navigator.push(OrbitWired)    │
  └─────────────────────────────────────┘


  ── Orbit Domain ───────────────────────────────────────────────────────

  ┌─────────────────────────────────────┐
  │       OrbitFriend                   │
  ├─────────────────────────────────────┤
  │ + contact: ContactModel             │
  │ + messageCount: int                 │
  │ + lastActivity: String              │
  │ + lastMessageTimestamp: DateTime?   │
  │ + unreadCount: int (default 0)     │
  └─────────────────────────────────────┘

  ┌─────────────────────────────────────┐
  │       OrbitGroup                   │
  ├─────────────────────────────────────┤
  │ + group: GroupModel                │
  │ + latestMessage: String?           │
  │ + unreadCount: int (default 0)    │
  │ + lastActivityTimestamp: DateTime? │
  ├─────────────────────────────────────┤
  │ + groupId: String (getter)         │
  │ + name: String (getter)            │
  │ + type: GroupType (getter)         │
  └─────────────────────────────────────┘

  ┌─────────────────────────────────────┐
  │    OrbitWired                        │
  ├─────────────────────────────────────┤
  │ + contactRepository: ContactRepo    │
  │ + messageRepository: MessageRepo    │
  │ + chatMessageListener: Listener     │
  │ + contactRequestListener: Listener  │
  │ + identityRepository: IdentityRepo  │
  │ + p2pService: P2PService            │
  │ + bridge: Bridge                    │
  │ + contactRequestRepository: CRRepo  │
  ├─────────────────────────────────────┤
  │ - _orbitFriends: List<OrbitFriend>  │
  │ - _filteredFriends: List<OrbitFriend>│
  │ - _identity: IdentityModel?         │
  │ - _collapseController: AnimCtrl     │
  │   (580ms)                           │
  │ - _searchDockController: AnimCtrl   │
  │   (560ms)                           │
  │ - _searchTriggerController: AnimCtrl│
  │   (340ms)                           │
  │ - _isSearchActive: bool             │
  │ - _searchQuery: String              │
  ├─────────────────────────────────────┤
  │ + _loadOrbitData()                  │
  │ + _onSearch(String)                 │
  │ + _onFriendTap(OrbitFriend)         │
  │     → Navigator.push(ConvWired)     │
  │ + _onClose()                        │
  │     → Navigator.pop()              │
  └─────────────────────────────────────┘


  ── Conversation Domain ─────────────────────────────────────────────────

  ┌─────────────────────────────────────┐
  │       ConversationMessage           │
  ├─────────────────────────────────────┤
  │ + id: String (UUID)                 │
  │ + contactPeerId: String             │
  │ + senderPeerId: String              │
  │ + text: String                      │
  │ + timestamp: String                 │
  │ + status: String                    │
  │   ('sending'|'sent'|'delivered'|    │
  │    'queued'|'failed')              │
  │ + isIncoming: bool                  │
  │ + createdAt: String                 │
  │ + readAt: String?                   │
  │ + quotedMessageId: String?          │
  │ + media: List<MediaAttachment>      │
  │ + transport: String?                │
  │ + wireEnvelope: String?             │
  ├─────────────────────────────────────┤
  │ + fromMap(Map): ConversationMessage │
  │ + toMap(): Map                      │
  │ + copyWith(): ConversationMessage   │
  └─────────────────────────────────────┘

  ┌─────────────────────────────────────┐
  │       MessagePayload                │
  ├─────────────────────────────────────┤
  │ + id: String                        │
  │ + text: String                      │
  │ + senderPeerId: String              │
  │ + senderUsername: String             │
  │ + timestamp: String                 │
  ├─────────────────────────────────────┤
  │ + fromJson(String): MessagePayload? │
  │ + toJson(): String (v1 envelope)    │
  │ + toInnerJson(): String (payload)   │
  │ + toConversationMessage(): Model    │
  │ + buildEncryptedEnvelope(           │
  │ │   kem, ciphertext, nonce,         │
  │ │   senderPeerId): String (v2)      │
  │ + parseEncryptedEnvelope(           │
  │ │   json): Map? (v2 detection)      │
  │ + fromDecryptedJson(                │
  │ │   json): MessagePayload?          │
  └─────────────────────────────────────┘

  ┌─────────────────────────────────────┐
  │         <<abstract>>                │
  │       MessageRepository             │
  ├─────────────────────────────────────┤
  │ + saveMessage(Model): void          │
  │ + getMessagesForContact(id): List   │
  │ + getLatestMessageForContact(): Msg?│
  │ + updateMessageStatus(id, s): void  │
  │ + messageExists(id): bool           │
  │ + getMessageCountForContact(        │
  │ │   contactPeerId): Future<int>     │
  │ + markConversationAsRead(           │
  │ │   contactPeerId): Future<int>     │
  │ + getUnreadCountForContact(         │
  │ │   contactPeerId): Future<int>     │
  │ + getTotalUnreadCount(): Future<int>│
  │ + getTotalUnreadCountExcluding     │
  │ │   Archived(): Future<int>        │
  │ + deleteMessagesForContact(        │
  │ │   peerId): Future<void>          │
  │ + getFailedOutgoingMessages():     │
  │ │   Future<List<ConversationMsg>>  │
  │ + getMessagesPage(contactPeerId,   │
  │ │   {limit, beforeTimestamp}):      │
  │ │   Future<List<ConversationMsg>>  │
  │ + getUnackedOutgoingMessages():    │
  │ │   Future<List<ConversationMsg>>  │
  └──────────────────┬──────────────────┘
                     │ implements
                     ▼
  ┌─────────────────────────────────────┐
  │     MessageRepositoryImpl           │
  ├─────────────────────────────────────┤
  │ - dbInsertMessage: Function         │
  │ - dbLoadMessagesForContact: Function│
  │ - dbLoadLatestMessageForContact: Fn │
  │ - dbUpdateMessageStatus: Function   │
  │ - dbLoadMessage: Function           │
  │ - dbCountMessagesForContact: Fn     │
  │ - dbMarkConversationAsRead: Function│
  │ - dbCountUnreadForContact: Function │
  │ - dbCountTotalUnread: Function      │
  │ - dbCountTotalUnreadExcluding      │
  │     Archived: Function              │
  │ - dbDeleteMessagesForContact: Fn    │
  │ - dbLoadFailedOutgoingMessages: Fn  │
  │ - dbLoadMessagesPage: Function      │
  └─────────────────────────────────────┘


  ── Media Attachment Domain ──────────────────────────────────────────────

  ┌─────────────────────────────────────┐
  │       MediaAttachment               │
  ├─────────────────────────────────────┤
  │ + id: String                        │
  │ + messageId: String                 │
  │ + mime: String                      │
  │ + size: int                         │
  │ + mediaType: MediaType              │
  │ + width: int?                       │
  │ + height: int?                      │
  │ + durationMs: int?                  │
  │ + localPath: String?                │
  │ + downloadStatus: DownloadStatus    │
  │ + createdAt: String                 │
  │ + waveform: String?                 │
  ├─────────────────────────────────────┤
  │ + fromMap(Map): MediaAttachment     │
  │ + toMap(): Map                      │
  └─────────────────────────────────────┘

  ┌─────────────────────────────────────┐
  │         <<abstract>>                │
  │     MediaAttachmentRepository       │
  ├─────────────────────────────────────┤
  │ + saveAttachment(Model): void       │
  │ + getAttachmentsForMessage(): List  │
  │ + getAttachmentsForMessages(): Map  │
  │ + updateLocalPath(id, path): void   │
  │ + updateDownloadStatus(): void      │
  │ + deleteForMessage(id): void        │
  │ + deleteForContact(peerId): void    │
  │ + getPendingDownloads(): List       │
  └──────────────────┬──────────────────┘
                     │ implements
                     ▼
  ┌─────────────────────────────────────┐
  │   MediaAttachmentRepositoryImpl     │
  ├─────────────────────────────────────┤
  │ - dbSaveAttachment: Function        │
  │ - dbLoadAttachments: Function       │
  │ - dbLoadAttachmentsForMsgs: Fn      │
  │ - dbUpdateLocalPath: Function       │
  │ - dbUpdateDownloadStatus: Fn        │
  │ - dbDeleteForMessage: Function      │
  │ - dbDeleteForContact: Function      │
  │ - dbLoadPendingDownloads: Function  │
  └─────────────────────────────────────┘


  ── Conversation Services ──────────────────────────────────────────────

  ┌─────────────────────────────────────┐
  │     ChatMessageListener             │
  ├─────────────────────────────────────┤
  │ - chatMessageStream: Stream         │
  │ - messageRepo: MessageRepository    │
  │ - contactRepo: ContactRepository    │
  │ - bridge: Bridge?                   │
  │ - getOwnMlKemSecretKey: Fn?        │
  │ - _subscription: StreamSubscription │
  │ - _messageController: StreamCtrl    │
  │ - _contactUpdatedController: Ctrl   │
  ├─────────────────────────────────────┤
  │ + incomingMessageStream: Stream     │
  │ + contactUpdatedStream: Stream      │
  │ + start(): void                     │
  │ + stop(): void                      │
  │ + dispose(): void                   │
  │ - _onMessage(ChatMessage): void     │
  └─────────────────────────────────────┘


  ── Incoming Message Router ────────────────────────────────────────────

  ┌─────────────────────────────────────┐
  │     IncomingMessageRouter           │
  ├─────────────────────────────────────┤
  │ - p2pService: P2PService            │
  │ - _subscription: StreamSubscription │
  │ - _contactRequestCtrl: StreamCtrl   │
  │ - _chatMessageCtrl: StreamCtrl      │
  │ - _unknownCtrl: StreamCtrl          │
  ├─────────────────────────────────────┤
  │ + contactRequestStream: Stream      │
  │ + chatMessageStream: Stream         │
  │ + unknownMessageStream: Stream      │
  │ + profileUpdateStream: Stream<ChatMessage> │
  │ + groupInviteStream: Stream<ChatMessage>   │
  │ + groupKeyUpdateStream: Stream<ChatMsg>    │
  │ + start(): void                     │
  │ + stop(): void                      │
  │ + dispose(): void                   │
  │ - _route(ChatMessage): void         │
  └─────────────────────────────────────┘


  ── Ring Avatar System ───────────────────────────────────────────────────

  ┌─────────────────────────────────────┐
  │     RingAvatarGenerator             │
  ├─────────────────────────────────────┤
  │ + generate(peerId, size): Data      │  (static)
  │ + djb2Hash(String): int             │  (static)
  │ - _shuffleColors(hash): List<Color> │
  │ - _generateRingParams(...)          │
  │ - _calculateRingRadii(...)          │
  │ - _generateGlow(hash, size)         │
  └─────────────────────────────────────┘

  ┌──────────────────┐  ┌──────────────────┐  ┌────────────────────┐
  │  RingAvatarData  │  │  RingData        │  │  GlowData          │
  │  rings: List     │  │  radius, stroke  │  │  color, outerR     │
  │  glow: GlowData  │  │  color, opacity  │  │  middleR, innerR   │
  │                  │  │  rotation, dash  │  │                    │
  └──────────────────┘  └──────────────────┘  └────────────────────┘


  ── Enums ────────────────────────────────────────────────────────────────

  ┌─────────────────────────────────────┐        ┌─────────────────────────┐
  │         <<enum>>                    │        │      <<enum>>           │
  │         StartupDecision             │        │  GenerateIdentityResult │
  ├─────────────────────────────────────┤        ├─────────────────────────┤
  │ + hasIdentityWithContacts           │        │ + success               │
  │ + hasIdentityNoContacts             │        │ + coreLibError          │
  │ + needsIdentity                     │        │ + dbError               │
  └─────────────────────────────────────┘        └─────────────────────────┘

  ┌─────────────────────────────────────┐        ┌─────────────────────────┐
  │         <<enum>>                    │        │      <<enum>>           │
  │       RestoreIdentityResult         │        │   BuildQRPayloadResult  │
  ├─────────────────────────────────────┤        ├─────────────────────────┤
  │ + success                           │        │ + success               │
  │ + invalidMnemonicFormat             │        │ + noIdentity            │
  │ + invalidMnemonicCore               │        │ + signingError          │
  │ + coreLibError                      │        └─────────────────────────┘
  │ + dbError                           │
  └─────────────────────────────────────┘

  ┌─────────────────────────────────────┐        ┌─────────────────────────┐
  │         <<enum>>                    │        │      <<enum>>           │
  │         ParseQRResult              │        │   AddContactResult      │
  ├─────────────────────────────────────┤        ├─────────────────────────┤
  │ + success                           │        │ + success               │
  │ + invalidJson                       │        │ + alreadyExists         │
  │ + missingFields                     │        │ + dbError               │
  │ + invalidSignature                  │        └─────────────────────────┘
  │ + expired                           │
  │ + selfScan                          │
  └─────────────────────────────────────┘

  ┌─────────────────────────────────────┐        ┌─────────────────────────┐
  │         <<enum>>                    │        │      <<enum>>           │
  │         StartNodeResult             │        │   StopNodeResult        │
  ├─────────────────────────────────────┤        ├─────────────────────────┤
  │ + success                           │        │ + success               │
  │ + noIdentity                        │        │ + notRunning            │
  │ + bridgeError                       │        │ + error                 │
  │ + connectionError                   │        └─────────────────────────┘
  └─────────────────────────────────────┘

  ┌─────────────────────────────────────┐        ┌─────────────────────────┐
  │       SendMessageResult             │        │      <<enum>>           │
  │       [P2P Model / Class]           │        │  DiscoverPeerResult     │
  ├─────────────────────────────────────┤        ├─────────────────────────┤
  │ + sent: bool                        │        │ + success               │
  │ + acked: bool                       │        │ + nodeNotRunning        │
  │ + reply: String?                    │        │ + notFound              │
  │ + acknowledged: bool (getter)       │        │ + error                 │
  │   (sent && reply != null/empty)     │        │                         │
  └─────────────────────────────────────┘        └─────────────────────────┘

  ┌─────────────────────────────────────┐        ┌─────────────────────────┐
  │         <<enum>>                    │        │      <<enum>>           │
  │    SendContactRequestResult         │        │ AcceptContactReqResult  │
  ├─────────────────────────────────────┤        ├─────────────────────────┤
  │ + success                           │        │ + success               │
  │ + noIdentity                        │        │ + notFound              │
  │ + signingError                      │        │ + notPending            │
  │ + nodeNotRunning                    │        │ + addContactError       │
  │ + peerNotFound                      │        │ + updateStatusError     │
  │ + sendFailed                        │        └─────────────────────────┘
  └─────────────────────────────────────┘

  ┌─────────────────────────────────────┐        ┌─────────────────────────┐
  │         <<enum>>                    │        │      <<enum>>           │
  │   DeclineContactRequestResult       │        │  HandleMessageResult    │
  ├─────────────────────────────────────┤        ├─────────────────────────┤
  │ + success                           │        │ + contactRequest        │
  │ + notFound                          │        │ + duplicateRequest      │
  │ + updateError                       │        │ + alreadyContact        │
  └─────────────────────────────────────┘        │ + regularMessage        │
                                                 │ + invalidMessage        │
  ┌─────────────────────────────────────┐        └─────────────────────────┘
  │         <<enum>>                    │
  │    ContactRequestStatus             │
  ├─────────────────────────────────────┤
  │ + pending                           │
  │ + accepted                          │
  │ + declined                          │
  └─────────────────────────────────────┘

  ┌─────────────────────────────────────┐        ┌─────────────────────────┐
  │         <<enum>>                    │        │      <<enum>>           │
  │    SendChatMessageResult            │        │ HandleChatMessageResult │
  ├─────────────────────────────────────┤        ├─────────────────────────┤
  │ + success                           │        │ + chatMessage           │
  │ + nodeNotRunning                    │        │ + notChatMessage        │
  │ + invalidMessage                    │        │ + unknownSender         │
  │ + peerNotFound                      │        │ + duplicate             │
  │ + dialFailed                        │        └─────────────────────────┘
  │ + sendFailed                        │
  └─────────────────────────────────────┘

  ┌─────────────────────────────────────┐        ┌─────────────────────────┐
  │         <<enum>>                    │        │      <<enum>>           │
  │    SendGroupMessageResult           │        │ HandleGroupInviteResult │
  ├─────────────────────────────────────┤        ├─────────────────────────┤
  │ + success                           │        │ + success               │
  │ + groupNotFound                     │        │ + duplicateGroup        │
  │ + unauthorized                      │        │ + invalidPayload        │
  │ + error                             │        │ + unknownSender         │
  └─────────────────────────────────────┘        │ + decryptionFailed      │
                                                 │ + bridgeError           │
  ┌─────────────────────────────────────┐        └─────────────────────────┘
  │         <<enum>>                    │
  │    SendGroupInviteResult            │        ┌─────────────────────────┐
  ├─────────────────────────────────────┤        │      <<class>>          │
  │ + success                           │        │ CreateGroupWithMembers  │
  │ + nodeNotRunning                    │        │       Result            │
  │ + encryptionRequired                │        ├─────────────────────────┤
  │ + sendFailed                        │        │ + group: GroupModel     │
  └─────────────────────────────────────┘        │ + membersAdded: int     │
                                                 │ + invitesSent: int      │
  ┌─────────────────────────────────────┐        └─────────────────────────┘
  │    BridgeCommandException           │
  ├─────────────────────────────────────┤
  │ + command: String                   │
  │ + errorCode: String                 │
  │ + errorMessage: String?             │
  └─────────────────────────────────────┘

└─────────────────────────────────────────────────────────────────────────────┘


┌─────────────────────────────────────────────────────────────────────────────┐
│                        GO BRIDGE WIRE FORMAT                                 │
├─────────────────────────────────────────────────────────────────────────────┤

  Bridge Request (MethodChannel → Go):
  ┌─────────────────────────────────────┐
  │  MethodChannel invocation           │
  ├─────────────────────────────────────┤
  │ + methodName: string                │
  │   (camelCase, e.g.                 │
  │    "generateIdentity",            │
  │    "startNode", "dialPeer")        │
  │ + argument: string? (JSON payload) │
  └─────────────────────────────────────┘

  Bridge Response (Go → MethodChannel):
  ┌─────────────────────────────────────┐
  │  JSON response string               │
  ├─────────────────────────────────────┤
  │ + ok: boolean                       │
  │ + identity?: IdentityJson           │
  │ + signature?: string                │
  │ + verified?: boolean                │
  │ + publicKey?: string                │
  │ + secretKey?: string                │
  │ + kem?: string                      │
  │ + ciphertext?: string               │
  │ + nonce?: string                    │
  │ + plaintext?: string                │
  │ + peerId?: string                   │
  │ + peers?: []                        │
  │ + messages?: []                     │
  │ + id?: string (media ID)           │
  │ + data?: string (base64 media)     │
  │ + files?: [] (media list)          │
  │ + errorCode?: string                │
  │ + errorMessage?: string             │
  └─────────────────────────────────────┘

  Push Events (Go → EventChannel):
  ┌─────────────────────────────────────┐
  │  JSON event via EventChannel        │
  ├─────────────────────────────────────┤
  │ + event: string                     │
  │   ("message:received" |            │
  │    "peer:connected" |              │
  │    "peer:disconnected" |           │
  │    "addresses:updated" |           │
  │    "group:message" |               │
  │    "group:discovery" |             │
  │    "group:publish_debug")          │
  │ + data: object                      │
  │   (message content or peer info)   │
  └─────────────────────────────────────┘

  Command Name Mapping (Dart cmd → MethodChannel method):
  ┌─────────────────────────────────────┐
  │  GoBridgeClient._cmdMap             │
  │  (cmd → _CmdSpec(methodName, bool)) │
  ├─────────────────────────────────────┤
  │  identity.generate → generateIdent. │
  │  identity.restore  → restoreIdent.  │
  │  payload.sign      → signPayload    │
  │  payload.verify    → verifyPayload  │
  │  mlkem.keygen      → mlKemKeygen    │
  │  message.encrypt   → encryptMessage │
  │  message.decrypt   → decryptMessage │
  │  node:start        → startNode      │
  │  node:stop         → stopNode       │
  │  node:status       → nodeStatus     │
  │  rendezvous:register → rendezvousR. │
  │  rendezvous:discover → rendezvousD. │
  │  peer:dial         → dialPeer       │
  │  peer:disconnect   → disconnectPeer │
  │  message:send      → sendMessage    │
  │  inbox:store       → inboxStore     │
  │  inbox:retrieve    → inboxRetrieve  │
  │  inbox:register_token → inboxReg.T. │
  │  media:upload      → mediaUpload    │
  │  media:download    → mediaDownload  │
  │  media:delete      → mediaDelete    │
  │  media:list        → mediaList      │
  │  profile:upload    → profileUpload  │
  │  profile:download  → profileDownload│
  │  encrypt_contact_request            │
  │    → encryptContactRequest          │
  │  decrypt_contact_request            │
  │    → decryptContactRequest          │
  │  relay:reconnect   → relayReconnect │
  │  relay:probe       → relayProbe     │
  │  group:create      → groupCreate    │
  │  group:join        → groupJoinTopic │
  │  group:leave       → groupLeaveTopic│
  │  group:publish     → groupPublish   │
  │  group:updateConfig→ groupUpdateCfg │
  │  group:rotateKey   → groupRotateKey │
  │  group:updateKey   → groupUpdateKey │
  │  group:inboxStore  → groupInboxStore│
  │  group:inboxRetrieve → groupInboxRt │
  │  group.keygen      → generateGrpKey │
  │  group.encrypt     → groupEncryptMsg│
  │  group.decrypt     → groupDecryptMsg│
  └─────────────────────────────────────┘

└─────────────────────────────────────────────────────────────────────────────┘


┌─────────────────────────────────────────────────────────────────────────────┐
│                       GROUP WIRE FORMAT                                       │
├─────────────────────────────────────────────────────────────────────────────┤

  Group Invite (v1 plaintext):
  ┌─────────────────────────────────────┐
  │ { "type": "group_invite",          │
  │   "version": "1",                  │
  │   "payload": {                     │
  │     "id": "uuid",                  │
  │     "groupId": "uuid",            │
  │     "groupKey": "base64",          │
  │     "keyEpoch": N,                 │
  │     "groupConfig": { ... },        │
  │     "senderPeerId": "...",         │
  │     "senderUsername": "...",        │
  │     "timestamp": "ISO-8601"        │
  │   }                                │
  │ }                                  │
  └─────────────────────────────────────┘

  Group Invite (v2 encrypted):
  ┌─────────────────────────────────────┐
  │ { "type": "group_invite",          │
  │   "version": "2",                  │
  │   "senderPeerId": "...",           │
  │   "encrypted": {                   │
  │     "kem": "base64",              │
  │     "ciphertext": "base64",        │
  │     "nonce": "base64"              │
  │   }                                │
  │ }                                  │
  └─────────────────────────────────────┘

  Group Key Update (v2 encrypted):
  ┌─────────────────────────────────────┐
  │ { "type": "group_key_update",      │
  │   "version": "2",                  │
  │   "encrypted": {                   │
  │     "kem": "base64",              │
  │     "ciphertext": "base64",        │
  │     "nonce": "base64"              │
  │   }                                │
  │ }                                  │
  │                                    │
  │ Decrypted payload:                 │
  │ { "groupId": "uuid",              │
  │   "keyGeneration": N,              │
  │   "encryptedKey": "base64"         │
  │ }                                  │
  └─────────────────────────────────────┘

  Group System Messages (via pubsub):
  ┌─────────────────────────────────────┐
  │ member_added:                      │
  │ { "__sys": "member_added",         │
  │   "member": { peerId, username,    │
  │     role, publicKey, mlKemPK },    │
  │   "groupConfig": { ... }           │
  │ }                                  │
  │                                    │
  │ members_added (batch):             │
  │ { "__sys": "members_added",        │
  │   "members": [ { ... }, ... ],     │
  │   "groupConfig": { ... }           │
  │ }                                  │
  │                                    │
  │ member_removed:                    │
  │ { "__sys": "member_removed",       │
  │   "member": { "peerId": "..." },   │
  │   "groupConfig": { ... }           │
  │ }                                  │
  │                                    │
  │ key_rotated:                       │
  │ { "__sys": "key_rotated",          │
  │   "newKeyEpoch": N                 │
  │ }                                  │
  └─────────────────────────────────────┘

  Group Message (Go pubsub v3 — encrypted + signed by Go internally):
  ┌─────────────────────────────────────┐
  │ Go handles encryption/signing      │
  │ internally in GroupPublish.         │
  │ Dart receives decrypted via        │
  │ bridge.onGroupMessageReceived:     │
  │ { "groupId": "uuid",              │
  │   "senderId": "peerId",            │
  │   "senderUsername": "...",          │
  │   "keyEpoch": N,                   │
  │   "text": "...",                   │
  │   "timestamp": "ISO-8601",         │
  │   "media": [ { ... } ]?           │
  │ }                                  │
  └─────────────────────────────────────┘

└─────────────────────────────────────────────────────────────────────────────┘


┌─────────────────────────────────────────────────────────────────────────────┐
│                            FUNCTION SIGNATURES                               │
├─────────────────────────────────────────────────────────────────────────────┤

  FLUTTER USE CASES - IDENTITY:
  ─────────────────────────────
  decideStartupRoute(
    identityRepo: IdentityRepository,
    contactRepo: ContactRepository
  ): Future<StartupDecision>

  generateNewIdentity(
    callGenerate: () => Future<Map>,
    repo: IdentityRepository
  ): Future<GenerateIdentityResult>

  restoreIdentityFromMnemonic(
    input: String,
    callRestore: (String) => Future<Map>,
    repo: IdentityRepository
  ): Future<RestoreIdentityResult>


  FLUTTER USE CASES - QR CODE:
  ────────────────────────────
  buildQRPayload(
    repo: IdentityRepository,
    callSign: (String, String) => Future<Map>
  ): Future<(BuildQRPayloadResult, String?)>

  parseQRPayload(
    qrString: String,
    bridge: Bridge,
    ownPeerId: String,
    {maxAge: Duration = 24h}
  ): Future<(ParseQRResult, ContactModel?)>

  handleScannedQR(
    qrString: String,
    bridge: Bridge,
    ownPeerId: String,
    contactRepo: ContactRepository,
    identityRepo: IdentityRepository,
    p2pService: P2PService
  ): Future<void>


  FLUTTER USE CASES - P2P:
  ────────────────────────
  startP2PNode(
    identityRepo: IdentityRepository,
    p2pService: P2PService
  ): Future<StartNodeResult>

  stopP2PNode(
    p2pService: P2PService
  ): Future<StopNodeResult>

  sendP2PMessage(
    p2pService: P2PService,
    peerId: String,
    message: String
  ): Future<SendMessageResult>

  discoverP2PPeer(
    p2pService: P2PService,
    peerId: String
  ): Future<(DiscoverPeerResult, DiscoveredPeer?)>

  dialP2PPeer(
    p2pService: P2PService,
    peerId: String,
    {addresses: List<String>?}
  ): Future<bool>


  FLUTTER USE CASES - CONVERSATION:
  ──────────────────────────────────
  sendChatMessage(
    p2pService: P2PService,
    messageRepo: MessageRepository,
    targetPeerId: String,
    text: String,
    senderPeerId: String,
    senderUsername: String,
    {messageId?: String, timestamp?: String,
     bridge?: Bridge,
     recipientMlKemPublicKey?: String}
  ): Future<(SendChatMessageResult, ConversationMessage?)>
  // If bridge + recipientMlKemPublicKey present → encrypt (v2 envelope)
  // Otherwise → plaintext (v1 envelope)
  // On send failure after 3x retry → storeInInbox() fallback

  handleIncomingChatMessage(
    message: ChatMessage,
    messageRepo: MessageRepository,
    contactRepo: ContactRepository,
    {bridge?: Bridge,
     ownMlKemSecretKey?: String}
  ): Future<(HandleChatMessageResult, ConversationMessage?, ContactModel?)>
  // Detects v2 encrypted envelope → decrypts via ML-KEM + AES-256-GCM
  // Falls back to v1 plaintext parsing

  loadConversation(
    messageRepo: MessageRepository,
    contactPeerId: String
  ): Future<List<ConversationMessage>>

  markConversationRead(
    messageRepo: MessageRepository,
    contactPeerId: String
  ): Future<int>

  retryFailedMessages(
    messageRepo: MessageRepository,
    identityRepo: IdentityRepository,
    contactRepo: ContactRepository,
    p2pService: P2PService,
    bridge: Bridge
  ): Future<int>   // Returns count of successfully retried messages

  sendVoiceMessage(
    audioRecorderService: AudioRecorderService,
    p2pService: P2PService,
    messageRepo: MessageRepository,
    mediaAttachmentRepo: MediaAttachmentRepository,
    bridge: Bridge,
    targetPeerId: String,
    senderPeerId: String,
    senderUsername: String
  ): Future<(SendChatMessageResult, ConversationMessage?)>

  retryUnackedMessages(
    messageRepo: MessageRepository,
    p2pService: P2PService
  ): Future<int>   // Returns count of messages re-queued to inbox


  FLUTTER USE CASES - FEED:
  ─────────────────────────
  loadFeed(
    contactRepo: ContactRepository,
    messageRepo: MessageRepository
  ): Future<List<FeedItem>>
  // Also queries unread counts per contact for MessageFeedItems


  FLUTTER USE CASES - ORBIT:
  ──────────────────────────
  loadOrbitData(
    contactRepo: ContactRepository,
    messageRepo: MessageRepository
  ): Future<List<OrbitFriend>>
  // Loads all contacts, queries message count + unread count per contact,
  // sorts by messageCount descending


  FLUTTER USE CASES - PUSH NOTIFICATIONS:
  ────────────────────────────────────────
  requestPushPermission(): Future<bool>

  registerPushToken(
    p2pService: P2PService
  ): Future<void>

  showNotification(
    notificationService: NotificationService,
    activeConversationTracker: ActiveConversationTracker,
    contactPeerId: String,
    senderUsername: String,
    messageText: String
  ): Future<void>


  FLUTTER USE CASES - SETTINGS:
  ─────────────────────────────
  getImageQualityPreference(
    secureKeyStore: SecureKeyStore
  ): Future<ImageQualityPreference>

  setImageQualityPreference(
    secureKeyStore: SecureKeyStore,
    preference: ImageQualityPreference
  ): Future<void>

  uploadProfilePicture(
    bridge: Bridge,
    imageBytes: Uint8List,
    imageProcessor: ImageProcessor
  ): Future<bool>

  downloadProfilePicture(
    bridge: Bridge,
    peerId: String
  ): Future<Uint8List?>


  FLUTTER USE CASES - MEDIA:
  ──────────────────────────
  uploadMedia(
    bridge: Bridge,
    filePath: String,
    imageProcessor: ImageProcessor,
    mediaAttachmentRepo: MediaAttachmentRepository
  ): Future<String?>   // Returns media ID on success

  downloadMedia(
    bridge: Bridge,
    mediaId: String,
    mediaAttachmentRepo: MediaAttachmentRepository,
    mediaFileManager: MediaFileManager
  ): Future<String?>   // Returns local path on success


  FLUTTER USE CASES - CONTACTS:
  ─────────────────────────────
  addContact(
    repository: ContactRepository,
    contact: ContactModel
  ): Future<AddContactResult>

  archiveContact(
    contactRepo: ContactRepository,
    peerId: String
  ): Future<void>

  unarchiveContact(
    contactRepo: ContactRepository,
    peerId: String
  ): Future<void>

  blockContact(
    contactRepo: ContactRepository,
    peerId: String
  ): Future<void>

  unblockContact(
    contactRepo: ContactRepository,
    peerId: String
  ): Future<void>

  deleteContactAndMessages(
    contactRepo: ContactRepository,
    messageRepo: MessageRepository,
    peerId: String
  ): Future<void>


  FLUTTER USE CASES - GROUPS:
  ──────────────────────────
  createGroup(
    bridge: Bridge,
    groupRepo: GroupRepository,
    name: String,
    type: GroupType,
    creatorPeerId: String,
    creatorPublicKey: String,
    creatorMlKemPublicKey: String,
    {description?: String}
  ): Future<GroupModel>

  createGroupWithMembers(
    bridge: Bridge,
    groupRepo: GroupRepository,
    p2pService: P2PService,
    identity: IdentityModel,
    selectedContacts: List<ContactModel>,
    type: GroupType,
    {name?: String, description?: String}
  ): Future<CreateGroupWithMembersResult>

  joinGroup(
    bridge: Bridge,
    groupRepo: GroupRepository,
    group: GroupModel,
    groupKey: String,
    keyEpoch: int,
    selfPeerId: String,
    selfPublicKey: String,
    selfRole: MemberRole
  ): Future<void>

  leaveGroup(
    bridge: Bridge,
    groupRepo: GroupRepository,
    groupId: String
  ): Future<void>

  archiveGroup(
    groupRepo: GroupRepository,
    groupId: String
  ): Future<void>

  unarchiveGroup(
    groupRepo: GroupRepository,
    groupId: String
  ): Future<void>

  deleteGroupAndMessages(
    bridge: Bridge,
    groupRepo: GroupRepository,
    groupMessageRepo: GroupMessageRepository,
    groupId: String
  ): Future<void>

  addGroupMember(
    bridge: Bridge,
    groupRepo: GroupRepository,
    groupId: String,
    newMember: GroupMember,
    selfPeerId: String
  ): Future<void>

  removeGroupMember(
    bridge: Bridge,
    groupRepo: GroupRepository,
    groupId: String,
    memberPeerId: String
  ): Future<void>

  sendGroupMessage(
    bridge: Bridge,
    groupRepo: GroupRepository,
    msgRepo: GroupMessageRepository,
    groupId: String,
    text: String,
    senderPeerId: String,
    senderPublicKey: String,
    senderPrivateKey: String,
    senderUsername: String,
    {mediaAttachments?: List<MediaAttachment>,
     mediaAttachmentRepo?: MediaAttachmentRepository}
  ): Future<(SendGroupMessageResult, GroupMessage?)>

  handleIncomingGroupMessage(
    groupRepo: GroupRepository,
    msgRepo: GroupMessageRepository,
    groupId: String,
    senderId: String,
    senderUsername: String,
    keyEpoch: int,
    text: String,
    timestamp: String,
    {media?: List<Map>,
     mediaAttachmentRepo?: MediaAttachmentRepository}
  ): Future<GroupMessage?>

  handleIncomingGroupInvite(
    message: ChatMessage,
    groupRepo: GroupRepository,
    contactRepo: ContactRepository,
    bridge: Bridge,
    {ownMlKemSecretKey?: String}
  ): Future<(HandleGroupInviteResult, String?)>

  sendGroupInvite(
    p2pService: P2PService,
    bridge: Bridge,
    recipientPeerId: String,
    recipientMlKemPublicKey: String?,
    senderPeerId: String,
    senderUsername: String,
    groupId: String,
    groupKey: String,
    keyEpoch: int,
    groupConfig: Map
  ): Future<SendGroupInviteResult>

  sendGroupInvitesInParallel(
    p2pService: P2PService,
    bridge: Bridge,
    senderPeerId: String,
    senderUsername: String,
    groupId: String,
    groupKey: String,
    keyEpoch: int,
    groupConfig: Map,
    recipients: List<({peerId, mlKemPublicKey?})>
  ): Future<int>

  rotateGroupKey(
    bridge: Bridge,
    groupRepo: GroupRepository,
    groupId: String
  ): Future<GroupKeyInfo>

  rotateAndDistributeGroupKey(
    bridge: Bridge,
    groupRepo: GroupRepository,
    groupId: String,
    selfPeerId: String,
    senderPublicKey: String,
    senderPrivateKey: String,
    senderUsername: String,
    {sendP2PMessage?: (peerId, msg) => bool}
  ): Future<GroupKeyInfo?>

  rejoinGroupTopics(
    bridge: Bridge,
    groupRepo: GroupRepository
  ): Future<void>

  drainGroupOfflineInbox(
    bridge: Bridge,
    groupRepo: GroupRepository,
    msgRepo: GroupMessageRepository,
    {mediaAttachmentRepo?: MediaAttachmentRepository}
  ): Future<void>


  FLUTTER USE CASES - ORBIT (GROUPS):
  ────────────────────────────────────
  loadOrbitGroups(
    groupRepo: GroupRepository,
    msgRepo: GroupMessageRepository,
    {includeArchived: bool = false}
  ): Future<List<OrbitGroup>>


  FLUTTER USE CASES - CONTACT REQUESTS:
  ─────────────────────────────────────
  sendContactRequest(
    p2pService: P2PService,
    identityRepo: IdentityRepository,
    bridge: Bridge,
    targetPeerId: String
  ): Future<SendContactRequestResult>

  acceptContactRequest(
    requestRepo: ContactRequestRepository,
    contactRepo: ContactRepository,
    peerId: String
  ): Future<AcceptContactRequestResult>

  declineContactRequest(
    requestRepo: ContactRequestRepository,
    peerId: String
  ): Future<DeclineContactRequestResult>

  handleIncomingMessage(
    message: ChatMessage,
    bridge: Bridge,
    requestRepo: ContactRequestRepository,
    contactRepo: ContactRepository,
    ownPeerId: String
  ): Future<(HandleMessageResult, ContactRequestModel?)>

  acceptAndReciprocate(
    requestRepo: ContactRequestRepository,
    contactRepo: ContactRepository,
    identityRepo: IdentityRepository,
    p2pService: P2PService,
    bridge: Bridge,
    peerId: String
  ): Future<AcceptContactRequestResult>

  retryIncompleteKeyExchanges(
    contactRepo: ContactRepository,
    identityRepo: IdentityRepository,
    p2pService: P2PService,
    bridge: Bridge
  ): Future<int>   // Returns count of contacts updated


  FLUTTER BRIDGE HELPERS - IDENTITY/CRYPTO:
  ─────────────────────────────────────────
  callIdentityGenerate(bridge: Bridge): Future<Map<String, dynamic>>
  callIdentityRestore(bridge: Bridge, mnemonic12: String): Future<Map<String, dynamic>>
  callSignPayload(bridge: Bridge, dataToSign: String, privateKey: String): Future<Map<String, dynamic>>
  callVerifyPayload(bridge: Bridge, dataToVerify: String, signature: String, publicKey: String): Future<Map<String, dynamic>>
  callMlKemKeygen(bridge: Bridge): Future<Map<String, dynamic>>
  callEncryptMessage({bridge, recipientMlKemPublicKey, plaintext, timeout?}): Future<Map<String, dynamic>>
  callDecryptMessage({bridge, ownMlKemSecretKey, kem, ciphertext, nonce, timeout?}): Future<Map<String, dynamic>>
  callEncryptContactRequest({bridge, recipientPublicKey, senderPrivateKey, plaintext, msgId, ts}): Future<Map<String, dynamic>>
  callDecryptContactRequest({bridge, senderPublicKey, recipientPrivateKey, ephemeralPublicKey, ciphertext, nonce, msgId, ts}): Future<Map<String, dynamic>>


  FLUTTER BRIDGE HELPERS - P2P:
  ─────────────────────────────
  callP2PNodeStart(bridge, privateKeyHex, {relayAddresses, autoRegister, namespace}): Future<Map>
  callP2PNodeStop(bridge): Future<Map>
  callP2PNodeStatus(bridge): Future<Map>
  callP2PRendezvousRegister(bridge, {namespace, serverAddresses}): Future<Map>
  callP2PRendezvousDiscover(bridge, {peerId, namespace, serverAddresses, timeoutMs}): Future<Map>
  callP2PPeerDial(bridge, peerId, {addresses, timeoutMs}): Future<Map>
  callP2PPeerDisconnect(bridge, peerId): Future<Map>
  callP2PMessageSend(bridge, peerId, message, {timeoutMs}): Future<Map>
  callP2PInboxStore(bridge, {toPeerId, message}): Future<Map>
  callP2PInboxRetrieve(bridge): Future<Map>
  callP2PInboxRegisterToken(bridge, {token, platform}): Future<Map>
  callP2PRelayReconnect(bridge): Future<Map>
  callP2PRelayProbe(bridge): Future<Map>


  FLUTTER DB HELPERS - IDENTITY:
  ──────────────────────────────
  dbLoadIdentityRow(db: Database): Future<Map<String, Object?>?>
  dbUpsertIdentityRow(db: Database, row: Map<String, Object?>): Future<void>
  runIdentityTableMigration(db: Database): Future<void>   ← creates all 3 tables


  FLUTTER DB HELPERS - CONTACTS:
  ──────────────────────────────
  dbLoadAllContacts(db: Database): Future<List<Map>>
  dbLoadContact(db: Database, peerId: String): Future<Map?>
  dbUpsertContact(db: Database, row: Map): Future<void>
  dbDeleteContact(db: Database, peerId: String): Future<void>
  dbGetContactCount(db: Database): Future<int>
  dbContactExists(db: Database, peerId: String): Future<bool>
  dbArchiveContact(db: Database, peerId: String): Future<void>
  dbUnarchiveContact(db: Database, peerId: String): Future<void>
  dbLoadActiveContacts(db: Database): Future<List<Map>>
  dbLoadArchivedContacts(db: Database): Future<List<Map>>
  dbBlockContact(db: Database, peerId: String): Future<void>
  dbUnblockContact(db: Database, peerId: String): Future<void>


  FLUTTER DB HELPERS - CONTACT REQUESTS:
  ──────────────────────────────────────
  dbLoadPendingRequests(db: Database): Future<List<Map>>
  dbLoadRequest(db: Database, peerId: String): Future<Map?>
  dbUpsertRequest(db: Database, row: Map): Future<void>
  dbUpdateRequestStatus(db: Database, peerId: String, status: String): Future<void>
  dbDeleteRequest(db: Database, peerId: String): Future<void>
  dbRequestExists(db: Database, peerId: String): Future<bool>


  FLUTTER DB HELPERS - MESSAGES:
  ──────────────────────────────
  dbInsertMessage(db: Database, row: Map<String, Object?>): Future<void>
  dbLoadMessagesForContact(db: Database, contactPeerId: String): Future<List<Map>>
  dbLoadLatestMessageForContact(db: Database, contactPeerId: String): Future<Map?>
  dbUpdateMessageStatus(db: Database, id: String, status: String): Future<void>
  dbLoadMessage(db: Database, id: String): Future<Map?>
  dbGetMessageCount(db: Database): Future<int>
  dbCountMessagesForContact(db: Database, contactPeerId: String): Future<int>
  dbMarkConversationAsRead(db: Database, contactPeerId: String): Future<int>
  dbCountUnreadForContact(db: Database, contactPeerId: String): Future<int>
  dbCountTotalUnread(db: Database): Future<int>
  dbCountTotalUnreadExcludingArchived(db: Database): Future<int>
  dbDeleteMessagesForContact(db: Database, contactPeerId: String): Future<void>
  dbLoadFailedOutgoingMessages(db: Database): Future<List<Map>>
  dbLoadMessagesPage(db: Database, contactPeerId: String, {limit: int, beforeTimestamp: String?}): Future<List<Map>>
  dbLoadUnackedOutgoingMessages(db: Database): Future<List<Map>>
  runMessagesTableMigration(db: Database): Future<void>   ← creates messages table + indexes
  runReadAtColumnMigration(db: Database): Future<void>    ← adds read_at TEXT to messages (v6)
  runArchiveColumnsMigration(db: Database): Future<void>  ← adds is_archived, archived_at to contacts (v7)
  runBlockColumnsMigration(db: Database): Future<void>    ← adds is_blocked, blocked_at to contacts (v8)
  runQuotedMessageIdMigration(db: Database): Future<void> ← adds quoted_message_id TEXT to messages (v9)
  runMediaAttachmentsMigration(db: Database): Future<void> ← creates media_attachments table + indexes (v10)
  runAvatarVersionMigration(db: Database): Future<void>   ← adds avatar_version INT to identity and contacts (v11)


  FLUTTER DB HELPERS - MEDIA ATTACHMENTS:
  ───────────────────────────────────────
  dbSaveAttachment(db: Database, row: Map<String, Object?>): Future<void>
  dbLoadAttachmentsForMessage(db: Database, messageId: String): Future<List<Map>>
  dbLoadAttachmentsForMessages(db: Database, messageIds: List<String>): Future<List<Map>>
  dbUpdateAttachmentLocalPath(db: Database, id: String, localPath: String): Future<void>
  dbUpdateAttachmentDownloadStatus(db: Database, id: String, status: String): Future<void>
  dbDeleteAttachmentsForMessage(db: Database, messageId: String): Future<void>
  dbDeleteAttachmentsForContact(db: Database, contactPeerId: String): Future<void>
  dbLoadPendingDownloads(db: Database): Future<List<Map>>


  FLUTTER BRIDGE HELPERS - GROUPS:
  ─────────────────────────────────
  callGroupCreate(bridge, {name, type, creatorPeerId, creatorPublicKey, creatorMlKemPublicKey?, description?, timeout?}): Future<Map>
  callGroupJoin(bridge, {groupId, topicName, timeout?}): Future<void>
  callGroupJoinWithConfig(bridge, {groupId, groupConfig, groupKey, keyEpoch, timeout?}): Future<void>
  callGroupLeave(bridge, groupId, {timeout?}): Future<void>
  callGroupPublish(bridge, {groupId, text, senderPeerId, senderPublicKey, senderPrivateKey, senderUsername?, media?, timeout?}): Future<Map>
  callGroupUpdateConfig(bridge, {groupId, groupConfig, timeout?}): Future<void>
  callGroupRotateKey(bridge, groupId, {timeout?}): Future<Map>
  callGroupUpdateKey(bridge, {groupId, groupKey, keyEpoch, timeout?}): Future<void>
  callGroupInboxStore(bridge, groupId, message, {timeout?}): Future<void>
  callGroupInboxRetrieve(bridge, groupId, sinceTimestamp, {timeout?}): Future<List<Map>>
  callGroupKeygen(bridge, {timeout?}): Future<String>
  callGroupEncrypt(bridge, groupKey, plaintext, {timeout?}): Future<Map>
  callGroupDecrypt(bridge, groupKey, ciphertext, nonce, {timeout?}): Future<String>


  FLUTTER BRIDGE HELPERS - MEDIA:
  ───────────────────────────────
  callMediaUpload(bridge: Bridge, {data: String, meta: Map}): Future<Map<String, dynamic>>
  callMediaDownload(bridge: Bridge, {id: String}): Future<Map<String, dynamic>>
  callMediaDelete(bridge: Bridge, {id: String}): Future<Map<String, dynamic>>
  callMediaList(bridge: Bridge): Future<Map<String, dynamic>>
  callProfileUpload(bridge: Bridge, {peerId: String, data: String}): Future<Map<String, dynamic>>
  callProfileDownload(bridge: Bridge, {peerId: String}): Future<Map<String, dynamic>>


  FLUTTER UTILS:
  ──────────────
  base64ToHex(String base64): String
  hexToBase64(String hex): String
  bytesToHex(Uint8List bytes): String
  hexToBytes(String hex): Uint8List
  RingAvatarGenerator.generate(String peerId, double size): RingAvatarData
  RingAvatarGenerator.djb2Hash(String input): int
  formatRelativeTime(DateTime timestamp): String   ← "2m ago", "3h ago", etc.


  FLUTTER DB HELPERS - GROUPS:
  ─────────────────────────────
  dbInsertGroup(db: Database, row: Map): Future<void>
  dbLoadAllGroups(db: Database): Future<List<Map>>
  dbLoadGroup(db: Database, id: String): Future<Map?>
  dbUpdateGroup(db: Database, row: Map): Future<void>
  dbDeleteGroup(db: Database, id: String): Future<void>
  dbCountGroups(db: Database): Future<int>
  dbArchiveGroup(db: Database, id: String): Future<void>
  dbUnarchiveGroup(db: Database, id: String): Future<void>
  dbLoadActiveGroups(db: Database): Future<List<Map>>
  runGroupsTablesMigration(db: Database): Future<void>   <- creates groups, group_members, group_keys tables (v17)


  FLUTTER DB HELPERS - GROUP MEMBERS:
  ────────────────────────────────────
  dbInsertGroupMember(db: Database, row: Map): Future<void>
  dbLoadAllGroupMembers(db: Database, groupId: String): Future<List<Map>>
  dbLoadGroupMember(db: Database, groupId: String, peerId: String): Future<Map?>
  dbUpdateGroupMemberRole(db: Database, groupId: String, peerId: String, role: String): Future<void>
  dbDeleteGroupMember(db: Database, groupId: String, peerId: String): Future<void>
  dbDeleteAllGroupMembers(db: Database, groupId: String): Future<void>
  dbCountGroupMembers(db: Database, groupId: String): Future<int>


  FLUTTER DB HELPERS - GROUP KEYS:
  ────────────────────────────────
  dbInsertGroupKey(db: Database, row: Map): Future<void>
  dbLoadLatestGroupKey(db: Database, groupId: String): Future<Map?>
  dbLoadGroupKeyByGeneration(db: Database, groupId: String, generation: int): Future<Map?>
  dbLoadAllGroupKeys(db: Database, groupId: String): Future<List<Map>>
  dbDeleteAllGroupKeys(db: Database, groupId: String): Future<void>


  FLUTTER DB HELPERS - GROUP MESSAGES:
  ─────────────────────────────────────
  dbInsertGroupMessage(db: Database, row: Map): Future<void>
  dbLoadGroupMessagesPage(db: Database, groupId: String, {limit: int, offset: int}): Future<List<Map>>
  dbLoadAllGroupMessages(db: Database, groupId: String): Future<List<Map>>
  dbLoadLatestGroupMessage(db: Database, groupId: String): Future<Map?>
  dbLoadGroupMessage(db: Database, id: String): Future<Map?>
  dbUpdateGroupMessageStatus(db: Database, id: String, status: String): Future<void>
  dbCountGroupMessages(db: Database, groupId: String): Future<int>
  dbCountUnreadGroupMessages(db: Database, groupId: String): Future<int>
  dbCountTotalUnreadGroupMessages(db: Database): Future<int>
  dbMarkGroupMessagesAsRead(db: Database, groupId: String): Future<int>
  dbExistsGroupMessageByContent(db, groupId, senderPeerId, text, timestamp): Future<bool>
  dbDeleteGroupMessagesForGroup(db: Database, groupId: String): Future<int>
  dbDeleteGroupMessage(db: Database, id: String): Future<void>
  runGroupMessagesTableMigration(db: Database): Future<void>   <- creates group_messages table + indexes (v18)


  FLUTTER DB HELPERS - ML-KEM KEYS:
  ─────────────────────────────────
  runMlKemKeysMigration(db: Database): Future<void>   ← adds ml_kem_* columns to identity, contacts, contact_requests


  FLUTTER DB HELPERS - DATA-AT-REST HARDENING:
  ─────────────────────────────────────────────
  runNullifySecretColumnsMigration(db: Database): Future<void>   ← v4: makes private_key, mnemonic12 nullable
  runSecretNullChecksMigration(db: Database): Future<void>       ← v5: CHECK constraints + avatar_blob BLOB


  FLUTTER DB HELPERS - TRANSPORT/WAVEFORM/WIRE ENVELOPE:
  ──────────────────────────────────────────────────────
  runTransportColumnMigration(db: Database): Future<void>        ← v12: adds transport TEXT to messages
  runWaveformColumnMigration(db: Database): Future<void>         ← v13: adds waveform TEXT to media_attachments
  runWireEnvelopeColumnMigration(db: Database): Future<void>     ← v14: adds wire_envelope TEXT to messages


  FLUTTER SECURE STORAGE:
  ───────────────────────
  SecureKeyStore.read(key: String): Future<String?>
  SecureKeyStore.write(key: String, value: String): Future<void>
  SecureKeyStore.delete(key: String): Future<void>
  SecureKeyStore.containsKey(key: String): Future<bool>
  openEncryptedDatabase(path, version, secureKeyStore): Future<Database>
  migrateSecretsToSecureStorage(db, secureKeyStore): Future<void>


  GO BRIDGE FUNCTIONS (go-mknoon/bridge/bridge.go):
  ─────────────────────────────────────────────────
  HandleCommand(command string, payload string) string   // JSON dispatch to all handlers
  handleIdentityGenerate(payload) → {ok, identity}       // BIP39 + Ed25519 + ML-KEM-768
  handleIdentityRestore(payload) → {ok, identity}        // Derive from mnemonic + fresh ML-KEM
  handlePayloadSign(payload) → {ok, signature}           // Ed25519 sign
  handlePayloadVerify(payload) → {ok, verified}          // Ed25519 verify
  handleMlKemKeygen(payload) → {ok, publicKey, secretKey}
  handleMessageEncrypt(payload) → {ok, kem, ciphertext, nonce}
  handleMessageDecrypt(payload) → {ok, plaintext}
  handleNodeStart(payload) → {ok, peerId, ...}           // libp2p node + relay + auto-register
  handleNodeStop(payload) → {ok}
  handleNodeStatus(payload) → {ok, peerId, isStarted, connections, ...}
  handleRendezvousRegister(payload) → {ok}               // Signed peer record registration
  handleRendezvousDiscover(payload) → {ok, peers}
  handlePeerDial(payload) → {ok}
  handlePeerDisconnect(payload) → {ok}
  handleMessageSend(payload) → {ok, reply?}              // Frame-based with ACK
  handleInboxStore(payload) → {ok}
  handleInboxRetrieve(payload) → {ok, messages}
  handleInboxRegisterToken(payload) → {ok}               // FCM token registration
  handleMediaUpload(payload) → {ok, id, ...}             // Media upload to relay
  handleMediaDownload(payload) → {ok, data, ...}         // Media download from relay
  handleMediaDelete(payload) → {ok}                      // Media delete from relay
  handleMediaList(payload) → {ok, files}                 // List media on relay
  handleProfileUpload(payload) → {ok}                    // Profile picture upload
  handleProfileDownload(payload) → {ok, data}            // Profile picture download
  handleEncryptContactRequest(payload) → {ok, ephemeralPublicKey, ciphertext, nonce}  // X25519 ECDH + HKDF + AES-256-GCM
  handleDecryptContactRequest(payload) → {ok, plaintext}                               // X25519 ECDH + HKDF + AES-256-GCM
  handleRelayReconnect(payload) → {ok}                   // Reconnect to relay
  handleRelayProbe(payload) → {ok}                       // Probe relay connectivity

  GO BRIDGE FUNCTIONS - GROUPS (go-mknoon/bridge/bridge.go):
  ──────────────────────────────────────────────────────────
  handleGroupCreate(payload) → {ok, groupId, topicName, groupKey, keyEpoch}
  handleGroupJoinTopic(payload) → {ok}                   // Subscribe to pubsub topic
  handleGroupLeaveTopic(payload) → {ok}                  // Unsubscribe from pubsub topic
  handleGroupPublish(payload) → {ok, messageId}          // Encrypt + sign + publish to topic
  handleGroupUpdateConfig(payload) → {ok}                // Update topic validator config
  handleGroupRotateKey(payload) → {ok, groupKey, keyEpoch}
  handleGroupUpdateKey(payload) → {ok}                   // Update stored key (non-admin)
  handleGroupInboxStore(payload) → {ok}                  // Store-and-forward via relay
  handleGroupInboxRetrieve(payload) → {ok, messages}     // Retrieve from relay inbox
  handleGenerateGroupKey(payload) → {ok, groupKey}       // AES-256 symmetric key generation
  handleGroupEncryptMessage(payload) → {ok, ciphertext, nonce}
  handleGroupDecryptMessage(payload) → {ok, plaintext}


  GO NODE FUNCTIONS (go-mknoon/node/):
  ─────────────────────────────────────
  Node.Start(privateKeyHex, relayAddresses) error        // libp2p host + relay + NAT + hole punch
  Node.Stop() error
  Node.Status() NodeStatus
  Node.RegisterRendezvous(namespace, serverAddrs) error  // Protobuf signed peer records
  Node.DiscoverPeers(namespace, serverAddrs, timeout) []Peer
  Node.DialPeer(peerId, addresses, timeout) error
  Node.DisconnectPeer(peerId) error
  Node.SendMessage(peerId, message, timeout) (reply, error)  // /mknoon/chat/1.0.0
  Node.StoreInbox(toPeerId, message) error               // /mknoon/inbox/1.0.0
  Node.RetrieveInbox() []InboxMessage
  Node.RegisterInboxToken(token, platform) error          // FCM push registration
  Node.MediaUpload(data, meta) (MediaMeta, error)        // /mknoon/media/1.0.0 upload
  Node.MediaDownload(id) ([]byte, error)                 // /mknoon/media/1.0.0 download
  Node.MediaDelete(id) error                             // /mknoon/media/1.0.0 delete
  Node.MediaList() []MediaMeta                           // /mknoon/media/1.0.0 list
  Node.ProfileUpload(peerId, data) error                 // Profile picture upload
  Node.ProfileDownload(peerId) ([]byte, error)           // Profile picture download
  Node.GroupCreateTopic(name, type, creatorPeerId, ...) (GroupResult, error)
  Node.GroupJoinTopic(groupId, config, key, epoch) error   // Subscribe + validator setup
  Node.GroupLeaveTopic(groupId) error                      // Unsubscribe pubsub topic
  Node.GroupPublish(groupId, text, senderKeys, ...) error  // Encrypt + sign + publish
  Node.GroupUpdateConfig(groupId, config) error             // Update topic validator
  Node.GroupRotateKey(groupId) (key, epoch, error)         // Generate new symmetric key
  Node.GroupUpdateKey(groupId, key, epoch) error            // Store key (non-admin path)
  Node.GroupInboxStore(groupId, message) error              // Store in relay group inbox
  Node.GroupInboxRetrieve(groupId, since) ([]Msg, error)   // Retrieve from relay inbox
  Node.SetEventCallback(callback)                         // Push events to Flutter

└─────────────────────────────────────────────────────────────────────────────┘
```

### Class Relationships

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          DEPENDENCY GRAPH                                    │
└─────────────────────────────────────────────────────────────────────────────┘

  StartupRouter
       │
       ├──────► decideStartupRoute()
       │              │
       │              ├──────► IdentityRepository.loadIdentity()
       │              │
       │              └──────► ContactRepository.getContactCount()
       │
       ├──────► FeedWired (hasIdentityWithContacts)
       │              │
       │              ├──────► IdentityRepository.loadIdentity()
       │              │
       │              ├──────► ContactRequestListener.requestStream
       │              │
       │              ├──────► ConnectionFeedItem.fromContact()
       │              │
       │              └──────► _onSwitchView('orbit')
       │                             │
       │                             └──────► Navigator.push(OrbitWired)
       │                                            │
       │                                            ├──────► loadOrbitData()
       │                                            │              │
       │                                            │              ├──────► ContactRepository.getAllContacts()
       │                                            │              │
       │                                            │              └──────► MessageRepository.getMessageCountForContact()
       │                                            │
       │                                            ├──────► ChatMessageListener.incomingMessageStream
       │                                            │
       │                                            ├──────► ContactRequestListener.requestStream
       │                                            │
       │                                            └──────► _onFriendTap()
       │                                                           │
       │                                                           └──────► Navigator.push(ConversationWired)
       │
       ├──────► FirstTimeExperienceWired (hasIdentityNoContacts)
       │
       ├──────► IdentityChoiceWired (needsIdentity)
       │              │
       │              ├──────► generateNewIdentity()
       │              │              │
       │              │              ├──────► callIdentityGenerate()
       │              │              │              │
       │              │              │              └──────► GoBridgeClient.send()
       │              │              │                             │
       │              │              │                             └──────► [Go] HandleCommand()
       │              │              │                                            │
       │              │              │                                            └──────► GenerateIdentity()
       │              │              │
       │              │              └──────► IdentityRepository.saveIdentity()
       │              │                             │
       │              │                             └──────► dbUpsertIdentityRow()
       │              │
       │              └──────► MnemonicInputWired
       │                             │
       │                             └──────► restoreIdentityFromMnemonic()
       │                                            │
       │                                            ├──────► callIdentityRestore()
       │                                            │              │
       │                                            │              └──────► [Go] RestoreFromMnemonic()
       │                                            │
       │                                            └──────► IdentityRepository.saveIdentity()
       │
       └──────► FirstTimeExperienceWired (from needsIdentity after generation)
                      │
                      ├──────► buildQRPayload()
                      │              │
                      │              ├──────► IdentityRepository.loadIdentity()
                      │              │
                      │              └──────► callSignPayload()
                      │                             │
                      │                             └──────► [Go] SignPayload()
                      │
                      ├──────► _onUsernameChanged()
                      │              │
                      │              └──────► IdentityRepository.saveIdentity()
                      │
                      ├──────► _onCameraPressed()
                      │              │
                      │              ├──────► ImagePicker.pickImage()
                      │              │
                      │              ├──────► Read bytes as Uint8List (no file copy to disk)
                      │              │
                      │              └──────► IdentityRepository.saveIdentity(avatarBlob: bytes)
                      │                             (avatar BLOB stored in SQLCipher DB)
                      │
                      ├──────► _onScanPressed()
                      │              │
                      │              └──────► QRScannerWired
                      │                             │
                      │                             ├──────► parseQRPayload()
                      │                             │              │
                      │                             │              ├──────► [Go] VerifyPayload()
                      │                             │              │
                      │                             │              └──────► ContactModel.fromQRPayload()
                      │                             │
                      │                             ├──────► addContact()
                      │                             │              │
                      │                             │              └──────► ContactRepository.addContact()
                      │                             │
                      │                             └──────► sendContactRequest() (background)
                      │                                            │
                      │                                            ├──────► P2PService.discoverPeer()
                      │                                            │
                      │                                            ├──────► P2PService.dialPeer()
                      │                                            │
                      │                                            └──────► P2PService.sendMessage()
                      │
                      └──────► ContactRequestListener.requestStream
                                     │
                                     └──────► _onContactRequest()
                                                    │
                                                    ├──────► ContactRequestDialog (Accept/Decline)
                                                    │
                                                    ├──────► acceptContactRequest()
                                                    │              │
                                                    │              ├──────► ContactRequestRepo.getRequest()
                                                    │              │
                                                    │              ├──────► ContactModel.fromRequest()
                                                    │              │
                                                    │              ├──────► ContactRepository.addContact()
                                                    │              │
                                                    │              └──────► ContactRequestRepo.updateStatus()
                                                    │
                                                    └──────► declineContactRequest()
                                                                   │
                                                                   └──────► ContactRequestRepo.updateStatus()


  IncomingMessageRouter (background service)
       │
       └──────► P2PService.messageStream (subscribe)
                      │
                      ├──────► contactRequestStream (type = "contact_request")
                      │
                      ├──────► chatMessageStream (type = "chat_message")
                      │
                      ├──────► groupInviteStream (type = "group_invite")
                      │
                      ├──────► groupKeyUpdateStream (type = "group_key_update")
                      │
                      └──────► unknownMessageStream (other types)


  ContactRequestListener (background service)
       │
       └──────► IncomingMessageRouter.contactRequestStream (subscribe)
                      │
                      └──────► handleIncomingMessage()
                                     │
                                     ├──────► JSON parse + validate
                                     │
                                     ├──────► [Go] VerifyPayload()
                                     │
                                     ├──────► ContactRepository.contactExists()
                                     │
                                     ├──────► ContactRequestRepo.requestExists()
                                     │
                                     └──────► ContactRequestRepo.addRequest()


  ChatMessageListener (background service)
       │
       ├──────► bridge: Bridge? (for ML-KEM decryption)
       │
       ├──────► getOwnMlKemSecretKey: () => Future<String?> (from identity repo)
       │
       └──────► IncomingMessageRouter.chatMessageStream (subscribe)
                      │
                      └──────► handleIncomingChatMessage(bridge, ownMlKemSecretKey)
                                     │
                                     ├──────► Detect v2 encrypted envelope
                                     │              │
                                     │              └──────► callDecryptMessage() (ML-KEM + AES-256-GCM)
                                     │
                                     ├──────► [else] Parse v1 plaintext MessagePayload
                                     │
                                     ├──────► ContactRepository.getContact() (validate sender)
                                     │
                                     ├──────► MessageRepository.messageExists() (duplicate check)
                                     │
                                     ├──────► ContactRepository.addContact() (if username changed)
                                     │
                                     └──────► MessageRepository.saveMessage()


  ConversationWired
       │
       ├──────► loadConversation()
       │              │
       │              └──────► MessageRepository.getMessagesForContact()
       │
       ├──────► _onSend(text) → sendChatMessage(bridge, recipientMlKemPublicKey)
       │              │
       │              ├──────► MessageRepository.saveMessage() (optimistic persist)
       │              │
       │              ├──────► [if ML-KEM key] callEncryptMessage() → v2 envelope
       │              │
       │              ├──────► [else] Build v1 plaintext envelope
       │              │
       │              ├──────► P2PService.discoverPeer()
       │              │
       │              ├──────► P2PService.dialPeer()
       │              │
       │              ├──────► P2PService.sendMessage() (3x retry)
       │              │
       │              └──────► P2PService.storeInInbox() (offline fallback)
       │
       ├──────► ChatMessageListener.incomingMessageStream (subscribe)
       │              │
       │              └──────► Filter by contactPeerId, update _messages
       │
       └──────► ChatMessageListener.contactUpdatedStream (subscribe)
                      │
                      └──────► Update _contact when username changes


  GroupMessageListener (background service)
       │
       ├──────► bridge.onGroupMessageReceived (subscribe via StreamController)
       │              │
       │              └──────► _handleMessage(Map)
       │                             │
       │                             ├──────► [if system msg] _handleSystemMessage()
       │                             │              │
       │                             │              ├──────► member_added → groupRepo.saveMember()
       │                             │              │                       + callGroupUpdateConfig()
       │                             │              │
       │                             │              ├──────► members_added → batch saveMember()
       │                             │              │                        + callGroupUpdateConfig()
       │                             │              │
       │                             │              └──────► member_removed
       │                             │                             │
       │                             │                             ├──────► [if self] leaveGroup()
       │                             │                             │              + groupRemovedStream.add()
       │                             │                             │
       │                             │                             └──────► [else] removeMember()
       │                             │                                            + callGroupUpdateConfig()
       │                             │
       │                             └──────► handleIncomingGroupMessage()
       │                                            │
       │                                            ├──────► GroupRepository.getGroup()
       │                                            │
       │                                            ├──────► GroupRepository.getMember()
       │                                            │
       │                                            ├──────► GroupMessageRepository.existsByContent()
       │                                            │
       │                                            └──────► GroupMessageRepository.saveMessage()
       │
       └──────► groupMessageStream (broadcast persisted GroupMessages to UI)


  GroupInviteListener (background service)
       │
       └──────► IncomingMessageRouter.groupInviteStream (subscribe)
                      │
                      └──────► handleIncomingGroupInvite()
                                     │
                                     ├──────► [v2] callDecryptMessage() (ML-KEM)
                                     │
                                     ├──────► [v1] GroupInvitePayload.fromJson()
                                     │
                                     ├──────► ContactRepository.getContact() (validate sender)
                                     │
                                     ├──────► GroupRepository.getGroup() (duplicate check)
                                     │
                                     ├──────► GroupRepository.saveGroup()
                                     │
                                     ├──────► GroupRepository.saveMember() (all members)
                                     │
                                     ├──────► GroupRepository.saveKey()
                                     │
                                     ├──────► callGroupJoinWithConfig()
                                     │
                                     └──────► _drainGroupInbox() (post-join inbox drain)


  GroupKeyUpdateListener (background service)
       │
       └──────► IncomingMessageRouter.groupKeyUpdateStream (subscribe)
                      │
                      └──────► _handleMessage()
                                     │
                                     ├──────► callDecryptMessage() (ML-KEM)
                                     │
                                     ├──────► GroupRepository.saveKey()
                                     │
                                     └──────► callGroupUpdateKey() (update Go validator)


  GroupConversationWired
       │
       ├──────► GroupMessageRepository.getMessagesPage()
       │
       ├──────► _onSend(text) → sendGroupMessage()
       │              │
       │              ├──────► GroupRepository.getGroup() (verify exists)
       │              │
       │              ├──────► callGroupPublish() (concurrent with inbox store)
       │              │
       │              ├──────► callGroupInboxStore() (concurrent with publish)
       │              │
       │              └──────► GroupMessageRepository.saveMessage()
       │
       ├──────► GroupMessageListener.groupMessageStream (subscribe)
       │              │
       │              └──────► Filter by groupId, update _messages
       │
       └──────► GroupMessageListener.groupRemovedStream (subscribe)
                      │
                      └──────► Navigator.pop() if current group removed


  P2PServiceImpl
       │
       ├──────► P2PBridgeClient (all bridge calls)
       │              │
       │              └──────► GoBridgeClient.send()
       │                             │
       │                             └──────► [Go] Node Module (libp2p)
       │                                            │
       │                                            └──────► Rendezvous Server
       │
       ├──────► stateStream (broadcast NodeState changes)
       │
       ├──────► messageStream (broadcast incoming ChatMessages)
       │
       ├──────► _drainOfflineInbox() (on startNode, injects queued messages)
       │              │
       │              └──────► retrieveInbox()
       │                             │
       │                             └──────► callP2PInboxRetrieve()
       │
       └──────► storeInInbox() / retrieveInbox()
                      │
                      └──────► callP2PInboxStore() / callP2PInboxRetrieve()

```

---

