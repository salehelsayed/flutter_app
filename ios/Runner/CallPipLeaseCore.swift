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

/// Exact remote lookup (PIP-NATIVE-1). The pinned plugin's peer lookup checks
/// local tracks first, so a local id collision is rejected before asking the
/// exact peer; there is never a global fallback.
func resolveExactRemoteTrack<T>(
  _ source: CallPipSource,
  localTrack: (String) -> Any?,
  peerTrack: (_ trackId: String, _ peerConnectionId: String) -> T?
) -> T? {
  if localTrack(source.remoteTrackId) != nil { return nil }
  return peerTrack(source.remoteTrackId, source.peerConnectionId)
}

/// Platform effects. A sink is an opaque native renderer bound to one track.
/// releaseSink and setAutoEnter throw when the platform cleanup fails.
protocol CallPipPlatform: AnyObject {
  func supported() -> Bool
  func hasVideoTrack(_ source: CallPipSource) -> Bool
  func attachSink(_ source: CallPipSource) -> AnyObject?
  func releaseSink(_ sink: AnyObject) throws
  func setAutoEnter(_ lease: CallPipIdentity?, _ controls: CallPipControls?) throws
  func requestEnter() -> Bool
  func leavePip()
}

/// Every OS callback carries the triple captured when it began (PIP-NATIVE-2);
/// one entry and one exit per lease, exit retires it (PIP-NATIVE-3); failed
/// cleanup stays owned until a disarm retries it (PIP-NATIVE-4).
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
  private var pendingSinks: [String: AnyObject] = [:]
  private var pendingAutoOff: CallPipIdentity?
  // The lease an in-flight OS entry belongs to, captured when it began; never
  // resolved from the current lease at completion time.
  private var pendingEntry: CallPipIdentity?

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
    guard (try? platform.setAutoEnter(id, controls)) != nil else {
      lease = nil
      return ["armed": false, "reason": "unsupported"]
    }
    pendingAutoOff = nil
    return ["armed": true, "reason": "ok"]
  }

  func update(_ id: CallPipIdentity, controls: CallPipControls) -> Bool {
    guard current(id) != nil else { return false }
    return (try? platform.setAutoEnter(id, controls)) != nil
  }

  func enter(_ id: CallPipIdentity) -> Bool {
    guard let target = current(id) else { return false }
    if target.entered { return true }
    // A retired lease's OS start is still outstanding: refuse, never overwrite.
    if let outstanding = pendingEntry, outstanding != id { return false }
    let previous = pendingEntry
    pendingEntry = id
    if platform.requestEnter() { return true }
    pendingEntry = previous
    return false
  }

  /// Retires a current triple, then retries any cleanup it still owns. True once
  /// nothing of that lease is left; never touches a successor.
  func disarm(_ id: CallPipIdentity) -> Bool {
    if lease?.id == id { retire(reason: "disarmed") }
    return retryCleanup(id)
  }

  /// OS entry is starting: attach the sink early and return the triple the
  /// adapter must pass to every later entry/exit callback.
  func beginEntry() -> CallPipIdentity? {
    guard let target = lease else { return nil }
    // An outstanding capture keeps its identity; a retired lease's capture
    // blocks the successor until its own terminal callback settles it.
    let owner = pendingEntry ?? target.id
    guard owner == target.id else { return nil }
    pendingEntry = owner
    if target.sink == nil { target.sink = platform.attachSink(target.source) }
    return owner
  }

  // OS-level callbacks: attributed only to the captured in-flight entry.

  /// False when the completion has no captured entry or a stale one; the
  /// adapter must then leave PiP.
  func osEntered() -> Bool {
    guard let owner = pendingEntry else { return false }
    onEntered(owner)
    guard let target = lease else { return false }
    return target.id == owner && target.entered
  }

  func osExited(restored: Bool) {
    if let owner = pendingEntry { onExited(owner, restored: restored) }
    pendingEntry = nil
  }

  func osEntryFailed() {
    if let owner = pendingEntry { onEntryFailed(owner) }
    pendingEntry = nil
  }

  /// `settled` false keeps a current capture (iOS can report active before
  /// stop); a retired lease's capture is always settled here.
  func osReturnedWithoutEntry(settled: Bool) {
    guard let owner = pendingEntry else { return }
    onReturnedWithoutEntry(owner)
    if settled || lease?.id != owner { pendingEntry = nil }
  }

  func onEntered(_ id: CallPipIdentity) {
    guard let target = current(id), !target.entered else { return }
    if target.sink == nil { target.sink = platform.attachSink(target.source) }
    guard target.sink != nil else {
      send(target, "failed", ["code": "trackLost"])
      drop(target)
      platform.leavePip()
      return
    }
    target.entered = true
    send(target, "entered")
  }

  func onExited(_ id: CallPipIdentity, restored: Bool) {
    guard let target = current(id), target.entered else { return }
    send(target, "exited", ["reason": restored ? "restored" : "closed"])
    drop(target)
  }

  /// OS entry failed after it began (iOS start error).
  func onEntryFailed(_ id: CallPipIdentity) {
    guard let target = current(id), !target.entered else { return }
    send(target, "failed", ["code": "enterRejected"])
    drop(target)
  }

  func onReturnedWithoutEntry(_ id: CallPipIdentity) {
    guard let target = current(id), !target.entered, let sink = target.sink else { return }
    target.sink = nil
    releaseOwned(target.id, sink)
  }

  func onAction(_ id: CallPipIdentity, _ kind: String) {
    guard let target = current(id), target.entered, Self.actions.contains(kind) else { return }
    send(target, "action", ["kind": kind])
  }

  /// Lock or user-disabled: retires the current lease even before entry.
  func onBlocked(_ reason: String) {
    guard let target = lease, Self.blocked.contains(reason) else { return }
    let wasEntered = target.entered
    drop(target)
    if wasEntered { platform.leavePip() }
    send(target, "blocked", ["reason": reason])
  }

  /// Host going away: retire without events.
  func shutdown() {
    guard let target = lease else { return }
    let wasEntered = target.entered
    drop(target)
    if wasEntered { platform.leavePip() }
  }

  private func current(_ id: CallPipIdentity) -> Lease? {
    guard let target = lease, target.id == id else { return nil }
    return target
  }

  private func accepts(_ id: CallPipIdentity) -> Bool {
    if retiredInstances.contains(id.instanceId) { return false }
    return id.instanceId != instance || id.leaseId > highestLease
  }

  private func retire(reason: String) {
    guard let target = lease else { return }
    let wasEntered = target.entered
    drop(target)
    if wasEntered {
      platform.leavePip()
      send(target, "exited", ["reason": reason])
    }
  }

  private static func key(_ id: CallPipIdentity) -> String { "\(id.instanceId)/\(id.callId)/\(id.leaseId)" }

  /// Retire first, then clean up; failed cleanup stays owned by this triple.
  private func drop(_ target: Lease) {
    lease = nil
    target.entered = false
    if (try? platform.setAutoEnter(nil, nil)) == nil { pendingAutoOff = target.id }
    guard let sink = target.sink else { return }
    target.sink = nil
    releaseOwned(target.id, sink)
  }

  private func releaseOwned(_ id: CallPipIdentity, _ sink: AnyObject) {
    if (try? platform.releaseSink(sink)) == nil { pendingSinks[Self.key(id)] = sink }
  }

  private func retryCleanup(_ id: CallPipIdentity) -> Bool {
    if pendingAutoOff == id && lease == nil {
      guard (try? platform.setAutoEnter(nil, nil)) != nil else { return false }
      pendingAutoOff = nil
    }
    guard let sink = pendingSinks[Self.key(id)] else { return pendingAutoOff != id }
    guard (try? platform.releaseSink(sink)) != nil else { return false }
    pendingSinks[Self.key(id)] = nil
    return true
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
