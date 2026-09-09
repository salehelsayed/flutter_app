import 'dart:convert';
import 'dart:io';

import 'package:flutter_app/core/database/app_database_version.dart';
import 'package:flutter_app/core/database/direct_event_fanout_contract.dart';
import 'package:flutter_app/core/database/direct_media_blob_custody.dart';
import 'package:flutter_app/core/database/helpers/direct_contact_device_bindings_db_helpers.dart';
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

  String diagnosticEnvelope(
    String id, {
    Map<String, Object?> extra = const {},
  }) => jsonEncode({
    ...jsonDecode(_envelope(id, 'unchanged-ciphertext'))
        as Map<String, dynamic>,
    'diagnosticTraceId': '07cdbd8a-ae03-42de-8dbb-3e688e107967',
    ...extra,
  });

  Future<ConversationMessage> stageDiagnosticEnvelope(
    String id, {
    Map<String, Object?> extra = const {},
  }) async {
    final message = _message(
      id,
      envelope: diagnosticEnvelope(id, extra: extra),
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
    return message;
  }

  for (final loadKind in ['batch', 'recipient', 'owner']) {
    test(
      'legacy diagnostic custody repair is atomic and fenced through $loadKind load',
      () async {
        final message = await stageDiagnosticEnvelope(
          'legacy-diagnostic-repair',
        );
        final legacyWire = message.wireEnvelope!;
        final originalOwner = (await db.query(
          'direct_inbox_custody_outbox',
        )).single;
        await db.close();
        db = await databaseFactoryFfi.openDatabase(
          '${tempDirectory.path}/identity.db',
          options: OpenDatabaseOptions(singleInstance: false),
        );
        repository = _buildRepository(db, capacity: 2);
        final repaired = switch (loadKind) {
          'batch' => (await repository.loadDirectInboxCustody()).single,
          'recipient' => (await repository.loadDirectInboxCustodyForMessage(
            recipientPeerId: _peer,
            messageId: message.id,
          ))!,
          _ => (await repository.loadDirectInboxCustodyOwnerForMessageId(
            messageId: message.id,
          ))!,
        };
        final expected = _envelope(message.id, 'unchanged-ciphertext');
        expect(repaired.wireEnvelope, expected);
        expect(repaired.incarnationId, _incarnationA);
        expect(
          (await dbLoadMessage(db, message.id))!['wire_envelope'],
          expected,
        );
        expect((await db.query('direct_inbox_custody_outbox')).single, {
          ...originalOwner,
          'wire_envelope': expected,
        });
        expect(
          await dbRecordDirectInboxCustodyFailureIfExact(
            db,
            recipientPeerId: _peer,
            messageId: message.id,
            expectedIncarnationId: _incarnationA,
            expectedWireEnvelope: legacyWire,
            errorCode: DirectInboxCustodyErrorCode.storeFailed,
            attemptedAt: _t1,
          ),
          isFalse,
        );
        final stale = await dbCompleteAcceptedDirectInboxCustodyIfExact(
          db,
          recipientPeerId: _peer,
          messageId: message.id,
          expectedIncarnationId: _incarnationA,
          expectedWireEnvelope: legacyWire,
          relayExpiresAt: null,
        );
        expect(stale, DirectInboxCustodyCompletionOutcome.stale);
        final completions = await Future.wait([
          repository.completeAcceptedDirectInboxCustodyIfExact(
            expected: repaired,
            relayExpiresAt: null,
          ),
          repository.completeAcceptedDirectInboxCustodyIfExact(
            expected: repaired,
            relayExpiresAt: null,
          ),
        ]);
        expect(completions.where((result) => result.completed), hasLength(1));
        expect(await db.query('direct_inbox_custody_outbox'), isEmpty);
        expect((await dbLoadMessage(db, message.id))!['status'], 'inboxed');
      },
    );
  }

  test('legacy diagnostic repair accepts an uppercase v4 UUID', () async {
    final message = await stageDiagnosticEnvelope(
      'legacy-diagnostic-uppercase',
      extra: {'diagnosticTraceId': '07CDBD8A-AE03-42DE-8DBB-3E688E107967'},
    );
    expect(
      (await repository.loadDirectInboxCustody()).single.wireEnvelope,
      _envelope(message.id, 'unchanged-ciphertext'),
    );
  });

  test('legacy diagnostic repair resumes the production custody drain', () async {
    final message = await stageDiagnosticEnvelope('legacy-diagnostic-drain');
    var stores = 0;
    final completed = await drainDirectInboxCustodyOutbox(
      custodyRepository: repository,
      storeInAckCustodyInboxDetailed:
          (recipient, envelope, {required custodyKind, timeoutMs}) async {
        stores++;
        expect(recipient, _peer);
        expect(custodyKind, AckCustodyKind.directTextV108);
        expect(envelope, _envelope(message.id, 'unchanged-ciphertext'));
        return const InboxStoreOutcome(
          status: InboxStoreStatus.stored,
          storeStatus: 'stored',
          custodyContract: ackOrExpiryInboxCustodyContract,
        );
      },
    );
    expect(completed, 1);
    expect(stores, 1);
    expect(await db.query('direct_inbox_custody_outbox'), isEmpty);
    expect((await dbLoadMessage(db, message.id))!['status'], 'inboxed');
  });

  test(
    'legacy diagnostic repair rolls owner and parent back together',
    () async {
      final message = await stageDiagnosticEnvelope(
        'legacy-diagnostic-rollback',
      );
      await db.execute('''CREATE TRIGGER refuse_legacy_parent_repair
      BEFORE UPDATE OF wire_envelope ON messages
      BEGIN SELECT RAISE(ABORT, 'test parent write failure'); END''');
      await expectLater(
        repository.loadDirectInboxCustody(),
        throwsA(isA<DatabaseException>()),
      );
      expect(
        (await db.query('direct_inbox_custody_outbox')).single['wire_envelope'],
        message.wireEnvelope,
      );
      expect(
        (await dbLoadMessage(db, message.id))!['wire_envelope'],
        message.wireEnvelope,
      );
      await db.execute('DROP TRIGGER refuse_legacy_parent_repair');
      expect(
        (await repository.loadDirectInboxCustody()).single.wireEnvelope,
        _envelope(message.id, 'unchanged-ciphertext'),
      );
    },
  );

  for (final variation in [
    'unknown-field',
    'invalid-trace',
    'successor',
    'recipient-drift',
    'media-bound',
  ]) {
    test(
      'legacy diagnostic repair preserves $variation authority unchanged',
      () async {
        final message = await stageDiagnosticEnvelope(
          'legacy-diagnostic-refusal',
          extra: {
            if (variation == 'unknown-field') 'futureAuthority': 'preserve-me',
            if (variation == 'invalid-trace') 'diagnosticTraceId': 'not-a-uuid',
          },
        );
        if (variation == 'successor') {
          await db.update(
            'messages',
            {'status': 'delivered', 'wire_envelope': null, 'read_at': _t1},
            where: 'id = ?',
            whereArgs: [message.id],
          );
        } else if (variation == 'recipient-drift') {
          await db.update(
            'messages',
            {'contact_peer_id': 'different-recipient'},
            where: 'id = ?',
            whereArgs: [message.id],
          );
        } else if (variation == 'media-bound') {
          await db.update('direct_inbox_custody_outbox', {
            'media_blob_manifest_hash': 'a' * 64,
            'media_blob_expires_at_ms': 1,
          });
        }
        final beforeOwner = (await db.query(
          'direct_inbox_custody_outbox',
        )).single;
        final beforeParent = await dbLoadMessage(db, message.id);
        final owner = (await repository.loadDirectInboxCustody()).single;
        expect(owner.wireEnvelope, message.wireEnvelope);
        expect(
          (await db.query('direct_inbox_custody_outbox')).single,
          beforeOwner,
        );
        expect(await dbLoadMessage(db, message.id), beforeParent);
      },
    );
  }

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
    'TC-361-01b legacy uninitialized fresh text stage cannot create a sibling '
    'global message-id owner',
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

  group('TC-361-01b blob-free direct event fanout (DB v113)', () {
    Future<DirectContactFanoutSnapshot> seedInitializedFanoutContact({
      bool legacyRevoked = true,
      bool includeDeviceB = true,
    }) async {
      await db.insert('contacts', _fanoutContactRow());
      await db.insert(
        'direct_contact_device_roster_metadata',
        _fanoutRosterMetadataRow(legacyRevoked: legacyRevoked),
      );
      await db.insert(
        'direct_contact_device_bindings',
        _fanoutBindingRow('device-a', _deviceTransportA, 'mlkem-device-a'),
      );
      if (includeDeviceB) {
        await db.insert(
          'direct_contact_device_bindings',
          _fanoutBindingRow('device-b', _deviceTransportB, 'mlkem-device-b'),
        );
      }
      final snapshot = await dbReadDirectContactFanoutSnapshot(
        db,
        contactAccountPeerId: _contactAccount,
      );
      expect(snapshot, isNotNull);
      return snapshot!;
    }

    Future<DbDirectEventFanoutStageResult> stageFanout({
      required String messageId,
      required DirectContactFanoutSnapshot snapshot,
      required List<DirectEventFanoutTargetCandidate> candidates,
      Map<String, Object?>? stagedRowOverride,
      int capacity = kDirectInboxCustodyOutboxCapacity,
      Future<void> Function()? beforeSiblingInsertForTest,
    }) {
      return dbStageOutgoingDirectTextFanoutInboxCustody(
        db,
        stagedRow:
            stagedRowOverride ??
            _fanoutStagedRow(
              messageId,
              witnessEnvelope: candidates.first.wireEnvelope,
            ),
        messageId: messageId,
        contactAccountPeerId: _contactAccount,
        senderTransportPeerId: 'peer-self',
        expectedSnapshot: snapshot,
        candidates: candidates,
        capacity: capacity,
        beforeSiblingInsertForTest: beforeSiblingInsertForTest,
      );
    }

    List<DirectEventFanoutTargetCandidate> candidatesFor(
      String messageId,
      DirectContactFanoutSnapshot snapshot,
    ) => <DirectEventFanoutTargetCandidate>[
      for (final target in snapshot.targets)
        DirectEventFanoutTargetCandidate(
          recipientPeerId: target.peerId,
          wireEnvelope: _envelope(messageId, 'cipher-for-${target.peerId}'),
        ),
    ];

    test('TC-361-01b authorized fanout stages the exact all-target batch '
        'atomically and every contradiction is all-zero', () async {
      final snapshot = await seedInitializedFanoutContact(legacyRevoked: false);
      expect(
        snapshot.targets.map((target) => target.peerId).toList(),
        const <String>[_contactAccount, _deviceTransportA, _deviceTransportB],
        reason: 'legacy target first, then stable device order',
      );

      const messageId = 'fanout-initial-1';
      final candidates = candidatesFor(messageId, snapshot);
      final staged = await stageFanout(
        messageId: messageId,
        snapshot: snapshot,
        candidates: candidates,
      );
      expect(staged.outcome, DirectEventFanoutStageOutcome.applied);
      expect(staged.authorizesTransport, isTrue);
      expect(staged.rows, hasLength(3));

      final message = (await db.query(
        'messages',
        where: 'id = ?',
        whereArgs: const <Object?>[messageId],
      )).single;
      expect(message['direct_event_fanout_generation_id'], messageId);
      expect(message['contact_peer_id'], _contactAccount);
      expect(
        message['wire_envelope'],
        candidates.first.wireEnvelope,
        reason: 'the representative witness is the first stable target',
      );

      final rows = await dbLoadDirectInboxCustodyOutboxRowsForMessageId(
        db,
        messageId: messageId,
      );
      expect(rows, hasLength(3));
      for (final candidate in candidates) {
        final row = rows.singleWhere(
          (row) => row['recipient_peer_id'] == candidate.recipientPeerId,
        );
        expect(row['wire_envelope'], candidate.wireEnvelope);
        expect(row['contact_account_peer_id'], _contactAccount);
        expect(
          row['incarnation_id'],
          computeDirectEventFanoutIncarnation(
            messageId: messageId,
            recipientPeerId: candidate.recipientPeerId,
          ),
          reason: 'one deterministic incarnation per (message, target)',
        );
      }

      Future<void> expectAllZero(
        Future<DbDirectEventFanoutStageResult> Function() attempt, {
        required String reason,
      }) async {
        final beforeMessages = await db.query('messages', orderBy: 'id');
        final beforeRows = await db.query(
          _fanoutTable,
          orderBy: 'incarnation_id',
        );
        final result = await attempt();
        expect(
          result.outcome,
          DirectEventFanoutStageOutcome.refused,
          reason: reason,
        );
        expect(result.authorizesTransport, isFalse, reason: reason);
        expect(
          await db.query('messages', orderBy: 'id'),
          beforeMessages,
          reason: reason,
        );
        expect(
          await db.query(_fanoutTable, orderBy: 'incarnation_id'),
          beforeRows,
          reason: reason,
        );
      }

      // Zero targets: initialized roster, legacy revoked, no active binding.
      await db.insert('contacts', _fanoutContactRow(peerId: _secondAccount));
      await db
          .insert('direct_contact_device_roster_metadata', <String, Object?>{
            ..._fanoutRosterMetadataRow(legacyRevoked: true),
            'contact_account_peer_id': _secondAccount,
          });
      final zeroTargets = await dbReadDirectContactFanoutSnapshot(
        db,
        contactAccountPeerId: _secondAccount,
      );
      expect(zeroTargets, isNotNull);
      expect(zeroTargets!.targets, isEmpty);
      await expectAllZero(
        () => dbStageOutgoingDirectTextFanoutInboxCustody(
          db,
          stagedRow: _fanoutStagedRow(
            'fanout-zero-targets',
            witnessEnvelope: _envelope('fanout-zero-targets', 'cipher-zero'),
            contactPeerId: _secondAccount,
          ),
          messageId: 'fanout-zero-targets',
          contactAccountPeerId: _secondAccount,
          senderTransportPeerId: 'peer-self',
          expectedSnapshot: zeroTargets,
          candidates: const <DirectEventFanoutTargetCandidate>[],
        ),
        reason: 'zero authorized targets must fail closed',
      );

      // Snapshot drift between capture and stage: key/fingerprint changed.
      const driftedId = 'fanout-drifted';
      final driftedCandidates = candidatesFor(driftedId, snapshot);
      await db.update(
        'direct_contact_device_bindings',
        <String, Object?>{
          'device_ml_kem_public_key': 'mlkem-device-b-rotated',
          'binding_fingerprint': 'b' * 64,
        },
        where: 'device_id = ?',
        whereArgs: const <Object?>['device-b'],
      );
      await expectAllZero(
        () => stageFanout(
          messageId: driftedId,
          snapshot: snapshot,
          candidates: driftedCandidates,
        ),
        reason: 'a stale caller snapshot must fail the whole batch',
      );
      await db.update(
        'direct_contact_device_bindings',
        <String, Object?>{
          'device_ml_kem_public_key': 'mlkem-device-b',
          'binding_fingerprint': _fanoutFingerprint('device-b'),
        },
        where: 'device_id = ?',
        whereArgs: const <Object?>['device-b'],
      );

      // Partial candidate set, duplicate transport, and capacity shortage.
      const partialId = 'fanout-partial';
      final partial = candidatesFor(partialId, snapshot)..removeLast();
      await expectAllZero(
        () => stageFanout(
          messageId: partialId,
          snapshot: snapshot,
          candidates: partial,
        ),
        reason: 'a missing per-target candidate must fail the whole batch',
      );
      final duplicated = candidatesFor(partialId, snapshot);
      duplicated[2] = DirectEventFanoutTargetCandidate(
        recipientPeerId: duplicated[1].recipientPeerId,
        wireEnvelope: duplicated[1].wireEnvelope,
      );
      await expectAllZero(
        () => stageFanout(
          messageId: partialId,
          snapshot: snapshot,
          candidates: duplicated,
        ),
        reason: 'a duplicate transport must fail the whole batch',
      );
      await expectAllZero(
        () => stageFanout(
          messageId: partialId,
          snapshot: snapshot,
          candidates: candidatesFor(partialId, snapshot),
          capacity: 5,
        ),
        reason: 'capacity must admit the whole batch or nothing',
      );

      // Injected sibling-insert failure rolls the whole batch back.
      var insertsBeforeFailure = 0;
      await expectLater(
        stageFanout(
          messageId: 'fanout-injected-failure',
          snapshot: snapshot,
          candidates: candidatesFor('fanout-injected-failure', snapshot),
          beforeSiblingInsertForTest: () async {
            insertsBeforeFailure++;
            if (insertsBeforeFailure == 2) {
              throw StateError('injected sibling insert failure');
            }
          },
        ),
        throwsA(isA<StateError>()),
      );
      expect(
        await db.query(
          'messages',
          where: 'id = ?',
          whereArgs: const <Object?>['fanout-injected-failure'],
        ),
        isEmpty,
        reason: 'a partial batch must roll back the canonical message',
      );
      expect(
        await dbLoadDirectInboxCustodyOutboxRowsForMessageId(
          db,
          messageId: 'fanout-injected-failure',
        ),
        isEmpty,
        reason: 'a partial batch must roll back every sibling',
      );

      // A conflicting existing canonical message refuses.
      await expectAllZero(
        () => stageFanout(
          messageId: messageId,
          snapshot: snapshot,
          candidates: candidatesFor(messageId, snapshot)
            ..removeAt(0)
            ..insert(
              0,
              DirectEventFanoutTargetCandidate(
                recipientPeerId: _contactAccount,
                wireEnvelope: _envelope(messageId, 'cipher-crossed'),
              ),
            ),
          stagedRowOverride: _fanoutStagedRow(
            messageId,
            witnessEnvelope: _envelope(messageId, 'cipher-crossed'),
          ),
        ),
        reason: 'crossed canonical bytes for an owned generation refuse',
      );
    });

    test(
      'TC-361-01b survivor-first replay precedes resolver and capacity and a '
      'terminal generation cannot be reminted',
      () async {
        final snapshot = await seedInitializedFanoutContact();
        expect(
          snapshot.targets.map((target) => target.peerId).toList(),
          const <String>[_deviceTransportA, _deviceTransportB],
          reason: 'revoked legacy target never resurrects',
        );

        const messageId = 'fanout-survivor-1';
        final candidates = candidatesFor(messageId, snapshot);
        final staged = await stageFanout(
          messageId: messageId,
          snapshot: snapshot,
          candidates: candidates,
        );
        expect(staged.outcome, DirectEventFanoutStageOutcome.applied);

        // Byte-exact replay wins BEFORE capacity: a full outbox cannot refuse
        // an already-committed batch.
        final replay = await stageFanout(
          messageId: messageId,
          snapshot: snapshot,
          candidates: candidates,
          capacity: 0,
        );
        expect(replay.outcome, DirectEventFanoutStageOutcome.survivorReplay);
        expect(replay.rows, hasLength(2));

        // Device A transfers to protected custody.
        final completionA = await dbCompleteAcceptedDirectInboxCustodyIfExact(
          db,
          recipientPeerId: _deviceTransportA,
          messageId: messageId,
          expectedIncarnationId: computeDirectEventFanoutIncarnation(
            messageId: messageId,
            recipientPeerId: _deviceTransportA,
          ),
          expectedWireEnvelope: candidates.first.wireEnvelope,
          relayExpiresAt: 1754899200000,
        );
        expect(
          completionA.completed,
          isTrue,
          reason: 'accepted handoff retires the exact sibling',
        );
        expect(
          completionA,
          DirectInboxCustodyCompletionOutcome.messagePreserved,
          reason: 'a surviving sibling forbids the canonical projection',
        );
        expect(
          (await db.query(
            'messages',
            where: 'id = ?',
            whereArgs: const <Object?>[messageId],
          )).single['status'],
          'sending',
        );

        // Roster drifts A/B -> B/C. Replay drains the surviving B row only:
        // no re-resolution, no C append, no A re-creation.
        expect(
          await dbRevokeDirectContactDeviceBinding(
            db,
            contactAccountPeerId: _contactAccount,
            deviceId: 'device-a',
            expectedFingerprint: _fanoutFingerprint('device-a'),
            expectedAccountSigningPublicKey: _fanoutContactPublicKey,
            decidedAt: _t1,
          ),
          isTrue,
        );
        await db.insert(
          'direct_contact_device_bindings',
          _fanoutBindingRow('device-c', _deviceTransportC, 'mlkem-device-c'),
        );
        final drifted = await stageFanout(
          messageId: messageId,
          snapshot: snapshot,
          candidates: candidates,
        );
        expect(drifted.outcome, DirectEventFanoutStageOutcome.survivorReplay);
        expect(drifted.rows, hasLength(1));
        expect(drifted.rows!.single['recipient_peer_id'], _deviceTransportB);
        expect(
          (await dbLoadDirectInboxCustodyOutboxRowsForMessageId(
            db,
            messageId: messageId,
          )).map((row) => row['recipient_peer_id']),
          const <String>[_deviceTransportB],
          reason: 'survivors are the complete pending set: no joined target',
        );

        // The final surviving sibling projects the canonical transition.
        final completionB = await dbCompleteAcceptedDirectInboxCustodyIfExact(
          db,
          recipientPeerId: _deviceTransportB,
          messageId: messageId,
          expectedIncarnationId: computeDirectEventFanoutIncarnation(
            messageId: messageId,
            recipientPeerId: _deviceTransportB,
          ),
          expectedWireEnvelope: candidates[1].wireEnvelope,
          relayExpiresAt: 1754899200000,
        );
        expect(
          completionB,
          DirectInboxCustodyCompletionOutcome.messageAdvanced,
        );
        final projected = (await db.query(
          'messages',
          where: 'id = ?',
          whereArgs: const <Object?>[messageId],
        )).single;
        expect(projected['status'], 'inboxed');
        expect(projected['transport'], 'inbox');
        expect(projected['direct_event_fanout_generation_id'], messageId);

        // Zero survivors + matching generation is terminal, not restageable.
        final terminal = await stageFanout(
          messageId: messageId,
          snapshot: snapshot,
          candidates: candidates,
        );
        expect(terminal.outcome, DirectEventFanoutStageOutcome.terminal);
        expect(
          await dbLoadDirectInboxCustodyOutboxRowsForMessageId(
            db,
            messageId: messageId,
          ),
          isEmpty,
        );

        // An authenticated receipt clears the representative witness only for
        // the exact current generation, and the cleared witness still cannot
        // be reminted.
        final staleReceipt = await dbSettleOutgoingOrdinaryTransport(
          db,
          messageId: messageId,
          expectedContactPeerId: _contactAccount,
          expectedEnvelope: projected['wire_envelope'] as String?,
          status: 'delivered',
          transport: projected['transport'] as String?,
          relayExpiresAt: null,
          mode: OutgoingOrdinarySettlementMode.receipt,
          expectedDirectEventFanoutGenerationId: 'later-generation',
        );
        expect(
          staleReceipt,
          OutgoingOrdinaryMutationOutcome.preserved,
          reason: 'a stale/future event receipt is zero-effect',
        );
        final ignoredReceipt = await dbSettleOutgoingOrdinaryTransport(
          db,
          messageId: messageId,
          expectedContactPeerId: _contactAccount,
          expectedEnvelope: projected['wire_envelope'] as String?,
          status: 'delivered',
          transport: projected['transport'] as String?,
          relayExpiresAt: null,
          mode: OutgoingOrdinarySettlementMode.receipt,
        );
        expect(
          ignoredReceipt,
          OutgoingOrdinaryMutationOutcome.preserved,
          reason: 'a settlement that ignores the generation is zero-effect',
        );
        final receipt = await dbSettleOutgoingOrdinaryTransport(
          db,
          messageId: messageId,
          expectedContactPeerId: _contactAccount,
          expectedEnvelope: projected['wire_envelope'] as String?,
          status: 'delivered',
          transport: projected['transport'] as String?,
          relayExpiresAt: null,
          mode: OutgoingOrdinarySettlementMode.receipt,
          expectedDirectEventFanoutGenerationId: messageId,
        );
        expect(receipt, OutgoingOrdinaryMutationOutcome.applied);
        final delivered = (await db.query(
          'messages',
          where: 'id = ?',
          whereArgs: const <Object?>[messageId],
        )).single;
        expect(delivered['status'], 'delivered');
        expect(delivered['wire_envelope'], isNull);
        expect(
          delivered['direct_event_fanout_generation_id'],
          messageId,
          reason: 'the generation persists through receipt settlement',
        );
        final afterReceipt = await stageFanout(
          messageId: messageId,
          snapshot: snapshot,
          candidates: candidates,
        );
        expect(
          afterReceipt.outcome,
          DirectEventFanoutStageOutcome.terminal,
          reason: 'a receipt-cleared witness is still no-remint authority',
        );
      },
    );

    test('TC-361-01b completion reconstructs the logical tombstone and the '
        'delete owner preserves the scrubbed generation witness', () async {
      final snapshot = await seedInitializedFanoutContact();

      // Physical parent removal before completion: any sibling rebuilds the
      // scrubbed hidden tombstone against the LOGICAL contact.
      const removedId = 'fanout-removed-parent';
      final removedCandidates = candidatesFor(removedId, snapshot);
      expect(
        (await stageFanout(
          messageId: removedId,
          snapshot: snapshot,
          candidates: removedCandidates,
        )).outcome,
        DirectEventFanoutStageOutcome.applied,
      );
      await db.delete(
        'messages',
        where: 'id = ?',
        whereArgs: const <Object?>[removedId],
      );
      final reconstructed = await dbCompleteAcceptedDirectInboxCustodyIfExact(
        db,
        recipientPeerId: _deviceTransportA,
        messageId: removedId,
        expectedIncarnationId: computeDirectEventFanoutIncarnation(
          messageId: removedId,
          recipientPeerId: _deviceTransportA,
        ),
        expectedWireEnvelope: removedCandidates.first.wireEnvelope,
        relayExpiresAt: 1754899200000,
      );
      expect(reconstructed, DirectInboxCustodyCompletionOutcome.messageRemoved);
      final tombstone = (await db.query(
        'messages',
        where: 'id = ?',
        whereArgs: const <Object?>[removedId],
      )).single;
      expect(
        tombstone['contact_peer_id'],
        _contactAccount,
        reason:
            'the tombstone owner is the logical contact, never the '
            'delivery transport',
      );
      expect(tombstone['hidden_at'], isNotNull);
      expect(tombstone['text'], '');
      expect(tombstone['wire_envelope'], isNull);
      expect(tombstone['direct_event_fanout_generation_id'], removedId);
      // The second sibling converges on the same tombstone.
      final second = await dbCompleteAcceptedDirectInboxCustodyIfExact(
        db,
        recipientPeerId: _deviceTransportB,
        messageId: removedId,
        expectedIncarnationId: computeDirectEventFanoutIncarnation(
          messageId: removedId,
          recipientPeerId: _deviceTransportB,
        ),
        expectedWireEnvelope: removedCandidates[1].wireEnvelope,
        relayExpiresAt: 1754899200000,
      );
      expect(second, DirectInboxCustodyCompletionOutcome.messagePreserved);
      expect(
        await dbLoadDirectInboxCustodyOutboxRowsForMessageId(
          db,
          messageId: removedId,
        ),
        isEmpty,
      );

      // All-complete then delete-for-me: the delete owner sweeps reactions,
      // scrubs and hides, and preserves id/logical contact/generation.
      const completedId = 'fanout-completed-then-deleted';
      final completedCandidates = candidatesFor(completedId, snapshot);
      expect(
        (await stageFanout(
          messageId: completedId,
          snapshot: snapshot,
          candidates: completedCandidates,
        )).outcome,
        DirectEventFanoutStageOutcome.applied,
      );
      for (final candidate in completedCandidates) {
        await dbCompleteAcceptedDirectInboxCustodyIfExact(
          db,
          recipientPeerId: candidate.recipientPeerId,
          messageId: completedId,
          expectedIncarnationId: computeDirectEventFanoutIncarnation(
            messageId: completedId,
            recipientPeerId: candidate.recipientPeerId,
          ),
          expectedWireEnvelope: candidate.wireEnvelope,
          relayExpiresAt: 1754899200000,
        );
      }
      await db.insert('message_reactions', <String, Object?>{
        'id': 'reaction-on-deleted',
        'message_id': completedId,
        'emoji': '👍',
        'sender_peer_id': _contactAccount,
        'timestamp': _t1,
        'created_at': _t1,
      });
      expect(await dbDeleteMessage(db, completedId), 1);
      expect(
        await db.query(
          'message_reactions',
          where: 'message_id = ?',
          whereArgs: const <Object?>[completedId],
        ),
        isEmpty,
        reason: 'single-message delete sweeps reactions before the scrub',
      );
      final scrubbed = (await db.query(
        'messages',
        where: 'id = ?',
        whereArgs: const <Object?>[completedId],
      )).single;
      expect(scrubbed['text'], '');
      expect(scrubbed['wire_envelope'], isNull);
      expect(scrubbed['hidden_at'], isNotNull);
      expect(scrubbed['contact_peer_id'], _contactAccount);
      expect(
        scrubbed['direct_event_fanout_generation_id'],
        completedId,
        reason: 'delete-for-me must preserve the only no-remint fact',
      );
      final replay = await stageFanout(
        messageId: completedId,
        snapshot: snapshot,
        candidates: completedCandidates,
      );
      expect(
        replay.outcome,
        DirectEventFanoutStageOutcome.terminal,
        reason: 'exact same-generation replay after delete is zero-effect',
      );
      expect(
        await dbLoadDirectInboxCustodyOutboxRowsForMessageId(
          db,
          messageId: completedId,
        ),
        isEmpty,
      );

      // A legacy unmarked row keeps the incumbent physical delete.
      final legacy = _message(
        'legacy-physical-delete',
        envelope: _envelope('legacy-physical-delete', 'cipher-legacy'),
      );
      await dbInsertMessage(db, legacy.toMap());
      expect(await dbDeleteMessage(db, legacy.id), 1);
      expect(
        await db.query(
          'messages',
          where: 'id = ?',
          whereArgs: <Object?>[legacy.id],
        ),
        isEmpty,
        reason: 'unmarked rows keep the incumbent physical delete',
      );
    });

    test('TC-361-01b generic single-owner wrappers fail closed on marked '
        'generations', () async {
      final snapshot = await seedInitializedFanoutContact();
      const messageId = 'fanout-single-owner-guard';
      final candidates = candidatesFor(messageId, snapshot);
      expect(
        (await stageFanout(
          messageId: messageId,
          snapshot: snapshot,
          candidates: candidates,
        )).outcome,
        DirectEventFanoutStageOutcome.applied,
      );

      // The generic single-owner loader may never select an arbitrary
      // sibling of a fanout generation — plural and single-marked alike.
      await expectLater(
        dbLoadDirectInboxCustodyOutboxOwnerForMessageId(
          db,
          messageId: messageId,
        ),
        throwsA(isA<StateError>()),
      );
      await dbCompleteAcceptedDirectInboxCustodyIfExact(
        db,
        recipientPeerId: _deviceTransportA,
        messageId: messageId,
        expectedIncarnationId: computeDirectEventFanoutIncarnation(
          messageId: messageId,
          recipientPeerId: _deviceTransportA,
        ),
        expectedWireEnvelope: candidates.first.wireEnvelope,
        relayExpiresAt: 1754899200000,
      );
      await expectLater(
        dbLoadDirectInboxCustodyOutboxOwnerForMessageId(
          db,
          messageId: messageId,
        ),
        throwsA(isA<StateError>()),
        reason: 'one surviving marked sibling is still fanout-owned',
      );

      // The custody verifier and unacked-rebuild loaders never select a
      // marked generation: they could only re-store the canonical witness
      // to the logical contact.
      await db.update(
        'messages',
        const <String, Object?>{'status': 'inboxed', 'transport': 'inbox'},
        where: 'id = ?',
        whereArgs: const <Object?>[messageId],
      );
      final legacyInboxed = _message(
        'legacy-inboxed-owner',
        envelope: _envelope('legacy-inboxed-owner', 'cipher-owner'),
      );
      await dbInsertMessage(db, legacyInboxed.toMap());
      await db.update(
        'messages',
        const <String, Object?>{'status': 'inboxed', 'transport': 'inbox'},
        where: 'id = ?',
        whereArgs: <Object?>[legacyInboxed.id],
      );
      expect(
        (await dbLoadInboxCustodyOutgoingMessages(
          db,
          recheckOlderThan: Duration.zero,
        )).map((row) => row['id']),
        <Object?>[legacyInboxed.id],
        reason: 'the verifier sweep must skip marked generations',
      );

      await db.update(
        'messages',
        <String, Object?>{'status': 'sent', 'timestamp': _t0},
        where: 'id = ?',
        whereArgs: const <Object?>[messageId],
      );
      await db.update(
        'messages',
        <String, Object?>{'status': 'sent', 'timestamp': _t0},
        where: 'id = ?',
        whereArgs: <Object?>[legacyInboxed.id],
      );
      expect(
        (await dbLoadUnackedOutgoingMessages(
          db,
          olderThan: DateTime.parse(_t1),
        )).map((row) => row['id']),
        <Object?>[legacyInboxed.id],
        reason: 'the unacked rebuild must skip marked generations',
      );
    });
  });

  group('TC-362-02b media fanout exact-target v108 completion', () {
    test('TC-362-02b exact-target completion converges one target and only '
        'the final sibling projects', () async {
      const messageId = 'tc362-media-fanout-completion';
      const attachmentId = '$messageId-a';
      const contentHash =
          '3333333333333333333333333333333333333333333333333333333333333333';
      const ciphertextSize = 96;
      const targets = <String>[_deviceTransportA, _deviceTransportB];
      const expiryByTarget = <String, int>{
        _deviceTransportA: 1900000060000,
        _deviceTransportB: 1900000120000,
      };
      String envelopeFor(String target) =>
          _envelope(messageId, 'cipher-for-$target');
      String incarnationFor(String target) =>
          computeDirectEventFanoutIncarnation(
            messageId: messageId,
            recipientPeerId: target,
          );

      // Canonical parent: generation marker + the FIRST target's envelope as
      // the correlation-only witness (raw seed, mirroring the Plan-361 fanout
      // completion fixtures).
      await db.insert(
        'messages',
        _fanoutStagedRow(
          messageId,
          witnessEnvelope: envelopeFor(_deviceTransportA),
        ),
      );
      // One shared canonical attachment (fingerprint target of the stamp).
      await dbInsertMediaAttachment(db, <String, Object?>{
        'id': attachmentId,
        'message_id': messageId,
        'owner_lane': 'direct',
        'mime': 'image/jpeg',
        'size': 900,
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
      // Per-target v114 rows: stored + bound to that target's OWN exact v108
      // incarnation, with a per-target expiry.
      for (final target in targets) {
        await db.insert(
          kDirectMediaBlobCustodyTable,
          DirectMediaBlobCustodyRow(
            attachmentId: attachmentId,
            messageId: messageId,
            direction: DirectMediaBlobCustodyDirection.outgoing,
            state: DirectMediaBlobCustodyState.outgoingStored,
            inboxCustodyIncarnationId: incarnationFor(target),
            recipientPeerId: target,
            contactAccountPeerId: _contactAccount,
            recipientMlKemPublicKey: 'mlkem-for-$target',
            ciphertextRelativePath:
                'direct_media_blob_custody_v1/$contentHash/$attachmentId.blob',
            contentHash: contentHash,
            ciphertextSize: ciphertextSize,
            expiresAtMs: expiryByTarget[target],
            custodyRelayPeerId: 'peer-relay',
            lastAttemptAt: null,
            nextAttemptAt: null,
            createdAt: _t0,
            updatedAt: _t0,
          ).toMap(),
        );
        // The v108 sibling binds ONLY this target's manifest/expiry.
        final manifest = <DirectMediaBlobManifestProjection>[
          DirectMediaBlobManifestProjection(
            attachmentId: attachmentId,
            commitment: DirectMediaBlobCustodyCommitment(
              contentHash: contentHash,
              ciphertextSize: ciphertextSize,
              expiresAtMs: expiryByTarget[target]!,
            ),
          ),
        ];
        await db.insert(_fanoutTable, <String, Object?>{
          'recipient_peer_id': target,
          'message_id': messageId,
          'incarnation_id': incarnationFor(target),
          'wire_envelope': envelopeFor(target),
          'retry_count': 0,
          'last_attempt_at': null,
          'last_error_code': null,
          'media_blob_manifest_hash': computeDirectMediaBlobManifestHash(
            manifest,
          ),
          'media_blob_expires_at_ms': earliestDirectMediaBlobExpiryMs(manifest),
          'contact_account_peer_id': _contactAccount,
          'created_at': _t0,
          'updated_at': _t0,
        });
      }

      Future<Map<String, Object?>> attachmentRow() async => (await db.query(
        'media_attachments',
        where: 'id = ?',
        whereArgs: const <Object?>[attachmentId],
      )).single;
      Future<List<Map<String, Object?>>> v114RowsFor(String target) => db.query(
        kDirectMediaBlobCustodyTable,
        where: 'message_id = ? AND recipient_peer_id = ?',
        whereArgs: <Object?>[messageId, target],
        orderBy: 'attachment_id ASC',
      );

      final expectedFingerprint = computeDirectMediaBlobGenerationFingerprintV2(
        attachmentId: attachmentId,
        contentHash: contentHash,
        ciphertextSize: ciphertextSize,
      );
      final siblingBRowsBefore = await v114RowsFor(_deviceTransportB);

      // Target A converges first: nonfinal, so the canonical message is
      // preserved untouched while A's exact rows retire.
      final completionA = await dbCompleteAcceptedDirectInboxCustodyIfExact(
        db,
        recipientPeerId: _deviceTransportA,
        messageId: messageId,
        expectedIncarnationId: incarnationFor(_deviceTransportA),
        expectedWireEnvelope: envelopeFor(_deviceTransportA),
        relayExpiresAt: expiryByTarget[_deviceTransportA]! - 1,
      );
      expect(
        completionA,
        DirectInboxCustodyCompletionOutcome.messagePreserved,
        reason: 'a surviving sibling forbids the canonical projection',
      );
      final afterA = (await db.query(
        'messages',
        where: 'id = ?',
        whereArgs: const <Object?>[messageId],
      )).single;
      expect(afterA['status'], 'sending');
      expect(afterA['direct_event_fanout_generation_id'], messageId);
      expect(
        (await v114RowsFor(
          _deviceTransportA,
        )).map((row) => row['state']).toList(),
        const <String>['outgoing_cleanup_pending'],
        reason: "only A's OWN v111 rows transition to cleanup",
      );
      expect(
        await v114RowsFor(_deviceTransportB),
        siblingBRowsBefore,
        reason: "B's v111 rows are byte-identical after A's completion",
      );
      final stampedAfterA = await attachmentRow();
      expect(
        stampedAfterA['direct_media_blob_custody_fingerprint'],
        expectedFingerprint,
        reason:
            'the first accepted target stamps the target-INDEPENDENT '
            'v2 generation digest',
      );
      expect(
        (stampedAfterA['direct_media_blob_custody_fingerprint_version'] as num)
            .toInt(),
        kDirectMediaBlobFingerprintVersionGeneration,
      );
      expect(
        (await dbLoadDirectInboxCustodyOutboxRowsForMessageId(
          db,
          messageId: messageId,
        )).map((row) => row['recipient_peer_id']),
        const <String>[_deviceTransportB],
        reason: 'exactly the exact A sibling retired',
      );

      // Target B is the FINAL surviving sibling: the canonical transition
      // projects and the persisted lineage must agree byte-for-byte.
      final completionB = await dbCompleteAcceptedDirectInboxCustodyIfExact(
        db,
        recipientPeerId: _deviceTransportB,
        messageId: messageId,
        expectedIncarnationId: incarnationFor(_deviceTransportB),
        expectedWireEnvelope: envelopeFor(_deviceTransportB),
        relayExpiresAt: expiryByTarget[_deviceTransportB]! - 1,
      );
      expect(completionB, DirectInboxCustodyCompletionOutcome.messageAdvanced);
      final afterB = (await db.query(
        'messages',
        where: 'id = ?',
        whereArgs: const <Object?>[messageId],
      )).single;
      expect(afterB['status'], 'inboxed');
      expect(afterB['transport'], 'inbox');
      expect(
        afterB['relay_expires_at'],
        expiryByTarget[_deviceTransportB]! - 1,
      );
      expect(afterB['direct_event_fanout_generation_id'], messageId);
      final stampedAfterB = await attachmentRow();
      expect(
        stampedAfterB['direct_media_blob_custody_fingerprint'],
        expectedFingerprint,
        reason:
            'the later target must AGREE with the stamped generation '
            'digest, never rewrite it',
      );
      expect(
        (stampedAfterB['direct_media_blob_custody_fingerprint_version'] as num)
            .toInt(),
        kDirectMediaBlobFingerprintVersionGeneration,
      );
      expect(
        (await v114RowsFor(
          _deviceTransportB,
        )).map((row) => row['state']).toList(),
        const <String>['outgoing_cleanup_pending'],
      );
      expect(
        await dbLoadDirectInboxCustodyOutboxRowsForMessageId(
          db,
          messageId: messageId,
        ),
        isEmpty,
        reason: 'zero surviving siblings after the final completion',
      );
    });
  });
}

const String _fanoutTable = 'direct_inbox_custody_outbox';
const String _contactAccount = 'peer-contact-account';
const String _secondAccount = 'peer-second-account';
const String _deviceTransportA = 'peer-device-transport-a';
const String _deviceTransportB = 'peer-device-transport-b';
const String _deviceTransportC = 'peer-device-transport-c';
const String _fanoutContactPublicKey = 'contact-account-signing-key';

Map<String, Object?> _fanoutContactRow({String peerId = _contactAccount}) =>
    <String, Object?>{
      'peer_id': peerId,
      'public_key': _fanoutContactPublicKey,
      'rendezvous': '/dns4/relay.example.com/tcp/443/wss/p2p/relay-id',
      'username': 'Fanout Contact',
      'signature': 'sig-base64',
      'scanned_at': _t0,
      'ml_kem_public_key': 'legacy-mlkem',
    };

Map<String, Object?> _fanoutRosterMetadataRow({required bool legacyRevoked}) =>
    <String, Object?>{
      'contact_account_peer_id': _contactAccount,
      'roster_initialized': 1,
      'legacy_target_state': legacyRevoked ? 'revoked' : 'active',
      'initialized_at': _t0,
      'legacy_revoked_at': legacyRevoked ? _t0 : null,
      'updated_at': _t0,
    };

String _fanoutFingerprint(String deviceId) =>
    deviceId.hashCode.toUnsigned(16).toRadixString(16).padLeft(4, '0') * 16;

Map<String, Object?> _fanoutBindingRow(
  String deviceId,
  String transportPeerId,
  String mlKemPublicKey,
) => <String, Object?>{
  'contact_account_peer_id': _contactAccount,
  'device_id': deviceId,
  'verified_account_signing_public_key': _fanoutContactPublicKey,
  'transport_peer_id': transportPeerId,
  'transport_public_key': 'transport-key-$deviceId',
  'device_ml_kem_public_key': mlKemPublicKey,
  'binding_fingerprint': _fanoutFingerprint(deviceId),
  'state': 'active',
  'staged_at': _t0,
  'decided_at': _t0,
};

Map<String, Object?> _fanoutStagedRow(
  String messageId, {
  required String witnessEnvelope,
  String contactPeerId = _contactAccount,
}) => <String, Object?>{
  ..._message(
    messageId,
    envelope: witnessEnvelope,
  ).copyWith(contactPeerId: contactPeerId).toMap(),
  'direct_event_fanout_generation_id': messageId,
};

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
