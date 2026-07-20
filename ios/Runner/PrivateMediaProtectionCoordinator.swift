import AVFoundation
import CoreMedia
import CoreVideo
import Flutter
import ImageIO
import UIKit

/// Route-scoped iOS privacy handling for private media.
///
/// Private still images are rendered by a separate capture-protected platform
/// view below. This coordinator keeps capture and lifecycle signals as a second
/// fail-closed boundary that covers and dismisses the route. Owner tokens are
/// accepted only by enter/exit and are never returned, logged, included in
/// events, or exposed by diagnostics.
final class PrivateMediaProtectionCoordinator: NSObject, FlutterStreamHandler {
  static let methodChannelName = "mknoon/private_media_protection"
  static let eventChannelName = "mknoon/private_media_protection/events"
  static let screenshotHandlingClaim = "detection"

  private static let debugEvents: Set<String> = [
    "screenshot",
    "captureStarted",
    "captureStopped",
    "inactive",
    "background",
    "foreground",
  ]
  private static let criticalEvents: Set<String> = [
    "screenshot",
    "captureStarted",
    "inactive",
    "background",
  ]

  private let methodChannel: FlutterMethodChannel
  private let eventChannel: FlutterEventChannel
  private let notificationCenter: NotificationCenter
  private let windowProvider: () -> UIWindow?
  private let captureProvider: () -> Bool
  private let coverFactory: () -> UIView
  private var observerTokens: [NSObjectProtocol] = []
  private var activeOwners: Set<String> = []
  private var eventSink: FlutterEventSink?
  private var pendingCriticalEvents: [String] = []
  private var coverView: UIView?
  private var captureActive = false
  private var appInactive = false
  private var incidentLatched = false
  private var disposed = false

  init(
    messenger: FlutterBinaryMessenger,
    notificationCenter: NotificationCenter = .default,
    windowProvider: @escaping () -> UIWindow? = PrivateMediaProtectionCoordinator.foregroundWindow,
    captureProvider: (() -> Bool)? = nil,
    coverFactory: @escaping () -> UIView = PrivateMediaProtectionCoordinator.makeOpaqueCover
  ) {
    methodChannel = FlutterMethodChannel(
      name: Self.methodChannelName,
      binaryMessenger: messenger
    )
    eventChannel = FlutterEventChannel(
      name: Self.eventChannelName,
      binaryMessenger: messenger
    )
    self.notificationCenter = notificationCenter
    self.windowProvider = windowProvider
    self.captureProvider =
      captureProvider ?? {
        windowProvider()?.screen.isCaptured ?? false
      }
    self.coverFactory = coverFactory
    super.init()
    methodChannel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
    eventChannel.setStreamHandler(self)
  }

  deinit {
    removeObservers()
    coverView?.removeFromSuperview()
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard !disposed else {
      unavailable(result)
      return
    }
    switch call.method {
    case "enter":
      enter(arguments: call.arguments, result: result)
    case "exit":
      exit(arguments: call.arguments, result: result)
    #if DEBUG
      case "debugGetState":
        guard call.arguments == nil else {
          invalidArguments(result)
          return
        }
        result(debugState())
      case "debugInjectEvent":
        guard let event = Self.parseDebugEvent(call.arguments) else {
          invalidArguments(result)
          return
        }
        inject(event)
        result(["ok": true])
    #endif
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  func dispose() {
    guard !disposed else { return }
    disposed = true
    activeOwners.removeAll()
    resetProtectionState()
    removeObservers()
    eventSink = nil
    methodChannel.setMethodCallHandler(nil)
    eventChannel.setStreamHandler(nil)
  }

  func onListen(
    withArguments arguments: Any?,
    eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? {
    guard !disposed else {
      return FlutterError(
        code: "protection_unavailable",
        message: "Private media protection is unavailable",
        details: nil
      )
    }
    eventSink = events
    let pending = pendingCriticalEvents
    pendingCriticalEvents.removeAll()
    pending.forEach { events(["event": $0]) }
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }

  private func enter(arguments: Any?, result: @escaping FlutterResult) {
    guard let token = Self.parseOwner(arguments) else {
      invalidArguments(result)
      return
    }
    guard windowProvider() != nil else {
      unavailable(result)
      return
    }

    let insertion = activeOwners.insert(token)
    let firstOwner = insertion.inserted && activeOwners.count == 1
    if firstOwner {
      installObservers()
    }

    captureActive = captureProvider()
    if captureActive {
      incidentLatched = true
      guard showCover() else {
        if insertion.inserted {
          activeOwners.remove(token)
        }
        if activeOwners.isEmpty {
          resetProtectionState()
          removeObservers()
        }
        unavailable(result)
        return
      }
      if insertion.inserted {
        emit("captureStarted")
      }
    }
    result(successEnvelope(protectionActive: true))
  }

  private func exit(arguments: Any?, result: @escaping FlutterResult) {
    guard let token = Self.parseOwner(arguments) else {
      invalidArguments(result)
      return
    }
    activeOwners.remove(token)
    if activeOwners.isEmpty {
      resetProtectionState()
      removeObservers()
    }
    result(successEnvelope(protectionActive: !activeOwners.isEmpty))
  }

  private func installObservers() {
    guard observerTokens.isEmpty else { return }
    observe(UIApplication.userDidTakeScreenshotNotification) { [weak self] in
      self?.handleScreenshot()
    }
    observe(UIScreen.capturedDidChangeNotification) { [weak self] in
      self?.handleCaptureChange()
    }
    observe(UIApplication.willResignActiveNotification) { [weak self] in
      self?.handleInactive()
    }
    observe(UIApplication.didEnterBackgroundNotification) { [weak self] in
      self?.handleBackground()
    }
    observe(UIApplication.willEnterForegroundNotification) { [weak self] in
      self?.handleForeground()
    }
    observe(UIApplication.didBecomeActiveNotification) { [weak self] in
      self?.handleForeground()
    }
    if #available(iOS 13.0, *) {
      observe(UIScene.willDeactivateNotification) { [weak self] in
        self?.handleInactive()
      }
      observe(UIScene.didEnterBackgroundNotification) { [weak self] in
        self?.handleBackground()
      }
      observe(UIScene.willEnterForegroundNotification) { [weak self] in
        self?.handleForeground()
      }
      observe(UIScene.didActivateNotification) { [weak self] in
        self?.handleForeground()
      }
    }
  }

  private func observe(_ name: Notification.Name, action: @escaping () -> Void) {
    let token = notificationCenter.addObserver(
      forName: name,
      object: nil,
      queue: .main
    ) { _ in action() }
    observerTokens.append(token)
  }

  private func removeObservers() {
    observerTokens.forEach(notificationCenter.removeObserver)
    observerTokens.removeAll()
  }

  private func handleScreenshot() {
    guard !activeOwners.isEmpty else { return }
    incidentLatched = true
    _ = showCover()
    emit("screenshot")
  }

  private func handleCaptureChange() {
    guard !activeOwners.isEmpty else { return }
    setCaptureActive(captureProvider())
  }

  private func setCaptureActive(_ active: Bool) {
    captureActive = active
    if active {
      incidentLatched = true
      _ = showCover()
      emit("captureStarted")
    } else {
      restoreOrdinaryPixelsIfAllowed()
      emit("captureStopped")
    }
  }

  private func handleInactive() {
    guard !activeOwners.isEmpty else { return }
    appInactive = true
    incidentLatched = true
    _ = showCover()
    emit("inactive")
  }

  private func handleBackground() {
    guard !activeOwners.isEmpty else { return }
    appInactive = true
    incidentLatched = true
    _ = showCover()
    emit("background")
  }

  private func handleForeground() {
    guard !activeOwners.isEmpty else { return }
    appInactive = false
    captureActive = captureProvider()
    restoreOrdinaryPixelsIfAllowed()
    emit("foreground")
  }

  private func inject(_ event: String) {
    switch event {
    case "screenshot": handleScreenshot()
    case "captureStarted": setCaptureActive(true)
    case "captureStopped": setCaptureActive(false)
    case "inactive": handleInactive()
    case "background": handleBackground()
    case "foreground": handleForeground()
    default: break
    }
  }

  @discardableResult
  private func showCover() -> Bool {
    guard !activeOwners.isEmpty, let window = windowProvider() else { return false }
    let cover = coverView ?? coverFactory()
    coverView = cover
    if cover.superview !== window {
      cover.removeFromSuperview()
      cover.frame = window.bounds
      cover.autoresizingMask = [.flexibleWidth, .flexibleHeight]
      window.addSubview(cover)
    }
    window.bringSubviewToFront(cover)
    return true
  }

  private func restoreOrdinaryPixelsIfAllowed() {
    if !captureActive && !appInactive && !incidentLatched {
      coverView?.removeFromSuperview()
    }
  }

  private func resetProtectionState() {
    captureActive = false
    appInactive = false
    incidentLatched = false
    pendingCriticalEvents.removeAll()
    coverView?.removeFromSuperview()
  }

  private func emit(_ event: String) {
    if let eventSink {
      eventSink(["event": event])
      return
    }
    guard
      !activeOwners.isEmpty,
      Self.criticalEvents.contains(event),
      !pendingCriticalEvents.contains(event)
    else {
      return
    }
    pendingCriticalEvents.append(event)
  }

  private func debugState() -> [String: Any] {
    [
      "coverVisible": coverView?.superview != nil,
      "captureActive": captureActive,
      "activeOwnerCount": activeOwners.count,
    ]
  }

  private func successEnvelope(protectionActive: Bool) -> [String: Any] {
    ["ok": true, "protectionActive": protectionActive]
  }

  private func invalidArguments(_ result: @escaping FlutterResult) {
    result(
      FlutterError(
        code: "bad_args",
        message: "Invalid private media protection request",
        details: nil
      ))
  }

  private func unavailable(_ result: @escaping FlutterResult) {
    result(
      FlutterError(
        code: "protection_unavailable",
        message: "Private media protection is unavailable",
        details: nil
      ))
  }

  private static func parseOwner(_ arguments: Any?) -> String? {
    guard
      let map = arguments as? [String: Any],
      Set(map.keys) == Set(["ownerToken"]),
      let token = map["ownerToken"] as? String,
      !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      token == token.trimmingCharacters(in: .whitespacesAndNewlines),
      token.count <= 128,
      token.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) })
    else {
      return nil
    }
    return token
  }

  private static func parseDebugEvent(_ arguments: Any?) -> String? {
    guard
      let map = arguments as? [String: Any],
      Set(map.keys) == Set(["event"]),
      let event = map["event"] as? String,
      debugEvents.contains(event)
    else {
      return nil
    }
    return event
  }

  private static func makeOpaqueCover() -> UIView {
    let cover = UIView(frame: .zero)
    cover.backgroundColor = .black
    cover.isOpaque = true
    cover.isUserInteractionEnabled = true
    cover.isAccessibilityElement = false
    cover.accessibilityElementsHidden = true
    return cover
  }

  private static func foregroundWindow() -> UIWindow? {
    if #available(iOS 13.0, *) {
      let scenes = UIApplication.shared.connectedScenes
        .compactMap { $0 as? UIWindowScene }
        .filter {
          $0.activationState == .foregroundActive || $0.activationState == .foregroundInactive
        }
      for scene in scenes {
        if let keyWindow = scene.windows.first(where: { $0.isKeyWindow }) {
          return keyWindow
        }
        if let visibleWindow = scene.windows.first(where: { !$0.isHidden && $0.alpha > 0 }) {
          return visibleWindow
        }
      }
    }
    return nil
  }
}

/// iOS has no window-wide FLAG_SECURE equivalent, but AVFoundation provides a
/// public, documented capture-protected video renderer. Private still images
/// are decoded to a single sample buffer and revealed through that renderer
/// only after Dart commits the route's first-frame lifecycle transition.
final class PrivateMediaCaptureProtectedImageViewFactory: NSObject,
  FlutterPlatformViewFactory
{
  static let viewType = "mknoon/private_capture_protected_image"

  private let messenger: FlutterBinaryMessenger

  init(messenger: FlutterBinaryMessenger) {
    self.messenger = messenger
    super.init()
  }

  func create(
    withFrame frame: CGRect,
    viewIdentifier viewId: Int64,
    arguments args: Any?
  ) -> FlutterPlatformView {
    let path: String?
    if let map = args as? [String: Any],
      Set(map.keys) == Set(["path"]),
      let candidate = map["path"] as? String,
      !candidate.isEmpty,
      candidate.hasPrefix("/"),
      candidate.count <= 4096,
      candidate.unicodeScalars.allSatisfy({
        !CharacterSet.controlCharacters.contains($0)
      })
    {
      path = candidate
    } else {
      path = nil
    }
    return PrivateMediaCaptureProtectedImagePlatformView(
      frame: frame,
      viewId: viewId,
      path: path,
      messenger: messenger
    )
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }
}

private final class PrivateMediaCaptureProtectedImagePlatformView: NSObject,
  FlutterPlatformView
{
  private static let decodeQueue = DispatchQueue(
    label: "mknoon.private-media-image-decode",
    qos: .userInitiated
  )

  private let protectedView: PrivateMediaCaptureProtectedImageView
  private let channel: FlutterMethodChannel
  private let path: String?
  private let notificationCenter = NotificationCenter.default
  private var observerTokens: [NSObjectProtocol] = []
  private var preparing = false
  private var preparedSampleBuffer: CMSampleBuffer?
  private var revealed = false
  private var renderFailureReported = false

  init(
    frame: CGRect,
    viewId: Int64,
    path: String?,
    messenger: FlutterBinaryMessenger
  ) {
    protectedView = PrivateMediaCaptureProtectedImageView(frame: frame)
    channel = FlutterMethodChannel(
      name: "\(PrivateMediaCaptureProtectedImageViewFactory.viewType)/\(viewId)",
      binaryMessenger: messenger
    )
    self.path = path
    super.init()
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(["ok": false])
        return
      }
      self.handle(call, result: result)
    }
    observeDecodeFailures()
  }

  deinit {
    channel.setMethodCallHandler(nil)
    observerTokens.forEach(notificationCenter.removeObserver)
    protectedView.clear()
  }

  func view() -> UIView {
    protectedView
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.arguments == nil else {
      result(["ok": false])
      return
    }
    switch call.method {
    case "prepare":
      prepare(result: result)
    case "reveal":
      reveal(result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func prepare(result: @escaping FlutterResult) {
    if preparedSampleBuffer != nil {
      result(["ok": true])
      return
    }
    guard !preparing, let path else {
      result(["ok": false])
      return
    }
    preparing = true
    Self.decodeQueue.async { [weak self] in
      let sampleBuffer = PrivateMediaCaptureProtectedImageSampleBuffer.make(path: path)
      DispatchQueue.main.async {
        guard let self else {
          result(["ok": false])
          return
        }
        self.preparing = false
        self.preparedSampleBuffer = sampleBuffer
        result(["ok": sampleBuffer != nil])
      }
    }
  }

  private func reveal(result: @escaping FlutterResult) {
    if revealed {
      result(["ok": !renderFailureReported])
      return
    }
    guard let sampleBuffer = preparedSampleBuffer else {
      result(["ok": false])
      return
    }
    revealed = true
    protectedView.replace(with: sampleBuffer) { [weak self] accepted in
      guard let self else {
        result(["ok": false])
        return
      }
      if !accepted { self.reportRenderFailure() }
      result(["ok": accepted])
    }
  }

  private func observeDecodeFailures() {
    let name: Notification.Name
    let object: Any
    if #available(iOS 17.0, *) {
      name = AVSampleBufferVideoRenderer.didFailToDecodeNotification
      object = protectedView.displayLayer.sampleBufferRenderer
    } else {
      name = Notification.Name.AVSampleBufferDisplayLayerFailedToDecode
      object = protectedView.displayLayer
    }
    observerTokens.append(
      notificationCenter.addObserver(
        forName: name,
        object: object,
        queue: .main
      ) { [weak self] _ in
        self?.reportRenderFailure()
      }
    )
  }

  private func reportRenderFailure() {
    guard revealed, !renderFailureReported else { return }
    renderFailureReported = true
    protectedView.clear()
    channel.invokeMethod("renderFailure", arguments: nil)
  }
}

final class PrivateMediaCaptureProtectedImageView: UIView {
  override class var layerClass: AnyClass {
    AVSampleBufferDisplayLayer.self
  }

  var displayLayer: AVSampleBufferDisplayLayer {
    layer as! AVSampleBufferDisplayLayer
  }

  override init(frame: CGRect) {
    super.init(frame: frame)
    backgroundColor = .black
    isOpaque = true
    isAccessibilityElement = false
    accessibilityElementsHidden = true
    displayLayer.backgroundColor = UIColor.black.cgColor
    displayLayer.videoGravity = .resizeAspect
    displayLayer.preventsCapture = true
    displayLayer.preventsDisplaySleepDuringVideoPlayback = false
  }

  required init?(coder: NSCoder) {
    nil
  }

  func clear() {
    if #available(iOS 17.0, *) {
      displayLayer.sampleBufferRenderer.flush(
        removingDisplayedImage: true,
        completionHandler: nil
      )
    } else {
      displayLayer.flushAndRemoveImage()
    }
  }

  func replace(
    with sampleBuffer: CMSampleBuffer,
    completion: @escaping (Bool) -> Void
  ) {
    displayLayer.preventsCapture = true
    if #available(iOS 17.0, *) {
      let renderer = displayLayer.sampleBufferRenderer
      renderer.flush(removingDisplayedImage: true) {
        DispatchQueue.main.async {
          renderer.enqueue(sampleBuffer)
          completion(renderer.status != .failed)
        }
      }
    } else {
      displayLayer.flushAndRemoveImage()
      displayLayer.enqueue(sampleBuffer)
      completion(displayLayer.status != .failed)
    }
  }
}

enum PrivateMediaCaptureProtectedImageSampleBuffer {
  private static let maxPixelSize = 4096

  static func make(path: String) -> CMSampleBuffer? {
    let url = URL(fileURLWithPath: path) as CFURL
    guard let source = CGImageSourceCreateWithURL(url, nil) else { return nil }
    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
      kCGImageSourceShouldCacheImmediately: true,
    ]
    guard
      let image = CGImageSourceCreateThumbnailAtIndex(
        source,
        0,
        options as CFDictionary
      ),
      let pixelBuffer = makePixelBuffer(image: image)
    else {
      return nil
    }

    var formatDescription: CMVideoFormatDescription?
    guard
      CMVideoFormatDescriptionCreateForImageBuffer(
        allocator: kCFAllocatorDefault,
        imageBuffer: pixelBuffer,
        formatDescriptionOut: &formatDescription
      ) == noErr,
      let formatDescription
    else {
      return nil
    }

    var timing = CMSampleTimingInfo(
      duration: .invalid,
      presentationTimeStamp: .zero,
      decodeTimeStamp: .invalid
    )
    var sampleBuffer: CMSampleBuffer?
    guard
      CMSampleBufferCreateReadyWithImageBuffer(
        allocator: kCFAllocatorDefault,
        imageBuffer: pixelBuffer,
        formatDescription: formatDescription,
        sampleTiming: &timing,
        sampleBufferOut: &sampleBuffer
      ) == noErr,
      let sampleBuffer
    else {
      return nil
    }

    guard
      let attachments = CMSampleBufferGetSampleAttachmentsArray(
        sampleBuffer,
        createIfNecessary: true
      ),
      CFArrayGetCount(attachments) == 1
    else {
      return nil
    }
    let first = unsafeBitCast(
      CFArrayGetValueAtIndex(attachments, 0),
      to: CFMutableDictionary.self
    )
    CFDictionarySetValue(
      first,
      Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
      Unmanaged.passUnretained(kCFBooleanTrue).toOpaque()
    )
    return sampleBuffer
  }

  private static func makePixelBuffer(image: CGImage) -> CVPixelBuffer? {
    let attributes =
      [
        kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue,
        kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue,
        kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
      ] as CFDictionary
    var pixelBuffer: CVPixelBuffer?
    guard
      CVPixelBufferCreate(
        kCFAllocatorDefault,
        image.width,
        image.height,
        kCVPixelFormatType_32BGRA,
        attributes,
        &pixelBuffer
      ) == kCVReturnSuccess,
      let pixelBuffer
    else {
      return nil
    }

    guard CVPixelBufferLockBaseAddress(pixelBuffer, []) == kCVReturnSuccess else {
      return nil
    }
    defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    CVBufferSetAttachment(
      pixelBuffer,
      kCVImageBufferCGColorSpaceKey,
      colorSpace,
      .shouldPropagate
    )
    guard
      let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer),
      let context = CGContext(
        data: baseAddress,
        width: image.width,
        height: image.height,
        bitsPerComponent: 8,
        bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
        space: colorSpace,
        bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue
          | CGImageAlphaInfo.premultipliedFirst.rawValue
      )
    else {
      return nil
    }
    context.draw(
      image,
      in: CGRect(x: 0, y: 0, width: image.width, height: image.height)
    )
    return pixelBuffer
  }
}
