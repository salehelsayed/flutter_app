import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'main shares the one composition-owned private-media outbox controller',
    () {
      final source = File('lib/main.dart').readAsStringSync();
      final compositionSource = File(
        'lib/debug/debug_e2e_composition_root.dart',
      ).readAsStringSync();
      expect(
        compositionSource,
        matches(
          RegExp(
            r'_privateMediaOutboxE2EController\s*\?\?=\s*'
            r'PrivateMediaOutboxE2EController\s*\(',
          ),
        ),
      );
      expect(
        compositionSource,
        contains('enabled: activation.isDebugMode && activation.e2eTestMode'),
      );
      expect(
        source,
        matches(
          RegExp(
            r'debugE2EComposition\s*'
            r'\?\.\s*initializePrivateMediaController\s*\(',
          ),
        ),
      );
      expect(
        source,
        isNot(contains('PrivateMediaOutboxE2EController(')),
        reason: 'production main must retain only the nullable phase handoff',
      );
      expect(
        compositionSource,
        contains('privateMediaOutboxE2EController:'),
        reason: 'the root-owned controller must reach the intro poller',
      );
      expect(
        RegExp(
          r'privateMediaOutboxE2EController:\s*'
          r'privateMediaOutboxE2EController',
        ).allMatches(source),
        hasLength(1),
        reason:
            'main must pass the one root-owned controller into MyApp exactly '
            'once',
      );
      expect(
        RegExp(
          r'privateMediaOutboxE2EController:\s*'
          r'privateMediaOutboxE2EController',
        ).allMatches(compositionSource),
        hasLength(2),
        reason:
            'the root-owned controller must reach the intro poller and its '
            'config-opened ConversationWired route',
      );
      expect(
        source,
        contains(
          'final PrivateMediaOutboxE2EController? '
          'privateMediaOutboxE2EController;',
        ),
      );
      expect(
        compositionSource,
        matches(
          RegExp(
            r'privateMediaOutboxE2EController:\s*'
            r'privateMediaOutboxE2EController',
          ),
        ),
        reason:
            'the SIMS launcher must mount the production conversation endpoint',
      );
      expect(
        source,
        contains(
          'privateMediaOutboxE2EController:\n'
          '              widget.privateMediaOutboxE2EController,',
        ),
        reason: 'ordinary direct-conversation routes share the gated endpoint',
      );
    },
  );
}
