import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_app/core/database/app_database_version.dart';
import 'package:flutter_app/core/database/migrations/001_identity_table.dart';
import 'package:flutter_app/core/database/migrations/003_mlkem_keys.dart';
import 'package:flutter_app/core/database/migrations/007_archive_columns.dart';
import 'package:flutter_app/core/database/migrations/008_block_columns.dart';
import 'package:flutter_app/core/database/migrations/011_avatar_version.dart';
import 'package:flutter_app/core/database/migrations/112_direct_linked_device_addressing.dart';
import 'package:flutter_app/core/database/direct_media_blob_custody.dart';
import 'package:flutter_app/core/database/helpers/contacts_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/direct_contact_device_bindings_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/direct_media_blob_custody_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/direct_inbox_custody_outbox_db_helpers.dart';
import 'package:flutter_app/core/database/production_migration_registry.dart';
import 'package:flutter_app/features/conversation/domain/models/direct_inbox_custody_outbox_entry.dart';

void main() {
  late Database db;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await openDatabase(inMemoryDatabasePath, version: 1);
    await runIdentityTableMigration(db);
    await runMlKemKeysMigration(db);
    await runArchiveColumnsMigration(db);
    await runBlockColumnsMigration(db);
    await runAvatarVersionMigration(db);
    // 360: `dbDeleteContact` is now the exact contact-deletion owner and also
    // clears that contact's linked-device roster in the same transaction, so
    // this fixture must carry the v112 tables the production schema has.
    await runDirectLinkedDeviceAddressingMigration(db);
  });

  tearDown(() async {
    await db.close();
  });

  Map<String, Object?> makeContactRow({
    String peerId = 'peer-001',
    String publicKey = 'pk-base64',
    String rendezvous = '/dns4/relay.example.com/tcp/443/wss/p2p/relay-id',
    String username = 'Alice',
    String signature = 'sig-base64',
    String scannedAt = '2026-01-01T00:00:00.000Z',
    String? avatarPath,
    String? avatarVersion,
    String? mlKemPublicKey,
    int isArchived = 0,
    String? archivedAt,
    int isBlocked = 0,
    String? blockedAt,
  }) {
    return {
      'peer_id': peerId,
      'public_key': publicKey,
      'rendezvous': rendezvous,
      'username': username,
      'signature': signature,
      'scanned_at': scannedAt,
      'avatar_path': avatarPath,
      'avatar_version': avatarVersion,
      'ml_kem_public_key': mlKemPublicKey,
      'is_archived': isArchived,
      'archived_at': archivedAt,
      'is_blocked': isBlocked,
      'blocked_at': blockedAt,
    };
  }

  group('dbLoadAllContacts', () {
    test('returns empty list when no contacts', () async {
      final results = await dbLoadAllContacts(db);
      expect(results, isEmpty);
    });

    test('returns all contacts ordered by scanned_at DESC', () async {
      await dbUpsertContact(
        db,
        makeContactRow(
          peerId: 'peer-oldest',
          scannedAt: '2026-01-01T00:00:00.000Z',
        ),
      );
      await dbUpsertContact(
        db,
        makeContactRow(
          peerId: 'peer-newest',
          scannedAt: '2026-03-01T00:00:00.000Z',
        ),
      );
      await dbUpsertContact(
        db,
        makeContactRow(
          peerId: 'peer-middle',
          scannedAt: '2026-02-01T00:00:00.000Z',
        ),
      );

      final results = await dbLoadAllContacts(db);
      expect(results.length, 3);
      expect(results[0]['peer_id'], 'peer-newest');
      expect(results[1]['peer_id'], 'peer-middle');
      expect(results[2]['peer_id'], 'peer-oldest');
    });
  });

  group('dbLoadContact', () {
    test('returns null for non-existent peerId', () async {
      final result = await dbLoadContact(db, 'nonexistent-peer');
      expect(result, isNull);
    });

    test('returns contact when exists', () async {
      await dbUpsertContact(
        db,
        makeContactRow(peerId: 'peer-alice', username: 'Alice'),
      );

      final result = await dbLoadContact(db, 'peer-alice');
      expect(result, isNotNull);
      expect(result!['username'], 'Alice');
    });
  });

  group('dbUpsertContact', () {
    test('inserts new contact', () async {
      await dbUpsertContact(db, makeContactRow(peerId: 'peer-new'));

      final rows = await db.query(
        'contacts',
        where: 'peer_id = ?',
        whereArgs: ['peer-new'],
      );
      expect(rows.length, 1);
      expect(rows[0]['peer_id'], 'peer-new');
    });

    test('upserts on conflict', () async {
      await dbUpsertContact(
        db,
        makeContactRow(peerId: 'peer-upsert', username: 'OriginalName'),
      );
      await dbUpsertContact(
        db,
        makeContactRow(peerId: 'peer-upsert', username: 'UpdatedName'),
      );

      final rows = await db.query(
        'contacts',
        where: 'peer_id = ?',
        whereArgs: ['peer-upsert'],
      );
      expect(rows.length, 1);
      expect(rows[0]['username'], 'UpdatedName');
    });
  });

  group('dbDeleteContact', () {
    test('deletes existing contact', () async {
      await dbUpsertContact(db, makeContactRow(peerId: 'peer-delete'));

      await dbDeleteContact(db, 'peer-delete');

      final rows = await db.query(
        'contacts',
        where: 'peer_id = ?',
        whereArgs: ['peer-delete'],
      );
      expect(rows, isEmpty);
    });

    test('does not delete other contacts', () async {
      await dbUpsertContact(
        db,
        makeContactRow(peerId: 'peer-delete', username: 'Delete Me'),
      );
      await dbUpsertContact(
        db,
        makeContactRow(peerId: 'peer-keep-contact', username: 'Keep Me'),
      );

      await dbDeleteContact(db, 'peer-delete');

      expect(await dbLoadContact(db, 'peer-delete'), isNull);
      final kept = await dbLoadContact(db, 'peer-keep-contact');
      expect(kept, isNotNull);
      expect(kept!['username'], 'Keep Me');
    });

    test('no error for non-existent peerId', () async {
      // Should not throw
      await dbDeleteContact(db, 'nonexistent-peer');
    });
  });

  group('dbGetContactCount', () {
    test('returns 0 when empty', () async {
      final count = await dbGetContactCount(db);
      expect(count, 0);
    });

    test('returns correct count', () async {
      await dbUpsertContact(db, makeContactRow(peerId: 'peer-a'));
      await dbUpsertContact(db, makeContactRow(peerId: 'peer-b'));
      await dbUpsertContact(db, makeContactRow(peerId: 'peer-c'));

      final count = await dbGetContactCount(db);
      expect(count, 3);
    });
  });

  group('dbArchiveContact', () {
    test('sets is_archived to 1 and archived_at to non-null', () async {
      await dbUpsertContact(db, makeContactRow(peerId: 'peer-archive'));

      await dbArchiveContact(db, 'peer-archive');

      final rows = await db.query(
        'contacts',
        where: 'peer_id = ?',
        whereArgs: ['peer-archive'],
      );
      expect(rows[0]['is_archived'], 1);
      expect(rows[0]['archived_at'], isNotNull);
    });
  });

  group('dbUnarchiveContact', () {
    test('sets is_archived to 0 and archived_at to null', () async {
      await dbUpsertContact(db, makeContactRow(peerId: 'peer-unarchive'));
      await dbArchiveContact(db, 'peer-unarchive');

      await dbUnarchiveContact(db, 'peer-unarchive');

      final rows = await db.query(
        'contacts',
        where: 'peer_id = ?',
        whereArgs: ['peer-unarchive'],
      );
      expect(rows[0]['is_archived'], 0);
      expect(rows[0]['archived_at'], isNull);
    });
  });

  group('dbLoadActiveContacts', () {
    test('returns only non-archived contacts', () async {
      await dbUpsertContact(db, makeContactRow(peerId: 'peer-active'));
      await dbUpsertContact(db, makeContactRow(peerId: 'peer-archived'));
      await dbArchiveContact(db, 'peer-archived');

      final results = await dbLoadActiveContacts(db);
      expect(results.length, 1);
      expect(results[0]['peer_id'], 'peer-active');
    });

    test('ordered by scanned_at DESC', () async {
      await dbUpsertContact(
        db,
        makeContactRow(
          peerId: 'peer-older',
          scannedAt: '2026-01-01T00:00:00.000Z',
        ),
      );
      await dbUpsertContact(
        db,
        makeContactRow(
          peerId: 'peer-newer',
          scannedAt: '2026-02-01T00:00:00.000Z',
        ),
      );

      final results = await dbLoadActiveContacts(db);
      expect(results.length, 2);
      expect(results[0]['peer_id'], 'peer-newer');
      expect(results[1]['peer_id'], 'peer-older');
    });
  });

  group('dbLoadArchivedContacts', () {
    test('returns only archived contacts', () async {
      await dbUpsertContact(db, makeContactRow(peerId: 'peer-active'));
      await dbUpsertContact(db, makeContactRow(peerId: 'peer-archived'));
      await dbArchiveContact(db, 'peer-archived');

      final results = await dbLoadArchivedContacts(db);
      expect(results.length, 1);
      expect(results[0]['peer_id'], 'peer-archived');
    });

    test('ordered by archived_at DESC', () async {
      await dbUpsertContact(db, makeContactRow(peerId: 'peer-first-archived'));
      await dbUpsertContact(db, makeContactRow(peerId: 'peer-second-archived'));
      await dbArchiveContact(db, 'peer-first-archived');
      // Small delay to ensure different archived_at timestamps
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await dbArchiveContact(db, 'peer-second-archived');

      final results = await dbLoadArchivedContacts(db);
      expect(results.length, 2);
      expect(results[0]['peer_id'], 'peer-second-archived');
      expect(results[1]['peer_id'], 'peer-first-archived');
    });
  });

  group('dbBlockContact', () {
    test('sets is_blocked to 1 and blocked_at to non-null', () async {
      await dbUpsertContact(db, makeContactRow(peerId: 'peer-block'));

      await dbBlockContact(db, 'peer-block');

      final rows = await db.query(
        'contacts',
        where: 'peer_id = ?',
        whereArgs: ['peer-block'],
      );
      expect(rows[0]['is_blocked'], 1);
      expect(rows[0]['blocked_at'], isNotNull);
    });
  });

  group('dbUnblockContact', () {
    test('sets is_blocked to 0 and blocked_at to null', () async {
      await dbUpsertContact(db, makeContactRow(peerId: 'peer-unblock'));
      await dbBlockContact(db, 'peer-unblock');

      await dbUnblockContact(db, 'peer-unblock');

      final rows = await db.query(
        'contacts',
        where: 'peer_id = ?',
        whereArgs: ['peer-unblock'],
      );
      expect(rows[0]['is_blocked'], 0);
      expect(rows[0]['blocked_at'], isNull);
    });
  });

  group('dbContactExists', () {
    test('returns false for non-existent', () async {
      final exists = await dbContactExists(db, 'nonexistent-peer');
      expect(exists, isFalse);
    });

    test('returns true for existing', () async {
      await dbUpsertContact(db, makeContactRow(peerId: 'peer-exists'));

      final exists = await dbContactExists(db, 'peer-exists');
      expect(exists, isTrue);
    });
  });

  group('TC-361-01b final serialized contact purge', () {
    const purgeContact = 'peer-purge-contact';
    const otherContact = 'peer-other-contact';
    const deviceTransport = 'peer-purge-device-transport';
    const t0 = '2026-08-11T10:00:00.000Z';

    late Directory tempDirectory;
    late Database current;

    setUp(() async {
      tempDirectory = await Directory.systemTemp.createTemp(
        'contact_purge_v113_',
      );
      current = await databaseFactoryFfi.openDatabase(
        '${tempDirectory.path}/identity.db',
        options: OpenDatabaseOptions(
          version: currentIdentityDatabaseVersion,
          singleInstance: false,
          onCreate: runProductionOnCreate,
          onUpgrade: runProductionOnUpgrade,
        ),
      );
      for (final peer in const <String>[purgeContact, otherContact]) {
        await current.insert('contacts', {
          ...makeContactRow(peerId: peer, mlKemPublicKey: 'mlkem-$peer'),
        });
      }
      await current.insert('direct_contact_device_roster_metadata', {
        'contact_account_peer_id': purgeContact,
        'roster_initialized': 1,
        'legacy_target_state': 'active',
        'initialized_at': t0,
        'legacy_revoked_at': null,
        'updated_at': t0,
      });
      await current.insert('direct_contact_device_bindings', {
        'contact_account_peer_id': purgeContact,
        'device_id': 'purge-device',
        'verified_account_signing_public_key': 'pk-base64',
        'transport_peer_id': deviceTransport,
        'transport_public_key': 'purge-transport-key',
        'device_ml_kem_public_key': 'purge-device-mlkem',
        'binding_fingerprint': 'c' * 64,
        'state': 'active',
        'staged_at': t0,
        'decided_at': t0,
      });

      Future<void> insertMessage(
        String id,
        String contact, {
        String? generation,
      }) => current.insert('messages', {
        'id': id,
        'contact_peer_id': contact,
        'sender_peer_id': 'peer-self',
        'text': 'text for $id',
        'timestamp': t0,
        'status': 'sent',
        'is_incoming': 0,
        'created_at': t0,
        'direct_event_fanout_generation_id': generation,
      });
      await insertMessage('purge-m1', purgeContact, generation: 'purge-m1');
      await insertMessage('purge-m2', purgeContact);
      await insertMessage('other-m1', otherContact);
      for (final (id, messageId) in const <(String, String)>[
        ('purge-r1', 'purge-m1'),
        ('other-r1', 'other-m1'),
      ]) {
        await current.insert('message_reactions', {
          'id': id,
          'message_id': messageId,
          'emoji': '👍',
          'sender_peer_id': 'peer-self',
          'timestamp': t0,
          'created_at': t0,
        });
      }
      Future<void> insertV108(
        String messageId,
        String recipient, {
        String? contactAccount,
        required String incarnation,
      }) => current.insert('direct_inbox_custody_outbox', {
        'recipient_peer_id': recipient,
        'message_id': messageId,
        'incarnation_id': incarnation,
        'wire_envelope': '{"probe":"$messageId"}',
        'retry_count': 0,
        'created_at': t0,
        'updated_at': t0,
        'contact_account_peer_id': contactAccount,
      });
      // A marked fanout sibling addressed to the linked transport, plus a
      // historical row whose ONLY logical-contact fact is its recipient.
      await insertV108(
        'purge-m1',
        deviceTransport,
        contactAccount: purgeContact,
        incarnation: '11111111111111111111111111111111',
      );
      await insertV108(
        'purge-m2',
        purgeContact,
        incarnation: '22222222222222222222222222222222',
      );
      await insertV108(
        'other-m1',
        otherContact,
        incarnation: '33333333333333333333333333333333',
      );
      Future<void> insertV109(
        String eventId,
        String recipient, {
        String? contactAccount,
        String? parentMessageId,
      }) => current.insert('direct_reaction_inbox_custody_outbox', {
        'recipient_peer_id': recipient,
        'event_id': eventId,
        'wire_envelope': '{"probe":"$eventId"}',
        'retry_count': 0,
        'created_at': t0,
        'updated_at': t0,
        'contact_account_peer_id': contactAccount,
        'parent_message_id': parentMessageId,
      });
      await insertV109(
        'purge-e1',
        deviceTransport,
        contactAccount: purgeContact,
        parentMessageId: 'purge-m1',
      );
      await insertV109('purge-e2', purgeContact);
      await insertV109('other-e1', otherContact);
    });

    tearDown(() async {
      if (current.isOpen) await current.close();
      if (await tempDirectory.exists()) {
        await tempDirectory.delete(recursive: true);
      }
    });

    Future<List<Object?>> remainingFor(String table, String column) async =>
        (await current.query(
          table,
          orderBy: column,
        )).map((row) => row[column]).toList();

    test('one transaction sweeps logical rows, roster, and contact', () async {
      final result = await dbPurgeDirectContactConversationAndContact(
        current,
        purgeContact,
      );

      expect(result.deletedTextCustodyRows, 2);
      expect(result.deletedEventCustodyRows, 2);
      expect(result.deletedReactions, 1);
      expect(result.deletedMessages, 2);
      expect(result.deletedContact, isTrue);

      expect(await remainingFor('messages', 'id'), ['other-m1']);
      expect(await remainingFor('message_reactions', 'id'), ['other-r1']);
      expect(
        await remainingFor('direct_inbox_custody_outbox', 'message_id'),
        ['other-m1'],
        reason:
            'COALESCE(contact_account_peer_id, recipient_peer_id) owns '
            'both marked and historical rows',
      );
      expect(
        await remainingFor('direct_reaction_inbox_custody_outbox', 'event_id'),
        ['other-e1'],
      );
      expect(await current.query('direct_contact_device_bindings'), isEmpty);
      expect(
        await current.query('direct_contact_device_roster_metadata'),
        isEmpty,
      );
      expect(await remainingFor('contacts', 'peer_id'), [otherContact]);
    });

    test(
      'a racing writer serializes behind the purge and finds no authority',
      () async {
        final observer = await databaseFactoryFfi.openDatabase(
          '${tempDirectory.path}/identity.db',
          options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
        );
        final transactionEntered = Completer<void>();
        final releaseTransaction = Completer<void>();
        try {
          final purge = dbPurgeDirectContactConversationAndContact(
            current,
            purgeContact,
            beforeContactDeleteForTest: () async {
              transactionEntered.complete();
              await releaseTransaction.future;
            },
          );
          await transactionEntered.future;

          // The observer still sees the pre-purge state: nothing is visible
          // until the single transaction commits.
          expect(
            (await observer.query(
              'contacts',
              where: 'peer_id = ?',
              whereArgs: const <Object?>[purgeContact],
            )),
            hasLength(1),
          );

          // A racing reaction apply through the SAME database serializes behind
          // the purge transaction instead of interleaving.
          var stageCompleted = false;
          final racing = current
              .insert('message_reactions', const {
                'id': 'purge-racing-reaction',
                'message_id': 'purge-m1',
                'emoji': '🎯',
                'sender_peer_id': 'peer-self',
                'timestamp': t0,
                'created_at': t0,
              })
              .whenComplete(() => stageCompleted = true);
          await Future<void>.delayed(const Duration(milliseconds: 10));
          expect(
            stageCompleted,
            isFalse,
            reason: 'the racing writer must wait for the owning transaction',
          );

          releaseTransaction.complete();
          await purge;
          await racing;

          // The late reaction row references a purged parent and a purged
          // contact: it cannot recreate an orphan conversation, and the final
          // owner's sweep semantics make the next purge-order equivalent.
          expect(
            await current.query(
              'messages',
              where: 'contact_peer_id = ?',
              whereArgs: const <Object?>[purgeContact],
            ),
            isEmpty,
          );
          expect(
            await current.query(
              'contacts',
              where: 'peer_id = ?',
              whereArgs: const <Object?>[purgeContact],
            ),
            isEmpty,
          );
        } finally {
          if (!releaseTransaction.isCompleted) releaseTransaction.complete();
          await observer.close();
        }
      },
    );

    test(
      'delete-first makes later completion and staging absent or refused',
      () async {
        final capturedRow = (await current.query(
          'direct_inbox_custody_outbox',
          where: 'message_id = ?',
          whereArgs: const <Object?>['purge-m1'],
        )).single;

        await dbPurgeDirectContactConversationAndContact(current, purgeContact);

        final completion = await dbCompleteAcceptedDirectInboxCustodyIfExact(
          current,
          recipientPeerId: capturedRow['recipient_peer_id'] as String,
          messageId: capturedRow['message_id'] as String,
          expectedIncarnationId: capturedRow['incarnation_id'] as String,
          expectedWireEnvelope: capturedRow['wire_envelope'] as String,
          relayExpiresAt: 1900000060000,
        );
        expect(
          completion,
          DirectInboxCustodyCompletionOutcome.stale,
          reason: 'a purged obligation is absent, never a reconstruction seed',
        );
        expect(
          await current.query(
            'messages',
            where: 'contact_peer_id = ?',
            whereArgs: const <Object?>[purgeContact],
          ),
          isEmpty,
          reason: 'no row may recreate an orphan conversation after the purge',
        );
        expect(
          await dbReadDirectContactFanoutSnapshot(
            current,
            contactAccountPeerId: purgeContact,
          ),
          isNull,
          reason: 'a removed contact refuses fanout rather than falling back',
        );
      },
    );

    test('TC-362-03a final contact purge transitions outgoing linked v114 rows '
        'and retains incoming obligations', () async {
      const attachmentId = 'purge-blob-att';
      final contentHash = 'c8' * 32;
      DirectMediaBlobCustodyRow blobRow({
        required String attachmentId,
        required DirectMediaBlobCustodyState state,
        String? recipientPeerId,
        String? contactAccountPeerId,
        String? recipientMlKemPublicKey,
        int? expiresAtMs,
        String? custodyRelayPeerId,
      }) => DirectMediaBlobCustodyRow(
        attachmentId: attachmentId,
        messageId: 'purge-m1',
        direction: state.direction,
        state: state,
        inboxCustodyIncarnationId: null,
        recipientPeerId: recipientPeerId,
        contactAccountPeerId: contactAccountPeerId,
        recipientMlKemPublicKey: recipientMlKemPublicKey,
        ciphertextRelativePath: recipientPeerId == null
            ? null
            : 'direct_media_blob_custody_v1/${'d' * 64}/$attachmentId.blob',
        contentHash: contentHash,
        ciphertextSize: 4096,
        expiresAtMs: expiresAtMs,
        custodyRelayPeerId: custodyRelayPeerId,
        lastAttemptAt: null,
        nextAttemptAt: null,
        createdAt: t0,
        updatedAt: t0,
      );

      // Two OUTGOING linked target rows (one prepared, one stored with its
      // full relay proof) owned by the purged logical contact.
      await current.insert(
        kDirectMediaBlobCustodyTable,
        blobRow(
          attachmentId: attachmentId,
          state: DirectMediaBlobCustodyState.outgoingPrepared,
          recipientPeerId: deviceTransport,
          contactAccountPeerId: purgeContact,
          recipientMlKemPublicKey: 'purge-device-mlkem',
        ).toMap(),
      );
      await current.insert(
        kDirectMediaBlobCustodyTable,
        blobRow(
          attachmentId: attachmentId,
          state: DirectMediaBlobCustodyState.outgoingStored,
          recipientPeerId: purgeContact,
          contactAccountPeerId: purgeContact,
          recipientMlKemPublicKey: 'mlkem-$purgeContact',
          expiresAtMs: 1900000600000,
          custodyRelayPeerId: 'relay-purge',
        ).toMap(),
      );
      // Two INCOMING obligations: one carries the linked logical-contact
      // marker, one keeps the historical NULL marker — BOTH must survive.
      await current.insert(
        kDirectMediaBlobCustodyTable,
        blobRow(
          attachmentId: 'purge-blob-incoming-marked',
          state: DirectMediaBlobCustodyState.incomingCommitted,
          contactAccountPeerId: purgeContact,
          expiresAtMs: 1900000700000,
        ).toMap(),
      );
      await current.insert(
        kDirectMediaBlobCustodyTable,
        blobRow(
          attachmentId: 'purge-blob-incoming-null',
          state: DirectMediaBlobCustodyState.incomingAckPending,
          expiresAtMs: 1900000800000,
          custodyRelayPeerId: 'relay-purge-source',
        ).toMap(),
      );
      final incomingBefore = await current.query(
        kDirectMediaBlobCustodyTable,
        where: "direction = 'incoming'",
        orderBy: 'attachment_id ASC',
      );

      final result = await dbPurgeDirectContactConversationAndContact(
        current,
        purgeContact,
      );
      expect(result.deletedContact, isTrue);

      // Outgoing linked rows transitioned to cleanup so the shared artifact
      // drains through the incumbent last-reference lifecycle.
      final outgoingAfter = await current.query(
        kDirectMediaBlobCustodyTable,
        where: "direction = 'outgoing'",
        orderBy: 'recipient_peer_id ASC',
      );
      expect(outgoingAfter, hasLength(2));
      for (final row in outgoingAfter) {
        expect(row['state'], 'outgoing_cleanup_pending');
        expect(row['contact_account_peer_id'], purgeContact);
      }

      // Incoming committed/ACK-pending obligations survive byte-identical:
      // they finish their own ACK/expiry convergence.
      expect(
        await current.query(
          kDirectMediaBlobCustodyTable,
          where: "direction = 'incoming'",
          orderBy: 'attachment_id ASC',
        ),
        incomingBefore,
      );

      // The logical conversation itself is gone: v108/v109 rows, messages
      // and the contact row.
      expect(await remainingFor('direct_inbox_custody_outbox', 'message_id'), [
        'other-m1',
      ]);
      expect(
        await remainingFor('direct_reaction_inbox_custody_outbox', 'event_id'),
        ['other-e1'],
      );
      expect(await remainingFor('messages', 'id'), ['other-m1']);
      expect(await remainingFor('contacts', 'peer_id'), [otherContact]);
    });
  });
}
