import CryptoKit
import Darwin
import Foundation

enum IosAppVisibilityLifecycle: String, Codable, CaseIterable {
  case foregroundActive = "FOREGROUND_ACTIVE"
  case inactive = "INACTIVE"
  case background = "BACKGROUND"
}

enum IosAppVisibilityLane: String, Codable {
  case direct
  case group

  fileprivate var discriminator: UInt8 {
    switch self {
    case .direct: return 0x01
    case .group: return 0x02
    }
  }
}

struct IosAppVisibilitySnapshotV1: Codable, Equatable {
  static let supportedSchemaVersion: Int64 = 1
  static let freshnessLimitMs: Int64 = 90_000

  let schemaVersion: Int64
  let revision: Int64
  let lifecycleGeneration: Int64
  let lifecycle: IosAppVisibilityLifecycle
  let visibleConversationDigest: String?
  let updatedMonotonicMs: Int64
  let bootSession: String

  private enum CodingKeys: String, CodingKey, CaseIterable {
    case schemaVersion
    case revision
    case lifecycleGeneration
    case lifecycle
    case visibleConversationDigest
    case updatedMonotonicMs
    case bootSession
  }

  init(
    schemaVersion: Int64 = Self.supportedSchemaVersion,
    revision: Int64,
    lifecycleGeneration: Int64,
    lifecycle: IosAppVisibilityLifecycle,
    visibleConversationDigest: String?,
    updatedMonotonicMs: Int64,
    bootSession: String
  ) {
    self.schemaVersion = schemaVersion
    self.revision = revision
    self.lifecycleGeneration = lifecycleGeneration
    self.lifecycle = lifecycle
    self.visibleConversationDigest = visibleConversationDigest
    self.updatedMonotonicMs = updatedMonotonicMs
    self.bootSession = bootSession
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    schemaVersion = try container.decode(Int64.self, forKey: .schemaVersion)
    revision = try container.decode(Int64.self, forKey: .revision)
    lifecycleGeneration = try container.decode(
      Int64.self,
      forKey: .lifecycleGeneration
    )
    lifecycle = try container.decode(
      IosAppVisibilityLifecycle.self,
      forKey: .lifecycle
    )
    if try container.decodeNil(forKey: .visibleConversationDigest) {
      visibleConversationDigest = nil
    } else {
      visibleConversationDigest = try container.decode(
        String.self,
        forKey: .visibleConversationDigest
      )
    }
    updatedMonotonicMs = try container.decode(
      Int64.self,
      forKey: .updatedMonotonicMs
    )
    bootSession = try container.decode(String.self, forKey: .bootSession)
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(schemaVersion, forKey: .schemaVersion)
    try container.encode(revision, forKey: .revision)
    try container.encode(lifecycleGeneration, forKey: .lifecycleGeneration)
    try container.encode(lifecycle, forKey: .lifecycle)
    if let visibleConversationDigest {
      try container.encode(
        visibleConversationDigest,
        forKey: .visibleConversationDigest
      )
    } else {
      try container.encodeNil(forKey: .visibleConversationDigest)
    }
    try container.encode(updatedMonotonicMs, forKey: .updatedMonotonicMs)
    try container.encode(bootSession, forKey: .bootSession)
  }

  var isStructurallyValid: Bool {
    guard schemaVersion == Self.supportedSchemaVersion,
          revision > 0,
          lifecycleGeneration > 0,
          updatedMonotonicMs >= 0,
          IosAppVisibilitySystemClock.isCanonicalRecordBootSession(bootSession)
    else {
      return false
    }
    return visibleConversationDigest.map(
      IosAppVisibilityDigest.isCanonicalDigest
    ) ?? true
  }

  func isEligibleForSuppression(
    expectedConversationDigest: String,
    currentBootSession: String,
    currentMonotonicMs: Int64
  ) -> Bool {
    guard isStructurallyValid,
          IosAppVisibilityDigest.isCanonicalDigest(
            expectedConversationDigest
          ),
          IosAppVisibilitySystemClock.isCanonicalRecordBootSession(
            currentBootSession
          ),
          bootSession == currentBootSession,
          lifecycle == .foregroundActive,
          visibleConversationDigest == expectedConversationDigest,
          currentMonotonicMs >= updatedMonotonicMs
    else {
      return false
    }
    return currentMonotonicMs - updatedMonotonicMs < Self.freshnessLimitMs
  }

  var methodChannelMap: [String: Any] {
    [
      "schemaVersion": schemaVersion,
      "revision": revision,
      "lifecycleGeneration": lifecycleGeneration,
      "lifecycle": lifecycle.rawValue,
      "visibleConversationDigest": visibleConversationDigest ?? NSNull(),
      "updatedMonotonicMs": updatedMonotonicMs,
      "bootSession": bootSession,
    ]
  }
}

enum IosAppVisibilityDigest {
  private static let domain = Data("mknoon/app-visibility/v1".utf8)

  static func canonicalPreimage(
    lane: IosAppVisibilityLane,
    conversationIdentifier: String
  ) -> Data? {
    guard let normalized = normalizedConversationIdentifier(
      lane: lane,
      conversationIdentifier: conversationIdentifier
    ) else {
      return nil
    }
    let identifierBytes = Data(normalized.utf8)
    guard identifierBytes.count <= Int(UInt32.max) else { return nil }

    var result = Data()
    result.append(domain)
    result.append(0x00)
    result.append(lane.discriminator)
    let length = UInt32(identifierBytes.count).bigEndian
    withUnsafeBytes(of: length) { result.append(contentsOf: $0) }
    result.append(identifierBytes)
    return result
  }

  static func digest(
    lane: IosAppVisibilityLane,
    conversationIdentifier: String
  ) -> String? {
    guard let preimage = canonicalPreimage(
      lane: lane,
      conversationIdentifier: conversationIdentifier
    ) else {
      return nil
    }
    return SHA256.hash(data: preimage)
      .map { String(format: "%02x", $0) }
      .joined()
  }

  static func isCanonicalDigest(_ value: String) -> Bool {
    guard value.utf8.count == 64 else { return false }
    return value.utf8.allSatisfy { byte in
      (byte >= 0x30 && byte <= 0x39) || (byte >= 0x61 && byte <= 0x66)
    }
  }

  static func normalizedConversationIdentifier(
    lane: IosAppVisibilityLane,
    conversationIdentifier: String
  ) -> String? {
    let trimmed = conversationIdentifier.trimmingCharacters(
      in: .whitespacesAndNewlines
    )
    guard !trimmed.isEmpty else { return nil }

    switch lane {
    case .direct:
      guard !trimmed.hasPrefix("group:"), isSafeText(trimmed) else { return nil }
      return trimmed
    case .group:
      guard trimmed.hasPrefix("group:") else { return nil }
      let route = String(trimmed.dropFirst("group:".count))
      let marker = "|message:"
      let markerRange = route.range(of: marker)
      let groupIdentifier = markerRange.map {
        String(route[..<$0.lowerBound])
      } ?? route
      guard !groupIdentifier.isEmpty,
            groupIdentifier.trimmingCharacters(in: .whitespacesAndNewlines) ==
              groupIdentifier,
            !groupIdentifier.contains("|"),
            !groupIdentifier.contains(":"),
            isSafeText(groupIdentifier)
      else {
        return nil
      }
      if let markerRange {
        guard route.range(of: marker, options: .backwards) == markerRange else {
          return nil
        }
        let messageIdentifier = String(route[markerRange.upperBound...])
        guard !messageIdentifier.isEmpty,
              messageIdentifier.trimmingCharacters(in: .whitespacesAndNewlines) ==
                messageIdentifier,
              !messageIdentifier.contains("|"),
              isSafeText(messageIdentifier)
        else {
          return nil
        }
      } else if route.contains("|") {
        return nil
      }
      return "group:\(groupIdentifier)"
    }
  }

  private static func isSafeText(_ value: String) -> Bool {
    value.unicodeScalars.allSatisfy { scalar in
      scalar.value >= 0x20 && !(0x7f ... 0x9f).contains(scalar.value)
    }
  }
}

enum IosAppVisibilitySystemClock {
  static func bootSession() -> String? {
    var mib = [Int32(CTL_KERN), Int32(KERN_BOOTTIME)]
    var bootTime = timeval()
    var size = MemoryLayout<timeval>.stride
    let status = mib.withUnsafeMutableBufferPointer { buffer in
      sysctl(buffer.baseAddress, u_int(buffer.count), &bootTime, &size, nil, 0)
    }
    guard status == 0,
          size == MemoryLayout<timeval>.stride,
          bootTime.tv_sec >= 0,
          bootTime.tv_usec >= 0,
          bootTime.tv_usec < 1_000_000
    else {
      return nil
    }
    return "ios:\(bootTime.tv_sec):\(bootTime.tv_usec)"
  }

  static func monotonicMilliseconds() -> Int64? {
    let uptime = ProcessInfo.processInfo.systemUptime
    guard uptime.isFinite, uptime >= 0 else { return nil }
    let milliseconds = uptime * 1_000
    guard milliseconds <= Double(Int64.max) else { return nil }
    return Int64(milliseconds.rounded(.down))
  }

  static func isCanonicalBootSession(_ value: String) -> Bool {
    let components = value.split(separator: ":", omittingEmptySubsequences: false)
    guard components.count == 3,
          components[0] == "ios",
          let seconds = Int64(components[1]),
          let microseconds = Int64(components[2]),
          seconds >= 0,
          microseconds >= 0,
          microseconds < 1_000_000
    else {
      return false
    }
    return value == "ios:\(seconds):\(microseconds)"
  }

  static func isCanonicalRecordBootSession(_ value: String) -> Bool {
    guard !value.isEmpty,
          value != "unavailable",
          value.trimmingCharacters(in: .whitespacesAndNewlines) == value
    else {
      return false
    }
    return value.unicodeScalars.allSatisfy { scalar in
      scalar.value >= 0x20 && !(0x7f ... 0x9f).contains(scalar.value)
    }
  }
}

struct IosAppVisibilityContext: Equatable {
  let currentMonotonicMs: Int64
  let currentBootSession: String
}

struct IosAppVisibilitySnapshotEnvelope: Equatable {
  let snapshot: IosAppVisibilitySnapshotV1
  let context: IosAppVisibilityContext

  var methodChannelMap: [String: Any] {
    [
      "snapshot": snapshot.methodChannelMap,
      "currentMonotonicMs": context.currentMonotonicMs,
      "currentBootSession": context.currentBootSession,
    ]
  }
}

struct IosAppVisibilityPublishResult: Equatable {
  let committed: Bool
  let snapshot: IosAppVisibilitySnapshotV1?
  let context: IosAppVisibilityContext?

  var methodChannelMap: [String: Any] {
    let effectiveContext = context ?? IosAppVisibilityContext(
      currentMonotonicMs: 0,
      currentBootSession: "unavailable"
    )
    return [
      "committed": committed,
      "snapshot": snapshot?.methodChannelMap ?? NSNull(),
      "currentMonotonicMs": effectiveContext.currentMonotonicMs,
      "currentBootSession": effectiveContext.currentBootSession,
    ]
  }
}

enum IosAppVisibilityCommitFaultPoint: Equatable {
  case beforeTemporaryWrite
  case beforeFileSync
  case beforeRename
  case afterRenameBeforeDirectorySync
  case beforeReadback
}

private enum IosAppVisibilityLoadResult {
  case missing
  case valid(IosAppVisibilitySnapshotV1)
  case futureSchema
  case unsupportedBounds
  case corrupt
  case unavailable
}

/// One whole-record, cross-process store shared by Runner and the notification
/// service extension. The data inode is atomically replaced; the flock inode is
/// stable for the lifetime of the installation.
final class IosAppVisibilitySnapshotStore {
  static let appGroupIdentifier = "group.com.mknoon.app.share"
  static let stateFileName = "app_visibility_snapshot_v1.json"
  static let lockFileName = ".app_visibility_snapshot.lock"

  private let directory: URL
  private let stateURL: URL
  private let lockURL: URL
  private let fileManager: FileManager
  private let bootSessionProvider: () -> String?
  private let monotonicMsProvider: () -> Int64?
  private let commitFault: (IosAppVisibilityCommitFaultPoint) -> Bool
  private let operationLock = NSLock()
  private var currentProcessEligible = true

  convenience init?(
    appGroupIdentifier: String = IosAppVisibilitySnapshotStore.appGroupIdentifier
  ) {
    guard let container = FileManager.default.containerURL(
      forSecurityApplicationGroupIdentifier: appGroupIdentifier
    ) else {
      return nil
    }
    self.init(directory: container)
  }

  init(
    directory: URL,
    fileManager: FileManager = .default,
    bootSessionProvider: @escaping () -> String? =
      IosAppVisibilitySystemClock.bootSession,
    monotonicMsProvider: @escaping () -> Int64? =
      IosAppVisibilitySystemClock.monotonicMilliseconds,
    commitFault: @escaping (IosAppVisibilityCommitFaultPoint) -> Bool = { _ in false }
  ) {
    self.directory = directory
    stateURL = directory.appendingPathComponent(Self.stateFileName)
    lockURL = directory.appendingPathComponent(Self.lockFileName)
    self.fileManager = fileManager
    self.bootSessionProvider = bootSessionProvider
    self.monotonicMsProvider = monotonicMsProvider
    self.commitFault = commitFault
  }

  func readSnapshot(
    admissionIsActive: () -> Bool = { true }
  ) -> IosAppVisibilitySnapshotEnvelope? {
    operationLock.lock()
    defer { operationLock.unlock() }
    guard currentProcessEligible,
          let context = currentContextUnlocked()
    else {
      currentProcessEligible = false
      return nil
    }
    return withFileLock(defaultValue: nil) {
      // Admission may expire while waiting for the shared inode. Refuse before
      // reading persisted state; an already-entered synchronous read still owns its lock.
      guard admissionIsActive() else { return nil }
      switch loadStateUnlocked() {
      case let .valid(snapshot):
        return IosAppVisibilitySnapshotEnvelope(
          snapshot: snapshot,
          context: context
        )
      case .unavailable:
        currentProcessEligible = false
        return nil
      case .missing, .futureSchema, .unsupportedBounds, .corrupt:
        return nil
      }
    }
  }

  /// NSE-only bounded reader. It preserves the exact v1 decoder and process
  /// fail-closed latch while ensuring a contended visibility inode cannot
  /// consume the extension's completion budget.
  func readSnapshotForNse(lockTimeoutMs: Int = 100)
    -> IosAppVisibilitySnapshotEnvelope? {
    guard operationLock.try() else { return nil }
    defer { operationLock.unlock() }
    guard currentProcessEligible,
          let context = currentContextUnlocked() else {
      currentProcessEligible = false
      return nil
    }
    return withBoundedFileLock(
      timeoutMs: min(250, max(1, lockTimeoutMs)),
      defaultValue: nil
    ) {
      switch loadStateUnlocked() {
      case let .valid(snapshot):
        return IosAppVisibilitySnapshotEnvelope(
          snapshot: snapshot,
          context: context
        )
      case .unavailable:
        currentProcessEligible = false
        return nil
      case .missing, .futureSchema, .unsupportedBounds, .corrupt:
        return nil
      }
    }
  }

  @discardableResult
  func recordColdStart(
    lifecycle: IosAppVisibilityLifecycle = .inactive
  ) -> Bool {
    transitionLifecycle(to: lifecycle, forceGenerationAdvance: true)
  }

  @discardableResult
  func transitionLifecycle(to lifecycle: IosAppVisibilityLifecycle) -> Bool {
    transitionLifecycle(to: lifecycle, forceGenerationAdvance: false)
  }

  func publishVisibleConversation(
    digest: String?,
    lifecycleGeneration: Int64
  ) -> IosAppVisibilityPublishResult {
    operationLock.lock()
    defer { operationLock.unlock() }

    guard let context = currentContextUnlocked() else {
      currentProcessEligible = false
      return IosAppVisibilityPublishResult(
        committed: false,
        snapshot: nil,
        context: nil
      )
    }
    guard lifecycleGeneration > 0,
          digest.map(IosAppVisibilityDigest.isCanonicalDigest) ?? true
    else {
      return IosAppVisibilityPublishResult(
        committed: false,
        snapshot: nil,
        context: context
      )
    }
    guard currentProcessEligible else {
      return IosAppVisibilityPublishResult(
        committed: false,
        snapshot: nil,
        context: context
      )
    }

    return withFileLock(
      defaultValue: IosAppVisibilityPublishResult(
        committed: false,
        snapshot: nil,
        context: context
      )
    ) {
      guard case let .valid(current) = loadStateUnlocked() else {
        currentProcessEligible = false
        return IosAppVisibilityPublishResult(
          committed: false,
          snapshot: nil,
          context: context
        )
      }
      guard current.bootSession == context.currentBootSession,
            current.lifecycle == .foregroundActive,
            current.lifecycleGeneration == lifecycleGeneration
      else {
        return IosAppVisibilityPublishResult(
          committed: false,
          snapshot: current,
          context: context
        )
      }
      guard let nextRevision = increment(current.revision) else {
        currentProcessEligible = false
        return IosAppVisibilityPublishResult(
          committed: false,
          snapshot: nil,
          context: context
        )
      }
      let next = IosAppVisibilitySnapshotV1(
        revision: nextRevision,
        lifecycleGeneration: current.lifecycleGeneration,
        lifecycle: .foregroundActive,
        visibleConversationDigest: digest,
        updatedMonotonicMs: context.currentMonotonicMs,
        bootSession: context.currentBootSession
      )
      guard commitUnlocked(next) else {
        currentProcessEligible = false
        return IosAppVisibilityPublishResult(
          committed: false,
          snapshot: nil,
          context: context
        )
      }
      currentProcessEligible = true
      return IosAppVisibilityPublishResult(
        committed: true,
        snapshot: next,
        context: context
      )
    }
  }

  func readRawStateForTesting() throws -> Data {
    try Data(contentsOf: stateURL)
  }

  private func transitionLifecycle(
    to lifecycle: IosAppVisibilityLifecycle,
    forceGenerationAdvance: Bool
  ) -> Bool {
    operationLock.lock()
    defer { operationLock.unlock() }
    guard let context = currentContextUnlocked() else {
      currentProcessEligible = false
      return false
    }

    return withFileLock(defaultValue: false) {
      let next: IosAppVisibilitySnapshotV1
      switch loadStateUnlocked() {
      case let .valid(current):
        if !forceGenerationAdvance,
           current.bootSession == context.currentBootSession,
           current.lifecycle == lifecycle {
          return true
        }
        guard let revision = increment(current.revision),
              let generation = increment(current.lifecycleGeneration)
        else {
          currentProcessEligible = false
          return false
        }
        next = IosAppVisibilitySnapshotV1(
          revision: revision,
          lifecycleGeneration: generation,
          lifecycle: lifecycle,
          visibleConversationDigest: nil,
          updatedMonotonicMs: context.currentMonotonicMs,
          bootSession: context.currentBootSession
        )
      case .missing, .corrupt:
        next = IosAppVisibilitySnapshotV1(
          revision: 1,
          lifecycleGeneration: 1,
          lifecycle: lifecycle,
          visibleConversationDigest: nil,
          updatedMonotonicMs: context.currentMonotonicMs,
          bootSession: context.currentBootSession
        )
      case .futureSchema, .unsupportedBounds:
        currentProcessEligible = false
        return false
      case .unavailable:
        currentProcessEligible = false
        return false
      }
      guard commitUnlocked(next) else {
        currentProcessEligible = false
        return false
      }
      currentProcessEligible = true
      return true
    }
  }

  private func currentContextUnlocked() -> IosAppVisibilityContext? {
    guard let bootSession = bootSessionProvider(),
          IosAppVisibilitySystemClock.isCanonicalBootSession(bootSession),
          let monotonicMs = monotonicMsProvider(),
          monotonicMs >= 0
    else {
      return nil
    }
    return IosAppVisibilityContext(
      currentMonotonicMs: monotonicMs,
      currentBootSession: bootSession
    )
  }

  private func withFileLock<T>(defaultValue: T, _ body: () -> T) -> T {
    do {
      try fileManager.createDirectory(
        at: directory,
        withIntermediateDirectories: true
      )
    } catch {
      currentProcessEligible = false
      return defaultValue
    }
    let descriptor = open(lockURL.path, O_RDWR | O_CREAT, S_IRUSR | S_IWUSR)
    guard descriptor >= 0 else {
      currentProcessEligible = false
      return defaultValue
    }
    defer {
      flock(descriptor, LOCK_UN)
      close(descriptor)
    }
    guard flock(descriptor, LOCK_EX) == 0 else {
      currentProcessEligible = false
      return defaultValue
    }
    return body()
  }

  private func withBoundedFileLock<T>(
    timeoutMs: Int,
    defaultValue: T,
    _ body: () -> T
  ) -> T {
    let descriptor = open(lockURL.path, O_RDWR | O_CLOEXEC)
    guard descriptor >= 0 else { return defaultValue }
    defer {
      _ = flock(descriptor, LOCK_UN)
      close(descriptor)
    }
    let deadline = DispatchTime.now().uptimeNanoseconds +
      UInt64(timeoutMs) * 1_000_000
    repeat {
      if flock(descriptor, LOCK_EX | LOCK_NB) == 0 { return body() }
      if errno != EWOULDBLOCK && errno != EAGAIN { return defaultValue }
      usleep(2_000)
    } while DispatchTime.now().uptimeNanoseconds < deadline
    return defaultValue
  }

  private func loadStateUnlocked() -> IosAppVisibilityLoadResult {
    guard fileManager.fileExists(atPath: stateURL.path) else { return .missing }
    let data: Data
    do {
      data = try Data(contentsOf: stateURL)
    } catch {
      return .unavailable
    }
    guard let object = try? JSONSerialization.jsonObject(with: data),
          let root = object as? [String: Any]
    else {
      return .corrupt
    }
    if Self.isIntegralNumberOutsideSignedInt64(root["schemaVersion"]) {
      return .unsupportedBounds
    }
    guard let schemaVersion = Self.strictInt64(root["schemaVersion"])
    else { return .corrupt }
    if schemaVersion > IosAppVisibilitySnapshotV1.supportedSchemaVersion {
      return .futureSchema
    }
    guard schemaVersion == IosAppVisibilitySnapshotV1.supportedSchemaVersion
    else { return .corrupt }
    let expectedKeys: Set<String> = [
      "schemaVersion",
      "revision",
      "lifecycleGeneration",
      "lifecycle",
      "visibleConversationDigest",
      "updatedMonotonicMs",
      "bootSession",
    ]
    guard Set(root.keys) == expectedKeys else { return .corrupt }
    for key in ["revision", "lifecycleGeneration", "updatedMonotonicMs"] {
      if Self.isIntegralNumberOutsideSignedInt64(root[key]) {
        return .unsupportedBounds
      }
      guard Self.strictInt64(root[key]) != nil else { return .corrupt }
    }
    guard
          let snapshot = try? JSONDecoder().decode(
            IosAppVisibilitySnapshotV1.self,
            from: data
          ),
          snapshot.isStructurallyValid,
          IosAppVisibilitySystemClock.isCanonicalBootSession(
            snapshot.bootSession
          )
    else {
      return .corrupt
    }
    return .valid(snapshot)
  }

  private func commitUnlocked(_ snapshot: IosAppVisibilitySnapshotV1) -> Bool {
    guard snapshot.isStructurallyValid,
          IosAppVisibilitySystemClock.isCanonicalBootSession(
            snapshot.bootSession
          )
    else {
      return false
    }
    let temporaryURL = directory.appendingPathComponent(
      ".\(Self.stateFileName).\(UUID().uuidString).tmp"
    )
    var renamed = false
    defer {
      if !renamed { try? fileManager.removeItem(at: temporaryURL) }
    }
    do {
      if commitFault(.beforeTemporaryWrite) { return false }
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.sortedKeys]
      let data = try encoder.encode(snapshot)
      try data.write(to: temporaryURL, options: [])
      try fileManager.setAttributes(
        [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
        ofItemAtPath: temporaryURL.path
      )
      var resourceValues = URLResourceValues()
      resourceValues.isExcludedFromBackup = true
      var protectedURL = temporaryURL
      try protectedURL.setResourceValues(resourceValues)

      if commitFault(.beforeFileSync) { return false }
      let fileDescriptor = open(temporaryURL.path, O_RDONLY)
      guard fileDescriptor >= 0 else { return false }
      let fileSyncResult = fsync(fileDescriptor)
      close(fileDescriptor)
      guard fileSyncResult == 0 else { return false }

      if commitFault(.beforeRename) { return false }
      guard rename(temporaryURL.path, stateURL.path) == 0 else { return false }
      renamed = true

      if commitFault(.afterRenameBeforeDirectorySync) { return false }
      let directoryDescriptor = open(directory.path, O_RDONLY)
      guard directoryDescriptor >= 0 else { return false }
      let directorySyncResult = fsync(directoryDescriptor)
      close(directoryDescriptor)
      guard directorySyncResult == 0 else { return false }

      if commitFault(.beforeReadback) { return false }
      guard case let .valid(reloaded) = loadStateUnlocked(),
            reloaded == snapshot
      else {
        return false
      }
      return true
    } catch {
      return false
    }
  }

  private func increment(_ value: Int64) -> Int64? {
    let (result, overflow) = value.addingReportingOverflow(1)
    return overflow || result <= 0 ? nil : result
  }

  private static func isBoolean(_ value: NSNumber) -> Bool {
    CFGetTypeID(value) == CFBooleanGetTypeID()
  }

  private static func strictInt64(_ value: Any?) -> Int64? {
    guard let number = value as? NSNumber, !isBoolean(number) else {
      return nil
    }
    return Int64(number.stringValue)
  }

  private static func isIntegralNumberOutsideSignedInt64(_ value: Any?) -> Bool {
    guard let number = value as? NSNumber, !isBoolean(number) else {
      return false
    }
    let decimal = NSDecimalNumber(decimal: number.decimalValue)
    guard decimal != .notANumber else { return false }
    let integer = decimal.rounding(accordingToBehavior: NSDecimalNumberHandler(
      roundingMode: .plain,
      scale: 0,
      raiseOnExactness: false,
      raiseOnOverflow: false,
      raiseOnUnderflow: false,
      raiseOnDivideByZero: false
    ))
    guard decimal.compare(integer) == .orderedSame else { return false }
    let minimum = NSDecimalNumber(value: Int64.min)
    let maximum = NSDecimalNumber(value: Int64.max)
    return decimal.compare(minimum) == .orderedAscending ||
      decimal.compare(maximum) == .orderedDescending
  }
}
