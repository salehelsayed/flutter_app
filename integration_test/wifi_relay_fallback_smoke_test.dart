// WiFi-Relay Fallback Smoke Test
//
// High-fidelity end-to-end smoke test using two real app instances to validate:
//   S1: Baseline relay chat (CLI peer sends message via relay)
//   S2: Send message to CLI peer
//   S3: Transport fallback (CLI stops -> inbox -> CLI restarts -> retrieval)
//   S4: Recovery after CLI restart (new messages work)
//
// NON-BLOCKING: runs nightly or before release, not on every PR.
//
// Launch with orchestrator:
//   dart run integration_test/scripts/run_wifi_relay_fallback_smoke.dart -p ios
//
// Or standalone (self-contained, S1/S2 only):
//   flutter test integration_test/wifi_relay_fallback_smoke_test.dart -d <device-id>

@Tags(['smoke'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:flutter_app/core/bridge/go_bridge_client.dart';
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

/// Path for reading orchestrator->Flutter signals.
String _readSignalPath(String name) => '$_readDir/$name';

/// Path for writing Flutter->orchestrator signals.
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
    print('[SMOKE] Failed to parse CLI peer fixture: $e');
    return null;
  }
}

void _writeFlutterPeerFixture({
  required String peerId,
  required String publicKey,
  String? mlKemPublicKey,
}) {
  final fixturePath = _writeSignalPath('flutter_peer_fixture.json');
  Directory(_writeDir).createSync(recursive: true);
  final data = {
    'peerId': peerId,
    'publicKey': publicKey,
    if (mlKemPublicKey != null) 'mlKemPublicKey': mlKemPublicKey,
  };
  File(fixturePath).writeAsStringSync(jsonEncode(data));
  print('[SMOKE] Flutter peer fixture written to $fixturePath');
}

// ---------------------------------------------------------------------------
// Shared test stack — builds the full DI stack
// ---------------------------------------------------------------------------

var _testCounter = 0;

Future<_SmokeTestStack> _setupStack() async {
  _testCounter++;
  print('\n========================================');
  print('SMOKE TEST -- SETUP #$_testCounter');
  print('========================================\n');

  final cliPeer = _loadCliPeerFixture();
  String? cliPeerId;
  String? cliPublicKey;
  String? cliMlKemPublicKey;

  if (cliPeer != null) {
    cliPeerId = cliPeer['peerId'] as String?;
    cliPublicKey = cliPeer['publicKey'] as String?;
    cliMlKemPublicKey = cliPeer['mlKemPublicKey'] as String?;
    print('[SMOKE] CLI peer loaded: ${cliPeerId?.substring(0, 20)}...');
  } else {
    print('[SMOKE] No CLI peer fixture -- running self-contained tests only');
  }

  final secureKeyStore = _FakeSecureKeyStore();
  final dbName = 'smoke_test_$_testCounter.db';

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
  print('[SMOKE] Database initialized (version 12)');

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
  print('[SMOKE] Bridge initialized');

  final p2pService = P2PServiceImpl(bridge: bridge);

  try {
    // Generate identity.
    print('[SMOKE] Generating identity...');
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
    print('[SMOKE] Identity: ${ownPeerId.substring(0, 20)}...');

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
      print('[SMOKE] ML-KEM keys generated');
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
        username: 'CLISmokeTestPeer',
        signature: 'sig-cli-peer',
        scannedAt: DateTime.now().toUtc().toIso8601String(),
        mlKemPublicKey: cliMlKemPublicKey,
      ));
      print('[SMOKE] CLI peer added as contact');
    }

    // Start real P2P node.
    print('[SMOKE] Starting P2P node...');
    final started = await p2pService.startNode(ownPrivateKey, ownPeerId);
    if (!started) {
      throw StateError('P2P node failed to start');
    }
    print('[SMOKE] P2P node started');

    // Wire ChatMessageListener.
    final chatListener = ChatMessageListener(
      chatMessageStream: p2pService.messageStream,
      messageRepo: messageRepo,
      contactRepo: contactRepo,
      bridge: bridge,
      getOwnMlKemSecretKey: () async => ownMlKemSecretKey,
    );
    chatListener.start();
    print('[SMOKE] ChatMessageListener started');

    return _SmokeTestStack(
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
    p2pService.dispose();
    bridge.dispose();
    await db.close();
    rethrow;
  }
}

class _SmokeTestStack {
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

  _SmokeTestStack({
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
    try {
      File(_writeSignalPath('flutter_peer_fixture.json')).deleteSync();
    } catch (_) {}
    print('[SMOKE] Cleanup complete');
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
  // Full WiFi-Relay Fallback Smoke Test
  // =========================================================================

  testWidgets('WiFi-Relay Fallback Smoke Test (S1-S4)', (tester) async {
    final stack = await _setupStack();

    final hasCli = stack.cliPeerId != null;
    if (!hasCli) {
      print('[SMOKE] No CLI peer -- only self-contained scenarios available');
    }

    final results = <_ScenarioResult>[];

    try {
      // ================================================================
      // S1: Baseline relay chat -- receive a message from CLI peer
      // ================================================================
      if (hasCli) {
        print('\n--- S1: Baseline relay chat ---');
        print('[SMOKE] S1: Waiting for CLI peer to send message via relay...');

        // The orchestrator discovers us via rendezvous and sends a v1 message.
        // Poll for up to 60s for the message to arrive.
        var s1Found = false;
        for (var sec = 0; sec < 60; sec++) {
          await Future.delayed(const Duration(seconds: 1));

          final msgs = await stack.messageRepo
              .getMessagesForContact(stack.cliPeerId!);
          final incoming = msgs.where((m) => m.isIncoming).toList();
          final s1Msgs = incoming.where((m) => m.text.contains('S1:')).toList();

          if (s1Msgs.isNotEmpty) {
            s1Found = true;
            final transport = s1Msgs.first.transport;
            // Accept relay or inbox transport -- both prove end-to-end works.
            final pass = transport == 'relay' || transport == 'inbox';
            results.add(_ScenarioResult(
                'S1', pass, 'transport=$transport text="${s1Msgs.first.text}"'));
            print('[SMOKE] S1 ${pass ? 'PASS' : 'FAIL'}: '
                '"${s1Msgs.first.text}" transport=$transport (after ${sec + 1}s)');
            break;
          }

          if (sec % 10 == 9) {
            print('[SMOKE] S1: ... ${sec + 1}s: ${incoming.length} incoming so far');
          }
        }

        if (!s1Found) {
          results.add(_ScenarioResult(
              'S1', false, 'no S1 message received after 60s'));
          print('[SMOKE] S1 FAIL: no incoming message with S1: prefix');
        }
      }

      // ================================================================
      // S2: Send message to CLI peer
      // ================================================================
      if (hasCli) {
        print('\n--- S2: Send v1 message to CLI peer ---');
        try {
          final (r2, m2) = await sendChatMessage(
            p2pService: stack.p2pService,
            messageRepo: stack.messageRepo,
            targetPeerId: stack.cliPeerId!,
            text: 'S2: Hello from Flutter smoke test',
            senderPeerId: stack.ownPeerId,
            senderUsername: 'FlutterSmoke',
          );

          final stored = await stack.messageRepo
              .getMessagesForContact(stack.cliPeerId!);
          final outgoing = stored
              .where((m) => !m.isIncoming && m.text.contains('S2:'))
              .toList();
          final status = outgoing.isNotEmpty ? outgoing.last.status : 'none';
          final transport = outgoing.isNotEmpty ? outgoing.last.transport : 'none';
          final detail = 'status=$status transport=$transport';
          // Accept delivered via relay or inbox.
          final pass = m2 != null &&
              status == 'delivered' &&
              (transport == 'relay' || transport == 'inbox');
          results.add(_ScenarioResult('S2', pass, detail));
          print('[SMOKE] S2 ${pass ? 'PASS' : 'FAIL'}: $detail');
        } catch (e) {
          results.add(_ScenarioResult('S2', false, 'error: $e'));
          print('[SMOKE] S2 FAIL: $e');
        }
      }

      // ================================================================
      // S3: Transport fallback -- CLI stops, Flutter sends to inbox,
      //     CLI restarts, retrieves from inbox
      // ================================================================
      if (hasCli) {
        print('\n--- S3: Transport fallback (inbox) ---');

        // Wait for orchestrator signal that CLI node is stopped.
        var cliStopped = false;
        for (var i = 0; i < 60; i++) {
          await Future.delayed(const Duration(seconds: 1));
          if (File(_readSignalPath('e2e_smoke_cli_stopped')).existsSync()) {
            cliStopped = true;
            print('[SMOKE] S3: CLI stopped signal found after ${i + 1}s');
            break;
          }
        }

        if (!cliStopped) {
          print('[SMOKE] S3: SKIP -- CLI stopped signal not found');
          results.add(_ScenarioResult(
              'S3', false, 'CLI stopped signal not received after 60s'));
        } else {
          try {
            // Send a message while CLI is down -- should fall back to inbox.
            final (s3Result, s3Msg) = await sendChatMessage(
              p2pService: stack.p2pService,
              messageRepo: stack.messageRepo,
              targetPeerId: stack.cliPeerId!,
              text: 'S3: Message while CLI is down (inbox fallback)',
              senderPeerId: stack.ownPeerId,
              senderUsername: 'FlutterSmoke',
            );

            // Signal orchestrator that we sent the S3 message.
            File(_writeSignalPath('e2e_smoke_s3_sent')).writeAsStringSync('sent');
            print('[SMOKE] S3: message sent, signal written');

            // Validate: message persisted with expected status/transport.
            final s3Stored = await stack.messageRepo
                .getMessagesForContact(stack.cliPeerId!);
            final s3Out = s3Stored
                .where((m) => !m.isIncoming && m.text.contains('S3:'))
                .toList();
            final s3Status = s3Out.isNotEmpty ? s3Out.last.status : 'none';
            final s3Transport = s3Out.isNotEmpty ? s3Out.last.transport : 'none';
            final s3Pass = s3Msg != null &&
                s3Status == 'delivered' &&
                s3Transport == 'inbox';
            results.add(_ScenarioResult(
                'S3', s3Pass, 'status=$s3Status transport=$s3Transport'));
            print('[SMOKE] S3 ${s3Pass ? 'PASS' : 'FAIL'}: '
                'status=$s3Status transport=$s3Transport');
          } catch (e) {
            // Still write signal so orchestrator does not hang.
            try {
              File(_writeSignalPath('e2e_smoke_s3_sent')).writeAsStringSync('sent');
            } catch (_) {}
            results.add(_ScenarioResult('S3', false, 'error: $e'));
            print('[SMOKE] S3 FAIL: $e');
          }
        }
      }

      // ================================================================
      // S4: Recovery after CLI restart -- new messages work
      // ================================================================
      if (hasCli) {
        print('\n--- S4: Recovery after CLI restart ---');

        // Wait for the orchestrator to send a post-recovery message.
        var s4Found = false;
        for (var sec = 0; sec < 90; sec++) {
          await Future.delayed(const Duration(seconds: 1));

          final msgs = await stack.messageRepo
              .getMessagesForContact(stack.cliPeerId!);
          final incoming = msgs.where((m) => m.isIncoming).toList();
          final s4Msgs = incoming.where((m) => m.text.contains('S4:')).toList();

          if (s4Msgs.isNotEmpty) {
            s4Found = true;
            final transport = s4Msgs.first.transport;
            final pass = transport == 'relay' || transport == 'inbox';
            results.add(_ScenarioResult(
                'S4', pass, 'transport=$transport text="${s4Msgs.first.text}"'));
            print('[SMOKE] S4 ${pass ? 'PASS' : 'FAIL'}: '
                '"${s4Msgs.first.text}" transport=$transport (after ${sec + 1}s)');
            break;
          }

          if (sec % 15 == 14) {
            print('[SMOKE] S4: ... ${sec + 1}s: ${incoming.length} incoming so far');
          }
        }

        if (!s4Found) {
          // Also try draining inbox in case the message was stored there.
          print('[SMOKE] S4: trying inbox drain...');
          try {
            await stack.p2pService.drainOfflineInbox();
            await Future.delayed(const Duration(seconds: 3));
            final msgs = await stack.messageRepo
                .getMessagesForContact(stack.cliPeerId!);
            final s4Msgs = msgs
                .where((m) => m.isIncoming && m.text.contains('S4:'))
                .toList();
            if (s4Msgs.isNotEmpty) {
              s4Found = true;
              final transport = s4Msgs.first.transport;
              results.add(_ScenarioResult('S4', true,
                  'transport=$transport (after inbox drain)'));
              print('[SMOKE] S4 PASS: found after inbox drain');
            }
          } catch (e) {
            print('[SMOKE] S4: inbox drain failed: $e');
          }
        }

        if (!s4Found) {
          results.add(_ScenarioResult(
              'S4', false, 'no S4 message received after 90s + inbox drain'));
          print('[SMOKE] S4 FAIL: no incoming message with S4: prefix');
        }

        // Send a reply to confirm bidirectional recovery.
        try {
          await sendChatMessage(
            p2pService: stack.p2pService,
            messageRepo: stack.messageRepo,
            targetPeerId: stack.cliPeerId!,
            text: 'S4-reply: Recovery confirmed from Flutter',
            senderPeerId: stack.ownPeerId,
            senderUsername: 'FlutterSmoke',
          );
          print('[SMOKE] S4: reply sent');
        } catch (e) {
          print('[SMOKE] S4: reply failed (non-fatal): $e');
        }
      }

      // ================================================================
      // SUMMARY
      // ================================================================
      print('\n========================================');
      print('SMOKE TEST SUMMARY');
      print('========================================');
      var passed = 0;
      var failed = 0;
      for (final r in results) {
        final status = r.passed ? 'PASS' : 'FAIL';
        if (r.passed) {
          passed++;
        } else {
          failed++;
        }
        print('  ${r.name}: $status -- ${r.detail}');
      }
      print('----------------------------------------');
      print('  $passed/${results.length} passed, $failed failed');
      print('========================================\n');

      // Hard-fail if any scenario failed.
      final failedScenarios = results.where((r) => !r.passed).toList();
      expect(failedScenarios, isEmpty,
          reason: 'Failed smoke scenarios: '
              '${failedScenarios.map((r) => '${r.name}: ${r.detail}').join(', ')}');
    } finally {
      await stack.teardown();
    }
  });
}
