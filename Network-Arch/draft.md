  1. iOS Bug: Background notifications never shown

  Problem: In lib/features/push/application/background_message_handler.dart:55, the background handler had:

  if (!Platform.isAndroid ||
      !shouldShowBackgroundPushFallbackNotification(message)) {
    return;
  }

  On iOS, !Platform.isAndroid is true, so the function returned immediately — no local notification was ever displayed. The relay
  server sends an APNS alert payload, but because the FCM message is a hybrid data+alert message with content-available: true, iOS
  can treat it as a silent push and suppress the banner.

  Fix: Removed the !Platform.isAndroid guard so both platforms show a local notification via flutter_local_notifications. The iOS
  DarwinNotificationDetails with presentAlert: true was already configured.
