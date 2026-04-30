import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/groups/application/handle_incoming_group_invite_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_invite_payload.dart';
import 'package:flutter_app/features/groups/domain/models/group_invite_consumption.dart';
import 'package:flutter_app/features/groups/domain/models/group_invite_revocation.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../features/contacts/domain/repositories/fake_contact_repository.dart';
import '../../../shared/fakes/in_memory_group_repository.dart';
import '../../../shared/fakes/in_memory_pending_group_invite_repository.dart';

void main() {
  late InMemoryGroupRepository groupRepo;
  late InMemoryPendingGroupInviteRepository pendingInviteRepo;
  late FakeContactRepository contactRepo;
  late FakeBridge bridge;

  ContactModel aliceContact() {
    return const ContactModel(
      peerId: '12D3KooWAlice',
      publicKey: 'alicePubKey64',
      rendezvous: '/ip4/0.0.0.0',
      username: 'Alice',
      signature: 'sig',
      scannedAt: '2026-01-01T00:00:00Z',
      mlKemPublicKey: 'aliceMlKem64',
    );
  }

  ChatMessage makeMessage({
    String groupId = 'grp-abc123',
    String inviteId = 'invite-1',
  }) {
    final payload = GroupInvitePayload(
      id: inviteId,
      groupId: groupId,
      groupKey: 'base64-key',
      keyEpoch: 1,
      groupConfig: {
        'name': 'Book Club',
        'groupType': 'chat',
        'description': 'A group for book lovers',
        'members': const [],
        'createdBy': '12D3KooWAlice',
        'createdAt': '2026-03-02T00:00:00.000Z',
      },
      senderPeerId: '12D3KooWAlice',
      senderUsername: 'Alice',
      timestamp: '2026-03-02T12:00:00.000Z',
    );
    return ChatMessage(
      from: '12D3KooWAlice',
      to: 'myPeerId',
      content: payload.toJson(),
      timestamp: '2026-03-02T12:00:00.000Z',
      isIncoming: true,
    );
  }

  setUp(() {
    groupRepo = InMemoryGroupRepository();
    pendingInviteRepo = InMemoryPendingGroupInviteRepository();
    contactRepo = FakeContactRepository()..seed([aliceContact()]);
    bridge = FakeBridge();
  });

  group('storeIncomingPendingGroupInvite', () {
    test(
      'stores validated invite as pending without creating group state',
      () async {
        final (result, invite) = await storeIncomingPendingGroupInvite(
          message: makeMessage(),
          groupRepo: groupRepo,
          pendingInviteRepo: pendingInviteRepo,
          contactRepo: contactRepo,
          bridge: bridge,
        );

        expect(result, StorePendingGroupInviteResult.storedPending);
        expect(invite, isNotNull);
        expect(invite!.groupName, 'Book Club');
        expect(await groupRepo.getGroup('grp-abc123'), isNull);
        expect(
          await pendingInviteRepo.getPendingInvite('grp-abc123'),
          isNotNull,
        );
      },
    );

    test('ignores delayed invite copy when invite was revoked', () async {
      final revokedAt = DateTime.utc(2026, 4, 29, 12);
      await pendingInviteRepo.saveRevokedInvite(
        GroupInviteRevocation(
          inviteId: 'invite-1',
          groupId: 'grp-abc123',
          revokedAt: revokedAt,
          expiresAt: revokedAt.add(const Duration(days: 7)),
          revokedBy: '12D3KooWAlice',
        ),
      );

      final (result, invite) = await storeIncomingPendingGroupInvite(
        message: makeMessage(),
        groupRepo: groupRepo,
        pendingInviteRepo: pendingInviteRepo,
        contactRepo: contactRepo,
        bridge: bridge,
        receivedAt: revokedAt.add(const Duration(minutes: 10)),
      );

      expect(result, StorePendingGroupInviteResult.revoked);
      expect(invite, isNull);
      expect(await pendingInviteRepo.getPendingInvite('grp-abc123'), isNull);
      expect(await groupRepo.getGroup('grp-abc123'), isNull);
    });

    test('ignores delayed invite copy when invite was already used', () async {
      final consumedAt = DateTime.utc(2026, 4, 29, 12);
      await pendingInviteRepo.saveConsumedInvite(
        GroupInviteConsumption(
          inviteId: 'invite-1',
          groupId: 'grp-abc123',
          consumedAt: consumedAt,
          expiresAt: consumedAt.add(const Duration(days: 7)),
        ),
      );

      final (result, invite) = await storeIncomingPendingGroupInvite(
        message: makeMessage(),
        groupRepo: groupRepo,
        pendingInviteRepo: pendingInviteRepo,
        contactRepo: contactRepo,
        bridge: bridge,
        receivedAt: consumedAt.add(const Duration(minutes: 10)),
      );

      expect(result, StorePendingGroupInviteResult.alreadyUsed);
      expect(invite, isNull);
      expect(await pendingInviteRepo.getPendingInvite('grp-abc123'), isNull);
      expect(await groupRepo.getGroup('grp-abc123'), isNull);
    });

    test('returns duplicateGroup when group already exists', () async {
      await groupRepo.saveGroup(
        GroupModel(
          id: 'grp-abc123',
          name: 'Joined Group',
          type: GroupType.chat,
          topicName: '/mknoon/group/grp-abc123',
          createdAt: DateTime.utc(2026, 3, 2),
          createdBy: '12D3KooWAlice',
          myRole: GroupRole.member,
        ),
      );

      final (result, invite) = await storeIncomingPendingGroupInvite(
        message: makeMessage(),
        groupRepo: groupRepo,
        pendingInviteRepo: pendingInviteRepo,
        contactRepo: contactRepo,
        bridge: bridge,
      );

      expect(result, StorePendingGroupInviteResult.duplicateGroup);
      expect(invite, isNull);
      expect(pendingInviteRepo.count, 0);
    });

    test('returns unknownSender when contact is missing', () async {
      contactRepo.seed([]);

      final (result, invite) = await storeIncomingPendingGroupInvite(
        message: makeMessage(),
        groupRepo: groupRepo,
        pendingInviteRepo: pendingInviteRepo,
        contactRepo: contactRepo,
        bridge: bridge,
      );

      expect(result, StorePendingGroupInviteResult.unknownSender);
      expect(invite, isNull);
      expect(pendingInviteRepo.count, 0);
    });
  });
}
