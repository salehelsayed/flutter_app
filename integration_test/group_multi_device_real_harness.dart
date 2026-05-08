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
import 'package:flutter_app/core/database/helpers/group_members_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_messages_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/groups_db_helpers.dart';
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
import 'package:flutter_app/core/notifications/active_conversation_tracker.dart';
import 'package:flutter_app/core/secure_storage/secure_key_store.dart';
import 'package:flutter_app/core/services/incoming_message_router.dart';
import 'package:flutter_app/core/services/p2p_service_impl.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository_impl.dart';
import 'package:flutter_app/features/groups/application/add_group_member_use_case.dart';
import 'package:flutter_app/features/groups/application/create_group_with_members_use_case.dart';
import 'package:flutter_app/features/groups/application/drain_group_offline_inbox_use_case.dart';
import 'package:flutter_app/features/groups/application/group_config_payload.dart';
import 'package:flutter_app/features/groups/application/group_key_update_listener.dart';
import 'package:flutter_app/features/groups/application/group_offline_replay_envelope.dart';
import 'package:flutter_app/features/groups/application/group_message_listener.dart';
import 'package:flutter_app/features/groups/application/send_group_message_use_case.dart';
import 'package:flutter_app/features/groups/application/set_group_muted_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository_impl.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository_impl.dart';
import 'package:flutter_app/features/identity/application/generate_identity_use_case.dart';
import 'package:flutter_app/features/identity/application/restore_identity_use_case.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository_impl.dart';

import '../test/shared/fakes/fake_notification_service.dart';
import '../test/shared/fakes/in_memory_inbox_staging_repository.dart';

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

void writeSharedJson(String name, Map<String, dynamic> value) {
  Directory(configuredSharedDir).createSync(recursive: true);
  File(sharedPath(name)).writeAsStringSync(jsonEncode(value));
}

void writeSharedText(String name, String value) {
  Directory(configuredSharedDir).createSync(recursive: true);
  File(sharedPath(name)).writeAsStringSync(value);
}

Future<Map<String, dynamic>> waitForSharedJson(
  String name, {
  Duration timeout = const Duration(seconds: 180),
}) async {
  final deadline = DateTime.now().add(timeout);
  final file = File(sharedPath(name));
  while (DateTime.now().isBefore(deadline)) {
    if (file.existsSync()) {
      return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    }
    await Future<void>.delayed(const Duration(milliseconds: 250));
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

class _FakeSecureKeyStore implements SecureKeyStore {
  final Map<String, String> _store = {};

  @override
  Future<String?> read(String key) async => _store[key];

  @override
  Future<void> write(String key, String value) async => _store[key] = value;

  @override
  Future<void> delete(String key) async => _store.remove(key);

  @override
  Future<bool> containsKey(String key) async => _store.containsKey(key);
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
    version: 66,
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
  final IncomingMessageRouter messageRouter;
  final GroupKeyUpdateListener groupKeyUpdateListener;
  final GroupMessageListener groupListener;
  final StreamController<Map<String, dynamic>> groupStreamController;
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
    required this.messageRouter,
    required this.groupKeyUpdateListener,
    required this.groupListener,
    required this.groupStreamController,
    required this.notificationService,
    required this.identity,
    required this.cliContact,
  });

  Future<void> teardown() async {
    groupKeyUpdateListener.dispose();
    messageRouter.dispose();
    groupListener.dispose();
    await groupStreamController.close();
    await p2pService.stopNode();
    p2pService.dispose();
    bridge.dispose();
    await db.close();
    await deleteTestDatabase(dbName);
  }
}

Future<GroupMultiDeviceTestStack> setupGroupMultiDeviceStack({
  required String dbName,
  required String username,
  required Map<String, dynamic>? cliPeerFixture,
  String? restoreMnemonic,
}) async {
  final secureKeyStore = _FakeSecureKeyStore();
  await deleteTestDatabase(dbName);
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
  final groupMsgRepo = GroupMessageRepositoryImpl(
    dbInsertGroupMessage: (row) => dbInsertGroupMessage(db, row),
    dbLoadGroupMessagesPage: (groupId, {limit = 50, offset = 0}) =>
        dbLoadGroupMessagesPage(db, groupId, limit: limit, offset: offset),
    dbLoadGroupMessage: (id) => dbLoadGroupMessage(db, id),
    dbLoadLatestGroupMessage: (groupId) =>
        dbLoadLatestGroupMessage(db, groupId),
    dbUpdateGroupMessageStatus: (id, status) =>
        dbUpdateGroupMessageStatus(db, id, status),
    dbCountGroupMessages: (groupId) => dbCountGroupMessages(db, groupId),
    dbCountUnreadGroupMessages: (groupId) =>
        dbCountUnreadGroupMessages(db, groupId),
    dbCountTotalUnreadGroupMessages: () => dbCountTotalUnreadGroupMessages(db),
    dbMarkGroupMessagesAsRead: (groupId) =>
        dbMarkGroupMessagesAsRead(db, groupId),
    dbDeleteGroupMessage: (id) => dbDeleteGroupMessage(db, id),
    dbExistsGroupMessageByContent: (groupId, senderPeerId, text, timestamp) =>
        dbExistsGroupMessageByContent(
          db,
          groupId,
          senderPeerId,
          text,
          timestamp,
        ),
    dbDeleteGroupMessagesForGroup: (groupId) =>
        dbDeleteGroupMessagesForGroup(db, groupId),
    dbLoadGroupThreadSummaries: (groupIds) =>
        dbLoadGroupThreadSummaries(db, groupIds),
    dbLoadFailedOutgoingGroupMessagesFn: () =>
        dbLoadFailedOutgoingGroupMessages(db),
    dbRecoverStuckSendingGroupMessagesFn: ({olderThan}) =>
        dbTransitionGroupSendingToFailed(db, olderThan: olderThan),
    dbLoadGroupMessagesWithFailedInboxStore: ({limit = 20}) =>
        dbLoadGroupMessagesWithFailedInboxStore(db, limit: limit),
    dbUpdateGroupMessageInboxStoredFn: (id, {required stored}) =>
        dbUpdateGroupMessageInboxStored(db, id, stored: stored),
    dbUpdateGroupMessageInboxRetryPayloadFn: (id, payload) =>
        dbUpdateGroupMessageInboxRetryPayload(db, id, payload),
    dbUpdateGroupMessageWireEnvelopeFn: (id, envelope) =>
        dbUpdateGroupMessageWireEnvelope(db, id, envelope),
  );

  final bridge = GoBridgeClient();
  await bridge.initialize();

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

  final savedIdentity = await identityRepo.loadIdentity();
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
    updatedIdentity.privateKey,
    updatedIdentity.peerId,
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

  final groupListener = GroupMessageListener(
    groupRepo: groupRepo,
    msgRepo: groupMsgRepo,
    bridge: bridge,
    getSelfPeerId: () async => updatedIdentity.peerId,
    notificationService: notificationService,
    groupConversationTracker: ActiveConversationTracker(),
    getAppLifecycleState: () => AppLifecycleState.paused,
  );
  messageRouter.start();
  groupKeyUpdateListener.start();
  groupListener.start(groupStreamController.stream);

  return GroupMultiDeviceTestStack(
    db: db,
    dbName: dbName,
    bridge: bridge,
    p2pService: p2pService,
    identityRepo: identityRepo,
    contactRepo: contactRepo,
    groupRepo: groupRepo,
    groupMsgRepo: groupMsgRepo,
    messageRouter: messageRouter,
    groupKeyUpdateListener: groupKeyUpdateListener,
    groupListener: groupListener,
    groupStreamController: groupStreamController,
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

  await stack.groupRepo.saveGroup(group);
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
  if (mnemonic == null || mnemonic.trim().isEmpty) {
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

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  initializeSqliteForCurrentPlatform();

  testWidgets(
    'MD-004 same-user sibling-device proof role=$configuredRole run=$configuredRunId',
    (tester) async {
      if (!_isPrimaryRole && !_isSiblingRole) {
        fail('Unsupported MD004_ROLE: $configuredRole');
      }

      if (_isPrimaryRole) {
        await _runPrimaryScenario();
      } else {
        await _runSiblingScenario();
      }
    },
  );
}
