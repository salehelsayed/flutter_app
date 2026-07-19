import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('main shares one gated private-media outbox controller', () {
    final source = File('lib/main.dart').readAsStringSync();
    const declaration =
        'final privateMediaOutboxE2EController = '
        'PrivateMediaOutboxE2EController(';
    expect(source, contains(declaration));
    expect(source, contains('enabled: kDebugMode && kE2ETestMode'));
    expect(
      RegExp(
        r'privateMediaOutboxE2EController:\s*'
        r'privateMediaOutboxE2EController',
      ).allMatches(source),
      hasLength(greaterThanOrEqualTo(3)),
      reason:
          'the same controller must reach MyApp, the intro poller, and its '
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
      source,
      contains(
        'privateMediaOutboxE2EController:\n'
        '                      privateMediaOutboxE2EController,',
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
  });
}
