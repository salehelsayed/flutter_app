import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../../tool/sims/build_orchestrator.dart';

/// Sims iOS device builds are Hetzner test builds. Each one used to start from
/// an empty DerivedData on the external disk (10.7 to 26.3 min per build).
/// They keep one DerivedData per profile on the internal disk, and wipe it
/// only when the toolchain changes. The path never matches a store, upload or
/// restore build folder.
void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('sims-dd-'));
  tearDown(() => root.deleteSync(recursive: true));

  test('each iOS device profile builds in its own internal-disk folder', () {
    const environment = <String, String>{'HOME': '/Users/tester'};
    expect(
      simsIosTestDerivedDataPath('ios.device.production', environment),
      '/Users/tester/dd-hetzner-test-ios.device.production',
    );
    expect(
      simsIosTestDerivedDataPath('ios.device.group_media_269', environment),
      '/Users/tester/dd-hetzner-test-ios.device.group_media_269',
    );
  });

  test('a build with the same toolchain keeps the previous build state', () {
    final derived = Directory('${root.path}/dd');
    expect(prepareSimsIosTestDerivedData(derived, 'xcode-a flutter-a'), isTrue);
    File('${derived.path}/Build/Intermediates.noindex/warm.o')
      ..createSync(recursive: true)
      ..writeAsStringSync('compiled');

    expect(
      prepareSimsIosTestDerivedData(derived, 'xcode-a flutter-a'),
      isFalse,
      reason: 'same toolchain: reuse',
    );
    expect(
      File('${derived.path}/Build/Intermediates.noindex/warm.o').existsSync(),
      isTrue,
    );
  });

  test('a toolchain change starts the folder empty', () {
    final derived = Directory('${root.path}/dd');
    prepareSimsIosTestDerivedData(derived, 'xcode-a flutter-a');
    File('${derived.path}/Build/Intermediates.noindex/warm.o')
      ..createSync(recursive: true)
      ..writeAsStringSync('compiled');

    expect(prepareSimsIosTestDerivedData(derived, 'xcode-b flutter-a'), isTrue);
    expect(
      File('${derived.path}/Build/Intermediates.noindex/warm.o').existsSync(),
      isFalse,
    );
    expect(
      prepareSimsIosTestDerivedData(derived, 'xcode-b flutter-a'),
      isFalse,
      reason: 'the new toolchain is recorded',
    );
  });

  test('a folder without a toolchain record starts empty', () {
    final derived = Directory('${root.path}/dd')..createSync();
    File('${derived.path}/leftover').writeAsStringSync('unknown');

    expect(prepareSimsIosTestDerivedData(derived, 'xcode-a flutter-a'), isTrue);
    expect(File('${derived.path}/leftover').existsSync(), isFalse);
  });

  test('a fresh bootstrap build in the folder is reused by the first sims '
      'build', () {
    final derived = Directory('${root.path}/dd')..createSync();
    File(
      '${derived.path}/.mknoon-test-toolchain',
    ).writeAsStringSync('Xcode 26.0\n{"frameworkVersion": "3.47.2"}');
    File('${derived.path}/Build/Intermediates.noindex/warm.o')
      ..createSync(recursive: true)
      ..writeAsStringSync('compiled by bootstrap');

    expect(
      prepareSimsIosTestDerivedData(
        derived,
        'sims-key',
        testScriptToolchainKey: () =>
            'Xcode 26.0\n{"frameworkVersion": "3.47.2"}',
      ),
      isFalse,
      reason: 'same Xcode and Flutter as the bootstrap build: reuse',
    );
    expect(
      File('${derived.path}/Build/Intermediates.noindex/warm.o').existsSync(),
      isTrue,
    );
    expect(
      prepareSimsIosTestDerivedData(derived, 'sims-key'),
      isFalse,
      reason: 'the sims record is now written',
    );
  });

  test('a bootstrap build with another toolchain is not reused', () {
    final derived = Directory('${root.path}/dd')..createSync();
    File(
      '${derived.path}/.mknoon-test-toolchain',
    ).writeAsStringSync('Xcode 26.0\n{"frameworkVersion": "3.47.2"}');
    File('${derived.path}/warm.o').writeAsStringSync('old');

    expect(
      prepareSimsIosTestDerivedData(
        derived,
        'sims-key',
        testScriptToolchainKey: () =>
            'Xcode 26.1\n{"frameworkVersion": "3.47.2"}',
      ),
      isTrue,
    );
    expect(File('${derived.path}/warm.o').existsSync(), isFalse);
  });

  test('a failed toolchain probe adopts nothing', () {
    final derived = Directory('${root.path}/dd')..createSync();
    File('${derived.path}/.mknoon-test-toolchain').writeAsStringSync('x');
    File('${derived.path}/warm.o').writeAsStringSync('old');

    expect(
      prepareSimsIosTestDerivedData(
        derived,
        'sims-key',
        testScriptToolchainKey: () => null,
      ),
      isTrue,
    );
    expect(File('${derived.path}/warm.o').existsSync(), isFalse);
  });

  test('the sims key equals the script record when a probe also writes '
      'stderr', () {
    final bin = Directory('${root.path}/bin')..createSync();
    File('${bin.path}/xcodebuild').writeAsStringSync(
      '#!/bin/bash\necho "Xcode 26.0"\necho "Build version 17A1"\n',
    );
    File('${bin.path}/flutter').writeAsStringSync(
      '#!/bin/bash\n'
      'echo "Waiting for another flutter command to release the startup lock..." >&2\n'
      'sleep 0.2\n'
      'echo \'{"frameworkVersion": "3.47.2"}\'\n',
    );
    Process.runSync('chmod', [
      '+x',
      '${bin.path}/xcodebuild',
      '${bin.path}/flutter',
    ]);
    final environment = <String, String>{
      ...Platform.environment,
      'PATH': '${bin.path}:${Platform.environment['PATH']}',
    };
    final derived = '${root.path}/dd-hetzner-test-key';
    final script = Process.runSync('bash', <String>[
      '-c',
      '. docker-ws/test_derived_data.sh && prepare_test_derived_data "\$1"',
      'bash',
      derived,
    ], environment: environment);
    expect(script.exitCode, 0, reason: '${script.stderr}');

    expect(
      simsTestScriptToolchainKey(environment),
      File('$derived/.mknoon-test-toolchain').readAsStringSync(),
    );
  });
}
