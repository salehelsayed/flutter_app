import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/lifecycle/handle_app_paused.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';

import '../../shared/fakes/in_memory_group_message_repository.dart';
import '../../shared/fakes/in_memory_message_repository.dart';

class _ThrowingGroupMessageRepository extends InMemoryGroupMessageRepository {
  @override
  Future<int> transitionSendingToFailed() async {
    throw Exception('group pause transition failed');
  }
}

ConversationMessage _makeSendingMessage({
  required String id,
  required String contactPeerId,
}) {
  return ConversationMessage(
    id: id,
    contactPeerId: contactPeerId,
    senderPeerId: 'peer-me',
    text: 'Hello',
    timestamp: '2026-01-01T00:00:00.000Z',
    status: 'sending',
    isIncoming: false,
    createdAt: '2026-01-01T00:00:00.000Z',
  );
}

GroupMessage _makeGroupSendingMessage({
  required String id,
  required String groupId,
}) {
  return GroupMessage(
    id: id,
    groupId: groupId,
    senderPeerId: 'peer-me',
    senderUsername: 'Alice',
    text: 'Hello group',
    timestamp: DateTime.parse('2026-01-01T00:00:00.000Z'),
    status: 'sending',
    isIncoming: false,
    createdAt: DateTime.parse('2026-01-01T00:00:00.000Z'),
  );
}

void main() {
  group('handleAppPaused for groups', () {
    test('transitions group alongside 1:1', () async {
      final messageRepo = InMemoryMessageRepository();
      final groupMsgRepo = InMemoryGroupMessageRepository();
      await messageRepo.saveMessage(
        _makeSendingMessage(id: 'dm-1', contactPeerId: 'peer-a'),
      );
      await groupMsgRepo.saveMessage(
        _makeGroupSendingMessage(id: 'group-1', groupId: 'group-a'),
      );

      final result = await handleAppPaused(
        messageRepo: messageRepo,
        groupMsgRepo: groupMsgRepo,
      );

      expect(result.transitionedCount, 1);
      expect(result.groupTransitionedCount, 1);
      expect(
        (await messageRepo.getMessagesForContact('peer-a')).single.status,
        'failed',
      );
      expect(
        (await groupMsgRepo.getMessagesPage('group-a')).single.status,
        'failed',
      );
    });

    test('group error isolation leaves 1:1 transition intact', () async {
      final messageRepo = InMemoryMessageRepository();
      final groupMsgRepo = _ThrowingGroupMessageRepository();
      await messageRepo.saveMessage(
        _makeSendingMessage(id: 'dm-2', contactPeerId: 'peer-b'),
      );

      final result = await handleAppPaused(
        messageRepo: messageRepo,
        groupMsgRepo: groupMsgRepo,
      );

      expect(result.transitionedCount, 1);
      expect(result.groupTransitionedCount, 0);
      expect(
        (await messageRepo.getMessagesForContact('peer-b')).single.status,
        'failed',
      );
    });

    test('null groupMsgRepo keeps pause handler backward compatible', () async {
      final messageRepo = InMemoryMessageRepository();
      await messageRepo.saveMessage(
        _makeSendingMessage(id: 'dm-3', contactPeerId: 'peer-c'),
      );

      final result = await handleAppPaused(messageRepo: messageRepo);

      expect(result.transitionedCount, 1);
      expect(result.groupTransitionedCount, 0);
    });

    test('group-only pending sends still transition when 1:1 count is zero',
        () async {
      final messageRepo = InMemoryMessageRepository();
      final groupMsgRepo = InMemoryGroupMessageRepository();
      await groupMsgRepo.saveMessage(
        _makeGroupSendingMessage(id: 'group-2', groupId: 'group-b'),
      );

      final result = await handleAppPaused(
        messageRepo: messageRepo,
        groupMsgRepo: groupMsgRepo,
      );

      expect(result.transitionedCount, 0);
      expect(result.groupTransitionedCount, 1);
      expect(
        (await groupMsgRepo.getMessagesPage('group-b')).single.status,
        'failed',
      );
    });
  });
}
