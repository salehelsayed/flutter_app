import 'dart:convert';

import 'package:flutter_app/app/lifecycle/handle_app_resumed.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../shared/fakes/in_memory_group_message_repository.dart';
import '../../shared/fakes/in_memory_group_repository.dart';
import '../bridge/fake_bridge.dart';
import '../services/fake_p2p_service.dart';

void main() {
  test(
    'P269 resume runs group media recovery after first group inbox drain',
    () async {
      final order = <String>[];
      final bridge = _GroupDrainTracingBridge(order);
      final p2pService = FakeP2PService(
        initialState: const NodeState(
          isStarted: true,
          peerId: 'p269-self',
          circuitAddresses: <String>['/p2p-circuit/p269'],
        ),
      );
      addTearDown(p2pService.dispose);
      final groupRepo = InMemoryGroupRepository();
      final messageRepo = InMemoryGroupMessageRepository();
      final createdAt = DateTime.utc(2026, 7, 22, 13);

      await groupRepo.saveGroup(
        GroupModel(
          id: 'p269-resume-group',
          name: 'P269 resume',
          type: GroupType.chat,
          topicName: 'p269-resume-topic',
          createdAt: createdAt,
          createdBy: 'p269-admin',
          myRole: GroupRole.member,
        ),
      );
      await groupRepo.saveKey(
        GroupKeyInfo(
          groupId: 'p269-resume-group',
          keyGeneration: 1,
          encryptedKey: 'p269-key',
          createdAt: createdAt,
        ),
      );
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'p269-resume-group',
          peerId: 'p269-self',
          username: 'Self',
          role: MemberRole.writer,
          publicKey: 'p269-public-key',
          joinedAt: createdAt,
        ),
      );

      await handleAppResumed(
        bridge: bridge,
        p2pService: p2pService,
        groupRepo: groupRepo,
        groupMsgRepo: messageRepo,
        retryIncompleteGroupDownloadsFn: () async {
          order.add('download-recovery');
          return 1;
        },
      );

      expect(order, contains('group-inbox-drain'));
      expect(order, contains('download-recovery'));
      expect(
        order.indexOf('download-recovery'),
        greaterThan(order.indexOf('group-inbox-drain')),
        reason:
            'durable media recovery must observe duplicate enrichment '
            'committed by the first inbox drain',
      );
      expect(
        order.where((event) => event == 'download-recovery'),
        hasLength(1),
      );
    },
  );
}

class _GroupDrainTracingBridge extends FakeBridge {
  _GroupDrainTracingBridge(this.order)
    : super(
        initialResponses: <String, Map<String, dynamic>>{
          'group:join': <String, dynamic>{'ok': true},
          'group:inboxRetrieveCursor': <String, dynamic>{
            'ok': true,
            'messages': <Object?>[],
            'cursor': '',
          },
        },
      );

  final List<String> order;

  @override
  Future<String> send(String message) async {
    final decoded = jsonDecode(message) as Map<String, dynamic>;
    if (decoded['cmd'] == 'group:inboxRetrieveCursor') {
      order.add('group-inbox-drain');
    }
    return super.send(message);
  }
}
