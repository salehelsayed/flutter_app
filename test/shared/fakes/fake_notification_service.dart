import 'package:flutter_app/core/notifications/notification_service.dart';

/// Records notification calls for test assertions.
class FakeNotificationService implements NotificationService {
  final List<FakeNotification> shown = [];
  bool initialized = false;

  @override
  void Function(String payload)? onNotificationTap;

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
    shown.add(
      FakeNotification(
        contactPeerId: contactPeerId,
        senderUsername: senderUsername,
        messageText: messageText,
      ),
    );
  }

  @override
  Future<void> showNotification({
    required String title,
    required String body,
    String? payload,
  }) async {
    shownGeneric.add(
      FakeGenericNotification(title: title, body: body, payload: payload),
    );
  }

  final List<FakeGenericNotification> shownGeneric = [];

  String? initialPayload;

  @override
  Future<String?> consumeInitialPayload() async {
    final payload = initialPayload;
    initialPayload = null;
    return payload;
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

class FakeGenericNotification {
  final String title;
  final String body;
  final String? payload;

  const FakeGenericNotification({
    required this.title,
    required this.body,
    this.payload,
  });
}
