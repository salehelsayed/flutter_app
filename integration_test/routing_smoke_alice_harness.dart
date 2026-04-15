/// Routing Smoke E2E — Alice Harness (Sender)
///
/// Runs on simulator 1 (iPhone 17 Pro). Alice is the primary sender in all 8
/// scenarios (S1–S8). Coordinates with Bob harness via shared signal files.
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
import 'package:flutter_app/core/bridge/p2p_bridge_client.dart';
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
import 'package:flutter_app/features/conversation/application/delete_message_use_case.dart';
import 'package:flutter_app/features/conversation/application/send_chat_message_use_case.dart';
import 'package:flutter_app/features/conversation/application/send_voice_message_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/audio_recording.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository_impl.dart';
import 'package:flutter_app/features/p2p/presentation/widgets/connection_status_indicator.dart';

import '../test/shared/fakes/in_memory_inbox_staging_repository.dart';

// ---------------------------------------------------------------------------
// Config from dart-defines
// ---------------------------------------------------------------------------

const _sharedDir = String.fromEnvironment('E2E_SHARED_DIR', defaultValue: '/tmp');
const _runId = String.fromEnvironment('SMOKE_RUN_ID', defaultValue: 'adhoc');
const _dbName = String.fromEnvironment('E2E_DB_NAME', defaultValue: 'routing_smoke_alice.db');

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
  throw TimeoutException('Alice: timed out waiting for signal: $name');
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
  throw TimeoutException('Alice: timed out waiting for json signal: $name');
}

// ---------------------------------------------------------------------------
// Secure key store (in-memory)
// ---------------------------------------------------------------------------

class _FakeSecureKeyStore implements SecureKeyStore {
  final Map<String, String> _store = {};
  @override Future<String?> read(String key) async => _store[key];
  @override Future<void> write(String key, String value) async => _store[key] = value;
  @override Future<void> delete(String key) async => _store.remove(key);
  @override Future<bool> containsKey(String key) async => _store.containsKey(key);
}

// ---------------------------------------------------------------------------
// DB setup (matches transport_e2e_test.dart)
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
// Flow event capture
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

List<Map<String, dynamic>> _filter(List<Map<String, dynamic>> events, String name) =>
    events.where((e) => e['event'] == name).toList();

// ---------------------------------------------------------------------------
// Send + capture helper
// ---------------------------------------------------------------------------

Future<Map<String, dynamic>?> _sendAndCapture({
  required P2PServiceImpl p2pService,
  required MessageRepositoryImpl messageRepo,
  required GoBridgeClient bridge,
  required String ownPeerId,
  required String targetPeerId,
  required String? recipientMlKemPublicKey,
  required String text,
}) async {
  final events = await _captureFlowEvents(() async {
    await sendChatMessage(
      p2pService: p2pService,
      messageRepo: messageRepo,
      targetPeerId: targetPeerId,
      text: text,
      senderPeerId: ownPeerId,
      senderUsername: 'Alice',
      bridge: bridge,
      recipientMlKemPublicKey: recipientMlKemPublicKey,
    );
  });
  final timings = _filter(events, 'CHAT_MSG_SEND_TIMING');
  if (timings.isEmpty) return null;
  return timings.first['details'] as Map<String, dynamic>;
}

Map<String, dynamic> _timingJson(Map<String, dynamic>? d) {
  if (d == null) return {'outcome': 'no_timing'};
  return {
    'sendMs': d['elapsedMs'],
    'sendPath': d['sendPath'],
    'connectionReused': d['connectionReused'],
    'outcome': d['outcome'],
  };
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
      print('[ALICE] Online after ${sw.elapsedMilliseconds}ms');
      return true;
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  print('[ALICE] TIMEOUT waiting for Online');
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

  testWidgets('Alice — Routing Smoke S1–S8', (tester) async {
    print('\n${'═' * 60}');
    print('  ALICE HARNESS — ROUTING SMOKE E2E');
    print('${'═' * 60}\n');

    // ── Stack setup ──
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

    print('[ALICE] peerId=${ownPeerId.substring(0, 20)}...');

    // Start P2P node
    final p2pService = P2PServiceImpl(
      bridge: bridge,
      inboxStagingRepository: InMemoryInboxStagingRepository(),
    );
    final started = await p2pService.startNode(ownPrivateKey, ownPeerId);
    if (!started) throw StateError('P2P node failed to start');
    await _waitForOnline(p2pService);

    // Wire ChatMessageListener (Alice also receives in S5/S8)
    var chatListener = ChatMessageListener(
      chatMessageStream: p2pService.messageStream,
      messageRepo: messageRepo,
      contactRepo: contactRepo,
      bridge: bridge,
      getOwnMlKemSecretKey: () async => ownMlKemSk,
    );
    chatListener.start();

    // ── Identity exchange ──
    // Write identity first, then signal ready so orchestrator can launch Bob.
    _writeTimingSignal('alice_identity.json', {
      'peerId': ownPeerId,
      'publicKey': ownPublicKey,
      'mlKemPublicKey': ownMlKemPk,
    });

    // Signal ready BEFORE waiting for Bob — orchestrator needs this to launch Bob
    _writeSignal('alice_ready', 'ok');
    print('[ALICE] Ready (identity written, waiting for Bob...)');

    final bobFixture = await _waitForJsonSignal('bob_identity.json');
    final bobPeerId = bobFixture['peerId'] as String;
    final bobMlKemPk = bobFixture['mlKemPublicKey'] as String?;

    await contactRepo.addContact(ContactModel(
      peerId: bobPeerId,
      publicKey: bobFixture['publicKey'] as String,
      rendezvous: '/dns4/relay/tcp/443/p2p/relay',
      username: 'Bob',
      signature: 'sig-bob',
      scannedAt: DateTime.now().toUtc().toIso8601String(),
      mlKemPublicKey: bobMlKemPk,
    ));
    print('[ALICE] Bob added as contact');

    // Helper to send + capture timing
    Future<Map<String, dynamic>?> send(String text) => _sendAndCapture(
      p2pService: p2pService,
      messageRepo: messageRepo,
      bridge: bridge,
      ownPeerId: ownPeerId,
      targetPeerId: bobPeerId,
      recipientMlKemPublicKey: bobMlKemPk,
      text: text,
    );

    // Helper to wait for message in Alice's DB (for bidirectional receive)
    Future<bool> waitForIncoming(String substring, {Duration timeout = const Duration(seconds: 30)}) async {
      final deadline = DateTime.now().add(timeout);
      while (DateTime.now().isBefore(deadline)) {
        final msgs = await messageRepo.getMessagesForContact(bobPeerId);
        if (msgs.any((m) => m.isIncoming && m.text.contains(substring))) return true;
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
      return false;
    }

    // ════════════════════════════════════════════════════════════════
    //  S1: Cold send
    // ════════════════════════════════════════════════════════════════
    await _waitForSignal('s1_go');
    print('\n--- S1: Cold send ---');
    final s1 = await send('S1: cold hello from Alice');
    _writeTimingSignal('s1_alice_sent', _timingJson(s1));
    await _waitForSignal('s1_verified');

    // ════════════════════════════════════════════════════════════════
    //  S2: Warm send x5
    // ════════════════════════════════════════════════════════════════
    await _waitForSignal('s2_go');
    print('\n--- S2: Warm send x5 ---');
    await Future<void>.delayed(const Duration(seconds: 1));
    final s2Timings = <Map<String, dynamic>>[];
    for (var i = 1; i <= 5; i++) {
      final d = await send('S2: warm msg $i');
      s2Timings.add(_timingJson(d));
    }
    _writeTimingSignal('s2_alice_sent', {'timings': s2Timings});
    await _waitForSignal('s2_verified');

    // ════════════════════════════════════════════════════════════════
    //  S3: Bob offline → inbox
    // ════════════════════════════════════════════════════════════════
    await _waitForSignal('s3_go');
    print('\n--- S3: Offline inbox ---');
    await _waitForSignal('s3_bob_stopped');
    final s3 = await send('S3: inbox msg from Alice');
    _writeTimingSignal('s3_alice_sent', _timingJson(s3));
    await _waitForSignal('s3_verified');

    // ════════════════════════════════════════════════════════════════
    //  S4: Reconnect
    // ════════════════════════════════════════════════════════════════
    await _waitForSignal('s4_go');
    print('\n--- S4: Reconnect ---');
    final s4 = await send('S4: reconnect msg');
    _writeTimingSignal('s4_alice_sent', _timingJson(s4));
    await _waitForSignal('s4_verified');

    // ════════════════════════════════════════════════════════════════
    //  S5: Bidirectional
    // ════════════════════════════════════════════════════════════════
    await _waitForSignal('s5_go');
    print('\n--- S5: Bidirectional ---');
    final s5a1 = await send('S5: alice msg 1');
    _writeTimingSignal('s5_alice_msg1', _timingJson(s5a1));

    await _waitForSignal('s5_bob_msg2');
    final gotMsg2 = await waitForIncoming('S5: bob msg 2');
    print('[ALICE] S5: received bob msg 2: $gotMsg2');

    final s5a3 = await send('S5: alice msg 3');
    _writeTimingSignal('s5_alice_msg3', _timingJson(s5a3));

    await _waitForSignal('s5_bob_msg4');
    final gotMsg4 = await waitForIncoming('S5: bob msg 4');
    print('[ALICE] S5: received bob msg 4: $gotMsg4');

    final s5a5 = await send('S5: alice msg 5');
    _writeTimingSignal('s5_alice_msg5', _timingJson(s5a5));
    _writeSignal('s5_alice_complete', 'ok');

    // ════════════════════════════════════════════════════════════════
    //  S6: Stale connection
    // ════════════════════════════════════════════════════════════════
    await _waitForSignal('s6_go');
    print('\n--- S6: Stale connection ---');
    await _waitForSignal('s6_bob_restarted');
    final s6 = await send('S6: stale recovery msg');
    _writeTimingSignal('s6_alice_sent', _timingJson(s6));
    await _waitForSignal('s6_verified');

    // ════════════════════════════════════════════════════════════════
    //  S7: All-paths-fail
    // ════════════════════════════════════════════════════════════════
    await _waitForSignal('s7_go');
    print('\n--- S7: All-paths-fail ---');
    final s7Events = await _captureFlowEvents(() async {
      await sendChatMessage(
        p2pService: p2pService,
        messageRepo: messageRepo,
        targetPeerId: '12D3KooWAllPathsFailSmokePeer000000000000000',
        text: 'S7: all fail msg',
        senderPeerId: ownPeerId,
        senderUsername: 'Alice',
        bridge: bridge,
      );
    });
    final s7Timings = _filter(s7Events, 'CHAT_MSG_SEND_TIMING');
    final s7D = s7Timings.isNotEmpty
        ? s7Timings.first['details'] as Map<String, dynamic>
        : null;
    _writeTimingSignal('s7_alice_sent', _timingJson(s7D));

    // ════════════════════════════════════════════════════════════════
    //  S8: Full lifecycle (10 messages)
    // ════════════════════════════════════════════════════════════════
    await _waitForSignal('s8_go');
    print('\n--- S8: Full lifecycle ---');
    final timeline = <Map<String, dynamic>>[];

    // Phase 1 [COLD]: msg1
    var d = await send('S8: msg1 cold');
    timeline.add({'n': 1, 'label': 'cold', ..._timingJson(d)});

    // Phase 2 [WARM]: msg2–msg4
    await Future<void>.delayed(const Duration(seconds: 1));
    for (var i = 2; i <= 4; i++) {
      d = await send('S8: msg$i warm');
      timeline.add({'n': i, 'label': 'warm', ..._timingJson(d)});
    }
    _writeSignal('s8_warm_done', 'ok');

    // Phase 3 [OFFLINE]: wait for Bob stop, send msg5 to inbox
    await _waitForSignal('s8_bob_stopped');
    d = await send('S8: msg5 offline');
    timeline.add({'n': 5, 'label': 'offline', ..._timingJson(d)});
    _writeSignal('s8_inbox_sent', 'ok');

    // Phase 4 [RECONNECT]: wait for Bob restart, send msg6
    await _waitForSignal('s8_bob_restarted');
    d = await send('S8: msg6 reconnect');
    timeline.add({'n': 6, 'label': 'reconnect', ..._timingJson(d)});

    // Phase 5 [BIDIR]: wait for Bob's msg7
    await _waitForSignal('s8_bob_msg7');
    final gotMsg7 = await waitForIncoming('S8: bob msg7');
    timeline.add({'n': 7, 'label': 'recv', 'received': gotMsg7});

    // Phase 6 [WARM AGAIN]: msg8–msg10
    for (var i = 8; i <= 10; i++) {
      d = await send('S8: msg$i warm');
      timeline.add({'n': i, 'label': 'warm', ..._timingJson(d)});
    }
    _writeTimingSignal('s8_alice_complete', {'timeline': timeline});

    // ════════════════════════════════════════════════════════════════
    //  S9: Batch inbox drain (5 messages while Bob offline)
    // ════════════════════════════════════════════════════════════════
    await _waitForSignal('s9_go');
    print('\n--- S9: Batch inbox drain (5 msgs) ---');
    await _waitForSignal('s9_bob_stopped');
    final s9Timings = <Map<String, dynamic>>[];
    for (var i = 1; i <= 5; i++) {
      final s9d = await send('S9: batch inbox msg $i');
      s9Timings.add(_timingJson(s9d));
    }
    _writeTimingSignal('s9_alice_sent', {'timings': s9Timings});
    await _waitForSignal('s9_verified');

    // ════════════════════════════════════════════════════════════════
    //  S10: Delete-for-everyone E2E
    // ════════════════════════════════════════════════════════════════
    await _waitForSignal('s10_go');
    print('\n--- S10: Delete-for-everyone ---');
    // Send a message first, wait for Bob to receive it
    final s10SendResult = await sendChatMessage(
      p2pService: p2pService,
      messageRepo: messageRepo,
      targetPeerId: bobPeerId,
      text: 'S10: message to delete',
      senderPeerId: ownPeerId,
      senderUsername: 'Alice',
      bridge: bridge,
      recipientMlKemPublicKey: bobMlKemPk,
    );
    final s10SentMessage = s10SendResult.$2;
    _writeSignal('s10_alice_msg_sent', 'ok');
    await _waitForSignal('s10_bob_received_msg');

    // Now delete it using the real ConversationMessage
    final s10DeleteSw = Stopwatch()..start();
    final s10DeleteEvents = await _captureFlowEvents(() async {
      if (s10SentMessage != null) {
        await deleteMessageForEveryone(
          p2pService: p2pService,
          messageRepo: messageRepo,
          originalMessage: s10SentMessage,
          bridge: bridge,
          recipientMlKemPublicKey: bobMlKemPk,
        );
      }
    });
    s10DeleteSw.stop();
    final s10DeleteTimings = _filter(s10DeleteEvents, 'CHAT_MSG_DELETE_FOR_EVERYONE_TIMING');
    _writeTimingSignal('s10_alice_delete_sent', {
      'deleteMs': s10DeleteSw.elapsedMilliseconds,
      'outcome': s10DeleteTimings.isNotEmpty
          ? (s10DeleteTimings.first['details'] as Map<String, dynamic>)['outcome']
          : 'no_timing',
    });
    await _waitForSignal('s10_verified');

    // ════════════════════════════════════════════════════════════════
    //  S13: Deferred Direct ACK under load (10 rapid sends)
    // ════════════════════════════════════════════════════════════════
    await _waitForSignal('s13_go');
    print('\n--- S13: ACK under load (10 rapid sends) ---');
    final s13Timings = <Map<String, dynamic>>[];
    for (var i = 1; i <= 10; i++) {
      final d = await send('S13: rapid msg $i');
      s13Timings.add(_timingJson(d));
    }
    _writeTimingSignal('s13_alice_sent', {'timings': s13Timings});
    await _waitForSignal('s13_verified');

    // ════════════════════════════════════════════════════════════════
    //  S11: Voice message e2e (full sendVoiceMessage flow)
    // ════════════════════════════════════════════════════════════════
    await _waitForSignal('s11_go');
    print('\n--- S11: Voice message ---');
    final s11Sw = Stopwatch()..start();
    try {
      // Create a synthetic audio file
      final testFile = File('${Directory.systemTemp.path}/smoke_test_voice.mp4');
      testFile.writeAsBytesSync(List.filled(10240, 0x42)); // 10KB dummy

      final s11Events = await _captureFlowEvents(() async {
        await sendVoiceMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: bobPeerId,
          senderPeerId: ownPeerId,
          senderUsername: 'Alice',
          recording: AudioRecording(
            filePath: testFile.path,
            durationMs: 2000,
            sizeBytes: 10240,
          ),
          bridge: bridge,
          recipientMlKemPublicKey: bobMlKemPk,
          waveform: [0.1, 0.5, 0.8, 0.3, 0.6],
        );
      });
      s11Sw.stop();
      final s11Timings = _filter(s11Events, 'VOICE_SEND_TIMING');
      _writeTimingSignal('s11_alice_sent', {
        'totalMs': s11Sw.elapsedMilliseconds,
        'voiceTiming': s11Timings.isNotEmpty
            ? s11Timings.first['details']
            : null,
      });
    } catch (e) {
      s11Sw.stop();
      _writeTimingSignal('s11_alice_sent', {
        'totalMs': s11Sw.elapsedMilliseconds,
        'error': e.toString().substring(0, (e.toString().length).clamp(0, 200)),
      });
    }
    await _waitForSignal('s11_verified');

    // ════════════════════════════════════════════════════════════════
    //  S12: Media transfer 1MB + 5MB
    // ════════════════════════════════════════════════════════════════
    await _waitForSignal('s12_go');
    print('\n--- S12: 1MB media transfer ---');

    // -- 1MB upload --
    int? upload1mbMs;
    dynamic s12Result1mb;
    String? s12Error1mb;
    Map<String, dynamic>? s12StreamTiming1mb;
    // Create file BEFORE starting stopwatch so file I/O doesn't pollute timing
    final bigFile1mb = File('${Directory.systemTemp.path}/smoke_test_1mb.bin');
    bigFile1mb.writeAsBytesSync(List.filled(1024 * 1024, 0xAB)); // 1MB
    final s12Sw = Stopwatch()..start();
    final s12Events1mb = await _captureFlowEvents(() async {
      try {
        s12Result1mb = await callP2PMediaUpload(
          bridge,
          id: 'smoke-1mb-${DateTime.now().millisecondsSinceEpoch}',
          toPeerId: bobPeerId,
          mime: 'application/octet-stream',
          filePath: bigFile1mb.path,
        );
        s12Sw.stop();
        upload1mbMs = s12Sw.elapsedMilliseconds;
      } catch (e) {
        s12Sw.stop();
        upload1mbMs = s12Sw.elapsedMilliseconds;
        s12Error1mb = e.toString().substring(0, (e.toString().length).clamp(0, 200));
      }
    });
    final s12StreamOpen1mb = _filter(s12Events1mb, 'media:stream_open_timing');
    if (s12StreamOpen1mb.isNotEmpty) {
      s12StreamTiming1mb = s12StreamOpen1mb.first['details'] as Map<String, dynamic>?;
    }

    // -- 5MB upload --
    print('\n--- S12: 5MB media transfer ---');
    int? upload5mbMs;
    dynamic s12Result5mb;
    String? s12Error5mb;
    Map<String, dynamic>? s12StreamTiming5mb;
    final bigFile5mb = File('${Directory.systemTemp.path}/smoke_test_5mb.bin');
    bigFile5mb.writeAsBytesSync(List.filled(5 * 1024 * 1024, 0xCD)); // 5MB
    final s12Sw5 = Stopwatch()..start();
    final s12Events5mb = await _captureFlowEvents(() async {
      try {
        s12Result5mb = await callP2PMediaUpload(
          bridge,
          id: 'smoke-5mb-${DateTime.now().millisecondsSinceEpoch}',
          toPeerId: bobPeerId,
          mime: 'application/octet-stream',
          filePath: bigFile5mb.path,
        );
        s12Sw5.stop();
        upload5mbMs = s12Sw5.elapsedMilliseconds;
      } catch (e) {
        s12Sw5.stop();
        upload5mbMs = s12Sw5.elapsedMilliseconds;
        s12Error5mb = e.toString().substring(0, (e.toString().length).clamp(0, 200));
      }
    });
    final s12StreamOpen5mb = _filter(s12Events5mb, 'media:stream_open_timing');
    if (s12StreamOpen5mb.isNotEmpty) {
      s12StreamTiming5mb = s12StreamOpen5mb.first['details'] as Map<String, dynamic>?;
    }

    // -- Report combined signal --
    final s12Ok1mb = s12Error1mb == null && s12Result1mb is Map
        ? (s12Result1mb as Map<String, dynamic>)['ok']
        : false;
    final s12Ok5mb = s12Error5mb == null && s12Result5mb is Map
        ? (s12Result5mb as Map<String, dynamic>)['ok']
        : false;
    _writeTimingSignal('s12_alice_sent', {
      'uploadMs': upload1mbMs,
      'ok': s12Ok1mb,
      'sizeBytes': 1024 * 1024,
      'throughputKBps': (upload1mbMs ?? 0) > 0
          ? (1024 * 1000 / upload1mbMs!).round()
          : 0,
      if (s12Error1mb != null) 'error': s12Error1mb,
      if (s12StreamTiming1mb != null) 'streamOpenTiming1mb': s12StreamTiming1mb,
      'upload5mbMs': upload5mbMs,
      'ok5mb': s12Ok5mb,
      'sizeBytes5mb': 5 * 1024 * 1024,
      'throughput5mbKBps': (upload5mbMs ?? 0) > 0
          ? (5 * 1024 * 1000 / upload5mbMs!).round()
          : 0,
      if (s12Error5mb != null) 'error5mb': s12Error5mb,
      if (s12StreamTiming5mb != null) 'streamOpenTiming5mb': s12StreamTiming5mb,
    });
    await _waitForSignal('s12_verified');

    // ════════════════════════════════════════════════════════════════
    //  S14: Local WiFi transfer (attempt — may not work on all simulators)
    // ════════════════════════════════════════════════════════════════
    await _waitForSignal('s14_go');
    print('\n--- S14: Local WiFi ---');
    // Check if Bob is detected as a local peer (mDNS on same host network)
    final s14IsLocal = p2pService.isLocalPeer(bobPeerId);
    if (s14IsLocal) {
      final s14Send = await send('S14: local wifi msg');
      _writeTimingSignal('s14_alice_sent', {
        'isLocal': true,
        ..._timingJson(s14Send),
      });
    } else {
      // Local discovery not available — send via relay as fallback
      final s14Send = await send('S14: relay fallback msg');
      _writeTimingSignal('s14_alice_sent', {
        'isLocal': false,
        ..._timingJson(s14Send),
      });
    }
    await _waitForSignal('s14_verified');

    // ════════════════════════════════════════════════════════════════
    //  S15: Relay probe path (Bob unregistered from rendezvous)
    // ════════════════════════════════════════════════════════════════
    await _waitForSignal('s15_go');
    print('\n--- S15: Relay probe ---');
    // Bob has unregistered from rendezvous but is still connected to relay.
    // Alice's discover will fail → relayProbeEligible → probe → relay send.
    await _waitForSignal('s15_bob_unregistered');
    final s15Events = await _captureFlowEvents(() async {
      await sendChatMessage(
        p2pService: p2pService,
        messageRepo: messageRepo,
        targetPeerId: bobPeerId,
        text: 'S15: relay probe msg',
        senderPeerId: ownPeerId,
        senderUsername: 'Alice',
        bridge: bridge,
        recipientMlKemPublicKey: bobMlKemPk,
      );
    });
    final s15Timings = _filter(s15Events, 'CHAT_MSG_SEND_TIMING');
    final s15ProbeEvents = _filter(s15Events, 'CHAT_MSG_SEND_RELAY_PROBE_BEGIN');
    final s15Details = s15Timings.isNotEmpty
        ? s15Timings.first['details'] as Map<String, dynamic>
        : <String, dynamic>{};
    _writeTimingSignal('s15_alice_sent', {
      'sendMs': s15Details['elapsedMs'],
      'sendPath': s15Details['sendPath'],
      'outcome': s15Details['outcome'],
      'probeAttempted': s15ProbeEvents.isNotEmpty,
    });
    await _waitForSignal('s15_verified');

    // ════════════════════════════════════════════════════════════════
    //  X1: Node restart timing (both sides)
    // ════════════════════════════════════════════════════════════════
    await _waitForSignal('x1_go');
    print('\n--- X1: Both-sides restart ---');
    // Stop node
    chatListener.dispose();
    await p2pService.stopNode();
    _writeSignal('x1_alice_stopped', 'ok');

    // Wait for orchestrator signal to restart
    await _waitForSignal('x1_restart');
    final x1Sw = Stopwatch()..start();
    final x1Started = await p2pService.startNode(ownPrivateKey, ownPeerId);
    if (!x1Started) throw StateError('X1: restart failed');
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
    _writeTimingSignal('x1_alice_restarted', {'restartMs': x1Sw.elapsedMilliseconds});

    // Wait for Bob to also be restarted, then send
    await _waitForSignal('x1_bob_restarted');
    await Future<void>.delayed(const Duration(seconds: 3));
    final x1Send = await send('X1: post-restart msg');
    _writeTimingSignal('x1_alice_sent', _timingJson(x1Send));
    await _waitForSignal('x1_verified');

    // ════════════════════════════════════════════════════════════════
    //  X2: Background/foreground cycle
    // ════════════════════════════════════════════════════════════════
    await _waitForSignal('x2_go');
    print('\n--- X2: Background/foreground ---');
    // Simulate background
    await handleAppPaused(messageRepo: messageRepo);
    _writeSignal('x2_alice_paused', 'ok');

    await _waitForSignal('x2_resume');
    final x2Sw = Stopwatch()..start();
    await handleAppResumed(
      bridge: bridge,
      p2pService: p2pService,
    );
    x2Sw.stop();
    _writeTimingSignal('x2_alice_resumed', {'resumeMs': x2Sw.elapsedMilliseconds});

    // Send after resume
    final x2Send = await send('X2: post-resume msg');
    _writeTimingSignal('x2_alice_sent', _timingJson(x2Send));
    await _waitForSignal('x2_verified');

    // ════════════════════════════════════════════════════════════════
    //  X3: Relay failover (disconnect + recover)
    // ════════════════════════════════════════════════════════════════
    await _waitForSignal('x3_go');
    print('\n--- X3: Relay failover ---');
    // Trigger health check which detects relay state
    final x3Sw = Stopwatch()..start();
    await p2pService.performImmediateHealthCheck();
    x3Sw.stop();
    // Send after health check
    final x3Send = await send('X3: post-healthcheck msg');
    _writeTimingSignal('x3_alice_sent', {
      'healthCheckMs': x3Sw.elapsedMilliseconds,
      ..._timingJson(x3Send),
    });
    await _waitForSignal('x3_verified');

    // ── Done ──
    await _waitForSignal('all_done');
    print('\n[ALICE] All scenarios complete');

    // Teardown
    chatListener.dispose();
    await p2pService.stopNode();
    p2pService.dispose();
    bridge.dispose();
    await db.close();
    await _deleteTestDatabase(_dbName);
    _writeSignal('alice_done', 'ok');
  });
}
