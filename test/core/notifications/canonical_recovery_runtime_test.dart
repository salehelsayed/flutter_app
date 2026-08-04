import 'dart:async';

import 'package:flutter_app/core/notifications/canonical_recovery_runtime.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const markerA = CanonicalRecoveryMarker(
    generation: 7,
    binding: 'install-a/account-a',
  );

  test(
    'deleted batch converges, closes and releases before exact ack',
    () async {
      final trace = <String>[];
      final session = _FakeSession(trace);
      var currentMarker = markerA;
      final runtime = CanonicalRecoveryRuntime(
        loadCurrentBinding: () async => markerA.binding,
        loadPendingMarker: () async => currentMarker,
        acquireSession: ({required binding, required reason}) async {
          trace.add('acquire:$binding:${reason.name}');
          return session;
        },
        acknowledgeMarker: (marker) async {
          trace.add('ack:${marker.generation}:${marker.binding}');
          currentMarker = marker;
          return true;
        },
      );

      final result = await runtime.run(CanonicalRecoveryReason.deletedBatch);

      expect(result.disposition, CanonicalRecoveryDisposition.succeeded);
      expect(result.generation, markerA.generation);
      expect(trace, <String>[
        'acquire:${markerA.binding}:deletedBatch',
        'runtime',
        'transport',
        'direct',
        'group',
        'projection',
        'quiesce',
        'close',
        'release:true',
        'ack:7:${markerA.binding}',
      ]);
    },
  );

  test(
    'non-converged drain retains marker and still releases cleanly',
    () async {
      final trace = <String>[];
      final session = _FakeSession(
        trace,
        direct: const CanonicalRecoveryDrainOutcome(
          isSuccessful: true,
          hasMore: true,
        ),
      );
      var ackCount = 0;
      final runtime = CanonicalRecoveryRuntime(
        loadCurrentBinding: () async => markerA.binding,
        loadPendingMarker: () async => markerA,
        acquireSession: ({required binding, required reason}) async => session,
        acknowledgeMarker: (_) async {
          ackCount++;
          return true;
        },
        maxDrainPassesPerLane: 1,
      );

      final result = await runtime.run(CanonicalRecoveryReason.deletedBatch);

      expect(result.disposition, CanonicalRecoveryDisposition.retry);
      expect(result.failureReason, 'direct_page_budget_exhausted');
      expect(ackCount, 0);
      expect(
        trace,
        containsAllInOrder(<String>['direct', 'close', 'release:true']),
      );
      expect(trace, isNot(contains('group')));
      expect(trace, isNot(contains('projection')));
    },
  );

  test(
    'multi-page direct and group drains exhaust before projection and ack',
    () async {
      final trace = <String>[];
      var currentMarker = markerA;
      final session = _FakeSession(
        trace,
        directOutcomes: const <CanonicalRecoveryDrainOutcome>[
          CanonicalRecoveryDrainOutcome(isSuccessful: true, hasMore: true),
          CanonicalRecoveryDrainOutcome(isSuccessful: true, hasMore: false),
        ],
        groupOutcomes: const <CanonicalRecoveryDrainOutcome>[
          CanonicalRecoveryDrainOutcome(isSuccessful: true, hasMore: true),
          CanonicalRecoveryDrainOutcome(isSuccessful: true, hasMore: false),
        ],
      );
      final runtime = CanonicalRecoveryRuntime(
        loadCurrentBinding: () async => markerA.binding,
        loadPendingMarker: () async => currentMarker,
        acquireSession: ({required binding, required reason}) async => session,
        acknowledgeMarker: (marker) async {
          trace.add('ack:${marker.generation}');
          currentMarker = marker;
          return true;
        },
      );

      final result = await runtime.run(CanonicalRecoveryReason.deletedBatch);

      expect(result.disposition, CanonicalRecoveryDisposition.succeeded);
      expect(
        trace,
        containsAllInOrder(<String>[
          'direct:1',
          'direct:2',
          'group:1',
          'group:2',
          'projection',
          'quiesce',
          'close',
          'release:true',
          'ack:7',
        ]),
      );
    },
  );

  test(
    'pending durable projection custody retries after cleanup without ack',
    () async {
      final trace = <String>[];
      var ackCount = 0;
      final runtime = CanonicalRecoveryRuntime(
        loadCurrentBinding: () async => markerA.binding,
        loadPendingMarker: () async => markerA,
        acquireSession: ({required binding, required reason}) async =>
            _FakeSession(
              trace,
              projection: const CanonicalRecoveryProjectionOutcome(
                isSuccessful: true,
                hasPendingWork: true,
              ),
            ),
        acknowledgeMarker: (_) async {
          ackCount++;
          return true;
        },
      );

      final result = await runtime.run(CanonicalRecoveryReason.deletedBatch);

      expect(result.disposition, CanonicalRecoveryDisposition.retry);
      expect(result.failureReason, 'projection_not_converged');
      expect(ackCount, 0);
      expect(
        trace,
        containsAllInOrder(<String>[
          'direct',
          'group',
          'projection',
          'quiesce',
          'close',
          'release:true',
        ]),
      );
    },
  );

  test('failed projection settlement retries without ack', () async {
    final trace = <String>[];
    var ackCount = 0;
    final runtime = CanonicalRecoveryRuntime(
      loadCurrentBinding: () async => markerA.binding,
      loadPendingMarker: () async => markerA,
      acquireSession: ({required binding, required reason}) async =>
          _FakeSession(
            trace,
            projection: const CanonicalRecoveryProjectionOutcome(
              isSuccessful: false,
              hasPendingWork: false,
              failureReason: 'projection_settlement_failed',
            ),
          ),
      acknowledgeMarker: (_) async {
        ackCount++;
        return true;
      },
    );

    final result = await runtime.run(CanonicalRecoveryReason.deletedBatch);

    expect(result.disposition, CanonicalRecoveryDisposition.retry);
    expect(result.failureReason, 'projection_settlement_failed');
    expect(ackCount, 0);
    expect(trace.sublist(trace.length - 2), <String>['close', 'release:true']);
  });

  test('stop between direct pages retains marker and skips group', () async {
    final trace = <String>[];
    var ackCount = 0;
    final runtime = CanonicalRecoveryRuntime(
      loadCurrentBinding: () async => markerA.binding,
      loadPendingMarker: () async => markerA,
      acquireSession: ({required binding, required reason}) async =>
          _FakeSession(
            trace,
            directOutcomes: const <CanonicalRecoveryDrainOutcome>[
              CanonicalRecoveryDrainOutcome(isSuccessful: true, hasMore: true),
              CanonicalRecoveryDrainOutcome(isSuccessful: true, hasMore: false),
            ],
          ),
      acknowledgeMarker: (_) async {
        ackCount++;
        return true;
      },
      isStopRequested: () => trace.contains('direct:1'),
    );

    final result = await runtime.run(CanonicalRecoveryReason.deletedBatch);

    expect(result.disposition, CanonicalRecoveryDisposition.retry);
    expect(result.failureReason, 'worker_stopped');
    expect(ackCount, 0);
    expect(trace, isNot(contains('direct:2')));
    expect(trace.where((value) => value.startsWith('group')), isEmpty);
    expect(
      trace,
      containsAllInOrder(<String>[
        'direct:1',
        'quiesce',
        'close',
        'release:true',
      ]),
    );
  });

  test(
    'newer marker at pre-ack resnapshot survives stale completion',
    () async {
      final trace = <String>[];
      var markerReads = 0;
      const markerB = CanonicalRecoveryMarker(
        generation: 8,
        binding: 'install-a/account-a',
      );
      var ackCount = 0;
      final runtime = CanonicalRecoveryRuntime(
        loadCurrentBinding: () async => markerA.binding,
        loadPendingMarker: () async => markerReads++ == 0 ? markerA : markerB,
        acquireSession: ({required binding, required reason}) async =>
            _FakeSession(trace),
        acknowledgeMarker: (_) async {
          ackCount++;
          return true;
        },
      );

      final result = await runtime.run(CanonicalRecoveryReason.deletedBatch);

      expect(result.disposition, CanonicalRecoveryDisposition.retry);
      expect(result.failureReason, 'generation_superseded');
      expect(result.generation, markerA.generation);
      expect(result.currentGeneration, markerB.generation);
      expect(ackCount, 0);
      expect(trace.sublist(trace.length - 2), <String>[
        'close',
        'release:true',
      ]);
    },
  );

  test(
    'account cutover before acquire retires stale work without opening',
    () async {
      var acquired = false;
      final runtime = CanonicalRecoveryRuntime(
        loadCurrentBinding: () async => 'install-b/account-b',
        loadPendingMarker: () async => markerA,
        acquireSession: ({required binding, required reason}) async {
          acquired = true;
          return _FakeSession(<String>[]);
        },
        acknowledgeMarker: (_) async => true,
      );

      final result = await runtime.run(CanonicalRecoveryReason.deletedBatch);

      expect(result.disposition, CanonicalRecoveryDisposition.stale);
      expect(result.failureReason, 'marker_binding_is_not_current');
      expect(acquired, isFalse);
    },
  );

  test('database close failure retains ownership and forces retry', () async {
    final trace = <String>[];
    var ackCount = 0;
    final runtime = CanonicalRecoveryRuntime(
      loadCurrentBinding: () async => markerA.binding,
      loadPendingMarker: () async => markerA,
      acquireSession: ({required binding, required reason}) async =>
          _FakeSession(trace, databaseClosed: false),
      acknowledgeMarker: (_) async {
        ackCount++;
        return true;
      },
    );

    final result = await runtime.run(CanonicalRecoveryReason.deletedBatch);

    expect(result.disposition, CanonicalRecoveryDisposition.retry);
    expect(result.failureReason, 'database_close_or_lease_release_failed');
    expect(ackCount, 0);
    expect(trace.sublist(trace.length - 2), <String>['close', 'release:false']);
  });

  test(
    'runtime quiescence failure never closes or transfers ownership',
    () async {
      final trace = <String>[];
      var ackCount = 0;
      final runtime = CanonicalRecoveryRuntime(
        loadCurrentBinding: () async => markerA.binding,
        loadPendingMarker: () async => markerA,
        acquireSession: ({required binding, required reason}) async =>
            _FakeSession(trace, runtimeQuiesced: false),
        acknowledgeMarker: (_) async {
          ackCount++;
          return true;
        },
      );

      final result = await runtime.run(CanonicalRecoveryReason.deletedBatch);

      expect(result.disposition, CanonicalRecoveryDisposition.retry);
      expect(
        result.failureReason,
        'runtime_quiesce_database_close_or_lease_release_failed',
      );
      expect(ackCount, 0);
      expect(
        trace,
        containsAllInOrder(<String>['projection', 'quiesce', 'release:false']),
      );
      expect(trace, isNot(contains('close')));
    },
  );

  test(
    'cooperative stop after direct drain skips later work and cleans up',
    () async {
      final trace = <String>[];
      var ackCount = 0;
      final runtime = CanonicalRecoveryRuntime(
        loadCurrentBinding: () async => markerA.binding,
        loadPendingMarker: () async => markerA,
        acquireSession: ({required binding, required reason}) async =>
            _FakeSession(trace),
        acknowledgeMarker: (_) async {
          ackCount++;
          return true;
        },
        isStopRequested: () => trace.contains('direct'),
      );

      final result = await runtime.run(CanonicalRecoveryReason.deletedBatch);

      expect(result.disposition, CanonicalRecoveryDisposition.retry);
      expect(result.failureReason, 'worker_stopped');
      expect(ackCount, 0);
      expect(
        trace,
        containsAllInOrder(<String>[
          'direct',
          'quiesce',
          'close',
          'release:true',
        ]),
      );
      expect(trace, isNot(contains('group')));
      expect(trace, isNot(contains('projection')));
    },
  );

  test(
    'periodic sweep without a marker converges but never acknowledges',
    () async {
      final trace = <String>[];
      var ackCount = 0;
      final runtime = CanonicalRecoveryRuntime(
        loadCurrentBinding: () async => markerA.binding,
        loadPendingMarker: () async => null,
        acquireSession: ({required binding, required reason}) async {
          expect(reason, CanonicalRecoveryReason.periodicSweep);
          return _FakeSession(trace);
        },
        acknowledgeMarker: (_) async {
          ackCount++;
          return true;
        },
      );

      final result = await runtime.run(CanonicalRecoveryReason.periodicSweep);

      expect(result.disposition, CanonicalRecoveryDisposition.succeeded);
      expect(result.generation, isNull);
      expect(ackCount, 0);
      expect(trace.sublist(trace.length - 2), <String>[
        'close',
        'release:true',
      ]);
    },
  );

  test(
    'periodic sweep beginning with a marker drains but preserves it for immediate work',
    () async {
      final trace = <String>[];
      var ackCount = 0;
      var markerReads = 0;
      final runtime = CanonicalRecoveryRuntime(
        loadCurrentBinding: () async => markerA.binding,
        loadPendingMarker: () async {
          markerReads++;
          return markerA;
        },
        acquireSession: ({required binding, required reason}) async {
          expect(reason, CanonicalRecoveryReason.periodicSweep);
          return _FakeSession(trace);
        },
        acknowledgeMarker: (_) async {
          ackCount++;
          return true;
        },
      );

      final result = await runtime.run(CanonicalRecoveryReason.periodicSweep);

      expect(result.disposition, CanonicalRecoveryDisposition.retry);
      expect(result.failureReason, 'generation_arrived_during_periodic_sweep');
      expect(result.currentGeneration, markerA.generation);
      expect(
        markerReads,
        1,
        reason: 'periodic reads only the final resnapshot',
      );
      expect(ackCount, 0);
      expect(
        trace,
        containsAllInOrder(<String>[
          'direct',
          'group',
          'projection',
          'quiesce',
          'close',
          'release:true',
        ]),
      );
    },
  );

  test('overlapping triggers share one canonical run', () async {
    final entered = Completer<void>();
    final release = Completer<void>();
    var acquisitions = 0;
    final runtime = CanonicalRecoveryRuntime(
      loadCurrentBinding: () async => markerA.binding,
      loadPendingMarker: () async => markerA,
      acquireSession: ({required binding, required reason}) async {
        acquisitions++;
        entered.complete();
        await release.future;
        return _FakeSession(<String>[]);
      },
      acknowledgeMarker: (_) async => true,
    );

    final first = runtime.run(CanonicalRecoveryReason.deletedBatch);
    await entered.future;
    final second = runtime.run(CanonicalRecoveryReason.periodicSweep);
    expect(identical(first, second), isTrue);
    release.complete();

    expect((await first).disposition, CanonicalRecoveryDisposition.succeeded);
    expect(acquisitions, 1);
  });
}

final class _FakeSession implements CanonicalRecoverySession {
  _FakeSession(
    this.trace, {
    this.direct = const CanonicalRecoveryDrainOutcome(
      isSuccessful: true,
      hasMore: false,
    ),
    this.databaseClosed = true,
    this.runtimeQuiesced = true,
    this.projection = const CanonicalRecoveryProjectionOutcome(
      isSuccessful: true,
      hasPendingWork: false,
    ),
    List<CanonicalRecoveryDrainOutcome>? directOutcomes,
    List<CanonicalRecoveryDrainOutcome>? groupOutcomes,
  }) : _directOutcomes = directOutcomes,
       _groupOutcomes = groupOutcomes;

  final List<String> trace;
  final CanonicalRecoveryDrainOutcome direct;
  static const group = CanonicalRecoveryDrainOutcome(
    isSuccessful: true,
    hasMore: false,
  );
  final bool databaseClosed;
  final bool runtimeQuiesced;
  final CanonicalRecoveryProjectionOutcome projection;
  final List<CanonicalRecoveryDrainOutcome>? _directOutcomes;
  final List<CanonicalRecoveryDrainOutcome>? _groupOutcomes;
  var _directIndex = 0;
  var _groupIndex = 0;

  @override
  Future<void> ensureRuntimeReady() async => trace.add('runtime');

  @override
  Future<void> ensureTransportHealthy() async => trace.add('transport');

  @override
  Future<CanonicalRecoveryDrainOutcome> drainDirectInbox() async {
    final outcomes = _directOutcomes;
    if (outcomes != null) {
      final index = _directIndex++;
      trace.add('direct:${index + 1}');
      return outcomes[index.clamp(0, outcomes.length - 1)];
    }
    trace.add('direct');
    return direct;
  }

  @override
  Future<CanonicalRecoveryDrainOutcome> drainGroupInbox() async {
    final outcomes = _groupOutcomes;
    if (outcomes != null) {
      final index = _groupIndex++;
      trace.add('group:${index + 1}');
      return outcomes[index.clamp(0, outcomes.length - 1)];
    }
    trace.add('group');
    return group;
  }

  @override
  Future<CanonicalRecoveryProjectionOutcome>
  settleNotificationProjection() async {
    trace.add('projection');
    return projection;
  }

  @override
  Future<bool> quiesceRuntime() async {
    trace.add('quiesce');
    return runtimeQuiesced;
  }

  @override
  Future<bool> closeDatabase() async {
    trace.add('close');
    return databaseClosed;
  }

  @override
  Future<bool> releaseOwnership({required bool databaseClosed}) async {
    trace.add('release:$databaseClosed');
    return databaseClosed;
  }
}
