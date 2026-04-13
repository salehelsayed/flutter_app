import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/features/groups/application/accept_pending_group_invite_use_case.dart';
import 'package:flutter_app/features/groups/application/group_message_listener.dart';
import 'package:flutter_app/features/groups/domain/models/group_invite_payload.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/models/pending_group_invite.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../conversation/domain/repositories/fake_reaction_repository.dart';
import '../../../shared/fakes/in_memory_group_message_repository.dart';
import '../../../shared/fakes/in_memory_group_repository.dart';
import '../../../shared/fakes/in_memory_pending_group_invite_repository.dart';

void main() {
  late InMemoryPendingGroupInviteRepository pendingInviteRepo;
  late InMemoryGroupRepository groupRepo;
  late InMemoryGroupMessageRepository msgRepo;
  late FakeBridge bridge;

  PendingGroupInvite makeInvite({DateTime? receivedAt}) {
    final effectiveReceivedAt = (receivedAt ?? DateTime.now().toUtc()).toUtc();
    final createdAt = effectiveReceivedAt.subtract(const Duration(hours: 6));
    final inviteTimestamp = createdAt.add(const Duration(minutes: 5));
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
        'createdAt': createdAt.toIso8601String(),
      },
      senderPeerId: '12D3KooWAlice',
      senderUsername: 'Alice',
      timestamp: inviteTimestamp.toIso8601String(),
    );
    return PendingGroupInvite.fromPayload(
      payload,
      receivedAt: effectiveReceivedAt,
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

    test(
      'accept replays backlog reactions when reactionRepo is provided',
      () async {
        final backlogTimestamp = DateTime.now()
            .toUtc()
            .subtract(const Duration(minutes: 5))
            .toIso8601String();
        final reactionTimestamp = DateTime.now()
            .toUtc()
            .subtract(const Duration(minutes: 4))
            .toIso8601String();
        final reactionRepo = FakeReactionRepository();
        final listener = GroupMessageListener(
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          bridge: bridge,
          getSelfPeerId: () async => 'peer-self',
          reactionRepo: reactionRepo,
        );
        addTearDown(listener.dispose);

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
                'timestamp': backlogTimestamp,
              }),
            },
            {
              'from': '12D3KooWAlice',
              'message': jsonEncode({
                'groupId': 'grp-abc123',
                'type': 'group_reaction',
                'senderId': '12D3KooWAlice',
                'reaction': jsonEncode({
                  'id': 'reaction-1',
                  'messageId': 'offline-msg-1',
                  'emoji': '👍',
                  'action': 'add',
                  'senderPeerId': '12D3KooWAlice',
                  'timestamp': reactionTimestamp,
                }),
                'timestamp': reactionTimestamp,
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
          reactionRepo: reactionRepo,
          groupMessageListener: listener,
        );

        expect(result, AcceptPendingGroupInviteResult.success);
        expect(group, isNotNull);
        expect(msgRepo.count, 1);

        final reactions = await reactionRepo.getReactionsForMessage(
          'offline-msg-1',
        );
        expect(reactions, hasLength(1));
        expect(reactions.single.senderPeerId, '12D3KooWAlice');
        expect(reactions.single.emoji, '👍');
      },
    );

    test(
      'successful accept publishes a durable join event for the group',
      () async {
        await pendingInviteRepo.savePendingInvite(makeInvite());

        final (result, group) = await acceptPendingGroupInvite(
          pendingInviteRepo: pendingInviteRepo,
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          bridge: bridge,
          groupId: 'grp-abc123',
          senderPeerId: '12D3KooWReceiver',
          senderPublicKey: 'receiver-public-key',
          senderPrivateKey: 'receiver-private-key',
          senderUsername: 'Receiver',
        );

        expect(result, AcceptPendingGroupInviteResult.success);
        expect(group, isNotNull);
        expect(bridge.commandLog, contains('group:publish'));
        expect(bridge.commandLog, contains('group:inboxStore'));
        expect(msgRepo.count, 1);

        final latestMessage = await msgRepo.getLatestMessage('grp-abc123');
        expect(latestMessage, isNotNull);
        expect(latestMessage!.text, 'Receiver joined the group');

        final publishMessage = bridge.sentMessages.firstWhere((message) {
          final parsed = jsonDecode(message) as Map<String, dynamic>;
          return parsed['cmd'] == 'group:publish';
        });
        final publishPayload =
            (jsonDecode(publishMessage) as Map<String, dynamic>)['payload']
                as Map<String, dynamic>;
        final sysText =
            jsonDecode(publishPayload['text'] as String)
                as Map<String, dynamic>;
        expect(sysText['__sys'], 'member_joined');
        expect(sysText['member']['peerId'], '12D3KooWReceiver');
        expect(sysText['member']['username'], 'Receiver');
      },
    );

    test(
      'bridgeError keeps a durable join owner and clears the pending invite row',
      () async {
        await pendingInviteRepo.savePendingInvite(makeInvite());
        bridge.responses['group:join'] = {
          'ok': false,
          'errorCode': 'JOIN_FAILED',
        };
        bridge.responses['group:publish'] = {
          'ok': false,
          'errorCode': 'PUBLISH_FAILED',
        };

        final (result, group) = await acceptPendingGroupInvite(
          pendingInviteRepo: pendingInviteRepo,
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          bridge: bridge,
          groupId: 'grp-abc123',
          senderPeerId: '12D3KooWReceiver',
          senderPublicKey: 'receiver-public-key',
          senderPrivateKey: 'receiver-private-key',
          senderUsername: 'Receiver',
        );

        expect(result, AcceptPendingGroupInviteResult.bridgeError);
        expect(group, isNotNull);
        expect(group!.id, 'grp-abc123');
        expect(await pendingInviteRepo.getPendingInvite('grp-abc123'), isNull);
        expect(await groupRepo.getGroup('grp-abc123'), isNotNull);
        expect(await groupRepo.getLatestKey('grp-abc123'), isNotNull);
        expect(msgRepo.count, 1);
        expect(bridge.commandLog, contains('group:publish'));
        expect(bridge.commandLog, contains('group:inboxStore'));

        final latestMessage = await msgRepo.getLatestMessage('grp-abc123');
        expect(latestMessage, isNotNull);
        expect(latestMessage!.text, 'Receiver joined the group');
      },
    );

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
