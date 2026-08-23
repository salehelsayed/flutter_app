import Flutter
import FirebaseMessaging
import CoreFoundation
import os.log
import UIKit
import UserNotifications

private let groupMediaNativeProofLog = OSLog(
  subsystem: "com.mknoon.group-media-269",
  category: "native-proof"
)

func logGroupMediaNativeProof(_ message: String) {
  os_log("%{public}@", log: groupMediaNativeProofLog, type: .default, message)
}

struct NotificationResponseDiagnostic: Equatable {
  static let redactedValue = "<redacted>"
  static let emptyValue = "<empty>"

  let threadIdentifier: String
  let threadIdentifierState: String
  let threadMatchesRoute: String
  let categoryIdentifier: String
  let categoryIdentifierState: String

  static func evaluate(
    content: UNNotificationContent,
    userInfo: [AnyHashable: Any]
  ) -> NotificationResponseDiagnostic {
    let threadIdentifier = content.threadIdentifier
    let categoryIdentifier = content.categoryIdentifier
    let routeThreadIdentifier = nonEmptyString(userInfo["groupId"])
      ?? nonEmptyString(userInfo["sender_id"])
    let threadMatchesRoute: String
    if let routeThreadIdentifier {
      threadMatchesRoute = threadIdentifier == routeThreadIdentifier ? "true" : "false"
    } else {
      threadMatchesRoute = "unavailable"
    }

    return NotificationResponseDiagnostic(
      threadIdentifier: threadIdentifier.isEmpty ? emptyValue : redactedValue,
      threadIdentifierState: threadIdentifier.isEmpty ? "empty" : "present",
      threadMatchesRoute: threadMatchesRoute,
      categoryIdentifier: categoryIdentifier.isEmpty ? emptyValue : redactedValue,
      categoryIdentifierState: categoryIdentifier.isEmpty ? "empty" : "present"
    )
  }

  var logSummary: String {
    return "threadIdentifier=\(threadIdentifier) "
      + "threadIdentifierState=\(threadIdentifierState) "
      + "threadMatchesRoute=\(threadMatchesRoute) "
      + "categoryIdentifier=\(categoryIdentifier) "
      + "categoryIdentifierState=\(categoryIdentifierState)"
  }

  private static func nonEmptyString(_ value: Any?) -> String? {
    guard let string = value as? String, !string.isEmpty else {
      return nil
    }
    return string
  }
}

/// Resolves foreground custody from the delegate's actual presentation result.
/// The gate also protects Apple's completion from a misbehaving delegate that
/// calls it more than once.
final class IosNotificationForegroundDispositionGate {
  private let lock = NSLock()
  private var completed = false
  private let requestIdentifier: String
  private let onSuppressed: (String) -> Void
  private let completion: (UNNotificationPresentationOptions) -> Void

  init(
    requestIdentifier: String,
    onSuppressed: @escaping (String) -> Void,
    completion: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    self.requestIdentifier = requestIdentifier
    self.onSuppressed = onSuppressed
    self.completion = completion
  }

  func complete(with options: UNNotificationPresentationOptions) {
    lock.lock()
    guard !completed else {
      lock.unlock()
      return
    }
    completed = true
    lock.unlock()

    if options.isEmpty {
      onSuppressed(requestIdentifier)
    }
    completion(options)
  }
}

enum IosGroupNotificationFullHorizonResultCode: Equatable {
  case complete
  case unstableAtDeadline
}

struct IosGroupNotificationFullHorizonOutcome {
  let inventory: IosGroupNotificationInventory
  let stableSampleCount: Int
  let sampledThroughDeadline: Bool
  let badSourceSeen: Bool
  let duplicateSeen: Bool
  let resultCode: IosGroupNotificationFullHorizonResultCode
}

/// Group-only sampler that deliberately never completes on three early equal
/// samples. It remains alive through the 8-second horizon and latches any
/// matching local/sanitized/unknown source or duplicate seen along the way.
final class IosGroupNotificationFullHorizonSampler {
  typealias ScheduleAfter = (TimeInterval, @escaping () -> Void) -> Void
  typealias FetchInventory = (@escaping (IosGroupNotificationInventory) -> Void) -> Void

  private let now: () -> Date
  private let scheduleAfter: ScheduleAfter
  private let fetchInventory: FetchInventory
  private let lock = NSLock()
  private var completed = false
  private var completion: ((IosGroupNotificationFullHorizonOutcome) -> Void)?
  private var latestInventory = IosGroupNotificationInventory.empty
  private var latestStableSampleCount = 0
  private var badSourceSeen = false
  private var duplicateSeen = false

  init(
    now: @escaping () -> Date,
    scheduleAfter: @escaping ScheduleAfter,
    fetchInventory: @escaping FetchInventory
  ) {
    self.now = now
    self.scheduleAfter = scheduleAfter
    self.fetchInventory = fetchInventory
  }

  func start(
    deadline requestedDeadline: Date,
    completion: @escaping (IosGroupNotificationFullHorizonOutcome) -> Void
  ) {
    let startedAt = now()
    let maximumDeadline = startedAt.addingTimeInterval(
      Double(IosGroupNotificationInventory.observationDeadlineMilliseconds) / 1_000
    )
    let deadline = min(requestedDeadline, maximumDeadline)
    lock.lock()
    guard self.completion == nil, !completed else {
      lock.unlock()
      return
    }
    self.completion = completion
    lock.unlock()
    scheduleAfter(max(0, deadline.timeIntervalSince(startedAt))) { [self] in
      completeAtDeadline()
    }
    sample(deadline: deadline, previous: nil, consecutiveSampleCount: 0)
  }

  private func sample(
    deadline: Date,
    previous: IosGroupNotificationInventory?,
    consecutiveSampleCount: Int
  ) {
    guard isPending else { return }
    fetchInventory { [self] inventory in
      guard isPending else { return }
      let nextCount = previous == inventory ? consecutiveSampleCount + 1 : 1
      guard remember(inventory: inventory, stableSampleCount: nextCount) else {
        return
      }
      let interval =
        Double(IosGroupNotificationInventory.stableSampleIntervalMilliseconds) / 1_000
      let sampledAt = now()
      guard sampledAt.addingTimeInterval(interval) < deadline else { return }
      scheduleAfter(interval) { [self] in
        sample(
          deadline: deadline,
          previous: inventory,
          consecutiveSampleCount: nextCount
        )
      }
    }
  }

  private var isPending: Bool {
    lock.lock()
    defer { lock.unlock() }
    return !completed
  }

  private func remember(
    inventory: IosGroupNotificationInventory,
    stableSampleCount: Int
  ) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    guard !completed else { return false }
    latestInventory = inventory
    latestStableSampleCount = min(
      stableSampleCount,
      IosGroupNotificationInventory.stableSampleTarget
    )
    badSourceSeen = badSourceSeen
      || inventory.matchingLocalCount > 0
      || inventory.matchingSanitizedProviderCount > 0
      || inventory.matchingFlutterLocalCount > 0
      || inventory.matchingUnknownCount > 0
    duplicateSeen = duplicateSeen || inventory.matchingTotalCount > 1
    return true
  }

  private func completeAtDeadline() {
    lock.lock()
    guard !completed, let callback = completion else {
      lock.unlock()
      return
    }
    completed = true
    completion = nil
    let stable = min(
      latestStableSampleCount,
      IosGroupNotificationInventory.stableSampleTarget
    )
    let outcome = IosGroupNotificationFullHorizonOutcome(
      inventory: latestInventory,
      stableSampleCount: stable,
      sampledThroughDeadline: true,
      badSourceSeen: badSourceSeen,
      duplicateSeen: duplicateSeen,
      resultCode: stable == IosGroupNotificationInventory.stableSampleTarget
        ? .complete
        : .unstableAtDeadline
    )
    lock.unlock()
    callback(outcome)
  }
}

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
#if canImport(GoMknoon)
  private var goBridge: GoBridge?
#endif
  private let iosNotificationOpenChannelName = "mknoon/ios_notification_open"
  private var iosNotificationOpenChannel: FlutterMethodChannel?
  private let iosNotificationRecoveryChannelName =
    "mknoon/ios_notification_recovery"
  private var iosNotificationRecoveryChannel: FlutterMethodChannel?
  private lazy var iosNotificationRecoveryCoordinator =
    IosNotificationRecoveryCoordinator()
  private let iosAppVisibilityChannelName = "mknoon/app_visibility"
  private var iosAppVisibilityChannel: FlutterMethodChannel?
  private lazy var iosAppVisibilityCoordinator =
    IosAppVisibilityCoordinator()
  private var pendingIosNotificationOpen: [String: Any]?
  private var iosNotificationOpenBridgeReady = false
#if MKNOON_SIMS_IOS_RECEIVER_BOOTSTRAP
  private let iosReceiverBootstrapHandoff = IosReceiverBootstrapHandoff(enabled: true)
  private var iosReceiverBootstrapChannel: FlutterMethodChannel?
  private var iosNotificationRecoveryProofInFlight = false
#endif

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
  private let appGroupPathChannelName = "mknoon/app_group_path"
  private var appGroupPathChannel: FlutterMethodChannel?
  private var receivedMediaEgressCoordinator: ReceivedMediaEgressCoordinator?
  private var privateMediaProtectionCoordinator: PrivateMediaProtectionCoordinator?
  private var privateMediaImageViewFactory: PrivateMediaCaptureProtectedImageViewFactory?

  // 191 (Fix N1): the FCM plugin's published UNUserNotificationCenterDelegate,
  // captured at plugin-registration time (scene-connect). Under UIScene the
  // plugin's own launch wiring — deferred into a
  // UIApplicationDidFinishLaunchingNotification observer that never fires — never
  // registers it into the engine's UN-callback chain, so a foreground push never
  // reaches Dart's FirebaseMessaging.onMessage. We forward willPresent to this
  // instance explicitly (see userNotificationCenter(_:willPresent:...)). Nil is
  // a fail-safe: willPresent falls through to super → the 189 periodic-drain grid.
  private var fcmMessagingPluginDelegate: UNUserNotificationCenterDelegate?

  deinit {
    iosAppVisibilityCoordinator?.stop()
    NotificationCenter.default.removeObserver(self)
  }

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Install the cold-start invalidation before `super` can expose a Flutter
    // messenger. Native lifecycle is the durable generation owner; Dart may
    // publish only after observing the resulting generation.
    iosAppVisibilityCoordinator?.start()
#if MKNOON_SIMS_IOS_RECEIVER_BOOTSTRAP
    iosReceiverBootstrapHandoff.prepareContainer()
#endif
#if MKNOON_SIMS_IOS_RECEIVER_BOOTSTRAP || MKNOON_SIMS_GROUP_MEDIA_269
    logGroupMediaNativeProof(
      "MKNOON_269_IOS_NATIVE event=process_launch "
        + "pid=\(ProcessInfo.processInfo.processIdentifier)"
    )
#endif
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
#if MKNOON_SIMS_IOS_RECEIVER_BOOTSTRAP
    iosReceiverBootstrapHandoff.recordApnsDeviceToken(deviceToken)
#endif
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
    let userInfo = notification.request.content.userInfo
#if MKNOON_SIMS_IOS_RECEIVER_BOOTSTRAP
    if userInfo["mknoon_sims_recovery_sentinel"] as? Bool == true {
      if #available(iOS 14.0, *) {
        completionHandler([.banner, .list])
      } else {
        completionHandler([.alert])
      }
      return
    }
#endif
    let dispositionGate = IosNotificationForegroundDispositionGate(
      requestIdentifier: notification.request.identifier,
      onSuppressed: { [weak self] requestIdentifier in
        self?.iosNotificationRecoveryCoordinator?.markForegroundSuppressed(
          requestIdentifier: requestIdentifier
        )
      },
      completion: completionHandler
    )
    let recoveryCompletionHandler: (UNNotificationPresentationOptions) -> Void = {
      options in dispositionGate.complete(with: options)
    }
    logApnsProviderProbeNotification(context: "willPresent", userInfo: userInfo)

    // 191 (Fix N1): forward FCM-shaped foreground notifications to the FCM
    // plugin's published delegate so its willPresent → Messaging#onMessage →
    // Dart FirebaseMessaging.onMessage runs (the push-triggered inbox drain that
    // never fired under UIScene). The plugin gates on gcm.message_id, self-
    // dedupes via _foregroundUniqueIdentifier, and completes EXACTLY ONCE with
    // the persisted presentation options (0 — no banner). FLN payloads, non-FCM
    // notifications, and the nil-ref fail-safe all take super — byte-identical
    // to pre-191 (nil-ref degrades to the 189 periodic-drain grid). didReceive
    // is deliberately NOT forwarded (that would double-route taps — the 139 bug).
    let decision = ForegroundPushForwardPolicy.decide(
      userInfo: userInfo,
      hasFcmPluginRef: fcmMessagingPluginDelegate != nil
    )
    if decision == .forwardToFcmPlugin,
      let plugin = fcmMessagingPluginDelegate,
      plugin.responds(
        to: #selector(
          UNUserNotificationCenterDelegate.userNotificationCenter(
            _:willPresent:withCompletionHandler:))) {
      NSLog("[PUSH_DIAG] willPresent_forward_to_fcm_plugin")
      plugin.userNotificationCenter?(
        center,
        willPresent: notification,
        withCompletionHandler: recoveryCompletionHandler
      )
      return
    }

    NSLog(
      "[PUSH_DIAG] willPresent_super_path fcm_plugin_ref=%@ fcm_shaped=%@",
      fcmMessagingPluginDelegate != nil ? "present" : "nil",
      ForegroundPushForwardPolicy.isFcmShaped(userInfo) ? "true" : "false"
    )
    super.userNotificationCenter(
      center,
      willPresent: notification,
      withCompletionHandler: recoveryCompletionHandler
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
    let content = response.notification.request.content
    let userInfo = content.userInfo
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
#if DEBUG
    let responseDiagnostic = NotificationResponseDiagnostic.evaluate(
      content: content,
      userInfo: userInfo
    )
    NSLog(
      "[PUSH_DIAG] ios_native_un_content %@",
      responseDiagnostic.logSummary
    )
#endif
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
    captureFcmMessagingPluginDelegate(registry: engineBridge.pluginRegistry)
    installNotificationCenterDelegate(context: "after_implicit_engine_plugin_registration")
    let messenger = engineBridge.applicationRegistrar.messenger()
    let privateMediaImageViewFactory = PrivateMediaCaptureProtectedImageViewFactory(
      messenger: messenger
    )
    engineBridge.applicationRegistrar.register(
      privateMediaImageViewFactory,
      withId: PrivateMediaCaptureProtectedImageViewFactory.viewType
    )
    self.privateMediaImageViewFactory = privateMediaImageViewFactory
    setupIosNotificationOpenBridge(messenger: messenger)
#if MKNOON_SIMS_IOS_RECEIVER_BOOTSTRAP
    setupIosReceiverBootstrapBridge(messenger: messenger)
#endif
    setupIosNotificationRecoveryBridge(messenger: messenger)
    setupIosAppVisibilityBridge(messenger: messenger)
    setupMigrationKeepAliveBridge(messenger: messenger)
    setupDiskSpaceBridge(messenger: messenger)
    setupAppGroupPathBridge(messenger: messenger)
    receivedMediaEgressCoordinator = ReceivedMediaEgressCoordinator(messenger: messenger)
    setupPrivateMediaProtectionBridge(messenger: messenger)

#if canImport(GoMknoon)
    goBridge = GoBridge(messenger: messenger)
    NSLog("[GoBridge] Initialized via applicationRegistrar messenger")
#endif
  }

  // 191 (Fix N1): capture the FCM plugin's published UNUserNotificationCenterDelegate.
  // The plugin publishes its instance (`[registrar publish:instance]`) under the
  // registrar key GeneratedPluginRegistrant uses
  // (`registrarForPlugin:@"FLTFirebaseMessagingPlugin"`), so it is retrievable via
  // the public `valuePublished(byPlugin:)` surface — no pod-header import needed.
  // If the key ever drifts (plugin upgrade), the ref is nil and willPresent
  // fails safe to super; the diag below makes that observable on-device.
  private func captureFcmMessagingPluginDelegate(registry: FlutterPluginRegistry) {
    let published = registry.valuePublished(byPlugin: "FLTFirebaseMessagingPlugin")
    if let delegate = published as? UNUserNotificationCenterDelegate {
      fcmMessagingPluginDelegate = delegate
      NSLog(
        "[PUSH_DIAG] fcm_plugin_ref found class=%@",
        String(describing: type(of: delegate))
      )
    } else {
      NSLog(
        "[PUSH_DIAG] fcm_plugin_ref nil published=%@",
        String(describing: published)
      )
    }
  }

  @objc private func handleDidBecomeActiveNotification() {
    NSLog("[PUSH_DIAG] didBecomeActiveNotification")
    installNotificationCenterDelegate(context: "didBecomeActive")
    logNotificationSettings(context: "didBecomeActive")
    requestRemoteNotificationRegistration(reason: "didBecomeActive")
#if MKNOON_SIMS_IOS_RECEIVER_BOOTSTRAP
    processPendingIosNotificationRecoveryProof()
#endif
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
        "MKNOON_APNS_PROVIDER_PROBE_NATIVE event=fcm_token_ready context=%@ length=%d",
        context,
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

#if MKNOON_SIMS_IOS_RECEIVER_BOOTSTRAP
  private func setupIosReceiverBootstrapBridge(messenger: FlutterBinaryMessenger) {
    if iosReceiverBootstrapChannel != nil {
      return
    }
    let channel = FlutterMethodChannel(
      name: "mknoon/sims_ios_receiver_bootstrap",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "publishTransportPeerId":
        guard
          let arguments = call.arguments as? [String: Any],
          let peerDeviceId = arguments["peerDeviceId"] as? String,
          let mlKemPublicKey = arguments["mlKemPublicKey"] as? String
        else {
          result(FlutterError(code: "bad_args", message: nil, details: nil))
          return
        }
        let outcome = self?.iosReceiverBootstrapHandoff.recordTransportIdentity(
          peerId: peerDeviceId,
          mlKemPublicKey: mlKemPublicKey
        )
        switch outcome {
        case .published:
          result(["status": "published"])
        case .waiting:
          result(["status": "waiting"])
        case .cleaned:
          result(["status": "cleaned"])
        case .rejected, .none:
          result(FlutterError(code: "handoff_rejected", message: nil, details: nil))
        }
      case "takeSenderProjectionRequest":
        result(self?.iosReceiverBootstrapHandoff.takeSenderProjectionRequest())
      case "completeSenderProjectionRequest":
        guard
          let arguments = call.arguments as? [String: Any],
          let captureNonce = arguments["captureNonce"] as? String,
          let action = arguments["action"] as? String,
          let apnsPayloadSha256 = arguments["apnsPayloadSha256"] as? String,
          let fixtureDigest = arguments["fixtureDigest"] as? String,
          let status = arguments["status"] as? String,
          let resultCode = arguments["resultCode"] as? String,
          self?.iosReceiverBootstrapHandoff.completeSenderProjectionRequest(
            captureNonce: captureNonce,
            action: action,
            apnsPayloadSha256: apnsPayloadSha256,
            fixtureDigest: fixtureDigest,
            status: status,
            resultCode: resultCode
          ) == true
        else {
          result(FlutterError(code: "sender_fixture_rejected", message: nil, details: nil))
          return
        }
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    iosReceiverBootstrapChannel = channel
    processPendingIosNotificationRecoveryProof()
  }

  private func processPendingIosNotificationRecoveryProof() {
    if processPendingIosGroupNotificationObservation() { return }
    guard
      !iosNotificationRecoveryProofInFlight,
      let request = iosReceiverBootstrapHandoff.takeNotificationRecoveryRequest()
    else { return }
    iosNotificationRecoveryProofInFlight = true
    let center = UNUserNotificationCenter.current()
    center.getDeliveredNotifications { [weak self] notifications in
      guard let self else { return }
      let before = Set(notifications.map(\.request.identifier))
      let badgeBefore = UIApplication.shared.applicationIconBadgeNumber
      let deliveredNotificationBadgeWasNil =
        notifications.count == 1 && notifications[0].request.content.badge == nil
      guard
        before.count == 1,
        badgeBefore == 1,
        deliveredNotificationBadgeWasNil,
        let sentinelIdentifier = request["sentinelIdentifier"],
        let accountPeerId = request["accountPeerId"]
      else {
        self.finishIosNotificationRecoveryProof(
          request: request,
          status: "failed",
          resultCode: "unexpected_initial_state",
          badgeBefore: max(0, badgeBefore),
          badgeAfter: max(0, badgeBefore),
          deliveredBefore: before.count,
          deliveredWithSentinel: before.count,
          deliveredAfter: before.count,
          deliveredNotificationBadgeWasNil: deliveredNotificationBadgeWasNil,
          sentinelSurvived: false,
          removedExactOwnedNotification: false
        )
        return
      }

      let content = UNMutableNotificationContent()
      content.title = "Mknoon recovery sentinel"
      content.body = "Unrelated notification preservation"
      content.badge = nil
      content.userInfo = ["mknoon_sims_recovery_sentinel": true]
      let sentinel = UNNotificationRequest(
        identifier: sentinelIdentifier,
        content: content,
        trigger: nil
      )
      center.add(sentinel) { [weak self] error in
        guard let self else { return }
        guard error == nil else {
          self.finishIosNotificationRecoveryProof(
            request: request,
            status: "failed",
            resultCode: "sentinel_delivery_failed",
            badgeBefore: badgeBefore,
            badgeAfter: UIApplication.shared.applicationIconBadgeNumber,
            deliveredBefore: before.count,
            deliveredWithSentinel: before.count,
            deliveredAfter: before.count,
            deliveredNotificationBadgeWasNil: deliveredNotificationBadgeWasNil,
            sentinelSurvived: false,
            removedExactOwnedNotification: false
          )
          return
        }
        self.waitForIosDeliveredIdentifiers(
          deadline: Date().addingTimeInterval(10),
          predicate: { identifiers in
            identifiers.count == 2 && identifiers.contains(sentinelIdentifier)
          }
        ) { identifiersWithSentinel in
          guard
            identifiersWithSentinel.count == 2,
            identifiersWithSentinel.contains(sentinelIdentifier),
            let coordinator = self.iosNotificationRecoveryCoordinator,
            let begin = coordinator.beginReconciliation(accountPeerId: accountPeerId)
          else {
            self.finishIosNotificationRecoveryProof(
              request: request,
              status: "failed",
              resultCode: "sentinel_not_observed",
              badgeBefore: badgeBefore,
              badgeAfter: UIApplication.shared.applicationIconBadgeNumber,
              deliveredBefore: before.count,
              deliveredWithSentinel: identifiersWithSentinel.count,
              deliveredAfter: identifiersWithSentinel.count,
              deliveredNotificationBadgeWasNil: deliveredNotificationBadgeWasNil,
              sentinelSurvived: identifiersWithSentinel.contains(sentinelIdentifier),
              removedExactOwnedNotification: false
            )
            return
          }
          coordinator.commitReconciliation(
            token: begin.token,
            watermark: begin.watermark,
            accountPeerId: accountPeerId,
            canonicalStateComplete: true,
            canonicalBadgeCount: 0,
            identities: []
          ) { committed in
            guard committed else {
              self.finishIosNotificationRecoveryProof(
                request: request,
                status: "failed",
                resultCode: "reconciliation_rejected",
                badgeBefore: badgeBefore,
                badgeAfter: UIApplication.shared.applicationIconBadgeNumber,
                deliveredBefore: before.count,
                deliveredWithSentinel: identifiersWithSentinel.count,
                deliveredAfter: identifiersWithSentinel.count,
                deliveredNotificationBadgeWasNil: deliveredNotificationBadgeWasNil,
                sentinelSurvived: identifiersWithSentinel.contains(sentinelIdentifier),
                removedExactOwnedNotification: false
              )
              return
            }
            self.waitForIosDeliveredIdentifiers(
              deadline: Date().addingTimeInterval(10),
              predicate: { identifiers in
                identifiers == Set([sentinelIdentifier])
                  && UIApplication.shared.applicationIconBadgeNumber == 0
              }
            ) { remaining in
              let sentinelSurvived = remaining == Set([sentinelIdentifier])
              let badgeAfter = UIApplication.shared.applicationIconBadgeNumber
              self.finishIosNotificationRecoveryProof(
                request: request,
                status: sentinelSurvived && badgeAfter == 0 ? "passed" : "failed",
                resultCode: sentinelSurvived && badgeAfter == 0
                  ? "ok"
                  : "retirement_incomplete",
                badgeBefore: badgeBefore,
                badgeAfter: max(0, badgeAfter),
                deliveredBefore: before.count,
                deliveredWithSentinel: identifiersWithSentinel.count,
                deliveredAfter: remaining.count,
                deliveredNotificationBadgeWasNil: deliveredNotificationBadgeWasNil,
                sentinelSurvived: sentinelSurvived,
                removedExactOwnedNotification:
                  before.count == 1
                    && identifiersWithSentinel.count == 2
                    && remaining.count == 1
              )
            }
          }
        }
      }
    }
  }

  @discardableResult
  private func processPendingIosGroupNotificationObservation() -> Bool {
    guard
      !iosNotificationRecoveryProofInFlight,
      let request = iosReceiverBootstrapHandoff
        .takeGroupNotificationObservationRequest(),
      let phaseText = request["phase"],
      let phase = IosGroupNotificationPhase(rawValue: phaseText),
      let groupHash = request["expectedGroupIdSha256"],
      let eventHash = request["expectedEventIdSha256"],
      let targetHash = request["expectedTargetMessageIdSha256"]
    else { return false }
    iosNotificationRecoveryProofInFlight = true
    let expected = IosGroupNotificationExpectedHashes(
      phase: phase,
      groupIdSha256: groupHash,
      eventIdSha256: eventHash,
      targetMessageIdSha256: targetHash
    )
    waitForFullHorizonIosGroupInventory(
      expected: expected,
      deadline: Date().addingTimeInterval(
        Double(IosGroupNotificationInventory.observationDeadlineMilliseconds) / 1_000
      )
    ) { [weak self] outcome in
      guard let self else { return }
      let inventory = outcome.inventory
      let exactUsefulSource =
        outcome.resultCode == .complete
          && outcome.sampledThroughDeadline
          && outcome.stableSampleCount
            == IosGroupNotificationInventory.stableSampleTarget
          && !outcome.badSourceSeen
          && !outcome.duplicateSeen
          && inventory.matchingRemoteCount == 1
          && inventory.matchingLocalCount == 0
          && inventory.matchingUsefulProviderCount == 1
          && inventory.matchingSanitizedProviderCount == 0
          && inventory.matchingFlutterLocalCount == 0
          && inventory.matchingUnknownCount == 0
          && inventory.matchingTotalCount == 1
      let resultCode: String
      if exactUsefulSource {
        resultCode = "ok"
      } else if outcome.resultCode == .unstableAtDeadline {
        resultCode = "source_inventory_unstable"
      } else if outcome.badSourceSeen {
        resultCode = "bad_source_seen"
      } else if outcome.duplicateSeen {
        resultCode = "duplicate_seen"
      } else {
        resultCode = "source_inventory_mismatch"
      }
      _ = self.iosReceiverBootstrapHandoff
        .completeGroupNotificationObservationRequest(
          request: request,
          status: exactUsefulSource ? "passed" : "failed",
          resultCode: resultCode,
          inventory: inventory,
          stableSampleCount: outcome.stableSampleCount,
          sampledThroughDeadline: outcome.sampledThroughDeadline,
          badSourceSeen: outcome.badSourceSeen,
          duplicateSeen: outcome.duplicateSeen
        )
      // Intentionally do not release iosNotificationRecoveryProofInFlight.
      // The host must pull the protected receipt and terminate Runner before
      // SpringBoard tap routing; a cleanup relaunch would consume the card.
    }
    return true
  }

  private func waitForIosDeliveredIdentifiers(
    deadline: Date,
    predicate: @escaping (Set<String>) -> Bool,
    completion: @escaping (Set<String>) -> Void
  ) {
    UNUserNotificationCenter.current().getDeliveredNotifications { [weak self] notifications in
      guard let self else { return }
      let identifiers = Set(notifications.map(\.request.identifier))
      guard !predicate(identifiers), Date() < deadline else {
        completion(identifiers)
        return
      }
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
        self.waitForIosDeliveredIdentifiers(
          deadline: deadline,
          predicate: predicate,
          completion: completion
        )
      }
    }
  }

  private func waitForFullHorizonIosGroupInventory(
    expected: IosGroupNotificationExpectedHashes,
    deadline: Date,
    completion: @escaping (IosGroupNotificationFullHorizonOutcome) -> Void
  ) {
    let center = UNUserNotificationCenter.current()
    let sampler = IosGroupNotificationFullHorizonSampler(
      now: Date.init,
      scheduleAfter: { delay, action in
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, delay)) {
          action()
        }
      },
      fetchInventory: { callback in
        center.getDeliveredNotifications { notifications in
          callback(
            IosGroupNotificationInventory.project(
              notifications,
              expected: expected
            )
          )
        }
      }
    )
    sampler.start(deadline: deadline, completion: completion)
  }

  private func finishIosNotificationRecoveryProof(
    request: [String: String],
    status: String,
    resultCode: String,
    badgeBefore: Int,
    badgeAfter: Int,
    deliveredBefore: Int,
    deliveredWithSentinel: Int,
    deliveredAfter: Int,
    deliveredNotificationBadgeWasNil: Bool,
    sentinelSurvived: Bool,
    removedExactOwnedNotification: Bool
  ) {
    _ = iosReceiverBootstrapHandoff.completeNotificationRecoveryRequest(
      request: request,
      status: status,
      resultCode: resultCode,
      badgeBefore: badgeBefore,
      badgeAfter: badgeAfter,
      deliveredBefore: deliveredBefore,
      deliveredWithSentinel: deliveredWithSentinel,
      deliveredAfter: deliveredAfter,
      deliveredNotificationBadgeWasNil: deliveredNotificationBadgeWasNil,
      sentinelSurvived: sentinelSurvived,
      removedExactOwnedNotification: removedExactOwnedNotification
    )
    iosNotificationRecoveryProofInFlight = false
  }
#endif

  private func logNotificationSettings(context: String) {
    UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
#if MKNOON_SIMS_IOS_RECEIVER_BOOTSTRAP
      let authorization: String
      switch settings.authorizationStatus {
      case .authorized:
        authorization = "authorized"
      case .provisional:
        authorization = "provisional"
      case .ephemeral:
        authorization = "ephemeral"
      case .denied:
        authorization = "denied"
      case .notDetermined:
        authorization = "not_determined"
      @unknown default:
        authorization = "not_determined"
      }
      let alertSetting: String
      switch settings.alertSetting {
      case .enabled:
        alertSetting = "enabled"
      case .disabled:
        alertSetting = "disabled"
      case .notSupported:
        alertSetting = "not_supported"
      @unknown default:
        alertSetting = "not_supported"
      }
      let badgeSetting: String
      switch settings.badgeSetting {
      case .enabled:
        badgeSetting = "enabled"
      case .disabled:
        badgeSetting = "disabled"
      case .notSupported:
        badgeSetting = "not_supported"
      @unknown default:
        badgeSetting = "not_supported"
      }
      DispatchQueue.main.async { [weak self] in
        self?.iosReceiverBootstrapHandoff.recordNotificationSettings(
          authorization: authorization,
          alertSetting: alertSetting,
          badgeSetting: badgeSetting
        )
      }
#endif
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
    setupIosNotificationRecoveryBridge(messenger: controller.binaryMessenger)
    setupIosAppVisibilityBridge(messenger: controller.binaryMessenger)
    setupMigrationKeepAliveBridge(messenger: controller.binaryMessenger)
    setupDiskSpaceBridge(messenger: controller.binaryMessenger)
    setupAppGroupPathBridge(messenger: controller.binaryMessenger)
    setupPrivateMediaProtectionBridge(messenger: controller.binaryMessenger)
  }

  private func setupPrivateMediaProtectionBridge(messenger: FlutterBinaryMessenger) {
    guard privateMediaProtectionCoordinator == nil else { return }
    privateMediaProtectionCoordinator = PrivateMediaProtectionCoordinator(messenger: messenger)
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

  // 04-P0 SI-5: expose the shared app-group container path to Dart so the
  // RecentRemoteNotificationGate can read the NSE's cross-process dedupe markers.
  private func setupAppGroupPathBridge(messenger: FlutterBinaryMessenger) {
    if appGroupPathChannel != nil {
      return
    }
    let channel = FlutterMethodChannel(
      name: appGroupPathChannelName,
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { call, result in
      guard call.method == "appGroupContainerPath" else {
        result(FlutterMethodNotImplemented)
        return
      }
#if MKNOON_SIMS_GROUP_MEDIA_269
      // The disposable TC-269 app is signed without app-group entitlements.
      // Fail before evaluating the production app-group identifier so this
      // build cannot touch production shared state even if Dart calls through.
      result(FlutterError(
        code: "app_group_unavailable",
        message: "shared app-group access is disabled for this build",
        details: nil
      ))
#else
      // Must match mknoonSharedAppGroupIdentifier in the NotificationService
      // target (a different module, so the literal is repeated here).
      guard let path = FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: "group.com.mknoon.app.share"
      )?.path else {
        result(FlutterError(
          code: "app_group_unavailable",
          message: "shared app-group container is unavailable",
          details: nil
        ))
        return
      }
      result(path)
#endif
    }
    appGroupPathChannel = channel
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
#if MKNOON_SIMS_IOS_RECEIVER_BOOTSTRAP || MKNOON_SIMS_GROUP_MEDIA_269
    logGroupMediaNativeProof(
      "MKNOON_269_IOS_NATIVE event=app_did_enter_background "
        + "pid=\(ProcessInfo.processInfo.processIdentifier)"
    )
#endif
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

  private func setupIosNotificationRecoveryBridge(
    messenger: FlutterBinaryMessenger
  ) {
    if iosNotificationRecoveryChannel != nil { return }
    let channel = FlutterMethodChannel(
      name: iosNotificationRecoveryChannelName,
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handleIosNotificationRecoveryMethodCall(call, result: result)
    }
    iosNotificationRecoveryChannel = channel
    NSLog("[PUSH_DIAG] ios_notification_recovery_bridge_setup")
  }

  private func setupIosAppVisibilityBridge(
    messenger: FlutterBinaryMessenger
  ) {
    if iosAppVisibilityChannel != nil { return }
    let channel = FlutterMethodChannel(
      name: iosAppVisibilityChannelName,
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handleIosAppVisibilityMethodCall(call, result: result)
    }
    iosAppVisibilityChannel = channel
  }

  private func handleIosAppVisibilityMethodCall(
    _ call: FlutterMethodCall,
    result: @escaping FlutterResult
  ) {
    switch call.method {
    case "readSnapshot":
      guard call.arguments == nil || call.arguments is NSNull else {
        result(FlutterError(
          code: "app_visibility_bad_args",
          message: "readSnapshot accepts null arguments",
          details: nil
        ))
        return
      }
      result(iosAppVisibilityCoordinator?.readSnapshot()?.methodChannelMap)
    case "publishVisibleConversation":
      guard let arguments = call.arguments as? [String: Any],
            arguments.keys.contains("visibleConversationDigest"),
            arguments.keys.contains("lifecycleGeneration"),
            arguments.count == 2,
            let lifecycleGeneration = appVisibilityInt64(
              arguments["lifecycleGeneration"]
            ),
            lifecycleGeneration > 0
      else {
        result(FlutterError(
          code: "app_visibility_bad_args",
          message: "publishVisibleConversation requires the exact visibility CAS arguments",
          details: nil
        ))
        return
      }
      let digestValue = arguments["visibleConversationDigest"]
      let digest: String?
      if digestValue == nil || digestValue is NSNull {
        digest = nil
      } else if let value = digestValue as? String,
                IosAppVisibilityDigest.isCanonicalDigest(value) {
        digest = value
      } else {
        result(FlutterError(
          code: "app_visibility_bad_args",
          message: "visibleConversationDigest must be null or lowercase SHA-256",
          details: nil
        ))
        return
      }
      let publication = iosAppVisibilityCoordinator?
        .publishVisibleConversation(
          digest: digest,
          lifecycleGeneration: lifecycleGeneration
        ) ?? IosAppVisibilityPublishResult(
          committed: false,
          snapshot: nil,
          context: nil
        )
      result(publication.methodChannelMap)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func appVisibilityInt64(_ raw: Any?) -> Int64? {
    guard let number = raw as? NSNumber,
          CFGetTypeID(number) != CFBooleanGetTypeID()
    else {
      return nil
    }
    return Int64(number.stringValue)
  }

  private func handleIosNotificationRecoveryMethodCall(
    _ call: FlutterMethodCall,
    result: @escaping FlutterResult
  ) {
#if MKNOON_SIMS_IOS_RECEIVER_BOOTSTRAP
    guard !iosNotificationRecoveryProofInFlight else {
      result(
        FlutterError(
          code: "notification_recovery_proof_in_flight",
          message: nil,
          details: nil
        )
      )
      return
    }
#endif
    guard let coordinator = iosNotificationRecoveryCoordinator else {
      result(FlutterError(
        code: "notification_recovery_unavailable",
        message: "shared notification recovery state is unavailable",
        details: nil
      ))
      return
    }

    switch call.method {
    case "beginReconciliation":
      guard let arguments = recoveryArguments(
              call.arguments,
              keys: ["accountPeerId"]
            ),
            let accountPeerId = nonEmptyRecoveryString(
              arguments["accountPeerId"]
            ),
            let begin = coordinator.beginReconciliation(
              accountPeerId: accountPeerId
            ),
            begin.watermark <= UInt64(Int64.max) else {
        result(recoveryFlutterError(code: "begin_rejected"))
        return
      }
      result([
        "token": begin.token,
        "watermark": Int64(begin.watermark),
        "mailboxAlertLease": begin.mailboxAlertLease?.methodChannelMap
          ?? NSNull(),
      ])

    case "consumeMailboxAlertLease":
      guard let arguments = recoveryArguments(
              call.arguments,
              keys: ["token", "watermark", "generation", "sequence"]
            ),
            let token = nonEmptyRecoveryString(arguments["token"]),
            let watermark = recoveryUInt64(arguments["watermark"]),
            let generation = recoveryUInt64(arguments["generation"]),
            generation > 0,
            let sequence = recoveryUInt64(arguments["sequence"]),
            sequence > 0 else {
        result(recoveryFlutterError(code: "bad_args"))
        return
      }
      guard coordinator.consumeMailboxAlertLease(
        token: token,
        watermark: watermark,
        generation: generation,
        sequence: sequence
      ) else {
        result(recoveryFlutterError(code: "consume_lease_rejected"))
        return
      }
      result(["ok": true])

    case "commitReconciliation":
      guard let arguments = recoveryArguments(
              call.arguments,
              keys: [
                "token",
                "watermark",
                "accountPeerId",
                "canonicalStateComplete",
                "canonicalBadgeCount",
                "identities",
              ]
            ),
            let token = nonEmptyRecoveryString(arguments["token"]),
            let accountPeerId = nonEmptyRecoveryString(
              arguments["accountPeerId"]
            ),
            let watermark = recoveryUInt64(arguments["watermark"]),
            let canonicalStateComplete = recoveryBool(
              arguments["canonicalStateComplete"]
            ),
            let canonicalBadgeCount = recoveryNonnegativeInt(
              arguments["canonicalBadgeCount"]
            ),
            let rawIdentities = arguments["identities"] as? [[String: Any]],
            let identities = parseCanonicalRecoveryIdentities(rawIdentities)
      else {
        result(recoveryFlutterError(code: "bad_args"))
        return
      }
      coordinator.commitReconciliation(
        token: token,
        watermark: watermark,
        accountPeerId: accountPeerId,
        canonicalStateComplete: canonicalStateComplete,
        canonicalBadgeCount: canonicalBadgeCount,
        identities: identities
      ) { ok in
        DispatchQueue.main.async {
          if ok {
            result(["ok": true])
          } else {
            result(self.recoveryFlutterError(code: "commit_rejected"))
          }
        }
      }

    case "retireConversation":
      guard let arguments = recoveryArguments(
              call.arguments,
              keys: ["accountPeerId", "lane", "conversationId"]
            ),
            let accountPeerId = nonEmptyRecoveryString(
              arguments["accountPeerId"]
            ),
            let rawLane = nonEmptyRecoveryString(arguments["lane"]),
            let lane = IosNotificationRecoveryLane(rawValue: rawLane),
            let conversationId = nonEmptyRecoveryString(
              arguments["conversationId"]
            ) else {
        result(recoveryFlutterError(code: "bad_args"))
        return
      }
      coordinator.retireConversation(
        accountPeerId: accountPeerId,
        lane: lane,
        conversationId: conversationId
      ) { ok in
        DispatchQueue.main.async {
          if ok {
            result(["ok": true])
          } else {
            result(self.recoveryFlutterError(code: "retire_rejected"))
          }
        }
      }

    case "retireGroupInvite":
      guard let arguments = recoveryArguments(
              call.arguments,
              keys: ["groupId", "inviteId"]
            ),
            let groupId = nonEmptyRecoveryString(arguments["groupId"]),
            let inviteId = nonEmptyRecoveryString(arguments["inviteId"])
      else {
        result(recoveryFlutterError(code: "bad_args"))
        return
      }
      coordinator.retireGroupInvite(
        groupId: groupId,
        inviteId: inviteId
      ) { ok in
        DispatchQueue.main.async {
          if ok {
            result(["ok": true])
          } else {
            result(self.recoveryFlutterError(
              code: "retire_group_invite_rejected"
            ))
          }
        }
      }

    case "clearAccount":
      guard let arguments = recoveryArguments(call.arguments, keys: []),
            arguments.isEmpty else {
        result(recoveryFlutterError(code: "bad_args"))
        return
      }
      coordinator.clearAccount { ok in
        DispatchQueue.main.async {
          if ok {
            result(["ok": true])
          } else {
            result(self.recoveryFlutterError(code: "clear_rejected"))
          }
        }
      }

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func parseCanonicalRecoveryIdentities(
    _ values: [[String: Any]]
  ) -> [IosNotificationCanonicalIdentity]? {
    var identities: [IosNotificationCanonicalIdentity] = []
    identities.reserveCapacity(values.count)
    for value in values {
      guard Set(value.keys) == ["lane", "conversationId", "eventId"],
            let rawLane = nonEmptyRecoveryString(value["lane"]),
            let lane = IosNotificationRecoveryLane(rawValue: rawLane),
            let conversationId = nonEmptyRecoveryString(
              value["conversationId"]
            ),
            let eventId = nonEmptyRecoveryString(value["eventId"]) else {
        return nil
      }
      identities.append(IosNotificationCanonicalIdentity(
        lane: lane,
        conversationId: conversationId,
        eventId: eventId
      ))
    }
    return identities
  }

  private func nonEmptyRecoveryString(_ value: Any?) -> String? {
    guard let value = value as? String, !value.isEmpty else { return nil }
    return value
  }

  private func recoveryArguments(
    _ value: Any?,
    keys: Set<String>
  ) -> [String: Any]? {
    guard let arguments = value as? [String: Any],
          Set(arguments.keys) == keys else {
      return nil
    }
    return arguments
  }

  private func recoveryBool(_ value: Any?) -> Bool? {
    guard let number = value as? NSNumber,
          CFGetTypeID(number) == CFBooleanGetTypeID() else {
      return nil
    }
    return number.boolValue
  }

  private func recoveryInteger(_ value: Any?) -> NSNumber? {
    guard let number = value as? NSNumber,
          CFGetTypeID(number) != CFBooleanGetTypeID(),
          !CFNumberIsFloatType(number) else {
      return nil
    }
    return number
  }

  private func recoveryUInt64(_ value: Any?) -> UInt64? {
    guard let number = recoveryInteger(value), number.int64Value >= 0 else {
      return nil
    }
    return UInt64(number.int64Value)
  }

  private func recoveryNonnegativeInt(_ value: Any?) -> Int? {
    guard let number = recoveryInteger(value),
          number.int64Value >= 0,
          number.int64Value <= Int64(Int.max) else {
      return nil
    }
    return Int(number.int64Value)
  }

  private func recoveryFlutterError(code: String) -> FlutterError {
    FlutterError(code: code, message: nil, details: nil)
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
    case "consumeInitialNotificationOpenAndMarkReady":
      // This MethodChannel handler runs on the main thread with notification
      // delegate delivery. Capture and clear the launch response while warm
      // forwarding is still disabled, then arm warm forwarding atomically.
      // No didReceive(response) callback can be reclassified between these
      // operations.
      let payload = pendingIosNotificationOpen
      pendingIosNotificationOpen = nil
      iosNotificationOpenBridgeReady = true
      NSLog("[PUSH_DIAG] ios_notification_open_bridge_ready")
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
    case "group_reaction":
      let groupId = trimmedString(payload["groupId"])
      let eventId = trimmedString(payload["event_id"])
      let targetMessageId = trimmedString(payload["target_message_id"])
      let reactorPeerId = trimmedString(payload["reactor_peer_id"])
      return groupId != nil &&
        eventId != nil &&
        targetMessageId != nil &&
        reactorPeerId != nil &&
        trimmedString(payload["action"]) == "add"
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
