import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_app/core/notifications/recent_background_notification_gate.dart';
import 'package:flutter_app/core/notifications/recent_remote_notification_gate.dart';
import 'package:flutter_app/core/notifications/conversation_notification_content_kind.dart';
import 'package:flutter_app/core/notifications/durable_conversation_notification_id_registry.dart';
import 'package:flutter_app/core/notifications/durable_notification_tone_lease.dart';
import 'package:flutter_app/features/push/application/background_message_handler.dart';
import 'package:flutter_app/features/push/application/background_push_notification_fallback.dart';
import 'package:flutter_app/features/push/application/push_envelope_staging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  final log = <MethodCall>[];
  final staged = <StagedPushEnvelope>[];

  setUp(() {
    log.clear();
    staged.clear();
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    debugSetBackgroundPushNotificationDisplayEligibilityResolver(
      (_) async => const PushFallbackNotificationDisplayEligibility.allow(),
    );
    debugSetBackgroundPushNotificationResolver(
      (_) async => const BackgroundPushNotificationFallback(
        title: 'Alice',
        body: 'payload body',
        payload: 'peer-alice',
      ),
    );
    debugSetBackgroundPushEnvelopeStager((entry) async {
      staged.add(entry);
    });
    debugSetBackgroundAccountMigrationNetworkGate(({
      String? peerId,
      required String operation,
    }) async {
      return true;
    });
    final backgroundGate = RecentBackgroundNotificationGate(
      filePath:
          '${Directory.systemTemp.path}/bg-stage-gate-${DateTime.now().microsecondsSinceEpoch}.json',
    );
    debugSetRecentBackgroundNotificationGate(backgroundGate);
    addTearDown(backgroundGate.clear);
    final remoteGate = RecentRemoteNotificationGate(
      filePath:
          '${Directory.systemTemp.path}/bg-stage-remote-gate-${DateTime.now().microsecondsSinceEpoch}.json',
    );
    debugSetRecentRemoteNotificationGate(remoteGate);
    addTearDown(remoteGate.clear);
    final reactionCoordinatorDirectory = Directory.systemTemp.createTempSync(
      'background-stage-reaction-coordinator-',
    );
    final reactionCoordinator = DurableNotificationToneLease(
      directory: reactionCoordinatorDirectory,
    );
    debugSetBackgroundReactionNotificationCoordinatorResolver(
      () async => reactionCoordinator,
    );
    addTearDown(() {
      if (reactionCoordinatorDirectory.existsSync()) {
        reactionCoordinatorDirectory.deleteSync(recursive: true);
      }
    });
    final notificationIdDirectory = Directory.systemTemp.createTempSync(
      'background-stage-notification-id-registry-',
    );
    final notificationIdRegistry = DurableConversationNotificationIdRegistry(
      directory: notificationIdDirectory,
    );
    debugSetBackgroundConversationNotificationIdRegistryResolver(
      () async => notificationIdRegistry,
    );
    addTearDown(() {
      if (notificationIdDirectory.existsSync()) {
        notificationIdDirectory.deleteSync(recursive: true);
      }
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          log.add(call);
          if (call.method == 'initialize') return true;
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
    debugResetBackgroundPushNotificationResolver();
    debugResetBackgroundPushNotificationDisplayEligibilityResolver();
    debugResetBackgroundPushEnvelopeStager();
    debugResetBackgroundAccountMigrationNetworkGate();
    debugResetBackgroundReactionNotificationCoordinatorResolver();
    debugResetBackgroundConversationNotificationIdRegistryResolver();
    debugResetBackgroundNotificationsInitialization();
    debugResetRecentBackgroundNotificationGate();
    debugResetRecentRemoteNotificationGate();
  });

  test(
    'routable chat data push with kem+ciphertext+nonce stages an envelope at receipt',
    () async {
      const message = RemoteMessage(
        messageId: 'fcm-1',
        data: {
          'type': 'new_message',
          'sender_id': 'peer-alice',
          'message_id': 'msg-1',
          'kem': 'kem',
          'ciphertext': 'ciphertext',
          'nonce': 'nonce-1',
        },
      );

      await firebaseMessagingBackgroundHandler(message);

      expect(staged, hasLength(1));
      expect(staged.single.kind, 'chat');
      expect(staged.single.kem, 'kem');
      expect(staged.single.ciphertext, 'ciphertext');
      expect(staged.single.nonce, 'nonce-1');
      expect(staged.single.id, 'nonce-1');
      expect(staged.single.senderPeerId, 'peer-alice');
      expect(staged.single.messageId, 'msg-1');
      expect(staged.single.receivedAtMs, greaterThan(0));
      expect(log.map((call) => call.method), contains('show'));
    },
  );

  test('Android stages reaction kind with typed outer metadata', () async {
    const message = RemoteMessage(
      messageId: 'fcm-reaction-1',
      data: {
        'type': 'message_reaction',
        'sender_id': 'peer-alice',
        'event_id': 'reaction-event-1',
        'target_message_id': 'target-message-1',
        'action': 'add',
        'kem': 'reaction-kem',
        'ciphertext': 'reaction-ciphertext',
        'nonce': 'reaction-nonce',
      },
    );

    await firebaseMessagingBackgroundHandler(message);

    expect(staged, hasLength(1));
    expect(staged.single.kind, 'reaction');
    expect(staged.single.senderPeerId, 'peer-alice');
    expect(staged.single.eventId, 'reaction-event-1');
    expect(staged.single.messageId, 'reaction-event-1');
    expect(staged.single.action, 'add');
    expect(staged.single.targetMessageId, 'target-message-1');
    expect(staged.single.kem, 'reaction-kem');
    expect(staged.single.ciphertext, 'reaction-ciphertext');
    expect(staged.single.nonce, 'reaction-nonce');
  });

  test(
    'authenticated inner identity promotes a test-mutated missing outer id before claim and show',
    () async {
      debugSetBackgroundPushNotificationResolver((message) async {
        final isReaction = message.data['type'] == 'message_reaction';
        return BackgroundPushNotificationFallback(
          title: 'Alice',
          body: 'authenticated body',
          payload: 'peer-alice',
          resolvedEventIdentity: isReaction
              ? const ResolvedPushEventIdentity.authenticatedInner(
                  kind: ConversationNotificationContentKind.reaction,
                  canonicalEventId: 'inner-reaction-1',
                  targetMessageId: 'target-message-1',
                  action: 'add',
                )
              : const ResolvedPushEventIdentity.authenticatedInner(
                  kind: ConversationNotificationContentKind.message,
                  canonicalEventId: 'inner-message-1',
                ),
        );
      });

      await firebaseMessagingBackgroundHandler(
        const RemoteMessage(
          messageId: 'transport-chat-1',
          data: <String, dynamic>{
            'type': 'new_message',
            'sender_id': 'peer-alice',
            'kem': 'kem',
            'ciphertext': 'ciphertext',
            'nonce': 'missing-chat-id-nonce',
          },
        ),
      );
      await firebaseMessagingBackgroundHandler(
        const RemoteMessage(
          messageId: 'transport-reaction-1',
          data: <String, dynamic>{
            'type': 'message_reaction',
            'sender_id': 'peer-alice',
            'target_message_id': 'target-message-1',
            'action': 'add',
            'kem': 'kem',
            'ciphertext': 'ciphertext',
            'nonce': 'missing-reaction-id-nonce',
          },
        ),
      );

      expect(staged, hasLength(4));
      expect(staged[0].identityResolutionPending, isTrue);
      expect(staged[0].messageId, isNull);
      expect(staged[1].identityResolutionPending, isFalse);
      expect(staged[1].messageId, 'inner-message-1');
      expect(staged[2].identityResolutionPending, isTrue);
      expect(staged[2].eventId, isNull);
      expect(staged[3].identityResolutionPending, isFalse);
      expect(staged[3].eventId, 'inner-reaction-1');
      expect(log.where((call) => call.method == 'show'), hasLength(2));
    },
  );

  test(
    'no-ciphertext push stages nothing; group-kind push stages nothing; staging throw never suppresses notification',
    () async {
      await firebaseMessagingBackgroundHandler(
        const RemoteMessage(
          messageId: 'missing-cipher',
          data: {
            'type': 'new_message',
            'sender_id': 'peer-alice',
            'kem': 'kem',
            'nonce': 'nonce-missing-cipher',
          },
        ),
      );
      await firebaseMessagingBackgroundHandler(
        const RemoteMessage(
          messageId: 'group-1',
          data: {
            'type': 'group_message',
            'groupId': 'group-1',
            'kem': 'kem',
            'ciphertext': 'ciphertext',
            'nonce': 'nonce-group',
          },
        ),
      );
      expect(staged, isEmpty);

      debugSetBackgroundPushEnvelopeStager((entry) async {
        throw StateError('disk full');
      });
      await firebaseMessagingBackgroundHandler(
        const RemoteMessage(
          messageId: 'throwing-stage',
          data: {
            'type': 'new_message',
            'sender_id': 'peer-alice',
            'kem': 'kem',
            'ciphertext': 'ciphertext',
            'nonce': 'nonce-throw',
          },
        ),
      );

      expect(log.where((call) => call.method == 'show'), hasLength(3));
    },
  );
}
