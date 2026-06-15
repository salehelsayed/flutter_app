// Transport Census Harness — TWO physical devices, fresh identity per run.
//
// STATUS (2026-05-30): REWORKED for two-device operation with NO cross-device
// filesystem and NO dependency on persisted onboarding. Compiles clean
// (`flutter analyze`); device-validation pending.
//
// ARCHITECTURE (solves the 3 walls of the previous scaffold):
//   1. FRESH identity per run on BOTH devices — generated in-harness and saved
//      to a FRESH per-role test DB (E2E_DB_NAME). The `flutter test` post-run
//      uninstall therefore wipes nothing we depend on (the previous design
//      reused the device's onboarded production identity.db; uninstall killed
//      it).
//   2. ONE-DIRECTION stdout->dart-define exchange. The RECEIVER prints its
//      fresh identity to STDOUT; the orchestrator (on the host) captures that
//      line and passes it to the SENDER via --dart-define=CENSUS_PEER_JSON.
//      No /tmp, no device files, no adb/devicectl push.
//   3. Transport-level delivery/ack is a Go-node concern, so the RECEIVER does
//      NOT need the SENDER as a contact for the sender's census to be correct.
//      Only the SENDER adds the receiver as a contact (to route the send).
//
// Roles are selected by the CENSUS_ROLE dart-define (sender|receiver). Both
// roles build the SAME fresh stack; only the post-setup behaviour differs.
//
// Launch via the orchestrator:
//   bash scripts/run_transport_census.sh \
//     --condition A_cold --n 50 --cold true \
//     --sender-device <id> --receiver-device <id>
//
// dart-define knobs (all compile-time):
//   CENSUS_ROLE             'sender' | 'receiver' (required)
//   CENSUS_CONDITION        label string, e.g. A_cold / B_cross (recorded only)
//   CENSUS_N                int, default 50 — number of sends
//   CENSUS_COLD             bool, default true — disconnect before each send
//   CENSUS_SEND_INTERVAL_MS int, default 2500 — pacing between sends
//   CENSUS_PEER_JSON        sender only — compact JSON of the receiver's fresh
//                           identity: {peerId, publicKey, mlKemPublicKey,
//                           rendezvous}
//   E2E_DB_NAME             per-role fresh DB file name
//   MKNOON_RELAY_ADDRESSES  pass-through to the stack (bridge reads it itself)

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:flutter_app/core/bridge/go_bridge_client.dart';
import 'package:flutter_app/core/bridge/p2p_bridge_client.dart';
import 'package:flutter_app/core/database/helpers/contacts_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/identity_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/messages_db_helpers.dart';
import 'package:flutter_app/core/debug/transport_metrics.dart';
import 'package:flutter_app/core/services/p2p_service_impl.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository_impl.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';
import 'package:flutter_app/features/conversation/application/send_chat_message_use_case.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository_impl.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository_impl.dart';

import '../test/shared/fakes/in_memory_inbox_staging_repository.dart';
import '_support/fake_secure_key_store.dart' show FakeSecureKeyStore;
import '_support/test_db_seeder.dart';

// ---------------------------------------------------------------------------
// Fresh test DB version — mirrors transport_e2e_test.dart (version 44 +
// migration list). KEEP IN SYNC with that file: each run creates a brand-new
// per-role DB so onCreate always fires with the full migration sequence.
// ---------------------------------------------------------------------------
const int _kTestDbVersion = 77;

// The rendezvous value transport_e2e_test uses when adding a contact. Kept
// identical so the contact-add shape matches the validated e2e path.
const String _kRendezvous = '/dns4/relay/tcp/443/p2p/relay';

// ---------------------------------------------------------------------------
// dart-define knobs
// ---------------------------------------------------------------------------

const String _role = String.fromEnvironment(
  'CENSUS_ROLE',
  defaultValue: '',
);
const String _condition = String.fromEnvironment(
  'CENSUS_CONDITION',
  defaultValue: 'unspecified',
);
const int _sendCount = int.fromEnvironment('CENSUS_N', defaultValue: 50);
const bool _cold = bool.fromEnvironment('CENSUS_COLD', defaultValue: true);
const int _sendIntervalMs = int.fromEnvironment(
  'CENSUS_SEND_INTERVAL_MS',
  defaultValue: 2500,
);
const String _peerJson = String.fromEnvironment(
  'CENSUS_PEER_JSON',
  defaultValue: '',
);
// Preferred channel: base64 of the peer JSON. Avoids quotes/spaces in the
// dart-define value (raw JSON with `"` breaks dart-define/Xcode arg handling).
const String _peerB64 = String.fromEnvironment(
  'CENSUS_PEER_B64',
  defaultValue: '',
);

/// Resolves the receiver identity JSON from either the base64 channel
/// (preferred) or the raw JSON channel.
String _resolvePeerJson() {
  if (_peerB64.trim().isNotEmpty) {
    return utf8.decode(base64.decode(_peerB64.trim()));
  }
  return _peerJson;
}
const String _dbName = String.fromEnvironment(
  'E2E_DB_NAME',
  defaultValue: 'census_default.db',
);
const String _relayAddresses = String.fromEnvironment(
  'MKNOON_RELAY_ADDRESSES',
  defaultValue: '',
);

String _truncate(String s, [int n = 20]) =>
    s.length > n ? '${s.substring(0, n)}...' : s;

void _log(String msg) {
  // ignore: avoid_print
  print('[CENSUS] $msg');
}

// ---------------------------------------------------------------------------
// Fresh stack (both roles build this).
// ---------------------------------------------------------------------------

class _Stack {
  final dynamic db;
  final GoBridgeClient bridge;
  final P2PServiceImpl p2pService;
  final ContactRepositoryImpl contactRepo;
  final MessageRepositoryImpl messageRepo;
  final ChatMessageListener chatListener;
  final TransportMetrics tm;
  final String ownPeerId;
  final String ownPublicKey;
  final String? ownMlKemPublicKey;

  _Stack({
    required this.db,
    required this.bridge,
    required this.p2pService,
    required this.contactRepo,
    required this.messageRepo,
    required this.chatListener,
    required this.tm,
    required this.ownPeerId,
    required this.ownPublicKey,
    required this.ownMlKemPublicKey,
  });

  Future<void> teardown() async {
    try {
      chatListener.dispose();
    } catch (_) {}
    try {
      await p2pService.stopNode();
    } catch (_) {}
    try {
      p2pService.dispose();
    } catch (_) {}
    try {
      bridge.dispose();
    } catch (_) {}
    try {
      await db.close();
    } catch (_) {}
    _log('Cleanup complete');
  }
}

Future<_Stack> _buildFreshStack() async {
  final secureKeyStore = FakeSecureKeyStore();
  final db = await openE2EDatabase(
    secureKeyStore: secureKeyStore,
    dbName: _dbName,
    version: _kTestDbVersion,
  );
  _log('Fresh test DB opened (name=$_dbName version=$_kTestDbVersion)');

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
    dbRecoverStuckSendingMessages:
        ({required DateTime olderThan, int limit = 50}) =>
            dbRecoverStuckSendingMessages(
              db,
              olderThan: olderThan,
              limit: limit,
            ),
    dbUpdateWireEnvelope: (id, wireEnvelope) =>
        dbUpdateWireEnvelope(db, id, wireEnvelope),
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

  final bridge = GoBridgeClient();
  await bridge.initialize();
  _log('Bridge initialized (relay="$_relayAddresses")');

  // Generate a FRESH identity for this run.
  final genResponse = await bridge.send(
    jsonEncode({'cmd': 'identity.generate', 'payload': {}}),
  );
  final genResult = jsonDecode(genResponse) as Map<String, dynamic>;
  if (genResult['ok'] != true) {
    throw StateError('identity.generate failed: $genResult');
  }
  final identityMap = genResult['identity'] as Map<String, dynamic>;
  final ownPeerId = identityMap['peerId'] as String;
  final ownPublicKey = identityMap['publicKey'] as String;
  final ownPrivateKey = identityMap['privateKey'] as String;
  final ownMnemonic = identityMap['mnemonic12'] as String? ?? '';
  _log('Fresh identity: ${_truncate(ownPeerId)}');

  // Generate ML-KEM keys.
  final mlkemResponse = await bridge.send(
    jsonEncode({'cmd': 'mlkem.keygen', 'payload': {}}),
  );
  final mlkemResult = jsonDecode(mlkemResponse) as Map<String, dynamic>;
  String? ownMlKemPublicKey;
  String? ownMlKemSecretKey;
  if (mlkemResult['ok'] == true) {
    ownMlKemPublicKey = mlkemResult['publicKey'] as String?;
    ownMlKemSecretKey = mlkemResult['secretKey'] as String?;
    _log('ML-KEM keys generated');
  }

  // Persist the fresh identity to the fresh DB (mirrors normal onboarding).
  final nowIso = DateTime.now().toUtc().toIso8601String();
  await identityRepo.saveIdentity(
    IdentityModel(
      peerId: ownPeerId,
      publicKey: ownPublicKey,
      privateKey: ownPrivateKey,
      mnemonic12: ownMnemonic,
      mlKemPublicKey: ownMlKemPublicKey,
      mlKemSecretKey: ownMlKemSecretKey,
      username: _role == 'sender' ? 'CensusSender' : 'CensusReceiver',
      createdAt: nowIso,
      updatedAt: nowIso,
    ),
  );
  _log('Fresh identity saved');

  final tm = TransportMetrics();
  final p2pService = P2PServiceImpl(
    bridge: bridge,
    inboxStagingRepository: InMemoryInboxStagingRepository(),
    transportMetrics: tm,
  );

  _log('Starting P2P node...');
  final started = await p2pService.startNode(ownPrivateKey, ownPeerId);
  if (!started) {
    throw StateError('P2P node failed to start');
  }
  _log('P2P node started');

  final chatListener = ChatMessageListener(
    chatMessageStream: p2pService.messageStream,
    messageRepo: messageRepo,
    contactRepo: contactRepo,
    bridge: bridge,
    getOwnMlKemSecretKey: () async => ownMlKemSecretKey,
  );
  chatListener.start();
  _log('ChatMessageListener started');

  return _Stack(
    db: db,
    bridge: bridge,
    p2pService: p2pService,
    contactRepo: contactRepo,
    messageRepo: messageRepo,
    chatListener: chatListener,
    tm: tm,
    ownPeerId: ownPeerId,
    ownPublicKey: ownPublicKey,
    ownMlKemPublicKey: ownMlKemPublicKey,
  );
}

// ---------------------------------------------------------------------------
// Census dump → structured map (sender vantage). Reused verbatim from the
// previous scaffold.
// ---------------------------------------------------------------------------

Map<String, dynamic> _censusToJson(TransportMetrics tm) {
  final latency = tm.latencyByTransport();
  return {
    'totalTransportSamples': tm.totalTransportSamples,
    'transportMix': tm.transportMix(),
    'rungDistribution': tm.rungDistribution(),
    'attemptCounts': tm.attemptCounts(),
    'attemptFailureCounts': tm.attemptFailureCounts(),
    // delivered-per-leg = attempts - failures (the per-leg success count).
    'attemptDelivered': {
      for (final leg in kSendAttemptLegs)
        leg: (tm.attemptCounts()[leg] ?? 0) -
            (tm.attemptFailureCounts()[leg] ?? 0),
    },
    'latencyByTransport': {
      for (final entry in latency.entries)
        entry.key: {
          'n': entry.value.sampleCount,
          'medianMs': entry.value.medianMs,
          'p95Ms': entry.value.p95Ms,
        },
    },
    'holePunchAttempts': tm.holePunchAttempts,
    'holePunchSuccesses': tm.holePunchSuccesses,
    'holePunchFailures': tm.holePunchFailures,
    'relayToDirectUpgrades': tm.relayToDirectUpgrades,
    'baselineReport': tm.baselineReport(),
  };
}

/// Prints the operator-facing, clearly-delimited census block to STDOUT.
void _printCensusBlock(
  TransportMetrics tm, {
  required String vantageLabel,
  required String targetPeerId,
  required String senderUsername,
  required int delivered,
  required int failed,
}) {
  final census = _censusToJson(tm);
  final buf = StringBuffer();
  buf.writeln('===CENSUS_BEGIN===');
  buf.writeln('vantage: $vantageLabel');
  buf.writeln('condition: $_condition');
  buf.writeln('N (requested): $_sendCount');
  buf.writeln('cold: $_cold');
  buf.writeln('sendIntervalMs: $_sendIntervalMs');
  buf.writeln('relayAddresses: $_relayAddresses');
  buf.writeln('sender (self) username: $senderUsername');
  buf.writeln('targetPeerId: ${_truncate(targetPeerId)}');
  buf.writeln('sends delivered/failed: $delivered/$failed');
  buf.writeln('--- transport census (SENDER vantage — count at sender) ---');
  buf.writeln('totalTransportSamples: ${census['totalTransportSamples']}');
  buf.writeln('transportMix: ${census['transportMix']}');
  buf.writeln('rungDistribution: ${census['rungDistribution']}');
  buf.writeln('attemptCounts (tried): ${census['attemptCounts']}');
  buf.writeln('attemptFailureCounts: ${census['attemptFailureCounts']}');
  buf.writeln('attemptDelivered (tried-failed): ${census['attemptDelivered']}');
  buf.writeln('holePunch attempt/success/fail: '
      '${census['holePunchAttempts']}/${census['holePunchSuccesses']}/'
      '${census['holePunchFailures']}');
  buf.writeln('relayToDirectUpgrades: ${census['relayToDirectUpgrades']}');
  buf.writeln('--- latency by transport (median/p95/n) ---');
  final lat = census['latencyByTransport'] as Map<String, dynamic>;
  for (final entry in lat.entries) {
    final v = entry.value as Map<String, dynamic>;
    buf.writeln(
      '${entry.key}: median=${v['medianMs']}ms p95=${v['p95Ms']}ms n=${v['n']}',
    );
  }
  buf.writeln('--- baselineReport ---');
  buf.writeln(census['baselineReport']);
  buf.writeln('===CENSUS_END===');
  // ignore: avoid_print
  print(buf.toString());
}

// ---------------------------------------------------------------------------
// RECEIVER role.
// ---------------------------------------------------------------------------

Future<void> _runReceiver(_Stack stack) async {
  // 1. Announce our fresh identity on STDOUT for the orchestrator to capture.
  final identity = {
    'peerId': stack.ownPeerId,
    'publicKey': stack.ownPublicKey,
    'mlKemPublicKey': stack.ownMlKemPublicKey ?? '',
    'rendezvous': _kRendezvous,
  };
  // ignore: avoid_print
  print('CENSUS_PEER_IDENTITY=${jsonEncode(identity)}');
  _log('RECEIVER announced identity (${_truncate(stack.ownPeerId)})');

  // 2. Stay online for the sender's whole run + slack. CRITICAL: the sender is
  // launched AFTER this receiver announces, and its build+install+launch can
  // take several minutes BEFORE it sends a single message — that whole window
  // counts against this TTL. So the TTL must cover (sender build budget) +
  // (send loop) + slack, not just the send loop. The orchestrator kills this
  // receiver via its EXIT trap as soon as the sender finishes, so erring long
  // is free; erring short means the receiver dies mid-build and every send
  // falls back to relay/inbox (contaminating the census). Budget 600s for the
  // sender's cold build/launch on top of the send loop.
  const senderBuildBudgetMs = 600000;
  final waitMs = senderBuildBudgetMs + _sendCount * _sendIntervalMs + 180000;
  _log('RECEIVER staying online ~${(waitMs / 1000).round()}s');
  final deadline = DateTime.now().add(Duration(milliseconds: waitMs));
  while (DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(seconds: 10));
    try {
      await stack.p2pService.drainOfflineInbox();
    } catch (_) {}
  }

  // 3. Optional cross-check census from the receiver vantage (NOT the gate
  // number — the sender vantage is authoritative).
  _printCensusBlock(
    stack.tm,
    vantageLabel: 'RECEIVER-VANTAGE (cross-check only)',
    targetPeerId: '(none)',
    senderUsername: 'CensusReceiver',
    delivered: 0,
    failed: 0,
  );
  _log('RECEIVER done');
}

// ---------------------------------------------------------------------------
// SENDER role.
// ---------------------------------------------------------------------------

Future<void> _runSender(_Stack stack) async {
  // 1. Parse the receiver identity injected by the orchestrator (base64
  //    channel preferred; raw JSON fallback).
  final peerJson = _resolvePeerJson();
  if (peerJson.trim().isEmpty) {
    fail(
      'transport_census_harness(sender): no peer identity. The orchestrator '
      "must capture the receiver's CENSUS_PEER_IDENTITY line and pass it via "
      '--dart-define=CENSUS_PEER_B64=<base64-of-json> (or CENSUS_PEER_JSON=...).',
    );
  }
  Map<String, dynamic> peer;
  try {
    peer = jsonDecode(peerJson) as Map<String, dynamic>;
  } catch (e) {
    fail(
      'transport_census_harness(sender): peer identity is not valid JSON '
      '($e). Got: $peerJson',
    );
  }
  final peerId = peer['peerId'] as String?;
  if (peerId == null || peerId.isEmpty) {
    fail(
      'transport_census_harness(sender): peer identity missing peerId. '
      'Got: $peerJson',
    );
  }
  final peerPublicKey = (peer['publicKey'] as String?) ?? 'pk-census-peer';
  final peerMlKemRaw = peer['mlKemPublicKey'] as String?;
  final peerMlKem = (peerMlKemRaw == null || peerMlKemRaw.isEmpty)
      ? null
      : peerMlKemRaw;
  final peerRendezvous = (peer['rendezvous'] as String?) ?? _kRendezvous;
  _log('SENDER target peer: ${_truncate(peerId)} hasMlKem=${peerMlKem != null}');

  // 2. Add the receiver as a CONTACT (mirrors transport_e2e add-contact shape).
  await stack.contactRepo.addContact(
    ContactModel(
      peerId: peerId,
      publicKey: peerPublicKey,
      rendezvous: peerRendezvous,
      username: 'CensusReceiver',
      signature: 'sig-census-peer',
      scannedAt: DateTime.now().toUtc().toIso8601String(),
      mlKemPublicKey: peerMlKem,
    ),
  );
  _log('SENDER added receiver as contact');

  // 3. Readiness wait: up to 90s for send capability; fallback ~10s delay.
  final readyDeadline = DateTime.now().add(const Duration(seconds: 90));
  var sawSendCapability = false;
  while (DateTime.now().isBefore(readyDeadline)) {
    final state = stack.p2pService.currentState;
    if (state.isStarted && state.sendCapabilityReady) {
      sawSendCapability = true;
      break;
    }
    await Future<void>.delayed(const Duration(seconds: 2));
  }
  if (sawSendCapability) {
    _log('Node reports sendCapabilityReady — beginning sends');
  } else {
    _log('sendCapabilityReady not observed within 90s — warming up ~10s then '
        'proceeding anyway');
    await Future<void>.delayed(const Duration(seconds: 10));
  }

  // 4. Sender loop.
  _log('SENDER loop: N=$_sendCount cold=$_cold interval=${_sendIntervalMs}ms');
  var delivered = 0;
  var failed = 0;

  for (var i = 1; i <= _sendCount; i++) {
    // Cold-send lever: tear down the warm connection before each send so the
    // reuse fast path cannot short-circuit. Measures re-dial availability
    // GIVEN known peerstore addrs — NOT from-scratch discovery (runbook caveat).
    if (_cold) {
      try {
        await callP2PPeerDisconnect(stack.bridge, peerId: peerId);
      } catch (e) {
        _log('send $i: disconnect failed (non-fatal): $e');
      }
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }

    try {
      final (result, message) = await sendChatMessage(
        p2pService: stack.p2pService,
        messageRepo: stack.messageRepo,
        targetPeerId: peerId,
        text: 'census-$_condition-$i',
        senderPeerId: stack.ownPeerId,
        senderUsername: 'CensusSender',
        bridge: stack.bridge,
        recipientMlKemPublicKey: peerMlKem,
        transportMetrics: stack.tm,
      );
      if (result == SendChatMessageResult.success && message != null) {
        delivered++;
      } else {
        failed++;
        _log('send $i NON-SUCCESS: $result');
      }
    } catch (e) {
      failed++;
      _log('send $i threw: $e');
    }

    if (i % 10 == 0) {
      _log('progress: $i/$_sendCount sent (delivered=$delivered '
          'failed=$failed, samples=${stack.tm.totalTransportSamples})');
    }

    await Future<void>.delayed(Duration(milliseconds: _sendIntervalMs));
  }

  _log('SENDER loop done: delivered=$delivered failed=$failed');

  // 5. Dump the census (sender vantage — authoritative).
  _printCensusBlock(
    stack.tm,
    vantageLabel: 'SENDER-VANTAGE (authoritative)',
    targetPeerId: peerId,
    senderUsername: 'CensusSender',
    delivered: delivered,
    failed: failed,
  );
}

// ---------------------------------------------------------------------------
// Main test.
// ---------------------------------------------------------------------------

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  if (Platform.isLinux || Platform.isMacOS || Platform.isWindows) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  testWidgets(
    'transport census ($_role / $_condition)',
    (tester) async {
      if (_role != 'sender' && _role != 'receiver') {
        fail(
          'transport_census_harness: CENSUS_ROLE must be "sender" or '
          '"receiver" (got "$_role"). Launch via run_transport_census.sh.',
        );
      }

      final stack = await _buildFreshStack();
      try {
        if (_role == 'receiver') {
          await _runReceiver(stack);
        } else {
          await _runSender(stack);
        }
      } finally {
        await stack.teardown();
      }
    },
    // Receiver waits N*interval + 180s; sender does N sends + readiness +
    // warm-up. 40 minutes covers either role comfortably.
    timeout: const Timeout(Duration(minutes: 40)),
  );
}
