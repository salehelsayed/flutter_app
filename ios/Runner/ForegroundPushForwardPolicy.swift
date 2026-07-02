import Foundation

/// 191 (Fix N1): the pure decision for whether an iOS foreground notification
/// (a `willPresent` callback) should be forwarded to the FCM plugin's published
/// `UNUserNotificationCenterDelegate` or handled by the existing super / FLN
/// path.
///
/// Background: under this app's UIScene adoption the firebase_messaging plugin's
/// launch wiring — which defers everything into a
/// `UIApplicationDidFinishLaunchingNotification` observer — never runs, so the
/// plugin is never in the engine's UN-callback fan-out and its `willPresent`
/// (the only path to `Messaging#onMessage` → Dart) is never invoked. AppDelegate
/// forwards FCM-shaped foreground notifications to the plugin explicitly; this
/// policy is the (pure, unit-lockable) gate for that forward. It deliberately
/// mirrors the plugin's own gate (`gcm.message_id` present) and the AppDelegate's
/// FLN-payload discriminator so a forward can never double-handle an FLN local
/// notification.
enum ForegroundPushForwardDecision: Equatable {
  /// Forward to the published FCM plugin delegate with the original completion.
  case forwardToFcmPlugin
  /// Fall through to `super` (the existing FLN / default presentation path).
  case superPath
}

enum ForegroundPushForwardPolicy {
  /// FCM-shaped: the notification carries the FCM message id the plugin keys on.
  static func isFcmShaped(_ userInfo: [AnyHashable: Any]) -> Bool {
    return userInfo["gcm.message_id"] != nil
  }

  /// FLN-shaped: a flutter_local_notifications payload (must NOT be forwarded —
  /// FLN owns its own presentation + tap handling via the engine chain).
  static func isFlnShaped(_ userInfo: [AnyHashable: Any]) -> Bool {
    return userInfo["NotificationId"] != nil || userInfo["payload"] != nil
  }

  /// The forward decision. Forward only when we actually hold a plugin ref, the
  /// notification is FCM-shaped, and it is NOT an FLN payload. Every other case
  /// (no ref → fail-safe to the 189 periodic-drain grid; FLN; non-FCM) takes the
  /// super path so behaviour is byte-identical to pre-191 for those inputs.
  static func decide(
    userInfo: [AnyHashable: Any],
    hasFcmPluginRef: Bool
  ) -> ForegroundPushForwardDecision {
    guard hasFcmPluginRef else {
      return .superPath
    }
    guard isFcmShaped(userInfo) else {
      return .superPath
    }
    guard !isFlnShaped(userInfo) else {
      return .superPath
    }
    return .forwardToFcmPlugin
  }
}
