import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/core/utils/push_diagnostics_logger.dart';

Future<bool> requestPushPermission({
  Future<NotificationSettings> Function()? requestPermissionFn,
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

  final granted =
      settings.authorizationStatus == AuthorizationStatus.authorized ||
      settings.authorizationStatus == AuthorizationStatus.provisional;

  logPushDiagnostic(
    'permission_request_result',
    details: {'status': settings.authorizationStatus.name, 'granted': granted},
  );

  emitFlowEvent(
    layer: 'FL',
    event: 'PUSH_PERMISSION_REQUEST_RESULT',
    details: {'status': settings.authorizationStatus.name, 'granted': granted},
  );

  return granted;
}
