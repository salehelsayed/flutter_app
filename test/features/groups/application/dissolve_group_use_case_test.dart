import 'dart:convert';

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
    'EK004 dissolve stores signed group_dissolved replay envelope',
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
      expect(group.lastMembershipEventAt, now.add(const Duration(minutes: 5)));

      final stored = await groupRepo.getGroup('group-1');
      expect(stored, isNotNull);
      expect(stored!.isDissolved, isTrue);
      expect(stored.dissolvedAt, now.add(const Duration(minutes: 5)));
      expect(stored.dissolvedBy, 'peer-admin');
      expect(stored.lastMembershipEventAt, now.add(const Duration(minutes: 5)));

      final latest = await msgRepo.getLatestMessage('group-1');
      expect(latest, isNotNull);
      expect(latest!.id.startsWith('sys-group_dissolved:group-1:'), isTrue);
      expect(latest.text, 'Admin dissolved the group');

      expect(
        bridge.commandLog,
        containsAll(['group:publish', 'group:inboxStore', 'group:leave']),
      );
      final inboxStoreMessage = bridge.sentMessages.firstWhere((message) {
        final parsed = jsonDecode(message) as Map<String, dynamic>;
        return parsed['cmd'] == 'group:inboxStore';
      });
      final inboxPayload =
          (jsonDecode(inboxStoreMessage) as Map<String, dynamic>)['payload']
              as Map<String, dynamic>;
      final replayEnvelope =
          jsonDecode(inboxPayload['message'] as String) as Map<String, dynamic>;
      expect(replayEnvelope['kind'], 'group_offline_replay');
      expect(replayEnvelope['payloadType'], 'group_message');
      expect(replayEnvelope['senderPeerId'], 'peer-admin');
      expect(replayEnvelope['senderPublicKey'], 'pk-admin');
      expect(replayEnvelope['signatureAlgorithm'], 'ed25519');
      expect(replayEnvelope['signedPayload'], isA<String>());
      expect(replayEnvelope['signature'], isA<String>());
      final replayPlaintext =
          jsonDecode(replayEnvelope['ciphertext'] as String)
              as Map<String, dynamic>;
      expect(replayEnvelope['messageId'], replayPlaintext['messageId']);
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

  test(
    'former creator who is no longer admin cannot dissolve the group',
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
    },
  );

  test('returns alreadyDissolved when the group is already closed', () async {
    await groupRepo.updateGroup(
      baseGroup.copyWith(
        isDissolved: true,
        dissolvedAt: now,
        dissolvedBy: 'peer-admin',
        lastMembershipEventAt: now,
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
    expect(group.dissolvedAt, now);
    expect(group.dissolvedBy, 'peer-admin');
    expect(group.lastMembershipEventAt, now);
    expect(bridge.commandLog, isEmpty);
  });

  test(
    'repeated dissolve preserves closure state and does not publish again',
    () async {
      final firstDissolvedAt = now.add(const Duration(minutes: 5));
      final secondDissolvedAt = now.add(const Duration(minutes: 30));

      final (firstResult, firstGroup) = await dissolveGroup(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        actorPeerId: 'peer-admin',
        actorUsername: 'Admin',
        actorPublicKey: 'pk-admin',
        actorPrivateKey: 'sk-admin',
        dissolvedAt: firstDissolvedAt,
      );

      expect(firstResult, DissolveGroupResult.success);
      expect(firstGroup, isNotNull);
      expect(firstGroup!.isDissolved, isTrue);

      bridge.commandLog.clear();
      bridge.sentMessages.clear();

      final (secondResult, secondGroup) = await dissolveGroup(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        actorPeerId: 'peer-admin',
        actorUsername: 'Admin Again',
        actorPublicKey: 'pk-admin',
        actorPrivateKey: 'sk-admin',
        dissolvedAt: secondDissolvedAt,
      );

      expect(secondResult, DissolveGroupResult.alreadyDissolved);
      expect(secondGroup, isNotNull);
      expect(secondGroup!.isDissolved, isTrue);
      expect(secondGroup.dissolvedAt, firstDissolvedAt);
      expect(secondGroup.dissolvedBy, 'peer-admin');
      expect(secondGroup.lastMembershipEventAt, firstDissolvedAt);
      expect(bridge.commandLog, isEmpty);
      expect(bridge.sentMessages, isEmpty);

      final stored = await groupRepo.getGroup('group-1');
      expect(stored, isNotNull);
      expect(stored!.isDissolved, isTrue);
      expect(stored.dissolvedAt, firstDissolvedAt);
      expect(stored.dissolvedBy, 'peer-admin');
      expect(stored.lastMembershipEventAt, firstDissolvedAt);

      final dissolvedMessages = (await msgRepo.getMessagesPage('group-1'))
          .where((message) => message.id.startsWith('sys-group_dissolved:'))
          .toList();
      expect(dissolvedMessages, hasLength(1));
    },
  );

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
