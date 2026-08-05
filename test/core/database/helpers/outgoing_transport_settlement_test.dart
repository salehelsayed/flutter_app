import 'package:flutter_app/core/database/app_database_version.dart';
import 'package:flutter_app/core/database/helpers/messages_db_helpers.dart';
import 'package:flutter_app/core/database/outgoing_transport_mutation.dart';
import 'package:flutter_app/core/database/production_migration_registry.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database db;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await openDatabase(inMemoryDatabasePath, version: 1);
    await runProductionOnCreate(db, currentIdentityDatabaseVersion);
  });

  tearDown(() => db.close());

  Map<String, Object?> messageRow({
    required String id,
    String contactPeerId = 'peer-a',
    String senderPeerId = 'self-peer',
    String text = 'payload',
    String status = 'sending',
    int isIncoming = 0,
    String? editedAt,
    String? deletedAt,
    String? deletedByPeerId,
    String? hiddenAt,
    String? transport,
    String? wireEnvelope = 'envelope-a',
    int? relayExpiresAt,
    String? custodyCheckedAt,
    int policyVersion = 0,
    String policyMode = 'ordinary',
  }) {
    final timestamp = '2026-08-05T12:00:00.000Z';
    final private = policyVersion > 0 && policyMode != 'unsupported';
    return <String, Object?>{
      'id': id,
      'contact_peer_id': contactPeerId,
      'sender_peer_id': senderPeerId,
      'text': text,
      'timestamp': timestamp,
      'status': status,
      'is_incoming': isIncoming,
      'created_at': timestamp,
      'edited_at': editedAt,
      'read_at': null,
      'quoted_message_id': null,
      'deleted_at': deletedAt,
      'deleted_by_peer_id': deletedByPeerId,
      'hidden_at': hiddenAt,
      'transport': transport,
      'wire_envelope': wireEnvelope,
      'relay_expires_at': relayExpiresAt,
      'custody_checked_at': custodyCheckedAt,
      'dedup_key': id,
      'is_forwarded': 0,
      'private_media_policy_version': policyVersion,
      'private_media_mode': policyMode,
      'private_media_duration_seconds': policyMode == 'disappearing'
          ? 3600
          : null,
      'private_media_state': private ? 'available' : 'none',
      'private_media_received_at_ms': null,
      'private_media_expires_at_ms': null,
      'private_media_revealed_at_ms': null,
      'private_media_terminal_at_ms': null,
      'private_media_clock_high_water_ms': null,
    };
  }

  Map<String, Object?> attachmentRow({
    required String id,
    required String messageId,
  }) => <String, Object?>{
    'id': id,
    'message_id': messageId,
    'owner_lane': MediaOwnerLane.direct.dbValue,
    'mime': 'image/jpeg',
    'size': 128,
    'media_type': 'image',
    'width': 16,
    'height': 16,
    'duration_ms': null,
    'local_path': 'pending_uploads/$messageId/$id.jpg',
    'download_status': 'upload_pending',
    'created_at': '2026-08-05T12:00:00.000Z',
    'content_hash': null,
    'thumbnail_hash': null,
    'encryption_key_base64': null,
    'encryption_nonce': null,
    'encryption_scheme': null,
  };

  Future<Map<String, Object?>> loadMessage(String id) async {
    final rows = await db.query(
      'messages',
      where: 'id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    expect(rows, hasLength(1), reason: 'expected durable message $id');
    return Map<String, Object?>.from(rows.single);
  }

  Future<Map<String, Object?>> insertMessage(Map<String, Object?> row) async {
    await db.insert('messages', row);
    return loadMessage(row['id']! as String);
  }

  Future<Map<String, Object?>?> maybeLoadMessage(String id) async {
    final rows = await db.query(
      'messages',
      where: 'id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    return rows.isEmpty ? null : Map<String, Object?>.from(rows.single);
  }

  Future<Map<String, Object?>> loadAttachment(String id) async {
    final rows = await db.query(
      'media_attachments',
      where: 'id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    expect(rows, hasLength(1), reason: 'expected durable attachment $id');
    return Map<String, Object?>.from(rows.single);
  }

  ({String? transport, int? relayExpiresAt}) candidateFields(String status) {
    return switch (status) {
      'delivered' => (transport: 'direct', relayExpiresAt: null),
      'inboxed' => (transport: 'inbox', relayExpiresAt: 900001),
      'sent' => (transport: 'wifi', relayExpiresAt: null),
      'failed' => (transport: null, relayExpiresAt: null),
      _ => throw ArgumentError.value(status),
    };
  }

  test(
    'normal settlement enforces the explicit predecessor table without a total rank',
    () async {
      const candidates = <String>{'delivered', 'inboxed', 'sent', 'failed'};
      const predecessors = <String>{
        'sending',
        'sent',
        'inboxed',
        'failed',
        'delivered',
      };
      const allowed = <String, Set<String>>{
        'delivered': <String>{'sending', 'sent', 'inboxed', 'failed'},
        'inboxed': <String>{'sending', 'sent', 'failed'},
        'sent': <String>{'sending', 'failed'},
        'failed': <String>{'sending'},
      };

      for (final candidate in candidates) {
        for (final predecessor in predecessors) {
          final id = 'table-$candidate-from-$predecessor';
          const envelope = 'table-envelope';
          final currentTransport = switch (predecessor) {
            'sent' => 'relay',
            'inboxed' => 'inbox',
            'delivered' => 'local',
            _ => null,
          };
          final before = await insertMessage(
            messageRow(
              id: id,
              status: predecessor,
              transport: currentTransport,
              wireEnvelope: predecessor == 'delivered' ? null : envelope,
              relayExpiresAt: predecessor == 'inboxed' ? 700001 : null,
              custodyCheckedAt: predecessor == 'delivered'
                  ? null
                  : '2026-08-05T12:01:00.000Z',
            ),
          );
          final fields = candidateFields(candidate);

          final outcome = await dbSettleOutgoingOrdinaryTransport(
            db,
            messageId: id,
            expectedContactPeerId: 'peer-a',
            expectedEnvelope: envelope,
            status: candidate,
            transport: fields.transport,
            relayExpiresAt: fields.relayExpiresAt,
            mode: OutgoingOrdinarySettlementMode.live,
          );

          if (candidate == predecessor) {
            expect(
              outcome,
              OutgoingOrdinaryMutationOutcome.idempotent,
              reason: '$predecessor -> $candidate must be a no-op',
            );
            expect(await loadMessage(id), before);
          } else if (allowed[candidate]!.contains(predecessor)) {
            expect(
              outcome,
              OutgoingOrdinaryMutationOutcome.applied,
              reason: '$predecessor -> $candidate must be accepted',
            );
            final expected = Map<String, Object?>.from(before)
              ..['status'] = candidate
              ..['transport'] = fields.transport
              ..['wire_envelope'] = candidate == 'delivered' ? null : envelope
              ..['relay_expires_at'] = fields.relayExpiresAt
              ..['custody_checked_at'] = null;
            expect(await loadMessage(id), expected);
          } else {
            expect(
              outcome,
              OutgoingOrdinaryMutationOutcome.preserved,
              reason: '$predecessor -> $candidate must be refused',
            );
            expect(await loadMessage(id), before);
          }
        }
      }

      final sameSent = await insertMessage(
        messageRow(
          id: 'same-sent-envelope',
          status: 'sent',
          transport: 'wifi',
          wireEnvelope: 'current-envelope',
        ),
      );
      expect(
        await dbSettleOutgoingOrdinaryTransport(
          db,
          messageId: 'same-sent-envelope',
          expectedContactPeerId: 'peer-a',
          expectedEnvelope: 'wrong-envelope',
          status: 'sent',
          transport: 'direct',
          relayExpiresAt: null,
          mode: OutgoingOrdinarySettlementMode.live,
        ),
        OutgoingOrdinaryMutationOutcome.preserved,
      );
      expect(await loadMessage('same-sent-envelope'), sameSent);

      final sameInboxed = await insertMessage(
        messageRow(
          id: 'same-inboxed-envelope',
          status: 'inboxed',
          transport: 'inbox',
          wireEnvelope: 'current-inboxed-envelope',
          relayExpiresAt: 700002,
          custodyCheckedAt: '2026-08-05T12:01:30.000Z',
        ),
      );
      expect(
        await dbSettleOutgoingOrdinaryTransport(
          db,
          messageId: 'same-inboxed-envelope',
          expectedContactPeerId: 'peer-a',
          expectedEnvelope: 'wrong-inboxed-envelope',
          status: 'inboxed',
          transport: 'inbox',
          relayExpiresAt: 700002,
          mode: OutgoingOrdinarySettlementMode.live,
        ),
        OutgoingOrdinaryMutationOutcome.preserved,
      );
      expect(await loadMessage('same-inboxed-envelope'), sameInboxed);

      final receiptSending = await insertMessage(
        messageRow(id: 'receipt-sending', wireEnvelope: 'receipt-envelope'),
      );
      expect(
        await dbSettleOutgoingOrdinaryTransport(
          db,
          messageId: 'receipt-sending',
          expectedContactPeerId: 'peer-a',
          expectedEnvelope: 'receipt-envelope',
          status: 'delivered',
          transport: 'direct',
          relayExpiresAt: null,
          mode: OutgoingOrdinarySettlementMode.receipt,
        ),
        OutgoingOrdinaryMutationOutcome.preserved,
      );
      expect(await loadMessage('receipt-sending'), receiptSending);

      await insertMessage(
        messageRow(
          id: 'legacy-receipt',
          status: 'failed',
          transport: null,
          wireEnvelope: null,
        ),
      );
      expect(
        await dbSettleOutgoingOrdinaryTransport(
          db,
          messageId: 'legacy-receipt',
          expectedContactPeerId: 'peer-a',
          expectedEnvelope: null,
          status: 'delivered',
          transport: null,
          relayExpiresAt: null,
          mode: OutgoingOrdinarySettlementMode.receipt,
        ),
        OutgoingOrdinaryMutationOutcome.applied,
      );
      final legacyDelivered = await loadMessage('legacy-receipt');
      expect(legacyDelivered['status'], 'delivered');
      expect(legacyDelivered['transport'], isNull);
      expect(legacyDelivered['wire_envelope'], isNull);
    },
  );

  test(
    'first delivered result owns fields across both callback orders',
    () async {
      await insertMessage(
        messageRow(
          id: 'delivered-first',
          wireEnvelope: 'delivered-first-envelope',
          custodyCheckedAt: '2026-08-05T12:01:00.000Z',
        ),
      );
      expect(
        await dbSettleOutgoingOrdinaryTransport(
          db,
          messageId: 'delivered-first',
          expectedContactPeerId: 'peer-a',
          expectedEnvelope: 'delivered-first-envelope',
          status: 'delivered',
          transport: 'direct',
          relayExpiresAt: null,
          mode: OutgoingOrdinarySettlementMode.live,
        ),
        OutgoingOrdinaryMutationOutcome.applied,
      );
      final deliveredFirst = await loadMessage('delivered-first');
      expect(deliveredFirst['wire_envelope'], isNull);
      expect(deliveredFirst['relay_expires_at'], isNull);
      expect(deliveredFirst['custody_checked_at'], isNull);

      expect(
        await dbSettleOutgoingOrdinaryTransport(
          db,
          messageId: 'delivered-first',
          expectedContactPeerId: 'peer-a',
          expectedEnvelope: 'delivered-first-envelope',
          status: 'inboxed',
          transport: 'inbox',
          relayExpiresAt: 123456,
          mode: OutgoingOrdinarySettlementMode.live,
        ),
        OutgoingOrdinaryMutationOutcome.preserved,
      );
      expect(await loadMessage('delivered-first'), deliveredFirst);

      await insertMessage(
        messageRow(id: 'inboxed-first', wireEnvelope: 'inboxed-envelope'),
      );
      expect(
        await dbSettleOutgoingOrdinaryTransport(
          db,
          messageId: 'inboxed-first',
          expectedContactPeerId: 'peer-a',
          expectedEnvelope: 'inboxed-envelope',
          status: 'inboxed',
          transport: 'inbox',
          relayExpiresAt: 654321,
          mode: OutgoingOrdinarySettlementMode.live,
        ),
        OutgoingOrdinaryMutationOutcome.applied,
      );
      expect(
        await dbSettleOutgoingOrdinaryTransport(
          db,
          messageId: 'inboxed-first',
          expectedContactPeerId: 'peer-a',
          expectedEnvelope: 'inboxed-envelope',
          status: 'delivered',
          transport: 'wifi',
          relayExpiresAt: null,
          mode: OutgoingOrdinarySettlementMode.live,
        ),
        OutgoingOrdinaryMutationOutcome.applied,
      );
      final inboxedThenDelivered = await loadMessage('inboxed-first');
      expect(inboxedThenDelivered['status'], 'delivered');
      expect(inboxedThenDelivered['transport'], 'wifi');
      expect(inboxedThenDelivered['wire_envelope'], isNull);
      expect(inboxedThenDelivered['relay_expires_at'], isNull);

      expect(
        await dbSettleOutgoingOrdinaryTransport(
          db,
          messageId: 'inboxed-first',
          expectedContactPeerId: 'peer-a',
          expectedEnvelope: 'obsolete-envelope',
          status: 'delivered',
          transport: 'relay',
          relayExpiresAt: null,
          mode: OutgoingOrdinarySettlementMode.live,
        ),
        OutgoingOrdinaryMutationOutcome.idempotent,
      );
      expect(await loadMessage('inboxed-first'), inboxedThenDelivered);
    },
  );

  test(
    'normal settlement binds identity policy and exact field shapes',
    () async {
      final ordinaryBefore = await insertMessage(
        messageRow(id: 'ordinary-negative', wireEnvelope: 'ordinary-envelope'),
      );

      Future<void> expectNoMutation(
        Future<OutgoingOrdinaryMutationOutcome> mutation, {
        OutgoingOrdinaryMutationOutcome? outcome,
      }) async {
        final result = await mutation;
        if (outcome != null) {
          expect(result, outcome);
        } else {
          expect(result, isNot(OutgoingOrdinaryMutationOutcome.applied));
        }
        expect(await loadMessage('ordinary-negative'), ordinaryBefore);
      }

      await expectNoMutation(
        dbSettleOutgoingOrdinaryTransport(
          db,
          messageId: 'ordinary-negative',
          expectedContactPeerId: 'wrong-peer',
          expectedEnvelope: 'ordinary-envelope',
          status: 'sent',
          transport: 'wifi',
          relayExpiresAt: null,
          mode: OutgoingOrdinarySettlementMode.live,
        ),
        outcome: OutgoingOrdinaryMutationOutcome.refused,
      );
      await expectNoMutation(
        dbSettleOutgoingOrdinaryTransport(
          db,
          messageId: 'ordinary-negative',
          expectedContactPeerId: 'peer-a',
          expectedEnvelope: 'crossed-envelope',
          status: 'sent',
          transport: 'wifi',
          relayExpiresAt: null,
          mode: OutgoingOrdinarySettlementMode.live,
        ),
      );

      for (final invalidEnvelope in <String?>[null, '']) {
        await expectNoMutation(
          dbSettleOutgoingOrdinaryTransport(
            db,
            messageId: 'ordinary-negative',
            expectedContactPeerId: 'peer-a',
            expectedEnvelope: invalidEnvelope,
            status: 'sent',
            transport: 'wifi',
            relayExpiresAt: null,
            mode: OutgoingOrdinarySettlementMode.live,
          ),
          outcome: OutgoingOrdinaryMutationOutcome.refused,
        );
      }

      final invalidCandidates =
          <({String status, String? transport, int? expiry})>[
            (status: 'unknown', transport: 'wifi', expiry: null),
            (status: 'sent', transport: 'telepathy', expiry: null),
            (status: 'inboxed', transport: 'direct', expiry: null),
            (status: 'inboxed', transport: null, expiry: null),
            (status: 'sent', transport: null, expiry: null),
            (status: 'sent', transport: 'wifi', expiry: 1),
            (status: 'failed', transport: 'inbox', expiry: null),
            (status: 'failed', transport: null, expiry: 1),
            (status: 'delivered', transport: null, expiry: null),
            (status: 'delivered', transport: 'direct', expiry: 1),
            (status: 'inboxed', transport: 'inbox', expiry: 0),
            (status: 'inboxed', transport: 'inbox', expiry: -1),
          ];
      for (final candidate in invalidCandidates) {
        await expectNoMutation(
          dbSettleOutgoingOrdinaryTransport(
            db,
            messageId: 'ordinary-negative',
            expectedContactPeerId: 'peer-a',
            expectedEnvelope: 'ordinary-envelope',
            status: candidate.status,
            transport: candidate.transport,
            relayExpiresAt: candidate.expiry,
            mode: OutgoingOrdinarySettlementMode.live,
          ),
          outcome: OutgoingOrdinaryMutationOutcome.refused,
        );
      }

      final malformedDelivered = await insertMessage(
        messageRow(
          id: 'malformed-delivered-row',
          status: 'delivered',
          transport: 'direct',
          wireEnvelope: null,
          custodyCheckedAt: '2026-08-05T12:03:00.000Z',
        ),
      );
      expect(
        await dbSettleOutgoingOrdinaryTransport(
          db,
          messageId: 'malformed-delivered-row',
          expectedContactPeerId: 'peer-a',
          expectedEnvelope: 'obsolete-envelope',
          status: 'delivered',
          transport: 'relay',
          relayExpiresAt: null,
          mode: OutgoingOrdinarySettlementMode.live,
        ),
        OutgoingOrdinaryMutationOutcome.refused,
        reason: 'duplicate delivery still validates its durable row shape',
      );
      expect(await loadMessage('malformed-delivered-row'), malformedDelivered);

      final forbiddenRows = <Map<String, Object?>>[
        messageRow(id: 'incoming-row', isIncoming: 1, senderPeerId: 'peer-a'),
        messageRow(id: 'hidden-row', hiddenAt: '2026-08-05T12:02:00.000Z'),
        messageRow(
          id: 'deleted-row',
          text: '',
          deletedAt: '2026-08-05T12:02:00.000Z',
          deletedByPeerId: 'self-peer',
        ),
        messageRow(id: 'dangling-deleter-row', deletedByPeerId: 'self-peer'),
        messageRow(
          id: 'protected-row',
          policyVersion: 1,
          policyMode: 'protected',
        ),
        messageRow(
          id: 'view-once-row',
          policyVersion: 1,
          policyMode: 'view_once',
        ),
        messageRow(
          id: 'future-row',
          policyVersion: 2,
          policyMode: 'unsupported',
        ),
      ];
      for (final row in forbiddenRows) {
        final id = row['id']! as String;
        final before = await insertMessage(row);
        final outcome = await dbSettleOutgoingOrdinaryTransport(
          db,
          messageId: id,
          expectedContactPeerId: 'peer-a',
          expectedEnvelope: 'envelope-a',
          status: 'sent',
          transport: 'wifi',
          relayExpiresAt: null,
          mode: OutgoingOrdinarySettlementMode.live,
        );
        expect(outcome, isNot(OutgoingOrdinaryMutationOutcome.applied));
        expect(await loadMessage(id), before);
      }

      for (final policy in const <({int version, String mode})>[
        (version: 0, mode: 'ordinary'),
        (version: 1, mode: 'disappearing'),
      ]) {
        final id = 'eligible-${policy.mode}';
        await insertMessage(
          messageRow(
            id: id,
            policyVersion: policy.version,
            policyMode: policy.mode,
          ),
        );
        expect(
          await dbSettleOutgoingOrdinaryTransport(
            db,
            messageId: id,
            expectedContactPeerId: 'peer-a',
            expectedEnvelope: 'envelope-a',
            status: 'sent',
            transport: 'wifi',
            relayExpiresAt: null,
            mode: OutgoingOrdinarySettlementMode.live,
          ),
          OutgoingOrdinaryMutationOutcome.applied,
        );
      }

      expect(
        await dbSettleOutgoingOrdinaryTransport(
          db,
          messageId: 'physically-removed',
          expectedContactPeerId: 'peer-a',
          expectedEnvelope: 'envelope-a',
          status: 'sent',
          transport: 'wifi',
          relayExpiresAt: null,
          mode: OutgoingOrdinarySettlementMode.live,
        ),
        OutgoingOrdinaryMutationOutcome.removed,
      );
      expect(await maybeLoadMessage('physically-removed'), isNull);
    },
  );

  test('fresh existing and edit staging bind one exact attempt', () async {
    final fresh = messageRow(
      id: 'fresh-stage',
      status: 'sending',
      transport: null,
      wireEnvelope: 'fresh-envelope',
    );
    expect(
      await dbStageOutgoingOrdinaryAttempt(
        db,
        expectedRow: null,
        stagedRow: fresh,
        kind: OutgoingOrdinaryAttemptKind.fresh,
      ),
      OutgoingOrdinaryMutationOutcome.applied,
    );
    final freshPersisted = await loadMessage('fresh-stage');
    expect(freshPersisted['status'], 'sending');
    expect(freshPersisted['wire_envelope'], 'fresh-envelope');

    expect(
      await dbStageOutgoingOrdinaryAttempt(
        db,
        expectedRow: null,
        stagedRow: fresh,
        kind: OutgoingOrdinaryAttemptKind.fresh,
      ),
      OutgoingOrdinaryMutationOutcome.refused,
    );
    expect(await loadMessage('fresh-stage'), freshPersisted);

    final existing = await insertMessage(
      messageRow(
        id: 'existing-stage',
        text: 'stable payload',
        status: 'failed',
        transport: 'inbox',
        wireEnvelope: 'old-envelope',
        relayExpiresAt: 8080,
        custodyCheckedAt: '2026-08-05T12:03:00.000Z',
      ),
    );
    final stagedExisting = Map<String, Object?>.from(existing)
      ..['status'] = 'sending'
      ..['transport'] = null
      ..['wire_envelope'] = 'new-envelope'
      ..['relay_expires_at'] = null
      ..['custody_checked_at'] = null;
    expect(
      await dbStageOutgoingOrdinaryAttempt(
        db,
        expectedRow: existing,
        stagedRow: stagedExisting,
        kind: OutgoingOrdinaryAttemptKind.existing,
      ),
      OutgoingOrdinaryMutationOutcome.applied,
    );
    final existingAfter = await loadMessage('existing-stage');
    expect(existingAfter, stagedExisting);
    expect(existingAfter['text'], 'stable payload');

    final sendingExisting = await insertMessage(
      messageRow(
        id: 'existing-sending-stage',
        text: 'sending payload',
        status: 'sending',
        transport: null,
        wireEnvelope: null,
      ),
    );
    final stagedSendingExisting = Map<String, Object?>.from(sendingExisting)
      ..['status'] = 'sending'
      ..['transport'] = null
      ..['wire_envelope'] = 'sending-stage-envelope'
      ..['relay_expires_at'] = null
      ..['custody_checked_at'] = null;
    expect(
      await dbStageOutgoingOrdinaryAttempt(
        db,
        expectedRow: sendingExisting,
        stagedRow: stagedSendingExisting,
        kind: OutgoingOrdinaryAttemptKind.existing,
      ),
      OutgoingOrdinaryMutationOutcome.applied,
    );
    expect(await loadMessage('existing-sending-stage'), stagedSendingExisting);

    expect(
      await dbStageOutgoingOrdinaryAttempt(
        db,
        expectedRow: existing,
        stagedRow: stagedExisting,
        kind: OutgoingOrdinaryAttemptKind.existing,
      ),
      OutgoingOrdinaryMutationOutcome.idempotent,
    );
    expect(await loadMessage('existing-stage'), existingAfter);

    final contentExpected = await insertMessage(
      messageRow(
        id: 'existing-content-race',
        text: 'stale content',
        status: 'failed',
        wireEnvelope: 'content-race-old-envelope',
      ),
    );
    await db.update(
      'messages',
      const <String, Object?>{'text': 'winning content'},
      where: 'id = ?',
      whereArgs: const <Object?>['existing-content-race'],
    );
    final contentWinner = await loadMessage('existing-content-race');
    final contentStage = Map<String, Object?>.from(contentExpected)
      ..['status'] = 'sending'
      ..['transport'] = null
      ..['wire_envelope'] = 'content-race-stage-envelope'
      ..['relay_expires_at'] = null
      ..['custody_checked_at'] = null;
    expect(
      await dbStageOutgoingOrdinaryAttempt(
        db,
        expectedRow: contentExpected,
        stagedRow: contentStage,
        kind: OutgoingOrdinaryAttemptKind.existing,
      ),
      OutgoingOrdinaryMutationOutcome.preserved,
    );
    expect(await loadMessage('existing-content-race'), contentWinner);

    final envelopeExpected = await insertMessage(
      messageRow(
        id: 'existing-envelope-race',
        status: 'failed',
        wireEnvelope: 'envelope-race-old-envelope',
      ),
    );
    await db.update(
      'messages',
      const <String, Object?>{
        'wire_envelope': 'envelope-race-winning-envelope',
      },
      where: 'id = ?',
      whereArgs: const <Object?>['existing-envelope-race'],
    );
    final envelopeWinner = await loadMessage('existing-envelope-race');
    final envelopeStage = Map<String, Object?>.from(envelopeExpected)
      ..['status'] = 'sending'
      ..['transport'] = null
      ..['wire_envelope'] = 'envelope-race-stage-envelope'
      ..['relay_expires_at'] = null
      ..['custody_checked_at'] = null;
    expect(
      await dbStageOutgoingOrdinaryAttempt(
        db,
        expectedRow: envelopeExpected,
        stagedRow: envelopeStage,
        kind: OutgoingOrdinaryAttemptKind.existing,
      ),
      OutgoingOrdinaryMutationOutcome.preserved,
    );
    expect(await loadMessage('existing-envelope-race'), envelopeWinner);

    final editExpected = await insertMessage(
      messageRow(
        id: 'edit-stage',
        text: 'old text',
        status: 'inboxed',
        transport: 'inbox',
        wireEnvelope: 'old-edit-envelope',
        relayExpiresAt: 9090,
        custodyCheckedAt: '2026-08-05T12:04:00.000Z',
      ),
    );
    final firstEdit = Map<String, Object?>.from(editExpected)
      ..['text'] = 'first edit'
      ..['edited_at'] = '2026-08-05T12:05:00.000Z'
      ..['status'] = 'sending'
      ..['transport'] = null
      ..['wire_envelope'] = 'first-edit-envelope'
      ..['relay_expires_at'] = null
      ..['custody_checked_at'] = null;
    final crossedEdit = Map<String, Object?>.from(firstEdit)
      ..['text'] = 'crossed edit'
      ..['edited_at'] = '2026-08-05T12:06:00.000Z'
      ..['wire_envelope'] = 'crossed-edit-envelope';
    expect(
      await dbStageOutgoingOrdinaryAttempt(
        db,
        expectedRow: editExpected,
        stagedRow: firstEdit,
        kind: OutgoingOrdinaryAttemptKind.edit,
      ),
      OutgoingOrdinaryMutationOutcome.applied,
    );
    final firstEditAfter = await loadMessage('edit-stage');
    expect(firstEditAfter, firstEdit);
    expect(firstEditAfter['transport'], isNull);
    expect(firstEditAfter['relay_expires_at'], isNull);
    expect(firstEditAfter['custody_checked_at'], isNull);

    expect(
      await dbStageOutgoingOrdinaryAttempt(
        db,
        expectedRow: editExpected,
        stagedRow: crossedEdit,
        kind: OutgoingOrdinaryAttemptKind.edit,
      ),
      OutgoingOrdinaryMutationOutcome.preserved,
    );
    expect(await loadMessage('edit-stage'), firstEditAfter);

    final removedExpected = await insertMessage(
      messageRow(id: 'removed-stage', status: 'failed'),
    );
    await db.delete(
      'messages',
      where: 'id = ?',
      whereArgs: const <Object?>['removed-stage'],
    );
    final removedStaged = Map<String, Object?>.from(removedExpected)
      ..['status'] = 'sending'
      ..['transport'] = null
      ..['wire_envelope'] = 'removed-new-envelope'
      ..['relay_expires_at'] = null
      ..['custody_checked_at'] = null;
    expect(
      await dbStageOutgoingOrdinaryAttempt(
        db,
        expectedRow: removedExpected,
        stagedRow: removedStaged,
        kind: OutgoingOrdinaryAttemptKind.existing,
      ),
      OutgoingOrdinaryMutationOutcome.removed,
    );
    expect(await maybeLoadMessage('removed-stage'), isNull);

    for (final status in const <String>['sent', 'inboxed', 'delivered']) {
      final expected = await insertMessage(
        messageRow(
          id: 'existing-refuses-$status',
          status: status,
          transport: status == 'inboxed' ? 'inbox' : 'wifi',
          wireEnvelope: status == 'delivered' ? null : 'existing-envelope',
        ),
      );
      final staged = Map<String, Object?>.from(expected)
        ..['status'] = 'sending'
        ..['transport'] = null
        ..['wire_envelope'] = 'replacement-envelope'
        ..['relay_expires_at'] = null
        ..['custody_checked_at'] = null;
      expect(
        await dbStageOutgoingOrdinaryAttempt(
          db,
          expectedRow: expected,
          stagedRow: staged,
          kind: OutgoingOrdinaryAttemptKind.existing,
        ),
        OutgoingOrdinaryMutationOutcome.refused,
      );
      expect(await loadMessage('existing-refuses-$status'), expected);
    }

    final mediaParent = await insertMessage(
      messageRow(id: 'text-stage-with-media', status: 'failed'),
    );
    final mediaRow = attachmentRow(
      id: 'text-stage-media',
      messageId: 'text-stage-with-media',
    );
    await db.insert('media_attachments', mediaRow);
    final persistedMedia = await loadAttachment('text-stage-media');
    final mediaStaged = Map<String, Object?>.from(mediaParent)
      ..['status'] = 'sending'
      ..['transport'] = null
      ..['wire_envelope'] = 'media-new-envelope'
      ..['relay_expires_at'] = null
      ..['custody_checked_at'] = null;
    expect(
      await dbStageOutgoingOrdinaryAttempt(
        db,
        expectedRow: mediaParent,
        stagedRow: mediaStaged,
        kind: OutgoingOrdinaryAttemptKind.existing,
      ),
      OutgoingOrdinaryMutationOutcome.refused,
    );
    expect(await loadMessage('text-stage-with-media'), mediaParent);
    expect(await loadAttachment('text-stage-media'), persistedMedia);

    await db.insert(
      'media_attachments',
      attachmentRow(id: 'orphan-media', messageId: 'fresh-media-refusal'),
    );
    expect(
      await dbStageOutgoingOrdinaryAttempt(
        db,
        expectedRow: null,
        stagedRow: messageRow(
          id: 'fresh-media-refusal',
          wireEnvelope: 'fresh-media-envelope',
        ),
        kind: OutgoingOrdinaryAttemptKind.fresh,
      ),
      OutgoingOrdinaryMutationOutcome.refused,
    );
    expect(await maybeLoadMessage('fresh-media-refusal'), isNull);
  });

  test(
    'ordinary tombstone staging and settlement never resurrect or cross envelopes',
    () async {
      final original = await insertMessage(
        messageRow(
          id: 'ordinary-tombstone',
          text: 'delete me',
          status: 'delivered',
          transport: 'wifi',
          wireEnvelope: null,
          relayExpiresAt: 1010,
          custodyCheckedAt: '2026-08-05T12:07:00.000Z',
        ),
      );
      const deletedAt = '2026-08-05T12:08:00.000Z';
      final stagedTombstone = Map<String, Object?>.from(original)
        ..['text'] = ''
        ..['status'] = 'sending'
        ..['deleted_at'] = deletedAt
        ..['deleted_by_peer_id'] = 'self-peer'
        ..['hidden_at'] = null
        ..['transport'] = null
        ..['wire_envelope'] = 'delete-envelope'
        ..['relay_expires_at'] = null
        ..['custody_checked_at'] = null;
      expect(
        await dbStageOutgoingOrdinaryAttempt(
          db,
          expectedRow: original,
          stagedRow: stagedTombstone,
          kind: OutgoingOrdinaryAttemptKind.tombstoneInitial,
        ),
        OutgoingOrdinaryMutationOutcome.applied,
      );
      expect(await loadMessage('ordinary-tombstone'), stagedTombstone);

      expect(
        await dbSettleOutgoingOrdinaryDeleteTombstone(
          db,
          messageId: 'ordinary-tombstone',
          expectedContactPeerId: 'peer-a',
          expectedEnvelope: 'delete-envelope',
          status: 'inboxed',
          transport: 'inbox',
          relayExpiresAt: 2020,
          mode: OutgoingOrdinarySettlementMode.live,
        ),
        OutgoingOrdinaryMutationOutcome.applied,
      );
      final inboxed = await loadMessage('ordinary-tombstone');
      final expectedInboxed = Map<String, Object?>.from(stagedTombstone)
        ..['status'] = 'inboxed'
        ..['transport'] = 'inbox'
        ..['wire_envelope'] = 'delete-envelope'
        ..['relay_expires_at'] = 2020
        ..['custody_checked_at'] = null;
      expect(inboxed, expectedInboxed);
      expect(inboxed['hidden_at'], isNull);
      expect(inboxed['deleted_at'], deletedAt);
      expect(inboxed['wire_envelope'], 'delete-envelope');

      expect(
        await dbSettleOutgoingOrdinaryDeleteTombstone(
          db,
          messageId: 'ordinary-tombstone',
          expectedContactPeerId: 'peer-a',
          expectedEnvelope: 'delete-envelope',
          status: 'delivered',
          transport: 'direct',
          relayExpiresAt: null,
          mode: OutgoingOrdinarySettlementMode.live,
        ),
        OutgoingOrdinaryMutationOutcome.applied,
      );
      final delivered = await loadMessage('ordinary-tombstone');
      final expectedDelivered = Map<String, Object?>.from(expectedInboxed)
        ..['status'] = 'delivered'
        ..['transport'] = 'direct'
        ..['wire_envelope'] = null
        ..['relay_expires_at'] = null
        ..['custody_checked_at'] = null
        ..['hidden_at'] = deletedAt;
      expect(delivered, expectedDelivered);
      expect(delivered['status'], 'delivered');
      expect(delivered['hidden_at'], deletedAt);
      expect(delivered['wire_envelope'], isNull);
      expect(delivered['relay_expires_at'], isNull);
      expect(delivered['custody_checked_at'], isNull);

      expect(
        await dbSettleOutgoingOrdinaryDeleteTombstone(
          db,
          messageId: 'ordinary-tombstone',
          expectedContactPeerId: 'peer-a',
          expectedEnvelope: 'delete-envelope',
          status: 'sent',
          transport: 'relay',
          relayExpiresAt: null,
          mode: OutgoingOrdinarySettlementMode.live,
        ),
        OutgoingOrdinaryMutationOutcome.preserved,
      );
      expect(await loadMessage('ordinary-tombstone'), delivered);
      expect(
        await dbSettleOutgoingOrdinaryDeleteTombstone(
          db,
          messageId: 'ordinary-tombstone',
          expectedContactPeerId: 'peer-a',
          expectedEnvelope: 'obsolete-delete-envelope',
          status: 'delivered',
          transport: 'relay',
          relayExpiresAt: null,
          mode: OutgoingOrdinarySettlementMode.live,
        ),
        OutgoingOrdinaryMutationOutcome.idempotent,
      );
      expect(await loadMessage('ordinary-tombstone'), delivered);

      final removedOriginal = await insertMessage(
        messageRow(
          id: 'removed-tombstone',
          status: 'delivered',
          transport: 'wifi',
          wireEnvelope: null,
        ),
      );
      await db.delete(
        'messages',
        where: 'id = ?',
        whereArgs: const <Object?>['removed-tombstone'],
      );
      final removedTombstone = Map<String, Object?>.from(removedOriginal)
        ..['text'] = ''
        ..['status'] = 'sending'
        ..['deleted_at'] = deletedAt
        ..['deleted_by_peer_id'] = 'self-peer'
        ..['transport'] = null
        ..['wire_envelope'] = 'removed-delete-envelope'
        ..['relay_expires_at'] = null
        ..['custody_checked_at'] = null;
      expect(
        await dbStageOutgoingOrdinaryAttempt(
          db,
          expectedRow: removedOriginal,
          stagedRow: removedTombstone,
          kind: OutgoingOrdinaryAttemptKind.tombstoneInitial,
        ),
        OutgoingOrdinaryMutationOutcome.removed,
      );
      expect(await maybeLoadMessage('removed-tombstone'), isNull);

      final failedTombstone = await insertMessage(
        messageRow(
          id: 'retry-tombstone',
          text: '',
          status: 'failed',
          deletedAt: deletedAt,
          deletedByPeerId: 'self-peer',
          transport: 'inbox',
          wireEnvelope: null,
          relayExpiresAt: 3030,
          custodyCheckedAt: '2026-08-05T12:09:00.000Z',
        ),
      );
      final retryStage = Map<String, Object?>.from(failedTombstone)
        ..['status'] = 'sending'
        ..['transport'] = null
        ..['wire_envelope'] = 'rebuilt-delete-envelope'
        ..['relay_expires_at'] = null
        ..['custody_checked_at'] = null;
      expect(
        await dbStageOutgoingOrdinaryAttempt(
          db,
          expectedRow: failedTombstone,
          stagedRow: retryStage,
          kind: OutgoingOrdinaryAttemptKind.tombstoneRetry,
        ),
        OutgoingOrdinaryMutationOutcome.applied,
      );
      expect(await loadMessage('retry-tombstone'), retryStage);

      final emptyEnvelopeTombstone = await insertMessage(
        messageRow(
          id: 'retry-tombstone-empty-envelope',
          text: '',
          status: 'failed',
          deletedAt: deletedAt,
          deletedByPeerId: 'self-peer',
          transport: 'inbox',
          wireEnvelope: '',
          relayExpiresAt: 4040,
          custodyCheckedAt: '2026-08-05T12:09:30.000Z',
        ),
      );
      final emptyEnvelopeRetryStage =
          Map<String, Object?>.from(emptyEnvelopeTombstone)
            ..['status'] = 'sending'
            ..['transport'] = null
            ..['wire_envelope'] = 'rebuilt-from-empty-delete-envelope'
            ..['relay_expires_at'] = null
            ..['custody_checked_at'] = null;
      expect(
        await dbStageOutgoingOrdinaryAttempt(
          db,
          expectedRow: emptyEnvelopeTombstone,
          stagedRow: emptyEnvelopeRetryStage,
          kind: OutgoingOrdinaryAttemptKind.tombstoneRetry,
        ),
        OutgoingOrdinaryMutationOutcome.applied,
      );
      expect(
        await loadMessage('retry-tombstone-empty-envelope'),
        emptyEnvelopeRetryStage,
      );

      final crossedExpected = await insertMessage(
        messageRow(
          id: 'crossed-tombstone',
          text: '',
          status: 'failed',
          deletedAt: deletedAt,
          deletedByPeerId: 'self-peer',
          wireEnvelope: 'old-delete-envelope',
        ),
      );
      await db.update(
        'messages',
        const <String, Object?>{'wire_envelope': 'winning-envelope'},
        where: 'id = ?',
        whereArgs: const <Object?>['crossed-tombstone'],
      );
      final crossedBefore = await loadMessage('crossed-tombstone');
      final crossedStage = Map<String, Object?>.from(crossedExpected)
        ..['status'] = 'sending'
        ..['transport'] = null
        ..['wire_envelope'] = 'losing-envelope'
        ..['relay_expires_at'] = null
        ..['custody_checked_at'] = null;
      expect(
        await dbStageOutgoingOrdinaryAttempt(
          db,
          expectedRow: crossedExpected,
          stagedRow: crossedStage,
          kind: OutgoingOrdinaryAttemptKind.tombstoneRetry,
        ),
        OutgoingOrdinaryMutationOutcome.preserved,
      );
      expect(await loadMessage('crossed-tombstone'), crossedBefore);

      final sentOriginal = await insertMessage(
        messageRow(
          id: 'invalid-initial-tombstone',
          status: 'sent',
          transport: 'wifi',
        ),
      );
      final invalidInitial = Map<String, Object?>.from(sentOriginal)
        ..['text'] = ''
        ..['status'] = 'sending'
        ..['deleted_at'] = deletedAt
        ..['deleted_by_peer_id'] = 'self-peer'
        ..['transport'] = null
        ..['wire_envelope'] = 'invalid-initial-envelope'
        ..['relay_expires_at'] = null
        ..['custody_checked_at'] = null;
      expect(
        await dbStageOutgoingOrdinaryAttempt(
          db,
          expectedRow: sentOriginal,
          stagedRow: invalidInitial,
          kind: OutgoingOrdinaryAttemptKind.tombstoneInitial,
        ),
        OutgoingOrdinaryMutationOutcome.refused,
        reason: 'initial delete authority is only delivered or inboxed',
      );
      expect(await loadMessage('invalid-initial-tombstone'), sentOriginal);
    },
  );

  test(
    'TC336-05 tombstoneInitial refuses a predecessor with a deletion owner byte-identically',
    () async {
      final before = await insertMessage(
        messageRow(
          id: 'initial-tombstone-dangling-deleter',
          status: 'delivered',
          deletedByPeerId: 'peer-that-already-deleted',
          transport: 'direct',
          wireEnvelope: null,
        ),
      );
      final staged = Map<String, Object?>.from(before)
        ..['text'] = ''
        ..['status'] = 'sending'
        ..['deleted_at'] = '2026-08-05T12:12:00.000Z'
        ..['deleted_by_peer_id'] = 'self-peer'
        ..['hidden_at'] = null
        ..['transport'] = null
        ..['wire_envelope'] = 'dangling-deleter-delete-envelope'
        ..['relay_expires_at'] = null
        ..['custody_checked_at'] = null;

      expect(
        await dbStageOutgoingOrdinaryAttempt(
          db,
          expectedRow: before,
          stagedRow: staged,
          kind: OutgoingOrdinaryAttemptKind.tombstoneInitial,
        ),
        OutgoingOrdinaryMutationOutcome.refused,
      );
      expect(await loadMessage('initial-tombstone-dangling-deleter'), before);
    },
  );

  test(
    'tombstone settlement refuses a delivered row without derived hidden_at byte-identically',
    () async {
      final before = await insertMessage(
        messageRow(
          id: 'malformed-delivered-tombstone',
          text: '',
          status: 'delivered',
          deletedAt: '2026-08-05T12:13:00.000Z',
          deletedByPeerId: 'self-peer',
          hiddenAt: null,
          transport: 'direct',
          wireEnvelope: null,
        ),
      );

      expect(
        await dbSettleOutgoingOrdinaryDeleteTombstone(
          db,
          messageId: 'malformed-delivered-tombstone',
          expectedContactPeerId: 'peer-a',
          expectedEnvelope: 'malformed-delivered-envelope',
          status: 'delivered',
          transport: 'direct',
          relayExpiresAt: null,
          mode: OutgoingOrdinarySettlementMode.live,
        ),
        OutgoingOrdinaryMutationOutcome.refused,
      );
      expect(await loadMessage('malformed-delivered-tombstone'), before);
    },
  );

  test(
    'TC336-07 unsafe-legacy quarantine refuses an empty deleted_at tombstone byte-identically',
    () async {
      final before = await insertMessage(
        messageRow(
          id: 'quarantine-empty-deleted-at',
          text: '',
          status: 'sent',
          deletedAt: '',
          deletedByPeerId: 'self-peer',
          transport: 'inbox',
          wireEnvelope: 'empty-deleted-at-envelope',
        ),
      );

      expect(
        await dbQuarantineUnsafeLegacyOutgoingEnvelope(
          db,
          messageId: 'quarantine-empty-deleted-at',
          expectedContactPeerId: 'peer-a',
          expectedEnvelope: 'empty-deleted-at-envelope',
          isDeleteTombstone: true,
        ),
        OutgoingOrdinaryMutationOutcome.refused,
      );
      expect(await loadMessage('quarantine-empty-deleted-at'), before);
    },
  );

  test(
    'unsafe-legacy quarantine changes only exact transport custody columns',
    () async {
      final ordinary = await insertMessage(
        messageRow(
          id: 'quarantine-exact-ordinary',
          text: 'edited payload survives',
          status: 'sent',
          editedAt: '2026-08-05T12:12:00.000Z',
          transport: 'inbox',
          wireEnvelope: 'legacy-chat-envelope',
          relayExpiresAt: 3360701,
          custodyCheckedAt: '2026-08-05T12:13:00.000Z',
        ),
      );
      expect(
        await dbQuarantineUnsafeLegacyOutgoingEnvelope(
          db,
          messageId: 'quarantine-exact-ordinary',
          expectedContactPeerId: 'peer-a',
          expectedEnvelope: 'legacy-chat-envelope',
          isDeleteTombstone: false,
        ),
        OutgoingOrdinaryMutationOutcome.applied,
      );
      final expectedOrdinary = Map<String, Object?>.from(ordinary)
        ..['status'] = 'failed'
        ..['transport'] = null
        ..['relay_expires_at'] = null
        ..['custody_checked_at'] = null;
      expect(await loadMessage('quarantine-exact-ordinary'), expectedOrdinary);

      final tombstone = await insertMessage(
        messageRow(
          id: 'quarantine-exact-tombstone',
          text: '',
          status: 'sent',
          deletedAt: '2026-08-05T12:14:00.000Z',
          deletedByPeerId: 'self-peer',
          transport: 'inbox',
          wireEnvelope: 'legacy-delete-envelope',
          relayExpiresAt: 3360702,
          custodyCheckedAt: '2026-08-05T12:15:00.000Z',
        ),
      );
      expect(
        await dbQuarantineUnsafeLegacyOutgoingEnvelope(
          db,
          messageId: 'quarantine-exact-tombstone',
          expectedContactPeerId: 'peer-a',
          expectedEnvelope: 'legacy-delete-envelope',
          isDeleteTombstone: true,
        ),
        OutgoingOrdinaryMutationOutcome.applied,
      );
      final expectedTombstone = Map<String, Object?>.from(tombstone)
        ..['status'] = 'failed'
        ..['transport'] = null
        ..['relay_expires_at'] = null
        ..['custody_checked_at'] = null;
      expect(
        await loadMessage('quarantine-exact-tombstone'),
        expectedTombstone,
      );

      final crossed = await insertMessage(
        messageRow(
          id: 'quarantine-crossed-envelope',
          status: 'sent',
          transport: 'inbox',
          wireEnvelope: 'winning-envelope',
          relayExpiresAt: 3360799,
          custodyCheckedAt: '2026-08-05T12:16:00.000Z',
        ),
      );
      expect(
        await dbQuarantineUnsafeLegacyOutgoingEnvelope(
          db,
          messageId: 'quarantine-crossed-envelope',
          expectedContactPeerId: 'peer-a',
          expectedEnvelope: 'stale-envelope',
          isDeleteTombstone: false,
        ),
        OutgoingOrdinaryMutationOutcome.preserved,
      );
      expect(await loadMessage('quarantine-crossed-envelope'), crossed);
    },
  );

  test(
    'media retry invalidates only an exact retryable cached envelope',
    () async {
      for (final status in const <String>['sending', 'failed']) {
        final id = 'invalidate-$status';
        final before = await insertMessage(
          messageRow(
            id: id,
            text: 'preserved $status payload',
            status: status,
            transport: status == 'failed' ? 'inbox' : 'wifi',
            wireEnvelope: 'invalidate-envelope',
            relayExpiresAt: 4040,
            custodyCheckedAt: '2026-08-05T12:10:00.000Z',
          ),
        );
        expect(
          await dbInvalidateOutgoingOrdinaryEnvelope(
            db,
            messageId: id,
            expectedContactPeerId: 'peer-a',
            expectedEnvelope: 'invalidate-envelope',
          ),
          OutgoingOrdinaryMutationOutcome.applied,
        );
        final expected = Map<String, Object?>.from(before)
          ..['wire_envelope'] = null;
        expect(await loadMessage(id), expected);
      }

      final disappearing = await insertMessage(
        messageRow(
          id: 'invalidate-disappearing',
          status: 'failed',
          wireEnvelope: 'disappearing-envelope',
          policyVersion: 1,
          policyMode: 'disappearing',
        ),
      );
      expect(
        await dbInvalidateOutgoingOrdinaryEnvelope(
          db,
          messageId: 'invalidate-disappearing',
          expectedContactPeerId: 'peer-a',
          expectedEnvelope: 'disappearing-envelope',
        ),
        OutgoingOrdinaryMutationOutcome.applied,
      );
      final expectedDisappearing = Map<String, Object?>.from(disappearing)
        ..['wire_envelope'] = null;
      expect(
        await loadMessage('invalidate-disappearing'),
        expectedDisappearing,
      );

      final wrongEnvelope = await insertMessage(
        messageRow(
          id: 'invalidate-wrong-envelope',
          status: 'failed',
          wireEnvelope: 'winning-envelope',
        ),
      );
      expect(
        await dbInvalidateOutgoingOrdinaryEnvelope(
          db,
          messageId: 'invalidate-wrong-envelope',
          expectedContactPeerId: 'peer-a',
          expectedEnvelope: 'losing-envelope',
        ),
        OutgoingOrdinaryMutationOutcome.preserved,
      );
      expect(await loadMessage('invalidate-wrong-envelope'), wrongEnvelope);

      final wrongPeer = await insertMessage(
        messageRow(
          id: 'invalidate-wrong-peer',
          status: 'failed',
          wireEnvelope: 'peer-envelope',
        ),
      );
      expect(
        await dbInvalidateOutgoingOrdinaryEnvelope(
          db,
          messageId: 'invalidate-wrong-peer',
          expectedContactPeerId: 'other-peer',
          expectedEnvelope: 'peer-envelope',
        ),
        OutgoingOrdinaryMutationOutcome.refused,
      );
      expect(await loadMessage('invalidate-wrong-peer'), wrongPeer);

      for (final status in const <String>['sent', 'inboxed', 'delivered']) {
        final id = 'invalidate-refuses-$status';
        final before = await insertMessage(
          messageRow(
            id: id,
            status: status,
            transport: status == 'inboxed' ? 'inbox' : 'wifi',
            wireEnvelope: 'status-envelope',
          ),
        );
        expect(
          await dbInvalidateOutgoingOrdinaryEnvelope(
            db,
            messageId: id,
            expectedContactPeerId: 'peer-a',
            expectedEnvelope: 'status-envelope',
          ),
          OutgoingOrdinaryMutationOutcome.refused,
        );
        expect(await loadMessage(id), before);
      }

      final hidden = await insertMessage(
        messageRow(
          id: 'invalidate-hidden',
          status: 'failed',
          hiddenAt: '2026-08-05T12:11:00.000Z',
          wireEnvelope: 'hidden-envelope',
        ),
      );
      expect(
        await dbInvalidateOutgoingOrdinaryEnvelope(
          db,
          messageId: 'invalidate-hidden',
          expectedContactPeerId: 'peer-a',
          expectedEnvelope: 'hidden-envelope',
        ),
        OutgoingOrdinaryMutationOutcome.preserved,
      );
      expect(await loadMessage('invalidate-hidden'), hidden);

      final danglingDeleter = await insertMessage(
        messageRow(
          id: 'invalidate-dangling-deleter',
          status: 'failed',
          deletedByPeerId: 'self-peer',
          wireEnvelope: 'dangling-envelope',
        ),
      );
      expect(
        await dbInvalidateOutgoingOrdinaryEnvelope(
          db,
          messageId: 'invalidate-dangling-deleter',
          expectedContactPeerId: 'peer-a',
          expectedEnvelope: 'dangling-envelope',
        ),
        OutgoingOrdinaryMutationOutcome.preserved,
      );
      expect(await loadMessage('invalidate-dangling-deleter'), danglingDeleter);

      final quarantineDanglingDeleter = await insertMessage(
        messageRow(
          id: 'quarantine-dangling-deleter',
          status: 'sent',
          transport: 'inbox',
          deletedByPeerId: 'self-peer',
          wireEnvelope: 'legacy-envelope',
        ),
      );
      expect(
        await dbQuarantineUnsafeLegacyOutgoingEnvelope(
          db,
          messageId: 'quarantine-dangling-deleter',
          expectedContactPeerId: 'peer-a',
          expectedEnvelope: 'legacy-envelope',
          isDeleteTombstone: false,
        ),
        OutgoingOrdinaryMutationOutcome.refused,
      );
      expect(
        await loadMessage('quarantine-dangling-deleter'),
        quarantineDanglingDeleter,
      );

      final protected = await insertMessage(
        messageRow(
          id: 'invalidate-protected',
          status: 'failed',
          wireEnvelope: 'protected-envelope',
          policyVersion: 1,
          policyMode: 'protected',
        ),
      );
      expect(
        await dbInvalidateOutgoingOrdinaryEnvelope(
          db,
          messageId: 'invalidate-protected',
          expectedContactPeerId: 'peer-a',
          expectedEnvelope: 'protected-envelope',
        ),
        OutgoingOrdinaryMutationOutcome.refused,
      );
      expect(await loadMessage('invalidate-protected'), protected);

      expect(
        await dbInvalidateOutgoingOrdinaryEnvelope(
          db,
          messageId: 'invalidate-removed',
          expectedContactPeerId: 'peer-a',
          expectedEnvelope: 'removed-envelope',
        ),
        OutgoingOrdinaryMutationOutcome.removed,
      );
      expect(await maybeLoadMessage('invalidate-removed'), isNull);
    },
  );
}
