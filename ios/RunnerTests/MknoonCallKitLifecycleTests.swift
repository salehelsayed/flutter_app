import AVFoundation
import CallKit
import Foundation
import XCTest

@testable import Runner

final class MknoonCallKitLifecycleTests: XCTestCase {
  private let now: Int64 = 1_900_000_000_000
  private let callA = UUID(uuidString: "123e4567-e89b-42d3-a456-426614174000")!
  private let callB = UUID(uuidString: "323e4567-e89b-42d3-a456-426614174002")!
  private let contact = "223e4567-e89b-42d3-a456-426614174001"

  func testReportsExactlyOneIncomingCallAndDuplicateAdoptsSameUUID() throws {
    let rig = makeRig()
    XCTAssertEqual(present(rig, payload(callA)), .presented)
    XCTAssertEqual(present(rig, payload(callA)), .duplicate)
    XCTAssertEqual(rig.provider.incomingReports.map(\.0), [callA])
    XCTAssertEqual(try XCTUnwrap(rig.store.snapshot()).events.map(\.type), [.presented])
  }

  func testAuthenticatedPresentationToleratesPeerClockSkewAndBoundsLocalExpiry() {
    let rig = makeRig()
    var presented: Bool?

    rig.controller.presentAuthenticated(
      callHandle: callA.uuidString.lowercased(),
      expiresAtMs: now + VoipPayloadParser.maxFutureSkewMs + 1_000
    ) { presented = $0 }

    XCTAssertEqual(presented, true)
    XCTAssertEqual(rig.provider.incomingReports.map(\.0), [callA])
    XCTAssertEqual(
      rig.store.snapshot()?.expiresAtMs,
      now + VoipPayloadParser.maxFutureSkewMs,
      "peer clock tolerance must not extend the local ringing lifetime"
    )
  }

  func testAuthenticatedPresentationPreservesNearerExpiry() {
    let rig = makeRig()
    var presented: Bool?

    rig.controller.presentAuthenticated(
      callHandle: callA.uuidString.lowercased(),
      expiresAtMs: now + 20_000
    ) { presented = $0 }

    XCTAssertEqual(presented, true)
    XCTAssertEqual(rig.store.snapshot()?.expiresAtMs, now + 20_000)
  }

  func testAuthenticatedPresentationAcceptsExactPeerClockSkewBudget() {
    let rig = makeRig()
    var presented: Bool?

    rig.controller.presentAuthenticated(
      callHandle: callA.uuidString.lowercased(),
      expiresAtMs: now
        + VoipPayloadParser.maxFutureSkewMs
        + MknoonCallKitController.authenticatedPeerClockSkewMs
    ) { presented = $0 }

    XCTAssertEqual(presented, true)
    XCTAssertEqual(
      rig.store.snapshot()?.expiresAtMs,
      now + VoipPayloadParser.maxFutureSkewMs
    )
  }

  func testAuthenticatedPresentationRejectsBeyondPeerClockSkewBudget() {
    let rig = makeRig()
    var presented: Bool?

    rig.controller.presentAuthenticated(
      callHandle: callA.uuidString.lowercased(),
      expiresAtMs: now
        + VoipPayloadParser.maxFutureSkewMs
        + 30_000
        + 1
    ) { presented = $0 }

    XCTAssertEqual(presented, false)
    XCTAssertTrue(rig.provider.incomingReports.isEmpty)
    XCTAssertNil(rig.store.snapshot())
  }

  func testAuthenticatedPresentationRejectsAlreadyExpiredSignal() {
    let rig = makeRig()
    var presented: Bool?

    rig.controller.presentAuthenticated(
      callHandle: callA.uuidString.lowercased(),
      expiresAtMs: now
    ) { presented = $0 }

    XCTAssertEqual(presented, false)
    XCTAssertTrue(rig.provider.incomingReports.isEmpty)
    XCTAssertNil(rig.store.snapshot())
  }

  func testAuthenticatedPresentationRetriesMatchingUnpresentedDescriptor() {
    let rig = makeRig()
    _ = rig.store.create(payload(callA))
    rig.provider.delayedReportCompletion = { _ in }
    var presented: Bool?

    rig.controller.presentAuthenticated(
      callHandle: callA.uuidString.lowercased(),
      expiresAtMs: now + 30_000
    ) { presented = $0 }

    XCTAssertNil(presented, "the unpresented crash window must retry CallKit")
    XCTAssertEqual(rig.provider.incomingReports.map(\.0), [callA])
    XCTAssertEqual(rig.store.snapshot()?.presented, false)

    rig.provider.delayedReportCompletion?(nil)

    XCTAssertEqual(presented, true)
    XCTAssertEqual(rig.store.snapshot()?.presented, true)
  }

  func testConcurrentPushKitAndAuthenticatedPresentationCoalesceOneCallKitReportAndOnePresentedEvent() {
    let rig = makeRig()
    rig.provider.delayedReportCompletion = { _ in }
    var pushResult: MknoonCallPresentationResult?
    var authenticatedResult: Bool?

    rig.controller.presentIncoming(payload(callA), reportRequired: true) { pushResult = $0 }
    rig.controller.presentAuthenticated(
      callHandle: callA.uuidString.lowercased(),
      expiresAtMs: now + 30_000
    ) { authenticatedResult = $0 }

    XCTAssertEqual(rig.provider.incomingReports.map(\.0), [callA])
    XCTAssertNil(pushResult)
    XCTAssertNil(authenticatedResult)

    rig.provider.delayedReportCompletion?(nil)

    XCTAssertEqual(pushResult, .presented)
    XCTAssertEqual(authenticatedResult, true)
    XCTAssertEqual(rig.store.snapshot()?.events.map(\.type), [.presented])
  }

  func testPushKitPresentationDuringAnInFlightAuthenticatedReportStillReportsToCallKit() {
    let rig = makeRig()
    rig.provider.delayedReportCompletion = { _ in }
    var authenticatedResult: Bool?
    var pushResult: MknoonCallPresentationResult?

    rig.controller.presentAuthenticated(
      callHandle: callA.uuidString.lowercased(),
      expiresAtMs: now + 30_000
    ) { authenticatedResult = $0 }
    rig.controller.presentIncoming(payload(callA), reportRequired: true) { pushResult = $0 }

    XCTAssertEqual(
      rig.provider.incomingReports.map(\.0), [callA, callA],
      "PushKit needs a CallKit report inside its own delegate invocation"
    )
    XCTAssertNil(authenticatedResult)
    XCTAssertNil(pushResult)
    guard rig.provider.delayedReportCompletions.count == 2 else {
      return XCTFail(
        "expected two in-flight CallKit reports, got \(rig.provider.delayedReportCompletions.count)"
      )
    }

    rig.provider.delayedReportCompletions[0](nil)

    XCTAssertEqual(authenticatedResult, true)
    XCTAssertEqual(pushResult, .duplicate)
    XCTAssertEqual(rig.store.snapshot()?.events.map(\.type), [.presented])

    rig.provider.delayedReportCompletions[1](NSError(
      domain: CXErrorDomainIncomingCall,
      code: CXErrorCodeIncomingCallError.Code.callUUIDAlreadyExists.rawValue
    ))

    XCTAssertTrue(rig.provider.endReports.isEmpty)
    XCTAssertNil(rig.store.snapshot()?.terminalEvent)
    XCTAssertEqual(rig.store.snapshot()?.presented, true)
  }

  func testAuthenticatedReceiptReplayCannotClaimPresentationWithoutCallKit() throws {
    let first = makeRig()
    XCTAssertEqual(present(first, payload(callA)), .presented)
    XCTAssertTrue(first.controller.handleSystemEnd(callA))
    let terminalSequence = try XCTUnwrap(first.store.snapshot()?.highestSequence)
    XCTAssertTrue(
      first.controller.acknowledge(
        callA,
        through: terminalSequence,
        disposition: .terminal
      )
    )
    XCTAssertNil(first.store.snapshot())

    let replay = makeRig(backend: first.backend)
    var presented: Bool?
    replay.controller.presentAuthenticated(
      callHandle: callA.uuidString.lowercased(),
      expiresAtMs: now + 30_000
    ) { presented = $0 }

    XCTAssertEqual(presented, false)
    XCTAssertTrue(replay.provider.incomingReports.isEmpty)
    XCTAssertNil(replay.store.snapshot())
  }

  func testUnpresentedDuplicateRetriesSameUuidAcrossBothCrashWindows() throws {
    let beforeReport = makeRig()
    _ = beforeReport.store.create(payload(callA))
    XCTAssertEqual(present(beforeReport, payload(callA)), .presented)
    XCTAssertEqual(beforeReport.provider.incomingReports.map(\.0), [callA])
    XCTAssertEqual(beforeReport.store.snapshot()?.presented, true)

    let afterReport = makeRig()
    _ = afterReport.store.create(payload(callB))
    afterReport.provider.nextReportError = NSError(
      domain: CXErrorDomainIncomingCall,
      code: CXErrorCodeIncomingCallError.Code.callUUIDAlreadyExists.rawValue
    )
    XCTAssertEqual(present(afterReport, payload(callB)), .duplicate)
    XCTAssertEqual(afterReport.provider.incomingReports.map(\.0), [callB])
    XCTAssertEqual(afterReport.store.snapshot()?.presented, true)
    XCTAssertNil(afterReport.store.snapshot()?.terminalEvent)
  }

  func testBusySecondCallIsRejectedWithoutSecondCallKitReport() {
    let rig = makeRig()
    XCTAssertEqual(present(rig, payload(callA)), .presented)
    XCTAssertEqual(present(rig, payload(callB)), .busy)
    XCTAssertEqual(rig.provider.incomingReports.count, 1)
    XCTAssertEqual(rig.store.snapshot()?.nativeCallId, callA)
  }

  func testLegacyRequiredBusyPushAttemptsExistingUuidWithoutSecondDescriptor() {
    let rig = makeRig()
    XCTAssertEqual(present(rig, payload(callA)), .presented)
    rig.provider.nextReportError = NSError(
      domain: CXErrorDomainIncomingCall,
      code: CXErrorCodeIncomingCallError.Code.callUUIDAlreadyExists.rawValue
    )

    XCTAssertEqual(present(rig, payload(callB), reportPolicy: .legacyRequired), .busy)
    XCTAssertEqual(rig.provider.incomingReports.map(\.0), [callA, callA])
    XCTAssertTrue(rig.provider.endReports.isEmpty)
    XCTAssertEqual(rig.store.snapshot()?.nativeCallId, callA)
    XCTAssertNil(rig.store.snapshot()?.terminalEvent)
  }

  func testSuccessfulLegacyBusyReportRaceEndsAndFailsMatchingActiveCall() {
    let rig = makeRig()
    XCTAssertEqual(present(rig, payload(callA)), .presented)

    XCTAssertEqual(present(rig, payload(callB), reportPolicy: .legacyRequired), .busy)
    XCTAssertEqual(rig.provider.incomingReports.map(\.0), [callA, callA])
    XCTAssertEqual(rig.provider.endReports.map(\.0), [callA])
    XCTAssertEqual(rig.provider.endReports.map(\.1), [.failed])
    XCTAssertEqual(rig.store.snapshot()?.nativeCallId, callA)
    XCTAssertEqual(rig.store.snapshot()?.terminalEvent?.type, .nativeFailure)
  }

  func testMetadataRequiredBusyPushReportsAndEndsDistinctUuidPreservingActiveCall() {
    let rig = makeRig()
    XCTAssertEqual(present(rig, payload(callA)), .presented)

    XCTAssertEqual(present(rig, payload(callB), reportPolicy: .metadataRequired), .busy)
    XCTAssertEqual(rig.provider.incomingReports.count, 2)
    let complianceId = rig.provider.incomingReports[1].0
    XCTAssertNotEqual(complianceId, callA)
    XCTAssertEqual(rig.provider.endReports.map(\.0), [complianceId])
    XCTAssertEqual(rig.provider.endReports.map(\.1), [.failed])
    XCTAssertEqual(rig.store.snapshot()?.nativeCallId, callA)
    XCTAssertNil(rig.store.snapshot()?.terminalEvent)
  }

  func testRequiredInvalidComplianceReportIsEphemeralAndWaitsToEndUntilSuccess() {
    let rig = makeRig()
    rig.provider.delayedReportCompletion = { _ in }
    var completionCount = 0

    rig.controller.satisfyRequiredVoipPushReport { completionCount += 1 }

    let reportedId = rig.provider.incomingReports.first?.0
    XCTAssertNotNil(reportedId)
    XCTAssertNil(rig.store.snapshot(), "invalid fallback must not create application call state")
    XCTAssertTrue(rig.provider.endReports.isEmpty)
    XCTAssertEqual(completionCount, 0)

    rig.provider.delayedReportCompletion?(nil)
    XCTAssertEqual(rig.provider.endReports.count, 1)
    XCTAssertEqual(rig.provider.endReports.first?.0, reportedId)
    XCTAssertEqual(rig.provider.endReports.map(\.1), [.failed])
    XCTAssertNil(rig.store.snapshot())
    XCTAssertEqual(completionCount, 1)
  }

  func testLegacyMalformedPushDuringActiveCallReportsExistingUuidAndPreservesOnError() {
    let rig = makeRig()
    XCTAssertEqual(present(rig, payload(callA)), .presented)
    rig.provider.nextReportError = NSError(
      domain: CXErrorDomainIncomingCall,
      code: CXErrorCodeIncomingCallError.Code.callUUIDAlreadyExists.rawValue
    )
    var completionCount = 0

    rig.controller.satisfyRequiredVoipPushReport(reportPolicy: .legacyRequired) {
      completionCount += 1
    }

    XCTAssertEqual(rig.provider.incomingReports.map(\.0), [callA, callA])
    XCTAssertTrue(rig.provider.endReports.isEmpty)
    XCTAssertEqual(rig.store.snapshot()?.nativeCallId, callA)
    XCTAssertNil(rig.store.snapshot()?.terminalEvent)
    XCTAssertEqual(completionCount, 1)
  }

  func testLegacyDisabledPushWithSurvivingActiveDescriptorReportsExistingUuid() {
    let rig = makeRig()
    XCTAssertEqual(present(rig, payload(callA)), .presented)
    rig.capability.enabled = false
    rig.provider.nextReportError = NSError(
      domain: CXErrorDomainIncomingCall,
      code: CXErrorCodeIncomingCallError.Code.callUUIDAlreadyExists.rawValue
    )

    XCTAssertEqual(present(rig, payload(callB), reportPolicy: .legacyRequired), .disabled)
    XCTAssertEqual(rig.provider.incomingReports.map(\.0), [callA, callA])
    XCTAssertTrue(rig.provider.endReports.isEmpty)
    XCTAssertEqual(rig.store.snapshot()?.nativeCallId, callA)
    XCTAssertNil(rig.store.snapshot()?.terminalEvent)
  }

  func testAnswerBeforeFlutterPersistsAndReplaysOnceInOrder() throws {
    let rig = makeRig()
    XCTAssertEqual(present(rig, payload(callA)), .presented)
    XCTAssertTrue(rig.controller.handleAnswer(callA))
    let recreated = makeRig(backend: rig.backend)
    let snapshot = try XCTUnwrap(recreated.controller.attach())
    XCTAssertEqual(snapshot.events.map(\.type), [.presented, .answerRequested])
    XCTAssertEqual(snapshot.events.map(\.sequence), [1, 2])
    XCTAssertEqual(recreated.controller.attach(), snapshot, "attach must not consume")
    XCTAssertTrue(recreated.controller.acknowledge(callA, through: 1, disposition: .adopted))
    XCTAssertEqual(recreated.controller.attach()?.events.map(\.sequence), [2])
    XCTAssertTrue(recreated.controller.acknowledge(callA, through: 2, disposition: .none))
    XCTAssertTrue(recreated.controller.attach()?.events.isEmpty == true)
  }

  func testDeclineEndRemoteCancelAndDartRaceConvergeOnOneTerminal() throws {
    let declined = makeRig()
    XCTAssertEqual(present(declined, payload(callA)), .presented)
    XCTAssertTrue(declined.controller.handleSystemEnd(callA))
    XCTAssertFalse(declined.controller.handleAnswer(callA))
    XCTAssertEqual(declined.store.snapshot()?.terminalEvent?.type, .declineRequested)

    let raced = makeRig()
    XCTAssertEqual(present(raced, payload(callB)), .presented)
    XCTAssertTrue(raced.controller.remoteCancel(callHandle: callB.uuidString.lowercased()))
    XCTAssertTrue(raced.controller.endFromDart(callB), "the same terminal is idempotently adopted")
    XCTAssertEqual(raced.provider.endReports.count, 1)
    XCTAssertEqual(raced.store.snapshot()?.events.filter(\.type.isTerminal).count, 1)
  }

  func testProviderResetSerializesOneTerminalAndNotifiesDartOnce() throws {
    let rig = makeRig()
    var events: [PendingNativeCallEvent] = []
    rig.controller.setEventHandler { events.append($0) }
    XCTAssertEqual(present(rig, payload(callA)), .presented)
    XCTAssertTrue(rig.controller.handleProviderReset())
    XCTAssertFalse(rig.controller.handleProviderReset())
    XCTAssertEqual(rig.store.snapshot()?.terminalEvent?.type, .providerRemoved)
    XCTAssertEqual(events.filter { $0.type == .providerRemoved }.count, 1)
  }

  func testExpiredDescriptorOnColdLaunchEndsWithoutRestoringRinging() throws {
    let backend = MemoryPendingCallBackend()
    let initialStore = PendingNativeCallStore(backend: backend, nowMs: { self.now })
    _ = initialStore.create(payload(callA, expiresAtMs: now + 1_000))
    _ = initialStore.append(nativeCallId: callA, type: .presented)

    let expired = makeRig(backend: backend, nowMs: now + 2_000)
    let snapshot = try XCTUnwrap(expired.controller.attach())
    XCTAssertEqual(snapshot.terminalEvent?.type, .expired)
    XCTAssertEqual(expired.provider.incomingReports.count, 0)
    XCTAssertEqual(expired.provider.endReports.count, 1)
  }

  func testCallerNameComesOnlyFromProtectedOpaqueMappingAndCanUpdate() throws {
    let rig = makeRig()
    XCTAssertTrue(rig.contacts.updateVerified(handle: contact, displayName: "Alice"))
    XCTAssertEqual(present(rig, payload(callA)), .presented)
    XCTAssertEqual(rig.provider.incomingReports.first?.1.localizedCallerName, "Alice")

    XCTAssertTrue(rig.controller.updateAuthenticatedContact(
      callHandle: callA.uuidString.lowercased(),
      verifiedDisplayName: "Alice Device"
    ))
    XCTAssertEqual(rig.provider.updates.last?.1.localizedCallerName, "Alice Device")
    XCTAssertFalse(rig.controller.updateAuthenticatedContact(
      callHandle: callB.uuidString.lowercased(),
      verifiedDisplayName: "Payload Name"
    ))

    XCTAssertTrue(rig.controller.acknowledge(callA, through: 1, disposition: .adopted))
    XCTAssertTrue(rig.controller.updateAuthenticatedContact(
      callHandle: callA.uuidString.lowercased(),
      verifiedDisplayName: "Alice Adopted"
    ))
    XCTAssertEqual(rig.provider.updates.last?.1.localizedCallerName, "Alice Adopted")
  }

  func testOpaqueContactCanPublishAndRevokeWithoutCallDescriptor() {
    let rig = makeRig()
    let wakeHandle = "223e4567e89b42d3a456426614174001"
    XCTAssertNil(rig.store.snapshot())

    XCTAssertTrue(rig.controller.publishOpaqueContact(
      wakeHandle: wakeHandle,
      displayName: "Alice"
    ))
    XCTAssertEqual(rig.contacts.displayName(for: wakeHandle), "Alice")
    XCTAssertNil(rig.store.snapshot())

    XCTAssertTrue(rig.controller.revokeOpaqueContactHandle(wakeHandle))
    XCTAssertEqual(
      rig.contacts.displayName(for: wakeHandle),
      OpaqueCallContactResolver.genericDisplayName
    )
    XCTAssertNil(rig.store.snapshot())
  }

  func testAudioRequiresAnswerAndCallKitActivationThenSerializesRouteAndDeactivation() throws {
    let rig = makeRig()
    XCTAssertEqual(present(rig, payload(callA)), .presented)
    XCTAssertFalse(rig.controller.activateAudio(callA))
    XCTAssertTrue(rig.controller.handleAnswer(callA))
    XCTAssertFalse(rig.controller.activateAudio(callA))
    XCTAssertTrue(rig.controller.recordAudioActivatedForTests(callA))
    XCTAssertFalse(
      rig.controller.activateAudio(callA),
      "CallKit activation is only a latch until authenticated adoption"
    )
    XCTAssertTrue(rig.controller.acknowledge(callA, through: 1, disposition: .adopted))
    XCTAssertTrue(rig.controller.activateAudio(callA))
    // Configured once at answer (before CallKit activates) and once at the
    // activation latch.
    XCTAssertEqual(rig.audio.prepareCount, 2)
    XCTAssertTrue(rig.controller.requestRoute(callA, route: "speaker"))
    XCTAssertEqual(rig.audio.requestedRoutes, ["speaker"])
    XCTAssertTrue(rig.controller.deactivateAudio(callA))
    XCTAssertTrue(rig.controller.recordAudioDeactivatedForTests(callA))
    XCTAssertEqual(
      rig.store.snapshot()?.events.map(\.type),
      [.answerRequested, .audioActivated, .routeChanged, .audioDeactivated]
    )
  }

  func testAudioRouteStateAndRequestsUseExactDartCanonicalWireNames() throws {
    let rig = makeRig()
    XCTAssertEqual(present(rig, payload(callA)), .presented)
    XCTAssertTrue(rig.controller.handleAnswer(callA))
    XCTAssertTrue(rig.controller.acknowledge(callA, through: 1, disposition: .adopted))
    XCTAssertTrue(rig.controller.recordAudioActivatedForTests(callA))
    XCTAssertTrue(rig.controller.activateAudio(callA))

    let canonicalRoutes = [
      "system_default",
      "earpiece",
      "speaker",
      "wired_headset",
      "bluetooth",
    ]
    let state = try XCTUnwrap(rig.controller.audioState(callA))
    XCTAssertEqual(state.route, "earpiece")
    XCTAssertEqual(state.availableRoutes, canonicalRoutes)

    for route in canonicalRoutes {
      XCTAssertTrue(rig.controller.requestRoute(callA, route: route))
    }
    XCTAssertEqual(rig.audio.requestedRoutes, canonicalRoutes)

    for legacyAlias in ["systemDefault", "receiver", "wired"] {
      XCTAssertFalse(rig.controller.requestRoute(callA, route: legacyAlias))
    }
  }

  func testOutgoingPresentedAdoptedCallKitActivationAllowsMediaClaimWithoutAnswer() {
    let rig = makeRig()
    var registered: Bool?

    rig.controller.registerOutgoingAuthenticated(
      callHandle: callA.uuidString.lowercased(),
      expiresAtMs: now + 30_000
    ) { registered = $0 }

    XCTAssertEqual(registered, true)
    XCTAssertEqual(rig.store.snapshot()?.direction, .outgoing)
    XCTAssertEqual(rig.store.snapshot()?.events.map(\.type), [.presented])
    XCTAssertTrue(rig.controller.acknowledge(callA, through: 1, disposition: .adopted))
    XCTAssertTrue(
      rig.controller.recordAudioActivatedForTests(callA),
      "CallKit activation must latch for an authenticated outgoing call"
    )
    XCTAssertTrue(rig.controller.activateAudio(callA))
    XCTAssertEqual(rig.audio.prepareCount, 1)
    XCTAssertFalse(rig.store.snapshot()?.answerRequested ?? true)
  }

  func testConnectedOutgoingSurvivesRegistrationExpiryAcrossControllerRecreation() throws {
    let backend = MemoryPendingCallBackend()
    var clock = now

    do {
      let initial = makeRig(backend: backend, nowMsProvider: { clock })
      var registered: Bool?
      initial.controller.registerOutgoingAuthenticated(
        callHandle: callA.uuidString.lowercased(),
        expiresAtMs: clock + 1_000
      ) { registered = $0 }

      XCTAssertEqual(registered, true)
      XCTAssertTrue(initial.controller.project(callA, state: "connected"))
      XCTAssertEqual(initial.provider.outgoingConnected, [callA])
      XCTAssertNil(initial.store.snapshot()?.terminalEvent)
    }

    clock += 1_001
    let recreated = makeRig(backend: backend, nowMsProvider: { clock })
    let snapshot = try XCTUnwrap(recreated.controller.attach())

    XCTAssertEqual(snapshot.direction, .outgoing)
    XCTAssertNil(snapshot.terminalEvent)
    XCTAssertTrue(recreated.provider.endReports.isEmpty)
  }

  func testUnconnectedOutgoingStillExpiresAcrossControllerRecreation() throws {
    let backend = MemoryPendingCallBackend()
    var clock = now

    do {
      let initial = makeRig(backend: backend, nowMsProvider: { clock })
      var registered: Bool?
      initial.controller.registerOutgoingAuthenticated(
        callHandle: callA.uuidString.lowercased(),
        expiresAtMs: clock + 1_000
      ) { registered = $0 }
      XCTAssertEqual(registered, true)
    }

    clock += 1_001
    let recreated = makeRig(backend: backend, nowMsProvider: { clock })
    let snapshot = try XCTUnwrap(recreated.controller.attach())

    XCTAssertEqual(snapshot.terminalEvent?.type, .expired)
    XCTAssertEqual(recreated.provider.endReports.map(\.1), [.unanswered])
  }

  func testConnectedProjectionFailsClosedBeforeReportingWhenMarkerCannotPersist() {
    let rig = makeRig()
    var registered: Bool?
    rig.controller.registerOutgoingAuthenticated(
      callHandle: callA.uuidString.lowercased(),
      expiresAtMs: now + 30_000
    ) { registered = $0 }
    XCTAssertEqual(registered, true)

    rig.backend.failWrites = true
    XCTAssertFalse(rig.controller.project(callA, state: "connected"))

    XCTAssertTrue(rig.provider.outgoingConnected.isEmpty)
    XCTAssertEqual(rig.provider.endReports.map(\.1), [.failed])
    XCTAssertFalse(rig.capability.enabled)
  }

  func testReturnWakeForRegisteredOutgoingPreservesOutgoingDescriptorWithoutIncomingUi() {
    let rig = makeRig()
    var registered: Bool?

    rig.controller.registerOutgoingAuthenticated(
      callHandle: callA.uuidString.lowercased(),
      expiresAtMs: now + 30_000
    ) { registered = $0 }
    rig.provider.nextReportError = NSError(
      domain: CXErrorDomainIncomingCall,
      code: CXErrorCodeIncomingCallError.Code.callUUIDAlreadyExists.rawValue
    )

    XCTAssertEqual(registered, true)
    XCTAssertEqual(
      present(rig, payload(callA), reportPolicy: .legacyRequired),
      .busy
    )
    XCTAssertEqual(rig.provider.outgoingConnecting, [callA])
    XCTAssertEqual(rig.provider.incomingReports.map(\.0), [callA])
    XCTAssertTrue(rig.provider.endReports.isEmpty)
    XCTAssertEqual(rig.store.snapshot()?.nativeCallId, callA)
    XCTAssertEqual(rig.store.snapshot()?.direction, .outgoing)
    XCTAssertNil(rig.store.snapshot()?.terminalEvent)
  }

  func testSuccessfulReturnWakeReportForRegisteredOutgoingDoesNotEndCall() {
    let rig = makeRig()
    var registered: Bool?

    rig.controller.registerOutgoingAuthenticated(
      callHandle: callA.uuidString.lowercased(),
      expiresAtMs: now + 30_000
    ) { registered = $0 }

    XCTAssertEqual(registered, true)
    XCTAssertEqual(
      present(rig, payload(callA), reportPolicy: .legacyRequired),
      .busy
    )
    XCTAssertEqual(rig.provider.outgoingConnecting, [callA])
    XCTAssertEqual(rig.provider.incomingReports.map(\.0), [callA])
    XCTAssertTrue(rig.provider.endReports.isEmpty)
    XCTAssertEqual(rig.store.snapshot()?.nativeCallId, callA)
    XCTAssertEqual(rig.store.snapshot()?.direction, .outgoing)
    XCTAssertNil(rig.store.snapshot()?.terminalEvent)
  }

  func testRouteChangeNotificationSerializesAndPersistenceFailureFailsClosed() throws {
    let rig = makeRig()
    XCTAssertEqual(present(rig, payload(callA)), .presented)
    XCTAssertTrue(rig.controller.handleAnswer(callA))
    XCTAssertTrue(rig.controller.acknowledge(callA, through: 1, disposition: .adopted))
    XCTAssertTrue(rig.controller.recordAudioActivatedForTests(callA))

    rig.notificationCenter.post(name: AVAudioSession.routeChangeNotification, object: nil)

    XCTAssertEqual(rig.store.snapshot()?.events.last?.type, .routeChanged)
    XCTAssertTrue(rig.controller.audioState(callA)?.active ?? false)
    XCTAssertTrue(rig.capability.enabled)

    rig.backend.failWrites = true
    rig.notificationCenter.post(name: AVAudioSession.routeChangeNotification, object: nil)

    XCTAssertFalse(rig.capability.enabled)
    XCTAssertFalse(rig.controller.audioState(callA)?.active ?? true)
    XCTAssertEqual(rig.provider.endReports.last?.1, .failed)
    XCTAssertEqual(
      rig.store.snapshot()?.events.filter { $0.type == .routeChanged }.count,
      1,
      "an uncommitted route event must never be published as native state"
    )
  }

  func testInterruptionNotificationsSerializeDeactivationAndEndedRoute() throws {
    let rig = makeRig()
    XCTAssertEqual(present(rig, payload(callA)), .presented)
    XCTAssertTrue(rig.controller.handleAnswer(callA))
    XCTAssertTrue(rig.controller.acknowledge(callA, through: 1, disposition: .adopted))
    XCTAssertTrue(rig.controller.recordAudioActivatedForTests(callA))

    rig.notificationCenter.post(
      name: AVAudioSession.interruptionNotification,
      object: nil,
      userInfo: [
        AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue,
      ]
    )
    XCTAssertFalse(rig.controller.audioState(callA)?.active ?? true)
    XCTAssertEqual(rig.store.snapshot()?.events.last?.type, .audioDeactivated)

    rig.notificationCenter.post(
      name: AVAudioSession.interruptionNotification,
      object: nil,
      userInfo: [
        AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.ended.rawValue,
      ]
    )
    XCTAssertEqual(
      rig.store.snapshot()?.events.suffix(2).map(\.type),
      [.audioDeactivated, .routeChanged]
    )

    rig.backend.failWrites = true
    rig.notificationCenter.post(
      name: AVAudioSession.interruptionNotification,
      object: nil,
      userInfo: [
        AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.ended.rawValue,
      ]
    )
    XCTAssertFalse(rig.capability.enabled)
    XCTAssertEqual(rig.provider.endReports.last?.1, .failed)
  }

  func testMediaServicesResetNotificationSerializesDeactivationAndRoute() throws {
    let rig = makeRig()
    XCTAssertEqual(present(rig, payload(callA)), .presented)
    XCTAssertTrue(rig.controller.handleAnswer(callA))
    XCTAssertTrue(rig.controller.acknowledge(callA, through: 1, disposition: .adopted))
    XCTAssertTrue(rig.controller.recordAudioActivatedForTests(callA))

    rig.notificationCenter.post(
      name: AVAudioSession.mediaServicesWereResetNotification,
      object: nil
    )

    XCTAssertFalse(rig.controller.audioState(callA)?.active ?? true)
    XCTAssertEqual(
      rig.store.snapshot()?.events.suffix(2).map(\.type),
      [.audioDeactivated, .routeChanged]
    )
  }

  func testMuteStateRehydratesAcrossProcessRecreationForMuteAndUnmute() throws {
    let rig = makeRig()
    XCTAssertEqual(present(rig, payload(callA)), .presented)
    XCTAssertTrue(rig.controller.handleMute(callA, muted: true))
    XCTAssertEqual(rig.store.snapshot()?.muted, true)

    let muted = makeRig(backend: rig.backend)
    XCTAssertEqual(muted.controller.audioState(callA)?.muted, true)
    XCTAssertTrue(muted.controller.handleMute(callA, muted: false))
    XCTAssertEqual(muted.store.snapshot()?.muted, false)

    let unmuted = makeRig(backend: rig.backend)
    XCTAssertEqual(unmuted.controller.audioState(callA)?.muted, false)
    XCTAssertEqual(
      unmuted.store.snapshot()?.events.filter { $0.type == .muteChanged }.count,
      2
    )
  }

  func testProviderResetAndAudioJournalFailuresFailClosedWithoutMemoryOnlySuccess() {
    let reset = makeRig()
    XCTAssertEqual(present(reset, payload(callA)), .presented)
    reset.backend.failWrites = true
    XCTAssertFalse(reset.controller.handleProviderReset())
    XCTAssertFalse(reset.capability.enabled)
    XCTAssertEqual(reset.provider.endReports.last?.1, .failed)

    let activation = makeRig()
    XCTAssertEqual(present(activation, payload(callB)), .presented)
    XCTAssertTrue(activation.controller.handleAnswer(callB))
    XCTAssertTrue(activation.controller.acknowledge(callB, through: 1, disposition: .adopted))
    activation.backend.failWrites = true
    XCTAssertFalse(activation.controller.recordAudioActivatedForTests(callB))
    XCTAssertFalse(activation.controller.audioState(callB)?.active ?? true)
    XCTAssertFalse(activation.capability.enabled)
    XCTAssertEqual(activation.provider.endReports.last?.1, .failed)

    let deactivation = makeRig()
    XCTAssertEqual(present(deactivation, payload(callA)), .presented)
    XCTAssertTrue(deactivation.controller.handleAnswer(callA))
    XCTAssertTrue(deactivation.controller.acknowledge(callA, through: 1, disposition: .adopted))
    XCTAssertTrue(deactivation.controller.recordAudioActivatedForTests(callA))
    deactivation.backend.failWrites = true
    XCTAssertFalse(deactivation.controller.recordAudioDeactivatedForTests(callA))
    XCTAssertFalse(deactivation.controller.audioState(callA)?.active ?? true)
    XCTAssertFalse(deactivation.capability.enabled)
    XCTAssertEqual(deactivation.provider.endReports.last?.1, .failed)
  }

  func testCapabilityDisableAttemptsRegistryAndFailsCurrentCallWhenDurabilityFails() {
    let rig = makeRig()
    XCTAssertEqual(present(rig, payload(callA)), .presented)
    var registryActive = true
    var capabilityChanges: [Bool] = []
    rig.controller.setCapabilityChangeHandler { enabled in
      capabilityChanges.append(enabled)
      registryActive = enabled
      return true
    }
    rig.capability.failWrites = true

    XCTAssertFalse(rig.controller.setCapabilityEnabled(false))

    XCTAssertEqual(capabilityChanges, [false])
    XCTAssertFalse(registryActive)
    XCTAssertTrue(rig.capability.enabled, "the failed durable write must not be reported as success")
    XCTAssertEqual(rig.store.snapshot()?.terminalEvent?.type, .nativeFailure)
    XCTAssertEqual(rig.provider.endReports.last?.1, .failed)
  }

  func testCapabilityDisablePersistsAndFailsCurrentCallDespiteRegistryHandlerFailure() {
    let rig = makeRig()
    XCTAssertEqual(present(rig, payload(callA)), .presented)
    var disableAttempts = 0
    rig.controller.setCapabilityChangeHandler { enabled in
      if !enabled { disableAttempts += 1 }
      return false
    }

    XCTAssertFalse(rig.controller.setCapabilityEnabled(false))

    XCTAssertEqual(disableAttempts, 1)
    XCTAssertFalse(rig.capability.enabled)
    XCTAssertEqual(rig.store.snapshot()?.terminalEvent?.type, .nativeFailure)
    XCTAssertEqual(rig.provider.endReports.last?.1, .failed)
  }

  func testCapabilityEnableStillRequiresDurabilityBeforeRegistration() {
    let rig = makeRig()
    rig.capability.enabled = false
    rig.capability.failWrites = true
    var registrationAttempts = 0
    rig.controller.setCapabilityChangeHandler { _ in
      registrationAttempts += 1
      return true
    }

    XCTAssertFalse(rig.controller.setCapabilityEnabled(true))
    XCTAssertEqual(registrationAttempts, 0)
    XCTAssertFalse(rig.capability.enabled)
  }

  func testAttachSweepsTerminalOnlyAfterBoundedReplayDeadline() throws {
    let backend = MemoryPendingCallBackend()
    var clock = now
    let initial = PendingNativeCallStore(backend: backend, nowMs: { clock })
    _ = initial.create(payload(callA))
    _ = initial.append(nativeCallId: callA, type: .presented)
    _ = initial.append(nativeCallId: callA, type: .expired)

    clock += PendingNativeCallStore.terminalReplayRetentionMs - 1
    XCTAssertNotNil(makeRig(backend: backend, nowMsProvider: { clock }).controller.attach())
    clock += 1
    XCTAssertNil(makeRig(backend: backend, nowMsProvider: { clock }).controller.attach())
    XCTAssertEqual(backend.deleteCount, 1)
  }

  func testAnswerThenRemoteCancelBeforeAttachmentCannotBeRevivedAndTerminalAckDeletesOnce() throws {
    let rig = makeRig()
    XCTAssertEqual(present(rig, payload(callA)), .presented)
    XCTAssertTrue(rig.controller.handleAnswer(callA))
    XCTAssertTrue(rig.controller.remoteCancel(callHandle: callA.uuidString.lowercased()))
    let recreated = makeRig(backend: rig.backend)
    let descriptor = try XCTUnwrap(recreated.controller.attach())
    XCTAssertEqual(descriptor.events.map(\.type), [.presented, .answerRequested, .remoteCancelled])
    XCTAssertFalse(recreated.controller.adopt(callA))
    XCTAssertFalse(recreated.controller.activateAudio(callA))
    XCTAssertTrue(recreated.controller.acknowledge(
      callA,
      through: descriptor.highestSequence,
      disposition: .terminal
    ))
    XCTAssertNil(recreated.store.snapshot())
    XCTAssertEqual(rig.backend.deleteCount, 1)
    XCTAssertTrue(recreated.controller.acknowledge(
      callA,
      through: descriptor.highestSequence,
      disposition: .terminal
    ))
    XCTAssertEqual(rig.backend.deleteCount, 1)
  }

  func testAnswerThenExpiryBeforeAttachmentCannotBeRevivedAndTerminalAckDeletesOnce() throws {
    let backend = MemoryPendingCallBackend()
    var clock = now
    let initial = makeRig(backend: backend, nowMsProvider: { clock })
    XCTAssertEqual(present(initial, payload(callA)), .presented)
    XCTAssertTrue(initial.controller.handleAnswer(callA))

    clock += 30_001
    let recreated = makeRig(backend: backend, nowMsProvider: { clock })
    let descriptor = try XCTUnwrap(recreated.controller.attach())

    XCTAssertEqual(descriptor.events.map(\.type), [.presented, .answerRequested, .expired])
    XCTAssertEqual(recreated.provider.endReports.map(\.1), [.unanswered])
    XCTAssertFalse(recreated.controller.adopt(callA))
    XCTAssertFalse(recreated.controller.activateAudio(callA))
    XCTAssertTrue(recreated.controller.acknowledge(
      callA,
      through: descriptor.highestSequence,
      disposition: .terminal
    ))
    XCTAssertNil(recreated.store.snapshot())
    XCTAssertEqual(backend.deleteCount, 1)
    XCTAssertTrue(recreated.controller.acknowledge(
      callA,
      through: descriptor.highestSequence,
      disposition: .terminal
    ))
    XCTAssertEqual(backend.deleteCount, 1)
  }

  private func makeRig(
    backend: MemoryPendingCallBackend = MemoryPendingCallBackend(),
    nowMs: Int64? = nil,
    nowMsProvider: (() -> Int64)? = nil
  ) -> CallKitRig {
    let observedNow = nowMs ?? now
    let clock = nowMsProvider ?? { observedNow }
    let store = PendingNativeCallStore(backend: backend, nowMs: clock)
    let provider = FakeCallProvider()
    let transactions = FakeCallTransactions()
    let contacts = OpaqueCallContactResolver(
      backend: MemoryOpaqueContactBackend(),
      nowMs: clock
    )
    let audio = FakeCallAudio()
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
      notificationCenter: notificationCenter
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
      notificationCenter: notificationCenter
    )
  }

  // MARK: - Call audio session configuration

  func testAnswerConfiguresTheCallAudioSessionBeforeFulfilment() {
    let rig = makeRig()
    XCTAssertEqual(present(rig, payload(callA)), .presented)
    XCTAssertEqual(rig.audio.prepareCount, 0, "ringing never configures call audio")

    XCTAssertTrue(rig.controller.handleAnswer(callA))

    // CallKit activates whatever session the app configured before the
    // answer action is fulfilled; configuring only inside didActivate leaves
    // nothing for it to activate on the first call.
    XCTAssertEqual(rig.audio.prepareCount, 1)
  }

  // MARK: - Answer adoption bound

  func testAnswerNobodyConsumesEndsTheCallAtTheAdoptionBound() {
    var clock = now
    let rig = makeRig(nowMsProvider: { clock })
    XCTAssertEqual(present(rig, payload(callA)), .presented)
    XCTAssertTrue(rig.controller.handleAnswer(callA))

    clock += MknoonCallKitController.answerAdoptionBoundMs - 1
    XCTAssertFalse(rig.controller.enforceAnswerAdoptionBound(callA))
    XCTAssertNil(rig.store.snapshot()?.terminalEvent)
    XCTAssertTrue(rig.provider.endReports.isEmpty)

    clock += 1
    XCTAssertTrue(rig.controller.enforceAnswerAdoptionBound(callA))
    XCTAssertEqual(rig.store.snapshot()?.terminalEvent?.type, .nativeFailure)
    XCTAssertEqual(rig.provider.endReports.map(\.0), [callA])
    XCTAssertEqual(rig.provider.endReports.map(\.1), [.failed])
    // Idempotent: the bound never ends a call twice.
    XCTAssertFalse(rig.controller.enforceAnswerAdoptionBound(callA))
  }

  func testAnswerConsumedByTheRuntimeIsNotEndedAtTheAdoptionBound() {
    var clock = now
    let rig = makeRig(nowMsProvider: { clock })
    XCTAssertEqual(present(rig, payload(callA)), .presented)
    XCTAssertTrue(rig.controller.handleAnswer(callA))
    let answerSequence = rig.store.snapshot()!.highestSequence
    XCTAssertTrue(
      rig.controller.acknowledge(callA, through: answerSequence, disposition: .adopted))

    clock += MknoonCallKitController.answerAdoptionBoundMs * 2
    XCTAssertFalse(rig.controller.enforceAnswerAdoptionBound(callA))
    XCTAssertNil(rig.store.snapshot()?.terminalEvent)
    XCTAssertTrue(rig.provider.endReports.isEmpty)
  }

  func testAnswerAdoptionBoundIgnoresOtherCalls() {
    var clock = now
    let rig = makeRig(nowMsProvider: { clock })
    XCTAssertEqual(present(rig, payload(callA)), .presented)
    XCTAssertTrue(rig.controller.handleAnswer(callA))
    clock += MknoonCallKitController.answerAdoptionBoundMs
    XCTAssertFalse(rig.controller.enforceAnswerAdoptionBound(UUID()))
    XCTAssertNil(rig.store.snapshot()?.terminalEvent)
  }

  private func present(
    _ rig: CallKitRig,
    _ payload: VoipWakePayload,
    reportPolicy: MknoonVoipPushReportPolicy = .notRequired,
    file: StaticString = #filePath,
    line: UInt = #line
  ) -> MknoonCallPresentationResult {
    var captured: MknoonCallPresentationResult?
    if reportPolicy != .notRequired {
      rig.controller.presentIncoming(payload, reportPolicy: reportPolicy) { captured = $0 }
    } else {
      rig.controller.presentIncoming(payload) { captured = $0 }
    }
    XCTAssertNotNil(captured, file: file, line: line)
    return captured ?? .callKitFailure
  }

  private func payload(_ id: UUID, expiresAtMs: Int64? = nil) -> VoipWakePayload {
    VoipWakePayload(
      nativeCallId: id,
      callHandle: id.uuidString.lowercased(),
      wakeHandle: contact,
      receivedAtMs: now,
      expiresAtMs: expiresAtMs ?? now + 30_000
    )
  }
}

struct CallKitRig {
  let controller: MknoonCallKitController
  let provider: FakeCallProvider
  let transactions: FakeCallTransactions
  let store: PendingNativeCallStore
  let backend: MemoryPendingCallBackend
  let contacts: OpaqueCallContactResolver
  let audio: FakeCallAudio
  let capability: MemoryCallCapability
  let notificationCenter: NotificationCenter
}

final class FakeCallProvider: MknoonCallProviding {
  weak var delegate: CXProviderDelegate?
  var incomingReports: [(UUID, CXCallUpdate)] = []
  var updates: [(UUID, CXCallUpdate)] = []
  var endReports: [(UUID, CXCallEndedReason)] = []
  var outgoingConnecting: [UUID] = []
  var outgoingConnected: [UUID] = []
  var nextReportError: Error?
  var delayedReportCompletion: ((Error?) -> Void)?
  var delayedReportCompletions: [(Error?) -> Void] = []

  func setDelegate(_ delegate: CXProviderDelegate?, queue: DispatchQueue?) {
    self.delegate = delegate
  }

  func reportNewIncomingCall(
    with UUID: UUID,
    update: CXCallUpdate,
    completion: @escaping (Error?) -> Void
  ) {
    incomingReports.append((UUID, update))
    if delayedReportCompletion == nil {
      completion(nextReportError)
    } else {
      delayedReportCompletion = completion
      delayedReportCompletions.append(completion)
    }
  }

  func reportCall(with UUID: UUID, updated update: CXCallUpdate) {
    updates.append((UUID, update))
  }

  func reportCall(with UUID: UUID, endedAt dateEnded: Date?, reason endedReason: CXCallEndedReason) {
    endReports.append((UUID, endedReason))
  }

  func reportOutgoingCall(with UUID: UUID, startedConnectingAt dateStartedConnecting: Date?) {
    outgoingConnecting.append(UUID)
  }

  func reportOutgoingCall(with UUID: UUID, connectedAt dateConnected: Date?) {
    outgoingConnected.append(UUID)
  }
}

final class FakeCallTransactions: MknoonCallTransactionRequesting {
  var transactions: [CXTransaction] = []
  var nextError: Error?

  func request(_ transaction: CXTransaction, completion: @escaping (Error?) -> Void) {
    transactions.append(transaction)
    completion(nextError)
  }
}

final class FakeCallAudio: MknoonCallAudioManaging {
  var prepareCount = 0
  var releaseCount = 0
  var requestedRoutes: [String] = []
  var state = (
    route: "earpiece",
    available: ["system_default", "earpiece", "speaker", "wired_headset", "bluetooth"]
  )

  func prepareForCallKitActivation() throws { prepareCount += 1 }
  func releaseAfterCallKitDeactivation() { releaseCount += 1 }
  func routeState() -> (route: String, available: [String]) { state }
  func requestRoute(_ route: String) -> Bool {
    guard state.available.contains(route) else { return false }
    requestedRoutes.append(route)
    state.route = route
    return true
  }
}

final class MemoryCallCapability: NativeCallCapabilityPersisting {
  var enabled: Bool
  var failWrites = false
  init(enabled: Bool) { self.enabled = enabled }
  func setEnabled(_ enabled: Bool) -> Bool {
    guard !failWrites else { return false }
    self.enabled = enabled
    return true
  }
}
