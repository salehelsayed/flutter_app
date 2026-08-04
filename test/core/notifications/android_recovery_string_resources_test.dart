import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _recoveryKeys = <String>{
  'dropped_push_recovery_channel_name',
  'dropped_push_recovery_channel_description',
  'dropped_push_recovery_notification_title',
  'dropped_push_recovery_notification_body',
  'dropped_push_recovery_worker_body',
};

Map<String, String> _recoveryStrings(String directory) {
  final file = File('android/app/src/main/res/$directory/strings.xml');
  expect(file.existsSync(), isTrue, reason: '${file.path} must exist');

  final values = <String, String>{};
  for (final match in RegExp(
    r'<string\s+name="([^"]+)">([\s\S]*?)</string>',
  ).allMatches(file.readAsStringSync())) {
    final key = match.group(1)!;
    if (key.startsWith('dropped_push_recovery_')) {
      values[key] = match.group(2)!.trim();
    }
  }
  return values;
}

void main() {
  test('default German and Arabic recovery resources have exact key parity', () {
    final localized = <String, Map<String, String>>{
      for (final directory in const <String>[
        'values',
        'values-de',
        'values-ar',
      ])
        directory: _recoveryStrings(directory),
    };

    for (final entry in localized.entries) {
      expect(
        entry.value.keys,
        unorderedEquals(_recoveryKeys),
        reason: '${entry.key} must define the complete recovery copy contract',
      );
      for (final value in entry.value.values) {
        expect(value, isNotEmpty, reason: '${entry.key} contains blank copy');
      }
    }

    // Android resolves an unsupported locale through the unqualified values/
    // directory, so keeping a complete default table is the fallback contract.
    expect(localized['values']!.keys, unorderedEquals(_recoveryKeys));
  });

  test('native recovery producers resolve copy through Android resources', () {
    final sources = <String>[
      File(
        'android/app/src/main/kotlin/com/mknoon/app/'
        'MknoonFirebaseMessagingService.kt',
      ).readAsStringSync(),
      File(
        'android/app/src/main/kotlin/com/mknoon/app/'
        'HeadlessCanonicalRecoveryWorker.kt',
      ).readAsStringSync(),
    ].join('\n');

    for (final key in _recoveryKeys) {
      expect(
        sources,
        contains('R.string.$key'),
        reason: '$key must be resolved using the active Android locale',
      );
    }

    for (final hardCodedEnglish in const <String>[
      '"Message recovery"',
      '"Alerts when messages may be waiting to be recovered"',
      '"Messages may be waiting"',
      '"Recovering messages"',
    ]) {
      expect(
        sources,
        isNot(contains(hardCodedEnglish)),
        reason: 'recovery copy must not bypass Android resource selection',
      );
    }
  });
}
