import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/lifecycle/handle_app_resumed.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';

import '../bridge/fake_bridge.dart';
import '../services/fake_p2p_service.dart';
import '../../shared/fakes/in_memory_group_message_repository.dart';
import '../../shared/fakes/in_memory_group_repository.dart';

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
    if (message.contains('"cmd":"group:join"')) {
      trace.add('rejoin');
    } else if (message.contains('"cmd":"group:inboxRetrieveCursor"')) {
      trace.add('drain');
    }
    return super.send(message);
  }
}

void main() {
  group('handleAppResumed group recovery', () {
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

    tearDown(() {
      p2pService.dispose();
    });

    test(
      'calls rejoin, drain, recoverStuck, retryIncompleteGroupUploads, then retryFailed',
      () async {
        final callOrder = <String>[];
        bridge = _TracingBridge(callOrder);

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

        await handleAppResumed(
          bridge: bridge,
          p2pService: p2pService,
          groupRepo: groupRepo,
          groupMsgRepo: groupMsgRepo,
          recoverStuckSendingGroupMessagesFn: () async {
            callOrder.add('recoverStuck');
            return 0;
          },
          retryIncompleteGroupUploadsFn: () async {
            callOrder.add('retryUploads');
            return 0;
          },
          retryFailedGroupMessagesFn: () async {
            callOrder.add('retryFailed');
            return 0;
          },
        );

        expect(callOrder, [
          'rejoin',
          'drain',
          'recoverStuck',
          'retryUploads',
          'retryFailed',
        ]);
      },
    );

    test('feature gate disables group recovery callbacks', () async {
      p2pService = FakeP2PService(
        initialState: const NodeState(
          isStarted: true,
          peerId: 'my-peer',
          circuitAddresses: ['/p2p-circuit/addr1'],
          needsGroupRecovery: true,
          featureFlags: {'enableResumeGroupRecovery': false},
        ),
      );

      var recoverCalled = false;
      var retryUploadsCalled = false;
      var retryCalled = false;

      await handleAppResumed(
        bridge: bridge,
        p2pService: p2pService,
        groupRepo: groupRepo,
        groupMsgRepo: groupMsgRepo,
        recoverStuckSendingGroupMessagesFn: () async {
          recoverCalled = true;
          return 0;
        },
        retryIncompleteGroupUploadsFn: () async {
          retryUploadsCalled = true;
          return 0;
        },
        retryFailedGroupMessagesFn: () async {
          retryCalled = true;
          return 0;
        },
      );

      expect(recoverCalled, isFalse);
      expect(retryUploadsCalled, isFalse);
      expect(retryCalled, isFalse);
    });
  });
}
