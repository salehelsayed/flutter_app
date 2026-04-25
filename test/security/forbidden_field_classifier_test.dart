import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const forbiddenCanaries = <String>[
    'Alice',
    'Team Chat',
    'Hello secret',
    'Alice: hello',
    'Photo',
    'Voice message',
    'Video',
    'File',
    'Media',
    'GIF',
  ];

  group('push forbidden-field classifier', () {
    test('committed ciphertext fixtures expose only encrypted route data', () {
      final files = <String>[
        'test/features/push/fixtures/one_to_one_text.json',
        'test/features/push/fixtures/group_text.json',
        'test/features/push/frozen_payloads/post_phase1_chat_text.json',
        'test/features/push/frozen_payloads/post_phase1_group_text.json',
      ];

      for (final path in files) {
        final fixture =
            jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
        final routeData = fixture['routeData'] as Map<String, dynamic>;
        final encodedRouteData = jsonEncode(routeData);

        for (final canary in forbiddenCanaries) {
          expect(
            encodedRouteData.contains(canary),
            isFalse,
            reason: '$path routeData leaked forbidden canary "$canary"',
          );
        }
      }
    });

    test('legacy frozen payload records the pre-Phase-1 leak explicitly', () {
      final fixture =
          jsonDecode(
                File(
                  'test/features/push/frozen_payloads/pre_phase1_group_text_legacy.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      final routeData = fixture['routeData'] as Map<String, dynamic>;
      final encodedRouteData = jsonEncode(routeData);

      expect(encodedRouteData, contains('Team Chat'));
      expect(encodedRouteData, contains('Alice: hello'));
    });
  });
}
