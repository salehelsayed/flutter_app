import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';

import 'fake_message_repository.dart';

ConversationMessage _makeMsg({
  required String id,
  required String status,
  required Duration age,
  bool isIncoming = false,
  String? wireEnvelope,
}) {
  final ts = DateTime.now().toUtc().subtract(age).toIso8601String();
  return ConversationMessage(
    id: id,
    contactPeerId: 'peer-a',
    senderPeerId: 'me',
    text: 'msg',
    timestamp: ts,
    status: status,
    isIncoming: isIncoming,
    createdAt: ts,
    wireEnvelope: wireEnvelope,
  );
}

void main() {
  group('FakeMessageRepository.getStuckSendingOutgoingMessages', () {
    late FakeMessageRepository repo;

    setUp(() {
      repo = FakeMessageRepository();
    });

    test('returns empty list when no messages exist', () async {
      final result = await repo.getStuckSendingOutgoingMessages(
        olderThan: const Duration(seconds: 30),
      );
      expect(result, isEmpty);
    });

    test('returns sending messages older than threshold', () async {
      repo.seed([
        _makeMsg(id: 'old-sending', status: 'sending', age: const Duration(minutes: 5)),
      ]);
      final result = await repo.getStuckSendingOutgoingMessages(
        olderThan: const Duration(seconds: 30),
      );
      expect(result.length, 1);
      expect(result.first.id, 'old-sending');
    });

    test('excludes sending messages younger than threshold', () async {
      repo.seed([
        _makeMsg(id: 'young-sending', status: 'sending', age: const Duration(seconds: 5)),
      ]);
      final result = await repo.getStuckSendingOutgoingMessages(
        olderThan: const Duration(seconds: 30),
      );
      expect(result, isEmpty);
    });

    test('excludes non-sending statuses', () async {
      repo.seed([
        _makeMsg(id: 'msg-failed', status: 'failed', age: const Duration(minutes: 5)),
        _makeMsg(id: 'msg-sent', status: 'sent', age: const Duration(minutes: 5)),
        _makeMsg(id: 'msg-delivered', status: 'delivered', age: const Duration(minutes: 5)),
      ]);
      final result = await repo.getStuckSendingOutgoingMessages(
        olderThan: const Duration(seconds: 30),
      );
      expect(result, isEmpty);
    });

    test('excludes incoming messages regardless of status', () async {
      repo.seed([
        _makeMsg(
          id: 'incoming-sending',
          status: 'sending',
          age: const Duration(minutes: 5),
          isIncoming: true,
        ),
      ]);
      final result = await repo.getStuckSendingOutgoingMessages(
        olderThan: const Duration(seconds: 30),
      );
      expect(result, isEmpty);
    });

    test('returns messages with and without wireEnvelope', () async {
      repo.seed([
        _makeMsg(
          id: 'with-env',
          status: 'sending',
          age: const Duration(minutes: 5),
          wireEnvelope: '{"type":"chat_message"}',
        ),
        _makeMsg(
          id: 'no-env',
          status: 'sending',
          age: const Duration(minutes: 5),
        ),
      ]);
      final result = await repo.getStuckSendingOutgoingMessages(
        olderThan: const Duration(seconds: 30),
      );
      expect(result.length, 2);
    });
  });
}
