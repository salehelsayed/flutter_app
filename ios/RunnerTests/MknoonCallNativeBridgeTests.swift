import CallKit
import Flutter
import Foundation
import XCTest

@testable import Runner

final class MknoonCallNativeBridgeTests: XCTestCase {
  private let now: Int64 = 1_900_000_000_000
  private let callId = UUID(uuidString: "123e4567-e89b-42d3-a456-426614174000")!

  func testColdAttachUsesExactCompatibilityEnvelope() throws {
    let rig = makeBridgeRig()
    let bridge = MknoonCallNativeBridge(controller: rig.controller, messenger: nil)
    let value = invoke(bridge, "attach", ["version": 1])
    let envelope = try XCTUnwrap(value as? [String: Any])
    XCTAssertEqual(Set(envelope.keys), [
      "version", "descriptor", "events", "nativeCallId", "highestSequence",
    ])
    XCTAssertEqual(envelope["version"] as? Int, 1)
    XCTAssertTrue(envelope["descriptor"] is NSNull)
    XCTAssertTrue(envelope["nativeCallId"] is NSNull)
    XCTAssertEqual((envelope["events"] as? [[String: Any]])?.count, 0)
    XCTAssertEqual(envelope["highestSequence"] as? Int64, 0)
  }

  func testAttachReturnsExactDescriptorAndOrderedEventsWithoutConsuming() throws {
    let rig = makeBridgeRig()
    var presented: MknoonCallPresentationResult?
    rig.controller.presentIncoming(payload()) { presented = $0 }
    XCTAssertEqual(presented, .presented)
    XCTAssertTrue(rig.controller.handleAnswer(callId))
    let bridge = MknoonCallNativeBridge(controller: rig.controller, messenger: nil)

    let first = try XCTUnwrap(invoke(bridge, "attach", nil) as? [String: Any])
    let second = try XCTUnwrap(invoke(bridge, "attach", ["version": 1]) as? [String: Any])
    XCTAssertEqual(first as NSDictionary, second as NSDictionary)
    let descriptor = try XCTUnwrap(first["descriptor"] as? [String: Any])
    XCTAssertEqual(Set(descriptor.keys), [
      "callHandle", "expiresAtMs", "direction", "phase", "presented",
    ])
    XCTAssertEqual(descriptor["direction"] as? String, "incoming")
    XCTAssertEqual(descriptor["phase"] as? String, "preStart")
    XCTAssertEqual(descriptor["presented"] as? Bool, true)
    let events = try XCTUnwrap(first["events"] as? [[String: Any]])
    XCTAssertEqual(events.map { $0["type"] as? String }, ["presented", "answer"])
    XCTAssertEqual(events.map { $0["sequence"] as? Int64 }, [1, 2])
    XCTAssertEqual(rig.backend.deleteCount, 0)
  }

  func testAttachPreservesDistinctPresentedAndAnswerOccurrenceTimes() throws {
    let presentedAtMs = now
    var clock = presentedAtMs
    let answerAtMs = now + 4_321
    let rig = makeBridgeRig(nowMs: { clock })
    rig.controller.presentIncoming(payload()) { _ in }
    clock = answerAtMs
    XCTAssertTrue(rig.controller.handleAnswer(callId))
    let bridge = MknoonCallNativeBridge(controller: rig.controller, messenger: nil)

    XCTAssertEqual(rig.store.snapshot()?.receivedAtMs, presentedAtMs)
    let envelope = try XCTUnwrap(invoke(bridge, "attach", nil) as? [String: Any])
    let events = try XCTUnwrap(envelope["events"] as? [[String: Any]])
    XCTAssertEqual(events.map { $0["type"] as? String }, ["presented", "answer"])
    XCTAssertEqual(
      events.map { $0["occurredAtMs"] as? Int64 },
      [presentedAtMs, answerAtMs]
    )
  }

  func testAdoptAcknowledgeAndTerminalDeleteUseDartHandleSchema() throws {
    let rig = makeBridgeRig()
    rig.controller.presentIncoming(payload()) { _ in }
    let bridge = MknoonCallNativeBridge(controller: rig.controller, messenger: nil)
    let handle = callId.uuidString.lowercased()
    XCTAssertEqual(invoke(bridge, "adopt", identity(handle)) as? Bool, true)
    XCTAssertEqual(invoke(bridge, "acknowledge", [
      "version": 1,
      "callHandle": handle,
      "throughSequence": Int64(1),
      "disposition": "ADOPTED",
    ]) as? Bool, true)
    XCTAssertEqual(rig.store.snapshot()?.phase, .journal)
    XCTAssertEqual(invoke(bridge, "end", identity(handle)) as? Bool, true)
    let high = try XCTUnwrap(rig.store.snapshot()?.highestSequence)
    XCTAssertEqual(invoke(bridge, "acknowledge", [
      "version": 1,
      "callHandle": handle,
      "throughSequence": high,
      "disposition": "TERMINAL",
    ]) as? Bool, true)
    XCTAssertNil(rig.store.snapshot())
    XCTAssertEqual(rig.backend.deleteCount, 1)
  }

  func testMalformedCallsReturnFixedBadArgsWithoutMutation() {
    let rig = makeBridgeRig()
    let bridge = MknoonCallNativeBridge(controller: rig.controller, messenger: nil)
    let malformed: [(String, Any?)] = [
      ("setCapabilityEnabled", ["version": 2, "enabled": true]),
      ("attach", ["extra": true]),
      ("adopt", ["version": 1, "callHandle": "not-a-call"]),
      ("presentAuthenticated", ["version": 1, "callHandle": 1, "expiresAtMs": 1]),
      ("registerOutgoingAuthenticated", ["version": 1]),
      ("acknowledge", ["version": 1]),
      ("end", ["version": 1]),
      ("authenticationFailed", ["version": 1]),
      ("remoteCancel", ["version": 1, "callHandle": 1]),
      ("expire", ["version": 1, "callHandle": "not-a-call"]),
      ("updateAuthenticatedContact", [
        "version": 1, "callHandle": callId.uuidString.lowercased(), "displayName": 1,
      ]),
      ("revokeOpaqueContact", [
        "version": 1, "callHandle": callId.uuidString.lowercased(), "opaqueHandle": "x",
      ]),
      ("publishOpaqueContact", [
        "version": 1, "wakeHandle": "223E4567E89B42D3A456426614174001",
        "displayName": "Alice",
      ]),
      ("publishOpaqueContact", [
        "version": 1, "wakeHandle": "223e4567e89b42d3a456426614174001",
        "displayName": " Alice ",
      ]),
      ("publishOpaqueContact", [
        "version": 1, "wakeHandle": "223e4567e89b42d3a456426614174001",
        "displayName": "Alice", "callHandle": callId.uuidString.lowercased(),
      ]),
      ("revokeOpaqueContactHandle", [
        "version": 1, "wakeHandle": "223e4567-e89b-42d3-7456-426614174001",
      ]),
      ("revokeOpaqueContactHandle", [
        "version": 1, "wakeHandle": "223e4567e89b42d3a456426614174001", "extra": true,
      ]),
      ("project", ["version": 1]),
      ("readAudioState", nil),
      ("requestRoute", ["version": 1]),
      ("activateAudio", ["version": true, "callHandle": "x"]),
      ("deactivateAudio", ["version": 1, "callHandle": 1]),
      ("failClosed", ["version": 1, "extra": true]),
      ("detach", ["version": 1, "extra": true]),
    ]
    for (method, arguments) in malformed {
      let value = invoke(bridge, method, arguments)
      let error = value as? FlutterError
      XCTAssertEqual(error?.code, "bad_args", method)
      XCTAssertNil(error?.details, method)
    }
    XCTAssertNil(rig.store.snapshot())
    XCTAssertTrue(rig.capability.enabled)
  }

  func testAuthenticatedPresentationBridgeToleratesPeerClockSkewAndBoundsExpiry() {
    let rig = makeBridgeRig()
    let bridge = MknoonCallNativeBridge(controller: rig.controller, messenger: nil)
    let handle = callId.uuidString.lowercased()

    XCTAssertEqual(invoke(bridge, "presentAuthenticated", [
      "version": 1,
      "callHandle": handle,
      "expiresAtMs": now + VoipPayloadParser.maxFutureSkewMs + 1_000,
    ]) as? Bool, true)
    XCTAssertEqual(rig.provider.incomingReports.map(\.0), [callId])
    XCTAssertEqual(
      rig.store.snapshot()?.expiresAtMs,
      now + VoipPayloadParser.maxFutureSkewMs
    )
  }

  func testAuthenticatedPresentationBridgeRejectsBeyondPeerClockSkewBudget() {
    let rig = makeBridgeRig()
    let bridge = MknoonCallNativeBridge(controller: rig.controller, messenger: nil)
    let handle = callId.uuidString.lowercased()

    XCTAssertEqual(invoke(bridge, "presentAuthenticated", [
      "version": 1,
      "callHandle": handle,
      "expiresAtMs": now
        + VoipPayloadParser.maxFutureSkewMs
        + MknoonCallKitController.authenticatedPeerClockSkewMs
        + 1,
    ]) as? Bool, false)
    XCTAssertTrue(rig.provider.incomingReports.isEmpty)
    XCTAssertNil(rig.store.snapshot())
  }

  func testOpaqueContactPublicationAndRevocationDoNotRequireCallDescriptor() {
    let rig = makeBridgeRig()
    let bridge = MknoonCallNativeBridge(controller: rig.controller, messenger: nil)
    let compactHandle = "223e4567e89b42d3a456426614174001"
    let uuidHandle = "323e4567-e89b-42d3-a456-426614174002"
    XCTAssertNil(rig.store.snapshot())

    XCTAssertEqual(invoke(bridge, "publishOpaqueContact", [
      "version": 1,
      "wakeHandle": compactHandle,
      "displayName": "Alice",
    ]) as? Bool, true)
    XCTAssertEqual(rig.contacts.displayName(for: compactHandle), "Alice")
    XCTAssertNil(rig.store.snapshot())

    XCTAssertEqual(invoke(bridge, "publishOpaqueContact", [
      "version": 1,
      "wakeHandle": uuidHandle,
      "displayName": "Alice Device",
    ]) as? Bool, true)
    XCTAssertEqual(rig.contacts.displayName(for: uuidHandle), "Alice Device")
    XCTAssertNil(rig.store.snapshot())

    XCTAssertEqual(invoke(bridge, "revokeOpaqueContactHandle", [
      "version": 1,
      "wakeHandle": compactHandle,
    ]) as? Bool, true)
    XCTAssertEqual(
      rig.contacts.displayName(for: compactHandle),
      OpaqueCallContactResolver.genericDisplayName
    )
    XCTAssertEqual(rig.contacts.displayName(for: uuidHandle), "Alice Device")
    XCTAssertNil(rig.store.snapshot())
  }

  func testPrivacySafeContactAndTerminalMethodsUseExactCallHandleMaps() throws {
    let contactRig = makeBridgeRig()
    contactRig.controller.presentIncoming(payload()) { _ in }
    let contactBridge = MknoonCallNativeBridge(controller: contactRig.controller, messenger: nil)
    let handle = callId.uuidString.lowercased()
    XCTAssertEqual(invoke(contactBridge, "acknowledge", [
      "version": 1,
      "callHandle": handle,
      "throughSequence": Int64(1),
      "disposition": "ADOPTED",
    ]) as? Bool, true)
    XCTAssertEqual(invoke(contactBridge, "updateAuthenticatedContact", [
      "version": 1,
      "callHandle": handle,
      "displayName": "Alice",
    ]) as? Bool, true)
    XCTAssertEqual(contactRig.provider.updates.last?.1.localizedCallerName, "Alice")
    XCTAssertEqual(invoke(contactBridge, "revokeOpaqueContact", identity(handle)) as? Bool, true)
    XCTAssertEqual(
      contactRig.contacts.displayName(for: "223e4567-e89b-42d3-a456-426614174001"),
      OpaqueCallContactResolver.genericDisplayName
    )

    let authentication = makeBridgeRig()
    XCTAssertTrue(authentication.contacts.updateVerified(
      handle: "223e4567-e89b-42d3-a456-426614174001",
      displayName: "Alice"
    ))
    authentication.controller.presentIncoming(payload()) { _ in }
    let authenticationBridge = MknoonCallNativeBridge(
      controller: authentication.controller,
      messenger: nil
    )
    XCTAssertEqual(
      invoke(authenticationBridge, "authenticationFailed", identity(handle)) as? Bool,
      true
    )
    XCTAssertEqual(authentication.store.snapshot()?.terminalEvent?.type, .nativeFailure)
    XCTAssertEqual(authentication.provider.endReports.last?.1, .failed)
    XCTAssertEqual(
      authentication.contacts.displayName(for: "223e4567-e89b-42d3-a456-426614174001"),
      OpaqueCallContactResolver.genericDisplayName
    )

    let remote = makeBridgeRig()
    remote.controller.presentIncoming(payload()) { _ in }
    let remoteBridge = MknoonCallNativeBridge(controller: remote.controller, messenger: nil)
    XCTAssertEqual(invoke(remoteBridge, "remoteCancel", identity(handle)) as? Bool, true)
    XCTAssertEqual(remote.store.snapshot()?.terminalEvent?.type, .remoteCancelled)
    // Cancelling this still-unanswered presentation must record a missed call.
    XCTAssertEqual(remote.provider.endReports.last?.1, .unanswered)

    let expired = makeBridgeRig()
    expired.controller.presentIncoming(payload()) { _ in }
    let expiredBridge = MknoonCallNativeBridge(controller: expired.controller, messenger: nil)
    XCTAssertEqual(invoke(expiredBridge, "expire", identity(handle)) as? Bool, true)
    XCTAssertEqual(expired.store.snapshot()?.terminalEvent?.type, .expired)
    XCTAssertEqual(expired.provider.endReports.last?.1, .unanswered)
  }

  func testProjectMapsEndedDeclinedAndFailedToDistinctTerminalReasons() {
    let cases: [(String, PendingNativeCallEventType, CXCallEndedReason)] = [
      ("ended", .endRequested, .remoteEnded),
      ("declined", .declineRequested, .declinedElsewhere),
      ("failed", .nativeFailure, .failed),
    ]
    for (state, event, reason) in cases {
      let rig = makeBridgeRig()
      rig.controller.presentIncoming(payload()) { _ in }
      let bridge = MknoonCallNativeBridge(controller: rig.controller, messenger: nil)
      XCTAssertEqual(invoke(bridge, "project", [
        "version": 1,
        "callHandle": callId.uuidString.lowercased(),
        "state": state,
      ]) as? Bool, true, state)
      XCTAssertEqual(rig.store.snapshot()?.terminalEvent?.type, event, state)
      XCTAssertEqual(rig.provider.endReports.last?.1, reason, state)
    }
  }

  func testLiveEventEnvelopeMatchesAttachEnvelopeAndDeliversOnMainThread() throws {
    let rig = makeBridgeRig()
    rig.controller.presentIncoming(payload()) { _ in }
    let bridge = MknoonCallNativeBridge(controller: rig.controller, messenger: nil)
    let delivered = expectation(description: "event")
    var eventValue: [String: Any]?
    XCTAssertNil(bridge.onListen(withArguments: nil) { value in
      XCTAssertTrue(Thread.isMainThread)
      eventValue = value as? [String: Any]
      delivered.fulfill()
    })
    XCTAssertTrue(rig.controller.handleAnswer(callId))
    wait(for: [delivered], timeout: 1)

    let envelope = try XCTUnwrap(eventValue)
    XCTAssertEqual(Set(envelope.keys), [
      "version", "descriptor", "events", "nativeCallId", "highestSequence",
    ])
    let events = try XCTUnwrap(envelope["events"] as? [[String: Any]])
    XCTAssertEqual(events.count, 1)
    XCTAssertEqual(Set(events[0].keys), [
      "callHandle", "sequence", "eventId", "type", "occurredAtMs",
    ])
    XCTAssertEqual(events[0]["type"] as? String, "answer")
    XCTAssertEqual(envelope["highestSequence"] as? Int64, 2)
  }

  func testRingbackMethodsResolveTheCallHandleAndDelegateToTheController() throws {
    let rig = makeBridgeRig()
    var registered: Bool?
    rig.controller.registerOutgoingAuthenticated(
      callHandle: callId.uuidString.lowercased(),
      expiresAtMs: now + 30_000
    ) { registered = $0 }
    XCTAssertEqual(registered, true)
    XCTAssertTrue(rig.controller.recordAudioActivatedForTests(callId))
    let bridge = MknoonCallNativeBridge(controller: rig.controller, messenger: nil)
    let handle = callId.uuidString.lowercased()
    let arguments: [String: Any] = ["version": 1, "callHandle": handle]

    XCTAssertEqual(invoke(bridge, "startRingback", arguments) as? Bool, true)
    XCTAssertEqual(rig.ringback.startCount, 1)
    XCTAssertEqual(invoke(bridge, "stopRingback", arguments) as? Bool, true)
    XCTAssertEqual(rig.ringback.stopCount, 1)
    XCTAssertEqual(invoke(bridge, "stopRingback", arguments) as? Bool, false)

    let malformed: [(String, Any?)] = [
      ("startRingback", nil),
      ("startRingback", ["version": 2, "callHandle": handle]),
      ("stopRingback", ["version": 1, "callHandle": "not-a-call-handle"]),
      ("startRingback", ["version": 1, "callHandle": handle, "loop": true]),
    ]
    for (method, arguments) in malformed {
      let error = invoke(bridge, method, arguments) as? FlutterError
      XCTAssertEqual(error?.code, "bad_args", method)
    }
    XCTAssertEqual(rig.ringback.startCount, 1)
  }

  private func makeBridgeRig(nowMs: (() -> Int64)? = nil) -> CallKitRig {
    let clock = nowMs ?? { self.now }
    let backend = MemoryPendingCallBackend()
    let store = PendingNativeCallStore(backend: backend, nowMs: clock)
    let provider = FakeCallProvider()
    let transactions = FakeCallTransactions()
    let contacts = OpaqueCallContactResolver(
      backend: MemoryOpaqueContactBackend(),
      nowMs: { self.now }
    )
    let audio = FakeCallAudio()
    let ringback = FakeCallRingback()
    let capability = MemoryCallCapability(enabled: true)
    let notificationCenter = NotificationCenter()
    let controller = MknoonCallKitController(
      provider: provider,
      transactionRequester: transactions,
      store: store,
      contacts: contacts,
      audio: audio,
      capability: capability,
      nowMs: clock,
      notificationCenter: notificationCenter,
      ringback: ringback
    )
    return CallKitRig(
      controller: controller,
      provider: provider,
      transactions: transactions,
      store: store,
      backend: backend,
      contacts: contacts,
      audio: audio,
      capability: capability,
      notificationCenter: notificationCenter,
      ringback: ringback
    )
  }

  private func payload() -> VoipWakePayload {
    VoipWakePayload(
      nativeCallId: callId,
      callHandle: callId.uuidString.lowercased(),
      wakeHandle: "223e4567-e89b-42d3-a456-426614174001",
      receivedAtMs: now,
      expiresAtMs: now + 30_000
    )
  }

  private func identity(_ handle: String) -> [String: Any] {
    ["version": 1, "callHandle": handle]
  }

  private func invoke(
    _ bridge: MknoonCallNativeBridge,
    _ method: String,
    _ arguments: Any?
  ) -> Any? {
    var captured: Any?
    bridge.handle(
      FlutterMethodCall(methodName: method, arguments: arguments)
    ) { captured = $0 }
    return captured
  }
}
