import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/feed/application/app_shell_controller.dart';
import 'package:flutter_app/features/feed/domain/models/app_shell_tab.dart';

void main() {
  test('defaults to feed and accepts orbit as a first-class tab', () {
    final controller = AppShellController();
    addTearDown(controller.dispose);

    expect(controller.activeTab, AppShellTab.feed);

    controller.switchTo(AppShellTab.orbit);

    expect(controller.activeTab, AppShellTab.orbit);
  });

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
}
