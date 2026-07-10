import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/notifications/notification_route_target.dart';

void main() {
  group('NotificationRouteTarget', () {
    test('fromRemoteMessageData maps new_message to conversation route', () {
      final routeTarget = NotificationRouteTarget.fromRemoteMessageData({
        'type': 'new_message',
        'sender_id': 'peer-123',
      });

      expect(routeTarget, isNotNull);
      expect(routeTarget!.kind, NotificationRouteTargetKind.conversation);
      expect(routeTarget.peerId, 'peer-123');
    });

    test('fromRemoteMessageData maps group_message to group route', () {
      final routeTarget = NotificationRouteTarget.fromRemoteMessageData({
        'type': 'group_message',
        'groupId': 'group-123',
      });

      expect(routeTarget, isNotNull);
      expect(routeTarget!.kind, NotificationRouteTargetKind.group);
      expect(routeTarget.groupId, 'group-123');
    });

    test(
      'fromRemoteMessageData maps accepted group id aliases to group routes',
      () {
        final cases = <String, String>{
          'group_id': 'group-snake',
          'gid': 'group-gid',
          'conversation_id': 'group-conversation',
        };

        for (final entry in cases.entries) {
          final routeTarget = NotificationRouteTarget.fromRemoteMessageData({
            'type': 'group_message',
            entry.key: entry.value,
            'message_id': 'msg-${entry.key}',
          });

          expect(routeTarget, isNotNull, reason: entry.key);
          expect(routeTarget!.kind, NotificationRouteTargetKind.group);
          expect(routeTarget.groupId, entry.value);
          expect(routeTarget.messageId, 'msg-${entry.key}');
        }
      },
    );

    test(
      'fromRemoteMessageData maps alternate group-message identity fields',
      () {
        final cases = <Map<String, dynamic>>[
          {
            'payloadType': 'group_message',
            'group_id': 'group-payload-type',
            'message_id': 'msg-payload-type',
          },
          {
            'kind': 'group_message',
            'gid': 'group-kind',
            'messageId': 'msg-kind',
          },
          {
            'kind': 'group_offline_replay',
            'payloadType': 'group_message',
            'conversation_id': 'group-replay',
            'msgId': 'msg-replay',
          },
        ];

        for (final data in cases) {
          final routeTarget = NotificationRouteTarget.fromRemoteMessageData(
            data,
          );

          expect(routeTarget, isNotNull, reason: data.toString());
          expect(routeTarget!.kind, NotificationRouteTargetKind.group);
          expect(routeTarget.groupId, startsWith('group-'));
          expect(routeTarget.messageId, startsWith('msg-'));
        }
      },
    );

    test('fromRemoteMessageData falls back to payload-only group routes', () {
      final routeTarget = NotificationRouteTarget.fromRemoteMessageData({
        'payload': 'group:group-123',
      });

      expect(routeTarget, isNotNull);
      expect(routeTarget!.kind, NotificationRouteTargetKind.group);
      expect(routeTarget.groupId, 'group-123');
    });

    test(
      'fromRemoteMessageData preserves group message anchors when present',
      () {
        final routeTarget = NotificationRouteTarget.fromRemoteMessageData({
          'type': 'group_message',
          'groupId': 'group-123',
          'messageId': 'msg-123',
        });

        expect(routeTarget, isNotNull);
        expect(routeTarget!.kind, NotificationRouteTargetKind.group);
        expect(routeTarget.groupId, 'group-123');
        expect(routeTarget.messageId, 'msg-123');
      },
    );

    test(
      'GIRD-006 group image remote payload uses canonical anchored route payload',
      () {
        final routeTarget = NotificationRouteTarget.fromRemoteMessageData({
          'type': 'group_message',
          'groupId': 'group-gird006',
          'message_id': 'msg-gird006-image',
          'payloadType': 'group_message',
          'kind': 'group_offline_replay',
        });

        expect(routeTarget, isNotNull);
        expect(routeTarget!.kind, NotificationRouteTargetKind.group);
        expect(routeTarget.groupId, 'group-gird006');
        expect(routeTarget.messageId, 'msg-gird006-image');
        expect(
          routeTarget.toPayload(),
          'group:group-gird006|message:msg-gird006-image',
        );
        expect(
          NotificationRouteTarget.fromPayload(
            routeTarget.toPayload(),
          )!.messageId,
          'msg-gird006-image',
        );
      },
    );

    test(
      'fromRemoteMessageData ignores ciphertext fields while routing chat pushes',
      () {
        final routeTarget = NotificationRouteTarget.fromRemoteMessageData({
          'type': 'new_message',
          'sender_id': 'peer-cipher',
          'message_id': 'msg-cipher-1',
          'envelope_version': '2',
          'kem': 'kem',
          'ciphertext': 'ciphertext',
          'nonce': 'nonce',
        });

        expect(routeTarget, isNotNull);
        expect(routeTarget!.kind, NotificationRouteTargetKind.conversation);
        expect(routeTarget.peerId, 'peer-cipher');
      },
    );

    test(
      'fromRemoteMessageData ignores ciphertext fields while routing group pushes',
      () {
        final routeTarget = NotificationRouteTarget.fromRemoteMessageData({
          'type': 'group_message',
          'groupId': 'group-cipher',
          'message_id': 'msg-group-cipher-1',
          'kind': 'group_offline_replay',
          'payloadType': 'group_message',
          'keyEpoch': '7',
          'ciphertext': 'ciphertext',
          'nonce': 'nonce',
        });

        expect(routeTarget, isNotNull);
        expect(routeTarget!.kind, NotificationRouteTargetKind.group);
        expect(routeTarget.groupId, 'group-cipher');
        expect(routeTarget.messageId, 'msg-group-cipher-1');
      },
    );

    test('fromRemoteMessageData maps APNs-direct one-to-one payloads', () {
      final data = <String, dynamic>{
        'aps': {
          'alert': {'title': 'Alice', 'body': 'Hello'},
        },
        'type': 'new_message',
        'sender_id': 'peer-apns-123',
        'message_id': 'msg-apns-123',
      };

      final routeTarget = NotificationRouteTarget.fromRemoteMessageData(data);

      expect(data.containsKey('gcm.message_id'), isFalse);
      expect(data.containsKey('payload'), isFalse);
      expect(routeTarget, isNotNull);
      expect(routeTarget!.kind, NotificationRouteTargetKind.conversation);
      expect(routeTarget.peerId, 'peer-apns-123');
    });

    test('fromRemoteMessageData maps APNs-direct group payloads', () {
      final data = <String, dynamic>{
        'aps': {
          'alert': {'title': 'Team', 'body': 'Alice: Hello'},
        },
        'type': 'group_message',
        'groupId': 'group-apns-123',
        'message_id': 'msg-group-apns-123',
      };

      final routeTarget = NotificationRouteTarget.fromRemoteMessageData(data);

      expect(data.containsKey('gcm.message_id'), isFalse);
      expect(data.containsKey('payload'), isFalse);
      expect(routeTarget, isNotNull);
      expect(routeTarget!.kind, NotificationRouteTargetKind.group);
      expect(routeTarget.groupId, 'group-apns-123');
      expect(routeTarget.messageId, 'msg-group-apns-123');
    });

    test('fromRemoteMessageData maps FCM-shaped one-to-one route payloads', () {
      final routeTarget = NotificationRouteTarget.fromRemoteMessageData({
        'aps': {
          'alert': {'title': 'Alice', 'body': 'Hello'},
        },
        'gcm.message_id': 'fcm-msg-123',
        'type': 'new_message',
        'sender_id': 'peer-fcm-123',
        'message_id': 'msg-fcm-123',
      });

      expect(routeTarget, isNotNull);
      expect(routeTarget!.kind, NotificationRouteTargetKind.conversation);
      expect(routeTarget.peerId, 'peer-fcm-123');
    });

    test('fromRemoteMessageData maps FCM-shaped group route payloads', () {
      final routeTarget = NotificationRouteTarget.fromRemoteMessageData({
        'aps': {
          'alert': {'title': 'Team', 'body': 'Alice: Hello'},
        },
        'gcm.message_id': 'fcm-group-123',
        'type': 'group_message',
        'groupId': 'group-fcm-123',
        'message_id': 'msg-group-fcm-123',
      });

      expect(routeTarget, isNotNull);
      expect(routeTarget!.kind, NotificationRouteTargetKind.group);
      expect(routeTarget.groupId, 'group-fcm-123');
      expect(routeTarget.messageId, 'msg-group-fcm-123');
    });

    test(
      'fromRemoteMessageData maps contact_request to contact-request route',
      () {
        final routeTarget = NotificationRouteTarget.fromRemoteMessageData({
          'type': 'contact_request',
          'sender_id': 'peer-contact-123',
        });

        expect(routeTarget, isNotNull);
        expect(routeTarget!.kind, NotificationRouteTargetKind.contactRequest);
        expect(routeTarget.peerId, 'peer-contact-123');
      },
    );

    test('fromRemoteMessageData maps group_invite to intros route', () {
      final routeTarget = NotificationRouteTarget.fromRemoteMessageData({
        'type': 'group_invite',
        'groupId': 'group-123',
      });

      expect(routeTarget, isNotNull);
      expect(routeTarget!.kind, NotificationRouteTargetKind.intros);
    });

    test('fromRemoteMessageData rejects group_message with empty groupId', () {
      final routeTarget = NotificationRouteTarget.fromRemoteMessageData({
        'type': 'group_message',
        'groupId': '   ',
      });

      expect(routeTarget, isNull);
    });

    test('fromPayload maps intros to intros route', () {
      final routeTarget = NotificationRouteTarget.fromPayload('intros');

      expect(routeTarget, isNotNull);
      expect(routeTarget!.kind, NotificationRouteTargetKind.intros);
    });

    test('group payload round-trips through toPayload and fromPayload', () {
      const routeTarget = NotificationRouteTarget.group('group-xyz');

      final payload = routeTarget.toPayload();
      final parsed = NotificationRouteTarget.fromPayload(payload);

      expect(payload, 'group:group-xyz');
      expect(parsed, isNotNull);
      expect(parsed!.kind, NotificationRouteTargetKind.group);
      expect(parsed.groupId, 'group-xyz');
    });

    test(
      'anchored group payload round-trips through toPayload and fromPayload',
      () {
        const routeTarget = NotificationRouteTarget.group(
          'group-xyz',
          messageId: 'msg-xyz',
        );

        final payload = routeTarget.toPayload();
        final parsed = NotificationRouteTarget.fromPayload(payload);

        expect(payload, 'group:group-xyz|message:msg-xyz');
        expect(parsed, isNotNull);
        expect(parsed!.kind, NotificationRouteTargetKind.group);
        expect(parsed.groupId, 'group-xyz');
        expect(parsed.messageId, 'msg-xyz');
      },
    );

    test(
      'contact-request payload round-trips through toPayload and fromPayload',
      () {
        const routeTarget = NotificationRouteTarget.contactRequest(
          'peer-contact-123',
        );

        final payload = routeTarget.toPayload();
        final parsed = NotificationRouteTarget.fromPayload(payload);

        expect(payload, 'contact_request:peer-contact-123');
        expect(parsed, isNotNull);
        expect(parsed!.kind, NotificationRouteTargetKind.contactRequest);
        expect(parsed.peerId, 'peer-contact-123');
      },
    );

    test('unknown whitespace payload does not coerce to an invalid route', () {
      final parsed = NotificationRouteTarget.fromPayload('   ');

      expect(parsed, isNull);
    });

    test(
      'acceptance intros route preserves envelope identity across remote and local payloads',
      () {
        const canonicalId = 'intro-golden::accept::peer-responder';

        final remote = NotificationRouteTarget.fromRemoteMessageData({
          'type': 'intros',
          'message_id': canonicalId,
        });

        expect(remote, isNotNull);
        expect(remote!.kind, NotificationRouteTargetKind.intros);
        expect(remote.messageId, canonicalId);

        final payload = remote.toPayload();
        expect(payload, 'intros|message:$canonicalId');

        final parsed = NotificationRouteTarget.fromPayload(payload);
        expect(parsed, isNotNull);
        expect(parsed!.kind, NotificationRouteTargetKind.intros);
        expect(parsed.messageId, canonicalId);
      },
    );

    test(
      'malformed acceptance identity and group invite fail closed to generic intros',
      () {
        final failClosedRemoteData = <Map<String, dynamic>>[
          // Legacy bare introduction ID (pre-canonical relay).
          {'type': 'intros', 'message_id': 'intro-legacy'},
          // Missing sender segment.
          {'type': 'intros', 'message_id': 'intro-1::accept'},
          // Empty introduction ID.
          {'type': 'intros', 'message_id': '::accept::peer-b'},
          // Empty sender segment.
          {'type': 'intros', 'message_id': 'intro-1::accept::'},
          // Unsupported action.
          {'type': 'intros', 'message_id': 'intro-1::approve::peer-b'},
          // Group invites never become acceptance anchors, even with a
          // canonical-looking message ID.
          {
            'type': 'group_invite',
            'groupId': 'group-1',
            'message_id': 'intro-1::accept::peer-b',
          },
        ];

        for (final data in failClosedRemoteData) {
          final target = NotificationRouteTarget.fromRemoteMessageData(data);
          expect(target, isNotNull, reason: data.toString());
          expect(
            target!.kind,
            NotificationRouteTargetKind.intros,
            reason: data.toString(),
          );
          expect(target.messageId, isNull, reason: data.toString());
          expect(target.toPayload(), 'intros', reason: data.toString());
        }

        // Malformed local anchored payloads also fail closed to generic
        // Intros instead of the conversation catch-all.
        final malformedLocal = NotificationRouteTarget.fromPayload(
          'intros|message:intro-legacy',
        );
        expect(malformedLocal, isNotNull);
        expect(malformedLocal!.kind, NotificationRouteTargetKind.intros);
        expect(malformedLocal.messageId, isNull);
      },
    );
  });
}
