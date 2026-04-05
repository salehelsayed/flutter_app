/// Abstract interface for showing local notifications.
abstract class NotificationService {
  /// Initialize the notification plugin and create channels.
  Future<void> initialize();

  /// Show a notification for an incoming message.
  Future<void> showMessageNotification({
    required String contactPeerId,
    required String senderUsername,
    required String messageText,
    String? payload,
  });

  /// Show a generic notification with a title, body, and optional payload.
  ///
  /// The [payload] string is passed to [onNotificationTap] when the user taps
  /// the notification, enabling deep-link navigation.
  Future<void> showNotification({
    required String title,
    required String body,
    String? payload,
  });

  /// Callback invoked when the user taps a notification.
  void Function(String payload)? onNotificationTap;

  /// Returns the launch payload if the app was opened from a local notification.
  Future<String?> consumeInitialPayload();

  /// Clears delivered notifications owned by the app.
  Future<void> clearDeliveredNotifications();

  /// Clean up resources.
  void dispose();
}
