import 'package:flutter_app/features/feed/application/app_shell_controller.dart';
import 'package:flutter_app/features/feed/domain/models/app_shell_tab.dart';
import 'package:flutter_app/features/settings/domain/models/background_preference.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppShellController change-kind discrimination (163)', () {
    test(
      'TC-163-01: setBackgroundPreference and switchTo notify DISTINCT change kinds',
      () {
        final controller = AppShellController();
        final kinds = <AppShellChangeKind>[];
        controller.addListener(() => kinds.add(controller.lastChangeKind));

        // A tab change signals a TAB kind only.
        controller.switchTo(AppShellTab.orbit);
        expect(kinds, [AppShellChangeKind.tab]);
        expect(kinds.contains(AppShellChangeKind.background), isFalse);

        // A background change signals a BACKGROUND kind only.
        controller.setBackgroundPreference(BackgroundPreference.cosmic);
        expect(kinds, [
          AppShellChangeKind.tab,
          AppShellChangeKind.background,
        ]);

        // No-op guards fire nothing: same tab, same preference → no notify.
        controller.switchTo(AppShellTab.orbit);
        controller.setBackgroundPreference(BackgroundPreference.cosmic);
        expect(kinds, [
          AppShellChangeKind.tab,
          AppShellChangeKind.background,
        ]);

        // The inverse routing also holds: a second tab change is a TAB kind.
        controller.switchTo(AppShellTab.feed);
        expect(kinds.last, AppShellChangeKind.tab);
      },
    );

    test('notifyIdentityChanged sets kind + notifies', () {
      final controller = AppShellController();
      final kinds = <AppShellChangeKind>[];
      controller.addListener(() => kinds.add(controller.lastChangeKind));

      controller.notifyIdentityChanged();

      expect(kinds, [AppShellChangeKind.identity]);
      expect(controller.lastChangeKind, AppShellChangeKind.identity);
      // Distinct from the pre-206 kinds.
      expect(controller.lastChangeKind, isNot(AppShellChangeKind.tab));
      expect(controller.lastChangeKind, isNot(AppShellChangeKind.background));
    });

    test('notifyMediaQualityChanged sets kind + notifies', () {
      final controller = AppShellController();
      final kinds = <AppShellChangeKind>[];
      controller.addListener(() => kinds.add(controller.lastChangeKind));

      controller.notifyMediaQualityChanged();

      expect(kinds, [AppShellChangeKind.mediaQuality]);
      expect(controller.lastChangeKind, AppShellChangeKind.mediaQuality);
      expect(controller.lastChangeKind, isNot(AppShellChangeKind.identity));
    });
  });
}
