/// Real-runtime device proof for Finding 05 Phase 1 (harden recovery
/// orchestration). The host unit suites prove the logic under `fakeAsync`;
/// this proof validates the SAME behavior on the real iOS Dart event loop with
/// real `Future`s and real `Timer`s — which matters here because the gate's
/// serialization is async-ordering-sensitive (the host impl had to avoid
/// chaining off a root-zone `Future`, a hazard only async semantics expose).
///
/// Proves:
///   * P1.1 — `GroupRecoveryGate.run()` serializes overlapping passes (the
///     second body starts only after the first completes) and reports
///     `isGroupRecoveryInProgress()` across the whole queued+active window.
///   * P1.1 — `runWithGroupRecoveryGateOrSkip` skips (returns null) while a
///     pass holds the gate, and a thrown pass still releases the chain.
///   * P1.2 + P1.3 — a `PendingMessageRetrier` wired with the production-style
///     provider `() => isGroupRecoveryInProgress()` SUPPRESSES its group pass
///     while a real recovery pass holds the gate, then RESUMES once released.
@Tags(['device'])
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:flutter_app/core/services/pending_message_retrier.dart';
import 'package:flutter_app/features/groups/application/group_recovery_gate.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';

import '../test/core/bridge/fake_bridge.dart';
import '../test/core/services/fake_p2p_service.dart';
import '../test/features/contacts/domain/repositories/fake_contact_repository.dart';
import '../test/features/conversation/domain/repositories/fake_message_repository.dart';
import '../test/features/identity/domain/repositories/fake_identity_repository.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Finding 05 Phase 1 — recovery gate serialization (real runtime)', () {
    setUp(() => groupRecoveryGate.resetForTest());
    tearDown(() => groupRecoveryGate.resetForTest());

    testWidgets('P1.1 run() serializes overlapping passes on real async', (
      tester,
    ) async {
      final order = <String>[];
      final firstStarted = Completer<void>();
      final releaseFirst = Completer<void>();

      final f1 = runWithGroupRecoveryGate(() async {
        order.add('first-start');
        firstStarted.complete();
        await releaseFirst.future;
        order.add('first-end');
      });
      final f2 = runWithGroupRecoveryGate(() async {
        order.add('second');
      });

      await firstStarted.future;
      // Second pass is queued, not running, while the first holds the gate.
      expect(order, <String>['first-start']);
      expect(isGroupRecoveryInProgress(), isTrue);
      expect(groupRecoveryGate.activeDepthListenable.value, 2);

      releaseFirst.complete();
      await Future.wait(<Future<void>>[f1, f2]);

      expect(order, <String>['first-start', 'first-end', 'second']);
      expect(isGroupRecoveryInProgress(), isFalse);
      expect(groupRecoveryGate.activeDepthListenable.value, 0);
    });

    testWidgets(
      'P1.1 OrSkip skips while busy; a thrown pass releases the chain',
      (tester) async {
        final release = Completer<void>();
        final held = runWithGroupRecoveryGate(() async {
          await release.future;
        });
        expect(isGroupRecoveryInProgress(), isTrue);

        var skippedRan = false;
        final skipped = runWithGroupRecoveryGateOrSkip(() async {
          skippedRan = true;
        });
        expect(skipped, isNull);

        release.complete();
        await held;
        expect(skippedRan, isFalse);
        expect(isGroupRecoveryInProgress(), isFalse);

        // A thrown pass must not wedge the chain.
        await expectLater(
          runWithGroupRecoveryGate(() async {
            throw StateError('boom');
          }),
          throwsA(isA<StateError>()),
        );
        var recovered = false;
        await runWithGroupRecoveryGate(() async {
          recovered = true;
        });
        expect(recovered, isTrue);
        expect(isGroupRecoveryInProgress(), isFalse);
      },
    );

    testWidgets(
      'P1.2+P1.3 retrier suppresses its group pass while recovery holds the '
      'gate, then resumes after release (real timers)',
      (tester) async {
        const onlineState = NodeState(
          isStarted: true,
          peerId: 'my-peer',
          circuitAddresses: ['/addr'],
          needsGroupRecovery: false,
        );

        var rejoinCount = 0;
        var drainCount = 0;
        final hold = Completer<void>();

        // A real recovery pass (startup/resume analog) holds the gate.
        final heldPass = runWithGroupRecoveryGate(() => hold.future);
        expect(isGroupRecoveryInProgress(), isTrue);

        final p2pService = FakeP2PService(initialState: onlineState);
        final retrier = PendingMessageRetrier(
          p2pService: p2pService,
          messageRepo: FakeMessageRepository(),
          identityRepo: FakeIdentityRepository(),
          contactRepo: FakeContactRepository(),
          bridge: FakeBridge(),
          rejoinGroupTopicsFn: () async {
            rejoinCount += 1;
          },
          drainGroupOfflineInboxFn: () async {
            drainCount += 1;
          },
          // Exactly the main.dart wiring (with _isResuming false here).
          retryDebounce: const Duration(milliseconds: 40),
        );
        addTearDown(() {
          retrier.dispose();
          p2pService.dispose();
        });
        retrier.setExternalRecoveryInProgressProvider(
          () => isGroupRecoveryInProgress(),
        );
        retrier.start();

        // Give the real debounce timer ample time to fire and be suppressed.
        await Future<void>.delayed(const Duration(milliseconds: 300));
        expect(
          rejoinCount,
          0,
          reason: 'suppressed while recovery holds the gate',
        );
        expect(drainCount, 0);

        // Release the recovery pass; gate goes idle.
        hold.complete();
        await heldPass;
        expect(isGroupRecoveryInProgress(), isFalse);

        // A fresh online->needsGroupRecovery edge re-triggers the sweep, which
        // must now run (gate released).
        p2pService.emitState(
          const NodeState(
            isStarted: true,
            peerId: 'my-peer',
            circuitAddresses: ['/addr'],
            needsGroupRecovery: true,
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 300));
        expect(
          rejoinCount,
          greaterThanOrEqualTo(1),
          reason: 'retrier resumes once the gate is released',
        );
        expect(drainCount, greaterThanOrEqualTo(1));
      },
    );
  });
}
