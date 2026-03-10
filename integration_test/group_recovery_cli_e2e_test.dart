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
    version: 25,
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
    },
    onUpgrade: (db, oldVersion, newVersion) async {
      if (oldVersion < 2) await runMessagesTableMigration(db);
      if (oldVersion < 3) await runMlKemKeysMigration(db);
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

  final p2pService = P2PServiceImpl(bridge: bridge);
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
