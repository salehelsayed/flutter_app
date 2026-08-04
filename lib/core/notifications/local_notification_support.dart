import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_app/core/notifications/notification_service.dart';

const mknoonMessagesChannelId = 'mknoon_messages';
const mknoonMessagesChannelName = 'Messages';
const mknoonMessagesChannelDescription = 'Incoming message notifications';

// 118 Phase 3: a separate, low-importance SILENT channel. An Android channel's
// sound is immutable after `createNotificationChannel`, so a no-sound variant
// requires a distinct channel id rather than mutating the high channel above.
const mknoonMessagesSilentChannelId = 'mknoon_messages_silent';
const mknoonMessagesSilentChannelName = 'Messages (silent)';
const mknoonMessagesSilentChannelDescription =
    'Silent follow-up message updates';

const mknoonMessagesChannel = AndroidNotificationChannel(
  mknoonMessagesChannelId,
  mknoonMessagesChannelName,
  description: mknoonMessagesChannelDescription,
  importance: Importance.high,
);

const mknoonMessagesSilentChannel = AndroidNotificationChannel(
  mknoonMessagesSilentChannelId,
  mknoonMessagesSilentChannelName,
  description: mknoonMessagesSilentChannelDescription,
  importance: Importance.low,
  playSound: false,
  enableVibration: false,
);

const mknoonMessagesNotificationDetails = NotificationDetails(
  android: AndroidNotificationDetails(
    mknoonMessagesChannelId,
    mknoonMessagesChannelName,
    channelDescription: mknoonMessagesChannelDescription,
    importance: Importance.high,
    priority: Priority.high,
    playSound: true,
  ),
  iOS: DarwinNotificationDetails(
    presentSound: true,
    presentAlert: true,
    presentBadge: true,
  ),
);

// 118 Phase 3: no-sound, no-vibration variant for the per-conversation tone
// debounce. Reusing the same per-conversation notification id with these
// details performs a silent in-place update of the existing notification.
const mknoonMessagesSilentNotificationDetails = NotificationDetails(
  android: AndroidNotificationDetails(
    mknoonMessagesSilentChannelId,
    mknoonMessagesSilentChannelName,
    channelDescription: mknoonMessagesSilentChannelDescription,
    importance: Importance.low,
    priority: Priority.low,
    playSound: false,
    enableVibration: false,
    onlyAlertOnce: true,
  ),
  iOS: DarwinNotificationDetails(
    presentSound: false,
    presentAlert: true,
    presentBadge: true,
  ),
);

/// Message-category details with a stable conversation thread. This is built
/// dynamically because the iOS thread identifier is recipient/conversation
/// specific; Android continues using the existing channel ids.
NotificationDetails mknoonConversationNotificationDetails({
  required String conversationKey,
  bool silent = false,
  bool autoCancel = true,
  ConversationNotificationSnapshot? snapshot,
}) {
  final historyLines = snapshot?.historyLines
      .where((line) => line.trim().isNotEmpty)
      .take(5)
      .toList(growable: false);
  final unreadMessageCount = snapshot?.totalUnreadMessageCount;
  return NotificationDetails(
    android: AndroidNotificationDetails(
      silent ? mknoonMessagesSilentChannelId : mknoonMessagesChannelId,
      silent ? mknoonMessagesSilentChannelName : mknoonMessagesChannelName,
      channelDescription: silent
          ? mknoonMessagesSilentChannelDescription
          : mknoonMessagesChannelDescription,
      importance: silent ? Importance.low : Importance.high,
      priority: silent ? Priority.low : Priority.high,
      playSound: !silent,
      enableVibration: !silent,
      onlyAlertOnce: silent,
      category: AndroidNotificationCategory.message,
      autoCancel: autoCancel,
      number: unreadMessageCount != null && unreadMessageCount > 0
          ? unreadMessageCount
          : null,
      styleInformation: historyLines == null || historyLines.isEmpty
          ? null
          : InboxStyleInformation(historyLines),
    ),
    iOS: DarwinNotificationDetails(
      presentSound: !silent,
      presentAlert: true,
      presentBadge: true,
      threadIdentifier: conversationKey,
    ),
  );
}

Future<void> ensureMknoonNotificationChannel(
  FlutterLocalNotificationsPlugin plugin,
) async {
  final android = plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();
  await android?.createNotificationChannel(mknoonMessagesChannel);
  await android?.createNotificationChannel(mknoonMessagesSilentChannel);
}
