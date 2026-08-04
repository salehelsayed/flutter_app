import 'dart:async';
import 'dart:io';

import 'package:flutter_app/core/database/helpers/direct_notification_read_projection_db_helpers.dart';
import 'package:flutter_app/core/database/migrations/107_direct_notification_durability.dart';
import 'package:flutter_app/core/notifications/direct_notification_presentation_coordinator.dart';
import 'package:flutter_app/core/notifications/direct_notification_read_projector.dart';
import 'package:flutter_app/core/notifications/notification_service.dart';
import 'package:flutter_app/features/conversation/application/mark_conversation_read_use_case.dart';
import 'package:flutter_app/features/conversation/data/repositories/message_repository_impl.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  test(
    'TC-331-10 read acknowledges exact generation and preserves later sibling',
    () async {
      final coordinator = DirectNotificationPresentationCoordinator();
      final cancellation = _GenerationCancellation(
        const ConversationNotificationContentMetadata(
          kind: ConversationNotificationContentKind.message,
          eventIdentity: 'message-a',
          generation: 'generation-a',
        ),
      );
      final commitStarted = Completer<void>();
      final releaseCommit = Completer<void>();
      final projector = DirectNotificationReadProjector(
        coordinator: coordinator,
        cancellation: cancellation,
        commitRead: (peerId, metadata) async {
          expect(peerId, 'peer-a');
          expect(metadata?.generation, 'generation-a');
          commitStarted.complete();
          await releaseCommit.future;
          return const DirectConversationReadCommit(
            markedCount: 1,
            notificationAcknowledged: true,
          );
        },
      );

      final read = projector.markConversationRead('peer-a');
      await commitStarted.future;
      cancellation.current = const ConversationNotificationContentMetadata(
        kind: ConversationNotificationContentKind.message,
        eventIdentity: 'message-b',
        generation: 'generation-b',
      );
      releaseCommit.complete();

      expect(await read, 1);
      expect(cancellation.cancelAttempts, const ['generation-a']);
      expect(cancellation.current?.generation, 'generation-b');
    },
  );

  test(
    'production read journals canonical state and peer reconciliation atomically',
    () async {
      final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      addTearDown(db.close);
      await _createV106Minimum(db);
      await runDirectNotificationDurabilityMigration(db);
      await db.insert('contacts', <String, Object?>{
        'peer_id': 'peer-a',
        'is_archived': 0,
        'is_blocked': 0,
      });
      await db.insert('messages', <String, Object?>{
        'id': 'message-a',
        'contact_peer_id': 'peer-a',
        'sender_peer_id': 'peer-a',
        'timestamp': '2026-08-03T10:00:00.000Z',
        'is_incoming': 1,
        'read_at': null,
        'hidden_at': null,
        'deleted_at': null,
      });

      final cancellation = _GenerationCancellation(
        const ConversationNotificationContentMetadata(
          kind: ConversationNotificationContentKind.message,
          eventIdentity: 'message-a',
          generation: 'generation-a',
        ),
      );
      final projector = DirectNotificationReadProjector(
        coordinator: DirectNotificationPresentationCoordinator(),
        cancellation: cancellation,
        commitRead: (peerId, metadata) =>
            dbMarkDirectConversationReadAndAcknowledge(
              db,
              peerId: peerId,
              metadata: metadata,
              nowUtc: () => DateTime.utc(2026, 8, 3, 11),
            ),
      );
      var legacyFallbackCalls = 0;
      final repository = _messageRepository(
        projectConversationRead: projector.markConversationRead,
        legacyMarkRead: (_) async {
          legacyFallbackCalls++;
          return 0;
        },
      );

      expect(
        await markConversationRead(
          messageRepo: repository,
          contactPeerId: 'peer-a',
        ),
        1,
      );
      expect(legacyFallbackCalls, 0);
      expect(cancellation.cancelAttempts, const ['generation-a']);
      expect(
        (await db.query(
          'messages',
          where: 'id = ?',
          whereArgs: const ['message-a'],
        )).single['read_at'],
        '2026-08-03T11:00:00.000Z',
      );
      expect(
        await db.query(
          'direct_notification_reconciliation_outbox',
          where: 'peer_id = ?',
          whereArgs: const ['peer-a'],
        ),
        hasLength(1),
      );
      expect(
        await db.query('direct_notification_read_acknowledgements'),
        isEmpty,
      );
    },
  );

  test(
    'TC-331-15 identity-free current generation cancels after live open',
    () async {
      final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      addTearDown(db.close);
      await _createV106Minimum(db);
      await runDirectNotificationDurabilityMigration(db);
      await db.insert('contacts', <String, Object?>{
        'peer_id': 'peer-generic',
        'is_archived': 0,
        'is_blocked': 0,
      });
      final cancellation = _GenerationCancellation(
        const ConversationNotificationContentMetadata(
          kind: ConversationNotificationContentKind.message,
          generation: 'generation-generic',
        ),
      );
      final projector = DirectNotificationReadProjector(
        coordinator: DirectNotificationPresentationCoordinator(),
        cancellation: cancellation,
        commitRead: (peerId, metadata) =>
            dbMarkDirectConversationReadAndAcknowledge(
              db,
              peerId: peerId,
              metadata: metadata,
              nowUtc: () => DateTime.utc(2026, 8, 3, 12),
            ),
      );

      expect(await projector.markConversationRead('peer-generic'), 0);
      expect(cancellation.cancelAttempts, const ['generation-generic']);
      expect(cancellation.current, isNull);
    },
  );

  test('Conversation, Feed, and Orbit use the shared read use-case route', () {
    for (final path in const <String>[
      'lib/features/conversation/presentation/screens/conversation_wired.dart',
      'lib/features/feed/presentation/screens/feed_wired.dart',
      'lib/features/orbit/presentation/screens/orbit_wired.dart',
    ]) {
      final source = File(path).readAsStringSync();
      expect(
        RegExp(r'await\s+markConversationRead\s*\(').hasMatch(source),
        isTrue,
        reason: '$path must retain the atomic shared read route',
      );
      expect(
        source.contains('.markConversationAsRead('),
        isFalse,
        reason: '$path must not bypass the shared use case',
      );
    }
  });
}

MessageRepositoryImpl _messageRepository({
  required Future<int> Function(String peerId) projectConversationRead,
  required Future<int> Function(String peerId) legacyMarkRead,
}) => MessageRepositoryImpl(
  dbInsertMessage: (_) async {},
  dbLoadMessagesForContact: (_) async => const [],
  dbLoadLatestMessageForContact: (_) async => null,
  dbUpdateMessageStatus: (_, _) async => 0,
  dbLoadMessage: (_) async => null,
  dbCountMessagesForContact: (_) async => 0,
  dbMarkConversationAsRead: legacyMarkRead,
  projectConversationRead: projectConversationRead,
  dbCountUnreadForContact: (_) async => 0,
  dbCountTotalUnread: () async => 0,
  dbCountTotalUnreadExcludingArchived: () async => 0,
  dbDeleteMessagesForContact: (_) async => 0,
  dbDeleteMessage: (_) async => 0,
  dbExistsMessageByContent: (_, _, _, _) async => false,
  dbLoadMessagesPage: (_, {int limit = 50, String? beforeTimestamp}) async =>
      const [],
  dbLoadFailedOutgoingMessages: () async => const [],
  dbLoadUnackedOutgoingMessages:
      ({required DateTime olderThan, int limit = 50}) async => const [],
  dbLoadConversationThreadSummaries: (_) async => const [],
  dbRecoverStuckSendingMessages:
      ({required DateTime olderThan, int limit = 50}) async => 0,
  dbLoadStuckSendingOutgoingMessages:
      ({required DateTime olderThan, int limit = 50}) async => const [],
  dbLoadSendingOutgoingMessages: () async => const [],
  dbConditionalTransitionStatus:
      (_, {required String fromStatus, required String toStatus}) async => 0,
);

Future<void> _createV106Minimum(Database db) async {
  await db.execute('''
    CREATE TABLE contacts (
      peer_id TEXT PRIMARY KEY,
      is_archived INTEGER NOT NULL DEFAULT 0,
      is_blocked INTEGER NOT NULL DEFAULT 0
    )
  ''');
  await db.execute('''
    CREATE TABLE messages (
      id TEXT PRIMARY KEY,
      contact_peer_id TEXT NOT NULL,
      sender_peer_id TEXT NOT NULL,
      timestamp TEXT NOT NULL,
      is_incoming INTEGER NOT NULL,
      read_at TEXT,
      hidden_at TEXT,
      deleted_at TEXT
    )
  ''');
}

final class _GenerationCancellation
    implements ConversationNotificationGenerationCancellation {
  _GenerationCancellation(this.current);

  ConversationNotificationContentMetadata? current;
  final List<String> cancelAttempts = <String>[];

  @override
  Future<ConversationNotificationContentMetadata?>
  lookupConversationNotificationContentMetadata(String conversationKey) async {
    return current;
  }

  @override
  Future<bool> cancelConversationNotificationGeneration(
    String conversationKey,
    String generation,
  ) async {
    cancelAttempts.add(generation);
    if (current?.generation != generation) return false;
    current = null;
    return true;
  }
}
