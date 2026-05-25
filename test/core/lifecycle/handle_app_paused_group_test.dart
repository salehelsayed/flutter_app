import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/lifecycle/handle_app_paused.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';

import '../../shared/fakes/in_memory_group_message_repository.dart';
import '../../shared/fakes/in_memory_message_repository.dart';

class _ThrowingGroupMessageRepository extends InMemoryGroupMessageRepository {
  @override
  Future<int> recoverStuckSendingMessages({required Duration olderThan}) async {
    throw Exception('group pause stale recovery failed');
  }
}

class _TrackingGroupMessageRepository extends InMemoryGroupMessageRepository {
  bool transitionSendingToFailedCalled = false;

  @override
  Future<int> transitionSendingToFailed() async {
    transitionSendingToFailedCalled = true;
    throw StateError('group pause must not use blanket transition');
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
  DateTime? timestamp,
  String status = 'sending',
  String? wireEnvelope,
  String? inboxRetryPayload,
  bool inboxStored = false,
}) {
  final resolvedTimestamp =
      timestamp ?? DateTime.parse('2026-01-01T00:00:00.000Z');
  return GroupMessage(
    id: id,
    groupId: groupId,
    senderPeerId: 'peer-me',
    senderUsername: 'Alice',
    text: 'Hello group',
    timestamp: resolvedTimestamp,
    status: status,
    isIncoming: false,
    createdAt: resolvedTimestamp,
    wireEnvelope: wireEnvelope,
    inboxStored: inboxStored,
    inboxRetryPayload: inboxRetryPayload,
  );
}

void main() {
  group('handleAppPaused for groups', () {
    test('recovers only stale group sends alongside 1:1', () async {
      final messageRepo = InMemoryMessageRepository();
      final groupMsgRepo = _TrackingGroupMessageRepository();
      final oldSendingAt = DateTime.now().toUtc().subtract(
        kPausedGroupSendingRecoveryThreshold + const Duration(seconds: 5),
      );
      final freshSendingAt = DateTime.now().toUtc();
      await messageRepo.saveMessage(
        _makeSendingMessage(id: 'dm-1', contactPeerId: 'peer-a'),
      );
      await groupMsgRepo.saveMessage(
        _makeGroupSendingMessage(
          id: 'group-old',
          groupId: 'group-a',
          timestamp: oldSendingAt,
        ),
      );
      await groupMsgRepo.saveMessage(
        _makeGroupSendingMessage(
          id: 'group-fresh',
          groupId: 'group-a',
          timestamp: freshSendingAt,
        ),
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
      expect((await groupMsgRepo.getMessage('group-old'))!.status, 'failed');
      expect((await groupMsgRepo.getMessage('group-fresh'))!.status, 'sending');
      expect(groupMsgRepo.transitionSendingToFailedCalled, isFalse);
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

    test(
      'group-only pending sends still transition when 1:1 count is zero',
      () async {
        final messageRepo = InMemoryMessageRepository();
        final groupMsgRepo = InMemoryGroupMessageRepository();
        final oldSendingAt = DateTime.now().toUtc().subtract(
          kPausedGroupSendingRecoveryThreshold + const Duration(seconds: 5),
        );
        await groupMsgRepo.saveMessage(
          _makeGroupSendingMessage(
            id: 'group-2',
            groupId: 'group-b',
            timestamp: oldSendingAt,
          ),
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
      },
    );

    test(
      'NW-011 pause transitions in-flight group send to retryable failed without deleting custody',
      () async {
        final messageRepo = InMemoryMessageRepository();
        final groupMsgRepo = InMemoryGroupMessageRepository();
        await groupMsgRepo.saveMessage(
          _makeGroupSendingMessage(
            id: 'nw011-sending',
            groupId: 'group-nw011',
            wireEnvelope: '{"messageId":"nw011-sending"}',
            inboxRetryPayload:
                '{"groupId":"group-nw011","message":"retryable"}',
          ),
        );
        await groupMsgRepo.saveMessage(
          _makeGroupSendingMessage(
            id: 'nw011-pending',
            groupId: 'group-nw011',
            status: 'pending',
            inboxRetryPayload:
                '{"groupId":"group-nw011","message":"pending-retry"}',
          ),
        );
        await groupMsgRepo.saveMessage(
          _makeGroupSendingMessage(
            id: 'nw011-sent',
            groupId: 'group-nw011',
            status: 'sent',
            inboxStored: true,
          ),
        );

        final result = await handleAppPaused(
          messageRepo: messageRepo,
          groupMsgRepo: groupMsgRepo,
        );

        expect(result.transitionedCount, 0);
        expect(result.groupTransitionedCount, 1);

        final failed = await groupMsgRepo.getMessage('nw011-sending');
        expect(failed, isNotNull);
        expect(failed!.status, 'failed');
        expect(failed.wireEnvelope, '{"messageId":"nw011-sending"}');
        expect(
          failed.inboxRetryPayload,
          '{"groupId":"group-nw011","message":"retryable"}',
        );

        final pending = await groupMsgRepo.getMessage('nw011-pending');
        expect(pending, isNotNull);
        expect(pending!.status, 'pending');
        expect(
          pending.inboxRetryPayload,
          '{"groupId":"group-nw011","message":"pending-retry"}',
        );

        final sent = await groupMsgRepo.getMessage('nw011-sent');
        expect(sent, isNotNull);
        expect(sent!.status, 'sent');
        expect(sent.inboxStored, isTrue);
      },
    );
  });
}
