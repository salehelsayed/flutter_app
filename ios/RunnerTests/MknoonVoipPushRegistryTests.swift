import CallKit
import Flutter
import Foundation
import PushKit
import XCTest

@testable import Runner

final class PresentationDiagnosticMemory: MknoonAppDiagnosticBackend, MknoonCallDiagnosticBackend {
  var data: Data?
  var fail = false
  func read() throws -> Data? { data }
  func replace(_ data: Data) throws {
    if fail { throw CocoaError(.fileWriteUnknown) }
    self.data = data
  }
}

final class MknoonVoipPushRegistryTests: XCTestCase {
  private let now: Int64 = 1_900_000_000_000
  private let call = "123e4567-e89b-42d3-a456-426614174000"
  private let contact = "223e4567-e89b-42d3-a456-426614174001"

  func testPresentationResultsReachBothProductionSpoolsTruthfullyAndOnce() throws {
    let cases: [(MknoonCallPresentationResult, String, String, String, String)] = [
      (.presented, "ok", "none", "ok", "none"),
      (.duplicate, "ok", "duplicate", "duplicate", "none"),
      (.busy, "blocked", "authority_rejected", "busy", "busy"),
      (.disabled, "blocked", "authority_rejected", "blocked", "calls_disabled"),
      (.invalid, "rejected", "invalid_request", "rejected", "invalid_request"),
      (.persistenceFailure, "failed", "native_write_failed", "failed", "native_persistence_failed"),
      (.callKitFailure, "failed", "lifecycle_interrupted", "failed", "native_lifecycle_failed"),
    ]
    for (result, appOutcome, appReason, callOutcome, callReason) in cases {
      let app = MknoonAppDiagnosticSpool(backend: PresentationDiagnosticMemory(), now: { self.now })
      let calls = MknoonCallDiagnosticSpool(backend: PresentationDiagnosticMemory(), now: { self.now })
      XCTAssertTrue(app.configure(true, consentEpoch: nil)); XCTAssertTrue(calls.configure(true))
      let reporter = DeferredIncomingReporter()
      var completions = 0
      let registry = MknoonVoipPushRegistry(
        controller: reporter, parser: VoipPayloadParser(nowMs: { self.now }),
        tokenAuthority: MknoonVoipTokenAuthority(backend: MemoryVoipTokenBackend()),
        capability: RegistryCallCapability(enabled: true), diagnosticSink: { _ in },
        appPresentationRecorder: { outcome, reason, values, trace in
          XCTAssertTrue(app.append("push", "presentation", outcome, reason, values: values, traceId: trace))
        },
        callPresentationRecorder: { handle, outcome, reason, context in
          calls.append(handle: handle, stage: "presentation", action: "present", outcome: outcome, reason: reason, context: context)
        })
      registry.handlePush(dictionary: validPayload()) { completions += 1 }
      XCTAssertEqual(completions, 0)
      reporter.complete(result); reporter.complete(result)
      XCTAssertEqual(completions, 1)
      let appEvents = try XCTUnwrap(app.drain()["events"] as? [[String: Any]])
      let callEvents = try XCTUnwrap(calls.drain(64)["events"] as? [[String: Any]])
      XCTAssertEqual(appEvents.count, 1, "duplicate callback must not double-count \(result)")
      XCTAssertEqual(callEvents.count, 1)
      XCTAssertEqual(appEvents.first?["outcome"] as? String, appOutcome)
      XCTAssertEqual(appEvents.first?["reason"] as? String, appReason)
      XCTAssertEqual((appEvents.first?["values"] as? [String: Any])?["committed"] as? Bool, result == .presented)
      XCTAssertEqual(callEvents.first?["outcome"] as? String, callOutcome)
      XCTAssertEqual(callEvents.first?["reason"] as? String, callReason)
    }
  }

  func testCallKitErrorFromRealControllerReachesPushSpoolWithoutPrivateErrorFields() throws {
    let app = MknoonAppDiagnosticSpool(backend: PresentationDiagnosticMemory(), now: { self.now })
    let calls = MknoonCallDiagnosticSpool(backend: PresentationDiagnosticMemory(), now: { self.now })
    XCTAssertTrue(app.configure(true, consentEpoch: nil)); XCTAssertTrue(calls.configure(true))
    let provider = FakeCallProvider()
    provider.delayedReportCompletion = { _ in }
    let store = PendingNativeCallStore(backend: MemoryPendingCallBackend(), nowMs: { self.now })
    let controller = MknoonCallKitController(provider: provider, transactionRequester: FakeCallTransactions(),
      store: store, contacts: OpaqueCallContactResolver(backend: MemoryOpaqueContactBackend(), nowMs: { self.now }),
      audio: FakeCallAudio(), capability: MemoryCallCapability(enabled: true), nowMs: { self.now })
    var completions = 0
    let registry = MknoonVoipPushRegistry(controller: controller,
      parser: VoipPayloadParser(nowMs: { self.now }),
      tokenAuthority: MknoonVoipTokenAuthority(backend: MemoryVoipTokenBackend()),
      capability: RegistryCallCapability(enabled: true), diagnosticSink: { _ in },
      appPresentationRecorder: { outcome, reason, values, trace in
        XCTAssertTrue(app.append("push", "presentation", outcome, reason, values: values, traceId: trace))
      }, callPresentationRecorder: { handle, outcome, reason, context in
        calls.append(handle: handle, stage: "presentation", action: "present", outcome: outcome, reason: reason, context: context)
      })
    registry.handlePush(dictionary: validPayload()) { completions += 1 }
    XCTAssertEqual(completions, 0)
    provider.delayedReportCompletion?(NSError(domain: CXErrorDomainIncomingCall, code: 3,
      userInfo: [NSLocalizedDescriptionKey: "private-error-text"]))
    XCTAssertEqual(completions, 1)
    XCTAssertEqual(store.snapshot()?.terminalEvent?.type, .nativeFailure)
    XCTAssertEqual(provider.endReports.count, 1)
    let appEvent = try XCTUnwrap((app.drain()["events"] as? [[String: Any]])?.first)
    XCTAssertEqual(appEvent["reason"] as? String, "prepare_failed")
    let values = try XCTUnwrap(appEvent["values"] as? [String: Any])
    XCTAssertEqual(values["osReasonCode"] as? Int64, 3)
    XCTAssertEqual(values["errorClass"] as? String, "platform")
    let callEvent = try XCTUnwrap((calls.drain(64)["events"] as? [[String: Any]])?.first)
    XCTAssertEqual(callEvent["reason"] as? String, "provider_error")
    let encoded = String(decoding: try JSONSerialization.data(withJSONObject: [appEvent, callEvent]), as: UTF8.self)
    for secret in ["private-error-text", CXErrorDomainIncomingCall, call, contact] { XCTAssertFalse(encoded.contains(secret)) }
    XCTAssertTrue(MknoonCallDiagnosticScope.current.isEmpty)
  }

  func testDisabledOrFailingDiagnosticSpoolsDoNotChangePushCompletion() {
    for enabled in [false, true] {
      let appMemory = PresentationDiagnosticMemory(), callMemory = PresentationDiagnosticMemory()
      let app = MknoonAppDiagnosticSpool(backend: appMemory, now: { self.now })
      let calls = MknoonCallDiagnosticSpool(backend: callMemory, now: { self.now })
      if enabled {
        XCTAssertTrue(app.configure(true, consentEpoch: nil)); XCTAssertTrue(calls.configure(true))
        appMemory.fail = true; callMemory.fail = true
      }
      let reporter = DeferredIncomingReporter()
      var completions = 0
      let registry = MknoonVoipPushRegistry(controller: reporter,
        parser: VoipPayloadParser(nowMs: { self.now }),
        tokenAuthority: MknoonVoipTokenAuthority(backend: MemoryVoipTokenBackend()),
        capability: RegistryCallCapability(enabled: true), diagnosticSink: { _ in },
        appPresentationRecorder: { outcome, reason, values, trace in
          _ = app.append("push", "presentation", outcome, reason, values: values, traceId: trace)
        }, callPresentationRecorder: { handle, outcome, reason, context in
          calls.append(handle: handle, stage: "presentation", action: "present", outcome: outcome, reason: reason, context: context)
        })
      registry.handlePush(dictionary: validPayload()) { completions += 1 }
      reporter.complete(.presented)
      XCTAssertEqual(completions, 1)
    }
  }

  func testColdDisabledLaunchKeepsMandatoryPushReceiverWithoutTokenPublication() throws {
    let driver = FakeVoipRegistrationDriver()
    let backend = MemoryVoipTokenBackend()
    let reporter = DeferredIncomingReporter()
    var runtimeWakeCount = 0
    let registry = MknoonVoipPushRegistry(
      controller: reporter,
      parser: VoipPayloadParser(nowMs: { self.now }),
      tokenAuthority: MknoonVoipTokenAuthority(backend: backend),
      capability: RegistryCallCapability(enabled: false),
      registrationDriver: driver,
      runtimeWake: { runtimeWakeCount += 1 }
    )

    XCTAssertTrue(registry.start())
    XCTAssertTrue(driver.delegate === registry,
                  "a PushKit launch needs its receiver even when calls were disabled")
    XCTAssertTrue(driver.enabled)
    XCTAssertFalse(registry.acceptUpdatedVoipToken(Data([0xab])))
    XCTAssertNil(backend.data)
    var completions = 0
    XCTAssertTrue(driver.deliverMandatoryPush(validPayload()) { completions += 1 })
    XCTAssertTrue(reporter.payloads.isEmpty)
    XCTAssertEqual(reporter.requiredCompliancePolicies, [.legacyRequired])
    XCTAssertEqual(completions, 0)
    XCTAssertEqual(runtimeWakeCount, 0)
    reporter.completeRequiredComplianceReport()
    XCTAssertEqual(completions, 1)
  }

  func testDisableRetainsQueuedMandatoryPushReceiverAndReenableRestoresCachedToken() throws {
    let driver = FakeVoipRegistrationDriver()
    let capability = RegistryCallCapability(enabled: true)
    let authority = MknoonVoipTokenAuthority(backend: MemoryVoipTokenBackend())
    let reporter = DeferredIncomingReporter()
    let registry = MknoonVoipPushRegistry(
      controller: reporter,
      parser: VoipPayloadParser(nowMs: { self.now }),
      tokenAuthority: authority,
      capability: capability,
      registrationDriver: driver,
      environmentProvider: FixedVoipEnvironment("development"),
      bundleIdentifier: { "com.mknoon.app" }
    )
    XCTAssertTrue(registry.start())
    XCTAssertTrue(registry.acceptUpdatedVoipToken(Data([0xab])))
    capability.enabled = false
    XCTAssertTrue(registry.applyCapability(false))
    XCTAssertTrue(driver.delegate === registry,
                  "capability withdrawal must not remove a queued push's callback")
    XCTAssertEqual(driver.disableCount, 0)
    XCTAssertTrue(try XCTUnwrap(authority.current()).invalidated)
    var completions = 0
    XCTAssertTrue(driver.deliverMandatoryPush(validPayload()) { completions += 1 })
    XCTAssertTrue(reporter.payloads.isEmpty)
    XCTAssertEqual(reporter.requiredCompliancePolicies, [.legacyRequired])
    reporter.completeRequiredComplianceReport()
    XCTAssertEqual(completions, 1)
    driver.cachedToken = Data([0xab])
    capability.enabled = true
    XCTAssertTrue(registry.applyCapability(true))
    XCTAssertFalse(try XCTUnwrap(authority.current()).invalidated,
                   "an unchanged OS token may not generate another callback")
    XCTAssertEqual(authority.current()?.token, "ab")
  }

  func testRequestedDisableRejectsLateAdmissionAndTokenWhenDurableCapabilityStaysEnabled() throws {
    let driver = FakeVoipRegistrationDriver()
    let capability = RegistryCallCapability(enabled: true)
    let authority = MknoonVoipTokenAuthority(backend: MemoryVoipTokenBackend())
    let reporter = DeferredIncomingReporter()
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
    XCTAssertTrue(registry.acceptUpdatedVoipToken(Data([0xab])))
    // The controller invokes the handler before persistence, and a failed
    // persistence write leaves this durable getter true.
    XCTAssertTrue(registry.applyCapability(false))
    XCTAssertTrue(capability.enabled)
    XCTAssertTrue(registry.start(), "restarting delivery must preserve the requested-disable latch")
    XCTAssertFalse(registry.acceptUpdatedVoipToken(Data([0xcd])))
    XCTAssertTrue(try XCTUnwrap(authority.current()).invalidated)
    var completions = 0
    XCTAssertTrue(driver.deliverMandatoryPush(validPayload()) { completions += 1 })
    XCTAssertTrue(reporter.payloads.isEmpty, "late push must not reach admission")
    XCTAssertEqual(reporter.requiredCompliancePolicies, [.legacyRequired])
    XCTAssertEqual(runtimeWakeCount, 0)
    XCTAssertEqual(completions, 0)
    reporter.completeRequiredComplianceReport()
    XCTAssertEqual(completions, 1)
  }

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
    XCTAssertEqual(absentDriver.disableCount, 0)
    XCTAssertTrue(absentDriver.enabled)
    XCTAssertEqual(absentBackend.replaceCount, 0)
    XCTAssertEqual(absentDiagnostics, [
      .registration(enabled: true),
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
    XCTAssertEqual(corruptDriver.disableCount, 0)
    XCTAssertTrue(corruptDriver.enabled)
    XCTAssertEqual(corruptBackend.data, corruptData)
    XCTAssertEqual(corruptBackend.replaceCount, 0)
    XCTAssertEqual(corruptDiagnostics, [
      .registration(enabled: true),
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

  func testAdvanceRefreshEpochRotatesOnlyTheExpectedEpochAndPersists() throws {
    let backend = MemoryVoipTokenBackend()
    let authority = MknoonVoipTokenAuthority(backend: backend)
    var events: [MknoonVoipTokenSnapshot] = []
    authority.setEventHandler { events.append($0) }
    XCTAssertTrue(authority.update(
      token: Data([0x01, 0xab]),
      environment: "development",
      topic: "com.mknoon.app.voip"
    ))
    XCTAssertEqual(events.count, 1)

    let advanced = try XCTUnwrap(authority.advanceRefreshEpoch(expected: 1, minimum: 0))
    XCTAssertEqual(advanced.refreshEpoch, 2)
    XCTAssertEqual(advanced.token, "01ab")
    XCTAssertEqual(advanced.environment, "development")
    XCTAssertFalse(advanced.invalidated)
    XCTAssertEqual(events.count, 2)
    XCTAssertEqual(MknoonVoipTokenAuthority(backend: backend).current(), advanced)

    // A stale expectation changes nothing and emits nothing.
    XCTAssertNil(authority.advanceRefreshEpoch(expected: 1, minimum: 0))
    XCTAssertEqual(authority.current()?.refreshEpoch, 2)
    XCTAssertEqual(events.count, 2)

    // The minimum lets one advance jump past a relay high-water it cannot see.
    let jumped = try XCTUnwrap(authority.advanceRefreshEpoch(expected: 2, minimum: 1_900_000_000))
    XCTAssertEqual(jumped.refreshEpoch, 1_900_000_000)
    XCTAssertEqual(events.count, 3)

    XCTAssertTrue(authority.invalidate())
    XCTAssertNil(authority.advanceRefreshEpoch(expected: 1_900_000_000, minimum: 0))
    XCTAssertEqual(authority.current()?.refreshEpoch, 1_900_000_000)

    let durabilityBackend = MemoryVoipTokenBackend()
    let durability = MknoonVoipTokenAuthority(backend: durabilityBackend)
    XCTAssertTrue(durability.update(
      token: Data([0x02]),
      environment: "production",
      topic: "com.mknoon.app.voip"
    ))
    durabilityBackend.failWrites = true
    XCTAssertNil(durability.advanceRefreshEpoch(expected: 1, minimum: 0))
    XCTAssertEqual(durability.current()?.refreshEpoch, 1)
  }

  func testTokenBridgeAdvanceRefreshEpochUsesStrictArgumentsAndReportsRefusal() throws {
    let backend = MemoryVoipTokenBackend()
    let authority = MknoonVoipTokenAuthority(backend: backend)
    let bridge = MknoonVoipTokenBridge(
      authority: authority,
      messenger: nil,
      now: { Date(timeIntervalSince1970: 1_900_000_000) }
    )
    XCTAssertTrue(authority.update(
      token: Data([0xab, 0xcd]),
      environment: "production",
      topic: "com.mknoon.app.voip"
    ))

    var advanced: Any?
    bridge.handle(
      FlutterMethodCall(
        methodName: "advanceRefreshEpoch",
        arguments: ["version": 1, "expectedRefreshEpoch": 1]
      )
    ) { advanced = $0 }
    let snapshot = try XCTUnwrap(advanced as? [String: Any])
    XCTAssertEqual(snapshot["refreshEpoch"] as? Int64, 1_900_000_000)
    XCTAssertEqual(snapshot["token"] as? String, "abcd")
    XCTAssertEqual(snapshot["invalidated"] as? Bool, false)
    XCTAssertEqual(authority.current()?.refreshEpoch, 1_900_000_000)

    var refused: Any?
    bridge.handle(
      FlutterMethodCall(
        methodName: "advanceRefreshEpoch",
        arguments: ["version": 1, "expectedRefreshEpoch": 1]
      )
    ) { refused = $0 }
    XCTAssertEqual((refused as? FlutterError)?.code, "epoch_advance_refused")
    XCTAssertEqual(authority.current()?.refreshEpoch, 1_900_000_000)

    for arguments in [
      ["version": 1] as [String: Any],
      ["version": 2, "expectedRefreshEpoch": 1_900_000_000],
      ["version": 1, "expectedRefreshEpoch": 0],
      ["version": 1, "expectedRefreshEpoch": "1"],
    ] {
      var malformed: Any?
      bridge.handle(
        FlutterMethodCall(methodName: "advanceRefreshEpoch", arguments: arguments)
      ) { malformed = $0 }
      XCTAssertEqual((malformed as? FlutterError)?.code, "bad_args", "\(arguments)")
    }
    XCTAssertEqual(authority.current()?.refreshEpoch, 1_900_000_000)
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
      .registration(enabled: true),
      .tokenInvalidation(accepted: true),
    ])
    XCTAssertTrue(try XCTUnwrap(authority.current()).invalidated)
    XCTAssertEqual(authority.current()?.invalidationReason, .callsDisabled)
    XCTAssertNotNil(authority.current()?.operationId)
  }

  func testPushKitInvalidationRetainsItsDistinctOriginAcrossRestart() throws {
    let backend = MemoryVoipTokenBackend()
    let authority = MknoonVoipTokenAuthority(backend: backend)
    XCTAssertTrue(authority.update(token: Data([0xab]), environment: "development", topic: "com.mknoon.app.voip"))
    let registry = MknoonVoipPushRegistry(controller: DeferredIncomingReporter(), tokenAuthority: authority,
                                         capability: RegistryCallCapability(enabled: true),
                                         registrationDriver: FakeVoipRegistrationDriver())
    registry.pushRegistry(PKPushRegistry(queue: .main), didInvalidatePushTokenFor: .voIP)
    let retained = try XCTUnwrap(MknoonVoipTokenAuthority(backend: backend).current())
    XCTAssertEqual(retained.invalidationReason, .pushkitTokenInvalidated)
    XCTAssertNotNil(retained.operationId)
    XCTAssertEqual(retained.token, "")
  }

  func testOptionalDiagnosticCorruptionDoesNotRejectValidTokenSnapshot() throws {
    let data = try JSONSerialization.data(withJSONObject: [
      "version": 1, "token": "ab", "environment": "development", "topic": "com.mknoon.app.voip",
      "capabilityVersion": 1, "refreshEpoch": 1, "invalidated": false,
      "invalidationReason": ["private": "malformed"], "operationId": 42,
      "parentOperationId": "not-a-uuid",
    ])
    let snapshot = try JSONDecoder().decode(MknoonVoipTokenSnapshot.self, from: data)
    XCTAssertEqual(snapshot.token, "ab")
    XCTAssertNil(snapshot.invalidationReason); XCTAssertNil(snapshot.operationId); XCTAssertNil(snapshot.parentOperationId)
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

  func testEntitlementProviderPrefersEmbeddedProfileApsEnvironment() {
    let development = Self.embeddedProfile(apsEnvironment: "development")
    XCTAssertEqual(
      EntitlementVoipEnvironmentProvider(
        infoPlistValue: { "production" }, embeddedProfile: { development }
      ).environment(),
      "development"
    )
    let production = Self.embeddedProfile(apsEnvironment: "production")
    XCTAssertEqual(
      EntitlementVoipEnvironmentProvider(
        infoPlistValue: { "development" }, embeddedProfile: { production }
      ).environment(),
      "production"
    )
    XCTAssertEqual(EntitlementVoipEnvironmentProvider.embeddedProfileFileName, "embedded.mobileprovision")
  }

  func testEntitlementProviderFallsBackToInfoPlistWithoutEmbeddedProfile() {
    XCTAssertEqual(
      EntitlementVoipEnvironmentProvider(
        infoPlistValue: { "production" }, embeddedProfile: { nil }
      ).environment(),
      "production"
    )
    XCTAssertEqual(
      EntitlementVoipEnvironmentProvider(
        infoPlistValue: { "development" }, embeddedProfile: { Data("not a profile".utf8) }
      ).environment(),
      "development"
    )
    let unknown = Self.embeddedProfile(apsEnvironment: "staging")
    XCTAssertEqual(
      EntitlementVoipEnvironmentProvider(
        infoPlistValue: { "production" }, embeddedProfile: { unknown }
      ).environment(),
      "production"
    )
    XCTAssertNil(
      EntitlementVoipEnvironmentProvider(
        infoPlistValue: { "staging" }, embeddedProfile: { nil }
      ).environment()
    )
    XCTAssertNil(
      EntitlementVoipEnvironmentProvider(
        infoPlistValue: { nil }, embeddedProfile: { Data("<plist".utf8) }
      ).environment()
    )
  }

  private static func embeddedProfile(apsEnvironment: String) -> Data {
    let plist = """
      <?xml version="1.0" encoding="UTF-8"?>
      <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
      <plist version="1.0">
      <dict>
        <key>Entitlements</key>
        <dict>
          <key>aps-environment</key>
          <string>\(apsEnvironment)</string>
        </dict>
        <key>Name</key>
        <string>fixture profile</string>
      </dict>
      </plist>
      """
    var data = Data([0x30, 0x82, 0x01, 0x02, 0x06, 0x09])
    data.append(Data(plist.utf8))
    data.append(Data([0x00, 0xff, 0x10]))
    return data
  }

  func testPersistedKillSwitchPreservesReceiverButControlsInvalidationAndDelivery() throws {
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
    XCTAssertTrue(driver.enabled)
    XCTAssertEqual(driver.enableCount, 1, "disabled cold launch must retain required-push reporting")

    capability.enabled = true
    XCTAssertTrue(registry.applyCapability(true))
    XCTAssertTrue(driver.enabled)
    XCTAssertEqual(driver.enableCount, 2)
    XCTAssertTrue(authority.update(
      token: Data([0xab]),
      environment: "development",
      topic: "com.mknoon.app.voip"
    ))
    let live = try XCTUnwrap(authority.current())

    capability.enabled = false
    XCTAssertTrue(registry.applyCapability(false))
    XCTAssertTrue(driver.enabled)
    XCTAssertEqual(driver.disableCount, 0)
    let invalidated = try XCTUnwrap(authority.current())
    XCTAssertTrue(invalidated.invalidated)
    XCTAssertEqual(invalidated.token, "")
    XCTAssertEqual(invalidated.refreshEpoch, live.refreshEpoch)

    var completionCount = 0
    registry.handlePush(
      dictionary: validPayload(),
      reportRequired: false
    ) { completionCount += 1 }
    XCTAssertEqual(completionCount, 1)
    XCTAssertTrue(reporter.payloads.isEmpty)
    XCTAssertTrue(reporter.reportPolicies.isEmpty)
    XCTAssertEqual(reporter.requiredComplianceReportCount, 0)
    XCTAssertEqual(runtimeWakeCount, 0)
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
  var cachedToken: Data?

  func deliverMandatoryPush(_ payload: [AnyHashable: Any], completion: @escaping () -> Void) -> Bool {
    guard enabled, let receiver = delegate as? MknoonVoipPushRegistry else { return false }
    receiver.handlePush(dictionary: payload, reportPolicy: .legacyRequired, completion: completion)
    return true
  }

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
