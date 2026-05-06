import Flutter
import FirebaseMessaging
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
#if canImport(GoMknoon)
  private var goBridge: GoBridge?
#endif
  private let iosNotificationOpenChannelName = "mknoon/ios_notification_open"
  private var iosNotificationOpenChannel: FlutterMethodChannel?
  private var pendingIosNotificationOpen: [String: Any]?
  private var iosNotificationOpenBridgeReady = false

  deinit {
    NotificationCenter.default.removeObserver(self)
  }

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    installNotificationCenterDelegate(context: "before_didFinishLaunching_super")
    let didFinish = super.application(application, didFinishLaunchingWithOptions: launchOptions)
    configureIosNotificationOpenBridgeFromRootViewController()
    installNotificationCenterDelegate(context: "after_didFinishLaunching_super")
    NSLog("[PUSH_DIAG] didFinishLaunching super=%@", didFinish ? "true" : "false")
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleDidBecomeActiveNotification),
      name: UIApplication.didBecomeActiveNotification,
      object: nil
    )
    logNotificationSettings(context: "didFinishLaunching")
    requestRemoteNotificationRegistration(reason: "didFinishLaunching")
    return didFinish
  }

  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    NSLog("[PUSH_DIAG] didRegisterForRemoteNotificationsWithDeviceToken bytes=%d", deviceToken.count)
    // Forward the APNs token explicitly so Firebase Messaging can mint the
    // FCM token even if iOS release/TestFlight delivery differs from debug.
    Messaging.messaging().apnsToken = deviceToken
    super.application(
      application,
      didRegisterForRemoteNotificationsWithDeviceToken: deviceToken
    )
  }

  override func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    NSLog("[PUSH_DIAG] didFailToRegisterForRemoteNotifications error=%@", String(describing: error))
    super.application(
      application,
      didFailToRegisterForRemoteNotificationsWithError: error
    )
  }

  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    let userInfo = response.notification.request.content.userInfo
    let keyNames = Set(userInfo.keys.map { String(describing: $0) })
    let flnKeys = ["NotificationId", "payload"].filter { keyNames.contains($0) }
    let fcmKeys = ["gcm.message_id"].filter { keyNames.contains($0) }
    let keyShape: String
    switch (flnKeys.isEmpty, fcmKeys.isEmpty) {
    case (false, false):
      keyShape = "fln+fcm"
    case (false, true):
      keyShape = "fln"
    case (true, false):
      keyShape = "fcm"
    case (true, true):
      keyShape = "neither"
    }
    let delegateClass: String
    if let delegate = center.delegate {
      delegateClass = String(describing: type(of: delegate))
    } else {
      delegateClass = "nil"
    }
    NSLog(
      "[PUSH_DIAG] ios_native_un_didReceive actionIdentifier=%@ delegateClass=%@ userInfoKeyShape=%@ userInfoKeyCount=%d flnKeys=%@ fcmKeys=%@",
      response.actionIdentifier,
      delegateClass,
      keyShape,
      userInfo.count,
      flnKeys.isEmpty ? "none" : flnKeys.joined(separator: ","),
      fcmKeys.isEmpty ? "none" : fcmKeys.joined(separator: ",")
    )
    forwardIosNotificationOpenIfNeeded(userInfo: userInfo)
    super.userNotificationCenter(
      center,
      didReceive: response,
      withCompletionHandler: completionHandler
    )
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    installNotificationCenterDelegate(context: "after_implicit_engine_plugin_registration")
    let messenger = engineBridge.applicationRegistrar.messenger()
    setupIosNotificationOpenBridge(messenger: messenger)

#if canImport(GoMknoon)
    goBridge = GoBridge(messenger: messenger)
    NSLog("[GoBridge] Initialized via applicationRegistrar messenger")
#endif
  }

  @objc private func handleDidBecomeActiveNotification() {
    NSLog("[PUSH_DIAG] didBecomeActiveNotification")
    installNotificationCenterDelegate(context: "didBecomeActive")
    logNotificationSettings(context: "didBecomeActive")
    requestRemoteNotificationRegistration(reason: "didBecomeActive")
  }

  private func installNotificationCenterDelegate(context: String) {
    if #available(iOS 10.0, *) {
      let center = UNUserNotificationCenter.current()
      let previousDelegateClass: String
      if let delegate = center.delegate {
        previousDelegateClass = String(describing: type(of: delegate))
      } else {
        previousDelegateClass = "nil"
      }
      center.delegate = self
      NSLog(
        "[PUSH_DIAG] notification_center_delegate_installed context=%@ previousDelegateClass=%@ currentDelegateClass=%@",
        context,
        previousDelegateClass,
        String(describing: type(of: center.delegate))
      )
    }
  }

  private func requestRemoteNotificationRegistration(reason: String) {
    DispatchQueue.main.async {
      NSLog("[PUSH_DIAG] native_registerForRemoteNotifications_begin reason=%@", reason)
      UIApplication.shared.registerForRemoteNotifications()
      NSLog(
        "[PUSH_DIAG] native_registerForRemoteNotifications_requested reason=%@ isRegistered=%@",
        reason,
        UIApplication.shared.isRegisteredForRemoteNotifications ? "true" : "false"
      )
    }
  }

  private func logNotificationSettings(context: String) {
    UNUserNotificationCenter.current().getNotificationSettings { settings in
      NSLog(
        "[PUSH_DIAG] native_notification_settings context=%@ authorization=%@ alert=%@ badge=%@ sound=%@",
        context,
        String(describing: settings.authorizationStatus),
        String(describing: settings.alertSetting),
        String(describing: settings.badgeSetting),
        String(describing: settings.soundSetting)
      )
    }
  }

  private func configureIosNotificationOpenBridgeFromRootViewController() {
    guard let controller = window?.rootViewController as? FlutterViewController else {
      return
    }
    setupIosNotificationOpenBridge(messenger: controller.binaryMessenger)
  }

  private func setupIosNotificationOpenBridge(messenger: FlutterBinaryMessenger) {
    if iosNotificationOpenChannel != nil {
      return
    }
    let channel = FlutterMethodChannel(
      name: iosNotificationOpenChannelName,
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handleIosNotificationOpenMethodCall(call, result: result)
    }
    iosNotificationOpenChannel = channel
    NSLog("[PUSH_DIAG] ios_notification_open_bridge_setup")
  }

  private func handleIosNotificationOpenMethodCall(
    _ call: FlutterMethodCall,
    result: @escaping FlutterResult
  ) {
    switch call.method {
    case "markNotificationOpenBridgeReady":
      iosNotificationOpenBridgeReady = true
      NSLog("[PUSH_DIAG] ios_notification_open_bridge_ready")
      result(nil)
    case "consumeInitialNotificationOpen":
      let payload = pendingIosNotificationOpen
      pendingIosNotificationOpen = nil
      if payload == nil {
        NSLog("[PUSH_DIAG] ios_notification_open_initial_empty")
      } else {
        NSLog("[PUSH_DIAG] ios_notification_open_initial_consumed")
      }
      result(payload)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func forwardIosNotificationOpenIfNeeded(userInfo: [AnyHashable: Any]) {
    let payload = copiedNotificationUserInfo(userInfo)
    guard isRouteShapedApnsNotificationOpenPayload(payload) else {
      NSLog("[PUSH_DIAG] ios_notification_open_skipped reason=not_route_shaped")
      return
    }
    guard !isFlnNotificationOpenPayload(payload) else {
      NSLog("[PUSH_DIAG] ios_notification_open_skipped reason=fln_payload")
      return
    }

    if iosNotificationOpenBridgeReady, let channel = iosNotificationOpenChannel {
      channel.invokeMethod("notificationOpened", arguments: payload)
      NSLog("[PUSH_DIAG] ios_notification_open_forwarded_warm")
    } else {
      pendingIosNotificationOpen = payload
      NSLog("[PUSH_DIAG] ios_notification_open_stored_pending")
    }
  }

  private func copiedNotificationUserInfo(_ userInfo: [AnyHashable: Any]) -> [String: Any] {
    var payload: [String: Any] = [:]
    for (key, value) in userInfo {
      payload[String(describing: key)] = jsonCompatibleNotificationValue(value)
    }
    return payload
  }

  private func jsonCompatibleNotificationValue(_ value: Any) -> Any {
    if let dictionary = value as? [AnyHashable: Any] {
      var copied: [String: Any] = [:]
      for (key, nestedValue) in dictionary {
        copied[String(describing: key)] = jsonCompatibleNotificationValue(nestedValue)
      }
      return copied
    }
    if let dictionary = value as? [String: Any] {
      return dictionary.mapValues { jsonCompatibleNotificationValue($0) }
    }
    if let array = value as? [Any] {
      return array.map { jsonCompatibleNotificationValue($0) }
    }
    if value is NSNull || value is String || value is NSNumber {
      return value
    }
    return String(describing: value)
  }

  private func isFlnNotificationOpenPayload(_ payload: [String: Any]) -> Bool {
    return payload["NotificationId"] != nil || payload["payload"] != nil
  }

  private func isRouteShapedApnsNotificationOpenPayload(_ payload: [String: Any]) -> Bool {
    guard let type = trimmedString(payload["type"]) else {
      return false
    }

    switch type {
    case "new_message":
      return trimmedString(payload["sender_id"]) != nil ||
        trimmedString(payload["from"]) != nil
    case "contact_request":
      return trimmedString(payload["sender_id"]) != nil ||
        trimmedString(payload["peer_id"]) != nil ||
        trimmedString(payload["peerId"]) != nil ||
        trimmedString(payload["from"]) != nil ||
        trimmedString(payload["ns"]) != nil
    case "group_message":
      return trimmedString(payload["groupId"]) != nil
    case "group_invite":
      return trimmedString(payload["groupId"]) != nil
    case "intros":
      return true
    case "post_create", "post_reaction", "post_comment_reaction":
      return trimmedString(payload["postId"]) != nil ||
        trimmedString(payload["post_id"]) != nil
    case "post_comment":
      let postId = trimmedString(payload["postId"]) ??
        trimmedString(payload["post_id"])
      let commentId = trimmedString(payload["commentId"]) ??
        trimmedString(payload["comment_id"])
      return postId != nil && commentId != nil
    default:
      return false
    }
  }

  private func trimmedString(_ value: Any?) -> String? {
    if let string = value as? String {
      let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
      return trimmed.isEmpty ? nil : trimmed
    }
    if let number = value as? NSNumber {
      return number.stringValue
    }
    return nil
  }
}
