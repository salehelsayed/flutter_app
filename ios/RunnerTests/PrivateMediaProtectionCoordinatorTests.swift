import AVFoundation
import Flutter
import UIKit
import XCTest

@testable import Runner

final class PrivateMediaProtectionCoordinatorTests: XCTestCase {
  func testOwnerReferencesScreenshotDetectionAndOrdinaryRestoration() {
    let center = NotificationCenter()
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 640))
    let cover = UIView()
    let coordinator = makeCoordinator(
      center: center,
      window: window,
      cover: cover
    )
    var events: [[String: Any]] = []
    coordinator.onListen(withArguments: nil) { raw in
      if let event = raw as? [String: Any] { events.append(event) }
    }

    assertSuccess(coordinator, method: "enter", arguments: owner("first"), active: true)
    assertSuccess(coordinator, method: "enter", arguments: owner("second"), active: true)
    assertSuccess(coordinator, method: "enter", arguments: owner("second"), active: true)
    XCTAssertEqual(debugState(coordinator)["activeOwnerCount"] as? Int, 2)
    XCTAssertNil(cover.superview)

    center.post(name: UIApplication.userDidTakeScreenshotNotification, object: nil)
    XCTAssertTrue(cover.superview === window)
    XCTAssertEqual(events.map { $0["event"] as? String }, ["screenshot"])
    XCTAssertEqual(
      PrivateMediaProtectionCoordinator.screenshotHandlingClaim,
      "detection"
    )

    assertSuccess(coordinator, method: "exit", arguments: owner("first"), active: true)
    XCTAssertTrue(cover.superview === window)
    assertSuccess(coordinator, method: "exit", arguments: owner("second"), active: false)
    XCTAssertNil(cover.superview)

    center.post(name: UIApplication.userDidTakeScreenshotNotification, object: nil)
    XCTAssertEqual(events.count, 1, "observers must be removed after the last owner exits")
  }

  func testCaptureProtectedImageViewConfiguresCaptureExcludedLayer() {
    let view = PrivateMediaCaptureProtectedImageView(
      frame: CGRect(x: 0, y: 0, width: 320, height: 640)
    )

    XCTAssertTrue(view.displayLayer.preventsCapture)
    XCTAssertEqual(view.displayLayer.videoGravity, .resizeAspect)
    XCTAssertEqual(view.displayLayer.backgroundColor, UIColor.black.cgColor)
    XCTAssertFalse(view.displayLayer.preventsDisplaySleepDuringVideoPlayback)
  }

  func testCaptureProtectedImageSampleBufferIsImmediateAndIOSurfaceBacked() throws {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    let image = UIGraphicsImageRenderer(
      size: CGSize(width: 32, height: 16),
      format: format
    ).image { context in
      UIColor.magenta.setFill()
      context.fill(CGRect(x: 0, y: 0, width: 32, height: 16))
    }
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(
      "private-media-\(UUID().uuidString).png"
    )
    try XCTUnwrap(image.pngData()).write(to: url, options: .atomic)
    defer { try? FileManager.default.removeItem(at: url) }

    let sampleBuffer = try XCTUnwrap(
      PrivateMediaCaptureProtectedImageSampleBuffer.make(path: url.path)
    )
    let pixelBuffer = try XCTUnwrap(CMSampleBufferGetImageBuffer(sampleBuffer))
    XCTAssertTrue(CMSampleBufferIsValid(sampleBuffer))
    XCTAssertEqual(CVPixelBufferGetWidth(pixelBuffer), 32)
    XCTAssertEqual(CVPixelBufferGetHeight(pixelBuffer), 16)
    XCTAssertNotNil(CVPixelBufferGetIOSurface(pixelBuffer))
    XCTAssertNotNil(
      CVBufferGetAttachment(pixelBuffer, kCVImageBufferCGColorSpaceKey, nil)
    )

    let attachments = try XCTUnwrap(
      CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
        as? [[CFString: Any]]
    )
    XCTAssertEqual(attachments.count, 1)
    XCTAssertEqual(
      attachments[0][kCMSampleAttachmentKey_DisplayImmediately] as? Bool,
      true
    )
  }

  func testCaptureAndLifecycleCoverUntilLastOwnerRestorationAndTeardown() {
    let center = NotificationCenter()
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 640))
    let cover = UIView()
    let capture = MutableCapture(false)
    let coordinator = makeCoordinator(
      center: center,
      window: window,
      cover: cover,
      capture: capture
    )
    var names: [String] = []
    coordinator.onListen(withArguments: nil) { raw in
      guard let event = raw as? [String: Any], let name = event["event"] as? String else { return }
      names.append(name)
    }
    assertSuccess(coordinator, method: "enter", arguments: owner("route"), active: true)

    center.post(name: UIApplication.willResignActiveNotification, object: nil)
    XCTAssertTrue(cover.superview === window)
    center.post(name: UIApplication.didBecomeActiveNotification, object: nil)
    XCTAssertTrue(cover.superview === window)

    capture.value = true
    center.post(name: UIScreen.capturedDidChangeNotification, object: nil)
    XCTAssertTrue(cover.superview === window)
    XCTAssertEqual(debugState(coordinator)["captureActive"] as? Bool, true)
    capture.value = false
    center.post(name: UIScreen.capturedDidChangeNotification, object: nil)
    XCTAssertTrue(cover.superview === window)

    center.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
    XCTAssertTrue(cover.superview === window)
    center.post(name: UIApplication.willEnterForegroundNotification, object: nil)
    XCTAssertTrue(cover.superview === window)

    XCTAssertEqual(
      names,
      ["inactive", "foreground", "captureStarted", "captureStopped", "background", "foreground"]
    )
    coordinator.dispose()
    XCTAssertNil(cover.superview)
    center.post(name: UIApplication.userDidTakeScreenshotNotification, object: nil)
    XCTAssertEqual(names.count, 6)
  }

  func testPendingCaptureAndBackgroundStayCoveredUntilLastOwnerExits() {
    let center = NotificationCenter()
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 640))
    let cover = UIView()
    let capture = MutableCapture(true)
    let coordinator = makeCoordinator(
      center: center,
      window: window,
      cover: cover,
      capture: capture
    )

    // Production can call enter before the EventChannel listen handshake has
    // reached native. A capture that is already active must remain observable
    // when Dart attaches after enter returns.
    assertSuccess(coordinator, method: "enter", arguments: owner("route"), active: true)
    XCTAssertTrue(cover.superview === window)
    center.post(name: UIApplication.didEnterBackgroundNotification, object: nil)

    var names: [String] = []
    coordinator.onListen(withArguments: nil) { raw in
      guard let event = raw as? [String: Any], let name = event["event"] as? String else {
        return
      }
      names.append(name)
    }
    XCTAssertEqual(names, ["captureStarted", "background"])

    capture.value = false
    center.post(name: UIScreen.capturedDidChangeNotification, object: nil)
    center.post(name: UIApplication.willEnterForegroundNotification, object: nil)
    XCTAssertEqual(
      names,
      ["captureStarted", "background", "captureStopped", "foreground"]
    )
    XCTAssertTrue(
      cover.superview === window,
      "a capture/background incident stays opaque until the last route owner exits"
    )

    assertSuccess(coordinator, method: "exit", arguments: owner("route"), active: false)
    XCTAssertNil(cover.superview)
  }

  func testMalformedCallsCompleteOnceAndChannelsDiagnosticsStayRedacted() {
    let center = NotificationCenter()
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 640))
    let cover = UIView()
    let coordinator = makeCoordinator(center: center, window: window, cover: cover)
    let secret = "owner-secret-value"
    var events: [[String: Any]] = []
    coordinator.onListen(withArguments: nil) { raw in
      if let event = raw as? [String: Any] { events.append(event) }
    }

    let malformed = invoke(
      coordinator,
      method: "enter",
      arguments: ["ownerToken": secret, "path": "/private/media.jpg"]
    )
    XCTAssertEqual(malformed.count, 1)
    let error = malformed.value as? FlutterError
    XCTAssertEqual(error?.code, "bad_args")
    XCTAssertNil(error?.details)
    XCTAssertFalse(String(describing: error).contains(secret))
    XCTAssertFalse(String(describing: error).contains("/private/media.jpg"))

    assertSuccess(coordinator, method: "enter", arguments: owner(secret), active: true)
    let state = debugState(coordinator)
    XCTAssertEqual(
      Set(state.keys),
      Set(["coverVisible", "captureActive", "activeOwnerCount"])
    )
    XCTAssertFalse(String(describing: state).contains(secret))

    let injected = invoke(
      coordinator,
      method: "debugInjectEvent",
      arguments: ["event": "background"]
    )
    XCTAssertEqual(injected.count, 1)
    XCTAssertEqual((injected.value as? [String: Any])?["ok"] as? Bool, true)
    XCTAssertEqual(events.count, 1)
    XCTAssertEqual(Set(events[0].keys), Set(["event"]))
    XCTAssertEqual(events[0]["event"] as? String, "background")
    XCTAssertFalse(String(describing: events).contains(secret))

    let invalidEvent = invoke(
      coordinator,
      method: "debugInjectEvent",
      arguments: ["event": "path=/private/media.jpg"]
    )
    XCTAssertEqual(invalidEvent.count, 1)
    XCTAssertEqual((invalidEvent.value as? FlutterError)?.code, "bad_args")
    XCTAssertNil((invalidEvent.value as? FlutterError)?.details)
    XCTAssertFalse(String(describing: invalidEvent.value).contains("/private/media.jpg"))

    assertSuccess(coordinator, method: "exit", arguments: owner("unknown"), active: true)
    assertSuccess(coordinator, method: "exit", arguments: owner(secret), active: false)
    assertSuccess(coordinator, method: "exit", arguments: owner(secret), active: false)
  }

  private func makeCoordinator(
    center: NotificationCenter,
    window: UIWindow,
    cover: UIView,
    capture: MutableCapture = MutableCapture(false)
  ) -> PrivateMediaProtectionCoordinator {
    PrivateMediaProtectionCoordinator(
      messenger: ProtectionMockMessenger(),
      notificationCenter: center,
      windowProvider: { window },
      captureProvider: { capture.value },
      coverFactory: { cover }
    )
  }

  private func owner(_ token: String) -> [String: Any] {
    ["ownerToken": token]
  }

  private func assertSuccess(
    _ coordinator: PrivateMediaProtectionCoordinator,
    method: String,
    arguments: Any?,
    active: Bool
  ) {
    let result = invoke(coordinator, method: method, arguments: arguments)
    XCTAssertEqual(result.count, 1)
    XCTAssertEqual(
      result.value as? [String: Bool],
      ["ok": true, "protectionActive": active]
    )
  }

  private func debugState(_ coordinator: PrivateMediaProtectionCoordinator) -> [String: Any] {
    let result = invoke(coordinator, method: "debugGetState", arguments: nil)
    XCTAssertEqual(result.count, 1)
    return result.value as! [String: Any]
  }

  private func invoke(
    _ coordinator: PrivateMediaProtectionCoordinator,
    method: String,
    arguments: Any?
  ) -> CapturedFlutterResult {
    let captured = CapturedFlutterResult()
    coordinator.handle(FlutterMethodCall(methodName: method, arguments: arguments)) { value in
      captured.count += 1
      captured.value = value
    }
    return captured
  }
}

private final class MutableCapture {
  var value: Bool
  init(_ value: Bool) { self.value = value }
}

private final class CapturedFlutterResult {
  var count = 0
  var value: Any?
}

private final class ProtectionMockMessenger: NSObject, FlutterBinaryMessenger {
  func send(onChannel channel: String, message: Data?) {}
  func send(onChannel channel: String, message: Data?, binaryReply callback: FlutterBinaryReply?) {}
  func setMessageHandlerOnChannel(
    _ channel: String,
    binaryMessageHandler handler: FlutterBinaryMessageHandler?
  ) -> FlutterBinaryMessengerConnection { 0 }
  func cleanUpConnection(_ connection: FlutterBinaryMessengerConnection) {}
}
