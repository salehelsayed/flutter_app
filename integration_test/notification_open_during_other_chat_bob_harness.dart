// Notification-open during other chat — Bob (sender) harness.
//
// Pairs with notification_open_during_other_chat_alice_harness.dart.
// Bob's only job here is to:
//   1. Bring up a real P2P/relay-backed stack.
//   2. Exchange identity with Alice via shared signal files.
//   3. Wait for bob_send_go from the orchestrator.
//   4. Send a single 1:1 message to Alice over the real wire.
//
// The receive-side notification fire / tap-routing is tested in the
// alice harness; this side is intentionally minimal.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:flutter_app/core/database/helpers/messages_db_helpers.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/conversation/application/send_chat_message_use_case.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository_impl.dart';
import 'package:flutter_app/features/p2p/presentation/widgets/connection_status_indicator.dart';

import 'group_multi_device_real_harness.dart';

const _sharedDir = String.fromEnvironment(
  'E2E_SHARED_DIR',
  defaultValue: '/tmp',
);
const _runId = String.fromEnvironment('SMOKE_RUN_ID', defaultValue: 'adhoc');
const _dbName = String.fromEnvironment(
  'E2E_DB_NAME',
  defaultValue: 'notif_open_during_other_chat_bob.db',
);

String _sig(String name) => '$_sharedDir/notifopen_${_runId}_$name';

void _writeSignal(String name, String content) {
  File(_sig(name)).writeAsStringSync(content);
}

void _writeJson(String name, Map<String, dynamic> data) {
  _writeSignal(name, jsonEncode(data));
}

Future<void> _waitForSignal(
  String name, {
  Duration timeout = const Duration(seconds: 300),
}) async {
  final path = _sig(name);
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (File(path).existsSync()) return;
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
  throw TimeoutException('Bob(notif-open): timed out waiting for $name');
}

Future<Map<String, dynamic>> _waitForJson(
  String name, {
  Duration timeout = const Duration(seconds: 300),
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
  throw TimeoutException('Bob(notif-open): timed out waiting for json: $name');
}

Future<bool> _waitForOnline(
  dynamic service, {
  Duration timeout = const Duration(seconds: 60),
}) async {
  final sw = Stopwatch()..start();
  while (sw.elapsed < timeout) {
    if (healthFromState(service.currentState) == ConnectionHealth.online) {
      print('[BOB-NO] Online after ${sw.elapsedMilliseconds}ms');
      return true;
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  return false;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  initializeSqliteForCurrentPlatform();

  testWidgets('Bob(notif-open during other chat) — sender', (tester) async {
    print('\n${'═' * 60}');
    print('  BOB (NOTIF-OPEN DURING OTHER CHAT) — SENDER');
    print('${'═' * 60}\n');

    // Mount a neutral staging screen so the binding is happy.
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            key: Key('bob-staging-screen'),
            child: Text('Bob: notif-open sender'),
          ),
        ),
      ),
    );

    // ── Stack ─────────────────────────────────────────────────────────
    final stack = await setupGroupMultiDeviceStack(
      dbName: _dbName,
      username: 'BobNotifOpen',
      cliPeerFixture: null,
    );
    await _waitForOnline(stack.p2pService);

    final messageRepo = MessageRepositoryImpl(
      dbInsertMessage: (row) => dbInsertMessage(stack.db, row),
      dbLoadMessagesForContact: (p) => dbLoadMessagesForContact(stack.db, p),
      dbLoadLatestMessageForContact: (p) =>
          dbLoadLatestMessageForContact(stack.db, p),
      dbUpdateMessageStatus: (id, s) => dbUpdateMessageStatus(stack.db, id, s),
      dbLoadMessage: (id) => dbLoadMessage(stack.db, id),
      dbCountMessagesForContact: (p) => dbCountMessagesForContact(stack.db, p),
      dbMarkConversationAsRead: (p) => dbMarkConversationAsRead(stack.db, p),
      dbCountUnreadForContact: (p) => dbCountUnreadForContact(stack.db, p),
      dbCountTotalUnread: () => dbCountTotalUnread(stack.db),
      dbCountTotalUnreadExcludingArchived: () =>
          dbCountTotalUnreadExcludingArchived(stack.db),
      dbDeleteMessagesForContact: (p) => dbDeleteMessagesForContact(stack.db, p),
      dbDeleteMessage: (id) => dbDeleteMessage(stack.db, id),
      dbLoadMessagesPage: (p, {limit = 50, beforeTimestamp}) =>
          dbLoadMessagesPage(
            stack.db,
            p,
            limit: limit,
            beforeTimestamp: beforeTimestamp,
          ),
      dbLoadFailedOutgoingMessages: () => dbLoadFailedOutgoingMessages(stack.db),
      dbLoadUnackedOutgoingMessages: ({required olderThan, limit = 50}) =>
          dbLoadUnackedOutgoingMessages(
            stack.db,
            olderThan: olderThan,
            limit: limit,
          ),
      dbLoadConversationThreadSummaries: (ids) =>
          dbLoadConversationThreadSummaries(stack.db, ids),
      dbRecoverStuckSendingMessages:
          ({required DateTime olderThan, int limit = 50}) =>
              dbRecoverStuckSendingMessages(
                stack.db,
                olderThan: olderThan,
                limit: limit,
              ),
      dbUpdateWireEnvelope: (id, we) => dbUpdateWireEnvelope(stack.db, id, we),
      dbLoadStuckSendingOutgoingMessages:
          ({required DateTime olderThan, int limit = 50}) =>
              dbLoadStuckSendingOutgoingMessages(
                stack.db,
                olderThan: olderThan,
                limit: limit,
              ),
      dbLoadSendingOutgoingMessages: () =>
          dbLoadSendingOutgoingMessages(stack.db),
      dbConditionalTransitionStatus:
          (id, {required fromStatus, required toStatus}) =>
              dbConditionalTransitionStatus(
                stack.db,
                id,
                fromStatus: fromStatus,
                toStatus: toStatus,
              ),
    );

    // ── Identity exchange ─────────────────────────────────────────────
    _writeJson('bob_identity.json', {
      'peerId': stack.identity.peerId,
      'publicKey': stack.identity.publicKey,
      'mlKemPublicKey': stack.identity.mlKemPublicKey,
    });

    final aliceFixture = await _waitForJson('alice_identity.json');
    final alicePeerId = aliceFixture['peerId'] as String;
    final aliceMlKemPk = aliceFixture['mlKemPublicKey'] as String?;

    await stack.contactRepo.addContact(
      ContactModel(
        peerId: alicePeerId,
        publicKey: aliceFixture['publicKey'] as String,
        rendezvous: '/dns4/relay/tcp/443/p2p/relay',
        username: 'AliceNotifOpen',
        signature: 'sig-alice-notif-open',
        scannedAt: DateTime.now().toUtc().toIso8601String(),
        mlKemPublicKey: aliceMlKemPk,
      ),
    );

    _writeSignal('bob_ready', 'ok');
    print('[BOB-NO] Ready — waiting for go signal');

    // ── Send the message that triggers Alice's notification ───────────
    await _waitForSignal('bob_send_go');
    print('[BOB-NO] Sending 1:1 to Alice');
    final result = await sendChatMessage(
      p2pService: stack.p2pService,
      messageRepo: messageRepo,
      targetPeerId: alicePeerId,
      text: 'Bob says: tap me while you are in user-c chat',
      senderPeerId: stack.identity.peerId,
      senderUsername: stack.identity.username,
      bridge: stack.bridge,
      recipientMlKemPublicKey: aliceMlKemPk,
    );
    _writeJson('bob_sent', {
      'outcome': result.$1.name,
      'messageId': result.$2?.id,
    });
    print('[BOB-NO] Send outcome: ${result.$1.name}');

    // ── Done ──────────────────────────────────────────────────────────
    await _waitForSignal('all_done');
    print('[BOB-NO] Complete');
    await stack.teardown();
    _writeSignal('bob_done', 'ok');
  }, timeout: const Timeout(Duration(minutes: 15)));
}
