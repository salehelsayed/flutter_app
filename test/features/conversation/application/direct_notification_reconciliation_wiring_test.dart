import 'dart:io';

import 'package:flutter_app/core/database/helpers/direct_notification_reconciliation_outbox_db_helpers.dart';
import 'package:flutter_app/core/database/migrations/107_direct_notification_durability.dart';
import 'package:flutter_app/core/notifications/direct_notification_canonical_reconciler.dart';
import 'package:flutter_app/core/notifications/direct_notification_presentation_coordinator.dart';
import 'package:flutter_app/core/notifications/notification_service.dart';
import 'package:flutter_app/features/conversation/application/direct_notification_projection_owner.dart';
import 'package:flutter_app/features/conversation/data/repositories/direct_notification_reconciliation_outbox_repository_impl.dart';
import 'package:flutter_app/features/conversation/domain/models/direct_notification_display_outbox_entry.dart';
import 'package:flutter_app/features/conversation/domain/models/direct_notification_reaction_terminal_event.dart';
import 'package:flutter_app/features/conversation/domain/repositories/direct_notification_display_outbox_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/direct_notification_reaction_terminal_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/direct_notification_reconciliation_outbox_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  test('all policy mutations rebuild one peer card', () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);
    await _createV106Minimum(db);
    await runDirectNotificationDurabilityMigration(db);
    await db.insert('contacts', const <String, Object?>{
      'peer_id': 'peer-policy',
      'is_archived': 0,
      'is_blocked': 0,
    });
    await db.delete('direct_notification_reconciliation_outbox');
    await db.insert('messages', const <String, Object?>{
      'id': 'message-policy',
      'contact_peer_id': 'peer-policy',
      'sender_peer_id': 'peer-policy',
      'timestamp': '2026-08-03T10:00:00.000Z',
      'is_incoming': 1,
      'read_at': null,
      'hidden_at': null,
      'deleted_at': null,
    });

    await db.update(
      'messages',
      const <String, Object?>{'read_at': '2026-08-03T10:01:00.000Z'},
      where: 'id = ?',
      whereArgs: const ['message-policy'],
    );
    await db.update(
      'messages',
      const <String, Object?>{'hidden_at': '2026-08-03T10:02:00.000Z'},
      where: 'id = ?',
      whereArgs: const ['message-policy'],
    );
    await db.update(
      'messages',
      const <String, Object?>{'deleted_at': '2026-08-03T10:03:00.000Z'},
      where: 'id = ?',
      whereArgs: const ['message-policy'],
    );
    await db.delete(
      'messages',
      where: 'id = ?',
      whereArgs: const ['message-policy'],
    );
    await db.update(
      'contacts',
      const <String, Object?>{'is_archived': 1},
      where: 'peer_id = ?',
      whereArgs: const ['peer-policy'],
    );
    await db.update(
      'contacts',
      const <String, Object?>{'is_blocked': 1},
      where: 'peer_id = ?',
      whereArgs: const ['peer-policy'],
    );
    await db.delete(
      'contacts',
      where: 'peer_id = ?',
      whereArgs: const ['peer-policy'],
    );
    // Reaction REMOVE uses this same production enqueue seam after its typed
    // terminal is deleted; it must coalesce with every trigger above.
    await dbEnqueueDirectNotificationReconciliationOutbox(
      db,
      peerId: 'peer-policy',
    );

    final before = (await db.query(
      'direct_notification_reconciliation_outbox',
    )).single;
    expect(before['peer_id'], 'peer-policy');
    expect(before['revision'], 8);

    final service = _GenerationService(
      const ConversationNotificationContentMetadata(
        kind: ConversationNotificationContentKind.message,
        eventIdentity: 'message-policy',
        generation: 'generation-policy',
      ),
    );
    final owner = _owner(
      reconciliationOutbox: _realOutbox(db),
      service: service,
      decision: DirectNotificationCanonicalContentDecision.retire,
    );
    addTearDown(owner.dispose);

    await owner.retryNow();

    expect(
      await db.query('direct_notification_reconciliation_outbox'),
      isEmpty,
    );
    expect(service.cancelledGenerations, const ['generation-policy']);
    expect(service.replacements, isEmpty);
  });

  test('unknown materialization retains restart-safe reconciliation', () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);
    await _createV106Minimum(db);
    await runDirectNotificationDurabilityMigration(db);
    await dbEnqueueDirectNotificationReconciliationOutbox(
      db,
      peerId: 'peer-push-before-inbox',
    );
    final service = _GenerationService(
      const ConversationNotificationContentMetadata(
        kind: ConversationNotificationContentKind.message,
        eventIdentity: 'not-materialized',
        generation: 'generation-pending',
      ),
    );
    final owner = _owner(
      reconciliationOutbox: _realOutbox(db),
      service: service,
      decision: DirectNotificationCanonicalContentDecision.unknown,
    );
    addTearDown(owner.dispose);

    await owner.retryNow();

    final retained = (await db.query(
      'direct_notification_reconciliation_outbox',
    )).single;
    expect(retained['peer_id'], 'peer-push-before-inbox');
    expect(retained['retry_count'], 1);
    expect(retained['next_attempt_at'], isNotNull);
    expect(service.cancelledGenerations, isEmpty);
    expect(service.replacements, isEmpty);
  });

  test(
    'generation race resnapshots and never overwrites newer sibling',
    () async {
      final service = _GenerationService(
        const ConversationNotificationContentMetadata(
          kind: ConversationNotificationContentKind.message,
          eventIdentity: 'message-a',
          generation: 'generation-a',
        ),
      )..rejectFirstReplacementWithNewerSibling = true;
      final reconciler = DirectNotificationCanonicalReconciler(
        coordinator: DirectNotificationPresentationCoordinator(),
        generationCancellation: service,
        generationReplacement: service,
        isCurrentContentCanonical: (_, _) async =>
            DirectNotificationCanonicalContentDecision.keep,
        loadReplacement: (_, metadata) async =>
            CanonicalConversationNotificationReplacement(
              senderUsername: 'Alice',
              messageText: metadata.eventIdentity ?? 'unknown',
              routePayload: 'peer-race',
              contentKind: metadata.kind,
              eventIdentity: metadata.eventIdentity ?? 'unknown',
            ),
      );

      await reconciler.reconcile('peer-race');

      expect(service.replacementExpectedGenerations, const [
        'generation-a',
        'generation-b',
      ]);
      expect(service.metadata?.eventIdentity, 'message-b');
      expect(service.metadata?.generation, 'replacement-1');
    },
  );

  test('production bootstrap composes every direct durability owner', () {
    final source = File(
      'lib/app/bootstrap/production_application_bootstrap.dart',
    ).readAsStringSync();
    for (final anchor in const <String>[
      'DirectNotificationDisplayOutboxRepositoryImpl(',
      'DirectNotificationReadAcknowledgementRepositoryImpl(',
      'DirectNotificationReactionTerminalRepositoryImpl(',
      'DirectNotificationReconciliationOutboxRepositoryImpl(',
      'projectConversationRead:',
      'DirectNotificationProjectionOwner(',
      'stageNotificationDisplayCustody:',
      'promoteNotificationDisplayCustody:',
      'commitNotificationRemove:',
      'retryDirectNotificationProjection:',
    ]) {
      expect(source, contains(anchor), reason: 'missing production $anchor');
    }
  });
}

DirectNotificationProjectionOwner _owner({
  required DirectNotificationReconciliationOutboxRepository
  reconciliationOutbox,
  required _GenerationService service,
  required DirectNotificationCanonicalContentDecision decision,
}) {
  final coordinator = DirectNotificationPresentationCoordinator();
  return DirectNotificationProjectionOwner(
    displayOutbox: _EmptyDisplayOutbox(),
    reconciliationOutbox: reconciliationOutbox,
    reactionTerminal: _EmptyReactionTerminal(),
    coordinator: coordinator,
    projectDisplay: (_) async => NotificationPresentationResult.shown,
    canonicalReconciler: DirectNotificationCanonicalReconciler(
      coordinator: coordinator,
      generationCancellation: service,
      generationReplacement: service,
      isCurrentContentCanonical: (_, _) async => decision,
      loadReplacement: (_, _) async => null,
    ),
    enqueueReconciliation: (_) async {},
    nowUtc: () => DateTime.utc(2026, 8, 3, 12),
    retryDelay: const Duration(hours: 1),
  );
}

DirectNotificationReconciliationOutboxRepository _realOutbox(Database db) =>
    DirectNotificationReconciliationOutboxRepositoryImpl(
      dbLoadEligible: ({int limit = 20, required String eligibleAt}) =>
          dbLoadEligibleDirectNotificationReconciliationOutboxEntries(
            db,
            limit: limit,
            eligibleAt: eligibleAt,
          ),
      dbLoadEarliestNextAttemptAt: () =>
          dbLoadEarliestDirectNotificationReconciliationOutboxNextAttemptAt(db),
      dbRecordFailureIfExact:
          ({
            required peerId,
            required expectedIncarnationId,
            required expectedRevision,
            required lastAttemptAt,
            required nextAttemptAt,
            required updatedAt,
          }) => dbRecordDirectNotificationReconciliationOutboxFailureIfExact(
            db,
            peerId: peerId,
            expectedIncarnationId: expectedIncarnationId,
            expectedRevision: expectedRevision,
            lastAttemptAt: lastAttemptAt,
            nextAttemptAt: nextAttemptAt,
            updatedAt: updatedAt,
          ),
      dbCompleteIfExact:
          ({
            required peerId,
            required expectedIncarnationId,
            required expectedRevision,
          }) => dbCompleteDirectNotificationReconciliationOutboxIfExact(
            db,
            peerId: peerId,
            expectedIncarnationId: expectedIncarnationId,
            expectedRevision: expectedRevision,
          ),
      now: () => DateTime.utc(2026, 8, 3, 12),
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

final class _GenerationService
    implements
        ConversationNotificationGenerationCancellation,
        ConversationNotificationGenerationReplacement {
  _GenerationService(this.metadata);

  ConversationNotificationContentMetadata? metadata;
  bool rejectFirstReplacementWithNewerSibling = false;
  final List<String> cancelledGenerations = <String>[];
  final List<CanonicalConversationNotificationReplacement> replacements = [];
  final List<String> replacementExpectedGenerations = <String>[];

  @override
  Future<ConversationNotificationContentMetadata?>
  lookupConversationNotificationContentMetadata(String conversationKey) async =>
      metadata;

  @override
  Future<bool> cancelConversationNotificationGeneration(
    String conversationKey,
    String generation,
  ) async {
    if (metadata?.generation != generation) return false;
    cancelledGenerations.add(generation);
    metadata = null;
    return true;
  }

  @override
  Future<bool> replaceConversationNotificationGeneration(
    String conversationKey,
    String expectedGeneration,
    CanonicalConversationNotificationReplacement replacement,
  ) async {
    replacementExpectedGenerations.add(expectedGeneration);
    if (rejectFirstReplacementWithNewerSibling &&
        replacementExpectedGenerations.length == 1) {
      metadata = const ConversationNotificationContentMetadata(
        kind: ConversationNotificationContentKind.message,
        eventIdentity: 'message-b',
        generation: 'generation-b',
      );
      return false;
    }
    if (metadata?.generation != expectedGeneration) return false;
    replacements.add(replacement);
    metadata = ConversationNotificationContentMetadata(
      kind: replacement.contentKind,
      eventIdentity: replacement.eventIdentity,
      generation: 'replacement-${replacements.length}',
    );
    return true;
  }
}

final class _EmptyDisplayOutbox
    implements DirectNotificationDisplayOutboxRepository {
  @override
  Future<void> stage(DirectNotificationDisplayOutboxEntry entry) async {}

  @override
  Future<DirectNotificationDisplayOutboxEntry?> loadExact({
    required String peerId,
    required String eventKind,
    required String eventId,
  }) async => null;

  @override
  Future<bool> promoteReadyIfExact({
    required String peerId,
    required String eventKind,
    required String eventId,
    required int expectedRevision,
  }) async => false;

  @override
  Future<List<DirectNotificationDisplayOutboxEntry>> loadReady({
    int limit = 20,
  }) async => const [];

  @override
  Future<DateTime?> loadEarliestNextAttemptAt() async => null;

  @override
  Future<bool> recordRetryIfExact({
    required String peerId,
    required String eventKind,
    required String eventId,
    required int expectedRevision,
    required String lastErrorCode,
    required DateTime nextAttemptAt,
  }) async => false;

  @override
  Future<bool> completeIfExact(
    DirectNotificationDisplayOutboxEntry _, {
    Object? outcome,
  }) async => false;

  @override
  Future<bool> retireIfExact(DirectNotificationDisplayOutboxEntry _) async =>
      false;

  @override
  Future<int> deleteForPeer(String _) async => 0;

  @override
  Future<int> deleteForMessage({
    required String peerId,
    required String messageId,
  }) async => 0;

  @override
  Future<int> deleteForReactionActor({
    required String peerId,
    required String messageId,
    required String actorPeerId,
  }) async => 0;
}

final class _EmptyReactionTerminal
    implements DirectNotificationReactionTerminalRepository {
  @override
  Future<bool> upsert({
    required String peerId,
    required String messageId,
    required String actorPeerId,
    required String reactionId,
    required String terminalEventId,
  }) async => true;

  @override
  Future<DirectNotificationReactionTerminalEvent?> loadExact({
    required String peerId,
    required String messageId,
    required String actorPeerId,
  }) async => null;

  @override
  Future<DirectNotificationReactionTerminalEvent?> loadByTerminalEvent({
    required String peerId,
    required String terminalEventId,
  }) async => null;

  @override
  Future<bool> markAcknowledgedIfExact({
    required String peerId,
    required String messageId,
    required String actorPeerId,
    required String terminalEventId,
  }) async => false;

  @override
  Future<bool> consumeAcknowledgementIfExact({
    required String peerId,
    required String messageId,
    required String actorPeerId,
    required String terminalEventId,
    required String generation,
  }) async => false;

  @override
  Future<int> deleteForActor({
    required String peerId,
    required String messageId,
    required String actorPeerId,
  }) async => 0;

  @override
  Future<int> deleteForMessage({
    required String peerId,
    required String messageId,
  }) async => 0;

  @override
  Future<int> deleteForPeer(String peerId) async => 0;
}
