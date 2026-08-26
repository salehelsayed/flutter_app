import CryptoKit
import Darwin
import Foundation
import Security
import UserNotifications

enum IosNotificationRecoveryLane: String, Codable {
  case direct
  case group
}

enum IosNotificationRecoveryKind: String, Codable {
  case ordinary
  case reaction
}

/// OS-owned notification origin used only while projecting a delivered-card
/// inventory. `remote` is derived from `UNPushNotificationTrigger`; payload
/// keys are never allowed to claim producer authority.
enum IosDirectNotificationTriggerOrigin: String, Equatable, Sendable {
  case remote
  case local
}

/// Secret-free terminal projection for one exact direct-notification card.
/// Raw request identifiers, routes, content and userInfo never enter this
/// value or cross the UserNotifications callback boundary through it.
enum IosDirectNotificationSource: String, Equatable, Sendable {
  case usefulProviderRich = "useful_provider_rich"
  case sanitizedProviderRich = "sanitized_provider_rich"
  case flutterLocal = "flutter_local"
  case unknown
}

enum IosDirectNotificationSourceClassifier {
  private static let envelopePrefix = "mknoon-conversation-card-v1:"
  private static let maxIdentityBytes = 512
  private static let maxEnvelopeBytes = 6_144
  private static let maxDecodedEnvelopeBytes = 4_096

  static func triggerOrigin(
    for trigger: UNNotificationTrigger?
  ) -> IosDirectNotificationTriggerOrigin {
    trigger is UNPushNotificationTrigger ? .remote : .local
  }

  static func classify(
    trigger: UNNotificationTrigger?,
    userInfo: [AnyHashable: Any],
    title: String,
    body: String,
    expectedPeerId: String,
    expectedMessageId: String
  ) -> IosDirectNotificationSource {
    classify(
      triggerOrigin: triggerOrigin(for: trigger),
      userInfo: userInfo,
      title: title,
      body: body,
      expectedPeerId: expectedPeerId,
      expectedMessageId: expectedMessageId
    )
  }

  /// Origin-taking overload is intentionally internal and exists so the fixed
  /// Swift/Dart vectors can mutation-test Apple's trigger decision without
  /// manufacturing the unavailable `UNPushNotificationTrigger` initializer.
  static func classify(
    triggerOrigin: IosDirectNotificationTriggerOrigin,
    userInfo: [AnyHashable: Any],
    title: String,
    body: String,
    expectedPeerId: String,
    expectedMessageId: String
  ) -> IosDirectNotificationSource {
    guard let peerId = boundedTrimmedString(
      expectedPeerId,
      maxBytes: maxIdentityBytes
    ),
      let messageId = boundedTrimmedString(
        expectedMessageId,
        maxBytes: maxIdentityBytes
      ) else {
      return .unknown
    }

    let hasLocalNotificationId = userInfo.keys.contains("NotificationId")
    let hasLocalPayload = userInfo.keys.contains("payload")
    let hasProviderShape = ["type", "sender_id", "message_id"].contains {
      userInfo.keys.contains(AnyHashable($0))
    }

    switch triggerOrigin {
    case .remote:
      guard !hasLocalNotificationId,
            !hasLocalPayload,
            exactBoundedString(userInfo["type"], maxBytes: 64) == "new_message",
            exactBoundedString(
              userInfo["sender_id"],
              maxBytes: maxIdentityBytes
            ) == peerId,
            exactBoundedString(
              userInfo["message_id"],
              maxBytes: maxIdentityBytes
            ) == messageId else {
        return .unknown
      }
      let hasTitle = boundedTrimmedString(title, maxBytes: 1_024) != nil
      let hasBody = boundedTrimmedString(body, maxBytes: 4_096) != nil
      if hasTitle && hasBody { return .usefulProviderRich }
      if !hasTitle && !hasBody { return .sanitizedProviderRich }
      return .unknown

    case .local:
      guard !hasProviderShape,
            hasLocalNotificationId,
            isValidFlutterNotificationId(userInfo["NotificationId"]),
            let payload = exactBoundedString(
              userInfo["payload"],
              maxBytes: maxEnvelopeBytes
            ) else {
        return .unknown
      }
      if payload == peerId { return .flutterLocal }
      return matchesTypedLocalEnvelope(
        payload,
        expectedPeerId: peerId,
        expectedMessageId: messageId
      ) ? .flutterLocal : .unknown
    }
  }

  private static func matchesTypedLocalEnvelope(
    _ payload: String,
    expectedPeerId: String,
    expectedMessageId: String
  ) -> Bool {
    guard payload.hasPrefix(envelopePrefix) else { return false }
    let encoded = String(payload.dropFirst(envelopePrefix.count))
    guard !encoded.isEmpty,
          encoded.utf8.count <= maxEnvelopeBytes - envelopePrefix.utf8.count,
          encoded.unicodeScalars.allSatisfy({ scalar in
            switch scalar.value {
            case 45, 48...57, 65...90, 95, 97...122:
              return true
            default:
              return false
            }
          }) else {
      return false
    }
    var base64 = encoded
      .replacingOccurrences(of: "-", with: "+")
      .replacingOccurrences(of: "_", with: "/")
    switch base64.count % 4 {
    case 0:
      break
    case 2:
      base64 += "=="
    case 3:
      base64 += "="
    default:
      return false
    }
    guard let data = Data(base64Encoded: base64),
          !data.isEmpty,
          data.count <= maxDecodedEnvelopeBytes,
          let object = try? JSONSerialization.jsonObject(with: data),
          let envelope = object as? [String: Any],
          isExactVersionOne(envelope["v"]),
          exactBoundedString(
            envelope["route"],
            maxBytes: maxIdentityBytes
          ) == expectedPeerId,
          exactBoundedString(
            envelope["conversation"],
            maxBytes: maxIdentityBytes
          ) == expectedPeerId,
          let content = envelope["content"] as? [String: Any],
          isExactVersionOne(content["v"]),
          exactBoundedString(content["kind"], maxBytes: 32) == "message",
          exactBoundedString(
            content["event"],
            maxBytes: maxIdentityBytes
          ) == expectedMessageId,
          boundedTrimmedString(
            content["generation"] as? String ?? "",
            maxBytes: maxIdentityBytes
          ) != nil else {
      return false
    }
    return true
  }

  private static func exactBoundedString(
    _ value: Any?,
    maxBytes: Int
  ) -> String? {
    guard let value = value as? String,
          let normalized = boundedTrimmedString(value, maxBytes: maxBytes),
          normalized == value else {
      return nil
    }
    return value
  }

  private static func boundedTrimmedString(
    _ value: String,
    maxBytes: Int
  ) -> String? {
    let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalized.isEmpty,
          normalized.utf8.count <= maxBytes else {
      return nil
    }
    return normalized
  }

  private static func isExactVersionOne(_ value: Any?) -> Bool {
    guard let number = value as? NSNumber,
          CFGetTypeID(number) != CFBooleanGetTypeID() else {
      return false
    }
    return number.doubleValue == 1
  }

  private static func isValidFlutterNotificationId(_ value: Any?) -> Bool {
    guard let number = value as? NSNumber,
          CFGetTypeID(number) != CFBooleanGetTypeID(),
          number.doubleValue.isFinite,
          number.doubleValue.rounded() == number.doubleValue,
          number.int64Value >= 0,
          number.int64Value <= Int64(Int32.max) else {
      return false
    }
    return true
  }
}

enum IosGroupNotificationPhase: String, Equatable, Sendable {
  case message
  case reaction
}

struct IosGroupNotificationExpectedHashes: Equatable, Sendable {
  let phase: IosGroupNotificationPhase
  let groupIdSha256: String
  let eventIdSha256: String
  let targetMessageIdSha256: String
  let expectedCollapseIdentifierSha256: String

  init(
    phase: IosGroupNotificationPhase,
    groupIdSha256: String,
    eventIdSha256: String,
    targetMessageIdSha256: String,
    expectedCollapseIdentifierSha256: String = String(repeating: "0", count: 64)
  ) {
    self.phase = phase
    self.groupIdSha256 = groupIdSha256
    self.eventIdSha256 = eventIdSha256
    self.targetMessageIdSha256 = targetMessageIdSha256
    self.expectedCollapseIdentifierSha256 =
      expectedCollapseIdentifierSha256
  }

  var isValid: Bool {
    [
      groupIdSha256,
      eventIdSha256,
      targetMessageIdSha256,
      expectedCollapseIdentifierSha256,
    ].allSatisfy {
      $0.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil
    }
  }
}

enum IosGroupNotificationDiagnosticReason: String, Equatable, Sendable {
  case exactUseful
  case exactSanitized
  case exactFlutterLocal
  case missingOrInvalidType
  case groupHashMismatch
  case partialContent
  case unclassifiedRemote
  case unclassifiedLocal
}

enum IosGroupNotificationDispatchClaim: String, Equatable, Sendable {
  case groupInbox
  case groupContent
  case absent
  case invalid
}

struct IosGroupNotificationProvenanceHashes: Equatable, Sendable {
  let dispatchCorrelationSha256: String?
  let claimedCollapseIdentifierSha256: String?
  let providerMessageIdSha256: String?
}

struct IosGroupNotificationDiagnosticClassification: Equatable, Sendable {
  let triggerOrigin: IosDirectNotificationTriggerOrigin
  let sourceClass: IosDirectNotificationSource
  let reason: IosGroupNotificationDiagnosticReason
  let dispatchClaim: IosGroupNotificationDispatchClaim
}

/// Classifies only cards matching the exact hash-bound group event. A nil
/// result is unrelated device inventory; `.unknown` is a run-owned event whose
/// origin or typed shape failed closed.
enum IosGroupNotificationSourceClassifier {
  static let dispatchClaimKey = "mknoon_group_message_dispatch_source"
  static let dispatchCorrelationKey = "mknoon_group_message_dispatch_id"
  static let claimedCollapseIdentifierKey =
    "mknoon_group_message_collapse_id"
  static let providerMessageIdKey = "gcm.message_id"
  private static let envelopePrefix = "mknoon-conversation-card-v1:"
  private static let maxIdentityBytes = 512
  private static let maxEnvelopeBytes = 6_144
  private static let maxDecodedEnvelopeBytes = 4_096

  /// Reduces bounded APNs/FCM provenance values to deterministic digests before
  /// they enter a diagnostic record. Missing, malformed, open, or over-bound
  /// values become nil; raw values never cross this projection boundary.
  static func provenanceHashes(
    userInfo: [AnyHashable: Any]
  ) -> IosGroupNotificationProvenanceHashes {
    let dispatchCorrelationSha256: String?
    if let value = exactString(
      userInfo[dispatchCorrelationKey],
      maxBytes: 36
    ),
      value.range(
        of: "^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$",
        options: .regularExpression
      ) != nil {
      dispatchCorrelationSha256 = sha256(value)
    } else {
      dispatchCorrelationSha256 = nil
    }

    let claimedCollapseIdentifierSha256 = exactString(
      userInfo[claimedCollapseIdentifierKey],
      maxBytes: 64
    ).map(sha256)
    let providerMessageIdSha256 = exactString(
      userInfo[providerMessageIdKey],
      maxBytes: 160
    ).map(sha256)
    return IosGroupNotificationProvenanceHashes(
      dispatchCorrelationSha256: dispatchCorrelationSha256,
      claimedCollapseIdentifierSha256: claimedCollapseIdentifierSha256,
      providerMessageIdSha256: providerMessageIdSha256
    )
  }

  static func classify(
    trigger: UNNotificationTrigger?,
    userInfo: [AnyHashable: Any],
    title: String,
    body: String,
    expected: IosGroupNotificationExpectedHashes
  ) -> IosDirectNotificationSource? {
    classify(
      triggerOrigin: trigger is UNPushNotificationTrigger ? .remote : .local,
      userInfo: userInfo,
      title: title,
      body: body,
      expected: expected
    )
  }

  /// Produces a diagnostic row only after the raw payload is bound to the
  /// exact expected event. Trigger origin remains the sole source of remote
  /// versus local authority; the bounded dispatch claim is correlation only.
  static func diagnose(
    triggerOrigin: IosDirectNotificationTriggerOrigin,
    userInfo: [AnyHashable: Any],
    title: String,
    body: String,
    expected: IosGroupNotificationExpectedHashes
  ) -> IosGroupNotificationDiagnosticClassification? {
    guard expected.isValid else { return nil }
    switch triggerOrigin {
    case .remote:
      return diagnoseRemote(
        userInfo: userInfo,
        title: title,
        body: body,
        expected: expected
      )
    case .local:
      return diagnoseLocal(userInfo: userInfo, expected: expected)
    }
  }

  private static func diagnoseRemote(
    userInfo: [AnyHashable: Any],
    title: String,
    body: String,
    expected: IosGroupNotificationExpectedHashes
  ) -> IosGroupNotificationDiagnosticClassification? {
    let eventKey = expected.phase == .message ? "message_id" : "event_id"
    guard let event = exactString(userInfo[eventKey], maxBytes: maxIdentityBytes),
          sha256(event) == expected.eventIdSha256 else {
      return nil
    }
    let claim = dispatchClaim(userInfo[dispatchClaimKey])
    func unknown(
      _ reason: IosGroupNotificationDiagnosticReason
    ) -> IosGroupNotificationDiagnosticClassification {
      IosGroupNotificationDiagnosticClassification(
        triggerOrigin: .remote,
        sourceClass: .unknown,
        reason: reason,
        dispatchClaim: claim
      )
    }

    let expectedType = expected.phase == .message
      ? "group_message"
      : "group_reaction"
    guard exactString(userInfo["type"], maxBytes: 64) == expectedType else {
      return unknown(.missingOrInvalidType)
    }
    guard let group = exactString(userInfo["groupId"], maxBytes: maxIdentityBytes),
          sha256(group) == expected.groupIdSha256 else {
      return unknown(.groupHashMismatch)
    }
    if expected.phase == .reaction {
      guard exactString(userInfo["action"], maxBytes: 16) == "add",
            let target = exactString(
              userInfo["target_message_id"],
              maxBytes: maxIdentityBytes
            ),
            sha256(target) == expected.targetMessageIdSha256 else {
        return unknown(.groupHashMismatch)
      }
    }
    guard !userInfo.keys.contains("NotificationId"),
          !userInfo.keys.contains("payload") else {
      return unknown(.unclassifiedRemote)
    }
    let hasTitle = boundedTrimmed(title, maxBytes: 1_024) != nil
    let hasBody = boundedTrimmed(body, maxBytes: 4_096) != nil
    if hasTitle && hasBody {
      return IosGroupNotificationDiagnosticClassification(
        triggerOrigin: .remote,
        sourceClass: .usefulProviderRich,
        reason: .exactUseful,
        dispatchClaim: claim
      )
    }
    if !hasTitle && !hasBody {
      return IosGroupNotificationDiagnosticClassification(
        triggerOrigin: .remote,
        sourceClass: .sanitizedProviderRich,
        reason: .exactSanitized,
        dispatchClaim: claim
      )
    }
    return unknown(.partialContent)
  }

  private static func diagnoseLocal(
    userInfo: [AnyHashable: Any],
    expected: IosGroupNotificationExpectedHashes
  ) -> IosGroupNotificationDiagnosticClassification? {
    guard let payload = exactString(userInfo["payload"], maxBytes: maxEnvelopeBytes),
          payload.hasPrefix(envelopePrefix),
          let envelope = decodeEnvelope(payload),
          let content = envelope["content"] as? [String: Any],
          let event = exactString(content["event"], maxBytes: maxIdentityBytes),
          sha256(event) == expected.eventIdSha256 else {
      return nil
    }
    let claim = dispatchClaim(userInfo[dispatchClaimKey])
    func unknown(
      _ reason: IosGroupNotificationDiagnosticReason
    ) -> IosGroupNotificationDiagnosticClassification {
      IosGroupNotificationDiagnosticClassification(
        triggerOrigin: .local,
        sourceClass: .unknown,
        reason: reason,
        dispatchClaim: claim
      )
    }
    guard let route = exactString(envelope["route"], maxBytes: maxIdentityBytes),
          let conversation = exactString(
            envelope["conversation"],
            maxBytes: maxIdentityBytes
          ),
          matchesGroupRoute(route, expectedHash: expected.groupIdSha256),
          matchesGroupRoute(
            conversation,
            expectedHash: expected.groupIdSha256
          ) else {
      return unknown(.groupHashMismatch)
    }
    guard isExactOne(envelope["v"]),
          isExactOne(content["v"]),
          userInfo.keys.contains("NotificationId"),
          isValidFlutterNotificationId(userInfo["NotificationId"]),
          !["type", "groupId", "message_id", "event_id"].contains(where: {
            userInfo.keys.contains(AnyHashable($0))
          }),
          exactString(content["kind"], maxBytes: 32)
            == (expected.phase == .message ? "message" : "reaction"),
          boundedTrimmed(
            content["generation"] as? String ?? "",
            maxBytes: 512
          ) != nil else {
      return unknown(.unclassifiedLocal)
    }
    return IosGroupNotificationDiagnosticClassification(
      triggerOrigin: .local,
      sourceClass: .flutterLocal,
      reason: .exactFlutterLocal,
      dispatchClaim: claim
    )
  }

  private static func dispatchClaim(
    _ value: Any?
  ) -> IosGroupNotificationDispatchClaim {
    guard value != nil else { return .absent }
    guard let value = value as? String else { return .invalid }
    switch value {
    case "group_inbox_v1": return .groupInbox
    case "group_content_v1": return .groupContent
    default: return .invalid
    }
  }

  static func classify(
    triggerOrigin: IosDirectNotificationTriggerOrigin,
    userInfo: [AnyHashable: Any],
    title: String,
    body: String,
    expected: IosGroupNotificationExpectedHashes
  ) -> IosDirectNotificationSource? {
    guard expected.isValid else { return .unknown }
    switch triggerOrigin {
    case .remote:
      return classifyRemote(
        userInfo: userInfo,
        title: title,
        body: body,
        expected: expected
      )
    case .local:
      return classifyLocal(userInfo: userInfo, expected: expected)
    }
  }

  private static func classifyRemote(
    userInfo: [AnyHashable: Any],
    title: String,
    body: String,
    expected: IosGroupNotificationExpectedHashes
  ) -> IosDirectNotificationSource? {
    let expectedType = expected.phase == .message ? "group_message" : "group_reaction"
    guard exactString(userInfo["type"], maxBytes: 64) == expectedType else {
      return nil
    }
    let eventKey = expected.phase == .message ? "message_id" : "event_id"
    guard let event = exactString(userInfo[eventKey], maxBytes: maxIdentityBytes) else {
      return .unknown
    }
    guard sha256(event) == expected.eventIdSha256 else { return nil }
    guard
      !userInfo.keys.contains("NotificationId"),
      !userInfo.keys.contains("payload"),
      let group = exactString(userInfo["groupId"], maxBytes: maxIdentityBytes),
      sha256(group) == expected.groupIdSha256
    else { return .unknown }
    if expected.phase == .reaction {
      guard exactString(userInfo["action"], maxBytes: 16) == "add",
            let target = exactString(
              userInfo["target_message_id"],
              maxBytes: maxIdentityBytes
            ),
            sha256(target) == expected.targetMessageIdSha256 else {
        return .unknown
      }
    }
    let hasTitle = boundedTrimmed(title, maxBytes: 1_024) != nil
    let hasBody = boundedTrimmed(body, maxBytes: 4_096) != nil
    if hasTitle && hasBody { return .usefulProviderRich }
    if !hasTitle && !hasBody { return .sanitizedProviderRich }
    return .unknown
  }

  private static func classifyLocal(
    userInfo: [AnyHashable: Any],
    expected: IosGroupNotificationExpectedHashes
  ) -> IosDirectNotificationSource? {
    guard let payload = exactString(userInfo["payload"], maxBytes: maxEnvelopeBytes),
          payload.hasPrefix(envelopePrefix),
          let envelope = decodeEnvelope(payload),
          let content = envelope["content"] as? [String: Any],
          isExactOne(envelope["v"]),
          isExactOne(content["v"]),
          let event = exactString(content["event"], maxBytes: maxIdentityBytes)
    else { return nil }
    guard sha256(event) == expected.eventIdSha256 else { return nil }
    guard
      userInfo.keys.contains("NotificationId"),
      isValidFlutterNotificationId(userInfo["NotificationId"]),
      !["type", "groupId", "message_id", "event_id"].contains(where: {
        userInfo.keys.contains(AnyHashable($0))
      }),
      exactString(content["kind"], maxBytes: 32)
        == (expected.phase == .message ? "message" : "reaction"),
      let route = exactString(envelope["route"], maxBytes: maxIdentityBytes),
      let conversation = exactString(
        envelope["conversation"],
        maxBytes: maxIdentityBytes
      ),
      matchesGroupRoute(route, expectedHash: expected.groupIdSha256),
      matchesGroupRoute(conversation, expectedHash: expected.groupIdSha256),
      boundedTrimmed(content["generation"] as? String ?? "", maxBytes: 512) != nil
    else { return .unknown }
    return .flutterLocal
  }

  private static func decodeEnvelope(_ payload: String) -> [String: Any]? {
    let encoded = String(payload.dropFirst(envelopePrefix.count))
    guard !encoded.isEmpty,
          encoded.utf8.count <= maxEnvelopeBytes - envelopePrefix.utf8.count else {
      return nil
    }
    var base64 = encoded
      .replacingOccurrences(of: "-", with: "+")
      .replacingOccurrences(of: "_", with: "/")
    switch base64.count % 4 {
    case 0: break
    case 2: base64 += "=="
    case 3: base64 += "="
    default: return nil
    }
    guard let data = Data(base64Encoded: base64),
          !data.isEmpty,
          data.count <= maxDecodedEnvelopeBytes,
          let object = try? JSONSerialization.jsonObject(with: data) else {
      return nil
    }
    return object as? [String: Any]
  }

  private static func matchesGroupRoute(_ value: String, expectedHash: String) -> Bool {
    let canonical = value.hasPrefix("group:")
      ? String(value.dropFirst("group:".count))
      : value
    return !canonical.isEmpty && sha256(canonical) == expectedHash
  }

  private static func exactString(_ value: Any?, maxBytes: Int) -> String? {
    guard let value = value as? String,
          let normalized = boundedTrimmed(value, maxBytes: maxBytes),
          normalized == value else { return nil }
    return value
  }

  private static func boundedTrimmed(_ value: String, maxBytes: Int) -> String? {
    let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalized.isEmpty, normalized.utf8.count <= maxBytes else { return nil }
    return normalized
  }

  private static func isExactOne(_ value: Any?) -> Bool {
    guard let number = value as? NSNumber,
          CFGetTypeID(number) != CFBooleanGetTypeID() else { return false }
    return number.doubleValue == 1
  }

  private static func isValidFlutterNotificationId(_ value: Any?) -> Bool {
    guard let number = value as? NSNumber,
          CFGetTypeID(number) != CFBooleanGetTypeID(),
          number.doubleValue.isFinite,
          number.doubleValue.rounded() == number.doubleValue,
          number.int64Value >= 0,
          number.int64Value <= Int64(Int32.max) else { return false }
    return true
  }

  private static func sha256(_ value: String) -> String {
    SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
  }
}

struct IosNotificationRecoveryIdentity: Equatable {
  let accountPeerId: String
  let lane: IosNotificationRecoveryLane
  let conversationId: String
  let eventId: String?
  let kind: IosNotificationRecoveryKind
}

struct IosNotificationCanonicalIdentity: Hashable {
  let lane: IosNotificationRecoveryLane
  let conversationId: String
  let eventId: String
}

struct IosNotificationRecoveryBegin: Equatable {
  let generation: UInt64
  let watermark: UInt64
  let mailboxAlertLease: IosNotificationMailboxAlertLease?
}

enum IosNotificationMailboxAlertLeasePhase: String, Codable {
  case prepared = "PREPARED"
  case publishing = "PUBLISHING"
  case audibleAmbiguous = "AUDIBLE_AMBIGUOUS"
}

/// Bounded compatibility projection for one fixed mailbox wake. Raw account,
/// binding and event identifiers never enter this store.
struct IosNotificationMailboxAlertLease: Codable, Equatable {
  let token: String
  let accountHash: String
  let bindingHash: String
  let requestIdentifier: String
  let generation: UInt64
  let sequence: UInt64
  var phase: IosNotificationMailboxAlertLeasePhase

  var methodChannelMap: [String: Any] {
    [
      "token": token,
      "accountHash": accountHash,
      "bindingHash": bindingHash,
      "requestIdentifier": requestIdentifier,
      "generation": Int64(generation),
      "sequence": Int64(sequence),
      "phase": phase.rawValue,
    ]
  }
}

struct IosNotificationBadgeSnapshot: Equatable {
  let revision: UInt64
  let count: Int
}

enum IosNotificationRecoveryClaim: Equatable {
  case unique
  case sameRequestDuplicate
  case duplicate
  case accountMismatch
  case unsupportedSchema
  case corruptState
  case capacityExceeded
  case storageUnavailable
}

private enum IosNotificationRecoveryDeliveryPhase: String, Codable {
  case prepared
  case committed
}

private struct IosNotificationRecoveryRow: Codable, Equatable {
  let accountHash: String
  let lane: IosNotificationRecoveryLane
  let conversationHash: String
  let eventHash: String?
  let kind: IosNotificationRecoveryKind
  let sequence: UInt64
  var observedDelivered: Bool
  var retired: Bool
  var deliveryPhase: IosNotificationRecoveryDeliveryPhase
}

private struct IosNotificationPendingOrdinaryEvent: Codable, Equatable {
  let accountHash: String
  let conversationHash: String
  let eventHash: String
  let sequence: UInt64
}

private struct IosNotificationRecentEventClaim: Codable, Equatable {
  let accountHash: String
  let eventHash: String
  let sequence: UInt64
}

private struct IosNotificationRecoveryState: Codable, Equatable {
  static let schemaVersion = 1

  var version = schemaVersion
  var revision: UInt64 = 0
  var nextSequence: UInt64 = 1
  var activeAccountHash: String?
  var nseClaimsSuspended = false
  var generation: UInt64 = 0
  var canonicalBadgeBaseline = 0
  var canonicalOrdinaryEventHashes: [String] = []
  var pendingOrdinaryEvents: [IosNotificationPendingOrdinaryEvent] = []
  var recentEventClaims: [IosNotificationRecentEventClaim] = []
  var requestRows: [String: IosNotificationRecoveryRow] = [:]
  var mailboxAlertLease: IosNotificationMailboxAlertLease?

  private enum CodingKeys: String, CodingKey {
    case version
    case revision
    case nextSequence
    case activeAccountHash
    case nseClaimsSuspended
    case generation
    case canonicalBadgeBaseline
    case canonicalOrdinaryEventHashes
    case pendingOrdinaryEvents
    case recentEventClaims
    case requestRows
    case mailboxAlertLease
  }

  init() {}

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    version = try container.decode(Int.self, forKey: .version)
    revision = try container.decode(UInt64.self, forKey: .revision)
    nextSequence = try container.decode(UInt64.self, forKey: .nextSequence)
    activeAccountHash = try container.decodeIfPresent(
      String.self,
      forKey: .activeAccountHash
    )
    nseClaimsSuspended = try container.decodeIfPresent(
      Bool.self,
      forKey: .nseClaimsSuspended
    ) ?? false
    generation = try container.decode(UInt64.self, forKey: .generation)
    canonicalBadgeBaseline = try container.decode(
      Int.self,
      forKey: .canonicalBadgeBaseline
    )
    // Tolerate v1 files written by an earlier Plan 333 build before canonical
    // replay memory was added. Unknown schema versions still fail closed.
    canonicalOrdinaryEventHashes = try container.decodeIfPresent(
      [String].self,
      forKey: .canonicalOrdinaryEventHashes
    ) ?? []
    pendingOrdinaryEvents = try container.decode(
      [IosNotificationPendingOrdinaryEvent].self,
      forKey: .pendingOrdinaryEvents
    )
    recentEventClaims = try container.decodeIfPresent(
      [IosNotificationRecentEventClaim].self,
      forKey: .recentEventClaims
    ) ?? []
    requestRows = try container.decode(
      [String: IosNotificationRecoveryRow].self,
      forKey: .requestRows
    )
    mailboxAlertLease = try container.decodeIfPresent(
      IosNotificationMailboxAlertLease.self,
      forKey: .mailboxAlertLease
    )
  }
}

private enum IosNotificationRecoveryLoad {
  case missing
  case valid(IosNotificationRecoveryState)
  case unsupported
  case corrupt
  case unavailable
}

/// The cross-process source of truth shared by Runner and the notification
/// service extension. The JSON inode is replaced atomically; the flock inode is
/// deliberately separate and stable for the lifetime of the installation.
final class IosNotificationRecoveryStore {
  private static let stateFileName = "ios_notification_recovery_v1.json"
  private static let stateLockFileName = ".ios_notification_recovery.lock"
  private static let badgeLockFileName = ".ios_notification_badge.lock"

  private let directory: URL
  private let stateURL: URL
  private let stateLockURL: URL
  let badgeLockURL: URL
  private let maxRows: Int
  private let maxCanonicalEvents: Int
  private let maxRecentEvents: Int
  private let fileManager: FileManager
  private let currentOpaqueBinding: () -> String?

  convenience init?(
    appGroupIdentifier: String = "group.com.mknoon.app.share",
    maxRows: Int = 512,
    maxCanonicalEvents: Int = 4_096,
    maxRecentEvents: Int = 256,
    currentOpaqueBinding: @escaping () -> String? = {
      IosNotificationRecoveryStore.readCurrentOpaqueBinding()
    }
  ) {
    guard let container = FileManager.default.containerURL(
      forSecurityApplicationGroupIdentifier: appGroupIdentifier
    ) else {
      return nil
    }
    self.init(
      directory: container,
      maxRows: maxRows,
      maxCanonicalEvents: maxCanonicalEvents,
      maxRecentEvents: maxRecentEvents,
      currentOpaqueBinding: currentOpaqueBinding
    )
  }

  init(
    directory: URL,
    maxRows: Int = 512,
    maxCanonicalEvents: Int = 4_096,
    maxRecentEvents: Int = 256,
    fileManager: FileManager = .default,
    currentOpaqueBinding: @escaping () -> String? = { nil }
  ) {
    self.directory = directory
    stateURL = directory.appendingPathComponent(Self.stateFileName)
    stateLockURL = directory.appendingPathComponent(Self.stateLockFileName)
    badgeLockURL = directory.appendingPathComponent(Self.badgeLockFileName)
    self.maxRows = max(0, maxRows)
    self.maxCanonicalEvents = max(0, maxCanonicalEvents)
    self.maxRecentEvents = max(0, maxRecentEvents)
    self.fileManager = fileManager
    self.currentOpaqueBinding = currentOpaqueBinding
    try? fileManager.createDirectory(
      at: directory,
      withIntermediateDirectories: true
    )
  }

  /// Persists the fixed-wake ambiguity boundary before any network/decrypt
  /// work. A newer fixed wake supersedes the single bounded lease.
  func prepareMailboxAlertLease(
    requestIdentifier: String
  ) -> IosNotificationMailboxAlertLease? {
    guard Self.isBoundedOpaqueString(requestIdentifier, maxBytes: 512),
          let opaqueBinding = currentOpaqueBinding(),
          Self.isCanonicalOpaqueBinding(opaqueBinding) else {
      return nil
    }
    return withBoundedLock(defaultValue: nil) {
      guard case var .valid(state) = loadState(),
            !state.nseClaimsSuspended,
            let accountHash = state.activeAccountHash else {
        return nil
      }
      return prepareMailboxAlertLeaseLocked(
        state: &state,
        requestIdentifier: requestIdentifier,
        accountHash: accountHash,
        opaqueBinding: opaqueBinding
      )
    }
  }

  func prepareMailboxAlertLease(
    requestIdentifier: String,
    accountPeerId: String,
    opaqueBinding: String
  ) -> IosNotificationMailboxAlertLease? {
    guard Self.isBoundedOpaqueString(requestIdentifier, maxBytes: 512),
          Self.isBoundedOpaqueString(accountPeerId, maxBytes: 512),
          Self.isCanonicalOpaqueBinding(opaqueBinding) else {
      return nil
    }
    return withBoundedLock(defaultValue: nil) {
      var state: IosNotificationRecoveryState
      switch loadState() {
      case let .valid(value): state = value
      case .missing: state = IosNotificationRecoveryState()
      case .unsupported, .corrupt, .unavailable: return nil
      }
      let accountHash = Self.hash(domain: "account", value: accountPeerId)
      guard !state.nseClaimsSuspended,
            state.activeAccountHash == nil ||
              state.activeAccountHash == accountHash,
            state.generation < UInt64(Int64.max) else {
        return nil
      }
      if state.activeAccountHash == nil {
        state.activeAccountHash = accountHash
        state.generation += 1
      }
      return prepareMailboxAlertLeaseLocked(
        state: &state,
        requestIdentifier: requestIdentifier,
        accountHash: accountHash,
        opaqueBinding: opaqueBinding
      )
    }
  }

  func mailboxAlertLeaseMatches(
    _ expected: IosNotificationMailboxAlertLease,
    accountPeerId: String,
    opaqueBinding: String
  ) -> Bool {
    guard Self.isBoundedOpaqueString(accountPeerId, maxBytes: 512),
          Self.isCanonicalOpaqueBinding(opaqueBinding) else {
      return false
    }
    return readBounded(defaultValue: false) { state in
      guard let current = state.mailboxAlertLease else { return false }
      return current == expected &&
        current.accountHash == Self.hash(domain: "account", value: accountPeerId) &&
        current.bindingHash == Self.hash(domain: "binding", value: opaqueBinding)
    }
  }

  @discardableResult
  func markMailboxAlertLeasePublishing(
    token: String,
    generation: UInt64,
    sequence: UInt64
  ) -> Bool {
    mutateExistingBounded { state in
      guard var lease = state.mailboxAlertLease,
            lease.token == token,
            lease.generation == generation,
            lease.sequence == sequence,
            (lease.phase == .prepared || lease.phase == .publishing) else {
        return false
      }
      lease.phase = .publishing
      state.mailboxAlertLease = lease
      return true
    }
  }

  @discardableResult
  func markMailboxAlertLeaseAudibleAmbiguous(
    token: String,
    generation: UInt64,
    sequence: UInt64
  ) -> Bool {
    mutateExistingBounded { state in
      guard var lease = state.mailboxAlertLease,
            lease.token == token,
            lease.generation == generation,
            lease.sequence == sequence,
            lease.phase == .publishing || lease.phase == .prepared else {
        return false
      }
      lease.phase = .audibleAmbiguous
      state.mailboxAlertLease = lease
      return true
    }
  }

  @discardableResult
  func retireMailboxAlertLease(
    token: String,
    generation: UInt64,
    sequence: UInt64
  ) -> Bool {
    mutateExistingBounded { state in
      guard let lease = state.mailboxAlertLease,
            lease.token == token,
            lease.generation == generation,
            lease.sequence == sequence else {
        return false
      }
      state.mailboxAlertLease = nil
      return true
    }
  }

  @discardableResult
  func consumeMailboxAlertLease(
    accountPeerId: String,
    generation: UInt64,
    sequence: UInt64,
    watermark: UInt64
  ) -> Bool {
    mutateExistingBounded { state in
      let accountHash = Self.hash(domain: "account", value: accountPeerId)
      guard let lease = state.mailboxAlertLease,
            state.activeAccountHash == accountHash,
            lease.accountHash == accountHash,
            lease.generation == generation,
            lease.sequence == sequence,
            lease.sequence <= watermark else {
        return false
      }
      state.mailboxAlertLease = nil
      return true
    }
  }

  func claimPrepared(
    requestIdentifier: String,
    identity: IosNotificationRecoveryIdentity
  ) -> IosNotificationRecoveryClaim {
    guard !requestIdentifier.isEmpty else { return .storageUnavailable }
    return withLock(defaultValue: .storageUnavailable) {
      var state: IosNotificationRecoveryState
      switch loadState() {
      case let .valid(value): state = value
      case .missing: state = IosNotificationRecoveryState()
      case .unsupported: return .unsupportedSchema
      case .corrupt: return .corruptState
      case .unavailable: return .storageUnavailable
      }

      let accountHash = Self.hash(
        domain: "account",
        value: identity.accountPeerId
      )
      if state.nseClaimsSuspended {
        return .accountMismatch
      }
      if let active = state.activeAccountHash, active != accountHash {
        return .accountMismatch
      }
      if state.activeAccountHash == nil {
        state.activeAccountHash = accountHash
        state.generation &+= 1
      }

      let conversationHash = Self.conversationHash(
        lane: identity.lane,
        conversationId: identity.conversationId
      )
      let eventHash = identity.eventId.map {
        Self.eventHash(
          lane: identity.lane,
          kind: identity.kind,
          conversationHash: conversationHash,
          eventId: $0
        )
      }

      if let existing = state.requestRows[requestIdentifier] {
        guard existing.accountHash == accountHash,
              existing.lane == identity.lane,
              existing.conversationHash == conversationHash,
              existing.eventHash == eventHash,
              existing.kind == identity.kind else {
          return .accountMismatch
        }
        return identity.kind == .ordinary && eventHash != nil
          ? .sameRequestDuplicate
          : .duplicate
      }
      guard state.requestRows.count < maxRows else {
        return .capacityExceeded
      }

      let isDuplicate = eventHash.map { candidate in
        let hasRequestCustody = state.requestRows.values.contains { row in
          row.accountHash == accountHash &&
            row.lane == identity.lane &&
            row.conversationHash == conversationHash &&
            row.kind == identity.kind &&
            row.eventHash == candidate
        }
        let wasRecentlySeen = state.recentEventClaims.contains {
          $0.accountHash == accountHash && $0.eventHash == candidate
        }
        if identity.kind == .reaction {
          return hasRequestCustody || wasRecentlySeen
        }
        let isPending = state.pendingOrdinaryEvents.contains {
          $0.accountHash == accountHash &&
            $0.conversationHash == conversationHash &&
            $0.eventHash == candidate
        }
        let isCanonical = state.canonicalOrdinaryEventHashes.contains(candidate)
        return hasRequestCustody || wasRecentlySeen || isPending || isCanonical
      } ?? false
      let sequence = state.nextSequence
      state.nextSequence &+= 1
      state.requestRows[requestIdentifier] = IosNotificationRecoveryRow(
        accountHash: accountHash,
        lane: identity.lane,
        conversationHash: conversationHash,
        eventHash: eventHash,
        kind: identity.kind,
        sequence: sequence,
        observedDelivered: false,
        retired: false,
        deliveryPhase: .prepared
      )
      if let eventHash,
         !state.recentEventClaims.contains(where: {
           $0.accountHash == accountHash && $0.eventHash == eventHash
         }) {
        state.recentEventClaims.append(IosNotificationRecentEventClaim(
          accountHash: accountHash,
          eventHash: eventHash,
          sequence: sequence
        ))
        let overflow = state.recentEventClaims.count - maxRecentEvents
        if overflow > 0 {
          state.recentEventClaims.removeFirst(overflow)
        }
      }
      if identity.kind == .ordinary,
         let eventHash,
         !isDuplicate,
         !state.pendingOrdinaryEvents.contains(where: {
           $0.accountHash == accountHash && $0.eventHash == eventHash
         }) {
        state.pendingOrdinaryEvents.append(
          IosNotificationPendingOrdinaryEvent(
            accountHash: accountHash,
            conversationHash: conversationHash,
            eventHash: eventHash,
            sequence: sequence
          )
        )
      }
      state.revision &+= 1
      guard writeState(state) else { return .storageUnavailable }
      return isDuplicate ? .duplicate : .unique
    }
  }

  @discardableResult
  func markCommitted(requestIdentifier: String) -> Bool {
    mutateExisting { state in
      guard var row = state.requestRows[requestIdentifier] else { return false }
      guard row.deliveryPhase != .committed else { return false }
      row.deliveryPhase = .committed
      state.requestRows[requestIdentifier] = row
      return true
    }
  }

  /// Runner-only entry point. Corrupt version-1 bytes are quarantined here so
  /// Runner can rebuild from its canonical database. An unknown future schema
  /// is never renamed or overwritten: an older binary must fail closed.
  func beginReconciliation(accountPeerId: String) -> IosNotificationRecoveryBegin? {
    withLock(defaultValue: nil) {
      let loaded = loadState()
      if case .unsupported = loaded { return nil }
      if case .unavailable = loaded { return nil }

      var state: IosNotificationRecoveryState
      switch loaded {
      case let .valid(value):
        state = value
      case .missing:
        state = IosNotificationRecoveryState()
      case .corrupt:
        guard quarantineCorruptState() else { return nil }
        state = IosNotificationRecoveryState()
      case .unsupported, .unavailable:
        return nil
      }

      let accountHash = Self.hash(domain: "account", value: accountPeerId)
      if state.activeAccountHash != accountHash {
        for key in state.requestRows.keys {
          guard var row = state.requestRows[key] else { continue }
          if row.accountHash != accountHash {
            row.retired = true
            state.requestRows[key] = row
          }
        }
        state.pendingOrdinaryEvents.removeAll { $0.accountHash != accountHash }
        state.recentEventClaims.removeAll()
        state.canonicalBadgeBaseline = 0
        state.canonicalOrdinaryEventHashes.removeAll()
        state.mailboxAlertLease = nil
        state.activeAccountHash = accountHash
      }
      let currentBindingHash = currentOpaqueBinding().flatMap { binding in
        Self.isCanonicalOpaqueBinding(binding)
          ? Self.hash(domain: "binding", value: binding)
          : nil
      }
      if let lease = state.mailboxAlertLease,
         lease.accountHash != accountHash ||
           lease.bindingHash != currentBindingHash {
        state.mailboxAlertLease = nil
      }
      state.nseClaimsSuspended = false
      state.generation &+= 1
      state.revision &+= 1
      let begin = IosNotificationRecoveryBegin(
        generation: state.generation,
        watermark: state.nextSequence == 0 ? 0 : state.nextSequence - 1,
        mailboxAlertLease: state.mailboxAlertLease
      )
      guard writeState(state) else { return nil }
      return begin
    }
  }

  @discardableResult
  func commitCanonicalState(
    accountPeerId: String,
    generation: UInt64,
    watermark: UInt64,
    canonicalBadgeCount: Int,
    identities: [IosNotificationCanonicalIdentity]
  ) -> Bool {
    withLock(defaultValue: false) {
      guard canonicalBadgeCount == identities.count,
            identities.count <= maxCanonicalEvents,
            Set(identities).count == identities.count else {
        return false
      }
      guard case var .valid(state) = loadState() else { return false }
      let accountHash = Self.hash(domain: "account", value: accountPeerId)
      guard state.activeAccountHash == accountHash,
            state.generation == generation,
            watermark < state.nextSequence else {
        return false
      }

      let eligibleEvents = Set(identities.map { identity in
        let conversationHash = Self.conversationHash(
          lane: identity.lane,
          conversationId: identity.conversationId
        )
        return Self.eventHash(
          lane: identity.lane,
          kind: .ordinary,
          conversationHash: conversationHash,
          eventId: identity.eventId
        )
      })
      let eligibleConversations = Set(identities.map {
        Self.conversationHash(
          lane: $0.lane,
          conversationId: $0.conversationId
        )
      })

      state.canonicalBadgeBaseline = max(0, canonicalBadgeCount)
      state.canonicalOrdinaryEventHashes = eligibleEvents.sorted()
      // This commit is the authoritative post-drain database view for every
      // event it contains, including an NSE claim that arrived after begin but
      // landed in the database before the canonical query. Later claims absent
      // from that view remain pending.
      state.pendingOrdinaryEvents.removeAll {
        $0.accountHash == accountHash && (
          $0.sequence <= watermark || eligibleEvents.contains($0.eventHash)
        )
      }
      for key in state.requestRows.keys {
        guard var row = state.requestRows[key],
              row.accountHash == accountHash,
              row.sequence <= watermark else {
          continue
        }
        let shouldRetire: Bool
        if row.kind == .ordinary, let eventHash = row.eventHash {
          shouldRetire = !eligibleEvents.contains(eventHash)
        } else {
          // Identity-free ordinary notifications and reactions cannot be
          // retired by an unrelated per-message omission. They are retired
          // only when the whole conversation has no eligible unread event.
          shouldRetire = !eligibleConversations.contains(row.conversationHash)
        }
        if shouldRetire {
          row.retired = true
          state.requestRows[key] = row
        }
      }
      state.revision &+= 1
      return writeState(state)
    }
  }

  @discardableResult
  func retireConversation(
    accountPeerId: String,
    lane: IosNotificationRecoveryLane,
    conversationId: String
  ) -> UInt64? {
    withLock(defaultValue: nil) {
      guard case var .valid(state) = loadState() else { return nil }
      let accountHash = Self.hash(domain: "account", value: accountPeerId)
      guard state.activeAccountHash == accountHash else { return nil }
      let conversationHash = Self.conversationHash(
        lane: lane,
        conversationId: conversationId
      )
      let watermark = state.nextSequence == 0 ? 0 : state.nextSequence - 1
      for key in state.requestRows.keys {
        guard var row = state.requestRows[key],
              row.accountHash == accountHash,
              row.lane == lane,
              row.conversationHash == conversationHash,
              row.sequence <= watermark else {
          continue
        }
        row.retired = true
        state.requestRows[key] = row
      }
      state.pendingOrdinaryEvents.removeAll {
        $0.accountHash == accountHash &&
          $0.conversationHash == conversationHash &&
          $0.sequence <= watermark
      }
      // Conversation retirement supersedes any canonical read captured before
      // this mutation. A stale complete commit must not restore the old badge
      // baseline or canonical replay memory after the conversation was read.
      state.generation &+= 1
      state.revision &+= 1
      guard writeState(state) else { return nil }
      return watermark
    }
  }

  @discardableResult
  func clearAccount() -> UInt64? {
    withLock(defaultValue: nil) {
      let loaded = loadState()
      if case .unsupported = loaded { return nil }
      if case .unavailable = loaded { return nil }
      var state: IosNotificationRecoveryState
      switch loaded {
      case let .valid(value): state = value
      case .missing: state = IosNotificationRecoveryState()
      case .corrupt:
        guard quarantineCorruptState() else { return nil }
        state = IosNotificationRecoveryState()
      case .unsupported, .unavailable: return nil
      }
      let watermark = state.nextSequence == 0 ? 0 : state.nextSequence - 1
      for key in state.requestRows.keys {
        guard var row = state.requestRows[key], row.sequence <= watermark else {
          continue
        }
        row.retired = true
        state.requestRows[key] = row
      }
      state.pendingOrdinaryEvents.removeAll()
      state.recentEventClaims.removeAll()
      state.canonicalBadgeBaseline = 0
      state.canonicalOrdinaryEventHashes.removeAll()
      state.mailboxAlertLease = nil
      state.activeAccountHash = nil
      state.nseClaimsSuspended = true
      state.generation &+= 1
      state.revision &+= 1
      guard writeState(state) else { return nil }
      return watermark
    }
  }

  @discardableResult
  func markDelivered(_ requestIdentifiers: Set<String>) -> Bool {
    guard !requestIdentifiers.isEmpty else { return true }
    return mutateExisting { state in
      var changed = false
      for key in requestIdentifiers {
        guard var row = state.requestRows[key], !row.observedDelivered else {
          continue
        }
        row.observedDelivered = true
        state.requestRows[key] = row
        changed = true
      }
      return changed
    }
  }

  func removalCandidates(watermark: UInt64) -> [String] {
    read(defaultValue: []) { state in
      state.requestRows.compactMap { key, row in
        row.retired && row.observedDelivered && row.sequence <= watermark
          ? key
          : nil
      }.sorted()
    }
  }

  /// Prunes only rows that were actually observed in Notification Center and
  /// are now absent. A prepared/unobserved row may simply not have been
  /// delivered yet and must remain available for a later exact-removal retry.
  @discardableResult
  func pruneObservedAbsent(
    remainingDeliveredIdentifiers: Set<String>,
    watermark: UInt64
  ) -> Bool {
    mutateExisting { state in
      let keys = state.requestRows.compactMap { key, row in
        row.sequence <= watermark &&
          row.observedDelivered &&
          !remainingDeliveredIdentifiers.contains(key) ? key : nil
      }
      guard !keys.isEmpty else { return false }
      for key in keys { state.requestRows.removeValue(forKey: key) }
      return true
    }
  }

  /// The post-removal readback may prune only rows selected for this exact
  /// removal pass. A non-selected card disappearing between the two inventory
  /// reads is handled as a user dismissal by the next initial read.
  @discardableResult
  func pruneSelectedObservedAbsent(
    selectedIdentifiers: Set<String>,
    remainingDeliveredIdentifiers: Set<String>,
    watermark: UInt64
  ) -> Bool {
    guard !selectedIdentifiers.isEmpty else { return false }
    return mutateExisting { state in
      let keys = state.requestRows.compactMap { key, row in
        selectedIdentifiers.contains(key) &&
          row.sequence <= watermark &&
          row.observedDelivered &&
          !remainingDeliveredIdentifiers.contains(key) ? key : nil
      }
      guard !keys.isEmpty else { return false }
      for key in keys { state.requestRows.removeValue(forKey: key) }
      return true
    }
  }

  func validatesReconciliation(
    accountPeerId: String,
    generation: UInt64,
    watermark: UInt64
  ) -> Bool {
    read(defaultValue: false) { state in
      state.activeAccountHash == Self.hash(
        domain: "account",
        value: accountPeerId
      ) &&
        state.generation == generation &&
        watermark < state.nextSequence
    }
  }

  /// Foreground `willPresent` with no presentation is a positive observation,
  /// not an inventory absence. Remove only that exact custody row while keeping
  /// its pending unread badge event for the upcoming canonical Dart drain.
  @discardableResult
  func markForegroundSuppressed(requestIdentifier: String) -> Bool {
    mutateExisting { state in
      guard state.requestRows.removeValue(forKey: requestIdentifier) != nil else {
        return false
      }
      // The foreground Dart handler has not necessarily entered its mutation
      // scope yet. Fence any canonical read captured before willPresent so it
      // cannot absorb this pending event before Dart handles it.
      state.generation &+= 1
      return true
    }
  }

  func desiredBadgeSnapshot() -> IosNotificationBadgeSnapshot? {
    read(defaultValue: nil) { state in
      let pendingCount: Int
      if let activeAccountHash = state.activeAccountHash {
        pendingCount = Set(
          state.pendingOrdinaryEvents
            .filter { $0.accountHash == activeAccountHash }
            .map(\.eventHash)
        ).count
      } else {
        pendingCount = 0
      }
      return IosNotificationBadgeSnapshot(
        revision: state.revision,
        count: max(0, state.canonicalBadgeBaseline + pendingCount)
      )
    }
  }

  // MARK: - Test observations

  func containsRequestForTesting(_ requestIdentifier: String) -> Bool {
    read(defaultValue: false) { $0.requestRows[requestIdentifier] != nil }
  }

  func rowObservedForTesting(_ requestIdentifier: String) -> Bool {
    read(defaultValue: false) {
      $0.requestRows[requestIdentifier]?.observedDelivered == true
    }
  }

  // MARK: - Persistence

  private func mutateExisting(
    _ mutation: (inout IosNotificationRecoveryState) -> Bool
  ) -> Bool {
    withLock(defaultValue: false) {
      guard case var .valid(state) = loadState() else { return false }
      guard mutation(&state) else { return false }
      state.revision &+= 1
      return writeState(state)
    }
  }

  private func mutateExistingBounded(
    _ mutation: (inout IosNotificationRecoveryState) -> Bool
  ) -> Bool {
    withBoundedLock(defaultValue: false) {
      guard case var .valid(state) = loadState() else { return false }
      guard mutation(&state) else { return false }
      guard state.revision < UInt64.max else { return false }
      state.revision += 1
      return writeState(state)
    }
  }

  private func prepareMailboxAlertLeaseLocked(
    state: inout IosNotificationRecoveryState,
    requestIdentifier: String,
    accountHash: String,
    opaqueBinding: String
  ) -> IosNotificationMailboxAlertLease? {
    guard state.activeAccountHash == accountHash,
          state.nextSequence > 0,
          state.nextSequence < UInt64(Int64.max),
          state.generation > 0,
          state.generation <= UInt64(Int64.max),
          state.revision < UInt64.max else {
      return nil
    }
    let lease = IosNotificationMailboxAlertLease(
      token: UUID().uuidString,
      accountHash: accountHash,
      bindingHash: Self.hash(domain: "binding", value: opaqueBinding),
      requestIdentifier: requestIdentifier,
      generation: state.generation,
      sequence: state.nextSequence,
      phase: .prepared
    )
    state.nextSequence += 1
    state.mailboxAlertLease = lease
    state.revision += 1
    guard writeState(state) else { return nil }
    return lease
  }

  private func read<T>(
    defaultValue: T,
    _ body: (IosNotificationRecoveryState) -> T
  ) -> T {
    withLock(defaultValue: defaultValue) {
      guard case let .valid(state) = loadState() else { return defaultValue }
      return body(state)
    }
  }

  private func readBounded<T>(
    defaultValue: T,
    _ body: (IosNotificationRecoveryState) -> T
  ) -> T {
    withBoundedLock(defaultValue: defaultValue) {
      guard case let .valid(state) = loadState() else { return defaultValue }
      return body(state)
    }
  }

  private func withLock<T>(defaultValue: T, _ body: () -> T) -> T {
    try? fileManager.createDirectory(
      at: directory,
      withIntermediateDirectories: true
    )
    let fd = open(stateLockURL.path, O_RDWR | O_CREAT, S_IRUSR | S_IWUSR)
    guard fd >= 0 else { return defaultValue }
    defer {
      flock(fd, LOCK_UN)
      close(fd)
    }
    guard flock(fd, LOCK_EX) == 0 else { return defaultValue }
    return body()
  }

  /// NSE-only lease operations must lose quickly to Runner/rich recovery
  /// contention. They never schedule late mutation after this function exits.
  private func withBoundedLock<T>(
    defaultValue: T,
    timeoutMs: UInt64 = 150,
    _ body: () -> T
  ) -> T {
    try? fileManager.createDirectory(
      at: directory,
      withIntermediateDirectories: true
    )
    let fd = open(stateLockURL.path, O_RDWR | O_CREAT, S_IRUSR | S_IWUSR)
    guard fd >= 0 else { return defaultValue }
    defer {
      flock(fd, LOCK_UN)
      close(fd)
    }
    let started = DispatchTime.now().uptimeNanoseconds
    let timeoutNs = timeoutMs * 1_000_000
    while flock(fd, LOCK_EX | LOCK_NB) != 0 {
      guard errno == EWOULDBLOCK || errno == EAGAIN,
            DispatchTime.now().uptimeNanoseconds - started < timeoutNs else {
        return defaultValue
      }
      usleep(2_000)
    }
    return body()
  }

  private func loadState() -> IosNotificationRecoveryLoad {
    guard fileManager.fileExists(atPath: stateURL.path) else { return .missing }
    guard let data = try? Data(contentsOf: stateURL) else { return .unavailable }
    guard let object = try? JSONSerialization.jsonObject(with: data),
          let root = object as? [String: Any],
          let versionNumber = root["version"] as? NSNumber else {
      return .corrupt
    }
    let version = versionNumber.intValue
    guard version == IosNotificationRecoveryState.schemaVersion else {
      return .unsupported
    }
    guard let state = try? JSONDecoder().decode(
      IosNotificationRecoveryState.self,
      from: data
    ),
      state.version == IosNotificationRecoveryState.schemaVersion,
      state.nextSequence > 0,
      state.canonicalBadgeBaseline >= 0,
      state.canonicalOrdinaryEventHashes.count <= maxCanonicalEvents,
      Set(state.canonicalOrdinaryEventHashes).count ==
        state.canonicalOrdinaryEventHashes.count,
      state.canonicalOrdinaryEventHashes.allSatisfy(Self.isStoredHash),
      state.recentEventClaims.count <= maxRecentEvents,
      state.recentEventClaims.allSatisfy({ event in
        Self.isStoredHash(event.accountHash) &&
          Self.isStoredHash(event.eventHash) &&
          event.sequence < state.nextSequence
      }),
      zip(
        state.recentEventClaims,
        state.recentEventClaims.dropFirst()
      ).allSatisfy({ pair in pair.0.sequence < pair.1.sequence }),
      Set(state.recentEventClaims.map {
        "\($0.accountHash):\($0.eventHash)"
      }).count == state.recentEventClaims.count,
      Self.isValidMailboxAlertLease(
        state.mailboxAlertLease,
        nextSequence: state.nextSequence
      ) else {
      return .corrupt
    }
    return .valid(state)
  }

  private func writeState(_ state: IosNotificationRecoveryState) -> Bool {
    let temporaryURL = directory.appendingPathComponent(
      ".\(Self.stateFileName).\(UUID().uuidString).tmp"
    )
    do {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.sortedKeys]
      let data = try encoder.encode(state)
      try data.write(to: temporaryURL, options: [])
      try fileManager.setAttributes(
        [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
        ofItemAtPath: temporaryURL.path
      )
      var values = URLResourceValues()
      values.isExcludedFromBackup = true
      var protectedURL = temporaryURL
      try protectedURL.setResourceValues(values)
      let fd = open(temporaryURL.path, O_RDONLY)
      guard fd >= 0 else {
        try? fileManager.removeItem(at: temporaryURL)
        return false
      }
      let fileSyncResult = fsync(fd)
      close(fd)
      guard fileSyncResult == 0 else {
        try? fileManager.removeItem(at: temporaryURL)
        return false
      }
      guard rename(temporaryURL.path, stateURL.path) == 0 else {
        try? fileManager.removeItem(at: temporaryURL)
        return false
      }
      let directoryFD = open(directory.path, O_RDONLY)
      guard directoryFD >= 0 else { return false }
      let directorySyncResult = fsync(directoryFD)
      close(directoryFD)
      guard directorySyncResult == 0 else { return false }
      return true
    } catch {
      try? fileManager.removeItem(at: temporaryURL)
      return false
    }
  }

  private func quarantineCorruptState() -> Bool {
    guard fileManager.fileExists(atPath: stateURL.path) else { return true }
    let quarantineURL = directory.appendingPathComponent(
      "ios_notification_recovery_corrupt_\(UUID().uuidString).json"
    )
    do {
      try fileManager.moveItem(at: stateURL, to: quarantineURL)
      return true
    } catch {
      return false
    }
  }

  private static func hash(domain: String, value: String) -> String {
    let digest = SHA256.hash(
      data: Data("mknoon.notification-recovery.v1|\(domain)|\(value)".utf8)
    )
    return digest.map { String(format: "%02x", $0) }.joined()
  }

  private static func conversationHash(
    lane: IosNotificationRecoveryLane,
    conversationId: String
  ) -> String {
    hash(
      domain: "conversation.\(lane.rawValue)",
      value: conversationId
    )
  }

  private static func eventHash(
    lane: IosNotificationRecoveryLane,
    kind: IosNotificationRecoveryKind,
    conversationHash: String,
    eventId: String
  ) -> String {
    hash(
      domain: "event.\(lane.rawValue).\(kind.rawValue).\(conversationHash)",
      value: eventId
    )
  }

  private static func isStoredHash(_ value: String) -> Bool {
    value.utf8.count == 64 && value.utf8.allSatisfy { byte in
      (byte >= 48 && byte <= 57) || (byte >= 97 && byte <= 102)
    }
  }

  private static func isCanonicalOpaqueBinding(_ value: String) -> Bool {
    guard value.utf8.count == 67, value.hasPrefix("v1:") else { return false }
    return value.dropFirst(3).utf8.allSatisfy { byte in
      (byte >= 48 && byte <= 57) || (byte >= 97 && byte <= 102)
    }
  }

  private static func isValidMailboxAlertLease(
    _ lease: IosNotificationMailboxAlertLease?,
    nextSequence: UInt64
  ) -> Bool {
    guard let lease else { return true }
    return isBoundedOpaqueString(lease.token, maxBytes: 128) &&
      isStoredHash(lease.accountHash) &&
      isStoredHash(lease.bindingHash) &&
      isBoundedOpaqueString(lease.requestIdentifier, maxBytes: 512) &&
      lease.generation > 0 &&
      lease.generation <= UInt64(Int64.max) &&
      lease.sequence > 0 &&
      lease.sequence < nextSequence &&
      lease.sequence <= UInt64(Int64.max)
  }

  private static func isBoundedOpaqueString(
    _ value: String,
    maxBytes: Int
  ) -> Bool {
    !value.isEmpty && value.utf8.count <= maxBytes &&
      value == value.trimmingCharacters(in: .whitespacesAndNewlines) &&
      value.unicodeScalars.allSatisfy { scalar in
        scalar.value > 31 && !(127...159).contains(scalar.value)
      }
  }

  private static func readCurrentOpaqueBinding() -> String? {
    var query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrAccount as String: "canonical_runtime_shared_account_binding_v1",
      kSecAttrService as String: "flutter_secure_storage_service",
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
      kSecAttrAccessGroup as String:
        "397R9Q4WMX.group.com.mknoon.app.share",
    ]
#if MKNOON_SIMS_GROUP_MEDIA_269
    query[kSecAttrAccessGroup as String] =
      "397R9Q4WMX.group.com.mknoon.sims.groupmedia269.share"
#endif
    var item: CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
          let data = item as? Data,
          let binding = String(data: data, encoding: .utf8),
          isCanonicalOpaqueBinding(binding) else {
      return nil
    }
    return binding
  }
}

protocol IosNotificationRecoveryHandoffStoring: AnyObject {
  func claimPrepared(
    requestIdentifier: String,
    identity: IosNotificationRecoveryIdentity
  ) -> IosNotificationRecoveryClaim
  func markCommitted(requestIdentifier: String) -> Bool
}

extension IosNotificationRecoveryStore: IosNotificationRecoveryHandoffStoring {}

enum IosNotificationRecoveryHandoffDisposition: Equatable {
  case unique
  case sameRequestDuplicate
  case duplicate
  case untracked
  case rejected
}

/// Production NSE handoff seam. The store's uniqueness decision and exact
/// request custody are durably prepared before the real Apple content handler
/// is invoked; committed is a cleanup phase, not the ownership boundary.
final class IosNotificationRecoveryHandoffOrchestrator {
  private let store: IosNotificationRecoveryHandoffStoring?

  init(store: IosNotificationRecoveryHandoffStoring?) {
    self.store = store
  }

  @discardableResult
  func handoff(
    requestIdentifier: String,
    identity: IosNotificationRecoveryIdentity?,
    content: UNNotificationContent,
    prepareContent: (IosNotificationRecoveryHandoffDisposition) -> Void,
    beforeContentHandler: (IosNotificationRecoveryHandoffDisposition) -> Void = {
      _ in
    },
    contentHandler: (UNNotificationContent) -> Void
  ) -> IosNotificationRecoveryHandoffDisposition {
    let disposition: IosNotificationRecoveryHandoffDisposition
    if let identity, let store {
      switch store.claimPrepared(
        requestIdentifier: requestIdentifier,
        identity: identity
      ) {
      case .unique:
        disposition = .unique
      case .sameRequestDuplicate:
        disposition = .sameRequestDuplicate
      case .duplicate:
        disposition = .duplicate
      case .accountMismatch, .unsupportedSchema:
        disposition = .rejected
      case .corruptState, .capacityExceeded, .storageUnavailable:
        // A corrupt/unavailable v1 store must never substitute provider copy;
        // the already-authorized trusted preview may still be handed off.
        disposition = .untracked
      }
    } else {
      disposition = .untracked
    }
    prepareContent(disposition)
    beforeContentHandler(disposition)
    contentHandler(content)
    if identity != nil,
       disposition == .unique || disposition == .sameRequestDuplicate ||
         disposition == .duplicate {
      _ = store?.markCommitted(requestIdentifier: requestIdentifier)
    }
    return disposition
  }
}

protocol IosNotificationBadgeWriting: AnyObject {
  func requestWrite()
}

/// iOS 16+ absolute badge writer. Its separate flock remains held through the
/// asynchronous UserNotifications completion, serializing Runner and NSE. It
/// re-reads desired state before releasing if a newer sequence arrived.
final class IosNotificationSerializedBadgeWriter: IosNotificationBadgeWriting {
  typealias Setter = (Int, @escaping (Error?) -> Void) -> Void

  private static let maximumAttemptsPerRevision = 3

  private let store: IosNotificationRecoveryStore
  private let setter: Setter
  private let queue: DispatchQueue

  init(
    store: IosNotificationRecoveryStore,
    setter: @escaping Setter,
    queue: DispatchQueue = DispatchQueue(
      label: "com.mknoon.notification-recovery.badge",
      qos: .utility
    )
  ) {
    self.store = store
    self.setter = setter
    self.queue = queue
  }

  func requestWrite() {
    // The queued operation owns the writer. In an NSE, Apple's content handler
    // may release the extension instance immediately after returning.
    queue.async { self.beginLockedWrite() }
  }

  private func beginLockedWrite() {
    let fd = open(
      store.badgeLockURL.path,
      O_RDWR | O_CREAT,
      S_IRUSR | S_IWUSR
    )
    guard fd >= 0 else { return }
    guard flock(fd, LOCK_EX) == 0 else {
      close(fd)
      return
    }
    writeLatest(fd: fd)
  }

  private func writeLatest(fd: Int32) {
    guard let snapshot = store.desiredBadgeSnapshot() else {
      finish(fd: fd)
      return
    }
    write(snapshot: snapshot, attempt: 1, fd: fd)
  }

  private func write(
    snapshot: IosNotificationBadgeSnapshot,
    attempt: Int,
    fd: Int32
  ) {
    setter(snapshot.count) { [self] error in
      self.queue.async {
        if let latest = self.store.desiredBadgeSnapshot(),
           latest.revision != snapshot.revision {
          self.write(snapshot: latest, attempt: 1, fd: fd)
        } else if error != nil,
                  attempt < Self.maximumAttemptsPerRevision {
          self.write(snapshot: snapshot, attempt: attempt + 1, fd: fd)
        } else {
          self.finish(fd: fd)
        }
      }
    }
  }

  private func finish(fd: Int32) {
    flock(fd, LOCK_UN)
    close(fd)
  }
}
