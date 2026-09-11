import CoreFoundation
import CryptoKit
import Foundation

#if MKNOON_RUNNER_TESTS && canImport(Runner)
  @testable import Runner
#endif

enum NseInboxCandidatePolicy: Equatable {
  case eligible
  case suppressedPolicy
}

struct NseInboxCandidate {
  let preview: NotificationPreviewResult
  let policy: NseInboxCandidatePolicy
  let currentOpaqueBinding: String
  let eventCorrelation: String
  let conversationDigest: String
  let conversationKey: String
  let producerKind: String
  let contentKind: String
  let recoveryIdentity: IosNotificationRecoveryIdentity
  let transportProjectionDigest: String
  let authorityProjectionDigests: [String: String]
}

protocol NseInboxCandidateAdapting {
  func adapt(
    _ row: NseInboxRetrievedMessage,
    credential: NseInboxCredential
  ) -> NseInboxCandidate?
}

/// Strict adapter between raw inbox producer bytes and the incumbent rich
/// renderer. Mailbox authentication is deliberately insufficient: direct
/// physical authority or protected-group signatures must validate first.
final class NseInboxCandidateAdapter: NseInboxCandidateAdapting {
  private let keyReader: PushKeyReading
  private let decryptor: PushPayloadDecrypting
  private let previewResolver: NotificationPreviewResolver
  private let now: () -> Date

  init(
    keyReader: PushKeyReading,
    decryptor: PushPayloadDecrypting,
    previewResolver: NotificationPreviewResolver,
    now: @escaping () -> Date = Date.init
  ) {
    self.keyReader = keyReader
    self.decryptor = decryptor
    self.previewResolver = previewResolver
    self.now = now
  }

  func adapt(
    _ row: NseInboxRetrievedMessage,
    credential: NseInboxCredential
  ) -> NseInboxCandidate? {
    guard let envelope = Self.decodeMap(row.message) else { return nil }
    switch envelope["type"] as? String {
    case "chat_message", "message_reaction":
      return adaptDirect(row, envelope: envelope, credential: credential)
    default:
      guard envelope["kind"] as? String == "group_offline_replay" else {
        return nil
      }
      return adaptGroup(row, envelope: envelope, credential: credential)
    }
  }

  private func adaptDirect(
    _ row: NseInboxRetrievedMessage,
    envelope: [String: Any],
    credential: NseInboxCredential
  ) -> NseInboxCandidate? {
    let isMessage = envelope["type"] as? String == "chat_message"
    let requiredKeys: Set<String> = isMessage
      ? ["type", "version", "id", "senderPeerId", "encrypted"]
      : [
        "type", "version", "senderPeerId", "eventId", "action",
        "targetMessageId", "encrypted",
      ]
    let allowedKeys = isMessage
      ? requiredKeys.union(["eventId"])
      : requiredKeys
    guard Set(envelope.keys).isSubset(of: allowedKeys),
          requiredKeys.isSubset(of: Set(envelope.keys)),
          envelope["version"] as? String == "2",
          let physicalSender = Self.exactPeerId(envelope["senderPeerId"]),
          physicalSender == row.from,
          let projection = DirectTransportProjection(
            keyReader: keyReader,
            expectedAccountPeerId: credential.logicalAccountPeerId
          ),
          let logicalSender = projection.uniqueLogicalSender(
            for: physicalSender
          ),
          let contact = projection.contacts[logicalSender],
          let encrypted = envelope["encrypted"] as? [String: Any],
          Set(encrypted.keys) == ["kem", "ciphertext", "nonce"],
          let kem = Self.exactString(encrypted["kem"], maxBytes: 65_536),
          let ciphertext = Self.exactString(
            encrypted["ciphertext"],
            maxBytes: 524_288
          ),
          let nonce = Self.exactString(encrypted["nonce"], maxBytes: 4_096),
          let secretKey = keyReader.readString(
            key: PushSharedKeyNames.identityMlKemSecretKey
          ),
          let plaintext = try? decryptor.decryptOneToOne(
            secretKey: secretKey,
            kem: kem,
            ciphertext: ciphertext,
            nonce: nonce
          ),
          let inner = Self.decodeMap(plaintext),
          Self.exactPeerId(inner["senderPeerId"]) ==
            logicalSender else {
      return nil
    }

    let producerKind: String
    let contentKind: String
    let eventKey: String
    let recoveryKind: IosNotificationRecoveryKind
    var route: [AnyHashable: Any]
    var policy: NseInboxCandidatePolicy = .eligible
    var authorityProjectionDigests = [
      PushSharedKeyNames.directReactionContacts: projection.documentDigest,
    ]

    if isMessage {
      guard let messageId = Self.wireId(envelope["id"], maxBytes: 4_096),
            !envelope.keys.contains("eventId"),
            Self.isSupportedFreshDirectMessage(
              inner,
              messageId: messageId,
              logicalSender: logicalSender
            )
      else {
        return nil
      }
      producerKind = "direct_message"
      contentKind = "message"
      eventKey = messageId
      recoveryKind = .ordinary
      route = [
        "type": "new_message",
        "sender_id": logicalSender,
        "message_id": messageId,
        "kem": kem,
        "ciphertext": ciphertext,
        "nonce": nonce,
      ]
    } else {
      guard let eventId = Self.wireId(
              envelope["eventId"],
              maxBytes: 4_096
            ),
            let action = Self.exactString(envelope["action"], maxBytes: 16),
            action == "add" || action == "remove",
            let targetMessageId = Self.wireId(
              envelope["targetMessageId"],
              maxBytes: 4_096
            ),
            Set(inner.keys) == [
              "id", "messageId", "emoji", "action", "senderPeerId",
              "timestamp",
            ],
            Self.exactString(inner["id"], maxBytes: 4_096) == eventId,
            Self.exactString(inner["messageId"], maxBytes: 4_096) ==
              targetMessageId,
            inner["action"] as? String == action,
            Self.exactString(inner["emoji"], maxBytes: 256) != nil,
            let reactionTimestampText = Self.exactString(
              inner["timestamp"], maxBytes: 128
            ),
            let reactionTimestamp = Self.canonicalReactionDate(
              reactionTimestampText
            ) else {
        return nil
      }
      guard let targetDigest = previewResolver
        .directReactionAuthorityDigest(
          expectedAccountPeerId: credential.logicalAccountPeerId,
          authorizedPeerIds: Set(projection.contacts.keys),
          senderPeerId: logicalSender,
          targetMessageId: targetMessageId,
          reactionTimestamp: reactionTimestamp
        ) else {
        return nil
      }
      authorityProjectionDigests[
        PushSharedKeyNames.directReactionAuthoredTargets
      ] = targetDigest
      producerKind = "direct_reaction"
      contentKind = "reaction"
      eventKey = eventId
      recoveryKind = .reaction
      if action == "remove" { policy = .suppressedPolicy }
      route = [
        "type": "message_reaction",
        "sender_id": logicalSender,
        "event_id": eventId,
        "action": action,
        "target_message_id": targetMessageId,
        "kem": kem,
        "ciphertext": ciphertext,
        "nonce": nonce,
      ]
    }

    if contact.blocked || contact.archived { policy = .suppressedPolicy }
    let recoveryIdentity = IosNotificationRecoveryIdentity(
      accountPeerId: credential.logicalAccountPeerId,
      lane: .direct,
      conversationId: logicalSender,
      eventId: eventKey,
      kind: recoveryKind
    )
    let preview: NotificationPreviewResult
    if policy == .eligible {
      let rendered = previewResolver.resolve(
        userInfo: route,
        fallbackTitle: "",
        fallbackBody: "",
        fallbackThreadIdentifier: logicalSender
      )
      guard rendered.didDecrypt,
            rendered.markAsShown,
            rendered.recoveryIdentity == recoveryIdentity else {
        return nil
      }
      preview = rendered
    } else {
      preview = Self.passivePreview(
        threadIdentifier: logicalSender,
        recoveryIdentity: recoveryIdentity,
        reason: "authenticated_direct_policy"
      )
    }
    return makeCandidate(
      preview: preview,
      policy: policy,
      credential: credential,
      conversationIdentifier: logicalSender,
      conversationKey: logicalSender,
      producerKind: producerKind,
      contentKind: contentKind,
      kindByte: producerKind == "direct_message" ? 0x01 : 0x02,
      eventKey: eventKey,
      recoveryIdentity: recoveryIdentity,
      lane: .direct,
      authorityProjectionDigests: authorityProjectionDigests
    )
  }

  private func adaptGroup(
    _ row: NseInboxRetrievedMessage,
    envelope: [String: Any],
    credential: NseInboxCredential
  ) -> NseInboxCandidate? {
    guard var protected = ProtectedGroupEnvelope.parse(
            envelope,
            rowFrom: row.from,
            credential: credential,
            keyReader: keyReader
          ),
          let groupKey = keyReader.readString(
            key: PushSharedKeyNames.groupKey(
              groupId: protected.groupId,
              keyEpoch: protected.keyEpoch
            )
          ),
          let plaintext = try? decryptor.decryptGroup(
            groupKey: groupKey,
            ciphertext: protected.ciphertext,
            nonce: protected.nonce
          ),
          Self.sha256(plaintext) == protected.plaintextHash,
          let inner = Self.decodeMap(plaintext) else {
      return nil
    }
    guard protected.matchesPlaintext(inner, now: now()) else {
      return nil
    }
    var authorityProjectionDigests = [
      PushSharedKeyNames.groupReactionContexts:
        protected.authorityProjectionDigest,
    ]

    let isReaction = protected.payloadType == "group_reaction"
    if isReaction {
      guard let reactionTimestamp = protected.reactionTimestamp,
            let evidence = previewResolver.groupReactionAuthorityDigests(
              expectedContextsDigest: protected.authorityProjectionDigest,
              groupId: protected.groupId,
              keyEpoch: protected.keyEpoch,
              targetMessageId: protected.reactionTargetMessageId ?? "",
              reactorPeerId: protected.logicalSenderPeerId,
              reactorTransportPeerId: protected.senderTransportPeerId,
              reactionTimestamp: reactionTimestamp
            ) else {
        return nil
      }
      authorityProjectionDigests.merge(evidence) { _, latest in latest }
    }
    let producerKind = isReaction ? "group_reaction" : "group_message"
    let contentKind = isReaction ? "reaction" : "message"
    let recoveryKind: IosNotificationRecoveryKind = isReaction
      ? .reaction
      : .ordinary
    let recoveryIdentity = IosNotificationRecoveryIdentity(
      accountPeerId: credential.logicalAccountPeerId,
      lane: .group,
      conversationId: protected.groupId,
      eventId: protected.contentEventId,
      kind: recoveryKind
    )
    var policy: NseInboxCandidatePolicy = protected.isPolicySuppressed
      ? .suppressedPolicy
      : .eligible
    if protected.reactionAction == "remove" {
      policy = .suppressedPolicy
    }

    var route: [AnyHashable: Any] = [
      "type": isReaction ? "group_reaction" : "group_message",
      "groupId": protected.groupId,
      "sender_transport_peer_id": protected.senderTransportPeerId,
      "keyEpoch": String(protected.keyEpoch),
      "ciphertext": protected.ciphertext,
      "nonce": protected.nonce,
    ]
    if isReaction {
      guard let reactionStateId = protected.reactionStateId else {
        return nil
      }
      route["message_id"] = reactionStateId
    } else {
      route["message_id"] = protected.contentEventId
    }
    if isReaction, let extensionValue = protected.reactionExtension,
       let extensionJSON = Self.canonicalJSON(extensionValue),
       let action = protected.reactionAction,
       let target = protected.reactionTargetMessageId {
      route["capability_version"] = "group_reaction_v1"
      route["envelope_version"] = "1"
      route["kind"] = "group_offline_replay"
      route["payloadType"] = "group_reaction"
      route["event_id"] = protected.contentEventId
      route["target_message_id"] = target
      route["action"] = action
      route["reactor_peer_id"] = protected.logicalSenderPeerId
      route["reactor_transport_peer_id"] = protected.senderTransportPeerId
      route["base_envelope_hash"] = protected.baseEnvelopeHash
      route["notification_extension"] = extensionJSON
      route["sender_public_key"] = protected.senderPublicKey
    }

    let preview: NotificationPreviewResult
    if policy == .eligible {
      let rendered = previewResolver.resolve(
        userInfo: route,
        fallbackTitle: "",
        fallbackBody: "",
        fallbackThreadIdentifier: protected.groupId
      )
      guard rendered.didDecrypt,
            rendered.markAsShown,
            rendered.recoveryIdentity == recoveryIdentity else {
        return nil
      }
      preview = rendered
    } else {
      preview = Self.passivePreview(
        threadIdentifier: protected.groupId,
        recoveryIdentity: recoveryIdentity,
        reason: "authenticated_group_policy"
      )
    }
    return makeCandidate(
      preview: preview,
      policy: policy,
      credential: credential,
      conversationIdentifier: "group:\(protected.groupId)",
      conversationKey: "group:\(protected.groupId)",
      producerKind: producerKind,
      contentKind: contentKind,
      kindByte: isReaction ? 0x04 : 0x03,
      eventKey: protected.logicalEventKey,
      recoveryIdentity: recoveryIdentity,
      lane: .group,
      authorityProjectionDigests: authorityProjectionDigests
    )
  }

  private func makeCandidate(
    preview: NotificationPreviewResult,
    policy: NseInboxCandidatePolicy,
    credential: NseInboxCredential,
    conversationIdentifier: String,
    conversationKey: String,
    producerKind: String,
    contentKind: String,
    kindByte: UInt8,
    eventKey: String,
    recoveryIdentity: IosNotificationRecoveryIdentity,
    lane: IosAppVisibilityLane,
    authorityProjectionDigests: [String: String]
  ) -> NseInboxCandidate? {
    guard let conversationDigest = IosAppVisibilityDigest.digest(
            lane: lane,
            conversationIdentifier: conversationIdentifier
          ),
          let eventCorrelation = Self.eventCorrelation(
            physicalPeerId: credential.transportPeerId,
            kindByte: kindByte,
            eventKey: eventKey
          ) else {
      return nil
    }
    return NseInboxCandidate(
      preview: preview,
      policy: policy,
      currentOpaqueBinding: credential.opaqueBinding,
      eventCorrelation: eventCorrelation,
      conversationDigest: conversationDigest,
      conversationKey: conversationKey,
      producerKind: producerKind,
      contentKind: contentKind,
      recoveryIdentity: recoveryIdentity,
      transportProjectionDigest: credential.transportProjectionDigest,
      authorityProjectionDigests: authorityProjectionDigests
    )
  }

  private static func passivePreview(
    threadIdentifier: String,
    recoveryIdentity: IosNotificationRecoveryIdentity,
    reason: String
  ) -> NotificationPreviewResult {
    NotificationPreviewResult(
      title: "",
      body: "",
      threadIdentifier: threadIdentifier,
      didDecrypt: true,
      reason: reason,
      suppress: true,
      markAsShown: false,
      recoveryIdentity: recoveryIdentity
    )
  }

  fileprivate static func decodeMap(_ encoded: String) -> [String: Any]? {
    guard encoded.utf8.count <= 524_288,
          let data = encoded.data(using: .utf8),
          let value = try? JSONSerialization.jsonObject(with: data),
          let result = value as? [String: Any] else {
      return nil
    }
    return result
  }

  fileprivate static func exactString(
    _ raw: Any?,
    maxBytes: Int
  ) -> String? {
    guard let value = raw as? String,
          !value.isEmpty,
          value == value.trimmingCharacters(in: .whitespacesAndNewlines),
          value.utf8.count <= maxBytes,
          value.unicodeScalars.allSatisfy({ scalar in
            scalar.value > 31 && !(127...159).contains(scalar.value)
          }) else {
      return nil
    }
    return value
  }

  static func wireId(_ raw: Any?, maxBytes: Int) -> String? {
    guard let value = exactString(raw, maxBytes: maxBytes),
          value.utf8.allSatisfy({ byte in
            (byte >= 48 && byte <= 57) ||
              (byte >= 65 && byte <= 90) ||
              (byte >= 97 && byte <= 122) ||
              byte == 46 || byte == 95 || byte == 58 || byte == 45
          }) else {
      return nil
    }
    return value
  }

  static func exactPeerId(_ raw: Any?) -> String? {
    guard let value = exactString(raw, maxBytes: 256),
          value.unicodeScalars.allSatisfy({ !$0.properties.isWhitespace }) else {
      return nil
    }
    return value
  }

  fileprivate static func canonicalEd25519PublicKey(_ raw: Any?) -> String? {
    guard let value = exactString(raw, maxBytes: 512),
          let bytes = Data(base64Encoded: value),
          bytes.count == 32,
          bytes.base64EncodedString() == value else {
      return nil
    }
    return value
  }

  fileprivate static func fixedUtcDate(_ raw: Any?) -> Date? {
    guard let value = raw as? String,
          value.range(
            of: #"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{6}Z$"#,
            options: .regularExpression
          ) != nil else {
      return nil
    }
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.date(from: value)
  }

  static func canonicalReactionDate(_ raw: Any?) -> Date? {
    guard let value = raw as? String,
          value.range(
            of: #"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}(?:\d{3})?Z$"#,
            options: .regularExpression
          ) != nil else {
      return nil
    }
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.date(from: value)
  }

  private static func isSupportedFreshDirectMessage(
    _ value: [String: Any],
    messageId: String,
    logicalSender: String
  ) -> Bool {
    let required: Set<String> = [
      "id", "text", "senderPeerId", "senderUsername", "timestamp",
    ]
    let allowed = required.union([
      "action", "quotedMessageId", "dedupKey", "isForwarded",
    ])
    guard Set(value.keys).isSubset(of: allowed),
          required.isSubset(of: Set(value.keys)),
          wireId(value["id"], maxBytes: 4_096) == messageId,
          exactPeerId(value["senderPeerId"]) == logicalSender,
          let text = value["text"] as? String,
          text.utf8.count <= 262_144,
          text.unicodeScalars.allSatisfy({ scalar in
            scalar.value > 31 && !(127...159).contains(scalar.value)
          }),
          !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          exactString(value["senderUsername"], maxBytes: 4_096) != nil,
          exactString(value["timestamp"], maxBytes: 128) != nil,
          value["action"] == nil || value["action"] as? String == "send",
          value["eventId"] == nil,
          value["editedAt"] == nil,
          value["media"] == nil,
          value["privateMedia"] == nil else {
      return false
    }
    if value.keys.contains("quotedMessageId") {
      guard let quoted = wireId(value["quotedMessageId"], maxBytes: 4_096),
            quoted != messageId else {
        return false
      }
    }
    if value.keys.contains("dedupKey") {
      guard wireId(value["dedupKey"], maxBytes: 4_096) != nil else {
        return false
      }
    }
    if value.keys.contains("isForwarded") {
      guard exactBool(value["isForwarded"]) == true else { return false }
    }
    return true
  }

  fileprivate static func exactInteger(_ raw: Any?) -> Int64? {
    guard let number = raw as? NSNumber,
          CFGetTypeID(number) != CFBooleanGetTypeID(),
          !CFNumberIsFloatType(number) else {
      return nil
    }
    return Int64(number.stringValue)
  }

  fileprivate static func exactBool(_ raw: Any?) -> Bool? {
    guard let number = raw as? NSNumber,
          CFGetTypeID(number) == CFBooleanGetTypeID() else {
      return nil
    }
    return number.boolValue
  }

  fileprivate static func canonicalJSON(_ value: Any) -> String? {
    guard JSONSerialization.isValidJSONObject(value),
          let data = try? JSONSerialization.data(
            withJSONObject: value,
            options: [.sortedKeys, .withoutEscapingSlashes]
          ) else {
      return nil
    }
    return String(data: data, encoding: .utf8)
  }

  fileprivate static func sha256(_ value: String) -> String {
    SHA256.hash(data: Data(value.utf8))
      .map { String(format: "%02x", $0) }
      .joined()
  }

  fileprivate static func isLowercaseDigest(_ value: String) -> Bool {
    value.utf8.count == 64 && value.utf8.allSatisfy { byte in
      (byte >= 48 && byte <= 57) || (byte >= 97 && byte <= 102)
    }
  }

  private static func eventCorrelation(
    physicalPeerId: String,
    kindByte: UInt8,
    eventKey: String
  ) -> String? {
    let domain = Data("mknoon/wake-outcome/v1".utf8)
    let peer = Data(physicalPeerId.utf8)
    let event = Data(eventKey.utf8)
    guard !peer.isEmpty, peer.count <= 1_024,
          !event.isEmpty, event.count <= 4_096 else {
      return nil
    }
    var preimage = Data()
    for bytes in [domain, peer] {
      var count = UInt32(bytes.count).bigEndian
      withUnsafeBytes(of: &count) { preimage.append(contentsOf: $0) }
      preimage.append(bytes)
    }
    preimage.append(kindByte)
    var eventCount = UInt32(event.count).bigEndian
    withUnsafeBytes(of: &eventCount) { preimage.append(contentsOf: $0) }
    preimage.append(event)
    return SHA256.hash(data: preimage)
      .map { String(format: "%02x", $0) }
      .joined()
  }

  static func dartJSONDoubleForTesting(_ value: Double) -> String? {
    ProtectedGroupEnvelope.dartJSONDoubleForTesting(value)
  }
}

private struct DirectTransportContact {
  let blocked: Bool
  let archived: Bool
  let transports: [String]
}

private struct DirectTransportProjection {
  let contacts: [String: DirectTransportContact]
  let documentDigest: String

  init?(keyReader: PushKeyReading, expectedAccountPeerId: String) {
    guard let encoded = keyReader.readString(
            key: PushSharedKeyNames.directReactionContacts
          ),
          let root = NseInboxCandidateAdapter.decodeMap(encoded),
          Set(root.keys) == ["version", "localAccountPeerId", "contacts"],
          NseInboxCandidateAdapter.exactInteger(root["version"]) == 1,
          root["localAccountPeerId"] as? String == expectedAccountPeerId,
          let values = root["contacts"] as? [String: Any],
          values.count <= 4_096 else {
      return nil
    }
    var result: [String: DirectTransportContact] = [:]
    for (peerId, raw) in values {
      guard NseInboxCandidateAdapter.exactPeerId(peerId) != nil,
            let contact = raw as? [String: Any],
            Set(contact.keys).isSubset(of: [
              "username", "blocked", "archived",
              "authorizedTransportPeerIds", "simsFixtureDigest",
            ]),
            Set(["username", "blocked", "archived",
                 "authorizedTransportPeerIds"]).isSubset(of: Set(contact.keys)),
            NseInboxCandidateAdapter.exactString(
              contact["username"],
              maxBytes: 4_096
            ) != nil,
            let blocked = NseInboxCandidateAdapter.exactBool(
              contact["blocked"]
            ),
            let archived = NseInboxCandidateAdapter.exactBool(
              contact["archived"]
            ),
            let transports = Self.sortedStrings(
              contact["authorizedTransportPeerIds"],
              limit: 32
            ),
            contact["simsFixtureDigest"] == nil ||
              (contact["simsFixtureDigest"] as? String).map(
                NseInboxCandidateAdapter.isLowercaseDigest
              ) == true else {
        return nil
      }
      result[peerId] = DirectTransportContact(
        blocked: blocked,
        archived: archived,
        transports: transports
      )
    }
    contacts = result
    documentDigest = NseInboxCandidateAdapter.sha256(encoded)
  }

  func uniqueLogicalSender(for transportPeerId: String) -> String? {
    let matches = contacts.compactMap { peerId, contact in
      contact.transports.contains(transportPeerId) ? peerId : nil
    }
    return matches.count == 1 ? matches[0] : nil
  }

  private static func sortedStrings(_ raw: Any?, limit: Int) -> [String]? {
    guard let values = raw as? [Any], values.count <= limit else { return nil }
    let strings = values.compactMap {
      NseInboxCandidateAdapter.exactPeerId($0)
    }
    guard strings.count == values.count,
          Set(strings).count == strings.count,
          strings == strings.sorted() else {
      return nil
    }
    return strings
  }
}

private struct ProtectedGroupEnvelope {
  static let allowedKeys: Set<String> = [
    "kind", "version", "groupId", "payloadType", "keyEpoch", "messageId",
    "senderPeerId", "senderDeviceId", "senderTransportPeerId",
    "senderPublicKey", "senderKeyPackageId", "recipientPeerIds",
    "recipientSetHash", "ciphertext", "nonce", "signatureAlgorithm",
    "signedPayload", "signature", "custodyKind", "contentEventId",
    "authorityEventAt", "authorityEventId", "authorityKeyEpoch",
    "mediaManifest", "mediaManifestHash", "notificationExtension",
  ]
  static let requiredKeys: Set<String> = [
    "kind", "version", "groupId", "payloadType", "keyEpoch", "messageId",
    "senderPeerId", "senderDeviceId", "senderTransportPeerId",
    "senderPublicKey", "recipientPeerIds", "recipientSetHash", "ciphertext",
    "nonce", "signatureAlgorithm", "signedPayload", "signature",
    "custodyKind", "contentEventId", "authorityEventAt", "authorityEventId",
    "authorityKeyEpoch",
  ]

  let groupId: String
  let payloadType: String
  let keyEpoch: Int
  let contentEventId: String
  let logicalSenderPeerId: String
  let senderDeviceId: String
  let senderTransportPeerId: String
  let senderPublicKey: String
  let recipientPeerIds: [String]
  let ciphertext: String
  let nonce: String
  let plaintextHash: String
  let baseEnvelopeHash: String
  let reactionExtension: [String: Any]?
  let reactionAction: String?
  let reactionTargetMessageId: String?
  let isPolicySuppressed: Bool
  let authorityEventAt: String
  let authorityEventId: String
  private(set) var logicalEventKey: String
  private(set) var reactionTimestamp: Date?
  private(set) var reactionStateId: String?
  let mediaManifest: String?
  let mediaManifestHash: String?
  let mediaTypes: [String]
  let authorityProjectionDigest: String

  static func parse(
    _ envelope: [String: Any],
    rowFrom: String,
    credential: NseInboxCredential,
    keyReader: PushKeyReading
  ) -> ProtectedGroupEnvelope? {
    let keys = Set(envelope.keys)
    guard keys.isSubset(of: allowedKeys),
          requiredKeys.isSubset(of: keys),
          envelope["kind"] as? String == "group_offline_replay",
          NseInboxCandidateAdapter.exactInteger(envelope["version"]) == 1,
          envelope["custodyKind"] as? String == "group_content_v1",
          let groupId = NseInboxCandidateAdapter.wireId(
            envelope["groupId"], maxBytes: 512
          ),
          let payloadType = envelope["payloadType"] as? String,
          payloadType == "group_message" || payloadType == "group_reaction",
          let keyEpoch64 = NseInboxCandidateAdapter.exactInteger(
            envelope["keyEpoch"]
          ),
          keyEpoch64 >= 0, keyEpoch64 <= Int64(Int.max),
          let authorityEpoch = NseInboxCandidateAdapter.exactInteger(
            envelope["authorityKeyEpoch"]
          ),
          authorityEpoch == keyEpoch64,
          let contentEventId = NseInboxCandidateAdapter.wireId(
            envelope["contentEventId"], maxBytes: 512
          ),
          envelope["messageId"] as? String == contentEventId,
          let sender = NseInboxCandidateAdapter.exactString(
            envelope["senderPeerId"], maxBytes: 1_024
          ),
          let senderDevice = NseInboxCandidateAdapter.exactString(
            envelope["senderDeviceId"], maxBytes: 1_024
          ),
          let senderTransport = NseInboxCandidateAdapter.exactPeerId(
            envelope["senderTransportPeerId"]
          ),
          senderTransport == rowFrom,
          let senderPublicKey =
            NseInboxCandidateAdapter.canonicalEd25519PublicKey(
              envelope["senderPublicKey"]
            ),
          let recipients = sortedStrings(envelope["recipientPeerIds"], limit: 256),
          !recipients.isEmpty,
          recipients.contains(credential.transportPeerId),
          let recipientHash = NseInboxCandidateAdapter.exactString(
            envelope["recipientSetHash"], maxBytes: 64
          ),
          recipientHash == NseInboxCandidateAdapter.sha256(
            NseInboxCandidateAdapter.canonicalJSON(recipients) ?? ""
          ),
          let ciphertext = NseInboxCandidateAdapter.exactString(
            envelope["ciphertext"], maxBytes: 524_288
          ),
          let nonce = NseInboxCandidateAdapter.exactString(
            envelope["nonce"], maxBytes: 4_096
          ),
          envelope["signatureAlgorithm"] as? String == "ed25519",
          let signedPayload = NseInboxCandidateAdapter.exactString(
            envelope["signedPayload"], maxBytes: 524_288
          ),
          let signed = NseInboxCandidateAdapter.decodeMap(signedPayload),
          NseInboxCandidateAdapter.canonicalJSON(signed) == signedPayload,
          let plaintextHash = NseInboxCandidateAdapter.exactString(
            signed["plaintextHash"], maxBytes: 64
          ),
          isDigest(plaintextHash),
          let authorityAt = NseInboxCandidateAdapter.exactString(
            envelope["authorityEventAt"], maxBytes: 64
          ),
          isFixedUtc(authorityAt),
          let authorityId = NseInboxCandidateAdapter.wireId(
            envelope["authorityEventId"], maxBytes: 512
          ),
          let projection = GroupSenderProjection(
            keyReader: keyReader,
            credential: credential,
            groupId: groupId
          ),
          projection.keyEpoch == Int(keyEpoch64),
          projection.authorityEventAt == authorityAt,
          projection.authorityEventId == authorityId,
          projection.matches(
            logicalSender: sender,
            deviceId: senderDevice,
            transportPeerId: senderTransport,
            signingPublicKey: senderPublicKey,
            payloadType: payloadType
          ) else {
      return nil
    }

    var expected: [String: Any] = [
      "schemaVersion": 1,
      "kind": "group_offline_replay",
      "groupId": groupId,
      "payloadType": payloadType,
      "keyEpoch": Int(keyEpoch64),
      "messageId": contentEventId,
      "senderPeerId": sender,
      "senderDeviceId": senderDevice,
      "senderTransportPeerId": senderTransport,
      "senderSigningPublicKey": senderPublicKey,
      "ciphertextHash": NseInboxCandidateAdapter.sha256(ciphertext),
      "nonceHash": NseInboxCandidateAdapter.sha256(nonce),
      "plaintextHash": plaintextHash,
      "recipientSetHash": recipientHash,
      "custodyKind": "group_content_v1",
      "contentEventId": contentEventId,
      "authorityEventAt": authorityAt,
      "authorityEventId": authorityId,
      "authorityKeyEpoch": Int(authorityEpoch),
      "recipientPeerIds": recipients,
    ]
    if envelope.keys.contains("senderKeyPackageId") {
      if !(envelope["senderKeyPackageId"] is NSNull) {
        guard let keyPackage = NseInboxCandidateAdapter.exactString(
          envelope["senderKeyPackageId"], maxBytes: 1_024
        ) else { return nil }
        expected["senderKeyPackageId"] = keyPackage
      }
    }
    var parsedMediaManifest: String?
    var parsedMediaManifestHash: String?
    var parsedMediaTypes: [String] = []
    if envelope.keys.contains("mediaManifest") ||
       envelope.keys.contains("mediaManifestHash") {
      guard payloadType == "group_message",
            let manifest = NseInboxCandidateAdapter.exactString(
              envelope["mediaManifest"], maxBytes: 262_144
            ),
            let manifestHash = NseInboxCandidateAdapter.exactString(
              envelope["mediaManifestHash"], maxBytes: 64
            ),
            isDigest(manifestHash),
            NseInboxCandidateAdapter.sha256(manifest) == manifestHash,
            let mediaTypes = validateMediaManifest(
              manifest,
              groupId: groupId,
              messageId: contentEventId,
              recipients: recipients
            ) else {
        return nil
      }
      expected["mediaManifestHash"] = manifestHash
      parsedMediaManifest = manifest
      parsedMediaManifestHash = manifestHash
      parsedMediaTypes = mediaTypes
    }
    guard NseInboxCandidateAdapter.canonicalJSON(expected) == signedPayload,
          verifySignature(
            publicKey: senderPublicKey,
            signature: envelope["signature"],
            signedPayload: signedPayload
          ) else {
      return nil
    }

    var reactionExtension: [String: Any]?
    var reactionAction: String?
    var reactionTarget: String?
    var baseHash = ""
    if payloadType == "group_reaction" {
      guard let rawExtension = envelope["notificationExtension"] as? [String: Any]
      else { return nil }
      var base = envelope
      base.removeValue(forKey: "notificationExtension")
      guard let canonicalBase = NseInboxCandidateAdapter.canonicalJSON(base)
      else { return nil }
      baseHash = NseInboxCandidateAdapter.sha256(canonicalBase)
      guard let parsed = parseReactionExtension(
        rawExtension,
        contentEventId: contentEventId,
        logicalSender: sender,
        senderTransport: senderTransport,
        senderPublicKey: senderPublicKey,
        replayRecipients: recipients,
        recipientSetHash: recipientHash,
        baseEnvelopeHash: baseHash,
        localTransportPeerId: credential.transportPeerId
      ) else {
        return nil
      }
      reactionExtension = rawExtension
      reactionAction = parsed.action
      reactionTarget = parsed.targetMessageId
    } else if envelope.keys.contains("notificationExtension") {
      return nil
    }

    return ProtectedGroupEnvelope(
      groupId: groupId,
      payloadType: payloadType,
      keyEpoch: Int(keyEpoch64),
      contentEventId: contentEventId,
      logicalSenderPeerId: sender,
      senderDeviceId: senderDevice,
      senderTransportPeerId: senderTransport,
      senderPublicKey: senderPublicKey,
      recipientPeerIds: recipients,
      ciphertext: ciphertext,
      nonce: nonce,
      plaintextHash: plaintextHash,
      baseEnvelopeHash: baseHash,
      reactionExtension: reactionExtension,
      reactionAction: reactionAction,
      reactionTargetMessageId: reactionTarget,
      isPolicySuppressed: projection.isPolicySuppressed,
      authorityEventAt: authorityAt,
      authorityEventId: authorityId,
      logicalEventKey: contentEventId,
      reactionTimestamp: nil,
      reactionStateId: nil,
      mediaManifest: parsedMediaManifest,
      mediaManifestHash: parsedMediaManifestHash,
      mediaTypes: parsedMediaTypes,
      authorityProjectionDigest: projection.documentDigest
    )
  }

  mutating func matchesPlaintext(
    _ value: [String: Any],
    now: Date
  ) -> Bool {
    guard value["groupId"] as? String == groupId,
          NseInboxCandidateAdapter.exactInteger(value["keyEpoch"]) ==
            Int64(keyEpoch),
          value["senderDeviceId"] as? String == senderDeviceId,
          value["transportPeerId"] as? String == senderTransportPeerId,
          value["custodyKind"] as? String == "group_content_v1",
          value["contentEventId"] as? String == contentEventId,
          value["authorityEventAt"] as? String == authorityEventAt,
          value["authorityEventId"] as? String == authorityEventId,
          NseInboxCandidateAdapter.exactInteger(value["authorityKeyEpoch"]) ==
            Int64(keyEpoch),
          Self.sortedStrings(value["recipientPeerIds"], limit: 256) ==
            recipientPeerIds else {
      return false
    }
    if payloadType == "group_message" {
      let requiredMessageKeys: Set<String> = [
        "groupId", "senderId", "senderDeviceId", "transportPeerId",
        "senderUsername", "keyEpoch", "text", "timestamp", "messageId",
        "logicalDeliveryId", "custodyKind", "contentEventId",
        "authorityEventAt", "authorityEventId", "authorityKeyEpoch",
        "recipientPeerIds",
      ]
      let allowedMessageKeys = requiredMessageKeys.union([
        "groupName", "quotedMessageId", "mediaManifest",
        "mediaManifestHash", "isForwarded",
      ])
      guard let logicalDeliveryId = NseInboxCandidateAdapter.wireId(
              value["logicalDeliveryId"], maxBytes: 4_096
            ),
            Set(value.keys).isSubset(of: allowedMessageKeys),
            requiredMessageKeys.isSubset(of: Set(value.keys)),
            logicalDeliveryId == contentEventId,
            let timestamp = value["timestamp"] as? String,
            Self.isValidAuthoringTime(
              timestamp,
              contentEventId: contentEventId,
              authorityEventAt: authorityEventAt,
              authorityEventId: authorityEventId,
              now: now
            ) else {
        return false
      }
      let privateKeys: Set<String> = [
        "mediaPolicyVersion", "mediaLifecycle", "mediaDurationSeconds",
        "mediaProtected",
      ]
      guard value.keys.allSatisfy({ !privateKeys.contains($0) }),
            value["media"] == nil,
            let text = value["text"] as? String,
            text == text.trimmingCharacters(in: .whitespacesAndNewlines),
            text.unicodeScalars.allSatisfy({ scalar in
              !Self.isBidiControl(scalar.value) && scalar.value > 31 &&
                !(127...159).contains(scalar.value)
            }),
            (mediaManifest != nil ||
              (!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                !text.hasPrefix("{\"__sys\":"))),
            value["messageId"] as? String == contentEventId,
            value["senderId"] as? String == logicalSenderPeerId,
            NseInboxCandidateAdapter.exactString(
              value["senderUsername"], maxBytes: 4_096
            ) != nil else {
        return false
      }
      if value.keys.contains("groupName") {
        guard NseInboxCandidateAdapter.exactString(
                value["groupName"], maxBytes: 4_096
              ) != nil else {
          return false
        }
      }
      if let quoted = value["quotedMessageId"] {
        guard let quotedId = NseInboxCandidateAdapter.wireId(
                quoted, maxBytes: 512
              ), quotedId != contentEventId else {
          return false
        }
      }
      if value.keys.contains("isForwarded") {
        guard value["isForwarded"] as? Bool == true,
              mediaManifest != nil,
              value["quotedMessageId"] == nil,
              mediaTypes.allSatisfy({ $0 == "image" || $0 == "video" }) else {
          return false
        }
      }
      if let mediaManifest {
        guard value["mediaManifest"] as? String == mediaManifest,
              value["mediaManifestHash"] as? String == mediaManifestHash else {
          return false
        }
      } else if value.keys.contains("mediaManifest") ||
                  value.keys.contains("mediaManifestHash") {
        return false
      }
      logicalEventKey = logicalDeliveryId
      return true
    }
    guard Set(value.keys) == [
            "id", "eventId", "messageId", "emoji", "action",
            "senderPeerId", "timestamp", "groupId", "keyEpoch",
            "senderDeviceId", "transportPeerId", "custodyKind",
            "contentEventId", "authorityEventAt", "authorityEventId",
            "authorityKeyEpoch", "recipientPeerIds",
          ],
          contentEventId.range(
            of: #"^gr1:[0-9a-f]{32}:\d{20}:[0-9a-f]{32}$"#,
            options: .regularExpression
          ) != nil,
          let timestamp = value["timestamp"] as? String,
          Self.isValidAuthoringTime(
            timestamp,
            contentEventId: contentEventId,
            authorityEventAt: authorityEventAt,
            authorityEventId: authorityEventId,
            now: now
          ),
          let target = reactionTargetMessageId,
          let action = reactionAction,
          let emoji = NseInboxCandidateAdapter.exactString(
            value["emoji"], maxBytes: 4_096
          ),
          let statePreimage = NseInboxCandidateAdapter.canonicalJSON([
            "group_reaction_state_v1", groupId, target,
            logicalSenderPeerId,
          ]),
          let eventPreimage = NseInboxCandidateAdapter.canonicalJSON([
            "group_reaction_event_v1",
            String(NseInboxCandidateAdapter.sha256(statePreimage).prefix(32)),
            action,
            emoji,
            timestamp,
          ]),
          let epochMicros = Self.fixedUtcEpochMicros(timestamp) else {
      return false
    }
    let stateDigest = String(
      NseInboxCandidateAdapter.sha256(statePreimage).prefix(32)
    )
    let eventDigest = String(
      NseInboxCandidateAdapter.sha256(eventPreimage).prefix(32)
    )
    let epochMicrosText = String(epochMicros)
    guard epochMicrosText.count <= 20 else { return false }
    let paddedEpochMicros = String(
      repeating: "0",
      count: 20 - epochMicrosText.count
    ) + epochMicrosText
    let expectedStateId = "group-reaction-state-\(stateDigest)"
    guard value["id"] as? String == expectedStateId,
          contentEventId ==
            "gr1:\(stateDigest):\(paddedEpochMicros):\(eventDigest)"
    else {
      return false
    }
    guard let parsedTimestamp = NseInboxCandidateAdapter.fixedUtcDate(timestamp)
    else { return false }
    logicalEventKey = contentEventId
    reactionTimestamp = parsedTimestamp
    reactionStateId = expectedStateId
    return value["eventId"] as? String == contentEventId &&
      value["senderPeerId"] as? String == logicalSenderPeerId &&
      value["action"] as? String == action &&
      value["messageId"] as? String == reactionTargetMessageId
  }

  private static func fixedUtcEpochMicros(_ value: String) -> Int64? {
    guard isFixedUtc(value), value.utf8.count == 27,
          let fractional = Int64(value.dropFirst(20).prefix(6)) else {
      return nil
    }
    let secondsText = String(value.prefix(19)) + "Z"
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    guard let secondsDate = formatter.date(from: secondsText) else {
      return nil
    }
    let seconds = Int64(secondsDate.timeIntervalSince1970.rounded())
    let (scaled, overflow) = seconds.multipliedReportingOverflow(by: 1_000_000)
    guard !overflow else { return nil }
    let (result, additionOverflow) = scaled.addingReportingOverflow(fractional)
    return additionOverflow || result < 0 ? nil : result
  }

  private static func isFixedUtcString(_ raw: Any?) -> Bool {
    NseInboxCandidateAdapter.fixedUtcDate(raw) != nil
  }

  private static func isBidiControl(_ value: UInt32) -> Bool {
    value == 0x061c || value == 0x200e || value == 0x200f ||
      (0x202a...0x202e).contains(value) ||
      (0x2066...0x2069).contains(value)
  }

  private static func isValidAuthoringTime(
    _ timestamp: String,
    contentEventId: String,
    authorityEventAt: String,
    authorityEventId: String,
    now: Date
  ) -> Bool {
    guard let eventAt = NseInboxCandidateAdapter.fixedUtcDate(timestamp),
          eventAt <= now.addingTimeInterval(5 * 60) else {
      return false
    }
    let timeOrder = authorityEventAt.compare(timestamp)
    return timeOrder == .orderedAscending ||
      (timeOrder == .orderedSame && authorityEventId <= contentEventId)
  }

  private static func parseReactionExtension(
    _ value: [String: Any],
    contentEventId: String,
    logicalSender: String,
    senderTransport: String,
    senderPublicKey: String,
    replayRecipients: [String],
    recipientSetHash: String,
    baseEnvelopeHash: String,
    localTransportPeerId: String
  ) -> (action: String, targetMessageId: String)? {
    let keys: Set<String> = [
      "version", "transitionId", "action", "targetMessageId",
      "reactorPeerId", "reactorTransportPeerId", "replayRecipientSetHash",
      "notificationRecipientTransportPeerIds", "baseEnvelopeHash",
      "signatureAlgorithm", "signedPayload", "signature",
    ]
    guard Set(value.keys) == keys,
          NseInboxCandidateAdapter.exactInteger(value["version"]) == 1,
          value["transitionId"] as? String == contentEventId,
          let action = value["action"] as? String,
          action == "add" || action == "remove",
          let target = NseInboxCandidateAdapter.wireId(
            value["targetMessageId"], maxBytes: 512
          ),
          value["reactorPeerId"] as? String == logicalSender,
          value["reactorTransportPeerId"] as? String == senderTransport,
          value["replayRecipientSetHash"] as? String == recipientSetHash,
          value["baseEnvelopeHash"] as? String == baseEnvelopeHash,
          value["signatureAlgorithm"] as? String == "ed25519",
          let recipients = sortedStrings(
            value["notificationRecipientTransportPeerIds"], limit: 256
          ),
          !recipients.isEmpty,
          recipients.contains(localTransportPeerId),
          recipients.allSatisfy(replayRecipients.contains),
          let signedPayload = NseInboxCandidateAdapter.exactString(
            value["signedPayload"], maxBytes: 262_144
          ) else {
      return nil
    }
    let expected: [String: Any] = [
      "kind": "group_reaction_notification",
      "version": 1,
      "transitionId": contentEventId,
      "action": action,
      "targetMessageId": target,
      "reactorPeerId": logicalSender,
      "reactorTransportPeerId": senderTransport,
      "replayRecipientSetHash": recipientSetHash,
      "notificationRecipientTransportPeerIds": recipients,
      "baseEnvelopeHash": baseEnvelopeHash,
    ]
    guard NseInboxCandidateAdapter.canonicalJSON(expected) == signedPayload,
          verifySignature(
            publicKey: senderPublicKey,
            signature: value["signature"],
            signedPayload: signedPayload
          ) else {
      return nil
    }
    return (action, target)
  }

  private static func validateMediaManifest(
    _ encoded: String,
    groupId: String,
    messageId: String,
    recipients: [String]
  ) -> [String]? {
    guard let manifest = NseInboxCandidateAdapter.decodeMap(encoded),
          Set(manifest.keys) == [
            "schema", "groupId", "messageId", "custodyKind",
            "custodyContract", "recipientPeerIds", "attachments",
          ],
          manifest["schema"] as? String == "group_media_manifest_v1",
          manifest["groupId"] as? String == groupId,
          manifest["messageId"] as? String == messageId,
          manifest["custodyKind"] as? String == "group_media_blob_v1",
          manifest["custodyContract"] as? String == "ack_or_expiry_v1",
          sortedStrings(manifest["recipientPeerIds"], limit: 256) == recipients,
          let attachments = manifest["attachments"] as? [Any],
          !attachments.isEmpty, attachments.count <= 256 else {
      return nil
    }
    let allowed: Set<String> = [
      "attachmentId", "custodyBlobId", "ciphertextSha256", "ciphertextSize",
      "mime", "mediaType", "width", "height", "durationMs", "waveform",
      "encryptionScheme", "encryptionKeyBase64", "encryptionNonce", "caption",
      "expiresAtMs",
    ]
    let required: Set<String> = [
      "attachmentId", "custodyBlobId", "ciphertextSha256", "ciphertextSize",
      "mime", "mediaType", "encryptionScheme", "encryptionKeyBase64",
      "encryptionNonce", "expiresAtMs",
    ]
    var priorId: String?
    var blobIds = Set<String>()
    var mediaTypes: [String] = []
    var canonicalAttachments: [String] = []
    for raw in attachments {
      guard let value = raw as? [String: Any],
            Set(value.keys).isSubset(of: allowed),
            required.isSubset(of: Set(value.keys)),
            let attachmentId = NseInboxCandidateAdapter.exactString(
              value["attachmentId"], maxBytes: 4_096
            ),
            priorId == nil || priorId! < attachmentId,
            let blobId = NseInboxCandidateAdapter.exactString(
              value["custodyBlobId"], maxBytes: 128
            ),
            blobId.range(
              of: #"^[A-Za-z0-9_-]{1,128}$"#,
              options: .regularExpression
            ) != nil,
            blobIds.insert(blobId).inserted,
            let cipherHash = value["ciphertextSha256"] as? String,
            isDigest(cipherHash),
            let size = NseInboxCandidateAdapter.exactInteger(
              value["ciphertextSize"]
            ), size > 16,
            let mime = NseInboxCandidateAdapter.exactString(
              value["mime"], maxBytes: 256
            ), mime.range(
              of: #"^[^/\s]+/[^/\s]+$"#,
              options: .regularExpression
            ) != nil,
            let mediaType = NseInboxCandidateAdapter.exactString(
              value["mediaType"], maxBytes: 64
            ),
            value["encryptionScheme"] as? String == "blob_aes_256_gcm_v1",
            let encryptionKey = NseInboxCandidateAdapter.exactString(
              value["encryptionKeyBase64"], maxBytes: 512
            ),
            let encryptionNonce = NseInboxCandidateAdapter.exactString(
              value["encryptionNonce"], maxBytes: 512
            ),
            let expiries = value["expiresAtMs"] as? [Any],
            expiries.count == recipients.count,
            expiries.allSatisfy({ raw in
              (NseInboxCandidateAdapter.exactInteger(raw) ?? 0) > 0
            }),
            Self.validOptionalPositiveInteger(value, key: "width"),
            Self.validOptionalPositiveInteger(value, key: "height"),
            Self.validOptionalNonNegativeInteger(value, key: "durationMs"),
            let waveform = Self.exactWaveform(value),
            let caption = Self.exactOptionalCaption(value),
            let attachmentJSON = Self.canonicalMediaAttachment(
              attachmentId: attachmentId,
              custodyBlobId: blobId,
              ciphertextSha256: cipherHash,
              ciphertextSize: size,
              mime: mime,
              mediaType: mediaType,
              width: Self.optionalInteger(value, key: "width"),
              height: Self.optionalInteger(value, key: "height"),
              durationMs: Self.optionalInteger(value, key: "durationMs"),
              waveform: waveform,
              encryptionKeyBase64: encryptionKey,
              encryptionNonce: encryptionNonce,
              caption: caption,
              expiresAtMs: expiries
            ) else {
        return nil
      }
      priorId = attachmentId
      mediaTypes.append(mediaType)
      canonicalAttachments.append(attachmentJSON)
    }
    guard let groupJSON = jsonFragment(groupId),
          let messageJSON = jsonFragment(messageId),
          let recipientsJSON = jsonFragment(recipients) else {
      return nil
    }
    let canonical = "{" +
      "\"schema\":\"group_media_manifest_v1\"," +
      "\"groupId\":\(groupJSON)," +
      "\"messageId\":\(messageJSON)," +
      "\"custodyKind\":\"group_media_blob_v1\"," +
      "\"custodyContract\":\"ack_or_expiry_v1\"," +
      "\"recipientPeerIds\":\(recipientsJSON)," +
      "\"attachments\":[\(canonicalAttachments.joined(separator: ","))]}"
    guard canonical == encoded else { return nil }
    return mediaTypes
  }

  private static func validOptionalPositiveInteger(
    _ value: [String: Any],
    key: String
  ) -> Bool {
    !value.keys.contains(key) ||
      (NseInboxCandidateAdapter.exactInteger(value[key]) ?? 0) > 0
  }

  private static func validOptionalNonNegativeInteger(
    _ value: [String: Any],
    key: String
  ) -> Bool {
    !value.keys.contains(key) ||
      (NseInboxCandidateAdapter.exactInteger(value[key]) ?? -1) >= 0
  }

  private static func optionalInteger(
    _ value: [String: Any],
    key: String
  ) -> Int64? {
    value.keys.contains(key)
      ? NseInboxCandidateAdapter.exactInteger(value[key])
      : nil
  }

  /// `nil` means absent; an empty array is non-canonical because Dart's
  /// incumbent encoder omits it.
  private static func exactWaveform(_ value: [String: Any]) -> [Double]? {
    guard value.keys.contains("waveform") else { return [] }
    guard let raw = value["waveform"] as? [Any], !raw.isEmpty else {
      return nil
    }
    var result: [Double] = []
    for sample in raw {
      guard let number = sample as? NSNumber,
            CFGetTypeID(number) != CFBooleanGetTypeID(),
            number.doubleValue.isFinite else {
        return nil
      }
      result.append(number.doubleValue)
    }
    return result
  }

  /// `nil` means absent. Present null/blank/edge-whitespace is non-canonical.
  private static func exactOptionalCaption(_ value: [String: Any]) -> String?? {
    guard value.keys.contains("caption") else { return .some(nil) }
    guard let caption = NseInboxCandidateAdapter.exactString(
            value["caption"], maxBytes: 16_384
          ) else {
      return nil
    }
    return .some(.some(caption))
  }

  private static func canonicalMediaAttachment(
    attachmentId: String,
    custodyBlobId: String,
    ciphertextSha256: String,
    ciphertextSize: Int64,
    mime: String,
    mediaType: String,
    width: Int64?,
    height: Int64?,
    durationMs: Int64?,
    waveform: [Double],
    encryptionKeyBase64: String,
    encryptionNonce: String,
    caption: String?,
    expiresAtMs: [Any]
  ) -> String? {
    guard let attachmentIdJSON = jsonFragment(attachmentId),
          let custodyBlobIdJSON = jsonFragment(custodyBlobId),
          let hashJSON = jsonFragment(ciphertextSha256),
          let mimeJSON = jsonFragment(mime),
          let mediaTypeJSON = jsonFragment(mediaType),
          let keyJSON = jsonFragment(encryptionKeyBase64),
          let nonceJSON = jsonFragment(encryptionNonce),
          let expiriesJSON = jsonFragment(expiresAtMs) else {
      return nil
    }
    var fields = [
      "\"attachmentId\":\(attachmentIdJSON)",
      "\"custodyBlobId\":\(custodyBlobIdJSON)",
      "\"ciphertextSha256\":\(hashJSON)",
      "\"ciphertextSize\":\(ciphertextSize)",
      "\"mime\":\(mimeJSON)",
      "\"mediaType\":\(mediaTypeJSON)",
    ]
    if let width { fields.append("\"width\":\(width)") }
    if let height { fields.append("\"height\":\(height)") }
    if let durationMs { fields.append("\"durationMs\":\(durationMs)") }
    if !waveform.isEmpty {
      guard waveform.allSatisfy({ Self.dartJSONDouble($0) != nil }) else {
        return nil
      }
      let waveformJSON = "[\(waveform.compactMap(Self.dartJSONDouble).joined(separator: ","))]"
      fields.append("\"waveform\":\(waveformJSON)")
    }
    fields.append("\"encryptionScheme\":\"blob_aes_256_gcm_v1\"")
    fields.append("\"encryptionKeyBase64\":\(keyJSON)")
    fields.append("\"encryptionNonce\":\(nonceJSON)")
    if let caption {
      guard let captionJSON = jsonFragment(caption) else { return nil }
      fields.append("\"caption\":\(captionJSON)")
    }
    fields.append("\"expiresAtMs\":\(expiriesJSON)")
    return "{\(fields.joined(separator: ","))}"
  }

  /// Dart's `jsonEncode` uses `double.toString()` spelling: fixed notation for
  /// magnitudes in [1e-6, 1e21), scientific notation otherwise, a decimal
  /// suffix for integral finite doubles, and no zero padding in exponents.
  /// Swift's shortest-round-trip digits are equivalent, but its notation
  /// thresholds differ, so normalize only the presentation around those
  /// already-shortest digits.
  private static func dartJSONDouble(_ value: Double) -> String? {
    guard value.isFinite else { return nil }
    if value == 0 {
      return value.sign == .minus ? "-0.0" : "0.0"
    }

    let rendered = String(value).lowercased()
    let negative = rendered.hasPrefix("-")
    let unsigned = negative ? String(rendered.dropFirst()) : rendered
    let pieces = unsigned.split(separator: "e", omittingEmptySubsequences: false)

    var digits: String
    var decimalExponent: Int
    if pieces.count == 2,
       let exponent = Int(pieces[1]) {
      let mantissa = String(pieces[0])
      guard let point = mantissa.firstIndex(of: ".") else {
        digits = mantissa
        decimalExponent = exponent
        return dartJSONDoubleFromDigits(
          digits,
          decimalExponent: decimalExponent,
          negative: negative,
          magnitude: abs(value)
        )
      }
      let fractionalCount = mantissa.distance(
        from: mantissa.index(after: point),
        to: mantissa.endIndex
      )
      digits = mantissa.replacingOccurrences(of: ".", with: "")
      decimalExponent = exponent - fractionalCount
    } else if pieces.count == 1 {
      let fixed = String(pieces[0])
      if let point = fixed.firstIndex(of: ".") {
        let fractionalCount = fixed.distance(
          from: fixed.index(after: point),
          to: fixed.endIndex
        )
        digits = fixed.replacingOccurrences(of: ".", with: "")
        decimalExponent = -fractionalCount
      } else {
        digits = fixed
        decimalExponent = 0
      }
    } else {
      return nil
    }

    return dartJSONDoubleFromDigits(
      digits,
      decimalExponent: decimalExponent,
      negative: negative,
      magnitude: abs(value)
    )
  }

  static func dartJSONDoubleForTesting(_ value: Double) -> String? {
    dartJSONDouble(value)
  }

  private static func dartJSONDoubleFromDigits(
    _ rawDigits: String,
    decimalExponent: Int,
    negative: Bool,
    magnitude: Double
  ) -> String? {
    guard !rawDigits.isEmpty,
          rawDigits.unicodeScalars.allSatisfy({
            $0.value >= 0x30 && $0.value <= 0x39
          }) else {
      return nil
    }
    var digits = rawDigits
    var exponent = decimalExponent
    while digits.count > 1, digits.last == "0" {
      digits.removeLast()
      exponent += 1
    }
    let sign = negative ? "-" : ""

    if magnitude >= 0.000001 && magnitude < 1.0e21 {
      let decimalPosition = digits.count + exponent
      if decimalPosition <= 0 {
        return sign + "0." + String(repeating: "0", count: -decimalPosition) + digits
      }
      if decimalPosition >= digits.count {
        return sign + digits +
          String(repeating: "0", count: decimalPosition - digits.count) +
          ".0"
      }
      let split = digits.index(digits.startIndex, offsetBy: decimalPosition)
      return sign + digits[..<split] + "." + digits[split...]
    }

    let scientificExponent = digits.count - 1 + exponent
    let mantissa: String
    if digits.count == 1 {
      mantissa = digits
    } else {
      mantissa = String(digits.prefix(1)) + "." + String(digits.dropFirst())
    }
    let exponentSign = scientificExponent >= 0 ? "+" : "-"
    return sign + mantissa + "e" + exponentSign +
      String(abs(scientificExponent))
  }

  private static func jsonFragment(_ value: Any) -> String? {
    guard JSONSerialization.isValidJSONObject([value]),
          let data = try? JSONSerialization.data(
            withJSONObject: [value],
            options: [.withoutEscapingSlashes]
          ),
          var encoded = String(data: data, encoding: .utf8),
          encoded.first == "[", encoded.last == "]" else {
      return nil
    }
    encoded.removeFirst()
    encoded.removeLast()
    return encoded
  }

  private static func verifySignature(
    publicKey: String,
    signature rawSignature: Any?,
    signedPayload: String
  ) -> Bool {
    guard let signature = NseInboxCandidateAdapter.exactString(
            rawSignature, maxBytes: 256
          ),
          let publicData = Data(base64Encoded: publicKey),
          publicData.count == 32,
          publicData.base64EncodedString() == publicKey,
          let signatureData = Data(base64Encoded: signature),
          signatureData.count == 64,
          signatureData.base64EncodedString() == signature,
          let key = try? Curve25519.Signing.PublicKey(
            rawRepresentation: publicData
          ) else {
      return false
    }
    return key.isValidSignature(signatureData, for: Data(signedPayload.utf8))
  }

  private static func sortedStrings(_ raw: Any?, limit: Int) -> [String]? {
    guard let values = raw as? [Any], values.count <= limit else { return nil }
    let strings = values.compactMap {
      NseInboxCandidateAdapter.exactPeerId($0)
    }
    guard strings.count == values.count,
          Set(strings).count == strings.count,
          strings == strings.sorted() else {
      return nil
    }
    return strings
  }

  private static func isDigest(_ value: String) -> Bool {
    value.utf8.count == 64 && value.utf8.allSatisfy { byte in
      (byte >= 48 && byte <= 57) || (byte >= 97 && byte <= 102)
    }
  }

  private static func isFixedUtc(_ value: String) -> Bool {
    NseInboxCandidateAdapter.fixedUtcDate(value) != nil
  }
}

private struct GroupSenderProjection {
  private struct Member {
    let role: String
    let deviceIds: Set<String>
    let transportPeerIds: Set<String>
  }

  struct Tuple: Equatable, Hashable {
    let logicalSender: String
    let deviceId: String
    let transportPeerId: String
    let signingPublicKey: String
  }

  let authorityEventAt: String
  let authorityEventId: String
  let keyEpoch: Int
  let tuples: [Tuple]
  private let groupType: String
  private let members: [String: Member]
  let isPolicySuppressed: Bool
  let documentDigest: String

  init?(
    keyReader: PushKeyReading,
    credential: NseInboxCredential,
    groupId: String
  ) {
    guard let encoded = keyReader.readString(
            key: PushSharedKeyNames.groupReactionContexts
          ),
          let root = NseInboxCandidateAdapter.decodeMap(encoded),
          Set(root.keys) == [
            "version", "localAccountPeerId", "localDeviceId",
            "localTransportPeerId", "groups",
          ],
          NseInboxCandidateAdapter.exactInteger(root["version"]) == 1,
          root["localAccountPeerId"] as? String ==
            credential.logicalAccountPeerId,
          let localDeviceId = NseInboxCandidateAdapter.exactString(
            root["localDeviceId"], maxBytes: 1_024
          ),
          NseInboxCandidateAdapter.exactPeerId(
            root["localTransportPeerId"]
          ) == credential.transportPeerId,
          root["localTransportPeerId"] as? String == credential.transportPeerId,
          let groups = root["groups"] as? [String: Any],
          groups.count <= 4_096,
          Self.validateAllGroups(groups),
          let group = groups[groupId] as? [String: Any],
          Set(group.keys) == [
            "name", "type", "muted", "archived", "dissolved", "keyEpoch",
            "members", "senderAuthority",
          ],
          NseInboxCandidateAdapter.exactString(
            group["name"], maxBytes: 4_096
          ) != nil,
          let groupType = group["type"] as? String,
          groupType == "chat" || groupType == "announcement",
          let groupEpoch = NseInboxCandidateAdapter.exactInteger(
            group["keyEpoch"]
          ),
          groupEpoch >= 0,
          let rawMembers = group["members"] as? [String: Any],
          let parsedMembers = Self.parseMembers(rawMembers),
          let localMember = parsedMembers[credential.logicalAccountPeerId],
          localMember.deviceIds.contains(localDeviceId),
          localMember.transportPeerIds.contains(credential.transportPeerId),
          let muted = NseInboxCandidateAdapter.exactBool(group["muted"]),
          let archived = NseInboxCandidateAdapter.exactBool(group["archived"]),
          let dissolved = NseInboxCandidateAdapter.exactBool(group["dissolved"]),
          let authority = group["senderAuthority"] as? [String: Any],
          Set(authority.keys) == [
            "authorityEventAt", "authorityEventId", "keyEpoch", "tuples",
          ],
          let authorityAt = NseInboxCandidateAdapter.exactString(
            authority["authorityEventAt"], maxBytes: 64
          ),
          NseInboxCandidateAdapter.fixedUtcDate(authorityAt) != nil,
          let authorityId = NseInboxCandidateAdapter.wireId(
            authority["authorityEventId"], maxBytes: 512
          ),
          let epoch = NseInboxCandidateAdapter.exactInteger(
            authority["keyEpoch"]
          ),
          epoch >= 0, epoch <= Int64(Int.max), epoch == groupEpoch,
          let rawTuples = authority["tuples"] as? [Any],
          !rawTuples.isEmpty, rawTuples.count <= 256 else {
      return nil
    }
    var parsed: [Tuple] = []
    for raw in rawTuples {
      guard let value = raw as? [String: Any],
            Set(value.keys) == [
              "logicalSender", "deviceId", "transportPeerId",
              "signingPublicKey",
            ],
            let logical = NseInboxCandidateAdapter.exactString(
              value["logicalSender"], maxBytes: 1_024
            ),
            let device = NseInboxCandidateAdapter.exactString(
              value["deviceId"], maxBytes: 1_024
            ),
            let transport = NseInboxCandidateAdapter.exactPeerId(
              value["transportPeerId"]
            ),
            let signing =
              NseInboxCandidateAdapter.canonicalEd25519PublicKey(
                value["signingPublicKey"]
              ) else {
        return nil
      }
      parsed.append(Tuple(
        logicalSender: logical,
        deviceId: device,
        transportPeerId: transport,
        signingPublicKey: signing
      ))
    }
    let sorted = parsed.sorted { left, right in
      [left.logicalSender, left.deviceId, left.transportPeerId,
       left.signingPublicKey].lexicographicallyPrecedes(
        [right.logicalSender, right.deviceId, right.transportPeerId,
         right.signingPublicKey]
      )
    }
    guard parsed == sorted,
          Set(parsed.map {
            "\($0.logicalSender)\u{0}\($0.deviceId)\u{0}\($0.transportPeerId)\u{0}\($0.signingPublicKey)"
          }).count == parsed.count else {
      return nil
    }
    var transports = Set<String>()
    for tuple in parsed {
      guard transports.insert(tuple.transportPeerId).inserted else { return nil }
    }
    var logicalDevices: [String: String] = [:]
    for tuple in parsed {
      let key = "\(tuple.logicalSender)\u{0}\(tuple.deviceId)"
      let authority = "\(tuple.transportPeerId)\u{0}\(tuple.signingPublicKey)"
      if let prior = logicalDevices[key], prior != authority { return nil }
      logicalDevices[key] = authority
    }
    authorityEventAt = authorityAt
    authorityEventId = authorityId
    keyEpoch = Int(epoch)
    tuples = parsed
    self.groupType = groupType
    self.members = parsedMembers
    isPolicySuppressed = muted || archived || dissolved
    documentDigest = NseInboxCandidateAdapter.sha256(encoded)
  }

  func matches(
    logicalSender: String,
    deviceId: String,
    transportPeerId: String,
    signingPublicKey: String,
    payloadType: String
  ) -> Bool {
    guard let member = members[logicalSender],
          member.deviceIds.contains(deviceId),
          member.transportPeerIds.contains(transportPeerId),
          payloadType != "group_message" ||
            (groupType == "announcement"
              ? member.role == "admin"
              : member.role == "admin" || member.role == "writer") else {
      return false
    }
    return tuples.contains(Tuple(
      logicalSender: logicalSender,
      deviceId: deviceId,
      transportPeerId: transportPeerId,
      signingPublicKey: signingPublicKey
    ))
  }

  private static func validateAllGroups(_ groups: [String: Any]) -> Bool {
    let allowedGroupKeys: Set<String> = [
      "name", "type", "muted", "archived", "dissolved", "keyEpoch",
      "members", "senderAuthority",
    ]
    let requiredGroupKeys: Set<String> = [
      "name", "type", "muted", "archived", "dissolved", "members",
    ]
    for (groupId, rawGroup) in groups {
      guard NseInboxCandidateAdapter.wireId(groupId, maxBytes: 512) != nil,
            let group = rawGroup as? [String: Any],
            Set(group.keys).isSubset(of: allowedGroupKeys),
            requiredGroupKeys.isSubset(of: Set(group.keys)),
            NseInboxCandidateAdapter.exactString(
              group["name"], maxBytes: 4_096
            ) != nil,
            let type = group["type"] as? String,
            type == "chat" || type == "announcement",
            NseInboxCandidateAdapter.exactBool(group["muted"]) != nil,
            NseInboxCandidateAdapter.exactBool(group["archived"]) != nil,
            NseInboxCandidateAdapter.exactBool(group["dissolved"]) != nil,
            let members = group["members"] as? [String: Any],
            members.count <= 4_096,
            validateMembers(members) else {
        return false
      }
      if group.keys.contains("keyEpoch") {
        guard let epoch = NseInboxCandidateAdapter.exactInteger(
                group["keyEpoch"]
              ), epoch >= 0 else {
          return false
        }
      }
      if let rawAuthority = group["senderAuthority"] {
        guard let authority = rawAuthority as? [String: Any],
              let groupEpoch = NseInboxCandidateAdapter.exactInteger(
                group["keyEpoch"]
              ),
              Set(authority.keys) == [
                "authorityEventAt", "authorityEventId", "keyEpoch", "tuples",
              ],
              let authorityAt = authority["authorityEventAt"] as? String,
              NseInboxCandidateAdapter.fixedUtcDate(authorityAt) != nil,
              NseInboxCandidateAdapter.wireId(
                authority["authorityEventId"], maxBytes: 512
              ) != nil,
              let epoch = NseInboxCandidateAdapter.exactInteger(
                authority["keyEpoch"]
              ), epoch >= 0, epoch == groupEpoch,
              let tuples = authority["tuples"] as? [Any],
              !tuples.isEmpty, tuples.count <= 256,
              validateTuples(tuples) else {
          return false
        }
      }
    }
    return true
  }

  private static func validateMembers(_ members: [String: Any]) -> Bool {
    parseMembers(members) != nil
  }

  private static func parseMembers(
    _ members: [String: Any]
  ) -> [String: Member]? {
    var result: [String: Member] = [:]
    for (peerId, rawMember) in members {
      guard let exactPeerId = NseInboxCandidateAdapter.exactPeerId(peerId),
            let member = rawMember as? [String: Any],
            Set(member.keys) == [
              "username", "role", "deviceIds", "transportPeerIds",
            ],
            NseInboxCandidateAdapter.exactString(
              member["username"], maxBytes: 4_096
            ) != nil,
            let role = member["role"] as? String,
            role == "admin" || role == "writer" || role == "reader",
            let deviceIds = sortedStrings(
              member["deviceIds"], limit: 256, peerIds: false
            ),
            let transportPeerIds = sortedStrings(
              member["transportPeerIds"], limit: 256, peerIds: true
            ),
            !deviceIds.isEmpty,
            !transportPeerIds.isEmpty else {
        return nil
      }
      result[exactPeerId] = Member(
        role: role,
        deviceIds: Set(deviceIds),
        transportPeerIds: Set(transportPeerIds)
      )
    }
    return result
  }

  private static func validateTuples(_ tuples: [Any]) -> Bool {
    var parsed: [Tuple] = []
    for raw in tuples {
      guard let value = raw as? [String: Any],
            Set(value.keys) == [
              "logicalSender", "deviceId", "transportPeerId",
              "signingPublicKey",
            ],
            let logical = NseInboxCandidateAdapter.exactString(
              value["logicalSender"], maxBytes: 1_024
            ),
            let device = NseInboxCandidateAdapter.exactString(
              value["deviceId"], maxBytes: 1_024
            ),
            let transport = NseInboxCandidateAdapter.exactPeerId(
              value["transportPeerId"]
            ),
            let signing =
              NseInboxCandidateAdapter.canonicalEd25519PublicKey(
                value["signingPublicKey"]
              ) else {
        return false
      }
      parsed.append(Tuple(
        logicalSender: logical,
        deviceId: device,
        transportPeerId: transport,
        signingPublicKey: signing
      ))
    }
    let sorted = parsed.sorted {
      [$0.logicalSender, $0.deviceId, $0.transportPeerId, $0.signingPublicKey]
        .lexicographicallyPrecedes(
          [$1.logicalSender, $1.deviceId, $1.transportPeerId,
           $1.signingPublicKey]
        )
    }
    guard parsed == sorted,
          Set(parsed.map(\.transportPeerId)).count == parsed.count,
          Set(parsed).count == parsed.count else {
      return false
    }
    var logicalDeviceOwners: [String: String] = [:]
    for tuple in parsed {
      let key = "\(tuple.logicalSender)\u{0}\(tuple.deviceId)"
      let owner = "\(tuple.transportPeerId)\u{0}\(tuple.signingPublicKey)"
      if let prior = logicalDeviceOwners[key], prior != owner { return false }
      logicalDeviceOwners[key] = owner
    }
    return true
  }

  private static func sortedStrings(
    _ raw: Any?,
    limit: Int,
    peerIds: Bool
  ) -> [String]? {
    guard let values = raw as? [Any], values.count <= limit else { return nil }
    let strings = values.compactMap { value in
      peerIds
        ? NseInboxCandidateAdapter.exactPeerId(value)
        : NseInboxCandidateAdapter.exactString(value, maxBytes: 1_024)
    }
    guard strings.count == values.count,
          Set(strings).count == strings.count,
          strings == strings.sorted() else {
      return nil
    }
    return strings
  }
}
