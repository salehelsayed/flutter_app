import Flutter
import Foundation
import PushKit
import XCTest

@testable import Runner

final class MknoonVoipPushRegistryTests: XCTestCase {
  private let now: Int64 = 1_900_000_000_000
  private let call = "123e4567-e89b-42d3-a456-426614174000"
  private let contact = "223e4567-e89b-42d3-a456-426614174001"

  func testTokenUpdateDuplicateRotationAndInvalidationPersistExactEpoch() throws {
    let backend = MemoryVoipTokenBackend()
    let authority = MknoonVoipTokenAuthority(backend: backend)
    var events: [MknoonVoipTokenSnapshot] = []
    authority.setEventHandler { events.append($0) }

    XCTAssertTrue(authority.update(
      token: Data([0x01, 0xab]),
      environment: "development",
      topic: "com.mknoon.app.voip"
    ))
    XCTAssertTrue(authority.update(
      token: Data([0x01, 0xab]),
      environment: "development",
      topic: "com.mknoon.app.voip"
    ))
    XCTAssertEqual(events.count, 1)
    XCTAssertEqual(authority.current()?.token, "01ab")
    XCTAssertEqual(authority.current()?.refreshEpoch, 1)

    XCTAssertTrue(authority.update(
      token: Data([0xcd, 0xef]),
      environment: "production",
      topic: "com.mknoon.app.voip"
    ))
    XCTAssertEqual(events.count, 2)
    XCTAssertEqual(authority.current()?.refreshEpoch, 2)
    XCTAssertEqual(authority.current()?.environment, "production")

    XCTAssertTrue(authority.invalidate())
    let invalidated = try XCTUnwrap(authority.current())
    XCTAssertEqual(invalidated.token, "")
    XCTAssertEqual(invalidated.refreshEpoch, 2)
    XCTAssertTrue(invalidated.invalidated)
    XCTAssertEqual(MknoonVoipTokenAuthority(backend: backend).current(), invalidated)
    XCTAssertTrue(MknoonVoipTokenAuthority(backend: backend).invalidate())
    XCTAssertEqual(events.count, 3)
  }

  func testTokenSnapshotShapeIsFixedAndDurabilityFailureCannotPublish() throws {
    let backend = MemoryVoipTokenBackend()
    let authority = MknoonVoipTokenAuthority(backend: backend)
    XCTAssertFalse(authority.update(
      token: Data([1]),
      environment: "sandbox",
      topic: "com.mknoon.app.voip"
    ))
    backend.failWrites = true
    var emitted = false
    authority.setEventHandler { _ in emitted = true }
    XCTAssertFalse(authority.update(
      token: Data([1]),
      environment: "development",
      topic: "com.mknoon.app.voip"
    ))
    XCTAssertNil(authority.current())
    XCTAssertFalse(emitted)

    backend.failWrites = false
    XCTAssertTrue(authority.update(
      token: Data([0x0a]),
      environment: "development",
      topic: "com.mknoon.app.voip"
    ))
    let wire = try XCTUnwrap(authority.current()?.wireValue)
    XCTAssertEqual(Set(wire.keys), [
      "version", "token", "environment", "topic", "capabilityVersion",
      "refreshEpoch", "invalidated",
    ])
    XCTAssertEqual(wire["version"] as? Int, 1)
    XCTAssertEqual(wire["capabilityVersion"] as? Int, 1)
    XCTAssertEqual(wire["token"] as? String, "0a")
  }

  func testCorruptTokenStateCannotBeOverwrittenInvalidatedOrResetToEpochOne() throws {
    let corruptSnapshot = MknoonVoipTokenSnapshot(
      version: 2,
      token: "ab",
      environment: "development",
      topic: "com.mknoon.app.voip",
      capabilityVersion: 1,
      refreshEpoch: 41,
      invalidated: false
    )
    let corruptData = try JSONEncoder().encode(corruptSnapshot)
    let backend = MemoryVoipTokenBackend(data: corruptData)
    let authority = MknoonVoipTokenAuthority(backend: backend)
    var events: [MknoonVoipTokenSnapshot] = []
    authority.setEventHandler { events.append($0) }

    XCTAssertNil(authority.current(), "current() remains wire-compatible for invalid state")
    XCTAssertFalse(authority.update(
      token: Data([0xcd]),
      environment: "development",
      topic: "com.mknoon.app.voip"
    ))
    XCTAssertFalse(authority.invalidate())
    XCTAssertEqual(backend.data, corruptData)
    XCTAssertEqual(backend.replaceCount, 0)
    XCTAssertTrue(events.isEmpty)
    let retainedCorrupt = try JSONDecoder().decode(
      MknoonVoipTokenSnapshot.self,
      from: XCTUnwrap(backend.data)
    )
    XCTAssertEqual(
      retainedCorrupt.refreshEpoch, 41,
      "corrupt durable state must never be replaced by a guessed epoch-one snapshot"
    )
  }

  func testUnreadableTokenStateFailsClosedWithoutWriteOrEvent() throws {
    let backend = MemoryVoipTokenBackend()
    let authority = MknoonVoipTokenAuthority(backend: backend)
    var events: [MknoonVoipTokenSnapshot] = []
    authority.setEventHandler { events.append($0) }
    XCTAssertTrue(authority.update(
      token: Data([0xab]),
      environment: "development",
      topic: "com.mknoon.app.voip"
    ))
    let retained = try XCTUnwrap(backend.data)
    let replaceCount = backend.replaceCount
    events.removeAll()
    backend.failReads = true

    XCTAssertNil(authority.current())
    XCTAssertFalse(authority.update(
      token: Data([0xcd]),
      environment: "development",
      topic: "com.mknoon.app.voip"
    ))
    XCTAssertFalse(authority.invalidate())
    XCTAssertEqual(backend.data, retained)
    XCTAssertEqual(backend.replaceCount, replaceCount)
    XCTAssertTrue(events.isEmpty)
  }

  func testDisabledRegistryTreatsAbsentTokenAsIdempotentButCorruptionAsFailure() throws {
    let absentBackend = MemoryVoipTokenBackend()
    let absentDriver = FakeVoipRegistrationDriver()
    var absentDiagnostics: [MknoonVoipPushDiagnosticEvent] = []
    let absentRegistry = MknoonVoipPushRegistry(
      controller: DeferredIncomingReporter(),
      tokenAuthority: MknoonVoipTokenAuthority(backend: absentBackend),
      capability: RegistryCallCapability(enabled: false),
      registrationDriver: absentDriver,
      diagnosticSink: { absentDiagnostics.append($0) }
    )
    XCTAssertTrue(absentRegistry.applyCapability(false))
    XCTAssertEqual(absentDriver.disableCount, 1)
    XCTAssertEqual(absentBackend.replaceCount, 0)
    XCTAssertEqual(absentDiagnostics, [
      .registration(enabled: false),
      .tokenInvalidation(accepted: true),
    ])

    let corruptData = Data("not-json".utf8)
    let corruptBackend = MemoryVoipTokenBackend(data: corruptData)
    let corruptDriver = FakeVoipRegistrationDriver()
    var corruptDiagnostics: [MknoonVoipPushDiagnosticEvent] = []
    let corruptRegistry = MknoonVoipPushRegistry(
      controller: DeferredIncomingReporter(),
      tokenAuthority: MknoonVoipTokenAuthority(backend: corruptBackend),
      capability: RegistryCallCapability(enabled: false),
      registrationDriver: corruptDriver,
      diagnosticSink: { corruptDiagnostics.append($0) }
    )
    XCTAssertFalse(corruptRegistry.applyCapability(false))
    XCTAssertEqual(corruptDriver.disableCount, 1)
    XCTAssertEqual(corruptBackend.data, corruptData)
    XCTAssertEqual(corruptBackend.replaceCount, 0)
    XCTAssertEqual(corruptDiagnostics, [
      .registration(enabled: false),
      .tokenInvalidation(accepted: false),
    ])
  }

  func testRunnerTokenBackendKeepsDirectoryTraversableAndSnapshotPrivate() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "vc205-token-\(UUID().uuidString)",
      isDirectory: true
    )
    defer { try? FileManager.default.removeItem(at: directory) }
    let authority = MknoonVoipTokenAuthority(
      backend: try RunnerVoipTokenFileBackend(directory: directory)
    )
    XCTAssertTrue(authority.update(
      token: Data([0xab]),
      environment: "development",
      topic: "com.mknoon.app.voip"
    ))
    let directoryAttributes = try FileManager.default.attributesOfItem(atPath: directory.path)
    let fileAttributes = try FileManager.default.attributesOfItem(
      atPath: directory.appendingPathComponent("voip-token-v1.json").path
    )
    XCTAssertEqual((directoryAttributes[.posixPermissions] as? NSNumber)?.intValue, 0o700)
    XCTAssertEqual((fileAttributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    XCTAssertEqual(
      RunnerVoipTokenFileBackend.protectionType,
      .completeUntilFirstUserAuthentication
    )
  }

  func testTokenBridgeReadCurrentAndEventsUseSeparateStrictChannels() throws {
    let backend = MemoryVoipTokenBackend()
    let authority = MknoonVoipTokenAuthority(backend: backend)
    let bridge = MknoonVoipTokenBridge(authority: authority, messenger: nil)
    var empty: Any?
    bridge.handle(
      FlutterMethodCall(methodName: "readCurrent", arguments: ["version": 1])
    ) { empty = $0 }
    XCTAssertNil(empty)

    let delivered = expectation(description: "token event")
    var event: [String: Any]?
    XCTAssertNil(bridge.onListen(withArguments: nil) { value in
      event = value as? [String: Any]
      delivered.fulfill()
    })
    XCTAssertTrue(authority.update(
      token: Data([0xab, 0xcd]),
      environment: "production",
      topic: "com.mknoon.app.voip"
    ))
    wait(for: [delivered], timeout: 1)
    XCTAssertEqual(event?["token"] as? String, "abcd")

    var current: Any?
    bridge.handle(
      FlutterMethodCall(methodName: "readCurrent", arguments: nil)
    ) { current = $0 }
    XCTAssertEqual(current as? NSDictionary, event as? NSDictionary)

    var malformed: Any?
    bridge.handle(
      FlutterMethodCall(methodName: "readCurrent", arguments: ["version": 2])
    ) { malformed = $0 }
    XCTAssertEqual((malformed as? FlutterError)?.code, "bad_args")
    XCTAssertEqual(MknoonVoipTokenBridge.methodChannelName, "mknoon/ios_voip_token")
    XCTAssertEqual(MknoonVoipTokenBridge.eventChannelName, "mknoon/ios_voip_token/events")
  }

  func testTokenBridgeReplaysDurableUpdateThatArrivedBeforeListenExactlyOnce() {
    let authority = MknoonVoipTokenAuthority(backend: MemoryVoipTokenBackend())
    let bridge = MknoonVoipTokenBridge(authority: authority, messenger: nil)
    XCTAssertTrue(authority.update(
      token: Data([0xab]),
      environment: "development",
      topic: "com.mknoon.app.voip"
    ))

    let delivered = expectation(description: "durable token replay")
    delivered.expectedFulfillmentCount = 1
    delivered.assertForOverFulfill = true
    var eventCount = 0
    var event: [String: Any]?
    XCTAssertNil(bridge.onListen(withArguments: nil) { value in
      eventCount += 1
      event = value as? [String: Any]
      delivered.fulfill()
    })

    wait(for: [delivered], timeout: 1)
    XCTAssertEqual(eventCount, 1)
    XCTAssertEqual(event?["token"] as? String, "ab")
    XCTAssertEqual(event?["invalidated"] as? Bool, false)
  }

  func testTokenBridgeLateListenReplaysLatestBeforeLiveRotationInOrder() {
    let authority = MknoonVoipTokenAuthority(backend: MemoryVoipTokenBackend())
    let bridge = MknoonVoipTokenBridge(authority: authority, messenger: nil)
    XCTAssertTrue(authority.update(
      token: Data([0x01]),
      environment: "development",
      topic: "com.mknoon.app.voip"
    ))
    XCTAssertTrue(authority.invalidate())
    var staleRead: [String: Any]?
    bridge.handle(
      FlutterMethodCall(methodName: "readCurrent", arguments: ["version": 1])
    ) { staleRead = $0 as? [String: Any] }
    XCTAssertEqual(staleRead?["refreshEpoch"] as? Int64, 1)
    XCTAssertEqual(staleRead?["invalidated"] as? Bool, true)

    XCTAssertTrue(authority.update(
      token: Data([0x02]),
      environment: "development",
      topic: "com.mknoon.app.voip"
    ))
    let delivered = expectation(description: "replay then live rotation")
    delivered.expectedFulfillmentCount = 2
    delivered.assertForOverFulfill = true
    var events: [[String: Any]] = []
    XCTAssertNil(bridge.onListen(withArguments: nil) { value in
      if let event = value as? [String: Any] { events.append(event) }
      delivered.fulfill()
    })
    XCTAssertTrue(authority.update(
      token: Data([0x03]),
      environment: "development",
      topic: "com.mknoon.app.voip"
    ))

    wait(for: [delivered], timeout: 1)
    XCTAssertEqual(events.compactMap { $0["refreshEpoch"] as? Int64 }, [2, 3])
    XCTAssertEqual(events.compactMap { $0["token"] as? String }, ["02", "03"])
    XCTAssertTrue(events.allSatisfy { $0["invalidated"] as? Bool == false })
  }

  func testPushCompletionComesFromCallKitReportAndNeverWaitsForRuntimeWake() {
    let reporter = DeferredIncomingReporter()
    let authority = MknoonVoipTokenAuthority(backend: MemoryVoipTokenBackend())
    var runtimeWakeCount = 0
    var completionCount = 0
    let registry = MknoonVoipPushRegistry(
      controller: reporter,
      parser: VoipPayloadParser(nowMs: { self.now }),
      tokenAuthority: authority,
      capability: RegistryCallCapability(enabled: true),
      environmentProvider: FixedVoipEnvironment("development"),
      bundleIdentifier: { "com.mknoon.app" },
      runtimeWake: { runtimeWakeCount += 1 }
    )

    registry.handlePush(dictionary: validPayload()) { completionCount += 1 }
    XCTAssertEqual(reporter.payloads.count, 1)
    XCTAssertEqual(reporter.reportPolicies, [.legacyRequired], "legacy delivery must report")
    XCTAssertEqual(runtimeWakeCount, 1)
    XCTAssertEqual(completionCount, 0, "must wait only for CallKit report completion")
    reporter.complete(.presented)
    reporter.complete(.presented)
    XCTAssertEqual(completionCount, 1)
  }

  func testFixedShapeDiagnosticsTraceAcceptedLegacyPushThroughPresentation() {
    let reporter = DeferredIncomingReporter()
    var diagnostics: [MknoonVoipPushDiagnosticEvent] = []
    var completionCount = 0
    let registry = MknoonVoipPushRegistry(
      controller: reporter,
      parser: VoipPayloadParser(nowMs: { self.now }),
      tokenAuthority: MknoonVoipTokenAuthority(backend: MemoryVoipTokenBackend()),
      capability: RegistryCallCapability(enabled: true),
      diagnosticSink: { diagnostics.append($0) }
    )

    registry.handlePush(dictionary: validPayload()) { completionCount += 1 }

    XCTAssertEqual(diagnostics, [
      .delegateEntry(.legacyRequired),
      .capability(enabled: true),
      .parserAccepted,
    ])
    XCTAssertEqual(completionCount, 0)

    reporter.complete(.presented)

    XCTAssertEqual(diagnostics, [
      .delegateEntry(.legacyRequired),
      .capability(enabled: true),
      .parserAccepted,
      .presentation(.presented),
    ])
    XCTAssertEqual(completionCount, 1)
    let output = diagnostics.map(\.logLine).joined(separator: "\n")
    XCTAssertFalse(output.contains(call))
    XCTAssertFalse(output.contains(contact))
    XCTAssertEqual(output, [
      "[MKNOON_PUSHKIT_DIAG] delegate=legacy",
      "[MKNOON_PUSHKIT_DIAG] capability=enabled",
      "[MKNOON_PUSHKIT_DIAG] parser=accepted",
      "[MKNOON_PUSHKIT_DIAG] presentation=presented",
    ].joined(separator: "\n"))
  }

  func testFixedShapeDiagnosticsTraceRejectedMetadataPathsAndComplianceCompletion() {
    let fixtureSecret = "must-never-appear-in-native-diagnostics"
    let malformed: [AnyHashable: Any] = ["secret": fixtureSecret]
    let requiredReporter = DeferredIncomingReporter()
    var requiredDiagnostics: [MknoonVoipPushDiagnosticEvent] = []
    var requiredCompletionCount = 0
    let requiredRegistry = MknoonVoipPushRegistry(
      controller: requiredReporter,
      parser: VoipPayloadParser(nowMs: { self.now }),
      tokenAuthority: MknoonVoipTokenAuthority(backend: MemoryVoipTokenBackend()),
      capability: RegistryCallCapability(enabled: false),
      diagnosticSink: { requiredDiagnostics.append($0) }
    )

    requiredRegistry.handlePush(
      dictionary: malformed,
      reportPolicy: .metadataRequired
    ) { requiredCompletionCount += 1 }

    XCTAssertEqual(requiredDiagnostics, [
      .delegateEntry(.metadataRequired),
      .capability(enabled: false),
      .parserRejected(.invalidShape),
    ])
    XCTAssertEqual(requiredCompletionCount, 0)

    requiredReporter.completeRequiredComplianceReport()

    XCTAssertEqual(requiredDiagnostics, [
      .delegateEntry(.metadataRequired),
      .capability(enabled: false),
      .parserRejected(.invalidShape),
      .complianceCompleted(.metadataRequired),
    ])
    XCTAssertEqual(requiredCompletionCount, 1)

    var optionalDiagnostics: [MknoonVoipPushDiagnosticEvent] = []
    var optionalCompletionCount = 0
    let optionalRegistry = MknoonVoipPushRegistry(
      controller: DeferredIncomingReporter(),
      parser: VoipPayloadParser(nowMs: { self.now }),
      tokenAuthority: MknoonVoipTokenAuthority(backend: MemoryVoipTokenBackend()),
      capability: RegistryCallCapability(enabled: true),
      diagnosticSink: { optionalDiagnostics.append($0) }
    )

    optionalRegistry.handlePush(
      dictionary: malformed,
      reportPolicy: .notRequired
    ) { optionalCompletionCount += 1 }

    XCTAssertEqual(optionalDiagnostics, [
      .delegateEntry(.notRequired),
      .capability(enabled: true),
      .parserRejected(.invalidShape),
      .rejectedWithoutReportCompleted,
    ])
    XCTAssertEqual(optionalCompletionCount, 1)
    let output = (requiredDiagnostics + optionalDiagnostics)
      .map(\.logLine)
      .joined(separator: "\n")
    XCTAssertFalse(output.contains(fixtureSecret))
    XCTAssertFalse(output.contains(call))
    XCTAssertFalse(output.contains(contact))
    XCTAssertTrue(output.contains("delegate=metadata_required"))
    XCTAssertTrue(output.contains("delegate=metadata_not_required"))
  }

  func testFixedShapeDiagnosticsUseExactParserRejectionRawValues() {
    let reasons: [VoipPayloadRejectionReason] = [
      .invalidShape, .duplicateKey, .tooLarge, .malformed, .stale, .tooFarFuture,
    ]

    XCTAssertEqual(
      reasons.map { MknoonVoipPushDiagnosticEvent.parserRejected($0).logLine },
      reasons.map { "[MKNOON_PUSHKIT_DIAG] parser=\($0.rawValue)" }
    )
  }

  func testFixedShapeDiagnosticsUseExactRegistrationAndTokenVocabulary() {
    let events: [MknoonVoipPushDiagnosticEvent] = [
      .registration(enabled: true),
      .registration(enabled: false),
      .tokenUpdate(accepted: true),
      .tokenUpdate(accepted: false),
      .tokenInvalidation(accepted: true),
      .tokenInvalidation(accepted: false),
    ]

    XCTAssertEqual(events.map(\.logLine), [
      "[MKNOON_PUSHKIT_DIAG] registration=enabled",
      "[MKNOON_PUSHKIT_DIAG] registration=disabled",
      "[MKNOON_PUSHKIT_DIAG] token=updated",
      "[MKNOON_PUSHKIT_DIAG] token=update_rejected",
      "[MKNOON_PUSHKIT_DIAG] token=invalidated",
      "[MKNOON_PUSHKIT_DIAG] token=invalidation_rejected",
    ])
  }

  func testCapabilityRegistrationAndTokenUpdateAcceptanceAreObservable() throws {
    let backend = MemoryVoipTokenBackend()
    let authority = MknoonVoipTokenAuthority(backend: backend)
    let capability = RegistryCallCapability(enabled: false)
    let driver = FakeVoipRegistrationDriver()
    var diagnostics: [MknoonVoipPushDiagnosticEvent] = []
    let registry = MknoonVoipPushRegistry(
      controller: DeferredIncomingReporter(),
      tokenAuthority: authority,
      capability: capability,
      registrationDriver: driver,
      environmentProvider: FixedVoipEnvironment("development"),
      bundleIdentifier: { "com.mknoon.app" },
      diagnosticSink: { diagnostics.append($0) }
    )

    capability.enabled = true
    XCTAssertTrue(registry.applyCapability(true))
    XCTAssertTrue(registry.acceptUpdatedVoipToken(Data([0xab])))
    XCTAssertTrue(driver.enabled)
    XCTAssertEqual(authority.current()?.token, "ab")
    XCTAssertEqual(diagnostics, [
      .registration(enabled: true),
      .tokenUpdate(accepted: true),
    ])

    capability.enabled = false
    XCTAssertTrue(registry.applyCapability(false))
    XCTAssertEqual(diagnostics, [
      .registration(enabled: true),
      .tokenUpdate(accepted: true),
      .registration(enabled: false),
      .tokenInvalidation(accepted: true),
    ])
    XCTAssertTrue(try XCTUnwrap(authority.current()).invalidated)
  }

  func testUpdatedVoipTokenRejectsDisabledOrInvalidContextWithoutPersistence() {
    let disabledBackend = MemoryVoipTokenBackend()
    var disabledDiagnostics: [MknoonVoipPushDiagnosticEvent] = []
    let disabledRegistry = MknoonVoipPushRegistry(
      controller: DeferredIncomingReporter(),
      tokenAuthority: MknoonVoipTokenAuthority(backend: disabledBackend),
      capability: RegistryCallCapability(enabled: false),
      environmentProvider: FixedVoipEnvironment("development"),
      bundleIdentifier: { "com.mknoon.app" },
      diagnosticSink: { disabledDiagnostics.append($0) }
    )

    XCTAssertFalse(disabledRegistry.acceptUpdatedVoipToken(Data([0xab])))
    XCTAssertNil(disabledBackend.data)
    XCTAssertEqual(disabledDiagnostics, [.tokenUpdate(accepted: false)])

    let invalidBackend = MemoryVoipTokenBackend()
    var invalidDiagnostics: [MknoonVoipPushDiagnosticEvent] = []
    let invalidRegistry = MknoonVoipPushRegistry(
      controller: DeferredIncomingReporter(),
      tokenAuthority: MknoonVoipTokenAuthority(backend: invalidBackend),
      capability: RegistryCallCapability(enabled: true),
      environmentProvider: FixedVoipEnvironment(nil),
      bundleIdentifier: { "com.mknoon.app" },
      diagnosticSink: { invalidDiagnostics.append($0) }
    )

    XCTAssertFalse(invalidRegistry.acceptUpdatedVoipToken(Data([0xcd])))
    XCTAssertNil(invalidBackend.data)
    XCTAssertEqual(invalidDiagnostics, [.tokenUpdate(accepted: false)])
  }

  func testMustReportFalseInvalidPushCompletesWithoutCallKitOrRuntime() {
    let reporter = DeferredIncomingReporter()
    let authority = MknoonVoipTokenAuthority(backend: MemoryVoipTokenBackend())
    var runtimeWakeCount = 0
    var completionCount = 0
    let registry = MknoonVoipPushRegistry(
      controller: reporter,
      parser: VoipPayloadParser(nowMs: { self.now }),
      tokenAuthority: authority,
      capability: RegistryCallCapability(enabled: true),
      environmentProvider: FixedVoipEnvironment(nil),
      runtimeWake: { runtimeWakeCount += 1 }
    )
    registry.handlePush(
      dictionary: ["v": "1"],
      reportRequired: false
    ) { completionCount += 1 }
    XCTAssertEqual(completionCount, 1)
    XCTAssertTrue(reporter.payloads.isEmpty)
    XCTAssertEqual(reporter.requiredComplianceReportCount, 0)
    XCTAssertEqual(runtimeWakeCount, 0)
  }

  func testRequiredInvalidPushWaitsForEphemeralComplianceReportExactlyOnce() {
    let reporter = DeferredIncomingReporter()
    let registry = MknoonVoipPushRegistry(
      controller: reporter,
      parser: VoipPayloadParser(nowMs: { self.now }),
      tokenAuthority: MknoonVoipTokenAuthority(backend: MemoryVoipTokenBackend()),
      capability: RegistryCallCapability(enabled: true),
      environmentProvider: FixedVoipEnvironment("development")
    )
    var completionCount = 0

    registry.handlePush(
      dictionary: ["v": "1"],
      reportRequired: true
    ) { completionCount += 1 }

    XCTAssertEqual(reporter.requiredComplianceReportCount, 1)
    XCTAssertEqual(reporter.requiredCompliancePolicies, [.metadataRequired])
    XCTAssertTrue(reporter.payloads.isEmpty)
    XCTAssertEqual(completionCount, 0)
    reporter.completeRequiredComplianceReport()
    reporter.completeRequiredComplianceReport()
    XCTAssertEqual(completionCount, 1)
  }

  func testLegacyMalformedPushRoutesLegacyCompliancePolicy() {
    let reporter = DeferredIncomingReporter()
    let registry = MknoonVoipPushRegistry(
      controller: reporter,
      parser: VoipPayloadParser(nowMs: { self.now }),
      tokenAuthority: MknoonVoipTokenAuthority(backend: MemoryVoipTokenBackend()),
      capability: RegistryCallCapability(enabled: true)
    )
    var completionCount = 0

    registry.handlePush(dictionary: ["v": "1"]) { completionCount += 1 }

    XCTAssertEqual(reporter.requiredCompliancePolicies, [.legacyRequired])
    XCTAssertEqual(completionCount, 0)
    reporter.completeRequiredComplianceReport()
    XCTAssertEqual(completionCount, 1)
  }

  func testMustReportFalseRoutesValidRejectedPushWithoutFallbackReport() {
    let reporter = DeferredIncomingReporter()
    let registry = MknoonVoipPushRegistry(
      controller: reporter,
      parser: VoipPayloadParser(nowMs: { self.now }),
      tokenAuthority: MknoonVoipTokenAuthority(backend: MemoryVoipTokenBackend()),
      capability: RegistryCallCapability(enabled: true),
      environmentProvider: FixedVoipEnvironment("development")
    )
    var completionCount = 0

    registry.handlePush(
      dictionary: validPayload(),
      reportRequired: false
    ) { completionCount += 1 }

    XCTAssertEqual(reporter.reportPolicies, [.notRequired])
    XCTAssertEqual(reporter.requiredComplianceReportCount, 0)
    XCTAssertEqual(completionCount, 0)
    reporter.complete(.busy)
    XCTAssertEqual(completionCount, 1)
  }

  func testMetadataRequiredSeamRoutesDistinctRequiredPolicy() {
    let reporter = DeferredIncomingReporter()
    let registry = MknoonVoipPushRegistry(
      controller: reporter,
      parser: VoipPayloadParser(nowMs: { self.now }),
      tokenAuthority: MknoonVoipTokenAuthority(backend: MemoryVoipTokenBackend()),
      capability: RegistryCallCapability(enabled: true)
    )
    var completionCount = 0

    registry.handlePush(
      dictionary: validPayload(),
      reportPolicy: .metadataRequired
    ) { completionCount += 1 }

    XCTAssertEqual(reporter.reportPolicies, [.metadataRequired])
    XCTAssertEqual(completionCount, 0)
    reporter.complete(.busy)
    XCTAssertEqual(completionCount, 1)
  }

  func testPreferredMetadataDelegateSelectorIsImplemented() {
    guard #available(iOS 26.4, *) else { return }
    let registry = MknoonVoipPushRegistry(
      controller: DeferredIncomingReporter(),
      tokenAuthority: MknoonVoipTokenAuthority(backend: MemoryVoipTokenBackend()),
      capability: RegistryCallCapability(enabled: true)
    )
    let selector = #selector(PKPushRegistryDelegate.pushRegistry(
      _:didReceiveIncomingVoIPPushWith:metadata:withCompletionHandler:
    ))
    XCTAssertEqual(
      NSStringFromSelector(selector),
      "pushRegistry:didReceiveIncomingVoIPPushWithPayload:metadata:withCompletionHandler:"
    )
    XCTAssertTrue(registry.responds(to: selector))
  }

  func testPersistedKillSwitchControlsRegistrationInvalidationAndDelivery() throws {
    let reporter = DeferredIncomingReporter()
    let authority = MknoonVoipTokenAuthority(backend: MemoryVoipTokenBackend())
    let capability = RegistryCallCapability(enabled: false)
    let driver = FakeVoipRegistrationDriver()
    var runtimeWakeCount = 0
    let registry = MknoonVoipPushRegistry(
      controller: reporter,
      parser: VoipPayloadParser(nowMs: { self.now }),
      tokenAuthority: authority,
      capability: capability,
      registrationDriver: driver,
      environmentProvider: FixedVoipEnvironment("development"),
      bundleIdentifier: { "com.mknoon.app" },
      runtimeWake: { runtimeWakeCount += 1 }
    )

    XCTAssertTrue(registry.start())
    XCTAssertFalse(driver.enabled)
    XCTAssertEqual(driver.enableCount, 0, "default-false must not register PushKit")

    capability.enabled = true
    XCTAssertTrue(registry.applyCapability(true))
    XCTAssertTrue(driver.enabled)
    XCTAssertEqual(driver.enableCount, 1)
    XCTAssertTrue(authority.update(
      token: Data([0xab]),
      environment: "development",
      topic: "com.mknoon.app.voip"
    ))
    let live = try XCTUnwrap(authority.current())

    capability.enabled = false
    XCTAssertTrue(registry.applyCapability(false))
    XCTAssertFalse(driver.enabled)
    XCTAssertGreaterThanOrEqual(driver.disableCount, 1)
    let invalidated = try XCTUnwrap(authority.current())
    XCTAssertTrue(invalidated.invalidated)
    XCTAssertEqual(invalidated.token, "")
    XCTAssertEqual(invalidated.refreshEpoch, live.refreshEpoch)

    var completionCount = 0
    registry.handlePush(
      dictionary: validPayload(),
      reportRequired: false
    ) { completionCount += 1 }
    XCTAssertEqual(completionCount, 0)
    XCTAssertEqual(reporter.payloads.count, 1)
    XCTAssertEqual(reporter.reportPolicies, [.notRequired])
    XCTAssertEqual(runtimeWakeCount, 0)
    reporter.complete(.disabled)
    XCTAssertEqual(completionCount, 1)

    capability.enabled = true
    XCTAssertTrue(registry.applyCapability(true))
    XCTAssertTrue(driver.enabled)
  }

  private func validPayload() -> [AnyHashable: Any] {
    [
      "aps": ["content-available": 1],
      "v": "1", "w": "call", "c": call, "h": contact,
      "e": String(now + 30_000),
    ]
  }
}

final class MemoryVoipTokenBackend: MknoonVoipTokenBackend {
  var data: Data?
  var failWrites = false
  var failReads = false
  private(set) var replaceCount = 0

  init(data: Data? = nil) {
    self.data = data
  }

  func read() throws -> Data? {
    if failReads { throw CocoaError(.fileReadUnknown) }
    return data
  }
  func replace(with data: Data?) throws {
    if failWrites { throw CocoaError(.fileWriteUnknown) }
    replaceCount += 1
    self.data = data
  }
}

final class DeferredIncomingReporter: MknoonIncomingCallReporting {
  var payloads: [VoipWakePayload] = []
  var reportPolicies: [MknoonVoipPushReportPolicy] = []
  private(set) var requiredComplianceReportCount = 0
  private(set) var requiredCompliancePolicies: [MknoonVoipPushReportPolicy] = []
  private var completion: ((MknoonCallPresentationResult) -> Void)?
  private var requiredComplianceCompletion: (() -> Void)?
  func presentIncoming(
    _ payload: VoipWakePayload,
    reportPolicy: MknoonVoipPushReportPolicy,
    completion: @escaping (MknoonCallPresentationResult) -> Void
  ) {
    payloads.append(payload)
    reportPolicies.append(reportPolicy)
    self.completion = completion
  }
  func satisfyRequiredVoipPushReport(
    reportPolicy: MknoonVoipPushReportPolicy,
    completion: @escaping () -> Void
  ) {
    requiredComplianceReportCount += 1
    requiredCompliancePolicies.append(reportPolicy)
    requiredComplianceCompletion = completion
  }
  func complete(_ result: MknoonCallPresentationResult) { completion?(result) }
  func completeRequiredComplianceReport() { requiredComplianceCompletion?() }
}

struct FixedVoipEnvironment: MknoonVoipEnvironmentProviding {
  let value: String?
  init(_ value: String?) { self.value = value }
  func environment() -> String? { value }
}

final class RegistryCallCapability: NativeCallCapabilityPersisting {
  var enabled: Bool
  init(enabled: Bool) { self.enabled = enabled }
  func setEnabled(_ enabled: Bool) -> Bool {
    self.enabled = enabled
    return true
  }
}

final class FakeVoipRegistrationDriver: MknoonVoipPushRegistrationDriving {
  private(set) var enabled = false
  private(set) var enableCount = 0
  private(set) var disableCount = 0
  weak var delegate: PKPushRegistryDelegate?

  func enable(delegate: PKPushRegistryDelegate) {
    self.delegate = delegate
    enabled = true
    enableCount += 1
  }

  func disable() {
    delegate = nil
    enabled = false
    disableCount += 1
  }
}
