/// Routing Smoke E2E — Bob Harness (Receiver)
///
/// Runs on simulator 2 (iPhone 17). Bob is the primary receiver in all 8
/// scenarios and also sends in S5 (bidirectional) and S8 (lifecycle).
/// Coordinates with Alice harness via shared signal files.
///
/// Launch via orchestrator:
///   dart run integration_test/scripts/run_routing_smoke_e2e.dart -d <alice>,<bob>

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite_sqlcipher/sqflite.dart' as sqlcipher;

import 'package:flutter_app/core/bridge/go_bridge_client.dart';
import 'package:flutter_app/core/database/encrypted_db_opener.dart';
import 'package:flutter_app/core/database/helpers/contacts_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/messages_db_helpers.dart';
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
import 'package:flutter_app/core/database/migrations/026_group_quoted_message_id.dart';
import 'package:flutter_app/core/database/migrations/043_messages_edited_at.dart';
import 'package:flutter_app/core/database/migrations/044_messages_deleted_state.dart';
import 'package:flutter_app/core/secure_storage/secure_key_store.dart';
import 'package:flutter_app/core/services/p2p_service_impl.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository_impl.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';
import 'package:flutter_app/core/lifecycle/handle_app_paused.dart';
import 'package:flutter_app/core/lifecycle/handle_app_resumed.dart';
import 'package:flutter_app/features/conversation/application/send_chat_message_use_case.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository_impl.dart';
import 'package:flutter_app/features/p2p/presentation/widgets/connection_status_indicator.dart';

import '../test/shared/fakes/in_memory_inbox_staging_repository.dart';

// ---------------------------------------------------------------------------
// Config
// ---------------------------------------------------------------------------

const _sharedDir = String.fromEnvironment('E2E_SHARED_DIR', defaultValue: '/tmp');
const _runId = String.fromEnvironment('SMOKE_RUN_ID', defaultValue: 'adhoc');
const _dbName = String.fromEnvironment('E2E_DB_NAME', defaultValue: 'routing_smoke_bob.db');

String _sig(String name) => '$_sharedDir/smoke_${_runId}_$name';

// ---------------------------------------------------------------------------
// Signal helpers
// ---------------------------------------------------------------------------

void _writeSignal(String name, String content) {
  File(_sig(name)).writeAsStringSync(content);
}

void _writeTimingSignal(String name, Map<String, dynamic> timing) {
  _writeSignal(name, jsonEncode(timing));
}

Future<void> _waitForSignal(
  String name, {
  Duration timeout = const Duration(seconds: 120),
}) async {
  final path = _sig(name);
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (File(path).existsSync()) return;
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
  throw TimeoutException('Bob: timed out waiting for signal: $name');
}

Future<Map<String, dynamic>> _waitForJsonSignal(
  String name, {
  Duration timeout = const Duration(seconds: 120),
}) async {
  final path = _sig(name);
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    final file = File(path);
    if (file.existsSync()) {
      return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    }
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
  throw TimeoutException('Bob: timed out waiting for json signal: $name');
}

// ---------------------------------------------------------------------------
// Secure key store
// ---------------------------------------------------------------------------

class _FakeSecureKeyStore implements SecureKeyStore {
  final Map<String, String> _store = {};
  @override Future<String?> read(String key) async => _store[key];
  @override Future<void> write(String key, String value) async => _store[key] = value;
  @override Future<void> delete(String key) async => _store.remove(key);
  @override Future<bool> containsKey(String key) async => _store.containsKey(key);
}

// ---------------------------------------------------------------------------
// DB setup (identical to Alice)
// ---------------------------------------------------------------------------

Future<void> _deleteTestDatabase(String dbName) async {
  try {
    final dbPath = await sqlcipher.getDatabasesPath();
    final fullPath = '$dbPath/$dbName';
    for (final p in [fullPath, '$fullPath-wal', '$fullPath-shm']) {
      final f = File(p);
      if (f.existsSync()) f.deleteSync();
    }
    await sqlcipher.deleteDatabase(fullPath);
  } catch (_) {}
}

Future<sqlcipher.Database> _openDb(SecureKeyStore keyStore) async {
  await _deleteTestDatabase(_dbName);
  return openEncryptedDatabase(
    secureKeyStore: keyStore,
    dbName: _dbName,
    version: 44,
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
      await runMessagesEditedAtMigration(db);
      await runMessagesDeletedStateMigration(db);
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
      if (oldVersion < 26) await runGroupQuotedMessageIdMigration(db);
      if (oldVersion < 43) await runMessagesEditedAtMigration(db);
      if (oldVersion < 44) await runMessagesDeletedStateMigration(db);
    },
  );
}

// ---------------------------------------------------------------------------
// Flow event capture (Bob uses this when sending in S5/S8)
// ---------------------------------------------------------------------------

Future<List<Map<String, dynamic>>> _captureFlowEvents(
  Future<void> Function() action,
) async {
  final printed = <String>[];
  final prev = flowEventLoggingEnabled;
  final origPrint = debugPrint;
  flowEventLoggingEnabled = true;
  debugPrint = (String? message, {int? wrapWidth}) {
    if (message != null) {
      printed.add(message);
      origPrint(message, wrapWidth: wrapWidth);
    }
  };
  try {
    await action();
  } finally {
    debugPrint = origPrint;
    flowEventLoggingEnabled = prev;
  }
  return printed
      .where((l) => l.startsWith('[FLOW] '))
      .map((l) => jsonDecode(l.substring('[FLOW] '.length)) as Map<String, dynamic>)
      .toList();
}

// ---------------------------------------------------------------------------
// Wait for Online
// ---------------------------------------------------------------------------

Future<bool> _waitForOnline(
  P2PServiceImpl service, {
  Duration timeout = const Duration(seconds: 60),
}) async {
  final sw = Stopwatch()..start();
  while (sw.elapsed < timeout) {
    if (healthFromState(service.currentState) == ConnectionHealth.online) {
      print('[BOB] Online after ${sw.elapsedMilliseconds}ms');
      return true;
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  print('[BOB] TIMEOUT waiting for Online');
  return false;
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  if (Platform.isLinux || Platform.isMacOS || Platform.isWindows) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  testWidgets('Bob — Routing Smoke S1–S8', (tester) async {
    print('\n${'═' * 60}');
    print('  BOB HARNESS — ROUTING SMOKE E2E');
    print('${'═' * 60}\n');

    // ── Stack setup (identical to Alice) ──
    final keyStore = _FakeSecureKeyStore();
    final db = await _openDb(keyStore);
    final bridge = GoBridgeClient();
    await bridge.initialize();

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
      dbSetIntrosSentAt: (peerId, ts) => dbSetIntrosSentAt(db, peerId, ts),
    );
    final messageRepo = MessageRepositoryImpl(
      dbInsertMessage: (row) => dbInsertMessage(db, row),
      dbLoadMessagesForContact: (p) => dbLoadMessagesForContact(db, p),
      dbLoadLatestMessageForContact: (p) => dbLoadLatestMessageForContact(db, p),
      dbUpdateMessageStatus: (id, s) => dbUpdateMessageStatus(db, id, s),
      dbLoadMessage: (id) => dbLoadMessage(db, id),
      dbCountMessagesForContact: (p) => dbCountMessagesForContact(db, p),
      dbMarkConversationAsRead: (p) => dbMarkConversationAsRead(db, p),
      dbCountUnreadForContact: (p) => dbCountUnreadForContact(db, p),
      dbCountTotalUnread: () => dbCountTotalUnread(db),
      dbCountTotalUnreadExcludingArchived: () => dbCountTotalUnreadExcludingArchived(db),
      dbDeleteMessagesForContact: (p) => dbDeleteMessagesForContact(db, p),
      dbDeleteMessage: (id) => dbDeleteMessage(db, id),
      dbLoadMessagesPage: (p, {limit = 50, beforeTimestamp}) =>
          dbLoadMessagesPage(db, p, limit: limit, beforeTimestamp: beforeTimestamp),
      dbLoadFailedOutgoingMessages: () => dbLoadFailedOutgoingMessages(db),
      dbLoadUnackedOutgoingMessages: ({required olderThan, limit = 50}) =>
          dbLoadUnackedOutgoingMessages(db, olderThan: olderThan, limit: limit),
      dbLoadConversationThreadSummaries: (ids) =>
          dbLoadConversationThreadSummaries(db, ids),
      dbRecoverStuckSendingMessages: ({required DateTime olderThan, int limit = 50}) =>
          dbRecoverStuckSendingMessages(db, olderThan: olderThan, limit: limit),
      dbUpdateWireEnvelope: (id, we) => dbUpdateWireEnvelope(db, id, we),
      dbLoadStuckSendingOutgoingMessages: ({required DateTime olderThan, int limit = 50}) =>
          dbLoadStuckSendingOutgoingMessages(db, olderThan: olderThan, limit: limit),
      dbLoadSendingOutgoingMessages: () => dbLoadSendingOutgoingMessages(db),
      dbConditionalTransitionStatus: (id, {required fromStatus, required toStatus}) =>
          dbConditionalTransitionStatus(db, id, fromStatus: fromStatus, toStatus: toStatus),
    );

    // Generate identity
    final genResp = await bridge.send(jsonEncode({'cmd': 'identity.generate', 'payload': {}}));
    final genResult = jsonDecode(genResp) as Map<String, dynamic>;
    if (genResult['ok'] != true) throw StateError('identity.generate failed');
    final identity = genResult['identity'] as Map<String, dynamic>;
    final ownPeerId = identity['peerId'] as String;
    final ownPrivateKey = identity['privateKey'] as String;
    final ownPublicKey = identity['publicKey'] as String;

    final mlkemResp = await bridge.send(jsonEncode({'cmd': 'mlkem.keygen', 'payload': {}}));
    final mlkemResult = jsonDecode(mlkemResp) as Map<String, dynamic>;
    final ownMlKemPk = mlkemResult['ok'] == true ? mlkemResult['publicKey'] as String? : null;
    final ownMlKemSk = mlkemResult['ok'] == true ? mlkemResult['secretKey'] as String? : null;

    print('[BOB] peerId=${ownPeerId.substring(0, 20)}...');

    // Start P2P node
    final p2pService = P2PServiceImpl(
      bridge: bridge,
      inboxStagingRepository: InMemoryInboxStagingRepository(),
    );
    var started = await p2pService.startNode(ownPrivateKey, ownPeerId);
    if (!started) throw StateError('P2P node failed to start');
    await _waitForOnline(p2pService);

    // Wire ChatMessageListener
    var chatListener = ChatMessageListener(
      chatMessageStream: p2pService.messageStream,
      messageRepo: messageRepo,
      contactRepo: contactRepo,
      bridge: bridge,
      getOwnMlKemSecretKey: () async => ownMlKemSk,
    );
    chatListener.start();

    // ── Identity exchange ──
    _writeTimingSignal('bob_identity.json', {
      'peerId': ownPeerId,
      'publicKey': ownPublicKey,
      'mlKemPublicKey': ownMlKemPk,
    });
    print('[BOB] Identity fixture written, reading Alice...');

    // Alice's identity should already exist (she launched first)
    final aliceFixture = await _waitForJsonSignal('alice_identity.json');
    final alicePeerId = aliceFixture['peerId'] as String;
    final aliceMlKemPk = aliceFixture['mlKemPublicKey'] as String?;

    await contactRepo.addContact(ContactModel(
      peerId: alicePeerId,
      publicKey: aliceFixture['publicKey'] as String,
      rendezvous: '/dns4/relay/tcp/443/p2p/relay',
      username: 'Alice',
      signature: 'sig-alice',
      scannedAt: DateTime.now().toUtc().toIso8601String(),
      mlKemPublicKey: aliceMlKemPk,
    ));
    print('[BOB] Alice added as contact');

    // Signal ready
    _writeSignal('bob_ready', 'ok');
    print('[BOB] Ready');

    // ── Helper: wait for incoming message in Bob's DB ──
    Future<Map<String, dynamic>?> waitForMessage(
      String substring, {
      Duration timeout = const Duration(seconds: 30),
    }) async {
      final sw = Stopwatch()..start();
      final deadline = DateTime.now().add(timeout);
      while (DateTime.now().isBefore(deadline)) {
        final msgs = await messageRepo.getMessagesForContact(alicePeerId);
        for (final m in msgs) {
          if (m.isIncoming && m.text.contains(substring)) {
            sw.stop();
            return {
              'e2eMs': sw.elapsedMilliseconds,
              'text': m.text,
              'status': m.status,
              'transport': m.transport,
            };
          }
        }
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
      return null;
    }

    // ── Helper: send from Bob (for bidirectional) ──
    Future<Map<String, dynamic>?> sendFromBob(String text) async {
      final events = await _captureFlowEvents(() async {
        await sendChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: alicePeerId,
          text: text,
          senderPeerId: ownPeerId,
          senderUsername: 'Bob',
          bridge: bridge,
          recipientMlKemPublicKey: aliceMlKemPk,
        );
      });
      final timings = events.where((e) => e['event'] == 'CHAT_MSG_SEND_TIMING').toList();
      if (timings.isEmpty) return null;
      final d = timings.first['details'] as Map<String, dynamic>;
      return {'sendMs': d['elapsedMs'], 'sendPath': d['sendPath'], 'outcome': d['outcome']};
    }

    // ════════════════════════════════════════════════════════════════
    //  S1: Cold send — Bob receives
    // ════════════════════════════════════════════════════════════════
    print('\n--- S1: Waiting for cold send ---');
    final s1 = await waitForMessage('S1:', timeout: const Duration(seconds: 60));
    print('[BOB] S1: ${s1 != null ? 'received (e2e=${s1['e2eMs']}ms)' : 'TIMEOUT'}');
    _writeTimingSignal('s1_bob_received', s1 ?? {'e2eMs': -1});

    // ════════════════════════════════════════════════════════════════
    //  S2: Warm send x5 — Bob receives all 5
    // ════════════════════════════════════════════════════════════════
    print('\n--- S2: Waiting for 5 warm messages ---');
    final s2Timings = <Map<String, dynamic>>[];
    for (var i = 1; i <= 5; i++) {
      final m = await waitForMessage('S2: warm msg $i');
      if (m != null) s2Timings.add(m);
    }
    print('[BOB] S2: received ${s2Timings.length}/5');
    _writeTimingSignal('s2_bob_received', {'timings': s2Timings, 'count': s2Timings.length});

    // ════════════════════════════════════════════════════════════════
    //  S3: Bob offline → restart → inbox drain → delivery
    // ════════════════════════════════════════════════════════════════
    print('\n--- S3: Going offline ---');
    await _waitForSignal('s3_bob_stop');
    chatListener.dispose();
    await p2pService.stopNode();
    _writeSignal('s3_bob_stopped', 'ok');
    print('[BOB] S3: Node stopped');

    // Wait for restart signal
    await _waitForSignal('s3_bob_restart');
    print('[BOB] S3: Restarting node...');
    started = await p2pService.startNode(ownPrivateKey, ownPeerId);
    if (!started) throw StateError('S3: restart failed');
    await _waitForOnline(p2pService);

    // Re-wire listener and drain inbox
    chatListener = ChatMessageListener(
      chatMessageStream: p2pService.messageStream,
      messageRepo: messageRepo,
      contactRepo: contactRepo,
      bridge: bridge,
      getOwnMlKemSecretKey: () async => ownMlKemSk,
    );
    chatListener.start();
    // Give relay time to establish before draining inbox
    await Future<void>.delayed(const Duration(seconds: 3));
    final s3Events = await _captureFlowEvents(() async {
      await p2pService.warmBackground();
    });

    // Capture INBOX_DELIVERY_TIMING events from the drain
    final s3DeliveryTimings = s3Events
        .where((e) => e['event'] == 'INBOX_DELIVERY_TIMING')
        .toList();
    for (final e in s3DeliveryTimings) {
      final d = e['details'] as Map<String, dynamic>;
      if (d.containsKey('deliveryMs')) {
        print('[SMOKE] inbox_delivery_ms=${d['deliveryMs']} messageId=${d['messageId']}');
      }
    }

    final s3 = await waitForMessage('S3:', timeout: const Duration(seconds: 90));
    print('[BOB] S3: ${s3 != null ? 'received via inbox (e2e=${s3['e2eMs']}ms)' : 'TIMEOUT'}');
    _writeTimingSignal('s3_bob_received', s3 ?? {'e2eMs': -1});

    // ════════════════════════════════════════════════════════════════
    //  S4: Reconnect — Bob receives
    // ════════════════════════════════════════════════════════════════
    print('\n--- S4: Waiting for reconnect message ---');
    final s4 = await waitForMessage('S4:', timeout: const Duration(seconds: 60));
    print('[BOB] S4: ${s4 != null ? 'received (e2e=${s4['e2eMs']}ms)' : 'TIMEOUT'}');
    _writeTimingSignal('s4_bob_received', s4 ?? {'e2eMs': -1});

    // ════════════════════════════════════════════════════════════════
    //  S5: Bidirectional — Bob sends + receives
    // ════════════════════════════════════════════════════════════════
    print('\n--- S5: Bidirectional ---');
    // Wait for Alice msg1
    await _waitForSignal('s5_alice_msg1');
    final s5m1 = await waitForMessage('S5: alice msg 1');
    print('[BOB] S5: received alice msg 1: ${s5m1 != null}');

    // Bob sends msg2
    final s5b2 = await sendFromBob('S5: bob msg 2');
    _writeTimingSignal('s5_bob_msg2', s5b2 ?? {});

    // Wait for Alice msg3
    await _waitForSignal('s5_alice_msg3');
    final s5m3 = await waitForMessage('S5: alice msg 3');
    print('[BOB] S5: received alice msg 3: ${s5m3 != null}');

    // Bob sends msg4
    final s5b4 = await sendFromBob('S5: bob msg 4');
    _writeTimingSignal('s5_bob_msg4', s5b4 ?? {});

    // Wait for Alice msg5
    await _waitForSignal('s5_alice_msg5');
    final s5m5 = await waitForMessage('S5: alice msg 5');
    print('[BOB] S5: received alice msg 5: ${s5m5 != null}');

    _writeTimingSignal('s5_bob_complete', {
      'received': [s5m1, s5m3, s5m5],
      'sent': [s5b2, s5b4],
    });

    // ════════════════════════════════════════════════════════════════
    //  S6: Stale connection — Bob killed abruptly
    // ════════════════════════════════════════════════════════════════
    print('\n--- S6: Stale kill ---');
    await _waitForSignal('s6_bob_kill');
    chatListener.dispose();
    await p2pService.stopNode();
    _writeSignal('s6_bob_killed', 'ok');
    print('[BOB] S6: Killed');

    await _waitForSignal('s6_bob_restart');
    started = await p2pService.startNode(ownPrivateKey, ownPeerId);
    if (!started) throw StateError('S6: restart failed');
    await _waitForOnline(p2pService);
    chatListener = ChatMessageListener(
      chatMessageStream: p2pService.messageStream,
      messageRepo: messageRepo,
      contactRepo: contactRepo,
      bridge: bridge,
      getOwnMlKemSecretKey: () async => ownMlKemSk,
    );
    chatListener.start();
    _writeSignal('s6_bob_restarted', 'ok');

    final s6 = await waitForMessage('S6:');
    print('[BOB] S6: ${s6 != null ? 'received (e2e=${s6['e2eMs']}ms)' : 'TIMEOUT'}');
    _writeTimingSignal('s6_bob_received', s6 ?? {'e2eMs': -1});

    // ════════════════════════════════════════════════════════════════
    //  S7: All-paths-fail — Bob does nothing
    // ════════════════════════════════════════════════════════════════
    print('\n--- S7: Idle (Alice sends to nonexistent peer) ---');

    // ════════════════════════════════════════════════════════════════
    //  S8: Full lifecycle — Bob's role
    // ════════════════════════════════════════════════════════════════
    print('\n--- S8: Full lifecycle ---');
    final s8Timeline = <Map<String, dynamic>>[];

    // Phase 1–2: Receive msg1–msg4
    for (var i = 1; i <= 4; i++) {
      final m = await waitForMessage('S8: msg$i', timeout: const Duration(seconds: 30));
      s8Timeline.add({'n': i, 'role': 'recv', ...?m});
      print('[BOB] S8: received msg$i: ${m != null}');
    }

    // Phase 3 [OFFLINE]
    await _waitForSignal('s8_bob_stop');
    chatListener.dispose();
    await p2pService.stopNode();
    _writeSignal('s8_bob_stopped', 'ok');
    print('[BOB] S8: stopped for offline phase');

    // Phase 4 [RESTART]
    await _waitForSignal('s8_bob_restart');
    started = await p2pService.startNode(ownPrivateKey, ownPeerId);
    if (!started) throw StateError('S8: restart failed');
    await _waitForOnline(p2pService);
    chatListener = ChatMessageListener(
      chatMessageStream: p2pService.messageStream,
      messageRepo: messageRepo,
      contactRepo: contactRepo,
      bridge: bridge,
      getOwnMlKemSecretKey: () async => ownMlKemSk,
    );
    chatListener.start();
    await Future<void>.delayed(const Duration(seconds: 3));
    await p2pService.warmBackground();
    _writeSignal('s8_bob_restarted', 'ok');

    // Inbox drain can lag or remain pending even when restart itself succeeded.
    // Don't block the rest of the lifecycle behind this best-effort receive.
    final msg5 = await waitForMessage('S8: msg5', timeout: const Duration(seconds: 15));
    s8Timeline.add({
      'n': 5,
      'role': 'recv_inbox',
      if (msg5 == null) 'pending': true,
      ...?msg5,
    });
    print('[BOB] S8: received msg5 via inbox: ${msg5 != null}');

    // Receive msg6 (reconnect)
    final msg6 = await waitForMessage('S8: msg6', timeout: const Duration(seconds: 30));
    s8Timeline.add({'n': 6, 'role': 'recv', ...?msg6});

    // Phase 5 [BIDIR]: Bob sends msg7
    final s8b7 = await sendFromBob('S8: bob msg7');
    s8Timeline.add({'n': 7, 'role': 'send', ...?s8b7});
    _writeTimingSignal('s8_bob_msg7', s8b7 ?? {});

    // Phase 6: Receive msg8–msg10
    for (var i = 8; i <= 10; i++) {
      final m = await waitForMessage('S8: msg$i', timeout: const Duration(seconds: 30));
      s8Timeline.add({'n': i, 'role': 'recv', ...?m});
    }

    _writeTimingSignal('s8_bob_complete', {'timeline': s8Timeline});
    print('[BOB] S8: lifecycle complete');

    // ════════════════════════════════════════════════════════════════
    //  S9: Batch inbox drain (5 messages while Bob offline)
    // ════════════════════════════════════════════════════════════════
    print('\n--- S9: Batch inbox drain ---');
    await _waitForSignal('s9_bob_stop');
    chatListener.dispose();
    await p2pService.stopNode();
    _writeSignal('s9_bob_stopped', 'ok');
    print('[BOB] S9: stopped');

    await _waitForSignal('s9_bob_restart');
    started = await p2pService.startNode(ownPrivateKey, ownPeerId);
    if (!started) throw StateError('S9: restart failed');
    await _waitForOnline(p2pService);
    chatListener = ChatMessageListener(
      chatMessageStream: p2pService.messageStream,
      messageRepo: messageRepo,
      contactRepo: contactRepo,
      bridge: bridge,
      getOwnMlKemSecretKey: () async => ownMlKemSk,
    );
    chatListener.start();
    await Future<void>.delayed(const Duration(seconds: 3));
    final s9Events = await _captureFlowEvents(() async {
      await p2pService.warmBackground();
    });

    // Capture INBOX_DELIVERY_TIMING events from the batch drain
    final s9DeliveryTimings = s9Events
        .where((e) => e['event'] == 'INBOX_DELIVERY_TIMING')
        .toList();
    for (final e in s9DeliveryTimings) {
      final d = e['details'] as Map<String, dynamic>;
      if (d.containsKey('deliveryMs')) {
        print('[SMOKE] inbox_delivery_ms=${d['deliveryMs']} messageId=${d['messageId']}');
      }
    }

    // Try to receive messages from inbox drain (15s each — best effort)
    final s9Received = <Map<String, dynamic>>[];
    for (var i = 1; i <= 5; i++) {
      final m = await waitForMessage('S9: batch inbox msg $i',
          timeout: const Duration(seconds: 15));
      if (m != null) s9Received.add(m);
      print('[BOB] S9: received msg $i: ${m != null}');
      if (m == null) break; // stop early if drain isn't delivering
    }
    _writeTimingSignal('s9_bob_received', {
      'count': s9Received.length,
      'timings': s9Received,
    });

    // ════════════════════════════════════════════════════════════════
    //  S10: Delete-for-everyone — Bob receives deletion
    // ════════════════════════════════════════════════════════════════
    print('\n--- S10: Waiting for message + deletion ---');
    final s10Msg = await waitForMessage('S10:', timeout: const Duration(seconds: 30));
    print('[BOB] S10: received msg: ${s10Msg != null}');
    _writeSignal('s10_bob_received_msg', 'ok');
    // The delete tombstone will arrive as a new message — wait for message count to change
    // or for the message to be marked deleted. For now, just signal received.

    // ════════════════════════════════════════════════════════════════
    //  S13: ACK under load — Bob receives 10 rapid messages
    // ════════════════════════════════════════════════════════════════
    print('\n--- S13: Receiving 10 rapid messages ---');
    final s13Received = <Map<String, dynamic>>[];
    for (var i = 1; i <= 10; i++) {
      final m = await waitForMessage('S13: rapid msg $i',
          timeout: const Duration(seconds: 15));
      if (m != null) s13Received.add(m);
    }
    print('[BOB] S13: received ${s13Received.length}/10');
    _writeTimingSignal('s13_bob_received', {
      'count': s13Received.length,
      'timings': s13Received,
    });

    // ════════════════════════════════════════════════════════════════
    //  S11: Voice/media — Bob side (Go handler processes upload)
    // ════════════════════════════════════════════════════════════════
    print('\n--- S11: Voice/media (Bob receives via Go handler) ---');
    // Bob's Go bridge handles the media upload stream automatically.
    // No explicit Dart action needed — just wait for Alice to finish.

    // ════════════════════════════════════════════════════════════════
    //  S12: 1MB media — Bob's Go handler processes upload automatically
    // ════════════════════════════════════════════════════════════════
    print('\n--- S12: 1MB media (Bob receives via Go handler) ---');

    // ════════════════════════════════════════════════════════════════
    //  S14: Local WiFi — Bob receives (same path as regular send)
    // ════════════════════════════════════════════════════════════════
    print('\n--- S14: Local WiFi ---');
    final s14Msg = await waitForMessage('S14:');
    print('[BOB] S14: received: ${s14Msg != null}');
    _writeTimingSignal('s14_bob_received', s14Msg ?? {'e2eMs': -1});

    // ════════════════════════════════════════════════════════════════
    //  S15: Relay probe — Bob restarts without rendezvous (brief window)
    // ════════════════════════════════════════════════════════════════
    print('\n--- S15: Relay probe ---');
    await _waitForSignal('s15_go');
    // Stop and restart to create a window where Bob is on relay but
    // not yet registered on rendezvous
    chatListener.dispose();
    await p2pService.stopNode();
    started = await p2pService.startNode(ownPrivateKey, ownPeerId);
    if (!started) throw StateError('S15: restart failed');
    // Signal immediately — before rendezvous registration completes
    _writeSignal('s15_bob_unregistered', 'ok');
    // Now wait for online (rendezvous registers in background)
    await _waitForOnline(p2pService);
    chatListener = ChatMessageListener(
      chatMessageStream: p2pService.messageStream,
      messageRepo: messageRepo,
      contactRepo: contactRepo,
      bridge: bridge,
      getOwnMlKemSecretKey: () async => ownMlKemSk,
    );
    chatListener.start();
    // Receive the relay probe message
    final s15Msg = await waitForMessage('S15:', timeout: const Duration(seconds: 30));
    print('[BOB] S15: received: ${s15Msg != null}');
    _writeTimingSignal('s15_bob_received', s15Msg ?? {'e2eMs': -1});

    // ════════════════════════════════════════════════════════════════
    //  X1: Node restart timing — Bob stops + restarts
    // ════════════════════════════════════════════════════════════════
    print('\n--- X1: Both-sides restart ---');
    await _waitForSignal('x1_go');
    chatListener.dispose();
    await p2pService.stopNode();
    _writeSignal('x1_bob_stopped', 'ok');

    await _waitForSignal('x1_restart');
    final x1Sw = Stopwatch()..start();
    started = await p2pService.startNode(ownPrivateKey, ownPeerId);
    if (!started) throw StateError('X1: restart failed');
    await _waitForOnline(p2pService);
    chatListener = ChatMessageListener(
      chatMessageStream: p2pService.messageStream,
      messageRepo: messageRepo,
      contactRepo: contactRepo,
      bridge: bridge,
      getOwnMlKemSecretKey: () async => ownMlKemSk,
    );
    chatListener.start();
    x1Sw.stop();
    _writeTimingSignal('x1_bob_restarted', {'restartMs': x1Sw.elapsedMilliseconds});

    // Receive post-restart message
    final x1Msg = await waitForMessage('X1:', timeout: const Duration(seconds: 60));
    print('[BOB] X1: received post-restart: ${x1Msg != null}');
    _writeTimingSignal('x1_bob_received', x1Msg ?? {'e2eMs': -1});

    // ════════════════════════════════════════════════════════════════
    //  X2: Background/foreground — Bob pauses + resumes
    // ════════════════════════════════════════════════════════════════
    print('\n--- X2: Background/foreground ---');
    await _waitForSignal('x2_go');
    await handleAppPaused(messageRepo: messageRepo);
    _writeSignal('x2_bob_paused', 'ok');

    await _waitForSignal('x2_resume');
    final x2Sw = Stopwatch()..start();
    await handleAppResumed(
      bridge: bridge,
      p2pService: p2pService,
    );
    x2Sw.stop();
    _writeTimingSignal('x2_bob_resumed', {'resumeMs': x2Sw.elapsedMilliseconds});

    final x2Msg = await waitForMessage('X2:', timeout: const Duration(seconds: 30));
    print('[BOB] X2: received post-resume: ${x2Msg != null}');
    _writeTimingSignal('x2_bob_received', x2Msg ?? {'e2eMs': -1});

    // ════════════════════════════════════════════════════════════════
    //  X3: Relay failover — Bob health check + receive
    // ════════════════════════════════════════════════════════════════
    print('\n--- X3: Relay failover ---');
    await _waitForSignal('x3_go');
    await p2pService.performImmediateHealthCheck();
    final x3Msg = await waitForMessage('X3:', timeout: const Duration(seconds: 30));
    print('[BOB] X3: received post-healthcheck: ${x3Msg != null}');
    _writeTimingSignal('x3_bob_received', x3Msg ?? {'e2eMs': -1});

    // ── Done ──
    await _waitForSignal('all_done');
    print('\n[BOB] All scenarios complete');

    chatListener.dispose();
    await p2pService.stopNode();
    p2pService.dispose();
    bridge.dispose();
    await db.close();
    await _deleteTestDatabase(_dbName);
    _writeSignal('bob_done', 'ok');
  });
}
