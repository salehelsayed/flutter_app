import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'TC-371-06 iOS visibility targets declare exact required-reason APIs',
    () async {
      final runnerManifest = File('ios/Runner/PrivacyInfo.xcprivacy');
      final serviceManifest = File(
        'ios/NotificationService/PrivacyInfo.xcprivacy',
      );
      final project = File('ios/Runner.xcodeproj/project.pbxproj');
      final sharedSource = File(
        'ios/NotificationService/IosAppVisibilitySnapshot.swift',
      );
      final coordinator = File('ios/Runner/IosAppVisibilityCoordinator.swift');

      for (final file in <File>[
        runnerManifest,
        serviceManifest,
        project,
        sharedSource,
        coordinator,
      ]) {
        expect(file.existsSync(), isTrue, reason: file.path);
      }

      for (final manifest in <File>[runnerManifest, serviceManifest]) {
        final lint = await Process.run('plutil', <String>[
          '-lint',
          manifest.path,
        ]);
        expect(lint.exitCode, 0, reason: '${manifest.path}: ${lint.stderr}');
      }

      final runner = runnerManifest.readAsStringSync();
      final service = serviceManifest.readAsStringSync();
      _expectExactEntry(
        runner,
        category: 'NSPrivacyAccessedAPICategorySystemBootTime',
        reason: '35F9.1',
      );
      _expectExactEntry(
        runner,
        category: 'NSPrivacyAccessedAPICategoryDiskSpace',
        reason: 'E174.1',
      );
      _expectExactEntry(
        service,
        category: 'NSPrivacyAccessedAPICategorySystemBootTime',
        reason: '35F9.1',
      );
      _expectExactEntry(
        service,
        category: 'NSPrivacyAccessedAPICategoryFileTimestamp',
        reason: 'C617.1',
      );
      expect(runner, isNot(contains('C617.1')));
      expect(service, isNot(contains('E174.1')));

      final pbx = project.readAsStringSync();
      expect(
        _occurrences(pbx, 'PrivacyInfo.xcprivacy in Resources'),
        2,
        reason: 'one Runner PBXBuildFile declaration plus one phase membership',
      );
      expect(pbx, contains('PBXFileSystemSynchronizedRootGroup section'));
      expect(pbx, contains('path = NotificationService;'));
      expect(pbx, contains('IosAppVisibilitySnapshot.swift in Sources'));
      expect(pbx, contains('IosAppVisibilityCoordinator.swift in Sources'));

      final swift = sharedSource.readAsStringSync();
      expect(swift, contains('ProcessInfo.processInfo.systemUptime'));
      expect(swift, contains('KERN_BOOTTIME'));
      expect(swift, contains('flock('));
      expect(
        swift,
        contains('FileProtectionType.completeUntilFirstUserAuthentication'),
      );
      expect(swift, contains('isExcludedFromBackup = true'));
    },
  );
}

void _expectExactEntry(
  String manifest, {
  required String category,
  required String reason,
}) {
  expect(_occurrences(manifest, category), 1, reason: category);
  expect(_occurrences(manifest, reason), 1, reason: reason);
}

int _occurrences(String source, String needle) =>
    RegExp(RegExp.escape(needle)).allMatches(source).length;
