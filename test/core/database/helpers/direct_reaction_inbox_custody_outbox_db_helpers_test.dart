import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_app/core/database/helpers/direct_reaction_inbox_custody_outbox_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/reactions_db_helpers.dart';
import 'package:flutter_app/core/database/outgoing_transport_mutation.dart';
import 'package:flutter_app/core/database/production_migration_registry.dart';
import 'package:flutter_app/features/conversation/data/repositories/reaction_repository_impl.dart';
import 'package:flutter_app/features/conversation/domain/models/direct_reaction_inbox_custody_outbox_entry.dart';
import 'package:flutter_app/features/conversation/domain/models/message_reaction.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _recipient = 'peer-recipient';
const _sender = 'peer-self';
const _t0 = '2026-08-07T07:00:00.000Z';
const _t1 = '2026-08-07T07:00:01.000Z';
const _t2 = '2026-08-07T07:00:02.000Z';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tempDirectory;
  late Database db;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp(
      'direct_reaction_custody_helper_',
    );
    db = await databaseFactoryFfi.openDatabase(
      '${tempDirectory.path}/identity.db',
      options: OpenDatabaseOptions(
        version: 109,
        singleInstance: false,
        onCreate: runProductionOnCreate,
        onUpgrade: runProductionOnUpgrade,
      ),
    );
  });

  tearDown(() async {
    if (db.isOpen) await db.close();
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  test(
    'TC-349-01 ordinary text mutations stage atomically in shared v109',
    () async {
      const messageId = 'ordinary-edit-target';
      const eventId = '34900000-0000-4000-8000-000000000001';
      final initial = <String, Object?>{
        'id': messageId,
        'contact_peer_id': _recipient,
        'sender_peer_id': _sender,
        'text': 'before',
        'timestamp': _t0,
        'status': 'delivered',
        'is_incoming': 0,
        'created_at': _t0,
        'private_media_policy_version': 0,
        'private_media_mode': 'ordinary',
        'private_media_state': 'none',
      };
      await db.insert('messages', initial);
      final expected = (await db.query(
        'messages',
        where: 'id = ?',
        whereArgs: const <Object?>[messageId],
      )).single;
      final envelope = jsonEncode(<String, Object?>{
        'type': 'chat_message',
        'version': '2',
        'id': messageId,
        'eventId': eventId,
        'senderPeerId': _sender,
        'encrypted': const <String, Object?>{
          'kem': 'kem-edit',
          'ciphertext': 'cipher-edit',
          'nonce': 'nonce-edit',
        },
      });
      final staged = <String, Object?>{
        ...expected,
        'text': 'after',
        'status': 'sending',
        'edited_at': _t1,
        'wire_envelope': envelope,
      };

      final stage = await dbStageOutgoingDirectTextMutationInboxCustody(
        db,
        expectedRow: expected,
        stagedRow: staged,
        kind: OutgoingOrdinaryAttemptKind.edit,
        recipientPeerId: _recipient,
        eventId: eventId,
        wireEnvelope: envelope,
      );

      expect(stage.outcome, OutgoingOrdinaryMutationOutcome.applied);
      expect((await db.query('messages')).single['text'], 'after');
      final owner = (await db.query(
        'direct_reaction_inbox_custody_outbox',
      )).single;
      expect(owner['event_id'], eventId);
      expect(owner['wire_envelope'], envelope);
    },
  );

  test(
    'TC-343-02 atomic direct-reaction custody preserves every transition and fails closed',
    () async {
      expect(kDirectReactionInboxCustodyOutboxCapacity, 512);
      expect(kDirectReactionInboxCustodyOutboxMaxLoadBatch, 50);
      await _insertDirectTarget(db, 'target-main');

      var repository = _repository(db, capacity: 2);
      final add = _reaction(
        id: 'event-add',
        messageId: 'target-main',
        timestamp: _t0,
      );
      final addEnvelope = _envelope(add, action: 'add', cipher: 'cipher-add');
      final addStage = await repository.stageOutgoingDirectReactionInboxCustody(
        reaction: add,
        recipientPeerId: _recipient,
        action: 'add',
        wireEnvelope: addEnvelope,
      );
      expect(addStage.outcome, DirectReactionCustodyStageOutcome.applied);
      expect(addStage.authorizesTransport, isTrue);
      expect(addStage.reaction, same(add));
      expect(addStage.custody?.wireEnvelope, addEnvelope);

      final remove = _reaction(
        id: 'event-remove',
        messageId: 'target-main',
        timestamp: _t2,
      );
      final removeEnvelope = _envelope(
        remove,
        action: 'remove',
        cipher: 'cipher-remove',
      );
      final removeStage = await repository
          .stageOutgoingDirectReactionInboxCustody(
            reaction: remove,
            recipientPeerId: _recipient,
            action: 'remove',
            wireEnvelope: removeEnvelope,
          );
      expect(removeStage.outcome, DirectReactionCustodyStageOutcome.applied);
      expect(
        await db.query('direct_reaction_inbox_custody_outbox'),
        hasLength(2),
      );
      var canonical = (await db.query('message_reactions')).single;
      expect(canonical['id'], remove.id);
      expect(canonical['removed_at'], remove.timestamp);
      expect(canonical['emoji'], remove.emoji);

      final exactAtCapacity = await repository
          .stageOutgoingDirectReactionInboxCustody(
            reaction: add,
            recipientPeerId: _recipient,
            action: 'add',
            wireEnvelope: addEnvelope,
          );
      expect(
        exactAtCapacity.outcome,
        DirectReactionCustodyStageOutcome.idempotent,
      );
      expect(exactAtCapacity.custody?.eventId, add.id);
      canonical = (await db.query('message_reactions')).single;
      expect(canonical['id'], remove.id, reason: 'exact older replay is inert');

      final changedBytes = await repository
          .stageOutgoingDirectReactionInboxCustody(
            reaction: add,
            recipientPeerId: _recipient,
            action: 'add',
            wireEnvelope: _envelope(
              add,
              action: 'add',
              cipher: 'changed-cipher',
            ),
          );
      expect(changedBytes.outcome, DirectReactionCustodyStageOutcome.refused);
      expect(
        await db.query('direct_reaction_inbox_custody_outbox'),
        hasLength(2),
      );

      final capacityRefused = _reaction(
        id: 'event-capacity-refused',
        messageId: 'target-main',
        timestamp: '2026-08-07T07:00:03.000Z',
      );
      final capacityOutcome = await repository
          .stageOutgoingDirectReactionInboxCustody(
            reaction: capacityRefused,
            recipientPeerId: _recipient,
            action: 'add',
            wireEnvelope: _envelope(
              capacityRefused,
              action: 'add',
              cipher: 'capacity',
            ),
          );
      expect(
        capacityOutcome.outcome,
        DirectReactionCustodyStageOutcome.refused,
      );
      canonical = (await db.query('message_reactions')).single;
      expect(canonical['id'], remove.id, reason: 'capacity is all-or-nothing');

      await db.delete('direct_reaction_inbox_custody_outbox');
      await db.delete('message_reactions');
      repository = _repository(db, capacity: 10);

      await repository.stageOutgoingDirectReactionInboxCustody(
        reaction: add,
        recipientPeerId: _recipient,
        action: 'add',
        wireEnvelope: addEnvelope,
      );
      await repository.stageOutgoingDirectReactionInboxCustody(
        reaction: remove,
        recipientPeerId: _recipient,
        action: 'remove',
        wireEnvelope: removeEnvelope,
      );
      final crossedOlder = _reaction(
        id: 'event-crossed-older',
        messageId: 'target-main',
        timestamp: _t1,
      );
      final crossedOutcome = await repository
          .stageOutgoingDirectReactionInboxCustody(
            reaction: crossedOlder,
            recipientPeerId: _recipient,
            action: 'add',
            wireEnvelope: _envelope(
              crossedOlder,
              action: 'add',
              cipher: 'crossed',
            ),
          );
      expect(crossedOutcome.authorizesTransport, isTrue);
      expect(
        await db.query('direct_reaction_inbox_custody_outbox'),
        hasLength(3),
      );
      canonical = (await db.query('message_reactions')).single;
      expect(canonical['id'], remove.id);
      expect(canonical['removed_at'], remove.timestamp);

      await _insertDirectTarget(db, 'target-remove-before-add');
      final removeFirst = _reaction(
        id: 'event-remove-first',
        messageId: 'target-remove-before-add',
        timestamp: _t1,
      );
      final removeFirstOutcome = await repository
          .stageOutgoingDirectReactionInboxCustody(
            reaction: removeFirst,
            recipientPeerId: _recipient,
            action: 'remove',
            wireEnvelope: _envelope(
              removeFirst,
              action: 'remove',
              cipher: 'remove-first',
            ),
          );
      expect(removeFirstOutcome.authorizesTransport, isTrue);
      final removeFirstCanonical = (await db.query(
        'message_reactions',
        where: 'message_id = ?',
        whereArgs: const <Object?>['target-remove-before-add'],
      )).single;
      expect(removeFirstCanonical['id'], removeFirst.id);
      expect(removeFirstCanonical['removed_at'], removeFirst.timestamp);

      final wrongRecipient = _reaction(
        id: 'event-wrong-recipient',
        messageId: 'target-remove-before-add',
        timestamp: _t2,
      );
      expect(
        (await repository.stageOutgoingDirectReactionInboxCustody(
          reaction: wrongRecipient,
          recipientPeerId: 'different-recipient',
          action: 'add',
          wireEnvelope: _envelope(
            wrongRecipient,
            action: 'add',
            cipher: 'wrong-recipient',
          ),
        )).outcome,
        DirectReactionCustodyStageOutcome.refused,
      );

      final missing = _reaction(
        id: 'event-missing',
        messageId: 'missing-target',
        timestamp: _t2,
      );
      expect(
        (await repository.stageOutgoingDirectReactionInboxCustody(
          reaction: missing,
          recipientPeerId: _recipient,
          action: 'add',
          wireEnvelope: _envelope(missing, action: 'add', cipher: 'missing'),
        )).outcome,
        DirectReactionCustodyStageOutcome.refused,
      );

      await _insertDirectTarget(db, 'target-lane-collision');
      await _insertGroupTarget(db, 'target-lane-collision');
      final colliding = _reaction(
        id: 'event-lane-collision',
        messageId: 'target-lane-collision',
        timestamp: _t2,
      );
      expect(
        (await repository.stageOutgoingDirectReactionInboxCustody(
          reaction: colliding,
          recipientPeerId: _recipient,
          action: 'add',
          wireEnvelope: _envelope(
            colliding,
            action: 'add',
            cipher: 'collision',
          ),
        )).outcome,
        DirectReactionCustodyStageOutcome.refused,
      );

      final retained = crossedOutcome.custody!;
      expect(
        await repository.recordDirectReactionInboxCustodyFailureIfExact(
          expected: retained.copyWith(wireEnvelope: 'wrong-envelope'),
          errorCode: DirectReactionInboxCustodyErrorCode.storeFailed,
        ),
        isFalse,
      );
      expect(
        await repository.recordDirectReactionInboxCustodyFailureIfExact(
          expected: retained,
          errorCode: DirectReactionInboxCustodyErrorCode.storeFailed,
        ),
        isTrue,
      );
      final failedEntry = await repository
          .loadDirectReactionInboxCustodyForEvent(
            recipientPeerId: retained.recipientPeerId,
            eventId: retained.eventId,
          );
      expect(failedEntry?.retryCount, 1);
      expect(
        failedEntry?.lastErrorCode,
        DirectReactionInboxCustodyErrorCode.storeFailed,
      );

      await db.delete(
        'messages',
        where: 'id = ?',
        whereArgs: const <Object?>['target-main'],
      );
      await db.delete(
        'message_reactions',
        where: 'message_id = ?',
        whereArgs: const <Object?>['target-main'],
      );
      expect(
        await repository.loadDirectReactionInboxCustodyForEvent(
          recipientPeerId: retained.recipientPeerId,
          eventId: retained.eventId,
        ),
        isNotNull,
        reason: 'target/canonical deletion cannot cascade authored custody',
      );
      final replayAfterDeletion = await repository
          .stageOutgoingDirectReactionInboxCustody(
            reaction: crossedOlder,
            recipientPeerId: _recipient,
            action: 'add',
            wireEnvelope: retained.wireEnvelope,
          );
      expect(
        replayAfterDeletion.outcome,
        DirectReactionCustodyStageOutcome.idempotent,
      );

      expect(
        await repository.completeAcceptedDirectReactionInboxCustodyIfExact(
          expected: retained.copyWith(wireEnvelope: 'wrong-envelope'),
        ),
        DirectReactionInboxCustodyCompletionOutcome.stale,
      );
      expect(
        await repository.completeAcceptedDirectReactionInboxCustodyIfExact(
          expected: failedEntry!,
        ),
        DirectReactionInboxCustodyCompletionOutcome.completed,
      );
      expect(
        await repository.completeAcceptedDirectReactionInboxCustodyIfExact(
          expected: failedEntry,
        ),
        DirectReactionInboxCustodyCompletionOutcome.absent,
      );
      expect(
        await db.query(
          'message_reactions',
          where: 'message_id = ?',
          whereArgs: const <Object?>['target-main'],
        ),
        isEmpty,
        reason: 'completion never rebuilds the canonical projection',
      );

      await _insertDirectTarget(db, 'target-sql-abort');
      final sqlAbort = _reaction(
        id: 'event-sql-abort',
        messageId: 'target-sql-abort',
        timestamp: _t2,
      );
      await db.execute('''
CREATE TRIGGER abort_direct_reaction_custody_insert
BEFORE INSERT ON direct_reaction_inbox_custody_outbox
WHEN NEW.event_id = 'event-sql-abort'
BEGIN
  SELECT RAISE(ABORT, 'injected custody failure');
END
''');
      await expectLater(
        repository.stageOutgoingDirectReactionInboxCustody(
          reaction: sqlAbort,
          recipientPeerId: _recipient,
          action: 'add',
          wireEnvelope: _envelope(sqlAbort, action: 'add', cipher: 'sql-abort'),
        ),
        throwsA(anything),
      );
      expect(
        await db.query(
          'message_reactions',
          where: 'id = ?',
          whereArgs: const <Object?>['event-sql-abort'],
        ),
        isEmpty,
      );
      expect(
        await db.query(
          'direct_reaction_inbox_custody_outbox',
          where: 'event_id = ?',
          whereArgs: const <Object?>['event-sql-abort'],
        ),
        isEmpty,
      );
      await db.execute('DROP TRIGGER abort_direct_reaction_custody_insert');

      await db.delete('direct_reaction_inbox_custody_outbox');
      for (var index = 0; index < 55; index++) {
        final createdAt = DateTime.utc(
          2026,
          8,
          7,
          8,
        ).add(Duration(seconds: index)).toIso8601String();
        await db
            .insert('direct_reaction_inbox_custody_outbox', <String, Object?>{
              'recipient_peer_id': _recipient,
              'event_id': 'fair-${index.toString().padLeft(2, '0')}',
              'wire_envelope': 'opaque-$index',
              'retry_count': 0,
              'last_attempt_at': null,
              'last_error_code': null,
              'created_at': createdAt,
              'updated_at': createdAt,
            });
      }
      final clamped = await repository.loadDirectReactionInboxCustody(
        limit: 500,
      );
      expect(clamped, hasLength(50));
      expect(clamped.first.eventId, 'fair-00');
      expect(clamped.last.eventId, 'fair-49');
    },
  );

  test(
    'TC-343-02 crossed stages serialize atomic canonical and custody writes',
    () async {
      const targetId = 'target-crossed-transaction';
      await _insertDirectTarget(db, targetId);
      final observer = await databaseFactoryFfi.openDatabase(
        '${tempDirectory.path}/identity.db',
        options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
      );
      final newerRemove = _reaction(
        id: 'event-newer-remove',
        messageId: targetId,
        timestamp: _t2,
      );
      final olderAdd = _reaction(
        id: 'event-older-add',
        messageId: targetId,
        timestamp: _t1,
      );
      final transactionEntered = Completer<void>();
      final releaseTransaction = Completer<void>();

      try {
        final newerStage = dbStageOutgoingDirectReactionInboxCustody(
          db,
          reactionRow: newerRemove.copyWith(removedAt: _t2).toMap(),
          recipientPeerId: _recipient,
          action: 'remove',
          wireEnvelope: _envelope(
            newerRemove,
            action: 'remove',
            cipher: 'newer-remove',
          ),
          beforeCustodyInsertForTest: () async {
            transactionEntered.complete();
            await releaseTransaction.future;
          },
        );
        await transactionEntered.future;

        // A second connection sees neither half while the transaction is
        // paused between its canonical and custody writes.
        expect(
          await observer.query(
            'message_reactions',
            where: 'message_id = ?',
            whereArgs: const <Object?>[targetId],
          ),
          isEmpty,
        );
        expect(
          await observer.query(
            'direct_reaction_inbox_custody_outbox',
            where: 'event_id = ?',
            whereArgs: const <Object?>['event-newer-remove'],
          ),
          isEmpty,
        );

        var olderCompleted = false;
        final olderStage = dbStageOutgoingDirectReactionInboxCustody(
          db,
          reactionRow: olderAdd.toMap(),
          recipientPeerId: _recipient,
          action: 'add',
          wireEnvelope: _envelope(olderAdd, action: 'add', cipher: 'older-add'),
        ).whenComplete(() => olderCompleted = true);
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(
          olderCompleted,
          isFalse,
          reason: 'the crossed stage must wait for the owning transaction',
        );

        releaseTransaction.complete();
        expect(
          (await newerStage).outcome,
          DirectReactionCustodyStageOutcome.applied,
        );
        expect(
          (await olderStage).outcome,
          DirectReactionCustodyStageOutcome.applied,
        );

        final canonical = (await db.query(
          'message_reactions',
          where: 'message_id = ?',
          whereArgs: const <Object?>[targetId],
        )).single;
        expect(canonical['id'], newerRemove.id);
        expect(canonical['removed_at'], newerRemove.timestamp);
        final custody = await db.query(
          'direct_reaction_inbox_custody_outbox',
          where: 'event_id IN (?, ?)',
          whereArgs: const <Object?>['event-newer-remove', 'event-older-add'],
        );
        expect(custody, hasLength(2));
      } finally {
        if (!releaseTransaction.isCompleted) releaseTransaction.complete();
        await observer.close();
      }
    },
  );
}

ReactionRepositoryImpl _repository(Database db, {required int capacity}) =>
    ReactionRepositoryImpl(
      dbInsertReaction: (row) => dbInsertReaction(db, row),
      dbLoadReactionsForMessage: (messageId) =>
          dbLoadReactionsForMessage(db, messageId),
      dbLoadReactionsForMessages: (messageIds) =>
          dbLoadReactionsForMessages(db, messageIds),
      dbLoadActiveOrTombstonedReactionForSender: (messageId, senderPeerId) =>
          dbLoadActiveOrTombstonedReactionForSender(
            db,
            messageId,
            senderPeerId,
          ),
      dbDeleteReaction: (messageId, senderPeerId, {removedAtTimestamp}) =>
          dbDeleteReaction(
            db,
            messageId,
            senderPeerId,
            removedAtTimestamp: removedAtTimestamp,
          ),
      dbDeleteReactionsForMessage: (messageId) =>
          dbDeleteReactionsForMessage(db, messageId),
      dbDeleteReactionsForContact: (contactPeerId) =>
          dbDeleteReactionsForContact(db, contactPeerId),
      dbStageOutgoingDirectReactionInboxCustody:
          ({
            required reactionRow,
            required recipientPeerId,
            required action,
            required wireEnvelope,
          }) => dbStageOutgoingDirectReactionInboxCustody(
            db,
            reactionRow: reactionRow,
            recipientPeerId: recipientPeerId,
            action: action,
            wireEnvelope: wireEnvelope,
            capacity: capacity,
          ),
      dbLoadDirectReactionInboxCustodyOutbox: ({limit = 50}) =>
          dbLoadDirectReactionInboxCustodyOutbox(db, limit: limit),
      dbLoadDirectReactionInboxCustodyOutboxForEvent:
          ({required recipientPeerId, required eventId}) =>
              dbLoadDirectReactionInboxCustodyOutboxForEvent(
                db,
                recipientPeerId: recipientPeerId,
                eventId: eventId,
              ),
      dbRecordDirectReactionInboxCustodyFailureIfExact:
          ({
            required recipientPeerId,
            required eventId,
            required expectedWireEnvelope,
            required errorCode,
            required attemptedAt,
          }) => dbRecordDirectReactionInboxCustodyFailureIfExact(
            db,
            recipientPeerId: recipientPeerId,
            eventId: eventId,
            expectedWireEnvelope: expectedWireEnvelope,
            errorCode: errorCode,
            attemptedAt: attemptedAt,
          ),
      dbCompleteAcceptedDirectReactionInboxCustodyIfExact:
          ({
            required recipientPeerId,
            required eventId,
            required expectedWireEnvelope,
          }) => dbCompleteAcceptedDirectReactionInboxCustodyIfExact(
            db,
            recipientPeerId: recipientPeerId,
            eventId: eventId,
            expectedWireEnvelope: expectedWireEnvelope,
          ),
      now: () => DateTime.parse('2026-08-07T09:00:00.000Z'),
    );

MessageReaction _reaction({
  required String id,
  required String messageId,
  required String timestamp,
}) => MessageReaction(
  id: id,
  messageId: messageId,
  emoji: '👍',
  senderPeerId: _sender,
  timestamp: timestamp,
  createdAt: timestamp,
);

String _envelope(
  MessageReaction reaction, {
  required String action,
  required String cipher,
}) => jsonEncode(<String, Object?>{
  'type': 'message_reaction',
  'version': '2',
  'senderPeerId': reaction.senderPeerId,
  'eventId': reaction.id,
  'action': action,
  'targetMessageId': reaction.messageId,
  'encrypted': <String, Object?>{
    'kem': 'kem-${reaction.id}',
    'ciphertext': cipher,
    'nonce': 'nonce-${reaction.id}',
  },
});

Future<void> _insertDirectTarget(Database db, String id) {
  return db.insert('messages', <String, Object?>{
    'id': id,
    'contact_peer_id': _recipient,
    'sender_peer_id': 'peer-contact',
    'text': 'target',
    'timestamp': _t0,
    'status': 'delivered',
    'is_incoming': 1,
    'created_at': _t0,
  });
}

Future<void> _insertGroupTarget(Database db, String id) {
  return db.insert('group_messages', <String, Object?>{
    'id': id,
    'group_id': 'group-1',
    'sender_peer_id': 'peer-group',
    'sender_username': 'Group peer',
    'text': 'group target',
    'timestamp': _t0,
    'key_generation': 0,
    'status': 'delivered',
    'is_incoming': 1,
    'created_at': _t0,
  });
}
