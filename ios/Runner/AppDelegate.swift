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

  // Move Account transfer keep-alive (audit gap G7, background half): while
  // Dart holds the keep-alive, a UIKit background task assertion buys ~30s of
  // continued execution after the user backgrounds the app, so a brief app
  // switch does not suspend the sender's segment POSTs or the receiver's
  // local HTTP server mid-transfer.
  private let migrationKeepAliveChannelName = "mknoon/migration_keepalive"
  private var migrationKeepAliveChannel: FlutterMethodChannel?
  private var migrationKeepAliveActive = false
  private var migrationBackgroundTask: UIBackgroundTaskIdentifier = .invalid
  private let diskSpaceChannelName = "mknoon/disk_space"
  private var diskSpaceChannel: FlutterMethodChannel?

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
    logApnsProviderProbeFcmToken(context: "didRegisterForRemoteNotifications")
    super.application(
      application,
      didRegisterForRemoteNotificationsWithDeviceToken: deviceToken
    )
  }

  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    logApnsProviderProbeNotification(
      context: "willPresent",
      userInfo: notification.request.content.userInfo
    )
    super.userNotificationCenter(
      center,
      willPresent: notification,
      withCompletionHandler: completionHandler
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
    logApnsProviderProbeNotification(
      context: "didReceive",
      userInfo: userInfo
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
    setupMigrationKeepAliveBridge(messenger: messenger)
    setupDiskSpaceBridge(messenger: messenger)

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

  private func apnsProviderProbeEnabled() -> Bool {
    let environment = ProcessInfo.processInfo.environment
    if environment["MKNOON_APNS_PROVIDER_PROBE"] == "1" {
      return true
    }
    return ProcessInfo.processInfo.arguments.contains("--mknoon-apns-provider-probe")
  }

  private func logApnsProviderProbeFcmToken(context: String) {
    guard apnsProviderProbeEnabled() else {
      return
    }
    Messaging.messaging().token { token, error in
      if let error = error {
        NSLog(
          "MKNOON_APNS_PROVIDER_PROBE_NATIVE event=fcm_token_error context=%@ error=%@",
          context,
          String(describing: error)
        )
        return
      }
      guard let token = token, !token.isEmpty else {
        NSLog(
          "MKNOON_APNS_PROVIDER_PROBE_NATIVE event=fcm_token_missing context=%@",
          context
        )
        return
      }
      NSLog(
        "MKNOON_APNS_PROVIDER_PROBE_NATIVE event=fcm_token_ready context=%@ token=%@ length=%d",
        context,
        token,
        token.count
      )
    }
  }

  private func logApnsProviderProbeNotification(
    context: String,
    userInfo: [AnyHashable: Any]
  ) {
    guard apnsProviderProbeEnabled() else {
      return
    }
    let keys = userInfo.keys.map { String(describing: $0) }.sorted().joined(separator: ",")
    let probeId = trimmedString(userInfo["probe_id"]) ?? "none"
    let type = trimmedString(userInfo["type"]) ?? "none"
    let messageId = trimmedString(userInfo["message_id"]) ??
      trimmedString(userInfo["messageId"]) ??
      "none"
    NSLog(
      "MKNOON_APNS_PROVIDER_PROBE_NATIVE event=notification_received context=%@ probe_id=%@ type=%@ message_id=%@ keys=%@",
      context,
      probeId,
      type,
      messageId,
      keys
    )
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
    setupMigrationKeepAliveBridge(messenger: controller.binaryMessenger)
    setupDiskSpaceBridge(messenger: controller.binaryMessenger)
  }

  private func setupDiskSpaceBridge(messenger: FlutterBinaryMessenger) {
    if diskSpaceChannel != nil {
      return
    }
    let channel = FlutterMethodChannel(
      name: diskSpaceChannelName,
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handleDiskSpaceMethodCall(call, result: result)
    }
    diskSpaceChannel = channel
  }

  private func handleDiskSpaceMethodCall(
    _ call: FlutterMethodCall,
    result: @escaping FlutterResult
  ) {
    guard call.method == "getAvailableBytes" else {
      result(FlutterMethodNotImplemented)
      return
    }
    guard
      let arguments = call.arguments as? [String: Any],
      let path = arguments["path"] as? String,
      !path.isEmpty
    else {
      result(FlutterError(code: "bad_args", message: "path is required", details: nil))
      return
    }

    do {
      let url = URL(fileURLWithPath: path)
      if #available(iOS 11.0, *) {
        let values = try url.resourceValues(
          forKeys: [.volumeAvailableCapacityForImportantUsageKey]
        )
        if let capacity = values.volumeAvailableCapacityForImportantUsage {
          result(Int64(capacity))
          return
        }
      }
      let attributes = try FileManager.default.attributesOfFileSystem(forPath: path)
      if let freeSize = attributes[.systemFreeSize] as? NSNumber {
        result(freeSize.int64Value)
        return
      }
      result(FlutterError(
        code: "disk_space_unavailable",
        message: "free size unavailable",
        details: nil
      ))
    } catch {
      result(FlutterError(
        code: "disk_space_unavailable",
        message: String(describing: error),
        details: nil
      ))
    }
  }

  private func setupMigrationKeepAliveBridge(messenger: FlutterBinaryMessenger) {
    if migrationKeepAliveChannel != nil {
      return
    }
    let channel = FlutterMethodChannel(
      name: migrationKeepAliveChannelName,
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handleMigrationKeepAliveMethodCall(call, result: result)
    }
    migrationKeepAliveChannel = channel
  }

  private func handleMigrationKeepAliveMethodCall(
    _ call: FlutterMethodCall,
    result: @escaping FlutterResult
  ) {
    switch call.method {
    case "start":
      migrationKeepAliveActive = true
      beginMigrationBackgroundTaskIfNeeded(context: "keepalive_start")
      result(nil)
    case "stop":
      migrationKeepAliveActive = false
      endMigrationBackgroundTask(context: "keepalive_stop")
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func beginMigrationBackgroundTaskIfNeeded(context: String) {
    guard migrationKeepAliveActive, migrationBackgroundTask == .invalid else {
      return
    }
    migrationBackgroundTask = UIApplication.shared.beginBackgroundTask(
      withName: "mknoon_account_move"
    ) { [weak self] in
      // Expiration: iOS is about to suspend us regardless; release the
      // assertion so the app is not terminated for overrunning it.
      self?.endMigrationBackgroundTask(context: "expiration")
    }
    NSLog("[MIGRATION_KEEPALIVE] background task begun context=%@", context)
  }

  private func endMigrationBackgroundTask(context: String) {
    guard migrationBackgroundTask != .invalid else {
      return
    }
    UIApplication.shared.endBackgroundTask(migrationBackgroundTask)
    migrationBackgroundTask = .invalid
    NSLog("[MIGRATION_KEEPALIVE] background task ended context=%@", context)
  }

  override func applicationDidEnterBackground(_ application: UIApplication) {
    super.applicationDidEnterBackground(application)
    // Re-arm the assertion on every backgrounding while a transfer is live
    // (it is ended on foreground to avoid burning the background budget).
    beginMigrationBackgroundTaskIfNeeded(context: "did_enter_background")
  }

  override func applicationWillEnterForeground(_ application: UIApplication) {
    super.applicationWillEnterForeground(application)
    endMigrationBackgroundTask(context: "will_enter_foreground")
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
