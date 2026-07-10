import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'egress sources stay behind service and import no transport or database writers',
    () {
      final files = Directory('lib/core/media')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.contains('received_media_egress'));
      final forbidden = RegExp(
        r'(P2PService|GoBridge|relay|inbox|database_helper|Repository)',
      );
      expect(files, isNotEmpty);
      for (final file in files) {
        expect(
          file.readAsStringSync(),
          isNot(matches(forbidden)),
          reason: file.path,
        );
      }
      final android = File(
        'android/app/src/main/kotlin/com/mknoon/app/MainActivity.kt',
      ).readAsStringSync();
      final ios = File('ios/Runner/AppDelegate.swift').readAsStringSync();
      expect(
        RegExp(
          r'ReceivedMediaEgress[^\n]*(register|Handler|Coordinator)',
          caseSensitive: false,
        ).hasMatch('$android\n$ios'),
        isTrue,
      );
      final iosCoordinator = File(
        'ios/Runner/ReceivedMediaEgressCoordinator.swift',
      ).readAsStringSync();
      expect(iosCoordinator, contains('forExporting: urls, asCopy: true'));
      expect(iosCoordinator, isNot(contains('.moveToService')));
      expect(
        iosCoordinator,
        contains('guard !completed else { return false }'),
      );
      expect(iosCoordinator, contains('completed = true'));
    },
  );
}
