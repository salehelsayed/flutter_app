import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/features/groups/domain/models/group_invite_payload.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/models/pending_group_invite.dart';

void main() {
  group('PendingGroupInvite', () {
    final payload = GroupInvitePayload(
      id: 'invite-1',
      groupId: 'group-1',
      groupKey: 'base64-key',
      keyEpoch: 1,
      groupConfig: {
        'name': 'Book Club',
        'groupType': 'chat',
        'description': 'A group for book lovers',
        'avatarBlobId': 'blob-1',
        'avatarMime': 'image/jpeg',
        'createdBy': 'peer-admin',
        'createdAt': '2026-04-05T12:00:00.000Z',
        'metadataUpdatedAt': '2026-04-05T12:05:00.000Z',
        'members': const [],
      },
      senderPeerId: 'peer-admin',
      senderUsername: 'Admin',
      timestamp: '2026-04-05T13:00:00.000Z',
    );

    test('fromPayload derives preview fields and expiry', () {
      final receivedAt = DateTime.utc(2026, 4, 5, 13, 0);
      final invite = PendingGroupInvite.fromPayload(
        payload,
        receivedAt: receivedAt,
      );

      expect(invite.groupId, 'group-1');
      expect(invite.groupName, 'Book Club');
      expect(invite.groupType, GroupType.chat);
      expect(invite.groupDescription, 'A group for book lovers');
      expect(invite.avatarBlobId, 'blob-1');
      expect(invite.avatarMime, 'image/jpeg');
      expect(invite.createdBy, 'peer-admin');
      expect(invite.receivedAt, receivedAt);
      expect(invite.expiresAt, receivedAt.add(pendingGroupInviteTtl));
      expect(invite.toPayload()!.groupId, 'group-1');
    });

    test('fromMap/toMap round-trip preserves fields', () {
      final invite = PendingGroupInvite.fromPayload(
        payload,
        receivedAt: DateTime.utc(2026, 4, 5, 13, 0),
      );

      final roundTrip = PendingGroupInvite.fromMap(invite.toMap());

      expect(roundTrip.groupId, invite.groupId);
      expect(roundTrip.groupName, invite.groupName);
      expect(roundTrip.senderPeerId, invite.senderPeerId);
      expect(roundTrip.metadataUpdatedAt, invite.metadataUpdatedAt);
      expect(roundTrip.expiresAt, invite.expiresAt);
    });

    test('isExpiredAt returns true on or after expiry', () {
      final invite = PendingGroupInvite.fromPayload(
        payload,
        receivedAt: DateTime.utc(2026, 4, 5, 13, 0),
      );

      expect(invite.isExpiredAt(DateTime.utc(2026, 4, 12, 12, 59)), isFalse);
      expect(invite.isExpiredAt(DateTime.utc(2026, 4, 12, 13, 0)), isTrue);
      expect(invite.isExpiredAt(DateTime.utc(2026, 4, 12, 13, 1)), isTrue);
    });
  });
}
