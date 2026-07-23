import 'dart:async';

import 'package:flutter_app/core/services/pending_message_retrier.dart';
import 'package:flutter_app/features/groups/application/group_recovery_gate.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../features/contacts/domain/repositories/fake_contact_repository.dart';
import '../../features/conversation/domain/repositories/fake_message_repository.dart';
import '../../features/identity/domain/repositories/fake_identity_repository.dart';
import '../bridge/fake_bridge.dart';
import 'fake_p2p_service.dart';

void main() {
  test(
    'P269 restored not ready and account denied do no work before node ready coalesced recovery',
    () async {
      const notReady = NodeState(
        isStarted: true,
        peerId: 'peer-self',
        circuitAddresses: <String>[],
        relayState: 'connecting',
        sendCapabilityReady: false,
        inboxCapabilityReady: false,
      );
      const ready = NodeState(
        isStarted: true,
        peerId: 'peer-self',
        circuitAddresses: <String>['/p2p-circuit/relay'],
        relayState: 'online',
        sendCapabilityReady: true,
        inboxCapabilityReady: true,
      );

      final restored = StreamController<void>.broadcast(sync: true);
      final p2pService = FakeP2PService(initialState: notReady);
      var accountNetworkSideEffectsAllowed = false;
      var accountGateChecks = 0;
      var activeRecoveries = 0;
      var maximumActiveRecoveries = 0;
      final recoverySources = <String>[];
      final readyRecoveryStarted = Completer<void>();
      final releaseReadyRecovery = Completer<void>();
      final periodicRecoveryStarted = Completer<void>();

      Future<int> runSharedRecovery(String source) async {
        recoverySources.add(source);
        activeRecoveries++;
        if (activeRecoveries > maximumActiveRecoveries) {
          maximumActiveRecoveries = activeRecoveries;
        }
        try {
          if (source == 'node-ready') {
            if (!readyRecoveryStarted.isCompleted) {
              readyRecoveryStarted.complete();
            }
            await releaseReadyRecovery.future;
          } else if (!periodicRecoveryStarted.isCompleted) {
            periodicRecoveryStarted.complete();
          }
          return 1;
        } finally {
          activeRecoveries--;
        }
      }

      Future<int> runBehindAccountGate(String source) async {
        accountGateChecks++;
        if (!accountNetworkSideEffectsAllowed) return 0;
        return runSharedRecovery(source);
      }

      final retrier = PendingMessageRetrier(
        p2pService: p2pService,
        messageRepo: FakeMessageRepository(),
        identityRepo: FakeIdentityRepository(),
        contactRepo: FakeContactRepository(),
        bridge: FakeBridge(),
        networkRestoredSignal: restored.stream,
        retryDebounce: Duration.zero,
        networkRestoredDebounce: Duration.zero,
        periodicRetryInterval: const Duration(milliseconds: 40),
        groupContinuitySweepInterval: const Duration(hours: 1),
        retryFailedMessagesOverride: () async => 0,
        retryUnackedMessagesOverride: () async => 0,
        retryIncompleteGroupDownloadsFn: () =>
            runBehindAccountGate('node-ready'),
        retryIncompleteGroupDownloadsPeriodicFn: () =>
            runBehindAccountGate('periodic'),
      );
      addTearDown(() async {
        retrier.dispose();
        await restored.close();
        p2pService.dispose();
        groupRecoveryGate.resetForTest();
      });

      retrier.start();

      // The early OS-restored lane deliberately runs before node readiness,
      // but ordinary group downloads require the ready group-recovery pass.
      restored.add(null);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(accountGateChecks, 0);
      expect(recoverySources, isEmpty);

      // Node readiness may schedule a pass, but the account-migration gate is
      // still the final authority and must prevent coordinator work.
      p2pService.emitState(ready);
      await Future<void>.delayed(const Duration(milliseconds: 15));
      expect(accountGateChecks, 1);
      expect(recoverySources, isEmpty);

      // Re-arm a genuine readiness edge after account network work is allowed.
      p2pService.emitState(notReady);
      accountNetworkSideEffectsAllowed = true;
      p2pService.emitState(ready);
      await readyRecoveryStarted.future.timeout(const Duration(seconds: 1));
      expect(recoverySources, <String>['node-ready']);

      // Periodic ticks that overlap the ready pass must not start a second
      // recovery. Once the ready pass settles, the explicitly selected
      // periodic callback is allowed to run through the same authority seam.
      await Future<void>.delayed(const Duration(milliseconds: 90));
      expect(recoverySources, <String>['node-ready']);
      releaseReadyRecovery.complete();
      await periodicRecoveryStarted.future.timeout(const Duration(seconds: 1));

      expect(recoverySources, <String>['node-ready', 'periodic']);
      expect(maximumActiveRecoveries, 1);
      expect(activeRecoveries, 0);
    },
  );
}
