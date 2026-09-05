import Flutter
import Foundation
import PushKit

internal struct MknoonVoipTokenSnapshot: Codable, Equatable {
  static let protocolVersion = 1
  static let capabilityVersion = 1

  let version: Int
  let token: String
  let environment: String
  let topic: String
  let capabilityVersion: Int
  let refreshEpoch: Int64
  let invalidated: Bool

  var wireValue: [String: Any] {
    [
      "version": version,
      "token": token,
      "environment": environment,
      "topic": topic,
      "capabilityVersion": capabilityVersion,
      "refreshEpoch": refreshEpoch,
      "invalidated": invalidated,
    ]
  }
}

internal protocol MknoonVoipTokenBackend: AnyObject {
  func read() throws -> Data?
  func replace(with data: Data?) throws
}

internal final class RunnerVoipTokenFileBackend: MknoonVoipTokenBackend {
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
    url = root.appendingPathComponent("voip-token-v1.json")
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

internal final class MknoonVoipTokenAuthority {
  typealias EventHandler = (MknoonVoipTokenSnapshot) -> Void

  private enum ReadState {
    case absent
    case valid(MknoonVoipTokenSnapshot)
    case corrupt
    case unreadable
  }

  private let backend: MknoonVoipTokenBackend
  private let lock = NSRecursiveLock()
  private let encoder = JSONEncoder()
  private let decoder = JSONDecoder()
  private var eventHandler: EventHandler?

  init(backend: MknoonVoipTokenBackend) {
    self.backend = backend
    encoder.outputFormatting = [.sortedKeys]
  }

  static func runnerDefault() -> MknoonVoipTokenAuthority? {
    guard let backend = try? RunnerVoipTokenFileBackend() else { return nil }
    return MknoonVoipTokenAuthority(backend: backend)
  }

  static func production() -> MknoonVoipTokenAuthority {
    runnerDefault() ?? MknoonVoipTokenAuthority(backend: UnavailableVoipTokenBackend())
  }

  func setEventHandler(_ handler: EventHandler?) {
    synchronized { eventHandler = handler }
  }

  /// Installs the listener and replays the latest durable snapshot in one
  /// authority-locked operation. This closes the cross-channel gap between a
  /// Flutter method-channel read and EventChannel `onListen` without allowing
  /// a newer live update to be delivered before an older replay.
  func setEventHandlerAndReplayCurrent(_ handler: @escaping EventHandler) {
    synchronized {
      eventHandler = handler
      guard case let .valid(snapshot) = readState() else { return }
      handler(snapshot)
    }
  }

  func current() -> MknoonVoipTokenSnapshot? {
    synchronized {
      guard case let .valid(snapshot) = readState() else { return nil }
      return snapshot
    }
  }

  /// Returns false on every durability failure. An idempotent duplicate does
  /// not advance the generation and does not emit a second registration event.
  @discardableResult
  func update(token: Data, environment: String, topic: String) -> Bool {
    synchronized {
      guard !token.isEmpty, token.count <= 128,
            Self.validEnvironment(environment), Self.validTopic(topic)
      else { return false }
      let hex = token.map { String(format: "%02x", $0) }.joined()
      guard hex.count == token.count * 2 else { return false }
      let priorEpoch: Int64
      switch readState() {
      case .absent:
        priorEpoch = 0
      case let .valid(current):
        if !current.invalidated, current.token == hex,
           current.environment == environment, current.topic == topic {
          return true
        }
        priorEpoch = current.refreshEpoch
      case .corrupt, .unreadable:
        return false
      }
      guard priorEpoch < Int64.max else { return false }
      let snapshot = MknoonVoipTokenSnapshot(
        version: MknoonVoipTokenSnapshot.protocolVersion,
        token: hex,
        environment: environment,
        topic: topic,
        capabilityVersion: MknoonVoipTokenSnapshot.capabilityVersion,
        refreshEpoch: priorEpoch + 1,
        invalidated: false
      )
      guard commit(snapshot) else { return false }
      eventHandler?(snapshot)
      return true
    }
  }

  /// Moves the durable registration of the unchanged token to a strictly
  /// newer refresh epoch after the relay refused the current one as stale
  /// (its refresh-epoch high-water survives revokes). `minimum` lets one
  /// advance jump past a high-water the client cannot see (wall-clock
  /// seconds), so a device recovers in a single round trip regardless of how
  /// far ahead the relay is. Refused, and nothing changes, unless the durable
  /// snapshot is valid, not invalidated, and still at `expected`.
  func advanceRefreshEpoch(expected: Int64, minimum: Int64) -> MknoonVoipTokenSnapshot? {
    synchronized {
      guard case let .valid(current) = readState(),
            !current.invalidated,
            current.refreshEpoch == expected,
            current.refreshEpoch < Int64.max
      else { return nil }
      let next = max(current.refreshEpoch + 1, minimum)
      let snapshot = MknoonVoipTokenSnapshot(
        version: MknoonVoipTokenSnapshot.protocolVersion,
        token: current.token,
        environment: current.environment,
        topic: current.topic,
        capabilityVersion: MknoonVoipTokenSnapshot.capabilityVersion,
        refreshEpoch: next,
        invalidated: false
      )
      guard commit(snapshot) else { return nil }
      eventHandler?(snapshot)
      return snapshot
    }
  }

  /// Keeps the last exact epoch across process restart so Dart can revoke that
  /// generation without ever receiving or persisting a guessed environment.
  @discardableResult
  func invalidate() -> Bool {
    synchronized {
      let current: MknoonVoipTokenSnapshot
      switch readState() {
      case .absent:
        return true
      case let .valid(snapshot):
        current = snapshot
      case .corrupt, .unreadable:
        return false
      }
      if current.invalidated { return true }
      let invalidated = MknoonVoipTokenSnapshot(
        version: MknoonVoipTokenSnapshot.protocolVersion,
        token: "",
        environment: current.environment,
        topic: current.topic,
        capabilityVersion: MknoonVoipTokenSnapshot.capabilityVersion,
        refreshEpoch: current.refreshEpoch,
        invalidated: true
      )
      guard commit(invalidated) else { return false }
      eventHandler?(invalidated)
      return true
    }
  }

  private func readState() -> ReadState {
    do {
      guard let data = try backend.read() else { return .absent }
      guard !data.isEmpty, data.count <= 1_024 else { return .corrupt }
      do {
        let snapshot = try decoder.decode(MknoonVoipTokenSnapshot.self, from: data)
        guard structurallyValid(snapshot) else { return .corrupt }
        return .valid(snapshot)
      } catch {
        return .corrupt
      }
    } catch {
      return .unreadable
    }
  }

  private func commit(_ snapshot: MknoonVoipTokenSnapshot) -> Bool {
    do {
      let data = try encoder.encode(snapshot)
      guard data.count <= 1_024 else { return false }
      try backend.replace(with: data)
      guard let retained = try backend.read(), retained == data else { return false }
      return true
    } catch {
      return false
    }
  }

  private func structurallyValid(_ value: MknoonVoipTokenSnapshot) -> Bool {
    value.version == MknoonVoipTokenSnapshot.protocolVersion
      && value.capabilityVersion == MknoonVoipTokenSnapshot.capabilityVersion
      && value.refreshEpoch > 0
      && Self.validEnvironment(value.environment)
      && Self.validTopic(value.topic)
      && (value.invalidated
        ? value.token.isEmpty
        : !value.token.isEmpty
          && value.token.count <= 256
          && value.token.count.isMultiple(of: 2)
          && value.token.unicodeScalars.allSatisfy {
            CharacterSet(charactersIn: "0123456789abcdef").contains($0)
          })
  }

  private static func validEnvironment(_ value: String) -> Bool {
    value == "development" || value == "production"
  }

  private static func validTopic(_ value: String) -> Bool {
    value.hasSuffix(".voip") && value.utf8.count > 5 && value.utf8.count <= 255
      && value.unicodeScalars.allSatisfy {
        CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-")
          .contains($0)
      }
  }

  private func synchronized<T>(_ action: () -> T) -> T {
    lock.lock()
    defer { lock.unlock() }
    return action()
  }
}

private final class UnavailableVoipTokenBackend: MknoonVoipTokenBackend {
  private enum Unavailable: Error { case unavailable }
  func read() throws -> Data? { throw Unavailable.unavailable }
  func replace(with data: Data?) throws { throw Unavailable.unavailable }
}

internal final class MknoonVoipTokenBridge: NSObject, FlutterStreamHandler {
  static let methodChannelName = "mknoon/ios_voip_token"
  static let eventChannelName = "mknoon/ios_voip_token/events"

  private let authority: MknoonVoipTokenAuthority
  private let methodChannel: FlutterMethodChannel?
  private let eventChannel: FlutterEventChannel?
  private let now: () -> Date
  private let subscriptionLock = NSLock()
  private let lock = NSLock()
  private var sink: FlutterEventSink?
  private var generation: Int64 = 0

  init(
    authority: MknoonVoipTokenAuthority,
    messenger: FlutterBinaryMessenger?,
    now: @escaping () -> Date = Date.init
  ) {
    self.authority = authority
    self.now = now
    if let messenger {
      methodChannel = FlutterMethodChannel(
        name: Self.methodChannelName,
        binaryMessenger: messenger
      )
      eventChannel = FlutterEventChannel(
        name: Self.eventChannelName,
        binaryMessenger: messenger
      )
    } else {
      methodChannel = nil
      eventChannel = nil
    }
    super.init()
    methodChannel?.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
    eventChannel?.setStreamHandler(self)
  }

  deinit {
    authority.setEventHandler(nil)
    methodChannel?.setMethodCallHandler(nil)
    eventChannel?.setStreamHandler(nil)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "readCurrent":
      guard Self.versionOnly(call.arguments) else {
        result(FlutterError(code: "bad_args", message: "invalid VoIP token arguments", details: nil))
        return
      }
      result(authority.current()?.wireValue)
    case "advanceRefreshEpoch":
      guard let expected = Self.expectedRefreshEpoch(call.arguments) else {
        result(FlutterError(code: "bad_args", message: "invalid VoIP token arguments", details: nil))
        return
      }
      let minimum = Int64(max(0, now().timeIntervalSince1970.rounded(.down)))
      guard let advanced = authority.advanceRefreshEpoch(expected: expected, minimum: minimum) else {
        result(
          FlutterError(
            code: "epoch_advance_refused",
            message: "VoIP token refresh epoch was not advanced",
            details: nil
          )
        )
        return
      }
      result(advanced.wireValue)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  func onListen(
    withArguments arguments: Any?,
    eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? {
    guard arguments == nil else {
      return FlutterError(code: "bad_args", message: "invalid VoIP token arguments", details: nil)
    }
    subscriptionLock.lock()
    defer { subscriptionLock.unlock() }
    lock.lock()
    generation += 1
    let subscriptionGeneration = generation
    sink = events
    lock.unlock()
    authority.setEventHandlerAndReplayCurrent { [weak self] snapshot in
      self?.emit(snapshot, subscriptionGeneration: subscriptionGeneration)
    }
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    subscriptionLock.lock()
    defer { subscriptionLock.unlock() }
    lock.lock()
    generation += 1
    sink = nil
    lock.unlock()
    authority.setEventHandler(nil)
    return nil
  }

  private func emit(
    _ snapshot: MknoonVoipTokenSnapshot,
    subscriptionGeneration: Int64
  ) {
    lock.lock()
    guard generation == subscriptionGeneration, let sink else {
      lock.unlock()
      return
    }
    lock.unlock()
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      self.lock.lock()
      let current = self.generation == subscriptionGeneration && self.sink != nil
      self.lock.unlock()
      if current { sink(snapshot.wireValue) }
    }
  }

  private static func versionOnly(_ arguments: Any?) -> Bool {
    if arguments == nil { return true }
    guard let map = arguments as? [String: Any], Set(map.keys) == ["version"] else {
      return false
    }
    return integerValue(map["version"]) == 1
  }

  /// Strict `{version: 1, expectedRefreshEpoch: <positive integer>}`.
  private static func expectedRefreshEpoch(_ arguments: Any?) -> Int64? {
    guard let map = arguments as? [String: Any],
          Set(map.keys) == ["version", "expectedRefreshEpoch"],
          integerValue(map["version"]) == 1,
          let expected = integerValue(map["expectedRefreshEpoch"]),
          expected > 0
    else { return nil }
    return expected
  }

  private static func integerValue(_ value: Any?) -> Int64? {
    guard let number = value as? NSNumber,
          CFGetTypeID(number) != CFBooleanGetTypeID()
    else { return nil }
    switch String(cString: number.objCType) {
    case "c", "s", "i", "l", "q", "C", "S", "I", "L", "Q":
      return number.int64Value
    default:
      return nil
    }
  }
}

internal enum MknoonVoipPushReportPolicy: Equatable {
  case notRequired
  case legacyRequired
  case metadataRequired
}

/// A deliberately closed diagnostic vocabulary for the PushKit-to-CallKit
/// boundary. Associated values are existing finite enums (or Bool), so this
/// type cannot carry a token, payload field, identifier, topic, or raw error.
internal enum MknoonVoipPushDiagnosticEvent: Equatable {
  case delegateEntry(MknoonVoipPushReportPolicy)
  case capability(enabled: Bool)
  case registration(enabled: Bool)
  case tokenUpdate(accepted: Bool)
  case tokenInvalidation(accepted: Bool)
  case parserAccepted
  case parserRejected(VoipPayloadRejectionReason)
  case presentation(MknoonCallPresentationResult)
  case complianceCompleted(MknoonVoipPushReportPolicy)
  case rejectedWithoutReportCompleted

  var logLine: String {
    let value: String
    switch self {
    case .delegateEntry(.legacyRequired):
      value = "delegate=legacy"
    case .delegateEntry(.metadataRequired):
      value = "delegate=metadata_required"
    case .delegateEntry(.notRequired):
      value = "delegate=metadata_not_required"
    case .capability(enabled: true):
      value = "capability=enabled"
    case .capability(enabled: false):
      value = "capability=disabled"
    case .registration(enabled: true):
      value = "registration=enabled"
    case .registration(enabled: false):
      value = "registration=disabled"
    case .tokenUpdate(accepted: true):
      value = "token=updated"
    case .tokenUpdate(accepted: false):
      value = "token=update_rejected"
    case .tokenInvalidation(accepted: true):
      value = "token=invalidated"
    case .tokenInvalidation(accepted: false):
      value = "token=invalidation_rejected"
    case .parserAccepted:
      value = "parser=accepted"
    case let .parserRejected(reason):
      value = "parser=\(reason.rawValue)"
    case .presentation(.presented):
      value = "presentation=presented"
    case .presentation(.duplicate):
      value = "presentation=duplicate"
    case .presentation(.busy):
      value = "presentation=busy"
    case .presentation(.disabled):
      value = "presentation=disabled"
    case .presentation(.invalid):
      value = "presentation=invalid"
    case .presentation(.persistenceFailure):
      value = "presentation=persistenceFailure"
    case .presentation(.callKitFailure):
      value = "presentation=callKitFailure"
    case .complianceCompleted(.legacyRequired):
      value = "compliance=legacy_completed"
    case .complianceCompleted(.metadataRequired):
      value = "compliance=metadata_required_completed"
    case .complianceCompleted(.notRequired):
      value = "compliance=metadata_not_required_completed"
    case .rejectedWithoutReportCompleted:
      value = "completion=rejected_without_report"
    }
    return "[MKNOON_PUSHKIT_DIAG] \(value)"
  }
}

internal typealias MknoonVoipPushDiagnosticSink = (MknoonVoipPushDiagnosticEvent) -> Void

internal protocol MknoonIncomingCallReporting: AnyObject {
  func presentIncoming(
    _ payload: VoipWakePayload,
    reportPolicy: MknoonVoipPushReportPolicy,
    completion: @escaping (MknoonCallPresentationResult) -> Void
  )
  func satisfyRequiredVoipPushReport(
    reportPolicy: MknoonVoipPushReportPolicy,
    completion: @escaping () -> Void
  )
}

extension MknoonCallKitController: MknoonIncomingCallReporting {}

internal protocol MknoonVoipEnvironmentProviding {
  func environment() -> String?
}

internal protocol MknoonVoipPushRegistrationDriving: AnyObject {
  var enabled: Bool { get }
  func enable(delegate: PKPushRegistryDelegate)
  func disable()
}

internal final class SystemVoipPushRegistrationDriver: MknoonVoipPushRegistrationDriving {
  private var registry: PKPushRegistry?

  var enabled: Bool {
    registry?.desiredPushTypes?.contains(.voIP) == true
  }

  func enable(delegate: PKPushRegistryDelegate) {
    precondition(Thread.isMainThread)
    if let registry {
      registry.delegate = delegate
      registry.desiredPushTypes = [.voIP]
      return
    }
    let created = PKPushRegistry(queue: .main)
    created.delegate = delegate
    created.desiredPushTypes = [.voIP]
    registry = created
  }

  func disable() {
    precondition(Thread.isMainThread)
    registry?.desiredPushTypes = []
    registry?.delegate = nil
    registry = nil
  }
}

/// Resolves the APNs environment the PushKit token belongs to.
///
/// The signed `aps-environment` of the embedded provisioning profile wins: a
/// dev-signed device build is re-signed with `aps-environment=development`
/// while Info.plist still carries the Release build setting, and labelling
/// that sandbox token `production` costs the relay one rejected APNs attempt
/// per wake. App Store builds carry no embedded profile, so Info.plist (the
/// same build setting as `aps-environment` in Runner.entitlements) is the
/// fallback. Invalid or absent values deliberately disable token publication
/// instead of inferring an APNs environment from the build type.
internal struct EntitlementVoipEnvironmentProvider: MknoonVoipEnvironmentProviding {
  static let embeddedProfileFileName = "embedded.mobileprovision"

  private let infoPlistValue: () -> Any?
  private let embeddedProfile: () -> Data?

  init(bundle: Bundle = .main) {
    self.init(
      infoPlistValue: { bundle.object(forInfoDictionaryKey: "MknoonVoipEnvironment") },
      embeddedProfile: {
        let url = bundle.bundleURL.appendingPathComponent(Self.embeddedProfileFileName)
        return FileManager.default.contents(atPath: url.path)
      }
    )
  }

  init(infoPlistValue: @escaping () -> Any?, embeddedProfile: @escaping () -> Data?) {
    self.infoPlistValue = infoPlistValue
    self.embeddedProfile = embeddedProfile
  }

  func environment() -> String? {
    if let signed = Self.signedApsEnvironment(from: embeddedProfile()) {
      return signed
    }
    guard let raw = infoPlistValue() as? String, Self.isValid(raw) else { return nil }
    return raw
  }

  /// Extracts `Entitlements["aps-environment"]` from the CMS-wrapped plist of
  /// an embedded provisioning profile. Anything malformed yields nil.
  static func signedApsEnvironment(from data: Data?) -> String? {
    guard let data, !data.isEmpty,
      let plistStart = data.range(of: Data("<plist".utf8)),
      let plistEnd = data.range(
        of: Data("</plist>".utf8), in: plistStart.lowerBound..<data.endIndex)
    else { return nil }
    let start = data.range(of: Data("<?xml".utf8), in: 0..<plistStart.lowerBound)?.lowerBound
      ?? plistStart.lowerBound
    let plistData = data.subdata(in: start..<plistEnd.upperBound)
    guard
      let plist = try? PropertyListSerialization.propertyList(
        from: plistData, options: [], format: nil) as? [String: Any],
      let entitlements = plist["Entitlements"] as? [String: Any],
      let value = entitlements["aps-environment"] as? String,
      isValid(value)
    else { return nil }
    return value
  }

  private static func isValid(_ value: String) -> Bool {
    value == "development" || value == "production"
  }
}

private final class VoipPushCompletionGate {
  private let lock = NSLock()
  private var completed = false
  private let completion: () -> Void

  init(_ completion: @escaping () -> Void) { self.completion = completion }

  func complete() {
    lock.lock()
    guard !completed else { lock.unlock(); return }
    completed = true
    lock.unlock()
    completion()
  }
}

/// Strongly owned by AppDelegate. It never waits for Flutter, Go, mailbox
/// retrieval, or the network before returning the PushKit completion handler.
internal final class MknoonVoipPushRegistry: NSObject, PKPushRegistryDelegate {
  private let controller: MknoonIncomingCallReporting
  private let parser: VoipPayloadParser
  let tokenAuthority: MknoonVoipTokenAuthority
  private let capability: NativeCallCapabilityPersisting
  private let registrationDriver: MknoonVoipPushRegistrationDriving
  private let environmentProvider: MknoonVoipEnvironmentProviding
  private let bundleIdentifier: () -> String?
  private let runtimeWake: () -> Void
  private let diagnosticSink: MknoonVoipPushDiagnosticSink

  init(
    controller: MknoonIncomingCallReporting,
    parser: VoipPayloadParser = VoipPayloadParser(),
    tokenAuthority: MknoonVoipTokenAuthority,
    capability: NativeCallCapabilityPersisting,
    registrationDriver: MknoonVoipPushRegistrationDriving = SystemVoipPushRegistrationDriver(),
    environmentProvider: MknoonVoipEnvironmentProviding = EntitlementVoipEnvironmentProvider(),
    bundleIdentifier: @escaping () -> String? = { Bundle.main.bundleIdentifier },
    runtimeWake: @escaping () -> Void = {},
    diagnosticSink: @escaping MknoonVoipPushDiagnosticSink = { event in
      mknoonCallKitDiag(event.logLine)
    }
  ) {
    self.controller = controller
    self.parser = parser
    self.tokenAuthority = tokenAuthority
    self.capability = capability
    self.registrationDriver = registrationDriver
    self.environmentProvider = environmentProvider
    self.bundleIdentifier = bundleIdentifier
    self.runtimeWake = runtimeWake
    self.diagnosticSink = diagnosticSink
    super.init()
  }

  @discardableResult
  func start() -> Bool {
    applyCapability(capability.enabled)
  }

  func stop() {
    onMain { self.registrationDriver.disable() }
  }

  @discardableResult
  func applyCapability(_ enabled: Bool) -> Bool {
    onMain {
      if enabled {
        self.registrationDriver.enable(delegate: self)
        self.diagnosticSink(.registration(enabled: true))
        return true
      }
      self.registrationDriver.disable()
      self.diagnosticSink(.registration(enabled: false))
      let invalidated = self.tokenAuthority.invalidate()
      self.diagnosticSink(.tokenInvalidation(accepted: invalidated))
      return invalidated
    }
  }

  func pushRegistry(
    _ registry: PKPushRegistry,
    didUpdate pushCredentials: PKPushCredentials,
    for type: PKPushType
  ) {
    guard type == .voIP else { return }
    _ = acceptUpdatedVoipToken(pushCredentials.token)
  }

  @discardableResult
  func acceptUpdatedVoipToken(_ token: Data) -> Bool {
    guard capability.enabled,
          let environment = environmentProvider.environment(),
          let bundle = bundleIdentifier(), !bundle.isEmpty
    else {
      diagnosticSink(.tokenUpdate(accepted: false))
      return false
    }
    let accepted = tokenAuthority.update(
      token: token,
      environment: environment,
      topic: bundle + ".voip"
    )
    diagnosticSink(.tokenUpdate(accepted: accepted))
    return accepted
  }

  func pushRegistry(
    _ registry: PKPushRegistry,
    didInvalidatePushTokenFor type: PKPushType
  ) {
    guard type == .voIP else { return }
    let invalidated = tokenAuthority.invalidate()
    diagnosticSink(.tokenInvalidation(accepted: invalidated))
  }

  func pushRegistry(
    _ registry: PKPushRegistry,
    didReceiveIncomingPushWith payload: PKPushPayload,
    for type: PKPushType,
    completion: @escaping () -> Void
  ) {
    guard type == .voIP else { completion(); return }
    handlePush(
      dictionary: payload.dictionaryPayload,
      reportPolicy: .legacyRequired,
      completion: completion
    )
  }

  @available(iOS 26.4, *)
  func pushRegistry(
    _ registry: PKPushRegistry,
    didReceiveIncomingVoIPPushWith payload: PKPushPayload,
    metadata: PKVoIPPushMetadata,
    withCompletionHandler completion: @escaping () -> Void
  ) {
    handlePush(
      dictionary: payload.dictionaryPayload,
      reportPolicy: metadata.mustReport ? .metadataRequired : .notRequired,
      completion: completion
    )
  }

  func handlePush(dictionary: [AnyHashable: Any], completion: @escaping () -> Void) {
    handlePush(dictionary: dictionary, reportPolicy: .legacyRequired, completion: completion)
  }

  func handlePush(
    dictionary: [AnyHashable: Any],
    reportRequired: Bool,
    completion: @escaping () -> Void
  ) {
    handlePush(
      dictionary: dictionary,
      reportPolicy: reportRequired ? .metadataRequired : .notRequired,
      completion: completion
    )
  }

  func handlePush(
    dictionary: [AnyHashable: Any],
    reportPolicy: MknoonVoipPushReportPolicy,
    completion: @escaping () -> Void
  ) {
    let gate = VoipPushCompletionGate(completion)
    let emitDiagnostic = diagnosticSink
    emitDiagnostic(.delegateEntry(reportPolicy))
    emitDiagnostic(.capability(enabled: capability.enabled))
    let payload: VoipWakePayload
    switch parser.parse(dictionary: dictionary) {
    case let .accepted(acceptedPayload):
      emitDiagnostic(.parserAccepted)
      payload = acceptedPayload
    case let .rejected(reason):
      emitDiagnostic(.parserRejected(reason))
      guard reportPolicy != .notRequired else {
        emitDiagnostic(.rejectedWithoutReportCompleted)
        gate.complete()
        return
      }
      controller.satisfyRequiredVoipPushReport(reportPolicy: reportPolicy) {
        emitDiagnostic(.complianceCompleted(reportPolicy))
        gate.complete()
      }
      return
    }
    let shouldWakeRuntime = capability.enabled
    controller.presentIncoming(payload, reportPolicy: reportPolicy) { result in
      emitDiagnostic(.presentation(result))
      gate.complete()
    }
    // This may cause the established implicit engine to attach, but it is not
    // part of the completion chain above.
    if shouldWakeRuntime { runtimeWake() }
  }

  private func onMain<T>(_ action: @escaping () -> T) -> T {
    if Thread.isMainThread { return action() }
    return DispatchQueue.main.sync(execute: action)
  }
}
