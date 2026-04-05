import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/features/groups/application/accept_pending_group_invite_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_invite_payload.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/models/pending_group_invite.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../shared/fakes/in_memory_group_message_repository.dart';
import '../../../shared/fakes/in_memory_group_repository.dart';
import '../../../shared/fakes/in_memory_pending_group_invite_repository.dart';

void main() {
  late InMemoryPendingGroupInviteRepository pendingInviteRepo;
  late InMemoryGroupRepository groupRepo;
  late InMemoryGroupMessageRepository msgRepo;
  late FakeBridge bridge;

  PendingGroupInvite makeInvite({DateTime? receivedAt}) {
    final payload = GroupInvitePayload(
      id: 'invite-1',
      groupId: 'grp-abc123',
      groupKey: 'base64-key',
      keyEpoch: 1,
      groupConfig: {
        'name': 'Book Club',
        'groupType': 'chat',
        'description': 'A group for book lovers',
        'members': [
          {
            'peerId': '12D3KooWAlice',
            'username': 'Alice',
            'role': 'admin',
            'publicKey': 'alicePubKey64',
            'mlKemPublicKey': 'aliceMlKem64',
          },
        ],
        'createdBy': '12D3KooWAlice',
        'createdAt': '2026-03-02T00:00:00.000Z',
      },
      senderPeerId: '12D3KooWAlice',
      senderUsername: 'Alice',
      timestamp: '2026-03-02T12:00:00.000Z',
    );
    return PendingGroupInvite.fromPayload(
      payload,
      receivedAt: receivedAt ?? DateTime.utc(2026, 4, 5, 13, 0),
    );
  }

  setUp(() {
    pendingInviteRepo = InMemoryPendingGroupInviteRepository();
    groupRepo = InMemoryGroupRepository();
    msgRepo = InMemoryGroupMessageRepository();
    bridge = FakeBridge();
  });

  group('acceptPendingGroupInvite', () {
    test('accepts pending invite, persists group, and drains inbox', () async {
      final inboxTimestamp = DateTime.now().toUtc().subtract(
        const Duration(hours: 1),
      );
      await pendingInviteRepo.savePendingInvite(makeInvite());
      bridge.responses['group:inboxRetrieveCursor'] = {
        'ok': true,
        'messages': [
          {
            'from': '12D3KooWAlice',
            'message': jsonEncode({
              'groupId': 'grp-abc123',
              'messageId': 'offline-msg-1',
              'senderId': '12D3KooWAlice',
              'senderUsername': 'Alice',
              'keyEpoch': 1,
              'text': 'Welcome back',
              'timestamp': inboxTimestamp.toIso8601String(),
            }),
          },
        ],
        'cursor': '',
      };

      final (result, group) = await acceptPendingGroupInvite(
        pendingInviteRepo: pendingInviteRepo,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        bridge: bridge,
        groupId: 'grp-abc123',
      );

      expect(result, AcceptPendingGroupInviteResult.success);
      expect(group, isNotNull);
      expect(group!.name, 'Book Club');
      expect(await pendingInviteRepo.getPendingInvite('grp-abc123'), isNull);
      expect(await groupRepo.getLatestKey('grp-abc123'), isNotNull);
      expect(msgRepo.count, 1);
      expect(bridge.commandLog, contains('group:join'));
      expect(bridge.commandLog, contains('group:inboxRetrieveCursor'));
    });

    test('returns expired and removes stale invite', () async {
      await pendingInviteRepo.savePendingInvite(
        makeInvite(receivedAt: DateTime.utc(2026, 4, 1, 13, 0)),
      );

      final (result, group) = await acceptPendingGroupInvite(
        pendingInviteRepo: pendingInviteRepo,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        bridge: bridge,
        groupId: 'grp-abc123',
        now: DateTime.utc(2026, 4, 12, 13, 0),
      );

      expect(result, AcceptPendingGroupInviteResult.expired);
      expect(group, isNull);
      expect(await pendingInviteRepo.getPendingInvite('grp-abc123'), isNull);
      expect(await groupRepo.getGroup('grp-abc123'), isNull);
    });

    test(
      'returns duplicateGroup and removes pending row when group already exists',
      () async {
        await pendingInviteRepo.savePendingInvite(makeInvite());
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

        final (result, group) = await acceptPendingGroupInvite(
          pendingInviteRepo: pendingInviteRepo,
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          bridge: bridge,
          groupId: 'grp-abc123',
        );

        expect(result, AcceptPendingGroupInviteResult.duplicateGroup);
        expect(group, isNull);
        expect(await pendingInviteRepo.getPendingInvite('grp-abc123'), isNull);
      },
    );

    test(
      'accepting on one device does not clear the sibling device pending invite',
      () async {
        final phonePendingInviteRepo = InMemoryPendingGroupInviteRepository();
        final tabletPendingInviteRepo = InMemoryPendingGroupInviteRepository();
        final phoneGroupRepo = InMemoryGroupRepository();
        final tabletGroupRepo = InMemoryGroupRepository();
        final phoneMsgRepo = InMemoryGroupMessageRepository();
        final phoneBridge = FakeBridge();

        await phonePendingInviteRepo.savePendingInvite(makeInvite());
        await tabletPendingInviteRepo.savePendingInvite(makeInvite());

        final (result, group) = await acceptPendingGroupInvite(
          pendingInviteRepo: phonePendingInviteRepo,
          groupRepo: phoneGroupRepo,
          msgRepo: phoneMsgRepo,
          bridge: phoneBridge,
          groupId: 'grp-abc123',
        );

        expect(result, AcceptPendingGroupInviteResult.success);
        expect(group, isNotNull);
        expect(
          await phonePendingInviteRepo.getPendingInvite('grp-abc123'),
          isNull,
        );
        expect(
          await tabletPendingInviteRepo.getPendingInvite('grp-abc123'),
          isNotNull,
        );
        expect(await tabletGroupRepo.getGroup('grp-abc123'), isNull);
      },
    );
  });
}
