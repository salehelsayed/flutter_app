/// Abstract interface for showing local notifications.
abstract class NotificationService {
  /// Initialize the notification plugin and create channels.
  Future<void> initialize();

  /// Show a notification for an incoming message.
  Future<void> showMessageNotification({
    required String contactPeerId,
    required String senderUsername,
    required String messageText,
  });

  /// Callback invoked when the user taps a notification.
  void Function(String contactPeerId)? onNotificationTap;

  /// Clean up resources.
  void dispose();
}
