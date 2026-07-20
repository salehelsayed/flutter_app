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
      String? inviterMlKemPublicKey,
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
        inviterMemberSnapshot: {
          'peerId': 'peer-admin',
          'username': 'Admin',
          'role': 'admin',
          'publicKey': 'pk-admin',
          'mlKemPublicKey': ?inviterMlKemPublicKey,
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

    test(
      'G1: fromPayload extracts inviter mlKemPublicKey from the freshness proof snapshot',
      () {
        final keyedPayload = GroupInvitePayload(
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
            inviterMlKemPublicKey: 'adminMlKem64',
          ),
        );

        final invite = PendingGroupInvite.fromPayload(
          keyedPayload,
          receivedAt: DateTime.utc(2026, 4, 5, 13, 0),
        );

        expect(invite.mlKemPublicKey, 'adminMlKem64');
      },
    );

    test(
      'G1: fromPayload leaves mlKemPublicKey null when the proof carries no key',
      () {
        // The shared `payload` has a proof without an mlKemPublicKey.
        final invite = PendingGroupInvite.fromPayload(
          payload,
          receivedAt: DateTime.utc(2026, 4, 5, 13, 0),
        );

        expect(invite.mlKemPublicKey, isNull);
      },
    );

    test('G1: toMap/fromMap round-trips mlKemPublicKey', () {
      final fixedTime = DateTime.utc(2026, 4, 5, 13);
      final invite = PendingGroupInvite(
        groupId: 'group-1',
        inviteId: 'invite-1',
        payloadJson: '{}',
        groupName: 'Book Club',
        groupType: GroupType.chat,
        senderPeerId: 'peer-admin',
        senderUsername: 'Admin',
        mlKemPublicKey: 'adminMlKem64',
        createdBy: 'peer-admin',
        createdAt: fixedTime,
        receivedAt: fixedTime,
        expiresAt: fixedTime,
      );

      final map = invite.toMap();
      expect(map['inviter_mlkem_public_key'], 'adminMlKem64');

      final roundTrip = PendingGroupInvite.fromMap(
        Map<String, dynamic>.from(map),
      );
      expect(roundTrip.mlKemPublicKey, 'adminMlKem64');
    });

    test('G1: fromMap tolerates a legacy row missing the inviter key', () {
      final legacyMap = <String, dynamic>{
        'group_id': 'group-1',
        'invite_id': 'invite-1',
        'payload_json': '{}',
        'group_name': 'Book Club',
        'group_type': 'chat',
        'sender_peer_id': 'peer-admin',
        'sender_username': 'Admin',
        'created_by': 'peer-admin',
        'created_at': '2026-04-05T13:00:00.000Z',
        'received_at': '2026-04-05T13:00:00.000Z',
        'expires_at': '2026-04-08T13:00:00.000Z',
      };

      final invite = PendingGroupInvite.fromMap(legacyMap);
      expect(invite.mlKemPublicKey, isNull);
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
