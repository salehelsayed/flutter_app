import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/_support/android_app_file_broker.dart';
import '../../integration_test/_support/group_multi_party_harness_runtime_loader.dart';
import '../../integration_test/_support/group_multi_party_verdict_handshake.dart';
import '../../integration_test/_support/signal_files.dart';
import '../../integration_test/scripts/group_multi_party_runtime_config.dart';
import '../../integration_test/scripts/run_group_multi_party_device_real.dart';
import '../../integration_test/scripts/run_b1b_sibling_device_convergence.dart';

final class _FakeAndroidAppFileTransport implements AndroidAppFileTransport {
  bool packageInstalled = true;
  String? processId;
  String appDataDirectoryValue = '/data/user/0/com.mknoon.app';
  final List<String> events = <String>[];
  Future<void> Function(String deviceId, String directory, String name)?
  afterWrite;
  final Set<String> unavailableDeviceIds = <String>{};
  final Map<String, Map<String, Map<String, List<int>>>> _files =
      <String, Map<String, Map<String, List<int>>>>{};
  final Map<String, int> readCounts = <String, int>{};
  Future<void> Function(String deviceId, String relativeDirectory)?
  beforeListFiles;
  Future<void> Function(
    String deviceId,
    String relativeDirectory,
    Set<String> snapshot,
  )?
  afterListFiles;

  Map<String, List<int>> _directory(String deviceId, String directory) {
    return _files
        .putIfAbsent(deviceId, () => <String, Map<String, List<int>>>{})
        .putIfAbsent(directory, () => <String, List<int>>{});
  }

  void _requireAvailable(String deviceId) {
    if (unavailableDeviceIds.contains(deviceId)) {
      throw StateError('$deviceId app sandbox is unavailable');
    }
  }

  void seed(
    String deviceId,
    String directory,
    String fileName,
    List<int> bytes,
  ) {
    _directory(deviceId, directory)[fileName] = List<int>.from(bytes);
  }

  List<int>? bytes(String deviceId, String directory, String fileName) {
    final value = _directory(deviceId, directory)[fileName];
    return value == null ? null : List<int>.from(value);
  }

  @override
  Future<String> appDataDirectory(String deviceId) async {
    events.add('data-dir:$deviceId');
    return appDataDirectoryValue;
  }

  @override
  Future<String?> appProcessId(String deviceId) async {
    events.add('pid:$deviceId:${processId ?? 'none'}');
    return processId;
  }

  @override
  Future<void> deleteFile(
    String deviceId,
    String relativeDirectory,
    String fileName,
  ) async {
    events.add('delete:$deviceId:$relativeDirectory:$fileName');
    _directory(deviceId, relativeDirectory).remove(fileName);
  }

  @override
  Future<void> ensureDirectory(
    String deviceId,
    String relativeDirectory,
  ) async {
    _requireAvailable(deviceId);
    events.add('mkdir:$deviceId:$relativeDirectory');
    _directory(deviceId, relativeDirectory);
  }

  @override
  Future<void> forceStopApp(String deviceId) async {
    events.add('force-stop:$deviceId');
    processId = null;
  }

  @override
  Future<bool> isPackageInstalled(String deviceId) async {
    events.add('installed:$deviceId');
    return packageInstalled;
  }

  @override
  Future<Set<String>> listFiles(
    String deviceId,
    String relativeDirectory,
  ) async {
    await beforeListFiles?.call(deviceId, relativeDirectory);
    events.add('list:$deviceId:$relativeDirectory');
    final snapshot = _directory(deviceId, relativeDirectory).keys.toSet();
    await afterListFiles?.call(deviceId, relativeDirectory, snapshot);
    return snapshot;
  }

  @override
  Future<List<int>?> readFile(
    String deviceId,
    String relativeDirectory,
    String fileName,
  ) async {
    _requireAvailable(deviceId);
    final key = '$deviceId:$relativeDirectory:$fileName';
    readCounts[key] = (readCounts[key] ?? 0) + 1;
    events.add('read:$key');
    return bytes(deviceId, relativeDirectory, fileName);
  }

  @override
  Future<void> writeFileAtomically(
    String deviceId,
    String relativeDirectory,
    String fileName,
    List<int> bytes,
  ) async {
    _requireAvailable(deviceId);
    events.add('write:$deviceId:$relativeDirectory:$fileName');
    seed(deviceId, relativeDirectory, fileName, bytes);
    await afterWrite?.call(deviceId, relativeDirectory, fileName);
  }
}

void main() {
  group('B1b terminal host capture', () {
    test('launch arguments require capture in both actual role builds', () {
      for (final role in <String>['primary', 'sibling']) {
        final args = buildB1bHarnessArguments(
          role: role,
          deviceId: 'device-$role',
          sharedDir: Directory('/data/user/0/disposable/cache/run'),
          runId: 'run-1',
          plan365GroupMedia: true,
        );
        expect(args, contains('--dart-define=B1B_REQUIRE_HOST_CAPTURE=true'));
        expect(args, contains('--dart-define=MD004_ROLE=$role'));
        expect(
          args,
          contains('--dart-define=B1B_ENABLE_PLAN365_GROUP_MEDIA=true'),
        );
        expect(args.last, 'device-$role');
        expect(
          args,
          contains('integration_test/group_multi_device_real_harness.dart'),
        );
      }
    });

    for (final proofPassed in <bool>[true, false]) {
      test(
        'dependent completion survives immediate uninstall; captured proof=$proofPassed',
        () async {
          final dir = await Directory.systemTemp.createTemp(
            'b1b-terminal-barrier-',
          );
          addTearDown(() => dir.delete(recursive: true));
          final transport = _FakeAndroidAppFileTransport();
          const devices = <String, String>{
            'primary': 'physical',
            'sibling': 'emulator',
          };
          const remote = 'cache/b1b-terminal';
          final signals = SignalDir.forDirectory(
            dir,
            prefix: 'md004_',
            runId: 'run-1_',
          );
          String name(String value) =>
              File(signals.path(value)).uri.pathSegments.last;
          final linkedBytes = utf8.encode(
            jsonEncode(<String, dynamic>{
              'proof': proofPassed,
              'role': 'linked',
            }),
          );
          final ordinaryBytes = utf8.encode(
            jsonEncode(<String, dynamic>{
              'proof': proofPassed,
              'role': 'ordinary',
            }),
          );
          final completeReceived = Completer<void>();
          final acknowledged = <String, Completer<void>>{
            'primary': Completer<void>(),
            'sibling': Completer<void>(),
          };
          final exits = <String, Completer<int>>{
            'primary': Completer<int>(),
            'sibling': Completer<int>(),
          };
          transport.afterWrite = (device, _, fileName) async {
            if (device == devices['sibling'] &&
                fileName == name('linked_complete') &&
                !completeReceived.isCompleted) {
              completeReceived.complete();
            }
            for (final role in devices.keys) {
              if (device == devices[role] &&
                  fileName == name('${role}_verdict_host_captured')) {
                expect(
                  File(signals.path('linked_verdict.json')).readAsBytesSync(),
                  linkedBytes,
                );
                expect(
                  File(signals.path('ordinary_verdict.json')).readAsBytesSync(),
                  ordinaryBytes,
                );
                acknowledged[role]!.complete();
                // Model Flutter removing this sandbox before the next ACK.
                await exits[role]!.future;
              }
            }
          };
          Future<void> actor(String role) async {
            if (role == 'sibling') await completeReceived.future;
            await writeGroupMultiPartyVerdictAndAwaitHostCapture(
              role: role,
              requireHostCapture: true,
              writeVerdict: () {
                transport.seed(
                  devices[role]!,
                  remote,
                  name(
                    role == 'primary'
                        ? 'linked_verdict.json'
                        : 'ordinary_verdict.json',
                  ),
                  role == 'primary' ? linkedBytes : ordinaryBytes,
                );
                if (role == 'primary') {
                  transport.seed(
                    devices[role]!,
                    remote,
                    name('linked_complete'),
                    utf8.encode('ok'),
                  );
                }
              },
              waitForSignal: (signal) {
                expect(signal, '${role}_verdict_host_captured');
                return acknowledged[role]!.future;
              },
            );
            transport.events.add('uninstalled:${devices[role]}');
            transport.unavailableDeviceIds.add(devices[role]!);
            exits[role]!.complete(0);
          }

          final primary = actor('primary');
          final sibling = actor('sibling');
          final broker = AndroidAppSignalBroker(
            transport: transport,
            deviceIds: devices.values.toList(),
            hostDirectory: dir,
            remoteDirectory: remote,
            filePrefix: 'md004_run-1_',
            pollInterval: Duration.zero,
            stableReadDelay: Duration.zero,
          );
          final brokerRun = broker.run();
          final verdicts = await captureB1bTerminalVerdicts(
            signals: signals,
            broker: broker,
            brokerRun: brokerRun,
            roleDevices: devices,
            roleExits: exits.map((role, exit) => MapEntry(role, exit.future)),
            verdictTimeout: const Duration(seconds: 2),
          );
          await Future.wait(<Future<void>>[primary, sibling]);
          expect(completeReceived.isCompleted, isTrue);
          expect(verdicts, <Map<String, dynamic>>[
            <String, dynamic>{'proof': proofPassed, 'role': 'linked'},
            <String, dynamic>{'proof': proofPassed, 'role': 'ordinary'},
          ]);
          for (final device in devices.values) {
            final uninstall = transport.events.indexOf('uninstalled:$device');
            expect(uninstall, isNonNegative);
            expect(
              transport.events
                  .skip(uninstall + 1)
                  .where((event) => event.contains(device)),
              isEmpty,
            );
          }
          expect(
            transport.readCounts.keys.where(
              (key) => key.endsWith('verdict_host_captured'),
            ),
            isEmpty,
          );
        },
      );
    }

    for (final failure in <String>[
      'early exit',
      'missing capture',
      'conflicting capture',
    ]) {
      test('$failure never acknowledges and stops the broker', () async {
        final dir = await Directory.systemTemp.createTemp(
          'b1b-terminal-failure-',
        );
        addTearDown(() => dir.delete(recursive: true));
        final transport = _FakeAndroidAppFileTransport();
        const devices = <String, String>{
          'primary': 'physical',
          'sibling': 'emulator',
        };
        const remote = 'cache/b1b-terminal';
        final signals = SignalDir.forDirectory(
          dir,
          prefix: 'md004_',
          runId: 'run-1_',
        );
        final exits = <String, Completer<int>>{
          'primary': Completer<int>(),
          'sibling': Completer<int>(),
        };
        if (failure == 'early exit') exits['primary']!.complete(0);
        if (failure == 'conflicting capture') {
          signals.writeJson('linked_verdict.json', <String, dynamic>{
            'proof': false,
          });
          transport.seed(
            'physical',
            remote,
            'md004_run-1_linked_verdict.json',
            utf8.encode('{"proof":true}'),
          );
        }
        final broker = AndroidAppSignalBroker(
          transport: transport,
          deviceIds: devices.values.toList(),
          hostDirectory: dir,
          remoteDirectory: remote,
          filePrefix: 'md004_run-1_',
          pollInterval: Duration.zero,
          stableReadDelay: Duration.zero,
        );
        final brokerRun = broker.run();
        await expectLater(
          captureB1bTerminalVerdicts(
            signals: signals,
            broker: broker,
            brokerRun: brokerRun,
            roleDevices: devices,
            roleExits: exits.map((role, exit) => MapEntry(role, exit.future)),
            verdictTimeout: const Duration(milliseconds: 30),
          ),
          throwsA(
            anyOf(isA<StateError>(), isA<AndroidSignalProtocolException>()),
          ),
        );
        if (failure == 'conflicting capture') {
          await expectLater(
            brokerRun,
            throwsA(isA<AndroidSignalProtocolException>()),
          );
        } else {
          await brokerRun;
        }
        expect(
          transport.events.where(
            (event) => event.contains('verdict_host_captured'),
          ),
          isEmpty,
        );
      });
    }
  });

  group('strict Android verdict host-capture handshake', () {
    test(
      'keeps the harness alive until its role acknowledgement arrives',
      () async {
        final acknowledgement = Completer<void>();
        final events = <String>[];
        var completed = false;

        final lifecycle = writeGroupMultiPartyVerdictAndAwaitHostCapture(
          role: 'charlie',
          requireHostCapture: true,
          writeVerdict: () => events.add('verdict-written'),
          waitForSignal: (signalName) {
            events.add('waiting:$signalName');
            return acknowledgement.future;
          },
        ).then((_) => completed = true);
        await Future<void>.delayed(Duration.zero);

        expect(events, <String>[
          'verdict-written',
          'waiting:charlie_verdict_host_captured',
        ]);
        expect(completed, isFalse);

        acknowledgement.complete();
        await lifecycle;
        expect(completed, isTrue);
      },
    );

    test(
      'quiesces after all verdicts, then never revisits an acked role',
      () async {
        final hostDirectory = await Directory.systemTemp.createTemp(
          'group_multi_party_targeted_ack_',
        );
        addTearDown(() async {
          if (hostDirectory.existsSync()) {
            await hostDirectory.delete(recursive: true);
          }
        });
        final transport = _FakeAndroidAppFileTransport();
        const devices = <String>['android-charlie', 'android-bob'];
        const remoteDirectory = 'cache/group_multi_party_h01_run-1';
        final signals = SignalDir.forDirectory(
          hostDirectory,
          prefix: 'gmp_',
          runId: 'run-1_',
          role: 'test',
        );
        final broker = AndroidAppSignalBroker(
          transport: transport,
          deviceIds: devices,
          hostDirectory: hostDirectory,
          remoteDirectory: remoteDirectory,
          filePrefix: 'gmp_run-1_',
          stableReadDelay: Duration.zero,
        );
        final captured = <String, Completer<Map<String, dynamic>>>{
          for (final role in const <String>['charlie', 'bob'])
            role: Completer<Map<String, dynamic>>(),
        };
        final lifecycleEvents = <String>[];
        final lifecycle =
            captureGroupMultiPartyVerdictsAtTerminalBarrier<
              Map<String, dynamic>
            >(
              roles: const <String>['charlie', 'bob'],
              acknowledgeHostCapture: true,
              captureVerdict: (role) {
                lifecycleEvents.add('capture:$role');
                return captured[role]!.future;
              },
              synchronizeHeldRoles: () async {
                lifecycleEvents.add('sync-held');
                await broker.synchronizeOnce();
              },
              stopSignalBroker: () async {
                lifecycleEvents.add('broker-stopped');
                broker.stop();
              },
              deliverAcknowledgement: (role, logicalName) async {
                lifecycleEvents.add('ack:$role');
                await broker.deliverTerminalHostSignalToDevice(
                  deviceId: role == 'charlie' ? devices.first : devices.last,
                  name: groupMultiPartyBrokerSignalFileName(
                    signals: signals,
                    logicalName: logicalName,
                  ),
                  bytes: utf8.encode('ok'),
                );
                if (role == 'charlie') {
                  transport.events.add('uninstalled:${devices.first}');
                  transport.unavailableDeviceIds.add(devices.first);
                }
              },
              awaitRoleExit: (role) async {
                lifecycleEvents.add('exit:$role');
              },
            );
        await Future<void>.delayed(Duration.zero);
        expect(lifecycleEvents, <String>['capture:charlie', 'capture:bob']);

        captured['charlie']!.complete(<String, dynamic>{'role': 'charlie'});
        await Future<void>.delayed(Duration.zero);
        expect(lifecycleEvents, <String>[
          'capture:charlie',
          'capture:bob',
        ], reason: 'no acknowledgement may release a role before all verdicts');

        captured['bob']!.complete(<String, dynamic>{'role': 'bob'});
        expect(await lifecycle, <Map<String, dynamic>>[
          <String, dynamic>{'role': 'charlie'},
          <String, dynamic>{'role': 'bob'},
        ]);
        expect(lifecycleEvents, <String>[
          'capture:charlie',
          'capture:bob',
          'sync-held',
          'broker-stopped',
          'ack:charlie',
          'ack:bob',
          'exit:charlie',
          'exit:bob',
        ]);

        expect(
          utf8.decode(
            transport.bytes(
              devices.last,
              remoteDirectory,
              'gmp_run-1_bob_verdict_host_captured',
            )!,
          ),
          'ok',
        );
        expect(signals.read('bob_verdict_host_captured'), 'ok');
        final uninstallIndex = transport.events.indexOf(
          'uninstalled:${devices.first}',
        );
        expect(uninstallIndex, greaterThanOrEqualTo(0));
        expect(
          transport.events
              .skip(uninstallIndex + 1)
              .where((event) => event.contains(devices.first)),
          isEmpty,
          reason: 'terminal delivery must never revisit an uninstalled role',
        );
        expect(
          transport.readCounts.keys.where(
            (key) => key.endsWith('verdict_host_captured'),
          ),
          isEmpty,
          reason: 'terminal acknowledgements must not be read back',
        );
      },
    );

    test('leaves legacy and iOS verdict publication non-waiting', () async {
      var waited = false;
      var synchronized = false;
      var stopped = false;
      var delivered = false;
      var exited = false;

      await writeGroupMultiPartyVerdictAndAwaitHostCapture(
        role: 'alice',
        requireHostCapture: false,
        writeVerdict: () {},
        waitForSignal: (_) {
          waited = true;
          return Future<void>.value();
        },
      );

      expect(waited, isFalse);
      await captureGroupMultiPartyVerdictsAtTerminalBarrier<void>(
        roles: const <String>['alice'],
        acknowledgeHostCapture: false,
        captureVerdict: (_) async {},
        synchronizeHeldRoles: () async {
          synchronized = true;
        },
        stopSignalBroker: () async {
          stopped = true;
        },
        deliverAcknowledgement: (role, signalName) async {
          delivered = true;
        },
        awaitRoleExit: (_) async {
          exited = true;
        },
      );
      expect(synchronized, isFalse);
      expect(stopped, isFalse);
      expect(delivered, isFalse);
      expect(exited, isTrue);
    });
  });

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

    test('selects the strict harness only for generic Android launches', () {
      HarnessLaunchSpec specFor(
        String deviceId, {
        bool requireAndroidRuntimeConfig = false,
      }) {
        return buildHarnessLaunchSpec(
          scenario: 'private_voluntary_leave_convergence',
          role: 'alice',
          deviceId: deviceId,
          sharedDir: Directory('/tmp/gmp-h01'),
          runId: 'run-1',
          relayAddresses: '127.0.0.1:4001',
          requireAndroidRuntimeConfig: requireAndroidRuntimeConfig,
        );
      }

      final strictAndroid = specFor(
        'emulator-5554',
        requireAndroidRuntimeConfig: true,
      );
      final specializedAndroid = specFor('emulator-5554');
      final ios = specFor('38FECA55-03C1-4907-BD9D-8E64BF8E3469');

      expect(
        strictAndroid.args,
        contains(
          'integration_test/'
          'group_multi_party_device_real_android_harness.dart',
        ),
      );
      expect(
        specializedAndroid.args,
        contains('integration_test/group_multi_party_device_real_harness.dart'),
      );
      expect(
        ios.args,
        contains(
          '--target=integration_test/'
          'group_multi_party_device_real_harness.dart',
        ),
      );
    });
  });

  group('Android GMP runtime transport', () {
    test(
      'non-strict Android ignores stale strict config while iOS preserves it',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'group_multi_party_harness_entrypoint_',
        );
        addTearDown(() async {
          if (directory.existsSync()) {
            await directory.delete(recursive: true);
          }
        });
        final configFile = File(
          '${directory.path}/$groupMultiPartyRuntimeConfigFileName',
        );
        await configFile.writeAsString(
          jsonEncode(
            const GroupMultiPartyRuntimeConfig(
              sharedDir: '/stale/android/signal-dir',
              role: 'charlie',
              scenario: 'private_voluntary_leave_convergence',
              runId: 'stale-run',
              mode: 'proof',
              restoreMnemonic: '',
              restoreIdentityPath: '',
              reuseExistingIdentity: false,
              dbName: 'stale.db',
            ).toJson(),
          ),
          flush: true,
        );
        var nonStrictAndroidResolvedDocuments = false;

        expect(
          await loadGroupMultiPartyHarnessRuntimeConfigValues(
            isAndroid: true,
            requireAndroidRuntimeConfig: false,
            resolveFinalConfigFile: () async {
              nonStrictAndroidResolvedDocuments = true;
              return configFile;
            },
          ),
          isEmpty,
        );
        expect(nonStrictAndroidResolvedDocuments, isFalse);
        expect(
          await loadGroupMultiPartyHarnessRuntimeConfigValues(
            isAndroid: false,
            requireAndroidRuntimeConfig: false,
            resolveFinalConfigFile: () async => configFile,
          ),
          containsPair(
            groupMultiPartyScenarioKey,
            'private_voluntary_leave_convergence',
          ),
        );
        expect(
          await loadGroupMultiPartyHarnessRuntimeConfigValues(
            isAndroid: true,
            requireAndroidRuntimeConfig: true,
            resolveFinalConfigFile: () async => configFile,
          ),
          containsPair(groupMultiPartyRunIdKey, 'stale-run'),
        );
      },
    );

    test(
      'framed ADB read never treats an exit-zero missing diagnostic as bytes',
      () async {
        const nonce = 'causal_missing_read';
        final codec = AndroidAppFileReadFrameCodec(nonce);
        var responseBytes = codec.missingFrame;
        var responseExitCode = 0;
        Encoding? requestedStdoutEncoding;
        final commands = <List<String>>[];
        final transport = AdbRunAsAppFileTransport(
          appPackage: 'com.mknoon.app',
          readFrameNonceFactory: () => nonce,
          commandRunner: (deviceId, arguments, {stdoutEncoding}) async {
            expect(deviceId, 'android-a');
            requestedStdoutEncoding = stdoutEncoding;
            commands.add(List<String>.from(arguments));
            return ProcessResult(
              1234,
              responseExitCode,
              List<int>.from(responseBytes),
              'framed stderr',
            );
          },
        );

        expect(
          await transport.readFile(
            'android-a',
            'app_flutter',
            groupMultiPartyRuntimeConfigFileName,
          ),
          isNull,
        );
        expect(requestedStdoutEncoding, isNull);
        expect(commands.single, <String>[
          'exec-out',
          'run-as',
          'com.mknoon.app',
          'sh',
          '-c',
          'path="\$1"; '
              'if [ ! -e "\$path" ]; then '
              "printf '%s' '${codec.missingMarker}'; exit 0; "
              'fi; '
              'if [ ! -f "\$path" ]; then '
              "printf '%s' '${codec.errorMarker}'; exit 41; "
              'fi; '
              "printf '%s' '${codec.presentPrefixMarker}'; "
              'if ! cat "\$path"; then exit 42; fi; '
              "printf '%s' '${codec.presentSuffixMarker}'",
          'mknoon-read',
          'app_flutter/$groupMultiPartyRuntimeConfigFileName',
        ]);

        final exactBytes = <int>[
          0,
          10,
          13,
          255,
          ...utf8.encode(codec.missingMarker),
        ];
        responseBytes = codec.encodePresentFrame(exactBytes);
        expect(
          await transport.readFile(
            'android-a',
            'app_flutter',
            groupMultiPartyRuntimeConfigFileName,
          ),
          exactBytes,
        );

        responseBytes = utf8.encode(
          'cat: app_flutter/$groupMultiPartyRuntimeConfigFileName: '
          'No such file or directory\n',
        );
        await expectLater(
          transport.readFile(
            'android-a',
            'app_flutter',
            groupMultiPartyRuntimeConfigFileName,
          ),
          throwsA(
            isA<AndroidAppFileTransportException>().having(
              (error) => error.message,
              'message',
              contains('Malformed framed Android app-file read'),
            ),
          ),
        );

        responseExitCode = 0;
        responseBytes = codec.errorFrame;
        await expectLater(
          transport.readFile(
            'android-a',
            'app_flutter',
            groupMultiPartyRuntimeConfigFileName,
          ),
          throwsA(
            isA<AndroidAppFileTransportException>().having(
              (error) => error.message,
              'message',
              contains('explicit error frame'),
            ),
          ),
        );
      },
    );

    test(
      'prelaunch removes stale final and pending config after force-stop',
      () async {
        final transport = _FakeAndroidAppFileTransport()..processId = 'old-pid';
        const deviceId = 'android-a';
        const directory = 'app_flutter';
        const fileName = groupMultiPartyRuntimeConfigFileName;
        transport.seed(deviceId, directory, fileName, utf8.encode('stale'));
        transport.seed(
          deviceId,
          directory,
          '.$fileName.host_pending',
          utf8.encode('partial'),
        );

        await prepareAndroidAppForFreshLaunch(
          transport: transport,
          deviceId: deviceId,
          configDirectory: directory,
          configFileName: fileName,
          delay: (_) async {},
        );

        expect(transport.processId, isNull);
        expect(transport.bytes(deviceId, directory, fileName), isNull);
        expect(
          transport.bytes(deviceId, directory, '.$fileName.host_pending'),
          isNull,
        );
        final forceStop = transport.events.indexOf('force-stop:$deviceId');
        final deleteFinal = transport.events.indexOf(
          'delete:$deviceId:$directory:$fileName',
        );
        final deletePending = transport.events.indexOf(
          'delete:$deviceId:$directory:.$fileName.host_pending',
        );
        expect(forceStop, greaterThanOrEqualTo(0));
        expect(forceStop, lessThan(deleteFinal));
        expect(deleteFinal, lessThan(deletePending));
      },
    );

    test(
      'post-launch staging waits for a new pid and stable exact bytes',
      () async {
        final transport = _FakeAndroidAppFileTransport();
        final processExit = Completer<int>();
        const deviceId = 'android-a';
        const directory = 'app_flutter';
        const signalDirectory = 'cache/group_multi_party_h01_run-1';
        const fileName = groupMultiPartyRuntimeConfigFileName;
        var releasedNewProcess = false;

        final processId = await stageAndroidAppFileAfterLaunch(
          transport: transport,
          deviceId: deviceId,
          relativeDirectory: directory,
          fileName: fileName,
          prepareForWrite: (_) =>
              transport.ensureDirectory(deviceId, signalDirectory),
          bytesForProcess: (pid) async {
            final appDataDir = await transport.appDataDirectory(deviceId);
            return utf8.encode(
              jsonEncode(<String, Object?>{
                'pid': pid,
                groupMultiPartySharedDirKey:
                    '$appDataDir/cache/group_multi_party_h01_run-1',
              }),
            );
          },
          launchedProcessExitCode: processExit.future,
          retryInterval: const Duration(milliseconds: 1),
          stableReadDelay: const Duration(milliseconds: 1),
          delay: (_) async {
            if (!releasedNewProcess) {
              releasedNewProcess = true;
              transport.processId = 'new-pid';
            }
          },
        );

        expect(processId, 'new-pid');
        final staged =
            jsonDecode(
                  utf8.decode(transport.bytes(deviceId, directory, fileName)!),
                )
                as Map<String, dynamic>;
        expect(staged['pid'], 'new-pid');
        expect(
          staged[groupMultiPartySharedDirKey],
          '/data/user/0/com.mknoon.app/'
          'cache/group_multi_party_h01_run-1',
        );
        expect(
          transport.readCounts['$deviceId:$directory:$fileName'],
          greaterThanOrEqualTo(2),
        );
        expect(
          transport.events.indexWhere((event) => event.startsWith('pid:')),
          lessThan(
            transport.events.indexOf('write:$deviceId:$directory:$fileName'),
          ),
        );
        expect(
          transport.events.indexOf('mkdir:$deviceId:$signalDirectory'),
          lessThan(
            transport.events.indexOf('write:$deviceId:$directory:$fileName'),
          ),
        );
      },
    );

    test('post-launch staging surfaces Flutter exit before config', () async {
      final transport = _FakeAndroidAppFileTransport();
      final processExit = Completer<int>()..complete(1);

      await expectLater(
        stageAndroidAppFileAfterLaunch(
          transport: transport,
          deviceId: 'android-a',
          relativeDirectory: 'app_flutter',
          fileName: groupMultiPartyRuntimeConfigFileName,
          bytesForProcess: (_) async => utf8.encode('{}'),
          launchedProcessExitCode: processExit.future,
          timeout: const Duration(seconds: 1),
          retryInterval: const Duration(milliseconds: 1),
          delay: (_) => Future<void>.delayed(Duration.zero),
        ),
        throwsA(
          isA<StateError>().having(
            (error) => '$error',
            'message',
            contains('exited with code 1'),
          ),
        ),
      );
    });

    test('three-device broker converges exact stable gmp files', () async {
      final hostDirectory = await Directory.systemTemp.createTemp(
        'group_multi_party_android_broker_',
      );
      addTearDown(() async {
        if (hostDirectory.existsSync()) {
          await hostDirectory.delete(recursive: true);
        }
      });
      final transport = _FakeAndroidAppFileTransport();
      const devices = <String>['android-a', 'android-b', 'android-c'];
      const remoteDirectory = 'cache/group_multi_party_private_leave_run-1';
      const prefix = 'gmp_run-1_';
      final expectedByName = <String, List<int>>{
        '${prefix}alice_identity.json': utf8.encode('{"role":"alice"}'),
        '${prefix}bob_identity.json': utf8.encode('{"role":"bob"}'),
        '${prefix}charlie_identity.json': utf8.encode('{"role":"charlie"}'),
      };
      for (var index = 0; index < devices.length; index++) {
        final entry = expectedByName.entries.elementAt(index);
        transport.seed(devices[index], remoteDirectory, entry.key, entry.value);
      }
      final broker = AndroidAppSignalBroker(
        transport: transport,
        deviceIds: devices,
        hostDirectory: hostDirectory,
        remoteDirectory: remoteDirectory,
        filePrefix: prefix,
        delay: (_) async {},
      );

      await broker.synchronizeOnce();

      for (final entry in expectedByName.entries) {
        expect(
          await File('${hostDirectory.path}/${entry.key}').readAsBytes(),
          entry.value,
        );
        for (final deviceId in devices) {
          expect(
            transport.bytes(deviceId, remoteDirectory, entry.key),
            entry.value,
          );
        }
      }
      expect(
        transport.readCounts['${devices.first}:$remoteDirectory:'
            '${prefix}alice_identity.json'],
        greaterThanOrEqualTo(2),
      );

      final readsAfterFirstPass = Map<String, int>.from(transport.readCounts);
      await broker.synchronizeOnce();
      expect(
        transport.readCounts,
        readsAfterFirstPass,
        reason: 'confirmed immutable finals must not be reread every pass',
      );
    });

    test('broker ignores harness atomic temp and host-pending files', () async {
      final hostDirectory = await Directory.systemTemp.createTemp(
        'group_multi_party_android_broker_temp_',
      );
      addTearDown(() async {
        if (hostDirectory.existsSync()) {
          await hostDirectory.delete(recursive: true);
        }
      });
      final transport = _FakeAndroidAppFileTransport();
      const devices = <String>['android-a', 'android-b', 'android-c'];
      const remoteDirectory = 'cache/group_multi_party_h01_run-1';
      const prefix = 'gmp_run-1_';
      const finalName = '${prefix}alice_verdict.json';
      const atomicTempName = '${prefix}alice_verdict.json.tmp.4321.987654321';
      const hostPendingName = '${prefix}alice_verdict.json.host_pending';
      transport
        ..seed(
          devices.first,
          remoteDirectory,
          finalName,
          utf8.encode('{"ok":true}'),
        )
        ..seed(
          devices.first,
          remoteDirectory,
          atomicTempName,
          utf8.encode('partial'),
        )
        ..seed(
          devices.first,
          remoteDirectory,
          hostPendingName,
          utf8.encode('pending'),
        );
      final broker = AndroidAppSignalBroker(
        transport: transport,
        deviceIds: devices,
        hostDirectory: hostDirectory,
        remoteDirectory: remoteDirectory,
        filePrefix: prefix,
        stableReadDelay: Duration.zero,
      );

      await broker.synchronizeOnce();

      expect(File('${hostDirectory.path}/$finalName').existsSync(), isTrue);
      expect(
        File('${hostDirectory.path}/$atomicTempName').existsSync(),
        isFalse,
      );
      expect(
        File('${hostDirectory.path}/$hostPendingName').existsSync(),
        isFalse,
      );
      for (final deviceId in devices.skip(1)) {
        expect(
          transport.bytes(deviceId, remoteDirectory, atomicTempName),
          isNull,
        );
        expect(
          transport.bytes(deviceId, remoteDirectory, hostPendingName),
          isNull,
        );
      }
    });

    test(
      'process-exit drain waits for the active pass then pulls exact verdict',
      () async {
        final hostDirectory = await Directory.systemTemp.createTemp(
          'group_multi_party_android_broker_drain_',
        );
        addTearDown(() async {
          if (hostDirectory.existsSync()) {
            await hostDirectory.delete(recursive: true);
          }
        });
        final transport = _FakeAndroidAppFileTransport();
        const devices = <String>['android-a', 'android-b', 'android-c'];
        const remoteDirectory = 'cache/group_multi_party_h01_run-1';
        const prefix = 'gmp_run-1_';
        const logicalVerdictName = 'charlie_verdict.json';
        final signals = SignalDir.forDirectory(
          hostDirectory,
          prefix: 'gmp_',
          runId: 'run-1_',
          role: 'test',
        );
        final verdictName = groupMultiPartyBrokerSignalFileName(
          signals: signals,
          logicalName: logicalVerdictName,
        );
        expect(verdictName, '${prefix}charlie_verdict.json');
        for (var index = 0; index < 12; index++) {
          final deviceId = devices[index % 2];
          transport.seed(
            deviceId,
            remoteDirectory,
            '${prefix}history_$index.json',
            utf8.encode('{"index":$index}'),
          );
        }
        final sourceSnapshotTaken = Completer<void>();
        final releaseActivePass = Completer<void>();
        transport.afterListFiles = (deviceId, _, _) async {
          if (deviceId == devices.last && !sourceSnapshotTaken.isCompleted) {
            sourceSnapshotTaken.complete();
            await releaseActivePass.future;
          }
        };
        final broker = AndroidAppSignalBroker(
          transport: transport,
          deviceIds: devices,
          hostDirectory: hostDirectory,
          remoteDirectory: remoteDirectory,
          filePrefix: prefix,
          pollInterval: const Duration(days: 1),
          stableReadDelay: Duration.zero,
        );
        final runFuture = broker.run();

        await sourceSnapshotTaken.future;
        final processExit = Completer<int>()..complete(0);
        expect(await processExit.future, 0);
        transport.events.add('process-exit:0');
        transport.seed(
          devices.last,
          remoteDirectory,
          verdictName,
          utf8.encode('{"ok":true}'),
        );
        final drainFuture = broker.drainSignalToHost(
          deviceId: devices.last,
          name: verdictName,
          timeout: const Duration(seconds: 2),
        );
        await Future<void>.delayed(Duration.zero);
        expect(
          transport.readCounts['${devices.last}:$remoteDirectory:$verdictName'],
          isNull,
          reason: 'the targeted drain must queue behind the active pass',
        );

        releaseActivePass.complete();
        expect(await drainFuture, isTrue);
        expect(
          jsonDecode(signals.read(logicalVerdictName)!),
          containsPair('ok', true),
        );
        expect(
          transport.events.indexOf('process-exit:0'),
          lessThan(
            transport.events.indexOf(
              'read:${devices.last}:$remoteDirectory:$verdictName',
            ),
          ),
        );

        broker.stop();
        await runFuture.timeout(const Duration(seconds: 1));
      },
    );

    test('stop wakes a pending poll and is idempotent', () async {
      final hostDirectory = await Directory.systemTemp.createTemp(
        'group_multi_party_android_broker_stop_poll_',
      );
      addTearDown(() async {
        if (hostDirectory.existsSync()) {
          await hostDirectory.delete(recursive: true);
        }
      });
      final pollStarted = Completer<void>();
      final neverReleasePoll = Completer<void>();
      final broker = AndroidAppSignalBroker(
        transport: _FakeAndroidAppFileTransport(),
        deviceIds: const <String>['android-a'],
        hostDirectory: hostDirectory,
        remoteDirectory: 'cache/group_multi_party_h01_run-1',
        filePrefix: 'gmp_run-1_',
        pollInterval: const Duration(days: 1),
        stableReadDelay: Duration.zero,
        delay: (duration) {
          if (!pollStarted.isCompleted) pollStarted.complete();
          return neverReleasePoll.future;
        },
      );
      final runFuture = broker.run();

      await pollStarted.future;
      broker
        ..stop()
        ..stop();

      await runFuture.timeout(const Duration(seconds: 1));
      expect(neverReleasePoll.isCompleted, isFalse);
    });

    test('stop observed inside a pass prevents later device work', () async {
      final hostDirectory = await Directory.systemTemp.createTemp(
        'group_multi_party_android_broker_stop_pass_',
      );
      addTearDown(() async {
        if (hostDirectory.existsSync()) {
          await hostDirectory.delete(recursive: true);
        }
      });
      final transport = _FakeAndroidAppFileTransport();
      final firstListCaptured = Completer<void>();
      final releaseFirstList = Completer<void>();
      transport.afterListFiles = (deviceId, _, _) async {
        if (deviceId == 'android-a' && !firstListCaptured.isCompleted) {
          firstListCaptured.complete();
          await releaseFirstList.future;
        }
      };
      final broker = AndroidAppSignalBroker(
        transport: transport,
        deviceIds: const <String>['android-a', 'android-b'],
        hostDirectory: hostDirectory,
        remoteDirectory: 'cache/group_multi_party_h01_run-1',
        filePrefix: 'gmp_run-1_',
        stableReadDelay: Duration.zero,
      );
      final runFuture = broker.run();

      await firstListCaptured.future;
      broker.stop();
      releaseFirstList.complete();
      await runFuture.timeout(const Duration(seconds: 1));

      expect(
        transport.events,
        isNot(contains('list:android-b:cache/group_multi_party_h01_run-1')),
      );
    });

    test(
      'broker makes conflicting, unsafe, and oversized signals fatal',
      () async {
        final hostDirectory = await Directory.systemTemp.createTemp(
          'group_multi_party_android_broker_fatal_',
        );
        addTearDown(() async {
          if (hostDirectory.existsSync()) {
            await hostDirectory.delete(recursive: true);
          }
        });
        const remoteDirectory = 'cache/group_multi_party_h01_run-1';
        const prefix = 'gmp_run-1_';

        final conflicting = _FakeAndroidAppFileTransport()
          ..seed(
            'android-a',
            remoteDirectory,
            '${prefix}alice_identity.json',
            utf8.encode('alice-a'),
          )
          ..seed(
            'android-b',
            remoteDirectory,
            '${prefix}alice_identity.json',
            utf8.encode('alice-b'),
          );
        await expectLater(
          AndroidAppSignalBroker(
            transport: conflicting,
            deviceIds: const <String>['android-a', 'android-b', 'android-c'],
            hostDirectory: hostDirectory,
            remoteDirectory: remoteDirectory,
            filePrefix: prefix,
            delay: (_) async {},
          ).synchronizeOnce(),
          throwsA(isA<AndroidSignalProtocolException>()),
        );

        await hostDirectory.delete(recursive: true);
        await hostDirectory.create(recursive: true);
        final unsafe = _FakeAndroidAppFileTransport()
          ..seed(
            'android-a',
            remoteDirectory,
            '${prefix}bad name.json',
            utf8.encode('unsafe'),
          );
        await expectLater(
          AndroidAppSignalBroker(
            transport: unsafe,
            deviceIds: const <String>['android-a', 'android-b', 'android-c'],
            hostDirectory: hostDirectory,
            remoteDirectory: remoteDirectory,
            filePrefix: prefix,
            delay: (_) async {},
          ).synchronizeOnce(),
          throwsA(isA<AndroidSignalProtocolException>()),
        );

        await hostDirectory.delete(recursive: true);
        await hostDirectory.create(recursive: true);
        final oversized = _FakeAndroidAppFileTransport()
          ..seed(
            'android-a',
            remoteDirectory,
            '${prefix}alice_identity.json',
            utf8.encode('too-large'),
          );
        await expectLater(
          AndroidAppSignalBroker(
            transport: oversized,
            deviceIds: const <String>['android-a', 'android-b', 'android-c'],
            hostDirectory: hostDirectory,
            remoteDirectory: remoteDirectory,
            filePrefix: prefix,
            maximumSignalBytes: 3,
            delay: (_) async {},
          ).synchronizeOnce(),
          throwsA(isA<AndroidSignalProtocolException>()),
        );
      },
    );

    test('scenario and run id jointly namespace Android signals', () {
      expect(
        groupMultiPartyAndroidSignalDirectory(
          scenario: 'private/leave',
          runId: 'shared run',
        ),
        'cache/group_multi_party_private_leave_shared_run',
      );
      expect(
        groupMultiPartyAndroidSignalDirectory(
          scenario: 'gm015',
          runId: 'shared run',
        ),
        'cache/group_multi_party_gm015_shared_run',
      );
    });

    test(
      'generic runner drains logs before staging and races broker failures',
      () {
        final source = File(
          'integration_test/scripts/run_group_multi_party_device_real.dart',
        ).readAsStringSync();
        final startRole = source.indexOf('Future<Process> _startHarnessRole({');
        final startProcess = source.indexOf(
          "final process = await Process.start('flutter', launchSpec.args);",
          startRole,
        );
        final attachLogs = source.indexOf(
          'onProcessStarted?.call(process);',
          startProcess,
        );
        final stageConfig = source.indexOf(
          'stageAndroidAppFileAfterLaunch(',
          attachLogs,
        );
        final prepareSignalDirectory = source.indexOf(
          'prepareForWrite: (_)',
          stageConfig,
        );
        final encodeRuntimeConfig = source.indexOf(
          'bytesForProcess: (processId)',
          prepareSignalDirectory,
        );
        final genericStart = source.indexOf('Future<void> _runScenario({');
        final specializedStart = source.indexOf(
          'Future<void> _runGe014Scenario({',
          genericStart,
        );
        final genericSource = source.substring(genericStart, specializedStart);
        final startBroker = genericSource.indexOf(
          'final signalBrokerRun = signalBroker?.run();',
        );
        final captureBroker = genericSource.indexOf(
          '_captureSignalBrokerOutcome(signalBrokerRun)',
          startBroker,
        );
        final wrapperSource = File(
          'integration_test/'
          'group_multi_party_device_real_android_harness.dart',
        ).readAsStringSync();
        final sharedHarnessSource = File(
          'integration_test/group_multi_party_device_real_harness.dart',
        ).readAsStringSync();

        expect(startRole, greaterThanOrEqualTo(0));
        expect(startRole, lessThan(startProcess));
        expect(startProcess, lessThan(attachLogs));
        expect(attachLogs, lessThan(stageConfig));
        expect(stageConfig, lessThan(prepareSignalDirectory));
        expect(prepareSignalDirectory, lessThan(encodeRuntimeConfig));
        expect(
          source,
          contains('requireAndroidRuntimeConfig: androidFileTransport != null'),
        );
        expect(
          RegExp('AndroidAppSignalBroker\\(').allMatches(genericSource),
          hasLength(1),
        );
        expect(
          RegExp(
            'signalBrokerOutcome: signalBrokerOutcome',
          ).allMatches(genericSource),
          hasLength(2),
        );
        expect(startBroker, greaterThanOrEqualTo(0));
        expect(startBroker, lessThan(captureBroker));
        expect(genericSource, isNot(contains('await signalBrokerRun')));
        expect(
          genericSource,
          contains(
            'synchronizeHeldRoles: () => signalBroker!.synchronizeOnce()',
          ),
        );
        expect(genericSource, contains('deliverTerminalHostSignalToDevice('));
        expect(
          genericSource,
          contains('final cleanupBrokerOutcome = await signalBrokerOutcome;'),
        );
        expect(genericSource, contains('signalBroker?.stop();'));
        expect(wrapperSource, contains('requireAndroidRuntimeConfig: true'));
        expect(
          sharedHarnessSource,
          contains('requireAndroidRuntimeConfig: false'),
        );
        expect(
          sharedHarnessSource,
          contains('timeout: const Duration(minutes: 20)'),
        );
      },
    );
  });
}
