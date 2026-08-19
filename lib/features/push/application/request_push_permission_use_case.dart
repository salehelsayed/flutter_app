import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/core/utils/push_diagnostics_logger.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Requests push permission and returns whether push cards can actually be
/// posted.
///
/// The request result alone is NOT trustworthy on Android. firebase_messaging
/// short-circuits `requestPermissions()` to `authorized` whenever
/// `Context.checkSelfPermission(POST_NOTIFICATIONS)` is granted on SDK >= 33,
/// never consulting `NotificationManagerCompat.areNotificationsEnabled()`. A
/// user whose notifications are off at the NotificationManager layer therefore
/// gets `authorized`, a registered token, and silently discarded cards — while
/// the in-app "Open notification settings" banner never appears because the
/// coordinator's denied branch is unreachable.
///
/// So a granted-looking request result is verified against the OS's real
/// notification state before it is believed. The verify only ever NARROWS a
/// granted verdict; a request-level denial is returned untouched and never
/// consults the OS.
Future<bool> requestPushPermission({
  Future<NotificationSettings> Function()? requestPermissionFn,
  Future<bool> Function()? osNotificationsEnabledFn,
}) async {
  logPushDiagnostic('permission_request_begin');
  emitFlowEvent(
    layer: 'FL',
    event: 'PUSH_PERMISSION_REQUEST_BEGIN',
    details: {},
  );

  final effectiveRequestPermission =
      requestPermissionFn ??
      () => FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

  final settings = await effectiveRequestPermission();

  final requestGranted =
      settings.authorizationStatus == AuthorizationStatus.authorized ||
      settings.authorizationStatus == AuthorizationStatus.provisional;

  var granted = requestGranted;
  // Raw reading of the OS check, stamped into the RESULT event whenever the
  // check was consulted. Stays null on a request-level denial, where the check
  // is deliberately never invoked.
  bool? osEnabled;

  if (requestGranted) {
    final effectiveOsCheck =
        osNotificationsEnabledFn ?? _defaultOsNotificationsEnabled;

    try {
      osEnabled = await effectiveOsCheck();
    } catch (e) {
      // Fail OPEN, behind a deliberately BROAD catch. An escaping throw would
      // land in the coordinator's exception handler, which schedules a 15s
      // retry that re-enters with the permission state still `unknown` and
      // re-fires the OS permission dialog every cycle. `on Exception` is not
      // enough: plugin/platform failures surface as Error subtypes too.
      // PUSH_PERMISSION_OS_CHECK_FAILED is the discriminator that tells this
      // fail-open `true` apart from a genuine `true` reading.
      osEnabled = true;
      logPushDiagnostic(
        'permission_os_check_failed',
        details: {'errorType': e.runtimeType.toString()},
      );
      emitFlowEvent(
        layer: 'FL',
        event: 'PUSH_PERMISSION_OS_CHECK_FAILED',
        details: {'errorType': e.runtimeType.toString()},
      );
    }

    if (!osEnabled) {
      granted = false;
      logPushDiagnostic(
        'permission_os_state_override',
        details: {
          'requestStatus': settings.authorizationStatus.name,
          'osEnabled': false,
        },
      );
      emitFlowEvent(
        layer: 'FL',
        event: 'PUSH_PERMISSION_OS_STATE_OVERRIDE',
        details: {
          'requestStatus': settings.authorizationStatus.name,
          'osEnabled': false,
        },
      );
    }
  }

  final resultDetails = <String, dynamic>{
    'status': settings.authorizationStatus.name,
    'granted': granted,
    // Null-aware element: the key is present only when the check answered.
    'osEnabled': ?osEnabled,
  };

  logPushDiagnostic('permission_request_result', details: resultDetails);

  emitFlowEvent(
    layer: 'FL',
    event: 'PUSH_PERMISSION_REQUEST_RESULT',
    details: resultDetails,
  );

  return granted;
}

/// Reads the OS's real notification state.
///
/// flutter_local_notifications is the very poster whose cards get dropped in
/// the bug state, and its Android `areNotificationsEnabled()` is an
/// UNCONDITIONAL `NotificationManagerCompat.areNotificationsEnabled()` read on
/// every SDK level — unlike `FirebaseMessaging.getNotificationSettings()` and
/// permission_handler's `Permission.notification.status`, which both route to
/// `checkSelfPermission` on SDK >= 33 and therefore repeat the same lie. It is
/// a read-only binder query: it never prompts and never mutates state.
///
/// Fails OPEN on a null platform resolve so non-Android hosts and any
/// unregistered-plugin case keep today's behavior.
Future<bool> _defaultOsNotificationsEnabled() async {
  if (kIsWeb || !Platform.isAndroid) return true;
  final android = FlutterLocalNotificationsPlugin()
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();
  return await android?.areNotificationsEnabled() ?? true;
}
