import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/features/groups/application/group_key_distribution_debug_gate.dart';
import 'package:flutter_app/features/groups/application/rotate_and_distribute_group_key_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../shared/fakes/in_memory_group_repository.dart';

void main() {
  late PassthroughCryptoBridge bridge;
  late InMemoryGroupRepository groupRepo;
  const groupId = 'group-1';

  setUp(() async {
    bridge = PassthroughCryptoBridge();
    groupRepo = InMemoryGroupRepository();
    final now = DateTime.now().toUtc();
    await groupRepo.saveGroup(
      GroupModel(
        id: groupId,
        name: 'Test Group',
        type: GroupType.chat,
        topicName: '/mknoon/group/$groupId',
        createdAt: now,
        createdBy: 'peer-self',
        myRole: GroupRole.admin,
      ),
    );
    for (final (peer, role) in [
      ('peer-self', MemberRole.admin),
      ('peer-bob', MemberRole.writer),
      ('peer-carol', MemberRole.writer),
    ]) {
      await groupRepo.saveMember(
        GroupMember(
          groupId: groupId,
          peerId: peer,
          username: peer,
          role: role,
          publicKey: '$peer-pub',
          mlKemPublicKey: '$peer-mlkem',
          joinedAt: now,
        ),
      );
    }
    await groupRepo.saveKey(
      GroupKeyInfo(
        groupId: groupId,
        keyGeneration: 1,
        encryptedKey: 'oldKey==',
        createdAt: now,
      ),
    );
    bridge.responses['group:generateNextKey'] = {
      'ok': true,
      'groupKey': 'newKey==',
      'keyEpoch': 2,
    };
    bridge.responses['group:publish'] = {'ok': true, 'messageId': 'sys'};
  });

  tearDown(() => debugGroupKeyDistributionGate = null);

  Future<List<String>> rotate(List<String> events) async {
    final outcome = await rotateAndDistributeGroupKey(
      bridge: bridge,
      groupRepo: groupRepo,
      groupId: groupId,
      selfPeerId: 'peer-self',
      senderPublicKey: 'peer-self-pub',
      senderPrivateKey: 'peer-self-priv',
      senderUsername: 'Self',
      sendP2PMessage: (peerId, _) async {
        events.add('send:$peerId');
        return true;
      },
    );
    expect(outcome.rotated, isTrue);
    return events;
  }

  test('without a gate the rotated key is sent unchanged', () async {
    expect(debugGroupKeyDistributionGate, isNull);
    final events = await rotate([]);
    expect(events.toSet(), {'send:peer-bob', 'send:peer-carol'});
  });

  test('an armed gate runs before each recipient send', () async {
    final events = <String>[];
    debugGroupKeyDistributionGate = (group, peer) async {
      expect(group, groupId);
      events.add('gate:$peer');
    };
    await rotate(events);
    for (final peer in ['peer-bob', 'peer-carol']) {
      expect(
        events.indexOf('gate:$peer'),
        lessThan(events.indexOf('send:$peer')),
      );
    }
  });

  test('a gate can hold one recipient until released', () async {
    final events = <String>[];
    final release = Completer<void>();
    debugGroupKeyDistributionGate = (_, peer) async {
      if (peer == 'peer-bob') {
        events.add('held:$peer');
        await release.future;
      }
    };
    final done = rotate(events);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(events, contains('held:peer-bob'));
    expect(events, isNot(contains('send:peer-bob')));
    release.complete();
    await done;
    expect(events, contains('send:peer-bob'));
  });
}
