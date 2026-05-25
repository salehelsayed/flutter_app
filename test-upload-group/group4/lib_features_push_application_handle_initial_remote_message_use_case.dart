import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';

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

  await Future.sync(() => onMessageOpened(message));
}
