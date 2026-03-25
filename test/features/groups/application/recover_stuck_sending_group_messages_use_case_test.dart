import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/groups/application/recover_stuck_sending_group_messages_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';

import '../../../shared/fakes/in_memory_group_message_repository.dart';

GroupMessage _makeSendingMessage({
  required String id,
  required Duration age,
}) {
  final ts = DateTime.now().toUtc().subtract(age);
  return GroupMessage(
    id: id,
    groupId: 'group-1',
    senderPeerId: 'peer-1',
    senderUsername: 'Alice',
    text: 'Hello group',
    timestamp: ts,
    keyGeneration: 0,
    status: 'sending',
    isIncoming: false,
    createdAt: ts,
  );
}

void main() {
  group('recoverStuckSendingGroupMessages', () {
    late InMemoryGroupMessageRepository msgRepo;

    setUp(() {
      msgRepo = InMemoryGroupMessageRepository();
    });

    test('returns count from repo and transitions stuck rows to failed', () async {
      await msgRepo.saveMessage(
        _makeSendingMessage(id: 'old-sending', age: const Duration(minutes: 5)),
      );
      await msgRepo.saveMessage(
        _makeSendingMessage(id: 'recent-sending', age: const Duration(seconds: 10)),
      );
      await msgRepo.saveMessage(
        GroupMessage(
          id: 'sent-row',
          groupId: 'group-1',
          senderPeerId: 'peer-1',
          senderUsername: 'Alice',
          text: 'Already sent',
          timestamp: DateTime.now().toUtc(),
          keyGeneration: 0,
          status: 'sent',
          isIncoming: false,
          createdAt: DateTime.now().toUtc(),
        ),
      );

      final count = await recoverStuckSendingGroupMessages(
        groupMsgRepo: msgRepo,
        threshold: const Duration(seconds: 30),
      );

      expect(count, 1);
      expect((await msgRepo.getMessage('old-sending'))!.status, 'failed');
      expect((await msgRepo.getMessage('recent-sending'))!.status, 'sending');
    });

    test('returns 0 when nothing is stuck', () async {
      final count = await recoverStuckSendingGroupMessages(
        groupMsgRepo: msgRepo,
        threshold: const Duration(seconds: 30),
      );

      expect(count, 0);
    });

    test('respects the supplied threshold', () async {
      await msgRepo.saveMessage(
        _makeSendingMessage(id: 'recent-sending', age: const Duration(seconds: 10)),
      );

      final count = await recoverStuckSendingGroupMessages(
        groupMsgRepo: msgRepo,
        threshold: const Duration(seconds: 30),
      );

      expect(count, 0);
      expect((await msgRepo.getMessage('recent-sending'))!.status, 'sending');
    });
  });
}
