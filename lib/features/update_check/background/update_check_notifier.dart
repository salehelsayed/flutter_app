import 'dart:ui' show Locale;

import 'package:flutter/services.dart';
import 'package:flutter_app/features/push/application/notification_preview_copy.dart';

import '../domain/update_check_notify_policy.dart';

/// The one channel between the T4a background check and native code, on the
/// main engine and on the Android minimal engine.
const String updateCheckBackgroundChannelName =
    'mknoon/update_check_background';

/// Built-in notification text. Nothing comes from the version file.
({String title, String body}) updateNotificationText(
  UpdateNotifyCopy copy, {
  Locale? locale,
}) {
  final l10n = notificationPreviewLocalizations(locale: locale);
  return switch (copy) {
    UpdateNotifyCopy.general => (
      title: l10n.update_notification_title_general,
      body: l10n.update_notification_body_general,
    ),
    UpdateNotifyCopy.security => (
      title: l10n.update_notification_title_security,
      body: l10n.update_notification_body_security,
    ),
  };
}

/// Posts the update notification. Native code checks the permission (it never
/// asks for it), uses the fixed id or tag per kind, and builds the tap action
/// from a built-in store URL.
abstract interface class UpdateNotificationPoster {
  /// True when the notification was posted. False when notifications are not
  /// allowed or posting failed.
  Future<bool> post({
    required UpdateNotifyKind kind,
    required String title,
    required String body,
  });
}

final class MethodChannelUpdateNotificationPoster
    implements UpdateNotificationPoster {
  const MethodChannelUpdateNotificationPoster({
    MethodChannel channel = const MethodChannel(
      updateCheckBackgroundChannelName,
    ),
  }) : _channel = channel;

  final MethodChannel _channel;

  @override
  Future<bool> post({
    required UpdateNotifyKind kind,
    required String title,
    required String body,
  }) async {
    try {
      final posted = await _channel.invokeMethod<bool>('notify', {
        'kind': kind.wireName,
        'title': title,
        'body': body,
      });
      return posted ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
