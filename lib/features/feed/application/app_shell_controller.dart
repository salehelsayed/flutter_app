import 'package:flutter/foundation.dart';

import 'package:flutter_app/features/feed/domain/models/app_shell_tab.dart';
import 'package:flutter_app/features/settings/domain/models/background_preference.dart';

/// Discriminates what kind of change a single `notifyListeners()` represents,
/// so a listener can react differently to a tab switch vs a background recolor
/// without two separate notifier channels (163: navigation-hangs-2).
enum AppShellChangeKind { tab, background }

class AppShellController extends ChangeNotifier {
  String _activeTab;
  BackgroundPreference _backgroundPreference;
  AppShellChangeKind _lastChangeKind = AppShellChangeKind.tab;

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

  /// The kind of the most recent change that fired `notifyListeners()`.
  AppShellChangeKind get lastChangeKind => _lastChangeKind;

  void switchTo(String tab) {
    if (!AppShellTab.isValid(tab) || _activeTab == tab) {
      return;
    }
    _activeTab = tab;
    _lastChangeKind = AppShellChangeKind.tab;
    notifyListeners();
  }

  void setBackgroundPreference(BackgroundPreference preference) {
    if (_backgroundPreference == preference) {
      return;
    }
    _backgroundPreference = preference;
    _lastChangeKind = AppShellChangeKind.background;
    notifyListeners();
  }
}
