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
        alertSetting: "enabled"
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
        "notificationAuthorization", "notificationAlertSetting", "capturedAt",
      ])
    )
    XCTAssertEqual(
      response["schema"] as? String,
      "mknoon.sims.ios-provider-receiver-handoff.v1"
    )
    XCTAssertEqual(response["captureNonce"] as? String, nonce)
    XCTAssertEqual(response["receiverDeviceId"] as? String, receiver)
    XCTAssertEqual(response["peerDeviceId"] as? String, peer)
    XCTAssertEqual(response["apnsEnvironment"] as? String, "development")
    XCTAssertEqual(response["apnsDeviceToken"] as? String, String(repeating: "ab", count: 32))
    XCTAssertEqual(response["mlKemPublicKey"] as? String, mlKem)
    XCTAssertEqual(response["notificationAuthorization"] as? String, "authorized")
    XCTAssertEqual(response["notificationAlertSetting"] as? String, "enabled")

    let attributes = try FileManager.default.attributesOfItem(atPath: handoff.responseURL.path)
    XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    XCTAssertEqual(attributes[.protectionKey] as? FileProtectionType, .complete)
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
      alertSetting: "enabled"
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

  func testCaptureRejectsDeniedOrAlertDisabledNotificationSettings() throws {
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
        alertSetting: "enabled"
      ),
      .rejected
    )
    XCTAssertFalse(FileManager.default.fileExists(atPath: handoff.responseURL.path))

    try writeRequest(handoff.requestURL, action: "capture")
    XCTAssertEqual(
      handoff.recordNotificationSettings(
        authorization: "authorized",
        alertSetting: "disabled"
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
    XCTAssertEqual(attributes[.protectionKey] as? FileProtectionType, .complete)

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

  private func json(_ url: URL) throws -> [String: Any] {
    try XCTUnwrap(
      JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
    )
  }
}
