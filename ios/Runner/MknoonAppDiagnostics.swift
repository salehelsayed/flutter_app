import Foundation
import CoreFoundation
import CryptoKit
#if canImport(Flutter)
import Flutter
#endif
#if os(iOS)
import MetricKit
#endif

internal protocol MknoonAppDiagnosticBackend {
  func read() throws -> Data?
  func replace(_ data: Data) throws
}

internal enum MknoonAppDiagnosticBridgeResponse {
  static let operations = ["startNode": "node_start", "stopNode": "node_stop", "relayReconnect": "relay_reconnect", "relayProbe": "relay_probe",
    "connectToPeer": "peer_dial", "disconnectPeer": "peer_disconnect", "nodeStatus": "other", "blobDecrypt": "other", "blobEncrypt": "other"]
  static func response(_ value: Any?) -> (String, String) {
    if let text = value as? String, text.utf8.count > 16384 { return ("unknown", "unknown") }
    guard let text = value as? String, text.utf8.count <= 16384, let data = text.data(using: .utf8),
          let row = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let ok = row["ok"] as? NSNumber, CFGetTypeID(ok) == CFBooleanGetTypeID() else { return ("failed", "malformed_response") }
    if ok.boolValue { return ("ok", "none") }
    let reason: String
    switch row["errorCode"] as? String {
    case "DECRYPT_AUTH_ERROR": reason = "auth_failed"
    case "DECRYPT_METADATA_ERROR": reason = "metadata_invalid"
    case "DECRYPT_IO_ERROR": reason = "io_failed"
    case "NOT_INITIALIZED", "GO_RUNTIME_NOT_ACTIVE": reason = "bridge_rejected"
    default: reason = "unknown"
    }
    return ("failed", reason)
  }
}

internal enum MknoonAppDiagnosticFingerprint {
  static func appFrames(_ data: Data) -> String? {
    guard data.count <= 262_144, let root = try? JSONSerialization.jsonObject(with: data) else { return nil }
    var frames: [String] = [], visited = 0
    func visit(_ node: Any, depth: Int) {
      guard depth <= 64, visited < 4096, frames.count < 64 else { return }
      visited += 1
      if let row = node as? [String: Any] {
        if let binary = row["binaryName"] as? String, ["Runner", "App", "GoMknoon"].contains(binary),
           let offset = MknoonAppDiagnosticSpool.integer(row["offsetIntoBinary"]) { frames.append("\(binary):\(offset)") }
        for key in row.keys.sorted() { visit(row[key]!, depth: depth + 1) }
      } else if let rows = node as? [Any] { for row in rows { visit(row, depth: depth + 1) } }
    }
    visit(root, depth: 0)
    guard !frames.isEmpty else { return nil }
    return SHA256.hash(data: Data(frames.joined(separator: "\n").utf8)).map { String(format: "%02x", $0) }.joined()
  }
}

internal final class MknoonAppDiagnosticFileBackend: MknoonAppDiagnosticBackend {
  private let file: URL
  init(directory: URL? = nil) throws {
    var root = try directory ?? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
      appropriateFor: nil, create: true).appendingPathComponent("MknoonAppDiagnostics", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    var resources = URLResourceValues(); resources.isExcludedFromBackup = true
    try root.setResourceValues(resources)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
#if os(iOS)
    try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: root.path)
#endif
    file = root.appendingPathComponent("diagnostics-v1.json")
  }
  func read() throws -> Data? {
    guard FileManager.default.fileExists(atPath: file.path) else { return nil }
    let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
    guard size <= MknoonAppDiagnosticSpool.maxBytes else { throw CocoaError(.fileReadCorruptFile) }
    return try Data(contentsOf: file)
  }
  func replace(_ data: Data) throws {
#if os(iOS)
    try data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
#else
    try data.write(to: file, options: .atomic)
#endif
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
  }
}

internal final class MknoonAppDiagnosticSpool {
  static let maxBytes = 786_432 // Remaining 256 KiB belongs to the separate NSE inbox.
  static let retentionMs: Int64 = 7 * 24 * 60 * 60 * 1000
  private let backend: MknoonAppDiagnosticBackend
  private let now: () -> Int64
  private let elapsed: () -> Int64
  private let installedBuild: String
  let runId = UUID().uuidString.lowercased()
  private var state: [String: Any] = ["enabled": false, "sequence": Int64(0), "dropped": Int64(0)]
  private var events: [[String: Any]] = []
  private var osReports: [String] = []
  private var loaded = false
  static func integer(_ value: Any?) -> Int64? {
    guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue.isFinite,
          number.doubleValue.rounded() == number.doubleValue, number.doubleValue >= 0,
          number.doubleValue <= 9_007_199_254_740_991 else { return nil }
    return number.int64Value
  }
  static func uuid(_ value: String?) -> Bool {
    guard let value else { return false }
    return value.range(of: "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89aAbB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$", options: .regularExpression) != nil
  }
  static func build(_ value: String) -> String {
    value.utf8.count <= 80 && value.range(of: "^[A-Za-z0-9._+()-]+$", options: .regularExpression) != nil ? value : "unknown"
  }
  static func values(_ raw: [String: Any]) -> [String: Any] {
    var safe: [String: Any] = [:]
    for key in raw.keys.sorted().prefix(16) {
      let value = raw[key]!
      if MknoonAppDiagnosticSchema.booleanValues.contains(key), let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() { safe[key] = number.boolValue }
      else if MknoonAppDiagnosticSchema.integerValues.contains(key), let number = integer(value) { safe[key] = number }
      else if let text = value as? String, MknoonAppDiagnosticSchema.enumValues[key]?.contains(text) == true { safe[key] = text }
      else if MknoonAppDiagnosticSchema.hashValues.contains(key), let text = value as? String, text.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil { safe[key] = text }
    }
    return safe
  }
  private static func valid(_ event: [String: Any]) -> Bool {
    let keys = Set(event.keys)
    guard keys.isSuperset(of: MknoonAppDiagnosticSchema.required), keys.isSubset(of: MknoonAppDiagnosticSchema.required.union(MknoonAppDiagnosticSchema.optional)),
          integer(event["schemaVersion"]) == 1, event["source"] as? String == "ios", event["platform"] as? String == "ios",
          uuid(event["eventId"] as? String), uuid(event["runId"] as? String), MknoonAppDiagnosticSchema.uuidFields.allSatisfy({ event[$0] == nil || uuid(event[$0] as? String) }),
          let feature = event["feature"] as? String, MknoonAppDiagnosticSchema.feature.contains(feature),
          let stage = event["stage"] as? String, MknoonAppDiagnosticSchema.stage.contains(stage),
          let outcome = event["outcome"] as? String, MknoonAppDiagnosticSchema.outcome.contains(outcome),
          let reason = event["reason"] as? String, MknoonAppDiagnosticSchema.reason.contains(reason),
          ["sequence", "occurredAtMs", "elapsedMs"].allSatisfy({ integer(event[$0]) != nil }),
          let stamp = event["build"] as? String, build(stamp) == stamp,
          let fields = event["values"] as? [String: Any], values(fields).count == fields.count,
          let data = try? JSONSerialization.data(withJSONObject: event), data.count <= 4096 else { return false }
    return true
  }
  init(backend: MknoonAppDiagnosticBackend,
       now: @escaping () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) },
       elapsed: @escaping () -> Int64 = { Int64(ProcessInfo.processInfo.systemUptime * 1000) }, installedBuild: String = "unknown") {
    self.backend = backend; self.now = now; self.elapsed = elapsed; self.installedBuild = installedBuild
    do {
      if let data = try backend.read() {
        guard data.count <= Self.maxBytes, let stored = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              Self.integer(stored["version"]) == 1, let old = stored["state"] as? [String: Any],
              let rows = stored["events"] as? [[String: Any]] else { return }
        state = old; events = rows.filter(Self.valid)
        osReports = Array((stored["osReports"] as? [String] ?? []).filter { $0.count <= 160 && $0.range(of: "^[0-9a-f:]+$", options: .regularExpression) != nil }.prefix(128))
      }
      loaded = true
      if enabled {
        let interrupted = state["openRun"] as? Bool == true; state["openRun"] = true
        _ = append("runtime", "recover", interrupted ? "interrupted_unknown" : "ok", interrupted ? "interrupted_before_final_record" : "bootstrap")
      }
    } catch { /* No capture until a successful configure. */ }
  }
  var enabled: Bool { loaded && state["enabled"] as? Bool == true }
  func configure(_ value: Bool, consentEpoch: Int64?) -> Bool {
    let highest = Self.integer(state["consentEpoch"]) ?? 0
    if let consentEpoch {
      guard consentEpoch > 0, consentEpoch >= highest,
            consentEpoch != highest || (state["requested"] as? Bool ?? enabled) == value else { return false }
    } else if highest > 0 { return false }
    if !loaded { state = ["sequence": Int64(0), "dropped": Int64(0)]; events = []; osReports = [] }
    if value && state["requested"] as? Bool != true { state["enabledSince"] = now() }
    if let consentEpoch { state["consentEpoch"] = consentEpoch }
    loaded = true; state["requested"] = value; state["enabled"] = value; state["openRun"] = value
    if !value { events = []; osReports = []; state["dropped"] = Int64(0); state["enabledSince"] = Int64(0) }
    if !persist() { state["enabled"] = false; return false }
    return true
  }
  @discardableResult
  func append(_ feature: String, _ stage: String, _ outcome: String, _ reason: String = "none", values: [String: Any] = [:],
              traceId: String? = nil, occurredAt: Int64? = nil, eventBuild: String? = nil) -> Bool {
    guard enabled, MknoonAppDiagnosticSchema.feature.contains(feature), MknoonAppDiagnosticSchema.stage.contains(stage),
          MknoonAppDiagnosticSchema.outcome.contains(outcome), MknoonAppDiagnosticSchema.reason.contains(reason) else { return false }
    let sequence = Self.integer(state["sequence"]) ?? 0
    guard sequence < 9_007_199_254_740_991 else { return false }
    state["sequence"] = sequence + 1
    var event: [String: Any] = ["schemaVersion": 1, "eventId": UUID().uuidString.lowercased(), "runId": runId,
      "source": "ios", "platform": "ios", "sequence": sequence + 1, "occurredAtMs": max(0, occurredAt ?? now()), "elapsedMs": max(0, elapsed()),
      "feature": feature, "stage": stage, "outcome": outcome, "reason": reason, "build": Self.build(eventBuild ?? installedBuild), "values": Self.values(values)]
    if Self.uuid(traceId) { event["traceId"] = traceId!.lowercased() }
    guard Self.valid(event) else { return false }
    events.append(event); enforceCaps(); return persist()
  }
  func importOsReport(crash: Bool, timestamp: Int64, intervalStart: Int64? = nil, durationMs: Int64 = 0, signal: Int64 = 0, reportBuild: String? = nil, fingerprint: String? = nil, reportIndex: Int = 0) -> Bool {
    let since = Self.integer(state["enabledSince"]) ?? 0
    guard enabled, since > 0, (intervalStart ?? timestamp) >= since, timestamp >= (intervalStart ?? timestamp), timestamp <= now() else { return false }
    let safeFingerprint = (Self.values(["fingerprint": fingerprint as Any])["fingerprint"] as? String)
    let id = "\(timestamp):\(crash ? 1 : 2):\(max(0, durationMs)):\(max(0, signal)):\(min(15, max(0, reportIndex)))" + (safeFingerprint.map { ":\($0)" } ?? "")
    guard !osReports.contains(id) else { return false }
    osReports.append(id); osReports = Array(osReports.suffix(128))
    let stamp = reportBuild.map(Self.build) ?? "unknown"
    var fields: [String: Any] = ["reportDelayed": true, "originalBuildKnown": stamp != "unknown", "reportTimeIsIntervalEnd": intervalStart != nil, "durationMs": max(0, durationMs), "signal": max(0, signal)]
    if let safeFingerprint { fields["fingerprint"] = safeFingerprint }
    return append("runtime", crash ? "crash" : "hang", "failed", crash ? "os_crash" : "os_hang",
      values: fields, traceId: UUID().uuidString.lowercased(), occurredAt: timestamp, eventBuild: stamp)
  }
  /// Imported event identity, original run/time/build survive the process handoff.
  /// The caller ACKs the NSE inbox only after this write succeeds.
  func importEvents(_ rows: [[String: Any]]) -> [String]? {
    guard enabled, rows.count <= 64 else { return nil }
    var accepted: [String] = []
    for row in rows {
      guard let id = row["eventId"] as? String, Self.uuid(id) else { continue }
      accepted.append(id)
      guard Self.valid(row) else { state["dropped"] = (Self.integer(state["dropped"]) ?? 0) + 1; continue }
      if !events.contains(where: { $0["eventId"] as? String == id }) { events.append(row) }
    }
    enforceCaps()
    return persist() ? accepted : nil
  }
  func drain(_ limit: Int = 64) -> [String: Any] {
    enforceCaps()
    return ["version": 1, "events": Array(events.prefix(max(1, min(64, limit)))), "droppedEvents": Self.integer(state["dropped"]) ?? 0]
  }
  func ack(_ ids: [String]) -> Bool {
    guard ids.count <= 64, ids.allSatisfy(Self.uuid) else { return false }
    let previous = events; events.removeAll { ids.contains($0["eventId"] as? String ?? "") }
    if persist() { return true }
    events = previous; return false
  }
  func clear() -> Bool {
    let previous = events, dropped = state["dropped"]
    events = []; state["dropped"] = Int64(0)
    if persist() { return true }
    events = previous; state["dropped"] = dropped; return false
  }
  private func enforceCaps() {
    func group(_ event: [String: Any]) -> String { event["traceId"] as? String ?? event["runId"] as? String ?? "unknown" }
    func drop(_ count: Int) { state["dropped"] = (Self.integer(state["dropped"]) ?? 0) + Int64(count) }
    let before = events.count; events.removeAll { (Self.integer($0["occurredAtMs"]) ?? 0) < now() - Self.retentionMs }; drop(before - events.count)
    while Set(events.map(group)).count > 100 { let first = group(events[0]), count = events.count; events.removeAll { group($0) == first }; drop(count - events.count) }
    for id in Set(events.map(group)) {
      while true {
        let rows = events.filter { group($0) == id }
        let bytes = rows.reduce(0) { $0 + ((try? JSONSerialization.data(withJSONObject: $1))?.count ?? 4096) }
        guard rows.count > 256 || bytes > 65536, let first = events.firstIndex(where: { group($0) == id }) else { break }
        events.remove(at: first); drop(1)
      }
    }
    while !events.isEmpty && ((try? encoded())?.count ?? Self.maxBytes + 1) > Self.maxBytes { events.removeFirst(); drop(1) }
  }
  private func encoded() throws -> Data { try JSONSerialization.data(withJSONObject: ["version": 1, "state": state, "events": events, "osReports": osReports], options: .sortedKeys) }
  private func persist() -> Bool {
    guard loaded else { return false }
    do { let data = try encoded(); guard data.count <= Self.maxBytes else { return false }; try backend.replace(data); return true } catch { return false }
  }
}

internal final class MknoonAppDiagnostics: NSObject {
  static let shared = MknoonAppDiagnostics()
  private let queue = DispatchQueue(label: "com.mknoon.app-diagnostics", qos: .utility)
  private var spool: MknoonAppDiagnosticSpool?
  private var sharedInbox: MknoonNseAppDiagnosticInbox?
  private static let installedBuild: String = {
    guard let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
          let number = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String else { return "unknown" }
    return MknoonAppDiagnosticSpool.build("\(version)+\(number)")
  }()
  private override init() {
    super.init()
    queue.async { [weak self] in if let backend = try? MknoonAppDiagnosticFileBackend() { self?.spool = MknoonAppDiagnosticSpool(backend: backend, installedBuild: Self.installedBuild) } }
#if os(iOS)
    if #available(iOS 14.0, *) { MXMetricManager.shared.add(self) }
#endif
  }
  func record(_ feature: String, _ stage: String, _ outcome: String, _ reason: String = "none", values: [String: Any] = [:], traceId: String? = nil) {
    queue.async { [weak self] in self?.spool?.append(feature, stage, outcome, reason, values: values, traceId: traceId) }
  }
  private func importExtensionEvents() -> Int64? {
    if sharedInbox == nil { sharedInbox = MknoonNseAppDiagnosticInbox.production() }
    guard let sharedInbox, let page = sharedInbox.drain() else { return nil }
    if !page.events.isEmpty, spool?.enabled == true {
      guard let ids = spool?.importEvents(page.events), sharedInbox.ack(ids) else { return nil }
    }
    return page.dropped
  }
  func command(_ method: String, _ raw: Any?, completion: @escaping (Any) -> Void) {
    queue.async { [weak self] in
      guard let self else { DispatchQueue.main.async { completion(false) }; return }
      if self.spool == nil, let backend = try? MknoonAppDiagnosticFileBackend() { self.spool = MknoonAppDiagnosticSpool(backend: backend, installedBuild: Self.installedBuild) }
      var result: Any = false
      if let args = raw as? [String: Any], MknoonAppDiagnosticSpool.integer(args["version"]) == 1 {
        switch method {
        case "configure":
          let epoch = MknoonAppDiagnosticSpool.integer(args["consentEpoch"])
          if args["consentEpoch"] == nil || epoch != nil,
             let value = args["enabled"] as? NSNumber, CFGetTypeID(value) == CFBooleanGetTypeID() {
            if self.sharedInbox == nil { self.sharedInbox = MknoonNseAppDiagnosticInbox.production() }
            // OFF reaches both sinks even if either write fails. A false result
            // exposes incomplete durable consent synchronization to Dart.
            let localAccepted = self.spool?.configure(value.boolValue, consentEpoch: epoch) ?? false
            let sharedAccepted = (epoch != nil && (localAccepted || !value.boolValue))
              ? self.sharedInbox?.configure(value.boolValue, epoch: epoch!) ?? false : false
            result = localAccepted && sharedAccepted
            if localAccepted && value.boolValue { self.spool?.append("startup", "bridge", "ok", "bootstrap") }
          }
        case "drain":
          if let sharedDropped = self.importExtensionEvents(), var page = self.spool?.drain(args["limit"] as? Int ?? 64) {
            page["droppedEvents"] = (MknoonAppDiagnosticSpool.integer(page["droppedEvents"]) ?? 0) + sharedDropped
            result = page
          }
        case "ack": result = (args["eventIds"] as? [String]).map { self.spool?.ack($0) ?? false } ?? false
        case "clear":
          if self.sharedInbox == nil { self.sharedInbox = MknoonNseAppDiagnosticInbox.production() }
          let local = self.spool?.clear() ?? false, shared = self.sharedInbox?.clear() ?? false
          result = local && shared
        default: break
        }
      }
      DispatchQueue.main.async { completion(result) }
    }
  }
}

#if os(iOS)
@available(iOS 14.0, *)
extension MknoonAppDiagnostics: MXMetricManagerSubscriber {
  func didReceive(_ payloads: [MXMetricPayload]) { /* General metrics are not collected. */ }
  func didReceive(_ payloads: [MXDiagnosticPayload]) {
    // MetricKit reports may be delayed and span an interval. The end timestamp
    // is the OS report interval boundary, not an invented exact crash time.
    for payload in payloads.prefix(16) {
      let timestamp = Int64(payload.timeStampEnd.timeIntervalSince1970 * 1000)
      let begin = Int64(payload.timeStampBegin.timeIntervalSince1970 * 1000)
      for (index, crash) in (payload.crashDiagnostics ?? []).prefix(16).enumerated() {
        let signal = crash.signal?.int64Value ?? 0
        let stamp = crash.metaData.applicationBuildVersion
        queue.async { [weak self] in
          guard let spool = self?.spool, spool.enabled else { return }
          let fingerprint = MknoonAppDiagnosticFingerprint.appFrames(crash.callStackTree.jsonRepresentation())
          _ = spool.importOsReport(crash: true, timestamp: timestamp, intervalStart: begin, signal: signal, reportBuild: stamp, fingerprint: fingerprint, reportIndex: index)
        }
      }
      for (index, hang) in (payload.hangDiagnostics ?? []).prefix(16).enumerated() {
        let duration = Int64(max(0, hang.hangDuration.converted(to: .milliseconds).value))
        let stamp = hang.metaData.applicationBuildVersion
        queue.async { [weak self] in
          guard let spool = self?.spool, spool.enabled else { return }
          let fingerprint = MknoonAppDiagnosticFingerprint.appFrames(hang.callStackTree.jsonRepresentation())
          _ = spool.importOsReport(crash: false, timestamp: timestamp, intervalStart: begin, durationMs: duration, reportBuild: stamp, fingerprint: fingerprint, reportIndex: index)
        }
      }
    }
  }
}
#endif

#if canImport(Flutter)
extension MknoonAppDiagnostics {
  func wrapBridge(_ method: String, arguments: Any?, result: @escaping FlutterResult) -> FlutterResult {
    guard let operation = MknoonAppDiagnosticBridgeResponse.operations[method] else { return result }
    var trace = UUID().uuidString.lowercased()
    if let text = arguments as? String, text.utf8.count <= 16384, let data = text.data(using: .utf8),
       let row = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
       let fields = row["diagnostics"] as? [String: Any], let candidate = fields["traceId"] as? String, MknoonAppDiagnosticSpool.uuid(candidate) { trace = candidate.lowercased() }
    let started = ProcessInfo.processInfo.systemUptime
    record("runtime", "bridge", "started", values: ["operation": operation], traceId: trace)
    return { [weak self] value in
      let outcome: String, reason: String
      if let error = value as? FlutterError {
        outcome = "failed"
        switch error.code {
        case "GO_RUNTIME_NOT_ACTIVE": reason = "bridge_rejected"
        case "GO_BRIDGE_DISPOSED": reason = "bridge_unavailable"
        case "TIMEOUT": reason = "bridge_timeout"
        default: reason = "unknown"
        }
      } else if let object = value as? NSObject, object === FlutterMethodNotImplemented {
        outcome = "failed"; reason = "bridge_handler_missing"
      } else { (outcome, reason) = MknoonAppDiagnosticBridgeResponse.response(value) }
      self?.record("runtime", "bridge", outcome, reason, values: ["operation": operation,
        "durationMs": Int64(max(0, (ProcessInfo.processInfo.systemUptime - started) * 1000))], traceId: trace)
      result(value)
    }
  }
}

internal final class MknoonAppDiagnosticBridge {
  private let channel: FlutterMethodChannel
  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "mknoon/app_diagnostics", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in MknoonAppDiagnostics.shared.command(call.method, call.arguments) { result($0) } }
  }
  deinit { channel.setMethodCallHandler(nil) }
}
#endif
