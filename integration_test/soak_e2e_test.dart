// Soak E2E Integration Test — Flutter Side
//
// Signal-driven soak test that coordinates with run_soak_e2e.dart orchestrator.
// The orchestrator sends commands via signal files; this test responds.
//
// Launch with orchestrator:
//   dart run integration_test/scripts/run_soak_e2e.dart -d <simulator-id>
//
// Signal protocol:
//   phase4_initial_ready → written after the Flutter harness is ready for the
//                          deterministic Phase 4 gate
//   phase4_resume_and_send → run the deterministic stale-discoverability gate
//                            and write phase4_result
//   soak_send_next     → send a message to CLI peer
//   soak_drain_inbox   → drain offline inbox
//   soak_health_check  → call handleAppResumed
//   soak_done          → exit the loop
//   soak_stats         → written by this test with current counts
//   phase4_result      → written by this test with transport/recovery evidence

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:flutter_app/core/bridge/go_bridge_client.dart';
import 'package:flutter_app/core/database/app_database_version.dart';
import 'package:flutter_app/core/database/helpers/contacts_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/messages_db_helpers.dart';
import 'package:flutter_app/core/database/production_migration_registry.dart';
import 'package:flutter_app/app/lifecycle/handle_app_resumed.dart';
import 'package:flutter_app/core/bridge/p2p_bridge_client.dart';
import 'package:flutter_app/core/services/p2p_service_impl.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/contacts/data/repositories/contact_repository_impl.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';
import 'package:flutter_app/features/conversation/application/send_chat_message_use_case.dart';
import 'package:flutter_app/features/conversation/data/repositories/message_repository_impl.dart';

import '../test/shared/fakes/in_memory_inbox_staging_repository.dart';
import '_support/signal_files.dart';

// ---------------------------------------------------------------------------
// Multi-relay closure gate
// ---------------------------------------------------------------------------

// Folded in from the deleted relay_chaos_soak_test wrapper. When
// MKNOON_REQUIRE_MULTI_RELAY=true the run asserts that at least two
// comma-separated MKNOON_RELAY_ADDRESSES entries are configured so the relay
// churn path is actually exercised. The gate defaults OFF — when it is unset
// the single-relay default behavior of this source test is unchanged.
const _configuredRelayAddresses = String.fromEnvironment(
  'MKNOON_RELAY_ADDRESSES',
  defaultValue: '',
);
const _requireConfiguredMultiRelayAddresses = bool.fromEnvironment(
  'MKNOON_REQUIRE_MULTI_RELAY',
);

bool _hasConfiguredMultiRelayAddresses() {
  final addresses = _configuredRelayAddresses
      .split(',')
      .map((entry) => entry.trim())
      .where((entry) => entry.isNotEmpty)
      .toList(growable: false);
  return addresses.length >= 2;
}

// ---------------------------------------------------------------------------
// Signal helpers
// ---------------------------------------------------------------------------

/// Base directory for signal files — matches the orchestrator's paths.
String _signalDir() {
  const configuredDir = String.fromEnvironment(
    'E2E_SIGNAL_DIR',
    defaultValue: '',
  );
  if (configuredDir.isNotEmpty) return configuredDir;
  final envDir = Platform.environment['E2E_SIGNAL_DIR'];
  if (envDir != null) return envDir;
  return '${Directory.systemTemp.path}/e2e_soak_signals';
}

/// Canonical flat signal coordinator for the soak harness side. Produces
/// `<_signalDir()>/<name>`, byte-identical to the old inline `_signalExists`
/// / `_readSignal` / `_writeSignal` helpers (no prefix, no runId).
final SignalDir _signals = SignalDir.flat(_signalDir(), role: 'SoakHarness');

// ---------------------------------------------------------------------------
// Main test
// ---------------------------------------------------------------------------

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // Multi-relay closure gate: when MKNOON_REQUIRE_MULTI_RELAY=true this run must
  // have at least two MKNOON_RELAY_ADDRESSES entries configured (the relay churn
  // path the deleted relay_chaos_soak_test wrapper used to assert). Fail closed
  // before the soak loop runs if the requirement is not met. With the gate off
  // (default) the soak test runs exactly as before.
  if (_requireConfiguredMultiRelayAddresses &&
      !_hasConfiguredMultiRelayAddresses()) {
    testWidgets('multi-relay fixture is required for this closure run', (
      _,
    ) async {
      fail(
        'MKNOON_REQUIRE_MULTI_RELAY=true requires at least two comma-separated '
        'MKNOON_RELAY_ADDRESSES entries via --dart-define.',
      );
    });
    return;
  }

  testWidgets('soak E2E — signal-driven loop', (tester) async {
    // 1. Read CLI peer fixture
    final fixtureFile = File(_signals.path('cli_peer_fixture.json'));
    if (!fixtureFile.existsSync()) {
      debugPrint(
        '[SOAK] SKIP: CLI peer fixture not found at ${fixtureFile.path}. '
        'Run with the orchestrator to exercise this test.',
      );
      return;
    }
    final fixture =
        jsonDecode(fixtureFile.readAsStringSync()) as Map<String, dynamic>;
    final cliPeerId = fixture['peerId'] as String;
    final cliPublicKey = fixture['publicKey'] as String;
    final cliMlKemPK = fixture['mlKemPublicKey'] as String?;

    // 2. Initialize local stack
    final bridge = GoBridgeClient();
    await bridge.initialize();

    final identityJson = await bridge.send(
      jsonEncode({'cmd': 'identity.generate', 'payload': {}}),
    );
    final identityResult = jsonDecode(identityJson) as Map<String, dynamic>;
    if (identityResult['ok'] != true) {
      throw StateError('identity.generate failed: $identityResult');
    }
    final identity = Map<String, dynamic>.from(
      identityResult['identity'] as Map,
    );
    final myPeerId = identity['peerId'] as String;
    final myPrivateKey = identity['privateKey'] as String;

    // Generate ML-KEM keys
    final mlKemJson = await bridge.send(
      jsonEncode({'cmd': 'mlkem.keygen', 'payload': {}}),
    );
    final mlKemResult = jsonDecode(mlKemJson) as Map<String, dynamic>;
    if (mlKemResult['ok'] != true) {
      throw StateError('mlkem.keygen failed: $mlKemResult');
    }
    final myMlKemPK = mlKemResult['publicKey'] as String;
    final myMlKemSK = mlKemResult['secretKey'] as String;

    // Open an in-memory DB with the current production schema.
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final db = await openDatabase(inMemoryDatabasePath, version: 1);
    await runProductionOnCreate(db, currentIdentityDatabaseVersion);

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
      dbExistsMessageByContent:
          (contactPeerId, senderPeerId, text, timestamp) =>
              dbExistsMessageByContent(
                db,
                contactPeerId,
                senderPeerId,
                text,
                timestamp,
              ),
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
      dbStageOutgoingOrdinaryAttempt:
          ({required expectedRow, required stagedRow, required kind}) =>
              dbStageOutgoingOrdinaryAttempt(
                db,
                expectedRow: expectedRow,
                stagedRow: stagedRow,
                kind: kind,
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

    // Start P2P node
    final p2pService = P2PServiceImpl(
      bridge: bridge,
      inboxStagingRepository: InMemoryInboxStagingRepository(),
    );
    await p2pService.startNode(myPrivateKey, myPeerId);
    final registerResult = await callP2PRendezvousRegister(
      bridge,
      namespace: 'mknoon:chat:$myPeerId',
    );
    if (registerResult['ok'] != true) {
      throw StateError(
        'rendezvous:register failed for soak peer: $registerResult',
      );
    }

    // Add CLI peer as contact
    await contactRepo.addContact(
      ContactModel(
        peerId: cliPeerId,
        publicKey: cliPublicKey,
        rendezvous: '/dns4/relay/tcp/443/p2p/relay',
        username: 'CLI-Soak-Peer',
        signature: 'sig-cli',
        scannedAt: DateTime.now().toUtc().toIso8601String(),
        mlKemPublicKey: cliMlKemPK,
      ),
    );

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
    _signals.writeSignal(
      'flutter_peer_fixture.json',
      content: jsonEncode({
        'peerId': myPeerId,
        'publicKey': identity['publicKey'],
        'mlKemPublicKey': myMlKemPK,
      }),
    );
    _signals.writeSignal('phase4_initial_ready', content: 'ready');

    Future<Map<String, dynamic>> buildStats({
      required int sentCount,
      required int drainCount,
      required int healthCheckCount,
      required int loopCount,
    }) async {
      final messages = await messageRepo.getMessagesForContact(cliPeerId);
      final outgoing = messages.where((m) => !m.isIncoming).toList();
      final incoming = messages.where((m) => m.isIncoming).toList();
      final latestOutgoing = outgoing.isNotEmpty ? outgoing.last : null;
      return {
        'sentCount': sentCount,
        'messageCount': messages.length,
        'incomingCount': incoming.length,
        'outgoingCount': outgoing.length,
        'drainCount': drainCount,
        'healthCheckCount': healthCheckCount,
        'loopCount': loopCount,
        'circuitCount': p2pService.currentState.circuitAddresses.length,
        'lastRecoveryMethod': p2pService.lastRecoveryMethod,
        'lastOutgoingTransport': latestOutgoing?.transport,
        'lastOutgoingStatus': latestOutgoing?.status,
        'lastOutgoingText': latestOutgoing?.text,
      };
    }

    // 3. Signal-driven loop
    int sentCount = 0;
    int drainCount = 0;
    int healthCheckCount = 0;
    int loopCount = 0;

    while (!_signals.exists('soak_done')) {
      loopCount++;

      if (_signals.exists('phase4_resume_and_send')) {
        final requestRaw = _signals.read('phase4_resume_and_send');
        _signals.delete('phase4_resume_and_send');

        final request = requestRaw == null || requestRaw.isEmpty
            ? const <String, dynamic>{}
            : jsonDecode(requestRaw) as Map<String, dynamic>;
        final phase4Text =
            request['text'] as String? ??
            'phase4-live-after-stale-discoverability';

        final discoveredBeforeResume = await p2pService.discoverPeer(cliPeerId);
        final bridgeOk = await handleAppResumed(
          bridge: bridge,
          p2pService: p2pService,
        );
        final discoveredAfterResume = await p2pService.discoverPeer(cliPeerId);

        final (sendResult, returnedMessage) = await sendChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: cliPeerId,
          text: phase4Text,
          senderPeerId: myPeerId,
          senderUsername: 'FlutterSoak',
          bridge: bridge,
          recipientMlKemPublicKey: cliMlKemPK,
        );

        final stored = await messageRepo.getMessagesForContact(cliPeerId);
        final matching = stored
            .where((m) => !m.isIncoming && m.text == phase4Text)
            .toList();
        final persisted = matching.isNotEmpty ? matching.last : null;

        _signals.writeSignal(
          'phase4_result',
          content: jsonEncode({
            'text': phase4Text,
            'discoverMissBeforeResume': discoveredBeforeResume == null,
            'discoverMissAfterResume': discoveredAfterResume == null,
            'bridgeOk': bridgeOk,
            'sendResult': sendResult.name,
            'returnedTransport': returnedMessage?.transport,
            'persistedTransport': persisted?.transport,
            'persistedStatus': persisted?.status,
            'livePath': persisted != null && persisted.transport != 'inbox',
            'circuitCount': p2pService.currentState.circuitAddresses.length,
            'lastRecoveryMethod': p2pService.lastRecoveryMethod,
          }),
        );
      }

      // Check for send signal
      if (_signals.exists('soak_send_next')) {
        _signals.delete('soak_send_next');
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
      if (_signals.exists('soak_drain_inbox')) {
        _signals.delete('soak_drain_inbox');
        drainCount++;
        await p2pService.drainOfflineInbox();
      }

      // Check for health check signal
      if (_signals.exists('soak_health_check')) {
        _signals.delete('soak_health_check');
        healthCheckCount++;
        await handleAppResumed(bridge: bridge, p2pService: p2pService);
      }

      // Write stats periodically (every 10 loops)
      if (loopCount % 10 == 0) {
        final stats = await buildStats(
          sentCount: sentCount,
          drainCount: drainCount,
          healthCheckCount: healthCheckCount,
          loopCount: loopCount,
        );
        _signals.writeSignal('soak_stats', content: jsonEncode(stats));
      }

      await Future.delayed(const Duration(milliseconds: 500));
    }

    // 4. Final stats
    final finalStats = await buildStats(
      sentCount: sentCount,
      drainCount: drainCount,
      healthCheckCount: healthCheckCount,
      loopCount: loopCount,
    );
    _signals.writeSignal('soak_final_stats', content: jsonEncode(finalStats));

    // Cleanup
    listener.dispose();
    p2pService.dispose();
    await db.close();
  }, timeout: const Timeout(Duration(minutes: 60)));
}
