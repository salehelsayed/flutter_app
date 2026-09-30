import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_app/core/notifications/durable_conversation_notification_id_registry.dart';
import 'package:flutter_app/core/notifications/flutter_notification_service.dart';
import 'package:flutter_app/core/notifications/notification_request_observation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  final calls = <MethodCall>[];
  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('native-observation-');
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'initialize') return true;
          return null;
        });
  });
  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
    await directory.delete(recursive: true);
  });

  FlutterNotificationService service(NotificationRequestObserver? observer) =>
      FlutterNotificationService(
        requestObserver: observer,
        notificationIdRegistryResolver: () async =>
            DurableConversationNotificationIdRegistry(directory: directory),
      );

  test(
    'native content is unchanged and observer retains only exact hashes',
    () async {
      final observations = <NotificationRequestObservation>[];
      final production = service(observations.add);
      final start = DateTime.now().toUtc().microsecondsSinceEpoch;
      await production.showMessageNotification(
        contactPeerId: 'peer-a',
        senderUsername: 'اسم sender',
        messageText: 'private body 🐈',
        payload: 'group:owned|message:one',
      );
      final end = DateTime.now().toUtc().microsecondsSinceEpoch;
      final native =
          calls.singleWhere((call) => call.method == 'show').arguments as Map;
      final observed = observations.single;
      expect(native['title'], 'اسم sender');
      expect(native['body'], 'private body 🐈');
      expect(native['payload'], 'group:owned|message:one');
      expect(observed.notificationId, native['id']);
      expect(observed.contactPeerId, 'peer-a');
      expect(observed.routePayload, native['payload']);
      expect(
        observed.titleSha256,
        sha256.convert(utf8.encode('اسم sender')).toString(),
      );
      expect(
        observed.bodySha256,
        sha256.convert(utf8.encode('private body 🐈')).toString(),
      );
      expect(observed.observedAtMicros, inInclusiveRange(start, end));
      expect(jsonEncode(observed.toJson()), isNot(contains('private body')));
      expect(jsonEncode(observed.toJson()), isNot(contains('اسم sender')));
    },
  );

  test(
    'upstream tone decision remains distinct from native silent override',
    () async {
      final observations = <NotificationRequestObservation>[];
      await service(observations.add).showMessageNotificationAtNativeBoundary(
        contactPeerId: 'peer-a',
        senderUsername: 'sender',
        messageText: 'body',
        silent: false,
        publishNative: (showNative) => showNative(silent: true),
      );
      expect(observations.single.requestedSilent, isFalse);
      expect(observations.single.silent, isTrue);
      expect(calls.where((call) => call.method == 'show'), hasLength(1));
    },
  );

  test(
    'observation failure cannot suppress actual native publication',
    () async {
      await service(
        (_) => throw StateError('observer fault'),
      ).showMessageNotification(
        contactPeerId: 'peer-a',
        senderUsername: 'sender',
        messageText: 'body',
      );
      expect(calls.where((call) => call.method == 'show'), hasLength(1));
    },
  );

  test(
    'ordinary production with no observer retains native publication',
    () async {
      await service(null).showMessageNotification(
        contactPeerId: 'peer-a',
        senderUsername: 'sender',
        messageText: 'body',
      );
      expect(calls.where((call) => call.method == 'show'), hasLength(1));
    },
  );
}
