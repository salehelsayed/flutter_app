// Soak E2E Integration Test — Flutter Side
//
// Signal-driven soak test that coordinates with run_soak_e2e.dart orchestrator.
// The orchestrator sends commands via signal files; this test responds.
//
// Launch with orchestrator:
//   dart run integration_test/scripts/run_soak_e2e.dart -d <simulator-id>
//
// Signal protocol:
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

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:flutter_app/core/bridge/go_bridge_client.dart';
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
import 'package:flutter_app/core/lifecycle/handle_app_resumed.dart';
import 'package:flutter_app/core/services/p2p_service_impl.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository_impl.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';
import 'package:flutter_app/features/conversation/application/send_chat_message_use_case.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository_impl.dart';

import '../test/shared/fakes/in_memory_inbox_staging_repository.dart';

// ---------------------------------------------------------------------------
// Signal helpers
// ---------------------------------------------------------------------------

/// Base directory for signal files — matches the orchestrator's paths.
String _signalDir() {
  final envDir = Platform.environment['E2E_SIGNAL_DIR'];
  if (envDir != null) return envDir;
  return '${Directory.systemTemp.path}/e2e_soak_signals';
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
      print(
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
      jsonEncode({'cmd': 'identity.generate'}),
    );
    final identityResult = jsonDecode(identityJson) as Map<String, dynamic>;
    final myPeerId = identityResult['peerId'] as String;
    final myPrivateKey = identityResult['privateKey'] as String;

    // Generate ML-KEM keys
    final mlKemJson = await bridge.send(jsonEncode({'cmd': 'mlkem.keygen'}));
    final mlKemResult = jsonDecode(mlKemJson) as Map<String, dynamic>;
    final myMlKemPK = mlKemResult['publicKey'] as String;
    final myMlKemSK = mlKemResult['secretKey'] as String;

    // Open in-memory DB with migrations
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final db = await openDatabase(
      inMemoryDatabasePath,
      version: 26,
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
    _writeSignal(
      'flutter_peer_fixture.json',
      jsonEncode({
        'peerId': myPeerId,
        'publicKey': identityResult['publicKey'],
        'mlKemPublicKey': myMlKemPK,
      }),
    );

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

    while (!_signalExists('soak_done')) {
      loopCount++;

      if (_signalExists('phase4_resume_and_send')) {
        final requestRaw = _readSignal('phase4_resume_and_send');
        _deleteSignal('phase4_resume_and_send');

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
        );

        final stored = await messageRepo.getMessagesForContact(cliPeerId);
        final matching = stored
            .where((m) => !m.isIncoming && m.text == phase4Text)
            .toList();
        final persisted = matching.isNotEmpty ? matching.last : null;

        _writeSignal(
          'phase4_result',
          jsonEncode({
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
        _writeSignal('soak_stats', jsonEncode(stats));
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
    _writeSignal('soak_final_stats', jsonEncode(finalStats));

    // Cleanup
    listener.dispose();
    p2pService.dispose();
    await db.close();
  }, timeout: const Timeout(Duration(minutes: 60)));
}
