import Foundation
import CoreFoundation
import Darwin

/// Independent App Group inbox. The app imports and durably ACKs this journal;
/// neither process writes the other's main spool or notification authority.
internal final class MknoonNseAppDiagnosticInbox {
  static let maxBytes = 262_144
  private let directory: URL
  private let now: () -> Int64
  init(directory: URL, now: @escaping () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) }) {
    self.directory = directory; self.now = now
  }
  static func production() -> MknoonNseAppDiagnosticInbox? {
    guard let group = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.mknoon.app.share") else { return nil }
    return MknoonNseAppDiagnosticInbox(directory: group.appendingPathComponent("AppDiagnosticNse", isDirectory: true))
  }
  private func number(_ value: Any?) -> Int64? {
    guard let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), n.doubleValue.isFinite,
          n.doubleValue >= 0, n.doubleValue <= 9_007_199_254_740_991, n.doubleValue.rounded() == n.doubleValue else { return nil }
    return n.int64Value
  }
  private func transaction<T>(_ body: (inout [String: Any]) throws -> (T, Bool)) -> T? {
    do {
      var root = directory
      try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
      try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
      var resources = URLResourceValues(); resources.isExcludedFromBackup = true; try root.setResourceValues(resources)
#if os(iOS)
      try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: root.path)
#endif
      let lock = open(root.appendingPathComponent("inbox.lock").path, O_CREAT | O_RDWR, 0o600)
      guard lock >= 0 else { return nil }
      defer { close(lock) }
      // Never wait for another process on a notification deadline.
      guard flock(lock, LOCK_EX | LOCK_NB) == 0 else { return nil }
      defer { flock(lock, LOCK_UN) }
      let file = root.appendingPathComponent("inbox-v1.json")
      var state: [String: Any] = ["version": 1, "enabled": false, "epoch": Int64(0), "since": Int64(0), "sequence": Int64(0), "dropped": Int64(0), "events": [[String: Any]]()]
      if FileManager.default.fileExists(atPath: file.path) {
        guard (try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Self.maxBytes + 1) <= Self.maxBytes,
              let stored = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any], number(stored["version"]) == 1,
              stored["enabled"] is Bool, number(stored["epoch"]) != nil, stored["events"] is [[String: Any]] else { return nil }
        state = stored
      }
      let (result, write) = try body(&state)
      if write {
        let data = try JSONSerialization.data(withJSONObject: state, options: .sortedKeys)
        guard data.count <= Self.maxBytes else { return nil }
#if os(iOS)
        try data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
#else
        try data.write(to: file, options: .atomic)
#endif
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
      }
      return result
    } catch { return nil }
  }
  func configure(_ enabled: Bool, epoch: Int64) -> Bool {
    transaction { state in
      let oldEpoch = self.number(state["epoch"]) ?? 0, oldEnabled = state["enabled"] as? Bool == true
      guard epoch > 0, epoch >= oldEpoch, epoch != oldEpoch || oldEnabled == enabled else { return (false, false) }
      if enabled && !oldEnabled { state["since"] = self.now() }
      state["epoch"] = epoch; state["enabled"] = enabled
      if !enabled { state["events"] = [[String: Any]](); state["dropped"] = Int64(0); state["since"] = Int64(0) }
      return (true, true)
    } ?? false
  }
  func append(traceId: String, runId: String, beganAt: Int64, occurredAt: Int64, elapsedMs: Int64, build: String,
              stage: String, outcome: String, reason: String) -> Bool {
    let uuid = { (text: String) in text.range(of: "^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$", options: .regularExpression) != nil }
    guard uuid(traceId), uuid(runId), ["receive", "process", "presentation"].contains(stage),
          ["started", "ok", "pending", "timeout", "failed"].contains(outcome), ["none", "timeout", "unknown"].contains(reason) else { return false }
    return transaction { state in
      guard state["enabled"] as? Bool == true, let since = self.number(state["since"]), since > 0, beganAt >= since,
            occurredAt >= beganAt, occurredAt <= self.now(), let sequence = self.number(state["sequence"]), sequence < 9_007_199_254_740_991 else { return (false, false) }
      let stamp = build.utf8.count <= 80 && build.range(of: "^[A-Za-z0-9._+()-]+$", options: .regularExpression) != nil ? build : "unknown"
      let event: [String: Any] = ["schemaVersion": 1, "eventId": UUID().uuidString.lowercased(), "traceId": traceId, "runId": runId,
        "sequence": sequence + 1, "occurredAtMs": occurredAt, "elapsedMs": max(0, elapsedMs), "build": stamp,
        "source": "ios", "platform": "ios", "feature": "push", "stage": stage, "outcome": outcome, "reason": reason,
        "values": ["extensionProcess": true]]
      state["sequence"] = sequence + 1
      var rows = state["events"] as? [[String: Any]] ?? []; rows.append(event)
      var dropped = self.number(state["dropped"]) ?? 0
      let old = rows.count; rows.removeAll { (self.number($0["occurredAtMs"]) ?? 0) < self.now() - 604_800_000 }; dropped += Int64(old - rows.count)
      while Set(rows.compactMap { $0["traceId"] as? String }).count > 100 {
        let first = rows.first?["traceId"] as? String; let count = rows.count
        rows.removeAll { $0["traceId"] as? String == first }; dropped += Int64(count - rows.count)
      }
      while rows.filter({ $0["traceId"] as? String == traceId }).count > 64 {
        if let index = rows.firstIndex(where: { $0["traceId"] as? String == traceId }) { rows.remove(at: index); dropped += 1 }
      }
      state["events"] = rows; state["dropped"] = dropped
      while !rows.isEmpty {
        guard try JSONSerialization.data(withJSONObject: state).count > Self.maxBytes else { break }
        rows.removeFirst(); dropped += 1; state["events"] = rows; state["dropped"] = dropped
      }
      return (true, true)
    } ?? false
  }
  func drain() -> (events: [[String: Any]], dropped: Int64)? {
    transaction { state in
      let rows = state["events"] as? [[String: Any]] ?? []
      return ((Array(rows.prefix(64)), self.number(state["dropped"]) ?? 0), false)
    }
  }
  func ack(_ ids: [String]) -> Bool {
    guard ids.count <= 64 else { return false }
    return transaction { state in
      var rows = state["events"] as? [[String: Any]] ?? []
      rows.removeAll { ids.contains($0["eventId"] as? String ?? "") }; state["events"] = rows
      return (true, true)
    } ?? false
  }
  func clear() -> Bool {
    transaction { state in state["events"] = [[String: Any]](); state["dropped"] = Int64(0); return (true, true) } ?? false
  }
}

/// All file work runs on a utility queue. Notification completion never waits.
internal final class MknoonNseAppDiagnosticScope {
  private static let queue = DispatchQueue(label: "com.mknoon.nse-app-diagnostics", qos: .utility)
  private static let runId = UUID().uuidString.lowercased()
  private let traceId = UUID().uuidString.lowercased()
  private let beganAt = Int64(Date().timeIntervalSince1970 * 1000)
  private let build: String = {
    let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
    let number = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
    return "\(version)+\(number)"
  }()
  func record(_ stage: String, _ outcome: String, _ reason: String = "none") {
    let at = Int64(Date().timeIntervalSince1970 * 1000), elapsed = Int64(ProcessInfo.processInfo.systemUptime * 1000)
    Self.queue.async { [self] in
      _ = MknoonNseAppDiagnosticInbox.production()?.append(traceId: traceId, runId: Self.runId, beganAt: beganAt,
        occurredAt: at, elapsedMs: elapsed, build: build, stage: stage, outcome: outcome, reason: reason)
    }
  }
}
