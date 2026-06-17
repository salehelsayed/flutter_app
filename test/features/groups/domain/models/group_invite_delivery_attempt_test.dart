import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/features/groups/domain/models/group_invite_delivery_attempt.dart';

void main() {
  group('GroupInviteDeliveryStatus', () {
    test('revoked and declined round-trip through toValue/fromValue', () {
      expect(GroupInviteDeliveryStatus.revoked.toValue(), 'revoked');
      expect(GroupInviteDeliveryStatus.declined.toValue(), 'declined');
      expect(
        GroupInviteDeliveryStatus.fromValue('revoked'),
        GroupInviteDeliveryStatus.revoked,
      );
      expect(
        GroupInviteDeliveryStatus.fromValue('declined'),
        GroupInviteDeliveryStatus.declined,
      );
    });

    test('an unrecognized future value degrades to unknown (no throw)', () {
      // Forward-compat: a status written by a newer build must not crash an
      // older reader.
      expect(
        GroupInviteDeliveryStatus.fromValue('some_future_status'),
        GroupInviteDeliveryStatus.unknown,
      );
      expect(
        GroupInviteDeliveryStatus.fromValue(null),
        GroupInviteDeliveryStatus.unknown,
      );
    });
  });

  group('GroupInviteDeliveryAttempt invite_id', () {
    test('round-trips through toMap/fromMap', () {
      final attempt = GroupInviteDeliveryAttempt(
        groupId: 'g1',
        peerId: 'p1',
        status: GroupInviteDeliveryStatus.sent,
        attemptedAt: DateTime.utc(2026, 6, 17),
        updatedAt: DateTime.utc(2026, 6, 17),
        inviteId: 'invite-xyz',
      );
      final map = attempt.toMap();
      expect(map['invite_id'], 'invite-xyz');

      final restored = GroupInviteDeliveryAttempt.fromMap(map);
      expect(restored.inviteId, 'invite-xyz');
    });

    test('fromMap tolerates a missing invite_id (legacy rows)', () {
      final restored = GroupInviteDeliveryAttempt.fromMap({
        'group_id': 'g1',
        'peer_id': 'p1',
        'status': 'sent',
        'attempted_at': '2026-06-17T00:00:00.000Z',
        'updated_at': '2026-06-17T00:00:00.000Z',
      });
      expect(restored.inviteId, isNull);
    });

    test('copyWith preserves invite_id and can update it', () {
      final attempt = GroupInviteDeliveryAttempt(
        groupId: 'g1',
        peerId: 'p1',
        status: GroupInviteDeliveryStatus.sent,
        attemptedAt: DateTime.utc(2026, 6, 17),
        updatedAt: DateTime.utc(2026, 6, 17),
        inviteId: 'invite-1',
      );
      expect(
        attempt.copyWith(status: GroupInviteDeliveryStatus.revoked).inviteId,
        'invite-1',
      );
      expect(attempt.copyWith(inviteId: 'invite-2').inviteId, 'invite-2');
    });
  });
}
