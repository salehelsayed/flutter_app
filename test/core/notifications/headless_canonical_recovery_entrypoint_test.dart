import 'dart:io';

import 'package:flutter_app/app/bootstrap/production_headless_canonical_recovery.dart';
import 'package:flutter_app/core/notifications/canonical_recovery_runtime.dart';
import 'package:flutter_app/core/notifications/headless_canonical_recovery_entrypoint.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'invocation parser binds reason binding nonce and nullable generation',
    () {
      final deleted = HeadlessCanonicalRecoveryInvocation.parse(const <String>[
        'deleted_batch',
        'nonce-a',
        'install-a/account-a',
        '7',
      ]);
      final periodic = HeadlessCanonicalRecoveryInvocation.parse(const <String>[
        'periodic_sweep',
        'nonce-b',
        'install-a/account-a',
        '',
      ]);

      expect(deleted.reason, CanonicalRecoveryReason.deletedBatch);
      expect(deleted.generation, 7);
      expect(periodic.reason, CanonicalRecoveryReason.periodicSweep);
      expect(periodic.generation, isNull);
      expect(
        () => HeadlessCanonicalRecoveryInvocation.parse(const <String>[
          'periodic_sweep',
          'nonce-b',
          'install-a/account-a',
          '7',
        ]),
        throwsFormatException,
      );
    },
  );

  test('ordinary retry echoes identity and truthful safe cleanup', () async {
    final channel = _FakeResultChannel();
    await runAndroidHeadlessCanonicalRecovery(
      const <String>['deleted_batch', 'nonce-a', 'install-a/account-a', '7'],
      resultChannel: channel,
      emergencyShutdown: () async => throw StateError('must not run'),
      runRecovery: ({required invocation, required isStopRequested}) async {
        channel.cancel();
        expect(isStopRequested(), isTrue);
        return HeadlessCanonicalRecoveryRunReport(
          result: CanonicalRecoveryResult(
            disposition: CanonicalRecoveryDisposition.retry,
            generation: invocation.generation,
            failureReason: 'worker_stopped',
          ),
          databaseClosed: true,
          leaseReleased: true,
        );
      },
    );

    expect(channel.methods, <String>['complete']);
    expect(channel.payloads.single, <String, Object?>{
      'reason': 'deleted_batch',
      'nonce': 'nonce-a',
      'binding': 'install-a/account-a',
      'generation': 7,
      'disposition': 'retry',
      'databaseClosed': true,
      'leaseReleased': true,
      'failureReason': 'worker_stopped',
    });
    expect(channel.disposed, isTrue);
  });

  test(
    'thrown composition reports failed retry after emergency cleanup',
    () async {
      final channel = _FakeResultChannel();
      var emergencyCalls = 0;

      await runAndroidHeadlessCanonicalRecovery(
        const <String>[
          'periodic_sweep',
          'nonce-periodic',
          'install-a/account-a',
          '',
        ],
        resultChannel: channel,
        runRecovery: ({required invocation, required isStopRequested}) async {
          throw StateError('composition failed');
        },
        emergencyShutdown: () async {
          emergencyCalls++;
          return const HeadlessCanonicalRecoveryCleanup(
            databaseClosed: true,
            leaseReleased: true,
          );
        },
      );

      expect(emergencyCalls, 1);
      expect(channel.methods, <String>['failed']);
      expect(channel.payloads.single['disposition'], 'retry');
      expect(channel.payloads.single['generation'], isNull);
      expect(channel.payloads.single['databaseClosed'], isTrue);
      expect(channel.payloads.single['leaseReleased'], isTrue);
    },
  );

  test(
    'TC-374-03 exact invocation and post-teardown authority prevent stale acquisition or ack',
    () async {
      const binding =
          'v1:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
      const marker = CanonicalRecoveryMarker(generation: 7, binding: binding);
      const initial = ProductionHeadlessCanonicalAuthoritySnapshot(
        binding: binding,
        marker: marker,
        recoveryWorkEnabled: true,
        migrationAllowsRecovery: true,
        roleAllowsRecovery: true,
        authorityFingerprint: 'linked:physical-a:active',
      );
      const deletedInvocation = HeadlessCanonicalRecoveryInvocation(
        reason: CanonicalRecoveryReason.deletedBatch,
        nativeReason: 'deleted_batch',
        nonce: 'nonce-a',
        binding: binding,
        generation: 7,
      );

      final staleInput = _RunnerBackend(initial)
        ..authority = const ProductionHeadlessCanonicalAuthoritySnapshot(
          binding:
              'v1:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
          marker: marker,
          recoveryWorkEnabled: true,
          migrationAllowsRecovery: true,
          roleAllowsRecovery: true,
          authorityFingerprint: 'linked:physical-a:active',
        );
      final staleReport = await ProductionHeadlessCanonicalRecoveryRunner(
        backend: staleInput,
      ).run(invocation: deletedInvocation, isStopRequested: () => false);
      expect(
        staleReport.result.disposition,
        CanonicalRecoveryDisposition.stale,
      );
      expect(
        staleReport.result.failureReason,
        'invocation_binding_is_not_current',
      );
      expect(staleInput.acquireCalls, 0);
      expect(staleInput.trace, isEmpty);

      final staleGeneration = _RunnerBackend(
        const ProductionHeadlessCanonicalAuthoritySnapshot(
          binding: binding,
          marker: CanonicalRecoveryMarker(generation: 8, binding: binding),
          recoveryWorkEnabled: true,
          migrationAllowsRecovery: true,
          roleAllowsRecovery: true,
          authorityFingerprint: 'linked:physical-a:active',
        ),
      );
      final staleGenerationReport =
          await ProductionHeadlessCanonicalRecoveryRunner(
            backend: staleGeneration,
          ).run(invocation: deletedInvocation, isStopRequested: () => false);
      expect(
        staleGenerationReport.result.disposition,
        CanonicalRecoveryDisposition.stale,
      );
      expect(
        staleGenerationReport.result.failureReason,
        'invocation_generation_is_not_current',
      );
      expect(staleGeneration.acquireCalls, 0);

      late final _RunnerBackend generationAdvancedAtCut;
      generationAdvancedAtCut = _RunnerBackend(initial)
        ..onAuthorityRead = (read) {
          if (read == 1) {
            generationAdvancedAtCut
                .authority = const ProductionHeadlessCanonicalAuthoritySnapshot(
              binding: binding,
              marker: CanonicalRecoveryMarker(generation: 8, binding: binding),
              recoveryWorkEnabled: true,
              migrationAllowsRecovery: true,
              roleAllowsRecovery: true,
              authorityFingerprint: 'linked:physical-a:active',
            );
          }
        };
      final advancedAtCutReport =
          await ProductionHeadlessCanonicalRecoveryRunner(
            backend: generationAdvancedAtCut,
          ).run(invocation: deletedInvocation, isStopRequested: () => false);
      expect(
        advancedAtCutReport.result.failureReason,
        'generation_superseded_before_acquire',
      );
      expect(generationAdvancedAtCut.acquireCalls, 0);
      expect(generationAdvancedAtCut.ackCalls, 0);

      late final _RunnerBackend bindingChangedAtCut;
      bindingChangedAtCut = _RunnerBackend(initial)
        ..onAuthorityRead = (read) {
          if (read == 1) {
            bindingChangedAtCut
                .authority = const ProductionHeadlessCanonicalAuthoritySnapshot(
              binding:
                  'v1:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd',
              marker: CanonicalRecoveryMarker(
                generation: 8,
                binding:
                    'v1:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd',
              ),
              recoveryWorkEnabled: true,
              migrationAllowsRecovery: true,
              roleAllowsRecovery: true,
              authorityFingerprint: 'primary:other-account',
            );
          }
        };
      final bindingAtCutReport =
          await ProductionHeadlessCanonicalRecoveryRunner(
            backend: bindingChangedAtCut,
          ).run(invocation: deletedInvocation, isStopRequested: () => false);
      expect(
        bindingAtCutReport.result.failureReason,
        'binding_changed_before_acquire',
      );
      expect(bindingChangedAtCut.acquireCalls, 0);
      expect(bindingChangedAtCut.ackCalls, 0);

      late final _RunnerBackend generationAdvancedBeforeLease;
      generationAdvancedBeforeLease = _RunnerBackend(initial)
        ..onAuthorityRead = (read) {
          if (read == 2) {
            generationAdvancedBeforeLease
                .authority = const ProductionHeadlessCanonicalAuthoritySnapshot(
              binding: binding,
              marker: CanonicalRecoveryMarker(generation: 8, binding: binding),
              recoveryWorkEnabled: true,
              migrationAllowsRecovery: true,
              roleAllowsRecovery: true,
              authorityFingerprint: 'linked:physical-a:active',
            );
          }
        };
      final advancedBeforeLeaseReport =
          await ProductionHeadlessCanonicalRecoveryRunner(
            backend: generationAdvancedBeforeLease,
          ).run(invocation: deletedInvocation, isStopRequested: () => false);
      expect(
        advancedBeforeLeaseReport.result.failureReason,
        'session_acquire_failed:'
        'ProductionHeadlessCanonicalRecoveryRefused',
      );
      expect(generationAdvancedBeforeLease.trace, isNot(contains('acquire')));
      expect(generationAdvancedBeforeLease.ackCalls, 0);

      final refusedRole = _RunnerBackend(
        const ProductionHeadlessCanonicalAuthoritySnapshot(
          binding: binding,
          marker: marker,
          recoveryWorkEnabled: true,
          migrationAllowsRecovery: true,
          roleAllowsRecovery: false,
          authorityFingerprint: 'linked:physical-a:preparing',
        ),
      );
      final refusedRoleReport = await ProductionHeadlessCanonicalRecoveryRunner(
        backend: refusedRole,
      ).run(invocation: deletedInvocation, isStopRequested: () => false);
      expect(
        refusedRoleReport.result.failureReason,
        'headless_authority_refused',
      );
      expect(refusedRole.acquireCalls, 0);

      final roleMutation = _RunnerBackend(initial);
      roleMutation.afterRelease = () {
        roleMutation.authority =
            const ProductionHeadlessCanonicalAuthoritySnapshot(
              binding: binding,
              marker: marker,
              recoveryWorkEnabled: true,
              migrationAllowsRecovery: true,
              roleAllowsRecovery: false,
              authorityFingerprint: 'linked:physical-a:revoked',
            );
      };
      final roleReport = await ProductionHeadlessCanonicalRecoveryRunner(
        backend: roleMutation,
      ).run(invocation: deletedInvocation, isStopRequested: () => false);
      expect(roleReport.result.disposition, CanonicalRecoveryDisposition.stale);
      expect(roleReport.result.failureReason, 'authority_changed_before_ack');
      expect(roleMutation.ackCalls, 0);
      expect(
        roleMutation.trace,
        containsAllInOrder(<String>[
          'acquire',
          'quiesce',
          'close',
          'release:true',
        ]),
      );

      final newerGeneration = _RunnerBackend(initial);
      newerGeneration.afterRelease = () {
        newerGeneration.authority =
            const ProductionHeadlessCanonicalAuthoritySnapshot(
              binding: binding,
              marker: CanonicalRecoveryMarker(generation: 8, binding: binding),
              recoveryWorkEnabled: true,
              migrationAllowsRecovery: true,
              roleAllowsRecovery: true,
              authorityFingerprint: 'linked:physical-a:active',
            );
      };
      final generationReport = await ProductionHeadlessCanonicalRecoveryRunner(
        backend: newerGeneration,
      ).run(invocation: deletedInvocation, isStopRequested: () => false);
      expect(
        generationReport.result.disposition,
        CanonicalRecoveryDisposition.retry,
      );
      expect(generationReport.result.failureReason, 'generation_superseded');
      expect(generationReport.result.currentGeneration, 8);
      expect(newerGeneration.ackCalls, 0);

      late final _RunnerBackend authorityMutationAtAtomicAck;
      authorityMutationAtAtomicAck = _RunnerBackend(initial)
        ..beforeAcknowledge = () {
          authorityMutationAtAtomicAck.authority =
              const ProductionHeadlessCanonicalAuthoritySnapshot(
                binding: binding,
                marker: marker,
                recoveryWorkEnabled: false,
                migrationAllowsRecovery: true,
                roleAllowsRecovery: false,
                authorityFingerprint: 'linked:physical-b:preparing',
                authorityRevision: 1,
                authorityMutationInProgress: true,
              );
        };
      final atomicAckReport = await ProductionHeadlessCanonicalRecoveryRunner(
        backend: authorityMutationAtAtomicAck,
      ).run(invocation: deletedInvocation, isStopRequested: () => false);
      expect(
        atomicAckReport.result.disposition,
        CanonicalRecoveryDisposition.retry,
      );
      expect(atomicAckReport.result.failureReason, 'exact_ack_failed');
      expect(authorityMutationAtAtomicAck.ackCalls, 1);
      expect(authorityMutationAtAtomicAck.lastAckAuthorityRevision, 0);
      expect(authorityMutationAtAtomicAck.authority.marker, marker);

      final accountCutover = _RunnerBackend(initial);
      accountCutover.afterRelease = () {
        accountCutover
            .authority = const ProductionHeadlessCanonicalAuthoritySnapshot(
          binding:
              'v1:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc',
          marker: marker,
          recoveryWorkEnabled: true,
          migrationAllowsRecovery: true,
          roleAllowsRecovery: true,
          authorityFingerprint: 'primary:other-account',
        );
      };
      final cutoverReport = await ProductionHeadlessCanonicalRecoveryRunner(
        backend: accountCutover,
      ).run(invocation: deletedInvocation, isStopRequested: () => false);
      expect(
        cutoverReport.result.disposition,
        CanonicalRecoveryDisposition.stale,
      );
      expect(cutoverReport.result.failureReason, 'binding_changed_before_ack');
      expect(accountCutover.ackCalls, 0);

      // Plan 375: a marker present when the periodic sweep STARTS is adopted
      // and exact-acknowledged after the same fixed-point proof — this is the
      // recovery path after an immediate enqueue failure.
      final periodic = _RunnerBackend(initial);
      const periodicInvocation = HeadlessCanonicalRecoveryInvocation(
        reason: CanonicalRecoveryReason.periodicSweep,
        nativeReason: 'periodic_sweep',
        nonce: 'nonce-periodic',
        binding: binding,
        generation: null,
      );
      final periodicReport = await ProductionHeadlessCanonicalRecoveryRunner(
        backend: periodic,
      ).run(invocation: periodicInvocation, isStopRequested: () => false);
      expect(
        periodicReport.result.disposition,
        CanonicalRecoveryDisposition.succeeded,
      );
      expect(
        periodic.ackCalls,
        1,
        reason: 'periodic continuation exact-acknowledges the adopted marker',
      );
      expect(periodic.lastExpectedMarker, isNull);

      // A marker that only ARRIVES mid-run is never consumed by that sweep:
      // it is preserved for the serial immediate work.
      const noMarker = ProductionHeadlessCanonicalAuthoritySnapshot(
        binding: binding,
        marker: null,
        recoveryWorkEnabled: true,
        migrationAllowsRecovery: true,
        roleAllowsRecovery: true,
        authorityFingerprint: 'linked:physical-a:active',
      );
      late final _RunnerBackend periodicArrival;
      periodicArrival = _RunnerBackend(noMarker)
        ..onAuthorityRead = (read) {
          if (read >= 2) periodicArrival.authority = initial;
        };
      final periodicArrivalReport =
          await ProductionHeadlessCanonicalRecoveryRunner(
            backend: periodicArrival,
          ).run(invocation: periodicInvocation, isStopRequested: () => false);
      expect(
        periodicArrivalReport.result.disposition,
        CanonicalRecoveryDisposition.retry,
      );
      expect(
        periodicArrivalReport.result.failureReason,
        'generation_arrived_during_periodic_sweep',
      );
      expect(
        periodicArrival.ackCalls,
        0,
        reason: 'periodic work cannot consume a marker it did not adopt',
      );

      final coherent = _RunnerBackend(initial);
      final coherentReport = await ProductionHeadlessCanonicalRecoveryRunner(
        backend: coherent,
      ).run(invocation: deletedInvocation, isStopRequested: () => false);
      expect(
        coherentReport.result.disposition,
        CanonicalRecoveryDisposition.succeeded,
      );
      expect(coherent.ackCalls, 1);
      expect(coherent.lastExpectedMarker, marker);
      expect(
        coherent.authorityReads,
        3,
        reason: 'preflight, pre-acquire, and pre-ACK are coherent snapshots',
      );
    },
  );

  test(
    'entrypoint source creates no UI root or implicit plugin registrant',
    () {
      final source = _repoFile(
        'lib/core/notifications/headless_canonical_recovery_entrypoint.dart',
      ).readAsStringSync();

      expect(source, isNot(contains('runApp(')));
      expect(source, isNot(contains('ApplicationRoot')));
      expect(source, isNot(contains('package:flutter/material.dart')));
      expect(source, isNot(contains('GeneratedPluginRegistrant')));
      expect(source, contains('WidgetsFlutterBinding.ensureInitialized()'));

      final mainSource = _repoFile('lib/main.dart').readAsStringSync();
      final entrypointStart = mainSource.indexOf(
        'Future<void> androidHeadlessCanonicalRecoveryMain',
      );
      expect(entrypointStart, greaterThanOrEqualTo(0));
      final entrypointBody = mainSource.substring(entrypointStart);
      expect(
        entrypointBody,
        contains('runProductionHeadlessCanonicalRecovery'),
      );
      expect(
        entrypointBody,
        contains('cleanupProductionHeadlessCanonicalRecovery'),
      );
      expect(
        entrypointBody,
        isNot(contains('runUnavailableHeadlessCanonicalRecovery')),
      );
      expect(entrypointBody, isNot(contains('ProductionApplicationBootstrap')));
      expect(entrypointBody, isNot(contains('acknowledge')));
    },
  );

  test(
    'runner retries emergency cleanup on the same retained partial owner',
    () async {
      const binding =
          'v1:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
      const marker = CanonicalRecoveryMarker(generation: 7, binding: binding);
      final backend = _RunnerBackend(
        const ProductionHeadlessCanonicalAuthoritySnapshot(
          binding: binding,
          marker: marker,
          recoveryWorkEnabled: true,
          migrationAllowsRecovery: true,
          roleAllowsRecovery: true,
          authorityFingerprint: 'primary:account-a',
        ),
      )..failDisposeOnce = true;

      final report =
          await ProductionHeadlessCanonicalRecoveryRunner(backend: backend).run(
            invocation: const HeadlessCanonicalRecoveryInvocation(
              reason: CanonicalRecoveryReason.deletedBatch,
              nativeReason: 'deleted_batch',
              nonce: 'nonce-emergency',
              binding: binding,
              generation: 7,
            ),
            isStopRequested: () => false,
          );

      expect(report.result.disposition, CanonicalRecoveryDisposition.retry);
      expect(report.result.failureReason, 'dart_owner_quiescence_failed');
      expect(report.databaseClosed, isTrue);
      expect(report.leaseReleased, isTrue);
      expect(backend.emergencyCalls, 1);
      expect(
        backend.trace,
        containsAllInOrder(<String>[
          'dispose',
          'release:false',
          'emergency',
          'dispose',
          'close',
          'release:true',
        ]),
      );
    },
  );
}

final class _RunnerBackend
    implements ProductionHeadlessCanonicalRecoveryBackend {
  _RunnerBackend(this.authority);

  ProductionHeadlessCanonicalAuthoritySnapshot authority;
  final List<String> trace = <String>[];
  int acquireCalls = 0;
  int ackCalls = 0;
  int emergencyCalls = 0;
  bool failDisposeOnce = false;
  int authorityReads = 0;
  void Function(int read)? onAuthorityRead;
  CanonicalRecoveryMarker? lastExpectedMarker;
  void Function()? afterRelease;
  void Function()? beforeAcknowledge;
  int? lastAckAuthorityRevision;
  _RunnerSession? session;

  @override
  Future<ProductionHeadlessCanonicalAuthoritySnapshot> loadAuthority() async {
    final snapshot = authority;
    authorityReads++;
    onAuthorityRead?.call(authorityReads);
    return snapshot;
  }

  @override
  Future<bool> readGenericRecoveryMayHaveAlerted() async => false;

  @override
  Future<ProductionHeadlessOwnedRecoverySession?> acquireSession({
    required String binding,
    required CanonicalRecoveryReason reason,
    CanonicalRecoveryMarker? expectedMarker,
  }) async {
    acquireCalls++;
    lastExpectedMarker = expectedMarker;
    if (expectedMarker != null && authority.marker != expectedMarker) {
      throw const ProductionHeadlessCanonicalRecoveryRefused(
        'pre_open_generation_changed',
      );
    }
    trace.add('acquire');
    return session = _RunnerSession(this);
  }

  @override
  Future<bool> acknowledgeHeadlessMarker(
    CanonicalRecoveryMarker marker, {
    int? authorityRevision,
  }) async {
    ackCalls++;
    lastAckAuthorityRevision = authorityRevision;
    beforeAcknowledge?.call();
    trace.add('ack');
    return authorityRevision != null &&
        authority.authorityRevision == authorityRevision &&
        !authority.authorityMutationInProgress;
  }

  @override
  HeadlessCanonicalRecoveryCleanup get lifecycleFacts =>
      session?.lifecycleFacts ??
      const HeadlessCanonicalRecoveryCleanup(
        databaseClosed: true,
        leaseReleased: true,
      );

  @override
  Future<HeadlessCanonicalRecoveryCleanup> emergencyCleanup() async {
    emergencyCalls++;
    trace.add('emergency');
    return session?.emergencyCleanup() ?? lifecycleFacts;
  }
}

final class _RunnerSession implements ProductionHeadlessOwnedRecoverySession {
  _RunnerSession(this.backend);

  final _RunnerBackend backend;
  bool databaseClosed = false;
  bool leaseReleased = false;

  @override
  HeadlessCanonicalRecoveryCleanup get lifecycleFacts =>
      HeadlessCanonicalRecoveryCleanup(
        databaseClosed: databaseClosed,
        leaseReleased: leaseReleased,
      );

  @override
  Future<void> ensureRuntimeReady() async => backend.trace.add('runtime');

  @override
  Future<void> ensureTransportHealthy() async => backend.trace.add('transport');

  @override
  Future<CanonicalRecoveryDrainOutcome> drainDirectInbox() async {
    backend.trace.add('direct');
    return const CanonicalRecoveryDrainOutcome(
      isSuccessful: true,
      hasMore: false,
    );
  }

  @override
  Future<CanonicalRecoveryDrainOutcome> drainGroupInbox() async {
    backend.trace.add('group');
    return const CanonicalRecoveryDrainOutcome(
      isSuccessful: true,
      hasMore: false,
    );
  }

  @override
  Future<CanonicalRecoveryProjectionOutcome>
  settleNotificationProjection() async {
    backend.trace.add('projection');
    return const CanonicalRecoveryProjectionOutcome(
      isSuccessful: true,
      hasPendingWork: false,
    );
  }

  @override
  Future<void> sealAdmissionAndAwaitInFlight() async =>
      backend.trace.add('seal');

  @override
  Future<void> stopGroupMessageListener() async =>
      backend.trace.add('stopGroup');

  @override
  Future<void> disposeProjectionOwners() async {
    backend.trace.add('dispose');
    if (backend.failDisposeOnce) {
      backend.failDisposeOnce = false;
      throw StateError('one-shot projection owner failure');
    }
  }

  @override
  Future<bool> quiesceRuntime() async {
    backend.trace.add('quiesce');
    return true;
  }

  @override
  Future<bool> closeDatabase() async {
    backend.trace.add('close');
    databaseClosed = true;
    return true;
  }

  @override
  Future<bool> releaseOwnership({required bool databaseClosed}) async {
    backend.trace.add('release:$databaseClosed');
    leaseReleased = databaseClosed;
    backend.afterRelease?.call();
    return leaseReleased;
  }

  @override
  Future<HeadlessCanonicalRecoveryCleanup> emergencyCleanup() async {
    await sealAdmissionAndAwaitInFlight();
    await stopGroupMessageListener();
    await disposeProjectionOwners();
    await quiesceRuntime();
    final closed = await closeDatabase();
    await releaseOwnership(databaseClosed: closed);
    return lifecycleFacts;
  }
}

final class _FakeResultChannel
    implements HeadlessCanonicalRecoveryResultChannel {
  void Function()? _onCancel;
  final methods = <String>[];
  final payloads = <Map<String, Object?>>[];
  bool disposed = false;

  @override
  void registerCancelHandler(void Function() onCancel) {
    _onCancel = onCancel;
  }

  void cancel() => _onCancel?.call();

  @override
  Future<void> send({
    required String method,
    required Map<String, Object?> payload,
  }) async {
    methods.add(method);
    payloads.add(payload);
  }

  @override
  void dispose() {
    disposed = true;
    _onCancel = null;
  }
}

File _repoFile(String relativePath) {
  for (final prefix in const <String>['', '../', '../../']) {
    final file = File('$prefix$relativePath');
    if (file.existsSync()) return file;
  }
  throw StateError('Cannot locate $relativePath');
}
