import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/support/android_app_state_guard.dart';
import '../../integration_test/support/production_android_journey.dart';
import '../../integration_test/support/production_ios_simulator_journey.dart';
import '../../tool/sims/build_orchestrator.dart';

final class _IdleDevices implements AndroidHostProcessRunner {
  @override
  Future<ProcessResult> run(String executable, List<String> arguments) async {
    expect(executable, 'adb');
    expect(arguments.first, '-s');
    expect(
      arguments[1],
      anyOf('emulator-4004', 'fixture-phone-1', 'emulator-5556'),
    );
    expect(arguments, isNot(contains('start')));
    if (arguments.contains('getprop')) return ProcessResult(0, 0, '36\n', '');
    return ProcessResult(
      0,
      0,
      arguments.contains('get-state') ? 'device\n' : '',
      '',
    );
  }
}

final class _Guard implements ProductionAndroidInstallGuard {
  _Guard(
    this.name,
    this.events, {
    this.failInstall = false,
    this.failRestore = false,
  });
  final String name;
  final List<String> events;
  final bool failInstall, failRestore;

  @override
  Future<void> prepareFreshInstall({
    required String device,
    required File artifact,
  }) async {
    events.add('install:$name:$device:${artifact.path}');
    if (failInstall) throw StateError('controlled install failure');
  }

  @override
  Future<void> restoreAll() async {
    events.add('restore:$name');
    if (failRestore) throw StateError('controlled restore failure');
  }
}

void main() {
  late Directory temporary;
  late Directory cache;
  const primary = 'android.e2e.production';
  const receiver = 'android.production_fcm.journey';
  const physical = 'fixture-phone-1';
  const emulator = 'emulator-5556';
  final input = sha256.convert(utf8.encode('source')).toString();

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('journey-guards-');
    cache = Directory('${temporary.path}/cache')..createSync();
  });
  tearDown(() async => temporary.delete(recursive: true));

  (File, String) prepared(String profile) {
    final artifact = File('${cache.path}/$profile/$input/artifact.apk');
    artifact.parent.createSync(recursive: true);
    artifact.writeAsBytesSync(utf8.encode(profile));
    final digest = sha256.convert(artifact.readAsBytesSync()).toString();
    File('${artifact.parent.path}/attestation.json').writeAsStringSync(
      jsonEncode({
        'schemaVersion': 1,
        'profileId': profile,
        'inputDigest': input,
        'artifactDigest': digest,
        'artifactPath': artifact.path,
        'redactedCommand': <String>[],
        'createdAt': DateTime.utc(2026).toIso8601String(),
      }),
    );
    return (artifact, digest);
  }

  Map<String, String> environment() {
    final (sender, senderDigest) = prepared(primary);
    final (bob, bobDigest) = prepared(receiver);
    return {
      'SIMS_CACHE_DIR': cache.path,
      'SIMS_ARTIFACT_ANDROID_E2E_PRODUCTION': sender.path,
      'SIMS_ARTIFACT_INPUT_DIGEST': input,
      'SIMS_ARTIFACT_SHA256': senderDigest,
      'SIMS_ARTIFACT_ANDROID_PRODUCTION_FCM_JOURNEY': bob.path,
      'SIMS_ARTIFACT_INPUT_DIGEST_ANDROID_PRODUCTION_FCM_JOURNEY': input,
      'SIMS_ARTIFACT_SHA256_ANDROID_PRODUCTION_FCM_JOURNEY': bobDigest,
      'SIMS_ANDROID_PHYSICAL_DEVICE_ID': physical,
      'SIMS_ANDROID_EMULATOR_DEVICE_ID': emulator,
    };
  }

  test(
    'physical performance keeps its phone pin under the global disposable journey flag',
    () async {
      final values = environment()..['SIMS_DISPOSABLE_ANDROID_JOURNEYS'] = '1';
      final (apk, digest) = prepared(productionPerformanceAndroidProfile);
      values['SIMS_ARTIFACT_ANDROID_E2E_PERFORMANCE_RELAY'] = apk.path;
      values['SIMS_ARTIFACT_SHA256'] = digest;
      final events = <String>[];
      ProductionAndroidJourney create() =>
          ProductionAndroidJourney.fromEnvironment(
            'production.startup_resume_performance',
            temporary,
            environment: values,
            runner: _IdleDevices(),
            captureGuard:
                ({
                  required devices,
                  required packageName,
                  required backupLabel,
                  required preparedArtifact,
                  required expectedArtifactSha256,
                }) async {
                  expect(devices, [physical]);
                  return _Guard(packageName, events, failInstall: true);
                },
          );
      final journey = create();
      expect(journey.disposableAndroidJourneys, isFalse);
      expect(journey.physical, physical);
      expect(journey.actors, hasLength(1));
      expect(journey.profileId, productionPerformanceAndroidProfile);
      await expectLater(journey.prepare(), throwsStateError);
      expect(
        events.single,
        startsWith('install:$productionJourneyAndroidPackage:$physical:'),
      );
      await journey.restore();
      values['SIMS_ANDROID_PHYSICAL_DEVICE_ID'] = 'emulator-4004';
      expect(create, throwsStateError);
      values.remove('SIMS_ANDROID_PHYSICAL_DEVICE_ID');
      values['SIMS_ANDROID_EMULATOR_FOURTH_DEVICE_ID'] = 'emulator-4004';
      expect(create, throwsStateError);
    },
  );

  test(
    'SE41 uses its explicit emulator without changing the shared pair topology',
    () {
      final values = environment()
        ..['SIMS_ANDROID_EMULATOR_FOURTH_DEVICE_ID'] = 'emulator-4004';
      final (apk, digest) = prepared(productionUpdateCheckAndroidProfile);
      values['SIMS_ARTIFACT_ANDROID_E2E_PRODUCTION_CALL_LOCAL'] = apk.path;
      values['SIMS_ARTIFACT_SHA256'] = digest;
      ProductionAndroidJourney create([String scenario = 'kx0020']) =>
          ProductionAndroidJourney.fromEnvironment(
            scenario,
            temporary,
            environment: values,
            runner: _IdleDevices(),
          );
      final journey = create();
      expect(values, isNot(contains('SIMS_DISPOSABLE_ANDROID_JOURNEYS')));
      expect(journey.disposableAndroidJourneys, isTrue);
      expect(journey.actors, hasLength(1));
      expect(journey.alice.device, emulator);
      expect(journey.alice.packageName, productionUpdateCheckAndroidPackage);
      expect(journey.profileId, productionUpdateCheckAndroidProfile);
      expect(journey.artifact.path, apk.path);
      expect(() => create('kx0028'), throwsArgumentError);
      values.remove('SIMS_ANDROID_EMULATOR_DEVICE_ID');
      expect(create, throwsStateError);
      values['SIMS_ANDROID_EMULATOR_DEVICE_ID'] = physical;
      expect(create, throwsStateError);
    },
  );

  test(
    'TestFlight selection needs only one explicitly disposable simulator',
    () {
      final bundle = Directory(
        '${cache.path}/ios.simulator.app/$input/Runner.app',
      )..createSync(recursive: true);
      File(
        '${bundle.path}/fixture',
      ).writeAsStringSync('synthetic simulator bundle');
      final digest = sha256
          .convert(simsPreparedArtifactDigestBytes(bundle))
          .toString();
      File('${bundle.parent.path}/attestation.json').writeAsStringSync(
        jsonEncode({
          'schemaVersion': 1,
          'profileId': 'ios.simulator.app',
          'inputDigest': input,
          'artifactDigest': digest,
          'artifactPath': bundle.path,
          'redactedCommand': <String>[],
          'createdAt': DateTime.utc(2026).toIso8601String(),
        }),
      );
      const simulator = '11111111-1111-4111-8111-111111111111';
      final values = {
        'SIMS_CACHE_DIR': cache.path,
        'SIMS_ARTIFACT_IOS_SIMULATOR_APP': bundle.path,
        'SIMS_ARTIFACT_INPUT_DIGEST': input,
        'SIMS_ARTIFACT_SHA256': digest,
        'SIMS_IOS_SIMULATOR_A_DEVICE_ID': simulator,
        'SIMS_IOS_DISPOSABLE_SIMULATOR_IDS': simulator,
      };
      ProductionIosSimulatorJourney create() =>
          ProductionIosSimulatorJourney.fromEnvironment(
            'kx0028',
            temporary,
            environment: values,
            runner: _IdleDevices(),
          );
      final journey = create();
      expect(journey.actors, hasLength(1));
      expect(journey.alice.invocation.role, 'alice');
      expect(journey.alice.device, simulator);
      values.remove('SIMS_IOS_DISPOSABLE_SIMULATOR_IDS');
      expect(create, throwsStateError);
    },
  );

  test(
    'contact deletion uses its explicit emulator without a global pair flag',
    () {
      final values = environment();
      ProductionAndroidJourney create(String id) =>
          ProductionAndroidJourney.fromEnvironment(
            id,
            temporary,
            environment: values,
            runner: _IdleDevices(),
          );
      for (final id in ['kx0010', 'kx0011', 'kx0012', 'kx0013', 'kx0014']) {
        final journey = create(id);
        expect(journey.disposableAndroidJourneys, isTrue);
        expect(journey.actors, hasLength(1));
        expect(journey.alice.device, emulator);
        expect(journey.profileId, productionJourneyAndroidProfile);
        expect(journey.alice.packageName, productionJourneyAndroidPackage);
      }
      values.remove('SIMS_ANDROID_EMULATOR_DEVICE_ID');
      expect(() => create('kx0010'), throwsStateError);
      values['SIMS_ANDROID_EMULATOR_DEVICE_ID'] = physical;
      expect(() => create('kx0010'), throwsStateError);
    },
  );

  test(
    'pair journeys keep the physical and emulator pins without the flag',
    () {
      final values = environment()
        ..['SIMS_ANDROID_EMULATOR_FOURTH_DEVICE_ID'] = 'emulator-4004';
      final journey = ProductionAndroidJourney.fromEnvironment(
        'production.routing_smoke',
        temporary,
        environment: values,
      );
      expect(journey.disposableAndroidJourneys, isFalse);
      expect(journey.alice.device, physical);
      expect(journey.bob.device, emulator);
      expect(journey.actors, hasLength(2));
    },
  );

  test('emulator-only pairs still require the explicit global flag', () {
    final values = environment()
      ..remove('SIMS_ANDROID_PHYSICAL_DEVICE_ID')
      ..['SIMS_ANDROID_EMULATOR_FOURTH_DEVICE_ID'] = 'emulator-4004';
    ProductionAndroidJourney create() =>
        ProductionAndroidJourney.fromEnvironment(
          'production.routing_smoke',
          temporary,
          environment: values,
        );
    expect(create, throwsStateError);
    values['SIMS_DISPOSABLE_ANDROID_JOURNEYS'] = '0';
    expect(create, throwsStateError);
    values['SIMS_ANDROID_PHYSICAL_DEVICE_ID'] = 'emulator-4004';
    expect(create, throwsStateError);
    values['SIMS_DISPOSABLE_ANDROID_JOURNEYS'] = '1';
    final journey = create();
    expect(journey.alice.device, 'emulator-4004');
    expect(journey.bob.device, emulator);
  });

  test(
    'single fixtures verify emulator transport before capturing app state',
    () async {
      for (final scenario in ['kx0020', 'kx0010']) {
        final values = environment();
        if (scenario == 'kx0020') {
          final (apk, digest) = prepared(productionUpdateCheckAndroidProfile);
          values['SIMS_ARTIFACT_ANDROID_E2E_PRODUCTION_CALL_LOCAL'] = apk.path;
          values['SIMS_ARTIFACT_SHA256'] = digest;
        }
        var captured = false;
        final journey = ProductionAndroidJourney.fromEnvironment(
          scenario,
          temporary,
          environment: values,
          runner: _IdleDevices(),
          captureGuard:
              ({
                required devices,
                required packageName,
                required backupLabel,
                required preparedArtifact,
                required expectedArtifactSha256,
              }) async {
                captured = true;
                throw StateError('must not capture');
              },
        );
        await expectLater(journey.prepare(), throwsStateError);
        expect(captured, isFalse);
      }
    },
  );

  test(
    'disposable journeys bind two explicit emulators without a phone alias',
    () {
      final values = environment()
        ..remove('SIMS_ANDROID_PHYSICAL_DEVICE_ID')
        ..['SIMS_DISPOSABLE_ANDROID_JOURNEYS'] = '1'
        ..['SIMS_ANDROID_EMULATOR_FOURTH_DEVICE_ID'] = 'emulator-4004';
      final journey = ProductionAndroidJourney.fromEnvironment(
        'production.routing_smoke',
        temporary,
        environment: values,
      );
      expect(journey.alice.device, 'emulator-4004');
      expect(journey.bob.device, emulator);
      expect(journey.actors, hasLength(2));
      values['SIMS_ANDROID_EMULATOR_FOURTH_DEVICE_ID'] = emulator;
      expect(
        () => ProductionAndroidJourney.fromEnvironment(
          'production.routing_smoke',
          temporary,
          environment: values,
        ),
        throwsStateError,
      );
      values['SIMS_ANDROID_EMULATOR_FOURTH_DEVICE_ID'] = physical;
      expect(
        () => ProductionAndroidJourney.fromEnvironment(
          'production.routing_smoke',
          temporary,
          environment: values,
        ),
        throwsStateError,
      );
    },
  );

  test(
    'disposable mode rejects a physical transport before guard capture',
    () async {
      final values = environment()
        ..['SIMS_DISPOSABLE_ANDROID_JOURNEYS'] = '1'
        ..['SIMS_ANDROID_EMULATOR_FOURTH_DEVICE_ID'] = 'emulator-4004';
      var captured = false;
      final journey = ProductionAndroidJourney.fromEnvironment(
        'production.routing_smoke',
        temporary,
        environment: values,
        runner: _IdleDevices(),
        captureGuard:
            ({
              required devices,
              required packageName,
              required backupLabel,
              required preparedArtifact,
              required expectedArtifactSha256,
            }) async {
              captured = true;
              throw StateError('must not capture');
            },
      );
      await expectLater(journey.prepare(), throwsStateError);
      expect(captured, isFalse);
    },
  );

  test(
    'both packages are captured before either peer install mutates state',
    () async {
      final events = <String>[];
      final journey = ProductionAndroidJourney.fromEnvironment(
        'production.notification_open',
        temporary,
        environment: environment(),
        runner: _IdleDevices(),
        captureGuard:
            ({
              required devices,
              required packageName,
              required backupLabel,
              required preparedArtifact,
              required expectedArtifactSha256,
            }) async {
              events.add('capture:$packageName:${devices.single}');
              expect(
                sha256.convert(preparedArtifact.readAsBytesSync()).toString(),
                expectedArtifactSha256,
              );
              return _Guard(
                packageName,
                events,
                failInstall:
                    packageName == productionNotificationAndroidPackage,
              );
            },
      );
      expect(journey.alice.invocation.profileId, primary);
      expect(journey.bob.invocation.profileId, receiver);
      expect(journey.alice.packageName, productionJourneyAndroidPackage);
      expect(journey.bob.packageName, productionNotificationAndroidPackage);
      await expectLater(journey.prepare(), throwsStateError);
      expect(events.take(2), [
        'capture:$productionJourneyAndroidPackage:$physical',
        'capture:$productionNotificationAndroidPackage:$emulator',
      ]);
      expect(events.where((e) => e.startsWith('install:')).length, 2);
      await journey.restore();
      expect(events.sublist(events.length - 2), [
        'restore:$productionNotificationAndroidPackage',
        'restore:$productionJourneyAndroidPackage',
      ]);
      final cleanup =
          jsonDecode(File('${temporary.path}/cleanup.json').readAsStringSync())
              as Map;
      expect(cleanup['status'], 'PASS');
      expect(cleanup['packagesByDevice'], {
        physical: productionJourneyAndroidPackage,
        emulator: productionNotificationAndroidPackage,
      });
    },
  );

  test('a failed first cleanup still attempts the other owned peer', () async {
    final events = <String>[];
    final journey = ProductionAndroidJourney.fromEnvironment(
      'production.notification_sound',
      temporary,
      environment: environment(),
      runner: _IdleDevices(),
      captureGuard:
          ({
            required devices,
            required packageName,
            required backupLabel,
            required preparedArtifact,
            required expectedArtifactSha256,
          }) async {
            events.add('capture:$packageName');
            return _Guard(
              packageName,
              events,
              failInstall: true,
              failRestore: packageName == productionNotificationAndroidPackage,
            );
          },
    );
    await expectLater(journey.prepare(), throwsStateError);
    await expectLater(journey.restore(), throwsStateError);
    expect(
      events,
      containsAllInOrder([
        'restore:$productionNotificationAndroidPackage',
        'restore:$productionJourneyAndroidPackage',
      ]),
    );
    final cleanup =
        jsonDecode(File('${temporary.path}/cleanup.json').readAsStringSync())
            as Map;
    expect(cleanup['status'], 'FAIL');
    expect(cleanup['exactRestorationVerified'], isFalse);
  });
}
