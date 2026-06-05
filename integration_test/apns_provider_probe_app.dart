import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

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
  // devicectl --console captures stdout in profile builds.
  // ignore: avoid_print
  print('MKNOON_APNS_PROVIDER_PROBE $encoded');
}

String _tokenSummary(String? token) {
  if (token == null || token.isEmpty) return '<none>';
  final prefix = token.length <= 10 ? token : token.substring(0, 10);
  return '$prefix...(${token.length})';
}

Future<String?> _waitForApnsToken() async {
  final deadline = DateTime.now().add(const Duration(seconds: 45));
  while (DateTime.now().isBefore(deadline)) {
    final token = await FirebaseMessaging.instance.getAPNSToken();
    if (token != null && token.isNotEmpty) return token;
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  return null;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _probeLog('app_start', {'platform': Platform.operatingSystem});

  runApp(const _ProbeApp(status: 'Initializing Firebase...'));

  try {
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    await FirebaseMessaging.instance
        .setForegroundNotificationPresentationOptions(
          alert: true,
          badge: true,
          sound: true,
        );
  } catch (error) {
    _probeLog('firebase_init_error', {'error': error.toString()});
    runApp(_ProbeApp(status: 'Firebase init failed: $error'));
    return;
  }

  runApp(const _ProbeApp(status: 'Requesting notification permission...'));
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

  runApp(const _ProbeApp(status: 'Waiting for APNs token...'));
  final apnsToken = Platform.isIOS ? await _waitForApnsToken() : null;
  _probeLog('apns_token', {'summary': _tokenSummary(apnsToken)});

  runApp(const _ProbeApp(status: 'Waiting for FCM token...'));
  final fcmToken = await FirebaseMessaging.instance.getToken();
  if (fcmToken == null || fcmToken.isEmpty) {
    _probeLog('fcm_token_missing');
    runApp(const _ProbeApp(status: 'FCM token missing'));
    return;
  }

  _probeLog('fcm_token_ready', {
    'token': fcmToken,
    'summary': _tokenSummary(fcmToken),
  });

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
  runApp(_ProbeApp(status: 'Ready for provider send\n$_probeId'));
}

class _ProbeApp extends StatelessWidget {
  const _ProbeApp({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(status, textAlign: TextAlign.center),
          ),
        ),
      ),
    );
  }
}
