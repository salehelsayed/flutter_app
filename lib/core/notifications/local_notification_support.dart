import 'package:flutter_local_notifications/flutter_local_notifications.dart';

const mknoonMessagesChannelId = 'mknoon_messages';
const mknoonMessagesChannelName = 'Messages';
const mknoonMessagesChannelDescription = 'Incoming message notifications';

const mknoonMessagesChannel = AndroidNotificationChannel(
  mknoonMessagesChannelId,
  mknoonMessagesChannelName,
  description: mknoonMessagesChannelDescription,
  importance: Importance.high,
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

Future<void> ensureMknoonNotificationChannel(
  FlutterLocalNotificationsPlugin plugin,
) async {
  await plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >()
      ?.createNotificationChannel(mknoonMessagesChannel);
}
