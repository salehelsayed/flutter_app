import XCTest

final class NotificationPreviewResolverTests: XCTestCase {
  func testDecryptsOneToOneFixturePreview() throws {
    let fixture = try loadFixture("one_to_one_text")
    let plaintext = try fixturePlaintextJSON(fixture)
    let routeData = try XCTUnwrap(fixture["routeData"] as? [String: Any])
    let keyReader = MemoryPushKeyReader([
      PushSharedKeyNames.identityMlKemSecretKey: "chat-secret",
    ])
    let decryptor = MemoryPushDecryptor(chatPlaintext: plaintext)
    let eventEmitter = MemoryPushPreviewEventEmitter()
    let resolver = NotificationPreviewResolver(
      keyReader: keyReader,
      decryptor: decryptor,
      dedupeStore: MemoryPushDedupeStore(),
      eventEmitter: eventEmitter
    )

    let result = resolver.resolve(
      userInfo: routeData,
      fallbackTitle: "New Message",
      fallbackBody: "You have a new message"
    )

    XCTAssertTrue(result.didDecrypt)
    XCTAssertEqual(result.reason, "chat")
    XCTAssertEqual(result.title, "Alice")
    XCTAssertEqual(result.body, "Hello secret")
    XCTAssertEqual(result.threadIdentifier, "peer-alice")
    XCTAssertEqual(decryptor.chatCalls, 1)
    XCTAssertEqual(decryptor.lastChatSecretKey, "chat-secret")
    XCTAssertEqual(eventEmitter.events.count, 1)
    XCTAssertEqual(eventEmitter.events[0].event, "PUSH_NSE_DECRYPT_OK")
    XCTAssertEqual(eventEmitter.events[0].details, ["kind": "chat"])
  }

  func testDecryptsGroupFixturePreview() throws {
    let fixture = try loadFixture("group_text")
    let plaintext = try fixturePlaintextJSON(fixture)
    let routeData = try XCTUnwrap(fixture["routeData"] as? [String: Any])
    let keyReader = MemoryPushKeyReader([
      PushSharedKeyNames.groupKey(groupId: "group-team", keyEpoch: 7): "group-secret",
    ])
    let decryptor = MemoryPushDecryptor(groupPlaintext: plaintext)
    let eventEmitter = MemoryPushPreviewEventEmitter()
    let resolver = NotificationPreviewResolver(
      keyReader: keyReader,
      decryptor: decryptor,
      dedupeStore: MemoryPushDedupeStore(),
      eventEmitter: eventEmitter
    )

    let result = resolver.resolve(
      userInfo: routeData,
      fallbackTitle: "New Message",
      fallbackBody: "You have a new message"
    )

    XCTAssertTrue(result.didDecrypt)
    XCTAssertEqual(result.reason, "group")
    XCTAssertEqual(result.title, "Team Chat")
    XCTAssertEqual(result.body, "Alice: Hello secret")
    XCTAssertEqual(result.threadIdentifier, "group-team")
    XCTAssertEqual(decryptor.groupCalls, 1)
    XCTAssertEqual(decryptor.lastGroupKey, "group-secret")
    XCTAssertEqual(eventEmitter.events.count, 1)
    XCTAssertEqual(eventEmitter.events[0].event, "PUSH_NSE_DECRYPT_OK")
    XCTAssertEqual(eventEmitter.events[0].details, ["kind": "group"])
  }

  // 04-P0 SI-1 NSE — a muted group is suppressed BEFORE decryption: even with a
  // valid group key seeded (decryption would otherwise succeed), the mute
  // sentinel short-circuits to a silent generic fallback and never touches the
  // plaintext.
  func testSuppressesMutedGroupBeforeDecrypting() throws {
    let fixture = try loadFixture("group_text")
    let plaintext = try fixturePlaintextJSON(fixture)
    let routeData = try XCTUnwrap(fixture["routeData"] as? [String: Any])
    let keyReader = MemoryPushKeyReader([
      PushSharedKeyNames.groupKey(groupId: "group-team", keyEpoch: 7): "group-secret",
      PushSharedKeyNames.groupMuted(groupId: "group-team"): "1",
    ])
    let decryptor = MemoryPushDecryptor(groupPlaintext: plaintext)
    let eventEmitter = MemoryPushPreviewEventEmitter()
    let resolver = NotificationPreviewResolver(
      keyReader: keyReader,
      decryptor: decryptor,
      dedupeStore: MemoryPushDedupeStore(),
      eventEmitter: eventEmitter
    )

    let result = resolver.resolve(
      userInfo: routeData,
      fallbackTitle: "New Message",
      fallbackBody: "You have a new message"
    )

    XCTAssertTrue(result.suppress)
    XCTAssertFalse(result.didDecrypt)
    XCTAssertEqual(result.reason, "group_muted")
    // Mute short-circuits before decrypt — no plaintext is touched.
    XCTAssertEqual(decryptor.groupCalls, 0)
    // Generic fallback content (no decrypted preview leaks for a muted group).
    XCTAssertEqual(result.title, "New Message")
    XCTAssertEqual(result.body, "You have a new message")
    XCTAssertTrue(
      eventEmitter.events.contains { $0.event == "PUSH_NSE_GROUP_MUTED" }
    )
  }

  // 04-P0 SI-2 NSE (security core) — a removed member's device deletes its
  // group-key mirror (GroupRepositoryImpl.removeAllKeys -> _deleteGroupKeyMirror),
  // so the out-of-process NSE has no key: it must keep the generic fallback and
  // NEVER attempt to decrypt the group message (no preview leak after removal).
  func testMissingGroupKeyKeepsFallbackWithoutDecrypting() throws {
    let fixture = try loadFixture("group_text")
    let routeData = try XCTUnwrap(fixture["routeData"] as? [String: Any])
    // No group key seeded — models a removed/never-member device.
    let keyReader = MemoryPushKeyReader([:])
    let decryptor = MemoryPushDecryptor(groupPlaintext: "{}")
    let eventEmitter = MemoryPushPreviewEventEmitter()
    let resolver = NotificationPreviewResolver(
      keyReader: keyReader,
      decryptor: decryptor,
      dedupeStore: MemoryPushDedupeStore(),
      eventEmitter: eventEmitter
    )

    let result = resolver.resolve(
      userInfo: routeData,
      fallbackTitle: "New Message",
      fallbackBody: "You have a new message"
    )

    XCTAssertFalse(result.didDecrypt)
    XCTAssertEqual(result.reason, "missing_group_key")
    XCTAssertEqual(result.title, "New Message")
    XCTAssertEqual(result.body, "You have a new message")
    XCTAssertEqual(decryptor.groupCalls, 0)
  }

  // 04-P0 SI-5 — the NSE marker writer must reproduce the EXACT Dart gate
  // message key (sha256-named sidecar file in the app-group container) so the
  // Dart RecentRemoteNotificationGate suppresses the duplicate Dart banner.
  // This is the Swift half of the cross-process key-parity contract; the Dart
  // half lives in recent_remote_notification_gate_test.dart (SI-5 group).
  func testRecentRemoteShownMarkerWriterReproducesTheDartGateKey() throws {
    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("si5-marker-\(UUID().uuidString)")
    let store = RecentRemoteShownMarkerStore(directory: dir)

    func markerExists(_ key: String) -> Bool {
      FileManager.default.fileExists(
        atPath: dir.appendingPathComponent(
          RecentRemoteShownMarkerStore.markerName(forKey: key)
        ).path
      )
    }

    // 1:1 — key = message:<peerId>|<messageId>
    let oneToOne: [AnyHashable: Any] = [
      "type": "new_message", "sender_id": "peer-alice", "message_id": "msg-1",
    ]
    XCTAssertEqual(
      RecentRemoteShownMarkerStore.gateMessageKey(userInfo: oneToOne),
      "message:peer-alice|msg-1"
    )
    XCTAssertTrue(store.mark(userInfo: oneToOne))
    XCTAssertTrue(markerExists("message:peer-alice|msg-1"))
    XCTAssertTrue(store.mark(userInfo: oneToOne)) // idempotent duplicate push

    // group — key = message:group:<gid>|message:<id>|<id> (double message:)
    let group: [AnyHashable: Any] = [
      "type": "group_message", "groupId": "g-1", "message_id": "m-9",
    ]
    XCTAssertEqual(
      RecentRemoteShownMarkerStore.gateMessageKey(userInfo: group),
      "message:group:g-1|message:m-9|m-9"
    )
    XCTAssertTrue(store.mark(userInfo: group))
    XCTAssertTrue(markerExists("message:group:g-1|message:m-9|m-9"))

    // Non-message push -> no key, no marker.
    XCTAssertNil(
      RecentRemoteShownMarkerStore.gateMessageKey(userInfo: ["type": "group_invite"])
    )
    XCTAssertFalse(store.mark(userInfo: ["type": "group_invite"]))

    // 'm'-only messageId is NOT used (Dart's deriver ignores 'm') -> no key,
    // so both sides skip consistently.
    XCTAssertNil(
      RecentRemoteShownMarkerStore.gateMessageKey(userInfo: [
        "type": "new_message", "sender_id": "peer-x", "m": "msg-z",
      ])
    )

    // older-relay aliases: 'from' (sender) + 'id' (messageId).
    XCTAssertEqual(
      RecentRemoteShownMarkerStore.gateMessageKey(userInfo: [
        "type": "new_message", "from": "peer-bob", "id": "msg-2",
      ]),
      "message:peer-bob|msg-2"
    )

    try? FileManager.default.removeItem(at: dir)
  }

  // G-S5-1: the SINGLE source of truth for the NSE<->Dart dedupe key is
  // test_fixtures/si5_dedupe_keys.json. The Dart half reads the SAME file in
  // recent_remote_notification_gate_test.dart (SI-5 group, "matches the shared
  // SI-5 dedupe-key fixture") and asserts the gate produces each expectedKey.
  // Here we assert the Swift NSE's gateMessageKey reproduces it byte-for-byte,
  // so any drift on either side fails both targets.
  func testGateMessageKeyMatchesSharedDedupeFixture() throws {
    let cases = try loadDedupeKeyFixture()
    XCTAssertFalse(cases.isEmpty)
    for testCase in cases {
      let description = (testCase["description"] as? String) ?? "<no description>"
      let push = try XCTUnwrap(testCase["push"] as? [String: Any], description)
      // expectedKey is a String, or nil when the JSON value is null (NSNull).
      let expectedKey = testCase["expectedKey"] as? String
      XCTAssertEqual(
        RecentRemoteShownMarkerStore.gateMessageKey(userInfo: push),
        expectedKey,
        description
      )
    }
  }

  // G-S5-2: lock the AppGroupPushDedupeStore O_EXCL claim() on a real filesystem
  // (first-wins / second-loses), closing the coverage gap where dedupe was only
  // exercised via the in-memory MemoryPushDedupeStore fake.
  func testAppGroupPushDedupeStoreClaimIsFirstWinsSecondLoses() throws {
    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("dedupe-claim-\(UUID().uuidString)")
    let store = AppGroupPushDedupeStore(directory: dir)

    // First claim wins (creates the marker via O_CREAT|O_EXCL).
    XCTAssertTrue(store.claim(type: "new_message", messageId: "msg-1"))
    // Second identical claim loses (EEXIST -> open fails -> false).
    XCTAssertFalse(store.claim(type: "new_message", messageId: "msg-1"))
    // A distinct message still claims independently.
    XCTAssertTrue(store.claim(type: "new_message", messageId: "msg-2"))

    let contents = try FileManager.default.contentsOfDirectory(atPath: dir.path)
    XCTAssertEqual(Set(contents), ["new_message-msg-1", "new_message-msg-2"])

    try? FileManager.default.removeItem(at: dir)
  }

  func testDecryptsNativeV3GroupPreviewFromEncryptedExtra() throws {
    let plaintext = try jsonString([
      "text": "Hello group",
      "timestamp": "2026-06-05T19:33:38.064850Z",
      "username": "Alice",
      "extra": [
        "groupName": "Team Chat",
        "messageId": "native-msg-1",
      ],
    ])
    let keyReader = MemoryPushKeyReader([
      PushSharedKeyNames.groupKey(groupId: "group-team", keyEpoch: 7): "group-secret",
    ])
    let decryptor = MemoryPushDecryptor(groupPlaintext: plaintext)
    let resolver = NotificationPreviewResolver(
      keyReader: keyReader,
      decryptor: decryptor,
      dedupeStore: MemoryPushDedupeStore()
    )

    let result = resolver.resolve(
      userInfo: [
        "type": "group_message",
        "groupId": "group-team",
        "message_id": "native-msg-1",
        "keyEpoch": "7",
        "ciphertext": "ciphertext",
        "nonce": "nonce",
      ],
      fallbackTitle: "New Message",
      fallbackBody: "You have a new message"
    )

    XCTAssertTrue(result.didDecrypt)
    XCTAssertEqual(result.reason, "group")
    XCTAssertEqual(result.title, "Team Chat")
    XCTAssertEqual(result.body, "Alice: Hello group")
    XCTAssertEqual(result.threadIdentifier, "group-team")
  }

  func testDecryptsNativeV3GroupPreviewFromCompactApnsAliases() throws {
    let plaintext = try jsonString([
      "text": "Alias group",
      "timestamp": "2026-06-05T19:33:38.064850Z",
      "username": "Alice",
      "extra": [
        "groupName": "Team Chat",
      ],
    ])
    let keyReader = MemoryPushKeyReader([
      PushSharedKeyNames.groupKey(groupId: "group-team", keyEpoch: 7): "group-secret",
    ])
    let decryptor = MemoryPushDecryptor(groupPlaintext: plaintext)
    let resolver = NotificationPreviewResolver(
      keyReader: keyReader,
      decryptor: decryptor,
      dedupeStore: MemoryPushDedupeStore()
    )

    let result = resolver.resolve(
      userInfo: [
        "t": "group_message",
        "g": "group-team",
        "m": "native-msg-1",
        "e": "7",
        "c": "ciphertext",
        "n": "nonce",
      ],
      fallbackTitle: "New Message",
      fallbackBody: "You have a new message"
    )

    XCTAssertTrue(result.didDecrypt)
    XCTAssertEqual(result.title, "Team Chat")
    XCTAssertEqual(result.body, "Alice: Alias group")
    XCTAssertEqual(result.threadIdentifier, "group-team")
  }

  func testSanitizesGroupMemberJoinedSystemPreview() throws {
    let plaintext = try jsonString([
      "messageId": "msg-group-join",
      "senderUsername": "Rasha",
      "text": jsonString([
        "__sys": "member_joined",
        "member": [
          "peerId": "12D3KooWRawPeerId",
          "username": "Rasha",
        ],
      ]),
    ])
    let routeData: [String: Any] = [
      "type": "group_message",
      "groupId": "group-team",
      "message_id": "msg-group-join",
      "keyEpoch": "7",
      "ciphertext": "ciphertext",
      "nonce": "nonce",
    ]
    let keyReader = MemoryPushKeyReader([
      PushSharedKeyNames.groupKey(groupId: "group-team", keyEpoch: 7): "group-secret",
    ])
    let decryptor = MemoryPushDecryptor(groupPlaintext: plaintext)
    let resolver = NotificationPreviewResolver(
      keyReader: keyReader,
      decryptor: decryptor,
      dedupeStore: MemoryPushDedupeStore()
    )

    let result = resolver.resolve(
      userInfo: routeData,
      fallbackTitle: "New Message",
      fallbackBody: "You have a new message"
    )

    XCTAssertTrue(result.didDecrypt)
    XCTAssertEqual(result.reason, "group")
    XCTAssertEqual(result.title, "New Message")
    XCTAssertEqual(result.body, "Rasha joined the group")
    XCTAssertEqual(result.threadIdentifier, "group-team")
    for forbidden in ["{", "}", "__sys", "peerId", "12D3"] {
      XCTAssertFalse(result.body.contains(forbidden))
    }
  }

  func testSanitizesUnknownGroupSystemPreview() throws {
    let plaintext = try jsonString([
      "messageId": "msg-group-role",
      "senderUsername": "Rasha",
      "text": jsonString([
        "__sys": "member_role_changed",
        "member": [
          "peerId": "12D3KooWRawPeerId",
        ],
      ]),
    ])
    let routeData: [String: Any] = [
      "type": "group_message",
      "groupId": "group-team",
      "message_id": "msg-group-role",
      "keyEpoch": "7",
      "ciphertext": "ciphertext",
      "nonce": "nonce",
    ]
    let keyReader = MemoryPushKeyReader([
      PushSharedKeyNames.groupKey(groupId: "group-team", keyEpoch: 7): "group-secret",
    ])
    let decryptor = MemoryPushDecryptor(groupPlaintext: plaintext)
    let resolver = NotificationPreviewResolver(
      keyReader: keyReader,
      decryptor: decryptor,
      dedupeStore: MemoryPushDedupeStore()
    )

    let result = resolver.resolve(
      userInfo: routeData,
      fallbackTitle: "New Message",
      fallbackBody: "You have a new message"
    )

    XCTAssertTrue(result.didDecrypt)
    XCTAssertEqual(result.reason, "group")
    XCTAssertEqual(result.title, "New Message")
    XCTAssertEqual(result.body, "Group update")
    XCTAssertEqual(result.threadIdentifier, "group-team")
    for forbidden in ["{", "}", "__sys", "peerId", "12D3"] {
      XCTAssertFalse(result.body.contains(forbidden))
    }
  }

  func testMissingChatSecretKeepsStaticFallbackWithoutDecrypting() {
    let decryptor = MemoryPushDecryptor(chatPlaintext: #"{"senderUsername":"Alice","text":"Secret"}"#)
    let eventEmitter = MemoryPushPreviewEventEmitter()
    let resolver = NotificationPreviewResolver(
      keyReader: MemoryPushKeyReader([:]),
      decryptor: decryptor,
      dedupeStore: MemoryPushDedupeStore(),
      eventEmitter: eventEmitter
    )

    let result = resolver.resolve(
      userInfo: [
        "type": "new_message",
        "sender_id": "peer-alice",
        "message_id": "msg-1",
        "kem": "kem",
        "ciphertext": "ciphertext",
        "nonce": "nonce",
      ],
      fallbackTitle: "New Message",
      fallbackBody: "You have a new message"
    )

    XCTAssertFalse(result.didDecrypt)
    XCTAssertEqual(result.reason, "missing_chat_secret")
    XCTAssertEqual(result.title, "New Message")
    XCTAssertEqual(result.body, "You have a new message")
    XCTAssertNil(result.threadIdentifier)
    XCTAssertEqual(decryptor.chatCalls, 0)
    XCTAssertEqual(eventEmitter.events.count, 1)
    XCTAssertEqual(eventEmitter.events[0].event, "PUSH_NSE_DECRYPT_FAIL")
    XCTAssertEqual(
      eventEmitter.events[0].details,
      ["kind": "chat", "reason": "missing_chat_secret"]
    )
  }

  func testDuplicateMessageKeepsFallbackAndSkipsSecondDecrypt() {
    let dedupeStore = MemoryPushDedupeStore()
    let decryptor = MemoryPushDecryptor(
      chatPlaintext: #"{"senderUsername":"Alice","text":"Secret"}"#
    )
    let eventEmitter = MemoryPushPreviewEventEmitter()
    let resolver = NotificationPreviewResolver(
      keyReader: MemoryPushKeyReader([
        PushSharedKeyNames.identityMlKemSecretKey: "chat-secret",
      ]),
      decryptor: decryptor,
      dedupeStore: dedupeStore,
      eventEmitter: eventEmitter
    )
    let userInfo: [String: Any] = [
      "type": "new_message",
      "sender_id": "peer-alice",
      "message_id": "msg-1",
      "kem": "kem",
      "ciphertext": "ciphertext",
      "nonce": "nonce",
    ]

    let first = resolver.resolve(
      userInfo: userInfo,
      fallbackTitle: "New Message",
      fallbackBody: "You have a new message"
    )
    let second = resolver.resolve(
      userInfo: userInfo,
      fallbackTitle: "New Message",
      fallbackBody: "You have a new message"
    )

    XCTAssertTrue(first.didDecrypt)
    XCTAssertFalse(second.didDecrypt)
    XCTAssertEqual(second.reason, "duplicate_message")
    XCTAssertEqual(second.title, "New Message")
    XCTAssertEqual(second.body, "You have a new message")
    XCTAssertEqual(decryptor.chatCalls, 1)
    XCTAssertEqual(eventEmitter.events.count, 2)
    XCTAssertEqual(eventEmitter.events[0].event, "PUSH_NSE_DECRYPT_OK")
    XCTAssertEqual(eventEmitter.events[1].event, "PUSH_NSE_DECRYPT_FAIL")
    XCTAssertEqual(
      eventEmitter.events[1].details,
      ["kind": "chat", "reason": "duplicate_message"]
    )
  }

  func testGIRD006DuplicateGroupMessageIdKeepsFallbackAndSkipsSecondDecrypt() {
    let dedupeStore = MemoryPushDedupeStore()
    let decryptor = MemoryPushDecryptor(
      groupPlaintext: #"{"senderUsername":"Alice","text":"","media":[{"mediaType":"image"}]}"#
    )
    let eventEmitter = MemoryPushPreviewEventEmitter()
    let resolver = NotificationPreviewResolver(
      keyReader: MemoryPushKeyReader([
        PushSharedKeyNames.groupKey(groupId: "group-team", keyEpoch: 7): "group-secret",
      ]),
      decryptor: decryptor,
      dedupeStore: dedupeStore,
      eventEmitter: eventEmitter
    )
    let userInfo: [String: Any] = [
      "type": "group_message",
      "groupId": "group-team",
      "message_id": "group-msg-1",
      "keyEpoch": "7",
      "ciphertext": "ciphertext",
      "nonce": "nonce",
    ]

    let first = resolver.resolve(
      userInfo: userInfo,
      fallbackTitle: "New Message",
      fallbackBody: "You have a new message"
    )
    let second = resolver.resolve(
      userInfo: userInfo,
      fallbackTitle: "New Message",
      fallbackBody: "You have a new message"
    )

    XCTAssertTrue(first.didDecrypt)
    XCTAssertEqual(first.body, "Alice: Photo")
    XCTAssertEqual(first.threadIdentifier, "group-team")
    XCTAssertFalse(second.didDecrypt)
    XCTAssertEqual(second.reason, "duplicate_message")
    XCTAssertEqual(second.title, "New Message")
    XCTAssertEqual(second.body, "You have a new message")
    XCTAssertEqual(decryptor.groupCalls, 1)
    XCTAssertEqual(eventEmitter.events.count, 2)
    XCTAssertEqual(eventEmitter.events[0].event, "PUSH_NSE_DECRYPT_OK")
    XCTAssertEqual(eventEmitter.events[1].event, "PUSH_NSE_DECRYPT_FAIL")
    XCTAssertEqual(
      eventEmitter.events[1].details,
      ["kind": "group", "reason": "duplicate_message"]
    )
  }

  func testGIRD006RemintedGroupImageMessageIdDecryptsAsIndependentNotification() {
    let dedupeStore = MemoryPushDedupeStore()
    let decryptor = MemoryPushDecryptor(
      groupPlaintext: #"{"senderUsername":"Alice","text":"","media":[{"mediaType":"image"}]}"#
    )
    let resolver = NotificationPreviewResolver(
      keyReader: MemoryPushKeyReader([
        PushSharedKeyNames.groupKey(groupId: "group-team", keyEpoch: 7): "group-secret",
      ]),
      decryptor: decryptor,
      dedupeStore: dedupeStore
    )

    let first = resolver.resolve(
      userInfo: [
        "type": "group_message",
        "groupId": "group-team",
        "message_id": "group-msg-1",
        "keyEpoch": "7",
        "ciphertext": "ciphertext",
        "nonce": "nonce",
      ],
      fallbackTitle: "New Message",
      fallbackBody: "You have a new message"
    )
    let reminted = resolver.resolve(
      userInfo: [
        "type": "group_message",
        "groupId": "group-team",
        "message_id": "group-msg-2",
        "keyEpoch": "7",
        "ciphertext": "ciphertext",
        "nonce": "nonce",
      ],
      fallbackTitle: "New Message",
      fallbackBody: "You have a new message"
    )

    XCTAssertTrue(first.didDecrypt)
    XCTAssertTrue(reminted.didDecrypt)
    XCTAssertEqual(first.body, "Alice: Photo")
    XCTAssertEqual(reminted.body, "Alice: Photo")
    XCTAssertEqual(first.threadIdentifier, "group-team")
    XCTAssertEqual(reminted.threadIdentifier, "group-team")
    XCTAssertEqual(decryptor.groupCalls, 2)
  }

  func testDecryptTelemetryDoesNotIncludePlaintextOrSender() {
    let eventEmitter = MemoryPushPreviewEventEmitter()
    let resolver = NotificationPreviewResolver(
      keyReader: MemoryPushKeyReader([
        PushSharedKeyNames.identityMlKemSecretKey: "chat-secret",
      ]),
      decryptor: MemoryPushDecryptor(
        chatPlaintext: #"{"senderUsername":"Alice","text":"UltraSecretCanary"}"#
      ),
      dedupeStore: MemoryPushDedupeStore(),
      eventEmitter: eventEmitter
    )

    let result = resolver.resolve(
      userInfo: [
        "type": "new_message",
        "sender_id": "peer-alice",
        "message_id": "msg-1",
        "kem": "kem",
        "ciphertext": "ciphertext",
        "nonce": "nonce",
      ],
      fallbackTitle: "New Message",
      fallbackBody: "You have a new message"
    )

    XCTAssertTrue(result.didDecrypt)
    XCTAssertEqual(result.title, "Alice")
    XCTAssertEqual(result.body, "UltraSecretCanary")

    let encodedEvents = eventEmitter.events
      .map { "\($0.event):\($0.details)" }
      .joined(separator: "\n")
    XCTAssertFalse(encodedEvents.contains("Alice"))
    XCTAssertFalse(encodedEvents.contains("UltraSecretCanary"))
  }

  func testPreviewBodyMatchesDartDescriptorsAndCap() {
    XCTAssertEqual(pushPreviewBody(text: "", media: [["mediaType": "image"]]), "Photo")
    XCTAssertEqual(pushPreviewBody(text: "", media: [["mediaType": "audio"]]), "Voice message")
    XCTAssertEqual(
      pushPreviewBody(
        text: "",
        media: [["mediaType": "image"], ["mediaType": "video"]]
      ),
      "Media"
    )
    XCTAssertEqual(pushPreviewBody(text: String(repeating: "a", count: 180), media: nil).count, 140)
  }

  private func loadFixture(_ name: String) throws -> [String: Any] {
    let iosRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    let appRoot = iosRoot.deletingLastPathComponent()
    let url = appRoot
      .appendingPathComponent("test/features/push/fixtures")
      .appendingPathComponent("\(name).json")
    let data = try Data(contentsOf: url)
    let object = try JSONSerialization.jsonObject(with: data)
    return try XCTUnwrap(object as? [String: Any])
  }

  /// Loads the repo-root test_fixtures/si5_dedupe_keys.json array shared with the
  /// Dart gate test (the single source of truth for cross-process dedupe keys).
  private func loadDedupeKeyFixture() throws -> [[String: Any]] {
    let iosRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    let appRoot = iosRoot.deletingLastPathComponent()
    let url = appRoot
      .appendingPathComponent("test_fixtures")
      .appendingPathComponent("si5_dedupe_keys.json")
    let data = try Data(contentsOf: url)
    let object = try JSONSerialization.jsonObject(with: data)
    return try XCTUnwrap(object as? [[String: Any]])
  }

  private func fixturePlaintextJSON(_ fixture: [String: Any]) throws -> String {
    let plaintext = try XCTUnwrap(fixture["plaintext"])
    let data = try JSONSerialization.data(withJSONObject: plaintext)
    return try XCTUnwrap(String(data: data, encoding: .utf8))
  }

  private func jsonString(_ object: [String: Any]) throws -> String {
    let data = try JSONSerialization.data(withJSONObject: object)
    return try XCTUnwrap(String(data: data, encoding: .utf8))
  }
}

private struct PushPreviewEventRecord {
  let event: String
  let details: [String: String]
}

private final class MemoryPushKeyReader: PushKeyReading {
  private let values: [String: String]

  init(_ values: [String: String]) {
    self.values = values
  }

  func readString(key: String) -> String? {
    values[key]
  }
}

private final class MemoryPushDecryptor: PushPayloadDecrypting {
  private let chatPlaintext: String?
  private let groupPlaintext: String?

  private(set) var chatCalls = 0
  private(set) var groupCalls = 0
  private(set) var lastChatSecretKey: String?
  private(set) var lastGroupKey: String?

  init(chatPlaintext: String? = nil, groupPlaintext: String? = nil) {
    self.chatPlaintext = chatPlaintext
    self.groupPlaintext = groupPlaintext
  }

  func decryptOneToOne(
    secretKey: String,
    kem: String,
    ciphertext: String,
    nonce: String
  ) throws -> String {
    chatCalls += 1
    lastChatSecretKey = secretKey
    return chatPlaintext ?? "{}"
  }

  func decryptGroup(
    groupKey: String,
    ciphertext: String,
    nonce: String
  ) throws -> String {
    groupCalls += 1
    lastGroupKey = groupKey
    return groupPlaintext ?? "{}"
  }
}

private final class MemoryPushPreviewEventEmitter: PushPreviewEventEmitting {
  private(set) var events: [PushPreviewEventRecord] = []

  func emit(event: String, details: [String: String]) {
    events.append(PushPreviewEventRecord(event: event, details: details))
  }
}

private final class MemoryPushDedupeStore: PushDedupeStoring {
  private var claimed = Set<String>()

  func claim(type: String, messageId: String) -> Bool {
    claimed.insert("\(type):\(messageId)").inserted
  }
}
