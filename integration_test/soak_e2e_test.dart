// Soak E2E Integration Test — Flutter Side
//
// Signal-driven soak test that coordinates with run_soak_e2e.dart orchestrator.
// The orchestrator sends commands via signal files; this test responds.
//
// Launch with orchestrator:
//   dart run integration_test/scripts/run_soak_e2e.dart -d <simulator-id>
//
// Signal protocol:
//   soak_send_next     → send a message to CLI peer
//   soak_drain_inbox   → drain offline inbox
//   soak_health_check  → call handleAppResumed
//   soak_done          → exit the loop
//   soak_stats         → written by this test with current counts

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

  @override
  Future<void> deleteAll() async => _store.clear();
}

// ---------------------------------------------------------------------------
// Signal helpers
// ---------------------------------------------------------------------------

/// Base directory for signal files — matches the orchestrator's paths.
String _signalDir() {
  // iOS simulator: shared filesystem — use /tmp/e2e_soak_<pid>
  // Android: would use app cache dir, but for now iOS-only
  final envDir = Platform.environment['E2E_SIGNAL_DIR'];
  if (envDir != null) return envDir;
  return '/tmp/e2e_soak_signals';
}

bool _signalExists(String name) {
  return File('${_signalDir()}/$name').existsSync();
}

String? _readSignal(String name) {
  final f = File('${_signalDir()}/$name');
  if (!f.existsSync()) return null;
  return f.readAsStringSync();
}

void _writeSignal(String name, String content) {
  File('${_signalDir()}/$name').writeAsStringSync(content);
}

void _deleteSignal(String name) {
  final f = File('${_signalDir()}/$name');
  if (f.existsSync()) f.deleteSync();
}

// ---------------------------------------------------------------------------
// Main test
// ---------------------------------------------------------------------------

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('soak E2E — signal-driven loop', (tester) async {
    // 1. Read CLI peer fixture
    final fixtureFile = File('${_signalDir()}/cli_peer_fixture.json');
    if (!fixtureFile.existsSync()) {
      fail('CLI peer fixture not found at ${fixtureFile.path}. '
          'Run with the orchestrator: '
          'dart run integration_test/scripts/run_soak_e2e.dart');
    }
    final fixture =
        jsonDecode(fixtureFile.readAsStringSync()) as Map<String, dynamic>;
    final cliPeerId = fixture['peerId'] as String;
    final cliPublicKey = fixture['publicKey'] as String;
    final cliMlKemPK = fixture['mlKemPublicKey'] as String?;

    // 2. Initialize local stack
    final secureKeyStore = _FakeSecureKeyStore();
    final bridge = GoBridgeClient();
    await bridge.initialize();

    final identityResult = await bridge.call('identity.generate', {});
    final myPeerId = identityResult['peerId'] as String;
    final myPrivateKey = identityResult['privateKey'] as String;

    // Generate ML-KEM keys
    final mlKemResult = await bridge.call('mlkem.keygen', {});
    final myMlKemPK = mlKemResult['publicKey'] as String;
    final myMlKemSK = mlKemResult['secretKey'] as String;

    // Open encrypted DB
    final dbKey = 'test-soak-key-${DateTime.now().millisecondsSinceEpoch}';
    await secureKeyStore.write('db_encryption_key', dbKey);

    final db = await openEncryptedDatabase(
      secureKeyStore: secureKeyStore,
      migrations: [
        createIdentityTable,
        createMessagesTable,
        addMlKemKeyColumns,
        addSecretNullChecks,
        addReadAtColumn,
        addArchiveColumns,
        addBlockColumns,
        addQuotedMessageIdColumn,
        createMediaAttachmentsTable,
        addAvatarVersionColumn,
        addTransportColumn,
      ],
    );

    final contactRepo = ContactRepositoryImpl(
      getContact: (peerId) => getContact(db, peerId),
      addContact: (contact) => insertContact(db, contact),
      deleteContact: (peerId) => deleteContact(db, peerId),
      getAllContacts: () => getAllContacts(db),
      contactExists: (peerId) => contactExists(db, peerId),
      getContactCount: () => getContactCount(db),
      archiveContact: (peerId) => archiveContact(db, peerId),
      unarchiveContact: (peerId) => unarchiveContact(db, peerId),
      getActiveContacts: () => getActiveContacts(db),
      getArchivedContacts: () => getArchivedContacts(db),
      blockContact: (peerId) => blockContact(db, peerId),
      unblockContact: (peerId) => unblockContact(db, peerId),
    );
    final messageRepo = MessageRepositoryImpl(
      saveMessage: (msg) => saveMessage(db, msg),
      getMessagesForContact: (cid) => getMessagesForContact(db, cid),
      getLatestMessageForContact: (cid) => getLatestMessageForContact(db, cid),
      updateMessageStatus: (id, status) => updateMessageStatus(db, id, status),
      messageExists: (id) => messageExists(db, id),
      getMessageCountForContact: (cid) => getMessageCountForContact(db, cid),
      markConversationAsRead: (cid) => markConversationAsRead(db, cid),
      getUnreadCountForContact: (cid) => getUnreadCountForContact(db, cid),
      getTotalUnreadCount: () => getTotalUnreadCount(db),
      getTotalUnreadCountExcludingArchived: () =>
          getTotalUnreadCountExcludingArchived(db),
      deleteMessagesForContact: (cid) => deleteMessagesForContact(db, cid),
      getFailedOutgoingMessages: () => getFailedOutgoingMessages(db),
      getMessagesPage: (cid, {int limit = 50, String? beforeTimestamp}) =>
          getMessagesPage(db, cid,
              limit: limit, beforeTimestamp: beforeTimestamp),
    );

    // Start P2P node
    final p2pBridge = P2PBridgeClient(bridge: bridge);
    final p2pService = P2PServiceImpl(bridge: p2pBridge);
    await p2pService.startNode(myPrivateKey, myPeerId);

    // Add CLI peer as contact
    await contactRepo.addContact(ContactModel(
      peerId: cliPeerId,
      publicKey: cliPublicKey,
      rendezvous: '/dns4/relay/tcp/443/p2p/relay',
      username: 'CLI-Soak-Peer',
      signature: 'sig-cli',
      scannedAt: DateTime.now().toUtc().toIso8601String(),
      mlKemPublicKey: cliMlKemPK,
    ));

    // Start listener
    final listener = ChatMessageListener(
      chatMessageStream: p2pService.messageStream,
      messageRepo: messageRepo,
      contactRepo: contactRepo,
      bridge: bridge,
      getOwnMlKemSecretKey: () async => myMlKemSK,
    );
    listener.start();

    // Write our fixture for the orchestrator
    _writeSignal('flutter_peer_fixture.json', jsonEncode({
      'peerId': myPeerId,
      'publicKey': identityResult['publicKey'],
      'mlKemPublicKey': myMlKemPK,
    }));

    // 3. Signal-driven loop
    int sentCount = 0;
    int receivedCount = 0;
    int drainCount = 0;
    int healthCheckCount = 0;
    int loopCount = 0;

    while (!_signalExists('soak_done')) {
      loopCount++;

      // Check for send signal
      if (_signalExists('soak_send_next')) {
        _deleteSignal('soak_send_next');
        sentCount++;
        await sendChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: cliPeerId,
          text: 'soak-flutter-$sentCount',
          senderPeerId: myPeerId,
          senderUsername: 'FlutterSoak',
          bridge: bridge,
          recipientMlKemPublicKey: cliMlKemPK,
        );
      }

      // Check for drain signal
      if (_signalExists('soak_drain_inbox')) {
        _deleteSignal('soak_drain_inbox');
        drainCount++;
        await p2pService.drainOfflineInbox();
      }

      // Check for health check signal
      if (_signalExists('soak_health_check')) {
        _deleteSignal('soak_health_check');
        healthCheckCount++;
        await p2pService.performImmediateHealthCheck();
      }

      // Write stats periodically (every 10 loops)
      if (loopCount % 10 == 0) {
        final msgCount = await messageRepo.getMessageCountForContact(cliPeerId);
        _writeSignal('soak_stats', jsonEncode({
          'sentCount': sentCount,
          'messageCount': msgCount,
          'drainCount': drainCount,
          'healthCheckCount': healthCheckCount,
          'loopCount': loopCount,
        }));
      }

      await Future.delayed(const Duration(milliseconds: 500));
    }

    // 4. Final stats
    final finalMsgCount =
        await messageRepo.getMessageCountForContact(cliPeerId);
    _writeSignal('soak_final_stats', jsonEncode({
      'sentCount': sentCount,
      'messageCount': finalMsgCount,
      'drainCount': drainCount,
      'healthCheckCount': healthCheckCount,
    }));

    // Cleanup
    listener.dispose();
    p2pService.dispose();
    await db.close();
  }, timeout: const Timeout(Duration(minutes: 60)));
}
