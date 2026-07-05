import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/feed/application/app_shell_controller.dart';
import 'package:flutter_app/features/feed/domain/models/app_shell_tab.dart';

/// 205 item 7 — permanent re-introduction guard for the deleted Orbit2 / Orbit3
/// `kDebugMode` mock prototypes. The dirs, the `orbit3` shell tab, and the nav
/// bar's Orbit3 coupling are gone for good; `AppShellController` degrades a
/// stale persisted `orbit3` tab to feed.
void main() {
  group('205 prototypes removed', () {
    test('TC-205-09 orbit2 + orbit3 prototype dirs, enum, and nav coupling gone',
        () {
      expect(Directory('lib/features/orbit2').existsSync(), isFalse,
          reason: 'the orbit2 prototype dir must be deleted');
      expect(Directory('lib/features/orbit3').existsSync(), isFalse,
          reason: 'the orbit3 prototype dir must be deleted');

      expect(AppShellTab.values, <String>{'feed', 'orbit'},
          reason: 'the shell tabs collapse to exactly feed + orbit');

      final navBar = File(
        'lib/features/feed/presentation/widgets/feed_navigation_bar.dart',
      ).readAsStringSync();
      expect(navBar, isNot(contains('orbit3')),
          reason: 'no orbit3 coupling remains in the nav bar source');
      expect(navBar, isNot(contains('orbit3_prototype')),
          reason: 'no orbit3_prototype import remains');
    });

    test('TC-205-12 AppShellController degrades a stale orbit3 tab to orbit', () {
      // 214: the invalid-id fallback is orbit (orbit is the main screen).
      final controller = AppShellController(initialTab: 'orbit3');
      expect(controller.activeTab, AppShellTab.orbit,
          reason: 'orbit3 is no longer valid → graceful fallback to orbit');
      expect(AppShellTab.isValid('orbit3'), isFalse);
    });
  });
}
