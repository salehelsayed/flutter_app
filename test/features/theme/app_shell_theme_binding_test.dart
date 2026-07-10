import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/app_shell_theme_binding.dart';
import 'package:flutter_app/core/theme/app_theme.dart';
import 'package:flutter_app/features/feed/application/app_shell_controller.dart';
import 'package:flutter_app/features/feed/domain/models/app_shell_tab.dart';
import 'package:flutter_app/features/settings/application/background_preference_use_cases.dart';
import 'package:flutter_app/features/settings/domain/models/background_preference.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../core/secure_storage/fake_secure_key_store.dart';

void main() {
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

  testWidgets(
    'initial controller preference maps Signal to light and every dark preset '
    'to dark',
    (tester) async {
      const expected = <BackgroundPreference, Brightness>{
        BackgroundPreference.defaultBackground: Brightness.dark,
        BackgroundPreference.cosmic: Brightness.dark,
        BackgroundPreference.aurora: Brightness.dark,
        BackgroundPreference.daylightLagoon: Brightness.light,
      };

      for (final entry in expected.entries) {
        final controller = AppShellController(
          initialBackgroundPreference: entry.key,
        );
        final probeKey = GlobalKey<_ProbeState>();
        await tester.pumpWidget(buildApp(controller, probeKey: probeKey));
        await tester.pumpAndSettle();

        expect(
          probeKey.currentState!.observedBrightness,
          entry.value,
          reason: '${entry.key} should map to ${entry.value}',
        );

        // Fully unmount before the next case so each mount is a fresh initState.
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
      }
    },
  );

  testWidgets(
    'background notification switches root brightness live and preserves '
    'child state',
    (tester) async {
      final controller = AppShellController(
        initialBackgroundPreference: BackgroundPreference.defaultBackground,
      );
      final probeKey = GlobalKey<_ProbeState>();
      await tester.pumpWidget(buildApp(controller, probeKey: probeKey));
      await tester.pumpAndSettle();

      expect(probeKey.currentState!.observedBrightness, Brightness.dark);

      // Mutate keyed child state so a remount (not a rebuild) is detectable.
      probeKey.currentState!.counter = 7;

      // dark → Signal light.
      controller.setBackgroundPreference(BackgroundPreference.daylightLagoon);
      await tester.pumpAndSettle();
      expect(probeKey.currentState!.observedBrightness, Brightness.light);
      expect(
        probeKey.currentState!.counter,
        7,
        reason: 'child state must survive the mode flip (no remount)',
      );

      // Signal → dark again (two flips on one mount).
      controller.setBackgroundPreference(BackgroundPreference.aurora);
      await tester.pumpAndSettle();
      expect(probeKey.currentState!.observedBrightness, Brightness.dark);
      expect(probeKey.currentState!.counter, 7);

      controller.dispose();
    },
  );

  testWidgets('non-background shell events do not rebuild theme builder', (
    tester,
  ) async {
    final controller = AppShellController(
      initialTab: AppShellTab.feed,
      initialBackgroundPreference: BackgroundPreference.daylightLagoon,
    );
    var themeBuilds = 0;
    await tester.pumpWidget(
      buildApp(controller, onThemeBuild: () => themeBuilds++),
    );
    await tester.pumpAndSettle();
    expect(themeBuilds, 1);

    // Real (non-background) notifications must NOT rebuild the root theme.
    controller.switchTo(AppShellTab.orbit);
    await tester.pump();
    controller.notifyIdentityChanged();
    await tester.pump();
    controller.notifyMediaQualityChanged();
    await tester.pump();
    expect(
      themeBuilds,
      1,
      reason: 'tab / identity / media-quality must not rebuild the root theme',
    );

    // A real mode-changing background event DOES rebuild.
    controller.setBackgroundPreference(BackgroundPreference.aurora);
    await tester.pumpAndSettle();
    expect(themeBuilds, 2);

    // Same resolved mode (Aurora → Cosmic, both dark) must NOT rebuild.
    controller.setBackgroundPreference(BackgroundPreference.cosmic);
    await tester.pumpAndSettle();
    expect(
      themeBuilds,
      2,
      reason: 'same resolved mode must not rebuild the theme',
    );

    // Back to Signal light — a real mode change rebuilds again.
    controller.setBackgroundPreference(BackgroundPreference.daylightLagoon);
    await tester.pumpAndSettle();
    expect(themeBuilds, 3);

    controller.dispose();
  });

  testWidgets(
    'binding swaps and disposes controller listeners without stale updates',
    (tester) async {
      final oldController = AppShellController(
        initialBackgroundPreference: BackgroundPreference.defaultBackground,
      );
      final newController = AppShellController(
        initialBackgroundPreference: BackgroundPreference.defaultBackground,
      );
      final probeKey = GlobalKey<_ProbeState>();

      await tester.pumpWidget(buildApp(oldController, probeKey: probeKey));
      await tester.pumpAndSettle();
      expect(probeKey.currentState!.observedBrightness, Brightness.dark);

      // Swap the controller the binding follows.
      await tester.pumpWidget(buildApp(newController, probeKey: probeKey));
      await tester.pumpAndSettle();

      // Old controller is detached: its changes must not move the root mode.
      oldController.setBackgroundPreference(
        BackgroundPreference.daylightLagoon,
      );
      await tester.pumpAndSettle();
      expect(
        probeKey.currentState!.observedBrightness,
        Brightness.dark,
        reason: 'old controller must be detached after swap',
      );

      // New controller drives the mode.
      newController.setBackgroundPreference(
        BackgroundPreference.daylightLagoon,
      );
      await tester.pumpAndSettle();
      expect(
        probeKey.currentState!.observedBrightness,
        Brightness.light,
        reason: 'new controller must be attached after swap',
      );

      // Unmount, then notify both: no setState-after-dispose may be thrown.
      await tester.pumpWidget(const SizedBox());
      oldController.setBackgroundPreference(BackgroundPreference.aurora);
      newController.setBackgroundPreference(BackgroundPreference.aurora);
      await tester.pump();

      oldController.dispose();
      newController.dispose();
    },
  );

  testWidgets('stored Signal load drives mounted root light', (tester) async {
    final store = FakeSecureKeyStore();
    await store.write(BackgroundPreference.storageKey, 'daylight_lagoon');

    // Mount initially dark (default), exactly like a fresh process.
    final controller = AppShellController();
    final probeKey = GlobalKey<_ProbeState>();
    await tester.pumpWidget(buildApp(controller, probeKey: probeKey));
    await tester.pumpAndSettle();
    expect(probeKey.currentState!.observedBrightness, Brightness.dark);

    // Real load → forward to real controller → binding observes light.
    final loaded = await loadBackgroundPreference(secureKeyStore: store);
    expect(loaded, BackgroundPreference.daylightLagoon);
    controller.setBackgroundPreference(loaded);
    await tester.pumpAndSettle();

    expect(probeKey.currentState!.observedBrightness, Brightness.light);
    controller.dispose();
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

  @override
  Widget build(BuildContext context) {
    observedBrightness = Theme.of(context).brightness;
    return const SizedBox.shrink();
  }
}
