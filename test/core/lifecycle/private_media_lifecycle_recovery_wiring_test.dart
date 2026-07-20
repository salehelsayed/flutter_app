import 'dart:io';

import 'package:flutter_app/core/lifecycle/handle_app_resumed.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_test/flutter_test.dart';

import '../bridge/fake_bridge.dart';
import '../services/fake_p2p_service.dart';

void main() {
  late FakeBridge bridge;
  late FakeP2PService p2pService;

  setUp(() {
    bridge = FakeBridge();
    p2pService = FakeP2PService(
      initialState: const NodeState(
        isStarted: true,
        peerId: 'private-recovery-peer',
      ),
    );
  });

  tearDown(() {
    p2pService.dispose();
  });

  test(
    'resume runs local private recovery before a denied network gate',
    () async {
      final order = <String>[];

      final result = await handleAppResumed(
        bridge: bridge,
        p2pService: p2pService,
        privateMediaLifecycleRecoveryFn: () async {
          order.add('private-recovery');
        },
        accountMigrationNetworkGate:
            ({String? peerId, required String operation}) async {
              order.add('network-gate');
              return false;
            },
      );

      expect(result, isFalse);
      expect(order, ['private-recovery', 'network-gate']);
      expect(
        bridge.checkHealthCallCount,
        0,
        reason:
            'a denied gate still permits local recovery but no network work',
      );
    },
  );

  test(
    'private recovery failure is isolated and later resume work continues',
    () async {
      final order = <String>[];

      final result = await handleAppResumed(
        bridge: bridge,
        p2pService: p2pService,
        privateMediaLifecycleRecoveryFn: () async {
          order.add('private-recovery');
          throw StateError('injected local recovery failure');
        },
        accountMigrationNetworkGate:
            ({String? peerId, required String operation}) async {
              order.add('network-gate');
              return true;
            },
      );

      expect(result, isTrue);
      expect(order, ['private-recovery', 'network-gate']);
      expect(bridge.checkHealthCallCount, 1);
      expect(p2pService.performImmediateHealthCheckCallCount, 1);
    },
  );

  test(
    'production uses one engine per private lane with shared recovery and scheduler lifecycle',
    () {
      final source = File('lib/main.dart').readAsStringSync();
      expect(
        RegExp(
          r'final directPrivateMediaLifecycleEngine =\s*PrivateMediaLifecycleEngine\(',
        ).allMatches(source),
        hasLength(1),
        reason: 'the direct lane must share one durable engine instance',
      );
      expect(
        'GroupPrivateMediaLifecycleEngine('.allMatches(source),
        hasLength(1),
        reason: 'the group lane must share one durable engine instance',
      );
      expect(
        source,
        contains(
          'final directPrivateMediaLifecycleEngine = PrivateMediaLifecycleEngine(',
        ),
      );
      expect(
        source,
        contains('directPrivateMediaLifecycleEngine.reconcileLocalLifecycle()'),
      );
      expect(
        source,
        contains('groupPrivateMediaLifecycleEngine.reconcileLocalLifecycle()'),
      );
      expect(
        source,
        contains(
          'dbLoadOutgoingDirectPrivateCommittedPendingCleanupCandidates:',
        ),
        reason:
            'production must wire the bounded real-repository cleanup query',
      );
      expect(
        'retryDirectPrivateCommittedPendingCleanup('.allMatches(source),
        hasLength(1),
        reason:
            'cold start and every real resume must share one cleanup callback',
      );
      expect(source, contains('privateMediaLifecycleRecoveryFn:'));
      expect(source, contains('widget.privateMediaLifecycleRecovery'));
      expect(source, contains('PrivateMediaLifecycleForegroundRuntime('));
      expect(
        source,
        allOf(
          contains('isForeground: () =>'),
          contains(
            'WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed',
          ),
        ),
        reason: 'a hidden/paused cold launch must never arm the expiry timer',
      );
      expect(
        source,
        contains('startScheduler: privateMediaExpiryScheduler.start'),
      );
      expect(
        source,
        contains('widget.stopPrivateMediaExpiryScheduler?.call()'),
      );
      expect(
        source,
        contains('widget.disposePrivateMediaExpiryScheduler?.call()'),
      );
      expect(
        source,
        isNot(contains('widget.startPrivateMediaExpiryScheduler?.call()')),
        reason: 'resume completion cannot unconditionally undo a later pause',
      );

      final sharedLocalRecovery = source.indexOf(
        'recoverLocalLifecycle: () async',
      );
      final directRecovery = source.indexOf(
        'directPrivateMediaLifecycleEngine.reconcileLocalLifecycle()',
        sharedLocalRecovery,
      );
      final committedPendingCleanup = source.indexOf(
        'retryDirectPrivateCommittedPendingCleanup(',
        sharedLocalRecovery,
      );
      final groupRecovery = source.indexOf(
        'groupPrivateMediaLifecycleEngine.reconcileLocalLifecycle()',
        sharedLocalRecovery,
      );
      expect(sharedLocalRecovery, isNonNegative);
      expect(directRecovery, greaterThan(sharedLocalRecovery));
      expect(committedPendingCleanup, greaterThan(directRecovery));
      expect(
        groupRecovery,
        greaterThan(committedPendingCleanup),
        reason:
            'pending cleanup load failures are isolated before group recovery',
      );

      final runAppMark = source.indexOf(
        "StartupTiming.instance.mark('run_app_called')",
      );
      expect(runAppMark, isNonNegative);
      final coldRecovery = source.indexOf(
        'unawaited(ensurePrivateMediaColdRecovery());',
        runAppMark,
      );
      expect(coldRecovery, greaterThan(runAppMark));

      final liveServices = source.indexOf(
        'Future<void> startLiveServices() async',
      );
      final recoveryGate = source.indexOf(
        'await ensurePrivateMediaColdRecovery();',
        liveServices,
      );
      final networkGate = source.indexOf(
        "allowsAccountRuntimeNetworkSideEffects('live_services_start')",
        liveServices,
      );
      expect(liveServices, isNonNegative);
      expect(recoveryGate, greaterThan(liveServices));
      expect(networkGate, greaterThan(recoveryGate));

      final resumeMethod = source.indexOf('Future<void> _onResumed() async');
      final beginPrivateResume = source.indexOf(
        'widget.privateMediaLifecycleRecovery?.call()',
        resumeMethod,
      );
      final broadResumeGuard = source.indexOf('if (_isResuming)', resumeMethod);
      expect(beginPrivateResume, greaterThan(resumeMethod));
      expect(
        broadResumeGuard,
        greaterThan(beginPrivateResume),
        reason:
            'a second real resume must refresh private recovery even while '
            'the broad network resume is coalesced',
      );
    },
  );
}
