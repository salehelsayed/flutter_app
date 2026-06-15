import 'package:flutter_local_notifications/flutter_local_notifications.dart';

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
