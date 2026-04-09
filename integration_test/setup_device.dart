/// Headless device setup: generates identity + sets username.
///
/// Usage (run per-device with --dart-define):
///   flutter test integration_test/setup_device.dart \
///     -d <device-id> --dart-define=USERNAME=a
///
/// State is written to the real DB (identity.db) and iOS Keychain,
/// so the normal app picks up the identity on next launch.
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/bridge/go_bridge_client.dart';
import 'package:flutter_app/core/database/encrypted_db_opener.dart';
import 'package:flutter_app/core/database/helpers/identity_db_helpers.dart';
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
import 'package:flutter_app/core/database/migrations/027_posts_core.dart';
import 'package:flutter_app/core/database/migrations/028_posts_engagement.dart';
import 'package:flutter_app/core/database/migrations/029_posts_nearby.dart';
import 'package:flutter_app/core/database/migrations/030_posts_pass_along.dart';
import 'package:flutter_app/core/database/migrations/031_posts_pins.dart';
import 'package:flutter_app/core/database/migrations/032_posts_retry_recipient_context.dart';
import 'package:flutter_app/core/database/migrations/033_posts_follow_on_outbox.dart';
import 'package:flutter_app/core/database/migrations/034_posts_media_upload_recovery.dart';
import 'package:flutter_app/core/database/migrations/035_posts_repost_delivery_state.dart';
import 'package:flutter_app/core/database/migrations/036_posts_pass_encrypted_snapshots.dart';
import 'package:flutter_app/core/database/migrations/037_posts_repost_engagement_state.dart';
import 'package:flutter_app/core/database/migrations/038_posts_repost_media_crypto.dart';
import 'package:flutter_app/core/database/migrations/039_posts_pass_avatar_snapshots.dart';
import 'package:flutter_app/core/database/migrations/040_posts_repost_visual_metrics.dart';
import 'package:flutter_app/core/database/migrations/041_group_message_reliability_columns.dart';
import 'package:flutter_app/core/database/migrations/042_media_attachment_reliability_columns.dart';
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
import 'package:flutter_app/core/secure_storage/flutter_secure_key_store.dart';
import 'package:flutter_app/core/secure_storage/migrate_secrets_to_secure_storage.dart';
import 'package:flutter_app/features/identity/application/generate_identity_use_case.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository_impl.dart';

const _username = String.fromEnvironment('USERNAME', defaultValue: 'test');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Setup device with username "$_username"', (tester) async {
    print('\n=== Setting up device with username: $_username ===\n');

    // 1. Real secure key store (iOS Keychain)
    final secureKeyStore = FlutterSecureKeyStore();

    // 2. Open real encrypted DB (same name + version + migrations as main.dart)
    final db = await openEncryptedDatabase(
      secureKeyStore: secureKeyStore,
      dbName: 'identity.db',
      version: 53,
      onCreate: (db, version) async {
        await runIdentityTableMigration(db);
        await runMessagesTableMigration(db);
        await runMlKemKeysMigration(db);
        // Fresh install: skip 004; 005 adds the nullable + CHECK schema.
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
        await runPostsCoreMigration(db);
        await runPostsEngagementMigration(db);
        await runPostsNearbyMigration(db);
        await runPostsPassAlongMigration(db);
        await runPostsPinsMigration(db);
        await runPostsRetryRecipientContextMigration(db);
        await runPostsFollowOnOutboxMigration(db);
        await runPostsMediaUploadRecoveryMigration(db);
        await runPostsRepostDeliveryStateMigration(db);
        await runPostsPassEncryptedSnapshotsMigration(db);
        await runPostsRepostEngagementStateMigration(db);
        await runPostsRepostMediaCryptoMigration(db);
        await runPostsPassAvatarSnapshotsMigration(db);
        await runPostsRepostVisualMetricsMigration(db);
        await runGroupMessageReliabilityColumnsMigration(db);
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
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) await runMessagesTableMigration(db);
        if (oldVersion < 3) await runMlKemKeysMigration(db);
        if (oldVersion < 4) await runNullifySecretColumnsMigration(db);
        if (oldVersion < 6) await runReadAtColumnMigration(db);
        if (oldVersion < 7) await runArchiveColumnsMigration(db);
        if (oldVersion < 8) await runBlockColumnsMigration(db);
        if (oldVersion < 9) await runQuotedMessageIdMigration(db);
        if (oldVersion < 10) await runMediaAttachmentsMigration(db);
        if (oldVersion < 42)
          await runMediaAttachmentReliabilityColumnsMigration(db);
        if (oldVersion < 11) await runAvatarVersionMigration(db);
        if (oldVersion < 12) await runTransportColumnMigration(db);
        if (oldVersion < 13) await runWaveformColumnMigration(db);
        if (oldVersion < 14) await runWireEnvelopeMigration(db);
        if (oldVersion < 15) await runMessageStatusCleanupMigration(db);
        if (oldVersion < 16) await runMessageReactionsMigration(db);
        if (oldVersion < 17) await runGroupsTablesMigration(db);
        if (oldVersion < 18) await runGroupMessagesTablesMigration(db);
        if (oldVersion < 19) await runIntroductionsTableMigration(db);
        if (oldVersion < 20) await runIntroBannerColumnsMigration(db);
        if (oldVersion < 21) await runContactIntroducedByMigration(db);
        if (oldVersion < 22) await runIntroductionKeysMigration(db);
        if (oldVersion < 23) await runIntroductionRecipientKeysMigration(db);
        if (oldVersion < 24) await runContactIntroducedByPeerIdMigration(db);
        if (oldVersion < 25) await runIntroductionAlreadyConnectedMigration(db);
        if (oldVersion < 26) await runGroupQuotedMessageIdMigration(db);
        if (oldVersion < 27) await runPostsCoreMigration(db);
        if (oldVersion < 28) await runPostsEngagementMigration(db);
        if (oldVersion < 29) await runPostsNearbyMigration(db);
        if (oldVersion < 30) await runPostsPassAlongMigration(db);
        if (oldVersion < 31) await runPostsPinsMigration(db);
        if (oldVersion < 32) await runPostsRetryRecipientContextMigration(db);
        if (oldVersion < 33) await runPostsFollowOnOutboxMigration(db);
        if (oldVersion < 34) await runPostsMediaUploadRecoveryMigration(db);
        if (oldVersion < 35) await runPostsRepostDeliveryStateMigration(db);
        if (oldVersion < 36) await runPostsPassEncryptedSnapshotsMigration(db);
        if (oldVersion < 37) await runPostsRepostEngagementStateMigration(db);
        if (oldVersion < 38) await runPostsRepostMediaCryptoMigration(db);
        if (oldVersion < 39) await runPostsPassAvatarSnapshotsMigration(db);
        if (oldVersion < 40) await runPostsRepostVisualMetricsMigration(db);
        if (oldVersion < 41)
          await runGroupMessageReliabilityColumnsMigration(db);
        if (oldVersion < 43) await runMessagesEditedAtMigration(db);
        if (oldVersion < 44) await runMessagesDeletedStateMigration(db);
        if (oldVersion < 45) await runInboxStagingEntriesMigration(db);
        if (oldVersion < 46) await runPendingIntroductionResponsesMigration(db);
        if (oldVersion < 47) await runIntroductionOutboxMigration(db);
        if (oldVersion < 48) await runGroupsLastMembershipEventAtMigration(db);
        if (oldVersion < 49) await runGroupsMetadataColumnsMigration(db);
        if (oldVersion < 50) await runGroupsMuteColumnMigration(db);
        if (oldVersion < 51) await runPendingGroupInvitesMigration(db);
        if (oldVersion < 52) await runGroupsDissolveColumnsMigration(db);
        if (oldVersion < 53)
          await runGroupsBacklogRetentionColumnsMigration(db);
      },
    );
    print('[SETUP] Database opened');

    await migrateSecretsToSecureStorage(db: db, secureKeyStore: secureKeyStore);
    await runSecretNullChecksMigration(db);
    print('[SETUP] Secrets migration/checks completed');

    // 3. Create identity repository (real DB + real Keychain)
    final repository = IdentityRepositoryImpl(
      dbLoadIdentityRow: () => dbLoadIdentityRow(db),
      dbUpsertIdentityRow: (row) => dbUpsertIdentityRow(db, row),
      secureKeyStore: secureKeyStore,
    );

    // 4. Initialize Go bridge
    final bridge = GoBridgeClient();
    await bridge.initialize();
    print('[SETUP] Bridge initialized');

    // 5. Generate identity (keys + ML-KEM, saved to DB + Keychain)
    final result = await generateNewIdentity(
      callGenerate: () => callIdentityGenerate(bridge),
      callMlKemKeygen: () => callMlKemKeygen(bridge),
      repo: repository,
    );
    expect(result, GenerateIdentityResult.success);
    print('[SETUP] Identity generated');

    // 6. Load identity, update username, save
    final identity = await repository.loadIdentity();
    expect(identity, isNotNull);

    final updated = IdentityModel(
      peerId: identity!.peerId,
      publicKey: identity.publicKey,
      privateKey: identity.privateKey,
      mnemonic12: identity.mnemonic12,
      mlKemPublicKey: identity.mlKemPublicKey,
      mlKemSecretKey: identity.mlKemSecretKey,
      username: _username,
      avatarBlob: identity.avatarBlob,
      avatarVersion: identity.avatarVersion,
      createdAt: identity.createdAt,
      updatedAt: identity.updatedAt,
    );
    await repository.saveIdentity(updated);
    print('[SETUP] Username set to: $_username');

    // 7. Verify
    final verify = await repository.loadIdentity();
    expect(verify!.username, _username);
    expect(verify.peerId, isNotEmpty);

    print('\n=== Device setup complete ===');
    print('  Username: $_username');
    print('  PeerId:   ${verify.peerId}');
    print('=============================\n');

    // Cleanup
    bridge.dispose();
    await db.close();
  });
}
