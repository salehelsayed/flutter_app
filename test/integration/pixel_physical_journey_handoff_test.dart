import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/support/android_app_state_guard.dart';
import '../../integration_test/support/production_android_journey.dart';

final class _NoDeviceRunner implements AndroidHostProcessRunner {
  int calls = 0;

  @override
  Future<ProcessResult> run(String executable, List<String> arguments) {
    calls++;
    throw StateError(
      'Device/process execution is forbidden in this host test.',
    );
  }
}

Map<String, String> _launcherHandoff(
  Directory fixture, {
  required String disposableJourneys,
}) {
  final cache = Directory('${fixture.path}/cache')..createSync();
  final inputDigest = sha256
      .convert(utf8.encode('synthetic source'))
      .toString();
  const profile = productionJourneyAndroidProfile;
  final apk = File('${cache.path}/$profile/$inputDigest/artifact.apk')
    ..createSync(recursive: true)
    ..writeAsBytesSync(utf8.encode('synthetic host fixture, never installed'));
  final artifactDigest = sha256.convert(apk.readAsBytesSync()).toString();
  File('${apk.parent.path}/attestation.json').writeAsStringSync(
    jsonEncode({
      'schemaVersion': 1,
      'profileId': profile,
      'inputDigest': inputDigest,
      'artifactDigest': artifactDigest,
      'artifactPath': apk.path,
      'redactedCommand': <String>[],
      'createdAt': DateTime.utc(2026).toIso8601String(),
    }),
  );
  // The values docker-ws/run_sims_safe.py --pixel-physical-rows exports.
  return {
    'SIMS_CACHE_DIR': cache.path,
    'SIMS_ARTIFACT_ANDROID_E2E_PRODUCTION': apk.path,
    'SIMS_ARTIFACT_INPUT_DIGEST': inputDigest,
    'SIMS_ARTIFACT_SHA256': artifactDigest,
    'SIMS_ANDROID_PHYSICAL_DEVICE_ID': 'PIXEL00TEST',
    'SIMS_ANDROID_EMULATOR_DEVICE_ID': 'emulator-5554',
    'SIMS_ANDROID_EMULATOR_SECOND_DEVICE_ID': 'emulator-5556',
    'SIMS_ANDROID_EMULATOR_THIRD_DEVICE_ID': 'emulator-5558',
    'MKNOON_PRESERVE_PHYSICAL_APP_DATA': '0',
    'SIMS_DISPOSABLE_ANDROID_JOURNEYS': disposableJourneys,
  };
}

void main() {
  const pixelRows = [
    'production.group_catalog.gm002',
    'production.group_catalog.gm003',
    'production.group_catalog.private_offline_add',
    'production.group_catalog.private_online_add',
  ];

  for (final row in pixelRows) {
    test(
      '$row puts Alice on the pinned Pixel with the opted launcher flags',
      () {
        final fixture = Directory.systemTemp.createTempSync('pixel-handoff-');
        addTearDown(() => fixture.deleteSync(recursive: true));
        final runner = _NoDeviceRunner();
        final journey = ProductionAndroidJourney.fromEnvironment(
          row,
          fixture,
          environment: _launcherHandoff(fixture, disposableJourneys: '0'),
          runner: runner,
        );
        expect(journey.alice.device, 'PIXEL00TEST');
        expect(journey.actors.map((peer) => peer.device).toSet(), {
          'PIXEL00TEST',
          'emulator-5554',
          'emulator-5556',
          'emulator-5558',
        });
        expect(runner.calls, 0);
      },
    );

    test('$row still refuses the Pixel under the emulator-only flag', () {
      final fixture = Directory.systemTemp.createTempSync('pixel-handoff-');
      addTearDown(() => fixture.deleteSync(recursive: true));
      final runner = _NoDeviceRunner();
      expect(
        () => ProductionAndroidJourney.fromEnvironment(
          row,
          fixture,
          environment: _launcherHandoff(fixture, disposableJourneys: '1'),
          runner: runner,
        ),
        throwsA(isA<StateError>()),
      );
      expect(runner.calls, 0);
    });
  }
}
