import 'dart:io';

import 'package:flutter_app/core/database/helpers/direct_inbox_custody_outbox_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/messages_db_helpers.dart';
import 'package:flutter_app/core/database/outgoing_transport_mutation.dart';
import 'package:flutter_app/core/database/production_migration_registry.dart';
import 'package:flutter_app/core/media/private_media_policy.dart';
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
        version: 108,
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

  test(
    'runtime custody capability requires the complete five-callback set',
    () {
      expect(repository.supportsDirectTextInboxCustody, isTrue);
      for (final omitted in <String>{
        'stage',
        'loadBatch',
        'loadMessage',
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
    },
  );

  test(
    'TC-342-02 atomic immutable direct-text custody mutations fail closed',
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
      final laterEditEnvelope = _envelope(crossedEdit.id, 'cipher-later-edit');
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
      expect(
        await db.query(
          'direct_inbox_custody_outbox',
          where: 'message_id = ?',
          whereArgs: <Object?>[removed.id],
        ),
        isEmpty,
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
        storeInInboxDetailed: (peerId, envelope, {timeoutMs}) async =>
            const InboxStoreOutcome(
              status: InboxStoreStatus.stored,
              expiresAtMs: 9300,
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
