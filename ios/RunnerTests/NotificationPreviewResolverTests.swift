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
    XCTAssertEqual(result.title, "New Message")
    XCTAssertEqual(result.body, "Alice: Hello secret")
    XCTAssertEqual(result.threadIdentifier, "group-team")
    XCTAssertEqual(decryptor.groupCalls, 1)
    XCTAssertEqual(decryptor.lastGroupKey, "group-secret")
    XCTAssertEqual(eventEmitter.events.count, 1)
    XCTAssertEqual(eventEmitter.events[0].event, "PUSH_NSE_DECRYPT_OK")
    XCTAssertEqual(eventEmitter.events[0].details, ["kind": "group"])
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
