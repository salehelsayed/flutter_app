import Flutter
import Foundation

/// Strict version-one Flutter boundary for the native iOS CallKit journal.
/// Its envelope intentionally matches the Android lifecycle adapter so Dart
/// can reuse one reconciliation algorithm without widening either parser.
internal final class MknoonCallNativeBridge: NSObject, FlutterStreamHandler {
  static let methodChannelName = "mknoon/ios_call_lifecycle"
  static let eventChannelName = "mknoon/ios_call_lifecycle/events"
  static let protocolVersion = 1

  private let controller: MknoonCallKitController
  private let methodChannel: FlutterMethodChannel?
  private let eventChannel: FlutterEventChannel?
  private let lock = NSRecursiveLock()
  private var eventSink: FlutterEventSink?
  private var sinkGeneration: Int64 = 0
  private var attaching = false
  private var bufferedEvents: [PendingNativeCallEvent] = []
  private var disposed = false

  init(controller: MknoonCallKitController, messenger: FlutterBinaryMessenger?) {
    self.controller = controller
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
    controller.setEventHandler { [weak self] event in self?.emit(event) }
  }

  deinit { dispose() }

  func dispose() {
    synchronized {
      guard !disposed else { return }
      disposed = true
      sinkGeneration += 1
      eventSink = nil
      bufferedEvents.removeAll()
      controller.setEventHandler(nil)
      methodChannel?.setMethodCallHandler(nil)
      eventChannel?.setStreamHandler(nil)
    }
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "setCapabilityEnabled":
      setCapability(call.arguments, result)
    case "attach":
      attach(call.arguments, result)
    case "adopt":
      withCallHandle(call.arguments, result, controller.adopt)
    case "presentAuthenticated":
      presentAuthenticated(call.arguments, result)
    case "registerOutgoingAuthenticated":
      registerOutgoingAuthenticated(call.arguments, result)
    case "acknowledge":
      acknowledge(call.arguments, result)
    case "end":
      withCallHandle(call.arguments, result, controller.endFromDart)
    case "authenticationFailed":
      withRawCallHandle(call.arguments, result, controller.authenticationFailed)
    case "remoteCancel":
      withRawCallHandle(call.arguments, result, controller.remoteCancel)
    case "expire":
      withRawCallHandle(call.arguments, result, controller.expire)
    case "updateAuthenticatedContact":
      updateAuthenticatedContact(call.arguments, result)
    case "revokeOpaqueContact":
      withRawCallHandle(call.arguments, result, controller.revokeOpaqueContact)
    case "publishOpaqueContact":
      publishOpaqueContact(call.arguments, result)
    case "revokeOpaqueContactHandle":
      revokeOpaqueContactHandle(call.arguments, result)
    case "project":
      project(call.arguments, result)
    case "readAudioState":
      readAudioState(call.arguments, result)
    case "startRingback":
      ringback(call.arguments, result, controller.startRingback)
    case "stopRingback":
      ringback(call.arguments, result, controller.stopRingback)
    case "requestRoute":
      requestRoute(call.arguments, result)
    case "answer":
      answer(call.arguments, result)
    case "activateAudio":
      withCallHandle(call.arguments, result, controller.activateAudio)
    case "deactivateAudio":
      withCallHandle(call.arguments, result, controller.deactivateAudio)
    case "failClosed":
      failClosed(call.arguments, result)
    case "detach":
      detach(call.arguments, result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  func onListen(
    withArguments arguments: Any?,
    eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? {
    guard arguments == nil else {
      return FlutterError(code: "bad_args", message: "invalid native call arguments", details: nil)
    }
    synchronized {
      guard !disposed else { return }
      sinkGeneration += 1
      eventSink = events
      controller.setEventHandler { [weak self] event in self?.emit(event) }
    }
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    synchronized {
      sinkGeneration += 1
      eventSink = nil
    }
    return nil
  }

  private func setCapability(_ arguments: Any?, _ result: @escaping FlutterResult) {
    guard let map = exactMap(arguments, keys: ["version", "enabled"]),
          validVersion(map["version"]),
          let enabled = map["enabled"] as? Bool
    else { badArguments(result); return }
    result(controller.setCapabilityEnabled(enabled))
  }

  private func attach(_ arguments: Any?, _ result: @escaping FlutterResult) {
    guard nullOrVersionOnly(arguments) else { badArguments(result); return }
    let descriptor: PendingNativeCallDescriptor? = synchronized {
      guard !disposed else { return nil }
      attaching = true
      bufferedEvents.removeAll()
      controller.setEventHandler { [weak self] event in self?.emit(event) }
      return controller.attach()
    }
    let high = descriptor?.highestSequence ?? 0
    result(envelope(descriptor))
    let buffered: [PendingNativeCallEvent] = synchronized {
      attaching = false
      let events = bufferedEvents.filter { $0.sequence > high }
      bufferedEvents.removeAll()
      return events
    }
    buffered.forEach(emit)
  }

  private func presentAuthenticated(_ arguments: Any?, _ result: @escaping FlutterResult) {
    guard let parsed = authenticatedArguments(arguments) else {
      badArguments(result)
      return
    }
    controller.presentAuthenticated(
      callHandle: parsed.callHandle,
      expiresAtMs: parsed.expiresAtMs,
      completion: result
    )
  }

  private func registerOutgoingAuthenticated(
    _ arguments: Any?,
    _ result: @escaping FlutterResult
  ) {
    guard let parsed = authenticatedArguments(arguments) else {
      badArguments(result)
      return
    }
    controller.registerOutgoingAuthenticated(
      callHandle: parsed.callHandle,
      expiresAtMs: parsed.expiresAtMs,
      completion: result
    )
  }

  private func acknowledge(_ arguments: Any?, _ result: @escaping FlutterResult) {
    guard let map = exactMap(
      arguments,
      keys: ["version", "callHandle", "throughSequence", "disposition"]
    ), validVersion(map["version"]),
      let callId = resolve(map["callHandle"]),
      let sequence = parseInt64(map["throughSequence"]),
      let rawDisposition = map["disposition"] as? String,
      let disposition = PendingNativeCallAcknowledgement(rawValue: rawDisposition)
    else { badArguments(result); return }
    result(controller.acknowledge(callId, through: sequence, disposition: disposition))
  }

  private func project(_ arguments: Any?, _ result: @escaping FlutterResult) {
    guard let map = exactMap(arguments, keys: ["version", "callHandle", "state"]),
          validVersion(map["version"]),
          let callId = resolve(map["callHandle"]),
          let state = map["state"] as? String
    else { badArguments(result); return }
    result(controller.project(callId, state: state))
  }

  private func readAudioState(_ arguments: Any?, _ result: @escaping FlutterResult) {
    guard let map = identityMap(arguments),
          let callId = resolve(map["callHandle"]),
          let state = controller.audioState(callId)
    else { badArguments(result); return }
    result([
      "version": Self.protocolVersion,
      "active": state.active,
      "muted": state.muted,
      "route": state.route,
      "availableRoutes": state.availableRoutes,
    ])
  }

  private func requestRoute(_ arguments: Any?, _ result: @escaping FlutterResult) {
    guard let map = exactMap(arguments, keys: ["version", "callHandle", "route"]),
          validVersion(map["version"]),
          let callId = resolve(map["callHandle"]),
          let route = map["route"] as? String
    else { badArguments(result); return }
    result(controller.requestRoute(callId, route: route))
  }

  private func updateAuthenticatedContact(
    _ arguments: Any?,
    _ result: @escaping FlutterResult
  ) {
    guard let map = exactMap(
      arguments,
      keys: ["version", "callHandle", "displayName"]
    ), validVersion(map["version"]),
      let callHandle = map["callHandle"] as? String,
      controller.resolveCallHandle(callHandle) != nil,
      let displayName = map["displayName"] as? String
    else { badArguments(result); return }
    result(controller.updateAuthenticatedContact(
      callHandle: callHandle,
      verifiedDisplayName: displayName
    ))
  }

  private func publishOpaqueContact(
    _ arguments: Any?,
    _ result: @escaping FlutterResult
  ) {
    guard let map = exactMap(
      arguments,
      keys: ["version", "wakeHandle", "displayName"]
    ), validVersion(map["version"]),
      let wakeHandle = map["wakeHandle"] as? String,
      OpaqueCallContactResolver.validHandle(wakeHandle),
      let displayName = map["displayName"] as? String,
      OpaqueCallContactResolver.validDisplayName(displayName)
    else { badArguments(result); return }
    result(controller.publishOpaqueContact(
      wakeHandle: wakeHandle,
      displayName: displayName
    ))
  }

  private func revokeOpaqueContactHandle(
    _ arguments: Any?,
    _ result: @escaping FlutterResult
  ) {
    guard let map = exactMap(arguments, keys: ["version", "wakeHandle"]),
          validVersion(map["version"]),
          let wakeHandle = map["wakeHandle"] as? String,
          OpaqueCallContactResolver.validHandle(wakeHandle)
    else { badArguments(result); return }
    result(controller.revokeOpaqueContactHandle(wakeHandle))
  }

  private func failClosed(_ arguments: Any?, _ result: @escaping FlutterResult) {
    guard let map = exactMap(arguments, keys: ["version"]),
          validVersion(map["version"])
    else { badArguments(result); return }
    result(controller.failClosed())
    synchronized {
      sinkGeneration += 1
      eventSink = nil
    }
  }

  private func detach(_ arguments: Any?, _ result: @escaping FlutterResult) {
    guard nullOrVersionOnly(arguments) else { badArguments(result); return }
    result(controller.detach())
    synchronized {
      sinkGeneration += 1
      eventSink = nil
    }
  }

  private func withCallHandle(
    _ arguments: Any?,
    _ result: @escaping FlutterResult,
    _ operation: (UUID) -> Bool
  ) {
    guard let map = identityMap(arguments), let callId = resolve(map["callHandle"])
    else { badArguments(result); return }
    result(operation(callId))
  }

  /// In-app Answer. CallKit must perform the answer itself so `didActivate`
  /// runs and the audio session can be latched; the resulting
  /// `answerRequested` event then drives the Dart accept.
  private func answer(_ arguments: Any?, _ result: @escaping FlutterResult) {
    guard let map = identityMap(arguments), let callId = resolve(map["callHandle"])
    else { badArguments(result); return }
    controller.answerFromDart(callId) { accepted in
      DispatchQueue.main.async { result(accepted) }
    }
  }

  private func withRawCallHandle(
    _ arguments: Any?,
    _ result: @escaping FlutterResult,
    _ operation: (String) -> Bool
  ) {
    guard let map = identityMap(arguments),
          let callHandle = map["callHandle"] as? String,
          controller.resolveCallHandle(callHandle) != nil
    else { badArguments(result); return }
    result(operation(callHandle))
  }

  private func emit(_ event: PendingNativeCallEvent) {
    let delivery: (FlutterEventSink, Int64, [String: Any])? = synchronized {
      if attaching {
        bufferedEvents.append(event)
        return nil
      }
      guard !disposed, let sink = eventSink,
            let descriptor = controller.channelDescriptor(for: event)
      else { return nil }
      return (sink, sinkGeneration, envelope(descriptor, selectedEvents: [event]))
    }
    guard let delivery else { return }
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      let current = self.synchronized {
        !self.disposed
          && self.sinkGeneration == delivery.1
          && self.eventSink != nil
      }
      if current { delivery.0(delivery.2) }
    }
  }

  private func envelope(
    _ descriptor: PendingNativeCallDescriptor?,
    selectedEvents: [PendingNativeCallEvent]? = nil
  ) -> [String: Any] {
    guard let descriptor else {
      return [
        "version": Self.protocolVersion,
        "descriptor": NSNull(),
        "events": [[String: Any]](),
        "nativeCallId": NSNull(),
        "highestSequence": Int64(0),
      ]
    }
    let events = selectedEvents ?? descriptor.events
    return [
      "version": Self.protocolVersion,
      "descriptor": [
        "callHandle": descriptor.callHandle,
        "expiresAtMs": descriptor.expiresAtMs,
        "direction": descriptor.direction.rawValue,
        "phase": descriptor.phase.rawValue,
        "presented": descriptor.handoffAcknowledgement == .adopted
          || descriptor.events.contains(where: { $0.type == .presented }),
      ],
      "events": events.map { event in
        [
          "callHandle": descriptor.callHandle,
          "sequence": event.sequence,
          "eventId": event.eventId.uuidString.lowercased(),
          "type": event.type.wireName,
          "occurredAtMs": event.occurredAtMs,
        ] as [String: Any]
      },
      "nativeCallId": descriptor.nativeCallId.uuidString.lowercased(),
      "highestSequence": selectedEvents?.map(\.sequence).max() ?? descriptor.highestSequence,
    ]
  }

  private func authenticatedArguments(_ arguments: Any?) -> (callHandle: String, expiresAtMs: Int64)? {
    guard let map = exactMap(
      arguments,
      keys: ["version", "callHandle", "expiresAtMs"]
    ), validVersion(map["version"]),
      let callHandle = map["callHandle"] as? String,
      let expiresAtMs = parseInt64(map["expiresAtMs"])
    else { return nil }
    return (callHandle, expiresAtMs)
  }

  private func ringback(
    _ arguments: Any?,
    _ result: @escaping FlutterResult,
    _ operation: (UUID) -> Bool
  ) {
    guard let map = identityMap(arguments), let callId = resolve(map["callHandle"]) else {
      badArguments(result)
      return
    }
    result(operation(callId))
  }

  private func identityMap(_ arguments: Any?) -> [String: Any]? {
    guard let map = exactMap(arguments, keys: ["version", "callHandle"]),
          validVersion(map["version"]),
          map["callHandle"] is String
    else { return nil }
    return map
  }

  private func resolve(_ value: Any?) -> UUID? {
    guard let handle = value as? String else { return nil }
    return controller.resolveCallHandle(handle)
  }

  private func exactMap(_ arguments: Any?, keys: Set<String>) -> [String: Any]? {
    guard let map = arguments as? [String: Any], Set(map.keys) == keys else { return nil }
    return map
  }

  private func validVersion(_ value: Any?) -> Bool {
    parseInt64(value) == Int64(Self.protocolVersion)
  }

  private func parseInt64(_ value: Any?) -> Int64? {
    guard let number = value as? NSNumber,
          CFGetTypeID(number) != CFBooleanGetTypeID()
    else { return nil }
    switch String(cString: number.objCType) {
    case "c", "s", "i", "l", "q":
      return number.int64Value
    case "C", "S", "I", "L", "Q":
      let unsigned = number.uint64Value
      return unsigned <= UInt64(Int64.max) ? Int64(unsigned) : nil
    default:
      return nil
    }
  }

  private func nullOrVersionOnly(_ arguments: Any?) -> Bool {
    if arguments == nil { return true }
    guard let map = exactMap(arguments, keys: ["version"]) else { return false }
    return validVersion(map["version"])
  }

  private func badArguments(_ result: FlutterResult) {
    result(FlutterError(
      code: "bad_args",
      message: "invalid native call arguments",
      details: nil
    ))
  }

  private func synchronized<T>(_ action: () -> T) -> T {
    lock.lock()
    defer { lock.unlock() }
    return action()
  }
}
