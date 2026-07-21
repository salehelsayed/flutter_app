// Integration test: Full DB migration chain.
//
// Verifies:
// 1a. Fresh install creates all tables with correct schema
// 1b. Step-by-step upgrade preserves seeded data
// 1c. Idempotent migrations can be re-run safely

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:flutter_app/core/database/app_database_version.dart';
import 'package:flutter_app/core/database/production_migration_registry.dart';

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
import 'package:flutter_app/core/database/migrations/048_groups_last_membership_event_at.dart';
import 'package:flutter_app/core/database/migrations/049_groups_metadata_columns.dart';
import 'package:flutter_app/core/database/migrations/050_groups_mute_column.dart';
import 'package:flutter_app/core/database/migrations/051_pending_group_invites.dart';
import 'package:flutter_app/core/database/migrations/052_groups_dissolve_columns.dart';
import 'package:flutter_app/core/database/migrations/053_groups_backlog_retention_columns.dart';
import 'package:flutter_app/core/database/migrations/054_group_reaction_replay_outbox.dart';
import 'package:flutter_app/core/database/migrations/055_group_invite_revocations.dart';
import 'package:flutter_app/core/database/migrations/056_group_invite_consumptions.dart';
import 'package:flutter_app/core/database/migrations/057_group_member_permissions.dart';
import 'package:flutter_app/core/database/migrations/058_media_attachment_integrity_columns.dart';
import 'package:flutter_app/core/database/migrations/059_media_attachment_encryption_columns.dart';
import 'package:flutter_app/core/database/migrations/060_group_event_log.dart';
import 'package:flutter_app/core/database/migrations/061_group_message_transport_peer_id.dart';
import 'package:flutter_app/core/database/migrations/062_group_member_device_identities.dart';
import 'package:flutter_app/core/database/migrations/063_group_pending_key_repairs.dart';
import 'package:flutter_app/core/database/migrations/064_group_welcome_key_package_tombstones.dart';
import 'package:flutter_app/core/database/migrations/065_group_history_gap_repairs.dart';
import 'package:flutter_app/core/database/migrations/066_group_sync_receipts.dart';
import 'package:flutter_app/core/database/migrations/067_group_invite_delivery_attempts.dart';
import 'package:flutter_app/core/database/migrations/068_removed_group_member_snapshots.dart';
import 'package:flutter_app/core/database/migrations/069_group_message_local_deletions.dart';
import 'package:flutter_app/core/database/migrations/070_group_key_rotation_drafts.dart';
import 'package:flutter_app/core/database/migrations/071_pending_introduction_response_transport_sender.dart';
import 'package:flutter_app/core/database/migrations/072_group_pending_membership_messages.dart';
import 'package:flutter_app/core/database/migrations/073_group_message_last_send_attempt_at.dart';
import 'package:flutter_app/core/database/migrations/074_group_message_logical_delivery_id.dart';
import 'package:flutter_app/core/database/migrations/077_message_relay_custody.dart';
import 'package:flutter_app/core/database/migrations/078_group_pending_key_distributions.dart';
import 'package:flutter_app/core/database/migrations/079_message_dedup_key.dart';
import 'package:flutter_app/core/database/migrations/080_group_pending_key_repairs_status_index.dart';
import 'package:flutter_app/core/database/migrations/081_group_pending_reactions.dart';
import 'package:flutter_app/core/database/migrations/082_message_reaction_tombstone.dart';
import 'package:flutter_app/core/database/migrations/083_groups_last_membership_event_id.dart';
import 'package:flutter_app/core/database/migrations/086_pending_group_broadcasts.dart';
import 'package:flutter_app/core/database/migrations/100_direct_private_media_lifecycle.dart';
import 'package:flutter_app/core/database/migrations/101_group_private_media_lifecycle.dart';
import 'package:flutter_app/core/database/migrations/102_groups_self_removed_at.dart';
import 'package:flutter_app/core/database/migrations/103_group_exit_intents.dart';
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
    // 228 TC-228-01: the fresh-install chain is no longer hand-maintained —
    // it delegates to the shared, order-locked production registry so this
    // fixture can never silently drift from main.dart again.
    await runProductionOnCreate(db, 95);

    final chainIndexNames = (await db.query(
      'sqlite_master',
      columns: ['name'],
      where: "type = 'index'",
    )).map((row) => row['name'] as String?).whereType<String>().toList();
    expect(
      chainIndexNames,
      contains('idx_group_pending_key_repairs_status_created'),
    );

    final groupCols53 = await getColumnNames(db, 'groups');
    expect(groupCols53, contains('last_membership_event_at'));
    expect(groupCols53, contains('last_membership_event_id'));
    expect(groupCols53, contains('avatar_blob_id'));
    expect(groupCols53, contains('avatar_mime'));
    expect(groupCols53, contains('avatar_path'));
    expect(groupCols53, contains('last_metadata_event_at'));
    expect(groupCols53, contains('is_muted'));
    expect(groupCols53, contains('is_dissolved'));
    expect(groupCols53, contains('dissolved_at'));
    expect(groupCols53, contains('dissolved_by'));
    expect(groupCols53, contains('last_backlog_expired_at'));
    expect(groupCols53, contains('last_backlog_retained_at'));
    final groupMemberCols57 = await getColumnNames(db, 'group_members');
    expect(groupMemberCols57, contains('permissions_json'));
    expect(groupMemberCols57, contains('devices_json'));
    expect(await getTableNames(db), contains('pending_group_invites'));
    expect(await getTableNames(db), contains('group_reaction_replay_outbox'));
    expect(await getTableNames(db), contains('group_invite_revocations'));
    expect(await getTableNames(db), contains('pending_group_broadcasts'));
    expect(await getTableNames(db), contains('group_invite_consumptions'));
    expect(await getTableNames(db), contains('group_event_log'));
    expect(await getTableNames(db), contains('group_pending_key_repairs'));
    expect(await getTableNames(db), contains('group_history_gap_repairs'));
    expect(await getTableNames(db), contains('group_inbox_cursors'));
    expect(await getTableNames(db), contains('group_message_receipts'));
    expect(await getTableNames(db), contains('group_invite_delivery_attempts'));
    expect(await getTableNames(db), contains('removed_group_member_snapshots'));
    expect(await getTableNames(db), contains('group_message_local_deletions'));
    expect(await getTableNames(db), contains('group_key_rotation_drafts'));
    expect(
      await getTableNames(db),
      contains('group_pending_membership_messages'),
    );
    final groupMessageCols61 = await getColumnNames(db, 'group_messages');
    expect(groupMessageCols61, contains('transport_peer_id'));
    expect(groupMessageCols61, contains('last_send_attempt_at'));
    expect(groupMessageCols61, contains('logical_delivery_id'));
    // Finding 05 Phase 4 (migration 087) backoff columns.
    expect(groupMessageCols61, contains('retry_attempt_count'));
    expect(groupMessageCols61, contains('next_eligible_at'));
    // Finding 05 Phase 3 (migration 088) bounded per-group rejoin retry state.
    expect(await getTableNames(db), contains('group_rejoin_state'));
    final pendingIntroResponseCols71 = await getColumnNames(
      db,
      'pending_introduction_responses',
    );
    expect(pendingIntroResponseCols71, contains('transport_sender_peer_id'));
    // 12-P2 Part B (migration 084) per-member device snapshots.
    expect(await getTableNames(db), contains('group_member_device_snapshots'));
    final deviceSnapshotCols84 = await getColumnNames(
      db,
      'group_member_device_snapshots',
    );
    expect(
      deviceSnapshotCols84,
      containsAll([
        'group_id',
        'peer_id',
        'public_key',
        'ml_kem_public_key',
        'devices_json',
        'saved_at',
      ]),
    );
    // 12-P2 Part B (migration 085) pending sibling devices.
    expect(await getTableNames(db), contains('pending_sibling_devices'));
    final pendingSiblingCols85 = await getColumnNames(
      db,
      'pending_sibling_devices',
    );
    expect(
      pendingSiblingCols85,
      containsAll([
        'group_id',
        'member_peer_id',
        'device_id',
        'transport_peer_id',
        'device_signing_public_key',
        'ml_kem_public_key',
        'key_package_id',
        'verified_account_signing_public_key',
        'announced_at',
      ]),
    );
    // Finding 09-P1 (migration 089) bounded media download retries.
    final mediaCols89 = await getColumnNames(db, 'media_attachments');
    expect(mediaCols89, contains('download_retry_count'));
  }

  Future<void> runUpgradePathFromV1ThroughV65(
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
    await runGroupsLastMembershipEventAtMigration(db);
    await runGroupsMetadataColumnsMigration(db);
    await runGroupsMuteColumnMigration(db);
    await runPendingGroupInvitesMigration(db);
    await runGroupsDissolveColumnsMigration(db);
    await runGroupsBacklogRetentionColumnsMigration(db);
    await runGroupReactionReplayOutboxMigration(db);
    await runGroupInviteRevocationsMigration(db);
    await runGroupInviteConsumptionsMigration(db);
    await runGroupMemberPermissionsMigration(db);
    await runMediaAttachmentIntegrityColumnsMigration(db);
    await runMediaAttachmentEncryptionColumnsMigration(db);
    await runGroupEventLogMigration(db);
    await runGroupMessageTransportPeerIdMigration(db);
    await runGroupMemberDeviceIdentitiesMigration(db);
    await runGroupPendingKeyRepairsMigration(db);
    await runGroupWelcomeKeyPackageTombstonesMigration(db);
    await runGroupHistoryGapRepairsMigration(db);
  }

  Future<void> runUpgradePathFromV1(
    Database db, {
    required FakeSecureKeyStore keyStore,
  }) async {
    await runUpgradePathFromV1ThroughV65(db, keyStore: keyStore);
    await runGroupSyncReceiptsMigration(db);
    await runGroupInviteDeliveryAttemptsMigration(db);
    await runRemovedGroupMemberSnapshotsMigration(db);
    await runGroupMessageLocalDeletionsMigration(db);
    await runGroupKeyRotationDraftsMigration(db);
    await runPendingIntroductionResponseTransportSenderMigration(db);
    await runGroupPendingMembershipMessagesMigration(db);
    await runGroupMessageLastSendAttemptAtMigration(db);
    await runGroupMessageLogicalDeliveryIdMigration(db);
    await runMessageRelayCustodyMigration(db);
    await runGroupPendingKeyDistributionsMigration(db);
    await runMessageDedupKeyMigration(db);
    await runGroupPendingKeyRepairsStatusIndexMigration(db);
    await runGroupPendingReactionsMigration(db);
    await runMessageReactionTombstoneMigration(db);
    await runGroupsLastMembershipEventIdMigration(db);
    await runPendingGroupBroadcastsMigration(db);
    // Plan 232 extends the legacy hand-driven fixture just far enough for the
    // current direct-message row mapper. The production registry remains the
    // source of the actual v97 migration function.
    await productionUpgradeMigrations
        .singleWhere((entry) => entry.version == 97)
        .run(db);
    // Plan 234 advances the same hand-driven repository fixture to the v100
    // direct-parent shape. v98/v99 are group-only and do not gate this model.
    await productionUpgradeMigrations
        .singleWhere((entry) => entry.version == 100)
        .run(db);
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
      dbExistsMessageByContent:
          (contactPeerId, senderPeerId, text, timestamp) =>
              dbExistsMessageByContent(
                db,
                contactPeerId,
                senderPeerId,
                text,
                timestamp,
              ),
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
      dbSaveIntroductionWithOutboxDeliveries: (introductionRow, deliveryRows) =>
          dbSaveIntroductionWithOutboxDeliveries(
            db,
            introductionRow,
            deliveryRows,
          ),
      dbReplaceIntroductionWithPendingResponseMigration:
          ({
            required introductionRow,
            required deliveryRows,
            required replacedIntroductionIds,
          }) => dbReplaceIntroductionWithPendingResponseMigration(
            db,
            introductionRow: introductionRow,
            deliveryRows: deliveryRows,
            replacedIntroductionIds: replacedIntroductionIds,
          ),
      dbSaveIntroductionResponseWithOutboxDeliveries:
          ({
            required introductionId,
            required isRecipient,
            required responseStatus,
            required respondedAt,
            required overallStatus,
            required deliveryRows,
          }) => dbSaveIntroductionResponseWithOutboxDeliveries(
            db,
            introductionId: introductionId,
            isRecipient: isRecipient,
            responseStatus: responseStatus,
            respondedAt: respondedAt,
            overallStatus: overallStatus,
            deliveryRows: deliveryRows,
          ),
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
    test(
      '090. group_invite_delivery_attempts accepts revoked/declined rows and an invite_id (v90)',
      () async {
        db = await databaseFactoryFfi.openDatabase(
          inMemoryDatabasePath,
          options: OpenDatabaseOptions(version: 1),
        );
        await runFreshInstallMigrations(db);

        // The widened CHECK + new invite_id column must accept the new statuses.
        await db.insert('group_invite_delivery_attempts', {
          'group_id': 'g1',
          'peer_id': 'p-revoked',
          'status': 'revoked',
          'attempted_at': '2026-06-17T00:00:00.000Z',
          'updated_at': '2026-06-17T00:00:00.000Z',
          'invite_id': 'invite-abc',
        });
        await db.insert('group_invite_delivery_attempts', {
          'group_id': 'g1',
          'peer_id': 'p-declined',
          'status': 'declined',
          'attempted_at': '2026-06-17T00:00:00.000Z',
          'updated_at': '2026-06-17T00:00:00.000Z',
          'invite_id': 'invite-def',
        });

        final rows = await db.query(
          'group_invite_delivery_attempts',
          orderBy: 'peer_id',
        );
        expect(rows, hasLength(2));
        expect(rows[0]['status'], 'declined');
        expect(rows[0]['invite_id'], 'invite-def');
        expect(rows[1]['status'], 'revoked');
        expect(rows[1]['invite_id'], 'invite-abc');

        // A bogus status is still rejected by the CHECK.
        await expectLater(
          () => db.insert('group_invite_delivery_attempts', {
            'group_id': 'g1',
            'peer_id': 'p-bogus',
            'status': 'not_a_status',
            'attempted_at': '2026-06-17T00:00:00.000Z',
            'updated_at': '2026-06-17T00:00:00.000Z',
          }),
          throwsA(anything),
        );
      },
    );

    test(
      '091. pending_group_invites carries a nullable inviter_mlkem_public_key (v91)',
      () async {
        db = await databaseFactoryFfi.openDatabase(
          inMemoryDatabasePath,
          options: OpenDatabaseOptions(version: 1),
        );
        await runFreshInstallMigrations(db);

        final columns = await db.rawQuery(
          'PRAGMA table_info(pending_group_invites)',
        );
        final mlkemColumn = columns.firstWhere(
          (col) => col['name'] == 'inviter_mlkem_public_key',
          orElse: () => <String, Object?>{},
        );
        expect(mlkemColumn, isNotEmpty);
        expect(mlkemColumn['type'], 'TEXT');
        // Nullable: notnull flag is 0.
        expect(mlkemColumn['notnull'], 0);

        // A legacy-style row (no inviter key) is accepted and reads back NULL.
        await db.insert('pending_group_invites', {
          'group_id': 'g-legacy',
          'invite_id': 'invite-legacy',
          'payload_json': '{}',
          'group_name': 'Legacy',
          'group_type': 'chat',
          'sender_peer_id': '12D3KooWAlice',
          'sender_username': 'Alice',
          'created_by': '12D3KooWAlice',
          'created_at': '2026-06-17T00:00:00.000Z',
          'received_at': '2026-06-17T00:00:00.000Z',
          'expires_at': '2026-06-24T00:00:00.000Z',
        });
        // A new row persists the inviter ML-KEM key.
        await db.insert('pending_group_invites', {
          'group_id': 'g-keyed',
          'invite_id': 'invite-keyed',
          'payload_json': '{}',
          'group_name': 'Keyed',
          'group_type': 'chat',
          'sender_peer_id': '12D3KooWBob',
          'sender_username': 'Bob',
          'created_by': '12D3KooWBob',
          'created_at': '2026-06-17T00:00:00.000Z',
          'received_at': '2026-06-17T00:00:00.000Z',
          'expires_at': '2026-06-24T00:00:00.000Z',
          'inviter_mlkem_public_key': 'bobMlKem64',
        });

        final rows = await db.query(
          'pending_group_invites',
          orderBy: 'group_id',
        );
        expect(rows, hasLength(2));
        expect(rows[0]['group_id'], 'g-keyed');
        expect(rows[0]['inviter_mlkem_public_key'], 'bobMlKem64');
        expect(rows[1]['group_id'], 'g-legacy');
        expect(rows[1]['inviter_mlkem_public_key'], isNull);
      },
    );

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
          'group_invite_revocations',
          'group_invite_consumptions',
          'group_history_gap_repairs',
          'group_inbox_cursors',
          'group_message_receipts',
          'group_invite_delivery_attempts',
          'removed_group_member_snapshots',
          'group_message_local_deletions',
          'group_key_rotation_drafts',
          'group_pending_key_distributions',
          'group_pending_reactions',
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
          'content_hash',
          'thumbnail_hash',
          'encryption_key_base64',
          'encryption_nonce',
          'encryption_scheme',
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
          'transport_peer_id',
          'last_send_attempt_at',
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
      await runMediaAttachmentIntegrityColumnsMigration(db);
      await runMediaAttachmentEncryptionColumnsMigration(db);
      final mediaCols10 = await getColumnNames(db, 'media_attachments');
      expect(
        mediaCols10,
        containsAll([
          'content_hash',
          'thumbnail_hash',
          'encryption_key_base64',
          'encryption_nonce',
          'encryption_scheme',
        ]),
      );

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
      'PREREQ-GROUP-SYNC-RECEIPTS v65 to v66 upgrade creates sync tables and preserves group messages',
      () async {
        db = await databaseFactoryFfi.openDatabase(
          inMemoryDatabasePath,
          options: OpenDatabaseOptions(version: 1),
        );

        await runIdentityTableMigration(db);
        final keyStore = FakeSecureKeyStore();
        await runUpgradePathFromV1ThroughV65(db, keyStore: keyStore);
        await db.insert('group_messages', {
          'id': 'group-msg-before-066',
          'group_id': 'group-1',
          'sender_peer_id': 'peer-sender',
          'sender_username': 'Sender',
          'text': 'Stored before sync receipt migration',
          'timestamp': '2026-05-01T12:00:00.000Z',
          'key_generation': 1,
          'status': 'delivered',
          'is_incoming': 1,
          'created_at': '2026-05-01T12:00:01.000Z',
        });

        await runGroupSyncReceiptsMigration(db);
        await runGroupSyncReceiptsMigration(db);

        final tables = await getTableNames(db);
        expect(tables, contains('group_inbox_cursors'));
        expect(tables, contains('group_message_receipts'));
        final preserved = await db.query(
          'group_messages',
          where: 'id = ?',
          whereArgs: ['group-msg-before-066'],
        );
        expect(preserved, hasLength(1));
        expect(
          preserved.single['text'],
          'Stored before sync receipt migration',
        );
      },
    );

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

        final groupMessageColumns = await getColumnNames(db, 'group_messages');
        expect(groupMessageColumns, contains('last_send_attempt_at'));

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
      await runMediaAttachmentIntegrityColumnsMigration(db);
      await runMediaAttachmentEncryptionColumnsMigration(db);
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
      await runPendingIntroductionResponsesMigration(db);
      await runGroupEventLogMigration(db);
      await runGroupPendingKeyRepairsMigration(db);
      await runGroupWelcomeKeyPackageTombstonesMigration(db);
      await runGroupHistoryGapRepairsMigration(db);
      await runGroupSyncReceiptsMigration(db);
      await runGroupInviteDeliveryAttemptsMigration(db);
      await runRemovedGroupMemberSnapshotsMigration(db);
      await runGroupMessageLocalDeletionsMigration(db);
      await runGroupKeyRotationDraftsMigration(db);
      await runPendingIntroductionResponseTransportSenderMigration(db);
      await runGroupPendingMembershipMessagesMigration(db);
      await runGroupMessageLastSendAttemptAtMigration(db);
      await runGroupMessageLogicalDeliveryIdMigration(db);
      await runGroupMessageLogicalDeliveryIdMigration(db);
      await runMessageRelayCustodyMigration(db);

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
      await runMediaAttachmentIntegrityColumnsMigration(db);
      await runMediaAttachmentEncryptionColumnsMigration(db);
      await runAvatarVersionMigration(db);
      await runTransportColumnMigration(db);
      await runWaveformColumnMigration(db);
      await runWireEnvelopeMigration(db);
      await runMessageStatusCleanupMigration(db);
      await runMessageReactionsMigration(db);
      await runGroupsTablesMigration(db);
      await runGroupMessagesTablesMigration(db);
      await runGroupQuotedMessageIdMigration(db);
      await runPendingIntroductionResponsesMigration(db);
      await runGroupEventLogMigration(db);
      await runGroupPendingKeyRepairsMigration(db);
      await runGroupWelcomeKeyPackageTombstonesMigration(db);
      await runGroupHistoryGapRepairsMigration(db);
      await runGroupSyncReceiptsMigration(db);
      await runGroupInviteDeliveryAttemptsMigration(db);
      await runRemovedGroupMemberSnapshotsMigration(db);
      await runGroupMessageLocalDeletionsMigration(db);
      await runGroupKeyRotationDraftsMigration(db);
      await runPendingIntroductionResponseTransportSenderMigration(db);
      await runGroupPendingMembershipMessagesMigration(db);
      await runGroupMessageLastSendAttemptAtMigration(db);

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

  group('Production migration registries (TC-228-01)', () {
    test(
      'production registries contain one ordered direct forwarded v97 entry',
      () {
        expect(currentIdentityDatabaseVersion, 103);
        for (final registry in [
          productionCreateMigrations,
          productionUpgradeMigrations,
        ]) {
          expect(registry.where((entry) => entry.version == 97), hasLength(1));
          final index96 = registry.indexWhere((entry) => entry.version == 96);
          final index97 = registry.indexWhere((entry) => entry.version == 97);
          expect(index96, greaterThanOrEqualTo(0));
          expect(index97, index96 + 1);
          expect(registry[index97].name, '097_direct_message_forwarded');
        }
      },
    );

    // 235: DB v98 — group media deletion journal appended exactly once to
    // BOTH production registries, immediately after v97.
    test(
      'production registries contain one ordered deletion journal v98 entry',
      () {
        expect(currentIdentityDatabaseVersion, 103);
        for (final registry in [
          productionCreateMigrations,
          productionUpgradeMigrations,
        ]) {
          expect(registry.where((entry) => entry.version == 98), hasLength(1));
          final index97 = registry.indexWhere((entry) => entry.version == 97);
          final index98 = registry.indexWhere((entry) => entry.version == 98);
          expect(index97, greaterThanOrEqualTo(0));
          expect(index98, index97 + 1);
          expect(registry[index98].name, '098_group_media_deletion_journal');
        }
      },
    );
    test(
      'production registries preserve v100-v102 and end with exit intents v103',
      () {
        expect(currentIdentityDatabaseVersion, 103);
        for (final registry in [
          productionCreateMigrations,
          productionUpgradeMigrations,
        ]) {
          final index99 = registry.indexWhere((entry) => entry.version == 99);
          final index100 = registry.indexWhere((entry) => entry.version == 100);
          final index101 = registry.indexWhere((entry) => entry.version == 101);
          final index102 = registry.indexWhere((entry) => entry.version == 102);
          final index103 = registry.indexWhere((entry) => entry.version == 103);
          expect(registry.where((entry) => entry.version == 100), hasLength(1));
          expect(registry.where((entry) => entry.version == 101), hasLength(1));
          expect(registry.where((entry) => entry.version == 102), hasLength(1));
          expect(registry.where((entry) => entry.version == 103), hasLength(1));
          expect(index99, greaterThanOrEqualTo(0));
          expect(index100, index99 + 1);
          expect(index101, index100 + 1);
          expect(index102, index101 + 1);
          expect(index103, index102 + 1);
          expect(index103, registry.length - 1);
          expect(registry[index100].name, '100_direct_private_media_lifecycle');
          expect(
            registry[index100].run,
            same(runDirectPrivateMediaLifecycleMigration),
          );
          expect(registry[index101].name, '101_group_private_media_lifecycle');
          expect(
            registry[index101].run,
            same(runGroupPrivateMediaLifecycleMigration),
          );
          expect(registry[index102].name, '102_groups_self_removed_at');
          expect(registry[index102].run, same(runGroupsSelfRemovedAtMigration));
          expect(registry[index103].name, '103_group_exit_intents');
          expect(registry[index103].run, same(runGroupExitIntentsMigration));
        }
      },
    );

    // The exact onCreate call order in main.dart through v95. Fresh installs
    // deliberately skip 004 (nullable secrets — 005 already ships nullable +
    // CHECK) and run 005 inline; 042 runs immediately after 010.
    const expectedCreateOrder = <int>[
      1,
      2,
      3,
      5,
      6,
      7,
      8,
      9,
      10,
      42,
      11,
      12,
      13,
      14,
      15,
      16,
      17,
      18,
      19,
      20,
      21,
      22,
      23,
      24,
      25,
      26,
      27,
      28,
      29,
      30,
      31,
      32,
      33,
      34,
      35,
      36,
      37,
      38,
      39,
      40,
      41,
      43,
      44,
      45,
      46,
      47,
      48,
      49,
      50,
      51,
      52,
      53,
      54,
      55,
      56,
      57,
      58,
      59,
      60,
      61,
      62,
      63,
      64,
      65,
      66,
      67,
      68,
      69,
      70,
      71,
      72,
      73,
      74,
      75,
      76,
      77,
      78,
      79,
      80,
      81,
      82,
      83,
      84,
      85,
      86,
      87,
      88,
      89,
      90,
      91,
      92,
      93,
      94,
      95,
    ];
    // The exact onUpgrade guard order in main.dart through v95. Upgrades run
    // 004 but defer 005 to post-open (main.dart runs it after secrets
    // migration); 042 runs immediately after 010, before 011.
    const expectedUpgradeOrder = <int>[
      2,
      3,
      4,
      6,
      7,
      8,
      9,
      10,
      42,
      11,
      12,
      13,
      14,
      15,
      16,
      17,
      18,
      19,
      20,
      21,
      22,
      23,
      24,
      25,
      26,
      27,
      28,
      29,
      30,
      31,
      32,
      33,
      34,
      35,
      36,
      37,
      38,
      39,
      40,
      41,
      43,
      44,
      45,
      46,
      47,
      48,
      49,
      50,
      51,
      52,
      53,
      54,
      55,
      56,
      57,
      58,
      59,
      60,
      61,
      62,
      63,
      64,
      65,
      66,
      67,
      68,
      69,
      70,
      71,
      72,
      73,
      74,
      75,
      76,
      77,
      78,
      79,
      80,
      81,
      82,
      83,
      84,
      85,
      86,
      87,
      88,
      89,
      90,
      91,
      92,
      93,
      94,
      95,
    ];

    Future<void> expectV95Artifacts(Database db) async {
      final userVersion = (await db.rawQuery(
        'PRAGMA user_version',
      )).first.values.first;
      expect(userVersion, 95);
      final tables = await getRegistryTableNames(db);
      // 092 + 095 table artifacts.
      expect(tables, contains('feed_cleared_threads'));
      expect(tables, contains('intro_review_seen'));
      // 093 + 094 index artifacts.
      final indexNames = (await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='index'",
      )).map((r) => r['name'] as String).toList();
      expect(indexNames, contains('idx_messages_contact_ts'));
      expect(indexNames, contains('idx_group_messages_group_ts'));
    }

    test(
      'production registries preserve the exact ordered v95 baseline',
      () async {
        // Manifest lock: the shared registries expose the literal ordered
        // production create/upgrade sequences through v95.
        final createVersions = productionCreateMigrations
            .sublist(0, expectedCreateOrder.length)
            .map((e) => e.version)
            .toList();
        final upgradeVersions = productionUpgradeMigrations
            .sublist(0, expectedUpgradeOrder.length)
            .map((e) => e.version)
            .toList();
        expect(createVersions, expectedCreateOrder);
        expect(upgradeVersions, expectedUpgradeOrder);

        // Intentional create/upgrade branch differences through v95 stay
        // intact: create skips 004 and runs 005 inline; upgrade runs 004 and
        // defers 005 to the post-open step in main.dart.
        expect(createVersions, isNot(contains(4)));
        expect(createVersions, contains(5));
        expect(upgradeVersions, contains(4));
        expect(upgradeVersions, isNot(contains(5)));

        final tempDir = await Directory.systemTemp.createTemp(
          'registry_v95_baseline_',
        );
        try {
          // Fresh create at literal target v95 via the production callback.
          final createPath = '${tempDir.path}/create_v95.db';
          final created = await databaseFactoryFfi.openDatabase(
            createPath,
            options: OpenDatabaseOptions(
              version: 95,
              onCreate: runProductionOnCreate,
              onUpgrade: runProductionOnUpgrade,
            ),
          );
          try {
            await expectV95Artifacts(created);
          } finally {
            await created.close();
          }

          // v1 -> v95 via the production upgrade callback preserves rows.
          final upgradePath = '${tempDir.path}/upgrade_v95.db';
          final legacy = await databaseFactoryFfi.openDatabase(
            upgradePath,
            options: OpenDatabaseOptions(
              version: 1,
              onCreate: (db, version) => runIdentityTableMigration(db),
            ),
          );
          await legacy.insert('contacts', {
            'peer_id': 'contact-registry-baseline',
            'public_key': 'pk-registry',
            'rendezvous': '/rv/registry',
            'username': 'RegistryContact',
            'signature': 'sig-registry',
            'scanned_at': '2026-01-01T00:00:00Z',
          });
          await legacy.close();

          final upgraded = await databaseFactoryFfi.openDatabase(
            upgradePath,
            options: OpenDatabaseOptions(
              version: 95,
              onCreate: runProductionOnCreate,
              onUpgrade: runProductionOnUpgrade,
            ),
          );
          try {
            await expectV95Artifacts(upgraded);
            final contact = await upgraded.query(
              'contacts',
              where: 'peer_id = ?',
              whereArgs: ['contact-registry-baseline'],
            );
            expect(contact, hasLength(1));
            expect(contact.single['username'], 'RegistryContact');
          } finally {
            await upgraded.close();
          }
        } finally {
          await tempDir.delete(recursive: true);
        }
      },
    );

    test('production create and v95 upgrade registries include media library '
        'state v96', () async {
      // TC-228-13: v96 is the current version and appears exactly once, as
      // the final entry, in BOTH production registry branches.
      expect(currentIdentityDatabaseVersion, 103);
      expect(
        productionCreateMigrations.where((e) => e.version == 96).length,
        1,
      );
      expect(
        productionUpgradeMigrations.where((e) => e.version == 96).length,
        1,
      );
      final create96 = productionCreateMigrations.indexWhere(
        (entry) => entry.version == 96,
      );
      final upgrade96 = productionUpgradeMigrations.indexWhere(
        (entry) => entry.version == 96,
      );
      expect(
        productionCreateMigrations[create96].name,
        '096_media_library_state',
      );
      expect(productionCreateMigrations[create96 + 1].version, 97);
      expect(productionUpgradeMigrations[upgrade96 + 1].version, 97);

      Future<void> expectV96Artifacts(Database db) async {
        final userVersion = (await db.rawQuery(
          'PRAGMA user_version',
        )).first.values.first;
        expect(userVersion, currentIdentityDatabaseVersion);
        final cols = (await db.rawQuery(
          'PRAGMA table_info(media_attachments)',
        )).map((c) => c['name'] as String).toSet();
        expect(
          cols,
          containsAll([
            'owner_lane',
            'is_bookmarked',
            'last_playback_position_ms',
          ]),
        );
        final indexNames = (await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='index' "
          "AND tbl_name='media_attachments'",
        )).map((r) => r['name'] as String).toList();
        expect(indexNames, contains('idx_media_attachments_owner_message'));
        expect(await getRegistryTableNames(db), contains('group_exit_intents'));
        expect(
          indexNames,
          contains('idx_media_attachments_owner_bookmark_message'),
        );
      }

      final tempDir = await Directory.systemTemp.createTemp(
        'registry_v96_inclusion_',
      );
      try {
        // Fresh create at the current version reaches v96.
        final createPath = '${tempDir.path}/create_v96.db';
        final created = await databaseFactoryFfi.openDatabase(
          createPath,
          options: OpenDatabaseOptions(
            version: currentIdentityDatabaseVersion,
            onCreate: runProductionOnCreate,
            onUpgrade: runProductionOnUpgrade,
          ),
        );
        try {
          await expectV96Artifacts(created);
        } finally {
          await created.close();
        }

        // Literal v95 database (production create callback), seeded, then
        // reopened through the production v96 upgrade callback.
        final upgradePath = '${tempDir.path}/upgrade_v96.db';
        final v95 = await databaseFactoryFfi.openDatabase(
          upgradePath,
          options: OpenDatabaseOptions(
            version: 95,
            onCreate: runProductionOnCreate,
            onUpgrade: runProductionOnUpgrade,
          ),
        );
        await v95.insert('messages', {
          'id': 'msg-v96-upgrade',
          'contact_peer_id': 'contact-1',
          'sender_peer_id': 'contact-1',
          'text': 'pre-upgrade parent',
          'timestamp': '2026-07-01T00:00:00.000Z',
          'status': 'delivered',
          'is_incoming': 1,
          'created_at': '2026-07-01T00:00:00.000Z',
        });
        await v95.insert('media_attachments', {
          'id': 'att-v96-upgrade',
          'message_id': 'msg-v96-upgrade',
          'mime': 'image/jpeg',
          'size': 42,
          'media_type': 'image',
          'download_status': 'done',
          'created_at': '2026-07-01T00:00:01.000Z',
        });
        await v95.close();

        final upgraded = await databaseFactoryFfi.openDatabase(
          upgradePath,
          options: OpenDatabaseOptions(
            version: currentIdentityDatabaseVersion,
            onCreate: runProductionOnCreate,
            onUpgrade: runProductionOnUpgrade,
          ),
        );
        try {
          await expectV96Artifacts(upgraded);
          final att = await upgraded.query(
            'media_attachments',
            where: 'id = ?',
            whereArgs: ['att-v96-upgrade'],
          );
          expect(att, hasLength(1));
          expect(att.single['owner_lane'], 'direct');
          expect(att.single['is_bookmarked'], 0);
          expect(att.single['last_playback_position_ms'], 0);
        } finally {
          await upgraded.close();
        }
      } finally {
        await tempDir.delete(recursive: true);
      }
    });

    test(
      'production fresh and 99 to 100 chains reopen rerun and reject downgrade',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'registry_v100_chain_',
        );
        final predecessorPath = '${tempDir.path}/predecessor.db';
        final freshPath = '${tempDir.path}/fresh.db';
        try {
          var predecessor = await databaseFactoryFfi.openDatabase(
            predecessorPath,
            options: OpenDatabaseOptions(
              version: 99,
              onCreate: runProductionOnCreate,
              onUpgrade: runProductionOnUpgrade,
            ),
          );
          await predecessor.insert('messages', {
            'id': 'v99-parent',
            'contact_peer_id': 'contact-1',
            'sender_peer_id': 'contact-1',
            'text': 'predecessor',
            'timestamp': '2026-07-11T00:00:00.000Z',
            'status': 'delivered',
            'is_incoming': 1,
            'created_at': '2026-07-11T00:00:00.000Z',
            'is_forwarded': 1,
          });
          await predecessor.close();

          predecessor = await databaseFactoryFfi.openDatabase(
            predecessorPath,
            options: OpenDatabaseOptions(
              version: 100,
              onCreate: runProductionOnCreate,
              onUpgrade: runProductionOnUpgrade,
              onDowngrade: onDatabaseVersionChangeError,
            ),
          );
          final entry = productionUpgradeMigrations.singleWhere(
            (candidate) => candidate.version == 100,
          );
          await entry.run(predecessor);
          await entry.run(predecessor);
          final upgraded = (await predecessor.query(
            'messages',
            where: 'id = ?',
            whereArgs: ['v99-parent'],
          )).single;
          expect(upgraded['is_forwarded'], 1);
          expect(upgraded['private_media_policy_version'], 0);
          expect(upgraded['private_media_mode'], 'ordinary');
          expect(upgraded['private_media_state'], 'none');
          await predecessor.update(
            'messages',
            {
              'private_media_policy_version': 1,
              'private_media_mode': 'view_once',
              'private_media_state': 'viewing',
              'private_media_received_at_ms': 1000,
              'private_media_revealed_at_ms': 2000,
              'private_media_clock_high_water_ms': 2000,
            },
            where: 'id = ?',
            whereArgs: ['v99-parent'],
          );
          await predecessor.close();

          predecessor = await databaseFactoryFfi.openDatabase(
            predecessorPath,
            options: OpenDatabaseOptions(
              version: 100,
              onCreate: runProductionOnCreate,
              onUpgrade: runProductionOnUpgrade,
              onDowngrade: onDatabaseVersionChangeError,
            ),
          );
          final reopened = (await predecessor.query('messages')).single;
          expect(reopened['private_media_mode'], 'view_once');
          expect(reopened['private_media_state'], 'viewing');
          expect(reopened['private_media_received_at_ms'], 1000);
          expect(reopened['private_media_revealed_at_ms'], 2000);
          await predecessor.close();

          await expectLater(
            databaseFactoryFfi.openDatabase(
              predecessorPath,
              options: OpenDatabaseOptions(
                version: 99,
                onDowngrade: onDatabaseVersionChangeError,
              ),
            ),
            throwsA(anything),
          );

          final fresh = await databaseFactoryFfi.openDatabase(
            freshPath,
            options: OpenDatabaseOptions(
              version: 100,
              onCreate: runProductionOnCreate,
              onUpgrade: runProductionOnUpgrade,
              onDowngrade: onDatabaseVersionChangeError,
            ),
          );
          final freshColumns = (await fresh.rawQuery(
            'PRAGMA table_info(messages)',
          )).map((row) => row['name'] as String).toSet();
          expect(
            freshColumns,
            containsAll({
              'private_media_policy_version',
              'private_media_mode',
              'private_media_duration_seconds',
              'private_media_state',
              'private_media_received_at_ms',
              'private_media_expires_at_ms',
              'private_media_revealed_at_ms',
              'private_media_terminal_at_ms',
              'private_media_clock_high_water_ms',
            }),
          );
          final indexes = (await fresh.rawQuery(
            "SELECT name FROM sqlite_master WHERE type='index' "
            "AND tbl_name='messages'",
          )).map((row) => row['name']);
          expect(indexes, contains('idx_messages_private_media_expiry'));
          await fresh.close();
        } finally {
          if (await tempDir.exists()) await tempDir.delete(recursive: true);
        }
      },
    );

    test(
      'production fresh and 100 to 101 chains preserve v100 and group rows',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'registry_v101_chain_',
        );
        final predecessorPath = '${tempDir.path}/predecessor.db';
        final freshPath = '${tempDir.path}/fresh.db';
        try {
          var predecessor = await databaseFactoryFfi.openDatabase(
            predecessorPath,
            options: OpenDatabaseOptions(
              version: 100,
              onCreate: runProductionOnCreate,
              onUpgrade: runProductionOnUpgrade,
            ),
          );
          await predecessor.insert('messages', {
            'id': 'same-id',
            'contact_peer_id': 'contact-1',
            'sender_peer_id': 'contact-1',
            'text': 'direct predecessor',
            'timestamp': '2026-07-12T00:00:00.000Z',
            'status': 'delivered',
            'is_incoming': 1,
            'created_at': '2026-07-12T00:00:00.000Z',
            'private_media_policy_version': 1,
            'private_media_mode': 'view_once',
            'private_media_state': 'available',
          });
          await predecessor.insert('group_messages', {
            'id': 'same-id',
            'group_id': 'group-1',
            'sender_peer_id': 'peer-1',
            'sender_username': 'Alice',
            'text': 'group predecessor',
            'timestamp': '2026-07-12T00:00:00.000Z',
            'key_generation': 1,
            'status': 'delivered',
            'is_incoming': 1,
            'created_at': '2026-07-12T00:00:00.000Z',
          });
          await predecessor.close();

          predecessor = await databaseFactoryFfi.openDatabase(
            predecessorPath,
            options: OpenDatabaseOptions(
              version: 101,
              onCreate: runProductionOnCreate,
              onUpgrade: runProductionOnUpgrade,
              onDowngrade: onDatabaseVersionChangeError,
            ),
          );
          final entry = productionUpgradeMigrations.singleWhere(
            (candidate) => candidate.version == 101,
          );
          await entry.run(predecessor);
          await entry.run(predecessor);
          final direct = (await predecessor.query('messages')).single;
          final group = (await predecessor.query('group_messages')).single;
          expect(direct['private_media_mode'], 'view_once');
          expect(direct['private_media_state'], 'available');
          expect(group['id'], 'same-id');
          expect(group['media_policy_version'], 0);
          expect(group['media_lifecycle'], 'standard');
          expect(group['media_protected'], 0);
          expect(group['media_cleanup_pending'], 0);
          final groupIndexes = (await predecessor.rawQuery(
            "SELECT name FROM sqlite_master WHERE type='index' "
            "AND tbl_name='group_messages'",
          )).map((row) => row['name']);
          expect(
            groupIndexes,
            contains('idx_group_messages_private_media_expiry'),
          );
          await predecessor.close();

          await expectLater(
            databaseFactoryFfi.openDatabase(
              predecessorPath,
              options: OpenDatabaseOptions(
                version: 100,
                onDowngrade: onDatabaseVersionChangeError,
              ),
            ),
            throwsA(anything),
          );

          final fresh = await databaseFactoryFfi.openDatabase(
            freshPath,
            options: OpenDatabaseOptions(
              version: 101,
              onCreate: runProductionOnCreate,
              onUpgrade: runProductionOnUpgrade,
              onDowngrade: onDatabaseVersionChangeError,
            ),
          );
          final freshColumns = (await fresh.rawQuery(
            'PRAGMA table_info(group_messages)',
          )).map((row) => row['name'] as String).toSet();
          expect(
            freshColumns,
            containsAll({
              'media_policy_version',
              'media_lifecycle',
              'media_duration_seconds',
              'media_protected',
              'media_received_at',
              'media_expires_at',
              'media_last_checked_at',
              'media_consumed_at',
              'media_expired_at',
              'media_cleanup_pending',
            }),
          );
          await fresh.close();
        } finally {
          if (await tempDir.exists()) await tempDir.delete(recursive: true);
        }
      },
    );
  });
}

/// Helper shared by the registry tests (outside the main group so it can be
/// used without the group-scoped `db`).
Future<List<String>> getRegistryTableNames(Database db) async {
  final rows = await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'",
  );
  return rows.map((r) => r['name'] as String).toList()..sort();
}
