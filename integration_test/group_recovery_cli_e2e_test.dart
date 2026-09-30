import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:flutter_app/core/bridge/go_bridge_client.dart';
import 'package:flutter_app/core/database/encrypted_db_opener.dart';
import 'package:flutter_app/core/database/app_database_version.dart';
import 'package:flutter_app/core/database/production_migration_registry.dart';
import 'package:flutter_app/core/database/helpers/contacts_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_invite_delivery_attempts_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_keys_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_members_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_messages_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/groups_db_helpers.dart';
import 'package:flutter_app/core/services/p2p_service_impl.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/contacts/data/repositories/contact_repository_impl.dart';
import 'package:flutter_app/features/groups/application/create_group_with_members_use_case.dart';
import 'package:flutter_app/features/groups/application/drain_group_offline_inbox_use_case.dart';
import 'package:flutter_app/features/groups/application/group_message_listener.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/data/repositories/group_message_repository_impl.dart';
import 'package:flutter_app/features/groups/data/repositories/group_invite_delivery_attempt_repository_impl.dart';
import 'package:flutter_app/features/groups/data/repositories/group_repository_impl.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';

import '../test/shared/fakes/in_memory_inbox_staging_repository.dart';
import '_support/canonical_runtime_device_test_lease.dart';
import '_support/cli_peer_fixture.dart';
import '_support/fake_secure_key_store.dart';
import '_support/signal_files.dart';

const _readDir = String.fromEnvironment('E2E_TEMP_DIR', defaultValue: '/tmp');
const _writeDir = String.fromEnvironment('E2E_WRITE_DIR', defaultValue: '/tmp');
const _dbName = String.fromEnvironment(
  'E2E_DB_NAME',
  defaultValue: 'group_recovery_cli_e2e.db',
);

// Flat (non-prefixed, non-run-keyed) signal families with SEPARATE read/write
// dirs. The reader polls files dropped by the CLI orchestrator in `_readDir`;
// the writer drops fixtures the orchestrator consumes in `_writeDir`.
final _readSignals = SignalDir.flat(_readDir, role: 'group-recovery-cli');
final _writeSignals = SignalDir.flat(_writeDir, role: 'group-recovery-cli');

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
  final GroupInviteDeliveryAttemptRepositoryImpl groupInviteDeliveryAttemptRepo;
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
    required this.groupInviteDeliveryAttemptRepo,
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
        _writeSignals.delete(name);
      } catch (_) {}
    }
  }
}

Future<_TestStack> _setupStack() async {
  final cliPeer = loadCliPeerFixture();
  final secureKeyStore = FakeSecureKeyStore();

  final db = await openEncryptedDatabase(
    secureKeyStore: secureKeyStore,
    dbName: _dbName,
    version: currentIdentityDatabaseVersion,
    onCreate: runProductionOnCreate,
    onUpgrade: runProductionOnUpgrade,
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

  _writeSignals.writeJson('flutter_peer_fixture.json', {
    'peerId': identity.peerId,
    'publicKey': identity.publicKey,
    if (identity.mlKemPublicKey != null)
      'mlKemPublicKey': identity.mlKemPublicKey,
  }, createDir: true);

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
    inviteDeliveryAttemptRepo: groupInviteDeliveryAttemptRepo,
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
    groupInviteDeliveryAttemptRepo: groupInviteDeliveryAttemptRepo,
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

  final runtimeLease = CanonicalRuntimeDeviceTestLease(
    binding: 'group-recovery-cli-device-test',
  );
  setUpAll(runtimeLease.acquire);
  tearDownAll(runtimeLease.release);

  if (Platform.isLinux || Platform.isMacOS || Platform.isWindows) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  testWidgets('real CLI peer drives live and inbox group recovery', (
    tester,
  ) async {
    if (loadCliPeerFixture() == null) {
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
        inviteDeliveryAttemptRepo: stack.groupInviteDeliveryAttemptRepo,
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

      _writeSignals.writeJson('group_recovery_fixture.json', {
        'groupId': result.group.id,
        'groupKey': keyInfo!.encryptedKey,
        'keyEpoch': keyInfo.keyGeneration,
        'groupConfig': _groupConfigFromModel(result.group, memberMaps),
      }, createDir: true);

      await _waitForIncomingGroupCount(stack.groupMsgRepo, result.group.id, 1);
      _writeSignals.writeSignal(
        'e2e_group_live_received',
        content: 'ok',
        createDir: true,
      );

      await _readSignals.waitForSignal(
        'e2e_group_cli_inbox_stored',
        timeout: const Duration(seconds: 60),
      );
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
