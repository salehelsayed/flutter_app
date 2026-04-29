import 'package:flutter/foundation.dart';

import 'package:flutter_app/features/feed/domain/models/app_shell_tab.dart';
import 'package:flutter_app/features/settings/domain/models/background_preference.dart';

class AppShellController extends ChangeNotifier {
  String _activeTab;
  BackgroundPreference _backgroundPreference;

  AppShellController({
    String initialTab = AppShellTab.feed,
    BackgroundPreference initialBackgroundPreference =
        BackgroundPreference.defaultBackground,
  }) : _activeTab = AppShellTab.isValid(initialTab)
           ? initialTab
           : AppShellTab.feed,
       _backgroundPreference = initialBackgroundPreference;

  String get activeTab => _activeTab;
  BackgroundPreference get backgroundPreference => _backgroundPreference;

  void switchTo(String tab) {
    if (!AppShellTab.isValid(tab) || _activeTab == tab) {
      return;
    }
    _activeTab = tab;
    notifyListeners();
  }

  void setBackgroundPreference(BackgroundPreference preference) {
    if (_backgroundPreference == preference) {
      return;
    }
    _backgroundPreference = preference;
    notifyListeners();
  }
}
