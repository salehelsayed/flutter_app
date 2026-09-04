import CryptoKit
import Foundation

internal enum PendingNativeCallAcknowledgement: String, Codable, Equatable {
  case none = "NONE"
  case adopted = "ADOPTED"
  case terminal = "TERMINAL"
}

internal enum PendingNativeCallPhase: String, Codable, Equatable {
  case preStart
  case journal
}

internal enum PendingNativeCallDirection: String, Codable, Equatable {
  case incoming
  case outgoing
}

internal enum PendingNativeCallEventType: String, Codable, CaseIterable, Equatable {
  case presented
  case answerRequested
  case declineRequested
  case endRequested
  case remoteCancelled
  case expired
  case providerRemoved
  case muteChanged
  case routeChanged
  case audioActivated
  case audioDeactivated
  case nativeFailure

  var isTerminal: Bool {
    switch self {
    case .declineRequested, .endRequested, .remoteCancelled, .expired,
         .providerRemoved, .nativeFailure:
      return true
    default:
      return false
    }
  }

  var wireName: String {
    switch self {
    case .presented: return "presented"
    case .answerRequested: return "answer"
    case .declineRequested: return "decline"
    case .endRequested: return "end"
    case .remoteCancelled: return "remoteCancelled"
    case .expired: return "expired"
    case .providerRemoved: return "providerRemoved"
    case .muteChanged: return "muteChanged"
    case .routeChanged: return "routeChanged"
    case .audioActivated: return "audioActivated"
    case .audioDeactivated: return "audioDeactivated"
    case .nativeFailure: return "nativeFailure"
    }
  }
}

internal struct PendingNativeCallEvent: Codable, Equatable {
  let nativeCallId: UUID
  let sequence: Int64
  let eventId: UUID
  let type: PendingNativeCallEventType
  let occurredAtMs: Int64
}

internal struct PendingNativeCallDescriptor: Codable, Equatable {
  static let schemaVersion = 1

  let nativeCallId: UUID
  let callHandle: String
  var wakeHandle: String
  let opaqueContactHandle: String?
  let receivedAtMs: Int64
  let expiresAtMs: Int64
  var connectedAtMs: Int64?
  var highestSequence: Int64
  var terminalEvent: PendingNativeCallEvent?
  var terminalRetentionDeadlineMs: Int64?
  var events: [PendingNativeCallEvent]
  var handoffAcknowledgement: PendingNativeCallAcknowledgement
  var phase: PendingNativeCallPhase
  var answerRequested: Bool
  var muted: Bool?
  var presented: Bool
  var lastAcknowledgement: PendingNativeCallAcknowledgement?
  var lastAcknowledgedSequence: Int64
  let direction: PendingNativeCallDirection
  let schemaVersion: Int

  func matches(_ payload: VoipWakePayload, direction: PendingNativeCallDirection) -> Bool {
    nativeCallId == payload.nativeCallId
      && callHandle == payload.callHandle
      && self.direction == direction
  }
}

internal enum PendingNativeCallCreateResult: Equatable {
  case created(PendingNativeCallDescriptor)
  case duplicate(PendingNativeCallDescriptor?)
  case busy(PendingNativeCallDescriptor)
  case persistenceFailure
}

internal enum PendingNativeCallAppendResult: Equatable {
  case appended(PendingNativeCallDescriptor, PendingNativeCallEvent)
  case ignoredAfterTerminal(PendingNativeCallDescriptor)
  case notFound
  case capacityReached
  case persistenceFailure
}

internal protocol PendingNativeCallBackend: AnyObject {
  func readDescriptor() throws -> Data?
  func replaceDescriptor(with data: Data?) throws
  func readAcknowledgementReceipts() throws -> Data?
  func replaceAcknowledgementReceipts(with data: Data?) throws
}

/// Runner-private atomic persistence. The directory and both records are
/// protected after first unlock; neither is shared with the NSE.
internal final class RunnerPendingNativeCallFileBackend: PendingNativeCallBackend {
  static let protectionType = FileProtectionType.completeUntilFirstUserAuthentication

  typealias AttributeSetter = ([FileAttributeKey: Any], String) throws -> Void
  typealias AtomicWriter = (Data, URL, Data.WritingOptions) throws -> Void

  private let fileManager: FileManager
  private let directory: URL
  private let descriptorURL: URL
  private let receiptURL: URL
  private let attributeSetter: AttributeSetter
  private let atomicWriter: AtomicWriter

  init(
    fileManager: FileManager = .default,
    directory: URL? = nil,
    attributeSetter: AttributeSetter? = nil,
    atomicWriter: AtomicWriter? = nil
  ) throws {
    self.fileManager = fileManager
    self.attributeSetter = attributeSetter ?? { attributes, path in
      try fileManager.setAttributes(attributes, ofItemAtPath: path)
    }
    self.atomicWriter = atomicWriter ?? { data, url, options in
      try data.write(to: url, options: options)
    }
    let resolved = try directory ?? fileManager.url(
      for: .applicationSupportDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: true
    ).appendingPathComponent("MknoonNativeCall", isDirectory: true)
    self.directory = resolved
    descriptorURL = resolved.appendingPathComponent("pending-call-v1.json")
    receiptURL = resolved.appendingPathComponent("pending-call-acks-v1.json")
    try fileManager.createDirectory(at: resolved, withIntermediateDirectories: true)
    try protect(resolved, permissions: 0o700)
  }

  func readDescriptor() throws -> Data? { try read(descriptorURL) }

  func replaceDescriptor(with data: Data?) throws {
    try replace(descriptorURL, data: data)
  }

  func readAcknowledgementReceipts() throws -> Data? { try read(receiptURL) }

  func replaceAcknowledgementReceipts(with data: Data?) throws {
    try replace(receiptURL, data: data)
  }

  private func read(_ url: URL) throws -> Data? {
    guard fileManager.fileExists(atPath: url.path) else { return nil }
    return try Data(contentsOf: url, options: [.mappedIfSafe])
  }

  private func replace(_ url: URL, data: Data?) throws {
    guard let data else {
      if fileManager.fileExists(atPath: url.path) {
        try fileManager.removeItem(at: url)
      }
      guard !fileManager.fileExists(atPath: url.path) else {
        throw CocoaError(.fileWriteUnknown)
      }
      return
    }
    try atomicWriter(data, url, [.atomic])
    try protect(url, permissions: 0o600)
    guard try Data(contentsOf: url) == data else {
      throw CocoaError(.fileWriteUnknown)
    }
  }

  private func protect(_ url: URL, permissions: Int) throws {
    try attributeSetter(
      [
        .protectionKey: Self.protectionType,
        .posixPermissions: permissions,
      ],
      url.path
    )
  }
}

internal final class PendingNativeCallStore {
  static let maxEvents = 32
  static let maxRecordBytes = 8 * 1024
  static let maxAcknowledgementReceipts = 32
  static let acknowledgementReceiptTtlMs: Int64 = 10 * 60 * 1_000
  static let terminalReplayRetentionMs: Int64 = 30_000

  private struct AcknowledgementReceipt: Codable, Equatable {
    let nativeCallId: UUID
    let callHandleDigest: String
    let highestConsumedSequence: Int64
    let expiresAtMs: Int64
  }

  private struct ReceiptEnvelope: Codable, Equatable {
    let version: Int
    var receipts: [AcknowledgementReceipt]
  }

  private enum StoredState {
    case empty
    case valid(PendingNativeCallDescriptor)
    case invalid
  }

  private enum ReceiptState {
    case empty
    case valid([AcknowledgementReceipt])
    case invalid
  }

  private enum CommitResult { case committed, tooLarge, failed }

  private let backend: PendingNativeCallBackend
  private let nowMs: () -> Int64
  private let eventId: () -> UUID
  private let lock = NSRecursiveLock()
  private let encoder = JSONEncoder()
  private let decoder = JSONDecoder()

  init(
    backend: PendingNativeCallBackend,
    nowMs: @escaping () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1_000) },
    eventId: @escaping () -> UUID = UUID.init
  ) {
    self.backend = backend
    self.nowMs = nowMs
    self.eventId = eventId
    encoder.outputFormatting = [.sortedKeys]
  }

  static func runnerDefault(
    nowMs: @escaping () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1_000) }
  ) -> PendingNativeCallStore? {
    guard let backend = try? RunnerPendingNativeCallFileBackend() else { return nil }
    return PendingNativeCallStore(backend: backend, nowMs: nowMs)
  }

  func create(_ payload: VoipWakePayload) -> PendingNativeCallCreateResult {
    create(payload, direction: .incoming)
  }

  func createOutgoing(_ payload: VoipWakePayload) -> PendingNativeCallCreateResult {
    create(payload, direction: .outgoing)
  }

  func snapshot() -> PendingNativeCallDescriptor? {
    synchronized {
      _ = readReceipts()
      guard case let .valid(descriptor) = readState() else { return nil }
      return descriptor
    }
  }

  /// Retains an unacknowledged terminal long enough for bounded Dart replay,
  /// then fences its call handle before deleting it. Receipt-first deletion
  /// means a failed descriptor removal can never resurrect the same call.
  @discardableResult
  func sweepExpiredTerminalRetention() -> Bool {
    synchronized { sweepExpiredTerminalRetentionLocked() }
  }

  func resolveCallHandle(_ callHandle: String) -> UUID? {
    synchronized {
      if case let .valid(descriptor) = readState(), descriptor.callHandle == callHandle {
        return descriptor.nativeCallId
      }
      guard let digest = Self.digest(callHandle) else { return nil }
      guard case let .valid(receipts) = readReceipts() else { return nil }
      return receipts.first { $0.callHandleDigest == digest }?.nativeCallId
    }
  }

  func append(
    nativeCallId: UUID,
    type: PendingNativeCallEventType,
    muted: Bool? = nil
  ) -> PendingNativeCallAppendResult {
    synchronized {
      guard (type == .muteChanged) == (muted != nil) else {
        return .persistenceFailure
      }
      guard case let .valid(current) = readState() else {
        return readStateIsInvalid() ? .persistenceFailure : .notFound
      }
      guard current.nativeCallId == nativeCallId else { return .notFound }
      if current.terminalEvent != nil { return .ignoredAfterTerminal(current) }
      guard current.highestSequence < Int64.max else { return .capacityReached }
      if !type.isTerminal && current.events.count >= Self.maxEvents {
        return .capacityReached
      }
      guard let nextId = uniqueEventId(existing: current.events) else {
        return .persistenceFailure
      }
      let event = PendingNativeCallEvent(
        nativeCallId: nativeCallId,
        sequence: current.highestSequence + 1,
        eventId: nextId,
        type: type,
        occurredAtMs: max(0, nowMs())
      )
      var updated = current
      updated.highestSequence = event.sequence
      if type.isTerminal {
        updated.terminalEvent = event
        updated.terminalRetentionDeadlineMs = Self.saturatingAdd(
          event.occurredAtMs,
          Self.terminalReplayRetentionMs
        )
      }
      updated.answerRequested = updated.answerRequested || type == .answerRequested
      if let muted { updated.muted = muted }
      updated.presented = updated.presented || type == .presented
      updated.events = type.isTerminal && current.events.count >= Self.maxEvents
        ? [event]
        : current.events + [event]

      switch commit(updated) {
      case .committed:
        return .appended(updated, event)
      case .tooLarge where type.isTerminal && updated.events.count > 1:
        updated.events = [event]
        return commit(updated) == .committed
          ? .appended(updated, event)
          : .persistenceFailure
      case .tooLarge:
        return .capacityReached
      case .failed:
        return .persistenceFailure
      }
    }
  }

  /// Durably records that the invitation/presentation deadline has been
  /// satisfied. The original deadline remains immutable for audit and wire
  /// replay, while expiry checks use this marker to distinguish an active call
  /// from a still-pending one after process recreation.
  @discardableResult
  func markConnected(nativeCallId: UUID) -> Bool {
    synchronized {
      guard case var .valid(current) = readState(),
            current.nativeCallId == nativeCallId,
            current.terminalEvent == nil
      else { return false }
      if current.connectedAtMs != nil { return true }
      let observedNow = nowMs()
      guard observedNow >= 0 else { return false }
      current.connectedAtMs = max(current.receivedAtMs, observedNow)
      return commit(current) == .committed
    }
  }

  @discardableResult
  func acknowledge(
    nativeCallId: UUID,
    highestConsumedSequence: Int64,
    acknowledgement: PendingNativeCallAcknowledgement
  ) -> Bool {
    synchronized {
      guard highestConsumedSequence >= 0 else { return false }
      let receipts: [AcknowledgementReceipt]
      switch readReceipts() {
      case let .valid(value): receipts = value
      case .empty: receipts = []
      case .invalid: return false
      }
      let committedReceipt = receipts.first {
        $0.nativeCallId == nativeCallId
          && $0.highestConsumedSequence == highestConsumedSequence
      }
      let descriptor: PendingNativeCallDescriptor?
      switch readState() {
      case let .valid(value): descriptor = value
      case .empty: descriptor = nil
      case .invalid: return false
      }
      if acknowledgement == .terminal, descriptor?.nativeCallId != nativeCallId {
        return committedReceipt != nil
      }
      guard var updated = descriptor, updated.nativeCallId == nativeCallId else {
        return false
      }
      if updated.lastAcknowledgement == acknowledgement,
         updated.lastAcknowledgedSequence == highestConsumedSequence {
        return true
      }

      switch acknowledgement {
      case .none:
        let acknowledgedThrough = (updated.events.first?.sequence ?? (updated.highestSequence + 1)) - 1
        guard highestConsumedSequence > acknowledgedThrough,
              highestConsumedSequence <= updated.highestSequence,
              updated.terminalEvent.map({ highestConsumedSequence < $0.sequence }) ?? true
        else { return false }
        updated.events.removeAll { $0.sequence <= highestConsumedSequence }
        updated.lastAcknowledgement = PendingNativeCallAcknowledgement.none
        updated.lastAcknowledgedSequence = highestConsumedSequence
        return commit(updated) == .committed

      case .adopted:
        let acknowledgedThrough = (updated.events.first?.sequence ?? (updated.highestSequence + 1)) - 1
        guard updated.terminalEvent == nil,
              updated.handoffAcknowledgement == .none,
              highestConsumedSequence > acknowledgedThrough,
              highestConsumedSequence <= updated.highestSequence
        else { return false }
        updated.events.removeAll { $0.sequence <= highestConsumedSequence }
        updated.handoffAcknowledgement = .adopted
        updated.phase = .journal
        updated.wakeHandle = ""
        updated.lastAcknowledgement = .adopted
        updated.lastAcknowledgedSequence = highestConsumedSequence
        return commit(updated) == .committed

      case .terminal:
        guard let terminal = updated.terminalEvent,
              terminal.sequence == updated.highestSequence,
              highestConsumedSequence == updated.highestSequence,
              let digest = Self.digest(updated.callHandle)
        else { return false }
        let observedNow = nowMs()
        guard observedNow >= 0 else { return false }
        let receipt = AcknowledgementReceipt(
          nativeCallId: nativeCallId,
          callHandleDigest: digest,
          highestConsumedSequence: highestConsumedSequence,
          expiresAtMs: Self.saturatingAdd(observedNow, Self.acknowledgementReceiptTtlMs)
        )
        guard commitReceipt(receipt, existing: receipts) else { return false }
        return deleteCommitted()
      }
    }
  }

  private func create(
    _ payload: VoipWakePayload,
    direction: PendingNativeCallDirection
  ) -> PendingNativeCallCreateResult {
    synchronized {
      guard valid(payload) else { return .persistenceFailure }
      guard sweepExpiredTerminalRetentionLocked() else { return .persistenceFailure }
      switch readReceipts() {
      case .invalid:
        return .persistenceFailure
      case let .valid(receipts):
        if let digest = Self.digest(payload.callHandle),
           receipts.contains(where: { $0.callHandleDigest == digest }) {
          return .duplicate(nil)
        }
      case .empty:
        break
      }
      switch readState() {
      case .empty:
        let descriptor = PendingNativeCallDescriptor(
          nativeCallId: payload.nativeCallId,
          callHandle: payload.callHandle,
          wakeHandle: payload.wakeHandle,
          opaqueContactHandle: payload.wakeHandle,
          receivedAtMs: payload.receivedAtMs,
          expiresAtMs: payload.expiresAtMs,
          connectedAtMs: nil,
          highestSequence: 0,
          terminalEvent: nil,
          terminalRetentionDeadlineMs: nil,
          events: [],
          handoffAcknowledgement: .none,
          phase: .preStart,
          answerRequested: false,
          muted: false,
          presented: false,
          lastAcknowledgement: nil,
          lastAcknowledgedSequence: 0,
          direction: direction,
          schemaVersion: PendingNativeCallDescriptor.schemaVersion
        )
        return commit(descriptor) == .committed
          ? .created(descriptor)
          : .persistenceFailure
      case let .valid(descriptor):
        return descriptor.matches(payload, direction: direction)
          ? .duplicate(descriptor)
          : .busy(descriptor)
      case .invalid:
        return .persistenceFailure
      }
    }
  }

  private func valid(_ payload: VoipWakePayload) -> Bool {
    guard payload.nativeCallId.uuidString.lowercased() == payload.callHandle,
          payload.receivedAtMs >= 0,
          payload.expiresAtMs > payload.receivedAtMs
    else { return false }
    let observed = nowMs()
    return observed >= 0
      && payload.receivedAtMs <= observed
      && payload.expiresAtMs > observed
      && payload.expiresAtMs - observed <= VoipPayloadParser.maxFutureSkewMs
  }

  private func readState() -> StoredState {
    do {
      guard let data = try backend.readDescriptor() else { return .empty }
      guard !data.isEmpty, data.count <= Self.maxRecordBytes,
            let value = try? decoder.decode(PendingNativeCallDescriptor.self, from: data),
            structurallyValid(value)
      else { return .invalid }
      return .valid(value)
    } catch {
      return .invalid
    }
  }

  private func readStateIsInvalid() -> Bool {
    if case .invalid = readState() { return true }
    return false
  }

  private func readReceipts() -> ReceiptState {
    do {
      guard let data = try backend.readAcknowledgementReceipts() else { return .empty }
      guard !data.isEmpty, data.count <= Self.maxRecordBytes,
            let envelope = try? decoder.decode(ReceiptEnvelope.self, from: data),
            envelope.version == 1,
            envelope.receipts.count <= Self.maxAcknowledgementReceipts
      else { return .invalid }
      let observed = nowMs()
      guard observed >= 0 else { return .invalid }
      let live = envelope.receipts.filter { $0.expiresAtMs > observed }
      if live != envelope.receipts {
        _ = replaceReceipts(live)
      }
      return live.isEmpty ? .empty : .valid(live)
    } catch {
      return .invalid
    }
  }

  private func structurallyValid(_ value: PendingNativeCallDescriptor) -> Bool {
    guard value.schemaVersion == PendingNativeCallDescriptor.schemaVersion,
          value.nativeCallId.uuidString.lowercased() == value.callHandle,
          (value.wakeHandle.isEmpty || OpaqueCallContactResolver.validHandle(value.wakeHandle)),
          value.opaqueContactHandle.map(OpaqueCallContactResolver.validHandle) ?? true,
          value.receivedAtMs >= 0,
          value.expiresAtMs > value.receivedAtMs,
          value.connectedAtMs.map({ $0 >= value.receivedAtMs }) ?? true,
          value.highestSequence >= 0,
          value.events.count <= Self.maxEvents,
          value.events.allSatisfy({ $0.nativeCallId == value.nativeCallId }),
          value.events.map(\.sequence) == value.events.map(\.sequence).sorted(),
          Set(value.events.map(\.eventId)).count == value.events.count,
          value.events.allSatisfy({ $0.sequence > value.lastAcknowledgedSequence }),
          (value.events.last?.sequence ?? value.lastAcknowledgedSequence) <= value.highestSequence
    else { return false }
    if let terminal = value.terminalEvent {
      let expectedDeadline = Self.saturatingAdd(
        terminal.occurredAtMs,
        Self.terminalReplayRetentionMs
      )
      return terminal.type.isTerminal
        && terminal.sequence == value.highestSequence
        && value.events.contains(terminal)
        && (value.terminalRetentionDeadlineMs == nil
          || value.terminalRetentionDeadlineMs == expectedDeadline)
    }
    return value.terminalRetentionDeadlineMs == nil
      && !value.events.contains(where: { $0.type.isTerminal })
  }

  private func sweepExpiredTerminalRetentionLocked() -> Bool {
    let descriptor: PendingNativeCallDescriptor
    switch readState() {
    case .empty:
      return true
    case .invalid:
      return false
    case let .valid(value):
      descriptor = value
    }
    guard let terminal = descriptor.terminalEvent else { return true }
    let deadline = descriptor.terminalRetentionDeadlineMs
      ?? Self.saturatingAdd(terminal.occurredAtMs, Self.terminalReplayRetentionMs)
    let observedNow = nowMs()
    guard observedNow >= 0 else { return false }
    guard observedNow >= deadline else { return true }

    let receipts: [AcknowledgementReceipt]
    switch readReceipts() {
    case .empty:
      receipts = []
    case let .valid(value):
      receipts = value
    case .invalid:
      return false
    }
    guard let digest = Self.digest(descriptor.callHandle) else { return false }
    let receipt = AcknowledgementReceipt(
      nativeCallId: descriptor.nativeCallId,
      callHandleDigest: digest,
      highestConsumedSequence: descriptor.highestSequence,
      expiresAtMs: Self.saturatingAdd(observedNow, Self.acknowledgementReceiptTtlMs)
    )
    guard commitReceipt(receipt, existing: receipts) else { return false }
    return deleteCommitted()
  }

  private func commit(_ descriptor: PendingNativeCallDescriptor) -> CommitResult {
    guard let data = try? encoder.encode(descriptor) else { return .failed }
    guard data.count <= Self.maxRecordBytes else { return .tooLarge }
    do {
      try backend.replaceDescriptor(with: data)
      guard case let .valid(verified) = readState(), verified == descriptor else {
        return .failed
      }
      return .committed
    } catch {
      return .failed
    }
  }

  private func deleteCommitted() -> Bool {
    do {
      try backend.replaceDescriptor(with: nil)
      return try backend.readDescriptor() == nil
    } catch {
      return false
    }
  }

  private func commitReceipt(
    _ receipt: AcknowledgementReceipt,
    existing: [AcknowledgementReceipt]
  ) -> Bool {
    if existing.contains(receipt) { return true }
    var next = existing.filter { $0.nativeCallId != receipt.nativeCallId }
    next.append(receipt)
    next.sort { $0.expiresAtMs < $1.expiresAtMs }
    if next.count > Self.maxAcknowledgementReceipts {
      next.removeFirst(next.count - Self.maxAcknowledgementReceipts)
    }
    return replaceReceipts(next)
  }

  private func replaceReceipts(_ receipts: [AcknowledgementReceipt]) -> Bool {
    do {
      if receipts.isEmpty {
        try backend.replaceAcknowledgementReceipts(with: nil)
        return try backend.readAcknowledgementReceipts() == nil
      }
      let data = try encoder.encode(ReceiptEnvelope(version: 1, receipts: receipts))
      guard data.count <= Self.maxRecordBytes else { return false }
      try backend.replaceAcknowledgementReceipts(with: data)
      guard let retained = try backend.readAcknowledgementReceipts(), retained == data else {
        return false
      }
      return true
    } catch {
      return false
    }
  }

  private func uniqueEventId(existing: [PendingNativeCallEvent]) -> UUID? {
    for _ in 0..<8 {
      let candidate = eventId()
      if !existing.contains(where: { $0.eventId == candidate }) { return candidate }
    }
    return nil
  }

  private static func digest(_ value: String) -> String? {
    guard !value.isEmpty, value.utf8.count <= 64 else { return nil }
    return SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
  }

  private static func saturatingAdd(_ lhs: Int64, _ rhs: Int64) -> Int64 {
    let (sum, overflow) = lhs.addingReportingOverflow(rhs)
    return overflow ? Int64.max : sum
  }

  private func synchronized<T>(_ action: () -> T) -> T {
    lock.lock()
    defer { lock.unlock() }
    return action()
  }
}
