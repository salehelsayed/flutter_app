import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/conversation/application/recover_stuck_sending_messages_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';

import '../domain/repositories/fake_message_repository.dart';

ConversationMessage _makeSendingMessage({
  String id = 'msg-stuck-001',
  String contactPeerId = 'peer-target',
  String? wireEnvelope,
  Duration age = const Duration(minutes: 5),
}) {
  final ts = DateTime.now().toUtc().subtract(age).toIso8601String();
  return ConversationMessage(
    id: id,
    contactPeerId: contactPeerId,
    senderPeerId: 'my-peer-id',
    text: 'Hello',
    timestamp: ts,
    status: 'sending',
    isIncoming: false,
    createdAt: ts,
    wireEnvelope: wireEnvelope,
  );
}

void main() {
  group('recoverStuckSendingMessages use case', () {
    late FakeMessageRepository messageRepo;

    setUp(() {
      messageRepo = FakeMessageRepository();
    });

    test('returns 0 when no stuck sending messages exist', () async {
      final count = await recoverStuckSendingMessages(
        messageRepo: messageRepo,
        threshold: const Duration(seconds: 30),
      );
      expect(count, 0);
      expect(messageRepo.recoverStuckSendingCallCount, 1);
    });

    test('calls recoverStuckSendingMessages on repo once', () async {
      await recoverStuckSendingMessages(
        messageRepo: messageRepo,
        threshold: const Duration(seconds: 30),
      );
      expect(messageRepo.recoverStuckSendingCallCount, 1);
    });

    test('returns count reported by the repo', () async {
      messageRepo.recoverStuckSendingReturnValue = 2;

      final count = await recoverStuckSendingMessages(
        messageRepo: messageRepo,
        threshold: const Duration(seconds: 30),
      );
      expect(count, 2);
    });

    test('passes the configured threshold duration to the repo', () async {
      const threshold = Duration(seconds: 45);
      await recoverStuckSendingMessages(
        messageRepo: messageRepo,
        threshold: threshold,
      );
      expect(messageRepo.lastRecoverStuckSendingThreshold, threshold);
    });

    test('uses default threshold of 30 seconds when not specified', () async {
      await recoverStuckSendingMessages(messageRepo: messageRepo);
      expect(
        messageRepo.lastRecoverStuckSendingThreshold,
        const Duration(seconds: 30),
      );
    });
  });
}
