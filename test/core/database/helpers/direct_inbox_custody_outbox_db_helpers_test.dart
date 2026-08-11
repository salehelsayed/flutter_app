import 'dart:io';

import 'package:flutter_app/core/database/app_database_version.dart';
import 'package:flutter_app/core/database/direct_media_blob_custody.dart';
import 'package:flutter_app/core/database/helpers/direct_inbox_custody_outbox_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/direct_media_blob_custody_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/media_attachments_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/messages_db_helpers.dart';
import 'package:flutter_app/core/database/outgoing_transport_mutation.dart';
import 'package:flutter_app/core/database/production_migration_registry.dart';
import 'package:flutter_app/core/media/direct_media_blob_custody.dart';
import 'package:flutter_app/core/media/private_media_policy.dart';
import 'package:flutter_app/core/secure_storage/secret_storage_references.dart';
import 'package:flutter_app/core/services/inbox_store_outcome.dart';
import 'package:flutter_app/features/conversation/application/drain_direct_inbox_custody_outbox_use_case.dart';
import 'package:flutter_app/features/conversation/data/repositories/message_repository_impl.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/direct_inbox_custody_outbox_entry.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _peer = 'peer-recipient';
const _t0 = '2026-08-06T10:00:00.000Z';
const _t1 = '2026-08-06T10:00:01.000Z';
const _incarnationA = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _incarnationB = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const _incarnationC = 'cccccccccccccccccccccccccccccccc';
const _incarnationD = 'dddddddddddddddddddddddddddddddd';
const _incarnationE = 'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee';
const _incarnationF = 'ffffffffffffffffffffffffffffffff';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tempDirectory;
  late Database db;
  late MessageRepositoryImpl repository;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp(
      'direct_inbox_custody_helper_',
    );
    db = await databaseFactoryFfi.openDatabase(
      '${tempDirectory.path}/identity.db',
      options: OpenDatabaseOptions(
        version: currentIdentityDatabaseVersion,
        singleInstance: false,
        onCreate: runProductionOnCreate,
        onUpgrade: runProductionOnUpgrade,
      ),
    );
    repository = _buildRepository(db, capacity: 2);
  });

  tearDown(() async {
    if (db.isOpen) await db.close();
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  test('runtime custody capability requires the complete six-callback set', () {
    expect(repository.supportsDirectTextInboxCustody, isTrue);
    for (final omitted in <String>{
      'stage',
      'loadBatch',
      'loadMessage',
      'loadOwner',
      'recordFailure',
      'complete',
    }) {
      final partial = _buildRepository(
        db,
        capacity: 2,
        omitCustodyDelegate: omitted,
      );
      expect(
        partial.supportsDirectTextInboxCustody,
        isFalse,
        reason: 'must fail closed when $omitted is absent',
      );
    }
  });

  test(
    'message-id owner lookup returns stored recipient after parent drift and rejects ambiguity',
    () async {
      final message = _message(
        'global-owner-lookup',
        envelope: _envelope('global-owner-lookup', 'cipher-owner'),
      );
      final staged = await repository.stageOutgoingDirectTextInboxCustody(
        expected: null,
        staged: message,
        kind: OutgoingOrdinaryAttemptKind.fresh,
        recipientPeerId: _peer,
        incarnationId: _incarnationA,
        wireEnvelope: message.wireEnvelope!,
      );
      expect(staged.authorizesTransport, isTrue);
      await db.update(
        'messages',
        const <String, Object?>{'contact_peer_id': 'peer-drifted'},
        where: 'id = ?',
        whereArgs: <Object?>[message.id],
      );

      final owner = await repository.loadDirectInboxCustodyOwnerForMessageId(
        messageId: message.id,
      );
      expect(owner?.recipientPeerId, _peer);
      expect(owner?.messageId, message.id);
      expect(
        await repository.loadDirectInboxCustodyForMessage(
          recipientPeerId: 'peer-drifted',
          messageId: message.id,
        ),
        isNull,
      );

      await db.insert('direct_inbox_custody_outbox', <String, Object?>{
        'recipient_peer_id': 'peer-other-owner',
        'message_id': message.id,
        'incarnation_id': _incarnationB,
        'wire_envelope': _envelope(message.id, 'cipher-other-owner'),
        'retry_count': 0,
        'last_attempt_at': null,
        'last_error_code': null,
        'created_at': _t1,
        'updated_at': _t1,
      });
      await expectLater(
        repository.loadDirectInboxCustodyOwnerForMessageId(
          messageId: message.id,
        ),
        throwsA(isA<StateError>()),
      );
    },
  );

  test(
    'TC-345-09b fresh text stage cannot create a sibling global message-id owner',
    () async {
      const messageId = 'global-message-id-stage-exclusion';
      const secondPeer = 'peer-second-recipient';
      final first = _message(
        messageId,
        envelope: _envelope(messageId, 'cipher-first-owner'),
      );
      final firstStage = await repository.stageOutgoingDirectTextInboxCustody(
        expected: null,
        staged: first,
        kind: OutgoingOrdinaryAttemptKind.fresh,
        recipientPeerId: _peer,
        incarnationId: _incarnationA,
        wireEnvelope: first.wireEnvelope!,
      );
      expect(firstStage.authorizesTransport, isTrue);
      await db.delete(
        'messages',
        where: 'id = ?',
        whereArgs: <Object?>[messageId],
      );

      final second = _message(
        messageId,
        envelope: _envelope(messageId, 'cipher-second-owner'),
        createdAt: _t1,
      ).copyWith(contactPeerId: secondPeer);
      final secondStage = await repository.stageOutgoingDirectTextInboxCustody(
        expected: null,
        staged: second,
        kind: OutgoingOrdinaryAttemptKind.fresh,
        recipientPeerId: secondPeer,
        incarnationId: _incarnationB,
        wireEnvelope: second.wireEnvelope!,
      );

      expect(secondStage.outcome, OutgoingOrdinaryMutationOutcome.refused);
      expect(secondStage.authorizesTransport, isFalse);
      expect(
        await db.query(
          'messages',
          where: 'id = ?',
          whereArgs: <Object?>[messageId],
        ),
        isEmpty,
      );
      final owners = await db.query(
        'direct_inbox_custody_outbox',
        where: 'message_id = ?',
        whereArgs: <Object?>[messageId],
      );
      expect(owners, hasLength(1));
      expect(owners.single['recipient_peer_id'], _peer);
      expect(owners.single['incarnation_id'], _incarnationA);
      expect(owners.single['wire_envelope'], first.wireEnvelope);
    },
  );

  test(
    'TC-342-02 atomic immutable direct-text custody mutations fail closed; TC-345-02g completion-before-stale-save stays terminal',
    () async {
      final first = _message(
        'generated-message',
        envelope: _envelope('generated-message', 'cipher-a'),
      );
      final firstStage = await repository.stageOutgoingDirectTextInboxCustody(
        expected: null,
        staged: first,
        kind: OutgoingOrdinaryAttemptKind.fresh,
        recipientPeerId: _peer,
        incarnationId: _incarnationA,
        wireEnvelope: first.wireEnvelope!,
      );
      expect(firstStage.outcome, OutgoingOrdinaryMutationOutcome.applied);
      expect(firstStage.authorizesTransport, isTrue);
      expect(await db.query('messages'), hasLength(1));
      expect(await db.query('direct_inbox_custody_outbox'), hasLength(1));
      expect(
        (await db.query('direct_inbox_custody_outbox')).single,
        containsPair('wire_envelope', first.wireEnvelope),
      );

      final exactReplay = await repository.stageOutgoingDirectTextInboxCustody(
        expected: null,
        staged: first,
        kind: OutgoingOrdinaryAttemptKind.fresh,
        recipientPeerId: _peer,
        incarnationId: _incarnationA,
        wireEnvelope: first.wireEnvelope!,
      );
      expect(exactReplay.outcome, OutgoingOrdinaryMutationOutcome.idempotent);
      expect(exactReplay.authorizesTransport, isTrue);
      expect(await db.query('messages'), hasLength(1));
      expect(await db.query('direct_inbox_custody_outbox'), hasLength(1));

      final changed = first.copyWith(
        wireEnvelope: _envelope(first.id, 'different-ciphertext'),
      );
      final conflict = await repository.stageOutgoingDirectTextInboxCustody(
        expected: null,
        staged: changed,
        kind: OutgoingOrdinaryAttemptKind.fresh,
        recipientPeerId: _peer,
        incarnationId: _incarnationB,
        wireEnvelope: changed.wireEnvelope!,
      );
      expect(conflict.outcome, OutgoingOrdinaryMutationOutcome.refused);
      expect(
        (await db.query('messages')).single['wire_envelope'],
        first.wireEnvelope,
      );
      expect(
        (await db.query('direct_inbox_custody_outbox')).single,
        containsPair('incarnation_id', _incarnationA),
      );

      final preassigned = _message(
        'caller-preassigned-fresh',
        envelope: _envelope('caller-preassigned-fresh', 'cipher-b'),
        createdAt: _t1,
      );
      final preassignedStage = await repository
          .stageOutgoingDirectTextInboxCustody(
            expected: null,
            staged: preassigned,
            kind: OutgoingOrdinaryAttemptKind.fresh,
            recipientPeerId: _peer,
            incarnationId: _incarnationB,
            wireEnvelope: preassigned.wireEnvelope!,
          );
      expect(preassignedStage.authorizesTransport, isTrue);
      expect(await db.query('messages'), hasLength(2));
      expect(await db.query('direct_inbox_custody_outbox'), hasLength(2));

      final firstEntry = (await repository.loadDirectInboxCustodyForMessage(
        recipientPeerId: _peer,
        messageId: first.id,
      ))!;
      expect(
        await repository.recordDirectInboxCustodyFailureIfExact(
          expected: firstEntry.copyWith(incarnationId: _incarnationF),
          errorCode: DirectInboxCustodyErrorCode.storeFailed,
        ),
        isFalse,
      );
      expect(
        await repository.recordDirectInboxCustodyFailureIfExact(
          expected: firstEntry,
          errorCode: DirectInboxCustodyErrorCode.storeFailed,
        ),
        isTrue,
      );
      final fair = await repository.loadDirectInboxCustody(limit: 500);
      expect(fair, hasLength(2));
      expect(
        fair.map((entry) => entry.messageId).toList(),
        <String>[preassigned.id, first.id],
        reason: 'never-attempted work must lead a retained poison row',
      );
      expect(fair.last.retryCount, 1);
      expect(fair.last.lastErrorCode, DirectInboxCustodyErrorCode.storeFailed);

      final overCapacity = _message(
        'over-capacity',
        envelope: _envelope('over-capacity', 'cipher-c'),
      );
      final refusedAtCapacity = await repository
          .stageOutgoingDirectTextInboxCustody(
            expected: null,
            staged: overCapacity,
            kind: OutgoingOrdinaryAttemptKind.fresh,
            recipientPeerId: _peer,
            incarnationId: _incarnationC,
            wireEnvelope: overCapacity.wireEnvelope!,
          );
      expect(
        refusedAtCapacity.outcome,
        OutgoingOrdinaryMutationOutcome.refused,
      );
      expect(
        await db.query(
          'messages',
          where: 'id = ?',
          whereArgs: <Object?>[overCapacity.id],
        ),
        isEmpty,
      );
      expect(await db.query('direct_inbox_custody_outbox'), hasLength(2));

      await db.update(
        'messages',
        <String, Object?>{
          'status': 'delivered',
          'transport': 'direct',
          'wire_envelope': null,
          'relay_expires_at': null,
        },
        where: 'id = ?',
        whereArgs: <Object?>[first.id],
      );
      final deliveredCompletion = await repository
          .completeAcceptedDirectInboxCustodyIfExact(
            expected: fair.last,
            relayExpiresAt: 9000,
          );
      expect(
        deliveredCompletion.outcome,
        DirectInboxCustodyCompletionOutcome.messagePreserved,
      );
      expect(deliveredCompletion.message?.status, 'delivered');
      expect(deliveredCompletion.message?.relayExpiresAt, isNull);
      expect(
        await repository.loadDirectInboxCustodyForMessage(
          recipientPeerId: _peer,
          messageId: first.id,
        ),
        isNull,
      );

      final preassignedEntry = (await repository
          .loadDirectInboxCustodyForMessage(
            recipientPeerId: _peer,
            messageId: preassigned.id,
          ))!;
      final staleCompletion = await repository
          .completeAcceptedDirectInboxCustodyIfExact(
            expected: preassignedEntry.copyWith(incarnationId: _incarnationF),
            relayExpiresAt: 9100,
          );
      expect(staleCompletion.completed, isFalse);
      expect(
        await repository.loadDirectInboxCustodyForMessage(
          recipientPeerId: _peer,
          messageId: preassigned.id,
        ),
        isNotNull,
      );
      final inboxedCompletion = await repository
          .completeAcceptedDirectInboxCustodyIfExact(
            expected: preassignedEntry,
            relayExpiresAt: 9100,
          );
      expect(
        inboxedCompletion.outcome,
        DirectInboxCustodyCompletionOutcome.messageAdvanced,
      );
      expect(inboxedCompletion.message?.status, 'inboxed');
      expect(inboxedCompletion.message?.transport, 'inbox');
      expect(inboxedCompletion.message?.relayExpiresAt, 9100);
      await repository.saveMessage(
        preassigned.copyWith(
          status: 'failed',
          wireEnvelope: _envelope(preassigned.id, 'stale-after-completion'),
        ),
      );
      expect(
        (await db.query(
          'messages',
          where: 'id = ?',
          whereArgs: <Object?>[preassigned.id],
        )).single,
        allOf(
          containsPair('status', 'inboxed'),
          containsPair('transport', 'inbox'),
          containsPair('wire_envelope', preassigned.wireEnvelope),
          containsPair('relay_expires_at', 9100),
        ),
        reason: 'completion must stay monotonic after the v108 row is retired',
      );

      final crossedEdit = _message(
        'crossed-edit-completion',
        envelope: _envelope('crossed-edit-completion', 'cipher-initial'),
      );
      await repository.stageOutgoingDirectTextInboxCustody(
        expected: null,
        staged: crossedEdit,
        kind: OutgoingOrdinaryAttemptKind.fresh,
        recipientPeerId: _peer,
        incarnationId: _incarnationC,
        wireEnvelope: crossedEdit.wireEnvelope!,
      );
      final crossedEditEntry = (await repository
          .loadDirectInboxCustodyForMessage(
            recipientPeerId: _peer,
            messageId: crossedEdit.id,
          ))!;
      final laterEditEnvelope =
          '{"type":"chat_message","version":"2",'
          '"id":"${crossedEdit.id}","eventId":"crossed-edit-event",'
          '"senderPeerId":"peer-self",'
          '"encrypted":{"kem":"kem","ciphertext":"cipher-later-edit",'
          '"nonce":"nonce"}}';
      await db.update(
        'messages',
        <String, Object?>{
          'text': 'later failed edit',
          'status': 'failed',
          'wire_envelope': laterEditEnvelope,
          'edited_at': _t1,
        },
        where: 'id = ?',
        whereArgs: <Object?>[crossedEdit.id],
      );
      final crossedEditCompletion = await repository
          .completeAcceptedDirectInboxCustodyIfExact(
            expected: crossedEditEntry,
            relayExpiresAt: 9150,
          );
      expect(
        crossedEditCompletion.outcome,
        DirectInboxCustodyCompletionOutcome.messagePreserved,
      );
      expect(
        (await db.query(
          'messages',
          where: 'id = ?',
          whereArgs: <Object?>[crossedEdit.id],
        )).single,
        allOf(
          containsPair('text', 'later failed edit'),
          containsPair('status', 'failed'),
          containsPair('wire_envelope', laterEditEnvelope),
          containsPair('relay_expires_at', null),
        ),
      );
      expect(
        await repository.loadDirectInboxCustodyForMessage(
          recipientPeerId: _peer,
          messageId: crossedEdit.id,
        ),
        isNull,
        reason:
            'accepted initial custody retires without projecting a later edit',
      );
      final crossedEditBeforeStaleSave = (await db.query(
        'messages',
        where: 'id = ?',
        whereArgs: <Object?>[crossedEdit.id],
      )).single;
      await repository.saveMessage(crossedEdit);
      expect(
        (await db.query(
          'messages',
          where: 'id = ?',
          whereArgs: <Object?>[crossedEdit.id],
        )).single,
        crossedEditBeforeStaleSave,
        reason:
            'a delayed initial save cannot overwrite the strict edit after v108 retirement',
      );

      const newestEditAt = '2026-08-06T10:00:02.000Z';
      final newestEditEnvelope =
          '{"type":"chat_message","version":"2",'
          '"id":"${crossedEdit.id}","eventId":"crossed-edit-event-2",'
          '"senderPeerId":"peer-self",'
          '"encrypted":{"kem":"kem","ciphertext":"cipher-newest-edit",'
          '"nonce":"nonce"}}';
      await repository.saveMessage(
        crossedEdit.copyWith(
          text: 'newest edit',
          status: 'sending',
          wireEnvelope: newestEditEnvelope,
          editedAt: newestEditAt,
        ),
      );
      expect(
        (await db.query(
          'messages',
          where: 'id = ?',
          whereArgs: <Object?>[crossedEdit.id],
        )).single,
        allOf(
          containsPair('text', 'newest edit'),
          containsPair('edited_at', newestEditAt),
          containsPair('status', 'sending'),
          containsPair('wire_envelope', newestEditEnvelope),
        ),
        reason: 'a demonstrably newer strict Plan342 edit remains writable',
      );

      final removed = _message(
        'removed-before-completion',
        envelope: _envelope('removed-before-completion', 'cipher-d'),
      );
      await repository.stageOutgoingDirectTextInboxCustody(
        expected: null,
        staged: removed,
        kind: OutgoingOrdinaryAttemptKind.fresh,
        recipientPeerId: _peer,
        incarnationId: _incarnationD,
        wireEnvelope: removed.wireEnvelope!,
      );
      final removedEntry = (await repository.loadDirectInboxCustodyForMessage(
        recipientPeerId: _peer,
        messageId: removed.id,
      ))!;
      await db.delete(
        'messages',
        where: 'id = ?',
        whereArgs: <Object?>[removed.id],
      );
      final removedCompletion = await repository
          .completeAcceptedDirectInboxCustodyIfExact(
            expected: removedEntry,
            relayExpiresAt: null,
          );
      expect(
        removedCompletion.outcome,
        DirectInboxCustodyCompletionOutcome.messageRemoved,
      );
      expect(removedCompletion.message, isNull);
      final removedTombstone = (await db.query(
        'messages',
        where: 'id = ?',
        whereArgs: <Object?>[removed.id],
      )).single;
      expect(
        removedTombstone,
        allOf(
          containsPair('contact_peer_id', _peer),
          containsPair('sender_peer_id', 'peer-self'),
          containsPair('text', ''),
          containsPair('wire_envelope', null),
          containsPair('status', 'inboxed'),
          containsPair('transport', 'inbox'),
          containsPair('hidden_at', _t0),
        ),
      );
      expect(
        await db.query(
          'direct_inbox_custody_outbox',
          where: 'message_id = ?',
          whereArgs: <Object?>[removed.id],
        ),
        isEmpty,
      );
      await repository.saveMessage(
        removed.copyWith(
          status: 'failed',
          wireEnvelope: _envelope(removed.id, 'stale-after-removal'),
        ),
      );
      expect(
        (await db.query(
          'messages',
          where: 'id = ?',
          whereArgs: <Object?>[removed.id],
        )).single,
        removedTombstone,
        reason:
            'messageRemoved completion must retain deletion authority after v108 retirement',
      );

      await db.execute('''
        CREATE TRIGGER inject_custody_insert_failure
        BEFORE INSERT ON direct_inbox_custody_outbox
        WHEN NEW.message_id = 'sql-failure'
        BEGIN
          SELECT RAISE(ABORT, 'injected custody insert failure');
        END
      ''');
      final sqlFailure = _message(
        'sql-failure',
        envelope: _envelope('sql-failure', 'cipher-e'),
      );
      await expectLater(
        repository.stageOutgoingDirectTextInboxCustody(
          expected: null,
          staged: sqlFailure,
          kind: OutgoingOrdinaryAttemptKind.fresh,
          recipientPeerId: _peer,
          incarnationId: _incarnationE,
          wireEnvelope: sqlFailure.wireEnvelope!,
        ),
        throwsA(isA<DatabaseException>()),
      );
      expect(
        await db.query(
          'messages',
          where: 'id = ?',
          whereArgs: <Object?>[sqlFailure.id],
        ),
        isEmpty,
        reason: 'the companion insert failure must roll back the message',
      );
      await db.execute('DROP TRIGGER inject_custody_insert_failure');

      final rollback = _message(
        'rollback-completion',
        envelope: _envelope('rollback-completion', 'cipher-f'),
      );
      await repository.stageOutgoingDirectTextInboxCustody(
        expected: null,
        staged: rollback,
        kind: OutgoingOrdinaryAttemptKind.fresh,
        recipientPeerId: _peer,
        incarnationId: _incarnationF,
        wireEnvelope: rollback.wireEnvelope!,
      );
      final rollbackEntry = (await repository.loadDirectInboxCustodyForMessage(
        recipientPeerId: _peer,
        messageId: rollback.id,
      ))!;
      await db.execute('''
        CREATE TRIGGER inject_custody_completion_failure
        BEFORE DELETE ON direct_inbox_custody_outbox
        WHEN OLD.message_id = 'rollback-completion'
        BEGIN
          SELECT RAISE(ABORT, 'injected custody completion failure');
        END
      ''');
      await expectLater(
        repository.completeAcceptedDirectInboxCustodyIfExact(
          expected: rollbackEntry,
          relayExpiresAt: 9200,
        ),
        throwsA(isA<DatabaseException>()),
      );
      expect(
        (await db.query(
          'messages',
          where: 'id = ?',
          whereArgs: <Object?>[rollback.id],
        )).single['status'],
        'sending',
      );
      expect(
        await db.query(
          'direct_inbox_custody_outbox',
          where: 'message_id = ?',
          whereArgs: <Object?>[rollback.id],
        ),
        hasLength(1),
      );

      final removedRollback = _message(
        'removed-rollback-completion',
        envelope: _envelope(
          'removed-rollback-completion',
          'cipher-removed-rollback',
        ),
      );
      await repository.stageOutgoingDirectTextInboxCustody(
        expected: null,
        staged: removedRollback,
        kind: OutgoingOrdinaryAttemptKind.fresh,
        recipientPeerId: _peer,
        incarnationId: _incarnationE,
        wireEnvelope: removedRollback.wireEnvelope!,
      );
      final removedRollbackEntry = (await repository
          .loadDirectInboxCustodyForMessage(
            recipientPeerId: _peer,
            messageId: removedRollback.id,
          ))!;
      await db.delete(
        'messages',
        where: 'id = ?',
        whereArgs: <Object?>[removedRollback.id],
      );
      await db.execute('''
        CREATE TRIGGER inject_removed_custody_completion_failure
        BEFORE DELETE ON direct_inbox_custody_outbox
        WHEN OLD.message_id = 'removed-rollback-completion'
        BEGIN
          SELECT RAISE(ABORT, 'injected removed custody completion failure');
        END
      ''');
      await expectLater(
        repository.completeAcceptedDirectInboxCustodyIfExact(
          expected: removedRollbackEntry,
          relayExpiresAt: 9250,
        ),
        throwsA(isA<DatabaseException>()),
      );
      expect(
        await db.query(
          'messages',
          where: 'id = ?',
          whereArgs: <Object?>[removedRollback.id],
        ),
        isEmpty,
        reason: 'the hidden tombstone insert must roll back with retirement',
      );
      expect(
        await db.query(
          'direct_inbox_custody_outbox',
          where: 'message_id = ?',
          whereArgs: <Object?>[removedRollback.id],
        ),
        hasLength(1),
        reason: 'the exact v108 authority must remain retryable after rollback',
      );
    },
  );

  test(
    'committed custody stage still authorizes transport when publication reload throws',
    () async {
      final publicationFailureRepository = _buildRepository(
        db,
        capacity: 2,
        dbLoadMessageOverride: (_) async =>
            throw StateError('injected post-commit reload failure'),
      );
      final message = _message(
        'publication-stage-failure',
        envelope: _envelope('publication-stage-failure', 'cipher-stage'),
      );

      final result = await publicationFailureRepository
          .stageOutgoingDirectTextInboxCustody(
            expected: null,
            staged: message,
            kind: OutgoingOrdinaryAttemptKind.fresh,
            recipientPeerId: _peer,
            incarnationId: _incarnationA,
            wireEnvelope: message.wireEnvelope!,
          );

      expect(result.outcome, OutgoingOrdinaryMutationOutcome.applied);
      expect(result.authorizesTransport, isTrue);
      expect(result.message?.id, message.id);
      expect(
        await db.query(
          'messages',
          where: 'id = ?',
          whereArgs: <Object?>[message.id],
        ),
        hasLength(1),
      );
      expect(
        await db.query(
          'direct_inbox_custody_outbox',
          where: 'message_id = ?',
          whereArgs: <Object?>[message.id],
        ),
        hasLength(1),
      );
    },
  );

  test(
    'committed custody stage keeps transport authority when publication reload observes removal',
    () async {
      var publicationReloads = 0;
      final removalRaceRepository = _buildRepository(
        db,
        capacity: 2,
        dbLoadMessageOverride: (id) async {
          publicationReloads++;
          await dbDeleteMessage(db, id);
          return null;
        },
      );
      final message = _message(
        'publication-stage-removal',
        envelope: _envelope('publication-stage-removal', 'cipher-removed'),
      );

      final result = await removalRaceRepository
          .stageOutgoingDirectTextInboxCustody(
            expected: null,
            staged: message,
            kind: OutgoingOrdinaryAttemptKind.fresh,
            recipientPeerId: _peer,
            incarnationId: _incarnationB,
            wireEnvelope: message.wireEnvelope!,
          );

      expect(publicationReloads, 1);
      expect(result.outcome, OutgoingOrdinaryMutationOutcome.applied);
      expect(result.authorizesTransport, isTrue);
      expect(result.message?.id, message.id);
      expect(
        await db.query(
          'messages',
          where: 'id = ?',
          whereArgs: <Object?>[message.id],
        ),
        isEmpty,
      );
      expect(
        await db.query(
          'direct_inbox_custody_outbox',
          where: 'message_id = ?',
          whereArgs: <Object?>[message.id],
        ),
        hasLength(1),
        reason: 'physical removal must not cancel independent custody',
      );
    },
  );

  test(
    'direct-text custody boundary rejects ineligible rows, malformed identity, and transient media',
    () async {
      final disappearing = _message(
        'disappearing-boundary',
        envelope: _envelope('disappearing-boundary', 'cipher-disappearing'),
      ).copyWith(privateMediaPolicy: PrivateMediaPolicy.disappearing(86400));
      final outerMismatch = _message(
        'outer-mismatch-boundary',
        envelope: _envelope('different-outer-id', 'cipher-mismatch'),
      );
      final malformedEncrypted = _message(
        'malformed-encrypted-boundary',
        envelope:
            '{"type":"chat_message","version":"2",'
            '"id":"malformed-encrypted-boundary",'
            '"senderPeerId":"peer-self",'
            '"encrypted":{"kem":"kem","ciphertext":"","nonce":"nonce"}}',
      );

      for (final candidate
          in <({ConversationMessage message, String incarnationId})>[
            (message: disappearing, incarnationId: _incarnationA),
            (message: outerMismatch, incarnationId: _incarnationB),
            (message: malformedEncrypted, incarnationId: _incarnationC),
          ]) {
        final result = await repository.stageOutgoingDirectTextInboxCustody(
          expected: null,
          staged: candidate.message,
          kind: OutgoingOrdinaryAttemptKind.fresh,
          recipientPeerId: _peer,
          incarnationId: candidate.incarnationId,
          wireEnvelope: candidate.message.wireEnvelope!,
        );
        expect(result.outcome, OutgoingOrdinaryMutationOutcome.refused);
        expect(await db.query('messages'), isEmpty);
        expect(await db.query('direct_inbox_custody_outbox'), isEmpty);
      }

      var databaseStageCalls = 0;
      final mediaBoundaryRepository = _buildRepository(
        db,
        capacity: 2,
        onStageCustody: () => databaseStageCalls++,
      );
      final mediaMessage =
          _message(
            'media-boundary',
            envelope: _envelope('media-boundary', 'cipher-media'),
          ).copyWith(
            media: const <MediaAttachment>[
              MediaAttachment(
                id: 'media-boundary-attachment',
                messageId: 'media-boundary',
                mime: 'image/png',
                size: 16,
                mediaType: 'image',
                downloadStatus: 'upload_pending',
                createdAt: _t0,
              ),
            ],
          );
      final mediaResult = await mediaBoundaryRepository
          .stageOutgoingDirectTextInboxCustody(
            expected: null,
            staged: mediaMessage,
            kind: OutgoingOrdinaryAttemptKind.fresh,
            recipientPeerId: _peer,
            incarnationId: _incarnationD,
            wireEnvelope: mediaMessage.wireEnvelope!,
          );

      expect(mediaResult.outcome, OutgoingOrdinaryMutationOutcome.refused);
      expect(databaseStageCalls, 0);
      expect(await db.query('messages'), isEmpty);
      expect(await db.query('direct_inbox_custody_outbox'), isEmpty);
    },
  );

  test(
    'accepted completion remains completed when post-commit publication throws',
    () async {
      final message = _message(
        'publication-completion-failure',
        envelope: _envelope(
          'publication-completion-failure',
          'cipher-complete',
        ),
      );
      await repository.stageOutgoingDirectTextInboxCustody(
        expected: null,
        staged: message,
        kind: OutgoingOrdinaryAttemptKind.fresh,
        recipientPeerId: _peer,
        incarnationId: _incarnationB,
        wireEnvelope: message.wireEnvelope!,
      );

      var failureRecordAttempts = 0;
      final publicationFailureRepository = _buildRepository(
        db,
        capacity: 2,
        loadOutgoingOrdinaryMediaOverride: (_) async =>
            throw StateError('injected post-commit projection failure'),
        onRecordCustodyFailure: () => failureRecordAttempts++,
      );
      final attempt = await drainDirectInboxCustodyOutboxForMessage(
        custodyRepository: publicationFailureRepository,
        storeInAckCustodyInboxDetailed:
            (peerId, envelope, {required custodyKind, timeoutMs}) async =>
                const InboxStoreOutcome(
                  status: InboxStoreStatus.stored,
                  storeStatus: 'stored',
                  expiresAtMs: 9300,
                  custodyContract: ackOrExpiryInboxCustodyContract,
                ),
        recipientPeerId: _peer,
        messageId: message.id,
      );

      expect(attempt.found, isTrue);
      expect(attempt.completed, isTrue);
      expect(failureRecordAttempts, 0);
      expect(
        await db.query(
          'direct_inbox_custody_outbox',
          where: 'message_id = ?',
          whereArgs: <Object?>[message.id],
        ),
        isEmpty,
      );
      expect(
        (await db.query(
          'messages',
          where: 'id = ?',
          whereArgs: <Object?>[message.id],
        )).single,
        allOf(
          containsPair('status', 'inboxed'),
          containsPair('transport', 'inbox'),
          containsPair('relay_expires_at', 9300),
        ),
      );
    },
  );

  test(
    'eligible live settlement keeps committed delivery when publication throws',
    () async {
      final message = _message(
        'publication-live-settlement-failure',
        envelope: _envelope(
          'publication-live-settlement-failure',
          'cipher-live',
        ),
      );
      await repository.stageOutgoingDirectTextInboxCustody(
        expected: null,
        staged: message,
        kind: OutgoingOrdinaryAttemptKind.fresh,
        recipientPeerId: _peer,
        incarnationId: _incarnationC,
        wireEnvelope: message.wireEnvelope!,
      );
      final publicationFailureRepository = _buildRepository(
        db,
        capacity: 2,
        loadOutgoingOrdinaryMediaOverride: (_) async =>
            throw StateError('injected live-settlement publication failure'),
      );

      final result = await publicationFailureRepository
          .settleOutgoingOrdinaryTransport(
            messageId: message.id,
            expectedContactPeerId: _peer,
            expectedEnvelope: message.wireEnvelope,
            status: 'delivered',
            transport: 'direct',
            relayExpiresAt: null,
            mode: OutgoingOrdinarySettlementMode.live,
          );

      expect(result.outcome, OutgoingOrdinaryMutationOutcome.applied);
      expect(result.message?.status, 'delivered');
      expect(result.message?.transport, 'direct');
      expect(
        (await db.query(
          'messages',
          where: 'id = ?',
          whereArgs: <Object?>[message.id],
        )).single,
        allOf(
          containsPair('status', 'delivered'),
          containsPair('transport', 'direct'),
          containsPair('wire_envelope', null),
        ),
      );
      expect(
        await db.query(
          'direct_inbox_custody_outbox',
          where: 'message_id = ?',
          whereArgs: <Object?>[message.id],
        ),
        hasLength(1),
        reason: 'live delivery must not retire independent relay custody',
      );
    },
  );

  group('Plan 353 direct-delivered strict media lineage', () {
    const nowMs = 1900000000000;
    var incarnationSeq = 0;

    /// Seeds one strict ordinary outgoing initial whose complete v111
    /// generation is still bound to a live v108 incarnation.
    Future<({String messageId, List<String> attachmentIds, String incarnation})>
    seedBoundStrictInitial(String suffix) async {
      final messageId = 'tc353-01a-$suffix';
      final incarnation =
          'd0d0d0d0d0d0d0d0d0d0d0d0'
          '${(++incarnationSeq).toRadixString(16).padLeft(8, '0')}';
      final envelope = _envelope(messageId, 'cipher-$suffix');
      final attachmentIds = <String>['$messageId-a', '$messageId-b'];
      await db.insert(
        'messages',
        _message(messageId, envelope: envelope).toMap(),
      );
      final manifest = <DirectMediaBlobManifestProjection>[];
      for (var index = 0; index < attachmentIds.length; index++) {
        final attachmentId = attachmentIds[index];
        // Two DISTINCT commitments: no generation-level manifest hash and no
        // shared expiry can stand in for either row's own lineage digest.
        final contentHash = index == 0 ? '1' * 64 : '2' * 64;
        final ciphertextSize = 71 + index;
        final expiresAtMs = nowMs + 60000 + (index * 1000);
        await dbInsertMediaAttachment(db, <String, Object?>{
          'id': attachmentId,
          'message_id': messageId,
          'owner_lane': 'direct',
          'mime': 'image/jpeg',
          'size': 900 + index,
          'media_type': 'image',
          'created_at': _t0,
          'download_status': 'done',
          'local_path': 'media/direct/$attachmentId.jpg',
          'content_hash': contentHash,
          'encryption_key_base64': secureStoreReferenceForKey(
            mediaAttachmentEncryptionKeyStoreName(attachmentId),
          ),
          'encryption_nonce': 'nonce-$attachmentId',
          'encryption_scheme': 'blob_aes_256_gcm_v1',
        });
        await db.insert(
          kDirectMediaBlobCustodyTable,
          DirectMediaBlobCustodyRow(
            attachmentId: attachmentId,
            messageId: messageId,
            direction: DirectMediaBlobCustodyDirection.outgoing,
            state: DirectMediaBlobCustodyState.outgoingStored,
            inboxCustodyIncarnationId: incarnation,
            recipientPeerId: _peer,
            ciphertextRelativePath:
                'direct_media_blob_custody_v1/${'a' * 64}/$attachmentId.blob',
            contentHash: contentHash,
            ciphertextSize: ciphertextSize,
            expiresAtMs: expiresAtMs,
            custodyRelayPeerId: 'relay-$index',
            lastAttemptAt: null,
            nextAttemptAt: null,
            createdAt: _t0,
            updatedAt: _t0,
          ).toMap(),
        );
        manifest.add(
          DirectMediaBlobManifestProjection(
            attachmentId: attachmentId,
            commitment: DirectMediaBlobCustodyCommitment(
              contentHash: contentHash,
              ciphertextSize: ciphertextSize,
              expiresAtMs: expiresAtMs,
            ),
          ),
        );
      }
      await db.insert('direct_inbox_custody_outbox', <String, Object?>{
        'recipient_peer_id': _peer,
        'message_id': messageId,
        'incarnation_id': incarnation,
        'wire_envelope': envelope,
        'retry_count': 0,
        'last_attempt_at': null,
        'last_error_code': null,
        'created_at': _t0,
        'updated_at': _t0,
        'media_blob_expires_at_ms': earliestDirectMediaBlobExpiryMs(manifest),
        'media_blob_manifest_hash': computeDirectMediaBlobManifestHash(
          manifest,
        ),
      });
      return (
        messageId: messageId,
        attachmentIds: attachmentIds,
        incarnation: incarnation,
      );
    }

    Future<Map<String, String>> expectedLineageOf(String messageId) async {
      final rows = (await db.query(
        kDirectMediaBlobCustodyTable,
        where: 'message_id = ?',
        whereArgs: <Object?>[messageId],
        orderBy: 'attachment_id ASC',
      )).map(DirectMediaBlobCustodyRow.fromMap).toList(growable: false);
      return <String, String>{
        for (final row in rows)
          row.attachmentId: computeDirectMediaBlobCommitmentFingerprint(
            attachmentId: row.attachmentId,
            commitment: DirectMediaBlobCustodyCommitment(
              kind: row.custodyKind,
              contract: row.custodyContract,
              contentHash: row.contentHash,
              ciphertextSize: row.ciphertextSize,
              transportMime: row.transportMime,
              expiresAtMs: row.expiresAtMs!,
            ),
          ),
      };
    }

    Future<Map<String, Object?>> lineageOf(String messageId) async => {
      for (final row in await db.query(
        'media_attachments',
        columns: const <String>['id', 'direct_media_blob_custody_fingerprint'],
        where: 'message_id = ?',
        whereArgs: <Object?>[messageId],
        orderBy: 'id ASC',
      ))
        row['id']! as String: row['direct_media_blob_custody_fingerprint'],
    };

    Future<DirectInboxCustodyCompletionOutcome> completeBound(
      ({String messageId, List<String> attachmentIds, String incarnation})
      bound,
    ) async {
      final v108 = (await db.query(
        'direct_inbox_custody_outbox',
        where: 'message_id = ?',
        whereArgs: <Object?>[bound.messageId],
      )).single;
      return dbCompleteAcceptedDirectInboxCustodyIfExact(
        db,
        recipientPeerId: _peer,
        messageId: bound.messageId,
        expectedIncarnationId: bound.incarnation,
        expectedWireEnvelope: v108['wire_envelope']! as String,
        relayExpiresAt: (v108['media_blob_expires_at_ms']! as num).toInt() - 1,
      );
    }

    /// The exact projection a direct/LAN delivery receipt commits: `delivered`
    /// with the initial envelope cleared and every settlement field released.
    Future<void> deliverDirectly(
      String messageId, {
      String? transport = 'direct',
    }) async {
      expect(
        await db.update(
          'messages',
          <String, Object?>{
            'status': 'delivered',
            'transport': transport,
            'wire_envelope': null,
            'relay_expires_at': null,
            'custody_checked_at': null,
          },
          where: 'id = ?',
          whereArgs: <Object?>[messageId],
        ),
        1,
      );
    }

    test('TC-353-01a direct-delivered strict media keeps lineage through v108 '
        'completion', () async {
      // 1. The canonical delivered successor: a direct receipt already cleared
      //    the initial envelope before protected v108 acceptance landed.
      final delivered = await seedBoundStrictInitial('delivered');
      final expectedLineage = await expectedLineageOf(delivered.messageId);
      expect(expectedLineage, hasLength(2));
      expect(expectedLineage.values.toSet(), hasLength(2));
      await deliverDirectly(delivered.messageId);

      expect(
        await completeBound(delivered),
        DirectInboxCustodyCompletionOutcome.messagePreserved,
      );
      expect(
        await lineageOf(delivered.messageId),
        expectedLineage,
        reason: 'the delivered successor still owns exactly this generation',
      );
      final settled = (await db.query(
        'messages',
        where: 'id = ?',
        whereArgs: <Object?>[delivered.messageId],
      )).single;
      expect(settled['status'], 'delivered');
      expect(settled['transport'], 'direct');
      expect(settled['wire_envelope'], isNull);
      expect(settled['relay_expires_at'], isNull);
      expect(settled['custody_checked_at'], isNull);
      expect(
        await db.query(
          'direct_inbox_custody_outbox',
          where: 'message_id = ?',
          whereArgs: <Object?>[delivered.messageId],
        ),
        isEmpty,
      );
      final cleanup = (await db.query(
        kDirectMediaBlobCustodyTable,
        where: 'message_id = ?',
        whereArgs: <Object?>[delivered.messageId],
        orderBy: 'attachment_id ASC',
      )).map(DirectMediaBlobCustodyRow.fromMap).toList(growable: false);
      expect(
        cleanup.map((row) => row.state).toSet(),
        <DirectMediaBlobCustodyState>{
          DirectMediaBlobCustodyState.outgoingCleanupPending,
        },
      );
      for (final row in cleanup) {
        expect(
          await dbDeleteDirectMediaBlobCleanupPendingIfExact(db, expected: row),
          isTrue,
        );
      }
      expect(
        await lineageOf(delivered.messageId),
        expectedLineage,
        reason: 'lineage must survive the physical v111 drain',
      );
      expect(
        await dbClassifyOutgoingDirectDeletionLane(
          db,
          messageId: delivered.messageId,
        ),
        OutgoingDirectDeletionLane.strictMedia,
        reason: 'the existing delete classifier stays strict post-drain',
      );

      // 2. Every supported and null transport label is the same canonical
      //    delivered shape.
      for (final transport in <String?>[
        null,
        'wifi',
        'local',
        'direct',
        'reuse',
        'relay',
        'inbox',
      ]) {
        final supported = await seedBoundStrictInitial(
          'transport-${transport ?? 'null'}',
        );
        final expected = await expectedLineageOf(supported.messageId);
        await deliverDirectly(supported.messageId, transport: transport);
        expect(
          await completeBound(supported),
          DirectInboxCustodyCompletionOutcome.messagePreserved,
          reason: 'transport $transport',
        );
        expect(
          await lineageOf(supported.messageId),
          expected,
          reason: 'transport $transport must still own its lineage',
        );
      }

      // 3. Successors that are NOT the canonical delivered settlement never
      //    gain authorship, and each keeps its current completion outcome.
      final unauthored = <String, Future<void> Function(String messageId)>{
        'later edit': (messageId) async {
          await db.update(
            'messages',
            <String, Object?>{
              'status': 'sending',
              'transport': null,
              'edited_at': _t1,
              'wire_envelope': _envelope(messageId, 'cipher-edit-attempt'),
            },
            where: 'id = ?',
            whereArgs: <Object?>[messageId],
          );
        },
        'delivered row that still carries an edit': (messageId) async {
          await deliverDirectly(messageId);
          await db.update(
            'messages',
            <String, Object?>{'edited_at': _t1},
            where: 'id = ?',
            whereArgs: <Object?>[messageId],
          );
        },
        'author tombstone': (messageId) async {
          await db.update(
            'messages',
            <String, Object?>{
              'text': '',
              'status': 'sending',
              'deleted_at': _t1,
              'deleted_by_peer_id': 'peer-self',
              'wire_envelope': _envelope(messageId, 'cipher-tombstone'),
            },
            where: 'id = ?',
            whereArgs: <Object?>[messageId],
          );
        },
        'crossed recipient': (messageId) async {
          await deliverDirectly(messageId);
          await db.update(
            'messages',
            const <String, Object?>{'contact_peer_id': 'peer-crossed'},
            where: 'id = ?',
            whereArgs: <Object?>[messageId],
          );
        },
        'malformed delivered relay expiry': (messageId) async {
          await deliverDirectly(messageId);
          await db.update(
            'messages',
            const <String, Object?>{'relay_expires_at': 1900000123456},
            where: 'id = ?',
            whereArgs: <Object?>[messageId],
          );
        },
        'malformed delivered custody check': (messageId) async {
          await deliverDirectly(messageId);
          await db.update(
            'messages',
            const <String, Object?>{'custody_checked_at': _t1},
            where: 'id = ?',
            whereArgs: <Object?>[messageId],
          );
        },
        'malformed delivered transport': (messageId) async {
          await deliverDirectly(messageId, transport: 'carrier-pigeon');
        },
      };
      for (final entry in unauthored.entries) {
        final seeded = await seedBoundStrictInitial(
          entry.key.replaceAll(' ', '-'),
        );
        await entry.value(seeded.messageId);
        final before = (await db.query(
          'messages',
          where: 'id = ?',
          whereArgs: <Object?>[seeded.messageId],
        )).single;
        await completeBound(seeded);
        expect(
          await lineageOf(seeded.messageId),
          <String, Object?>{for (final id in seeded.attachmentIds) id: null},
          reason: '${entry.key} must never receive lineage authorship',
        );
        expect(
          (await db.query(
            'messages',
            where: 'id = ?',
            whereArgs: <Object?>[seeded.messageId],
          )).single,
          before,
          reason: '${entry.key} keeps its current completion outcome',
        );
      }
    });

    /// Rewrites a seeded ordinary strict parent into the exact newly authored
    /// v1 private shape Plan 358 (disappearing) or Plan 354 (P/VO) authors.
    Future<void> applyPrivatePolicy(
      String messageId, {
      required String mode,
      int? durationSeconds,
      String state = 'available',
    }) async {
      expect(
        await db.update(
          'messages',
          <String, Object?>{
            'text': '',
            'private_media_policy_version': 1,
            'private_media_mode': mode,
            'private_media_duration_seconds': durationSeconds,
            'private_media_state': state,
          },
          where: 'id = ?',
          whereArgs: <Object?>[messageId],
        ),
        1,
      );
    }

    test('TC-358-01c accepted disappearing custody preserves strict lineage '
        'through v111 drain', () async {
      // 1. Every allowed duration stamps the exact per-attachment lineage
      //    before v108 retirement and the v111 cleanup transition.
      for (final durationSeconds in <int>[3600, 86400, 604800]) {
        final bound = await seedBoundStrictInitial(
          'disappearing-$durationSeconds',
        );
        await applyPrivatePolicy(
          bound.messageId,
          mode: 'disappearing',
          durationSeconds: durationSeconds,
        );
        final expectedLineage = await expectedLineageOf(bound.messageId);
        expect(expectedLineage, hasLength(2));
        expect(expectedLineage.values.toSet(), hasLength(2));

        expect(
          await completeBound(bound),
          DirectInboxCustodyCompletionOutcome.messageAdvanced,
          reason: 'duration $durationSeconds',
        );
        expect(
          await lineageOf(bound.messageId),
          expectedLineage,
          reason:
              'an accepted disappearing generation owns exactly this '
              'lineage ($durationSeconds)',
        );
        expect(
          await db.query(
            'direct_inbox_custody_outbox',
            where: 'message_id = ?',
            whereArgs: <Object?>[bound.messageId],
          ),
          isEmpty,
        );
        final advanced = (await db.query(
          'messages',
          where: 'id = ?',
          whereArgs: <Object?>[bound.messageId],
        )).single;
        expect(advanced['status'], 'inboxed');
        expect(advanced['transport'], 'inbox');
        // The transport lease never becomes the receiver-local deadline.
        expect(advanced['private_media_expires_at_ms'], isNull);
        expect(advanced['private_media_received_at_ms'], isNull);
        expect(advanced['private_media_clock_high_water_ms'], isNull);
        expect(advanced['private_media_duration_seconds'], durationSeconds);

        final cleanup = (await db.query(
          kDirectMediaBlobCustodyTable,
          where: 'message_id = ?',
          whereArgs: <Object?>[bound.messageId],
          orderBy: 'attachment_id ASC',
        )).map(DirectMediaBlobCustodyRow.fromMap).toList(growable: false);
        expect(
          cleanup.map((row) => row.state).toSet(),
          <DirectMediaBlobCustodyState>{
            DirectMediaBlobCustodyState.outgoingCleanupPending,
          },
        );
        for (final row in cleanup) {
          expect(
            await dbDeleteDirectMediaBlobCleanupPendingIfExact(
              db,
              expected: row,
            ),
            isTrue,
          );
        }
        expect(
          await lineageOf(bound.messageId),
          expectedLineage,
          reason: 'disappearing lineage must survive the physical v111 drain',
        );
      }

      // 2. Exact Protected and View-Once controls still converge, but a
      //    broad `policyVersion == 1` patch must not stamp them.
      for (final mode in <String>['protected', 'view_once']) {
        final control = await seedBoundStrictInitial('control-$mode');
        await applyPrivatePolicy(control.messageId, mode: mode);
        expect(
          await completeBound(control),
          DirectInboxCustodyCompletionOutcome.messageAdvanced,
          reason: mode,
        );
        expect(
          await lineageOf(control.messageId),
          <String, Object?>{for (final id in control.attachmentIds) id: null},
          reason: '$mode keeps its no-v110 owner and gains no fingerprint',
        );
        expect(
          await db.query(
            'direct_inbox_custody_outbox',
            where: 'message_id = ?',
            whereArgs: <Object?>[control.messageId],
          ),
          isEmpty,
          reason: '$mode still retires its exact v108 incarnation',
        );
        expect(
          (await db.query(
                kDirectMediaBlobCustodyTable,
                where: 'message_id = ?',
                whereArgs: <Object?>[control.messageId],
              ))
              .map(DirectMediaBlobCustodyRow.fromMap)
              .map((row) => row.state)
              .toSet(),
          <DirectMediaBlobCustodyState>{
            DirectMediaBlobCustodyState.outgoingCleanupPending,
          },
          reason: '$mode still converges its v111 generation',
        );
      }

      // 3. Crossed or malformed disappearing state is not this lineage.
      // An out-of-set duration is already impossible: the frozen v100 CHECK
      // constraint rejects the write itself, which is strictly stronger than
      // a predicate refusal.
      {
        final schemaGuarded = await seedBoundStrictInitial('schema-duration');
        await expectLater(
          db.update(
            'messages',
            const <String, Object?>{
              'private_media_policy_version': 1,
              'private_media_mode': 'disappearing',
              'private_media_duration_seconds': 7200,
            },
            where: 'id = ?',
            whereArgs: <Object?>[schemaGuarded.messageId],
          ),
          throwsA(isA<DatabaseException>()),
        );
      }

      final crossed = <String, Future<void> Function(String messageId)>{
        'missing duration': (messageId) =>
            applyPrivatePolicy(messageId, mode: 'disappearing'),
        'terminal state': (messageId) => applyPrivatePolicy(
          messageId,
          mode: 'disappearing',
          durationSeconds: 3600,
          state: 'expired',
        ),
        'receiver clock on an outgoing row': (messageId) async {
          await applyPrivatePolicy(
            messageId,
            mode: 'disappearing',
            durationSeconds: 3600,
          );
          await db.update(
            'messages',
            const <String, Object?>{
              'private_media_received_at_ms': 1,
              'private_media_expires_at_ms': 3600001,
              'private_media_clock_high_water_ms': 1,
            },
            where: 'id = ?',
            whereArgs: <Object?>[messageId],
          );
        },
      };
      for (final entry in crossed.entries) {
        final seeded = await seedBoundStrictInitial(
          'crossed-${entry.key.replaceAll(' ', '-')}',
        );
        await entry.value(seeded.messageId);
        await completeBound(seeded);
        expect(
          await lineageOf(seeded.messageId),
          <String, Object?>{for (final id in seeded.attachmentIds) id: null},
          reason: '${entry.key} must never receive lineage authorship',
        );
      }
    });
  });
}

ConversationMessage _message(
  String id, {
  required String envelope,
  String createdAt = _t0,
}) => ConversationMessage(
  id: id,
  contactPeerId: _peer,
  senderPeerId: 'peer-self',
  text: 'immutable text for $id',
  timestamp: createdAt,
  status: 'sending',
  isIncoming: false,
  createdAt: createdAt,
  wireEnvelope: envelope,
  dedupKey: id,
);

String _envelope(String id, String ciphertext) =>
    '{"type":"chat_message","version":"2","id":"$id",'
    '"senderPeerId":"peer-self",'
    '"encrypted":{"kem":"kem","ciphertext":"$ciphertext","nonce":"nonce"}}';

MessageRepositoryImpl _buildRepository(
  Database db, {
  required int capacity,
  String? omitCustodyDelegate,
  Future<Map<String, Object?>?> Function(String id)? dbLoadMessageOverride,
  Future<List<MediaAttachment>> Function(String messageId)?
  loadOutgoingOrdinaryMediaOverride,
  void Function()? onStageCustody,
  void Function()? onRecordCustodyFailure,
}) {
  return MessageRepositoryImpl(
    dbInsertMessage: (row) => dbInsertMessage(db, row),
    dbLoadMessagesForContact: (peerId) => dbLoadMessagesForContact(db, peerId),
    dbLoadLatestMessageForContact: (peerId) =>
        dbLoadLatestMessageForContact(db, peerId),
    dbUpdateMessageStatus: (id, status) =>
        dbUpdateMessageStatus(db, id, status),
    dbLoadMessage: dbLoadMessageOverride ?? (id) => dbLoadMessage(db, id),
    dbCountMessagesForContact: (peerId) =>
        dbCountMessagesForContact(db, peerId),
    dbMarkConversationAsRead: (peerId) => dbMarkConversationAsRead(db, peerId),
    dbCountUnreadForContact: (peerId) => dbCountUnreadForContact(db, peerId),
    dbCountTotalUnread: () => dbCountTotalUnread(db),
    dbCountTotalUnreadExcludingArchived: () =>
        dbCountTotalUnreadExcludingArchived(db),
    dbDeleteMessagesForContact: (peerId) =>
        dbDeleteMessagesForContact(db, peerId),
    dbDeleteMessage: (id) => dbDeleteMessage(db, id),
    dbExistsMessageByContent: (peerId, senderPeerId, text, timestamp) =>
        dbExistsMessageByContent(db, peerId, senderPeerId, text, timestamp),
    dbLoadMessagesPage: (peerId, {limit = 50, beforeTimestamp}) =>
        dbLoadMessagesPage(
          db,
          peerId,
          limit: limit,
          beforeTimestamp: beforeTimestamp,
        ),
    dbLoadFailedOutgoingMessages: () => dbLoadFailedOutgoingMessages(db),
    dbLoadUnackedOutgoingMessages: ({required olderThan, limit = 50}) =>
        dbLoadUnackedOutgoingMessages(db, olderThan: olderThan, limit: limit),
    dbLoadConversationThreadSummaries: (peerIds) =>
        dbLoadConversationThreadSummaries(db, peerIds),
    dbRecoverStuckSendingMessages: ({required olderThan, limit = 50}) =>
        dbRecoverStuckSendingMessages(db, olderThan: olderThan, limit: limit),
    dbLoadStuckSendingOutgoingMessages: ({required olderThan, limit = 50}) =>
        dbLoadStuckSendingOutgoingMessages(
          db,
          olderThan: olderThan,
          limit: limit,
        ),
    dbLoadSendingOutgoingMessages: () => dbLoadSendingOutgoingMessages(db),
    dbConditionalTransitionStatus:
        (id, {required fromStatus, required toStatus}) =>
            dbConditionalTransitionStatus(
              db,
              id,
              fromStatus: fromStatus,
              toStatus: toStatus,
            ),
    dbStageOutgoingDirectTextInboxCustody: omitCustodyDelegate == 'stage'
        ? null
        : ({
            required expectedRow,
            required stagedRow,
            required kind,
            required recipientPeerId,
            required messageId,
            required incarnationId,
            required wireEnvelope,
          }) {
            onStageCustody?.call();
            return dbStageOutgoingDirectTextInboxCustody(
              db,
              expectedRow: expectedRow,
              stagedRow: stagedRow,
              kind: kind,
              recipientPeerId: recipientPeerId,
              messageId: messageId,
              incarnationId: incarnationId,
              wireEnvelope: wireEnvelope,
              capacity: capacity,
            );
          },
    dbLoadDirectInboxCustodyOutbox: omitCustodyDelegate == 'loadBatch'
        ? null
        : ({limit = 50}) => dbLoadDirectInboxCustodyOutbox(db, limit: limit),
    dbLoadDirectInboxCustodyOutboxForMessage:
        omitCustodyDelegate == 'loadMessage'
        ? null
        : ({required recipientPeerId, required messageId}) =>
              dbLoadDirectInboxCustodyOutboxForMessage(
                db,
                recipientPeerId: recipientPeerId,
                messageId: messageId,
              ),
    dbLoadDirectInboxCustodyOutboxOwnerForMessageId:
        omitCustodyDelegate == 'loadOwner'
        ? null
        : ({required messageId}) =>
              dbLoadDirectInboxCustodyOutboxOwnerForMessageId(
                db,
                messageId: messageId,
              ),
    dbRecordDirectInboxCustodyFailureIfExact:
        omitCustodyDelegate == 'recordFailure'
        ? null
        : ({
            required recipientPeerId,
            required messageId,
            required expectedIncarnationId,
            required expectedWireEnvelope,
            required errorCode,
            required attemptedAt,
          }) {
            onRecordCustodyFailure?.call();
            return dbRecordDirectInboxCustodyFailureIfExact(
              db,
              recipientPeerId: recipientPeerId,
              messageId: messageId,
              expectedIncarnationId: expectedIncarnationId,
              expectedWireEnvelope: expectedWireEnvelope,
              errorCode: errorCode,
              attemptedAt: attemptedAt,
            );
          },
    dbCompleteAcceptedDirectInboxCustodyIfExact:
        omitCustodyDelegate == 'complete'
        ? null
        : ({
            required recipientPeerId,
            required messageId,
            required expectedIncarnationId,
            required expectedWireEnvelope,
            required relayExpiresAt,
          }) => dbCompleteAcceptedDirectInboxCustodyIfExact(
            db,
            recipientPeerId: recipientPeerId,
            messageId: messageId,
            expectedIncarnationId: expectedIncarnationId,
            expectedWireEnvelope: expectedWireEnvelope,
            relayExpiresAt: relayExpiresAt,
          ),
    dbSettleOutgoingOrdinaryTransport:
        ({
          required messageId,
          required expectedContactPeerId,
          required expectedEnvelope,
          required status,
          required transport,
          required relayExpiresAt,
          required mode,
        }) => dbSettleOutgoingOrdinaryTransport(
          db,
          messageId: messageId,
          expectedContactPeerId: expectedContactPeerId,
          expectedEnvelope: expectedEnvelope,
          status: status,
          transport: transport,
          relayExpiresAt: relayExpiresAt,
          mode: mode,
        ),
    loadOutgoingOrdinaryMedia: loadOutgoingOrdinaryMediaOverride,
    now: () => DateTime.parse(_t1),
  );
}
