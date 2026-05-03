import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/lifecycle/handle_app_resumed.dart';
import 'package:flutter_app/features/groups/application/group_offline_replay_envelope.dart';
import 'package:flutter_app/features/groups/application/group_message_listener.dart';
import 'package:flutter_app/features/groups/application/group_recovery_gate.dart';
import 'package:flutter_app/features/groups/application/remove_group_member_use_case.dart';
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

class _BlockingDrainBridge extends FakeBridge {
  _BlockingDrainBridge({required this.messages})
    : super(
        initialResponses: {
          'group:join': {'ok': true},
          'group:acknowledgeRecovery': {'ok': true},
          'group:leave': {'ok': true},
        },
      );

  final List<Map<String, dynamic>> messages;
  final Completer<void> drainStarted = Completer<void>();
  final Completer<void> allowDrain = Completer<void>();

  @override
  Future<String> send(String message) async {
    final parsed = jsonDecode(message) as Map<String, dynamic>;
    final cmd = parsed['cmd'] as String?;

    if (cmd == 'group:inboxRetrieveCursor') {
      sendCallCount++;
      lastSentMessage = message;
      sentMessages.add(message);
      lastCommand = cmd;
      commandLog.add(cmd!);
      if (!drainStarted.isCompleted) {
        drainStarted.complete();
      }
      await allowDrain.future;
      return jsonEncode({'ok': true, 'messages': messages, 'cursor': ''});
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
      groupRecoveryGate.resetForTest();
    });

    tearDown(() {
      groupRecoveryGate.resetForTest();
      p2pService.dispose();
    });

    test(
      'calls rejoin, drain, recoverStuck, retryIncompleteGroupUploads, retryFailed, then retryFailedGroupInboxStores',
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
          retryFailedGroupInboxStoresFn: () async {
            callOrder.add('retryInbox');
            return 0;
          },
        );

        expect(callOrder, [
          'rejoin',
          'drain',
          'recoverStuck',
          'retryUploads',
          'retryFailed',
          'retryInbox',
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

    test(
      'blocks admin-only group actions until replayed membership removal settles',
      () async {
        final now = DateTime.utc(2026, 4, 5, 12);
        final removalEventAt = now.add(const Duration(minutes: 1));
        const groupId = 'group-stale-admin';
        final bridge = _BlockingDrainBridge(messages: []);
        final removalPayload = {
          'groupId': groupId,
          'senderId': 'peer-other-admin',
          'senderUsername': 'OtherAdmin',
          'senderDeviceId': 'peer-other-admin',
          'transportPeerId': 'peer-other-admin',
          'keyEpoch': 1,
          'text': jsonEncode({
            '__sys': 'member_removed',
            'member': {
              'peerId': 'my-peer',
              'username': 'Self',
              'role': 'admin',
              'publicKey': 'pk-self',
            },
            'groupConfig': {
              'name': 'Recovery Group',
              'groupType': 'chat',
              'members': [
                {
                  'peerId': 'peer-other-admin',
                  'username': 'OtherAdmin',
                  'role': 'admin',
                  'publicKey': 'pk-other-admin',
                },
                {
                  'peerId': 'peer-bystander',
                  'username': 'Bystander',
                  'role': 'writer',
                  'publicKey': 'pk-bystander',
                },
              ],
              'createdBy': 'peer-other-admin',
              'createdAt': now.toIso8601String(),
            },
          }),
          'timestamp': removalEventAt.toIso8601String(),
          'messageId': 'sys-remove-self',
        };
        final listener = GroupMessageListener(
          groupRepo: groupRepo,
          msgRepo: groupMsgRepo,
          bridge: bridge,
          getSelfPeerId: () async => 'my-peer',
        );

        await groupRepo.saveGroup(
          GroupModel(
            id: groupId,
            name: 'Recovery Group',
            type: GroupType.chat,
            topicName: 'topic-$groupId',
            createdAt: now,
            createdBy: 'my-peer',
            myRole: GroupRole.admin,
          ),
        );
        await groupRepo.saveKey(
          GroupKeyInfo(
            groupId: groupId,
            keyGeneration: 1,
            encryptedKey: 'key-1',
            createdAt: now,
          ),
        );
        await groupRepo.saveMember(
          GroupMember(
            groupId: groupId,
            peerId: 'my-peer',
            username: 'Self',
            role: MemberRole.admin,
            publicKey: 'pk-self',
            joinedAt: now,
          ),
        );
        await groupRepo.saveMember(
          GroupMember(
            groupId: groupId,
            peerId: 'peer-other-admin',
            username: 'OtherAdmin',
            role: MemberRole.admin,
            publicKey: 'pk-other-admin',
            joinedAt: now,
          ),
        );
        await groupRepo.saveMember(
          GroupMember(
            groupId: groupId,
            peerId: 'peer-bystander',
            username: 'Bystander',
            role: MemberRole.writer,
            publicKey: 'pk-bystander',
            joinedAt: now,
          ),
        );
        bridge.messages.add({
          'from': 'peer-other-admin',
          'message': await buildGroupOfflineReplayEnvelope(
            bridge: bridge,
            groupRepo: groupRepo,
            groupId: groupId,
            payloadType: groupOfflineReplayPayloadTypeMessage,
            plaintext: jsonEncode(removalPayload),
            senderPeerId: 'peer-other-admin',
            senderPublicKey: 'pk-other-admin',
            senderPrivateKey: 'sk-other-admin',
            messageId: 'sys-remove-self',
            senderDeviceId: 'peer-other-admin',
            senderTransportPeerId: 'peer-other-admin',
            recipientPeerIds: const ['my-peer'],
          ),
        });

        final resumeFuture = handleAppResumed(
          bridge: bridge,
          p2pService: p2pService,
          groupRepo: groupRepo,
          groupMsgRepo: groupMsgRepo,
          groupMessageListener: listener,
        );

        await bridge.drainStarted.future;
        expect(isGroupRecoveryInProgress(), isTrue);

        await expectLater(
          removeGroupMember(
            bridge: bridge,
            groupRepo: groupRepo,
            groupId: groupId,
            memberPeerId: 'peer-bystander',
          ),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              contains(groupRecoveryPendingError),
            ),
          ),
        );
        expect(bridge.commandLog, isNot(contains('group:updateConfig')));

        bridge.allowDrain.complete();
        await resumeFuture;

        expect(await groupRepo.getGroup(groupId), isNull);
        expect(isGroupRecoveryInProgress(), isFalse);
      },
    );
  });
}
