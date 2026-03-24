import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository_impl.dart';

// Helper that constructs a minimal MessageRepositoryImpl wired to an in-memory
// map, matching the pattern in message_repository_impl_test.dart.
MessageRepositoryImpl _buildRepo({
  required Map<String, Map<String, Object?>> store,
  required Future<int> Function({required DateTime olderThan, int limit})
      dbRecoverStuckSendingMessages,
}) {
  return MessageRepositoryImpl(
    dbInsertMessage: (row) async => store[row['id'] as String] = Map.from(row),
    dbLoadMessagesForContact: (cp) async =>
        store.values.where((r) => r['contact_peer_id'] == cp).toList(),
    dbLoadLatestMessageForContact: (cp) async => null,
    dbUpdateMessageStatus: (id, s) async {},
    dbLoadMessage: (id) async => store[id],
    dbCountMessagesForContact: (cp) async => 0,
    dbMarkConversationAsRead: (cp) async => 0,
    dbCountUnreadForContact: (cp) async => 0,
    dbCountTotalUnread: () async => 0,
    dbCountTotalUnreadExcludingArchived: () async => 0,
    dbDeleteMessagesForContact: (cp) async => 0,
    dbLoadMessagesPage: (cp, {int limit = 50, String? beforeTimestamp}) async =>
        [],
    dbLoadFailedOutgoingMessages: () async => [],
    dbLoadUnackedOutgoingMessages: ({required DateTime olderThan, int limit = 50}) async =>
        [],
    dbLoadConversationThreadSummaries: (ids) async => [],
    dbRecoverStuckSendingMessages: dbRecoverStuckSendingMessages,
    dbUpdateWireEnvelope: (id, wireEnvelope) async {},
    dbLoadStuckSendingOutgoingMessages: ({required DateTime olderThan, int limit = 50}) async => [],
    dbLoadSendingOutgoingMessages: () async => [],
    dbConditionalTransitionStatus: (id, {required fromStatus, required toStatus}) async => 0,
  );
}

void main() {
  group('MessageRepositoryImpl.recoverStuckSendingMessages', () {
    test('delegates to dbRecoverStuckSendingMessages with correct cutoff', () async {
      int helperCallCount = 0;
      DateTime? capturedOlderThan;

      final store = <String, Map<String, Object?>>{};
      final repo = _buildRepo(
        store: store,
        dbRecoverStuckSendingMessages: ({required DateTime olderThan, int limit = 50}) async {
          helperCallCount++;
          capturedOlderThan = olderThan;
          return 0;
        },
      );

      const threshold = Duration(seconds: 30);
      final before = DateTime.now().toUtc().subtract(threshold);
      await repo.recoverStuckSendingMessages(olderThan: threshold);
      final after = DateTime.now().toUtc().subtract(threshold);

      expect(helperCallCount, 1);
      // The cutoff passed to the helper must be between before and after
      expect(capturedOlderThan!.isAfter(before.subtract(const Duration(seconds: 1))), isTrue);
      expect(capturedOlderThan!.isBefore(after.add(const Duration(seconds: 1))), isTrue);
    });

    test('returns count from db helper', () async {
      final store = <String, Map<String, Object?>>{};
      final repo = _buildRepo(
        store: store,
        dbRecoverStuckSendingMessages:
            ({required DateTime olderThan, int limit = 50}) async => 3,
      );

      final count = await repo.recoverStuckSendingMessages(
        olderThan: const Duration(seconds: 30),
      );
      expect(count, 3);
    });

    test('returns 0 when helper returns 0', () async {
      final store = <String, Map<String, Object?>>{};
      final repo = _buildRepo(
        store: store,
        dbRecoverStuckSendingMessages:
            ({required DateTime olderThan, int limit = 50}) async => 0,
      );

      final count = await repo.recoverStuckSendingMessages(
        olderThan: const Duration(seconds: 30),
      );
      expect(count, 0);
    });
  });
}
