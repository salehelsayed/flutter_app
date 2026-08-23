import Foundation
import XCTest

@testable import Runner

final class IosReceiverBootstrapHandoffTests: XCTestCase {
  private let now = Date(timeIntervalSince1970: 1_900_000_000)
  private let receiver = "00008110-001A123E0E91801E"
  private let nonce = "nonce-bootstrap-native-1"
  private let peer = "12D3KooW" + String(repeating: "1", count: 44)
  private let mlKem = Data(repeating: 0x41, count: 1184).base64EncodedString()

  func testCaptureWaitsForBothValuesThenPublishesProtectedNonceBoundFile() throws {
    let root = try temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
    let handoff = IosReceiverBootstrapHandoff(
      enabled: true,
      now: { self.now },
      rootDirectory: root
    )
    XCTAssertEqual(handoff.prepareContainer(), .waiting)
    try writeRequest(handoff.requestURL, action: "capture")

    XCTAssertEqual(
      handoff.recordTransportIdentity(peerId: peer, mlKemPublicKey: mlKem),
      .waiting
    )
    XCTAssertEqual(
      handoff.recordApnsDeviceToken(Data(repeating: 0xab, count: 32)),
      .waiting
    )
    XCTAssertEqual(
      handoff.recordNotificationSettings(
        authorization: "authorized",
        alertSetting: "enabled",
        badgeSetting: "enabled"
      ),
      .published
    )
    XCTAssertFalse(FileManager.default.fileExists(atPath: handoff.requestURL.path))

    let response = try json(handoff.responseURL)
    XCTAssertEqual(
      Set(response.keys),
      Set([
        "schema", "captureNonce", "receiverDeviceId", "peerDeviceId",
        "bundleId", "apnsEnvironment", "apnsDeviceToken", "mlKemPublicKey",
        "notificationAuthorization", "notificationAlertSetting",
        "notificationBadgeSetting", "capturedAt",
      ])
    )
    XCTAssertEqual(
      response["schema"] as? String,
      "mknoon.sims.ios-provider-receiver-handoff.v2"
    )
    XCTAssertEqual(response["captureNonce"] as? String, nonce)
    XCTAssertEqual(response["receiverDeviceId"] as? String, receiver)
    XCTAssertEqual(response["peerDeviceId"] as? String, peer)
    XCTAssertEqual(response["apnsEnvironment"] as? String, "development")
    XCTAssertEqual(response["apnsDeviceToken"] as? String, String(repeating: "ab", count: 32))
    XCTAssertEqual(response["mlKemPublicKey"] as? String, mlKem)
    XCTAssertEqual(response["notificationAuthorization"] as? String, "authorized")
    XCTAssertEqual(response["notificationAlertSetting"] as? String, "enabled")
    XCTAssertEqual(response["notificationBadgeSetting"] as? String, "enabled")

    let attributes = try FileManager.default.attributesOfItem(atPath: handoff.responseURL.path)
    XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    assertCompleteFileProtection(attributes)
  }

  func testExpiredOrMismatchedCleanupFailsClosed() throws {
    let root = try temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
    let handoff = IosReceiverBootstrapHandoff(
      enabled: true,
      now: { self.now },
      rootDirectory: root
    )
    XCTAssertEqual(handoff.prepareContainer(), .waiting)
    try writeRequest(
      handoff.requestURL,
      action: "capture",
      expiresAt: now.addingTimeInterval(-1)
    )
    XCTAssertEqual(handoff.prepareContainer(), .rejected)
    XCTAssertFalse(FileManager.default.fileExists(atPath: handoff.responseURL.path))

    try writeRequest(handoff.requestURL, action: "capture")
    _ = handoff.recordTransportIdentity(peerId: peer, mlKemPublicKey: mlKem)
    _ = handoff.recordNotificationSettings(
      authorization: "provisional",
      alertSetting: "enabled",
      badgeSetting: "enabled"
    )
    XCTAssertEqual(handoff.recordApnsDeviceToken(Data(repeating: 0xcd, count: 32)), .published)
    try writeRequest(
      handoff.requestURL,
      action: "cleanup",
      nonce: "nonce-bootstrap-native-other"
    )
    XCTAssertEqual(handoff.prepareContainer(), .rejected)
    XCTAssertTrue(FileManager.default.fileExists(atPath: handoff.responseURL.path))

    try writeRequest(handoff.requestURL, action: "cleanup")
    XCTAssertEqual(handoff.prepareContainer(), .cleaned)
    XCTAssertFalse(FileManager.default.fileExists(atPath: handoff.responseURL.path))
  }

  func testCaptureRejectsDeniedOrPresentationDisabledNotificationSettings() throws {
    let root = try temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
    let handoff = IosReceiverBootstrapHandoff(
      enabled: true,
      now: { self.now },
      rootDirectory: root
    )
    XCTAssertEqual(handoff.prepareContainer(), .waiting)
    try writeRequest(handoff.requestURL, action: "capture")
    XCTAssertEqual(
      handoff.recordTransportIdentity(peerId: peer, mlKemPublicKey: mlKem),
      .waiting
    )
    XCTAssertEqual(
      handoff.recordApnsDeviceToken(Data(repeating: 0xef, count: 32)),
      .waiting
    )
    XCTAssertEqual(
      handoff.recordNotificationSettings(
        authorization: "denied",
        alertSetting: "enabled",
        badgeSetting: "enabled"
      ),
      .rejected
    )
    XCTAssertFalse(FileManager.default.fileExists(atPath: handoff.responseURL.path))

    try writeRequest(handoff.requestURL, action: "capture")
    XCTAssertEqual(
      handoff.recordNotificationSettings(
        authorization: "authorized",
        alertSetting: "disabled",
        badgeSetting: "enabled"
      ),
      .rejected
    )
    XCTAssertFalse(FileManager.default.fileExists(atPath: handoff.responseURL.path))

    try writeRequest(handoff.requestURL, action: "capture")
    XCTAssertEqual(
      handoff.recordNotificationSettings(
        authorization: "authorized",
        alertSetting: "enabled",
        badgeSetting: "disabled"
      ),
      .rejected
    )
    XCTAssertFalse(FileManager.default.fileExists(atPath: handoff.responseURL.path))
  }

  func testSenderProjectionCommandIsProtectedBoundAndSecretFreeOnCompletion() throws {
    XCTAssertTrue(IosReceiverBootstrapHandoff.isSenderUsername(String(repeating: "x", count: 30)))
    XCTAssertFalse(IosReceiverBootstrapHandoff.isSenderUsername(String(repeating: "x", count: 31)))
    let root = try temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
    let handoff = IosReceiverBootstrapHandoff(
      enabled: true,
      now: { self.now },
      rootDirectory: root
    )
    XCTAssertEqual(handoff.prepareContainer(), .waiting)
    let sender = "12D3KooW" + String(repeating: "2", count: 44)
    let payloadDigest = String(repeating: "a", count: 64)
    let fixtureDigest = String(repeating: "b", count: 64)
    try writeSenderRequest(
      handoff.senderRequestURL,
      action: "seed_sender",
      sender: sender,
      payloadDigest: payloadDigest
    )

    let command = try XCTUnwrap(handoff.takeSenderProjectionRequest())
    XCTAssertEqual(command["senderPeerId"], sender)
    XCTAssertEqual(command["captureNonce"], nonce)
    XCTAssertTrue(
      handoff.completeSenderProjectionRequest(
        captureNonce: nonce,
        action: "seed_sender",
        apnsPayloadSha256: payloadDigest,
        fixtureDigest: fixtureDigest,
        status: "seeded",
        resultCode: "ok"
      )
    )
    XCTAssertFalse(FileManager.default.fileExists(atPath: handoff.senderRequestURL.path))
    let result = try json(handoff.senderResultURL)
    XCTAssertEqual(
      Set(result.keys),
      Set([
        "schema", "action", "captureNonce", "receiverDeviceId", "bundleId",
        "apnsPayloadSha256", "fixtureDigest", "status", "resultCode",
        "completedAt",
      ])
    )
    XCTAssertEqual(result["status"] as? String, "seeded")
    XCTAssertNil(result["senderPeerId"])
    XCTAssertFalse(String(data: try Data(contentsOf: handoff.senderResultURL), encoding: .utf8)!.contains(sender))
    let attributes = try FileManager.default.attributesOfItem(
      atPath: handoff.senderResultURL.path
    )
    XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    assertCompleteFileProtection(attributes)

    // Re-staging the same generation does not return raw sender data to Dart
    // again once its protected completion is present.
    try writeSenderRequest(
      handoff.senderRequestURL,
      action: "seed_sender",
      sender: sender,
      payloadDigest: payloadDigest
    )
    XCTAssertNil(handoff.takeSenderProjectionRequest())
  }

  func testNotificationRecoveryCommandIsProtectedBoundAndSecretFreeOnCompletion() throws {
    let root = try temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
    let handoff = IosReceiverBootstrapHandoff(
      enabled: true,
      now: { self.now },
      rootDirectory: root
    )
    XCTAssertEqual(handoff.prepareContainer(), .waiting)
    let payloadDigest = String(repeating: "c", count: 64)
    let sentinel = "mknoon-sims-recovery-" + String(repeating: "d", count: 24)
    try writeRecoveryRequest(
      handoff.recoveryRequestURL,
      payloadDigest: payloadDigest,
      sentinel: sentinel
    )

    let command = try XCTUnwrap(handoff.takeNotificationRecoveryRequest())
    XCTAssertEqual(command["captureNonce"], nonce)
    XCTAssertEqual(command["accountPeerId"], peer)
    XCTAssertEqual(command["sentinelIdentifier"], sentinel)
    XCTAssertTrue(
      handoff.completeNotificationRecoveryRequest(
        request: command,
        status: "passed",
        resultCode: "ok",
        badgeBefore: 1,
        badgeAfter: 0,
        deliveredBefore: 1,
        deliveredWithSentinel: 2,
        deliveredAfter: 1,
        deliveredNotificationBadgeWasNil: true,
        sentinelSurvived: true,
        removedExactOwnedNotification: true
      )
    )
    XCTAssertFalse(FileManager.default.fileExists(atPath: handoff.recoveryRequestURL.path))
    let result = try json(handoff.recoveryResultURL)
    XCTAssertEqual(
      Set(result.keys),
      Set([
        "schema", "action", "captureNonce", "receiverDeviceId", "bundleId",
        "apnsPayloadSha256", "status", "resultCode", "badgeBefore", "badgeAfter",
        "deliveredBefore", "deliveredWithSentinel", "deliveredAfter",
        "deliveredNotificationBadgeWasNil", "sentinelSurvived",
        "removedExactOwnedNotification", "childBuildCount", "manualActionCount",
        "completedAt",
      ])
    )
    XCTAssertEqual(result["schema"] as? String, IosReceiverBootstrapHandoff.recoveryResultSchema)
    XCTAssertEqual(result["badgeBefore"] as? Int, 1)
    XCTAssertEqual(result["badgeAfter"] as? Int, 0)
    XCTAssertEqual(result["deliveredWithSentinel"] as? Int, 2)
    XCTAssertEqual(result["deliveredNotificationBadgeWasNil"] as? Bool, true)
    XCTAssertNil(result["accountPeerId"])
    XCTAssertNil(result["sentinelIdentifier"])
    let encoded = try XCTUnwrap(String(data: Data(contentsOf: handoff.recoveryResultURL), encoding: .utf8))
    XCTAssertFalse(encoded.contains(peer))
    XCTAssertFalse(encoded.contains(sentinel))
    let attributes = try FileManager.default.attributesOfItem(
      atPath: handoff.recoveryResultURL.path
    )
    XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    assertCompleteFileProtection(attributes)

    try writeRequest(handoff.requestURL, action: "cleanup")
    XCTAssertEqual(handoff.prepareContainer(), .cleaned)
    XCTAssertFalse(FileManager.default.fileExists(atPath: handoff.recoveryResultURL.path))
  }

  func testTC397GroupObservationReceiptIsProtectedAndRedacted() throws {
    let root = try temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
    let handoff = IosReceiverBootstrapHandoff(
      enabled: true,
      now: { self.now },
      rootDirectory: root
    )
    XCTAssertEqual(handoff.prepareContainer(), .waiting)
    let groupHash = String(repeating: "a", count: 64)
    let eventHash = String(repeating: "b", count: 64)
    let targetHash = String(repeating: "c", count: 64)
    try writeGroupObservationRequest(
      handoff.groupObservationRequestURL,
      phase: "reaction",
      groupHash: groupHash,
      eventHash: eventHash,
      targetHash: targetHash
    )

    let command = try XCTUnwrap(
      handoff.takeGroupNotificationObservationRequest()
    )
    XCTAssertEqual(command["phase"], "reaction")
    XCTAssertEqual(command["expectedGroupIdSha256"], groupHash)
    XCTAssertNil(command["groupId"])
    XCTAssertTrue(
      handoff.completeGroupNotificationObservationRequest(
        request: command,
        status: "passed",
        resultCode: "ok",
        inventory: Runner.IosGroupNotificationInventory(
          matchingRemoteCount: 1,
          matchingLocalCount: 0,
          matchingUsefulProviderCount: 1,
          matchingSanitizedProviderCount: 0,
          matchingFlutterLocalCount: 0,
          matchingUnknownCount: 0,
          requestIdentifierSha256: [String(repeating: "d", count: 64)]
        ),
        stableSampleCount: 3,
        sampledThroughDeadline: true,
        badSourceSeen: false,
        duplicateSeen: false
      )
    )
    XCTAssertFalse(
      FileManager.default.fileExists(atPath: handoff.groupObservationRequestURL.path)
    )
    let result = try json(handoff.groupObservationResultURL)
    XCTAssertEqual(
      Set(result.keys),
      Set([
        "schema", "action", "phase", "captureNonce", "receiverDeviceId",
        "bundleId", "expectedGroupIdSha256", "expectedEventIdSha256",
        "expectedTargetMessageIdSha256", "status", "resultCode",
        "matchingRemoteCount", "matchingLocalCount",
        "matchingUsefulProviderCount", "matchingSanitizedProviderCount",
        "matchingFlutterLocalCount", "matchingUnknownCount", "matchingTotalCount",
        "stableSampleCount", "stableSampleIntervalMilliseconds",
        "observationDeadlineMilliseconds", "sampledThroughDeadline",
        "badSourceSeen", "duplicateSeen", "requestIdentifierSha256",
        "childBuildCount", "manualActionCount", "completedAt",
      ])
    )
    XCTAssertEqual(
      result["schema"] as? String,
      IosReceiverBootstrapHandoff.groupObservationResultSchema
    )
    XCTAssertEqual(result["sampledThroughDeadline"] as? Bool, true)
    XCTAssertEqual(result["badSourceSeen"] as? Bool, false)
    XCTAssertEqual(result["duplicateSeen"] as? Bool, false)
    let encoded = try XCTUnwrap(
      String(data: Data(contentsOf: handoff.groupObservationResultURL), encoding: .utf8)
    )
    XCTAssertFalse(encoded.contains("raw-group"))
    let attributes = try FileManager.default.attributesOfItem(
      atPath: handoff.groupObservationResultURL.path
    )
    XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    assertCompleteFileProtection(attributes)

    try writeRequest(handoff.requestURL, action: "cleanup")
    XCTAssertEqual(handoff.prepareContainer(), .cleaned)
    XCTAssertFalse(
      FileManager.default.fileExists(atPath: handoff.groupObservationResultURL.path)
    )
  }

  private func assertCompleteFileProtection(
    _ attributes: [FileAttributeKey: Any],
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    let protection = attributes[.protectionKey] as? FileProtectionType
#if targetEnvironment(simulator)
    XCTAssertTrue(
      protection == nil || protection == .complete,
      "The simulator may omit file-protection metadata, but must not report a weaker class.",
      file: file,
      line: line
    )
#else
    XCTAssertEqual(protection, .complete, file: file, line: line)
#endif
  }

  private func temporaryRoot() throws -> URL {
    let parent = FileManager.default.temporaryDirectory.appendingPathComponent(
      "mknoon-ios-bootstrap-tests-\(UUID().uuidString)",
      isDirectory: true
    )
    try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
    return parent.appendingPathComponent("handoff", isDirectory: true)
  }

  private func writeRequest(
    _ url: URL,
    action: String,
    nonce: String? = nil,
    expiresAt: Date? = nil
  ) throws {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let object: [String: Any] = [
      "schema": IosReceiverBootstrapHandoff.requestSchema,
      "action": action,
      "captureNonce": nonce ?? self.nonce,
      "receiverDeviceId": receiver,
      "bundleId": "com.mknoon.app",
      "expiresAt": formatter.string(from: expiresAt ?? now.addingTimeInterval(180)),
    ]
    let data = try JSONSerialization.data(withJSONObject: object)
    FileManager.default.createFile(
      atPath: url.path,
      contents: data,
      attributes: [.posixPermissions: 0o600]
    )
  }

  private func writeSenderRequest(
    _ url: URL,
    action: String,
    sender: String,
    payloadDigest: String
  ) throws {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let object: [String: Any] = [
      "schema": IosReceiverBootstrapHandoff.senderRequestSchema,
      "action": action,
      "captureNonce": nonce,
      "receiverDeviceId": receiver,
      "bundleId": "com.mknoon.app",
      "senderPeerId": sender,
      "senderUsername": "Encrypted fixture title",
      "apnsPayloadSha256": payloadDigest,
      "createdAt": formatter.string(from: now),
      "expiresAt": formatter.string(from: now.addingTimeInterval(180)),
    ]
    let data = try JSONSerialization.data(withJSONObject: object)
    FileManager.default.createFile(
      atPath: url.path,
      contents: data,
      attributes: [.posixPermissions: 0o600]
    )
  }

  private func writeRecoveryRequest(
    _ url: URL,
    payloadDigest: String,
    sentinel: String
  ) throws {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let object: [String: Any] = [
      "schema": IosReceiverBootstrapHandoff.recoveryRequestSchema,
      "action": "prove_recovery",
      "captureNonce": nonce,
      "receiverDeviceId": receiver,
      "bundleId": "com.mknoon.app",
      "accountPeerId": peer,
      "sentinelIdentifier": sentinel,
      "apnsPayloadSha256": payloadDigest,
      "createdAt": formatter.string(from: now),
      "expiresAt": formatter.string(from: now.addingTimeInterval(180)),
    ]
    let data = try JSONSerialization.data(withJSONObject: object)
    FileManager.default.createFile(
      atPath: url.path,
      contents: data,
      attributes: [.posixPermissions: 0o600]
    )
  }

  private func writeGroupObservationRequest(
    _ url: URL,
    phase: String,
    groupHash: String,
    eventHash: String,
    targetHash: String
  ) throws {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let object: [String: Any] = [
      "schema": IosReceiverBootstrapHandoff.groupObservationRequestSchema,
      "action": "observe_group",
      "phase": phase,
      "captureNonce": nonce,
      "receiverDeviceId": receiver,
      "bundleId": "com.mknoon.app",
      "expectedGroupIdSha256": groupHash,
      "expectedEventIdSha256": eventHash,
      "expectedTargetMessageIdSha256": targetHash,
      "createdAt": formatter.string(from: now),
      "expiresAt": formatter.string(from: now.addingTimeInterval(180)),
    ]
    let data = try JSONSerialization.data(withJSONObject: object)
    FileManager.default.createFile(
      atPath: url.path,
      contents: data,
      attributes: [.posixPermissions: 0o600]
    )
  }

  private func json(_ url: URL) throws -> [String: Any] {
    try XCTUnwrap(
      JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
    )
  }
}
