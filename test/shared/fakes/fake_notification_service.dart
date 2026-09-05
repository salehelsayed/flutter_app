import 'package:flutter_app/core/notifications/notification_service.dart';

/// Records notification calls for test assertions.
class FakeNotificationService implements NotificationService {
  final List<FakeNotification> shown = [];
  bool initialized = false;
  int clearedDeliveredNotificationsCount = 0;

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
    String? payload,
    bool silent = false,
    ConversationNotificationContentKind? contentKind,
    String? contentEventIdentity,
    ConversationNotificationSnapshot? snapshot,
  }) async {
    shown.add(
      FakeNotification(
        contactPeerId: contactPeerId,
        senderUsername: senderUsername,
        messageText: messageText,
        payload: payload ?? contactPeerId,
        silent: silent,
        contentKind: contentKind,
        contentEventIdentity: contentEventIdentity,
        snapshot: snapshot,
      ),
    );
  }

  @override
  Future<void> showNotification({
    required String title,
    required String body,
    String? payload,
    int? androidNotificationId,
    String? androidNotificationTag,
  }) async {
    shownGeneric.add(
      FakeGenericNotification(
        title: title,
        body: body,
        payload: payload,
        androidNotificationId: androidNotificationId,
        androidNotificationTag: androidNotificationTag,
      ),
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
  Future<void> clearDeliveredNotifications() async {
    clearedDeliveredNotificationsCount += 1;
  }

  @override
  Future<void> showMissedCallNotification({
    required String contactAccountPeerId,
    required String title,
    required String body,
  }) async {
    missedCallNotifications.add((
      contactAccountPeerId: contactAccountPeerId,
      title: title,
      body: body,
    ));
  }

  final missedCallNotifications =
      <({String contactAccountPeerId, String title, String body})>[];

  @override
  void dispose() {}
}

class FakeNotification {
  final String contactPeerId;
  final String senderUsername;
  final String messageText;
  final String payload;
  final bool silent;
  final ConversationNotificationContentKind? contentKind;
  final String? contentEventIdentity;
  final ConversationNotificationSnapshot? snapshot;

  const FakeNotification({
    required this.contactPeerId,
    required this.senderUsername,
    required this.messageText,
    required this.payload,
    this.silent = false,
    this.contentKind,
    this.contentEventIdentity,
    this.snapshot,
  });
}

class FakeGenericNotification {
  final String title;
  final String body;
  final String? payload;
  final int? androidNotificationId;
  final String? androidNotificationTag;

  const FakeGenericNotification({
    required this.title,
    required this.body,
    this.payload,
    this.androidNotificationId,
    this.androidNotificationTag,
  });
}
