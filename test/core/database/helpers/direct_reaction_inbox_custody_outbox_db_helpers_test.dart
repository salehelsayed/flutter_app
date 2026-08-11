import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_app/core/database/app_database_version.dart';
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

  test('TC-353-03 media caption edit reuses one exact v109 lifecycle', () async {
    const relayExpiresAt = 1900000060000;
    var eventSeq = 0;
    String nextEventId() =>
        '35300000-0000-4000-8000-${(++eventSeq).toString().padLeft(12, '0')}';

    String editEnvelope(String messageId, String eventId) =>
        jsonEncode(<String, Object?>{
          'type': 'chat_message',
          'version': '2',
          'id': messageId,
          'eventId': eventId,
          'senderPeerId': _sender,
          'encrypted': <String, Object?>{
            'kem': 'kem-353',
            'ciphertext': 'cipher-$eventId',
            'nonce': 'nonce-353',
          },
        });

    /// Seeds one already-authorized caption EDIT: the parent projects the
    /// exact edit attempt and the raw event is retained in v109.
    Future<({String messageId, String eventId, String envelope})>
    seedStagedCaptionEdit(String suffix, {bool withAttachment = true}) async {
      final messageId = 'tc353-03-$suffix';
      final eventId = nextEventId();
      final envelope = editEnvelope(messageId, eventId);
      await db.insert('messages', <String, Object?>{
        'id': messageId,
        'contact_peer_id': _recipient,
        'sender_peer_id': _sender,
        'text': 'edited caption',
        'timestamp': _t0,
        'status': 'sending',
        'is_incoming': 0,
        'created_at': _t0,
        'edited_at': _t1,
        'wire_envelope': envelope,
        'private_media_policy_version': 0,
        'private_media_mode': 'ordinary',
        'private_media_state': 'none',
      });
      if (withAttachment) {
        await db.insert('media_attachments', <String, Object?>{
          'id': '$messageId-a',
          'message_id': messageId,
          'owner_lane': 'direct',
          'mime': 'image/jpeg',
          'size': 800,
          'media_type': 'image',
          'created_at': _t0,
          'download_status': 'done',
          'local_path': 'media/direct/$messageId-a.jpg',
        });
      }
      await db.insert('direct_reaction_inbox_custody_outbox', <String, Object?>{
        'recipient_peer_id': _recipient,
        'event_id': eventId,
        'wire_envelope': envelope,
        'retry_count': 0,
        'last_attempt_at': null,
        'last_error_code': null,
        'created_at': _t0,
        'updated_at': _t0,
      });
      return (messageId: messageId, eventId: eventId, envelope: envelope);
    }

    Future<DirectMutationInboxCustodyCompletionOutcome> complete(
      ({String messageId, String eventId, String envelope}) staged,
    ) => dbCompleteAcceptedDirectMutationInboxCustodyIfExact(
      db,
      recipientPeerId: _recipient,
      eventId: staged.eventId,
      expectedWireEnvelope: staged.envelope,
      relayExpiresAt: relayExpiresAt,
    );

    Future<Map<String, Object?>> parentOf(String messageId) async =>
        (await db.query(
          'messages',
          where: 'id = ?',
          whereArgs: <Object?>[messageId],
        )).single;

    // 1. Physical attachments present: stage-time authority is decisive, so
    //    acceptance settles the exact current parent and retires only its row.
    final present = await seedStagedCaptionEdit('attachments-present');
    final attachmentsBefore = await db.query(
      'media_attachments',
      where: 'message_id = ?',
      whereArgs: <Object?>[present.messageId],
    );
    expect(
      await complete(present),
      DirectMutationInboxCustodyCompletionOutcome.completed,
    );
    final settled = await parentOf(present.messageId);
    expect(settled['status'], 'inboxed');
    expect(settled['transport'], 'inbox');
    expect(settled['relay_expires_at'], relayExpiresAt);
    expect(settled['custody_checked_at'], isNull);
    expect(settled['text'], 'edited caption');
    expect(
      await db.query(
        'media_attachments',
        where: 'message_id = ?',
        whereArgs: <Object?>[present.messageId],
      ),
      attachmentsBefore,
      reason: 'completion must never inspect or mutate blob state',
    );
    expect(
      await db.query(
        'direct_reaction_inbox_custody_outbox',
        where: 'event_id = ?',
        whereArgs: <Object?>[present.eventId],
      ),
      isEmpty,
    );

    // 2. Locally evicted attachments converge identically.
    final evicted = await seedStagedCaptionEdit(
      'attachments-evicted',
      withAttachment: false,
    );
    expect(
      await complete(evicted),
      DirectMutationInboxCustodyCompletionOutcome.completed,
    );
    expect((await parentOf(evicted.messageId))['status'], 'inboxed');

    // 3. A newer edit already won: the event retires without regressing it.
    final superseded = await seedStagedCaptionEdit('newer-edit');
    final newerEnvelope = editEnvelope(superseded.messageId, nextEventId());
    await db.update(
      'messages',
      <String, Object?>{
        'text': 'newest caption',
        'edited_at': _t2,
        'status': 'sending',
        'wire_envelope': newerEnvelope,
      },
      where: 'id = ?',
      whereArgs: <Object?>[superseded.messageId],
    );
    final newerBefore = await parentOf(superseded.messageId);
    expect(
      await complete(superseded),
      DirectMutationInboxCustodyCompletionOutcome.completed,
    );
    expect(await parentOf(superseded.messageId), newerBefore);

    // 4. A deletion winner and an absent parent both converge. A staged
    //    tombstone replaces the parent's projected envelope, exactly as the
    //    Plan 351 media deletion owner commits it.
    final deleted = await seedStagedCaptionEdit('deleted-parent');
    await db.update(
      'messages',
      <String, Object?>{
        'text': '',
        'status': 'sending',
        'deleted_at': _t2,
        'deleted_by_peer_id': _sender,
        'wire_envelope': jsonEncode(<String, Object?>{
          'type': 'message_deletion',
          'version': '2',
          'eventId': nextEventId(),
          'senderPeerId': _sender,
          'encrypted': const <String, Object?>{
            'kem': 'kem-353',
            'ciphertext': 'cipher-tombstone',
            'nonce': 'nonce-353',
          },
        }),
      },
      where: 'id = ?',
      whereArgs: <Object?>[deleted.messageId],
    );
    final deletedBefore = await parentOf(deleted.messageId);
    expect(
      await complete(deleted),
      DirectMutationInboxCustodyCompletionOutcome.completed,
    );
    expect(await parentOf(deleted.messageId), deletedBefore);

    final absent = await seedStagedCaptionEdit('absent-parent');
    await db.delete(
      'messages',
      where: 'id = ?',
      whereArgs: <Object?>[absent.messageId],
    );
    expect(
      await complete(absent),
      DirectMutationInboxCustodyCompletionOutcome.completed,
    );

    // 5. Duplicate acceptance is explicit convergence; a crossed envelope is
    //    stale and retains the exact event.
    expect(
      await complete(present),
      DirectMutationInboxCustodyCompletionOutcome.absent,
    );
    final retained = await seedStagedCaptionEdit('crossed-envelope');
    expect(
      await dbCompleteAcceptedDirectMutationInboxCustodyIfExact(
        db,
        recipientPeerId: _recipient,
        eventId: retained.eventId,
        expectedWireEnvelope: editEnvelope(
          retained.messageId,
          retained.eventId,
        ).replaceAll('cipher-', 'forged-'),
        relayExpiresAt: relayExpiresAt,
      ),
      DirectMutationInboxCustodyCompletionOutcome.stale,
    );
    expect(
      await db.query(
        'direct_reaction_inbox_custody_outbox',
        where: 'event_id = ?',
        whereArgs: <Object?>[retained.eventId],
      ),
      hasLength(1),
    );
    expect((await parentOf(retained.messageId))['status'], 'sending');
  });

  test('TC-356-01b private deletion v109 stage and completion preserve '
      'independent lifecycle authority', () async {
    const relayExpiresAt = 1900000060000;
    final current = await databaseFactoryFfi.openDatabase(
      '${tempDirectory.path}/current.db',
      options: OpenDatabaseOptions(
        version: currentIdentityDatabaseVersion,
        singleInstance: false,
        onCreate: runProductionOnCreate,
        onUpgrade: runProductionOnUpgrade,
      ),
    );
    addTearDown(current.close);

    var eventSeq = 0;
    String nextEventId() =>
        '35600000-0000-4000-8000-${(++eventSeq).toString().padLeft(12, '0')}';

    String deletionEnvelope(String eventId) => jsonEncode(<String, Object?>{
      'type': 'message_deletion',
      'version': '2',
      'eventId': eventId,
      'senderPeerId': _sender,
      'encrypted': <String, Object?>{
        'kem': 'kem-356',
        'ciphertext': 'cipher-$eventId',
        'nonce': 'nonce-356',
      },
    });

    String editEnvelope(String messageId, String eventId) =>
        jsonEncode(<String, Object?>{
          'type': 'chat_message',
          'version': '2',
          'id': messageId,
          'eventId': eventId,
          'senderPeerId': _sender,
          'encrypted': <String, Object?>{
            'kem': 'kem-356',
            'ciphertext': 'cipher-$eventId',
            'nonce': 'nonce-356',
          },
        });

    /// Seeds one already-staged private deletion: the exact P/VO tombstone
    /// projects the deletion envelope and the raw event is retained in v109.
    Future<({String messageId, String eventId, String envelope})>
    seedStagedPrivateDeletion(
      String suffix, {
      String mode = 'protected',
      String? hiddenAt,
      bool asEdit = false,
      int? durationSeconds,
      String state = 'available',
    }) async {
      final messageId = 'tc356-01b-$suffix';
      final eventId = nextEventId();
      final envelope = asEdit
          ? editEnvelope(messageId, eventId)
          : deletionEnvelope(eventId);
      await current.insert('messages', <String, Object?>{
        'id': messageId,
        'contact_peer_id': _recipient,
        'sender_peer_id': _sender,
        'text': asEdit ? 'edited private caption' : '',
        'timestamp': _t0,
        'status': 'sending',
        'is_incoming': 0,
        'created_at': _t0,
        'deleted_at': asEdit ? null : _t1,
        'deleted_by_peer_id': asEdit ? null : _sender,
        'edited_at': asEdit ? _t1 : null,
        'hidden_at': hiddenAt,
        'wire_envelope': envelope,
        'private_media_policy_version': 1,
        'private_media_mode': mode,
        'private_media_duration_seconds': durationSeconds,
        'private_media_state': state,
        'private_media_received_at_ms': 1000,
        'private_media_clock_high_water_ms': 1000,
      });
      await current
          .insert('direct_reaction_inbox_custody_outbox', <String, Object?>{
            'recipient_peer_id': _recipient,
            'event_id': eventId,
            'wire_envelope': envelope,
            'retry_count': 0,
            'last_attempt_at': null,
            'last_error_code': null,
            'created_at': _t0,
            'updated_at': _t0,
          });
      return (messageId: messageId, eventId: eventId, envelope: envelope);
    }

    Future<DirectMutationInboxCustodyCompletionOutcome> complete(
      ({String messageId, String eventId, String envelope}) staged,
    ) => dbCompleteAcceptedDirectMutationInboxCustodyIfExact(
      current,
      recipientPeerId: _recipient,
      eventId: staged.eventId,
      expectedWireEnvelope: staged.envelope,
      relayExpiresAt: relayExpiresAt,
    );

    Future<Map<String, Object?>> parentOf(String messageId) async =>
        (await current.query(
          'messages',
          where: 'id = ?',
          whereArgs: <Object?>[messageId],
        )).single;

    Future<List<Map<String, Object?>>> eventRows(String eventId) =>
        current.query(
          'direct_reaction_inbox_custody_outbox',
          where: 'event_id = ?',
          whereArgs: <Object?>[eventId],
        );

    // 1. A live P/VO deletion tombstone settles and retires its exact event
    //    while every private lifecycle column survives byte-identically.
    final live = await seedStagedPrivateDeletion('live');
    final beforeLive = await parentOf(live.messageId);
    expect(
      await complete(live),
      DirectMutationInboxCustodyCompletionOutcome.completed,
    );
    final settledLive = await parentOf(live.messageId);
    expect(settledLive['status'], 'inboxed');
    expect(settledLive['transport'], 'inbox');
    expect(settledLive['relay_expires_at'], relayExpiresAt);
    expect(settledLive['custody_checked_at'], isNull);
    expect(settledLive['deleted_at'], beforeLive['deleted_at']);
    expect(settledLive['deleted_by_peer_id'], beforeLive['deleted_by_peer_id']);
    expect(settledLive['hidden_at'], beforeLive['hidden_at']);
    for (final column in const <String>[
      'private_media_policy_version',
      'private_media_mode',
      'private_media_duration_seconds',
      'private_media_state',
      'private_media_received_at_ms',
      'private_media_expires_at_ms',
      'private_media_revealed_at_ms',
      'private_media_terminal_at_ms',
      'private_media_clock_high_water_ms',
    ]) {
      expect(
        settledLive[column],
        beforeLive[column],
        reason: 'completion must never rewrite $column',
      );
    }
    expect(await eventRows(live.eventId), isEmpty);

    // 2. A hidden (locally terminal) P/VO tombstone still completes, and its
    //    hidden claim is never cleared by settlement.
    final hidden = await seedStagedPrivateDeletion('hidden', hiddenAt: _t2);
    expect(
      await complete(hidden),
      DirectMutationInboxCustodyCompletionOutcome.completed,
    );
    final settledHidden = await parentOf(hidden.messageId);
    expect(settledHidden['status'], 'inboxed');
    expect(settledHidden['hidden_at'], _t2);

    // 3. View-Once behaves identically to Protected.
    final viewOnce = await seedStagedPrivateDeletion(
      'view-once',
      mode: 'view_once',
      state: 'consumed',
    );
    expect(
      await complete(viewOnce),
      DirectMutationInboxCustodyCompletionOutcome.completed,
    );
    expect(
      (await parentOf(viewOnce.messageId))['private_media_state'],
      'consumed',
    );

    // 4. A physically removed parent converges: the event alone retires.
    final removed = await seedStagedPrivateDeletion('removed-parent');
    await current.delete(
      'messages',
      where: 'id = ?',
      whereArgs: <Object?>[removed.messageId],
    );
    expect(
      await complete(removed),
      DirectMutationInboxCustodyCompletionOutcome.completed,
    );
    expect(await eventRows(removed.eventId), isEmpty);

    // 5. Private EDIT is never admitted by the widened deletion branch.
    final privateEdit = await seedStagedPrivateDeletion(
      'private-edit',
      asEdit: true,
    );
    final editBefore = await parentOf(privateEdit.messageId);
    expect(
      await complete(privateEdit),
      DirectMutationInboxCustodyCompletionOutcome.stale,
    );
    expect(await parentOf(privateEdit.messageId), editBefore);
    expect(await eventRows(privateEdit.eventId), hasLength(1));

    // 6. A crossed sender-clock disappearing projection is not the Plan 359
    //    owner either; its exact positive lives in TC-359-01b.
    final disappearing = await seedStagedPrivateDeletion(
      'disappearing',
      mode: 'disappearing',
      durationSeconds: 3600,
    );
    final disappearingBefore = await parentOf(disappearing.messageId);
    expect(
      await complete(disappearing),
      DirectMutationInboxCustodyCompletionOutcome.stale,
    );
    expect(await parentOf(disappearing.messageId), disappearingBefore);
    expect(await eventRows(disappearing.eventId), hasLength(1));

    // 7. A crossed envelope is stale and retains the exact event.
    final crossed = await seedStagedPrivateDeletion('crossed');
    expect(
      await dbCompleteAcceptedDirectMutationInboxCustodyIfExact(
        current,
        recipientPeerId: _recipient,
        eventId: crossed.eventId,
        expectedWireEnvelope: crossed.envelope.replaceAll('cipher-', 'forged-'),
        relayExpiresAt: relayExpiresAt,
      ),
      DirectMutationInboxCustodyCompletionOutcome.stale,
    );
    expect(await eventRows(crossed.eventId), hasLength(1));

    // 8. Two parents projecting the same envelope stay ambiguous.
    final ambiguous = await seedStagedPrivateDeletion('ambiguous');
    await current.insert('messages', <String, Object?>{
      'id': '${ambiguous.messageId}-twin',
      'contact_peer_id': _recipient,
      'sender_peer_id': _sender,
      'text': '',
      'timestamp': _t0,
      'status': 'sending',
      'is_incoming': 0,
      'created_at': _t0,
      'deleted_at': _t1,
      'deleted_by_peer_id': _sender,
      'wire_envelope': ambiguous.envelope,
      'private_media_policy_version': 1,
      'private_media_mode': 'protected',
      'private_media_state': 'available',
    });
    expect(
      await complete(ambiguous),
      DirectMutationInboxCustodyCompletionOutcome.ambiguous,
    );
    expect(await eventRows(ambiguous.eventId), hasLength(1));

    // --- Atomic stage: the tombstone and its exact event land together, or
    // every row, attachment and independent obligation stays untouched. ---
    Future<
      ({
        Map<String, Object?> expected,
        Map<String, Object?> tombstone,
        String eventId,
        String envelope,
      })
    >
    seedLivePrivateParent(String suffix, {String mode = 'protected'}) async {
      final messageId = 'tc356-01b-stage-$suffix';
      final eventId = nextEventId();
      final envelope = deletionEnvelope(eventId);
      await current.insert('messages', <String, Object?>{
        'id': messageId,
        'contact_peer_id': _recipient,
        'sender_peer_id': _sender,
        'text': 'private caption',
        'timestamp': _t0,
        'status': 'delivered',
        'is_incoming': 0,
        'created_at': _t0,
        'private_media_policy_version': 1,
        'private_media_mode': mode,
        'private_media_state': 'available',
        'private_media_received_at_ms': 1000,
        'private_media_clock_high_water_ms': 1000,
      });
      await current.insert('media_attachments', <String, Object?>{
        'id': '$messageId-a',
        'message_id': messageId,
        'owner_lane': 'direct',
        'mime': 'image/jpeg',
        'size': 800,
        'media_type': 'image',
        'created_at': _t0,
        'download_status': 'upload_pending',
        'local_path': 'pending_uploads/$messageId/$messageId-a.jpg',
      });
      final expected = (await current.query(
        'messages',
        where: 'id = ?',
        whereArgs: <Object?>[messageId],
      )).single;
      return (
        expected: expected,
        tombstone: <String, Object?>{
          ...expected,
          'text': '',
          'status': 'sending',
          'transport': null,
          'deleted_at': _t1,
          'deleted_by_peer_id': _sender,
          'wire_envelope': envelope,
        },
        eventId: eventId,
        envelope: envelope,
      );
    }

    /// The complete ordered inventory a refusal must leave byte-identical.
    Future<Map<String, List<Map<String, Object?>>>> inventory() async => {
      'messages': await current.query('messages', orderBy: 'id ASC'),
      'v109': await current.query(
        'direct_reaction_inbox_custody_outbox',
        orderBy: 'recipient_peer_id ASC, event_id ASC',
      ),
      'v108': await current.query(
        'direct_inbox_custody_outbox',
        orderBy: 'recipient_peer_id ASC, message_id ASC',
      ),
      'v111': await current.query(
        'direct_media_blob_custody',
        orderBy: 'attachment_id ASC',
      ),
      'attachments': await current.query(
        'media_attachments',
        orderBy: 'id ASC',
      ),
    };

    Future<DbDirectPrivateDeletionCustodyStageResult> stage(
      ({
        Map<String, Object?> expected,
        Map<String, Object?> tombstone,
        String eventId,
        String envelope,
      })
      seed, {
      String? recipientPeerId,
      String? eventId,
      String? wireEnvelope,
      Map<String, Object?>? tombstone,
      int capacity = kDirectReactionInboxCustodyOutboxCapacity,
      Future<void> Function()? beforeCustodyInsertForTest,
    }) => dbStageOutgoingDirectPrivateDeletionInboxCustody(
      current,
      expectedRow: seed.expected,
      tombstoneRow: tombstone ?? seed.tombstone,
      recipientPeerId: recipientPeerId ?? _recipient,
      eventId: eventId ?? seed.eventId,
      wireEnvelope: wireEnvelope ?? seed.envelope,
      capacity: capacity,
      beforeCustodyInsertForTest: beforeCustodyInsertForTest,
    );

    // Applied: one tombstone plus exactly one event, attachment untouched.
    final applied = await seedLivePrivateParent('applied');
    final appliedResult = await stage(applied);
    expect(appliedResult.outcome, OutgoingOrdinaryMutationOutcome.applied);
    expect(appliedResult.authorizesTransport, isTrue);
    expect(appliedResult.messageRow!['deleted_at'], _t1);
    expect(appliedResult.messageRow!['status'], 'sending');
    expect(appliedResult.custodyRow!['event_id'], applied.eventId);
    expect(await eventRows(applied.eventId), hasLength(1));
    expect(
      await current.query(
        'media_attachments',
        where: 'message_id = ?',
        whereArgs: <Object?>['${applied.expected['id']}'],
      ),
      hasLength(1),
      reason: 'the stage authorizes cleanup, it never performs it',
    );

    // Exact replay wins BEFORE capacity.
    final replayed = await stage(applied, capacity: 0);
    expect(replayed.outcome, OutgoingOrdinaryMutationOutcome.idempotent);
    expect(replayed.custodyRow!['event_id'], applied.eventId);

    // A crossed envelope on the same event id refuses.
    final crossedBytes = await stage(
      applied,
      wireEnvelope: applied.envelope.replaceAll('cipher-', 'forged-'),
    );
    expect(crossedBytes.outcome, OutgoingOrdinaryMutationOutcome.refused);

    // Capacity, envelope/identity drift, disappearing duration and a removed
    // parent all refuse with an unchanged inventory.
    Future<void> expectRefusedWithNoEffect(
      String label,
      Future<DbDirectPrivateDeletionCustodyStageResult> Function() action,
    ) async {
      final before = await inventory();
      final result = await action();
      expect(
        result.outcome,
        OutgoingOrdinaryMutationOutcome.refused,
        reason: label,
      );
      expect(result.messageRow, isNull);
      expect(result.custodyRow, isNull);
      expect(await inventory(), before, reason: label);
    }

    final full = await seedLivePrivateParent('capacity');
    await expectRefusedWithNoEffect(
      'a full outbox refuses',
      () => stage(full, capacity: 0),
    );

    final drift = await seedLivePrivateParent('identity-drift');
    await expectRefusedWithNoEffect(
      'a crossed recipient refuses',
      () => stage(drift, recipientPeerId: 'peer-someone-else'),
    );
    await expectRefusedWithNoEffect(
      'an envelope whose event id differs from the key refuses',
      () => stage(drift, eventId: nextEventId()),
    );
    await expectRefusedWithNoEffect(
      'a tombstone that keeps its text refuses',
      () => stage(
        drift,
        tombstone: <String, Object?>{...drift.tombstone, 'text': 'kept'},
      ),
    );
    await expectRefusedWithNoEffect(
      'a crossed deletion author refuses',
      () => stage(
        drift,
        tombstone: <String, Object?>{
          ...drift.tombstone,
          'deleted_by_peer_id': 'peer-impostor',
        },
      ),
    );

    final disappearing2 = await seedLivePrivateParent(
      'disappearing',
      mode: 'disappearing',
    );
    await expectRefusedWithNoEffect(
      'disappearing stays outside this slice',
      () => stage(disappearing2),
    );

    final removed2 = await seedLivePrivateParent('removed-parent');
    await current.delete(
      'messages',
      where: 'id = ?',
      whereArgs: <Object?>[removed2.expected['id']],
    );
    await expectRefusedWithNoEffect(
      'a physically removed parent is authoritative',
      () => stage(removed2),
    );

    // An injected v109 insert failure rolls the parent update back.
    final aborted = await seedLivePrivateParent('insert-abort');
    final beforeAbort = await inventory();
    await expectLater(
      stage(
        aborted,
        beforeCustodyInsertForTest: () async =>
            throw StateError('injected v109 insert failure'),
      ),
      throwsA(isA<StateError>()),
    );
    expect(
      await inventory(),
      beforeAbort,
      reason: 'a failed event insert must roll the tombstone back',
    );
  });

  test('TC-357-01a exact private deletion v109 replay authorizes only the '
      'persisted tombstone', () async {
    final current = await databaseFactoryFfi.openDatabase(
      '${tempDirectory.path}/replay.db',
      options: OpenDatabaseOptions(
        version: currentIdentityDatabaseVersion,
        singleInstance: false,
        onCreate: runProductionOnCreate,
        onUpgrade: runProductionOnUpgrade,
      ),
    );
    addTearDown(current.close);

    var eventSeq = 0;
    String nextEventId() =>
        '35700000-0000-4000-8000-${(++eventSeq).toString().padLeft(12, '0')}';

    String deletionEnvelope(String eventId) => jsonEncode(<String, Object?>{
      'type': 'message_deletion',
      'version': '2',
      'eventId': eventId,
      'senderPeerId': _sender,
      'encrypted': <String, Object?>{
        'kem': 'kem-357',
        'ciphertext': 'cipher-$eventId',
        'nonce': 'nonce-357',
      },
    });

    /// Seeds one live v1 Protected parent plus its pending attachment and
    /// returns the exact rows the private deletion stage is called with.
    Future<
      ({
        String messageId,
        Map<String, Object?> expected,
        Map<String, Object?> tombstone,
        String eventId,
        String envelope,
      })
    >
    seedLiveParent(
      String suffix, {
      String mode = 'protected',
      String? eventId,
      String? envelope,
    }) async {
      final messageId = 'tc357-01a-$suffix';
      final resolvedEventId = eventId ?? nextEventId();
      final resolvedEnvelope = envelope ?? deletionEnvelope(resolvedEventId);
      await current.insert('messages', <String, Object?>{
        'id': messageId,
        'contact_peer_id': _recipient,
        'sender_peer_id': _sender,
        'text': 'private caption',
        'timestamp': _t0,
        'status': 'delivered',
        'is_incoming': 0,
        'created_at': _t0,
        'private_media_policy_version': 1,
        'private_media_mode': mode,
        'private_media_state': 'available',
        'private_media_received_at_ms': 1000,
        'private_media_clock_high_water_ms': 1000,
      });
      await current.insert('media_attachments', <String, Object?>{
        'id': '$messageId-a',
        'message_id': messageId,
        'owner_lane': 'direct',
        'mime': 'image/jpeg',
        'size': 800,
        'media_type': 'image',
        'created_at': _t0,
        'download_status': 'upload_pending',
        'local_path': 'pending_uploads/$messageId/$messageId-a.jpg',
      });
      final expected = (await current.query(
        'messages',
        where: 'id = ?',
        whereArgs: <Object?>[messageId],
      )).single;
      return (
        messageId: messageId,
        expected: expected,
        tombstone: <String, Object?>{
          ...expected,
          'text': '',
          'status': 'sending',
          'transport': null,
          'deleted_at': _t1,
          'deleted_by_peer_id': _sender,
          'wire_envelope': resolvedEnvelope,
        },
        eventId: resolvedEventId,
        envelope: resolvedEnvelope,
      );
    }

    Future<DbDirectPrivateDeletionCustodyStageResult> stage(
      ({
        String messageId,
        Map<String, Object?> expected,
        Map<String, Object?> tombstone,
        String eventId,
        String envelope,
      })
      seed, {
      int capacity = kDirectReactionInboxCustodyOutboxCapacity,
    }) => dbStageOutgoingDirectPrivateDeletionInboxCustody(
      current,
      expectedRow: seed.expected,
      tombstoneRow: seed.tombstone,
      recipientPeerId: _recipient,
      eventId: seed.eventId,
      wireEnvelope: seed.envelope,
      capacity: capacity,
    );

    /// The complete ordered inventory every refusal must leave byte-identical.
    Future<Map<String, List<Map<String, Object?>>>> inventory() async => {
      'messages': await current.query('messages', orderBy: 'id ASC'),
      'v109': await current.query(
        'direct_reaction_inbox_custody_outbox',
        orderBy: 'recipient_peer_id ASC, event_id ASC',
      ),
      'v108': await current.query(
        'direct_inbox_custody_outbox',
        orderBy: 'recipient_peer_id ASC, message_id ASC',
      ),
      'v111': await current.query(
        'direct_media_blob_custody',
        orderBy: 'attachment_id ASC',
      ),
      'attachments': await current.query(
        'media_attachments',
        orderBy: 'id ASC',
      ),
    };

    /// Deposits the exact physical v109 row a prior attempt would have left,
    /// using the same shape every other mutation owner writes.
    Future<void> seedExistingEvent(String eventId, String envelope) => current
        .insert('direct_reaction_inbox_custody_outbox', <String, Object?>{
          'recipient_peer_id': _recipient,
          'event_id': eventId,
          'wire_envelope': envelope,
          'retry_count': 0,
          'last_attempt_at': null,
          'last_error_code': null,
          'created_at': _t0,
          'updated_at': _t0,
        });

    Future<void> expectRefusedWithNoEffect(
      String label,
      Future<DbDirectPrivateDeletionCustodyStageResult> Function() action,
    ) async {
      final before = await inventory();
      final result = await action();
      expect(
        result.outcome,
        OutgoingOrdinaryMutationOutcome.refused,
        reason: label,
      );
      expect(result.messageRow, isNull, reason: label);
      expect(result.custodyRow, isNull, reason: label);
      expect(await inventory(), before, reason: label);
    }

    // 1. The only authorized replay: the persisted parent already IS the exact
    //    supplied tombstone. Exact replay still wins before shared capacity.
    final persisted = await seedLiveParent('persisted');
    expect(
      (await stage(persisted)).outcome,
      OutgoingOrdinaryMutationOutcome.applied,
    );
    final replayed = await stage(persisted, capacity: 0);
    expect(replayed.outcome, OutgoingOrdinaryMutationOutcome.idempotent);
    expect(replayed.custodyRow!['event_id'], persisted.eventId);
    expect(
      replayed.messageRow!['id'],
      persisted.messageId,
      reason: 'replay returns the persisted tombstone, never a foreign parent',
    );
    expect(replayed.messageRow!['deleted_at'], _t1);
    expect(replayed.messageRow!['status'], 'sending');
    expect(replayed.messageRow!['wire_envelope'], persisted.envelope);

    // 2. A LIVE parent whose event already sits in v109 may not authorize
    //    transport: no durable tombstone exists for it yet.
    final live = await seedLiveParent('live-parent');
    await seedExistingEvent(live.eventId, live.envelope);
    await expectRefusedWithNoEffect(
      'a live parent can never be authorized by a pre-existing event',
      () => stage(live),
    );

    // 3. The deletion envelope carries no target binding, so the same event
    //    presented for a DIFFERENT live message must refuse.
    final crossed = await seedLiveParent(
      'crossed-target',
      eventId: persisted.eventId,
      envelope: persisted.envelope,
    );
    await expectRefusedWithNoEffect(
      'a crossed message id cannot inherit another parent\'s event',
      () => stage(crossed),
    );

    // 4. Two outgoing rows projecting one envelope are ambiguous.
    final ambiguous = await seedLiveParent('ambiguous');
    expect(
      (await stage(ambiguous)).outcome,
      OutgoingOrdinaryMutationOutcome.applied,
    );
    await current.insert('messages', <String, Object?>{
      ...ambiguous.tombstone,
      'id': '${ambiguous.messageId}-twin',
    });
    await expectRefusedWithNoEffect(
      'two parents projecting one envelope cannot be disambiguated',
      () => stage(ambiguous, capacity: 0),
    );

    // 5. A physically removed parent is authoritative: replay never recreates
    //    it, and the pre-existing event stays drainable.
    final removed = await seedLiveParent('removed-parent');
    expect(
      (await stage(removed)).outcome,
      OutgoingOrdinaryMutationOutcome.applied,
    );
    await current.delete(
      'messages',
      where: 'id = ?',
      whereArgs: <Object?>[removed.messageId],
    );
    await expectRefusedWithNoEffect(
      'an absent parent cannot be resurrected by replay',
      () => stage(removed),
    );
    expect(
      await current.query(
        'direct_reaction_inbox_custody_outbox',
        where: 'event_id = ?',
        whereArgs: <Object?>[removed.eventId],
      ),
      hasLength(1),
      reason: 'the pre-existing event remains its own drain obligation',
    );

    // 6. Immutable-projection drift on the persisted row refuses.
    Future<void> expectDriftRefuses(
      String suffix,
      Map<String, Object?> drift,
    ) async {
      final seed = await seedLiveParent(suffix);
      expect(
        (await stage(seed)).outcome,
        OutgoingOrdinaryMutationOutcome.applied,
      );
      await current.update(
        'messages',
        drift,
        where: 'id = ?',
        whereArgs: <Object?>[seed.messageId],
      );
      await expectRefusedWithNoEffect(
        'persisted drift ${drift.keys.join(',')} refuses',
        () => stage(seed, capacity: 0),
      );
    }

    await expectDriftRefuses('drift-timestamp', <String, Object?>{
      'timestamp': _t2,
    });
    await expectDriftRefuses('drift-status', <String, Object?>{
      'status': 'failed',
    });
    await expectDriftRefuses('drift-transport', <String, Object?>{
      'transport': 'inbox',
      'relay_expires_at': 1900000060000,
    });
    await expectDriftRefuses('drift-duration', <String, Object?>{
      'private_media_duration_seconds': 3600,
    });
    await expectDriftRefuses('drift-author', <String, Object?>{
      'deleted_by_peer_id': 'peer-impostor',
    });
    await expectDriftRefuses('drift-caption', <String, Object?>{
      'text': 'restored caption',
    });

    // 7. Only local read/hide and the incumbent private lifecycle clocks may
    //    drift under an otherwise exact replay.
    final tolerated = await seedLiveParent('tolerated-drift');
    expect(
      (await stage(tolerated)).outcome,
      OutgoingOrdinaryMutationOutcome.applied,
    );
    await current.update(
      'messages',
      <String, Object?>{
        'read_at': _t2,
        'hidden_at': _t2,
        'private_media_state': 'consumed',
        'private_media_terminal_at_ms': 1900000000000,
        'private_media_clock_high_water_ms': 2000,
      },
      where: 'id = ?',
      whereArgs: <Object?>[tolerated.messageId],
    );
    final toleratedReplay = await stage(tolerated, capacity: 0);
    expect(
      toleratedReplay.outcome,
      OutgoingOrdinaryMutationOutcome.idempotent,
      reason: 'local hide and lifecycle clocks are not deletion identity',
    );
    expect(toleratedReplay.messageRow!['hidden_at'], _t2);
  });

  test('TC-359-01b disappearing deletion completion is exact and private EDIT '
      'remains refused', () async {
    const relayExpiresAt = 1900000060000;
    final current = await databaseFactoryFfi.openDatabase(
      '${tempDirectory.path}/tc359-01b.db',
      options: OpenDatabaseOptions(
        version: currentIdentityDatabaseVersion,
        singleInstance: false,
        onCreate: runProductionOnCreate,
        onUpgrade: runProductionOnUpgrade,
      ),
    );
    addTearDown(current.close);

    var eventSeq = 0;
    String nextEventId() =>
        '35900000-0000-4000-8000-${(++eventSeq).toString().padLeft(12, '0')}';

    String deletionEnvelope(String eventId) => jsonEncode(<String, Object?>{
      'type': 'message_deletion',
      'version': '2',
      'eventId': eventId,
      'senderPeerId': _sender,
      'encrypted': <String, Object?>{
        'kem': 'kem-359',
        'ciphertext': 'cipher-$eventId',
        'nonce': 'nonce-359',
      },
    });

    String editEnvelope(String messageId, String eventId) =>
        jsonEncode(<String, Object?>{
          'type': 'chat_message',
          'version': '2',
          'id': messageId,
          'eventId': eventId,
          'senderPeerId': _sender,
          'encrypted': <String, Object?>{
            'kem': 'kem-359',
            'ciphertext': 'cipher-$eventId',
            'nonce': 'nonce-359',
          },
        });

    /// Seeds one already-staged direct mutation: the parent projects the exact
    /// event envelope and the raw event is retained in the shared v109 outbox.
    Future<({String messageId, String eventId, String envelope})> seedStaged(
      String suffix, {
      String mode = 'disappearing',
      int policyVersion = 1,
      int? durationSeconds = 3600,
      String state = 'available',
      String status = 'sending',
      bool asEdit = false,
      Object? receivedAtMs,
      Object? terminalAtMs,
      Object? clockHighWaterMs,
      Object? deletedByPeerId = _sender,
      Object? hiddenAt,
    }) async {
      final messageId = 'tc359-01b-$suffix';
      final eventId = nextEventId();
      final envelope = asEdit
          ? editEnvelope(messageId, eventId)
          : deletionEnvelope(eventId);
      await current.insert('messages', <String, Object?>{
        'id': messageId,
        'contact_peer_id': _recipient,
        'sender_peer_id': _sender,
        'text': asEdit ? 'edited private caption' : '',
        'timestamp': _t0,
        'status': status,
        'is_incoming': 0,
        'created_at': _t0,
        'deleted_at': asEdit ? null : _t1,
        'deleted_by_peer_id': asEdit ? null : deletedByPeerId,
        'edited_at': asEdit ? _t1 : null,
        'hidden_at': hiddenAt,
        'wire_envelope': envelope,
        'private_media_policy_version': policyVersion,
        'private_media_mode': mode,
        'private_media_duration_seconds': durationSeconds,
        'private_media_state': state,
        'private_media_received_at_ms': receivedAtMs,
        'private_media_terminal_at_ms': terminalAtMs,
        'private_media_clock_high_water_ms': clockHighWaterMs,
      });
      await current
          .insert('direct_reaction_inbox_custody_outbox', <String, Object?>{
            'recipient_peer_id': _recipient,
            'event_id': eventId,
            'wire_envelope': envelope,
            'retry_count': 0,
            'last_attempt_at': null,
            'last_error_code': null,
            'created_at': _t0,
            'updated_at': _t0,
          });
      return (messageId: messageId, eventId: eventId, envelope: envelope);
    }

    Future<DirectMutationInboxCustodyCompletionOutcome> complete(
      ({String messageId, String eventId, String envelope}) staged,
    ) => dbCompleteAcceptedDirectMutationInboxCustodyIfExact(
      current,
      recipientPeerId: _recipient,
      eventId: staged.eventId,
      expectedWireEnvelope: staged.envelope,
      relayExpiresAt: relayExpiresAt,
    );

    Future<Map<String, Object?>?> parentOf(String messageId) async {
      final rows = await current.query(
        'messages',
        where: 'id = ?',
        whereArgs: <Object?>[messageId],
      );
      return rows.isEmpty ? null : rows.single;
    }

    Future<List<Map<String, Object?>>> eventRows(String eventId) =>
        current.query(
          'direct_reaction_inbox_custody_outbox',
          where: 'event_id = ?',
          whereArgs: <Object?>[eventId],
        );

    const lifecycleColumns = <String>[
      'private_media_policy_version',
      'private_media_mode',
      'private_media_duration_seconds',
      'private_media_state',
      'private_media_received_at_ms',
      'private_media_expires_at_ms',
      'private_media_revealed_at_ms',
      'private_media_terminal_at_ms',
      'private_media_clock_high_water_ms',
    ];

    // 1. Every allowed duration and every admitted settlement status settles
    //    while each disappearing lifecycle column survives byte-identically.
    for (final positive in <({int duration, String status})>[
      (duration: 3600, status: 'sending'),
      (duration: 86400, status: 'failed'),
      (duration: 604800, status: 'sent'),
    ]) {
      final staged = await seedStaged(
        'ok-${positive.duration}',
        durationSeconds: positive.duration,
        status: positive.status,
      );
      final before = (await parentOf(staged.messageId))!;
      expect(
        await complete(staged),
        DirectMutationInboxCustodyCompletionOutcome.completed,
        reason: 'duration ${positive.duration}',
      );
      final settled = (await parentOf(staged.messageId))!;
      expect(settled['status'], 'inboxed');
      expect(settled['transport'], 'inbox');
      expect(settled['relay_expires_at'], relayExpiresAt);
      expect(settled['custody_checked_at'], isNull);
      expect(settled['deleted_at'], before['deleted_at']);
      expect(settled['deleted_by_peer_id'], before['deleted_by_peer_id']);
      for (final column in lifecycleColumns) {
        expect(
          settled[column],
          before[column],
          reason: 'completion must never rewrite $column',
        );
      }
      expect(await eventRows(staged.eventId), isEmpty);
    }

    // 2. A locally hidden disappearing tombstone still settles; the hide is an
    //    independent terminal claim, never a settlement conflict.
    final hidden = await seedStaged('hidden', hiddenAt: _t2);
    expect(
      await complete(hidden),
      DirectMutationInboxCustodyCompletionOutcome.completed,
    );
    expect((await parentOf(hidden.messageId))!['hidden_at'], _t2);

    // 3. Completion stays attachment/parent-independent after cleanup or a
    //    contact deletion physically removed the row.
    final removed = await seedStaged('removed-parent');
    await current.delete(
      'messages',
      where: 'id = ?',
      whereArgs: <Object?>[removed.messageId],
    );
    expect(
      await complete(removed),
      DirectMutationInboxCustodyCompletionOutcome.completed,
    );
    expect(await eventRows(removed.eventId), isEmpty);

    // 4. Every crossed or malformed disappearing projection stays stale, and
    //    private EDIT is never admitted by the widened deletion branch.
    Future<void> expectStale(
      String label,
      ({String messageId, String eventId, String envelope}) staged,
    ) async {
      final before = await parentOf(staged.messageId);
      expect(
        await complete(staged),
        DirectMutationInboxCustodyCompletionOutcome.stale,
        reason: label,
      );
      expect(await parentOf(staged.messageId), before, reason: label);
      expect(await eventRows(staged.eventId), hasLength(1), reason: label);
    }

    await expectStale(
      'a sender-side receiver clock is never this owner',
      await seedStaged('sender-clock', receivedAtMs: 1000),
    );
    await expectStale(
      'a high-water clock on the sender is crossed state',
      await seedStaged('high-water', clockHighWaterMs: 2000),
    );
    await expectStale(
      'a terminal disappearing state refuses',
      await seedStaged('terminal-state', state: 'expired'),
    );
    await expectStale(
      'a missing duration refuses',
      await seedStaged('missing-duration', durationSeconds: null),
    );
    await expectStale(
      'a crossed deletion author refuses',
      await seedStaged('crossed-author', deletedByPeerId: 'peer-impostor'),
    );
    await expectStale(
      'a disappearing EDIT never gains v109 completion',
      await seedStaged('disappearing-edit', asEdit: true),
    );
    await expectStale(
      'a protected EDIT never gains v109 completion',
      await seedStaged(
        'protected-edit',
        mode: 'protected',
        durationSeconds: null,
        asEdit: true,
      ),
    );
    await expectStale(
      'a delivered disappearing tombstone is stronger than inbox custody',
      await seedStaged('delivered-status', status: 'delivered'),
    );

    // 5. The exact Protected control still completes unchanged.
    final protectedControl = await seedStaged(
      'protected-control',
      mode: 'protected',
      durationSeconds: null,
      receivedAtMs: 1000,
      clockHighWaterMs: 1000,
    );
    expect(
      await complete(protectedControl),
      DirectMutationInboxCustodyCompletionOutcome.completed,
    );
    expect(
      (await parentOf(protectedControl.messageId))!['private_media_mode'],
      'protected',
    );
  });
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
