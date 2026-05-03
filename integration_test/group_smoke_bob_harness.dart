/// Group Smoke E2E — Bob Harness (Sibling / Group Joiner)
///
/// Runs on simulator 2. Bob joins Alice's group, receives messages
/// via GroupMessageListener, and sends in bidirectional scenarios.
///
/// Launch via orchestrator:
///   dart run integration_test/scripts/run_routing_smoke_e2e.dart -d <alice>,<bob>

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:flutter_app/core/bridge/bridge_group_helpers.dart';
import 'package:flutter_app/core/notifications/active_conversation_tracker.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/groups/application/drain_group_offline_inbox_use_case.dart';
import 'package:flutter_app/features/groups/application/group_message_listener.dart';
import 'package:flutter_app/features/groups/application/send_group_message_use_case.dart';
import 'package:flutter_app/features/p2p/presentation/widgets/connection_status_indicator.dart';

import '../test/shared/fakes/fake_notification_service.dart';

import 'group_multi_device_real_harness.dart';

// ---------------------------------------------------------------------------
// Config
// ---------------------------------------------------------------------------

const _sharedDir = String.fromEnvironment(
  'E2E_SHARED_DIR',
  defaultValue: '/tmp',
);
const _runId = String.fromEnvironment('SMOKE_RUN_ID', defaultValue: 'adhoc');
const _dbName = String.fromEnvironment(
  'E2E_DB_NAME',
  defaultValue: 'group_smoke_bob.db',
);

String _sig(String name) => '$_sharedDir/gsmoke_${_runId}_$name';

void _writeSignal(String name, String content) {
  File(_sig(name)).writeAsStringSync(content);
}

void _writeJson(String name, Map<String, dynamic> data) {
  _writeSignal(name, jsonEncode(data));
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
  throw TimeoutException('Bob(group): timed out waiting for $name');
}

Future<Map<String, dynamic>> _waitForJson(
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
  throw TimeoutException('Bob(group): timed out waiting for json: $name');
}

Future<bool> _waitForOnline(
  dynamic service, {
  Duration timeout = const Duration(seconds: 60),
}) async {
  final sw = Stopwatch()..start();
  while (sw.elapsed < timeout) {
    if (healthFromState(service.currentState) == ConnectionHealth.online) {
      print('[BOB-G] Online after ${sw.elapsedMilliseconds}ms');
      return true;
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  return false;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  initializeSqliteForCurrentPlatform();

  testWidgets('Bob(Group) — G1–G5', (tester) async {
    print('\n${'═' * 60}');
    print('  BOB (GROUP) — SMOKE E2E');
    print('${'═' * 60}\n');

    // ── Setup group stack ──
    final stack = await setupGroupMultiDeviceStack(
      dbName: _dbName,
      username: 'BobGroup',
      cliPeerFixture: null,
    );
    await _waitForOnline(stack.p2pService);

    // ── Identity exchange ──
    _writeJson('bob_identity.json', {
      'peerId': stack.identity.peerId,
      'publicKey': stack.identity.publicKey,
      'mlKemPublicKey': stack.identity.mlKemPublicKey,
    });
    print('[BOB-G] Identity written, waiting for Alice...');

    final aliceFixture = await _waitForJson('alice_identity.json');
    final alicePeerId = aliceFixture['peerId'] as String;

    // Add Alice as contact
    await stack.contactRepo.addContact(
      ContactModel(
        peerId: alicePeerId,
        publicKey: aliceFixture['publicKey'] as String,
        rendezvous: '/dns4/relay/tcp/443/p2p/relay',
        username: 'AliceGroup',
        signature: 'sig-alice-group',
        scannedAt: DateTime.now().toUtc().toIso8601String(),
        mlKemPublicKey: aliceFixture['mlKemPublicKey'] as String?,
      ),
    );

    // Wait for Alice's ready signal (she needs to create the group first)
    await _waitForSignal('alice_ready');

    // Import group fixture
    final groupFixture = await _waitForJson('group_fixture.json');
    final groupId = await importJoinedGroupFixture(
      stack: stack,
      fixture: groupFixture,
    );
    final groupConfig = Map<String, dynamic>.from(
      groupFixture['groupConfig'] as Map,
    );
    final keyFixture = Map<String, dynamic>.from(groupFixture['key'] as Map);
    final groupKey = keyFixture['encrypted_key'] as String;
    final keyEpoch = keyFixture['key_generation'] as int;
    print('[BOB-G] Joined group: ${groupId.substring(0, 20)}...');

    _writeSignal('bob_group_joined', 'ok');

    // Wait for GossipSub peer discovery
    await Future<void>.delayed(const Duration(seconds: 5));
    var activeGroupListener = stack.groupListener;

    // Helper: wait for group message in Bob's DB
    Future<Map<String, dynamic>?> waitForGroupMsg(
      String substring, {
      Duration timeout = const Duration(seconds: 60),
    }) async {
      final sw = Stopwatch()..start();
      final deadline = DateTime.now().add(timeout);
      var nextDrainAt = DateTime.fromMillisecondsSinceEpoch(0);
      while (DateTime.now().isBefore(deadline)) {
        if (DateTime.now().isAfter(nextDrainAt)) {
          nextDrainAt = DateTime.now().add(const Duration(seconds: 2));
          try {
            await drainGroupOfflineInboxForGroup(
              bridge: stack.bridge,
              groupRepo: stack.groupRepo,
              msgRepo: stack.groupMsgRepo,
              groupId: groupId,
              groupMessageListener: activeGroupListener,
              selfPeerId: stack.identity.peerId,
            );
          } catch (e) {
            print('[BOB-G] waitForGroupMsg drain error: $e');
          }
        }
        final msgs = await stack.groupMsgRepo.getMessagesPage(groupId);
        for (final m in msgs) {
          if (m.text.contains(substring) &&
              m.senderPeerId != stack.identity.peerId) {
            sw.stop();
            return {
              'e2eMs': sw.elapsedMilliseconds,
              'text': m.text,
              'senderPeerId': m.senderPeerId,
            };
          }
        }
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
      return null;
    }

    // Helper: send from Bob
    Future<Map<String, dynamic>> sendGroup(String text) async {
      final sw = Stopwatch()..start();
      final result = await sendGroupMessage(
        bridge: stack.bridge,
        groupRepo: stack.groupRepo,
        msgRepo: stack.groupMsgRepo,
        groupId: groupId,
        text: text,
        senderPeerId: stack.identity.peerId,
        senderPublicKey: stack.identity.publicKey,
        senderPrivateKey: stack.identity.privateKey,
        senderUsername: stack.identity.username,
      );
      sw.stop();
      return {'sendMs': sw.elapsedMilliseconds, 'outcome': result.$1.name};
    }

    bool isAcceptedSendOutcome(Map<String, dynamic> result) {
      final outcome = result['outcome']?.toString();
      return outcome == 'success' || outcome == 'successNoPeers';
    }

    Future<Map<String, dynamic>> sendGroupWithReadinessRetry(
      String text, {
      int maxAttempts = 4,
    }) async {
      final attempts = <Map<String, dynamic>>[];
      for (var attempt = 1; attempt <= maxAttempts; attempt++) {
        if (attempt > 1) {
          await Future<void>.delayed(const Duration(seconds: 2));
          try {
            await stack.p2pService.warmBackground();
          } catch (e) {
            print('[BOB-G] retry warmBackground error: $e');
          }
          try {
            await drainGroupOfflineInboxForGroup(
              bridge: stack.bridge,
              groupRepo: stack.groupRepo,
              msgRepo: stack.groupMsgRepo,
              groupId: groupId,
              groupMessageListener: activeGroupListener,
              selfPeerId: stack.identity.peerId,
            );
          } catch (e) {
            print('[BOB-G] retry group inbox drain error: $e');
          }
        }

        final result = await sendGroup(text);
        final annotated = {...result, 'attempt': attempt};
        attempts.add(annotated);
        print(
          '[BOB-G] send "$text" attempt $attempt '
          'outcome=${result['outcome']} sendMs=${result['sendMs']}',
        );
        if (isAcceptedSendOutcome(result)) {
          return {
            ...result,
            if (attempt > 1) 'attempt': attempt,
            if (attempt > 1) 'attempts': attempts,
          };
        }
      }

      return {...attempts.last, 'attempts': attempts};
    }

    Future<void> rejoinGroupTopic(String phase) async {
      await callGroupJoinWithConfig(
        stack.bridge,
        groupId: groupId,
        groupConfig: groupConfig,
        groupKey: groupKey,
        keyEpoch: keyEpoch,
      );
      print('[BOB-G] $phase: rejoined group topic');
    }

    // ════════════════════════════════════════════════════════════════
    //  G1: Group publish → Bob receives
    // ════════════════════════════════════════════════════════════════
    print('\n--- G1: Waiting for group publish ---');
    final g1 = await waitForGroupMsg('G1:');
    print(
      '[BOB-G] G1: ${g1 != null ? 'received (e2e=${g1['e2eMs']}ms)' : 'TIMEOUT'}',
    );
    _writeJson('g1_bob_received', g1 ?? {'e2eMs': -1});

    // ════════════════════════════════════════════════════════════════
    //  G2: Group warm x5 — Bob receives all 5
    // ════════════════════════════════════════════════════════════════
    print('\n--- G2: Waiting for 5 group messages ---');
    final g2Received = <Map<String, dynamic>>[];
    for (var i = 1; i <= 5; i++) {
      final m = await waitForGroupMsg('G2: warm group msg $i');
      if (m != null) g2Received.add(m);
      print('[BOB-G] G2: msg $i: ${m != null}');
    }
    _writeJson('g2_bob_received', {
      'count': g2Received.length,
      'timings': g2Received,
    });

    // ════════════════════════════════════════════════════════════════
    //  G3: Group bidirectional
    // ════════════════════════════════════════════════════════════════
    print('\n--- G3: Group bidirectional ---');
    await _waitForSignal('g3_alice_msg1');
    final g3m1 = await waitForGroupMsg('G3: alice group msg 1');
    print('[BOB-G] G3: received alice msg 1: ${g3m1 != null}');

    // Bob sends msg2
    final g3b2 = await sendGroup('G3: bob group msg 2');
    _writeJson('g3_bob_msg2', g3b2);

    await _waitForSignal('g3_alice_msg3');
    final g3m3 = await waitForGroupMsg('G3: alice group msg 3');
    print('[BOB-G] G3: received alice msg 3: ${g3m3 != null}');

    _writeJson('g3_bob_complete', {
      'received': [g3m1, g3m3],
      'sent': [g3b2],
    });

    // ════════════════════════════════════════════════════════════════
    //  G4: Group offline → inbox → drain
    // ════════════════════════════════════════════════════════════════
    print('\n--- G4: Group offline inbox ---');
    await _waitForSignal('g4_bob_stop');
    stack.groupListener.dispose();
    await stack.p2pService.stopNode();
    _writeSignal('g4_bob_stopped', 'ok');
    print('[BOB-G] G4: stopped');

    await _waitForSignal('g4_bob_restart');
    final restarted = await stack.p2pService.startNode(
      stack.identity.privateKey,
      stack.identity.peerId,
    );
    if (!restarted) throw StateError('G4: restart failed');
    await _waitForOnline(stack.p2pService);
    await rejoinGroupTopic('G4');

    // Re-wire group listener
    final newGroupStream = StreamController<Map<String, dynamic>>.broadcast();
    stack.bridge.onGroupMessageReceived = (data) {
      newGroupStream.add(Map<String, dynamic>.from(data));
    };
    final newGroupListener = GroupMessageListener(
      groupRepo: stack.groupRepo,
      msgRepo: stack.groupMsgRepo,
      bridge: stack.bridge,
      getSelfPeerId: () async => stack.identity.peerId,
      notificationService: stack.notificationService,
      groupConversationTracker: ActiveConversationTracker(),
      getAppLifecycleState: () => AppLifecycleState.paused,
    );
    newGroupListener.start(newGroupStream.stream);
    activeGroupListener = newGroupListener;

    // Drain group offline inbox
    await Future<void>.delayed(const Duration(seconds: 3));
    try {
      await drainGroupOfflineInbox(
        bridge: stack.bridge,
        groupRepo: stack.groupRepo,
        msgRepo: stack.groupMsgRepo,
      );
    } catch (e) {
      print('[BOB-G] G4: group inbox drain error: $e');
    }

    final g4 = await waitForGroupMsg(
      'G4:',
      timeout: const Duration(seconds: 90),
    );
    print(
      '[BOB-G] G4: ${g4 != null ? 'received (e2e=${g4['e2eMs']}ms)' : 'TIMEOUT'}',
    );
    _writeJson('g4_bob_received', g4 ?? {'e2eMs': -1});

    // ════════════════════════════════════════════════════════════════
    //  G5: Group full lifecycle
    // ════════════════════════════════════════════════════════════════
    print('\n--- G5: Group lifecycle ---');
    final g5Timeline = <Map<String, dynamic>>[];

    // Receive msg1–msg4
    for (var i = 1; i <= 4; i++) {
      final m = await waitForGroupMsg(
        'G5: msg$i',
        timeout: const Duration(seconds: 30),
      );
      g5Timeline.add({'n': i, 'role': 'recv', ...?m});
      print('[BOB-G] G5: received msg$i: ${m != null}');
    }

    // Offline phase
    await _waitForSignal('g5_bob_stop');
    newGroupListener.dispose();
    await newGroupStream.close();
    await stack.p2pService.stopNode();
    _writeSignal('g5_bob_stopped', 'ok');

    // Restart
    await _waitForSignal('g5_bob_restart');
    final restarted2 = await stack.p2pService.startNode(
      stack.identity.privateKey,
      stack.identity.peerId,
    );
    if (!restarted2) throw StateError('G5: restart failed');
    await _waitForOnline(stack.p2pService);
    await rejoinGroupTopic('G5');

    final g5GroupStream = StreamController<Map<String, dynamic>>.broadcast();
    stack.bridge.onGroupMessageReceived = (data) {
      g5GroupStream.add(Map<String, dynamic>.from(data));
    };
    final g5GroupListener = GroupMessageListener(
      groupRepo: stack.groupRepo,
      msgRepo: stack.groupMsgRepo,
      bridge: stack.bridge,
      getSelfPeerId: () async => stack.identity.peerId,
      notificationService: stack.notificationService,
      groupConversationTracker: ActiveConversationTracker(),
      getAppLifecycleState: () => AppLifecycleState.paused,
    );
    g5GroupListener.start(g5GroupStream.stream);
    activeGroupListener = g5GroupListener;

    await Future<void>.delayed(const Duration(seconds: 3));
    try {
      await drainGroupOfflineInbox(
        bridge: stack.bridge,
        groupRepo: stack.groupRepo,
        msgRepo: stack.groupMsgRepo,
      );
    } catch (e) {
      print('[BOB-G] G5: group inbox drain error: $e');
    }

    _writeSignal('g5_bob_restarted', 'ok');

    // Group inbox replay is best-effort; keep the lifecycle moving even if the
    // offline message has not surfaced yet after restart.
    final msg5 = await waitForGroupMsg(
      'G5: msg5',
      timeout: const Duration(seconds: 15),
    );
    g5Timeline.add({
      'n': 5,
      'role': 'recv_inbox',
      if (msg5 == null) 'pending': true,
      ...?msg5,
    });

    // Receive msg6 (reconnect)
    final msg6 = await waitForGroupMsg(
      'G5: msg6',
      timeout: const Duration(seconds: 30),
    );
    g5Timeline.add({'n': 6, 'role': 'recv', ...?msg6});

    // Bidirectional: Bob sends msg7
    await Future<void>.delayed(const Duration(seconds: 1));
    final g5b7 = await sendGroupWithReadinessRetry('G5: bob msg7');
    g5Timeline.add({'n': 7, 'role': 'send', ...g5b7});
    _writeJson('g5_bob_msg7', g5b7);

    // Receive msg8–msg9
    for (var i = 8; i <= 9; i++) {
      final m = await waitForGroupMsg(
        'G5: msg$i',
        timeout: const Duration(seconds: 30),
      );
      g5Timeline.add({'n': i, 'role': 'recv', ...?m});
    }

    _writeJson('g5_bob_complete', {'timeline': g5Timeline});
    print('[BOB-G] G5: lifecycle complete');

    // ════════════════════════════════════════════════════════════════
    //  G6: Group peer discovery — Bob already joined, just signal done
    // ════════════════════════════════════════════════════════════════
    print('\n--- G6: Peer discovery timing ---');
    _writeJson('g6_bob_done', {
      'note': 'peer discovery measured during G1 setup',
    });

    // ════════════════════════════════════════════════════════════════
    //  G7: Key rotation — Bob receives msgs before + after rotation
    // ════════════════════════════════════════════════════════════════
    print('\n--- G7: Key rotation ---');
    // Receive pre-rotation message
    final g7Pre = await waitForGroupMsg(
      'G7: pre-rotation',
      timeout: const Duration(seconds: 30),
    );
    print('[BOB-G] G7: pre-rotation received: ${g7Pre != null}');

    // Receive post-rotation message (Bob must auto-accept new key via GroupMessageListener)
    final g7Post = await waitForGroupMsg(
      'G7: post-rotation',
      timeout: const Duration(seconds: 30),
    );
    print('[BOB-G] G7: post-rotation received: ${g7Post != null}');
    _writeJson('g7_bob_received', {
      'preRotation': g7Pre,
      'postRotation': g7Post,
      'bothReceived': g7Pre != null && g7Post != null,
    });

    // ════════════════════════════════════════════════════════════════
    //  G8: Multi-member publish — Bob receives flood publish
    // ════════════════════════════════════════════════════════════════
    print('\n--- G8: Multi-member publish ---');
    final g8 = await waitForGroupMsg(
      'G8:',
      timeout: const Duration(seconds: 30),
    );
    print('[BOB-G] G8: received: ${g8 != null}');
    _writeJson('g8_bob_received', g8 ?? {'e2eMs': -1});

    // ── Done ──
    await _waitForSignal('all_done');
    print('\n[BOB-G] All group scenarios complete');

    g5GroupListener.dispose();
    await g5GroupStream.close();
    await stack.teardown();
    _writeSignal('bob_done', 'ok');
  });
}
