import 'dart:async';
import 'dart:io';

import 'package:flutter_app/core/notifications/dropped_push_recovery_bridge.dart';
import 'package:flutter_app/core/notifications/dropped_push_recovery_coordinator.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeGateway implements DroppedPushRecoveryGateway {
  int? pending;
  Object? pendingReadError;
  int pendingReads = 0;
  final List<int> acknowledgeAttempts = <int>[];
  Future<bool> Function(int generation)? onAcknowledge;
  Future<void> Function(int? generation)? handler;

  @override
  Future<int?> pendingGeneration() async {
    pendingReads += 1;
    final error = pendingReadError;
    if (error != null) throw error;
    return pending;
  }

  @override
  Future<bool> acknowledgeGeneration(int generation) async {
    acknowledgeAttempts.add(generation);
    final override = onAcknowledge;
    if (override != null) return override(generation);
    if (pending != generation) return false;
    pending = null;
    return true;
  }

  @override
  void register(Future<void> Function(int? generation) onRecoveryPending) {
    handler = onRecoveryPending;
  }

  @override
  void dispose() {}
}

const _directSuccess = DirectInboxDrainOutcome(
  isSuccessful: true,
  hasMore: false,
);
const _groupSuccess = DroppedPushGroupDrainOutcome(
  isSuccessful: true,
  hasMorePages: false,
);

void main() {
  late _FakeGateway gateway;
  late List<String> calls;
  late DirectInboxDrainOutcome directOutcome;
  late DroppedPushGroupDrainOutcome groupOutcome;
  late Future<void> Function() ensureRuntimeReady;
  late Future<void> Function() ensureTransportHealthy;

  DroppedPushRecoveryCoordinator buildCoordinator({
    Future<DirectInboxDrainOutcome> Function()? drainDirect,
    Future<DroppedPushGroupDrainOutcome> Function()? drainGroups,
  }) {
    return DroppedPushRecoveryCoordinator(
      gateway: gateway,
      ensureRuntimeReady: ensureRuntimeReady,
      ensureTransportHealthy: ensureTransportHealthy,
      drainDirectInboxFully:
          drainDirect ??
          () async {
            calls.add('direct');
            return directOutcome;
          },
      drainGroupInboxFully:
          drainGroups ??
          () async {
            calls.add('group');
            return groupOutcome;
          },
    );
  }

  setUp(() {
    gateway = _FakeGateway();
    calls = <String>[];
    directOutcome = _directSuccess;
    groupOutcome = _groupSuccess;
    ensureRuntimeReady = () async => calls.add('runtime');
    ensureTransportHealthy = () async => calls.add('health');
  });

  test('no pending generation performs no runtime or inbox work', () async {
    final coordinator = buildCoordinator();

    final result = await coordinator.recoverIfPending();

    expect(result.disposition, DroppedPushRecoveryDisposition.noPending);
    expect(calls, isEmpty);
    expect(gateway.acknowledgeAttempts, isEmpty);
  });

  test('pending ownership poll is non-consuming and fails closed', () async {
    final coordinator = buildCoordinator();
    expect(await coordinator.hasPendingRecovery(), isFalse);

    gateway.pending = 6;
    expect(await coordinator.hasPendingRecovery(), isTrue);
    expect(gateway.pending, 6);
    expect(calls, isEmpty);
    expect(gateway.acknowledgeAttempts, isEmpty);
  });

  test(
    'pending read failure owns the drain and never reports no pending',
    () async {
      gateway.pendingReadError = StateError('native read failed');
      final coordinator = buildCoordinator();

      expect(await coordinator.hasPendingRecovery(), isTrue);
      final result = await coordinator.recoverIfPending();

      expect(result.disposition, DroppedPushRecoveryDisposition.retained);
      expect(result.failureReason, contains('pending_read_failed'));
      expect(calls, isEmpty);
      expect(gateway.acknowledgeAttempts, isEmpty);
    },
  );

  test(
    'matching generation is acknowledged only after both full drains',
    () async {
      gateway.pending = 7;
      gateway.onAcknowledge = (generation) async {
        calls.add('ack:$generation');
        if (gateway.pending != generation) return false;
        gateway.pending = null;
        return true;
      };
      final coordinator = buildCoordinator();

      final result = await coordinator.recoverIfPending();

      expect(result.disposition, DroppedPushRecoveryDisposition.recovered);
      expect(result.generation, 7);
      expect(calls, <String>['runtime', 'health', 'direct', 'group', 'ack:7']);
      expect(gateway.pending, isNull);
    },
  );

  test(
    'direct failure still attempts groups and retains the generation',
    () async {
      gateway.pending = 8;
      directOutcome = const DirectInboxDrainOutcome(
        isSuccessful: false,
        hasMore: true,
        failureReason: 'retrieve_failed',
      );
      final coordinator = buildCoordinator();

      final result = await coordinator.recoverIfPending();

      expect(result.disposition, DroppedPushRecoveryDisposition.retained);
      expect(result.failureReason, contains('direct'));
      expect(calls, containsAllInOrder(<String>['direct', 'group']));
      expect(gateway.pending, 8);
      expect(gateway.acknowledgeAttempts, isEmpty);
    },
  );

  test(
    'group failure retains a successful direct recovery generation',
    () async {
      gateway.pending = 9;
      groupOutcome = const DroppedPushGroupDrainOutcome(
        isSuccessful: false,
        hasMorePages: false,
      );
      final coordinator = buildCoordinator();

      final result = await coordinator.recoverIfPending();

      expect(result.disposition, DroppedPushRecoveryDisposition.retained);
      expect(result.failureReason, contains('group'));
      expect(gateway.pending, 9);
      expect(gateway.acknowledgeAttempts, isEmpty);
    },
  );

  test('remaining direct or group pages prevent acknowledgement', () async {
    gateway.pending = 10;
    directOutcome = const DirectInboxDrainOutcome(
      isSuccessful: true,
      hasMore: true,
    );
    var result = await buildCoordinator().recoverIfPending();
    expect(result.disposition, DroppedPushRecoveryDisposition.retained);
    expect(gateway.acknowledgeAttempts, isEmpty);

    directOutcome = _directSuccess;
    groupOutcome = const DroppedPushGroupDrainOutcome(
      isSuccessful: true,
      hasMorePages: true,
    );
    result = await buildCoordinator().recoverIfPending();
    expect(result.disposition, DroppedPushRecoveryDisposition.retained);
    expect(gateway.acknowledgeAttempts, isEmpty);
  });

  test('crash-equivalent exception after read retains the marker', () async {
    gateway.pending = 11;
    ensureRuntimeReady = () async => throw StateError('bootstrap failed');

    final result = await buildCoordinator().recoverIfPending();

    expect(result.disposition, DroppedPushRecoveryDisposition.retained);
    expect(result.failureReason, contains('bootstrap'));
    expect(gateway.pending, 11);
    expect(gateway.acknowledgeAttempts, isEmpty);
  });

  test(
    'concurrent requests coalesce into one runtime and drain pass',
    () async {
      gateway.pending = 12;
      final directGate = Completer<void>();
      var directCalls = 0;
      final coordinator = buildCoordinator(
        drainDirect: () async {
          directCalls += 1;
          await directGate.future;
          return _directSuccess;
        },
      );

      final first = coordinator.recoverIfPending();
      await Future<void>.delayed(Duration.zero);
      final second = coordinator.recoverIfPending();
      directGate.complete();

      final results = await Future.wait(<Future<DroppedPushRecoveryResult>>[
        first,
        second,
      ]);
      expect(
        results.map((result) => result.disposition),
        everyElement(DroppedPushRecoveryDisposition.recovered),
      );
      expect(directCalls, 1);
      expect(gateway.acknowledgeAttempts, <int>[12]);
    },
  );

  test(
    'new deletion during drain defeats stale ack and remains pending',
    () async {
      gateway.pending = 13;
      gateway.onAcknowledge = (generation) async {
        if (gateway.pending != generation) return false;
        gateway.pending = null;
        return true;
      };
      final directGate = Completer<void>();
      final coordinator = buildCoordinator(
        drainDirect: () async {
          await directGate.future;
          return _directSuccess;
        },
      );

      final first = coordinator.recoverIfPending();
      await Future<void>.delayed(Duration.zero);
      gateway.pending = 14;
      directGate.complete();
      final stale = await first;

      expect(stale.disposition, DroppedPushRecoveryDisposition.superseded);
      expect(gateway.pending, 14);
      expect(gateway.acknowledgeAttempts, <int>[13]);

      final current = await coordinator.recoverIfPending();
      expect(current.disposition, DroppedPushRecoveryDisposition.recovered);
      expect(gateway.acknowledgeAttempts, <int>[13, 14]);
    },
  );

  test(
    'failed native acknowledgement retains the matching generation',
    () async {
      gateway.pending = 16;
      gateway.onAcknowledge = (_) async => false;

      final result = await buildCoordinator().recoverIfPending();

      expect(result.disposition, DroppedPushRecoveryDisposition.retained);
      expect(result.failureReason, 'generation_ack_failed');
      expect(gateway.pending, 16);
      expect(gateway.acknowledgeAttempts, <int>[16]);
    },
  );

  test(
    'native acceleration uses the same single-flight recovery path',
    () async {
      gateway.pending = 15;
      final directGate = Completer<void>();
      var directCalls = 0;
      final coordinator = buildCoordinator(
        drainDirect: () async {
          directCalls += 1;
          await directGate.future;
          return _directSuccess;
        },
      );
      coordinator.registerNativeAcceleration();

      final first = gateway.handler!(15);
      await Future<void>.delayed(Duration.zero);
      final second = gateway.handler!(15);
      directGate.complete();
      await Future.wait(<Future<void>>[first, second]);

      expect(directCalls, 1);
      expect(gateway.acknowledgeAttempts, <int>[15]);
    },
  );

  test(
    'native acceleration can route through the application-root latch',
    () async {
      gateway.pending = 17;
      var rootRecoveryCalls = 0;
      final coordinator = buildCoordinator();
      coordinator.registerNativeAcceleration(() async {
        rootRecoveryCalls += 1;
      });

      await gateway.handler!(17);

      expect(rootRecoveryCalls, 1);
      expect(calls, isEmpty);
      expect(gateway.acknowledgeAttempts, isEmpty);
    },
  );

  test(
    'resume repoll latch preserves a request arriving during the prior poll',
    () async {
      final latch = DroppedPushRecoveryRepollLatch();
      final firstPoll = Completer<bool>();
      var pollCalls = 0;
      var recoveryCalls = 0;
      latch.request();

      final drain = latch.drain(
        hasPendingRecovery: () {
          pollCalls += 1;
          if (pollCalls == 1) return firstPoll.future;
          return Future<bool>.value(true);
        },
        recoverIfPending: () async {
          recoveryCalls += 1;
        },
      );
      await Future<void>.delayed(Duration.zero);
      latch.request();
      firstPoll.complete(false);
      await drain;

      expect(pollCalls, 2);
      expect(recoveryCalls, 1);
    },
  );

  test('application root registers acceleration and polls on every resume', () {
    final source = File('lib/app/application_root.dart').readAsStringSync();
    final initStart = source.indexOf('void initState() {');
    final initEnd = source.indexOf(
      'Future<void> _ensureRuntimeServicesReady()',
      initStart,
    );
    final resumeStart = source.indexOf('Future<void> _onResumed() async {');
    final resumeEnd = source.indexOf('void _setupPushListeners()', resumeStart);

    expect(initStart, isNonNegative);
    expect(initEnd, greaterThan(initStart));
    expect(
      source.substring(initStart, initEnd),
      contains('registerNativeAcceleration('),
    );
    expect(resumeStart, isNonNegative);
    expect(resumeEnd, greaterThan(resumeStart));
    final resumeSource = source.substring(resumeStart, resumeEnd);
    final ownershipPoll = resumeSource.indexOf(
      'await _hasPendingDroppedPushRecovery()',
    );
    final ordinaryResume = resumeSource.indexOf('await handleAppResumed(');
    expect(ownershipPoll, isNonNegative);
    expect(ordinaryResume, greaterThan(ownershipPoll));
    expect(resumeSource, contains('skipDirectInboxDrain:'));
    expect(resumeSource, contains('skipGroupInboxDrain:'));
    expect(
      resumeSource,
      contains('_droppedPushRecoveryRepollLatch.request();'),
    );
    expect(
      resumeSource,
      contains('await _droppedPushRecoveryRepollLatch.drain('),
    );
    final nativeSignalStart = source.indexOf(
      'Future<void> _handleNativeDroppedPushRecoverySignal() async {',
    );
    final nativeSignalEnd = source.indexOf(
      'Future<void> _ingestStagedPushEnvelopes',
      nativeSignalStart,
    );
    expect(nativeSignalStart, isNonNegative);
    expect(nativeSignalEnd, greaterThan(nativeSignalStart));
    expect(
      source.substring(nativeSignalStart, nativeSignalEnd),
      contains('_droppedPushRecoveryRepollLatch.request();'),
    );
  });

  test('cold startup replaces the ordinary group drain before recovery', () {
    final source = File(
      'lib/features/identity/presentation/startup_router.dart',
    ).readAsStringSync();
    final start = source.indexOf('if (result == StartNodeResult.success) {');
    final end = source.indexOf(
      '// Node startup can fail while cleanup_pending work is entirely local.',
      start,
    );
    final coldSource = source.substring(start, end);

    final ownershipPoll = coldSource.indexOf(
      'await hasPendingDroppedPushRecovery()',
    );
    final groupDrain = coldSource.indexOf('await drainGroupOfflineInbox(');
    final recovery = coldSource.indexOf('await recoverDroppedPushes();');
    expect(ownershipPoll, isNonNegative);
    expect(groupDrain, greaterThan(ownershipPoll));
    expect(coldSource, contains('!droppedPushRecoveryOwnsInbox'));
    expect(recovery, greaterThan(groupDrain));
    expect(coldSource, contains('await groupRecovery;'));
  });
}
