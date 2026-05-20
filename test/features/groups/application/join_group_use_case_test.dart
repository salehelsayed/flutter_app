import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/core/bridge/bridge_group_helpers.dart';
import 'package:flutter_app/features/groups/application/join_group_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../shared/fakes/in_memory_group_repository.dart';

class _TimeoutCommandBridge extends FakeBridge {
  final String command;

  _TimeoutCommandBridge(this.command);

  @override
  Future<String> send(String message) async {
    final parsed = jsonDecode(message) as Map<String, dynamic>;
    final cmd = parsed['cmd'] as String?;
    if (cmd == command) {
      sendCallCount++;
      lastSentMessage = message;
      sentMessages.add(message);
      lastCommand = cmd;
      commandLog.add(cmd!);
      throw TimeoutException('Simulated $command timeout');
    }
    return super.send(message);
  }
}

void main() {
  late FakeBridge bridge;
  late InMemoryGroupRepository groupRepo;

  final testGroup = GroupModel(
    id: 'group-join-1',
    name: 'Join Group',
    type: GroupType.chat,
    topicName: 'group-topic-join-1',
    createdAt: DateTime.now().toUtc(),
    createdBy: 'peer-creator',
    myRole: GroupRole.member,
  );

  final fullGroupConfig = {
    'name': 'Join Group',
    'groupType': 'chat',
    'description': null,
    'members': [
      {
        'peerId': 'peer-creator',
        'username': 'Creator',
        'role': 'admin',
        'publicKey': 'pk-creator',
      },
      {
        'peerId': 'peer-self',
        'username': 'Self',
        'role': 'writer',
        'publicKey': 'pk-self',
      },
    ],
    'createdBy': 'peer-creator',
    'createdAt': '2026-05-10T00:00:00.000Z',
  };

  setUp(() {
    bridge = FakeBridge();
    groupRepo = InMemoryGroupRepository();

    bridge.responses['group:join'] = {'ok': true};
  });

  test('joins group successfully', () async {
    await joinGroup(
      bridge: bridge,
      groupRepo: groupRepo,
      group: testGroup,
      groupKey: 'shared-group-key',
      keyEpoch: 1,
      groupConfig: fullGroupConfig,
      selfPeerId: 'peer-self',
      selfPublicKey: 'pk-self',
      selfRole: MemberRole.writer,
    );

    final saved = await groupRepo.getGroup('group-join-1');
    expect(saved, isNotNull);
    expect(saved!.name, 'Join Group');
  });

  test('saves group, member, and key', () async {
    await joinGroup(
      bridge: bridge,
      groupRepo: groupRepo,
      group: testGroup,
      groupKey: 'shared-group-key',
      keyEpoch: 1,
      groupConfig: fullGroupConfig,
      selfPeerId: 'peer-self',
      selfPublicKey: 'pk-self',
      selfRole: MemberRole.writer,
    );

    // Group saved
    final group = await groupRepo.getGroup('group-join-1');
    expect(group, isNotNull);

    // Member saved
    final member = await groupRepo.getMember('group-join-1', 'peer-self');
    expect(member, isNotNull);
    expect(member!.role, MemberRole.writer);

    // Key saved
    final key = await groupRepo.getLatestKey('group-join-1');
    expect(key, isNotNull);
    expect(key!.encryptedKey, 'shared-group-key');
    expect(key.keyGeneration, 1);
  });

  test('BB-006 joins with full config payload and no topicName', () async {
    await joinGroup(
      bridge: bridge,
      groupRepo: groupRepo,
      group: testGroup,
      groupKey: 'shared-group-key',
      keyEpoch: 1,
      groupConfig: fullGroupConfig,
      selfPeerId: 'peer-self',
      selfPublicKey: 'pk-self',
      selfRole: MemberRole.writer,
    );

    expect(bridge.commandLog, contains('group:join'));

    final sent = jsonDecode(bridge.lastSentMessage!) as Map<String, dynamic>;
    expect(sent['cmd'], 'group:join');

    final payload = sent['payload'] as Map<String, dynamic>;
    expect(payload['groupId'], 'group-join-1');
    expect(payload['groupConfig'], fullGroupConfig);
    expect(payload['groupKey'], 'shared-group-key');
    expect(payload['keyEpoch'], 1);
    expect(payload.containsKey('topicName'), isFalse);
  });

  test(
    'BB-002 group:join NOT_INITIALIZED does not persist group member or key',
    () async {
      bridge.responses['group:join'] = {
        'ok': false,
        'errorCode': 'NOT_INITIALIZED',
        'errorMessage': 'native node not initialized',
      };

      await expectLater(
        joinGroup(
          bridge: bridge,
          groupRepo: groupRepo,
          group: testGroup,
          groupKey: 'shared-group-key',
          keyEpoch: 1,
          groupConfig: fullGroupConfig,
          selfPeerId: 'peer-self',
          selfPublicKey: 'pk-self',
          selfRole: MemberRole.writer,
        ),
        throwsA(
          isA<BridgeCommandException>().having(
            (error) => error.errorCode,
            'errorCode',
            'NOT_INITIALIZED',
          ),
        ),
      );

      expect(await groupRepo.getGroup('group-join-1'), isNull);
      expect(await groupRepo.getMember('group-join-1', 'peer-self'), isNull);
      expect(await groupRepo.getLatestKey('group-join-1'), isNull);
    },
  );

  test(
    'BB-013 group:join timeout does not persist group member or key',
    () async {
      final timeoutBridge = _TimeoutCommandBridge('group:join');

      await expectLater(
        joinGroup(
          bridge: timeoutBridge,
          groupRepo: groupRepo,
          group: testGroup,
          groupKey: 'shared-group-key',
          keyEpoch: 1,
          groupConfig: fullGroupConfig,
          selfPeerId: 'peer-self',
          selfPublicKey: 'pk-self',
          selfRole: MemberRole.writer,
        ),
        throwsA(isA<TimeoutException>()),
      );

      expect(await groupRepo.getGroup('group-join-1'), isNull);
      expect(await groupRepo.getMember('group-join-1', 'peer-self'), isNull);
      expect(await groupRepo.getLatestKey('group-join-1'), isNull);
      expect(timeoutBridge.commandLog, ['group:join']);
    },
  );

  test(
    'BB-006 invalid full-config material fails before bridge send or persistence',
    () async {
      bridge.responses['group:join'] = {'ok': true};

      await expectLater(
        joinGroup(
          bridge: bridge,
          groupRepo: groupRepo,
          group: testGroup,
          groupKey: 'shared-group-key',
          keyEpoch: 1,
          groupConfig: {
            'name': 'Join Group',
            'groupType': 'chat',
            'createdBy': 'peer-creator',
            'createdAt': '2026-05-10T00:00:00.000Z',
            'members': <Map<String, dynamic>>[],
          },
          selfPeerId: 'peer-self',
          selfPublicKey: 'pk-self',
          selfRole: MemberRole.writer,
        ),
        throwsA(
          isA<BridgeCommandException>().having(
            (error) => error.errorCode,
            'errorCode',
            'INVALID_JOIN_MATERIAL',
          ),
        ),
      );

      expect(bridge.sendCallCount, 0);
      expect(await groupRepo.getGroup('group-join-1'), isNull);
      expect(await groupRepo.getMember('group-join-1', 'peer-self'), isNull);
      expect(await groupRepo.getLatestKey('group-join-1'), isNull);
    },
  );
}
