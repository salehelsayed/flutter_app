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
}
