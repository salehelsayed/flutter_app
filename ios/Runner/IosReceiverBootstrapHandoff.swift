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
  static let recoveryRequestSchema = "mknoon.sims.ios-notification-recovery-request.v2"
  static let recoveryResultSchema = "mknoon.sims.ios-notification-recovery-result.v2"
  static let groupObservationRequestSchema =
    "mknoon.sims.ios-group-notification-observation-request.v2"
  static let groupObservationResultSchema =
    "mknoon.sims.ios-group-notification-observation-result.v3"
  static let groupObservationDiagnosticSchema =
    "mknoon.sims.ios-group-notification-diagnostics.v2"
  static let relativeDirectory = "mknoon.sims.ios-receiver-bootstrap"
  static let requestFileName = "request.json"
  static let responseFileName = "response.json"
  static let senderRequestFileName = "sender-request.json"
  static let senderResultFileName = "sender-result.json"
  static let recoveryRequestFileName = "recovery-request.json"
  static let recoveryResultFileName = "recovery-result.json"
  static let groupObservationRequestFileName = "group-observation-request.json"
  static let groupObservationResultFileName = "group-observation-result.json"
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

  var groupObservationRequestURL: URL {
    rootDirectory.appendingPathComponent(
      Self.groupObservationRequestFileName,
      isDirectory: false
    )
  }

  var groupObservationResultURL: URL {
    rootDirectory.appendingPathComponent(
      Self.groupObservationResultFileName,
      isDirectory: false
    )
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
    removedExactOwnedNotification: Bool,
    inventory: IosDirectNotificationInventory,
    stableSampleCount: Int
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
      let action = request["action"],
      action == "prove_recovery" || action == "observe_direct",
      let proofStage = request["proofStage"],
      Self.isRecoveryProofStage(proofStage),
      stableSampleCount >= 0,
      stableSampleCount <= IosDirectNotificationInventory.stableSampleTarget,
      inventory.matchingRemoteCount >= 0,
      inventory.matchingLocalCount >= 0,
      inventory.matchingUsefulProviderCount >= 0,
      inventory.matchingSanitizedProviderCount >= 0,
      inventory.matchingFlutterLocalCount >= 0,
      inventory.matchingUnknownCount >= 0,
      inventory.matchingTotalCount <= 8,
      inventory.requestIdentifierSha256.count == inventory.matchingTotalCount,
      inventory.requestIdentifierSha256.allSatisfy(Self.isSha256),
      let captureNonce = request["captureNonce"],
      let receiverDeviceId = request["receiverDeviceId"],
      let payloadSha256 = request["apnsPayloadSha256"]
    else { return false }
    do {
      let result: [String: Any] = [
        "schema": Self.recoveryResultSchema,
        "action": action,
        "proofStage": proofStage,
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
        "matchingRemoteCount": inventory.matchingRemoteCount,
        "matchingLocalCount": inventory.matchingLocalCount,
        "matchingUsefulProviderCount": inventory.matchingUsefulProviderCount,
        "matchingSanitizedProviderCount": inventory.matchingSanitizedProviderCount,
        "matchingFlutterLocalCount": inventory.matchingFlutterLocalCount,
        "matchingUnknownCount": inventory.matchingUnknownCount,
        "matchingTotalCount": inventory.matchingTotalCount,
        "stableSampleCount": stableSampleCount,
        "stableSampleIntervalMilliseconds":
          IosDirectNotificationInventory.stableSampleIntervalMilliseconds,
        "settleDelayMilliseconds":
          IosDirectNotificationInventory.settleDelayMilliseconds,
        "observationDeadlineMilliseconds":
          IosDirectNotificationInventory.observationDeadlineMilliseconds,
        "requestIdentifierSha256": inventory.requestIdentifierSha256,
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

  /// Returns one hash-only group observation command from its own protected
  /// files so Plan 396's direct request/result bytes remain unchanged.
  func takeGroupNotificationObservationRequest() -> [String: String]? {
    guard enabled else { return nil }
    do {
      try createProtectedDirectory()
      guard fileManager.fileExists(atPath: groupObservationRequestURL.path) else {
        return nil
      }
      guard try isNonSymlinkRegularFile(groupObservationRequestURL) else {
        try? fileManager.removeItem(at: groupObservationRequestURL)
        return nil
      }
      try protectFile(groupObservationRequestURL)
      guard let request = try validatedGroupNotificationObservationRequest() else {
        try? fileManager.removeItem(at: groupObservationRequestURL)
        return nil
      }
      if fileManager.fileExists(atPath: groupObservationResultURL.path) {
        try fileManager.removeItem(at: groupObservationResultURL)
      }
      return request
    } catch {
      return nil
    }
  }

  @discardableResult
  func completeGroupNotificationObservationRequest(
    request: [String: String],
    status: String,
    resultCode: String,
    inventory: IosGroupNotificationInventory,
    stableSampleCount: Int,
    sampledThroughDeadline: Bool,
    badSourceSeen: Bool,
    duplicateSeen: Bool,
    diagnosticRecords: [IosGroupNotificationDiagnosticRecord] = [],
    diagnosticOverflow: Bool = false,
    diagnosticConflict: Bool = false,
    diagnosticComplete: Bool = false
  ) -> Bool {
    let sortedDiagnosticRecords = diagnosticRecords.sorted {
      $0.requestIdentifierSha256 < $1.requestIdentifierSha256
    }
    let diagnosticHashes = sortedDiagnosticRecords.map(
      \.requestIdentifierSha256
    )
    let inventoryHashes = inventory.requestIdentifierSha256
    guard let expectedCollapseHash =
      request["expectedCollapseIdentifierSha256"] else {
      return false
    }
    let collapseMatchesAreConsistent = sortedDiagnosticRecords.allSatisfy {
      $0.expectedCollapseIdentifierMatch
        == ($0.requestIdentifierSha256 == expectedCollapseHash)
    }
    let inventoryHashesAreCovered = Set(inventoryHashes)
      .isSubset(of: Set(diagnosticHashes))
    let inventoryDiagnosticRecords = inventory.diagnosticRecords
    let inventoryDiagnosticHashes = inventoryDiagnosticRecords
      .map(\.requestIdentifierSha256)
      .sorted()
    let inventoryRecordsAreConsistent =
      inventoryDiagnosticRecords.count == inventory.matchingTotalCount
      && inventoryDiagnosticRecords.allSatisfy(\.isClosedAndConsistent)
      && inventoryDiagnosticHashes == inventoryHashes
      && Set(inventoryDiagnosticHashes).count
        == inventoryDiagnosticHashes.count
      && inventory.matchingRemoteCount
        == inventoryDiagnosticRecords.filter { $0.triggerOrigin == .remote }.count
      && inventory.matchingLocalCount
        == inventoryDiagnosticRecords.filter { $0.triggerOrigin == .local }.count
      && inventory.matchingUsefulProviderCount
        == inventoryDiagnosticRecords.filter {
          $0.sourceClass == .usefulProviderRich
        }.count
      && inventory.matchingSanitizedProviderCount
        == inventoryDiagnosticRecords.filter {
          $0.sourceClass == .sanitizedProviderRich
        }.count
      && inventory.matchingFlutterLocalCount
        == inventoryDiagnosticRecords.filter {
          $0.sourceClass == .flutterLocal
        }.count
      && inventory.matchingUnknownCount
        == inventoryDiagnosticRecords.filter { $0.sourceClass == .unknown }.count
    let computedDiagnosticComplete = sampledThroughDeadline
      && !diagnosticOverflow
      && !diagnosticConflict
      && !sortedDiagnosticRecords.isEmpty
      && sortedDiagnosticRecords.allSatisfy(\.isClosedAndConsistent)
    let canonicalPassRecord = sortedDiagnosticRecords.count == 1
      && sortedDiagnosticRecords[0].requestIdentifierSha256
        == expectedCollapseHash
      && sortedDiagnosticRecords[0].expectedCollapseIdentifierMatch
      && sortedDiagnosticRecords[0].triggerOrigin == .remote
      && sortedDiagnosticRecords[0].sourceClass == .usefulProviderRich
      && sortedDiagnosticRecords[0].reason == .exactUseful
    let exactUsefulSource = sampledThroughDeadline
      && diagnosticComplete
      && stableSampleCount == IosGroupNotificationInventory.stableSampleTarget
      && !badSourceSeen
      && !duplicateSeen
      && !diagnosticOverflow
      && !diagnosticConflict
      && inventory.matchingRemoteCount == 1
      && inventory.matchingLocalCount == 0
      && inventory.matchingUsefulProviderCount == 1
      && inventory.matchingSanitizedProviderCount == 0
      && inventory.matchingFlutterLocalCount == 0
      && inventory.matchingUnknownCount == 0
      && inventory.matchingTotalCount == 1
      && inventoryHashes == [expectedCollapseHash]
      && canonicalPassRecord
    let expectedResultCode: String
    if exactUsefulSource {
      expectedResultCode = "ok"
    } else if !sampledThroughDeadline
                || stableSampleCount != IosGroupNotificationInventory.stableSampleTarget {
      expectedResultCode = "source_inventory_unstable"
    } else if badSourceSeen {
      expectedResultCode = "bad_source_seen"
    } else if duplicateSeen {
      expectedResultCode = "duplicate_seen"
    } else {
      expectedResultCode = "source_inventory_mismatch"
    }
    let statusAndResultAreConsistent =
      status == (exactUsefulSource ? "passed" : "failed")
        && resultCode == expectedResultCode
    guard
      enabled,
      request["schema"] == Self.groupObservationRequestSchema,
      request["action"] == "observe_group",
      status == "passed" || status == "failed",
      Self.isResultCode(resultCode),
      stableSampleCount >= 0,
      stableSampleCount <= IosGroupNotificationInventory.stableSampleTarget,
      inventory.matchingRemoteCount >= 0,
      inventory.matchingLocalCount >= 0,
      inventory.matchingUsefulProviderCount >= 0,
      inventory.matchingSanitizedProviderCount >= 0,
      inventory.matchingFlutterLocalCount >= 0,
      inventory.matchingUnknownCount >= 0,
      inventory.matchingRemoteCount + inventory.matchingLocalCount
        == inventory.matchingTotalCount,
      inventory.matchingTotalCount <= 8,
      inventoryHashes.count == inventory.matchingTotalCount,
      inventoryHashes.allSatisfy(Self.isSha256),
      inventoryHashes == inventoryHashes.sorted(),
      Set(inventoryHashes).count == inventoryHashes.count,
      sortedDiagnosticRecords.count <= 8,
      diagnosticHashes == diagnosticHashes.sorted(),
      Set(diagnosticHashes).count == diagnosticHashes.count,
      sortedDiagnosticRecords.allSatisfy(\.isClosedAndConsistent),
      diagnosticComplete == computedDiagnosticComplete,
      inventoryRecordsAreConsistent,
      statusAndResultAreConsistent,
      let captureNonce = request["captureNonce"],
      let receiverDeviceId = request["receiverDeviceId"],
      let phase = request["phase"],
      phase == "message" || phase == "reaction",
      let groupHash = request["expectedGroupIdSha256"],
      let eventHash = request["expectedEventIdSha256"],
      let targetHash = request["expectedTargetMessageIdSha256"],
      Self.isSha256(expectedCollapseHash),
      collapseMatchesAreConsistent,
      inventoryHashesAreCovered
    else { return false }
    do {
      let result: [String: Any] = [
        "schema": Self.groupObservationResultSchema,
        "action": "observe_group",
        "phase": phase,
        "captureNonce": captureNonce,
        "receiverDeviceId": receiverDeviceId,
        "bundleId": "com.mknoon.app",
        "expectedGroupIdSha256": groupHash,
        "expectedEventIdSha256": eventHash,
        "expectedTargetMessageIdSha256": targetHash,
        "expectedCollapseIdentifierSha256": expectedCollapseHash,
        "status": status,
        "resultCode": resultCode,
        "matchingRemoteCount": inventory.matchingRemoteCount,
        "matchingLocalCount": inventory.matchingLocalCount,
        "matchingUsefulProviderCount": inventory.matchingUsefulProviderCount,
        "matchingSanitizedProviderCount": inventory.matchingSanitizedProviderCount,
        "matchingFlutterLocalCount": inventory.matchingFlutterLocalCount,
        "matchingUnknownCount": inventory.matchingUnknownCount,
        "matchingTotalCount": inventory.matchingTotalCount,
        "stableSampleCount": stableSampleCount,
        "stableSampleIntervalMilliseconds":
          IosGroupNotificationInventory.stableSampleIntervalMilliseconds,
        "observationDeadlineMilliseconds":
          IosGroupNotificationInventory.observationDeadlineMilliseconds,
        "sampledThroughDeadline": sampledThroughDeadline,
        "badSourceSeen": badSourceSeen,
        "duplicateSeen": duplicateSeen,
        "requestIdentifierSha256": inventory.requestIdentifierSha256,
        "diagnosticSchema": Self.groupObservationDiagnosticSchema,
        "diagnosticRecords": sortedDiagnosticRecords.map(\.jsonObject),
        "diagnosticRecordCount": sortedDiagnosticRecords.count,
        "diagnosticOverflow": diagnosticOverflow,
        "diagnosticConflict": diagnosticConflict,
        "diagnosticComplete": diagnosticComplete,
        "childBuildCount": 0,
        "manualActionCount": 0,
        "completedAt": Self.timestamp(now()),
      ]
      let encoded = try JSONSerialization.data(
        withJSONObject: result,
        options: [.sortedKeys]
      )
      guard encoded.count <= 8_192 else { return false }
      try publishAtomically(
        result,
        to: groupObservationResultURL,
        temporaryPrefix: ".group-observation-result"
      )
      try? fileManager.removeItem(at: groupObservationRequestURL)
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
      try? fileManager.removeItem(at: groupObservationRequestURL)
      try? fileManager.removeItem(at: groupObservationResultURL)
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

  private func validatedGroupNotificationObservationRequest() throws
    -> [String: String]?
  {
    guard fileManager.fileExists(atPath: groupObservationRequestURL.path) else {
      return nil
    }
    guard try isNonSymlinkRegularFile(groupObservationRequestURL) else {
      return nil
    }
    try protectFile(groupObservationRequestURL)
    let decoded = try decodeObject(at: groupObservationRequestURL)
    let expectedKeys = Set([
      "schema", "action", "phase", "captureNonce", "receiverDeviceId",
      "bundleId", "expectedGroupIdSha256", "expectedEventIdSha256",
      "expectedTargetMessageIdSha256", "expectedCollapseIdentifierSha256",
      "createdAt", "expiresAt",
    ])
    guard
      Set(decoded.keys) == expectedKeys,
      decoded["schema"] as? String == Self.groupObservationRequestSchema,
      decoded["action"] as? String == "observe_group",
      let phase = decoded["phase"] as? String,
      phase == "message" || phase == "reaction",
      let captureNonce = decoded["captureNonce"] as? String,
      Self.isNonce(captureNonce),
      let receiverDeviceId = decoded["receiverDeviceId"] as? String,
      Self.isReceiverDeviceId(receiverDeviceId),
      decoded["bundleId"] as? String == "com.mknoon.app",
      let groupHash = decoded["expectedGroupIdSha256"] as? String,
      Self.isSha256(groupHash),
      let eventHash = decoded["expectedEventIdSha256"] as? String,
      Self.isSha256(eventHash),
      let targetHash = decoded["expectedTargetMessageIdSha256"] as? String,
      Self.isSha256(targetHash),
      let expectedCollapseHash =
        decoded["expectedCollapseIdentifierSha256"] as? String,
      Self.isSha256(expectedCollapseHash),
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
      "schema": Self.groupObservationRequestSchema,
      "action": "observe_group",
      "phase": phase,
      "captureNonce": captureNonce,
      "receiverDeviceId": receiverDeviceId,
      "bundleId": "com.mknoon.app",
      "expectedGroupIdSha256": groupHash,
      "expectedEventIdSha256": eventHash,
      "expectedTargetMessageIdSha256": targetHash,
      "expectedCollapseIdentifierSha256": expectedCollapseHash,
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
      "accountPeerId", "expectedSenderPeerId", "expectedMessageId",
      "sentinelIdentifier", "proofStage", "apnsPayloadSha256", "createdAt", "expiresAt",
    ])
    guard
      Set(decoded.keys) == expectedKeys,
      decoded["schema"] as? String == Self.recoveryRequestSchema,
      let action = decoded["action"] as? String,
      action == "prove_recovery" || action == "observe_direct",
      let captureNonce = decoded["captureNonce"] as? String,
      Self.isNonce(captureNonce),
      let receiverDeviceId = decoded["receiverDeviceId"] as? String,
      Self.isReceiverDeviceId(receiverDeviceId),
      decoded["bundleId"] as? String == "com.mknoon.app",
      let accountPeerId = decoded["accountPeerId"] as? String,
      Self.isTransportPeerId(accountPeerId),
      let expectedSenderPeerId = decoded["expectedSenderPeerId"] as? String,
      Self.isTransportPeerId(expectedSenderPeerId),
      let expectedMessageId = decoded["expectedMessageId"] as? String,
      Self.isBoundedRecoveryIdentifier(expectedMessageId),
      let sentinelIdentifier = decoded["sentinelIdentifier"] as? String,
      Self.isRecoverySentinelIdentifier(sentinelIdentifier),
      let proofStage = decoded["proofStage"] as? String,
      Self.isRecoveryProofStage(proofStage),
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
      "action": action,
      "captureNonce": captureNonce,
      "receiverDeviceId": receiverDeviceId,
      "bundleId": "com.mknoon.app",
      "accountPeerId": accountPeerId,
      "expectedSenderPeerId": expectedSenderPeerId,
      "expectedMessageId": expectedMessageId,
      "sentinelIdentifier": sentinelIdentifier,
      "proofStage": proofStage,
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

  static func isRecoveryProofStage(_ value: String) -> Bool {
    value == "single_submission" || value == "retry_first" || value == "retry_second"
  }

  static func isBoundedRecoveryIdentifier(_ value: String) -> Bool {
    guard !value.isEmpty,
          value == value.trimmingCharacters(in: .whitespacesAndNewlines),
          value.lengthOfBytes(using: .utf8) <= 512 else { return false }
    return !value.unicodeScalars.contains {
      $0.value < 0x20 || ($0.value >= 0x7f && $0.value <= 0x9f)
    }
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
