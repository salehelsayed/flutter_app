import CryptoKit
import Foundation
import UserNotifications
import XCTest

@testable import Runner

final class IosReceiverBootstrapHandoffTests: XCTestCase {
  private let now = Date(timeIntervalSince1970: 1_900_000_000)
  private let receiver = "00008110-001A123E0E91801E"
  private let nonce = "nonce-bootstrap-native-1"
  private let peer = "12D3KooW" + String(repeating: "1", count: 44)
  private let mlKem = Data(repeating: 0x41, count: 1184).base64EncodedString()

  func testTC396StableSamplerCompletesAtHardDeadlineWhenCallbackIsMissing() {
    var fetchCallback: (([UNNotification]) -> Void)?
    var scheduled: [(TimeInterval, () -> Void)] = []
    var outcomes: [IosDirectNotificationStableSampleOutcome] = []
    let sampler = IosDirectNotificationStableSampler(
      now: { self.now },
      scheduleAfter: { delay, action in scheduled.append((delay, action)) },
      fetchDeliveredNotifications: { callback in fetchCallback = callback }
    )

    sampler.start(
      expectedPeerId: peer,
      expectedMessageId: "direct-message-396",
      deadline: now.addingTimeInterval(8),
      completion: { outcomes.append($0) }
    )

    XCTAssertNotNil(fetchCallback)
    XCTAssertEqual(scheduled.count, 1)
    XCTAssertEqual(scheduled[0].0, 8, accuracy: 0.001)
    XCTAssertTrue(outcomes.isEmpty)
    scheduled[0].1()
    XCTAssertEqual(outcomes.count, 1)
    XCTAssertEqual(outcomes[0].resultCode, .deadlineExceeded)
    XCTAssertEqual(outcomes[0].stableSampleCount, 0)
    XCTAssertEqual(outcomes[0].inventory, .empty)
  }

  func testTC396StableSamplerIgnoresCallbackAfterHardDeadlineCompletion() {
    var fetchCallback: (([UNNotification]) -> Void)?
    var scheduled: [(TimeInterval, () -> Void)] = []
    var outcomes: [IosDirectNotificationStableSampleOutcome] = []
    let sampler = IosDirectNotificationStableSampler(
      now: { self.now },
      scheduleAfter: { delay, action in scheduled.append((delay, action)) },
      fetchDeliveredNotifications: { callback in fetchCallback = callback }
    )

    sampler.start(
      expectedPeerId: peer,
      expectedMessageId: "direct-message-396",
      deadline: now.addingTimeInterval(8),
      completion: { outcomes.append($0) }
    )
    scheduled[0].1()
    fetchCallback?([])

    XCTAssertEqual(outcomes.count, 1)
    XCTAssertEqual(outcomes[0].resultCode, .deadlineExceeded)
  }

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

  func testTC396RecoveryResultPublishesBoundedSourceCounts() throws {
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
    XCTAssertEqual(command["expectedSenderPeerId"], peer)
    XCTAssertEqual(command["expectedMessageId"], "direct-message-396")
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
        removedExactOwnedNotification: true,
        inventory: Runner.IosDirectNotificationInventory(
          matchingRemoteCount: 1,
          matchingLocalCount: 0,
          matchingUsefulProviderCount: 1,
          matchingSanitizedProviderCount: 0,
          matchingFlutterLocalCount: 0,
          matchingUnknownCount: 0,
          requestIdentifierSha256: [String(repeating: "a", count: 64)]
        ),
        stableSampleCount: 3
      )
    )
    XCTAssertFalse(FileManager.default.fileExists(atPath: handoff.recoveryRequestURL.path))
    let result = try json(handoff.recoveryResultURL)
    XCTAssertEqual(
      Set(result.keys),
      Set([
        "schema", "action", "proofStage", "captureNonce", "receiverDeviceId", "bundleId",
        "apnsPayloadSha256", "status", "resultCode", "badgeBefore", "badgeAfter",
        "deliveredBefore", "deliveredWithSentinel", "deliveredAfter",
        "deliveredNotificationBadgeWasNil", "sentinelSurvived",
        "removedExactOwnedNotification", "childBuildCount", "manualActionCount",
        "matchingRemoteCount", "matchingLocalCount", "matchingUsefulProviderCount",
        "matchingSanitizedProviderCount", "matchingFlutterLocalCount",
        "matchingUnknownCount", "matchingTotalCount", "stableSampleCount",
        "stableSampleIntervalMilliseconds", "settleDelayMilliseconds",
        "observationDeadlineMilliseconds", "requestIdentifierSha256", "completedAt",
      ])
    )
    XCTAssertEqual(result["schema"] as? String, IosReceiverBootstrapHandoff.recoveryResultSchema)
    XCTAssertEqual(result["badgeBefore"] as? Int, 1)
    XCTAssertEqual(result["badgeAfter"] as? Int, 0)
    XCTAssertEqual(result["deliveredWithSentinel"] as? Int, 2)
    XCTAssertEqual(result["deliveredNotificationBadgeWasNil"] as? Bool, true)
    XCTAssertEqual(result["matchingUsefulProviderCount"] as? Int, 1)
    XCTAssertEqual(result["matchingFlutterLocalCount"] as? Int, 0)
    XCTAssertEqual(result["stableSampleCount"] as? Int, 3)
    XCTAssertEqual(
      result["requestIdentifierSha256"] as? [String],
      [String(repeating: "a", count: 64)]
    )
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
    let requestHash = String(repeating: "d", count: 64)
    let diagnosticRecord = Runner.IosGroupNotificationDiagnosticRecord(
      requestIdentifierSha256: requestHash,
      triggerOrigin: .remote,
      sourceClass: .usefulProviderRich,
      reason: .exactUseful,
      expectedCollapseIdentifierMatch: true,
      dispatchClaim: .groupInbox
    )
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
          requestIdentifierSha256: [requestHash],
          diagnosticRecords: [diagnosticRecord]
        ),
        stableSampleCount: 3,
        sampledThroughDeadline: true,
        badSourceSeen: false,
        duplicateSeen: false,
        diagnosticRecords: [diagnosticRecord],
        diagnosticComplete: true
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
        "expectedTargetMessageIdSha256",
        "expectedCollapseIdentifierSha256", "status", "resultCode",
        "matchingRemoteCount", "matchingLocalCount",
        "matchingUsefulProviderCount", "matchingSanitizedProviderCount",
        "matchingFlutterLocalCount", "matchingUnknownCount", "matchingTotalCount",
        "stableSampleCount", "stableSampleIntervalMilliseconds",
        "observationDeadlineMilliseconds", "sampledThroughDeadline",
        "badSourceSeen", "duplicateSeen", "requestIdentifierSha256",
        "diagnosticSchema", "diagnosticRecords", "diagnosticRecordCount",
        "diagnosticOverflow", "diagnosticConflict", "diagnosticComplete",
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

  func testTC398GroupObservationReceiptPersistsBoundedPerCardDiagnostics() throws {
    func hash(_ value: String) -> String {
      SHA256.hash(data: Data(value.utf8))
        .map { String(format: "%02x", $0) }.joined()
    }
    let root = try temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
    let handoff = IosReceiverBootstrapHandoff(
      enabled: true,
      now: { self.now },
      rootDirectory: root
    )
    XCTAssertEqual(handoff.prepareContainer(), .waiting)
    let dispatchCorrelation = "01234567-89ab-4cde-8fab-0123456789ab"
    let claimedCollapseIdentifier =
      "group-message:" + String(repeating: "d", count: 48)
    let providerMessageId = "0:1900000398%aabbccdd"
    let expectedHash = hash(claimedCollapseIdentifier)
    try writeGroupObservationRequest(
      handoff.groupObservationRequestURL,
      phase: "message",
      groupHash: String(repeating: "a", count: 64),
      eventHash: String(repeating: "b", count: 64),
      targetHash: String(repeating: "c", count: 64),
      expectedCollapseIdentifierSha256: expectedHash
    )

    let command = try XCTUnwrap(
      handoff.takeGroupNotificationObservationRequest(),
      "TC-398-02 protected receipt"
    )
    XCTAssertEqual(
      command["expectedCollapseIdentifierSha256"],
      expectedHash
    )
    let validRecord = Runner.IosGroupNotificationDiagnosticRecord(
      requestIdentifierSha256: expectedHash,
      triggerOrigin: .remote,
      sourceClass: .usefulProviderRich,
      reason: .exactUseful,
      expectedCollapseIdentifierMatch: true,
      dispatchClaim: .groupInbox,
      dispatchCorrelationSha256: hash(dispatchCorrelation),
      claimedCollapseIdentifierSha256: hash(claimedCollapseIdentifier),
      providerMessageIdSha256: hash(providerMessageId)
    )
    let invalidRecord = Runner.IosGroupNotificationDiagnosticRecord(
      requestIdentifierSha256: String(repeating: "e", count: 64),
      triggerOrigin: .remote,
      sourceClass: .usefulProviderRich,
      reason: .partialContent,
      expectedCollapseIdentifierMatch: false,
      dispatchClaim: .absent
    )
    let malformedDigestRecord = Runner.IosGroupNotificationDiagnosticRecord(
      requestIdentifierSha256: String(repeating: "e", count: 64),
      triggerOrigin: .remote,
      sourceClass: .usefulProviderRich,
      reason: .exactUseful,
      expectedCollapseIdentifierMatch: false,
      dispatchClaim: .groupInbox,
      dispatchCorrelationSha256: "raw-dispatch-id"
    )
    let contradictoryCollapseRecord =
      Runner.IosGroupNotificationDiagnosticRecord(
        requestIdentifierSha256: expectedHash,
        triggerOrigin: .remote,
        sourceClass: .usefulProviderRich,
        reason: .exactUseful,
        expectedCollapseIdentifierMatch: false,
        dispatchClaim: .groupInbox,
        dispatchCorrelationSha256: hash(dispatchCorrelation),
        claimedCollapseIdentifierSha256: hash(claimedCollapseIdentifier),
        providerMessageIdSha256: hash(providerMessageId)
      )
    let inventory = Runner.IosGroupNotificationInventory(
      matchingRemoteCount: 1,
      matchingLocalCount: 0,
      matchingUsefulProviderCount: 1,
      matchingSanitizedProviderCount: 0,
      matchingFlutterLocalCount: 0,
      matchingUnknownCount: 0,
      requestIdentifierSha256: [expectedHash],
      diagnosticRecords: [validRecord]
    )

    XCTAssertTrue(handoff.completeGroupNotificationObservationRequest(
      request: command,
      status: "passed",
      resultCode: "ok",
      inventory: inventory,
      stableSampleCount: 3,
      sampledThroughDeadline: true,
      badSourceSeen: false,
      duplicateSeen: false,
      diagnosticRecords: [validRecord],
      diagnosticComplete: true
    ))

    let missingFinalDiagnosticsInventory =
      Runner.IosGroupNotificationInventory(
        matchingRemoteCount: 1,
        matchingLocalCount: 0,
        matchingUsefulProviderCount: 1,
        matchingSanitizedProviderCount: 0,
        matchingFlutterLocalCount: 0,
        matchingUnknownCount: 0,
        requestIdentifierSha256: [expectedHash]
      )
    XCTAssertFalse(handoff.completeGroupNotificationObservationRequest(
      request: command,
      status: "failed",
      resultCode: "bad_source_seen",
      inventory: missingFinalDiagnosticsInventory,
      stableSampleCount: 3,
      sampledThroughDeadline: true,
      badSourceSeen: true,
      duplicateSeen: true,
      diagnosticRecords: [validRecord],
      diagnosticComplete: true
    ))

    // The handoff must reproduce AppDelegate's closed producer mapping rather
    // than accept any syntactically valid non-ok result code.
    XCTAssertFalse(handoff.completeGroupNotificationObservationRequest(
      request: command,
      status: "failed",
      resultCode: "open",
      inventory: inventory,
      stableSampleCount: 3,
      sampledThroughDeadline: true,
      badSourceSeen: false,
      duplicateSeen: false,
      diagnosticRecords: [validRecord],
      diagnosticComplete: true
    ))
    XCTAssertFalse(handoff.completeGroupNotificationObservationRequest(
      request: command,
      status: "failed",
      resultCode: "source_inventory_mismatch",
      inventory: inventory,
      stableSampleCount: 3,
      sampledThroughDeadline: true,
      badSourceSeen: false,
      duplicateSeen: false,
      diagnosticRecords: [validRecord],
      diagnosticComplete: true
    ))
    XCTAssertFalse(handoff.completeGroupNotificationObservationRequest(
      request: command,
      status: "failed",
      resultCode: "bad_source_seen",
      inventory: inventory,
      stableSampleCount: 2,
      sampledThroughDeadline: true,
      badSourceSeen: true,
      duplicateSeen: true,
      diagnosticRecords: [validRecord],
      diagnosticComplete: true
    ))
    XCTAssertTrue(handoff.completeGroupNotificationObservationRequest(
      request: command,
      status: "failed",
      resultCode: "source_inventory_unstable",
      inventory: inventory,
      stableSampleCount: 2,
      sampledThroughDeadline: true,
      badSourceSeen: true,
      duplicateSeen: true,
      diagnosticRecords: [validRecord],
      diagnosticComplete: true
    ))
    XCTAssertTrue(handoff.completeGroupNotificationObservationRequest(
      request: command,
      status: "failed",
      resultCode: "source_inventory_unstable",
      inventory: inventory,
      stableSampleCount: 3,
      sampledThroughDeadline: false,
      badSourceSeen: true,
      duplicateSeen: true,
      diagnosticRecords: [validRecord],
      diagnosticComplete: false
    ))
    XCTAssertTrue(handoff.completeGroupNotificationObservationRequest(
      request: command,
      status: "failed",
      resultCode: "source_inventory_mismatch",
      inventory: .empty,
      stableSampleCount: 3,
      sampledThroughDeadline: true,
      badSourceSeen: false,
      duplicateSeen: false,
      diagnosticComplete: false
    ))
    XCTAssertFalse(handoff.completeGroupNotificationObservationRequest(
      request: command,
      status: "failed",
      resultCode: "duplicate_seen",
      inventory: inventory,
      stableSampleCount: 3,
      sampledThroughDeadline: true,
      badSourceSeen: true,
      duplicateSeen: true,
      diagnosticRecords: [validRecord],
      diagnosticComplete: true
    ))

    XCTAssertFalse(handoff.completeGroupNotificationObservationRequest(
      request: command,
      status: "failed",
      resultCode: "duplicate_seen",
      inventory: inventory,
      stableSampleCount: 3,
      sampledThroughDeadline: true,
      badSourceSeen: true,
      duplicateSeen: true,
      diagnosticRecords: [malformedDigestRecord],
      diagnosticComplete: true
    ))
    XCTAssertFalse(handoff.completeGroupNotificationObservationRequest(
      request: command,
      status: "failed",
      resultCode: "duplicate_seen",
      inventory: inventory,
      stableSampleCount: 3,
      sampledThroughDeadline: true,
      badSourceSeen: true,
      duplicateSeen: true,
      diagnosticRecords: [contradictoryCollapseRecord],
      diagnosticComplete: true
    ))
    let contradictoryCountInventory = Runner.IosGroupNotificationInventory(
      matchingRemoteCount: 2,
      matchingLocalCount: 0,
      matchingUsefulProviderCount: 1,
      matchingSanitizedProviderCount: 0,
      matchingFlutterLocalCount: 0,
      matchingUnknownCount: 0,
      requestIdentifierSha256: [expectedHash],
      diagnosticRecords: [validRecord]
    )
    XCTAssertFalse(handoff.completeGroupNotificationObservationRequest(
      request: command,
      status: "failed",
      resultCode: "duplicate_seen",
      inventory: contradictoryCountInventory,
      stableSampleCount: 3,
      sampledThroughDeadline: true,
      badSourceSeen: true,
      duplicateSeen: true,
      diagnosticRecords: [validRecord],
      diagnosticComplete: true
    ))
    let contradictoryCategoryInventory = Runner.IosGroupNotificationInventory(
      matchingRemoteCount: 0,
      matchingLocalCount: 1,
      matchingUsefulProviderCount: 1,
      matchingSanitizedProviderCount: 0,
      matchingFlutterLocalCount: 0,
      matchingUnknownCount: 0,
      requestIdentifierSha256: [expectedHash],
      diagnosticRecords: [validRecord]
    )
    XCTAssertFalse(handoff.completeGroupNotificationObservationRequest(
      request: command,
      status: "failed",
      resultCode: "duplicate_seen",
      inventory: contradictoryCategoryInventory,
      stableSampleCount: 3,
      sampledThroughDeadline: true,
      badSourceSeen: true,
      duplicateSeen: true,
      diagnosticRecords: [validRecord],
      diagnosticComplete: true
    ))
    let duplicateHashInventory = Runner.IosGroupNotificationInventory(
      matchingRemoteCount: 2,
      matchingLocalCount: 0,
      matchingUsefulProviderCount: 2,
      matchingSanitizedProviderCount: 0,
      matchingFlutterLocalCount: 0,
      matchingUnknownCount: 0,
      requestIdentifierSha256: [expectedHash, expectedHash],
      diagnosticRecords: [validRecord]
    )
    XCTAssertFalse(handoff.completeGroupNotificationObservationRequest(
      request: command,
      status: "failed",
      resultCode: "duplicate_seen",
      inventory: duplicateHashInventory,
      stableSampleCount: 3,
      sampledThroughDeadline: true,
      badSourceSeen: true,
      duplicateSeen: true,
      diagnosticRecords: [validRecord],
      diagnosticComplete: true
    ))

    XCTAssertFalse(handoff.completeGroupNotificationObservationRequest(
      request: command,
      status: "failed",
      resultCode: "duplicate_seen",
      inventory: inventory,
      stableSampleCount: 3,
      sampledThroughDeadline: true,
      badSourceSeen: true,
      duplicateSeen: true,
      diagnosticRecords: [invalidRecord],
      diagnosticComplete: true
    ))
    let nineRecords = (0..<9).map { index in
      Runner.IosGroupNotificationDiagnosticRecord(
        requestIdentifierSha256: String(
          repeating: String(format: "%x", index),
          count: 64
        ),
        triggerOrigin: .remote,
        sourceClass: .unknown,
        reason: .unclassifiedRemote,
        expectedCollapseIdentifierMatch: false,
        dispatchClaim: .absent
      )
    }
    XCTAssertFalse(handoff.completeGroupNotificationObservationRequest(
      request: command,
      status: "failed",
      resultCode: "duplicate_seen",
      inventory: inventory,
      stableSampleCount: 3,
      sampledThroughDeadline: true,
      badSourceSeen: true,
      duplicateSeen: true,
      diagnosticRecords: nineRecords,
      diagnosticOverflow: true,
      diagnosticComplete: false
    ))
    XCTAssertFalse(handoff.completeGroupNotificationObservationRequest(
      request: command,
      status: "failed",
      resultCode: "duplicate_seen",
      inventory: inventory,
      stableSampleCount: 3,
      sampledThroughDeadline: true,
      badSourceSeen: true,
      duplicateSeen: true,
      diagnosticRecords: [validRecord],
      diagnosticComplete: false
    ))
    XCTAssertTrue(handoff.completeGroupNotificationObservationRequest(
      request: command,
      status: "failed",
      resultCode: "bad_source_seen",
      inventory: inventory,
      stableSampleCount: 3,
      sampledThroughDeadline: true,
      badSourceSeen: true,
      duplicateSeen: true,
      diagnosticRecords: [validRecord],
      diagnosticComplete: true
    ))

    let result = try json(handoff.groupObservationResultURL)
    XCTAssertEqual(result["status"] as? String, "failed")
    XCTAssertEqual(
      result["expectedCollapseIdentifierSha256"] as? String,
      expectedHash
    )
    XCTAssertEqual(
      result["diagnosticSchema"] as? String,
      IosReceiverBootstrapHandoff.groupObservationDiagnosticSchema
    )
    XCTAssertEqual(
      IosReceiverBootstrapHandoff.groupObservationResultSchema,
      "mknoon.sims.ios-group-notification-observation-result.v3"
    )
    XCTAssertEqual(
      IosReceiverBootstrapHandoff.groupObservationDiagnosticSchema,
      "mknoon.sims.ios-group-notification-diagnostics.v2"
    )
    XCTAssertEqual(result["diagnosticRecordCount"] as? Int, 1)
    XCTAssertEqual(result["diagnosticOverflow"] as? Bool, false)
    XCTAssertEqual(result["diagnosticConflict"] as? Bool, false)
    XCTAssertEqual(result["diagnosticComplete"] as? Bool, true)
    let records = try XCTUnwrap(
      result["diagnosticRecords"] as? [[String: Any]]
    )
    XCTAssertEqual(Set(records[0].keys), Set([
      "requestIdentifierSha256", "triggerOrigin", "sourceClass", "reason",
      "expectedCollapseIdentifierMatch", "dispatchClaim",
      "dispatchCorrelationSha256", "claimedCollapseIdentifierSha256",
      "providerMessageIdSha256",
    ]))
    XCTAssertEqual(records[0]["triggerOrigin"] as? String, "remote")
    XCTAssertEqual(records[0]["sourceClass"] as? String, "usefulProviderRich")
    XCTAssertEqual(records[0]["reason"] as? String, "exactUseful")
    XCTAssertEqual(records[0]["dispatchClaim"] as? String, "groupInbox")
    XCTAssertEqual(
      records[0]["dispatchCorrelationSha256"] as? String,
      hash(dispatchCorrelation)
    )
    XCTAssertEqual(
      records[0]["claimedCollapseIdentifierSha256"] as? String,
      hash(claimedCollapseIdentifier)
    )
    XCTAssertEqual(
      records[0]["providerMessageIdSha256"] as? String,
      hash(providerMessageId)
    )
    let nilRecord = Runner.IosGroupNotificationDiagnosticRecord(
      requestIdentifierSha256: String(repeating: "f", count: 64),
      triggerOrigin: .remote,
      sourceClass: .unknown,
      reason: .unclassifiedRemote,
      expectedCollapseIdentifierMatch: false,
      dispatchClaim: .absent
    )
    XCTAssertTrue(nilRecord.jsonObject["dispatchCorrelationSha256"] is NSNull)
    XCTAssertTrue(
      nilRecord.jsonObject["claimedCollapseIdentifierSha256"] is NSNull
    )
    XCTAssertTrue(nilRecord.jsonObject["providerMessageIdSha256"] is NSNull)
    let encoded = try Data(contentsOf: handoff.groupObservationResultURL)
    XCTAssertLessThanOrEqual(encoded.count, 8_192)
    let text = try XCTUnwrap(String(data: encoded, encoding: .utf8))
    XCTAssertFalse(text.contains("group-398"))
    XCTAssertFalse(text.contains("message-398"))
    XCTAssertFalse(text.contains("collapse-398"))
    XCTAssertFalse(text.contains(dispatchCorrelation))
    XCTAssertFalse(text.contains(claimedCollapseIdentifier))
    XCTAssertFalse(text.contains(providerMessageId))

    let maximumRoot = try temporaryRoot()
    defer {
      try? FileManager.default.removeItem(
        at: maximumRoot.deletingLastPathComponent()
      )
    }
    let maximumHandoff = IosReceiverBootstrapHandoff(
      enabled: true,
      now: { self.now },
      rootDirectory: maximumRoot
    )
    XCTAssertEqual(maximumHandoff.prepareContainer(), .waiting)
    try writeGroupObservationRequest(
      maximumHandoff.groupObservationRequestURL,
      phase: "message",
      groupHash: String(repeating: "a", count: 64),
      eventHash: String(repeating: "b", count: 64),
      targetHash: String(repeating: "c", count: 64),
      expectedCollapseIdentifierSha256: expectedHash
    )
    let maximumCommand = try XCTUnwrap(
      maximumHandoff.takeGroupNotificationObservationRequest()
    )
    let maximumRecords = (0..<8).map { index in
      Runner.IosGroupNotificationDiagnosticRecord(
        requestIdentifierSha256: String(
          repeating: String(format: "%x", index),
          count: 64
        ),
        triggerOrigin: .remote,
        sourceClass: .usefulProviderRich,
        reason: .exactUseful,
        expectedCollapseIdentifierMatch: false,
        dispatchClaim: .groupContent,
        dispatchCorrelationSha256: hash(
          "00000000-0000-4000-8000-00000000000\(index)"
        ),
        claimedCollapseIdentifierSha256: hash(
          "group-message:" + String(repeating: String(format: "%x", index), count: 48)
        ),
        providerMessageIdSha256: hash(
          "0:1900000398%aabbccd\(index)"
        )
      )
    }
    let maximumHashes = maximumRecords.map(\.requestIdentifierSha256).sorted()
    let maximumInventory = Runner.IosGroupNotificationInventory(
      matchingRemoteCount: 8,
      matchingLocalCount: 0,
      matchingUsefulProviderCount: 8,
      matchingSanitizedProviderCount: 0,
      matchingFlutterLocalCount: 0,
      matchingUnknownCount: 0,
      requestIdentifierSha256: maximumHashes,
      diagnosticRecords: maximumRecords
    )
    XCTAssertTrue(maximumHandoff.completeGroupNotificationObservationRequest(
      request: maximumCommand,
      status: "failed",
      resultCode: "duplicate_seen",
      inventory: maximumInventory,
      stableSampleCount: 3,
      sampledThroughDeadline: true,
      badSourceSeen: false,
      duplicateSeen: true,
      diagnosticRecords: maximumRecords,
      diagnosticComplete: true
    ))
    let maximumEncoded = try Data(
      contentsOf: maximumHandoff.groupObservationResultURL
    )
    XCTAssertGreaterThan(maximumEncoded.count, 4_096)
    XCTAssertLessThanOrEqual(maximumEncoded.count, 8_192)
  }

  func testTC398SetupEntryReceiptAdvancesNativeToDartAndRejectsGateBypass() throws {
    let parent = try temporaryRoot()
    defer { try? FileManager.default.removeItem(at: parent.deletingLastPathComponent()) }
    let rawAttempt = "plan398-v3-entry-attempt-0001"
    let attemptSha256 = SHA256.hash(data: Data(rawAttempt.utf8))
      .map { String(format: "%02x", $0) }
      .joined()
    let validEnvironment = [
      IosSetupReadinessEntryCoordinator.attemptEnvironmentKey: rawAttempt,
      IosSetupReadinessEntryCoordinator.profileEnvironmentKey:
        IosSetupReadinessEntryCoordinator.expectedProfileId,
    ]
    let validRoot = parent.appendingPathComponent("valid", isDirectory: true)
    let coordinator = IosSetupReadinessEntryCoordinator(
      documentsDirectory: validRoot
    )

    XCTAssertEqual(
      coordinator.armNativeLaunch(environment: validEnvironment),
      .published
    )
    var receipt = try json(coordinator.receiptURL)
    XCTAssertEqual(Set(receipt.keys), Set([
      "schema", "status", "stage", "reason", "profileId",
      "launchAttemptSha256", "nativeEntryAcknowledged",
      "dartEntryAcknowledged", "launchInputPresent",
      "identityInitiallyPresent", "generationAttempted",
      "generationSucceeded", "reloadSucceeded", "qrPayloadBuilt",
      "identityExported", "identityExportSha256", "containsSecrets",
    ]))
    XCTAssertEqual(
      receipt["schema"] as? String,
      "mknoon.plan398.ios-setup-readiness.v3"
    )
    XCTAssertEqual(receipt["status"] as? String, "FAIL")
    XCTAssertEqual(receipt["stage"] as? String, "native_app_delegate")
    XCTAssertEqual(receipt["reason"] as? String, "dart_main_not_reached")
    XCTAssertEqual(receipt["profileId"] as? String, "ios.device.group_reaction_notification_397")
    XCTAssertEqual(receipt["launchAttemptSha256"] as? String, attemptSha256)
    XCTAssertEqual(receipt["nativeEntryAcknowledged"] as? Bool, true)
    XCTAssertEqual(receipt["dartEntryAcknowledged"] as? Bool, false)
    XCTAssertEqual(receipt["containsSecrets"] as? Bool, false)
    let nativeBytes = try Data(contentsOf: coordinator.receiptURL)
    XCTAssertLessThanOrEqual(nativeBytes.count, 2_048)
    XCTAssertFalse(String(decoding: nativeBytes, as: UTF8.self).contains(rawAttempt))
    let attributes = try FileManager.default.attributesOfItem(
      atPath: coordinator.receiptURL.path
    )
    XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    assertCompleteFileProtection(attributes)

    XCTAssertThrowsError(try coordinator.acknowledgeDartMain(arguments: [
      "schema": IosSetupReadinessEntryCoordinator.schema,
      "profileId": IosSetupReadinessEntryCoordinator.expectedProfileId,
      "launchAttemptSha256": String(repeating: "f", count: 64),
    ]))
    XCTAssertThrowsError(try coordinator.acknowledgeDartMain(arguments: [
      "schema": IosSetupReadinessEntryCoordinator.schema,
      "profileId": IosSetupReadinessEntryCoordinator.expectedProfileId,
      "launchAttemptSha256": attemptSha256,
      "rawAttempt": rawAttempt,
    ]))
    XCTAssertEqual(
      try json(coordinator.receiptURL)["stage"] as? String,
      "native_app_delegate"
    )

    let acknowledgement = try coordinator.acknowledgeDartMain(arguments: [
      "schema": IosSetupReadinessEntryCoordinator.schema,
      "profileId": IosSetupReadinessEntryCoordinator.expectedProfileId,
      "launchAttemptSha256": attemptSha256,
    ])
    XCTAssertEqual(Set(acknowledgement.keys), Set([
      "schema", "status", "stage", "reason", "profileId",
      "launchAttemptSha256", "nativeEntryAcknowledged",
      "dartEntryAcknowledged", "launchInputPresent",
      "identityInitiallyPresent", "generationAttempted",
      "generationSucceeded", "reloadSucceeded", "qrPayloadBuilt",
      "identityExported", "identityExportSha256", "containsSecrets",
    ]))
    receipt = try json(coordinator.receiptURL)
    XCTAssertEqual(receipt["stage"] as? String, "dart_main")
    XCTAssertEqual(
      receipt["reason"] as? String,
      "application_documents_not_ready"
    )
    XCTAssertEqual(receipt["nativeEntryAcknowledged"] as? Bool, true)
    XCTAssertEqual(receipt["dartEntryAcknowledged"] as? Bool, true)
    XCTAssertEqual(
      acknowledgement["launchAttemptSha256"] as? String,
      attemptSha256
    )
    XCTAssertThrowsError(try coordinator.acknowledgeDartMain(arguments: [
      "schema": IosSetupReadinessEntryCoordinator.schema,
      "profileId": IosSetupReadinessEntryCoordinator.expectedProfileId,
      "launchAttemptSha256": attemptSha256,
    ]))

    let gateCases: [([String: String], IosSetupReadinessEntryCoordinator.ArmOutcome)] = [
      ([:], .inactive),
      ([IosSetupReadinessEntryCoordinator.attemptEnvironmentKey: rawAttempt], .rejected),
      ([
        IosSetupReadinessEntryCoordinator.profileEnvironmentKey:
          IosSetupReadinessEntryCoordinator.expectedProfileId,
      ], .rejected),
      ([
        IosSetupReadinessEntryCoordinator.attemptEnvironmentKey: "too short",
        IosSetupReadinessEntryCoordinator.profileEnvironmentKey:
          IosSetupReadinessEntryCoordinator.expectedProfileId,
      ], .rejected),
      ([
        IosSetupReadinessEntryCoordinator.attemptEnvironmentKey: rawAttempt,
        IosSetupReadinessEntryCoordinator.profileEnvironmentKey: "ios.device.production",
      ], .rejected),
    ]
    for (index, gateCase) in gateCases.enumerated() {
      let rejected = IosSetupReadinessEntryCoordinator(
        documentsDirectory: parent.appendingPathComponent(
          "gate-\(index)",
          isDirectory: true
        )
      )
      XCTAssertEqual(
        rejected.armNativeLaunch(environment: gateCase.0),
        gateCase.1,
        "gate case \(index)"
      )
      XCTAssertFalse(FileManager.default.fileExists(atPath: rejected.receiptURL.path))
      XCTAssertThrowsError(try rejected.acknowledgeDartMain(arguments: [
        "schema": IosSetupReadinessEntryCoordinator.schema,
        "profileId": IosSetupReadinessEntryCoordinator.expectedProfileId,
        "launchAttemptSha256": attemptSha256,
      ]))
    }

    let blockedRoot = parent.appendingPathComponent("blocked", isDirectory: false)
    XCTAssertTrue(FileManager.default.createFile(atPath: blockedRoot.path, contents: Data()))
    let blocked = IosSetupReadinessEntryCoordinator(documentsDirectory: blockedRoot)
    XCTAssertEqual(
      blocked.armNativeLaunch(environment: validEnvironment),
      .rejected
    )
    XCTAssertThrowsError(try blocked.acknowledgeDartMain(arguments: [
      "schema": IosSetupReadinessEntryCoordinator.schema,
      "profileId": IosSetupReadinessEntryCoordinator.expectedProfileId,
      "launchAttemptSha256": attemptSha256,
    ]))
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
      "expectedSenderPeerId": peer,
      "expectedMessageId": "direct-message-396",
      "sentinelIdentifier": sentinel,
      "proofStage": "single_submission",
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
    targetHash: String,
    expectedCollapseIdentifierSha256: String = String(
      repeating: "d",
      count: 64
    )
  ) throws {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    var object: [String: Any] = [
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
    object["expectedCollapseIdentifierSha256"] =
      expectedCollapseIdentifierSha256
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
