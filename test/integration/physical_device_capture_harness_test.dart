import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/scripts/physical_device_capture_harness.dart';

void main() {
  group('PhysicalDeviceCaptureAdapter', () {
    late Directory temporaryDirectory;

    setUp(() {
      temporaryDirectory = Directory.systemTemp.createTempSync(
        'physical-device-capture-harness-test-',
      );
    });

    tearDown(() {
      if (temporaryDirectory.existsSync()) {
        temporaryDirectory.deleteSync(recursive: true);
      }
    });

    test('builds one pinned capture command before plan arguments', () {
      final driver = File(
        '${temporaryDirectory.path}${Platform.pathSeparator}capture.dart',
      );
      final artifacts = Directory(
        '${temporaryDirectory.path}${Platform.pathSeparator}artifacts',
      );
      final adapter = PhysicalDeviceCaptureAdapter(
        captureDriver: driver,
        scenarioId: 'ios_notification_permission',
        senderDeviceId: 'emulator-5554',
        recipientDeviceId: '00008110-00184D622289801E',
        artifactDirectory: artifacts,
        additionalArguments: const <String>[
          '--staging-manifest',
          '/tmp/staging.json',
          '--no-child-builds',
        ],
      );

      expect(adapter.processArguments, <String>[
        'run',
        driver.absolute.path,
        '--scenario',
        'ios_notification_permission',
        '--sender',
        'emulator-5554',
        '--recipient',
        '00008110-00184D622289801E',
        '--artifact-dir',
        artifacts.path,
        '--staging-manifest',
        '/tmp/staging.json',
        '--no-child-builds',
      ]);
    });

    test('rejects plan arguments that override pinned routing', () {
      expect(
        () => PhysicalDeviceCaptureAdapter(
          captureDriver: File('capture.dart'),
          scenarioId: 'scenario',
          senderDeviceId: 'emulator-5554',
          recipientDeviceId: 'physical-device',
          artifactDirectory: Directory('artifacts'),
          additionalArguments: const <String>['--recipient=someone-else'],
        ),
        throwsArgumentError,
      );
    });

    test('purges all stale verdict shapes without touching other plans', () {
      final artifacts = Directory(
        '${temporaryDirectory.path}${Platform.pathSeparator}artifacts',
      )..createSync(recursive: true);
      final nested = Directory(
        '${artifacts.path}${Platform.pathSeparator}scenario',
      )..createSync(recursive: true);
      final stale = <File>[
        File('${artifacts.path}${Platform.pathSeparator}scenario.json'),
        File(
          '${artifacts.path}${Platform.pathSeparator}'
          'scenario_capture_failure.json',
        ),
        File('${nested.path}${Platform.pathSeparator}scenario.json'),
        File(
          '${nested.path}${Platform.pathSeparator}'
          'scenario_capture_failure.json',
        ),
      ];
      for (final file in stale) {
        file.writeAsStringSync('{}');
      }
      final unrelated = File(
        '${artifacts.path}${Platform.pathSeparator}other-plan.json',
      )..writeAsStringSync('{}');

      purgePhysicalDeviceCaptureArtifacts(artifacts, 'scenario');

      expect(stale.where((file) => file.existsSync()), isEmpty);
      expect(unrelated.existsSync(), isTrue);
    });

    test('resolves direct and nested authoritative artifact layouts', () {
      final artifacts = Directory(
        '${temporaryDirectory.path}${Platform.pathSeparator}artifacts',
      )..createSync(recursive: true);
      final nested = File(
        '${artifacts.path}${Platform.pathSeparator}scenario'
        '${Platform.pathSeparator}scenario.json',
      )..createSync(recursive: true);

      expect(
        physicalDeviceCaptureArtifact(artifacts, 'scenario').path,
        nested.path,
      );

      final direct = File(
        '${artifacts.path}${Platform.pathSeparator}scenario.json',
      )..writeAsStringSync('{}');
      expect(
        physicalDeviceCaptureArtifact(artifacts, 'scenario').path,
        direct.path,
      );
    });
  });
}
