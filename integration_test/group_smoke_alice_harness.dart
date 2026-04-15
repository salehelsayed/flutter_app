/// Group Smoke E2E — Alice Harness (Primary / Group Creator)
///
/// Runs on simulator 1. Alice creates a group with Bob, then drives
/// scenarios G1–G5 measuring group publish timing on both sides.
///
/// Launch via orchestrator:
///   dart run integration_test/scripts/run_routing_smoke_e2e.dart -d <alice>,<bob>

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/groups/application/create_group_with_members_use_case.dart';
import 'package:flutter_app/features/groups/application/rotate_and_distribute_group_key_use_case.dart';
import 'package:flutter_app/features/groups/application/send_group_message_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/p2p/presentation/widgets/connection_status_indicator.dart';

import 'group_multi_device_real_harness.dart';

// ---------------------------------------------------------------------------
// Config from dart-defines (same namespace as routing smoke)
// ---------------------------------------------------------------------------

const _sharedDir = String.fromEnvironment('E2E_SHARED_DIR', defaultValue: '/tmp');
const _runId = String.fromEnvironment('SMOKE_RUN_ID', defaultValue: 'adhoc');
const _dbName = String.fromEnvironment('E2E_DB_NAME', defaultValue: 'group_smoke_alice.db');

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
  throw TimeoutException('Alice(group): timed out waiting for $name');
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
  throw TimeoutException('Alice(group): timed out waiting for json: $name');
}

Future<bool> _waitForOnline(dynamic service, {Duration timeout = const Duration(seconds: 60)}) async {
  final sw = Stopwatch()..start();
  while (sw.elapsed < timeout) {
    if (healthFromState(service.currentState) == ConnectionHealth.online) {
      print('[ALICE-G] Online after ${sw.elapsedMilliseconds}ms');
      return true;
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  return false;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  initializeSqliteForCurrentPlatform();

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
    await _waitForOnline(stack.p2pService);

    // ── Identity exchange ──
    _writeJson('alice_identity.json', {
      'peerId': stack.identity.peerId,
      'publicKey': stack.identity.publicKey,
      'mlKemPublicKey': stack.identity.mlKemPublicKey,
    });
    _writeSignal('alice_ready', 'ok');
    print('[ALICE-G] Ready, waiting for Bob...');

    final bobFixture = await _waitForJson('bob_identity.json');
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
    );
    final groupId = groupResult.group.id;
    print('[ALICE-G] Group created: ${groupId.substring(0, 20)}...');

    final group = await stack.groupRepo.getGroup(groupId);
    final keyInfo = await stack.groupRepo.getLatestKey(groupId);
    final members = await stack.groupRepo.getMembers(groupId);

    // Share group fixture with Bob
    _writeJson('group_fixture.json', buildGroupFixture(
      group: group!,
      keyInfo: keyInfo!,
      members: members,
    ));
    print('[ALICE-G] Group fixture written');

    // Wait for Bob to join — measure discovery timing
    final discoveryStopwatch = Stopwatch()..start();
    await _waitForSignal('bob_group_joined');
    print('[ALICE-G] Bob joined group');

    // Wait for peer discovery (give GossipSub time to connect)
    await Future<void>.delayed(const Duration(seconds: 5));
    discoveryStopwatch.stop();
    final peerDiscoveryMs = discoveryStopwatch.elapsedMilliseconds;
    print('[ALICE-G] Peer discovery: ${peerDiscoveryMs}ms (includes 5s settle)');

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
      );
      sw.stop();
      return {
        'sendMs': sw.elapsedMilliseconds,
        'outcome': result.$1.name,
        'messageId': result.$2?.id ?? '',
      };
    }

    // Helper: wait for incoming group message in Bob's repo (Alice checks her own)
    Future<bool> waitForGroupMsg(String substring, {Duration timeout = const Duration(seconds: 30)}) async {
      final deadline = DateTime.now().add(timeout);
      while (DateTime.now().isBefore(deadline)) {
        final msgs = await stack.groupMsgRepo.getMessagesPage(groupId);
        if (msgs.any((m) => m.text.contains(substring) && m.senderPeerId != stack.identity.peerId)) {
          return true;
        }
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
      return false;
    }

    // ════════════════════════════════════════════════════════════════
    //  G1: Group publish → receive
    // ════════════════════════════════════════════════════════════════
    await _waitForSignal('g1_go');
    print('\n--- G1: Group publish ---');
    final g1 = await sendGroup('G1: alice group msg');
    _writeJson('g1_alice_sent', g1);
    await _waitForSignal('g1_verified');

    // ════════════════════════════════════════════════════════════════
    //  G2: Group warm send x5
    // ════════════════════════════════════════════════════════════════
    await _waitForSignal('g2_go');
    print('\n--- G2: Group warm x5 ---');
    final g2Timings = <Map<String, dynamic>>[];
    for (var i = 1; i <= 5; i++) {
      final d = await sendGroup('G2: warm group msg $i');
      g2Timings.add(d);
    }
    _writeJson('g2_alice_sent', {'timings': g2Timings});
    await _waitForSignal('g2_verified');

    // ════════════════════════════════════════════════════════════════
    //  G3: Group bidirectional
    // ════════════════════════════════════════════════════════════════
    await _waitForSignal('g3_go');
    print('\n--- G3: Group bidirectional ---');
    final g3a1 = await sendGroup('G3: alice group msg 1');
    _writeJson('g3_alice_msg1', g3a1);

    await _waitForSignal('g3_bob_msg2');
    final gotBobMsg2 = await waitForGroupMsg('G3: bob group msg 2');
    print('[ALICE-G] G3: received bob msg 2: $gotBobMsg2');

    final g3a3 = await sendGroup('G3: alice group msg 3');
    _writeJson('g3_alice_msg3', g3a3);
    _writeSignal('g3_alice_complete', 'ok');

    // ════════════════════════════════════════════════════════════════
    //  G4: Group offline → inbox → drain
    // ════════════════════════════════════════════════════════════════
    await _waitForSignal('g4_go');
    print('\n--- G4: Group offline inbox ---');
    await _waitForSignal('g4_bob_stopped');
    final g4 = await sendGroup('G4: group inbox msg');
    _writeJson('g4_alice_sent', g4);
    await _waitForSignal('g4_verified');

    // ════════════════════════════════════════════════════════════════
    //  G5: Group full lifecycle
    // ════════════════════════════════════════════════════════════════
    await _waitForSignal('g5_go');
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
    _writeSignal('g5_warm_done', 'ok');

    // Offline phase: wait for Bob stop, publish to inbox
    await _waitForSignal('g5_bob_stopped');
    gd = await sendGroup('G5: msg5 offline');
    g5Timeline.add({'n': 5, 'label': 'offline', ...gd});
    _writeSignal('g5_inbox_sent', 'ok');

    // Reconnect phase
    await _waitForSignal('g5_bob_restarted');
    gd = await sendGroup('G5: msg6 reconnect');
    g5Timeline.add({'n': 6, 'label': 'reconnect', ...gd});

    // Bidirectional: wait for Bob's msg7
    await _waitForSignal('g5_bob_msg7');
    final gotMsg7 = await waitForGroupMsg('G5: bob msg7');
    g5Timeline.add({'n': 7, 'label': 'recv', 'received': gotMsg7});

    // Warm again
    for (var i = 8; i <= 9; i++) {
      gd = await sendGroup('G5: msg$i warm');
      g5Timeline.add({'n': i, 'label': 'warm', ...gd});
    }
    _writeJson('g5_alice_complete', {'timeline': g5Timeline});

    // ════════════════════════════════════════════════════════════════
    //  G6: Group peer discovery timing
    // ════════════════════════════════════════════════════════════════
    await _waitForSignal('g6_go');
    print('\n--- G6: Group peer discovery timing ---');
    // Measure time to see Bob as a GossipSub peer
    // We already have the group; the timing was captured during initial join.
    // Re-measure by checking topic peer count now vs at join.
    _writeJson('g6_alice_done', {
      'peerDiscoveryMs': peerDiscoveryMs,
      'note': 'Time from Bob joined signal to GossipSub settle (includes 5s wait)',
    });

    // ════════════════════════════════════════════════════════════════
    //  G7: Group key rotation under traffic
    // ════════════════════════════════════════════════════════════════
    await _waitForSignal('g7_go');
    print('\n--- G7: Key rotation under traffic ---');

    // Send a pre-rotation message
    final g7Pre = await sendGroup('G7: pre-rotation msg');
    _writeJson('g7_pre_rotation', g7Pre);

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
    );
    g7RotSw.stop();
    print('[ALICE-G] G7: key rotated in ${g7RotSw.elapsedMilliseconds}ms (new key: ${newKey != null})');

    // Send a post-rotation message (uses new key)
    final g7Post = await sendGroup('G7: post-rotation msg');
    _writeJson('g7_alice_sent', {
      'rotationMs': g7RotSw.elapsedMilliseconds,
      'newKeyGeneration': newKey?.keyGeneration,
      'preRotation': g7Pre,
      'postRotation': g7Post,
    });
    await _waitForSignal('g7_verified');

    // ════════════════════════════════════════════════════════════════
    //  G8: 3-member group (Alice + Bob + Bob's second identity)
    //  Note: We can't easily add a 3rd simulator, so we measure with
    //  the existing 2 members — the GossipSub flood publish behavior
    //  is the same (WithFloodPublish sends to ALL peers).
    // ════════════════════════════════════════════════════════════════
    await _waitForSignal('g8_go');
    print('\n--- G8: Multi-member publish ---');
    final g8 = await sendGroup('G8: flood publish msg');
    _writeJson('g8_alice_sent', g8);
    await _waitForSignal('g8_verified');

    // ── Done ──
    await _waitForSignal('all_done');
    print('\n[ALICE-G] All group scenarios complete');

    await stack.teardown();
    _writeSignal('alice_done', 'ok');
  });
}
