import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/conversation/application/mark_conversation_read_use_case.dart';

import '../../conversation/domain/repositories/fake_message_repository.dart';

void main() {
  late FakeMessageRepository messageRepo;

  setUp(() {
    messageRepo = FakeMessageRepository();
  });

  group('markConversationRead', () {
    test('returns count from repo', () async {
      messageRepo.markAsReadReturnValue = 5;

      final count = await markConversationRead(
        messageRepo: messageRepo,
        contactPeerId: 'peer-abc',
      );

      expect(count, 5);
      expect(messageRepo.markConversationAsReadCallCount, 1);
    });

    test('passes correct contactPeerId to repo', () async {
      const targetPeerId = 'peer-mark-read-xyz';

      await markConversationRead(
        messageRepo: messageRepo,
        contactPeerId: targetPeerId,
      );

      expect(messageRepo.lastMarkReadContactPeerId, targetPeerId);
    });

    test('returns 0 when no unread messages', () async {
      // markAsReadReturnValue defaults to 0
      final count = await markConversationRead(
        messageRepo: messageRepo,
        contactPeerId: 'peer-no-unread',
      );

      expect(count, 0);
    });
  });
}
