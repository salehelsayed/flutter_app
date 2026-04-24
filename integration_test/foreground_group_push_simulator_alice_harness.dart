// Foreground Group Push Simulator Smoke — Alice Harness
//
// Runs on simulator A and creates the shared group for the Report 71 smoke.
// This is a simulator approximation of the real-device checklist: it uses
// the real bridge / P2P / relay-backed group stack, but the foreground push
// itself is replayed by Bob through the app's foreground router instead of
// through APNs delivery.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/groups/application/create_group_with_members_use_case.dart';
import 'package:flutter_app/features/groups/application/send_group_message_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/p2p/presentation/widgets/connection_status_indicator.dart';

import 'group_multi_device_real_harness.dart';

const _sharedDir = String.fromEnvironment(
  'E2E_SHARED_DIR',
  defaultValue: '/tmp',
);
const _runId = String.fromEnvironment('SMOKE_RUN_ID', defaultValue: 'adhoc');
const _dbName = String.fromEnvironment(
  'E2E_DB_NAME',
  defaultValue: 'foreground_group_push_sim_alice.db',
);

String _sig(String name) => '$_sharedDir/fgpush_${_runId}_$name';

void _writeSignal(String name, String content) {
  File(_sig(name)).writeAsStringSync(content);
}

void _writeJson(String name, Map<String, dynamic> data) {
  _writeSignal(name, jsonEncode(data));
}

Future<void> _waitForSignal(
  String name, {
  Duration timeout = const Duration(minutes: 5),
}) async {
  final deadline = DateTime.now().add(timeout);
  final file = File(_sig(name));
  while (DateTime.now().isBefore(deadline)) {
    if (file.existsSync()) return;
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
  throw TimeoutException('Alice(fgpush): timed out waiting for $name');
}

Future<Map<String, dynamic>> _waitForJson(
  String name, {
  Duration timeout = const Duration(minutes: 5),
}) async {
  final deadline = DateTime.now().add(timeout);
  final file = File(_sig(name));
  while (DateTime.now().isBefore(deadline)) {
    if (file.existsSync()) {
      return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    }
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
  throw TimeoutException('Alice(fgpush): timed out waiting for json: $name');
}

Future<bool> _waitForOnline(
  dynamic service, {
  Duration timeout = const Duration(seconds: 60),
}) async {
  final sw = Stopwatch()..start();
  while (sw.elapsed < timeout) {
    if (healthFromState(service.currentState) == ConnectionHealth.online) {
      print('[ALICE-FGPUSH] Online after ${sw.elapsedMilliseconds}ms');
      return true;
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  return false;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  initializeSqliteForCurrentPlatform();

  testWidgets(
    'Alice(Foreground Group Push Simulator) — S1/S2',
    (tester) async {
      print('\n${'═' * 60}');
      print('  ALICE (FOREGROUND GROUP PUSH SIMULATOR)');
      print('${'═' * 60}\n');

      final stack = await setupGroupMultiDeviceStack(
        dbName: _dbName,
        username: 'AliceFgPush',
        cliPeerFixture: null,
      );
      await _waitForOnline(stack.p2pService);

      _writeJson('alice_identity.json', {
        'peerId': stack.identity.peerId,
        'publicKey': stack.identity.publicKey,
        'mlKemPublicKey': stack.identity.mlKemPublicKey,
      });
      _writeSignal('alice_ready', 'ok');

      final bobFixture = await _waitForJson('bob_identity.json');
      final bobPeerId = bobFixture['peerId'] as String;
      await stack.contactRepo.addContact(
        ContactModel(
          peerId: bobPeerId,
          publicKey: bobFixture['publicKey'] as String,
          rendezvous: '/dns4/relay/tcp/443/p2p/relay',
          username: 'BobFgPush',
          signature: 'sig-bob-fgpush',
          scannedAt: DateTime.now().toUtc().toIso8601String(),
          mlKemPublicKey: bobFixture['mlKemPublicKey'] as String?,
        ),
      );

      final bobContact = await stack.contactRepo.getContact(bobPeerId);
      final groupResult = await createGroupWithMembers(
        bridge: stack.bridge,
        groupRepo: stack.groupRepo,
        p2pService: stack.p2pService,
        identity: stack.identity,
        selectedContacts: [bobContact!],
        type: GroupType.chat,
        name: 'Foreground Group Push Smoke',
      );
      final groupId = groupResult.group.id;
      final group = await stack.groupRepo.getGroup(groupId);
      final keyInfo = await stack.groupRepo.getLatestKey(groupId);
      final members = await stack.groupRepo.getMembers(groupId);
      expect(group, isNotNull);
      expect(keyInfo, isNotNull);

      _writeJson(
        'group_fixture.json',
        buildGroupFixture(group: group!, keyInfo: keyInfo!, members: members),
      );

      await _waitForSignal(
        'bob_group_joined',
        timeout: const Duration(minutes: 8),
      );
      await Future<void>.delayed(const Duration(seconds: 5));

      Future<Map<String, dynamic>> sendScenarioMessage(
        String scenarioId,
      ) async {
        final text =
            '$scenarioId from Alice at '
            '${DateTime.now().toUtc().toIso8601String()}';
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
        final message = result.$2;
        expect(message, isNotNull);
        return {
          'scenarioId': scenarioId,
          'groupId': groupId,
          'text': text,
          'sendMs': sw.elapsedMilliseconds,
          'outcome': result.$1.name,
          'messageId': message!.id,
        };
      }

      await _waitForSignal('s1_go');
      await _waitForSignal(
        's1_bob_gap_ready',
        timeout: const Duration(minutes: 3),
      );
      await Future<void>.delayed(const Duration(seconds: 8));
      _writeJson('s1_alice_sent', await sendScenarioMessage('S1'));
      await _waitForSignal('s1_verified');

      await _waitForSignal('s2_go');
      await _waitForSignal(
        's2_bob_live_ready',
        timeout: const Duration(minutes: 3),
      );
      await Future<void>.delayed(const Duration(seconds: 8));
      _writeJson('s2_alice_sent', await sendScenarioMessage('S2'));
      await _waitForSignal('s2_verified');

      await _waitForSignal('all_done');
      await stack.teardown();
      _writeSignal('alice_done', 'ok');
    },
    timeout: const Timeout(Duration(minutes: 25)),
  );
}
