import Foundation
import XCTest

@testable import Runner

final class PendingNativeCallStoreTests: XCTestCase {
  private let now: Int64 = 1_900_000_000_000
  private let callA = UUID(uuidString: "123e4567-e89b-42d3-a456-426614174000")!
  private let callB = UUID(uuidString: "323e4567-e89b-42d3-a456-426614174002")!

  func testOneDescriptorDuplicateAdoptionAndBusyRejection() throws {
    let backend = MemoryPendingCallBackend()
    let store = makeStore(backend)

    guard case let .created(created) = store.create(payload(callA)) else {
      return XCTFail("expected create")
    }
    XCTAssertEqual(created.direction, .incoming)
    guard case let .duplicate(duplicate) = store.create(payload(callA)) else {
      return XCTFail("expected duplicate")
    }
    XCTAssertEqual(duplicate, created)
    guard case let .busy(active) = store.create(payload(callB)) else {
      return XCTFail("expected busy")
    }
    XCTAssertEqual(active.nativeCallId, callA)
    XCTAssertEqual(backend.descriptorWriteCount, 1)
  }

  func testOrderedEventsPersistAcrossRecreationAndTerminalDominatesAnswer() throws {
    let backend = MemoryPendingCallBackend()
    let store = makeStore(backend)
    _ = store.create(payload(callA))
    assertAppended(store.append(nativeCallId: callA, type: .presented), sequence: 1)
    assertAppended(store.append(nativeCallId: callA, type: .answerRequested), sequence: 2)
    assertAppended(store.append(nativeCallId: callA, type: .remoteCancelled), sequence: 3)

    let reopened = makeStore(backend)
    let snapshot = try XCTUnwrap(reopened.snapshot())
    XCTAssertEqual(snapshot.events.map(\.sequence), [1, 2, 3])
    XCTAssertEqual(snapshot.events.map(\.type), [.presented, .answerRequested, .remoteCancelled])
    XCTAssertEqual(snapshot.terminalEvent?.type, .remoteCancelled)
    XCTAssertTrue(snapshot.answerRequested)
    guard case .ignoredAfterTerminal = reopened.append(nativeCallId: callA, type: .audioActivated)
    else { return XCTFail("terminal must dominate") }
  }

  func testPartialAndAdoptionAcknowledgementsReplayOnlyUnconsumedEvents() throws {
    let backend = MemoryPendingCallBackend()
    let store = makeStore(backend)
    _ = store.create(payload(callA))
    _ = store.append(nativeCallId: callA, type: .presented)
    _ = store.append(nativeCallId: callA, type: .answerRequested)
    _ = store.append(nativeCallId: callA, type: .muteChanged, muted: true)

    XCTAssertTrue(store.acknowledge(
      nativeCallId: callA,
      highestConsumedSequence: 1,
      acknowledgement: .adopted
    ))
    var snapshot = try XCTUnwrap(makeStore(backend).snapshot())
    XCTAssertEqual(snapshot.phase, .journal)
    XCTAssertEqual(snapshot.handoffAcknowledgement, .adopted)
    XCTAssertEqual(snapshot.wakeHandle, "")
    XCTAssertEqual(snapshot.events.map(\.sequence), [2, 3])

    XCTAssertTrue(makeStore(backend).acknowledge(
      nativeCallId: callA,
      highestConsumedSequence: 2,
      acknowledgement: .none
    ))
    snapshot = try XCTUnwrap(makeStore(backend).snapshot())
    XCTAssertEqual(snapshot.events.map(\.sequence), [3])
    XCTAssertFalse(makeStore(backend).acknowledge(
      nativeCallId: callA,
      highestConsumedSequence: 2,
      acknowledgement: .none
    ) == false, "exact repeated high-water acknowledgement is idempotent")
    XCTAssertEqual(backend.deleteCount, 0)
  }

  func testConnectedMarkerPersistsIdempotentlyAndMissingLegacyFieldDecodesPending() throws {
    let backend = MemoryPendingCallBackend()
    let store = makeStore(backend)
    _ = store.createOutgoing(payload(callA))

    let encoded = try XCTUnwrap(backend.descriptor)
    let legacyShape = try XCTUnwrap(
      JSONSerialization.jsonObject(with: encoded) as? [String: Any]
    )
    XCTAssertNil(legacyShape["connectedAtMs"])
    XCTAssertNil(try XCTUnwrap(makeStore(backend).snapshot()).connectedAtMs)

    XCTAssertTrue(store.markConnected(nativeCallId: callA))
    let writesAfterFirstMark = backend.descriptorWriteCount
    XCTAssertEqual(try XCTUnwrap(makeStore(backend).snapshot()).connectedAtMs, now)

    XCTAssertTrue(makeStore(backend).markConnected(nativeCallId: callA))
    XCTAssertEqual(backend.descriptorWriteCount, writesAfterFirstMark)
  }

  func testTerminalAckWritesReceiptDeletesExactlyOnceAndFencesDuplicatePush() throws {
    let backend = MemoryPendingCallBackend()
    let store = makeStore(backend)
    _ = store.create(payload(callA))
    _ = store.append(nativeCallId: callA, type: .presented)
    _ = store.append(nativeCallId: callA, type: .declineRequested)

    XCTAssertTrue(store.acknowledge(
      nativeCallId: callA,
      highestConsumedSequence: 2,
      acknowledgement: .terminal
    ))
    XCTAssertNil(store.snapshot())
    XCTAssertEqual(backend.deleteCount, 1)
    XCTAssertTrue(makeStore(backend).acknowledge(
      nativeCallId: callA,
      highestConsumedSequence: 2,
      acknowledgement: .terminal
    ))
    XCTAssertEqual(backend.deleteCount, 1)
    guard case .duplicate(nil) = makeStore(backend).create(payload(callA)) else {
      return XCTFail("receipt must fence duplicate wake")
    }
  }

  func testTerminalEventRemainsAdmissibleAtBoundAndPersistenceFailuresFailClosed() throws {
    let backend = MemoryPendingCallBackend()
    let store = makeStore(backend)
    _ = store.create(payload(callA))
    for index in 0..<PendingNativeCallStore.maxEvents {
      let type: PendingNativeCallEventType = index == 0 ? .presented : .routeChanged
      assertAppended(store.append(nativeCallId: callA, type: type), sequence: Int64(index + 1))
    }
    guard case .capacityReached = store.append(
      nativeCallId: callA,
      type: .muteChanged,
      muted: true
    )
    else { return XCTFail("non-terminal bound") }
    assertAppended(
      store.append(nativeCallId: callA, type: .expired),
      sequence: Int64(PendingNativeCallStore.maxEvents + 1)
    )
    XCTAssertEqual(try XCTUnwrap(store.snapshot()).events.map(\.type), [.expired])

    let failing = MemoryPendingCallBackend()
    failing.failWrites = true
    guard case .persistenceFailure = makeStore(failing).create(payload(callB)) else {
      return XCTFail("durability failure must fail closed")
    }
    XCTAssertNil(failing.descriptor)
  }

  func testRunnerBackendUsesAtomicAfterFirstUnlockProtection() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "vc205-store-\(UUID().uuidString)",
      isDirectory: true
    )
    defer { try? FileManager.default.removeItem(at: directory) }
    var attributeRequests: [(path: String, protection: FileProtectionType?, mode: Int?)] = []
    var writeOptions: [Data.WritingOptions] = []
    let fileManager = FileManager.default
    let backend = try RunnerPendingNativeCallFileBackend(
      fileManager: fileManager,
      directory: directory,
      attributeSetter: { attributes, path in
        attributeRequests.append((
          path,
          attributes[.protectionKey] as? FileProtectionType,
          (attributes[.posixPermissions] as? NSNumber)?.intValue
            ?? attributes[.posixPermissions] as? Int
        ))
        try fileManager.setAttributes(attributes, ofItemAtPath: path)
      },
      atomicWriter: { data, url, options in
        writeOptions.append(options)
        try data.write(to: url, options: options)
      }
    )
    let data = Data("protected".utf8)
    try backend.replaceDescriptor(with: data)
    XCTAssertEqual(try backend.readDescriptor(), data)
    let url = directory.appendingPathComponent("pending-call-v1.json")
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    XCTAssertEqual(
      RunnerPendingNativeCallFileBackend.protectionType,
      .completeUntilFirstUserAuthentication
    )
    XCTAssertEqual(writeOptions, [[.atomic]])
    XCTAssertEqual(attributeRequests.count, 2)
    XCTAssertEqual(attributeRequests[0].path, directory.path)
    XCTAssertEqual(attributeRequests[0].protection, .completeUntilFirstUserAuthentication)
    XCTAssertEqual(attributeRequests[0].mode, 0o700)
    XCTAssertEqual(attributeRequests[1].path, url.path)
    XCTAssertEqual(attributeRequests[1].protection, .completeUntilFirstUserAuthentication)
    XCTAssertEqual(attributeRequests[1].mode, 0o600)
    // CoreSimulator filesystems may omit the protection attribute even after
    // accepting it. The recording seam above proves the exact production call;
    // validate the OS readback too whenever CoreSimulator surfaces it.
    if let protection = attributes[.protectionKey] as? FileProtectionType {
      XCTAssertEqual(protection, .completeUntilFirstUserAuthentication)
    }
    XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    try backend.replaceDescriptor(with: nil)
    XCTAssertNil(try backend.readDescriptor())
  }

  func testTerminalReplayRetentionSurvivesRecreationThenSweepsAndAllowsNextCall() throws {
    let backend = MemoryPendingCallBackend()
    var clock = now
    let store = PendingNativeCallStore(backend: backend, nowMs: { clock })
    _ = store.create(payload(callA, receivedAtMs: clock))
    _ = store.append(nativeCallId: callA, type: .presented)
    _ = store.append(nativeCallId: callA, type: .remoteCancelled)
    let terminal = try XCTUnwrap(store.snapshot())
    XCTAssertEqual(
      terminal.terminalRetentionDeadlineMs,
      now + PendingNativeCallStore.terminalReplayRetentionMs
    )

    clock += PendingNativeCallStore.terminalReplayRetentionMs - 1
    let beforeDeadline = PendingNativeCallStore(backend: backend, nowMs: { clock })
    guard case .busy = beforeDeadline.create(payload(callB, receivedAtMs: clock)) else {
      return XCTFail("a live unacknowledged terminal must retain replay custody")
    }
    XCTAssertEqual(beforeDeadline.snapshot()?.nativeCallId, callA)

    clock += 1
    let afterDeadline = PendingNativeCallStore(backend: backend, nowMs: { clock })
    guard case let .created(created) = afterDeadline.create(payload(callB, receivedAtMs: clock)) else {
      return XCTFail("expired terminal retention must release custody")
    }
    XCTAssertEqual(created.nativeCallId, callB)
    XCTAssertEqual(backend.deleteCount, 1)
    guard case .duplicate(nil) = afterDeadline.create(payload(callA, receivedAtMs: clock)) else {
      return XCTFail("receipt must fence the swept terminal call")
    }
  }

  private func makeStore(_ backend: MemoryPendingCallBackend) -> PendingNativeCallStore {
    PendingNativeCallStore(backend: backend, nowMs: { self.now })
  }

  private func payload(_ id: UUID, receivedAtMs: Int64? = nil) -> VoipWakePayload {
    let receivedAtMs = receivedAtMs ?? now
    return VoipWakePayload(
      nativeCallId: id,
      callHandle: id.uuidString.lowercased(),
      wakeHandle: "223e4567-e89b-42d3-a456-426614174001",
      receivedAtMs: receivedAtMs,
      expiresAtMs: receivedAtMs + 30_000
    )
  }

  private func assertAppended(
    _ result: PendingNativeCallAppendResult,
    sequence: Int64,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    guard case let .appended(_, event) = result else {
      XCTFail("expected append", file: file, line: line)
      return
    }
    XCTAssertEqual(event.sequence, sequence, file: file, line: line)
  }
}

final class MemoryPendingCallBackend: PendingNativeCallBackend {
  var descriptor: Data?
  var receipts: Data?
  var failReads = false
  var failWrites = false
  var descriptorWriteCount = 0
  var deleteCount = 0

  func readDescriptor() throws -> Data? {
    if failReads { throw CocoaError(.fileReadUnknown) }
    return descriptor
  }

  func replaceDescriptor(with data: Data?) throws {
    if failWrites { throw CocoaError(.fileWriteUnknown) }
    descriptorWriteCount += 1
    if data == nil, descriptor != nil { deleteCount += 1 }
    descriptor = data
  }

  func readAcknowledgementReceipts() throws -> Data? {
    if failReads { throw CocoaError(.fileReadUnknown) }
    return receipts
  }

  func replaceAcknowledgementReceipts(with data: Data?) throws {
    if failWrites { throw CocoaError(.fileWriteUnknown) }
    receipts = data
  }
}
