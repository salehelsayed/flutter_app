import CryptoKit
import Security
import UserNotifications
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
    let previewEvents = eventEmitter.events.filter {
      $0.event.hasPrefix("PUSH_NSE_DECRYPT_")
    }
    XCTAssertEqual(previewEvents.count, 1)
    XCTAssertEqual(previewEvents[0].event, "PUSH_NSE_DECRYPT_OK")
    XCTAssertEqual(previewEvents[0].details, ["kind": "chat"])
  }

  func testPrivateMediaPreviewIsGenericForSupportedLocalesAndMalformedPolicy() throws {
    let routeData: [String: Any] = [
      "type": "new_message",
      "sender_id": "peer-alice",
      "message_id": "private-message",
      "kem": "kem",
      "ciphertext": "ciphertext",
      "nonce": "nonce",
    ]
    let cases: [(locale: String, expected: String, policy: Any)] = [
      ("en-US", "Private media", ["version": 1, "mode": "protected"]),
      ("de-DE", "Private Medien", ["version": 1, "mode": "view_once"]),
      ("ar", "وسائط خاصة", ["version": 1, "mode": "disappearing"]),
      ("en-GB", "Private media", ["version": 99, "mode": "future"]),
      ("en-US", "Private media", "malformed"),
      ("en-US", "Private media", NSNull()),
    ]

    for item in cases {
      let plaintextData = try JSONSerialization.data(withJSONObject: [
        "id": "private-message",
        "senderPeerId": "peer-alice",
        "senderUsername": "Alice",
        "text": "do not reveal this secret",
        "caption": "do not reveal this caption",
        "media": [[
          "mediaType": "image",
          "fileName": "secret-photo.jpg",
        ]],
        "privateMedia": item.policy,
      ])
      let plaintext = try XCTUnwrap(
        String(data: plaintextData, encoding: .utf8)
      )
      let resolver = NotificationPreviewResolver(
        keyReader: MemoryPushKeyReader([
          PushSharedKeyNames.identityMlKemSecretKey: "chat-secret",
        ]),
        decryptor: MemoryPushDecryptor(chatPlaintext: plaintext),
        dedupeStore: MemoryPushDedupeStore(),
        localeIdentifierProvider: { item.locale }
      )

      let result = resolver.resolve(
        userInfo: routeData,
        fallbackTitle: "New Message",
        fallbackBody: "You have a new message"
      )

      XCTAssertTrue(result.didDecrypt, "locale=\(item.locale)")
      XCTAssertEqual(result.reason, "chat", "locale=\(item.locale)")
      XCTAssertEqual(result.title, "Alice", "locale=\(item.locale)")
      XCTAssertEqual(result.body, item.expected, "locale=\(item.locale)")
      XCTAssertFalse(result.body.contains("secret"), "locale=\(item.locale)")
      XCTAssertFalse(result.body.contains("Photo"), "locale=\(item.locale)")
    }
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
    let previewEvents = eventEmitter.events.filter {
      $0.event.hasPrefix("PUSH_NSE_DECRYPT_")
    }
    XCTAssertEqual(previewEvents.count, 1)
    XCTAssertEqual(previewEvents[0].event, "PUSH_NSE_DECRYPT_OK")
    XCTAssertEqual(previewEvents[0].details, ["kind": "group"])
  }

  func testGroupPrivateMediaPreviewIsGenericForAnnouncementsAndMalformedPolicy()
    throws
  {
    let cases: [(locale: String, expected: String, fields: [String: Any])] = [
      (
        "en-US",
        "New private media",
        [
          "mediaPolicyVersion": 1,
          "mediaLifecycle": "viewOnce",
          "mediaDurationSeconds": NSNull(),
          "mediaProtected": true,
        ]
      ),
      (
        "de-DE",
        "Neue private Medien",
        [
          "extra": [
            "groupName": "SECRET announcement title",
            "mediaPolicyVersion": 1,
            "mediaLifecycle": "disappearing",
            "mediaDurationSeconds": 3600,
            "mediaProtected": true,
          ],
        ]
      ),
      (
        "ar",
        "وسائط خاصة جديدة",
        ["mediaPolicyVersion": 1]
      ),
      (
        "en-GB",
        "New private media",
        [
          "mediaPolicyVersion": "future",
          "mediaLifecycle": "futureMode",
          "mediaDurationSeconds": "SECRET duration",
          "mediaProtected": "true",
        ]
      ),
    ]

    for (index, item) in cases.enumerated() {
      var payload: [String: Any] = [
        "groupId": "group-team",
        "messageId": "private-announcement-\(index)",
        "senderPeerId": "peer-alice",
        "groupName": "SECRET announcement title",
        "senderUsername": "SECRET admin name",
        "text": "SECRET private announcement caption",
        "media": [[
          "mediaType": "video",
          "fileName": "SECRET-private-announcement.mp4",
        ]],
      ]
      for (key, value) in item.fields {
        payload[key] = value
      }
      let plaintext = try jsonString(payload)
      let resolver = NotificationPreviewResolver(
        keyReader: MemoryPushKeyReader([
          PushSharedKeyNames.groupKey(groupId: "group-team", keyEpoch: 7):
            "group-secret",
        ]),
        decryptor: MemoryPushDecryptor(groupPlaintext: plaintext),
        dedupeStore: MemoryPushDedupeStore(),
        localeIdentifierProvider: { item.locale }
      )

      let result = resolver.resolve(
        userInfo: [
          "type": "group_message",
          "groupId": "group-team",
          "sender_transport_peer_id": "transport-alice",
          "message_id": "private-announcement-\(index)",
          "keyEpoch": "7",
          "ciphertext": "ciphertext",
          "nonce": "nonce-\(index)",
        ],
        fallbackTitle: "New Message",
        fallbackBody: "You have a new message"
      )

      XCTAssertTrue(result.didDecrypt, "locale=\(item.locale)")
      XCTAssertEqual(result.reason, "group", "locale=\(item.locale)")
      XCTAssertEqual(result.title, "Mknoon", "locale=\(item.locale)")
      XCTAssertEqual(result.body, item.expected, "locale=\(item.locale)")
      XCTAssertEqual(result.threadIdentifier, "group-team")
      let visible = "\(result.title)|\(result.body)"
      XCTAssertFalse(visible.contains("SECRET"), "locale=\(item.locale)")
      XCTAssertFalse(visible.contains("viewOnce"), "locale=\(item.locale)")
      XCTAssertFalse(visible.contains("futureMode"), "locale=\(item.locale)")
      XCTAssertFalse(visible.contains("video"), "locale=\(item.locale)")
    }
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
      PushSharedKeyNames.groupReactionContexts: try ordinaryGroupContextsJSON(
        groupId: "group-team",
        groupName: "Team Chat",
        groupType: "chat",
        senderTransportPeerId: "transport-alice",
        senderRole: "writer",
        muted: true
      ),
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
    XCTAssertFalse(result.markAsShown)
    XCTAssertFalse(result.didDecrypt)
    XCTAssertEqual(result.reason, "group_recipient_policy_rejected")
    // Mute short-circuits before decrypt — no plaintext is touched.
    XCTAssertEqual(decryptor.groupCalls, 0)
    // Generic fallback content (no decrypted preview leaks for a muted group).
    XCTAssertEqual(result.title, "Mknoon")
    XCTAssertEqual(result.body, "New message")
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
    XCTAssertEqual(result.title, "Team Chat")
    XCTAssertEqual(result.body, "New message")
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
      if let eventId = testCase["reactionEventId"] as? String,
         let expectedIdentity = testCase["expectedReactionIdentity"] as? String {
        let identity = boundedReactionNotificationIdentity(eventId: eventId)
        XCTAssertEqual(identity, expectedIdentity, description)
        XCTAssertLessThanOrEqual(identity.utf8.count, 64, description)
      }
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

  func testKeychainReaderUsesEntitledAccessGroupAndRealSecurityQueryKeys() {
    let query = KeychainPushKeyReader().readQuery(key: "projection-key")

    XCTAssertEqual(
      query[kSecAttrAccessGroup as String] as? String,
      "397R9Q4WMX.group.com.mknoon.app.share"
    )
    XCTAssertEqual(
      query[kSecAttrAccessGroup as String] as? String,
      mknoonSharedKeychainAccessGroupIdentifier
    )
    XCTAssertEqual(
      query[kSecClass as String] as? String,
      kSecClassGenericPassword as String
    )
    XCTAssertEqual(query[kSecAttrAccount as String] as? String, "projection-key")
    XCTAssertEqual(
      query[kSecAttrService as String] as? String,
      mknoonFlutterSecureStorageService
    )
    XCTAssertEqual(query[kSecReturnData as String] as? Bool, true)
    XCTAssertEqual(
      query[kSecMatchLimit as String] as? String,
      kSecMatchLimitOne as String
    )
  }

  func testAppGroupPushEnvelopeStoreUsesInjectiveNonceFileNames() throws {
    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("push-envelope-\(UUID().uuidString)")
    let store = AppGroupPushEnvelopeStore(directory: dir)
    let base64Nonce = "a+b/c="
    let sanitizedCollision = "a_b_c_"

    XCTAssertEqual(
      AppGroupPushEnvelopeStore.fileName(forNonce: base64Nonce),
      "nonce-v1-612b622f633d.json"
    )
    XCTAssertEqual(
      AppGroupPushEnvelopeStore.fileName(forNonce: sanitizedCollision),
      "nonce-v1-615f625f635f.json"
    )
    XCTAssertNotEqual(
      AppGroupPushEnvelopeStore.fileName(forNonce: base64Nonce),
      AppGroupPushEnvelopeStore.fileName(forNonce: sanitizedCollision)
    )

    XCTAssertTrue(store.stage(userInfo: [
      "type": "new_message",
      "sender_id": "peer-alice",
      "message_id": "msg-1",
      "kem": "kem-1",
      "ciphertext": "cipher-1",
      "nonce": base64Nonce,
    ]))
    XCTAssertTrue(store.stage(userInfo: [
      "type": "new_message",
      "sender_id": "peer-alice",
      "message_id": "msg-2",
      "kem": "kem-2",
      "ciphertext": "cipher-2",
      "nonce": sanitizedCollision,
    ]))

    let contents = try FileManager.default.contentsOfDirectory(atPath: dir.path)
    XCTAssertEqual(Set(contents), [
      "nonce-v1-612b622f633d.json",
      "nonce-v1-615f625f635f.json",
    ])

    let firstData = try Data(
      contentsOf: dir.appendingPathComponent(
        AppGroupPushEnvelopeStore.fileName(forNonce: base64Nonce)
      )
    )
    let firstJSON = try XCTUnwrap(
      JSONSerialization.jsonObject(with: firstData) as? [String: Any]
    )
    XCTAssertEqual(firstJSON["nonce"] as? String, base64Nonce)

    XCTAssertTrue(store.clear(nonce: base64Nonce))
    let contentsAfterClear = try FileManager.default.contentsOfDirectory(
      atPath: dir.path
    )
    XCTAssertEqual(Set(contentsAfterClear), [
      "nonce-v1-615f625f635f.json",
    ])
    XCTAssertFalse(
      FileManager.default.fileExists(
        atPath: dir.appendingPathComponent(
          AppGroupPushEnvelopeStore.fileName(forNonce: base64Nonce)
        ).path
      )
    )
    XCTAssertTrue(
      FileManager.default.fileExists(
        atPath: dir.appendingPathComponent(
          AppGroupPushEnvelopeStore.fileName(forNonce: sanitizedCollision)
        ).path
      )
    )

    try? FileManager.default.removeItem(at: dir)
  }

  func testDecryptsNativeV3GroupPreviewFromEncryptedExtra() throws {
    let plaintext = try jsonString([
      "groupId": "group-team",
      "senderPeerId": "peer-alice",
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
        "sender_transport_peer_id": "transport-alice",
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
      "groupId": "group-team",
      "messageId": "native-msg-1",
      "senderPeerId": "peer-alice",
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
        "sender_transport_peer_id": "transport-alice",
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
      "groupId": "group-team",
      "senderPeerId": "peer-alice",
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
      "sender_transport_peer_id": "transport-alice",
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
    XCTAssertEqual(result.title, "Team Chat")
    XCTAssertEqual(result.body, "A member joined the group")
    XCTAssertEqual(result.threadIdentifier, "group-team")
    for forbidden in ["{", "}", "__sys", "peerId", "12D3"] {
      XCTAssertFalse(result.body.contains(forbidden))
    }
  }

  func testSanitizesUnknownGroupSystemPreview() throws {
    let plaintext = try jsonString([
      "groupId": "group-team",
      "senderPeerId": "peer-alice",
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
      "sender_transport_peer_id": "transport-alice",
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
    XCTAssertEqual(result.title, "Team Chat")
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
    XCTAssertEqual(result.title, "Alice")
    XCTAssertEqual(result.body, "New message")
    XCTAssertEqual(result.threadIdentifier, "peer-alice")
    XCTAssertTrue(result.suppress)
    XCTAssertFalse(result.markAsShown)
    XCTAssertEqual(decryptor.chatCalls, 0)
    let previewEvents = eventEmitter.events.filter {
      $0.event.hasPrefix("PUSH_NSE_DECRYPT_")
    }
    XCTAssertEqual(previewEvents.count, 1)
    XCTAssertEqual(previewEvents[0].event, "PUSH_NSE_DECRYPT_FAIL")
    XCTAssertEqual(
      previewEvents[0].details,
      ["kind": "chat", "reason": "missing_chat_secret"]
    )
  }

  func testDuplicateMessageClaimsOnlyAfterSecondCopyPassesParity() {
    let dedupeStore = MemoryPushDedupeStore()
    let decryptor = MemoryPushDecryptor(
      chatPlaintext: #"{"id":"msg-1","senderPeerId":"peer-alice","senderUsername":"Alice","text":"Secret"}"#
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
    XCTAssertEqual(second.title, "Alice")
    XCTAssertEqual(second.body, "Secret")
    XCTAssertTrue(second.suppress)
    XCTAssertFalse(second.markAsShown)
    XCTAssertEqual(decryptor.chatCalls, 2)
    let previewEvents = eventEmitter.events.filter {
      $0.event.hasPrefix("PUSH_NSE_DECRYPT_")
    }
    XCTAssertEqual(previewEvents.count, 2)
    XCTAssertEqual(previewEvents[0].event, "PUSH_NSE_DECRYPT_OK")
    XCTAssertEqual(previewEvents[1].event, "PUSH_NSE_DECRYPT_OK")
  }

  func testGIRD006DuplicateGroupMessageIdClaimsOnlyAfterParity() {
    let dedupeStore = MemoryPushDedupeStore()
    let decryptor = MemoryPushDecryptor(
      groupPlaintext: #"{"groupId":"group-team","messageId":"group-msg-1","senderPeerId":"peer-alice","senderUsername":"Alice","text":"","media":[{"mediaType":"image"}]}"#
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
      "sender_transport_peer_id": "transport-alice",
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
    XCTAssertEqual(second.title, "Team Chat")
    XCTAssertEqual(second.body, "Alice: Photo")
    XCTAssertTrue(second.suppress)
    XCTAssertFalse(second.markAsShown)
    XCTAssertEqual(decryptor.groupCalls, 2)
    let previewEvents = eventEmitter.events.filter {
      $0.event.hasPrefix("PUSH_NSE_DECRYPT_")
    }
    XCTAssertEqual(previewEvents.count, 2)
    XCTAssertEqual(previewEvents[0].event, "PUSH_NSE_DECRYPT_OK")
    XCTAssertEqual(previewEvents[1].event, "PUSH_NSE_DECRYPT_OK")
  }

  func testGIRD006RemintedGroupImageMessageIdDecryptsAsIndependentNotification() {
    let dedupeStore = MemoryPushDedupeStore()
    let decryptor = MemoryPushDecryptor(
      groupPlaintext: #"{"groupId":"group-team","messageId":"group-msg-1","senderPeerId":"peer-alice","senderUsername":"Alice","text":"","media":[{"mediaType":"image"}]}"#
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
        "sender_transport_peer_id": "transport-alice",
        "message_id": "group-msg-1",
        "keyEpoch": "7",
        "ciphertext": "ciphertext",
        "nonce": "nonce",
      ],
      fallbackTitle: "New Message",
      fallbackBody: "You have a new message"
    )
    decryptor.groupPlaintext = #"{"groupId":"group-team","messageId":"group-msg-2","senderPeerId":"peer-alice","senderUsername":"Alice","text":"","media":[{"mediaType":"image"}]}"#
    let reminted = resolver.resolve(
      userInfo: [
        "type": "group_message",
        "groupId": "group-team",
        "sender_transport_peer_id": "transport-alice",
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
        chatPlaintext: #"{"id":"msg-1","senderPeerId":"peer-alice","senderUsername":"Alice","text":"UltraSecretCanary"}"#
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

  func testOrdinaryDirectRecipientPolicyFailsClosedBeforeCryptoClaimOrTone() throws {
    let eligibleContacts = try ordinaryDirectContactsJSON()
    let blockedContacts = try ordinaryDirectContactsJSON(blocked: true)
    let archivedContacts = try ordinaryDirectContactsJSON(archived: true)
    let selfContacts = try ordinaryDirectContactsJSON(
      peerId: "peer-self",
      username: "Local Account"
    )
    let identity = try ordinaryLocalIdentityContextsJSON()
    let conflictingIdentity = try ordinaryLocalIdentityContextsJSON(
      conflictingLegacyIdentity: true
    )
    let cases: [(String, String, String?, String)] = [
      (
        "unknown",
        #"{"version":1,"localAccountPeerId":"peer-self","contacts":{}}"#,
        identity,
        "peer-alice"
      ),
      ("blocked", blockedContacts, identity, "peer-alice"),
      ("archived", archivedContacts, identity, "peer-alice"),
      ("self", selfContacts, identity, "peer-self"),
      ("missing_identity", eligibleContacts, nil, "peer-alice"),
      ("conflicting_identity", eligibleContacts, conflictingIdentity, "peer-alice"),
    ]

    for item in cases {
      var values: [String: String] = [
        PushSharedKeyNames.identityMlKemSecretKey: "chat-secret",
        PushSharedKeyNames.directReactionContacts: item.1,
        PushSharedKeyNames.directReactionAuthoredTargets:
          try ordinaryDirectTargetsJSON(),
      ]
      if let contexts = item.2 {
        values[PushSharedKeyNames.groupReactionContexts] = contexts
      }
      let decryptor = MemoryPushDecryptor(
        chatPlaintext: #"{"id":"msg-policy","senderPeerId":"peer-alice","text":"secret"}"#
      )
      let dedupe = MemoryPushDedupeStore()
      let tone = MemoryPushToneReservationStore(outcomes: [.reserved])
      let resolver = NotificationPreviewResolver(
        keyReader: MemoryPushKeyReader(
          values,
          includeDefaultOrdinaryProjection: false
        ),
        decryptor: decryptor,
        dedupeStore: dedupe,
        toneLeaseStore: tone
      )

      let result = resolver.resolve(
        userInfo: [
          "type": "new_message",
          "sender_id": item.3,
          "message_id": "msg-policy",
          "kem": "kem",
          "ciphertext": "ciphertext",
          "nonce": "nonce",
        ],
        fallbackTitle: "FORGED TITLE",
        fallbackBody: "FORGED BODY"
      )

      XCTAssertTrue(result.suppress, item.0)
      XCTAssertFalse(result.markAsShown, item.0)
      XCTAssertEqual(result.reason, "chat_recipient_policy_rejected", item.0)
      XCTAssertEqual(decryptor.chatCalls, 0, item.0)
      XCTAssertTrue(dedupe.claims.isEmpty, item.0)
      XCTAssertTrue(tone.conversations.isEmpty, item.0)
    }
  }

  func testOrdinaryDirectRejectsMissingOrCrossAccountDocumentsBeforeSideEffects()
    throws
  {
    let cases: [(String, String, String)] = [
      (
        "legacy_contacts_missing_account",
        #"{"version":1,"contacts":{"peer-alice":{"username":"Old Alice","blocked":false,"archived":false}}}"#,
        try ordinaryDirectTargetsJSON()
      ),
      (
        "old_contacts_and_targets_with_new_recipient_identity",
        try ordinaryDirectContactsJSON(localAccountPeerId: "peer-old"),
        try ordinaryDirectTargetsJSON(localAccountPeerId: "peer-old")
      ),
    ]

    for item in cases {
      let decryptor = MemoryPushDecryptor(
        chatPlaintext: #"{"id":"msg-account-switch","senderPeerId":"peer-alice","text":"secret"}"#
      )
      let dedupe = MemoryPushDedupeStore()
      let tone = MemoryPushToneReservationStore(outcomes: [.reserved])
      let result = NotificationPreviewResolver(
        keyReader: MemoryPushKeyReader(
          [
            PushSharedKeyNames.identityMlKemSecretKey: "chat-secret",
            PushSharedKeyNames.directReactionContacts: item.1,
            PushSharedKeyNames.directReactionAuthoredTargets: item.2,
            PushSharedKeyNames.groupReactionContexts:
              try ordinaryLocalIdentityContextsJSON(),
          ],
          includeDefaultOrdinaryProjection: false
        ),
        decryptor: decryptor,
        dedupeStore: dedupe,
        toneLeaseStore: tone
      ).resolve(
        userInfo: [
          "type": "new_message",
          "sender_id": "peer-alice",
          "message_id": "msg-account-switch",
          "kem": "kem",
          "ciphertext": "ciphertext",
          "nonce": "nonce",
        ],
        fallbackTitle: "FORGED TITLE",
        fallbackBody: "FORGED BODY"
      )

      XCTAssertTrue(result.suppress, item.0)
      XCTAssertFalse(result.markAsShown, item.0)
      XCTAssertEqual(result.reason, "chat_recipient_policy_rejected", item.0)
      XCTAssertEqual(decryptor.chatCalls, 0, item.0)
      XCTAssertTrue(dedupe.claims.isEmpty, item.0)
      XCTAssertTrue(tone.conversations.isEmpty, item.0)
    }
  }

  func testOrdinaryDirectUsesTrustedCopyAndClaimsToneOnlyAfterParity() throws {
    let contacts = try ordinaryDirectContactsJSON(username: "Trusted Alice")
    let contexts = try ordinaryLocalIdentityContextsJSON()
    let values = [
      PushSharedKeyNames.identityMlKemSecretKey: "chat-secret",
      PushSharedKeyNames.directReactionContacts: contacts,
      PushSharedKeyNames.groupReactionContexts: contexts,
    ]
    let decryptor = MemoryPushDecryptor(
      chatPlaintext: #"{"id":"msg-trusted","senderPeerId":"peer-alice","senderUsername":"FORGED NAME","text":"Secret body"}"#
    )
    let dedupe = MemoryPushDedupeStore()
    let tone = MemoryPushToneReservationStore(outcomes: [.reserved])
    let resolver = NotificationPreviewResolver(
      keyReader: MemoryPushKeyReader(
        values,
        includeDefaultOrdinaryProjection: false
      ),
      decryptor: decryptor,
      dedupeStore: dedupe,
      toneLeaseStore: tone
    )

    let result = resolver.resolve(
      userInfo: [
        "type": "new_message",
        "sender_id": "peer-alice",
        "message_id": "msg-trusted",
        "kem": "kem",
        "ciphertext": "ciphertext",
        "nonce": "nonce",
      ],
      fallbackTitle: "FORGED TITLE",
      fallbackBody: "FORGED BODY"
    )

    XCTAssertTrue(result.didDecrypt)
    XCTAssertEqual(result.title, "Trusted Alice")
    XCTAssertEqual(result.body, "Secret body")
    XCTAssertEqual(dedupe.claims, ["new_message:msg-trusted"])
    XCTAssertEqual(tone.conversations, ["peer-alice"])
    let reservation = try XCTUnwrap(
      result.toneReservation as? MemoryPushToneReservation
    )
    XCTAssertEqual(reservation.commitCalls, 0)
    XCTAssertTrue(reservation.commit(now: Date()))
    XCTAssertEqual(reservation.commitCalls, 1)

    let mismatchDedupe = MemoryPushDedupeStore()
    let mismatchTone = MemoryPushToneReservationStore(outcomes: [.reserved])
    let mismatchDecryptor = MemoryPushDecryptor(
      chatPlaintext: #"{"id":"msg-trusted","senderPeerId":"peer-mallory","text":"secret"}"#
    )
    let mismatch = NotificationPreviewResolver(
      keyReader: MemoryPushKeyReader(
        values,
        includeDefaultOrdinaryProjection: false
      ),
      decryptor: mismatchDecryptor,
      dedupeStore: mismatchDedupe,
      toneLeaseStore: mismatchTone
    ).resolve(
      userInfo: [
        "type": "new_message",
        "sender_id": "peer-alice",
        "message_id": "msg-trusted",
        "kem": "kem",
        "ciphertext": "ciphertext",
        "nonce": "nonce",
      ],
      fallbackTitle: "FORGED TITLE",
      fallbackBody: "FORGED BODY"
    )
    XCTAssertTrue(mismatch.suppress)
    XCTAssertFalse(mismatch.markAsShown)
    XCTAssertEqual(mismatch.reason, "chat_plaintext_parity_mismatch")
    XCTAssertTrue(mismatchDedupe.claims.isEmpty)
    XCTAssertTrue(mismatchTone.conversations.isEmpty)
  }

  func testOrdinaryRouteOnlyUsesRecipientCopyWithoutDecrypting() throws {
    let directDedupe = MemoryPushDedupeStore()
    let directTone = MemoryPushToneReservationStore(outcomes: [.reserved])
    let directDecryptor = MemoryPushDecryptor()
    let direct = NotificationPreviewResolver(
      keyReader: MemoryPushKeyReader([:]),
      decryptor: directDecryptor,
      dedupeStore: directDedupe,
      toneLeaseStore: directTone
    ).resolve(
      userInfo: [
        "type": "new_message",
        "sender_id": "peer-alice",
        "preview_unavailable": "1",
      ],
      fallbackTitle: "FORGED TITLE",
      fallbackBody: "FORGED BODY"
    )
    XCTAssertFalse(direct.didDecrypt)
    XCTAssertFalse(direct.suppress)
    XCTAssertTrue(direct.markAsShown)
    XCTAssertEqual(direct.title, "Alice")
    XCTAssertEqual(direct.body, "New message")
    XCTAssertEqual(directDecryptor.chatCalls, 0)
    XCTAssertTrue(directDedupe.claims.isEmpty)
    XCTAssertEqual(directTone.conversations, ["peer-alice"])

    let groupDedupe = MemoryPushDedupeStore()
    let groupTone = MemoryPushToneReservationStore(outcomes: [.reserved])
    let groupDecryptor = MemoryPushDecryptor()
    let group = NotificationPreviewResolver(
      keyReader: MemoryPushKeyReader(
        [
          PushSharedKeyNames.directReactionContacts: "{corrupt",
          PushSharedKeyNames.directReactionAuthoredTargets: "[]",
          PushSharedKeyNames.groupReactionContexts:
            try ordinaryGroupContextsJSON(
              groupId: "group-team",
              groupName: "Team Chat",
              groupType: "chat",
              senderTransportPeerId: "transport-alice",
              senderRole: "writer"
            ),
        ],
        includeDefaultOrdinaryProjection: false
      ),
      decryptor: groupDecryptor,
      dedupeStore: groupDedupe,
      toneLeaseStore: groupTone
    ).resolve(
      userInfo: [
        "type": "group_message",
        "groupId": "group-team",
        "sender_transport_peer_id": "transport-alice",
        "message_id": "route-only-group",
        "preview_unavailable": "1",
      ],
      fallbackTitle: "FORGED TITLE",
      fallbackBody: "FORGED BODY"
    )
    XCTAssertFalse(group.didDecrypt)
    XCTAssertFalse(group.suppress)
    XCTAssertTrue(group.markAsShown)
    XCTAssertEqual(group.title, "Team Chat")
    XCTAssertEqual(group.body, "Alice: New message")
    XCTAssertEqual(groupDecryptor.groupCalls, 0)
    XCTAssertEqual(groupDedupe.claims, ["group_message:route-only-group"])
    XCTAssertEqual(groupTone.conversations, ["group:group-team"])
  }

  func testOrdinaryRouteOnlyRequiresCanonicalTypeAndRouteKeysBeforeSideEffects() {
    let cases: [(String, [String: Any], String)] = [
      (
        "direct_type_alias",
        [
          "t": "new_message",
          "sender_id": "peer-alice",
          "preview_unavailable": "1",
        ],
        "chat_preview_unavailable_route_rejected"
      ),
      (
        "direct_sender_alias",
        [
          "type": "new_message",
          "s": "peer-alice",
          "preview_unavailable": "1",
        ],
        "chat_preview_unavailable_route_rejected"
      ),
      (
        "group_type_alias",
        [
          "t": "group_message",
          "groupId": "group-team",
          "sender_transport_peer_id": "transport-alice",
          "preview_unavailable": "1",
        ],
        "group_preview_unavailable_route_rejected"
      ),
      (
        "group_id_alias",
        [
          "type": "group_message",
          "group_id": "group-team",
          "sender_transport_peer_id": "transport-alice",
          "preview_unavailable": "1",
        ],
        "group_preview_unavailable_route_rejected"
      ),
    ]

    for item in cases {
      let decryptor = MemoryPushDecryptor()
      let dedupe = MemoryPushDedupeStore()
      let tone = MemoryPushToneReservationStore(outcomes: [.reserved])
      let result = NotificationPreviewResolver(
        keyReader: MemoryPushKeyReader([:]),
        decryptor: decryptor,
        dedupeStore: dedupe,
        toneLeaseStore: tone
      ).resolve(
        userInfo: item.1,
        fallbackTitle: "FORGED TITLE",
        fallbackBody: "FORGED BODY"
      )

      XCTAssertTrue(result.suppress, item.0)
      XCTAssertFalse(result.markAsShown, item.0)
      XCTAssertEqual(result.reason, item.2, item.0)
      XCTAssertEqual(decryptor.chatCalls, 0, item.0)
      XCTAssertEqual(decryptor.groupCalls, 0, item.0)
      XCTAssertTrue(dedupe.claims.isEmpty, item.0)
      XCTAssertTrue(tone.conversations.isEmpty, item.0)
    }
  }

  func testOrdinaryGroupRecipientPolicyRejectsEveryUnauthorizedRouteBeforeSideEffects()
    throws
  {
    let cases: [(String, String, Bool)] = [
      (
        "muted",
        try ordinaryGroupContextsJSON(
          groupId: "group-team",
          groupName: "Trusted Team",
          groupType: "chat",
          senderTransportPeerId: "transport-alice",
          senderRole: "writer",
          muted: true
        ),
        false
      ),
      (
        "archived",
        try ordinaryGroupContextsJSON(
          groupId: "group-team",
          groupName: "Trusted Team",
          groupType: "chat",
          senderTransportPeerId: "transport-alice",
          senderRole: "writer",
          archived: true
        ),
        false
      ),
      (
        "dissolved",
        try ordinaryGroupContextsJSON(
          groupId: "group-team",
          groupName: "Trusted Team",
          groupType: "chat",
          senderTransportPeerId: "transport-alice",
          senderRole: "writer",
          dissolved: true
        ),
        false
      ),
      (
        "missing_local_member",
        try ordinaryGroupContextsJSON(
          groupId: "group-team",
          groupName: "Trusted Team",
          groupType: "chat",
          senderTransportPeerId: "transport-alice",
          senderRole: "writer",
          includeLocalMember: false
        ),
        false
      ),
      (
        "revoked_local_device",
        try ordinaryGroupContextsJSON(
          groupId: "group-team",
          groupName: "Trusted Team",
          groupType: "chat",
          senderTransportPeerId: "transport-alice",
          senderRole: "writer",
          localMemberDeviceIds: ["device-revoked"]
        ),
        false
      ),
      (
        "ambiguous_sender_transport",
        try ordinaryGroupContextsJSON(
          groupId: "group-team",
          groupName: "Trusted Team",
          groupType: "chat",
          senderTransportPeerId: "transport-alice",
          senderRole: "writer",
          duplicateSenderTransport: true
        ),
        false
      ),
      (
        "chat_reader",
        try ordinaryGroupContextsJSON(
          groupId: "group-team",
          groupName: "Trusted Team",
          groupType: "chat",
          senderTransportPeerId: "transport-alice",
          senderRole: "reader"
        ),
        false
      ),
      (
        "announcement_writer",
        try ordinaryGroupContextsJSON(
          groupId: "group-team",
          groupName: "Trusted Announcements",
          groupType: "announcement",
          senderTransportPeerId: "transport-alice",
          senderRole: "writer"
        ),
        false
      ),
      (
        "forbidden_outer_sender_id",
        try ordinaryGroupContextsJSON(
          groupId: "group-team",
          groupName: "Trusted Team",
          groupType: "chat",
          senderTransportPeerId: "transport-alice",
          senderRole: "writer"
        ),
        true
      ),
    ]

    for item in cases {
      let decryptor = MemoryPushDecryptor(
        groupPlaintext: #"{"groupId":"group-team","messageId":"msg-group-policy","senderPeerId":"peer-alice","text":"secret"}"#
      )
      let dedupe = MemoryPushDedupeStore()
      let tone = MemoryPushToneReservationStore(outcomes: [.reserved])
      var userInfo: [String: Any] = [
        "type": "group_message",
        "groupId": "group-team",
        "sender_transport_peer_id": "transport-alice",
        "message_id": "msg-group-policy",
        "keyEpoch": "7",
        "ciphertext": "ciphertext",
        "nonce": "nonce",
      ]
      if item.2 { userInfo["sender_id"] = "peer-alice" }
      let result = NotificationPreviewResolver(
        keyReader: MemoryPushKeyReader([
          PushSharedKeyNames.groupReactionContexts: item.1,
          PushSharedKeyNames.groupKey(groupId: "group-team", keyEpoch: 7):
            "group-secret",
        ]),
        decryptor: decryptor,
        dedupeStore: dedupe,
        toneLeaseStore: tone
      ).resolve(
        userInfo: userInfo,
        fallbackTitle: "FORGED TITLE",
        fallbackBody: "FORGED BODY"
      )

      XCTAssertTrue(result.suppress, item.0)
      XCTAssertFalse(result.markAsShown, item.0)
      XCTAssertEqual(decryptor.groupCalls, 0, item.0)
      XCTAssertTrue(dedupe.claims.isEmpty, item.0)
      XCTAssertTrue(tone.conversations.isEmpty, item.0)
    }
  }

  func testOrdinaryAnnouncementUsesTrustedNamesAndExactParity() throws {
    let contexts = try ordinaryGroupContextsJSON(
      groupId: "group-team",
      groupName: "Trusted Announcements",
      groupType: "announcement",
      senderTransportPeerId: "transport-alice",
      senderRole: "admin"
    )
    let decryptor = MemoryPushDecryptor(
      groupPlaintext: #"{"groupId":"group-team","messageId":"announcement-1","senderPeerId":"peer-alice","groupName":"FORGED GROUP","senderUsername":"FORGED SENDER","text":"Update"}"#
    )
    let dedupe = MemoryPushDedupeStore()
    let tone = MemoryPushToneReservationStore(outcomes: [.reserved])
    let result = NotificationPreviewResolver(
      keyReader: MemoryPushKeyReader(
        [
          PushSharedKeyNames.groupReactionContexts: contexts,
          PushSharedKeyNames.groupKey(groupId: "group-team", keyEpoch: 7):
            "group-secret",
        ],
        includeDefaultOrdinaryProjection: false
      ),
      decryptor: decryptor,
      dedupeStore: dedupe,
      toneLeaseStore: tone
    ).resolve(
      userInfo: [
        "type": "group_message",
        "groupId": "group-team",
        "sender_transport_peer_id": "transport-alice",
        "message_id": "announcement-1",
        "keyEpoch": "7",
        "ciphertext": "ciphertext",
        "nonce": "nonce",
      ],
      fallbackTitle: "FORGED TITLE",
      fallbackBody: "FORGED BODY"
    )

    XCTAssertTrue(result.didDecrypt)
    XCTAssertEqual(result.title, "Trusted Announcements")
    XCTAssertEqual(result.body, "Alice: Update")
    XCTAssertFalse(result.title.contains("FORGED"))
    XCTAssertFalse(result.body.contains("FORGED"))
    XCTAssertEqual(dedupe.claims, ["group_message:announcement-1"])
    XCTAssertEqual(tone.conversations, ["group:group-team"])
  }

  func testReactionUsesTrustedContactAndClaimsOnlyAfterDecryptedParity() throws {
    let eventId = "reaction-event-123"
    let keyReader = MemoryPushKeyReader([
      PushSharedKeyNames.identityMlKemSecretKey: "chat-secret",
      PushSharedKeyNames.directReactionContacts: try reactionContactsJSON(
        username: "Alice",
        blocked: false
      ),
      PushSharedKeyNames.directReactionAuthoredTargets: try reactionTargetsJSON(),
    ])
    let decryptor = MemoryPushDecryptor(
      chatPlaintext: try reactionPlaintextJSON(eventId: eventId)
    )
    let resolver = NotificationPreviewResolver(
      keyReader: keyReader,
      decryptor: decryptor,
      dedupeStore: MemoryPushDedupeStore(),
      toneLeaseStore: MemoryPushToneLeaseStore(results: [true])
    )

    let result = resolver.resolve(
      userInfo: reactionRoute(eventId: eventId),
      fallbackTitle: "New reaction",
      fallbackBody: "Someone reacted to your message"
    )

    XCTAssertTrue(result.didDecrypt)
    XCTAssertEqual(result.reason, "reaction")
    XCTAssertEqual(result.title, "Alice")
    XCTAssertEqual(result.body, "Reacted 👍 to your message")
    XCTAssertEqual(result.threadIdentifier, "peer-alice")
    XCTAssertEqual(result.categoryIdentifier, "MESSAGE_REACTION")
    XCTAssertEqual(
      result.targetContentIdentifier,
      "reaction:813117a606a0d109f3414152f6092e5c33da6c311a4a7736"
    )
    XCTAssertFalse(result.suppress)
    XCTAssertTrue(result.markAsShown)
  }

  func testReactionNotificationBoundaryRestoresSoundOnlyForValidatedAlert() throws {
    let eventId = "reaction-sound-boundary"
    let resolver = NotificationPreviewResolver(
      keyReader: MemoryPushKeyReader([
        PushSharedKeyNames.identityMlKemSecretKey: "chat-secret",
        PushSharedKeyNames.directReactionContacts: try reactionContactsJSON(
          username: "Alice",
          blocked: false
        ),
        PushSharedKeyNames.directReactionAuthoredTargets: try reactionTargetsJSON(),
      ]),
      decryptor: MemoryPushDecryptor(
        chatPlaintext: try reactionPlaintextJSON(eventId: eventId)
      ),
      dedupeStore: MemoryPushDedupeStore(),
      toneLeaseStore: MemoryPushToneLeaseStore(results: [true])
    )

    let valid = resolver.resolve(
      userInfo: reactionRoute(eventId: eventId),
      fallbackTitle: "New reaction",
      fallbackBody: "Someone reacted to your message"
    )
    let validContent = UNMutableNotificationContent()
    validContent.sound = nil // relay fallback is deliberately silent
    if #available(iOS 15.0, *) {
      validContent.interruptionLevel = .passive
    }
    applyNotificationPreviewResult(valid, to: validContent)

    XCTAssertEqual(validContent.sound, UNNotificationSound.default)
    if #available(iOS 15.0, *) {
      XCTAssertEqual(validContent.interruptionLevel, .active)
    }

    let duplicate = resolver.resolve(
      userInfo: reactionRoute(eventId: eventId),
      fallbackTitle: "New reaction",
      fallbackBody: "Someone reacted to your message"
    )
    let duplicateContent = UNMutableNotificationContent()
    duplicateContent.sound = .default
    applyNotificationPreviewResult(duplicate, to: duplicateContent)
    XCTAssertTrue(duplicate.suppress)
    XCTAssertNil(duplicateContent.sound)
    if #available(iOS 15.0, *) {
      XCTAssertEqual(duplicateContent.interruptionLevel, .passive)
    }

    let rejected = NotificationPreviewResolver(
      keyReader: MemoryPushKeyReader([:]),
      decryptor: MemoryPushDecryptor(chatPlaintext: "{}"),
      dedupeStore: MemoryPushDedupeStore()
    ).resolve(
      userInfo: reactionRoute(eventId: "reaction-rejected"),
      fallbackTitle: "New reaction",
      fallbackBody: "Someone reacted to your message"
    )
    let rejectedContent = UNMutableNotificationContent()
    rejectedContent.sound = .default
    applyNotificationPreviewResult(rejected, to: rejectedContent)
    XCTAssertTrue(rejected.suppress)
    XCTAssertNil(rejectedContent.sound)
  }

  func testReactionSharedFixtureUsesProjectionCopyAndLeaksNoPrivateFields() throws {
    let fixture = try loadRepoFixture("one_to_one_reaction_add")
    let routeData = try XCTUnwrap(fixture["routeData"] as? [String: Any])
    let plaintext = try XCTUnwrap(fixture["plaintext"] as? [String: Any])
    let eventId = try XCTUnwrap(fixture["eventId"] as? String)
    let targetMessageId = try XCTUnwrap(
      routeData["target_message_id"] as? String
    )
    let resolver = NotificationPreviewResolver(
      keyReader: MemoryPushKeyReader([
        PushSharedKeyNames.identityMlKemSecretKey: "chat-secret",
        PushSharedKeyNames.directReactionContacts: try reactionContactsJSON(
          username: "Trusted Alice",
          blocked: false
        ),
        PushSharedKeyNames.directReactionAuthoredTargets: try reactionTargetsJSON(
          targetMessageId: targetMessageId
        ),
      ]),
      decryptor: MemoryPushDecryptor(
        chatPlaintext: try jsonString(plaintext)
      ),
      dedupeStore: MemoryPushDedupeStore(),
      toneLeaseStore: MemoryPushToneLeaseStore(results: [true])
    )

    let result = resolver.resolve(
      userInfo: routeData,
      fallbackTitle: "Provider fallback",
      fallbackBody: "Provider body"
    )

    XCTAssertTrue(result.didDecrypt)
    XCTAssertEqual(result.title, "Trusted Alice")
    XCTAssertEqual(result.body, "Reacted 👍 to your message")
    XCTAssertEqual(
      result.targetContentIdentifier,
      boundedReactionNotificationIdentity(eventId: eventId)
    )
    let rendered = "\(result.title)\n\(result.body)"
    XCTAssertFalse(rendered.contains("Original target text"))
    XCTAssertFalse(rendered.contains("fixture-ciphertext-reaction-1"))
    XCTAssertFalse(rendered.contains("Provider fallback"))
    XCTAssertFalse(rendered.contains("actorUsername"))
  }

  func testReactionInvalidFirstCopyDoesNotPoisonLaterValidCopy() throws {
    let eventId = "reaction-retry"
    let decryptor = MemoryPushDecryptor(
      chatPlaintext: try reactionPlaintextJSON(
        eventId: eventId,
        targetMessageId: "forged-target"
      )
    )
    let dedupeStore = MemoryPushDedupeStore()
    let resolver = NotificationPreviewResolver(
      keyReader: MemoryPushKeyReader([
        PushSharedKeyNames.identityMlKemSecretKey: "chat-secret",
        PushSharedKeyNames.directReactionContacts: try reactionContactsJSON(
          username: "Alice",
          blocked: false
        ),
        PushSharedKeyNames.directReactionAuthoredTargets: try reactionTargetsJSON(),
      ]),
      decryptor: decryptor,
      dedupeStore: dedupeStore
    )

    let invalid = resolver.resolve(
      userInfo: reactionRoute(eventId: eventId),
      fallbackTitle: "provider title",
      fallbackBody: "provider body"
    )
    XCTAssertEqual(invalid.reason, "reaction_parity_mismatch")
    XCTAssertTrue(invalid.suppress)
    XCTAssertFalse(invalid.markAsShown)

    decryptor.chatPlaintext = try reactionPlaintextJSON(eventId: eventId)
    let valid = resolver.resolve(
      userInfo: reactionRoute(eventId: eventId),
      fallbackTitle: "provider title",
      fallbackBody: "provider body"
    )
    XCTAssertTrue(valid.didDecrypt)
    XCTAssertEqual(valid.title, "Alice")
    XCTAssertEqual(decryptor.chatCalls, 2)
  }

  func testReactionProjectionEligibilityFailsPassiveBeforeDecrypt() throws {
    let cases: [(name: String, contacts: String, targets: String, reason: String)] = [
      (
        "unknown",
        try jsonString([
          "version": 1,
          "localAccountPeerId": "peer-self",
          "contacts": [:],
        ]),
        try reactionTargetsJSON(),
        "reaction_unknown_contact"
      ),
      (
        "blocked",
        try reactionContactsJSON(username: "Alice", blocked: true),
        try reactionTargetsJSON(),
        "reaction_blocked_contact"
      ),
      (
        "not authored for reactor",
        try reactionContactsJSON(username: "Alice", blocked: false),
        try reactionTargetsJSON(peerId: "peer-other"),
        "reaction_target_not_locally_authored"
      ),
      (
        "legacy account missing",
        try jsonString(["version": 1, "contacts": [:]]),
        try reactionTargetsJSON(),
        "reaction_recipient_projection_rejected"
      ),
      (
        "old direct account with new recipient identity",
        try reactionContactsJSON(
          username: "Old Alice",
          blocked: false,
          localAccountPeerId: "peer-old"
        ),
        try reactionTargetsJSON(localAccountPeerId: "peer-old"),
        "reaction_recipient_projection_rejected"
      ),
    ]

    for testCase in cases {
      let decryptor = MemoryPushDecryptor(
        chatPlaintext: try reactionPlaintextJSON(eventId: "event-1")
      )
      let resolver = NotificationPreviewResolver(
        keyReader: MemoryPushKeyReader([
          PushSharedKeyNames.identityMlKemSecretKey: "chat-secret",
          PushSharedKeyNames.directReactionContacts: testCase.contacts,
          PushSharedKeyNames.directReactionAuthoredTargets: testCase.targets,
        ]),
        decryptor: decryptor,
        dedupeStore: MemoryPushDedupeStore()
      )
      let result = resolver.resolve(
        userInfo: reactionRoute(eventId: "event-1"),
        fallbackTitle: "New Message",
        fallbackBody: "You have a new message"
      )
      XCTAssertEqual(result.reason, testCase.reason, testCase.name)
      XCTAssertEqual(result.body, "Someone reacted to your message", testCase.name)
      XCTAssertTrue(result.suppress, testCase.name)
      XCTAssertEqual(decryptor.chatCalls, 0, testCase.name)
    }
  }

  func testReactionToneLeaseMakesDistinctBurstUpdatePassive() throws {
    let toneStore = MemoryPushToneLeaseStore(results: [true, false])
    let decryptor = MemoryPushDecryptor(
      chatPlaintext: try reactionPlaintextJSON(eventId: "event-one")
    )
    let resolver = NotificationPreviewResolver(
      keyReader: MemoryPushKeyReader([
        PushSharedKeyNames.identityMlKemSecretKey: "chat-secret",
        PushSharedKeyNames.directReactionContacts: try reactionContactsJSON(
          username: "Alice",
          blocked: false
        ),
        PushSharedKeyNames.directReactionAuthoredTargets: try reactionTargetsJSON(),
      ]),
      decryptor: decryptor,
      dedupeStore: MemoryPushDedupeStore(),
      toneLeaseStore: toneStore
    )

    let first = resolver.resolve(
      userInfo: reactionRoute(eventId: "event-one"),
      fallbackTitle: "New reaction",
      fallbackBody: "Someone reacted to your message"
    )
    decryptor.chatPlaintext = try reactionPlaintextJSON(eventId: "event-two")
    let second = resolver.resolve(
      userInfo: reactionRoute(eventId: "event-two"),
      fallbackTitle: "New reaction",
      fallbackBody: "Someone reacted to your message"
    )

    XCTAssertFalse(first.suppress)
    XCTAssertTrue(second.suppress)
    XCTAssertTrue(second.markAsShown)
    XCTAssertEqual(toneStore.conversations, ["peer-alice", "peer-alice"])
  }

  func testReactionEnvelopeStagesWithReactionKind() throws {
    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("reaction-envelope-\(UUID().uuidString)")
    let store = AppGroupPushEnvelopeStore(directory: dir)

    XCTAssertTrue(store.stage(userInfo: reactionRoute(eventId: "event-stage")))
    let file = try XCTUnwrap(
      try FileManager.default.contentsOfDirectory(
        at: dir,
        includingPropertiesForKeys: nil
      ).first
    )
    let json = try XCTUnwrap(
      JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any]
    )
    XCTAssertEqual(json["kind"] as? String, "reaction")
    XCTAssertEqual(json["eventId"] as? String, "event-stage")
    XCTAssertEqual(json["targetMessageId"] as? String, "target-message")
    XCTAssertEqual(json["action"] as? String, "add")
    XCTAssertNil(json["emoji"])
    XCTAssertNil(json["username"])

    try? FileManager.default.removeItem(at: dir)
  }

  func testReactionClaimExpiryPruningAndToneLeaseAreDurable() throws {
    let claimDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("reaction-claims-\(UUID().uuidString)")
    let claimStore = AppGroupPushDedupeStore(
      directory: claimDir,
      maxEntries: 2,
      ttlSeconds: 1
    )
    XCTAssertTrue(claimStore.claim(type: "message_reaction", messageId: "old"))
    let oldURL = claimDir.appendingPathComponent("message_reaction-old")
    try FileManager.default.setAttributes(
      [.modificationDate: Date(timeIntervalSinceNow: -10)],
      ofItemAtPath: oldURL.path
    )
    XCTAssertTrue(claimStore.claim(type: "message_reaction", messageId: "old"))
    XCTAssertTrue(claimStore.claim(type: "message_reaction", messageId: "second"))
    XCTAssertTrue(claimStore.claim(type: "message_reaction", messageId: "third"))
    XCTAssertFalse(claimStore.claim(type: "message_reaction", messageId: "third"))
    XCTAssertLessThanOrEqual(
      try FileManager.default.contentsOfDirectory(atPath: claimDir.path).count,
      2
    )

    let toneDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("reaction-tones-\(UUID().uuidString)")
    let firstProcess = AppGroupNotificationToneLeaseStore(
      directory: toneDir,
      leaseSeconds: 30
    )
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    XCTAssertTrue(firstProcess.acquire(conversationId: "peer-alice", now: now))
    let restartedProcess = AppGroupNotificationToneLeaseStore(
      directory: toneDir,
      leaseSeconds: 30
    )
    XCTAssertFalse(
      restartedProcess.acquire(
        conversationId: "peer-alice",
        now: now.addingTimeInterval(29)
      )
    )
    XCTAssertTrue(
      restartedProcess.acquire(
        conversationId: "peer-alice",
        now: now.addingTimeInterval(31)
      )
    )

    try? FileManager.default.removeItem(at: claimDir)
    try? FileManager.default.removeItem(at: toneDir)
  }

  func testReactionAtomicClaimAndToneLeaseAllowOneConcurrentWinner() {
    let claimDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("reaction-claim-race-\(UUID().uuidString)")
    let claimStore = AppGroupPushDedupeStore(directory: claimDir)
    let claimWins = LockedWinCounter()
    DispatchQueue.concurrentPerform(iterations: 16) { _ in
      claimWins.record(
        claimStore.claim(type: "message_reaction", messageId: "reaction:shared")
      )
    }
    XCTAssertEqual(claimWins.value, 1)

    let toneDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("reaction-tone-race-\(UUID().uuidString)")
    let toneStore = AppGroupNotificationToneLeaseStore(directory: toneDir)
    let toneWins = LockedWinCounter()
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    DispatchQueue.concurrentPerform(iterations: 16) { _ in
      toneWins.record(
        toneStore.acquire(conversationId: "peer-alice", now: now)
      )
    }
    XCTAssertEqual(toneWins.value, 1)

    try? FileManager.default.removeItem(at: claimDir)
    try? FileManager.default.removeItem(at: toneDir)
  }

  func testNotificationServiceCompletionGateExpiryBeforeResolutionRejectsPublisher() {
    let gate = NotificationServiceCompletionGate()
    let generation = gate.reset { _ in }

    var expiryHandoffs = 0
    XCTAssertTrue(
      gate.claim(generation: generation) {
        expiryHandoffs += 1
      }
    )
    var latePublishRan = false
    XCTAssertFalse(
      gate.publish(generation: generation) {
        latePublishRan = true
      }
    )
    XCTAssertEqual(expiryHandoffs, 1)
    XCTAssertFalse(latePublishRan)
  }

  func testNotificationServiceCompletionGateExpiryAfterAuthorizedResolutionIsOnce() {
    let gate = NotificationServiceCompletionGate()
    let generation = gate.reset { _ in }
    var authorizedPublished = false
    XCTAssertTrue(
      gate.publish(generation: generation) {
        authorizedPublished = true
      }
    )

    var applyCalls = 0
    var shownMarkerCalls = 0
    var handoffCalls = 0
    var toneCommitCalls = 0
    XCTAssertTrue(
      gate.claim(generation: generation) {
        if authorizedPublished {
          applyCalls += 1
          shownMarkerCalls += 1
          handoffCalls += 1
          toneCommitCalls += 1
        }
      }
    )
    XCTAssertFalse(gate.claim(generation: generation) {})
    XCTAssertEqual(applyCalls, 1)
    XCTAssertEqual(shownMarkerCalls, 1)
    XCTAssertEqual(handoffCalls, 1)
    XCTAssertEqual(toneCommitCalls, 1)
  }

  func testNotificationServiceCompletionGateRejectsStaleRequestGeneration() {
    let gate = NotificationServiceCompletionGate()
    var activeState = ""
    let first = gate.reset { _ in activeState = "request-a" }
    XCTAssertTrue(
      gate.claim(generation: first) {
        activeState = "request-a-expired"
      }
    )
    let second = gate.reset { _ in activeState = "request-b" }
    var staleActionRan = false
    let staleReservation = MemoryPushToneReservation()
    let stalePublished = gate.publish(generation: first) {
      staleActionRan = true
    }
    if !stalePublished {
      XCTAssertTrue(staleReservation.release())
    }
    XCTAssertFalse(stalePublished)
    XCTAssertFalse(
      gate.claim(generation: first) {
        staleActionRan = true
      }
    )
    XCTAssertFalse(staleActionRan)
    XCTAssertEqual(activeState, "request-b")
    XCTAssertEqual(staleReservation.releaseCalls, 1)
    XCTAssertEqual(staleReservation.commitCalls, 0)

    let wins = LockedWinCounter()
    DispatchQueue.concurrentPerform(iterations: 32) { _ in
      wins.record(gate.claim(generation: second) {})
    }
    XCTAssertEqual(wins.value, 1)
  }

  func testUnresolvedExpirySanitizerClearsVisibleMetadataButRetainsRoute() {
    let content = UNMutableNotificationContent()
    content.title = "FORGED TITLE"
    content.subtitle = "FORGED SUBTITLE"
    content.body = "FORGED BODY"
    content.badge = 9
    content.sound = .default
    content.categoryIdentifier = "FORGED_CATEGORY"
    content.threadIdentifier = "FORGED_THREAD"
    content.summaryArgument = "FORGED SUMMARY"
    content.summaryArgumentCount = 7
    content.launchImageName = "forged.png"
    content.userInfo = ["type": "new_message", "sender_id": "peer-alice"]
    if #available(iOS 15.0, *) {
      content.targetContentIdentifier = "FORGED_TARGET"
      content.relevanceScore = 1
      content.interruptionLevel = .active
    }
    if #available(iOS 16.0, *) {
      content.filterCriteria = "FORGED_FILTER"
    }

    sanitizeNotificationContentForUnresolvedExpiry(content)

    XCTAssertEqual(content.title, "")
    XCTAssertEqual(content.subtitle, "")
    XCTAssertEqual(content.body, "")
    XCTAssertTrue(content.attachments.isEmpty)
    XCTAssertNil(content.badge)
    XCTAssertNil(content.sound)
    XCTAssertEqual(content.categoryIdentifier, "")
    XCTAssertEqual(content.threadIdentifier, "")
    XCTAssertEqual(content.summaryArgument, "")
    XCTAssertEqual(content.summaryArgumentCount, 0)
    XCTAssertEqual(content.launchImageName, "")
    XCTAssertEqual(content.userInfo["type"] as? String, "new_message")
    XCTAssertEqual(content.userInfo["sender_id"] as? String, "peer-alice")
    if #available(iOS 15.0, *) {
      XCTAssertEqual(content.targetContentIdentifier, "")
      XCTAssertEqual(content.relevanceScore, 0)
      XCTAssertEqual(content.interruptionLevel, .passive)
    }
    if #available(iOS 16.0, *) {
      XCTAssertEqual(content.filterCriteria, "")
    }
  }

  func testRejectedNormalAuthMuteDedupeMalformedAndOversizedSanitizeProviderMetadata()
    throws
  {
    let blocked = NotificationPreviewResolver(
      keyReader: MemoryPushKeyReader(
        [
          PushSharedKeyNames.directReactionContacts:
            try ordinaryDirectContactsJSON(blocked: true),
          PushSharedKeyNames.groupReactionContexts:
            try ordinaryLocalIdentityContextsJSON(),
        ],
        includeDefaultOrdinaryProjection: false
      ),
      decryptor: MemoryPushDecryptor(),
      dedupeStore: MemoryPushDedupeStore()
    ).resolve(
      userInfo: [
        "type": "new_message",
        "sender_id": "peer-alice",
        "preview_unavailable": "1",
      ],
      fallbackTitle: "FORGED TITLE",
      fallbackBody: "FORGED BODY"
    )

    let muted = NotificationPreviewResolver(
      keyReader: MemoryPushKeyReader(
        [
          PushSharedKeyNames.groupReactionContexts:
            try ordinaryGroupContextsJSON(
              groupId: "group-team",
              groupName: "Team Chat",
              groupType: "chat",
              senderTransportPeerId: "transport-alice",
              senderRole: "writer",
              muted: true
            ),
        ],
        includeDefaultOrdinaryProjection: false
      ),
      decryptor: MemoryPushDecryptor(),
      dedupeStore: MemoryPushDedupeStore()
    ).resolve(
      userInfo: [
        "type": "group_message",
        "groupId": "group-team",
        "sender_transport_peer_id": "transport-alice",
        "preview_unavailable": "1",
      ],
      fallbackTitle: "FORGED TITLE",
      fallbackBody: "FORGED BODY"
    )

    let malformed = NotificationPreviewResolver(
      keyReader: MemoryPushKeyReader([:]),
      decryptor: MemoryPushDecryptor(),
      dedupeStore: MemoryPushDedupeStore()
    ).resolve(
      userInfo: ["type": "new_message", "sender_id": "peer-alice"],
      fallbackTitle: "FORGED TITLE",
      fallbackBody: "FORGED BODY"
    )

    let oversizedRejected = NotificationPreviewResolver(
      keyReader: MemoryPushKeyReader([:]),
      decryptor: MemoryPushDecryptor(),
      dedupeStore: MemoryPushDedupeStore()
    ).resolve(
      userInfo: [
        "type": "new_message",
        "sender_id": "peer-unknown",
        "preview_unavailable": "1",
      ],
      fallbackTitle: "FORGED TITLE",
      fallbackBody: "FORGED BODY"
    )

    let dedupe = MemoryPushDedupeStore()
    let duplicateResolver = NotificationPreviewResolver(
      keyReader: MemoryPushKeyReader([
        PushSharedKeyNames.identityMlKemSecretKey: "chat-secret",
      ]),
      decryptor: MemoryPushDecryptor(
        chatPlaintext: #"{"id":"duplicate-message","senderPeerId":"peer-alice","text":"trusted"}"#
      ),
      dedupeStore: dedupe
    )
    let duplicateRoute: [String: Any] = [
      "type": "new_message",
      "sender_id": "peer-alice",
      "message_id": "duplicate-message",
      "kem": "kem",
      "ciphertext": "ciphertext",
      "nonce": "nonce",
    ]
    let first = duplicateResolver.resolve(
      userInfo: duplicateRoute,
      fallbackTitle: "FORGED TITLE",
      fallbackBody: "FORGED BODY"
    )
    XCTAssertTrue(first.markAsShown)
    let duplicate = duplicateResolver.resolve(
      userInfo: duplicateRoute,
      fallbackTitle: "FORGED TITLE",
      fallbackBody: "FORGED BODY"
    )

    let attachmentRoot = FileManager.default.temporaryDirectory
      .appendingPathComponent("forged-notification-\(UUID().uuidString)")
    try FileManager.default.createDirectory(
      at: attachmentRoot,
      withIntermediateDirectories: true
    )
    defer { try? FileManager.default.removeItem(at: attachmentRoot) }
    let attachmentURL = attachmentRoot.appendingPathComponent("forged.png")
    let png = try XCTUnwrap(
      Data(
        base64Encoded:
          "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
      )
    )
    try png.write(to: attachmentURL)
    let attachment = try UNNotificationAttachment(
      identifier: "forged",
      url: attachmentURL
    )

    let cases: [(String, NotificationPreviewResult)] = [
      ("auth", blocked),
      ("mute", muted),
      ("dedupe", duplicate),
      ("malformed", malformed),
      ("oversized", oversizedRejected),
    ]
    for item in cases {
      XCTAssertFalse(item.1.markAsShown, item.0)
      XCTAssertNil(item.1.toneReservation, item.0)
      let content = UNMutableNotificationContent()
      content.title = "FORGED TITLE"
      content.subtitle = "FORGED SUBTITLE"
      content.body = "FORGED BODY"
      content.attachments = [attachment]
      content.badge = 9
      content.sound = .default
      content.categoryIdentifier = "FORGED_CATEGORY"
      content.threadIdentifier = "FORGED_THREAD"
      content.summaryArgument = "FORGED SUMMARY"
      content.summaryArgumentCount = 7
      content.launchImageName = "forged.png"
      content.userInfo = ["message_id": "route-must-remain"]
      if #available(iOS 15.0, *) {
        content.targetContentIdentifier = "FORGED_TARGET"
        content.relevanceScore = 1
        content.interruptionLevel = .active
      }
      if #available(iOS 16.0, *) {
        content.filterCriteria = "FORGED_FILTER"
      }

      let applied = applyOrSanitizeNotificationPreviewResult(
        item.1,
        to: content
      )
      var shownMarkerCalls = 0
      if applied { shownMarkerCalls += 1 }
      XCTAssertFalse(applied, item.0)
      XCTAssertEqual(shownMarkerCalls, 0, item.0)
      XCTAssertEqual(content.title, "", item.0)
      XCTAssertEqual(content.subtitle, "", item.0)
      XCTAssertEqual(content.body, "", item.0)
      XCTAssertTrue(content.attachments.isEmpty, item.0)
      XCTAssertNil(content.badge, item.0)
      XCTAssertNil(content.sound, item.0)
      XCTAssertEqual(content.categoryIdentifier, "", item.0)
      XCTAssertEqual(content.threadIdentifier, "", item.0)
      XCTAssertEqual(content.summaryArgument, "", item.0)
      XCTAssertEqual(content.summaryArgumentCount, 0, item.0)
      XCTAssertEqual(content.launchImageName, "", item.0)
      XCTAssertEqual(
        content.userInfo["message_id"] as? String,
        "route-must-remain",
        item.0
      )
      if #available(iOS 15.0, *) {
        XCTAssertEqual(content.targetContentIdentifier, "", item.0)
        XCTAssertEqual(content.relevanceScore, 0, item.0)
        XCTAssertEqual(content.interruptionLevel, .passive, item.0)
      }
      if #available(iOS 16.0, *) {
        XCTAssertEqual(content.filterCriteria, "", item.0)
      }
    }
  }

  func testReactionStoresUseTheCrossLanguageAppGroupLayout() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("reaction-shared-layout-\(UUID().uuidString)")
    let claimDir = root.appendingPathComponent("NotificationServiceDedupe")
    let toneDir = root.appendingPathComponent("NotificationToneLeases")
    let identity = "reaction:abcdef0123456789"
    let claimStore = AppGroupPushDedupeStore(directory: claimDir)

    XCTAssertTrue(
      claimStore.claim(type: "message_reaction", messageId: identity)
    )
    XCTAssertTrue(
      FileManager.default.fileExists(
        atPath: claimDir.appendingPathComponent(
          "message_reaction-reaction_abcdef0123456789"
        ).path
      )
    )
    let groupEventIdentity = boundedReactionNotificationIdentity(
      eventId: "group-reaction-event-1"
    )
    XCTAssertEqual(
      groupEventIdentity,
      "reaction:bfa7b4002bed4b9fb3a1f537c29b03b7bab67234bfe72d2f"
    )
    XCTAssertTrue(
      claimStore.claim(
        type: "message_reaction",
        messageId: groupEventIdentity
      )
    )
    XCTAssertTrue(
      FileManager.default.fileExists(
        atPath: claimDir.appendingPathComponent(
          "message_reaction-reaction_bfa7b4002bed4b9fb3a1f537c29b03b7bab67234bfe72d2f"
        ).path
      )
    )

    let toneStore = AppGroupNotificationToneLeaseStore(directory: toneDir)
    let now = Date(timeIntervalSince1970: 1_800_000_000.125)
    XCTAssertTrue(toneStore.acquire(conversationId: "peer-alice", now: now))
    let toneIdentity = SHA256.hash(data: Data("peer-alice".utf8))
      .map { String(format: "%02x", $0) }
      .joined()
    let toneData = try Data(
      contentsOf: toneDir.appendingPathComponent("\(toneIdentity).lease")
    )
    XCTAssertEqual(
      TimeInterval(String(decoding: toneData, as: UTF8.self)),
      now.timeIntervalSince1970
    )
    XCTAssertTrue(
      toneStore.acquire(
        conversationId: "group:group-team",
        now: now
      )
    )
    let groupToneData = try Data(
      contentsOf: toneDir.appendingPathComponent(
        "8a1bd335a82c0a3727c776f654f2a1b37a5bbc43cf12a88fd8dbf293b1335203.lease"
      )
    )
    XCTAssertEqual(
      TimeInterval(String(decoding: groupToneData, as: UTF8.self)),
      now.timeIntervalSince1970
    )

    try? FileManager.default.removeItem(at: root)
  }

  func testOrdinaryToneReservationReleaseCommitAndDartSidecarParity() throws {
    let toneDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("ordinary-tone-reservation-\(UUID().uuidString)")
    let store = AppGroupNotificationToneLeaseStore(directory: toneDir)
    let now = Date(timeIntervalSince1970: 1_800_000_100.125)
    let identity = SHA256.hash(data: Data("peer-alice".utf8))
      .map { String(format: "%02x", $0) }
      .joined()
    let leaseURL = toneDir.appendingPathComponent("\(identity).lease")
    let pendingURL = toneDir.appendingPathComponent(".\(identity).pending-tone")

    guard case let .reserved(first) = store.reserve(
      conversationId: "peer-alice",
      now: now
    ) else {
      return XCTFail("first producer must reserve")
    }
    let pending = try XCTUnwrap(
      try JSONSerialization.jsonObject(with: Data(contentsOf: pendingURL))
        as? [String: Any]
    )
    XCTAssertEqual(pending["state"] as? String, "pending")
    XCTAssertNotNil(pending["token"] as? String)
    XCTAssertEqual((pending["reservedAtMs"] as? NSNumber)?.int64Value, 1_800_000_100_125)
    XCTAssertEqual(
      TimeInterval(try String(contentsOf: leaseURL, encoding: .utf8)),
      now.timeIntervalSince1970
    )
    XCTAssertTrue(first.release())
    XCTAssertFalse(FileManager.default.fileExists(atPath: leaseURL.path))
    XCTAssertFalse(FileManager.default.fileExists(atPath: pendingURL.path))

    guard case let .reserved(second) = store.reserve(
      conversationId: "peer-alice",
      now: now.addingTimeInterval(1)
    ) else {
      return XCTFail("release must permit immediate redelivery")
    }
    XCTAssertFalse(first.release(), "stale owner cannot delete a newer reservation")
    XCTAssertTrue(second.commit(now: now.addingTimeInterval(2)))
    XCTAssertFalse(FileManager.default.fileExists(atPath: pendingURL.path))
    guard case .leaseHeld = store.reserve(
      conversationId: "peer-alice",
      now: now.addingTimeInterval(29)
    ) else {
      return XCTFail("committed tone window must suppress a burst")
    }
    guard case let .reserved(third) = store.reserve(
      conversationId: "peer-alice",
      now: now.addingTimeInterval(33)
    ) else {
      return XCTFail("expired tone window must allow a new reservation")
    }
    XCTAssertTrue(third.release())

    // This literal is the Dart DurableNotificationToneLease SHA-256 filename
    // for its normalized group conversation key `group:group-team`.
    let groupIdentity =
      "8a1bd335a82c0a3727c776f654f2a1b37a5bbc43cf12a88fd8dbf293b1335203"
    let groupLeaseURL = toneDir.appendingPathComponent("\(groupIdentity).lease")
    let groupPendingURL = toneDir.appendingPathComponent(
      ".\(groupIdentity).pending-tone"
    )
    guard case let .reserved(groupReservation) = store.reserve(
      conversationId: "group:group-team",
      now: now.addingTimeInterval(34)
    ) else {
      return XCTFail("ordinary group must reserve the Dart-normalized key")
    }
    XCTAssertTrue(FileManager.default.fileExists(atPath: groupLeaseURL.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: groupPendingURL.path))
    XCTAssertTrue(groupReservation.release())
    XCTAssertFalse(FileManager.default.fileExists(atPath: groupLeaseURL.path))
    XCTAssertFalse(FileManager.default.fileExists(atPath: groupPendingURL.path))
    try? FileManager.default.removeItem(at: toneDir)
  }

  func testOrdinaryToneReservationBurstHasOneOwnerAndFailureCanRelease() {
    let toneDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("ordinary-tone-burst-\(UUID().uuidString)")
    let store = AppGroupNotificationToneLeaseStore(directory: toneDir)
    let now = Date(timeIntervalSince1970: 1_800_000_200)
    let wins = LockedWinCounter()
    let reservations = LockedReservationCollector()
    DispatchQueue.concurrentPerform(iterations: 16) { _ in
      if case let .reserved(reservation) = store.reserve(
        conversationId: "group:group-team",
        now: now
      ) {
        wins.record(true)
        reservations.record(reservation)
      }
    }
    XCTAssertEqual(wins.value, 1)
    let winner = reservations.first
    XCTAssertNotNil(winner)
    XCTAssertTrue(winner?.release() == true)
    guard case let .reserved(retry) = store.reserve(
      conversationId: "group:group-team",
      now: now
    ) else {
      return XCTFail("failed display release must restore audible ownership")
    }
    XCTAssertTrue(retry.commit(now: now))
    try? FileManager.default.removeItem(at: toneDir)
  }

  func testGroupReactionUsesProjectedContextAndClaimsOnlyAfterExactParity() throws {
    let eventId = "group-reaction-event-1"
    let stateId = "group-reaction-state-1"
    let decryptor = MemoryPushDecryptor(
      groupPlaintext: try groupReactionPlaintextJSON(
        eventId: eventId,
        stateId: stateId
      )
    )
    let toneStore = MemoryPushToneLeaseStore(results: [true])
    let dedupeStore = MemoryPushDedupeStore()
    let resolver = NotificationPreviewResolver(
      keyReader: MemoryPushKeyReader(
        try groupReactionProjectionValues()
      ),
      decryptor: decryptor,
      dedupeStore: dedupeStore,
      toneLeaseStore: toneStore
    )

    let route = try groupReactionRoute(
      eventId: eventId,
      stateId: stateId
    )
    let result = resolver.resolve(
      userInfo: route,
      fallbackTitle: "New Message",
      fallbackBody: "You have a new message"
    )

    XCTAssertTrue(result.didDecrypt)
    XCTAssertEqual(result.reason, "group_reaction")
    XCTAssertEqual(result.title, "Garden Announcements")
    XCTAssertEqual(result.body, "Alice reacted 👍 to your message")
    XCTAssertEqual(result.threadIdentifier, "group-team")
    XCTAssertEqual(result.categoryIdentifier, "MESSAGE_REACTION")
    XCTAssertEqual(
      result.targetContentIdentifier,
      boundedReactionNotificationIdentity(eventId: eventId)
    )
    XCTAssertFalse(result.suppress)
    XCTAssertTrue(result.markAsShown)
    XCTAssertEqual(decryptor.groupCalls, 1)
    XCTAssertEqual(decryptor.lastGroupKey, "group-secret")
    XCTAssertEqual(
      dedupeStore.claims,
      [
        "message_reaction:\(boundedReactionNotificationIdentity(eventId: eventId))",
      ]
    )
    XCTAssertEqual(toneStore.conversations, ["group:group-team"])
    XCTAssertEqual(
      RecentRemoteShownMarkerStore.gateMessageKey(userInfo: route),
      "message:group:group-team|message:target-message|group-reaction-event-1"
    )

    let content = UNMutableNotificationContent()
    content.sound = nil
    applyNotificationPreviewResult(result, to: content)
    XCTAssertEqual(content.sound, .default)
    XCTAssertEqual(content.threadIdentifier, "group-team")
    XCTAssertEqual(content.categoryIdentifier, "MESSAGE_REACTION")
    if #available(iOS 15.0, *) {
      XCTAssertEqual(content.interruptionLevel, .active)
      XCTAssertEqual(
        content.targetContentIdentifier,
        boundedReactionNotificationIdentity(eventId: eventId)
      )
    }
  }

  func testGroupReactionInvalidFirstCopyDoesNotPoisonLaterValidCopy() throws {
    let eventId = "group-reaction-retry"
    let stateId = "group-reaction-state-retry"
    let decryptor = MemoryPushDecryptor(
      groupPlaintext: try groupReactionPlaintextJSON(
        eventId: eventId,
        stateId: stateId,
        targetMessageId: "forged-target"
      )
    )
    let resolver = NotificationPreviewResolver(
      keyReader: MemoryPushKeyReader(
        try groupReactionProjectionValues()
      ),
      decryptor: decryptor,
      dedupeStore: MemoryPushDedupeStore()
    )
    let route = try groupReactionRoute(
      eventId: eventId,
      stateId: stateId
    )

    let invalid = resolver.resolve(
      userInfo: route,
      fallbackTitle: "New Message",
      fallbackBody: "You have a new message"
    )
    XCTAssertEqual(invalid.reason, "group_reaction_parity_mismatch")
    XCTAssertEqual(invalid.title, "New reaction")
    XCTAssertEqual(invalid.body, "Someone reacted to your message")
    XCTAssertTrue(invalid.suppress)
    XCTAssertFalse(invalid.markAsShown)

    decryptor.groupPlaintext = try groupReactionPlaintextJSON(
      eventId: eventId,
      stateId: stateId
    )
    let valid = resolver.resolve(
      userInfo: route,
      fallbackTitle: "New Message",
      fallbackBody: "You have a new message"
    )
    XCTAssertTrue(valid.didDecrypt)
    XCTAssertEqual(valid.body, "Alice reacted 👍 to your message")
    XCTAssertEqual(decryptor.groupCalls, 2)
  }

  func testGroupReactionRejectsDelayedAddOlderThanActiveOrTombstonedState()
    throws {
    let cases: [(String, String, String?)] = [
      (
        "newer active ADD",
        "2026-07-12T11:00:00.000Z",
        nil
      ),
      (
        "newer REMOVE tombstone",
        "2026-07-12T09:30:00.000Z",
        "2026-07-12T11:00:00.000Z"
      ),
    ]

    for testCase in cases {
      let eventId = "stale-state-\(testCase.0)"
      let dedupeStore = MemoryPushDedupeStore()
      let decryptor = MemoryPushDecryptor(
        groupPlaintext: try groupReactionPlaintextJSON(eventId: eventId)
      )
      let result = NotificationPreviewResolver(
        keyReader: MemoryPushKeyReader(
          try groupReactionProjectionValues(
            latestStateTimestamp: testCase.1,
            latestStateRemovedAt: testCase.2
          )
        ),
        decryptor: decryptor,
        dedupeStore: dedupeStore
      ).resolve(
        userInfo: try groupReactionRoute(eventId: eventId),
        fallbackTitle: "New reaction",
        fallbackBody: "Someone reacted to your message"
      )

      XCTAssertEqual(result.reason, "group_reaction_stale_state", testCase.0)
      XCTAssertTrue(result.suppress, testCase.0)
      XCTAssertFalse(result.markAsShown, testCase.0)
      XCTAssertEqual(decryptor.groupCalls, 1, testCase.0)
      XCTAssertTrue(dedupeStore.claims.isEmpty, testCase.0)
    }
  }

  func testGroupReactionAllowsOlderAuthoredTargetAtCurrentReactionEpoch() throws {
    let eventId = "reaction-to-older-target"
    let decryptor = MemoryPushDecryptor(
      groupPlaintext: try groupReactionPlaintextJSON(eventId: eventId)
    )
    let result = NotificationPreviewResolver(
      keyReader: MemoryPushKeyReader(
        try groupReactionProjectionValues(targetKeyEpoch: 6)
      ),
      decryptor: decryptor,
      dedupeStore: MemoryPushDedupeStore()
    ).resolve(
      userInfo: try groupReactionRoute(eventId: eventId),
      fallbackTitle: "New reaction",
      fallbackBody: "Someone reacted to your message"
    )

    XCTAssertTrue(result.didDecrypt)
    XCTAssertEqual(result.reason, "group_reaction")
    XCTAssertEqual(result.body, "Alice reacted 👍 to your message")
    XCTAssertEqual(decryptor.groupCalls, 1)
  }

  func testGroupReactionProjectionEligibilityFailsPassiveBeforeDecrypt() throws {
    func assertRejected(
      _ name: String,
      values: [String: String],
      route: [String: Any],
      reason: String
    ) {
      let decryptor = MemoryPushDecryptor(groupPlaintext: "{}")
      let result = NotificationPreviewResolver(
        keyReader: MemoryPushKeyReader(values),
        decryptor: decryptor,
        dedupeStore: MemoryPushDedupeStore()
      ).resolve(
        userInfo: route,
        fallbackTitle: "New Message",
        fallbackBody: "You have a new message"
      )

      XCTAssertEqual(result.reason, reason, name)
      XCTAssertEqual(result.title, "New reaction", name)
      XCTAssertEqual(result.body, "Someone reacted to your message", name)
      XCTAssertTrue(result.suppress, name)
      XCTAssertFalse(result.markAsShown, name)
      XCTAssertEqual(decryptor.groupCalls, 0, name)
    }

    let validRoute = try groupReactionRoute(eventId: "eligibility-event")
    assertRejected(
      "missing projection",
      values: [:],
      route: validRoute,
      reason: "group_reaction_missing_projection"
    )
    assertRejected(
      "identity transition mismatch",
      values: try groupReactionProjectionValues(
        targetDocumentAccountPeerId: "peer-previous"
      ),
      route: validRoute,
      reason: "group_reaction_missing_projection"
    )
    assertRejected(
      "legacy sibling-device union cannot identify this installation",
      values: try groupReactionProjectionValues(
        legacyLocalInstallationUnion: true
      ),
      route: validRoute,
      reason: "group_reaction_missing_projection"
    )
    assertRejected(
      "muted",
      values: try groupReactionProjectionValues(muted: true),
      route: validRoute,
      reason: "group_reaction_muted"
    )
    assertRejected(
      "dissolved",
      values: try groupReactionProjectionValues(dissolved: true),
      route: validRoute,
      reason: "group_reaction_dissolved"
    )
    assertRejected(
      "reaction key epoch is not current",
      values: try groupReactionProjectionValues(),
      route: try groupReactionRoute(
        eventId: "old-reaction-key-event",
        keyEpoch: 6
      ),
      reason: "group_reaction_key_epoch_mismatch"
    )
    assertRejected(
      "local account is no longer a member",
      values: try groupReactionProjectionValues(includeLocalMember: false),
      route: validRoute,
      reason: "group_reaction_local_member_missing"
    )
    assertRejected(
      "reactor is no longer a member",
      values: try groupReactionProjectionValues(includeActor: false),
      route: validRoute,
      reason: "group_reaction_actor_missing"
    )
    assertRejected(
      "authored target was deleted or pruned",
      values: try groupReactionProjectionValues(includeTarget: false),
      route: validRoute,
      reason: "group_reaction_target_not_locally_authored"
    )
    assertRejected(
      "bystander device was not nominated",
      values: try groupReactionProjectionValues(),
      route: try groupReactionRoute(
        eventId: "bystander-event",
        notificationRecipients: ["transport-other-author"]
      ),
      reason: "group_reaction_invalid_extension"
    )
    assertRejected(
      "sibling transport from another group was nominated",
      values: try groupReactionProjectionValues(
        localTransportPeerId: "transport-current-group",
        localMemberTransportPeerIds: [
          "transport-current-group",
          "transport-other-group",
        ]
      ),
      route: try groupReactionRoute(
        eventId: "cross-group-sibling-event",
        notificationRecipients: ["transport-other-group"]
      ),
      reason: "group_reaction_invalid_extension"
    )
    assertRejected(
      "this installation is revoked while sibling remains active",
      values: try groupReactionProjectionValues(
        localDeviceId: "device-a-revoked",
        localTransportPeerId: "transport-a-revoked",
        localMemberDeviceIds: ["device-b-active"],
        localMemberTransportPeerIds: ["transport-b-active"]
      ),
      route: try groupReactionRoute(
        eventId: "revoked-current-install-event",
        notificationRecipients: ["transport-b-active"]
      ),
      reason: "group_reaction_local_member_missing"
    )
    assertRejected(
      "active sibling nomination cannot authorize this installation",
      values: try groupReactionProjectionValues(
        localDeviceId: "device-a-active",
        localTransportPeerId: "transport-a-active",
        localMemberDeviceIds: ["device-a-active", "device-b-active"],
        localMemberTransportPeerIds: [
          "transport-a-active",
          "transport-b-active",
        ]
      ),
      route: try groupReactionRoute(
        eventId: "sibling-only-nomination-event",
        notificationRecipients: ["transport-b-active"]
      ),
      reason: "group_reaction_invalid_extension"
    )
    assertRejected(
      "self reaction",
      values: try groupReactionProjectionValues(actorPeerId: "peer-self"),
      route: try groupReactionRoute(
        eventId: "self-event",
        actorPeerId: "peer-self",
        actorTransportPeerId: "transport-self"
      ),
      reason: "group_reaction_self"
    )
    assertRejected(
      "remove",
      values: try groupReactionProjectionValues(),
      route: try groupReactionRoute(
        eventId: "remove-event",
        action: "remove"
      ),
      reason: "group_reaction_not_add"
    )
  }

  func testGroupReactionRejectsMismatchedSignedExtensionBeforeDecrypt() throws {
    var route = try groupReactionRoute(eventId: "signed-event")
    route["base_envelope_hash"] = String(repeating: "f", count: 64)
    let decryptor = MemoryPushDecryptor(
      groupPlaintext: try groupReactionPlaintextJSON(
        eventId: "signed-event"
      )
    )
    let result = NotificationPreviewResolver(
      keyReader: MemoryPushKeyReader(
        try groupReactionProjectionValues()
      ),
      decryptor: decryptor,
      dedupeStore: MemoryPushDedupeStore()
    ).resolve(
      userInfo: route,
      fallbackTitle: "New Message",
      fallbackBody: "You have a new message"
    )

    XCTAssertEqual(result.reason, "group_reaction_invalid_extension")
    XCTAssertTrue(result.suppress)
    XCTAssertFalse(result.markAsShown)
    XCTAssertEqual(decryptor.groupCalls, 0)

    var invalidSignatureRoute = try groupReactionRoute(
      eventId: "invalid-signature-event"
    )
    let encodedExtension = try XCTUnwrap(
      invalidSignatureRoute["notification_extension"] as? String
    )
    var extensionObject = try XCTUnwrap(
      JSONSerialization.jsonObject(
        with: Data(encodedExtension.utf8)
      ) as? [String: Any]
    )
    extensionObject["signature"] = Data(repeating: 0, count: 64)
      .base64EncodedString()
    invalidSignatureRoute["notification_extension"] = try canonicalJSONString(
      extensionObject
    )
    let signatureDecryptor = MemoryPushDecryptor(groupPlaintext: "{}")
    let invalidSignature = NotificationPreviewResolver(
      keyReader: MemoryPushKeyReader(
        try groupReactionProjectionValues()
      ),
      decryptor: signatureDecryptor,
      dedupeStore: MemoryPushDedupeStore()
    ).resolve(
      userInfo: invalidSignatureRoute,
      fallbackTitle: "New Message",
      fallbackBody: "You have a new message"
    )
    XCTAssertEqual(
      invalidSignature.reason,
      "group_reaction_invalid_extension"
    )
    XCTAssertEqual(signatureDecryptor.groupCalls, 0)
  }

  func testGroupReactionRejectsEveryInnerIdentityMismatchBeforeClaim() throws {
    let eventId = "inner-parity-event"
    let cases: [(String, String)] = [
      (
        "state id",
        try groupReactionPlaintextJSON(
          eventId: eventId,
          stateId: "forged-state"
        )
      ),
      (
        "transition id",
        try groupReactionPlaintextJSON(eventId: "forged-event")
      ),
      (
        "action",
        try groupReactionPlaintextJSON(eventId: eventId, action: "remove")
      ),
      (
        "actor",
        try groupReactionPlaintextJSON(
          eventId: eventId,
          actorPeerId: "peer-mallory"
        )
      ),
      (
        "timestamp",
        try groupReactionPlaintextJSON(
          eventId: eventId,
          timestamp: "2026-07-12T08:00:00.000Z"
        )
      ),
      (
        "emoji",
        try groupReactionPlaintextJSON(eventId: eventId, emoji: "")
      ),
    ]

    for testCase in cases {
      let decryptor = MemoryPushDecryptor(groupPlaintext: testCase.1)
      let result = NotificationPreviewResolver(
        keyReader: MemoryPushKeyReader(
          try groupReactionProjectionValues()
        ),
        decryptor: decryptor,
        dedupeStore: MemoryPushDedupeStore()
      ).resolve(
        userInfo: try groupReactionRoute(eventId: eventId),
        fallbackTitle: "New Message",
        fallbackBody: "You have a new message"
      )

      XCTAssertEqual(
        result.reason,
        "group_reaction_parity_mismatch",
        testCase.0
      )
      XCTAssertTrue(result.suppress, testCase.0)
      XCTAssertFalse(result.markAsShown, testCase.0)
      XCTAssertEqual(decryptor.groupCalls, 1, testCase.0)
    }
  }

  func testGroupReactionDecryptFailureUsesTrustedLocalCopyWithoutEmoji() throws {
    let eventId = "group-reaction-decrypt-failure"
    let decryptor = MemoryPushDecryptor(
      groupPlaintext: "{}",
      groupError: MemoryPushDecryptError.injected
    )
    let result = NotificationPreviewResolver(
      keyReader: MemoryPushKeyReader(
        try groupReactionProjectionValues()
      ),
      decryptor: decryptor,
      dedupeStore: MemoryPushDedupeStore()
    ).resolve(
      userInfo: try groupReactionRoute(eventId: eventId),
      fallbackTitle: "New Message",
      fallbackBody: "You have a new message"
    )

    XCTAssertEqual(result.reason, "group_reaction_decrypt_error")
    XCTAssertEqual(result.title, "Garden Announcements")
    XCTAssertEqual(result.body, "Alice reacted to your message")
    XCTAssertFalse(result.body.contains("👍"))
    XCTAssertTrue(result.suppress)
    XCTAssertFalse(result.markAsShown)
    XCTAssertEqual(decryptor.groupCalls, 1)
  }

  func testGroupReactionOversizeProviderFallbackNeverMasqueradesAsMessage() {
    let result = NotificationPreviewResolver(
      keyReader: MemoryPushKeyReader([:]),
      decryptor: MemoryPushDecryptor(groupPlaintext: "{}"),
      dedupeStore: MemoryPushDedupeStore()
    ).resolve(
      userInfo: [
        "type": "group_reaction",
        "groupId": "group-team",
        "event_id": "oversize-event",
        "target_message_id": "target-message",
        "action": "add",
        "preview_unavailable": "1",
      ],
      fallbackTitle: "New Message",
      fallbackBody: "You have a new message"
    )

    XCTAssertEqual(result.title, "New reaction")
    XCTAssertEqual(result.body, "Someone reacted to your message")
    XCTAssertEqual(result.reason, "group_reaction_missing_input")
    XCTAssertTrue(result.suppress)
    XCTAssertFalse(result.markAsShown)
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

  func testMessageNotificationProjectionMatrixCoversContextsAndModalities() throws {
    let fixture = try loadFixture("ios_notification_message_matrix")
    let cases = try XCTUnwrap(fixture["cases"] as? [[String: Any]])
    XCTAssertEqual(cases.count, 12)

    var coveredPairs = Set<String>()
    for testCase in cases {
      let caseId = try XCTUnwrap(testCase["id"] as? String)
      let context = try XCTUnwrap(testCase["context"] as? String)
      let modality = try XCTUnwrap(testCase["modality"] as? String)
      let routeCategory = try XCTUnwrap(testCase["routeCategory"] as? String)
      let routeData = try XCTUnwrap(testCase["routeData"] as? [String: Any])
      let plaintextObject = try XCTUnwrap(testCase["plaintext"] as? [String: Any])
      let expected = try XCTUnwrap(testCase["expected"] as? [String: Any])
      let plaintext = try jsonString(plaintextObject)
      coveredPairs.insert("\(context):\(modality)")

      let keyValues: [String: String]
      switch context {
      case "direct":
        XCTAssertEqual(routeCategory, "direct_message", caseId)
        XCTAssertEqual(routeData["type"] as? String, "new_message", caseId)
        XCTAssertNotNil(routeData["sender_id"] as? String, caseId)
        XCTAssertNil(routeData["sender_transport_peer_id"], caseId)
        XCTAssertNil(plaintextObject["groupType"], caseId)
        keyValues = [PushSharedKeyNames.identityMlKemSecretKey: "direct-secret"]
      case "group", "announcement":
        let groupId = try XCTUnwrap(routeData["groupId"] as? String, caseId)
        let senderTransportPeerId = try XCTUnwrap(
          routeData["sender_transport_peer_id"] as? String,
          caseId
        )
        let keyEpochString = try XCTUnwrap(routeData["keyEpoch"] as? String, caseId)
        let keyEpoch = try XCTUnwrap(Int(keyEpochString), caseId)
        let groupIdCharacters = Array(groupId)
        XCTAssertEqual(routeData["type"] as? String, "group_message", caseId)
        XCTAssertEqual(
          senderTransportPeerId,
          "12D3KooWFixtureAliceTransport",
          caseId
        )
        XCTAssertNil(routeData["sender_id"], caseId)
        XCTAssertEqual(groupId, groupId.lowercased(), caseId)
        XCTAssertEqual(UUID(uuidString: groupId)?.uuidString.lowercased(), groupId, caseId)
        XCTAssertEqual(groupIdCharacters.count, 36, caseId)
        if groupIdCharacters.count == 36 {
          XCTAssertEqual(groupIdCharacters[14], "4", caseId)
          XCTAssertTrue("89ab".contains(groupIdCharacters[19]), caseId)
        }
        XCTAssertEqual(plaintextObject["groupId"] as? String, groupId, caseId)
        XCTAssertEqual(expected["threadIdentifier"] as? String, groupId, caseId)
        XCTAssertEqual(
          routeCategory,
          context == "announcement" ? "announcement_message" : "group_message",
          caseId
        )
        XCTAssertEqual(
          plaintextObject["groupType"] as? String,
          context == "announcement" ? "announcement" : "chat",
          caseId
        )
        keyValues = [
          PushSharedKeyNames.groupKey(groupId: groupId, keyEpoch: keyEpoch):
            "group-secret",
          PushSharedKeyNames.groupReactionContexts:
            try ordinaryGroupContextsJSON(
              groupId: groupId,
              groupName: expected["title"] as? String ?? "Group",
              groupType: context == "announcement" ? "announcement" : "chat",
              senderTransportPeerId: senderTransportPeerId,
              senderRole: context == "announcement" ? "admin" : "writer",
              keyEpoch: keyEpoch
            ),
        ]
      default:
        XCTFail("Unknown notification context \(context) for \(caseId)")
        continue
      }

      let resolver = NotificationPreviewResolver(
        keyReader: MemoryPushKeyReader(keyValues),
        decryptor: MemoryPushDecryptor(
          chatPlaintext: plaintext,
          groupPlaintext: plaintext
        ),
        dedupeStore: MemoryPushDedupeStore()
      )
      let result = resolver.resolve(
        userInfo: routeData,
        fallbackTitle: "New Message",
        fallbackBody: "You have a new message"
      )

      XCTAssertTrue(result.didDecrypt, caseId)
      XCTAssertFalse(result.suppress, caseId)
      XCTAssertTrue(result.markAsShown, caseId)
      XCTAssertEqual(result.reason, context == "direct" ? "chat" : "group", caseId)
      XCTAssertEqual(result.title, expected["title"] as? String, caseId)
      XCTAssertEqual(result.body, expected["body"] as? String, caseId)
      XCTAssertEqual(
        result.threadIdentifier,
        expected["threadIdentifier"] as? String,
        caseId
      )

      let content = UNMutableNotificationContent()
      applyNotificationPreviewResult(result, to: content)
      XCTAssertEqual(content.title, expected["title"] as? String, caseId)
      XCTAssertEqual(content.body, expected["body"] as? String, caseId)
      XCTAssertEqual(
        content.threadIdentifier,
        expected["threadIdentifier"] as? String,
        caseId
      )
      // Message taps are routed by the encrypted route data and stored group
      // type. Do not attach an unregistered interactive-action category.
      XCTAssertTrue(content.categoryIdentifier.isEmpty, caseId)
    }

    XCTAssertEqual(
      coveredPairs,
      Set(
        ["direct", "group", "announcement"].flatMap { context in
          ["text", "image", "video", "voice"].map { modality in
            "\(context):\(modality)"
          }
        }
      )
    )
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

  private func loadRepoFixture(_ name: String) throws -> [String: Any] {
    let iosRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    let appRoot = iosRoot.deletingLastPathComponent()
    let url = appRoot
      .appendingPathComponent("test_fixtures")
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

  private func reactionRoute(eventId: String) -> [String: Any] {
    [
      "type": "message_reaction",
      "sender_id": "peer-alice",
      "event_id": eventId,
      "target_message_id": "target-message",
      "action": "add",
      "kem": "kem",
      "ciphertext": "ciphertext",
      "nonce": "nonce-\(eventId)",
    ]
  }

  private func reactionPlaintextJSON(
    eventId: String,
    targetMessageId: String = "target-message"
  ) throws -> String {
    try jsonString([
      "id": eventId,
      "messageId": targetMessageId,
      "emoji": "👍",
      "action": "add",
      "senderPeerId": "peer-alice",
      "timestamp": "2026-07-12T10:00:00.000Z",
    ])
  }

  private func reactionContactsJSON(
    username: String,
    blocked: Bool,
    localAccountPeerId: String = "peer-self"
  ) throws -> String {
    try jsonString([
      "version": 1,
      "localAccountPeerId": localAccountPeerId,
      "contacts": [
        "peer-alice": [
          "username": username,
          "blocked": blocked,
          "archived": false,
        ],
      ],
    ])
  }

  private func reactionTargetsJSON(
    peerId: String = "peer-alice",
    targetMessageId: String = "target-message",
    localAccountPeerId: String = "peer-self"
  ) throws -> String {
    try jsonString([
      "version": 1,
      "localAccountPeerId": localAccountPeerId,
      "targets": [
        [
          "id": targetMessageId,
          "peerId": peerId,
          "timestamp": "2026-07-12T09:00:00.000Z",
        ],
      ],
    ])
  }

  private func groupReactionRoute(
    eventId: String,
    stateId: String = "group-reaction-state",
    targetMessageId: String = "target-message",
    action: String = "add",
    actorPeerId: String = "peer-alice",
    actorTransportPeerId: String = "transport-alice",
    notificationRecipients: [String] = ["transport-self"],
    keyEpoch: Int = 7
  ) throws -> [String: Any] {
    let privateKey = Curve25519.Signing.PrivateKey()
    let baseEnvelopeHash = String(repeating: "a", count: 64)
    let replayRecipientSetHash = String(repeating: "b", count: 64)
    let signedFields: [String: Any] = [
      "kind": "group_reaction_notification",
      "version": 1,
      "transitionId": eventId,
      "action": action,
      "targetMessageId": targetMessageId,
      "reactorPeerId": actorPeerId,
      "reactorTransportPeerId": actorTransportPeerId,
      "replayRecipientSetHash": replayRecipientSetHash,
      "notificationRecipientTransportPeerIds": notificationRecipients.sorted(),
      "baseEnvelopeHash": baseEnvelopeHash,
    ]
    let signedPayload = try canonicalJSONString(signedFields)
    let signature = try privateKey.signature(
      for: Data(signedPayload.utf8)
    ).base64EncodedString()
    let notificationExtension: [String: Any] = [
      "version": 1,
      "transitionId": eventId,
      "action": action,
      "targetMessageId": targetMessageId,
      "reactorPeerId": actorPeerId,
      "reactorTransportPeerId": actorTransportPeerId,
      "replayRecipientSetHash": replayRecipientSetHash,
      "notificationRecipientTransportPeerIds": notificationRecipients.sorted(),
      "baseEnvelopeHash": baseEnvelopeHash,
      "signatureAlgorithm": "ed25519",
      "signedPayload": signedPayload,
      "signature": signature,
    ]
    return [
      "type": "group_reaction",
      "groupId": "group-team",
      "event_id": eventId,
      "target_message_id": targetMessageId,
      "action": action,
      "capability_version": "group_reaction_v1",
      "envelope_version": "1",
      "reactor_peer_id": actorPeerId,
      "reactor_transport_peer_id": actorTransportPeerId,
      "base_envelope_hash": baseEnvelopeHash,
      "notification_extension": try canonicalJSONString(notificationExtension),
      "sender_public_key": privateKey.publicKey.rawRepresentation.base64EncodedString(),
      "kind": "group_offline_replay",
      "payloadType": "group_reaction",
      "keyEpoch": String(keyEpoch),
      "message_id": stateId,
      "ciphertext": "ciphertext-\(eventId)",
      "nonce": "nonce-\(eventId)",
    ]
  }

  private func groupReactionPlaintextJSON(
    eventId: String,
    stateId: String = "group-reaction-state",
    targetMessageId: String = "target-message",
    action: String = "add",
    actorPeerId: String = "peer-alice",
    emoji: String = "👍",
    timestamp: String = "2026-07-12T10:00:00.000Z"
  ) throws -> String {
    try jsonString([
      "id": stateId,
      "eventId": eventId,
      "messageId": targetMessageId,
      "emoji": emoji,
      "action": action,
      "senderPeerId": actorPeerId,
      "timestamp": timestamp,
    ])
  }

  private func groupReactionProjectionValues(
    contextAccountPeerId: String = "peer-self",
    targetDocumentAccountPeerId: String = "peer-self",
    actorPeerId: String = "peer-alice",
    muted: Bool = false,
    dissolved: Bool = false,
    includeLocalMember: Bool = true,
    includeActor: Bool = true,
    includeTarget: Bool = true,
    targetKeyEpoch: Int = 7,
    localDeviceId: String = "device-self",
    localTransportPeerId: String = "transport-self",
    localMemberDeviceIds: [String] = ["device-self"],
    localMemberTransportPeerIds: [String] = ["transport-self"],
    legacyLocalInstallationUnion: Bool = false,
    latestStateTimestamp: String? = nil,
    latestStateRemovedAt: String? = nil
  ) throws -> [String: String] {
    var members: [String: Any] = [:]
    if includeLocalMember {
      members["peer-self"] = [
        "username": "Local Account",
        "role": "admin",
        "deviceIds": localMemberDeviceIds,
        "transportPeerIds": localMemberTransportPeerIds,
      ]
    }
    if includeActor {
      members[actorPeerId] = [
        "username": actorPeerId == "peer-self" ? "Local Account" : "Alice",
        "role": actorPeerId == "peer-self" ? "admin" : "writer",
        "deviceIds": [
          actorPeerId == "peer-self" ? "device-self" : "device-alice",
        ],
        "transportPeerIds": [
          actorPeerId == "peer-self" ? "transport-self" : "transport-alice",
        ],
      ]
    }
    var contextDocument: [String: Any] = [
      "version": 1,
      "localAccountPeerId": contextAccountPeerId,
      "localDeviceId": localDeviceId,
      "localTransportPeerId": localTransportPeerId,
      "groups": [
        "group-team": [
          "name": "Garden Announcements",
          "type": "announcement",
          "muted": muted,
          "archived": false,
          "dissolved": dissolved,
          "keyEpoch": 7,
          "members": members,
        ],
      ],
    ]
    if legacyLocalInstallationUnion {
      contextDocument.removeValue(forKey: "localDeviceId")
      contextDocument.removeValue(forKey: "localTransportPeerId")
      contextDocument["localDeviceIds"] = [localDeviceId, "device-sibling"]
      contextDocument["localTransportPeerIds"] = [
        localTransportPeerId,
        "transport-sibling",
      ]
    }
    let contexts = try jsonString(contextDocument)
    let targets: [[String: Any]] = includeTarget ? [[
      "id": "target-message",
      "groupId": "group-team",
      "keyEpoch": targetKeyEpoch,
      "timestamp": "2026-07-12T09:00:00.000Z",
    ]] : []
    var latestStates: [[String: Any]] = []
    if let latestStateTimestamp {
      var state: [String: Any] = [
        "groupId": "group-team",
        "targetMessageId": "target-message",
        "reactorPeerId": actorPeerId,
        "timestamp": latestStateTimestamp,
      ]
      if let latestStateRemovedAt {
        state["removedAt"] = latestStateRemovedAt
      }
      latestStates.append(state)
    }
    return [
      PushSharedKeyNames.groupReactionContexts: contexts,
      PushSharedKeyNames.groupReactionAuthoredTargets: try jsonString([
        "version": 1,
        "localAccountPeerId": targetDocumentAccountPeerId,
        "targets": targets,
      ]),
      PushSharedKeyNames.groupReactionLatestStates: try jsonString([
        "version": 1,
        "localAccountPeerId": targetDocumentAccountPeerId,
        "states": latestStates,
      ]),
      PushSharedKeyNames.groupKey(groupId: "group-team", keyEpoch: 7):
        "group-secret",
    ]
  }

  private func ordinaryGroupContextsJSON(
    groupId: String,
    groupName: String,
    groupType: String,
    senderTransportPeerId: String,
    senderRole: String,
    keyEpoch: Int = 7,
    muted: Bool = false,
    archived: Bool = false,
    dissolved: Bool = false,
    includeLocalMember: Bool = true,
    localDeviceId: String = "device-self",
    localTransportPeerId: String = "transport-self",
    localMemberDeviceIds: [String]? = nil,
    localMemberTransportPeerIds: [String]? = nil,
    duplicateSenderTransport: Bool = false
  ) throws -> String {
    var members: [String: Any] = [
      "peer-alice": [
        "username": "Alice",
        "role": senderRole,
        "deviceIds": ["device-alice"],
        "transportPeerIds": [senderTransportPeerId],
      ],
    ]
    if includeLocalMember {
      members["peer-self"] = [
        "username": "Local Account",
        "role": "admin",
        "deviceIds": localMemberDeviceIds ?? [localDeviceId],
        "transportPeerIds": localMemberTransportPeerIds ?? [localTransportPeerId],
      ]
    }
    if duplicateSenderTransport {
      members["peer-mallory"] = [
        "username": "Mallory",
        "role": "writer",
        "deviceIds": ["device-mallory"],
        "transportPeerIds": [senderTransportPeerId],
      ]
    }
    return try jsonString([
      "version": 1,
      "localAccountPeerId": "peer-self",
      "localDeviceId": localDeviceId,
      "localTransportPeerId": localTransportPeerId,
      "groups": [
        groupId: [
          "name": groupName,
          "type": groupType,
          "muted": muted,
          "archived": archived,
          "dissolved": dissolved,
          "keyEpoch": keyEpoch,
          "members": members,
        ],
      ],
    ])
  }

  private func ordinaryDirectContactsJSON(
    peerId: String = "peer-alice",
    username: String = "Trusted Alice",
    blocked: Bool = false,
    archived: Bool = false,
    localAccountPeerId: String = "peer-self"
  ) throws -> String {
    try jsonString([
      "version": 1,
      "localAccountPeerId": localAccountPeerId,
      "contacts": [
        peerId: [
          "username": username,
          "blocked": blocked,
          "archived": archived,
        ],
      ],
    ])
  }

  private func ordinaryDirectTargetsJSON(
    localAccountPeerId: String = "peer-self"
  ) throws -> String {
    try jsonString([
      "version": 1,
      "localAccountPeerId": localAccountPeerId,
      "targets": [],
    ])
  }

  private func ordinaryLocalIdentityContextsJSON(
    localAccountPeerId: String = "peer-self",
    localDeviceId: String = "device-self",
    localTransportPeerId: String = "transport-self",
    conflictingLegacyIdentity: Bool = false
  ) throws -> String {
    var value: [String: Any] = [
      "version": 1,
      "localAccountPeerId": localAccountPeerId,
      "localDeviceId": localDeviceId,
      "localTransportPeerId": localTransportPeerId,
      "groups": [String: Any](),
    ]
    if conflictingLegacyIdentity {
      value["localDeviceIds"] = [localDeviceId, "device-conflict"]
    }
    return try jsonString(value)
  }

  private func canonicalJSONString(_ object: Any) throws -> String {
    let data = try JSONSerialization.data(
      withJSONObject: object,
      options: [.sortedKeys, .withoutEscapingSlashes]
    )
    return try XCTUnwrap(String(data: data, encoding: .utf8))
  }
}

private struct PushPreviewEventRecord {
  let event: String
  let details: [String: String]
}

private final class MemoryPushKeyReader: PushKeyReading {
  private let values: [String: String]

  init(
    _ values: [String: String],
    includeDefaultOrdinaryProjection: Bool = true
  ) {
    let defaults: [String: String] = includeDefaultOrdinaryProjection ? [
      PushSharedKeyNames.directReactionContacts:
        #"{"version":1,"localAccountPeerId":"peer-self","contacts":{"peer-alice":{"username":"Alice","blocked":false,"archived":false}}}"#,
      PushSharedKeyNames.directReactionAuthoredTargets:
        #"{"version":1,"localAccountPeerId":"peer-self","targets":[]}"#,
      PushSharedKeyNames.groupReactionContexts:
        #"{"version":1,"localAccountPeerId":"peer-self","localDeviceId":"device-self","localTransportPeerId":"transport-self","groups":{"group-team":{"name":"Team Chat","type":"chat","muted":false,"archived":false,"dissolved":false,"keyEpoch":7,"members":{"peer-self":{"username":"Local Account","role":"admin","deviceIds":["device-self"],"transportPeerIds":["transport-self"]},"peer-alice":{"username":"Alice","role":"writer","deviceIds":["device-alice"],"transportPeerIds":["transport-alice"]}}}}}"#,
    ] : [:]
    self.values = defaults.merging(values) { _, explicit in explicit }
  }

  func readString(key: String) -> String? {
    values[key]
  }
}

private enum MemoryPushDecryptError: Error {
  case injected
}

private final class MemoryPushDecryptor: PushPayloadDecrypting {
  var chatPlaintext: String?
  var groupPlaintext: String?
  var groupError: Error?

  private(set) var chatCalls = 0
  private(set) var groupCalls = 0
  private(set) var lastChatSecretKey: String?
  private(set) var lastGroupKey: String?

  init(
    chatPlaintext: String? = nil,
    groupPlaintext: String? = nil,
    groupError: Error? = nil
  ) {
    self.chatPlaintext = chatPlaintext
    self.groupPlaintext = groupPlaintext
    self.groupError = groupError
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
    if let groupError {
      throw groupError
    }
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
  private(set) var claims: [String] = []

  func claim(type: String, messageId: String) -> Bool {
    let identity = "\(type):\(messageId)"
    claims.append(identity)
    return claimed.insert(identity).inserted
  }
}

private final class MemoryPushToneLeaseStore: PushToneLeaseStoring {
  private var results: [Bool]
  private(set) var conversations: [String] = []

  init(results: [Bool]) {
    self.results = results
  }

  func acquire(conversationId: String, now: Date) -> Bool {
    conversations.append(conversationId)
    if results.isEmpty { return true }
    return results.removeFirst()
  }
}

private enum MemoryToneReservationOutcome {
  case reserved
  case leaseHeld
  case storageUnavailable
}

private final class MemoryPushToneReservation: PushToneReservation {
  private(set) var commitCalls = 0
  private(set) var releaseCalls = 0
  var commitResult = true
  var releaseResult = true

  func commit(now: Date) -> Bool {
    commitCalls += 1
    return commitResult
  }

  func release() -> Bool {
    releaseCalls += 1
    return releaseResult
  }
}

private final class MemoryPushToneReservationStore:
  PushToneLeaseStoring,
  PushToneReservationStoring {
  private var outcomes: [MemoryToneReservationOutcome]
  private(set) var conversations: [String] = []
  private(set) var reservations: [MemoryPushToneReservation] = []

  init(outcomes: [MemoryToneReservationOutcome]) {
    self.outcomes = outcomes
  }

  func acquire(conversationId: String, now: Date) -> Bool {
    switch reserve(conversationId: conversationId, now: now) {
    case let .reserved(reservation):
      return reservation.commit(now: now)
    case .leaseHeld, .storageUnavailable:
      return false
    }
  }

  func reserve(
    conversationId: String,
    now: Date
  ) -> PushToneReservationOutcome {
    conversations.append(conversationId)
    let outcome = outcomes.isEmpty ? .reserved : outcomes.removeFirst()
    switch outcome {
    case .reserved:
      let reservation = MemoryPushToneReservation()
      reservations.append(reservation)
      return .reserved(reservation)
    case .leaseHeld:
      return .leaseHeld
    case .storageUnavailable:
      return .storageUnavailable
    }
  }
}

private final class LockedWinCounter {
  private let lock = NSLock()
  private var wins = 0

  func record(_ won: Bool) {
    guard won else { return }
    lock.lock()
    wins += 1
    lock.unlock()
  }

  var value: Int {
    lock.lock()
    defer { lock.unlock() }
    return wins
  }
}

private final class LockedReservationCollector {
  private let lock = NSLock()
  private var values: [PushToneReservation] = []

  func record(_ reservation: PushToneReservation) {
    lock.lock()
    values.append(reservation)
    lock.unlock()
  }

  var first: PushToneReservation? {
    lock.lock()
    defer { lock.unlock() }
    return values.first
  }
}
