import Foundation

internal protocol OpaqueCallContactBackend: AnyObject {
  func read() throws -> Data?
  func replace(with data: Data?) throws
}

internal final class RunnerOpaqueCallContactFileBackend: OpaqueCallContactBackend {
  static let protectionType = FileProtectionType.completeUntilFirstUserAuthentication

  private let fileManager: FileManager
  private let url: URL

  init(fileManager: FileManager = .default, directory: URL? = nil) throws {
    let root = try directory ?? fileManager.url(
      for: .applicationSupportDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: true
    ).appendingPathComponent("MknoonNativeCall", isDirectory: true)
    try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
    try fileManager.setAttributes(
      [
        .protectionKey: Self.protectionType,
        .posixPermissions: 0o700,
      ],
      ofItemAtPath: root.path
    )
    self.fileManager = fileManager
    url = root.appendingPathComponent("opaque-contacts-v1.json")
  }

  func read() throws -> Data? {
    guard fileManager.fileExists(atPath: url.path) else { return nil }
    return try Data(contentsOf: url, options: [.mappedIfSafe])
  }

  func replace(with data: Data?) throws {
    guard let data else {
      if fileManager.fileExists(atPath: url.path) { try fileManager.removeItem(at: url) }
      guard !fileManager.fileExists(atPath: url.path) else {
        throw CocoaError(.fileWriteUnknown)
      }
      return
    }
    try data.write(to: url, options: [.atomic])
    try fileManager.setAttributes(
      [
        .protectionKey: Self.protectionType,
        .posixPermissions: 0o600,
      ],
      ofItemAtPath: url.path
    )
    guard try Data(contentsOf: url) == data else { throw CocoaError(.fileWriteUnknown) }
  }
}

/// Protected, recipient-issued handle mapping. The APNs payload can select a
/// mapping but can never provide the display string used by CallKit.
internal final class OpaqueCallContactResolver {
  static let genericDisplayName = "Mknoon call"
  static let maxMappings = 512
  static let maxRecordBytes = 64 * 1024

  private struct Mapping: Codable, Equatable {
    let handle: String
    let displayName: String
    let verifiedAtMs: Int64
  }

  private struct Envelope: Codable, Equatable {
    let version: Int
    var mappings: [Mapping]
  }

  private let backend: OpaqueCallContactBackend
  private let nowMs: () -> Int64
  private let lock = NSLock()
  private let encoder = JSONEncoder()
  private let decoder = JSONDecoder()

  init(
    backend: OpaqueCallContactBackend,
    nowMs: @escaping () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1_000) }
  ) {
    self.backend = backend
    self.nowMs = nowMs
    encoder.outputFormatting = [.sortedKeys]
  }

  static func runnerDefault() -> OpaqueCallContactResolver? {
    guard let backend = try? RunnerOpaqueCallContactFileBackend() else { return nil }
    return OpaqueCallContactResolver(backend: backend)
  }

  func displayName(for opaqueHandle: String) -> String {
    synchronized {
      guard Self.validHandle(opaqueHandle),
            let mappings = readMappings()
      else { return Self.genericDisplayName }
      return mappings.first { $0.handle == opaqueHandle }?.displayName
        ?? Self.genericDisplayName
    }
  }

  /// Callers may invoke this only after accepted-contact authentication. The
  /// boolean return intentionally contains no submitted value.
  @discardableResult
  func updateVerified(handle: String, displayName: String) -> Bool {
    synchronized {
      guard Self.validHandle(handle), let normalized = Self.normalizedName(displayName) else {
        return false
      }
      let observedNow = nowMs()
      guard observedNow >= 0 else { return false }
      var mappings = readMappings() ?? []
      mappings.removeAll { $0.handle == handle }
      mappings.append(Mapping(
        handle: handle,
        displayName: normalized,
        verifiedAtMs: observedNow
      ))
      mappings.sort { $0.verifiedAtMs < $1.verifiedAtMs }
      if mappings.count > Self.maxMappings {
        mappings.removeFirst(mappings.count - Self.maxMappings)
      }
      return commit(mappings)
    }
  }

  @discardableResult
  func revoke(handle: String) -> Bool {
    synchronized {
      guard Self.validHandle(handle), var mappings = readMappings() else { return false }
      let before = mappings.count
      mappings.removeAll { $0.handle == handle }
      if mappings.count == before { return true }
      return commit(mappings)
    }
  }

  static func validHandle(_ value: String) -> Bool {
    guard value == value.lowercased() else { return false }
    if value.count == 32 {
      return value.unicodeScalars.allSatisfy { CharacterSet(charactersIn: "0123456789abcdef").contains($0) }
    }
    guard value.count == 36,
          value[value.index(value.startIndex, offsetBy: 14)] == "4",
          "89ab".contains(value[value.index(value.startIndex, offsetBy: 19)])
    else { return false }
    return UUID(uuidString: value) != nil
  }

  /// The pre-publication bridge accepts only an already-normalized name so
  /// platform boundaries cannot disagree about which value was authorized.
  static func validDisplayName(_ value: String) -> Bool {
    Self.normalizedName(value) == value
  }

  private func readMappings() -> [Mapping]? {
    do {
      guard let data = try backend.read() else { return [] }
      guard !data.isEmpty, data.count <= Self.maxRecordBytes,
            let envelope = try? decoder.decode(Envelope.self, from: data),
            envelope.version == 1,
            envelope.mappings.count <= Self.maxMappings,
            Set(envelope.mappings.map(\.handle)).count == envelope.mappings.count,
            envelope.mappings.allSatisfy({
              Self.validHandle($0.handle) && Self.normalizedName($0.displayName) == $0.displayName
            })
      else { return nil }
      return envelope.mappings
    } catch {
      return nil
    }
  }

  private func commit(_ mappings: [Mapping]) -> Bool {
    do {
      if mappings.isEmpty {
        try backend.replace(with: nil)
        return try backend.read() == nil
      }
      let data = try encoder.encode(Envelope(version: 1, mappings: mappings))
      guard data.count <= Self.maxRecordBytes else { return false }
      try backend.replace(with: data)
      return try backend.read() == data
    } catch {
      return false
    }
  }

  private static func normalizedName(_ input: String) -> String? {
    let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, trimmed.count <= 80,
          !trimmed.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
    else { return nil }
    return trimmed
  }

  private func synchronized<T>(_ action: () -> T) -> T {
    lock.lock()
    defer { lock.unlock() }
    return action()
  }
}
