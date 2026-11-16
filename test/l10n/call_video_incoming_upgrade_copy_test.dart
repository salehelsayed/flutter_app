import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const expected = {
    'en': '{name} wants to turn on video',
    'de': '{name} möchte das Video einschalten',
    'ar': 'طلب تشغيل الفيديو من {name}',
  };
  for (final entry in expected.entries) {
    test('incoming upgrade ${entry.key} has exact named consent copy', () {
      final arb = jsonDecode(
        File('lib/l10n/app_${entry.key}.arb').readAsStringSync(),
      ) as Map<String, dynamic>;
      const key = 'call_video_incoming_upgrade_from';
      // Assert copy before reading metadata: missing behavior is the RED cause,
      // with no dependency on a not-yet-generated localization getter.
      expect(arb[key], entry.value);
      final metadata = arb['@$key'];
      expect(metadata, isA<Map<String, dynamic>>());
      final placeholders = (metadata as Map<String, dynamic>)['placeholders'];
      expect(placeholders, isA<Map<String, dynamic>>());
      final names = placeholders as Map<String, dynamic>;
      expect(names.keys, unorderedEquals(['name']));
      expect(names['name'], containsPair('type', 'String'));
    });
  }
}
