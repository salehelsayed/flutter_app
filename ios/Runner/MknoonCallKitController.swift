import AVFoundation
import CallKit
import Foundation
import os.log

/// CallKit diagnostics carry only fixed wire names and outcomes (never a
/// handle, token or contact), so they are logged public: NSLog lines from a
/// release build reach the device syslog fully redacted as `<private>`.
private let callKitDiagLog = OSLog(subsystem: "com.mknoon.app", category: "callkit")

func mknoonCallKitDiag(_ message: String) {
  os_log("%{public}@", log: callKitDiagLog, type: .default, message)
}

internal enum MknoonCallPresentationResult: Equatable {
  case presented
  case duplicate
  case busy
  case disabled
  case invalid
  case persistenceFailure
  case callKitFailure
}

private enum MknoonOutgoingRegistrationDecision {
  case duplicate
  case rejected
  case created(UUID, VoipWakePayload)
}

internal struct MknoonCallAudioState: Equatable {
  let active: Bool
  let muted: Bool
  let route: String
  let availableRoutes: [String]
}

internal protocol MknoonCallProviding: AnyObject {
  func setDelegate(_ delegate: CXProviderDelegate?, queue: DispatchQueue?)
  func reportNewIncomingCall(
    with UUID: UUID,
    update: CXCallUpdate,
    completion: @escaping @Sendable (Error?) -> Void
  )
  func reportCall(with UUID: UUID, updated update: CXCallUpdate)
  func reportCall(with UUID: UUID, endedAt dateEnded: Date?, reason endedReason: CXCallEndedReason)
  func reportOutgoingCall(with UUID: UUID, startedConnectingAt dateStartedConnecting: Date?)
  func reportOutgoingCall(with UUID: UUID, connectedAt dateConnected: Date?)
}

extension CXProvider: MknoonCallProviding {}

internal protocol MknoonCallTransactionRequesting: AnyObject {
  func request(_ transaction: CXTransaction, completion: @escaping @Sendable (Error?) -> Void)
}

extension CXCallController: MknoonCallTransactionRequesting {}

internal protocol MknoonCallAudioManaging: AnyObject {
  func prepareForCallKitActivation() throws
  func releaseAfterCallKitDeactivation()
  func routeState() -> (route: String, available: [String])
  func requestRoute(_ route: String) -> Bool
}

internal final class MknoonSystemCallAudioManager: MknoonCallAudioManaging {
  private let session: AVAudioSession

  init(session: AVAudioSession = .sharedInstance()) {
    self.session = session
  }

  func prepareForCallKitActivation() throws {
    try session.setCategory(
      .playAndRecord,
      mode: .voiceChat,
      options: [.allowBluetoothHFP, .allowBluetoothA2DP]
    )
  }

  func releaseAfterCallKitDeactivation() {
    try? session.overrideOutputAudioPort(.none)
    try? session.setPreferredInput(nil)
  }

  func routeState() -> (route: String, available: [String]) {
    let current = routeName(for: session.currentRoute.outputs.first?.portType)
    var available: Set<String> = ["system_default", "earpiece", "speaker"]
    for input in session.availableInputs ?? [] {
      switch input.portType {
      case .bluetoothHFP, .bluetoothLE, .bluetoothA2DP:
        available.insert("bluetooth")
      case .headsetMic, .headphones, .usbAudio:
        available.insert("wired_headset")
      default:
        break
      }
    }
    if current != "system_default" { available.insert(current) }
    let ordered = ["system_default", "earpiece", "speaker", "wired_headset", "bluetooth"]
      .filter(available.contains)
    return (current, ordered)
  }

  func requestRoute(_ route: String) -> Bool {
    do {
      switch route {
      case "system_default", "earpiece":
        try session.setPreferredInput(nil)
        try session.overrideOutputAudioPort(.none)
      case "speaker":
        try session.setPreferredInput(nil)
        try session.overrideOutputAudioPort(.speaker)
      case "wired_headset", "bluetooth":
        let target = (session.availableInputs ?? []).first { input in
          switch (route, input.portType) {
          case ("wired_headset", .headsetMic), ("wired_headset", .headphones),
               ("wired_headset", .usbAudio),
               ("bluetooth", .bluetoothHFP), ("bluetooth", .bluetoothLE),
               ("bluetooth", .bluetoothA2DP):
            return true
          default:
            return false
          }
        }
        guard let target else { return false }
        try session.overrideOutputAudioPort(.none)
        try session.setPreferredInput(target)
      default:
        return false
      }
      return true
    } catch {
      return false
    }
  }

  private func routeName(for port: AVAudioSession.Port?) -> String {
    switch port {
    case .builtInReceiver: return "earpiece"
    case .builtInSpeaker: return "speaker"
    case .headphones, .headsetMic, .usbAudio: return "wired_headset"
    case .bluetoothHFP, .bluetoothLE, .bluetoothA2DP: return "bluetooth"
    default: return "system_default"
    }
  }
}

internal protocol NativeCallCapabilityPersisting: AnyObject {
  var enabled: Bool { get }
  func setEnabled(_ enabled: Bool) -> Bool
}

internal final class UserDefaultsNativeCallCapabilityStore: NativeCallCapabilityPersisting {
  private static let key = "mknoon.ios.call-capability-v1"
  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) { self.defaults = defaults }

  var enabled: Bool { defaults.bool(forKey: Self.key) }

  func setEnabled(_ enabled: Bool) -> Bool {
    defaults.set(enabled, forKey: Self.key)
    return defaults.bool(forKey: Self.key) == enabled
  }
}

private final class UnavailablePendingNativeCallBackend: PendingNativeCallBackend {
  private enum Unavailable: Error { case unavailable }
  func readDescriptor() throws -> Data? { throw Unavailable.unavailable }
  func replaceDescriptor(with data: Data?) throws { throw Unavailable.unavailable }
  func readAcknowledgementReceipts() throws -> Data? { throw Unavailable.unavailable }
  func replaceAcknowledgementReceipts(with data: Data?) throws { throw Unavailable.unavailable }
}

private final class UnavailableOpaqueCallContactBackend: OpaqueCallContactBackend {
  private enum Unavailable: Error { case unavailable }
  func read() throws -> Data? { throw Unavailable.unavailable }
  func replace(with data: Data?) throws { throw Unavailable.unavailable }
}

/// Process-wide native lifecycle owner. Product state remains in Dart; this
/// object owns only CallKit projection, the bounded native journal, and the
/// CallKit-controlled audio gate.
internal final class MknoonCallKitController: NSObject, CXProviderDelegate {
  typealias EventHandler = (PendingNativeCallEvent) -> Void

  private struct IncomingReportWaiter {
    let coalesced: Bool
    let completion: (MknoonCallPresentationResult) -> Void
  }

  /// Matches Dart's authenticated-envelope future clock-skew allowance. Raw
  /// PushKit payloads deliberately keep their stricter zero-skew boundary.
  static let authenticatedPeerClockSkewMs: Int64 = 30_000

  private let provider: MknoonCallProviding
  private let transactionRequester: MknoonCallTransactionRequesting
  private let store: PendingNativeCallStore
  private let contacts: OpaqueCallContactResolver
  private let audio: MknoonCallAudioManaging
  private let capability: NativeCallCapabilityPersisting
  private let nowMs: () -> Int64
  private let notificationCenter: NotificationCenter
  private let lock = NSRecursiveLock()
  private var eventHandler: EventHandler?
  private var capabilityChangeHandler: ((Bool) -> Bool)?
  private var endedCallIds: Set<UUID> = []
  private var answeredCallIds: Set<UUID> = []
  private var mutedCallIds: Set<UUID> = []
  private var audioActivatedCallIds: Set<UUID> = []
  private var mediaClaimedCallIds: Set<UUID> = []
  private var incomingReportWaiters: [UUID: [IncomingReportWaiter]] = [:]
  private var expiryWorkItem: DispatchWorkItem?
  /// An answered call whose answer the runtime never consumed is a phantom:
  /// CallKit shows it connected while nothing signals or carries media behind
  /// it. Bound that state instead of letting it sit until the user hangs up.
  static let answerAdoptionBoundMs: Int64 = 10_000
  private var answerAdoptionWorkItem: DispatchWorkItem?

  init(
    provider: MknoonCallProviding,
    transactionRequester: MknoonCallTransactionRequesting,
    store: PendingNativeCallStore,
    contacts: OpaqueCallContactResolver,
    audio: MknoonCallAudioManaging,
    capability: NativeCallCapabilityPersisting,
    nowMs: @escaping () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1_000) },
    notificationCenter: NotificationCenter = .default,
    delegateQueue: DispatchQueue? = nil
  ) {
    self.provider = provider
    self.transactionRequester = transactionRequester
    self.store = store
    self.contacts = contacts
    self.audio = audio
    self.capability = capability
    self.nowMs = nowMs
    self.notificationCenter = notificationCenter
    super.init()
    provider.setDelegate(self, queue: delegateQueue)
    notificationCenter.addObserver(
      self,
      selector: #selector(audioRouteChanged),
      name: AVAudioSession.routeChangeNotification,
      object: nil
    )
    notificationCenter.addObserver(
      self,
      selector: #selector(audioInterrupted),
      name: AVAudioSession.interruptionNotification,
      object: nil
    )
    notificationCenter.addObserver(
      self,
      selector: #selector(mediaServicesReset),
      name: AVAudioSession.mediaServicesWereResetNotification,
      object: nil
    )
    restorePersistedRuntimeState()
    expirePendingIfNecessary()
  }

  deinit {
    expiryWorkItem?.cancel()
    notificationCenter.removeObserver(self)
    provider.setDelegate(nil, queue: nil)
  }

  static func production(
    capability: NativeCallCapabilityPersisting = UserDefaultsNativeCallCapabilityStore()
  ) -> MknoonCallKitController {
    let configuration = CXProviderConfiguration()
    configuration.supportsVideo = false
    configuration.maximumCallGroups = 1
    configuration.maximumCallsPerCallGroup = 1
    configuration.supportedHandleTypes = [.generic]
    configuration.includesCallsInRecents = false
    let provider = CXProvider(configuration: configuration)
    let store = PendingNativeCallStore.runnerDefault()
      ?? PendingNativeCallStore(backend: UnavailablePendingNativeCallBackend())
    let contacts = OpaqueCallContactResolver.runnerDefault()
      ?? OpaqueCallContactResolver(backend: UnavailableOpaqueCallContactBackend())
    return MknoonCallKitController(
      provider: provider,
      transactionRequester: CXCallController(),
      store: store,
      contacts: contacts,
      audio: MknoonSystemCallAudioManager(),
      capability: capability,
      delegateQueue: DispatchQueue(label: "com.mknoon.callkit.delegate")
    )
  }

  func setEventHandler(_ handler: EventHandler?) {
    synchronized { eventHandler = handler }
  }

  func setCapabilityChangeHandler(_ handler: ((Bool) -> Bool)?) {
    synchronized { capabilityChangeHandler = handler }
  }

  func setCapabilityEnabled(_ enabled: Bool) -> Bool {
    synchronized {
      if enabled {
        // Preserve the enable contract: durability must precede registration.
        guard capability.setEnabled(true) else { return false }
        return capabilityChangeHandler?(true) ?? true
      }

      // Disable live delivery first. The production handler unregisters
      // PushKit before invalidating its token, so even a false result has
      // already withdrawn desired push types. Persistence and current-call
      // termination are then attempted independently.
      let deliveryDisabled = capabilityChangeHandler?(false) ?? true
      let persisted = capability.setEnabled(false)
      let currentTerminated = store.snapshot() == nil
        || terminateCurrent(type: .nativeFailure, reason: .failed)
      return deliveryDisabled && persisted && currentTerminated
    }
  }

  func isCapabilityEnabled() -> Bool { synchronized { capability.enabled } }

  func presentIncoming(
    _ payload: VoipWakePayload,
    completion: @escaping (MknoonCallPresentationResult) -> Void
  ) {
    presentIncoming(payload, reportPolicy: .notRequired, completion: completion)
  }

  func presentIncoming(
    _ payload: VoipWakePayload,
    reportRequired: Bool,
    completion: @escaping (MknoonCallPresentationResult) -> Void
  ) {
    presentIncoming(
      payload,
      reportPolicy: reportRequired ? .metadataRequired : .notRequired,
      completion: completion
    )
  }

  func presentIncoming(
    _ payload: VoipWakePayload,
    reportPolicy: MknoonVoipPushReportPolicy,
    completion: @escaping (MknoonCallPresentationResult) -> Void
  ) {
    let decision: PendingNativeCallCreateResult = synchronized {
      guard capability.enabled else { return .persistenceFailure }
      expirePendingIfNecessary()
      return store.create(payload)
    }
    guard capability.enabled else {
      completeRejectedIncoming(
        .disabled,
        payload: payload,
        reportPolicy: reportPolicy,
        completion: completion
      )
      return
    }
    switch decision {
    case .persistenceFailure:
      completeRejectedIncoming(
        .persistenceFailure,
        payload: payload,
        reportPolicy: reportPolicy,
        completion: completion
      )
    case let .busy(descriptor):
      if reportPolicy == .legacyRequired,
         descriptor.direction == .outgoing,
         descriptor.terminalEvent == nil,
         descriptor.presented,
         descriptor.nativeCallId == payload.nativeCallId,
         descriptor.callHandle == payload.callHandle {
        completeRegisteredOutgoingReturnWake(
          .busy,
          descriptor: descriptor,
          completion: completion
        )
      } else {
        completeRejectedIncoming(
          .busy,
          payload: payload,
          reportPolicy: reportPolicy,
          completion: completion
        )
      }
    case let .duplicate(descriptor):
      guard let descriptor, descriptor.terminalEvent == nil, !descriptor.presented else {
        completeRejectedIncoming(
          .duplicate,
          payload: payload,
          reportPolicy: reportPolicy,
          completion: completion
        )
        return
      }
      reportIncoming(payload, acceptsAlreadyReportedCall: true, completion: completion)
    case .created:
      reportIncoming(payload, acceptsAlreadyReportedCall: false, completion: completion)
    }
  }

  /// Satisfies PushKit's report contract for a payload that was too malformed
  /// to create application call state. The random UUID and generic update are
  /// deliberately not persisted, surfaced to Flutter, or used to start media.
  func satisfyRequiredVoipPushReport(completion: @escaping () -> Void) {
    satisfyRequiredVoipPushReport(reportPolicy: .metadataRequired, completion: completion)
  }

  func satisfyRequiredVoipPushReport(
    reportPolicy: MknoonVoipPushReportPolicy,
    completion: @escaping () -> Void
  ) {
    guard reportPolicy != .notRequired else {
      completion()
      return
    }
    let context: (UUID, CXCallUpdate, Bool) = synchronized {
      let active = store.snapshot().flatMap { descriptor in
        descriptor.terminalEvent == nil ? descriptor : nil
      }
      if reportPolicy == .legacyRequired, let descriptor = active {
        return (descriptor.nativeCallId, incomingUpdate(for: descriptor), true)
      }
      let callId = ephemeralCallId(excluding: active?.nativeCallId)
      return (callId, complianceUpdate(for: callId), false)
    }
    satisfyRequiredVoipPushReport(
      callId: context.0,
      update: context.1,
      failMatchingActiveDescriptor: context.2,
      completion: completion
    )
  }

  func presentAuthenticated(
    callHandle: String,
    expiresAtMs: Int64,
    completion: @escaping (Bool) -> Void
  ) {
    guard let callId = UUID(uuidString: callHandle),
          callId.uuidString.lowercased() == callHandle,
          OpaqueCallContactResolver.validHandle(callHandle)
    else {
      mknoonCallKitDiag("[MKNOON_CALLKIT_DIAG] result=invalid_handle")
      completion(false)
      return
    }
    let now = nowMs()
    guard now >= 0 else {
      mknoonCallKitDiag("[MKNOON_CALLKIT_DIAG] result=invalid_clock")
      completion(false)
      return
    }
    let (localExpiryLimit, localExpiryOverflow) = now.addingReportingOverflow(
      VoipPayloadParser.maxFutureSkewMs
    )
    let (authenticatedExpiryLimit, authenticatedExpiryOverflow) =
      localExpiryLimit.addingReportingOverflow(Self.authenticatedPeerClockSkewMs)
    guard !localExpiryOverflow, !authenticatedExpiryOverflow,
          expiresAtMs > now, expiresAtMs <= authenticatedExpiryLimit
    else {
      mknoonCallKitDiag("[MKNOON_CALLKIT_DIAG] result=invalid_expiry")
      completion(false)
      return
    }
    let effectiveExpiresAtMs = min(expiresAtMs, localExpiryLimit)
    if let descriptor = snapshot(), descriptor.callHandle == callHandle,
       descriptor.expiresAtMs == effectiveExpiresAtMs,
       descriptor.terminalEvent == nil, descriptor.presented {
      mknoonCallKitDiag("[MKNOON_CALLKIT_DIAG] result=existing_presented")
      completion(true)
      return
    }
    let payload = VoipWakePayload(
      nativeCallId: callId,
      callHandle: callHandle,
      wakeHandle: callHandle,
      receivedAtMs: now,
      expiresAtMs: effectiveExpiresAtMs
    )
    presentIncoming(payload) { [weak self] result in
      guard let self else { completion(false); return }
      let acceptedDuplicate = result == .duplicate
        && self.snapshot().map {
          $0.callHandle == callHandle
            && $0.terminalEvent == nil
            && $0.presented
        } == true
      let accepted = result == .presented || acceptedDuplicate
      mknoonCallKitDiag(
        "[MKNOON_CALLKIT_DIAG] result=" + (accepted ? "presented" : "rejected")
          + " presentation=" + String(describing: result)
      )
      completion(accepted)
    }
  }

  func registerOutgoingAuthenticated(
    callHandle: String,
    expiresAtMs: Int64,
    completion: @escaping (Bool) -> Void
  ) {
    let decision: MknoonOutgoingRegistrationDecision = synchronized {
      guard capability.enabled,
            let callId = UUID(uuidString: callHandle),
            callId.uuidString.lowercased() == callHandle
      else { return .rejected }
      let now = nowMs()
      guard now >= 0, expiresAtMs > now,
            expiresAtMs - now <= VoipPayloadParser.maxFutureSkewMs
      else { return .rejected }
      let payload = VoipWakePayload(
        nativeCallId: callId,
        callHandle: callHandle,
        wakeHandle: callHandle,
        receivedAtMs: now,
        expiresAtMs: expiresAtMs
      )
      switch store.createOutgoing(payload) {
      case .duplicate:
        return .duplicate
      case .busy, .persistenceFailure:
        return .rejected
      case .created:
        return .created(callId, payload)
      }
    }
    switch decision {
    case .duplicate:
      completion(true)
      return
    case .rejected:
      completion(false)
      return
    case let .created(callId, payload):
      let action = CXStartCallAction(
        call: callId,
        handle: CXHandle(type: .generic, value: callHandle)
      )
      action.isVideo = false
      transactionRequester.request(CXTransaction(action: action)) { [weak self] error in
        guard let self else { completion(false); return }
        if error == nil {
          self.provider.reportOutgoingCall(with: callId, startedConnectingAt: Date())
          let succeeded = self.record(callId, .presented)
          if succeeded { self.scheduleExpiry(payload) }
          completion(succeeded)
        } else {
          _ = self.record(callId, .nativeFailure)
          completion(false)
        }
      }
    }
  }

  func attach() -> PendingNativeCallDescriptor? {
    synchronized {
      expirePendingIfNecessary()
      _ = store.sweepExpiredTerminalRetention()
      return store.snapshot()
    }
  }

  @discardableResult
  func detach() -> Bool {
    synchronized {
      eventHandler = nil
      return true
    }
  }

  func snapshot() -> PendingNativeCallDescriptor? { synchronized { store.snapshot() } }

  func resolveCallHandle(_ callHandle: String) -> UUID? {
    synchronized { store.resolveCallHandle(callHandle) }
  }

  func channelDescriptor(for event: PendingNativeCallEvent) -> PendingNativeCallDescriptor? {
    synchronized {
      guard let descriptor = store.snapshot(), descriptor.nativeCallId == event.nativeCallId else {
        return nil
      }
      return descriptor
    }
  }

  func acknowledge(
    _ nativeCallId: UUID,
    through sequence: Int64,
    disposition: PendingNativeCallAcknowledgement
  ) -> Bool {
    synchronized {
      let acknowledged = store.acknowledge(
        nativeCallId: nativeCallId,
        highestConsumedSequence: sequence,
        acknowledgement: disposition
      )
      mknoonCallKitDiag(
        "[MKNOON_CALLKIT_DIAG] ack=" + String(describing: disposition) + " through=" + String(sequence)
          + " ok=" + String(acknowledged)
      )
      if acknowledged && disposition == .terminal {
        clearNativeReferences(nativeCallId)
      }
      return acknowledged
    }
  }

  func adopt(_ nativeCallId: UUID) -> Bool {
    synchronized {
      guard let descriptor = store.snapshot(), descriptor.nativeCallId == nativeCallId,
            descriptor.terminalEvent == nil
      else {
        mknoonCallKitDiag("[MKNOON_CALLKIT_DIAG] adopt=refused")
        return false
      }
      mknoonCallKitDiag("[MKNOON_CALLKIT_DIAG] adopt=ok phase=" + String(describing: descriptor.phase))
      return true
    }
  }

  func activateAudio(_ nativeCallId: UUID) -> Bool {
    synchronized {
      guard let descriptor = store.snapshot(), descriptor.nativeCallId == nativeCallId else {
        mknoonCallKitDiag("[MKNOON_CALLKIT_DIAG] activate_audio=refused reason=no_matching_descriptor")
        return false
      }
      guard descriptor.terminalEvent == nil else {
        mknoonCallKitDiag("[MKNOON_CALLKIT_DIAG] activate_audio=refused reason=terminal")
        return false
      }
      guard canLatchCallKitAudio(for: descriptor) else {
        mknoonCallKitDiag("[MKNOON_CALLKIT_DIAG] activate_audio=refused reason=not_answered")
        return false
      }
      guard descriptor.handoffAcknowledgement == .adopted else {
        mknoonCallKitDiag(
          "[MKNOON_CALLKIT_DIAG] activate_audio=refused reason=not_adopted handoff="
            + String(describing: descriptor.handoffAcknowledgement)
            + " phase=" + String(describing: descriptor.phase)
        )
        return false
      }
      guard audioActivatedCallIds.contains(nativeCallId) else {
        mknoonCallKitDiag("[MKNOON_CALLKIT_DIAG] activate_audio=refused reason=session_not_activated")
        return false
      }
      mediaClaimedCallIds.insert(nativeCallId)
      mknoonCallKitDiag("[MKNOON_CALLKIT_DIAG] activate_audio=claimed")
      return true
    }
  }

  func deactivateAudio(_ nativeCallId: UUID) -> Bool {
    synchronized {
      guard store.snapshot()?.nativeCallId == nativeCallId else { return false }
      mediaClaimedCallIds.remove(nativeCallId)
      return true
    }
  }

  func endFromDart(_ nativeCallId: UUID) -> Bool {
    synchronized { terminate(nativeCallId, type: .endRequested, reason: .remoteEnded) }
  }

  func remoteCancel(callHandle: String) -> Bool {
    synchronized {
      guard let callId = store.resolveCallHandle(callHandle) else { return false }
      return terminate(callId, type: .remoteCancelled, reason: .remoteEnded)
    }
  }

  func authenticationFailed(callHandle: String) -> Bool {
    synchronized {
      guard let descriptor = store.snapshot(), descriptor.callHandle == callHandle else {
        return false
      }
      let revoked = revokeContactMapping(for: descriptor)
      let terminated = terminate(descriptor.nativeCallId, type: .nativeFailure, reason: .failed)
      return revoked && terminated
    }
  }

  func expire(callHandle: String) -> Bool {
    synchronized {
      guard let descriptor = store.snapshot(), descriptor.callHandle == callHandle else {
        return false
      }
      return terminate(descriptor.nativeCallId, type: .expired, reason: .unanswered)
    }
  }

  func updateAuthenticatedContact(
    callHandle: String,
    verifiedDisplayName: String
  ) -> Bool {
    synchronized {
      guard let descriptor = store.snapshot(), descriptor.callHandle == callHandle,
            descriptor.terminalEvent == nil,
            let opaqueHandle = contactHandle(for: descriptor),
            contacts.updateVerified(handle: opaqueHandle, displayName: verifiedDisplayName)
      else { return false }
      let update = callUpdate(
        displayName: contacts.displayName(for: opaqueHandle),
        callHandle: descriptor.callHandle
      )
      provider.reportCall(with: descriptor.nativeCallId, updated: update)
      return true
    }
  }

  /// Stores a recipient-authenticated call-only contact mapping before any
  /// PushKit descriptor exists. Signaling identifiers are intentionally not
  /// accepted at this boundary.
  func publishOpaqueContact(wakeHandle: String, displayName: String) -> Bool {
    synchronized {
      guard OpaqueCallContactResolver.validHandle(wakeHandle),
            OpaqueCallContactResolver.validDisplayName(displayName)
      else { return false }
      return contacts.updateVerified(handle: wakeHandle, displayName: displayName)
    }
  }

  func revokeOpaqueContactHandle(_ wakeHandle: String) -> Bool {
    synchronized {
      guard OpaqueCallContactResolver.validHandle(wakeHandle) else { return false }
      return contacts.revoke(handle: wakeHandle)
    }
  }

  func revokeOpaqueContact(callHandle: String) -> Bool {
    synchronized {
      guard let descriptor = store.snapshot(), descriptor.callHandle == callHandle else {
        return false
      }
      return revokeContactMapping(for: descriptor)
    }
  }

  func project(_ nativeCallId: UUID, state: String) -> Bool {
    synchronized {
      guard let descriptor = store.snapshot(), descriptor.nativeCallId == nativeCallId else {
        return false
      }
      switch state {
      case "ringing", "connecting":
        return descriptor.terminalEvent == nil
      case "active", "connected":
        guard descriptor.terminalEvent == nil else { return false }
        guard store.markConnected(nativeCallId: nativeCallId) else {
          failClosedAfterPersistenceFailure(nativeCallId)
          return false
        }
        expiryWorkItem?.cancel()
        if descriptor.direction == .outgoing {
          provider.reportOutgoingCall(with: nativeCallId, connectedAt: Date())
        }
        return true
      case "ended":
        return terminate(nativeCallId, type: .endRequested, reason: .remoteEnded)
      case "declined":
        return terminate(nativeCallId, type: .declineRequested, reason: .declinedElsewhere)
      case "failed":
        return terminate(nativeCallId, type: .nativeFailure, reason: .failed)
      default:
        return false
      }
    }
  }

  func audioState(_ nativeCallId: UUID) -> MknoonCallAudioState? {
    synchronized {
      guard store.snapshot()?.nativeCallId == nativeCallId else { return nil }
      let route = audio.routeState()
      return MknoonCallAudioState(
        active: audioActivatedCallIds.contains(nativeCallId),
        muted: mutedCallIds.contains(nativeCallId),
        route: route.route,
        availableRoutes: route.available
      )
    }
  }

  func requestRoute(_ nativeCallId: UUID, route: String) -> Bool {
    synchronized {
      guard store.snapshot()?.nativeCallId == nativeCallId,
            audioActivatedCallIds.contains(nativeCallId),
            audio.routeState().available.contains(route),
            audio.requestRoute(route)
      else { return false }
      guard record(nativeCallId, .routeChanged) else {
        failClosedAfterPersistenceFailure(nativeCallId)
        return false
      }
      return true
    }
  }

  func failClosed() -> Bool {
    synchronized {
      defer { eventHandler = nil }
      guard store.snapshot() != nil else { return true }
      return terminateCurrent(type: .nativeFailure, reason: .failed)
    }
  }

  // MARK: CXProviderDelegate

  func providerDidReset(_ provider: CXProvider) {
    handleProviderReset()
  }

  @discardableResult
  func handleProviderReset() -> Bool {
    synchronized {
      guard let descriptor = store.snapshot(), descriptor.terminalEvent == nil else { return false }
      guard record(descriptor.nativeCallId, .providerRemoved) else {
        failClosedAfterPersistenceFailure(descriptor.nativeCallId)
        return false
      }
      clearRuntimeAudio(descriptor.nativeCallId)
      endedCallIds.insert(descriptor.nativeCallId)
      expiryWorkItem?.cancel()
      return true
    }
  }

  func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
    if handleAnswer(action.callUUID) { action.fulfill() } else { action.fail() }
  }

  func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
    if handleSystemEnd(action.callUUID) { action.fulfill() } else { action.fail() }
  }

  func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
    if handleMute(action.callUUID, muted: action.isMuted) {
      action.fulfill()
    } else {
      action.fail()
    }
  }

  func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
    synchronized { configureCallAudioSession(stage: "start") }
    action.fulfill()
  }

  /// Configures the call audio session before an answer or start action is
  /// fulfilled, as Apple's CallKit sample does. CallKit activates the session
  /// the app configured; on a first call nothing was configured yet, and the
  /// activation (and `didActivate`) never came, so media could not start.
  /// This only sets the category; activation stays with CallKit.
  private func configureCallAudioSession(stage: String) {
    do {
      try audio.prepareForCallKitActivation()
      mknoonCallKitDiag("[MKNOON_CALLKIT_DIAG] audio_session=configured stage=" + stage)
    } catch {
      mknoonCallKitDiag("[MKNOON_CALLKIT_DIAG] audio_session=configure_failed stage=" + stage)
    }
  }

  func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
    synchronized {
      guard let descriptor = store.snapshot(), descriptor.terminalEvent == nil,
            canLatchCallKitAudio(for: descriptor)
      else {
        mknoonCallKitDiag("[MKNOON_CALLKIT_DIAG] audio_session=activated_unlatched")
        return
      }
      do {
        try audio.prepareForCallKitActivation()
        audioActivatedCallIds.insert(descriptor.nativeCallId)
        mknoonCallKitDiag("[MKNOON_CALLKIT_DIAG] audio_session=latched")
        guard record(descriptor.nativeCallId, .audioActivated) else {
          failClosedAfterPersistenceFailure(descriptor.nativeCallId)
          return
        }
      } catch {
        _ = terminate(descriptor.nativeCallId, type: .nativeFailure, reason: .failed)
      }
    }
  }

  func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
    synchronized {
      guard let descriptor = store.snapshot(), descriptor.terminalEvent == nil else { return }
      audio.releaseAfterCallKitDeactivation()
      if audioActivatedCallIds.remove(descriptor.nativeCallId) != nil {
        mediaClaimedCallIds.remove(descriptor.nativeCallId)
        guard record(descriptor.nativeCallId, .audioDeactivated) else {
          failClosedAfterPersistenceFailure(descriptor.nativeCallId)
          return
        }
      }
    }
  }

  func provider(_ provider: CXProvider, timedOutPerforming action: CXAction) {
    action.fail()
    guard let callAction = action as? CXCallAction else { return }
    synchronized {
      _ = terminate(callAction.callUUID, type: .nativeFailure, reason: .failed)
    }
  }

  // MARK: Host-testable action seams

  @discardableResult
  func handleAnswer(_ nativeCallId: UUID) -> Bool {
    synchronized {
      guard record(nativeCallId, .answerRequested) else {
        mknoonCallKitDiag("[MKNOON_CALLKIT_DIAG] answer=persist_failed")
        return false
      }
      answeredCallIds.insert(nativeCallId)
      scheduleAnswerAdoptionBound(nativeCallId)
      mknoonCallKitDiag("[MKNOON_CALLKIT_DIAG] answer=recorded")
      configureCallAudioSession(stage: "answer")
      return true
    }
  }

  /// Ends the call when its answer is still unconsumed by the runtime after
  /// `answerAdoptionBoundMs`. A consumed answer leaves the journal through
  /// acknowledgement, so its presence is the phantom signal. Returns true only
  /// when this check ended the call.
  @discardableResult
  func enforceAnswerAdoptionBound(_ nativeCallId: UUID) -> Bool {
    synchronized {
      guard let descriptor = store.snapshot(),
            descriptor.nativeCallId == nativeCallId,
            descriptor.terminalEvent == nil,
            let answer = descriptor.events.last(where: { $0.type == .answerRequested }),
            nowMs() - answer.occurredAtMs >= Self.answerAdoptionBoundMs
      else { return false }
      mknoonCallKitDiag("[MKNOON_CALLKIT_DIAG] answer_adoption_bound=exceeded")
      return terminate(nativeCallId, type: .nativeFailure, reason: .failed)
    }
  }

  private func scheduleAnswerAdoptionBound(_ nativeCallId: UUID) {
    answerAdoptionWorkItem?.cancel()
    let item = DispatchWorkItem { [weak self] in
      self?.enforceAnswerAdoptionBound(nativeCallId)
    }
    answerAdoptionWorkItem = item
    DispatchQueue.global(qos: .userInitiated).asyncAfter(
      deadline: .now() + .milliseconds(Int(Self.answerAdoptionBoundMs)),
      execute: item
    )
  }

  /// In-app Answer routed through CallKit. Only a presented, non-terminal
  /// incoming call can be answered; the transaction's own delegate callback
  /// records `answerRequested` and fulfils the action.
  func answerFromDart(_ nativeCallId: UUID, completion: @escaping (Bool) -> Void) {
    let eligible: Bool = synchronized {
      guard let descriptor = store.snapshot(),
            descriptor.nativeCallId == nativeCallId,
            descriptor.terminalEvent == nil,
            descriptor.direction == .incoming
      else { return false }
      return true
    }
    guard eligible else { completion(false); return }
    let action = CXAnswerCallAction(call: nativeCallId)
    transactionRequester.request(CXTransaction(action: action)) { error in
      completion(error == nil)
    }
  }

  @discardableResult
  func handleSystemEnd(_ nativeCallId: UUID) -> Bool {
    synchronized {
      // An outgoing call never has an answer request; ending it from the
      // system UI is a hang-up, not a decline.
      let descriptor = store.snapshot()
      let type: PendingNativeCallEventType = answeredCallIds.contains(nativeCallId)
        || descriptor?.answerRequested == true
        || descriptor?.direction == .outgoing
        ? .endRequested
        : .declineRequested
      guard record(nativeCallId, type) else { return false }
      endedCallIds.insert(nativeCallId)
      clearRuntimeAudio(nativeCallId)
      expiryWorkItem?.cancel()
      return true
    }
  }

  @discardableResult
  func handleMute(_ nativeCallId: UUID, muted: Bool) -> Bool {
    synchronized {
      guard recordMute(nativeCallId, muted: muted) else { return false }
      if muted { mutedCallIds.insert(nativeCallId) } else { mutedCallIds.remove(nativeCallId) }
      return true
    }
  }

  @discardableResult
  func recordAudioActivatedForTests(_ nativeCallId: UUID) -> Bool {
    synchronized {
      guard let descriptor = store.snapshot(), descriptor.nativeCallId == nativeCallId,
            canLatchCallKitAudio(for: descriptor) else { return false }
      do { try audio.prepareForCallKitActivation() } catch { return false }
      audioActivatedCallIds.insert(nativeCallId)
      guard record(nativeCallId, .audioActivated) else {
        failClosedAfterPersistenceFailure(nativeCallId)
        return false
      }
      return true
    }
  }

  private func canLatchCallKitAudio(for descriptor: PendingNativeCallDescriptor) -> Bool {
    descriptor.direction == .outgoing
      || descriptor.answerRequested
      || answeredCallIds.contains(descriptor.nativeCallId)
  }

  @discardableResult
  func recordAudioDeactivatedForTests(_ nativeCallId: UUID) -> Bool {
    synchronized {
      guard audioActivatedCallIds.remove(nativeCallId) != nil else { return false }
      audio.releaseAfterCallKitDeactivation()
      guard record(nativeCallId, .audioDeactivated) else {
        failClosedAfterPersistenceFailure(nativeCallId)
        return false
      }
      return true
    }
  }

  @objc private func audioRouteChanged(_ notification: Notification) {
    synchronized {
      guard let descriptor = store.snapshot(), descriptor.terminalEvent == nil,
            audioActivatedCallIds.contains(descriptor.nativeCallId)
      else { return }
      guard record(descriptor.nativeCallId, .routeChanged) else {
        failClosedAfterPersistenceFailure(descriptor.nativeCallId)
        return
      }
    }
  }

  @objc private func audioInterrupted(_ notification: Notification) {
    synchronized {
      guard let descriptor = store.snapshot(), descriptor.terminalEvent == nil,
            let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
            let type = AVAudioSession.InterruptionType(rawValue: raw)
      else { return }
      switch type {
      case .began:
        if audioActivatedCallIds.remove(descriptor.nativeCallId) != nil {
          mediaClaimedCallIds.remove(descriptor.nativeCallId)
          guard record(descriptor.nativeCallId, .audioDeactivated) else {
            failClosedAfterPersistenceFailure(descriptor.nativeCallId)
            return
          }
        }
      case .ended:
        guard record(descriptor.nativeCallId, .routeChanged) else {
          failClosedAfterPersistenceFailure(descriptor.nativeCallId)
          return
        }
      @unknown default:
        guard record(descriptor.nativeCallId, .routeChanged) else {
          failClosedAfterPersistenceFailure(descriptor.nativeCallId)
          return
        }
      }
    }
  }

  @objc private func mediaServicesReset(_ notification: Notification) {
    synchronized {
      guard let descriptor = store.snapshot(), descriptor.terminalEvent == nil else { return }
      audioActivatedCallIds.remove(descriptor.nativeCallId)
      mediaClaimedCallIds.remove(descriptor.nativeCallId)
      guard record(descriptor.nativeCallId, .audioDeactivated),
            record(descriptor.nativeCallId, .routeChanged)
      else {
        failClosedAfterPersistenceFailure(descriptor.nativeCallId)
        return
      }
    }
  }

  private func reportIncoming(
    _ payload: VoipWakePayload,
    acceptsAlreadyReportedCall: Bool,
    completion: @escaping (MknoonCallPresentationResult) -> Void
  ) {
    let shouldReport = synchronized {
      if incomingReportWaiters[payload.nativeCallId] != nil {
        incomingReportWaiters[payload.nativeCallId]?.append(
          IncomingReportWaiter(coalesced: true, completion: completion)
        )
        return false
      }
      incomingReportWaiters[payload.nativeCallId] = [
        IncomingReportWaiter(coalesced: false, completion: completion),
      ]
      return true
    }
    let update = incomingUpdate(for: payload)
    guard shouldReport else {
      // PushKit requires a CallKit report inside every delegate invocation,
      // even when the same call is already being reported (the relay signal
      // and the VoIP push race). Report the same UUID again: CallKit answers
      // "already exists" while the first report is live, and the first
      // report's completion settles every waiter. Should this duplicate
      // outlive a failed first report, it must not leave a ghost call ringing.
      provider.reportNewIncomingCall(with: payload.nativeCallId, update: update) {
        [weak self] error in
        guard let self, error == nil else { return }
        self.synchronized {
          let live = self.store.snapshot()
          if live == nil || live?.nativeCallId != payload.nativeCallId
            || live?.terminalEvent != nil {
            self.endCallKitOnce(payload.nativeCallId, reason: .failed)
          }
        }
      }
      return
    }

    provider.reportNewIncomingCall(with: payload.nativeCallId, update: update) {
      [weak self] error in
      guard let self else {
        completion(.callKitFailure)
        return
      }
      let outcome: (MknoonCallPresentationResult, [IncomingReportWaiter]) = self.synchronized {
        let adoptedExistingCall = acceptsAlreadyReportedCall
          && error.map(Self.isAlreadyReportedCallError) == true
        let result: MknoonCallPresentationResult
        if let error, !adoptedExistingCall {
          _ = error
          _ = self.terminate(payload.nativeCallId, type: .nativeFailure, reason: .failed)
          result = .callKitFailure
        } else if !self.record(payload.nativeCallId, .presented) {
          self.failClosedAfterPersistenceFailure(payload.nativeCallId)
          result = .persistenceFailure
        } else {
          self.scheduleExpiry(payload)
          result = adoptedExistingCall ? .duplicate : .presented
        }
        let waiters = self.incomingReportWaiters.removeValue(
          forKey: payload.nativeCallId
        ) ?? [IncomingReportWaiter(coalesced: false, completion: completion)]
        return (result, waiters)
      }
      for waiter in outcome.1 {
        let result = outcome.0 == .presented && waiter.coalesced
          ? MknoonCallPresentationResult.duplicate
          : outcome.0
        waiter.completion(result)
      }
    }
  }

  private func completeRejectedIncoming(
    _ result: MknoonCallPresentationResult,
    payload: VoipWakePayload,
    reportPolicy: MknoonVoipPushReportPolicy,
    completion: @escaping (MknoonCallPresentationResult) -> Void
  ) {
    guard reportPolicy != .notRequired else {
      completion(result)
      return
    }

    let reportContext: (UUID, CXCallUpdate, Bool) = synchronized {
      let active = store.snapshot().flatMap { descriptor in
        descriptor.terminalEvent == nil ? descriptor : nil
      }
      if reportPolicy == .legacyRequired, let descriptor = active {
        return (descriptor.nativeCallId, incomingUpdate(for: descriptor), true)
      }
      let callId = ephemeralCallId(excluding: active?.nativeCallId)
      return (callId, incomingUpdate(for: payload), false)
    }
    satisfyRequiredVoipPushReport(
      callId: reportContext.0,
      update: reportContext.1,
      failMatchingActiveDescriptor: reportContext.2
    ) {
      completion(result)
    }
  }

  private func completeRegisteredOutgoingReturnWake(
    _ result: MknoonCallPresentationResult,
    descriptor: PendingNativeCallDescriptor,
    completion: @escaping (MknoonCallPresentationResult) -> Void
  ) {
    provider.reportNewIncomingCall(
      with: descriptor.nativeCallId,
      update: incomingUpdate(for: descriptor)
    ) { _ in
      // The legacy PushKit contract requires a CallKit report attempt. When
      // this wake is return signaling for the already-presented outgoing
      // call, both success and already-exists mean the same CallKit call
      // remains authoritative; neither outcome may terminalize it.
      completion(result)
    }
  }

  private func satisfyRequiredVoipPushReport(
    callId: UUID,
    update: CXCallUpdate,
    failMatchingActiveDescriptor: Bool,
    completion: @escaping () -> Void
  ) {
    provider.reportNewIncomingCall(with: callId, update: update) { [weak self] error in
      guard let self else {
        completion()
        return
      }
      if error == nil {
        self.synchronized {
          let descriptor = self.store.snapshot()
          if failMatchingActiveDescriptor,
             descriptor?.nativeCallId == callId,
             descriptor?.terminalEvent == nil {
            _ = self.terminate(callId, type: .nativeFailure, reason: .failed)
          } else {
            self.provider.reportCall(with: callId, endedAt: Date(), reason: .failed)
          }
        }
      }
      // Any CallKit result proves the required report was attempted. In
      // particular, already-exists and other errors must not disturb the
      // active persisted call.
      completion()
    }
  }

  private static func isAlreadyReportedCallError(_ error: Error) -> Bool {
    let value = error as NSError
    return value.domain == CXErrorDomainIncomingCall
      && value.code == CXErrorCodeIncomingCallError.Code.callUUIDAlreadyExists.rawValue
  }

  private func contactHandle(for descriptor: PendingNativeCallDescriptor) -> String? {
    if let retained = descriptor.opaqueContactHandle,
       OpaqueCallContactResolver.validHandle(retained) {
      return retained
    }
    guard OpaqueCallContactResolver.validHandle(descriptor.wakeHandle) else { return nil }
    return descriptor.wakeHandle
  }

  private func revokeContactMapping(for descriptor: PendingNativeCallDescriptor) -> Bool {
    guard let opaqueHandle = contactHandle(for: descriptor) else { return false }
    return contacts.revoke(handle: opaqueHandle)
  }

  private func incomingUpdate(for payload: VoipWakePayload) -> CXCallUpdate {
    callUpdate(
      displayName: contacts.displayName(for: payload.wakeHandle),
      callHandle: payload.callHandle
    )
  }

  private func incomingUpdate(for descriptor: PendingNativeCallDescriptor) -> CXCallUpdate {
    let opaqueHandle = contactHandle(for: descriptor)
    return callUpdate(
      displayName: opaqueHandle.map { contacts.displayName(for: $0) } ?? "",
      callHandle: descriptor.callHandle
    )
  }

  private func complianceUpdate(for callId: UUID) -> CXCallUpdate {
    callUpdate(displayName: "", callHandle: callId.uuidString.lowercased())
  }

  private func ephemeralCallId(excluding excluded: UUID?) -> UUID {
    var candidate = UUID()
    while candidate == excluded { candidate = UUID() }
    return candidate
  }

  private func callUpdate(displayName: String, callHandle: String) -> CXCallUpdate {
    let update = CXCallUpdate()
    update.remoteHandle = CXHandle(type: .generic, value: callHandle)
    update.localizedCallerName = displayName
    update.hasVideo = false
    update.supportsHolding = false
    update.supportsGrouping = false
    update.supportsUngrouping = false
    update.supportsDTMF = false
    return update
  }

  @discardableResult
  private func record(_ nativeCallId: UUID, _ type: PendingNativeCallEventType) -> Bool {
    switch store.append(nativeCallId: nativeCallId, type: type) {
    case let .appended(_, event):
      eventHandler?(event)
      return true
    case .ignoredAfterTerminal:
      return type.isTerminal
    case .notFound, .capacityReached, .persistenceFailure:
      return false
    }
  }

  private func recordMute(_ nativeCallId: UUID, muted: Bool) -> Bool {
    switch store.append(nativeCallId: nativeCallId, type: .muteChanged, muted: muted) {
    case let .appended(_, event):
      eventHandler?(event)
      return true
    case .ignoredAfterTerminal, .notFound, .capacityReached, .persistenceFailure:
      return false
    }
  }

  private func terminate(
    _ nativeCallId: UUID,
    type: PendingNativeCallEventType,
    reason: CXCallEndedReason
  ) -> Bool {
    guard type.isTerminal, let descriptor = store.snapshot(),
          descriptor.nativeCallId == nativeCallId
    else { return false }
    let newlyRecorded = descriptor.terminalEvent == nil
    if newlyRecorded, !record(nativeCallId, type) {
      failClosedAfterPersistenceFailure(nativeCallId)
      return false
    }
    endCallKitOnce(nativeCallId, reason: reason)
    clearRuntimeAudio(nativeCallId)
    expiryWorkItem?.cancel()
    answerAdoptionWorkItem?.cancel()
    if newlyRecorded {
      mknoonCallKitDiag("[MKNOON_CALLKIT_DIAG] terminal=" + type.wireName)
      if type == .remoteCancelled {
        mknoonCallKitDiag("[MKNOON_CALLKIT_DIAG] result=remote_cancelled")
      }
    }
    return true
  }

  private func terminateCurrent(
    type: PendingNativeCallEventType,
    reason: CXCallEndedReason
  ) -> Bool {
    guard let descriptor = store.snapshot() else { return false }
    return terminate(descriptor.nativeCallId, type: type, reason: reason)
  }

  private func endCallKitOnce(_ nativeCallId: UUID, reason: CXCallEndedReason) {
    guard endedCallIds.insert(nativeCallId).inserted else { return }
    provider.reportCall(with: nativeCallId, endedAt: Date(), reason: reason)
  }

  private func clearRuntimeAudio(_ nativeCallId: UUID) {
    answeredCallIds.remove(nativeCallId)
    mutedCallIds.remove(nativeCallId)
    audioActivatedCallIds.remove(nativeCallId)
    mediaClaimedCallIds.remove(nativeCallId)
    audio.releaseAfterCallKitDeactivation()
  }

  private func failClosedAfterPersistenceFailure(_ nativeCallId: UUID) {
    _ = capability.setEnabled(false)
    // Never call out under the controller lock: the handler hops to the main
    // queue synchronously, and the main queue may be waiting for this lock.
    if let handler = capabilityChangeHandler {
      DispatchQueue.global(qos: .userInitiated).async { _ = handler(false) }
    }
    endCallKitOnce(nativeCallId, reason: .failed)
    clearRuntimeAudio(nativeCallId)
    expiryWorkItem?.cancel()
  }

  private func restorePersistedRuntimeState() {
    guard let descriptor = store.snapshot(), descriptor.terminalEvent == nil else { return }
    if descriptor.answerRequested { answeredCallIds.insert(descriptor.nativeCallId) }
    if descriptor.muted == true { mutedCallIds.insert(descriptor.nativeCallId) }
  }

  private func clearNativeReferences(_ nativeCallId: UUID) {
    clearRuntimeAudio(nativeCallId)
    endedCallIds.remove(nativeCallId)
    expiryWorkItem?.cancel()
    answerAdoptionWorkItem?.cancel()
  }

  private func expirePendingIfNecessary() {
    guard let descriptor = store.snapshot(), descriptor.terminalEvent == nil,
          descriptor.connectedAtMs == nil,
          descriptor.expiresAtMs <= nowMs()
    else { return }
    _ = terminate(descriptor.nativeCallId, type: .expired, reason: .unanswered)
  }

  private func scheduleExpiry(_ payload: VoipWakePayload) {
    synchronized {
      expiryWorkItem?.cancel()
      let item = DispatchWorkItem { [weak self] in
        guard let self else { return }
        self.synchronized {
          guard let descriptor = self.store.snapshot(),
                descriptor.nativeCallId == payload.nativeCallId,
                descriptor.terminalEvent == nil,
                descriptor.connectedAtMs == nil,
                descriptor.expiresAtMs <= self.nowMs()
          else { return }
          _ = self.terminate(descriptor.nativeCallId, type: .expired, reason: .unanswered)
        }
      }
      expiryWorkItem = item
      let delayMs = max(0, payload.expiresAtMs - nowMs())
      DispatchQueue.global(qos: .userInitiated).asyncAfter(
        deadline: .now() + .milliseconds(Int(min(delayMs, Int64(Int.max)))),
        execute: item
      )
    }
  }

  private func synchronized<T>(_ action: () -> T) -> T {
    lock.lock()
    defer { lock.unlock() }
    return action()
  }
}
