import XCTest
import Darwin
#if canImport(Runner)
@testable import Runner
#endif

final class MknoonAppDiagnosticSpoolTests: XCTestCase {
  private final class Memory: MknoonAppDiagnosticBackend {
    var data: Data?
    var fail = false
    var writes = 0
    func read() throws -> Data? { data }
    func replace(_ data: Data) throws { if fail { throw CocoaError(.fileWriteUnknown) }; self.data = data; writes += 1 }
  }
  private func spool(_ memory: Memory, now: @escaping () -> Int64 = { 1_900_000_000_000 }, build: String = "1.0.1+112") -> MknoonAppDiagnosticSpool {
    MknoonAppDiagnosticSpool(backend: memory, now: now, elapsed: { 500 }, installedBuild: build)
  }
  private func events(_ store: MknoonAppDiagnosticSpool) -> [[String: Any]] { store.drain()["events"] as? [[String: Any]] ?? [] }
  func testSlowWriterAdmissionIsBoundedAndRecoversWithoutBlockingControls() {
    let admission = MknoonAppDiagnosticAdmission()
    var queued: [() -> Void] = [], accepted = 0, dropped: Int64 = 0, control = false
    for _ in 0..<10_000 {
      admission.enqueue({ queued.append($0) }) { lost in accepted += 1; dropped += lost }
    }
    XCTAssertEqual(queued.count, 64)
    queued.append { control = true } // Consent/ACK bypass event admission.
    queued.forEach { $0() }; queued = []
    XCTAssertTrue(control); XCTAssertEqual(accepted, 64); XCTAssertEqual(dropped, 9_936)
    admission.enqueue({ queued.append($0) }) { _ in accepted += 1 }
    queued[0](); XCTAssertEqual(accepted, 65)
  }
  func testQueuedObservationsShareOneWriteAndControlPersistsCurrentState() {
    let memory = Memory()
    let active = spool(memory); XCTAssertTrue(active.configure(true, consentEpoch: 10))
    let initial = memory.writes
    for _ in 0..<64 { XCTAssertTrue(active.append("runtime", "bridge", "ok", deferPersistence: true)) }
    XCTAssertEqual(memory.writes, initial)
    XCTAssertTrue(active.persistPending()); XCTAssertEqual(memory.writes, initial + 1)
    XCTAssertEqual(events(active).count, 64)
    active.recordDropped(100)
    XCTAssertTrue(active.append("push", "receive", "ok", deferPersistence: true))
    XCTAssertTrue(active.configure(false, consentEpoch: 11))
    XCTAssertTrue(active.persistPending()); XCTAssertTrue(events(spool(memory)).isEmpty)
    XCTAssertEqual(active.drain()["droppedEvents"] as? Int64, 0)
  }
  func testFailedDeferredWriteRemainsRetryableAndCountsOverflow() {
    let memory = Memory()
    let active = spool(memory); XCTAssertTrue(active.configure(true, consentEpoch: 10))
    active.recordDropped(20)
    for _ in 0..<64 { active.append("push", "receive", "ok", deferPersistence: true) }
    memory.fail = true; XCTAssertFalse(active.persistPending())
    memory.fail = false; XCTAssertTrue(active.persistPending())
    XCTAssertEqual(events(active).count, 64); XCTAssertEqual(active.drain()["droppedEvents"] as? Int64, 20)
  }
  func testDefaultOffAndExplicitOffSurviveRestart() {
    let memory = Memory(), store = spool(Memory())
    XCTAssertFalse(store.append("push", "receive", "ok")); XCTAssertTrue(events(store).isEmpty)
    let active = spool(memory); XCTAssertTrue(active.configure(true, consentEpoch: 10)); active.append("push", "receive", "ok")
    XCTAssertTrue(active.configure(false, consentEpoch: 11)); XCTAssertTrue(active.clear())
    let recovered = spool(memory)
    XCTAssertFalse(recovered.configure(true, consentEpoch: 10)); XCTAssertFalse(recovered.configure(true, consentEpoch: 11)); XCTAssertFalse(recovered.configure(true, consentEpoch: nil))
    XCTAssertTrue(recovered.configure(false, consentEpoch: 11)); XCTAssertTrue(events(recovered).isEmpty)
    XCTAssertTrue(recovered.configure(true, consentEpoch: 12))
  }
  func testDrainPreservesAndFailedAckDoesNotDelete() {
    let memory = Memory()
    let active = spool(memory); _ = active.configure(true, consentEpoch: 10); active.append("startup", "launch", "started")
    let id = events(active)[0]["eventId"] as! String
    XCTAssertEqual(events(active)[0]["eventId"] as? String, id)
    memory.fail = true; XCTAssertFalse(active.ack([id])); XCTAssertEqual(events(active)[0]["eventId"] as? String, id)
    memory.fail = false; XCTAssertTrue(active.ack([id])); XCTAssertFalse(events(spool(memory)).contains { $0["eventId"] as? String == id })
  }
  func testUnclosedRunIsUnknownAndOriginalBuildSurvives() {
    let memory = Memory()
    let active = spool(memory); _ = active.configure(true, consentEpoch: 10); active.append("startup", "launch", "started")
    let recovered = spool(memory, build: "1.0.2+113")
    XCTAssertEqual(events(recovered).first?["build"] as? String, "1.0.1+112")
    XCTAssertEqual(events(recovered).last?["outcome"] as? String, "interrupted_unknown")
    XCTAssertFalse(events(recovered).contains { $0["reason"] as? String == "os_crash" })
  }
  func testFailedConsentWriteDisablesCaptureAndRetries() {
    let memory = Memory()
    let store = spool(memory); memory.fail = true
    XCTAssertFalse(store.configure(true, consentEpoch: 10)); XCTAssertFalse(store.append("push", "receive", "ok"))
    memory.fail = false; XCTAssertTrue(store.configure(true, consentEpoch: 10))
    memory.fail = true; XCTAssertFalse(store.configure(false, consentEpoch: 11)); XCTAssertFalse(store.append("push", "receive", "ok"))
    XCTAssertFalse(store.configure(true, consentEpoch: 10)); XCTAssertFalse(store.configure(true, consentEpoch: 11))
    memory.fail = false; XCTAssertTrue(store.configure(false, consentEpoch: 11)); XCTAssertTrue(events(spool(memory)).isEmpty)
  }
  func testRawValuesAndIdentifiersNeverExport() throws {
    let store = spool(Memory(), build: "/private/device/file"); _ = store.configure(true, consentEpoch: 10)
    XCTAssertTrue(store.append("runtime", "bridge", "failed", "unknown", values: ["error": "private-token", "path": "/private/file", "count": 2, "errorClass": "platform", "fingerprint": "secret"], traceId: "raw-peer-id"))
    let row = try XCTUnwrap(events(store).first), data = try JSONSerialization.data(withJSONObject: row)
    let text = String(data: data, encoding: .utf8)!
    for value in ["private-token", "/private", "raw-peer", "secret"] { XCTAssertFalse(text.contains(value)) }
    XCTAssertNil(row["traceId"]); XCTAssertEqual(row["build"] as? String, "unknown")
    XCTAssertFalse(store.append("private-text", "bridge", "failed")); XCTAssertFalse(store.ack(["raw-peer-id"]))
  }
  func testCapsAndRetentionCountDrops() throws {
    var now: Int64 = 1_900_000_000_000
    let memory = Memory()
    let active = spool(memory, now: { now }); _ = active.configure(true, consentEpoch: 10)
    for _ in 0..<400 { active.append("runtime", "snapshot", "ok") }
    let stored = try JSONSerialization.jsonObject(with: XCTUnwrap(memory.data)) as! [String: Any]
    XCTAssertLessThanOrEqual((stored["events"] as! [[String: Any]]).count, 256)
    XCTAssertLessThanOrEqual((active.drain(1000)["events"] as! [[String: Any]]).count, 64)
    XCTAssertGreaterThan(active.drain()["droppedEvents"] as! Int64, 0); XCTAssertLessThanOrEqual(memory.data!.count, MknoonAppDiagnosticSpool.maxBytes)
    now += MknoonAppDiagnosticSpool.retentionMs + 1; XCTAssertTrue(events(active).isEmpty)
  }
  func testOSReportTimeBuildConsentAndDedupAreTruthful() {
    var now: Int64 = 1_900_000_000_000
    let memory = Memory()
    let active = spool(memory, now: { now }); _ = active.configure(true, consentEpoch: 10); now += 10
    XCTAssertFalse(active.importOsReport(crash: true, timestamp: now, intervalStart: now - 11))
    XCTAssertTrue(active.importOsReport(crash: true, timestamp: now, intervalStart: now - 5, signal: 11, reportBuild: "112"))
    XCTAssertFalse(active.importOsReport(crash: true, timestamp: now, intervalStart: now - 5, signal: 11, reportBuild: "112"))
    let row = events(active).last!, values = row["values"] as! [String: Any]
    XCTAssertEqual(row["reason"] as? String, "os_crash"); XCTAssertEqual(row["build"] as? String, "112")
    XCTAssertEqual(values["reportTimeIsIntervalEnd"] as? Bool, true); XCTAssertEqual(values["originalBuildKnown"] as? Bool, true)
    XCTAssertFalse(spool(memory, now: { now }).importOsReport(crash: true, timestamp: now, intervalStart: now - 5, signal: 11))
    _ = active.configure(false, consentEpoch: 11); now += 10; _ = active.configure(true, consentEpoch: 12)
    XCTAssertFalse(active.importOsReport(crash: false, timestamp: now - 1, durationMs: 500))
  }
  func testFailedOSWriteCanRecoverAfterRestart() {
    var now: Int64 = 1_900_000_000_000
    let memory = Memory()
    let active = spool(memory, now: { now }); _ = active.configure(true, consentEpoch: 10); now += 1
    memory.fail = true; XCTAssertFalse(active.importOsReport(crash: false, timestamp: now, durationMs: 500))
    memory.fail = false; let recovered = spool(memory, now: { now })
    XCTAssertTrue(recovered.importOsReport(crash: false, timestamp: now, durationMs: 500))
    XCTAssertEqual(events(recovered).filter { $0["reason"] as? String == "os_hang" }.count, 1)
  }
  func testFingerprintIgnoresPrivateMetadataAndExternalFrames() throws {
    func payload(_ secret: String) throws -> Data {
      try JSONSerialization.data(withJSONObject: ["message": secret, "frames": [
        ["binaryName": "Runner", "offsetIntoBinary": 123, "path": secret],
        ["binaryName": "PrivateLibrary", "offsetIntoBinary": 999, "message": secret]]])
    }
    let first = MknoonAppDiagnosticFingerprint.appFrames(try payload("private-token"))
    XCTAssertNotNil(first); XCTAssertEqual(first?.count, 64)
    XCTAssertEqual(first, MknoonAppDiagnosticFingerprint.appFrames(try payload("changed-private-path")))
    XCTAssertNil(MknoonAppDiagnosticFingerprint.appFrames(Data("{\"message\":\"secret\",\"binaryName\":\"UIKitCore\",\"offsetIntoBinary\":5}".utf8)))
    XCTAssertNil(MknoonAppDiagnosticFingerprint.appFrames(Data("{\"binaryName\":\"Runner\",\"offsetIntoBinary\":true}".utf8)))
  }
  func testBridgeClassifiesOnlyFixedCodesWithoutRawText() {
    let response = MknoonAppDiagnosticBridgeResponse.response("{\"ok\":false,\"errorCode\":\"DECRYPT_IO_ERROR\",\"errorMessage\":\"private-file\"}")
    XCTAssertEqual(response.0, "failed"); XCTAssertEqual(response.1, "io_failed")
    XCTAssertEqual(MknoonAppDiagnosticBridgeResponse.response("{\"ok\":false,\"errorCode\":\"DECRYPT_AUTH_ERROR\"}").1, "auth_failed")
    XCTAssertEqual(MknoonAppDiagnosticBridgeResponse.response("{\"ok\":false,\"errorCode\":\"private-secret\"}").1, "unknown")
    XCTAssertEqual(MknoonAppDiagnosticBridgeResponse.response("{\"ok\":1}").1, "malformed_response")
    XCTAssertEqual(MknoonAppDiagnosticBridgeResponse.response(String(repeating: "x", count: 16385)).0, "unknown")
    XCTAssertNil(MknoonAppDiagnosticBridgeResponse.operations["appDiagnosticsV1"])
  }
  func testOSReportsKeepSeparateTraceAndPersistentFingerprintDedup() {
    var now: Int64 = 1_900_000_000_000
    let memory = Memory(), fingerprint = String(repeating: "a", count: 64)
    let active = spool(memory, now: { now }); _ = active.configure(true, consentEpoch: 10); now += 10
    XCTAssertTrue(active.importOsReport(crash: true, timestamp: now, fingerprint: fingerprint))
    XCTAssertTrue(active.importOsReport(crash: true, timestamp: now, fingerprint: fingerprint, reportIndex: 1))
    let rows = events(active).filter { $0["stage"] as? String == "crash" }
    XCTAssertEqual(Set(rows.compactMap { $0["traceId"] as? String }).count, 2)
    XCTAssertFalse(spool(memory, now: { now }).importOsReport(crash: true, timestamp: now, fingerprint: fingerprint))
    XCTAssertFalse(spool(memory, now: { now }).importOsReport(crash: true, timestamp: now, fingerprint: fingerprint, reportIndex: 1))
  }
  func testCorruptedOptionalUUIDIsDroppedOnRecovery() throws {
    let memory = Memory()
    let store = spool(memory); _ = store.configure(true, consentEpoch: 10); store.append("push", "receive", "ok")
    var stored = try JSONSerialization.jsonObject(with: XCTUnwrap(memory.data)) as! [String: Any]
    var rows = stored["events"] as! [[String: Any]]; let id = rows[0]["eventId"] as! String
    rows[0]["reportingRunId"] = "raw-device-id"; stored["events"] = rows
    memory.data = try JSONSerialization.data(withJSONObject: stored)
    XCTAssertFalse(events(spool(memory)).contains { $0["eventId"] as? String == id })
  }
  private func inbox(_ directory: URL, now: @escaping () -> Int64 = { 1_900_000_000_000 }) -> MknoonNseAppDiagnosticInbox {
    MknoonNseAppDiagnosticInbox(directory: directory, now: now)
  }
  private func nseAppend(_ inbox: MknoonNseAppDiagnosticInbox, at: Int64 = 1_900_000_000_000,
                         began: Int64 = 1_900_000_000_000, trace: String = UUID().uuidString.lowercased(), build: String = "1.0.1+112") -> Bool {
    inbox.append(traceId: trace, runId: UUID().uuidString.lowercased(), beganAt: began, occurredAt: at, elapsedMs: 12,
                 build: build, stage: "receive", outcome: "ok", reason: "none")
  }
  func testNseDefaultOffAndSharedRevocationCannotBeReenabledByStaleEpoch() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let shared = inbox(directory)
    XCTAssertFalse(nseAppend(shared)); XCTAssertTrue(shared.configure(true, epoch: 10)); XCTAssertTrue(nseAppend(shared))
    XCTAssertTrue(shared.configure(false, epoch: 11)); XCTAssertFalse(nseAppend(shared))
    let otherProcess = inbox(directory)
    XCTAssertFalse(otherProcess.configure(true, epoch: 10)); XCTAssertFalse(otherProcess.configure(true, epoch: 11))
    XCTAssertEqual(otherProcess.drain()?.events.count, 0)
  }
  func testNseOldCallbackCannotReturnAfterClearAndNewConsent() throws {
    var now: Int64 = 1_900_000_000_000
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let shared = inbox(directory, now: { now }); XCTAssertTrue(shared.configure(true, epoch: 10))
    let began = now; now += 10
    XCTAssertTrue(shared.configure(false, epoch: 11)); XCTAssertTrue(shared.clear()); now += 10
    XCTAssertTrue(shared.configure(true, epoch: 12))
    XCTAssertFalse(nseAppend(shared, at: now, began: began))
    XCTAssertTrue(nseAppend(shared, at: now, began: now))
  }
  func testNseImportPreservesIdentityBuildAndOnlyAcksAfterDurableWrite() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let shared = inbox(directory); XCTAssertTrue(shared.configure(true, epoch: 10)); XCTAssertTrue(nseAppend(shared))
    let page = try XCTUnwrap(shared.drain()), row = try XCTUnwrap(page.events.first), memory = Memory()
    let app = spool(memory, build: "1.0.2+113"); XCTAssertTrue(app.configure(true, consentEpoch: 10))
    memory.fail = true; XCTAssertNil(app.importEvents(page.events)); XCTAssertEqual(shared.drain()?.events.count, 1)
    memory.fail = false; let ids = try XCTUnwrap(app.importEvents(page.events)); XCTAssertTrue(shared.ack(ids))
    let imported = try XCTUnwrap(events(app).first)
    for key in ["eventId", "traceId", "runId", "build"] { XCTAssertEqual(imported[key] as? String, row[key] as? String) }
    XCTAssertEqual(imported["occurredAtMs"] as? Int64, row["occurredAtMs"] as? Int64)
    XCTAssertEqual((imported["values"] as? [String: Any])?["extensionProcess"] as? Bool, true)
    XCTAssertEqual(shared.drain()?.events.count, 0); XCTAssertEqual(events(app).count, 1)
  }
  func testNseLockContentionNeverBlocksOrChangesConsent() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let shared = inbox(directory); XCTAssertTrue(shared.configure(true, epoch: 10))
    let lock = open(directory.appendingPathComponent("inbox.lock").path, O_RDWR)
    XCTAssertGreaterThanOrEqual(lock, 0); defer { flock(lock, LOCK_UN); close(lock) }
    XCTAssertEqual(flock(lock, LOCK_EX | LOCK_NB), 0)
    XCTAssertFalse(nseAppend(shared)); XCTAssertFalse(shared.configure(false, epoch: 11)); XCTAssertNil(shared.drain())
    flock(lock, LOCK_UN)
    XCTAssertTrue(shared.configure(false, epoch: 11)); XCTAssertFalse(nseAppend(shared))
  }
  func testNsePrivacyAndQuotaAreIndependentFromMainSpool() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let shared = inbox(directory); XCTAssertTrue(shared.configure(true, epoch: 10))
    XCTAssertFalse(nseAppend(shared, trace: "raw-message-id"))
    for _ in 0..<110 { XCTAssertTrue(nseAppend(shared, build: "/private/device/path")) }
    let page = try XCTUnwrap(shared.drain())
    XCTAssertLessThanOrEqual(page.events.count, 64); XCTAssertGreaterThan(page.dropped, 0)
    XCTAssertTrue(page.events.allSatisfy { $0["build"] as? String == "unknown" })
    let size = try directory.appendingPathComponent("inbox-v1.json").resourceValues(forKeys: [.fileSizeKey]).fileSize!
    XCTAssertLessThanOrEqual(size, MknoonNseAppDiagnosticInbox.maxBytes)
    XCTAssertEqual(MknoonNseAppDiagnosticInbox.maxBytes + MknoonAppDiagnosticSpool.maxBytes, 1_048_576)
  }
  func testVocabularyMatchesCanonicalSchema() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let data = try Data(contentsOf: root.appendingPathComponent("tool/app_diagnostics/schema_v1.json"))
    let schema = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    let copies: [String: Set<String>] = ["required": MknoonAppDiagnosticSchema.required, "optional": MknoonAppDiagnosticSchema.optional,
      "feature": MknoonAppDiagnosticSchema.feature, "stage": MknoonAppDiagnosticSchema.stage, "outcome": MknoonAppDiagnosticSchema.outcome,
      "reason": MknoonAppDiagnosticSchema.reason, "booleanValues": MknoonAppDiagnosticSchema.booleanValues,
      "integerValues": MknoonAppDiagnosticSchema.integerValues, "hashValues": MknoonAppDiagnosticSchema.hashValues, "uuidFields": MknoonAppDiagnosticSchema.uuidFields]
    for (key, copy) in copies { XCTAssertEqual(copy, Set(schema[key] as! [String])) }
    let enums = schema["enumValues"] as! [String: [String]]
    XCTAssertEqual(Set(enums.keys), Set(MknoonAppDiagnosticSchema.enumValues.keys))
    for (key, copy) in MknoonAppDiagnosticSchema.enumValues { XCTAssertEqual(copy, Set(enums[key]!)) }
  }
}
