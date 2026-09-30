import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/debug/production_journeys/production_group_reaction_toggle.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';

import '../core/bridge/fake_bridge.dart';
import '../features/conversation/domain/repositories/fake_reaction_repository.dart';
import '../features/identity/domain/repositories/fake_identity_repository.dart';
import '../shared/fakes/fake_group_reaction_replay_outbox_repository.dart';
import '../shared/fakes/in_memory_group_message_repository.dart';
import '../shared/fakes/in_memory_group_repository.dart';

class _Bridge extends FakeBridge {
  int publishCount = 0;
  int? failPublish;
  final publishAt = <DateTime>[];
  @override
  Future<String> send(String message) async {
    if ((jsonDecode(message) as Map)['cmd'] == 'group:publishReaction') {
      publishAt.add(DateTime.now());
      if (++publishCount == failPublish) throw StateError('publish rejected');
    }
    return super.send(message);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Bridge bridge;
  late InMemoryGroupRepository groups;
  late InMemoryGroupMessageRepository messages;
  late FakeReactionRepository reactions;
  late FakeGroupReactionReplayOutboxRepository outbox;
  late FakeIdentityRepository identities;
  Future<Map<String, Object?>> execute() => executeProductionReactionToggle(
    bridge: bridge,
    groupRepository: groups,
    messageRepository: messages,
    reactionRepository: reactions,
    replayOutboxRepository: outbox,
    inviteDeliveryRepository: null,
    identityRepository: identities,
    groupId: 'group',
    messageId: 'target',
    reactorPeerId: 'bob',
  );
  setUp(() async {
    bridge = _Bridge()..responses['group:publishReaction'] = {'ok': true};
    groups = InMemoryGroupRepository();
    messages = InMemoryGroupMessageRepository();
    reactions = FakeReactionRepository();
    outbox = FakeGroupReactionReplayOutboxRepository();
    identities = FakeIdentityRepository()
      ..seed(FakeIdentityRepository.makeIdentity(peerId: 'bob'));
    final at = DateTime.now().toUtc();
    await groups.saveGroup(
      GroupModel(
        id: 'group',
        name: 'Group',
        type: GroupType.chat,
        topicName: 'topic',
        createdAt: at,
        createdBy: 'alice',
        myRole: GroupRole.member,
      ),
    );
    await groups.saveMember(
      GroupMember(
        groupId: 'group',
        peerId: 'bob',
        username: 'Journeybob',
        publicKey: 'pk-test',
        role: MemberRole.writer,
        joinedAt: at,
      ),
    );
    await groups.saveKey(
      GroupKeyInfo(
        groupId: 'group',
        keyGeneration: 0,
        encryptedKey: 'key',
        createdAt: at,
      ),
    );
    await messages.saveMessage(
      GroupMessage(
        id: 'target',
        groupId: 'group',
        senderPeerId: 'alice',
        senderUsername: 'Journeyalice',
        text: 'RT-001 target',
        timestamp: at,
        keyGeneration: 0,
        status: 'delivered',
        isIncoming: true,
        createdAt: at,
      ),
    );
  });
  test(
    'actual production use cases publish add/remove/re-add and persist final row',
    () async {
      final result = await execute();
      final outcomes = result['outcomes'] as List;
      expect(outcomes.map((r) => r['operation']), ['add', 'remove', 'readd']);
      expect(outcomes.map((r) => r['outcome']), everyElement('success'));
      expect(
        result['returnToNextCallMs'],
        everyElement(greaterThanOrEqualTo(500)),
      );
      expect(bridge.publishCount, 3);
      for (var i = 1; i < 3; i++) {
        expect(
          bridge.publishAt[i]
              .difference(bridge.publishAt[i - 1])
              .inMilliseconds,
          greaterThanOrEqualTo(500),
        );
      }
      final rows = await reactions.getReactionsForMessage('target');
      expect(rows, hasLength(1));
      expect(rows.single.emoji, '✅');
      expect(rows.single.id, outcomes.last['reactionId']);
    },
  );
  test('changed identity refuses all transport and writes', () async {
    identities.seed(FakeIdentityRepository.makeIdentity(peerId: 'charlie'));
    await expectLater(execute(), throwsStateError);
    expect(bridge.sendCallCount, 0);
    expect(outbox.entries, isEmpty);
    expect(await reactions.getReactionsForMessage('target'), isEmpty);
  });
  test('queued add cannot proceed to removal or re-add', () async {
    bridge.failPublish = 1;
    final result = await execute();
    expect(result['outcomes'], hasLength(1));
    expect((result['outcomes'] as List).single['outcome'], 'queuedForRetry');
    expect(result['returnToNextCallMs'], isEmpty);
    expect(bridge.publishCount, 1);
  });
  test('queued removal cannot proceed to re-add', () async {
    bridge.failPublish = 2;
    final result = await execute();
    expect(result['outcomes'], hasLength(2));
    expect((result['outcomes'] as List).last['outcome'], 'queuedForRetry');
    expect(result['returnToNextCallMs'], hasLength(1));
    expect(bridge.publishCount, 2);
    expect(
      (await reactions.getReactionsForMessage(
        'target',
      )).where((r) => r.emoji == '✅'),
      isEmpty,
    );
  });
}
