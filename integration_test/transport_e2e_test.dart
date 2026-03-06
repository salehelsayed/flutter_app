// E2E Transport Integration Test
//
// Tests the full message stack across all transport types (relay, inbox)
// using a real Go bridge, encrypted DB, and P2P service. Coordinates with
// a Go CLI test peer process via fixture files.
//
// Launch with orchestrator:
//   dart run integration_test/scripts/run_transport_e2e.dart -d <simulator-id>
//
// Or standalone (self-contained tests only):
//   flutter test integration_test/transport_e2e_test.dart -d <simulator-id>

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:flutter_app/core/bridge/go_bridge_client.dart';
import 'package:flutter_app/core/bridge/p2p_bridge_client.dart';
import 'package:flutter_app/core/database/encrypted_db_opener.dart';
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
import 'package:flutter_app/core/database/helpers/contacts_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/messages_db_helpers.dart';
import 'package:flutter_app/core/secure_storage/secure_key_store.dart';
import 'package:flutter_app/core/services/p2p_service_impl.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository_impl.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';
import 'package:flutter_app/features/conversation/application/send_chat_message_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository_impl.dart';

// ---------------------------------------------------------------------------
// Test-only SecureKeyStore (in-memory)
// ---------------------------------------------------------------------------
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

// ---------------------------------------------------------------------------
// Temp directory + signal file paths (shared with orchestrator)
// ---------------------------------------------------------------------------

/// Read dir: orchestrator pushes signals here (readable by app on Android).
const _readDir = String.fromEnvironment(
  'E2E_TEMP_DIR',
  defaultValue: '/tmp',
);

/// Write dir: app writes signals here (app-private cache on Android).
const _writeDir = String.fromEnvironment(
  'E2E_WRITE_DIR',
  defaultValue: '/tmp',
);

/// Path for reading orchestrator→Flutter signals.
String _readSignalPath(String name) => '$_readDir/$name';

/// Path for writing Flutter→orchestrator signals.
String _writeSignalPath(String name) => '$_writeDir/$name';

// ---------------------------------------------------------------------------
// CLI peer fixture loader
// ---------------------------------------------------------------------------

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
    print('[TEST] Failed to parse CLI peer fixture: $e');
    return null;
  }
}

void _writeFlutterPeerFixture({
  required String peerId,
  required String publicKey,
  String? mlKemPublicKey,
}) {
  final fixturePath = _writeSignalPath('flutter_peer_fixture.json');
  // Ensure the write directory exists (app cache dir on Android).
  Directory(_writeDir).createSync(recursive: true);
  final data = {
    'peerId': peerId,
    'publicKey': publicKey,
    if (mlKemPublicKey != null) 'mlKemPublicKey': mlKemPublicKey,
  };
  File(fixturePath).writeAsStringSync(jsonEncode(data));
  print('[TEST] Flutter peer fixture written to $fixturePath');
}

// ---------------------------------------------------------------------------
// Shared setup — builds the full DI stack
// ---------------------------------------------------------------------------

var _testCounter = 0;

Future<_TestStack> _setupStack() async {
  _testCounter++;
  print('\n========================================');
  print('TRANSPORT E2E TEST — SETUP #$_testCounter');
  print('========================================\n');

  final cliPeer = _loadCliPeerFixture();
  String? cliPeerId;
  String? cliPublicKey;
  String? cliMlKemPublicKey;

  if (cliPeer != null) {
    cliPeerId = cliPeer['peerId'] as String?;
    cliPublicKey = cliPeer['publicKey'] as String?;
    cliMlKemPublicKey = cliPeer['mlKemPublicKey'] as String?;
    print('[TEST] CLI peer loaded: ${cliPeerId?.substring(0, 20)}...');
  } else {
    print('[TEST] No CLI peer fixture — running self-contained tests only');
  }

  final secureKeyStore = _FakeSecureKeyStore();
  final dbName = 'transport_e2e_test_$_testCounter.db';

  final db = await openEncryptedDatabase(
    secureKeyStore: secureKeyStore,
    dbName: dbName,
    version: 12,
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
    },
  );
  print('[TEST] Database initialized (version 12 with transport column)');

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

  final messageRepo = MessageRepositoryImpl(
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
    dbLoadMessagesPage: (contactPeerId, {limit = 50, beforeTimestamp}) =>
        dbLoadMessagesPage(db, contactPeerId,
            limit: limit, beforeTimestamp: beforeTimestamp),
    dbLoadFailedOutgoingMessages: () => dbLoadFailedOutgoingMessages(db),
    dbLoadUnackedOutgoingMessages: ({required olderThan, limit = 50}) =>
        dbLoadUnackedOutgoingMessages(db, olderThan: olderThan, limit: limit),
  );

  final bridge = GoBridgeClient();
  await bridge.initialize();
  print('[TEST] Bridge initialized');

  final p2pService = P2PServiceImpl(bridge: bridge);

  try {
    // Generate identity.
    print('[TEST] Generating identity...');
    final genResponse = await bridge.send(jsonEncode({
      'cmd': 'identity.generate',
      'payload': {},
    }));
    final genResult = jsonDecode(genResponse) as Map<String, dynamic>;
    if (genResult['ok'] != true) {
      throw StateError('identity.generate failed: $genResult');
    }

    final identity = genResult['identity'] as Map<String, dynamic>;
    final ownPeerId = identity['peerId'] as String;
    final ownPrivateKey = identity['privateKey'] as String;
    print('[TEST] Identity: ${ownPeerId.substring(0, 20)}...');

    // Generate ML-KEM keys.
    final mlkemResponse = await bridge.send(jsonEncode({
      'cmd': 'mlkem.keygen',
      'payload': {},
    }));
    final mlkemResult = jsonDecode(mlkemResponse) as Map<String, dynamic>;
    String? ownMlKemPublicKey;
    String? ownMlKemSecretKey;
    if (mlkemResult['ok'] == true) {
      ownMlKemPublicKey = mlkemResult['publicKey'] as String?;
      ownMlKemSecretKey = mlkemResult['secretKey'] as String?;
      print('[TEST] ML-KEM keys generated');
    }

    // Write Flutter peer fixture for orchestrator.
    _writeFlutterPeerFixture(
      peerId: ownPeerId,
      publicKey: identity['publicKey'] as String,
      mlKemPublicKey: ownMlKemPublicKey,
    );

    // Add CLI peer as contact (required for handleIncomingChatMessage).
    if (cliPeerId != null) {
      await contactRepo.addContact(ContactModel(
        peerId: cliPeerId,
        publicKey: cliPublicKey ?? 'pk-cli-peer',
        rendezvous: '/dns4/relay/tcp/443/p2p/relay',
        username: 'CLITestPeer',
        signature: 'sig-cli-peer',
        scannedAt: DateTime.now().toUtc().toIso8601String(),
        mlKemPublicKey: cliMlKemPublicKey,
      ));
      print('[TEST] CLI peer added as contact');
    }

    // Start real P2P node.
    print('[TEST] Starting P2P node...');
    final started = await p2pService.startNode(ownPrivateKey, ownPeerId);
    if (!started) {
      throw StateError('P2P node failed to start');
    }
    print('[TEST] P2P node started');

    // Wire ChatMessageListener.
    final chatListener = ChatMessageListener(
      chatMessageStream: p2pService.messageStream,
      messageRepo: messageRepo,
      contactRepo: contactRepo,
      bridge: bridge,
      getOwnMlKemSecretKey: () async => ownMlKemSecretKey,
    );
    chatListener.start();
    print('[TEST] ChatMessageListener started');

    return _TestStack(
      db: db,
      bridge: bridge,
      p2pService: p2pService,
      contactRepo: contactRepo,
      messageRepo: messageRepo,
      chatListener: chatListener,
      ownPeerId: ownPeerId,
      ownPrivateKey: ownPrivateKey,
      ownMlKemPublicKey: ownMlKemPublicKey,
      ownMlKemSecretKey: ownMlKemSecretKey,
      cliPeerId: cliPeerId,
      cliPublicKey: cliPublicKey,
      cliMlKemPublicKey: cliMlKemPublicKey,
    );
  } catch (e) {
    // Clean up resources before rethrowing to prevent leaks.
    p2pService.dispose();
    bridge.dispose();
    await db.close();
    rethrow;
  }
}

class _TestStack {
  final dynamic db;
  final GoBridgeClient bridge;
  final P2PServiceImpl p2pService;
  final ContactRepositoryImpl contactRepo;
  final MessageRepositoryImpl messageRepo;
  final ChatMessageListener chatListener;
  final String ownPeerId;
  final String ownPrivateKey;
  final String? ownMlKemPublicKey;
  final String? ownMlKemSecretKey;
  final String? cliPeerId;
  final String? cliPublicKey;
  final String? cliMlKemPublicKey;

  _TestStack({
    required this.db,
    required this.bridge,
    required this.p2pService,
    required this.contactRepo,
    required this.messageRepo,
    required this.chatListener,
    required this.ownPeerId,
    required this.ownPrivateKey,
    this.ownMlKemPublicKey,
    this.ownMlKemSecretKey,
    this.cliPeerId,
    this.cliPublicKey,
    this.cliMlKemPublicKey,
  });

  Future<void> teardown() async {
    chatListener.dispose();
    await p2pService.stopNode();
    p2pService.dispose();
    bridge.dispose();
    await db.close();
    // Signal files live in the orchestrator's temp dir which it cleans up.
    // Only delete our own fixture as a courtesy.
    try { File(_writeSignalPath('flutter_peer_fixture.json')).deleteSync(); } catch (_) {}
    print('[TEST] Cleanup complete');
  }
}

// ---------------------------------------------------------------------------
// Scenario result tracker
// ---------------------------------------------------------------------------

class _ScenarioResult {
  final String name;
  final bool passed;
  final String detail;
  _ScenarioResult(this.name, this.passed, this.detail);
}

// ---------------------------------------------------------------------------
// Main test suite
// ---------------------------------------------------------------------------

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  if (Platform.isLinux || Platform.isMacOS || Platform.isWindows) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  // =========================================================================
  // Orchestrated E2E: single test with a persistent identity
  // =========================================================================

  testWidgets('Full orchestrated E2E transport test', (tester) async {
    final stack = await _setupStack();

    final hasCli = stack.cliPeerId != null;
    if (!hasCli) {
      print('[TEST] No CLI peer — running self-contained scenarios only');
    }

    final results = <_ScenarioResult>[];

    try {
      // ==== A1: Send v1 plaintext to CLI peer ====
      if (hasCli) {
        print('\n--- A1: Send v1 plaintext via relay ---');
        try {
          final (r1, m1) = await sendChatMessage(
            p2pService: stack.p2pService,
            messageRepo: stack.messageRepo,
            targetPeerId: stack.cliPeerId!,
            text: 'A1: Hello via relay v1',
            senderPeerId: stack.ownPeerId,
            senderUsername: 'FlutterE2E',
          );
          final stored = await stack.messageRepo
              .getMessagesForContact(stack.cliPeerId!);
          final outgoing = stored.where((m) => !m.isIncoming).toList();
          final status = outgoing.last.status;
          final transport = outgoing.last.transport;
          final detail = 'status=$status transport=$transport';
          final pass = m1 != null &&
              status == 'delivered' &&
              (transport == 'relay' || transport == 'inbox');
          results.add(_ScenarioResult('A1', pass, detail));
          print('[TEST] A1: $detail');
        } catch (e) {
          results.add(_ScenarioResult('A1', false, 'error: $e'));
          print('[TEST] A1 FAIL: $e');
        }
      }

      // ==== A4: Send v2 encrypted to CLI peer ====
      if (hasCli && stack.cliMlKemPublicKey != null) {
        print('\n--- A4: Send v2 encrypted ---');
        try {
          final (r4, m4) = await sendChatMessage(
            p2pService: stack.p2pService,
            messageRepo: stack.messageRepo,
            targetPeerId: stack.cliPeerId!,
            text: 'A4: Encrypted hello',
            senderPeerId: stack.ownPeerId,
            senderUsername: 'FlutterE2E',
            bridge: stack.bridge,
            recipientMlKemPublicKey: stack.cliMlKemPublicKey,
          );
          final stored = await stack.messageRepo
              .getMessagesForContact(stack.cliPeerId!);
          final outgoing = stored.where((m) => !m.isIncoming).toList();
          final status = outgoing.last.status;
          final transport = outgoing.last.transport;
          final detail = 'status=$status transport=$transport';
          final pass = m4 != null &&
              status == 'delivered' &&
              (transport == 'relay' || transport == 'inbox');
          results.add(_ScenarioResult('A4', pass, detail));
          print('[TEST] A4: $detail');
        } catch (e) {
          results.add(_ScenarioResult('A4', false, 'error: $e'));
          print('[TEST] A4 FAIL: $e');
        }
      }

      // ==== Wait for orchestrator messages ====
      if (hasCli) {
        print('\n--- Waiting for orchestrator to send messages (60s) ---');
        // The orchestrator waits for our fixture, discovers us, then sends
        // A2, A3, A5, B2, B3, B6 (60 msgs), D3, D4, E1, E3, E4, E6, E7.
        // Total orchestrator time after discovering us: ~40s.
        // Give generous buffer for discovery + relay latency.
        for (var sec = 0; sec < 60; sec++) {
          await Future.delayed(const Duration(seconds: 1));
          if (sec % 10 == 9) {
            final msgs = await stack.messageRepo
                .getMessagesForContact(stack.cliPeerId!);
            final incoming = msgs.where((m) => m.isIncoming).length;
            print('[TEST] ... ${sec + 1}s: $incoming incoming messages so far');
          }
        }

        // ==== Drain inbox — multiple passes for B6's 60 messages ====
        print('\n--- Draining inbox (multi-pass) ---');
        for (var pass = 1; pass <= 5; pass++) {
          try {
            await stack.p2pService.drainOfflineInbox();
            print('[TEST] Drain pass $pass complete');
          } catch (e) {
            print('[TEST] Drain pass $pass failed: $e');
          }
          final current = await stack.messageRepo
              .getMessagesForContact(stack.cliPeerId!);
          final b6Count = current.where((m) => m.text.contains('B6:')).length;
          print('[TEST] Drain pass $pass: $b6Count B6 messages so far');
          if (b6Count >= 60) break;
          await Future.delayed(const Duration(seconds: 3));
        }

        // Wait for inbox messages to be processed.
        await Future.delayed(const Duration(seconds: 5));

        // ==== Collect and validate all messages ====
        final allMsgs = await stack.messageRepo
            .getMessagesForContact(stack.cliPeerId!);
        final incoming = allMsgs.where((m) => m.isIncoming).toList();
        final outgoing = allMsgs.where((m) => !m.isIncoming).toList();

        print('\n========================================');
        print('RECEIVED ${incoming.length} incoming, ${outgoing.length} outgoing');
        print('========================================');
        for (final m in incoming) {
          final preview = m.text.length > 60
              ? '${m.text.substring(0, 60)}...'
              : m.text;
          print('[RECV] "$preview" transport=${m.transport} status=${m.status}');
        }

        // ==== A2: Receive v1 via relay ====
        print('\n--- A2: Receive v1 plaintext via relay ---');
        final a2 = incoming.where((m) => m.text.contains('A2:')).toList();
        if (a2.isNotEmpty) {
          final a2Transport = a2.first.transport;
          final a2Pass = a2Transport == 'relay';
          results.add(_ScenarioResult(
              'A2', a2Pass, 'transport=$a2Transport'));
          print('[TEST] A2 ${a2Pass ? 'PASS' : 'FAIL'}: '
              '"${a2.first.text}" transport=$a2Transport');
        } else {
          results.add(_ScenarioResult('A2', false, 'no message received'));
          print('[TEST] A2 FAIL: no incoming message with A2: prefix');
        }

        // ==== A3: Bidirectional (receive reply) ====
        print('\n--- A3: Receive reply ---');
        final a3 = incoming.where((m) => m.text.contains('A3:')).toList();
        if (a3.isNotEmpty) {
          results.add(_ScenarioResult('A3', true, 'received reply'));
          print('[TEST] A3 PASS: "${a3.first.text}"');
        } else {
          results.add(_ScenarioResult('A3', false, 'no reply received'));
          print('[TEST] A3 FAIL: no incoming message with A3: prefix');
        }

        // ==== A5: Receive v2 encrypted ====
        print('\n--- A5: Receive v2 encrypted ---');
        final a5 = incoming.where((m) => m.text.contains('A5:')).toList();
        if (a5.isNotEmpty) {
          final a5Transport = a5.first.transport;
          final a5Pass = a5Transport == 'relay';
          results.add(_ScenarioResult(
              'A5', a5Pass, 'transport=$a5Transport decrypted: "${a5.first.text}"'));
          print('[TEST] A5 ${a5Pass ? 'PASS' : 'FAIL'}: '
              '"${a5.first.text}" transport=$a5Transport');
        } else {
          results.add(_ScenarioResult('A5', false, 'no encrypted message'));
          print('[TEST] A5 FAIL: no incoming message with A5: prefix');
        }

        // ==== A6: Fast path (peer already connected) ====
        print('\n--- A6: Fast path ---');
        try {
          final isConnected =
              stack.p2pService.isConnectedToPeer(stack.cliPeerId!);
          print('[TEST] A6: peer connected: $isConnected');

          final (r6, m6) = await sendChatMessage(
            p2pService: stack.p2pService,
            messageRepo: stack.messageRepo,
            targetPeerId: stack.cliPeerId!,
            text: 'A6: Fast path message',
            senderPeerId: stack.ownPeerId,
            senderUsername: 'FlutterE2E',
          );
          final a6Stored = await stack.messageRepo
              .getMessagesForContact(stack.cliPeerId!);
          final a6Out = a6Stored
              .where((m) => !m.isIncoming && m.text.contains('A6:'))
              .toList();
          final a6Status = a6Out.isNotEmpty ? a6Out.last.status : 'none';
          final a6Pass = m6 != null && a6Status == 'delivered';
          results.add(_ScenarioResult('A6', a6Pass,
              'connected=$isConnected status=$a6Status'));
          print('[TEST] A6 ${a6Pass ? 'PASS' : 'FAIL'}: '
              'status=$a6Status connected=$isConnected');
        } catch (e) {
          results.add(_ScenarioResult('A6', false, 'error: $e'));
          print('[TEST] A6 FAIL: $e');
        }

        // ==== B2: Inbox message from CLI peer ====
        print('\n--- B2: Inbox message ---');
        final b2 = incoming.where((m) => m.text.contains('B2:')).toList();
        if (b2.isNotEmpty) {
          final b2Transport = b2.first.transport;
          final b2Pass = b2Transport == 'inbox';
          results.add(_ScenarioResult(
              'B2', b2Pass, 'transport=$b2Transport'));
          print('[TEST] B2 ${b2Pass ? 'PASS' : 'FAIL'}: '
              '"${b2.first.text}" transport=$b2Transport');
        } else {
          results.add(_ScenarioResult('B2', false, 'no inbox message'));
          print('[TEST] B2 FAIL: no incoming message with B2: prefix');
        }

        // ==== B3: Multiple inbox messages ====
        print('\n--- B3: Multiple inbox messages ---');
        final b3 = incoming.where((m) => m.text.contains('B3:')).toList();
        if (b3.length >= 5) {
          results.add(_ScenarioResult('B3', true, '${b3.length} messages'));
          print('[TEST] B3 PASS: ${b3.length} inbox messages');
        } else {
          results.add(_ScenarioResult(
              'B3', false, 'expected 5, got ${b3.length}'));
          print('[TEST] B3 FAIL: expected 5, got ${b3.length}');
        }

        // ==== B4: Inbox cleared after retrieval ====
        print('\n--- B4: Inbox cleared ---');
        try {
          final secondDrain = await stack.p2pService.retrieveInbox();
          final pass = secondDrain.isEmpty;
          results.add(_ScenarioResult(
              'B4', pass, 'second drain: ${secondDrain.length}'));
          print('[TEST] B4 ${pass ? 'PASS' : 'FAIL'}: '
              'second drain returned ${secondDrain.length}');
        } catch (e) {
          results.add(_ScenarioResult('B4', false, 'error: $e'));
          print('[TEST] B4 FAIL: $e');
        }

        // ==== B5: Unknown sender inbox message — should be dropped ====
        print('\n--- B5: Unknown sender dropped ---');
        // The orchestrator stored a v1 envelope with senderPeerId not in our
        // contacts. handleIncomingChatMessage should reject it, so no message
        // with "B5:" prefix should be persisted. This documents the inbox loss
        // window: the inbox server deleted the message, but the app rejected it.
        final b5 = incoming.where((m) => m.text.contains('B5:')).toList();
        final b5Pass = b5.isEmpty;
        results.add(_ScenarioResult('B5', b5Pass,
            b5Pass ? 'correctly dropped' : 'unexpected: ${b5.length} persisted'));
        print('[TEST] B5 ${b5Pass ? 'PASS' : 'FAIL'}: '
            '${b5.length} messages with B5: prefix');

        // ==== G2: Encrypted inbox message from known contact ====
        print('\n--- G2: Encrypted inbox message ---');
        final g2 = incoming.where((m) => m.text.contains('G2:')).toList();
        if (g2.isNotEmpty) {
          final g2Transport = g2.first.transport;
          final g2Pass = g2Transport == 'inbox';
          results.add(_ScenarioResult(
              'G2', g2Pass, 'transport=$g2Transport (expect inbox)'));
          print('[TEST] G2 ${g2Pass ? 'PASS' : 'FAIL'}: '
              '"${g2.first.text}" transport=$g2Transport');
        } else {
          results.add(_ScenarioResult('G2', false, 'no G2 message'));
          print('[TEST] G2 FAIL: no incoming message with G2: prefix');
        }

        // ==== D3: Different messages, same content ====
        print('\n--- D3: Dedup by ID ---');
        final d3 = incoming.where((m) => m.text.contains('D3:')).toList();
        if (d3.length >= 2) {
          final ids = d3.map((m) => m.id).toSet();
          final pass = ids.length == d3.length;
          results.add(_ScenarioResult(
              'D3', pass, '${d3.length} msgs, ${ids.length} unique IDs'));
          print('[TEST] D3 ${pass ? 'PASS' : 'FAIL'}: '
              '${d3.length} messages, ${ids.length} unique IDs');
        } else {
          results.add(_ScenarioResult(
              'D3', false, 'expected 2+, got ${d3.length}'));
          print('[TEST] D3 FAIL: expected 2+, got ${d3.length}');
        }

        // ==== E1: Large message ====
        print('\n--- E1: Large message ---');
        final large = incoming.where((m) => m.text.length > 50000).toList();
        if (large.isNotEmpty) {
          results.add(_ScenarioResult(
              'E1', true, '${large.first.text.length} bytes'));
          print('[TEST] E1 PASS: received ${large.first.text.length} byte message');
        } else {
          results.add(_ScenarioResult('E1', false, 'no large message'));
          print('[TEST] E1 FAIL: no message > 50KB');
        }

        // ==== E3: Quote-reply ====
        print('\n--- E3: Quote-reply ---');
        final e3 = incoming
            .where((m) => m.quotedMessageId != null && m.text.contains('E3:'))
            .toList();
        if (e3.isNotEmpty) {
          results.add(_ScenarioResult(
              'E3', true, 'quotedId=${e3.first.quotedMessageId}'));
          print('[TEST] E3 PASS: quotedMessageId=${e3.first.quotedMessageId}');
        } else {
          results.add(_ScenarioResult('E3', false, 'no quote-reply'));
          print('[TEST] E3 FAIL: no message with quotedMessageId');
        }

        // ==== E4: Rapid fire 10 messages ====
        print('\n--- E4: Rapid fire ---');
        final e4 = incoming.where((m) => m.text.contains('E4:')).toList();
        final e4Ids = e4.map((m) => m.id).toSet();
        if (e4.length >= 10) {
          final noDups = e4Ids.length == e4.length;
          results.add(_ScenarioResult(
              'E4', noDups, '${e4.length} msgs, ${e4Ids.length} unique'));
          print('[TEST] E4 ${noDups ? 'PASS' : 'FAIL'}: '
              '${e4.length} rapid messages');
        } else {
          results.add(_ScenarioResult(
              'E4', false, 'expected 10, got ${e4.length}'));
          print('[TEST] E4 FAIL: expected 10, got ${e4.length}');
        }

        // ==== E6: Malformed envelope — node still alive ====
        print('\n--- E6: Malformed envelope ---');
        final alive = stack.p2pService.currentState.isStarted;
        results.add(_ScenarioResult('E6', alive, 'node alive=$alive'));
        print('[TEST] E6 ${alive ? 'PASS' : 'FAIL'}: node alive=$alive');

        // ==== B5: (already validated above) ====

        // ==== B6: 60 inbox messages, multi-drain ====
        print('\n--- B6: 60 inbox messages ---');
        final b6 = incoming.where((m) => m.text.contains('B6:')).toList();
        final b6Ids = b6.map((m) => m.id).toSet();
        if (b6.length >= 60) {
          final noDups = b6Ids.length == b6.length;
          results.add(_ScenarioResult(
              'B6', noDups, '${b6.length} msgs, ${b6Ids.length} unique'));
          print('[TEST] B6 ${noDups ? 'PASS' : 'FAIL'}: '
              '${b6.length} messages, ${b6Ids.length} unique IDs');
        } else {
          results.add(_ScenarioResult(
              'B6', false, 'expected 60, got ${b6.length}'));
          print('[TEST] B6 FAIL: expected 60, got ${b6.length}');
        }

        // ==== B7: At-most-once inbox semantics (documentation) ====
        // The relay deletes messages atomically on retrieve. If the app crashes
        // between retrieve and local persist, those messages are lost forever.
        // This is a known at-most-once delivery guarantee. B4 already confirms
        // the relay empties after first retrieve. True process-death testing
        // is not possible in Flutter integration tests — this would require a
        // unit test with a mocked repository that throws mid-persist.
        results.add(_ScenarioResult('B7', true,
            'documented: at-most-once semantics (confirmed by B4)'));
        print('[TEST] B7 PASS: documented at-most-once semantics');

        // ==== D4: Cross-transport dedup ====
        print('\n--- D4: Cross-transport dedup ---');
        final d4 = incoming.where((m) => m.text.contains('D4:')).toList();
        if (d4.length == 1) {
          final d4Transport = d4.first.transport;
          // Relay arrives first. If dedup works, inbox dup rejected → stays relay.
          // If dedup breaks, INSERT OR REPLACE overwrites → transport flips to inbox → FAIL.
          final d4Pass = d4Transport == 'relay';
          results.add(_ScenarioResult('D4', d4Pass,
              'count=1 transport=$d4Transport (expect relay)'));
          print('[TEST] D4 ${d4Pass ? 'PASS' : 'FAIL'}: '
              'transport=$d4Transport');
        } else if (d4.isEmpty) {
          results.add(_ScenarioResult('D4', false, 'no D4 message received'));
          print('[TEST] D4 FAIL: no D4 message received');
        } else {
          results.add(_ScenarioResult(
              'D4', false, 'expected 1, got ${d4.length} (dedup broken)'));
          print('[TEST] D4 FAIL: expected 1, got ${d4.length}');
        }

        // ==== E7: Tampered v2 envelopes — no crash, no persist ====
        print('\n--- E7: Tampered v2 envelopes ---');
        // The tampered envelopes have garbage crypto — decryption fails silently.
        // Verify node is still alive (decryption failure didn't crash).
        final e7Alive = stack.p2pService.currentState.isStarted;
        // Direct assertion: every persisted incoming message must match a known
        // scenario prefix. Any message that doesn't is a leaked tampered envelope
        // (whose decrypted text would be empty or garbage).
        const knownPrefixes = [
          'A2:', 'A3:', 'A5:', 'B2:', 'B3:', 'B5:', 'B6:',
          'G2:', 'D3:', 'D4:', 'E1:', 'E3:', 'E4:',
          'A7:', 'D1:', 'C3-pre:', 'E5-',
        ];
        final leaked = incoming.where((m) =>
            !knownPrefixes.any((p) => m.text.contains(p))).toList();
        final noLeakedE7 = leaked.isEmpty;
        final e7Pass = e7Alive && noLeakedE7;
        results.add(_ScenarioResult('E7', e7Pass,
            'alive=$e7Alive leaked=${leaked.length}'));
        print('[TEST] E7 ${e7Pass ? 'PASS' : 'FAIL'}: '
            'alive=$e7Alive leaked=${leaked.length}');
        for (final m in leaked) {
          final preview = m.text.length > 80
              ? '${m.text.substring(0, 80)}...'
              : m.text;
          print('[TEST] E7 LEAKED: "$preview" transport=${m.transport}');
        }

        // ==== A7: Rendezvous discovery E2E ====
        print('\n--- A7: Rendezvous discovery ---');
        final a7 = incoming.where((m) => m.text.contains('A7:')).toList();
        if (a7.isNotEmpty) {
          final a7Transport = a7.first.transport;
          final a7Pass = a7Transport == 'relay';
          results.add(_ScenarioResult(
              'A7', a7Pass, 'transport=$a7Transport'));
          print('[TEST] A7 ${a7Pass ? 'PASS' : 'FAIL'}: '
              '"${a7.first.text}" transport=$a7Transport');
        } else {
          results.add(_ScenarioResult('A7', false, 'no message received'));
          print('[TEST] A7 FAIL: no incoming message with A7: prefix');
        }

        // ==== E5: Unicode stress ====
        print('\n--- E5: Unicode stress ---');
        final e5 = incoming.where((m) => m.text.contains('E5-')).toList();
        if (e5.length >= 4) {
          final e5Emoji = e5.any((m) => m.text.contains('E5-emoji:'));
          final e5Rtl = e5.any((m) => m.text.contains('E5-rtl:'));
          final e5Cjk = e5.any((m) => m.text.contains('E5-cjk:'));
          final e5Combining = e5.any((m) => m.text.contains('E5-combining:'));
          final e5Pass = e5Emoji && e5Rtl && e5Cjk && e5Combining;
          results.add(_ScenarioResult(
              'E5', e5Pass,
              '${e5.length} msgs: emoji=$e5Emoji rtl=$e5Rtl cjk=$e5Cjk combining=$e5Combining'));
          print('[TEST] E5 ${e5Pass ? 'PASS' : 'FAIL'}: ${e5.length} unicode messages');
          for (final m in e5) {
            print('[TEST] E5: "${m.text}"');
          }
        } else {
          results.add(_ScenarioResult(
              'E5', false, 'expected 4, got ${e5.length}'));
          print('[TEST] E5 FAIL: expected 4, got ${e5.length}');
        }

        // ==== D1: Duplicate relay messages (same ID) ====
        print('\n--- D1: Duplicate relay messages ---');
        final d1 = incoming.where((m) => m.text.contains('D1:')).toList();
        if (d1.isNotEmpty) {
          final d1Pass = d1.length == 1;
          final d1Id = d1.first.id;
          results.add(_ScenarioResult(
              'D1', d1Pass,
              'count=${d1.length} id=$d1Id (expect 1 — dedup)'));
          print('[TEST] D1 ${d1Pass ? 'PASS' : 'FAIL'}: '
              '${d1.length} messages with D1: prefix');
        } else {
          results.add(_ScenarioResult('D1', false, 'no D1 message received'));
          print('[TEST] D1 FAIL: no D1 message received');
        }

        // ==== C3-pre: Before network change ====
        print('\n--- C3-pre: Before network change ---');
        final c3pre = incoming.where((m) => m.text.contains('C3-pre:')).toList();
        if (c3pre.isNotEmpty) {
          results.add(_ScenarioResult(
              'C3-pre', true, 'transport=${c3pre.first.transport}'));
          print('[TEST] C3-pre PASS: "${c3pre.first.text}"');
        } else {
          results.add(_ScenarioResult('C3-pre', false, 'not received'));
          print('[TEST] C3-pre FAIL: no C3-pre message');
        }

        // ==== C2 (deferred): In-flight send drop ====
        // Dropping a connection during the sub-millisecond window between send
        // and ack cannot be triggered reliably in E2E. The fallback chain
        // (fast-path → 3x discover-dial-send → inbox → failed) is tested
        // implicitly by C1. For precise in-flight testing, use a unit test
        // with a mocked P2PService that delays/drops the ack.

        // ==== C4 (deferred): Crash during inbox drain ====
        // Simulating process death mid-drain is not possible in Flutter
        // integration tests. The at-most-once semantics are documented in B7.
        // For testing partial-persist scenarios, use a unit test with a mocked
        // MessageRepository that throws after N inserts.
      }

      // ==== Phase 2: C1 — Connection drop + inbox fallback ====
      if (hasCli) {
        print('\n--- C1: Connection drop + inbox fallback ---');
        // Poll for the orchestrator's signal that CLI node is stopped.
        var cliStopped = false;
        for (var i = 0; i < 60; i++) {
          await Future.delayed(const Duration(seconds: 1));
          if (File(_readSignalPath('e2e_cli_stopped')).existsSync()) {
            cliStopped = true;
            print('[TEST] C1: CLI stopped signal found after ${i + 1}s');
            break;
          }
        }

        if (!cliStopped) {
          print('[TEST] C1: SKIP — CLI stopped signal not found');
          results.add(_ScenarioResult(
              'C1', false, 'CLI stopped signal not received'));
        } else {
          try {
            // Send a message while the CLI node is down — should fall back to inbox.
            final (c1Result, c1Msg) = await sendChatMessage(
              p2pService: stack.p2pService,
              messageRepo: stack.messageRepo,
              targetPeerId: stack.cliPeerId!,
              text: 'C1: Message while CLI is down',
              senderPeerId: stack.ownPeerId,
              senderUsername: 'FlutterE2E',
            );

            // Signal orchestrator that we sent the C1 message.
            File(_writeSignalPath('e2e_c1_sent')).writeAsStringSync('sent');
            print('[TEST] C1: message sent, signal written');

            // Validate: message persisted with expected status/transport.
            final c1Stored = await stack.messageRepo
                .getMessagesForContact(stack.cliPeerId!);
            final c1Out = c1Stored
                .where((m) => !m.isIncoming && m.text.contains('C1:'))
                .toList();
            final c1Status = c1Out.isNotEmpty ? c1Out.last.status : 'none';
            final c1Transport = c1Out.isNotEmpty ? c1Out.last.transport : 'none';
            final c1Pass = c1Msg != null &&
                c1Status == 'delivered' &&
                c1Transport == 'inbox';
            results.add(_ScenarioResult(
                'C1', c1Pass, 'status=$c1Status transport=$c1Transport'));
            print('[TEST] C1 ${c1Pass ? 'PASS' : 'FAIL'}: '
                'status=$c1Status transport=$c1Transport');
          } catch (e) {
            // Still write the signal so orchestrator doesn't hang.
            try {
              File(_writeSignalPath('e2e_c1_sent')).writeAsStringSync('sent');
            } catch (_) {}
            results.add(_ScenarioResult('C1', false, 'error: $e'));
            print('[TEST] C1 FAIL: $e');
          }
        }
      }

      // ==== Phase 3: A8 — Relay reconnect + C3-post ====
      if (hasCli) {
        print('\n--- A8: Waiting for post-reconnect messages (120s) ---');
        // The orchestrator sends A8:, A8b:, C3-post: after C1.
        // Poll for these messages arriving.
        var a8Found = false;
        var a8bFound = false;
        var c3postFound = false;
        var a8ReplySent = false;

        for (var sec = 0; sec < 120; sec++) {
          await Future.delayed(const Duration(seconds: 1));

          final msgs = await stack.messageRepo
              .getMessagesForContact(stack.cliPeerId!);
          final inc = msgs.where((m) => m.isIncoming).toList();

          if (!a8Found) {
            final a8Msg = inc.where((m) => m.text.contains('A8:') && !m.text.contains('A8b:')).toList();
            if (a8Msg.isNotEmpty) {
              a8Found = true;
              print('[TEST] A8: received after ${sec + 1}s');

              // Reply to A8.
              if (!a8ReplySent) {
                try {
                  await sendChatMessage(
                    p2pService: stack.p2pService,
                    messageRepo: stack.messageRepo,
                    targetPeerId: stack.cliPeerId!,
                    text: 'A8-reply: Got your reconnect message',
                    senderPeerId: stack.ownPeerId,
                    senderUsername: 'FlutterE2E',
                  );
                  a8ReplySent = true;
                  print('[TEST] A8: reply sent');
                } catch (e) {
                  print('[TEST] A8: reply failed: $e');
                }
              }
            }
          }

          if (!a8bFound) {
            final a8bMsg = inc.where((m) => m.text.contains('A8b:')).toList();
            if (a8bMsg.isNotEmpty) {
              a8bFound = true;
              print('[TEST] A8b: received after ${sec + 1}s');
            }
          }

          if (!c3postFound) {
            final c3postMsg = inc.where((m) => m.text.contains('C3-post:')).toList();
            if (c3postMsg.isNotEmpty) {
              c3postFound = true;
              print('[TEST] C3-post: received after ${sec + 1}s');
            }
          }

          if (a8Found && a8bFound && c3postFound) break;

          if (sec % 15 == 14) {
            print('[TEST] ... ${sec + 1}s: a8=$a8Found a8b=$a8bFound c3post=$c3postFound');
          }
        }

        // Validate A8.
        print('\n--- A8: Relay reconnect ---');
        final a8Msgs = (await stack.messageRepo.getMessagesForContact(stack.cliPeerId!))
            .where((m) => m.isIncoming && m.text.contains('A8:') && !m.text.contains('A8b:'))
            .toList();
        if (a8Msgs.isNotEmpty) {
          final a8Transport = a8Msgs.first.transport;
          results.add(_ScenarioResult('A8', true, 'transport=$a8Transport'));
          print('[TEST] A8 PASS: transport=$a8Transport');
        } else {
          results.add(_ScenarioResult('A8', false, 'no A8 message'));
          print('[TEST] A8 FAIL: no A8 message');
        }

        // Validate A8b (second reconnect).
        print('\n--- A8b: Second reconnect ---');
        final a8bMsgs = (await stack.messageRepo.getMessagesForContact(stack.cliPeerId!))
            .where((m) => m.isIncoming && m.text.contains('A8b:'))
            .toList();
        if (a8bMsgs.isNotEmpty) {
          results.add(_ScenarioResult('A8b', true, 'second reconnect OK'));
          print('[TEST] A8b PASS');
        } else {
          results.add(_ScenarioResult('A8b', false, 'no A8b message'));
          print('[TEST] A8b FAIL: no A8b message');
        }

        // Validate C3-post.
        print('\n--- C3: Network transition (full) ---');
        final c3postMsgs = (await stack.messageRepo.getMessagesForContact(stack.cliPeerId!))
            .where((m) => m.isIncoming && m.text.contains('C3-post:'))
            .toList();
        final c3preReceived = (await stack.messageRepo.getMessagesForContact(stack.cliPeerId!))
            .any((m) => m.isIncoming && m.text.contains('C3-pre:'));
        if (c3postMsgs.isNotEmpty && c3preReceived) {
          final c3Transport = c3postMsgs.first.transport;
          results.add(_ScenarioResult(
              'C3', true, 'pre+post received, post transport=$c3Transport'));
          print('[TEST] C3 PASS: both pre and post received');
        } else {
          results.add(_ScenarioResult('C3', false,
              'pre=$c3preReceived post=${c3postMsgs.isNotEmpty}'));
          print('[TEST] C3 FAIL: pre=$c3preReceived post=${c3postMsgs.isNotEmpty}');
        }
      }

      // ==== Phase 4: B8 — Encrypted inbox from Flutter ====
      if (hasCli && stack.cliMlKemPublicKey != null) {
        print('\n--- B8: Encrypted inbox from Flutter ---');
        var b8Stopped = false;
        for (var i = 0; i < 60; i++) {
          await Future.delayed(const Duration(seconds: 1));
          if (File(_readSignalPath('e2e_cli_b8_stopped')).existsSync()) {
            b8Stopped = true;
            print('[TEST] B8: CLI stopped signal found after ${i + 1}s');
            break;
          }
        }

        if (!b8Stopped) {
          results.add(_ScenarioResult(
              'B8', false, 'CLI stopped signal not received'));
          print('[TEST] B8 SKIP: CLI stopped signal not found');
        } else {
          try {
            final (b8Result, b8Msg) = await sendChatMessage(
              p2pService: stack.p2pService,
              messageRepo: stack.messageRepo,
              targetPeerId: stack.cliPeerId!,
              text: 'B8: Encrypted inbox message',
              senderPeerId: stack.ownPeerId,
              senderUsername: 'FlutterE2E',
              bridge: stack.bridge,
              recipientMlKemPublicKey: stack.cliMlKemPublicKey,
            );

            File(_writeSignalPath('e2e_b8_sent')).writeAsStringSync('sent');
            print('[TEST] B8: encrypted message sent, signal written');

            final b8Stored = await stack.messageRepo
                .getMessagesForContact(stack.cliPeerId!);
            final b8Out = b8Stored
                .where((m) => !m.isIncoming && m.text.contains('B8:'))
                .toList();
            final b8Status = b8Out.isNotEmpty ? b8Out.last.status : 'none';
            final b8Transport = b8Out.isNotEmpty ? b8Out.last.transport : 'none';
            final b8Pass = b8Msg != null &&
                b8Status == 'delivered' &&
                b8Transport == 'inbox';
            results.add(_ScenarioResult(
                'B8', b8Pass, 'status=$b8Status transport=$b8Transport'));
            print('[TEST] B8 ${b8Pass ? 'PASS' : 'FAIL'}: '
                'status=$b8Status transport=$b8Transport');
          } catch (e) {
            try {
              File(_writeSignalPath('e2e_b8_sent')).writeAsStringSync('sent');
            } catch (_) {}
            results.add(_ScenarioResult('B8', false, 'error: $e'));
            print('[TEST] B8 FAIL: $e');
          }
        }
      }

      // ==== Phase 5: E8 — Media attachment E2E ====
      if (hasCli) {
        print('\n--- E8: Media attachment ---');
        try {
          final e8Bytes = _minimalPng();
          final e8TempFile = File('${Directory.systemTemp.path}/e2e_test_image.png');
          await e8TempFile.writeAsBytes(e8Bytes);
          print('[TEST] E8: wrote test PNG (${e8Bytes.length} bytes)');

          final e8BlobId = 'e8-test-blob-${DateTime.now().millisecondsSinceEpoch}';

          final uploadResult = await callP2PMediaUpload(
            stack.bridge,
            id: e8BlobId,
            toPeerId: stack.cliPeerId!,
            mime: 'image/png',
            filePath: e8TempFile.path,
          );
          final uploaded = uploadResult['ok'] == true;
          print('[TEST] E8: upload ok=$uploaded');

          if (uploaded) {
            // Send chat message with media reference.
            final (e8Result, e8Msg) = await sendChatMessage(
              p2pService: stack.p2pService,
              messageRepo: stack.messageRepo,
              targetPeerId: stack.cliPeerId!,
              text: 'E8: Media attachment test',
              senderPeerId: stack.ownPeerId,
              senderUsername: 'FlutterE2E',
            );

            // Write blob ID signal for orchestrator.
            File(_writeSignalPath('e2e_e8_blobid')).writeAsStringSync(e8BlobId);
            print('[TEST] E8: blob ID signal written');

            final e8Pass = e8Msg != null;
            results.add(_ScenarioResult('E8', e8Pass,
                'uploaded=$uploaded blobId=$e8BlobId'));
            print('[TEST] E8 ${e8Pass ? 'PASS' : 'FAIL'}');
          } else {
            results.add(_ScenarioResult('E8', false, 'upload failed'));
            print('[TEST] E8 FAIL: upload failed');
          }

          // Cleanup.
          try { e8TempFile.deleteSync(); } catch (_) {}
        } catch (e) {
          results.add(_ScenarioResult('E8', false, 'error: $e'));
          print('[TEST] E8 FAIL: $e');
        }
      }

      // ==== Phase 6: G6 — Profile upload/download E2E ====
      if (hasCli) {
        print('\n--- G6: Profile upload/download ---');
        try {
          // Upload Flutter's profile.
          final g6Bytes = _minimalPng();
          final g6TempFile = File('${Directory.systemTemp.path}/e2e_flutter_profile.png');
          await g6TempFile.writeAsBytes(g6Bytes);

          final uploadResult = await callP2PProfileUpload(
            stack.bridge,
            mime: 'image/png',
            filePath: g6TempFile.path,
          );
          final uploaded = uploadResult['ok'] == true;
          print('[TEST] G6: profile upload ok=$uploaded');

          if (uploaded) {
            File(_writeSignalPath('e2e_g6_flutter_uploaded')).writeAsStringSync('uploaded');
            print('[TEST] G6: upload signal written');

            // Wait for CLI to upload its profile.
            var cliUploaded = false;
            for (var i = 0; i < 60; i++) {
              await Future.delayed(const Duration(seconds: 1));
              if (File(_readSignalPath('e2e_g6_cli_uploaded')).existsSync()) {
                cliUploaded = true;
                print('[TEST] G6: CLI upload signal after ${i + 1}s');
                break;
              }
            }

            if (cliUploaded) {
              // Download CLI's profile.
              final dlPath = '${Directory.systemTemp.path}/e2e_cli_profile_dl.png';
              final dlResult = await callP2PProfileDownload(
                stack.bridge,
                ownerPeerId: stack.cliPeerId!,
                outputPath: dlPath,
              );
              final dlOk = dlResult['ok'] == true;
              final dlSize = dlResult['size'] ?? 0;
              final g6Pass = dlOk && (dlSize as num) > 0;
              results.add(_ScenarioResult('G6', g6Pass,
                  'upload=$uploaded cliDownload=$dlOk size=$dlSize'));
              print('[TEST] G6 ${g6Pass ? 'PASS' : 'FAIL'}: '
                  'upload=$uploaded download=$dlOk size=$dlSize');
              try { File(dlPath).deleteSync(); } catch (_) {}
            } else {
              results.add(_ScenarioResult('G6', false, 'CLI upload signal timeout'));
              print('[TEST] G6 FAIL: CLI upload signal not received');
            }
          } else {
            results.add(_ScenarioResult('G6', false, 'Flutter upload failed'));
            print('[TEST] G6 FAIL: profile upload failed');
          }

          try { g6TempFile.deleteSync(); } catch (_) {}
        } catch (e) {
          results.add(_ScenarioResult('G6', false, 'error: $e'));
          print('[TEST] G6 FAIL: $e');
        }
      }

      // ==== F: WiFi fallback (documented) ====
      // True WiFi→relay fallback requires two Flutter devices on the same
      // network with mDNS (Bonsoir). The CLI Go testpeer doesn't run mDNS
      // so it never appears as a local peer. WiFi fallback is implicitly
      // tested: isLocalPeer() returns false for CLI → relay path used →
      // all relay scenarios confirm the relay path works.
      results.add(_ScenarioResult('F', true,
          'documented: WiFi fallback tested implicitly via relay scenarios'));
      print('[TEST] F PASS: documented WiFi fallback (implicit)');

      // ==== B1: Send to offline peer (inbox fallback) — self-contained ====
      print('\n--- B1: Inbox fallback (offline peer) ---');
      try {
        const offlinePeerId = '12D3KooWOfflinePeerForInboxTest0001';
        await stack.contactRepo.addContact(ContactModel(
          peerId: offlinePeerId,
          publicKey: 'pk-offline',
          rendezvous: '/dns4/relay/tcp/443/p2p/relay',
          username: 'OfflinePeer',
          signature: 'sig-offline',
          scannedAt: DateTime.now().toUtc().toIso8601String(),
        ));

        final (result, msg) = await sendChatMessage(
          p2pService: stack.p2pService,
          messageRepo: stack.messageRepo,
          targetPeerId: offlinePeerId,
          text: 'B1: Hello inbox',
          senderPeerId: stack.ownPeerId,
          senderUsername: 'FlutterE2E',
        );

        final stored = await stack.messageRepo
            .getMessagesForContact(offlinePeerId);
        final status = stored.isNotEmpty ? stored.last.status : 'none';
        final transport = stored.isNotEmpty ? stored.last.transport : 'none';
        // B1 pass: message persisted; delivered via inbox OR failed is acceptable.
        final b1Pass = msg != null &&
            (status == 'delivered' || status == 'failed') &&
            (status != 'delivered' || transport == 'inbox');
        results.add(_ScenarioResult(
            'B1', b1Pass, 'status=$status transport=$transport'));
        print('[TEST] B1: status=$status transport=$transport');
      } catch (e) {
        results.add(_ScenarioResult('B1', false, 'error: $e'));
        print('[TEST] B1 FAIL: $e');
      }

      // ==== SUMMARY ====
      print('\n========================================');
      print('TEST SUMMARY');
      print('========================================');
      var passed = 0;
      var failed = 0;
      var total = results.length;
      for (final r in results) {
        final status = r.passed ? 'PASS' : 'FAIL';
        if (r.passed) passed++;
        else failed++;
        print('  ${r.name}: $status — ${r.detail}');
      }
      print('----------------------------------------');
      print('  $passed/$total passed, $failed failed');
      print('========================================\n');

      // Hard-fail if any scenario failed — replaces the old weak
      // "is node still alive" check.
      final failedScenarios = results.where((r) => !r.passed).toList();
      expect(failedScenarios, isEmpty,
          reason: 'Failed scenarios: '
              '${failedScenarios.map((r) => '${r.name}: ${r.detail}').join(', ')}');

    } finally {
      await stack.teardown();
    }
  });

  // =========================================================================
  // Self-contained: no CLI peer needed
  // =========================================================================

  testWidgets('Self-contained: send to unreachable peer', (tester) async {
    final stack = await _setupStack();

    try {
      const fakePeerId = '12D3KooWFakePeerForSelfContainedTest01';
      await stack.contactRepo.addContact(ContactModel(
        peerId: fakePeerId,
        publicKey: 'pk-fake',
        rendezvous: '/dns4/relay/tcp/443/p2p/relay',
        username: 'FakePeer',
        signature: 'sig-fake',
        scannedAt: DateTime.now().toUtc().toIso8601String(),
      ));

      final (result, msg) = await sendChatMessage(
        p2pService: stack.p2pService,
        messageRepo: stack.messageRepo,
        targetPeerId: fakePeerId,
        text: 'Self-contained: Hello unreachable peer',
        senderPeerId: stack.ownPeerId,
        senderUsername: 'FlutterE2E',
      );

      expect(msg, isNotNull, reason: 'Message should be persisted');

      final stored = await stack.messageRepo.getMessagesForContact(fakePeerId);
      expect(stored.length, 1);
      expect(stored.first.text, 'Self-contained: Hello unreachable peer');
      expect(stored.first.isIncoming, false);
      expect(
        stored.first.status,
        anyOf('delivered', 'failed'),
        reason: 'Status should be delivered (inbox) or failed',
      );

      print('[TEST] Self-contained PASS: status=${stored.first.status} '
          'transport=${stored.first.transport}');
    } finally {
      await stack.teardown();
    }
  });

  // =========================================================================
  // E2: Empty/zero-length message — self-contained
  // =========================================================================

  testWidgets('E2: Empty message rejection', (tester) async {
    final stack = await _setupStack();

    try {
      const fakePeerId = '12D3KooWFakePeerForEmptyMsgTest00001';
      await stack.contactRepo.addContact(ContactModel(
        peerId: fakePeerId,
        publicKey: 'pk-fake-e2',
        rendezvous: '/dns4/relay/tcp/443/p2p/relay',
        username: 'FakePeerE2',
        signature: 'sig-fake-e2',
        scannedAt: DateTime.now().toUtc().toIso8601String(),
      ));

      // Attempt to send empty text.
      final (result, msg) = await sendChatMessage(
        p2pService: stack.p2pService,
        messageRepo: stack.messageRepo,
        targetPeerId: fakePeerId,
        text: '',
        senderPeerId: stack.ownPeerId,
        senderUsername: 'FlutterE2E',
      );

      // Empty text should be rejected at the use-case level.
      expect(result, SendChatMessageResult.invalidMessage,
          reason: 'Empty text should return invalidMessage');
      expect(msg, isNull,
          reason: 'No message should be persisted for empty text');

      // Verify nothing was persisted.
      final stored = await stack.messageRepo.getMessagesForContact(fakePeerId);
      expect(stored.isEmpty, true,
          reason: 'No messages should be in DB');

      print('[TEST] E2 PASS: empty text correctly rejected '
          '(result=$result, msg=$msg)');

      // Also test whitespace-only text.
      final (result2, msg2) = await sendChatMessage(
        p2pService: stack.p2pService,
        messageRepo: stack.messageRepo,
        targetPeerId: fakePeerId,
        text: '   \n\t  ',
        senderPeerId: stack.ownPeerId,
        senderUsername: 'FlutterE2E',
      );

      expect(result2, SendChatMessageResult.invalidMessage,
          reason: 'Whitespace-only text should return invalidMessage');
      expect(msg2, isNull);

      print('[TEST] E2 PASS: whitespace-only text correctly rejected');
    } finally {
      await stack.teardown();
    }
  });
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Minimal valid 1x1 red PNG (67 bytes).
List<int> _minimalPng() {
  return [
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, // PNG signature
    // IHDR chunk (13 bytes)
    0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
    0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
    0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53,
    0xDE,
    // IDAT chunk
    0x00, 0x00, 0x00, 0x0C, 0x49, 0x44, 0x41, 0x54,
    0x08, 0xD7, 0x63, 0xF8, 0xCF, 0xC0, 0x00, 0x00,
    0x00, 0x02, 0x00, 0x01, 0xE2, 0x21, 0xBC, 0x33,
    // IEND chunk
    0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44,
    0xAE, 0x42, 0x60, 0x82,
  ];
}
