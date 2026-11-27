import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/app_shell_theme_binding.dart';
import 'package:flutter_app/core/theme/app_theme.dart';
import 'package:flutter_app/features/feed/application/app_shell_controller.dart';
import 'package:flutter_app/features/feed/domain/models/app_shell_tab.dart';
import 'package:flutter_app/features/settings/application/background_preference_use_cases.dart';
import 'package:flutter_app/features/settings/domain/models/background_preference.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../core/secure_storage/fake_secure_key_store.dart';

const _deadline = Duration(seconds: 3);

Future<void> _settleTheme(WidgetTester tester) async {
  await tester
      .pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        _deadline,
      )
      .timeout(_deadline);
}

void main() {
  testWidgets('motion scope updates without rebuilding theme or route state', (
    tester,
  ) async {
    final controller = AppShellController();
    addTearDown(controller.dispose);
    final probeKey = GlobalKey<_ProbeState>();
    var themeBuilds = 0;
    await tester
        .pumpWidget(
          AppShellThemeBinding(
            controller: controller,
            builder: (_, _) {
              themeBuilds++;
              return MaterialApp(home: _Probe(key: probeKey));
            },
          ),
        )
        .timeout(_deadline);
    expect(probeKey.currentState!.observedMotionEnabled, isTrue);
    probeKey.currentState!.counter = 9;
    controller.setBackgroundMotionEnabled(false);
    await tester.pump().timeout(_deadline);
    expect(probeKey.currentState!.observedMotionEnabled, isFalse);
    expect(probeKey.currentState!.counter, 9);
    expect(themeBuilds, 1);
    controller.setBackgroundMotionEnabled(true);
    await tester.pump().timeout(_deadline);
    expect(probeKey.currentState!.observedMotionEnabled, isTrue);
    expect(themeBuilds, 1);
  });

  testWidgets('motion scope defaults on without an app controller', (
    tester,
  ) async {
    bool? enabled;
    await tester
        .pumpWidget(
          Builder(
            builder: (context) {
              enabled = BackgroundMotionScope.enabledOf(context);
              return const SizedBox.shrink();
            },
          ),
        )
        .timeout(_deadline);
    expect(enabled, isTrue);
  });

  Widget buildApp(
    AppShellController controller, {
    GlobalKey<_ProbeState>? probeKey,
    VoidCallback? onThemeBuild,
  }) {
    return AppShellThemeBinding(
      controller: controller,
      builder: (context, mode) {
        onThemeBuild?.call();
        return MaterialApp(
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: mode,
          home: _Probe(key: probeKey),
        );
      },
    );
  }

  for (final mode in Brightness.values) {
    for (final wallpaper in BackgroundPreference.values) {
      testWidgets('${wallpaper.name} starts in system ${mode.name}', (
        tester,
      ) async {
        final platform = tester.platformDispatcher;
        addTearDown(platform.clearPlatformBrightnessTestValue);
        platform.platformBrightnessTestValue = mode;
        final controller = AppShellController(
          initialBackgroundPreference: wallpaper,
        );
        addTearDown(controller.dispose);
        final probeKey = GlobalKey<_ProbeState>();

        await tester
            .pumpWidget(buildApp(controller, probeKey: probeKey))
            .timeout(_deadline);

        expect(probeKey.currentState!.observedBrightness, mode);
      });
    }
  }

  testWidgets('live system appearance changes preserve child state', (
    tester,
  ) async {
    final platform = tester.platformDispatcher;
    addTearDown(platform.clearPlatformBrightnessTestValue);
    platform.platformBrightnessTestValue = Brightness.dark;
    final controller = AppShellController();
    addTearDown(controller.dispose);
    final probeKey = GlobalKey<_ProbeState>();
    await tester
        .pumpWidget(buildApp(controller, probeKey: probeKey))
        .timeout(_deadline);

    final originalState = probeKey.currentState!;
    expect(originalState.observedBrightness, Brightness.dark);
    originalState.counter = 7;

    for (final mode in [Brightness.light, Brightness.dark]) {
      platform.platformBrightnessTestValue = mode;
      await _settleTheme(tester);
      expect(probeKey.currentState, same(originalState));
      expect(originalState.observedBrightness, mode);
      expect(originalState.counter, 7);
    }
  });

  testWidgets('wallpaper changes preserve system appearance and child state', (
    tester,
  ) async {
    final platform = tester.platformDispatcher;
    addTearDown(platform.clearPlatformBrightnessTestValue);
    platform.platformBrightnessTestValue = Brightness.dark;
    final controller = AppShellController();
    addTearDown(controller.dispose);
    final probeKey = GlobalKey<_ProbeState>();
    await tester
        .pumpWidget(buildApp(controller, probeKey: probeKey))
        .timeout(_deadline);

    final originalState = probeKey.currentState!;
    for (final wallpaper in BackgroundPreference.values) {
      controller.setBackgroundPreference(wallpaper);
      await _settleTheme(tester);
      expect(controller.backgroundPreference, wallpaper);
      expect(probeKey.currentState, same(originalState));
      expect(originalState.observedBrightness, Brightness.dark);
    }
  });

  testWidgets('unrelated shell events do not rebuild the theme builder', (
    tester,
  ) async {
    final controller = AppShellController(initialTab: AppShellTab.feed);
    addTearDown(controller.dispose);
    var themeBuilds = 0;
    await tester
        .pumpWidget(buildApp(controller, onThemeBuild: () => themeBuilds++))
        .timeout(_deadline);
    expect(themeBuilds, 1);

    controller.switchTo(AppShellTab.orbit);
    await tester.pump().timeout(_deadline);
    controller.notifyIdentityChanged();
    await tester.pump().timeout(_deadline);
    controller.notifyMediaQualityChanged();
    await tester.pump().timeout(_deadline);
    expect(themeBuilds, 1);
  });

  testWidgets('motion scope follows the replacement controller', (
    tester,
  ) async {
    final oldController = AppShellController();
    final newController = AppShellController();
    addTearDown(oldController.dispose);
    addTearDown(newController.dispose);
    final probeKey = GlobalKey<_ProbeState>();

    await tester
        .pumpWidget(buildApp(oldController, probeKey: probeKey))
        .timeout(_deadline);
    expect(probeKey.currentState!.observedMotionEnabled, isTrue);

    await tester
        .pumpWidget(buildApp(newController, probeKey: probeKey))
        .timeout(_deadline);
    oldController.setBackgroundMotionEnabled(false);
    await tester.pump().timeout(_deadline);
    expect(probeKey.currentState!.observedMotionEnabled, isTrue);

    newController.setBackgroundMotionEnabled(false);
    await tester.pump().timeout(_deadline);
    expect(probeKey.currentState!.observedMotionEnabled, isFalse);

    await tester.pumpWidget(const SizedBox()).timeout(_deadline);
    oldController.setBackgroundMotionEnabled(true);
    newController.setBackgroundMotionEnabled(true);
    await tester.pump().timeout(_deadline);
    expect(tester.takeException(), isNull);
  });

  testWidgets('restoring stored Signal keeps the active system appearance', (
    tester,
  ) async {
    final platform = tester.platformDispatcher;
    addTearDown(platform.clearPlatformBrightnessTestValue);
    platform.platformBrightnessTestValue = Brightness.dark;
    final store = FakeSecureKeyStore();
    await store
        .write(BackgroundPreference.storageKey, 'daylight_lagoon')
        .timeout(_deadline);

    final controller = AppShellController();
    addTearDown(controller.dispose);
    final probeKey = GlobalKey<_ProbeState>();
    await tester
        .pumpWidget(buildApp(controller, probeKey: probeKey))
        .timeout(_deadline);
    expect(probeKey.currentState!.observedBrightness, Brightness.dark);

    final loaded = await loadBackgroundPreference(secureKeyStore: store)
        .timeout(_deadline);
    controller.setBackgroundPreference(loaded);
    await _settleTheme(tester);

    expect(
      controller.backgroundPreference,
      BackgroundPreference.daylightLagoon,
    );
    expect(probeKey.currentState!.observedBrightness, Brightness.dark);
  });
}

class _Probe extends StatefulWidget {
  const _Probe({super.key});

  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  int counter = 0;
  Brightness? observedBrightness;
  bool? observedMotionEnabled;

  @override
  Widget build(BuildContext context) {
    observedBrightness = Theme.of(context).brightness;
    observedMotionEnabled = BackgroundMotionScope.enabledOf(context);
    return const SizedBox.shrink();
  }
}
