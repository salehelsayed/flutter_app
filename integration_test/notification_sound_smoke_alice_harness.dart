/// Notification Sound Smoke — Alice Harness (Sender)
///
/// Drives the four scenarios (S1 1:1, S2 group chat, S3 group announcement,
/// S4 suppression control) by sending one message each to Bob. Coordinated
/// with Bob via signal files under `/tmp/nsmoke_<runId>_*`.
///
/// Launch via orchestrator:
///   dart run integration_test/scripts/run_notification_sound_smoke.dart -d <alice>,<bob>

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:flutter_app/core/database/helpers/messages_db_helpers.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/conversation/application/send_chat_message_use_case.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository_impl.dart';
import 'package:flutter_app/features/groups/application/create_group_with_members_use_case.dart';
import 'package:flutter_app/features/groups/application/send_group_message_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/p2p/presentation/widgets/connection_status_indicator.dart';

import 'group_multi_device_real_harness.dart';

// ---------------------------------------------------------------------------
// Config from dart-defines
// ---------------------------------------------------------------------------

const _sharedDir =
    String.fromEnvironment('E2E_SHARED_DIR', defaultValue: '/tmp');
const _runId = String.fromEnvironment('SMOKE_RUN_ID', defaultValue: 'adhoc');
const _dbName = String.fromEnvironment(
  'E2E_DB_NAME',
  defaultValue: 'notif_sound_smoke_alice.db',
);

String _sig(String name) => '$_sharedDir/nsmoke_${_runId}_$name';

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
  throw TimeoutException('Alice(notif): timed out waiting for $name');
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
  throw TimeoutException('Alice(notif): timed out waiting for json: $name');
}

Future<bool> _waitForOnline(dynamic service,
    {Duration timeout = const Duration(seconds: 60)}) async {
  final sw = Stopwatch()..start();
  while (sw.elapsed < timeout) {
    if (healthFromState(service.currentState) == ConnectionHealth.online) {
      print('[ALICE-N] Online after ${sw.elapsedMilliseconds}ms');
      return true;
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  return false;
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  initializeSqliteForCurrentPlatform();

  testWidgets('Alice(Notif) — S1..S4', (tester) async {
    print('\n${'═' * 60}');
    print('  ALICE (NOTIFICATION SOUND) — SMOKE E2E');
    print('${'═' * 60}\n');

    // ── Stack (reuse the group-capable setup; all repos we need) ──
    final stack = await setupGroupMultiDeviceStack(
      dbName: _dbName,
      username: 'AliceNotif',
      cliPeerFixture: null,
    );
    await _waitForOnline(stack.p2pService);

    // ── 1:1 message repo (not created by setupGroupMultiDeviceStack) ──
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
          dbLoadMessagesPage(stack.db, p,
              limit: limit, beforeTimestamp: beforeTimestamp),
      dbLoadFailedOutgoingMessages: () => dbLoadFailedOutgoingMessages(stack.db),
      dbLoadUnackedOutgoingMessages: ({required olderThan, limit = 50}) =>
          dbLoadUnackedOutgoingMessages(stack.db,
              olderThan: olderThan, limit: limit),
      dbLoadConversationThreadSummaries: (ids) =>
          dbLoadConversationThreadSummaries(stack.db, ids),
      dbRecoverStuckSendingMessages: (
              {required DateTime olderThan, int limit = 50}) =>
          dbRecoverStuckSendingMessages(stack.db,
              olderThan: olderThan, limit: limit),
      dbUpdateWireEnvelope: (id, we) =>
          dbUpdateWireEnvelope(stack.db, id, we),
      dbLoadStuckSendingOutgoingMessages: (
              {required DateTime olderThan, int limit = 50}) =>
          dbLoadStuckSendingOutgoingMessages(stack.db,
              olderThan: olderThan, limit: limit),
      dbLoadSendingOutgoingMessages: () =>
          dbLoadSendingOutgoingMessages(stack.db),
      dbConditionalTransitionStatus: (id,
              {required fromStatus, required toStatus}) =>
          dbConditionalTransitionStatus(stack.db, id,
              fromStatus: fromStatus, toStatus: toStatus),
    );

    // ── Identity exchange ──
    _writeJson('alice_identity.json', {
      'peerId': stack.identity.peerId,
      'publicKey': stack.identity.publicKey,
      'mlKemPublicKey': stack.identity.mlKemPublicKey,
    });
    _writeSignal('alice_ready', 'ok');
    print('[ALICE-N] Ready — waiting for Bob identity...');

    final bobFixture = await _waitForJson('bob_identity.json');
    final bobPeerId = bobFixture['peerId'] as String;
    final bobMlKemPk = bobFixture['mlKemPublicKey'] as String?;

    await stack.contactRepo.addContact(ContactModel(
      peerId: bobPeerId,
      publicKey: bobFixture['publicKey'] as String,
      rendezvous: '/dns4/relay/tcp/443/p2p/relay',
      username: 'BobNotif',
      signature: 'sig-bob-notif',
      scannedAt: DateTime.now().toUtc().toIso8601String(),
      mlKemPublicKey: bobMlKemPk,
    ));
    await _waitForSignal('bob_ready');
    final bobContact = await stack.contactRepo.getContact(bobPeerId);
    if (bobContact == null) {
      throw StateError('Alice failed to persist Bob as contact');
    }

    // ════════════════════════════════════════════════════════════════
    //  S1: 1:1 direct chat
    // ════════════════════════════════════════════════════════════════
    print('\n--- S1: 1:1 send ---');
    await _waitForSignal('s1_go');
    final s1Result = await sendChatMessage(
      p2pService: stack.p2pService,
      messageRepo: messageRepo,
      targetPeerId: bobPeerId,
      text: 'S1: notification sound 1:1',
      senderPeerId: stack.identity.peerId,
      senderUsername: stack.identity.username,
      bridge: stack.bridge,
      recipientMlKemPublicKey: bobMlKemPk,
    );
    _writeSignal(
      's1_alice_sent',
      jsonEncode({'outcome': s1Result.$1.name}),
    );
    print('[ALICE-N] S1 sent: ${s1Result.$1.name}');
    await _waitForSignal('s1_verdict_ack');

    // ════════════════════════════════════════════════════════════════
    //  S2: Group discussion (GroupType.chat)
    // ════════════════════════════════════════════════════════════════
    print('\n--- S2: Group discussion (chat) create+send ---');
    final chatGroupResult = await createGroupWithMembers(
      bridge: stack.bridge,
      groupRepo: stack.groupRepo,
      p2pService: stack.p2pService,
      identity: stack.identity,
      selectedContacts: [bobContact],
      type: GroupType.chat,
      name: 'Notif Sound Discussion',
    );
    final chatGroup = await stack.groupRepo.getGroup(chatGroupResult.group.id);
    final chatKeyInfo =
        await stack.groupRepo.getLatestKey(chatGroupResult.group.id);
    final chatMembers =
        await stack.groupRepo.getMembers(chatGroupResult.group.id);
    _writeJson(
      'group_chat_fixture.json',
      buildGroupFixture(
        group: chatGroup!,
        keyInfo: chatKeyInfo!,
        members: chatMembers,
      ),
    );
    _writeSignal('alice_group_chat_ready', 'ok');
    await _waitForSignal('bob_group_chat_joined');
    // Let GossipSub peer discovery + mesh form on both sides.
    await Future<void>.delayed(const Duration(seconds: 5));

    await _waitForSignal('s2_go');
    final s2Result = await sendGroupMessage(
      bridge: stack.bridge,
      groupRepo: stack.groupRepo,
      msgRepo: stack.groupMsgRepo,
      groupId: chatGroup.id,
      text: 'S2: notification sound discussion',
      senderPeerId: stack.identity.peerId,
      senderPublicKey: stack.identity.publicKey,
      senderPrivateKey: stack.identity.privateKey,
      senderUsername: stack.identity.username,
    );
    _writeSignal(
      's2_alice_sent',
      jsonEncode({'outcome': s2Result.$1.name}),
    );
    print('[ALICE-N] S2 sent: ${s2Result.$1.name}');
    await _waitForSignal('s2_verdict_ack');

    // ════════════════════════════════════════════════════════════════
    //  S3: Group announcement (GroupType.announcement)
    // ════════════════════════════════════════════════════════════════
    print('\n--- S3: Group announcement create+send ---');
    final annGroupResult = await createGroupWithMembers(
      bridge: stack.bridge,
      groupRepo: stack.groupRepo,
      p2pService: stack.p2pService,
      identity: stack.identity,
      selectedContacts: [bobContact],
      type: GroupType.announcement,
      name: 'Notif Sound Announcement',
    );
    final annGroup = await stack.groupRepo.getGroup(annGroupResult.group.id);
    final annKeyInfo =
        await stack.groupRepo.getLatestKey(annGroupResult.group.id);
    final annMembers =
        await stack.groupRepo.getMembers(annGroupResult.group.id);
    _writeJson(
      'group_announcement_fixture.json',
      buildGroupFixture(
        group: annGroup!,
        keyInfo: annKeyInfo!,
        members: annMembers,
      ),
    );
    _writeSignal('alice_group_announcement_ready', 'ok');
    await _waitForSignal('bob_group_announcement_joined');
    await Future<void>.delayed(const Duration(seconds: 5));

    await _waitForSignal('s3_go');
    final s3Result = await sendGroupMessage(
      bridge: stack.bridge,
      groupRepo: stack.groupRepo,
      msgRepo: stack.groupMsgRepo,
      groupId: annGroup.id,
      text: 'S3: notification sound announcement',
      senderPeerId: stack.identity.peerId,
      senderPublicKey: stack.identity.publicKey,
      senderPrivateKey: stack.identity.privateKey,
      senderUsername: stack.identity.username,
    );
    _writeSignal(
      's3_alice_sent',
      jsonEncode({'outcome': s3Result.$1.name}),
    );
    print('[ALICE-N] S3 sent: ${s3Result.$1.name}');
    await _waitForSignal('s3_verdict_ack');

    // ════════════════════════════════════════════════════════════════
    //  S4: Suppression control — Bob is now viewing Alice's 1:1 conversation.
    //       Alice re-sends a 1:1 message; Bob should SUPPRESS.
    // ════════════════════════════════════════════════════════════════
    print('\n--- S4: Suppression control (1:1) ---');
    await _waitForSignal('bob_viewing_conversation');
    await _waitForSignal('s4_go');
    final s4Result = await sendChatMessage(
      p2pService: stack.p2pService,
      messageRepo: messageRepo,
      targetPeerId: bobPeerId,
      text: 'S4: should be suppressed',
      senderPeerId: stack.identity.peerId,
      senderUsername: stack.identity.username,
      bridge: stack.bridge,
      recipientMlKemPublicKey: bobMlKemPk,
    );
    _writeSignal(
      's4_alice_sent',
      jsonEncode({'outcome': s4Result.$1.name}),
    );
    print('[ALICE-N] S4 sent: ${s4Result.$1.name}');
    await _waitForSignal('s4_verdict_ack');

    // ── Done ──
    await _waitForSignal('all_done');
    print('\n[ALICE-N] Complete');
    await stack.teardown();
    _writeSignal('alice_done', 'ok');
  }, timeout: const Timeout(Duration(minutes: 20)));
}
