import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart' as permissions;

abstract interface class PushNotificationSettingsGateway {
  Future<bool> openNotificationSettings();
}

typedef OpenAndroidNotificationSettings = Future<bool> Function();

/// Opens the app-specific system settings page that owns notification access.
///
/// Android uses `ACTION_APP_NOTIFICATION_SETTINGS`, not the generic app-details
/// page. iOS uses the existing permission plugin's app settings route.
final class PlatformPushNotificationSettingsGateway
    implements PushNotificationSettingsGateway {
  const PlatformPushNotificationSettingsGateway({
    bool? isAndroid,
    bool? isIOS,
    OpenAndroidNotificationSettings? openAndroidNotificationSettings,
  }) : _isAndroid = isAndroid,
       _isIOS = isIOS,
       _openAndroidNotificationSettings = openAndroidNotificationSettings;

  static const _channel = MethodChannel('mknoon/push_notification_settings');
  static const _openMethod = 'openAppNotificationSettings';

  final bool? _isAndroid;
  final bool? _isIOS;
  final OpenAndroidNotificationSettings? _openAndroidNotificationSettings;

  @override
  Future<bool> openNotificationSettings() async {
    final isAndroid = _isAndroid ?? (!kIsWeb && Platform.isAndroid);
    try {
      if (!isAndroid) {
        final isIOS = _isIOS ?? (!kIsWeb && Platform.isIOS);
        return isIOS ? await permissions.openAppSettings() : false;
      }
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
