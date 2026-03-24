import Flutter
import FirebaseMessaging
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
#if canImport(GoMknoon)
  private var goBridge: GoBridge?
#endif

  deinit {
    NotificationCenter.default.removeObserver(self)
  }

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self
    }
    let didFinish = super.application(application, didFinishLaunchingWithOptions: launchOptions)
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

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

#if canImport(GoMknoon)
    let messenger = engineBridge.applicationRegistrar.messenger()
    goBridge = GoBridge(messenger: messenger)
    NSLog("[GoBridge] Initialized via applicationRegistrar messenger")
#endif
  }

  @objc private func handleDidBecomeActiveNotification() {
    NSLog("[PUSH_DIAG] didBecomeActiveNotification")
    logNotificationSettings(context: "didBecomeActive")
    requestRemoteNotificationRegistration(reason: "didBecomeActive")
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
}
