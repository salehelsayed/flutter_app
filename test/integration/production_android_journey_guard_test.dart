import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/support/android_app_state_guard.dart';
import '../../integration_test/support/production_android_journey.dart';

final class _IdleDevices implements AndroidHostProcessRunner {
  @override
  Future<ProcessResult> run(String executable, List<String> arguments) async {
    expect(executable, 'adb');
    expect(arguments.first, '-s');
    expect(arguments[1], anyOf('21071FDF600CSC', 'emulator-5556'));
    expect(arguments, isNot(contains('start')));
    return ProcessResult(0, 0, arguments.contains('get-state') ? 'device\n' : '', '');
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
  const primary = 'android.e2e.main';
  const receiver = 'android.production_fcm.journey';
  const physical = '21071FDF600CSC';
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
      'SIMS_ARTIFACT_ANDROID_E2E_MAIN': sender.path,
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
