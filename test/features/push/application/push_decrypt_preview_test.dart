import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/conversation/domain/models/message_payload.dart';
import 'package:flutter_app/features/push/application/background_push_notification_fallback.dart';
import 'package:flutter_app/features/push/application/push_decrypt_preview.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('resolveBackgroundPushNotification', () {
    test('decrypts 1:1 ciphertext preview with sender title', () async {
      const message = RemoteMessage(
        data: {
          'type': 'new_message',
          'sender_id': 'peer-alice',
          'message_id': 'msg-chat-1',
          'kem': 'kem',
          'ciphertext': 'ciphertext',
          'nonce': 'nonce',
        },
      );

      final resolved = await resolveBackgroundPushNotification(
        message,
        decryptOneToOne:
            ({required kem, required ciphertext, required nonce}) async {
              expect(kem, 'kem');
              expect(ciphertext, 'ciphertext');
              expect(nonce, 'nonce');
              return const MessagePayload(
                id: 'msg-chat-1',
                text: 'Hello secret',
                senderPeerId: 'peer-alice',
                senderUsername: 'Alice',
                timestamp: '2026-04-24T12:00:00.000Z',
              ).toInnerJson();
            },
      );

      expect(resolved.title, 'Alice');
      expect(resolved.body, 'Hello secret');
      expect(resolved.payload, 'peer-alice');
    });

    test('emits leak-safe Android decrypt telemetry', () async {
      final events = <Map<String, dynamic>>[];
      debugSetFlowEventSink(events.add);
      addTearDown(() => debugSetFlowEventSink(null));

      const message = RemoteMessage(
        data: {
          'type': 'new_message',
          'sender_id': 'peer-alice',
          'message_id': 'msg-chat-1',
          'kem': 'kem',
          'ciphertext': 'ciphertext',
          'nonce': 'nonce',
        },
      );

      final resolved = await resolveBackgroundPushNotification(
        message,
        decryptOneToOne:
            ({required kem, required ciphertext, required nonce}) async {
              return const MessagePayload(
                id: 'msg-chat-1',
                text: 'UltraSecretCanary',
                senderPeerId: 'peer-alice',
                senderUsername: 'Alice',
                timestamp: '2026-04-24T12:00:00.000Z',
              ).toInnerJson();
            },
      );

      expect(resolved.title, 'Alice');
      expect(resolved.body, 'UltraSecretCanary');
      expect(events, hasLength(1));
      expect(events.single['event'], 'PUSH_ANDROID_DATA_DECRYPT_OK');
      expect(events.single['details'], {'kind': 'chat'});

      final encodedEvents = jsonEncode(events);
      expect(encodedEvents, isNot(contains('UltraSecretCanary')));
      expect(encodedEvents, isNot(contains('Alice')));
    });

    test(
      'decrypts group ciphertext preview with sender-prefixed body',
      () async {
        const message = RemoteMessage(
          data: {
            'type': 'group_message',
            'groupId': 'group-team',
            'message_id': 'msg-group-1',
            'keyEpoch': '7',
            'ciphertext': 'ciphertext',
            'nonce': 'nonce',
          },
        );

        final resolved = await resolveBackgroundPushNotification(
          message,
          decryptGroup:
              ({
                required groupId,
                required keyEpoch,
                required ciphertext,
                required nonce,
              }) async {
                expect(groupId, 'group-team');
                expect(keyEpoch, 7);
                expect(ciphertext, 'ciphertext');
                expect(nonce, 'nonce');
                return jsonEncode({
                  'messageId': 'msg-group-1',
                  'senderUsername': 'Alice',
                  'text': 'Hello group',
                });
              },
        );

        expect(resolved.title, backgroundPushDefaultTitle);
        expect(resolved.body, 'Alice: Hello group');
        expect(resolved.payload, 'group:group-team|message:msg-group-1');
      },
    );

    test('degrades to fallback when decrypt input is missing', () async {
      const message = RemoteMessage(
        data: {'type': 'new_message', 'sender_id': 'peer-alice'},
      );

      final resolved = await resolveBackgroundPushNotification(
        message,
        decryptOneToOne:
            ({required kem, required ciphertext, required nonce}) async =>
                throw StateError('should not decrypt'),
      );

      expect(resolved.title, backgroundPushDefaultTitle);
      expect(resolved.body, backgroundPushDefaultBody);
      expect(resolved.payload, 'peer-alice');
    });

    test('degrades to fallback when decrypt throws', () async {
      const message = RemoteMessage(
        data: {
          'type': 'group_message',
          'groupId': 'group-team',
          'message_id': 'msg-group-1',
          'keyEpoch': '7',
          'ciphertext': 'ciphertext',
          'nonce': 'nonce',
        },
      );

      final resolved = await resolveBackgroundPushNotification(
        message,
        decryptGroup:
            ({
              required groupId,
              required keyEpoch,
              required ciphertext,
              required nonce,
            }) async => throw StateError('missing key'),
      );

      expect(resolved.title, backgroundPushDefaultTitle);
      expect(resolved.body, backgroundPushDefaultBody);
      expect(resolved.payload, 'group:group-team|message:msg-group-1');
    });
  });

  group('pushPreviewBody', () {
    test('caps long text previews at 140 scalar values', () {
      final body = pushPreviewBody('a' * 180, null);

      expect(body.length, 140);
    });

    test('renders typed media descriptors', () {
      expect(
        pushPreviewBody('', [
          {'mediaType': 'audio'},
        ]),
        'Voice message',
      );
      expect(
        pushPreviewBody('', [
          {'mediaType': 'image'},
        ]),
        'Photo',
      );
    });
  });
}
