import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/app/lifecycle/handle_app_resumed.dart';
import 'package:flutter_app/features/groups/application/recover_stuck_sending_group_messages_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';

import '../bridge/fake_bridge.dart';
import '../../shared/fakes/in_memory_group_message_repository.dart';
import '../../shared/fakes/in_memory_group_repository.dart';
import '../services/fake_p2p_service.dart';

class _TracingBridge extends FakeBridge {
  final List<String> trace;

  _TracingBridge(this.trace)
    : super(
        initialResponses: {
          'group:join': {'ok': true},
          'group:inboxRetrieveCursor': {
            'ok': true,
            'messages': [],
            'cursor': '',
          },
        },
      );

  @override
  Future<String> send(String message) async {
    final parsed = jsonDecode(message) as Map<String, dynamic>;
    final cmd = parsed['cmd'] as String?;

    if (cmd == 'group:join') {
      trace.add('rejoin');
    } else if (cmd == 'group:inboxRetrieveCursor') {
      trace.add('drain');
    }

    return super.send(message);
  }
}

void main() {
  group('handleAppResumed — group stuck sending recovery', () {
    late FakeBridge bridge;
    late FakeP2PService p2pService;
    late InMemoryGroupRepository groupRepo;
    late InMemoryGroupMessageRepository groupMsgRepo;

    setUp(() {
      bridge = _TracingBridge([]);
      p2pService = FakeP2PService(
        initialState: const NodeState(
          isStarted: true,
          peerId: 'my-peer',
          circuitAddresses: ['/p2p-circuit/addr1'],
          needsGroupRecovery: true,
        ),
      );
      groupRepo = InMemoryGroupRepository();
      groupMsgRepo = InMemoryGroupMessageRepository();
    });

    test('calls rejoin, drain, recoverStuck, then retryFailed', () async {
      await groupRepo.saveGroup(
        GroupModel(
          id: 'group-1',
          name: 'Test Group',
          type: GroupType.chat,
          topicName: 'topic-1',
          createdAt: DateTime.utc(2026, 1, 15, 12),
          createdBy: 'peer-admin',
          myRole: GroupRole.member,
        ),
      );
      await groupRepo.saveKey(
        GroupKeyInfo(
          groupId: 'group-1',
          keyGeneration: 0,
          encryptedKey: 'encrypted-key',
          createdAt: DateTime.utc(2026, 1, 15, 12),
        ),
      );
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: 'peer-2',
          username: 'Bob',
          role: MemberRole.writer,
          publicKey: 'pk-2',
          joinedAt: DateTime.utc(2026, 1, 15, 12),
        ),
      );

      final callOrder = <String>[];
      bridge = _TracingBridge(callOrder);

      await handleAppResumed(
        bridge: bridge,
        p2pService: p2pService,
        groupRepo: groupRepo,
        groupMsgRepo: groupMsgRepo,
        recoverStuckSendingGroupMessagesFn: () async {
          callOrder.add('recoverStuck');
          return 0;
        },
        retryFailedGroupMessagesFn: () async {
          callOrder.add('retryFailed');
          return 0;
        },
      );

      expect(callOrder, ['rejoin', 'drain', 'recoverStuck', 'retryFailed']);
    });

    test(
      'resume recovery does not immediately fail a freshly retried old group row',
      () async {
        final oldLogicalTimestamp = DateTime.now().toUtc().subtract(
          const Duration(minutes: 5),
        );
        final freshAttemptTimestamp = DateTime.now().toUtc().subtract(
          const Duration(seconds: 10),
        );
        await groupMsgRepo.saveMessage(
          GroupMessage(
            id: 'fresh-retry-old-logical',
            groupId: 'group-1',
            senderPeerId: 'my-peer',
            senderUsername: 'Alice',
            text: 'Retry still in flight',
            timestamp: oldLogicalTimestamp,
            status: 'sending',
            isIncoming: false,
            createdAt: oldLogicalTimestamp,
            lastSendAttemptAt: freshAttemptTimestamp,
          ),
        );

        await handleAppResumed(
          bridge: bridge,
          p2pService: p2pService,
          groupRepo: groupRepo,
          groupMsgRepo: groupMsgRepo,
          recoverStuckSendingGroupMessagesFn: () =>
              recoverStuckSendingGroupMessages(
                groupMsgRepo: groupMsgRepo,
                threshold: const Duration(seconds: 30),
              ),
          retryFailedGroupMessagesFn: () async => 0,
        );

        final message = await groupMsgRepo.getMessage(
          'fresh-retry-old-logical',
        );
        expect(message, isNotNull);
        expect(message!.status, 'sending');
      },
    );
  });
}
