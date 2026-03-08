import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';

void main() {
  group('GroupMessage', () {
    Map<String, dynamic> makeMap({
      String id = 'msg-001',
      String groupId = 'group-1',
      String senderPeerId = 'peer-sender',
      String? senderUsername = 'Alice',
      String text = 'Hello group',
      String timestamp = '2026-01-15T12:00:00.000Z',
      int keyGeneration = 1,
      String status = 'sent',
      int isIncoming = 1,
      String? readAt,
      String createdAt = '2026-01-15T12:00:00.000Z',
    }) {
      return {
        'id': id,
        'group_id': groupId,
        'sender_peer_id': senderPeerId,
        'sender_username': senderUsername,
        'text': text,
        'timestamp': timestamp,
        'key_generation': keyGeneration,
        'status': status,
        'is_incoming': isIncoming,
        'read_at': readAt,
        'created_at': createdAt,
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
      expect(result['key_generation'], 1);
      expect(result['status'], 'sent');
      expect(result['is_incoming'], 1);
      expect(result['read_at'], isNull);
      expect(result['created_at'], '2026-01-15T12:00:00.000Z');
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
  });
}
