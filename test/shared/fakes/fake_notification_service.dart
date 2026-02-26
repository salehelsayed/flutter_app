import 'package:flutter_app/core/notifications/notification_service.dart';

/// Records notification calls for test assertions.
class FakeNotificationService implements NotificationService {
  final List<FakeNotification> shown = [];
  bool initialized = false;

  @override
  void Function(String contactPeerId)? onNotificationTap;

  @override
  Future<void> initialize() async {
    initialized = true;
  }

  @override
  Future<void> showMessageNotification({
    required String contactPeerId,
    required String senderUsername,
    required String messageText,
  }) async {
    shown.add(FakeNotification(
      contactPeerId: contactPeerId,
      senderUsername: senderUsername,
      messageText: messageText,
    ));
  }

  @override
  void dispose() {}
}

class FakeNotification {
  final String contactPeerId;
  final String senderUsername;
  final String messageText;

  const FakeNotification({
    required this.contactPeerId,
    required this.senderUsername,
    required this.messageText,
  });
}
