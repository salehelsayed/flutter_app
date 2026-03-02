import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/features/groups/application/send_group_message_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../shared/fakes/in_memory_group_repository.dart';
import '../../../shared/fakes/in_memory_group_message_repository.dart';

void main() {
  late FakeBridge bridge;
  late InMemoryGroupRepository groupRepo;
  late InMemoryGroupMessageRepository msgRepo;

  final testGroup = GroupModel(
    id: 'group-1',
    name: 'Test Group',
    type: GroupType.chat,
    topicName: 'group-topic-1',
    createdAt: DateTime.now().toUtc(),
    createdBy: 'peer-1',
    myRole: GroupRole.admin,
  );

  setUp(() async {
    bridge = FakeBridge();
    groupRepo = InMemoryGroupRepository();
    msgRepo = InMemoryGroupMessageRepository();

    await groupRepo.saveGroup(testGroup);

    bridge.responses['group:publish'] = {
      'ok': true,
      'messageId': 'msg-123',
    };
  });

  test('sends message successfully', () async {
    final (result, message) = await sendGroupMessage(
      bridge: bridge,
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      groupId: 'group-1',
      text: 'Hello group!',
      senderPeerId: 'peer-1',
      senderPublicKey: 'pk-1',
      senderPrivateKey: 'sk-1',
      senderUsername: 'Alice',
    );

    expect(result, SendGroupMessageResult.success);
    expect(message, isNotNull);
    expect(message!.text, 'Hello group!');
    expect(message.isIncoming, false);
    expect(message.status, 'sent');
  });

  test('returns groupNotFound for unknown group', () async {
    final (result, message) = await sendGroupMessage(
      bridge: bridge,
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      groupId: 'nonexistent',
      text: 'Hello',
      senderPeerId: 'peer-1',
      senderPublicKey: 'pk-1',
      senderPrivateKey: 'sk-1',
      senderUsername: 'Alice',
    );

    expect(result, SendGroupMessageResult.groupNotFound);
    expect(message, isNull);
  });

  test('returns unauthorized for non-admin in announcement group', () async {
    final announcementGroup = GroupModel(
      id: 'group-announce',
      name: 'Announcements',
      type: GroupType.announcement,
      topicName: 'group-topic-announce',
      createdAt: DateTime.now().toUtc(),
      createdBy: 'peer-admin',
      myRole: GroupRole.member,
    );
    await groupRepo.saveGroup(announcementGroup);

    final (result, message) = await sendGroupMessage(
      bridge: bridge,
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      groupId: 'group-announce',
      text: 'Hello',
      senderPeerId: 'peer-2',
      senderPublicKey: 'pk-2',
      senderPrivateKey: 'sk-2',
      senderUsername: 'Bob',
    );

    expect(result, SendGroupMessageResult.unauthorized);
    expect(message, isNull);
  });

  test('saves message to repo on success', () async {
    await sendGroupMessage(
      bridge: bridge,
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      groupId: 'group-1',
      text: 'Hello group!',
      senderPeerId: 'peer-1',
      senderPublicKey: 'pk-1',
      senderPrivateKey: 'sk-1',
      senderUsername: 'Alice',
    );

    expect(msgRepo.count, 1);
    final latest = await msgRepo.getLatestMessage('group-1');
    expect(latest, isNotNull);
    expect(latest!.text, 'Hello group!');
  });
}
