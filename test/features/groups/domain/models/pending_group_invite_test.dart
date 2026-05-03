import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/features/groups/application/group_config_payload.dart';
import 'package:flutter_app/features/groups/domain/models/group_invite_payload.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/models/pending_group_invite.dart';

void main() {
  group('PendingGroupInvite', () {
    GroupInviteMembershipFreshnessProof makeFreshnessProof({
      required String inviteId,
      required String groupId,
      required Map<String, dynamic> groupConfig,
      required DateTime issuedAt,
    }) {
      final stateHash = buildGroupConfigStateHash(
        groupId: groupId,
        groupConfig: groupConfig,
      );
      return GroupInviteMembershipFreshnessProof(
        inviteId: inviteId,
        groupId: groupId,
        recipientPeerId: 'peer-recipient',
        inviterPeerId: 'peer-admin',
        inviterPublicKey: 'pk-admin',
        keyEpoch: 1,
        groupConfigStateHash: stateHash,
        membershipWatermark: stateHash,
        issuedAt: issuedAt.toUtc(),
        expiresAt: issuedAt.toUtc().add(groupInviteMembershipFreshnessTtl),
        inviterMemberSnapshot: const {
          'peerId': 'peer-admin',
          'username': 'Admin',
          'role': 'admin',
          'publicKey': 'pk-admin',
        },
      );
    }

    final Map<String, dynamic> groupConfig = {
      'name': 'Book Club',
      'groupType': 'chat',
      'description': 'A group for book lovers',
      'avatarBlobId': 'blob-1',
      'avatarMime': 'image/jpeg',
      'createdBy': 'peer-admin',
      'createdAt': '2026-04-05T12:00:00.000Z',
      'metadataUpdatedAt': '2026-04-05T12:05:00.000Z',
      'members': [
        {
          'peerId': 'peer-admin',
          'username': 'Admin',
          'role': 'admin',
          'publicKey': 'pk-admin',
        },
        {
          'peerId': 'peer-recipient',
          'username': 'Recipient',
          'role': 'writer',
          'publicKey': 'pk-recipient',
        },
      ],
    };
    final issuedAt = DateTime.utc(2026, 4, 5, 13);
    final payload = GroupInvitePayload(
      id: 'invite-1',
      groupId: 'group-1',
      groupKey: 'base64-key',
      keyEpoch: 1,
      groupConfig: groupConfig,
      senderPeerId: 'peer-admin',
      senderUsername: 'Admin',
      timestamp: '2026-04-05T13:00:00.000Z',
      recipientPeerId: 'peer-recipient',
      invitePolicy: GroupInvitePolicy(
        expiresAt: DateTime.utc(2026, 4, 8, 13),
        allowedDevices: const ['peer-recipient'],
        assignedRole: 'writer',
        canInviteOthers: false,
        joinMaterialKind: GroupInvitePolicy.inlineGroupKeyKind,
        keyEpoch: 1,
      ),
      membershipFreshnessProof: makeFreshnessProof(
        inviteId: 'invite-1',
        groupId: 'group-1',
        groupConfig: groupConfig,
        issuedAt: issuedAt,
      ),
    ).withInviteSignature(signature: 'signed-invite-by-admin');

    test('fromPayload derives preview fields and policy-clamped expiry', () {
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
      expect(invite.expiresAt, DateTime.utc(2026, 4, 8, 13));
      expect(invite.toPayload()!.groupId, 'group-1');
    });

    test('IJ001 clamps sender policy expiry no later than local TTL', () {
      final receivedAt = DateTime.utc(2026, 4, 5, 13, 0);
      final longPolicyPayload = GroupInvitePayload(
        id: payload.id,
        groupId: payload.groupId,
        groupKey: payload.groupKey,
        keyEpoch: payload.keyEpoch,
        groupConfig: payload.groupConfig,
        senderPeerId: payload.senderPeerId,
        senderUsername: payload.senderUsername,
        timestamp: payload.timestamp,
        recipientPeerId: payload.recipientPeerId,
        invitePolicy: GroupInvitePolicy(
          expiresAt: DateTime.utc(2026, 5, 5, 13),
          allowedDevices: const ['peer-recipient'],
          assignedRole: 'writer',
          canInviteOthers: false,
          joinMaterialKind: GroupInvitePolicy.inlineGroupKeyKind,
          keyEpoch: 1,
        ),
        membershipFreshnessProof: makeFreshnessProof(
          inviteId: payload.id,
          groupId: payload.groupId,
          groupConfig: payload.groupConfig,
          issuedAt: issuedAt,
        ),
      ).withInviteSignature(signature: 'signed-invite-by-admin');

      final invite = PendingGroupInvite.fromPayload(
        longPolicyPayload,
        receivedAt: receivedAt,
      );

      expect(invite.expiresAt, receivedAt.add(pendingGroupInviteTtl));
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

      expect(invite.isExpiredAt(DateTime.utc(2026, 4, 8, 12, 59)), isFalse);
      expect(invite.isExpiredAt(DateTime.utc(2026, 4, 8, 13, 0)), isTrue);
      expect(invite.isExpiredAt(DateTime.utc(2026, 4, 8, 13, 1)), isTrue);
    });
  });
}
