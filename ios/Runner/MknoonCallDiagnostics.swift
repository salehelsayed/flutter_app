import Foundation
import Flutter

internal protocol MknoonCallDiagnosticBackend {
  func read() throws -> Data?
  func replace(_ data: Data) throws
}

internal enum MknoonCallDiagnosticScope {
  private static let key = "mknoon.call-diagnostic-context"
  static var current: [String: Any] { Thread.current.threadDictionary[key] as? [String: Any] ?? [:] }
  static func withContext(_ context: [String: Any], _ action: () -> Void) {
    let old = Thread.current.threadDictionary[key]
    Thread.current.threadDictionary[key] = context
    defer { Thread.current.threadDictionary[key] = old }
    action()
  }
}

/// Separate from the call journal: diagnostic persistence never grants authority.
internal final class MknoonCallDiagnosticFileBackend: MknoonCallDiagnosticBackend {
  private let url: URL
  init(directory: URL? = nil) throws {
    let root = try directory ?? FileManager.default.url(
      for: .applicationSupportDirectory, in: .userDomainMask,
      appropriateFor: nil, create: true
    ).appendingPathComponent("MknoonCallDiagnostics", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try FileManager.default.setAttributes([
      .protectionKey: FileProtectionType.completeUntilFirstUserAuthentication,
      .posixPermissions: 0o700,
    ], ofItemAtPath: root.path)
    var excluded = root
    var resources = URLResourceValues()
    resources.isExcludedFromBackup = true
    try excluded.setResourceValues(resources)
    url = root.appendingPathComponent("diagnostics-v1.json")
  }
  func read() throws -> Data? {
    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
    let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
    guard size <= MknoonCallDiagnosticSpool.maxBytes else { throw CocoaError(.fileReadCorruptFile) }
    return try Data(contentsOf: url)
  }
  func replace(_ data: Data) throws {
    try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
  }
  static func protectDartDirectory() {
    do {
      var root = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                             appropriateFor: nil, create: true).appendingPathComponent("call_diagnostics", isDirectory: true)
      try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
      var resources = URLResourceValues(); resources.isExcludedFromBackup = true
      try root.setResourceValues(resources)
      try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication,
                                             .posixPermissions: 0o700], ofItemAtPath: root.path)
      for child in try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey]) {
        let info = try child.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        if info.isRegularFile == true && info.isSymbolicLink != true {
          try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication,
                                                 .posixPermissions: 0o600], ofItemAtPath: child.path)
        }
      }
    } catch { /* Protection failure is contained; no sensitive error is emitted. */ }
  }
}

internal final class MknoonCallDiagnosticSpool {
  static let maxBytes = 1_048_576
  static let retentionMs: Int64 = 7 * 24 * 60 * 60 * 1_000
  private let backend: MknoonCallDiagnosticBackend
  private let now: () -> Int64
  private let elapsed: () -> Int64
  private let installedBuild: String?
  let runId = UUID().uuidString.lowercased()
  private var state: [String: Any] = ["enabled": false, "sequence": Int64(0), "dropped": 0]
  private var events: [[String: Any]] = []
  private var pendingEvents: Set<String> = []
  // Only this private, protected state contains authority handles. drain never returns it.
  private var bindings: [String: [String: Any]] = [:]
  private var loaded = false

  init(backend: MknoonCallDiagnosticBackend,
       now: @escaping () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1_000) },
       elapsed: @escaping () -> Int64 = { Int64(ProcessInfo.processInfo.systemUptime * 1_000) },
       installedBuild: String? = nil) {
    self.backend = backend; self.now = now; self.elapsed = elapsed; self.installedBuild = installedBuild
    do {
      if let data = try backend.read() {
        guard data.count <= Self.maxBytes,
              let stored = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              stored["version"] as? Int == 1,
              let storedState = stored["state"] as? [String: Any],
              let storedEvents = stored["events"] as? [[String: Any]],
              let storedBindings = stored["bindings"] as? [String: [String: Any]]
        else { return }
        state = storedState
        events = storedEvents.filter(Self.validEvent)
        bindings = storedBindings
      }
      loaded = true
      if enabled {
        let previous = state["openRun"] as? String
        state["openRun"] = runId
        append(stage: "runtime", action: "recover", outcome: previous == nil ? "ok" : "interrupted",
               reason: previous == nil ? "bootstrap" : "interrupted_before_final_record")
      }
    } catch { /* Disabled until an explicit successful configure. */ }
  }

  var enabled: Bool { loaded && state["enabled"] as? Bool == true }
  func configure(_ enabled: Bool, consentEpoch: Int64? = nil) -> Bool {
    let highest = (state["consentEpoch"] as? NSNumber)?.int64Value ?? 0
    if let consentEpoch {
      guard consentEpoch > 0, consentEpoch >= highest,
            consentEpoch != highest || ((state["requestedEnabled"] as? Bool) ?? self.enabled) == enabled else { return false }
    } else if highest > 0 { return false }
    if !loaded { state = ["sequence": Int64(0), "dropped": 0]; events = []; bindings = [:] }
    loaded = true
    if let consentEpoch { state["consentEpoch"] = consentEpoch }
    state["requestedEnabled"] = enabled
    state["enabled"] = enabled
    if enabled { state["openRun"] = runId }
    else { events = []; bindings = [:]; state.removeValue(forKey: "openRun"); state["dropped"] = 0 }
    if !persist() { state["enabled"] = false; return false }
    return true
  }

  func bind(_ handle: String, traceId: String, context: [String: Any] = [:]) -> Bool {
    guard enabled, Self.handle(handle), Self.uuid(traceId), Self.canonical(handle) != traceId.lowercased() else { return false }
    prune()
    let existing = bindings[Self.canonical(handle)]
    let previousTrace = existing?["traceId"] as? String
    var binding = Self.context(context)
    binding["traceId"] = traceId.lowercased()
    binding["at"] = now()
    bindings[Self.canonical(handle)] = binding
    // A local pre-Dart trace may later be bound to the shared attempt reference.
    if let previousTrace, previousTrace != traceId.lowercased() {
      for index in events.indices where events[index]["traceId"] as? String == previousTrace {
        events[index]["traceId"] = traceId.lowercased()
      }
    }
    enforceCaps()
    return persist()
  }
  func lookup(_ handle: String) -> [String: Any] {
    guard enabled, Self.handle(handle) else { return ["version": 1] }
    prune()
    let key = Self.canonical(handle)
    guard let trace = bindings[key]?["traceId"] as? String, Self.uuid(trace), trace != key else { return ["version": 1] }
    return ["version": 1, "traceId": trace]
  }

  @discardableResult
  func append(handle: String? = nil, stage: String, action: String, outcome: String,
              reason: String = "none", values: [String: Any] = [:], context: [String: Any] = [:], deferPersistence: Bool = false) -> Bool {
    guard enabled else { return false }
    if !deferPersistence { prune() }
    var metadata = Self.context(context)
    if let handle, Self.handle(handle) {
      let key = Self.canonical(handle)
      if let at = (bindings[key]?["at"] as? NSNumber)?.int64Value, at < max(0, now() - Self.retentionMs) {
        bindings.removeValue(forKey: key)
      }
      if bindings[key] == nil {
        bindings[key] = ["traceId": UUID().uuidString.lowercased(), "at": now()]
      }
      metadata = (bindings[key] ?? [:]).merging(metadata) { _, new in new }
    }
    let sequence = (state["sequence"] as? NSNumber)?.int64Value ?? 0
    guard sequence < Int64.max else { return false }
    state["sequence"] = sequence + 1
    var event: [String: Any] = [
      "schemaVersion": 1, "eventId": UUID().uuidString.lowercased(), "source": "ios",
      "role": "local", "runId": runId, "sequence": sequence + 1,
      "occurredAtMs": max(0, now()), "elapsedMs": max(0, elapsed()),
      "stage": MknoonCallDiagnosticSchema.stage.contains(stage) ? stage : "runtime",
      "action": MknoonCallDiagnosticSchema.action.contains(action) ? action : "snapshot",
      "outcome": MknoonCallDiagnosticSchema.outcome.contains(outcome) ? outcome : "unknown",
      "reason": MknoonCallDiagnosticSchema.reason.contains(reason) ? reason : "unknown",
      "values": Self.values(values),
    ]
    for key in ["traceId", "requestId", "operationId", "parentOperationId"] {
      if let value = metadata[key] as? String,
         handle.map({ Self.canonical($0) != value }) ?? true { event[key] = value }
    }
    if let role = context["role"] as? String, ["caller", "callee", "local"].contains(role) { event["role"] = role }
    // Only new records receive this installed build; drain never relabels history.
    if let installedBuild, Self.validBuild(installedBuild) { event["build"] = installedBuild }
    guard Self.validEvent(event) else { return false }
    events.append(event)
    if deferPersistence { pendingEvents.insert(event["eventId"] as! String); return true }
    if persist() { return true }
    events.removeAll { $0["eventId"] as? String == event["eventId"] as? String }
    state["dropped"] = ((state["dropped"] as? Int) ?? 0) + 1
    return false
  }

  func drain(_ limit: Int) -> [String: Any] {
    prune(); _ = persist()
    return ["version": 1, "events": enabled ? Array(events.prefix(min(64, max(0, limit)))) : [],
            "droppedEvents": max(0, (state["dropped"] as? Int) ?? 0)]
  }
  func ack(_ ids: [String]) -> Bool {
    guard ids.count <= 64, ids.allSatisfy(Self.uuid) else { return false }
    let accepted = Set(ids.map { $0.lowercased() })
    let prior = events
    events.removeAll { accepted.contains($0["eventId"] as? String ?? "") }
    if persist() { return true }
    events = prior; return false
  }
  func clear() -> Bool {
    events = []; bindings = [:]; state["dropped"] = 0
    return persist()
  }
  func closeRun() { state.removeValue(forKey: "openRun"); _ = persist() }

  private func prune() {
    let deadline = max(0, now() - Self.retentionMs)
    events.removeAll { (($0["occurredAtMs"] as? NSNumber)?.int64Value ?? 0) < deadline }
    bindings = bindings.filter { (($0.value["at"] as? NSNumber)?.int64Value ?? 0) >= deadline }
  }
  private func dropOldest() {
    if !events.isEmpty { events.removeFirst(); state["dropped"] = min(Int.max - 1, (state["dropped"] as? Int) ?? 0) + 1 }
  }
  private func enforceCaps() {
    while Set(events.compactMap { $0["traceId"] as? String }).count > 100 {
      guard let trace = events.first(where: { $0["traceId"] != nil })?["traceId"] as? String else { break }
      let count = events.count
      events.removeAll { $0["traceId"] as? String == trace }
      state["dropped"] = ((state["dropped"] as? Int) ?? 0) + count - events.count
      bindings = bindings.filter { $0.value["traceId"] as? String != trace }
    }
    while bindings.count > 100 {
      guard let oldest = bindings.min(by: { (($0.value["at"] as? NSNumber)?.int64Value ?? 0) < (($1.value["at"] as? NSNumber)?.int64Value ?? 0) }) else { break }
      let trace = oldest.value["traceId"] as? String
      bindings.removeValue(forKey: oldest.key)
      while let index = events.firstIndex(where: { $0["traceId"] as? String == trace }) {
        events.remove(at: index); state["dropped"] = ((state["dropped"] as? Int) ?? 0) + 1
      }
    }
    for trace in Set(events.map { $0["traceId"] as? String ?? "local" }) {
      while true {
        let selected = events.filter { ($0["traceId"] as? String ?? "local") == trace }
        let bytes = selected.reduce(0) { $0 + ((try? JSONSerialization.data(withJSONObject: $1).count) ?? 4096) }
        guard selected.count > 256 || bytes > 65_536 else { break }
        guard let index = events.firstIndex(where: { ($0["traceId"] as? String ?? "local") == trace }) else { break }
        events.remove(at: index); state["dropped"] = ((state["dropped"] as? Int) ?? 0) + 1
      }
    }
    while !events.isEmpty, (encoded()?.count ?? Int.max) > Self.maxBytes { dropOldest() }
  }
  private func encoded() -> Data? {
    try? JSONSerialization.data(withJSONObject: ["version": 1, "state": state, "events": events, "bindings": bindings], options: [.sortedKeys])
  }
  private func persist() -> Bool {
    guard loaded else { return false }
    prune(); enforceCaps()
    guard let data = encoded(), data.count <= Self.maxBytes else { return false }
    do { try backend.replace(data); pendingEvents = []; return true } catch { return false }
  }
  func recordDropped(_ count: Int64) {
    guard enabled, count > 0 else { return }
    state["dropped"] = min(((state["dropped"] as? Int) ?? 0) + Int(min(count, 9_007_199_254_740_991)), 9_007_199_254_740_991)
  }
  func persistPending() -> Bool {
    if persist() { return true }
    let before = events.count
    events.removeAll { pendingEvents.contains($0["eventId"] as? String ?? "") }
    state["dropped"] = ((state["dropped"] as? Int) ?? 0) + before - events.count
    pendingEvents = []; return false
  }
  static func uuid(_ value: String) -> Bool {
    value.count == 36 && UUID(uuidString: value)?.uuidString.lowercased() == value.lowercased()
  }
  static func integer(_ value: Any?) -> Int64? {
    guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
          ["c", "s", "i", "l", "q", "C", "S", "I", "L", "Q"].contains(String(cString: number.objCType)),
          number.doubleValue <= Double(Int64.max), number.doubleValue >= 0 else { return nil }
    return number.int64Value
  }
  static func handle(_ value: String) -> Bool {
    value.range(of: "^(?:[0-9a-f]{32}|[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})$", options: .regularExpression) != nil
  }
  static func canonical(_ value: String) -> String {
    let raw = value.replacingOccurrences(of: "-", with: "").lowercased()
    guard raw.count == 32 else { return value }
    return "\(raw.prefix(8))-\(raw.dropFirst(8).prefix(4))-\(raw.dropFirst(12).prefix(4))-\(raw.dropFirst(16).prefix(4))-\(raw.dropFirst(20))"
  }
  static func context(_ input: [String: Any]) -> [String: Any] {
    var result: [String: Any] = [:]
    for key in ["traceId", "requestId", "operationId", "parentOperationId"] {
      if let value = input[key] as? String, uuid(value) { result[key] = value.lowercased() }
    }
    // Wire contexts use cause; emitted events and private native scopes use reason.
    if let reason = (input["cause"] ?? input["reason"]) as? String, MknoonCallDiagnosticSchema.reason.contains(reason) { result["reason"] = reason }
    return result
  }
  static func values(_ input: [String: Any]) -> [String: Any] {
    input.filter { key, value in
      if MknoonCallDiagnosticSchema.booleanValues.contains(key) { return CFGetTypeID(value as CFTypeRef) == CFBooleanGetTypeID() }
      if MknoonCallDiagnosticSchema.integerValues.contains(key), let number = value as? NSNumber {
        return CFGetTypeID(number) != CFBooleanGetTypeID() && number.doubleValue >= 0 && number.doubleValue <= 9_007_199_254_740_991 && number.doubleValue.rounded() == number.doubleValue
      }
      if let allowed = MknoonCallDiagnosticSchema.enumValues[key], let text = value as? String { return allowed.contains(text) }
      return false
    }
  }
  static func journalReason(_ type: PendingNativeCallEventType, context: [String: Any]) -> String {
    switch type {
    case .providerRemoved: return "provider_reset"
    case .nativeFailure: return "native_lifecycle_failed"
    case .expired: return "expired"
    case .remoteCancelled: return "remote_terminal"
    case .endRequested, .declineRequested: return commandReason(context)
    default: return "none"
    }
  }
  static func validBuild(_ value: String) -> Bool {
    value.range(of: "^[0-9A-Za-z.+_-]{1,80}$", options: .regularExpression) != nil
  }
  static func commandReason(_ input: [String: Any]) -> String {
    guard let reason = context(input)["reason"] as? String, reason != "none" else { return "unknown" }
    return reason
  }
  static func validEvent(_ event: [String: Any]) -> Bool {
    guard Set(event.keys).isSubset(of: MknoonCallDiagnosticSchema.eventKeys),
          event["schemaVersion"] as? Int == 1,
          event["source"] as? String == "ios",
          let role = event["role"] as? String, ["caller", "callee", "local"].contains(role),
          let eventId = event["eventId"] as? String, uuid(eventId),
          let run = event["runId"] as? String, uuid(run),
          let stage = event["stage"] as? String, MknoonCallDiagnosticSchema.stage.contains(stage),
          let action = event["action"] as? String, MknoonCallDiagnosticSchema.action.contains(action),
          let outcome = event["outcome"] as? String, MknoonCallDiagnosticSchema.outcome.contains(outcome),
          let reason = event["reason"] as? String, MknoonCallDiagnosticSchema.reason.contains(reason),
          let numbers = event["values"] as? [String: Any], values(numbers).count == numbers.count,
          event["build"] == nil || ((event["build"] as? String).map(validBuild) ?? false),
          let size = try? JSONSerialization.data(withJSONObject: event).count, size <= 4096 else { return false }
    for key in ["sequence", "occurredAtMs", "elapsedMs"] {
      guard let value = event[key] as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(), value.int64Value >= 0 else { return false }
    }
    for key in ["traceId", "requestId", "operationId", "parentOperationId"] {
      if let value = event[key], !(value is String && uuid(value as! String)) { return false }
    }
    return true
  }
}

/// Serial, asynchronous sink: no file or bridge operation is on PushKit's completion path.
internal final class MknoonCallDiagnostics {
  static let shared = MknoonCallDiagnostics()
  private let queue = DispatchQueue(label: "com.mknoon.call-diagnostics", qos: .utility)
  private let admission = MknoonAppDiagnosticAdmission()
  private var spool: MknoonCallDiagnosticSpool?
  private var persistenceScheduled = false
  private static let installedBuild: String? = {
    guard let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
          let number = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
    else { return nil }
    let value = "\(version)+\(number)"
    return MknoonCallDiagnosticSpool.validBuild(value) ? value : nil
  }()
  private init() {
    queue.async { [weak self] in
      guard let backend = try? MknoonCallDiagnosticFileBackend() else { return }
      self?.spool = MknoonCallDiagnosticSpool(backend: backend, installedBuild: Self.installedBuild)
    }
  }
  func record(handle: String? = nil, stage: String, action: String, outcome: String,
              reason: String = "none", values: [String: Any] = [:], context: [String: Any] = [:]) {
    let captured = MknoonCallDiagnosticScope.current.merging(context) { _, new in new }
    admission.enqueue({ work in queue.async { work() } }) { [weak self] dropped in
      guard let self else { return }
      self.spool?.recordDropped(dropped)
      if self.spool?.append(handle: handle, stage: stage, action: action, outcome: outcome, reason: reason, values: values, context: captured, deferPersistence: true) == true,
         !self.persistenceScheduled {
        self.persistenceScheduled = true
        self.queue.async { [weak self] in
          self?.persistenceScheduled = false
          _ = self?.spool?.persistPending()
        }
      }
    }
  }
  func bind(handle: String, traceId: String, context: [String: Any] = [:]) {
    queue.async { [weak self] in _ = self?.spool?.bind(handle, traceId: traceId, context: context) }
  }
  func journal(_ handle: String, _ type: PendingNativeCallEventType) {
    let stage: String
    switch type {
    case .presented: stage = "presentation"
    case .answerRequested: stage = "answer"
    case .audioActivated, .audioDeactivated, .muteChanged, .routeChanged: stage = "audio"
    default: stage = "terminal"
    }
    let reason = MknoonCallDiagnosticSpool.journalReason(type, context: MknoonCallDiagnosticScope.current)
    record(handle: handle, stage: stage, action: "commit", outcome: "ok", reason: reason,
           values: ["nativeCommitted": true, "terminal": type.isTerminal])
  }
  /// Strip optional diagnostics before the existing strict authority parser.
  /// Invalid metadata is ignored and never changes an otherwise valid call.
  static func pushMetadata(_ dictionary: [AnyHashable: Any]) -> ([AnyHashable: Any], String?) {
    var base = dictionary
    let raw = base.removeValue(forKey: "diagnostics")
    guard let metadata = raw as? [String: Any], Set(metadata.keys) == ["schemaVersion", "traceId"],
          MknoonCallDiagnosticSpool.integer(metadata["schemaVersion"]) == 1,
          let trace = metadata["traceId"] as? String, MknoonCallDiagnosticSpool.uuid(trace),
          (base["c"] as? String).map({ MknoonCallDiagnosticSpool.canonical($0) != trace.lowercased() }) ?? true
    else { return (base, nil) }
    return (base, trace.lowercased())
  }
  func command(_ method: String, _ args: Any?, completion: @escaping (Any?) -> Void) {
    queue.async { [weak self] in
      guard let self else { DispatchQueue.main.async { completion(false) }; return }
      if self.spool == nil, let backend = try? MknoonCallDiagnosticFileBackend() { self.spool = MknoonCallDiagnosticSpool(backend: backend, installedBuild: Self.installedBuild) }
      let result: Any
      if let args = args as? [String: Any], MknoonCallDiagnosticSpool.integer(args["version"]) == 1 {
        switch method {
        case "configure":
          MknoonCallDiagnosticFileBackend.protectDartDirectory()
          let epoch = MknoonCallDiagnosticSpool.integer(args["consentEpoch"])
          if args["consentEpoch"] != nil && epoch == nil { result = false }
          else if let enabled = args["enabled"] as? NSNumber, CFGetTypeID(enabled) == CFBooleanGetTypeID() {
            result = self.spool?.configure(enabled.boolValue, consentEpoch: epoch) ?? false
          } else { result = false }
        case "drain": result = self.spool?.drain(args["limit"] as? Int ?? 64) ?? ["version": 1, "events": [], "droppedEvents": 0]
        case "ack": result = (args["eventIds"] as? [String]).map { self.spool?.ack($0) ?? false } ?? false
        case "clear": result = self.spool?.clear() ?? false
        case "bind":
          if let handle = args["callHandle"] as? String, let trace = args["traceId"] as? String { result = self.spool?.bind(handle, traceId: trace, context: args) ?? false }
          else { result = false }
        case "lookup": result = (args["callHandle"] as? String).map { self.spool?.lookup($0) ?? ["version": 1] } ?? ["version": 1]
        default: result = FlutterMethodNotImplemented
        }
      } else { result = false }
      DispatchQueue.main.async { completion(result) }
    }
  }
}

internal final class MknoonCallDiagnosticBridge {
  private let channel: FlutterMethodChannel
  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "mknoon/call_diagnostics", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in MknoonCallDiagnostics.shared.command(call.method, call.arguments, completion: result) }
  }
  deinit { channel.setMethodCallHandler(nil) }
}

// Closed vocabulary mirrored from tool/call_diagnostics/schema_v1.json.
internal enum MknoonCallDiagnosticSchema {
  static let stage: Set<String> = ["attempt", "preflight", "authority", "signaling", "push", "admission", "presentation", "answer", "audio", "media", "turn", "terminal", "cleanup", "upload", "runtime"]
  static let action: Set<String> = ["start", "check", "lookup", "publish", "revoke", "invalidate", "replace", "send_direct", "store", "retrieve", "ack", "cancel", "expire", "dispatch", "present", "accept", "activate", "snapshot", "finish", "recover", "drop", "upload", "flush", "response", "mint", "retry", "bind", "configure", "disable", "enable", "reset", "receive", "parse", "commit", "adopt", "stop"]
  static let outcome: Set<String> = ["started", "ok", "failed", "rejected", "not_found", "not_found_or_expired", "duplicate", "skipped", "suppressed", "timeout", "interrupted", "completed", "partial", "pending", "blocked", "canceled", "declined", "busy", "no_answer", "connected", "media_flow_verified", "answered_without_verified_media", "completed_after_media", "dropped_after_media", "preflight_failed", "signaling_failed", "native_answer_failed", "media_failed", "interrupted_unknown", "partial_legacy", "missing_endpoint_report", "unknown"]
  static let reason: Set<String> = ["none", "unknown", "user_action", "local_user", "remote_user", "remote_terminal", "permission_denied", "microphone_denied", "permission_revoked", "full_screen_permission_denied", "notifications_denied", "platform_unsupported", "graph_unavailable", "graph_replaced", "graph_shutdown", "graph_not_owner", "capability_unavailable", "capability_publish_failed", "endpoint_not_found", "endpoint_expired", "endpoint_invalid", "authority_invalid", "authority_rejected", "authority_unreachable", "wake_authority_missing", "wake_failed", "no_route", "not_found_or_expired", "receipt_missing", "receipt_invalid", "signature_invalid", "blocked", "busy", "canceled", "declined", "no_answer", "timeout", "deadline", "network_unavailable", "transport_failed", "bridge_unavailable", "malformed_response", "backend_unavailable", "rate_limited", "invalid_request", "duplicate", "replay", "expired", "stale_epoch", "pushkit_token_invalidated", "calls_disabled", "native_token_updated", "resume_refresh", "bootstrap", "logout", "account_changed", "native_snapshot_invalid", "native_read_timeout", "native_stream_failed", "native_lifecycle_failed", "token_rotation_cleanup", "native_persistence_failed", "native_answer_refused", "provider_reset", "action_timeout", "audio_activation_failed", "audio_session_failed", "turn_unavailable", "turn_credential_failed", "ice_failed", "dtls_failed", "media_failed", "media_stalled", "negotiation_failed", "cleanup_failed", "sink_unavailable", "quota_exceeded", "retention_expired", "interrupted_before_final_record", "legacy_peer", "diagnostics_disabled", "server_error", "auth_error", "invalid_token", "provider_error", "rejected_payload", "rejected_route", "sent_cross_environment", "write_failed", "suppressed_attached", "invalidated", "token_changed", "capability_disabled", "token_invalidation", "adoption_failed", "unavailable", "remote_reject"]
  static let booleanValues: Set<String> = ["foreground", "enabled", "ownerMatched", "accepted", "connected", "terminal", "nativeCommitted", "audioActive", "structuralReady", "mediaFlowVerified", "inboundRtpObserved", "outboundRtpObserved", "inboundRtpProgress", "outboundRtpProgress", "muted", "relayOnly", "fullScreenAllowed", "notificationAllowed", "microphoneAllowed", "hasMore", "truncated", "legacy", "complete", "found", "storeCommitted", "responseWritten", "providerInvoked", "databaseClosed", "leaseReleased", "requiredPersistenceComplete"]
  static let integerValues: Set<String> = ["durationMs", "retry", "pending", "acked", "count", "dropped", "inboundPackets", "outboundPackets", "inboundBytes", "outboundBytes", "sampleCount", "cleanupRemaining", "graphGeneration", "epoch", "generation", "limit", "bytes", "attemptCount", "eventCount"]
  static let eventKeys: Set<String> = ["schemaVersion", "eventId", "source", "role", "runId", "sequence", "occurredAtMs", "elapsedMs", "stage", "action", "outcome", "reason", "values", "traceId", "requestId", "operationId", "parentOperationId", "build"]
  static let enumValues: [String: Set<String>] = [
    "admissionDisposition": Set(["admitted", "terminal", "permanent_reject", "empty_or_already_acked", "deferred", "unknown"]),
    "authorityKind": Set(["endpoint", "wake_grant", "standard_call_token", "ios_voip_token", "unknown"]),
    "state": Set(["idle", "incoming_validating", "incoming_ringing", "outgoing_preparing", "outgoing_inviting", "outgoing_ringing", "ringing", "inviting", "dialing", "accepted", "connecting", "connected", "reconnecting", "ending", "ended", "failed", "unknown"]),
    "transport": Set(["direct", "circuit_relay", "turn_udp", "turn_tcp", "turn_tls", "relay", "none", "unknown"]),
    "network": Set(["wifi", "cellular", "ethernet", "offline", "unknown"]),
    "platform": Set(["ios", "android", "other", "unknown"]),
    "completeness": Set(["complete", "partial", "legacy", "interrupted", "truncated", "unknown"]),
    "route": Set(["system_default", "earpiece", "speaker", "bluetooth", "wired_headset", "unknown"]),
    "failureStage": Set(["android_audio_focus", "peer_create", "user_media", "track_invariant", "add_track", "snapshot_senders", "snapshot_transceivers", "snapshot_transceiver_direction", "snapshot_receivers", "snapshot_stats", "snapshot_deadline", "set_audio_session_active", "create_connection", "supported_output_routes", "snapshot"]),
  ]
}
