/// Group Smoke E2E — Role-Dispatched Harness (Alice + Bob)
///
/// Single harness launched twice by the orchestrator with
/// `--dart-define=SMOKE_ROLE=alice` (group creator) and `SMOKE_ROLE=bob`
/// (group joiner). Drives scenarios G1–G8 measuring group publish timing on
/// both sides. The two sides coordinate via shared signal files in the
/// `gsmoke_${runId}_*` namespace.
///
/// Launch via orchestrator:
///   dart run integration_test/scripts/run_routing_smoke_e2e.dart -d <alice>,<bob>

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:flutter_app/core/bridge/bridge_group_helpers.dart';
import 'package:flutter_app/core/notifications/active_conversation_tracker.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/groups/application/create_group_with_members_use_case.dart';
import 'package:flutter_app/features/groups/application/drain_group_offline_inbox_use_case.dart';
import 'package:flutter_app/features/groups/application/group_message_listener.dart';
import 'package:flutter_app/features/groups/application/rotate_and_distribute_group_key_use_case.dart';
import 'package:flutter_app/features/groups/application/send_group_message_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';

import '_support/node_readiness.dart';
import '_support/signal_files.dart';
import 'group_multi_device_real_harness.dart';

// ---------------------------------------------------------------------------
// Config from dart-defines (same namespace as routing smoke)
// ---------------------------------------------------------------------------

const _role = String.fromEnvironment('SMOKE_ROLE', defaultValue: 'alice');
const _sharedDir = String.fromEnvironment(
  'E2E_SHARED_DIR',
  defaultValue: '/tmp',
);
const _runId = String.fromEnvironment('SMOKE_RUN_ID', defaultValue: 'adhoc');
const _dbName = String.fromEnvironment(
  'E2E_DB_NAME',
  defaultValue: 'group_smoke.db',
);

/// Shared signal-file coordinator for the `gsmoke_${_runId}_*` namespace.
/// Produces byte-identical paths to the former inline `_sig(name)` helper:
/// `'$_sharedDir/gsmoke_${_runId}_$name'`.
final _signals = SignalDir(
  dir: _sharedDir,
  prefix: 'gsmoke_',
  runId: '${_runId}_',
  role: '$_role(group)',
);

// ---------------------------------------------------------------------------
// Main — dispatches on SMOKE_ROLE
// ---------------------------------------------------------------------------

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  initializeSqliteForCurrentPlatform();

  if (_role == 'bob') {
    _runBob();
  } else {
    _runAlice();
  }
}

// ===========================================================================
//  ALICE (group creator)
// ===========================================================================

void _runAlice() {
  testWidgets('Alice(Group) — G1–G5', (tester) async {
    print('\n${'═' * 60}');
    print('  ALICE (GROUP) — SMOKE E2E');
    print('${'═' * 60}\n');

    // ── Setup full group stack ──
    final stack = await setupGroupMultiDeviceStack(
      dbName: _dbName,
      username: 'AliceGroup',
      cliPeerFixture: null, // no CLI peer — Bob is the other simulator
    );
    await waitForOnline(
      stack.p2pService,
      timeout: const Duration(seconds: 60),
    );

    // ── Identity exchange ──
    _signals.writeJson('alice_identity.json', {
      'peerId': stack.identity.peerId,
      'publicKey': stack.identity.publicKey,
      'mlKemPublicKey': stack.identity.mlKemPublicKey,
    });
    _signals.writeSignal('alice_ready');
    print('[ALICE-G] Ready, waiting for Bob...');

    final bobFixture = await _signals.waitForJson(
      'bob_identity.json',
      timeout: const Duration(minutes: 15),
    );
    final bobPeerId = bobFixture['peerId'] as String;

    // Add Bob as contact (needed for group creation)
    await stack.contactRepo.addContact(
      ContactModel(
        peerId: bobPeerId,
        publicKey: bobFixture['publicKey'] as String,
        rendezvous: '/dns4/relay/tcp/443/p2p/relay',
        username: 'BobGroup',
        signature: 'sig-bob-group',
        scannedAt: DateTime.now().toUtc().toIso8601String(),
        mlKemPublicKey: bobFixture['mlKemPublicKey'] as String?,
      ),
    );
    print('[ALICE-G] Bob added as contact');

    // ── Create group ──
    final bobContact = await stack.contactRepo.getContact(bobPeerId);
    final groupResult = await createGroupWithMembers(
      bridge: stack.bridge,
      groupRepo: stack.groupRepo,
      p2pService: stack.p2pService,
      identity: stack.identity,
      selectedContacts: [bobContact!],
      type: GroupType.chat,
      name: 'Smoke Test Group',
      inviteDeliveryAttemptRepo: stack.groupInviteDeliveryAttemptRepo,
    );
    final groupId = groupResult.group.id;
    print('[ALICE-G] Group created: ${groupId.substring(0, 20)}...');

    final group = await stack.groupRepo.getGroup(groupId);
    final keyInfo = await stack.groupRepo.getLatestKey(groupId);
    final members = await stack.groupRepo.getMembers(groupId);

    // Share group fixture with Bob
    _signals.writeJson(
      'group_fixture.json',
      buildGroupFixture(group: group!, keyInfo: keyInfo!, members: members),
    );
    print('[ALICE-G] Group fixture written');

    // Wait for Bob to join — measure discovery timing
    final discoveryStopwatch = Stopwatch()..start();
    await _signals.waitForSignal('bob_group_joined');
    await stack.groupInviteDeliveryAttemptRepo.markJoined(
      groupId: groupId,
      peerId: bobPeerId,
      username: 'BobGroup',
    );
    print('[ALICE-G] Bob joined group');

    // Wait for peer discovery (give GossipSub time to connect)
    await Future<void>.delayed(const Duration(seconds: 5));
    discoveryStopwatch.stop();
    final peerDiscoveryMs = discoveryStopwatch.elapsedMilliseconds;
    print(
      '[ALICE-G] Peer discovery: ${peerDiscoveryMs}ms (includes 5s settle)',
    );

    // Helper: send group message + capture timing
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
        inviteDeliveryAttemptRepo: stack.groupInviteDeliveryAttemptRepo,
      );
      sw.stop();
      return {
        'sendMs': sw.elapsedMilliseconds,
        'outcome': result.$1.name,
        'messageId': result.$2?.id ?? '',
      };
    }

    // Helper: wait for incoming group message in Alice's repo.
    Future<Map<String, dynamic>?> waitForGroupMsg(
      String substring, {
      Duration timeout = const Duration(seconds: 30),
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
              groupMessageListener: stack.groupListener,
              selfPeerId: stack.identity.peerId,
            );
          } catch (e) {
            print('[ALICE-G] waitForGroupMsg drain error: $e');
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

    // ════════════════════════════════════════════════════════════════
    //  G1: Group publish → receive
    // ════════════════════════════════════════════════════════════════
    await _signals.waitForSignal('g1_go');
    print('\n--- G1: Group publish ---');
    final g1 = await sendGroup('G1: alice group msg');
    _signals.writeJson('g1_alice_sent', g1);
    await _signals.waitForSignal('g1_verified');

    // ════════════════════════════════════════════════════════════════
    //  G2: Group warm send x5
    // ════════════════════════════════════════════════════════════════
    await _signals.waitForSignal('g2_go');
    print('\n--- G2: Group warm x5 ---');
    final g2Timings = <Map<String, dynamic>>[];
    for (var i = 1; i <= 5; i++) {
      final d = await sendGroup('G2: warm group msg $i');
      g2Timings.add(d);
    }
    _signals.writeJson('g2_alice_sent', {'timings': g2Timings});
    await _signals.waitForSignal('g2_verified');

    // ════════════════════════════════════════════════════════════════
    //  G3: Group bidirectional
    // ════════════════════════════════════════════════════════════════
    await _signals.waitForSignal('g3_go');
    print('\n--- G3: Group bidirectional ---');
    final g3a1 = await sendGroup('G3: alice group msg 1');
    _signals.writeJson('g3_alice_msg1', g3a1);

    await _signals.waitForSignal('g3_bob_msg2');
    final gotBobMsg2 = await waitForGroupMsg('G3: bob group msg 2');
    print('[ALICE-G] G3: received bob msg 2: ${gotBobMsg2 != null}');

    final g3a3 = await sendGroup('G3: alice group msg 3');
    _signals.writeJson('g3_alice_msg3', g3a3);
    _signals.writeSignal('g3_alice_complete');

    // ════════════════════════════════════════════════════════════════
    //  G4: Group offline → inbox → drain
    // ════════════════════════════════════════════════════════════════
    await _signals.waitForSignal('g4_go');
    print('\n--- G4: Group offline inbox ---');
    await _signals.waitForSignal('g4_bob_stopped');
    final g4 = await sendGroup('G4: group inbox msg');
    _signals.writeJson('g4_alice_sent', g4);
    await _signals.waitForSignal('g4_verified');

    // ════════════════════════════════════════════════════════════════
    //  G5: Group full lifecycle
    // ════════════════════════════════════════════════════════════════
    await _signals.waitForSignal('g5_go');
    print('\n--- G5: Group lifecycle ---');
    final g5Timeline = <Map<String, dynamic>>[];

    // Cold publish
    var gd = await sendGroup('G5: msg1 cold');
    g5Timeline.add({'n': 1, 'label': 'cold', ...gd});

    // Warm x3
    await Future<void>.delayed(const Duration(seconds: 1));
    for (var i = 2; i <= 4; i++) {
      gd = await sendGroup('G5: msg$i warm');
      g5Timeline.add({'n': i, 'label': 'warm', ...gd});
    }
    _signals.writeSignal('g5_warm_done');

    // Offline phase: wait for Bob stop, publish to inbox
    await _signals.waitForSignal('g5_bob_stopped');
    gd = await sendGroup('G5: msg5 offline');
    g5Timeline.add({'n': 5, 'label': 'offline', ...gd});
    _signals.writeSignal('g5_inbox_sent');

    // Reconnect phase
    await _signals.waitForSignal('g5_bob_restarted');
    gd = await sendGroup('G5: msg6 reconnect');
    g5Timeline.add({'n': 6, 'label': 'reconnect', ...gd});

    // Bidirectional: wait for Bob's msg7
    await _signals.waitForSignal('g5_bob_msg7');
    final gotMsg7 = await waitForGroupMsg('G5: bob msg7');
    g5Timeline.add({'n': 7, 'label': 'recv', 'received': gotMsg7});

    // Warm again
    for (var i = 8; i <= 9; i++) {
      gd = await sendGroup('G5: msg$i warm');
      g5Timeline.add({'n': i, 'label': 'warm', ...gd});
    }
    _signals.writeJson('g5_alice_complete', {'timeline': g5Timeline});

    // ════════════════════════════════════════════════════════════════
    //  G6: Group peer discovery timing
    // ════════════════════════════════════════════════════════════════
    await _signals.waitForSignal('g6_go');
    print('\n--- G6: Group peer discovery timing ---');
    // Measure time to see Bob as a GossipSub peer
    // We already have the group; the timing was captured during initial join.
    // Re-measure by checking topic peer count now vs at join.
    _signals.writeJson('g6_alice_done', {
      'peerDiscoveryMs': peerDiscoveryMs,
      'note':
          'Time from Bob joined signal to GossipSub settle (includes 5s wait)',
    });

    // ════════════════════════════════════════════════════════════════
    //  G7: Group key rotation under traffic
    // ════════════════════════════════════════════════════════════════
    await _signals.waitForSignal('g7_go');
    print('\n--- G7: Key rotation under traffic ---');

    // Send a pre-rotation message
    final g7Pre = await sendGroup('G7: pre-rotation msg');
    _signals.writeJson('g7_pre_rotation', g7Pre);

    // Rotate the group key
    final g7RotSw = Stopwatch()..start();
    final newKey = await rotateAndDistributeGroupKey(
      bridge: stack.bridge,
      groupRepo: stack.groupRepo,
      groupId: groupId,
      selfPeerId: stack.identity.peerId,
      senderPublicKey: stack.identity.publicKey,
      senderPrivateKey: stack.identity.privateKey,
      senderUsername: stack.identity.username,
      sendP2PMessage: stack.p2pService.sendMessage,
    );
    g7RotSw.stop();
    print(
      '[ALICE-G] G7: key rotated in ${g7RotSw.elapsedMilliseconds}ms (new key: ${newKey != null})',
    );

    // Send a post-rotation message (uses new key)
    final g7Post = await sendGroup('G7: post-rotation msg');
    _signals.writeJson('g7_alice_sent', {
      'rotationMs': g7RotSw.elapsedMilliseconds,
      'newKeyGeneration': newKey?.keyGeneration,
      'preRotation': g7Pre,
      'postRotation': g7Post,
    });
    await _signals.waitForSignal('g7_verified');

    // ════════════════════════════════════════════════════════════════
    //  G8: 3-member group (Alice + Bob + Bob's second identity)
    //  Note: We can't easily add a 3rd simulator, so we measure with
    //  the existing 2 members — the GossipSub flood publish behavior
    //  is the same (WithFloodPublish sends to ALL peers).
    // ════════════════════════════════════════════════════════════════
    await _signals.waitForSignal('g8_go');
    print('\n--- G8: Multi-member publish ---');
    final g8 = await sendGroup('G8: flood publish msg');
    _signals.writeJson('g8_alice_sent', g8);
    await _signals.waitForSignal('g8_verified');

    // ── Done ──
    await _signals.waitForSignal('all_done');
    print('\n[ALICE-G] All group scenarios complete');

    await stack.teardown();
    _signals.writeSignal('alice_done');
  });
}

// ===========================================================================
//  BOB (group joiner)
// ===========================================================================

void _runBob() {
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
    await waitForOnline(stack.p2pService, timeout: const Duration(seconds: 60));

    // ── Identity exchange ──
    _signals.writeJson('bob_identity.json', {
      'peerId': stack.identity.peerId,
      'publicKey': stack.identity.publicKey,
      'mlKemPublicKey': stack.identity.mlKemPublicKey,
    });
    print('[BOB-G] Identity written, waiting for Alice...');

    final aliceFixture = await _signals.waitForJson('alice_identity.json');
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
    await _signals.waitForSignal('alice_ready');

    // Import group fixture
    final groupFixture = await _signals.waitForJson('group_fixture.json');
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

    _signals.writeSignal('bob_group_joined');

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
        inviteDeliveryAttemptRepo: stack.groupInviteDeliveryAttemptRepo,
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
    _signals.writeJson('g1_bob_received', g1 ?? {'e2eMs': -1});

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
    _signals.writeJson('g2_bob_received', {
      'count': g2Received.length,
      'timings': g2Received,
    });

    // ════════════════════════════════════════════════════════════════
    //  G3: Group bidirectional
    // ════════════════════════════════════════════════════════════════
    print('\n--- G3: Group bidirectional ---');
    await _signals.waitForSignal('g3_alice_msg1');
    final g3m1 = await waitForGroupMsg('G3: alice group msg 1');
    print('[BOB-G] G3: received alice msg 1: ${g3m1 != null}');

    // Bob sends msg2
    final g3b2 = await sendGroup('G3: bob group msg 2');
    _signals.writeJson('g3_bob_msg2', g3b2);

    await _signals.waitForSignal('g3_alice_msg3');
    final g3m3 = await waitForGroupMsg('G3: alice group msg 3');
    print('[BOB-G] G3: received alice msg 3: ${g3m3 != null}');

    _signals.writeJson('g3_bob_complete', {
      'received': [g3m1, g3m3],
      'sent': [g3b2],
    });

    // ════════════════════════════════════════════════════════════════
    //  G4: Group offline → inbox → drain
    // ════════════════════════════════════════════════════════════════
    print('\n--- G4: Group offline inbox ---');
    await _signals.waitForSignal('g4_bob_stop');
    stack.groupListener.dispose();
    await stack.p2pService.stopNode();
    _signals.writeSignal('g4_bob_stopped');
    print('[BOB-G] G4: stopped');

    await _signals.waitForSignal('g4_bob_restart');
    final restarted = await stack.p2pService.startNode(
      stack.identity.privateKey,
      stack.identity.peerId,
    );
    if (!restarted) throw StateError('G4: restart failed');
    await waitForOnline(stack.p2pService, timeout: const Duration(seconds: 60));
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
      inviteDeliveryAttemptRepo: stack.groupInviteDeliveryAttemptRepo,
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
    _signals.writeJson('g4_bob_received', g4 ?? {'e2eMs': -1});

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
    await _signals.waitForSignal('g5_bob_stop');
    newGroupListener.dispose();
    await newGroupStream.close();
    await stack.p2pService.stopNode();
    _signals.writeSignal('g5_bob_stopped');

    // Restart
    await _signals.waitForSignal('g5_bob_restart');
    final restarted2 = await stack.p2pService.startNode(
      stack.identity.privateKey,
      stack.identity.peerId,
    );
    if (!restarted2) throw StateError('G5: restart failed');
    await waitForOnline(stack.p2pService, timeout: const Duration(seconds: 60));
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
      inviteDeliveryAttemptRepo: stack.groupInviteDeliveryAttemptRepo,
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

    _signals.writeSignal('g5_bob_restarted');

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
    _signals.writeJson('g5_bob_msg7', g5b7);

    // Receive msg8–msg9
    for (var i = 8; i <= 9; i++) {
      final m = await waitForGroupMsg(
        'G5: msg$i',
        timeout: const Duration(seconds: 30),
      );
      g5Timeline.add({'n': i, 'role': 'recv', ...?m});
    }

    _signals.writeJson('g5_bob_complete', {'timeline': g5Timeline});
    print('[BOB-G] G5: lifecycle complete');

    // ════════════════════════════════════════════════════════════════
    //  G6: Group peer discovery — Bob already joined, just signal done
    // ════════════════════════════════════════════════════════════════
    print('\n--- G6: Peer discovery timing ---');
    _signals.writeJson('g6_bob_done', {
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
    _signals.writeJson('g7_bob_received', {
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
    _signals.writeJson('g8_bob_received', g8 ?? {'e2eMs': -1});

    // ── Done ──
    await _signals.waitForSignal('all_done');
    print('\n[BOB-G] All group scenarios complete');

    g5GroupListener.dispose();
    await g5GroupStream.close();
    await stack.teardown();
    _signals.writeSignal('bob_done');
  });
}
