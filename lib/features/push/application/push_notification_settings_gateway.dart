import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';

abstract interface class PushNotificationSettingsGateway {
  Future<bool> openNotificationSettings();
}

typedef OpenAndroidNotificationSettings = Future<bool> Function();

/// Opens the app-specific system settings page that owns notification access.
///
/// Android uses `ACTION_APP_NOTIFICATION_SETTINGS`, not the generic app-details
/// page exposed by `permission_handler.openAppSettings`. Other platforms fail
/// closed without attempting an Android channel call.
final class PlatformPushNotificationSettingsGateway
    implements PushNotificationSettingsGateway {
  const PlatformPushNotificationSettingsGateway({
    bool? isAndroid,
    OpenAndroidNotificationSettings? openAndroidNotificationSettings,
  }) : _isAndroid = isAndroid,
       _openAndroidNotificationSettings = openAndroidNotificationSettings;

  static const _channel = MethodChannel('mknoon/push_notification_settings');
  static const _openMethod = 'openAppNotificationSettings';

  final bool? _isAndroid;
  final OpenAndroidNotificationSettings? _openAndroidNotificationSettings;

  @override
  Future<bool> openNotificationSettings() async {
    final isAndroid = _isAndroid ?? (!kIsWeb && Platform.isAndroid);
    if (!isAndroid) return false;
    try {
      final open = _openAndroidNotificationSettings ?? _openWithMethodChannel;
      return await open();
    } on Object {
      return false;
    }
  }

  static Future<bool> _openWithMethodChannel() async {
    return await _channel.invokeMethod<bool>(_openMethod) ?? false;
  }
}
