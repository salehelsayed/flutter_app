// Integration test: Phase 6 background reconnect smoke test.
//
// Runs on a REAL device with the real Go bridge and relay server.
// Exercises the Phase 6 user-visible contract:
//   1. Start node -> wait for dotted relay-ready badge (`Online.`)
//   2. Disconnect relay peer -> lose dotted readiness
//   3. Start a fresh readiness proof window
//   4. Prove send and inbox success while relay is still absent -> plain `Online`
//   5. Reconnect relay -> dotted `Online.` returns
//
// Run on device:
//   flutter test integration_test/background_reconnect_test.dart -d <DEVICE_ID>
@Tags(['device'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:flutter_app/core/bridge/go_bridge_client.dart';
import 'package:flutter_app/core/bridge/p2p_bridge_client.dart';
import 'package:flutter_app/core/services/p2p_service_impl.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';

import '../test/shared/fakes/in_memory_inbox_staging_repository.dart';
import '_support/canonical_runtime_device_test_lease.dart';
import '_support/node_readiness.dart';

final _relayPeerId = defaultRendezvousAddress.split('/p2p/').last;

bool _isSendable(NodeState state) {
  return state.badgeReadinessState == BadgeReadinessState.online ||
      state.badgeReadinessState == BadgeReadinessState.onlineDotted ||
      state.badgeReadinessState == BadgeReadinessState.onlineDirect;
}

bool _isPlainOnline(NodeState state) {
  return state.badgeReadinessState == BadgeReadinessState.online;
}

bool _isRelayReady(NodeState state) {
  return state.badgeReadinessState == BadgeReadinessState.onlineDotted;
}

String _badgeLabel(NodeState state) {
  return switch (state.badgeReadinessState) {
    BadgeReadinessState.offline => 'Offline',
    BadgeReadinessState.connecting => 'Connecting',
    BadgeReadinessState.online => 'Online',
    BadgeReadinessState.onlineDotted => 'Online.',
    // FDC-14: exhaustiveness arm for the new tier (mirrors the indicator's
    // _labelForBadgeState). Inert until FDC-14b wires the directReady producer.
    BadgeReadinessState.onlineDirect => 'Online ✦',
  };
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final runtimeLease = CanonicalRuntimeDeviceTestLease(
    binding: 'background-reconnect-device-test',
  );
  setUpAll(runtimeLease.acquire);
  tearDownAll(runtimeLease.release);

  if (Platform.isLinux || Platform.isMacOS || Platform.isWindows) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  testWidgets(
    'Background reconnect exposes plain Online before dotted Online.',
    (tester) async {
      print('\n');
      print('═' * 60);
      print('  PHASE 6 BACKGROUND RECONNECT SMOKE');
      print('═' * 60);
      print('');

      final bridge = GoBridgeClient();
      await bridge.initialize();

      final genResponse = await bridge.send(
        jsonEncode({'cmd': 'identity.generate', 'payload': {}}),
      );
      final genResult = jsonDecode(genResponse) as Map<String, dynamic>;
      expect(genResult['ok'], true, reason: 'identity.generate should succeed');
      final identity = genResult['identity'] as Map<String, dynamic>;
      final peerId = identity['peerId'] as String;
      final privateKey = identity['privateKey'] as String;

      final p2pService = P2PServiceImpl(
        bridge: bridge,
        inboxStagingRepository: InMemoryInboxStagingRepository(),
      );

      final stateLog = <String>[];
      NodeState? observedPlainOnline;
      StreamSubscription<NodeState>? resumeStateSub;
      final startTime = DateTime.now();
      final stateSub = p2pService.stateStream.listen((state) {
        final elapsed = DateTime.now().difference(startTime).inMilliseconds;
        final entry =
            '  +${elapsed}ms  badge=${_badgeLabel(state)} '
            'sendReady=${state.sendCapabilityReady} '
            'inboxReady=${state.inboxCapabilityReady} '
            'relayReady=${state.relayReady} '
            'circuits=${state.circuitAddresses.length}';
        stateLog.add(entry);
        print('[STATE] $entry');
      });

      try {
        print('[PHASE 1] Starting node...');
        final started = await p2pService.startNode(privateKey, peerId);
        if (!started) {
          fail('P2P node failed to start');
        }

        final reachedRelayReady = await waitFor(
          () => _isRelayReady(p2pService.currentState),
          timeout: const Duration(seconds: 30),
          label: 'Initial Online.',
        );
        expect(
          reachedRelayReady,
          isTrue,
          reason: 'Node should reach Online. before the reconnect scenario',
        );
        print(
          '[PHASE 1] Initial badge: ${_badgeLabel(p2pService.currentState)}',
        );

        print('');
        print('─' * 60);
        print(
          '[PHASE 2] Disconnecting relay peer to simulate background loss...',
        );
        // Automatic relay recovery can restore relay-ready before the send
        // proof lands; that attempt cannot show plain Online by design. Repeat
        // the precondition (relay down, fresh proof window) a bounded number
        // of times. A genuine missing plain Online still fails below.
        const maxProofWindowAttempts = 3;
        var disconnectMs = 0;
        var sendMs = 0;
        var inboxMs = 0;
        var reachedPlainOnline = false;
        for (var attempt = 1; attempt <= maxProofWindowAttempts; attempt++) {
          await resumeStateSub?.cancel();
          resumeStateSub = null;
          observedPlainOnline = null;
          final disconnectStart = DateTime.now();
          final disconnectResponse = await bridge.send(
            jsonEncode({
              'cmd': 'peer:disconnect',
              'payload': {'peerId': _relayPeerId},
            }),
          );
          final disconnectResult =
              jsonDecode(disconnectResponse) as Map<String, dynamic>;
          print(
            '[PHASE 2] attempt $attempt disconnect result: '
            '${disconnectResult['ok']}',
          );

          final relayDropped = await waitFor(
            () => !_isRelayReady(p2pService.currentState),
            timeout: const Duration(seconds: 15),
            label: 'Relay-ready badge dropped',
          );
          expect(
            relayDropped,
            isTrue,
            reason: 'Disconnect should remove dotted relay-ready state',
          );
          disconnectMs = DateTime.now()
              .difference(disconnectStart)
              .inMilliseconds;
          print('[PHASE 2] Relay-ready removed in ${disconnectMs}ms');
          print(
            '[PHASE 2] Badge after disconnect: '
            '${_badgeLabel(p2pService.currentState)}',
          );

          print('');
          print('─' * 60);
          print(
            '[PHASE 3] attempt $attempt: fresh proof window without '
            'relay-ready...',
          );
          p2pService.markResumeStarted();
          p2pService.noteTransportSessionReset(
            trigger: 'background_reconnect_phase6_smoke',
          );
          // Subscribe after the reset so startup/previous-window states cannot
          // satisfy this proof. Automatic relay recovery can replace plain
          // Online between the 500 ms polling ticks; retain the actual emitted
          // snapshot, and record whether relay-ready returned before send proof.
          var relayReturnedBeforeSendProof = false;
          resumeStateSub = p2pService.stateStream.listen((state) {
            if (_isPlainOnline(state)) observedPlainOnline ??= state;
            if (_isRelayReady(state) && !state.sendCapabilityReady) {
              relayReturnedBeforeSendProof = true;
            }
          });

          final sendStart = DateTime.now();
          final stored = await p2pService.storeInInbox(
            peerId,
            jsonEncode({
              'type': 'phase6_probe',
              'version': '1',
              'timestamp': DateTime.now().toUtc().toIso8601String(),
            }),
          );
          sendMs = DateTime.now().difference(sendStart).inMilliseconds;
          expect(
            stored,
            isTrue,
            reason: 'Inbox-backed send proof should succeed',
          );
          print('[PHASE 3] storeInInbox succeeded in ${sendMs}ms');
          print(
            '[PHASE 3] Badge after send proof: '
            '${_badgeLabel(p2pService.currentState)}',
          );

          final inboxStart = DateTime.now();
          final inboxMessages = await p2pService.retrieveInbox();
          inboxMs = DateTime.now().difference(inboxStart).inMilliseconds;
          print('[PHASE 3] retrieveInbox succeeded in ${inboxMs}ms');
          print('[PHASE 3] Retrieved ${inboxMessages.length} messages');

          reachedPlainOnline = await waitFor(
            () => observedPlainOnline != null,
            timeout: const Duration(seconds: 15),
            label: 'Plain Online before dotted reconnect',
          );
          if (reachedPlainOnline ||
              !relayReturnedBeforeSendProof ||
              attempt == maxProofWindowAttempts) {
            break;
          }
          print(
            '[PHASE 3] attempt $attempt: relay-ready returned before the send '
            'proof, so plain Online could not be exercised; repeating.',
          );
        }
        expect(
          reachedPlainOnline,
          isTrue,
          reason:
              'The device smoke must surface plain Online after truthful send '
              'and inbox proof while relay-ready is still absent.',
        );
        final plainOnline = observedPlainOnline!;
        expect(_isSendable(plainOnline), isTrue);
        expect(plainOnline.sendCapabilityReady, isTrue);
        expect(plainOnline.inboxCapabilityReady, isTrue);
        expect(_isRelayReady(plainOnline), isFalse);
        print(
          '[PHASE 3] Plain usable badge observed: ${_badgeLabel(plainOnline)}',
        );

        print('');
        print('─' * 60);
        print('[PHASE 4] Reconnecting relay to recover dotted readiness...');
        final reconnectStart = DateTime.now();
        final reconnectResponse = await bridge.send(
          jsonEncode({'cmd': 'relay:reconnect', 'payload': {}}),
        );
        final reconnectResult =
            jsonDecode(reconnectResponse) as Map<String, dynamic>;
        print('[PHASE 4] relay:reconnect result: ${reconnectResult['ok']}');

        final reachedDottedOnline = await waitFor(
          () => _isRelayReady(p2pService.currentState),
          timeout: const Duration(seconds: 30),
          label: 'Relay-ready Online. restored',
        );
        final reconnectMs = DateTime.now()
            .difference(reconnectStart)
            .inMilliseconds;
        expect(
          reachedDottedOnline,
          isTrue,
          reason:
              'After the plain Online window, relay reconnect should restore '
              'the dotted Online. badge.',
        );

        print('');
        print('═' * 60);
        print('  RESULTS');
        print('═' * 60);
        print('');
        print('  Relay disconnect to non-dotted: ${disconnectMs}ms');
        print('  Plain Online send proof:        ${sendMs}ms');
        print('  Plain Online inbox proof:       ${inboxMs}ms');
        print('  Relay reconnect to Online.:     ${reconnectMs}ms');
        print('');
        print('  Final badge: ${_badgeLabel(p2pService.currentState)}');
        print(
          '  Final sendReady: ${p2pService.currentState.sendCapabilityReady}',
        );
        print(
          '  Final inboxReady: ${p2pService.currentState.inboxCapabilityReady}',
        );
        print('  Final relayReady: ${p2pService.currentState.relayReady}');
        print('');
        print('  State transition log:');
        for (final entry in stateLog) {
          print(entry);
        }
        print('');
      } finally {
        await resumeStateSub?.cancel();
        await stateSub.cancel();
        await p2pService.stopNode();
        p2pService.dispose();
        bridge.dispose();
      }
    },
    skip: _shouldSkipBackgroundReconnectSmoke(),
  );
}

bool _shouldSkipBackgroundReconnectSmoke() {
  if (Platform.isMacOS || Platform.isLinux || Platform.isWindows) {
    return true;
  }
  if (!Platform.isIOS) {
    return false;
  }
  if (Directory.systemTemp.path.contains('CoreSimulator')) {
    return true;
  }
  final env = Platform.environment;
  return env.containsKey('SIMULATOR_DEVICE_NAME') ||
      env.containsKey('SIMULATOR_UDID') ||
      env.containsKey('SIMULATOR_HOST_HOME') ||
      env.containsKey('IPHONE_SIMULATOR_ROOT');
}
