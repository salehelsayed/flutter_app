import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite_sqlcipher/sqflite.dart' as sqlcipher;

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/bridge/bridge_group_helpers.dart';
import 'package:flutter_app/core/bridge/go_bridge_client.dart';
import 'package:flutter_app/core/database/app_database_version.dart';
import 'package:flutter_app/core/database/direct_event_fanout_contract.dart';
import 'package:flutter_app/core/database/encrypted_db_opener.dart';
import 'package:flutter_app/core/config/direct_linked_devices_flag.dart';
import 'package:flutter_app/core/config/direct_linked_event_fanout_flag.dart';
import 'package:flutter_app/core/config/direct_linked_media_fanout_flag.dart';
import 'package:flutter_app/core/config/direct_media_blob_custody_client_flag.dart';
import 'package:flutter_app/core/database/direct_media_blob_custody.dart';
import 'package:flutter_app/core/database/helpers/direct_contact_device_bindings_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/direct_inbox_custody_outbox_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/direct_media_blob_custody_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/direct_reaction_inbox_custody_outbox_db_helpers.dart';
import 'package:flutter_app/core/notifications/canonical_runtime_lease.dart';
import 'package:flutter_app/core/secure_storage/flutter_secure_key_store.dart';
import 'package:flutter_app/features/identity/application/linked_installation_authority.dart';
import 'package:flutter_app/features/p2p/application/start_node_use_case.dart';
import 'package:flutter_app/features/qr_code/application/direct_linked_device_qr.dart';
import 'package:flutter_app/core/database/helpers/contacts_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_exit_intents_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_event_log_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_keys_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_invite_delivery_attempts_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_members_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_message_local_deletions_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_messages_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_media_key_snapshot.dart';
import 'package:flutter_app/core/database/helpers/pending_group_broadcasts_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/pending_sibling_devices_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/linked_group_bootstrap_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_pending_key_repairs_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_reaction_replay_outbox_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_sync_receipts_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/groups_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/identity_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/media_attachments_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/media_library_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/messages_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/reactions_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/protected_group_content_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/protected_group_reaction_target_db_helpers.dart';
import 'package:flutter_app/core/database/outgoing_transport_mutation.dart';
import 'package:flutter_app/core/database/production_migration_registry.dart';
import 'package:flutter_app/core/notifications/active_conversation_tracker.dart';
import 'package:flutter_app/core/media/direct_media_blob_artifact_store.dart';
import 'package:flutter_app/core/media/direct_media_custody_intent.dart';
import 'package:flutter_app/core/media/group_media_blob_artifact_store.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/secure_storage/secure_key_store.dart';
import 'package:flutter_app/core/services/incoming_message_router.dart';
import 'package:flutter_app/core/services/p2p_service_impl.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/contacts/application/direct_transport_authority.dart';
import 'package:flutter_app/features/contacts/data/repositories/contact_repository_impl.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';
import 'package:flutter_app/features/conversation/application/delivery_receipt_listener.dart';
import 'package:flutter_app/features/conversation/application/direct_event_fanout_coordinator.dart';
import 'package:flutter_app/features/conversation/application/direct_media_fanout_admission.dart';
import 'package:flutter_app/features/conversation/application/prepared_direct_media_blob_custody_coordinator.dart';
import 'package:flutter_app/features/conversation/application/send_chat_message_use_case.dart';
import 'package:flutter_app/features/conversation/application/send_delivery_receipt_use_case.dart';
import 'package:flutter_app/features/conversation/data/repositories/media_attachment_repository_impl.dart';
import 'package:flutter_app/features/conversation/data/repositories/message_repository_impl.dart';
import 'package:flutter_app/features/conversation/data/repositories/reaction_repository_impl.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/models/outgoing_ordinary_mutation_result.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/groups/application/add_group_member_use_case.dart';
import 'package:flutter_app/features/groups/application/create_group_use_case.dart';
import 'package:flutter_app/features/groups/application/create_group_with_members_use_case.dart';
import 'package:flutter_app/features/groups/application/drain_group_offline_inbox_use_case.dart';
import 'package:flutter_app/features/groups/application/group_config_payload.dart';
import 'package:flutter_app/features/groups/application/group_invite_send_latency_trace.dart';
import 'package:flutter_app/features/groups/application/group_key_update_listener.dart';
import 'package:flutter_app/features/groups/application/group_membership_update_listener.dart';
import 'package:flutter_app/features/groups/application/group_offline_replay_envelope.dart';
import 'package:flutter_app/features/groups/application/group_pending_broadcast_repush.dart';
import 'package:flutter_app/features/groups/application/group_pending_broadcast_runner.dart';
import 'package:flutter_app/features/groups/application/linked_group_bootstrap_service.dart';
import 'package:flutter_app/features/groups/application/protected_group_authority.dart';
import 'package:flutter_app/features/groups/application/protected_group_authority_history.dart';
import 'package:flutter_app/features/groups/application/protected_group_content_authoring_resolver.dart';
import 'package:flutter_app/features/groups/application/protected_group_content_reconciliation.dart';
import 'package:flutter_app/features/groups/application/protected_group_content_receive.dart';
import 'package:flutter_app/features/groups/application/protected_group_envelope.dart';
import 'package:flutter_app/features/groups/application/prepared_group_media_blob_custody_coordinator.dart';
import 'package:flutter_app/features/groups/application/protected_group_media_manifest.dart';
import 'package:flutter_app/features/groups/application/remove_group_reaction_use_case.dart';
import 'package:flutter_app/features/groups/application/group_message_listener.dart';
import 'package:flutter_app/features/groups/application/rejoin_group_topics_use_case.dart';
import 'package:flutter_app/features/groups/application/rotate_and_distribute_group_key_use_case.dart';
import 'package:flutter_app/features/groups/application/send_group_message_use_case.dart';
import 'package:flutter_app/features/groups/application/send_group_reaction_use_case.dart';
import 'package:flutter_app/features/groups/application/signed_group_transition_audit.dart';
import 'package:flutter_app/features/groups/application/strict_group_media_blob_download_ack_owner.dart';
import 'package:flutter_app/features/groups/application/set_group_muted_use_case.dart';
import 'package:flutter_app/features/groups/application/decline_pending_group_invite_use_case.dart';
import 'package:flutter_app/features/groups/application/group_invite_listener.dart';
import 'package:flutter_app/features/groups/application/on_join_group_config_resync_use_case.dart';
import 'package:flutter_app/features/groups/application/resend_group_invite_use_case.dart';
import 'package:flutter_app/features/groups/application/revoke_pending_group_invite_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_invite_delivery_attempt.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/models/group_reaction_replay_outbox_entry.dart';
import 'package:flutter_app/features/groups/data/repositories/group_message_repository_impl.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_exit_intent_repository.dart';
import 'package:flutter_app/features/groups/data/repositories/group_exit_intent_repository_impl.dart';
import 'package:flutter_app/features/groups/data/repositories/group_invite_delivery_attempt_repository_impl.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_pending_broadcast_repository.dart';
import 'package:flutter_app/features/groups/data/repositories/group_pending_broadcast_repository_impl.dart';
import 'package:flutter_app/features/groups/data/repositories/group_pending_key_repair_repository_impl.dart';
import 'package:flutter_app/features/groups/data/repositories/group_reaction_replay_outbox_repository_impl.dart';
import 'package:flutter_app/features/groups/data/repositories/group_repository_impl.dart';
import 'package:flutter_app/features/groups/presentation/screens/contact_picker_wired.dart';
import 'package:flutter_app/features/groups/presentation/screens/create_group_picker_wired.dart';
import 'package:flutter_app/features/identity/application/generate_identity_use_case.dart';
import 'package:flutter_app/features/identity/application/restore_identity_use_case.dart';
import 'package:flutter_app/features/identity/application/linked_secondary_setup_use_case.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/identity/data/repositories/identity_repository_impl.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

import '_support/invite_reliability_runner_contract.dart';
import '_support/group_multi_party_verdict_handshake.dart';
import '_support/canonical_runtime_device_test_lease.dart';
import '../test/shared/fakes/fake_notification_service.dart';
import '../test/shared/fakes/in_memory_inbox_staging_repository.dart';
import '../test/shared/fakes/in_memory_pending_group_invite_repository.dart';
import '../test/shared/helpers/durable_group_exit_driver.dart';

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
const configuredPlan362FixtureIdentitySha256 = String.fromEnvironment(
  'PLAN362_FIXTURE_IDENTITY_SHA256',
  defaultValue: '',
);

/// The legacy default branch name. Named so the terminal-unknown guard below
/// can compare against it explicitly rather than falling through to it.
const String _legacySameUserScenario = 'same_user';

const configuredScenario = String.fromEnvironment(
  'MD004_SCENARIO',
  defaultValue: _legacySameUserScenario,
);
const configuredMode = String.fromEnvironment(
  'MD004_MODE',
  defaultValue: 'baseline',
);
const configuredB1bPlan365GroupMedia = bool.fromEnvironment(
  'B1B_ENABLE_PLAN365_GROUP_MEDIA',
  defaultValue: false,
);
const configuredB1bRequireHostCapture = bool.fromEnvironment(
  'B1B_REQUIRE_HOST_CAPTURE',
  defaultValue: false,
);
const configuredKeyRotationGracePeriodMs = int.fromEnvironment(
  'MKNOON_KEY_ROTATION_GRACE_PERIOD_MS',
  defaultValue: 0,
);

Duration? configuredKeyRotationGracePeriod() {
  if (configuredKeyRotationGracePeriodMs <= 0) return null;
  return Duration(milliseconds: configuredKeyRotationGracePeriodMs);
}

String? _runtimeSharedDirOverride;

void setGroupMultiDeviceRuntimeSharedDir(String? sharedDir) {
  final normalized = sharedDir?.trim();
  _runtimeSharedDirOverride = normalized == null || normalized.isEmpty
      ? null
      : normalized;
}

String groupMultiDeviceRuntimeSharedDir() =>
    _runtimeSharedDirOverride ?? configuredSharedDir;

String sharedPath(String name) => '${groupMultiDeviceRuntimeSharedDir()}/$name';

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
  Directory(groupMultiDeviceRuntimeSharedDir()).createSync(recursive: true);
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
  // 228 (TC-228-13H): this harness instantiates the REAL media repository,
  // so it opens at the CURRENT production schema through the SHARED
  // registry — never a hand-maintained historical migration list that can
  // silently drift from main.dart.
  return openEncryptedDatabase(
    secureKeyStore: secureKeyStore,
    dbName: dbName,
    version: currentIdentityDatabaseVersion,
    onCreate: runProductionOnCreate,
    onUpgrade: runProductionOnUpgrade,
  );
}

class GroupMultiDeviceTestStack {
  final sqlcipher.Database db;
  final String dbName;
  final SecureKeyStore secureKeyStore;
  final GoBridgeClient bridge;
  final P2PServiceImpl p2pService;
  final IdentityRepositoryImpl identityRepo;
  final ContactRepositoryImpl contactRepo;
  final GroupRepositoryImpl groupRepo;
  final GroupMessageRepositoryImpl groupMsgRepo;
  final GroupInviteDeliveryAttemptRepositoryImpl groupInviteDeliveryAttemptRepo;
  final MessageRepositoryImpl messageRepo;
  final MediaAttachmentRepositoryImpl mediaAttachmentRepo;
  final ReactionRepositoryImpl reactionRepo;
  final GroupReactionReplayOutboxRepositoryImpl reactionReplayOutboxRepo;
  final GroupExitIntentRepository groupExitIntentRepo;
  final GroupPendingBroadcastRepository groupPendingBroadcastRepo;
  final DurableGroupExitDriver durableGroupExitDriver;
  final IncomingMessageRouter messageRouter;
  final ChatMessageListener chatMessageListener;
  final DeliveryReceiptListener deliveryReceiptListener;
  final MediaFileManager mediaFileManager;
  final List<String> deliveryReceiptTargets;
  final List<Map<String, String>> mediaFanoutEnvelopeBindings;
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
    required this.secureKeyStore,
    required this.bridge,
    required this.p2pService,
    required this.identityRepo,
    required this.contactRepo,
    required this.groupRepo,
    required this.groupMsgRepo,
    required this.groupInviteDeliveryAttemptRepo,
    required this.messageRepo,
    required this.mediaAttachmentRepo,
    required this.reactionRepo,
    required this.reactionReplayOutboxRepo,
    required this.groupExitIntentRepo,
    required this.groupPendingBroadcastRepo,
    required this.durableGroupExitDriver,
    required this.messageRouter,
    required this.chatMessageListener,
    required this.deliveryReceiptListener,
    required this.mediaFileManager,
    required this.deliveryReceiptTargets,
    required this.mediaFanoutEnvelopeBindings,
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

  int get groupLeaveCommandCount {
    final currentBridge = bridge;
    if (currentBridge is! RecordingGoBridgeClient) {
      throw StateError('Exact group:leave command recording is unavailable.');
    }
    return currentBridge.groupLeaveCommandCount;
  }

  Future<void> teardown({bool deleteStorage = true}) async {
    chatMessageListener.dispose();
    deliveryReceiptListener.dispose();
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
    if (deleteStorage) {
      await deleteTestDatabase(dbName);
      await deleteTestSecureStore(dbName);
    }
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

  int commandCount(String command) {
    var count = 0;
    for (final message in sentMessages) {
      try {
        final decoded = jsonDecode(message);
        if (decoded is Map && decoded['cmd'] == command) count++;
      } catch (_) {
        // Non-command bridge payloads are irrelevant to this exact count.
      }
    }
    return count;
  }

  int get groupLeaveCommandCount => commandCount('group:leave');
}

/// Closed observations from only one owner invocation; raw exchanges stay local.
Map<String, Object> summarizeGroupMediaDownloadObservation({
  required List<String> sentMessages,
  required List<Map<String, String>> bridgeExchanges,
  required int sentStart,
  required int exchangeStart,
}) {
  Map<String, dynamic>? decode(String? value) {
    if (value == null) return null;
    try {
      final decoded = jsonDecode(value);
      return decoded is Map<String, dynamic> ? decoded : null;
    } on FormatException {
      return null;
    }
  }

  const errorCodes = <String>{
    'MEDIA_CUSTODY_ADMISSION_DISABLED',
    'MEDIA_CUSTODY_FULL',
    'MEDIA_CUSTODY_UNSUPPORTED',
    'MEDIA_CUSTODY_IDENTITY_CONFLICT',
    'MEDIA_CUSTODY_INELIGIBLE',
    'MEDIA_CUSTODY_NOT_AUTHORIZED',
    'MEDIA_CUSTODY_HASH_MISMATCH',
    'MEDIA_CUSTODY_ALREADY_ACKED',
    'MEDIA_CUSTODY_CLEANUP_PENDING',
    'MEDIA_CUSTODY_STORAGE_ERROR',
    'MEDIA_CUSTODY_NOT_FOUND',
    'MEDIA_CUSTODY_COMMIT_INDETERMINATE',
    'DECRYPT_AUTH_ERROR',
    'DECRYPT_METADATA_ERROR',
    'DECRYPT_IO_ERROR',
    'DECRYPT_ERROR',
    'INVALID_INPUT',
    'INTERNAL_ERROR',
  };
  final result = <String, Object>{};
  for (final (command, label) in const <(String, String)>[
    ('media:download', 'download'),
    ('blob:decrypt', 'decrypt'),
    ('media:delete', 'ack'),
  ]) {
    final requests = sentMessages
        .skip(sentStart)
        .where((raw) => decode(raw)?['cmd'] == command);
    final exchanges = bridgeExchanges
        .skip(exchangeStart)
        .where((item) => decode(item['request'])?['cmd'] == command)
        .take(2)
        .toList(growable: false);
    final requestCount = requests.take(2).length;
    result['${label}Requests'] = requestCount;
    result['${label}Responses'] = exchanges.length;
    final exact = requestCount == 1 && exchanges.length == 1
        ? exchanges.single
        : null;
    final request = decode(exact?['request']);
    final payload = request?['payload'];
    final response = decode(exact?['response']);
    final ok = response?['ok'] == true;
    result['${label}Ok'] = ok;
    final code = response?['errorCode'];
    result['${label}ErrorCode'] = exchanges.isEmpty
        ? 'unobserved'
        : exchanges.length > 1 || requestCount != 1
        ? 'ambiguous'
        : response == null ||
              (response['ok'] != true && response['ok'] != false)
        ? 'malformed'
        : ok
        ? 'none'
        : code is String && errorCodes.contains(code)
        ? code
        : 'unknown';
    if (command == 'media:download') {
      final relay = response?['custodyRelayPeerId'];
      result['receiptMatchesRequest'] =
          ok &&
          payload is Map &&
          const <String>[
            'id',
            'custodyKind',
            'custodyContract',
            'contentHash',
            'mime',
          ].every(
            (key) =>
                payload[key] is String &&
                (payload[key] as String).isNotEmpty &&
                response?[key] == payload[key],
          ) &&
          const <String>['size', 'expiresAtMs'].every(
            (key) =>
                payload[key] is int &&
                (payload[key] as int) > 0 &&
                response?[key] == payload[key],
          ) &&
          relay is String &&
          relay.trim().isNotEmpty &&
          relay == relay.trim();
    } else if (command == 'blob:decrypt') {
      final filePath = payload is Map ? payload['filePath'] : null;
      result['decryptPathMatchesRequest'] =
          ok &&
          filePath is String &&
          filePath.isNotEmpty &&
          response?['decryptedPath'] == '$filePath.dec';
    }
  }
  return result;
}

/// Android f1b568bca (canonical-runtime ownership): MainActivity no longer
/// constructs the native GoBridge eagerly. The `com.mknoon/go_bridge`
/// Method/EventChannels are only registered once the Dart side acquires the
/// canonical-runtime lease and calls attachRuntime — production bootstrap does
/// this during M1. Without it, every bridge call fails MISSING_PLUGIN
/// ("Native bridge method ... is not available"), which
/// `generateNewIdentity` collapses into GenerateIdentityResult.coreLibError
/// and setup dies ~1s in. iOS still registers GoBridge eagerly in
/// AppDelegate, so this is Android-only.
///
/// The broker re-returns the current token only for an identical
/// (ownerId, binding, role) triple, so repeated setups in one process must
/// use the same fixed binding — and an entrypoint that already owns the lease
/// under a DIFFERENT binding is joined, never acquired over.
Future<void> ensureCanonicalRuntimeAttachedForTest() async {
  if (!Platform.isAndroid) return;
  const binding =
      'v1:0000000000000000000000000000000000000000000000000000000000000000';
  final gateway = MethodChannelCanonicalRuntimeLeaseGateway();
  // JOIN an existing owner rather than acquiring over it. Entrypoints reach
  // this function on two different kinds of path: some already hold the
  // process-wide writable lease through a `CanonicalRuntimeDeviceTestLease`
  // (this file's own `main()`, `benchmark_harness.dart` under
  // BENCHMARK=GROUP_PUBLISH), and some hold nothing. The broker re-returns a
  // live token only for an identical (ownerId, binding, role) triple, so on
  // the first kind an unconditional acquire under the fixed binding above is
  // rejected with `lease_unavailable` — and the gateway does not catch that
  // PlatformException, so it kills setUpAll before any bridge call.
  final existing = await gateway.status();
  final alreadyOwned = existing.state == CanonicalRuntimeLeaseState.active;
  if (!alreadyOwned) {
    final snapshot = await gateway.acquire(binding);
    if (snapshot.state != CanonicalRuntimeLeaseState.active) {
      throw StateError(
        'canonical-runtime test lease acquire left state ${snapshot.state}',
      );
    }
  }
  final attached = await gateway.attachRuntime();
  if (!attached) {
    throw StateError(
      'canonical-runtime attach failed after lease acquire — native GoBridge '
      'did not construct; go_bridge channel calls would all MISSING_PLUGIN',
    );
  }
  print(
    '[STACK-DIAG] canonical runtime lease '
    '${alreadyOwned ? 'joined' : 'acquired'} + Go runtime attached',
  );
}

/// The device stack and host SQLite regression share this exact wiring.
GroupReactionReplayOutboxRepositoryImpl
createGroupMultiDeviceReactionReplayOutbox(Database db) {
  return GroupReactionReplayOutboxRepositoryImpl(
    dbUpsertGroupReactionReplayOutboxEntry: (row) =>
        dbUpsertGroupReactionReplayOutboxEntry(db, row),
    dbAttachGroupReactionReplayOutboxPayload:
        ({
          required reactionId,
          required inboxRetryPayload,
          required updatedAt,
        }) => dbAttachGroupReactionReplayOutboxPayload(
          db,
          reactionId: reactionId,
          inboxRetryPayload: inboxRetryPayload,
          updatedAt: updatedAt,
        ),
    dbLoadGroupReactionReplayOutboxEntry: (reactionId) =>
        dbLoadGroupReactionReplayOutboxEntry(db, reactionId),
    dbLoadLatestGroupReactionReplayOutboxEntryForTarget:
        ({
          required String groupId,
          required String messageId,
          required String senderPeerId,
        }) => dbLoadLatestGroupReactionReplayOutboxEntryForTarget(
          db,
          groupId: groupId,
          messageId: messageId,
          senderPeerId: senderPeerId,
        ),
    dbLoadRetryableGroupReactionReplayOutboxEntries:
        ({int limit = 20, bool strictContentOnly = false, int offset = 0}) =>
            dbLoadRetryableGroupReactionReplayOutboxEntries(
              db,
              limit: limit,
              strictContentOnly: strictContentOnly,
              offset: offset,
            ),
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
    dbUpdateGroupReactionReplayOutboxEntryStatusIfExact:
        ({
          required expected,
          required deliveryStatus,
          lastError,
          required updatedAt,
        }) => dbUpdateGroupReactionReplayOutboxEntryStatusIfExact(
          db,
          expected: expected,
          deliveryStatus: deliveryStatus,
          lastError: lastError,
          updatedAt: updatedAt,
        ),
    dbReplaceGroupReactionReplayOutboxPayloadIfExact:
        ({required expected, required replacement, required updatedAt}) =>
            dbReplaceGroupReactionReplayOutboxPayloadIfExact(
              db,
              expected: expected,
              replacement: replacement,
              updatedAt: updatedAt,
            ),
    dbCompleteGroupReactionContentIfExact:
        ({
          required expected,
          required reactionRow,
          required action,
          required transitionId,
          required sourcePeerId,
          required sourceEventId,
          required sourceTimestamp,
          required eventPayload,
          required updatedAt,
        }) => dbCompleteGroupReactionContentIfExact(
          db,
          expected: expected,
          reactionRow: reactionRow,
          action: action,
          transitionId: transitionId,
          sourcePeerId: sourcePeerId,
          sourceEventId: sourceEventId,
          sourceTimestamp: sourceTimestamp,
          eventPayload: eventPayload,
          updatedAt: updatedAt,
        ),
    dbStageAndCompleteLocalGroupReactionContentFn:
        ({
          required expected,
          required reactionRow,
          required action,
          required transitionId,
          required sourcePeerId,
          required sourceEventId,
          required sourceTimestamp,
          required eventPayload,
        }) => dbStageAndCompleteLocalGroupReactionContent(
          db,
          expected: expected,
          reactionRow: reactionRow,
          action: action,
          transitionId: transitionId,
          sourcePeerId: sourcePeerId,
          sourceEventId: sourceEventId,
          sourceTimestamp: sourceTimestamp,
          eventPayload: eventPayload,
        ),
    dbStagePreparedLocalGroupReactionContentFn:
        ({
          required expected,
          required sourcePeerId,
          required sourceEventId,
          required sourceTimestamp,
          required preparedEventPayload,
        }) => dbStagePreparedLocalGroupReactionContent(
          db,
          expected: expected,
          sourcePeerId: sourcePeerId,
          sourceEventId: sourceEventId,
          sourceTimestamp: sourceTimestamp,
          preparedEventPayload: preparedEventPayload,
        ),
    dbTerminalizePreparedLocalGroupReactionIfExactFn:
        ({
          required expected,
          required preparedEventPayload,
          required terminalSourcePeerId,
          required terminalSourceEventId,
          required terminalSourceTimestamp,
          required terminalEventPayload,
        }) => dbTerminalizePreparedLocalGroupReactionIfExact(
          db,
          expected: expected,
          preparedEventPayload: preparedEventPayload,
          terminalSourcePeerId: terminalSourcePeerId,
          terminalSourceEventId: terminalSourceEventId,
          terminalSourceTimestamp: terminalSourceTimestamp,
          terminalEventPayload: terminalEventPayload,
        ),
    dbHasExactPreparedLocalGroupReactionFn:
        ({required expected, required eventPayload}) =>
            dbHasExactPreparedLocalGroupReaction(
              db,
              expected: expected,
              eventPayload: eventPayload,
            ),
    dbDeleteGroupReactionReplayOutboxEntry: (reactionId) =>
        dbDeleteGroupReactionReplayOutboxEntry(db, reactionId),
  );
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
  bool setupAsLinkedSecondary = false,
  bool restrictedLinkedRuntime = false,
  bool startGroupTopicsOnReuse = true,
  bool onJoinMetadataResyncEnabled = false,
  Future<OutgoingOrdinaryMutationResult> Function({
    required String messageId,
    required OutgoingOrdinaryMutationOutcome outcome,
    required List<MediaAttachment> committedMedia,
  })?
  publishOutgoingOrdinaryMutation,
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
  print('[STACK-DIAG] db opened; wiring repos');

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
  late final MediaAttachmentRepositoryImpl mediaAttachmentRepo;
  final messageRepo = MessageRepositoryImpl(
    dbInsertMessage: (row) => dbInsertMessage(db, row),
    dbLoadMessagesForContact: (contactPeerId) =>
        dbLoadMessagesForContact(db, contactPeerId),
    dbLoadLatestMessageForContact: (contactPeerId) =>
        dbLoadLatestMessageForContact(db, contactPeerId),
    dbUpdateMessageStatus: (id, status) =>
        dbUpdateMessageStatus(db, id, status),
    dbLoadMessage: (id) => dbLoadMessage(db, id),
    dbExistsMessageByContent: (contactPeerId, senderPeerId, text, timestamp) =>
        dbExistsMessageByContent(
          db,
          contactPeerId,
          senderPeerId,
          text,
          timestamp,
        ),
    dbExistsMessageByDedupKey: (contactPeerId, senderPeerId, dedupKey) =>
        dbExistsMessageByDedupKey(db, contactPeerId, senderPeerId, dedupKey),
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
    dbLoadUnackedOutgoingMessages: ({required olderThan, limit = 50}) =>
        dbLoadUnackedOutgoingMessages(db, olderThan: olderThan, limit: limit),
    dbLoadConversationThreadSummaries: (contactPeerIds) =>
        dbLoadConversationThreadSummaries(db, contactPeerIds),
    dbRecoverStuckSendingMessages: ({required olderThan, limit = 50}) =>
        dbRecoverStuckSendingMessages(db, olderThan: olderThan, limit: limit),
    dbUpdateWireEnvelope: (id, wireEnvelope) =>
        dbUpdateWireEnvelope(db, id, wireEnvelope),
    dbStageOutgoingOrdinaryAttempt:
        ({required expectedRow, required stagedRow, required kind}) =>
            dbStageOutgoingOrdinaryAttempt(
              db,
              expectedRow: expectedRow,
              stagedRow: stagedRow,
              kind: kind,
            ),
    dbStageOutgoingDirectTextInboxCustody:
        ({
          required expectedRow,
          required stagedRow,
          required kind,
          required recipientPeerId,
          required messageId,
          required incarnationId,
          required wireEnvelope,
        }) => dbStageOutgoingDirectTextInboxCustody(
          db,
          expectedRow: expectedRow,
          stagedRow: stagedRow,
          kind: kind,
          recipientPeerId: recipientPeerId,
          messageId: messageId,
          incarnationId: incarnationId,
          wireEnvelope: wireEnvelope,
        ),
    dbReadDirectContactFanoutSnapshot: ({required contactAccountPeerId}) =>
        dbReadDirectContactFanoutSnapshot(
          db,
          contactAccountPeerId: contactAccountPeerId,
        ),
    dbLoadDirectInboxCustodyOutboxRowsForMessageId: ({required messageId}) =>
        dbLoadDirectInboxCustodyOutboxRowsForMessageId(
          db,
          messageId: messageId,
        ),
    dbLoadDirectReactionInboxCustodyOutboxRowsForEventId:
        ({required eventId}) =>
            dbLoadDirectReactionInboxCustodyOutboxRowsForEventId(
              db,
              eventId: eventId,
            ),
    dbStageOutgoingDirectTextFanoutInboxCustody:
        ({
          required stagedRow,
          required messageId,
          required contactAccountPeerId,
          required senderTransportPeerId,
          required expectedSnapshot,
          required candidates,
        }) => dbStageOutgoingDirectTextFanoutInboxCustody(
          db,
          stagedRow: stagedRow,
          messageId: messageId,
          contactAccountPeerId: contactAccountPeerId,
          senderTransportPeerId: senderTransportPeerId,
          expectedSnapshot: expectedSnapshot,
          candidates: candidates,
        ),
    dbStageOutgoingDirectTextMutationFanoutInboxCustody:
        ({
          required expectedRow,
          required stagedRow,
          required kind,
          required eventId,
          required parentMessageId,
          required contactAccountPeerId,
          required senderTransportPeerId,
          required expectedSnapshot,
          required candidates,
        }) => dbStageOutgoingDirectTextMutationFanoutInboxCustody(
          db,
          expectedRow: expectedRow,
          stagedRow: stagedRow,
          kind: kind,
          eventId: eventId,
          parentMessageId: parentMessageId,
          contactAccountPeerId: contactAccountPeerId,
          senderTransportPeerId: senderTransportPeerId,
          expectedSnapshot: expectedSnapshot,
          candidates: candidates,
        ),
    dbApplyIncomingOrdinaryTextMutationWithAuthority:
        ({
          required incomingRow,
          required kind,
          required authenticatedTransportPeerId,
        }) => dbApplyIncomingOrdinaryTextMutation(
          db,
          incomingRow: incomingRow,
          kind: kind,
          authenticatedTransportPeerId: authenticatedTransportPeerId,
        ),
    dbApplyIncomingDirectMessageDeletionWithAuthority:
        ({
          required messageId,
          required senderPeerId,
          required deletedAt,
          required transport,
          required createdAt,
          required authenticatedTransportPeerId,
        }) => dbApplyIncomingDirectMessageDeletion(
          db,
          messageId: messageId,
          senderPeerId: senderPeerId,
          deletedAt: deletedAt,
          transport: transport,
          createdAt: createdAt,
          authenticatedTransportPeerId: authenticatedTransportPeerId,
        ),
    dbSettleOutgoingOrdinaryTransportWithFanoutAuthority:
        ({
          required messageId,
          required expectedContactPeerId,
          required expectedEnvelope,
          required status,
          required transport,
          required relayExpiresAt,
          required mode,
          required isDeleteTombstone,
          expectedDirectEventFanoutGenerationId,
          authenticatedTransportPeerId,
        }) => isDeleteTombstone
        ? dbSettleOutgoingOrdinaryDeleteTombstone(
            db,
            messageId: messageId,
            expectedContactPeerId: expectedContactPeerId,
            expectedEnvelope: expectedEnvelope,
            status: status,
            transport: transport,
            relayExpiresAt: relayExpiresAt,
            mode: mode,
            expectedDirectEventFanoutGenerationId:
                expectedDirectEventFanoutGenerationId,
            authenticatedTransportPeerId: authenticatedTransportPeerId,
          )
        : dbSettleOutgoingOrdinaryTransport(
            db,
            messageId: messageId,
            expectedContactPeerId: expectedContactPeerId,
            expectedEnvelope: expectedEnvelope,
            status: status,
            transport: transport,
            relayExpiresAt: relayExpiresAt,
            mode: mode,
            expectedDirectEventFanoutGenerationId:
                expectedDirectEventFanoutGenerationId,
            authenticatedTransportPeerId: authenticatedTransportPeerId,
          ),
    dbLoadDirectInboxCustodyOutbox: ({limit = 50}) =>
        dbLoadDirectInboxCustodyOutbox(db, limit: limit),
    dbLoadDirectInboxCustodyOutboxForMessage:
        ({required recipientPeerId, required messageId}) =>
            dbLoadDirectInboxCustodyOutboxForMessage(
              db,
              recipientPeerId: recipientPeerId,
              messageId: messageId,
            ),
    dbLoadDirectInboxCustodyOutboxOwnerForMessageId: ({required messageId}) =>
        dbLoadDirectInboxCustodyOutboxOwnerForMessageId(
          db,
          messageId: messageId,
        ),
    dbRecordDirectInboxCustodyFailureIfExact:
        ({
          required recipientPeerId,
          required messageId,
          required expectedIncarnationId,
          required expectedWireEnvelope,
          required errorCode,
          required attemptedAt,
        }) => dbRecordDirectInboxCustodyFailureIfExact(
          db,
          recipientPeerId: recipientPeerId,
          messageId: messageId,
          expectedIncarnationId: expectedIncarnationId,
          expectedWireEnvelope: expectedWireEnvelope,
          errorCode: errorCode,
          attemptedAt: attemptedAt,
        ),
    dbCompleteAcceptedDirectInboxCustodyIfExact:
        ({
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
    dbSettleOutgoingOrdinaryDeleteTombstone:
        ({
          required messageId,
          required expectedContactPeerId,
          required expectedEnvelope,
          required status,
          required transport,
          required relayExpiresAt,
          required mode,
        }) => dbSettleOutgoingOrdinaryDeleteTombstone(
          db,
          messageId: messageId,
          expectedContactPeerId: expectedContactPeerId,
          expectedEnvelope: expectedEnvelope,
          status: status,
          transport: transport,
          relayExpiresAt: relayExpiresAt,
          mode: mode,
        ),
    dbInvalidateOutgoingOrdinaryEnvelope:
        ({
          required messageId,
          required expectedContactPeerId,
          required expectedEnvelope,
        }) => dbInvalidateOutgoingOrdinaryEnvelope(
          db,
          messageId: messageId,
          expectedContactPeerId: expectedContactPeerId,
          expectedEnvelope: expectedEnvelope,
        ),
    dbQuarantineUnsafeLegacyOutgoingEnvelope:
        ({
          required messageId,
          required expectedContactPeerId,
          required expectedEnvelope,
          required isDeleteTombstone,
        }) => dbQuarantineUnsafeLegacyOutgoingEnvelope(
          db,
          messageId: messageId,
          expectedContactPeerId: expectedContactPeerId,
          expectedEnvelope: expectedEnvelope,
          isDeleteTombstone: isDeleteTombstone,
        ),
    loadOutgoingOrdinaryMedia: (messageId) => mediaAttachmentRepo
        .getAttachmentsForMessage(messageId, owner: MediaOwnerLane.direct),
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
    dbLoadAllGroupKeys: (groupId) => dbLoadAllGroupKeys(db, groupId),
    dbDeleteGroupKeysBeforeGeneration: (groupId, minKeyGenerationToKeep) =>
        dbDeleteGroupKeysBeforeGeneration(db, groupId, minKeyGenerationToKeep),
    dbUpsertPendingGroupKeyRotation: (row) =>
        dbUpsertPendingGroupKeyRotation(db, row),
    dbLoadPendingGroupKeyRotation: (groupId) =>
        dbLoadPendingGroupKeyRotation(db, groupId),
    dbDeletePendingGroupKeyRotation: (groupId, keyGeneration) =>
        dbDeletePendingGroupKeyRotation(db, groupId, keyGeneration),
    dbDeletePendingGroupKeyRotations: (groupId) =>
        dbDeletePendingGroupKeyRotations(db, groupId),
    dbUpsertPendingSiblingDevice: (row) =>
        dbUpsertPendingSiblingDevice(db, row),
    dbLoadPendingSiblingDevicesForGroup: (groupId) =>
        dbLoadPendingSiblingDevicesForGroup(db, groupId),
    dbLoadPendingSiblingDevice: (groupId, memberPeerId, deviceId) =>
        dbLoadPendingSiblingDevice(db, groupId, memberPeerId, deviceId),
    dbDeletePendingSiblingDevice: (groupId, memberPeerId, deviceId) =>
        dbDeletePendingSiblingDevice(db, groupId, memberPeerId, deviceId),
    dbCommitLinkedGroupBootstrapAuthoringFn:
        ({
          required expectedGroup,
          required expectedMembers,
          required expectedSelfMember,
          required expectedLatestKeyGeneration,
          required expectedLatestKeyCreatedAt,
          required updatedSelfMember,
          required pendingDevice,
          required pendingBroadcast,
          required authorityGenesisSourcePeerId,
          required authorityGenesisSourceEventId,
          required authorityGenesisSourceTimestamp,
          required authorityGenesisPayload,
        }) => dbCommitLinkedGroupBootstrapAuthoring(
          db,
          expectedGroup: expectedGroup,
          expectedMembers: expectedMembers,
          expectedSelfMember: expectedSelfMember,
          expectedLatestKeyGeneration: expectedLatestKeyGeneration,
          expectedLatestKeyCreatedAt: expectedLatestKeyCreatedAt,
          updatedSelfMember: updatedSelfMember,
          pendingDevice: pendingDevice,
          pendingBroadcast: pendingBroadcast,
          authorityGenesisSourcePeerId: authorityGenesisSourcePeerId,
          authorityGenesisSourceEventId: authorityGenesisSourceEventId,
          authorityGenesisSourceTimestamp: authorityGenesisSourceTimestamp,
          authorityGenesisPayload: authorityGenesisPayload,
        ),
    dbCompleteLinkedGroupBootstrapCustodyFn:
        ({required expectedDevice, required expectedBroadcast}) =>
            dbCompleteLinkedGroupBootstrapCustody(
              db,
              expectedDevice: expectedDevice,
              expectedBroadcast: expectedBroadcast,
            ),
    dbCommitLinkedGroupBootstrapMaterializationFn:
        ({
          required groupRow,
          required memberRows,
          required keyRow,
          required authorityGenesisSourcePeerId,
          required authorityGenesisSourceEventId,
          required authorityGenesisSourceTimestamp,
          required authorityGenesisPayload,
        }) => dbCommitLinkedGroupBootstrapMaterialization(
          db,
          groupRow: groupRow,
          memberRows: memberRows,
          keyRow: keyRow,
          authorityGenesisSourcePeerId: authorityGenesisSourcePeerId,
          authorityGenesisSourceEventId: authorityGenesisSourceEventId,
          authorityGenesisSourceTimestamp: authorityGenesisSourceTimestamp,
          authorityGenesisPayload: authorityGenesisPayload,
        ),
    dbHasLinkedGroupBootstrapIntentFn:
        ({required groupId, required transportPeerId}) =>
            dbHasLinkedGroupBootstrapIntent(
              db,
              groupId: groupId,
              transportPeerId: transportPeerId,
            ),
    groupKeyStore: secureKeyStore,
    dbCommitProtectedDissolvedGroup:
        ({
          required groupRow,
          required expectedBroadcastRows,
          required authorityCompleteSourcePeerId,
          required authorityCompleteSourceEventId,
          required authorityCompleteSourceTimestamp,
          required authorityCompletePayload,
        }) => dbCommitProtectedDissolvedGroup(
          db,
          groupRow: groupRow,
          expectedBroadcastRows: expectedBroadcastRows,
          authorityCompleteSourcePeerId: authorityCompleteSourcePeerId,
          authorityCompleteSourceEventId: authorityCompleteSourceEventId,
          authorityCompleteSourceTimestamp: authorityCompleteSourceTimestamp,
          authorityCompletePayload: authorityCompletePayload,
        ),
    dbHasGroupExitCleanupPending: (groupId) async {
      final row = await dbLoadGroupExitIntentForGroup(db, groupId);
      return row?['state'] == 'cleanup_pending';
    },
  );
  final groupMediaKeyAccess = GroupMediaKeyAccess(
    secureKeyStore: secureKeyStore,
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
      dbLoadGroupMessagesWithFailedInboxStore:
          ({limit = 20, strictContentOnly = false, offset = 0}) =>
              dbLoadGroupMessagesWithFailedInboxStore(
                executor,
                limit: limit,
                strictContentOnly: strictContentOnly,
                offset: offset,
              ),
      dbUpdateGroupMessageInboxStoredFn: (id, {required stored}) =>
          dbUpdateGroupMessageInboxStored(executor, id, stored: stored),
      dbUpdateGroupMessageInboxRetryPayloadFn: (id, payload) =>
          dbUpdateGroupMessageInboxRetryPayload(executor, id, payload),
      dbUpdateGroupMessageWireEnvelopeFn: (id, envelope) =>
          dbUpdateGroupMessageWireEnvelope(executor, id, envelope),
      dbCompleteGroupContentInboxStoreRetryIfExactFn:
          ({
            required expected,
            required sourcePeerId,
            required sourceEventId,
            required sourceTimestamp,
            required eventPayload,
          }) => dbCompleteGroupContentInboxStoreRetryIfExact(
            db,
            expected: expected,
            sourcePeerId: sourcePeerId,
            sourceEventId: sourceEventId,
            sourceTimestamp: sourceTimestamp,
            eventPayload: eventPayload,
            mediaKeyAccess: groupMediaKeyAccess,
          ),
      dbStageAndCompleteLocalGroupContentMessageFn: identical(executor, db)
          ? ({
              required expected,
              required sourcePeerId,
              required sourceEventId,
              required sourceTimestamp,
              required eventPayload,
            }) => dbStageAndCompleteLocalGroupContentMessage(
              db,
              expected: expected,
              sourcePeerId: sourcePeerId,
              sourceEventId: sourceEventId,
              sourceTimestamp: sourceTimestamp,
              eventPayload: eventPayload,
              mediaKeyAccess: groupMediaKeyAccess,
            )
          : null,
      dbStagePreparedLocalGroupContentMessageFn: identical(executor, db)
          ? ({
              required expected,
              required sourcePeerId,
              required sourceEventId,
              required sourceTimestamp,
              required preparedEventPayload,
            }) => dbStagePreparedLocalGroupContentMessage(
              db,
              expected: expected,
              sourcePeerId: sourcePeerId,
              sourceEventId: sourceEventId,
              sourceTimestamp: sourceTimestamp,
              preparedEventPayload: preparedEventPayload,
              mediaKeyAccess: groupMediaKeyAccess,
            )
          : null,
      dbTerminalizePreparedLocalGroupContentMessageIfExactFn:
          identical(executor, db)
          ? ({
              required expected,
              required preparedEventPayload,
              required terminalSourcePeerId,
              required terminalSourceEventId,
              required terminalSourceTimestamp,
              required terminalEventPayload,
            }) => dbTerminalizePreparedLocalGroupContentMessageIfExact(
              db,
              expected: expected,
              preparedEventPayload: preparedEventPayload,
              terminalSourcePeerId: terminalSourcePeerId,
              terminalSourceEventId: terminalSourceEventId,
              terminalSourceTimestamp: terminalSourceTimestamp,
              terminalEventPayload: terminalEventPayload,
              mediaKeyAccess: groupMediaKeyAccess,
            )
          : null,
      dbHasExactPreparedLocalGroupContentMessageFn:
          ({required expected, required eventPayload}) =>
              dbHasExactPreparedLocalGroupContentMessage(
                executor,
                expected: expected,
                eventPayload: eventPayload,
                mediaKeyAccess: executor is Database
                    ? groupMediaKeyAccess
                    : null,
              ),
      dbIsStrictGroupReactionTargetEligibleFn: (expected) =>
          dbIsStrictGroupReactionTargetEligible(executor, expected),
      dbReplaceGroupInboxRetryPayloadIfExactFn: (expected, replacement) =>
          dbReplaceGroupInboxRetryPayloadIfExact(
            db,
            expected,
            replacement,
            mediaKeyAccess: groupMediaKeyAccess,
          ),
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
  final groupExitIntentRepo = GroupExitIntentRepositoryImpl(
    dbLoadForGroup: (groupId) => dbLoadGroupExitIntentForGroup(db, groupId),
    dbLoadAll: () => dbLoadAllGroupExitIntents(db),
    dbEnqueue: (row) => dbEnqueueGroupExitIntent(db, row),
    dbCancelQueued: ({required expected, required updatedAt}) =>
        dbCancelQueuedGroupExitIntent(
          db,
          expected: expected,
          updatedAt: updatedAt,
        ),
    dbPrepareLeaveNotice:
        ({
          required expected,
          required timelineRow,
          required pendingBroadcastRow,
          required updatedAt,
        }) => dbPrepareGroupExitLeaveNotice(
          db,
          expected: expected,
          timelineRow: timelineRow,
          pendingBroadcastRow: pendingBroadcastRow,
          updatedAt: updatedAt,
        ),
    dbCompleteLeaveNoticeAttempt:
        ({
          required expected,
          required pendingBroadcastRow,
          required completionCode,
          required updatedAt,
        }) => dbCompleteGroupExitLeaveNotice(
          db,
          expected: expected,
          pendingBroadcastRow: pendingBroadcastRow,
          completionCode: completionCode,
          updatedAt: updatedAt,
        ),
    dbAdvance:
        ({
          required expected,
          required nextState,
          required updatedAt,
          lastErrorCode,
        }) => dbAdvanceGroupExitIntent(
          db,
          expected: expected,
          nextState: nextState,
          updatedAt: updatedAt,
          lastErrorCode: lastErrorCode,
        ),
    dbCleanupOrRetire: ({required expected, required updatedAt}) =>
        dbCleanupOrRetireGroupExitIntent(
          db,
          expected: expected,
          updatedAt: updatedAt,
        ),
    dbRetireExact: (expected) => dbRetireExactGroupExitIntent(db, expected),
    dbTerminalizeForGroup: (groupId) =>
        dbTerminalizeGroupExitIntentForGroup(db, groupId),
  );
  final groupPendingBroadcastRepo = GroupPendingBroadcastRepositoryImpl(
    dbInsert: (row) => dbInsertPendingGroupBroadcast(db, row),
    dbInsertProtectedBatch:
        ({
          required groupId,
          required rows,
          required authorityPreparedSourcePeerId,
          required authorityPreparedSourceEventId,
          required authorityPreparedSourceTimestamp,
          required authorityPreparedPayload,
        }) => dbInsertPendingGroupBroadcastsWithAuthorityPreparedAtomically(
          db,
          groupId: groupId,
          rows: rows,
          authorityPreparedSourcePeerId: authorityPreparedSourcePeerId,
          authorityPreparedSourceEventId: authorityPreparedSourceEventId,
          authorityPreparedSourceTimestamp: authorityPreparedSourceTimestamp,
          authorityPreparedPayload: authorityPreparedPayload,
        ),
    dbLoadForGroup: (groupId) =>
        dbLoadPendingGroupBroadcastsForGroup(db, groupId),
    dbLoadAll: () => dbLoadAllPendingGroupBroadcasts(db),
    dbCountForGroup: (groupId) =>
        dbCountPendingGroupBroadcastsForGroup(db, groupId),
    dbDelete: (id) => dbDeletePendingGroupBroadcast(db, id),
    dbDeleteIfExact: (expected) =>
        dbDeletePendingGroupBroadcastIfExact(db, expected),
    dbDeleteForGroup: (groupId) =>
        dbDeletePendingGroupBroadcastsForGroup(db, groupId),
    dbRemoveRecipientIfExact:
        ({required expected, required recipientPeerId, required updatedAt}) =>
            dbRemovePendingGroupBroadcastRecipientIfExact(
              db,
              expected: expected,
              recipientPeerId: recipientPeerId,
              updatedAt: updatedAt,
            ),
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
  final mediaFanoutEnvelopeBindings = <Map<String, String>>[];
  mediaAttachmentRepo = MediaAttachmentRepositoryImpl(
    // Keep the production ordinary/private classifier in front of generic
    // pending-row persistence. For this TC-362 ordinary parent it returns
    // `notPrivateParent`, authorizing the incumbent generic insert; omitting
    // the seam would turn a real ordinary v110 preparation into a synthetic
    // private-media refusal in the shared harness only.
    dbInsertOutgoingDirectPrivatePendingAttachmentsIfEligible: (rows) =>
        dbInsertOutgoingDirectPrivatePendingAttachmentsIfEligible(db, rows),
    dbSaveMediaAttachmentPreservingLocalState: (row) =>
        dbSaveMediaAttachmentPreservingLocalState(db, row),
    dbCanApplyGenericMediaAttachmentSave: (row) =>
        dbCanApplyGenericMediaAttachmentSave(db, row),
    dbStageOutgoingOrdinaryAttemptWithMedia:
        ({
          required expectedRow,
          required stagedRow,
          required attachmentRows,
          required kind,
        }) => dbStageOutgoingOrdinaryAttemptWithMedia(
          db,
          expectedRow: expectedRow,
          stagedRow: stagedRow,
          attachmentRows: attachmentRows,
          kind: kind,
        ),
    dbStageOutgoingDirectMediaInboxCustody:
        ({
          required expectedRow,
          required stagedRow,
          required attachmentRows,
          required kind,
          required recipientPeerId,
          required wireEnvelope,
          wireMediaBlobManifestHash,
          wireMediaBlobExpiresAtMs,
        }) => dbStageOutgoingDirectMediaInboxCustody(
          db,
          expectedRow: expectedRow,
          stagedRow: stagedRow,
          attachmentRows: attachmentRows,
          kind: kind,
          recipientPeerId: recipientPeerId,
          wireEnvelope: wireEnvelope,
          wireMediaBlobManifestHash: wireMediaBlobManifestHash,
          wireMediaBlobExpiresAtMs: wireMediaBlobExpiresAtMs,
        ),
    dbStageOutgoingDirectMediaBlobGeneration:
        ({
          required expectedParentRow,
          required expectedAttachmentRows,
          required preparedAttachmentRows,
          required custodyRows,
        }) => dbStageOutgoingDirectMediaBlobGeneration(
          db,
          expectedParentRow: expectedParentRow,
          expectedAttachmentRows: expectedAttachmentRows,
          preparedAttachmentRows: preparedAttachmentRows,
          custodyRows: custodyRows,
        ),
    dbStageFreshOutgoingDirectMediaBlobGeneration:
        ({
          required parentRow,
          required expectedAttachmentRows,
          required preparedAttachmentRows,
          required custodyRows,
          authorizedForwardDedupKey,
        }) => dbStageFreshOutgoingDirectMediaBlobGeneration(
          db,
          parentRow: parentRow,
          expectedAttachmentRows: expectedAttachmentRows,
          preparedAttachmentRows: preparedAttachmentRows,
          custodyRows: custodyRows,
          authorizedForwardDedupKey: authorizedForwardDedupKey,
        ),
    dbReadDirectContactFanoutSnapshotForMedia:
        ({required contactAccountPeerId}) => dbReadDirectContactFanoutSnapshot(
          db,
          contactAccountPeerId: contactAccountPeerId,
        ),
    dbStageOutgoingDirectLinkedMediaBlobFanoutGeneration:
        ({
          required expectedParentRow,
          required expectedAttachmentRows,
          required preparedAttachmentRows,
          required custodyRows,
          required contactAccountPeerId,
          required expectedSnapshot,
          allowFreshParent = false,
          authorizedForwardDedupKey,
        }) => dbStageOutgoingDirectLinkedMediaBlobFanoutGeneration(
          db,
          expectedParentRow: expectedParentRow,
          expectedAttachmentRows: expectedAttachmentRows,
          preparedAttachmentRows: preparedAttachmentRows,
          custodyRows: custodyRows,
          contactAccountPeerId: contactAccountPeerId,
          expectedSnapshot: expectedSnapshot,
          allowFreshParent: allowFreshParent,
          authorizedForwardDedupKey: authorizedForwardDedupKey,
        ),
    dbStageOutgoingDirectMediaFanoutInboxCustody:
        ({
          required expectedRow,
          required stagedRow,
          required attachmentRows,
          required senderTransportPeerId,
          required contactAccountPeerId,
          required authority,
          required expectedSnapshot,
          required targetBindings,
        }) =>
            dbStageOutgoingDirectMediaFanoutInboxCustody(
              db,
              expectedRow: expectedRow,
              stagedRow: stagedRow,
              attachmentRows: attachmentRows,
              senderTransportPeerId: senderTransportPeerId,
              contactAccountPeerId: contactAccountPeerId,
              authority: authority,
              expectedSnapshot: expectedSnapshot,
              targetBindings: targetBindings,
            ).whenComplete(() {
              mediaFanoutEnvelopeBindings
                ..clear()
                ..addAll(
                  targetBindings.map(
                    (binding) => <String, String>{
                      'recipientPeerId': binding.recipientPeerId,
                      'wireEnvelope': binding.wireEnvelope,
                    },
                  ),
                );
            }),
    dbStageFreshOutgoingGroupMediaBlobGeneration:
        ({
          required parentRow,
          required attachmentRows,
          required custodyRows,
          required custodyBlobIdsByAttachmentId,
        }) => dbStageFreshOutgoingGroupMediaBlobGeneration(
          db,
          parentRow: parentRow,
          attachmentRows: attachmentRows,
          custodyRows: custodyRows,
          custodyBlobIdsByAttachmentId: custodyBlobIdsByAttachmentId,
        ),
    dbLoadGroupMediaBlobCustodyForMessage:
        ({required groupId, required messageId}) =>
            dbLoadGroupMediaBlobCustodyForMessage(
              db,
              groupId: groupId,
              messageId: messageId,
            ),
    dbLoadGroupMediaBlobCustodyByStates: ({required states, int limit = 50}) =>
        dbLoadGroupMediaBlobCustodyByStates(db, states: states, limit: limit),
    dbLoadGroupMediaBlobCustodyForTarget:
        ({
          required groupId,
          required attachmentId,
          required custodyBlobId,
          required direction,
          recipientPeerId,
        }) => dbLoadGroupMediaBlobCustodyForTarget(
          db,
          groupId: groupId,
          attachmentId: attachmentId,
          custodyBlobId: custodyBlobId,
          direction: direction,
          recipientPeerId: recipientPeerId,
        ),
    dbTransitionGroupMediaBlobCustodyIfExact:
        ({required expected, required next}) =>
            dbTransitionGroupMediaBlobCustodyIfExact(
              db,
              expected: expected,
              next: next,
            ),
    dbDeleteGroupMediaBlobCleanupPendingIfExact: ({required expected}) =>
        dbDeleteGroupMediaBlobCleanupPendingIfExact(db, expected: expected),
    dbCommitIncomingGroupMediaBlobLocalPath:
        ({
          required expectedAttachmentRow,
          required expectedCustody,
          required localPath,
          required sourceRelayPeerId,
          required updatedAt,
          required nowMs,
        }) => dbCommitIncomingGroupMediaBlobLocalPath(
          db,
          expectedAttachmentRow: expectedAttachmentRow,
          expectedCustody: expectedCustody,
          localPath: localPath,
          sourceRelayPeerId: sourceRelayPeerId,
          updatedAt: updatedAt,
          nowMs: nowMs,
        ),
    dbTerminalizeIncomingGroupMediaBlobForLocalDeletion:
        ({
          required expectedAttachmentRow,
          required expectedCustody,
          required sourceRelayPeerId,
          required updatedAt,
        }) => dbTerminalizeIncomingGroupMediaBlobForLocalDeletion(
          db,
          expectedAttachmentRow: expectedAttachmentRow,
          expectedCustody: expectedCustody,
          sourceRelayPeerId: sourceRelayPeerId,
          updatedAt: updatedAt,
        ),
    dbDeleteIncomingGroupMediaBlobAckPendingIfExact: ({required expected}) =>
        dbDeleteIncomingGroupMediaBlobAckPendingIfExact(db, expected: expected),
    dbDeleteIncomingGroupMediaBlobIfExpired:
        ({required expected, required nowMs}) =>
            dbDeleteIncomingGroupMediaBlobIfExpired(
              db,
              expected: expected,
              nowMs: nowMs,
            ),
    dbCountOtherGroupMediaBlobCustodyRowsReferencingArtifact:
        ({
          required ciphertextRelativePath,
          required contentHash,
          required ciphertextSize,
          required excluding,
        }) => dbCountOtherGroupMediaBlobCustodyRowsReferencingArtifact(
          db,
          ciphertextRelativePath: ciphertextRelativePath,
          contentHash: contentHash,
          ciphertextSize: ciphertextSize,
          excluding: excluding,
        ),
    dbLoadDirectMediaBlobCustodyRowsForAttachment: ({required attachmentId}) =>
        dbLoadDirectMediaBlobCustodyRowsForAttachment(
          db,
          attachmentId: attachmentId,
        ),
    dbLoadDirectMediaBlobCustodyForTarget:
        ({required attachmentId, required direction, recipientPeerId}) =>
            dbLoadDirectMediaBlobCustodyForTarget(
              db,
              attachmentId: attachmentId,
              direction: direction,
              recipientPeerId: recipientPeerId,
            ),
    dbLoadDirectMediaBlobCustodyForMessage: ({required messageId}) =>
        dbLoadDirectMediaBlobCustodyForMessage(db, messageId: messageId),
    dbLoadDirectMediaBlobCustodyByStates: ({required states, int limit = 50}) =>
        dbLoadDirectMediaBlobCustodyByStates(db, states: states, limit: limit),
    dbLoadLinkedDirectMediaBlobCustodyByStates:
        ({required states, int limit = 50}) =>
            dbLoadLinkedDirectMediaBlobCustodyByStates(
              db,
              states: states,
              limit: limit,
            ),
    dbTransitionDirectMediaBlobCustodyIfExact:
        ({required expected, required next}) =>
            dbTransitionDirectMediaBlobCustodyIfExact(
              db,
              expected: expected,
              next: next,
            ),
    dbDeleteDirectMediaBlobCleanupPendingIfExact: ({required expected}) =>
        dbDeleteDirectMediaBlobCleanupPendingIfExact(db, expected: expected),
    dbTerminalizeOutgoingDirectMediaBlobGenerationIfExact:
        ({required expectedRows, required reason, required nowMs}) =>
            dbTerminalizeOutgoingDirectMediaBlobGenerationIfExact(
              db,
              expectedRows: expectedRows,
              reason: reason,
              nowMs: nowMs,
            ),
    dbStageIncomingDirectMediaBlobCustody:
        ({
          required messageRow,
          required attachmentRows,
          required custodyRows,
          authenticatedTransportPeerId,
        }) => dbStageIncomingDirectMediaBlobCustody(
          db,
          messageRow: messageRow,
          attachmentRows: attachmentRows,
          custodyRows: custodyRows,
          authenticatedTransportPeerId: authenticatedTransportPeerId,
        ),
    dbCommitIncomingDirectMediaBlobLocalPath:
        ({
          required expectedAttachmentRow,
          required expectedCustody,
          required localPath,
          required sourceRelayPeerId,
          required updatedAt,
          required nowMs,
        }) => dbCommitIncomingDirectMediaBlobLocalPath(
          db,
          expectedAttachmentRow: expectedAttachmentRow,
          expectedCustody: expectedCustody,
          localPath: localPath,
          sourceRelayPeerId: sourceRelayPeerId,
          updatedAt: updatedAt,
          nowMs: nowMs,
        ),
    dbDeleteIncomingDirectMediaBlobAckPendingIfExact: ({required expected}) =>
        dbDeleteIncomingDirectMediaBlobAckPendingIfExact(
          db,
          expected: expected,
        ),
    dbDeleteIncomingDirectMediaBlobIfExpired:
        ({required expected, required nowMs}) =>
            dbDeleteIncomingDirectMediaBlobIfExpired(
              db,
              expected: expected,
              nowMs: nowMs,
            ),
    dbProjectOutgoingDirectMediaCustodyUploadFailure:
        ({
          required expectedParentRow,
          required expectedAttachmentRows,
          required failedAttachmentId,
          required disposition,
        }) => dbProjectOutgoingDirectMediaCustodyUploadFailure(
          db,
          expectedParentRow: expectedParentRow,
          expectedAttachmentRows: expectedAttachmentRows,
          failedAttachmentId: failedAttachmentId,
          disposition: disposition,
        ),
    publishOutgoingOrdinaryMutation:
        publishOutgoingOrdinaryMutation ??
        ({required messageId, required outcome, required committedMedia}) =>
            messageRepo.publishOutgoingOrdinaryMutation(
              messageId: messageId,
              outcome: outcome,
              committedMedia: committedMedia,
            ),
    dbLoadMediaForMessage: (messageId, ownerLane) =>
        dbLoadMediaForMessage(db, messageId, ownerLane: ownerLane),
    dbLoadMediaById: (id) => dbLoadMediaById(db, id),
    dbLoadMediaForMessages: (messageIds, ownerLane) =>
        dbLoadMediaForMessages(db, messageIds, ownerLane: ownerLane),
    dbUpdateMediaLocalPath: (id, localPath, downloadStatus) =>
        dbUpdateMediaLocalPath(db, id, localPath, downloadStatus),
    dbUpdateMediaDownloadStatus: (id, downloadStatus) =>
        dbUpdateMediaDownloadStatus(db, id, downloadStatus),
    dbDeleteMediaForMessage: (messageId, ownerLane) =>
        dbDeleteMediaForMessage(db, messageId, ownerLane: ownerLane),
    dbDeleteMediaForContact: (contactPeerId) =>
        dbDeleteMediaForContact(db, contactPeerId),
    dbMarkUploadPendingAttachmentsFailedForMessage: (messageId, ownerLane) =>
        dbMarkUploadPendingAttachmentsFailedForMessage(
          db,
          messageId,
          ownerLane: ownerLane,
        ),
    dbLoadPendingMediaDownloads: () => dbLoadPendingMediaDownloads(db),
    dbLoadUploadPendingAttachments:
        ({int limit = 50, required String ownerLane}) =>
            dbLoadUploadPendingAttachments(
              db,
              limit: limit,
              ownerLane: ownerLane,
            ),
    dbSetMediaBookmarked: (id, bookmarked) =>
        dbSetMediaBookmarked(db, id, bookmarked: bookmarked),
    dbUpdateMediaPlaybackPosition: (id, positionMs) =>
        dbUpdateMediaPlaybackPosition(db, id, positionMs),
    dbLoadMediaLibraryPage:
        ({
          required String scopeKind,
          required String scopeId,
          required List<String> mediaTypes,
          required bool bookmarkedOnly,
          required bool incomingOnly,
          required int limit,
          String? afterTimestamp,
          String? afterMessageId,
          String? afterAttachmentId,
        }) => dbLoadMediaLibraryPage(
          db,
          scopeKind: scopeKind,
          scopeId: scopeId,
          mediaTypes: mediaTypes,
          bookmarkedOnly: bookmarkedOnly,
          incomingOnly: incomingOnly,
          limit: limit,
          afterTimestamp: afterTimestamp,
          afterMessageId: afterMessageId,
          afterAttachmentId: afterAttachmentId,
        ),
    dbBeginMediaDownload: (id, {required String ownerLane}) =>
        dbBeginMediaDownload(db, id, ownerLane: ownerLane),
    dbCommitMediaDownloadLocalPath:
        (id, {required String ownerLane, required String localPath}) =>
            dbCommitMediaDownloadLocalPath(
              db,
              id,
              ownerLane: ownerLane,
              localPath: localPath,
            ),
    dbSaveGroupMediaAttachmentGuarded: (row, {required String groupId}) =>
        dbSaveGroupMediaAttachmentGuarded(db, row, groupId: groupId),
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
        dbDeleteReaction(
          db,
          messageId,
          senderPeerId,
          removedAtTimestamp: removedAtTimestamp,
        ),
    dbDeleteReactionsForMessage: (messageId) =>
        dbDeleteReactionsForMessage(db, messageId),
    dbDeleteReactionsForContact: (contactPeerId) =>
        dbDeleteReactionsForContact(db, contactPeerId),
  );
  final reactionReplayOutboxRepo = createGroupMultiDeviceReactionReplayOutbox(
    db,
  );

  await ensureCanonicalRuntimeAttachedForTest();
  final bridge = RecordingGoBridgeClient();
  print('[STACK-DIAG] bridge.initialize() ...');
  await bridge.initialize();
  print('[STACK-DIAG] bridge initialized');

  LinkedInstallationAuthority? setupLinkedAuthority;
  String? effectiveRestoreMnemonic = restoreMnemonic;
  if (setupAsLinkedSecondary) {
    if (reuseExistingIdentity) {
      setupLinkedAuthority = LinkedInstallationAuthority(
        secureKeyStore: secureKeyStore,
      );
    } else {
      if (effectiveRestoreMnemonic == null) {
        final generated = await callIdentityGenerate(bridge);
        final generatedIdentity = generated['identity'];
        if (generated['ok'] != true || generatedIdentity is! Map) {
          throw StateError('Could not generate the B1b account seed');
        }
        effectiveRestoreMnemonic = generatedIdentity['mnemonic12'] as String?;
        if (effectiveRestoreMnemonic == null ||
            effectiveRestoreMnemonic.trim().isEmpty) {
          throw StateError('Generated B1b account seed had no mnemonic');
        }
      }
      await secureKeyStore.write(
        canonicalRuntimeInstallationIdStorageKey,
        'b1b-linked-$configuredRunId',
      );
      setupLinkedAuthority = LinkedInstallationAuthority(
        secureKeyStore: secureKeyStore,
      );
      final setup = await setUpLinkedSecondaryInstallation(
        mnemonic: effectiveRestoreMnemonic,
        authority: setupLinkedAuthority,
        identityRepo: identityRepo,
        callRestore: (mnemonic) => callIdentityRestore(bridge, mnemonic),
        callMlKemKeygen: () => callMlKemKeygen(bridge),
        callIdentityGenerate: () => callIdentityGenerate(bridge),
        callSign: (data, privateKey) => callSignPayload(
          bridge: bridge,
          dataToSign: data,
          privateKey: privateKey,
        ),
        callVerify: ({required publicKey, required data, required signature}) =>
            callVerifyPayload(
              bridge: bridge,
              publicKey: publicKey,
              data: data,
              signature: signature,
            ),
        selector: const DirectLinkedDeviceSelector.enabled(),
      );
      if (setup != LinkedSecondarySetupResult.success) {
        throw StateError('Production linked setup failed: ${setup.name}');
      }
    }
  }

  var savedIdentity = restoreIdentity;
  if (savedIdentity == null && reuseExistingIdentity) {
    savedIdentity = await identityRepo.loadIdentity();
  }
  if (reuseExistingIdentity &&
      savedIdentity == null &&
      restoreMnemonic == null) {
    throw StateError('Existing identity requested but none was found');
  }
  if (savedIdentity == null && !setupAsLinkedSecondary) {
    print('[STACK-DIAG] generating identity via bridge');
    final identityResult = effectiveRestoreMnemonic == null
        ? await generateNewIdentity(
            callGenerate: () => callIdentityGenerate(bridge),
            callMlKemKeygen: () => callMlKemKeygen(bridge),
            repo: identityRepo,
          )
        : await restoreIdentityFromMnemonic(
            input: effectiveRestoreMnemonic,
            callRestore: (mnemonic) => callIdentityRestore(bridge, mnemonic),
            callMlKemKeygen: () => callMlKemKeygen(bridge),
            repo: identityRepo,
          );
    if (identityResult.toString().endsWith('success') != true) {
      throw StateError('Identity setup failed: $identityResult');
    }
    savedIdentity = await identityRepo.loadIdentity();
  }
  savedIdentity ??= await identityRepo.loadIdentity();

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
  print('[STACK-DIAG] identity resolved; saving');
  await identityRepo.saveIdentity(updatedIdentity);
  print('[STACK-DIAG] identity saved');

  var transportPrivateKey = updatedIdentity.privateKey;
  var transportPeerId = updatedIdentity.peerId;
  if (setupAsLinkedSecondary) {
    final authority = setupLinkedAuthority!;
    final active = await authority.load(
      expectedAccountPeerId: updatedIdentity.peerId,
    );
    if (!active.isActiveLinkedSecondary || active.credential == null) {
      throw StateError('Linked setup did not leave active authority');
    }
    transportPrivateKey = active.credential!.transportPrivateKey;
    transportPeerId = active.credential!.transportPeerId;
  } else if (effectiveRestoreMnemonic != null &&
      useFreshTransportIdentityForRestoredAccount) {
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
    keyRotationGracePeriodOverride: configuredKeyRotationGracePeriod(),
    requiredTransportPeerId: restrictedLinkedRuntime && setupAsLinkedSecondary
        ? () => transportPeerId
        : null,
    logicalAccountPeerId: restrictedLinkedRuntime && setupAsLinkedSecondary
        ? () => updatedIdentity.peerId
        : null,
  );
  print('[STACK-DIAG] starting p2p node');
  final started = await p2pService.startNode(
    transportPrivateKey,
    transportPeerId,
  );
  if (!started) {
    throw StateError('P2P node failed to start');
  }
  print('[STACK-DIAG] p2p node started');

  final notificationService = FakeNotificationService();
  await notificationService.initialize();
  final messageRouter = IncomingMessageRouter(p2pService: p2pService);
  final directTransportAuthority = DatabaseDirectTransportAuthority(
    database: db,
  );
  final mediaFileManager = MediaFileManager();
  final deliveryReceiptTargets = <String>[];
  final chatMessageListener = ChatMessageListener(
    transportAuthority: directTransportAuthority,
    chatMessageStream: messageRouter.chatMessageStream,
    messageRepo: messageRepo,
    contactRepo: contactRepo,
    bridge: bridge,
    getOwnMlKemSecretKey: () async => updatedIdentity.mlKemSecretKey,
    mediaAttachmentRepo: mediaAttachmentRepo,
    mediaFileManager: mediaFileManager,
    sendDeliveryReceipt:
        ({
          required contactPeerId,
          required messageIds,
          mutationEventIds,
        }) async {
          deliveryReceiptTargets.add(contactPeerId);
          await sendDeliveryReceipt(
            p2pService: p2pService,
            targetPeerId: contactPeerId,
            messageIds: messageIds,
            mutationEventIds: mutationEventIds,
          );
        },
  );
  final deliveryReceiptListener = DeliveryReceiptListener(
    transportAuthority: directTransportAuthority,
    receiptStream: messageRouter.deliveryReceiptStream,
    messageRepo: messageRepo,
    mediaAttachmentRepo: mediaAttachmentRepo,
  );
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
  var durableExitId = 0;
  final durableGroupExitDriver = DurableGroupExitDriver.compose(
    bridge: bridge,
    intentRepository: groupExitIntentRepo,
    pendingRepository: groupPendingBroadcastRepo,
    groupRepository: groupRepo,
    identityRepository: identityRepo,
    loadMessage: groupMsgRepo.getMessage,
    rePushPendingBroadcast: buildGroupPendingBroadcastRePush(
      bridge: bridge,
      groupRepo: groupRepo,
      loadIdentity: identityRepo.loadIdentity,
      pendingRepository: groupPendingBroadcastRepo,
    ),
    newId: () =>
        'device-group-exit-${updatedIdentity.peerId}-${++durableExitId}',
    now: () => DateTime.now().toUtc(),
    sendP2PMessage: (peerId, message) async =>
        p2pService.sendMessage(peerId, message),
    storeP2PMessageInInbox: (peerId, message) async =>
        p2pService.storeInInbox(peerId, message),
  );

  messageRouter.start();
  chatMessageListener.start();
  deliveryReceiptListener.start();
  if (!restrictedLinkedRuntime) {
    groupKeyUpdateListener.start();
    groupListener.start(
      groupStreamController.stream,
      incomingGroupReactions: groupReactionStreamController.stream,
    );
    groupMembershipUpdateListener.start();
    groupInviteListener.start();
  }
  if (reuseExistingIdentity && startGroupTopicsOnReuse) {
    await rejoinGroupTopics(bridge: bridge, groupRepo: groupRepo);
  }

  print('[STACK-DIAG] stack setup complete');
  return GroupMultiDeviceTestStack(
    db: db,
    dbName: dbName,
    secureKeyStore: secureKeyStore,
    bridge: bridge,
    p2pService: p2pService,
    identityRepo: identityRepo,
    contactRepo: contactRepo,
    groupRepo: groupRepo,
    groupMsgRepo: groupMsgRepo,
    groupInviteDeliveryAttemptRepo: groupInviteDeliveryAttemptRepo,
    messageRepo: messageRepo,
    mediaAttachmentRepo: mediaAttachmentRepo,
    reactionRepo: reactionRepo,
    reactionReplayOutboxRepo: reactionReplayOutboxRepo,
    groupExitIntentRepo: groupExitIntentRepo,
    groupPendingBroadcastRepo: groupPendingBroadcastRepo,
    durableGroupExitDriver: durableGroupExitDriver,
    messageRouter: messageRouter,
    chatMessageListener: chatMessageListener,
    deliveryReceiptListener: deliveryReceiptListener,
    mediaFileManager: mediaFileManager,
    deliveryReceiptTargets: deliveryReceiptTargets,
    mediaFanoutEnvelopeBindings: mediaFanoutEnvelopeBindings,
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

    final bobFixture = await waitForSharedJson(
      _signalName('bob_identity.json'),
    );
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

// ── TC-267 Wave 0: invite_send_latency baseline ──
//
// The two Android targets never share a filesystem. Every file below is
// written under each app's target-local cache directory. The host runner
// copies complete files between those directories with `adb run-as` and pulls
// both final artifacts for strict validation.

typedef _InviteLatencyCell = ({String path, String condition, int repetition});
typedef _InviteLatencyRecipientTransition = ({
  bool stopCompleted,
  bool restartCompleted,
});

const _inviteLatencyArtifactSchemaVersion = 2;
const _inviteLatencyObservationWindowVersion = 1;
const _inviteLatencyObservationWindow = Duration(seconds: 30);
const _inviteLatencyDiagnosticOperationTimeout = Duration(seconds: 30);

const _inviteLatencyPhaseOrder = <GroupInviteLatencyPhase>[
  GroupInviteLatencyPhase.preFanout,
  GroupInviteLatencyPhase.sign,
  GroupInviteLatencyPhase.encrypt,
  GroupInviteLatencyPhase.live,
  GroupInviteLatencyPhase.inbox,
  GroupInviteLatencyPhase.persistence,
  GroupInviteLatencyPhase.navigationSettlement,
];

List<_InviteLatencyCell> _inviteLatencyCells() => <_InviteLatencyCell>[
  for (final path in const <String>['create', 'add'])
    for (final condition in const <String>[
      'online-warm',
      'online-cold',
      'offline',
    ])
      for (var repetition = 1; repetition <= 5; repetition++)
        (path: path, condition: condition, repetition: repetition),
];

String _latencyOperationId(_InviteLatencyCell cell) =>
    '${configuredRunId}_${cell.path}_${cell.condition}_${cell.repetition}';

String _latencySignalName(String operationId, String suffix) {
  final safeOperationId = operationId.replaceAll(
    RegExp(r'[^A-Za-z0-9_.-]'),
    '_',
  );
  return _signalName('latency_${safeOperationId}_$suffix');
}

String _latencyArtifactName(String role) =>
    _signalName('invite_send_latency_$role.json');

String _latencyArtifactSha256(String role) => sha256
    .convert(File(sharedPath(_latencyArtifactName(role))).readAsBytesSync())
    .toString();

Future<void> _waitForLatencyHostCaptureReceipt({
  required String role,
  required String ownArtifactSha256,
}) async {
  final receipt = await waitForSharedJson(
    inviteSendLatencyHostCaptureReceiptFileName(configuredRunId),
    timeout: const Duration(minutes: 5),
  );
  final validation = validateInviteSendLatencyHostCaptureReceiptForRole(
    receipt: receipt,
    expectedRunId: configuredRunId,
    expectedMode: configuredMode,
    role: role,
    expectedOwnArtifactSha256: ownArtifactSha256,
  );
  if (!validation.ok) {
    throw StateError(
      'invite_send_latency host capture receipt rejected by $role: '
      '${validation.detail}',
    );
  }
}

void _requireTargetLocalLatencyDirectory() {
  if (!Platform.isAndroid) return;
  final path = groupMultiDeviceRuntimeSharedDir();
  final appCachePath = RegExp(r'^/data/(?:user/0|data)/[^/]+/cache(?:/|$)');
  if (!appCachePath.hasMatch(path)) {
    throw StateError(
      'invite_send_latency requires an Android target-local app cache path; '
      'got $path',
    );
  }
}

Future<Map<String, dynamic>> _runLatencySelfCustodyCanary(
  GroupMultiDeviceTestStack stack, {
  required String role,
}) async {
  final startedAt = DateTime.now().toUtc();
  // startNode returns before its background relay/inbox proofs necessarily
  // converge on slower targets. Admission waits for that one bounded state
  // transition, then performs exactly one custody store/drain attempt below.
  await waitForCondition(() async {
    final state = stack.p2pService.currentState;
    return state.isStarted && state.usabilityReady && state.relayReady;
  }, timeout: const Duration(seconds: 90));
  final initialState = stack.p2pService.currentState;
  final transportPeerId = initialState.peerId;
  expect(transportPeerId, isNotNull);
  expect(initialState.isStarted, isTrue);
  expect(initialState.usabilityReady, isTrue);
  expect(initialState.relayReady, isTrue);

  // One admission probe per role and run. It is deliberately not retried and
  // never participates in any later per-cell delivery verdict.
  final storeAccepted = await stack.p2pService
      .storeInInbox(
        transportPeerId!,
        jsonEncode(<String, dynamic>{
          'type': 'tc267_self_custody_canary',
          'version': '1',
          'runId': configuredRunId,
          'role': role,
        }),
      )
      .timeout(_inviteLatencyDiagnosticOperationTimeout);
  final storeCompletedAt = DateTime.now().toUtc();
  expect(storeAccepted, isTrue, reason: 'self-custody canary must be accepted');
  await stack.p2pService.drainOfflineInbox().timeout(
    _inviteLatencyDiagnosticOperationTimeout,
  );
  final drainCompletedAt = DateTime.now().toUtc();
  await stack.groupInviteListener.waitForIdle().timeout(
    _inviteLatencyDiagnosticOperationTimeout,
  );
  final freshState = stack.p2pService.currentState;
  final stateObservedAt = DateTime.now().toUtc();
  expect(freshState.peerId, transportPeerId);
  expect(freshState.isStarted, isTrue);
  expect(freshState.usabilityReady, isTrue);
  expect(freshState.relayReady, isTrue);
  final completedAt = DateTime.now().toUtc();
  return <String, dynamic>{
    'kind': 'self_inbox_custody',
    'attemptCount': 1,
    'startedAt': startedAt.toIso8601String(),
    'stateObservedAt': stateObservedAt.toIso8601String(),
    'storeCompletedAt': storeCompletedAt.toIso8601String(),
    'drainCompletedAt': drainCompletedAt.toIso8601String(),
    'completedAt': completedAt.toIso8601String(),
    'storeAccepted': storeAccepted,
    'drainCompleted': true,
    'nodeStarted': freshState.isStarted,
    'usabilityReady': freshState.usabilityReady,
    'relayReady': freshState.relayReady,
    'transportPeerId': freshState.peerId,
    'status': 'accepted',
  };
}

Future<void> _startLatencyNode(
  GroupMultiDeviceTestStack stack, {
  required String expectedTransportPeerId,
}) async {
  if (!stack.p2pService.currentState.isStarted) {
    final started = await stack.p2pService.startNode(
      stack.identity.privateKey,
      stack.identity.peerId,
    );
    expect(started, isTrue, reason: 'latency recipient node must restart');
  }
  await waitForCondition(
    () async =>
        stack.p2pService.currentState.usabilityReady &&
        stack.p2pService.currentState.relayReady,
    timeout: const Duration(seconds: 90),
  );
  expect(
    stack.p2pService.currentState.peerId,
    expectedTransportPeerId,
    reason: 'latency node restart must preserve its transport identity',
  );
}

Future<void> _stopLatencyNode(GroupMultiDeviceTestStack stack) async {
  if (!stack.p2pService.currentState.isStarted) return;
  final stopped = await stack.p2pService.stopNode();
  expect(stopped, isTrue, reason: 'latency recipient node must stop');
  expect(stack.p2pService.currentState.isStarted, isFalse);
}

Future<_InviteLatencyRecipientTransition> _prepareLatencyRecipient(
  GroupMultiDeviceTestStack stack,
  String condition, {
  required String expectedTransportPeerId,
}) async {
  switch (condition) {
    case 'online-warm':
      expect(
        stack.p2pService.currentState.isStarted,
        isTrue,
        reason: 'warm condition must not restart a stopped node',
      );
      await _startLatencyNode(
        stack,
        expectedTransportPeerId: expectedTransportPeerId,
      );
      return (stopCompleted: false, restartCompleted: false);
    case 'online-cold':
      expect(
        stack.p2pService.currentState.isStarted,
        isTrue,
        reason: 'cold condition requires a live-to-stopped transition',
      );
      await _stopLatencyNode(stack);
      await _startLatencyNode(
        stack,
        expectedTransportPeerId: expectedTransportPeerId,
      );
      return (stopCompleted: true, restartCompleted: true);
    case 'offline':
      expect(
        stack.p2pService.currentState.isStarted,
        isTrue,
        reason: 'offline condition requires an observed node stop',
      );
      await _stopLatencyNode(stack);
      return (stopCompleted: true, restartCompleted: false);
    default:
      throw StateError('Unsupported invite latency condition: $condition');
  }
}

Future<void> _pumpLatencyUntil(
  WidgetTester tester,
  bool Function() condition, {
  Duration timeout = const Duration(minutes: 5),
  String reason = 'widget condition',
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (condition()) return;
    await tester.pump(const Duration(milliseconds: 100));
    await Future<void>.delayed(const Duration(milliseconds: 40));
  }
  throw TimeoutException('Timed out waiting for $reason');
}

bool _hasLatencyPhaseEnd(
  List<GroupInviteLatencyEvent> events,
  String operationId,
  GroupInviteLatencyPhase phase,
) => events.any(
  (event) =>
      event.operationId == operationId &&
      event.phase == phase &&
      event.boundary == GroupInviteLatencyBoundary.end,
);

Widget _latencyMaterialApp({required Widget home}) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: home,
);

Future<String> _driveLatencyCreateCaller({
  required WidgetTester tester,
  required GroupMultiDeviceTestStack stack,
  required String operationId,
  required String groupName,
  required List<GroupInviteLatencyEvent> events,
}) async {
  await tester.pumpWidget(
    _latencyMaterialApp(
      home: CreateGroupPickerWired(
        groupType: GroupType.chat,
        groupRepo: stack.groupRepo,
        msgRepo: stack.groupMsgRepo,
        groupMessageListener: stack.groupListener,
        inviteDeliveryAttemptRepo: stack.groupInviteDeliveryAttemptRepo,
        contactRepo: stack.contactRepo,
        bridge: stack.bridge,
        identityRepo: stack.identityRepo,
        p2pService: stack.p2pService,
        mediaAttachmentRepo: stack.mediaAttachmentRepo,
        reactionRepo: stack.reactionRepo,
        groupReactionReplayOutboxRepository: stack.reactionReplayOutboxRepo,
        inviteLatencyOperationId: operationId,
      ),
    ),
  );
  await _pumpLatencyUntil(
    tester,
    () => find.text('Bob').evaluate().isNotEmpty,
    reason: 'create caller contact load',
  );
  await tester.tap(find.text('Bob').first);
  await tester.pump();
  final nameField = find.byType(TextField).last;
  await tester.enterText(nameField, groupName);
  final startButton = find.text('Start group chat');
  await tester.ensureVisible(startButton);
  await tester.tap(startButton);
  await _pumpLatencyUntil(
    tester,
    () => _hasLatencyPhaseEnd(
      events,
      operationId,
      GroupInviteLatencyPhase.navigationSettlement,
    ),
    timeout: const Duration(minutes: 8),
    reason: 'create caller navigation settlement',
  );

  final groupIds = events
      .where((event) => event.operationId == operationId)
      .map((event) => event.groupId)
      .whereType<String>()
      .toSet();
  expect(groupIds, hasLength(1));
  return groupIds.single;
}

Future<String> _driveLatencyAddCaller({
  required WidgetTester tester,
  required GroupMultiDeviceTestStack stack,
  required String operationId,
  required String groupName,
  required List<GroupInviteLatencyEvent> events,
}) async {
  final baseGroup = await createGroupWithMembers(
    bridge: stack.bridge,
    groupRepo: stack.groupRepo,
    p2pService: stack.p2pService,
    identity: stack.identity,
    selectedContacts: const <ContactModel>[],
    type: GroupType.chat,
    name: groupName,
    inviteDeliveryAttemptRepo: stack.groupInviteDeliveryAttemptRepo,
  );
  ContactPickerInviteResult? popResult;
  await tester.pumpWidget(
    _latencyMaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                popResult = await Navigator.of(context)
                    .push<ContactPickerInviteResult>(
                      MaterialPageRoute(
                        builder: (_) => ContactPickerWired(
                          groupId: baseGroup.group.id,
                          groupRepo: stack.groupRepo,
                          contactRepo: stack.contactRepo,
                          bridge: stack.bridge,
                          identityRepo: stack.identityRepo,
                          p2pService: stack.p2pService,
                          msgRepo: stack.groupMsgRepo,
                          inviteDeliveryAttemptRepo:
                              stack.groupInviteDeliveryAttemptRepo,
                          inviteLatencyOperationId: operationId,
                        ),
                      ),
                    );
              },
              child: const Text('Open latency add caller'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open latency add caller'));
  await _pumpLatencyUntil(
    tester,
    () => find.text('Bob').evaluate().isNotEmpty,
    reason: 'add caller contact load',
  );
  await tester.tap(find.text('Bob').first);
  await tester.pump();
  final sendButton = find.text('Send Invites');
  await tester.ensureVisible(sendButton);
  await tester.tap(sendButton);
  await _pumpLatencyUntil(
    tester,
    () =>
        popResult != null &&
        _hasLatencyPhaseEnd(
          events,
          operationId,
          GroupInviteLatencyPhase.navigationSettlement,
        ),
    timeout: const Duration(minutes: 8),
    reason: 'add caller navigation settlement',
  );
  expect(popResult!.membersAdded, 1);
  return baseGroup.group.id;
}

({GroupInviteLatencyEvent begin, GroupInviteLatencyEvent end})
_latencyPhasePair(
  List<GroupInviteLatencyEvent> operationEvents,
  GroupInviteLatencyPhase phase,
) {
  final phaseEvents = operationEvents
      .where((event) => event.phase == phase)
      .toList(growable: false);
  expect(
    phaseEvents,
    hasLength(2),
    reason: '${phase.wireName} must have exactly one begin/end pair',
  );
  expect(phaseEvents.first.boundary, GroupInviteLatencyBoundary.begin);
  expect(phaseEvents.last.boundary, GroupInviteLatencyBoundary.end);
  expect(
    phaseEvents.last.at.isBefore(phaseEvents.first.at),
    isFalse,
    reason: '${phase.wireName} end must not precede begin',
  );
  return (begin: phaseEvents.first, end: phaseEvents.last);
}

String _latencyDetailString(GroupInviteLatencyEvent event, String key) {
  final value = event.details[key];
  expect(value, isA<String>(), reason: '$key must be recorded');
  return value! as String;
}

Map<String, dynamic> _buildLatencyPrimarySample({
  required _InviteLatencyCell cell,
  required String operationId,
  required String groupId,
  required String recipientPeerId,
  required GroupInviteDeliveryAttempt attempt,
  required List<GroupInviteLatencyEvent> allEvents,
}) {
  final operationEvents = allEvents
      .where((event) => event.operationId == operationId)
      .toList(growable: false);
  final pairs =
      <
        GroupInviteLatencyPhase,
        ({GroupInviteLatencyEvent begin, GroupInviteLatencyEvent end})
      >{
        for (final phase in _inviteLatencyPhaseOrder)
          phase: _latencyPhasePair(operationEvents, phase),
      };
  for (var index = 1; index < _inviteLatencyPhaseOrder.length; index++) {
    final previous = pairs[_inviteLatencyPhaseOrder[index - 1]]!;
    final current = pairs[_inviteLatencyPhaseOrder[index]]!;
    expect(
      current.begin.at.isBefore(previous.end.at),
      isFalse,
      reason: 'latency phases must remain ordered',
    );
  }

  final inviteIds = operationEvents
      .map((event) => event.inviteId)
      .whereType<String>()
      .toSet();
  expect(inviteIds, hasLength(1));
  final inviteId = inviteIds.single;
  expect(attempt.inviteId, inviteId);
  expect(
    attempt.groupId,
    groupId,
    reason: 'persisted delivery attempt must bind the sampled group',
  );
  expect(
    attempt.peerId,
    recipientPeerId,
    reason: 'persisted delivery attempt must bind the sampled recipient',
  );

  final live = pairs[GroupInviteLatencyPhase.live]!;
  final inbox = pairs[GroupInviteLatencyPhase.inbox]!;
  final persistence = pairs[GroupInviteLatencyPhase.persistence]!;
  final navigation = pairs[GroupInviteLatencyPhase.navigationSettlement]!;
  final preFanout = pairs[GroupInviteLatencyPhase.preFanout]!;
  final liveAcknowledged = live.end.details['acknowledged'];
  expect(liveAcknowledged, isA<bool>());
  final liveOutcome = _latencyDetailString(live.end, 'outcome');
  final inboxOutcome = _latencyDetailString(inbox.end, 'outcome');
  final inboxAttemptCount = inboxOutcome == 'skipped' ? 0 : 1;
  final confirmedInboxStoreCount = inboxOutcome == 'stored' ? 1 : 0;
  final transport = liveAcknowledged == true
      ? 'direct'
      : confirmedInboxStoreCount == 1
      ? 'inbox'
      : 'none';
  final applicationResult = switch ((attempt.status, attempt.lastError)) {
    (GroupInviteDeliveryStatus.sent, null) => 'success',
    (GroupInviteDeliveryStatus.queued, null) => 'queued',
    (GroupInviteDeliveryStatus.needsResend, 'send_failed') => 'send_failed',
    _ => throw StateError(
      'TC-267 latency sample reached unsupported attempt status/error '
      '${attempt.status.toValue()}/${attempt.lastError}',
    ),
  };
  final deliveryKnowledge = switch (transport) {
    'direct' => 'wire_ack_confirmed',
    'inbox' => 'relay_custody_confirmed',
    _ => 'outcome_unknown',
  };
  final envelopeSha256 = _latencyDetailString(live.begin, 'envelopeSha256');
  expect(envelopeSha256, matches(RegExp(r'^[0-9a-f]{64}$')));

  return <String, dynamic>{
    'operationId': operationId,
    'path': cell.path,
    'condition': cell.condition,
    'repetition': cell.repetition,
    'groupId': groupId,
    'inviteId': inviteId,
    'recipientPeerId': recipientPeerId,
    'connectionState': _latencyDetailString(live.begin, 'connectionState'),
    'envelopeSha256': envelopeSha256,
    'transport': transport,
    'applicationResult': applicationResult,
    'attemptStatus': attempt.status.toValue(),
    'attemptLastError': attempt.lastError,
    'deliveryKnowledge': deliveryKnowledge,
    'liveAcknowledged': liveAcknowledged,
    'liveOutcome': liveOutcome,
    'inboxAttemptCount': inboxAttemptCount,
    'confirmedInboxStoreCount': confirmedInboxStoreCount,
    'inboxOutcome': inboxOutcome,
    'attemptId': '${attempt.groupId}:${attempt.peerId}',
    'caller': <String, dynamic>{
      'beginAt': preFanout.begin.at.toUtc().toIso8601String(),
      'endAt': persistence.end.at.toUtc().toIso8601String(),
      'settledAt': navigation.end.at.toUtc().toIso8601String(),
    },
    'phases': <Map<String, dynamic>>[
      for (final phase in _inviteLatencyPhaseOrder)
        <String, dynamic>{
          'name': phase.wireName,
          'beginAt': pairs[phase]!.begin.at.toUtc().toIso8601String(),
          'endAt': pairs[phase]!.end.at.toUtc().toIso8601String(),
          'outcome': _latencyDetailString(pairs[phase]!.end, 'outcome'),
        },
    ],
  };
}

Map<String, dynamic> _latencyRoleArtifact({
  required String role,
  required GroupMultiDeviceTestStack stack,
  required Map<String, dynamic> admissionCanary,
  required List<Map<String, dynamic>> samples,
}) => <String, dynamic>{
  'schema': 'mknoon.tc267.invite-send-latency',
  'schemaVersion': _inviteLatencyArtifactSchemaVersion,
  'scenario': 'invite_send_latency',
  'mode': configuredMode,
  'runId': configuredRunId,
  'role': role,
  'roleVerdict': 'pass',
  'identity': <String, dynamic>{
    'peerId': stack.identity.peerId,
    'transportPeerId': stack.p2pService.currentState.peerId,
  },
  'admissionCanary': admissionCanary,
  'samples': samples,
};

String _latencyRecipientObservationStatus({
  required String inviteId,
  required String? pendingInviteId,
  required int eventCount,
}) {
  if (pendingInviteId != null && pendingInviteId != inviteId) {
    throw StateError(
      'TC-267 recipient pending invite $pendingInviteId does not match '
      'correlated invite $inviteId',
    );
  }
  if (eventCount >= 1) {
    return pendingInviteId == inviteId
        ? 'exact_event_observed'
        : 'event_without_pending';
  }
  return pendingInviteId == inviteId
      ? 'pending_without_event'
      : 'not_observed_within_window';
}

Future<void> _runInviteSendLatencyPrimary(WidgetTester tester) async {
  _requireTargetLocalLatencyDirectory();
  final stack = await setupGroupMultiDeviceStack(
    dbName: _dbNameForRole(),
    username: 'Alice',
    cliPeerFixture: null,
  );
  final traceEvents = <GroupInviteLatencyEvent>[];
  final traceLease = installGroupInviteLatencySink(traceEvents.add);
  try {
    writeSharedJson(
      _signalName('latency_alice_identity.json'),
      _peerIdentityFixture(stack.identity),
    );
    final bobFixture = await waitForSharedJson(
      _signalName('latency_bob_identity.json'),
      timeout: const Duration(minutes: 12),
    );
    final bobContact = _contactFromFixture(bobFixture, 'Bob');
    await stack.contactRepo.addContact(bobContact);
    final admissionCanary = await _runLatencySelfCustodyCanary(
      stack,
      role: 'primary',
    );

    final samples = <Map<String, dynamic>>[];
    for (final cell in _inviteLatencyCells()) {
      final operationId = _latencyOperationId(cell);
      writeSharedJson(
        _latencySignalName(operationId, 'prepare.json'),
        <String, dynamic>{
          'operationId': operationId,
          'path': cell.path,
          'condition': cell.condition,
          'repetition': cell.repetition,
        },
      );
      final ready = await waitForSharedJson(
        _latencySignalName(operationId, 'ready.json'),
        timeout: const Duration(minutes: 4),
      );
      expect(ready['operationId'], operationId);
      expect(ready['transportPeerId'], bobContact.peerId);
      if (cell.condition == 'offline') {
        expect(ready['nodeStarted'], isFalse);
        expect(ready['relayReady'], isFalse);
        expect(ready['stopCompleted'], isTrue);
        expect(ready['restartCompleted'], isFalse);
      } else if (cell.condition == 'online-cold') {
        expect(ready['nodeStarted'], isTrue);
        expect(ready['relayReady'], isTrue);
        expect(ready['stopCompleted'], isTrue);
        expect(ready['restartCompleted'], isTrue);
      } else {
        expect(ready['nodeStarted'], isTrue);
        expect(ready['relayReady'], isTrue);
        expect(ready['stopCompleted'], isFalse);
        expect(ready['restartCompleted'], isFalse);
      }

      if (cell.condition == 'online-warm') {
        await stack.p2pService.warmPeer(bobContact.peerId);
        try {
          await waitForCondition(
            () async => stack.p2pService.isConnectedToPeer(bobContact.peerId),
            timeout: const Duration(seconds: 8),
          );
        } on TimeoutException {
          // Warm is an attempted condition, not a fabricated connection fact;
          // the trace records the actual structural state at the live await.
        }
      }

      final groupName =
          'TC267 ${cell.path} ${cell.condition} ${cell.repetition}';
      final groupId = cell.path == 'create'
          ? await _driveLatencyCreateCaller(
              tester: tester,
              stack: stack,
              operationId: operationId,
              groupName: groupName,
              events: traceEvents,
            )
          : await _driveLatencyAddCaller(
              tester: tester,
              stack: stack,
              operationId: operationId,
              groupName: groupName,
              events: traceEvents,
            );
      final attempt = await stack.groupInviteDeliveryAttemptRepo.getAttempt(
        groupId: groupId,
        peerId: bobContact.peerId,
      );
      expect(attempt, isNotNull);
      expect(attempt!.inviteId, isNotNull);
      final sample = _buildLatencyPrimarySample(
        cell: cell,
        operationId: operationId,
        groupId: groupId,
        recipientPeerId: bobContact.peerId,
        attempt: attempt,
        allEvents: traceEvents,
      );
      samples.add(sample);
      writeSharedJson(
        _latencySignalName(operationId, 'sent.json'),
        <String, dynamic>{
          'operationId': operationId,
          'path': cell.path,
          'condition': cell.condition,
          'repetition': cell.repetition,
          'groupId': groupId,
          'inviteId': sample['inviteId'],
          'recipientPeerId': bobContact.peerId,
        },
      );
      final observed = await waitForSharedJson(
        _latencySignalName(operationId, 'observed.json'),
        timeout: const Duration(minutes: 4),
      );
      expect(observed['operationId'], operationId);
      expect(observed['inviteId'], sample['inviteId']);
      expect(observed['eventCount'], isA<int>());
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    }
    expect(samples, hasLength(30));
    writeSharedJson(
      _latencyArtifactName('primary'),
      _latencyRoleArtifact(
        role: 'primary',
        stack: stack,
        admissionCanary: admissionCanary,
        samples: samples,
      ),
    );
    final ownArtifactSha256 = _latencyArtifactSha256('primary');
    // Release the sibling only after every sender operation has settled. The
    // sibling keeps its pending-invite observation live until this signal, so
    // its final artifact can freeze counts after the complete sender window.
    writeSharedText(_signalName('latency_primary_sampling_complete'), 'ok');
    // Stay installed until the host has stably captured both immutable role
    // artifacts. A flutter-test teardown may uninstall the package and purge
    // target-local cache files immediately after this function returns.
    await _waitForLatencyHostCaptureReceipt(
      role: 'primary',
      ownArtifactSha256: ownArtifactSha256,
    );
  } finally {
    traceLease.release();
    await stack.teardown();
  }
}

Future<void> _runInviteSendLatencySibling() async {
  _requireTargetLocalLatencyDirectory();
  final stack = await setupGroupMultiDeviceStack(
    dbName: _dbNameForRole(),
    username: 'Bob',
    cliPeerFixture: null,
  );
  final eventCounts = <String, int>{};
  final firstObservedAt = <String, DateTime>{};
  final pendingSubscription = stack.groupInviteListener.pendingInviteStream
      .listen((invite) {
        firstObservedAt.putIfAbsent(invite.inviteId, DateTime.now().toUtc);
        eventCounts.update(
          invite.inviteId,
          (count) => count + 1,
          ifAbsent: () => 1,
        );
      });
  var observationFrozen = false;
  try {
    final stableTransportPeerId = stack.p2pService.currentState.peerId;
    expect(stableTransportPeerId, isNotNull);
    writeSharedJson(
      _signalName('latency_bob_identity.json'),
      _peerIdentityFixture(stack.identity),
    );
    final aliceFixture = await waitForSharedJson(
      _signalName('latency_alice_identity.json'),
      timeout: const Duration(minutes: 12),
    );
    await stack.contactRepo.addContact(
      _contactFromFixture(aliceFixture, 'Alice'),
    );
    final admissionCanary = await _runLatencySelfCustodyCanary(
      stack,
      role: 'sibling',
    );

    final samples = <Map<String, dynamic>>[];
    for (final cell in _inviteLatencyCells()) {
      final operationId = _latencyOperationId(cell);
      final prepare = await waitForSharedJson(
        _latencySignalName(operationId, 'prepare.json'),
        timeout: const Duration(minutes: 8),
      );
      expect(prepare['operationId'], operationId);
      expect(prepare['path'], cell.path);
      expect(prepare['condition'], cell.condition);
      expect(prepare['repetition'], cell.repetition);
      final transition = await _prepareLatencyRecipient(
        stack,
        cell.condition,
        expectedTransportPeerId: stableTransportPeerId!,
      );
      final preparedNodeStarted = stack.p2pService.currentState.isStarted;
      final preparedRelayReady = stack.p2pService.currentState.relayReady;
      if (cell.condition == 'offline') {
        expect(preparedNodeStarted, isFalse);
        expect(preparedRelayReady, isFalse);
      } else {
        expect(preparedNodeStarted, isTrue);
        expect(preparedRelayReady, isTrue);
      }
      writeSharedJson(
        _latencySignalName(operationId, 'ready.json'),
        <String, dynamic>{
          'operationId': operationId,
          'nodeStarted': preparedNodeStarted,
          'relayReady': preparedRelayReady,
          'transportPeerId': stableTransportPeerId,
          'stopCompleted': transition.stopCompleted,
          'restartCompleted': transition.restartCompleted,
        },
      );

      final sent = await waitForSharedJson(
        _latencySignalName(operationId, 'sent.json'),
        timeout: const Duration(minutes: 10),
      );
      if (cell.condition == 'offline') {
        await _startLatencyNode(
          stack,
          expectedTransportPeerId: stableTransportPeerId,
        );
      }
      final groupId = sent['groupId'] as String;
      final inviteId = sent['inviteId'] as String;
      final observationStartedAt = DateTime.now().toUtc();
      final observationDeadlineAt = observationStartedAt.add(
        _inviteLatencyObservationWindow,
      );
      var drainAttemptCount = 0;
      var drainErrorCount = 0;
      String? pendingInviteId;
      while (DateTime.now().toUtc().isBefore(observationDeadlineAt)) {
        drainAttemptCount += 1;
        try {
          await stack.p2pService.drainOfflineInbox();
        } catch (_) {
          drainErrorCount += 1;
        }
        final pending = await stack.pendingInviteRepo.getPendingInvite(groupId);
        pendingInviteId = pending?.inviteId;
        if (pendingInviteId == inviteId && (eventCounts[inviteId] ?? 0) >= 1) {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
      final observationCompletedAt = DateTime.now().toUtc();
      final initialEventCount = eventCounts[inviteId] ?? 0;
      final initialObservedAt = firstObservedAt[inviteId];
      final sample = <String, dynamic>{
        'operationId': operationId,
        'path': cell.path,
        'condition': cell.condition,
        'repetition': cell.repetition,
        'groupId': groupId,
        'inviteId': inviteId,
        'recipientPeerId': stack.identity.peerId,
        'pendingInviteId': pendingInviteId,
        'eventCount': initialEventCount,
        'observationStatus': _latencyRecipientObservationStatus(
          inviteId: inviteId,
          pendingInviteId: pendingInviteId,
          eventCount: initialEventCount,
        ),
        'observedLate':
            initialObservedAt != null &&
            initialObservedAt.isAfter(observationDeadlineAt),
        'observationWindowVersion': _inviteLatencyObservationWindowVersion,
        'observationWindowMs': _inviteLatencyObservationWindow.inMilliseconds,
        'observationStartedAt': observationStartedAt.toIso8601String(),
        'observationDeadlineAt': observationDeadlineAt.toIso8601String(),
        'observationCompletedAt': observationCompletedAt.toIso8601String(),
        'finalReconciledAt': observationCompletedAt.toIso8601String(),
        'drainAttemptCount': drainAttemptCount,
        'drainErrorCount': drainErrorCount,
        'preparedNodeStarted': preparedNodeStarted,
        'preparedRelayReady': preparedRelayReady,
        'preparedTransportPeerId': stableTransportPeerId,
        'preparedStopCompleted': transition.stopCompleted,
        'preparedRestartCompleted': transition.restartCompleted,
        'observedAt': initialObservedAt?.toIso8601String(),
      };
      samples.add(sample);
      writeSharedJson(_latencySignalName(operationId, 'observed.json'), sample);
    }
    // The final per-cell observation only proves that the thirtieth invite was
    // visible. Wait until the primary confirms that every sender caller has
    // settled before starting the final duplicate-observation window.
    await waitForSharedSignal(
      _signalName('latency_primary_sampling_complete'),
      timeout: const Duration(minutes: 5),
    );
    // Drain once more and hold a bounded quiet window before freezing counts
    // so a delayed second visible event from any earlier cell is not silently
    // reported as one. Cancel the stream before projecting the final counts;
    // the artifact is written exactly once after observation is immutable.
    try {
      await stack.p2pService.drainOfflineInbox();
    } catch (_) {
      // Baseline reconciliation records non-observation rather than selecting
      // away a delivery tail because a final diagnostic drain failed.
    }
    await stack.groupInviteListener.waitForIdle().timeout(
      _inviteLatencyDiagnosticOperationTimeout,
    );
    await Future<void>.delayed(const Duration(seconds: 1));
    try {
      await stack.p2pService.drainOfflineInbox();
    } catch (_) {
      // See above. The fixed per-sample drain counts remain the raw evidence.
    }
    await stack.groupInviteListener.waitForIdle().timeout(
      _inviteLatencyDiagnosticOperationTimeout,
    );
    await pendingSubscription.cancel();
    observationFrozen = true;
    for (final sample in samples) {
      final groupId = sample['groupId'] as String;
      final inviteId = sample['inviteId'] as String;
      final pending = await stack.pendingInviteRepo.getPendingInvite(groupId);
      final pendingInviteId = pending?.inviteId;
      final finalCount = eventCounts[inviteId] ?? 0;
      final observedAt = firstObservedAt[inviteId];
      final observationDeadlineAt = DateTime.parse(
        sample['observationDeadlineAt'] as String,
      );
      sample['pendingInviteId'] = pendingInviteId;
      sample['eventCount'] = finalCount;
      sample['observedAt'] = observedAt?.toIso8601String();
      sample['observedLate'] =
          observedAt != null && observedAt.isAfter(observationDeadlineAt);
      sample['observationStatus'] = _latencyRecipientObservationStatus(
        inviteId: inviteId,
        pendingInviteId: pendingInviteId,
        eventCount: finalCount,
      );
      sample['finalReconciledAt'] = DateTime.now().toUtc().toIso8601String();
    }
    expect(samples, hasLength(30));
    writeSharedJson(
      _latencyArtifactName('sibling'),
      _latencyRoleArtifact(
        role: 'sibling',
        stack: stack,
        admissionCanary: admissionCanary,
        samples: samples,
      ),
    );
    final ownArtifactSha256 = _latencyArtifactSha256('sibling');
    await _waitForLatencyHostCaptureReceipt(
      role: 'sibling',
      ownArtifactSha256: ownArtifactSha256,
    );
  } finally {
    if (!observationFrozen) {
      await pendingSubscription.cancel();
    }
    await stack.teardown();
  }
}

// ── Plan 363: availability-bounded B1b linked-group bootstrap proof ─────────
// The runner pins the physical Android as `primary`; that role is the fresh
// linked secondary which owns an empty repository and publishes its production
// QR. The emulator `sibling` is the ordinary account-primary which creates one
// group, scans that QR, and owns protected bootstrap/authority custody.

var _b1bContentIngressAuthorityGateInvocations = 0;
var _b1bAuthorityReconcileInvocations = 0;
var _b1bLocalAuthorityReconcileInvocations = 0;
var _b1bPlan365RestrictedFixedPointInvocations = 0;

ProtectedGroupReplayOutcome _b1bReplayOutcome(
  ProtectedGroupReplayDisposition disposition,
  String reasonCode,
) => (disposition: disposition, reasonCode: reasonCode, reasonDetail: null);

Future<LinkedInstallationAuthoritySnapshot> _b1bLinkedAuthority(
  GroupMultiDeviceTestStack stack,
) {
  return LinkedInstallationAuthority(
    secureKeyStore: stack.secureKeyStore,
  ).load(expectedAccountPeerId: stack.identity.peerId);
}

Future<ProtectedGroupContentAuthority?> _b1bLoadContentAuthority(
  GroupMultiDeviceTestStack stack,
  String groupId,
  GroupContentAuthorityVersion version,
) {
  return loadProtectedGroupContentAuthorityFromHistory(
    groupId: groupId,
    version: version,
    loadExact: ({required groupId, required phase, required eventId}) =>
        loadAuthenticatedGroupAuthorityProofFromEventLog(
          loadRow: ({required groupId, required sourceEventId}) =>
              dbLoadGroupEventLogEntryExact(
                stack.db,
                groupId: groupId,
                sourceEventId: sourceEventId,
              ),
          groupId: groupId,
          phase: phase,
          verify: ({required publicKey, required data, required signature}) =>
              callVerifyPayload(
                bridge: stack.bridge,
                publicKey: publicKey,
                data: data,
                signature: signature,
              ),
          eventId: eventId,
        ),
    loadCompleteRows:
        ({
          required groupId,
          required eventType,
          afterSourceTimestamp,
          afterSourceEventId,
          throughSourceTimestamp,
          required limit,
        }) => dbLoadGroupEventLogTypePage(
          stack.db,
          groupId: groupId,
          eventType: eventType,
          afterSourceTimestamp: afterSourceTimestamp,
          afterSourceEventId: afterSourceEventId,
          throughSourceTimestamp: throughSourceTimestamp,
          newestFirst: true,
          limit: limit,
        ),
    loadGenesisRows:
        ({
          required groupId,
          required eventType,
          afterSourceTimestamp,
          afterSourceEventId,
          throughSourceTimestamp,
          required limit,
        }) => dbLoadGroupEventLogTypePage(
          stack.db,
          groupId: groupId,
          eventType: eventType,
          afterSourceTimestamp: afterSourceTimestamp,
          afterSourceEventId: afterSourceEventId,
          throughSourceTimestamp: throughSourceTimestamp,
          newestFirst: true,
          limit: limit,
        ),
    verify: ({required publicKey, required data, required signature}) =>
        callVerifyPayload(
          bridge: stack.bridge,
          publicKey: publicKey,
          data: data,
          signature: signature,
        ),
  );
}

Future<bool> _b1bHasPendingContentAuthority(
  GroupMultiDeviceTestStack stack,
  String groupId,
) => hasPendingProtectedGroupContentAuthority(
  groupId: groupId,
  loadPreparedPage:
      ({afterSourceTimestamp, afterSourceEventId, required limit}) =>
          loadAuthenticatedGroupAuthorityProofPage(
            loadRows:
                ({
                  required groupId,
                  required eventType,
                  afterSourceTimestamp,
                  afterSourceEventId,
                  throughSourceTimestamp,
                  required limit,
                }) => dbLoadGroupEventLogTypePage(
                  stack.db,
                  groupId: groupId,
                  eventType: eventType,
                  afterSourceTimestamp: afterSourceTimestamp,
                  afterSourceEventId: afterSourceEventId,
                  throughSourceTimestamp: throughSourceTimestamp,
                  newestFirst: true,
                  limit: limit,
                ),
            groupId: groupId,
            phase: AuthenticatedGroupAuthorityPhase.prepared,
            verify: ({required publicKey, required data, required signature}) =>
                callVerifyPayload(
                  bridge: stack.bridge,
                  publicKey: publicKey,
                  data: data,
                  signature: signature,
                ),
            afterSourceTimestamp: afterSourceTimestamp,
            afterSourceEventId: afterSourceEventId,
            limit: limit,
          ),
  loadExactPhase: ({required phase, required eventId}) =>
      loadAuthenticatedGroupAuthorityProofFromEventLog(
        loadRow: ({required groupId, required sourceEventId}) =>
            dbLoadGroupEventLogEntryExact(
              stack.db,
              groupId: groupId,
              sourceEventId: sourceEventId,
            ),
        groupId: groupId,
        phase: phase,
        eventId: eventId,
        verify: ({required publicKey, required data, required signature}) =>
            callVerifyPayload(
              bridge: stack.bridge,
              publicKey: publicKey,
              data: data,
              signature: signature,
            ),
      ),
  loadReconciliationRow: (authorityEventId) => dbLoadGroupEventLogEntryExact(
    stack.db,
    groupId: groupId,
    sourceEventId: protectedGroupContentReconciliationCompleteSourceEventId(
      authorityEventId,
    ),
  ),
);

Future<AuthenticatedGroupAuthorityProof?> _b1bLatestSettledContentAuthority(
  GroupMultiDeviceTestStack stack,
  String groupId,
) async {
  if (await _b1bHasPendingContentAuthority(stack, groupId)) return null;
  Future<AuthenticatedGroupAuthorityProof?> latest(
    AuthenticatedGroupAuthorityPhase phase,
  ) async {
    final page = await loadAuthenticatedGroupAuthorityProofPage(
      loadRows:
          ({
            required groupId,
            required eventType,
            afterSourceTimestamp,
            afterSourceEventId,
            throughSourceTimestamp,
            required limit,
          }) => dbLoadGroupEventLogTypePage(
            stack.db,
            groupId: groupId,
            eventType: eventType,
            afterSourceTimestamp: afterSourceTimestamp,
            afterSourceEventId: afterSourceEventId,
            throughSourceTimestamp: throughSourceTimestamp,
            newestFirst: true,
            limit: limit,
          ),
      groupId: groupId,
      phase: phase,
      verify: ({required publicKey, required data, required signature}) =>
          callVerifyPayload(
            bridge: stack.bridge,
            publicKey: publicKey,
            data: data,
            signature: signature,
          ),
      limit: 1,
    );
    return page.isEmpty ? null : page.single;
  }

  final complete = await latest(AuthenticatedGroupAuthorityPhase.complete);
  final genesis = await latest(AuthenticatedGroupAuthorityPhase.genesis);
  var selected = complete;
  if (selected == null ||
      (genesis != null &&
          (genesis.eventAt.isAfter(selected.eventAt) ||
              (genesis.eventAt == selected.eventAt &&
                  genesis.eventId.compareTo(selected.eventId) > 0)))) {
    selected = genesis;
  }
  if (selected == null) return null;
  if (complete != null && identical(selected, complete)) {
    final row = await dbLoadGroupEventLogEntryExact(
      stack.db,
      groupId: groupId,
      sourceEventId: protectedGroupContentReconciliationCompleteSourceEventId(
        selected.eventId,
      ),
    );
    if (!isProtectedGroupContentReconciliationCompleteRow(
      row,
      authority: selected,
    )) {
      return null;
    }
  }
  final key = await stack.groupRepo.getLatestKey(groupId);
  return key?.keyGeneration == selected.keyEpoch ? selected : null;
}

ResolveGroupContentAuthoring _b1bProductionContentAuthoringResolver(
  GroupMultiDeviceTestStack stack, {
  required void Function() onResolved,
}) => buildProtectedGroupContentAuthoringResolver(
  loadIdentity: () async {
    final identity = await stack.identityRepo.loadIdentity();
    return identity == null
        ? null
        : (peerId: identity.peerId, publicKey: identity.publicKey);
  },
  loadMember: stack.groupRepo.getMember,
  loadInstallationAuthority: (expectedAccountPeerId) =>
      LinkedInstallationAuthority(
        secureKeyStore: stack.secureKeyStore,
      ).load(expectedAccountPeerId: expectedAccountPeerId),
  loadLatestSettledAuthority: (groupId) =>
      _b1bLatestSettledContentAuthority(stack, groupId),
  readCurrentTransportPeerId: () => stack.p2pService.currentState.peerId,
  inboxStore: stack.p2pService,
  directLinkedDeviceSelector: const DirectLinkedDeviceSelector.enabled(),
  multiDeviceSyncEnabled: true,
  onResolved: onResolved,
);

int _b1bBridgeCommandCount(GroupMultiDeviceTestStack stack, String command) {
  final bridge = stack.bridge;
  if (bridge is! RecordingGoBridgeClient) {
    throw StateError('B1b requires exact native command recording');
  }
  return bridge.commandCount(command);
}

void _installB1bProtectedReplayHandler(GroupMultiDeviceTestStack stack) {
  stack.p2pService.setProtectedGroupReplayHandler((message) async {
    final authority = await _b1bLinkedAuthority(stack);
    final identity = await stack.identityRepo.loadIdentity();
    final ownMlKemPublicKey = identity?.mlKemPublicKey;
    final ownMlKemSecretKey = identity?.mlKemSecretKey;
    if (identity == null ||
        ownMlKemPublicKey == null ||
        ownMlKemSecretKey == null) {
      return _b1bReplayOutcome(
        ProtectedGroupReplayDisposition.prerequisiteWaiting,
        'identity_unavailable',
      );
    }
    Map<String, dynamic>? contentOuter;
    try {
      final decoded = jsonDecode(message.content);
      if (decoded is Map) {
        contentOuter = Map<String, dynamic>.from(decoded);
      }
    } catch (_) {
      contentOuter = null;
    }
    if (contentOuter?['custodyKind'] == groupContentCustodyKind) {
      _b1bContentIngressAuthorityGateInvocations++;
      final contentGroupId = contentOuter?['groupId'];
      if (contentGroupId is String &&
          contentGroupId.isNotEmpty &&
          await _b1bHasPendingContentAuthority(stack, contentGroupId)) {
        return _b1bReplayOutcome(
          ProtectedGroupReplayDisposition.prerequisiteWaiting,
          'authority_reconciliation_pending',
        );
      }
      final localTransportPeerId = authority.isActiveLinkedSecondary
          ? authority.credential!.transportPeerId
          : identity.peerId;
      final result = await handleProtectedGroupContentReplay(
        bridge: stack.bridge,
        groupRepository: stack.groupRepo,
        message: message,
        localLogicalPeerId: identity.peerId,
        localTransportPeerId: localTransportPeerId,
        loadAuthority: (groupId, version) =>
            _b1bLoadContentAuthority(stack, groupId, version),
        hasPendingAuthority: (groupId) async {
          _b1bContentIngressAuthorityGateInvocations++;
          return _b1bHasPendingContentAuthority(stack, groupId);
        },
        hasTerminal:
            ({
              required groupId,
              required payloadType,
              required contentEventId,
            }) => hasProtectedGroupContentTerminalEvidence(
              groupId: groupId,
              payloadType: payloadType,
              contentEventId: contentEventId,
              loadRows:
                  ({
                    required groupId,
                    required eventType,
                    afterSourceTimestamp,
                    afterSourceEventId,
                    throughSourceTimestamp,
                    required limit,
                  }) => dbLoadGroupEventLogTypePage(
                    stack.db,
                    groupId: groupId,
                    eventType: eventType,
                    afterSourceTimestamp: afterSourceTimestamp,
                    afterSourceEventId: afterSourceEventId,
                    throughSourceTimestamp: throughSourceTimestamp,
                    newestFirst: true,
                    limit: limit,
                  ),
            ),
        commitMessage:
            ({
              required groupId,
              required sourcePeerId,
              required sourceEventId,
              required sourceTimestamp,
              required eventPayload,
              required messageRow,
              required mediaAttachmentRows,
              required incomingMediaCustodyRows,
              readyDisplayOutboxRow,
            }) => dbCommitProtectedGroupMessage(
              stack.db,
              groupId: groupId,
              sourcePeerId: sourcePeerId,
              sourceEventId: sourceEventId,
              sourceTimestamp: sourceTimestamp,
              eventPayload: eventPayload,
              messageRow: messageRow,
              mediaAttachmentRows: mediaAttachmentRows,
              incomingMediaCustodyRows: incomingMediaCustodyRows,
              readyDisplayOutboxRow: readyDisplayOutboxRow,
            ),
        commitReaction:
            ({
              required groupId,
              required sourcePeerId,
              required sourceEventId,
              required sourceTimestamp,
              required eventPayload,
              required reactionRow,
              required transitionId,
              required action,
              readyDisplayOutboxRow,
            }) => dbCommitProtectedGroupReaction(
              stack.db,
              groupId: groupId,
              sourcePeerId: sourcePeerId,
              sourceEventId: sourceEventId,
              sourceTimestamp: sourceTimestamp,
              eventPayload: eventPayload,
              reactionRow: reactionRow,
              transitionId: transitionId,
              action: action,
              readyDisplayOutboxRow: readyDisplayOutboxRow,
            ),
        commitTerminal:
            ({
              required groupId,
              required sourcePeerId,
              required sourceEventId,
              required sourceTimestamp,
              required eventPayload,
            }) => dbCommitProtectedGroupContentTerminal(
              stack.db,
              groupId: groupId,
              sourcePeerId: sourcePeerId,
              sourceEventId: sourceEventId,
              sourceTimestamp: sourceTimestamp,
              eventPayload: eventPayload,
            ),
        resolveReactionTarget: (groupId, messageId) async {
          final target = await dbClassifyProtectedGroupReactionTarget(
            stack.db,
            groupId: groupId,
            messageId: messageId,
          );
          if (target !=
              ProtectedGroupReactionTargetDisposition.prerequisiteWaiting) {
            return target;
          }
          final deletion = await dbLoadGroupMessageLocalDeletion(
            stack.db,
            messageId,
          );
          if (deletion?['group_id'] == groupId) {
            return ProtectedGroupReactionTargetDisposition.terminal;
          }
          final terminalRows = await dbLoadGroupEventLogTypePage(
            stack.db,
            groupId: groupId,
            eventType: protectedGroupContentTerminalEventType,
            newestFirst: true,
            limit: 200,
          );
          for (final terminal in terminalRows) {
            final raw = terminal['canonical_payload'];
            if (raw is! String) continue;
            try {
              final decoded = jsonDecode(raw);
              if (decoded is Map &&
                  decoded['payloadType'] ==
                      groupOfflineReplayPayloadTypeMessage &&
                  decoded['contentEventId'] == messageId) {
                return ProtectedGroupReactionTargetDisposition.terminal;
              }
            } catch (_) {}
          }
          return ProtectedGroupReactionTargetDisposition.prerequisiteWaiting;
        },
        buildMessageDisplayRow:
            stack.groupListener.buildProtectedMessageDisplayReadyRow,
        buildReactionDisplayRow:
            stack.groupListener.buildProtectedReactionDisplayReadyRow,
        publishMessage: stack.groupListener.publishProtectedGroupMessage,
        publishReaction:
            stack.groupListener.publishProtectedGroupReactionChange,
      );
      return switch (result.disposition) {
        ProtectedGroupContentApplyDisposition.applied => _b1bReplayOutcome(
          ProtectedGroupReplayDisposition.applied,
          result.reasonCode,
        ),
        ProtectedGroupContentApplyDisposition.exactDuplicate =>
          _b1bReplayOutcome(
            ProtectedGroupReplayDisposition.duplicate,
            result.reasonCode,
          ),
        ProtectedGroupContentApplyDisposition.terminalReject =>
          _b1bReplayOutcome(
            ProtectedGroupReplayDisposition.terminalRejected,
            result.reasonCode,
          ),
        ProtectedGroupContentApplyDisposition.unverifiedReject =>
          _b1bReplayOutcome(
            ProtectedGroupReplayDisposition.unverifiedRejected,
            result.reasonCode,
          ),
        ProtectedGroupContentApplyDisposition.prerequisiteWaiting =>
          _b1bReplayOutcome(
            ProtectedGroupReplayDisposition.prerequisiteWaiting,
            result.reasonCode,
          ),
        ProtectedGroupContentApplyDisposition.retryableFailure =>
          _b1bReplayOutcome(
            ProtectedGroupReplayDisposition.retryable,
            result.reasonCode,
          ),
      };
    }
    final outer = ProtectedGroupEnvelope.tryParse(message.content);
    if (outer?.type == linkedGroupBootstrapEnvelopeType) {
      final result = await handleLinkedGroupBootstrapEnvelope(
        message: message,
        linkedAuthority: authority,
        ownMlKemPublicKey: ownMlKemPublicKey,
        ownMlKemSecretKey: ownMlKemSecretKey,
        groupRepository: stack.groupRepo,
        callDecrypt:
            ({
              required ownMlKemSecretKey,
              required kem,
              required ciphertext,
              required nonce,
            }) => callDecryptMessage(
              bridge: stack.bridge,
              ownMlKemSecretKey: ownMlKemSecretKey,
              kem: kem,
              ciphertext: ciphertext,
              nonce: nonce,
            ),
        callVerify: ({required publicKey, required data, required signature}) =>
            callVerifyPayload(
              bridge: stack.bridge,
              publicKey: publicKey,
              data: data,
              signature: signature,
            ),
      );
      return switch (result) {
        HandleLinkedGroupBootstrapResult.applied => _b1bReplayOutcome(
          ProtectedGroupReplayDisposition.applied,
          'bootstrap_applied',
        ),
        HandleLinkedGroupBootstrapResult.duplicate => _b1bReplayOutcome(
          ProtectedGroupReplayDisposition.duplicate,
          'bootstrap_duplicate',
        ),
        HandleLinkedGroupBootstrapResult.terminalRejected => _b1bReplayOutcome(
          ProtectedGroupReplayDisposition.terminalRejected,
          'bootstrap_rejected',
        ),
        HandleLinkedGroupBootstrapResult.retryable => _b1bReplayOutcome(
          ProtectedGroupReplayDisposition.retryable,
          'bootstrap_retryable',
        ),
      };
    }
    if (outer?.type != protectedGroupAuthorityEnvelopeType) {
      return _b1bReplayOutcome(
        ProtectedGroupReplayDisposition.terminalRejected,
        'unsupported_protected_type',
      );
    }
    final result = await handleProtectedGroupAuthority(
      message: message,
      ownTransportPeerId: authority.isActiveLinkedSecondary
          ? authority.credential!.transportPeerId
          : identity.peerId,
      ownMlKemSecretKey: ownMlKemSecretKey,
      groupRepository: stack.groupRepo,
      callDecrypt:
          ({
            required ownMlKemSecretKey,
            required kem,
            required ciphertext,
            required nonce,
          }) => callDecryptMessage(
            bridge: stack.bridge,
            ownMlKemSecretKey: ownMlKemSecretKey,
            kem: kem,
            ciphertext: ciphertext,
            nonce: nonce,
          ),
      callVerify: ({required publicKey, required data, required signature}) =>
          callVerifyPayload(
            bridge: stack.bridge,
            publicKey: publicKey,
            data: data,
            signature: signature,
          ),
      loadAuthorityProof:
          ({required groupId, required phase, required eventId}) =>
              loadAuthenticatedGroupAuthorityProofFromEventLog(
                loadRow: ({required groupId, required sourceEventId}) =>
                    dbLoadGroupEventLogEntryExact(
                      stack.db,
                      groupId: groupId,
                      sourceEventId: sourceEventId,
                    ),
                groupId: groupId,
                phase: phase,
                eventId: eventId,
                verify:
                    ({required publicKey, required data, required signature}) =>
                        callVerifyPayload(
                          bridge: stack.bridge,
                          publicKey: publicKey,
                          data: data,
                          signature: signature,
                        ),
              ),
      appendAuthorityProof: ({required phase, required proof}) async {
        await dbAppendGroupEventLogEntry(
          stack.db,
          groupId: proof.groupId,
          eventType: phase.eventType,
          sourcePeerId: proof.actorAccountPeerId,
          sourceEventId: authenticatedGroupAuthoritySourceEventId(
            phase,
            proof.eventId,
          ),
          sourceTimestamp: fixedGroupAuthorityUtc(proof.eventAt),
          payload: authenticatedGroupAuthorityFactPayload(proof),
        );
      },
      applyReplay: (control, replayData, _) async {
        if (control != ProtectedGroupAuthorityControl.groupDissolve) {
          return ProtectedGroupAuthorityApplyResult.rejected;
        }
        final groupId = replayData['groupId'];
        final dissolvedAtRaw = replayData['dissolvedAt'];
        final dissolvedBy = replayData['dissolvedBy'];
        if (groupId is! String ||
            dissolvedAtRaw is! String ||
            dissolvedBy is! String) {
          return ProtectedGroupAuthorityApplyResult.rejected;
        }
        final group = await stack.groupRepo.getGroup(groupId);
        if (group == null) {
          return ProtectedGroupAuthorityApplyResult.retryable;
        }
        if (group.isDissolved) {
          return ProtectedGroupAuthorityApplyResult.duplicate;
        }
        final dissolvedAt = DateTime.tryParse(dissolvedAtRaw)?.toUtc();
        if (dissolvedAt == null) {
          return ProtectedGroupAuthorityApplyResult.rejected;
        }
        await stack.groupRepo.saveGroup(
          group.copyWith(
            isDissolved: true,
            dissolvedAt: dissolvedAt,
            dissolvedBy: dissolvedBy,
            lastMembershipEventAt: dissolvedAt,
          ),
        );
        return ProtectedGroupAuthorityApplyResult.applied;
      },
      reconcileContent: (control, replayData, verifiedAuthority) async {
        if (control != verifiedAuthority.control || replayData.isEmpty) {
          return false;
        }
        _b1bAuthorityReconcileInvocations++;
        return reconcileProtectedGroupContentForAuthority(
          db: stack.db,
          groupRepository: stack.groupRepo,
          authority: verifiedAuthority.proof,
          terminalizePreparedContent:
              ({
                required txn,
                required groupId,
                required payloadType,
                required contentEventId,
                required ownerKind,
                required ownerId,
                required eventPayload,
                required terminalSourcePeerId,
                required terminalSourceEventId,
                required terminalSourceTimestamp,
                required terminalEventPayload,
                mediaKeySnapshot,
              }) async {
                if (ownerId != contentEventId) return false;
                if (payloadType == groupOfflineReplayPayloadTypeMessage &&
                    ownerKind == 'group_message') {
                  final rows = await txn.query(
                    'group_messages',
                    where: 'id = ? AND group_id = ?',
                    whereArgs: <Object?>[ownerId, groupId],
                    limit: 1,
                  );
                  return rows.isNotEmpty &&
                      await dbTerminalizePreparedLocalGroupContentMessageIfExactInTransaction(
                        txn,
                        expected: rows.single,
                        preparedEventPayload: eventPayload,
                        terminalSourcePeerId: terminalSourcePeerId,
                        terminalSourceEventId: terminalSourceEventId,
                        terminalSourceTimestamp: terminalSourceTimestamp,
                        terminalEventPayload: terminalEventPayload,
                        mediaKeySnapshot: mediaKeySnapshot,
                      );
                }
                if (payloadType == groupOfflineReplayPayloadTypeReaction &&
                    ownerKind == 'group_reaction') {
                  final rows = await txn.query(
                    'group_reaction_replay_outbox',
                    where: 'reaction_id = ? AND group_id = ?',
                    whereArgs: <Object?>[ownerId, groupId],
                    limit: 1,
                  );
                  return rows.isNotEmpty &&
                      await dbTerminalizePreparedLocalGroupReactionIfExactInTransaction(
                        txn,
                        expected: rows.single,
                        preparedEventPayload: eventPayload,
                        terminalSourcePeerId: terminalSourcePeerId,
                        terminalSourceEventId: terminalSourceEventId,
                        terminalSourceTimestamp: terminalSourceTimestamp,
                        terminalEventPayload: terminalEventPayload,
                      );
                }
                return false;
              },
          validateHistoricalAuthority:
              ({
                required groupId,
                required payloadType,
                required contentEventId,
                required eventAt,
                required authorityVersion,
                required logicalSenderPeerId,
                required senderDeviceId,
                required senderTransportPeerId,
                required senderPublicKey,
              }) async {
                final historical = await _b1bLoadContentAuthority(
                  stack,
                  groupId,
                  authorityVersion,
                );
                return historical?.authorizesHistoricalContent(
                      payloadType: payloadType,
                      contentEventId: contentEventId,
                      eventAt: eventAt,
                      logicalSenderPeerId: logicalSenderPeerId,
                      senderDeviceId: senderDeviceId,
                      senderTransportPeerId: senderTransportPeerId,
                      senderPublicKey: senderPublicKey,
                    ) ==
                    true;
              },
          mediaKeyAccess: GroupMediaKeyAccess(
            secureKeyStore: stack.secureKeyStore,
          ),
        );
      },
    );
    return switch (result) {
      ProtectedGroupAuthorityHandleResult.applied => _b1bReplayOutcome(
        ProtectedGroupReplayDisposition.applied,
        'authority_applied',
      ),
      ProtectedGroupAuthorityHandleResult.duplicate => _b1bReplayOutcome(
        ProtectedGroupReplayDisposition.duplicate,
        'authority_duplicate',
      ),
      ProtectedGroupAuthorityHandleResult.terminalRejected => _b1bReplayOutcome(
        ProtectedGroupReplayDisposition.terminalRejected,
        'authority_rejected',
      ),
      ProtectedGroupAuthorityHandleResult.retryable => _b1bReplayOutcome(
        ProtectedGroupReplayDisposition.retryable,
        'authority_retryable',
      ),
      ProtectedGroupAuthorityHandleResult.prerequisiteWaiting =>
        _b1bReplayOutcome(
          ProtectedGroupReplayDisposition.prerequisiteWaiting,
          'bootstrap_required',
        ),
    };
  });
}

GroupPendingBroadcastRunner _b1bProtectedRunner(
  GroupMultiDeviceTestStack stack,
) {
  setReconcileCompletedProtectedGroupAuthority(stack.groupRepo, (
    authority,
  ) async {
    _b1bLocalAuthorityReconcileInvocations++;
    return reconcileProtectedGroupContentForAuthority(
      db: stack.db,
      groupRepository: stack.groupRepo,
      authority: authority,
      validateHistoricalAuthority:
          ({
            required groupId,
            required payloadType,
            required contentEventId,
            required eventAt,
            required authorityVersion,
            required logicalSenderPeerId,
            required senderDeviceId,
            required senderTransportPeerId,
            required senderPublicKey,
          }) async {
            final historical = await _b1bLoadContentAuthority(
              stack,
              groupId,
              authorityVersion,
            );
            return historical?.authorizesHistoricalContent(
                  payloadType: payloadType,
                  contentEventId: contentEventId,
                  eventAt: eventAt,
                  logicalSenderPeerId: logicalSenderPeerId,
                  senderDeviceId: senderDeviceId,
                  senderTransportPeerId: senderTransportPeerId,
                  senderPublicKey: senderPublicKey,
                ) ==
                true;
          },
      mediaKeyAccess: GroupMediaKeyAccess(secureKeyStore: stack.secureKeyStore),
    );
  });
  return GroupPendingBroadcastRunner(
    repository: stack.groupPendingBroadcastRepo,
    rePush: (_) async => false,
    protectedInboxStore: stack.p2pService,
    pendingSiblingDeviceRepository: stack.groupRepo,
    linkedGroupBootstrapRepository: stack.groupRepo,
    finalizeProtectedDissolve: (broadcast) {
      final identity = parseProtectedGroupAuthorityDeliveryId(
        broadcast.sourceMessageId ?? '',
      );
      if (identity == null ||
          identity.control != ProtectedGroupAuthorityControl.groupDissolve) {
        return Future<bool>.value(false);
      }
      return recoverPreparedProtectedGroupDissolve(
        groupId: broadcast.groupId,
        eventId: identity.transitionId,
        groupRepository: stack.groupRepo,
        pendingRepository: stack.groupPendingBroadcastRepo,
        protectedInboxStore: stack.p2pService,
        pendingSiblingDeviceRepository: stack.groupRepo,
        loadAuthorityProof:
            ({required groupId, required phase, required eventId}) =>
                loadAuthenticatedGroupAuthorityProofFromEventLog(
                  loadRow: ({required groupId, required sourceEventId}) =>
                      dbLoadGroupEventLogEntryExact(
                        stack.db,
                        groupId: groupId,
                        sourceEventId: sourceEventId,
                      ),
                  groupId: groupId,
                  phase: phase,
                  eventId: eventId,
                  verify:
                      ({
                        required publicKey,
                        required data,
                        required signature,
                      }) => callVerifyPayload(
                        bridge: stack.bridge,
                        publicKey: publicKey,
                        data: data,
                        signature: signature,
                      ),
                ),
      );
    },
  );
}

List<int> _b1bPlan365JpegBytes() => <int>[
  0xff,
  0xd8,
  0xff,
  0xe0,
  0x00,
  0x10,
  ...List<int>.generate(58, (index) => (index * 17) & 0xff),
];

List<int> _b1bPlan365VoiceBytes() => <int>[
  0x00,
  0x00,
  0x00,
  0x18,
  0x66,
  0x74,
  0x79,
  0x70,
  0x6d,
  0x70,
  0x34,
  0x32,
  0x00,
  0x00,
  0x00,
  0x00,
  ...List<int>.generate(48, (index) => (0xa5 + index) & 0xff),
];

int _b1bGroupMediaBridgeCommandCount(
  GroupMultiDeviceTestStack stack,
  String command, {
  required bool strict,
}) {
  final bridge = stack.bridge;
  if (bridge is! RecordingGoBridgeClient) {
    throw StateError('B1b requires exact native command recording');
  }
  var count = 0;
  for (final raw in bridge.sentMessages) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map || decoded['cmd'] != command) continue;
      final payload = decoded['payload'];
      if (payload is! Map) continue;
      final isStrict =
          payload['custodyKind'] == groupMediaBlobCustodyKind &&
          payload['custodyContract'] == groupMediaBlobCustodyContract;
      final isLegacy = payload.containsKey('allowedPeers');
      if ((strict && isStrict) || (!strict && isLegacy)) count++;
    } catch (_) {}
  }
  return count;
}

Future<Map<String, dynamic>> _b1bAuthorPlan365MediaAndVoice({
  required GroupMultiDeviceTestStack stack,
  required String groupId,
}) async {
  final idScope = sha256
      .convert(utf8.encode(configuredRunId))
      .toString()
      .substring(0, 12);
  final coordinator = PreparedGroupMediaBlobCustodyCoordinator(
    artifactStore: GroupMediaBlobArtifactStore(),
  );
  final strictUploadsBefore = _b1bGroupMediaBridgeCommandCount(
    stack,
    'media:upload',
    strict: true,
  );
  final legacyUploadsBefore = _b1bGroupMediaBridgeCommandCount(
    stack,
    'media:upload',
    strict: false,
  );

  Future<Map<String, dynamic>> author({
    required String modality,
    required String mime,
    required List<int> bytes,
    required String text,
    int? durationMs,
    List<double>? waveform,
  }) async {
    final messageId = 'b1b-365-$idScope-$modality';
    final attachmentId = 'b1b-365-$idScope-$modality-blob';
    final source = File(
      '${Directory.systemTemp.path}/b1b-365-$idScope-$modality.source',
    );
    await source.writeAsBytes(bytes, flush: true);
    final storedPath = await stack.mediaFileManager.copyToDurableStorage(
      sourceFilePath: source.path,
      messageId: messageId,
      attachmentId: attachmentId,
      mime: mime,
    );
    final plaintextPath = await stack.mediaFileManager.resolveStoredPath(
      storedPath,
    );
    final authoredAt = DateTime.now().toUtc();
    final parent = GroupMessage(
      id: messageId,
      groupId: groupId,
      senderPeerId: stack.identity.peerId,
      senderUsername: stack.identity.username,
      text: text,
      timestamp: authoredAt,
      status: GroupMessage.statusQueuedOffline,
      isIncoming: false,
      createdAt: authoredAt,
    );
    final attachment = MediaAttachment(
      id: attachmentId,
      messageId: messageId,
      mime: mime,
      size: bytes.length,
      mediaType: modality == 'voice' ? 'audio' : 'image',
      width: modality == 'image' ? 8 : null,
      height: modality == 'image' ? 8 : null,
      durationMs: durationMs,
      waveform: waveform,
      localPath: storedPath,
      downloadStatus: 'upload_pending',
      createdAt: authoredAt.toIso8601String(),
      ownerLane: MediaOwnerLane.group,
    );
    // Preserve the existing send failure reason before debugPrint's buffered
    // output is lost when the device test ends. Capture only closed labels.
    var mediaTimingMatches = 0;
    var mediaSendOutcome = 'unobserved';
    var mediaSendReason = 'unobserved';
    const observedOutcomes = <String>{
      'unauthorized',
      'strict_custody_complete',
    };
    const observedReasons = <String>{
      'strict_group_content_authority_unavailable',
      'strict_group_content_not_qualified',
      'strict_group_content_order_invalid',
      'strict_group_content_missing_credential',
      'strict_group_content_ambiguous_sender_binding',
      'strict_group_media_manifest_mismatch',
      'strict_group_content_crypto_failed',
    };
    final observation = installScopedE2EFlowEventSink((event) {
      if (event['event'] != 'GROUP_SEND_MSG_TIMING') return;
      final details = event['details'];
      if (details is! Map || details['hasMedia'] != true) return;
      if (mediaTimingMatches > 0) {
        mediaTimingMatches = 2; // Saturated: two or more events are ambiguous.
        mediaSendOutcome = 'ambiguous';
        mediaSendReason = 'ambiguous';
        return;
      }
      mediaTimingMatches = 1;
      final outcome = details['outcome'];
      final reason = details['reason'];
      mediaSendOutcome = outcome is String && observedOutcomes.contains(outcome)
          ? outcome
          : 'unclassified';
      mediaSendReason = reason == null
          ? 'none'
          : reason is String && observedReasons.contains(reason)
          ? reason
          : 'unclassified';
    });
    late PreparedGroupMediaSendResult result;
    try {
      result = await coordinator.prepareAndSend(
        bridge: stack.bridge,
        groupRepository: stack.groupRepo,
        messageRepository: stack.groupMsgRepo,
        mediaAttachmentRepository: stack.mediaAttachmentRepo,
        identityPeerId: stack.identity.peerId,
        senderPublicKey: stack.identity.publicKey,
        senderPrivateKey: stack.identity.privateKey,
        senderUsername: stack.identity.username,
        senderDeviceId: stack.identity.peerId,
        senderTransportPeerId: stack.identity.peerId,
        parent: parent,
        sources: <PreparedGroupMediaBlobSource>[
          PreparedGroupMediaBlobSource(
            attachment: attachment,
            plaintextPath: plaintextPath,
          ),
        ],
        inviteDeliveryAttemptRepository: stack.groupInviteDeliveryAttemptRepo,
      );
    } finally {
      observation.release();
    }
    final failureContext =
        '$modality; timingMatchesCappedAt2=$mediaTimingMatches; '
        'sendOutcome=$mediaSendOutcome; sendReason=$mediaSendReason';
    expect(result.preparation.isComplete, isTrue, reason: failureContext);
    expect(
      result.sendResult,
      SendGroupMessageResult.success,
      reason: failureContext,
    );
    expect(result.message?.status, 'sent', reason: modality);
    final completed = result.preparation.attachments.single;
    expect(completed.groupMediaBlobCustodyFingerprint, isNotNull);
    expect(completed.downloadStatus, 'done');
    return <String, dynamic>{
      'messageId': messageId,
      'attachmentId': attachmentId,
      'mime': mime,
      'plaintextSha256': sha256.convert(bytes).toString(),
      'plaintextSize': bytes.length,
    };
  }

  final image = await author(
    modality: 'image',
    mime: 'image/jpeg',
    bytes: _b1bPlan365JpegBytes(),
    text: 'B1b Plan 365 deterministic image',
  );
  final voice = await author(
    modality: 'voice',
    mime: 'audio/mp4',
    bytes: _b1bPlan365VoiceBytes(),
    text: '',
    durationMs: 960,
    waveform: const <double>[0.0, 0.5, 1.0, 0.5, 0.0],
  );
  final strictUploadActions =
      _b1bGroupMediaBridgeCommandCount(stack, 'media:upload', strict: true) -
      strictUploadsBefore;
  final legacyUploadActions =
      _b1bGroupMediaBridgeCommandCount(stack, 'media:upload', strict: false) -
      legacyUploadsBefore;
  expect(strictUploadActions, 2);
  expect(legacyUploadActions, 0);
  return <String, dynamic>{
    'groupId': groupId,
    'image': image,
    'voice': voice,
    'productionPreparedCoordinatorInvoked': true,
    'strictUploadActionsObserved': strictUploadActions == 2,
    'zeroLegacyAllowedPeersUploads': legacyUploadActions == 0,
  };
}

Future<Map<String, dynamic>> _b1bRecoverPlan365MediaAndVoice({
  required GroupMultiDeviceTestStack stack,
  required String groupId,
  required Map<String, dynamic> fixture,
}) async {
  final descriptors = <Map<String, dynamic>>[
    Map<String, dynamic>.from(fixture['image'] as Map),
    Map<String, dynamic>.from(fixture['voice'] as Map),
  ];
  await waitForCondition(() async {
    _b1bPlan365RestrictedFixedPointInvocations++;
    await stack.p2pService.drainProtectedGroupContentFixedPoint();
    for (final descriptor in descriptors) {
      final messageId = descriptor['messageId'] as String;
      final message = await stack.groupMsgRepo.getMessage(messageId);
      final attachments = await stack.mediaAttachmentRepo
          .getAttachmentsForMessage(messageId, owner: MediaOwnerLane.group);
      if (message == null || attachments.length != 1) return false;
      final attachment = attachments.single;
      if (attachment.id != descriptor['attachmentId'] ||
          attachment.groupMediaBlobCustodyFingerprint?.isNotEmpty != true ||
          attachment.downloadStatus != 'pending') {
        return false;
      }
    }
    return true;
  }, timeout: const Duration(minutes: 3));

  final owner = StrictGroupMediaBlobDownloadAckOwner(
    bridge: stack.bridge,
    mediaAttachmentRepository: stack.mediaAttachmentRepo,
    mediaFileManager: stack.mediaFileManager,
  );
  final downloadBefore = _b1bGroupMediaBridgeCommandCount(
    stack,
    'media:download',
    strict: true,
  );
  final deleteBefore = _b1bGroupMediaBridgeCommandCount(
    stack,
    'media:delete',
    strict: true,
  );
  for (final descriptor in descriptors) {
    final messageId = descriptor['messageId'] as String;
    final attachment =
        (await stack.mediaAttachmentRepo.getAttachmentsForMessage(
          messageId,
          owner: MediaOwnerLane.group,
        )).single;
    final recordingBridge = stack.bridge as RecordingGoBridgeClient;
    final sentStart = recordingBridge.sentMessages.length;
    final exchangeStart = recordingBridge.bridgeExchanges.length;
    final downloaded = await owner.downloadAndAcknowledge(
      attachment: attachment,
      groupId: groupId,
    );
    // The fatal assertion uses synchronous print; buffered flow events can be
    // lost when Flutter terminates the integration-test app after a failure.
    final observation = summarizeGroupMediaDownloadObservation(
      sentMessages: recordingBridge.sentMessages,
      bridgeExchanges: recordingBridge.bridgeExchanges,
      sentStart: sentStart,
      exchangeStart: exchangeStart,
    );
    expect(downloaded, isNotNull, reason: jsonEncode(observation));
    expect(downloaded!.downloadStatus, 'done');
    expect(downloaded.groupMediaBlobCustodyFingerprint, isNotNull);
    final localPath = await stack.mediaFileManager.resolveStoredPath(
      downloaded.localPath!,
    );
    final localBytes = await File(localPath).readAsBytes();
    expect(localBytes.length, descriptor['plaintextSize']);
    expect(
      sha256.convert(localBytes).toString(),
      descriptor['plaintextSha256'],
    );
  }
  await waitForCondition(() async {
    await owner.retryPendingAcknowledgements();
    for (final descriptor in descriptors) {
      final rows = await stack.mediaAttachmentRepo
          .loadGroupMediaBlobCustodyForMessage(
            groupId: groupId,
            messageId: descriptor['messageId'] as String,
          );
      if (rows.isNotEmpty) return false;
    }
    return true;
  }, timeout: const Duration(minutes: 2));

  final strictDownloads =
      _b1bGroupMediaBridgeCommandCount(stack, 'media:download', strict: true) -
      downloadBefore;
  final strictDeletes =
      _b1bGroupMediaBridgeCommandCount(stack, 'media:delete', strict: true) -
      deleteBefore;
  expect(strictDownloads, 2);
  expect(strictDeletes, greaterThanOrEqualTo(2));
  return <String, dynamic>{
    'groupId': groupId,
    'imageMessageId': (fixture['image'] as Map)['messageId'],
    'voiceMessageId': (fixture['voice'] as Map)['messageId'],
    'fingerprintedDescriptorsVerified': true,
    'localPlaintextBytesVerified': true,
    'strictBlobAckConverged': true,
    'productionDownloadOwnerInvoked': true,
    'restrictedFixedPointInvoked':
        _b1bPlan365RestrictedFixedPointInvocations > 0,
    'strictDownloadActionsObserved': strictDownloads == 2,
    'strictDeleteActionsObserved': strictDeletes >= 2,
  };
}

Future<void> _runB1bConvergencePrimary() async {
  final dbName = _dbNameForRole();
  var stack = await setupGroupMultiDeviceStack(
    dbName: dbName,
    username: 'B1b Linked Secondary',
    cliPeerFixture: null,
    setupAsLinkedSecondary: true,
    restrictedLinkedRuntime: true,
  );
  var deleteStorage = true;
  Map<String, dynamic>? plan365LinkedProof;
  try {
    expect(await stack.groupRepo.getAllGroups(), isEmpty);
    await _waitForDirectRelayReady(stack);
    final authority = await _b1bLinkedAuthority(stack);
    expect(authority.isActiveLinkedSecondary, isTrue);
    final (qrResult, qrDocument) = await buildDirectLinkedDeviceQr(
      linkedAuthority: authority,
      accountPeerId: stack.identity.peerId,
      accountPublicKey: stack.identity.publicKey,
      accountPrivateKey: stack.identity.privateKey,
      deviceMlKemPublicKey: stack.identity.mlKemPublicKey,
      callSign: (data, privateKey) => callSignPayload(
        bridge: stack.bridge,
        dataToSign: data,
        privateKey: privateKey,
      ),
      selector: const DirectLinkedDeviceSelector.enabled(),
    );
    expect(qrResult, BuildDirectLinkedDeviceQrResult.success);
    expect(qrDocument, isNotNull);
    writeSharedJson(_signalName('linked_bootstrap_fixture.json'), {
      'accountPeerId': stack.identity.peerId,
      'mnemonic12': stack.identity.mnemonic12,
      'linkedTransportPeerId': authority.credential!.transportPeerId,
      'qrDocument': qrDocument,
    });
    _installB1bProtectedReplayHandler(stack);

    final authored = await waitForSharedJson(
      _signalName('bootstrap_authored.json'),
      timeout: const Duration(minutes: 12),
    );
    final groupId = authored['groupId'] as String;
    await waitForCondition(() async {
      try {
        await stack.p2pService.drainOfflineInbox();
      } catch (_) {}
      return await stack.groupRepo.getGroup(groupId) != null &&
          await stack.groupRepo.getLatestKey(groupId) != null;
    }, timeout: const Duration(minutes: 3));
    final materialized = await stack.groupRepo.getGroup(groupId);
    expect(materialized, isNotNull);
    expect(materialized!.myRole, GroupRole.admin);
    expect(materialized.isDissolved, isFalse);
    writeSharedText(_signalName('bootstrap_materialized'), 'ok');

    final stableTransport = authority.credential!.transportPeerId;
    await stack.teardown(deleteStorage: false);
    deleteStorage = false;
    stack = await setupGroupMultiDeviceStack(
      dbName: dbName,
      username: 'B1b Linked Secondary',
      cliPeerFixture: null,
      deleteExistingDb: false,
      reuseExistingIdentity: true,
      setupAsLinkedSecondary: true,
      restrictedLinkedRuntime: true,
      startGroupTopicsOnReuse: false,
    );
    deleteStorage = true;
    await _waitForDirectRelayReady(stack);
    final reopenedAuthority = await _b1bLinkedAuthority(stack);
    expect(reopenedAuthority.credential!.transportPeerId, stableTransport);
    expect(await stack.groupRepo.getGroup(groupId), isNotNull);
    expect(await stack.groupRepo.getLatestKey(groupId), isNotNull);
    _installB1bProtectedReplayHandler(stack);
    writeSharedText(_signalName('linked_reopened'), 'ok');

    // Keep the linked physical recipient offline for every strict custody
    // authoring step. The ordinary emulator never gets a topic/pubsub escape
    // hatch: each accepted relay row is drained through the protected content
    // fixed point before the existing terminal authority is authored.
    expect(await stack.p2pService.stopNode(), isTrue);
    writeSharedText(_signalName('content_recipient_offline'), 'ok');
    final contentFixture = await waitForSharedJson(
      _signalName('content_message_custody_stored.json'),
      timeout: const Duration(minutes: 5),
    );
    final contentMessageId = contentFixture['messageId'] as String;
    final contentText = contentFixture['text'] as String;
    expect(
      await stack.p2pService.startNode(
        reopenedAuthority.credential!.transportPrivateKey,
        stableTransport,
      ),
      isTrue,
    );
    await _waitForDirectRelayReady(stack);
    await waitForCondition(() async {
      await stack.p2pService.drainProtectedGroupContentFixedPoint();
      return await stack.groupMsgRepo.getMessage(contentMessageId) != null;
    }, timeout: const Duration(minutes: 3));
    final receivedContent = await stack.groupMsgRepo.getMessage(
      contentMessageId,
    );
    expect(receivedContent, isNotNull);
    expect(receivedContent!.groupId, groupId);
    expect(receivedContent.senderPeerId, stack.identity.peerId);
    expect(receivedContent.transportPeerId, isNot(stableTransport));
    expect(receivedContent.text, contentText);
    expect(receivedContent.media, isEmpty);
    expect(receivedContent.quotedMessageId, isNull);
    expect(receivedContent.isForwarded, isFalse);
    expect(receivedContent.privateMediaPolicy.isOrdinary, isTrue);
    expect(
      await stack.mediaAttachmentRepo.getAttachmentsForMessage(
        contentMessageId,
        owner: MediaOwnerLane.group,
      ),
      isEmpty,
    );
    final contentEvent = await dbLoadGroupEventLogEntryExact(
      stack.db,
      groupId: groupId,
      sourceEventId: protectedGroupMessageSourceEventId(contentMessageId),
    );
    expect(contentEvent?['event_type'], protectedGroupMessageEventType);
    writeSharedText(_signalName('content_message_applied'), 'ok');

    expect(await stack.p2pService.stopNode(), isTrue);
    writeSharedText(_signalName('reaction_add_recipient_offline'), 'ok');
    final addFixture = await waitForSharedJson(
      _signalName('reaction_add_custody_stored.json'),
      timeout: const Duration(minutes: 5),
    );
    final addTransitionId = addFixture['transitionId'] as String;
    expect(GroupReactionTransitionOrder.tryParse(addTransitionId), isNotNull);
    expect(
      await stack.p2pService.startNode(
        reopenedAuthority.credential!.transportPrivateKey,
        stableTransport,
      ),
      isTrue,
    );
    await _waitForDirectRelayReady(stack);
    await waitForCondition(() async {
      await stack.p2pService.drainProtectedGroupContentFixedPoint();
      final reaction = await stack.reactionRepo
          .getReactionForSenderIncludingRemoved(
            messageId: contentMessageId,
            senderPeerId: stack.identity.peerId,
          );
      return reaction != null && !reaction.isRemoved;
    }, timeout: const Duration(minutes: 3));
    final added = await stack.reactionRepo.getReactionForSenderIncludingRemoved(
      messageId: contentMessageId,
      senderPeerId: stack.identity.peerId,
    );
    expect(added, isNotNull);
    expect(added!.emoji, addFixture['emoji']);
    expect(added.isRemoved, isFalse);
    final addEvent = await dbLoadGroupEventLogEntryExact(
      stack.db,
      groupId: groupId,
      sourceEventId: protectedGroupReactionSourceEventId(addTransitionId),
    );
    expect(addEvent?['event_type'], protectedGroupReactionEventType);
    writeSharedText(_signalName('reaction_add_applied'), 'ok');

    expect(await stack.p2pService.stopNode(), isTrue);
    writeSharedText(_signalName('reaction_remove_recipient_offline'), 'ok');
    final removeFixture = await waitForSharedJson(
      _signalName('reaction_remove_custody_stored.json'),
      timeout: const Duration(minutes: 5),
    );
    final removeTransitionId = removeFixture['transitionId'] as String;
    expect(
      GroupReactionTransitionOrder.tryParse(removeTransitionId),
      isNotNull,
    );
    expect(removeTransitionId, isNot(addTransitionId));
    expect(
      await stack.p2pService.startNode(
        reopenedAuthority.credential!.transportPrivateKey,
        stableTransport,
      ),
      isTrue,
    );
    await _waitForDirectRelayReady(stack);
    await waitForCondition(() async {
      await stack.p2pService.drainProtectedGroupContentFixedPoint();
      final reaction = await stack.reactionRepo
          .getReactionForSenderIncludingRemoved(
            messageId: contentMessageId,
            senderPeerId: stack.identity.peerId,
          );
      return reaction?.isRemoved == true;
    }, timeout: const Duration(minutes: 3));
    final removed = await stack.reactionRepo
        .getReactionForSenderIncludingRemoved(
          messageId: contentMessageId,
          senderPeerId: stack.identity.peerId,
        );
    expect(removed, isNotNull);
    expect(removed!.id, added.id);
    expect(removed.isRemoved, isTrue);
    final removeEvent = await dbLoadGroupEventLogEntryExact(
      stack.db,
      groupId: groupId,
      sourceEventId: protectedGroupReactionSourceEventId(removeTransitionId),
    );
    expect(removeEvent?['event_type'], protectedGroupReactionEventType);
    writeSharedText(_signalName('reaction_remove_applied'), 'ok');

    if (configuredB1bPlan365GroupMedia) {
      expect(await stack.p2pService.stopNode(), isTrue);
      writeSharedText(_signalName('plan365_media_recipient_offline'), 'ok');
      final mediaFixture = await waitForSharedJson(
        _signalName('plan365_media_custody_stored.json'),
        timeout: const Duration(minutes: 8),
      );
      expect(mediaFixture['groupId'], groupId);
      expect(
        await stack.p2pService.startNode(
          reopenedAuthority.credential!.transportPrivateKey,
          stableTransport,
        ),
        isTrue,
      );
      await _waitForDirectRelayReady(stack);
      plan365LinkedProof = await _b1bRecoverPlan365MediaAndVoice(
        stack: stack,
        groupId: groupId,
        fixture: mediaFixture,
      );
      writeSharedJson(
        _signalName('plan365_media_applied.json'),
        plan365LinkedProof,
      );
    }

    await waitForSharedSignal(
      _signalName('dissolve_stored'),
      timeout: const Duration(minutes: 5),
    );
    await waitForCondition(() async {
      try {
        await stack.p2pService.drainOfflineInbox();
      } catch (_) {}
      return (await stack.groupRepo.getGroup(groupId))?.isDissolved == true;
    }, timeout: const Duration(minutes: 3));
    final terminal = await stack.groupRepo.getGroup(groupId);
    expect(terminal, isNotNull);
    expect(terminal!.isDissolved, isTrue);
    expect(await stack.groupRepo.getLatestKey(groupId), isNotNull);
    expect(_b1bContentIngressAuthorityGateInvocations, greaterThan(0));
    expect(_b1bAuthorityReconcileInvocations, greaterThan(0));
    final terminalAuthority = await _b1bLatestSettledContentAuthority(
      stack,
      groupId,
    );
    expect(terminalAuthority, isNotNull);
    final dissolveReconciliation = await dbLoadGroupEventLogEntryExact(
      stack.db,
      groupId: groupId,
      sourceEventId: protectedGroupContentReconciliationCompleteSourceEventId(
        terminalAuthority!.eventId,
      ),
    );
    expect(
      isProtectedGroupContentReconciliationCompleteRow(
        dissolveReconciliation,
        authority: terminalAuthority,
      ),
      isTrue,
    );
    await writeGroupMultiPartyVerdictAndAwaitHostCapture(
      role: 'primary',
      requireHostCapture: configuredB1bRequireHostCapture,
      writeVerdict: () {
        writeSharedJson(_signalName('linked_verdict.json'), {
          'groupId': groupId,
          'linkedTransportPeerId': stableTransport,
          'emptyRepositoryBeforeBootstrap': true,
          'bootstrapMaterialized': true,
          'preservedStorageReopened': true,
          'offlineBlobFreeDiscussionApplied': true,
          'strictReactionAddApplied': true,
          'strictReactionRemoveApplied': true,
          'productionContentIngressGateInvoked':
              _b1bContentIngressAuthorityGateInvocations > 0,
          'productionAuthorityReconcileInvoked':
              _b1bAuthorityReconcileInvocations > 0,
          'contentMessageId': contentMessageId,
          'reactionAddTransitionId': addTransitionId,
          'reactionRemoveTransitionId': removeTransitionId,
          'terminalReadOnlyDissolve': true,
          if (configuredB1bPlan365GroupMedia) ...<String, dynamic>{
            'plan365MediaAndVoiceApplied': plan365LinkedProof != null,
            'plan365FingerprintDescriptorsVerified':
                plan365LinkedProof?['fingerprintedDescriptorsVerified'] == true,
            'plan365LocalPlaintextVerified':
                plan365LinkedProof?['localPlaintextBytesVerified'] == true,
            'plan365StrictBlobAckConverged':
                plan365LinkedProof?['strictBlobAckConverged'] == true,
            'plan365ProductionDownloadOwnerInvoked':
                plan365LinkedProof?['productionDownloadOwnerInvoked'] == true,
            'plan365RestrictedFixedPointInvoked':
                plan365LinkedProof?['restrictedFixedPointInvoked'] == true,
            'plan365StrictDownloadActionsObserved':
                plan365LinkedProof?['strictDownloadActionsObserved'] == true,
            'plan365StrictDeleteActionsObserved':
                plan365LinkedProof?['strictDeleteActionsObserved'] == true,
            'plan365ImageMessageId': plan365LinkedProof?['imageMessageId'],
            'plan365VoiceMessageId': plan365LinkedProof?['voiceMessageId'],
          },
        });
        writeSharedText(_signalName('linked_complete'), 'ok');
      },
      waitForSignal: (name) => waitForSharedSignal(
        _signalName(name),
        timeout: const Duration(minutes: 5),
      ),
    );
  } finally {
    await stack.teardown(deleteStorage: deleteStorage);
    if (!deleteStorage) {
      await deleteTestDatabase(dbName);
      await deleteTestSecureStore(dbName);
    }
  }
}

Future<void> _runB1bConvergenceSibling() async {
  final fixture = await waitForSharedJson(
    _signalName('linked_bootstrap_fixture.json'),
    timeout: const Duration(minutes: 12),
  );
  final mnemonic = fixture['mnemonic12'] as String?;
  final qrDocument = fixture['qrDocument'] as String?;
  expect(mnemonic, isNotNull);
  expect(qrDocument, isNotNull);
  final stack = await setupGroupMultiDeviceStack(
    dbName: _dbNameForRole(),
    username: 'B1b Ordinary Primary',
    cliPeerFixture: null,
    restoreMnemonic: mnemonic,
  );
  Map<String, dynamic>? plan365OrdinaryProof;
  try {
    await _waitForDirectRelayReady(stack);
    expect(stack.identity.peerId, fixture['accountPeerId']);
    expect(
      stack.p2pService.currentState.peerId,
      stack.identity.peerId,
      reason: 'the emulator role must remain the ordinary account-primary',
    );
    final creatorMlKem = stack.identity.mlKemPublicKey;
    expect(creatorMlKem, isNotNull);
    final group = await createGroup(
      bridge: stack.bridge,
      groupRepo: stack.groupRepo,
      name: 'B1b Linked Bootstrap',
      type: GroupType.chat,
      creatorPeerId: stack.identity.peerId,
      creatorPublicKey: stack.identity.publicKey,
      creatorMlKemPublicKey: creatorMlKem!,
      creatorUsername: stack.identity.username,
    );
    final (parseResult, verifiedTarget) = await parseLinkedGroupBootstrapQr(
      qrString: qrDocument!,
      ownAccountPeerId: stack.identity.peerId,
      ownAccountPublicKey: stack.identity.publicKey,
      isOrdinaryPrimary: true,
      callVerify: ({required publicKey, required data, required signature}) =>
          callVerifyPayload(
            bridge: stack.bridge,
            publicKey: publicKey,
            data: data,
            signature: signature,
          ),
      selector: const DirectLinkedDeviceSelector.enabled(),
      multiDeviceSyncEnabled: true,
    );
    expect(parseResult, ParseLinkedGroupBootstrapQrResult.success);
    expect(verifiedTarget, isNotNull);
    final authored = await authorLinkedGroupBootstrap(
      groupRepository: stack.groupRepo,
      groupId: group.id,
      ownAccountPeerId: stack.identity.peerId,
      ownAccountPublicKey: stack.identity.publicKey,
      ownAccountPrivateKey: stack.identity.privateKey,
      verifiedTarget: verifiedTarget!,
      isOrdinaryPrimary: true,
      callSign: (data, privateKey) => callSignPayload(
        bridge: stack.bridge,
        dataToSign: data,
        privateKey: privateKey,
      ),
      callEncrypt: ({required recipientMlKemPublicKey, required plaintext}) =>
          callEncryptMessage(
            bridge: stack.bridge,
            recipientMlKemPublicKey: recipientMlKemPublicKey,
            plaintext: plaintext,
          ),
      selector: const DirectLinkedDeviceSelector.enabled(),
      multiDeviceSyncEnabled: true,
    );
    expect(authored, AuthorLinkedGroupBootstrapResult.committed);
    writeSharedJson(_signalName('bootstrap_authored.json'), {
      'groupId': group.id,
    });
    final runner = _b1bProtectedRunner(stack);
    await waitForCondition(() async {
      await runner.drainForGroup(group.id);
      return (await stack.groupPendingBroadcastRepo.forGroup(group.id)).isEmpty;
    }, timeout: const Duration(minutes: 3));
    await waitForSharedSignal(
      _signalName('bootstrap_materialized'),
      timeout: const Duration(minutes: 5),
    );
    await waitForSharedSignal(
      _signalName('linked_reopened'),
      timeout: const Duration(minutes: 5),
    );

    var authoringResolverInvocations = 0;
    setGroupContentAuthoringResolver(
      stack.groupRepo,
      _b1bProductionContentAuthoringResolver(
        stack,
        onResolved: () => authoringResolverInvocations++,
      ),
    );
    final contentMessageId = 'b1b-content-$configuredRunId';
    const contentText = 'B1b offline blob-free discussion';
    final publishBefore = _b1bBridgeCommandCount(stack, 'group:publish');
    final reliableBefore = _b1bBridgeCommandCount(stack, 'group:sendReliable');
    final reactionPublishBefore = _b1bBridgeCommandCount(
      stack,
      'group:publishReaction',
    );
    await waitForSharedSignal(
      _signalName('content_recipient_offline'),
      timeout: const Duration(minutes: 5),
    );
    final (contentResult, authoredContent) = await sendGroupMessage(
      bridge: stack.bridge,
      groupRepo: stack.groupRepo,
      msgRepo: stack.groupMsgRepo,
      groupId: group.id,
      text: contentText,
      senderPeerId: stack.identity.peerId,
      senderPublicKey: stack.identity.publicKey,
      senderPrivateKey: stack.identity.privateKey,
      senderUsername: stack.identity.username,
      senderDeviceId: stack.identity.peerId,
      senderTransportPeerId: stack.identity.peerId,
      messageId: contentMessageId,
      logicalDeliveryId: contentMessageId,
      timestamp: DateTime.now().toUtc(),
      inviteDeliveryAttemptRepo: stack.groupInviteDeliveryAttemptRepo,
    );
    expect(contentResult, SendGroupMessageResult.success);
    expect(authoredContent, isNotNull);
    expect(authoredContent!.id, contentMessageId);
    expect(authoredContent.status, 'sent');
    expect(authoredContent.inboxStored, isTrue);
    expect(authoredContent.inboxRetryPayload, isNull);
    expect(authoredContent.media, isEmpty);
    expect(
      await stack.mediaAttachmentRepo.getAttachmentsForMessage(
        contentMessageId,
        owner: MediaOwnerLane.group,
      ),
      isEmpty,
    );
    writeSharedJson(_signalName('content_message_custody_stored.json'), {
      'messageId': contentMessageId,
      'text': contentText,
      'custodyKind': groupContentCustodyKind,
    });
    await waitForSharedSignal(
      _signalName('content_message_applied'),
      timeout: const Duration(minutes: 5),
    );

    const reactionEmoji = '👍';
    await waitForSharedSignal(
      _signalName('reaction_add_recipient_offline'),
      timeout: const Duration(minutes: 5),
    );
    final (addResult, localAdd) = await sendGroupReaction(
      bridge: stack.bridge,
      groupRepo: stack.groupRepo,
      msgRepo: stack.groupMsgRepo,
      reactionRepo: stack.reactionRepo,
      reactionReplayOutboxRepo: stack.reactionReplayOutboxRepo,
      groupId: group.id,
      messageId: contentMessageId,
      emoji: reactionEmoji,
      senderPeerId: stack.identity.peerId,
      senderPublicKey: stack.identity.publicKey,
      senderPrivateKey: stack.identity.privateKey,
      inviteDeliveryAttemptRepo: stack.groupInviteDeliveryAttemptRepo,
      authoredAt: DateTime.now().toUtc(),
    );
    expect(addResult, SendGroupReactionResult.success);
    expect(localAdd, isNotNull);
    expect(localAdd!.isRemoved, isFalse);
    final addEntry = await stack.reactionReplayOutboxRepo
        .getLatestEntryForTarget(
          groupId: group.id,
          messageId: contentMessageId,
          senderPeerId: stack.identity.peerId,
        );
    expect(addEntry, isNotNull);
    expect(addEntry!.action, 'add');
    expect(addEntry.deliveryStatus, GroupReactionReplayOutboxStatus.stored);
    expect(
      GroupReactionTransitionOrder.tryParse(addEntry.reactionId),
      isNotNull,
    );
    writeSharedJson(_signalName('reaction_add_custody_stored.json'), {
      'messageId': contentMessageId,
      'emoji': reactionEmoji,
      'transitionId': addEntry.reactionId,
      'custodyKind': groupContentCustodyKind,
    });
    await waitForSharedSignal(
      _signalName('reaction_add_applied'),
      timeout: const Duration(minutes: 5),
    );

    await waitForSharedSignal(
      _signalName('reaction_remove_recipient_offline'),
      timeout: const Duration(minutes: 5),
    );
    final targetMessage = await stack.groupMsgRepo.getMessage(contentMessageId);
    expect(targetMessage, isNotNull);
    final removeResult = await removeGroupReaction(
      bridge: stack.bridge,
      groupRepo: stack.groupRepo,
      reactionRepo: stack.reactionRepo,
      reactionReplayOutboxRepo: stack.reactionReplayOutboxRepo,
      groupId: group.id,
      messageId: contentMessageId,
      emoji: reactionEmoji,
      senderPeerId: stack.identity.peerId,
      senderPublicKey: stack.identity.publicKey,
      senderPrivateKey: stack.identity.privateKey,
      msgRepo: stack.groupMsgRepo,
      inviteDeliveryAttemptRepo: stack.groupInviteDeliveryAttemptRepo,
      targetMessage: targetMessage,
      authoredAt: DateTime.now().toUtc(),
    );
    expect(removeResult, RemoveGroupReactionResult.success);
    final localRemove = await stack.reactionRepo
        .getReactionForSenderIncludingRemoved(
          messageId: contentMessageId,
          senderPeerId: stack.identity.peerId,
        );
    expect(localRemove, isNotNull);
    expect(localRemove!.id, localAdd.id);
    expect(localRemove.isRemoved, isTrue);
    final removeEntry = await stack.reactionReplayOutboxRepo
        .getLatestEntryForTarget(
          groupId: group.id,
          messageId: contentMessageId,
          senderPeerId: stack.identity.peerId,
        );
    expect(removeEntry, isNotNull);
    expect(removeEntry!.action, 'remove');
    expect(removeEntry.deliveryStatus, GroupReactionReplayOutboxStatus.stored);
    expect(removeEntry.reactionId, isNot(addEntry.reactionId));
    expect(
      GroupReactionTransitionOrder.tryParse(removeEntry.reactionId),
      isNotNull,
    );
    writeSharedJson(_signalName('reaction_remove_custody_stored.json'), {
      'messageId': contentMessageId,
      'emoji': reactionEmoji,
      'transitionId': removeEntry.reactionId,
      'custodyKind': groupContentCustodyKind,
    });
    await waitForSharedSignal(
      _signalName('reaction_remove_applied'),
      timeout: const Duration(minutes: 5),
    );
    expect(_b1bBridgeCommandCount(stack, 'group:publish'), publishBefore);
    expect(_b1bBridgeCommandCount(stack, 'group:sendReliable'), reliableBefore);
    expect(
      _b1bBridgeCommandCount(stack, 'group:publishReaction'),
      reactionPublishBefore,
    );
    expect(
      authoringResolverInvocations,
      greaterThanOrEqualTo(3),
      reason: 'message, ADD and REMOVE must use the production resolver',
    );

    if (configuredB1bPlan365GroupMedia) {
      await waitForSharedSignal(
        _signalName('plan365_media_recipient_offline'),
        timeout: const Duration(minutes: 5),
      );
      final mediaFixture = await _b1bAuthorPlan365MediaAndVoice(
        stack: stack,
        groupId: group.id,
      );
      writeSharedJson(
        _signalName('plan365_media_custody_stored.json'),
        mediaFixture,
      );
      final linkedProof = await waitForSharedJson(
        _signalName('plan365_media_applied.json'),
        timeout: const Duration(minutes: 8),
      );
      expect(linkedProof['groupId'], group.id);
      expect(linkedProof['fingerprintedDescriptorsVerified'], isTrue);
      expect(linkedProof['localPlaintextBytesVerified'], isTrue);
      expect(linkedProof['strictBlobAckConverged'], isTrue);
      plan365OrdinaryProof = <String, dynamic>{
        ...mediaFixture,
        'imageMessageId': (mediaFixture['image'] as Map)['messageId'],
        'voiceMessageId': (mediaFixture['voice'] as Map)['messageId'],
        'linkedRecoveryVerified': true,
      };
    }

    final currentGroup = await stack.groupRepo.getGroup(group.id);
    final selfMember = await stack.groupRepo.getMember(
      group.id,
      stack.identity.peerId,
    );
    expect(currentGroup, isNotNull);
    expect(selfMember, isNotNull);
    final senderDevice = selfMember!
        .activeDevicesWithLegacyFallback()
        .singleWhere(
          (device) => device.transportPeerId == stack.identity.peerId,
        );
    final frozenRecipients = selfMember.activeDevicesWithLegacyFallback();
    final dissolvedAt = DateTime.now().toUtc();
    final transitionId = 'b1b-dissolve-${dissolvedAt.microsecondsSinceEpoch}';
    final preTransitionStateHash = await buildGroupTransitionStateHash(
      stack.groupRepo,
      group.id,
    );
    final signedDissolve = await signGroupSystemTransitionPayload(
      bridge: stack.bridge,
      groupRepo: stack.groupRepo,
      groupId: group.id,
      transitionType: 'group_dissolved',
      sourceEventId: transitionId,
      eventAt: dissolvedAt,
      actorPeerId: stack.identity.peerId,
      actorUsername: stack.identity.username,
      actorSigningPublicKey: stack.identity.publicKey,
      actorPrivateKey: stack.identity.privateKey,
      actorDeviceId: senderDevice.deviceId,
      actorTransportPeerId: senderDevice.transportPeerId,
      actorKeyPackageId: senderDevice.keyPackageId,
      preTransitionStateHash: preTransitionStateHash,
      systemPayload: <String, dynamic>{
        '__sys': 'group_dissolved',
        'dissolvedAt': dissolvedAt.toIso8601String(),
        'dissolvedBy': stack.identity.peerId,
      },
    );
    final latestKey = await stack.groupRepo.getLatestKey(group.id);
    expect(latestKey, isNotNull);
    final preparation = await buildProtectedGroupAuthorityRows(
      groupId: group.id,
      transitionId: transitionId,
      control: ProtectedGroupAuthorityControl.groupDissolve,
      replayData: <String, dynamic>{
        'groupId': group.id,
        'senderId': stack.identity.peerId,
        'senderUsername': stack.identity.username,
        'senderDeviceId': senderDevice.deviceId,
        'transportPeerId': senderDevice.transportPeerId,
        'text': jsonEncode(signedDissolve),
        'timestamp': dissolvedAt.toIso8601String(),
        'messageId': transitionId,
        'dissolvedAt': dissolvedAt.toIso8601String(),
        'dissolvedBy': stack.identity.peerId,
      },
      keyEpoch: latestKey!.keyGeneration,
      actorAccountPeerId: stack.identity.peerId,
      actorAccountPublicKey: stack.identity.publicKey,
      actorAccountPrivateKey: stack.identity.privateKey,
      senderDevice: senderDevice,
      frozenRecipients: frozenRecipients,
      callSign: (data, privateKey) => callSignPayload(
        bridge: stack.bridge,
        dataToSign: data,
        privateKey: privateKey,
      ),
      callEncrypt: ({required recipientMlKemPublicKey, required plaintext}) =>
          callEncryptMessage(
            bridge: stack.bridge,
            recipientMlKemPublicKey: recipientMlKemPublicKey,
            plaintext: plaintext,
          ),
      now: () => dissolvedAt,
    );
    expect(preparation.rows, hasLength(1));
    expect(preparation.hasAuthenticatedAuthority, isTrue);
    expect(
      await persistPreparedProtectedGroupAuthority(
        repository: stack.groupPendingBroadcastRepo,
        preparation: preparation,
      ),
      isTrue,
    );
    await waitForCondition(() async {
      await runner.drainForGroup(group.id);
      return (await stack.groupPendingBroadcastRepo.forGroup(group.id)).isEmpty;
    }, timeout: const Duration(minutes: 3));
    final ordinaryTerminal = await stack.groupRepo.getGroup(group.id);
    expect(ordinaryTerminal, isNotNull);
    expect(ordinaryTerminal!.isDissolved, isTrue);
    expect(ordinaryTerminal.dissolvedAt?.toUtc(), dissolvedAt);
    expect(_b1bLocalAuthorityReconcileInvocations, greaterThan(0));
    final localAuthority = preparation.authorityProof!;
    expect(
      isProtectedGroupContentReconciliationCompleteRow(
        await dbLoadGroupEventLogEntryExact(
          stack.db,
          groupId: group.id,
          sourceEventId:
              protectedGroupContentReconciliationCompleteSourceEventId(
                localAuthority.eventId,
              ),
        ),
        authority: localAuthority,
      ),
      isTrue,
    );
    writeSharedText(_signalName('dissolve_stored'), 'ok');
    await waitForSharedSignal(
      _signalName('linked_complete'),
      timeout: const Duration(minutes: 5),
    );
    await writeGroupMultiPartyVerdictAndAwaitHostCapture(
      role: 'sibling',
      requireHostCapture: configuredB1bRequireHostCapture,
      writeVerdict: () {
        writeSharedJson(_signalName('ordinary_verdict.json'), {
          'groupId': group.id,
          'linkedTransportPeerId': verifiedTarget.transportPeerId,
          'bootstrapCustodyAccepted': true,
          'offlineBlobFreeDiscussionCustodyAccepted': true,
          'strictReactionAddCustodyAccepted': true,
          'strictReactionRemoveCustodyAccepted': true,
          'zeroGroupPubsubForStrictContent': true,
          'productionAuthoringResolverInvoked':
              authoringResolverInvocations > 0,
          'localAuthorityReconcileInvoked':
              _b1bLocalAuthorityReconcileInvocations > 0,
          'contentMessageId': contentMessageId,
          'reactionAddTransitionId': addEntry.reactionId,
          'reactionRemoveTransitionId': removeEntry.reactionId,
          'dissolveCustodyAcceptedBeforeTerminalCommit': true,
          if (configuredB1bPlan365GroupMedia) ...<String, dynamic>{
            'plan365MediaAndVoiceCustodyAccepted':
                plan365OrdinaryProof?['linkedRecoveryVerified'] == true,
            'plan365ProductionPreparedCoordinatorInvoked':
                plan365OrdinaryProof?['productionPreparedCoordinatorInvoked'] ==
                true,
            'plan365StrictUploadActionsObserved':
                plan365OrdinaryProof?['strictUploadActionsObserved'] == true,
            'plan365ZeroLegacyAllowedPeersUploads':
                plan365OrdinaryProof?['zeroLegacyAllowedPeersUploads'] == true,
            'plan365ImageMessageId': plan365OrdinaryProof?['imageMessageId'],
            'plan365VoiceMessageId': plan365OrdinaryProof?['voiceMessageId'],
          },
        });
      },
      waitForSignal: (name) => waitForSharedSignal(
        _signalName(name),
        timeout: const Duration(minutes: 5),
      ),
    );
  } finally {
    setGroupContentAuthoringResolver(stack.groupRepo, null);
    await stack.teardown();
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  initializeSqliteForCurrentPlatform();

  final runtimeLease = CanonicalRuntimeDeviceTestLease(
    binding: 'group-multi-device-real-$configuredRole',
  );
  setUpAll(runtimeLease.acquire);
  tearDownAll(runtimeLease.release);

  testWidgets(
    'MD-004 multi-device proof scenario=$configuredScenario role=$configuredRole run=$configuredRunId',
    (tester) async {
      try {
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

        if (configuredScenario == 'invite_send_latency') {
          if (_isPrimaryRole) {
            await _runInviteSendLatencyPrimary(tester);
          } else {
            await _runInviteSendLatencySibling();
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

        // 360 / TC-360-04a: the registered linked-device addressing pair.
        if (configuredScenario == directLinkedDeviceAddressingScenario) {
          // The runner launches the PRIMARY first and only starts the sibling
          // once the primary has written its readiness fixture. The linked
          // secondary is therefore the primary role here: it is the publisher
          // (identity, then QR). Putting account B on primary would deadlock —
          // it would wait for a fixture only the never-launched sibling writes.
          if (_isPrimaryRole) {
            await _runDirectLinkedDeviceAddressingLinkedSide();
          } else {
            await _runDirectLinkedDeviceAddressingAccountBSide();
          }
          return;
        }

        // 362 / TC-362-05b: one aggregate linked-origin text + shared-blob
        // fanout proof on the availability-bounded Android pair.
        if (configuredScenario == directLinkedDeviceEventBlobFanoutScenario) {
          if (_isPrimaryRole) {
            await _runDirectLinkedDeviceEventBlobFanoutLinkedSide();
          } else {
            await _runDirectLinkedDeviceEventBlobFanoutAccountBSide();
          }
          return;
        }

        // 360: an unregistered scenario is TERMINAL.
        //
        // Before this guard, anything unrecognized fell through to the legacy
        // `same_user` branch below — so a typo, or a scenario registered on the
        // host side but not here, would run a completely different proof and
        // report PASS for the scenario the caller actually named. That is a
        // false green, not a missing feature.
        if (configuredScenario != _legacySameUserScenario) {
          fail('Unregistered MD004_SCENARIO: $configuredScenario');
        }

        if (_isPrimaryRole) {
          await _runPrimaryScenario();
        } else {
          await _runSiblingScenario();
        }
      } catch (error, stackTrace) {
        // `debugPrint` is throttled behind the migration flow-event burst on
        // Android. Use synchronous `print` here so an early harness failure is
        // visible to the host runner before the integration-test app exits.
        print(
          '[MD004_FATAL] scenario=$configuredScenario role=$configuredRole '
          'errorType=${error.runtimeType} '
          'error=${sanitizeDiagnosticText(error)}',
        );
        print('[MD004_FATAL_STACK]\n$stackTrace');
        rethrow;
      }
    },
  );
}

// ── 360 / TC-360-04a: registered Android linked-device addressing pair ──────
//
// Topology is TWO targets, not three phones:
//   * `sibling` role = account A's LINKED SECONDARY. It uses real
//     `FlutterSecureKeyStore` for exactly the run-scoped linked marker and
//     credential keys, real bridge identity generation, starts with a stable
//     transport peer distinct from its logical account, and emits the
//     dual-signed QR.
//   * `primary` role = a DIFFERENT account B that already stores A's logical
//     account as a legacy contact fixture. It stages then explicitly verifies
//     the scanned document, and refuses one tampered copy.
//
// The real primary account-A device need not run: this scenario proves
// identity and trust, not delivery. Stop/start only — no chat, event, or blob
// traffic is exercised.

/// Runs the ACCOUNT-B side: stage, verify, and refuse a tampered document.
Future<void> _runDirectLinkedDeviceAddressingAccountBSide() async {
  final stack = await setupGroupMultiDeviceStack(
    dbName: _dbNameForRole(),
    username: 'Bob',
    cliPeerFixture: null,
  );
  try {
    // B publishes nothing; it only needs A's logical account as a contact.
    final aliceFixture = await waitForSharedJson(
      _signalName('alice_identity.json'),
    );
    final aliceContact = _contactFromFixture(aliceFixture, 'Alice');
    await stack.contactRepo.addContact(aliceContact);

    final qrFixture = await waitForSharedJson(
      _signalName('linked_device_qr.json'),
    );
    final qrDocument = qrFixture['document'] as String;
    final tamperedDocument = qrFixture['tamperedDocument'] as String;

    Future<bool> verifySignature({
      required String publicKey,
      required String data,
      required String signature,
    }) => callVerifyPayload(
      bridge: stack.bridge,
      publicKey: publicKey,
      data: data,
      signature: signature,
    );

    // The tampered copy must be refused BEFORE the good one is accepted, so a
    // pass cannot come from "the first document we happened to try".
    final (tamperedResult, _) = await parseDirectLinkedDeviceQr(
      qrString: tamperedDocument,
      ownAccountPeerId: stack.identity.peerId,
      lookupContact: stack.contactRepo.getContact,
      callVerify: verifySignature,
      selector: const DirectLinkedDeviceSelector.enabled(),
    );
    expect(
      tamperedResult,
      isNot(ParseDirectLinkedDeviceQrResult.success),
      reason: 'a tampered linked-device document must never authenticate',
    );

    final (parseResult, document) = await parseDirectLinkedDeviceQr(
      qrString: qrDocument,
      ownAccountPeerId: stack.identity.peerId,
      lookupContact: stack.contactRepo.getContact,
      callVerify: verifySignature,
      selector: const DirectLinkedDeviceSelector.enabled(),
    );
    expect(parseResult, ParseDirectLinkedDeviceQrResult.success);
    expect(document, isNotNull);

    final stagedAt = DateTime.now().toUtc().toIso8601String();
    final stageOutcome = await dbStageDirectContactDeviceBinding(
      stack.db,
      contactAccountPeerId: document!.accountPeerId,
      accountSigningPublicKey: document.accountPublicKey,
      deviceId: document.deviceId,
      transportPeerId: document.transportPeerId,
      transportPublicKey: document.transportPublicKey,
      deviceMlKemPublicKey: document.deviceMlKemPublicKey,
      stagedAt: stagedAt,
    );
    expect(stageOutcome, DirectContactDeviceBindingStageOutcome.staged);

    final fingerprint = computeDirectContactDeviceBindingFingerprint(
      contactAccountPeerId: document.accountPeerId,
      accountSigningPublicKey: document.accountPublicKey,
      deviceId: document.deviceId,
      transportPeerId: document.transportPeerId,
      transportPublicKey: document.transportPublicKey,
      deviceMlKemPublicKey: document.deviceMlKemPublicKey,
    );
    final verified = await dbVerifyDirectContactDeviceBinding(
      stack.db,
      contactAccountPeerId: document.accountPeerId,
      deviceId: document.deviceId,
      expectedFingerprint: fingerprint,
      expectedAccountSigningPublicKey: document.accountPublicKey,
      decidedAt: DateTime.now().toUtc().toIso8601String(),
    );
    expect(verified, isTrue);

    final roster = await dbLoadDirectContactDeviceRoster(
      stack.db,
      document.accountPeerId,
    );
    expect(roster.metadata.rosterInitialized, isTrue);
    expect(roster.activeBindings, hasLength(1));
    expect(
      roster.activeBindings.single.transportPeerId,
      document.transportPeerId,
    );

    // The verified transport must be a DIFFERENT peer than the logical
    // account. Equal peers would mean the shared-mailbox topology never
    // actually changed.
    expect(
      roster.activeBindings.single.transportPeerId,
      isNot(document.accountPeerId),
    );

    writeSharedJson(
      directLinkedDeviceAddressingReadyFileName(configuredRunId, 'sibling'),
      <String, dynamic>{
        'schema': directLinkedDeviceAddressingReadySchema,
        'schemaVersion': directLinkedDeviceAddressingReadySchemaVersion,
        'role': 'sibling',
        'runId': configuredRunId,
        'stagedThenVerified': true,
        'tamperedRefused': true,
        'tamperedResult': tamperedResult.name,
        'activeDeviceCount': roster.activeBindings.length,
      },
    );
    // Signal completion, then STAY ALIVE until the peer acknowledges.
    //
    // `flutter test` uninstalls the app when a role finishes, which deletes the
    // app-private signal dir. An artifact written as a role's LAST action can
    // therefore be destroyed before the 500ms host sync pulls it — which is
    // exactly how the previous run failed, with this side passing and the peer
    // timing out on an artifact that no longer existed anywhere.
    writeSharedText(_signalName('accountb_verified'), 'ok');
    await waitForSharedSignal(
      _signalName('linked_side_done'),
      timeout: const Duration(minutes: 5),
    );
  } finally {
    await stack.teardown();
  }
}

/// Runs the LINKED-SECONDARY side for account A.
Future<void> _runDirectLinkedDeviceAddressingLinkedSide() async {
  final stack = await setupGroupMultiDeviceStack(
    dbName: _dbNameForRole(),
    username: 'Alice',
    cliPeerFixture: null,
  );
  // Real platform secure storage for EXACTLY the two run-scoped linked keys.
  // Every other harness store stays fake, and these are deleted before and
  // after so raw key material never survives the run or reaches an artifact.
  final deviceSecureStore = FlutterSecureKeyStore();

  // The authority READS the canonical runtime installation ID (it never mints
  // one), so this run must supply a value. Capture whatever was there first and
  // put it back afterwards, so the proof writes nothing durable it did not
  // already own — the same discipline the two linked keys follow.
  String? priorInstallationId;

  Future<void> restoreRunScopedSecureState() async {
    await deviceSecureStore.delete(linkedInstallationRoleStorageKey);
    await deviceSecureStore.delete(
      linkedInstallationTransportCredentialStorageKey,
    );
    final prior = priorInstallationId;
    if (prior == null) {
      await deviceSecureStore.delete(canonicalRuntimeInstallationIdStorageKey);
    } else {
      await deviceSecureStore.write(
        canonicalRuntimeInstallationIdStorageKey,
        prior,
      );
    }
  }

  try {
    priorInstallationId = await deviceSecureStore.read(
      canonicalRuntimeInstallationIdStorageKey,
    );
    await deviceSecureStore.delete(linkedInstallationRoleStorageKey);
    await deviceSecureStore.delete(
      linkedInstallationTransportCredentialStorageKey,
    );
    await deviceSecureStore.write(
      canonicalRuntimeInstallationIdStorageKey,
      'tc360-$configuredRunId-linked',
    );

    final authority = LinkedInstallationAuthority(
      secureKeyStore: deviceSecureStore,
    );

    // Crash-safe order: marker, then ONE preparing credential, then activate.
    await authority.markExpectedLinkedRole();
    final (setupResult, credential) = await authority
        .createOrResumeTransportCredential(
          accountPeerId: stack.identity.peerId,
          accountPublicKey: stack.identity.publicKey,
          callIdentityGenerate: () => callIdentityGenerate(stack.bridge),
          callSign: (data, privateKey) => callSignPayload(
            bridge: stack.bridge,
            dataToSign: data,
            privateKey: privateKey,
          ),
          callVerify:
              ({
                required String publicKey,
                required String data,
                required String signature,
              }) => callVerifyPayload(
                bridge: stack.bridge,
                publicKey: publicKey,
                data: data,
                signature: signature,
              ),
        );
    expect(setupResult, LinkedInstallationSetupResult.success);
    expect(credential, isNotNull);
    expect(credential!.transportPeerId, isNot(stack.identity.peerId));

    // Resume must re-adopt the SAME bytes rather than mint a second identity.
    final (resumeResult, resumed) = await authority
        .createOrResumeTransportCredential(
          accountPeerId: stack.identity.peerId,
          accountPublicKey: stack.identity.publicKey,
          callIdentityGenerate: () => callIdentityGenerate(stack.bridge),
          callSign: (data, privateKey) => callSignPayload(
            bridge: stack.bridge,
            dataToSign: data,
            privateKey: privateKey,
          ),
          callVerify:
              ({
                required String publicKey,
                required String data,
                required String signature,
              }) => callVerifyPayload(
                bridge: stack.bridge,
                publicKey: publicKey,
                data: data,
                signature: signature,
              ),
        );
    expect(resumeResult, LinkedInstallationSetupResult.success);
    expect(resumed!.transportPeerId, credential.transportPeerId);

    expect(
      await authority.activateTransportCredential(
        accountPeerId: stack.identity.peerId,
        expectedTransportPeerId: credential.transportPeerId,
      ),
      LinkedInstallationSetupResult.success,
    );

    final activeAuthority = await authority.load(
      expectedAccountPeerId: stack.identity.peerId,
    );
    expect(activeAuthority.isActiveLinkedSecondary, isTrue);

    // The shared stack helper starts a node on the ACCOUNT identity for its own
    // purposes. A real linked installation starts on a fresh process where no
    // node is running, so stop that one first.
    //
    // This is not incidental cleanup — it is the exact hot-restart hazard the
    // production peer barrier exists for. Without the stop, `node:start` answers
    // "already started", `startNodeCore` resyncs from `node:status`, and the
    // service reports the ACCOUNT peer while believing it started the transport.
    // Production refuses that outcome (`_qualifyLinkedTransportPeer` stops the
    // node and fails the start); this harness's service is constructed by the
    // shared helper without that qualifier, so the assertion below is what
    // catches it here.
    await stack.p2pService.stopNode();

    // Start the node on the TRANSPORT identity, then stop. Stop/start only.
    final startResult = await startP2PNode(
      identityRepo: stack.identityRepo,
      p2pService: stack.p2pService,
      linkedAuthority: activeAuthority,
    );
    expect(startResult, StartNodeResult.success);
    final startedPeerId = stack.p2pService.currentState.peerId;
    expect(
      startedPeerId,
      credential.transportPeerId,
      reason:
          'the node must come up as the TRANSPORT peer, not the account peer',
    );
    expect(
      startedPeerId,
      isNot(stack.identity.peerId),
      reason: 'a linked secondary must not share the account mailbox',
    );
    await stack.p2pService.stopNode();

    // Restart proves the transport peer is STABLE across a stop/start, which
    // is what makes a contact's stored binding durable.
    final restartAuthority = await authority.load(
      expectedAccountPeerId: stack.identity.peerId,
    );
    expect(
      restartAuthority.credential!.transportPeerId,
      credential.transportPeerId,
    );

    // `alice_identity.json` is the EXACT readiness fixture the runner polls for
    // before it launches the sibling. Publishing account A's logical identity
    // here is both the release signal and the legacy-contact fixture the other
    // account needs.
    writeSharedJson(
      _signalName('alice_identity.json'),
      _peerIdentityFixture(stack.identity),
    );

    final (buildResult, document) = await buildDirectLinkedDeviceQr(
      linkedAuthority: activeAuthority,
      accountPeerId: stack.identity.peerId,
      accountPublicKey: stack.identity.publicKey,
      accountPrivateKey: stack.identity.privateKey,
      deviceMlKemPublicKey: stack.identity.mlKemPublicKey,
      callSign: (data, privateKey) => callSignPayload(
        bridge: stack.bridge,
        dataToSign: data,
        privateKey: privateKey,
      ),
      selector: const DirectLinkedDeviceSelector.enabled(),
    );
    expect(buildResult, BuildDirectLinkedDeviceQrResult.success);
    expect(document, isNotNull);

    // Tamper with the SIGNED body (the device ID) while leaving both
    // signatures intact — the exact forgery dual signing must catch.
    final decoded = jsonDecode(document!) as Map<String, dynamic>;
    final envelope = Map<String, dynamic>.from(
      decoded['mknoon'] as Map<String, dynamic>,
    );
    final body = Map<String, dynamic>.from(
      envelope['body'] as Map<String, dynamic>,
    );
    body['deviceId'] = '${body['deviceId']}-tampered';
    envelope['body'] = body;
    final tampered = jsonEncode(<String, dynamic>{'mknoon': envelope});

    writeSharedJson(_signalName('linked_device_qr.json'), <String, dynamic>{
      'document': document,
      'tamperedDocument': tampered,
    });

    // Account B still has to BUILD and install after this role signalled
    // readiness, so this barrier is deliberately generous. It waits on B's
    // EARLY signal — written while B is still running — never on an artifact B
    // writes as its final action, which its own uninstall can destroy.
    await waitForSharedSignal(
      _signalName('accountb_verified'),
      timeout: const Duration(minutes: 12),
    );

    writeSharedJson(
      directLinkedDeviceAddressingReadyFileName(configuredRunId, 'primary'),
      <String, dynamic>{
        'schema': directLinkedDeviceAddressingReadySchema,
        'schemaVersion': directLinkedDeviceAddressingReadySchemaVersion,
        'role': 'primary',
        'runId': configuredRunId,
        'transportDistinctFromAccount': true,
        'transportStableAcrossRestart': true,
        'qrEmitted': true,
      },
    );
    // Release B only after this side's own artifact is published.
    writeSharedText(_signalName('linked_side_done'), 'ok');
  } finally {
    // Raw key material never outlives the run, and the canonical installation
    // ID is restored to exactly what this proof found.
    await restoreRunScopedSecureState();
    await stack.teardown();
  }
}

// ── 362 / TC-362-05b: aggregate linked-origin event + blob fanout ─────────

String _plan362Sha256(String value) =>
    sha256.convert(utf8.encode(value)).toString();

List<int> _plan362TinyPngBytes() => base64Decode(
  // One opaque 1x1 PNG. Its bytes are intentionally fixed so the receiver can
  // prove the downloaded plaintext rather than merely observing `done`.
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk'
  '/w8AAusB9Y9ZQmcAAAAASUVORK5CYII=',
);

void _requirePlan362FixtureIdentity() {
  if (!RegExp(
    r'^[0-9a-f]{64}$',
  ).hasMatch(configuredPlan362FixtureIdentitySha256)) {
    throw StateError(
      'TC-362 requires the capability-bound Plan-347 fixture identity',
    );
  }
}

Future<void> _waitForDirectRelayReady(GroupMultiDeviceTestStack stack) async {
  await waitForCondition(
    () async => stack.p2pService.currentState.relayReady,
    timeout: const Duration(minutes: 2),
  );
}

Future<DirectLinkedDeviceQrDocument> _stageAndVerifyLinkedQr({
  required GroupMultiDeviceTestStack stack,
  required String qrDocument,
}) async {
  final (parseResult, document) = await parseDirectLinkedDeviceQr(
    qrString: qrDocument,
    ownAccountPeerId: stack.identity.peerId,
    lookupContact: stack.contactRepo.getContact,
    callVerify:
        ({
          required String publicKey,
          required String data,
          required String signature,
        }) => callVerifyPayload(
          bridge: stack.bridge,
          publicKey: publicKey,
          data: data,
          signature: signature,
        ),
    selector: const DirectLinkedDeviceSelector.enabled(),
  );
  expect(parseResult, ParseDirectLinkedDeviceQrResult.success);
  expect(document, isNotNull);
  final authenticated = document!;
  final stageOutcome = await dbStageDirectContactDeviceBinding(
    stack.db,
    contactAccountPeerId: authenticated.accountPeerId,
    accountSigningPublicKey: authenticated.accountPublicKey,
    deviceId: authenticated.deviceId,
    transportPeerId: authenticated.transportPeerId,
    transportPublicKey: authenticated.transportPublicKey,
    deviceMlKemPublicKey: authenticated.deviceMlKemPublicKey,
    stagedAt: DateTime.now().toUtc().toIso8601String(),
  );
  expect(stageOutcome, DirectContactDeviceBindingStageOutcome.staged);
  final fingerprint = computeDirectContactDeviceBindingFingerprint(
    contactAccountPeerId: authenticated.accountPeerId,
    accountSigningPublicKey: authenticated.accountPublicKey,
    deviceId: authenticated.deviceId,
    transportPeerId: authenticated.transportPeerId,
    transportPublicKey: authenticated.transportPublicKey,
    deviceMlKemPublicKey: authenticated.deviceMlKemPublicKey,
  );
  expect(
    await dbVerifyDirectContactDeviceBinding(
      stack.db,
      contactAccountPeerId: authenticated.accountPeerId,
      deviceId: authenticated.deviceId,
      expectedFingerprint: fingerprint,
      expectedAccountSigningPublicKey: authenticated.accountPublicKey,
      decidedAt: DateTime.now().toUtc().toIso8601String(),
    ),
    isTrue,
  );
  return authenticated;
}

Map<String, dynamic> _plan362CommonArtifact({
  required String role,
  required String accountAPeerId,
  required String accountATransportPeerId,
  required String accountBPeerId,
  required String offlineBTransportPeerId,
  required String eventMessageId,
  required String mediaMessageId,
  required String attachmentId,
  required String ciphertextSha256,
}) => <String, dynamic>{
  'schema': directLinkedDeviceEventBlobFanoutArtifactSchema,
  'schemaVersion': directLinkedDeviceEventBlobFanoutArtifactSchemaVersion,
  'scenario': directLinkedDeviceEventBlobFanoutScenario,
  'runId': configuredRunId,
  'role': role,
  'fixtureIdentitySha256': configuredPlan362FixtureIdentitySha256,
  'accountAPeerIdSha256': _plan362Sha256(accountAPeerId),
  'accountATransportPeerIdSha256': _plan362Sha256(accountATransportPeerId),
  'accountBPeerIdSha256': _plan362Sha256(accountBPeerId),
  'offlineBTransportPeerIdSha256': _plan362Sha256(offlineBTransportPeerId),
  'eventMessageIdSha256': _plan362Sha256(eventMessageId),
  'mediaMessageIdSha256': _plan362Sha256(mediaMessageId),
  'attachmentIdSha256': _plan362Sha256(attachmentId),
  'ciphertextSha256': ciphertextSha256,
};

/// The emulator/account-B receiver. It creates one inert offline linked-B
/// target, verifies A's linked transport, goes offline before authoring, then
/// drains only its own protected siblings and proves apply/download/ACK.
Future<void> _runDirectLinkedDeviceEventBlobFanoutAccountBSide() async {
  _requirePlan362FixtureIdentity();
  final stack = await setupGroupMultiDeviceStack(
    dbName: _dbNameForRole(),
    username: 'Bob TC362',
    cliPeerFixture: null,
  );
  final observedOuter = <String, ChatMessage>{};
  final outerSubscription = stack.messageRouter.chatMessageStream.listen((msg) {
    try {
      final decoded = jsonDecode(msg.content);
      if (decoded is Map && decoded['id'] is String) {
        observedOuter[decoded['id'] as String] = msg;
      }
    } on Object {
      // Non-v2 messages are outside this scenario and remain with the router.
    }
  });

  try {
    final offlineIdentityResult = await callIdentityGenerate(stack.bridge);
    expect(offlineIdentityResult['ok'], isTrue);
    final offlineIdentity = Map<String, dynamic>.from(
      offlineIdentityResult['identity'] as Map,
    );
    final offlineMlKemResult = await callMlKemKeygen(stack.bridge);
    expect(offlineMlKemResult['ok'], isTrue);
    final offlineTransportPeerId = offlineIdentity['peerId'] as String;
    final offlineTransportPublicKey = offlineIdentity['publicKey'] as String;
    final offlineMlKemPublicKey = offlineMlKemResult['publicKey'] as String;
    final liveMlKemPublicKey = stack.identity.mlKemPublicKey;
    expect(liveMlKemPublicKey, isNotNull);
    expect(offlineTransportPeerId, isNot(stack.identity.peerId));
    expect(offlineMlKemPublicKey, isNot(liveMlKemPublicKey));

    writeSharedJson(_signalName('fanout_b_identity.json'), <String, dynamic>{
      ..._peerIdentityFixture(stack.identity),
      'offlineDeviceId': offlineTransportPeerId,
      'offlineTransportPeerId': offlineTransportPeerId,
      'offlineTransportPublicKey': offlineTransportPublicKey,
      'offlineMlKemPublicKey': offlineMlKemPublicKey,
    });

    final aliceFixture = await waitForSharedJson(
      _signalName('alice_identity.json'),
      timeout: const Duration(minutes: 12),
    );
    await stack.contactRepo.addContact(
      _contactFromFixture(aliceFixture, 'Alice TC362'),
    );
    final qrFixture = await waitForSharedJson(
      _signalName('fanout_linked_qr.json'),
    );
    final linkedDocument = await _stageAndVerifyLinkedQr(
      stack: stack,
      qrDocument: qrFixture['document'] as String,
    );
    expect(linkedDocument.accountPeerId, aliceFixture['peerId']);
    expect(linkedDocument.transportPeerId, isNot(linkedDocument.accountPeerId));

    // The live legacy-B sibling must enter the protected relay inbox, not win
    // a direct race. The offline linked-B identity never starts anywhere.
    expect(await stack.p2pService.stopNode(), isTrue);
    writeSharedText(_signalName('fanout_b_ready'), 'ok');
    await waitForSharedSignal(
      _signalName('fanout_authored'),
      timeout: const Duration(minutes: 5),
    );
    final targets = await waitForSharedJson(
      directLinkedDeviceEventBlobFanoutTargetFixtureFileName(configuredRunId),
    );
    final eventMessageId = targets['eventMessageId'] as String;
    final mediaMessageId = targets['mediaMessageId'] as String;
    final attachmentId = targets['attachmentId'] as String;
    expect(targets['liveRecipientPeerId'], stack.identity.peerId);
    expect(targets['offlineRecipientPeerId'], offlineTransportPeerId);

    expect(
      await stack.p2pService.startNode(
        stack.identity.privateKey,
        stack.identity.peerId,
      ),
      isTrue,
    );
    await _waitForDirectRelayReady(stack);

    await waitForCondition(() async {
      await stack.p2pService.drainOfflineInbox().timeout(
        const Duration(seconds: 60),
      );
      final event = await stack.messageRepo.getMessage(eventMessageId);
      final media = await stack.messageRepo.getMessage(mediaMessageId);
      final attachments = await stack.mediaAttachmentRepo
          .getAttachmentsForMessage(
            mediaMessageId,
            owner: MediaOwnerLane.direct,
          );
      if (event == null || media == null || attachments.length != 1) {
        return false;
      }
      final attachment = attachments.single;
      final storedPath = attachment.localPath;
      if (attachment.downloadStatus != 'done' ||
          storedPath == null ||
          storedPath.isEmpty) {
        return false;
      }
      final absolutePath = await stack.mediaFileManager.resolveStoredPath(
        storedPath,
      );
      final incomingCustody = await stack.mediaAttachmentRepo
          .loadIncomingDirectMediaBlobCustodyForAttachment(attachmentId);
      return await File(absolutePath).exists() &&
          incomingCustody == null &&
          observedOuter.containsKey(eventMessageId) &&
          observedOuter.containsKey(mediaMessageId) &&
          stack.deliveryReceiptTargets.contains(linkedDocument.transportPeerId);
    }, timeout: const Duration(minutes: 3));

    final event = (await stack.messageRepo.getMessage(eventMessageId))!;
    final media = (await stack.messageRepo.getMessage(mediaMessageId))!;
    final attachment =
        (await stack.mediaAttachmentRepo.getAttachmentsForMessage(
          mediaMessageId,
          owner: MediaOwnerLane.direct,
        )).single;
    final absoluteDownloadedPath = await stack.mediaFileManager
        .resolveStoredPath(attachment.localPath!);
    expect(
      await File(absoluteDownloadedPath).readAsBytes(),
      _plan362TinyPngBytes(),
      reason: 'the live B target must hold the exact authored plaintext',
    );
    expect(event.senderPeerId, linkedDocument.accountPeerId);
    expect(media.senderPeerId, linkedDocument.accountPeerId);
    expect(
      stack.deliveryReceiptTargets,
      isNotEmpty,
      reason: 'durable inbox apply must emit delivery receipts',
    );
    expect(
      stack.deliveryReceiptTargets.toSet(),
      <String>{linkedDocument.transportPeerId},
      reason: 'receipts target only A physical transport, never A account',
    );

    for (final id in <String>[eventMessageId, mediaMessageId]) {
      final outer = observedOuter[id]!;
      final envelope = jsonDecode(outer.content) as Map<String, dynamic>;
      expect(outer.from, linkedDocument.transportPeerId);
      expect(envelope['senderPeerId'], linkedDocument.transportPeerId);
    }
    expect(attachment.contentHash, isNotNull);

    writeSharedJson(
      directLinkedDeviceEventBlobFanoutArtifactFileName(
        configuredRunId,
        'sibling',
      ),
      <String, dynamic>{
        ..._plan362CommonArtifact(
          role: 'sibling',
          accountAPeerId: linkedDocument.accountPeerId,
          accountATransportPeerId: linkedDocument.transportPeerId,
          accountBPeerId: stack.identity.peerId,
          offlineBTransportPeerId: offlineTransportPeerId,
          eventMessageId: eventMessageId,
          mediaMessageId: mediaMessageId,
          attachmentId: attachmentId,
          ciphertextSha256: attachment.contentHash!,
        ),
        'outerSenderTransportPeerIdSha256': _plan362Sha256(
          linkedDocument.transportPeerId,
        ),
        'innerSenderAccountPeerIdSha256': _plan362Sha256(event.senderPeerId),
        'receiptDestinationPeerIdSha256': _plan362Sha256(
          linkedDocument.transportPeerId,
        ),
        'eventApplied': true,
        'mediaApplied': true,
        'blobDownloaded': true,
        'blobAcked': true,
        'receiptRoutedToPhysicalTransport': true,
      },
    );
    writeSharedText(_signalName('fanout_b_complete'), 'ok');
    await waitForSharedSignal(
      _signalName('fanout_primary_complete'),
      timeout: const Duration(minutes: 5),
    );
    await Future<void>.delayed(const Duration(seconds: 2));
  } finally {
    await outerSubscription.cancel();
    await stack.teardown();
  }
}

/// The physical linked-secondary/account-A author. One read-only admission is
/// resolved before the media copy/parent/attachment/crypto boundary, then the
/// exact snapshot authors both target batches while B is offline.
Future<void> _runDirectLinkedDeviceEventBlobFanoutLinkedSide() async {
  _requirePlan362FixtureIdentity();
  expect(kDirectLinkedDevicesEnabled, isTrue);
  expect(kDirectLinkedEventFanoutEnabled, isTrue);
  expect(kDirectMediaBlobCustodyClientEnabled, isTrue);
  expect(kDirectLinkedMediaFanoutEnabled, isTrue);

  final stack = await setupGroupMultiDeviceStack(
    dbName: _dbNameForRole(),
    username: 'Alice TC362',
    cliPeerFixture: null,
  );
  final deviceSecureStore = FlutterSecureKeyStore();
  final artifactStore = DirectMediaBlobArtifactStore();
  String? priorInstallationId;
  String? pendingMediaMessageId;
  File? plaintextSource;
  final artifactRelativePaths = <String>{};

  Future<void> restoreRunScopedSecureState() async {
    await deviceSecureStore.delete(linkedInstallationRoleStorageKey);
    await deviceSecureStore.delete(
      linkedInstallationTransportCredentialStorageKey,
    );
    final prior = priorInstallationId;
    if (prior == null) {
      await deviceSecureStore.delete(canonicalRuntimeInstallationIdStorageKey);
    } else {
      await deviceSecureStore.write(
        canonicalRuntimeInstallationIdStorageKey,
        prior,
      );
    }
  }

  try {
    priorInstallationId = await deviceSecureStore.read(
      canonicalRuntimeInstallationIdStorageKey,
    );
    await deviceSecureStore.delete(linkedInstallationRoleStorageKey);
    await deviceSecureStore.delete(
      linkedInstallationTransportCredentialStorageKey,
    );
    await deviceSecureStore.write(
      canonicalRuntimeInstallationIdStorageKey,
      'tc362-$configuredRunId-linked',
    );
    final authority = LinkedInstallationAuthority(
      secureKeyStore: deviceSecureStore,
    );
    await authority.markExpectedLinkedRole();
    final (setupResult, credential) = await authority
        .createOrResumeTransportCredential(
          accountPeerId: stack.identity.peerId,
          accountPublicKey: stack.identity.publicKey,
          callIdentityGenerate: () => callIdentityGenerate(stack.bridge),
          callSign: (data, privateKey) => callSignPayload(
            bridge: stack.bridge,
            dataToSign: data,
            privateKey: privateKey,
          ),
          callVerify:
              ({
                required String publicKey,
                required String data,
                required String signature,
              }) => callVerifyPayload(
                bridge: stack.bridge,
                publicKey: publicKey,
                data: data,
                signature: signature,
              ),
        );
    expect(setupResult, LinkedInstallationSetupResult.success);
    expect(credential, isNotNull);
    expect(credential!.transportPeerId, isNot(stack.identity.peerId));
    final (resumeResult, resumed) = await authority
        .createOrResumeTransportCredential(
          accountPeerId: stack.identity.peerId,
          accountPublicKey: stack.identity.publicKey,
          callIdentityGenerate: () => callIdentityGenerate(stack.bridge),
          callSign: (data, privateKey) => callSignPayload(
            bridge: stack.bridge,
            dataToSign: data,
            privateKey: privateKey,
          ),
          callVerify:
              ({
                required String publicKey,
                required String data,
                required String signature,
              }) => callVerifyPayload(
                bridge: stack.bridge,
                publicKey: publicKey,
                data: data,
                signature: signature,
              ),
        );
    expect(resumeResult, LinkedInstallationSetupResult.success);
    expect(resumed!.transportPeerId, credential.transportPeerId);
    expect(
      await authority.activateTransportCredential(
        accountPeerId: stack.identity.peerId,
        expectedTransportPeerId: credential.transportPeerId,
      ),
      LinkedInstallationSetupResult.success,
    );
    final linkedAuthority = await authority.load(
      expectedAccountPeerId: stack.identity.peerId,
    );
    expect(linkedAuthority.isActiveLinkedSecondary, isTrue);

    await stack.p2pService.stopNode();
    expect(
      await startP2PNode(
        identityRepo: stack.identityRepo,
        p2pService: stack.p2pService,
        linkedAuthority: linkedAuthority,
      ),
      StartNodeResult.success,
    );
    await _waitForDirectRelayReady(stack);
    final senderTransportPeerId = stack.p2pService.currentState.peerId;
    expect(senderTransportPeerId, credential.transportPeerId);
    expect(senderTransportPeerId, isNot(stack.identity.peerId));

    // This is the runner's release fixture: publish only after the linked node
    // is actually authenticated and relay-ready.
    writeSharedJson(
      _signalName('alice_identity.json'),
      _peerIdentityFixture(stack.identity),
    );
    final (qrResult, qrDocument) = await buildDirectLinkedDeviceQr(
      linkedAuthority: linkedAuthority,
      accountPeerId: stack.identity.peerId,
      accountPublicKey: stack.identity.publicKey,
      accountPrivateKey: stack.identity.privateKey,
      deviceMlKemPublicKey: stack.identity.mlKemPublicKey,
      callSign: (data, privateKey) => callSignPayload(
        bridge: stack.bridge,
        dataToSign: data,
        privateKey: privateKey,
      ),
      selector: const DirectLinkedDeviceSelector(),
    );
    expect(qrResult, BuildDirectLinkedDeviceQrResult.success);
    expect(qrDocument, isNotNull);
    writeSharedJson(_signalName('fanout_linked_qr.json'), <String, dynamic>{
      'document': qrDocument,
    });

    final bobFixture = await waitForSharedJson(
      _signalName('fanout_b_identity.json'),
      timeout: const Duration(minutes: 12),
    );
    final bobContact = _contactFromFixture(bobFixture, 'Bob TC362');
    await stack.contactRepo.addContact(bobContact);
    final offlineDeviceId = bobFixture['offlineDeviceId'] as String;
    final offlineTransportPeerId =
        bobFixture['offlineTransportPeerId'] as String;
    final offlineTransportPublicKey =
        bobFixture['offlineTransportPublicKey'] as String;
    final offlineMlKemPublicKey = bobFixture['offlineMlKemPublicKey'] as String;
    expect(offlineTransportPeerId, isNot(bobContact.peerId));
    expect(offlineMlKemPublicKey, isNot(bobContact.mlKemPublicKey));

    final stagedOffline = await dbStageDirectContactDeviceBinding(
      stack.db,
      contactAccountPeerId: bobContact.peerId,
      accountSigningPublicKey: bobContact.publicKey,
      deviceId: offlineDeviceId,
      transportPeerId: offlineTransportPeerId,
      transportPublicKey: offlineTransportPublicKey,
      deviceMlKemPublicKey: offlineMlKemPublicKey,
      stagedAt: DateTime.now().toUtc().toIso8601String(),
    );
    expect(stagedOffline, DirectContactDeviceBindingStageOutcome.staged);
    final offlineFingerprint = computeDirectContactDeviceBindingFingerprint(
      contactAccountPeerId: bobContact.peerId,
      accountSigningPublicKey: bobContact.publicKey,
      deviceId: offlineDeviceId,
      transportPeerId: offlineTransportPeerId,
      transportPublicKey: offlineTransportPublicKey,
      deviceMlKemPublicKey: offlineMlKemPublicKey,
    );
    expect(
      await dbVerifyDirectContactDeviceBinding(
        stack.db,
        contactAccountPeerId: bobContact.peerId,
        deviceId: offlineDeviceId,
        expectedFingerprint: offlineFingerprint,
        expectedAccountSigningPublicKey: bobContact.publicKey,
        decidedAt: DateTime.now().toUtc().toIso8601String(),
      ),
      isTrue,
    );

    // Strong admission boundary: resolve once before the source copy, parent
    // write, attachment write, blob encryption, upload or event network.
    final mediaAdmission = await resolveDirectMediaFanoutAdmission(
      mediaAttachmentRepository: stack.mediaAttachmentRepo,
      contactAccountPeerId: bobContact.peerId,
      canServeLinkedFanout:
          kDirectLinkedDevicesEnabled &&
          kDirectLinkedEventFanoutEnabled &&
          kDirectMediaBlobCustodyClientEnabled &&
          kDirectLinkedMediaFanoutEnabled,
    );
    expect(mediaAdmission.requiresLinkedFanout, isTrue);
    final snapshot = mediaAdmission.snapshot!;
    expect(snapshot.rosterInitialized, isTrue);
    expect(snapshot.targets.map((target) => target.peerId).toList(), <String>[
      bobContact.peerId,
      offlineTransportPeerId,
    ]);

    await waitForSharedSignal(
      _signalName('fanout_b_ready'),
      timeout: const Duration(minutes: 5),
    );

    final capturedEventCandidates = <DirectEventFanoutTargetCandidate>[];
    final eventFanout = DirectEventFanoutAuthoring(
      selector: const DirectLinkedEventFanoutSelector(),
      linkedOrigin: true,
      senderTransportPeerId: senderTransportPeerId!,
      readSnapshot: stack.messageRepo.readDirectContactFanoutSnapshot,
      encrypt: ({required recipientMlKemPublicKey, required plaintext}) async {
        final encrypted = await callEncryptMessage(
          bridge: stack.bridge,
          recipientMlKemPublicKey: recipientMlKemPublicKey,
          plaintext: plaintext,
        );
        if (encrypted['ok'] != true) return null;
        return (
          kem: encrypted['kem'] as String,
          ciphertext: encrypted['ciphertext'] as String,
          nonce: encrypted['nonce'] as String,
        );
      },
      loadTextSiblings: stack.messageRepo.loadDirectTextFanoutSiblings,
      stageTextFanout:
          ({
            required stagedRow,
            required messageId,
            required contactAccountPeerId,
            required senderTransportPeerId,
            required expectedSnapshot,
            required candidates,
          }) async {
            capturedEventCandidates
              ..clear()
              ..addAll(candidates);
            return stack.messageRepo.stageDirectTextFanout(
              stagedRow: stagedRow,
              messageId: messageId,
              contactAccountPeerId: contactAccountPeerId,
              senderTransportPeerId: senderTransportPeerId,
              expectedSnapshot: expectedSnapshot,
              candidates: candidates,
            );
          },
      loadEventSiblings: stack.messageRepo.loadDirectEventFanoutSiblings,
      stageMutationFanout:
          ({
            required expectedRow,
            required stagedRow,
            required kind,
            required eventId,
            required parentMessageId,
            required contactAccountPeerId,
            required senderTransportPeerId,
            required expectedSnapshot,
            required candidates,
          }) => stack.messageRepo.stageDirectTextMutationFanout(
            expectedRow: expectedRow,
            stagedRow: stagedRow,
            kind: kind,
            eventId: eventId,
            parentMessageId: parentMessageId,
            contactAccountPeerId: contactAccountPeerId,
            senderTransportPeerId: senderTransportPeerId,
            expectedSnapshot: expectedSnapshot,
            candidates: candidates,
          ),
      stageReactionFanout:
          ({
            required reactionRow,
            required action,
            required parentMessageId,
            required contactAccountPeerId,
            required senderTransportPeerId,
            required expectedSnapshot,
            required candidates,
          }) => throw StateError('TC-362 aggregate authors no reaction'),
    );

    final idScope = _plan362Sha256(configuredRunId).substring(0, 12);
    final eventMessageId = 'tc362_${idScope}_event';
    final mediaMessageId = 'tc362_${idScope}_media';
    final attachmentId = 'tc362_${idScope}_blob';
    pendingMediaMessageId = mediaMessageId;
    final eventTimestamp = DateTime.now().toUtc().toIso8601String();
    final (eventResult, eventMessage) = await sendChatMessage(
      p2pService: stack.p2pService,
      messageRepo: stack.messageRepo,
      targetPeerId: bobContact.peerId,
      text: 'TC-362 linked event $idScope',
      senderPeerId: stack.identity.peerId,
      senderUsername: stack.identity.username,
      messageId: eventMessageId,
      preassignedMessageIdIsFresh: true,
      timestamp: eventTimestamp,
      createdAt: eventTimestamp,
      bridge: stack.bridge,
      recipientMlKemPublicKey: bobContact.mlKemPublicKey,
      directEventFanout: eventFanout,
    );
    expect(eventResult, SendChatMessageResult.success);
    expect(eventMessage, isNotNull);
    expect(capturedEventCandidates, hasLength(2));

    final mediaTimestamp = DateTime.now().toUtc().toIso8601String();
    plaintextSource = File('${Directory.systemTemp.path}/tc362_$idScope.png');
    await plaintextSource.writeAsBytes(_plan362TinyPngBytes(), flush: true);
    final pendingPath = await stack.mediaFileManager.copyToDurableStorage(
      sourceFilePath: plaintextSource.path,
      messageId: mediaMessageId,
      attachmentId: attachmentId,
      mime: 'image/png',
    );
    final pendingAbsolutePath = await stack.mediaFileManager.resolveStoredPath(
      pendingPath,
    );
    final intentId = computeDirectMediaCustodyIntentId(
      messageId: mediaMessageId,
      attachmentIds: <String>[attachmentId],
    );
    final mediaParent = ConversationMessage(
      id: mediaMessageId,
      contactPeerId: bobContact.peerId,
      senderPeerId: stack.identity.peerId,
      text: '',
      timestamp: mediaTimestamp,
      status: 'sending',
      isIncoming: false,
      createdAt: mediaTimestamp,
      directMediaCustodyIntentId: intentId,
    );
    final pendingAttachment = MediaAttachment(
      id: attachmentId,
      messageId: mediaMessageId,
      mime: 'image/png',
      size: await File(pendingAbsolutePath).length(),
      mediaType: 'image',
      width: 1,
      height: 1,
      localPath: pendingPath,
      downloadStatus: 'upload_pending',
      createdAt: mediaTimestamp,
      ownerLane: MediaOwnerLane.direct,
    );
    await stack.messageRepo.saveMessage(mediaParent);
    await stack.mediaAttachmentRepo.saveAttachment(
      pendingAttachment,
      owner: MediaOwnerLane.direct,
    );

    final coordinator = PreparedDirectMediaBlobCustodyCoordinator(
      repository: stack.mediaAttachmentRepo,
      artifactStore: artifactStore,
    );
    final blobResult = await coordinator.prepareAndUploadFreshFanout(
      bridge: stack.bridge,
      identityPeerId: stack.identity.peerId,
      contactAccountPeerId: bobContact.peerId,
      snapshot: snapshot,
      expectedParent: mediaParent,
      sources: <PreparedDirectMediaBlobSource>[
        PreparedDirectMediaBlobSource(
          attachment: pendingAttachment,
          plaintextPath: pendingAbsolutePath,
        ),
      ],
    );
    expect(blobResult.isComplete, isTrue);
    expect(blobResult.attachments, hasLength(1));
    expect(blobResult.targetRows.keys.toSet(), <String>{
      bobContact.peerId,
      offlineTransportPeerId,
    });
    final blobRows = blobResult.targetRows.values
        .expand((rows) => rows)
        .toList(growable: false);
    expect(blobRows, hasLength(2));
    artifactRelativePaths.addAll(
      blobRows.map((row) => row.ciphertextRelativePath!).toSet(),
    );
    final contentHashes = blobRows.map((row) => row.contentHash).toSet();
    final artifactPaths = blobRows
        .map((row) => row.ciphertextRelativePath)
        .toSet();
    expect(contentHashes, hasLength(1));
    expect(artifactPaths, hasLength(1));
    expect(
      blobRows.every(
        (row) => row.state == DirectMediaBlobCustodyState.outgoingStored,
      ),
      isTrue,
    );

    final (mediaResult, mediaMessage) = await sendChatMessage(
      p2pService: stack.p2pService,
      messageRepo: stack.messageRepo,
      targetPeerId: bobContact.peerId,
      text: '',
      senderPeerId: stack.identity.peerId,
      senderUsername: stack.identity.username,
      messageId: mediaMessageId,
      preassignedMessageIdIsFresh: false,
      timestamp: mediaTimestamp,
      createdAt: mediaTimestamp,
      bridge: stack.bridge,
      recipientMlKemPublicKey: bobContact.mlKemPublicKey,
      mediaAttachments: blobResult.attachments,
      mediaAttachmentRepo: stack.mediaAttachmentRepo,
      directLinkedMediaFanout: DirectLinkedMediaFanoutContext(
        contactAccountPeerId: bobContact.peerId,
        snapshot: snapshot,
        targetRows: blobResult.targetRows,
      ),
    );
    expect(mediaResult, SendChatMessageResult.success);
    expect(mediaMessage, isNotNull);
    expect(stack.mediaFanoutEnvelopeBindings, hasLength(2));

    writeSharedJson(
      directLinkedDeviceEventBlobFanoutTargetFixtureFileName(configuredRunId),
      <String, dynamic>{
        'schema': directLinkedDeviceEventBlobFanoutTargetFixtureSchema,
        'schemaVersion':
            directLinkedDeviceEventBlobFanoutTargetFixtureSchemaVersion,
        'runId': configuredRunId,
        'liveRecipientPeerId': bobContact.peerId,
        'offlineRecipientPeerId': offlineTransportPeerId,
        'eventMessageId': eventMessageId,
        'mediaMessageId': mediaMessageId,
        'attachmentId': attachmentId,
      },
    );
    writeSharedText(_signalName('fanout_authored'), 'ok');
    await waitForSharedSignal(
      _signalName('fanout_b_complete'),
      timeout: const Duration(minutes: 5),
    );

    final eventByRecipient = <String, String>{
      for (final candidate in capturedEventCandidates)
        candidate.recipientPeerId: candidate.wireEnvelope,
    };
    final mediaByRecipient = <String, String>{
      for (final binding in stack.mediaFanoutEnvelopeBindings)
        binding['recipientPeerId']!: binding['wireEnvelope']!,
    };
    expect(eventByRecipient.keys, <String>{
      bobContact.peerId,
      offlineTransportPeerId,
    });
    expect(mediaByRecipient.keys, <String>{
      bobContact.peerId,
      offlineTransportPeerId,
    });
    for (final envelope in <String>[
      ...eventByRecipient.values,
      ...mediaByRecipient.values,
    ]) {
      expect(
        (jsonDecode(envelope) as Map<String, dynamic>)['senderPeerId'],
        senderTransportPeerId,
      );
    }

    final ciphertextSha256 = contentHashes.single;
    final absoluteCiphertextPath = await artifactStore.resolveOwnedArtifactPath(
      identityPeerId: stack.identity.peerId,
      relativePath: artifactRelativePaths.single,
    );
    expect(absoluteCiphertextPath, isNotNull);
    expect(
      sha256
          .convert(await File(absoluteCiphertextPath!).readAsBytes())
          .toString(),
      ciphertextSha256,
    );
    final liveBlobRow = blobResult.targetRows[bobContact.peerId]!.single;
    final offlineBlobRow =
        blobResult.targetRows[offlineTransportPeerId]!.single;
    expect(liveBlobRow.contentHash, offlineBlobRow.contentHash);
    expect(
      liveBlobRow.ciphertextRelativePath,
      offlineBlobRow.ciphertextRelativePath,
    );

    writeSharedJson(
      directLinkedDeviceEventBlobFanoutArtifactFileName(
        configuredRunId,
        'primary',
      ),
      <String, dynamic>{
        ..._plan362CommonArtifact(
          role: 'primary',
          accountAPeerId: stack.identity.peerId,
          accountATransportPeerId: senderTransportPeerId,
          accountBPeerId: bobContact.peerId,
          offlineBTransportPeerId: offlineTransportPeerId,
          eventMessageId: eventMessageId,
          mediaMessageId: mediaMessageId,
          attachmentId: attachmentId,
          ciphertextSha256: ciphertextSha256,
        ),
        'legacyBMlKemPublicKeySha256': _plan362Sha256(
          bobContact.mlKemPublicKey!,
        ),
        'offlineBMlKemPublicKeySha256': _plan362Sha256(offlineMlKemPublicKey),
        'eventLegacyEnvelopeSha256': _plan362Sha256(
          eventByRecipient[bobContact.peerId]!,
        ),
        'eventOfflineEnvelopeSha256': _plan362Sha256(
          eventByRecipient[offlineTransportPeerId]!,
        ),
        'mediaLegacyEnvelopeSha256': _plan362Sha256(
          mediaByRecipient[bobContact.peerId]!,
        ),
        'mediaOfflineEnvelopeSha256': _plan362Sha256(
          mediaByRecipient[offlineTransportPeerId]!,
        ),
        'transportDistinctFromAccount':
            senderTransportPeerId != stack.identity.peerId,
        'targetMlKemKeysDistinct':
            bobContact.mlKemPublicKey != offlineMlKemPublicKey,
        'eventTargetCount': eventByRecipient.length,
        'mediaTargetCount': mediaByRecipient.length,
        'oneBlobAcrossTargets':
            contentHashes.length == 1 && artifactPaths.length == 1,
        'eventEnvelopesDistinct': eventByRecipient.values.toSet().length == 2,
        'mediaEnvelopesDistinct': mediaByRecipient.values.toSet().length == 2,
        'offlineEventSiblingExact':
            (jsonDecode(eventByRecipient[offlineTransportPeerId]!)
                as Map<String, dynamic>)['id'] ==
            eventMessageId,
        'offlineBlobSiblingExact':
            offlineBlobRow.contentHash == ciphertextSha256 &&
            offlineBlobRow.ciphertextRelativePath ==
                liveBlobRow.ciphertextRelativePath,
      },
    );
    writeSharedText(_signalName('fanout_primary_complete'), 'ok');
    await Future<void>.delayed(const Duration(seconds: 2));
  } finally {
    final mediaMessageId = pendingMediaMessageId;
    if (mediaMessageId != null) {
      try {
        await stack.mediaFileManager.deletePendingUploadDir(mediaMessageId);
      } on Object catch (error) {
        debugPrint('TC-362 pending cleanup failed: ${error.runtimeType}');
      }
    }
    for (final path in artifactRelativePaths) {
      try {
        await artifactStore.deleteOwnedArtifact(
          identityPeerId: stack.identity.peerId,
          relativePath: path,
        );
      } on Object catch (error) {
        debugPrint('TC-362 artifact cleanup failed: ${error.runtimeType}');
      }
    }
    final source = plaintextSource;
    if (source != null && await source.exists()) {
      try {
        await source.delete();
      } on Object catch (error) {
        debugPrint('TC-362 plaintext cleanup failed: ${error.runtimeType}');
      }
    }
    await restoreRunScopedSecureState();
    await stack.teardown();
  }
}
