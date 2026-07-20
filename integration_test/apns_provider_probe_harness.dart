import 'dart:convert';
import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:flutter_app/features/push/application/background_message_handler.dart';

const _probeId = String.fromEnvironment(
  'APNS_PROVIDER_PROBE_ID',
  defaultValue: 'adhoc',
);

void _probeLog(String event, [Map<String, Object?> details = const {}]) {
  final encoded = jsonEncode(<String, Object?>{
    'event': event,
    'probeId': _probeId,
    ...details,
  });
  // Intentionally machine-readable: the host script watches stdout/device logs.
  // ignore: avoid_print
  print('MKNOON_APNS_PROVIDER_PROBE $encoded');
}

String _tokenSummary(String? token) {
  if (token == null || token.isEmpty) return '<none>';
  return '<present:length=${token.length}>';
}

Future<String?> _waitForApnsToken() async {
  final deadline = DateTime.now().add(const Duration(seconds: 30));
  while (DateTime.now().isBefore(deadline)) {
    final token = await FirebaseMessaging.instance.getAPNSToken();
    if (token != null && token.isNotEmpty) return token;
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  return null;
}

Future<void> main() async {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('physical iOS APNs provider probe waits for remote push', (
    tester,
  ) async {
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    await FirebaseMessaging.instance
        .setForegroundNotificationPresentationOptions(
          alert: true,
          badge: true,
          sound: true,
        );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Center(child: Text('APNs provider probe ready'))),
      ),
    );

    final settings = await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );
    _probeLog('permission_result', {
      'authorizationStatus': settings.authorizationStatus.name,
      'platform': Platform.operatingSystem,
    });

    final apnsToken = Platform.isIOS ? await _waitForApnsToken() : null;
    _probeLog('apns_token', {'summary': _tokenSummary(apnsToken)});

    final fcmToken = await FirebaseMessaging.instance.getToken();
    if (fcmToken == null || fcmToken.isEmpty) {
      _probeLog('fcm_token_missing');
      fail('FCM token was not available');
    }

    _probeLog('fcm_token_ready', {'summary': _tokenSummary(fcmToken)});

    FirebaseMessaging.onMessage.listen((message) {
      _probeLog('foreground_message', {
        'messageId': message.messageId,
        'data': message.data,
        'hasNotification': message.notification != null,
      });
    });

    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      _probeLog('message_opened_app', {
        'messageId': message.messageId,
        'data': message.data,
        'hasNotification': message.notification != null,
      });
    });

    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) {
      _probeLog('initial_message', {
        'messageId': initial.messageId,
        'data': initial.data,
        'hasNotification': initial.notification != null,
      });
    }

    _probeLog('ready_for_provider_send');

    // Keep the process alive long enough for foreground/background/terminated
    // host-side probes. The host may suspend or terminate the app externally.
    await Future<void>.delayed(const Duration(minutes: 10));
  });
}
