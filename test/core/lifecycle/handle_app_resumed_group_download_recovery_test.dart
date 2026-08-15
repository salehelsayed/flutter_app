import 'dart:convert';
import 'dart:io';

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
    'TC-365-04a linked resume routes strict group downloads before refresh without a generic owner',
    () {
      final production = File(
        'lib/app/bootstrap/production_application_bootstrap.dart',
      ).readAsStringSync();
      final restrictedOwner = File(
        'lib/app/bootstrap/direct_blob_free_linked_services.dart',
      ).readAsStringSync();
      final callbackStart = production.indexOf(
        'Future<int> drainLinkedGroupIncomingMediaCustody()',
      );
      final callbackEnd = production.indexOf('// 360:', callbackStart);
      expect(callbackStart, greaterThanOrEqualTo(0));
      expect(callbackEnd, greaterThan(callbackStart));
      final linkedCallback = production.substring(callbackStart, callbackEnd);

      expect(
        linkedCallback,
        contains(
          'action: groupMediaDownloadCoordinator.callStrictGroupMediaCustodyOnly',
        ),
      );
      expect(
        linkedCallback,
        isNot(contains('action: groupMediaDownloadCoordinator.call,')),
        reason: 'the linked callback must never start the generic group lane',
      );
      final incoming = restrictedOwner.indexOf(
        'drainIncomingMedia: drainLinkedGroupIncomingMedia',
      );
      final notification = restrictedOwner.indexOf(
        'drainLinkedGroupNotificationDisplayCustody?.call()',
      );
      final refresh = restrictedOwner.indexOf('refreshLinkedGroupList?.call()');
      expect(incoming, greaterThanOrEqualTo(0));
      expect(notification, greaterThan(incoming));
      expect(refresh, greaterThan(notification));
    },
  );

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
