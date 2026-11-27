import 'package:flutter/material.dart';
import 'package:flutter_app/features/feed/application/app_shell_controller.dart';

/// Shares the app-owned motion preference with backgrounds on every route.
class BackgroundMotionScope extends InheritedNotifier<AppShellController> {
  const BackgroundMotionScope({
    super.key,
    required AppShellController controller,
    required super.child,
  }) : super(notifier: controller);

  static bool enabledOf(BuildContext context) {
    return context
            .dependOnInheritedWidgetOfExactType<BackgroundMotionScope>()
            ?.notifier
            ?.backgroundMotionEnabled ??
        true;
  }
}

/// Follows system appearance and shares the independent wallpaper motion setting.
class AppShellThemeBinding extends StatelessWidget {
  final AppShellController controller;
  final Widget Function(BuildContext context, ThemeMode themeMode) builder;

  const AppShellThemeBinding({
    super.key,
    required this.controller,
    required this.builder,
  });

  @override
  Widget build(BuildContext context) {
    return BackgroundMotionScope(
      controller: controller,
      child: builder(context, ThemeMode.system),
    );
  }
}
