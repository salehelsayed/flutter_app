import 'dart:async';

import 'package:flutter_app/app/lifecycle/handle_app_resumed.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_test/flutter_test.dart';

import '../bridge/fake_bridge.dart';
import '../services/fake_p2p_service.dart';

/// FDC-05 — Parallel (not serial) resume re-prime.
///
/// HEAD ran the resume re-prime strictly serially:
///   checkHealth → performImmediateHealthCheck → push → **await drainOfflineInbox**
/// so the first post-resume send sat behind a multi-second awaited inbox drain.
///
/// The fix kicks the relay/mDNS re-prime off, fires the inbox drain
/// **unawaited** (with its own catchError for fault isolation), emits
/// `APP_LIFECYCLE_RESUME_REPRIME_PARALLEL`, and awaits only the bounded
/// re-prime — while keeping `bridge.checkHealth()` first and the Step-8 outbound
/// recovery sweep strictly ordered.
void main() {
  late FakeBridge fakeBridge;
  late FakeP2PService fakeP2PService;
  late List<Map<String, dynamic>> flowEvents;

  setUp(() {
    fakeBridge = FakeBridge();
    fakeP2PService = FakeP2PService(
      initialState: const NodeState(
        isStarted: true,
        peerId: 'my-peer',
        circuitAddresses: ['/p2p-circuit/addr1'],
      ),
    );
    flowEvents = <Map<String, dynamic>>[];
    debugSetFlowEventSink(flowEvents.add);
  });

  tearDown(() {
    debugSetFlowEventSink(null);
    fakeP2PService.dispose();
  });

  List<Map<String, dynamic>> eventsNamed(String name) => flowEvents
      .where((event) => event['event'] == name)
      .toList(growable: false);

  // Records each Step-8 callback into a shared order list (mirrors the existing
  // handle_app_resumed_upload_ordering_test pattern).
  ({
    List<String> order,
    Future<int> Function() recoverStuck,
    Future<int> Function() retryUploads,
    Future<int> Function() retryFailed,
    Future<int> Function() retryUnacked,
    Future<int> Function() verifyCustody,
    Future<int> Function() retryIntros,
  })
  wireStep8Sweep() {
    final order = <String>[];
    Future<int> rec(String name) async {
      order.add(name);
      return 0;
    }

    return (
      order: order,
      recoverStuck: () => rec('recoverStuckSendingMessages'),
      retryUploads: () => rec('retryIncompleteUploads'),
      retryFailed: () => rec('retryFailedMessages'),
      retryUnacked: () => rec('retryUnackedMessages'),
      verifyCustody: () => rec('verifyInboxCustody'),
      retryIntros: () => rec('retryPendingIntroductionDeliveries'),
    );
  }

  const expectedSweepOrder = <String>[
    'recoverStuckSendingMessages',
    'retryIncompleteUploads',
    'retryFailedMessages',
    'retryUnackedMessages',
    'verifyInboxCustody',
    'retryPendingIntroductionDeliveries',
  ];

  group('handleAppResumed — FDC-05 parallel resume re-prime', () {
    // TC-05-01 — resume future does NOT await the inbox drain.
    test('resume completes while inbox drain is still in flight', () async {
      // A drain that hangs forever (a Completer the test never completes — a
      // Completer leaves no pending Timer, unlike Future.delayed).
      final holdDrain = Completer<void>();
      fakeP2PService.onDrainOfflineInbox = () => holdDrain.future;

      // On HEAD `await drainOfflineInbox()` would hang the resume future; the
      // timeout converts that hang into a clean RED rather than a suite stall.
      final result = await handleAppResumed(
        bridge: fakeBridge,
        p2pService: fakeP2PService,
      ).timeout(const Duration(seconds: 3));

      expect(result, isTrue, reason: 'resume returns bridgeOk, not blocked');
      expect(
        fakeP2PService.drainOfflineInboxCallCount,
        1,
        reason: 'the drain WAS started (fire-and-forget), not skipped',
      );
      expect(
        holdDrain.isCompleted,
        isFalse,
        reason: 'resume did not block waiting for the drain to finish',
      );
    });

    test(
      'dropped-wake ownership suppresses the ordinary direct drain',
      () async {
        final result = await handleAppResumed(
          bridge: fakeBridge,
          p2pService: fakeP2PService,
          skipDirectInboxDrain: true,
        );

        expect(result, isTrue);
        expect(fakeP2PService.performImmediateHealthCheckCallCount, 1);
        expect(fakeP2PService.drainOfflineInboxCallCount, 0);
      },
    );

    // TC-05-02 — re-prime and drain OVERLAP (not strictly serial).
    test('inbox drain fires before performImmediateHealthCheck resolves', () async {
      final reprimeEntered = Completer<void>();
      final holdReprime = Completer<void>();
      fakeP2PService.onPerformImmediateHealthCheck = () {
        if (!reprimeEntered.isCompleted) reprimeEntered.complete();
        // Held open — never completes — so the re-prime is still pending while
        // we observe whether the drain has fired.
        return holdReprime.future;
      };

      // Start the resume but do NOT await it (the re-prime is held open).
      unawaited(
        handleAppResumed(bridge: fakeBridge, p2pService: fakeP2PService),
      );

      // Resume once the re-prime has been entered. In the GREEN parallel shape,
      // the drain kick-off + the resume future parking on `await reprime` run
      // synchronously after the re-prime kick-off; one microtask hop guarantees
      // they have executed before we assert.
      await reprimeEntered.future;
      await Future<void>.microtask(() {});

      expect(fakeP2PService.performImmediateHealthCheckCallCount, 1);
      expect(
        fakeP2PService.drainOfflineInboxCallCount,
        1,
        reason:
            'drain overlaps the still-pending re-prime; on HEAD it is 0 '
            'because the drain only fires after the awaited health check',
      );
      expect(holdReprime.isCompleted, isFalse);
    });

    // TC-05-03 — distinct parallel-shape flow event emitted.
    test('emits APP_LIFECYCLE_RESUME_REPRIME_PARALLEL', () async {
      await handleAppResumed(bridge: fakeBridge, p2pService: fakeP2PService);

      expect(
        eventsNamed('APP_LIFECYCLE_RESUME_REPRIME_PARALLEL'),
        hasLength(1),
        reason: 'the parallel shape is observable via its own discriminator',
      );
      // Both serial and parallel shapes still end with COMPLETE — the new event
      // is the discriminator that the parallel path ran.
      expect(eventsNamed('APP_LIFECYCLE_RESUME_COMPLETE'), hasLength(1));
    });

    // TC-05-04 — Step-8 sweep reached + ordered DESPITE an in-flight drain.
    test('recovery sweep runs in order while drain is still pending', () async {
      final holdDrain = Completer<void>();
      fakeP2PService.onDrainOfflineInbox = () => holdDrain.future;

      final sweep = wireStep8Sweep();

      final result = await handleAppResumed(
        bridge: fakeBridge,
        p2pService: fakeP2PService,
        recoverStuckSendingMessagesFn: sweep.recoverStuck,
        retryIncompleteUploadsFn: sweep.retryUploads,
        retryFailedMessagesFn: sweep.retryFailed,
        retryUnackedMessagesFn: sweep.retryUnacked,
        verifyInboxCustodyFn: sweep.verifyCustody,
        retryPendingIntroductionDeliveriesFn: sweep.retryIntros,
      ).timeout(const Duration(seconds: 3));

      expect(result, isTrue);
      expect(
        sweep.order,
        expectedSweepOrder,
        reason: 'outbound sweep reached AND strictly ordered while drain pends',
      );
      expect(
        holdDrain.isCompleted,
        isFalse,
        reason: 'the sweep ran without waiting for the drain to finish',
      );
    });

    // TC-05-05 — a throwing drain no longer aborts resume / no longer skips the
    // sweep (fault isolation).
    test(
      'drain error is isolated, recovery sweep still runs, resume returns healthy',
      () async {
        fakeP2PService.throwOnDrainInbox = true;

        final sweep = wireStep8Sweep();

        final result = await handleAppResumed(
          bridge: fakeBridge,
          p2pService: fakeP2PService,
          recoverStuckSendingMessagesFn: sweep.recoverStuck,
          retryIncompleteUploadsFn: sweep.retryUploads,
          retryFailedMessagesFn: sweep.retryFailed,
          retryUnackedMessagesFn: sweep.retryUnacked,
          verifyInboxCustodyFn: sweep.verifyCustody,
          retryPendingIntroductionDeliveriesFn: sweep.retryIntros,
        ).timeout(const Duration(seconds: 3));

        expect(result, isTrue, reason: 'drain throw must not abort the resume');
        expect(sweep.order, expectedSweepOrder);

        // The unawaited drain's catchError runs as a microtask after the
        // synchronous throw; pump so the isolated error event is captured.
        await Future<void>.microtask(() {});
        expect(
          eventsNamed('APP_LIFECYCLE_RESUME_DRAIN_ERROR'),
          hasLength(1),
          reason: 'isolated drain failure has its own discriminator',
        );
        expect(
          eventsNamed('APP_LIFECYCLE_RESUME_ERROR'),
          isEmpty,
          reason: 'a drain throw must NOT surface as a whole-resume abort',
        );
      },
    );

    // TC-05-06 — bridge.checkHealth still runs first; the drain is not started
    // before the bridge is healthy (preservation lock).
    test('bridge health check precedes the parallel re-prime', () async {
      final callOrder = <String>[];
      fakeBridge.onCheckHealth = () async {
        // Record on COMPLETION (after a microtask yield) so an over-
        // parallelization mutation that starts checkHealth concurrently with the
        // re-prime/drain is exposed: those start-time records would land before
        // this completion record, knocking checkHealth off the front.
        await Future<void>.microtask(() {});
        callOrder.add('checkHealth');
      };
      fakeP2PService.onPerformImmediateHealthCheck = () async {
        callOrder.add('performImmediateHealthCheck');
      };
      fakeP2PService.onDrainOfflineInbox = () async {
        callOrder.add('drainOfflineInbox');
      };

      await handleAppResumed(bridge: fakeBridge, p2pService: fakeP2PService);

      expect(callOrder, isNotEmpty);
      expect(callOrder.first, 'checkHealth');
      expect(
        callOrder.indexOf('checkHealth'),
        lessThan(callOrder.indexOf('performImmediateHealthCheck')),
        reason: 'bridge must be healthy before the relay/mDNS re-prime',
      );
      expect(
        callOrder.indexOf('checkHealth'),
        lessThan(callOrder.indexOf('drainOfflineInbox')),
        reason: 'bridge must be healthy before the inbox drain',
      );
    });
  });
}
