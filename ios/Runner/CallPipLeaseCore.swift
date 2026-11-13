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
  // API scaffold: behavior lands in the GREEN commit.
  private unowned let platform: CallPipPlatform
  private let emit: ([String: Any]) -> Void

  init(platform: CallPipPlatform, emit: @escaping ([String: Any]) -> Void) {
    self.platform = platform
    self.emit = emit
  }

  func availability() -> [String: Any] { [:] }
  func arm(_ id: CallPipIdentity, source: CallPipSource, controls: CallPipControls) -> [String: Any] {
    ["armed": false, "reason": "unimplemented"]
  }
  func update(_ id: CallPipIdentity, controls: CallPipControls) -> Bool { false }
  func enter(_ id: CallPipIdentity) -> Bool { false }
  func disarm(_ id: CallPipIdentity) -> Bool { false }
  func onUserLeaving() {}
  func onEntered() {}
  func onExited(restored: Bool) {}
  func onAction(_ kind: String) {}
  func onBlocked(_ reason: String) {}
  func onReturnedWithoutEntry() {}
}
