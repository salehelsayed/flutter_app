import 'dart:io';

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
    'dormant AOT entrypoint can only report composition unavailable retry',
    () async {
      final invocation = HeadlessCanonicalRecoveryInvocation.parse(
        const <String>[
          'deleted_batch',
          'nonce-dormant',
          'install-a/account-a',
          '7',
        ],
      );

      final report = await runUnavailableHeadlessCanonicalRecovery(
        invocation: invocation,
        isStopRequested: () => false,
        loadLeaseReleased: () async => true,
      );
      final uncertainCleanup =
          await cleanupUnavailableHeadlessCanonicalRecovery(
            loadLeaseReleased: () async =>
                throw StateError('status unavailable'),
          );

      expect(report.result.disposition, CanonicalRecoveryDisposition.retry);
      expect(report.result.failureReason, 'headless_composition_unavailable');
      expect(report.result.generation, 7);
      expect(report.databaseClosed, isTrue);
      expect(report.leaseReleased, isTrue);
      expect(uncertainCleanup.databaseClosed, isTrue);
      expect(uncertainCleanup.leaseReleased, isFalse);
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
        contains('runUnavailableHeadlessCanonicalRecovery'),
      );
      expect(entrypointBody, isNot(contains('ProductionApplicationBootstrap')));
      expect(entrypointBody, isNot(contains('acknowledge')));
    },
  );
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
