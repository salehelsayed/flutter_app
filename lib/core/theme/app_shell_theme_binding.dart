import 'package:flutter/material.dart';
import 'package:flutter_app/features/feed/application/app_shell_controller.dart';
import 'package:flutter_app/features/settings/domain/models/background_preference.dart';

/// 248 — binds the root [MaterialApp]'s [ThemeMode] to the live
/// [AppShellController] background preference so selecting Signal switches the
/// whole app (root ThemeData, pushed routes, modals) to light, while every dark
/// wallpaper keeps the dark root.
///
/// Only [AppShellChangeKind.background] notifications rebuild the theme, and
/// only when the *resolved* mode actually changes, so tab / identity /
/// media-quality events never rebuild the root Material config (TC-248-04). The
/// listener follows controller replacement (didUpdateWidget) and detaches on
/// dispose (TC-248-05).
class AppShellThemeBinding extends StatefulWidget {
  final AppShellController controller;
  final Widget Function(BuildContext context, ThemeMode themeMode) builder;

  const AppShellThemeBinding({
    super.key,
    required this.controller,
    required this.builder,
  });

  /// Signal ([BackgroundPreference.daylightLagoon]) is the only light wallpaper;
  /// Default / Cosmic / Aurora all resolve to a dark root.
  static ThemeMode themeModeFor(BackgroundPreference preference) {
    return preference == BackgroundPreference.daylightLagoon
        ? ThemeMode.light
        : ThemeMode.dark;
  }

  @override
  State<AppShellThemeBinding> createState() => _AppShellThemeBindingState();
}

class _AppShellThemeBindingState extends State<AppShellThemeBinding> {
  late ThemeMode _themeMode;

  @override
  void initState() {
    super.initState();
    _themeMode = AppShellThemeBinding.themeModeFor(
      widget.controller.backgroundPreference,
    );
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void didUpdateWidget(covariant AppShellThemeBinding oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
      // Re-resolve against the newly-followed controller.
      _syncMode();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    // Only a background change can move the root mode; tab / identity /
    // media-quality notifications are ignored (TC-248-04).
    if (widget.controller.lastChangeKind != AppShellChangeKind.background) {
      return;
    }
    _syncMode();
  }

  void _syncMode() {
    final next = AppShellThemeBinding.themeModeFor(
      widget.controller.backgroundPreference,
    );
    // Same resolved mode (e.g. Cosmic → Aurora, both dark) must not rebuild.
    if (next == _themeMode) {
      return;
    }
    setState(() => _themeMode = next);
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(context, _themeMode);
  }
}
