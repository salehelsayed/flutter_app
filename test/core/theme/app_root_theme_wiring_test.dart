import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Source-contract guards. These read the real production source (tests run
/// from the package root) so a refactor that silently drops the root light
/// wiring or the StartupRouter forwarding fails loudly.
void main() {
  test('main root wires AppShellThemeBinding around MaterialApp', () {
    final source = File('lib/main.dart').readAsStringSync();

    expect(
      source.contains('AppShellThemeBinding('),
      isTrue,
      reason: 'root MaterialApp must be wrapped in AppShellThemeBinding',
    );
    expect(
      source.contains('AppTheme.lightTheme'),
      isTrue,
      reason: 'root must supply the warm light theme',
    );
    expect(
      source.contains('AppTheme.darkTheme'),
      isTrue,
      reason: 'root must keep the dark theme as darkTheme',
    );
    expect(
      source.contains('ThemeMode.dark'),
      isFalse,
      reason: 'the fixed ThemeMode.dark pin must be gone; mode is resolved',
    );
  });

  test('StartupRouter forwards loaded background into AppShellController', () {
    final source = File(
      'lib/features/identity/presentation/startup_router.dart',
    ).readAsStringSync();

    expect(source.contains('loadBackgroundPreference('), isTrue);
    expect(
      source.contains(
        'appShellController.setBackgroundPreference(backgroundPreference)',
      ),
      isTrue,
      reason: 'loaded background must be forwarded to the controller',
    );

    // Forwarding stays after the initial share-intent capture await.
    final captureIndex = source.indexOf('initialShareIntentCapture');
    final forwardIndex = source.indexOf(
      'appShellController.setBackgroundPreference(backgroundPreference)',
    );
    expect(captureIndex, greaterThanOrEqualTo(0));
    expect(forwardIndex, greaterThan(captureIndex));
  });
}
