/// Integration test: Full DB migration chain.
///
/// Verifies:
/// 1a. Fresh install creates all tables with correct schema
/// 1b. Step-by-step upgrade preserves seeded data
/// 1c. Idempotent migrations can be re-run safely

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:flutter_app/core/database/helpers/messages_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/introductions_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/introduction_outbox_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/pending_introduction_responses_db_helpers.dart';
import 'package:flutter_app/core/database/migrations/001_identity_table.dart';
import 'package:flutter_app/core/database/migrations/002_messages_table.dart';
import 'package:flutter_app/core/database/migrations/003_mlkem_keys.dart';
import 'package:flutter_app/core/database/migrations/004_nullify_secret_columns.dart';
import 'package:flutter_app/core/database/migrations/005_secret_null_checks.dart';
import 'package:flutter_app/core/database/migrations/006_read_at_column.dart';
import 'package:flutter_app/core/database/migrations/007_archive_columns.dart';
import 'package:flutter_app/core/database/migrations/008_block_columns.dart';
import 'package:flutter_app/core/database/migrations/009_quoted_message_id.dart';
import 'package:flutter_app/core/database/migrations/010_media_attachments.dart';
import 'package:flutter_app/core/database/migrations/042_media_attachment_reliability_columns.dart';
import 'package:flutter_app/core/database/migrations/011_avatar_version.dart';
import 'package:flutter_app/core/database/migrations/012_transport_column.dart';
import 'package:flutter_app/core/database/migrations/013_waveform_column.dart';
import 'package:flutter_app/core/database/migrations/014_wire_envelope_column.dart';
import 'package:flutter_app/core/database/migrations/015_message_status_cleanup.dart';
import 'package:flutter_app/core/database/migrations/016_message_reactions.dart';
import 'package:flutter_app/core/database/migrations/017_groups_tables.dart';
import 'package:flutter_app/core/database/migrations/018_group_messages_tables.dart';
import 'package:flutter_app/core/database/migrations/019_introductions_table.dart';
import 'package:flutter_app/core/database/migrations/020_intro_banner_columns.dart';
import 'package:flutter_app/core/database/migrations/021_contact_introduced_by.dart';
import 'package:flutter_app/core/database/migrations/022_introduction_keys.dart';
import 'package:flutter_app/core/database/migrations/023_introduction_recipient_keys.dart';
import 'package:flutter_app/core/database/migrations/024_contact_introduced_by_peer_id.dart';
import 'package:flutter_app/core/database/migrations/025_introduction_already_connected_status.dart';
import 'package:flutter_app/core/database/migrations/026_group_quoted_message_id.dart';
import 'package:flutter_app/core/database/migrations/043_messages_edited_at.dart';
import 'package:flutter_app/core/database/migrations/044_messages_deleted_state.dart';
import 'package:flutter_app/core/database/migrations/045_inbox_staging_entries.dart';
import 'package:flutter_app/core/database/migrations/046_pending_introduction_responses.dart';
import 'package:flutter_app/core/database/migrations/047_introduction_outbox.dart';
import 'package:flutter_app/core/secure_storage/migrate_secrets_to_secure_storage.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository_impl.dart';
import 'package:flutter_app/features/introduction/domain/models/introduction_model.dart';
import 'package:flutter_app/features/introduction/domain/models/pending_introduction_response.dart';
import 'package:flutter_app/features/introduction/domain/repositories/introduction_repository_impl.dart';

import '../../../core/secure_storage/fake_secure_key_store.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;

  tearDown(() async {
    try {
      await db.close();
    } catch (_) {}
  });

  /// Helper: get table names in DB
  Future<List<String>> getTableNames(Database db) async {
    final rows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'",
    );
    return rows.map((r) => r['name'] as String).toList()..sort();
  }

  /// Helper: get column names for a table
  Future<List<String>> getColumnNames(Database db, String table) async {
    final rows = await db.rawQuery('PRAGMA table_info($table)');
    return rows.map((r) => r['name'] as String).toList();
  }

  Future<void> runFreshInstallMigrations(Database db) async {
    await runIdentityTableMigration(db);
    await runMessagesTableMigration(db);
    await runMlKemKeysMigration(db);
    await runSecretNullChecksMigration(db);
    await runReadAtColumnMigration(db);
    await runArchiveColumnsMigration(db);
    await runBlockColumnsMigration(db);
    await runQuotedMessageIdMigration(db);
    await runMediaAttachmentsMigration(db);
    await runMediaAttachmentReliabilityColumnsMigration(db);
    await runAvatarVersionMigration(db);
    await runTransportColumnMigration(db);
    await runWaveformColumnMigration(db);
    await runWireEnvelopeMigration(db);
    await runMessageStatusCleanupMigration(db);
    await runMessageReactionsMigration(db);
    await runGroupsTablesMigration(db);
    await runGroupMessagesTablesMigration(db);
    await runIntroductionsTableMigration(db);
    await runIntroBannerColumnsMigration(db);
    await runContactIntroducedByMigration(db);
    await runIntroductionKeysMigration(db);
    await runIntroductionRecipientKeysMigration(db);
    await runContactIntroducedByPeerIdMigration(db);
    await runIntroductionAlreadyConnectedMigration(db);
    await runGroupQuotedMessageIdMigration(db);
    await runMessagesEditedAtMigration(db);
    await runMessagesDeletedStateMigration(db);
    await runInboxStagingEntriesMigration(db);
    await runPendingIntroductionResponsesMigration(db);
    await runIntroductionOutboxMigration(db);
  }

  Future<void> runUpgradePathFromV1(
    Database db, {
    required FakeSecureKeyStore keyStore,
  }) async {
    await runMessagesTableMigration(db);
    await runMlKemKeysMigration(db);
    await runNullifySecretColumnsMigration(db);
    await migrateSecretsToSecureStorage(db: db, secureKeyStore: keyStore);
    await runSecretNullChecksMigration(db);
    await runReadAtColumnMigration(db);
    await runArchiveColumnsMigration(db);
    await runBlockColumnsMigration(db);
    await runQuotedMessageIdMigration(db);
    await runMediaAttachmentsMigration(db);
    await runMediaAttachmentReliabilityColumnsMigration(db);
    await runAvatarVersionMigration(db);
    await runTransportColumnMigration(db);
    await runWaveformColumnMigration(db);
    await runWireEnvelopeMigration(db);
    await runMessageStatusCleanupMigration(db);
    await runMessageReactionsMigration(db);
    await runGroupsTablesMigration(db);
    await runGroupMessagesTablesMigration(db);
    await runIntroductionsTableMigration(db);
    await runIntroBannerColumnsMigration(db);
    await runContactIntroducedByMigration(db);
    await runIntroductionKeysMigration(db);
    await runIntroductionRecipientKeysMigration(db);
    await runContactIntroducedByPeerIdMigration(db);
    await runIntroductionAlreadyConnectedMigration(db);
    await runGroupQuotedMessageIdMigration(db);
    await runMessagesEditedAtMigration(db);
    await runMessagesDeletedStateMigration(db);
    await runInboxStagingEntriesMigration(db);
    await runPendingIntroductionResponsesMigration(db);
    await runIntroductionOutboxMigration(db);
  }

  MessageRepositoryImpl buildMessageRepository(Database db) {
    return MessageRepositoryImpl(
      dbInsertMessage: (row) => dbInsertMessage(db, row),
      dbLoadMessagesForContact: (contactPeerId) =>
          dbLoadMessagesForContact(db, contactPeerId),
      dbLoadLatestMessageForContact: (contactPeerId) =>
          dbLoadLatestMessageForContact(db, contactPeerId),
      dbUpdateMessageStatus: (id, status) =>
          dbUpdateMessageStatus(db, id, status),
      dbLoadMessage: (id) => dbLoadMessage(db, id),
      dbCountMessagesForContact: (contactPeerId) =>
          dbCountMessagesForContact(db, contactPeerId),
      dbMarkConversationAsRead: (contactPeerId) =>
          dbMarkConversationAsRead(db, contactPeerId),
      dbCountUnreadForContact: (contactPeerId) =>
          dbCountUnreadForContact(db, contactPeerId),
      dbCountTotalUnread: () => dbCountTotalUnread(db),
      dbCountTotalUnreadExcludingArchived: () =>
          dbCountTotalUnreadExcludingArchived(db),
      dbDeleteMessagesForContact: (contactPeerId) =>
          dbDeleteMessagesForContact(db, contactPeerId),
      dbDeleteMessage: (id) => dbDeleteMessage(db, id),
      dbLoadMessagesPage: (contactPeerId, {limit = 50, beforeTimestamp}) =>
          dbLoadMessagesPage(
            db,
            contactPeerId,
            limit: limit,
            beforeTimestamp: beforeTimestamp,
          ),
      dbLoadFailedOutgoingMessages: () => dbLoadFailedOutgoingMessages(db),
      dbLoadUnackedOutgoingMessages: ({required olderThan, limit = 100}) =>
          dbLoadUnackedOutgoingMessages(db, olderThan: olderThan, limit: limit),
      dbLoadConversationThreadSummaries: (contactPeerIds) =>
          dbLoadConversationThreadSummaries(db, contactPeerIds),
      dbRecoverStuckSendingMessages: ({required olderThan, limit = 100}) =>
          dbRecoverStuckSendingMessages(db, olderThan: olderThan, limit: limit),
      dbUpdateWireEnvelope: (id, wireEnvelope) =>
          dbUpdateWireEnvelope(db, id, wireEnvelope),
      dbLoadStuckSendingOutgoingMessages: ({required olderThan, limit = 100}) =>
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
    );
  }

  IntroductionRepositoryImpl buildIntroductionRepository(Database db) {
    return IntroductionRepositoryImpl(
      dbInsertIntroduction: (row) => dbInsertIntroduction(db, row),
      dbLoadIntroduction: (id) => dbLoadIntroduction(db, id),
      dbDeleteIntroduction: (id) => dbDeleteIntroduction(db, id),
      dbLoadIntroductionsByRecipient: (recipientId) =>
          dbLoadIntroductionsByRecipient(db, recipientId),
      dbLoadIntroductionsByIntroduced: (introducedId) =>
          dbLoadIntroductionsByIntroduced(db, introducedId),
      dbLoadIntroductionsByIntroducer: (introducerId) =>
          dbLoadIntroductionsByIntroducer(db, introducerId),
      dbLoadIntroductionsForRecipientAndIntroducer:
          (recipientId, introducerId) =>
              dbLoadIntroductionsForRecipientAndIntroducer(
                db,
                recipientId,
                introducerId,
              ),
      dbUpdateRecipientStatus: (id, status, respondedAt) =>
          dbUpdateRecipientStatus(db, id, status, respondedAt),
      dbUpdateIntroducedStatus: (id, status, respondedAt) =>
          dbUpdateIntroducedStatus(db, id, status, respondedAt),
      dbUpdateOverallStatus: (id, status) =>
          dbUpdateOverallStatus(db, id, status),
      dbLoadPendingIntroductionsForUser: (peerId) =>
          dbLoadPendingIntroductionsForUser(db, peerId),
      dbCountPendingIntroductions: (peerId) =>
          dbCountPendingIntroductions(db, peerId),
      dbUpsertPendingIntroductionResponse: (row) =>
          dbUpsertPendingIntroductionResponse(db, row),
      dbLoadPendingIntroductionResponses: (introductionId) =>
          dbLoadPendingIntroductionResponses(db, introductionId),
      dbDeletePendingIntroductionResponse: (responseKey) =>
          dbDeletePendingIntroductionResponse(db, responseKey),
      dbUpsertIntroductionOutboxDelivery: (row) =>
          dbUpsertIntroductionOutboxDelivery(db, row),
      dbLoadIntroductionOutboxDeliveriesForIntroduction: (introductionId) =>
          dbLoadIntroductionOutboxDeliveriesForIntroduction(db, introductionId),
      dbLoadRetryableIntroductionOutboxDeliveries:
          ({required olderThan, limit = 100}) =>
              dbLoadRetryableIntroductionOutboxDeliveries(
                db,
                olderThan: olderThan,
                limit: limit,
              ),
      dbDeleteIntroductionOutboxDelivery: (deliveryId) =>
          dbDeleteIntroductionOutboxDelivery(db, deliveryId),
      dbDeleteIntroductionOutboxDeliveriesForIntroduction: (introductionId) =>
          dbDeleteIntroductionOutboxDeliveriesForIntroduction(
            db,
            introductionId,
          ),
    );
  }

  group('Full DB migration chain', () {
    test('1a. Fresh install path creates all tables with correct schema', () async {
      db = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(version: 1),
      );

      // Run the full fresh-install migration chain (matching main.dart onCreate)
      await runFreshInstallMigrations(db);

      // Verify: current production tables exist
      final tables = await getTableNames(db);
      expect(
        tables,
        containsAll([
          'identity',
          'contacts',
          'contact_requests',
          'messages',
          'media_attachments',
          'message_reactions',
          'groups',
          'group_members',
          'group_keys',
          'group_messages',
          'introductions',
          'introduction_outbox_deliveries',
          'inbox_staging_entries',
          'pending_introduction_responses',
        ]),
      );

      // Verify: identity has CHECK constraints (insert non-null private_key throws)
      expect(
        () async => await db.insert('identity', {
          'id': 99,
          'peer_id': 'test',
          'public_key': 'pk',
          'private_key': 'should_fail',
          'username': 'Test',
          'created_at': '2026-01-01',
          'updated_at': '2026-01-01',
        }),
        throwsA(anything),
      );

      // Verify: messages has read_at, quoted_message_id, transport columns
      final msgCols = await getColumnNames(db, 'messages');
      expect(
        msgCols,
        containsAll(['read_at', 'quoted_message_id', 'transport']),
      );

      // Verify: contacts has ml_kem_public_key, is_archived, is_blocked, avatar_version
      final contactCols = await getColumnNames(db, 'contacts');
      expect(
        contactCols,
        containsAll([
          'ml_kem_public_key',
          'is_archived',
          'is_blocked',
          'avatar_version',
        ]),
      );

      // Verify: media_attachments has all expected columns
      final mediaCols = await getColumnNames(db, 'media_attachments');
      expect(
        mediaCols,
        containsAll([
          'id',
          'message_id',
          'mime',
          'size',
          'media_type',
          'width',
          'height',
          'duration_ms',
          'local_path',
          'download_status',
          'created_at',
          'upload_retry_count',
        ]),
      );

      // Verify: index exists on media_attachments
      final indexes = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='media_attachments'",
      );
      expect(
        indexes.map((r) => r['name'] as String),
        contains('idx_media_attachments_message'),
      );

      // Verify: message_reactions has all expected columns
      final reactionCols = await getColumnNames(db, 'message_reactions');
      expect(
        reactionCols,
        containsAll([
          'id',
          'message_id',
          'emoji',
          'sender_peer_id',
          'timestamp',
          'created_at',
        ]),
      );

      // Verify: index exists on message_reactions
      final reactionIndexes = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='message_reactions'",
      );
      expect(
        reactionIndexes.map((r) => r['name'] as String),
        contains('idx_message_reactions_message'),
      );

      // Verify: group_messages includes quote support
      final groupMessageCols = await getColumnNames(db, 'group_messages');
      expect(
        groupMessageCols,
        containsAll([
          'group_id',
          'sender_peer_id',
          'text',
          'timestamp',
          'quoted_message_id',
        ]),
      );
    });

    test('1b. Step-by-step upgrade preserves seeded data', () async {
      db = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(version: 1),
      );

      // Step 1: Run migration 001 (identity, contacts, contact_requests)
      await runIdentityTableMigration(db);

      // Seed data
      await db.insert('identity', {
        'id': 1,
        'peer_id': 'peer-abc',
        'public_key': 'pk-abc',
        'private_key': 'sk-abc',
        'mnemonic12':
            'word1 word2 word3 word4 word5 word6 word7 word8 word9 word10 word11 word12',
        'username': 'TestUser',
        'created_at': '2026-01-01T00:00:00Z',
        'updated_at': '2026-01-01T00:00:00Z',
      });
      await db.insert('contacts', {
        'peer_id': 'contact-1',
        'public_key': 'pk-c1',
        'rendezvous': '/rv/1',
        'username': 'ContactOne',
        'signature': 'sig-c1',
        'scanned_at': '2026-01-01T00:00:00Z',
      });
      await db.insert('contact_requests', {
        'peer_id': 'req-1',
        'public_key': 'pk-r1',
        'rendezvous': '/rv/r1',
        'username': 'Requester',
        'signature': 'sig-r1',
        'received_at': '2026-01-01T00:00:00Z',
        'status': 'pending',
      });

      // Step 2: Migration 002 -> messages table
      await runMessagesTableMigration(db);
      final tables2 = await getTableNames(db);
      expect(tables2, contains('messages'));

      // Step 3: Migration 003 -> ML-KEM columns
      await runMlKemKeysMigration(db);
      final identityCols3 = await getColumnNames(db, 'identity');
      expect(
        identityCols3,
        containsAll(['ml_kem_public_key', 'ml_kem_secret_key']),
      );
      final contactCols3 = await getColumnNames(db, 'contacts');
      expect(contactCols3, contains('ml_kem_public_key'));

      // Step 4: Migration 004 -> nullable secrets
      await runNullifySecretColumnsMigration(db);
      // Verify private_key still has value (not yet migrated)
      final identityRow4 = await db.query(
        'identity',
        where: 'id = ?',
        whereArgs: [1],
      );
      expect(identityRow4.first['private_key'], 'sk-abc');

      // Run secrets migration
      final keyStore = FakeSecureKeyStore();
      await migrateSecretsToSecureStorage(db: db, secureKeyStore: keyStore);

      // Verify secrets moved to secure storage
      expect(await keyStore.read('identity_private_key'), 'sk-abc');
      expect(
        await keyStore.read('identity_mnemonic12'),
        'word1 word2 word3 word4 word5 word6 word7 word8 word9 word10 word11 word12',
      );

      // Verify DB columns are null
      final identityRow4b = await db.query(
        'identity',
        where: 'id = ?',
        whereArgs: [1],
      );
      expect(identityRow4b.first['private_key'], isNull);
      expect(identityRow4b.first['mnemonic12'], isNull);

      // Step 5: Migration 005 -> CHECK constraints
      await runSecretNullChecksMigration(db);
      // Verify CHECK constraints active (non-null private_key throws)
      expect(
        () async => await db.update(
          'identity',
          {'private_key': 'should-fail'},
          where: 'id = ?',
          whereArgs: [1],
        ),
        throwsA(anything),
      );

      // Step 6: Migration 006 -> read_at column
      await runReadAtColumnMigration(db);
      final msgCols6 = await getColumnNames(db, 'messages');
      expect(msgCols6, contains('read_at'));

      // Insert messages and verify mark-read works
      await db.insert('messages', {
        'id': 'msg-1',
        'contact_peer_id': 'contact-1',
        'sender_peer_id': 'contact-1',
        'text': 'Hello',
        'timestamp': '2026-01-01T00:00:00Z',
        'status': 'delivered',
        'is_incoming': 1,
        'created_at': '2026-01-01T00:00:00Z',
      });
      final msgBefore = await db.query(
        'messages',
        where: 'id = ?',
        whereArgs: ['msg-1'],
      );
      expect(msgBefore.first['read_at'], isNull);

      // Step 7: Migration 007 -> archive columns
      await runArchiveColumnsMigration(db);
      final contactCols7 = await getColumnNames(db, 'contacts');
      expect(contactCols7, containsAll(['is_archived', 'archived_at']));

      // Step 8: Migration 008 -> block columns
      await runBlockColumnsMigration(db);
      final contactCols8 = await getColumnNames(db, 'contacts');
      expect(contactCols8, containsAll(['is_blocked', 'blocked_at']));

      // Step 9: Migration 009 -> quoted_message_id
      await runQuotedMessageIdMigration(db);
      final msgCols9 = await getColumnNames(db, 'messages');
      expect(msgCols9, contains('quoted_message_id'));

      // Step 10: Migration 010 -> media_attachments
      await runMediaAttachmentsMigration(db);
      final tables10 = await getTableNames(db);
      expect(tables10, contains('media_attachments'));

      // Step 11: Migration 011 -> avatar_version
      await runAvatarVersionMigration(db);
      final identityCols11 = await getColumnNames(db, 'identity');
      expect(identityCols11, contains('avatar_version'));
      final contactCols11 = await getColumnNames(db, 'contacts');
      expect(contactCols11, contains('avatar_version'));

      // Step 12: Migration 012 -> transport column
      await runTransportColumnMigration(db);
      final msgCols12 = await getColumnNames(db, 'messages');
      expect(msgCols12, contains('transport'));

      // Verify existing message (msg-1 from Step 6) has null transport
      final existingMsg12 = await db.query(
        'messages',
        where: 'id = ?',
        whereArgs: ['msg-1'],
      );
      expect(existingMsg12.first['transport'], isNull);

      // Insert a message with transport='wifi' and verify
      await db.insert('messages', {
        'id': 'msg-wifi-12',
        'contact_peer_id': 'contact-1',
        'sender_peer_id': 'contact-1',
        'text': 'wifi transport message',
        'timestamp': '2026-02-01T00:00:00Z',
        'status': 'delivered',
        'is_incoming': 1,
        'created_at': '2026-02-01T00:00:00Z',
        'transport': 'wifi',
      });
      final wifiMsg = await db.query(
        'messages',
        where: 'id = ?',
        whereArgs: ['msg-wifi-12'],
      );
      expect(wifiMsg.first['transport'], 'wifi');

      // Step 13: Migration 013 -> waveform column
      await runWaveformColumnMigration(db);
      final mediaCols13 = await getColumnNames(db, 'media_attachments');
      expect(mediaCols13, contains('waveform'));

      // Step 14: Migration 014 -> wire_envelope column
      await runWireEnvelopeMigration(db);
      final msgCols14 = await getColumnNames(db, 'messages');
      expect(msgCols14, contains('wire_envelope'));

      // Step 15: Migration 015 -> message status cleanup
      await runMessageStatusCleanupMigration(db);

      // Step 16: Migration 016 -> message_reactions table
      await runMessageReactionsMigration(db);
      final tables16 = await getTableNames(db);
      expect(tables16, contains('message_reactions'));

      // Verify reaction table schema
      final reactionCols = await getColumnNames(db, 'message_reactions');
      expect(
        reactionCols,
        containsAll([
          'id',
          'message_id',
          'emoji',
          'sender_peer_id',
          'timestamp',
          'created_at',
        ]),
      );

      // Verify UNIQUE constraint on (message_id, sender_peer_id)
      await db.insert('message_reactions', {
        'id': 'r1',
        'message_id': 'msg-1',
        'emoji': '👍',
        'sender_peer_id': 'sender-1',
        'timestamp': '2026-02-27T10:00:00.000Z',
        'created_at': '2026-02-27T10:00:01.000Z',
      });
      // Second insert with same message+sender should fail
      expect(
        () async => await db.insert('message_reactions', {
          'id': 'r2',
          'message_id': 'msg-1',
          'emoji': '❤️',
          'sender_peer_id': 'sender-1',
          'timestamp': '2026-02-27T10:01:00.000Z',
          'created_at': '2026-02-27T10:01:01.000Z',
        }),
        throwsA(anything),
      );

      // Step 17: Migration 017 -> groups tables
      await runGroupsTablesMigration(db);
      final tables17 = await getTableNames(db);
      expect(tables17, containsAll(['groups', 'group_members']));

      // Step 18: Migration 018 -> group keys + group messages tables
      await runGroupMessagesTablesMigration(db);
      final tables18 = await getTableNames(db);
      expect(tables18, containsAll(['group_keys', 'group_messages']));

      // Step 19-25: introduction and contact provenance migrations
      await runIntroductionsTableMigration(db);
      await runIntroBannerColumnsMigration(db);
      await runContactIntroducedByMigration(db);
      await runIntroductionKeysMigration(db);
      await runIntroductionRecipientKeysMigration(db);
      await runContactIntroducedByPeerIdMigration(db);
      await runIntroductionAlreadyConnectedMigration(db);

      // Seed a v25-era group message before the v26 quote column exists.
      await db.insert('group_messages', {
        'id': 'group-msg-1',
        'group_id': 'group-1',
        'sender_peer_id': 'peer-abc',
        'sender_username': 'Alice',
        'text': 'Pre-v26 group message',
        'timestamp': '2026-03-01T00:00:00Z',
        'key_generation': 0,
        'status': 'delivered',
        'is_incoming': 1,
        'created_at': '2026-03-01T00:00:00Z',
      });

      // Step 26: Migration 026 -> group quoted_message_id
      await runGroupQuotedMessageIdMigration(db);
      final groupCols26 = await getColumnNames(db, 'group_messages');
      expect(groupCols26, contains('quoted_message_id'));

      final existingGroupMessage = await db.query(
        'group_messages',
        where: 'id = ?',
        whereArgs: ['group-msg-1'],
      );
      expect(existingGroupMessage.first['quoted_message_id'], isNull);

      // Final: verify seeded data is preserved
      final identity = await db.query(
        'identity',
        where: 'id = ?',
        whereArgs: [1],
      );
      expect(identity.first['peer_id'], 'peer-abc');
      expect(identity.first['public_key'], 'pk-abc');
      expect(identity.first['username'], 'TestUser');
      // Secrets should be null (migrated to secure storage)
      expect(identity.first['private_key'], isNull);

      final contact = await db.query(
        'contacts',
        where: 'peer_id = ?',
        whereArgs: ['contact-1'],
      );
      expect(contact.first['username'], 'ContactOne');
      expect(contact.first['public_key'], 'pk-c1');

      final request = await db.query(
        'contact_requests',
        where: 'peer_id = ?',
        whereArgs: ['req-1'],
      );
      expect(request.first['username'], 'Requester');
      expect(request.first['status'], 'pending');
    });

    test(
      '1c. migrated schema persists newly arrived incoming messages',
      () async {
        db = await databaseFactoryFfi.openDatabase(
          inMemoryDatabasePath,
          options: OpenDatabaseOptions(version: 1),
        );

        await runIdentityTableMigration(db);

        await db.insert('identity', {
          'id': 1,
          'peer_id': 'peer-migrated-self',
          'public_key': 'pk-self',
          'private_key': 'sk-self',
          'mnemonic12':
              'word1 word2 word3 word4 word5 word6 word7 word8 word9 word10 word11 word12',
          'username': 'MigratedUser',
          'created_at': '2026-01-01T00:00:00Z',
          'updated_at': '2026-01-01T00:00:00Z',
        });
        await db.insert('contacts', {
          'peer_id': 'contact-migrated',
          'public_key': 'pk-contact',
          'rendezvous': '/rv/contact',
          'username': 'Contact',
          'signature': 'sig-contact',
          'scanned_at': '2026-01-01T00:00:00Z',
        });

        final keyStore = FakeSecureKeyStore();
        await runUpgradePathFromV1(db, keyStore: keyStore);

        final messageRepo = buildMessageRepository(db);
        const timestamp = '2026-01-02T12:34:56.000Z';

        await messageRepo.saveMessage(
          const ConversationMessage(
            id: 'post-migration-msg-1',
            contactPeerId: 'contact-migrated',
            senderPeerId: 'contact-migrated',
            text: 'Delivered after migration',
            timestamp: timestamp,
            status: 'delivered',
            isIncoming: true,
            createdAt: timestamp,
            transport: 'inbox',
            wireEnvelope: '{"type":"chat","id":"post-migration-msg-1"}',
          ),
        );

        final messages = await messageRepo.getMessagesForContact(
          'contact-migrated',
        );
        expect(messages, hasLength(1));
        expect(messages.single.text, 'Delivered after migration');
        expect(messages.single.isIncoming, isTrue);
        expect(messages.single.transport, 'inbox');
        expect(messages.single.wireEnvelope, isNotNull);

        final latest = await messageRepo.getLatestMessageForContact(
          'contact-migrated',
        );
        expect(latest?.id, 'post-migration-msg-1');
        expect(
          await messageRepo.getUnreadCountForContact('contact-migrated'),
          1,
        );
      },
    );

    test(
      '1c. migrated schema persists newly arrived introductions and deferred responses',
      () async {
        db = await databaseFactoryFfi.openDatabase(
          inMemoryDatabasePath,
          options: OpenDatabaseOptions(version: 1),
        );

        await runIdentityTableMigration(db);

        await db.insert('identity', {
          'id': 1,
          'peer_id': 'peer-migrated-self',
          'public_key': 'pk-self',
          'private_key': 'sk-self',
          'mnemonic12':
              'word1 word2 word3 word4 word5 word6 word7 word8 word9 word10 word11 word12',
          'username': 'MigratedUser',
          'created_at': '2026-01-01T00:00:00Z',
          'updated_at': '2026-01-01T00:00:00Z',
        });
        await db.insert('contacts', {
          'peer_id': 'introducer-migrated',
          'public_key': 'pk-introducer',
          'rendezvous': '/rv/introducer',
          'username': 'Noor',
          'signature': 'sig-introducer',
          'scanned_at': '2026-01-01T00:00:00Z',
        });
        await db.insert('contacts', {
          'peer_id': 'contact-migrated',
          'public_key': 'pk-contact',
          'rendezvous': '/rv/contact',
          'username': 'Sarah',
          'signature': 'sig-contact',
          'scanned_at': '2026-01-01T00:00:00Z',
        });

        final keyStore = FakeSecureKeyStore();
        await runUpgradePathFromV1(db, keyStore: keyStore);

        final introRepo = buildIntroductionRepository(db);
        const introId = 'post-migration-intro-1';
        const createdAt = '2026-01-02T12:34:56.000Z';

        await introRepo.saveIntroduction(
          const IntroductionModel(
            id: introId,
            introducerId: 'introducer-migrated',
            recipientId: 'peer-migrated-self',
            introducedId: 'contact-migrated',
            introducerUsername: 'Noor',
            recipientUsername: 'MigratedUser',
            introducedUsername: 'Sarah',
            createdAt: createdAt,
            introducedPublicKey: 'pk-contact',
            introducedMlKemPublicKey: 'mlkem-pk-contact',
          ),
        );

        await introRepo.savePendingResponse(
          const PendingIntroductionResponse(
            responseKey: 'post-migration-intro-1::contact-migrated::accept',
            introductionId: introId,
            action: 'accept',
            responderId: 'contact-migrated',
            responderUsername: 'Sarah',
            createdAt: createdAt,
          ),
        );

        final loaded = await introRepo.getIntroduction(introId);
        expect(loaded, isNotNull);
        expect(loaded!.recipientId, 'peer-migrated-self');
        expect(loaded.introducedId, 'contact-migrated');
        expect(loaded.introducerUsername, 'Noor');
        expect(loaded.introducedMlKemPublicKey, 'mlkem-pk-contact');

        final pending = await introRepo.loadPendingResponses(introId);
        expect(pending, hasLength(1));
        expect(pending.single.responderId, 'contact-migrated');
        expect(pending.single.action, 'accept');

        final pendingForUser = await introRepo.getPendingIntroductionsForUser(
          'peer-migrated-self',
        );
        expect(pendingForUser, hasLength(1));
        expect(
          await introRepo.countPendingIntroductions('peer-migrated-self'),
          1,
        );
      },
    );

    test('1d. Idempotent migrations can be re-run safely', () async {
      db = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(version: 1),
      );

      // Run full chain first
      await runIdentityTableMigration(db);
      await runMessagesTableMigration(db);
      await runMlKemKeysMigration(db);
      await runNullifySecretColumnsMigration(db);

      final keyStore = FakeSecureKeyStore();
      await migrateSecretsToSecureStorage(db: db, secureKeyStore: keyStore);
      await runSecretNullChecksMigration(db);
      await runReadAtColumnMigration(db);
      await runArchiveColumnsMigration(db);
      await runBlockColumnsMigration(db);
      await runQuotedMessageIdMigration(db);
      await runMediaAttachmentsMigration(db);
      await runAvatarVersionMigration(db);
      await runTransportColumnMigration(db);
      await runWaveformColumnMigration(db);
      await runWireEnvelopeMigration(db);
      await runMessageStatusCleanupMigration(db);
      await runMessageReactionsMigration(db);
      await runGroupsTablesMigration(db);
      await runGroupMessagesTablesMigration(db);
      await runIntroductionsTableMigration(db);
      await runIntroBannerColumnsMigration(db);
      await runContactIntroducedByMigration(db);
      await runIntroductionKeysMigration(db);
      await runIntroductionRecipientKeysMigration(db);
      await runContactIntroducedByPeerIdMigration(db);
      await runIntroductionAlreadyConnectedMigration(db);
      await runGroupQuotedMessageIdMigration(db);

      // Seed data
      await db.insert('identity', {
        'id': 1,
        'peer_id': 'peer-test',
        'public_key': 'pk-test',
        'username': 'Test',
        'created_at': '2026-01-01',
        'updated_at': '2026-01-01',
      });

      // Re-run idempotent migrations
      await runSecretNullChecksMigration(db);
      await runReadAtColumnMigration(db);
      await runArchiveColumnsMigration(db);
      await runBlockColumnsMigration(db);
      await runQuotedMessageIdMigration(db);
      await runMediaAttachmentsMigration(db);
      await runAvatarVersionMigration(db);
      await runTransportColumnMigration(db);
      await runWaveformColumnMigration(db);
      await runWireEnvelopeMigration(db);
      await runMessageStatusCleanupMigration(db);
      await runMessageReactionsMigration(db);
      await runGroupsTablesMigration(db);
      await runGroupMessagesTablesMigration(db);
      await runGroupQuotedMessageIdMigration(db);

      // Re-run secrets migration (should be no-op)
      await migrateSecretsToSecureStorage(db: db, secureKeyStore: keyStore);

      // Data should be intact
      final identity = await db.query(
        'identity',
        where: 'id = ?',
        whereArgs: [1],
      );
      expect(identity.first['peer_id'], 'peer-test');
    });

    test(
      '1e. v25 to v26 upgrade adds group quoted_message_id safely',
      () async {
        db = await databaseFactoryFfi.openDatabase(
          inMemoryDatabasePath,
          options: OpenDatabaseOptions(version: 25),
        );

        await runIdentityTableMigration(db);
        await runMessagesTableMigration(db);
        await runMlKemKeysMigration(db);
        await runSecretNullChecksMigration(db);
        await runReadAtColumnMigration(db);
        await runArchiveColumnsMigration(db);
        await runBlockColumnsMigration(db);
        await runQuotedMessageIdMigration(db);
        await runMediaAttachmentsMigration(db);
        await runAvatarVersionMigration(db);
        await runTransportColumnMigration(db);
        await runWaveformColumnMigration(db);
        await runWireEnvelopeMigration(db);
        await runMessageStatusCleanupMigration(db);
        await runMessageReactionsMigration(db);
        await runGroupsTablesMigration(db);
        await runGroupMessagesTablesMigration(db);
        await runIntroductionsTableMigration(db);
        await runIntroBannerColumnsMigration(db);
        await runContactIntroducedByMigration(db);
        await runIntroductionKeysMigration(db);
        await runIntroductionRecipientKeysMigration(db);
        await runContactIntroducedByPeerIdMigration(db);
        await runIntroductionAlreadyConnectedMigration(db);

        await db.insert('group_messages', {
          'id': 'group-msg-v25',
          'group_id': 'group-1',
          'sender_peer_id': 'peer-a',
          'sender_username': 'Alice',
          'text': 'Legacy group message',
          'timestamp': '2026-03-01T00:00:00Z',
          'key_generation': 0,
          'status': 'delivered',
          'is_incoming': 1,
          'created_at': '2026-03-01T00:00:00Z',
        });

        await runGroupQuotedMessageIdMigration(db);

        final groupCols = await getColumnNames(db, 'group_messages');
        expect(groupCols, contains('quoted_message_id'));

        final legacyRow = await db.query(
          'group_messages',
          where: 'id = ?',
          whereArgs: ['group-msg-v25'],
        );
        expect(legacyRow.first['quoted_message_id'], isNull);

        await db.insert('group_messages', {
          'id': 'group-msg-v26',
          'group_id': 'group-1',
          'sender_peer_id': 'peer-b',
          'sender_username': 'Bob',
          'text': 'Quoted upgrade reply',
          'timestamp': '2026-03-02T00:00:00Z',
          'quoted_message_id': 'group-msg-v25',
          'key_generation': 0,
          'status': 'delivered',
          'is_incoming': 1,
          'created_at': '2026-03-02T00:00:00Z',
        });

        final upgradedRow = await db.query(
          'group_messages',
          where: 'id = ?',
          whereArgs: ['group-msg-v26'],
        );
        expect(upgradedRow.first['quoted_message_id'], 'group-msg-v25');
      },
    );
  });
}
