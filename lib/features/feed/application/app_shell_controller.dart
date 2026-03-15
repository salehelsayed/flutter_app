import 'package:flutter/foundation.dart';

import 'package:flutter_app/features/feed/domain/models/app_shell_tab.dart';

class AppShellController extends ChangeNotifier {
  String _activeTab;

  AppShellController({String initialTab = AppShellTab.feed})
    : _activeTab = AppShellTab.isValid(initialTab)
          ? initialTab
          : AppShellTab.feed;

  String get activeTab => _activeTab;

  void switchTo(String tab) {
    if (!AppShellTab.isValid(tab) || _activeTab == tab) {
      return;
    }
    _activeTab = tab;
    notifyListeners();
  }
}
