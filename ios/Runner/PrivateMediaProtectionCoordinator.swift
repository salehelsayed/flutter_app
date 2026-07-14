import Flutter
import UIKit

/// Route-scoped iOS privacy handling for direct private media.
///
/// iOS cannot reliably prevent screenshots. This coordinator detects capture
/// signals, obscures the foreground scene, and tells Dart to dismiss/settle the
/// route. Owner tokens are accepted only by enter/exit and are never returned,
/// logged, included in events, or exposed by diagnostics.
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
    self.captureProvider = captureProvider ?? {
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
    result(FlutterError(
      code: "bad_args",
      message: "Invalid private media protection request",
      details: nil
    ))
  }

  private func unavailable(_ result: @escaping FlutterResult) {
    result(FlutterError(
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
          $0.activationState == .foregroundActive ||
            $0.activationState == .foregroundInactive
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
