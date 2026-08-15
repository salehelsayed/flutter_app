import 'package:sqflite_sqlcipher/sqflite.dart';

import 'migrations/001_identity_table.dart';
import 'migrations/002_messages_table.dart';
import 'migrations/003_mlkem_keys.dart';
import 'migrations/004_nullify_secret_columns.dart';
import 'migrations/005_secret_null_checks.dart';
import 'migrations/006_read_at_column.dart';
import 'migrations/007_archive_columns.dart';
import 'migrations/008_block_columns.dart';
import 'migrations/009_quoted_message_id.dart';
import 'migrations/010_media_attachments.dart';
import 'migrations/011_avatar_version.dart';
import 'migrations/012_transport_column.dart';
import 'migrations/013_waveform_column.dart';
import 'migrations/014_wire_envelope_column.dart';
import 'migrations/015_message_status_cleanup.dart';
import 'migrations/016_message_reactions.dart';
import 'migrations/017_groups_tables.dart';
import 'migrations/018_group_messages_tables.dart';
import 'migrations/019_introductions_table.dart';
import 'migrations/020_intro_banner_columns.dart';
import 'migrations/021_contact_introduced_by.dart';
import 'migrations/022_introduction_keys.dart';
import 'migrations/023_introduction_recipient_keys.dart';
import 'migrations/024_contact_introduced_by_peer_id.dart';
import 'migrations/025_introduction_already_connected_status.dart';
import 'migrations/026_group_quoted_message_id.dart';
import 'migrations/027_posts_core.dart';
import 'migrations/028_posts_engagement.dart';
import 'migrations/029_posts_nearby.dart';
import 'migrations/030_posts_pass_along.dart';
import 'migrations/031_posts_pins.dart';
import 'migrations/032_posts_retry_recipient_context.dart';
import 'migrations/033_posts_follow_on_outbox.dart';
import 'migrations/034_posts_media_upload_recovery.dart';
import 'migrations/035_posts_repost_delivery_state.dart';
import 'migrations/036_posts_pass_encrypted_snapshots.dart';
import 'migrations/037_posts_repost_engagement_state.dart';
import 'migrations/038_posts_repost_media_crypto.dart';
import 'migrations/039_posts_pass_avatar_snapshots.dart';
import 'migrations/040_posts_repost_visual_metrics.dart';
import 'migrations/041_group_message_reliability_columns.dart';
import 'migrations/042_media_attachment_reliability_columns.dart';
import 'migrations/043_messages_edited_at.dart';
import 'migrations/044_messages_deleted_state.dart';
import 'migrations/045_inbox_staging_entries.dart';
import 'migrations/046_pending_introduction_responses.dart';
import 'migrations/047_introduction_outbox.dart';
import 'migrations/048_groups_last_membership_event_at.dart';
import 'migrations/049_groups_metadata_columns.dart';
import 'migrations/050_groups_mute_column.dart';
import 'migrations/051_pending_group_invites.dart';
import 'migrations/052_groups_dissolve_columns.dart';
import 'migrations/053_groups_backlog_retention_columns.dart';
import 'migrations/054_group_reaction_replay_outbox.dart';
import 'migrations/055_group_invite_revocations.dart';
import 'migrations/056_group_invite_consumptions.dart';
import 'migrations/057_group_member_permissions.dart';
import 'migrations/058_media_attachment_integrity_columns.dart';
import 'migrations/059_media_attachment_encryption_columns.dart';
import 'migrations/060_group_event_log.dart';
import 'migrations/061_group_message_transport_peer_id.dart';
import 'migrations/062_group_member_device_identities.dart';
import 'migrations/063_group_pending_key_repairs.dart';
import 'migrations/064_group_welcome_key_package_tombstones.dart';
import 'migrations/065_group_history_gap_repairs.dart';
import 'migrations/066_group_sync_receipts.dart';
import 'migrations/067_group_invite_delivery_attempts.dart';
import 'migrations/068_removed_group_member_snapshots.dart';
import 'migrations/069_group_message_local_deletions.dart';
import 'migrations/070_group_key_rotation_drafts.dart';
import 'migrations/071_pending_introduction_response_transport_sender.dart';
import 'migrations/072_group_pending_membership_messages.dart';
import 'migrations/073_group_message_last_send_attempt_at.dart';
import 'migrations/074_group_message_logical_delivery_id.dart';
import 'migrations/075_contacts_ml_kem_key_updated_ts.dart';
import 'migrations/076_post_media_attachment_crypto_columns.dart';
import 'migrations/077_message_relay_custody.dart';
import 'migrations/078_group_pending_key_distributions.dart';
import 'migrations/079_message_dedup_key.dart';
import 'migrations/080_group_pending_key_repairs_status_index.dart';
import 'migrations/081_group_pending_reactions.dart';
import 'migrations/082_message_reaction_tombstone.dart';
import 'migrations/083_groups_last_membership_event_id.dart';
import 'migrations/084_group_member_device_snapshots.dart';
import 'migrations/085_pending_sibling_devices.dart';
import 'migrations/086_pending_group_broadcasts.dart';
import 'migrations/087_group_message_retry_backoff_columns.dart';
import 'migrations/088_group_rejoin_state.dart';
import 'migrations/089_media_attachment_download_retry_column.dart';
import 'migrations/090_group_invite_delivery_attempts_revoked_declined.dart';
import 'migrations/091_pending_group_invites_inviter_mlkem.dart';
import 'migrations/092_feed_cleared_threads.dart';
import 'migrations/093_messages_contact_ts_index.dart';
import 'migrations/094_group_messages_group_ts_index.dart';
import 'migrations/095_intro_review_seen.dart';
import 'migrations/096_media_library_state.dart';
import 'migrations/097_direct_message_forwarded.dart';
import 'migrations/098_group_media_deletion_journal.dart';
import 'migrations/099_group_messages_is_forwarded.dart';
import 'migrations/100_direct_private_media_lifecycle.dart';
import 'migrations/101_group_private_media_lifecycle.dart';
import 'migrations/102_groups_self_removed_at.dart';
import 'migrations/103_group_exit_intents.dart';
import 'migrations/104_group_exit_diagnostics.dart';
import 'migrations/105_reaction_outbox_needs_build.dart';
import 'migrations/106_group_notification_display_outbox.dart';
import 'migrations/107_direct_notification_durability.dart';
import 'migrations/108_direct_inbox_custody_outbox.dart';
import 'migrations/109_direct_reaction_inbox_custody_outbox.dart';
import 'migrations/110_direct_media_custody_intent.dart';
import 'migrations/111_direct_media_blob_custody.dart';
import 'migrations/112_direct_linked_device_addressing.dart';
import 'migrations/113_direct_linked_device_event_fanout.dart';
import 'migrations/114_direct_linked_device_media_blob_fanout.dart';
import 'migrations/115_group_media_blob_custody.dart';

/// One ordered production migration step: the schema version it belongs to,
/// its migration-file stem, and the migration function itself.
class ProductionMigrationEntry {
  const ProductionMigrationEntry(this.version, this.name, this.run);

  final int version;
  final String name;
  final Future<void> Function(Database db) run;
}

/// The EXACT ordered fresh-install (onCreate) sequence from main.dart.
///
/// Intentional differences from the upgrade sequence (locked by
/// full_migration_chain_test.dart 'production registries preserve the exact
/// ordered v95 baseline'):
///  - 004 (nullify secret columns) is SKIPPED — 005 already ships nullable
///    columns + CHECK constraints;
///  - 005 runs inline (there are no pre-existing secrets to migrate first);
///  - 042 runs immediately after 010, before 011 (historical order).
final List<ProductionMigrationEntry>
productionCreateMigrations = List.unmodifiable(<ProductionMigrationEntry>[
  ProductionMigrationEntry(1, '001_identity_table', runIdentityTableMigration),
  ProductionMigrationEntry(2, '002_messages_table', runMessagesTableMigration),
  ProductionMigrationEntry(3, '003_mlkem_keys', runMlKemKeysMigration),
  ProductionMigrationEntry(
    5,
    '005_secret_null_checks',
    runSecretNullChecksMigration,
  ),
  ProductionMigrationEntry(6, '006_read_at_column', runReadAtColumnMigration),
  ProductionMigrationEntry(
    7,
    '007_archive_columns',
    runArchiveColumnsMigration,
  ),
  ProductionMigrationEntry(8, '008_block_columns', runBlockColumnsMigration),
  ProductionMigrationEntry(
    9,
    '009_quoted_message_id',
    runQuotedMessageIdMigration,
  ),
  ProductionMigrationEntry(
    10,
    '010_media_attachments',
    runMediaAttachmentsMigration,
  ),
  ProductionMigrationEntry(
    42,
    '042_media_attachment_reliability_columns',
    runMediaAttachmentReliabilityColumnsMigration,
  ),
  ProductionMigrationEntry(11, '011_avatar_version', runAvatarVersionMigration),
  ProductionMigrationEntry(
    12,
    '012_transport_column',
    runTransportColumnMigration,
  ),
  ProductionMigrationEntry(
    13,
    '013_waveform_column',
    runWaveformColumnMigration,
  ),
  ProductionMigrationEntry(
    14,
    '014_wire_envelope_column',
    runWireEnvelopeMigration,
  ),
  ProductionMigrationEntry(
    15,
    '015_message_status_cleanup',
    runMessageStatusCleanupMigration,
  ),
  ProductionMigrationEntry(
    16,
    '016_message_reactions',
    runMessageReactionsMigration,
  ),
  ProductionMigrationEntry(17, '017_groups_tables', runGroupsTablesMigration),
  ProductionMigrationEntry(
    18,
    '018_group_messages_tables',
    runGroupMessagesTablesMigration,
  ),
  ProductionMigrationEntry(
    19,
    '019_introductions_table',
    runIntroductionsTableMigration,
  ),
  ProductionMigrationEntry(
    20,
    '020_intro_banner_columns',
    runIntroBannerColumnsMigration,
  ),
  ProductionMigrationEntry(
    21,
    '021_contact_introduced_by',
    runContactIntroducedByMigration,
  ),
  ProductionMigrationEntry(
    22,
    '022_introduction_keys',
    runIntroductionKeysMigration,
  ),
  ProductionMigrationEntry(
    23,
    '023_introduction_recipient_keys',
    runIntroductionRecipientKeysMigration,
  ),
  ProductionMigrationEntry(
    24,
    '024_contact_introduced_by_peer_id',
    runContactIntroducedByPeerIdMigration,
  ),
  ProductionMigrationEntry(
    25,
    '025_introduction_already_connected_status',
    runIntroductionAlreadyConnectedMigration,
  ),
  ProductionMigrationEntry(
    26,
    '026_group_quoted_message_id',
    runGroupQuotedMessageIdMigration,
  ),
  ProductionMigrationEntry(27, '027_posts_core', runPostsCoreMigration),
  ProductionMigrationEntry(
    28,
    '028_posts_engagement',
    runPostsEngagementMigration,
  ),
  ProductionMigrationEntry(29, '029_posts_nearby', runPostsNearbyMigration),
  ProductionMigrationEntry(
    30,
    '030_posts_pass_along',
    runPostsPassAlongMigration,
  ),
  ProductionMigrationEntry(31, '031_posts_pins', runPostsPinsMigration),
  ProductionMigrationEntry(
    32,
    '032_posts_retry_recipient_context',
    runPostsRetryRecipientContextMigration,
  ),
  ProductionMigrationEntry(
    33,
    '033_posts_follow_on_outbox',
    runPostsFollowOnOutboxMigration,
  ),
  ProductionMigrationEntry(
    34,
    '034_posts_media_upload_recovery',
    runPostsMediaUploadRecoveryMigration,
  ),
  ProductionMigrationEntry(
    35,
    '035_posts_repost_delivery_state',
    runPostsRepostDeliveryStateMigration,
  ),
  ProductionMigrationEntry(
    36,
    '036_posts_pass_encrypted_snapshots',
    runPostsPassEncryptedSnapshotsMigration,
  ),
  ProductionMigrationEntry(
    37,
    '037_posts_repost_engagement_state',
    runPostsRepostEngagementStateMigration,
  ),
  ProductionMigrationEntry(
    38,
    '038_posts_repost_media_crypto',
    runPostsRepostMediaCryptoMigration,
  ),
  ProductionMigrationEntry(
    39,
    '039_posts_pass_avatar_snapshots',
    runPostsPassAvatarSnapshotsMigration,
  ),
  ProductionMigrationEntry(
    40,
    '040_posts_repost_visual_metrics',
    runPostsRepostVisualMetricsMigration,
  ),
  ProductionMigrationEntry(
    41,
    '041_group_message_reliability_columns',
    runGroupMessageReliabilityColumnsMigration,
  ),
  ProductionMigrationEntry(
    43,
    '043_messages_edited_at',
    runMessagesEditedAtMigration,
  ),
  ProductionMigrationEntry(
    44,
    '044_messages_deleted_state',
    runMessagesDeletedStateMigration,
  ),
  ProductionMigrationEntry(
    45,
    '045_inbox_staging_entries',
    runInboxStagingEntriesMigration,
  ),
  ProductionMigrationEntry(
    46,
    '046_pending_introduction_responses',
    runPendingIntroductionResponsesMigration,
  ),
  ProductionMigrationEntry(
    47,
    '047_introduction_outbox',
    runIntroductionOutboxMigration,
  ),
  ProductionMigrationEntry(
    48,
    '048_groups_last_membership_event_at',
    runGroupsLastMembershipEventAtMigration,
  ),
  ProductionMigrationEntry(
    49,
    '049_groups_metadata_columns',
    runGroupsMetadataColumnsMigration,
  ),
  ProductionMigrationEntry(
    50,
    '050_groups_mute_column',
    runGroupsMuteColumnMigration,
  ),
  ProductionMigrationEntry(
    51,
    '051_pending_group_invites',
    runPendingGroupInvitesMigration,
  ),
  ProductionMigrationEntry(
    52,
    '052_groups_dissolve_columns',
    runGroupsDissolveColumnsMigration,
  ),
  ProductionMigrationEntry(
    53,
    '053_groups_backlog_retention_columns',
    runGroupsBacklogRetentionColumnsMigration,
  ),
  ProductionMigrationEntry(
    54,
    '054_group_reaction_replay_outbox',
    runGroupReactionReplayOutboxMigration,
  ),
  ProductionMigrationEntry(
    55,
    '055_group_invite_revocations',
    runGroupInviteRevocationsMigration,
  ),
  ProductionMigrationEntry(
    56,
    '056_group_invite_consumptions',
    runGroupInviteConsumptionsMigration,
  ),
  ProductionMigrationEntry(
    57,
    '057_group_member_permissions',
    runGroupMemberPermissionsMigration,
  ),
  ProductionMigrationEntry(
    58,
    '058_media_attachment_integrity_columns',
    runMediaAttachmentIntegrityColumnsMigration,
  ),
  ProductionMigrationEntry(
    59,
    '059_media_attachment_encryption_columns',
    runMediaAttachmentEncryptionColumnsMigration,
  ),
  ProductionMigrationEntry(
    60,
    '060_group_event_log',
    runGroupEventLogMigration,
  ),
  ProductionMigrationEntry(
    61,
    '061_group_message_transport_peer_id',
    runGroupMessageTransportPeerIdMigration,
  ),
  ProductionMigrationEntry(
    62,
    '062_group_member_device_identities',
    runGroupMemberDeviceIdentitiesMigration,
  ),
  ProductionMigrationEntry(
    63,
    '063_group_pending_key_repairs',
    runGroupPendingKeyRepairsMigration,
  ),
  ProductionMigrationEntry(
    64,
    '064_group_welcome_key_package_tombstones',
    runGroupWelcomeKeyPackageTombstonesMigration,
  ),
  ProductionMigrationEntry(
    65,
    '065_group_history_gap_repairs',
    runGroupHistoryGapRepairsMigration,
  ),
  ProductionMigrationEntry(
    66,
    '066_group_sync_receipts',
    runGroupSyncReceiptsMigration,
  ),
  ProductionMigrationEntry(
    67,
    '067_group_invite_delivery_attempts',
    runGroupInviteDeliveryAttemptsMigration,
  ),
  ProductionMigrationEntry(
    68,
    '068_removed_group_member_snapshots',
    runRemovedGroupMemberSnapshotsMigration,
  ),
  ProductionMigrationEntry(
    69,
    '069_group_message_local_deletions',
    runGroupMessageLocalDeletionsMigration,
  ),
  ProductionMigrationEntry(
    70,
    '070_group_key_rotation_drafts',
    runGroupKeyRotationDraftsMigration,
  ),
  ProductionMigrationEntry(
    71,
    '071_pending_introduction_response_transport_sender',
    runPendingIntroductionResponseTransportSenderMigration,
  ),
  ProductionMigrationEntry(
    72,
    '072_group_pending_membership_messages',
    runGroupPendingMembershipMessagesMigration,
  ),
  ProductionMigrationEntry(
    73,
    '073_group_message_last_send_attempt_at',
    runGroupMessageLastSendAttemptAtMigration,
  ),
  ProductionMigrationEntry(
    74,
    '074_group_message_logical_delivery_id',
    runGroupMessageLogicalDeliveryIdMigration,
  ),
  ProductionMigrationEntry(
    75,
    '075_contacts_ml_kem_key_updated_ts',
    runContactsMlKemKeyUpdatedTsMigration,
  ),
  ProductionMigrationEntry(
    76,
    '076_post_media_attachment_crypto_columns',
    runPostMediaAttachmentCryptoColumnsMigration,
  ),
  ProductionMigrationEntry(
    77,
    '077_message_relay_custody',
    runMessageRelayCustodyMigration,
  ),
  ProductionMigrationEntry(
    78,
    '078_group_pending_key_distributions',
    runGroupPendingKeyDistributionsMigration,
  ),
  ProductionMigrationEntry(
    79,
    '079_message_dedup_key',
    runMessageDedupKeyMigration,
  ),
  ProductionMigrationEntry(
    80,
    '080_group_pending_key_repairs_status_index',
    runGroupPendingKeyRepairsStatusIndexMigration,
  ),
  ProductionMigrationEntry(
    81,
    '081_group_pending_reactions',
    runGroupPendingReactionsMigration,
  ),
  ProductionMigrationEntry(
    82,
    '082_message_reaction_tombstone',
    runMessageReactionTombstoneMigration,
  ),
  ProductionMigrationEntry(
    83,
    '083_groups_last_membership_event_id',
    runGroupsLastMembershipEventIdMigration,
  ),
  ProductionMigrationEntry(
    84,
    '084_group_member_device_snapshots',
    runGroupMemberDeviceSnapshotsMigration,
  ),
  ProductionMigrationEntry(
    85,
    '085_pending_sibling_devices',
    runPendingSiblingDevicesMigration,
  ),
  ProductionMigrationEntry(
    86,
    '086_pending_group_broadcasts',
    runPendingGroupBroadcastsMigration,
  ),
  ProductionMigrationEntry(
    87,
    '087_group_message_retry_backoff_columns',
    runGroupMessageRetryBackoffColumnsMigration,
  ),
  ProductionMigrationEntry(
    88,
    '088_group_rejoin_state',
    runGroupRejoinStateMigration,
  ),
  ProductionMigrationEntry(
    89,
    '089_media_attachment_download_retry_column',
    runMediaAttachmentDownloadRetryColumnMigration,
  ),
  ProductionMigrationEntry(
    90,
    '090_group_invite_delivery_attempts_revoked_declined',
    runGroupInviteDeliveryAttemptsRevokedDeclinedMigration,
  ),
  ProductionMigrationEntry(
    91,
    '091_pending_group_invites_inviter_mlkem',
    runPendingGroupInvitesInviterMlKemMigration,
  ),
  ProductionMigrationEntry(
    92,
    '092_feed_cleared_threads',
    runFeedClearedThreadsMigration,
  ),
  ProductionMigrationEntry(
    93,
    '093_messages_contact_ts_index',
    runMessagesContactTsIndexMigration,
  ),
  ProductionMigrationEntry(
    94,
    '094_group_messages_group_ts_index',
    runGroupMessagesGroupTsIndexMigration,
  ),
  ProductionMigrationEntry(
    95,
    '095_intro_review_seen',
    runIntroReviewSeenMigration,
  ),
  ProductionMigrationEntry(
    96,
    '096_media_library_state',
    runMediaLibraryStateMigration,
  ),
  ProductionMigrationEntry(
    97,
    '097_direct_message_forwarded',
    runDirectMessageForwardedMigration,
  ),
  ProductionMigrationEntry(
    98,
    '098_group_media_deletion_journal',
    runGroupMediaDeletionJournalMigration,
  ),
  ProductionMigrationEntry(
    99,
    '099_group_messages_is_forwarded',
    runGroupMessagesIsForwardedMigration,
  ),
  ProductionMigrationEntry(
    100,
    '100_direct_private_media_lifecycle',
    runDirectPrivateMediaLifecycleMigration,
  ),
  ProductionMigrationEntry(
    101,
    '101_group_private_media_lifecycle',
    runGroupPrivateMediaLifecycleMigration,
  ),
  ProductionMigrationEntry(
    102,
    '102_groups_self_removed_at',
    runGroupsSelfRemovedAtMigration,
  ),
  ProductionMigrationEntry(
    103,
    '103_group_exit_intents',
    runGroupExitIntentsMigration,
  ),
  ProductionMigrationEntry(
    104,
    '104_group_exit_diagnostics',
    runGroupExitDiagnosticsMigration,
  ),
  ProductionMigrationEntry(
    105,
    '105_reaction_outbox_needs_build',
    runReactionOutboxNeedsBuildMigration,
  ),
  ProductionMigrationEntry(
    106,
    '106_group_notification_display_outbox',
    runGroupNotificationDisplayOutboxMigration,
  ),
  ProductionMigrationEntry(
    107,
    '107_direct_notification_durability',
    runDirectNotificationDurabilityMigration,
  ),
  ProductionMigrationEntry(
    108,
    '108_direct_inbox_custody_outbox',
    runDirectInboxCustodyOutboxMigration,
  ),
  ProductionMigrationEntry(
    109,
    '109_direct_reaction_inbox_custody_outbox',
    runDirectReactionInboxCustodyOutboxMigration,
  ),
  ProductionMigrationEntry(
    110,
    '110_direct_media_custody_intent',
    runDirectMediaCustodyIntentMigration,
  ),
  ProductionMigrationEntry(
    111,
    '111_direct_media_blob_custody',
    runDirectMediaBlobCustodyMigration,
  ),
  ProductionMigrationEntry(
    112,
    '112_direct_linked_device_addressing',
    runDirectLinkedDeviceAddressingMigration,
  ),
  ProductionMigrationEntry(
    113,
    '113_direct_linked_device_event_fanout',
    runDirectLinkedDeviceEventFanoutMigration,
  ),
  ProductionMigrationEntry(
    114,
    '114_direct_linked_device_media_blob_fanout',
    runDirectLinkedDeviceMediaBlobFanoutMigration,
  ),
  ProductionMigrationEntry(
    115,
    '115_group_media_blob_custody',
    runGroupMediaBlobCustodyMigration,
  ),
]);

/// The EXACT ordered upgrade (onUpgrade) guard sequence from main.dart.
///
/// Intentional differences from the create sequence (locked by the same
/// baseline test):
///  - 004 (nullify secret columns) RUNS on upgrade;
///  - 005 is DEFERRED — main.dart runs it post-open, after
///    migrateSecretsToSecureStorage, so CHECK constraints never reject
///    existing non-null secrets during the rebuild;
///  - 042 runs immediately after 010, before 011 (historical order).
final List<ProductionMigrationEntry>
productionUpgradeMigrations = List.unmodifiable(<ProductionMigrationEntry>[
  ProductionMigrationEntry(2, '002_messages_table', runMessagesTableMigration),
  ProductionMigrationEntry(3, '003_mlkem_keys', runMlKemKeysMigration),
  ProductionMigrationEntry(
    4,
    '004_nullify_secret_columns',
    runNullifySecretColumnsMigration,
  ),
  ProductionMigrationEntry(6, '006_read_at_column', runReadAtColumnMigration),
  ProductionMigrationEntry(
    7,
    '007_archive_columns',
    runArchiveColumnsMigration,
  ),
  ProductionMigrationEntry(8, '008_block_columns', runBlockColumnsMigration),
  ProductionMigrationEntry(
    9,
    '009_quoted_message_id',
    runQuotedMessageIdMigration,
  ),
  ProductionMigrationEntry(
    10,
    '010_media_attachments',
    runMediaAttachmentsMigration,
  ),
  ProductionMigrationEntry(
    42,
    '042_media_attachment_reliability_columns',
    runMediaAttachmentReliabilityColumnsMigration,
  ),
  ProductionMigrationEntry(11, '011_avatar_version', runAvatarVersionMigration),
  ProductionMigrationEntry(
    12,
    '012_transport_column',
    runTransportColumnMigration,
  ),
  ProductionMigrationEntry(
    13,
    '013_waveform_column',
    runWaveformColumnMigration,
  ),
  ProductionMigrationEntry(
    14,
    '014_wire_envelope_column',
    runWireEnvelopeMigration,
  ),
  ProductionMigrationEntry(
    15,
    '015_message_status_cleanup',
    runMessageStatusCleanupMigration,
  ),
  ProductionMigrationEntry(
    16,
    '016_message_reactions',
    runMessageReactionsMigration,
  ),
  ProductionMigrationEntry(17, '017_groups_tables', runGroupsTablesMigration),
  ProductionMigrationEntry(
    18,
    '018_group_messages_tables',
    runGroupMessagesTablesMigration,
  ),
  ProductionMigrationEntry(
    19,
    '019_introductions_table',
    runIntroductionsTableMigration,
  ),
  ProductionMigrationEntry(
    20,
    '020_intro_banner_columns',
    runIntroBannerColumnsMigration,
  ),
  ProductionMigrationEntry(
    21,
    '021_contact_introduced_by',
    runContactIntroducedByMigration,
  ),
  ProductionMigrationEntry(
    22,
    '022_introduction_keys',
    runIntroductionKeysMigration,
  ),
  ProductionMigrationEntry(
    23,
    '023_introduction_recipient_keys',
    runIntroductionRecipientKeysMigration,
  ),
  ProductionMigrationEntry(
    24,
    '024_contact_introduced_by_peer_id',
    runContactIntroducedByPeerIdMigration,
  ),
  ProductionMigrationEntry(
    25,
    '025_introduction_already_connected_status',
    runIntroductionAlreadyConnectedMigration,
  ),
  ProductionMigrationEntry(
    26,
    '026_group_quoted_message_id',
    runGroupQuotedMessageIdMigration,
  ),
  ProductionMigrationEntry(27, '027_posts_core', runPostsCoreMigration),
  ProductionMigrationEntry(
    28,
    '028_posts_engagement',
    runPostsEngagementMigration,
  ),
  ProductionMigrationEntry(29, '029_posts_nearby', runPostsNearbyMigration),
  ProductionMigrationEntry(
    30,
    '030_posts_pass_along',
    runPostsPassAlongMigration,
  ),
  ProductionMigrationEntry(31, '031_posts_pins', runPostsPinsMigration),
  ProductionMigrationEntry(
    32,
    '032_posts_retry_recipient_context',
    runPostsRetryRecipientContextMigration,
  ),
  ProductionMigrationEntry(
    33,
    '033_posts_follow_on_outbox',
    runPostsFollowOnOutboxMigration,
  ),
  ProductionMigrationEntry(
    34,
    '034_posts_media_upload_recovery',
    runPostsMediaUploadRecoveryMigration,
  ),
  ProductionMigrationEntry(
    35,
    '035_posts_repost_delivery_state',
    runPostsRepostDeliveryStateMigration,
  ),
  ProductionMigrationEntry(
    36,
    '036_posts_pass_encrypted_snapshots',
    runPostsPassEncryptedSnapshotsMigration,
  ),
  ProductionMigrationEntry(
    37,
    '037_posts_repost_engagement_state',
    runPostsRepostEngagementStateMigration,
  ),
  ProductionMigrationEntry(
    38,
    '038_posts_repost_media_crypto',
    runPostsRepostMediaCryptoMigration,
  ),
  ProductionMigrationEntry(
    39,
    '039_posts_pass_avatar_snapshots',
    runPostsPassAvatarSnapshotsMigration,
  ),
  ProductionMigrationEntry(
    40,
    '040_posts_repost_visual_metrics',
    runPostsRepostVisualMetricsMigration,
  ),
  ProductionMigrationEntry(
    41,
    '041_group_message_reliability_columns',
    runGroupMessageReliabilityColumnsMigration,
  ),
  ProductionMigrationEntry(
    43,
    '043_messages_edited_at',
    runMessagesEditedAtMigration,
  ),
  ProductionMigrationEntry(
    44,
    '044_messages_deleted_state',
    runMessagesDeletedStateMigration,
  ),
  ProductionMigrationEntry(
    45,
    '045_inbox_staging_entries',
    runInboxStagingEntriesMigration,
  ),
  ProductionMigrationEntry(
    46,
    '046_pending_introduction_responses',
    runPendingIntroductionResponsesMigration,
  ),
  ProductionMigrationEntry(
    47,
    '047_introduction_outbox',
    runIntroductionOutboxMigration,
  ),
  ProductionMigrationEntry(
    48,
    '048_groups_last_membership_event_at',
    runGroupsLastMembershipEventAtMigration,
  ),
  ProductionMigrationEntry(
    49,
    '049_groups_metadata_columns',
    runGroupsMetadataColumnsMigration,
  ),
  ProductionMigrationEntry(
    50,
    '050_groups_mute_column',
    runGroupsMuteColumnMigration,
  ),
  ProductionMigrationEntry(
    51,
    '051_pending_group_invites',
    runPendingGroupInvitesMigration,
  ),
  ProductionMigrationEntry(
    52,
    '052_groups_dissolve_columns',
    runGroupsDissolveColumnsMigration,
  ),
  ProductionMigrationEntry(
    53,
    '053_groups_backlog_retention_columns',
    runGroupsBacklogRetentionColumnsMigration,
  ),
  ProductionMigrationEntry(
    54,
    '054_group_reaction_replay_outbox',
    runGroupReactionReplayOutboxMigration,
  ),
  ProductionMigrationEntry(
    55,
    '055_group_invite_revocations',
    runGroupInviteRevocationsMigration,
  ),
  ProductionMigrationEntry(
    56,
    '056_group_invite_consumptions',
    runGroupInviteConsumptionsMigration,
  ),
  ProductionMigrationEntry(
    57,
    '057_group_member_permissions',
    runGroupMemberPermissionsMigration,
  ),
  ProductionMigrationEntry(
    58,
    '058_media_attachment_integrity_columns',
    runMediaAttachmentIntegrityColumnsMigration,
  ),
  ProductionMigrationEntry(
    59,
    '059_media_attachment_encryption_columns',
    runMediaAttachmentEncryptionColumnsMigration,
  ),
  ProductionMigrationEntry(
    60,
    '060_group_event_log',
    runGroupEventLogMigration,
  ),
  ProductionMigrationEntry(
    61,
    '061_group_message_transport_peer_id',
    runGroupMessageTransportPeerIdMigration,
  ),
  ProductionMigrationEntry(
    62,
    '062_group_member_device_identities',
    runGroupMemberDeviceIdentitiesMigration,
  ),
  ProductionMigrationEntry(
    63,
    '063_group_pending_key_repairs',
    runGroupPendingKeyRepairsMigration,
  ),
  ProductionMigrationEntry(
    64,
    '064_group_welcome_key_package_tombstones',
    runGroupWelcomeKeyPackageTombstonesMigration,
  ),
  ProductionMigrationEntry(
    65,
    '065_group_history_gap_repairs',
    runGroupHistoryGapRepairsMigration,
  ),
  ProductionMigrationEntry(
    66,
    '066_group_sync_receipts',
    runGroupSyncReceiptsMigration,
  ),
  ProductionMigrationEntry(
    67,
    '067_group_invite_delivery_attempts',
    runGroupInviteDeliveryAttemptsMigration,
  ),
  ProductionMigrationEntry(
    68,
    '068_removed_group_member_snapshots',
    runRemovedGroupMemberSnapshotsMigration,
  ),
  ProductionMigrationEntry(
    69,
    '069_group_message_local_deletions',
    runGroupMessageLocalDeletionsMigration,
  ),
  ProductionMigrationEntry(
    70,
    '070_group_key_rotation_drafts',
    runGroupKeyRotationDraftsMigration,
  ),
  ProductionMigrationEntry(
    71,
    '071_pending_introduction_response_transport_sender',
    runPendingIntroductionResponseTransportSenderMigration,
  ),
  ProductionMigrationEntry(
    72,
    '072_group_pending_membership_messages',
    runGroupPendingMembershipMessagesMigration,
  ),
  ProductionMigrationEntry(
    73,
    '073_group_message_last_send_attempt_at',
    runGroupMessageLastSendAttemptAtMigration,
  ),
  ProductionMigrationEntry(
    74,
    '074_group_message_logical_delivery_id',
    runGroupMessageLogicalDeliveryIdMigration,
  ),
  ProductionMigrationEntry(
    75,
    '075_contacts_ml_kem_key_updated_ts',
    runContactsMlKemKeyUpdatedTsMigration,
  ),
  ProductionMigrationEntry(
    76,
    '076_post_media_attachment_crypto_columns',
    runPostMediaAttachmentCryptoColumnsMigration,
  ),
  ProductionMigrationEntry(
    77,
    '077_message_relay_custody',
    runMessageRelayCustodyMigration,
  ),
  ProductionMigrationEntry(
    78,
    '078_group_pending_key_distributions',
    runGroupPendingKeyDistributionsMigration,
  ),
  ProductionMigrationEntry(
    79,
    '079_message_dedup_key',
    runMessageDedupKeyMigration,
  ),
  ProductionMigrationEntry(
    80,
    '080_group_pending_key_repairs_status_index',
    runGroupPendingKeyRepairsStatusIndexMigration,
  ),
  ProductionMigrationEntry(
    81,
    '081_group_pending_reactions',
    runGroupPendingReactionsMigration,
  ),
  ProductionMigrationEntry(
    82,
    '082_message_reaction_tombstone',
    runMessageReactionTombstoneMigration,
  ),
  ProductionMigrationEntry(
    83,
    '083_groups_last_membership_event_id',
    runGroupsLastMembershipEventIdMigration,
  ),
  ProductionMigrationEntry(
    84,
    '084_group_member_device_snapshots',
    runGroupMemberDeviceSnapshotsMigration,
  ),
  ProductionMigrationEntry(
    85,
    '085_pending_sibling_devices',
    runPendingSiblingDevicesMigration,
  ),
  ProductionMigrationEntry(
    86,
    '086_pending_group_broadcasts',
    runPendingGroupBroadcastsMigration,
  ),
  ProductionMigrationEntry(
    87,
    '087_group_message_retry_backoff_columns',
    runGroupMessageRetryBackoffColumnsMigration,
  ),
  ProductionMigrationEntry(
    88,
    '088_group_rejoin_state',
    runGroupRejoinStateMigration,
  ),
  ProductionMigrationEntry(
    89,
    '089_media_attachment_download_retry_column',
    runMediaAttachmentDownloadRetryColumnMigration,
  ),
  ProductionMigrationEntry(
    90,
    '090_group_invite_delivery_attempts_revoked_declined',
    runGroupInviteDeliveryAttemptsRevokedDeclinedMigration,
  ),
  ProductionMigrationEntry(
    91,
    '091_pending_group_invites_inviter_mlkem',
    runPendingGroupInvitesInviterMlKemMigration,
  ),
  ProductionMigrationEntry(
    92,
    '092_feed_cleared_threads',
    runFeedClearedThreadsMigration,
  ),
  ProductionMigrationEntry(
    93,
    '093_messages_contact_ts_index',
    runMessagesContactTsIndexMigration,
  ),
  ProductionMigrationEntry(
    94,
    '094_group_messages_group_ts_index',
    runGroupMessagesGroupTsIndexMigration,
  ),
  ProductionMigrationEntry(
    95,
    '095_intro_review_seen',
    runIntroReviewSeenMigration,
  ),
  ProductionMigrationEntry(
    96,
    '096_media_library_state',
    runMediaLibraryStateMigration,
  ),
  ProductionMigrationEntry(
    97,
    '097_direct_message_forwarded',
    runDirectMessageForwardedMigration,
  ),
  ProductionMigrationEntry(
    98,
    '098_group_media_deletion_journal',
    runGroupMediaDeletionJournalMigration,
  ),
  ProductionMigrationEntry(
    99,
    '099_group_messages_is_forwarded',
    runGroupMessagesIsForwardedMigration,
  ),
  ProductionMigrationEntry(
    100,
    '100_direct_private_media_lifecycle',
    runDirectPrivateMediaLifecycleMigration,
  ),
  ProductionMigrationEntry(
    101,
    '101_group_private_media_lifecycle',
    runGroupPrivateMediaLifecycleMigration,
  ),
  ProductionMigrationEntry(
    102,
    '102_groups_self_removed_at',
    runGroupsSelfRemovedAtMigration,
  ),
  ProductionMigrationEntry(
    103,
    '103_group_exit_intents',
    runGroupExitIntentsMigration,
  ),
  ProductionMigrationEntry(
    104,
    '104_group_exit_diagnostics',
    runGroupExitDiagnosticsMigration,
  ),
  ProductionMigrationEntry(
    105,
    '105_reaction_outbox_needs_build',
    runReactionOutboxNeedsBuildMigration,
  ),
  ProductionMigrationEntry(
    106,
    '106_group_notification_display_outbox',
    runGroupNotificationDisplayOutboxMigration,
  ),
  ProductionMigrationEntry(
    107,
    '107_direct_notification_durability',
    runDirectNotificationDurabilityMigration,
  ),
  ProductionMigrationEntry(
    108,
    '108_direct_inbox_custody_outbox',
    runDirectInboxCustodyOutboxMigration,
  ),
  ProductionMigrationEntry(
    109,
    '109_direct_reaction_inbox_custody_outbox',
    runDirectReactionInboxCustodyOutboxMigration,
  ),
  ProductionMigrationEntry(
    110,
    '110_direct_media_custody_intent',
    runDirectMediaCustodyIntentMigration,
  ),
  ProductionMigrationEntry(
    111,
    '111_direct_media_blob_custody',
    runDirectMediaBlobCustodyMigration,
  ),
  ProductionMigrationEntry(
    112,
    '112_direct_linked_device_addressing',
    runDirectLinkedDeviceAddressingMigration,
  ),
  ProductionMigrationEntry(
    113,
    '113_direct_linked_device_event_fanout',
    runDirectLinkedDeviceEventFanoutMigration,
  ),
  ProductionMigrationEntry(
    114,
    '114_direct_linked_device_media_blob_fanout',
    runDirectLinkedDeviceMediaBlobFanoutMigration,
  ),
  ProductionMigrationEntry(
    115,
    '115_group_media_blob_custody',
    runGroupMediaBlobCustodyMigration,
  ),
]);

/// Production onCreate callback: runs every create entry whose version is
/// within [targetVersion], in the exact recorded order. Target-version-aware
/// so tests (and the SQLCipher device proof) can literally create a v95
/// database through the same callback production uses.
Future<void> runProductionOnCreate(Database db, int targetVersion) async {
  for (final entry in productionCreateMigrations) {
    if (entry.version <= targetVersion) {
      await entry.run(db);
    }
  }
}

/// Production onUpgrade callback: runs every upgrade entry gated by the same
/// `oldVersion < version` guard main.dart used, in the exact recorded order,
/// bounded by [newVersion] so tests can replay a literal historical upgrade.
///
/// NOTE: migration 005 is deliberately absent — main.dart runs it after
/// migrateSecretsToSecureStorage post-open (see main.dart step 3/4).
Future<void> runProductionOnUpgrade(
  Database db,
  int oldVersion,
  int newVersion,
) async {
  for (final entry in productionUpgradeMigrations) {
    if (oldVersion < entry.version && entry.version <= newVersion) {
      await entry.run(db);
    }
  }
}
