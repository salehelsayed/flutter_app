import 'package:firebase_messaging/firebase_messaging.dart';

const backgroundPushDefaultTitle = 'New Message';
const backgroundPushDefaultBody = 'You have a new message';

class BackgroundPushNotificationFallback {
  final String title;
  final String body;
  final String? payload;

  const BackgroundPushNotificationFallback({
    required this.title,
    required this.body,
    this.payload,
  });
}

bool shouldShowBackgroundPushFallbackNotification(RemoteMessage message) {
  if (message.notification != null) return false;

  final type = _trimToNull(message.data['type']);
  return switch (type) {
    'new_message' => true,
    'group_message' => _trimToNull(message.data['groupId']) != null,
    'intros' => true,
    _ => _trimToNull(message.data['payload']) != null,
  };
}

BackgroundPushNotificationFallback buildBackgroundPushFallbackNotification(
  RemoteMessage message,
) {
  final payload = _payloadFromMessage(message);
  final title =
      _trimToNull(message.data['title']) ?? backgroundPushDefaultTitle;
  final body = _trimToNull(message.data['body']) ?? backgroundPushDefaultBody;

  return BackgroundPushNotificationFallback(
    title: title,
    body: body,
    payload: payload,
  );
}

String? _payloadFromMessage(RemoteMessage message) {
  final type = _trimToNull(message.data['type']);
  switch (type) {
    case 'new_message':
      return _trimToNull(message.data['from']);
    case 'group_message':
      final groupId = _trimToNull(message.data['groupId']);
      return groupId == null ? null : 'group:$groupId';
    case 'intros':
      return 'intros';
  }

  return _trimToNull(message.data['payload']) ??
      _trimToNull(message.data['route']);
}

String? _trimToNull(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  return trimmed;
}
