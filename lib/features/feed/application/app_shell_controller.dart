import 'package:flutter/foundation.dart';

import 'package:flutter_app/features/feed/domain/models/app_shell_tab.dart';
import 'package:flutter_app/features/settings/domain/models/background_preference.dart';

/// Discriminates what kind of change a single `notifyListeners()` represents,
/// so a listener can react differently to a tab switch vs a background recolor
/// without two separate notifier channels (163: navigation-hangs-2).
///
/// 206 — [identity] / [mediaQuality] let Settings (opened from ANY entry point,
/// including the new Orbit center avatar) push identity/username/avatar and
/// image/video-quality changes to the Feed AND Orbit passively, replacing the
/// Feed-only `.then`-continuation reload the removed header avatar carried.
enum AppShellChangeKind { tab, background, identity, mediaQuality }

/// 214 — Orbit is the main screen: the default (and invalid-id fallback) tab
/// is orbit, so every landing that constructs the controller bare — cold
/// start with contacts, post-QR-scan, post-first-accept — renders the Orbit
/// pane. The tab is deliberately NOT persisted: every process restart lands
/// back on Orbit.
class AppShellController extends ChangeNotifier {
  String _activeTab;
  BackgroundPreference _backgroundPreference;
  AppShellChangeKind _lastChangeKind = AppShellChangeKind.tab;

  AppShellController({
    String initialTab = AppShellTab.orbit,
    BackgroundPreference initialBackgroundPreference =
        BackgroundPreference.defaultBackground,
  }) : _activeTab = AppShellTab.isValid(initialTab)
           ? initialTab
           : AppShellTab.orbit,
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

  /// 206 — the self identity (username / avatar bytes) changed; listeners
  /// reload it. Carries no payload (each listener re-reads its own source), so
  /// it mirrors [setBackgroundPreference] minus the stored value.
  void notifyIdentityChanged() {
    _lastChangeKind = AppShellChangeKind.identity;
    notifyListeners();
  }

  /// 206 — the image/video media-quality preference changed; listeners reload
  /// it so subsequent media sends honor the new preference.
  void notifyMediaQualityChanged() {
    _lastChangeKind = AppShellChangeKind.mediaQuality;
    notifyListeners();
  }
}
