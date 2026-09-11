import Foundation
import XCTest
#if canImport(Runner)
@testable import Runner
#endif

final class MknoonCallDiagnosticSpoolTests: XCTestCase {
  private final class Memory: MknoonCallDiagnosticBackend {
    var data: Data?
    var fail = false
    var writes = 0
    func read() throws -> Data? { data }
    func replace(_ data: Data) throws {
      if fail { throw CocoaError(.fileWriteUnknown) }
      self.data = data; writes += 1
    }
  }
  private let handle = "123e4567-e89b-42d3-a456-426614174000"
  private let trace = "223e4567-e89b-42d3-a456-426614174001"
  private func events(_ store: MknoonCallDiagnosticSpool) -> [[String: Any]] { store.drain(64)["events"] as! [[String: Any]] }

  func testQueuedCallObservationsShareWriteAndPreserveTerminalAndBinding() {
    let memory = Memory()
    let active = MknoonCallDiagnosticSpool(backend: memory)
    XCTAssertTrue(active.configure(true)); XCTAssertTrue(active.bind(handle, traceId: trace))
    let writes = memory.writes
    for _ in 0..<63 { XCTAssertTrue(active.append(handle: handle, stage: "audio", action: "snapshot", outcome: "ok", deferPersistence: true)) }
    XCTAssertTrue(active.append(handle: handle, stage: "terminal", action: "commit", outcome: "ok", deferPersistence: true))
    XCTAssertEqual(memory.writes, writes); XCTAssertTrue(active.persistPending()); XCTAssertEqual(memory.writes, writes + 1)
    let rows = events(active); XCTAssertEqual(rows.count, 64); XCTAssertEqual(rows.last?["stage"] as? String, "terminal")
    XCTAssertTrue(rows.allSatisfy { $0["traceId"] as? String == trace })
  }
  func testDeferredSinkFailureDropsOnlyUncommittedObservations() {
    let memory = Memory()
    let active = MknoonCallDiagnosticSpool(backend: memory); XCTAssertTrue(active.configure(true))
    active.append(handle: handle, stage: "answer", action: "commit", outcome: "ok")
    for _ in 0..<64 { active.append(handle: handle, stage: "audio", action: "snapshot", outcome: "ok", deferPersistence: true) }
    memory.fail = true; XCTAssertFalse(active.persistPending())
    XCTAssertEqual(events(active).count, 1); XCTAssertEqual(active.drain(64)["droppedEvents"] as? Int, 64)
  }
  func testOptOutBeforeQueuedFlushCannotResurrectCallEvidence() {
    let memory = Memory()
    let active = MknoonCallDiagnosticSpool(backend: memory); XCTAssertTrue(active.configure(true, consentEpoch: 10))
    active.append(handle: handle, stage: "answer", action: "commit", outcome: "ok", deferPersistence: true); active.recordDropped(20)
    XCTAssertTrue(active.configure(false, consentEpoch: 11)); XCTAssertTrue(active.persistPending())
    XCTAssertTrue(events(MknoonCallDiagnosticSpool(backend: memory)).isEmpty); XCTAssertEqual(active.drain(64)["droppedEvents"] as? Int, 0)
  }
  func testDeferredAppendReplacesExpiredBindingBeforeRecordingFreshCall() {
    var now: Int64 = 1_900_000_000_000
    let active = MknoonCallDiagnosticSpool(backend: Memory(), now: { now }, elapsed: { 1 })
    XCTAssertTrue(active.configure(true)); XCTAssertTrue(active.bind(handle, traceId: trace))
    now += MknoonCallDiagnosticSpool.retentionMs + 1
    active.append(handle: handle, stage: "answer", action: "commit", outcome: "ok", deferPersistence: true)
    XCTAssertTrue(active.persistPending())
    let fresh = events(active).first?["traceId"] as? String
    XCTAssertNotEqual(fresh, trace); XCTAssertEqual(active.lookup(handle)["traceId"] as? String, fresh)
    active.append(handle: handle, stage: "audio", action: "activate", outcome: "ok", deferPersistence: true)
    XCTAssertTrue(active.persistPending()); XCTAssertTrue(events(active).allSatisfy { $0["traceId"] as? String == fresh })
  }

  func testBuildIsStampedAtCreationAndNeverRewrittenOnRestart() {
    let memory = Memory()
    let original = MknoonCallDiagnosticSpool(backend: memory, installedBuild: "1.2.3+100")
    XCTAssertTrue(original.configure(true)); original.append(handle: handle, stage: "push", action: "receive", outcome: "ok")
    XCTAssertEqual(events(original).first?["build"] as? String, "1.2.3+100")
    let upgraded = MknoonCallDiagnosticSpool(backend: memory, installedBuild: "1.2.4+101")
    XCTAssertEqual(events(upgraded).first?["build"] as? String, "1.2.3+100")
    upgraded.append(handle: handle, stage: "push", action: "receive", outcome: "ok")
    XCTAssertEqual(events(upgraded).last?["build"] as? String, "1.2.4+101")
    let legacyMemory = Memory()
    let storedLegacy = MknoonCallDiagnosticSpool(backend: legacyMemory)
    XCTAssertTrue(storedLegacy.configure(true)); storedLegacy.append(handle: handle, stage: "push", action: "receive", outcome: "ok")
    XCTAssertNil(events(MknoonCallDiagnosticSpool(backend: legacyMemory, installedBuild: "1.2.4+101")).first?["build"])
    let invalid = MknoonCallDiagnosticSpool(backend: Memory(), installedBuild: "private error / token")
    XCTAssertTrue(invalid.configure(true)); invalid.append(handle: handle, stage: "push", action: "receive", outcome: "ok")
    XCTAssertNil(events(invalid).first?["build"])
  }
  func testTerminalCommandReasonNeverInventsAUserAction() {
    XCTAssertEqual(MknoonCallDiagnosticSpool.journalReason(.endRequested, context: ["cause": "no_answer"]), "no_answer")
    XCTAssertEqual(MknoonCallDiagnosticSpool.journalReason(.endRequested, context: ["cause": "local_user"]), "local_user")
    for input: [String: Any] in [[:], ["cause": "none"], ["cause": "private error"]] {
      XCTAssertEqual(MknoonCallDiagnosticSpool.journalReason(.endRequested, context: input), "unknown")
    }
  }
  func testDefaultOffOptOutErasesBindingsAndEvents() throws {
    let memory = Memory(), store = MknoonCallDiagnosticSpool(backend: Memory())
    store.append(handle: handle, stage: "push", action: "receive", outcome: "ok")
    XCTAssertTrue(events(store).isEmpty)
    XCTAssertFalse(store.bind(handle, traceId: trace))
    let enabled = MknoonCallDiagnosticSpool(backend: memory)
    XCTAssertTrue(enabled.configure(true)); XCTAssertTrue(enabled.bind(handle, traceId: trace))
    enabled.append(handle: handle, stage: "answer", action: "commit", outcome: "ok")
    XCTAssertEqual(events(enabled).first?["traceId"] as? String, trace)
    XCTAssertTrue(enabled.configure(false))
    XCTAssertTrue(events(MknoonCallDiagnosticSpool(backend: memory)).isEmpty)
    XCTAssertFalse(String(data: try XCTUnwrap(memory.data), encoding: .utf8)!.contains(handle))
  }
  func testRestartRetainsUnackedEventsAndRecordsUnknownInterruption() throws {
    let memory = Memory()
    let initial = MknoonCallDiagnosticSpool(backend: memory)
    XCTAssertTrue(initial.configure(true)); XCTAssertTrue(initial.bind(handle, traceId: trace))
    initial.append(handle: handle, stage: "answer", action: "commit", outcome: "ok")
    let first = try XCTUnwrap(events(initial).first)
    let recovered = MknoonCallDiagnosticSpool(backend: memory)
    XCTAssertEqual(events(recovered).first?["eventId"] as? String, first["eventId"] as? String)
    XCTAssertEqual(events(recovered).last?["reason"] as? String, "interrupted_before_final_record")
    XCTAssertTrue(recovered.ack([first["eventId"] as! String]))
    recovered.append(handle: handle, stage: "audio", action: "activate", outcome: "ok")
    XCTAssertEqual(events(recovered).last?["traceId"] as? String, trace)
  }
  func testAckFailureRetainsBatchAndSinkFailureDoesNotEscape() {
    let memory = Memory()
    let initial = MknoonCallDiagnosticSpool(backend: memory)
    XCTAssertTrue(initial.configure(true))
    initial.append(handle: handle, stage: "answer", action: "commit", outcome: "ok")
    let id = events(initial).first!["eventId"] as! String
    memory.fail = true
    XCTAssertFalse(initial.ack([id]))
    XCTAssertEqual(events(initial).first?["eventId"] as? String, id)
    initial.append(handle: handle, stage: "audio", action: "activate", outcome: "ok")
    XCTAssertEqual(events(initial).count, 1)
  }
  func testPrivateInputCannotReachOutputAndAuthorityIdentityCannotBeTrace() throws {
    let store = MknoonCallDiagnosticSpool(backend: Memory())
    XCTAssertTrue(store.configure(true)); XCTAssertFalse(store.bind(handle, traceId: handle))
    store.append(handle: handle, stage: "secret-token", action: "private-error", outcome: "contact-name", reason: "10.1.2.3",
                 values: ["token": "private-token", "durationMs": 12, "connected": true, "route": "private-device"],
                 context: ["traceId": handle, "operationId": handle])
    let data = try JSONSerialization.data(withJSONObject: events(store))
    let output = String(data: data, encoding: .utf8)!
    for secret in [handle, "private-token", "private-device", "10.1.2.3", "contact-name", "private-error", "secret-token"] { XCTAssertFalse(output.contains(secret)) }
    XCTAssertTrue(output.contains("durationMs"))
  }
  func testRetentionAndPerAttemptCapsWithBoundedDrain() {
    var now: Int64 = 1_900_000_000_000
    let store = MknoonCallDiagnosticSpool(backend: Memory(), now: { now }, elapsed: { 1 })
    XCTAssertTrue(store.configure(true)); XCTAssertTrue(store.bind(handle, traceId: trace))
    for _ in 0..<300 { store.append(handle: handle, stage: "audio", action: "snapshot", outcome: "ok") }
    XCTAssertEqual(events(store).count, 64)
    XCTAssertGreaterThan(store.drain(1000)["droppedEvents"] as! Int, 0)
    var count = 0
    while !events(store).isEmpty { let batch = events(store); count += batch.count; XCTAssertTrue(store.ack(batch.map { $0["eventId"] as! String })) }
    XCTAssertLessThanOrEqual(count, 256)
    store.append(handle: handle, stage: "audio", action: "activate", outcome: "ok")
    now += MknoonCallDiagnosticSpool.retentionMs + 1
    XCTAssertTrue(events(store).isEmpty)
  }
  func testSharedBindingRetagsOnlyMatchingPrivateCall() {
    let store = MknoonCallDiagnosticSpool(backend: Memory()); XCTAssertTrue(store.configure(true))
    store.append(handle: handle, stage: "push", action: "receive", outcome: "ok")
    store.append(handle: UUID().uuidString.lowercased(), stage: "push", action: "receive", outcome: "ok")
    XCTAssertTrue(store.bind(handle, traceId: trace))
    XCTAssertEqual(events(store)[0]["traceId"] as? String, trace)
    XCTAssertNotEqual(events(store)[1]["traceId"] as? String, trace)
  }
  func testStaleConsentCannotReenableAfterDisableClearAndRestart() {
    let memory = Memory()
    let initial = MknoonCallDiagnosticSpool(backend: memory)
    XCTAssertTrue(initial.configure(true, consentEpoch: 10))
    XCTAssertTrue(initial.configure(false, consentEpoch: 11)); XCTAssertTrue(initial.clear())
    let recovered = MknoonCallDiagnosticSpool(backend: memory)
    XCTAssertFalse(recovered.configure(true, consentEpoch: 10))
    XCTAssertFalse(recovered.configure(true, consentEpoch: 11))
    XCTAssertFalse(recovered.configure(true))
    XCTAssertTrue(recovered.configure(false, consentEpoch: 11))
    recovered.append(handle: handle, stage: "audio", action: "activate", outcome: "ok")
    XCTAssertTrue(events(recovered).isEmpty)
    XCTAssertTrue(recovered.configure(true, consentEpoch: 12))
  }
  func testPushMetadataIsSeparateFromTheUnchangedAuthorityEnvelope() {
    let base: [AnyHashable: Any] = ["v": "1", "c": handle, "h": "private-wake", "w": "call", "e": "1900000000000"]
    var payload = base
    payload["diagnostics"] = ["schemaVersion": 1, "traceId": trace]
    let accepted = MknoonCallDiagnostics.pushMetadata(payload)
    XCTAssertEqual(accepted.1, trace)
    XCTAssertEqual(accepted.0 as NSDictionary, base as NSDictionary)
    for invalid: Any in ["private-token", ["schemaVersion": 1, "traceId": handle], ["schemaVersion": 1, "traceId": trace, "token": "secret"]] {
      payload["diagnostics"] = invalid
      let stripped = MknoonCallDiagnostics.pushMetadata(payload)
      XCTAssertNil(stripped.1)
      XCTAssertEqual(stripped.0 as NSDictionary, base as NSDictionary)
    }
  }
  func testFailedConsentWriteDisablesCaptureButSameRequestCanRetry() {
    let memory = Memory()
    let actual = MknoonCallDiagnosticSpool(backend: memory)
    memory.fail = true
    XCTAssertFalse(actual.configure(true, consentEpoch: 10))
    actual.append(handle: handle, stage: "answer", action: "commit", outcome: "ok")
    XCTAssertTrue(events(actual).isEmpty)
    memory.fail = false
    XCTAssertTrue(actual.configure(true, consentEpoch: 10))
    memory.fail = true
    XCTAssertFalse(actual.configure(false, consentEpoch: 11))
    actual.append(handle: handle, stage: "audio", action: "activate", outcome: "ok")
    XCTAssertTrue(events(actual).isEmpty)
    XCTAssertFalse(actual.configure(true, consentEpoch: 10))
    XCTAssertFalse(actual.configure(true, consentEpoch: 11))
    memory.fail = false
    XCTAssertTrue(actual.configure(false, consentEpoch: 11))
    XCTAssertTrue(events(MknoonCallDiagnosticSpool(backend: memory)).isEmpty)
  }
  func testLookupRetainsOnlyPrivateBindingAcrossAckRestartAndExpires() throws {
    var now: Int64 = 1_900_000_000_000
    let memory = Memory(), compact = "00112233445566778899aabbccddeeff"
    let initial = MknoonCallDiagnosticSpool(backend: memory, now: { now })
    XCTAssertNil(initial.lookup(compact)["traceId"])
    XCTAssertTrue(initial.configure(true, consentEpoch: 10))
    XCTAssertTrue(initial.bind(compact, traceId: trace))
    initial.append(handle: compact, stage: "push", action: "receive", outcome: "ok")
    XCTAssertTrue(initial.ack(events(initial).map { $0["eventId"] as! String }))
    let recovered = MknoonCallDiagnosticSpool(backend: memory, now: { now })
    let result = recovered.lookup("00112233-4455-6677-8899-aabbccddeeff")
    XCTAssertEqual(Set(result.keys), ["version", "traceId"])
    XCTAssertEqual(result["traceId"] as? String, trace)
    XCTAssertNil(recovered.lookup(handle)["traceId"])
    now += MknoonCallDiagnosticSpool.retentionMs + 1
    XCTAssertNil(recovered.lookup(compact)["traceId"])
    XCTAssertTrue(recovered.configure(false, consentEpoch: 11))
    XCTAssertNil(recovered.lookup(compact)["traceId"])
  }
  func testWireCausePreservesClosedNativeReasonAndIgnoresPrivateInput() throws {
    for wire in try nativeDiagnosticWireContexts().values {
      var expected = wire
      expected["reason"] = expected.removeValue(forKey: "cause")
      XCTAssertEqual(MknoonCallDiagnosticSpool.context(wire.merging(["private": "secret"]) { _, new in new }) as NSDictionary, expected as NSDictionary)
    }
    XCTAssertEqual(MknoonCallDiagnosticSpool.context(["reason": "resume_refresh"]) as NSDictionary,
                   ["reason": "resume_refresh"] as NSDictionary)
    XCTAssertTrue(MknoonCallDiagnosticSpool.context(["cause": "private-token"]).isEmpty)
  }
}

func nativeDiagnosticWireContexts() throws -> [String: [String: Any]] {
  let bundle = Bundle(for: MknoonCallDiagnosticSpoolTests.self).url(forResource: "wire_fixtures_v1", withExtension: "json")
  let hostOverride = ProcessInfo.processInfo.environment["MKNOON_CALL_DIAGNOSTIC_WIRE_FIXTURE"].map { URL(fileURLWithPath: $0) }
  let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("tool/call_diagnostics/wire_fixtures_v1.json")
  let raw = try JSONSerialization.jsonObject(with: Data(contentsOf: bundle ?? hostOverride ?? source)) as! [String: Any]
  return raw["contexts"] as! [String: [String: Any]]
}
