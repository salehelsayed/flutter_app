import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/scripts/group_multi_party_runtime_config.dart';
import '../../integration_test/scripts/run_group_multi_party_device_real.dart';

void main() {
  group('disposable simulator authorization', () {
    const a = '11111111-1111-1111-1111-111111111111';
    const b = '22222222-2222-2222-2222-222222222222';
    const c = '33333333-3333-3333-3333-333333333333';
    const d = '44444444-4444-4444-4444-444444444444';

    test('requires an exact allowlist before any iOS simulator mutation', () {
      expect(
        groupMultiPartySimulatorTargetsAreDisposable(
          const <String>[a, b, c, d],
          environment: const <String, String>{
            'SIMS_IOS_DISPOSABLE_SIMULATOR_IDS': '$d,$c,$b,$a',
          },
        ),
        isTrue,
      );
      expect(
        groupMultiPartySimulatorTargetsAreDisposable(const <String>[
          a,
          b,
          c,
          d,
        ], environment: const <String, String>{}),
        isFalse,
      );
      expect(
        groupMultiPartySimulatorTargetsAreDisposable(
          const <String>[a, b, c, d],
          environment: const <String, String>{
            'SIMS_IOS_DISPOSABLE_SIMULATOR_IDS': '$a,$b,$c',
          },
        ),
        isFalse,
      );
    });

    test('does not require destructive authorization for non-iOS targets', () {
      expect(
        groupMultiPartySimulatorTargetsAreDisposable(const <String>[
          'android-physical',
          'emulator-5554',
        ], environment: const <String, String>{}),
        isTrue,
      );
    });
  });

  group('resolveGroupMultiPartyIosRunnerAppPath', () {
    test('uses the centrally prepared sims artifact when supplied', () {
      expect(
        resolveGroupMultiPartyIosRunnerAppPath(
          environment: const <String, String>{
            groupMultiPartySimsArtifactEnvironmentKey:
                '/tmp/sims-cache/Runner.app',
          },
        ),
        '/tmp/sims-cache/Runner.app',
      );
    });

    test('preserves the legacy Flutter build output by default', () {
      expect(
        resolveGroupMultiPartyIosRunnerAppPath(
          environment: const <String, String>{},
        ),
        'build/ios/iphonesimulator/Runner.app',
      );
    });
  });

  group('buildHarnessLaunchSpec', () {
    test('keeps per-run runtime values out of flutter dart-defines', () {
      final spec = buildHarnessLaunchSpec(
        scenario: 'ge014',
        role: 'charlie',
        deviceId: '38FECA55-03C1-4907-BD9D-8E64BF8E3469',
        sharedDir: Directory('/tmp/gmp-ge014'),
        runId: 'sweep-001',
        relayAddresses: '127.0.0.1:4001',
        mode: 'restartSeed',
        restoreMnemonic: 'alpha beta gamma',
        reuseExistingIdentity: true,
      );

      final joinedArgs = spec.args.join('\n');
      expect(joinedArgs, isNot(contains('--dart-define=GROUP_MULTI_PARTY_')));
      expect(joinedArgs, isNot(contains('--dart-define=E2E_DB_NAME=')));
      expect(joinedArgs, isNot(contains('--dart-define=E2E_SHARED_DIR=')));
    });

    test('carries per-run values through a Documents-file runtime config', () {
      final spec = buildHarnessLaunchSpec(
        scenario: 'ge014',
        role: 'charlie',
        deviceId: '38FECA55-03C1-4907-BD9D-8E64BF8E3469',
        sharedDir: Directory('/tmp/gmp-ge014'),
        runId: 'sweep-001',
        relayAddresses: '127.0.0.1:4001',
        mode: 'restartSeed',
        restoreMnemonic: 'alpha beta gamma',
        restoreIdentityPath: '/tmp/identity.json',
        reuseExistingIdentity: true,
      );

      expect(spec.runtimeConfig.stagingMechanism, 'documents-file');
      expect(spec.runtimeConfig.sharedDir, '/tmp/gmp-ge014');
      expect(spec.runtimeConfig.role, 'charlie');
      expect(spec.runtimeConfig.scenario, 'ge014');
      expect(spec.runtimeConfig.runId, 'sweep-001');
      expect(spec.runtimeConfig.mode, 'restartSeed');
      expect(spec.runtimeConfig.restoreMnemonic, 'alpha beta gamma');
      expect(spec.runtimeConfig.restoreIdentityPath, '/tmp/identity.json');
      expect(spec.runtimeConfig.reuseExistingIdentity, isTrue);
      expect(
        spec.runtimeConfig.dbName,
        'group_multi_party_ge014_sweep-001_charlie.db',
      );
      expect(
        spec.runtimeConfig.toJson(),
        containsPair(groupMultiPartyScenarioKey, 'ge014'),
      );
    });

    test(
      'preserves Flutter drive/test shape and stable compile-time defines',
      () {
        final iosSpec = buildHarnessLaunchSpec(
          scenario: 'gm001',
          role: 'alice',
          deviceId: '38FECA55-03C1-4907-BD9D-8E64BF8E3469',
          sharedDir: Directory('/tmp/gmp-gm001'),
          runId: 'sweep-001',
          relayAddresses: '127.0.0.1:4001',
        );
        final hostSpec = buildHarnessLaunchSpec(
          scenario: 'gm001',
          role: 'alice',
          deviceId: 'macos',
          sharedDir: Directory('/tmp/gmp-gm001'),
          runId: 'sweep-001',
          relayAddresses: '127.0.0.1:4001',
        );

        expect(iosSpec.args.first, 'drive');
        expect(iosSpec.args, contains('-d'));
        expect(iosSpec.args, contains('38FECA55-03C1-4907-BD9D-8E64BF8E3469'));
        expect(iosSpec.args, contains('--no-build'));
        expect(hostSpec.args.first, 'test');
        expect(
          hostSpec.args,
          contains(
            'integration_test/group_multi_party_device_real_harness.dart',
          ),
        );
        expect(
          iosSpec.args,
          contains('--dart-define=MKNOON_RELAY_ADDRESSES=127.0.0.1:4001'),
        );
        expect(
          iosSpec.args,
          contains('--dart-define=MKNOON_KEY_ROTATION_GRACE_PERIOD_MS=1500'),
        );
      },
    );

    test('accepts one sweep-level run id across multiple scenario specs', () {
      const sweepRunId = 'sweep-shared';
      final ge001 = buildHarnessLaunchSpec(
        scenario: 'ge001',
        role: 'alice',
        deviceId: '38FECA55-03C1-4907-BD9D-8E64BF8E3469',
        sharedDir: Directory('/tmp/gmp-ge001'),
        runId: sweepRunId,
        relayAddresses: '127.0.0.1:4001',
      );
      final gm001 = buildHarnessLaunchSpec(
        scenario: 'gm001',
        role: 'bob',
        deviceId: '38FECA55-03C1-4907-BD9D-8E64BF8E3469',
        sharedDir: Directory('/tmp/gmp-gm001'),
        runId: sweepRunId,
        relayAddresses: '127.0.0.1:4001',
      );

      expect(ge001.runtimeConfig.runId, sweepRunId);
      expect(gm001.runtimeConfig.runId, sweepRunId);
      expect(ge001.runtimeConfig.dbName, contains('ge001_$sweepRunId'));
      expect(gm001.runtimeConfig.dbName, contains('gm001_$sweepRunId'));
    });
  });
}
