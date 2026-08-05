import Foundation

/// SIMS-only handoff for the APNs device token and this installation's live
/// libp2p transport identity.
///
/// The coordinator is instantiated only when the Runner target is compiled
/// with `MKNOON_SIMS_IOS_RECEIVER_BOOTSTRAP`. A short-lived, nonce-bound
/// request must also be present in the app data container. Neither value is
/// logged or returned over the Flutter channel. The response exists only as a
/// complete-protection, owner-only file for `devicectl device copy from`.
final class IosReceiverBootstrapHandoff {
  static let requestSchema = "mknoon.sims.ios-receiver-bootstrap-request.v1"
  static let responseSchema = "mknoon.sims.ios-provider-receiver-handoff.v2"
  static let senderRequestSchema = "mknoon.sims.ios-sender-projection-request.v1"
  static let senderResultSchema = "mknoon.sims.ios-sender-projection-result.v1"
  static let recoveryRequestSchema = "mknoon.sims.ios-notification-recovery-request.v1"
  static let recoveryResultSchema = "mknoon.sims.ios-notification-recovery-result.v1"
  static let relativeDirectory = "mknoon.sims.ios-receiver-bootstrap"
  static let requestFileName = "request.json"
  static let responseFileName = "response.json"
  static let senderRequestFileName = "sender-request.json"
  static let senderResultFileName = "sender-result.json"
  static let recoveryRequestFileName = "recovery-request.json"
  static let recoveryResultFileName = "recovery-result.json"
  static let apnsEnvironment = "development"

  enum Outcome: Equatable {
    case waiting
    case published
    case cleaned
    case rejected
  }

  private let enabled: Bool
  private let fileManager: FileManager
  private let now: () -> Date
  private let rootDirectory: URL
  private var apnsDeviceToken: Data?
  private var transportPeerId: String?
  private var mlKemPublicKey: String?
  private var notificationAuthorization: String?
  private var notificationAlertSetting: String?
  private var notificationBadgeSetting: String?

  init(
    enabled: Bool,
    fileManager: FileManager = .default,
    now: @escaping () -> Date = Date.init,
    rootDirectory: URL? = nil
  ) {
    self.enabled = enabled
    self.fileManager = fileManager
    self.now = now
    self.rootDirectory = rootDirectory ?? Self.defaultRootDirectory(fileManager: fileManager)
  }

  var requestURL: URL {
    rootDirectory.appendingPathComponent(Self.requestFileName, isDirectory: false)
  }

  var responseURL: URL {
    rootDirectory.appendingPathComponent(Self.responseFileName, isDirectory: false)
  }

  var senderRequestURL: URL {
    rootDirectory.appendingPathComponent(Self.senderRequestFileName, isDirectory: false)
  }

  var senderResultURL: URL {
    rootDirectory.appendingPathComponent(Self.senderResultFileName, isDirectory: false)
  }

  var recoveryRequestURL: URL {
    rootDirectory.appendingPathComponent(Self.recoveryRequestFileName, isDirectory: false)
  }

  var recoveryResultURL: URL {
    rootDirectory.appendingPathComponent(Self.recoveryResultFileName, isDirectory: false)
  }

  @discardableResult
  func prepareContainer() -> Outcome {
    guard enabled else { return .rejected }
    do {
      try createProtectedDirectory()
      return try consumePendingRequest()
    } catch {
      return .rejected
    }
  }

  @discardableResult
  func recordApnsDeviceToken(_ token: Data) -> Outcome {
    guard enabled, token.count == 32 else { return .rejected }
    apnsDeviceToken = token
    return prepareContainer()
  }

  @discardableResult
  func recordTransportIdentity(peerId: String, mlKemPublicKey: String) -> Outcome {
    guard
      enabled,
      Self.isTransportPeerId(peerId),
      Self.isMlKemPublicKey(mlKemPublicKey)
    else { return .rejected }
    transportPeerId = peerId
    self.mlKemPublicKey = mlKemPublicKey
    return prepareContainer()
  }

  @discardableResult
  func recordNotificationSettings(
    authorization: String,
    alertSetting: String,
    badgeSetting: String
  ) -> Outcome {
    guard
      enabled,
      Self.isKnownNotificationAuthorization(authorization),
      Self.isKnownNotificationPresentationSetting(alertSetting),
      Self.isKnownNotificationPresentationSetting(badgeSetting)
    else { return .rejected }
    notificationAuthorization = authorization
    notificationAlertSetting = alertSetting
    notificationBadgeSetting = badgeSetting
    return prepareContainer()
  }

  /// Returns one fresh, protected sender-fixture command to Dart. Raw sender
  /// identity is never logged or included in the eventual host receipt.
  func takeSenderProjectionRequest() -> [String: String]? {
    guard enabled else { return nil }
    do {
      try createProtectedDirectory()
      guard fileManager.fileExists(atPath: senderRequestURL.path) else {
        return nil
      }
      guard try isNonSymlinkRegularFile(senderRequestURL) else {
        try? fileManager.removeItem(at: senderRequestURL)
        return nil
      }
      try protectFile(senderRequestURL)
      guard let request = try validatedSenderProjectionRequest() else {
        try? fileManager.removeItem(at: senderRequestURL)
        return nil
      }
      if fileManager.fileExists(atPath: senderResultURL.path) {
        if try senderResultMatchesRequest(request) {
          try? fileManager.removeItem(at: senderRequestURL)
          return nil
        }
        try fileManager.removeItem(at: senderResultURL)
      }
      return request
    } catch {
      return nil
    }
  }

  /// Publishes only a digest-bound, secret-free completion record. The sender
  /// peer ID never crosses this method or enters the result file.
  func completeSenderProjectionRequest(
    captureNonce: String,
    action: String,
    apnsPayloadSha256: String,
    fixtureDigest: String,
    status: String,
    resultCode: String
  ) -> Bool {
    guard enabled else { return false }
    do {
      guard
        let request = try validatedSenderProjectionRequest(),
        request["captureNonce"] == captureNonce,
        request["action"] == action,
        request["apnsPayloadSha256"] == apnsPayloadSha256,
        Self.isSha256(fixtureDigest),
        Self.isSenderProjectionStatus(status, action: action),
        Self.isResultCode(resultCode)
      else { return false }
      let result: [String: Any] = [
        "schema": Self.senderResultSchema,
        "action": action,
        "captureNonce": captureNonce,
        "receiverDeviceId": request["receiverDeviceId"]!,
        "bundleId": "com.mknoon.app",
        "apnsPayloadSha256": apnsPayloadSha256,
        "fixtureDigest": fixtureDigest,
        "status": status,
        "resultCode": resultCode,
        "completedAt": Self.timestamp(now()),
      ]
      try publishAtomically(
        result,
        to: senderResultURL,
        temporaryPrefix: ".sender-result"
      )
      try? fileManager.removeItem(at: senderRequestURL)
      return true
    } catch {
      return false
    }
  }

  /// Returns one nonce-bound recovery proof command from the protected SIMS
  /// container. The account peer ID is consumed only in-process and never
  /// copied into the redacted result.
  func takeNotificationRecoveryRequest() -> [String: String]? {
    guard enabled else { return nil }
    do {
      try createProtectedDirectory()
      guard fileManager.fileExists(atPath: recoveryRequestURL.path) else {
        return nil
      }
      guard try isNonSymlinkRegularFile(recoveryRequestURL) else {
        try? fileManager.removeItem(at: recoveryRequestURL)
        return nil
      }
      try protectFile(recoveryRequestURL)
      guard let request = try validatedNotificationRecoveryRequest() else {
        try? fileManager.removeItem(at: recoveryRequestURL)
        return nil
      }
      if fileManager.fileExists(atPath: recoveryResultURL.path) {
        try fileManager.removeItem(at: recoveryResultURL)
      }
      return request
    } catch {
      return nil
    }
  }

  @discardableResult
  func completeNotificationRecoveryRequest(
    request: [String: String],
    status: String,
    resultCode: String,
    badgeBefore: Int,
    badgeAfter: Int,
    deliveredBefore: Int,
    deliveredWithSentinel: Int,
    deliveredAfter: Int,
    deliveredNotificationBadgeWasNil: Bool,
    sentinelSurvived: Bool,
    removedExactOwnedNotification: Bool
  ) -> Bool {
    guard
      enabled,
      status == "passed" || status == "failed",
      Self.isResultCode(resultCode),
      badgeBefore >= 0,
      badgeAfter >= 0,
      deliveredBefore >= 0,
      deliveredWithSentinel >= 0,
      deliveredAfter >= 0,
      request["schema"] == Self.recoveryRequestSchema,
      request["action"] == "prove_recovery",
      let captureNonce = request["captureNonce"],
      let receiverDeviceId = request["receiverDeviceId"],
      let payloadSha256 = request["apnsPayloadSha256"]
    else { return false }
    do {
      let result: [String: Any] = [
        "schema": Self.recoveryResultSchema,
        "action": "prove_recovery",
        "captureNonce": captureNonce,
        "receiverDeviceId": receiverDeviceId,
        "bundleId": "com.mknoon.app",
        "apnsPayloadSha256": payloadSha256,
        "status": status,
        "resultCode": resultCode,
        "badgeBefore": badgeBefore,
        "badgeAfter": badgeAfter,
        "deliveredBefore": deliveredBefore,
        "deliveredWithSentinel": deliveredWithSentinel,
        "deliveredAfter": deliveredAfter,
        "deliveredNotificationBadgeWasNil": deliveredNotificationBadgeWasNil,
        "sentinelSurvived": sentinelSurvived,
        "removedExactOwnedNotification": removedExactOwnedNotification,
        "childBuildCount": 0,
        "manualActionCount": 0,
        "completedAt": Self.timestamp(now()),
      ]
      try publishAtomically(
        result,
        to: recoveryResultURL,
        temporaryPrefix: ".recovery-result"
      )
      try? fileManager.removeItem(at: recoveryRequestURL)
      return true
    } catch {
      return false
    }
  }

  private func consumePendingRequest() throws -> Outcome {
    guard fileManager.fileExists(atPath: requestURL.path) else { return .waiting }
    guard try isNonSymlinkRegularFile(requestURL) else {
      try? fileManager.removeItem(at: requestURL)
      return .rejected
    }
    try protectFile(requestURL)
    let request = try decodeObject(at: requestURL)
    guard
      request["schema"] as? String == Self.requestSchema,
      let action = request["action"] as? String,
      let captureNonce = request["captureNonce"] as? String,
      Self.isNonce(captureNonce),
      let receiverDeviceId = request["receiverDeviceId"] as? String,
      Self.isReceiverDeviceId(receiverDeviceId),
      request["bundleId"] as? String == "com.mknoon.app",
      let expiresAt = Self.parseTimestamp(request["expiresAt"]),
      expiresAt >= now(),
      expiresAt.timeIntervalSince(now()) <= 300
    else {
      try? fileManager.removeItem(at: requestURL)
      return .rejected
    }

    switch action {
    case "cleanup":
      if fileManager.fileExists(atPath: responseURL.path) {
        guard
          let responseNonce = try? decodeObject(at: responseURL)["captureNonce"] as? String,
          responseNonce == captureNonce
        else {
          try? fileManager.removeItem(at: requestURL)
          return .rejected
        }
        try fileManager.removeItem(at: responseURL)
      }
      try? fileManager.removeItem(at: senderRequestURL)
      try? fileManager.removeItem(at: senderResultURL)
      try? fileManager.removeItem(at: recoveryRequestURL)
      try? fileManager.removeItem(at: recoveryResultURL)
      try? fileManager.removeItem(at: requestURL)
      return .cleaned
    case "capture":
      if fileManager.fileExists(atPath: responseURL.path) {
        let existingNonce = try? decodeObject(at: responseURL)["captureNonce"] as? String
        if existingNonce == captureNonce {
          try? fileManager.removeItem(at: requestURL)
          return .published
        }
        try fileManager.removeItem(at: responseURL)
      }
      guard
        let apnsDeviceToken,
        let transportPeerId,
        let mlKemPublicKey,
        let notificationAuthorization,
        let notificationAlertSetting,
        let notificationBadgeSetting
      else {
        return .waiting
      }
      guard
        Self.isAcceptedNotificationAuthorization(notificationAuthorization),
        notificationAlertSetting == "enabled",
        notificationBadgeSetting == "enabled"
      else {
        try? fileManager.removeItem(at: requestURL)
        return .rejected
      }
      let response: [String: Any] = [
        "schema": Self.responseSchema,
        "captureNonce": captureNonce,
        "receiverDeviceId": receiverDeviceId,
        "peerDeviceId": transportPeerId,
        "bundleId": "com.mknoon.app",
        "apnsEnvironment": Self.apnsEnvironment,
        "apnsDeviceToken": apnsDeviceToken.map { String(format: "%02x", $0) }.joined(),
        "mlKemPublicKey": mlKemPublicKey,
        "notificationAuthorization": notificationAuthorization,
        "notificationAlertSetting": notificationAlertSetting,
        "notificationBadgeSetting": notificationBadgeSetting,
        "capturedAt": Self.timestamp(now()),
      ]
      try publishAtomically(
        response,
        to: responseURL,
        temporaryPrefix: ".response"
      )
      try? fileManager.removeItem(at: requestURL)
      return .published
    default:
      try? fileManager.removeItem(at: requestURL)
      return .rejected
    }
  }

  private func validatedSenderProjectionRequest() throws -> [String: String]? {
    guard fileManager.fileExists(atPath: senderRequestURL.path) else {
      return nil
    }
    guard try isNonSymlinkRegularFile(senderRequestURL) else { return nil }
    try protectFile(senderRequestURL)
    let decoded = try decodeObject(at: senderRequestURL)
    let expectedKeys = Set([
      "schema", "action", "captureNonce", "receiverDeviceId", "bundleId",
      "senderPeerId", "senderUsername", "apnsPayloadSha256", "createdAt",
      "expiresAt",
    ])
    guard
      Set(decoded.keys) == expectedKeys,
      decoded["schema"] as? String == Self.senderRequestSchema,
      let action = decoded["action"] as? String,
      action == "seed_sender" || action == "cleanup_sender",
      let captureNonce = decoded["captureNonce"] as? String,
      Self.isNonce(captureNonce),
      let receiverDeviceId = decoded["receiverDeviceId"] as? String,
      Self.isReceiverDeviceId(receiverDeviceId),
      decoded["bundleId"] as? String == "com.mknoon.app",
      let senderPeerId = decoded["senderPeerId"] as? String,
      Self.isTransportPeerId(senderPeerId),
      let senderUsername = decoded["senderUsername"] as? String,
      Self.isSenderUsername(senderUsername),
      let apnsPayloadSha256 = decoded["apnsPayloadSha256"] as? String,
      Self.isSha256(apnsPayloadSha256),
      let createdAtText = decoded["createdAt"] as? String,
      let createdAt = Self.parseTimestamp(createdAtText),
      let expiresAtText = decoded["expiresAt"] as? String,
      let expiresAt = Self.parseTimestamp(expiresAtText)
    else { return nil }
    let current = now()
    guard
      createdAt <= current.addingTimeInterval(15),
      current.timeIntervalSince(createdAt) <= 300,
      expiresAt >= current,
      expiresAt.timeIntervalSince(current) <= 300,
      expiresAt >= createdAt
    else { return nil }
    return [
      "schema": Self.senderRequestSchema,
      "action": action,
      "captureNonce": captureNonce,
      "receiverDeviceId": receiverDeviceId,
      "bundleId": "com.mknoon.app",
      "senderPeerId": senderPeerId,
      "senderUsername": senderUsername,
      "apnsPayloadSha256": apnsPayloadSha256,
      "createdAt": createdAtText,
      "expiresAt": expiresAtText,
    ]
  }

  private func validatedNotificationRecoveryRequest() throws -> [String: String]? {
    guard fileManager.fileExists(atPath: recoveryRequestURL.path) else {
      return nil
    }
    guard try isNonSymlinkRegularFile(recoveryRequestURL) else { return nil }
    try protectFile(recoveryRequestURL)
    let decoded = try decodeObject(at: recoveryRequestURL)
    let expectedKeys = Set([
      "schema", "action", "captureNonce", "receiverDeviceId", "bundleId",
      "accountPeerId", "sentinelIdentifier", "apnsPayloadSha256", "createdAt",
      "expiresAt",
    ])
    guard
      Set(decoded.keys) == expectedKeys,
      decoded["schema"] as? String == Self.recoveryRequestSchema,
      decoded["action"] as? String == "prove_recovery",
      let captureNonce = decoded["captureNonce"] as? String,
      Self.isNonce(captureNonce),
      let receiverDeviceId = decoded["receiverDeviceId"] as? String,
      Self.isReceiverDeviceId(receiverDeviceId),
      decoded["bundleId"] as? String == "com.mknoon.app",
      let accountPeerId = decoded["accountPeerId"] as? String,
      Self.isTransportPeerId(accountPeerId),
      let sentinelIdentifier = decoded["sentinelIdentifier"] as? String,
      Self.isRecoverySentinelIdentifier(sentinelIdentifier),
      let apnsPayloadSha256 = decoded["apnsPayloadSha256"] as? String,
      Self.isSha256(apnsPayloadSha256),
      let createdAtText = decoded["createdAt"] as? String,
      let createdAt = Self.parseTimestamp(createdAtText),
      let expiresAtText = decoded["expiresAt"] as? String,
      let expiresAt = Self.parseTimestamp(expiresAtText)
    else { return nil }
    let current = now()
    guard
      createdAt <= current.addingTimeInterval(15),
      current.timeIntervalSince(createdAt) <= 300,
      expiresAt >= current,
      expiresAt.timeIntervalSince(current) <= 300,
      expiresAt >= createdAt
    else { return nil }
    return [
      "schema": Self.recoveryRequestSchema,
      "action": "prove_recovery",
      "captureNonce": captureNonce,
      "receiverDeviceId": receiverDeviceId,
      "bundleId": "com.mknoon.app",
      "accountPeerId": accountPeerId,
      "sentinelIdentifier": sentinelIdentifier,
      "apnsPayloadSha256": apnsPayloadSha256,
      "createdAt": createdAtText,
      "expiresAt": expiresAtText,
    ]
  }

  private func senderResultMatchesRequest(_ request: [String: String]) throws -> Bool {
    guard try isNonSymlinkRegularFile(senderResultURL) else { return false }
    try protectFile(senderResultURL)
    let result = try decodeObject(at: senderResultURL)
    let expectedKeys = Set([
      "schema", "action", "captureNonce", "receiverDeviceId", "bundleId",
      "apnsPayloadSha256", "fixtureDigest", "status", "resultCode",
      "completedAt",
    ])
    guard
      Set(result.keys) == expectedKeys,
      let action = result["action"] as? String,
      let fixtureDigest = result["fixtureDigest"] as? String,
      Self.isSha256(fixtureDigest),
      let status = result["status"] as? String,
      Self.isSenderProjectionStatus(status, action: action),
      let resultCode = result["resultCode"] as? String,
      Self.isResultCode(resultCode),
      let completedAt = Self.parseTimestamp(result["completedAt"]),
      completedAt <= now().addingTimeInterval(15),
      now().timeIntervalSince(completedAt) <= 300
    else { return false }
    return result["schema"] as? String == Self.senderResultSchema
      && result["action"] as? String == request["action"]
      && result["captureNonce"] as? String == request["captureNonce"]
      && result["receiverDeviceId"] as? String == request["receiverDeviceId"]
      && result["bundleId"] as? String == "com.mknoon.app"
      && result["apnsPayloadSha256"] as? String == request["apnsPayloadSha256"]
  }

  private func createProtectedDirectory() throws {
    try fileManager.createDirectory(
      at: rootDirectory,
      withIntermediateDirectories: true,
      attributes: [
        .posixPermissions: 0o700,
        .protectionKey: FileProtectionType.complete,
      ]
    )
    try fileManager.setAttributes(
      [
        .posixPermissions: 0o700,
        .protectionKey: FileProtectionType.complete,
      ],
      ofItemAtPath: rootDirectory.path
    )
    var resourceValues = URLResourceValues()
    resourceValues.isExcludedFromBackup = true
    var mutableRoot = rootDirectory
    try mutableRoot.setResourceValues(resourceValues)
  }

  private func protectFile(_ url: URL) throws {
    try fileManager.setAttributes(
      [
        .posixPermissions: 0o600,
        .protectionKey: FileProtectionType.complete,
      ],
      ofItemAtPath: url.path
    )
  }

  private func publishAtomically(
    _ object: [String: Any],
    to destination: URL,
    temporaryPrefix: String
  ) throws {
    let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    let temporary = rootDirectory.appendingPathComponent(
      "\(temporaryPrefix).\(UUID().uuidString).tmp",
      isDirectory: false
    )
    guard fileManager.createFile(
      atPath: temporary.path,
      contents: nil,
      attributes: [
        .posixPermissions: 0o600,
        .protectionKey: FileProtectionType.complete,
      ]
    ) else {
      throw CocoaError(.fileWriteUnknown)
    }
    do {
      let handle = try FileHandle(forWritingTo: temporary)
      if #available(iOS 13.4, *) {
        try handle.write(contentsOf: data)
        try handle.synchronize()
        try handle.close()
      } else {
        handle.write(data)
        handle.synchronizeFile()
        handle.closeFile()
      }
      try protectFile(temporary)
      if fileManager.fileExists(atPath: destination.path) {
        try fileManager.removeItem(at: destination)
      }
      try fileManager.moveItem(at: temporary, to: destination)
      try protectFile(destination)
    } catch {
      try? fileManager.removeItem(at: temporary)
      throw error
    }
  }

  private func decodeObject(at url: URL) throws -> [String: Any] {
    guard fileManager.fileExists(atPath: url.path) else {
      throw CocoaError(.fileNoSuchFile)
    }
    let data = try Data(contentsOf: url, options: [.mappedIfSafe])
    guard
      data.count <= 4096,
      let value = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
      throw CocoaError(.fileReadCorruptFile)
    }
    return value
  }

  private func isNonSymlinkRegularFile(_ url: URL) throws -> Bool {
    let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
    return values.isRegularFile == true && values.isSymbolicLink != true
  }

  static func isTransportPeerId(_ value: String) -> Bool {
    let base58 = "[1-9A-HJ-NP-Za-km-z]"
    let pattern = "^(?:12D3KooW\(base58){44}|Qm\(base58){44})$"
    return value.range(of: pattern, options: .regularExpression) != nil
  }

  static func isNonce(_ value: String) -> Bool {
    value.range(
      of: "^[A-Za-z0-9._:-]{12,160}$",
      options: .regularExpression
    ) != nil
  }

  static func isReceiverDeviceId(_ value: String) -> Bool {
    value.range(
      of: "^[A-Za-z0-9._:-]{4,160}$",
      options: .regularExpression
    ) != nil
  }

  static func isMlKemPublicKey(_ value: String) -> Bool {
    guard value.range(
      of: "^[A-Za-z0-9_+/=-]{100,4096}$",
      options: .regularExpression
    ) != nil else { return false }
    var normalized = value
      .replacingOccurrences(of: "-", with: "+")
      .replacingOccurrences(of: "_", with: "/")
    let remainder = normalized.count % 4
    if remainder != 0 {
      normalized += String(repeating: "=", count: 4 - remainder)
    }
    return Data(base64Encoded: normalized)?.count == 1184
  }

  static func isSha256(_ value: String) -> Bool {
    value.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil
  }

  static func isSenderUsername(_ value: String) -> Bool {
    guard value == value.trimmingCharacters(in: .whitespacesAndNewlines),
          !value.isEmpty,
          value.count <= 30 else { return false }
    return value.unicodeScalars.allSatisfy {
      !CharacterSet.controlCharacters.contains($0)
    }
  }

  static func isResultCode(_ value: String) -> Bool {
    value.range(of: "^[a-z_]{2,64}$", options: .regularExpression) != nil
  }

  static func isRecoverySentinelIdentifier(_ value: String) -> Bool {
    value.range(
      of: "^mknoon-sims-recovery-[0-9a-f]{24}$",
      options: .regularExpression
    ) != nil
  }

  static func isSenderProjectionStatus(_ value: String, action: String) -> Bool {
    value == "rejected"
      || (action == "seed_sender" && value == "seeded")
      || (action == "cleanup_sender" && value == "cleaned")
  }

  static func isAcceptedNotificationAuthorization(_ value: String) -> Bool {
    value == "authorized" || value == "provisional" || value == "ephemeral"
  }

  static func isKnownNotificationAuthorization(_ value: String) -> Bool {
    isAcceptedNotificationAuthorization(value)
      || value == "denied"
      || value == "not_determined"
  }

  static func isKnownNotificationPresentationSetting(_ value: String) -> Bool {
    value == "enabled" || value == "disabled" || value == "not_supported"
  }

  private static func defaultRootDirectory(fileManager: FileManager) -> URL {
    let applicationSupport = fileManager.urls(
      for: .applicationSupportDirectory,
      in: .userDomainMask
    ).first!
    return applicationSupport.appendingPathComponent(relativeDirectory, isDirectory: true)
  }

  private static func timestamp(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: date)
  }

  private static func parseTimestamp(_ value: Any?) -> Date? {
    guard let value = value as? String else { return nil }
    let fractional = ISO8601DateFormatter()
    fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let parsed = fractional.date(from: value) { return parsed }
    return ISO8601DateFormatter().date(from: value)
  }
}
