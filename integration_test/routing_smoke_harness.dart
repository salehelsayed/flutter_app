/// Routing Smoke E2E — Role-Dispatched Harness (Alice + Bob)
///
/// Single harness launched twice by the orchestrator with
/// `--dart-define=SMOKE_ROLE=alice` (sender) and `SMOKE_ROLE=bob` (receiver).
///
/// Alice is the primary sender in all scenarios (S1–S15, X1–X3). Bob is the
/// primary receiver and also sends in S5 (bidirectional) and S8 (lifecycle).
/// The two sides coordinate via shared signal files.
///
/// Launch via orchestrator:
///   `dart run integration_test/scripts/run_routing_smoke_e2e.dart -d <alice>,<bob>`
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite_sqlcipher/sqflite.dart' as sqlcipher;

import 'package:flutter_app/core/bridge/go_bridge_client.dart';
import 'package:flutter_app/core/bridge/p2p_bridge_client.dart';
import 'package:flutter_app/core/database/helpers/contacts_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/messages_db_helpers.dart';
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

import '../test/shared/fakes/in_memory_inbox_staging_repository.dart';
import '_support/fake_secure_key_store.dart';
import '_support/node_readiness.dart';
import '_support/signal_files.dart';
import '_support/test_db_seeder.dart';

// ---------------------------------------------------------------------------
// Config from dart-defines
// ---------------------------------------------------------------------------

const _role = String.fromEnvironment('SMOKE_ROLE', defaultValue: 'alice');
const _sharedDir = String.fromEnvironment(
  'E2E_SHARED_DIR',
  defaultValue: '/tmp',
);
const _runId = String.fromEnvironment('SMOKE_RUN_ID', defaultValue: 'adhoc');
const _dbName = String.fromEnvironment(
  'E2E_DB_NAME',
  defaultValue: 'routing_smoke.db',
);

// ---------------------------------------------------------------------------
// Signal helpers — canonical SignalDir (see integration_test/_support/
// signal_files.dart). Path layout reproduced byte-identically:
//   `_signals.path(name)` == `'$_sharedDir/smoke_${_runId}_$name'`
// (prefix 'smoke_' + runId '${_runId}_' so the literal '_' that followed the
// run id in the old inline `_sig` is preserved).
// ---------------------------------------------------------------------------

final SignalDir _signals = SignalDir(
  dir: _sharedDir,
  prefix: 'smoke_',
  runId: '${_runId}_',
  role: _role,
);

// ---------------------------------------------------------------------------
// DB setup (identical for both roles — see _support/test_db_seeder.dart)
// ---------------------------------------------------------------------------

Future<sqlcipher.Database> _openDb(SecureKeyStore keyStore) =>
    openE2EDatabase(secureKeyStore: keyStore, dbName: _dbName, version: 79);

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
      .map(
        (l) =>
            jsonDecode(l.substring('[FLOW] '.length)) as Map<String, dynamic>,
      )
      .toList();
}

List<Map<String, dynamic>> _filter(
  List<Map<String, dynamic>> events,
  String name,
) => events.where((e) => e['event'] == name).toList();

// ---------------------------------------------------------------------------
// Send + capture helper (Alice path)
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

Future<ContactModel> _generateUnreachableContact({
  required GoBridgeClient bridge,
  required String username,
}) async {
  final identityResponse = await bridge.send(
    jsonEncode({'cmd': 'identity.generate', 'payload': {}}),
  );
  final identityResult = jsonDecode(identityResponse) as Map<String, dynamic>;
  if (identityResult['ok'] != true) {
    throw StateError('identity.generate for $username failed: $identityResult');
  }
  final identity = identityResult['identity'] as Map<String, dynamic>;

  final mlKemResponse = await bridge.send(
    jsonEncode({'cmd': 'mlkem.keygen', 'payload': {}}),
  );
  final mlKemResult = jsonDecode(mlKemResponse) as Map<String, dynamic>;
  if (mlKemResult['ok'] != true) {
    throw StateError('mlkem.keygen for $username failed: $mlKemResult');
  }

  return ContactModel(
    peerId: identity['peerId'] as String,
    publicKey: identity['publicKey'] as String,
    rendezvous: '/dns4/relay/tcp/443/p2p/relay',
    username: username,
    signature: 'sig-$username',
    scannedAt: DateTime.now().toUtc().toIso8601String(),
    mlKemPublicKey: mlKemResult['publicKey'] as String,
  );
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
// Main — dispatches on SMOKE_ROLE
// ---------------------------------------------------------------------------

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  if (Platform.isLinux || Platform.isMacOS || Platform.isWindows) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  if (_role == 'bob') {
    _runBob();
  } else {
    _runAlice();
  }
}

// ===========================================================================
//  ALICE (sender)
// ===========================================================================

void _runAlice() {
  testWidgets('Alice — Routing Smoke S1–S8', (tester) async {
    print('\n${'═' * 60}');
    print('  ALICE HARNESS — ROUTING SMOKE E2E');
    print('${'═' * 60}\n');

    // ── Stack setup ──
    final keyStore = FakeSecureKeyStore();
    final db = await openE2EDatabase(
      secureKeyStore: keyStore,
      dbName: _dbName,
      version: 79,
    );
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
      dbLoadLatestMessageForContact: (p) =>
          dbLoadLatestMessageForContact(db, p),
      dbUpdateMessageStatus: (id, s) => dbUpdateMessageStatus(db, id, s),
      dbLoadMessage: (id) => dbLoadMessage(db, id),
      dbExistsMessageByContent:
          (contactPeerId, senderPeerId, text, timestamp) =>
              dbExistsMessageByContent(
                db,
                contactPeerId,
                senderPeerId,
                text,
                timestamp,
              ),
      dbCountMessagesForContact: (p) => dbCountMessagesForContact(db, p),
      dbMarkConversationAsRead: (p) => dbMarkConversationAsRead(db, p),
      dbCountUnreadForContact: (p) => dbCountUnreadForContact(db, p),
      dbCountTotalUnread: () => dbCountTotalUnread(db),
      dbCountTotalUnreadExcludingArchived: () =>
          dbCountTotalUnreadExcludingArchived(db),
      dbDeleteMessagesForContact: (p) => dbDeleteMessagesForContact(db, p),
      dbDeleteMessage: (id) => dbDeleteMessage(db, id),
      dbLoadMessagesPage: (p, {limit = 50, beforeTimestamp}) =>
          dbLoadMessagesPage(
            db,
            p,
            limit: limit,
            beforeTimestamp: beforeTimestamp,
          ),
      dbLoadFailedOutgoingMessages: () => dbLoadFailedOutgoingMessages(db),
      dbLoadUnackedOutgoingMessages: ({required olderThan, limit = 50}) =>
          dbLoadUnackedOutgoingMessages(db, olderThan: olderThan, limit: limit),
      dbLoadConversationThreadSummaries: (ids) =>
          dbLoadConversationThreadSummaries(db, ids),
      dbRecoverStuckSendingMessages:
          ({required DateTime olderThan, int limit = 50}) =>
              dbRecoverStuckSendingMessages(
                db,
                olderThan: olderThan,
                limit: limit,
              ),
      dbUpdateWireEnvelope: (id, we) => dbUpdateWireEnvelope(db, id, we),
      dbLoadStuckSendingOutgoingMessages:
          ({required DateTime olderThan, int limit = 50}) =>
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

    // Generate identity
    final genResp = await bridge.send(
      jsonEncode({'cmd': 'identity.generate', 'payload': {}}),
    );
    final genResult = jsonDecode(genResp) as Map<String, dynamic>;
    if (genResult['ok'] != true) throw StateError('identity.generate failed');
    final identity = genResult['identity'] as Map<String, dynamic>;
    final ownPeerId = identity['peerId'] as String;
    final ownPrivateKey = identity['privateKey'] as String;
    final ownPublicKey = identity['publicKey'] as String;

    final mlkemResp = await bridge.send(
      jsonEncode({'cmd': 'mlkem.keygen', 'payload': {}}),
    );
    final mlkemResult = jsonDecode(mlkemResp) as Map<String, dynamic>;
    final ownMlKemPk = mlkemResult['ok'] == true
        ? mlkemResult['publicKey'] as String?
        : null;
    final ownMlKemSk = mlkemResult['ok'] == true
        ? mlkemResult['secretKey'] as String?
        : null;

    print('[ALICE] peerId=${ownPeerId.substring(0, 20)}...');

    // Start P2P node
    final p2pService = P2PServiceImpl(
      bridge: bridge,
      inboxStagingRepository: InMemoryInboxStagingRepository(),
    );
    final started = await p2pService.startNode(ownPrivateKey, ownPeerId);
    if (!started) throw StateError('P2P node failed to start');
    await waitForOnline(p2pService, timeout: const Duration(seconds: 60));

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
    _signals.writeJson('alice_identity.json', {
      'peerId': ownPeerId,
      'publicKey': ownPublicKey,
      'mlKemPublicKey': ownMlKemPk,
    });

    // Signal ready BEFORE waiting for Bob — orchestrator needs this to launch Bob
    _signals.writeSignal('alice_ready');
    print('[ALICE] Ready (identity written, waiting for Bob...)');

    final bobFixture = await _signals.waitForJson(
      'bob_identity.json',
      timeout: const Duration(minutes: 15),
    );
    final bobPeerId = bobFixture['peerId'] as String;
    final bobMlKemPk = bobFixture['mlKemPublicKey'] as String?;

    await contactRepo.addContact(
      ContactModel(
        peerId: bobPeerId,
        publicKey: bobFixture['publicKey'] as String,
        rendezvous: '/dns4/relay/tcp/443/p2p/relay',
        username: 'Bob',
        signature: 'sig-bob',
        scannedAt: DateTime.now().toUtc().toIso8601String(),
        mlKemPublicKey: bobMlKemPk,
      ),
    );
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
    Future<bool> waitForIncoming(
      String substring, {
      Duration timeout = const Duration(seconds: 30),
    }) async {
      final deadline = DateTime.now().add(timeout);
      while (DateTime.now().isBefore(deadline)) {
        final msgs = await messageRepo.getMessagesForContact(bobPeerId);
        if (msgs.any((m) => m.isIncoming && m.text.contains(substring))) {
          return true;
        }
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
      return false;
    }

    // ════════════════════════════════════════════════════════════════
    //  S1: Cold send
    // ════════════════════════════════════════════════════════════════
    await _signals.waitForSignal('s1_go');
    print('\n--- S1: Cold send ---');
    final s1 = await send('S1: cold hello from Alice');
    _signals.writeJson('s1_alice_sent', _timingJson(s1));
    await _signals.waitForSignal('s1_verified');

    // 132 convergence: once Bob has received S1, Alice's outgoing row must
    // converge to 'delivered' — via the live ack OR Bob's confirmatory delivery
    // receipt (Phase 1). Poll briefly for the receipt round-trip, then report
    // the final status for the orchestrator to assert.
    var s1Status = '';
    for (var i = 0; i < 30; i++) {
      final msgs = await messageRepo.getMessagesForContact(bobPeerId);
      final outgoing = msgs
          .where(
            (m) => !m.isIncoming && m.text.contains('S1: cold hello from Alice'),
          )
          .toList();
      s1Status = outgoing.isNotEmpty ? outgoing.last.status : '';
      if (s1Status == 'delivered') break;
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    print('--- S1 convergence: Alice status=$s1Status ---');
    _signals.writeJson('s1_alice_converged', {
      'status': s1Status,
      'delivered': s1Status == 'delivered',
    });

    // ════════════════════════════════════════════════════════════════
    //  S2: Warm send x5
    // ════════════════════════════════════════════════════════════════
    await _signals.waitForSignal('s2_go');
    print('\n--- S2: Warm send x5 ---');
    await Future<void>.delayed(const Duration(seconds: 1));
    final s2Timings = <Map<String, dynamic>>[];
    for (var i = 1; i <= 5; i++) {
      final d = await send('S2: warm msg $i');
      s2Timings.add(_timingJson(d));
    }
    _signals.writeJson('s2_alice_sent', {'timings': s2Timings});
    await _signals.waitForSignal('s2_verified');

    // ════════════════════════════════════════════════════════════════
    //  S3: Bob offline → inbox
    // ════════════════════════════════════════════════════════════════
    await _signals.waitForSignal('s3_go');
    print('\n--- S3: Offline inbox ---');
    await _signals.waitForSignal('s3_bob_stopped');
    final s3 = await send('S3: inbox msg from Alice');
    _signals.writeJson('s3_alice_sent', _timingJson(s3));
    await _signals.waitForSignal('s3_verified');

    // ════════════════════════════════════════════════════════════════
    //  S4: Reconnect
    // ════════════════════════════════════════════════════════════════
    await _signals.waitForSignal('s4_go');
    print('\n--- S4: Reconnect ---');
    final s4 = await send('S4: reconnect msg');
    _signals.writeJson('s4_alice_sent', _timingJson(s4));
    await _signals.waitForSignal('s4_verified');

    // ════════════════════════════════════════════════════════════════
    //  S5: Bidirectional
    // ════════════════════════════════════════════════════════════════
    await _signals.waitForSignal('s5_go');
    print('\n--- S5: Bidirectional ---');
    final s5a1 = await send('S5: alice msg 1');
    _signals.writeJson('s5_alice_msg1', _timingJson(s5a1));

    await _signals.waitForSignal('s5_bob_msg2');
    final gotMsg2 = await waitForIncoming('S5: bob msg 2');
    print('[ALICE] S5: received bob msg 2: $gotMsg2');

    final s5a3 = await send('S5: alice msg 3');
    _signals.writeJson('s5_alice_msg3', _timingJson(s5a3));

    await _signals.waitForSignal('s5_bob_msg4');
    final gotMsg4 = await waitForIncoming('S5: bob msg 4');
    print('[ALICE] S5: received bob msg 4: $gotMsg4');

    final s5a5 = await send('S5: alice msg 5');
    _signals.writeJson('s5_alice_msg5', _timingJson(s5a5));
    _signals.writeSignal('s5_alice_complete');

    // ════════════════════════════════════════════════════════════════
    //  S6: Stale connection
    // ════════════════════════════════════════════════════════════════
    await _signals.waitForSignal('s6_go');
    print('\n--- S6: Stale connection ---');
    await _signals.waitForSignal('s6_bob_restarted');
    final s6 = await send('S6: stale recovery msg');
    _signals.writeJson('s6_alice_sent', _timingJson(s6));
    await _signals.waitForSignal('s6_verified');

    // ════════════════════════════════════════════════════════════════
    //  S7: All-paths-fail
    // ════════════════════════════════════════════════════════════════
    await _signals.waitForSignal('s7_go');
    print('\n--- S7: All-paths-fail ---');
    final s7Contact = await _generateUnreachableContact(
      bridge: bridge,
      username: 'AllPathsFailSmoke',
    );
    await contactRepo.addContact(s7Contact);
    final s7Events = await _captureFlowEvents(() async {
      await sendChatMessage(
        p2pService: p2pService,
        messageRepo: messageRepo,
        targetPeerId: s7Contact.peerId,
        text: 'S7: all fail msg',
        senderPeerId: ownPeerId,
        senderUsername: 'Alice',
        bridge: bridge,
        recipientMlKemPublicKey: s7Contact.mlKemPublicKey,
      );
    });
    final s7Timings = _filter(s7Events, 'CHAT_MSG_SEND_TIMING');
    final s7D = s7Timings.isNotEmpty
        ? s7Timings.first['details'] as Map<String, dynamic>
        : null;
    _signals.writeJson('s7_alice_sent', _timingJson(s7D));

    // ════════════════════════════════════════════════════════════════
    //  S8: Full lifecycle (10 messages)
    // ════════════════════════════════════════════════════════════════
    await _signals.waitForSignal('s8_go');
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
    _signals.writeSignal('s8_warm_done');

    // Phase 3 [OFFLINE]: wait for Bob stop, send msg5 to inbox
    await _signals.waitForSignal('s8_bob_stopped');
    d = await send('S8: msg5 offline');
    timeline.add({'n': 5, 'label': 'offline', ..._timingJson(d)});
    _signals.writeSignal('s8_inbox_sent');

    // Phase 4 [RECONNECT]: wait for Bob restart, send msg6
    await _signals.waitForSignal('s8_bob_restarted');
    d = await send('S8: msg6 reconnect');
    timeline.add({'n': 6, 'label': 'reconnect', ..._timingJson(d)});

    // Phase 5 [BIDIR]: wait for Bob's msg7
    await _signals.waitForSignal('s8_bob_msg7');
    final gotMsg7 = await waitForIncoming('S8: bob msg7');
    timeline.add({'n': 7, 'label': 'recv', 'received': gotMsg7});

    // Phase 6 [WARM AGAIN]: msg8–msg10
    for (var i = 8; i <= 10; i++) {
      d = await send('S8: msg$i warm');
      timeline.add({'n': i, 'label': 'warm', ..._timingJson(d)});
    }
    _signals.writeJson('s8_alice_complete', {'timeline': timeline});

    // ════════════════════════════════════════════════════════════════
    //  S9: Batch inbox drain (5 messages while Bob offline)
    // ════════════════════════════════════════════════════════════════
    await _signals.waitForSignal('s9_go');
    print('\n--- S9: Batch inbox drain (5 msgs) ---');
    await _signals.waitForSignal('s9_bob_stopped');
    final s9Timings = <Map<String, dynamic>>[];
    for (var i = 1; i <= 5; i++) {
      final s9d = await send('S9: batch inbox msg $i');
      s9Timings.add(_timingJson(s9d));
    }
    _signals.writeJson('s9_alice_sent', {'timings': s9Timings});
    await _signals.waitForSignal('s9_verified');

    // ════════════════════════════════════════════════════════════════
    //  S10: Delete-for-everyone E2E
    // ════════════════════════════════════════════════════════════════
    await _signals.waitForSignal('s10_go');
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
    _signals.writeSignal('s10_alice_msg_sent');
    await _signals.waitForSignal('s10_bob_received_msg');

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
    final s10DeleteTimings = _filter(
      s10DeleteEvents,
      'CHAT_MSG_DELETE_FOR_EVERYONE_TIMING',
    );
    _signals.writeJson('s10_alice_delete_sent', {
      'deleteMs': s10DeleteSw.elapsedMilliseconds,
      'outcome': s10DeleteTimings.isNotEmpty
          ? (s10DeleteTimings.first['details']
                as Map<String, dynamic>)['outcome']
          : 'no_timing',
    });
    await _signals.waitForSignal('s10_verified');

    // ════════════════════════════════════════════════════════════════
    //  S13: Deferred Direct ACK under load (10 rapid sends)
    // ════════════════════════════════════════════════════════════════
    await _signals.waitForSignal('s13_go');
    print('\n--- S13: ACK under load (10 rapid sends) ---');
    final s13Timings = <Map<String, dynamic>>[];
    for (var i = 1; i <= 10; i++) {
      final d = await send('S13: rapid msg $i');
      s13Timings.add(_timingJson(d));
    }
    _signals.writeJson('s13_alice_sent', {'timings': s13Timings});
    await _signals.waitForSignal('s13_verified');

    // ════════════════════════════════════════════════════════════════
    //  S11: Voice message e2e (full sendVoiceMessage flow)
    // ════════════════════════════════════════════════════════════════
    await _signals.waitForSignal('s11_go');
    print('\n--- S11: Voice message ---');
    final s11Sw = Stopwatch()..start();
    try {
      // Create a synthetic audio file
      final testFile = File(
        '${Directory.systemTemp.path}/smoke_test_voice.mp4',
      );
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
      _signals.writeJson('s11_alice_sent', {
        'totalMs': s11Sw.elapsedMilliseconds,
        'voiceTiming': s11Timings.isNotEmpty
            ? s11Timings.first['details']
            : null,
      });
    } catch (e) {
      s11Sw.stop();
      _signals.writeJson('s11_alice_sent', {
        'totalMs': s11Sw.elapsedMilliseconds,
        'error': e.toString().substring(0, (e.toString().length).clamp(0, 200)),
      });
    }
    await _signals.waitForSignal('s11_verified');

    // ════════════════════════════════════════════════════════════════
    //  S12: Media transfer 1MB + 5MB
    // ════════════════════════════════════════════════════════════════
    await _signals.waitForSignal('s12_go');
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
        s12Error1mb = e.toString().substring(
          0,
          (e.toString().length).clamp(0, 200),
        );
      }
    });
    final s12StreamOpen1mb = _filter(s12Events1mb, 'media:stream_open_timing');
    if (s12StreamOpen1mb.isNotEmpty) {
      s12StreamTiming1mb =
          s12StreamOpen1mb.first['details'] as Map<String, dynamic>?;
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
        s12Error5mb = e.toString().substring(
          0,
          (e.toString().length).clamp(0, 200),
        );
      }
    });
    final s12StreamOpen5mb = _filter(s12Events5mb, 'media:stream_open_timing');
    if (s12StreamOpen5mb.isNotEmpty) {
      s12StreamTiming5mb =
          s12StreamOpen5mb.first['details'] as Map<String, dynamic>?;
    }

    // -- Report combined signal --
    final s12Ok1mb = s12Error1mb == null && s12Result1mb is Map
        ? (s12Result1mb as Map<String, dynamic>)['ok']
        : false;
    final s12Ok5mb = s12Error5mb == null && s12Result5mb is Map
        ? (s12Result5mb as Map<String, dynamic>)['ok']
        : false;
    _signals.writeJson('s12_alice_sent', {
      'uploadMs': upload1mbMs,
      'ok': s12Ok1mb,
      'sizeBytes': 1024 * 1024,
      'throughputKBps': (upload1mbMs ?? 0) > 0
          ? (1024 * 1000 / upload1mbMs!).round()
          : 0,
      'error': ?s12Error1mb,
      'streamOpenTiming1mb': ?s12StreamTiming1mb,
      'upload5mbMs': upload5mbMs,
      'ok5mb': s12Ok5mb,
      'sizeBytes5mb': 5 * 1024 * 1024,
      'throughput5mbKBps': (upload5mbMs ?? 0) > 0
          ? (5 * 1024 * 1000 / upload5mbMs!).round()
          : 0,
      'error5mb': ?s12Error5mb,
      'streamOpenTiming5mb': ?s12StreamTiming5mb,
    });
    await _signals.waitForSignal('s12_verified');

    // ════════════════════════════════════════════════════════════════
    //  S14: Local WiFi transfer (attempt — may not work on all simulators)
    // ════════════════════════════════════════════════════════════════
    await _signals.waitForSignal('s14_go');
    print('\n--- S14: Local WiFi ---');
    // Check if Bob is detected as a local peer (mDNS on same host network)
    final s14IsLocal = p2pService.isLocalPeer(bobPeerId);
    if (s14IsLocal) {
      final s14Send = await send('S14: local wifi msg');
      _signals.writeJson('s14_alice_sent', {
        'isLocal': true,
        ..._timingJson(s14Send),
      });
    } else {
      // Local discovery not available — send via relay as fallback
      final s14Send = await send('S14: relay fallback msg');
      _signals.writeJson('s14_alice_sent', {
        'isLocal': false,
        ..._timingJson(s14Send),
      });
    }
    await _signals.waitForSignal('s14_verified');

    // ════════════════════════════════════════════════════════════════
    //  S15: Relay probe path (Bob unregistered from rendezvous)
    // ════════════════════════════════════════════════════════════════
    await _signals.waitForSignal('s15_go');
    print('\n--- S15: Relay probe ---');
    // Bob has unregistered from rendezvous but is still connected to relay.
    // Alice's discover will fail → relayProbeEligible → probe → relay send.
    await _signals.waitForSignal('s15_bob_unregistered');
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
    final s15ProbeEvents = _filter(
      s15Events,
      'CHAT_MSG_SEND_RELAY_PROBE_BEGIN',
    );
    final s15Details = s15Timings.isNotEmpty
        ? s15Timings.first['details'] as Map<String, dynamic>
        : <String, dynamic>{};
    _signals.writeJson('s15_alice_sent', {
      'sendMs': s15Details['elapsedMs'],
      'sendPath': s15Details['sendPath'],
      'outcome': s15Details['outcome'],
      'probeAttempted': s15ProbeEvents.isNotEmpty,
    });
    await _signals.waitForSignal('s15_verified');

    // ════════════════════════════════════════════════════════════════
    //  X1: Node restart timing (both sides)
    // ════════════════════════════════════════════════════════════════
    await _signals.waitForSignal('x1_go');
    print('\n--- X1: Both-sides restart ---');
    // Stop node
    chatListener.dispose();
    await p2pService.stopNode();
    _signals.writeSignal('x1_alice_stopped');

    // Wait for orchestrator signal to restart
    await _signals.waitForSignal('x1_restart');
    final x1Sw = Stopwatch()..start();
    final x1Started = await p2pService.startNode(ownPrivateKey, ownPeerId);
    if (!x1Started) throw StateError('X1: restart failed');
    await waitForOnline(p2pService, timeout: const Duration(seconds: 60));
    chatListener = ChatMessageListener(
      chatMessageStream: p2pService.messageStream,
      messageRepo: messageRepo,
      contactRepo: contactRepo,
      bridge: bridge,
      getOwnMlKemSecretKey: () async => ownMlKemSk,
    );
    chatListener.start();
    x1Sw.stop();
    _signals.writeJson('x1_alice_restarted', {
      'restartMs': x1Sw.elapsedMilliseconds,
    });

    // Wait for Bob to also be restarted, then send
    await _signals.waitForSignal('x1_bob_restarted');
    await Future<void>.delayed(const Duration(seconds: 3));
    final x1Send = await send('X1: post-restart msg');
    _signals.writeJson('x1_alice_sent', _timingJson(x1Send));
    await _signals.waitForSignal('x1_verified');

    // ════════════════════════════════════════════════════════════════
    //  X2: Background/foreground cycle
    // ════════════════════════════════════════════════════════════════
    await _signals.waitForSignal('x2_go');
    print('\n--- X2: Background/foreground ---');
    // Simulate background
    await handleAppPaused(messageRepo: messageRepo);
    _signals.writeSignal('x2_alice_paused');

    await _signals.waitForSignal('x2_resume');
    final x2Sw = Stopwatch()..start();
    await handleAppResumed(bridge: bridge, p2pService: p2pService);
    x2Sw.stop();
    _signals.writeJson('x2_alice_resumed', {
      'resumeMs': x2Sw.elapsedMilliseconds,
    });

    // Send after resume
    final x2Send = await send('X2: post-resume msg');
    _signals.writeJson('x2_alice_sent', _timingJson(x2Send));
    await _signals.waitForSignal('x2_verified');

    // ════════════════════════════════════════════════════════════════
    //  X3: Relay failover (disconnect + recover)
    // ════════════════════════════════════════════════════════════════
    await _signals.waitForSignal('x3_go');
    print('\n--- X3: Relay failover ---');
    // Trigger health check which detects relay state
    final x3Sw = Stopwatch()..start();
    await p2pService.performImmediateHealthCheck();
    x3Sw.stop();
    // Send after health check
    final x3Send = await send('X3: post-healthcheck msg');
    _signals.writeJson('x3_alice_sent', {
      'healthCheckMs': x3Sw.elapsedMilliseconds,
      ..._timingJson(x3Send),
    });
    await _signals.waitForSignal('x3_verified');

    // ── Done ──
    await _signals.waitForSignal('all_done');
    print('\n[ALICE] All scenarios complete');

    // Teardown
    chatListener.dispose();
    await p2pService.stopNode();
    p2pService.dispose();
    bridge.dispose();
    await db.close();
    await deleteTestDatabase(_dbName);
    _signals.writeSignal('alice_done');
  });
}

// ===========================================================================
//  BOB (receiver)
// ===========================================================================

void _runBob() {
  testWidgets('Bob — Routing Smoke S1–S8', (tester) async {
    print('\n${'═' * 60}');
    print('  BOB HARNESS — ROUTING SMOKE E2E');
    print('${'═' * 60}\n');

    // ── Stack setup (identical to Alice) ──
    final keyStore = FakeSecureKeyStore();
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
      dbLoadLatestMessageForContact: (p) =>
          dbLoadLatestMessageForContact(db, p),
      dbUpdateMessageStatus: (id, s) => dbUpdateMessageStatus(db, id, s),
      dbLoadMessage: (id) => dbLoadMessage(db, id),
      dbExistsMessageByContent:
          (contactPeerId, senderPeerId, text, timestamp) =>
              dbExistsMessageByContent(
                db,
                contactPeerId,
                senderPeerId,
                text,
                timestamp,
              ),
      dbCountMessagesForContact: (p) => dbCountMessagesForContact(db, p),
      dbMarkConversationAsRead: (p) => dbMarkConversationAsRead(db, p),
      dbCountUnreadForContact: (p) => dbCountUnreadForContact(db, p),
      dbCountTotalUnread: () => dbCountTotalUnread(db),
      dbCountTotalUnreadExcludingArchived: () =>
          dbCountTotalUnreadExcludingArchived(db),
      dbDeleteMessagesForContact: (p) => dbDeleteMessagesForContact(db, p),
      dbDeleteMessage: (id) => dbDeleteMessage(db, id),
      dbLoadMessagesPage: (p, {limit = 50, beforeTimestamp}) =>
          dbLoadMessagesPage(
            db,
            p,
            limit: limit,
            beforeTimestamp: beforeTimestamp,
          ),
      dbLoadFailedOutgoingMessages: () => dbLoadFailedOutgoingMessages(db),
      dbLoadUnackedOutgoingMessages: ({required olderThan, limit = 50}) =>
          dbLoadUnackedOutgoingMessages(db, olderThan: olderThan, limit: limit),
      dbLoadConversationThreadSummaries: (ids) =>
          dbLoadConversationThreadSummaries(db, ids),
      dbRecoverStuckSendingMessages:
          ({required DateTime olderThan, int limit = 50}) =>
              dbRecoverStuckSendingMessages(
                db,
                olderThan: olderThan,
                limit: limit,
              ),
      dbUpdateWireEnvelope: (id, we) => dbUpdateWireEnvelope(db, id, we),
      dbLoadStuckSendingOutgoingMessages:
          ({required DateTime olderThan, int limit = 50}) =>
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

    // Generate identity
    final genResp = await bridge.send(
      jsonEncode({'cmd': 'identity.generate', 'payload': {}}),
    );
    final genResult = jsonDecode(genResp) as Map<String, dynamic>;
    if (genResult['ok'] != true) throw StateError('identity.generate failed');
    final identity = genResult['identity'] as Map<String, dynamic>;
    final ownPeerId = identity['peerId'] as String;
    final ownPrivateKey = identity['privateKey'] as String;
    final ownPublicKey = identity['publicKey'] as String;

    final mlkemResp = await bridge.send(
      jsonEncode({'cmd': 'mlkem.keygen', 'payload': {}}),
    );
    final mlkemResult = jsonDecode(mlkemResp) as Map<String, dynamic>;
    final ownMlKemPk = mlkemResult['ok'] == true
        ? mlkemResult['publicKey'] as String?
        : null;
    final ownMlKemSk = mlkemResult['ok'] == true
        ? mlkemResult['secretKey'] as String?
        : null;

    print('[BOB] peerId=${ownPeerId.substring(0, 20)}...');

    // Start P2P node
    final p2pService = P2PServiceImpl(
      bridge: bridge,
      inboxStagingRepository: InMemoryInboxStagingRepository(),
    );
    var started = await p2pService.startNode(ownPrivateKey, ownPeerId);
    if (!started) throw StateError('P2P node failed to start');
    await waitForOnline(p2pService, timeout: const Duration(seconds: 60));

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
    _signals.writeJson('bob_identity.json', {
      'peerId': ownPeerId,
      'publicKey': ownPublicKey,
      'mlKemPublicKey': ownMlKemPk,
    });
    print('[BOB] Identity fixture written, reading Alice...');

    // Alice's identity should already exist (she launched first)
    final aliceFixture = await _signals.waitForJson('alice_identity.json');
    final alicePeerId = aliceFixture['peerId'] as String;
    final aliceMlKemPk = aliceFixture['mlKemPublicKey'] as String?;

    await contactRepo.addContact(
      ContactModel(
        peerId: alicePeerId,
        publicKey: aliceFixture['publicKey'] as String,
        rendezvous: '/dns4/relay/tcp/443/p2p/relay',
        username: 'Alice',
        signature: 'sig-alice',
        scannedAt: DateTime.now().toUtc().toIso8601String(),
        mlKemPublicKey: aliceMlKemPk,
      ),
    );
    print('[BOB] Alice added as contact');

    // Signal ready
    _signals.writeSignal('bob_ready');
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
      final timings = events
          .where((e) => e['event'] == 'CHAT_MSG_SEND_TIMING')
          .toList();
      if (timings.isEmpty) return null;
      final d = timings.first['details'] as Map<String, dynamic>;
      return {
        'sendMs': d['elapsedMs'],
        'sendPath': d['sendPath'],
        'outcome': d['outcome'],
      };
    }

    // ════════════════════════════════════════════════════════════════
    //  S1: Cold send — Bob receives
    // ════════════════════════════════════════════════════════════════
    print('\n--- S1: Waiting for cold send ---');
    final s1 = await waitForMessage(
      'S1:',
      timeout: const Duration(seconds: 60),
    );
    print(
      '[BOB] S1: ${s1 != null ? 'received (e2e=${s1['e2eMs']}ms)' : 'TIMEOUT'}',
    );
    _signals.writeJson('s1_bob_received', s1 ?? {'e2eMs': -1});

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
    _signals.writeJson('s2_bob_received', {
      'timings': s2Timings,
      'count': s2Timings.length,
    });

    // ════════════════════════════════════════════════════════════════
    //  S3: Bob offline → restart → inbox drain → delivery
    // ════════════════════════════════════════════════════════════════
    print('\n--- S3: Going offline ---');
    await _signals.waitForSignal('s3_bob_stop');
    chatListener.dispose();
    await p2pService.stopNode();
    _signals.writeSignal('s3_bob_stopped');
    print('[BOB] S3: Node stopped');

    // Wait for restart signal
    await _signals.waitForSignal('s3_bob_restart');
    print('[BOB] S3: Restarting node...');
    started = await p2pService.startNode(ownPrivateKey, ownPeerId);
    if (!started) throw StateError('S3: restart failed');
    await waitForOnline(p2pService, timeout: const Duration(seconds: 60));

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
        print(
          '[SMOKE] inbox_delivery_ms=${d['deliveryMs']} messageId=${d['messageId']}',
        );
      }
    }

    final s3 = await waitForMessage(
      'S3:',
      timeout: const Duration(seconds: 90),
    );
    print(
      '[BOB] S3: ${s3 != null ? 'received via inbox (e2e=${s3['e2eMs']}ms)' : 'TIMEOUT'}',
    );
    _signals.writeJson('s3_bob_received', s3 ?? {'e2eMs': -1});

    // ════════════════════════════════════════════════════════════════
    //  S4: Reconnect — Bob receives
    // ════════════════════════════════════════════════════════════════
    print('\n--- S4: Waiting for reconnect message ---');
    final s4 = await waitForMessage(
      'S4:',
      timeout: const Duration(seconds: 60),
    );
    print(
      '[BOB] S4: ${s4 != null ? 'received (e2e=${s4['e2eMs']}ms)' : 'TIMEOUT'}',
    );
    _signals.writeJson('s4_bob_received', s4 ?? {'e2eMs': -1});

    // ════════════════════════════════════════════════════════════════
    //  S5: Bidirectional — Bob sends + receives
    // ════════════════════════════════════════════════════════════════
    print('\n--- S5: Bidirectional ---');
    // Wait for Alice msg1
    await _signals.waitForSignal('s5_alice_msg1');
    final s5m1 = await waitForMessage('S5: alice msg 1');
    print('[BOB] S5: received alice msg 1: ${s5m1 != null}');

    // Bob sends msg2
    final s5b2 = await sendFromBob('S5: bob msg 2');
    _signals.writeJson('s5_bob_msg2', s5b2 ?? {});

    // Wait for Alice msg3
    await _signals.waitForSignal('s5_alice_msg3');
    final s5m3 = await waitForMessage('S5: alice msg 3');
    print('[BOB] S5: received alice msg 3: ${s5m3 != null}');

    // Bob sends msg4
    final s5b4 = await sendFromBob('S5: bob msg 4');
    _signals.writeJson('s5_bob_msg4', s5b4 ?? {});

    // Wait for Alice msg5
    await _signals.waitForSignal('s5_alice_msg5');
    final s5m5 = await waitForMessage('S5: alice msg 5');
    print('[BOB] S5: received alice msg 5: ${s5m5 != null}');

    _signals.writeJson('s5_bob_complete', {
      'received': [s5m1, s5m3, s5m5],
      'sent': [s5b2, s5b4],
    });

    // ════════════════════════════════════════════════════════════════
    //  S6: Stale connection — Bob killed abruptly
    // ════════════════════════════════════════════════════════════════
    print('\n--- S6: Stale kill ---');
    await _signals.waitForSignal('s6_bob_kill');
    chatListener.dispose();
    await p2pService.stopNode();
    _signals.writeSignal('s6_bob_killed');
    print('[BOB] S6: Killed');

    await _signals.waitForSignal('s6_bob_restart');
    started = await p2pService.startNode(ownPrivateKey, ownPeerId);
    if (!started) throw StateError('S6: restart failed');
    await waitForOnline(p2pService, timeout: const Duration(seconds: 60));
    chatListener = ChatMessageListener(
      chatMessageStream: p2pService.messageStream,
      messageRepo: messageRepo,
      contactRepo: contactRepo,
      bridge: bridge,
      getOwnMlKemSecretKey: () async => ownMlKemSk,
    );
    chatListener.start();
    _signals.writeSignal('s6_bob_restarted');

    final s6 = await waitForMessage('S6:');
    print(
      '[BOB] S6: ${s6 != null ? 'received (e2e=${s6['e2eMs']}ms)' : 'TIMEOUT'}',
    );
    _signals.writeJson('s6_bob_received', s6 ?? {'e2eMs': -1});

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
      final m = await waitForMessage(
        'S8: msg$i',
        timeout: const Duration(seconds: 30),
      );
      s8Timeline.add({'n': i, 'role': 'recv', ...?m});
      print('[BOB] S8: received msg$i: ${m != null}');
    }

    // Phase 3 [OFFLINE]
    await _signals.waitForSignal('s8_bob_stop');
    chatListener.dispose();
    await p2pService.stopNode();
    _signals.writeSignal('s8_bob_stopped');
    print('[BOB] S8: stopped for offline phase');

    // Phase 4 [RESTART]
    await _signals.waitForSignal('s8_bob_restart');
    started = await p2pService.startNode(ownPrivateKey, ownPeerId);
    if (!started) throw StateError('S8: restart failed');
    await waitForOnline(p2pService, timeout: const Duration(seconds: 60));
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
    _signals.writeSignal('s8_bob_restarted');

    // Inbox drain can lag or remain pending even when restart itself succeeded.
    // Don't block the rest of the lifecycle behind this best-effort receive.
    final msg5 = await waitForMessage(
      'S8: msg5',
      timeout: const Duration(seconds: 15),
    );
    s8Timeline.add({
      'n': 5,
      'role': 'recv_inbox',
      if (msg5 == null) 'pending': true,
      ...?msg5,
    });
    print('[BOB] S8: received msg5 via inbox: ${msg5 != null}');

    // Receive msg6 (reconnect)
    final msg6 = await waitForMessage(
      'S8: msg6',
      timeout: const Duration(seconds: 30),
    );
    s8Timeline.add({'n': 6, 'role': 'recv', ...?msg6});

    // Phase 5 [BIDIR]: Bob sends msg7
    final s8b7 = await sendFromBob('S8: bob msg7');
    s8Timeline.add({'n': 7, 'role': 'send', ...?s8b7});
    _signals.writeJson('s8_bob_msg7', s8b7 ?? {});

    // Phase 6: Receive msg8–msg10
    for (var i = 8; i <= 10; i++) {
      final m = await waitForMessage(
        'S8: msg$i',
        timeout: const Duration(seconds: 30),
      );
      s8Timeline.add({'n': i, 'role': 'recv', ...?m});
    }

    _signals.writeJson('s8_bob_complete', {'timeline': s8Timeline});
    print('[BOB] S8: lifecycle complete');

    // ════════════════════════════════════════════════════════════════
    //  S9: Batch inbox drain (5 messages while Bob offline)
    // ════════════════════════════════════════════════════════════════
    print('\n--- S9: Batch inbox drain ---');
    await _signals.waitForSignal('s9_bob_stop');
    chatListener.dispose();
    await p2pService.stopNode();
    _signals.writeSignal('s9_bob_stopped');
    print('[BOB] S9: stopped');

    await _signals.waitForSignal('s9_bob_restart');
    started = await p2pService.startNode(ownPrivateKey, ownPeerId);
    if (!started) throw StateError('S9: restart failed');
    await waitForOnline(p2pService, timeout: const Duration(seconds: 60));
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
        print(
          '[SMOKE] inbox_delivery_ms=${d['deliveryMs']} messageId=${d['messageId']}',
        );
      }
    }

    // Try to receive messages from inbox drain (15s each — best effort)
    final s9Received = <Map<String, dynamic>>[];
    for (var i = 1; i <= 5; i++) {
      final m = await waitForMessage(
        'S9: batch inbox msg $i',
        timeout: const Duration(seconds: 15),
      );
      if (m != null) s9Received.add(m);
      print('[BOB] S9: received msg $i: ${m != null}');
      if (m == null) break; // stop early if drain isn't delivering
    }
    _signals.writeJson('s9_bob_received', {
      'count': s9Received.length,
      'timings': s9Received,
    });

    // ════════════════════════════════════════════════════════════════
    //  S10: Delete-for-everyone — Bob receives deletion
    // ════════════════════════════════════════════════════════════════
    print('\n--- S10: Waiting for message + deletion ---');
    final s10Msg = await waitForMessage(
      'S10:',
      timeout: const Duration(seconds: 30),
    );
    print('[BOB] S10: received msg: ${s10Msg != null}');
    _signals.writeSignal('s10_bob_received_msg');
    // The delete tombstone will arrive as a new message — wait for message count to change
    // or for the message to be marked deleted. For now, just signal received.

    // ════════════════════════════════════════════════════════════════
    //  S13: ACK under load — Bob receives 10 rapid messages
    // ════════════════════════════════════════════════════════════════
    print('\n--- S13: Receiving 10 rapid messages ---');
    final s13Received = <Map<String, dynamic>>[];
    for (var i = 1; i <= 10; i++) {
      final m = await waitForMessage(
        'S13: rapid msg $i',
        timeout: const Duration(seconds: 15),
      );
      if (m != null) s13Received.add(m);
    }
    print('[BOB] S13: received ${s13Received.length}/10');
    _signals.writeJson('s13_bob_received', {
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
    _signals.writeJson('s14_bob_received', s14Msg ?? {'e2eMs': -1});

    // ════════════════════════════════════════════════════════════════
    //  S15: Relay probe — Bob restarts without rendezvous (brief window)
    // ════════════════════════════════════════════════════════════════
    print('\n--- S15: Relay probe ---');
    await _signals.waitForSignal('s15_go');
    // Stop and restart to create a window where Bob is on relay but
    // not yet registered on rendezvous
    chatListener.dispose();
    await p2pService.stopNode();
    started = await p2pService.startNode(ownPrivateKey, ownPeerId);
    if (!started) throw StateError('S15: restart failed');
    // Signal immediately — before rendezvous registration completes
    _signals.writeSignal('s15_bob_unregistered');
    // Now wait for online (rendezvous registers in background)
    await waitForOnline(p2pService, timeout: const Duration(seconds: 60));
    chatListener = ChatMessageListener(
      chatMessageStream: p2pService.messageStream,
      messageRepo: messageRepo,
      contactRepo: contactRepo,
      bridge: bridge,
      getOwnMlKemSecretKey: () async => ownMlKemSk,
    );
    chatListener.start();
    // Receive the relay probe message
    final s15Msg = await waitForMessage(
      'S15:',
      timeout: const Duration(seconds: 30),
    );
    print('[BOB] S15: received: ${s15Msg != null}');
    _signals.writeJson('s15_bob_received', s15Msg ?? {'e2eMs': -1});

    // ════════════════════════════════════════════════════════════════
    //  X1: Node restart timing — Bob stops + restarts
    // ════════════════════════════════════════════════════════════════
    print('\n--- X1: Both-sides restart ---');
    await _signals.waitForSignal('x1_go');
    chatListener.dispose();
    await p2pService.stopNode();
    _signals.writeSignal('x1_bob_stopped');

    await _signals.waitForSignal('x1_restart');
    final x1Sw = Stopwatch()..start();
    started = await p2pService.startNode(ownPrivateKey, ownPeerId);
    if (!started) throw StateError('X1: restart failed');
    await waitForOnline(p2pService, timeout: const Duration(seconds: 60));
    chatListener = ChatMessageListener(
      chatMessageStream: p2pService.messageStream,
      messageRepo: messageRepo,
      contactRepo: contactRepo,
      bridge: bridge,
      getOwnMlKemSecretKey: () async => ownMlKemSk,
    );
    chatListener.start();
    x1Sw.stop();
    _signals.writeJson('x1_bob_restarted', {
      'restartMs': x1Sw.elapsedMilliseconds,
    });

    // Receive post-restart message
    final x1Msg = await waitForMessage(
      'X1:',
      timeout: const Duration(seconds: 60),
    );
    print('[BOB] X1: received post-restart: ${x1Msg != null}');
    _signals.writeJson('x1_bob_received', x1Msg ?? {'e2eMs': -1});

    // ════════════════════════════════════════════════════════════════
    //  X2: Background/foreground — Bob pauses + resumes
    // ════════════════════════════════════════════════════════════════
    print('\n--- X2: Background/foreground ---');
    await _signals.waitForSignal('x2_go');
    await handleAppPaused(messageRepo: messageRepo);
    _signals.writeSignal('x2_bob_paused');

    await _signals.waitForSignal('x2_resume');
    final x2Sw = Stopwatch()..start();
    await handleAppResumed(bridge: bridge, p2pService: p2pService);
    x2Sw.stop();
    _signals.writeJson('x2_bob_resumed', {
      'resumeMs': x2Sw.elapsedMilliseconds,
    });

    final x2Msg = await waitForMessage(
      'X2:',
      timeout: const Duration(seconds: 30),
    );
    print('[BOB] X2: received post-resume: ${x2Msg != null}');
    _signals.writeJson('x2_bob_received', x2Msg ?? {'e2eMs': -1});

    // ════════════════════════════════════════════════════════════════
    //  X3: Relay failover — Bob health check + receive
    // ════════════════════════════════════════════════════════════════
    print('\n--- X3: Relay failover ---');
    await _signals.waitForSignal('x3_go');
    await p2pService.performImmediateHealthCheck();
    final x3Msg = await waitForMessage(
      'X3:',
      timeout: const Duration(seconds: 30),
    );
    print('[BOB] X3: received post-healthcheck: ${x3Msg != null}');
    _signals.writeJson('x3_bob_received', x3Msg ?? {'e2eMs': -1});

    // ── Done ──
    await _signals.waitForSignal('all_done');
    print('\n[BOB] All scenarios complete');

    chatListener.dispose();
    await p2pService.stopNode();
    p2pService.dispose();
    bridge.dispose();
    await db.close();
    await deleteTestDatabase(_dbName);
    _signals.writeSignal('bob_done');
  });
}
