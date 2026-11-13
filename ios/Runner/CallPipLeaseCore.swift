import Foundation

/// Live-call PiP lease state (bridge contract v1, bl16-pip-bridge-contract.md).
/// Pure Swift mirror of the Android CallPipLeaseCore: identity, lease order, seq
/// and event rules only. Main thread only. Native never touches a camera and
/// never ends a call.
struct CallPipIdentity: Equatable {
  let instanceId: String
  let callId: String
  let leaseId: Int64

  static func parse(_ args: [String: Any]?) -> CallPipIdentity? {
    guard let args, (args["version"] as? NSNumber)?.intValue == 1,
      let instance = args["instanceId"] as? String, !instance.isEmpty,
      let call = args["callId"] as? String, !call.isEmpty,
      let lease = (args["leaseId"] as? NSNumber)?.int64Value, lease > 0
    else { return nil }
    return CallPipIdentity(instanceId: instance, callId: call, leaseId: lease)
  }
}

struct CallPipSource: Equatable {
  let peerConnectionId: String
  let remoteTrackId: String

  static func parse(_ args: [String: Any]) -> CallPipSource? {
    guard let pc = args["peerConnectionId"] as? String, !pc.isEmpty,
      let track = args["remoteTrackId"] as? String, !track.isEmpty,
      let negotiation = args["negotiationId"] as? String, !negotiation.isEmpty,
      let revision = (args["mediaRevision"] as? NSNumber)?.int64Value, revision >= 0,
      let epoch = (args["rendererEpoch"] as? NSNumber)?.int64Value, epoch >= 0
    else { return nil }
    return CallPipSource(peerConnectionId: pc, remoteTrackId: track)
  }
}

struct CallPipControls: Equatable {
  let muted: Bool
  let cameraOn: Bool
  let cameraEnabled: Bool

  static func parse(_ args: [String: Any]) -> CallPipControls? {
    guard let muted = args["muted"] as? Bool, let on = args["cameraOn"] as? Bool,
      let enabled = args["cameraEnabled"] as? Bool
    else { return nil }
    return CallPipControls(muted: muted, cameraOn: on, cameraEnabled: enabled)
  }
}

/// Platform effects. A sink is an opaque native renderer bound to one track.
protocol CallPipPlatform: AnyObject {
  func supported() -> Bool
  func hasVideoTrack(_ source: CallPipSource) -> Bool
  func attachSink(_ source: CallPipSource) -> AnyObject?
  func releaseSink(_ sink: AnyObject)
  func setAutoEnter(_ controls: CallPipControls?)
  func requestEnter() -> Bool
  func leavePip()
}

final class CallPipLeaseCore {
  private final class Lease {
    let id: CallPipIdentity
    let source: CallPipSource
    var seq: Int64 = 0
    var sink: AnyObject?
    var entered = false
    init(id: CallPipIdentity, source: CallPipSource) {
      self.id = id
      self.source = source
    }
  }

  private static let actions: Set<String> = ["mute", "camera", "end"]
  private static let blocked: Set<String> = ["locked", "userDisabled"]

  private unowned let platform: CallPipPlatform
  private let emit: ([String: Any]) -> Void
  private var lease: Lease?
  private var instance: String?
  private var highestLease: Int64 = 0
  private var retiredInstances = Set<String>()

  init(platform: CallPipPlatform, emit: @escaping ([String: Any]) -> Void) {
    self.platform = platform
    self.emit = emit
  }

  func availability() -> [String: Any] {
    let supported = platform.supported()
    // Unit 3 never enables same-session background capture.
    return ["supported": supported, "cameraInPip": false, "reason": supported ? "ok" : "os"]
  }

  func arm(_ id: CallPipIdentity, source: CallPipSource, controls: CallPipControls) -> [String: Any] {
    guard accepts(id) else { return ["armed": false, "reason": "stale"] }
    if id.instanceId != instance {
      if let old = instance { retiredInstances.insert(old) }
      instance = id.instanceId
    }
    highestLease = id.leaseId
    retire(reason: "disarmed")
    guard platform.supported() else { return ["armed": false, "reason": "unsupported"] }
    guard platform.hasVideoTrack(source) else { return ["armed": false, "reason": "trackNotFound"] }
    lease = Lease(id: id, source: source)
    platform.setAutoEnter(controls)
    return ["armed": true, "reason": "ok"]
  }

  func update(_ id: CallPipIdentity, controls: CallPipControls) -> Bool {
    guard lease?.id == id else { return false }
    platform.setAutoEnter(controls)
    return true
  }

  func enter(_ id: CallPipIdentity) -> Bool {
    guard let current = lease, current.id == id else { return false }
    return current.entered || platform.requestEnter()
  }

  /// Idempotent: a retired or unknown triple is already clean and never touches a successor.
  func disarm(_ id: CallPipIdentity) -> Bool {
    if lease?.id == id { retire(reason: "disarmed") }
    return true
  }

  func onUserLeaving() {
    guard let current = lease, current.sink == nil else { return }
    current.sink = platform.attachSink(current.source)
  }

  func onEntered() {
    guard let current = lease, !current.entered else { return }
    if current.sink == nil { current.sink = platform.attachSink(current.source) }
    guard current.sink != nil else {
      send(current, "failed", ["code": "trackLost"])
      drop(current)
      platform.leavePip()
      return
    }
    current.entered = true
    send(current, "entered")
  }

  func onExited(restored: Bool) {
    guard let current = lease, current.entered else { return }
    current.entered = false
    if let sink = current.sink { platform.releaseSink(sink) }
    current.sink = nil
    send(current, "exited", ["reason": restored ? "restored" : "closed"])
  }

  func onAction(_ kind: String) {
    guard let current = lease, current.entered, Self.actions.contains(kind) else { return }
    send(current, "action", ["kind": kind])
  }

  func onBlocked(_ reason: String) {
    guard let current = lease, Self.blocked.contains(reason) else { return }
    let wasEntered = current.entered
    drop(current)
    if wasEntered { platform.leavePip() }
    send(current, "blocked", ["reason": reason])
  }

  func onReturnedWithoutEntry() {
    guard let current = lease, !current.entered else { return }
    if let sink = current.sink { platform.releaseSink(sink) }
    current.sink = nil
  }

  private func accepts(_ id: CallPipIdentity) -> Bool {
    if retiredInstances.contains(id.instanceId) { return false }
    return id.instanceId != instance || id.leaseId > highestLease
  }

  private func retire(reason: String) {
    guard let current = lease else { return }
    let wasEntered = current.entered
    drop(current)
    if wasEntered {
      platform.leavePip()
      send(current, "exited", ["reason": reason])
    }
  }

  /// Retire first, then clean up: no callback can reach this lease afterwards.
  private func drop(_ current: Lease) {
    lease = nil
    current.entered = false
    platform.setAutoEnter(nil)
    if let sink = current.sink { platform.releaseSink(sink) }
    current.sink = nil
  }

  private func send(_ target: Lease, _ type: String, _ extra: [String: Any] = [:]) {
    target.seq += 1
    var event: [String: Any] = [
      "version": 1,
      "instanceId": target.id.instanceId,
      "callId": target.id.callId,
      "leaseId": target.id.leaseId,
      "seq": target.seq,
      "type": type,
    ]
    event.merge(extra) { _, new in new }
    emit(event)
  }
}
