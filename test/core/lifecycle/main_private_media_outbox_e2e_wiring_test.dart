import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'bootstrap and app root share one composition-owned outbox controller',
    () {
      final productionSource = File(
        'lib/app/bootstrap/production_application_bootstrap.dart',
      ).readAsStringSync();
      final applicationRootSource = File(
        'lib/app/application_root.dart',
      ).readAsStringSync();
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
        productionSource,
        matches(
          RegExp(
            r'debugE2EComposition\s*'
            r'\?\.\s*initializePrivateMediaController\s*\(',
          ),
        ),
      );
      expect(
        productionSource,
        isNot(contains('PrivateMediaOutboxE2EController(')),
        reason:
            'the production bootstrap must retain only the nullable handoff',
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
        ).allMatches(productionSource),
        hasLength(1),
        reason:
            'the bootstrap must pass the one debug-root-owned controller into '
            'MyApp exactly once',
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
        applicationRootSource,
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
        applicationRootSource,
        contains(
          'privateMediaOutboxE2EController:\n'
          '              widget.privateMediaOutboxE2EController,',
        ),
        reason: 'ordinary direct-conversation routes share the gated endpoint',
      );
    },
  );
}
