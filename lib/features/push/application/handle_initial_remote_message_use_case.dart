import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';

import '../../../core/notifications/notification_route_target.dart';
import '../../../core/utils/cold_start_notif_anchor.dart';

typedef GetInitialRemoteMessageFn = Future<RemoteMessage?> Function();
typedef OnInitialRemoteMessageFn =
    FutureOr<void> Function(RemoteMessage message);

/// Replays the remote notification tap that launched the app from a
/// terminated state.
Future<void> handleInitialRemoteMessage({
  required GetInitialRemoteMessageFn getInitialMessage,
  required OnInitialRemoteMessageFn onMessageOpened,
}) async {
  final message = await getInitialMessage();
  if (message == null) return;

  // FDC-S1 Method 5(d): this is the cross-platform cold notif-tap entry (iOS
  // consumeInitialNotificationOpen + Android getInitialMessage). Record the tap
  // so the main isolate can emit FDC_COLDSTART_NOTIF_TAP_NODE_READY once
  // node:start returns, yielding the NSE→main-isolate gap. Observation-only.
  ColdStartNotifAnchor.instance.recordNotifTap(
    NotificationRouteTarget.messageIdFromRemoteMessageData(message.data),
  );

  await Future.sync(() => onMessageOpened(message));
}
