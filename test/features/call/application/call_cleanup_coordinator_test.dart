import 'dart:async';

import 'package:flutter_app/features/call/application/call_cleanup_coordinator.dart';
import 'package:flutter_app/features/call/domain/call_end_reason.dart';
import 'package:flutter_app/features/call/domain/call_id.dart';
import 'package:flutter_app/features/call/domain/call_session_snapshot.dart';
import 'package:flutter_app/features/call/domain/call_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final snapshot = CallSessionSnapshot.active(
    callId: CallId.parse('44444444-4444-4444-8444-444444444444'),
    contactPeerId: 'private-contact-identity',
    direction: CallDirection.outgoing,
    state: CallState.ended,
    callerAccountPeerId: 'local-account',
    callerDeviceId: 'local-device',
    startedAt: DateTime.utc(2026, 8, 30, 12),
    endedAt: DateTime.utc(2026, 8, 30, 12, 0, 5),
    endReason: CallEndReason.callerCancelled,
  );

  test('a hung release step is bounded and later cleanup still runs', () async {
    final never = Completer<void>();
    var laterRuns = 0;
    final cleanup = CallCleanupCoordinator(<CallCleanupStep>[
      CallCleanupStep('hung_native', (_) => never.future),
      CallCleanupStep('later_store', (_) async => laterRuns++),
    ], stepTimeout: const Duration(milliseconds: 10));

    final report = await cleanup.cleanup(snapshot);

    expect(report.completed, isFalse);
    expect(report.terminalAckReady, isTrue);
    expect(report.failedStepNames, <String>['hung_native']);
    expect(laterRuns, 1);
  });

  test(
    'completed cleanup tombstones stay at the fixed process bound',
    () async {
      var runs = 0;
      final cleanup = CallCleanupCoordinator(<CallCleanupStep>[
        CallCleanupStep('count', (_) async => runs++),
      ], completedTombstoneCapacity: 2);
      final ids = <CallId>[
        CallId.parse('11111111-1111-4111-8111-111111111111'),
        CallId.parse('22222222-2222-4222-8222-222222222222'),
        CallId.parse('33333333-3333-4333-8333-333333333333'),
      ];
      for (final id in ids) {
        await cleanup.cleanup(
          CallSessionSnapshot.active(
            callId: id,
            contactPeerId: 'private-contact-identity',
            direction: CallDirection.outgoing,
            state: CallState.ended,
            callerAccountPeerId: 'local-account',
            callerDeviceId: 'local-device',
            startedAt: DateTime.utc(2026, 8, 30, 12),
            endedAt: DateTime.utc(2026, 8, 30, 12, 0, 5),
            endReason: CallEndReason.callerCancelled,
          ),
        );
      }

      expect(cleanup.hasCompleted(ids.first), isFalse);
      expect(cleanup.hasCompleted(ids[1]), isTrue);
      expect(cleanup.hasCompleted(ids[2]), isTrue);
      expect(runs, 3);
    },
  );

  test('concurrent and duplicate cleanup execute every step once', () async {
    var timerCancellations = 0;
    var streamClosures = 0;
    final gate = Completer<void>();
    final coordinator = CallCleanupCoordinator(<CallCleanupStep>[
      CallCleanupStep('timers', (_) async {
        timerCancellations++;
        await gate.future;
      }),
      CallCleanupStep('streams', (_) async {
        streamClosures++;
      }),
    ]);

    final first = coordinator.cleanup(snapshot);
    final second = coordinator.cleanup(snapshot);
    gate.complete();
    final reports = await Future.wait(<Future<CallCleanupReport>>[
      first,
      second,
    ]);
    final third = await coordinator.cleanup(snapshot);

    expect(timerCancellations, 1);
    expect(streamClosures, 1);
    expect(reports.first.completed, isTrue);
    expect(reports.last.completed, isTrue);
    expect(third.alreadyCompleted, isTrue);
  });

  test(
    'one failed step does not skip remaining cleanup or expose identity',
    () async {
      var finalStepRan = false;
      final coordinator = CallCleanupCoordinator(<CallCleanupStep>[
        CallCleanupStep(
          'failing-step',
          (_) async => throw StateError('secret'),
        ),
        CallCleanupStep('final-step', (_) async => finalStepRan = true),
      ]);

      final report = await coordinator.cleanup(snapshot);

      expect(finalStepRan, isTrue);
      expect(report.completed, isFalse);
      expect(report.terminalAckReady, isTrue);
      expect(report.failedStepNames, <String>['failing-step']);
      expect('$report', isNot(contains('private-contact-identity')));
      expect('$report', isNot(contains('secret')));
    },
  );

  test(
    'critical failure blocks terminal ACK and retry runs only that step',
    () async {
      var criticalRuns = 0;
      var laterRuns = 0;
      final cleanup = CallCleanupCoordinator(<CallCleanupStep>[
        CallCleanupStep('call_media', (_) async {
          criticalRuns++;
          if (criticalRuns == 1) throw StateError('private failure');
        }, requiredForTerminalAck: true),
        CallCleanupStep('later_store', (_) async => laterRuns++),
      ]);

      final first = await cleanup.cleanup(snapshot);
      expect(first.completed, isFalse);
      expect(first.terminalAckReady, isFalse);
      expect(first.failedStepNames, <String>['call_media']);
      expect(laterRuns, 1);

      final retries = await Future.wait(<Future<CallCleanupReport>>[
        cleanup.cleanup(snapshot),
        cleanup.cleanup(snapshot),
      ]);
      final completed = await cleanup.cleanup(snapshot);

      expect(criticalRuns, 2);
      expect(laterRuns, 1);
      expect(retries.every((report) => report.terminalAckReady), isTrue);
      expect(completed.alreadyCompleted, isTrue);
    },
  );

  test(
    'report observer cannot change cleanup authority or expose identity',
    () async {
      final observed = <CallCleanupReport>[];
      final cleanup = CallCleanupCoordinator(
        <CallCleanupStep>[
          CallCleanupStep(
            'call_media',
            (_) async => throw StateError('private failure'),
            requiredForTerminalAck: true,
          ),
        ],
        onReport: (report) {
          observed.add(report);
          throw StateError('observer failure');
        },
      );

      final report = await cleanup.cleanup(snapshot);

      expect(report.terminalAckReady, isFalse);
      expect(observed, hasLength(1));
      expect(observed.single.failedStepNames, <String>['call_media']);
      expect('$report', isNot(contains('private-contact-identity')));
      expect('$report', isNot(contains('private failure')));
    },
  );
}
