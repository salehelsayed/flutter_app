import Flutter
import UIKit
import XCTest

@testable import Runner

final class CallPipLeaseCoreTests: XCTestCase {
  private final class FakePlatform: CallPipPlatform {
    var isSupported = true
    var videoTracks = [CallPipSource(peerConnectionId: "pc-1", remoteTrackId: "remote-v")]
    var enterAllowed = true
    var log: [String] = []
    var live: [String] = []
    var autoEnter: CallPipControls?
    var autoLease: CallPipIdentity?
    var failRelease = false
    private var next = 0

    func supported() -> Bool { isSupported }
    func hasVideoTrack(_ source: CallPipSource) -> Bool { videoTracks.contains(source) }
    func attachSink(_ source: CallPipSource) -> AnyObject? {
      guard videoTracks.contains(source) else { return nil }
      next += 1
      let sink = "sink-\(next):\(source.peerConnectionId)"
      live.append(sink)
      log.append("attach \(sink)")
      return sink as NSString
    }
    func releaseSink(_ sink: AnyObject) throws {
      if failRelease { throw NSError(domain: "test", code: 1) }
      let name = sink as! String
      live.removeAll { $0 == name }
      log.append("release \(name)")
    }
    func setAutoEnter(_ lease: CallPipIdentity?, _ controls: CallPipControls?) throws {
      autoEnter = controls
      autoLease = lease
      log.append("auto \(controls != nil)")
    }
    func requestEnter() -> Bool {
      log.append("enter")
      return enterAllowed
    }
    func leavePip() { log.append("leave") }
  }

  private var platform: FakePlatform!
  private var events: [[String: Any]] = []
  private var core: CallPipLeaseCore!
  private let source = CallPipSource(peerConnectionId: "pc-1", remoteTrackId: "remote-v")
  private let controls = CallPipControls(muted: false, cameraOn: false, cameraEnabled: false)

  override func setUp() {
    super.setUp()
    platform = FakePlatform()
    events = []
    core = CallPipLeaseCore(platform: platform) { [unowned self] in self.events.append($0) }
  }

  private func id(_ lease: Int64, _ instance: String = "graph-a") -> CallPipIdentity {
    CallPipIdentity(instanceId: instance, callId: "call-1", leaseId: lease)
  }

  private func types() -> [String] {
    events.map { "\($0["leaseId"]!):\($0["seq"]!):\($0["type"]!)" }
  }

  func testParseAcceptsOnlyTheExactV1Schema() {
    let args: [String: Any] = [
      "version": 1, "instanceId": "graph-a", "callId": "call-1", "leaseId": 3,
      "negotiationId": "n", "mediaRevision": 0, "rendererEpoch": 2,
      "peerConnectionId": "pc-1", "remoteTrackId": "remote-v",
      "muted": true, "cameraOn": false, "cameraEnabled": false,
    ]
    XCTAssertEqual(CallPipIdentity.parse(args), id(3))
    XCTAssertEqual(CallPipSource.parse(args), source)
    XCTAssertEqual(CallPipControls.parse(args), CallPipControls(muted: true, cameraOn: false, cameraEnabled: false))
    XCTAssertNil(CallPipIdentity.parse(args.merging(["version": 2]) { $1 }))
    XCTAssertNil(CallPipIdentity.parse(args.merging(["leaseId": 0]) { $1 }))
    XCTAssertNil(CallPipSource.parse(args.filter { $0.key != "peerConnectionId" }))
    XCTAssertNil(CallPipControls.parse(args.filter { $0.key != "cameraEnabled" }))
  }

  func testWithoutAnArmNothingIsRequestedGateOff() {
    XCTAssertNil(core.beginEntry())
    core.onEntered(id(1))
    core.onAction(id(1), "end")
    core.onReturnedWithoutEntry(id(1))
    core.onBlocked("locked")
    core.shutdown()
    XCTAssertEqual(platform.log, [])
    XCTAssertTrue(events.isEmpty)
  }

  func testAvailabilityNeverClaimsCameraInPip() {
    XCTAssertEqual(core.availability() as NSDictionary, ["supported": true, "cameraInPip": false, "reason": "ok"])
    platform.isSupported = false
    XCTAssertEqual(core.availability() as NSDictionary, ["supported": false, "cameraInPip": false, "reason": "os"])
  }

  func testRemoteLookupRejectsLocalCollisionAndWrongPeer() {
    func resolve(_ s: CallPipSource, locals: Set<String>) -> String? {
      resolveExactRemoteTrack(
        s,
        localTrack: { locals.contains($0) ? "local-camera" : nil },
        peerTrack: { track, peer in track == "remote-v" && peer == "pc-1" ? "remote-track" : nil })
    }
    XCTAssertEqual(resolve(source, locals: []), "remote-track")
    XCTAssertNil(resolve(source, locals: ["remote-v"]))
    XCTAssertNil(resolve(CallPipSource(peerConnectionId: "pc-old", remoteTrackId: "remote-v"), locals: []))
  }

  func testArmBindsOnlyTheExactPeerAndVideoTrack() {
    let stale = CallPipSource(peerConnectionId: "pc-old", remoteTrackId: "remote-v")
    XCTAssertEqual(core.arm(id(1), source: stale, controls: controls) as NSDictionary, ["armed": false, "reason": "trackNotFound"])
    XCTAssertNil(platform.autoEnter)
    XCTAssertEqual(core.arm(id(2), source: source, controls: controls) as NSDictionary, ["armed": true, "reason": "ok"])
    XCTAssertEqual(platform.autoEnter, controls)
    XCTAssertEqual(platform.autoLease, id(2))
    XCTAssertEqual(platform.log, ["auto true"])
  }

  func testOneEntryAndOneExitPerLeaseThenRetired() {
    _ = core.arm(id(1), source: source, controls: controls)
    core.onAction(id(1), "mute")
    XCTAssertEqual(core.beginEntry(), id(1))
    core.onEntered(id(1))
    core.onEntered(id(1))
    core.onAction(id(1), "mute")
    core.onExited(id(1), restored: true)
    core.onExited(id(1), restored: false)
    core.onEntered(id(1))
    XCTAssertEqual(types(), ["1:1:entered", "1:2:action", "1:3:exited"])
    XCTAssertEqual(events[2]["reason"] as? String, "restored")
    XCTAssertNil(platform.autoEnter)
    XCTAssertEqual(platform.live, [])
    XCTAssertFalse(core.update(id(1), controls: controls))
    XCTAssertEqual(events[0]["instanceId"] as? String, "graph-a")
    XCTAssertEqual(events[0]["version"] as? Int, 1)
  }

  func testCloseReportsClosedAndReentryNeedsFreshArm() {
    _ = core.arm(id(1), source: source, controls: controls)
    _ = core.beginEntry()
    core.onEntered(id(1))
    core.onExited(id(1), restored: false)
    XCTAssertEqual(events.last?["reason"] as? String, "closed")
    XCTAssertNil(core.beginEntry())
    _ = core.arm(id(2), source: source, controls: controls)
    _ = core.beginEntry()
    core.onEntered(id(2))
    XCTAssertEqual(types(), ["1:1:entered", "1:2:exited", "2:1:entered"])
  }

  func testOldCallbacksNeverTouchASuccessor() {
    _ = core.arm(id(1), source: source, controls: controls)
    _ = core.beginEntry()
    core.onEntered(id(1))
    _ = core.arm(id(2), source: source, controls: controls)
    core.onAction(id(1), "end")
    core.onEntered(id(1))
    core.onExited(id(1), restored: false)
    core.onEntryFailed(id(1))
    core.onReturnedWithoutEntry(id(1))
    XCTAssertEqual(types(), ["1:1:entered", "1:2:exited"])
    XCTAssertEqual(platform.autoLease, id(2))
    XCTAssertEqual(core.beginEntry(), id(2))
    XCTAssertEqual(platform.live, ["sink-2:pc-1"])
    XCTAssertFalse(core.arm(id(1), source: source, controls: controls)["armed"] as! Bool)
  }

  func testNewGraphInstanceRetiresTheOldOneForGood() {
    _ = core.arm(id(5, "graph-a"), source: source, controls: controls)
    XCTAssertEqual(core.arm(id(1, "graph-b"), source: source, controls: controls)["armed"] as? Bool, true)
    XCTAssertEqual(core.arm(id(9, "graph-a"), source: source, controls: controls)["reason"] as? String, "stale")
    XCTAssertTrue(core.update(id(1, "graph-b"), controls: controls))
  }

  func testDisarmRetiresBeforeCleanupAndEmitsNothingAfter() {
    _ = core.arm(id(1), source: source, controls: controls)
    _ = core.beginEntry()
    core.onEntered(id(1))
    XCTAssertTrue(core.disarm(id(1)))
    XCTAssertEqual(types(), ["1:1:entered", "1:2:exited"])
    XCTAssertNil(platform.autoEnter)
    XCTAssertTrue(platform.log.contains("leave"))
    core.onAction(id(1), "end")
    core.onExited(id(1), restored: true)
    XCTAssertEqual(events.count, 2)
  }

  func testFailedCleanupStaysOwnedAndIsRetried() {
    _ = core.arm(id(1), source: source, controls: controls)
    _ = core.beginEntry()
    core.onEntered(id(1))
    platform.failRelease = true
    XCTAssertFalse(core.disarm(id(1)))
    XCTAssertEqual(platform.live, ["sink-1:pc-1"])
    XCTAssertEqual(core.arm(id(2), source: source, controls: controls)["armed"] as? Bool, true)
    XCTAssertFalse(core.disarm(id(1)))
    XCTAssertEqual(platform.autoEnter, controls)
    platform.failRelease = false
    XCTAssertTrue(core.disarm(id(1)))
    XCTAssertEqual(platform.live, [])
    XCTAssertTrue(core.update(id(2), controls: controls))
  }

  func testShutdownRetiresAndTurnsAutoEntryOff() {
    _ = core.arm(id(1), source: source, controls: controls)
    _ = core.beginEntry()
    core.onEntered(id(1))
    core.shutdown()
    XCTAssertNil(platform.autoEnter)
    XCTAssertEqual(platform.live, [])
    XCTAssertEqual(types(), ["1:1:entered"])
  }

  func testTrackLostAndAsyncStartFailureRetire() {
    _ = core.arm(id(1), source: source, controls: controls)
    platform.videoTracks = []
    core.onEntered(id(1))
    XCTAssertEqual(events.last?["code"] as? String, "trackLost")
    platform.videoTracks = [source]
    _ = core.arm(id(2), source: source, controls: controls)
    _ = core.beginEntry()
    core.onEntryFailed(id(2))
    XCTAssertEqual(types(), ["1:1:failed", "2:1:failed"])
    XCTAssertEqual(events.last?["code"] as? String, "enterRejected")
    XCTAssertNil(platform.autoEnter)
    XCTAssertEqual(platform.live, [])
  }

  func testLockRetiresAnArmedLeaseBeforeEntry() {
    _ = core.arm(id(1), source: source, controls: controls)
    core.onBlocked("locked")
    XCTAssertEqual(types(), ["1:1:blocked"])
    XCTAssertNil(platform.autoEnter)
    XCTAssertNil(core.beginEntry())
    XCTAssertTrue(core.disarm(id(1)))
  }

  func testEnterIsBestEffortAndIdempotent() {
    XCTAssertFalse(core.enter(id(1)))
    _ = core.arm(id(1), source: source, controls: controls)
    platform.enterAllowed = false
    XCTAssertFalse(core.enter(id(1)))
    XCTAssertTrue(events.isEmpty)
    platform.enterAllowed = true
    XCTAssertTrue(core.enter(id(1)))
    core.onEntered(id(1))
    let requests = platform.log.filter { $0 == "enter" }.count
    XCTAssertTrue(core.enter(id(1)))
    XCTAssertEqual(platform.log.filter { $0 == "enter" }.count, requests)
  }

  func testLateCompletionOfExplicitEnterIsNeverCreditedToSuccessor() {
    _ = core.arm(id(1), source: source, controls: controls)
    XCTAssertTrue(core.enter(id(1)))
    _ = core.arm(id(2), source: source, controls: controls)
    XCTAssertFalse(core.osEntered())
    XCTAssertTrue(events.isEmpty)
    XCTAssertEqual(platform.live, [])
    XCTAssertEqual(platform.autoLease, id(2))
    core.osExited(restored: false)
    XCTAssertTrue(events.isEmpty)
    XCTAssertEqual(core.beginEntry(), id(2))
    XCTAssertTrue(core.osEntered())
    XCTAssertEqual(types(), ["2:1:entered"])
  }

  func testCompletionWithNoCapturedEntryIsRejected() {
    _ = core.arm(id(1), source: source, controls: controls)
    XCTAssertFalse(core.osEntered())
    core.osEntryFailed()
    core.osExited(restored: true)
    XCTAssertTrue(events.isEmpty)
    XCTAssertEqual(platform.live, [])
  }

  func testOsCallbacksFollowTheCapturedEntry() {
    _ = core.arm(id(1), source: source, controls: controls)
    XCTAssertTrue(core.enter(id(1)))
    XCTAssertEqual(core.beginEntry(), id(1))
    XCTAssertTrue(core.osEntered())
    core.osReturnedWithoutEntry(settled: false) // iOS active-before-stop: inert
    core.osExited(restored: true)
    XCTAssertEqual(types(), ["1:1:entered", "1:2:exited"])
    _ = core.arm(id(2), source: source, controls: controls)
    _ = core.beginEntry()
    core.osEntryFailed()
    XCTAssertEqual(events.last?["code"] as? String, "enterRejected")
    XCTAssertFalse(core.osEntered())
  }

  /// Guard for Kayan m-69a3dbc5 condition 2: without an arm no PiP controller exists.
  func testControllerCreatesNoPipBeforeArmAndFailsClosed() {
    let controller = CallPictureInPictureController(messenger: MockFlutterBinaryMessenger()) { UIView() }
    var replies: [Any?] = []
    let identity: [String: Any] = ["version": 1, "instanceId": "graph-a", "callId": "call-1", "leaseId": 1]
    controller.handle(FlutterMethodCall(methodName: "arm", arguments: identity)) { replies.append($0) }
    controller.handle(FlutterMethodCall(methodName: "enter", arguments: identity)) { replies.append($0) }
    controller.handle(FlutterMethodCall(methodName: "disarm", arguments: identity)) { replies.append($0) }
    controller.handle(FlutterMethodCall(methodName: "availability", arguments: ["version": 2])) {
      replies.append($0)
    }
    XCTAssertEqual(replies[0] as? NSDictionary, ["armed": false, "reason": "invalid"])
    XCTAssertEqual(replies[1] as? Bool, false)
    XCTAssertEqual(replies[2] as? Bool, false)
    XCTAssertEqual(replies[3] as? NSDictionary, ["supported": false, "cameraInPip": false, "reason": "invalid"])
    XCTAssertFalse(controller.hasPictureInPictureController)
  }
}
