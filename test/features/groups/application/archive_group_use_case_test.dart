import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/groups/application/archive_group_use_case.dart';
import 'package:flutter_app/features/groups/application/unarchive_group_use_case.dart';
import 'package:flutter_app/features/groups/application/handle_incoming_group_message_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import '../../../shared/fakes/in_memory_group_message_repository.dart';
import '../../../../test/shared/fakes/in_memory_group_repository.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';

void main() {
  late InMemoryGroupRepository groupRepo;
  const groupId = 'test-group-id-12345';

  setUp(() {
    groupRepo = InMemoryGroupRepository();
  });

  group('archiveGroup', () {
    test('calls groupRepo.archiveGroup(groupId) successfully', () async {
      await groupRepo.saveGroup(
        GroupModel(
          id: groupId,
          name: 'Test Group',
          type: GroupType.chat,
          topicName: '/mknoon/group/$groupId',
          createdBy: 'creator-peer',
          myRole: GroupRole.admin,
          createdAt: DateTime.now().toUtc(),
        ),
      );

      await archiveGroup(groupRepo: groupRepo, groupId: groupId);

      final group = await groupRepo.getGroup(groupId);
      expect(group!.isArchived, isTrue);
      expect(group.archivedAt, isNotNull);
    });

    test(
      'GROUP-010 archive incoming message and reopen retain history membership and keys',
      () async {
        final messages = InMemoryGroupMessageRepository();
        final joined = DateTime.utc(2026, 10, 1);
        await groupRepo.saveGroup(
          GroupModel(
            id: groupId,
            name: 'History group',
            type: GroupType.chat,
            topicName: '/mknoon/group/$groupId',
            createdBy: 'creator',
            myRole: GroupRole.member,
            createdAt: joined,
          ),
        );
        for (final peer in ['creator', 'self']) {
          await groupRepo.saveMember(
            GroupMember(
              groupId: groupId,
              peerId: peer,
              username: peer,
              role: peer == 'creator' ? MemberRole.admin : MemberRole.writer,
              joinedAt: joined,
            ),
          );
        }
        await groupRepo.saveKey(
          GroupKeyInfo(
            groupId: groupId,
            keyGeneration: 0,
            encryptedKey: 'synthetic-group-key',
            createdAt: joined,
          ),
        );
        final roster = (await groupRepo.getMembers(
          groupId,
        )).map((m) => m.toMap()).toList();
        Future<void> receive(String id, String text, int minute) async {
          final message = await handleIncomingGroupMessage(
            groupRepo: groupRepo,
            msgRepo: messages,
            groupId: groupId,
            senderId: 'creator',
            senderUsername: 'creator',
            selfPeerId: 'self',
            keyEpoch: 0,
            text: text,
            timestamp: joined.add(Duration(minutes: minute)).toIso8601String(),
            messageId: id,
          );
          expect(message, isNotNull);
        }

        await receive('history-before', 'Before archive', 1);
        await archiveGroup(groupRepo: groupRepo, groupId: groupId);
        expect(await groupRepo.getActiveGroups(), isEmpty);
        expect((await groupRepo.getGroup(groupId))!.isArchived, isTrue);
        await receive('history-during', 'While archived', 2);
        expect((await groupRepo.getGroup(groupId))!.isArchived, isTrue);
        expect(await groupRepo.getActiveGroups(), isEmpty);
        expect(
          (await groupRepo.getMembers(groupId)).map((m) => m.toMap()).toList(),
          roster,
        );
        expect(
          (await groupRepo.getLatestKey(groupId))!.encryptedKey,
          'synthetic-group-key',
        );
        await unarchiveGroup(groupRepo: groupRepo, groupId: groupId);
        final reopened = (await groupRepo.getActiveGroups()).single;
        expect(reopened.id, groupId);
        expect(reopened.name, 'History group');
        expect(reopened.myRole, GroupRole.member);
        expect(reopened.isArchived, isFalse);
        final history = await messages.getMessagesPage(groupId, limit: 20);
        expect(history.map((m) => m.id).toSet(), {
          'history-before',
          'history-during',
        });
        expect(history.map((m) => m.text).toSet(), {
          'Before archive',
          'While archived',
        });
        expect(
          (await groupRepo.getMembers(groupId)).map((m) => m.toMap()).toList(),
          roster,
        );
        expect((await groupRepo.getLatestKey(groupId))!.keyGeneration, 0);
      },
    );

    test('propagates errors from repository', () async {
      final failingRepo = _FailingGroupRepository();

      expect(
        () => archiveGroup(groupRepo: failingRepo, groupId: groupId),
        throwsA(isA<Exception>()),
      );
    });
  });
}

class _FailingGroupRepository extends InMemoryGroupRepository {
  @override
  Future<void> archiveGroup(String id) async {
    throw Exception('DB error');
  }
}
