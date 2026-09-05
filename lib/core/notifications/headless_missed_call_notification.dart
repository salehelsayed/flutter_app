import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'deterministic_notification_id.dart';
import 'local_notification_support.dart';
import '../utils/flow_event_emitter.dart';

/// 408: posts the missed-call card from the killed-app isolate.
///
/// A call that arrives while the app is dead has no `FlutterNotificationService`
/// and no widget tree to read a localization delegate from. Plan 406 gave that
/// path its history row, but the user still got no card — the case where one
/// matters most, because there is no open app in which to notice the call.
///
/// The isolate owns its own plugin instance, exactly as
/// `background_message_handler.dart` does: a background `FlutterEngine` has its
/// own module globals, so the foreground plugin's initialization and channels
/// do not exist here.
final class HeadlessMissedCallNotification {
  HeadlessMissedCallNotification({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  bool _initialized = false;

  /// Shows one card. Never throws: a notification is presentation, and a call
  /// must not fail because the platform refused to draw one.
  Future<void> show({
    required String contactAccountPeerId,
    required String title,
    required String body,
  }) async {
    try {
      await _ensureInitialized();
      await _plugin.show(
        // The same id the foreground path mints, so a later foreground post
        // for the same contact replaces this card instead of stacking.
        deterministicConversationNotificationId(
          'call:${contactAccountPeerId.trim()}',
        ),
        title,
        body,
        mknoonMissedCallNotificationDetails,
        payload: contactAccountPeerId,
      );
      emitFlowEvent(
        layer: 'FL',
        event: 'HEADLESS_MISSED_CALL_NOTIFICATION_POSTED',
        details: const <String, Object?>{},
      );
    } catch (error) {
      emitFlowEvent(
        layer: 'FL',
        event: 'HEADLESS_MISSED_CALL_NOTIFICATION_FAILED',
        details: {'errorType': error.runtimeType.toString()},
      );
    }
  }

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(
        requestSoundPermission: false,
        requestBadgePermission: false,
        requestAlertPermission: false,
      ),
    );
    await _plugin.initialize(settings);
    // A channel that was never created posts nothing at all on Android 8+,
    // and this plugin instance has created none of them yet.
    await ensureMknoonNotificationChannel(_plugin);
    _initialized = true;
  }
}
