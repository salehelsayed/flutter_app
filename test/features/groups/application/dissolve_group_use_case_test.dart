import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/features/groups/application/dissolve_group_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../shared/fakes/in_memory_group_message_repository.dart';
import '../../../shared/fakes/in_memory_group_repository.dart';

void main() {
  late FakeBridge bridge;
  late InMemoryGroupRepository groupRepo;
  late InMemoryGroupMessageRepository msgRepo;

  final now = DateTime.utc(2026, 4, 5, 12, 0, 0);
  final baseGroup = GroupModel(
    id: 'group-1',
    name: 'Project Group',
    type: GroupType.chat,
    topicName: 'topic-group-1',
    createdAt: now,
    createdBy: 'peer-admin',
    myRole: GroupRole.admin,
  );

  setUp(() async {
    bridge = FakeBridge();
    groupRepo = InMemoryGroupRepository();
    msgRepo = InMemoryGroupMessageRepository();

    await groupRepo.saveGroup(baseGroup);
    await groupRepo.saveKey(
      GroupKeyInfo(
        groupId: 'group-1',
        keyGeneration: 1,
        encryptedKey: 'test-group-key-1',
        createdAt: now,
      ),
    );
    await groupRepo.saveMember(
      GroupMember(
        groupId: 'group-1',
        peerId: 'peer-admin',
        username: 'Admin',
        role: MemberRole.admin,
        joinedAt: now,
      ),
    );
    await groupRepo.saveMember(
      GroupMember(
        groupId: 'group-1',
        peerId: 'peer-bob',
        username: 'Bob',
        role: MemberRole.writer,
        joinedAt: now,
      ),
    );
  });

  test(
    'dissolves a group, stores a timeline event, and leaves the topic',
    () async {
      final (result, group) = await dissolveGroup(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        actorPeerId: 'peer-admin',
        actorUsername: 'Admin',
        actorPublicKey: 'pk-admin',
        actorPrivateKey: 'sk-admin',
        dissolvedAt: now.add(const Duration(minutes: 5)),
      );

      expect(result, DissolveGroupResult.success);
      expect(group, isNotNull);
      expect(group!.isDissolved, isTrue);
      expect(group.dissolvedAt, now.add(const Duration(minutes: 5)));
      expect(group.dissolvedBy, 'peer-admin');

      final stored = await groupRepo.getGroup('group-1');
      expect(stored, isNotNull);
      expect(stored!.isDissolved, isTrue);

      final latest = await msgRepo.getLatestMessage('group-1');
      expect(latest, isNotNull);
      expect(latest!.id.startsWith('sys-group_dissolved:group-1:'), isTrue);
      expect(latest.text, 'Admin dissolved the group');

      expect(
        bridge.commandLog,
        containsAll(['group:publish', 'group:inboxStore', 'group:leave']),
      );
    },
  );

  test('returns unauthorized for non-admin users', () async {
    await groupRepo.updateGroup(baseGroup.copyWith(myRole: GroupRole.member));

    final (result, group) = await dissolveGroup(
      bridge: bridge,
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      groupId: 'group-1',
      actorPeerId: 'peer-admin',
      actorUsername: 'Admin',
      actorPublicKey: 'pk-admin',
      actorPrivateKey: 'sk-admin',
    );

    expect(result, DissolveGroupResult.unauthorized);
    expect(group, isNotNull);
    expect(group!.isDissolved, isFalse);
    expect(bridge.commandLog, isEmpty);
  });

  test('former creator who is no longer admin cannot dissolve the group',
      () async {
    await groupRepo.updateGroup(baseGroup.copyWith(myRole: GroupRole.member));
    await groupRepo.saveMember(
      GroupMember(
        groupId: 'group-1',
        peerId: 'peer-admin',
        username: 'Admin',
        role: MemberRole.writer,
        joinedAt: now,
      ),
    );

    final (result, group) = await dissolveGroup(
      bridge: bridge,
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      groupId: 'group-1',
      actorPeerId: 'peer-admin',
      actorUsername: 'Admin',
      actorPublicKey: 'pk-admin',
      actorPrivateKey: 'sk-admin',
    );

    expect(result, DissolveGroupResult.unauthorized);
    expect(group, isNotNull);
    expect(group!.isDissolved, isFalse);
    expect(bridge.commandLog, isEmpty);
  });

  test('returns alreadyDissolved when the group is already closed', () async {
    await groupRepo.updateGroup(
      baseGroup.copyWith(
        isDissolved: true,
        dissolvedAt: now,
        dissolvedBy: 'peer-admin',
      ),
    );

    final (result, group) = await dissolveGroup(
      bridge: bridge,
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      groupId: 'group-1',
      actorPeerId: 'peer-admin',
      actorUsername: 'Admin',
      actorPublicKey: 'pk-admin',
      actorPrivateKey: 'sk-admin',
    );

    expect(result, DissolveGroupResult.alreadyDissolved);
    expect(group, isNotNull);
    expect(group!.isDissolved, isTrue);
    expect(bridge.commandLog, isEmpty);
  });

  test(
    'returns bridgeError when inbox fallback fails but still marks the group dissolved',
    () async {
      bridge.responses['group:inboxStore'] = {
        'ok': false,
        'errorCode': 'INBOX_STORE_FAILED',
      };

      final (result, group) = await dissolveGroup(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        actorPeerId: 'peer-admin',
        actorUsername: 'Admin',
        actorPublicKey: 'pk-admin',
        actorPrivateKey: 'sk-admin',
        dissolvedAt: now.add(const Duration(minutes: 10)),
      );

      expect(result, DissolveGroupResult.bridgeError);
      expect(group, isNotNull);
      expect(group!.isDissolved, isTrue);
      expect(group.dissolvedAt, now.add(const Duration(minutes: 10)));
      expect(bridge.commandLog, contains('group:leave'));

      final stored = await groupRepo.getGroup('group-1');
      expect(stored, isNotNull);
      expect(stored!.isDissolved, isTrue);
    },
  );
}
