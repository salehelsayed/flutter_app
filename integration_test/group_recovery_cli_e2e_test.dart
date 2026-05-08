import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:flutter_app/core/bridge/go_bridge_client.dart';
import 'package:flutter_app/core/database/encrypted_db_opener.dart';
import 'package:flutter_app/core/database/helpers/contacts_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_keys_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_members_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_messages_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/groups_db_helpers.dart';
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
import 'package:flutter_app/core/database/migrations/067_group_invite_delivery_attempts.dart';
import 'package:flutter_app/core/secure_storage/secure_key_store.dart';
import 'package:flutter_app/core/services/p2p_service_impl.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository_impl.dart';
import 'package:flutter_app/features/groups/application/create_group_with_members_use_case.dart';
import 'package:flutter_app/features/groups/application/drain_group_offline_inbox_use_case.dart';
import 'package:flutter_app/features/groups/application/group_message_listener.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository_impl.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository_impl.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';

import '../test/shared/fakes/in_memory_inbox_staging_repository.dart';

const _readDir = String.fromEnvironment('E2E_TEMP_DIR', defaultValue: '/tmp');
const _writeDir = String.fromEnvironment('E2E_WRITE_DIR', defaultValue: '/tmp');
const _dbName = String.fromEnvironment(
  'E2E_DB_NAME',
  defaultValue: 'group_recovery_cli_e2e.db',
);

String _readSignalPath(String name) => '$_readDir/$name';
String _writeSignalPath(String name) => '$_writeDir/$name';

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

Map<String, dynamic>? _loadCliPeerFixture() {
  const fixturePath = String.fromEnvironment(
    'CLI_PEER_FIXTURE',
    defaultValue: '/tmp/cli_peer_fixture.json',
  );

  final file = File(fixturePath);
  if (!file.existsSync()) return null;

  try {
    return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  } catch (e) {
    debugPrint('[GROUP-E2E] Failed to parse CLI fixture: $e');
    return null;
  }
}

void _writeJsonSignal(String name, Map<String, dynamic> value) {
  Directory(_writeDir).createSync(recursive: true);
  File(_writeSignalPath(name)).writeAsStringSync(jsonEncode(value));
}

void _writeTextSignal(String name, String value) {
  Directory(_writeDir).createSync(recursive: true);
  File(_writeSignalPath(name)).writeAsStringSync(value);
}

Future<void> _waitForSignal(
  String name, {
  Duration timeout = const Duration(seconds: 60),
}) async {
  final deadline = DateTime.now().add(timeout);
  final file = File(_readSignalPath(name));
  while (DateTime.now().isBefore(deadline)) {
    if (file.existsSync()) return;
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
  fail('Timed out waiting for signal: $name');
}

Future<void> _waitForIncomingGroupCount(
  GroupMessageRepositoryImpl repo,
  String groupId,
  int expectedCount, {
  Duration timeout = const Duration(seconds: 45),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    final messages = await repo.getMessagesPage(groupId, limit: 20);
    final incoming = messages.where((m) => m.isIncoming).length;
    if (incoming >= expectedCount) return;
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
  fail('Timed out waiting for $expectedCount incoming group messages');
}

class _TestStack {
  final dynamic db;
  final String dbName;
  final GoBridgeClient bridge;
  final P2PServiceImpl p2pService;
  final ContactRepositoryImpl contactRepo;
  final GroupRepositoryImpl groupRepo;
  final GroupMessageRepositoryImpl groupMsgRepo;
  final GroupMessageListener groupListener;
  final StreamController<Map<String, dynamic>> groupStreamController;
  final IdentityModel identity;
  final ContactModel? cliContact;

  const _TestStack({
    required this.db,
    required this.dbName,
    required this.bridge,
    required this.p2pService,
    required this.contactRepo,
    required this.groupRepo,
    required this.groupMsgRepo,
    required this.groupListener,
    required this.groupStreamController,
    required this.identity,
    required this.cliContact,
  });

  Future<void> teardown() async {
    groupListener.dispose();
    await groupStreamController.close();
    await p2pService.stopNode();
    p2pService.dispose();
    bridge.dispose();
    await db.close();
    try {
      final dbPath = await databaseFactory.getDatabasesPath();
      await databaseFactory.deleteDatabase('$dbPath/$dbName');
    } catch (_) {}

    for (final name in [
      'flutter_peer_fixture.json',
      'group_recovery_fixture.json',
      'e2e_group_live_received',
    ]) {
      try {
        File(_writeSignalPath(name)).deleteSync();
      } catch (_) {}
    }
  }
}

Future<_TestStack> _setupStack() async {
  final cliPeer = _loadCliPeerFixture();
  final secureKeyStore = _FakeSecureKeyStore();

  final db = await openEncryptedDatabase(
    secureKeyStore: secureKeyStore,
    dbName: _dbName,
    version: 67,
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
    },
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
  );

  final bridge = GoBridgeClient();
  await bridge.initialize();

  final genResponse = await bridge.send(
    jsonEncode({'cmd': 'identity.generate', 'payload': {}}),
  );
  final genResult = jsonDecode(genResponse) as Map<String, dynamic>;
  expect(genResult['ok'], true);

  final mlKemResponse = await bridge.send(
    jsonEncode({'cmd': 'mlkem.keygen', 'payload': {}}),
  );
  final mlKemResult = jsonDecode(mlKemResponse) as Map<String, dynamic>;
  expect(mlKemResult['ok'], true);

  final identity = IdentityModel(
    peerId: genResult['identity']['peerId'] as String,
    publicKey: genResult['identity']['publicKey'] as String,
    privateKey: genResult['identity']['privateKey'] as String,
    mnemonic12: genResult['identity']['mnemonic12'] as String,
    mlKemPublicKey: mlKemResult['publicKey'] as String,
    mlKemSecretKey: mlKemResult['secretKey'] as String,
    username: 'FlutterGroupE2E',
    createdAt: DateTime.now().toUtc().toIso8601String(),
    updatedAt: DateTime.now().toUtc().toIso8601String(),
  );

  ContactModel? cliContact;
  if (cliPeer != null) {
    cliContact = ContactModel(
      peerId: cliPeer['peerId'] as String,
      publicKey: cliPeer['publicKey'] as String,
      rendezvous: '/dns4/relay/tcp/443/p2p/relay',
      username: 'CLIGroupPeer',
      signature: 'sig-cli-group-peer',
      scannedAt: DateTime.now().toUtc().toIso8601String(),
      mlKemPublicKey: cliPeer['mlKemPublicKey'] as String?,
    );
    await contactRepo.addContact(cliContact);
  }

  _writeJsonSignal('flutter_peer_fixture.json', {
    'peerId': identity.peerId,
    'publicKey': identity.publicKey,
    if (identity.mlKemPublicKey != null)
      'mlKemPublicKey': identity.mlKemPublicKey,
  });

  final p2pService = P2PServiceImpl(
    bridge: bridge,
    inboxStagingRepository: InMemoryInboxStagingRepository(),
  );
  final started = await p2pService.startNode(
    identity.privateKey,
    identity.peerId,
  );
  expect(started, true, reason: 'P2P node failed to start');

  final groupStreamController =
      StreamController<Map<String, dynamic>>.broadcast();
  bridge.onGroupMessageReceived = (data) {
    groupStreamController.add(data);
  };

  final groupListener = GroupMessageListener(
    groupRepo: groupRepo,
    msgRepo: groupMsgRepo,
    bridge: bridge,
    getSelfPeerId: () async => identity.peerId,
  );
  groupListener.start(groupStreamController.stream);

  return _TestStack(
    db: db,
    dbName: _dbName,
    bridge: bridge,
    p2pService: p2pService,
    contactRepo: contactRepo,
    groupRepo: groupRepo,
    groupMsgRepo: groupMsgRepo,
    groupListener: groupListener,
    groupStreamController: groupStreamController,
    identity: identity,
    cliContact: cliContact,
  );
}

Map<String, dynamic> _groupConfigFromModel(
  GroupModel group,
  List<dynamic> members,
) {
  return {
    'name': group.name,
    'groupType': group.type.toValue(),
    if (group.description != null) 'description': group.description,
    'members': members,
    'createdBy': group.createdBy,
    'createdAt': group.createdAt.toUtc().toIso8601String(),
  };
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  if (Platform.isLinux || Platform.isMacOS || Platform.isWindows) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  testWidgets('real CLI peer drives live and inbox group recovery', (
    tester,
  ) async {
    if (_loadCliPeerFixture() == null) {
      debugPrint(
        '[GROUP-E2E] No accessible CLI peer fixture. Skipping CLI-backed scenario.',
      );
      return;
    }

    final stack = await _setupStack();

    try {
      final result = await createGroupWithMembers(
        bridge: stack.bridge,
        groupRepo: stack.groupRepo,
        p2pService: stack.p2pService,
        identity: stack.identity,
        selectedContacts: [stack.cliContact!],
        type: GroupType.chat,
        name: 'CLI Recovery Group',
      );

      final keyInfo = await stack.groupRepo.getLatestKey(result.group.id);
      expect(keyInfo, isNotNull, reason: 'Group key should be persisted');

      final members = await stack.groupRepo.getMembers(result.group.id);
      final memberMaps = members
          .map(
            (member) => {
              'peerId': member.peerId,
              'username': member.username,
              'role': member.role.toValue(),
              'publicKey': member.publicKey,
              if (member.mlKemPublicKey != null)
                'mlKemPublicKey': member.mlKemPublicKey,
            },
          )
          .toList(growable: false);

      _writeJsonSignal('group_recovery_fixture.json', {
        'groupId': result.group.id,
        'groupKey': keyInfo!.encryptedKey,
        'keyEpoch': keyInfo.keyGeneration,
        'groupConfig': _groupConfigFromModel(result.group, memberMaps),
      });

      await _waitForIncomingGroupCount(stack.groupMsgRepo, result.group.id, 1);
      _writeTextSignal('e2e_group_live_received', 'ok');

      await _waitForSignal('e2e_group_cli_inbox_stored');
      await drainGroupOfflineInbox(
        bridge: stack.bridge,
        groupRepo: stack.groupRepo,
        msgRepo: stack.groupMsgRepo,
      );

      final firstDrain = await stack.groupMsgRepo.getMessagesPage(
        result.group.id,
        limit: 20,
      );
      final firstIncoming = firstDrain.where((m) => m.isIncoming).toList();
      expect(firstIncoming, hasLength(2));
      expect(
        firstIncoming.map((m) => m.text),
        containsAll(['CLI live message', 'CLI missed inbox message']),
      );

      await drainGroupOfflineInbox(
        bridge: stack.bridge,
        groupRepo: stack.groupRepo,
        msgRepo: stack.groupMsgRepo,
      );

      final secondDrain = await stack.groupMsgRepo.getMessagesPage(
        result.group.id,
        limit: 20,
      );
      expect(secondDrain.where((m) => m.isIncoming), hasLength(2));
    } finally {
      await stack.teardown();
    }
  });
}
