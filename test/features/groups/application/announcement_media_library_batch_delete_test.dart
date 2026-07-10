import 'dart:async';

import 'package:flutter_app/features/groups/application/group_media_delete_for_me_coordinator.dart';
import 'package:flutter_app/features/groups/application/group_shared_media_batch_actions.dart';
import 'package:flutter_app/features/groups/application/group_shared_media_library_controller.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../shared/fakes/in_memory_group_message_repository.dart';

void main() {
  test(
    'AML-10 v99 batch delete is capped whole message deterministic and overlap safe',
    () async {
      final messages = InMemoryGroupMessageRepository();
      await messages.saveMessage(_message('one'));
      await messages.saveMessage(_message('two'));
      final delegate = _ControlledDelete(messages);
      final batch = GroupSharedMediaBatchDeleteCoordinator(
        messageRepository: messages,
        coordinator: delegate,
      );
      const firstSelection = [
        GroupSharedMediaIdentity(
          groupId: 'announcement-a',
          messageId: 'one',
          attachmentId: 'a1',
        ),
        GroupSharedMediaIdentity(
          groupId: 'announcement-a',
          messageId: 'one',
          attachmentId: 'a2',
        ),
        GroupSharedMediaIdentity(
          groupId: 'announcement-a',
          messageId: 'two',
          attachmentId: 'b1',
        ),
      ];
      final first = batch.perform(identities: firstSelection, confirmed: true);
      await delegate.started.future;
      final overlap = await batch.perform(
        identities: firstSelection,
        confirmed: true,
      );
      expect(overlap.deletedMessageIds, isEmpty);
      expect(delegate.calls, ['one']);
      delegate.release.complete();
      final settled = await first;
      expect(settled.deletedMessageIds, {'one', 'two'});
      expect(delegate.calls, ['one', 'two']);

      delegate.calls.clear();
      final cancelled = await batch.perform(
        identities: firstSelection,
        confirmed: false,
      );
      expect(cancelled.deletedMessageIds, isEmpty);
      expect(delegate.calls, isEmpty);

      await messages.saveMessage(
        _message('outgoing').copyWith(isIncoming: false),
      );
      final outgoing = await batch.perform(
        identities: const [
          GroupSharedMediaIdentity(
            groupId: 'announcement-a',
            messageId: 'outgoing',
            attachmentId: 'outgoing-a',
          ),
        ],
        confirmed: true,
      );
      expect(outgoing.failedMessageIds, {'outgoing'});
      expect(delegate.calls, isEmpty);

      final overCap = [
        for (var i = 0; i < 11; i++)
          GroupSharedMediaIdentity(
            groupId: 'announcement-a',
            messageId: 'm$i',
            attachmentId: 'x$i',
          ),
      ];
      await expectLater(
        batch.perform(identities: overCap, confirmed: true),
        throwsArgumentError,
      );
      expect(delegate.calls, isEmpty);
    },
  );
}

GroupMessage _message(String id) => GroupMessage(
  id: id,
  groupId: 'announcement-a',
  senderPeerId: 'peer',
  text: id,
  timestamp: DateTime.utc(2026, 7, 10),
  isIncoming: true,
  createdAt: DateTime.utc(2026, 7, 10),
);

class _ControlledDelete implements GroupMediaDeleteForMeCoordinator {
  _ControlledDelete(this.messages);
  final InMemoryGroupMessageRepository messages;
  final List<String> calls = [];
  final Completer<void> started = Completer<void>();
  final Completer<void> release = Completer<void>();

  @override
  Future<void> deleteForMe({
    required String groupId,
    required String messageId,
  }) async {
    calls.add(messageId);
    if (!started.isCompleted) started.complete();
    if (messageId == 'one') await release.future;
    await messages.deleteMessage(messageId);
  }
}
