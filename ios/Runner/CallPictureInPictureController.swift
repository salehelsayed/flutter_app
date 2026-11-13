import AVKit
import Flutter
import UIKit
import WebRTC
import flutter_webrtc

/// iOS side of the live-call PiP bridge (contract v1): remote video only, through
/// AVKit's video-call PiP. No plist or entitlement change. AVKit gives this
/// content source no custom buttons, so mute/camera/End stay in the app and no
/// `action` event is emitted on iOS. Until Dart arms a lease (never while the
/// video gate is off) no AVPictureInPictureController exists.
final class CallPictureInPictureController: NSObject, CallPipPlatform, FlutterStreamHandler,
  AVPictureInPictureControllerDelegate
{
  private final class RemoteSink {
    let track: RTCVideoTrack
    let view: RTCMTLVideoView
    init(track: RTCVideoTrack, view: RTCMTLVideoView) {
      self.track = track
      self.view = view
    }
    func release() {
      track.remove(view)
      view.removeFromSuperview()
    }
  }

  private let methods: FlutterMethodChannel
  private let events: FlutterEventChannel
  private let sourceView: () -> UIView?
  private var eventSink: FlutterEventSink?
  private lazy var core = CallPipLeaseCore(platform: self) { [weak self] in self?.eventSink?($0) }
  private var pip: AVPictureInPictureController?
  private var content: AVPictureInPictureVideoCallViewController?
  private var restoring = false
  private var observers: [NSObjectProtocol] = []

  /// Test observation only: true once an armed lease created the AVKit controller.
  var hasPictureInPictureController: Bool { pip != nil }

  init(messenger: FlutterBinaryMessenger, sourceView: @escaping () -> UIView?) {
    methods = FlutterMethodChannel(name: "mknoon/call_pip", binaryMessenger: messenger)
    events = FlutterEventChannel(name: "mknoon/call_pip/events", binaryMessenger: messenger)
    self.sourceView = sourceView
    super.init()
    methods.setMethodCallHandler { [weak self] call, result in
      guard let self else { return result(FlutterMethodNotImplemented) }
      self.handle(call, result)
    }
    events.setStreamHandler(self)
    let center = NotificationCenter.default
    observers.append(
      center.addObserver(
        forName: UIApplication.protectedDataWillBecomeUnavailableNotification, object: nil, queue: .main
      ) { [weak self] _ in
        guard let self, self.pip?.isPictureInPictureActive == true else { return }
        self.core.onBlocked("locked")
      })
    observers.append(
      center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) {
        [weak self] _ in
        guard let self, self.pip?.isPictureInPictureActive != true else { return }
        self.core.onReturnedWithoutEntry()
      })
  }

  deinit {
    for observer in observers { NotificationCenter.default.removeObserver(observer) }
  }

  func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any]
    let id = CallPipIdentity.parse(args)
    switch call.method {
    case "availability":
      result(id == nil ? ["supported": false, "cameraInPip": false, "reason": "invalid"] : core.availability())
    case "arm":
      guard let id, let args, let source = CallPipSource.parse(args),
        let controls = CallPipControls.parse(args)
      else { return result(["armed": false, "reason": "invalid"]) }
      result(core.arm(id, source: source, controls: controls))
    case "update":
      guard let id, let args, let controls = CallPipControls.parse(args) else { return result(false) }
      result(core.update(id, controls: controls))
    case "enter":
      result(id.map { core.enter($0) } ?? false)
    case "disarm":
      guard let id, args?["reason"] is String else { return result(false) }
      result(core.disarm(id))
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // FlutterStreamHandler.
  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    eventSink = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }

  // CallPipPlatform.
  func supported() -> Bool { AVPictureInPictureController.isPictureInPictureSupported() }

  /// Exact peer + track lookup through the plugin's public API; never first match.
  private static func videoTrack(_ source: CallPipSource) -> RTCVideoTrack? {
    FlutterWebRTCPlugin.sharedSingleton()?
      .track(forId: source.remoteTrackId, peerConnectionId: source.peerConnectionId) as? RTCVideoTrack
  }

  func hasVideoTrack(_ source: CallPipSource) -> Bool { Self.videoTrack(source) != nil }

  func attachSink(_ source: CallPipSource) -> AnyObject? {
    guard let track = Self.videoTrack(source), let content else { return nil }
    let view = RTCMTLVideoView(frame: content.view.bounds)
    view.videoContentMode = .scaleAspectFill
    view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    content.view.addSubview(view)
    track.add(view)
    return RemoteSink(track: track, view: view)
  }

  func releaseSink(_ sink: AnyObject) {
    (sink as? RemoteSink)?.release()
  }

  func setAutoEnter(_ controls: CallPipControls?) {
    guard controls != nil else {
      pip?.canStartPictureInPictureAutomaticallyFromInline = false
      return
    }
    ensureController()
    pip?.canStartPictureInPictureAutomaticallyFromInline = true
  }

  func requestEnter() -> Bool {
    guard let pip, pip.isPictureInPicturePossible else { return false }
    pip.startPictureInPicture()
    return true
  }

  func leavePip() {
    pip?.stopPictureInPicture()
  }

  private func ensureController() {
    guard pip == nil, let source = sourceView() else { return }
    let call = AVPictureInPictureVideoCallViewController()
    call.preferredContentSize = CGSize(width: 1080, height: 1920)
    let controller = AVPictureInPictureController(
      contentSource: .init(activeVideoCallSourceView: source, contentViewController: call))
    controller.delegate = self
    pip = controller
    content = call
  }

  // AVPictureInPictureControllerDelegate.
  func pictureInPictureControllerWillStartPictureInPicture(_ controller: AVPictureInPictureController) {
    core.onUserLeaving()
  }

  func pictureInPictureControllerDidStartPictureInPicture(_ controller: AVPictureInPictureController) {
    core.onEntered()
  }

  func pictureInPictureController(
    _ controller: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error
  ) {
    core.onReturnedWithoutEntry()
  }

  func pictureInPictureController(
    _ controller: AVPictureInPictureController,
    restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
  ) {
    restoring = true
    completionHandler(true)
  }

  func pictureInPictureControllerDidStopPictureInPicture(_ controller: AVPictureInPictureController) {
    let restored = restoring
    restoring = false
    core.onExited(restored: restored)
  }
}
