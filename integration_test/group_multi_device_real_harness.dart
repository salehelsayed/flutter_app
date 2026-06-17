import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite_sqlcipher/sqflite.dart' as sqlcipher;

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/bridge/bridge_group_helpers.dart';
import 'package:flutter_app/core/bridge/go_bridge_client.dart';
import 'package:flutter_app/core/database/encrypted_db_opener.dart';
import 'package:flutter_app/core/database/helpers/contacts_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_keys_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_invite_delivery_attempts_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_members_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_messages_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_pending_key_repairs_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_reaction_replay_outbox_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_sync_receipts_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/groups_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/identity_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/media_attachments_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/reactions_db_helpers.dart';
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
import 'package:flutter_app/core/database/migrations/081_group_pending_reactions.dart';
import 'package:flutter_app/core/database/migrations/082_message_reaction_tombstone.dart';
import 'package:flutter_app/core/database/migrations/083_groups_last_membership_event_id.dart';
import 'package:flutter_app/core/database/migrations/089_media_attachment_download_retry_column.dart';
import 'package:flutter_app/core/database/migrations/090_group_invite_delivery_attempts_revoked_declined.dart';
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
import 'package:flutter_app/core/database/migrations/075_contacts_ml_kem_key_updated_ts.dart';
import 'package:flutter_app/core/database/migrations/076_post_media_attachment_crypto_columns.dart';
import 'package:flutter_app/core/database/migrations/077_message_relay_custody.dart';
import 'package:flutter_app/core/database/migrations/078_group_pending_key_distributions.dart';
import 'package:flutter_app/core/notifications/active_conversation_tracker.dart';
import 'package:flutter_app/core/secure_storage/secure_key_store.dart';
import 'package:flutter_app/core/services/incoming_message_router.dart';
import 'package:flutter_app/core/services/p2p_service_impl.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository_impl.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository_impl.dart';
import 'package:flutter_app/features/conversation/domain/repositories/reaction_repository_impl.dart';
import 'package:flutter_app/features/groups/application/add_group_member_use_case.dart';
import 'package:flutter_app/features/groups/application/create_group_with_members_use_case.dart';
import 'package:flutter_app/features/groups/application/drain_group_offline_inbox_use_case.dart';
import 'package:flutter_app/features/groups/application/group_config_payload.dart';
import 'package:flutter_app/features/groups/application/group_key_update_listener.dart';
import 'package:flutter_app/features/groups/application/group_membership_update_listener.dart';
import 'package:flutter_app/features/groups/application/group_offline_replay_envelope.dart';
import 'package:flutter_app/features/groups/application/group_message_listener.dart';
import 'package:flutter_app/features/groups/application/rejoin_group_topics_use_case.dart';
import 'package:flutter_app/features/groups/application/rotate_and_distribute_group_key_use_case.dart';
import 'package:flutter_app/features/groups/application/admit_sibling_device_use_case.dart';
import 'package:flutter_app/features/groups/application/announce_restored_device_use_case.dart';
import 'package:flutter_app/features/groups/application/group_pending_key_distribution_service.dart';
import 'package:flutter_app/features/groups/domain/models/group_pending_key_distribution.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_pending_key_distribution_repository_impl.dart';
import 'package:flutter_app/core/database/helpers/group_pending_key_distributions_db_helpers.dart';
import 'package:flutter_app/features/groups/application/send_group_message_use_case.dart';
import 'package:flutter_app/features/groups/application/set_group_muted_use_case.dart';
import 'package:flutter_app/features/groups/application/decline_pending_group_invite_use_case.dart';
import 'package:flutter_app/features/groups/application/group_invite_listener.dart';
import 'package:flutter_app/features/groups/application/on_join_group_config_resync_use_case.dart';
import 'package:flutter_app/features/groups/application/resend_group_invite_use_case.dart';
import 'package:flutter_app/features/groups/application/revoke_pending_group_invite_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_invite_delivery_attempt.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository_impl.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_invite_delivery_attempt_repository_impl.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_pending_key_repair_repository_impl.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_reaction_replay_outbox_repository_impl.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository_impl.dart';
import 'package:flutter_app/features/identity/application/generate_identity_use_case.dart';
import 'package:flutter_app/features/identity/application/restore_identity_use_case.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository_impl.dart';

import '../test/shared/fakes/fake_notification_service.dart';
import '../test/shared/fakes/in_memory_inbox_staging_repository.dart';
import '../test/shared/fakes/in_memory_pending_group_invite_repository.dart';

const configuredSharedDir = String.fromEnvironment(
  'E2E_SHARED_DIR',
  defaultValue: '/tmp',
);
const configuredCliPeerFixture = String.fromEnvironment(
  'CLI_PEER_FIXTURE',
  defaultValue: '',
);
const configuredRole = String.fromEnvironment(
  'MD004_ROLE',
  defaultValue: 'primary',
);
const configuredRunId = String.fromEnvironment(
  'MD004_RUN_ID',
  defaultValue: 'adhoc',
);
const configuredDbName = String.fromEnvironment(
  'E2E_DB_NAME',
  defaultValue: '',
);
const configuredScenario = String.fromEnvironment(
  'MD004_SCENARIO',
  defaultValue: 'same_user',
);

String sharedPath(String name) => '$configuredSharedDir/$name';

void initializeSqliteForCurrentPlatform() {
  if (Platform.isLinux || Platform.isMacOS || Platform.isWindows) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
}

Map<String, dynamic>? loadCliPeerFixture() {
  final fixturePath = configuredCliPeerFixture.isNotEmpty
      ? configuredCliPeerFixture
      : sharedPath('group_multi_device_cli_peer_fixture.json');
  final file = File(fixturePath);
  if (!file.existsSync()) return null;

  try {
    return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  } catch (_) {
    return null;
  }
}

void _writeSharedAtomically(String name, String value) {
  Directory(configuredSharedDir).createSync(recursive: true);
  final targetPath = sharedPath(name);
  final tempPath =
      '$targetPath.tmp.$pid.${DateTime.now().microsecondsSinceEpoch}';
  final tempFile = File(tempPath);
  try {
    tempFile.writeAsStringSync(value, flush: true);
    tempFile.renameSync(targetPath);
  } finally {
    if (tempFile.existsSync()) {
      try {
        tempFile.deleteSync();
      } catch (_) {}
    }
  }
}

void writeSharedJson(String name, Map<String, dynamic> value) {
  _writeSharedAtomically(name, jsonEncode(value));
}

void writeSharedText(String name, String value) {
  _writeSharedAtomically(name, value);
}

Future<Map<String, dynamic>> waitForSharedJson(
  String name, {
  Duration timeout = const Duration(seconds: 180),
}) async {
  final deadline = DateTime.now().add(timeout);
  final file = File(sharedPath(name));
  Object? lastDecodeError;
  while (DateTime.now().isBefore(deadline)) {
    if (file.existsSync()) {
      try {
        return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      } on FormatException catch (error) {
        lastDecodeError = error;
      } on FileSystemException catch (error) {
        lastDecodeError = error;
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
  if (lastDecodeError != null) {
    throw TimeoutException(
      'Timed out waiting for complete shared json: $name; last error: '
      '$lastDecodeError',
    );
  }
  throw TimeoutException('Timed out waiting for shared json: $name');
}

Future<void> waitForSharedSignal(
  String name, {
  Duration timeout = const Duration(seconds: 180),
}) async {
  final deadline = DateTime.now().add(timeout);
  final file = File(sharedPath(name));
  while (DateTime.now().isBefore(deadline)) {
    if (file.existsSync()) return;
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
  throw TimeoutException('Timed out waiting for shared signal: $name');
}

Future<void> waitForCondition(
  Future<bool> Function() condition, {
  Duration timeout = const Duration(seconds: 60),
  Duration interval = const Duration(milliseconds: 200),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (await condition()) return;
    await Future<void>.delayed(interval);
  }
  throw TimeoutException('Timed out waiting for condition');
}

String _secureStorePathForDb(String dbName) {
  final safeName = dbName.replaceAll(RegExp('[^A-Za-z0-9_.-]'), '_');
  return sharedPath('secure_store_$safeName.json');
}

Future<void> deleteTestSecureStore(String dbName) async {
  try {
    final file = File(_secureStorePathForDb(dbName));
    if (file.existsSync()) {
      file.deleteSync();
    }
  } catch (_) {}
}

class _FakeSecureKeyStore implements SecureKeyStore {
  _FakeSecureKeyStore({String? dbName})
    : _persistenceFile = dbName == null || dbName.isEmpty
          ? null
          : File(_secureStorePathForDb(dbName)) {
    final file = _persistenceFile;
    if (file == null || !file.existsSync()) return;
    try {
      final persisted = jsonDecode(file.readAsStringSync());
      if (persisted is Map<String, dynamic>) {
        for (final entry in persisted.entries) {
          if (entry.value is String) {
            _store[entry.key] = entry.value as String;
          }
        }
      }
    } catch (_) {}
  }

  final File? _persistenceFile;
  final Map<String, String> _store = {};

  @override
  Future<String?> read(String key) async => _store[key];

  @override
  Future<void> write(String key, String value) async {
    _store[key] = value;
    _flush();
  }

  @override
  Future<void> delete(String key) async {
    _store.remove(key);
    _flush();
  }

  @override
  Future<bool> containsKey(String key) async => _store.containsKey(key);

  void _flush() {
    final file = _persistenceFile;
    if (file == null) return;
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(jsonEncode(_store));
  }
}

Future<void> deleteTestDatabase(String dbName) async {
  try {
    final dbPath = await sqlcipher.getDatabasesPath();
    final fullPath = '$dbPath/$dbName';
    for (final path in [
      fullPath,
      '$fullPath-wal',
      '$fullPath-shm',
      '$fullPath.encrypted',
    ]) {
      final file = File(path);
      if (file.existsSync()) {
        file.deleteSync();
      }
    }
    await sqlcipher.deleteDatabase(fullPath);
  } catch (_) {}
}

Future<sqlcipher.Database> _openTestDatabase({
  required SecureKeyStore secureKeyStore,
  required String dbName,
}) async {
  return openEncryptedDatabase(
    secureKeyStore: secureKeyStore,
    dbName: dbName,
    version: 77,
    onCreate: (db, version) async {
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
      await runMediaAttachmentReliabilityColumnsMigration(db);
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
      await runGroupSyncReceiptsMigration(db);
      await runGroupInviteDeliveryAttemptsMigration(db);
      await runRemovedGroupMemberSnapshotsMigration(db);
      await runGroupMessageLocalDeletionsMigration(db);
      await runGroupKeyRotationDraftsMigration(db);
      await runPendingIntroductionResponseTransportSenderMigration(db);
      await runGroupPendingMembershipMessagesMigration(db);
      await runGroupMessageLastSendAttemptAtMigration(db);
      await runGroupMessageLogicalDeliveryIdMigration(db);
      await runContactsMlKemKeyUpdatedTsMigration(db);
      await runPostMediaAttachmentCryptoColumnsMigration(db);
      await runMessageRelayCustodyMigration(db);
      // R6 b1b: the deferred per-device key-distribution table (078). The
      // sibling-admit redistribution path upserts/reopens rows here, so the
      // harness schema must have it (else reopen/drain sinks throw and the
      // sibling never converges).
      await runGroupPendingKeyDistributionsMigration(db);
      // Finding 10 reaction reliability: durable buffer (081) + message_reactions
      // removed_at tombstone (082). 082 is REQUIRED — reaction insert/load/remove
      // all reference removed_at once Phase 5 lands.
      await runGroupPendingReactionsMigration(db);
      await runMessageReactionTombstoneMigration(db);
      // Concurrent finding-07 landing: groups.last_membership_event_id (083).
      // The lib group-save writes it, so the harness schema must have it too.
      await runGroupsLastMembershipEventIdMigration(db);
      // Finding 09 Phase 3: media_attachments.download_retry_count (089). The
      // download use case reads/writes it, so the harness schema must have it.
      await runMediaAttachmentDownloadRetryColumnMigration(db);
      // Review-08 findings C+F: widen invite delivery-attempt CHECK to
      // 'revoked'/'declined' + add invite_id (HOLE-4). The invite-reliability
      // scenario persists those statuses + the id, so the harness needs it.
      await runGroupInviteDeliveryAttemptsRevokedDeclinedMigration(db);
    },
    onUpgrade: (db, oldVersion, newVersion) async {
      if (oldVersion < 2) await runMessagesTableMigration(db);
      if (oldVersion < 3) await runMlKemKeysMigration(db);
      if (oldVersion < 4) await runNullifySecretColumnsMigration(db);
      if (oldVersion < 5) await runSecretNullChecksMigration(db);
      if (oldVersion < 6) await runReadAtColumnMigration(db);
      if (oldVersion < 7) await runArchiveColumnsMigration(db);
      if (oldVersion < 8) await runBlockColumnsMigration(db);
      if (oldVersion < 9) await runQuotedMessageIdMigration(db);
      if (oldVersion < 10) await runMediaAttachmentsMigration(db);
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
      if (oldVersion < 41) await runGroupMessageReliabilityColumnsMigration(db);
      if (oldVersion < 42) {
        await runMediaAttachmentReliabilityColumnsMigration(db);
      }
      if (oldVersion < 43) await runMessagesEditedAtMigration(db);
      if (oldVersion < 44) await runMessagesDeletedStateMigration(db);
      if (oldVersion < 45) await runInboxStagingEntriesMigration(db);
      if (oldVersion < 46) {
        await runPendingIntroductionResponsesMigration(db);
      }
      if (oldVersion < 47) await runIntroductionOutboxMigration(db);
      if (oldVersion < 48) await runGroupsLastMembershipEventAtMigration(db);
      if (oldVersion < 49) await runGroupsMetadataColumnsMigration(db);
      if (oldVersion < 50) await runGroupsMuteColumnMigration(db);
      if (oldVersion < 51) await runPendingGroupInvitesMigration(db);
      if (oldVersion < 52) await runGroupsDissolveColumnsMigration(db);
      if (oldVersion < 53) await runGroupsBacklogRetentionColumnsMigration(db);
      if (oldVersion < 54) await runGroupReactionReplayOutboxMigration(db);
      if (oldVersion < 55) await runGroupInviteRevocationsMigration(db);
      if (oldVersion < 56) await runGroupInviteConsumptionsMigration(db);
      if (oldVersion < 57) await runGroupMemberPermissionsMigration(db);
      if (oldVersion < 58) {
        await runMediaAttachmentIntegrityColumnsMigration(db);
      }
      if (oldVersion < 59) {
        await runMediaAttachmentEncryptionColumnsMigration(db);
      }
      if (oldVersion < 60) await runGroupEventLogMigration(db);
      if (oldVersion < 61) {
        await runGroupMessageTransportPeerIdMigration(db);
      }
      if (oldVersion < 62) await runGroupMemberDeviceIdentitiesMigration(db);
      if (oldVersion < 63) await runGroupPendingKeyRepairsMigration(db);
      if (oldVersion < 64) {
        await runGroupWelcomeKeyPackageTombstonesMigration(db);
      }
      if (oldVersion < 65) await runGroupHistoryGapRepairsMigration(db);
      if (oldVersion < 66) await runGroupSyncReceiptsMigration(db);
      if (oldVersion < 67) await runGroupInviteDeliveryAttemptsMigration(db);
      if (oldVersion < 68) await runRemovedGroupMemberSnapshotsMigration(db);
      if (oldVersion < 69) await runGroupMessageLocalDeletionsMigration(db);
      if (oldVersion < 70) await runGroupKeyRotationDraftsMigration(db);
      if (oldVersion < 71) {
        await runPendingIntroductionResponseTransportSenderMigration(db);
      }
      if (oldVersion < 72) await runGroupPendingMembershipMessagesMigration(db);
      if (oldVersion < 73) await runGroupMessageLastSendAttemptAtMigration(db);
      if (oldVersion < 74) await runGroupMessageLogicalDeliveryIdMigration(db);
      if (oldVersion < 75) await runContactsMlKemKeyUpdatedTsMigration(db);
      if (oldVersion < 76) {
        await runPostMediaAttachmentCryptoColumnsMigration(db);
      }
      if (oldVersion < 77) await runMessageRelayCustodyMigration(db);
    },
  );
}

class GroupMultiDeviceTestStack {
  final sqlcipher.Database db;
  final String dbName;
  final GoBridgeClient bridge;
  final P2PServiceImpl p2pService;
  final IdentityRepositoryImpl identityRepo;
  final ContactRepositoryImpl contactRepo;
  final GroupRepositoryImpl groupRepo;
  final GroupMessageRepositoryImpl groupMsgRepo;
  final GroupInviteDeliveryAttemptRepositoryImpl groupInviteDeliveryAttemptRepo;
  final MediaAttachmentRepositoryImpl mediaAttachmentRepo;
  final ReactionRepositoryImpl reactionRepo;
  final GroupReactionReplayOutboxRepositoryImpl reactionReplayOutboxRepo;
  final IncomingMessageRouter messageRouter;
  final GroupKeyUpdateListener groupKeyUpdateListener;
  final GroupMembershipUpdateListener groupMembershipUpdateListener;
  final GroupMessageListener groupListener;
  final GroupInviteListener groupInviteListener;
  final InMemoryPendingGroupInviteRepository pendingInviteRepo;
  final StreamController<Map<String, dynamic>> groupStreamController;
  final StreamController<Map<String, dynamic>> groupReactionStreamController;
  final FakeNotificationService notificationService;
  final IdentityModel identity;
  final ContactModel? cliContact;

  const GroupMultiDeviceTestStack({
    required this.db,
    required this.dbName,
    required this.bridge,
    required this.p2pService,
    required this.identityRepo,
    required this.contactRepo,
    required this.groupRepo,
    required this.groupMsgRepo,
    required this.groupInviteDeliveryAttemptRepo,
    required this.mediaAttachmentRepo,
    required this.reactionRepo,
    required this.reactionReplayOutboxRepo,
    required this.messageRouter,
    required this.groupKeyUpdateListener,
    required this.groupMembershipUpdateListener,
    required this.groupListener,
    required this.groupInviteListener,
    required this.pendingInviteRepo,
    required this.groupStreamController,
    required this.groupReactionStreamController,
    required this.notificationService,
    required this.identity,
    required this.cliContact,
  });

  Future<void> teardown() async {
    groupKeyUpdateListener.dispose();
    groupMembershipUpdateListener.dispose();
    messageRouter.dispose();
    groupListener.dispose();
    groupInviteListener.dispose();
    await groupStreamController.close();
    await groupReactionStreamController.close();
    await p2pService.stopNode();
    p2pService.dispose();
    bridge.dispose();
    await db.close();
    await deleteTestDatabase(dbName);
  }
}

class RecordingGoBridgeClient extends GoBridgeClient {
  final List<String> sentMessages = <String>[];
  final List<Map<String, String>> bridgeExchanges = <Map<String, String>>[];

  @override
  Future<String> send(String message) async {
    sentMessages.add(message);
    final response = await super.send(message);
    bridgeExchanges.add(<String, String>{
      'request': message,
      'response': response,
    });
    return response;
  }
}

Future<GroupMultiDeviceTestStack> setupGroupMultiDeviceStack({
  required String dbName,
  required String username,
  required Map<String, dynamic>? cliPeerFixture,
  String? restoreMnemonic,
  IdentityModel? restoreIdentity,
  bool deleteExistingDb = true,
  bool reuseExistingIdentity = false,
  bool useFreshTransportIdentityForRestoredAccount = false,
  bool onJoinMetadataResyncEnabled = false,
}) async {
  if (deleteExistingDb) {
    await deleteTestSecureStore(dbName);
    await deleteTestDatabase(dbName);
  }
  final secureKeyStore = _FakeSecureKeyStore(dbName: dbName);
  final db = await _openTestDatabase(
    secureKeyStore: secureKeyStore,
    dbName: dbName,
  );

  final identityRepo = IdentityRepositoryImpl(
    dbLoadIdentityRow: () => dbLoadIdentityRow(db),
    dbUpsertIdentityRow: (row) => dbUpsertIdentityRow(db, row),
    secureKeyStore: secureKeyStore,
  );
  final contactRepo = ContactRepositoryImpl(
    dbLoadAllContacts: () => dbLoadAllContacts(db),
    dbLoadContact: (peerId) => dbLoadContact(db, peerId),
    dbUpsertContact: (row) => dbUpsertContact(db, row),
    dbDeleteContact: (peerId) => dbDeleteContact(db, peerId),
    dbGetContactCount: () => dbGetContactCount(db),
    dbContactExists: (peerId) => dbContactExists(db, peerId),
    dbArchiveContact: (peerId) => dbArchiveContact(db, peerId),
    dbUnarchiveContact: (peerId) => dbUnarchiveContact(db, peerId),
    dbLoadActiveContacts: () => dbLoadActiveContacts(db),
    dbLoadArchivedContacts: () => dbLoadArchivedContacts(db),
    dbBlockContact: (peerId) => dbBlockContact(db, peerId),
    dbUnblockContact: (peerId) => dbUnblockContact(db, peerId),
    dbDismissIntroBanner: (peerId) => dbDismissIntroBanner(db, peerId),
    dbSetIntrosSentAt: (peerId, timestamp) =>
        dbSetIntrosSentAt(db, peerId, timestamp),
  );
  final groupRepo = GroupRepositoryImpl(
    dbInsertGroup: (row) => dbInsertGroup(db, row),
    dbLoadAllGroups: () => dbLoadAllGroups(db),
    dbLoadGroup: (id) => dbLoadGroup(db, id),
    dbUpdateGroup: (row) => dbUpdateGroup(db, row),
    dbDeleteGroup: (id) => dbDeleteGroup(db, id),
    dbLoadActiveGroups: () => dbLoadActiveGroups(db),
    dbArchiveGroup: (id) => dbArchiveGroup(db, id),
    dbUnarchiveGroup: (id) => dbUnarchiveGroup(db, id),
    dbInsertGroupMember: (row) => dbInsertGroupMember(db, row),
    dbLoadAllGroupMembers: (groupId) => dbLoadAllGroupMembers(db, groupId),
    dbLoadGroupMember: (groupId, peerId) =>
        dbLoadGroupMember(db, groupId, peerId),
    dbUpdateGroupMemberRole: (groupId, peerId, role) =>
        dbUpdateGroupMemberRole(db, groupId, peerId, role),
    dbDeleteGroupMember: (groupId, peerId) =>
        dbDeleteGroupMember(db, groupId, peerId),
    dbDeleteAllGroupMembers: (groupId) => dbDeleteAllGroupMembers(db, groupId),
    dbInsertGroupKey: (row) => dbInsertGroupKey(db, row),
    dbLoadLatestGroupKey: (groupId) => dbLoadLatestGroupKey(db, groupId),
    dbLoadGroupKeyByGeneration: (groupId, generation) =>
        dbLoadGroupKeyByGeneration(db, groupId, generation),
    dbDeleteAllGroupKeys: (groupId) => dbDeleteAllGroupKeys(db, groupId),
  );
  GroupMessageRepositoryImpl createGroupMessageRepository(
    dynamic executor, {
    bool enableInboxPageTransactions = false,
  }) {
    return GroupMessageRepositoryImpl(
      dbInsertGroupMessage: (row) => dbInsertGroupMessage(executor, row),
      dbLoadGroupMessagesPage: (groupId, {limit = 50, offset = 0}) =>
          dbLoadGroupMessagesPage(
            executor,
            groupId,
            limit: limit,
            offset: offset,
          ),
      dbLoadGroupMessage: (id) => dbLoadGroupMessage(executor, id),
      dbLoadLatestGroupMessage: (groupId) =>
          dbLoadLatestGroupMessage(executor, groupId),
      dbLoadLatestRemovalTimestampForSenderFn: (groupId, senderPeerId) =>
          dbLoadLatestGroupRemovalTimestampForSender(
            executor,
            groupId,
            senderPeerId,
          ),
      dbUpdateGroupMessageStatus: (id, status) =>
          dbUpdateGroupMessageStatus(executor, id, status),
      dbCountGroupMessages: (groupId) =>
          dbCountGroupMessages(executor, groupId),
      dbCountUnreadGroupMessages: (groupId) =>
          dbCountUnreadGroupMessages(executor, groupId),
      dbCountTotalUnreadGroupMessages: () =>
          dbCountTotalUnreadGroupMessages(executor),
      dbMarkGroupMessagesAsRead: (groupId) =>
          dbMarkGroupMessagesAsRead(executor, groupId),
      dbDeleteGroupMessage: (id) => dbDeleteGroupMessage(executor, id),
      dbExistsGroupMessageByContent: (groupId, senderPeerId, text, timestamp) =>
          dbExistsGroupMessageByContent(
            executor,
            groupId,
            senderPeerId,
            text,
            timestamp,
          ),
      dbDeleteGroupMessagesForGroup: (groupId) =>
          dbDeleteGroupMessagesForGroup(executor, groupId),
      dbLoadGroupThreadSummaries: (groupIds) =>
          dbLoadGroupThreadSummaries(executor, groupIds),
      dbLoadFailedOutgoingGroupMessagesFn: () =>
          dbLoadFailedOutgoingGroupMessages(executor),
      dbRecoverStuckSendingGroupMessagesFn: ({olderThan}) =>
          dbTransitionGroupSendingToFailed(executor, olderThan: olderThan),
      dbLoadGroupMessagesWithFailedInboxStore: ({limit = 20}) =>
          dbLoadGroupMessagesWithFailedInboxStore(executor, limit: limit),
      dbUpdateGroupMessageInboxStoredFn: (id, {required stored}) =>
          dbUpdateGroupMessageInboxStored(executor, id, stored: stored),
      dbUpdateGroupMessageInboxRetryPayloadFn: (id, payload) =>
          dbUpdateGroupMessageInboxRetryPayload(executor, id, payload),
      dbUpdateGroupMessageWireEnvelopeFn: (id, envelope) =>
          dbUpdateGroupMessageWireEnvelope(executor, id, envelope),
      dbLoadGroupInboxCursorFn: (groupId) async {
        final row = await dbLoadGroupInboxCursor(executor, groupId);
        return row?['cursor'] as String?;
      },
      dbLoadGroupMessageReceiptsFn:
          (groupId, messageId, {String? receiptType}) =>
              dbLoadGroupMessageReceipts(
                executor,
                groupId: groupId,
                messageId: messageId,
                receiptType: receiptType,
              ),
      dbRunGroupInboxPageTransactionFn: enableInboxPageTransactions
          ? ({
              required groupId,
              required nextCursor,
              required apply,
              required receipts,
              required markReadMessageIds,
            }) {
              return dbApplyGroupInboxPageTransaction(
                db,
                groupId: groupId,
                nextCursor: nextCursor,
                receiptRows: () =>
                    receipts.map((receipt) => receipt.toMap()).toList(),
                markReadMessageIds: () => markReadMessageIds,
                apply: (transactionExecutor) {
                  final transactionRepo = createGroupMessageRepository(
                    transactionExecutor,
                  );
                  return apply(transactionRepo);
                },
              );
            }
          : null,
    );
  }

  final groupMsgRepo = createGroupMessageRepository(
    db,
    enableInboxPageTransactions: true,
  );
  final groupInviteDeliveryAttemptRepo =
      GroupInviteDeliveryAttemptRepositoryImpl(
        dbUpsertGroupInviteDeliveryAttempt: (row) =>
            dbUpsertGroupInviteDeliveryAttempt(db, row),
        dbLoadGroupInviteDeliveryAttempt:
            ({required groupId, required peerId}) =>
                dbLoadGroupInviteDeliveryAttempt(
                  db,
                  groupId: groupId,
                  peerId: peerId,
                ),
        dbLoadGroupInviteDeliveryAttemptsForGroup: (groupId) =>
            dbLoadGroupInviteDeliveryAttemptsForGroup(db, groupId),
        dbUpdateGroupInviteDeliveryAttemptStatus:
            ({
              required groupId,
              required peerId,
              required status,
              required updatedAt,
            }) => dbUpdateGroupInviteDeliveryAttemptStatus(
              db,
              groupId: groupId,
              peerId: peerId,
              status: status,
              updatedAt: updatedAt,
            ),
        dbDeleteGroupInviteDeliveryAttempt:
            ({required groupId, required peerId}) =>
                dbDeleteGroupInviteDeliveryAttempt(
                  db,
                  groupId: groupId,
                  peerId: peerId,
                ),
        dbDeleteGroupInviteDeliveryAttemptsForGroup: (groupId) =>
            dbDeleteGroupInviteDeliveryAttemptsForGroup(db, groupId),
      );
  final groupPendingKeyRepairRepo = GroupPendingKeyRepairRepositoryImpl(
    dbUpsertGroupPendingKeyRepair: (row) =>
        dbUpsertGroupPendingKeyRepair(db, row),
    dbLoadGroupPendingKeyRepair: (id) => dbLoadGroupPendingKeyRepair(db, id),
    dbLoadPendingGroupKeyRepairsForEpoch:
        ({required groupId, required keyEpoch, int limit = 50}) =>
            dbLoadPendingGroupKeyRepairsForEpoch(
              db,
              groupId: groupId,
              keyEpoch: keyEpoch,
              limit: limit,
            ),
    dbRecordGroupPendingKeyRepairAttempt:
        (id, {required lastError, required updatedAt}) =>
            dbRecordGroupPendingKeyRepairAttempt(
              db,
              id,
              lastError: lastError,
              updatedAt: updatedAt,
            ),
    dbFinalizeGroupPendingKeyRepair:
        (id, {required status, required lastError, required finalizedAt}) =>
            dbFinalizeGroupPendingKeyRepair(
              db,
              id,
              status: status,
              lastError: lastError,
              finalizedAt: finalizedAt,
            ),
    dbLoadAllPendingGroupKeyRepairs: ({int limit = 200}) =>
        dbLoadAllPendingGroupKeyRepairs(db, limit: limit),
    dbLoadPendingGroupKeyRepairsForGroup:
        ({required groupId, int limit = 100}) =>
            dbLoadPendingGroupKeyRepairsForGroup(
              db,
              groupId: groupId,
              limit: limit,
            ),
    dbDeleteGroupPendingKeyRepair: (id) =>
        dbDeleteGroupPendingKeyRepair(db, id),
  );
  final mediaAttachmentRepo = MediaAttachmentRepositoryImpl(
    dbInsertMediaAttachment: (row) => dbInsertMediaAttachment(db, row),
    dbLoadMediaForMessage: (messageId) => dbLoadMediaForMessage(db, messageId),
    dbLoadMediaById: (id) => dbLoadMediaById(db, id),
    dbLoadMediaForMessages: (messageIds) =>
        dbLoadMediaForMessages(db, messageIds),
    dbUpdateMediaLocalPath: (id, localPath, downloadStatus) =>
        dbUpdateMediaLocalPath(db, id, localPath, downloadStatus),
    dbUpdateMediaDownloadStatus: (id, downloadStatus) =>
        dbUpdateMediaDownloadStatus(db, id, downloadStatus),
    dbDeleteMediaForMessage: (messageId) =>
        dbDeleteMediaForMessage(db, messageId),
    dbDeleteMediaForContact: (contactPeerId) =>
        dbDeleteMediaForContact(db, contactPeerId),
    dbMarkUploadPendingAttachmentsFailedForMessage: (messageId) =>
        dbMarkUploadPendingAttachmentsFailedForMessage(db, messageId),
    dbLoadPendingMediaDownloads: () => dbLoadPendingMediaDownloads(db),
    dbLoadUploadPendingAttachments: ({int limit = 50}) =>
        dbLoadUploadPendingAttachments(db, limit: limit),
    secureKeyStore: secureKeyStore,
  );
  final reactionRepo = ReactionRepositoryImpl(
    dbInsertReaction: (row) => dbInsertReaction(db, row),
    dbLoadReactionsForMessage: (messageId) =>
        dbLoadReactionsForMessage(db, messageId),
    dbLoadReactionsForMessages: (messageIds) =>
        dbLoadReactionsForMessages(db, messageIds),
    dbLoadActiveOrTombstonedReactionForSender: (messageId, senderPeerId) =>
        dbLoadActiveOrTombstonedReactionForSender(db, messageId, senderPeerId),
    dbDeleteReaction: (messageId, senderPeerId, {removedAtTimestamp}) =>
        dbDeleteReaction(db, messageId, senderPeerId,
            removedAtTimestamp: removedAtTimestamp),
    dbDeleteReactionsForMessage: (messageId) =>
        dbDeleteReactionsForMessage(db, messageId),
    dbDeleteReactionsForContact: (contactPeerId) =>
        dbDeleteReactionsForContact(db, contactPeerId),
  );
  final reactionReplayOutboxRepo = GroupReactionReplayOutboxRepositoryImpl(
    dbUpsertGroupReactionReplayOutboxEntry: (row) =>
        dbUpsertGroupReactionReplayOutboxEntry(db, row),
    dbLoadGroupReactionReplayOutboxEntry: (reactionId) =>
        dbLoadGroupReactionReplayOutboxEntry(db, reactionId),
    dbLoadRetryableGroupReactionReplayOutboxEntries: ({int limit = 20}) =>
        dbLoadRetryableGroupReactionReplayOutboxEntries(db, limit: limit),
    dbUpdateGroupReactionReplayOutboxEntryStatus:
        (
          reactionId, {
          required deliveryStatus,
          lastError,
          required updatedAt,
        }) => dbUpdateGroupReactionReplayOutboxEntryStatus(
          db,
          reactionId,
          deliveryStatus: deliveryStatus,
          lastError: lastError,
          updatedAt: updatedAt,
        ),
    dbDeleteGroupReactionReplayOutboxEntry: (reactionId) =>
        dbDeleteGroupReactionReplayOutboxEntry(db, reactionId),
  );

  final bridge = RecordingGoBridgeClient();
  await bridge.initialize();

  var savedIdentity = restoreIdentity;
  if (savedIdentity == null && reuseExistingIdentity) {
    savedIdentity = await identityRepo.loadIdentity();
  }
  if (reuseExistingIdentity &&
      savedIdentity == null &&
      restoreMnemonic == null) {
    throw StateError('Existing identity requested but none was found');
  }
  if (savedIdentity == null) {
    final identityResult = restoreMnemonic == null
        ? await generateNewIdentity(
            callGenerate: () => callIdentityGenerate(bridge),
            callMlKemKeygen: () => callMlKemKeygen(bridge),
            repo: identityRepo,
          )
        : await restoreIdentityFromMnemonic(
            input: restoreMnemonic,
            callRestore: (mnemonic) => callIdentityRestore(bridge, mnemonic),
            callMlKemKeygen: () => callMlKemKeygen(bridge),
            repo: identityRepo,
          );
    if (identityResult.toString().endsWith('success') != true) {
      throw StateError('Identity setup failed: $identityResult');
    }
    savedIdentity = await identityRepo.loadIdentity();
  }

  if (savedIdentity == null) {
    throw StateError('Identity missing after setup');
  }

  final updatedIdentity = IdentityModel(
    peerId: savedIdentity.peerId,
    publicKey: savedIdentity.publicKey,
    privateKey: savedIdentity.privateKey,
    mnemonic12: savedIdentity.mnemonic12,
    mlKemPublicKey: savedIdentity.mlKemPublicKey,
    mlKemSecretKey: savedIdentity.mlKemSecretKey,
    username: username,
    avatarBlob: savedIdentity.avatarBlob,
    avatarVersion: savedIdentity.avatarVersion,
    createdAt: savedIdentity.createdAt,
    updatedAt: DateTime.now().toUtc().toIso8601String(),
  );
  await identityRepo.saveIdentity(updatedIdentity);

  var transportPrivateKey = updatedIdentity.privateKey;
  var transportPeerId = updatedIdentity.peerId;
  if (restoreMnemonic != null && useFreshTransportIdentityForRestoredAccount) {
    final transportResponse = await callIdentityGenerate(bridge);
    if (transportResponse['ok'] != true) {
      throw StateError(
        'Transport identity setup failed: ${transportResponse['errorMessage']}',
      );
    }
    final transportIdentity =
        transportResponse['identity'] as Map<String, dynamic>?;
    if (transportIdentity == null) {
      throw StateError('Transport identity setup returned no identity');
    }
    transportPrivateKey = transportIdentity['privateKey'] as String;
    transportPeerId = transportIdentity['peerId'] as String;
    if (transportPeerId == updatedIdentity.peerId) {
      throw StateError('Transport identity must differ from logical identity');
    }
  }

  ContactModel? cliContact;
  if (cliPeerFixture != null) {
    cliContact = ContactModel(
      peerId: cliPeerFixture['peerId'] as String,
      publicKey: cliPeerFixture['publicKey'] as String,
      rendezvous: '/dns4/relay/tcp/443/p2p/relay',
      username: cliPeerFixture['username'] as String? ?? 'CLIGroupPeer',
      signature: 'sig-cli-group-peer',
      scannedAt: DateTime.now().toUtc().toIso8601String(),
      mlKemPublicKey: cliPeerFixture['mlKemPublicKey'] as String?,
    );
    await contactRepo.addContact(cliContact);
  }

  final p2pService = P2PServiceImpl(
    bridge: bridge,
    inboxStagingRepository: InMemoryInboxStagingRepository(),
  );
  final started = await p2pService.startNode(
    transportPrivateKey,
    transportPeerId,
  );
  if (!started) {
    throw StateError('P2P node failed to start');
  }

  final notificationService = FakeNotificationService();
  await notificationService.initialize();
  final messageRouter = IncomingMessageRouter(p2pService: p2pService);
  final groupKeyUpdateListener = GroupKeyUpdateListener(
    groupKeyUpdateStream: messageRouter.groupKeyUpdateStream,
    groupRepo: groupRepo,
    bridge: bridge,
    getOwnMlKemSecretKey: () async => updatedIdentity.mlKemSecretKey,
    getOwnPeerId: () async => updatedIdentity.peerId,
    getOwnDeviceId: () async => p2pService.currentState.peerId,
  );
  final groupStreamController =
      StreamController<Map<String, dynamic>>.broadcast();
  bridge.onGroupMessageReceived = (data) {
    groupStreamController.add(Map<String, dynamic>.from(data));
  };
  final groupReactionStreamController =
      StreamController<Map<String, dynamic>>.broadcast();
  bridge.onGroupReactionReceived = (data) {
    groupReactionStreamController.add(Map<String, dynamic>.from(data));
  };

  final groupListener = GroupMessageListener(
    groupRepo: groupRepo,
    msgRepo: groupMsgRepo,
    bridge: bridge,
    getSelfPeerId: () async => updatedIdentity.peerId,
    mediaAttachmentRepo: mediaAttachmentRepo,
    notificationService: notificationService,
    groupConversationTracker: ActiveConversationTracker(),
    getAppLifecycleState: () => AppLifecycleState.paused,
    reactionRepo: reactionRepo,
    groupDiagnosticEvents: groupDiagnosticEventStream,
    pendingKeyRepairRepo: groupPendingKeyRepairRepo,
    inviteDeliveryAttemptRepo: groupInviteDeliveryAttemptRepo,
    // Mirror main.dart: the remaining group creator re-keys when a member it did
    // not author departs (forward secrecy for best-effort voluntary leave).
    rotateGroupKeyAfterRemoteRemoval: (groupId) async {
      final identity = await identityRepo.loadIdentity();
      if (identity == null) return false;
      final rotated = await rotateAndDistributeGroupKey(
        bridge: bridge,
        groupRepo: groupRepo,
        groupId: groupId,
        selfPeerId: identity.peerId,
        senderPublicKey: identity.publicKey,
        senderPrivateKey: identity.privateKey,
        senderUsername: identity.username,
        sendP2PMessage: (peerId, message) async =>
            p2pService.sendMessage(peerId, message),
        storeP2PMessageInInbox: (peerId, message) async =>
            p2pService.storeInInbox(peerId, message),
      );
      return rotated.rotated;
    },
  );
  final groupMembershipUpdateListener = GroupMembershipUpdateListener(
    groupMembershipUpdateStream: messageRouter.groupMembershipUpdateStream,
    groupRepo: groupRepo,
    bridge: bridge,
    groupMessageListener: groupListener,
    msgRepo: groupMsgRepo,
    pendingKeyRepairRepo: groupPendingKeyRepairRepo,
  );
  final pendingInviteRepo = InMemoryPendingGroupInviteRepository();
  final groupInviteListener = GroupInviteListener(
    groupInviteStream: messageRouter.groupInviteStream,
    groupRepo: groupRepo,
    pendingInviteRepo: pendingInviteRepo,
    contactRepo: contactRepo,
    bridge: bridge,
    deliveryRepo: groupInviteDeliveryAttemptRepo,
    p2pService: p2pService,
    loadOwnIdentity: () => identityRepo.loadIdentity(),
    onJoinMetadataResyncEnabled: onJoinMetadataResyncEnabled,
    getOwnMlKemSecretKey: () async => updatedIdentity.mlKemSecretKey,
    getOwnPeerId: () async => updatedIdentity.peerId,
    getOwnMlKemPublicKey: () async => updatedIdentity.mlKemPublicKey,
  );

  messageRouter.start();
  groupKeyUpdateListener.start();
  groupListener.start(
    groupStreamController.stream,
    incomingGroupReactions: groupReactionStreamController.stream,
  );
  groupMembershipUpdateListener.start();
  groupInviteListener.start();
  if (reuseExistingIdentity) {
    await rejoinGroupTopics(bridge: bridge, groupRepo: groupRepo);
  }

  return GroupMultiDeviceTestStack(
    db: db,
    dbName: dbName,
    bridge: bridge,
    p2pService: p2pService,
    identityRepo: identityRepo,
    contactRepo: contactRepo,
    groupRepo: groupRepo,
    groupMsgRepo: groupMsgRepo,
    groupInviteDeliveryAttemptRepo: groupInviteDeliveryAttemptRepo,
    mediaAttachmentRepo: mediaAttachmentRepo,
    reactionRepo: reactionRepo,
    reactionReplayOutboxRepo: reactionReplayOutboxRepo,
    messageRouter: messageRouter,
    groupKeyUpdateListener: groupKeyUpdateListener,
    groupMembershipUpdateListener: groupMembershipUpdateListener,
    groupListener: groupListener,
    groupInviteListener: groupInviteListener,
    pendingInviteRepo: pendingInviteRepo,
    groupStreamController: groupStreamController,
    groupReactionStreamController: groupReactionStreamController,
    notificationService: notificationService,
    identity: updatedIdentity,
    cliContact: cliContact,
  );
}

Map<String, dynamic> buildGroupFixture({
  required GroupModel group,
  required GroupKeyInfo keyInfo,
  required List<GroupMember> members,
}) {
  return {
    'group': group.toMap(),
    'key': keyInfo.toMap(),
    'members': members.map((member) => member.toMap()).toList(growable: false),
    'groupConfig': buildGroupConfigPayload(group, members),
  };
}

Future<String> importJoinedGroupFixture({
  required GroupMultiDeviceTestStack stack,
  required Map<String, dynamic> fixture,
}) async {
  final group = GroupModel.fromMap(
    Map<String, dynamic>.from(fixture['group'] as Map),
  );
  final key = GroupKeyInfo.fromMap(
    Map<String, dynamic>.from(fixture['key'] as Map),
  );
  final members = (fixture['members'] as List<dynamic>)
      .map((raw) => GroupMember.fromMap(Map<String, dynamic>.from(raw as Map)))
      .toList(growable: false);
  final groupConfig = Map<String, dynamic>.from(fixture['groupConfig'] as Map);

  // The fixture's group row carries the CREATOR's myRole (admin). Correct it to
  // the importing peer's actual role from the members list so role-gated actions
  // (voluntary leave, etc.) behave correctly for a joiner instead of treating it
  // as the sole admin.
  MemberRole? selfMemberRole;
  for (final member in members) {
    if (member.peerId == stack.identity.peerId) {
      selfMemberRole = member.role;
      break;
    }
  }
  final importedGroup = selfMemberRole == null
      ? group
      : group.copyWith(
          myRole: selfMemberRole == MemberRole.admin
              ? GroupRole.admin
              : GroupRole.member,
        );
  await stack.groupRepo.saveGroup(importedGroup);
  for (final member in members) {
    await stack.groupRepo.saveMember(member);
  }
  await stack.groupRepo.saveKey(key);

  await callGroupJoinWithConfig(
    stack.bridge,
    groupId: group.id,
    groupConfig: groupConfig,
    groupKey: key.encryptedKey,
    keyEpoch: key.keyGeneration,
  );

  return group.id;
}

Map<String, dynamic> buildMemberRoleUpdatedSystemPayload({
  required String groupId,
  required String updatedPeerId,
  required String? updatedUsername,
  required String updatedRole,
  required String? publicKey,
  required String? mlKemPublicKey,
  required Map<String, dynamic> groupConfig,
}) {
  return {
    '__sys': 'member_role_updated',
    'member': {
      'peerId': updatedPeerId,
      'username': updatedUsername,
      'role': updatedRole,
      'publicKey': publicKey,
      'mlKemPublicKey': mlKemPublicKey,
    },
    'groupConfig': groupConfig,
  };
}

bool get _isPrimaryRole => configuredRole == 'primary';
bool get _isSiblingRole => configuredRole == 'sibling';

String _signalName(String name) => 'md004_${configuredRunId}_$name';

String _dbNameForRole() {
  if (configuredDbName.isNotEmpty) return configuredDbName;
  return 'group_multi_device_real_${configuredRunId}_$configuredRole.db';
}

Map<String, dynamic> _primaryIdentityFixture(IdentityModel identity) {
  final mnemonic = identity.mnemonic12;
  if (mnemonic.trim().isEmpty) {
    throw StateError(
      'Primary identity mnemonic is required for sibling restore',
    );
  }
  return {
    'peerId': identity.peerId,
    'publicKey': identity.publicKey,
    'mlKemPublicKey': identity.mlKemPublicKey,
    'mnemonic12': mnemonic,
    'username': identity.username,
  };
}

Map<String, dynamic> _buildCliJoinFixture({
  required GroupModel group,
  required GroupKeyInfo keyInfo,
  required List<GroupMember> members,
}) {
  return {
    'groupId': group.id,
    'groupKey': keyInfo.encryptedKey,
    'keyEpoch': keyInfo.keyGeneration,
    'groupConfig': buildGroupConfigPayload(group, members),
  };
}

Future<ContactModel> _generateOfflineContact({
  required GoBridgeClient bridge,
  required String username,
}) async {
  final identityResult = await callIdentityGenerate(bridge);
  if (identityResult['ok'] != true) {
    throw StateError('identity.generate failed for $username: $identityResult');
  }
  final identity = Map<String, dynamic>.from(identityResult['identity'] as Map);

  final mlKemResult = await callMlKemKeygen(bridge);
  if (mlKemResult['ok'] != true) {
    throw StateError('mlkem_keygen failed for $username: $mlKemResult');
  }

  return ContactModel(
    peerId: identity['peerId'] as String,
    publicKey: identity['publicKey'] as String,
    rendezvous: '/dns4/relay/tcp/443/p2p/relay',
    username: username,
    signature: 'sig-$username',
    scannedAt: DateTime.now().toUtc().toIso8601String(),
    mlKemPublicKey: mlKemResult['publicKey'] as String?,
  );
}

Future<void> _runPrimaryScenario() async {
  final cliPeerFixture = loadCliPeerFixture();
  expect(
    cliPeerFixture,
    isNotNull,
    reason: 'MD-004 primary run requires a CLI peer fixture',
  );

  final stack = await setupGroupMultiDeviceStack(
    dbName: _dbNameForRole(),
    username: 'MD004 Primary',
    cliPeerFixture: cliPeerFixture,
  );

  try {
    writeSharedJson(
      _signalName('primary_identity.json'),
      _primaryIdentityFixture(stack.identity),
    );

    final groupResult = await createGroupWithMembers(
      bridge: stack.bridge,
      groupRepo: stack.groupRepo,
      p2pService: stack.p2pService,
      identity: stack.identity,
      selectedContacts: [stack.cliContact!],
      type: GroupType.chat,
      name: 'MD-004 Shared Devices',
      inviteDeliveryAttemptRepo: stack.groupInviteDeliveryAttemptRepo,
    );
    expect(
      groupResult.membersAdded,
      1,
      reason: 'Primary must add the CLI peer to the proof group',
    );

    final group = await stack.groupRepo.getGroup(groupResult.group.id);
    final keyInfo = await stack.groupRepo.getLatestKey(groupResult.group.id);
    final members = await stack.groupRepo.getMembers(groupResult.group.id);
    expect(group, isNotNull);
    expect(keyInfo, isNotNull);

    writeSharedJson(
      _signalName('group_fixture.json'),
      buildGroupFixture(group: group!, keyInfo: keyInfo!, members: members),
    );
    writeSharedJson(
      _signalName('cli_group_join_fixture.json'),
      _buildCliJoinFixture(group: group, keyInfo: keyInfo, members: members),
    );

    // Fresh multi-simulator iOS test boots can spend several extra minutes in
    // Xcode build/install before the sibling harness can signal readiness.
    await waitForSharedSignal(
      _signalName('sibling_ready'),
      timeout: const Duration(minutes: 12),
    );

    final sendResult = await sendGroupMessage(
      bridge: stack.bridge,
      groupRepo: stack.groupRepo,
      msgRepo: stack.groupMsgRepo,
      groupId: group.id,
      text: 'MD-004 same-user send',
      senderPeerId: stack.identity.peerId,
      senderPublicKey: stack.identity.publicKey,
      senderPrivateKey: stack.identity.privateKey,
      senderUsername: stack.identity.username,
      inviteDeliveryAttemptRepo: stack.groupInviteDeliveryAttemptRepo,
      includeSenderPeerIdInDurableRecipients: true,
    );
    expect(
      sendResult.$1,
      anyOf(
        SendGroupMessageResult.success,
        SendGroupMessageResult.successNoPeers,
      ),
    );
    expect(sendResult.$2, isNotNull);
    await waitForSharedSignal(_signalName('sibling_send_verified'));

    final charlie = await _generateOfflineContact(
      bridge: stack.bridge,
      username: 'Charlie',
    );
    await stack.contactRepo.addContact(charlie);

    final charlieMember = GroupMember(
      groupId: group.id,
      peerId: charlie.peerId,
      username: charlie.username,
      role: MemberRole.writer,
      publicKey: charlie.publicKey,
      mlKemPublicKey: charlie.mlKemPublicKey,
      joinedAt: DateTime.now().toUtc(),
    );
    await addGroupMember(
      bridge: stack.bridge,
      groupRepo: stack.groupRepo,
      groupId: group.id,
      newMember: charlieMember,
      selfPeerId: stack.identity.peerId,
    );

    final updatedMembers = await stack.groupRepo.getMembers(group.id);
    final updatedGroup = await stack.groupRepo.getGroup(group.id);
    expect(updatedGroup, isNotNull);
    final membershipEventAt = DateTime.now().toUtc();
    final membershipMessageId =
        'members_added:${group.id}:${stack.identity.peerId}:${membershipEventAt.microsecondsSinceEpoch}';
    final membershipReplayRecipients = updatedMembers
        .map((member) => member.peerId)
        .where((peerId) => peerId.isNotEmpty)
        .toSet()
        .toList(growable: false);
    final membersAddedSystemPayload = jsonEncode({
      '__sys': 'members_added',
      'members': [
        {
          'peerId': charlieMember.peerId,
          'username': charlieMember.username,
          'role': charlieMember.role.toValue(),
          'publicKey': charlieMember.publicKey,
          if (charlieMember.mlKemPublicKey != null)
            'mlKemPublicKey': charlieMember.mlKemPublicKey,
        },
      ],
      'groupConfig': buildGroupConfigPayload(updatedGroup!, updatedMembers),
    });
    final membershipPublish = await callGroupPublish(
      stack.bridge,
      groupId: group.id,
      text: membersAddedSystemPayload,
      senderPeerId: stack.identity.peerId,
      senderPublicKey: stack.identity.publicKey,
      senderPrivateKey: stack.identity.privateKey,
      senderUsername: stack.identity.username,
      messageId: membershipMessageId,
    );
    expect(
      membershipPublish['ok'],
      isTrue,
      reason: 'Primary must publish the members_added system payload',
    );
    await storeGroupOfflineReplayEnvelope(
      bridge: stack.bridge,
      groupRepo: stack.groupRepo,
      groupId: group.id,
      payloadType: groupOfflineReplayPayloadTypeMessage,
      plaintext: jsonEncode({
        'groupId': group.id,
        'senderId': stack.identity.peerId,
        'senderUsername': stack.identity.username,
        'text': membersAddedSystemPayload,
        'timestamp': membershipEventAt.toIso8601String(),
        'messageId': membershipMessageId,
      }),
      senderPeerId: stack.identity.peerId,
      senderPublicKey: stack.identity.publicKey,
      senderPrivateKey: stack.identity.privateKey,
      messageId: membershipMessageId,
      recipientPeerIds: membershipReplayRecipients,
    );
    await waitForSharedSignal(_signalName('sibling_membership_verified'));

    await setGroupMuted(
      groupRepo: stack.groupRepo,
      groupId: group.id,
      isMuted: true,
    );
    expect((await stack.groupRepo.getGroup(group.id))!.isMuted, isTrue);

    writeSharedText(_signalName('cli_publish_ready'), 'ok');
    await waitForSharedSignal(_signalName('cli_message_published'));

    await waitForCondition(
      () async => await stack.groupMsgRepo.getUnreadCount(group.id) == 1,
      timeout: const Duration(seconds: 90),
    );
    expect(
      stack.notificationService.shown,
      isEmpty,
      reason: 'Muted primary should not surface a local notification',
    );

    await stack.groupMsgRepo.markAsRead(group.id);
    expect(await stack.groupMsgRepo.getUnreadCount(group.id), 0);
    writeSharedText(_signalName('primary_marked_read'), 'ok');

    await waitForSharedSignal(_signalName('sibling_complete'));
  } finally {
    await stack.teardown();
  }
}

Future<void> _runSiblingScenario() async {
  final cliPeerFixture = loadCliPeerFixture();
  expect(
    cliPeerFixture,
    isNotNull,
    reason: 'MD-004 sibling run requires a CLI peer fixture',
  );

  final identityFixture = await waitForSharedJson(
    _signalName('primary_identity.json'),
  );
  final mnemonic = identityFixture['mnemonic12'] as String?;
  expect(
    mnemonic,
    isNotNull,
    reason: 'Primary must publish a mnemonic for sibling restore',
  );

  final stack = await setupGroupMultiDeviceStack(
    dbName: _dbNameForRole(),
    username: 'MD004 Sibling',
    cliPeerFixture: cliPeerFixture,
    restoreMnemonic: mnemonic,
  );

  try {
    expect(
      stack.identity.peerId,
      identityFixture['peerId'],
      reason: 'Sibling must restore the exact same user identity',
    );

    final fixture = await waitForSharedJson(_signalName('group_fixture.json'));
    final groupId = await importJoinedGroupFixture(
      stack: stack,
      fixture: fixture,
    );
    writeSharedText(_signalName('sibling_ready'), 'ok');

    await waitForCondition(() async {
      await drainGroupOfflineInboxForGroup(
        bridge: stack.bridge,
        groupRepo: stack.groupRepo,
        msgRepo: stack.groupMsgRepo,
        groupId: groupId,
        groupMessageListener: stack.groupListener,
      );
      return await stack.groupMsgRepo.getMessageCount(groupId) >= 1;
    }, timeout: const Duration(seconds: 90));
    final sentMirror = await stack.groupMsgRepo.getLatestMessage(groupId);
    expect(sentMirror, isNotNull);
    expect(sentMirror!.text, 'MD-004 same-user send');
    expect(sentMirror.senderPeerId, stack.identity.peerId);
    expect(sentMirror.isIncoming, isFalse);
    expect(sentMirror.status, 'sent');
    expect(await stack.groupMsgRepo.getUnreadCount(groupId), 0);
    expect(
      stack.notificationService.shown,
      isEmpty,
      reason: 'Sibling should not notify for same-user mirrored sends',
    );
    writeSharedText(_signalName('sibling_send_verified'), 'ok');

    await waitForCondition(() async {
      await drainGroupOfflineInboxForGroup(
        bridge: stack.bridge,
        groupRepo: stack.groupRepo,
        msgRepo: stack.groupMsgRepo,
        groupId: groupId,
        groupMessageListener: stack.groupListener,
      );
      final members = await stack.groupRepo.getMembers(groupId);
      return members.any((member) => member.username == 'Charlie');
    }, timeout: const Duration(seconds: 90));
    final convergedMembers = await stack.groupRepo.getMembers(groupId);
    expect(
      convergedMembers.where(
        (member) => member.peerId == stack.identity.peerId,
      ),
      hasLength(1),
      reason: 'Sibling must not duplicate self-membership rows',
    );
    writeSharedText(_signalName('sibling_membership_verified'), 'ok');

    final siblingGroup = await stack.groupRepo.getGroup(groupId);
    expect(siblingGroup, isNotNull);
    expect(
      siblingGroup!.isMuted,
      isFalse,
      reason: 'Mute state must remain device-local on the sibling',
    );
    final unreadBeforeCli = await stack.groupMsgRepo.getUnreadCount(groupId);
    expect(
      unreadBeforeCli,
      1,
      reason: 'Membership replay should remain unread on the sibling',
    );

    await waitForSharedSignal(_signalName('cli_message_published'));
    await waitForCondition(() async {
      await drainGroupOfflineInboxForGroup(
        bridge: stack.bridge,
        groupRepo: stack.groupRepo,
        msgRepo: stack.groupMsgRepo,
        groupId: groupId,
        groupMessageListener: stack.groupListener,
      );
      final latestMessage = await stack.groupMsgRepo.getLatestMessage(groupId);
      final unreadCount = await stack.groupMsgRepo.getUnreadCount(groupId);
      return latestMessage?.text == 'MD-004 CLI incoming' &&
          latestMessage?.senderPeerId == stack.cliContact?.peerId &&
          unreadCount == unreadBeforeCli + 1;
    }, timeout: const Duration(seconds: 90));
    await waitForCondition(
      () async => stack.notificationService.shown.length == 1,
      timeout: const Duration(seconds: 90),
    );
    expect(
      stack.notificationService.shown.single.contactPeerId,
      'group:$groupId',
    );

    await waitForSharedSignal(_signalName('primary_marked_read'));
    expect(
      await stack.groupMsgRepo.getUnreadCount(groupId),
      unreadBeforeCli + 1,
      reason: 'Sibling unread state must remain device-local after phone read',
    );
    writeSharedText(_signalName('sibling_complete'), 'ok');
  } finally {
    await stack.teardown();
  }
}

// ── Review-08 invite-reliability two-DIFFERENT-user relay scenario ──
// primary = Alice (admin/inviter), sibling = Bob (invitee). Every new envelope
// (invite, decline-ack, revocation, config request/response) traverses the REAL
// relay via storeInInbox + the recipient's drainOfflineInbox → router →
// GroupInviteListener, then is verified/applied with real Go ML-KEM + ed25519.

Map<String, dynamic> _peerIdentityFixture(IdentityModel identity) => {
  'peerId': identity.peerId,
  'publicKey': identity.publicKey,
  'mlKemPublicKey': identity.mlKemPublicKey,
  'username': identity.username,
};

ContactModel _contactFromFixture(
  Map<String, dynamic> fixture,
  String fallbackUsername,
) {
  return ContactModel(
    peerId: fixture['peerId'] as String,
    publicKey: fixture['publicKey'] as String,
    rendezvous: '/dns4/relay/tcp/443/p2p/relay',
    username: (fixture['username'] as String?) ?? fallbackUsername,
    signature: 'sig-${fixture['peerId']}',
    scannedAt: DateTime.now().toUtc().toIso8601String(),
    mlKemPublicKey: fixture['mlKemPublicKey'] as String?,
  );
}

Future<void> _runInviteReliabilityPrimary() async {
  final stack = await setupGroupMultiDeviceStack(
    dbName: _dbNameForRole(),
    username: 'Alice',
    cliPeerFixture: null,
    onJoinMetadataResyncEnabled: true,
  );
  try {
    writeSharedJson(
      _signalName('alice_identity.json'),
      _peerIdentityFixture(stack.identity),
    );

    final bobFixture = await waitForSharedJson(_signalName('bob_identity.json'));
    final bobContact = _contactFromFixture(bobFixture, 'Bob');
    await stack.contactRepo.addContact(bobContact);

    // Real create-with-members: creates the group + sends Bob invite#1 over the
    // relay + records his delivery attempt (status sent, with invite_id).
    final groupResult = await createGroupWithMembers(
      bridge: stack.bridge,
      groupRepo: stack.groupRepo,
      p2pService: stack.p2pService,
      identity: stack.identity,
      selectedContacts: [bobContact],
      type: GroupType.chat,
      name: 'Invite Reliability',
      inviteDeliveryAttemptRepo: stack.groupInviteDeliveryAttemptRepo,
    );
    final groupId = groupResult.group.id;
    expect(groupResult.membersAdded, 1);

    final group = await stack.groupRepo.getGroup(groupId);
    final keyInfo = await stack.groupRepo.getLatestKey(groupId);
    final members = await stack.groupRepo.getMembers(groupId);
    expect(group, isNotNull);
    expect(keyInfo, isNotNull);
    writeSharedJson(
      _signalName('group_fixture.json'),
      buildGroupFixture(group: group!, keyInfo: keyInfo!, members: members),
    );

    // ── F: Bob declines invite#1; the decline-ack flips Alice's row. ──
    await waitForSharedSignal(
      _signalName('bob_declined'),
      timeout: const Duration(minutes: 4),
    );
    await waitForCondition(() async {
      await stack.p2pService.drainOfflineInbox();
      final status = await stack.groupInviteDeliveryAttemptRepo
          .getStatusForMember(groupId: groupId, peerId: bobContact.peerId);
      return status == GroupInviteDeliveryStatus.declined;
    }, timeout: const Duration(seconds: 150));
    writeSharedText(_signalName('alice_saw_decline'), 'ok');

    // ── C: resend invite#2, then revoke it (HOLE-4 invite_id match). ──
    await resendGroupInvite(
      p2pService: stack.p2pService,
      bridge: stack.bridge,
      groupRepo: stack.groupRepo,
      inviteDeliveryAttemptRepo: stack.groupInviteDeliveryAttemptRepo,
      identity: stack.identity,
      groupId: groupId,
      memberPeerId: bobContact.peerId,
    );
    writeSharedText(_signalName('alice_invite2_sent'), 'ok');
    await waitForSharedSignal(
      _signalName('bob_got_invite2'),
      timeout: const Duration(minutes: 3),
    );

    final attempt = await stack.groupInviteDeliveryAttemptRepo.getAttempt(
      groupId: groupId,
      peerId: bobContact.peerId,
    );
    expect(
      attempt?.inviteId,
      isNotNull,
      reason: 'resend must persist the invite_id for revocation (HOLE-4)',
    );
    final revokeResult = await sendGroupInviteRevocation(
      p2pService: stack.p2pService,
      bridge: stack.bridge,
      inviteId: attempt!.inviteId!,
      groupId: groupId,
      recipientPeerId: bobContact.peerId,
      recipientMlKemPublicKey: bobContact.mlKemPublicKey,
      senderPeerId: stack.identity.peerId,
      senderPublicKey: stack.identity.publicKey,
      senderPrivateKey: stack.identity.privateKey,
      groupConfig: buildGroupConfigPayload(group, members),
    );
    expect(revokeResult, SendGroupInviteRevocationResult.success);
    writeSharedText(_signalName('alice_revoked'), 'ok');
    await waitForSharedSignal(
      _signalName('bob_revoked_ok'),
      timeout: const Duration(minutes: 3),
    );

    // ── D: bump metadata; answer Bob's config:request over the relay. ──
    final freshAt = DateTime.now().toUtc();
    await stack.groupRepo.updateGroup(
      group.copyWith(
        name: 'Invite Reliability (fresh)',
        lastMetadataEventAt: freshAt,
      ),
    );
    writeSharedText(_signalName('alice_metadata_fresh'), 'ok');
    // Keep draining so Alice processes Bob's config:request and replies.
    await waitForCondition(() async {
      await stack.p2pService.drainOfflineInbox();
      return File(sharedPath(_signalName('bob_converged'))).existsSync();
    }, timeout: const Duration(minutes: 4));
    writeSharedText(_signalName('alice_done'), 'ok');
  } finally {
    await stack.teardown();
  }
}

Future<void> _runInviteReliabilitySibling() async {
  final stack = await setupGroupMultiDeviceStack(
    dbName: _dbNameForRole(),
    username: 'Bob',
    cliPeerFixture: null,
    onJoinMetadataResyncEnabled: true,
  );
  try {
    writeSharedJson(
      _signalName('bob_identity.json'),
      _peerIdentityFixture(stack.identity),
    );
    final aliceFixture = await waitForSharedJson(
      _signalName('alice_identity.json'),
    );
    final aliceContact = _contactFromFixture(aliceFixture, 'Alice');
    await stack.contactRepo.addContact(aliceContact);

    // ── F: receive invite#1 over the relay, then decline it. ──
    await waitForCondition(() async {
      await stack.p2pService.drainOfflineInbox();
      return (await stack.pendingInviteRepo.getPendingInvites()).isNotEmpty;
    }, timeout: const Duration(minutes: 4));
    final firstInvite =
        (await stack.pendingInviteRepo.getPendingInvites()).first;
    final groupId = firstInvite.groupId;

    final declineResult = await declinePendingGroupInvite(
      pendingInviteRepo: stack.pendingInviteRepo,
      groupId: groupId,
      p2pService: stack.p2pService,
      bridge: stack.bridge,
      contactRepo: stack.contactRepo,
      declinerPeerId: stack.identity.peerId,
      declinerPrivateKey: stack.identity.privateKey,
    );
    expect(
      declineResult,
      anyOf(
        DeclinePendingGroupInviteResult.success,
        DeclinePendingGroupInviteResult.expired,
      ),
    );
    writeSharedText(_signalName('bob_declined'), 'ok');
    await waitForSharedSignal(
      _signalName('alice_saw_decline'),
      timeout: const Duration(minutes: 3),
    );

    // ── C: receive invite#2, confirm it is then revoked (deleted). ──
    await waitForSharedSignal(
      _signalName('alice_invite2_sent'),
      timeout: const Duration(minutes: 3),
    );
    await waitForCondition(() async {
      await stack.p2pService.drainOfflineInbox();
      return (await stack.pendingInviteRepo.getPendingInvite(groupId)) != null;
    }, timeout: const Duration(seconds: 150));
    writeSharedText(_signalName('bob_got_invite2'), 'ok');

    await waitForSharedSignal(
      _signalName('alice_revoked'),
      timeout: const Duration(minutes: 3),
    );
    await waitForCondition(() async {
      await stack.p2pService.drainOfflineInbox();
      return (await stack.pendingInviteRepo.getPendingInvite(groupId)) == null;
    }, timeout: const Duration(seconds: 150));
    writeSharedText(_signalName('bob_revoked_ok'), 'ok');

    // ── D: import membership (stale name), pull fresh config over the relay. ──
    final fixture = await waitForSharedJson(_signalName('group_fixture.json'));
    await importJoinedGroupFixture(stack: stack, fixture: fixture);
    await waitForSharedSignal(
      _signalName('alice_metadata_fresh'),
      timeout: const Duration(minutes: 3),
    );
    await sendOnJoinGroupConfigRequest(
      p2pService: stack.p2pService,
      bridge: stack.bridge,
      groupId: groupId,
      requesterPeerId: stack.identity.peerId,
      inviterPeerId: aliceContact.peerId,
      inviterMlKemPublicKey: aliceContact.mlKemPublicKey,
    );
    await waitForCondition(() async {
      await stack.p2pService.drainOfflineInbox();
      final converged = await stack.groupRepo.getGroup(groupId);
      return converged?.name == 'Invite Reliability (fresh)';
    }, timeout: const Duration(minutes: 4));
    writeSharedText(_signalName('bob_converged'), 'ok');
    await waitForSharedSignal(
      _signalName('alice_done'),
      timeout: const Duration(minutes: 3),
    );
  } finally {
    await stack.teardown();
  }
}

// ── R6: b1b_sibling_device_convergence (per-device ML-KEM key separation) ──
// primary = admin/creator; sibling = primary's restored second device (fresh
// transport + fresh ML-KEM). The sibling joins the topic (for the announce +
// to receive the post-admit group message) but DOES NOT persist the group key
// locally — it must obtain the current key ONLY via the live admit->redistribute
// 1:1 key-update, ML-KEM-sealed to its fresh per-device key. Build with
// --dart-define=MKNOON_ENABLE_MULTI_DEVICE_SYNC=true so admit/announce are live.

/// Imports the group SHELL (group + members + Go-side topic subscription) WITHOUT
/// persisting the group key to the local repo, so the only way `getLatestKey`
/// becomes non-null is the live key redistribution decrypting on this device's
/// fresh ML-KEM secret (the B1b proof). Mirrors [importJoinedGroupFixture] minus
/// the `saveKey` teleport.
Future<String> _importGroupShellForB1b({
  required GroupMultiDeviceTestStack stack,
  required Map<String, dynamic> fixture,
}) async {
  final group = GroupModel.fromMap(
    Map<String, dynamic>.from(fixture['group'] as Map),
  );
  final key = GroupKeyInfo.fromMap(
    Map<String, dynamic>.from(fixture['key'] as Map),
  );
  final members = (fixture['members'] as List<dynamic>)
      .map((raw) => GroupMember.fromMap(Map<String, dynamic>.from(raw as Map)))
      .toList(growable: false);
  final groupConfig = Map<String, dynamic>.from(fixture['groupConfig'] as Map);

  MemberRole? selfMemberRole;
  for (final member in members) {
    if (member.peerId == stack.identity.peerId) {
      selfMemberRole = member.role;
      break;
    }
  }
  final importedGroup = selfMemberRole == null
      ? group
      : group.copyWith(
          myRole: selfMemberRole == MemberRole.admin
              ? GroupRole.admin
              : GroupRole.member,
        );
  await stack.groupRepo.saveGroup(importedGroup);
  for (final member in members) {
    await stack.groupRepo.saveMember(member);
  }
  // NOTE: deliberately NO `stack.groupRepo.saveKey(key)` — the key must arrive
  // via the live redistribution, not the fixture. callGroupJoinWithConfig still
  // subscribes the Go bridge to the topic (so the announce can publish and the
  // post-admit message can be received).
  await callGroupJoinWithConfig(
    stack.bridge,
    groupId: group.id,
    groupConfig: groupConfig,
    groupKey: key.encryptedKey,
    keyEpoch: key.keyGeneration,
  );
  return group.id;
}

Future<void> _runB1bConvergencePrimary() async {
  final stack = await setupGroupMultiDeviceStack(
    dbName: _dbNameForRole(),
    username: 'B1b Primary',
    cliPeerFixture: null,
  );

  // Wire the SEND side of the deferred-distribution machinery (the 2-role stack
  // wires only the receive-side GroupKeyUpdateListener). Mirrors main.dart so
  // admit's reopen+drain re-distributes the current key to the sibling device.
  final distributionRepo = GroupPendingKeyDistributionRepositoryImpl(
    dbUpsertGroupPendingKeyDistribution: (row) =>
        dbUpsertGroupPendingKeyDistribution(stack.db, row),
    dbReopenGroupPendingKeyDistributionForRedelivery: (row) =>
        dbReopenGroupPendingKeyDistributionForRedelivery(stack.db, row),
    dbLoadGroupPendingKeyDistribution: (id) =>
        dbLoadGroupPendingKeyDistribution(stack.db, id),
    dbLoadPendingGroupKeyDistributionsForPeer:
        ({required peerId, groupId, int limit = 50}) =>
            dbLoadPendingGroupKeyDistributionsForPeer(
              stack.db,
              peerId: peerId,
              groupId: groupId,
              limit: limit,
            ),
    dbLoadPendingGroupKeyDistributionsForGroup:
        ({required groupId, int limit = 50}) =>
            dbLoadPendingGroupKeyDistributionsForGroup(
              stack.db,
              groupId: groupId,
              limit: limit,
            ),
    dbRecordGroupPendingKeyDistributionAttempt:
        (id, {required lastError, required updatedAt}) =>
            dbRecordGroupPendingKeyDistributionAttempt(
              stack.db,
              id,
              lastError: lastError,
              updatedAt: updatedAt,
            ),
    dbFinalizeGroupPendingKeyDistribution:
        (id, {required status, required lastError, required finalizedAt}) =>
            dbFinalizeGroupPendingKeyDistribution(
              stack.db,
              id,
              status: status,
              lastError: lastError,
              finalizedAt: finalizedAt,
            ),
  );
  final distributionRunner = GroupPendingKeyDistributionRunner(
    bridge: stack.bridge,
    groupRepo: stack.groupRepo,
    repository: distributionRepo,
    loadIdentity: stack.identityRepo.loadIdentity,
    sendP2PMessage: (peerId, message) async =>
        stack.p2pService.sendMessage(peerId, message),
    storeP2PMessageInInbox: (peerId, message) async =>
        stack.p2pService.storeInInbox(peerId, message),
  );
  setDeferredGroupKeyDistributionReopenSink(({
    required groupId,
    required peerId,
    required keyEpoch,
  }) async {
    final now = DateTime.now().toUtc();
    await distributionRepo.reopenForRedelivery(
      GroupPendingKeyDistribution(
        id: groupPendingKeyDistributionId(groupId, peerId),
        groupId: groupId,
        peerId: peerId,
        keyEpoch: keyEpoch,
        createdAt: now,
        updatedAt: now,
      ),
    );
  });
  setDeferredDistributionDrainSink(({required groupId, required peerId}) async {
    await distributionRunner.drainPendingForPeer(
      groupId: groupId,
      peerId: peerId,
    );
  });

  try {
    writeSharedJson(
      _signalName('primary_identity.json'),
      _primaryIdentityFixture(stack.identity),
    );

    final witness = await _generateOfflineContact(
      bridge: stack.bridge,
      username: 'B1b Witness',
    );
    await stack.contactRepo.addContact(witness);
    final groupResult = await createGroupWithMembers(
      bridge: stack.bridge,
      groupRepo: stack.groupRepo,
      p2pService: stack.p2pService,
      identity: stack.identity,
      selectedContacts: [witness],
      type: GroupType.chat,
      name: 'B1b Sibling Convergence',
      inviteDeliveryAttemptRepo: stack.groupInviteDeliveryAttemptRepo,
    );
    final groupId = groupResult.group.id;
    final group = await stack.groupRepo.getGroup(groupId);
    final keyInfo = await stack.groupRepo.getLatestKey(groupId);
    final members = await stack.groupRepo.getMembers(groupId);
    expect(group, isNotNull);
    expect(keyInfo, isNotNull);
    final primaryEpoch = keyInfo!.keyGeneration;

    writeSharedJson(
      _signalName('group_fixture.json'),
      buildGroupFixture(group: group!, keyInfo: keyInfo, members: members),
    );

    // Wait for the sibling to restore + announce its fresh per-device identity.
    final siblingDevice = await waitForSharedJson(
      _signalName('sibling_announced.json'),
      timeout: const Duration(minutes: 12),
    );
    final siblingTransport = siblingDevice['transportPeerId'] as String;
    final siblingMlKem = siblingDevice['mlKemPublicKey'] as String?;
    final siblingSigningKey = siblingDevice['publicKey'] as String;

    // Process the device_announce that the sibling published on the group topic
    // (best-effort; the admit below uses the announced identity directly — the
    // admin's trust approval).
    await drainGroupOfflineInboxForGroup(
      bridge: stack.bridge,
      groupRepo: stack.groupRepo,
      msgRepo: stack.groupMsgRepo,
      groupId: groupId,
      groupMessageListener: stack.groupListener,
    );

    final outcome = await admitSiblingDeviceIfTrusted(
      groupRepo: stack.groupRepo,
      groupId: groupId,
      memberPeerId: stack.identity.peerId,
      announcedDeviceId: siblingTransport,
      announcedTransportPeerId: siblingTransport,
      announcedDeviceSigningPublicKey: siblingSigningKey,
      verifiedAccountSigningPublicKey: stack.identity.publicKey,
      announcedMlKemPublicKey: siblingMlKem,
      multiDeviceSyncEnabled: true,
    );
    expect(
      outcome,
      SiblingDeviceAdmissionOutcome.admitted,
      reason: 'B1b: the fresh sibling device must be admitted',
    );
    final selfMember = await stack.groupRepo.getMember(
      groupId,
      stack.identity.peerId,
    );
    expect(
      selfMember!.activeDevices.any(
        (device) => device.transportPeerId == siblingTransport,
      ),
      isTrue,
      reason: 'B1b: the sibling device must land on the creator member roster',
    );
    writeSharedText(_signalName('primary_admitted_sibling'), 'ok');

    // The admit triggered reopen+drain; also send a post-admit group message the
    // converged sibling should receive + decrypt.
    final postAdmitText = 'B1b post-admit from primary $configuredRunId';
    final sendResult = await sendGroupMessage(
      bridge: stack.bridge,
      groupRepo: stack.groupRepo,
      msgRepo: stack.groupMsgRepo,
      groupId: groupId,
      text: postAdmitText,
      senderPeerId: stack.identity.peerId,
      senderPublicKey: stack.identity.publicKey,
      senderPrivateKey: stack.identity.privateKey,
      senderUsername: stack.identity.username,
      inviteDeliveryAttemptRepo: stack.groupInviteDeliveryAttemptRepo,
      includeSenderPeerIdInDurableRecipients: true,
    );
    expect(
      sendResult.$1,
      anyOf(
        SendGroupMessageResult.success,
        SendGroupMessageResult.successNoPeers,
      ),
    );

    writeSharedJson(_signalName('primary_verdict.json'), {
      'primaryPeerId': stack.identity.peerId,
      'primaryTransportPeerId': stack.p2pService.currentState.peerId,
      'primaryMlKemPublicKey': stack.identity.mlKemPublicKey,
      'admitOutcome': outcome.name,
      'primaryEpoch': primaryEpoch,
      'postAdmitText': postAdmitText,
    });

    await waitForSharedSignal(
      _signalName('sibling_complete'),
      timeout: const Duration(minutes: 5),
    );
  } finally {
    setDeferredDistributionDrainSink(null);
    setDeferredGroupKeyDistributionReopenSink(null);
    await stack.teardown();
  }
}

Future<void> _runB1bConvergenceSibling() async {
  final identityFixture = await waitForSharedJson(
    _signalName('primary_identity.json'),
  );
  final mnemonic = identityFixture['mnemonic12'] as String?;
  expect(
    mnemonic,
    isNotNull,
    reason: 'Primary must publish a mnemonic for sibling restore',
  );

  final stack = await setupGroupMultiDeviceStack(
    dbName: _dbNameForRole(),
    username: 'B1b Sibling',
    cliPeerFixture: null,
    restoreMnemonic: mnemonic,
    useFreshTransportIdentityForRestoredAccount: true,
  );

  try {
    expect(
      stack.identity.peerId,
      identityFixture['peerId'],
      reason: 'Sibling must restore the same user (logical) identity',
    );
    final siblingTransport = stack.p2pService.currentState.peerId!;
    expect(
      siblingTransport,
      isNot(stack.identity.peerId),
      reason: 'B1b: the restored device must use a FRESH transport peer id',
    );
    expect(
      stack.identity.mlKemPublicKey,
      isNot(identityFixture['mlKemPublicKey']),
      reason: 'B1b: restore must mint a FRESH per-device ML-KEM key',
    );

    final fixture = await waitForSharedJson(_signalName('group_fixture.json'));
    final groupId = await _importGroupShellForB1b(
      stack: stack,
      fixture: fixture,
    );
    // Proof precondition: the sibling has NO group key yet (the fixture key was
    // deliberately not persisted).
    expect(
      await stack.groupRepo.getLatestKey(groupId),
      isNull,
      reason: 'B1b: sibling must start keyless (key only via redistribution)',
    );

    // Announce this fresh device to the group (account-key-signed) — exercises
    // the real announce wire path.
    final announcedDevice = GroupMemberDeviceIdentity(
      deviceId: siblingTransport,
      transportPeerId: siblingTransport,
      deviceSigningPublicKey: stack.identity.publicKey,
      mlKemPublicKey: stack.identity.mlKemPublicKey,
    );
    final announcedCount = await announceRestoredDeviceToGroups(
      bridge: stack.bridge,
      groupRepo: stack.groupRepo,
      selfPeerId: stack.identity.peerId,
      accountSigningPublicKey: stack.identity.publicKey,
      accountSigningPrivateKey: stack.identity.privateKey,
      selfUsername: stack.identity.username,
      announcedDevice: announcedDevice,
      multiDeviceSyncEnabled: true,
    );
    expect(
      announcedCount,
      greaterThanOrEqualTo(1),
      reason: 'B1b: the sibling must announce its device to the group',
    );

    // Publish the announced device identity so the primary (admin) can admit it.
    writeSharedJson(_signalName('sibling_announced.json'), {
      'transportPeerId': siblingTransport,
      'publicKey': stack.identity.publicKey,
      if (stack.identity.mlKemPublicKey != null)
        'mlKemPublicKey': stack.identity.mlKemPublicKey,
    });

    // A restored device knows its OWN identity: register this device on the
    // local member roster so the incoming redistribution's recipient-device
    // binding (_isBoundToLocalRecipient) resolves. The shell fixture predates the
    // admin's admit, so the device is otherwise absent from the local roster —
    // this does NOT introduce the key (which still arrives only via the live
    // 1:1 ML-KEM redistribution).
    final selfMemberBeforeKey = await stack.groupRepo.getMember(
      groupId,
      stack.identity.peerId,
    );
    if (selfMemberBeforeKey != null &&
        !selfMemberBeforeKey.devices.any(
          (device) => device.transportPeerId == siblingTransport,
        )) {
      await stack.groupRepo.saveMember(
        selfMemberBeforeKey.copyWith(
          devices: [...selfMemberBeforeKey.devices, announcedDevice],
        ),
      );
    }

    await waitForSharedSignal(
      _signalName('primary_admitted_sibling'),
      timeout: const Duration(minutes: 5),
    );

    // The runner now re-distributes the CURRENT group key 1:1, ML-KEM-sealed to
    // this device's FRESH key. Drain the relay inbox so the key-update arrives;
    // getLatestKey transitions null -> present ONLY when our GroupKeyUpdateListener
    // decrypts that key-update with our fresh ML-KEM secret (the B1b proof).
    await waitForCondition(() async {
      await drainGroupOfflineInboxForGroup(
        bridge: stack.bridge,
        groupRepo: stack.groupRepo,
        msgRepo: stack.groupMsgRepo,
        groupId: groupId,
        groupMessageListener: stack.groupListener,
      );
      return (await stack.groupRepo.getLatestKey(groupId)) != null;
    }, timeout: const Duration(seconds: 120));
    final convergedKey = await stack.groupRepo.getLatestKey(groupId);
    expect(convergedKey, isNotNull);

    // Decrypt the primary's post-admit group message (end-to-end proof).
    final primaryVerdict = await waitForSharedJson(
      _signalName('primary_verdict.json'),
    );
    final postAdmitText = primaryVerdict['postAdmitText'] as String;
    await waitForCondition(() async {
      await drainGroupOfflineInboxForGroup(
        bridge: stack.bridge,
        groupRepo: stack.groupRepo,
        msgRepo: stack.groupMsgRepo,
        groupId: groupId,
        groupMessageListener: stack.groupListener,
      );
      final latest = await stack.groupMsgRepo.getLatestMessage(groupId);
      return latest?.text == postAdmitText;
    }, timeout: const Duration(seconds: 120));

    expect(
      stack.identity.mlKemPublicKey,
      isNot(primaryVerdict['primaryMlKemPublicKey']),
      reason: 'B1b: sibling per-device ML-KEM must differ from the primary',
    );
    expect(siblingTransport, isNot(primaryVerdict['primaryTransportPeerId']));

    writeSharedJson(_signalName('sibling_verdict.json'), {
      'siblingPeerId': stack.identity.peerId,
      'siblingTransportPeerId': siblingTransport,
      'siblingMlKemPublicKey': stack.identity.mlKemPublicKey,
      'keyEpochReceived': convergedKey!.keyGeneration,
      'decryptedPostAdmitText': postAdmitText,
    });
    writeSharedText(_signalName('sibling_complete'), 'ok');
  } finally {
    await stack.teardown();
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  initializeSqliteForCurrentPlatform();

  testWidgets(
    'MD-004 multi-device proof scenario=$configuredScenario role=$configuredRole run=$configuredRunId',
    (tester) async {
      if (!_isPrimaryRole && !_isSiblingRole) {
        fail('Unsupported MD004_ROLE: $configuredRole');
      }

      if (configuredScenario == 'invite_reliability') {
        if (_isPrimaryRole) {
          await _runInviteReliabilityPrimary();
        } else {
          await _runInviteReliabilitySibling();
        }
        return;
      }

      // R6 (12-P2 Part B): per-device ML-KEM key separation. The primary
      // (admin/creator) admits its OWN restored sibling device; the sibling
      // obtains the current group key ONLY via the live announce->admit->
      // redistribute path (a 1:1 key-update ML-KEM-sealed to its FRESH per-device
      // key), never via the fixture. Requires the build to be compiled with
      // --dart-define=MKNOON_ENABLE_MULTI_DEVICE_SYNC=true.
      if (configuredScenario == 'b1b_sibling_device_convergence') {
        if (_isPrimaryRole) {
          await _runB1bConvergencePrimary();
        } else {
          await _runB1bConvergenceSibling();
        }
        return;
      }

      if (_isPrimaryRole) {
        await _runPrimaryScenario();
      } else {
        await _runSiblingScenario();
      }
    },
  );
}
