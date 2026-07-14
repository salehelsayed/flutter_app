import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_private_media_policy.dart';

void main() {
  group('GroupMessage', () {
    Map<String, dynamic> makeMap({
      String id = 'msg-001',
      String groupId = 'group-1',
      String senderPeerId = 'peer-sender',
      String? senderUsername = 'Alice',
      String text = 'Hello group',
      String timestamp = '2026-01-15T12:00:00.000Z',
      String? quotedMessageId,
      String? logicalDeliveryId,
      int keyGeneration = 1,
      String status = 'sent',
      int isIncoming = 1,
      String? readAt,
      String createdAt = '2026-01-15T12:00:00.000Z',
      Map<String, Object?> privateMedia = const {},
    }) {
      return {
        'id': id,
        'group_id': groupId,
        'sender_peer_id': senderPeerId,
        'sender_username': senderUsername,
        'text': text,
        'timestamp': timestamp,
        'quoted_message_id': quotedMessageId,
        'logical_delivery_id': ?logicalDeliveryId,
        'key_generation': keyGeneration,
        'status': status,
        'is_incoming': isIncoming,
        'read_at': readAt,
        'created_at': createdAt,
        ...privateMedia,
      };
    }

    test('fromMap/toMap round-trip preserves all fields', () {
      final map = makeMap();
      final model = GroupMessage.fromMap(map);
      final result = model.toMap();

      expect(result['id'], 'msg-001');
      expect(result['group_id'], 'group-1');
      expect(result['sender_peer_id'], 'peer-sender');
      expect(result['sender_username'], 'Alice');
      expect(result['text'], 'Hello group');
      expect(result['timestamp'], '2026-01-15T12:00:00.000Z');
      expect(result['quoted_message_id'], isNull);
      expect(result['key_generation'], 1);
      expect(result['status'], 'sent');
      expect(result['is_incoming'], 1);
      expect(result['read_at'], isNull);
      expect(result['created_at'], '2026-01-15T12:00:00.000Z');
    });

    test('round-trip preserves quoted_message_id', () {
      final map = makeMap(quotedMessageId: 'msg-parent-1');
      final model = GroupMessage.fromMap(map);

      expect(model.quotedMessageId, 'msg-parent-1');
      expect(model.toMap()['quoted_message_id'], 'msg-parent-1');
    });

    test('round-trip preserves logical_delivery_id', () {
      final map = makeMap(logicalDeliveryId: 'logical-delivery-1');
      final model = GroupMessage.fromMap(map);

      expect(model.logicalDeliveryId, 'logical-delivery-1');
      expect(model.toMap()['logical_delivery_id'], 'logical-delivery-1');
    });

    test('isIncoming bool correctly converts from int', () {
      final incoming = GroupMessage.fromMap(makeMap(isIncoming: 1));
      final outgoing = GroupMessage.fromMap(makeMap(isIncoming: 0));

      expect(incoming.isIncoming, true);
      expect(outgoing.isIncoming, false);
    });

    test('toMap converts isIncoming bool to int', () {
      final incoming = GroupMessage.fromMap(makeMap(isIncoming: 1));
      final outgoing = GroupMessage.fromMap(makeMap(isIncoming: 0));

      expect(incoming.toMap()['is_incoming'], 1);
      expect(outgoing.toMap()['is_incoming'], 0);
    });

    test('media defaults to empty list', () {
      final msg = GroupMessage.fromMap(makeMap());
      expect(msg.media, isEmpty);
    });

    test('can be constructed with media attachments', () {
      final attachment = MediaAttachment(
        id: 'att-1',
        messageId: 'msg-001',
        mime: 'image/jpeg',
        size: 1024,
        mediaType: 'image',
        downloadStatus: 'done',
        localPath: '/tmp/img.jpg',
        createdAt: '2026-01-15T12:00:00.000Z',
      );
      final msg = GroupMessage(
        id: 'msg-001',
        groupId: 'group-1',
        senderPeerId: 'peer-sender',
        text: 'Hello',
        timestamp: DateTime.utc(2026, 1, 15, 12),
        createdAt: DateTime.utc(2026, 1, 15, 12),
        media: [attachment],
      );
      expect(msg.media, hasLength(1));
      expect(msg.media.first.id, 'att-1');
    });

    test('copyWith preserves and replaces media', () {
      final attachment = MediaAttachment(
        id: 'att-1',
        messageId: 'msg-001',
        mime: 'image/jpeg',
        size: 1024,
        mediaType: 'image',
        downloadStatus: 'done',
        createdAt: '2026-01-15T12:00:00.000Z',
      );
      final msg = GroupMessage.fromMap(makeMap());
      expect(msg.media, isEmpty);

      final withMedia = msg.copyWith(media: [attachment]);
      expect(withMedia.media, hasLength(1));
      expect(withMedia.media.first.id, 'att-1');
      // Original unchanged
      expect(msg.media, isEmpty);
    });

    test('copyWith preserves and replaces quotedMessageId', () {
      final msg = GroupMessage.fromMap(
        makeMap(quotedMessageId: 'msg-parent-1'),
      );

      expect(msg.quotedMessageId, 'msg-parent-1');

      final cleared = msg.copyWith(quotedMessageId: null);
      final replaced = msg.copyWith(quotedMessageId: 'msg-parent-2');

      expect(cleared.quotedMessageId, isNull);
      expect(replaced.quotedMessageId, 'msg-parent-2');
      expect(msg.quotedMessageId, 'msg-parent-1');
    });

    test('copyWith preserves, replaces, and clears logicalDeliveryId', () {
      final msg = GroupMessage.fromMap(
        makeMap(logicalDeliveryId: 'logical-original'),
      );

      final preserved = msg.copyWith(text: 'changed body');
      final replaced = msg.copyWith(logicalDeliveryId: 'logical-replaced');
      final cleared = msg.copyWith(logicalDeliveryId: null);

      expect(preserved.logicalDeliveryId, 'logical-original');
      expect(replaced.logicalDeliveryId, 'logical-replaced');
      expect(cleared.logicalDeliveryId, isNull);
      expect(msg.logicalDeliveryId, 'logical-original');
    });

    test('legacy mapping defaults to an ordinary group media policy', () {
      final message = GroupMessage.fromMap(makeMap());

      expect(
        message.privateMediaPolicy,
        const GroupPrivateMediaPolicy.ordinary(),
      );
      expect(message.mediaReceivedAt, isNull);
      expect(message.mediaExpiresAt, isNull);
      expect(message.mediaLastCheckedAt, isNull);
      expect(message.mediaConsumedAt, isNull);
      expect(message.mediaExpiredAt, isNull);
      expect(message.mediaCleanupPending, isFalse);
      expect(message.toMap(), containsPair('media_policy_version', 0));
      expect(message.toMap(), containsPair('media_lifecycle', 'standard'));
      expect(message.toMap(), containsPair('media_protected', 0));
    });

    test(
      'private policy and incoming or outgoing local anchor map and copy exactly',
      () {
        GroupMessage mapped({required int isIncoming}) => GroupMessage.fromMap(
          makeMap(
            isIncoming: isIncoming,
            privateMedia: const {
              'media_policy_version': 1,
              'media_lifecycle': 'disappearing',
              'media_duration_seconds': 3600,
              'media_protected': 1,
              'media_received_at': 1000,
              'media_expires_at': 3601000,
              'media_last_checked_at': 2000,
              'media_consumed_at': null,
              'media_expired_at': null,
              'media_cleanup_pending': 0,
            },
          ),
        );

        for (final message in [mapped(isIncoming: 1), mapped(isIncoming: 0)]) {
          expect(
            message.privateMediaPolicy,
            GroupPrivateMediaPolicy.disappearing(3600),
          );
          expect(message.mediaReceivedAt, 1000);
          expect(message.mediaExpiresAt, 3601000);
          expect(message.mediaLastCheckedAt, 2000);
          expect(message.mediaConsumedAt, isNull);
          expect(message.mediaExpiredAt, isNull);
          expect(message.mediaCleanupPending, isFalse);
          expect(message.toMap(), containsPair('media_received_at', 1000));
        }

        final original = mapped(isIncoming: 1);
        final preserved = original.copyWith(text: 'changed');
        final replaced = original.copyWith(
          privateMediaPolicy: const GroupPrivateMediaPolicy.viewOnce(),
          mediaReceivedAt: 3000,
          mediaExpiresAt: null,
          mediaLastCheckedAt: 4000,
          mediaConsumedAt: 5000,
          mediaExpiredAt: null,
          mediaCleanupPending: true,
        );
        expect(preserved.privateMediaPolicy, original.privateMediaPolicy);
        expect(preserved.mediaReceivedAt, 1000);
        expect(
          replaced.privateMediaPolicy,
          const GroupPrivateMediaPolicy.viewOnce(),
        );
        expect(replaced.mediaReceivedAt, 3000);
        expect(replaced.mediaExpiresAt, isNull);
        expect(replaced.mediaLastCheckedAt, 4000);
        expect(replaced.mediaConsumedAt, 5000);
        expect(replaced.mediaExpiredAt, isNull);
        expect(replaced.mediaCleanupPending, isTrue);
      },
    );

    test(
      'inconsistent durable tuple hydrates as unsupported and clears claims',
      () {
        final message = GroupMessage.fromMap(
          makeMap(
            privateMedia: const {
              'media_policy_version': 0,
              'media_lifecycle': 'standard',
              'media_duration_seconds': null,
              'media_protected': 0,
              'media_received_at': 1000,
              'media_expires_at': null,
              'media_last_checked_at': null,
              'media_consumed_at': null,
              'media_expired_at': null,
              'media_cleanup_pending': 0,
            },
          ),
        );

        expect(message.privateMediaPolicy.isUnsupported, isTrue);
        expect(message.mediaReceivedAt, isNull);
        expect(message.mediaExpiresAt, isNull);
        expect(message.mediaConsumedAt, isNull);
        expect(message.mediaExpiredAt, isNull);
        expect(message.toMap()['media_lifecycle'], 'unsupported');
        expect(message.toMap()['media_protected'], 1);
      },
    );
  });
}
