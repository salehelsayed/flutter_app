import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/feed/application/app_shell_controller.dart';
import 'package:flutter_app/features/feed/domain/models/app_shell_tab.dart';
import 'package:flutter_app/features/settings/domain/models/background_preference.dart';

void main() {
  test('defaults to orbit and accepts feed as a first-class tab', () {
    // 214: Orbit is the main screen — a bare-constructed controller must land
    // every surface (cold start, post-scan, post-accept) on the Orbit pane.
    final controller = AppShellController();
    addTearDown(controller.dispose);

    expect(controller.activeTab, AppShellTab.orbit);

    controller.switchTo(AppShellTab.feed);

    expect(controller.activeTab, AppShellTab.feed);
  });

  test(
    '214: invalid initial tab ids coerce to orbit; explicit feed honored',
    () {
      final coerced = AppShellController(initialTab: 'not-a-tab');
      addTearDown(coerced.dispose);
      expect(coerced.activeTab, AppShellTab.orbit);

      final explicitFeed = AppShellController(initialTab: AppShellTab.feed);
      addTearDown(explicitFeed.dispose);
      expect(explicitFeed.activeTab, AppShellTab.feed);
    },
  );

  test('ignores invalid tab ids and duplicate switches', () {
    final controller = AppShellController(initialTab: AppShellTab.orbit);
    addTearDown(controller.dispose);

    var notifications = 0;
    controller.addListener(() => notifications++);

    controller.switchTo(AppShellTab.orbit);
    controller.switchTo('not-a-tab');
    controller.switchTo(AppShellTab.feed);

    expect(controller.activeTab, AppShellTab.feed);
    expect(notifications, 1);
  });

  test('defaults background preference and notifies on real changes', () {
    final controller = AppShellController();
    addTearDown(controller.dispose);

    var notifications = 0;
    controller.addListener(() => notifications++);

    expect(
      controller.backgroundPreference,
      BackgroundPreference.defaultBackground,
    );

    controller.setBackgroundPreference(BackgroundPreference.defaultBackground);
    expect(notifications, 0);

    controller.setBackgroundPreference(BackgroundPreference.cosmic);

    expect(controller.backgroundPreference, BackgroundPreference.cosmic);
    expect(notifications, 1);

    controller.setBackgroundPreference(BackgroundPreference.aurora);

    expect(controller.backgroundPreference, BackgroundPreference.aurora);
    expect(notifications, 2);
  });

  test('accepts initial background preference', () {
    final controller = AppShellController(
      initialBackgroundPreference: BackgroundPreference.aurora,
    );
    addTearDown(controller.dispose);

    expect(controller.backgroundPreference, BackgroundPreference.aurora);
  });
}
